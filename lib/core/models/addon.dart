import '../util/version_label.dart';
import 'game_flavor.dart';
import 'wow_installation.dart';

/// Where an addon is published.
enum AddonSourceId {
  curseforge('CurseForge'),
  wago('Wago'),
  wowup('WowUp Hub'),
  tukui('TukUI'),
  wowinterface('WoWInterface'),
  github('GitHub');

  const AddonSourceId(this.label);

  final String label;

  static AddonSourceId? tryParse(String? name) =>
      AddonSourceId.values.where((s) => s.name == name).firstOrNull;
}

/// A downloadable build of an addon.
class AddonRelease {
  const AddonRelease({
    required this.id,
    required this.version,
    required this.channel,
    required this.downloadUrl,
    this.releasedAt,
    this.fileName,
    this.changelogUrl,
    this.interfaces = const [],
    this.dependencies = const [],
    this.notes,
    this.size,
  });

  /// Source specific identifier (file id, release id, or version string).
  final String id;
  final String version;
  final ReleaseChannel channel;
  final String downloadUrl;
  final DateTime? releasedAt;
  final String? fileName;
  final String? changelogUrl;

  /// TOC interface numbers this release targets, when the source provides them.
  final List<int> interfaces;

  /// External ids (same source) of addons this release requires.
  final List<String> dependencies;

  /// Release notes, when the source ships them with the release listing.
  final String? notes;

  /// Download size in bytes, when known.
  final int? size;

  Map<String, dynamic> toJson() => {
    'id': id,
    'version': version,
    'channel': channel.name,
    'downloadUrl': downloadUrl,
    'releasedAt': releasedAt?.toIso8601String(),
    'fileName': fileName,
    'changelogUrl': changelogUrl,
    'interfaces': interfaces,
    'dependencies': dependencies,
    'size': size,
  };

  factory AddonRelease.fromJson(Map<String, dynamic> json) => AddonRelease(
    id: json['id'] as String,
    version: json['version'] as String,
    channel:
        ReleaseChannel.tryParse(json['channel'] as String?) ??
        ReleaseChannel.stable,
    downloadUrl: json['downloadUrl'] as String,
    releasedAt: DateTime.tryParse(json['releasedAt'] as String? ?? ''),
    fileName: json['fileName'] as String?,
    changelogUrl: json['changelogUrl'] as String?,
    interfaces: (json['interfaces'] as List?)?.cast<int>() ?? const [],
    dependencies: (json['dependencies'] as List?)?.cast<String>() ?? const [],
    size: json['size'] as int?,
  );
}

/// An addon as listed by a source (search results, featured lists, matches).
class RemoteAddon {
  const RemoteAddon({
    required this.source,
    required this.externalId,
    required this.name,
    this.summary,
    this.author,
    this.thumbnailUrl,
    this.websiteUrl,
    this.downloadCount,
    this.updatedAt,
    this.releases = const [],
    this.downloadsAllowed = true,
  });

  final AddonSourceId source;
  final String externalId;
  final String name;
  final String? summary;
  final String? author;
  final String? thumbnailUrl;
  final String? websiteUrl;
  final int? downloadCount;
  final DateTime? updatedAt;

  /// Latest known releases, typically one per channel.
  final List<AddonRelease> releases;

  /// `false` when the author disallows downloads through third-party tools
  /// (CurseForge's "allow mod distribution"); the addon can then only be
  /// installed from its website.
  final bool downloadsAllowed;

  String get key => '${source.name}:$externalId';

  /// The newest release acceptable for [channel].
  AddonRelease? latestFor(ReleaseChannel channel) {
    final candidates = releases
        .where((r) => channel.accepts(r.channel))
        .toList();
    if (candidates.isEmpty) return null;
    candidates.sort(_newestFirst);
    return candidates.first;
  }

  static int _newestFirst(AddonRelease a, AddonRelease b) {
    final ad = a.releasedAt, bd = b.releasedAt;
    if (ad != null && bd != null) return bd.compareTo(ad);
    // Without dates, prefer the more stable release.
    return a.channel.index.compareTo(b.channel.index);
  }
}

/// Another source that publishes the same addon as an installed one; the
/// user can switch to it, and website-only addons fall back to it.
class AddonAlternative {
  const AddonAlternative({
    required this.source,
    required this.externalId,
    required this.name,
    this.downloadsAllowed = true,
  });

  factory AddonAlternative.of(RemoteAddon remote) => AddonAlternative(
    source: remote.source,
    externalId: remote.externalId,
    name: remote.name,
    downloadsAllowed: remote.downloadsAllowed,
  );

  final AddonSourceId source;
  final String externalId;
  final String name;
  final bool downloadsAllowed;

  String get key => '${source.name}:$externalId';

  Map<String, dynamic> toJson() => {
    'source': source.name,
    'externalId': externalId,
    'name': name,
    'downloadsAllowed': downloadsAllowed,
  };

  static AddonAlternative? fromJson(Map<String, dynamic> json) {
    final source = AddonSourceId.tryParse(json['source'] as String?);
    final externalId = json['externalId'] as String?;
    if (source == null || externalId == null) return null;
    return AddonAlternative(
      source: source,
      externalId: externalId,
      name: json['name'] as String? ?? externalId,
      downloadsAllowed: json['downloadsAllowed'] as bool? ?? true,
    );
  }
}

/// An addon present in an installation's `Interface/AddOns` folder.
class InstalledAddon {
  const InstalledAddon({
    required this.id,
    required this.name,
    required this.folders,
    this.source,
    this.externalId,
    this.author,
    this.summary,
    this.thumbnailUrl,
    this.websiteUrl,
    this.installedVersion,
    this.installedReleaseId,
    this.installedAt,
    this.channel = ReleaseChannel.stable,
    this.autoUpdate = true,
    this.ignored = false,
    this.pinned = false,
    this.external = false,
    this.downloadsAllowed = true,
    this.manualSource = false,
    this.alternatives = const [],
    this.alternativesCheckedAt,
    this.latestRelease,
    this.interfaces = const [],
  });

  final String id;
  final String name;

  /// Top-level folders in `Interface/AddOns` owned by this addon. The first
  /// entry is the primary folder.
  final List<String> folders;

  /// `null` when the addon could not be matched to any source.
  final AddonSourceId? source;
  final String? externalId;
  final String? author;
  final String? summary;
  final String? thumbnailUrl;
  final String? websiteUrl;
  final String? installedVersion;
  final String? installedReleaseId;
  final DateTime? installedAt;
  final ReleaseChannel channel;

  /// Per-addon opt-out of automatic updates; only effective while automatic
  /// updates are enabled globally.
  final bool autoUpdate;

  /// No update hints at all.
  final bool ignored;

  /// Stays on the installed version; newer versions are still shown.
  final bool pinned;

  /// A local addon that is only available through a subscription or its own
  /// client (Zygor, RestedXP, …), so no source can ever manage it.
  final bool external;

  /// Mirrors [RemoteAddon.downloadsAllowed] of the assigned source.
  final bool downloadsAllowed;

  /// The user picked [source] as the primary source; syncs and the
  /// automatic fallback to other sources keep it.
  final bool manualSource;

  /// Other sources that publish this addon, in no particular order.
  final List<AddonAlternative> alternatives;

  /// When other sources were last searched for this addon by name.
  final DateTime? alternativesCheckedAt;

  /// Most recent release for [channel], refreshed by update checks.
  final AddonRelease? latestRelease;
  final List<int> interfaces;

  bool get isManaged => source != null && externalId != null;

  String? get remoteKey => isManaged ? '${source!.name}:$externalId' : null;

  /// A release other than the installed one is available.
  bool get newerAvailable {
    final latest = latestRelease;
    if (!isManaged || latest == null) return false;
    if (installedReleaseId != null) return latest.id != installedReleaseId;
    return latest.version != installedVersion;
  }

  /// Whether the addon takes part in updates.
  bool get hasUpdate => newerAvailable && !ignored && !pinned;

  /// The author disallows downloads through third-party tools (CurseForge
  /// returns no download URL), so the update has to come from the website.
  bool get updateNeedsWebsite =>
      hasUpdate &&
      (!downloadsAllowed || (latestRelease?.downloadUrl.isEmpty ?? false));

  InstalledAddon copyWith({
    String? name,
    List<String>? folders,
    AddonSourceId? source,
    String? externalId,
    String? author,
    String? summary,
    String? thumbnailUrl,
    String? websiteUrl,
    String? installedVersion,
    String? installedReleaseId,
    bool clearInstalledReleaseId = false,
    DateTime? installedAt,
    ReleaseChannel? channel,
    bool? autoUpdate,
    bool? ignored,
    bool? pinned,
    bool? external,
    bool? downloadsAllowed,
    bool? manualSource,
    List<AddonAlternative>? alternatives,
    DateTime? alternativesCheckedAt,
    AddonRelease? latestRelease,
    bool clearLatestRelease = false,
    List<int>? interfaces,
  }) => InstalledAddon(
    id: id,
    name: name ?? this.name,
    folders: folders ?? this.folders,
    source: source ?? this.source,
    externalId: externalId ?? this.externalId,
    author: author ?? this.author,
    summary: summary ?? this.summary,
    thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    websiteUrl: websiteUrl ?? this.websiteUrl,
    installedVersion: installedVersion ?? this.installedVersion,
    installedReleaseId: clearInstalledReleaseId
        ? null
        : installedReleaseId ?? this.installedReleaseId,
    installedAt: installedAt ?? this.installedAt,
    channel: channel ?? this.channel,
    autoUpdate: autoUpdate ?? this.autoUpdate,
    ignored: ignored ?? this.ignored,
    pinned: pinned ?? this.pinned,
    external: external ?? this.external,
    downloadsAllowed: downloadsAllowed ?? this.downloadsAllowed,
    manualSource: manualSource ?? this.manualSource,
    alternatives: alternatives ?? this.alternatives,
    alternativesCheckedAt: alternativesCheckedAt ?? this.alternativesCheckedAt,
    latestRelease: clearLatestRelease
        ? null
        : latestRelease ?? this.latestRelease,
    interfaces: interfaces ?? this.interfaces,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'folders': folders,
    'source': source?.name,
    'externalId': externalId,
    'author': author,
    'summary': summary,
    'thumbnailUrl': thumbnailUrl,
    'websiteUrl': websiteUrl,
    'installedVersion': installedVersion,
    'installedReleaseId': installedReleaseId,
    'installedAt': installedAt?.toIso8601String(),
    'channel': channel.name,
    'autoUpdate': autoUpdate,
    'ignored': ignored,
    'pinned': pinned,
    'external': external,
    'downloadsAllowed': downloadsAllowed,
    'manualSource': manualSource,
    'alternatives': alternatives.map((a) => a.toJson()).toList(),
    'alternativesCheckedAt': alternativesCheckedAt?.toIso8601String(),
    'latestRelease': latestRelease?.toJson(),
    'interfaces': interfaces,
  };

  factory InstalledAddon.fromJson(Map<String, dynamic> json) => InstalledAddon(
    id: json['id'] as String,
    name: json['name'] as String,
    folders: (json['folders'] as List).cast<String>(),
    source: AddonSourceId.tryParse(json['source'] as String?),
    externalId: json['externalId'] as String?,
    author: json['author'] as String?,
    summary: json['summary'] as String?,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    websiteUrl: json['websiteUrl'] as String?,
    // Older releases stored archive names such as `Foo1.2.zip` as version.
    installedVersion: switch (json['installedVersion']) {
      final String v => versionLabel(v),
      _ => null,
    },
    installedReleaseId: json['installedReleaseId'] as String?,
    installedAt: DateTime.tryParse(json['installedAt'] as String? ?? ''),
    channel:
        ReleaseChannel.tryParse(json['channel'] as String?) ??
        ReleaseChannel.stable,
    autoUpdate: json['autoUpdate'] as bool? ?? true,
    ignored: json['ignored'] as bool? ?? false,
    pinned: json['pinned'] as bool? ?? false,
    external: json['external'] as bool? ?? false,
    downloadsAllowed: json['downloadsAllowed'] as bool? ?? true,
    manualSource: json['manualSource'] as bool? ?? false,
    alternatives: [
      for (final a in (json['alternatives'] as List?) ?? const [])
        ?AddonAlternative.fromJson(a as Map<String, dynamic>),
    ],
    alternativesCheckedAt: DateTime.tryParse(
      json['alternativesCheckedAt'] as String? ?? '',
    ),
    latestRelease: json['latestRelease'] == null
        ? null
        : AddonRelease.fromJson(json['latestRelease'] as Map<String, dynamic>),
    interfaces: (json['interfaces'] as List?)?.cast<int>() ?? const [],
  );
}

/// Extended information for the addon detail page, loaded on demand.
class AddonDetails {
  const AddonDetails({
    this.paragraphs = const [],
    this.features = const [],
    this.screenshots = const [],
    this.category,
    this.flavors,
  });

  final List<String> paragraphs;

  /// Bullet points taken from the description.
  final List<String> features;
  final List<String> screenshots;
  final String? category;

  /// Game flavors the addon publishes files for; `null` when the source
  /// cannot tell.
  final Set<GameFlavor>? flavors;
}
