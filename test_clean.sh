#!/bin/bash
# Tes aman clean.sh di home PALSU (tidak menyentuh home asli).  bash test_clean.sh
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mk() { mkdir -p "$T/$(dirname "$1")"; echo x > "$T/$1"; }

mkdir -p "$T/.amnesia/templates/Amnesia.app"
cp "$DIR/clean.sh" "$DIR/keep.example.conf" "$T/.amnesia/"   # tes memakai contoh (tanpa keep.conf pribadi)
mk "Desktop/rahasia.txt"; mk "Downloads/a b.zip"; mk "Keep/penting.txt"
mk "Library/Application Support/Google/Chrome/Default/Cookies"
mk "Library/Application Support/com.nordvpn.macos/token"
mk "Library/Application Support/com.apple.TCC/x"
mk "Library/Application Support/com.apple.sharedfilelist/recent"
mk "Library/Containers/com.whatsapp/data"
mk "Library/Group Containers/group.com.surfshark.vpn/conf"
mk "Library/Preferences/com.google.Chrome.plist"
mk "Library/Preferences/com.apple.dock.plist"
mk "Library/Preferences/com.nordvpn.macos.plist"
mk "Library/Caches/foo/bar"
mk ".zsh_history"; mk ".zshrc"; mk ".zsh_sessions/s1"; mk ".config/opencode/auth"; mk ".config/rclone/rclone.conf"
mk ".homebrew/bin/brew"; mk ".local/bin/tool"; mk ".local/share/opencode/auth.json"
mk "Public/Drop Box/.keep"; mk ".Trash/old.txt"

AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" now --dry-run > "$T/dry.txt"
[ -f "$T/Desktop/rahasia.txt" ] || { echo "FAILED: dry-run deleted a file"; exit 1; }
grep -q "rahasia.txt" "$T/dry.txt" || { echo "FAILED: dry-run did not list Desktop"; exit 1; }

AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" now >/dev/null 2>&1

fail=0
gone() { [ ! -e "$T/$1" ] || { echo "FAILED: still there  $1"; fail=1; }; }
here() { [ -e "$T/$1" ] || { echo "FAILED: deleted      $1"; fail=1; }; }
gone "Desktop/rahasia.txt"; gone "Downloads/a b.zip"
gone "Library/Application Support/Google"; gone "Library/Containers/com.whatsapp"
gone "Library/Application Support/com.apple.sharedfilelist"
gone "Library/Preferences/com.google.Chrome.plist"; gone "Library/Caches/foo"
gone ".zsh_history"; gone ".zsh_sessions"; gone ".config/opencode"; here ".config/rclone/rclone.conf"; gone ".local/share"; gone ".Trash/old.txt"
here "Keep/penting.txt"; here ".amnesia/clean.sh"; here ".zshrc"
here "Library/Application Support/com.nordvpn.macos/token"
here "Library/Application Support/com.apple.TCC/x"
here "Library/Group Containers/group.com.surfshark.vpn/conf"
here "Library/Preferences/com.apple.dock.plist"; here "Library/Preferences/com.nordvpn.macos.plist"
here ".homebrew/bin/brew"; here ".local/bin/tool"; here "Public/Drop Box/.keep"
here "Desktop/Keep"; here "Library/Caches"

# pause 1 sesi: logout & login dilewati, lalu bersih lagi
mk "Desktop/b.txt"; touch "$T/.amnesia/pause_once"
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout >/dev/null 2>&1; here "Desktop/b.txt"
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" login  >/dev/null 2>&1; here "Desktop/b.txt"
gone ".amnesia/pause_once"
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout >/dev/null 2>&1; gone "Desktop/b.txt"

# folder Keep custom: di dalam Documents, nama dengan spasi & kurung siku
printf 'KEEP_DIR=~/Documents/Barang [Saya]\n' > "$T/.amnesia/settings.conf"
mk "Documents/Barang [Saya]/file.txt"; mk "Documents/lain.txt"; mk "Keep/lama.txt"
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout >/dev/null 2>&1
here "Documents/Barang [Saya]/file.txt"; gone "Documents/lain.txt"; here "Desktop/Barang [Saya]"
here "Keep/lama.txt"   # folder di root home (selain Desktop dkk.) memang tidak pernah dihapus
# di luar home: tidak disentuh, dan home tetap bersih
mkdir -p "$T/luar"; printf 'KEEP_DIR=%s\n' "$T/luar/Simpan" > "$T/.amnesia/settings.conf"
mk "Desktop/c.txt"
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout >/dev/null 2>&1
gone "Desktop/c.txt"; here "luar/Simpan"; here "Desktop/Simpan"
# KEEP_DIR berbahaya (home sendiri) -> kembali ke ~/Keep, tidak menyelamatkan seluruh home
printf 'KEEP_DIR=~/\n' > "$T/.amnesia/settings.conf"; mk "Downloads/d.txt"
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout >/dev/null 2>&1
gone "Downloads/d.txt"; here "Keep"

[ $fail = 0 ] && echo "OK: all clean.sh tests passed" || exit 1
