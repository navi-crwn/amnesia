# Amnesia for Windows (early preview)

Work in progress. This version **never deletes anything**: it only shows what Amnesia *would* wipe from your user folder (a dry run).

- `src/Amnesia/`: the tray app (C# .NET 8, WinForms + WebView2).
- `ui/`: the pages (HTML/CSS/JS, same look as the website). Buttons talk to C# through `Bridge.cs`.
- `scripts/clean.ps1`: the cleaner. Only `-DryRun` works for now.
- `tests/test_clean.ps1`: tests on a fake user folder.

Every push that changes `windows/` is built and tested on GitHub's Windows servers (`.github/workflows/windows.yml`).
To try it: repo → **Actions** → latest **Windows** run → **Artifacts** → `Amnesia-windows-arm64` (Windows on a Mac VM) or `Amnesia-windows-x64` (normal PC). Unzip, run `Amnesia.exe`. Windows SmartScreen will warn because the app isn't signed yet: **More info → Run anyway**.
