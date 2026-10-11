<#
  Amnesia for Windows: collect a log for troubleshooting.
  v0.6: writes ONE text file into your Keep folder (amnesia-log.txt), so it stays private to you and is not left in
  Public Documents for every user of this PC to read. Opens it in Notepad. Nothing is sent anywhere: you decide what to share.
  No file names from your folders are collected, only Amnesia's own step log, settings and Windows error events.
  Run it by double-clicking "Collect log.cmd" next to this file.
#>
param([string]$Dir = '')
$ErrorActionPreference = 'Continue'
$H = [Environment]::GetFolderPath('UserProfile')
$A = Join-Path $H '.amnesia'
$docs = $Dir
if (-not $docs) { $k = Join-Path $H 'Keep'; if (Test-Path $k) { $docs = $k } else { $docs = [IO.Path]::GetTempPath() } }
New-Item -ItemType Directory -Force $docs | Out-Null
$out = Join-Path $docs 'amnesia-log.txt'
$lines = New-Object System.Collections.Generic.List[string]
function Add([string] $s) { $lines.Add($s) }
function Section([string] $t) { Add ''; Add "=== $t ===" }
function Tail([string] $file, [int] $n) {
    if (Test-Path -LiteralPath $file) { Get-Content -LiteralPath $file -Tail $n | ForEach-Object { Add $_ } }
    else { Add "(no $([IO.Path]::GetFileName($file)))" }
}

Add "Amnesia log, made $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

Section 'Windows'
try {
    $os = Get-CimInstance Win32_OperatingSystem
    Add "$($os.Caption) $($os.Version) build $($os.BuildNumber), $env:PROCESSOR_ARCHITECTURE"
    Add "Last boot: $($os.LastBootUpTime)"
} catch { Add "(could not read Windows version: $($_.Exception.Message))" }
try {
    $cs = Get-CimInstance Win32_ComputerSystem
    Add "Model: $($cs.Manufacturer) $($cs.Model), RAM $([math]::Round($cs.TotalPhysicalMemory / 1GB, 1)) GB"
} catch { }

Section 'Amnesia'
$inst = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\Amnesia\Amnesia.exe'
if (Test-Path -LiteralPath $inst) { Add "Installed: yes, version $((Get-Item -LiteralPath $inst).VersionInfo.ProductVersion)" } else { Add 'Installed: no' }
try {
    $run = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Amnesia' -ErrorAction Stop).Amnesia
    Add "Starts with Windows: yes ($run)"
} catch { Add 'Starts with Windows: no' }
Add "Installed with Setup.exe: $(Test-Path -LiteralPath (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\Amnesia\unins000.exe'))"
Add "Vault: $(Test-Path -LiteralPath (Join-Path $A 'vault\public.key'))"
Add "Paused (1 session): $(Test-Path -LiteralPath (Join-Path $A 'pause_once'))"
Add "Trash waiting to be deleted: $(Test-Path -LiteralPath (Join-Path $H '.amnesia-trash'))"
Add '-- settings.conf --'
Tail (Join-Path $A 'settings.conf') 50
Add '-- doomsday.log --'
Tail (Join-Path $A 'doomsday.log') 5

Section 'Amnesia step log (trace.log, last 60 lines)'
Tail (Join-Path $A 'trace.log') 60
Section 'Amnesia history (last 30 lines)'
Tail (Join-Path $A 'history.log') 30

Section 'Disk encryption'
try {
    $v = (New-Object -ComObject Shell.Application).NameSpace("$env:SystemDrive\").Self.ExtendedProperty('System.Volume.BitLockerProtection')
    $txt = @{ 1 = 'on'; 3 = 'on'; 6 = 'on'; 5 = 'paused'; 2 = 'off'; 4 = 'off' }[[int]$v]
    Add "BitLockerProtection = $v ($(if ($txt) { $txt } else { 'unknown' }))"
} catch { Add "(could not read: $($_.Exception.Message))" }
try {
    $mb = & manage-bde -status $env:SystemDrive 2>&1 | Out-String
    if ($mb -match 'Protection Status|Conversion Status') { $mb.Trim().Split("`n") | Select-Object -Last 12 | ForEach-Object { Add $_.TrimEnd() } }
    else { Add '(manage-bde needs "Run as administrator", skipped)' }
} catch { }

Section 'Windows errors and unexpected shutdowns (last 3 days)'
try {
    Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1, 2; StartTime = (Get-Date).AddDays(-3) } -MaxEvents 40 -ErrorAction Stop |
        ForEach-Object { Add ('{0:yyyy-MM-dd HH:mm:ss}  {1,-6} {2}: {3}' -f $_.TimeCreated, $_.Id, $_.ProviderName, (($_.Message -split "`n")[0]).Trim()) }
} catch { Add "(none or not readable: $($_.Exception.Message))" }
try {
    Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 41, 6008, 1074; StartTime = (Get-Date).AddDays(-3) } -MaxEvents 15 -ErrorAction Stop |
        ForEach-Object { Add ('{0:yyyy-MM-dd HH:mm:ss}  {1,-6} {2}: {3}' -f $_.TimeCreated, $_.Id, $_.ProviderName, (($_.Message -split "`n")[0]).Trim()) }
} catch { }
Section 'Startup repair log'
$srt = Join-Path "$env:SystemRoot\" 'System32\LogFiles\Srt\SrtTrail.txt'
if ($env:SystemRoot -and (Test-Path -LiteralPath $srt)) { Tail $srt 40 } else { Add '(no SrtTrail.txt: Windows did not run Startup Repair)' }

try {
    [IO.File]::WriteAllLines($out, $lines, (New-Object System.Text.UTF8Encoding $true))
    Write-Host "Saved: $out"
    Start-Process notepad.exe $out
} catch {
    Write-Host "Could not save the log: $($_.Exception.Message)"
    $lines | ForEach-Object { Write-Host $_ }
}
