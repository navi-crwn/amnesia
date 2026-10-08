<#
  Tests for scripts\clean.ps1 (dry run). Builds a fake user folder in a temp folder, never touches the real one.
    pwsh -File windows\tests\test_clean.ps1      (also runs in GitHub Actions on Windows)
#>
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot '..\scripts\clean.ps1'
$fake = Join-Path ([IO.Path]::GetTempPath()) ("amnesia-test-" + [guid]::NewGuid().ToString('N'))
$fails = 0
# which PowerShell runs clean.ps1: pwsh (7) by default, AMNESIA_TEST_SHELL=powershell for the Windows built-in 5.1
$sh = if ($env:AMNESIA_TEST_SHELL) { $env:AMNESIA_TEST_SHELL } else { 'pwsh' }
Write-Host "Testing clean.ps1 with $sh"
function Check([bool] $ok, [string] $what) {
    if ($ok) { Write-Host "  ok    $what" } else { Write-Host "  FAIL  $what"; $script:fails++ }
}
function Make([string] $rel, [switch] $Dir) {
    $p = Join-Path $fake $rel
    if ($Dir) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
    else { New-Item -ItemType Directory -Force -Path (Split-Path $p) | Out-Null; Set-Content -LiteralPath $p -Value 'x' }
}

try {
    # a pretend user folder
    Make 'NTUSER.DAT'
    Make 'Downloads/movie.mp4'
    Make 'Downloads/desktop.ini'
    Make 'Desktop/notes.txt'
    Make 'Documents/Projects/site/index.html'
    Make 'Documents/Taxes/2026.pdf'
    Make 'AppData/Roaming/Microsoft/Credentials/abc'
    Make 'AppData/Roaming/SomeChat/session.db'
    Make 'AppData/Roaming/Code/User/settings.json'
    Make 'AppData/Roaming/Code/Cache/blob'
    Make 'AppData/Local/Temp/tmp1.tmp'
    Make 'AppData/Local/Packages/App/x'
    Make 'AppData/Local/Amnesia/WebView2/x'
    Make 'Keep/important.txt'
    Make 'Vault2/secret.txt'
    Make '.ssh/id_ed25519'
    Make '.gitconfig'
    Make '.amnesia/settings.conf'
    Set-Content -LiteralPath (Join-Path $fake '.amnesia/settings.conf') -Value 'LANG=id'
    Set-Content -LiteralPath (Join-Path $fake '.amnesia/keep.conf') -Value @(
        '# my keep list', '.ssh', 'Documents\Taxes', 'AppData/Roaming/Code*/User', 'keychain:whatever'
    )

    $env:AMNESIA_HOME = $fake
    $out = & $sh -NoProfile -ExecutionPolicy Bypass -File $script -DryRun -Json
    Check ($LASTEXITCODE -eq 0) 'dry run finishes'
    $r = $out | ConvertFrom-Json
    $del = @($r.items | ForEach-Object { $_.path })
    $keep = @($r.kept)

    Write-Host 'Would be deleted:'
    Check ($del -contains 'Downloads\movie.mp4') 'Downloads content'
    Check ($del -contains 'Desktop\notes.txt') 'Desktop content'
    Check ($del -contains 'Documents\Projects') 'Documents content'
    Check ($del -contains 'AppData\Roaming\SomeChat') 'app data in Roaming'
    Check ($del -contains 'AppData\Roaming\Code\Cache') 'the rest of a partly kept app'
    Check ($del -contains 'AppData\Local\Temp') 'Temp'
    Check ($del -contains 'Vault2') 'a folder that only looks like Keep'
    Check ($del -contains '.gitconfig') 'dot files'

    Write-Host 'Must stay:'
    foreach ($s in 'Downloads', 'Desktop', 'Documents', 'AppData') { Check (-not ($del -contains $s)) "$s folder itself" }
    foreach ($s in 'NTUSER.DAT', 'Keep', '.amnesia', '.ssh', 'Documents\Taxes', 'AppData\Roaming\Code\User',
        'AppData\Roaming\Microsoft', 'AppData\Local\Packages', 'AppData\Local\Amnesia', 'Downloads\desktop.ini') {
        Check (($keep -contains $s) -and -not ($del -contains $s)) $s
    }
    Check (@($del | Where-Object { $_ -like 'Keep\*' -or $_ -like '.amnesia*' }).Count -eq 0) 'nothing inside Keep or .amnesia'

    Write-Host 'Safety:'
    & $sh -NoProfile -ExecutionPolicy Bypass -File $script -Mode logout 2>$null | Out-Null
    Check ($LASTEXITCODE -eq 2) 'without -DryRun it refuses (exit 2)'
    Check (Test-Path (Join-Path $fake 'Downloads/movie.mp4')) 'files are still there'

    # a Keep folder somewhere else, set in settings.conf
    Set-Content -LiteralPath (Join-Path $fake '.amnesia/settings.conf') -Value 'KEEP_DIR=~/Vault2'
    $r2 = (& $sh -NoProfile -ExecutionPolicy Bypass -File $script -DryRun -Json) | ConvertFrom-Json
    Check (@($r2.kept) -contains 'Vault2') 'KEEP_DIR from settings is kept'
    Check (@($r2.items | ForEach-Object { $_.path }) -contains 'Keep') 'old Keep folder is no longer protected'
}
finally {
    Remove-Item Env:AMNESIA_HOME -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fake -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fails) { Write-Host "$fails test(s) failed"; exit 1 }
Write-Host 'All clean.ps1 tests passed'
