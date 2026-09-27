import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/addon_service.dart';
import '../services/backup/git_backup_service.dart';
import '../services/backup/zip_backup_service.dart';
import '../services/installation_detector.dart';
import '../services/storage.dart';
import '../sources/api_client.dart';
import '../sources/source_registry.dart';
import 'settings_controller.dart';

/// Overridden in `main` once the application support directory is known.
final storageProvider = Provider<Storage>(
  (ref) => throw UnimplementedError('storageProvider must be overridden'),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  ref.onDispose(client.close);
  return client;
});

/// Rebuilt whenever keys, priority or enabled sources change.
final sourcesProvider = Provider<SourceRegistry>((ref) {
  final settings = ref.watch(settingsProvider);
  return SourceRegistry(ref.watch(apiClientProvider), settings);
});

final addonServiceProvider = Provider<AddonService>(
  (ref) => AddonService(
    api: ref.watch(apiClientProvider),
    sources: () => ref.read(sourcesProvider),
    defaultChannel: () => ref.read(settingsProvider).defaultChannel,
  ),
);

final installationDetectorProvider = Provider(
  (ref) => const InstallationDetector(),
);

final zipBackupServiceProvider = Provider((ref) => const ZipBackupService());

final gitBackupServiceProvider = Provider((ref) => const GitBackupService());
