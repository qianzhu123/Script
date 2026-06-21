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

Assert-Contains 'Enter Word file or folder path:' 'The script must prompt for a file or folder.'
Assert-NotContains 'Enter output folder path' 'The output-folder prompt must be removed.'
Assert-NotContains 'include subfolders?' 'The recursion prompt must be removed.'
Assert-NotContains 'WORD2PDF_OUTPUT' 'The shared output environment variable must be removed.'
Assert-NotContains 'WORD2PDF_RECURSE' 'The recursion environment variable must be removed.'
Assert-Contains 'SearchOption]::AllDirectories' 'Folder discovery must always recurse.'
Assert-NotContains 'A folder path is required.' 'Supported file input must not be rejected.'
Assert-Contains '$files = @($item)' 'A supported file input must become a one-item conversion list.'
Assert-Contains 'Unsupported file type:' 'Unsupported file input must report its extension.'
Assert-Contains '$file.DirectoryName' 'Output paths must use each source file directory.'
Assert-Contains 'Remove-Item -LiteralPath $pdfPath -Force' 'An existing same-name PDF must be replaced explicitly.'
Assert-Contains '-Stream Zone.Identifier' 'Downloaded documents must be detected by their security stream.'
Assert-Contains 'Copy-Item -LiteralPath $File.FullName' 'A downloaded source must be copied before unblocking.'
Assert-Contains 'Unblock-File -LiteralPath $tempPath' 'Only the temporary copy must be unblocked.'
Assert-NotContains 'Unblock-File -LiteralPath $file.FullName' 'The original source security marker must remain intact.'
Assert-Contains '$word.Documents.Open($openPath' 'Word must open the selected original or temporary path.'
Assert-Contains 'Remove-Item -LiteralPath $openCopy.TempDir -Recurse -Force' 'Temporary files must be removed in cleanup.'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('word to pdf 中文 ' + [guid]::NewGuid())
$inputFile = Join-Path $tempRoot 'input.txt'
try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    [System.IO.File]::WriteAllText($inputFile, '"' + $tempRoot + '"' + "`r`n", [System.Text.UTF8Encoding]::new($false))
    $cmd = 'type "{0}" | "{1}"' -f $inputFile, $batPath
    $ErrorActionPreference = 'Continue'
    $output = & $env:ComSpec /d /c $cmd 2>&1 | Out-String
    $ErrorActionPreference = 'Stop'
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
