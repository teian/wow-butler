// Debug helper: runs the source matching against a real AddOns folder.
// Usage: CF_KEY=... dart run tool/debug_match.dart <AddOns path>
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:wow_butler/core/models/game_flavor.dart';
import 'package:wow_butler/services/addon_scanner.dart';
import 'package:wow_butler/sources/api_client.dart';
import 'package:wow_butler/sources/curseforge_source.dart';
import 'package:wow_butler/sources/wowup_source.dart';

Future<void> main(List<String> args) async {
  final path = args.first;
  const flavor = GameFlavor.forever;
  final folders = scanAddonFoldersSync(path, flavor);
  print('folders: ${folders.length}');
  for (final f in folders.take(40)) {
    print(
      '  ${f.name}: hasToc=${f.hasToc} hasAnyToc=${f.hasAnyToc} '
      'fp=${f.fingerprint != null} toc=${f.toc?.path.split('/').last}',
    );
  }

  final api = ApiClient();
  final cfKey = Platform.environment['CF_KEY'];

  final wowup = WowUpSource(api);
  try {
    final matches = await wowup.match(folders, flavor);
    print('wowup matches: ${matches.length}');
    for (final m in matches) {
      print('  ${m.addon.name} -> ${m.folders} releases=${m.addon.releases.length}');
    }
  } catch (e) {
    print('wowup match error: $e');
  }

  if (cfKey != null && cfKey.isNotEmpty) {
    final cf = CurseForgeSource(api, cfKey);
    try {
      final matches = await cf.match(folders, flavor);
      print('curseforge matches: ${matches.length}');
      for (final m in matches) {
        print(
          '  ${m.addon.name} -> ${m.folders} releases=${m.addon.releases.length}',
        );
      }
    } catch (e) {
      print('curseforge match error: $e');
    }
  }
  api.close();
}
