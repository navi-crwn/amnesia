#!/bin/bash
# Update GitHub Amnesia dalam 1x jalan: rapikan file, commit, push, deskripsi repo, dan Release berisi app jadi.
# Aman dijalankan berulang kali.   bash ~/.amnesia/app/github_backup.sh
set -euo pipefail
cd "$HOME/.amnesia"
command -v gh >/dev/null || { echo "gh is missing. Run: brew install gh"; exit 1; }
gh auth status >/dev/null 2>&1 || gh auth login --web --git-protocol https
V="$(defaults read "$PWD/app/Info" CFBundleShortVersionString)"

echo "1/7  Tidying old files..."
rm -rf reset.sh clean_keychain.sh keep_apps.conf amnesia_app.py templates __pycache__ app/build/makeicon docs/vault.png
# README now uses images drawn from the website (docs/readme/*.webp); the old banner/feature images and app screenshots are no longer used
rm -rf docs/banner.png docs/banner.id.png docs/features.png docs/fitur.png docs/screens
# screenshot lama (v5.6) diganti hasil app/screenshots.sh
[ -f docs/screens/en/home.png ] && rm -f docs/screens/menu.png docs/screens/home.png docs/screens/vault.png docs/screens/keep.png docs/screens/backup.png

# Data pribadi, rahasia & catatan TIDAK ikut ke GitHub
cat > .gitignore <<'IGN'
vault/
*.log
backup_checksums.txt
pause_once
.just_activated
__pycache__/
app/build/
app/shots/
video/vo/
video/vo2/
video/out/
video/paper/out/
video/paper/sfx/
video/paper/music/
video/hyperframes/
.DS_Store
keep.conf
settings.conf
backup.ok
backup.vault.ok
clean.done
crash/
bin/
.engine_version
*.md
!README.md
!README.id.md
!CHANGELOG.md
!CHANGELOG.id.md
!TERMS.md
!TERMS.id.md
IGN

echo "2/7  Commit & push..."
[ -d .git ] || git init -q -b main
git config user.name >/dev/null || git config user.name "$(gh api user -q .login)"
git config user.email >/dev/null || git config user.email "$(gh api user -q .id)+$(gh api user -q .login)@users.noreply.github.com"
git rm -r -q --cached --ignore-unmatch keep.conf settings.conf backup.ok AMNESIA_SPEK.md PROFILE_VAULT_SPEK.md reset.sh clean_keychain.sh keep_apps.conf amnesia_app.py templates __pycache__ >/dev/null
git add -A
git commit -q -m "Amnesia v$V - $(date '+%F %H:%M')" || echo "     nothing new to commit"
if git remote get-url origin >/dev/null 2>&1; then git push -q -u origin main
else gh repo create amnesia --private --source=. --push; fi

echo "3/7  Repo description & topics..."
gh repo edit --description "Your Mac forgets everything at logout. Except the logins and files you keep. Free macOS menu bar app with an encrypted login vault, backups and a panic word." \
  --homepage "https://navi-crwn.github.io/amnesia-mac/" \
  --add-topic macos --add-topic privacy --add-topic swiftui --add-topic menubar-app --add-topic encryption --add-topic backup \
  --add-topic opsec --add-topic mac-app --add-topic open-source >/dev/null

echo "4/7  Making the installer (.dmg)..."
APP=""
for d in /Applications "$HOME/Applications"; do [ -d "$d/Amnesia.app" ] && { APP="$d/Amnesia.app"; break; }; done
[ -n "$APP" ] || { echo "Amnesia.app is not installed yet. Run first: bash ~/.amnesia/app/build.sh"; exit 1; }
# .dmg: buka, lalu seret Amnesia ke folder Applications. Ada "READ ME FIRST" berisi peringatan.
STAGE="$(mktemp -d)/Amnesia"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Amnesia.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/READ ME FIRST.txt" <<TXT
AMNESIA v$V - read this before you install

1. Drag Amnesia into the Applications folder.
2. The first time, macOS says it can't check the developer. Open
   System Settings > Privacy & Security and click "Open Anyway".

WARNING: Amnesia really deletes data. Once you turn it on, everything outside
your Keep folder and Keep List is deleted at every logout, restart and shutdown.
It does not go to the Trash and cannot be undone. Back up first.
Full terms: https://github.com/navi-crwn/amnesia-mac/blob/main/TERMS.md

Your data stays on your Mac. Amnesia has no servers, no tracking, no analytics.

UNINSTALL: don't just drag the app to the Trash (the login agent would stay).
Paste this in Terminal instead:  bash ~/.amnesia/uninstall.sh
(add --all to also delete the vault and settings in ~/.amnesia)

---
PERINGATAN: Amnesia benar-benar menghapus data. Setelah aktif, semua di luar
folder Keep dan Keep List dihapus setiap logout, restart dan shutdown, tidak
masuk Trash dan tidak bisa dibatalkan. Backup dulu.
Ketentuan lengkap: https://github.com/navi-crwn/amnesia-mac/blob/main/TERMS.id.md

HAPUS APP: jangan cuma buang ke Trash (agent login masih tertinggal).
Tempel ini di Terminal:  bash ~/.amnesia/uninstall.sh
(tambah --all untuk ikut menghapus vault dan pengaturan di ~/.amnesia)
TXT
PKG="$(mktemp -d)/Amnesia-v$V.dmg"
hdiutil create -quiet -volname "Amnesia $V" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$PKG"
NOTES="$(mktemp)"
awk -v v="## v$V" '$0 ~ "^"v {on=1; next} on && /^## v/ {exit} on' CHANGELOG.md > "$NOTES"

echo "5/7  Release v$V..."
if gh release view "v$V" >/dev/null 2>&1; then
  gh release upload "v$V" "$PKG" --clobber
  gh release edit "v$V" --notes-file "$NOTES" >/dev/null
else
  gh release create "v$V" "$PKG" --title "Amnesia v$V" --notes-file "$NOTES" >/dev/null
fi
OWNER="$(gh api user -q .login)"; REPO="$(gh repo view --json name -q .name)"
SITE="https://$OWNER.github.io/$REPO/"

echo "6/7  Landing page (GitHub Pages from docs/)..."
gh api "repos/$OWNER/$REPO/pages" >/dev/null 2>&1 || \
  gh api -X POST "repos/$OWNER/$REPO/pages" -f "source[branch]=main" -f "source[path]=/docs" >/dev/null \
  || echo "     (couldn't turn on Pages: Settings > Pages > Branch: main, folder: /docs)"
gh repo edit --homepage "$SITE" >/dev/null

echo "7/7  Homebrew (brew install --cask $OWNER/tap/amnesia)..."
SHA="$(shasum -a 256 "$PKG" | cut -d' ' -f1)"
TAP="$(mktemp -d)/homebrew-tap"
gh repo view "$OWNER/homebrew-tap" >/dev/null 2>&1 || \
  gh repo create homebrew-tap --public --description "Homebrew tap for Amnesia" >/dev/null
git clone -q "https://github.com/$OWNER/homebrew-tap.git" "$TAP" 2>/dev/null || { mkdir -p "$TAP"; git -C "$TAP" init -q -b main; }
mkdir -p "$TAP/Casks"
cat > "$TAP/Casks/amnesia.rb" <<CASK
cask "amnesia" do
  version "$V"
  sha256 "$SHA"

  url "https://github.com/$OWNER/$REPO/releases/download/v#{version}/Amnesia-v#{version}.dmg"
  name "Amnesia"
  desc "Wipes your Mac at every logout, except what you choose to keep"
  homepage "$SITE"

  depends_on macos: ">= :sequoia"

  app "Amnesia.app"

  # Turns off the login agent safely (agent file first, so stopping it doesn't wipe).
  # ~/.amnesia (vault, settings) is kept; run uninstall.sh --all to remove it too.
  uninstall early_script: {
    executable: "/bin/bash",
    args:       ["#{appdir}/Amnesia.app/Contents/Resources/engine/uninstall.sh", "--yes", "--keep-app"],
  }

  # Not signed by Apple yet: remove the download quarantine so the app opens.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Amnesia.app"]
  end

  caveats <<~EOS
    Amnesia really deletes data once you turn it on. Read the terms first:
      https://github.com/$OWNER/$REPO/blob/main/TERMS.md
    To uninstall: brew uninstall --cask amnesia (turns Amnesia off safely).
    To also delete the vault and settings: bash ~/.amnesia/uninstall.sh --all
  EOS
end
CASK
cat > "$TAP/README.md" <<README
# Homebrew tap

\`\`\`bash
brew install --cask $OWNER/tap/amnesia
\`\`\`

[Amnesia]($SITE): your Mac forgets everything every time you log out, except what you choose to keep.
README
git -C "$TAP" add -A
git -C "$TAP" -c user.name="$(git config user.name)" -c user.email="$(git config user.email)" \
  commit -q -m "amnesia $V" || true
git -C "$TAP" remote get-url origin >/dev/null 2>&1 || git -C "$TAP" remote add origin "https://github.com/$OWNER/homebrew-tap.git"
git -C "$TAP" push -q -u origin HEAD:main

echo "DONE: $(gh repo view --json url -q .url)  (release v$V)"
echo "      site: $SITE   ·   brew install --cask $OWNER/tap/amnesia"
