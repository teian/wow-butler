import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../../core/models/addon.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/wow_installation.dart';
import '../../core/util/archive_extract.dart';
import '../../core/util/file_sync.dart';
import 'zip_backup_service.dart';

class GitException implements Exception {
  GitException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GitCommit {
  const GitCommit({
    required this.hash,
    required this.date,
    required this.message,
  });

  final String hash;
  final DateTime date;
  final String message;

  String get shortHash => hash.substring(0, 8);
}

class GitBackupOutcome {
  const GitBackupOutcome({this.commit, this.pushed = false, this.pushError});

  /// `null` when nothing changed since the last backup.
  final String? commit;
  final bool pushed;
  final String? pushError;
}

/// Versioned backups in a git repository. Each installation gets its own
/// folder (`<slug>/Interface/AddOns`, `<slug>/WTF`, `<slug>/addons.json`), so
/// one repository can hold all clients and be pushed to any remote.
///
/// Uses the system `git` executable, which also brings the user's credential
/// helpers and SSH setup for pushing.
class GitBackupService {
  const GitBackupService();

  static const _identity = [
    '-c',
    'user.name=WoW Butler',
    '-c',
    'user.email=wow-butler@localhost',
  ];

  Future<String?> gitVersion() async {
    try {
      final r = await Process.run('git', ['--version']);
      return r.exitCode == 0 ? (r.stdout as String).trim() : null;
    } on ProcessException {
      return null;
    }
  }

  Future<void> ensureRepo(GitBackupSettings s) async {
    final repo = s.repoPath!;
    await Directory(repo).create(recursive: true);
    if (!await Directory(p.join(repo, '.git')).exists()) {
      await _git(repo, ['init']);
      await _git(repo, ['symbolic-ref', 'HEAD', 'refs/heads/${s.branch}']);
    }
    // Saved variables must round-trip byte for byte on every OS.
    await File(p.join(repo, '.gitattributes')).writeAsString('* -text\n');
    await File(p.join(repo, '.gitignore')).writeAsString('*.bak\n*.old\n');

    final remote = s.remoteUrl?.trim();
    if (remote != null && remote.isNotEmpty) {
      final current = await _gitResult(repo, ['remote', 'get-url', 'origin']);
      if (current.exitCode != 0) {
        await _git(repo, ['remote', 'add', 'origin', remote]);
      } else if ((current.stdout as String).trim() != remote) {
        await _git(repo, ['remote', 'set-url', 'origin', remote]);
      }
    }
  }

  Future<GitBackupOutcome> backup({
    required GitBackupSettings settings,
    required WowInstallation inst,
    required List<InstalledAddon> addons,
    String? message,
  }) async {
    await ensureRepo(settings);
    final repo = settings.repoPath!;
    final target = p.join(repo, inst.slug);
    final clientPath = inst.clientPath;
    final includeAddons = settings.includeAddonFiles;
    final includeWtf = settings.includeWtf;

    await _mirrorIntoRepoInIsolate(
      target,
      clientPath,
      includeAddons,
      includeWtf,
    );

    const encoder = JsonEncoder.withIndent('  ');
    await File(p.join(target, 'addons.json')).writeAsString(
      encoder.convert([
        for (final a in addons) a.copyWith(clearLatestRelease: true).toJson(),
      ]),
    );
    await File(p.join(target, 'installation.json'))
        .writeAsString(encoder.convert(inst.toJson()));

    await _git(repo, [
      'add',
      '-A',
      '--',
      inst.slug,
      '.gitattributes',
      '.gitignore',
    ]);
    final diff = await _gitResult(repo, ['diff', '--cached', '--quiet']);
    if (diff.exitCode == 0) return const GitBackupOutcome();

    await _git(repo, [
      ...await _identityArgs(repo),
      'commit',
      '-q',
      '-m',
      message ?? 'Backup ${inst.label} ${DateTime.now().toIso8601String()}',
    ]);
    final hash = (await _git(repo, ['rev-parse', 'HEAD'])).trim();

    if (!settings.autoPush || (settings.remoteUrl?.trim().isEmpty ?? true)) {
      return GitBackupOutcome(commit: hash);
    }
    try {
      await push(settings);
      return GitBackupOutcome(commit: hash, pushed: true);
    } on GitException catch (e) {
      return GitBackupOutcome(commit: hash, pushError: e.message);
    }
  }

  Future<void> push(GitBackupSettings s) =>
      _git(s.repoPath!, ['push', '-u', 'origin', s.branch]);

  Future<List<GitCommit>> history(
    GitBackupSettings s,
    WowInstallation inst, {
    int limit = 100,
  }) async {
    final repo = s.repoPath;
    if (repo == null || !await Directory(p.join(repo, '.git')).exists()) {
      return const [];
    }
    final head = await _gitResult(repo, ['rev-parse', '--verify', 'HEAD']);
    if (head.exitCode != 0) return const [];
    final out = await _git(repo, [
      'log',
      '-n',
      '$limit',
      '--format=%H%x1f%aI%x1f%s',
      '--',
      inst.slug,
    ]);
    return [
      for (final line in const LineSplitter().convert(out))
        if (line.split('\x1f') case [final hash, final date, final msg])
          GitCommit(hash: hash, date: DateTime.parse(date), message: msg),
    ];
  }

  /// Addon list recorded in [commit], e.g. to reinstall addons when only the
  /// manifest was versioned.
  Future<List<InstalledAddon>?> manifestAt(
    GitBackupSettings s,
    WowInstallation inst,
    String commit,
  ) async {
    final r = await _gitResult(s.repoPath!, [
      'show',
      '$commit:${inst.slug}/addons.json',
    ]);
    if (r.exitCode != 0) return null;
    return [
      for (final a in jsonDecode(r.stdout as String) as List)
        InstalledAddon.fromJson(a as Map<String, dynamic>),
    ];
  }

  /// Restores files from [commit]. The current state is committed first, so
  /// the restore itself can be undone from the history.
  Future<void> restore({
    required GitBackupSettings settings,
    required WowInstallation inst,
    required List<InstalledAddon> currentAddons,
    required String commit,
    required BackupScope scope,
  }) async {
    await backup(
      settings: settings,
      inst: inst,
      addons: currentAddons,
      message: 'Stand vor Wiederherstellung von ${commit.substring(0, 8)}',
    );
    final repo = settings.repoPath!;
    final r = await Process.run(
      'git',
      ['archive', '--format=tar', commit, '--', inst.slug],
      workingDirectory: repo,
      stdoutEncoding: null,
    );
    if (r.exitCode != 0) {
      throw GitException('git archive: ${r.stderr}'.trim());
    }
    final tar = r.stdout as List<int>;
    final slug = inst.slug;
    final clientPath = inst.clientPath;
    await _restoreTarInIsolate(tar, slug, clientPath, scope);
  }

  Future<List<String>> _identityArgs(String repo) async {
    final email = await _gitResult(repo, ['config', 'user.email']);
    final hasIdentity =
        email.exitCode == 0 && (email.stdout as String).trim().isNotEmpty;
    return hasIdentity ? const [] : _identity;
  }

  Future<String> _git(String repo, List<String> args) async {
    final r = await _gitResult(repo, args);
    if (r.exitCode != 0) {
      final err = '${r.stderr}'.trim();
      throw GitException(
        'git ${args.firstWhere((a) => !a.startsWith('-') && !a.contains('='))}: '
        '${err.isEmpty ? 'Exit-Code ${r.exitCode}' : err}',
      );
    }
    return r.stdout as String;
  }

  Future<ProcessResult> _gitResult(String repo, List<String> args) async {
    try {
      return await Process.run(
        'git',
        args,
        workingDirectory: repo,
        // Never block on an interactive credential prompt.
        environment: {'GIT_TERMINAL_PROMPT': '0'},
      );
    } on ProcessException {
      throw GitException(
        'git wurde nicht gefunden. Bitte git installieren und zum PATH hinzufügen.',
      );
    }
  }
}

// Isolate entry points are top-level so their closures capture only the
// sendable parameters.
Future<void> _mirrorIntoRepoInIsolate(
  String target,
  String clientPath,
  bool includeAddons,
  bool includeWtf,
) => Isolate.run(() {
  final addonsTarget = p.join(target, 'Interface', 'AddOns');
  if (includeAddons) {
    mirrorDirectorySync(
      p.join(clientPath, 'Interface', 'AddOns'),
      addonsTarget,
      exclude: _excludeNestedGit,
    );
  } else if (Directory(p.join(target, 'Interface')).existsSync()) {
    Directory(p.join(target, 'Interface')).deleteSync(recursive: true);
  }
  final wtfTarget = p.join(target, 'WTF');
  if (includeWtf) {
    mirrorDirectorySync(
      p.join(clientPath, 'WTF'),
      wtfTarget,
      exclude: isWowTempFile,
    );
  } else if (Directory(wtfTarget).existsSync()) {
    Directory(wtfTarget).deleteSync(recursive: true);
  }
});

Future<void> _restoreTarInIsolate(
  List<int> tar,
  String slug,
  String clientPath,
  BackupScope scope,
) => Isolate.run(() {
  final staging = Directory(p.join(clientPath, '.wow-butler-restore'));
  if (staging.existsSync()) staging.deleteSync(recursive: true);
  extractArchiveSafely(TarDecoder().decodeBytes(tar), staging.path);
  try {
    final root = p.join(staging.path, slug);
    final addons = p.join(root, 'Interface', 'AddOns');
    if (scope.addons && Directory(addons).existsSync()) {
      mirrorDirectorySync(addons, p.join(clientPath, 'Interface', 'AddOns'));
    }
    final wtf = p.join(root, 'WTF');
    if (scope.wtf && Directory(wtf).existsSync()) {
      mirrorDirectorySync(
        wtf,
        p.join(clientPath, 'WTF'),
        exclude: isWowTempFile,
      );
    }
  } finally {
    staging.deleteSync(recursive: true);
  }
});

bool _excludeNestedGit(String rel) => rel.split('/').contains('.git');
