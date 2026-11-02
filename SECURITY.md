# Security

Amnesia deletes data on purpose, so a bug can cost someone their files. Thank you for taking the time to look.

## Report a security problem

Please report it privately, not in a public issue:

1. Go to [github.com/navi-crwn/amnesia/security/advisories/new](https://github.com/navi-crwn/amnesia/security/advisories/new) (repo → **Security** → **Report a vulnerability**).
2. Say which app and version (Mac `v5.x.x` or Windows `v0.x.x`, shown next to the Amnesia title), what you did, what happened and what you expected.
3. Please leave out your own file names and personal data. A fake user folder or a test account is enough to show most problems.

You'll get an answer in the advisory. Amnesia is a small project made by one person, so please give it some time before you share details in public. Once a fix is out, the advisory is published and the CHANGELOG says what was fixed.

**Which versions:** only the newest Mac release and the newest Windows release get fixes. Please update first and check that the problem is still there.

**Where Amnesia comes from:** only [github.com/navi-crwn/amnesia](https://github.com/navi-crwn/amnesia), its website [navi-crwn.github.io/amnesia](https://navi-crwn.github.io/amnesia/) (GitHub Pages) and the Homebrew tap `navi-crwn/tap`. If you found a copy somewhere else, it isn't from us; please tell us about it the same way.

### What counts

- Amnesia deleting something it should keep: the Keep folder, `~/.amnesia` (or `%USERPROFILE%\.amnesia` on Windows), anything on the Keep List, cloud folders, virtual machines, other users' files, system files.
- Amnesia following a symlink or a Windows reparse point out of the home folder.
- Ways to read the Profile Vault, a backup or the Brankas / Safe box without the password.
- Ways to get an unsigned update installed by the in-app updater.
- Amnesia writing file names or passwords to its logs, or sending anything over the network that isn't described below.
- The Ask an AI report containing file contents or the names of your files.

Things in **What Amnesia can't do** below are known limits, not bugs. Ideas to make them better are still welcome as normal issues.

## How Amnesia tries to stay safe

This is a short, honest summary. The code is the final word.

**Deleting**
- Nothing is deleted unless Amnesia is turned on. On Windows the installed app must also still exist. **Pause 1 Session** skips the next cleanup.
- Protected every time: the Keep folder, `.amnesia`, the Keep List, and on Mac the Apple system data you choose to keep.
- If the Keep List can't be read or has gone missing, the cleanup stops and deletes nothing, and History says so. A copy of the last good Keep List is kept to restore it.
- Folders that are symlinks are never emptied through the link. Desktop and Documents are skipped while iCloud Desktop & Documents is on. Cloud folders are left alone. Virtual machines are left alone on Windows; on Mac they get a warning and a Keep button (nothing is added to the Keep List without you).
- When a check can't tell (an error, a timeout, an unreadable item, an unknown owner), the item is kept. A file left behind is better than a file deleted by mistake.
- Files that couldn't be deleted are counted as "could not be deleted", never as cleaned, and are tried again next time.
- **What Gets Deleted** (Mac) and **What gets wiped** (Windows) show the list without deleting anything. On Mac the same list comes from `bash ~/.amnesia/clean.sh logout --dry-run`.

**Care page** (Mac v5.24, Windows v0.9)
- Every Care action scans first and shows a list. Nothing risky is ticked for you, and you confirm the count, the size and where things go.
- On Mac, apps you uninstall go to the Trash. On Windows, a program is removed by its own uninstaller. App leftovers, installers and project build folders go to the Trash / Recycle Bin, not straight to deletion. Emptying the Trash or Recycle Bin is never ticked for you.
- Just before acting, each item is checked again: it must still be the same item, not a link, and not protected. If anything changed, it's skipped.
- Care never asks for an admin password and never touches system files or other users.

**Amnesia modes and Ask an AI** (Mac v5.25, Windows v0.10)
- Switching mode always shows a preview (what will now be wiped, what will now be kept) and asks you to confirm. It takes effect at the next logout or sign out; nothing is deleted when you switch.
- A mode only changes its own marked section of the Keep List. If the mode file is missing or damaged, or the Keep List can't be read, the mode is not changed. It never leaves you with an empty Keep List.
- The Ask an AI report stays on your computer. Amnesia makes no network calls for it: nothing leaves the computer unless you copy or save the report and paste it somewhere yourself.
- What the report contains: your OS and its version, the Amnesia version, the mode, your Keep List lines, the names and sizes of the apps in the Profile Vault, your vault profiles, the names and sizes of the folders right inside your home folder, the names of app data folders (Mac: `Library/Application Support`; Windows: the top of `AppData\Roaming` and `AppData\Local`), the names of installed apps, and counts and sizes (what the next cleanup would delete, Care numbers).
- What it never contains: file contents, the names of your files, or the names of folders deeper inside your home folder (other than the app data folders above and what your Keep List lines say). With **Hide folder names**, folder names that aren't standard, app data folders of apps outside the vault, your own Keep List lines and the Keep folder path are replaced by placeholders.
- An AI's answer is only a suggestion. Each change gets a checkbox and the same preview as a mode switch, nothing is applied until you confirm, and Amnesia's own Keep List lines can't be removed this way.
- The Mac `amnesia` Terminal command only reads. It never deletes or changes anything.

**Passwords and encryption**
- Mac: the Profile Vault uses an RSA-4096 key whose private half is locked with 7-Zip AES-256 under your vault password, and backups are 7-Zip AES-256. The Brankas is an encrypted APFS disk image.
- Windows: the vault and the Safe box use AES-256-GCM, with the key wrapped by an RSA key.
- The panic word and the Keep password are stored as PBKDF2 hashes, not as text.
- There is no way to recover a forgotten vault, backup or Brankas password. That is on purpose.

**Updates and network**
- The only thing Amnesia asks the internet on its own is GitHub's newest version number, on the schedule you pick, and you can switch it off.
- In-app updates only install when `SHA256SUMS.txt` has a valid developer signature (`SHA256SUMS.txt.sig`, ECDSA P-256). Without it, the release page opens instead.
- Backups only go to places you set up yourself (a drive, your own server, your cloud account).

**Logs**
- `trace.log` and History hold times, steps, counts and app names, never the names of your files.

## What Amnesia can't do

Amnesia cleans your own user folder at logout. It is not a full anti-forensics tool. In particular:

- **Deleted files can sometimes be recovered** from the disk. Files are removed the normal way, not overwritten. Turn on FileVault (Mac) or BitLocker / Device Encryption (Windows).
- **Time Machine, APFS snapshots, Windows restore points** and **Spotlight / Windows Search** can still hold old files or bits of them.
- **Anything synced to a cloud** stays in the cloud and on your other devices.
- **Swap, sleep image, hibernation file and system logs** belong to the system and are not cleaned.
- **Other accounts** on the same computer are not cleaned.
- **The Keep folder is not encrypted.** The Keep lock uses macOS / Windows permissions, not encryption: anyone logged in as you can remove it, and file names right inside Keep stay visible. Use FileVault, or the Brankas / Safe box for secrets.
- **Websites, your internet provider and the apps' own servers** still have their records of you.
- **The app is not signed by Apple or by a paid Windows certificate**, so macOS and SmartScreen warn the first time. Check your download against `SHA256SUMS.txt`.

The app shows this list too: **Limitations** on Mac, **What Amnesia can't do** on Windows.
