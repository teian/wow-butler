import 'package:flutter_test/flutter_test.dart';
import 'package:wow_butler/core/models/addon.dart';
import 'package:wow_butler/core/models/app_settings.dart';
import 'package:wow_butler/core/models/wow_installation.dart';

AddonRelease release(String id, ReleaseChannel channel, DateTime date) =>
    AddonRelease(
      id: id,
      version: 'v$id',
      channel: channel,
      downloadUrl: 'https://x/$id.zip',
      releasedAt: date,
    );

void main() {
  test('latestFor respects the channel', () {
    final remote = RemoteAddon(
      source: AddonSourceId.curseforge,
      externalId: '1',
      name: 'X',
      releases: [
        release('1', ReleaseChannel.stable, DateTime(2026, 9, 1)),
        release('2', ReleaseChannel.beta, DateTime(2026, 9, 10)),
        release('3', ReleaseChannel.alpha, DateTime(2026, 9, 20)),
      ],
    );
    expect(remote.latestFor(ReleaseChannel.stable)!.id, '1');
    expect(remote.latestFor(ReleaseChannel.beta)!.id, '2');
    expect(remote.latestFor(ReleaseChannel.alpha)!.id, '3');
  });

  group('InstalledAddon update state', () {
    final base = InstalledAddon(
      id: 'a',
      name: 'A',
      folders: const ['A'],
      source: AddonSourceId.wago,
      externalId: 'abc',
      installedReleaseId: '1',
      latestRelease: release('2', ReleaseChannel.stable, DateTime(2026)),
    );

    test('detects a newer release', () {
      expect(base.newerAvailable, isTrue);
      expect(base.hasUpdate, isTrue);
    });

    test('pinned addons show the release but do not update', () {
      final pinned = base.copyWith(pinned: true);
      expect(pinned.newerAvailable, isTrue);
      expect(pinned.hasUpdate, isFalse);
    });

    test('ignored addons do not update', () {
      expect(base.copyWith(ignored: true).hasUpdate, isFalse);
    });

    test('local addons never update', () {
      const local = InstalledAddon(id: 'l', name: 'L', folders: ['L']);
      expect(local.hasUpdate, isFalse);
    });

    test('survives a JSON round trip', () {
      final restored = InstalledAddon.fromJson(
        base.copyWith(pinned: true).toJson(),
      );
      expect(restored.pinned, isTrue);
      expect(restored.latestRelease!.id, '2');
      expect(restored.remoteKey, 'wago:abc');
    });
  });

  test('settings keep new sources when loading an old priority list', () {
    final s = AppSettings.fromJson({
      'sourcePriority': ['curseforge'],
      'defaultChannel': 'beta',
    });
    expect(s.sourcePriority.first, AddonSourceId.curseforge);
    expect(s.sourcePriority.toSet(), AddonSourceId.values.toSet());
    expect(s.defaultChannel, ReleaseChannel.beta);
    expect(s.autoUpdate, isTrue);
  });
}
