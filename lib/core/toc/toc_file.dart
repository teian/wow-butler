import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/game_flavor.dart';

/// Parsed `.toc` file of an addon folder.
class TocFile {
  TocFile({
    required this.path,
    required Map<String, String> metadata,
    required this.files,
  }) : _metadata = {
         for (final e in metadata.entries) e.key.toLowerCase(): e.value,
       };

  final String path;
  final Map<String, String> _metadata;

  /// Non-comment lines: the Lua/XML files the client loads, in order.
  final List<String> files;

  String? operator [](String key) => _metadata[key.toLowerCase()];

  String get folderName => p.basename(p.dirname(path));

  String get title {
    final raw = this['Title'];
    if (raw == null || raw.trim().isEmpty) return folderName;
    final clean = stripUiEscapes(raw).trim();
    return clean.isEmpty ? folderName : clean;
  }

  String? get notes {
    final raw = this['Notes'];
    return raw == null ? null : stripUiEscapes(raw).trim();
  }

  String? get author {
    final raw = this['Author'];
    return raw == null ? null : stripUiEscapes(raw).trim();
  }

  String? get version {
    final raw = this['Version'];
    if (raw == null) return null;
    final v = raw.trim();
    // Unreplaced packager tokens carry no information.
    if (v.isEmpty || v.startsWith('@')) return null;
    return v;
  }

  /// `## Interface` may list several comma separated versions (multi-client
  /// TOCs since 11.1).
  List<int> get interfaces => [
    for (final part in (this['Interface'] ?? '').split(','))
      ?int.tryParse(part.trim()),
  ];

  List<String> get dependencies =>
      _list(['Dependencies', 'RequiredDeps', 'Dep', 'Dependancies', 'Deps']);

  List<String> get optionalDependencies => _list(['OptionalDeps']);

  /// Folder names bundled with this addon according to TukUI metadata.
  List<String> get tukuiProjectFolders => _list(['X-Tukui-ProjectFolders']);

  String? get curseProjectId => _id('X-Curse-Project-ID');
  String? get wagoId => _id('X-Wago-ID');
  String? get wowInterfaceId => _id('X-WoWI-ID');
  String? get tukuiProjectId => _id('X-Tukui-ProjectID');
  String? get website => _id('X-Website');

  /// Whether a packager marked this as a build for another game version
  /// (`## X-Flavor: Cata` installed on Forever). Such an install should be
  /// replaced by the right build, so its version counts as unknown.
  bool builtForOtherFlavor(GameFlavor flavor) {
    final builtFor = this['X-Flavor']?.trim().toLowerCase();
    return builtFor != null && builtFor.isNotEmpty && builtFor != flavor.name;
  }

  /// A folder shipping `LoadOnDemand` with a parent dependency is a module of
  /// another addon rather than an addon of its own.
  bool get isLoadOnDemand => this['LoadOnDemand']?.trim() == '1';

  String? _id(String key) {
    final v = this[key]?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  List<String> _list(List<String> keys) {
    for (final key in keys) {
      final raw = this[key];
      if (raw == null) continue;
      return raw
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static final _metaLine = RegExp(r'^##\s*([^:]+?)\s*:\s*(.*)$');

  static TocFile parse(String path, String content) {
    final metadata = <String, String>{};
    final files = <String>[];
    for (var line in const LineSplitter().convert(content)) {
      line = line.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('##')) {
        final m = _metaLine.firstMatch(line);
        // First declaration wins, like in the game client.
        if (m != null) metadata.putIfAbsent(m.group(1)!, () => m.group(2)!);
        continue;
      }
      if (line.startsWith('#')) continue;
      files.add(line);
    }
    return TocFile(path: path, metadata: metadata, files: files);
  }

  static TocFile readSync(String path) {
    final bytes = File(path).readAsBytesSync();
    // Some TOCs start with a UTF-8 BOM or contain Latin-1 bytes.
    var content = utf8.decode(bytes, allowMalformed: true);
    if (content.startsWith('\u{FEFF}')) content = content.substring(1);
    return parse(path, content);
  }

  static final _colorCode = RegExp(
    r'\|c[0-9a-fA-F]{8}|\|r|\|T[^|]*\|t|\|A[^|]*\|a',
  );

  /// Removes WoW UI escape sequences (colors, textures, atlases).
  static String stripUiEscapes(String s) => s.replaceAll(_colorCode, '');
}

/// Selects the TOC the game client would load for a given flavor.
///
/// Mirrors the client rules: a flavor specific TOC (`Addon_Mists.toc`,
/// `Addon-Classic.toc`, ...) wins over the plain `Addon.toc`.
class TocSelector {
  static const _suffixes = <GameFlavor, List<String>>{
    GameFlavor.retail: ['mainline'],
    GameFlavor.mists: ['mists', 'classic'],
    GameFlavor.cata: ['cata', 'classic'],
    GameFlavor.wrath: ['wrath', 'wotlkc', 'classic'],
    GameFlavor.tbc: ['tbc', 'bcc', 'classic'],
    GameFlavor.vanilla: ['vanilla', 'classic'],
    // The Forever client accepts its internal codename and its public name.
    GameFlavor.forever: ['camelot', 'forever'],
  };

  static const _allSuffixes = {
    'mainline', 'classic', 'vanilla', 'tbc', 'bcc', 'wrath', 'wotlkc', //
    'cata', 'mists', 'standard', 'camelot', 'forever',
  };

  /// Returns the TOC file name suffix (lowercase) or null for a plain TOC.
  static String? suffixOf(String folderName, String tocFileName) {
    final base = p.basenameWithoutExtension(tocFileName).toLowerCase();
    final folder = folderName.toLowerCase();
    if (base == folder) return null;
    if (!base.startsWith(folder) || base.length <= folder.length + 1) {
      return null;
    }
    final sep = base[folder.length];
    if (sep != '_' && sep != '-') return null;
    final suffix = base.substring(folder.length + 1);
    return _allSuffixes.contains(suffix) ? suffix : null;
  }

  /// Picks the best TOC path among [tocPaths] (all inside [folderName]).
  static String? select(
    String folderName,
    List<String> tocPaths,
    GameFlavor flavor,
  ) {
    final bySuffix = <String?, String>{};
    for (final path in tocPaths) {
      final name = p.basename(path);
      final base = p.basenameWithoutExtension(name).toLowerCase();
      final suffix = suffixOf(folderName, name);
      if (suffix == null && base != folderName.toLowerCase()) continue;
      bySuffix.putIfAbsent(suffix, () => path);
    }
    for (final suffix in _suffixes[flavor]!) {
      final match = bySuffix[suffix];
      if (match != null) return match;
    }
    return bySuffix[null];
  }
}
