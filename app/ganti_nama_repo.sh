#!/bin/bash
# Semua jadi "amnesia" dalam 1x jalan, tanpa ketik apa pun:
#   bash ~/.amnesia/app/ganti_nama_repo.sh
#   1. cek Amnesia sedang Off (update app hanya boleh saat Off)
#   2. repo GitHub amnesia-mac -> amnesia (dilewati kalau sudah)
#   3. build + pasang app v5.18.2 (link di app sudah ke repo baru)
#   4. github_backup.sh: commit, push, Release, website (navi-crwn.github.io/amnesia, + /win/), Homebrew
#   5. rapikan Releases: sisakan hanya versi terbaru
# Link github.com/navi-crwn/amnesia-mac tetap dialihkan GitHub ke repo baru. Jangan pernah buat repo baru bernama amnesia-mac.
set -euo pipefail
cd "$HOME/.amnesia"
NEW=amnesia

if [ -f "$HOME/Library/LaunchAgents/com.amnesia.agent.plist" ]; then
  echo "Amnesia sedang ON. Klik ikon Amnesia di menu bar -> Turn Off, lalu jalankan perintah ini lagi."
  echo "Setelah selesai, Turn On lagi. Belum ada yang diubah."
  exit 1
fi

command -v gh >/dev/null || { echo "gh is missing. Run: brew install gh"; exit 1; }
gh auth status >/dev/null 2>&1 || gh auth login --web --git-protocol https
OWNER="$(gh api user -q .login)"
NOW="$(gh repo view --json name -q .name)"
echo "1/4  Repo: $OWNER/$NOW"
if [ "$NOW" != "$NEW" ]; then
  if gh api "repos/$OWNER/$NEW" -q .name 2>/dev/null | grep -qx "$NEW"; then
    echo "GAGAL: repo $OWNER/$NEW sudah ada. Hapus atau ganti namanya dulu di github.com."; exit 1
  fi
  gh repo rename "$NEW" --yes
  echo "     renamed to $OWNER/$NEW"
fi
git remote set-url origin "https://github.com/$OWNER/$NEW.git"

echo "2/4  Building the app..."
bash app/build.sh

echo "3/4  GitHub..."
bash app/github_backup.sh

echo "4/4  Tidying Releases..."
bash app/rapikan_release.sh --yes

echo
echo "SELESAI. Jangan lupa Turn On Amnesia lagi."
echo "  Repo:    https://github.com/$OWNER/$NEW"
echo "  Website: https://$OWNER.github.io/$NEW/   (Windows: https://$OWNER.github.io/$NEW/win/)"
