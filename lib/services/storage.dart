import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/models/addon.dart';
import '../core/models/app_settings.dart';

/// JSON file persistence below the application support directory.
class Storage {
  Storage(this.rootPath);

  final String rootPath;

  String get _settingsPath => p.join(rootPath, 'settings.json');
  String _addonsPath(String installationId) =>
      p.join(rootPath, 'addons', '$installationId.json');
  String get cachePath => p.join(rootPath, 'cache');

  Future<AppSettings> loadSettings() async {
    final json = await _readJson(_settingsPath);
    return json is Map<String, dynamic>
        ? AppSettings.fromJson(json)
        : const AppSettings();
  }

  Future<void> saveSettings(AppSettings settings) =>
      _writeJson(_settingsPath, settings.toJson());

  Future<List<InstalledAddon>> loadAddons(String installationId) async {
    final json = await _readJson(_addonsPath(installationId));
    if (json is! List) return [];
    return [
      for (final a in json) InstalledAddon.fromJson(a as Map<String, dynamic>),
    ];
  }

  Future<void> saveAddons(String installationId, List<InstalledAddon> addons) =>
      _writeJson(
        _addonsPath(installationId),
        addons.map((a) => a.toJson()).toList(),
      );

  Future<Object?> _readJson(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      return jsonDecode(await file.readAsString());
    } on FormatException {
      // Keep the corrupt file for inspection and start fresh.
      await file.rename('$path.corrupt');
      return null;
    }
  }

  /// Pending write per file, so concurrent saves cannot race on the same
  /// temp file (the loser's rename would otherwise find it gone).
  final _pendingWrites = <String, Future<void>>{};

  /// Writes to a temp file and renames it, so a crash never leaves a
  /// half-written file behind. Writes to the same path are serialized in
  /// call order.
  Future<void> _writeJson(String path, Object json) {
    final write = (_pendingWrites[path] ?? Future.value()).then(
      (_) => _writeJsonNow(path, json),
    );
    // Keep the chain usable after a failed write; errors still reach the
    // caller through the returned future.
    _pendingWrites[path] = write.catchError((_) {});
    return write;
  }

  Future<void> _writeJsonNow(String path, Object json) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final tmp = File('$path.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );
    await tmp.rename(path);
  }
}
