import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/addon.dart';
import '../core/models/wow_installation.dart';
import '../core/util/limiter.dart';
import '../services/backup/zip_backup_service.dart';
import 'activity_log.dart';
import 'backup_controller.dart';
import 'providers.dart';
import 'settings_controller.dart';

enum QueueStage { waiting, downloading, extracting, done, failed }

/// One addon in the update queue shown at the bottom of the window.
class QueueItem {
  const QueueItem({
    required this.addonId,
    required this.name,
    required this.toVersion,
    this.progress = 0,
    this.stage = QueueStage.waiting,
    this.error,
  });

  final String addonId;
  final String name;
  final String toVersion;
  final double progress;
  final QueueStage stage;
  final String? error;

  bool get finished => stage == QueueStage.done || stage == QueueStage.failed;

  QueueItem copyWith({double? progress, QueueStage? stage, String? error}) =>
      QueueItem(
        addonId: addonId,
        name: name,
        toVersion: toVersion,
        progress: progress ?? this.progress,
        stage: stage ?? this.stage,
        error: error ?? this.error,
      );
}

class AddonsState {
  const AddonsState({
    this.addons = const [],
    this.loaded = false,
    this.scanning = false,
    this.checking = false,
    this.installing = const {},
    this.queue = const [],
    this.backupMessage,
    this.lastChecked,
  });

  final List<InstalledAddon> addons;
  final bool loaded;
  final bool scanning;
  final bool checking;

  /// Remote key -> progress `0..1` of installs started from "Entdecken".
  final Map<String, double> installing;
  final List<QueueItem> queue;

  /// Where the WTF folder was saved before the current update run.
  final String? backupMessage;
  final DateTime? lastChecked;

  /// Addons the app can update itself; updates that are only available on
  /// the website are left out, so (automatic) batch updates skip them.
  List<InstalledAddon> get updatable =>
      addons.where((a) => a.hasUpdate && !a.updateNeedsWebsite).toList();

  QueueItem? queued(String addonId) =>
      queue.where((q) => q.addonId == addonId && !q.finished).firstOrNull;

  bool get queueDone => queue.isNotEmpty && queue.every((q) => q.finished);

  AddonsState copyWith({
    List<InstalledAddon>? addons,
    bool? loaded,
    bool? scanning,
    bool? checking,
    Map<String, double>? installing,
    List<QueueItem>? queue,
    String? backupMessage,
    bool clearBackupMessage = false,
    DateTime? lastChecked,
  }) => AddonsState(
    addons: addons ?? this.addons,
    loaded: loaded ?? this.loaded,
    scanning: scanning ?? this.scanning,
    checking: checking ?? this.checking,
    installing: installing ?? this.installing,
    queue: queue ?? this.queue,
    backupMessage: clearBackupMessage
        ? null
        : backupMessage ?? this.backupMessage,
    lastChecked: lastChecked ?? this.lastChecked,
  );
}

final addonsProvider =
    NotifierProvider.family<AddonsController, AddonsState, String>(
      AddonsController.new,
    );

/// Addons of one installation. All mutations of the addon list run through a
/// queue, so concurrent installs never overwrite each other's results.
class AddonsController extends Notifier<AddonsState> {
  AddonsController(this.installationId);

  final String installationId;
  Future<void> _serialQueue = Future.value();

  /// Bounds parallel downloads (installs and updates) to the setting.
  late final _downloads = Limiter(
    () => ref.read(settingsProvider).parallelDownloads,
  );
  bool _started = false;

  @override
  AddonsState build() {
    if (!_started) {
      _started = true;
      Future.microtask(_initialLoad);
    }
    return const AddonsState();
  }

  WowInstallation? get _inst => ref
      .read(settingsProvider)
      .installations
      .where((i) => i.id == installationId)
      .firstOrNull;

  ActivityLog get _log => ref.read(activityProvider.notifier);

  Future<void> _initialLoad() async {
    final stored = await ref.read(storageProvider).loadAddons(installationId);
    state = state.copyWith(addons: stored, loaded: true);
    await rescan();
    if (ref.read(settingsProvider).checkOnStart) {
      await checkUpdates(autoUpdate: true);
    }
  }

  Future<T> _serial<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _serialQueue = _serialQueue.then((_) async {
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<void> _commit(List<InstalledAddon> addons) async {
    state = state.copyWith(addons: addons);
    await ref.read(storageProvider).saveAddons(installationId, addons);
  }

  /// Rescans the AddOns folder. With [rematch], every addon is identified
  /// again from scratch.
  Future<void> rescan({bool rematch = false}) => _serial(() async {
    final inst = _inst;
    if (inst == null) return;
    state = state.copyWith(scanning: true);
    try {
      final result = await ref
          .read(addonServiceProvider)
          .sync(inst, state.addons, rematch: rematch);
      await _commit(result.addons);
      for (final w in result.warnings) {
        _log.warning(w, toast: false);
      }
    } catch (e) {
      _log.error('Scan fehlgeschlagen (${inst.label}): $e');
    } finally {
      state = state.copyWith(scanning: false);
    }
  });

  /// Refreshes the latest releases. With [autoUpdate], addons eligible for
  /// automatic updates are updated right away.
  Future<void> checkUpdates({bool autoUpdate = false}) async {
    final inst = _inst;
    if (inst == null || state.checking) return;
    state = state.copyWith(checking: true);
    try {
      await _serial(() async {
        final result = await ref
            .read(addonServiceProvider)
            .checkUpdates(inst, state.addons);
        await _commit(result.addons);
        for (final w in result.warnings) {
          _log.warning(w, toast: false);
        }
      });
      state = state.copyWith(lastChecked: DateTime.now());
    } catch (e) {
      _log.error('Update-Prüfung fehlgeschlagen: $e');
    } finally {
      state = state.copyWith(checking: false);
    }
    if (autoUpdate && ref.read(settingsProvider).autoUpdate) {
      await updateMany(state.updatable.where((a) => a.autoUpdate).toList());
    }
  }

  Future<void> update(InstalledAddon addon) => updateMany([addon]);

  Future<void> updateAll() => updateMany(state.updatable);

  /// Queues updates for [addons]. The WTF folder is saved once per run
  /// beforehand when enabled.
  Future<void> updateMany(List<InstalledAddon> addons) async {
    final inst = _inst;
    if (inst == null) return;
    final targets = addons
        .where((a) => a.hasUpdate && state.queued(a.id) == null)
        .toList();
    if (targets.isEmpty) return;

    final base = state.queueDone ? const <QueueItem>[] : state.queue;
    state = state.copyWith(
      queue: [
        ...base,
        for (final a in targets)
          QueueItem(
            addonId: a.id,
            name: a.name,
            toVersion: a.latestRelease?.version ?? '?',
          ),
      ],
      clearBackupMessage: state.queueDone,
    );

    await _backupWtfBeforeUpdate(inst);
    // Downloads run in parallel up to the configured limit; moving the files
    // into AddOns happens one addon at a time.
    await Future.wait([
      for (final addon in targets) _runQueued(inst, addon, force: false),
    ]);
  }

  /// Installs the current release again, e.g. to repair modified files.
  Future<void> reinstall(InstalledAddon addon) async {
    final inst = _inst;
    if (inst == null || state.queued(addon.id) != null) return;
    final base = state.queueDone ? const <QueueItem>[] : state.queue;
    state = state.copyWith(
      queue: [
        ...base,
        QueueItem(
          addonId: addon.id,
          name: addon.name,
          toVersion: addon.installedVersion ?? '?',
        ),
      ],
    );
    await _runQueued(inst, addon, force: true);
  }

  Future<void> _runQueued(
    WowInstallation inst,
    InstalledAddon addon, {
    required bool force,
  }) async {
    void stage(QueueStage stage, {double? progress, String? error}) {
      state = state.copyWith(
        queue: [
          for (final q in state.queue)
            q.addonId == addon.id && !q.finished
                ? q.copyWith(stage: stage, progress: progress, error: error)
                : q,
        ],
      );
    }

    void progress(double v) => stage(
      v < 0.8 ? QueueStage.downloading : QueueStage.extracting,
      progress: v,
    );

    InstalledAddon current() =>
        state.addons.where((a) => a.id == addon.id).firstOrNull ?? addon;

    final service = ref.read(addonServiceProvider);
    try {
      final prepared = await _downloads.run(() async {
        stage(QueueStage.downloading, progress: 0.02);
        final plan = await service.planUpdate(inst, current(), force: force);
        if (plan.upToDate) {
          await _serial(
            () => _commit(
              service.markUpToDate(state.addons, current(), plan.release),
            ),
          );
          return null;
        }
        return service.prepare(
          inst,
          remote: plan.remote,
          release: plan.release,
          onProgress: progress,
        );
      });
      if (prepared != null) {
        await _serial(() async {
          final updated = await service.apply(
            inst,
            state.addons,
            prepared,
            channel: current().channel,
            onProgress: progress,
          );
          await _commit(updated);
        });
      }
      stage(QueueStage.done, progress: 1);
    } catch (e) {
      stage(QueueStage.failed, progress: 1, error: '$e');
      _log.error('${addon.name}: $e');
    }
  }

  Future<void> _backupWtfBeforeUpdate(WowInstallation inst) async {
    final settings = ref.read(settingsProvider);
    if (!settings.backupBeforeUpdate) return;
    final root = ref.read(zipBackupRootProvider);
    try {
      final result = await ref
          .read(zipBackupServiceProvider)
          .createIfChanged(
            backupRoot: root,
            inst: inst,
            addons: state.addons,
            scope: const BackupScope(addons: false, wtf: true),
            suffix: 'vor-update',
          );
      state = state.copyWith(
        backupMessage: result.created
            ? 'WTF gesichert → ${result.backup.path}'
            : 'WTF unverändert – letzte Sicherung ${result.backup.fileName}',
      );
    } catch (e) {
      _log.warning('WTF-Sicherung vor dem Update fehlgeschlagen: $e');
    }
  }

  void clearQueue() {
    if (!state.queueDone) return;
    state = state.copyWith(queue: const [], clearBackupMessage: true);
  }

  /// Installs [release]; returns whether it succeeded (failures are logged).
  /// With [archive], the release is taken from that file (downloaded by the
  /// user in the browser) instead of being downloaded.
  Future<bool> install(
    RemoteAddon remote,
    AddonRelease release, {
    ReleaseChannel? channel,
    File? archive,
  }) async {
    final inst = _inst;
    if (inst == null) return false;
    void progress(double? v) {
      final next = {...state.installing};
      v == null ? next.remove(remote.key) : next[remote.key] = v;
      state = state.copyWith(installing: next);
    }

    progress(0);
    final service = ref.read(addonServiceProvider);
    try {
      final prepared = archive != null
          ? await service.prepareFile(
              inst,
              remote: remote,
              release: release,
              archive: archive,
              onProgress: progress,
            )
          : await _downloads.run(
              () => service.prepare(
                inst,
                remote: remote,
                release: release,
                onProgress: progress,
              ),
            );
      await _serial(() async {
        final updated = await service.apply(
          inst,
          state.addons,
          prepared,
          channel: channel,
          onProgress: progress,
        );
        await _commit(updated);
      });
      _log.success('${remote.name} ${release.version} installiert');
      return true;
    } catch (e) {
      _log.error('${remote.name}: $e');
      return false;
    } finally {
      progress(null);
    }
  }

  Future<void> uninstall(InstalledAddon addon) => uninstallMany([addon]);

  Future<void> uninstallMany(List<InstalledAddon> addons) async {
    final inst = _inst;
    if (inst == null || addons.isEmpty) return;
    try {
      await _serial(() async {
        var list = state.addons;
        for (final addon in addons) {
          list = await ref
              .read(addonServiceProvider)
              .uninstall(inst, list, addon);
        }
        await _commit(list);
      });
      _log.info(
        addons.length == 1
            ? '${addons.first.name} deinstalliert'
            : '${addons.length} Addons deinstalliert',
      );
    } catch (e) {
      _log.error('Deinstallation fehlgeschlagen: $e');
    }
  }

  Future<void> setChannel(InstalledAddon addon, ReleaseChannel channel) async {
    await _modify([addon.id], (a) => a.copyWith(channel: channel));
    await checkUpdates();
  }

  Future<void> setAutoUpdate(InstalledAddon addon, bool value) =>
      _modify([addon.id], (a) => a.copyWith(autoUpdate: value));

  Future<void> setIgnored(Iterable<String> ids, bool value) =>
      _modify(ids, (a) => a.copyWith(ignored: value));

  Future<void> setPinned(Iterable<String> ids, bool value) =>
      _modify(ids, (a) => a.copyWith(pinned: value));

  /// Marks local addons as distributed only by subscription or external
  /// software; managed addons are left alone.
  Future<void> setExternal(Iterable<String> ids, bool value) =>
      _modify(ids, (a) => a.isManaged ? a : a.copyWith(external: value));

  /// Links an installed addon to [remote] without reinstalling it and
  /// makes it the addon's primary source; the previous source stays as an
  /// alternative. The installed release is recognized by version when
  /// possible; otherwise the next update installs the current release.
  Future<void> assignSource(InstalledAddon addon, RemoteAddon remote) async {
    final service = ref.read(addonServiceProvider);
    await _modify([addon.id], (a) => service.relink(a, remote, manual: true));
    _log.success('${remote.name} ist jetzt ${remote.source.label} zugeordnet');
  }

  /// Makes [alternative] the primary source of [addon].
  Future<void> setPrimarySource(
    InstalledAddon addon,
    AddonAlternative alternative,
  ) async {
    final inst = _inst;
    if (inst == null) return;
    final source = ref.read(sourcesProvider)[alternative.source];
    if (!source.isAvailable) {
      _log.error('${source.id.label}: ${source.unavailableReason}');
      return;
    }
    try {
      final remote = await source.getById(alternative.externalId, inst.flavor);
      if (remote == null) {
        _log.error(
          '${alternative.name} ist auf ${source.id.label} nicht mehr '
          'verfügbar.',
        );
        return;
      }
      await assignSource(addon, remote);
    } catch (e) {
      _log.error('${addon.name}: $e');
    }
  }

  /// Lets syncs switch [addon] to another source again, as if the user had
  /// never picked one.
  Future<void> resetPrimarySource(InstalledAddon addon) async {
    await _modify([addon.id], (a) => a.copyWith(manualSource: false));
    await rescan();
  }

  /// Searches the other sources for [addon] and stores the hits as
  /// alternatives; returns how many alternatives it has afterwards.
  Future<int> findAlternatives(InstalledAddon addon) async {
    final inst = _inst;
    if (inst == null) return 0;
    try {
      final found = await ref
          .read(addonServiceProvider)
          .withAlternatives(inst, addon);
      await _modify(
        [addon.id],
        (a) => a.copyWith(
          alternatives: found.alternatives,
          alternativesCheckedAt: found.alternativesCheckedAt,
        ),
      );
      return found.alternatives.length;
    } catch (e) {
      _log.error('${addon.name}: $e');
      return 0;
    }
  }

  /// Installs the addon archive [archive] (e.g. a zip downloaded by hand)
  /// and identifies it with the next scan.
  Future<bool> installArchive(File archive) async {
    final inst = _inst;
    if (inst == null) return false;
    try {
      final folders = await _serial(
        () => ref.read(addonServiceProvider).installArchive(inst, archive),
      );
      await rescan();
      _log.success('${folders.join(', ')} installiert');
      return true;
    } catch (e) {
      _log.error('$e');
      return false;
    }
  }

  Future<void> _modify(
    Iterable<String> ids,
    InstalledAddon Function(InstalledAddon) f,
  ) {
    final set = ids.toSet();
    return _serial(
      () => _commit([
        for (final a in state.addons) set.contains(a.id) ? f(a) : a,
      ]),
    );
  }

  /// Installs every managed addon of [manifest] that is missing, e.g. after
  /// restoring settings from a backup that did not contain addon files.
  Future<int> installFromManifest(List<InstalledAddon> manifest) async {
    final inst = _inst;
    if (inst == null) return 0;
    final registry = ref.read(sourcesProvider);

    Future<bool> restore(InstalledAddon entry) async {
      final source = registry[entry.source!];
      if (!source.isAvailable) return false;
      try {
        final remote = await source.getById(entry.externalId!, inst.flavor);
        final release = remote?.latestFor(entry.channel);
        if (remote == null || release == null) return false;
        return await install(remote, release, channel: entry.channel);
      } catch (e) {
        _log.error('${entry.name}: $e');
        return false;
      }
    }

    // [install] bounds the parallel downloads.
    final results = await Future.wait([
      for (final entry in manifest.where((a) => a.isManaged))
        if (!state.addons.any((a) => a.remoteKey == entry.remoteKey))
          restore(entry),
    ]);
    return results.where((ok) => ok).length;
  }
}
