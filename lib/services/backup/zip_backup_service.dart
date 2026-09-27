import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../core/models/addon.dart';
import '../../core/models/wow_installation.dart';
import '../../core/util/file_sync.dart';

/// A zip archive created by [ZipBackupService].
class ZipBackup {
  const ZipBackup({
    required this.path,
    required this.createdAt,
    required this.sizeBytes,
  });

  final String path;
  final DateTime createdAt;
  final int sizeBytes;

  String get fileName => p.basename(path);
}

/// What a backup or restore covers.
class BackupScope {
  const BackupScope({this.addons = true, this.wtf = true});

  final bool addons;
  final bool wtf;
}

/// Zip snapshots of `Interface/AddOns` and `WTF`, stored per installation in
/// a user chosen directory: `<dir>/<installation-slug>/<timestamp>.zip`.
class ZipBackupService {
  const ZipBackupService();

  static const manifestName = 'wow-butler-addons.json';
  static final _stamp = DateFormat('yyyy-MM-dd_HH-mm-ss');

  String _dirFor(String backupRoot, WowInstallation inst) =>
      p.join(backupRoot, inst.slug);

  /// Creates a backup unless the data in [scope] is unchanged since the
  /// newest backup with the same scope. In that case the existing backup is
  /// returned with `created: false`.
  Future<({ZipBackup backup, bool created})> createIfChanged({
    required String backupRoot,
    required WowInstallation inst,
    required List<InstalledAddon> addons,
    required BackupScope scope,
    String? suffix,
  }) async {
    final fingerprint = await _fingerprintInIsolate(inst.clientPath, scope);
    final previous = await _latestWithScope(backupRoot, inst, scope);
    if (previous != null && previous.fingerprint == fingerprint) {
      return (backup: previous.backup, created: false);
    }
    final backup = await create(
      backupRoot: backupRoot,
      inst: inst,
      addons: addons,
      scope: scope,
      suffix: suffix,
      fingerprint: fingerprint,
    );
    return (backup: backup, created: true);
  }

  /// Newest backup whose manifest records the same scope, with the
  /// fingerprint stored in it. Only the most recent archives are inspected.
  Future<({ZipBackup backup, String? fingerprint})?> _latestWithScope(
    String backupRoot,
    WowInstallation inst,
    BackupScope scope,
  ) async {
    for (final backup in (await list(backupRoot, inst)).take(20)) {
      final json = await _readManifestJson(backup.path);
      final s = json?['scope'];
      if (s is! Map) continue;
      if (s['addons'] == scope.addons && s['wtf'] == scope.wtf) {
        return (backup: backup, fingerprint: json!['fingerprint'] as String?);
      }
    }
    return null;
  }

  Future<ZipBackup> create({
    required String backupRoot,
    required WowInstallation inst,
    required List<InstalledAddon> addons,
    required BackupScope scope,
    String? suffix,
    String? fingerprint,
  }) async {
    fingerprint ??= await _fingerprintInIsolate(inst.clientPath, scope);
    final dir = _dirFor(backupRoot, inst);
    await Directory(dir).create(recursive: true);
    final name =
        '${_stamp.format(DateTime.now())}${suffix == null ? '' : '_$suffix'}.zip';
    final zipPath = p.join(dir, name);
    final manifest = jsonEncode({
      'installation': inst.toJson(),
      'createdAt': DateTime.now().toIso8601String(),
      'scope': {'addons': scope.addons, 'wtf': scope.wtf},
      'fingerprint': fingerprint,
      'addons': addons.map((a) => a.toJson()).toList(),
    });
    final clientPath = inst.clientPath;
    await _createZipInIsolate(zipPath, clientPath, scope, manifest);
    final stat = await File(zipPath).stat();
    return ZipBackup(
      path: zipPath,
      createdAt: DateTime.now(),
      sizeBytes: stat.size,
    );
  }

  Future<List<ZipBackup>> list(String backupRoot, WowInstallation inst) async {
    final dir = Directory(_dirFor(backupRoot, inst));
    if (!await dir.exists()) return const [];
    final backups = <ZipBackup>[];
    await for (final e in dir.list()) {
      if (e is! File || p.extension(e.path) != '.zip') continue;
      final stat = await e.stat();
      final base = p.basenameWithoutExtension(e.path);
      DateTime created;
      try {
        created = base.length >= 19
            ? _stamp.parse(base.substring(0, 19))
            : stat.modified;
      } on FormatException {
        created = stat.modified;
      }
      backups.add(
        ZipBackup(path: e.path, createdAt: created, sizeBytes: stat.size),
      );
    }
    backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return backups;
  }

  /// Deletes the oldest scheduled archives beyond [keep]. Archives with a
  /// suffix (manual, pre-restore) are never pruned.
  Future<void> prune(String backupRoot, WowInstallation inst, int keep) async {
    if (keep <= 0) return;
    final all = await list(backupRoot, inst);
    final scheduled = all
        .where((b) => p.basenameWithoutExtension(b.path).length == 19)
        .toList();
    for (final old in scheduled.skip(keep)) {
      await File(old.path).delete();
    }
  }

  /// Restores [backup] into the installation. The current state is saved as
  /// a `pre-restore` archive first, so a restore can always be undone.
  Future<void> restore({
    required ZipBackup backup,
    required String backupRoot,
    required WowInstallation inst,
    required List<InstalledAddon> currentAddons,
    required BackupScope scope,
  }) async {
    await create(
      backupRoot: backupRoot,
      inst: inst,
      addons: currentAddons,
      scope: scope,
      suffix: 'pre-restore',
    );
    final zipPath = backup.path;
    final clientPath = inst.clientPath;
    await _restoreInIsolate(zipPath, clientPath, scope);
  }

  /// Reads the addon list stored alongside the files.
  Future<List<InstalledAddon>?> readManifest(ZipBackup backup) async {
    final json = await _readManifestJson(backup.path);
    if (json == null) return null;
    return [
      for (final a in json['addons'] as List)
        InstalledAddon.fromJson(a as Map<String, dynamic>),
    ];
  }

  Future<Map<String, dynamic>?> _readManifestJson(String zipPath) async {
    try {
      final text = await _readManifestInIsolate(zipPath);
      return text == null ? null : jsonDecode(text) as Map<String, dynamic>;
    } on Object {
      // Unreadable or foreign archive: treat as having no manifest.
      return null;
    }
  }
}

// Isolate entry points are top-level so their closures capture only the
// sendable parameters.
Future<void> _createZipInIsolate(
  String zipPath,
  String clientPath,
  BackupScope scope,
  String manifest,
) => Isolate.run(
  () => _createZipSync(
    zipPath: zipPath,
    clientPath: clientPath,
    scope: scope,
    manifest: manifest,
  ),
);

Future<void> _restoreInIsolate(
  String zipPath,
  String clientPath,
  BackupScope scope,
) => Isolate.run(() => _restoreSync(zipPath, clientPath, scope));

Future<String> _fingerprintInIsolate(String clientPath, BackupScope scope) =>
    Isolate.run(() => backupFingerprintSync(clientPath, scope));

/// Identifies the state of the data a backup of [scope] would contain.
///
/// WTF files are hashed by content: the game rewrites saved variables on
/// every logout, so timestamps change even when nothing else does. The much
/// larger AddOns tree is compared by size and modification time.
String backupFingerprintSync(String clientPath, BackupScope scope) {
  final entries = <String>[];
  void walk(String relative, {required bool content}) {
    final dir = Directory(p.join(clientPath, relative));
    if (!dir.existsSync()) return;
    for (final e in dir.listSync(recursive: true, followLinks: true)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: clientPath).replaceAll(r'\', '/');
      if (isWowTempFile(rel)) continue;
      if (content) {
        entries.add('$rel|${md5.convert(e.readAsBytesSync())}');
      } else {
        final stat = e.statSync();
        entries.add(
          '$rel|${stat.size}|${stat.modified.millisecondsSinceEpoch ~/ 1000}',
        );
      }
    }
  }

  if (scope.addons) walk(p.join('Interface', 'AddOns'), content: false);
  if (scope.wtf) walk('WTF', content: true);
  entries.sort();
  return sha1.convert(utf8.encode(entries.join('\n'))).toString();
}

Future<String?> _readManifestInIsolate(String zipPath) => Isolate.run(() {
  final input = InputFileStream(zipPath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    final file = archive.findFile(ZipBackupService.manifestName);
    return file == null ? null : utf8.decode(file.content);
  } finally {
    input.closeSync();
  }
});

void _createZipSync({
  required String zipPath,
  required String clientPath,
  required BackupScope scope,
  required String manifest,
}) {
  final tmpPath = '$zipPath.partial';
  final encoder = ZipFileEncoder()..create(tmpPath);
  try {
    void addTree(String relative) {
      final dir = Directory(p.join(clientPath, relative));
      if (!dir.existsSync()) return;
      for (final e in dir.listSync(recursive: true, followLinks: true)) {
        if (e is! File) continue;
        final rel = p.relative(e.path, from: clientPath).replaceAll(r'\', '/');
        if (isWowTempFile(rel)) continue;
        encoder.addFileSync(e, rel);
      }
    }

    if (scope.addons) addTree(p.join('Interface', 'AddOns'));
    if (scope.wtf) addTree('WTF');
    final bytes = utf8.encode(manifest);
    encoder.addArchiveFile(
      ArchiveFile.bytes(ZipBackupService.manifestName, bytes),
    );
  } finally {
    encoder.closeSync();
  }
  File(tmpPath).renameSync(zipPath);
}

void _restoreSync(String zipPath, String clientPath, BackupScope scope) {
  final staging = Directory(p.join(clientPath, '.wow-butler-restore'));
  if (staging.existsSync()) staging.deleteSync(recursive: true);
  final input = InputFileStream(zipPath);
  try {
    extractArchiveToDiskSync(ZipDecoder().decodeStream(input), staging.path);
  } finally {
    input.closeSync();
  }
  try {
    final addons = p.join(staging.path, 'Interface', 'AddOns');
    if (scope.addons && Directory(addons).existsSync()) {
      mirrorDirectorySync(addons, p.join(clientPath, 'Interface', 'AddOns'));
    }
    final wtf = p.join(staging.path, 'WTF');
    if (scope.wtf && Directory(wtf).existsSync()) {
      mirrorDirectorySync(
        wtf,
        p.join(clientPath, 'WTF'),
        exclude: isWowTempFile,
      );
    }
  } finally {
    staging.deleteSync(recursive: true);
  }
}
