// Debug helper: exercises the WoWInterface source against the live API.
// Usage: dart run tool/debug_wowi.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:wow_butler/core/models/game_flavor.dart';
import 'package:wow_butler/sources/api_client.dart';
import 'package:wow_butler/sources/wowinterface_source.dart';

Future<void> main() async {
  final api = ApiClient();
  final source = WowInterfaceSource(api);

  final featured = await source.featured(GameFlavor.retail);
  print('featured retail: ${featured.length}');
  for (final a in featured.take(5)) {
    print('  ${a.name} (${a.author}) v=${a.releases.firstOrNull?.version} '
        'dl=${a.downloadCount}');
  }

  final hits = await source.search('details', GameFlavor.vanilla);
  print('search "details" vanilla: ${hits.length}');
  for (final a in hits.take(3)) {
    print('  ${a.name} -> ${a.releases.firstOrNull?.downloadUrl}');
  }

  final atlas = await source.getById('3896', GameFlavor.retail);
  print('getById Atlas: v=${atlas?.releases.firstOrNull?.version} '
      'url=${atlas?.releases.firstOrNull?.downloadUrl}');
  final details = await source.details(atlas!, GameFlavor.retail);
  print('details: paragraphs=${details.paragraphs.length} '
      'screenshots=${details.screenshots.length} flavors=${details.flavors}');

  // The list-derived download URL must actually resolve.
  final derived = featured.first.releases.first.downloadUrl;
  final req = await HttpClient().headUrl(Uri.parse(derived));
  req.followRedirects = true;
  final res = await req.close();
  print('derived URL HEAD: ${res.statusCode} ($derived)');

  final forever = await source.featured(GameFlavor.forever);
  print('featured forever: ${forever.length} (expected 0)');
  api.close();
  exit(0);
}
