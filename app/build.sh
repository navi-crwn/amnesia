#!/bin/bash
# Build app Amnesia (SwiftUI) tanpa Xcode — cukup Command Line Tools.
# Jalankan:  bash ~/.amnesia/app/build.sh
set -euo pipefail
cd "$(dirname "$0")"
command -v swiftc >/dev/null || { echo "Command Line Tools are missing. Run: xcode-select --install"; exit 1; }

B="$PWD/build"; APP="$B/Amnesia.app"; ARCH="$(uname -m)"
rm -rf "$B"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$B/AppIcon.iconset"

[ -f ../keep.conf ] || cp ../keep.example.conf ../keep.conf   # Keep List pertama dari contoh
echo "1/4  Compile app..."
swiftc -swift-version 5 -O -parse-as-library -target "$ARCH-apple-macos15.0" Amnesia.swift -o "$APP/Contents/MacOS/Amnesia"
cp Info.plist "$APP/Contents/Info.plist"

echo "2/4  Drawing the icon..."
swiftc -O makeicon.swift -o "$B/makeicon"
"$B/makeicon" "$B/icon.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$B/icon.png" --out "$B/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$B/icon.png" --out "$B/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$B/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "3/4  Signing locally..."
codesign --force --deep -s - "$APP"

echo "4/4  Removing old Amnesia copies & installing the new one..."
pkill -f amnesia_app.py 2>/dev/null || true     # app lama (Tk)
pkill -x Amnesia 2>/dev/null || true            # semua Amnesia yang sedang jalan
pkill -x amnesia 2>/dev/null || true
sleep 1
# semua salinan Amnesia.app lama (hasil cari Spotlight + lokasi yang dikenal), kecuali hasil build ini
{ mdfind "kMDItemCFBundleIdentifier == 'com.amnesia.controlpanel'" 2>/dev/null || true
  ls -d /Applications/Amnesia.app "$HOME/Applications/Amnesia.app" "$HOME/Desktop/Amnesia.app" ../templates/Amnesia.app 2>/dev/null || true
} | sort -u | while read -r old; do
  case "$old" in "$B"/*|"") continue ;; esac
  [ -e "$old" ] || [ -L "$old" ] || continue
  echo "     removed: $old"
  rm -rf "$old"
done
rmdir ../templates 2>/dev/null || true

DEST=/Applications                               # tampil di Launchpad
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
cp -R "$APP" "$DEST/"
ln -sfn "$DEST/Amnesia.app" "$HOME/Desktop/Amnesia.app"   # pintasan di Desktop
open "$DEST/Amnesia.app"
echo "DONE: Amnesia v$(defaults read "$DEST/Amnesia.app/Contents/Info" CFBundleShortVersionString) installed in $DEST"
