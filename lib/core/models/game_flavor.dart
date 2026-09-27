/// The game ruleset an installation runs. Addon sources publish files per
/// flavor, so every lookup is scoped by it.
enum GameFlavor {
  retail('Retail'),
  mists('Mists Classic'),
  cata('Cataclysm Classic'),
  wrath('Wrath Classic'),
  tbc('TBC Classic'),
  vanilla('Classic Era');

  const GameFlavor(this.label);

  final String label;

  /// Maps a major game version (e.g. `11` from `11.2.0.62213`) to its flavor.
  static GameFlavor fromMajorVersion(int major) => switch (major) {
    1 => GameFlavor.vanilla,
    2 => GameFlavor.tbc,
    3 => GameFlavor.wrath,
    4 => GameFlavor.cata,
    5 => GameFlavor.mists,
    _ => GameFlavor.retail,
  };

  /// Maps a TOC interface number (e.g. `110200`, `50500`, `11507`).
  static GameFlavor fromInterface(int interface) =>
      fromMajorVersion(interface ~/ 10000);

  static GameFlavor? tryParse(String? name) =>
      GameFlavor.values.where((f) => f.name == name).firstOrNull;
}

/// A concrete game client folder inside a WoW installation root.
enum WowClientType {
  retail('_retail_', 'Retail', GameFlavor.retail),
  ptr('_ptr_', 'Retail PTR', GameFlavor.retail),
  xptr('_xptr_', 'Retail XPTR', GameFlavor.retail),
  beta('_beta_', 'Retail Beta', GameFlavor.retail),
  classic('_classic_', 'Classic', GameFlavor.mists),
  classicPtr('_classic_ptr_', 'Classic PTR', GameFlavor.mists),
  classicBeta('_classic_beta_', 'Classic Beta', GameFlavor.mists),
  classicEra('_classic_era_', 'Classic Era', GameFlavor.vanilla),
  classicEraPtr('_classic_era_ptr_', 'Classic Era PTR', GameFlavor.vanilla),
  anniversary('_anniversary_', 'Anniversary', GameFlavor.tbc);

  const WowClientType(this.folderName, this.label, this.defaultFlavor);

  final String folderName;
  final String label;

  /// Used when the client's real version cannot be read from `.build.info`.
  final GameFlavor defaultFlavor;

  static WowClientType? fromFolderName(String name) => WowClientType.values
      .where((c) => c.folderName == name.toLowerCase())
      .firstOrNull;

  static WowClientType? tryParse(String? name) =>
      WowClientType.values.where((c) => c.name == name).firstOrNull;
}
