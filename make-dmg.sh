#!/bin/zsh
# Builds Matrix.saver and packages it into dist/Matrix-<version>.dmg, with a styled
# Finder window and Instructions.txt. Finder may ask for permission to be automated.
set -euo pipefail
cd "${0:A:h}"

./build.sh

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
VOLUME="Matrix $VERSION"
DMG="dist/Matrix-$VERSION.dmg"
WORK="build/dmg"
RW="$WORK/rw.dmg"
STAGE="$WORK/stage"
MOUNT="/Volumes/$VOLUME"

[[ -d "$MOUNT" ]] && hdiutil detach "$MOUNT" -quiet
mkdir -p "$STAGE/.background" dist
ditto build/Matrix.saver "$STAGE/Matrix.saver"
cp Instructions.txt "$STAGE/"

swiftc -o "$WORK/make-background" make-dmg-background.swift -framework AppKit
"$WORK/make-background" Artwork/matrix.jpeg "$WORK"
# One multi-resolution image, so the background stays sharp on Retina displays.
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" \
  -out "$STAGE/.background/background.tiff" 2>/dev/null

hdiutil create -quiet -ov -srcfolder "$STAGE" -volname "$VOLUME" -fs HFS+ -format UDRW "$RW"
hdiutil attach -quiet -noautoopen "$RW"
trap '[[ -d "$MOUNT" ]] && hdiutil detach "$MOUNT" -force -quiet' EXIT

# Window content is 660x400, matching make-dmg-background.swift; bounds add the 28pt title bar.
osascript <<EOF
tell application "Finder"
  activate
  -- Finder can take a moment to notice a newly attached disk.
  repeat 40 times
    if exists disk "$VOLUME" then exit repeat
    delay 0.5
  end repeat
  tell disk "$VOLUME"
    open
    delay 1
    tell container window
      set current view to icon view
      set toolbar visible to false
      set statusbar visible to false
    end tell
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 96
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "Matrix.saver" of container window to {210, 175}
    set position of item "Instructions.txt" of container window to {450, 175}
    update without registering applications
    delay 1
    close
    open
    delay 1
  end tell
  -- Set last, on the reopened window: Finder saves the size of the window as it closes.
  set bounds of front window to {200, 120, 860, 548}
  delay 2
  close front window
  delay 2
end tell
EOF

sync
hdiutil detach "$MOUNT" -quiet
trap - EXIT
hdiutil convert -quiet -ov "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -rf "$WORK"
echo "Built $DMG"
