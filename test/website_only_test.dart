import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:wow_butler/core/models/addon.dart';
import 'package:wow_butler/core/models/app_settings.dart';
import 'package:wow_butler/core/models/game_flavor.dart';
import 'package:wow_butler/core/models/wow_installation.dart';
import 'package:wow_butler/services/addon_service.dart';
import 'package:wow_butler/sources/api_client.dart';
import 'package:wow_butler/sources/curseforge_source.dart';
import 'package:wow_butler/sources/source_registry.dart';

const _cfKey = r'$2a$10$abcdefghijklmnopqrstuvABCDEFGHIJKLMNOPQRSTUV0123456789';

/// QuestieDB as CurseForge returns it, with third-party downloads disabled.
Map<String, dynamic> _questieDbMod({bool allowed = false}) => {
  'id': 42,
  'slug': 'questiedb',
  'name': 'QuestieDB',
  'allowModDistribution': allowed,
  'authors': [
    {'name': 'Lawgon'},
  ],
  'links': {'websiteUrl': 'https://www.curseforge.com/wow/addons/questiedb'},
  'latestFiles': [
    {
      'id': 420,
      'displayName': '1.0.11 (Forever)',
      'fileName': 'QuestieDB-1.0.11-Forever.zip',
      'downloadUrl': allowed ? 'https://example.invalid/q.zip' : null,
      'releaseType': 1,
      'sortableGameVersions': [
        {
          'gameVersionTypeId': CurseForgeSource.gameVersionTypeId(
            GameFlavor.forever,
          ),
        },
      ],
      'modules': [
        {'name': 'QuestieDB', 'fingerprint': 1},
      ],
    },
  ],
};

void main() {
  late Directory tmp;
  late WowInstallation inst;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wb-web');
    inst = WowInstallation(
      id: '0123456789abcdef',
      label: 'Test',
      clientPath: tmp.path,
      clientType: WowClientType.forever,
      flavor: GameFlavor.forever,
    );
    final dir = Directory(p.join(inst.addonsPath, 'QuestieDB'))
      ..createSync(recursive: true);
    // The Cata build, as found on a real Forever install.
    File(p.join(dir.path, 'QuestieDB.toc')).writeAsStringSync(
      '## Interface: 16001\n'
      '## Title: QuestieDB\n'
      '## Author: Code: Logonz\n'
      '## Version: 1.0.11\n'
      '## X-Flavor: Cata\n'
      'db.lua\n',
    );
    File(p.join(dir.path, 'db.lua')).writeAsStringSync('-- data');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Syncs with CurseForge and GitHub active; [github] says whether the
  /// GitHub repository has a Forever build.
  Future<InstalledAddon> sync({
    required bool github,
    bool cfAllowed = false,
    List<InstalledAddon> stored = const [],
  }) async {
    final api = ApiClient(
      client: MockClient((request) async {
        final path = request.url.path;
        Object? body;
        if (request.url.host == 'api.curseforge.com') {
          if (path.contains('/fingerprints/')) {
            body = {
              'data': {'exactMatches': <Object>[]},
            };
          } else if (path.endsWith('/mods/search')) {
            body = {
              'data': [
                if (request.url.queryParameters['slug'] == 'questiedb')
                  _questieDbMod(allowed: cfAllowed),
              ],
            };
          }
        } else if (request.url.host == 'api.github.com' && github) {
          if (path.endsWith('/releases')) {
            body = [
              {
                'id': 7,
                'tag_name': 'v1.0.11',
                'prerelease': false,
                'assets': [
                  {
                    'name': 'QuestieDB-1.0.11-Forever.zip',
                    'content_type': 'application/zip',
                    'browser_download_url': 'https://example.invalid/f.zip',
                  },
                ],
              },
            ];
          } else {
            body = {'name': 'QuestieDB', 'html_url': 'https://github.com/x'};
          }
        }
        return body == null
            ? http.Response('not found', 404)
            : http.Response(jsonEncode(body), 200);
      }),
    );
    final settings = AppSettings(
      curseforgeApiKey: _cfKey,
      disabledSources: AddonSourceId.values
          .where(
            (s) => s != AddonSourceId.curseforge && s != AddonSourceId.github,
          )
          .toSet(),
    );
    final service = AddonService(
      api: api,
      sources: () => SourceRegistry(api, settings),
      defaultChannel: () => ReleaseChannel.stable,
    );
    final result = await service.sync(inst, stored);
    api.close();
    return result.addons.single;
  }

  test('prefers another source over a website-only one', () async {
    final addon = await sync(github: true);
    expect(addon.source, AddonSourceId.github);
    expect(addon.downloadsAllowed, isTrue);
  });

  test('falls back to the website-only source', () async {
    final addon = await sync(github: false);
    expect(addon.source, AddonSourceId.curseforge);
    expect(addon.downloadsAllowed, isFalse);
    // The installed Cata build counts as unknown: an update is pending,
    // and it has to come from the website.
    expect(addon.installedReleaseId, isNull);
    expect(addon.updateNeedsWebsite, isTrue);
  });

  test('uses CurseForge when it allows downloads', () async {
    final addon = await sync(github: true, cfAllowed: true);
    expect(addon.source, AddonSourceId.curseforge);
    expect(addon.downloadsAllowed, isTrue);
  });

  test('a stored website-only entry moves to a new source', () async {
    final first = await sync(github: false);
    final second = await sync(github: true, stored: [first]);
    expect(second.source, AddonSourceId.github);
    expect(second.id, first.id);
  });
}
