import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/models/addon.dart';
import '../core/models/wow_installation.dart';
import '../services/backup/git_backup_service.dart';
import '../services/backup/zip_backup_service.dart';
import 'activity_log.dart';
import 'addons_controller.dart';
import 'providers.dart';
import 'settings_controller.dart';

class BackupState {
  const BackupState({
    this.zipRunning = false,
    this.gitRunning = false,
    this.restoring = false,
  });

  final bool zipRunning;
  final bool gitRunning;
  final bool restoring;

  bool get busy => zipRunning || gitRunning || restoring;
}

final backupProvider = NotifierProvider<BackupController, BackupState>(
  BackupController.new,
);

/// Where zip archives go: the configured folder, or the app data folder so
/// the pre-update WTF backups work without any setup.
final zipBackupRootProvider = Provider<String>((ref) {
  final dir = ref.watch(settingsProvider.select((s) => s.zipBackup.directory));
  if (dir != null && dir.isNotEmpty) return dir;
  return p.join(ref.watch(storageProvider).rootPath, 'backups');
});

final zipBackupsProvider = FutureProvider.family<List<ZipBackup>, String>((
  ref,
  installationId,
) async {
  final settings = ref.watch(settingsProvider);
  final inst = settings.installations
      .where((i) => i.id == installationId)
      .firstOrNull;
  if (inst == null) return const [];
  return ref
      .read(zipBackupServiceProvider)
      .list(ref.watch(zipBackupRootProvider), inst);
});

final gitHistoryProvider = FutureProvider.family<List<GitCommit>, String>((
  ref,
  installationId,
) async {
  final settings = ref.watch(settingsProvider);
  final inst = settings.installations
      .where((i) => i.id == installationId)
      .firstOrNull;
  if (!settings.gitBackup.isConfigured || inst == null) return const [];
  return ref.read(gitBackupServiceProvider).history(settings.gitBackup, inst);
});

final gitVersionProvider = FutureProvider<String?>(
  (ref) => ref.read(gitBackupServiceProvider).gitVersion(),
);

class BackupController extends Notifier<BackupState> {
  @override
  BackupState build() => const BackupState();

  ActivityLog get _log => ref.read(activityProvider.notifier);

  /// Addons of [inst]; falls back to the stored list when the installation
  /// has not been opened in this session yet.
  Future<List<InstalledAddon>> _addonsOf(WowInstallation inst) async {
    final live = ref.read(addonsProvider(inst.id));
    if (live.loaded) return live.addons;
    return ref.read(storageProvider).loadAddons(inst.id);
  }

  /// Zip backup of the given installations (default: all).
  Future<void> runZip({
    List<WowInstallation>? only,
    bool scheduled = false,
  }) async {
    final settings = ref.read(settingsProvider);
    final cfg = settings.zipBackup;
    final root = ref.read(zipBackupRootProvider);
    if (state.zipRunning) return;
    state = BackupState(zipRunning: true, gitRunning: state.gitRunning);
    final service = ref.read(zipBackupServiceProvider);
    try {
      for (final inst in only ?? settings.installations) {
        try {
          final result = await service.createIfChanged(
            backupRoot: root,
            inst: inst,
            addons: await _addonsOf(inst),
            scope: BackupScope(addons: cfg.includeAddons, wtf: cfg.includeWtf),
            suffix: scheduled ? null : 'manuell',
          );
          if (result.created) {
            await service.prune(root, inst, cfg.retention);
            _log.success(
              'ZIP-Backup ${inst.label}: ${result.backup.fileName}',
              toast: !scheduled,
            );
          } else {
            _log.info(
              'ZIP-Backup ${inst.label}: keine Änderungen seit '
              '${result.backup.fileName}',
              toast: !scheduled,
            );
          }
        } catch (e) {
          _log.error('ZIP-Backup ${inst.label} fehlgeschlagen: $e');
        }
        ref.invalidate(zipBackupsProvider(inst.id));
      }
      await ref
          .read(settingsProvider.notifier)
          .update(
            (s) => s.copyWith(
              zipBackup: s.zipBackup.copyWith(lastRunAt: DateTime.now()),
            ),
          );
    } finally {
      state = BackupState(gitRunning: state.gitRunning);
    }
  }

  Future<void> runGit({
    List<WowInstallation>? only,
    bool scheduled = false,
  }) async {
    final settings = ref.read(settingsProvider);
    final cfg = settings.gitBackup;
    if (!cfg.isConfigured || state.gitRunning) return;
    state = BackupState(gitRunning: true, zipRunning: state.zipRunning);
    final service = ref.read(gitBackupServiceProvider);
    try {
      for (final inst in only ?? settings.installations) {
        try {
          final outcome = await service.backup(
            settings: cfg,
            inst: inst,
            addons: await _addonsOf(inst),
          );
          if (outcome.commit == null) {
            _log.info(
              'Git-Backup ${inst.label}: keine Änderungen',
              toast: !scheduled,
            );
          } else {
            _log.success(
              'Git-Backup ${inst.label}: ${outcome.commit!.substring(0, 8)}'
              '${outcome.pushed ? ' (gepusht)' : ''}',
              toast: !scheduled,
            );
          }
          if (outcome.pushError != null) {
            _log.warning('Git-Push fehlgeschlagen: ${outcome.pushError}');
          }
        } catch (e) {
          _log.error('Git-Backup ${inst.label} fehlgeschlagen: $e');
        }
        ref.invalidate(gitHistoryProvider(inst.id));
      }
      await ref
          .read(settingsProvider.notifier)
          .update(
            (s) => s.copyWith(
              gitBackup: s.gitBackup.copyWith(lastRunAt: DateTime.now()),
            ),
          );
    } finally {
      state = BackupState(zipRunning: state.zipRunning);
    }
  }

  Future<void> push() async {
    final cfg = ref.read(settingsProvider).gitBackup;
    try {
      await ref.read(gitBackupServiceProvider).push(cfg);
      _log.success('Git-Repository gepusht');
    } catch (e) {
      _log.error('Git-Push fehlgeschlagen: $e');
    }
  }

  Future<void> restoreZip(
    WowInstallation inst,
    ZipBackup backup,
    BackupScope scope,
  ) async {
    final dir = ref.read(zipBackupRootProvider);
    await _restoring(
      inst,
      () async => ref
          .read(zipBackupServiceProvider)
          .restore(
            backup: backup,
            backupRoot: dir,
            inst: inst,
            currentAddons: await _addonsOf(inst),
            scope: scope,
          ),
    );
    ref.invalidate(zipBackupsProvider(inst.id));
  }

  Future<void> restoreGit(
    WowInstallation inst,
    GitCommit commit,
    BackupScope scope,
  ) async {
    final cfg = ref.read(settingsProvider).gitBackup;
    await _restoring(
      inst,
      () async => ref
          .read(gitBackupServiceProvider)
          .restore(
            settings: cfg,
            inst: inst,
            currentAddons: await _addonsOf(inst),
            commit: commit.hash,
            scope: scope,
          ),
    );
    ref.invalidate(gitHistoryProvider(inst.id));
  }

  Future<void> _restoring(
    WowInstallation inst,
    Future<void> Function() restore,
  ) async {
    state = const BackupState(restoring: true);
    try {
      await restore();
      _log.success('Wiederherstellung für ${inst.label} abgeschlossen');
      await ref.read(addonsProvider(inst.id).notifier).rescan();
    } catch (e) {
      _log.error('Wiederherstellung fehlgeschlagen: $e');
    } finally {
      state = const BackupState();
    }
  }
}
