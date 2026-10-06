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
fail() { echo "FAILED: $*"; exit 1; }

echo "pw-backup-123" | bash "$DIR/backup.sh" >/dev/null || fail "backup to drive"
F=$(ls "$T/Volumes/SSD"/amnesia_backup_*.7z) || fail "backup file missing"
grep -q "OK:" "$T/home/.amnesia/backup.log" || fail "status log"
[ -f "$T/home/.amnesia/backup.ok" ] || fail "backup.ok marker"
grep -q "amnesia_backup_" "$T/home/.amnesia/backup_checksums.txt" || fail "checksum"
! grep -aq "penting" "$F" || fail "contents not encrypted"
echo "" | bash "$DIR/backup.sh" 2>/dev/null && fail "empty password must be refused"
sed -i.bak 's/BACKUP_DRIVE=SSD/BACKUP_DRIVE=TidakAda/' "$T/home/.amnesia/settings.conf"
echo "pw-backup-123" | bash "$DIR/backup.sh" 2>/dev/null && fail "missing drive must fail"
grep -q "FAILED" "$T/home/.amnesia/backup.log" || fail "failure log"

# Mac baru: vault belum ada -> ambil dari backup
rm -rf "$T/home/.amnesia/vault"
echo "salah-password" | bash "$DIR/backup.sh" --restore-vault "$F" 2>/dev/null && fail "wrong password must fail"
echo "pw-backup-123" | bash "$DIR/backup.sh" --restore-vault "$F" >/dev/null || fail "restore vault"
[ "$(cat "$T/home/.amnesia/vault/private.7z")" = kunci ] || fail "vault contents"
[ ! -e "$T/home/Keep/b" ] && [ ! -e "$T/home/.amnesia/Keep" ] || fail "only the vault is restored"
echo "pw-backup-123" | bash "$DIR/backup.sh" --restore-vault "$F" 2>/dev/null && fail "existing vault must not be overwritten"
echo "OK: all backup tests passed"
