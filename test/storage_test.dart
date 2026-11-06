import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wow_butler/core/models/app_settings.dart';
import 'package:wow_butler/services/storage.dart';

void main() {
  late Directory tmp;
  late Storage storage;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wow_butler_storage');
    storage = Storage(tmp.path);
  });

  tearDown(() => tmp.delete(recursive: true));

  test('concurrent saves do not race on the temp file', () async {
    // Unserialized, these all write and rename the same settings.json.tmp;
    // every rename after the first then throws PathNotFoundException.
    await Future.wait([
      for (var i = 0; i < 20; i++)
        storage.saveSettings(AppSettings(updateCheckMinutes: i)),
    ]);

    final loaded = await storage.loadSettings();
    expect(loaded.updateCheckMinutes, 19, reason: 'last write wins');
    expect(
      File(p.join(tmp.path, 'settings.json.tmp')).existsSync(),
      isFalse,
      reason: 'no temp file left behind',
    );
  });

  test('settings survive a save/load round trip', () async {
    await storage.saveSettings(const AppSettings(wagoApiKey: 'key'));
    final loaded = await storage.loadSettings();
    expect(loaded.wagoApiKey, 'key');
  });
}
