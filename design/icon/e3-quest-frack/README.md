# WoW Butler – App-Icon E3 „Quest-! im Frack“ (Hell & Dunkel)

| Ordner / Datei | Inhalt |
|---|---|
| `dunkel/` | Dunkle Variante: `wow-butler.svg`, `-small.svg` (16–32 px), PNGs, `.ico`, `.icns` |
| `hell/` | Helle Variante: `wow-butler-light.*`, gleicher Aufbau |
| `linux/hicolor/` | Beide als Theme-Icons: `wow-butler` (dunkel) und `wow-butler-light` (hell) |
| `linux/wow-butler.desktop` | Desktop-Eintrag (`Icon=wow-butler`) |

Beide Kacheln haben einen eigenen Hintergrund und einen Goldrahmen und lesen sich deshalb auf
hellem wie dunklem Untergrund. Die Wahl betrifft vor allem die Optik zum App-Theme.

## Umschalten zur Laufzeit

Dock-, Taskleisten- und Datei-Icons (`.ico`, `.icns`, `.desktop`) sind statisch, dort gilt
eine Variante, Standard: dunkel. Das Fenster- bzw. Tray-Icon kann die App beim Theme-Wechsel tauschen:

- Tauri: `window.set_icon(...)` / `tray.set_icon(...)` beim `ThemeChanged`-Event
- Electron: `nativeTheme.on('updated', …)` → `win.setIcon()` / `tray.setImage()`
- Qt: `QIcon::fromTheme(dark ? "wow-butler" : "wow-butler-light")`

## Linux installieren (pro Benutzer)

    cp -r linux/hicolor ~/.local/share/icons/
    cp linux/wow-butler.desktop ~/.local/share/applications/
    gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor 2>/dev/null || true

Für die helle Variante als Programmicon in der `.desktop`-Datei `Icon=wow-butler-light` setzen.
