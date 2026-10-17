; Amnesia for Windows: Setup.exe (Inno Setup 6). Built by GitHub Actions (.github/workflows/windows.yml):
;   ISCC.exe /DArch=x64|arm64 /DVersion=0.5.0 /DSrc=<folder with Amnesia.exe, ui\, scripts\> installer\Amnesia.iss
; Installs just for you (no admin) into %LOCALAPPDATA%\Programs\Amnesia, the folder Amnesia's cleanup never touches,
; adds a Start menu entry and an entry in Apps & features. Amnesia stays OFF after installing: you turn it on in the app.
; Updating and uninstalling first close Amnesia with "Amnesia.exe --quit", which never runs a cleanup.
; v0.8: English and Indonesian, with a Welcome page, the Terms (must be accepted), a warning before installing and a
; short tour after it. An update from inside the app runs silently and skips all of these pages.
; Uninstalling asks the Keep password when Keep is locked (else Keep stays locked and you are told how to open it),
; and asks whether Amnesia's own data (.amnesia: settings, Keep List, vault, logs) should go too. Keep always stays.

#ifndef Arch
  #define Arch "x64"
#endif
#ifndef Version
  #define Version "0.0.0"
#endif
#ifndef Src
  #define Src "..\out\Amnesia"
#endif

[Setup]
AppId={{6E3B1C52-8F7A-4C1E-9B5D-A3F0D2E4C719}
AppName=Amnesia
AppVersion={#Version}
AppVerName=Amnesia {#Version}
AppPublisher=Amnesia (open source)
AppPublisherURL=https://github.com/navi-crwn/amnesia
AppSupportURL=https://github.com/navi-crwn/amnesia/issues
AppUpdatesURL=https://github.com/navi-crwn/amnesia/releases
DefaultDirName={localappdata}\Programs\Amnesia
DisableDirPage=yes
DisableProgramGroupPage=yes
DefaultGroupName=Amnesia
PrivilegesRequired=lowest
OutputBaseFilename=Amnesia-Setup-{#Version}-{#Arch}
OutputDir=..\out
SetupIconFile=..\src\Amnesia\amnesia.ico
UninstallDisplayIcon={app}\Amnesia.exe
UninstallDisplayName=Amnesia
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
DisableWelcomePage=no
ShowLanguageDialog=auto
CloseApplications=no
RestartApplications=no
#if Arch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
MinVersion=10.0.17763

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"; LicenseFile: "terms-en.txt"; InfoBeforeFile: "before-en.txt"; InfoAfterFile: "after-en.txt"
Name: "id"; MessagesFile: "compiler:Default.isl,Indonesian.isl"; LicenseFile: "terms-id.txt"; InfoBeforeFile: "before-id.txt"; InfoAfterFile: "after-id.txt"

[CustomMessages]
en.OpenApp=Open Amnesia
id.OpenApp=Buka Amnesia
en.LabLocked=This PC has the Amnesia lab lock on. Amnesia stays installed until the lab PIN is entered.
id.LabLocked=PC ini memakai kunci lab Amnesia. Amnesia tetap terpasang sampai PIN lab dimasukkan.
en.AskData=Also delete Amnesia's own data?%n%n%1%n(settings, Keep List, vault with your saved app logins, the locked Safe box, logs)%n%nYour Keep folder is never deleted. Choose No if you might install Amnesia again.
id.AskData=Hapus juga data milik Amnesia?%n%n%1%n(pengaturan, Keep List, vault berisi login app yang disimpan, Brankas yang terkunci, log)%n%nFolder Keep tidak pernah dihapus. Pilih Tidak kalau mungkin akan memasang Amnesia lagi.
en.DataKept=Amnesia's data stays in %1, so your Keep password still works if you install Amnesia again.
id.DataKept=Data Amnesia tetap ada di %1, jadi password Keep masih berlaku kalau kamu memasang Amnesia lagi.

[Files]
Source: "{#Src}\Amnesia.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Src}\ui\*"; DestDir: "{app}\ui"; Flags: ignoreversion recursesubdirs
Source: "{#Src}\scripts\*"; DestDir: "{app}\scripts"; Flags: ignoreversion recursesubdirs
Source: "{#Src}\THIRD-PARTY-NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[InstallDelete]
; the sign out helper scripts of v0.2/v0.3 are gone since v0.4 (the cleanup runs inside Amnesia.exe)
Type: files; Name: "{app}\scripts\clean.ps1"
Type: files; Name: "{app}\scripts\standby.ps1"

[Icons]
Name: "{autoprograms}\Amnesia"; Filename: "{app}\Amnesia.exe"

[Run]
Filename: "{app}\Amnesia.exe"; Description: "{cm:OpenApp}"; Flags: nowait postinstall skipifsilent
; after an update from inside the app (silent setup): open Amnesia again in the tray
Filename: "{app}\Amnesia.exe"; Parameters: "--login-tray"; Flags: nowait; Check: WizardSilent

[UninstallRun]
; turn Amnesia off (nothing is wiped any more, start with Windows removed), then close it
Filename: "{app}\Amnesia.exe"; Parameters: "--off"; Flags: runhidden waituntilterminated; RunOnceId: "AmnesiaOff"

[Code]
var
  KeepStillLocked: Boolean;

// v0.7: a PC with the lab lock on can only be uninstalled with the lab PIN (Amnesia asks it and removes the lock).
// v0.8: then a locked Keep folder: Amnesia asks the Keep password and opens it for good (exit 2 = it stays locked).
function InitializeUninstall(): Boolean;
var
  Code: Integer;
begin
  Result := True;
  KeepStillLocked := False;
  if FileExists(ExpandConstant('{app}\Amnesia.exe')) then
  begin
    if Exec(ExpandConstant('{app}\Amnesia.exe'), '--lab-check', '', SW_SHOW, ewWaitUntilTerminated, Code) and (Code <> 0) then
    begin
      MsgBox(CustomMessage('LabLocked'), mbInformation, MB_OK);
      Result := False;
      exit;
    end;
    if not UninstallSilent then
      if Exec(ExpandConstant('{app}\Amnesia.exe'), '--keep-check', '', SW_SHOW, ewWaitUntilTerminated, Code) and (Code = 2) then
        KeepStillLocked := True;
  end;
end;

// close a running Amnesia before files are replaced (an update). --quit never cleans anything.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Code: Integer;
begin
  if FileExists(ExpandConstant('{app}\Amnesia.exe')) then
    Exec(ExpandConstant('{app}\Amnesia.exe'), '--quit', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Result := '';
end;

// v0.6: after removing, Start sometimes kept showing a dead Amnesia entry until the next sign in.
// Restarting Start's own process (Windows starts it again at once) makes it read the list again.
// v0.8: Amnesia's own data (.amnesia) is only deleted when you say so (never in a silent uninstall, never while Keep
// is still locked: the Keep password is stored there).
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Code: Integer;
  Data: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    Exec(ExpandConstant('{sys}\taskkill.exe'), '/f /im StartMenuExperienceHost.exe', '', SW_HIDE, ewWaitUntilTerminated, Code);
    Data := ExpandConstant('{%USERPROFILE}\.amnesia');
    if (not UninstallSilent) and DirExists(Data) then
    begin
      if KeepStillLocked then
        MsgBox(FmtMessage(CustomMessage('DataKept'), [Data]), mbInformation, MB_OK)
      else if MsgBox(FmtMessage(CustomMessage('AskData'), [Data]), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
        DelTree(Data, True, True, True);
    end;
  end;
end;
