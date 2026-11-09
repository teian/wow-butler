import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wow_butler/core/models/addon.dart';
import 'package:wow_butler/core/models/app_settings.dart';
import 'package:wow_butler/core/models/game_flavor.dart';
import 'package:wow_butler/core/models/wow_installation.dart';
import 'package:wow_butler/services/addon_service.dart';
import 'package:wow_butler/sources/api_client.dart';
import 'package:wow_butler/sources/curseforge_source.dart';
import 'package:wow_butler/sources/source_registry.dart';

const _cfKey = r'$2a$10$abcdefghijklmnopqrstuvABCDEFGHIJKLMNOPQRSTUV0123456789';

void main() {
  late Directory tmp;
  late WowInstallation inst;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wb-cf-dl');
    inst = WowInstallation(
      id: '0123456789abcdef',
      label: 'Test',
      clientPath: tmp.path,
      clientType: WowClientType.retail,
      flavor: GameFlavor.retail,
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  final remote = RemoteAddon(
    source: AddonSourceId.curseforge,
    externalId: '1',
    name: 'MyAddon',
    releases: [
      AddonRelease(
        id: '100',
        version: '1.0.0',
        channel: ReleaseChannel.stable,
        downloadUrl: 'https://cdn.fallback/MyAddon-1.0.0.zip',
      ),
    ],
  );

  AddonService service(ApiClient api) {
    final settings = AppSettings(
      curseforgeApiKey: _cfKey,
      disabledSources: AddonSourceId.values
          .where((s) => s != AddonSourceId.curseforge)
          .toSet(),
    );
    return AddonService(
      api: api,
      sources: () => SourceRegistry(api, settings),
      defaultChannel: () => ReleaseChannel.stable,
    );
  }

  List<int> addonArchive() => ZipEncoder().encode(
    Archive()..add(ArchiveFile.string('MyAddon/MyAddon.toc', '## Title: A\n')),
  );

  group('AddonService.prepare for CurseForge', () {
    test('downloads with the browser user agent', () async {
      final archiveBytes = addonArchive();
      http.Request? downloadRequest;
      final client = ApiClient(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/download-url')) {
            return http.Response(
              jsonEncode({'data': 'https://cdn.example/MyAddon-1.0.0.zip'}),
              200,
            );
          }
          if (request.url.host == 'cdn.example') {
            downloadRequest = request;
            return http.Response.bytes(archiveBytes, 200);
          }
          return http.Response('not found', 404);
        }),
      );

      final prepared = await service(client).prepare(
        inst,
        remote: remote,
        release: remote.releases.single,
      );
      final result = await service(client).apply(inst, const [], prepared);
      client.close();

      expect(result.single.folders, ['MyAddon']);
      expect(
        downloadRequest!.url.toString(),
        'https://cdn.example/MyAddon-1.0.0.zip',
      );
      expect(downloadRequest!.headers['x-api-key'], _cfKey);
      expect(
        downloadRequest!.headers[HttpHeaders.userAgentHeader],
        CurseForgeSource.browserUserAgent,
      );
    });

    test('retries with the WowUp user agent when the browser is rejected',
        () async {
      final archiveBytes = addonArchive();
      final agents = <String?>[];
      final client = ApiClient(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/download-url')) {
            return http.Response(
              jsonEncode({'data': 'https://cdn.example/MyAddon-1.0.0.zip'}),
              200,
            );
          }
          if (request.url.host == 'cdn.example') {
            final agent = request.headers[HttpHeaders.userAgentHeader];
            agents.add(agent);
            // The CDN rejects anything that is not the WowUp client.
            return agent == CurseForgeSource.wowupCfUserAgent
                ? http.Response.bytes(archiveBytes, 200)
                : http.Response('forbidden', 403);
          }
          return http.Response('not found', 404);
        }),
      );

      final prepared = await service(client).prepare(
        inst,
        remote: remote,
        release: remote.releases.single,
      );
      final result = await service(client).apply(inst, const [], prepared);
      client.close();

      expect(result.single.folders, ['MyAddon']);
      expect(agents, [
        CurseForgeSource.browserUserAgent,
        CurseForgeSource.wowupCfUserAgent,
      ]);
    });
  });
}
