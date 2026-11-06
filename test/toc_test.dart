import 'package:flutter_test/flutter_test.dart';
import 'package:wow_butler/core/models/game_flavor.dart';
import 'package:wow_butler/core/toc/toc_file.dart';

void main() {
  group('TocFile', () {
    final toc = TocFile.parse('/x/AddOns/Details/Details.toc', '''
## Interface: 110200, 50500, 11507
## Title: |cffffaa00Details!|r Damage Meter
## Author: Terciob
## Version: @project-version@
## X-Curse-Project-ID: 61284
## Dependencies: LibStub, AceAddon
## LoadOnDemand: 1
# plain comment
core.lua
   ui/frame.xml
''');

    test('reads metadata case-insensitively', () {
      expect(toc['interface'], '110200, 50500, 11507');
      expect(toc.curseProjectId, '61284');
      expect(toc.author, 'Terciob');
    });

    test('strips UI escapes from the title', () {
      expect(toc.title, 'Details! Damage Meter');
    });

    test('ignores unreplaced packager tokens', () {
      expect(toc.version, isNull);
    });

    test('parses multi-client interfaces', () {
      expect(toc.interfaces, [110200, 50500, 11507]);
      expect(toc.interfaces.map(GameFlavor.fromInterface), [
        GameFlavor.retail,
        GameFlavor.mists,
        GameFlavor.vanilla,
      ]);
    });

    test('lists files and dependencies', () {
      expect(toc.files, ['core.lua', 'ui/frame.xml']);
      expect(toc.dependencies, ['LibStub', 'AceAddon']);
      expect(toc.isLoadOnDemand, isTrue);
    });
  });

  group('TocSelector', () {
    const tocs = [
      '/a/Foo/Foo.toc',
      '/a/Foo/Foo_Mainline.toc',
      '/a/Foo/Foo-Classic.toc',
      '/a/Foo/Foo_Vanilla.toc',
      '/a/Foo/Other.toc',
    ];

    test('prefers the flavor specific TOC', () {
      expect(
        TocSelector.select('Foo', tocs, GameFlavor.retail),
        '/a/Foo/Foo_Mainline.toc',
      );
      expect(
        TocSelector.select('Foo', tocs, GameFlavor.vanilla),
        '/a/Foo/Foo_Vanilla.toc',
      );
      expect(
        TocSelector.select('Foo', tocs, GameFlavor.mists),
        '/a/Foo/Foo-Classic.toc',
      );
    });

    test('falls back to the plain TOC', () {
      expect(
        TocSelector.select('Foo', [
          '/a/Foo/Foo.toc',
          '/a/Foo/Foo_Mainline.toc',
        ], GameFlavor.tbc),
        '/a/Foo/Foo.toc',
      );
    });

    test('returns null when no TOC is loadable', () {
      expect(
        TocSelector.select('Foo', [
          '/a/Foo/Foo_Vanilla.toc',
        ], GameFlavor.retail),
        isNull,
      );
    });

    test('picks the Camelot TOC for Forever', () {
      expect(
        TocSelector.select('Foo', [
          '/a/Foo/Foo.toc',
          '/a/Foo/Foo_Vanilla.toc',
          '/a/Foo/Foo_Camelot.toc',
        ], GameFlavor.forever),
        '/a/Foo/Foo_Camelot.toc',
      );
    });

    test('falls back to the Forever TOC for Forever', () {
      expect(
        TocSelector.select('Foo', [
          '/a/Foo/Foo.toc',
          '/a/Foo/Foo_Forever.toc',
        ], GameFlavor.forever),
        '/a/Foo/Foo_Forever.toc',
      );
    });
  });

  group('GameFlavor Forever', () {
    test('version 1.60+ is Forever, 1.1x stays Classic Era', () {
      expect(GameFlavor.fromVersion(1, 60), GameFlavor.forever);
      expect(GameFlavor.fromVersion(1, 15), GameFlavor.vanilla);
      expect(GameFlavor.fromInterface(16001), GameFlavor.forever);
      expect(GameFlavor.fromInterface(11507), GameFlavor.vanilla);
    });

    test('the _forever_ client folder is recognized', () {
      final type = WowClientType.fromFolderName('_forever_');
      expect(type, WowClientType.forever);
      expect(type!.defaultFlavor, GameFlavor.forever);
    });
  });
}
