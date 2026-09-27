$ErrorActionPreference = "Stop"

# ============================================================
#  BongoCat DLL Updater
#  Find the newest Assembly-CSharp.dll downloaded within the
#  last 24 hours under %USERPROFILE%\Downloads (path must
#  contain a BongoCat-related keyword), then overwrite the
#  DLL in the game's Managed folder.
#
#  No backup is made before overwriting (the game self-repairs
#  via Steam if anything goes wrong).
# ============================================================

# ---------- Configuration ----------
$DownloadsRoot = Join-Path $env:USERPROFILE "Downloads"
$DllName      = "Assembly-CSharp.dll"
$MaxAgeHours  = 24
$Keyword      = "bongocat"
# This machine is Windows: only accept DLLs whose path sits under a
# Windows/win folder, so the macOS/linux builds shipped in the same
# archive are never picked.
$PlatformRegex = '(\\|/)Windows(\\|/)|(\\|/)win(\\|/)'
$GameManaged   = "D:\tools\Misc\Tools\Steam\steamapps\common\BongoCat\BongoCat_Data\Managed"
$GameDll       = Join-Path $GameManaged $DllName

# ---------- Helpers ----------
function Write-Section($t) { Write-Host "`n==== $t ====" -ForegroundColor Cyan }
function Write-Ok($t)       { Write-Host "[OK] $t" -ForegroundColor Green }
function Write-Warn($t)     { Write-Host "[!!] $t" -ForegroundColor Yellow }
function Write-Err($t)      { Write-Host "[ERROR] $t" -ForegroundColor Red }

# ---------- Validate downloads root ----------
if (-not (Test-Path -Path $DownloadsRoot -PathType Container)) {
    Write-Err "Downloads folder not found: $DownloadsRoot"
    pause; exit 1
}

Write-Section "BongoCat DLL Updater"
Write-Host "Source: $DownloadsRoot (recursively, last $MaxAgeHours hours, keyword: $Keyword, Windows builds only)"
Write-Host "Target: $GameDll"

# ---------- Find candidate DLLs ----------
$cutoff = (Get-Date).AddHours(-$MaxAgeHours)
Write-Section "Scanning Downloads ..."

$candidates = Get-ChildItem -Path $DownloadsRoot -Recurse -Filter $DllName -File -ErrorAction SilentlyContinue |
    Where-Object {
        ($_.LastWriteTime -ge $cutoff) -and
        ($_.FullName -imatch $Keyword) -and
        ($_.FullName -imatch $PlatformRegex)
    } |
    Sort-Object LastWriteTime -Descending

if (-not $candidates -or $candidates.Count -eq 0) {
    Write-Err "No '$DllName' younger than $MaxAgeHours hours with keyword '$Keyword' under $DownloadsRoot"
    Write-Host "Tip: make sure the mod archive was just downloaded/extracted under Downloads."
    pause; exit 1
}

# Newest one
$source = $candidates[0]
Write-Ok "Found $($candidates.Count) candidate(s). Newest selected:"
Write-Host "  Path : $($source.FullName)"
Write-Host "  Size : $([math]::Round($source.Length / 1KB, 1)) KB"
Write-Host "  Time : $($source.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"

# ---------- Handle multiple candidates ----------
if ($candidates.Count -gt 1) {
    Write-Warn "Other recent candidates (ignored):"
    $candidates | Select-Object -Skip 1 | ForEach-Object {
        Write-Host ("    {0}  {1}" -f $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'), $_.FullName) -ForegroundColor DarkGray
    }
}

# ---------- Validate target ----------
if (-not (Test-Path -Path $GameDll -PathType Leaf)) {
    Write-Err "Target DLL not found: $GameDll"
    Write-Host "Check that BongoCat is installed at the expected Steam path."
    pause; exit 1
}

$targetInfo = Get-Item $GameDll
Write-Section "Current target DLL"
Write-Host "  Path : $($targetInfo.FullName)"
Write-Host "  Size : $([math]::Round($targetInfo.Length / 1KB, 1)) KB"
Write-Host "  Time : $($targetInfo.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"

# ---------- Overwrite (no backup) ----------
try {
    Copy-Item -Path $source.FullName -Destination $GameDll -Force
    Write-Ok "Replaced '$DllName' in game folder with the downloaded one."
    Write-Host "  $($source.FullName)"
    Write-Host "  -> $GameDll"
} catch {
    Write-Err "Failed to overwrite: $($_.Exception.Message)"
    Write-Host "If the game is running, close BongoCat first (the DLL may be locked)."
    pause; exit 1
}

Write-Section "Done"
pause
