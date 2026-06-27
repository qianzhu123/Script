<#
.SYNOPSIS
Replace one page in a Word document with a page from another Word document.

.DESCRIPTION
Copies the target document to an output file, then uses Microsoft Word COM automation
to replace TargetPage in the copied target document with SourcePage from the source document.

Requirements:
- Windows with Microsoft Word installed.
- Supported extensions: .doc, .docx, .docm, .rtf.

Usage:
  .\replace_word_page.ps1 -SourcePath "D:\template.docx" -SourcePage 2 -TargetPath "D:\target.docx" -TargetPage 5
  .\replace_word_page.ps1 -SourcePath "D:\template.docx" -SourcePage 2 -TargetPath "D:\target.docx" -TargetPage 5 -OutputPath "D:\target_replaced.docx"

Default output:
- If OutputPath is empty, saves next to TargetPath as target_replaced.ext.
- If OutputPath is a directory, saves inside that directory as target_replaced.ext.
#>

param(
    [string]$SourcePath = "",
    [int]$SourcePage = 0,
    [string]$TargetPath = "",
    [int]$TargetPage = 0,
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

try {
    [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
}
catch {
}

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

function Test-SupportedWordFile {
    param([string]$Path)
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    return @(".doc", ".docx", ".docm", ".rtf") -contains $extension
}

function Normalize-InputPath {
    param([string]$Path)
    return ($Path -as [string]).Trim().Trim('"')
}

function Get-DefaultOutputPath {
    param(
        [string]$Path,
        [string]$Directory = ""
    )

    if ([string]::IsNullOrWhiteSpace($Directory)) {
        $Directory = [System.IO.Path]::GetDirectoryName($Path)
    }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $extension = [System.IO.Path]::GetExtension($Path)
    $candidate = Join-Path $Directory ($baseName + "_replaced" + $extension)
    $index = 1

    while (Test-Path -LiteralPath $candidate) {
        $candidate = Join-Path $Directory ("{0}_replaced_{1}{2}" -f $baseName, $index, $extension)
        $index++
    }

    return $candidate
}

function Get-PageRange {
    param(
        $Document,
        [int]$PageNumber
    )

    $wdGoToPage = 1
    $wdGoToAbsolute = 1
    $wdStatisticPages = 2
    $wdCharacter = 1

    $pageCount = $Document.ComputeStatistics($wdStatisticPages)
    if ($PageNumber -lt 1 -or $PageNumber -gt $pageCount) {
        throw "Page $PageNumber is out of range. Document has $pageCount page(s)."
    }

    $startRange = $Document.GoTo($wdGoToPage, $wdGoToAbsolute, $PageNumber)
    $start = $startRange.Start

    if ($PageNumber -lt $pageCount) {
        $nextRange = $Document.GoTo($wdGoToPage, $wdGoToAbsolute, $PageNumber + 1)
        $end = $nextRange.Start
    }
    else {
        $end = $Document.Content.End
    }

    if ($end -gt $start) {
        $candidate = $Document.Range($end - 1, $end)
        if ($candidate.Text -eq "`f") {
            $end--
        }
    }

    return $Document.Range($start, $end)
}

function Test-WordAvailable {
    $word = $null
    try {
        $word = New-Object -ComObject Word.Application
        return $true
    }
    catch {
        return $false
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

Write-Host "========================================"
Write-Host "Word Page Replacer"
Write-Host "========================================"
Write-Host ""

if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Read-Host "Enter source/template Word path"
}

if ($SourcePage -le 0) {
    $SourcePage = [int](Read-Host "Enter source/template page number")
}

if ([string]::IsNullOrWhiteSpace($TargetPath)) {
    $TargetPath = Read-Host "Enter target Word path"
}

if ($TargetPage -le 0) {
    $TargetPage = [int](Read-Host "Enter target page number to replace")
}

$SourcePath = Normalize-InputPath $SourcePath
$TargetPath = Normalize-InputPath $TargetPath

if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    throw "SourcePath is required."
}

if ([string]::IsNullOrWhiteSpace($TargetPath)) {
    throw "TargetPath is required."
}

if (-not (Test-Path -LiteralPath $SourcePath)) {
    throw "Source file does not exist: $SourcePath"
}

if (-not (Test-Path -LiteralPath $TargetPath)) {
    throw "Target file does not exist: $TargetPath"
}

$resolvedSourcePath = Resolve-FullPath $SourcePath
$resolvedTargetPath = Resolve-FullPath $TargetPath

if (-not (Test-SupportedWordFile $resolvedSourcePath)) {
    throw "Unsupported source file type: $resolvedSourcePath"
}

if (-not (Test-SupportedWordFile $resolvedTargetPath)) {
    throw "Unsupported target file type: $resolvedTargetPath"
}

if ($SourcePage -le 0) {
    throw "SourcePage must be greater than 0."
}

if ($TargetPage -le 0) {
    throw "TargetPage must be greater than 0."
}

$normalizedOutputPath = Normalize-InputPath $OutputPath
if ([string]::IsNullOrWhiteSpace($normalizedOutputPath) -or $normalizedOutputPath -eq "=" -or $normalizedOutputPath.Trim("=") -eq "") {
    $OutputPath = ""
}
else {
    $OutputPath = $normalizedOutputPath
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Get-DefaultOutputPath $resolvedTargetPath
}
elseif ((Test-Path -LiteralPath $OutputPath -PathType Container) -or $OutputPath.EndsWith([System.IO.Path]::DirectorySeparatorChar) -or $OutputPath.EndsWith([System.IO.Path]::AltDirectorySeparatorChar)) {
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $OutputPath = Get-DefaultOutputPath -Path $resolvedTargetPath -Directory ([System.IO.Path]::GetFullPath($OutputPath))
}

$outputDirectory = [System.IO.Path]::GetDirectoryName($OutputPath)
if ([string]::IsNullOrWhiteSpace($outputDirectory)) {
    $outputDirectory = (Get-Location).Path
    $OutputPath = Join-Path $outputDirectory $OutputPath
}

if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)

if ($resolvedSourcePath -eq $resolvedOutputPath) {
    throw "OutputPath cannot be the same as SourcePath."
}

if ($resolvedTargetPath -eq $resolvedOutputPath) {
    throw "OutputPath cannot be the same as TargetPath. Provide a different file path or an output directory."
}

Write-Info "Source: $resolvedSourcePath"
Write-Info "Source page: $SourcePage"
Write-Info "Target: $resolvedTargetPath"
Write-Info "Target page: $TargetPage"
Write-Info "Output: $resolvedOutputPath"
Write-Host ""

if (-not (Test-WordAvailable)) {
    throw "Microsoft Word is required but was not detected."
}

Copy-Item -LiteralPath $resolvedTargetPath -Destination $resolvedOutputPath -Force

$word = $null
$sourceDocument = $null
$targetDocument = $null
$sourceRange = $null
$targetRange = $null

try {
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    $word.DisplayAlerts = 0

    Write-Info "Opening documents..."
    $sourceDocument = $word.Documents.Open($resolvedSourcePath, $false, $true)
    $targetDocument = $word.Documents.Open($resolvedOutputPath, $false, $false)

    Write-Info "Copying source page..."
    $sourceRange = Get-PageRange -Document $sourceDocument -PageNumber $SourcePage
    $sourceRange.Copy() | Out-Null

    Write-Info "Replacing target page..."
    $targetRange = Get-PageRange -Document $targetDocument -PageNumber $TargetPage
    $targetRange.Delete() | Out-Null
    $targetRange.PasteAndFormat(16) | Out-Null

    $targetDocument.Save()
    Write-Ok "Saved: $resolvedOutputPath"
}
finally {
    if ($targetDocument) {
        $targetDocument.Close($true)
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($targetDocument) | Out-Null
    }

    if ($sourceDocument) {
        $sourceDocument.Close($false)
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($sourceDocument) | Out-Null
    }

    foreach ($item in @($targetRange, $sourceRange)) {
        if ($item) {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($item) | Out-Null
        }
    }

    if ($word) {
        $word.Quit()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
    }

    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}

Write-Host ""
Write-WarnMsg "Word pages are layout-dependent. Please review the output if the document has complex headers, footers, sections, or floating objects."
Write-Ok "Done."
