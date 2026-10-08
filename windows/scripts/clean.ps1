<#
  AMNESIA CLEAN for Windows (early preview)
  Shows what Amnesia WOULD delete from your user folder. In this version it never deletes anything:
  without -DryRun it stops with an error. Real cleanup comes later, after it has been tested in a VM.

    clean.ps1 [-Mode logout|login|now] -DryRun [-Json]

  Protected (never touched):
    - your Keep folder (KEEP_DIR in %USERPROFILE%\.amnesia\settings.conf, default %USERPROFILE%\Keep)
    - %USERPROFILE%\.amnesia
    - every line in %USERPROFILE%\.amnesia\keep.conf (paths from your user folder, * works as a wildcard, / or \)
    - what Windows itself needs to log you in (see $BuiltInKeep)
    - links/junctions such as "Application Data" are never followed
  Your standard folders (Desktop, Documents, Downloads, ...) stay; only what is inside them goes.

  Works with Windows PowerShell 5.1 (built into Windows) and PowerShell 7.
  AMNESIA_HOME (environment variable) replaces the user folder; only used by the tests.
#>
[CmdletBinding()]
param(
    [ValidateSet('logout', 'login', 'now')] [string] $Mode = 'now',
    [switch] $DryRun,
    [switch] $Json
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

if (-not $DryRun) {
    [Console]::Error.WriteLine('Real cleanup is not built yet in this early Windows version. Only -DryRun works.')
    exit 2
}

# the app reads the answer as UTF-8 (names with é, ü, emoji...); Windows PowerShell 5.1 would otherwise use the old code page
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }

if ($env:AMNESIA_HOME) { $H = $env:AMNESIA_HOME } else { $H = [Environment]::GetFolderPath('UserProfile') }
$H = $H.TrimEnd('\', '/')
$A = Join-Path $H '.amnesia'

# ---------- what is protected ----------
# Windows needs these to log you in, keep saved passwords (Credential Manager, DPAPI keys) and run Store apps.
$BuiltInKeep = @(
    'NTUSER*', 'ntuser*',
    '.amnesia',
    'AppData/Local/Microsoft',
    'AppData/Roaming/Microsoft',
    'AppData/Local/Packages',
    'AppData/Local/Amnesia',
    'AppData/Local/Programs/Amnesia'
)
# Kept by name wherever they are (Windows uses them to show folder names and icons).
$KeepByName = @('desktop.ini')
# Folders that stay; only what is inside them is wiped.
$Containers = @(
    'AppData', 'AppData/Roaming', 'AppData/Local', 'AppData/LocalLow',
    'Desktop', 'Documents', 'Downloads', 'Pictures', 'Music', 'Videos',
    'Favorites', 'Contacts', 'Links', 'Saved Games', 'Searches', '3D Objects'
)

function Get-Setting([string] $name) {
    $f = Join-Path $A 'settings.conf'
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    $line = Get-Content -LiteralPath $f | Where-Object { $_ -like "$name=*" } | Select-Object -Last 1
    if ($line) { return $line.Substring($name.Length + 1) }
    return $null
}

# Keep folder: "~/Something" = inside the user folder; a full path outside it is never touched anyway.
$keepRel = 'Keep'
$kd = Get-Setting 'KEEP_DIR'
if ($kd) {
    $kd = $kd.Trim().Replace('\', '/')
    if ($kd.StartsWith('~/')) { $keepRel = $kd.Substring(2).TrimEnd('/') }
    elseif ($kd.Replace('\', '/').StartsWith($H.Replace('\', '/') + '/', [StringComparison]::OrdinalIgnoreCase)) {
        $keepRel = $kd.Substring($H.Length + 1).TrimEnd('/')
    }
    else { $keepRel = '' } # outside the user folder: never touched anyway
    if ($keepRel -like '.amnesia*' -or $keepRel -like 'AppData*') { $keepRel = 'Keep' } # same safety rule as the Mac
}

$patterns = New-Object System.Collections.Generic.List[string]
$BuiltInKeep | ForEach-Object { $patterns.Add($_) }
if ($keepRel) { $patterns.Add($keepRel) }
$kc = Join-Path $A 'keep.conf'
if (Test-Path -LiteralPath $kc) {
    foreach ($l in Get-Content -LiteralPath $kc) {
        $l = $l.Trim()
        if ($l -eq '' -or $l.StartsWith('#') -or $l -match '^[a-z]+:') { continue } # comments, keychain:/credential: lines
        $patterns.Add($l.Replace('\', '/').Trim('/'))
    }
}

# ---------- matching (always with / inside, case-insensitive like Windows) ----------
function Test-Kept([string] $rel) {
    $leaf = Split-Path -Leaf $rel
    foreach ($n in $KeepByName) { if ($leaf -like $n) { return $true } }
    foreach ($p in $patterns) {
        if ($rel -like $p) { return $true }
        # inside a kept folder: everything below it stays too
        $ps = $p.Split('/'); $rs = $rel.Split('/')
        if ($rs.Count -gt $ps.Count) { if ((($rs[0..($ps.Count - 1)]) -join '/') -like $p) { return $true } }
    }
    return $false
}
# true when something that must stay is somewhere inside this folder: then we look inside instead of wiping it whole
function Test-HoldsKept([string] $rel) {
    $rs = $rel.Split('/')
    foreach ($p in $patterns) {
        $ps = $p.Split('/')
        if ($ps.Count -gt $rs.Count) { if ($rel -like (($ps[0..($rs.Count - 1)]) -join '/')) { return $true } }
    }
    return $false
}

$items = New-Object System.Collections.Generic.List[object]
$kept = New-Object System.Collections.Generic.List[string]
$sep = [IO.Path]::DirectorySeparatorChar

function Visit([string] $rel) {
    $dir = if ($rel) { Join-Path $H ($rel.Replace('/', $sep)) } else { $H }
    foreach ($c in Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue) {
        $r = if ($rel) { "$rel/$($c.Name)" } else { $c.Name }
        if ($c.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue } # junctions/links: never followed, never deleted
        if (Test-Kept $r) { $kept.Add($r.Replace('/', '\')); continue }
        if ($c.PSIsContainer -and (($Containers -contains $r) -or (Test-HoldsKept $r))) { Visit $r; continue }
        $kind = if ($c.PSIsContainer) { 'folder' } else { 'file' }
        $items.Add([pscustomobject]@{ path = $r.Replace('/', '\'); kind = $kind })
    }
}
Visit ''

if ($Json) {
    [pscustomobject]@{
        mode = $Mode; dryRun = $true; home = $H
        count = $items.Count; items = $items.ToArray(); kept = $kept.ToArray()
    } | ConvertTo-Json -Depth 4 -Compress
}
else {
    foreach ($i in $items) { "would delete: $($i.path)" }
    "--- $($items.Count) item(s) would be deleted (dry run, nothing was touched)"
}
