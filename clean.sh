#!/bin/bash
# ============================================
# AMNESIA CLEAN v4 — hapus semua jejak sesi
# Dipakai agent.sh saat LOGOUT/RESTART/SHUTDOWN, lalu dicek ulang saat LOGIN.
#
#   clean.sh logout|login|now [--dry-run]
#   --dry-run  : hanya tampilkan apa yang AKAN dihapus, tidak menghapus apa pun
#   --keep-file=PATH : (v5.25) hanya bersama --dry-run: pakai file ini sebagai Keep List (pratinjau mode)
#   clean.sh --skips : (v5.22) hanya tampilkan folder yang dilewati (symlink, iCloud Desktop & Dokumen), cepat
#
# Yang dilindungi: folder Keep (KEEP_DIR di settings.conf, default ~/Keep), ~/.amnesia,
# isi keep.conf, file sistem Apple.
# v5.24: Keep List hilang/tidak bisa dibaca = berhenti tanpa menghapus apa pun (exit 3). Semua penghapusan lewat
# safe_path (lihat di bawah); rm/mv hanya di amn_rm, amn_mv, trash_or_rm dan purge_now.
# (Kompatibel bash 3.2 bawaan macOS.)
# ============================================
set -u
shopt -s nullglob dotglob

H="${AMNESIA_HOME:-$HOME}"   # AMNESIA_HOME hanya untuk tes
# v5.24: path dirapikan dulu ("//" jadi "/", tanpa "/" di akhir), supaya perbandingan path selalu sama bentuknya.
# Hasil di NP (tanpa subshell: dipanggil untuk tiap path yang dihapus).
norm_path() {
    local p="$1" s=/
    while [ "${p#*$s$s}" != "$p" ]; do p="${p//$s$s/$s}"; done
    while [ ${#p} -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
    NP="$p"
}
norm_path "$H"; H="$NP"
# v5.24: home harus path lengkap dan bukan "/" (kalau tidak, berhenti: lebih baik tidak membersihkan apa pun)
case "$H" in /?*) ;; *) echo "clean.sh: no usable home folder" >&2; exit 2 ;; esac
A="$H/.amnesia"
# Bahasa pesan log (English / Indonesia), dipilih di Pengaturan app
LANGX="$(grep '^LANG=' "$A/settings.conf" 2>/dev/null | tail -1 | cut -d= -f2)"
t() { if [ "$LANGX" = id ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
# Folder Keep: bisa di mana saja dengan nama apa saja (Pengaturan app). "~/" = folder home.
KD="$(grep '^KEEP_DIR=' "$A/settings.conf" 2>/dev/null | tail -1 | cut -d= -f2-)"
case "$KD" in "~/"?*) KD="$H/${KD#\~/}" ;; /?*) ;; *) KD="$H/Keep" ;; esac
norm_path "$KD"; KD="$NP"      # v5.24: juga "//" di tengah
case "$KD" in */./*|*/../*|*/.|*/..) KD="$H/Keep" ;; esac      # v5.24: "." / ".." di path Keep = tidak jelas, pakai default
case "$KD" in "$H"|"$H/.amnesia"|"$H/.amnesia/"*|"$H/.Trash"|"$H/.Trash/"*) KD="$H/Keep" ;; esac
KREL=""; case "$KD" in "$H"/?*) KREL="${KD#"$H"/}" ;; esac      # kosong = di luar home (tidak pernah disentuh)
MODE="now"; DRY=0; SKIPS=0
KFSET=0; KFILE=""   # v5.25: --keep-file=PATH (pratinjau mode: "bagaimana kalau Keep List-nya ini?")
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY=1 ;;
        --skips) DRY=1; SKIPS=1 ;;
        --keep-file=*) KFSET=1; KFILE="${arg#--keep-file=}" ;;
        logout|login|now) MODE="$arg" ;;
    esac
done
# v5.25: --keep-file hanya boleh bersama --dry-run (tidak pernah untuk pembersihan sungguhan), dan path-nya wajib ada
if [ "$KFSET" = 1 ] && { [ "$DRY" != 1 ] || [ -z "$KFILE" ]; }; then
    echo "clean.sh: --keep-file=PATH only works together with --dry-run" >&2
    exit 2
fi
COUNT=0
FAIL=0          # v5.22: yang gagal dihapus (tidak dihitung "dibersihkan")
SLOT=0          # nomor folder di tempat sampah
REFUSED=0       # v5.24: ditolak safe_path (dilindungi)
LINKSKIP=0
ICLOUD=""       # v5.22: kenapa iCloud Desktop & Dokumen dianggap aktif (kosong = tidak aktif)
TRASHROOT="$H/.amnesia-trash"   # v5.14: tempat sampah Amnesia (di disk yang sama, jadi memindah = instan)
TRASH=""
TRACE="$A/trace.log"
# catatan langkah: jam + nama langkah saja (tanpa nama file), untuk melacak logout yang macet
trace() { [ "$DRY" = 1 ] || echo "$(date '+%F %T') clean $MODE: $*" >> "$TRACE" 2>/dev/null; }
# limit <detik> <perintah...>: perintah yang macet dihentikan, supaya logout tidak tertahan
# v5.24: penjaga waktu ikut menghentikan "sleep"-nya sendiri. Dulu sleep itu tetap hidup sampai habis waktunya
# (yatim), jadi proses yang menunggu keluaran clean.sh bisa ikut menunggu.
limit() {
    local s=$1 pid w rc; shift
    "$@" & pid=$!
    ( sp=""; trap '[ -n "$sp" ] && kill "$sp" 2>/dev/null; exit 0' TERM
      sleep "$s" & sp=$!; wait "$sp"; kill -9 "$pid" 2>/dev/null ) </dev/null >/dev/null 2>&1 &
    w=$!
    wait "$pid" 2>/dev/null; rc=$?
    kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
    return $rc
}

# v5.22: apakah salah satu bagian path ini symlink? (mis. ~/Documents -> ~/Keep/Docs atau ke disk eksternal)
via_link() {
    local p="" part IFS=/
    for part in $1; do
        p="${p:+$p/}$part"
        [ -L "$H/$p" ] && return 0
    done
    return 1
}

# v5.24: berkas kerja Amnesia sendiri di ~/.amnesia (penanda, log, laporan crash). Hanya nama relatif di dalam
# ~/.amnesia, tanpa "..", bukan folder, dan tidak pernah keep.conf atau vault. Selain lewat sini (dan trash_or_rm /
# purge_now), clean.sh tidak memakai rm atau mv sama sekali (dicek oleh test_clean.sh).
amn_name() {
    case "$1" in ""|/*|*..*|keep.conf|keep.conf.last|vault|vault/*|*/) return 1 ;; esac
    return 0
}
amn_rm() {
    amn_name "$1" || return 1
    [ -e "$A/$1" ] || [ -L "$A/$1" ] || return 0
    [ -d "$A/$1" ] && [ ! -L "$A/$1" ] && return 1
    rm -f "$A/$1" 2>/dev/null
}
# amn_mv <dari> <ke>: ke keep.conf.last boleh (salinan Keep List terakhir yang baik), selain itu sama dengan amn_rm
amn_mv() {
    amn_name "$1" || return 1
    [ "$2" = keep.conf.last ] || amn_name "$2" || return 1
    [ -f "$A/$1" ] && [ ! -L "$A/$1" ] || return 1
    mv -f "$A/$1" "$A/$2" 2>/dev/null
}

# v5.22: iCloud "Desktop & Documents" aktif? Kalau ya, Desktop dan Documents disinkron ke iCloud: menghapus isinya
# = menghapus di iCloud dan di semua perangkat Apple kamu. Hanya MEMBACA (folder, atribut, pengaturan Finder).
# Ragu = dianggap aktif (lebih baik ada file yang tertinggal daripada file di iCloud ikut terhapus).
icloud_docs() {
    local cd="$H/Library/Mobile Documents/com~apple~CloudDocs" d v
    for d in Desktop Documents; do
        if [ -e "$cd/$d" ] || [ -L "$cd/$d" ]; then ICLOUD="icloud-folder"; return 0; fi
    done
    # v5.24: folder iCloud ada tapi isinya tidak bisa dibaca = tidak bisa memastikan = dianggap aktif
    if [ -d "$cd" ] && ! limit 5 ls "$cd" >/dev/null 2>&1; then ICLOUD="icloud-unreadable"; return 0; fi
    if command -v xattr >/dev/null 2>&1; then
        for d in Desktop Documents; do
            [ -d "$H/$d" ] && [ ! -L "$H/$d" ] || continue
            # v5.24: xattr gagal (izin, macet) = tidak bisa memastikan = dianggap aktif
            v="$(limit 5 xattr "$H/$d" 2>/dev/null)" || { ICLOUD="xattr-unreadable"; return 0; }
            printf '%s\n' "$v" | grep -q 'com\.apple\.icloud' && { ICLOUD="xattr"; return 0; }
        done
    fi
    # v5.24: pengaturan Finder ada tapi tidak bisa dibaca = dianggap aktif
    if [ -e "$H/Library/Preferences/com.apple.finder.plist" ] && [ ! -r "$H/Library/Preferences/com.apple.finder.plist" ]; then
        ICLOUD="finder-unreadable"; return 0
    fi
    if command -v defaults >/dev/null 2>&1 && [ -f "$H/Library/Preferences/com.apple.finder.plist" ]; then
        for d in FXICloudDriveDesktop FXICloudDriveDocuments; do
            v="$(defaults read "$H/Library/Preferences/com.apple.finder" "$d" 2>/dev/null)"
            [ "$v" = 1 ] && { ICLOUD="finder-setting"; return 0; }
        done
    fi
    return 1
}
icloud_docs

# ---------- v5.22: hanya daftar folder yang dilewati (untuk app: Cek kesehatan, Yang Akan Dihapus) ----------
if [ "$SKIPS" = 1 ]; then
    for d in Desktop Downloads Documents Pictures Movies Music Public .Trash; do
        [ -L "$H/$d" ] && echo "LEWATI  ~/$d (symlink)"
    done
    [ -n "$ICLOUD" ] && { echo "LEWATI  ~/Desktop (icloud)"; echo "LEWATI  ~/Documents (icloud)"; }
    exit 0
fi

# ---------- v5.22: Brankas & kunci Keep (keeplock.sh) ----------
# Brankas (disk terenkripsi di folder Keep) dilepas dulu sebelum pembersihan, dan isi Keep dikunci lagi
# (kalau Kunci Keep menyala). Juga saat Jeda: keduanya bukan pembersihan.
if [ "$DRY" = 0 ] && [ -f "$A/keeplock.sh" ] && { [ "$MODE" = logout ] || [ "$MODE" = login ]; }; then
    limit 30 /bin/bash "$A/keeplock.sh" box-detach "$MODE" >/dev/null 2>&1    # v5.23: + mode (logout = catat kalau gagal)
    limit 60 /bin/bash "$A/keeplock.sh" lock >/dev/null 2>&1
fi

# ---------- Pause 1 sesi ----------
# Jeda dibuat dari GUI (file pause_once). Logout berikutnya + login berikutnya dilewati,
# lalu penanda dihapus sehingga siklus sesudahnya bersih lagi.
if [ "$DRY" = 0 ] && [ -f "$TRACE" ] && [ "$(wc -l < "$TRACE")" -gt 600 ]; then
    tail -n 400 "$TRACE" > "$TRACE.tmp" 2>/dev/null && amn_mv trace.log.tmp trace.log
fi
trace "start"
if [ "$DRY" = 0 ] && [ -f "$A/pause_once" ]; then
    if [ "$MODE" = "login" ]; then
        amn_rm pause_once
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
    # v5.24: file cloud (iCloud Drive, Dropbox, Google Drive, OneDrive...): menghapus di sini = menghapus di cloud
    "Library/Mobile Documents"
    "Library/CloudStorage"
)
KC_KEEP=(
    "com.apple.*" "AirPort" "AirPlay Server Identity" "Apple Persistent State Encryption"
    "AppleIDClientIdentifier" "BluetoothGlobal" "BluetoothLE" "ProtectedCloudStorage"
    "TelephonyUtilities" "WiFiAnalytics" "MetadataKeychain" "iCloud"
)
# folder Keep (karakter * ? [ ] di namanya dibaca apa adanya, bukan pola)
# v5.22: pola Keep + bentuk Unicode lainnya (NFC/NFD). APFS menyimpan nama apa adanya, jadi "Café" yang
# diketik (NFC) dan "Café" dari Finder/backup lama (NFD) beda byte, padahal namanya sama.
add_keep() {
    KEEP+=("$1")
    printf '%s' "$1" | LC_ALL=C grep -q '[^ -~]' || return 0      # hanya huruf ASCII: tidak perlu
    local v
    for v in "$(printf '%s' "$1" | iconv -f UTF-8-MAC -t UTF-8 2>/dev/null)" \
             "$(printf '%s' "$1" | iconv -f UTF-8 -t UTF-8-MAC 2>/dev/null)"; do
        [ -n "$v" ] && [ "$v" != "$1" ] && KEEP+=("$v")
    done
    return 0
}
[ -n "$KREL" ] && add_keep "$(printf '%s' "$KREL" | sed 's/[][*?\\]/\\&/g')"
APP_KEEP=()
# keep.conf = milik pribadi (tidak di GitHub).
# v5.24: dulu keep.conf yang hilang/rusak diam-diam diganti keep.example.conf, jadi semua yang disimpan bisa ikut
# terhapus. Sekarang pembersihan BERHENTI (tidak menghapus apa pun) kalau:
#   - keep.conf ada tapi tidak bisa dibaca (izin, folder, link rusak)       -> keeplist-unreadable
#   - keep.conf hilang padahal salinan terakhir (keep.conf.last) ada        -> keeplist-missing
# keep.example.conf hanya dipakai kalau belum pernah ada Keep List sama sekali (instalasi baru, tes).
KC="$A/keep.conf"; KSTOP=""; KTXT=""; KEEPF=""
if [ "$KFSET" = 1 ]; then
    KEEPF="$KFILE"          # v5.25: pratinjau mode (hanya dry-run, dicek di atas)
elif [ -e "$KC" ] || [ -L "$KC" ]; then
    KEEPF="$KC"
elif [ -e "$A/keep.conf.last" ] || [ -L "$A/keep.conf.last" ]; then
    KSTOP="keeplist-missing"
elif [ -e "$A/keep.example.conf" ]; then
    KEEPF="$A/keep.example.conf"
fi
if [ -n "$KEEPF" ]; then
    # dibaca utuh dulu: gagal di tengah jalan = tidak bisa dibaca (bukan Keep List yang setengah)
    if [ -f "$KEEPF" ] && KTXT="$(cat "$KEEPF" 2>/dev/null)"; then
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line%$'\r'}"
            line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
            case "$line" in
                ""|"#"*) ;;
                keychain:*) KC_KEEP+=("${line#keychain:}") ;;
                app:*) APP_KEEP+=("${line#app:}") ;;          # v5.19: app yang tidak ikut "Hapus app baru"
                *) add_keep "${line#\~/}" ;;
            esac
        done < <(printf '%s\n' "$KTXT")
    else
        KSTOP="keeplist-unreadable"
    fi
fi
if [ -n "$KSTOP" ]; then
    if [ "$DRY" = 1 ]; then
        echo "STOP  $KSTOP"
        echo "--- dry-run ($MODE): $(t "0 items would be deleted. Nothing was deleted." "0 item akan dihapus. Tidak ada yang dihapus.") ---"
        exit 0
    fi
    echo "$(date '+%F %T') $MODE: STOPPED $KSTOP" > "$A/clean.log"
    printf '%s\tstopped\t%s %s\n' "$(date '+%F %T')" "$MODE" "$KSTOP" >> "$A/history.log"
    case "$KSTOP" in keeplist-missing) trace "stop: keep list missing" ;; *) trace "stop: keep list unreadable" ;; esac
    exit 3
fi

# path (relatif ke home) cocok dengan salah satu pola keep?
kept() {
    local p
    for p in "${KEEP[@]}"; do [[ "$1" == $p ]] && return 0; done
    return 1
}

# v5.23: Claude di Keep List = Claude Code ikut disimpan. Chat di tab Code (Claude Desktop) ada di ~/.claude dan
# ~/.claude.json (+ .backup), bukan di Library/Application Support/Claude, jadi dulu tetap hilang tiap logout.
if kept "Library/Application Support/Claude"; then
    for c in .claude .claude.json .claude.json.backup; do kept "$c" || add_keep "$c"; done
    trace "claude code data kept with Claude"
fi

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

# v5.14: tempat sampah Amnesia untuk pembersihan ini (dibuat saat pertama dipakai)
new_trash() {
    [ -n "$TRASH" ] && return 0
    TRASH="$TRASHROOT/$(date +%Y%m%d-%H%M%S)-$$"
    mkdir -p "$TRASH" 2>/dev/null && chmod 700 "$TRASHROOT" 2>/dev/null
    touch "$TRASHROOT/.metadata_never_index" 2>/dev/null      # Spotlight tidak mengindeks isinya
}

# v5.24: SATU pengecekan untuk semua yang dihapus/dipindah. 0 = boleh. Ditolak:
#   - kosong, bukan path lengkap, ada bagian "." atau ".."
#   - folder home sendiri, ~/.amnesia, folder Keep, tempat sampah Amnesia (juga isinya, dan folder di atasnya)
#   - apa pun di luar home, kecuali app milik kamu langsung di /Applications (Nama.app, bukan link)
#   - path di bawah home yang salah satu folder di atasnya symlink (tidak pernah lewat link)
# "//" dan "/" di akhir dirapikan dulu. Huruf besar/kecil dianggap sama (APFS biasanya tidak membedakan).
# Tanpa program luar: dipanggil untuk tiap item.
safe_path() {
    local p rel q r=1 bad=0 x
    case "$1" in /*) ;; *) return 1 ;; esac
    norm_path "$1"; p="$NP"
    case "$p/" in */./*|*/../*) return 1 ;; esac
    shopt -s nocasematch
    [[ "$p" == "$H" ]] && bad=1
    for x in "$A" "$TRASHROOT" ${KD:+"$KD"}; do
        [[ "$p" == "$x" || "$p" == "$x/"* || "$x" == "$p/"* ]] && bad=1
    done
    shopt -u nocasematch
    [ "$bad" = 0 ] || return 1
    case "$p" in
        "$H"/?*)
            rel="${p#"$H"/}"
            case "$rel" in */*) via_link "${rel%/*}" && return 1 ;; esac
            r=0 ;;
        /Applications/?*.app)
            q="${p#/Applications/}"
            # mode tes: di luar home tidak pernah disentuh
            if [ -z "${AMNESIA_HOME:-}" ]; then
                case "$q" in */*) ;; *) [ -d "$p" ] && [ ! -L "$p" ] && [ -O "$p" ] && r=0 ;; esac
            fi ;;
    esac
    return $r
}

# v5.22: pindah ke tempat sampah Amnesia, atau hapus langsung. Hasil 1 = gagal (dicatat, tidak dihitung "dibersihkan").
# $1 = path lengkap, $2 = bagian untuk trace.log (hanya nama area, mis. "Desktop", tidak pernah nama file)
# v5.24: selalu lewat safe_path dulu. Ditolak = dilindungi (tidak dihapus, tidak dihitung gagal).
trash_or_rm() {
    if ! safe_path "$1"; then
        REFUSED=$((REFUSED + 1))
        trace "refused a protected path (in $2)"
        return 1
    fi
    new_trash
    SLOT=$((SLOT + 1))
    # tempat sampah Amnesia yang ternyata symlink tidak dipakai (isinya bisa pindah ke tempat lain)
    [ ! -L "$TRASHROOT" ] && mkdir "$TRASH/$SLOT" 2>/dev/null && mv "$1" "$TRASH/$SLOT/" 2>/dev/null && { COUNT=$((COUNT + 1)); return 0; }
    rm -rf "$1" 2>/dev/null
    if [ -e "$1" ] || [ -L "$1" ]; then
        FAIL=$((FAIL + 1))
        trace "could not delete (in $2)"
        return 1
    fi
    COUNT=$((COUNT + 1))
}

remove() {
    if [ "$DRY" = 1 ]; then
        # v5.24: pratinjau memakai pengecekan yang sama dengan penghapusan sungguhan
        safe_path "$H/$1" || { echo "LEWATI  ~/$1 (protected)"; return 0; }
        COUNT=$((COUNT + 1)); echo "HAPUS  ~/$1"; return 0
    fi
    # v5.14: dipindah ke tempat sampah Amnesia (instan, berapa pun ukurannya), lalu dihapus pelan di
    # background setelah login. Kalau pindah gagal, langsung dihapus seperti dulu.
    # v5.22: yang tetap ada (mis. file terkunci) dihitung gagal, bukan "dibersihkan"
    local area="${1%%/*}"
    case "$1" in Library/*/*) area="$(printf '%s' "$1" | cut -d/ -f1-2)" ;; */*) ;; *) area="home folder" ;; esac
    trash_or_rm "$H/$1" "$area"
}

# v5.22: hapus isi tempat sampah. Yang gagal dicatat di trace.log (jumlahnya saja) dan di trash.failed (untuk app),
# lalu dicoba lagi di pembersihan berikutnya (sisanya tetap di ~/.amnesia-trash).
# purge_now <tempat sampah> <trace.log> <file status> <mode>
purge_now() {
    local root="$1" left
    # v5.24: hanya pernah menghapus folder bernama .amnesia-trash (path lengkap, tanpa "." / "..", bukan link)
    case "$root" in /*/.amnesia-trash) ;; *) return 1 ;; esac
    case "$root/" in */./*|*/../*|*//*) return 1 ;; esac
    [ -L "$root" ] && return 1
    [ -d "$root" ] || return 0
    rm -rf "$root" 2>/dev/null
    if [ -e "$root" ] && command -v chflags >/dev/null 2>&1; then
        # file yang dikunci (Get Info → Locked) di dalam folder yang sudah dipindah: buka kuncinya, lalu coba lagi
        chflags -R nouchg "$root" 2>/dev/null
        rm -rf "$root" 2>/dev/null
    fi
    left=0
    # hanya file yang dihitung (folder yang tertinggal karena isinya tidak bisa dihapus tidak dihitung lagi)
    if [ -e "$root" ]; then
        left="$(find "$root" -mindepth 1 ! -type d 2>/dev/null | wc -l | tr -d ' ')"
        [ "${left:-0}" -gt 0 ] || left=1
    fi
    if [ "${left:-0}" -gt 0 ]; then
        echo "$(date '+%F %T') clean $4: trash: $left items could not be deleted (tried again next time)" >> "$2" 2>/dev/null
        echo "$left" > "$3" 2>/dev/null
    else
        rm -rf "$root" 2>/dev/null
        echo "$(date '+%F %T') clean $4: trash emptied" >> "$2" 2>/dev/null
        rm -f "$3"
    fi
}

# isi tempat sampah dihapus di background dengan prioritas rendah, supaya Mac tidak terasa lambat.
# v5.22: dulu "nohup rm" tanpa catatan (kegagalan tidak terlihat). Sekarang hasilnya selalu dicatat.
purge_trash() {
    [ -d "$TRASHROOT" ] || return 0
    if [ -n "${AMNESIA_HOME:-}" ]; then purge_now "$TRASHROOT" "$TRACE" "$A/trash.failed" "$MODE"; return 0; fi   # mode tes: langsung
    export -f purge_now
    nohup /usr/bin/nice -n 20 /usr/sbin/taskpolicy -b /bin/bash -c 'purge_now "$@"' purge \
        "$TRASHROOT" "$TRACE" "$A/trash.failed" "$MODE" >/dev/null 2>&1 &
}

# ---------- v5.24: folder yang sedang dipakai app yang terbuka ----------
# Saat login dan "now" (bukan logout: waktunya terbatas) folder yang masih punya file terbuka dilewati, lalu
# dibersihkan lain kali. Satu panggilan lsof (dibatasi waktunya), disingkat jadi path pendek:
# Library/* = 4 tingkat (mis. Library/Application Support/Google/GoogleUpdater: pembantu yang jalan sendiri tidak
# membuat seluruh Library/Application Support/Google, termasuk data Chrome, dilewati), lainnya 2 tingkat
# (mis. Downloads/proyek).
# Hanya disimpan di memori. trace.log hanya mencatat jumlah dan area, tidak pernah nama file.
INUSE=(); NINUSE=0; INUSESKIP=0
load_in_use() {
    local out x rc=0
    command -v lsof >/dev/null 2>&1 || { trace "in-use check: no lsof"; return 0; }
    # v5.25: lsof memberi path asli (mis. /private/var/... untuk /var/..., atau tujuan link), jadi home juga
    # dibandingkan dalam bentuk aslinya (pwd -P)
    local hp; hp="$(cd "$H" 2>/dev/null && pwd -P)"; [ -n "$hp" ] || hp="$H"
    out="$(limit 15 lsof -n -P -w -F n -u "$(id -u)" 2>/dev/null | awk -v h="$H/" -v hp="$hp/" '
        substr($0, 1, 1) == "n" {
            p = substr($0, 2)
            if (index(p, h) == 1) r = substr(p, length(h) + 1)
            else if (index(p, hp) == 1) r = substr(p, length(hp) + 1)
            else next
            n = split(r, a, "/")
            if (n < 1 || a[1] == "") next
            k = (a[1] == "Library") ? 4 : 2
            short = (n < k) ? "S " : ""
            if (n < k) k = n
            s = a[1]
            for (i = 2; i <= k; i++) s = s "/" a[i]
            print short s
        }' | sort -u; echo "rc=${PIPESTATUS[0]}")"
    while IFS= read -r x; do
        case "$x" in
            rc=*) rc="${x#rc=}" ;;
            # kurang dari 2/4 tingkat: hanya file biasa (folder kerja sebuah Terminal tidak membuat seluruh
            # Downloads atau Library/Caches dilewati)
            "S "*) x="${x#S }"; [ -f "$H/$x" ] && [ ! -L "$H/$x" ] && { INUSE+=("$x"); NINUSE=$((NINUSE + 1)); } ;;
            ?*) INUSE+=("$x"); NINUSE=$((NINUSE + 1)) ;;
        esac
    done < <(printf '%s\n' "$out")
    # lsof terputus (macet, waktu habis): daftar bisa kurang lengkap, dicatat
    [ "${rc:-0}" -ge 128 ] 2>/dev/null && trace "in-use check incomplete (lsof stopped)"
    trace "in-use check: $NINUSE places"
}
# path ini (atau folder di atasnya) dipakai app yang terbuka?
in_use() {
    local u
    for u in "${INUSE[@]+"${INUSE[@]}"}"; do
        [ "$1" = "$u" ] && return 0
        case "$1" in "$u"/*) return 0 ;; esac
    done
    return 1
}
# ada yang dipakai DI DALAM path ini? -> masuk ke dalam, jangan pindahkan foldernya utuh
use_inside() {
    local u
    for u in "${INUSE[@]+"${INUSE[@]}"}"; do
        case "$u" in "$1"/*) return 0 ;; esac
    done
    return 1
}
skip_in_use() {
    local area="${1%%/*}"
    case "$1" in Library/*/*) area="$(printf '%s' "$1" | cut -d/ -f1-2)" ;; */*) ;; *) area="home folder" ;; esac
    INUSESKIP=$((INUSESKIP + 1))
    [ "$DRY" = 1 ] && echo "LEWATI  ~/$1 (in use)"
    trace "skip in use (in $area)"
}

# hapus satu path, menghormati keep list
wipe() {
    local rel="$1" c
    [ -e "$H/$rel" ] || [ -L "$H/$rel" ] || return 0
    kept "$rel" && return 0
    if [ "$NINUSE" -gt 0 ]; then            # v5.24: dipakai app yang terbuka -> lain kali
        if in_use "$rel"; then skip_in_use "$rel"; return 0; fi
        if [ -d "$H/$rel" ] && [ ! -L "$H/$rel" ] && use_inside "$rel"; then
            for c in "$H/$rel"/*; do wipe "$rel/${c##*/}"; done
            return 0
        fi
    fi
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
    # isi folder yang ternyata symlink TIDAK dikosongkan: targetnya bisa folder Keep, disk lain, atau iCloud
    if via_link "$1"; then
        [ "$DRY" = 1 ] && echo "LEWATI  ~/$1 (symlink)"
        trace "skip symlinked folder"
        LINKSKIP=$((LINKSKIP + 1))
        return 0
    fi
    for c in "$H/$1"/*; do wipe "$1/${c##*/}"; done
}

# hapus walau termasuk pola Apple (jejak "recent" milik sistem)
force() {
    [ -e "$H/$1" ] || [ -L "$H/$1" ] || return 0
    if [ "$NINUSE" -gt 0 ] && in_use "$1"; then skip_in_use "$1"; return 0; fi   # v5.24
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
    amn_rm clean.done
fi
trace "light=$LIGHT"

# ---------- v5.23: salinan "sebelum restore" dari Profile Vault paling lama 3 hari ----------
# Biasanya sudah ikut terhapus bersama Library/Caches saat logout. Ini untuk yang lolos (mis. Library/Caches di
# Keep List). Bisa belasan GB, jadi tidak dibiarkan menumpuk.
if [ "$DRY" = 0 ] && [ "$MODE" = login ]; then
    for d in before-restore after-restore; do
        d="$H/Library/Caches/Amnesia/$d"
        [ -d "$d" ] && [ -n "$(find "$d" -maxdepth 0 -mmin +4320 2>/dev/null)" ] || continue
        trash_or_rm "$d" "Library/Caches" && trace "old before-restore copy removed (3 days)"
    done
fi

# ---------- Saat login: tutup app yang sempat terbuka ----------
if [ "$MODE" = "login" ] && [ "$DRY" = 0 ] && [ -z "${AMNESIA_HOME:-}" ]; then
    killall "Google Chrome" "Brave Browser" "Firefox" "Safari" "Claude" "WhatsApp" "Telegram" \
        "Cursor" "Code" "Thunderbird" "Tailscale" "AnyDesk" "OpenCode" 2>/dev/null
    sleep 2
fi
# v5.24: folder yang dipakai app yang terbuka. Dicek SETELAH app di atas ditutup (kalau sebelumnya, data browser
# yang dibuka ulang saat login ikut dilewati). Tidak saat logout (waktunya terbatas).
[ "$MODE" = logout ] || load_in_use

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
    [ -d "$A/crash" ] && ls -t "$A/crash" | tail -n +6 | while IFS= read -r x; do amn_rm "crash/$x"; done
fi
wipe_inside "Library/Logs"

# ---------- 3. Folder kerja (paling besar, terakhir) ----------
trace "3 work folders"
# v5.22: iCloud Desktop & Documents aktif: Desktop dan Documents tidak disentuh sama sekali (isinya ada di iCloud)
if [ -n "$ICLOUD" ]; then
    trace "iCloud Desktop & Documents on ($ICLOUD): Desktop and Documents skipped"
    [ "$DRY" = 1 ] && { echo "LEWATI  ~/Desktop (icloud)"; echo "LEWATI  ~/Documents (icloud)"; }
fi
for d in Desktop Downloads Documents Pictures Movies Music Public .Trash; do
    [ -n "$ICLOUD" ] && { [ "$d" = Desktop ] || [ "$d" = Documents ]; } && continue
    wipe_inside "$d"
done

# ---------- 3b. App yang baru dipasang (v5.19, Pengaturan → Lanjutan, default mati) ----------
# App di Applications yang tidak ada di daftar patokan (dibuat saat fitur ini dinyalakan) dan tidak ada di
# Keep List (baris app:/Applications/Nama.app) ikut dihapus. Hanya app milik user kamu sendiri: app yang
# dipasang dengan password admin (.pkg, App Store) tidak disentuh, cuma dihitung.
APPS_SKIPPED=0
remove_new_apps() {
    [ "$(grep '^REMOVE_NEW_APPS=' "$A/settings.conf" 2>/dev/null | tail -1 | cut -d= -f2)" = 1 ] || return 0
    local base="$A/apps_baseline.txt" dirs app k ok
    [ -f "$base" ] || return 0
    # v5.24: daftar patokan tidak bisa dibaca = tidak tahu app mana yang baru = tidak ada app yang dihapus
    cat "$base" >/dev/null 2>&1 || { trace "new apps: baseline unreadable, nothing removed"; return 0; }
    if [ -n "${AMNESIA_APPS_DIRS:-}" ]; then dirs="$AMNESIA_APPS_DIRS"          # hanya untuk tes
    elif [ -n "${AMNESIA_HOME:-}" ]; then dirs="$H/Applications"                # mode tes: jangan sentuh /Applications asli
    else dirs="/Applications:$H/Applications"; fi
    local IFS=:
    for d in $dirs; do
        IFS=$' \t\n'
        for app in "$d"/*.app; do
            [ -d "$app" ] && [ ! -L "$app" ] || continue
            case "${app##*/}" in Amnesia.app|"Amnesia Shots.app") continue ;; esac
            grep -qxF "$app" "$base"; [ $? = 1 ] || continue     # v5.24: 0 = di patokan, 2 = error -> lewati
            ok=0; for k in "${APP_KEEP[@]+"${APP_KEEP[@]}"}"; do [ "$k" = "$app" ] && ok=1; done
            [ "$ok" = 1 ] && continue
            if [ ! -O "$app" ]; then APPS_SKIPPED=$((APPS_SKIPPED + 1)); continue; fi   # milik admin/sistem
            if [ "$DRY" = 1 ]; then COUNT=$((COUNT + 1)); echo "APP  $app"; continue; fi
            trash_or_rm "$app" "Applications"
        done
        IFS=:
    done
}
trace "3b new apps"
remove_new_apps

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
# pintasan folder Keep di Desktop (kalau foldernya tidak di Desktop sendiri). v5.19.1: bisa dimatikan di
# Pengaturan → "Alias Keep di Desktop" (KEEP_SHORTCUT=0)
KL="$H/Desktop/${KD##*/}"
if [ "$(grep '^KEEP_SHORTCUT=' "$A/settings.conf" 2>/dev/null | tail -1 | cut -d= -f2)" != 0 ]; then
case "$KD" in "$H/Desktop"|"$H/Desktop/"*) ;; *)
    [ -d "$KD" ] && { [ ! -e "$KL" ] || [ -L "$KL" ]; } && ln -sfn "$KD" "$KL" 2>/dev/null ;;
esac
fi

amn_rm report.txt     # laporan "yang akan dihapus" berisi nama file: ikut dibuang
# Log hanya waktu + jumlah, tanpa nama file (log juga jejak)
# v5.22: yang gagal dihapus ikut disebut (jumlahnya saja)
FAILTXT=""; [ "$FAIL" -gt 0 ] && FAILTXT="$(t "; $FAIL could not be deleted" "; $FAIL gagal dihapus")"
echo "$(date '+%F %T') $MODE: $(t "$COUNT items wiped" "$COUNT item dibersihkan")$FAILTXT" > "$A/clean.log"
# v5.19: ukuran yang dibersihkan (KB) ikut dicatat di Riwayat. du dibatasi waktunya: logout tidak boleh tertahan.
KB=0
if [ -n "$TRASH" ] && [ -d "$TRASH" ]; then
    KB="$(limit 10 du -sk "$TRASH" 2>/dev/null | cut -f1)"; KB="${KB:-0}"
fi
printf '%s\tclean\t%s %s %s %s\n' "$(date '+%F %T')" "$MODE" "$COUNT" "$KB" "$FAIL" >> "$A/history.log"   # halaman Riwayat (v5.22: + gagal)
[ "$APPS_SKIPPED" -gt 0 ] && printf '%s\tappskip\t%s\n' "$(date '+%F %T')" "$APPS_SKIPPED" >> "$A/history.log"
[ "$MODE" = logout ] && touch "$A/clean.done"      # login berikutnya cukup cek ringan
[ "$MODE" = logout ] || purge_trash               # saat logout waktunya terbatas: hapus nanti saja
# v5.24: salinan Keep List terakhir yang baik (app memakainya untuk memulihkan keep.conf yang hilang).
# Ditulis ke file sementara lalu di-rename (tidak pernah setengah jadi).
if [ "$KEEPF" = "$KC" ]; then
    if ( umask 077; printf '%s\n' "$KTXT" > "$A/keep.conf.last.tmp" ) 2>/dev/null; then
        amn_mv keep.conf.last.tmp keep.conf.last || amn_rm keep.conf.last.tmp
    else
        amn_rm keep.conf.last.tmp
    fi
fi
[ "$INUSESKIP" -gt 0 ] && trace "in use: $INUSESKIP skipped (wiped next time)"
[ "$REFUSED" -gt 0 ] && trace "protected paths refused: $REFUSED"
trace "done ($COUNT, failed $FAIL)"
