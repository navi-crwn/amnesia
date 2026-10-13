; Amnesia for Windows: Setup.exe (Inno Setup 6). Built by GitHub Actions (.github/workflows/windows.yml):
;   ISCC.exe /DArch=x64|arm64 /DVersion=0.5.0 /DSrc=<folder with Amnesia.exe, ui\, scripts\> installer\Amnesia.iss
; Installs just for you (no admin) into %LOCALAPPDATA%\Programs\Amnesia, the folder Amnesia's cleanup never touches,
; adds a Start menu entry and an entry in Apps & features. Amnesia stays OFF after installing: you turn it on in the app.
; Updating and uninstalling first close Amnesia with "Amnesia.exe --quit", which never runs a cleanup.

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
Name: "en"; MessagesFile: "compiler:Default.isl"

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
Filename: "{app}\Amnesia.exe"; Description: "Open Amnesia"; Flags: nowait postinstall skipifsilent
; after an update from inside the app (silent setup): open Amnesia again in the tray
Filename: "{app}\Amnesia.exe"; Parameters: "--login-tray"; Flags: nowait; Check: WizardSilent

[UninstallRun]
; turn Amnesia off (nothing is wiped any more, start with Windows removed), then close it
Filename: "{app}\Amnesia.exe"; Parameters: "--off"; Flags: runhidden waituntilterminated; RunOnceId: "AmnesiaOff"

[Code]
// v0.7: a PC with the lab lock on can only be uninstalled with the lab PIN (Amnesia asks it and removes the lock).
function InitializeUninstall(): Boolean;
var
  Code: Integer;
begin
  Result := True;
  if FileExists(ExpandConstant('{app}\Amnesia.exe')) then
    if Exec(ExpandConstant('{app}\Amnesia.exe'), '--lab-check', '', SW_SHOW, ewWaitUntilTerminated, Code) and (Code <> 0) then
    begin
      MsgBox('This PC has the Amnesia lab lock on. Amnesia stays installed until the lab PIN is entered.', mbInformation, MB_OK);
      Result := False;
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
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Code: Integer;
begin
  if CurUninstallStep = usPostUninstall then
    Exec(ExpandConstant('{sys}\taskkill.exe'), '/f /im StartMenuExperienceHost.exe', '', SW_HIDE, ewWaitUntilTerminated, Code);
end;
