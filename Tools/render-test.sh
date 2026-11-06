#!/bin/zsh
# Renders the saver in Logs mode to a PNG without System Settings. Settings come from environment
# variables; see Tools/render-test/main.swift. Examples:
#   Tools/render-test.sh                                         # install.log -> build/render-test.png
#   SOURCE=/var/log/wifi.log COLOR=4 Tools/render-test.sh        # another file, red rain
#   SOURCE=http://10.1.1.11:3100 DURATION=12 Tools/render-test.sh # Loki, default query
#   SOURCE=http://10.1.1.11:3100 SHEET=build/logs-tab.png TAB=3 Tools/render-test.sh
#   SOURCE=http://10.1.1.11:3100 MENU=1 Tools/render-test.sh     # drive the Services menu
set -euo pipefail
cd "${0:A:h}/.."

mkdir -p build
swiftc -O -target arm64-apple-macos13 -o build/render-test \
  MatrixView.swift Tools/render-test/main.swift -framework ScreenSaver -framework AppKit
build/render-test
# The test writes the unsandboxed ByHost prefs; don't leave them lying around.
defaults -currentHost delete local.agentsmith.MatrixSaver >/dev/null 2>&1 || true
rm -f ~/Library/Preferences/ByHost/local.agentsmith.MatrixSaver.*.plist(N)  # the empty file it leaves
