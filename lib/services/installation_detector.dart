import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/models/game_flavor.dart';
import '../core/models/wow_installation.dart';

/// Finds WoW game clients on disk and reads their version information.
class InstallationDetector {
  const InstallationDetector();

  /// Scans well-known install locations for game clients.
  Future<List<WowInstallation>> detect() async {
    final found = <WowInstallation>[];
    final seen = <String>{};
    for (final root in await _candidateRoots()) {
      for (final inst in await clientsIn(root)) {
        if (seen.add(inst.id)) found.add(inst);
      }
    }
    return found;
  }

  /// Resolves a user chosen folder to clients. Accepts the installation root
  /// (`World of Warcraft`), a client folder (`_retail_`) or its `Interface`
  /// or `AddOns` subfolder.
  Future<List<WowInstallation>> fromUserPath(String path) async {
    var dir = p.normalize(path);
    for (var i = 0; i < 3; i++) {
      final name = p.basename(dir).toLowerCase();
      if (name == 'addons' || name == 'interface') {
        dir = p.dirname(dir);
      }
    }
    final client = await _clientAt(dir);
    if (client != null) return [client];
    return clientsIn(dir);
  }

  Future<List<WowInstallation>> clientsIn(String root) async {
    final dir = Directory(root);
    if (!await dir.exists()) return const [];
    final result = <WowInstallation>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final client = await _clientAt(entity.path);
      if (client != null) result.add(client);
    }
    result.sort((a, b) => a.clientType.index.compareTo(b.clientType.index));
    return result;
  }

  Future<WowInstallation?> _clientAt(String clientPath) async {
    final type = WowClientType.fromFolderName(p.basename(clientPath));
    if (type == null || !await _looksLikeClient(clientPath)) return null;

    clientPath = await _canonical(clientPath);
    final root = p.dirname(clientPath);
    final product = await _readFlavorProduct(clientPath);
    final version = await _readBuildVersion(root, product);
    final parts = version?.split('.');
    final major = int.tryParse(parts?.first ?? '');
    final minor = parts != null && parts.length > 1
        ? int.tryParse(parts[1]) ?? 0
        : 0;
    final flavor = major != null
        ? GameFlavor.fromVersion(major, minor)
        : type.defaultFlavor;

    return WowInstallation(
      id: installationId(clientPath),
      label: type.label,
      clientPath: clientPath,
      clientType: type,
      flavor: flavor,
      gameVersion: version,
    );
  }

  /// Resolves symlinked routes to one physical path, so the same client is
  /// not reported twice (e.g. `~/.steam/steam` → `~/.local/share/Steam`).
  Future<String> _canonical(String path) async {
    try {
      return await Directory(path).resolveSymbolicLinks();
    } on FileSystemException {
      return p.normalize(p.absolute(path));
    }
  }

  /// Removes stored installations that address the same physical client
  /// through different routes (duplicates persisted before paths were
  /// canonicalized). Within a group the entry with [preferredId] wins,
  /// then the one whose stored path is already canonical, then the first.
  Future<List<WowInstallation>> dedupeByPath(
    List<WowInstallation> installations, {
    String? preferredId,
  }) async {
    final byCanonical = <String, WowInstallation>{};
    final order = <String>[];
    for (final inst in installations) {
      var key = await _canonical(inst.clientPath);
      if (Platform.isWindows) key = key.toLowerCase();
      final existing = byCanonical[key];
      if (existing == null) {
        byCanonical[key] = inst;
        order.add(key);
      } else if (inst.id == preferredId ||
          (existing.id != preferredId &&
              p.equals(inst.clientPath, key) &&
              !p.equals(existing.clientPath, key))) {
        byCanonical[key] = inst;
      }
    }
    return [for (final key in order) byCanonical[key]!];
  }

  static String installationId(String clientPath) {
    var normalized = p.normalize(p.absolute(clientPath));
    if (Platform.isWindows) normalized = normalized.toLowerCase();
    return sha1.convert(utf8.encode(normalized)).toString();
  }

  Future<bool> _looksLikeClient(String clientPath) async {
    if (await File(p.join(clientPath, '.flavor.info')).exists()) return true;
    if (await Directory(p.join(clientPath, 'Interface')).exists()) return true;
    if (await Directory(p.join(clientPath, 'WTF')).exists()) return true;
    await for (final e in Directory(clientPath).list(followLinks: false)) {
      final name = p.basename(e.path).toLowerCase();
      if (name.startsWith('wow') && name.endsWith('.exe')) return true;
      if (name.startsWith('world of warcraft') && name.endsWith('.app')) {
        return true;
      }
    }
    return false;
  }

  /// `.flavor.info` holds the Battle.net product code (e.g. `wow_classic`).
  Future<String?> _readFlavorProduct(String clientPath) async {
    final file = File(p.join(clientPath, '.flavor.info'));
    if (!await file.exists()) return null;
    final lines = (await file.readAsLines())
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines.length >= 2 ? lines[1] : null;
  }

  /// `.build.info` is a pipe separated table with one row per product.
  Future<String?> _readBuildVersion(String root, String? product) async {
    final file = File(p.join(root, '.build.info'));
    if (!await file.exists() || product == null) return null;
    final lines = await file.readAsLines();
    if (lines.isEmpty) return null;
    final header = lines.first
        .split('|')
        .map((h) => h.split('!').first)
        .toList();
    final versionCol = header.indexOf('Version');
    final productCol = header.indexOf('Product');
    if (versionCol < 0 || productCol < 0) return null;
    for (final line in lines.skip(1)) {
      final cols = line.split('|');
      if (cols.length <= productCol || cols.length <= versionCol) continue;
      if (cols[productCol] == product) return cols[versionCol];
    }
    return null;
  }

  Future<List<String>> _candidateRoots() async {
    const folder = 'World of Warcraft';
    final roots = <String>[];
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';

    if (Platform.isWindows) {
      for (final drive in 'CDEFGHIJ'.split('')) {
        roots.addAll([
          '$drive:\\Program Files (x86)\\$folder',
          '$drive:\\Program Files\\$folder',
          '$drive:\\$folder',
          '$drive:\\Games\\$folder',
          '$drive:\\Battle.net\\$folder',
        ]);
      }
    } else if (Platform.isMacOS) {
      roots.addAll([
        '/Applications/$folder',
        p.join(home, 'Applications', folder),
      ]);
    } else {
      const winePaths = [
        'drive_c/Program Files (x86)/$folder',
        'drive_c/Program Files/$folder',
      ];
      final prefixes = <String>[
        p.join(home, '.wine'),
        p.join(home, 'Games', 'battlenet'),
        p.join(home, 'Games', 'battle-net'),
        p.join(home, 'Games', 'world-of-warcraft'),
        ...await _subdirs(p.join(home, 'Games')),
        ...await _subdirs(p.join(home, '.local/share/bottles/bottles')),
        ...await _subdirs(
          p.join(home, '.var/app/com.usebottles.bottles/data/bottles/bottles'),
        ),
        for (final d in await _subdirs(
          p.join(home, '.local/share/Steam/steamapps/compatdata'),
        ))
          p.join(d, 'pfx'),
        for (final d in await _subdirs(
          p.join(home, '.steam/steam/steamapps/compatdata'),
        ))
          p.join(d, 'pfx'),
      ];
      for (final prefix in prefixes) {
        for (final w in winePaths) {
          roots.add(p.join(prefix, w));
        }
      }
    }
    final existing = <String>[];
    for (final r in roots.toSet()) {
      if (await Directory(r).exists()) existing.add(r);
    }
    return existing;
  }

  Future<List<String>> _subdirs(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return const [];
    try {
      final entries = await dir.list(followLinks: false).toList();
      return [
        for (final e in entries)
          if (e is Directory) e.path,
      ];
    } on FileSystemException {
      return const [];
    }
  }
}
