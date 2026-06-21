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
    param([System.IO.FileInfo[]]$Files)

    $word = $null
    try {
        $word = New-Object -ComObject Word.Application
        $word.Visible = $false
        $word.DisplayAlerts = 0

        foreach ($file in $Files) {
            $pdfPath = Join-Path $file.DirectoryName ($file.BaseName + ".pdf")
            Write-Info "Converting with Microsoft Word: $($file.FullName)"
            Remove-Item -LiteralPath $pdfPath -Force -ErrorAction SilentlyContinue

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
        [string]$SofficePath
    )

    foreach ($file in $Files) {
        Write-Info "Converting with LibreOffice/OpenOffice: $($file.FullName)"
        $targetDir = $file.DirectoryName
        $pdfPath = Join-Path $targetDir ($file.BaseName + ".pdf")
        Remove-Item -LiteralPath $pdfPath -Force -ErrorAction SilentlyContinue
        $arguments = @(
            "--headless",
            "--convert-to", "pdf",
            "--outdir", $targetDir,
            $file.FullName
        )

        $process = Start-Process -FilePath $SofficePath -ArgumentList $arguments -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -eq 0) {
            Write-Ok "Saved: $pdfPath"
        }
        else {
            Write-WarnMsg "Failed: $($file.FullName). ExitCode=$($process.ExitCode)"
        }
    }
}

$InputPath = $env:WORD2PDF_INPUT

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    throw "Folder path is required."
}

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "Folder does not exist: $InputPath"
}

$resolvedInputPath = Resolve-FullPath $InputPath
$item = Get-Item -LiteralPath $resolvedInputPath
if (-not $item.PSIsContainer) {
    throw "A folder path is required. Received: $resolvedInputPath"
}

$supportedExtensions = @(".doc", ".docx", ".docm", ".rtf", ".odt")
$files = [System.IO.Directory]::EnumerateFiles(
    $item.FullName,
    "*.*",
    [System.IO.SearchOption]::AllDirectories
) |
    Where-Object { $supportedExtensions -contains ([System.IO.Path]::GetExtension($_).ToLowerInvariant()) } |
    ForEach-Object { Get-Item -LiteralPath $_ }

if (-not $files -or $files.Count -eq 0) {
    throw "No supported Word documents found."
}

Write-Info "Input: $resolvedInputPath"
Write-Info "Files: $($files.Count)"
Write-Host ""

if (Test-WordAvailable) {
    Convert-WithWord -Files $files
}
else {
    $sofficePath = Get-SofficePath
    if ($sofficePath) {
        Convert-WithSoffice -Files $files -SofficePath $sofficePath
    }
    else {
        throw "No converter found. Please install Microsoft Word or LibreOffice, then try again."
    }
}

Write-Host ""
Write-Ok "Conversion finished."
