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

# v5.14: logout MEMINDAH ke tempat sampah (cepat), login menghapusnya; login ringan kalau logout selesai
rm -f "$T/.amnesia/settings.conf"; mk "Downloads/e.txt"
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout >/dev/null 2>&1
gone "Downloads/e.txt"; here ".amnesia/clean.done"
ls "$T/.amnesia-trash"/*/*/e.txt >/dev/null 2>&1 || { echo "FAILED: not moved to trash"; fail=1; }
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" login >/dev/null 2>&1
gone ".amnesia-trash"; gone ".amnesia/clean.done"
grep -q "clean login: light=1" "$T/.amnesia/trace.log" || { echo "FAILED: light login not used"; fail=1; }
# logout terputus (tanpa clean.done) -> login membersihkan penuh
mk "Downloads/f.txt"
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" login >/dev/null 2>&1
gone "Downloads/f.txt"; grep -q "clean login: light=0" "$T/.amnesia/trace.log" || { echo "FAILED: full login after interrupted logout"; fail=1; }
! grep -q "f.txt\|e.txt" "$T/.amnesia/trace.log" || { echo "FAILED: trace.log contains file names"; fail=1; }

# v5.19: Riwayat mencatat ukuran (KB) yang dibersihkan
grep -qE "	clean	logout [0-9]+ [0-9]+( [0-9]+)?$" "$T/.amnesia/history.log" || { echo "FAILED: history has no size"; fail=1; }

# v5.19: "Hapus app baru" (default mati). Hanya app di luar patokan & Keep List, milik user sendiri.
mkdir -p "$T/Applications/Lama.app" "$T/Applications/Baru.app" "$T/Applications/Disimpan.app" "$T/Applications/Amnesia.app"
mk "Desktop/g.txt"
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout >/dev/null 2>&1
here "Applications/Baru.app"     # fitur mati: tidak ada app yang dihapus
printf '%s\n' "$T/Applications/Lama.app" > "$T/.amnesia/apps_baseline.txt"
printf 'REMOVE_NEW_APPS=1\n' > "$T/.amnesia/settings.conf"
printf 'app:%s\n' "$T/Applications/Disimpan.app" >> "$T/.amnesia/keep.example.conf"
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout --dry-run | grep -q "^APP  .*Baru.app" || { echo "FAILED: dry-run does not list the new app"; fail=1; }
here "Applications/Baru.app"
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout >/dev/null 2>&1
gone "Applications/Baru.app"; here "Applications/Lama.app"; here "Applications/Disimpan.app"; here "Applications/Amnesia.app"
rm -f "$T/.amnesia/settings.conf" "$T/.amnesia/apps_baseline.txt"

# v5.15: agent.sh membersihkan saat logout hanya kalau app masih ada (dibuang ke Trash = tidak membersihkan)
G="$T/agenthome"; mkdir -p "$G/.amnesia" "$G/Library/LaunchAgents" "$G/Amnesia.app"
cp "$DIR/agent.sh" "$G/.amnesia/"
printf '#!/bin/bash\ntouch "$HOME/cleaned"\n' > "$G/.amnesia/clean.sh"
agent_logout() {   # $1 = letak app untuk agent
    touch "$G/.amnesia/.just_activated" "$G/Library/LaunchAgents/com.amnesia.agent.plist" \
          "$G/Library/LaunchAgents/com.amnesia.menubar.plist"
    HOME="$G" AMNESIA_APP="$1" bash "$G/.amnesia/agent.sh" & local pid=$!
    sleep 1; kill -TERM $pid; wait $pid 2>/dev/null
}
agent_logout "$G/Amnesia.app"
[ -f "$G/cleaned" ] || { echo "FAILED: agent did not clean while the app exists"; fail=1; }
rm -f "$G/cleaned"; agent_logout "$G/Gone.app"
[ ! -f "$G/cleaned" ] || { echo "FAILED: agent cleaned although the app is gone"; fail=1; }
[ ! -f "$G/Library/LaunchAgents/com.amnesia.agent.plist" ] || { echo "FAILED: agent not turned off after app removed"; fail=1; }
rm -f "$G/cleaned"; agent_logout "$G/.Trash/Amnesia.app"
[ ! -f "$G/cleaned" ] || { echo "FAILED: agent cleaned although the app is in the Trash"; fail=1; }

# v5.19.1: alias Keep di Desktop bisa dimatikan (Pengaturan → Alias Keep di Desktop)
mkdir -p "$T/Keep"
printf 'KEEP_SHORTCUT=0\n' > "$T/.amnesia/settings.conf"
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout >/dev/null 2>&1
[ ! -L "$T/Desktop/Keep" ] || { echo "FAILED: Keep alias made although switched off"; fail=1; }
rm -f "$T/.amnesia/settings.conf"
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout >/dev/null 2>&1
[ -L "$T/Desktop/Keep" ] || { echo "FAILED: Keep alias missing"; fail=1; }

# ---------------- v5.22 ----------------
# agent: app dipindah/dihapus -> tercatat (dan notifikasi di macOS)
grep -q "stopped (app removed or moved, nothing wiped)" "$G/.amnesia/trace.log" 2>/dev/null \
    || { echo "FAILED: agent trace does not say the app was removed or moved"; fail=1; }

# symlink: Documents -> Keep/DocsAsli. Isinya (di Keep) tidak boleh ikut dihapus lewat symlink
rm -rf "$T/Documents"; mk "Keep/DocsAsli/tesis.docx"; ln -s "$T/Keep/DocsAsli" "$T/Documents"
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" --skips | grep -q "^LEWATI  ~/Documents (symlink)" \
    || { echo "FAILED: --skips does not list the symlinked Documents"; fail=1; }
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout --dry-run | grep -q "tesis.docx" \
    && { echo "FAILED: dry-run lists a file behind the symlink"; fail=1; }
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout >/dev/null 2>&1
here "Keep/DocsAsli/tesis.docx"; [ -L "$T/Documents" ] || { echo "FAILED: symlink Documents removed"; fail=1; }
rm -f "$T/Documents"; mkdir -p "$T/Documents"

# NFC/NFD: "Café" di Keep List (NFC) harus juga menyimpan "Café" (NFD) dari Finder/backup lama.
# Di Linux tidak ada iconv UTF-8-MAC: pakai pengganti kecil (python) yang hanya untuk tes ini.
SHIM=""
if ! printf 'x' | iconv -f UTF-8-MAC -t UTF-8 >/dev/null 2>&1; then
    SHIM="$T/shim"; mkdir -p "$SHIM"
    cat > "$SHIM/iconv" <<'EOF'
#!/bin/bash
# tes saja: -f UTF-8-MAC -> NFC, -t UTF-8-MAC -> NFD
case "$*" in *"-f UTF-8-MAC"*) f=NFC ;; *"-t UTF-8-MAC"*) f=NFD ;; *) exec cat ;; esac
exec python3 -c 'import sys,unicodedata; sys.stdout.write(unicodedata.normalize(sys.argv[1], sys.stdin.read()))' "$f"
EOF
    chmod +x "$SHIM/iconv"
fi
NFC="$(python3 -c 'import unicodedata;print(unicodedata.normalize("NFC","Downloads/Café"))')"
NFD="$(python3 -c 'import unicodedata;print(unicodedata.normalize("NFD","Downloads/Café"))')"
cp "$T/.amnesia/keep.example.conf" "$T/keep.bak"
printf '%s\n' "$NFC" >> "$T/.amnesia/keep.example.conf"
mkdir -p "$T/$NFD"; echo x > "$T/$NFD/menu.txt"; mk "Downloads/lain2.txt"
PATH="${SHIM:+$SHIM:}$PATH" AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout >/dev/null 2>&1
[ -f "$T/$NFD/menu.txt" ] || { echo "FAILED: NFD name not kept by an NFC Keep List entry"; fail=1; }
gone "Downloads/lain2.txt"
cp "$T/keep.bak" "$T/.amnesia/keep.example.conf"; rm -rf "$T/$NFD"

# gagal dihapus: dicatat (jumlah saja), tidak dihitung "dibersihkan", dicoba lagi lain kali
lockf() { chattr +i "$1" 2>/dev/null || chflags uchg "$1" 2>/dev/null; }
unlockf() { chattr -i "$1" 2>/dev/null || chflags nouchg "$1" 2>/dev/null; true; }
mk "Downloads/terkunci.txt"
if lockf "$T/Downloads/terkunci.txt"; then
    trap 'unlockf "$T/Downloads/terkunci.txt"; find "$T" -exec chattr -i {} + 2>/dev/null; rm -rf "$T"' EXIT
    AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout >/dev/null 2>&1
    here "Downloads/terkunci.txt"
    grep -q "1 could not be deleted" "$T/.amnesia/clean.log" || { echo "FAILED: clean.log does not report the failed delete"; fail=1; }
    tail -1 "$T/.amnesia/history.log" | grep -qE "	clean	logout [0-9]+ [0-9]+ 1$" || { echo "FAILED: history has no failed count"; fail=1; }
    grep -q "could not delete (in Downloads)" "$T/.amnesia/trace.log" || { echo "FAILED: trace has no failed delete"; fail=1; }
    grep -q "terkunci" "$T/.amnesia/trace.log" && { echo "FAILED: trace.log contains a file name"; fail=1; }
    unlockf "$T/Downloads/terkunci.txt"
    AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout >/dev/null 2>&1
    gone "Downloads/terkunci.txt"
    grep -q "could not be deleted" "$T/.amnesia/clean.log" && { echo "FAILED: clean.log still reports a failure"; fail=1; }
    # isi tempat sampah yang tidak bisa dihapus: trash.failed (untuk app), lalu hilang setelah berhasil
    AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" login >/dev/null 2>&1
    mkdir -p "$T/.amnesia-trash/1/Downloads"; echo x > "$T/.amnesia-trash/1/Downloads/x"; lockf "$T/.amnesia-trash/1/Downloads/x"
    AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" login >/dev/null 2>&1
    [ "$(cat "$T/.amnesia/trash.failed" 2>/dev/null)" = 1 ] || { echo "FAILED: trash.failed not written"; fail=1; }
    grep -q "trash: 1 items could not be deleted" "$T/.amnesia/trace.log" || { echo "FAILED: purge result not logged"; fail=1; }
    unlockf "$T/.amnesia-trash/1/Downloads/x"
    AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" login >/dev/null 2>&1
    [ ! -e "$T/.amnesia/trash.failed" ] || { echo "FAILED: trash.failed not removed after success"; fail=1; }
    grep -q "trash emptied" "$T/.amnesia/trace.log" || { echo "FAILED: trash emptied not logged"; fail=1; }
else
    echo "SKIP: cannot make an undeletable file here (no chattr/chflags): failed-delete test skipped"
fi

# iCloud Desktop & Documents: keduanya dilewati, dicatat, dan terlihat di --skips / dry-run
mkdir -p "$T/Library/Mobile Documents/com~apple~CloudDocs/Desktop"
mk "Desktop/awan.txt"; mk "Documents/awan.txt"; mk "Downloads/awan.txt"
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" --skips > "$T/skips.txt"
grep -q "^LEWATI  ~/Desktop (icloud)" "$T/skips.txt" && grep -q "^LEWATI  ~/Documents (icloud)" "$T/skips.txt" \
    || { echo "FAILED: --skips does not list iCloud Desktop & Documents"; fail=1; }
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout --dry-run | grep -q "HAPUS  ~/Desktop/awan.txt" \
    && { echo "FAILED: dry-run lists Desktop although iCloud Desktop is on"; fail=1; }
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout >/dev/null 2>&1
here "Desktop/awan.txt"; here "Documents/awan.txt"; gone "Downloads/awan.txt"
grep -q "iCloud Desktop & Documents on (icloud-folder): Desktop and Documents skipped" "$T/.amnesia/trace.log" \
    || { echo "FAILED: iCloud skip not in trace.log"; fail=1; }
rm -rf "$T/Library/Mobile Documents"
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" --skips | grep -q "icloud" && { echo "FAILED: iCloud still detected"; fail=1; }
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout >/dev/null 2>&1
gone "Desktop/awan.txt"; gone "Documents/awan.txt"

# keeplock.sh: di luar macOS "unsupported", dan tidak merusak apa pun
cp "$DIR/keeplock.sh" "$T/.amnesia/"
printf 'KEEP_LOCK=1\n' > "$T/.amnesia/settings.conf"; mk "Keep/kunci.txt"
if [ "$(uname)" != Darwin ]; then
    [ "$(AMNESIA_HOME="$T" bash "$T/.amnesia/keeplock.sh" status)" = unsupported ] || { echo "FAILED: keeplock status"; fail=1; }
    AMNESIA_HOME="$T" bash "$T/.amnesia/keeplock.sh" lock >/dev/null && { echo "FAILED: keeplock lock claimed success"; fail=1; }
    [ "$(AMNESIA_HOME="$T" bash "$T/.amnesia/keeplock.sh" box-status)" = none ] || { echo "FAILED: box-status"; fail=1; }
    AMNESIA_HOME="$T" bash "$T/.amnesia/keeplock.sh" box-create 1 </dev/null 2>/dev/null && { echo "FAILED: box-create without hdiutil"; fail=1; }
    AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout >/dev/null 2>&1    # clean.sh memanggil keeplock: tetap jalan
    here "Keep/kunci.txt"; [ -f "$T/.amnesia/clean.done" ] || { echo "FAILED: clean.sh broke with keeplock.sh present"; fail=1; }
    echo "SKIP: Keep lock / Brankas need macOS (ACL, hdiutil): only the 'unsupported' path was tested"
fi
rm -f "$T/.amnesia/settings.conf" "$T/.amnesia/keeplock.sh"

[ $fail = 0 ] && echo "OK: all clean.sh tests passed" || exit 1
