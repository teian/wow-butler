import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wow_butler/core/models/addon.dart';
import 'package:wow_butler/core/models/app_settings.dart';
import 'package:wow_butler/core/models/game_flavor.dart';
import 'package:wow_butler/core/models/wow_installation.dart';
import 'package:wow_butler/core/util/limiter.dart';
import 'package:wow_butler/services/addon_service.dart';
import 'package:wow_butler/sources/api_client.dart';
import 'package:wow_butler/sources/source_registry.dart';

void main() {
  group('Limiter', () {
    test('runs at most limit tasks at once', () async {
      final limiter = Limiter(() => 2);
      var running = 0, peak = 0;
      final gates = List.generate(5, (_) => Completer<void>());
      final done = [
        for (final gate in gates)
          limiter.run(() async {
            running++;
            peak = running > peak ? running : peak;
            await gate.future;
            running--;
          }),
      ];
      await pumpEventQueue();
      expect(running, 2);
      for (final gate in gates) {
        gate.complete();
        await pumpEventQueue();
      }
      await Future.wait(done);
      expect(peak, 2);
      expect(limiter.running, 0);
    });

    test('a failing task frees its slot', () async {
      final limiter = Limiter(() => 1);
      await expectLater(
        limiter.run<void>(() async => throw StateError('x')),
        throwsStateError,
      );
      expect(await limiter.run(() async => 42), 42);
    });

    test('treats a limit below one as one', () async {
      expect(await Limiter(() => 0).run(() async => 'ok'), 'ok');
    });
  });

  test(
    'parallel prepares followed by serial applies keep all addons',
    () async {
      final tmp = Directory.systemTemp.createTempSync('wb-par');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final inst = WowInstallation(
        id: '0123456789abcdef',
        label: 'Test',
        clientPath: tmp.path,
        clientType: WowClientType.forever,
        flavor: GameFlavor.forever,
      );

      List<int> zipOf(String folder) {
        final archive = Archive()
          ..add(
            ArchiveFile.string('$folder/$folder.toc', '## Title: $folder\n'),
          )
          ..add(ArchiveFile.string('$folder/main.lua', '-- $folder'));
        return ZipEncoder().encode(archive);
      }

      final api = ApiClient(
        client: MockClient((request) async {
          final name = request.url.pathSegments.last.replaceAll('.zip', '');
          return http.Response.bytes(zipOf(name), 200);
        }),
      );
      addTearDown(api.close);
      final service = AddonService(
        api: api,
        sources: () => SourceRegistry(api, const AppSettings()),
        defaultChannel: () => ReleaseChannel.stable,
      );

      (RemoteAddon, AddonRelease) addon(String name) => (
        RemoteAddon(
          source: AddonSourceId.github,
          externalId: 'o/$name',
          name: name,
        ),
        AddonRelease(
          id: name,
          version: '1.0',
          channel: ReleaseChannel.stable,
          downloadUrl: 'https://example.invalid/$name.zip',
        ),
      );

      final prepared = await Future.wait([
        for (final name in ['Alpha', 'Beta', 'Gamma'])
          service.prepare(
            inst,
            remote: addon(name).$1,
            release: addon(name).$2,
          ),
      ]);
      var addons = <InstalledAddon>[];
      for (final p in prepared) {
        addons = await service.apply(inst, addons, p);
      }

      expect(addons.map((a) => a.name), ['Alpha', 'Beta', 'Gamma']);
      for (final name in ['Alpha', 'Beta', 'Gamma']) {
        expect(File('${inst.addonsPath}/$name/main.lua').existsSync(), isTrue);
      }
      // Staging is cleaned up once everything is applied.
      expect(
        Directory('${inst.interfacePath}/.wow-butler-staging').existsSync(),
        isFalse,
      );
    },
  );
}
