#!/bin/bash
# Buat repo PUBLIC baru "amnesia" dengan riwayat bersih (cukup 1x).
# Repo private "amnesia" yang lama TIDAK dihapus dan tidak diubah: riwayatnya berisi file pribadi,
# jadi tidak dipakai untuk versi public. Kalau mau, hapus sendiri lewat GitHub > Settings.
# Setelah ini, github_backup.sh meng-update repo public.
set -euo pipefail
cd "$HOME/.amnesia"
NAME="${1:-amnesia}"
OWNER="$(gh api user -q .login)"
if git remote get-url public-done >/dev/null 2>&1; then echo "Sudah public: $(git remote get-url origin)"; exit 0; fi

bash app/github_backup.sh                       # simpan perubahan terakhir ke repo private dulu
V="$(defaults read "$PWD/app/Info" CFBundleShortVersionString)"

git branch -m main riwayat-private              # riwayat lama tetap ada di Mac (tidak dihapus)
git remote rename origin private
git checkout -q --orphan main                   # riwayat baru, mulai dari kode sekarang
git commit -q -m "Amnesia v$V"
gh repo create "$NAME" --public --source=. --push
gh repo set-default "$OWNER/$NAME"
git remote add public-done "https://github.com/$OWNER/$NAME" 2>/dev/null || true   # penanda: sudah dijalankan
bash app/github_backup.sh                       # deskripsi, topik & release di repo public
