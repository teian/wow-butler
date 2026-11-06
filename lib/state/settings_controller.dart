import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/app_settings.dart';
import '../core/models/wow_installation.dart';
import 'providers.dart';

/// Settings loaded before the first frame; overridden in `main`.
final initialSettingsProvider = Provider<AppSettings>(
  (ref) => const AppSettings(),
);

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

final selectedInstallationProvider = Provider<WowInstallation?>(
  (ref) => ref.watch(settingsProvider).selectedInstallation,
);

class SettingsController extends Notifier<AppSettings> {
  bool _dedupeScheduled = false;

  @override
  AppSettings build() {
    if (!_dedupeScheduled) {
      _dedupeScheduled = true;
      Future.microtask(_dedupeInstallations);
    }
    return ref.read(initialSettingsProvider);
  }

  /// Drops stored installations that point at the same physical client
  /// through different routes (persisted before paths were canonicalized).
  Future<void> _dedupeInstallations() async {
    final s = state;
    if (s.installations.length < 2) return;
    final kept = await ref
        .read(installationDetectorProvider)
        .dedupeByPath(s.installations, preferredId: s.selectedInstallationId);
    if (kept.length == s.installations.length) return;
    await update(
      (x) => AppSettings.fromJson({
        ...x.toJson(),
        'installations': [for (final i in kept) i.toJson()],
        'selectedInstallationId':
            kept.any((i) => i.id == x.selectedInstallationId)
            ? x.selectedInstallationId
            : kept.firstOrNull?.id,
      }),
    );
  }

  Future<void> update(AppSettings Function(AppSettings s) change) async {
    state = change(state);
    await ref.read(storageProvider).saveSettings(state);
  }

  Future<void> selectInstallation(String id) =>
      update((s) => s.copyWith(selectedInstallationId: id));

  /// Adds installations that are not known yet; returns how many were new.
  Future<int> addInstallations(List<WowInstallation> found) async {
    final known = {for (final i in state.installations) i.id};
    final fresh = found.where((i) => !known.contains(i.id)).toList();
    if (fresh.isEmpty) return 0;
    await update(
      (s) => s.copyWith(
        installations: [...s.installations, ...fresh],
        selectedInstallationId: s.selectedInstallationId ?? fresh.first.id,
      ),
    );
    return fresh.length;
  }

  Future<void> updateInstallation(WowInstallation inst) => update(
    (s) => s.copyWith(
      installations: [
        for (final i in s.installations) i.id == inst.id ? inst : i,
      ],
    ),
  );

  Future<void> removeInstallation(String id) => update((s) {
    final rest = s.installations.where((i) => i.id != id).toList();
    return AppSettings.fromJson({
      ...s.toJson(),
      'installations': rest.map((i) => i.toJson()).toList(),
      'selectedInstallationId': s.selectedInstallationId == id
          ? rest.firstOrNull?.id
          : s.selectedInstallationId,
    });
  });

  /// Detects installed clients and refreshes version info of known ones.
  Future<int> detectInstallations() async {
    final found = await ref.read(installationDetectorProvider).detect();
    for (final inst in found) {
      final known = state.installations
          .where((i) => i.id == inst.id)
          .firstOrNull;
      if (known != null && known.gameVersion != inst.gameVersion) {
        await updateInstallation(
          known.copyWith(gameVersion: inst.gameVersion, flavor: inst.flavor),
        );
      }
    }
    return addInstallations(found);
  }
}
