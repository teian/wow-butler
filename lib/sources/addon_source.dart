import '../core/models/addon.dart';
import '../core/models/addon_category.dart';
import '../core/models/addon_folder.dart';
import '../core/models/game_flavor.dart';

/// An installed addon identified by a source, covering one or more folders.
class AddonMatch {
  const AddonMatch({
    required this.addon,
    required this.folders,
    this.installedRelease,
  });

  final RemoteAddon addon;

  /// Names of the matched folders; the primary folder comes first.
  final List<String> folders;

  /// The release that is currently on disk, when the source can tell.
  final AddonRelease? installedRelease;
}

/// A place addons are published: CurseForge, Wago, WowUp Hub, TukUI, GitHub.
abstract class AddonSource {
  AddonSourceId get id;

  /// Why the source cannot be used right now (e.g. missing API key), or
  /// `null` if it is ready.
  String? get unavailableReason => null;

  bool get isAvailable => unavailableReason == null;

  /// Whether free text search is supported. GitHub only resolves URLs.
  bool get supportsTextSearch => true;

  /// Whether installed folders can be identified by this source.
  bool get supportsMatching => true;

  Future<List<RemoteAddon>> featured(GameFlavor flavor);

  Future<List<RemoteAddon>> search(String query, GameFlavor flavor);

  /// Lists addons for the discover page, optionally narrowed to [category].
  ///
  /// Sources without their own category taxonomy fall back to a keyword
  /// filter over name and summary; sources that support it server side
  /// (CurseForge) override this.
  Future<List<RemoteAddon>> browse(
    String query,
    GameFlavor flavor, {
    AddonCategory? category,
  }) async {
    final results = query.isEmpty
        ? await featured(flavor)
        : await search(query, flavor);
    if (category == null) return results;
    return [
      for (final a in results)
        if (category.matches(a)) a,
    ];
  }

  Future<RemoteAddon?> getById(String externalId, GameFlavor flavor);

  /// Fetches current release information for many addons at once.
  Future<List<RemoteAddon>> getMany(List<String> ids, GameFlavor flavor);

  /// Identifies which of [folders] belong to addons published here.
  Future<List<AddonMatch>> match(List<AddonFolder> folders, GameFlavor flavor);

  /// Long description, screenshots and compatibility for the detail page.
  Future<AddonDetails> details(RemoteAddon addon, GameFlavor flavor) async =>
      AddonDetails(paragraphs: [?addon.summary]);

  /// Release notes of [release] as plain text or markdown, if available.
  Future<String?> changelog(String externalId, AddonRelease release) async =>
      release.notes;

  /// The page where a user downloads [release] in the browser, for addons
  /// whose author disallows downloads through third-party tools.
  String? websiteDownloadUrl(RemoteAddon addon, AddonRelease release) =>
      addon.websiteUrl;

  /// The request used to download [release]; adds auth where needed.
  ({Uri uri, Map<String, String> headers}) downloadRequest(
    AddonRelease release,
  ) => (uri: Uri.parse(release.downloadUrl), headers: const {});

  /// The download requests to try in order for [release] of [addon], stopping
  /// at the first that succeeds. Sources with short-lived URLs resolve them
  /// here, and sources whose CDN is picky about clients can offer a second
  /// attempt with a different user agent.
  Future<List<({Uri uri, Map<String, String> headers})>> downloadRequests(
    RemoteAddon addon,
    AddonRelease release,
  ) async => [downloadRequest(release)];
}
