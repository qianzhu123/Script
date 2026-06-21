# Word to PDF File Input Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow `bat/word_to_pdf.bat` to accept either one supported document or one folder while preserving recursive folder conversion and same-directory PDF output.

**Architecture:** Keep the current BAT and embedded PowerShell structure. Change only the input classification boundary: a directory continues through recursive enumeration, while a supported file is wrapped in a one-item array and sent through the existing converter functions.

**Tech Stack:** Windows Batch, Windows PowerShell 5.1-compatible PowerShell, Microsoft Word COM, LibreOffice/OpenOffice CLI

---

## File structure

- Modify `tests/word_to_pdf_folder.Tests.ps1`: replace the obsolete file-rejection assertion with file-acceptance and unsupported-extension assertions.
- Modify `bat/word_to_pdf.bat`: update the prompt/error copy and branch between file and directory input.

### Task 1: Add a failing file-input regression

**Files:**
- Modify: `tests/word_to_pdf_folder.Tests.ps1:15-23`
- Test: `tests/word_to_pdf_folder.Tests.ps1`

- [ ] **Step 1: Replace the obsolete source assertions**

Replace the folder-only prompt and rejection assertions with:

```powershell
Assert-Contains 'Enter Word file or folder path:' 'The script must prompt for a file or folder.'
Assert-NotContains 'A folder path is required.' 'Supported file input must not be rejected.'
Assert-Contains '$files = @($item)' 'A supported file input must become a one-item conversion list.'
Assert-Contains 'Unsupported file type:' 'Unsupported file input must report its extension.'
```

Keep the existing assertions for recursive folder enumeration, same-directory output, overwrite behavior, and removed output/recursion prompts.

- [ ] **Step 2: Run the regression test and verify RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\word_to_pdf_folder.Tests.ps1
```

Expected: exit code `1` with `The script must prompt for a file or folder.` because the production script still has a folder-only contract.

- [ ] **Step 3: Commit the failing regression**

```powershell
git add -- tests/word_to_pdf_folder.Tests.ps1
git commit -m "test: require direct word file input"
```

### Task 2: Accept supported files without changing conversion output

**Files:**
- Modify: `bat/word_to_pdf.bat:10-24`
- Modify: `bat/word_to_pdf.bat:178-204`
- Test: `tests/word_to_pdf_folder.Tests.ps1`

- [ ] **Step 1: Update the user-facing input contract**

Use this exact BAT interaction text:

```bat
echo Usage:
echo   Enter a Word file or a folder containing Word documents.
echo   Folder input includes all subfolders automatically.
echo   Each PDF is saved beside its source document.
echo.

set "INPUT_PATH="
set /p "INPUT_PATH=Enter Word file or folder path: "

if not defined INPUT_PATH (
    echo [ERROR] File or folder path is required.
    echo.
    pause
    exit /b 1
)
```

- [ ] **Step 2: Replace directory-only validation with file-or-folder classification**

Use this complete classification block after resolving `$InputPath`:

```powershell
$resolvedInputPath = Resolve-FullPath $InputPath
$item = Get-Item -LiteralPath $resolvedInputPath
$supportedExtensions = @('.doc', '.docx', '.docm', '.rtf', '.odt')

if ($item.PSIsContainer) {
    $files = [System.IO.Directory]::EnumerateFiles(
        $item.FullName,
        '*.*',
        [System.IO.SearchOption]::AllDirectories
    ) |
        Where-Object { $supportedExtensions -contains ([System.IO.Path]::GetExtension($_).ToLowerInvariant()) } |
        ForEach-Object { Get-Item -LiteralPath $_ }
}
else {
    if (-not ($supportedExtensions -contains $item.Extension.ToLowerInvariant())) {
        throw "Unsupported file type: $($item.Extension)"
    }
    $files = @($item)
}
```

Change the surrounding empty/missing input messages to:

```powershell
if ([string]::IsNullOrWhiteSpace($InputPath)) {
    throw 'File or folder path is required.'
}

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "File or folder does not exist: $InputPath"
}
```

Do not alter `Convert-WithWord` or `Convert-WithSoffice`; both already derive the PDF path from `$file.DirectoryName`.

- [ ] **Step 3: Run the regression test and verify GREEN**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\word_to_pdf_folder.Tests.ps1
```

Expected: exit code `0` and `word_to_pdf folder regression tests passed.`

- [ ] **Step 4: Parse the embedded PowerShell payload**

Run:

```powershell
$lines = Get-Content -LiteralPath bat\word_to_pdf.bat -Encoding UTF8
$idx = [Array]::IndexOf($lines, '# POWERSHELL_PAYLOAD')
$code = $lines[($idx + 1)..($lines.Count - 1)] -join [Environment]::NewLine
[scriptblock]::Create($code) | Out-Null
Write-Host 'Embedded PowerShell syntax passed.'
```

Expected: exit code `0` and `Embedded PowerShell syntax passed.`

- [ ] **Step 5: Commit the fix**

```powershell
git add -- bat/word_to_pdf.bat
git commit -m "fix: accept direct word file input"
```

### Task 3: Final scoped verification

**Files:**
- Verify: `bat/word_to_pdf.bat`
- Verify: `tests/word_to_pdf_folder.Tests.ps1`

- [ ] **Step 1: Re-run the complete regression test**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\word_to_pdf_folder.Tests.ps1
```

Expected: exit code `0` with no CMD parse error.

- [ ] **Step 2: Check the two-file diff**

```powershell
git diff --check HEAD~2..HEAD -- bat/word_to_pdf.bat tests/word_to_pdf_folder.Tests.ps1
git diff --stat HEAD~2..HEAD -- bat/word_to_pdf.bat tests/word_to_pdf_folder.Tests.ps1
```

Expected: no whitespace errors; changes are limited to the input regression and file-or-folder classification.

- [ ] **Step 3: Confirm the regression test starts no Word process**

```powershell
$before = @(Get-Process WINWORD -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
powershell -NoProfile -ExecutionPolicy Bypass -File tests\word_to_pdf_folder.Tests.ps1
$after = @(Get-Process WINWORD -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
@($after | Where-Object { $_ -notin $before }).Count
```

Expected: `0` because the runtime fixture remains an empty folder and source assertions do not invoke conversion.
