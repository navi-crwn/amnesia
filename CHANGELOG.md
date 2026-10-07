# Changelog

**English** · [Bahasa Indonesia](CHANGELOG.id.md)

Every change to Amnesia is written down here, newest first.
You can see the version number in the app too (next to the title and at the bottom of the menu bar panel).

## v5.13 — 2026-10-07

### Fixed
- **Shutdown went ahead even though Amnesia tried to stop it.** When a pop-up from Amnesia was open (for example "wrong password"), macOS had to wait until the pop-up was closed before Amnesia could answer the shutdown. By then macOS had already stopped waiting, so the "Cancel" came too late. Pop-ups no longer block Amnesia: a logout, restart or shutdown is answered right away, even with a pop-up open. If the main window is closed, Amnesia opens it first so the pop-up can sit on it.
- **Restore Profiles deleted the app data that was on the Mac right before the restore.** It is now moved (not deleted) to `~/Library/Caches/Amnesia/before-restore`, and the Restore result tells you where. That folder stays until the next logout.

### Added
- **"LAST TRY" warning.** When only 1 password try is left, Amnesia asks first: one more wrong password deletes the vault forever. This shows before Restore Profiles, the password check in Change Password, saving a Panic Word and Restore Keys. The wrong-password message also says "LAST TRY" when only 1 try is left.
- **Turn On checks that the vault has a backup.** If you have a vault that was never part of a backup, Turn On warns you first and offers to go to the Backup page. "Turn On Anyway" is still possible.
- **Open at login** (Settings, on by default). Amnesia starts by itself in the menu bar every time you log in, also while it is turned off. It uses a small separate login item (`com.amnesia.menubar`) that only opens the app; it never wipes anything. Takes effect from the next login. `uninstall.sh` removes it too.
- **Light Chrome snapshot** (Settings, on by default). The vault skips Chrome's extension program files and big caches (Extensions, ScriptCache, AI model files, Safe Browsing lists and similar). On a typical Mac that is about 1 GB → 150 MB, so snapshots and restores are much faster. Logins, bookmarks, history, passwords and the settings inside extensions are kept. After Restore, Chrome downloads the extensions again from the Web Store (needs internet, a few minutes). Extensions that did not come from the Web Store do not come back. Turn it off to keep the full Chrome profile.

### Changed
- **Backups include the Profile Vault by default.** The option is now called "Include Profile Vault (your saved app logins, encrypted)". The old label "(for moving Macs)" made it look like it was only for moving to a new Mac, which is how a vault got lost without any copy. If you untick it, a warning explains that a lost vault then cannot be brought back. If you had unticked it before, it stays unticked.
- A backup that included the vault leaves a small marker (`~/.amnesia/backup.vault.ok`), which Turn On uses for the check above.

## v5.12 — 2026-10-07

### Fixed
- **Backup to Dropbox jumped to 100% right away** and then sat at 100% until it was done, with a speed that started very high and slowly dropped. rclone fills a 48 MB piece of the file before sending it to Dropbox, and counted that piece as "sent" as soon as it was filled. Amnesia now uses 8 MB pieces for Dropbox, so the progress bar follows the real upload. OneDrive and other clouds are unchanged.
- **The server speed test showed a number that was far too high** (for example "10000 KB/s" on a connection that really does about 750 KB/s). It took the time to open the connection away from the send time, and when those two were close, almost nothing was left. Now it sends 1 MB and then 5 MB and only looks at the extra time the bigger one needs, so the connection time drops out on its own. If that difference is too small to trust, it uses the whole time instead, which gives a lower number, never a too-high one.

### Changed
- **The privacy note in the welcome tour and in Settings is bigger** ("Everything stays on this Mac…"), so it's easier to read.

## v5.11 — 2026-10-07

### Fixed
- **Logging in to Dropbox, OneDrive, Box and pCloud always failed** ("isn't connected"). Amnesia started rclone with an option (`--auth-no-open-browser`) that the connect command doesn't know, so rclone stopped right away and no login page ever opened. That option is gone.
- **Google Drive said "not signed in" while it was still syncing.** Amnesia now looks for Google Drive in the background, says "signed in, but not ready yet (still syncing)" when that's the case, and shows 3 steps: open Google Drive and sign in, wait until syncing is done, press Check Again.

### Changed
- **Cloud login opens in your normal browser** (the one you set as default, or Safari on a new Mac), instead of a small window inside Amnesia. The waiting screen has a "Browser didn't open? Open the login page" button and a Cancel button.
- **Repeat boxes tell you right away whether they match**: vault password, panic word (in the vault setup and in the Panic Word window), new password and backup password.
- **"What goes in the vault" is now a grid of small tiles** with the app icon, name and size. Tap a tile to pick it. One short note at the bottom says when a snapshot can take a few minutes (and which apps are the big ones), instead of a warning under every app.
- **A new vault starts with no apps picked.** You choose which apps go in.
- **Delete one app's snapshot** with the trash icon next to it. "Delete All Snapshots" still removes them all (the vault and password stay).
- **Guides open as pop-ups** with a clear button: "How backup works" (now at the top of the Backup page) and "Show me how (7 steps)" for your own Google access.
- **Bigger, easier-to-read text** on the home page and in the welcome tour. Home tiles have the icon on the left and the text next to it, so the whole page (including "What Gets Deleted") fits without scrolling.
- **"What Gets Deleted" explains rows from apps in your Keep List**, for example "only cache: the app is in your Keep List, its login stays".
- **Server speed test** sends 2 MB and leaves out the time it takes to open the connection, so the number is closer to the real backup speed. It's marked as a rough estimate.
- **Backup waiting screen** only says "Don't unplug the drive" for USB drives, "Keep the internet on" for servers and cloud, and that the Google Drive app uploads afterwards for Google Drive.
- Google Drive now shows up in the Keep List app picker (its data lives in `Application Support/Google/DriveFS`).

## v5.10.1 — 2026-10-07

### Fixed
- **Full Disk Access no longer disappears after an update.** Amnesia isn't signed by Apple, so every new build looked like a different app to macOS: the switch in System Settings stayed on, but the permission didn't apply. `app/build.sh` now makes a local signing certificate once ("Amnesia Local Signing", in your login Keychain) and signs every build with it, so macOS knows it's the same app.
- The first build may show one Keychain pop-up asking if `codesign` can use the key. Enter your Mac password and press **Always Allow**.
- One last time after this update: remove Amnesia from Full Disk Access (−), add it again (+), then Quit & Reopen. After that it stays.
- If the certificate can't be made, the build falls back to the old way and says so. Amnesia's logout wipe only removes saved passwords from the Keychain, never certificates, so the certificate stays.

## v5.10 — 2026-10-07

### Added
- **"Apple accounts & data" in the Keep List.** A new card at the top of the Keep List (and on the "What should stay?" page after the tour) keeps your iCloud / Apple ID sign-in, Photos, Notes, Mail, Calendar & Reminders, Contacts, Messages, Shortcuts and git settings. All switched on by default. You can switch each one off (Amnesia asks first). These stay in the Keep List, not the vault, because Apple accounts are tied to this Mac and Photos can be huge (`APPLE_KEEP` in settings.conf).
- **Add any file or folder to the Keep List.** "Add Folder or File" now has a "Choose in Finder…" button (hidden files shown) and a box to type a path, so files like `Library/Preferences/MobileMeAccounts.plist` can be added too.
- **Snapshots per app.** Every app gets its own snapshot, so saving one app never overwrites another. The vault page shows the last snapshot time and size for each app. Old single-file snapshots are still read, and are cleaned up once every app has its own.
- **Folders in the vault.** Add folders (documents, PDFs, music, videos) to the vault on the Profile Vault page. A warning shows when a folder is over 1 GB (`VAULT_FOLDERS` in settings.conf).
- **Sizes before you save.** The vault page shows the size of every app and the total, and warns only for big apps (500 MB or more) that a snapshot can take a while.
- **"Delete Snapshots"** removes only the saved snapshots. Your vault and password stay. "Delete Vault" still removes everything.
- **Cancel button** for Snapshot, Restore and Backup (in the window and in the menu bar panel). Your previous snapshot or backup stays untouched, and half-finished files are removed.
- **Check after Restore.** After a restore you get a list with ✅ or ❌ per app (for example whether `gh` is logged in), plus a "check yourself" line for web logins in Chrome.
- **Backup progress for every destination** (drive, folder, server, cloud): the step ("1/2 Locking files…", "2/2 Uploading…"), percentage, speed, time left, and a Cancel button. If nothing moves for 10 minutes, the backup stops by itself and says so.
- **Backup to any folder** (for example a mounted network drive), next to flash drive, server and cloud.
- **Server: Port box** (default 22). `user@address:port` works too.
- **Server: Connect checks the folder.** It creates the backup folder, tests that it can write there, and shows the full path on the server. If the folder needs admin rights (sudo), it says so and suggests a folder in your home instead. Amnesia never uses sudo.
- **Server: speed test on Connect**, then an estimate of how long a backup will take. A slow backup usually means a slow upload connection, not that it's stuck.
- **Google Drive through the Google Drive app.** If Google Drive for Desktop is installed, Amnesia copies backups into its folder and the app uploads them. If it isn't installed, there's a download button. Your own Google client ID is under "Advanced", with a step-by-step guide.
- **Backup guide inside the app**: steps for each destination, which folders are safe, how long it takes, and how to check your backup file.
- **Shortcut to "What gets deleted"** on the home page.
- Cloud login notes are written to `~/.amnesia/cloud.log` (without passwords or tokens), to help find out why a login failed.

### Changed
- **"What gets deleted" is easier to read.** Rows use the real app icons, macOS icons for system items and file-type icons for files. Real thumbnails are made only when you open a group, and only for Desktop, Downloads, Documents and Pictures. Each row has a clear name (for example "Chrome · cache"); the full path shows when you click it or hover over it.
- Groups by meaning: "Restored from your vault", "Your files", "Apple accounts & sync", "App data & settings", "Keychain", "History, caches & logs" and "macOS system data (made again automatically)". The system group is hidden unless you switch it on.
- Shortcuts that Amnesia makes itself (`~/Desktop/Keep`, `~/Desktop/Amnesia.app`) are no longer listed, because they are made again automatically.
- **Cloud box in 3 steps:** 1. pick the service, 2. connect ("✓ Connected as …"), 3. type just the folder name. The words "remote" and "rclone" moved to "Advanced".
- **Snapshot progress per app**: "Saving OpenCode… 2 of 3". The text always matches the app being saved.
- **Full Disk Access is checked once, before Snapshot**, so macOS doesn't keep asking in the middle. Quit & Reopen is blocked while something is running, and the app explains how to fix a "Limit Access" press.
- **Vault setup:** the "Repeat password" box only appears once you start typing, and says when the two don't match.
- **Change password:** first your current password, then the new one, then repeat it. A new password that's the same as the old one is refused.
- **Backup messages** say the time and the destination, with a clear message for cancelled ("Backup cancelled. Your previous backup is safe."), stopped, stuck and failed, instead of "exited with code 15".
- **Pop-ups stick to the Amnesia window** instead of the middle of the screen, and the window remembers its position.
- Home page tiles are a bit smaller and the page scrolls, so everything fits.

### Fixed
- Dropbox and OneDrive sometimes failed with "isn't connected". If the login window doesn't finish, Amnesia now offers to log in with your normal browser instead. (Not fully confirmed yet; tell us if it still fails.)
- `app/screenshots.sh` didn't capture "What gets deleted" because macOS closed the app while it prepared the list. Automatic closing is now switched off during screenshots. The Move to a new Mac page is captured too (28 screenshots in total).
- Cancelling a backup could leave 7-Zip running in the background.

## v5.9.1 — 2026-10-06

### Added
- **Safe uninstall: `uninstall.sh`.** Run `bash ~/.amnesia/uninstall.sh` in Terminal. It deletes the login agent file first, so stopping the agent can never start a wipe. Then it stops anything still running, removes the app (also the Homebrew version) and checks that nothing is left. If something is left, it tells you not to log out yet.
- By default your vault, Keep List and settings in `~/.amnesia` stay, in case you install again. `--all` deletes those too, but only after you type `DELETE` (or `HAPUS`). Your Keep folder is never touched.
- The app copies `uninstall.sh` into `~/.amnesia`, so it's there even if you installed from the .dmg.
- `brew uninstall --cask amnesia` now runs the same safe steps.
- **How to uninstall** is explained in the README ("Uninstall" section), on the website FAQ, in the .dmg's READ ME FIRST, and in the Homebrew message: don't just drag the app to the Trash.

### Fixed
- The app didn't compile because of a name clash in the screenshot code (`log`).

## v5.9 — 2026-10-06

### Added
- **Progress bar** for Snapshot, Restore and Save & Log Out. It shows a percentage, so you know how far along it is. The menu bar panel shows the percentage too.
- **Change the vault password** (Profile Vault, Password button). Your snapshot stays as it is; you no longer have to delete the vault and make a new one.
- **Choose what goes in the vault.** On the Profile Vault page, tick the apps you want saved (for example, leave out WhatsApp). Snapshots and Save & Log Out only save the ticked apps (`VAULT_SKIP` in settings.conf).
- **Repeat the panic word** when you set it (in the vault setup and in the Panic Word window), so a typo can't lock you out. Save only works when both match.
- **Move to a new Mac** now has its own page (from the Profile Vault page or Settings), with a simple 4-step guide: Prepare Move, Back up, Get Vault from Backup, Restore Profiles and Keys.
- **Quit & Reopen** button next to Full Disk Access (in the tour and in Settings). **The tour remembers where you were**, so after reopening it continues on the same page instead of starting over.
- **Clear SSH messages.** If a backup can't reach your server, the message says why: the server refused the key (press Connect again), the server looks different (reinstalled?), or it can't be reached right now (tried again later). Changing your server password doesn't break backups, because Amnesia logs in with a key, not the password.
- If your server was reinstalled, Connect explains it and asks before forgetting the old server identity.

### Changed
- Snapshot apps now show as a neat grid of chips, instead of text running down the page. The page also says that only the newest snapshot is kept, and that snapshots don't need your password (only Restore does).
- **"What gets deleted"**: tap anywhere on a group's row to open its list (not just the small arrow). The time now shows when it was really updated (for example "Today 15:20") instead of "0 seconds ago", and the list is only rebuilt if it's more than a minute old.
- The cloud backup box shows the steps: 1. pick your service (Google Drive, Dropbox, OneDrive, Box, pCloud), 2. press the button to log in.

## v5.8.1 — 2026-10-06

### Fixed
- `app/screenshots.sh` stopped after 10 screenshots (English only). It now runs one language at a time, so a problem in one doesn't stop the other, and takes the "what gets deleted" screen last, with its list prepared in the background.
- Notes from the screenshot run go to `~/.amnesia/shots.log`, and the script says how many of the 22 screenshots were made.
- Removed a harmless "No such file or directory" message from the screenshot script.

## v5.8 — 2026-10-06

### Added
- **Pick what stays, right after the tour.** When the welcome tour ends, a "What should stay?" page lists the apps on your Mac. The tour itself now only shows an example.
- **See exactly what's kept.** Switch an app on and it unfolds: which data is kept (app data, sandbox data, shared data, settings), where it lives, and how big it is.
- **No more locked apps.** Apps the Profile Vault handles (Chrome, Claude, WhatsApp…) can be switched on too, if you'd rather keep them whole instead of in the vault.
- **Your own Keep folder.** Pick any folder, anywhere, with any name (even on an external drive): on the Keep List page, in Settings, or on the "What should stay?" page. Amnesia can move your files over from the old one. The wiper, the panic word and backups all follow the folder you picked (`KEEP_DIR` in settings.conf).
- **"Read this first" page** in the tour: what Amnesia deletes, what happens if you forget a password, and that it's free software used at your own risk. You have to tick that you understand before you can continue, and before Turn On works.
- **`TERMS.md` / `TERMS.id.md`**: the full terms & warning, linked from the README, the website, the app and the installer.
- **Privacy note** on the welcome page and in Settings: no servers, no tracking, no analytics, nothing leaves your Mac unless you set up a backup.
- **Full Disk Access, asked once.** The quick check shows whether Amnesia has it, with a button that opens the right Settings page. No more pop-ups for every folder.
- **Connect a server without Terminal.** Type the server password once and press Connect. Amnesia makes an SSH key, installs it on the server, and tells you the exact folder where backups go. The password is never saved. If your key already works, no password is needed at all.
- **Cloud login in a small window** inside the app (Apple's secure login sheet), instead of opening Chrome or your browser. It doesn't use your browser's cookies.
- **Installer (.dmg)** for releases: open it and drag Amnesia to Applications. It also has a short "READ ME FIRST" with the warning. Homebrew installs the .dmg too.
- **Automatic screenshots**: `app/screenshots.sh` takes every screen (tour, Keep setup, home, vault, Keep List, backup, what gets deleted, settings, dark mode, menu bar) in English and Indonesian, using demo data so nothing personal shows up.
- Backups can include folders outside your home folder too (for example on another drive).

### Changed
- The welcome page sits higher, so the logo and text aren't pushed down.
- **"What gets deleted" opens instantly.** The list is prepared in the background (20 seconds after the app starts, then every 30 minutes) and shown right away, with "Updated … ago" and a Refresh button. The saved list (`report.txt`) is deleted at every real wipe, so it never leaves a trace.
- The wiper is a lot faster: checking the Keep List no longer starts extra programs for every folder.
- At login, macOS now starts the cleaner through the Amnesia app itself, so the Full Disk Access you gave Amnesia also covers the wipe at logout. Existing setups are updated automatically on the next app launch.
- The Desktop shortcut to the Keep folder follows its new name and place.
- The README and website have the new screenshots (in both languages), the warning, the .dmg installer and new FAQ answers (privacy, Full Disk Access, backups without Terminal).
- SSH server can be written as `user@host` (backups then go to `~/amnesia-backup` on the server) or `user@host:folder`.

### Removed
- The "Set Up SSH Key" button that opened Terminal (replaced by Connect).
- The zip download (replaced by the .dmg).

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
