#!/bin/bash
# ============================================
# AMNESIA KEEP LOCK + BRANKAS (v5.22, baru, eksperimen). Dipakai app, clean.sh, backup.sh, vault.py, uninstall.sh.
#
#   keeplock.sh lock          kunci ISI folder Keep (hanya kalau Kunci Keep menyala, KEEP_LOCK=1)
#   keeplock.sh unlock        buka lagi (dipanggil app setelah password Keep benar, atau backup/Doomsday sebentar)
#   keeplock.sh status        locked | open | unsupported
#   keeplock.sh box-create GB buat Brankas: disk APFS terenkripsi (AES-256) di Keep/Brankas.sparsebundle.
#                             Password dibaca dari stdin (tanpa enter di akhir), tidak pernah lewat argumen.
#   keeplock.sh box-attach    buka Brankas (password dari stdin). Hasil: baris "MOUNT <folder>"
#   keeplock.sh box-detach    tutup Brankas kalau sedang terbuka (dipanggil clean.sh sebelum membersihkan)
#   keeplock.sh box-status    none | closed | open <folder>
#
# Cara kerja Kunci Keep: izin "deny" (ACL macOS, chmod +a) untuk user kamu sendiri pada tiap file/folder di
# dalam Keep, plus "tidak boleh menambah/menghapus" pada folder Keep. Finder dan app lain mendapat "tidak ada izin".
# JUJUR: ini pengaman ringan. File TIDAK dienkripsi (pakai FileVault atau Brankas untuk itu), dan pemilik folder
# (kamu, atau siapa pun yang login sebagai kamu) bisa membuangnya sendiri dengan:  chmod -RN ~/Keep
# Symlink tidak pernah disentuh (targetnya bisa di luar Keep), Brankas.sparsebundle juga tidak (sudah terenkripsi,
# dan izin deny bisa merusak disk yang sedang terbuka).
# (Kompatibel bash 3.2 bawaan macOS.)
# ============================================
set -u
shopt -s nullglob dotglob
H="${AMNESIA_HOME:-$HOME}"; A="$H/.amnesia"; CONF="$A/settings.conf"
cfg() { grep "^$1=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-; }
trace() { echo "$(date '+%F %T') keeplock: $*" >> "$A/trace.log" 2>/dev/null; }   # tanpa nama file
# folder Keep (sama seperti clean.sh)
KD="$(cfg KEEP_DIR)"
case "$KD" in "~/"?*) KD="$H/${KD#\~/}" ;; /?*) ;; *) KD="$H/Keep" ;; esac
KD="${KD%/}"
case "$KD" in "$H"|"$H/.amnesia"|"$H/.amnesia/"*|"$H/.Trash"|"$H/.Trash/"*) KD="$H/Keep" ;; esac
BOX="$KD/Brankas.sparsebundle"
U="$(id -un)"
P_FILE="read,write,append,execute,delete,writeattr,writeextattr"
P_DIR="list,search,add_file,add_subdirectory,delete_child,delete,writeattr,writeextattr"
P_SELF="add_file,add_subdirectory,delete_child,writeattr,writeextattr"

# folder Keep punya izin deny dari Amnesia?
is_locked() { ls -led "$KD" 2>/dev/null | grep -q "user:$U deny .*delete_child"; }

# buang SEMUA izin deny milik user kamu di 1 path (juga yang dibuat versi lain)
drop_denies() {
    local n i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        n="$(ls -led "$1" 2>/dev/null | sed -n "s/^ *\([0-9][0-9]*\): user:$U deny .*/\1/p" | head -1)"
        [ -n "$n" ] || return 0
        chmod -a# "$n" "$1" 2>/dev/null || return 1
    done
}

do_lock() {
    [ "$(cfg KEEP_LOCK)" = 1 ] || return 0
    [ -d "$KD" ] && [ ! -L "$KD" ] || return 0
    [ "$(uname)" = Darwin ] || { echo unsupported; return 1; }
    is_locked && drop_denies "$KD"          # dikunci lagi: item baru sejak dibuka ikut terkunci
    local c bad=0
    for c in "$KD"/*; do
        [ -L "$c" ] && continue
        [ "$c" = "$BOX" ] && continue
        drop_denies "$c"
        if [ -d "$c" ]; then chmod +a "user:$U deny $P_DIR" "$c" 2>/dev/null || bad=$((bad + 1))
        else chmod +a "user:$U deny $P_FILE" "$c" 2>/dev/null || bad=$((bad + 1)); fi
    done
    chmod +a "user:$U deny $P_SELF" "$KD" 2>/dev/null || bad=$((bad + 1))
    if is_locked; then trace "locked ($bad not locked)"; echo locked; return 0; fi
    trace "lock failed"; echo unsupported; return 1
}

do_unlock() {
    [ -d "$KD" ] || return 0
    local c
    drop_denies "$KD"                         # folder Keep dulu, supaya isinya bisa dibuka
    for c in "$KD"/*; do
        [ -L "$c" ] && continue
        drop_denies "$c"
    done
    if is_locked; then trace "unlock failed"; echo locked; return 1; fi
    trace "unlocked"; echo open
}

# perangkat /dev/diskN dan folder tempat Brankas terbuka (kosong = tidak terbuka)
box_dev() {
    command -v hdiutil >/dev/null 2>&1 || return 0
    hdiutil info 2>/dev/null | awk -v img="$BOX" '
        /^=+$/ { on = 0; next }
        /^image-path/ { sub(/^image-path[ \t]*:[ \t]*/, ""); on = ($0 == img); next }
        on && /^\/dev\/disk/ { print $1; exit }'
}
box_mount() {
    command -v hdiutil >/dev/null 2>&1 || return 0
    hdiutil info 2>/dev/null | awk -v img="$BOX" -F '\t' '
        /^=+$/ { on = 0; next }
        /^image-path/ { p = $0; sub(/^image-path[ \t]*:[ \t]*/, "", p); on = (p == img); next }
        on && /^\/dev\/disk/ && $NF ~ /^\// { print $NF; exit }'
}

case "${1:-status}" in
    lock) do_lock ;;
    unlock) do_unlock ;;
    status)
        if [ "$(uname)" != Darwin ]; then echo unsupported
        elif is_locked; then echo locked
        else echo open; fi ;;
    box-status)
        if [ ! -d "$BOX" ]; then echo none
        else m="$(box_mount)"; if [ -n "$m" ]; then echo "open $m"; else echo closed; fi; fi ;;
    box-create)
        command -v hdiutil >/dev/null 2>&1 || { echo "FAILED: hdiutil not found" >&2; exit 1; }
        [ -e "$BOX" ] && { echo "FAILED: Brankas already exists" >&2; exit 1; }
        is_locked && { echo "FAILED: [locked] Keep is locked" >&2; exit 1; }
        GB="${2:-}"; case "$GB" in ''|*[!0-9]*) echo "FAILED: size" >&2; exit 1 ;; esac
        mkdir -p "$KD" || exit 1
        # -stdinpass: password dari stdin, tidak terlihat di daftar proses
        out="$(hdiutil create -size "${GB}g" -type SPARSEBUNDLE -fs APFS -encryption AES-256 -stdinpass \
               -volname Brankas "$BOX" 2>&1)" || { echo "FAILED: $(printf '%s' "$out" | tail -c 200)" >&2; exit 1; }
        trace "box created"
        echo "OK" ;;
    box-attach)
        [ -d "$BOX" ] || { echo "FAILED: no Brankas" >&2; exit 1; }
        m="$(box_mount)"; [ -n "$m" ] && { echo "MOUNT $m"; exit 0; }
        out="$(hdiutil attach -stdinpass -noautoopen "$BOX" 2>&1)" || {
            case "$out" in *"Authentication error"*|*"authentication"*) echo "FAILED: [wrongpw]" >&2 ;;
                           *) echo "FAILED: $(printf '%s' "$out" | tail -c 200)" >&2 ;; esac
            exit 1; }
        trace "box opened"
        echo "MOUNT $(box_mount)" ;;
    box-detach)
        d="$(box_dev)"; [ -n "$d" ] || exit 0
        hdiutil detach "$d" >/dev/null 2>&1 || hdiutil detach -force "$d" >/dev/null 2>&1 || { trace "box close failed"; exit 1; }
        trace "box closed" ;;
    *) echo "usage: keeplock.sh lock|unlock|status|box-create GB|box-attach|box-detach|box-status" >&2; exit 2 ;;
esac
