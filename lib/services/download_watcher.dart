import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Waits for a file the user downloads in the browser to show up, complete,
/// in a downloads folder.
///
/// Polls instead of using file system events, which are unreliable on some
/// platforms and network folders. Files are compared with a snapshot of the
/// folder taken at the start, not by modification time: Firefox sets the
/// time of a download to the server's `Last-Modified`, which lies in the
/// past.
class DownloadWatcher {
  DownloadWatcher({
    required this.directory,
    required this.fileName,
    this.addonName = '',
    this.interval = const Duration(seconds: 1),
  });

  final Directory directory;

  /// The expected file name; browsers may append ` (1)` and similar when a
  /// file of that name exists. Empty accepts any new zip archive.
  final String fileName;

  /// Name of the addon; a new zip archive whose name contains it counts
  /// as well, in case the browser saved the file under another name.
  final String addonName;
  final Duration interval;

  Timer? _timer;
  Map<String, String>? _snapshot;
  final _sizes = <String, int>{};
  Completer<File>? _completer;

  /// Completes with the downloaded file once its size stopped changing.
  Future<File> wait() {
    final completer = _completer ??= Completer<File>();
    _snapshot ??= _scan();
    _timer ??= Timer.periodic(interval, (_) => _poll());
    return completer.future;
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// File path -> "size:modified" of the zip archives in [directory].
  Map<String, String> _scan() {
    final result = <String, String>{};
    try {
      for (final file in directory.listSync().whereType<File>()) {
        if (!file.path.toLowerCase().endsWith('.zip')) continue;
        try {
          final stat = file.statSync();
          result[file.path] = '${stat.size}:${stat.modified}';
        } on FileSystemException {
          continue;
        }
      }
    } on FileSystemException {
      // Missing or unreadable folder: nothing to compare against.
    }
    return result;
  }

  void _poll() {
    final completer = _completer;
    final snapshot = _snapshot;
    if (completer == null || snapshot == null || completer.isCompleted) {
      return;
    }
    final current = _scan();
    final fresh = [
      for (final entry in current.entries)
        if (snapshot[entry.key] != entry.value) entry.key,
    ];
    // Exact names first, then names that only mention the addon.
    final candidates = [
      ...fresh.where((f) => matches(p.basename(f), fileName)),
      ...fresh.where(
        (f) =>
            !matches(p.basename(f), fileName) &&
            mentions(p.basename(f), addonName),
      ),
    ];
    for (final path in candidates) {
      final size = int.parse(current[path]!.split(':').first);
      if (size == 0) continue;
      // Complete when the size is the same as on the previous poll.
      if (_sizes[path] == size) {
        cancel();
        completer.complete(File(path));
        return;
      }
      _sizes[path] = size;
    }
  }

  /// Whether the file [name] is the download of [expected], allowing the
  /// suffixes browsers add to duplicate names (`Foo (1).zip`, `Foo(2).zip`,
  /// `Foo-1.zip`).
  static bool matches(String name, String expected) {
    final lower = name.toLowerCase();
    if (!lower.endsWith('.zip')) return false;
    if (expected.isEmpty) return true;
    final want = expected.toLowerCase();
    if (lower == want) return true;
    final stem = p.basenameWithoutExtension(want);
    final ext = p.extension(want);
    final duplicate = RegExp(
      '^${RegExp.escape(stem)}(?: ?\\(\\d+\\)|-\\d+)${RegExp.escape(ext)}\$',
    );
    return duplicate.hasMatch(lower);
  }

  /// Whether the zip archive [name] contains [addonName], ignoring case
  /// and punctuation.
  static bool mentions(String name, String addonName) {
    String norm(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final addon = norm(addonName);
    return name.toLowerCase().endsWith('.zip') &&
        addon.isNotEmpty &&
        norm(p.basenameWithoutExtension(name)).contains(addon);
  }
}
