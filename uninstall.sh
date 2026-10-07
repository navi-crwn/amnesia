#!/bin/bash
# ============================================
# AMNESIA UNINSTALL: remove Amnesia from this Mac, the safe way.
#
#   bash ~/.amnesia/uninstall.sh          remove the app, keep your vault & settings
#   bash ~/.amnesia/uninstall.sh --all    also delete ~/.amnesia (vault, Keep List, settings)
#
# Order matters: the login agent file is deleted FIRST. The agent checks for that
# file when it is stopped; without it, it stops WITHOUT wiping anything.
# Your Keep folder (your own files) is never touched.
# ============================================
set -u
A="$HOME/.amnesia"
LA="$HOME/Library/LaunchAgents"
U="gui/$(id -u)"
ALL=0; YES=0; KEEPAPP=0
for x in "$@"; do
    case "$x" in
        --all) ALL=1 ;;
        --yes) YES=1 ;;
        --keep-app) KEEPAPP=1 ;;     # Homebrew removes the app itself
    esac
done

LANG_ID=0; grep -qx "LANG=id" "$A/settings.conf" 2>/dev/null && LANG_ID=1
t() { [ $LANG_ID = 1 ] && echo "$2" || echo "$1"; }
ask() {   # works with "curl ... | bash" too: reads from the keyboard, not the pipe
    local r; printf "%s " "$1" >&2; { read -r r </dev/tty; } 2>/dev/null || r=""; echo "$r"
}

echo
echo "=== $(t "Uninstall Amnesia" "Hapus Amnesia") ==="
echo "$(t "- Stops Amnesia so it will NOT wipe your Mac anymore." "- Menghentikan Amnesia supaya Mac TIDAK dibersihkan lagi.")"
echo "$(t "- Removes the app." "- Menghapus app-nya.")"
if [ $ALL = 1 ]; then
    echo "$(t "- ALSO deletes ~/.amnesia: Profile Vault, snapshots, Keep List, settings. Cannot be undone." \
              "- JUGA menghapus ~/.amnesia: Profile Vault, snapshot, Keep List, pengaturan. Tidak bisa dibatalkan.")"
else
    echo "$(t "- Keeps ~/.amnesia (vault, Keep List, settings), in case you install again." \
              "- ~/.amnesia (vault, Keep List, pengaturan) tetap disimpan, kalau nanti mau pasang lagi.")"
fi
echo "$(t "- Your Keep folder and your files are not touched." "- Folder Keep dan file kamu tidak disentuh.")"
echo
if [ $YES = 0 ]; then
    r="$(ask "$(t "Continue? (y/n)" "Lanjut? (y/n)")")"
    case "$r" in y|Y|yes|ya|Ya) ;; *) echo "$(t "Cancelled. Nothing changed." "Dibatalkan. Tidak ada yang berubah.")"; exit 0 ;; esac
fi

echo "1/4 $(t "Turning off the login agent..." "Mematikan agent login...")"
rm -f "$LA/com.amnesia.agent.plist" "$LA/com.amnesia.loginreset.plist" "$LA/com.amnesia.menubar.plist"   # FIRST: so stopping it doesn't wipe
launchctl bootout "$U/com.amnesia.agent" 2>/dev/null
launchctl bootout "$U/com.amnesia.loginreset" 2>/dev/null
launchctl bootout "$U/com.amnesia.menubar" 2>/dev/null
sleep 2

echo "2/4 $(t "Stopping anything still running..." "Menghentikan yang masih jalan...")"
pkill -9 -f "$A/(agent|clean|reset)\.sh" 2>/dev/null
pkill -x Amnesia 2>/dev/null
pkill -f amnesia_app.py 2>/dev/null
sleep 1

echo "3/4 $(t "Removing the app..." "Menghapus app...")"
if [ $KEEPAPP = 0 ]; then
    if command -v brew >/dev/null && brew list --cask amnesia >/dev/null 2>&1; then
        brew uninstall --cask amnesia >/dev/null 2>&1
    fi
    rm -rf /Applications/Amnesia.app "$HOME/Applications/Amnesia.app"
fi
# tempat sampah Amnesia (sisa pembersihan yang belum selesai dihapus di background)
rm -rf "$HOME/.amnesia-trash"
if [ $ALL = 1 ]; then
    r="$(ask "$(t "Type DELETE to also erase ~/.amnesia (vault included):" "Ketik HAPUS untuk ikut menghapus ~/.amnesia (termasuk vault):")")"
    if [ "$r" = "DELETE" ] || [ "$r" = "HAPUS" ]; then
        rm -rf "$A"
        security delete-generic-password -s "Amnesia Backup" >/dev/null 2>&1
        echo "    $(t "~/.amnesia deleted." "~/.amnesia dihapus.")"
    else
        echo "    $(t "Skipped: ~/.amnesia was kept." "Dilewati: ~/.amnesia tetap disimpan.")"
    fi
fi

echo "4/4 $(t "Checking..." "Mengecek...")"
ok=1
launchctl list 2>/dev/null | grep -q "com.amnesia" && { ok=0; echo "  ! $(t "agent still loaded" "agent masih aktif")"; }
ls "$LA" 2>/dev/null | grep -q "com.amnesia" && { ok=0; echo "  ! $(t "agent file still there" "file agent masih ada")"; }
pgrep -x Amnesia >/dev/null && { ok=0; echo "  ! $(t "Amnesia is still running" "Amnesia masih jalan")"; }
[ $KEEPAPP = 0 ] && [ -d /Applications/Amnesia.app ] && { ok=0; echo "  ! $(t "app still in Applications" "app masih ada di Applications")"; }
echo
if [ $ok = 1 ]; then
    echo "$(t "Done. Amnesia is removed and won't wipe anything anymore." "Selesai. Amnesia sudah dihapus dan tidak akan membersihkan apa pun lagi.")"
else
    echo "$(t "Not fully clean (see above). Don't log out yet; run this script once more." \
              "Belum bersih sepenuhnya (lihat di atas). Jangan logout dulu; jalankan script ini sekali lagi.")"
    exit 1
fi
