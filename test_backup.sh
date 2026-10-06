#!/bin/bash
# Tes backup.sh di home PALSU (tujuan drive palsu + ambil vault).  bash test_backup.sh
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export AMNESIA_HOME="$T/home" AMNESIA_VOLUMES="$T/Volumes"
export AMNESIA_7Z="${AMNESIA_7Z:-$(command -v 7zz || command -v 7z)}"
mkdir -p "$T/home/.amnesia/vault" "$T/home/Keep" "$T/home/Documents" "$T/Volumes/SSD"
echo penting > "$T/home/Keep/a.txt"; echo kunci > "$T/home/.amnesia/vault/private.7z"; echo pub > "$T/home/.amnesia/vault/public.pem"
printf 'BACKUP_DEST=drive\nBACKUP_DRIVE=SSD\nBACKUP_FOLDERS=Keep,Documents\nBACKUP_VAULT=1\n' > "$T/home/.amnesia/settings.conf"
fail() { echo "GAGAL: $*"; exit 1; }

echo "pw-backup-123" | bash "$DIR/backup.sh" >/dev/null || fail "backup ke drive"
F=$(ls "$T/Volumes/SSD"/amnesia_backup_*.7z) || fail "file backup tidak ada"
grep -q "OK:" "$T/home/.amnesia/backup.log" || fail "log status"
[ -f "$T/home/.amnesia/backup.ok" ] || fail "penanda backup.ok"
grep -q "amnesia_backup_" "$T/home/.amnesia/backup_checksums.txt" || fail "checksum"
! grep -aq "penting" "$F" || fail "isi tidak terenkripsi"
echo "" | bash "$DIR/backup.sh" 2>/dev/null && fail "password kosong harus ditolak"
sed -i.bak 's/BACKUP_DRIVE=SSD/BACKUP_DRIVE=TidakAda/' "$T/home/.amnesia/settings.conf"
echo "pw-backup-123" | bash "$DIR/backup.sh" 2>/dev/null && fail "drive hilang harus gagal"
grep -q "GAGAL" "$T/home/.amnesia/backup.log" || fail "log gagal"

# Mac baru: vault belum ada -> ambil dari backup
rm -rf "$T/home/.amnesia/vault"
echo "salah-password" | bash "$DIR/backup.sh" --restore-vault "$F" 2>/dev/null && fail "password salah harus gagal"
echo "pw-backup-123" | bash "$DIR/backup.sh" --restore-vault "$F" >/dev/null || fail "ambil vault"
[ "$(cat "$T/home/.amnesia/vault/private.7z")" = kunci ] || fail "isi vault"
[ ! -e "$T/home/Keep/b" ] && [ ! -e "$T/home/.amnesia/Keep" ] || fail "hanya vault yang diambil"
echo "pw-backup-123" | bash "$DIR/backup.sh" --restore-vault "$F" 2>/dev/null && fail "vault yang ada tidak boleh ditimpa"
echo "OK: semua tes backup lulus"
