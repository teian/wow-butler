# CurseForge user agent

CurseForge's API and CDN reject or throttle unknown third-party clients, so
WoW Butler identifies itself the way the WowUp CurseForge client does. The
user-agent constants are versioned and must be kept current.

## Strategy

A CurseForge download is attempted in order:

1. **Browser user agent** (`CurseForgeSource.browserUserAgent`) — a regular,
   current Chrome desktop user agent. CurseForge serves files to a normal
   browser, so this is the primary attempt and is also used for the Core API
   requests (`_headers`).
2. **WowUp-CF user agent** (`CurseForgeSource.wowupCfUserAgent`) — the exact
   agent the WowUp CurseForge client sends, used as a fallback when the CDN
   rejects the browser agent.

`AddonSource.downloadRequests(...)` returns the attempts in order and
`AddonService.prepare` retries the next one on failure. Both constants live in
`lib/sources/curseforge_source.dart`.

## Keep the versions current

Both are versioned and silently go stale. Bump them when they fall behind:

- **`browserUserAgent`** — the `Chrome/<major>` part should match the current
  Chrome stable release. Check
  <https://chromereleases.googleblog.com> or
  <https://chromiumdash.appspot.com/schedule>.

- **`wowupCfVersion`** (used by `wowupCfUserAgent`) — match the product version
  of the WowUp CurseForge client, from the `version` field of
  `wowup-electron/package.json` in <https://github.com/WowUp/WowUp> (`master`).
  Keep the format identical to WowUp-CF's `getUserAgent` in
  `wowup-electron/app/main.ts`:

      WowUp-Client/<version> (<os.type()>; <os.release()>; <os.arch()>; CF;  +https://wowup.io)

  Note the **two spaces after `CF;`**: WowUp-CF interpolates an empty portable
  flag there. The OS and architecture parts are derived at runtime from
  `dart:io`'s `Platform`, so only the version needs bumping.

The format is asserted in `test/curseforge_source_test.dart` and
`test/curseforge_download_test.dart`; run `flutter test` after bumping.
