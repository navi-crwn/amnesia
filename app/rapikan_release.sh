#!/bin/bash
# Rapikan halaman Releases di GitHub: sisakan HANYA release versi sekarang, hapus release lama (beserta tag-nya).
# Catatan release versi sekarang diisi ulang dari CHANGELOG.md oleh github_backup.sh, jadi jalankan itu dulu.
#   bash ~/.amnesia/app/rapikan_release.sh          (tanya dulu, ketik HAPUS)
#   bash ~/.amnesia/app/rapikan_release.sh --yes    (langsung, dipakai ganti_nama_repo.sh)
# Tidak menyentuh kode, commit, atau file di Mac kamu. Release lama tidak bisa dikembalikan setelah dihapus,
# jadi skrip ini menunjukkan daftarnya dulu dan baru jalan setelah kamu ketik HAPUS.
set -e
cd "$(dirname "$0")/.."
V="v$(defaults read "$PWD/app/Info" CFBundleShortVersionString)"
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

echo "Repo: $REPO"
echo "Release yang tetap ada: $V"
gh release view "$V" >/dev/null 2>&1 || { echo "GAGAL: release $V belum ada di GitHub. Jalankan dulu: bash ~/.amnesia/app/github_backup.sh"; exit 1; }

OLD="$(gh release list --limit 200 --json tagName -q '.[].tagName' | grep -vx "$V" || true)"
if [ -z "$OLD" ]; then echo "Sudah rapi: cuma ada $V."; exit 0; fi
echo
echo "Release lama yang akan dihapus ($(echo "$OLD" | wc -l | tr -d ' ')):"
echo "$OLD" | sed 's/^/  - /'
echo
echo "File .dmg di release lama ikut hilang. Kode dan riwayat commit TIDAK berubah."
if [ "${1:-}" != "--yes" ]; then
  read -r -p "Ketik HAPUS untuk lanjut (atau Enter untuk batal): " OK
  [ "$OK" = "HAPUS" ] || { echo "Dibatalkan, tidak ada yang dihapus."; exit 0; }
fi

for t in $OLD; do
  gh release delete "$t" --yes --cleanup-tag && echo "  dihapus: $t"
done
echo
echo "Selesai. Sekarang Releases cuma berisi $V: https://github.com/$REPO/releases"
