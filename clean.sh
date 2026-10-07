#!/bin/bash
# ============================================
# AMNESIA CLEAN v4 — hapus semua jejak sesi
# Dipakai agent.sh saat LOGOUT/RESTART/SHUTDOWN, lalu dicek ulang saat LOGIN.
#
#   clean.sh logout|login|now [--dry-run]
#   --dry-run  : hanya tampilkan apa yang AKAN dihapus, tidak menghapus apa pun
#
# Yang dilindungi: folder Keep (KEEP_DIR di settings.conf, default ~/Keep), ~/.amnesia,
# isi keep.conf, file sistem Apple.
# (Kompatibel bash 3.2 bawaan macOS.)
# ============================================
set -u
shopt -s nullglob dotglob

H="${AMNESIA_HOME:-$HOME}"   # AMNESIA_HOME hanya untuk tes
A="$H/.amnesia"
# Bahasa pesan log (English / Indonesia), dipilih di Pengaturan app
LANGX="$(grep '^LANG=' "$A/settings.conf" 2>/dev/null | tail -1 | cut -d= -f2)"
t() { if [ "$LANGX" = id ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
# Folder Keep: bisa di mana saja dengan nama apa saja (Pengaturan app). "~/" = folder home.
KD="$(grep '^KEEP_DIR=' "$A/settings.conf" 2>/dev/null | tail -1 | cut -d= -f2-)"
case "$KD" in "~/"?*) KD="$H/${KD#\~/}" ;; /?*) ;; *) KD="$H/Keep" ;; esac
KD="${KD%/}"
case "$KD" in "$H"|"$H/.amnesia"|"$H/.amnesia/"*|"$H/.Trash"|"$H/.Trash/"*) KD="$H/Keep" ;; esac
KREL=""; case "$KD" in "$H"/?*) KREL="${KD#"$H"/}" ;; esac      # kosong = di luar home (tidak pernah disentuh)
MODE="now"; DRY=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY=1 ;;
        logout|login|now) MODE="$arg" ;;
    esac
done
COUNT=0
TRASHROOT="$H/.amnesia-trash"   # v5.14: tempat sampah Amnesia (di disk yang sama, jadi memindah = instan)
TRASH=""
TRACE="$A/trace.log"
# catatan langkah: jam + nama langkah saja (tanpa nama file), untuk melacak logout yang macet
trace() { [ "$DRY" = 1 ] || echo "$(date '+%F %T') clean $MODE: $*" >> "$TRACE" 2>/dev/null; }
# limit <detik> <perintah...>: perintah yang macet dihentikan, supaya logout tidak tertahan
limit() {
    local s=$1 pid w rc; shift
    "$@" & pid=$!
    ( sleep "$s"; kill -9 "$pid" 2>/dev/null ) >/dev/null 2>&1 &
    w=$!
    wait "$pid" 2>/dev/null; rc=$?
    kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
    return $rc
}

# ---------- Pause 1 sesi ----------
# Jeda dibuat dari GUI (file pause_once). Logout berikutnya + login berikutnya dilewati,
# lalu penanda dihapus sehingga siklus sesudahnya bersih lagi.
if [ "$DRY" = 0 ] && [ -f "$TRACE" ] && [ "$(wc -l < "$TRACE")" -gt 600 ]; then
    tail -n 400 "$TRACE" > "$TRACE.tmp" 2>/dev/null && mv "$TRACE.tmp" "$TRACE"
fi
trace "start"
if [ "$DRY" = 0 ] && [ -f "$A/pause_once" ]; then
    if [ "$MODE" = "login" ]; then
        rm -f "$A/pause_once"
        echo "$(date '+%F %T') login: $(t "paused (marker removed)" "dijeda (penanda dihapus)")" > "$A/clean.log"
        printf '%s\tpaused\tlogin\n' "$(date '+%F %T')" >> "$A/history.log"
        exit 0
    elif [ "$MODE" = "logout" ]; then
        echo "$(date '+%F %T') logout: $(t paused dijeda)" > "$A/clean.log"
        printf '%s\tpaused\tlogout\n' "$(date '+%F %T')" >> "$A/history.log"
        exit 0
    fi
fi

# ---------- Daftar yang dilindungi ----------
KEEP=(
    ".amnesia"
    ".amnesia-trash"
    # Sistem Apple (jangan disentuh)
    "Library/Application Support/com.apple.*"
    "Library/Application Support/Apple"
    "Library/Application Support/CloudDocs"
    "Library/Application Support/CallHistory*"
    "Library/Application Support/Knowledge*"
    "Library/Preferences/com.apple.*"
    "Library/Preferences/.GlobalPreferences*"
    "Library/Preferences/loginwindow.plist"
    "Library/Preferences/ByHost/com.apple.*"
    "Library/Preferences/ByHost/.GlobalPreferences*"
    "Public/Drop Box"
)
KC_KEEP=(
    "com.apple.*" "AirPort" "AirPlay Server Identity" "Apple Persistent State Encryption"
    "AppleIDClientIdentifier" "BluetoothGlobal" "BluetoothLE" "ProtectedCloudStorage"
    "TelephonyUtilities" "WiFiAnalytics" "MetadataKeychain" "iCloud"
)
# folder Keep (karakter * ? [ ] di namanya dibaca apa adanya, bukan pola)
[ -n "$KREL" ] && KEEP+=("$(printf '%s' "$KREL" | sed 's/[][*?\\]/\\&/g')")
KEEPF="$A/keep.conf"; [ -f "$KEEPF" ] || KEEPF="$A/keep.example.conf"   # keep.conf = milik pribadi (tidak di GitHub)
if [ -f "$KEEPF" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
        case "$line" in
            ""|"#"*) ;;
            keychain:*) KC_KEEP+=("${line#keychain:}") ;;
            *) KEEP+=("${line#\~/}") ;;
        esac
    done < "$KEEPF"
fi

# path (relatif ke home) cocok dengan salah satu pola keep?
kept() {
    local p
    for p in "${KEEP[@]}"; do [[ "$1" == $p ]] && return 0; done
    return 1
}

# ada pola keep DI DALAM path ini? -> masuk ke dalam, jangan hapus foldernya utuh
# (tanpa program luar: dipanggil ribuan kali, jadi harus cepat)
has_kept_inside() {
    local p pre ps i s="${1//[!\/]/}"
    local n=${#s}
    for p in "${KEEP[@]}"; do
        ps="${p//[!\/]/}"
        [ ${#ps} -gt $n ] || continue          # pola harus lebih dalam dari path ini
        pre="$p"
        for ((i = ${#ps}; i > n; i--)); do pre="${pre%/*}"; done
        [[ "$1" == $pre ]] && return 0
    done
    return 1
}

remove() {
    COUNT=$((COUNT + 1))
    if [ "$DRY" = 1 ]; then echo "HAPUS  ~/$1"; return 0; fi
    # v5.14: dipindah ke tempat sampah Amnesia (instan, berapa pun ukurannya), lalu dihapus pelan di
    # background setelah login. Kalau pindah gagal, langsung dihapus seperti dulu.
    if [ -z "$TRASH" ]; then
        TRASH="$TRASHROOT/$(date +%Y%m%d-%H%M%S)-$$"
        mkdir -p "$TRASH" 2>/dev/null && chmod 700 "$TRASHROOT" 2>/dev/null
        touch "$TRASHROOT/.metadata_never_index" 2>/dev/null      # Spotlight tidak mengindeks isinya
    fi
    mkdir "$TRASH/$COUNT" 2>/dev/null && mv "$H/$1" "$TRASH/$COUNT/" 2>/dev/null && return 0
    rm -rf "$H/$1" 2>/dev/null
}

# isi tempat sampah dihapus di background dengan prioritas rendah, supaya Mac tidak terasa lambat
purge_trash() {
    [ -d "$TRASHROOT" ] || return 0
    if [ -n "${AMNESIA_HOME:-}" ]; then rm -rf "$TRASHROOT"; return 0; fi    # mode tes: langsung
    nohup /usr/bin/nice -n 20 /usr/sbin/taskpolicy -b /bin/rm -rf "$TRASHROOT" >/dev/null 2>&1 &
}

# hapus satu path, menghormati keep list
wipe() {
    local rel="$1" c
    [ -e "$H/$rel" ] || [ -L "$H/$rel" ] || return 0
    kept "$rel" && return 0
    if [ -d "$H/$rel" ] && [ ! -L "$H/$rel" ] && has_kept_inside "$rel"; then
        for c in "$H/$rel"/*; do wipe "$rel/${c##*/}"; done
        return 0
    fi
    remove "$rel"
}

# hapus isi folder, foldernya tetap ada
wipe_inside() {
    local c
    [ -d "$H/$1" ] || return 0
    for c in "$H/$1"/*; do wipe "$1/${c##*/}"; done
}

# hapus walau termasuk pola Apple (jejak "recent" milik sistem)
force() {
    [ -e "$H/$1" ] || [ -L "$H/$1" ] || return 0
    remove "$1"
}

kc_kept() {
    local p
    for p in "${KC_KEEP[@]}"; do [[ "$1" == $p ]] && return 0; done
    return 1
}

clean_keychain() {
    [ -n "${AMNESIA_HOME:-}" ] && return 0      # mode tes: jangan sentuh Keychain asli
    command -v security >/dev/null || return 0
    local dump name i
    dump=$(limit 20 security dump-keychain 2>/dev/null) || return 0
    # generic password (svce) dan internet password (srvr)
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        kc_kept "$name" && continue
        COUNT=$((COUNT + 1))
        if [ "$DRY" = 1 ]; then echo "KEYCHAIN  $name"; continue; fi
        # satu panggilan hanya hapus 1 item; ulangi sampai habis
        for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
            limit 5 security delete-generic-password -s "$name" >/dev/null 2>&1 || break
        done
    done < <(printf '%s\n' "$dump" | sed -n 's/^ *"svce"<blob>="\(.*\)"$/\1/p' | sort -u)
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        kc_kept "$name" && continue
        COUNT=$((COUNT + 1))
        if [ "$DRY" = 1 ]; then echo "KEYCHAIN-WEB  $name"; continue; fi
        for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
            limit 5 security delete-internet-password -s "$name" >/dev/null 2>&1 || break
        done
    done < <(printf '%s\n' "$dump" | sed -n 's/^ *"srvr"<blob>="\(.*\)"$/\1/p' | sort -u)
}

# ---------- 55b: logout terakhir selesai dengan rapi? ----------
# Logout menulis penanda clean.done di akhir. Saat login: kalau penanda ada, cek ulang cukup ringan
# (Keychain dilewati). Kalau logout terputus (crash, mati listrik), pembersihan penuh.
LIGHT=0
if [ "$DRY" = 0 ]; then
    [ "$MODE" = login ] && [ -f "$A/clean.done" ] && LIGHT=1
    rm -f "$A/clean.done"
fi
trace "light=$LIGHT"

# ---------- Saat login: tutup app yang sempat terbuka ----------
if [ "$MODE" = "login" ] && [ "$DRY" = 0 ] && [ -z "${AMNESIA_HOME:-}" ]; then
    killall "Google Chrome" "Brave Browser" "Firefox" "Safari" "Claude" "WhatsApp" "Telegram" \
        "Cursor" "Code" "Thunderbird" "Tailscale" "AnyDesk" "OpenCode" 2>/dev/null
    sleep 2
fi

# ---------- 1. Jejak paling sensitif dulu (waktu logout terbatas) ----------
trace "1 app data"
wipe_inside "Library/Application Support"      # browser, app login, token
wipe_inside "Library/Containers"
wipe_inside "Library/Group Containers"
for d in Cookies HTTPStorages WebKit Safari; do wipe "Library/$d"; done
if [ "$LIGHT" = 0 ]; then trace "1 keychain"; clean_keychain; fi
trace "1 history"
for f in .zsh_history .bash_history .python_history .lesshst .viminfo .node_repl_history \
         .wget-hsts .sqlite_history .psql_history .mysql_history .claude.json .claude.json.backup; do
    wipe "$f"
done
# semua folder dot di home (.zsh_sessions, .config, .cursor, .vscode, .npm, ...), kecuali keep
for c in "$H"/.*; do
    [ -d "$c" ] && [ ! -L "$c" ] || continue
    n="${c##*/}"
    case "$n" in .|..|.Trash) continue ;; esac
    wipe "$n"
done

# ---------- 2. Riwayat sistem & setting app ----------
trace "2 settings"
force "Library/Application Support/com.apple.sharedfilelist"   # recent items
force "Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2"
wipe "Library/Application Support/NotificationCenter"
wipe_inside "Library/Preferences"
wipe_inside "Library/Preferences/ByHost"
wipe_inside "Library/Saved Application State"
for d in Assistant Suggestions FontCaches; do wipe "Library/$d"; done
wipe_inside "Library/Caches"
# laporan crash Amnesia disimpan dulu di ~/.amnesia/crash (maksimal 5 terbaru), untuk melacak masalah
if [ "$DRY" = 0 ]; then
    for f in "$H/Library/Logs/DiagnosticReports"/Amnesia*; do
        mkdir -p "$A/crash" && cp -p "$f" "$A/crash/" 2>/dev/null
    done
    [ -d "$A/crash" ] && ls -t "$A/crash" | tail -n +6 | while IFS= read -r x; do rm -f "$A/crash/$x"; done
fi
wipe_inside "Library/Logs"

# ---------- 3. Folder kerja (paling besar, terakhir) ----------
trace "3 work folders"
for d in Desktop Downloads Documents Pictures Movies Music Public .Trash; do
    wipe_inside "$d"
done

if [ "$DRY" = 1 ]; then
    echo "--- dry-run ($MODE): $(t "$COUNT items would be deleted. Nothing was deleted." "$COUNT item akan dihapus. Tidak ada yang dihapus.") ---"
    exit 0
fi

# ---------- 4. Setelah bersih ----------
if [ -z "${AMNESIA_HOME:-}" ]; then
trace "4 after"
limit 5 killall cfprefsd 2>/dev/null          # supaya setting lama tidak ditulis ulang dari memori
limit 5 dscacheutil -flushcache 2>/dev/null
limit 5 killall -HUP mDNSResponder 2>/dev/null
fi
# folder Keep dibuat lagi kalau belum ada (di luar home: hanya kalau drive/foldernya ada)
{ [ -n "$KREL" ] || [ -d "${KD%/*}" ]; } && mkdir -p "$KD" 2>/dev/null
for d in /Applications "$H/Applications"; do      # pintasan app di Desktop (bukan salinan)
    [ -d "$d/Amnesia.app" ] && { ln -sfn "$d/Amnesia.app" "$H/Desktop/Amnesia.app" 2>/dev/null; break; }
done
# pintasan folder Keep di Desktop (kalau foldernya tidak di Desktop sendiri)
KL="$H/Desktop/${KD##*/}"
case "$KD" in "$H/Desktop"|"$H/Desktop/"*) ;; *)
    [ -d "$KD" ] && { [ ! -e "$KL" ] || [ -L "$KL" ]; } && ln -sfn "$KD" "$KL" 2>/dev/null ;;
esac

rm -f "$A/report.txt"     # laporan "yang akan dihapus" berisi nama file: ikut dibuang
# Log hanya waktu + jumlah, tanpa nama file (log juga jejak)
echo "$(date '+%F %T') $MODE: $(t "$COUNT items wiped" "$COUNT item dibersihkan")" > "$A/clean.log"
printf '%s\tclean\t%s %s\n' "$(date '+%F %T')" "$MODE" "$COUNT" >> "$A/history.log"   # halaman Riwayat
[ "$MODE" = logout ] && touch "$A/clean.done"      # login berikutnya cukup cek ringan
[ "$MODE" = logout ] || purge_trash               # saat logout waktunya terbatas: hapus nanti saja
trace "done ($COUNT)"
