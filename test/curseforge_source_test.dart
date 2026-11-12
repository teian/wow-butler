import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wow_butler/core/models/addon.dart';
import 'package:wow_butler/core/models/wow_installation.dart';
import 'package:wow_butler/sources/api_client.dart';
import 'package:wow_butler/sources/curseforge_source.dart';

const _cfKey = r'$2a$10$abcdefghijklmnopqrstuvABCDEFGHIJKLMNOPQRSTUV0123456789';

void main() {
  final api = ApiClient();

  group('CurseForgeSource.unavailableReason', () {
    test('asks for a key when none is set', () {
      expect(CurseForgeSource(api, null).unavailableReason, isNotNull);
      expect(CurseForgeSource(api, '').unavailableReason, isNotNull);
    });

    test('flags an authors token (UUID) as the wrong key type', () {
      final source = CurseForgeSource(
        api,
        '123e4567-e89b-12d3-a456-426614174000',
      );
      expect(source.unavailableReason, contains('console.curseforge.com'));
    });

    test('accepts a Core API key', () {
      final source = CurseForgeSource(
        api,
        _cfKey,
      );
      expect(source.unavailableReason, isNull);
    });
  });

  group('CurseForgeSource user agents', () {
    test('defaults to a current browser user agent', () {
      expect(CurseForgeSource.browserUserAgent, startsWith('Mozilla/5.0 '));
      expect(CurseForgeSource.browserUserAgent, contains('Chrome/'));
    });

    test('offers the WowUp CurseForge client as fallback', () {
      expect(
        CurseForgeSource.wowupCfUserAgent,
        startsWith('WowUp-Client/${CurseForgeSource.wowupCfVersion} ('),
      );
      expect(CurseForgeSource.wowupCfUserAgent, contains('; CF; '));
      expect(
        CurseForgeSource.wowupCfUserAgent,
        endsWith(' +https://wowup.io)'),
      );
    });
  });

  group('CurseForgeSource.downloadRequests', () {
    final release = AddonRelease(
      id: '1234',
      version: '1.0.0',
      channel: ReleaseChannel.stable,
      downloadUrl: 'https://cdn.fallback/legacy.zip',
    );
    final addon = RemoteAddon(
      source: AddonSourceId.curseforge,
      externalId: '42',
      name: 'TestAddon',
      releases: [release],
    );

    test('resolves a fresh URL and offers browser then WowUp', () async {
      http.Request? captured;
      final client = ApiClient(
        client: MockClient((request) async {
          captured = request;
          if (request.url.path.endsWith('/download-url')) {
            return http.Response(
              jsonEncode({'data': 'https://cdn.fresh/file.zip'}),
              200,
            );
          }
          return http.Response('not found', 404);
        }),
      );
      final source = CurseForgeSource(client, _cfKey);
      final requests = await source.downloadRequests(addon, release);
      client.close();

      expect(requests, hasLength(2));
      for (final request in requests) {
        expect(request.uri.toString(), 'https://cdn.fresh/file.zip');
        expect(request.headers['x-api-key'], _cfKey);
        expect(request.headers[HttpHeaders.acceptHeader], '*/*');
      }
      expect(
        requests.first.headers[HttpHeaders.userAgentHeader],
        CurseForgeSource.browserUserAgent,
      );
      expect(
        requests.last.headers[HttpHeaders.userAgentHeader],
        CurseForgeSource.wowupCfUserAgent,
      );
      expect(
        captured?.url.path,
        endsWith('/mods/42/files/1234/download-url'),
      );
      // The API request uses the browser user agent too.
      expect(
        captured?.headers[HttpHeaders.userAgentHeader],
        CurseForgeSource.browserUserAgent,
      );
      expect(captured?.headers['x-api-key'], _cfKey);
    });

    test('falls back to the release URL when the endpoint fails', () async {
      final client = ApiClient(
        client: MockClient((request) async => http.Response('error', 500)),
      );
      final source = CurseForgeSource(client, _cfKey);
      final requests = await source.downloadRequests(addon, release);
      client.close();

      expect(
        requests.map((r) => r.uri.toString()),
        everyElement(release.downloadUrl),
      );
    });

    test('falls back when the endpoint returns an empty URL', () async {
      final client = ApiClient(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/download-url')) {
            return http.Response(jsonEncode({'data': ''}), 200);
          }
          return http.Response('not found', 404);
        }),
      );
      final source = CurseForgeSource(client, _cfKey);
      final requests = await source.downloadRequests(addon, release);
      client.close();

      expect(
        requests.map((r) => r.uri.toString()),
        everyElement(release.downloadUrl),
      );
    });

    test('uses the stored URL when no API key is configured', () async {
      final client = ApiClient(
        client: MockClient((request) async => http.Response('{}', 200)),
      );
      final source = CurseForgeSource(client, null);
      final requests = await source.downloadRequests(addon, release);
      client.close();

      expect(
        requests.map((r) => r.uri.toString()),
        everyElement(release.downloadUrl),
      );
    });
  });
}
