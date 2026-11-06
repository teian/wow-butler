import '../core/models/addon.dart';
import '../core/models/addon_folder.dart';
import '../core/models/game_flavor.dart';
import '../core/models/wow_installation.dart';
import 'addon_source.dart';
import 'api_client.dart';
import 'description.dart';

/// WowUp Hub (https://hub.wowup.io): GitHub hosted addons indexed by WowUp.
/// Public, no authentication.
class WowUpSource extends AddonSource {
  WowUpSource(this._api);

  final ApiClient _api;

  static const _base = 'https://hub.wowup.io';
  static const _website = 'https://wowup.io';

  @override
  AddonSourceId get id => AddonSourceId.wowup;

  static String gameType(GameFlavor flavor) => switch (flavor) {
    GameFlavor.retail => 'retail',
    GameFlavor.vanilla => 'classic',
    GameFlavor.tbc => 'burningCrusade',
    GameFlavor.wrath => 'wotlk',
    GameFlavor.cata => 'cata',
    GameFlavor.mists => 'mists',
    GameFlavor.forever => 'forever',
  };

  @override
  Future<List<RemoteAddon>> featured(GameFlavor flavor) async {
    final uri = Uri.parse('$_base/addons/featured/${gameType(flavor)}')
        .replace(queryParameters: {'count': '60', 'recent': '30'});
    final json = await _api.getJson(uri) as Map<String, dynamic>;
    final seen = <String>{};
    return [
      for (final a in [...json.objs('addons'), ...json.objs('recent')])
        if (seen.add('${a['id']}')) _toRemote(a, flavor),
    ];
  }

  @override
  Future<List<RemoteAddon>> search(String query, GameFlavor flavor) async {
    final uri = Uri.parse('$_base/addons/search/${gameType(flavor)}')
        .replace(queryParameters: {'query': query, 'limit': '50'});
    final json = await _api.getJson(uri) as Map<String, dynamic>;
    return [for (final a in json.objs('addons')) _toRemote(a, flavor)];
  }

  @override
  Future<RemoteAddon?> getById(String externalId, GameFlavor flavor) async {
    final json = await _api.getJson(
      Uri.parse('$_base/addons/$externalId'),
    ) as Map<String, dynamic>;
    final addon = json.obj('addon');
    return addon == null ? null : _toRemote(addon, flavor);
  }

  @override
  Future<List<RemoteAddon>> getMany(List<String> ids, GameFlavor flavor) async {
    if (ids.isEmpty) return const [];
    final json = await _api.postJson(
      Uri.parse('$_base/addons/batch/${gameType(flavor)}'),
      {'addonIds': ids.map(int.parse).toList()},
    ) as Map<String, dynamic>;
    return [for (final a in json.objs('addons')) _toRemote(a, flavor)];
  }

  @override
  Future<List<AddonMatch>> match(
    List<AddonFolder> folders,
    GameFlavor flavor,
  ) async {
    final candidates = folders
        .where((f) => f.hasToc && f.fingerprint != null)
        .toList();
    if (candidates.isEmpty) return const [];
    final hashes = {for (final f in candidates) f.fingerprint!.md5};

    final json = await _api.postJson(Uri.parse('$_base/addons/fingerprint'), {
      'fingerprints': hashes.toList(),
    }) as Map<String, dynamic>;

    final type = gameType(flavor);
    final onDisk = {for (final f in folders) f.name.toLowerCase(): f.name};
    final byId = <String, AddonMatch>{};

    // Prefer matches whose release targets this client.
    final exact = json.objs('exactMatches')
      ..sort(
        (a, b) => (_targets(b.obj('matched_release'), type) ? 1 : 0).compareTo(
          _targets(a.obj('matched_release'), type) ? 1 : 0,
        ),
      );
    for (final addon in exact) {
      final release = addon.obj('matched_release');
      if (release == null) continue;
      final addonFolders = release.objs('addonFolders');
      if (!addonFolders.any((f) => hashes.contains(f['fingerprint']))) {
        continue;
      }
      final remote = _toRemote(addon, flavor);
      byId.putIfAbsent(
        remote.externalId,
        () => AddonMatch(
          addon: remote,
          folders: [
            for (final f in addonFolders)
              ?onDisk[(f['folder_name'] as String? ?? '').toLowerCase()],
          ],
          installedRelease: _toRelease(release),
        ),
      );
    }
    return byId.values.toList();
  }

  @override
  Future<AddonDetails> details(RemoteAddon addon, GameFlavor flavor) async {
    final json = await _api.getJson(
      Uri.parse('$_base/addons/${addon.externalId}'),
    ) as Map<String, dynamic>;
    final a = json.obj('addon') ?? const {};
    final releases = [...a.objs('releases'), ?a.obj('current_release')];
    final types = {
      for (final r in releases)
        for (final gv in r.objs('game_versions')) gv['game_type'],
    };
    return detailsFromDescription(
      html: a.str('description'),
      screenshots: [
        for (final r in releases.take(1))
          for (final p in r.objs('previews'))
            if (p['preview_type'] != 'video') ?p.str('url'),
      ],
      category: (a['topics'] as List?)?.whereType<String>().firstOrNull,
      flavors: {
        for (final f in GameFlavor.values)
          if (types.contains(gameType(f))) f,
      },
    );
  }

  bool _targets(Map<String, dynamic>? release, String type) =>
      release != null &&
      release.objs('game_versions').any((gv) => gv['game_type'] == type);

  RemoteAddon _toRemote(Map<String, dynamic> a, GameFlavor flavor) {
    final type = gameType(flavor);
    final releases = [
      ...a.objs('releases'),
      ?a.obj('current_release'),
    ].where((r) => _targets(r, type));

    final seen = <String>{};
    final description = a.str('description');
    return RemoteAddon(
      source: id,
      externalId: '${a['id']}',
      name: a.str('repository_name') ?? a.str('repository') ?? '?',
      summary: description == null ? null : plainText(description),
      author: a.str('owner_name'),
      thumbnailUrl: a.str('image_url') ?? a.str('owner_image_url'),
      websiteUrl: a.str('homepage') ?? '$_website/addons/${a['id']}',
      downloadCount: a.integer('total_download_count'),
      releases: [
        for (final r in releases)
          if (seen.add('${r['id']}')) ?_toRelease(r),
      ],
    );
  }

  AddonRelease? _toRelease(Map<String, dynamic> r) {
    final url = r.str('download_url');
    if (url == null) return null;
    return AddonRelease(
      id: '${r['id']}',
      version: r.str('tag_name') ?? r.str('name') ?? '?',
      channel: r['prerelease'] == true
          ? ReleaseChannel.beta
          : ReleaseChannel.stable,
      downloadUrl: url,
      releasedAt: r.date('published_at'),
      notes: r.str('body'),
      interfaces: [
        for (final gv in r.objs('game_versions'))
          ?int.tryParse('${gv['interface']}'),
      ],
    );
  }
}
