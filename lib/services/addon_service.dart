import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import '../core/external_addons.dart';
import '../core/models/addon.dart';
import '../core/models/addon_folder.dart';
import '../core/models/wow_installation.dart';
import '../core/util/archive_extract.dart';
import '../core/util/ids.dart';
import '../sources/addon_source.dart';
import '../sources/api_client.dart';
import '../sources/source_registry.dart';
import 'addon_scanner.dart';

class AddonException implements Exception {
  AddonException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Result of an operation that can partially fail, e.g. when one source is
/// unreachable while the others answer.
class AddonsResult {
  const AddonsResult(this.addons, [this.warnings = const []]);

  final List<InstalledAddon> addons;
  final List<String> warnings;
}

typedef ProgressCallback = void Function(double progress);

/// Scans, matches, updates, installs and removes addons of an installation.
/// Stateless: callers pass the current addon list and persist the result.
class AddonService {
  AddonService({
    required this.api,
    required this.sources,
    required this.defaultChannel,
    bool Function()? preferDownloadable,
  }) : preferDownloadable = preferDownloadable ?? (() => true);

  final ApiClient api;
  final SourceRegistry Function() sources;

  /// Channel for addons that have none yet (fresh installs and matches).
  final ReleaseChannel Function() defaultChannel;

  /// Whether website-only addons switch to another source automatically
  /// ([AppSettings.preferDownloadableSource]).
  final bool Function() preferDownloadable;

  /// Reconciles [stored] with the folders on disk and identifies unknown
  /// folders through the active sources, in priority order.
  ///
  /// With [rematch] all addons are identified again from scratch; per-addon
  /// preferences (channel, auto update, ignore) are kept.
  Future<AddonsResult> sync(
    WowInstallation inst,
    List<InstalledAddon> stored, {
    bool rematch = false,
  }) async {
    final folders = await scanAddonFolders(inst.addonsPath, inst.flavor);
    final byName = {for (final f in folders) f.name.toLowerCase(): f};
    final warnings = <String>[];

    final previousByFolder = {
      for (final a in stored) a.folders.first.toLowerCase(): a,
    };
    final result = <InstalledAddon>[];
    if (!rematch) {
      for (final addon in stored) {
        // Entries without a source are re-identified on every sync: a new
        // key or source may be able to match them now. So are entries whose
        // source only allows website downloads, in case another source has
        // them, unless the user picked that source. Preferences survive
        // through [previousByFolder].
        if (!addon.isManaged) continue;
        if (!addon.downloadsAllowed && !addon.manualSource) continue;
        final existing = addon.folders
            .map((f) => byName[f.toLowerCase()]?.name)
            .nonNulls
            .toList();
        if (existing.isEmpty) continue;
        result.add(addon.copyWith(folders: existing));
      }
    }

    final owned = {
      for (final a in result)
        for (final f in a.folders) f.toLowerCase(),
    };
    var remaining = folders
        .where((f) => f.hasAnyToc && !owned.contains(f.name.toLowerCase()))
        .toList();

    /// Claims the still free folders of [folderNames]; returns the claimed
    /// names in their original spelling.
    List<String> claim(Iterable<String> folderNames) {
      final free = {for (final f in remaining) f.name.toLowerCase(): f.name};
      final taken = folderNames
          .map((f) => free[f.toLowerCase()])
          .nonNulls
          .toList();
      final takenLower = taken.map((t) => t.toLowerCase()).toSet();
      remaining = remaining
          .where((f) => !takenLower.contains(f.name.toLowerCase()))
          .toList();
      return taken;
    }

    void take(AddonMatch match) {
      final taken = claim(match.folders);
      if (taken.isEmpty) return;
      final previous = previousByFolder[taken.first.toLowerCase()];
      result.add(_fromMatch(inst, match, taken, byName, previous));
    }

    // Matches the app cannot download from are only used when no other
    // source knows the addon.
    final websiteOnly = <AddonMatch>[];
    for (final source in sources().active.where((s) => s.supportsMatching)) {
      if (remaining.where((f) => f.hasToc).isEmpty) break;
      final List<AddonMatch> matches;
      try {
        matches = await source.match(remaining, inst.flavor);
      } on Object catch (e) {
        warnings.add('${source.id.label}: $e');
        continue;
      }
      for (final match in matches) {
        if (match.addon.downloadsAllowed) {
          take(match);
        } else {
          websiteOnly.add(match);
        }
      }
    }
    for (final match in websiteOnly) {
      // Another source took the folders: remember this one as alternative.
      final first = match.folders.first.toLowerCase();
      final owner = result.indexWhere(
        (a) => a.folders.any((f) => f.toLowerCase() == first),
      );
      if (owner < 0) {
        take(match);
        continue;
      }
      final addon = result[owner];
      if (addon.remoteKey == match.addon.key) continue;
      result[owner] = addon.copyWith(
        alternatives: _withAlternative(
          addon.alternatives,
          AddonAlternative.of(match.addon),
        ),
      );
    }

    // A website-only assignment (e.g. made by hand) that no source confirmed
    // again stays as it was instead of falling back to a local addon.
    if (!rematch) {
      for (final addon in stored) {
        if (!addon.isManaged || addon.downloadsAllowed) continue;
        final taken = claim(addon.folders);
        if (taken.isNotEmpty) result.add(addon.copyWith(folders: taken));
      }
    }

    _addUnmanaged(result, remaining, previousByFolder);
    _refreshFromToc(result, byName);
    await _fallBackToDownloadable(inst, result, warnings);
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return AddonsResult(result, warnings);
  }

  InstalledAddon _fromMatch(
    WowInstallation inst,
    AddonMatch match,
    List<String> folders,
    Map<String, AddonFolder> byName,
    InstalledAddon? previous,
  ) {
    final toc = byName[folders.first.toLowerCase()]?.toc;
    final installed = match.installedRelease;
    var channel = previous?.channel ?? defaultChannel();
    if (installed != null && installed.channel.index > channel.index) {
      channel = installed.channel;
    }
    final remote = match.addon;
    // A TOC built for another game version does not tell the installed
    // version of this client's build; only a matched release does.
    final tocVersion = (toc?.builtForOtherFlavor(inst.flavor) ?? false)
        ? null
        : toc?.version;
    return InstalledAddon(
      id: previous?.id ?? newId(),
      name: remote.name,
      folders: folders,
      source: remote.source,
      externalId: remote.externalId,
      author: remote.author ?? toc?.author,
      summary: remote.summary ?? toc?.notes,
      thumbnailUrl: remote.thumbnailUrl,
      websiteUrl: remote.websiteUrl,
      installedVersion: tocVersion ?? installed?.version,
      installedReleaseId: installed?.id,
      downloadsAllowed: remote.downloadsAllowed,
      alternatives: [
        for (final a in previous?.alternatives ?? const <AddonAlternative>[])
          if (a.key != remote.key) a,
      ],
      alternativesCheckedAt: previous?.alternativesCheckedAt,
      installedAt: previous?.installedAt,
      channel: channel,
      autoUpdate: previous?.autoUpdate ?? true,
      pinned: previous?.pinned ?? false,
      ignored: previous?.ignored ?? false,
      latestRelease: remote.latestFor(channel),
      interfaces: toc?.interfaces ?? const [],
    );
  }

  /// Unidentified folders become local addons. Folders that are obviously
  /// modules of another addon (`Foo_Options` depending on `Foo`) are
  /// attached to it instead of cluttering the list.
  void _addUnmanaged(
    List<InstalledAddon> result,
    List<AddonFolder> remaining,
    Map<String, InstalledAddon> previousByFolder,
  ) {
    final sorted = [...remaining]
      ..sort((a, b) => a.name.length.compareTo(b.name.length));
    for (final folder in sorted) {
      final lower = folder.name.toLowerCase();
      final deps = {
        for (final d in folder.toc?.dependencies ?? const <String>[])
          d.toLowerCase(),
      };
      final parentIndex = result.indexWhere((a) {
        final primary = a.folders.first.toLowerCase();
        final isPrefix =
            lower.startsWith('${primary}_') ||
            lower.startsWith('$primary-') ||
            lower.startsWith('$primary.');
        return isPrefix &&
            (deps.contains(primary) || (folder.toc?.isLoadOnDemand ?? false));
      });
      if (parentIndex >= 0) {
        final parent = result[parentIndex];
        result[parentIndex] = parent.copyWith(
          folders: [...parent.folders, folder.name],
        );
        continue;
      }
      final previous = previousByFolder[lower];
      result.add(
        InstalledAddon(
          id: previous?.id ?? newId(),
          name: folder.toc?.title ?? folder.name,
          folders: [folder.name],
          ignored: previous?.ignored ?? false,
          pinned: previous?.pinned ?? false,
          external:
              (previous?.external ?? false) ||
              isKnownExternalAddon(folder.name),
        ),
      );
    }
  }

  /// Local addons have no remote metadata, so the TOC is the source of truth.
  void _refreshFromToc(
    List<InstalledAddon> addons,
    Map<String, AddonFolder> byName,
  ) {
    for (var i = 0; i < addons.length; i++) {
      final addon = addons[i];
      final toc = byName[addon.folders.first.toLowerCase()]?.toc;
      if (toc == null) continue;
      addons[i] = addon.isManaged
          ? addon.copyWith(interfaces: toc.interfaces)
          : addon.copyWith(
              name: toc.title,
              author: toc.author,
              summary: toc.notes,
              installedVersion: toc.version,
              websiteUrl: toc.website,
              interfaces: toc.interfaces,
            );
    }
  }

  /// Website-only addons switch to another source that publishes them and
  /// allows downloads, in source priority order. Other sources are searched
  /// by name when none is known yet. Addons whose source the user picked
  /// stay as they are.
  Future<void> _fallBackToDownloadable(
    WowInstallation inst,
    List<InstalledAddon> addons,
    List<String> warnings,
  ) async {
    if (!preferDownloadable()) return;
    var searches = 0;
    for (var i = 0; i < addons.length; i++) {
      var addon = addons[i];
      if (!addon.isManaged || addon.downloadsAllowed || addon.manualSource) {
        continue;
      }
      final checked = addon.alternativesCheckedAt;
      final stale =
          checked == null ||
          DateTime.now().difference(checked) > _alternativesMaxAge;
      if (stale && searches < _maxAlternativeSearches) {
        searches++;
        addon = await withAlternatives(inst, addon, warnings: warnings);
        addons[i] = addon;
      }
      final remote = await _downloadableAlternative(inst, addon);
      if (remote != null) addons[i] = relink(addon, remote);
    }
  }

  /// Website-only addons searched by name per sync.
  static const _maxAlternativeSearches = 10;

  /// How long a name search for alternatives stays valid.
  static const _alternativesMaxAge = Duration(days: 7);

  /// The first alternative of [addon] (in source priority order) that
  /// allows downloads and has a release for its channel.
  Future<RemoteAddon?> _downloadableAlternative(
    WowInstallation inst,
    InstalledAddon addon,
  ) async {
    final registry = sources();
    final active = registry.active.map((s) => s.id).toList();
    final candidates =
        addon.alternatives
            .where((a) => a.downloadsAllowed && active.contains(a.source))
            .toList()
          ..sort(
            (a, b) =>
                active.indexOf(a.source).compareTo(active.indexOf(b.source)),
          );
    for (final alt in candidates) {
      try {
        final remote = await registry[alt.source].getById(
          alt.externalId,
          inst.flavor,
        );
        if (remote != null &&
            remote.downloadsAllowed &&
            remote.latestFor(addon.channel) != null) {
          return remote;
        }
      } on Object {
        continue;
      }
    }
    return null;
  }

  /// Searches the other active sources for [addon] by name and returns it
  /// with every hit of the same name added to its alternatives.
  Future<InstalledAddon> withAlternatives(
    WowInstallation inst,
    InstalledAddon addon, {
    List<String>? warnings,
  }) async {
    final hits = await Future.wait([
      for (final source in sources().active)
        if (source.supportsTextSearch && source.id != addon.source)
          () async {
            try {
              return await source.search(addon.name, inst.flavor);
            } on Object catch (e) {
              warnings?.add('${source.id.label}: $e');
              return const <RemoteAddon>[];
            }
          }(),
    ]);
    var alternatives = addon.alternatives;
    for (final remote in hits.expand((h) => h)) {
      if (remote.key == addon.remoteKey) continue;
      if (!isSameAddon(addon, remote)) continue;
      alternatives = _withAlternative(
        alternatives,
        AddonAlternative.of(remote),
      );
    }
    return addon.copyWith(
      alternatives: alternatives,
      alternativesCheckedAt: DateTime.now(),
    );
  }

  /// Whether a search hit is the same addon: same name (ignoring case and
  /// punctuation) and, when both sides name authors, a shared author.
  static bool isSameAddon(InstalledAddon addon, RemoteAddon remote) {
    String norm(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (norm(addon.name) != norm(remote.name)) return false;
    Set<String> authors(String? s) => {
      for (final part in (s ?? '').toLowerCase().split(RegExp(r'[^a-z0-9]+')))
        if (part.length >= 3) part,
    };
    final a = authors(addon.author), b = authors(remote.author);
    return a.isEmpty || b.isEmpty || a.intersection(b).isNotEmpty;
  }

  /// [addon] linked to [remote] without reinstalling it. The previous source
  /// becomes an alternative. The installed release is recognized by version
  /// when possible; otherwise the next update installs the current release.
  InstalledAddon relink(
    InstalledAddon addon,
    RemoteAddon remote, {
    bool manual = false,
  }) {
    String norm(String? v) => (v ?? '').replaceFirst(RegExp(r'^[vV]'), '');
    final sameSource = addon.remoteKey == remote.key;
    final installed = sameSource
        ? null
        : remote.releases
              .where((r) => norm(r.version) == norm(addon.installedVersion))
              .firstOrNull;
    var alternatives = [
      for (final a in addon.alternatives)
        if (a.key != remote.key) a,
    ];
    if (addon.isManaged && !sameSource) {
      alternatives = _withAlternative(
        alternatives,
        AddonAlternative(
          source: addon.source!,
          externalId: addon.externalId!,
          name: addon.name,
          downloadsAllowed: addon.downloadsAllowed,
        ),
      );
    }
    return addon.copyWith(
      name: remote.name,
      source: remote.source,
      externalId: remote.externalId,
      downloadsAllowed: remote.downloadsAllowed,
      manualSource: manual,
      alternatives: alternatives,
      author: remote.author,
      summary: remote.summary,
      thumbnailUrl: remote.thumbnailUrl,
      websiteUrl: remote.websiteUrl,
      installedReleaseId: installed?.id,
      clearInstalledReleaseId: !sameSource && installed == null,
      latestRelease: remote.latestFor(addon.channel),
      clearLatestRelease: remote.latestFor(addon.channel) == null,
    );
  }

  static List<AddonAlternative> _withAlternative(
    List<AddonAlternative> list,
    AddonAlternative alt,
  ) => [
    for (final a in list)
      if (a.key != alt.key) a,
    alt,
  ];

  /// Refreshes [InstalledAddon.latestRelease] for all managed addons.
  Future<AddonsResult> checkUpdates(
    WowInstallation inst,
    List<InstalledAddon> addons,
  ) async {
    final registry = sources();
    final warnings = <String>[];
    final remotes = <String, RemoteAddon>{};

    final bySource = groupBy(
      addons.where((a) => a.isManaged),
      (InstalledAddon a) => a.source!,
    );
    await Future.wait(
      bySource.entries.map((entry) async {
        final source = registry[entry.key];
        if (!source.isAvailable) {
          warnings.add('${source.id.label}: ${source.unavailableReason}');
          return;
        }
        try {
          final ids = entry.value.map((a) => a.externalId!).toSet().toList();
          for (final remote in await source.getMany(ids, inst.flavor)) {
            remotes[remote.key] = remote;
          }
        } on Object catch (e) {
          warnings.add('${source.id.label}: $e');
        }
      }),
    );

    final updated = [
      for (final a in addons)
        if (remotes[a.remoteKey] case final remote?)
          a.copyWith(
            name: remote.name,
            author: remote.author,
            summary: remote.summary,
            thumbnailUrl: remote.thumbnailUrl,
            websiteUrl: remote.websiteUrl,
            downloadsAllowed: remote.downloadsAllowed,
            latestRelease: remote.latestFor(a.channel),
            clearLatestRelease: remote.latestFor(a.channel) == null,
          )
        else
          a,
    ];
    return AddonsResult(updated, warnings);
  }

  /// Installs [release] of [remote], replacing any previous install and
  /// taking over folders that other entries claimed. Required dependencies
  /// that are missing get installed as well.
  ///
  /// Equivalent to [prepare] followed by [apply]; callers that run several
  /// installs at once use the two steps to download in parallel.
  Future<List<InstalledAddon>> install(
    WowInstallation inst,
    List<InstalledAddon> addons, {
    required RemoteAddon remote,
    required AddonRelease release,
    ReleaseChannel? channel,
    ProgressCallback? onProgress,
    Set<String>? visited,
  }) async {
    final prepared = await prepare(
      inst,
      remote: remote,
      release: release,
      onProgress: onProgress,
    );
    return apply(
      inst,
      addons,
      prepared,
      channel: channel,
      onProgress: onProgress,
      visited: visited,
    );
  }

  /// Downloads and extracts [release] into a staging folder without touching
  /// the AddOns folder, so several downloads can run at the same time.
  /// Pass the result to [apply], or [PreparedInstall.discard] it.
  Future<PreparedInstall> prepare(
    WowInstallation inst, {
    required RemoteAddon remote,
    required AddonRelease release,
    ProgressCallback? onProgress,
  }) async {
    if (release.downloadUrl.isEmpty) {
      throw AddonException('${remote.name}: $websiteOnlyMessage');
    }
    final source = sources()[remote.source];
    return _stage(inst, remote, release, onProgress, (zip) async {
      final request = source.downloadRequest(release);
      await api.download(
        request.uri,
        zip,
        headers: request.headers,
        onProgress: (v) => onProgress?.call(v * 0.8),
      );
    });
  }

  /// Like [prepare], but takes the archive from [archive] instead of
  /// downloading it, e.g. a file the user downloaded in the browser.
  Future<PreparedInstall> prepareFile(
    WowInstallation inst, {
    required RemoteAddon remote,
    required AddonRelease release,
    required File archive,
    ProgressCallback? onProgress,
  }) => _stage(inst, remote, release, onProgress, (zip) async {
    await archive.copy(zip.path);
    onProgress?.call(0.8);
  });

  Future<PreparedInstall> _stage(
    WowInstallation inst,
    RemoteAddon remote,
    AddonRelease release,
    ProgressCallback? onProgress,
    Future<void> Function(File zip) fetch,
  ) async {
    // Staging lives next to AddOns so the final move is a cheap rename on
    // the same filesystem.
    final staging = Directory(
      p.join(inst.interfacePath, '.wow-butler-staging', newId()),
    );
    await staging.create(recursive: true);
    final prepared = PreparedInstall._(remote, release, staging);

    try {
      final zip = File(p.join(staging.path, 'download.zip'));
      await fetch(zip);

      final extractDir = p.join(staging.path, 'extract');
      final folders = await _extractInIsolate(zip.path, extractDir);
      if (folders.isEmpty) {
        throw AddonException(
          '${remote.name}: Archiv enthält keine Addon-Ordner.',
        );
      }
      prepared._folders = folders;
      onProgress?.call(0.85);
      return prepared;
    } catch (_) {
      await prepared.discard();
      rethrow;
    }
  }

  /// Moves a [prepared] release into the AddOns folder and returns the new
  /// addon list based on [addons]. Callers must not run two [apply] calls
  /// for the same installation at once.
  Future<List<InstalledAddon>> apply(
    WowInstallation inst,
    List<InstalledAddon> addons,
    PreparedInstall prepared, {
    ReleaseChannel? channel,
    ProgressCallback? onProgress,
    Set<String>? visited,
  }) async {
    final remote = prepared.remote!;
    final release = prepared.release!;
    visited ??= {};
    visited.add(remote.key);
    try {
      final addonsDir = Directory(inst.addonsPath);
      await addonsDir.create(recursive: true);
      final newFolders = prepared._folders;

      final existing = addons.firstWhereOrNull(
        (a) => a.remoteKey == remote.key,
      );

      final newNames = newFolders.map(p.basename).toList();
      final newLower = newNames.map((n) => n.toLowerCase()).toSet();
      final toDelete = {...newNames, ...?existing?.folders};
      for (final name in toDelete) {
        final dir = Directory(p.join(inst.addonsPath, name));
        if (await dir.exists()) await dir.delete(recursive: true);
      }
      for (final folder in newFolders) {
        await _move(folder, p.join(inst.addonsPath, p.basename(folder)));
      }
      onProgress?.call(0.95);

      final effectiveChannel = channel ?? existing?.channel ?? defaultChannel();
      final installed = InstalledAddon(
        id: existing?.id ?? newId(),
        manualSource: existing?.manualSource ?? false,
        alternatives: existing?.alternatives ?? const [],
        alternativesCheckedAt: existing?.alternativesCheckedAt,
        name: remote.name,
        folders: orderFolders(newNames, preferred: existing?.folders.first),
        source: remote.source,
        externalId: remote.externalId,
        author: remote.author,
        summary: remote.summary,
        thumbnailUrl: remote.thumbnailUrl,
        websiteUrl: remote.websiteUrl,
        installedVersion: release.version,
        installedReleaseId: release.id,
        installedAt: DateTime.now(),
        downloadsAllowed: remote.downloadsAllowed,
        channel: effectiveChannel,
        autoUpdate: existing?.autoUpdate ?? true,
        pinned: false,
        ignored: existing?.ignored ?? false,
        latestRelease: release,
        interfaces: release.interfaces,
      );

      var result =
          <InstalledAddon>[
              for (final a in addons)
                if (a.id != installed.id)
                  a.copyWith(
                    folders: a.folders
                        .where((f) => !newLower.contains(f.toLowerCase()))
                        .toList(),
                  ),
            ].where((a) => a.folders.isNotEmpty).toList()
            ..add(installed)
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );

      final source = sources()[remote.source];
      for (final depId in release.dependencies) {
        final key = '${remote.source.name}:$depId';
        if (visited.contains(key) || result.any((a) => a.remoteKey == key)) {
          continue;
        }
        // A failing dependency must not lose the record of the main addon,
        // which is already on disk; the next sync picks the dependency up.
        try {
          final dep = await source.getById(depId, inst.flavor);
          final depRelease = dep?.latestFor(effectiveChannel);
          if (dep == null || depRelease == null) continue;
          result = await install(
            inst,
            result,
            remote: dep,
            release: depRelease,
            channel: effectiveChannel,
            visited: visited,
          );
        } on Object {
          continue;
        }
      }
      onProgress?.call(1);
      return result;
    } finally {
      await prepared.discard();
    }
  }

  /// Extracts the addon archive [archive] into AddOns, replacing folders of
  /// the same name, and returns the folder names. The caller rescans to
  /// identify the addon.
  Future<List<String>> installArchive(
    WowInstallation inst,
    File archive,
  ) async {
    final staging = Directory(
      p.join(inst.interfacePath, '.wow-butler-staging', newId()),
    );
    await staging.create(recursive: true);
    try {
      final folders = await _extractInIsolate(
        archive.path,
        p.join(staging.path, 'extract'),
      );
      if (folders.isEmpty) {
        throw AddonException(
          '${p.basename(archive.path)}: Archiv enthält keine Addon-Ordner.',
        );
      }
      await Directory(inst.addonsPath).create(recursive: true);
      for (final folder in folders) {
        final target = Directory(p.join(inst.addonsPath, p.basename(folder)));
        if (await target.exists()) await target.delete(recursive: true);
        await _move(folder, target.path);
      }
      return folders.map(p.basename).toList();
    } finally {
      await PreparedInstall._(null, null, staging).discard();
    }
  }

  /// Fetches fresh release data and installs the newest release for the
  /// addon's channel. Download URLs of some sources are short-lived, so
  /// the cached [InstalledAddon.latestRelease] is not used directly.
  Future<List<InstalledAddon>> update(
    WowInstallation inst,
    List<InstalledAddon> addons,
    InstalledAddon addon, {
    ProgressCallback? onProgress,
    bool force = false,
  }) async {
    final plan = await planUpdate(inst, addon, force: force);
    if (plan.upToDate) return markUpToDate(addons, addon, plan.release);
    return install(
      inst,
      addons,
      remote: plan.remote,
      release: plan.release,
      channel: addon.channel,
      onProgress: onProgress,
    );
  }

  /// Resolves the release an update of [addon] installs. Without [force]
  /// the plan reports when that release is already installed.
  Future<UpdatePlan> planUpdate(
    WowInstallation inst,
    InstalledAddon addon, {
    bool force = false,
  }) async {
    if (!addon.isManaged) {
      throw AddonException('${addon.name} ist keiner Quelle zugeordnet.');
    }
    final source = sources()[addon.source!];
    if (!source.isAvailable) throw AddonException(source.unavailableReason!);
    final remote = await source.getById(addon.externalId!, inst.flavor);
    final release = remote?.latestFor(addon.channel);
    if (remote == null || release == null) {
      throw AddonException(
        '${addon.name}: Keine passende Version für ${inst.flavor.label}.',
      );
    }
    return UpdatePlan(
      remote,
      release,
      upToDate: !force && release.id == addon.installedReleaseId,
    );
  }

  /// [addons] with [release] recorded as the latest one of [addon].
  List<InstalledAddon> markUpToDate(
    List<InstalledAddon> addons,
    InstalledAddon addon,
    AddonRelease release,
  ) => [
    for (final a in addons)
      a.id == addon.id ? a.copyWith(latestRelease: release) : a,
  ];

  Future<List<InstalledAddon>> uninstall(
    WowInstallation inst,
    List<InstalledAddon> addons,
    InstalledAddon addon,
  ) async {
    for (final folder in addon.folders) {
      final dir = Directory(p.join(inst.addonsPath, folder));
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    return addons.where((a) => a.id != addon.id).toList();
  }

  Future<void> _move(String from, String to) async {
    try {
      await Directory(from).rename(to);
    } on FileSystemException {
      // Different filesystem (e.g. symlinked AddOns): copy instead.
      await _copyInIsolate(from, to);
    }
  }
}

/// Shown when an author disallows downloads through third-party tools.
const websiteOnlyMessage =
    'Der Autor erlaubt keine direkten Downloads über Drittanbieter-Programme. '
    'Lade die Datei über die Website herunter; WoW Butler installiert sie '
    'danach.';

/// What an update of an addon would install.
class UpdatePlan {
  const UpdatePlan(this.remote, this.release, {required this.upToDate});

  final RemoteAddon remote;
  final AddonRelease release;

  /// [release] is already installed; nothing to download.
  final bool upToDate;
}

/// A release downloaded and extracted by [AddonService.prepare], waiting in
/// a staging folder to be moved into AddOns by [AddonService.apply].
class PreparedInstall {
  PreparedInstall._(this.remote, this.release, this._staging);

  /// `null` only for the internal staging of [AddonService.installArchive].
  final RemoteAddon? remote;
  final AddonRelease? release;
  final Directory _staging;
  List<String> _folders = const [];

  /// Deletes the staging folder; safe to call more than once.
  Future<void> discard() async {
    if (await _staging.exists()) {
      await _staging.delete(recursive: true).catchError((_) => _staging);
    }
    final root = _staging.parent;
    // Another download may be staging in parallel; only an empty root goes.
    if (await root.exists() && await root.list().isEmpty) {
      await root.delete().catchError((_) => root);
    }
  }
}

// Isolate entry points are top-level so their closures capture nothing but
// the (sendable) parameters. A closure inside a method can share its context
// with other closures and drag unsendable objects like callbacks along.
Future<List<String>> _extractInIsolate(String zipPath, String outDir) =>
    Isolate.run(() => extractAddonArchive(zipPath, outDir));

Future<void> _copyInIsolate(String from, String to) =>
    Isolate.run(() => _copyDirSync(from, to));

void _copyDirSync(String from, String to) {
  for (final e in Directory(from).listSync(recursive: true)) {
    final target = p.join(to, p.relative(e.path, from: from));
    if (e is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (e is File) {
      File(target).parent.createSync(recursive: true);
      e.copySync(target);
    }
  }
}

/// Puts the folder that others are named after first
/// (`ElvUI` before `ElvUI_Options`).
List<String> orderFolders(List<String> names, {String? preferred}) {
  int score(String n) {
    if (preferred != null && n.toLowerCase() == preferred.toLowerCase()) {
      return -1000;
    }
    final lower = n.toLowerCase();
    return -names
        .where((o) => o != n && o.toLowerCase().startsWith(lower))
        .length;
  }

  return [...names]..sort((a, b) {
    final s = score(a).compareTo(score(b));
    return s != 0 ? s : a.length.compareTo(b.length);
  });
}

/// Extracts [zipPath] and returns the paths of the addon folders inside,
/// normalizing common packaging quirks. Synchronous; run in an isolate.
List<String> extractAddonArchive(String zipPath, String outDir) {
  final input = InputFileStream(zipPath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    extractArchiveSafely(archive, outDir);
  } finally {
    input.closeSync();
  }

  bool hasToc(Directory d) => d.listSync().any(
    (e) => e is File && p.extension(e.path).toLowerCase() == '.toc',
  );
  List<Directory> subdirs(String path) =>
      Directory(path)
          .listSync()
          .whereType<Directory>()
          .where((d) => !p.basename(d.path).startsWith('__MACOSX'))
          .where((d) => !p.basename(d.path).startsWith('.'))
          .toList();

  var dirs = subdirs(outDir);

  // Loose TOC at the archive root: wrap it into a folder named after it.
  final rootToc = Directory(outDir)
      .listSync()
      .whereType<File>()
      .where((f) => p.extension(f.path).toLowerCase() == '.toc')
      .firstOrNull;
  if (rootToc != null) {
    final name = _tocBaseName(rootToc.path);
    final wrapper = Directory(p.join(p.dirname(outDir), '_wrap', name))
      ..createSync(recursive: true);
    for (final e in Directory(outDir).listSync()) {
      e.renameSync(p.join(wrapper.path, p.basename(e.path)));
    }
    return [wrapper.path];
  }

  // A single wrapper folder (e.g. GitHub source archives) around the addons.
  if (dirs.length == 1 && !hasToc(dirs.first)) {
    final inner = subdirs(dirs.first.path);
    if (inner.any(hasToc)) dirs = inner;
  }

  final result = <String>[];
  for (final dir in dirs.where(hasToc)) {
    final name = p.basename(dir.path);
    final tocNames = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.extension(f.path).toLowerCase() == '.toc')
        .map((f) => _tocBaseName(f.path))
        .toSet();
    if (tocNames.any((t) => t.toLowerCase() == name.toLowerCase())) {
      result.add(dir.path);
      continue;
    }
    // Folder named after the release (`MyAddon-1.2.3`): rename to the TOC.
    final target = p.join(p.dirname(dir.path), tocNames.first);
    dir.renameSync(target);
    result.add(target);
  }
  return result;
}

String _tocBaseName(String tocPath) => p
    .basenameWithoutExtension(tocPath)
    .replaceFirst(
      RegExp(
        r'[-_](mainline|classic|vanilla|tbc|bcc|wrath|wotlkc|cata|mists|camelot|forever)$',
        caseSensitive: false,
      ),
      '',
    );
