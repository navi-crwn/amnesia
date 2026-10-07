#!/bin/bash
# Bikin screenshot app untuk README & website, otomatis (English + Indonesia, terang + gelap).
# Aman: app dijalankan dengan HOME PALSU berisi data contoh. Home kamu, vault kamu dan Keychain tidak disentuh,
# dan tidak ada data pribadi yang ikut terfoto.
#   bash ~/.amnesia/app/screenshots.sh        -> hasil di ~/.amnesia/docs/screens/en|id/*.png
set -u
cd "$(dirname "$0")/.."
OUT="$PWD/docs/screens"
APPBIN=""
for a in /Applications/Amnesia.app "$HOME/Applications/Amnesia.app" app/build/Amnesia.app; do
  [ -x "$a/Contents/MacOS/Amnesia" ] && { APPBIN="$a/Contents/MacOS/Amnesia"; break; }
done
[ -n "$APPBIN" ] || { echo "Amnesia.app not found. Run app/build.sh first."; exit 0; }

# v5.16: salinan KHUSUS screenshot ("Amnesia Shots", id com.amnesia.shots). Salinan ini tidak bisa membersihkan,
# tidak bisa mengubah LaunchAgent, Keychain atau vault, dan hanya mau jalan dengan --shots di home palsu.
# Izin Screen Recording cukup diberikan ke salinan ini (bukan ke Amnesia asli), supaya hasilnya HD seperti aslinya.
SRC="${APPBIN%/Contents/MacOS/Amnesia}"
SHOTS_APP="$PWD/app/shots/Amnesia Shots.app"
rm -rf "$SHOTS_APP"; mkdir -p "$(dirname "$SHOTS_APP")"
ditto "$SRC" "$SHOTS_APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.amnesia.shots" "$SHOTS_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName 'Amnesia Shots'" "$SHOTS_APP/Contents/Info.plist" 2>/dev/null || true
SIGN="$(security find-certificate -c "Amnesia Local Signing" -Z "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null | awk '/SHA-1/ { print $NF; exit }')"
codesign --force --deep -s "${SIGN:--}" "$SHOTS_APP" 2>/dev/null || codesign --force --deep -s - "$SHOTS_APP"
APPBIN="$SHOTS_APP/Contents/MacOS/Amnesia"

D="$(mktemp -d)/home"; trap 'rm -rf "$(dirname "$D")"' EXIT
A="$D/.amnesia"
mkdir -p "$A" "$D/Keep" "$D/Desktop" "$D/Downloads" "$D/Documents" "$D/Library/Preferences"
cp clean.sh agent.sh vault.py backup.sh keep.example.conf "$A/"
cp keep.example.conf "$A/keep.conf"
[ -x "$HOME/.amnesia/bin/7zz" ] && { mkdir -p "$A/bin"; cp "$HOME/.amnesia/bin/7zz" "$A/bin/"; }
cat > "$A/settings.conf" <<CONF
ONBOARDED=1
TERMS=1
KEEP_DIR=~/Keep
BACKUP_DEST=ssh
BACKUP_SSH=user@remoteserv.er:backup
BACKUP_FOLDERS=@keep,Documents,Desktop
BACKUP_SCHEDULE=daily
BACKUP_VAULT=1
CONF
echo "$(date '+%F %T') logout: 1284 items wiped" > "$A/clean.log"
# riwayat contoh (halaman Riwayat)
Y="$(date -v-1d '+%F')"; N="$(date '+%F')"
printf '%s\n' "$Y 09:02:11	clean	login 12" "$Y 09:10:40	restore	Chrome, Claude, WhatsApp" \
  "$Y 18:31:05	backup	1 1 214" "$Y 22:15:30	snapshot	auto:Chrome, Claude" "$Y 22:15:58	clean	logout 1284" \
  "$N 08:30:12	clean	login 9" "$N 12:05:44	snapshot	Chrome, Claude, WhatsApp" "$N 12:06:20	clean	logout 1302" \
  "$N 12:07:31	clean	login 0" > "$A/history.log"
echo "$(date '+%F %T') OK: amnesia_backup_$(date +%Y%m%d)_1830.7z (214 MB) to user@remoteserv.er:backup" > "$A/backup.log"
mk() { mkdir -p "$D/$(dirname "$1")"; echo demo > "$D/$1"; }
# data contoh (supaya vault & "yang akan dihapus" ada isinya)
mk "Library/Application Support/Google/Chrome/Default/Preferences"
mk "Library/Application Support/Claude/config.json"
mk "Library/Containers/net.whatsapp.WhatsApp/Data/x"
mk ".claude/settings.json"; mk ".config/gh/hosts.yml"; mk ".gemini/settings.json"
mk "Desktop/notes from today.txt"; mk "Desktop/screenshot 1.png"; mk "Downloads/invoice.pdf"
mk "Downloads/setup.dmg"; mk "Documents/draft.docx"; mk "Keep/project plan.md"
mk "Library/Caches/com.example.app/cache.db"; mk ".zsh_history"; mk "Library/Cookies/Cookies.binarycookies"
# app yang terpasang dapat folder data contoh (ukuran acak), supaya halaman "Apa yang disimpan?" terisi
# tanpa membaca data asli kamu
for app in /Applications/*.app; do
  bid="$(defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null)" || continue
  case "$bid" in com.apple.*|com.amnesia.*|"") continue ;; esac
  n="$(basename "$app" .app)"; dd="$D/Library/Application Support/$n"
  mkdir -p "$dd" && head -c $((RANDOM * 40)) /dev/zero > "$dd/data" 2>/dev/null
  echo demo > "$D/Library/Preferences/$bid.plist"
done
PY=/opt/homebrew/bin/python3; [ -x "$PY" ] || PY=/usr/bin/python3
printf 'demo-password-123\n\n' | AMNESIA_HOME="$D" "$PY" "$A/vault.py" create >/dev/null 2>&1
AMNESIA_HOME="$D" "$PY" "$A/vault.py" snapshot >/dev/null 2>&1

echo "Taking screenshots (about 1 minute, a Dock icon may blink)..."
mkdir -p "$OUT"
# v5.17: screenshot halaman-panjang lama tidak dibuat lagi (lebih tinggi dari jendela asli); hapus sisa buatan script ini
rm -f "$OUT"/en/*-full.png "$OUT"/id/*-full.png
LOG="$HOME/.amnesia/shots.log"; : > "$LOG"
for L in en id; do                   # 1 bahasa per jalan: kalau satu macet, yang lain tetap jadi
  AMNESIA_HOME="$D" "$APPBIN" --shots "$OUT" --lang "$L" >>"$LOG" 2>&1 &
  PID=$!
  for _ in $(seq 1 300); do kill -0 $PID 2>/dev/null || break; sleep 1; done
  kill -0 $PID 2>/dev/null && { echo "shots: $L timed out" >>"$LOG"; kill $PID 2>/dev/null; }
  wait $PID 2>/dev/null; echo "shots: $L exit code $?" >>"$LOG"
done
N=$(ls "$OUT"/en/*.png "$OUT"/id/*.png 2>/dev/null | wc -l | tr -d ' ')
echo "Done: $N screenshots in docs/screens/en and docs/screens/id (log: ~/.amnesia/shots.log)"
if grep -q "no screen recording permission" "$LOG"; then
  echo
  echo "Tip: for screenshots that look exactly like the app (HD, glass effects):"
  echo "  System Settings > Privacy & Security > Screen & System Audio Recording > switch on \"Terminal\""
  echo "  (the app you run this script from), choose Quit & Reopen, then run this script again:"
  echo "  bash ~/.amnesia/app/screenshots.sh"
  echo "  Amnesia itself never gets this permission. You can switch Terminal off again afterwards."
fi
exit 0
