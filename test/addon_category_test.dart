import 'package:flutter_test/flutter_test.dart';
import 'package:wow_butler/core/models/addon.dart';
import 'package:wow_butler/core/models/addon_category.dart';

RemoteAddon _addon(String name, [String? summary]) => RemoteAddon(
  source: AddonSourceId.wowup,
  externalId: '1',
  name: name,
  summary: summary,
);

void main() {
  group('AddonCategory.parse', () {
    test('resolves aliases and labels as tags', () {
      expect(AddonCategory.parse('minimap'), AddonCategory.maps);
      expect(AddonCategory.parse('Quests'), AddonCategory.quests);
      expect(AddonCategory.parse('Auktion & Wirtschaft'), AddonCategory.auction);
      expect(AddonCategory.parse('PVP'), AddonCategory.pvp);
    });

    test('leaves ordinary queries alone', () {
      expect(AddonCategory.parse('quest helper deluxe'), isNull);
      expect(AddonCategory.parse('details'), isNull);
      expect(AddonCategory.parse(''), isNull);
    });
  });

  group('AddonCategory.matches', () {
    test('matches on name or summary keywords', () {
      expect(
        AddonCategory.maps.matches(_addon('HandyNotes', 'Notes on your map')),
        isTrue,
      );
      expect(
        AddonCategory.auction.matches(_addon('Auctionator')),
        isFalse,
        reason: 'keyword must stand alone, not inside a word',
      );
      expect(
        AddonCategory.auction.matches(_addon('TSM', 'Auction house suite')),
        isTrue,
      );
      expect(AddonCategory.pvp.matches(_addon('Questie', 'Quest helper')), isFalse);
    });
  });
}
