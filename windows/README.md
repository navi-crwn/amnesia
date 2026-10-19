# Amnesia for Windows

**v0.8.1**, an official release for Windows 10 and 11 (x64 and ARM). Once you press **Turn On**, Amnesia **really deletes** what's in your user folder at sign out, restart and shutdown (and checks again at sign in), except your Keep folder and Keep List. Look at **What gets wiped** before you turn it on. Website: [navi-crwn.github.io/amnesia/win](https://navi-crwn.github.io/amnesia/win/).

## Install
- **Setup.exe** (`Amnesia-Setup-<version>-x64.exe` for normal PCs, `-arm64.exe` for Windows on ARM) from the Windows release on [Releases](../../../releases) (tags start with `win-v`). It installs just for you, no admin, into `%LOCALAPPDATA%\Programs\Amnesia`, with a Start menu entry and an Apps & features entry. Amnesia stays off until you turn it on.
- **Portable zip**: unzip, run `Amnesia.exe`. Turn On copies it to the same install folder.
- Check your download against `SHA256SUMS.txt` (PowerShell: `Get-FileHash .\Amnesia-Setup-*.exe`). There's no paid code signing certificate, so SmartScreen warns the first time: **More info → Run anyway**.
- Updating over an older version: **Turn Off**, install, **Turn On**. Updates from inside the app only install when `SHA256SUMS.txt` has a valid developer signature (`SHA256SUMS.txt.sig`); otherwise the release page opens instead.

## What it does
- **Turn On** starts Amnesia at every sign in. If Task Manager switches that off, the home page warns you and has a **Switch it back on** button.
- **At sign out**, Amnesia cleans right when Windows asks "may I sign out?" and shows "Amnesia is cleaning up..." while it works. Everything outside the Keep folder and Keep List moves to `%USERPROFILE%\.amnesia-trash`, which is emptied at the next sign in, when Amnesia checks once more. Honest trade-off: if you cancel a sign out after the cleanup started, the cleanup has already happened, like **Clean now**.
- **Windows traces**: recent files and jump lists, PowerShell history, Run box, Explorer address bar and search, open/save dialogs, UserAssist, shellbags, Start search and notification history, clipboard history, Remote Desktop history, crash reports, Notepad unsaved tabs, Snipping Tool captures, Office and other recent-file lists, DNS cache and more.
- **Never wiped**: the Keep folder, Keep List, `.amnesia`, cloud folders (OneDrive, Dropbox, Google Drive, iCloud Drive, Nextcloud, MEGA, Box, pCloud, Proton Drive and every folder Windows knows as a sync folder), virtual machines and disc images of 1 GB or more (switch in Settings), what Windows needs to sign you in. Microsoft Store app data and saved app passwords stay too, unless you switch those on.
- **Keep List** with app icons and names. **Keep an app** lists installed apps (Microsoft Store apps too) and keeps all of an app's folders in one click. **Keep** in the new apps list also keeps the app's program folder.
- **Profile Vault** (AES-256): Chrome, Edge, Firefox, Telegram, WhatsApp, Claude, Signal, Bitwarden, Obsidian, Antigravity, Gemini CLI and more, with a spare snapshot. Panic word and Doomsday delete it.
- **Backup** to a folder, USB drive, cloud folder or your own SSH server, plus **Move to a new PC**.
- **Health check** on the home page (is it on, does it start with Windows, last cleanup, files left behind, cloud folders, vault, backup, Keep lock) and **What Amnesia can't do**, the honest limits.
- **Keep lock**: Keep can't be opened or changed until you type the Keep password. It uses Windows permissions, not encryption, so file names stay visible.
- **Safe box (experimental)**: a locked folder inside Keep, one encrypted file while closed. Amnesia closes it at every sign out.
- **Quick exits**: panic hotkey, USB key (sign out or shut down when it's pulled), sign out when idle. **Lab lock** for shared PCs.
- **Advanced**: Stop Windows remembering, remove new apps (3-day trash, never anything on the Keep List), Find leftovers, Extra cleaning list ([Winapp2.ini](https://github.com/MoscaDotTo/Winapp2), downloaded only when you ask), Throwaway Windows (Windows Sandbox), wipe free space, Windows protections.
- **Safety**: nothing is deleted unless Amnesia is on, the installed app still exists and no pause is set. An installer closing Amnesia is never treated as a sign out. Uninstalling asks for the Keep password and opens Keep first.

## Code
- `src/Amnesia.Core/`: the real work, plain .NET 8 (`CleanEngine`, `Vault`, `Backup`, `Crypto`, `KeepList`, `Safe`, `UpdateSig`, `AppMatch`, `NewApps`, `Winapp2`, `Leftovers`, `Tweaks`). Runs on any OS, so the tests do too.
- `src/Amnesia/`: the tray app (C# .NET 8, WinForms + WebView2): the Windows-only parts (sign out watcher, registry traces, new apps, quick exits, Keep lock, admin switches, updater, SSH).
- `ui/`: the pages (HTML/CSS/JS, same look as the website), English and Indonesian. Buttons talk to C# through `Bridge.cs`.
- `installer/Amnesia.iss`: Setup.exe (Inno Setup 6).
- `tests/Amnesia.Tests/`: 294 tests on a fake user folder: `dotnet run --project windows/tests/Amnesia.Tests`.
- `scripts/Collect log.cmd` (runs `collect-log.ps1`): saves a troubleshooting log to `C:\Users\Public\Documents\amnesia-log.txt` and opens it. Nothing is sent; no file names from your folders.

Every push that changes `windows/` is built and tested on GitHub's Windows servers (`.github/workflows/windows.yml`): repo → **Actions** → latest **Windows** run → **Artifacts**. A `win-v*` tag also makes a GitHub release (used by the in-app update).

## Learned from
Ideas (and, where the license allows, a little data) came from BleachBit, Winapp2, Bulk Crap Uninstaller, privacy.sexy, Win11Debloat, Pearcleaner, Sandboxie and Tails. What came from where: [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
