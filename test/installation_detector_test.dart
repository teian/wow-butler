import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wow_butler/core/models/game_flavor.dart';
import 'package:wow_butler/core/models/wow_installation.dart';
import 'package:wow_butler/services/installation_detector.dart';

void main() {
  const detector = InstallationDetector();
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wow_butler_detect');
  });

  tearDown(() => tmp.delete(recursive: true));

  Future<String> createClient(String root, String folder) async {
    final client = p.join(tmp.path, root, 'World of Warcraft', folder);
    await Directory(p.join(client, 'Interface')).create(recursive: true);
    return client;
  }

  test('finds a Forever client folder', () async {
    final client = await createClient('real', '_forever_');
    final found = await detector.fromUserPath(client);
    expect(found, hasLength(1));
    expect(found.single.clientType, WowClientType.forever);
    expect(found.single.flavor, GameFlavor.forever);
  });

  test('symlinked routes resolve to the same installation', () async {
    final client = await createClient('real', '_forever_');
    final link = await Link(
      p.join(tmp.path, 'link'),
    ).create(p.join(tmp.path, 'real'));

    final direct = await detector.fromUserPath(client);
    final viaLink = await detector.fromUserPath(
      p.join(link.path, 'World of Warcraft', '_forever_'),
    );

    expect(direct.single.id, viaLink.single.id);
    expect(direct.single.clientPath, viaLink.single.clientPath);
  }, skip: Platform.isWindows);

  test('dedupeByPath drops stored symlink twins, keeping the preferred one', () async {
    final client = await createClient('real', '_retail_');
    await Link(p.join(tmp.path, 'link')).create(p.join(tmp.path, 'real'));
    final linked = p.join(tmp.path, 'link', 'World of Warcraft', '_retail_');
    final other = await createClient('elsewhere', '_classic_era_');

    WowInstallation entry(String id, String path, WowClientType type) =>
        WowInstallation(
          id: id,
          label: type.label,
          clientPath: path,
          clientType: type,
          flavor: type.defaultFlavor,
        );

    final kept = await detector.dedupeByPath([
      entry('a', client, WowClientType.retail),
      entry('b', linked, WowClientType.retail),
      entry('c', other, WowClientType.classicEra),
    ], preferredId: 'b');

    expect(kept.map((i) => i.id), ['b', 'c']);
  }, skip: Platform.isWindows);
}
