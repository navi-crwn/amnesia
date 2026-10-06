#!/bin/bash
# ============================================
# AMNESIA BACKUP — dipanggil app (manual atau terjadwal).
#   backup.sh [--auto]                  buat backup .7z terenkripsi lalu kirim ke tujuan
#   backup.sh --restore-vault FILE      ambil Profile Vault dari file backup (untuk Mac baru)
# Password backup selalu dibaca dari stdin (1 baris), tidak pernah lewat argumen.
# Tujuan diatur di settings.conf: BACKUP_DEST = drive | ssh | rclone
# ============================================
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
H="${AMNESIA_HOME:-$HOME}"; A="$H/.amnesia"; CONF="$A/settings.conf"
SEVENZ="${AMNESIA_7Z:-/opt/homebrew/bin/7zz}"; VOLUMES="${AMNESIA_VOLUMES:-/Volumes}"
AUTO=0; [ "${1:-}" = "--auto" ] && AUTO=1

cfg() { grep "^$1=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-; }
notify() { [ "$AUTO" = 1 ] && osascript -e "display notification \"$1\" with title \"Amnesia Backup\"" 2>/dev/null; true; }
fail() { echo "$(date '+%F %T') GAGAL: $*" > "$A/backup.log"; notify "Backup gagal: $*"; echo "GAGAL: $*" >&2; exit 1; }

IFS= read -r PW || true
[ -n "$PW" ] || fail "password backup kosong"
[ -x "$SEVENZ" ] || fail "7zz tidak ditemukan (brew install sevenzip)"

# ---------- Ambil vault dari file backup (Mac baru) ----------
if [ "${1:-}" = "--restore-vault" ]; then
    FILE="${2:-}"; [ -f "$FILE" ] || { echo "GAGAL: file backup tidak ditemukan" >&2; exit 1; }
    [ -f "$A/vault/private.7z" ] && { echo "GAGAL: vault sudah ada di Mac ini. Hapus dulu kalau mau diganti." >&2; exit 1; }
    out="$(printf '%s\n' "$PW" | "$SEVENZ" x -y -bso0 -bsp0 -o"$H" "$FILE" ".amnesia/vault/*" -r 2>&1)"
    [ -f "$A/vault/private.7z" ] || { echo "GAGAL: password salah, atau backup ini tidak berisi Profile Vault. $out" | tail -c 300 >&2; exit 1; }
    echo "OK: vault dipulihkan"
    exit 0
fi

# ---------- Kumpulkan yang di-backup ----------
cd "$H" || fail "folder home tidak ada"
items=()
IFS=',' read -ra F <<< "$(cfg BACKUP_FOLDERS || true)"
[ ${#F[@]} -gt 0 ] || F=(Keep)
for f in "${F[@]}"; do [ -n "$f" ] && [ -e "$f" ] && items+=("$f"); done
[ "$(cfg BACKUP_VAULT)" = 1 ] && [ -d .amnesia/vault ] && items+=(.amnesia/vault)
[ ${#items[@]} -gt 0 ] || fail "tidak ada folder untuk di-backup"

NAME="amnesia_backup_$(date +%Y%m%d_%H%M).7z"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/$NAME"
printf '%s\n%s\n' "$PW" "$PW" | "$SEVENZ" a -t7z -m0=lzma2 -mx=5 -mhe=on -p -bso0 -bsp0 "$OUT" "${items[@]}" \
    '-xr!node_modules' '-xr!.DS_Store' '-xr!.tmp' >/dev/null 2>"$TMP/err"
rc=$?
{ [ $rc -le 1 ] && [ -f "$OUT" ]; } || fail "7zz gagal (kode $rc) $(tail -c 200 "$TMP/err")"
SHA="$(shasum -a 256 "$OUT" 2>/dev/null || sha256sum "$OUT")"; SHA="${SHA%% *}"
SIZE="$(du -m "$OUT" | cut -f1)"

# ---------- Kirim ke tujuan ----------
DEST="$(cfg BACKUP_DEST)"; DEST="${DEST:-drive}"
case "$DEST" in
    drive)
        D="$(cfg BACKUP_DRIVE)"; T="$VOLUMES/$D"
        { [ -n "$D" ] && [ -d "$T" ] && [ -w "$T" ]; } || fail "drive \"$D\" tidak terpasang"
        cp "$OUT" "$T/" || fail "gagal menyalin ke $D"
        WHERE="$T" ;;
    ssh)
        R="$(cfg BACKUP_SSH)"; [ -n "$R" ] || fail "server belum diatur"
        HOST="${R%%:*}"; RPATH="${R#*:}"; [ "$RPATH" = "$R" ] && RPATH="amnesia-backup"
        SSHO=(-o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new)
        ssh "${SSHO[@]}" "$HOST" "mkdir -p -- $RPATH" || fail "tidak bisa konek ke $HOST (cek kunci SSH)"
        rsync -t --partial -e "ssh ${SSHO[*]}" "$OUT" "$HOST:$RPATH/" || fail "upload ke $HOST gagal"
        WHERE="$HOST:$RPATH" ;;
    rclone)
        R="$(cfg BACKUP_RCLONE)"; [ -n "$R" ] || fail "cloud belum diatur"
        command -v rclone >/dev/null || fail "rclone belum terpasang (brew install rclone)"
        rclone copy "$OUT" "$R" || fail "upload ke $R gagal"
        WHERE="$R" ;;
    *) fail "tujuan backup tidak dikenal: $DEST" ;;
esac

echo "$SHA  $WHERE/$NAME" >> "$A/backup_checksums.txt"
echo "$(date '+%F %T') OK: $NAME (${SIZE} MB) ke $WHERE" > "$A/backup.log"
touch "$A/backup.ok"                                  # dipakai app untuk jadwal backup
notify "Backup selesai: ${SIZE} MB ke $WHERE"
echo "OK: $NAME (${SIZE} MB) ke $WHERE"
