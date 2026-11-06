import 'package:flutter_test/flutter_test.dart';
import 'package:wow_butler/core/models/game_flavor.dart';
import 'package:wow_butler/sources/wowinterface_source.dart';

void main() {
  Map<String, dynamic> listing(List<String> versions) => {
    'UID': '1',
    'UIName': 'Test',
    if (versions.isNotEmpty)
      'UICompatibility': [
        for (final v in versions) {'version': v, 'name': v},
      ],
  };

  group('WowInterfaceSource.isCompatible', () {
    test('maps compatibility versions to flavors', () {
      final a = listing(['11.0.2', '1.15.2', '4.4.0']);
      expect(WowInterfaceSource.isCompatible(a, GameFlavor.retail), isTrue);
      expect(WowInterfaceSource.isCompatible(a, GameFlavor.vanilla), isTrue);
      expect(WowInterfaceSource.isCompatible(a, GameFlavor.cata), isTrue);
      expect(WowInterfaceSource.isCompatible(a, GameFlavor.mists), isFalse);
    });

    test('listings without compatibility count as retail only', () {
      final a = listing([]);
      expect(WowInterfaceSource.isCompatible(a, GameFlavor.retail), isTrue);
      expect(WowInterfaceSource.isCompatible(a, GameFlavor.vanilla), isFalse);
    });

    test('WoWInterface hosts no Forever addons', () {
      expect(
        WowInterfaceSource.isCompatible(
          listing(['1.60.1']),
          GameFlavor.forever,
        ),
        isFalse,
      );
    });
  });
}
