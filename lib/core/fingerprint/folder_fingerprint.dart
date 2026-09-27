import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import 'murmur2.dart';

/// Fingerprints of one addon folder, compatible with the hashes CurseForge,
/// Wago and the WowUp Hub use to identify installed addons.
///
/// Port of WoWUp's `curse-folder-scanner.ts` and `wowup-folder-scanner.ts`:
/// only files the client actually loads are hashed (TOCs, `Bindings.xml` and
/// everything reachable through TOC entries and XML `Include`/`Script` tags).
class FolderFingerprint {
  const FolderFingerprint({required this.curse, required this.md5});

  /// CurseForge murmur2 fingerprint.
  final int curse;

  /// Lowercase hex md5 fingerprint used by Wago and the WowUp Hub.
  final String md5;

  /// Computes both fingerprints for the addon folder at [folderPath].
  /// Synchronous, meant to run inside an isolate.
  static FolderFingerprint compute(String folderPath) {
    final scanner = _Scanner(folderPath);
    final curseFiles = scanner.matchingFiles(perLineIncludes: true);
    final md5Files = scanner.matchingFiles(perLineIncludes: false);

    final curseHashes = <int>[for (final f in curseFiles) ?scanner.curseHash(f)]
      ..sort();
    final md5Hashes = <String>[for (final f in md5Files) ?scanner.md5Hash(f)]
      ..sort();

    return FolderFingerprint(
      curse: murmur2(Uint8List.fromList(ascii.encode(curseHashes.join()))),
      md5: crypto.md5.convert(utf8.encode(md5Hashes.join())).toString(),
    );
  }
}

class _Scanner {
  _Scanner(this.folderPath) {
    final dir = Directory(folderPath);
    for (final e in dir.listSync(recursive: true, followLinks: true)) {
      if (e is File) _fileMap[e.path.toLowerCase()] = e.path;
    }
  }

  final String folderPath;

  /// Lowercase path -> real path, to resolve includes whose case differs from
  /// the file on disk (matters on case sensitive filesystems).
  final _fileMap = <String, String>{};
  final _bytes = <String, Uint8List?>{};

  static final _tocFile = RegExp(
    r'^([^/]+)/\1([-_|](mainline|bcc|tbc|classic|vanilla|wrath|wotlkc|cata|mists))?\.toc$',
    caseSensitive: false,
  );
  static final _bindingsXml = RegExp(
    r'^[^/]+/bindings\.xml$',
    caseSensitive: false,
  );
  static final _tocComments = RegExp(r'\s*#.*$', multiLine: true);
  static final _tocIncludes = RegExp(
    r'^\s*((?:(?<!\.\.).)+\.(?:xml|lua))\s*$',
    multiLine: true,
    caseSensitive: false,
  );
  static final _xmlComments = RegExp(r'<!--.*?-->', dotAll: true);
  static final _xmlIncludes = RegExp(
    r'''<(?:Include|Script)\s+file=["']((?:(?<!\.\.).)+)["']\s*/>''',
    caseSensitive: false,
    dotAll: true,
  );
  static final _invalidPathChars = RegExp(r'[|\x00-\x1f]');

  List<String> matchingFiles({required bool perLineIncludes}) {
    final parent = p.dirname(folderPath);
    final entryPoints = <String>[];
    final result = <String>[];
    final seen = <String>{};

    final all = _fileMap.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final file in all) {
      final rel = p
          .relative(file, from: parent)
          .replaceAll(r'\', '/')
          .toLowerCase();
      if (_tocFile.hasMatch(rel)) {
        entryPoints.add(file);
      } else if (_bindingsXml.hasMatch(rel)) {
        if (seen.add(file)) result.add(file);
      }
    }
    for (final toc in entryPoints) {
      _processInclude(toc, result, seen, perLineIncludes);
    }
    return result;
  }

  void _processInclude(
    String path,
    List<String> result,
    Set<String> seen,
    bool perLine,
  ) {
    final real = _fileMap[p.normalize(path).toLowerCase()];
    if (real == null || !seen.add(real)) return;
    result.add(real);

    final ext = p.extension(real);
    if (ext != '.toc' && ext != '.xml') return;
    final bytes = _read(real);
    if (bytes == null) return;

    var content = utf8.decode(bytes, allowMalformed: true);
    final isToc = ext == '.toc';
    content = content.replaceAll(isToc ? _tocComments : _xmlComments, '');
    final regex = isToc ? _tocIncludes : _xmlIncludes;

    final includes = perLine
        ? [
            // CurseForge mimics .NET regex behaviour and matches line by line.
            for (final line in content.split('\n'))
              ?regex.firstMatch(line.trim())?.group(1)?.trim(),
          ]
        : [for (final m in regex.allMatches(content)) m.group(1)!];

    final dir = p.dirname(real);
    for (final include in includes) {
      if (_invalidPathChars.hasMatch(include)) break;
      final normalized = include.replaceAll(r'\', p.separator);
      _processInclude(p.join(dir, normalized), result, seen, perLine);
    }
  }

  Uint8List? _read(String path) => _bytes.putIfAbsent(path, () {
    try {
      return File(path).readAsBytesSync();
    } on FileSystemException {
      return null;
    }
  });

  int? curseHash(String path) {
    final bytes = _read(path);
    return bytes == null ? null : curseFileFingerprint(bytes);
  }

  String? md5Hash(String path) {
    final bytes = _read(path);
    return bytes == null ? null : crypto.md5.convert(bytes).toString();
  }
}
