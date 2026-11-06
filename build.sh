#!/bin/zsh
# Builds Matrix.saver (Apple silicon) into ./build.
#   --install    also copy it to ~/Library/Screen Savers
#   --thumbnail  regenerate Resources/thumbnail*.png from the build, then rebuild with them
set -euo pipefail
cd "${0:A:h}"

NAME="Matrix.saver"
OUT="build/$NAME"
DEST=~/Library/Screen\ Savers

build() {
  rm -rf build && mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
  cp Info.plist "$OUT/Contents/"
  [[ -d Resources ]] && cp Resources/* "$OUT/Contents/Resources/"

  swiftc -O -module-name MatrixSaver -target arm64-apple-macos13 \
    -emit-library -Xlinker -bundle -o "$OUT/Contents/MacOS/Matrix" \
    MatrixView.swift -framework ScreenSaver -framework AppKit
  codesign --force --sign - "$OUT"
  echo "Built $OUT"
}

build

if [[ "${1:-}" == "--thumbnail" ]]; then
  mkdir -p Resources
  swiftc -o build/make-thumbnail make-thumbnail.swift -framework ScreenSaver -framework AppKit
  build/make-thumbnail "$OUT" Resources
  build
fi

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$DEST"
  rm -rf "$DEST/$NAME" "$DEST/Matrix Rain.saver"  # Matrix Rain.saver: name used in v1.2
  cp -R "$OUT" "$DEST/"
  killall legacyScreenSaver WallpaperLegacyExtension 2>/dev/null || true
  echo "Installed to $DEST/$NAME"
fi
