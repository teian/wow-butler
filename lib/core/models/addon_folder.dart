import '../fingerprint/folder_fingerprint.dart';
import '../toc/toc_file.dart';

/// A top-level folder in `Interface/AddOns` as found on disk.
class AddonFolder {
  const AddonFolder({
    required this.name,
    required this.path,
    this.toc,
    this.fingerprint,
    this.hasAnyToc = false,
  });

  final String name;
  final String path;

  /// The TOC the game would load for the installation's flavor. `null` means
  /// the folder is not loadable by this client (or not an addon at all).
  final TocFile? toc;

  /// `null` when the folder has no TOC at all.
  final FolderFingerprint? fingerprint;

  /// Whether the folder has a TOC for any game flavor.
  final bool hasAnyToc;

  bool get hasToc => toc != null;
}
