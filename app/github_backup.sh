#!/bin/bash
# Update GitHub Amnesia dalam 1x jalan: rapikan file, commit, push, deskripsi repo, dan Release berisi app jadi.
# Aman dijalankan berulang kali.   bash ~/.amnesia/app/github_backup.sh
set -euo pipefail
cd "$HOME/.amnesia"
command -v gh >/dev/null || { echo "gh belum ada. Jalankan: brew install gh"; exit 1; }
gh auth status >/dev/null 2>&1 || gh auth login --web --git-protocol https
V="$(defaults read "$PWD/app/Info" CFBundleShortVersionString)"

echo "1/5  Rapikan file lama..."
rm -rf reset.sh clean_keychain.sh keep_apps.conf amnesia_app.py templates __pycache__ app/build/makeicon

# Data pribadi, rahasia & catatan TIDAK ikut ke GitHub
cat > .gitignore <<'IGN'
vault/
*.log
backup_checksums.txt
pause_once
.just_activated
__pycache__/
app/build/
.DS_Store
keep.conf
*.md
!README.md
!CHANGELOG.md
IGN

echo "2/5  Commit & push..."
[ -d .git ] || git init -q -b main
git config user.name >/dev/null || git config user.name "$(gh api user -q .login)"
git config user.email >/dev/null || git config user.email "$(gh api user -q .id)+$(gh api user -q .login)@users.noreply.github.com"
git rm -r -q --cached --ignore-unmatch keep.conf AMNESIA_SPEK.md PROFILE_VAULT_SPEK.md reset.sh clean_keychain.sh keep_apps.conf amnesia_app.py templates __pycache__ >/dev/null
git add -A
git commit -q -m "Amnesia v$V - $(date '+%F %H:%M')" || echo "     tidak ada perubahan baru"
if git remote get-url origin >/dev/null 2>&1; then git push -q -u origin main
else gh repo create amnesia --private --source=. --push; fi

echo "3/5  Deskripsi & topik repo..."
gh repo edit --description "Bikin Mac kamu lupa semua jejak setiap logout, tapi login dan file pilihanmu tetap aman. App menu bar macOS dengan brankas login terenkripsi." \
  --add-topic macos --add-topic privacy --add-topic swiftui --add-topic menubar-app --add-topic encryption >/dev/null

echo "4/5  Siapkan app jadi..."
APP=""
for d in /Applications "$HOME/Applications"; do [ -d "$d/Amnesia.app" ] && { APP="$d/Amnesia.app"; break; }; done
[ -n "$APP" ] || { echo "Amnesia.app belum terpasang. Jalankan dulu: bash ~/.amnesia/app/build.sh"; exit 1; }
ZIP="$(mktemp -d)/Amnesia-v$V.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
NOTES="$(mktemp)"
awk -v v="## v$V" '$0 ~ "^"v {on=1; next} on && /^## v/ {exit} on' CHANGELOG.md > "$NOTES"

echo "5/5  Release v$V..."
if gh release view "v$V" >/dev/null 2>&1; then
  gh release upload "v$V" "$ZIP" --clobber
  gh release edit "v$V" --notes-file "$NOTES" >/dev/null
else
  gh release create "v$V" "$ZIP" --title "Amnesia v$V" --notes-file "$NOTES" >/dev/null
fi
echo "BERES: $(gh repo view --json url -q .url)  (release v$V)"
