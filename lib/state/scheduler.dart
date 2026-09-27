import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'addons_controller.dart';
import 'backup_controller.dart';
import 'settings_controller.dart';

/// Runs periodic update checks and backups while the app is open. Kept alive
/// by being watched from the app root.
final schedulerProvider = Provider<Scheduler>((ref) {
  final scheduler = Scheduler(ref);
  ref.onDispose(scheduler.dispose);
  return scheduler;
});

class Scheduler {
  Scheduler(this._ref) {
    _startup = Timer(const Duration(seconds: 20), _tick);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  final Ref _ref;
  late final Timer _startup;
  late final Timer _timer;
  DateTime _lastUpdateCheck = DateTime.now();
  bool _running = false;

  void dispose() {
    _startup.cancel();
    _timer.cancel();
  }

  static bool _due(DateTime? last, Duration interval) =>
      last == null || DateTime.now().difference(last) >= interval;

  Future<void> _tick() async {
    if (_running) return;
    _running = true;
    try {
      final settings = _ref.read(settingsProvider);
      final backups = _ref.read(backupProvider.notifier);

      final zip = settings.zipBackup;
      if (zip.enabled &&
          zip.isConfigured &&
          zip.intervalHours > 0 &&
          _due(zip.lastRunAt, Duration(hours: zip.intervalHours))) {
        await backups.runZip(scheduled: true);
      }

      final git = settings.gitBackup;
      if (git.enabled &&
          git.isConfigured &&
          git.intervalHours > 0 &&
          _due(git.lastRunAt, Duration(hours: git.intervalHours))) {
        await backups.runGit(scheduled: true);
      }

      // The initial load already checks for updates, so the first scheduled
      // check waits a full interval.
      final minutes = settings.updateCheckMinutes;
      if (minutes > 0 && _due(_lastUpdateCheck, Duration(minutes: minutes))) {
        _lastUpdateCheck = DateTime.now();
        for (final inst in settings.installations) {
          await _ref
              .read(addonsProvider(inst.id).notifier)
              .checkUpdates(autoUpdate: true);
        }
      }
    } finally {
      _running = false;
    }
  }
}
