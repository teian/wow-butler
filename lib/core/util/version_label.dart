final _archiveSuffix = RegExp(
  r'\.(zip|rar|7z|tar\.gz|tgz)$',
  caseSensitive: false,
);
final _versionNumber = RegExp(r'\d+(?:\.\d+)+(?:-[0-9A-Za-z.]+)?');

/// Turns a release name that is really a file name into a version.
///
/// Some authors publish files whose display name is the archive name, e.g.
/// `ForeverDungeonJournal1.7.1.zip`; this yields `1.7.1`. Names without an
/// archive extension are returned unchanged (trimmed).
String versionLabel(String raw) {
  final value = raw.trim();
  if (!_archiveSuffix.hasMatch(value)) return value;
  final stem = value.replaceFirst(_archiveSuffix, '');
  return _versionNumber.firstMatch(stem)?.group(0) ?? stem;
}
