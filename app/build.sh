#!/bin/bash
# Build app Amnesia (SwiftUI) tanpa Xcode — cukup Command Line Tools.
# Jalankan:  bash ~/.amnesia/app/build.sh
set -euo pipefail
cd "$(dirname "$0")"
command -v swiftc >/dev/null || { echo "Command Line Tools are missing. Run: xcode-select --install"; exit 1; }

B="$PWD/build"; APP="$B/Amnesia.app"; ARCH="$(uname -m)"
rm -rf "$B"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$B/AppIcon.iconset"

[ -f ../keep.conf ] || cp ../keep.example.conf ../keep.conf   # Keep List pertama dari contoh

# Tanda tangan lokal yang SAMA di setiap build. macOS mengenali app dari tanda tangannya: dengan tanda tangan
# "ad-hoc" (-) setiap build dianggap app baru, jadi izin Full Disk Access hilang setiap update.
# Sertifikat dibuat sekali di Keychain login kamu (bukan dari Apple, jadi "Open Anyway" tetap perlu di Mac lain).
# Pembersihan Amnesia hanya menghapus password di Keychain, bukan sertifikat, jadi sertifikat ini tetap ada.
SIGN_NAME="Amnesia Local Signing"
KC="$HOME/Library/Keychains/login.keychain-db"
sign_hash() { { security find-certificate -c "$SIGN_NAME" -Z "$KC" 2>/dev/null | awk '/SHA-1/ { print $NF; exit }'; } || true; }
make_cert() {
  local d r; d="$(mktemp -d)"
  cat > "$d/cfg" <<CFG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $SIGN_NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CFG
  # "amnesia" di bawah hanya kunci sementara untuk file .p12 ini (langsung dihapus), bukan password kamu
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$d/cfg" \
      -keyout "$d/key.pem" -out "$d/cert.pem" >/dev/null 2>&1 \
    && /usr/bin/openssl pkcs12 -export -inkey "$d/key.pem" -in "$d/cert.pem" -name "$SIGN_NAME" \
      -passout pass:amnesia -out "$d/id.p12" >/dev/null 2>&1 \
    && security import "$d/id.p12" -k "$KC" -P amnesia -T /usr/bin/codesign >/dev/null 2>&1
  r=$?; rm -rf "$d"; return $r
}
SIGN="$(sign_hash)"
if [ -z "$SIGN" ]; then
  echo "0/4  Making a local signing certificate (once, in your login Keychain)..."
  make_cert && SIGN="$(sign_hash)"
fi
# Tanda tangani (dengan sertifikat tetap; kalau gagal, ad-hoc seperti dulu)
sign() {
  if [ -n "$SIGN" ] && codesign --force --deep -s "$SIGN" "$1" 2>/dev/null; then return 0; fi
  [ -n "$SIGN" ] && { echo "     (local certificate didn't work, signing ad-hoc)"; SIGN=""; }
  codesign --force --deep -s - "$1"
}
echo "1/4  Compile app..."
swiftc -swift-version 5 -O -parse-as-library -target "$ARCH-apple-macos15.0" Amnesia.swift -o "$APP/Contents/MacOS/Amnesia"
cp Info.plist "$APP/Contents/Info.plist"

# Mesin Amnesia ikut di dalam app, jadi app dari GitHub Releases langsung bisa dipakai
R="$APP/Contents/Resources"; mkdir -p "$R/engine" "$R/bin"
cp ../clean.sh ../agent.sh ../vault.py ../backup.sh ../uninstall.sh ../keep.example.conf "$R/engine/"
echo "     getting 7-Zip..."
SZ="$B/7zip"; mkdir -p "$SZ"
if curl -fsSL https://github.com/ip7z/7zip/releases/download/24.09/7z2409-mac.tar.xz -o "$SZ/7z.tar.xz" \
   && tar -xf "$SZ/7z.tar.xz" -C "$SZ" 7zz License.txt; then
  cp "$SZ/7zz" "$R/bin/7zz"; cp "$SZ/License.txt" "$R/bin/7-Zip-License.txt"
elif [ -x /opt/homebrew/bin/7zz ]; then
  cp /opt/homebrew/bin/7zz "$R/bin/7zz"
else
  echo "     (no 7-Zip bundled: install it with  brew install sevenzip)"
fi
[ -f "$R/bin/7zz" ] && sign "$R/bin/7zz"

echo "2/4  Drawing the icon..."
swiftc -O makeicon.swift -o "$B/makeicon"
"$B/makeicon" "$B/icon.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$B/icon.png" --out "$B/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$B/icon.png" --out "$B/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$B/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "3/4  Signing locally..."
sign "$APP"
if [ -n "$SIGN" ]; then
  echo "     signed with \"$SIGN_NAME\": Full Disk Access stays on after updates"
else
  echo "     signed ad-hoc: after each update, remove Amnesia from Full Disk Access (-), add it again (+), then reopen"
fi

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
