import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:wow_butler/core/models/addon.dart';
import 'package:wow_butler/core/models/app_settings.dart';
import 'package:wow_butler/core/models/game_flavor.dart';
import 'package:wow_butler/core/models/wow_installation.dart';
import 'package:wow_butler/services/addon_service.dart';
import 'package:wow_butler/services/download_watcher.dart';
import 'package:wow_butler/sources/api_client.dart';
import 'package:wow_butler/sources/curseforge_source.dart';
import 'package:wow_butler/sources/source_registry.dart';

const _cfKey = r'$2a$10$abcdefghijklmnopqrstuvABCDEFGHIJKLMNOPQRSTUV0123456789';

/// Auctionator as CurseForge returns it with third-party downloads disabled.
Map<String, dynamic> _cfAuctionator() => {
  'id': 7,
  'slug': 'auctionator',
  'name': 'Auctionator',
  'allowModDistribution': false,
  'authors': [
    {'name': 'plusmouse'},
  ],
  'links': {'websiteUrl': 'https://www.curseforge.com/wow/addons/auctionator'},
  'latestFiles': [
    {
      'id': 700,
      'displayName': '300.1.0',
      'fileName': 'Auctionator-300.1.0.zip',
      'downloadUrl': null,
      'releaseType': 1,
      'sortableGameVersions': [
        {
          'gameVersionTypeId': CurseForgeSource.gameVersionTypeId(
            GameFlavor.retail,
          ),
        },
      ],
      'modules': [
        {'name': 'Auctionator', 'fingerprint': 1},
      ],
    },
  ],
};

/// The same addon on the WowUp Hub, by [author].
Map<String, dynamic> _hubAuctionator({String author = 'plusmouse'}) => {
  'id': 99,
  'repository_name': 'Auctionator',
  'owner_name': author,
  'current_release': {
    'id': 990,
    'tag_name': '300.1.0',
    'download_url': 'https://example.invalid/auctionator.zip',
    'game_versions': [
      {'game_type': 'retail', 'interface': 110200},
    ],
  },
};

void main() {
  late Directory tmp;
  late WowInstallation inst;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wb-fallback');
    inst = WowInstallation(
      id: '0123456789abcdef',
      label: 'Test',
      clientPath: tmp.path,
      clientType: WowClientType.retail,
      flavor: GameFlavor.retail,
    );
    final dir = Directory(p.join(inst.addonsPath, 'Auctionator'))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'Auctionator.toc')).writeAsStringSync(
      '## Interface: 110200\n'
      '## Title: Auctionator\n'
      '## Author: plusmouse\n'
      '## Version: 300.1.0\n'
      '## X-Curse-Project-ID: 7\n'
      'main.lua\n',
    );
    File(p.join(dir.path, 'main.lua')).writeAsStringSync('-- main');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  ApiClient api({
    String hubAuthor = 'plusmouse',
    List<String>? searches,
    bool hubSearchFails = false,
  }) => ApiClient(
    client: MockClient((request) async {
      final url = request.url;
      if (hubSearchFails && url.path.contains('/addons/search/')) {
        return http.Response('unavailable', 503);
      }
      Object? body;
      if (url.host == 'api.curseforge.com') {
        if (url.path.contains('/fingerprints/')) {
          body = {
            'data': {'exactMatches': <Object>[]},
          };
        } else if (url.path.endsWith('/v1/mods')) {
          body = {
            'data': [_cfAuctionator()],
          };
        } else if (url.path.endsWith('/v1/mods/7')) {
          body = {'data': _cfAuctionator()};
        } else if (url.path.endsWith('/mods/search')) {
          body = {'data': <Object>[]};
        }
      } else if (url.host == 'hub.wowup.io') {
        if (url.path.endsWith('/addons/fingerprint')) {
          body = {'exactMatches': <Object>[]};
        } else if (url.path.contains('/addons/search/')) {
          searches?.add(url.queryParameters['query'] ?? '');
          body = {
            'addons': [_hubAuctionator(author: hubAuthor)],
          };
        } else if (url.path.endsWith('/addons/99')) {
          body = {'addon': _hubAuctionator(author: hubAuthor)};
        }
      }
      return body == null
          ? http.Response('not found', 404)
          : http.Response(jsonEncode(body), 200);
    }),
  );

  AddonService service(ApiClient api, {bool prefer = true}) {
    final settings = AppSettings(
      curseforgeApiKey: _cfKey,
      // CurseForge first, so the fallback is what moves the addon.
      sourcePriority: <AddonSourceId>{
        AddonSourceId.curseforge,
        AddonSourceId.wowup,
        ...AppSettings.defaultSourcePriority,
      }.toList(),
      disabledSources: AddonSourceId.values
          .where(
            (s) => s != AddonSourceId.curseforge && s != AddonSourceId.wowup,
          )
          .toSet(),
    );
    return AddonService(
      api: api,
      sources: () => SourceRegistry(api, settings),
      defaultChannel: () => ReleaseChannel.stable,
      preferDownloadable: () => prefer,
    );
  }

  test(
    'a website-only addon moves to a source that allows downloads',
    () async {
      final client = api();
      final addon = (await service(client).sync(inst, const [])).addons.single;
      client.close();

      expect(addon.source, AddonSourceId.wowup);
      expect(addon.externalId, '99');
      expect(addon.downloadsAllowed, isTrue);
      expect(addon.manualSource, isFalse);
      // The installed version is recognized on the new source.
      expect(addon.installedReleaseId, '990');
      expect(addon.hasUpdate, isFalse);
      // CurseForge stays available as alternative.
      expect(addon.alternatives.map((a) => a.key), ['curseforge:7']);
      expect(addon.alternatives.single.downloadsAllowed, isFalse);
    },
  );

  test('stays on the website-only source when the fallback is off', () async {
    final searches = <String>[];
    final client = api(searches: searches);
    final addon = (await service(
      client,
      prefer: false,
    ).sync(inst, const [])).addons.single;
    client.close();

    expect(addon.source, AddonSourceId.curseforge);
    expect(addon.downloadsAllowed, isFalse);
    expect(searches, isEmpty);
  });

  test('keeps a source the user picked', () async {
    final client = api();
    final s = service(client);
    final first = (await s.sync(inst, const [])).addons.single;
    // The user switches back to CurseForge by hand.
    final cf = await s.sources()[AddonSourceId.curseforge].getById(
      '7',
      inst.flavor,
    );
    final picked = s.relink(first, cf!, manual: true);
    final again = (await s.sync(inst, [picked])).addons.single;
    client.close();

    expect(picked.alternatives.map((a) => a.key), ['wowup:99']);
    expect(again.source, AddonSourceId.curseforge);
    expect(again.manualSource, isTrue);
    expect(again.alternatives.map((a) => a.key), ['wowup:99']);
  });

  test('searches again after a source failed', () async {
    final client = api(hubSearchFails: true);
    final result = await service(client).sync(inst, const []);
    client.close();

    final addon = result.addons.single;
    expect(addon.source, AddonSourceId.curseforge);
    expect(addon.alternativesCheckedAt, isNull);
    expect(result.warnings, isNotEmpty);
  });

  test('ignores a namesake by another author', () async {
    final client = api(hubAuthor: 'someoneelse');
    final addon = (await service(client).sync(inst, const [])).addons.single;
    client.close();

    expect(addon.source, AddonSourceId.curseforge);
    expect(addon.alternatives, isEmpty);
    expect(addon.alternativesCheckedAt, isNotNull);
  });

  test('installs a release from a file downloaded in the browser', () async {
    final client = api();
    final s = service(client, prefer: false);
    final addons = (await s.sync(inst, const [])).addons;
    final remote = await s.sources()[AddonSourceId.curseforge].getById(
      '7',
      inst.flavor,
    );
    final release = remote!.releases.single;
    expect(release.downloadUrl, isEmpty);

    final archive = Archive()
      ..add(ArchiveFile.string('Auctionator/Auctionator.toc', '## Title: A\n'))
      ..add(ArchiveFile.string('Auctionator/new.lua', '-- new'));
    final zip = File(p.join(tmp.path, 'Auctionator-300.1.0.zip'))
      ..writeAsBytesSync(ZipEncoder().encode(archive));

    final prepared = await s.prepareFile(
      inst,
      remote: remote,
      release: release,
      archive: zip,
    );
    final result = await s.apply(inst, addons, prepared);
    client.close();

    final addon = result.single;
    expect(addon.remoteKey, 'curseforge:7');
    expect(addon.installedReleaseId, '700');
    expect(addon.hasUpdate, isFalse);
    expect(
      File(p.join(inst.addonsPath, 'Auctionator', 'new.lua')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(inst.addonsPath, 'Auctionator', 'main.lua')).existsSync(),
      isFalse,
    );
  });

  test('installs a loose addon archive', () async {
    final client = api();
    final archive = Archive()
      ..add(ArchiveFile.string('MyAddon/MyAddon.toc', '## Title: MyAddon\n'));
    final zip = File(p.join(tmp.path, 'MyAddon.zip'))
      ..writeAsBytesSync(ZipEncoder().encode(archive));
    final folders = await service(client).installArchive(inst, zip);
    client.close();

    expect(folders, ['MyAddon']);
    expect(
      File(p.join(inst.addonsPath, 'MyAddon', 'MyAddon.toc')).existsSync(),
      isTrue,
    );
  });

  group('DownloadWatcher', () {
    test('matches browser names for duplicate downloads', () {
      const want = 'Auctionator-300.1.0.zip';
      expect(DownloadWatcher.matches('Auctionator-300.1.0.zip', want), isTrue);
      expect(
        DownloadWatcher.matches('Auctionator-300.1.0 (1).zip', want),
        isTrue,
      );
      expect(
        DownloadWatcher.matches('Auctionator-300.1.0(2).zip', want),
        isTrue,
      );
      expect(
        DownloadWatcher.matches('Auctionator-300.1.0-1.zip', want),
        isTrue,
      );
      expect(
        DownloadWatcher.matches('Auctionator-300.1.0.zip.part', want),
        isFalse,
      );
      expect(DownloadWatcher.matches('Other.zip', want), isFalse);
      expect(DownloadWatcher.matches('Other.zip', ''), isTrue);
    });

    test('waits until the download is complete', () async {
      final dir = Directory(p.join(tmp.path, 'Downloads'))..createSync();
      // An older download of the same file is not picked up.
      File(p.join(dir.path, 'Auctionator-300.1.0.zip'))
          .writeAsStringSync('old');
      final watcher = DownloadWatcher(
        directory: dir,
        fileName: 'Auctionator-300.1.0.zip',
        interval: const Duration(milliseconds: 20),
      );
      final found = watcher.wait();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      // Firefox dates a download by the server's Last-Modified.
      File(p.join(dir.path, 'Auctionator-300.1.0 (1).zip'))
        ..writeAsStringSync('new')
        ..setLastModifiedSync(DateTime(2024));
      final file = await found.timeout(const Duration(seconds: 2));
      expect(p.basename(file.path), 'Auctionator-300.1.0 (1).zip');
    });

    test('accepts a renamed download that names the addon', () async {
      final dir = Directory(p.join(tmp.path, 'Downloads'))..createSync();
      final watcher = DownloadWatcher(
        directory: dir,
        fileName: 'Auctionator-300.1.0.zip',
        addonName: 'Auctionator',
        interval: const Duration(milliseconds: 20),
      );
      final found = watcher.wait();
      File(p.join(dir.path, 'Other.zip')).writeAsStringSync('other');
      File(p.join(dir.path, 'auctionator_300_1_0.zip'))
          .writeAsStringSync('new');
      final file = await found.timeout(const Duration(seconds: 2));
      expect(p.basename(file.path), 'auctionator_300_1_0.zip');
    });
  });
}
