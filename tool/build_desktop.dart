// Build and package the native desktop app.
//
// Usage: dart run tool/build_desktop.dart [linux|windows|macos] [--skip-build]
//
// Needs nothing beyond the Flutter SDK: archiving and checksums use the
// project's own dependencies (archive, crypto). macOS packaging shells out
// to the system's `ditto`, which preserves framework symlinks, executable
// modes and app metadata.
// ignore_for_file: avoid_print
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
  final skipBuild = args.contains('--skip-build');
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final target = positional.isEmpty ? host : positional.first;
  if (positional.length > 1 ||
      args.any((a) => a.startsWith('--') && a != '--skip-build')) {
    _fail('Usage: dart run tool/build_desktop.dart '
        '[${_targets.join('|')}] [--skip-build]');
  }
  if (target == null || !_targets.contains(target) || target != host) {
    _fail('Run this command on the target operating system; '
        'Flutter cannot cross-build desktop apps.');
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

  final digest = await sha256.bind(File(output).openRead()).first;
  File('$output.sha256').writeAsStringSync('$digest  ${p.basename(output)}\n');
  print('Packaged: $output');
}

Future<void> _run(String command, List<String> args) async {
  final process = await Process.start(
    command,
    args,
    workingDirectory: root,
    runInShell: true,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) _fail('$command ${args.join(' ')} exited with $code');
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
