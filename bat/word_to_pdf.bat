@echo off
chcp 65001 >nul
setlocal

REM Word to PDF Converter - single BAT script for web service.
REM The PowerShell payload is embedded below, so only this BAT file needs to be registered.

echo ========================================
echo Word to PDF Converter
echo ========================================
echo.
echo Usage:
echo   Enter a folder containing Word documents.
echo   All subfolders are included automatically.
echo   Each PDF is saved beside its source document.
echo.

set "INPUT_PATH="
set /p "INPUT_PATH=Enter Word document folder path: "

if not defined INPUT_PATH (
    echo [ERROR] Folder path is required.
    echo.
    pause
    exit /b 1
)

REM Paths copied from Explorer or terminals are often wrapped in double quotes.
REM Double quotes cannot be part of a Windows file name, so remove them here.
set "INPUT_PATH=%INPUT_PATH:"=%"

set "WORD2PDF_INPUT=%INPUT_PATH%"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$lines=Get-Content -LiteralPath '%~f0' -Encoding UTF8; $idx=[Array]::IndexOf($lines,'# POWERSHELL_PAYLOAD'); if($idx -lt 0){throw 'PowerShell payload not found.'}; $code=($lines[($idx+1)..($lines.Count-1)] -join [Environment]::NewLine); $script=[scriptblock]::Create($code); & $script"

set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" (
    echo [ERROR] Conversion failed. Exit code: %EXIT_CODE%
) else (
    echo [OK] Done.
)

endlocal
pause
exit /b %EXIT_CODE%

# POWERSHELL_PAYLOAD
$ErrorActionPreference = "Stop"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarnMsg {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Resolve-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
}

function Get-SofficePath {
    $cmd = Get-Command "soffice.exe" -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $candidates = @(
        "C:\Program Files\LibreOffice\program\soffice.exe",
        "C:\Program Files (x86)\LibreOffice\program\soffice.exe",
        "C:\Program Files\OpenOffice 4\program\soffice.exe",
        "C:\Program Files (x86)\OpenOffice 4\program\soffice.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

function Test-WordAvailable {
    try {
        $word = New-Object -ComObject Word.Application
        $word.Quit()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Convert-WithWord {
    param(
        [System.IO.FileInfo[]]$Files,
        [string]$TargetDir
    )

    $word = $null
    try {
        $word = New-Object -ComObject Word.Application
        $word.Visible = $false
        $word.DisplayAlerts = 0

        foreach ($file in $Files) {
            $pdfPath = Join-Path $TargetDir ($file.BaseName + ".pdf")
            Write-Info "Converting with Microsoft Word: $($file.FullName)"

            $document = $null
            try {
                $document = $word.Documents.Open($file.FullName, $false, $true)
                # 17 = wdExportFormatPDF
                $document.ExportAsFixedFormat($pdfPath, 17)
                Write-Ok "Saved: $pdfPath"
            }
            catch {
                Write-WarnMsg "Failed: $($file.FullName)"
                Write-WarnMsg $_.Exception.Message
            }
            finally {
                if ($document) {
                    $document.Close($false)
                    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($document) | Out-Null
                }
            }
        }
    }
    finally {
        if ($word) {
            $word.Quit()
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
        }
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}

function Convert-WithSoffice {
    param(
        [System.IO.FileInfo[]]$Files,
        [string]$TargetDir,
        [string]$SofficePath
    )

    foreach ($file in $Files) {
        Write-Info "Converting with LibreOffice/OpenOffice: $($file.FullName)"
        $arguments = @(
            "--headless",
            "--convert-to", "pdf",
            "--outdir", $TargetDir,
            $file.FullName
        )

        $process = Start-Process -FilePath $SofficePath -ArgumentList $arguments -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -eq 0) {
            $pdfPath = Join-Path $TargetDir ($file.BaseName + ".pdf")
            Write-Ok "Saved: $pdfPath"
        }
        else {
            Write-WarnMsg "Failed: $($file.FullName). ExitCode=$($process.ExitCode)"
        }
    }
}

$InputPath = $env:WORD2PDF_INPUT
$OutputDir = $env:WORD2PDF_OUTPUT
$Recurse = $env:WORD2PDF_RECURSE -eq "1"

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    throw "Input path is required."
}

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "Input path does not exist: $InputPath"
}

$resolvedInputPath = Resolve-FullPath $InputPath
$supportedExtensions = @(".doc", ".docx", ".docm", ".rtf", ".odt")
$files = @()

$item = Get-Item -LiteralPath $resolvedInputPath
if ($item.PSIsContainer) {
    $searchOption = if ($Recurse) { "AllDirectories" } else { "TopDirectoryOnly" }
    $files = [System.IO.Directory]::EnumerateFiles($item.FullName, "*.*", $searchOption) |
        Where-Object { $supportedExtensions -contains ([System.IO.Path]::GetExtension($_).ToLowerInvariant()) } |
        ForEach-Object { Get-Item -LiteralPath $_ }

    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        $OutputDir = Join-Path $item.FullName "pdf_output"
    }
}
else {
    if (-not ($supportedExtensions -contains $item.Extension.ToLowerInvariant())) {
        throw "Unsupported file type: $($item.Extension)"
    }
    $files = @($item)

    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        $OutputDir = $item.DirectoryName
    }
}

if (-not $files -or $files.Count -eq 0) {
    throw "No supported Word documents found."
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
    Write-Info "Creating output directory: $OutputDir"
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$resolvedOutputDir = Resolve-FullPath $OutputDir
Write-Info "Input: $resolvedInputPath"
Write-Info "Output: $resolvedOutputDir"
Write-Info "Files: $($files.Count)"
Write-Host ""

if (Test-WordAvailable) {
    Convert-WithWord -Files $files -TargetDir $resolvedOutputDir
}
else {
    $sofficePath = Get-SofficePath
    if ($sofficePath) {
        Convert-WithSoffice -Files $files -TargetDir $resolvedOutputDir -SofficePath $sofficePath
    }
    else {
        throw "No converter found. Please install Microsoft Word or LibreOffice, then try again."
    }
}

Write-Host ""
Write-Ok "Conversion finished."
