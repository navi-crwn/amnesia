#!/bin/bash
# Save your free VirusTotal API key once, so every release gets a virus-scan link.
#   bash ~/.amnesia/app/virustotal_key.sh
# The key goes to 2 places only, never into a file in the repo, never into chat:
#   - your Mac Keychain ("Amnesia VirusTotal"), used by github_backup.sh for the .dmg
#   - GitHub Secret VT_API_KEY on the repo, used by GitHub Actions for the Windows .exe
# Get a key: sign up at https://www.virustotal.com (free), click your name > API key.
set -euo pipefail
cd "$HOME/.amnesia"
command -v gh >/dev/null || { echo "gh is missing. Run: brew install gh"; exit 1; }
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

printf "Paste your VirusTotal API key (it stays hidden) and press Enter: "
read -rs KEY; echo
KEY="$(printf '%s' "$KEY" | tr -d '[:space:]')"
[ ${#KEY} -ge 32 ] || { echo "That doesn't look like a VirusTotal key (too short). Nothing saved."; exit 1; }

security add-generic-password -U -s "Amnesia VirusTotal" -a "$USER" -w "$KEY"
echo "Saved in your Keychain."
printf '%s' "$KEY" | gh secret set VT_API_KEY --repo "$REPO"
echo "Saved as GitHub Secret VT_API_KEY on $REPO."
unset KEY

# Amnesia wipes Keychain passwords at logout unless they're on the Keep List
if [ -f keep.conf ] && ! grep -qx 'keychain:Amnesia VirusTotal' keep.conf; then
  echo 'keychain:Amnesia VirusTotal' >> keep.conf
  echo "Added to your Keep List, so the key survives logout."
fi
echo "Done. The next github_backup.sh run and the next Windows build will include a VirusTotal scan link."
