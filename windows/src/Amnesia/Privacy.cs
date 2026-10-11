// v0.5 "Stop Windows remembering" (Settings → Advanced). Windows' own privacy switches in your part of the registry,
// so no admin is needed and they survive sign out (your registry stays). Values from Win11Debloat (MIT, see
// THIRD-PARTY-NOTICES.md) plus a few from privacy.sexy's list. Core\Tweaks.cs writes down the old values for Undo.
using Amnesia.Core;
using Microsoft.Win32;

namespace Amnesia;

static class Privacy
{
    const string Adv = @"Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced";
    const string Exp = @"Software\Microsoft\Windows\CurrentVersion\Explorer";
    const string Cdm = @"Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager";

    public static readonly Tweak[] All =
    {
        // track: Windows stops keeping lists of what you opened (Start, Quick access, jump lists)
        new("track", Adv, "Start_TrackProgs", 0),
        new("track", Adv, "Start_TrackDocs", 0),
        new("track", Exp, "ShowRecent", 0),
        new("track", Exp, "ShowFrequent", 0),
        // clipboard: no clipboard history (Win+V) and no syncing it to your other devices
        new("clipboard", @"Software\Microsoft\Clipboard", "EnableClipboardHistory", 0),
        new("clipboard", @"Software\Microsoft\Clipboard", "CloudClipboardAutomaticUpload", 0),
        // search: no web results in Start search, no search history on this device or in the cloud
        new("search", @"Software\Policies\Microsoft\Windows\Explorer", "DisableSearchBoxSuggestions", 1),
        new("search", @"Software\Microsoft\Windows\CurrentVersion\SearchSettings", "IsDeviceSearchHistoryEnabled", 0),
        new("search", @"Software\Microsoft\Windows\CurrentVersion\SearchSettings", "IsMSACloudSearchEnabled", 0),
        new("search", @"Software\Microsoft\Windows\CurrentVersion\SearchSettings", "IsAADCloudSearchEnabled", 0),
        // typing: Windows stops learning from what you type, write and say
        new("typing", @"Software\Microsoft\InputPersonalization", "RestrictImplicitInkCollection", 1),
        new("typing", @"Software\Microsoft\InputPersonalization", "RestrictImplicitTextCollection", 1),
        new("typing", @"Software\Microsoft\InputPersonalization\TrainedDataStore", "HarvestContacts", 0),
        new("typing", @"Software\Microsoft\Personalization\Settings", "AcceptedPrivacyPolicy", 0),
        new("typing", @"Software\Microsoft\Input\TIPC", "Enabled", 0),
        new("typing", @"Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy", "HasAccepted", 0),
        // ads: no advertising ID, no "tailored experiences", no suggested apps and tips
        new("ads", @"Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo", "Enabled", 0),
        new("ads", @"Software\Microsoft\Windows\CurrentVersion\Privacy", "TailoredExperiencesWithDiagnosticDataEnabled", 0),
        new("ads", Cdm, "SystemPaneSuggestionsEnabled", 0),
        new("ads", Cdm, "SoftLandingEnabled", 0),
        new("ads", Cdm, "SilentInstalledAppsEnabled", 0),
        new("ads", Cdm, "SubscribedContent-310093Enabled", 0),
        new("ads", Cdm, "SubscribedContent-338388Enabled", 0),
        new("ads", Cdm, "SubscribedContent-338389Enabled", 0),
        new("ads", Cdm, "SubscribedContent-338393Enabled", 0),
        new("ads", Cdm, "SubscribedContent-353694Enabled", 0),
        new("ads", Cdm, "SubscribedContent-353696Enabled", 0),
        new("ads", Adv, "Start_IrisRecommendations", 0),
        new("ads", Adv, "Start_AccountNotifications", 0),
        // ai: Recall snapshots, Click to Do and Copilot off for you (the admin switch does it for the whole PC)
        new("ai", @"Software\Policies\Microsoft\Windows\WindowsAI", "DisableAIDataAnalysis", 1),
        new("ai", @"Software\Policies\Microsoft\Windows\WindowsAI", "DisableClickToDo", 1),
        new("ai", @"Software\Policies\Microsoft\Windows\WindowsCopilot", "TurnOffWindowsCopilot", 1),
        new("ai", Adv, "ShowCopilotButton", 0),
    };

    public static readonly string[] Groups = { "track", "clipboard", "search", "typing", "ads", "ai" };

    sealed class HkcuStore : IRegStore
    {
        public int? Get(string key, string name) { using var k = Registry.CurrentUser.OpenSubKey(key); return k?.GetValue(name) as int?; }
        public void Set(string key, string name, int value) { using var k = Registry.CurrentUser.CreateSubKey(key); k.SetValue(name, value, RegistryValueKind.DWord); }
        public void Delete(string key, string name) { using var k = Registry.CurrentUser.OpenSubKey(key, writable: true); k?.DeleteValue(name, false); }
    }
    static readonly HkcuStore Store = new();

    public static Dictionary<string, bool> Status() => Groups.ToDictionary(g => g, g => Tweaks.IsOn(Store, All.Where(t => t.Group == g)));

    /// <summary>Switches the chosen groups on (and Undo for the ones you unticked that Amnesia had changed).</summary>
    public static void Apply(IEnumerable<string> on)
    {
        var want = on.ToHashSet();
        Tweaks.Apply(Store, All.Where(t => want.Contains(t.Group)));
        Tweaks.Undo(Store, All.Where(t => !want.Contains(t.Group)));
        Refresh();
        AppInfo.Trace($"privacy switches: {string.Join(',', want)}");
    }

    public static void UndoAll() { Tweaks.Undo(Store, All); Refresh(); }

    // Explorer and the taskbar read some of these only at start; this nudges them to look again
    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, string lParam, uint flags, uint timeout, out IntPtr result);
    static void Refresh() { try { SendMessageTimeout((IntPtr)0xffff, 0x001A, IntPtr.Zero, "Policy", 0x2, 2000, out _); } catch { } }
}
