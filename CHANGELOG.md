# Changelog

**English** · [Bahasa Indonesia](CHANGELOG.id.md)

Everything that changed in Amnesia, newest on top.
Quick backstory: on October 6, 2026 Amnesia was a handful of scripts. Two days and a lot of coffee later it's a real Mac app with a vault, backups and its own website. To keep things readable, those two busy days are grouped into three chapters below instead of 30 tiny entries.

Your version number is next to the Amnesia title and at the bottom of the menu bar panel.

## v5.26.0 · A Profile Vault you can follow step by step (Nov 2, 2026)

**Turn Off** Amnesia before installing, then turn it on again.

### Changed
- Profile Vault now has three numbered steps, in the order you use them: 1 pick the apps to save, 2 save your logins now (Snapshot Now), 3 bring them back after you log in (profile, password, Restore Profiles). Password, panic word, moving to a new Mac and the delete buttons are in Vault settings at the bottom.
- In step 1, Change… opens the app list, other apps with logins, the light snapshot switches and folders. It opens by itself when no app is picked yet.
- In step 2, See each app shows every snapshot with its size and its own trash button.
- Settings show one line per setting. The ⓘ button next to a title opens its explanation, and explanations also show while you search. Longer cards (Keep lock, Brankas, Terminal command, auto logout) have an Info link instead of a long text.
- README texts are shorter and plainer.

### Fixed
- VoiceOver reads the name of every button and switch: Back, Settings, the minus and trash buttons, switches, home tiles and group titles. The names sit inside the controls now, and a test checks this.
- A preview that can't read the Keep List says "STOPPED, nothing was checked" instead of "0 items would be deleted". The preview also accepts a Keep List given as a pipe (`--keep-file=<(...)`).
- Going back to Everything in Memory Recall keeps `profiles.json` and writes "last: all" in it, instead of deleting the file.

### Privacy
- Two files from the developer's own Mac were in the repository since v5.8: `report.txt` (a list of files a cleanup would delete) and `apps_baseline.txt` (installed apps). They are removed from the repository and can't be added by the release script again. Your own copies of these files are never uploaded by the app.
- The release script now writes the same `.gitignore` as the repository, so `profiles.json`, `keep.conf.last` and the files above stay on the Mac. A test checks both lists.

## Windows v0.11.0 · A Vault page you can follow step by step (Nov 2, 2026)

Not released yet. It comes with the next Windows release, together with everything from v0.10.0 below.

### Changed
- The Vault page has three numbered steps: 1 pick the apps to save (with Change...), 2 save your logins now (Snapshot now, and when they were last saved), 3 bring them back after you sign in. Vault options are folded away below.
- Settings and Vault cards show a small Info button; the grey explanations open with it, and show while you search.

### Fixed
- Going back to Everything for a restore keeps `profiles.json` (it now says "last: all") instead of deleting it.

## v5.25.0 · Amnesia modes, vault profiles and Ask an AI (Oct 26, 2026)

This release also contains everything from v5.24.0 below, which was never released on its own.

**Turn Off** Amnesia before installing, then turn it on again.

### New
- **Amnesia modes: pick how much is forgotten at every logout.** Retrograde Amnesia, Selective Amnesia (recommended), Partial Amnesia or Custom Amnesia.
  - **Retrograde Amnesia** is like a brand-new account at every login. Only your Keep folder and what Amnesia needs to work stay. Auto snapshot at logout is turned off; your snapshots stay and you can still restore by hand.
  - **Selective Amnesia** is the basic list for a new install: your Keep folder, app logins from the vault, SSH keys, Git and shell settings. The default list no longer contains the developer's own apps (VPN apps, terminal tools); you add your own apps on the Keep List. Your existing Keep List is not changed.
  - **Partial Amnesia** lets apps keep their settings and logins in place. Your files, Downloads, Desktop, caches, logs, the Trash and shell history are wiped. Honest note: browsing history and cookies inside a browser's own folder stay too, because that folder is kept.
  - **Custom Amnesia** is your own Keep List. It is picked for you when you change the lines a mode added.
- **Every mode switch shows a preview first**: what will now be wiped and what will now be kept, with a warning when more is wiped. It takes effect at the next logout.
- **Your own Keep List lines stay**: a mode only changes its own marked section.
- **Vault profiles: restore only what you need**, like Work or Personal, or everything. You can rename, add and remove profiles. When one app is in two profiles, Amnesia says so: one browser holds one set of logins, so a second browser (or a separate browser profile) keeps personal use apart.
- **Ask an AI: advice without sharing your files.** Amnesia makes a report with no file contents and no names of your files, plus a ready prompt. You paste it into the AI you choose, then paste the answer back and tick the changes you want. You can also hide folder names, and save the report to your Keep folder.
- **Terminal command `amnesia`**: status, preview, report, keep, history. Read only, it never deletes anything. Switch it on in Settings.

### Safer
- **Amnesia makes no network calls for Ask an AI**: nothing leaves the computer unless you paste it somewhere.
- **A missing or damaged mode file never empties your Keep List**; the mode is just not changed.
- **Nothing an AI suggests is applied without your tick and confirm**; Amnesia's own lines can't be removed this way.

### Simpler and fixed after testing
- **Virtual machines and Photos are no longer added to your Keep List by themselves.** When Amnesia finds virtual machines (UTM, Parallels, VirtualBox, VMware Fusion) or a Photos library that is not kept, the Keep List and What Gets Deleted pages show a warning with the size and two buttons: **Keep** or **Don't Keep**. Lines you already have stay as they are.
- **Settings are grouped**: Logout, Keep, App, and Safety & checks. Rarely used things (Terminal command, Brankas, auto logout, removing new apps, panic word, moving to a new Mac) are under **Show advanced settings**, closed until you open it. Searching still finds everything.
- **Settings search shows the first hit at the top**, not above the window.
- **Opening the Keep List page no longer writes the mode to settings.conf**; it is only written when you really switch mode. Picking **Everything** in Memory Recall no longer creates `profiles.json`.
- **The mode preview no longer says `.zshrc`, `.zprofile` or `.gitconfig` will be wiped.** Amnesia never wipes those files in your home folder; lines that leave the Keep List but wipe nothing are listed apart.
- **Small snapshots show their real size** (GitHub CLI showed "0 KB").
- **Health Check no longer lists apps in the Profile Vault (like Chrome) as big files that get deleted**: they come back with Restore Profiles.
- **Sizes use the same units everywhere** (1 MB = 1000 KB, like Finder): the app, the Terminal command and the Ask an AI report.
- **Ask an AI: "Don't show this again"** on the Copied message.
- **Accessibility**: every switch, picker and icon-only button has a name for VoiceOver, and a test checks it.

### Website and README
- **Both websites and the README** have a section for modes, vault profiles and Ask an AI, and list Mac v5.25.0 and Windows v0.10.0.
- **`SECURITY.md`** says what the Ask an AI report contains and that it stays on your computer unless you paste it.
- **`llms.txt`** tells AI assistants how to use `amnesia report` and the suggestion format.

## Windows v0.10.0 · Amnesia modes, vault profiles and Ask an AI (Oct 26, 2026)

Not released yet. It comes with the next Windows release.

This release also contains everything from v0.9.0 below, which was never released on its own.

### New
- **Amnesia modes: pick how much is forgotten at every sign out.** Retrograde Amnesia, Selective Amnesia (recommended, same as before), Partial Amnesia or Custom Amnesia.
  - **Retrograde Amnesia** is like a brand-new account at every sign in. Only your Keep folder and what Amnesia needs to work stay. The vault's auto snapshot at sign out is turned off; your snapshots stay and you can still restore by hand.
  - **Selective Amnesia** keeps your Keep folder and brings app logins back from the vault, as before.
  - **Partial Amnesia** lets apps keep their settings and logins in place: everything in AppData stays. Your files, Desktop, Documents and Downloads are wiped. Honest note: because all of AppData is kept, browsing history and cookies inside a browser's own folder (Edge too), Temp files, recent file lists and PowerShell history stay as well. Thumbnail and icon caches, notification history, the Recycle Bin, the clipboard and the registry's recent lists are still wiped.
  - **Custom Amnesia** is your own Keep List. It is picked for you when you change the lines a mode added.
- **Every mode switch shows a preview first**: what will now be wiped and what will now be kept, with a warning when more is wiped. It takes effect at the next sign out.
- **Your own Keep List lines stay**: a mode only changes its own marked section.
- **Vault profiles: restore only what you need**, like Work or Personal, or everything. You can rename, add and remove profiles. When one app is in two profiles, Amnesia says so: one browser holds one set of logins, so a second browser (or a separate browser profile) keeps personal use apart.
- **Ask an AI: advice without sharing your files.** Amnesia makes a report with no file contents and no names of your files, plus a ready prompt. You paste it into the AI you choose, then paste the answer back and tick the changes you want. You can also hide folder names, and save the report to your Keep folder.

### Safer
- **Amnesia makes no network calls for Ask an AI**: nothing leaves the computer unless you paste it somewhere.
- **A missing or damaged mode list never empties your Keep List**; the mode is just not changed.
- **Nothing an AI suggests is applied without your tick and confirm.**

### Simpler and fixed after testing
- **Settings are grouped**: Keep (shortcuts and Keep lock), What stays safe, and App. Advanced settings are closed until you open them; searching still finds everything and shows the first hit at the top.
- **Opening the Keep List page no longer writes the mode to the settings**; it is only written when you really switch mode. Picking **Everything** for a restore no longer creates `profiles.json`.
- **The mode preview lists lines that leave the Keep List but wipe nothing apart**, instead of under "will now be wiped".
- **Sizes in the Ask an AI report use the same units as the app** (1 MB = 1000 KB).
- **Accessibility**: Remove, Keep, Delete and Uninstall buttons in lists, and checkboxes and pickers without a visible title, now tell a screen reader which item they are for.

## v5.24.0 · Care page, and a cleanup that stops when it is unsure (Oct 26, 2026)

**Turn Off** Amnesia before installing, then turn it on again.

Amnesia already wipes most of your home folder at every logout, so Care mostly matters for your Keep folder, the apps you kept and big files made during this session.

### New
- **Care: a new page to free up space on demand, always with a list to check first.** Nothing risky is ticked for you, and you confirm the count, the size and where things go before anything moves.
- **Disk overview** shows what takes space: Keep folder, vault, trash, caches, biggest folders and files, old downloads. Read only.
- **Clean now** empties caches, logs and Amnesia's trash; caches of apps that are open are skipped. Emptying the macOS Trash is listed too, but never ticked for you, because that one is permanent.
- **Uninstall apps** moves an app you installed and its caches to the Trash; its personal data stays unless you tick it.
- **Project build folders** (node_modules, target, build, dist and more) can go to the Trash; folders used in the last 7 days or tracked by git are left alone.
- **Old installers** (.dmg, .pkg) go to the Trash; disk images and virtual machines are never picked for you.
- **Safe tune-ups** without an admin password: refresh Quick Look thumbnails, restart the Dock.
- **Health check** shows free disk space, memory and battery condition.
- **Every Care run is in History** with the space freed.

### Fixed
- **The search field in Settings stays at the top** while you scroll the settings.

### Safer
- **The cleanup stops and deletes nothing when the Keep List cannot be read or has gone missing**, and says so in History.
- **A copy of your last good Keep List is kept** and used to restore it.
- **Every delete goes through one check** that refuses the home folder, the Keep folder, `~/.amnesia` and anything outside your home folder (except new apps you asked Amnesia to remove).
- **When a check cannot tell** (cloud, iCloud, links, owner), the item is kept.
- **At login and on Clean Now, folders that an open app is still using are skipped** and wiped next time.

### Website and README
- **Both websites and the README** have a Care section and list Mac v5.24.0 and Windows v0.9.0.
- **New `SECURITY.md`**: how to report a security problem privately, and an honest list of what Amnesia protects and what it can't.
- **New `llms.txt`**: a short guide for AI assistants that help someone install Amnesia, so they check What Gets Deleted and the Keep folder first.
- **Where to get Amnesia**: the README now says it only comes from github.com/navi-crwn/amnesia, its website on GitHub Pages and the Homebrew tap `navi-crwn/tap`.

## Windows v0.9.0 · Care page, and a cleanup that stops when it is unsure (Oct 26, 2026)

Not released yet. It comes with the next Windows release.

Amnesia already wipes most of your user folder at every sign out, so Care mostly matters for your Keep folder, the apps you kept and big files made during this session.

### New
- **Care: a new page to free up space on demand, always with a list to check first.** Nothing risky is ticked for you, and you confirm the count, the size and where things go before anything moves.
- **Disk overview** shows what takes space: Keep folder, vault, Recycle Bin, Temp, biggest folders and files, old downloads. Read only.
- **Clean now** empties Temp, crash dumps, app caches and Amnesia's trash. The Recycle Bin is listed too, but never ticked for you, because emptying it is permanent. Files Windows still has open are skipped and counted, not shown as errors.
- **Uninstall apps**: programs installed just for you run their own uninstaller, programs installed for everyone open Windows Settings. Leftover caches go to the Recycle Bin; personal data stays unless you tick it.
- **Project build folders** (node_modules, target, build, dist, and bin and obj of .NET projects, and more) can go to the Recycle Bin; folders used in the last 7 days or tracked by git are left alone.
- **Old installers** (.msi, .msix) go to the Recycle Bin; setup .exe files are listed but never picked for you, and disk images and virtual machines are never picked for you.
- **Safe tune-ups** without admin: restart Explorer, open Startup apps and Storage settings.
- **Health check** shows free disk space, memory and battery charge.
- **Every Care run is in History** with the space freed.

### Safer
- **The cleanup stops and deletes nothing when the Keep List cannot be read or has gone missing**, and says so in History.
- **A copy of your last good Keep List is kept** and used to restore it.
- **Every delete goes through one check** that refuses the user folder, the Keep folder, `.amnesia` and anything outside your user folder.
- **When a check cannot tell** (cloud folders, links, owner), the item is kept.

## v5.23.1 · Long popups scroll, websites and README catch up (Oct 18, 2026)

**Turn Off** Amnesia before installing, then turn it on again.

### Fixed
- **Long popups scroll now.** Restoring many apps made the result popup taller than the screen, so you couldn't reach its buttons. Popups now stop at about half the screen height and scroll inside; the OK and Cancel buttons always stay visible.

### Website and README
- **Seven languages (added Oct 20).** Both pages now come in English, 简体中文, Deutsch, Bahasa Indonesia, 日本語, Português (Brasil) and Español, each at its own address (for example `/de/` and `/de/win/`). A globe menu at the top switches language; on your first visit the English page sends you to your browser's language if there is a page for it. The pages are built from one source by `site/i18n/build.py`. The README has a language bar that links to each one.
- **Mac page** shows v5.23: six new feature cards (Keep lock, Health check, Brankas, signed updates, safe with iCloud, Claude and Claude Code), Undo Restore, how to check a download, and five new FAQ answers. It no longer scrolls sideways on a phone.
- **Windows page** rebuilt for v0.8: the open source section with the 3D commit chart, a 3D folder board for what's safe at sign out, a 3D safe box, the Health check, real Windows warnings, an 8-step tutorial and 36 new screenshots of the app. A wrong FAQ answer is fixed: cancelling a sign out doesn't undo the cleanup any more.
- **README** (English and Indonesian) lists the latest versions and features and has a section for Amnesia for Windows. The update check is weekly to monthly, not daily. `windows/README.md` no longer says "preview, test in a VM".

## Windows v0.8.2 · Long questions scroll (Oct 18, 2026)

Not released yet. It comes with the next Windows release.

### Fixed
- **Long questions scroll inside the popup**, so the buttons always stay on screen. The welcome tour also scrolls on a small window.

## v5.23.0 · Claude in your Keep List really stays, safer restores, Brankas closes properly (Oct 17, 2026)

**Turn Off** Amnesia before installing, then turn it on again.

Everything here comes from a real test on a Mac on Oct 17. The bugs from the last test (symlinked folders, accented names, failed deletes counted as cleaned) all passed this time.

### Fixed (important)
- **Claude was on the Keep List, but your Claude Code chats still vanished.** The Keep List only kept the Claude Desktop app. Chats from the Code tab live in `~/.claude` and `~/.claude.json`, so they were wiped at every logout and only came back with a vault restore. Now keeping Claude keeps those too. Pick Apps adds them when you save Claude, and the cleanup also keeps them on its own as long as Claude is on your list.
- **A restore could roll your data back.** Restoring always put back the snapshot, even when the data on your Mac was newer. Now:
  - anything on your Keep List is never overwritten by a restore
  - if an app's data is newer than its snapshot, you get asked first ("Restore anyway" or Cancel)
  - after a restore there's an **Undo Restore** button on the Vault page that puts your data from just before the restore back, until your next logout
- **The Brankas didn't close at logout** ("box close failed"), only at the next login. Amnesia now tries several times, looks for apps still using it (it only counts them, no names), then forces it closed. If it still fails, you get a notice after login and a warning in the Health check.

### Fixed
- **The auto snapshot at logout no longer skips** when you made a snapshot less than 10 minutes earlier. Before, work you did after a manual snapshot could be lost. Apps that didn't change are still skipped, and a stuck snapshot can never hold up the cleanup.
- **Apps come back after Snapshot Now.** Apps that were open and got closed for the snapshot are opened again afterwards, just like after a restore.
- **Health check** now also shows Full Disk Access, symlinked folders and virtual machines when they're fine, and a warning if the Brankas couldn't close. "1 things" now reads "1 thing".
- **The "before restore" copy** (it can be several GB) no longer shows up as a scary big file. The Health check explains what it is and when it goes away, and copies older than 3 days are removed.
- **Keep lock:** the Settings text and the Limitations page now say it plainly: names of files and folders right inside Keep are still visible while it's locked.

## Windows v0.8.1 · Sign out cleans right away, "Keep" on a new app really keeps it (Oct 17, 2026)

Everything here comes from a real test on a Windows 11 laptop on Oct 17.

### Fixed (important)
- **A normal sign out still cleaned only at the next sign in.** Closing the safe box and making the list used up the few seconds Windows gives, so the cleanup barely started. Now Amnesia cleans first, right when Windows asks "may I sign out?", shows "Amnesia is cleaning up..." while it works, and closes the safe box after that (it lives in Keep, so it's never wiped). One trade-off: if you cancel the sign out after that point, the cleanup has already happened, like "Clean now".
- **"Keep" in the new apps list didn't keep the app.** You pressed Keep, but the app's program folder in AppData was still wiped at sign out, leaving a broken app. Keep now also puts the app's program folder and data folders on your Keep List.
- **New apps were deleted for good instead of waiting 3 days.** The normal cleanup got to their folder first. Now a new app's folder always goes to the Amnesia trash for 3 days.
- **The safe box card said "Throwaway Windows".** Its text was mixed up with Windows Sandbox. Both cards have their own text and buttons again.

### Fixed
- **Panic is faster** with a big safe box: Amnesia asks Windows to sign out right after cleaning and closes the safe box while Windows signs out.
- **Uninstall warns you** when your safe box still has files in it. It also no longer keeps a second full copy of the safe box on disk.
- **New apps list is easier to read:** one app is one row (no more registry numbers like "121a0be4-…"), and an app that only got updated (a new version number) isn't treated as new any more. "Keep all" is written to the log and History.
- **Startup warning** now shows up in a window that's already open, and Amnesia notes it in trace.log. A wrong Keep password at uninstall is logged too (never the password itself).
- **Keep List suggestions:** one app with folders in both Local and Roaming is one chip that keeps both. Technical folders like Sentry or crash folders are no longer suggested.
- **Keep still locked from an older version:** Amnesia notices, and offers to open it from the home page and the Health check.
- Automatic tests: 294 (was 273).

### Still needs a test on a real PC
- A normal sign out with lots of files cleans before the sign in screen.

## v5.22.0 · Signed updates, iCloud-safe cleaning, Keep lock, Health check (Oct 17, 2026)

**Turn Off** Amnesia before installing, then turn it on again.

### New
- **Keep lock (new).** Finder and other apps can't open or change what's in your Keep folder until you type the Keep password in Amnesia. It locks again after 5–60 minutes, when the screen locks, when Amnesia quits, and at every logout and login. To be clear: this uses macOS permissions, not encryption. Anyone logged in as you can remove it with `chmod -RN ~/Keep`. Off by default (Settings → Keep lock).
- **Brankas (experimental).** An encrypted disk (APFS, AES-256) inside your Keep folder, for files that really must stay secret. Amnesia closes it before every cleanup. If you forget its password, the files in it are gone.
- **Health check.** One page that shows:
  - whether Amnesia is on and the login agent points to a real app
  - Full Disk Access
  - iCloud Desktop & Documents, and folders that are symlinks
  - virtual machines that are not kept, and files of 1 GB or more about to be deleted
  - how old your last backup is
  - update check, Keep lock and FileVault

  Most rows have a button that fixes the problem.
- **Limitations page.** A plain list of what Amnesia can't wipe: Time Machine and APFS snapshots, Spotlight, iCloud and other clouds, swap and sleepimage, system logs, other accounts, and the Keep folder (not encrypted).
- **More apps in Profile Vault:** Signal, Session, Element, Telegram, Obsidian, Notion, Zoom and Bitwarden. Each one starts unticked, so you pick what goes in.
- **Vault suggestions.** Amnesia lists other installed apps that look like they keep a login (they have a "Safe Storage" item in Keychain). Nothing is added until you tick it, and you can take it out again.
- **Password strength meter** for the vault, Keep lock and Brankas passwords. It's a rough guess, not a promise.

### Fixed
- **Folders that are symlinks are never emptied through the link.** Before, if `~/Documents` pointed into your Keep folder, cleaning Documents emptied Keep.
- **Keep List names with accents ("Café") match whichever way macOS stores them (NFC or NFD).** Before, a name typed in Amnesia could miss the same name coming from Finder or an old backup.
- **iCloud Desktop & Documents: Desktop and Documents are skipped.** Wiping them would delete the files in iCloud and on your other Apple devices too. Amnesia logs it and tells you on the What Gets Deleted page and in the Health check. If it isn't sure, it skips them: better a file left behind than one deleted from iCloud.
- **Files that couldn't be deleted are no longer counted as cleaned.** The last-cleanup line and History now say "N could not be deleted". Amnesia tries them again next time. trace.log only gets the count and the area (like "Downloads"), never file names.
- **Emptying Amnesia's trash is logged now.** Before, it ran silently in the background. Leftovers are counted and shown in the app.
- **Vault jobs can't run on top of each other.** A second snapshot or restore now waits, then stops with a clear message. Leftovers from a job that was cut off are cleaned up first.
- **Restore no longer writes the vault's private key to disk.** It stays in memory.
- **Saving the backup password in Keychain** no longer puts it in the command line, where other programs on the Mac could see it.
- **Moving or renaming Amnesia.app no longer turns protection off silently.** You get a notification while you're still logged in, and the reason is in trace.log.

### Changed
- **Updates from inside the app must be signed.** Amnesia only installs an update if `SHA256SUMS.txt` has a valid developer signature (ECDSA P-256). If the signature is missing or wrong, it sends you to the release page instead.
- **A backup where 7-Zip could not read some files** (open in another app, no permission) is now "finished with warnings", not plain "done". You see what was skipped. That list is shown only, never saved.
- The Backup page now says what is left out on purpose: folders named `node_modules` or `.tmp`, and `.DS_Store` files.
- The Doomsday, panic-word and Delete Vault texts now say plainly how deleting works:
  - files are removed the normal way, not overwritten
  - the vault itself is encrypted
  - files emptied from Keep are not encrypted
  - backups, Time Machine and the cloud are not touched
- Uninstalling (from the app or `uninstall.sh`) asks for the Keep password and unlocks Keep first. Without the password, Keep stays locked and you get the command that opens it: `chmod -RN ~/Keep`.

## Windows v0.8.0 · Keep can't be touched by "Remove new apps", cloud folders and VMs stay, a Health check (Oct 17, 2026)

Turn Amnesia Off before installing over an older version, then turn it On again.

This version comes from a full audit and a test on a real Windows 11 laptop. The first two fixes are the big ones: please update.

### Fixed (important)
- **"Remove new apps" could delete a folder inside Keep.** In the test it took a folder that was on the Keep List, for good. Now it only takes an app's own folder in AppData, never anything on the Keep List, never a folder that holds something kept, and never shared folders like Programs or Packages. And it no longer deletes right away: the folder goes to Amnesia's trash and waits **3 days** first.
- **Cloud folders are never wiped any more.** Dropbox, Google Drive, iCloud Drive, Nextcloud, MEGA, Box, pCloud, Proton Drive and others stay where they are, plus every folder Windows itself knows as a sync folder. Before, moving them away looked like "deleted" to the sync app, which could then delete your files in the cloud too. Files that are only in the cloud ("Files On-Demand") are left alone too.
- **Virtual machines and big disc images stay.** VirtualBox, Hyper-V, VMware, WSL, Docker and Android emulator disks, and .iso files of 1 GB or more. You can switch this off in Settings > Protection.

### Fixed
- **Sign out is faster and more reliable.** Amnesia makes the list of what to wipe the moment Windows asks to sign out, skips counting sizes, and stops a running vault snapshot so the cleanup gets the time. trace.log now writes how long each step took. (Normal sign out sometimes left the wipe for the next sign in; this needs one more test on your laptop.)
- **Panic while Paused now works.** A quick exit cancels the pause, kills Explorer, wipes its thumbnail and icon caches, cleans, and signs out. If Windows is slow to sign out, it tries again after 8 seconds.
- **Startup switched off = Amnesia silently stopped.** If Task Manager's Startup apps turns Amnesia off, the home page now shows a warning with a **Switch it back on** button. While Amnesia is off it no longer starts with Windows at all (new switch: Settings > Protection > Open at login).
- **Keep stayed locked after uninstall.** Uninstalling from the app now asks the Keep password and opens Keep first. Uninstalling from Windows Settings asks it too. Without the password Keep stays locked and you get the one command that opens it.
- **The uninstaller no longer deletes Amnesia's data by itself.** It asks first (default No), and never while Keep is still locked.
- **A Keep List line that didn't save** now shows an error instead of a silent "Saved".
- **Backups:** an old backup inside Keep is no longer packed into every new one, a backup folder inside Keep is refused, files in use are counted and named in the result, and a restore that was cut off (power cut) cleans up after itself and puts your old vault back.
- **The window was too narrow at 150% scaling.** It now grows with Windows scaling.
- A crash when the window closed while a long job was still answering.
- Pause is written in the history as "Paused for one session" (it said "turned off" in the log).
- The elevated helper only reads its own list of folders to delete.

### New
- **App icons and names in the Keep List.** Rows show "Discord" with its icon instead of only a path. **Keep an app** lists installed apps (also Microsoft Store apps) and keeps all of an app's folders with one click.
- **Health check** on the home page: is Amnesia on, does it start with Windows, last cleanup, files left behind, cloud folders, vault, backup, Keep lock. Below it: **What Amnesia can't do**, the honest limits.
- **Signed updates (free).** The in-app updater now also checks a signature from the developer on SHA256SUMS.txt. No signature, no install from the app: it opens the release page instead.
- **Safe box (experimental):** a locked folder inside Keep. Closed it is one encrypted file, open it is Keep\Safe. Amnesia closes it again at every sign out.
- **Optional:** also wipe Microsoft Store app data, and also wipe saved app passwords in Credential Manager (never your Microsoft account, OneDrive or Office). Both off by default.
- **Vault:** Session, WhatsApp, Element, Obsidian, Thunderbird, Bitwarden, Antigravity, Windsurf, Gemini CLI and OpenCode. The vault also suggests installed apps it doesn't know yet. A password strength meter, and the Doomsday text now says honestly what it can't stop.
- **Setup:** a welcome page, the terms, a short warning before installing and a short tour after, in English and Indonesian.
- Automatic tests: 273 (was 207).

### Still needs a test on a real PC
- Normal sign out cleaning right away (not at the next sign in).
- Thumbnail cache after a normal sign out.
- Keep List with Microsoft Store app folders.

## Windows v0.7.2 · No more "Test in a VM" badge, a full Windows website (Oct 14, 2026)

Turn Amnesia Off before installing over an older version, then turn it On again.

- The "Test in a VM" badge next to the name is gone, and so is "test in a VM before your real PC" in the welcome tour. The app works the same as v0.7.1.
- **New Windows website:** the Windows page now looks like the Mac one, with the same animations, real screenshots of the app (English and Indonesian, dark and light), install steps with the SmartScreen warning explained, Keep lock and lab lock, and a Windows FAQ.
- **Mac website:** shows the v5.20 and v5.21 features (search in Settings and in What Gets Deleted, developer tools, update schedule, virtual machines kept, the Trash group) and fixes the old "checks for updates once a day" answer.

## v5.21.0 · New apps in the preview, search in "What Gets Deleted", virtual machines kept safe (Oct 13, 2026)

**Turn Off** Amnesia before installing, then turn it on again.

### New
- **Search in "What Gets Deleted".** A search box (name or path, across every group), a group picker and **Biggest first**. Every row now shows its size right away, without opening its group.
- **Big file warning.** A warning at the top of the list when files of 1 GB or more, or virtual machine data, are about to be deleted. It shows the four biggest with their sizes and suggests moving them to Keep.
- **Virtual machines are safe by default.** UTM, Parallels, VirtualBox and VMware Fusion are now in Pick Apps. When Amnesia finds VM data, it adds it to the Keep List automatically (once; if you switch it off, it stays off). Switched off, the row clearly says "Wiped at logout, virtual machines too!".
- **The Trash has its own group:** "Trash (emptied at logout)", with its size, so nobody is surprised when the Trash is gone.

### Fixed
- **Apps installed after Amnesia was turned on didn't show in the preview**, although they really are removed at logout. They now show in "Apps installed later", with their icons.
- Apps that opened by themselves at login (before the vault was restored) are now quit, then opened again once their data is back.
- Restoring a chosen folder from the vault can no longer fail with an error.

## Windows v0.7.1 · Sign out cleans again, no Explorer flicker, tidier pages (Oct 13, 2026)

Turn Amnesia Off before installing over an older version, then turn it On again.

### Fixed
- **Sign out didn't clean** (files were only removed at the next sign in). The automatic vault snapshot ran first and used up the time Windows gives. Now Amnesia **cleans right away** at sign out, and Windows shows "Amnesia is cleaning up..." until it's done. If the sign out is cancelled, nothing is removed.
- **The automatic snapshot moved:** vault apps are saved in the background **after you close them** (checked every minute, only when changed). Tools without a window (Claude Code, Git, chosen folders) are saved after 3 minutes without changes. Note: if Edge keeps running in the background ("startup boost"), it is only saved once it really closes.
- Leftovers of an interrupted snapshot (`*.amv.new`) are removed when Amnesia starts.
- **The Keep lock made Desktop icons flicker.** The lock now closes what's inside Keep, not the folder itself, so Explorer can still read Keep's icon. Keep leaves the sidebar while locked and comes back when opened. File names in Keep stay visible but can't be opened, and no program can write into Keep.
- **Explorer flickered after the clean at sign in.** Explorer is now told to reload its icons.
- Icon and thumbnail caches are never removed while Explorer is running any more (the old cause of flickering icons).
- False "Edge setup unfinished" warning in the vault.
- The "wipe free space" question is no longer cut off in a small window.
- Claude from the Microsoft Store is suggested in the Keep List too.
- The Keep icon in the sidebar turns purple too.
- The "Remove new apps" list reloads after an uninstaller finishes.

### Changed
- **Tighter pages:** a bento-style home page, the footer always at the very bottom, Settings in groups (General, Updates & help, then Advanced: Leaving the PC, Privacy & Windows, Programs, Locks).
- **Search in "What gets wiped"**: a search box, a folder filter (with counts and sizes) and Biggest first.
- **Collect log** shows a status and the file location, and its button can't be clicked twice.
- The Keep shortcut card says "shows up after Turn On" while Amnesia is off.
- Automatic tests: 207 (was 190).
- **Out of test status.** The website, README and the turn-on question no longer say "virtual machine only". Found a bug or want a change? Open an issue on GitHub.

## v5.20.0 · Search in Settings, a resizable window, smarter app picking (Oct 12, 2026)

Turn Amnesia **Off** before installing, then turn it On again.

### New stuff
- **Search in Settings.** Settings has a search box on top. Type in English or Indonesian, whatever the app language is, and only the matching settings stay. Other words work too, like "filevault", "password", "startup", "idle", "migrate" or "version". If nothing matches, the app says so.
- **Advanced is now part of Settings**, as a group at the bottom under the normal settings, and the search covers it too. The separate Advanced page is gone (same as the Windows app).
- **Resizable window.** Make the main window bigger or smaller, down to 440×560. It still opens at 480×690, and on a small screen it opens smaller so it fits.
- **Better app detection in "Pick Apps".** Amnesia now finds more of an app's data by its bundle id: web logins (HTTPStorages), WebKit data, team-named shared folders and folders named after the app's real name. Caches and saved window state are left out on purpose.
- **Developer tools & terminal.** "Pick Apps" has a new section with the settings of SSH, GitHub CLI, zsh/bash, Vim/Neovim, tmux, npm, Docker, AWS, gcloud, kubectl, OpenCode, Claude Code, Codex and Gemini CLI. Only the ones that exist on your Mac show up.
- **Choose how often to check for updates:** Off, every week, every 2 weeks or every month. The default is every week. The old daily check becomes weekly by itself, and Off stays Off.

### Fixed & safer
- An app that you kept before shows as ON in "Pick Apps" even when Amnesia now knows extra folders for it, so pressing Save only **adds** lines to your Keep List and never removes your old ones.
- Switching one app off no longer removes a folder that another app you kept still needs.

## Windows v0.7.0 · Lab lock, Keep lock, a spare vault snapshot and calmer update checks (Oct 12, 2026)

Windows preview, still **test it in a virtual machine only**. Turn Amnesia Off before installing over the old version, then turn it On again.

### New stuff
- **Lab lock** (Settings → Advanced, for administrators). For a PC many people use, like a computer lab or a library. Set a PIN of 6 or more digits, and Windows asks for administrator permission once. From then on this Windows user can't turn Amnesia off, pause it, quit it, uninstall it, or change the settings and Keep List without the PIN. Amnesia always starts at sign in (started by Windows, not by the user), and the page shows "Locked by the administrator". The PIN opens the settings for 10 minutes. The locked copy lives in `C:\ProgramData\Amnesia\lab`, which normal users can only read. Honest note: someone can still end Amnesia in Task Manager, but the check at the next sign in cleans anyway.
- **Keep lock** (Settings → Advanced). The Keep folder can only be opened through Amnesia (Open Keep, the tray menu or the Desktop shortcut) with its own password. It locks again after the minutes you pick, when you lock the screen (Win+L), at sign out and when Amnesia starts. Backup, restore, Collect log and Doomsday unlock it by themselves for a moment. Honest note: the files are not encrypted (use BitLocker for that), and someone who signs in as you and knows Windows can remove the lock in the folder's Properties. Forgot the password? Same way: Properties → Security, remove the "Deny" line.
- **A spare vault snapshot.** Each app keeps the snapshot before the newest one as "previous". If a new snapshot is much smaller than the last one (for example taken from an empty, fresh profile), the vault says so, and ticking **Use the snapshot before the newest one** when you restore brings back the older one.
- The vault notes when a browser snapshot (Edge, Chrome...) was taken before its first-run setup was finished, because restoring it shows the welcome pages again.
- **Choose how often to check for updates:** Off, every week, every 2 weeks or every month. The default is every week instead of daily.

### Fixed & safer
- Uninstalling a PC with the lab lock asks for the lab PIN, and then removes the lab lock completely.
- "Collect log" waits until the log is really written before it says it's done.
- New automatic tests (190 in total): PIN, lab lock settings, previous snapshot, smaller snapshot warning and the Edge setup note.

## Windows v0.6.1 · Same app, fixed GitHub build (Oct 11, 2026)

No changes in the app itself, same as v0.6.0. The license notes file (`THIRD-PARTY-NOTICES.md`) was left out on GitHub because of a "skip .md files" rule, so the automatic Windows build there failed and v0.6.0 never got a download. The rule now lets that file through, and this version makes the release with Setup x64 and arm64.

## Windows v0.6.0 · Looks like the Mac app, and sign out from Start cleans again (Oct 11, 2026)

Windows preview, still **test it in a virtual machine only**. Turn Amnesia Off before installing over the old version, then Turn it On again.

### Fixed
- **Sign out or shut down from the Start menu sometimes skipped the cleanup.** Windows only waits for programs that have a window, and Amnesia's sign out watcher was hidden, so Windows closed Amnesia after a few seconds while it was still busy. Now the watcher is a real (invisible, click-through) window, so Windows shows "Amnesia is cleaning up..." and waits. The auto snapshot starts as soon as Windows asks to sign out, gets at most 20 seconds, and the cleanup runs after it either way.
- **"Amnesia (Not Responding)"** when you pressed Apply in Advanced (Windows data, clipboard and so on), saved settings or opened the vault. All that work now runs in the background, so the window stays responsive.
- **Dead Amnesia icon left in Start after uninstalling.** The uninstaller now restarts the Start menu so the icon disappears.
- **Claude from the Microsoft Store** is now found by the vault too (it keeps its data in a different folder than the normal Claude app).
- The Doomsday reset now also clears which apps and folders were ticked for the vault, so a new vault starts clean.

### Changed
- **New look, like the Mac app.** No more tabs. The home page has the big status card and buttons (Vault, Review & sign out, Pause, Keep, Backup, History), each page has a Back button, and the window is narrower (max 560 px, you can still resize it).
- **Advanced is now part of Settings**, in its own group under the normal settings, with a **search box** on top (works in English and Indonesian).
- **Keep folder has its own icon** (a purple folder with the Amnesia logo), the Desktop shortcut too. Uninstalling puts the normal folder icon back.
- "Collect log" now saves the log into your Keep folder (it used to go to Public Documents).
- "Remove new apps" warns that apps from the Microsoft Store are removed too.
- trace.log now says which areas were in use when something could not be deleted.
- Clearer texts in several places (encryption, vault restore problems, Keep).
- New automatic tests (172 in total).
- **Website and README:** the Windows page now says **Work in progress · v0.6.0**, lists what really works, and explains how to download the Setup from Releases (no more Artifacts). The "Coming next" list is updated.

## Windows v0.5.2 · No more flickering Desktop (Oct 11, 2026)

Windows preview, still **test it in a virtual machine only**. Includes the v0.5.1 Edge fix below.

### Fixed
- **Desktop icons flickering, Explorer eating CPU, and new or copied files not showing until you refresh.** The sign in check deleted Explorer's own icon and thumbnail caches and the "shellbags" (how each folder is shown, the Desktop too) while Explorer was already running, and then told Explorer that *every* icon had changed. Explorer kept rebuilding and lost track of the Desktop. Now:
  - Explorer's caches (icon cache, thumbnails, Start menu and shell caches) and the shellbags are only wiped **at sign out**, when Explorer is gone. The sign in check and "Clean now" leave them alone and write how many they skipped in trace.log.
  - Explorer only gets "this folder changed" for Desktop, Documents and your user folder, no more "all icons changed".
  - Everything else (recent files, Notepad tabs, clipboard, Paint history...) is still wiped at the sign in check too.
  - Honest note: until the sign out bug is fixed (sign out or shut down from Start sometimes skips the cleanup), thumbnails can stay until a sign out that does clean. The panic key and idle sign out always clean.
- 4 new automatic tests (168 in total).

## Windows v0.5.1 · Edge comes back from the vault (Oct 11, 2026)

Windows preview, still **test it in a virtual machine only**. A fix from testing v0.5.0 in the VM.

### Fixed
- **Restoring Microsoft Edge from the vault failed with "Access denied"** every time, even after closing Edge. Edge quietly starts itself in the background at every sign in (`--no-startup-window`), so its `User Data` folder was always held open. Now:
  - Amnesia asks Windows which programs hold the folder (the same "files in use" check Windows uses), closes Edge's own helper programs (never WebView2, which Amnesia and other apps need) and tries again a few times.
  - If Windows still won't let go of the folder, the snapshot is put back **file by file**. The few files still in use stay as they were, and the message tells you how many.
  - One app that can't be restored no longer stops the others.
  - A restore never touches the snapshots in the vault, so a failed restore can't lose one.
  - trace.log now says how each restore went, and which programs held the folder (program names only, never file names).
- 8 new automatic tests (164 in total).

## Windows v0.5.0 · Learned from 8 similar programs: more traces, privacy switches, leftovers, sandbox (Oct 11, 2026)

Windows preview, still **test it in a virtual machine only**. This version is what Amnesia picked up from BleachBit, Winapp2, Bulk Crap Uninstaller, privacy.sexy, Win11Debloat, Pearcleaner, Sandboxie and Tails. Code was only copied where the license allows it (Win11Debloat, MIT); everything else is ideas, written fresh. Details in `windows/THIRD-PARTY-NOTICES.md`. The Mac app is unchanged (still v5.19.1).

### New stuff
- **More traces wiped** (from BleachBit, privacy.sexy, Winapp2, Bulk Crap Uninstaller): crash reports (they name the programs you ran), Windows search history, Office recent files (Word, Excel, PowerPoint... any version), Paint / WordPad / Media Player / Media Player Classic / Photoshop recent files, the last place opened in Registry Editor (your favorites there stay), "recently opened" in Start, the last game you started, **Compatibility Assistant** (Windows' hidden list of every program you ran), more open/save dialog history, Remote Desktop screen cache, **Notepad's unsaved tabs**, Snipping Tool's recent captures and the **DNS cache** (which websites were opened). After the cleanup Explorer is told to refresh, so it doesn't show old things.
- **Stop Windows remembering** (Advanced, from Win11Debloat and privacy.sexy). Six groups of Windows' own privacy switches, just for your account, no admin: no recent apps/files lists, no clipboard history or sync, no web results or search history in Start, Windows stops learning from your typing and voice, no advertising ID or suggested apps, Recall / Click to Do / Copilot off. Amnesia writes down the old values first, so **Undo all** puts back exactly what was there. A tip from Tails links to Wi-Fi "Random hardware addresses".
- **Extra cleaning list** (Advanced, off by default, from Winapp2 + BleachBit). Downloads the community list Winapp2.ini (~4,000 apps) from GitHub when you press the button; Amnesia doesn't ship it, so the list keeps its own license. Only its lines for the folders that stay on purpose (AppData\Microsoft, Store apps) and your registry are used, and only for apps that are on your PC. Saved passwords, sign-in data, your Keep folder and Keep List are never touched, whatever the list says. Entries with a warning are skipped.
- **Remove new apps** now also removes the **settings new programs wrote in your registry** (`HKCU\Software\<name>`, idea from Pearcleaner and Bulk Crap Uninstaller). Windows' own names are never touched. Coming from v0.4: today's keys are written down first, so nothing old looks "new".
- **Find leftovers** (Advanced, from Bulk Crap Uninstaller "orphans" + Pearcleaner). Lists folders in Program Files / ProgramData and settings in your registry that no installed program uses anymore. "Probably safe" ones are ticked; folders with programs inside are marked "only if you are sure". Nothing is deleted until you press Delete; folders need admin (one Windows prompt) and are checked again right before.
- **Uninstall button** removes MSI programs properly (`/X` instead of `/I`, which only "repairs").
- **Throwaway Windows** (Advanced, idea from Sandboxie): opens Windows Sandbox, a fresh Windows in a window that's gone when you close it. Optional: your Keep folder inside, read only, and internet on or off. Needs Windows Pro/Enterprise; inside a VM it often doesn't work, and the card says so.
- **Wipe free space** (Advanced, idea from BleachBit): runs Windows' own `cipher /w` so deleted files can't be brought back with recovery tools. Slow, asks first.
- **USB key can shut down** (idea from Tails): choose "Clean and sign out" or "Clean and shut down" when the USB key is pulled out.
- **Windows protections (admin):** Recall now also can't be switched back on and saves no snapshots; new switches **Copilot off for everyone** and **least telemetry**; new one-time button **Clean Windows traces now** (Prefetch, Windows Temp, crash reports, memory dumps).

### Safer
- 156 automated checks now (30 new): the extra list on a pretend list and on the real Winapp2.ini (4,068 entries planned in about 0.3 s, every line passes the safety rules), saved passwords never, Keep List wins, leftovers, registry safety, Undo.
- Tested in Wine as well: the sign in check really wiped crash reports, Office recent files and the new registry history, removed only the value it should in Registry Editor's key, removed a brand-new app's registry settings but kept the old ones, and the admin switches wrote the right values.

## Windows v0.4.0 · The big one: vault, backup, Keep List page, quick exits and a real installer (Oct 11, 2026)

Windows preview, still **test it in a virtual machine only**. Everything you asked for in one package, so you only download and install once in the VM. The Mac app is unchanged (still v5.19.1).

### New stuff
- **Setup.exe.** `Amnesia-Setup-0.4.0-arm64.exe` (Windows on ARM, like your VM) and `-x64.exe` (normal PCs). It installs just for you, no admin, into `%LOCALAPPDATA%\Programs\Amnesia` (the folder the cleanup never touches), adds Amnesia to the Start menu and to Apps & features (so you can uninstall it like any app). Amnesia stays **Off** after installing. A portable zip is still there too.
- **Keep List page.** See what's on your Keep List, remove lines, add a folder with a picker or type a path. "Apps on this PC" lists app data found on your PC: click one to keep it.
- **Vault** (same idea as the Mac). Pick apps (Chrome, Edge, Brave, Vivaldi, Opera, Firefox, Discord, Telegram, Signal, Slack, Spotify, VS Code, Cursor, Claude, Claude Code, GitHub CLI, Git) or any folder. **Snapshot now** saves them locked (AES-256-GCM, a new random key per snapshot, locked with the vault's RSA key), no password needed. **Restore** needs your password. Automatic snapshot at sign out (only apps that changed, at most 60 seconds), a reminder after sign in (click it to restore), **panic word** and **Doomsday** (3 wrong passwords delete the vault; can be switched off). Change password and panic word on the same page. Honest note: Windows locks saved logins to your Windows user, so snapshots come back on the same PC and user only.
- **Backup.** Keep folder + Keep List + vault in one locked file (`amnesia_backup_YYYY-MM-DD_HHMMSS.amb`) to a folder (USB drive, another drive, OneDrive / Google Drive folder) or to your server over SSH (`scp`, built into Windows; `.ssh` is added to your Keep List). Daily or weekly automatic backups, progress bar and Cancel. Old backups are never deleted. **Move to a new PC**: pick a backup, type your vault password, everything comes back (Amnesia stays off).
- **Advanced page:**
  - **Sign out when idle** (5 to 60 minutes): 60-second countdown, move the mouse to cancel.
  - **Panic hotkey** (Ctrl+Alt+Shift+X, Q or F12) and **USB key** (pull out the chosen USB drive): the screen locks at once, Amnesia cleans up and signs you out without waiting for other apps. Also a **Panic sign out now** button and tray menu item.
  - **Remove new apps** (off by default): programs installed just for you after Turn On lose their Apps & features entry, Start menu shortcut and autostart entry at sign out (their files already went with the cleanup); Microsoft Store apps you installed are removed at the next sign in. Programs for everyone are listed with an **Uninstall** button. **Keep** keeps one.
  - **Dynamic Lock** switch (Windows locks when your paired phone walks away).
  - **Windows protections (admin, one Windows prompt):** empty the page file at shut down, turn off hibernation, stop Windows Recall screenshots, turn off activity history.
  - **Antivirus card:** shows whether Windows Security's Controlled folder access is on and how to allow Amnesia.
- **Review and sign out** (Home button and tray menu): see what goes, keep something first, then sign out.
- **More Windows traces wiped:** which programs you ran (UserAssist, MuiCache, jump list data), folders you opened ("shellbags"), taskbar usage counters, Remote Desktop history, network drive history, open/save dialog sizes, notification history, Start menu search history, old Internet Explorer cache/cookies/history, clipboard history files. Recall snapshots and activity history (in `AppData\Local`) were already wiped with everything else.
- **Settings:** language (same as Windows, English, Indonesian), **Update** (checks GitHub once a day for a Windows release; installs a Setup.exe after checking its SHA-256; portable copies get a link), **Uninstall** (turns off first; "delete everything" also removes settings and vault after you type DELETE), welcome tour again.
- **Welcome tour** at the first start (4 short steps).

### Safer
- **No more PowerShell at sign out.** The cleanup runs inside Amnesia.exe (C#). Antivirus programs dislike hidden PowerShell, and it also makes sign out simpler and faster: the `standby.ps1` helper from v0.2.2 is gone. Only "Collect log" still uses PowerShell, and only when you press it.
- **An installer closing Amnesia is never a sign out.** Windows' Restart Manager uses the same "end session" message; Amnesia now checks the flag and only quits (the Mac had exactly this bug in v5.13).
- If Windows Security or an antivirus blocks the cleanup ("access denied"), the Home page and a notification say so and explain how to allow Amnesia. Never "turn your antivirus off".
- The window fits small screens (at most 90% of the screen, minimum 520 × 460).
- Tests are now C# too: 126 checks on a fake user folder (cleanup, Keep List, vault, backup, damaged files, Doomsday), run on GitHub's Windows servers for every push. The GitHub Actions build also makes Setup.exe, the portable zip and SHA256SUMS; a `win-v*` tag makes a release (never marked "latest", so the Mac updater is not confused).

## v5.19.1 · Advanced settings, updates from the app, quick ways to Keep, and Windows that really wipes (Oct 10–11, 2026)

### New stuff
- **Quick ways to your Keep folder** (v5.19.1). The menu bar panel has an **Open Keep** tile next to Open Amnesia. Settings has two new switches, both on by default. **Keep shortcut on the Desktop**: the Keep alias that Amnesia puts back after every cleanup (switch it off and it's gone; aliases you make yourself are still wiped like any file). **Keep in the Finder sidebar**: Keep shows up under Favorites. The sidebar list is wiped at logout because it shows folders you used, so Amnesia adds Keep again after every login. Changing the Keep folder moves both along.
- **Advanced page.** Settings → **Advanced** collects the settings that can delete more or act on their own, each with a clear explanation and a confirm step. Uninstall stays on the normal Settings page.
- **Log out when the Mac is left alone** (Advanced). Pick Off, 5, 10, 15, 30 or 60 minutes. When nobody touches the keyboard, mouse or trackpad for that long, a 60-second countdown appears on top of everything. Touch anything (or press **I'm Here**) and it's cancelled. Otherwise you're logged out and the session is wiped, with your auto snapshot as usual. Only runs while Amnesia is On (not paused, not during a snapshot or backup). An app with an unsaved document can still stop the logout. Shows up in History as "Logged out automatically".
- **Remove apps installed later** (Advanced, off by default). When you switch it on, Amnesia writes down every app that is already in Applications. Apps you install after that are moved out at each logout and deleted at the next login, unless you press **Keep** next to them on the Advanced page (that adds an `app:` line to the Keep List). Amnesia itself is never touched. Apps installed with an admin password (owned by another user, like most `.pkg` installers) are left alone and only counted in History. Honest note: the vault keeps app *data*, not the apps themselves, so a removed app has to be installed again.
- **Updates from the app.** Settings → **Updates**. Amnesia asks GitHub once a day which version is the newest (only that, nothing about you), downloads it on its own, and checks the file against the release's `SHA256SUMS.txt`. Installing always waits for you: press **Install & Reopen**. If Amnesia was On, it turns off for a moment (nothing is wiped), the new version replaces the old one in Applications, opens by itself and turns Amnesia back on. If copying fails, the old version is put back. Both switches (check daily, download automatically) can be turned off. Installed with Homebrew? The app tells you to use `brew upgrade --cask amnesia` instead.
- **Menu bar shows new versions.** When an update is out, a row appears in the menu bar panel: open Settings, or **Install** once it's downloaded.
- **FileVault check.** Settings shows whether disk encryption is on. If it's off, it explains why that matters (Amnesia only wipes at logout and your Keep folder isn't encrypted) and opens the FileVault settings for you.
- **Run in the background** (Settings, on by default). On: at login Amnesia is only the menu bar icon. Off: the Amnesia window opens at every login.
- **History shows how much was cleaned,** like "1284 items, 2.3 GB". Older entries without a size still show like before.

### Looks & feel
- **The menu bar panel matches the main window:** same background, the same status card with the Turn On / Turn Off button, tiles that look like the home page tiles, and a cleaner Cancel and Quit button. The old 4-button grid is gone.

### Fixed & safer
- `build.sh` now refuses to install while Amnesia is On, with a message saying what to do (Turn Off, run again, Turn On). Nothing is changed in that case.
- The privacy note in the app, the README and the website FAQ now mention the daily update check, so the "nothing leaves your Mac" promise stays honest.

### Windows (preview v0.3.0, test in a virtual machine only)
- **v0.3.0 (your wish list from the VM test):** a **Settings** tab next to Home. It shows your Keep folder with an **Open Keep** button, two switches, both on: **Keep shortcut on the Desktop** (a `Keep.lnk` that Amnesia leaves alone at sign out; shortcuts you make yourself are still wiped) and **Keep in Explorer's side bar** (pinned to Quick access; Windows forgets pins at every sign out, so Amnesia pins it again after each sign in), plus a **Collect log** button. The tray icon's menu (right click) now has **Open Keep folder** and **Turn On / Turn Off Amnesia** (turning off asks first; the very first Turn On still happens in the window). Scrolling fixed: the page didn't always get the mouse wheel after opening from the tray, it now gets the focus when it loads and whenever the window comes forward.
- **v0.2.3 (after the v0.2.2 restart test):** sign out cleanup works now (2 seconds in the test). New bug it showed: after the sign in check, opening Amnesia gave "Dll was not found" and a black window. Amnesia.exe unpacks its window part (`WebView2Loader.dll`) into `AppData\Local\Temp\.net\Amnesia`, and the sign in check wiped Temp while Amnesia was running. That one folder now stays; everything else in Temp is still wiped.
- **v0.2.2 (after the restart test):** the sign out cleanup didn't run at all: once Windows starts signing out it refuses to start new programs, so PowerShell failed with error 0xc0000142 (that was the popup at restart). Now a small helper (`scripts\standby.ps1`) starts at sign in and waits quietly; at sign out Amnesia just tells it to go. Windows also closes that helper only after Amnesia is done. And the "Unknown Publisher, Run / Cancel" question at every sign in is gone: the installed copy no longer carries Windows' "downloaded from the internet" mark (older installs are fixed the next time Amnesia starts).
- **v0.2.1 (after the first VM test):** Microsoft Edge history, cookies and logins are now wiped too (Edge keeps them inside `AppData\Local\Microsoft`, which stays for Windows sign in, so it was skipped before). Edge is closed first if it's running. On the Keep List (`AppData\Local\Microsoft\Edge`)? Then it stays. The sign in check starts right after sign in instead of a few minutes later (Windows' startup delay is turned off for this user while Amnesia is on, and put back at Turn Off). The app now writes its sign out / sign in steps to `trace.log`, so the log shows why a sign out cleanup didn't run.
- **It really wipes now,** once you press **Turn On** and tick that you understand. Amnesia copies itself to `%LOCALAPPDATA%\Programs\Amnesia` and starts with Windows.
- **At sign out, restart and shutdown** Windows waits while your user folder is cleaned (everything outside the Keep folder and Keep List is moved to a hidden trash folder). **At the next sign in** that trash is deleted and Amnesia checks once more. Pause 1 session skips one sign out and sign in.
- **Windows traces wiped too:** recent files, PowerShell history, thumbnail and icon cache, Run box, Explorer address bar, search history, recent documents, open/save dialog history, Recycle Bin and clipboard history.
- **Always kept:** OneDrive, the default Links, Searches and Favorites folders, folders Windows makes itself (Screenshots, Camera Roll, Captures) and everything Windows needs to sign you in.
- **History page** (times and counts only) and a **BitLocker check**.
- Fixes from the first VM test: the title bar is dark in dark mode, opening `Amnesia.exe` a second time brings the open window to the front instead of doing nothing, and the website link goes to the new address.
- **Collect log:** double-click `scripts\Collect log.cmd` to save a troubleshooting log (Amnesia's steps, settings, Windows errors from the last 3 days, no file names) to `C:\Users\Public\Documents\amnesia-log.txt`. Nothing is sent; you choose what to share.
- Safety: nothing is deleted unless Amnesia is turned on, the installed app still exists and no pause is set. New tests cover all of that on a fake user folder.

## v5.18.2 · It looks like the website now (Oct 7–8, 2026)

It covers v5.16 up to v5.18.2, plus the new website, the videos and a first look at Windows.

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
- The GitHub and Terms buttons in the app now go to the new repo address.

### Website & README
- **Brand new website** at [navi-crwn.github.io/amnesia](https://navi-crwn.github.io/amnesia/): scroll animations, a 3D logo, light and dark mode, the app taken apart button by button, a click-along tutorial, install cards and a big FAQ. Still works fine with animations off. No tracking.
- **Built in the open:** a section with live repo info and a 3D chart of every commit.
- **"If you know, you know" 😉** for people who'd rather not explain: lending your Mac, losing it, "just open it real quick" and nosy family. With honest fine print: it protects you after a logout, and the panic word can't be undone.
- **Paper craft videos.** A 54-second stop motion film right under the top of the page, and three 30-second vertical clips in the "If you know, you know" cards. They play silently while on screen; tap to watch with sound.
- **The README** got a 15-second moving preview that links to the full video.
- **The README looks like the website now.** Its pictures are taken straight from the website (in light or dark, following your GitHub theme), instead of old screenshots. Lighter WebP images, a new link preview when you share the repo, and a fresher repo description.
- **A Windows page** on the website ([/win](https://navi-crwn.github.io/amnesia/win/)) with what already works, what's next and how to try the preview. A Mac / Windows switch sits in the menu bar of both pages.
- **Check your download.** Every release now has a `SHA256SUMS.txt` checksum file and, once the maintainer adds a free VirusTotal key, a link to a virus scan by 70+ antivirus engines. Windows builds also get GitHub's build attestation: proof that the file was built from this repo.
- **Homebrew install uses the newer cask format,** which should get rid of the two "deprecated" warnings during `brew install`.
- **Shorter Homebrew command:** `brew install navi-crwn/tap/amnesia` (no `--cask` needed).
- **New address.** The repo is now [github.com/navi-crwn/amnesia](https://github.com/navi-crwn/amnesia) and the website [navi-crwn.github.io/amnesia](https://navi-crwn.github.io/amnesia/), since Amnesia is heading to Windows too. Old repo links still work; the old website link does not, so please update your bookmark.

### Behind the scenes
- New tests for Restore Files, Check a backup file and per-browser light snapshots.
- **Windows version: first steps.** A very early preview lives in `windows/` (tray app + pages that look like the website). It only shows what it *would* wipe and never deletes anything yet. GitHub builds and tests it on Windows after every change.

Older changes: [the full changelog](https://github.com/navi-crwn/amnesia/blob/main/CHANGELOG.md).

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
