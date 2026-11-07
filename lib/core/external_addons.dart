/// Folder name prefixes (lower case) of addons that are distributed only
/// through a subscription or the vendor's own client. No addon source
/// carries them, so they are marked external instead of plain local.
const _externalPrefixes = [
  'zygorguidesviewer', // Zygor Guides (Zygor client)
  'rxpguides', // RestedXP Guides (RXP app)
  'tradeskillmaster_apphelper', // TSM desktop app
  'weakaurascompanion', // WeakAuras Companion app
];

/// Whether the AddOns folder [name] belongs to a known externally
/// distributed addon.
bool isKnownExternalAddon(String name) {
  final lower = name.toLowerCase();
  return _externalPrefixes.any(lower.startsWith);
}
