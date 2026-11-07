import 'package:collection/collection.dart';

import '../core/external_addons.dart';
import '../core/models/addon.dart';
import '../core/models/addon_category.dart';
import '../core/models/addon_folder.dart';
import '../core/models/game_flavor.dart';
import '../core/models/wow_installation.dart';
import '../core/util/version_label.dart';
import 'addon_source.dart';
import 'api_client.dart';
import 'description.dart';

/// CurseForge Core API (https://docs.curseforge.com). Requires a personal
/// API key from https://console.curseforge.com.
class CurseForgeSource extends AddonSource {
  CurseForgeSource(this._api, this._apiKey);

  final ApiClient _api;
  final String? _apiKey;

  static const _base = 'https://api.curseforge.com';
  static const _gameId = 1;

  @override
  AddonSourceId get id => AddonSourceId.curseforge;

  /// Authors tokens (authors.curseforge.com) are UUIDs; the Core API needs
  /// the bcrypt style key from console.curseforge.com instead.
  static final _authorsTokenPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
    r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  String? get unavailableReason {
    if (_apiKey == null || _apiKey.isEmpty) {
      return 'CurseForge benötigt einen API-Schlüssel (Einstellungen → Quellen).';
    }
    if (_authorsTokenPattern.hasMatch(_apiKey)) {
      return 'Der Schlüssel ist ein Autoren-Token – benötigt wird ein '
          'Core-API-Key von console.curseforge.com.';
    }
    return null;
  }

  Map<String, String> get _headers => {'x-api-key': _apiKey ?? ''};

  static int gameVersionTypeId(GameFlavor flavor) => switch (flavor) {
    GameFlavor.retail => 517,
    GameFlavor.vanilla => 67408,
    GameFlavor.tbc => 73246,
    GameFlavor.wrath => 73713,
    GameFlavor.cata => 77522,
    GameFlavor.mists => 79434,
    GameFlavor.forever => 88568,
  };

  @override
  Future<List<RemoteAddon>> featured(GameFlavor flavor) async {
    final json = await _api.postJson(Uri.parse('$_base/v1/mods/featured'), {
      'gameId': _gameId,
      'gameVersionTypeId': gameVersionTypeId(flavor),
      'excludedModIds': <int>[],
    }, headers: _headers) as Map<String, dynamic>;
    final data = json.obj('data') ?? const {};
    final mods = [
      ...data.objs('popular'),
      ...data.objs('recentlyUpdated'),
      ...data.objs('featured'),
    ];
    final seen = <int>{};
    return [
      for (final m in mods)
        if (seen.add(m['id'] as int)) _toRemote(m, flavor),
    ];
  }

  @override
  Future<List<RemoteAddon>> search(String query, GameFlavor flavor) async {
    final uri = Uri.parse('$_base/v1/mods/search').replace(
      queryParameters: {
        'gameId': '$_gameId',
        'searchFilter': query,
        'gameVersionTypeId': '${gameVersionTypeId(flavor)}',
        'sortField': '2', // popularity
        'sortOrder': 'desc',
        'pageSize': '50',
      },
    );
    final json = await _api.getJson(uri, headers: _headers) as Map;
    return [
      for (final m in (json['data'] as List).cast<Map<String, dynamic>>())
        _toRemote(m, flavor),
    ];
  }

  /// Category browsing is server side: CurseForge's own taxonomy is richer
  /// than any keyword heuristic.
  @override
  Future<List<RemoteAddon>> browse(
    String query,
    GameFlavor flavor, {
    AddonCategory? category,
  }) async {
    if (category == null) return super.browse(query, flavor);
    final uri = Uri.parse('$_base/v1/mods/search').replace(
      queryParameters: {
        'gameId': '$_gameId',
        if (query.isNotEmpty) 'searchFilter': query,
        'categoryId': '${category.curseforgeId}',
        'gameVersionTypeId': '${gameVersionTypeId(flavor)}',
        'sortField': '2', // popularity
        'sortOrder': 'desc',
        'pageSize': '50',
      },
    );
    final json = await _api.getJson(uri, headers: _headers) as Map;
    return [
      for (final m in (json['data'] as List).cast<Map<String, dynamic>>())
        _toRemote(m, flavor),
    ];
  }

  @override
  Future<RemoteAddon?> getById(String externalId, GameFlavor flavor) async {
    final json = await _api.getJson(
      Uri.parse('$_base/v1/mods/$externalId'),
      headers: _headers,
    ) as Map<String, dynamic>;
    final data = json.obj('data');
    return data == null ? null : _toRemote(data, flavor);
  }

  @override
  Future<List<RemoteAddon>> getMany(List<String> ids, GameFlavor flavor) async {
    if (ids.isEmpty) return const [];
    final json = await _api.postJson(Uri.parse('$_base/v1/mods'), {
      'modIds': ids.map(int.parse).toList(),
    }, headers: _headers) as Map<String, dynamic>;
    return [for (final m in json.objs('data')) _toRemote(m, flavor)];
  }

  @override
  Future<List<AddonMatch>> match(
    List<AddonFolder> folders,
    GameFlavor flavor,
  ) async {
    final byFingerprint = <int, AddonFolder>{
      for (final f in folders)
        if (f.hasToc && f.fingerprint != null) f.fingerprint!.curse: f,
    };
    final typeId = gameVersionTypeId(flavor);

    // modId -> matched file; prefer files compatible with this client.
    final byMod = <int, Map<String, dynamic>>{};
    if (byFingerprint.isNotEmpty) {
      final json =
          await _api.postJson(Uri.parse('$_base/v1/fingerprints/$_gameId'), {
                'fingerprints': byFingerprint.keys.toList(),
              }, headers: _headers)
              as Map<String, dynamic>;
      final exact = (json.obj('data') ?? const {}).objs('exactMatches');
      for (final folder in byFingerprint.entries) {
        final candidates = exact.where((m) {
          final file = m.obj('file');
          return file != null &&
              file
                  .objs('modules')
                  .any((mod) => mod['fingerprint'] == folder.key);
        }).toList();
        final best =
            candidates.firstWhereOrNull(
              (m) => _isCompatible(m.obj('file')!, typeId),
            ) ??
            candidates.firstOrNull;
        if (best != null) byMod.putIfAbsent(best['id'] as int, () => best);
      }
    }

    final mods = byMod.isEmpty
        ? const <RemoteAddon>[]
        : await getMany(byMod.keys.map((id) => '$id').toList(), flavor);
    final onDisk = {for (final f in folders) f.name.toLowerCase(): f.name};

    final matches = [
      for (final mod in mods)
        if (byMod[int.parse(mod.externalId)] case final match?)
          AddonMatch(
            addon: mod,
            folders: [
              for (final module in match.obj('file')!.objs('modules'))
                ?onDisk[(module['name'] as String? ?? '').toLowerCase()],
            ],
            installedRelease: _toRelease(match.obj('file')!),
          ),
    ];
    matches.addAll(
      await _matchByTocId(folders, flavor, matches, byMod.keys.toSet()),
    );
    matches.addAll(await _matchByName(folders, flavor, matches));
    return matches;
  }

  /// Identifies folders the fingerprint pass missed through their
  /// `X-Curse-Project-ID`, e.g. installs that did not come from a CurseForge
  /// zip. The project's release file names all folders it owns.
  Future<List<AddonMatch>> _matchByTocId(
    List<AddonFolder> folders,
    GameFlavor flavor,
    List<AddonMatch> matched,
    Set<int> matchedMods,
  ) async {
    final claimed = {
      for (final m in matched)
        for (final f in m.folders) f.toLowerCase(),
    };
    final byProject = <int, List<AddonFolder>>{};
    for (final f in folders) {
      if (!f.hasToc || claimed.contains(f.name.toLowerCase())) continue;
      final id = int.tryParse(f.toc!.curseProjectId ?? '');
      if (id == null || matchedMods.contains(id)) continue;
      byProject.putIfAbsent(id, () => []).add(f);
    }
    if (byProject.isEmpty) return const [];

    final json =
        await _api.postJson(Uri.parse('$_base/v1/mods'), {
              'modIds': byProject.keys.toList(),
            }, headers: _headers)
            as Map<String, dynamic>;

    final onDisk = {for (final f in folders) f.name.toLowerCase(): f.name};
    return [
      for (final mod in json.objs('data'))
        if (byProject[mod.integer('id')] case final declaring?)
          _matchFromMod(mod, declaring, onDisk, flavor),
    ];
  }

  /// AddOns folders (lower case) of CurseForge projects whose TOC carries
  /// neither a project ID nor the CurseForge author name, mapped to the
  /// project slug.
  static const _knownSlugs = <String, String>{'questiedb': 'questiedb'};

  /// Last resort for folders without fingerprint or TOC ID match, e.g. a
  /// local build of an addon that is also on CurseForge. Known folders are
  /// looked up by their project slug. Others search the TOC title and only
  /// accept a project whose release ships a folder of the same name and
  /// whose authors include the TOC author.
  Future<List<AddonMatch>> _matchByName(
    List<AddonFolder> folders,
    GameFlavor flavor,
    List<AddonMatch> matched,
  ) async {
    final claimed = {
      for (final m in matched)
        for (final f in m.folders) f.toLowerCase(),
    };
    final claimedMods = {for (final m in matched) m.addon.externalId};
    final candidates = folders
        .where(
          (f) =>
              f.hasToc &&
              !claimed.contains(f.name.toLowerCase()) &&
              (_knownSlugs.containsKey(f.name.toLowerCase()) ||
                  (f.toc!.author?.isNotEmpty ?? false)) &&
              !f.toc!.isLoadOnDemand &&
              !isKnownExternalAddon(f.name),
        )
        .take(_maxNameSearches);

    final onDisk = {for (final f in folders) f.name.toLowerCase(): f.name};
    final matches = <AddonMatch>[];
    for (final folder in candidates) {
      if (claimed.contains(folder.name.toLowerCase())) continue;
      final toc = folder.toc!;
      final slug = _knownSlugs[folder.name.toLowerCase()];
      final uri = Uri.parse('$_base/v1/mods/search').replace(
        queryParameters: {
          'gameId': '$_gameId',
          if (slug != null) 'slug': slug else 'searchFilter': toc.title,
          'gameVersionTypeId': '${gameVersionTypeId(flavor)}',
          'pageSize': '20',
        },
      );
      final Map json;
      try {
        json = await _api.getJson(uri, headers: _headers) as Map;
      } on Object {
        // A failed search must not discard the fingerprint matches.
        continue;
      }
      final author = toc.author?.toLowerCase();
      final mod = ((json['data'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .where((m) {
            if (claimedMods.contains('${m['id']}')) return false;
            if (slug != null) return m['slug'] == slug;
            final byAuthor = m
                .objs('authors')
                .any((a) => (a.str('name') ?? '').toLowerCase() == author);
            final shipsFolder = m
                .objs('latestFiles')
                .any(
                  (f) => f
                      .objs('modules')
                      .any(
                        (mod) =>
                            (mod.str('name') ?? '').toLowerCase() ==
                            folder.name.toLowerCase(),
                      ),
                );
            return byAuthor && shipsFolder;
          })
          .firstOrNull;
      if (mod == null) continue;
      final match = _matchFromMod(mod, [folder], onDisk, flavor);
      matches.add(match);
      claimed.addAll(match.folders.map((f) => f.toLowerCase()));
      claimedMods.add(match.addon.externalId);
    }
    return matches;
  }

  /// Name searches per sync; folders that stay local are searched again on
  /// every sync, so this bounds the cost of large local collections.
  static const _maxNameSearches = 25;

  /// A match for [mod], owned by the [declaring] folders plus the modules of
  /// its newest compatible release that exist on disk.
  AddonMatch _matchFromMod(
    Map<String, dynamic> mod,
    List<AddonFolder> declaring,
    Map<String, String> onDisk,
    GameFlavor flavor,
  ) {
    final typeId = gameVersionTypeId(flavor);
    final files =
        mod
            .objs('latestFiles')
            .where((f) => f['exposeAsAlternative'] != true)
            .where((f) => _isCompatible(f, typeId))
            .toList()
          ..sort((a, b) => (b.integer('id') ?? 0) - (a.integer('id') ?? 0));

    // The installed version is known from the TOC, not from a fingerprint.
    // A build for another game version counts as unknown, so the next
    // update installs the right one.
    final toc = declaring.first.toc;
    final tocVersion = (toc?.builtForOtherFlavor(flavor) ?? true)
        ? null
        : toc?.version?.replaceFirst(
      RegExp(r'^[vV]'),
      '',
    );
    final installedFile = files.firstWhereOrNull(
      (f) =>
          tocVersion != null &&
          versionLabel(f.str('displayName') ?? '')
                  .replaceFirst(RegExp(r'^[vV]'), '') ==
              tocVersion,
    );

    return AddonMatch(
      addon: _toRemote(mod, flavor),
      folders: {
        for (final f in declaring) f.name,
        for (final module in files.firstOrNull?.objs('modules') ?? const [])
          ?onDisk[(module['name'] as String? ?? '').toLowerCase()],
      }.toList(),
      installedRelease: installedFile == null
          ? null
          : _toRelease(installedFile),
    );
  }

  @override
  Future<AddonDetails> details(RemoteAddon addon, GameFlavor flavor) async {
    final results = await Future.wait([
      _api.getJson(
        Uri.parse('$_base/v1/mods/${addon.externalId}'),
        headers: _headers,
      ),
      _api.getJson(
        Uri.parse('$_base/v1/mods/${addon.externalId}/description'),
        headers: _headers,
      ),
    ]);
    final mod = (results[0] as Map<String, dynamic>).obj('data') ?? const {};
    final html = (results[1] as Map<String, dynamic>).str('data');
    final typeIds = {
      for (final f in mod.objs('latestFiles'))
        for (final v in f.objs('sortableGameVersions')) v['gameVersionTypeId'],
    };
    return detailsFromDescription(
      html: html,
      screenshots: [for (final s in mod.objs('screenshots')) ?s.str('url')],
      category: mod.objs('categories').firstOrNull?.str('name'),
      flavors: {
        for (final f in GameFlavor.values)
          if (typeIds.contains(gameVersionTypeId(f))) f,
      },
    );
  }

  @override
  Future<String?> changelog(String externalId, AddonRelease release) async {
    final json = await _api.getJson(
      Uri.parse('$_base/v1/mods/$externalId/files/${release.id}/changelog'),
      headers: _headers,
    ) as Map<String, dynamic>;
    final html = json.str('data');
    return html == null ? null : htmlToText(html);
  }

  @override
  ({Uri uri, Map<String, String> headers}) downloadRequest(
    AddonRelease release,
  ) {
    final uri = Uri.parse(release.downloadUrl);
    return (
      uri: uri,
      headers: uri.host == 'api.curseforge.com' ? _headers : const {},
    );
  }

  bool _isCompatible(Map<String, dynamic> file, int typeId) => file
      .objs('sortableGameVersions')
      .any((v) => v['gameVersionTypeId'] == typeId);

  RemoteAddon _toRemote(Map<String, dynamic> m, GameFlavor flavor) {
    final typeId = gameVersionTypeId(flavor);
    final files = m
        .objs('latestFiles')
        .where((f) => f['exposeAsAlternative'] != true)
        .where((f) => _isCompatible(f, typeId))
        .toList();
    final releases = [for (final f in files) ?_toRelease(f)];
    return RemoteAddon(
      source: id,
      externalId: '${m['id']}',
      name: m.str('name') ?? '?',
      summary: m.str('summary'),
      author: m.objs('authors').map((a) => a['name']).firstOrNull as String?,
      thumbnailUrl: m.obj('logo')?.str('thumbnailUrl'),
      websiteUrl: m.obj('links')?.str('websiteUrl'),
      downloadCount: m.integer('downloadCount'),
      updatedAt: m.date('dateReleased') ?? m.date('dateModified'),
      releases: releases,
      // Older API responses lack the flag; files without a download URL
      // tell the same.
      downloadsAllowed:
          m['allowModDistribution'] != false &&
          !(releases.isNotEmpty &&
              releases.every((r) => r.downloadUrl.isEmpty)),
    );
  }

  AddonRelease? _toRelease(Map<String, dynamic> f) {
    final fileId = f.integer('id');
    if (fileId == null) return null;
    final fileName = f.str('fileName') ?? '';
    // A missing URL means the author opted out of third-party distribution.
    // We respect that; the installer reports it instead of downloading.
    final url = f.str('downloadUrl') ?? '';
    return AddonRelease(
      id: '$fileId',
      version: versionLabel(f.str('displayName') ?? fileName),
      channel: switch (f['releaseType']) {
        2 => ReleaseChannel.beta,
        3 => ReleaseChannel.alpha,
        _ => ReleaseChannel.stable,
      },
      downloadUrl: url,
      releasedAt: f.date('fileDate'),
      fileName: fileName,
      size: f.integer('fileLength'),
      dependencies: [
        for (final d in f.objs('dependencies'))
          if (d['relationType'] == 3) '${d['modId']}',
      ],
    );
  }
}
