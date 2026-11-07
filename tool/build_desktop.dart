// Build and package the native desktop app.
//
// Usage: dart run tool/build_desktop.dart [linux|windows|macos]
//            [--skip-build] [--archive-only]
//
// Produces a portable archive plus native installers in dist/:
//   linux:   .tar.gz, .deb (Debian/Ubuntu), .rpm (Fedora), .pkg.tar.zst (Arch)
//   windows: .zip, .msi (WiX Toolset v5)
//   macos:   .zip, .dmg
//
// Archives and checksums use the project's own dependencies (archive,
// crypto). macOS packaging shells out to the system's `ditto` and `hdiutil`.
// The installers need, on PATH or via the named environment variable:
//   linux:   nfpm (NFPM)
//   windows: the `wix` dotnet tool (WIX)
// --archive-only skips the installers and their tools.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const _targets = ['linux', 'windows', 'macos'];

final String root = () {
  var dir = File.fromUri(Platform.script).parent;
  while (!File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
    if (dir.parent.path == dir.path) {
      _fail('Could not locate pubspec.yaml above ${Platform.script.path}');
    }
    dir = dir.parent;
  }
  return dir.path;
}();

Never _fail(String message) {
  stderr.writeln('Build failed: $message');
  exit(1);
}

Future<void> main(List<String> args) async {
  final host = switch (Platform.operatingSystem) {
    'linux' => 'linux',
    'windows' => 'windows',
    'macos' => 'macos',
    _ => null,
  };
  const flags = {'--skip-build', '--archive-only'};
  final skipBuild = args.contains('--skip-build');
  final archiveOnly = args.contains('--archive-only');
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final target = positional.isEmpty ? host : positional.first;
  if (positional.length > 1 ||
      args.any((a) => a.startsWith('--') && !flags.contains(a))) {
    _fail(
      'Usage: dart run tool/build_desktop.dart '
      '[${_targets.join('|')}] [${flags.join('] [')}]',
    );
  }
  if (target == null || !_targets.contains(target) || target != host) {
    _fail(
      'Run this command on the target operating system; '
      'Flutter cannot cross-build desktop apps.',
    );
  }

  var arch = switch (Abi.current()) {
    Abi.linuxX64 || Abi.windowsX64 || Abi.macosX64 => 'x64',
    Abi.linuxArm64 || Abi.windowsArm64 || Abi.macosArm64 => 'arm64',
    _ => _fail('Unsupported host architecture: ${Abi.current()}'),
  };

  final pubspec = File(p.join(root, 'pubspec.yaml')).readAsStringSync();
  final version = RegExp(
    r'^version:\s*([^\s#]+)',
    multiLine: true,
  ).firstMatch(pubspec)?.group(1);
  if (version == null) _fail('pubspec.yaml is missing its version');
  final release = _Version.parse(version);

  if (!skipBuild) {
    await _run('flutter', ['pub', 'get', '--enforce-lockfile']);
    await _run('flutter', ['build', target, '--release', '--no-pub']);
  }

  final (bundle, executable) = switch (target) {
    'macos' => (
      p.join(root, 'build/macos/Build/Products/Release/wow_butler.app'),
      p.join(
        root,
        'build/macos/Build/Products/Release/wow_butler.app',
        'Contents/MacOS/wow_butler',
      ),
    ),
    'windows' => (
      p.join(root, 'build/windows/$arch/runner/Release'),
      p.join(root, 'build/windows/$arch/runner/Release/wow_butler.exe'),
    ),
    _ => (
      p.join(root, 'build/linux/$arch/release/bundle'),
      p.join(root, 'build/linux/$arch/release/bundle/wow_butler'),
    ),
  };
  if (!File(executable).existsSync()) {
    _fail('Release executable missing: $executable');
  }

  if (target == 'macos') {
    final lipo = await Process.run('lipo', ['-archs', executable]);
    if (lipo.exitCode != 0) _fail('lipo failed: ${lipo.stderr}');
    final architectures = ('${lipo.stdout}').trim().split(RegExp(r'\s+'))
      ..sort();
    arch = switch (architectures.join(',')) {
      'arm64,x86_64' => 'universal',
      'arm64' => 'arm64',
      'x86_64' => 'x64',
      _ => _fail('Unexpected macOS architectures: $architectures'),
    };
  }

  final destination = Directory(p.join(root, 'dist'))..createSync();
  final name = 'wow-butler-$version-$target-$arch';
  final String output;
  switch (target) {
    case 'linux':
      output = p.join(destination.path, '$name.tar.gz');
      await _tarGzBundle(bundle, output);
    case 'macos':
      output = p.join(destination.path, '$name.zip');
      await _run('ditto', [
        '-c',
        '-k',
        '--sequesterRsrc',
        '--keepParent',
        bundle,
        output,
      ]);
    default:
      output = p.join(destination.path, '$name.zip');
      await _zipBundle(bundle, output);
  }

  final outputs = [output];
  if (!archiveOnly) {
    final installers = switch (target) {
      'linux' => _linuxPackages(bundle, release, arch, destination.path),
      'windows' => _windowsInstaller(
        bundle,
        release,
        arch,
        destination.path,
        name,
      ),
      _ => _macDiskImage(bundle, destination.path, name),
    };
    outputs.addAll(await installers);
  }

  for (final file in outputs) {
    final digest = await sha256.bind(File(file).openRead()).first;
    File('$file.sha256').writeAsStringSync('$digest  ${p.basename(file)}\n');
    print('Packaged: $file');
  }
}

/// pubspec `1.2.3-beta+4` as the pieces installers want: `1.2.3-beta` for
/// display and Linux packages, `1.2.3` for the MSI's numeric-only
/// version and `4` as the package release.
class _Version {
  const _Version(this.display, this.numeric, this.build);

  factory _Version.parse(String version) {
    final [display, ...rest] = version.split('+');
    final numeric = RegExp(r'^\d+(\.\d+){0,3}').stringMatch(display);
    if (numeric == null) _fail('Unsupported version: $version');
    final build = rest.isEmpty ? '1' : rest.join('+');
    return _Version(display, numeric, build);
  }

  final String display;
  final String numeric;
  final String build;
}

/// The tool from [envVar] if set, else [fallback] for a PATH lookup.
String _tool(String envVar, String fallback) {
  final override = Platform.environment[envVar];
  return override == null || override.isEmpty ? fallback : override;
}

/// .deb, .rpm and Arch packages via nfpm. The bundle goes to
/// /usr/lib/wow-butler with a /usr/bin/wow_butler launcher symlink; the
/// Flutter runner resolves its data and lib/ through /proc/self/exe.
Future<List<String>> _linuxPackages(
  String bundle,
  _Version version,
  String arch,
  String destination,
) async {
  const appDir = '/usr/lib/wow-butler';
  final config = {
    'name': 'wow-butler',
    'arch': arch == 'x64' ? 'amd64' : arch,
    'platform': 'linux',
    'version': version.display,
    'release': version.build,
    'section': 'games',
    'priority': 'optional',
    'maintainer': 'Frank Gehann <fg@fgehann.de>',
    'vendor': 'Frank Gehann',
    'homepage': 'https://github.com/teian/wow-butler',
    'license': 'GPL-3.0-only',
    'description':
        'Addon manager for World of Warcraft\n'
        'Installs and updates addons from CurseForge, Wago, WowUp Hub, '
        'TukUI and GitHub and backs up WTF and addon data as ZIP or Git.',
    'contents': [
      {
        'src': p.join(bundle, 'wow_butler'),
        'dst': '$appDir/wow_butler',
        'file_info': {'mode': 493}, // 0755
      },
      {'src': p.join(bundle, 'lib'), 'dst': '$appDir/lib', 'type': 'tree'},
      {'src': p.join(bundle, 'data'), 'dst': '$appDir/data', 'type': 'tree'},
      {'dst': appDir, 'type': 'dir'},
      {
        'src': '$appDir/wow_butler',
        'dst': '/usr/bin/wow_butler',
        'type': 'symlink',
      },
      {
        'src': p.join(root, 'linux/de.fgehann.wow_butler.desktop'),
        'dst': '/usr/share/applications/de.fgehann.wow_butler.desktop',
        'file_info': {'mode': 420}, // 0644
      },
      {
        'src': p.join(root, 'design/icon/e3-quest-frack/linux/hicolor/'),
        'dst': '/usr/share/icons/hicolor',
      },
      {
        'src': p.join(root, 'LICENSE'),
        'dst': '/usr/share/licenses/wow-butler/LICENSE',
        'file_info': {'mode': 420},
      },
    ],
    'overrides': {
      'deb': {
        'depends': ['libgtk-3-0t64 | libgtk-3-0'],
        'recommends': ['git', 'xdg-desktop-portal'],
      },
      'rpm': {
        'depends': ['gtk3'],
        'recommends': ['git', 'xdg-desktop-portal'],
      },
      'archlinux': {
        'depends': ['gtk3'],
        'recommends': ['git: Git-Backups', 'xdg-desktop-portal: Ordnerauswahl'],
      },
    },
    'rpm': {'summary': 'Addon manager for World of Warcraft'},
  };

  final temp = Directory.systemTemp.createTempSync('wow_butler_nfpm');
  try {
    // JSON is valid YAML, so nfpm reads it as is.
    final configFile = File(p.join(temp.path, 'nfpm.yaml'))
      ..writeAsStringSync(jsonEncode(config));
    final nfpm = _tool('NFPM', 'nfpm');
    final outputs = <String>[];
    for (final packager in ['deb', 'rpm', 'archlinux']) {
      final target = Directory(p.join(temp.path, packager))..createSync();
      await _run(nfpm, [
        'package',
        '--config',
        configFile.path,
        '--packager',
        packager,
        '--target',
        target.path,
      ], shell: false);
      for (final file in target.listSync().whereType<File>()) {
        // Copy, not rename: the temp dir may be on another file system.
        outputs.add(
          file.copySync(p.join(destination, p.basename(file.path))).path,
        );
      }
    }
    return outputs;
  } finally {
    temp.deleteSync(recursive: true);
  }
}

/// Per-machine .msi built with the WiX Toolset.
Future<List<String>> _windowsInstaller(
  String bundle,
  _Version version,
  String arch,
  String destination,
  String name,
) async {
  final msi = p.join(destination, '$name.msi');
  await _run(_tool('WIX', 'wix'), [
    'build',
    p.join(root, 'packaging', 'windows', 'wow-butler.wxs'),
    '-arch',
    arch,
    '-d',
    'Version=${version.numeric}',
    '-d',
    'IconFile=${p.join(root, 'windows', 'runner', 'resources', 'app_icon.ico')}',
    '-bindpath',
    'bundle=$bundle',
    '-pdbtype',
    'none',
    '-o',
    msi,
  ], shell: false);

  return [msi];
}

/// Compressed disk image with the app and an /Applications shortcut for
/// drag-and-drop installation.
Future<List<String>> _macDiskImage(
  String bundle,
  String destination,
  String name,
) async {
  final output = p.join(destination, '$name.dmg');
  final temp = Directory.systemTemp.createTempSync('wow_butler_dmg');
  try {
    final staging = Directory(p.join(temp.path, 'WoW Butler'))..createSync();
    await _run('ditto', [
      bundle,
      p.join(staging.path, p.basename(bundle)),
    ], shell: false);
    Link(p.join(staging.path, 'Applications')).createSync('/Applications');

    // hdiutil occasionally fails with "Resource busy" on CI machines.
    for (var attempt = 1; ; attempt++) {
      final code = await _run(
        'hdiutil',
        [
          'create',
          '-volname',
          'WoW Butler',
          '-srcfolder',
          staging.path,
          '-fs',
          'HFS+',
          '-format',
          'UDZO',
          '-ov',
          output,
        ],
        shell: false,
        check: attempt == 3,
      );
      if (code == 0) break;
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    return [output];
  } finally {
    temp.deleteSync(recursive: true);
  }
}

/// Runs [command] with inherited stdio. [shell] is needed for Flutter's
/// .bat launcher on Windows; tools given by full path run without it so
/// paths with spaces and parentheses reach them unchanged.
Future<int> _run(
  String command,
  List<String> args, {
  bool shell = true,
  bool check = true,
}) async {
  final Process process;
  try {
    process = await Process.start(
      command,
      args,
      workingDirectory: root,
      runInShell: shell,
      mode: ProcessStartMode.inheritStdio,
    );
  } on ProcessException catch (e) {
    _fail(
      'Could not start $command: ${e.message}\n'
      'Install it (see README, Desktop-Builds; nfpm comes with '
      '`mise install`) or pass --archive-only.',
    );
  }
  final code = await process.exitCode;
  if (check && code != 0) {
    _fail('$command ${args.join(' ')} exited with $code');
  }
  return code;
}

List<File> _bundleFiles(String bundle) =>
    Directory(bundle).listSync(recursive: true).whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// Archive entry name below the common `wow-butler/` top-level folder,
/// always with forward slashes.
String _entryName(String bundle, File file) =>
    'wow-butler/${p.split(p.relative(file.path, from: bundle)).join('/')}';

/// tar.gz with the files' own modes, so the executable stays executable.
Future<void> _tarGzBundle(String bundle, String output) async {
  final temp = Directory.systemTemp.createTempSync('wow_butler_pkg');
  try {
    final tarPath = p.join(temp.path, 'bundle.tar');
    final tar = TarFileEncoder()..create(tarPath);
    for (final file in _bundleFiles(bundle)) {
      await tar.addFile(file, _entryName(bundle, file));
    }
    await tar.close();

    final input = InputFileStream(tarPath);
    final gz = OutputFileStream(output);
    try {
      GZipEncoder().encodeStream(input, gz);
    } finally {
      await input.close();
      await gz.close();
    }
  } finally {
    temp.deleteSync(recursive: true);
  }
}

Future<void> _zipBundle(String bundle, String output) async {
  final zip = ZipFileEncoder()..create(output);
  for (final file in _bundleFiles(bundle)) {
    await zip.addFile(file, _entryName(bundle, file));
  }
  await zip.close();
}
