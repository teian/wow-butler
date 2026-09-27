import '../core/models/addon.dart';
import '../core/models/addon_folder.dart';
import '../core/models/game_flavor.dart';
import '../core/models/wow_installation.dart';
import 'addon_source.dart';
import 'api_client.dart';
import 'description.dart';

/// Wago Addons (https://addons.wago.io). Requires a personal access key,
/// available to Wago subscribers under account → API keys.
class WagoSource extends AddonSource {
  WagoSource(this._api, this._apiKey);

  final ApiClient _api;
  final String? _apiKey;

  static const _base = 'https://addons.wago.io/api/external';

  @override
  AddonSourceId get id => AddonSourceId.wago;

  @override
  String? get unavailableReason => (_apiKey == null || _apiKey.length < 20)
      ? 'Wago benötigt einen Access-Key (Einstellungen → Quellen).'
      : null;

  Map<String, String> get _headers => {'Authorization': 'Bearer $_apiKey'};

  static String gameVersion(GameFlavor flavor) => switch (flavor) {
    GameFlavor.retail => 'retail',
    GameFlavor.vanilla => 'classic',
    GameFlavor.tbc => 'bc',
    GameFlavor.wrath => 'wotlk',
    GameFlavor.cata => 'cata',
    GameFlavor.mists => 'mop',
  };

  @override
  Future<List<RemoteAddon>> featured(GameFlavor flavor) async {
    final uri = Uri.parse('$_base/addons/popular')
        .replace(queryParameters: {'game_version': gameVersion(flavor)});
    final json =
        await _api.getJson(uri, headers: _headers) as Map<String, dynamic>;
    return [for (final a in json.objs('data')) _fromSearchItem(a)];
  }

  @override
  Future<List<RemoteAddon>> search(String query, GameFlavor flavor) async {
    final uri = Uri.parse('$_base/addons/_search').replace(
      queryParameters: {
        'query': query,
        'game_version': gameVersion(flavor),
        'stability': 'alpha',
      },
    );
    final json =
        await _api.getJson(uri, headers: _headers) as Map<String, dynamic>;
    return [for (final a in json.objs('data')) _fromSearchItem(a)];
  }

  @override
  Future<RemoteAddon?> getById(String externalId, GameFlavor flavor) async {
    final results = await getMany([externalId], flavor);
    return results.firstOrNull;
  }

  @override
  Future<List<RemoteAddon>> getMany(List<String> ids, GameFlavor flavor) async {
    if (ids.isEmpty) return const [];
    final json = await _api.postJson(Uri.parse('$_base/addons/_recents'), {
      'game_version': gameVersion(flavor),
      'addons': ids,
    }, headers: _headers) as Map<String, dynamic>;
    final addons = json.obj('addons') ?? const {};
    return [
      for (final entry in addons.entries)
        if (entry.value is Map<String, dynamic>)
          _fromScanAddon(
            entry.value as Map<String, dynamic>,
            fallbackId: entry.key,
          ),
    ];
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

    final json = await _api.postJson(Uri.parse('$_base/addons/_match'), {
      'game_version': gameVersion(flavor),
      'addons': [
        for (final f in candidates)
          {
            'name': f.name,
            'hash': f.fingerprint!.md5,
            if (f.toc!.wagoId != null) 'wago': f.toc!.wagoId,
          },
      ],
    }, headers: _headers) as Map<String, dynamic>;

    final hashes = {for (final f in candidates) f.fingerprint!.md5};
    final onDisk = {for (final f in folders) f.name.toLowerCase(): f.name};
    final matches = <AddonMatch>[];
    final seen = <String>{};

    for (final scan in json.objs('addons')) {
      final modules = scan.obj('modules') ?? const {};
      final matched = modules.values.whereType<Map<String, dynamic>>().any(
        (m) => hashes.contains(m['hash']),
      );
      final remote = _fromScanAddon(scan);
      if (!matched || !seen.add(remote.externalId)) continue;

      final installed = scan.obj('matched_release');
      matches.add(
        AddonMatch(
          addon: remote,
          folders: [
            for (final e in modules.entries)
              if (e.value is Map && (e.value as Map)['hash'] is String)
                ?onDisk[e.key.toLowerCase()],
          ],
          installedRelease: installed == null
              ? null
              : _release(
                  installed,
                  _channelOf(installed, ReleaseChannel.stable),
                ),
        ),
      );
    }
    return matches;
  }

  @override
  Future<AddonDetails> details(RemoteAddon addon, GameFlavor flavor) async {
    final json = await _api.getJson(
      Uri.parse('$_base/addons/${addon.externalId}'),
      headers: _headers,
    ) as Map<String, dynamic>;
    final a = json.obj('data') ?? json;
    // Releases carry `supported_<game>_patch` keys for every client they
    // target.
    final releases = [
      ...(a.obj('recent_releases') ?? a.obj('recent_release') ?? const {})
          .values
          .whereType<Map<String, dynamic>>(),
    ];
    const patchKeys = {
      'retail': GameFlavor.retail,
      'classic': GameFlavor.vanilla,
      'bc': GameFlavor.tbc,
      'wotlk': GameFlavor.wrath,
      'cata': GameFlavor.cata,
      'mop': GameFlavor.mists,
    };
    final flavors = {
      for (final r in releases)
        for (final e in patchKeys.entries)
          if (r['supported_${e.key}_patch'] != null) e.value,
    };
    return detailsFromDescription(
      markdown: a.str('description') ?? a.str('summary'),
      screenshots: [
        for (final g in (a['gallery'] as List?) ?? const [])
          if (g is String)
            g
          else if (g is Map)
            ?(g['url'] ?? g['image'] ?? g['src'])?.toString(),
      ],
      flavors: flavors.isEmpty ? null : flavors,
    );
  }

  @override
  ({Uri uri, Map<String, String> headers}) downloadRequest(
    AddonRelease release,
  ) {
    final uri = Uri.parse(release.downloadUrl);
    return (
      uri: uri.replace(
        queryParameters: {...uri.queryParameters, 'token': _apiKey ?? ''},
      ),
      headers: const {},
    );
  }

  RemoteAddon _fromSearchItem(Map<String, dynamic> a) {
    final releases = a.obj('releases') ?? const {};
    return RemoteAddon(
      source: id,
      externalId: a.str('id') ?? '',
      name: a.str('display_name') ?? a.str('name') ?? '?',
      summary: a.str('summary'),
      author: _authors(a['authors']),
      thumbnailUrl: a.str('thumbnail_image') ?? a.str('thumbnail'),
      websiteUrl: a.str('website_url'),
      downloadCount: a.integer('download_count'),
      releases: _releases(releases),
    );
  }

  RemoteAddon _fromScanAddon(Map<String, dynamic> a, {String? fallbackId}) =>
      RemoteAddon(
        source: id,
        externalId: a.str('id') ?? fallbackId ?? '',
        name: a.str('display_name') ?? a.str('name') ?? '?',
        summary: a.str('summary'),
        author: _authors(a['authors']),
        thumbnailUrl: a.str('thumbnail') ?? a.str('thumbnail_image'),
        websiteUrl: a.str('website_url'),
        releases: _releases(
          a.obj('recent_releases') ?? a.obj('recent_release') ?? const {},
        ),
      );

  List<AddonRelease> _releases(Map<String, dynamic> byStability) => [
    for (final channel in ReleaseChannel.values)
      if (byStability.obj(channel.name) case final r?) _release(r, channel),
  ];

  /// Wago identifies releases by their label (the version string); it is the
  /// only field present in every endpoint's release shape.
  AddonRelease _release(Map<String, dynamic> r, ReleaseChannel channel) =>
      AddonRelease(
        id: r.str('label') ?? r.str('id') ?? '',
        version: r.str('label') ?? '?',
        channel: channel,
        downloadUrl: r.str('download_link') ?? r.str('link') ?? '',
        releasedAt: r.date('created_at'),
        notes: r.str('changelog'),
      );

  ReleaseChannel _channelOf(Map<String, dynamic> r, ReleaseChannel fallback) =>
      ReleaseChannel.tryParse(r.str('stability')) ?? fallback;

  String? _authors(Object? authors) {
    if (authors is String) return authors;
    if (authors is List && authors.isNotEmpty) {
      return authors
          .map((a) => a is Map ? (a['name'] ?? '').toString() : '$a')
          .where((s) => s.isNotEmpty)
          .join(', ');
    }
    return null;
  }
}
