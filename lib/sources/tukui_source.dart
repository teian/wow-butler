import 'package:http/http.dart' as http;

import '../core/models/addon.dart';
import '../core/models/addon_folder.dart';
import '../core/models/game_flavor.dart';
import '../core/models/wow_installation.dart';
import 'addon_source.dart';
import 'api_client.dart';
import 'description.dart';

/// TukUI API (https://api.tukui.org): ElvUI, Tukui and a few companion
/// addons, served straight from the authors.
class TukuiSource extends AddonSource {
  TukuiSource(this._api);

  final ApiClient _api;

  static const _base = 'https://api.tukui.org/v1';

  /// Download URLs are signed per request, so the list is cached briefly.
  static const _cacheTtl = Duration(minutes: 2);
  List<Map<String, dynamic>>? _cache;
  DateTime? _cachedAt;

  @override
  AddonSourceId get id => AddonSourceId.tukui;

  Future<List<Map<String, dynamic>>> _all() async {
    final cachedAt = _cachedAt;
    if (_cache != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return _cache!;
    }
    final json = await _api.getJson(Uri.parse('$_base/addons')) as List;
    _cache = json.whereType<Map<String, dynamic>>().toList();
    _cachedAt = DateTime.now();
    return _cache!;
  }

  /// The patch this addon supports for [flavor], e.g. `5.5.4` for Mists.
  static String? patchFor(Map<String, dynamic> a, GameFlavor flavor) {
    final patches = [for (final p in (a['patch'] as List?) ?? const []) '$p'];
    final prefix = switch (flavor) {
      GameFlavor.vanilla => '1.',
      GameFlavor.tbc => '2.',
      GameFlavor.wrath => '3.',
      GameFlavor.cata => '4.',
      GameFlavor.mists => '5.',
      GameFlavor.retail => null,
    };
    if (prefix != null) {
      return patches.where((p) => p.startsWith(prefix)).firstOrNull;
    }
    return patches
        .where((p) => (int.tryParse(p.split('.').first) ?? 0) >= 6)
        .firstOrNull;
  }

  @override
  Future<List<RemoteAddon>> featured(GameFlavor flavor) async => [
    for (final a in await _all())
      if (patchFor(a, flavor) != null) _toRemote(a),
  ];

  @override
  Future<List<RemoteAddon>> search(String query, GameFlavor flavor) async {
    final q = query.toLowerCase();
    return [
      for (final a in await _all())
        if (patchFor(a, flavor) != null &&
            ('${a['name']} ${a['slug']} ${a['small_desc']}')
                .toLowerCase()
                .contains(q))
          _toRemote(a),
    ];
  }

  @override
  Future<RemoteAddon?> getById(String externalId, GameFlavor flavor) async {
    final a = (await _all())
        .where((a) => '${a['id']}' == externalId || a['slug'] == externalId)
        .firstOrNull;
    return a == null ? null : _toRemote(a);
  }

  @override
  Future<List<RemoteAddon>> getMany(List<String> ids, GameFlavor flavor) async {
    final wanted = ids.toSet();
    return [
      for (final a in await _all())
        if (wanted.contains('${a['id']}')) _toRemote(a),
    ];
  }

  @override
  Future<List<AddonMatch>> match(
    List<AddonFolder> folders,
    GameFlavor flavor,
  ) async {
    final all = await _all();
    final onDisk = {for (final f in folders) f.name.toLowerCase(): f.name};
    final matches = <AddonMatch>[];

    for (final a in all) {
      final directories = [
        for (final d in (a['directories'] as List?) ?? const []) '$d',
      ];
      final primary = directories.firstOrNull?.toLowerCase();
      final folder = folders.where((f) {
        if (!f.hasToc) return false;
        final projectId = f.toc!.tukuiProjectId;
        if (projectId != null) return projectId == '${a['id']}';
        return f.name.toLowerCase() == primary;
      }).firstOrNull;
      if (folder == null) continue;

      final toc = folder.toc!;
      final owned = {
        folder.name,
        for (final d in [...directories, ...toc.tukuiProjectFolders])
          ?onDisk[d.toLowerCase()],
      };
      // TOCs often prefix the version with "v" while the API does not.
      final version = toc.version?.replaceFirst(RegExp(r'^[vV]'), '');
      matches.add(
        AddonMatch(
          addon: _toRemote(a),
          folders: [folder.name, ...owned.where((n) => n != folder.name)],
          installedRelease: version == null
              ? null
              : AddonRelease(
                  id: version,
                  version: version,
                  channel: ReleaseChannel.stable,
                  downloadUrl: '',
                ),
        ),
      );
    }
    return matches;
  }

  @override
  Future<AddonDetails> details(RemoteAddon addon, GameFlavor flavor) async {
    final a = (await _all())
        .where((a) => '${a['id']}' == addon.externalId)
        .firstOrNull;
    if (a == null) return super.details(addon, flavor);
    return detailsFromDescription(
      markdown: a.str('desc') ?? a.str('small_desc'),
      screenshots: [
        for (final g in (a['gallery_url'] as List?) ?? const []) '$g',
        ?a.str('screenshot_url'),
      ],
      category: 'Interface',
      flavors: {
        for (final f in GameFlavor.values)
          if (patchFor(a, f) != null) f,
      },
    );
  }

  @override
  Future<String?> changelog(String externalId, AddonRelease release) async {
    final url = release.changelogUrl;
    if (url == null) return null;
    final response = await http.get(
      Uri.parse(url),
      headers: {'User-Agent': ApiClient.userAgent},
    );
    return response.statusCode == 200 ? response.body : null;
  }

  RemoteAddon _toRemote(Map<String, dynamic> a) {
    final version = a.str('version') ?? '?';
    final updated = DateTime.tryParse('${a['last_update']}T00:00:00Z');
    return RemoteAddon(
      source: id,
      externalId: '${a['id']}',
      name: a.str('name') ?? '?',
      summary: a.str('small_desc'),
      author: a.str('author'),
      thumbnailUrl: a.str('logo_square_url') ?? a.str('screenshot_url'),
      websiteUrl: a.str('web_url'),
      updatedAt: updated,
      releases: [
        if (a.str('url') case final url?)
          AddonRelease(
            // Release id is the version, so TOC detected installs compare
            // equal to the API listing.
            id: version,
            version: version,
            channel: ReleaseChannel.stable,
            downloadUrl: url,
            releasedAt: updated,
            changelogUrl: a.str('changelog_url'),
          ),
      ],
    );
  }
}
