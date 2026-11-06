import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// Writes the regular file entries of [archive] below [outputDir].
///
/// Replacement for package:archive's `extractArchiveToDiskSync`, whose
/// symlink containment checks silently drop every entry on Windows. Addon
/// zips and backup archives carry only regular files, so anything else is
/// skipped, as is any entry that would escape [outputDir] (zip slip).
void extractArchiveSafely(Archive archive, String outputDir) {
  final root = p.normalize(p.absolute(outputDir));
  Directory(root).createSync(recursive: true);
  for (final entry in archive) {
    if (!entry.isFile || entry.isSymbolicLink) continue;
    final target = p.normalize(p.join(root, entry.name.replaceAll(r'\', '/')));
    if (!p.isWithin(root, target)) continue;
    File(target).parent.createSync(recursive: true);
    final output = OutputFileStream(target);
    entry.writeContent(output);
    output.closeSync();
  }
}
