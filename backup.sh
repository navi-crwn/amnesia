#!/bin/bash
# ============================================
# AMNESIA BACKUP — dipanggil app (manual atau terjadwal).
#   backup.sh [--auto]                  buat backup .7z terenkripsi lalu kirim ke tujuan
#   backup.sh --restore-vault FILE      ambil Profile Vault dari file backup (untuk Mac baru)
#   backup.sh --check-vault FILE        cek vault di file backup (folder sementara, vault di Mac ini tidak disentuh)
# Password backup selalu dibaca dari stdin (1 baris), tidak pernah lewat argumen.
# Tujuan diatur di settings.conf: BACKUP_DEST = drive | ssh | rclone | folder
#   folder = folder biasa di Mac, mis. folder Google Drive (app Google Drive for Desktop yang mengunggah)
# Kemajuan ditulis ke stderr untuk app:  PROGRESS <persen> <tahap> <n/total> <byte selesai> <byte total>
# Dibatalkan (SIGTERM dari tombol Batal): semua proses anak ikut dihentikan, file setengah jadi dihapus,
# backup.log tidak diubah (backup sebelumnya tetap tercatat), keluar dengan kode 130.
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
fail() { echo "$(date '+%F %T') FAILED: $*" > "$A/backup.log"; printf '%s\tbackupfail\t%s\n' "$(date '+%F %T')" "$AUTO" >> "$A/history.log"; notify "$(t "Backup failed" "Backup gagal"): $*"; echo "FAILED: $*" >&2; exit 1; }

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

# ---------- v5.16: cek file backup tanpa menyentuh vault yang ada ----------
# Vault dibongkar ke folder sementara, dicek isinya, lalu folder itu dihapus. Vault di Mac ini tidak diubah.
if [ "${1:-}" = "--check-vault" ]; then
    FILE="${2:-}"; [ -f "$FILE" ] || { echo "FAILED: $(t "backup file not found" "file backup tidak ditemukan")" >&2; exit 1; }
    TMPV="$(mktemp -d)"; trap 'rm -rf "$TMPV"' EXIT
    out="$(printf '%s\n' "$PW" | "$SEVENZ" x -y -bso0 -bsp0 -o"$TMPV" "$FILE" ".amnesia/vault/*" -r 2>&1)"
    V="$TMPV/.amnesia/vault"
    [ -f "$V/private.7z" ] || { echo "FAILED: $(t "wrong password, or this backup has no Profile Vault." "password salah, atau backup ini tidak berisi Profile Vault.") $out" | tail -c 300 >&2; exit 1; }
    SIZE_MB=$(du -sm "$V" 2>/dev/null | cut -f1)
    INFO="$(/usr/bin/python3 - "$V/manifest.json" 2>/dev/null <<'PY'
import json, sys
try:
    m = json.load(open(sys.argv[1]))
except Exception:
    m = {}
print(f"{m.get('time', '')}|{', '.join(m.get('apps', []))}")
PY
)"
    echo "OK: VAULT ${SIZE_MB:-0}|$INFO"
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
# vault ikut di-backup kecuali dimatikan (BACKUP_VAULT=0): tanpa salinan ini, vault yang terhapus tidak bisa kembali
WITHVAULT=0
[ "$(cfg BACKUP_VAULT)" != 0 ] && [ -d .amnesia/vault ] && { items+=(.amnesia/vault); WITHVAULT=1; }
[ ${#items[@]} -gt 0 ] || fail "$(t "nothing to back up" "tidak ada folder untuk di-backup")"

NAME="amnesia_backup_$(date +%Y%m%d_%H%M).7z"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/$NAME"
PARTIAL=""; REMOTE_CLEAN=()

# ---------- Batal: hentikan semua anak proses (7zz, cp, rsync, ssh, rclone) ----------
killtree() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do killtree "$c"; done; kill -TERM "$1" 2>/dev/null; }
on_cancel() {
    trap '' TERM INT HUP
    local c; for c in $(pgrep -P $$ 2>/dev/null); do killtree "$c"; done
    # anak yang induknya sudah mati (mis. "pkill -f backup.sh" dari Terminal) dikenali dari file sementara ini
    pkill -TERM -f "$TMP/" 2>/dev/null
    [ -n "$PARTIAL" ] && rm -f "$PARTIAL"
    [ ${#REMOTE_CLEAN[@]} -gt 0 ] && ssh "${REMOTE_CLEAN[@]}" >/dev/null 2>&1
    echo "CANCELLED" >&2
    exit 130
}
trap on_cancel TERM INT HUP

progress() { echo "PROGRESS $1 $2 $3 ${4:-0} ${5:-0}" >&2; }
fsize() { local n; n="$( { wc -c <"$1"; } 2>/dev/null | tr -d ' ')"; echo "${n:-0}"; }

# persen dari 7zz (-bsp1: angka ditimpa pakai backspace)
pct7z() {
    local chunk last=-1
    while IFS= read -r -d $'\b' chunk || [ -n "$chunk" ]; do
        if [[ "$chunk" =~ ([0-9]{1,3})% ]] && [ "${BASH_REMATCH[1]}" != "$last" ]; then
            last="${BASH_REMATCH[1]}"; progress "$last" compress 1/2
        fi
    done
}
# persen & byte dari rsync --progress (baris ditimpa pakai \r)
pctrsync() {
    local line last=-1 sec=-1 b
    while IFS= read -r -d $'\r' line || [ -n "$line" ]; do
        # dilaporkan saat persen berubah, atau tiap detik (supaya kecepatan & "masih jalan" terlihat)
        if [[ "$line" =~ ^[[:space:]]*([0-9,.]+)[[:space:]]+([0-9]{1,3})% ]] \
           && { [ "${BASH_REMATCH[2]}" != "$last" ] || [ "$SECONDS" != "$sec" ]; }; then
            last="${BASH_REMATCH[2]}"; sec="$SECONDS"; b="${BASH_REMATCH[1]//[,.]/}"; progress "$last" upload 2/2 "$b" "$TOTAL"
        fi
    done
}
# persen dari rclone --stats-one-line
pctrclone() {
    local line last
    while IFS= read -r line; do
        if [[ "$line" =~ ([0-9]{1,3})%, ]]; then        # rclone menulis 1 baris tiap detik
            last="${BASH_REMATCH[1]}"; progress "$last" upload 2/2 $((TOTAL * last / 100)) "$TOTAL"
        else
            echo "$line" >>"$TMP/up"
        fi
    done
}
# salin file sambil melaporkan ukuran yang sudah tersalin
copy_progress() {   # sumber tujuan
    PARTIAL="$2.part"
    cp "$1" "$PARTIAL" & local cpid=$!
    while kill -0 "$cpid" 2>/dev/null; do
        local d; d="$(fsize "$PARTIAL")"; progress $((d * 100 / (TOTAL > 0 ? TOTAL : 1))) copy 2/2 "$d" "$TOTAL"
        sleep 1
    done
    wait "$cpid" && mv -f "$PARTIAL" "$2" && PARTIAL=""
}

# ---------- 1/2 Kunci (kompres + enkripsi) ----------
progress 0 compress 1/2
( printf '%s\n%s\n' "$PW" "$PW" | "$SEVENZ" a -t7z -m0=lzma2 -mx=5 -mhe=on -p -bso0 -bse2 -bsp1 "$OUT" "${items[@]}" \
    '-xr!node_modules' '-xr!.DS_Store' '-xr!.tmp' 2>"$TMP/err" | pct7z
  echo "${PIPESTATUS[1]}" >"$TMP/rc" ) &
wait $!
rc="$(cat "$TMP/rc" 2>/dev/null || echo 9)"
{ [ "$rc" -le 1 ] && [ -f "$OUT" ]; } || fail "$(t "7zz failed" "7zz gagal") ($rc) $(tail -c 200 "$TMP/err")"
SHA="$(shasum -a 256 "$OUT" 2>/dev/null || sha256sum "$OUT")"; SHA="${SHA%% *}"
SIZE="$(du -m "$OUT" | cut -f1)"
TOTAL="$(fsize "$OUT")"

# ---------- 2/2 Kirim ke tujuan ----------
DEST="$(cfg BACKUP_DEST)"; DEST="${DEST:-drive}"
case "$DEST" in
    drive)
        D="$(cfg BACKUP_DRIVE)"; T="$VOLUMES/$D"
        { [ -n "$D" ] && [ -d "$T" ] && [ -w "$T" ]; } || fail "$(t "drive \"$D\" is not plugged in" "drive \"$D\" tidak terpasang")"
        copy_progress "$OUT" "$T/$NAME" || fail "$(t "couldn't copy to $D" "gagal menyalin ke $D")"
        WHERE="$T" ;;
    folder)
        D="$(cfg BACKUP_LOCAL)"; case "$D" in "~/"?*) D="$H/${D#\~/}" ;; esac
        { [ -n "$D" ] && [ -d "$(dirname "$D")" ]; } || fail "$(t "the folder \"$D\" can't be found (is the Google Drive app running?)" "folder \"$D\" tidak ditemukan (app Google Drive sudah jalan?)")"
        mkdir -p "$D" 2>/dev/null && [ -w "$D" ] || fail "$(t "can't write to \"$D\"" "tidak bisa menulis ke \"$D\"")"
        copy_progress "$OUT" "$D/$NAME" || fail "$(t "couldn't copy to $D" "gagal menyalin ke $D")"
        WHERE="$D" ;;
    ssh)
        R="$(cfg BACKUP_SSH)"; [ -n "$R" ] || fail "$(t "no server set up" "server belum diatur")"
        PORT="$(cfg BACKUP_SSH_PORT)"; case "$PORT" in ''|*[!0-9]*) PORT=22 ;; esac
        HOST="${R%%:*}"; RPATH="${R#*:}"; { [ "$RPATH" = "$R" ] || [ -z "$RPATH" ]; } && RPATH="amnesia-backup"
        # batas waktu: koneksi yang diam lebih dari ±1 menit diputus (tidak macet selamanya)
        SSHO=(-p "$PORT" -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=4
              -o StrictHostKeyChecking=accept-new)
        # buat folder + tes bisa ditulis; hasilnya path lengkap di server
        FULL="$(ssh "${SSHO[@]}" "$HOST" "mkdir -p -- $RPATH 2>/dev/null && cd -- $RPATH && touch .amnesia-write-test 2>/dev/null && rm -f .amnesia-write-test && pwd || echo AMNESIA_NOWRITE" 2>"$TMP/ssh")"
        if [ $? -ne 0 ]; then
            # pesan yang bisa dipahami, sesuai penyebabnya
            if grep -q "IDENTIFICATION HAS CHANGED\|Host key verification failed" "$TMP/ssh"; then
                fail "$(t "$HOST looks different (server reinstalled?). Open Backup and press Connect again." "$HOST terlihat berbeda (server diinstal ulang?). Buka Backup lalu tekan Hubungkan lagi.")"
            elif grep -q "Permission denied" "$TMP/ssh"; then
                fail "$(t "$HOST refused the key. Open Backup and press Connect again." "$HOST menolak kunci. Buka Backup lalu tekan Hubungkan lagi.")"
            elif grep -qi "timed out\|No route\|Could not resolve\|Connection refused" "$TMP/ssh"; then
                fail "$(t "$HOST can't be reached (offline, wrong port, or server down). Will try again later." "$HOST tidak bisa dihubungi (offline, port salah, atau server mati). Nanti dicoba lagi.")"
            else
                fail "$(t "can't connect to $HOST" "tidak bisa konek ke $HOST"): $(tail -c 150 "$TMP/ssh")"
            fi
        fi
        case "$FULL" in *AMNESIA_NOWRITE*)
            fail "$(t "the server account can't write to \"$RPATH\". Pick a folder in your home on the server, e.g. $HOST:backup (Amnesia never uses sudo)." "akun server tidak bisa menulis ke \"$RPATH\". Pilih folder di home server, mis. $HOST:backup (Amnesia tidak pernah memakai sudo).")" ;;
        esac
        FULL="$(printf '%s' "$FULL" | tail -1)"; [ -n "$FULL" ] || FULL="$RPATH"
        RS=(-t)
        RH="$(rsync --help 2>&1)"
        case "$RH" in *--timeout*) RS+=(--timeout=120) ;; esac
        case "$RH" in *--progress*) RS+=(--progress) ;; esac
        REMOTE_CLEAN=("${SSHO[@]}" "$HOST" "rm -f -- $RPATH/.$NAME.*")    # sisa upload yang terputus
        ( rsync "${RS[@]}" -e "ssh ${SSHO[*]}" "$OUT" "$HOST:$RPATH/" 2>"$TMP/up" | pctrsync
          echo "${PIPESTATUS[0]}" >"$TMP/rc" ) &
        wait $!
        [ "$(cat "$TMP/rc" 2>/dev/null)" = 0 ] || fail "$(t "upload to $HOST failed" "upload ke $HOST gagal"): $(tail -c 150 "$TMP/up")"
        REMOTE_CLEAN=()
        WHERE="$HOST:$FULL" ;;
    rclone)
        R="$(cfg BACKUP_RCLONE)"; [ -n "$R" ] || fail "$(t "no cloud set up" "cloud belum diatur")"
        command -v rclone >/dev/null || fail "$(t "rclone is not installed" "rclone belum terpasang") (brew install rclone)"
        # Dropbox: rclone menampung file per potongan 48 MB sebelum dikirim, dan potongan yang baru ditampung sudah
        # dihitung "terkirim". Akibatnya progress langsung 100% padahal upload baru mulai. Potongan 8 MB membuat
        # progress mengikuti upload yang sebenarnya. Cloud lain (OneDrive, dll.) tidak diubah.
        RX=()
        [ "$(rclone listremotes --long 2>/dev/null | awk -v r="${R%%:*}:" '$1 == r { print $2 }')" = dropbox ] \
            && RX=(--dropbox-chunk-size 8M)
        # batas waktu: koneksi yang diam 2 menit dianggap gagal, dicoba ulang maksimal 2x
        ( rclone copy "$OUT" "$R" --stats 1s --stats-one-line --stats-log-level NOTICE ${RX[@]+"${RX[@]}"} \
              --contimeout 30s --timeout 2m --retries 2 --low-level-retries 3 2>&1 >/dev/null | pctrclone
          echo "${PIPESTATUS[0]}" >"$TMP/rc" ) &
        wait $!
        [ "$(cat "$TMP/rc" 2>/dev/null)" = 0 ] || fail "$(t "upload to $R failed" "upload ke $R gagal"): $(grep -i "error\|fail" "$TMP/up" 2>/dev/null | tail -1 | tail -c 150)"
        WHERE="$R" ;;
    *) fail "$(t "unknown backup destination" "tujuan backup tidak dikenal"): $DEST" ;;
esac
trap '' TERM INT HUP          # sudah terkirim: catatan di bawah tidak boleh terpotong

echo "$SHA  $WHERE/$NAME" >> "$A/backup_checksums.txt"
TO="$(t to ke)"
echo "$(date '+%F %T') OK: $NAME (${SIZE} MB) $TO $WHERE" > "$A/backup.log"
printf '%s\tbackup\t%s %s %s\n' "$(date '+%F %T')" "$AUTO" "$WITHVAULT" "$SIZE" >> "$A/history.log"   # halaman Riwayat
touch "$A/backup.ok"                                  # dipakai app untuk jadwal backup
[ "$WITHVAULT" = 1 ] && touch "$A/backup.vault.ok"   # app: vault sudah pernah ikut backup
notify "$(t "Backup done" "Backup selesai"): ${SIZE} MB $TO $WHERE"
echo "OK: $NAME (${SIZE} MB) $TO $WHERE"
