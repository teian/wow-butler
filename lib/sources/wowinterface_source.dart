import '../core/models/addon.dart';
import '../core/models/addon_folder.dart';
import '../core/models/game_flavor.dart';
import '../core/models/wow_installation.dart';
import 'addon_source.dart';
import 'api_client.dart';
import 'description.dart';

/// WoWInterface (https://www.wowinterface.com) through the public Minion
/// API at api.mmoui.com. No key required. The file list carries metadata
/// and folder names; download URL, description and changelog come from
/// the filedetails endpoint.
class WowInterfaceSource extends AddonSource {
  WowInterfaceSource(this._api);

  final ApiClient _api;

  static const _base = 'https://api.mmoui.com/v3/game/WOW';

  /// The full list is ~5 MB, so it is cached for a while.
  static const _cacheTtl = Duration(minutes: 15);
  List<Map<String, dynamic>>? _cache;
  DateTime? _cachedAt;

  @override
  AddonSourceId get id => AddonSourceId.wowinterface;

  Future<List<Map<String, dynamic>>> _all() async {
    final cachedAt = _cachedAt;
    if (_cache != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return _cache!;
    }
    final json = await _api.getJson(Uri.parse('$_base/filelist.json')) as List;
    _cache = json.whereType<Map<String, dynamic>>().toList();
    _cachedAt = DateTime.now();
    return _cache!;
  }

  /// Compatibility entries name plain game versions (`11.0.2`, `1.15.2`).
  /// Listings without any entry are treated as retail only, and
  /// WoWInterface does not host Forever addons at all.
  static bool isCompatible(Map<String, dynamic> a, GameFlavor flavor) {
    if (flavor == GameFlavor.forever) return false;
    final entries = ((a['UICompatibility'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (entries.isEmpty) return flavor == GameFlavor.retail;
    for (final e in entries) {
      final parts = '${e['version']}'.split('.');
      final major = int.tryParse(parts.first);
      final minor = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      if (major != null && GameFlavor.fromVersion(major, minor) == flavor) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<List<RemoteAddon>> featured(GameFlavor flavor) async {
    final all = (await _all()).where((a) => isCompatible(a, flavor)).toList()
      ..sort(
        (a, b) => (int.tryParse('${b['UIDownloadMonthly']}') ?? 0).compareTo(
          int.tryParse('${a['UIDownloadMonthly']}') ?? 0,
        ),
      );
    return [for (final a in all.take(60)) _toRemote(a)];
  }

  @override
  Future<List<RemoteAddon>> search(String query, GameFlavor flavor) async {
    final q = query.toLowerCase();
    final hits = (await _all())
        .where((a) => isCompatible(a, flavor))
        .where(
          (a) =>
              '${a['UIName']} ${a['UIAuthorName']}'.toLowerCase().contains(q),
        )
        .toList()
      ..sort(
        (a, b) => (int.tryParse('${b['UIDownloadTotal']}') ?? 0).compareTo(
          int.tryParse('${a['UIDownloadTotal']}') ?? 0,
        ),
      );
    return [for (final a in hits.take(50)) _toRemote(a)];
  }

  @override
  Future<RemoteAddon?> getById(String externalId, GameFlavor flavor) async =>
      (await getMany([externalId], flavor)).firstOrNull;

  @override
  Future<List<RemoteAddon>> getMany(List<String> ids, GameFlavor flavor) async {
    if (ids.isEmpty) return const [];
    final listed = {for (final a in await _all()) '${a['UID']}': a};
    final json =
        await _api.getJson(
              Uri.parse('$_base/filedetails/${ids.join(',')}.json'),
            )
            as List;
    return [
      for (final d in json.whereType<Map<String, dynamic>>())
        _toRemote(listed['${d['UID']}'] ?? d, details: d),
    ];
  }

  /// Matching is driven by the `X-WoWI-ID` TOC field; the listing's folder
  /// names then claim the sibling folders on disk.
  @override
  Future<List<AddonMatch>> match(
    List<AddonFolder> folders,
    GameFlavor flavor,
  ) async {
    final byId = <String, List<AddonFolder>>{};
    for (final f in folders) {
      if (!f.hasToc) continue;
      final id = f.toc!.wowInterfaceId;
      if (id != null) byId.putIfAbsent(id, () => []).add(f);
    }
    if (byId.isEmpty) return const [];

    final listed = {for (final a in await _all()) '${a['UID']}': a};
    final onDisk = {for (final f in folders) f.name.toLowerCase(): f.name};
    final matches = <AddonMatch>[];
    for (final entry in byId.entries) {
      final a = listed[entry.key];
      if (a == null) continue;
      final version = _cleanVersion(a.str('UIVersion'));
      final tocVersion = _cleanVersion(entry.value.first.toc?.version);
      matches.add(
        AddonMatch(
          addon: _toRemote(a),
          folders: {
            for (final f in entry.value) f.name,
            for (final dir in (a['UIDir'] as List?) ?? const [])
              ?onDisk['$dir'.toLowerCase()],
          }.toList(),
          installedRelease: tocVersion != null && tocVersion == version
              ? _release(a)
              : null,
        ),
      );
    }
    return matches;
  }

  @override
  Future<AddonDetails> details(RemoteAddon addon, GameFlavor flavor) async {
    final a = (await _all())
        .where((e) => '${e['UID']}' == addon.externalId)
        .firstOrNull;
    final json =
        await _api.getJson(
              Uri.parse('$_base/filedetails/${addon.externalId}.json'),
            )
            as List;
    final d = json.whereType<Map<String, dynamic>>().firstOrNull;
    return detailsFromDescription(
      markdown: _stripBbcode(d?.str('UIDescription') ?? ''),
      screenshots: [
        for (final img in (a?['UIIMGs'] as List?) ?? const []) '$img',
      ],
      flavors: a == null
          ? null
          : {
              for (final f in GameFlavor.values)
                if (isCompatible(a, f)) f,
            },
    );
  }

  @override
  Future<String?> changelog(String externalId, AddonRelease release) async {
    final json =
        await _api.getJson(Uri.parse('$_base/filedetails/$externalId.json'))
            as List;
    final log = json
        .whereType<Map<String, dynamic>>()
        .firstOrNull
        ?.str('UIChangeLog');
    return log == null ? null : _stripBbcode(htmlToText(log));
  }

  RemoteAddon _toRemote(Map<String, dynamic> a, {Map<String, dynamic>? details}) {
    return RemoteAddon(
      source: id,
      externalId: '${a['UID']}',
      name: a.str('UIName') ?? '?',
      summary: details == null
          ? null
          : plainText(_stripBbcode(details.str('UIDescription') ?? '')),
      author: a.str('UIAuthorName'),
      thumbnailUrl: [
        for (final t in (a['UIIMG_Thumbs'] as List?) ?? const []) '$t',
      ].firstOrNull,
      websiteUrl: a.str('UIFileInfoURL'),
      downloadCount: int.tryParse(
        '${a['UIDownloadTotal'] ?? a['UIHitCount']}',
      ),
      updatedAt: _date(a),
      releases: [?_release(a, details: details)],
    );
  }

  AddonRelease? _release(
    Map<String, dynamic> a, {
    Map<String, dynamic>? details,
  }) {
    final version = _cleanVersion(
      (details ?? a).str('UIVersion') ?? a.str('UIVersion'),
    );
    if (version == null) return null;
    final date = _date(details ?? a) ?? _date(a);
    // filedetails carries the authoritative URL; list entries derive it
    // from the stable Minion download pattern.
    final url =
        details?.str('UIDownload') ??
        (date == null
            ? null
            : '$_downloadBase?id=${a['UID']}'
                  '&d=${date.millisecondsSinceEpoch ~/ 1000}&minion');
    if (url == null) return null;
    return AddonRelease(
      // The version doubles as release id, so installs recognized through
      // the TOC compare equal to the listing.
      id: version,
      version: version,
      channel: ReleaseChannel.stable,
      downloadUrl: url,
      releasedAt: date,
      fileName: details?.str('UIFileName'),
    );
  }

  static const _downloadBase =
      'https://cdn.wowinterface.com/downloads/getfile.php';

  DateTime? _date(Map<String, dynamic> a) {
    final ms = a.integer('UIDate');
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  /// `v1.54.04` and `1.54.04` are the same release.
  String? _cleanVersion(String? v) {
    final cleaned = v?.trim().replaceFirst(RegExp(r'^[vV]'), '');
    return (cleaned == null || cleaned.isEmpty) ? null : cleaned;
  }

  /// WoWInterface descriptions and changelogs are BBCode.
  static String _stripBbcode(String s) => s
      .replaceAllMapped(
        RegExp(r'\[URL=[^\]]*\](.*?)\[/URL\]', caseSensitive: false, dotAll: true),
        (m) => m.group(1)!,
      )
      .replaceAll(
        RegExp(r'\[IMG\].*?\[/IMG\]', caseSensitive: false, dotAll: true),
        '',
      )
      .replaceAll(RegExp(r'^\s*\[\*\]\s*', multiLine: true), '- ')
      .replaceAll(
        RegExp(
          r'\[/?(B|I|U|S|URL|COLOR|SIZE|FONT|CENTER|LEFT|RIGHT|QUOTE|CODE|'
          r'LIST|INDENT|HIGHLIGHT|SPOILER|H[1-6])[^\]]*\]',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
}
