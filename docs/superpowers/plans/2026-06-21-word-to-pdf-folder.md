# Word to PDF Folder Conversion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change `bat/word_to_pdf.bat` to accept one folder, recursively convert supported documents, and save every PDF beside its source document.

**Architecture:** Keep the existing self-contained BAT plus embedded PowerShell structure. Simplify the BAT input contract to one environment variable, then make the PowerShell payload directory-only, always recursive, and responsible for deriving each output directory from the current source file.

**Tech Stack:** Windows Batch, Windows PowerShell 5.1-compatible PowerShell, Microsoft Word COM, LibreOffice/OpenOffice CLI

---

## File structure

- Modify `bat/word_to_pdf.bat`: user prompts, environment boundary, recursive discovery, and per-document output paths.
- Create `tests/word_to_pdf_folder.Tests.ps1`: dependency-free regression checks for the BAT contract and a real CMD parsing check using a quoted Chinese folder path.

### Task 1: Add failing folder-workflow regression tests

**Files:**
- Create: `tests/word_to_pdf_folder.Tests.ps1`
- Test: `tests/word_to_pdf_folder.Tests.ps1`

- [ ] **Step 1: Write the failing regression script**

Create a PowerShell script that reads `bat/word_to_pdf.bat`, collects assertion failures, and verifies the required source contract:

```powershell
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$batPath = Join-Path $repoRoot 'bat\word_to_pdf.bat'
$source = Get-Content -Raw -LiteralPath $batPath
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contains([string]$Needle, [string]$Message) {
    if (-not $source.Contains($Needle)) { $failures.Add($Message) }
}

function Assert-NotContains([string]$Needle, [string]$Message) {
    if ($source.Contains($Needle)) { $failures.Add($Message) }
}

Assert-Contains 'Enter Word document folder path:' 'The script must have one folder prompt.'
Assert-NotContains 'Enter output folder path' 'The output-folder prompt must be removed.'
Assert-NotContains 'include subfolders?' 'The recursion prompt must be removed.'
Assert-NotContains 'WORD2PDF_OUTPUT' 'The shared output environment variable must be removed.'
Assert-NotContains 'WORD2PDF_RECURSE' 'The recursion environment variable must be removed.'
Assert-Contains 'SearchOption]::AllDirectories' 'Folder discovery must always recurse.'
Assert-Contains 'A folder path is required.' 'File input must be rejected explicitly.'
Assert-Contains '$file.DirectoryName' 'Output paths must use each source file directory.'
Assert-Contains 'Remove-Item -LiteralPath $pdfPath -Force' 'An existing same-name PDF must be replaced explicitly.'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('word to pdf 中文 ' + [guid]::NewGuid())
$inputFile = Join-Path $tempRoot 'input.txt'
try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    [System.IO.File]::WriteAllText($inputFile, '"' + $tempRoot + '"' + "`r`n", [System.Text.UTF8Encoding]::new($false))
    $cmd = 'type "{0}" | "{1}"' -f $inputFile, $batPath
    $output = & $env:ComSpec /d /c $cmd 2>&1 | Out-String
    if ($output.Contains('unexpected at this time')) {
        $failures.Add('Quoted folder input still breaks CMD parsing.')
    }
    if (-not $output.Contains('No supported Word documents found.')) {
        $failures.Add('Quoted Chinese folder input did not reach folder discovery.')
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'word_to_pdf folder regression tests passed.'
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\word_to_pdf_folder.Tests.ps1
```

Expected: exit code `1`, with failures for the old output prompt, recursion prompt, and missing folder-only behavior.

- [ ] **Step 3: Commit the failing test**

```powershell
git add -- tests/word_to_pdf_folder.Tests.ps1
git commit -m "test: define recursive word folder conversion behavior"
```

### Task 2: Simplify the BAT interaction and environment contract

**Files:**
- Modify: `bat/word_to_pdf.bat:8-43`
- Test: `tests/word_to_pdf_folder.Tests.ps1`

- [ ] **Step 1: Replace the usage text and prompts**

Use one folder prompt and retain quote normalization:

```bat
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
```

Delete `OUTPUT_DIR`, `RECURSE_CHOICE`, `WORD2PDF_OUTPUT`, and `WORD2PDF_RECURSE` handling.

- [ ] **Step 2: Run the regression script and confirm remaining failures are payload-only**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\word_to_pdf_folder.Tests.ps1
```

Expected: exit code `1`; prompt/environment assertions pass, while recursive discovery and per-file output assertions still fail.

- [ ] **Step 3: Commit the interaction change**

```powershell
git add -- bat/word_to_pdf.bat
git commit -m "refactor: reduce word converter to one folder prompt"
```

### Task 3: Implement recursive discovery and same-folder PDF output

**Files:**
- Modify: `bat/word_to_pdf.bat:89-205`
- Test: `tests/word_to_pdf_folder.Tests.ps1`

- [ ] **Step 1: Make Word conversion derive each target path**

Remove `TargetDir` from `Convert-WithWord` and derive the PDF path inside the loop:

```powershell
function Convert-WithWord {
    param([System.IO.FileInfo[]]$Files)

    $word = $null
    try {
        $word = New-Object -ComObject Word.Application
        $word.Visible = $false
        $word.DisplayAlerts = 0

        foreach ($file in $Files) {
            $pdfPath = Join-Path $file.DirectoryName ($file.BaseName + '.pdf')
            Write-Info "Converting with Microsoft Word: $($file.FullName)"
            Remove-Item -LiteralPath $pdfPath -Force -ErrorAction SilentlyContinue

            $document = $null
            try {
                $document = $word.Documents.Open($file.FullName, $false, $true)
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
```

- [ ] **Step 2: Make LibreOffice conversion derive each target directory**

Remove `TargetDir` from `Convert-WithSoffice` and use the source directory for both `--outdir` and success logging:

```powershell
function Convert-WithSoffice {
    param(
        [System.IO.FileInfo[]]$Files,
        [string]$SofficePath
    )

    foreach ($file in $Files) {
        $targetDir = $file.DirectoryName
        $pdfPath = Join-Path $targetDir ($file.BaseName + '.pdf')
        Remove-Item -LiteralPath $pdfPath -Force -ErrorAction SilentlyContinue
        $arguments = @(
            '--headless',
            '--convert-to', 'pdf',
            '--outdir', $targetDir,
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
```

- [ ] **Step 3: Enforce folder input and always recurse**

Replace shared output and recursion state with directory-only discovery:

```powershell
$InputPath = $env:WORD2PDF_INPUT

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    throw 'Folder path is required.'
}

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "Folder does not exist: $InputPath"
}

$resolvedInputPath = Resolve-FullPath $InputPath
$item = Get-Item -LiteralPath $resolvedInputPath
if (-not $item.PSIsContainer) {
    throw "A folder path is required: $resolvedInputPath"
}

$supportedExtensions = @('.doc', '.docx', '.docm', '.rtf', '.odt')
$files = [System.IO.Directory]::EnumerateFiles(
    $item.FullName,
    '*.*',
    [System.IO.SearchOption]::AllDirectories
) |
    Where-Object { $supportedExtensions -contains ([System.IO.Path]::GetExtension($_).ToLowerInvariant()) } |
    ForEach-Object { Get-Item -LiteralPath $_ }

if (-not $files -or $files.Count -eq 0) {
    throw 'No supported Word documents found.'
}
```

Update converter calls to omit a shared target directory:

```powershell
if (Test-WordAvailable) {
    Convert-WithWord -Files $files
}
else {
    $sofficePath = Get-SofficePath
    if ($sofficePath) {
        Convert-WithSoffice -Files $files -SofficePath $sofficePath
    }
    else {
        throw 'No converter found. Please install Microsoft Word or LibreOffice, then try again.'
    }
}
```

- [ ] **Step 4: Run the regression script and verify GREEN**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\word_to_pdf_folder.Tests.ps1
```

Expected: exit code `0` and `word_to_pdf folder regression tests passed.`

- [ ] **Step 5: Parse the embedded PowerShell payload**

Run:

```powershell
$lines = Get-Content -LiteralPath bat\word_to_pdf.bat -Encoding UTF8
$idx = [Array]::IndexOf($lines, '# POWERSHELL_PAYLOAD')
$code = $lines[($idx + 1)..($lines.Count - 1)] -join [Environment]::NewLine
[scriptblock]::Create($code) | Out-Null
Write-Host 'Embedded PowerShell syntax passed.'
```

Expected: exit code `0` and `Embedded PowerShell syntax passed.`

- [ ] **Step 6: Commit the payload change**

```powershell
git add -- bat/word_to_pdf.bat
git commit -m "feat: save recursively converted PDFs beside source documents"
```

### Task 4: Final verification

**Files:**
- Verify: `bat/word_to_pdf.bat`
- Verify: `tests/word_to_pdf_folder.Tests.ps1`

- [ ] **Step 1: Run the complete regression test from the repository root**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\word_to_pdf_folder.Tests.ps1
```

Expected: exit code `0`, no CMD parse error, and one passing summary line.

- [ ] **Step 2: Inspect the scoped diff**

```powershell
git diff HEAD~2 -- bat/word_to_pdf.bat tests/word_to_pdf_folder.Tests.ps1
```

Expected: only the approved interaction, recursive enumeration, per-document output path, and regression coverage changes appear.

- [ ] **Step 3: Confirm no test Word process remains**

```powershell
Get-Process WINWORD -ErrorAction SilentlyContinue | Select-Object Id, StartTime, MainWindowTitle
```

Expected: the regression test starts no Word process because its temporary folder contains no supported documents.
