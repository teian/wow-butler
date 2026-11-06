import 'addon.dart';

/// Curated browse categories for the discover page.
///
/// Each category carries the matching CurseForge category id (used for
/// server side filtering) and a list of aliases. The aliases double as
/// search tags — typing one into the search field activates the category —
/// and as keyword matchers for sources without their own category data.
enum AddonCategory {
  actionBars('Aktionsleisten', 1018, [
    'action bars',
    'actionbars',
    'actionbar',
    'bars',
  ]),
  auction('Auktion & Wirtschaft', 1002, [
    'auction',
    'auktion',
    'auktionshaus',
    'economy',
    'wirtschaft',
    'gold',
    'ah',
  ]),
  bags('Taschen & Inventar', 1009, [
    'bags',
    'bag',
    'inventory',
    'taschen',
    'inventar',
    'bank',
  ]),
  bossMods('Bosskämpfe', 1014, [
    'boss',
    'boss mods',
    'bossmods',
    'encounter',
    'encounters',
  ]),
  buffs('Buffs & Debuffs', 1005, ['buffs', 'debuffs', 'aura', 'auras', 'auren']),
  chat('Chat', 1001, ['chat', 'communication', 'kommunikation']),
  classes('Klassen & Rotation', 1020, [
    'class',
    'klasse',
    'klassen',
    'rotation',
  ]),
  combat('Kampf & Meter', 1019, [
    'combat',
    'kampf',
    'damage meter',
    'dps',
    'meter',
    'threat',
  ]),
  hud('HUDs', 1039, ['hud', 'huds']),
  maps('Karte & Minimap', 1011, [
    'map',
    'maps',
    'minimap',
    'karte',
    'weltkarte',
    'coords',
    'koordinaten',
  ]),
  professions('Berufe', 1015, [
    'professions',
    'profession',
    'berufe',
    'beruf',
    'crafting',
    'handwerk',
  ]),
  pvp('PvP & Arena', 1004, [
    'pvp',
    'arena',
    'battleground',
    'schlachtfeld',
  ]),
  quests('Quests & Leveln', 1013, [
    'quest',
    'quests',
    'leveling',
    'leveln',
    'guide',
    'guides',
  ]),
  raidFrames('Raid-Frames', 1037, [
    'raid frames',
    'raidframes',
    'raid frame',
  ]),
  tooltip('Tooltips', 1055, ['tooltip', 'tooltips']),
  unitFrames('Einheitenfenster', 1016, [
    'unit frames',
    'unitframes',
    'unit frame',
    'einheitenfenster',
    'nameplates',
    'nameplate',
  ]);

  const AddonCategory(this.label, this.curseforgeId, this.aliases);

  final String label;
  final int curseforgeId;
  final List<String> aliases;

  /// Resolves a search term that names a category exactly (label or alias),
  /// so tags can simply be typed into the search field.
  static AddonCategory? parse(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;
    return values
        .where((c) => c.label.toLowerCase() == q || c.aliases.contains(q))
        .firstOrNull;
  }

  static final _patterns = <AddonCategory, RegExp>{
    for (final c in values)
      c: RegExp(
        r'\b(?:' + c.aliases.map(RegExp.escape).join('|') + r')\b',
        caseSensitive: false,
      ),
  };

  /// Keyword heuristic for sources without category metadata: does the
  /// addon's name or summary mention this category?
  bool matches(RemoteAddon addon) =>
      _patterns[this]!.hasMatch('${addon.name} ${addon.summary ?? ''}');
}
