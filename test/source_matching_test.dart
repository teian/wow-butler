import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wow_butler/core/models/addon.dart';
import 'package:wow_butler/core/models/addon_folder.dart';
import 'package:wow_butler/core/models/game_flavor.dart';
import 'package:wow_butler/core/models/wow_installation.dart';
import 'package:wow_butler/core/toc/toc_file.dart';
import 'package:wow_butler/sources/api_client.dart';
import 'package:wow_butler/sources/curseforge_source.dart';
import 'package:wow_butler/sources/github_source.dart';

TocFile _toc(String folder, Map<String, String> metadata) => TocFile(
  path: '/AddOns/$folder/$folder.toc',
  metadata: metadata,
  files: const [],
);

AddonFolder _folder(String name, Map<String, String> metadata) => AddonFolder(
  name: name,
  path: '/AddOns/$name',
  toc: _toc(name, metadata),
  hasAnyToc: true,
);

Map<String, dynamic> _mod(int id, String author, String folder) => {
  'id': id,
  'name': 'ForeverThreat',
  'authors': [
    {'name': author},
  ],
  'latestFiles': [
    {
      'id': id * 10,
      'displayName': 'ForeverThreat1.7.1.zip',
      'fileName': 'ForeverThreat1.7.1.zip',
      'downloadUrl': 'https://example.invalid/$id.zip',
      'releaseType': 1,
      'sortableGameVersions': [
        {
          'gameVersionTypeId': CurseForgeSource.gameVersionTypeId(
            GameFlavor.forever,
          ),
        },
      ],
      'modules': [
        {'name': folder, 'fingerprint': 1},
      ],
    },
  ],
};

void main() {
  group('CurseForge name fallback', () {
    final threat = _folder('ForeverThreat', {
      'Title': 'ForeverThreat',
      'Author': 'Loyftwa',
      'Version': '1.7.1',
    });

    Future<List<String>> run(List<Map<String, dynamic>> results) async {
      final searches = <String>[];
      final api = ApiClient(
        client: MockClient((request) async {
          searches.add(request.url.queryParameters['searchFilter'] ?? '');
          return http.Response(jsonEncode({'data': results}), 200);
        }),
      );
      final source = CurseForgeSource(api, 'key');
      final matches = await source.match([threat], GameFlavor.forever);
      api.close();
      expect(searches, ['ForeverThreat']);
      return [
        for (final m in matches)
          '${m.addon.externalId} ${m.folders} ${m.installedRelease?.version}',
      ];
    }

    test('accepts a project by the TOC author that ships the folder', () async {
      expect(
        await run([
          _mod(1, 'SomeoneElse', 'ForeverThreat'),
          _mod(2, 'Loyftwa', 'ForeverThreatOther'),
          _mod(3, 'loyftwa', 'ForeverThreat'),
        ]),
        ['3 [ForeverThreat] 1.7.1'],
      );
    });

    test('leaves the folder local without such a project', () async {
      expect(await run([_mod(1, 'SomeoneElse', 'ForeverThreat')]), isEmpty);
    });
  });

  group('GitHubSource.installedRelease', () {
    const releases = [
      AddonRelease(
        id: '1',
        version: 'v1.0.11',
        channel: ReleaseChannel.stable,
        downloadUrl: '',
      ),
      AddonRelease(
        id: '2',
        version: 'v1.0.10',
        channel: ReleaseChannel.stable,
        downloadUrl: '',
      ),
    ];

    test('recognizes the installed version', () {
      final toc = _toc('QuestieDB', {
        'Version': '1.0.11',
        'X-Flavor': 'Forever',
      });
      expect(
        GitHubSource.installedRelease(toc, releases, GameFlavor.forever)?.id,
        '1',
      );
    });

    test('treats a build for another game version as unknown', () {
      final toc = _toc('QuestieDB', {'Version': '1.0.11', 'X-Flavor': 'Cata'});
      expect(
        GitHubSource.installedRelease(toc, releases, GameFlavor.forever),
        isNull,
      );
    });
  });

  test('updates without download URL need the website', () {
    InstalledAddon addon(String url) => InstalledAddon(
      id: 'a',
      name: 'ForeverThreat',
      folders: const ['ForeverThreat'],
      source: AddonSourceId.curseforge,
      externalId: '1',
      installedReleaseId: '1',
      latestRelease: AddonRelease(
        id: '2',
        version: '1.8.0',
        channel: ReleaseChannel.stable,
        downloadUrl: url,
      ),
    );
    expect(addon('').updateNeedsWebsite, isTrue);
    expect(addon('https://example.invalid/a.zip').updateNeedsWebsite, isFalse);
  });
}
