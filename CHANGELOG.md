# Changelog

**English** · [Bahasa Indonesia](CHANGELOG.id.md)

Everything that changed in Amnesia, newest on top.
Quick backstory: on October 6, 2026 Amnesia was a handful of scripts. Two days and a lot of coffee later it's a real Mac app with a vault, backups and its own website. To keep things readable, those two busy days are grouped into three chapters below instead of 30 tiny entries.

Your version number is next to the Amnesia title and at the bottom of the menu bar panel.

## v5.18.1 · It looks like the website now (Oct 7–8, 2026)

This is the version to download. It covers v5.16 up to v5.18.1, plus the new website and the videos.

### New stuff
- **History page.** A new tile on the home page shows what Amnesia did, day by day: cleanups (with how many items), paused sessions, snapshots, restores, backups and the panic word. Only times, counts and app names get written down, never your file names.
- **Restore Files.** Need just a few files back from a backup? Backup → **Restore Files…**, pick the `.7z`, type the password, tick what you want. It goes back exactly where it came from. Nothing gets overwritten: whatever is already there is moved to `~/.amnesia/before-restore/` first. Or send everything to another folder.
- **Check a backup file.** Pick a backup and Amnesia peeks inside: is the Profile Vault in there, how big, which apps. Your real vault isn't touched. If something's off it tells you what: wrong password, a backup without vault, or a broken file.
- **Run the scheduled backup now.** Test your schedule right away instead of waiting a day.
- **Light snapshot, per browser.** Profile Vault has a switch for each browser. On (the default) skips caches and Web Store extension files, so Chrome shrinks from about 1 GB to 150 MB. Logins, bookmarks and extension settings always stay.
- **More browsers in the vault:** Brave, Edge, Vivaldi, Arc and Opera (only shown if you have them).
- **Read more…** under long texts, so pages don't feel like a wall of words.

### Looks & feel
- **The app matches the website.** Dark (or soft white in light mode, it follows your Mac), flat cards with thin borders, calm feature colors, and a status card that's green when On, orange when Paused and neutral when Off.
- **Turn On / Turn Off** is now a big button on the status card at the top of the home page.
- **Popups are easier to read.** Every warning is split into colored boxes: what will happen, what gets deleted, what stays, what you need to do, be careful, good to know.
- **Uninstall goes in two steps,** and only deletes your vault and settings if you tick the box and confirm again (they go to the Trash, not straight into the void).
- **Status in normal words,** like "Last cleaned: today 13:03, at logout, 1284 items".
- All texts checked again so button names in the explanations match the real buttons, in English and Indonesian.

### Fixed
- The main popup button (like **Turn Off**) was invisible on macOS 26. It's back.
- Tiles and buttons near the edges had their border or shadow cut off.
- The scheduled backup kept asking for your Mac password (Keychain popup). Allow it once and it stays quiet.

### Website & README
- **Brand new website** at [navi-crwn.github.io/amnesia-mac](https://navi-crwn.github.io/amnesia-mac/): scroll animations, a 3D logo, light and dark mode, the app taken apart button by button, a click-along tutorial, install cards and a big FAQ. Still works fine with animations off. No tracking.
- **Built in the open:** a section with live repo info and a 3D chart of every commit.
- **"If you know, you know" 😉** for people who'd rather not explain: lending your Mac, losing it, "just open it real quick" and nosy family. With honest fine print: it protects you after a logout, and the panic word can't be undone.
- **Paper craft videos.** A 54-second stop motion film right under the top of the page, and three 30-second vertical clips in the "If you know, you know" cards. They play silently while on screen; tap to watch with sound.
- **The README** got a 15-second moving preview that links to the full video.

### Behind the scenes
- New tests for Restore Files, Check a backup file and per-browser light snapshots.

Older changes: [the full changelog](https://github.com/navi-crwn/amnesia-mac/blob/main/CHANGELOG.md).

## v5.15 · Faster, safer, easier to remove (Oct 7, 2026)

Covers v5.10 up to v5.15. Lots of real-life testing on day two, and it shows.

### Faster
- **Logout is basically instant.** Wiped stuff is moved into `~/.amnesia-trash` (same disk, so 1 GB or 100 GB takes the same split second) and really deleted later, quietly, after you log in. Measured: about 2 seconds for 300+ items.
- **Lighter login check** when the logout finished properly. A crash or forced power-off still gets the full cleanup.
- **Auto snapshot only saves apps that changed,** and gives up cleanly after 150 seconds so the cleanup always gets its turn.

### New stuff
- **Uninstall button** in Settings. No Terminal needed. Your vault, Keep List, settings and Keep folder stay unless you choose otherwise.
- **Dragged the app to the Trash?** Amnesia notices and switches itself off, and the login agent refuses to wipe anything if the app is gone.
- **Open at login** (on by default): Amnesia sits in your menu bar after every login.
- **"Apple accounts & data" card** at the top of the Keep List: iCloud, Photos, Notes, Mail, Calendar, Contacts, Messages and more stay put.
- **Add any file or folder to the Keep List,** straight from Finder or by typing a path.
- **Snapshots per app,** so saving one app never overwrites another. You can delete a single app's snapshot too.
- **Folders in the vault** for documents, PDFs, music or videos.
- **Cancel button** for Snapshot, Restore and Backup. Your previous copy stays safe.
- **Check after Restore:** a ✅ or ❌ per app.
- **Backup progress everywhere** (drive, folder, server, cloud) with speed and time left. Backup to any folder too.
- **Server backups without fuss:** port box, a folder check on Connect, and a speed test so you know how long it'll take.
- **Google Drive through the Google Drive app** if you have it installed.
- **"Last try" warning** when one more wrong password would delete the vault.
- **Turn On checks your vault has a backup,** and warns when the vault has no snapshot yet.
- **Light Chrome snapshot** (about 1 GB down to 150 MB). Extensions not from the Web Store are kept.

### Changed
- **Backups include the Profile Vault by default.** The old label made it look like it was only for moving Macs, and that's how a vault got lost without a copy.
- **Cloud login opens in your normal browser,** with a "didn't open?" button.
- **"What gets deleted" is easier to read:** real app icons, clear names, sensible groups.
- **A new vault starts empty.** You pick the apps.
- Bigger text on the home page and in the tour. Password and panic word boxes tell you right away if the two don't match.

### Fixed
- **Installing an update while Amnesia was ON wiped the session** (the installer stopped the background agent, and the agent took that as a logout). Fixed. Still, the golden rule stays: **install updates while Amnesia is Turned Off.**
- Shutdown went ahead even though Amnesia tried to stop it, when one of its popups was open.
- Restore deleted the app data that was on the Mac right before the restore. It's now moved aside instead.
- Full Disk Access kept disappearing after every update. Builds are now signed with a local certificate so macOS recognizes the app.
- Logging in to Dropbox, OneDrive, Box and pCloud always failed.
- Google Drive said "not signed in" while it was just still syncing.
- Dropbox progress jumped to 100% straight away.
- The server speed test showed numbers way too high.
- At login the main window popped open instead of just the menu bar icon.

### Behind the scenes
- `~/.amnesia/trace.log` keeps the last few hundred steps (times and step names only) to track down problems. Crash reports are kept too.
- Time limits on cleanup steps that could hang.

## v5.9.1 · From scripts to a real Mac app (Oct 6, 2026)

Covers v5.0 up to v5.9.1. The day Amnesia got a face.

### The app
- **A native SwiftUI app** with a menu bar icon and a new logo (a shield with a keyhole and fading dots). It only runs once, lives in `/Applications`, and shows its version next to the title.
- **Welcome tour:** language, how it works, a quick check, your apps, Profile Vault setup and your daily routine. Ends with a "What should stay?" page and a "Read this first" page you have to tick.
- **English and Indonesian.** English is the main language; Amnesia follows your Mac's language on a fresh install.
- **Ready straight from GitHub:** the app carries its own scripts and 7-Zip, and sets itself up in `~/.amnesia`. Install with the .dmg or `brew install --cask navi-crwn/tap/amnesia`.
- **Settings page** with auto snapshot at logout, a notification after login, and a check before logout that shows what will be deleted (Continue or Cancel).
- **Pick what stays:** an app picker, details per app (what's kept, where, how big) and your own Keep folder anywhere you like.
- **Full Disk Access asked once,** with a button to the right Settings page.

### Profile Vault
- Encrypted snapshots of your logins: Chrome, Claude, Claude Code, OpenCode, Gemini, Kimi, GitHub CLI, WhatsApp and more.
- Choose which apps go in, change the vault password, progress bars for Snapshot, Restore and Save & Log Out.
- Panic word you type twice, so a typo can't lock you out.
- **Move to a new Mac** in 4 simple steps, Keychain keys included.

### Backup
- **USB drive, your own server (SSH) or the cloud** (Google Drive, Dropbox, OneDrive, Box, pCloud), connected without Terminal.
- **Scheduled backups** (daily or weekly), with the password saved in Keychain if you want.
- Add any folder, also outside your home folder.
- Clear messages when a server can't be reached, and why.

### Safety
- **Safe uninstall:** `bash ~/.amnesia/uninstall.sh` removes the login agent first, so nothing can start a wipe. Never just drag the app to the Trash.
- **Terms & warning** (`TERMS.md`) linked from everywhere. Amnesia really deletes data.
- Privacy note: no servers, no tracking, nothing leaves your Mac unless you set up a backup.

### Fixed
- Turning Amnesia on again could start a cleanup in the middle of a session.
- A bunch of small things: cut-off labels, a checkbox that looked ticked when it wasn't, system folders in the Keep List picker, screenshot script hiccups.

## v4.0 and earlier · The script days (Oct 6, 2026)

- Cleaning **before** logout, restart and shutdown, plus a re-check at login.
- The first Profile Vault: encrypted snapshots, 3 wrong passwords and the vault is gone, and a panic word.
- `--dry-run` to see what would be deleted, a flexible Keep List, and the first automatic tests.
- Pause that only lasts one session.
