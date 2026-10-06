<p align="center"><b>English</b> · <a href="README.id.md">Bahasa Indonesia</a></p>

<p align="center"><img src="docs/banner.png" alt="Amnesia" width="100%"></p>

<p align="center">
  <b>Every time you log out, your Mac forgets everything.<br>Except the stuff you actually want to keep.</b>
</p>

<p align="center">
  <a href="../../releases/latest"><b>⬇️ Download the app</b></a> ·
  <a href="#install">Install</a> ·
  <a href="#faq">FAQ</a> ·
  <a href="CHANGELOG.md">Changelog</a>
</p>

---

## What is Amnesia?

Think of your Mac as a desk. When you're done for the day, Amnesia **clears the desk**: browser history, cookies, downloads, caches, Terminal history, all gone. Tomorrow you start fresh, with nothing left over from yesterday.

The catch: if everything is gone, you'd have to log back in to Gmail, WhatsApp, Telegram and the rest every single day. That's 15–20 minutes of your life. So Amnesia comes with a **Profile Vault**, a locked safe for your logins. After you log in to your Mac, type **one password** and all your logins are back.

**Good for you if you:**
- share your Mac, or use it in public places,
- don't want any trace of your work left behind,
- like a Mac that starts clean and light every day.

<p align="center"><img src="docs/features.png" alt="Amnesia features" width="100%"></p>

## What gets wiped, what stays?

| 🗑️ Wiped at every logout | ✅ Stays safe |
|---|---|
| Browser history & cookies | Everything in **`~/Keep`** (put your important files here) |
| Desktop, Downloads, Documents, Pictures | Logins saved in the **Profile Vault** |
| Caches, logs, Terminal history | Everything on the **Keep List** (VPN, SSH keys, Terminal settings, etc.) |
| Data from apps you didn't pick | Apps in `/Applications` and Homebrew |

Want to see exactly what would go, **without deleting anything**? In the app, open Settings (⚙️) → **See what would be deleted now**. Or in Terminal:

```bash
bash ~/.amnesia/clean.sh logout --dry-run
```

## Features

- **🛡️ Auto wipe.** Cleaning runs **before** your Mac logs out, restarts or shuts down. At the next login Amnesia checks again, so anything that slipped through gets cleaned too.
- **🔐 Profile Vault.** Your Chrome logins (Gmail, WhatsApp Web, Telegram Web), Claude, WhatsApp, and coding tools like Claude Code, OpenCode, Gemini CLI and GitHub CLI go into an encrypted safe (AES-256). One password brings them back.
- **⏏️ Save & Log Out.** One click: your logins are saved to the vault first, then the Mac logs out. If saving fails, the logout is cancelled, so nothing gets lost.
- **⏸️ Pause 1 Session.** Need to skip the wipe just once? Hit Pause. After one logout and login, Amnesia turns itself back on.
- **📌 Keep List.** Pick the folders and apps that should never be wiped, right from the app.
- **💾 Backup anywhere.** Your chosen folders get locked into one `.7z` file (AES-256) and sent to:
  - a **USB drive / SSD** that's plugged in,
  - **your own server / VPS** over SSH + rsync,
  - the **cloud** (Google Drive, Dropbox, OneDrive, S3) with rclone.
- **⏰ Scheduled backups.** Daily or weekly, running on their own while the Amnesia icon is in the menu bar.
- **🚚 Move to a new Mac.** Take all your logins with you: the Keychain keys go into the vault, the vault goes into a backup, and you restore it on the new Mac.
- **🔥 Panic button.** Get the vault password wrong 3 times, or type your *panic word*, and the vault is destroyed on the spot.
- **👀 Check before logout.** Logging out or restarting from the Apple menu? Amnesia holds on for a second and shows what's about to be deleted. You decide: continue or cancel.
- **📸 Auto snapshot.** Forgot to press Save & Log Out? Your logins still get saved to the vault on a normal logout.
- **🔔 Notifications.** After login, Amnesia tells you the Mac is clean and reminds you to restore your profiles.
- **⚙️ Settings.** Turn any of the above on or off.
- **🌐 Two languages.** English or Bahasa Indonesia, pick one in Settings.
- **🟢 Menu bar icon.** You can always see Amnesia's status in the top right: green is on, orange is paused, red is off.

## Install

**You need:** macOS 15 or newer, [Homebrew](https://brew.sh), and the Command Line Tools (free, install with `xcode-select --install`).

Open **Terminal** and paste:

```bash
brew install sevenzip python      # + rclone if you want cloud backups
git clone https://github.com/navi-crwn/amnesia-mac.git ~/.amnesia
bash ~/.amnesia/app/build.sh
```

Amnesia opens by itself and shows up in Launchpad.

## First-time setup

1. **Create the vault.** Open *Profile Vault*, pick a password (at least 12 characters), then press *Create Vault*. This password **can't be recovered** if you forget it, so keep it somewhere safe.
2. **Save your logins.** Log in to Chrome, WhatsApp and your other apps like normal, then press *Snapshot*.
3. **Protect your files.** Move anything important into the `~/Keep` folder.
4. **Double-check.** Open Settings (⚙️) → **See what would be deleted now**, and make sure nothing important is on the list.
5. **Turn it on.** Press *Turn On*. From the next logout on, your Mac always starts clean.

**Day to day:** log out with **Save & Log Out**. When you log back in, open Profile Vault and press **Restore Profiles**.

## FAQ

**What's the difference between the Keep List and the Profile Vault?**
The Keep List is for stuff that isn't secret and can just stay (like VPN settings). The Profile Vault is for logins and personal data: it's locked, and only opens with your password.

**What if I log out from the Apple menu?**
That's fine. Amnesia holds on for a moment to show you what will be deleted, then saves your logins to the vault before cleaning up. You can turn both of these off in Settings.

**What if I forget the vault password?**
Then nobody can open the vault, including you. Delete it, make a new one, and log back in to your apps.

**Does my data get sent to the internet?**
No, unless you choose a server or cloud backup yourself. Even then, only the locked `.7z` file is sent, and the server can't read what's inside. Your vault and your personal Keep List never go to GitHub either.

**What do I need for online backups?**
- *SSH server:* type `user@host:folder`, press **Set Up SSH Key** once (you'll type the server password one time), then **Test Connection**.
- *Google Drive:* press **Connect Google Drive**, log in in your browser, done. The default destination is `gdrive:Amnesia`.

Heads up: every backup is uploaded in full (not just what changed), because the file is encrypted. Old backups aren't deleted automatically, so clean them up at the destination now and then.

**How do I open a backup file?**
Use an app like Keka, or Terminal: `7zz x amnesia_backup_xxx.7z`, then type your backup password.

**Moving to a new Mac, what are the steps?**
1. On the old Mac: Profile Vault → **Prepare Move** (click *Always Allow* in the macOS popups).
2. Back up with **Include Profile Vault** ticked.
3. On the new Mac: install Amnesia, open Profile Vault → **Get Vault from Backup**.
4. Press **Restore Profiles**, then **Restore Keys**. Chrome, Claude and WhatsApp open with your old logins.

**How do I turn it off?**
Press *Turn Off* in the app. Your Mac stops being wiped until you turn it back on.

## Under the hood

| File | What it does |
|---|---|
| `clean.sh` | The main wiper. Reads `keep.conf` (your Keep List). |
| `agent.sh` | Started by macOS at login, then waits to clean up at logout. |
| `vault.py` | Profile Vault: RSA-4096 key + 7-Zip AES-256. |
| `backup.sh` | Encrypted backups to a USB drive, an SSH server, or the cloud (rclone). |
| `keep.example.conf` | Example Keep List. `build.sh` copies it to `keep.conf` on first install. |
| `app/` | The SwiftUI app, the icon, and the build/backup scripts. |
| `test_clean.sh`, `test_vault.py`, `test_backup.sh` | Automatic tests in a fake home folder, safe to run anytime. |

---

<p align="center">Made for personal use. Use it wisely: Amnesia really does delete your data.</p>
