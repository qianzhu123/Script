$ErrorActionPreference = "Stop"

# ============================================================
#  Design MD Copier
#  Copy DESIGN.md from selected awesome-design-md folders
#  into a target project directory.
# ============================================================

$DesignMdRoot = "D:\data\Prompt\awesome-design-md-main\design-md"

# ----- Validate source directory -----
if (-not (Test-Path -Path $DesignMdRoot -PathType Container)) {
    Write-Host "[ERROR] Design-MD root not found: $DesignMdRoot" -ForegroundColor Red
    pause
    exit 1
}

# ----- Collect available brand folders -----
$folders = Get-ChildItem -Path $DesignMdRoot -Directory | Sort-Object Name

$validFolders = @()
foreach ($f in $folders) {
    $designFile = Join-Path $f.FullName "DESIGN.md"
    if (Test-Path -Path $designFile -PathType Leaf) {
        $validFolders += $f
    }
}

if ($validFolders.Count -eq 0) {
    Write-Host "[ERROR] No folders contain DESIGN.md in: $DesignMdRoot" -ForegroundColor Red
    pause
    exit 1
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Design MD Copier" -ForegroundColor Cyan
Write-Host "  Copy DESIGN.md to your project" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ----- Prompt for target project path -----
Write-Host "Enter target project path:" -ForegroundColor Yellow
$targetPath = Read-Host ">"

if ([string]::IsNullOrWhiteSpace($targetPath)) {
    Write-Host "[ERROR] Project path cannot be empty." -ForegroundColor Red
    pause
    exit 1
}

# Expand environment variables and resolve
$targetPath = [System.Environment]::ExpandEnvironmentVariables($targetPath)
if (-not (Test-Path -Path $targetPath -PathType Container)) {
    Write-Host "[WARN] Directory does not exist: $targetPath" -ForegroundColor Yellow
    Write-Host "Create it? (Y/N)" -ForegroundColor Yellow
    $create = Read-Host ">"
    if ($create -eq "Y" -or $create -eq "y") {
        New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
        Write-Host "[OK] Created: $targetPath" -ForegroundColor Green
    } else {
        Write-Host "[CANCELLED] Operation aborted." -ForegroundColor Red
        pause
        exit 0
    }
}

# ----- Display available folders -----
Write-Host ""
Write-Host "Available design references ($($validFolders.Count) brands):" -ForegroundColor Cyan
Write-Host "---------------------------------------------" -ForegroundColor DarkGray

$index = 1
foreach ($f in $validFolders) {
    Write-Host ("  {0,3}. {1}" -f $index, $f.Name) -ForegroundColor White
    $index++
}

Write-Host "---------------------------------------------" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Select folders to copy (space-separated numbers or ranges):" -ForegroundColor Yellow
Write-Host "  Examples: 1 3 5    |    1-10    |    1 3 5-8 12    |    all" -ForegroundColor DarkGray
Write-Host ""

$selection = Read-Host ">"

if ([string]::IsNullOrWhiteSpace($selection)) {
    Write-Host "[CANCELLED] No selection made." -ForegroundColor Red
    pause
    exit 0
}

# ----- Parse selection -----
$selectedIndices = @()

if ($selection.Trim() -eq "all") {
    $selectedIndices = 1..$validFolders.Count
} else {
    $tokens = $selection.Trim() -split '\s+'
    foreach ($token in $tokens) {
        if ($token -match '^(\d+)-(\d+)$') {
            $start = [int]$Matches[1]
            $end   = [int]$Matches[2]
            if ($start -ge 1 -and $end -le $validFolders.Count -and $start -le $end) {
                $selectedIndices += $start..$end
            } else {
                Write-Host "[WARN] Invalid range: $token (skipped)" -ForegroundColor Yellow
            }
        } elseif ($token -match '^\d+$') {
            $num = [int]$token
            if ($num -ge 1 -and $num -le $validFolders.Count) {
                $selectedIndices += $num
            } else {
                Write-Host "[WARN] Invalid number: $token (skipped)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "[WARN] Unrecognized token: $token (skipped)" -ForegroundColor Yellow
        }
    }
}

# Deduplicate and sort
$selectedIndices = $selectedIndices | Sort-Object -Unique

if ($selectedIndices.Count -eq 0) {
    Write-Host "[CANCELLED] No valid selection." -ForegroundColor Red
    pause
    exit 0
}

Write-Host ""
Write-Host "Selected $($selectedIndices.Count) design(s):" -ForegroundColor Cyan
foreach ($i in $selectedIndices) {
    Write-Host ("  - {0}" -f $validFolders[$i - 1].Name) -ForegroundColor White
}
Write-Host ""

# ----- Confirm before copy -----
Write-Host "Proceed with copy? (Y/N)" -ForegroundColor Yellow
$confirm = Read-Host ">"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "[CANCELLED] Operation aborted." -ForegroundColor Red
    pause
    exit 0
}

# ----- Copy DESIGN.md files -----
Write-Host ""
$copiedCount = 0
$skippedCount = 0

foreach ($i in $selectedIndices) {
    $folder     = $validFolders[$i - 1]
    $srcFile    = Join-Path $folder.FullName "DESIGN.md"
    $destFolder = Join-Path $targetPath $folder.Name
    $destFile   = Join-Path $destFolder "DESIGN.md"

    try {
        if (-not (Test-Path -Path $destFolder -PathType Container)) {
            New-Item -Path $destFolder -ItemType Directory -Force | Out-Null
        }

        if (Test-Path -Path $destFile -PathType Leaf) {
            Write-Host ("  [SKIP] {0}/DESIGN.md already exists" -f $folder.Name) -ForegroundColor Yellow
            $skippedCount++
        } else {
            Copy-Item -Path $srcFile -Destination $destFile -Force
            Write-Host ("  [OK]   {0}/DESIGN.md" -f $folder.Name) -ForegroundColor Green
            $copiedCount++
        }
    } catch {
        Write-Host ("  [ERR]  {0}: {1}" -f $folder.Name, $_.Exception.Message) -ForegroundColor Red
        $skippedCount++
    }
}

# ----- Summary -----
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Done! Copied: $copiedCount | Skipped: $skippedCount" -ForegroundColor Cyan
Write-Host "  Target: $targetPath" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

pause
