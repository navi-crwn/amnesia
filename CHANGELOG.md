# Changelog

**English** · [Bahasa Indonesia](CHANGELOG.id.md)

Every change to Amnesia is written down here, newest first.
You can see the version number in the app too (next to the title and at the bottom of the menu bar panel).

## v5.7 — 2026-10-06

### Added
- **Ready to use straight from GitHub.** The app now carries everything it needs: the Amnesia scripts and 7-Zip (official build, with its license). On first launch it sets itself up in `~/.amnesia`. Your Keep List, settings and vault are never overwritten.
- **Welcome tour** the first time you open the app:
  1. Hello + pick your language.
  2. How it works, in 4 short points.
  3. Quick check: engine, 7-Zip and Apple's Command Line Tools, with an install button if they're missing.
  4. **Your apps**: Amnesia finds the apps on your Mac and you switch on the ones that should keep their data. VPNs and password managers are switched on for you. Apps the Profile Vault handles show a lock.
  5. Profile Vault in 3 steps.
  6. Your daily routine.
  You can run the tour again from Settings.
- **Pick Apps** button on the Keep List page (same app picker as the tour).
- **Backup: add any folder** inside your home folder, not just the 7 standard ones.
- **More clouds, no Terminal**: Google Drive, Dropbox, OneDrive, Box and pCloud. Pick one, press Connect, log in in your browser. Amnesia installs rclone if needed and checks the connection. The login token is never shown on screen.
- Shows when your cloud is already connected, with a Reconnect button.
- **Website** (GitHub Pages, `docs/index.html`): English + Indonesian, light + dark mode, works on phones.
- **Homebrew**: `brew install --cask navi-crwn/tap/amnesia`. `github_backup.sh` creates and updates the `homebrew-tap` repo with every release.
- **MIT License** (`LICENSE`).
- Real screenshots in the README and on the website.

### Changed
- The app shows up in **Cmd-Tab** and the Dock while its window is open, and goes back to just the menu bar icon when you close it.
- SSH example is now `user@remoteserv.er:backup`.
- The tagline on the home screen no longer gets cut off.
- `vault.py` and `backup.sh` use the 7-Zip bundled in the app first, then Homebrew's.
- `build.sh` puts the scripts and 7-Zip inside the app.
- README: 3 ways to install (Homebrew, download, build it yourself), how to get past the "unidentified developer" warning, and how to uninstall safely.

### Security
- If you connected Google Drive with v5.6, its token was printed in the Terminal window. If you shared a screenshot of it, revoke rclone at https://myaccount.google.com/connections and connect again.

## v5.6 — 2026-10-06

### Added
- **Two languages.** English is now the main language, and Bahasa Indonesia is still there. Pick one in Settings → Language. On a fresh install Amnesia follows your Mac's language.
- Everything follows the language you pick: the app, the login notification, vault and backup messages, and the "Last wiped" line.
- `README.id.md` and `CHANGELOG.id.md`: the Indonesian versions of these pages. The English ones are the main pages on GitHub.
- New English images for GitHub (`docs/banner.png`, `docs/features.png`). The Indonesian ones are `docs/banner.id.png` and `docs/fitur.png`.

### Changed
- README rewritten in English, same relaxed style.
- GitHub repo description is in English now, plus a `backup` topic.
- Terminal messages from `build.sh`, `github_backup.sh`, `add_keep.sh` and the tests are in English.
- `keep.example.conf` comments are in English.
- Error messages from scripts now start with `FAILED:` (was `GAGAL:`).
- The "Backup & Panic" feature card mentions server and cloud backups.

## v5.5 — 2026-10-06

### Added
- **Online backup.** The Backup page has 3 destinations:
  - **USB drive / SSD**: plugged-in drives are found automatically (↻ to look again).
  - **SSH server**: send to your own server/VPS with SSH + rsync (`user@host:folder`). Comes with **Test Connection** and **Set Up SSH Key** buttons (makes `~/.ssh/id_ed25519` and installs it on the server through Terminal).
  - **Cloud**: Google Drive, Dropbox, OneDrive, S3 through rclone. The **Connect Google Drive** button installs rclone (if needed) and opens the Google login in your browser.
- **Scheduled backups**: Off / Daily / Weekly. Checked 2 minutes after the app starts, then every 10 minutes. For a USB drive, the backup waits until the drive is plugged in. If it fails, it tries again an hour later. You get a notification with the result.
- **Save the backup password in Keychain** (optional, needed for scheduled backups). Saved as the `Amnesia Backup` item.
- **Include Profile Vault** in backups, for moving to a new Mac.
- **Move to a new Mac** (on the Profile Vault page):
  - **Prepare Move**: saves the "… Safe Storage" Keychain keys (Chrome, Claude, WhatsApp, etc.) into the vault, encrypted like a snapshot.
  - **Get Vault from Backup** (shows up when there's no vault yet): pick a `.7z` backup, type the backup password, and the vault is restored.
  - **Restore Keys**: puts those keys into the new Mac's Keychain, using the vault password. Only runs when you press the button, never on its own.
- The last backup result (done/failed) shows at the top of the Backup page.
- `backup.sh` (the backup engine the app uses) and `test_backup.sh` (automatic tests in a fake home folder).
- `vault.py`: `exportkeys` and `importkeys` commands; `status` also reports the saved keys.

### Changed
- Backup settings (destination, folders, schedule) are saved in `settings.conf`, so you don't have to fill them in every time.
- Keep List: added `keychain:Amnesia Backup` (scheduled backup password) and `.config/rclone` (cloud login) so they survive logout. `add_keep.sh` adds them for you.
- The Backup card on the home screen says "To a USB drive, server or cloud".
- `test_clean.sh` also checks that `.config/rclone` stays safe.

### Notes
- Encrypted backup files are uploaded in full every time (not just the changes).
- Old backups aren't deleted automatically.
- After rebuilding the app, macOS may ask once more whether Amnesia can read the backup password in Keychain. Click *Always Allow*.

## v5.4 — 2026-10-06

### Added
- **Settings page** (⚙️ icon, top right). Every new feature below can be switched on or off here, and they're all on by default.
- **Auto snapshot at logout.** Logging out, restarting or shutting down from the Apple menu still saves your logins to the vault before the Mac gets wiped. Skipped if there's no vault, Amnesia is paused, or there was a snapshot in the last 10 minutes (e.g. from Save & Log Out).
- **Notification after login**: "Your Mac is clean. Click the Amnesia icon in the menu bar to restore your profiles."
- **Check before logout.** When you log out, restart or shut down from the Apple menu, Amnesia holds on and shows what will be deleted, grouped (Desktop, Downloads, Keychain, etc.). Pick **Continue** or **Cancel**.
- **"See what would be deleted now"** button in Settings: a dry run without Terminal.

### Changed
- Cleanup time limit at logout raised from 120 to 300 seconds, so the auto snapshot has time to finish. Applies after turning Amnesia on (or off and on again).
- The Save & Log Out button isn't held back by "Check before logout".

## v5.3 — 2026-10-06

### Added
- `app/make_public.sh`: creates a new **public** repo `amnesia-mac` with a clean history. The old private repo isn't deleted or changed.
- `keep.example.conf`: an example Keep List for new users. `build.sh` copies it to `keep.conf` if there isn't one.

### Changed
- README rewritten to be more relaxed and clear: what Amnesia is, what gets wiped vs. what stays, first-time setup, and an FAQ.
- Clearer GitHub repo description.
- Your personal `keep.conf` (with your app list and server notes) no longer goes to GitHub.
- `test_clean.sh` uses `keep.example.conf`, so the tests work on anyone's clone.

### Fixed
- The feature image in the README had empty icons on every card. Now they have icons.

## v5.2 — 2026-10-06

### Added
- New GitHub page: full README with a banner, feature image, how it works, install steps and limits.
- `CHANGELOG.md` (this file). Every future change gets a note here.
- The built app is uploaded to **GitHub Releases** (`Amnesia-v5.2.zip`) by `app/github_backup.sh`.
- Keep List: Keychain items `gemini` (Gemini CLI login), `*.XAUTH` (VPN profile passwords), and `.gitconfig` (git settings).

### Changed
- `app/github_backup.sh` now does it all at once: tidies files, updates the repo description and topics, commits, pushes and makes a release.

### Removed
- Old scripts nobody used anymore: `reset.sh`, `clean_keychain.sh`, `keep_apps.conf`, `amnesia_app.py` (the Tk app), the `templates/` folder.
- Spec notes (`AMNESIA_SPEK.md`, `PROFILE_VAULT_SPEK.md`) no longer go to GitHub. They're still on the Mac.

## v5.1 — 2026-10-06

### Added
- The app can only run **once**. Opening Amnesia again brings up the window that's already open.
- The version number shows next to the "Amnesia" title and at the bottom of the menu bar panel.
- Code backup to GitHub (private repo) with `app/github_backup.sh`.
- The Profile Vault also keeps: Claude Code, CodeBuddy, Gemini CLI, Kimi, GitHub CLI, Antigravity, WhatsApp and Windows App.
- Keep List: `.zshrc`, `.zprofile`, `.mitmproxy`, Shottr, Tailscale, and the Claude Code & GitHub CLI Keychain items (`app/add_keep.sh` only adds, never overwrites).

### Changed
- The app is installed in `/Applications` (so it shows in Launchpad). The Desktop only has a shortcut, not a copy.
- The build removes every old Amnesia copy (that's what caused 2 icons in the menu bar).
- Menu bar panel redesigned: colored status card, snapshot & Keep List info, and 4 colorful buttons.

### Fixed
- The "Quit App (cleaning keeps running)" text got cut off.
- The "Panic word also empties ~/Keep" checkbox looked ticked even with no panic word.

## v5.0 — 2026-10-06

### Added
- New **SwiftUI** app (native Mac) replacing the Tk app: colorful look, status icon in the menu bar, runs in the background.
- New logo: a shield with a keyhole and fading dots.
- The Turn On button asks you to confirm first.

### Fixed
- Turning Amnesia on again could trigger a cleanup in the middle of a session (LaunchAgent order).
- Profile Vault said "not responding" when no vault had been made yet.
- Apple system folders (`group.com.apple.*`) showed up in the Add to Keep List list.

## v4.0 — 2026-10-06

### Added
- Cleaning **before** logout/restart/shutdown, plus a re-check at login (`agent.sh` + `clean.sh`).
- **Profile Vault** (`vault.py`): encrypted profile snapshots & restore, 3 wrong passwords = vault destroyed, panic word.
- `--dry-run` mode to see what would be deleted.
- Flexible Keep List (`keep.conf`) with `*` patterns and Keychain items.
- Automatic tests: `test_clean.sh` and `test_vault.py`.

### Fixed
- Empty app window (macOS's built-in Tk 8.5), fixed by using Homebrew Python.
- Pause only lasts 1 session, then turns back on by itself.
