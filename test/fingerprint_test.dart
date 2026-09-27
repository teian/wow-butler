import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wow_butler/core/fingerprint/folder_fingerprint.dart';
import 'package:wow_butler/core/fingerprint/murmur2.dart';

void main() {
  group('curseFileFingerprint', () {
    // Reference values from a port of WoWUp's native curse.cc.
    final vectors = <String, int>{
      '': 1540447798,
      'a': 626045324,
      'ab': 1692487918,
      'abc': 1621425345,
      'abcd': 3376380438,
      'Hello, World!\n': 1961219979,
    };
    vectors.forEach((input, expected) {
      test('matches CurseForge for ${jsonEncode(input)}', () {
        expect(
          curseFileFingerprint(Uint8List.fromList(utf8.encode(input))),
          expected,
        );
      });
    });

    test('ignores whitespace bytes', () {
      final bytes = Uint8List.fromList(List.generate(256, (i) => i));
      expect(curseFileFingerprint(bytes), 2094645347);
      expect(
        curseFileFingerprint(Uint8List.fromList(utf8.encode('a b\tc\r\nd'))),
        curseFileFingerprint(Uint8List.fromList(utf8.encode('abcd'))),
      );
    });
  });

  group('FolderFingerprint', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('wb-fp'));
    tearDown(() => root.deleteSync(recursive: true));

    File write(String rel, String content) {
      final f = File(p.join(root.path, rel))..createSync(recursive: true);
      f.writeAsStringSync(content);
      return f;
    }

    test('hashes only files reachable from the TOC', () {
      write(
        'MyAddon/MyAddon.toc',
        '## Interface: 110200\n# comment\ncore.lua\nui\\ui.xml\n',
      );
      write('MyAddon/core.lua', 'print(1)');
      write(
        'MyAddon/ui/ui.xml',
        '<Ui><!-- <Script file="skip.lua"/> --><Script file="frame.lua"/></Ui>',
      );
      write('MyAddon/ui/frame.lua', 'local f');
      write('MyAddon/ui/skip.lua', 'ignored');
      write('MyAddon/README.md', 'not loaded');

      final fp = FolderFingerprint.compute(p.join(root.path, 'MyAddon'));

      final loaded = [
        'MyAddon/MyAddon.toc',
        'MyAddon/core.lua',
        'MyAddon/ui/ui.xml',
        'MyAddon/ui/frame.lua',
      ].map((rel) => File(p.join(root.path, rel)).readAsBytesSync());

      final md5s = [for (final b in loaded) md5.convert(b).toString()]..sort();
      expect(fp.md5, md5.convert(utf8.encode(md5s.join())).toString());

      final curse = [for (final b in loaded) curseFileFingerprint(b)]..sort();
      expect(fp.curse, murmur2(Uint8List.fromList(ascii.encode(curse.join()))));
    });

    test('resolves includes case-insensitively', () {
      write('A/A.toc', 'Core.LUA\n');
      write('A/core.lua', 'x');
      final withMismatch = FolderFingerprint.compute(p.join(root.path, 'A'));
      File(p.join(root.path, 'A/A.toc')).writeAsStringSync('core.lua\n');
      final exact = FolderFingerprint.compute(p.join(root.path, 'A'));
      // Same file set; only the TOC bytes differ.
      expect(withMismatch.md5, isNot(exact.md5));
      expect(FolderFingerprint.compute(p.join(root.path, 'A')).md5, exact.md5);
    });
  });
}
