# Matrix screen saver

A macOS screen saver (`Matrix.saver`) of digital rain. Apple silicon, macOS 13+. All the code is in
`MatrixView.swift`.

**Handoff:** development switches between Troy's work and personal Claude accounts, which don't
share memory or chat history. This file is the shared record. Read it first, and at the end of a
session update **Status and history** and anything else that changed.

## Files

| Path | What |
|---|---|
| `MatrixView.swift` | Everything: settings, rain, log feed, drawing, Options sheet |
| `Info.plist` | Bundle info. Version lives here (see Releasing) |
| `Instructions.txt` | User docs, shipped in the DMG. Update it when options change |
| `build.sh` | Builds `build/Matrix.saver`. `--install` also installs it; `--thumbnail` regenerates thumbnails |
| `make-dmg.sh` | Builds and packages `dist/Matrix-<version>.dmg` (drives Finder to lay out the window) |
| `make-thumbnail.swift`, `make-dmg-background.swift`, `Artwork/`, `Resources/` | Thumbnail and DMG artwork |
| `Tools/render-test.sh` | Renders the saver to a PNG without System Settings (see Testing) |
| `Archive/1.0/` | Source of version 1.0 only |
| `dist/` | Release DMGs |

Not a git repository.

## Commands

```bash
./build.sh             # build only (wipes build/)
./build.sh --install   # build, copy to ~/Library/Screen Savers, restart the saver host
./make-dmg.sh          # build + dist/Matrix-<CFBundleShortVersionString>.dmg
Tools/render-test.sh   # render test, see below
```

## How it works

- **Settings** (struct): persisted with `ScreenSaverDefaults` (module `local.agentsmith.MatrixSaver`).
  Add a key in all four places: property, `register(defaults:)`, `load()`, `save()`.
- **Drawing:** glyphs are pre-rendered **white** into small images. A frame blits them, then one
  `.multiply` fill tints the whole frame. Anything that must keep its own colour is drawn **after**
  the tint: bright head cores, hidden messages, and red log keywords (`drawKeywords`).
- **Layer:** one plane of rain (three with Depth). `chars`, `bright`, and `hot` (keyword cells) are
  per-cell arrays. `Drop` is a falling head.
- **Character sets:** Film, Binary, Latin, Custom, Logs (`Settings.logCharset = 4`). Logs uses
  printable ASCII, glyph index = scalar - 0x20.
- **Logs mode:** each drop spells one log line top to bottom from a random start row. Glyph
  mutation is off, drops are slower and trails longer so it can be read.
  - `LogSource`: `.file(path)` or `.loki(url:query:)`.
  - `LogFeed`: one **shared** instance per process (`LogFeed.shared`), because System Settings
    makes several preview views and the saver has one view per display. `poll()` is called from
    the view's `step`, so nothing is polled while the saver isn't drawing.
  - Files: reads the last 256 KB, then appended lines every 3 s, restarting on rotation.
  - Loki: `query_range` over the last 24 h at start (backward, 2000), then forward from the
    newest timestamp every 3 s (every 10 s while unreachable). Lines are prefixed with
    `container_name` / `service_name` / `job`. `tidy()` turns JSON into "level message k=v" and
    drops logfmt noise (`ts`, `caller`, `org_id`, `query_hash`, ...). Leading timestamps and a
    repeated host name are stripped.
  - **Self-echo filter:** Loki logs every query it runs, so each poll appends
    `!= "matrix-saver-poll" != "query_type=stats"` (`LogFeed.lokiFilters`). The tag removes lines
    about the saver's own queries; Loki's per-query stats lines drop the tag, hence the second
    filter.
  - Keywords: matched case-insensitively when a line is encoded; matching letters carry
    `LogFeed.keywordBit` (0x8000) and become `hot` cells, drawn red (white if the rain is red).
- **Options sheet** (`OptionsController`): tabs Rain, Effects, Text, Logs. Laid out with **fixed
  frames, not Auto Layout**: in legacyScreenSaver an unsatisfiable constraint is an uncaught
  exception that freezes the sheet. The controller is independent of any view because System
  Settings drops the view while the sheet is open.
  - Logs tab: Source (file / Loki), Log file, Loki URL, **Services** (pull-down of checkboxes;
    checkbox views in menu items keep the menu open), Query, Keywords. Services fetches
    `/loki/api/v1/label/service_name/values` for the last 7 days and writes
    `{service_name=~"a|b"}` into Query. Any other query shows as "Custom query".
  - Migration in `Settings.load()`: an `http(s)://` in `logPath` (from a test build) moves to
    `lokiURL` with Source = Loki.

## Sandbox (verified 2026-11-06, macOS 27)

The saver runs inside Apple's sandboxed `legacyScreenSaver`. Its entitlements include:
- read-only access to `/` (`temporary-exception.files.absolute-path.read-only`), so any file
  readable by the user works, e.g. `/var/log/wifi.log` (admin group);
- `network.client`. Verified: plain `http://` to a LAN IP works from the real host, with no Local
  Network prompt or block.

The real saver's prefs are in its sandbox container, which the shell can't write (macOS app data
protection). To change the installed saver's settings, ask Troy to use Options.

## Testing

- `Tools/render-test.sh` compiles `MatrixView.swift` with a small driver and renders frames.
  Settings come from environment variables: `SOURCE` (file or Loki URL), `QUERY`, `DURATION`,
  `COLOR` (4 = Red), `OUT`, `SHEET` + `TAB` (Options tab to PNG), `MENU=1` (drive the Services
  menu). Look at the PNGs. It is **not sandboxed**, so it can't prove sandbox behaviour. It deletes
  its ByHost prefs afterwards. Output goes in `build/`, which `build.sh` wipes.
- **In the real host:** after `./build.sh --install`, open
  `x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension`. The preview runs in a
  `legacyScreenSaver` process; if `pgrep -l legacyScreenSav` shows none, the preview isn't running
  (ask Troy to select Matrix). Loki errors are logged:
  `/usr/bin/log show --last 5m --predicate 'subsystem == "local.agentsmith.MatrixSaver"'`.
- **Checking the saver's Loki polls:** query Loki's own logs for the tag, with a unique extra
  filter so the check doesn't match itself:
  `{container_name="loki"} |= "engine.go" |= "matrix-saver-poll" != "<unique-word>"`.

## Gotchas on this Mac

- `sed` on PATH is **GNU** sed: `sed -i '' ...` fails. Use `sed -i`, python, or PlistBuddy.
- In zsh, `log` is shadowed; use `/usr/bin/log`.
- Avoid `SECONDS` as an env var in zsh (built-in timer).
- `build.sh --install` kills `legacyScreenSaver` / `WallpaperLegacyExtension`; System Settings may
  need reopening to show the new build.
- DMGs are ad-hoc signed, not notarized (Instructions.txt explains Open Anyway).

## Releasing

1. `/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString X.Y' -c 'Set :CFBundleVersion N' Info.plist`
   (bump the build number by one every release).
2. `./make-dmg.sh` (a Finder window opens and closes).
3. Check: `hdiutil verify`, mount read-only, version in the mounted `Info.plist`, binary matches
   `build/`, `codesign -v`. Then `./build.sh --install`.

## Troy's preferences

- Each finished feature gets a minor version bump and a new DMG, when Troy says so.
- Troy deletes old DMGs from `dist/` and doesn't need old builds kept. Don't flag a
  missing old DMG, but ask before deleting any yourself.
- Confirm with Troy before installing a build over the one he uses, unless he has asked for it.

## Home server (for Loki mode)

- Loki: `http://10.1.1.11:3100`, no auth. Logs arrive via Grafana Alloy (Docker containers,
  systemd journal, UniFi gateway as `unifi-siem`).
- Labels include `service_name` (~39 values over a week) and `container_name` (Docker only).
- Busiest: `unifi-siem` ~3000 lines/h, `loki` ~1500/h. Postgres ~26/h. Traefik logs almost
  nothing because its access log is off (`accessLog` in its static config would fix that).

## Status and history

- **2.2**: baseline (Film/Binary/Latin/Custom, depth, glow, CRT, glitches, clock, intro, messages).
- **3.0** (2026-11-06): Logs character set, raining lines from a log file.
- **3.1** (2026-11-06): keywords shown in red.
- **3.2** (2026-11-06): Loki source; log settings moved to a new Logs tab.
- **3.3** (2026-11-06): Services picker for Loki. Current release, installed on Troy's Mac.

Ideas not done:
- Loki basic auth / API token (would be stored in plain text in prefs).
- Optional "colour the whole line" for keywords.
- The default `install.log` produces lots of red from "Failed to..." lines; Troy may trim
  the default keywords.
