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

echo "pw-backup-123" | bash "$DIR/backup.sh" >/dev/null 2>&1 || fail "backup to drive"
F=$(ls "$T/Volumes/SSD"/amnesia_backup_*.7z) || fail "backup file missing"
grep -q "OK:" "$T/home/.amnesia/backup.log" || fail "status log"
[ -f "$T/home/.amnesia/backup.ok" ] || fail "backup.ok marker"
grep -q "amnesia_backup_" "$T/home/.amnesia/backup_checksums.txt" || fail "checksum"
! grep -aq "penting" "$F" || fail "contents not encrypted"
[ -f "$T/home/.amnesia/backup.vault.ok" ] || fail "backup.vault.ok marker"
# vault ikut secara default (BACKUP_VAULT tidak diisi); BACKUP_VAULT=0 mematikannya
mv "$F" "$T/v1.7z"; F="$T/v1.7z"; rm -f "$T/home/.amnesia/backup.vault.ok"
printf 'BACKUP_DEST=drive\nBACKUP_DRIVE=SSD\nBACKUP_FOLDERS=Keep\n' > "$T/home/.amnesia/settings.conf"
echo "pw-backup-123" | bash "$DIR/backup.sh" >/dev/null 2>&1 || fail "backup with default vault"
D=$(ls "$T/Volumes/SSD"/amnesia_backup_*.7z); "$AMNESIA_7Z" l -p"pw-backup-123" "$D" | grep -q ".amnesia/vault/private.7z" || fail "vault not in backup by default"
[ -f "$T/home/.amnesia/backup.vault.ok" ] || fail "default vault marker"
rm -f "$D" "$T/home/.amnesia/backup.vault.ok"
printf 'BACKUP_DEST=drive\nBACKUP_DRIVE=SSD\nBACKUP_FOLDERS=Keep\nBACKUP_VAULT=0\n' > "$T/home/.amnesia/settings.conf"
echo "pw-backup-123" | bash "$DIR/backup.sh" >/dev/null 2>&1 || fail "backup without vault"
D=$(ls "$T/Volumes/SSD"/amnesia_backup_*.7z); "$AMNESIA_7Z" l -p"pw-backup-123" "$D" | grep -q ".amnesia/vault" && fail "BACKUP_VAULT=0 must leave the vault out"
[ ! -f "$T/home/.amnesia/backup.vault.ok" ] || fail "no vault marker without vault"
rm -f "$D"
# folder Keep custom lewat @keep (path lengkap di luar home juga bisa)
mkdir -p "$T/luar/Arsip"; echo rahasia-keep > "$T/luar/Arsip/k.txt"
printf 'BACKUP_DEST=drive\nBACKUP_DRIVE=SSD\nBACKUP_FOLDERS=@keep\nKEEP_DIR=%s\n' "$T/luar/Arsip" > "$T/home/.amnesia/settings.conf"
mv "$F" "$T/first.7z"; F="$T/first.7z"
echo "pw-backup-123" | bash "$DIR/backup.sh" >/dev/null 2>&1 || fail "backup custom keep folder"
G=$(ls "$T/Volumes/SSD"/amnesia_backup_*.7z) || fail "custom keep backup missing"
"$AMNESIA_7Z" l -p"pw-backup-123" "$G" | grep -q "Arsip/k.txt" || fail "custom keep folder not in backup"
printf 'BACKUP_DEST=drive\nBACKUP_DRIVE=SSD\nBACKUP_FOLDERS=Keep,Documents\nBACKUP_VAULT=1\n' > "$T/home/.amnesia/settings.conf"
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
# kemajuan & tombol Batal: berhenti rapi (kode 130), tidak ada file setengah jadi, backup.log tidak berubah
sed -i.bak 's/BACKUP_DRIVE=TidakAda/BACKUP_DRIVE=SSD/' "$T/home/.amnesia/settings.conf"
# v5.16: cek vault di file backup tanpa menyentuh vault yang ada
printf '{"apps": ["Chrome", "Claude"], "time": "2026-10-07 09:00"}' > "$T/home/.amnesia/vault/manifest.json"
echo "pw-backup-123" | bash "$DIR/backup.sh" >/dev/null 2>&1 || fail "backup for check-vault"
C=$(ls -t "$T/Volumes/SSD"/amnesia_backup_*.7z | head -1)
echo kunci-sekarang > "$T/home/.amnesia/vault/private.7z"
echo "salah-password" | bash "$DIR/backup.sh" --check-vault "$C" >/dev/null 2>&1 && fail "check-vault wrong password must fail"
R=$(echo "pw-backup-123" | bash "$DIR/backup.sh" --check-vault "$C" 2>/dev/null) || fail "check-vault"
echo "$R" | grep -q "^OK: VAULT .*2026-10-07 09:00|Chrome, Claude" || fail "check-vault info: $R"
[ "$(cat "$T/home/.amnesia/vault/private.7z")" = kunci-sekarang ] || fail "check-vault must not touch the vault"
rm -f "$C" "$T/home/.amnesia/vault/manifest.json"; echo kunci > "$T/home/.amnesia/vault/private.7z"
grep -q "	backup	" "$T/home/.amnesia/history.log" || fail "history.log backup entry"

echo "pw-backup-123" | bash "$DIR/backup.sh" >/dev/null 2>"$T/prog" || fail "backup for progress"
grep -q "^PROGRESS [0-9]* compress 1/2" "$T/prog" || fail "compress progress lines"
grep -q "^PROGRESS 100 copy 2/2\|^PROGRESS [0-9]* copy 2/2" "$T/prog" || fail "copy progress lines"
rm -f "$T/Volumes/SSD"/*.7z
head -c 80000000 /dev/urandom > "$T/home/Documents/besar.bin"
cp "$T/home/.amnesia/backup.log" "$T/log.before"
( echo "pw-backup-123" | bash "$DIR/backup.sh" >/dev/null 2>"$T/cancel"; echo $? > "$T/cancel.rc" ) &
for _ in $(seq 1 100); do grep -q "^PROGRESS" "$T/cancel" 2>/dev/null && break; sleep 0.1; done
sleep 0.5
pkill -TERM -f "bash $DIR/backup.sh" || fail "backup not running"
wait
[ "$(cat "$T/cancel.rc")" = 130 ] || fail "cancel exit code $(cat "$T/cancel.rc")"
grep -q "^CANCELLED" "$T/cancel" || fail "cancel message"
sleep 0.5; pgrep -f "7z.*amnesia_backup" >/dev/null && fail "7z still running after cancel"
ls "$T/Volumes/SSD" | grep -q . && fail "half-written file left"
cmp -s "$T/home/.amnesia/backup.log" "$T/log.before" || fail "backup.log changed on cancel"
rm -f "$T/home/Documents/besar.bin"
echo "OK: all backup tests passed"
