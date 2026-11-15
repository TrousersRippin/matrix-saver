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
| `dist/` | Release DMGs |
| `readme.md` | GitHub readme: features, install, Loki setup, building, version history. Update it with each release |

**Git:** repo on `main`, remote `git@github.com:TrousersRippin/matrix-saver.git` (first commit
2026-11-06). `.gitignore` ignores `build/`, `dist/` and `.DS_Store` (they were tracked in the
first commit and untracked afterwards). Troy's global `~/.config/git/ignore` ignores `.gitignore`
itself, so it was force-added (`git add -f`); once tracked, edits to it show up normally. Commit or push only
when Troy asks.

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
  mutation is off, drops fall at the same speed as Film but trails are longer (fade 0.75×,
  i.e. 1.33× the length) so it can be read.
  - `LogSource`: `.file(path)` or `.loki(url:query:)`.
  - `LogFeed`: one **shared** instance per process (`LogFeed.shared`), because System Settings
    makes several preview views and the saver has one view per display. `poll()` is called from
    the view's `step`, so nothing is polled while the saver isn't drawing.
  - Files: reads the last 256 KB, then appended lines every 3 s, restarting on rotation.
  - Loki: `query_range` over the last 24 h at start (backward, 2000), then forward from the
    newest timestamp every 3 s (every 10 s while unreachable). The start fetch goes in up to 5
    rounds: services with ≥300 lines (else the top one) are excluded
    (`service_name!~"..."` inserted into the selector, `LogFeed.query(_:excluding:)`) and it
    reruns, so quiet services get lines from further back. Stops when a round returns <2000.
    Lines are prefixed with
    `container_name` / `service_name` / `job`. `tidy()` turns JSON into "level message k=v" and
    drops logfmt noise (`ts`, `caller`, `org_id`, `query_hash`, ...). Leading timestamps and a
    repeated host name are stripped.
  - **Fair share:** history is kept per source (`LogFeed.Source`, keyed by `service_name`, else
    the shown name; a file is one source "") with 300 lines each (3000 for a file). `nextLine()`
    takes new lines first, then picks a source by smooth weighted round-robin, weight
    sqrt(line count). Measured with all ~27 services: unifi-siem went from 52% of drops to 6%.
  - **Self-echo filter:** Loki logs every query it runs, so each poll appends
    `!= "matrix-saver-poll" != "query_type=stats"` (`LogFeed.lokiFilters`). The tag removes lines
    about the saver's own queries; Loki's per-query stats lines drop the tag, hence the second
    filter.
    A third filter, `!~ "caller=(scheduler_processor|errors).go.*(context canceled|err=EOF)"`,
    drops the `level=error` lines Loki logs when it cancels the leftover hourly subqueries of the
    saver's 24 h start fetch (about 8 per start; before this they rained red and fired a ripple
    at every start). Over 7 days nothing outside Loki matched the pattern.
  - Keywords: matched case-insensitively when a line is encoded; matching letters carry
    `LogFeed.keywordBit` (0x8000) and become `Layer.Ink.keyword` cells, drawn red after tinting
    (white if the rain is red, including while Colour Cycle passes through red).
  - **Levels** (`Settings.levelColors`, default on): `LogFeed.level(of:)` / `level(labels:)` guess
    each line's level (level= field, CEF severity, glog prefix, else the first level word near
    the start: any case if first or bracketed, capitals only elsewhere). It goes in glyph bits
    13-14 (`levelBits`). Each cell gets a `Layer.Ink` class (plain, keyword, error, warn, debug,
    keyword-on-error); `Settings.inkColors` gives the colours (red, amber, white when the rain is
    near that colour) and `renderInkGlyphs()` renders one glyph set per colour, re-rendered when
    Colour Cycle crosses an edge. Debug is drawn tinted at 0.4 alpha. ANSI colour codes are
    stripped from lines.
  - **Volume** (`Settings.followVolume`, default on): `LogFeed.updateVolume` (from `poll()`, once a
    second) compares new lines in the last 20 s (`append` records `arrivals`) with a usual rate,
    seeded from Loki's initial fetch (count / span) or a file's first 60 s, then a 15-min moving
    average that a burst can only pull towards 3× usual. `volume` = sqrt(ratio) clamped 0.5...2.5.
    The view eases `volumeShown` towards it and sets each `Layer.active`; layers allocate 2.5× the
    drops, and drops past `active` park (`Drop.idle`) when they finish falling.
- **Options sheet** (`OptionsController`): tabs Rain, Effects, Text, Logs. Laid out with **fixed
  frames, not Auto Layout**: in legacyScreenSaver an unsatisfiable constraint is an uncaught
  exception that freezes the sheet. The controller is independent of any view because System
  Settings drops the view while the sheet is open.
  - Logs tab: Source (file / Loki), Log file, Loki URL, **Services** (pull-down of checkboxes;
    checkbox views in menu items keep the menu open), Query, Keywords, "Colour lines by log level", "More rain when logs are busy", "Ripple when an error arrives", "Write new errors across the screen". Pages are 11 rows. Services fetches
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
2. Update the version and history in `readme.md` (and `Instructions.txt` if options changed).
3. `./make-dmg.sh` (a Finder window opens and closes).
4. Check: `hdiutil verify`, mount read-only, version in the mounted `Info.plist`, binary matches
   `build/`, `codesign -v`. Then `./build.sh --install`.
5. When Troy asks: commit, push, then `gh release create vX.Y dist/Matrix-X.Y.dmg --target main
   --title "Matrix X.Y" --notes-file <notes>` (`--target` needs a branch or full SHA, not a short
   one).

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

Renumbered on 2026-11-18 (see Git): versions before the log features are 1.x, Logs mode and
after are 2.x. Old numbers are in brackets, as older notes, DMGs and GitHub may mention them.

- **1.0** (2026-10-30): first version.
- **1.1** (2026-11-06, was 2.2): presets, colours, depth, glow, CRT, glitches, rain clock, film
  intro, hidden messages. Its source wasn't kept separately: rebuilt on 2026-11-18 from 2.0 by
  removing the log code (Logs character set, `LogFeed`, keywords, the Logs tab). Checked that it
  compiles and renders, with the Options sheet on three tabs; never installed as such.
- **2.0** (2026-11-06, was 3.0-3.3): Logs character set raining a log file's lines; keywords in
  red; Loki source with log settings on a new Logs tab; Services picker for Loki.
- **2.1** (2026-11-07, was 3.4 and 3.5): Logs drops fall at Film speed (fade 0.75 so the trail is
  long enough to read). All rain 20% slower at every Speed setting: `Settings.baseSpeed = 0.8`
  multiplies `settings.speed` (drops and fade together, so trails keep their length); the slider
  still reads 1.00×.
- **2.2** (2026-11-14, was the 3.5 rebuild): bug fixes. Log drops show no head above their start
  row (it showed a stale random glyph); an empty log file says IS EMPTY, not CANNOT READ; an
  empty Loki service list says so instead of "Loading services…"; keyword colour follows Colour
  Cycle.
- **2.3** (2026-11-15, was 3.6): **colour by log level** (Logs tab checkbox). Also fixed: ANSI
  colour codes rained as "[32m"; the timestamp stripper ate zerolog levels (`INF`, `ERR`) after
  ISO times, taking them for a time zone.
- **2.4** (2026-11-15, was 3.7): **rain density follows log volume** (Logs tab checkbox). Tested
  with a scratch harness (seed, 2.5× in a burst, back to ~1× 20 s after) and renders.
- **2.5** (2026-11-15, was 3.8): **error ripple** (`Settings.errorRipple`, Logs tab "Ripple when
  an error arrives", default on). A drop carrying a *newly arrived* error line
  (`LogFeed.nextLine()` returns `isNew`) records its column/row in `Layer.ripplesAt` when its
  first character shows; `MatrixView.stepRipples` turns that into a ring (1.6 s, ≤1 per 3 s)
  that raises `bright` and sets error ink on cells it crosses (plain ink if level colours are
  off). Levels are now always encoded in lines; `LogFeed.ink(_:levels:)` ignores them when
  colour-by-level is off. Tested with a scratch harness (append an error line mid-run, capture
  frames): red concentric rings, gone after ~2 s.
- **2.6** (2026-11-15, was 3.9): fix. Loki's own cancellation errors from the saver's start fetch
  got past the self-echo filter (seen in Loki: every scheduler_processor error burst over 6 h
  matched a saver start). Added the third filter in `LogFeed.lokiFilters`; checked live (7 new
  errors at start, 0 let through) and with a render.
- **2.7** (2026-11-15, was 3.10): **fair share between services** (always on, no checkbox).
  Before, the 2000-line start fetch covered only the last ~29 min and was half unifi-siem;
  Postgres had 10 lines. Tested with a scratch harness (2000 `nextLine()` calls, all services:
  27 sources, top ones ~6% each) and renders (file and Loki).
- **2.8** (2026-11-15, was 3.11): **error banner**. `Settings.errorBanner`, Logs tab "Write new
  errors across the screen", default on. Same trigger as the ripple (`Layer.newErrors`, which
  now carries the line's text): `MatrixView.stepBanner` types the line (80 letters/s) across the
  front layer, wrapped at spaces to ≤72 columns and ≤3 rows, in a cleared strip (`bannerBox`:
  cells zeroed, back layers darkened in `drawLayer`, heads skipped), holds 4 s, then lets
  letters go at random over 1.5 s so the rain eats them. ≤1 per 10 s. Always in error ink (red,
  white on red rain) even with level colours off, so ink glyphs are rendered whenever the banner
  is on. Tested with a scratch harness (append an error to a file mid-run, frames every 0.5 s):
  typed, readable, melted, gone after ~7 s.

Ideas not done:
- Loki basic auth / API token (would be stored in plain text in prefs).
- Optional "colour the whole line" for keywords.
- The default `install.log` produces lots of red from "Failed to..." lines; Troy may trim
  the default keywords.
