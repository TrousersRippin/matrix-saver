#!/bin/zsh
# Tests the log feed (LogFeed in MatrixView.swift): line cleanup, levels, folding repeats, fair
# share, volume, file tailing and rotation, Loki fetches against a fake server, and quiet alerts.
# Needs no network and no Loki. Prints each check and exits non-zero if any fail.
#
# LogFeed is private to MatrixView.swift, so the tests are appended to a copy of that file and
# compiled with it; the saver's own source is unchanged. Output goes in build/feed-test.
#   Tools/feed-test.sh            # all tests
#   FILTER=loki Tools/feed-test.sh  # only groups whose name contains "loki"
set -euo pipefail
cd "${0:A:h}/.."

out=build/feed-test
rm -rf "$out"
mkdir -p "$out"
cat MatrixView.swift Tools/feed-test/Tests.swift > "$out/Combined.swift"
swiftc -target arm64-apple-macos13 -o "$out/feed-test" \
  "$out/Combined.swift" Tools/feed-test/main.swift -framework ScreenSaver -framework AppKit
"$out/feed-test" "$out/tmp"
