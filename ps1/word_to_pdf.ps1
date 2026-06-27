<#
.SYNOPSIS
Convert Word documents to PDF.

.DESCRIPTION
Supports converting a single Word document or all Word documents in a directory.
Preferred converter order:
1. Microsoft Word COM automation, if Microsoft Word is installed.
2. LibreOffice / OpenOffice command line, if soffice.exe is available in PATH or common install paths.

Supported input extensions: .doc, .docx, .docm, .rtf, .odt
#>

param(
    [string]$InputPath = "",
    [string]$OutputDir = "",
    [switch]$Recurse
)

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

Write-Host "========================================"
Write-Host "Word to PDF Converter"
Write-Host "========================================"
Write-Host ""

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    $InputPath = Read-Host "Enter a Word file path or a directory path"
}

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
