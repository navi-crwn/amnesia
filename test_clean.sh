#!/bin/bash
# Tes aman clean.sh di home PALSU (tidak menyentuh home asli).  bash test_clean.sh
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mk() { mkdir -p "$T/$(dirname "$1")"; echo x > "$T/$1"; }

mkdir -p "$T/.amnesia/templates/Amnesia.app"
cp "$DIR/clean.sh" "$DIR/keep.example.conf" "$T/.amnesia/"   # tes memakai contoh (tanpa keep.conf pribadi)
# v5.25: daftar dasar sekarang umum; tes menambah baris pribadi contoh (VPN, alat terminal) seperti yang ditambah pengguna
printf '%s\n' 'Library/Application Support/com.nordvpn*' 'Library/Preferences/com.nordvpn*' 'Library/Group Containers/*surfshark*' '.homebrew' '.local/bin' >> "$T/.amnesia/keep.example.conf"
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
    # v5.24: agent.sh menunggu dengan "sleep 600 &". Setelah TERM, sleep itu tertinggal (yatim) dan dulu masih
    # memegang stdout tes ini: "bash test_clean.sh | cat" atau $(...) jadi menunggu 10 menit. Sekarang agent
    # tidak mewarisi stdout/stderr tes, dan sleep yang tertinggal dihentikan.
    HOME="$G" AMNESIA_APP="$1" bash "$G/.amnesia/agent.sh" </dev/null >/dev/null 2>&1 & local pid=$! k kids
    sleep 1; kids="$(pgrep -P $pid 2>/dev/null)"
    kill -TERM $pid; wait $pid 2>/dev/null
    for k in $kids; do case "$(ps -o comm= -p "$k" 2>/dev/null)" in *sleep) kill "$k" 2>/dev/null ;; esac; done
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
    # v5.25: di macOS purge_now melepas chflags uchg sendiri (v5.22), jadi di sana folder dibuat read-only (chmod 500)
    lockt() { chattr +i "$1" 2>/dev/null && return 0; [ "$(id -u)" != 0 ] && chmod 500 "$(dirname "$1")"; }
    unlockt() { chattr -i "$1" 2>/dev/null; chmod 700 "$(dirname "$1")" 2>/dev/null; true; }
    mkdir -p "$T/.amnesia-trash/1/Downloads"; echo x > "$T/.amnesia-trash/1/Downloads/x"; lockt "$T/.amnesia-trash/1/Downloads/x"
    AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" login >/dev/null 2>&1
    [ "$(cat "$T/.amnesia/trash.failed" 2>/dev/null)" = 1 ] || { echo "FAILED: trash.failed not written"; fail=1; }
    grep -q "trash: 1 items could not be deleted" "$T/.amnesia/trace.log" || { echo "FAILED: purge result not logged"; fail=1; }
    unlockt "$T/.amnesia-trash/1/Downloads/x"
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

# ---------------- v5.23 ----------------
# Claude di Keep List = chat Claude Code (~/.claude, ~/.claude.json, .backup) ikut disimpan
cp "$T/.amnesia/keep.example.conf" "$T/keep.bak"
printf 'Library/Application Support/Claude\n' >> "$T/.amnesia/keep.example.conf"
mk "Library/Application Support/Claude/config.json"; mk ".claude/projects/p/chat.jsonl"; mk ".claude.json"; mk ".claude.json.backup"
mk ".codex/x"
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout --dry-run | grep -q "\.claude" \
    && { echo "FAILED: dry-run lists Claude Code data although Claude is kept"; fail=1; }
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout >/dev/null 2>&1
here "Library/Application Support/Claude/config.json"; here ".claude/projects/p/chat.jsonl"; here ".claude.json"; here ".claude.json.backup"
gone ".codex"
grep -q "claude code data kept with Claude" "$T/.amnesia/trace.log" || { echo "FAILED: Claude Code keep not in trace.log"; fail=1; }
grep -q "chat.jsonl\|\.claude\.json\|projects/p" "$T/.amnesia/trace.log" && { echo "FAILED: trace.log contains a file name"; fail=1; }
cp "$T/keep.bak" "$T/.amnesia/keep.example.conf"
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" logout >/dev/null 2>&1
gone ".claude"; gone ".claude.json"; gone ".claude.json.backup"; gone "Library/Application Support/Claude"

# salinan "sebelum restore" (Profile Vault) yang lolos dari logout dibuang saat login setelah 3 hari
printf 'Library/Caches/Amnesia\n' >> "$T/.amnesia/keep.example.conf"
mk "Library/Caches/Amnesia/before-restore/.claude.json"; mk "Library/Caches/Amnesia/after-restore/x"
touch -t 202001010000 "$T/Library/Caches/Amnesia/before-restore"
AMNESIA_HOME="$T" bash "$T/.amnesia/clean.sh" login >/dev/null 2>&1
gone "Library/Caches/Amnesia/before-restore"; here "Library/Caches/Amnesia/after-restore/x"
grep -q "old before-restore copy removed (3 days)" "$T/.amnesia/trace.log" || { echo "FAILED: 3-day removal not in trace.log"; fail=1; }
cp "$T/keep.bak" "$T/.amnesia/keep.example.conf"

# ---------------- v5.24 ----------------
K="$T/.amnesia"
bad() { echo "FAILED: $1"; fail=1; }
rm -f "$K/settings.conf"

# 158: Keep List yang baik -> salinan keep.conf.last ditulis (utuh, tanpa file sementara tertinggal)
cp "$K/keep.example.conf" "$K/keep.conf"
mk "Downloads/h.txt"
AMNESIA_HOME="$T" bash "$K/clean.sh" logout >/dev/null 2>&1
gone "Downloads/h.txt"
cmp -s "$K/keep.conf" "$K/keep.conf.last" || bad "keep.conf.last not written after a good run"
[ ! -e "$K/keep.conf.last.tmp" ] || bad "keep.conf.last.tmp left behind"
case "$(ls -l "$K/keep.conf.last" 2>/dev/null)" in -rw-------*) ;; *) bad "keep.conf.last is not private (600)" ;; esac
# dry-run tidak menulis salinan
rm -f "$K/keep.conf.last"
AMNESIA_HOME="$T" bash "$K/clean.sh" logout --dry-run >/dev/null 2>&1
[ ! -e "$K/keep.conf.last" ] || bad "dry-run wrote keep.conf.last"
AMNESIA_HOME="$T" bash "$K/clean.sh" logout >/dev/null 2>&1

# 158: keep.conf hilang padahal salinan terakhir ada -> BERHENTI, tidak ada yang dihapus
rm -f "$K/keep.conf"; mk "Downloads/i.txt"
AMNESIA_HOME="$T" bash "$K/clean.sh" logout >/dev/null 2>&1; rc=$?
[ "$rc" = 3 ] || bad "missing Keep List: exit code $rc, expected 3"
here "Downloads/i.txt"
grep -qE "^[0-9-]+ [0-9:]+ logout: STOPPED keeplist-missing$" "$K/clean.log" || bad "clean.log has no STOPPED keeplist-missing"
tail -1 "$K/history.log" | grep -qE "	stopped	logout keeplist-missing$" || bad "history has no stopped line (missing)"
grep -q "clean logout: stop: keep list missing" "$K/trace.log" || bad "trace has no stop line (missing)"
AMNESIA_HOME="$T" bash "$K/clean.sh" logout --dry-run > "$T/dry2.txt" 2>&1; rc=$?
[ "$rc" = 0 ] || bad "stopped dry-run exit code $rc"
grep -qx "STOP  keeplist-missing" "$T/dry2.txt" || bad "dry-run has no STOP line"
grep -q "^--- dry-run (logout): 0 items would be deleted" "$T/dry2.txt" || bad "stopped dry-run footer"
grep -q "^HAPUS" "$T/dry2.txt" && bad "stopped dry-run still lists items"
AMNESIA_HOME="$T" bash "$K/clean.sh" now >/dev/null 2>&1; here "Downloads/i.txt"

# 158: keep.conf ada tapi tidak bisa dibaca (di sini: folder bernama keep.conf, juga berlaku untuk root) -> BERHENTI
mkdir "$K/keep.conf"
AMNESIA_HOME="$T" bash "$K/clean.sh" login >/dev/null 2>&1; rc=$?
[ "$rc" = 3 ] || bad "unreadable Keep List: exit code $rc, expected 3"
here "Downloads/i.txt"
grep -q " login: STOPPED keeplist-unreadable$" "$K/clean.log" || bad "clean.log has no STOPPED keeplist-unreadable"
tail -1 "$K/history.log" | grep -qE "	stopped	login keeplist-unreadable$" || bad "history has no stopped line (unreadable)"
grep -q "clean login: stop: keep list unreadable" "$K/trace.log" || bad "trace has no stop line (unreadable)"
rmdir "$K/keep.conf"
# link yang rusak = tidak bisa dibaca
ln -s "$T/tidak-ada.conf" "$K/keep.conf"
AMNESIA_HOME="$T" bash "$K/clean.sh" now >/dev/null 2>&1; rc=$?
[ "$rc" = 3 ] || bad "broken keep.conf link: exit code $rc, expected 3"; here "Downloads/i.txt"
rm -f "$K/keep.conf"
# tanpa izin baca (root selalu bisa membaca, jadi hanya dites sebagai user biasa)
if [ "$(id -u)" != 0 ]; then
    cp "$K/keep.example.conf" "$K/keep.conf"; chmod 000 "$K/keep.conf"
    AMNESIA_HOME="$T" bash "$K/clean.sh" now >/dev/null 2>&1; rc=$?
    [ "$rc" = 3 ] || bad "unreadable (chmod 000) Keep List: exit code $rc"; here "Downloads/i.txt"
    chmod 600 "$K/keep.conf"; rm -f "$K/keep.conf"
else
    echo "SKIP: running as root: the chmod 000 Keep List case was not tested (a folder named keep.conf was)"
fi
# kembali normal: keep.conf ada -> bersih lagi
cp "$K/keep.example.conf" "$K/keep.conf"
AMNESIA_HOME="$T" bash "$K/clean.sh" logout >/dev/null 2>&1; gone "Downloads/i.txt"

# 158: vault.py (restore) juga memakai keep.conf.last kalau keep.conf hilang, bukan contohnya
printf 'Downloads/hanya-di-last\n' > "$K/keep.conf.last"; rm -f "$K/keep.conf"
AMNESIA_HOME="$T" python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import vault; sys.exit(0 if vault.KeepRules().kept("Downloads/hanya-di-last") else 1)' "$DIR" \
    || bad "vault.py KeepRules does not use keep.conf.last"
mkdir "$K/keep.conf"
AMNESIA_HOME="$T" python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import vault; sys.exit(0 if vault.KeepRules().kept("Downloads/hanya-di-last") else 1)' "$DIR" \
    || bad "vault.py KeepRules does not fall back to keep.conf.last when keep.conf is unreadable"
# keep.conf tidak bisa dibaca dan tidak ada salinan: restore berhenti (bukan memakai contoh)
rm -f "$K/keep.conf.last"
AMNESIA_HOME="$T" python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import vault
try:
    vault.KeepRules()
except vault.VaultError:
    sys.exit(0)
sys.exit(1)' "$DIR" || bad "vault.py KeepRules uses the example when keep.conf is unreadable"
rmdir "$K/keep.conf"; cp "$K/keep.example.conf" "$K/keep.conf"
AMNESIA_HOME="$T" bash "$K/clean.sh" logout >/dev/null 2>&1

# 159: satu pengecekan path (safe_path). Fungsinya diambil dari clean.sh dan dites langsung.
SP="$T/safepath.sh"
{ echo 'set -u; shopt -s nullglob dotglob'
  sed -n '/^norm_path() {/,/^}/p; /^via_link() {/,/^}/p; /^safe_path() {/,/^}/p' "$DIR/clean.sh"
  echo 'H="$1"; A="$H/.amnesia"; TRASHROOT="$H/.amnesia-trash"; KD="$H/Keep"; shift'
  echo 'safe_path "$1"'; } > "$SP"
mkdir -p "$T/Keep" "$T/Documents/real" "$T/Downloads/ok"; ln -sfn "$T/Keep" "$T/Documents/lewat-link"
refuse() { AMNESIA_HOME="$T" bash "$SP" "$T" "$1" && bad "safe_path allowed: $1"; }
allow()  { AMNESIA_HOME="$T" bash "$SP" "$T" "$1" || bad "safe_path refused: $1"; }
refuse ""; refuse "Downloads/ok"; refuse "./Downloads"; refuse "$T/Downloads/../.amnesia"; refuse "$T/./Downloads/ok"
refuse "$T/Downloads/.."; refuse "$T"; refuse "$T/"; refuse "$T//"; refuse "$T/.amnesia"; refuse "$T//.amnesia//"
refuse "$T/.amnesia/keep.conf"; refuse "$T/Keep"; refuse "$T/Keep/penting.txt"; refuse "$T/KEEP"; refuse "$T/keep/x"
refuse "$T/.amnesia-trash"; refuse "$T/.amnesia-trash/1"; refuse "/"; refuse "/etc/passwd"; refuse "/tmp"
refuse "${T%/*}"; refuse "/Applications/Foo.app"; refuse "$T/Documents/lewat-link/penting.txt"
allow "$T/Downloads/ok"; allow "$T//Downloads///ok/"; allow "$T/Documents/real"; allow "$T/Documents/lewat-link"
allow "$T/.amnesia-trashy"; allow "$T/Keeper"
rm -f "$T/Documents/lewat-link"; rm -rf "$T/Documents/real" "$T/Downloads/ok"
# Keep folder di dalam folder yang dibersihkan (mis. Keep = Downloads): isinya tidak pernah dihapus
printf 'KEEP_DIR=~/Downloads\n' > "$K/settings.conf"; mk "Downloads/k.txt"
AMNESIA_HOME="$T" bash "$K/clean.sh" logout --dry-run | grep -q "HAPUS  ~/Downloads/k.txt" && bad "dry-run lists a file inside the Keep folder"
AMNESIA_HOME="$T" bash "$K/clean.sh" logout >/dev/null 2>&1
here "Downloads/k.txt"
rm -f "$K/settings.conf" "$T/Downloads/k.txt"; rm -rf "$T/Desktop/Downloads"
# purge_now hanya pernah menghapus folder bernama .amnesia-trash
PN="$T/purge.sh"
{ sed -n '/^purge_now() {/,/^}/p' "$DIR/clean.sh"; echo 'purge_now "$@"'; } > "$PN"
mkdir -p "$T/bukan-sampah/x"
bash "$PN" "$T/bukan-sampah" "$T/pn.log" "$T/pn.failed" now; here "bukan-sampah/x"
mkdir -p "$T/.amnesia-trash/simpan"
bash "$PN" "$T/bukan-sampah/../.amnesia-trash" "$T/pn.log" "$T/pn.failed" now; here ".amnesia-trash/simpan"
bash "$PN" "$T//.amnesia-trash" "$T/pn.log" "$T/pn.failed" now; here ".amnesia-trash/simpan"
rm -rf "$T/.amnesia-trash"
mkdir -p "$T/luar-sampah/y"
mkdir -p "$T/link/"; ln -sfn "$T/luar-sampah" "$T/link/.amnesia-trash"
bash "$PN" "$T/link/.amnesia-trash" "$T/pn.log" "$T/pn.failed" now; here "luar-sampah/y"
mkdir -p "$T/sub/.amnesia-trash/z"; bash "$PN" "$T/sub/.amnesia-trash" "$T/pn.log" "$T/pn.failed" now; gone "sub/.amnesia-trash"
rm -rf "$T/bukan-sampah" "$T/luar-sampah" "$T/link" "$T/sub" "$T/pn.log" "$T/pn.failed"

# 159: katalog perintah terlarang. rm / mv / rmdir / unlink / find -delete hanya boleh di dalam fungsi yang
# disetujui (amn_rm, amn_mv, trash_or_rm, purge_now). Gagal kalau clean.sh menambah penghapusan di tempat lain.
catalog() {
    awk '
        /^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { fn = $1; sub(/\(\).*/, "", fn) }
        {
            line = $0
            sub(/^[ \t]*#.*/, "", line); sub(/[ \t]+#[ \t].*$/, "", line)
            if (line ~ /(^|[^A-Za-z0-9_.\/-])(rm|mv|rmdir|unlink|shred|srm)([ \t]|$)/ || line ~ /-delete([ \t]|$)/) {
                if (fn != "amn_rm" && fn != "amn_mv" && fn != "trash_or_rm" && fn != "purge_now") print NR ": " $0
            }
        }
        /^\}/ { fn = "" }' "$1"
}
out="$(catalog "$DIR/clean.sh")"
[ -z "$out" ] || { bad "clean.sh deletes outside the approved helpers:"; printf '%s\n' "$out"; }
# kendali: katalog memang menangkap penghapusan baru
{ cat "$DIR/clean.sh"; printf 'wipe_all() {\n    rm -rf "$H/x"\n}\nfind "$H/y" -delete\nmv "$H/a" /tmp/\n'; } > "$T/mutant.sh"
[ "$(catalog "$T/mutant.sh" | wc -l | tr -d ' ')" = 3 ] || bad "catalog test does not catch new deletes"
# trash_or_rm memanggil safe_path sebelum apa pun
sed -n '/^trash_or_rm() {/,/^}/p' "$DIR/clean.sh" | sed -n '2,3p' | grep -q "safe_path" || bad "trash_or_rm does not check safe_path first"

# 161: folder yang sedang dipakai app yang terbuka dilewati saat login/now, tidak saat logout
if command -v lsof >/dev/null 2>&1; then
    mk "Downloads/sibuk/data.db"; mk "Downloads/bebas.txt"; mk "Library/Caches/com.terbuka/c/x"; mk "Library/Caches/com.tutup/x"
    ( exec 3<"$T/Downloads/sibuk/data.db" 4<"$T/Library/Caches/com.terbuka/c/x"; exec sleep 60 ) </dev/null >/dev/null 2>&1 &
    HOLD=$!; sleep 1
    AMNESIA_HOME="$T" bash "$K/clean.sh" now --dry-run > "$T/dry3.txt" 2>&1
    grep -qx "LEWATI  ~/Downloads/sibuk (in use)" "$T/dry3.txt" || bad "dry-run does not show the in-use folder"
    AMNESIA_HOME="$T" bash "$K/clean.sh" now >/dev/null 2>&1
    here "Downloads/sibuk/data.db"; gone "Downloads/bebas.txt"
    here "Library/Caches/com.terbuka/c/x"; gone "Library/Caches/com.tutup"
    grep -q "clean now: skip in use (in Downloads)" "$K/trace.log" || bad "in-use skip not in trace.log"
    grep -q "clean now: in use: 2 skipped (wiped next time)" "$K/trace.log" || bad "in-use count not in trace.log"
    grep -q "sibuk\|data.db\|terbuka" "$K/trace.log" && bad "trace.log contains a file name (in use)"
    AMNESIA_HOME="$T" bash "$K/clean.sh" logout >/dev/null 2>&1      # logout: tidak dicek (waktu terbatas)
    gone "Downloads/sibuk"; gone "Library/Caches/com.terbuka"
    kill "$HOLD" 2>/dev/null; wait "$HOLD" 2>/dev/null
else
    echo "SKIP: no lsof here: the in-use test was skipped"
fi

# 160: daftar patokan app yang tidak bisa dibaca = tidak ada app yang dihapus
mkdir -p "$T/Applications/Baru2.app"; mkdir "$K/apps_baseline.txt"
printf 'REMOVE_NEW_APPS=1\n' > "$K/settings.conf"
AMNESIA_HOME="$T" bash "$K/clean.sh" logout >/dev/null 2>&1
here "Applications/Baru2.app"
rmdir "$K/apps_baseline.txt"; rm -f "$K/settings.conf"; rm -rf "$T/Applications/Baru2.app"
rm -f "$K/keep.conf" "$K/keep.conf.last"

# ===== v5.25 modes =====
# Mode Amnesia: preset di presets/<id>.conf, ditulis ke keep.conf sebagai bagian bertanda
# "# amnesia-mode: <id> begin" ... "# amnesia-mode end". Home palsu sendiri (modes-home), tidak memakai $K.
M="$T/modes-home"; MA="$M/.amnesia"
# macOS punya perintah timeout hanya lewat Homebrew coreutils: tanpa itu, jalankan saja tanpa batas waktu
command -v timeout >/dev/null 2>&1 || timeout() { shift; "$@"; }
mkdir -p "$MA"; cp "$DIR/clean.sh" "$DIR/keep.example.conf" "$MA/"; mkdir -p "$MA/presets"; cp "$DIR"/presets/*.conf "$MA/presets/"
mm() { mkdir -p "$M/$(dirname "$1")"; echo x > "$M/$1"; }
nc() { grep -v '^[[:space:]]*#' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$'; }   # baris yang menyimpan sesuatu
# presets: ada, tidak kosong, tanpa penanda mode; balanced = keep.example.conf (baris yang sama, urutan sama)
for id in full balanced light; do
    [ -s "$DIR/presets/$id.conf" ] || bad "presets/$id.conf is missing or empty"
    [ "$(nc "$DIR/presets/$id.conf" | wc -l | tr -d ' ')" -gt 0 ] || bad "presets/$id.conf has no keep lines"
    grep -q '^[[:space:]]*# amnesia-mode' "$DIR/presets/$id.conf" && bad "presets/$id.conf contains a mode marker"
done
[ "$(nc "$DIR/keep.example.conf")" = "$(nc "$DIR/presets/balanced.conf")" ] || bad "presets/balanced.conf differs from keep.example.conf"
[ "$(sed -n '/^# --- Amnesia: scheduled backup/,$p' "$DIR/keep.example.conf")" = "$(grep -v '^##' "$DIR/presets/balanced.conf")" ] \
    || bad "presets/balanced.conf is not byte for byte the end of keep.example.conf"
[ "$(nc "$DIR/presets/full.conf" | head -4 | tr '\n' '|')" = "keychain:Amnesia Backup|keychain:Amnesia VirusTotal|.config/rclone|keychain:* Safe Storage|" ] \
    || bad "presets/full.conf does not start with the 4 required lines"
# v5.25 (pemilik 26 Okt): preset umum untuk semua orang, tanpa app/VM pribadi (itu dipilih sendiri di Keep List)
for id in full balanced light; do
    grep -qiE 'nordvpn|surfshark|utmapp|parallels|virtualbox|photoslibrary' "$DIR/presets/$id.conf" && bad "presets/$id.conf has personal app or VM lines"
done
# v5.25 (audit): every preset lists the 4 required lines itself, so taking off a wider line (keychain:*, .config) never drops them
for id in balanced light; do
    for r in "keychain:Amnesia Backup" "keychain:Amnesia VirusTotal" ".config/rclone" "keychain:* Safe Storage"; do
        nc "$DIR/presets/$id.conf" | grep -qxF "$r" || bad "presets/$id.conf does not list the required line $r"
    done
done
grep -q 'static let requiredLines = \["keychain:Amnesia Backup", "keychain:Amnesia VirusTotal", ".config/rclone", "keychain:\* Safe Storage"\]' \
    "$DIR/app/Amnesia.swift" || bad "Keep.requiredLines in Amnesia.swift differs from presets/full.conf"
# build.sh bundelt preset ke engine/presets
grep -q 'cp ../presets/\*.conf "$R/engine/presets/"' "$DIR/app/build.sh" || bad "build.sh does not bundle presets/"

# isi home palsu
for f in Desktop/a.txt Documents/b.txt Downloads/c.zip Library/Caches/foo/x Library/Logs/l/x \
         "Library/Saved Application State/s.savedState/x" .Trash/t .zsh_history .zsh_sessions/s1 \
         "Library/Application Support/X/data" "Library/Application Support/com.nordvpn.macos/token" \
         Library/Containers/com.whatsapp/d Library/Preferences/com.x.plist Library/Cookies/c.binarycookies \
         .config/other/z .config/rclone/rclone.conf .ssh/id .local/bin/tool .gitconfig Documents/mine/m.txt; do mm "$f"; done
mm "Library/Containers/com.utmapp.UTM/Data/Documents/win.utm/disk.img"; mm "Library/Group Containers/WDNLXAD4W8.com.utmapp.UTM/x"
mm "Pictures/Photos Library.photoslibrary/database/x"; mm "Pictures/other.jpg"
block() {   # block <id> [baris sendiri...] -> keep.conf versi mode
    echo "# amnesia-mode: $1 begin"
    echo "# Amnesia writes the lines between these markers when you pick a mode. Put your own lines below the end marker."
    grep -v '^##' "$MA/presets/$1.conf"
    echo "# amnesia-mode end"; shift
    [ $# -gt 0 ] && { echo; printf '%s\n' "$@"; }
}
modedry() { AMNESIA_HOME="$M" timeout 300 bash "$MA/clean.sh" logout --dry-run --keep-file="$1" 2>&1; }
wiped() { grep -qF "HAPUS  ~/$2" "$1" || bad "mode $3: not wiped: $2"; }
keptm() { grep -qF "HAPUS  ~/$2" "$1" && bad "mode $3: wiped but should be kept: $2"; }
for id in full balanced light; do
    block "$id" "Documents/mine" > "$M/k-$id.conf"
    modedry "$M/k-$id.conf" > "$M/dry-$id.txt"
    grep -q '^--- dry-run (logout)' "$M/dry-$id.txt" || bad "mode $id: dry-run with --keep-file did not finish"
    grep -q '^STOP' "$M/dry-$id.txt" && bad "mode $id: dry-run stopped"
    for w in Desktop/a.txt Downloads/c.zip Documents/b.txt Library/Caches/foo Library/Logs/l \
             "Library/Saved Application State/s.savedState" .Trash/t .zsh_history .zsh_sessions; do wiped "$M/dry-$id.txt" "$w" "$id"; done
    keptm "$M/dry-$id.txt" "Documents/mine" "$id"          # baris sendiri di luar bagian mode
    keptm "$M/dry-$id.txt" ".config/rclone" "$id"          # Amnesia sendiri (semua mode)
done
f="$M/dry-full.txt";     wiped "$f" "Library/Application Support/X" full; wiped "$f" ".config/other" full; wiped "$f" ".ssh" full
                         wiped "$f" "Library/Application Support/com.nordvpn.macos" full; wiped "$f" ".local" full
f="$M/dry-balanced.txt"; wiped "$f" "Library/Application Support/X" balanced; keptm "$f" ".ssh" balanced
                         wiped "$f" "Library/Application Support/com.nordvpn.macos" balanced; wiped "$f" ".local" balanced
                         keptm "$f" ".gitconfig" balanced
                         wiped "$f" "Library/Containers/com.whatsapp" balanced
f="$M/dry-light.txt";    keptm "$f" "Library/Application Support/X" light; keptm "$f" ".config" light; keptm "$f" ".ssh" light
                         keptm "$f" "Library/Containers/com.whatsapp" light; keptm "$f" "Library/Preferences/com.x.plist" light
                         keptm "$f" "Library/Cookies" light; keptm "$f" ".gitconfig" light
# balanced dengan bagian mode = hasil yang sama dengan keep.example.conf tanpa bagian mode (pengguna lama tidak melihat beda)
modedry "$MA/keep.example.conf" | grep '^HAPUS' | sort > "$M/dry-example.txt"
grep '^HAPUS' "$M/dry-balanced.txt" | grep -v 'Documents/mine' | sort > "$M/dry-bal2.txt"
block balanced > "$M/k-bal-only.conf"; modedry "$M/k-bal-only.conf" | grep '^HAPUS' | sort > "$M/dry-bal3.txt"
cmp -s "$M/dry-example.txt" "$M/dry-bal3.txt" || bad "balanced mode block wipes something different from keep.example.conf"
# --keep-file: hanya bersama --dry-run, path wajib ada, tidak pernah menghapus
AMNESIA_HOME="$M" timeout 300 bash "$MA/clean.sh" logout --keep-file="$M/k-full.conf" >/dev/null 2>&1
[ $? = 2 ] || bad "--keep-file without --dry-run does not exit 2"
AMNESIA_HOME="$M" timeout 300 bash "$MA/clean.sh" logout --dry-run --keep-file= >/dev/null 2>&1
[ $? = 2 ] || bad "--keep-file= (empty) does not exit 2"
[ -e "$M/Desktop/a.txt" ] && [ -e "$M/Library/Application Support/X/data" ] || bad "--keep-file without --dry-run deleted something"
[ -e "$MA/keep.conf.last" ] && bad "--keep-file wrote keep.conf.last"
# pratinjau dengan Keep List yang tidak bisa dibaca = STOP (tidak pernah "Keep List kosong")
mkdir "$M/k-dir.conf"; modedry "$M/k-dir.conf" | grep -q '^STOP  keeplist-unreadable' || bad "--keep-file on an unreadable file does not stop"
rmdir "$M/k-dir.conf"
# pembersihan sungguhan dengan bagian mode Ringan di keep.conf: penanda hanya komentar biasa
block light "Documents/mine" > "$MA/keep.conf"
AMNESIA_HOME="$M" timeout 300 bash "$MA/clean.sh" logout >/dev/null 2>&1
for g in Desktop/a.txt Downloads/c.zip Documents/b.txt Library/Caches/foo .zsh_history .zsh_sessions .Trash/t; do
    [ -e "$M/$g" ] && bad "light logout: still there $g"
done
for h in "Library/Application Support/X/data" .config/other/z .config/rclone/rclone.conf .ssh/id Documents/mine/m.txt \
         Library/Preferences/com.x.plist Library/Containers/com.whatsapp/d; do
    [ -e "$M/$h" ] || bad "light logout: deleted $h"
done

# Ganti mode: tiruan logika Keep.applyMode (Amnesia.swift, tidak bisa dites tanpa Mac). Aturan kontrak v5.25:
# baris sendiri di luar bagian mode tidak pernah hilang, bagian rusak = ditolak, preset hilang/kosong = ditolak.
cat > "$T/modesim.py" <<'PY'
import sys, os
BEGIN, END = "# amnesia-mode: %s begin", "# amnesia-mode end"
HINT = "# Amnesia writes the lines between these markers when you pick a mode. Put your own lines below the end marker."
def lines(t):
    l = [x[:-1] if x.endswith("\r") else x for x in t.split("\n")]
    if l and l[-1] == "": l.pop()
    return l
def keep(l): return [x.strip() for x in l if x.strip() and not x.strip().startswith("#")]
def preset(d, i):
    try: t = open(os.path.join(d, i + ".conf"), encoding="utf-8").read()
    except Exception: return None
    l = [x for x in lines(t) if not x.startswith("##")]
    while l and not l[0].strip(): l.pop(0)
    while l and not l[-1].strip(): l.pop()
    if any(x.strip().startswith("# amnesia-mode") for x in l): return None
    return l if keep(l) else None
def block(l):
    b, e, other = [], [], False
    for i, x in enumerate(l):
        s = x.strip()
        if not s.startswith("# amnesia-mode"): continue
        if s == END: e.append(i)
        elif s.startswith("# amnesia-mode:") and s.endswith(" begin"): b.append(i)
        else: other = True
    if not b and not e and not other: return "none", None
    if other or len(b) != 1 or len(e) != 1 or b[0] > e[0]: return "broken", None
    return "ok", (b[0], e[0])
def apply(text, i, d, rm=()):
    l = lines(text); st, be = block(l)
    if st == "broken": return None
    p = None
    if i != "custom":
        p = preset(d, i)
        if p is None: return None
    rm = set(x.strip() for x in rm)
    mig = False
    if st == "ok":
        inner = l[be[0] + 1:be[1]]; own = l[:be[0]] + l[be[1] + 1:]
    elif i != "custom" and preset(d, "balanced") is not None:
        bal = set(x.strip() for x in preset(d, "balanced") if x.strip())
        own = [x for x in l if x.strip() not in bal]; mig = len(own) != len(l); inner = []
    else:
        own, inner = l, []
    mode = i
    if p is not None and rm & set(keep(p)): mode, top = "custom", p
    elif p is not None: top = [BEGIN % i, HINT] + p + [END]
    else: top = [x for x in inner if x.strip() != HINT]
    if mode == "custom": top = [x for x in top if x.strip() not in rm]
    own = [x for x in own if x.strip() not in rm]
    if mig:
        t = []
        for x in own:
            if not (not x.strip() and (not t or not t[-1].strip())): t.append(x)
        own = t
    new = top + ([""] if top and own and own[0].strip() else []) + own
    if mode != "custom" and not keep(new): return None
    return mode, ("\n".join(new) + "\n") if new else ""
cmd, path, i, d = sys.argv[1:5]
r = apply(open(path, encoding="utf-8").read(), i, d, sys.argv[5:])
if r is None: print("REFUSED"); sys.exit(3)
open(path, "w", encoding="utf-8").write(r[1]); print(r[0])
PY
sim() { timeout 60 python3 "$T/modesim.py" apply "$@"; }
# pengguna lama: keep.example.conf + baris sendiri -> balanced: baris sama pindah ke bagian mode, baris sendiri tetap
{ cat "$DIR/keep.example.conf"; printf 'Documents/mine\nkeychain:My VPN\n'; } > "$M/sw.conf"
[ "$(sim "$M/sw.conf" balanced "$MA/presets")" = balanced ] || bad "switch to balanced failed"
[ "$(head -1 "$M/sw.conf")" = "# amnesia-mode: balanced begin" ] || bad "mode block is not at the top"
[ "$(nc "$M/sw.conf" | sort)" = "$( { nc "$DIR/keep.example.conf"; printf 'Documents/mine\nkeychain:My VPN\n'; } | sort)" ] \
    || bad "migration to balanced changed what is kept"
# balanced -> full -> light -> balanced: baris sendiri selalu tetap ada
for id in full light balanced; do
    sim "$M/sw.conf" "$id" "$MA/presets" >/dev/null || bad "switch to $id failed"
    grep -qx 'Documents/mine' "$M/sw.conf" && grep -qx 'keychain:My VPN' "$M/sw.conf" || bad "own lines lost when switching to $id"
    [ "$(grep -c '^# amnesia-mode' "$M/sw.conf")" = 2 ] || bad "switch to $id: not exactly one mode block"
    [ "$(sed -n '/^# amnesia-mode: /,/^# amnesia-mode end/p' "$M/sw.conf" | nc /dev/stdin)" = "$(nc "$MA/presets/$id.conf")" ] \
        || bad "switch to $id: block is not the preset"
done
# baris sendiri yang dicentang ("Berhenti menyimpan baris ini juga") hilang, yang lain tetap
sim "$M/sw.conf" full "$MA/presets" "keychain:My VPN" >/dev/null
grep -qx 'keychain:My VPN' "$M/sw.conf" && bad "ticked own line not removed"
grep -qx 'Documents/mine' "$M/sw.conf" || bad "unticked own line removed"
# baris preset dicentang -> jadi custom (penanda dibuang, sisa baris tetap)
[ "$(sim "$M/sw.conf" full "$MA/presets" ".config/rclone")" = custom ] || bad "removing a preset line does not give custom"
grep -q '^# amnesia-mode' "$M/sw.conf" && bad "custom still has mode markers"
grep -qx 'keychain:Amnesia Backup' "$M/sw.conf" || bad "custom lost the other preset lines"
# preset hilang / kosong / berisi penanda: ditolak, keep.conf tidak berubah (tidak pernah Keep List kosong)
sim "$M/sw.conf" light "$MA/presets" >/dev/null; cp "$M/sw.conf" "$M/sw.before"
mkdir -p "$M/bad-presets"; cp "$MA/presets/balanced.conf" "$M/bad-presets/"
sim "$M/sw.conf" full "$M/bad-presets" >/dev/null && bad "missing preset was applied"
printf '## only notes\n# and a comment\n\n' > "$M/bad-presets/full.conf"
sim "$M/sw.conf" full "$M/bad-presets" >/dev/null && bad "empty preset was applied"
printf '# amnesia-mode end\n.ssh\n' > "$M/bad-presets/light.conf"
sim "$M/sw.conf" light "$M/bad-presets" >/dev/null && bad "preset with a marker was applied"
cmp -s "$M/sw.conf" "$M/sw.before" || bad "a refused mode switch changed keep.conf"
[ "$(nc "$M/sw.conf" | wc -l | tr -d ' ')" -gt 0 ] || bad "keep.conf became empty"
# bagian mode rusak (2x begin, tanpa end, end sebelum begin): ditolak
for broken in "begin begin end" "begin" "end begin"; do
    : > "$M/br.conf"
    for w in $broken; do [ "$w" = begin ] && echo "# amnesia-mode: full begin" >> "$M/br.conf" || echo "# amnesia-mode end" >> "$M/br.conf"; done
    echo ".ssh" >> "$M/br.conf"; cp "$M/br.conf" "$M/br.before"
    sim "$M/br.conf" balanced "$MA/presets" >/dev/null && bad "damaged mode block ($broken) was accepted"
    cmp -s "$M/br.conf" "$M/br.before" || bad "damaged mode block ($broken) changed keep.conf"
done
# kustom dari mode: penanda dibuang, isi yang disimpan sama persis
block light "Documents/mine" > "$M/cu.conf"; nc "$M/cu.conf" > "$M/cu.before"
[ "$(sim "$M/cu.conf" custom "$MA/presets")" = custom ] || bad "switch to custom failed"
nc "$M/cu.conf" | cmp -s - "$M/cu.before" || bad "switch to custom changed what is kept"
grep -q '^# amnesia-mode' "$M/cu.conf" && bad "custom kept the markers"
# Swift: logika sama ada di Amnesia.swift (nama fungsi kontrak), dry-run pratinjau memakai --keep-file
for fn in "static func applyMode(_ id: String, extraAdd: \[String\] = \[\], extraRemove: \[String\] = \[\]) -> ModePreview" \
          "static func commitMode(_ p: ModePreview) -> Bool" "static func currentMode() -> String" \
          "static func presetLines(_ id: String) -> \[String\]?" '"--keep-file=" + tmp' 'case "mode":'; do
    grep -q "$fn" "$DIR/app/Amnesia.swift" || bad "Amnesia.swift is missing: $fn"
done
rm -rf "$M"
# ===== end v5.25 modes =====

# ===== v5.25 temuan uji Mac (item 187, 189-197) =====
# 190: file dot di home (.zshrc, .zprofile, .gitconfig) tidak pernah dihapus clean.sh, jadi pratinjau mode tidak boleh
# menulisnya "dihapus". Bukti di home palsu: Keep List tanpa baris itu -> dry-run tetap tidak menyebutnya.
Z=$(mktemp -d); mkdir -p "$Z/.amnesia"; cp "$DIR/clean.sh" "$Z/.amnesia/"
for f in .zshrc .zprofile .gitconfig; do echo x > "$Z/$f"; done
mkdir -p "$Z/Desktop"; echo x > "$Z/Desktop/d.txt"
printf 'keychain:* Safe Storage\n' > "$Z/k.conf"
AMNESIA_HOME="$Z" bash "$Z/.amnesia/clean.sh" logout --dry-run --keep-file="$Z/k.conf" > "$Z/dry.txt" 2>/dev/null
grep -q "Desktop/d.txt" "$Z/dry.txt" || bad "190: dry-run without .zshrc line did not run"
grep -Eq '\.zshrc|\.zprofile|\.gitconfig' "$Z/dry.txt" && bad "190: dry-run lists a home dot file (preview would be right to say wiped)"
for f in .zshrc .zprofile .gitconfig; do [ -f "$Z/$f" ] || bad "190: dry-run deleted $f"; done
rm -rf "$Z"
SW="$DIR/app/Amnesia.swift"
grep -q "static func lineWipes" "$SW" && grep -q "removedIdle" "$SW" || bad "190: Swift preview does not separate lines that wipe nothing"
# 187: VM dan Foto tidak lagi ditambahkan diam-diam; saran dengan peringatan + tombol Keep
grep -rq "VMKeep.applyDefaults" "$DIR/app/" && bad "187: VMKeep.applyDefaults (silent add) is still called"
grep -q 'for a in appleItems where a.id != "photos" { set(a, true) }' "$SW" || bad "187: Photos is still switched on by itself"
[ "$(grep -c 'KeepSuggestCard {' "$SW")" -ge 2 ] || bad "187: the Keep suggestion card is not on the Keep List and What Gets Deleted pages"
# 189: membuka halaman Keep List tidak menulis settings.conf; AMNESIA_MODE hanya ditulis saat mode diganti
[ "$(grep -c 'Config.set("AMNESIA_MODE"' "$SW")" = 1 ] || bad "189: AMNESIA_MODE is written outside commitMode"
# 191 + 195: Pengaturan berkelompok, pencarian menggulir ke atas, Lanjutan tertutup sampai dibuka
grep -q 'proxy.scrollTo("top", anchor: .top)' "$SW" || bad "191: Settings search does not scroll to the first hit"
for g in logoutGroup keepGroup appGroup safetyGroup advancedToggle; do grep -q "private var $g" "$SW" || bad "195: Settings group $g missing"; done
# 196: "Jangan tampilkan lagi" di dialog Disalin (Tanya AI)
grep -q 'AI_COPIED_HIDE' "$DIR/app/AskAI.swift" || bad "196: Ask AI Copied dialog has no Don't show again"
# 197: setiap sakelar/pilihan tanpa judul dan setiap tombol yang hanya berisi ikon punya label aksesibilitas
a11y="$(python3 - "$DIR/app" <<'PY'
import glob, re, sys
out = []
for f in sorted(glob.glob(sys.argv[1] + "/*.swift")):
    L = open(f, encoding="utf-8").read().split("\n")
    for i, l in enumerate(L):
        icon_btn = re.search(r'Button\b.*label:\s*\{\s*Image\(', l) or (
            re.search(r'Button\b.*label:\s*\{\s*$', l) and i + 1 < len(L) and re.match(r'\s*Image\(', L[i + 1])
            and not any('Text(' in L[k] or 'Label(' in L[k] for k in range(i + 1, min(i + 4, len(L)))))
        if icon_btn or 'Toggle("",' in l or 'Picker("",' in l:
            if 'accessibilityLabel' not in "\n".join(L[i:i + 12]):
                out.append(f"{f.rsplit('/', 1)[1]}:{i + 1}")
print(" ".join(out))
PY
)"
[ -z "$a11y" ] || bad "197: no accessibility label at $a11y"
# 194: perintah Terminal memakai satuan desimal seperti app (1 MB = 1000 KB)
grep -q 'b >= 1e6' "$DIR/bin/amnesia" || bad "194: bin/amnesia still uses 1024 for MB"
# ===== end v5.25 temuan uji =====

[ $fail = 0 ] && echo "OK: all clean.sh tests passed" || exit 1
