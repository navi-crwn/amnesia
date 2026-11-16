# Installer and sign-in cleanup test for Amnesia for Windows.
# It runs on a throwaway GitHub Actions Windows machine (see .github/workflows/windows.yml, job "installer-test").
# It installs the Setup.exe from the build, makes sample files in the real profile of that machine, runs the real
# sign-in cleanup, checks what went and what stayed, then uninstalls and looks for leftovers.
#
# It deletes files in the profile of the user who runs it. It refuses to run anywhere except GitHub Actions.
param([Parameter(Mandatory = $true)][string]$SetupDir)

if ($env:GITHUB_ACTIONS -ne 'true') {
    Write-Output 'This test wipes the profile of the user who runs it. It only runs on GitHub Actions. Stopping.'
    exit 2
}

$ErrorActionPreference = 'Stop'
$script:fails = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { Write-Output "  ok    $what" } else { Write-Output "  FAIL  $what"; $script:fails++ }
}
function Put([string]$rel, [string]$text = 'x') {
    $p = Join-Path $env:USERPROFILE $rel
    New-Item -ItemType Directory -Path (Split-Path $p) -Force | Out-Null
    Set-Content -Path $p -Value $text
}
function Here([string]$rel) { Test-Path -LiteralPath (Join-Path $env:USERPROFILE $rel) }

$setup = Get-ChildItem $SetupDir -Recurse -Filter 'Amnesia-Setup-*-x64.exe' | Select-Object -First 1
if (-not $setup) { throw "No Amnesia-Setup-*-x64.exe found in $SetupDir" }
$home_ = $env:USERPROFILE
$app = Join-Path $env:LOCALAPPDATA 'Programs\Amnesia'
$exe = Join-Path $app 'Amnesia.exe'
$data = Join-Path $home_ '.amnesia'
$trash = Join-Path $home_ '.amnesia-trash'
$local = Join-Path $env:LOCALAPPDATA 'Amnesia'

function Stop-Amnesia {
    if (Test-Path $exe) { Start-Process $exe -ArgumentList '--quit' -Wait -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
    Get-Process -Name Amnesia -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

try {
    Write-Output "== Silent install: $($setup.Name)"
    $p = Start-Process $setup.FullName -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
    Check ($p.ExitCode -eq 0) "Setup.exe exits with 0 (got $($p.ExitCode))"
    Check (Test-Path $exe) 'Amnesia.exe is installed'
    Check (Test-Path (Join-Path $app 'unins000.exe')) 'the uninstaller is installed'
    Check (Test-Path (Join-Path $app 'ui\index.html')) 'the page files are installed'
    Stop-Amnesia   # a silent install starts Amnesia in the tray; it has to be gone before the cleanup runs

    Write-Output '== --keep-locked with no Keep lock'
    $p = Start-Process $exe -ArgumentList '--keep-locked' -Wait -PassThru
    Check ($p.ExitCode -eq 0) "--keep-locked exits with 0 when Keep is not locked (got $($p.ExitCode))"

    Write-Output '== Sample files and settings (what Turn On would have written)'
    Put 'Desktop\wipe-me.txt'; Put 'Documents\wipe-me.txt'; Put 'Downloads\wipe-me.txt'
    Put 'Documents\Proyek\Dalam\rahasia.kdbx'; Put 'Documents\Proyek\Dalam\sampah.txt'
    Put 'Documents\Spesial\a.txt'; Put 'Documents\Biasa\b.txt'; Put 'Keep\aman.txt'
    New-Item -ItemType Directory -Path $data -Force | Out-Null
    Set-Content (Join-Path $data 'settings.conf') @('ENABLED=1', "APP_PATH=$exe", 'LANG=en')
    Set-Content (Join-Path $data 'keep.conf') @('*.kdbx', '~/Documents/Spesial', 'D:\Elsewhere\Ke')

    Write-Output '== Sign-in cleanup (the real one, on this throwaway profile)'
    $run = Start-Process $exe -ArgumentList '--login' -PassThru
    $trace = Join-Path $data 'trace.log'
    $done = $false
    for ($i = 0; $i -lt 120; $i++) {
        Start-Sleep -Seconds 2
        if ((Test-Path $trace) -and (Select-String -Path $trace -Pattern 'sign in check (finished|failed)' -Quiet)) { $done = $true; break }
        if ($run.HasExited) { break }
    }
    Start-Sleep -Seconds 3
    Check $done 'the sign-in check finished'
    Stop-Amnesia
    Check (-not (Here 'Desktop\wipe-me.txt')) 'Desktop\wipe-me.txt was wiped'
    Check (-not (Here 'Documents\wipe-me.txt')) 'Documents\wipe-me.txt was wiped'
    Check (-not (Here 'Downloads\wipe-me.txt')) 'Downloads\wipe-me.txt was wiped'
    Check (-not (Here 'Documents\Proyek\Dalam\sampah.txt')) 'sampah.txt next to the kept file was wiped'
    Check (-not (Here 'Documents\Biasa')) 'a plain Documents folder was wiped'
    Check (Here 'Documents\Proyek\Dalam\rahasia.kdbx') 'rahasia.kdbx stayed (the line *.kdbx protects it in a sub folder)'
    Check (Here 'Documents\Spesial\a.txt') 'Documents\Spesial stayed (the line was written as ~/Documents/Spesial)'
    Check (Here 'Keep\aman.txt') 'the Keep folder stayed'
    Check (Test-Path (Join-Path $data 'keep.conf')) 'keep.conf is still there'

    Write-Output '== Silent uninstall with Keep locked must stop'
    Add-Content (Join-Path $data 'settings.conf') @('KEEP_LOCK=1', 'KEEP_LOCK_PW=not-a-real-hash')
    Start-Process (Join-Path $app 'unins000.exe') -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait
    Start-Sleep -Seconds 8
    Check (Test-Path $exe) 'a silent uninstall with Keep locked leaves Amnesia installed'
    $lines = Get-Content (Join-Path $data 'settings.conf') | Where-Object { $_ -notmatch '^KEEP_LOCK' }
    Set-Content (Join-Path $data 'settings.conf') $lines

    Write-Output '== Uninstall leaves nothing behind'
    New-Item -ItemType Directory -Path (Join-Path $local 'WebView2') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $local 'update') -Force | Out-Null
    Set-Content (Join-Path $local 'WebView2\x.txt') 'x'; Set-Content (Join-Path $local 'update\y.exe') 'x'
    New-Item -ItemType Directory -Path (Join-Path $trash '20260101-000000\Documents') -Force | Out-Null
    Set-Content (Join-Path $trash '20260101-000000\Documents\f.txt') 'x'
    New-Item -ItemType Directory -Path (Join-Path $trash '29990101-000000-apps\AppData') -Force | Out-Null
    Start-Process (Join-Path $app 'unins000.exe') -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait
    for ($i = 0; $i -lt 30 -and (Test-Path $app); $i++) { Start-Sleep -Seconds 2 }
    Check (-not (Test-Path $app)) 'the install folder is gone'
    Check (-not (Test-Path $local)) '%LOCALAPPDATA%\Amnesia (WebView2 data, update) is gone'
    Check (-not (Test-Path $trash)) '.amnesia-trash is gone, including the new app folder'
    Check (Test-Path (Join-Path $data 'settings.conf')) 'your settings stay (the default uninstall keeps .amnesia)'
    Check ((Get-Content (Join-Path $data 'settings.conf')) -contains 'ENABLED=0') 'Amnesia was turned off by the uninstaller'
}
finally {
    $trace = Join-Path $data 'trace.log'
    if (Test-Path $trace) { Write-Output '== trace.log (steps only, no file names)'; Get-Content $trace -Tail 40 }
}

if ($script:fails -gt 0) { Write-Output "$($script:fails) check(s) failed"; exit 1 }
Write-Output 'All installer checks passed'
