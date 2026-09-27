import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import '../core/models/addon.dart';
import '../core/models/addon_folder.dart';
import '../core/models/wow_installation.dart';
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
  });

  final ApiClient api;
  final SourceRegistry Function() sources;

  /// Channel for addons that have none yet (fresh installs and matches).
  final ReleaseChannel Function() defaultChannel;

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
        final free = {for (final f in remaining) f.name.toLowerCase(): f.name};
        final taken = match.folders
            .map((f) => free[f.toLowerCase()])
            .nonNulls
            .toList();
        if (taken.isEmpty) continue;
        final previous = previousByFolder[taken.first.toLowerCase()];
        result.add(_fromMatch(inst, match, taken, byName, previous));
        final takenLower = taken.map((t) => t.toLowerCase()).toSet();
        remaining = remaining
            .where((f) => !takenLower.contains(f.name.toLowerCase()))
            .toList();
      }
    }

    _addUnmanaged(result, remaining, previousByFolder);
    _refreshFromToc(result, byName);
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
      installedVersion: toc?.version ?? installed?.version,
      installedReleaseId: installed?.id,
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
  Future<List<InstalledAddon>> install(
    WowInstallation inst,
    List<InstalledAddon> addons, {
    required RemoteAddon remote,
    required AddonRelease release,
    ReleaseChannel? channel,
    ProgressCallback? onProgress,
    Set<String>? visited,
  }) async {
    visited ??= {};
    visited.add(remote.key);
    if (release.downloadUrl.isEmpty) {
      throw AddonException(
        '${remote.name}: Der Autor erlaubt keine Downloads über '
        'Drittanbieter-Programme. Bitte über die Website installieren.',
      );
    }

    final source = sources()[remote.source];
    final addonsDir = Directory(inst.addonsPath);
    await addonsDir.create(recursive: true);
    // Staging lives next to AddOns so the final move is a cheap rename on
    // the same filesystem.
    final staging = Directory(
      p.join(inst.interfacePath, '.wow-butler-staging', newId()),
    );
    await staging.create(recursive: true);

    try {
      final zip = File(p.join(staging.path, 'download.zip'));
      final request = source.downloadRequest(release);
      await api.download(
        request.uri,
        zip,
        headers: request.headers,
        onProgress: (v) => onProgress?.call(v * 0.8),
      );

      final extractDir = p.join(staging.path, 'extract');
      final newFolders = await _extractInIsolate(zip.path, extractDir);
      if (newFolders.isEmpty) {
        throw AddonException(
          '${remote.name}: Archiv enthält keine Addon-Ordner.',
        );
      }
      onProgress?.call(0.85);

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
      await staging.delete(recursive: true).catchError((_) => staging);
      final root = staging.parent;
      if (await root.exists() && await root.list().isEmpty) {
        await root.delete().catchError((_) => root);
      }
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
    if (!force && release.id == addon.installedReleaseId) {
      return [
        for (final a in addons)
          a.id == addon.id ? a.copyWith(latestRelease: release) : a,
      ];
    }
    return install(
      inst,
      addons,
      remote: remote,
      release: release,
      channel: addon.channel,
      onProgress: onProgress,
    );
  }

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
    extractArchiveToDiskSync(archive, outDir);
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
        r'[-_](mainline|classic|vanilla|tbc|bcc|wrath|wotlkc|cata|mists)$',
        caseSensitive: false,
      ),
      '',
    );
