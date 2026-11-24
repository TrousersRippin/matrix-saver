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
| `make-dmg.sh` | Builds and packages `dist/Matrix-<version>.dmg` (drives Finder to lay out the window), plus `dist/matrix.zip` (the bare saver); `--zip` also makes `dist/Matrix-<version>.zip` |
| `make-thumbnail.swift`, `make-dmg-background.swift`, `Artwork/`, `Resources/` | Thumbnail and DMG artwork |
| `Tools/render-test.sh` | Renders the saver to a PNG without System Settings (see Testing) |
| `Tools/feed-test.sh`, `Tools/feed-test/` | Log feed tests, no network needed (see Testing) |
| `dist/` | Release DMGs |
| `readme.md` | GitHub readme: features, install, Loki setup, building, version history. Update it with each release |

**Git:** repo on `main`, remote `git@github.com:TrousersRippin/matrix-saver.git`. On 2026-11-18
the history was rewritten so each version is one commit, 1.0 to 2.13 (see Status and history for
the old numbers), each with a lightweight tag `vX.Y` on its commit. `.gitignore` ignores `build/`, `dist/` and
`.DS_Store`. Troy's global `~/.config/git/ignore` ignores `.gitignore` itself, so it was
force-added (`git add -f`); once tracked, edits to it show up normally. Commit or push only
when Troy asks.

## Commands

```bash
./build.sh             # build only (wipes build/)
./build.sh --install   # build, copy to ~/Library/Screen Savers, restart the saver host
./make-dmg.sh          # build + dist/Matrix-<CFBundleShortVersionString>.dmg + dist/matrix.zip
./make-dmg.sh --zip    # also dist/Matrix-<version>.zip (folder with saver + Instructions.txt)
Tools/render-test.sh   # render test, see below
Tools/feed-test.sh     # log feed tests (156 checks, ~1 min with compile); FILTER=<group> for some
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
  - Files: reads the last 256 KB, then appended lines every 3 s (if >256 KB arrived, the last
    256 KB from the first whole line, `read(midLine:)`). Rotation (inode changed, `fileID`, or
    file shrank) reads the new file from its start as new lines and keeps the history. Lines
    written to the old file after the last poll and before a rename are missed.
  - Loki: `query_range` over the last 24 h at start (backward, 2000), then forward from the
    newest timestamp every 3 s (every 10 s while unreachable). Each poll starts
    `lokiOverlap` (30 s) before the newest timestamp seen, so lines ingested late with older
    timestamps are caught; entries already seen (`lokiSeenIDs`: hash of time, stream labels and
    raw line) are skipped. The start fetch goes in up to 5
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
  - **Folding repeats** (always on): `store()` keeps one line per shape per source, the newest,
    moved to the newest end. `LogFeed.shape(of:)` hashes a line with every hex run (joined by
    `: . -`) holding a decimal digit folded to one mark, words compared in any order (Grafana
    shuffles its logfmt keys). Lines are encoded up to `maxEncoded` (800) glyphs so the shape is
    of the whole line, then `cut()` to `maxLineLength` (200) in `store`/`append`; otherwise
    numbers of different widths moved the cut and long repeats didn't match. New lines still all
    rain (`fresh` isn't folded). Live: unifi-siem 300 kept lines → ~23, grafana 300 → ~39.
  - **Banner text** (`LogFeed.bannerText`, error banners only, not alerts or the rain): keeps
    Loki's "name: " prefix, then `shorten()`: glog header off; `host prog[pid]:` → `prog:`; noise
    fields off (`level`, `lvl`, `severity`, `logger`, `component`, `user`, `userId`, `orgId`,
    `uname`, `t`, `fp`, `middleware`); a first level word off only if it is a marker (closed
    bracket, colon, capitals, or lower case before a capital as tidied JSON gives, so "Error
    handling request" stays; `<error code=...>` stays); then `msg="..."` first, unquoted. A line
    that would be empty is kept whole. Re-encoded, so keywords and level stay.
  - **Quiet alerts** (`Settings.quietAlerts`, Logs tab "Warn when logging goes quiet", default
    on, Loki only): `LogFeed.alerts` (id, time, text with its level in the glyph bits), shown by
    `stepBanner` before errors (alerts wait for a free banner, dropped after 2 min; each view keeps
    `alertShown` because the feed is shared). Loki unreachable ≥30 s after it had answered → red;
    back → plain, and 5 min grace for quiet alerts. Every 2 min (`watchQuiet`, set by the view)
    `checkQuiet` runs `sum by (service_name) (count_over_time(<query><filters> [300s]))` over
    12 h, step 300; `evaluateQuiet`: steady = lines in ≥85% of the 72 buckets of the 6 h before
    its last line; quiet once silent ≥ max(15 min, 2× longest gap in those 6 h); silences >6 h
    aren't judged. Back when a new line arrives (`append`) or counts show one. Live 2026-11-17:
    7 of 29 services steady (unifi-siem, seerr, postgres, loki, grafana, ghost, gatus).
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
  - **Split across displays** (`Settings.splitDisplays`, Logs tab "Split services across
    displays", default on, Loki only, not with Main display only): each view works out its
    `LogFeed.Part` (its index among `NSScreen.screens` sorted left to right, of the count; nil for
    previews or one display), rechecked every 2 s, and sets `Layer.part`;
    `nextLine(part:)` then uses only the sources `owner(parts:)` gives that display (busiest
    first, each to the display with least sqrt weight; recomputed only when a source is added).
    A display that owns none uses all. `fresh` entries carry their source: a new line waits for
    its own display; a new **error** line goes to every display (`taken`), so ripples and
    banners show everywhere. Alerts are per view as before.
  - **Service shades** (`Settings.serviceShades`, Logs tab "Shade the rain by service", default
    on, Loki only: `Settings.shadesShown`): each source has a `shade` 0-5 from an FNV-1a hash of
    its name (`LogFeed.shade(of:)`, stable across restarts and displays; a file's "" is 0).
    **Front layer only** (`Layer.shades`): inks are drawn after the tint, over every layer, so
    with Depth a back layer's shades covered the front layer, clock and banner (fixed in 2.15;
    back layers get no shade glyphs). `nextLine` returns it, `Drop.shade` carries it, and a plain cell gets ink
    `Layer.Ink.firstShade + shade - 1` (shade 0 stays plain and tinted). `Settings.shadeColors`
    gives shades 1-5: rain hue ±0.05, ±0.1 (saturation 0.9×), and paler (0.4× saturation);
    white rain gets pale tints (hues 0.3-0.9). A shade whose hue lands in the red (<0.06, >0.94)
    or amber (0.06-0.18) band, while the rain isn't there (`rainNear`, the same rule as
    `inkColors`), becomes the rain hue darker instead, so no shade passes for an error or warning
    (2.14 had Red rain's +0.1 shade amber). Hues are calibrated (generic RGB); Custom and Cycle use
    their exact hue. Ripples with level colours off leave shades alone. They are appended to `inkColors`, rendered by
    `renderInkGlyphs` with the trail's softer glow and drawn in `drawInk` at the trail's b²
    alpha, so shade 0 and the tinted rain look the same. Levels, keywords, ripples and banners
    override the shade. Under Colour Cycle the shade hue moves in 1/48 steps (2.5 s) and
    `renderInkGlyphs(budget: 1)` renders one changed colour per frame (~7 ms at 2560×1440 with
    Depth; all at once was ~35 ms, a dropped frame). Unchanged sets are kept.
- **Battery** (`Settings.batteryLight`, Effects tab "Lighter rain on battery", default on):
  `checkPower` every 5 s (IOKit `IOPSGetProvidingPowerSourceType`); on battery each
  `Layer.active` is × `batteryShare` (0.5, drops park when they finish falling, as for volume)
  and `frameInterval` caps fps at 20. Troy's Mac is a Mac mini (`Mac16,10`), so it is never on
  battery: tested by forcing `battery = true` in a scratch copy (moving drops 352 → ~180 over
  ~10 s, 20 fps). Not yet checked that IOKit power info is readable in the sandbox on a laptop.
- **Options sheet** (`OptionsController`): tabs Rain, Effects, Text, Logs. Laid out with **fixed
  frames, not Auto Layout**: in legacyScreenSaver an unsatisfiable constraint is an uncaught
  exception that freezes the sheet. The controller is independent of any view because System
  Settings drops the view while the sheet is open.
  - Logs tab: Source (file / Loki), Log file, Loki URL, **Services** (pull-down of checkboxes;
    checkbox views in menu items keep the menu open), Query, Keywords, "Colour lines by log level", "Shade the rain by service" (Loki only), "More rain when logs are busy", "Ripple when an error arrives", "Write new errors across the screen", "Warn when logging goes quiet" (Loki only), "Split services across displays" (Loki only). Pages are 14 rows (13 until 2.14). Services fetches
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

- **`Tools/feed-test.sh`: run it after any change to `LogFeed`**, and add checks for new feed
  behaviour to `Tools/feed-test/Tests.swift`. `LogFeed` is `private`, so the script appends
  `Tests.swift` to a copy of `MatrixView.swift` (`build/feed-test/Combined.swift`); the tests are
  static funcs in an `extension LogFeed` and can use its private members (e.g. `pollFile`,
  `fetchLoki`, `fresh`, `lokiDownSince`) and its private init (no shared instance). Loki is faked
  with a `URLProtocol` (`FakeLoki`, host `fake-loki.test`, `handler` gives status + JSON, and
  `requests` records the URLs). Groups: cleanup, levels, keywords, shape, fair share, shades, volume,
  displays (split, stable owners, new lines to their display, errors to all), file (tail, big
  append, rename/inode/truncate rotation, folding, empty/missing), loki (start,
  overlap/late/repeat, quiet check, down/back, unreachable at start), loki start rounds, quiet
  rules. Checked by breaking three behaviours in a copy: each was caught, exit status 1.
- `Tools/render-test.sh` compiles `MatrixView.swift` with a small driver and renders frames.
  Settings come from environment variables: `SOURCE` (file or Loki URL), `QUERY`, `DURATION`,
  `COLOR` (4 = Red, 8 = Cycle), `SHADES=0` (service shades off), `DEPTH=1` (three layers; off by default), `OUT`, `SHEET` + `TAB` (Options tab to PNG), `MENU=1` (drive the Services
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
3. `./make-dmg.sh --zip` (a Finder window opens and closes). The zip is made with
   `ditto -c -k --norsrc --keepParent`: `ditto` keeps the bundle exact so the signature verifies;
   `--norsrc` drops this Mac's xattrs (`com.apple.provenance`/`macl`), which became `._` files.
   Every run also makes `dist/matrix.zip`, just `Matrix.saver`, with Troy's command
   `ditto -c -k --sequesterRsrc --keepParent Matrix.saver matrix.zip` (run in `build/`). It keeps
   the xattrs in `__MACOSX` (Archive Utility restores them; other unzippers show the folder).
   The signature verifies after `ditto -x -k`. It's for Troy's own use, not for the GitHub release.
4. Check: `hdiutil verify`, mount read-only, version in the mounted `Info.plist`, binary matches
   `build/`, `codesign -v`; unzip the zip (`ditto -x -k`) and `codesign -v` it too. Then
   `./build.sh --install`.
5. When Troy asks: commit, push, then `gh release create vX.Y dist/Matrix-X.Y.dmg dist/Matrix-X.Y.zip --target main
   --title "Matrix X.Y" --notes-file <notes>` (`--target` needs a branch or full SHA, not a short
   one). Tag each release on its version commit. Since the renumbering, GitHub has releases
   v2.13, v2.14 (2026-11-21) and v2.15 (2026-11-24); the older versions have tags only.

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
- **2.9** (2026-11-15, was 3.12): three log fixes. (1) More than 256 KB appended between polls no
  longer starts mid-line. (2) Rotation is noticed when the path's inode changes, not only when
  the file shrinks; the new file's lines show as new and the history is kept. (3) Loki polls
  overlap 30 s and skip repeats, so late lines aren't missed. Tested with a scratch harness and
  a fake Loki via `URLProtocol` (a local Python HTTP server couldn't be reached on this Mac, even
  unsandboxed); 40 s live against the home Loki. Also `make-dmg.sh --zip` (2026-11-16):
  releases are a DMG and a zip from then on.
- **2.10** (2026-11-17, was 3.13): **fold repeated lines** in the history (see Logs mode, always
  on). Tested with a scratch harness: a 1500-line file of firewall lines with random IPs/MACs
  plus 20 distinct lines kept 21 lines; a new repeat replaced the old one; live Loki per-source
  counts; a render.
- **2.11** (2026-11-17, was 3.14): **quiet alerts** (see Logs mode). Tested with synthetic counts
  (steady service quiet 20 min → alert; bursty, steady-but-live, quiet >6 h, 2-hour-old service
  → none; a service with 10-min pauses alerted at 35 min, not 20), back via a new line and via
  counts, no repeat alert, Loki down 10 s → none, 31 s → one red alert, back → "Loki is back",
  grace blocks quiet alerts; live metric query (29 services, 7 steady, none quiet). Also
  **`Tools/feed-test.sh`**, the permanent log feed test (see Testing). Banner frames aren't in
  it (they're view-level: use render-test).
- **2.12** (2026-11-17, was 3.15): **shorter error banners** (see Banner text). Checked on 40
  distinct real error lines from the home Loki (grafana 367 → 268 chars, loki 117 → 81,
  dns-cache-db 110 → 86); 24 feed-test checks added; a render shows a one-row banner. Note for
  banner renders: start the background append after the test binary is built
  (`build/render-test`), or it lands while compiling and isn't new.
- **2.13** (2026-11-17, was 3.16): **lighter rain on battery** and **services split across
  displays** (see How it works). Feed tests 133 pass; Effects and Logs tabs rendered; battery
  tested by forcing it in a scratch copy. Can't be checked live on this Mac: it has one display
  (S34C65xU) and no battery. Installed on Troy's Mac.
- **2.14** (2026-11-21): **service shades** (see Logs mode). Feed tests 154 pass (21 new in
  "shades"); renders against the home Loki with all services in green, blue, white and Colour
  Cycle (2560×1440, Depth) and the Logs tab. The orange columns seen in the green render were
  real WRN lines (gotify, netbootxyz). Options pages grew to 14 rows. Installed on Troy's Mac.
- **2.15** (2026-11-24): fixes from a code review of 2.14. (1) With Depth, back layers' shaded
  text drew over the front layer, clock and banner: shades are now front layer only. (2) On Red
  or Amber rain a shade looked like the warning or error ink: shades avoid those bands (a feed
  test sweeps the palette and Custom/Cycle hues; with the fix disabled it fails on Red and
  Amber). (3) A ripple with level colours off removed shades. (4) The Logs tab note (1.5 rows
  tall from row 12/13) overflowed the page, which macOS 13 clips; now one row. Feed tests 156
  pass; renders with Depth in red and green, and the Logs tab.

Ideas not done (suggested 2026-11-15; Troy's picks, fold repeats, quiet-service alert,
the test script and service shades, are all done):
- Stats under the clock: errors in the last hour, lines per minute.
- Errors/warnings only; dim the start-fetch backlog; Grafana/Alertmanager alerts; Loki
  `/tail` WebSocket instead of polling.
- Grafana alerts (looked at 2026-11-19, set aside): Grafana 13.3.1 at `http://10.1.1.11:3000`;
  its alert APIs (`/api/prometheus/grafana/api/v1/alerts`, `/api/alertmanager/grafana/api/v2/alerts`)
  return 401 without auth. Alert state history isn't in Loki and ngalert doesn't log state changes
  at info. Routes: a Viewer service account token in prefs, or `[unified_alerting.state_history]`
  with `backend = loki` in grafana.ini so the saver reads it from Loki.
- Missed: lines written to a log between the last poll and a rename (would need the file kept open).
- Loki basic auth / API token (would be stored in plain text in prefs).
- Optional "colour the whole line" for keywords.
- The default `install.log` produces lots of red from "Failed to..." lines; Troy may trim
  the default keywords.
