import 'dart:convert';

import '../core/models/addon.dart';
import '../core/models/addon_folder.dart';
import '../core/models/game_flavor.dart';
import '../core/models/wow_installation.dart';
import 'addon_source.dart';
import 'api_client.dart';
import 'description.dart';

/// Addons published as GitHub releases. Addressed by `owner/repo` or a
/// repository URL; there is no catalog to browse or fingerprint against.
class GitHubSource extends AddonSource {
  GitHubSource(this._api, this._token);

  final ApiClient _api;
  final String? _token;

  static const _base = 'https://api.github.com/repos';

  @override
  AddonSourceId get id => AddonSourceId.github;

  @override
  bool get supportsTextSearch => false;

  @override
  bool get supportsMatching => false;

  Map<String, String> get _headers => {
    'Accept': 'application/vnd.github+json',
    if (_token != null && _token.isNotEmpty) 'Authorization': 'Bearer $_token',
  };

  static final _repoPattern = RegExp(
    r'^(?:https?://)?(?:www\.)?(?:github\.com/)?([\w.-]+)/([\w.-]+?)(?:\.git)?(?:/.*)?$',
  );

  /// Project sites of addons that release on GitHub, so pasting the
  /// website address works like pasting the repository URL.
  static const _projectSites = <String, String>{
    'ellesmereui.com': 'EllesmereGaming/EllesmereUI',
  };

  /// Parses `owner/repo` from a repository reference or a known project
  /// website, or `null`.
  static String? parseRepo(String input) {
    final trimmed = input.trim();
    final uri = Uri.tryParse(
      trimmed.contains('://') ? trimmed : 'https://$trimmed',
    );
    final host = uri?.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final site = _projectSites[host];
    if (site != null) return site;

    final m = _repoPattern.firstMatch(trimmed);
    if (m == null) return null;
    return '${m.group(1)}/${m.group(2)}';
  }

  @override
  Future<List<RemoteAddon>> featured(GameFlavor flavor) async => const [];

  @override
  Future<List<RemoteAddon>> search(String query, GameFlavor flavor) async {
    final repo = parseRepo(query);
    if (repo == null) return const [];
    try {
      final addon = await getById(repo, flavor);
      return addon == null ? const [] : [addon];
    } on ApiException catch (e) {
      if (e.statusCode == 404) return const [];
      rethrow;
    }
  }

  @override
  Future<RemoteAddon?> getById(String externalId, GameFlavor flavor) async {
    final repo = await _api.getJson(
      Uri.parse('$_base/$externalId'),
      headers: _headers,
    ) as Map<String, dynamic>;
    final releases =
        (await _api.getJson(
              Uri.parse('$_base/$externalId/releases?per_page=10'),
              headers: _headers,
            ) as List)
            .whereType<Map<String, dynamic>>()
            .where((r) => r['draft'] != true)
            .toList();

    final picked = <AddonRelease>[];
    for (final prerelease in [false, true]) {
      for (final r in releases.where((r) => r['prerelease'] == prerelease)) {
        final release = await _pickAsset(r, flavor);
        if (release != null) {
          picked.add(release);
          break;
        }
      }
    }

    return RemoteAddon(
      source: id,
      externalId: externalId,
      name: repo.str('name') ?? externalId,
      summary: repo.str('description'),
      author: repo.obj('owner')?.str('login'),
      thumbnailUrl: repo.obj('owner')?.str('avatar_url'),
      websiteUrl: repo.str('html_url'),
      downloadCount: repo.integer('stargazers_count'),
      updatedAt: repo.date('pushed_at'),
      releases: picked,
    );
  }

  @override
  Future<List<RemoteAddon>> getMany(List<String> ids, GameFlavor flavor) async {
    final results = <RemoteAddon>[];
    // Sequential, to stay well within the unauthenticated rate limit.
    for (final id in ids) {
      final addon = await getById(id, flavor);
      if (addon != null) results.add(addon);
    }
    return results;
  }

  @override
  Future<List<AddonMatch>> match(
    List<AddonFolder> folders,
    GameFlavor flavor,
  ) async => const [];

  @override
  Future<AddonDetails> details(RemoteAddon addon, GameFlavor flavor) async {
    String? readme;
    try {
      final json = await _api.getJson(
        Uri.parse('$_base/${addon.externalId}/readme'),
        headers: _headers,
      ) as Map<String, dynamic>;
      final content = json.str('content');
      if (content != null) {
        readme = utf8.decode(
          base64.decode(content.replaceAll('\n', '')),
          allowMalformed: true,
        );
      }
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
    if (readme == null) return super.details(addon, flavor);
    return detailsFromDescription(markdown: readme);
  }

  static String packagerFlavor(GameFlavor flavor) => switch (flavor) {
    GameFlavor.retail => 'mainline',
    GameFlavor.vanilla => 'classic',
    GameFlavor.tbc => 'bcc',
    GameFlavor.wrath => 'wrath',
    GameFlavor.cata => 'cata',
    GameFlavor.mists => 'mists',
    GameFlavor.forever => 'forever',
  };

  static final _flavorAsset = <GameFlavor, RegExp>{
    GameFlavor.vanilla: RegExp(
      r'[-_](classic|vanilla)\.zip$',
      caseSensitive: false,
    ),
    GameFlavor.tbc: RegExp(r'[-_](bc|bcc|tbc)\.zip$', caseSensitive: false),
    GameFlavor.wrath: RegExp(r'[-_](wrath|wotlkc)\.zip$', caseSensitive: false),
    GameFlavor.cata: RegExp(r'[-_]cata\.zip$', caseSensitive: false),
    GameFlavor.mists: RegExp(r'[-_]mists\.zip$', caseSensitive: false),
    GameFlavor.forever: RegExp(
      r'[-_](forever|camelot)\.zip$',
      caseSensitive: false,
    ),
  };

  Future<AddonRelease?> _pickAsset(
    Map<String, dynamic> release,
    GameFlavor flavor,
  ) async {
    final assets = release.objs('assets');
    final zips = assets.where(_isZip).toList();
    Map<String, dynamic>? asset;

    // BigWigs packager metadata names the right zip per flavor.
    final meta = assets.where((a) => a['name'] == 'release.json').firstOrNull;
    if (meta != null) {
      try {
        final json = await _api.getJson(
          Uri.parse(meta.str('browser_download_url')!),
          headers: _headers,
        ) as Map<String, dynamic>;
        final entry = json.objs('releases').where((r) {
          if (r['nolib'] == true) return false;
          return r
              .objs('metadata')
              .any((m) => m['flavor'] == packagerFlavor(flavor));
        }).firstOrNull;
        if (entry != null) {
          asset = zips.where((a) => a['name'] == entry['filename']).firstOrNull;
        }
      } on Object {
        // Fall back to file name heuristics below.
      }
    }

    if (asset == null) {
      final usable = zips
          .where((a) => !(a.str('name') ?? '').toLowerCase().contains('-nolib'))
          .toList();
      final pattern = _flavorAsset[flavor];
      if (pattern != null) {
        asset = usable.where((a) => pattern.hasMatch(a['name'])).firstOrNull;
      } else {
        asset = usable
            .where(
              (a) => !_flavorAsset.values.any((p) => p.hasMatch(a['name'])),
            )
            .firstOrNull;
      }
    }
    if (asset == null) return null;

    return AddonRelease(
      id: '${release['id']}',
      version: release.str('tag_name') ?? release.str('name') ?? '?',
      channel: release['prerelease'] == true
          ? ReleaseChannel.beta
          : ReleaseChannel.stable,
      downloadUrl: asset.str('browser_download_url')!,
      releasedAt: release.date('published_at'),
      fileName: asset.str('name'),
      size: asset.integer('size'),
      changelogUrl: release.str('html_url'),
      notes: release.str('body'),
    );
  }

  bool _isZip(Map<String, dynamic> asset) {
    final type = asset.str('content_type');
    final name = (asset.str('name') ?? '').toLowerCase();
    return type == 'application/zip' ||
        type == 'application/x-zip-compressed' ||
        name.endsWith('.zip');
  }
}
