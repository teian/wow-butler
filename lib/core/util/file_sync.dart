import 'dart:io';

import 'package:path/path.dart' as p;

/// Makes [target] an exact copy of [source]: copies new or changed files and
/// deletes files that no longer exist in [source]. Paths matching [exclude]
/// (relative, `/` separated) are neither copied nor deleted.
///
/// Synchronous on purpose: callers run it inside an isolate.
void mirrorDirectorySync(
  String source,
  String target, {
  bool Function(String relativePath)? exclude,
}) {
  final src = Directory(source);
  final dst = Directory(target);
  dst.createSync(recursive: true);
  if (!src.existsSync()) {
    _deleteChildren(dst, exclude, target);
    return;
  }

  final wanted = <String>{};
  for (final entity in src.listSync(recursive: true, followLinks: true)) {
    final rel = _rel(entity.path, source);
    if (exclude?.call(rel) ?? false) continue;
    wanted.add(rel);
    final out = p.join(target, rel);
    if (entity is Directory) {
      Directory(out).createSync(recursive: true);
    } else if (entity is File) {
      final outFile = File(out);
      if (_needsCopy(entity, outFile)) {
        outFile.parent.createSync(recursive: true);
        entity.copySync(out);
        outFile.setLastModifiedSync(entity.lastModifiedSync());
      }
    }
  }

  // Deepest paths first so directories are empty before removal.
  final existing = dst.listSync(recursive: true, followLinks: false).toList()
    ..sort((a, b) => b.path.length.compareTo(a.path.length));
  for (final entity in existing) {
    final rel = _rel(entity.path, target);
    if (wanted.contains(rel) || (exclude?.call(rel) ?? false)) continue;
    if (rel == '.git' || rel.startsWith('.git/')) continue;
    if (entity is Directory) {
      // Keep folders that still hold excluded files (e.g. `*.bak`).
      if (entity.listSync().isEmpty) entity.deleteSync();
    } else {
      entity.deleteSync();
    }
  }
}

void _deleteChildren(
  Directory dir,
  bool Function(String)? exclude,
  String root,
) {
  for (final e in dir.listSync(followLinks: false)) {
    if (exclude?.call(_rel(e.path, root)) ?? false) continue;
    e.deleteSync(recursive: true);
  }
}

String _rel(String path, String root) =>
    p.relative(path, from: root).replaceAll(r'\', '/');

bool _needsCopy(File source, File target) {
  if (!target.existsSync()) return true;
  final a = source.statSync(), b = target.statSync();
  return a.size != b.size ||
      a.modified.millisecondsSinceEpoch ~/ 1000 !=
          b.modified.millisecondsSinceEpoch ~/ 1000;
}

/// Backup files the game writes next to saved variables.
bool isWowTempFile(String relativePath) {
  final lower = relativePath.toLowerCase();
  return lower.endsWith('.bak') || lower.endsWith('.old');
}

/// Total size of all files below [path] in bytes.
int directorySizeSync(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return 0;
  var total = 0;
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is File) total += e.lengthSync();
  }
  return total;
}
