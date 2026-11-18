import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wow_butler/core/models/game_flavor.dart';
import 'package:wow_butler/core/models/wow_installation.dart';
import 'package:wow_butler/services/backup/zip_backup_service.dart';

void main() {
  late Directory tmp;
  late WowInstallation inst;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wb-zip');
    final client = p.join(tmp.path, 'wow', '_retail_');
    File(p.join(client, 'WTF', 'Config.wtf'))
      ..createSync(recursive: true)
      ..writeAsStringSync('SET a "1"');
    File(p.join(client, 'WTF', 'Account', 'X', 'SV.lua.bak'))
      ..createSync(recursive: true)
      ..writeAsStringSync('old');
    File(p.join(client, 'Interface', 'AddOns', 'A', 'A.toc'))
      ..createSync(recursive: true)
      ..writeAsStringSync('## Title: A');
    inst = WowInstallation(
      id: 'abcdef0123456789',
      label: 'Retail',
      clientPath: client,
      clientType: WowClientType.retail,
      flavor: GameFlavor.retail,
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('stores archives per game variant and adopts old folders', () async {
    const service = ZipBackupService();
    final root = p.join(tmp.path, 'backups');
    // Folders of the old `<variant>-<id>` scheme, one from another machine.
    for (final old in ['retail-abcdef01', 'retail-12345678']) {
      File(
          p.join(
            root,
            old,
            '2026-01-0${old.endsWith('1') ? 1 : 2}_10-00-00.zip',
          ),
        )
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
    }
    File(p.join(root, 'classic-abcdef01', '2026-01-03_10-00-00.zip'))
      ..createSync(recursive: true)
      ..writeAsStringSync('x');

    final backup = await service.create(
      backupRoot: root,
      inst: inst,
      addons: const [],
      scope: const BackupScope(),
    );
    expect(p.dirname(backup.path), p.join(root, 'retail'));
    expect((await service.list(root, inst)).length, 3);
    expect(Directory(root).listSync().map((e) => p.basename(e.path)).toSet(), {
      'retail',
      'classic-abcdef01',
    });
  });

  test('lists archives of old folders that cannot be merged', () async {
    const service = ZipBackupService();
    final root = p.join(tmp.path, 'backups');
    // Same file name in both folders: the old one has to stay where it is.
    for (final dir in ['retail', 'retail-12345678']) {
      File(p.join(root, dir, '2026-01-01_10-00-00.zip'))
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
    }
    final paths = [for (final b in await service.list(root, inst)) b.path];
    expect(paths.map(p.dirname).map(p.basename).toSet(), {
      'retail',
      'retail-12345678',
    });
  });

  test('creates, lists, prunes and restores archives', () async {
    const service = ZipBackupService();
    final root = p.join(tmp.path, 'backups');

    final wtfOnly = await service.create(
      backupRoot: root,
      inst: inst,
      addons: const [],
      scope: const BackupScope(addons: false, wtf: true),
      suffix: 'vor-update',
    );
    expect(File(wtfOnly.path).existsSync(), isTrue);

    final full = await service.create(
      backupRoot: root,
      inst: inst,
      addons: const [],
      scope: const BackupScope(),
    );
    expect((await service.list(root, inst)).length, 2);

    // Break the installation, then restore.
    File(p.join(inst.wtfPath, 'Config.wtf')).writeAsStringSync('broken');
    Directory(p.join(inst.addonsPath, 'A')).deleteSync(recursive: true);
    await service.restore(
      backup: full,
      backupRoot: root,
      inst: inst,
      currentAddons: const [],
      scope: const BackupScope(),
    );
    expect(
      File(p.join(inst.wtfPath, 'Config.wtf')).readAsStringSync(),
      'SET a "1"',
    );
    expect(File(p.join(inst.addonsPath, 'A', 'A.toc')).existsSync(), isTrue);
    // The .bak file was never backed up but must survive the restore.
    expect(
      File(p.join(inst.wtfPath, 'Account', 'X', 'SV.lua.bak')).existsSync(),
      isTrue,
    );
    expect(await service.readManifest(full), isEmpty);
  });

  test('creates a new backup only when the WTF data changed', () async {
    const service = ZipBackupService();
    final root = p.join(tmp.path, 'backups');
    const scope = BackupScope(addons: false, wtf: true);
    Future<bool> run() async => (await service.createIfChanged(
      backupRoot: root,
      inst: inst,
      addons: const [],
      scope: scope,
      suffix: 'vor-update',
    )).created;

    expect(await run(), isTrue);
    expect(await run(), isFalse);

    // The game rewrites files on logout; same content means no new backup.
    final config = File(p.join(inst.wtfPath, 'Config.wtf'));
    config.writeAsStringSync('SET a "1"');
    config.setLastModifiedSync(DateTime(2030));
    expect(await run(), isFalse);

    // Temp files are not part of the backup.
    File(p.join(inst.wtfPath, 'x.old')).writeAsStringSync('noise');
    expect(await run(), isFalse);

    // A different scope has its own history.
    final full = await service.createIfChanged(
      backupRoot: root,
      inst: inst,
      addons: const [],
      scope: const BackupScope(),
    );
    expect(full.created, isTrue);

    config.writeAsStringSync('SET a "2"');
    await Future<void>.delayed(const Duration(seconds: 1)); // unique name
    expect(await run(), isTrue);
    expect((await service.list(root, inst)).length, 3);
  });
}
