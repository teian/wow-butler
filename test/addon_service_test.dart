import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wow_butler/core/util/file_sync.dart';
import 'package:wow_butler/services/addon_service.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('wb-svc'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String zip(Map<String, String> files) {
    final archive = Archive();
    files.forEach(
      (name, content) => archive.add(ArchiveFile.string(name, content)),
    );
    final path = p.join(tmp.path, 'a.zip');
    File(path).writeAsBytesSync(ZipEncoder().encode(archive));
    return path;
  }

  group('extractAddonArchive', () {
    test('returns the top level addon folders', () {
      final out = extractAddonArchive(
        zip({'ElvUI/ElvUI.toc': '', 'ElvUI_Options/ElvUI_Options.toc': ''}),
        p.join(tmp.path, 'x'),
      );
      expect(out.map(p.basename).toSet(), {'ElvUI', 'ElvUI_Options'});
    });

    test('unwraps a single wrapper folder', () {
      final out = extractAddonArchive(
        zip({'repo-1.0/MyAddon/MyAddon.toc': ''}),
        p.join(tmp.path, 'x'),
      );
      expect(out.map(p.basename), ['MyAddon']);
    });

    test('renames a release named folder after its TOC', () {
      final out = extractAddonArchive(
        zip({'MyAddon-1.2.3/MyAddon_Mainline.toc': ''}),
        p.join(tmp.path, 'x'),
      );
      expect(out.map(p.basename), ['MyAddon']);
    });

    test('wraps loose files at the archive root', () {
      final out = extractAddonArchive(
        zip({'Loose.toc': '', 'core.lua': ''}),
        p.join(tmp.path, 'x'),
      );
      expect(out.map(p.basename), ['Loose']);
      expect(File(p.join(out.single, 'core.lua')).existsSync(), isTrue);
    });
  });

  test('orderFolders puts the parent folder first', () {
    expect(
      orderFolders(['ElvUI_Options', 'ElvUI_Libraries', 'ElvUI']).first,
      'ElvUI',
    );
    expect(orderFolders(['B', 'A'], preferred: 'B').first, 'B');
  });

  test('mirrorDirectorySync copies, updates and deletes', () {
    final src = Directory(p.join(tmp.path, 'src'))..createSync();
    final dst = Directory(p.join(tmp.path, 'dst'))..createSync();
    File(p.join(src.path, 'keep.txt')).writeAsStringSync('new');
    File(p.join(src.path, 'sub', 'a.lua'))
      ..createSync(recursive: true)
      ..writeAsStringSync('a');
    File(p.join(dst.path, 'stale.txt')).writeAsStringSync('old');
    File(p.join(dst.path, 'x.bak')).writeAsStringSync('excluded');

    mirrorDirectorySync(src.path, dst.path, exclude: isWowTempFile);

    expect(File(p.join(dst.path, 'keep.txt')).readAsStringSync(), 'new');
    expect(File(p.join(dst.path, 'sub', 'a.lua')).existsSync(), isTrue);
    expect(File(p.join(dst.path, 'stale.txt')).existsSync(), isFalse);
    expect(File(p.join(dst.path, 'x.bak')).existsSync(), isTrue);
  });
}
