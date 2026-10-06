#!/bin/bash
# ============================================
# AMNESIA BACKUP — dipanggil app (manual atau terjadwal).
#   backup.sh [--auto]                  buat backup .7z terenkripsi lalu kirim ke tujuan
#   backup.sh --restore-vault FILE      ambil Profile Vault dari file backup (untuk Mac baru)
# Password backup selalu dibaca dari stdin (1 baris), tidak pernah lewat argumen.
# Tujuan diatur di settings.conf: BACKUP_DEST = drive | ssh | rclone
# BACKUP_FOLDERS: daftar dipisah koma. "@keep" = folder Keep, lainnya relatif ke home atau path lengkap.
# ============================================
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
H="${AMNESIA_HOME:-$HOME}"; A="$H/.amnesia"; CONF="$A/settings.conf"
SEVENZ="${AMNESIA_7Z:-}"   # 7-Zip bawaan app dulu, lalu Homebrew
if [ -z "$SEVENZ" ]; then
    for SEVENZ in "$A/bin/7zz" /opt/homebrew/bin/7zz /usr/local/bin/7zz; do [ -x "$SEVENZ" ] && break; done
fi; VOLUMES="${AMNESIA_VOLUMES:-/Volumes}"
AUTO=0; [ "${1:-}" = "--auto" ] && AUTO=1

cfg() { grep "^$1=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-; }
t() { if [ "$(cfg LANG)" = id ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }   # English / Indonesia
notify() { [ "$AUTO" = 1 ] && osascript -e "display notification \"$1\" with title \"Amnesia Backup\"" 2>/dev/null; true; }
fail() { echo "$(date '+%F %T') FAILED: $*" > "$A/backup.log"; notify "$(t "Backup failed" "Backup gagal"): $*"; echo "FAILED: $*" >&2; exit 1; }

IFS= read -r PW || true
[ -n "$PW" ] || fail "$(t "backup password is empty" "password backup kosong")"
[ -x "$SEVENZ" ] || fail "$(t "7zz not found" "7zz tidak ditemukan") (brew install sevenzip)"

# ---------- Ambil vault dari file backup (Mac baru) ----------
if [ "${1:-}" = "--restore-vault" ]; then
    FILE="${2:-}"; [ -f "$FILE" ] || { echo "FAILED: $(t "backup file not found" "file backup tidak ditemukan")" >&2; exit 1; }
    [ -f "$A/vault/private.7z" ] && { echo "FAILED: $(t "this Mac already has a vault. Delete it first if you want to replace it." "vault sudah ada di Mac ini. Hapus dulu kalau mau diganti.")" >&2; exit 1; }
    out="$(printf '%s\n' "$PW" | "$SEVENZ" x -y -bso0 -bsp0 -o"$H" "$FILE" ".amnesia/vault/*" -r 2>&1)"
    [ -f "$A/vault/private.7z" ] || { echo "FAILED: $(t "wrong password, or this backup has no Profile Vault." "password salah, atau backup ini tidak berisi Profile Vault.") $out" | tail -c 300 >&2; exit 1; }
    echo "OK: $(t "vault restored" "vault dipulihkan")"
    exit 0
fi

# ---------- Kumpulkan yang di-backup ----------
cd "$H" || fail "$(t "home folder not found" "folder home tidak ada")"
# folder Keep pilihan user (KEEP_DIR, default ~/Keep)
KD="$(cfg KEEP_DIR)"
case "$KD" in "~/"?*) KD="$H/${KD#\~/}" ;; /?*) ;; *) KD="$H/Keep" ;; esac
items=()
IFS=',' read -ra F <<< "$(cfg BACKUP_FOLDERS || true)"
[ ${#F[@]} -gt 0 ] || F=(@keep)
for f in "${F[@]}"; do
    case "$f" in @keep) f="${KD%/}" ;; "~/"?*) f="${f#\~/}" ;; esac   # selain itu: relatif ke home, atau path lengkap
    [ -n "$f" ] && [ -e "$f" ] && items+=("$f")
done
[ "$(cfg BACKUP_VAULT)" = 1 ] && [ -d .amnesia/vault ] && items+=(.amnesia/vault)
[ ${#items[@]} -gt 0 ] || fail "$(t "nothing to back up" "tidak ada folder untuk di-backup")"

NAME="amnesia_backup_$(date +%Y%m%d_%H%M).7z"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/$NAME"
printf '%s\n%s\n' "$PW" "$PW" | "$SEVENZ" a -t7z -m0=lzma2 -mx=5 -mhe=on -p -bso0 -bsp0 "$OUT" "${items[@]}" \
    '-xr!node_modules' '-xr!.DS_Store' '-xr!.tmp' >/dev/null 2>"$TMP/err"
rc=$?
{ [ $rc -le 1 ] && [ -f "$OUT" ]; } || fail "$(t "7zz failed" "7zz gagal") ($rc) $(tail -c 200 "$TMP/err")"
SHA="$(shasum -a 256 "$OUT" 2>/dev/null || sha256sum "$OUT")"; SHA="${SHA%% *}"
SIZE="$(du -m "$OUT" | cut -f1)"

# ---------- Kirim ke tujuan ----------
DEST="$(cfg BACKUP_DEST)"; DEST="${DEST:-drive}"
case "$DEST" in
    drive)
        D="$(cfg BACKUP_DRIVE)"; T="$VOLUMES/$D"
        { [ -n "$D" ] && [ -d "$T" ] && [ -w "$T" ]; } || fail "$(t "drive \"$D\" is not plugged in" "drive \"$D\" tidak terpasang")"
        cp "$OUT" "$T/" || fail "$(t "couldn't copy to $D" "gagal menyalin ke $D")"
        WHERE="$T" ;;
    ssh)
        R="$(cfg BACKUP_SSH)"; [ -n "$R" ] || fail "$(t "no server set up" "server belum diatur")"
        HOST="${R%%:*}"; RPATH="${R#*:}"; { [ "$RPATH" = "$R" ] || [ -z "$RPATH" ]; } && RPATH="amnesia-backup"
        SSHO=(-o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new)
        if ! ssh "${SSHO[@]}" "$HOST" "mkdir -p -- $RPATH" 2>"$TMP/ssh"; then
            # pesan yang bisa dipahami, sesuai penyebabnya
            if grep -q "IDENTIFICATION HAS CHANGED\|Host key verification failed" "$TMP/ssh"; then
                fail "$(t "$HOST looks different (server reinstalled?). Open Backup and press Connect again." "$HOST terlihat berbeda (server diinstal ulang?). Buka Backup lalu tekan Hubungkan lagi.")"
            elif grep -q "Permission denied" "$TMP/ssh"; then
                fail "$(t "$HOST refused the key. Open Backup and press Connect again." "$HOST menolak kunci. Buka Backup lalu tekan Hubungkan lagi.")"
            elif grep -qi "timed out\|No route\|Could not resolve\|Connection refused" "$TMP/ssh"; then
                fail "$(t "$HOST can't be reached (offline or server down). Will try again later." "$HOST tidak bisa dihubungi (offline atau server mati). Nanti dicoba lagi.")"
            else
                fail "$(t "can't connect to $HOST" "tidak bisa konek ke $HOST"): $(tail -c 150 "$TMP/ssh")"
            fi
        fi
        rsync -t --partial -e "ssh ${SSHO[*]}" "$OUT" "$HOST:$RPATH/" || fail "$(t "upload to $HOST failed" "upload ke $HOST gagal")"
        WHERE="$HOST:$RPATH" ;;
    rclone)
        R="$(cfg BACKUP_RCLONE)"; [ -n "$R" ] || fail "$(t "no cloud set up" "cloud belum diatur")"
        command -v rclone >/dev/null || fail "$(t "rclone is not installed" "rclone belum terpasang") (brew install rclone)"
        rclone copy "$OUT" "$R" || fail "$(t "upload to $R failed" "upload ke $R gagal")"
        WHERE="$R" ;;
    *) fail "$(t "unknown backup destination" "tujuan backup tidak dikenal"): $DEST" ;;
esac

echo "$SHA  $WHERE/$NAME" >> "$A/backup_checksums.txt"
TO="$(t to ke)"
echo "$(date '+%F %T') OK: $NAME (${SIZE} MB) $TO $WHERE" > "$A/backup.log"
touch "$A/backup.ok"                                  # dipakai app untuk jadwal backup
notify "$(t "Backup done" "Backup selesai"): ${SIZE} MB $TO $WHERE"
echo "OK: $NAME (${SIZE} MB) $TO $WHERE"
