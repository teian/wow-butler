import '../core/models/addon.dart';
import '../core/models/app_settings.dart';
import 'addon_source.dart';
import 'api_client.dart';
import 'curseforge_source.dart';
import 'github_source.dart';
import 'tukui_source.dart';
import 'wago_source.dart';
import 'wowinterface_source.dart';
import 'wowup_source.dart';

/// All sources configured from the current settings.
class SourceRegistry {
  SourceRegistry(ApiClient api, AppSettings settings)
    : _priority = settings.sourcePriority,
      _disabled = settings.disabledSources,
      _sources = {
        AddonSourceId.curseforge: CurseForgeSource(
          api,
          settings.curseforgeApiKey,
        ),
        AddonSourceId.wago: WagoSource(api, settings.wagoApiKey),
        AddonSourceId.wowup: WowUpSource(api),
        AddonSourceId.tukui: TukuiSource(api),
        AddonSourceId.wowinterface: WowInterfaceSource(api),
        AddonSourceId.github: GitHubSource(api, settings.githubToken),
      };

  final Map<AddonSourceId, AddonSource> _sources;
  final List<AddonSourceId> _priority;
  final Set<AddonSourceId> _disabled;

  AddonSource operator [](AddonSourceId id) => _sources[id]!;

  List<AddonSource> get all => [for (final id in _priority) _sources[id]!];

  /// Enabled and configured sources, in matching priority order.
  List<AddonSource> get active => [
    for (final s in all)
      if (!_disabled.contains(s.id) && s.isAvailable) s,
  ];
}
