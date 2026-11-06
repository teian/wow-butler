import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/addon.dart';
import '../core/models/game_flavor.dart';
import '../core/models/wow_installation.dart';
import 'addons_controller.dart';
import 'providers.dart';
import 'settings_controller.dart';

typedef AddonKey = ({String installationId, String addonId});

/// Fresh remote data (releases, downloads) for the detail view.
final addonRemoteProvider = FutureProvider.autoDispose
    .family<RemoteAddon?, AddonKey>((ref, key) async {
      final inst = ref
          .read(settingsProvider)
          .installations
          .where((i) => i.id == key.installationId)
          .firstOrNull;
      final addon = ref
          .read(addonsProvider(key.installationId))
          .addons
          .where((a) => a.id == key.addonId)
          .firstOrNull;
      if (inst == null || addon == null || !addon.isManaged) return null;
      final source = ref.read(sourcesProvider)[addon.source!];
      if (!source.isAvailable) return null;
      return source.getById(addon.externalId!, inst.flavor);
    });

class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    required this.channel,
    required this.date,
    required this.installed,
    required this.isNew,
    required this.lines,
  });

  final String version;
  final ReleaseChannel channel;
  final DateTime? date;
  final bool installed;
  final bool isNew;
  final List<String> lines;
}

/// Release notes of the known releases, newest first.
final changelogProvider = FutureProvider.autoDispose
    .family<List<ChangelogEntry>, AddonKey>((ref, key) async {
      final remote = await ref.watch(addonRemoteProvider(key).future);
      final addon = ref
          .read(addonsProvider(key.installationId))
          .addons
          .where((a) => a.id == key.addonId)
          .firstOrNull;
      if (remote == null || addon == null) return const [];
      final source = ref.read(sourcesProvider)[remote.source];

      final releases = [...remote.releases]
        ..sort(
          (a, b) => (b.releasedAt ?? DateTime(0)).compareTo(
            a.releasedAt ?? DateTime(0),
          ),
        );
      final installedId = addon.installedReleaseId;
      if (installedId != null && !releases.any((r) => r.id == installedId)) {
        releases.add(
          AddonRelease(
            id: installedId,
            version: addon.installedVersion ?? installedId,
            channel: addon.channel,
            downloadUrl: '',
          ),
        );
      }

      final entries = <ChangelogEntry>[];
      for (final r in releases.take(4)) {
        String? text;
        try {
          text = await source.changelog(remote.externalId, r);
        } on Object {
          text = null;
        }
        final lines = (text ?? '')
            .split('\n')
            .map((l) => l.replaceFirst(RegExp(r'^\s*([-*•]|#+)\s*'), '').trim())
            .where((l) => l.isNotEmpty)
            .take(14)
            .toList();
        entries.add(
          ChangelogEntry(
            version: r.version,
            channel: r.channel,
            date: r.releasedAt,
            installed: r.id == installedId,
            isNew: r.id == addon.latestRelease?.id && r.id != installedId,
            lines: lines,
          ),
        );
      }
      return entries;
    });

/// Description, screenshots and compatibility of an addon from "Entdecken".
final remoteDetailsProvider = FutureProvider.autoDispose
    .family<AddonDetails, RemoteAddon>((ref, addon) async {
      final flavor = ref.watch(
        selectedInstallationProvider.select((i) => i?.flavor),
      );
      final source = ref.read(sourcesProvider)[addon.source];
      return source.details(addon, flavor ?? GameFlavor.retail);
    });

/// The same source details for an installed (managed) addon, so the
/// installed detail page shows what the discover page shows.
final installedDetailsProvider = FutureProvider.autoDispose
    .family<AddonDetails?, AddonKey>((ref, key) async {
      final remote = await ref.watch(addonRemoteProvider(key).future);
      if (remote == null) return null;
      return ref.watch(remoteDetailsProvider(remote).future);
    });
