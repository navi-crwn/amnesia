# Amnesia for Windows (early preview)

Work in progress, **v0.5.0**. Once you press **Turn On**, Amnesia **really deletes** your user folder at sign out, restart and shutdown (and checks again at sign in). Test it in a virtual machine only, never on your real PC.

## Install
- **Setup.exe** (`Amnesia-Setup-<version>-arm64.exe` for Windows on ARM, `-x64.exe` for normal PCs): installs just for you, no admin, into `%LOCALAPPDATA%\Programs\Amnesia`, with a Start menu entry and an Apps & features entry. Amnesia stays off until you turn it on.
- **Portable zip**: unzip, run `Amnesia.exe`. Turn On copies it to the same install folder.
- Windows SmartScreen warns because the app isn't signed yet: **More info → Run anyway**. Check your download against `SHA256SUMS.txt`.

## What it does
- **Turn On** starts Amnesia at every sign in (`HKCU\...\Run`, with `--login`).
- At sign out / restart / shutdown, Windows waits while Amnesia (inside `Amnesia.exe`, no PowerShell) makes an automatic vault snapshot of changed apps and moves everything outside the Keep folder and Keep List to `%USERPROFILE%\.amnesia-trash`. At the next sign in that trash is deleted and Amnesia checks once more.
- Windows traces: recent files and jump lists, PowerShell history, thumbnail/icon cache, Run box, Explorer address bar and search, recent documents, open/save dialogs, UserAssist, MuiCache, shellbags, taskbar usage, Remote Desktop history and screen cache, notification history, Start search history, old IE cache, Recycle Bin, clipboard history, crash reports, Office / Paint / WordPad / Media Player / Adobe recent files, Notepad unsaved tabs, Snipping Tool captures, Compatibility Assistant history, DNS cache.
- **Extra cleaning list** (optional): downloads the community list [Winapp2.ini](https://github.com/MoscaDotTo/Winapp2) and uses its lines for the folders that stay on purpose and your registry.
- Always kept: the Keep folder, Keep List, `.amnesia`, OneDrive, Microsoft Store app data, what Windows needs to sign you in, folders Windows makes itself.
- **Pages:** Home (status, preview, History, BitLocker), Keep List, Vault, Backup (+ Move to a new PC), Advanced (sign out when idle, panic hotkey, USB key with sign out or shut down, Stop Windows remembering, remove new apps and their registry settings, Find leftovers, Extra cleaning list, Throwaway Windows (Windows Sandbox), Wipe free space, Dynamic Lock, Windows protections, antivirus), Settings (language, Keep shortcuts, Update, Collect log, Uninstall).
- Safety: nothing is deleted unless `ENABLED=1`, the installed app still exists, and no pause is set. An installer closing Amnesia is never treated as a sign out.

## Code
- `src/Amnesia.Core/`: the real work, plain .NET 8 (`CleanEngine`, `Vault`, `Backup`, `Crypto`, `KeepList`, `Conf`, `Winapp2`, `Leftovers`, `Tweaks`). Runs on any OS, so the tests do too.
- `src/Amnesia/`: the tray app (C# .NET 8, WinForms + WebView2): Windows-only parts (registry traces, new apps, quick exits, admin switches, updater, SSH).
- `ui/`: the pages (HTML/CSS/JS, same look as the website). Buttons talk to C# through `Bridge.cs`.
- `installer/Amnesia.iss`: Setup.exe (Inno Setup 6).
- `tests/Amnesia.Tests/`: tests on a fake user folder: `dotnet run --project windows/tests/Amnesia.Tests`.
- `scripts/Collect log.cmd` (runs `collect-log.ps1`): saves a troubleshooting log to `C:\Users\Public\Documents\amnesia-log.txt` and opens it. Nothing is sent; no file names from your folders.

Every push that changes `windows/` is built and tested on GitHub's Windows servers (`.github/workflows/windows.yml`): repo → **Actions** → latest **Windows** run → **Artifacts**. A tag `win-v0.5.0` also makes a GitHub release (used by the in-app update).

## Learned from
v0.5 took ideas (and, where the license allows, a little data) from BleachBit, Winapp2, Bulk Crap Uninstaller, privacy.sexy, Win11Debloat, Pearcleaner, Sandboxie and Tails. What came from where: [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
