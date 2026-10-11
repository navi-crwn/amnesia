# Third-party notices (Amnesia for Windows)

Amnesia is MIT licensed. Since v0.5 it learns from other open source privacy and cleanup tools. This file says what
came from where, and under which license.

## Code or data copied into Amnesia

### Win11Debloat (MIT)
The registry values behind "Stop Windows remembering" (`src/Amnesia/Privacy.cs`) and the Recall / Copilot / telemetry
admin switches (`src/Amnesia/AdminTasks.cs`) come from Win11Debloat's `Regfiles` folder.
https://github.com/Raphire/Win11Debloat

```
MIT License

Copyright (c) 2020 Raphire (https://github.com/Raphire)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Downloaded on request, never shipped

### Winapp2.ini (CC BY-SA 4.0)
"Extra cleaning list" downloads Winapp2.ini from https://github.com/MoscaDotTo/Winapp2 into `%USERPROFILE%\.amnesia`
when you press the button. Amnesia does not include or change the file; it stays under its own license
(https://github.com/MoscaDotTo/Winapp2/blob/master/License.md). Credit: the Winapp2 project.

## Ideas only (no code copied)

Amnesia's code for these was written from scratch after reading how they work:

| Project | License | Idea used in Amnesia |
|---|---|---|
| [BleachBit](https://github.com/bleachbit/bleachbit) | GPL-3.0 | more Explorer and app history locations, DNS cache, telling Explorer to refresh, wiping free space |
| [privacy.sexy](https://github.com/undergroundwires/privacy.sexy) | AGPL-3.0 | which registry keys hold recent-file and search history, Windows trace folders (Prefetch, crash reports) |
| [Bulk Crap Uninstaller](https://github.com/Klocman/Bulk-Crap-Uninstaller) | Apache-2.0 | finding leftover folders ("orphans") with a confidence level, MSI uninstall with /X, Compatibility Assistant history |
| [Pearcleaner](https://github.com/alienator88/Pearcleaner) | Apache-2.0 + Commons Clause | matching leftover files and settings to an app by its name |
| [Sandboxie-Plus](https://github.com/sandboxie-plus/Sandboxie) | GPL-3.0 | a throwaway box for risky files (Amnesia opens Windows' own Windows Sandbox) |
| [Tails](https://tails.net) | GPL-3.0 | shutting down when the USB stick is pulled out, random hardware (MAC) addresses |
