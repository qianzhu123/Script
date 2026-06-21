# Word Download Security Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent hidden Word automation from hanging on downloaded documents while preserving the original document and its security marker.

**Architecture:** Detect `Zone.Identifier` before Word opens each source. Marked documents are copied into a unique temporary directory, the temporary copy is unblocked and opened, and the PDF path continues to derive from the original source; cleanup runs in `finally` for both success and failure.

**Tech Stack:** Windows Batch, Windows PowerShell 5.1-compatible PowerShell, NTFS alternate data streams, Microsoft Word COM

---

## File structure

- Modify `tests/word_to_pdf_folder.Tests.ps1`: add source-contract regressions for safe temporary-copy handling.
- Modify `bat/word_to_pdf.bat`: add one helper for creating an unblocked copy and integrate it into Word conversion cleanup.

### Task 1: Add failing downloaded-document regressions

**Files:**
- Modify: `tests/word_to_pdf_folder.Tests.ps1:15-26`
- Test: `tests/word_to_pdf_folder.Tests.ps1`

- [ ] **Step 1: Add the security-handling assertions**

Append these assertions after the existing output-path assertions:

```powershell
Assert-Contains '-Stream Zone.Identifier' 'Downloaded documents must be detected by their security stream.'
Assert-Contains 'Copy-Item -LiteralPath $File.FullName' 'A downloaded source must be copied before unblocking.'
Assert-Contains 'Unblock-File -LiteralPath $tempPath' 'Only the temporary copy must be unblocked.'
Assert-NotContains 'Unblock-File -LiteralPath $file.FullName' 'The original source security marker must remain intact.'
Assert-Contains '$word.Documents.Open($openPath' 'Word must open the selected original or temporary path.'
Assert-Contains 'Remove-Item -LiteralPath $openCopy.TempDir -Recurse -Force' 'Temporary files must be removed in cleanup.'
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\word_to_pdf_folder.Tests.ps1
```

Expected: exit code `1` with `Downloaded documents must be detected by their security stream.`

- [ ] **Step 3: Commit the failing regression**

```powershell
git add -- tests/word_to_pdf_folder.Tests.ps1
git commit -m "test: require safe handling for downloaded word files"
```

### Task 2: Open a safe temporary copy for downloaded documents

**Files:**
- Modify: `bat/word_to_pdf.bat:105-150`
- Test: `tests/word_to_pdf_folder.Tests.ps1`

- [ ] **Step 1: Add the temporary-copy helper before `Convert-WithWord`**

```powershell
function New-UnblockedWordCopy {
    param([System.IO.FileInfo]$File)

    $zoneStream = Get-Item -LiteralPath $File.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue
    if (-not $zoneStream) {
        return $null
    }

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("word_to_pdf_" + [guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        $tempPath = Join-Path $tempDir $File.Name
        Copy-Item -LiteralPath $File.FullName -Destination $tempPath -Force
        Unblock-File -LiteralPath $tempPath
        Write-Info "Using a safe temporary copy for downloaded document: $($File.FullName)"
        return [pscustomobject]@{
            Path = $tempPath
            TempDir = $tempDir
        }
    }
    catch {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}
```

- [ ] **Step 2: Replace `Convert-WithWord` with the integrated cleanup version**

```powershell
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
            $openCopy = $null
            try {
                $openCopy = New-UnblockedWordCopy -File $file
                $openPath = if ($openCopy) { $openCopy.Path } else { $file.FullName }
                $document = $word.Documents.Open($openPath, $false, $true)
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
                if ($openCopy) {
                    Remove-Item -LiteralPath $openCopy.TempDir -Recurse -Force -ErrorAction SilentlyContinue
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

- [ ] **Step 3: Run regression and syntax tests**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\word_to_pdf_folder.Tests.ps1
$lines = Get-Content -LiteralPath bat\word_to_pdf.bat -Encoding UTF8
$idx = [Array]::IndexOf($lines, '# POWERSHELL_PAYLOAD')
$code = $lines[($idx + 1)..($lines.Count - 1)] -join [Environment]::NewLine
[scriptblock]::Create($code) | Out-Null
Write-Host 'Embedded PowerShell syntax passed.'
```

Expected: exit code `0`, regression pass summary, and `Embedded PowerShell syntax passed.`

- [ ] **Step 4: Commit the implementation**

```powershell
git add -- bat/word_to_pdf.bat
git commit -m "fix: convert downloaded word files through safe copies"
```

### Task 3: End-to-end verification with the reported document

**Files:**
- Verify: `bat/word_to_pdf.bat`
- Verify: `tests/word_to_pdf_folder.Tests.ps1`
- Input: `C:\Users\Light\Downloads\241040100419 张宁.doc`
- Output: `C:\Users\Light\Downloads\241040100419 张宁.pdf`

- [ ] **Step 1: Record the original security stream and Word process IDs**

```powershell
$source = 'C:\Users\Light\Downloads\241040100419 张宁.doc'
$zoneBefore = Get-Content -LiteralPath $source -Stream Zone.Identifier -Raw
$wordBefore = @(Get-Process WINWORD -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
```

- [ ] **Step 2: Run the BAT with a 60-second outer timeout**

Create a CRLF input file containing the quoted source path, start `cmd.exe` hidden with `type <input> | bat\word_to_pdf.bat`, and wait at most 60 seconds. If it exceeds the limit, stop only the newly created Word process and report failure.

```powershell
$inputFile = Join-Path $env:TEMP 'word_to_pdf_e2e_input.txt'
[System.IO.File]::WriteAllText($inputFile, '"' + $source + '"' + "`r`n", [System.Text.UTF8Encoding]::new($false))
$command = 'type "{0}" | "{1}"' -f $inputFile, (Resolve-Path 'bat\word_to_pdf.bat')
$process = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d', '/c', $command) -WindowStyle Hidden -PassThru
if (-not $process.WaitForExit(60000)) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    $newWord = @(Get-Process WINWORD -ErrorAction SilentlyContinue | Where-Object { $_.Id -notin $wordBefore })
    $newWord | Stop-Process -Force -ErrorAction SilentlyContinue
    throw 'End-to-end conversion exceeded 60 seconds.'
}
Remove-Item -LiteralPath $inputFile -Force -ErrorAction SilentlyContinue
```

- [ ] **Step 3: Verify output, source preservation, cleanup, and no leaked Word process**

```powershell
$output = 'C:\Users\Light\Downloads\241040100419 张宁.pdf'
if (-not (Test-Path -LiteralPath $output)) { throw 'Expected PDF was not created.' }
if ((Get-Item -LiteralPath $output).Length -le 0) { throw 'Created PDF is empty.' }
$zoneAfter = Get-Content -LiteralPath $source -Stream Zone.Identifier -Raw
if ($zoneAfter -ne $zoneBefore) { throw 'Original Zone.Identifier changed.' }
$tempLeaks = @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Directory -Filter 'word_to_pdf_*' -ErrorAction SilentlyContinue)
if ($tempLeaks.Count -gt 0) { throw "Temporary directories leaked: $($tempLeaks.FullName -join ', ')" }
$newWord = @(Get-Process WINWORD -ErrorAction SilentlyContinue | Where-Object { $_.Id -notin $wordBefore })
if ($newWord.Count -gt 0) { throw "Word processes leaked: $($newWord.Id -join ', ')" }
Write-Host "E2E PDF bytes: $((Get-Item -LiteralPath $output).Length)"
```

- [ ] **Step 4: Run the final scoped diff checks**

```powershell
git diff --check HEAD~2..HEAD -- bat/word_to_pdf.bat tests/word_to_pdf_folder.Tests.ps1
git diff --stat HEAD~2..HEAD -- bat/word_to_pdf.bat tests/word_to_pdf_folder.Tests.ps1
```

Expected: no whitespace errors and only the test assertions plus safe-copy implementation.
