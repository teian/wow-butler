import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../core/fingerprint/folder_fingerprint.dart';
import '../core/models/addon_folder.dart';
import '../core/models/game_flavor.dart';
import '../core/toc/toc_file.dart';

/// Reads all addon folders of an installation. Hashing hundreds of folders is
/// CPU and IO heavy, so the work runs in a background isolate.
Future<List<AddonFolder>> scanAddonFolders(
  String addonsPath,
  GameFlavor flavor,
) {
  return Isolate.run(() => scanAddonFoldersSync(addonsPath, flavor));
}

List<AddonFolder> scanAddonFoldersSync(String addonsPath, GameFlavor flavor) {
  final dir = Directory(addonsPath);
  if (!dir.existsSync()) return const [];
  final folders = <AddonFolder>[];
  for (final entity in dir.listSync(followLinks: false)) {
    if (entity is! Directory && entity is! Link) continue;
    final name = p.basename(entity.path);
    if (name.startsWith('.')) continue;
    folders.add(scanFolderSync(entity.path, flavor));
  }
  folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return folders;
}

AddonFolder scanFolderSync(String path, GameFlavor flavor) {
  final name = p.basename(path);
  final tocs = <String>[];
  try {
    for (final e in Directory(path).listSync(followLinks: true)) {
      if (e is File && p.extension(e.path).toLowerCase() == '.toc') {
        tocs.add(e.path);
      }
    }
  } on FileSystemException {
    return AddonFolder(name: name, path: path);
  }
  if (tocs.isEmpty) return AddonFolder(name: name, path: path);

  final selected = TocSelector.select(name, tocs, flavor);
  TocFile? toc;
  if (selected != null) {
    try {
      toc = TocFile.readSync(selected);
    } on FileSystemException {
      toc = null;
    }
  }
  FolderFingerprint? fingerprint;
  try {
    fingerprint = FolderFingerprint.compute(path);
  } on FileSystemException {
    fingerprint = null;
  }
  return AddonFolder(
    name: name,
    path: path,
    toc: toc,
    fingerprint: fingerprint,
    hasAnyToc: true,
  );
}
