import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wow_butler/core/external_addons.dart';
import 'package:wow_butler/core/models/addon.dart';
import 'package:wow_butler/core/models/app_settings.dart';
import 'package:wow_butler/core/models/game_flavor.dart';
import 'package:wow_butler/core/models/wow_installation.dart';
import 'package:wow_butler/core/util/version_label.dart';
import 'package:wow_butler/services/addon_service.dart';
import 'package:wow_butler/sources/api_client.dart';
import 'package:wow_butler/sources/source_registry.dart';

void main() {
  group('versionLabel', () {
    test('extracts the version from archive names', () {
      expect(versionLabel('ForeverDungeonJournal1.7.1.zip'), '1.7.1');
      expect(
        versionLabel('TalentsForeverBook-0.38.19.20261106.zip'),
        '0.38.19.20261106',
      );
      expect(versionLabel('Foo-v2.3.0-beta.1.zip'), '2.3.0-beta.1');
      expect(versionLabel('Foo.zip'), 'Foo');
    });

    test('leaves real version names alone', () {
      expect(versionLabel(' v3.8.7 '), 'v3.8.7');
      expect(versionLabel('341'), '341');
      expect(versionLabel('Questie-v12.6.2'), 'Questie-v12.6.2');
    });
  });

  test('isKnownExternalAddon recognizes subscription addons', () {
    expect(isKnownExternalAddon('ZygorGuidesViewer'), isTrue);
    expect(isKnownExternalAddon('ZygorGuidesViewerForever'), isTrue);
    expect(isKnownExternalAddon('RXPGuides'), isTrue);
    expect(isKnownExternalAddon('TradeSkillMaster_AppHelper'), isTrue);
    expect(isKnownExternalAddon('TradeSkillMaster'), isFalse);
    expect(isKnownExternalAddon('Questie'), isFalse);
  });

  test('InstalledAddon keeps the external flag and cleans old versions', () {
    final addon = InstalledAddon.fromJson({
      'id': 'a',
      'name': 'DungeonJournal',
      'folders': ['DungeonJournal'],
      'installedVersion': 'ForeverDungeonJournal1.7.1.zip',
      'external': true,
    });
    expect(addon.installedVersion, '1.7.1');
    expect(InstalledAddon.fromJson(addon.toJson()).external, isTrue);
    expect(
      InstalledAddon.fromJson({
        'id': 'b',
        'name': 'B',
        'folders': ['B'],
      }).external,
      isFalse,
    );
  });

  group('sync marks external addons', () {
    late Directory tmp;
    late WowInstallation inst;
    late ApiClient api;
    late AddonService service;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('wb-ext');
      inst = WowInstallation(
        id: '0123456789abcdef',
        label: 'Test',
        clientPath: tmp.path,
        clientType: WowClientType.forever,
        flavor: GameFlavor.forever,
      );
      void addon(String folder, String toc) {
        final dir = Directory(p.join(inst.addonsPath, folder))
          ..createSync(recursive: true);
        File(p.join(dir.path, '$folder.toc')).writeAsStringSync(toc);
      }

      addon('ZygorGuidesViewer', '## Title: Zygor Guides Viewer\n');
      addon('MyLocal', '## Title: My Local\n');
      api = ApiClient();
      // No active sources: everything stays local.
      final settings = AppSettings(
        disabledSources: AddonSourceId.values.toSet(),
      );
      service = AddonService(
        api: api,
        sources: () => SourceRegistry(api, settings),
        defaultChannel: () => ReleaseChannel.stable,
      );
    });
    tearDown(() {
      api.close();
      tmp.deleteSync(recursive: true);
    });

    InstalledAddon byFolder(List<InstalledAddon> list, String folder) =>
        list.singleWhere((a) => a.folders.first == folder);

    test('known external folders are marked, others stay local', () async {
      final result = await service.sync(inst, const []);
      expect(byFolder(result.addons, 'ZygorGuidesViewer').external, isTrue);
      expect(byFolder(result.addons, 'MyLocal').external, isFalse);
    });

    test('a manual mark survives the next sync', () async {
      final first = await service.sync(inst, const []);
      final marked = [
        for (final a in first.addons)
          a.folders.first == 'MyLocal' ? a.copyWith(external: true) : a,
      ];
      final second = await service.sync(inst, marked);
      expect(byFolder(second.addons, 'MyLocal').external, isTrue);
    });
  });
}
