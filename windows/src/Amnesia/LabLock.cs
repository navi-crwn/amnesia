// v0.7 Lab lock, the app side (the locked files and their rules are in Core\Lab.cs).
// Turning it on or off needs an administrator (one Windows prompt): the locked copy goes to %ProgramData%\Amnesia\lab,
// a folder normal users can only read, and Windows starts Amnesia at every sign in from HKLM\...\Run.
// While locked, the page can only look; changing anything needs the PIN, which opens it for 10 minutes.
using Amnesia.Core;

namespace Amnesia;

static class LabLock
{
    static DateTime openUntil;

    public static bool Active => Lab.Active;
    /// <summary>Locked and the PIN was not entered in the last 10 minutes.</summary>
    public static bool Closed => Lab.Active && DateTime.Now >= openUntil;

    public static bool Unlock(string pin)
    {
        if (!Lab.Check(pin)) { AppInfo.Trace("lab: wrong PIN"); return false; }
        openUntil = DateTime.Now.AddMinutes(10);
        AppInfo.Trace("lab: opened with the PIN for 10 min");
        return true;
    }

    public static void Close() => openUntil = DateTime.MinValue;

    /// <summary>Locks with this PIN and the settings and Keep List you have now. Also used to save changes again.
    /// Returns false when the Windows administrator prompt was answered No.</summary>
    public static bool TurnOn(string pin)
    {
        if (!Pin.GoodPin(pin)) throw new InvalidOperationException("lab-pin-short");
        if (Lab.Active && !Lab.Check(pin)) throw new InvalidOperationException("lab-pin-wrong");
        var stage = Path.Combine(Path.GetTempPath(), "amnesia-lab-" + Guid.NewGuid().ToString("N"));
        try
        {
            Lab.Stage(stage, pin, Setup.RunningInstalled ? Setup.InstalledExe : Environment.ProcessPath!);
            if (!AdminTasks.Run("labon:" + stage)) return false;
        }
        finally { try { Directory.Delete(stage, true); } catch { } }
        Close();
        AppInfo.Trace("lab: locked");
        return true;
    }

    public static bool TurnOff(string pin)
    {
        if (!Lab.Check(pin)) throw new InvalidOperationException("lab-pin-wrong");
        if (!AdminTasks.Run("laboff")) return false;
        AppInfo.Trace("lab: unlocked for good");
        return true;
    }

    /// <summary>Tray Turn Off / Quit and the uninstaller: asks the PIN when locked. True = go ahead.</summary>
    public static bool AskIfLocked(IWin32Window? owner = null) =>
        !Closed || PinPrompt.Ask(owner, Text2.LabTitle, Text2.LabAsk, digitsOnly: true, check: Unlock) != null;
}
