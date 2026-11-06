// Debug helper: runs a full read-only sync for the selected installation.
// Usage: dart run tool/debug_sync.dart <app data dir>
// Nothing is written; the result is only printed.
// ignore_for_file: avoid_print
import 'package:wow_butler/core/models/wow_installation.dart';
import 'package:wow_butler/services/addon_service.dart';
import 'package:wow_butler/services/storage.dart';
import 'package:wow_butler/sources/api_client.dart';
import 'package:wow_butler/sources/source_registry.dart';

Future<void> main(List<String> args) async {
  final storage = Storage(args.first);
  final settings = await storage.loadSettings();
  final inst = settings.installations
      .where((i) => i.id == settings.selectedInstallationId)
      .first;
  print('installation: ${inst.label} (${inst.flavor.name})');

  final stored = await storage.loadAddons(inst.id);
  print('stored: ${stored.length} entries, '
      '${stored.where((a) => a.isManaged).length} managed');

  final api = ApiClient();
  final registry = SourceRegistry(api, settings);
  final service = AddonService(
    api: api,
    sources: () => registry,
    defaultChannel: () => ReleaseChannel.stable,
  );

  final result = await service.sync(inst, stored);
  for (final w in result.warnings) {
    print('warning: $w');
  }
  for (final a in result.addons) {
    print(
      '  ${a.name} -> ${a.source?.name ?? 'LOKAL'}'
      ' (${a.folders.length} Ordner, v=${a.installedVersion ?? '?'}'
      ', update=${a.latestRelease?.version ?? '-'})',
    );
  }
  api.close();
}
