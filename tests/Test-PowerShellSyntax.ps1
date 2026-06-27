$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$failures = New-Object System.Collections.Generic.List[string]

Get-ChildItem -LiteralPath (Join-Path $projectRoot 'ps1') -Filter '*.ps1' -File | ForEach-Object {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $_.FullName,
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null

    foreach ($parseError in @($errors)) {
        $failures.Add(
            ('{0}:{1}: {2}' -f $_.Name, $parseError.Extent.StartLineNumber, $parseError.Message)
        )
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host '[PASS] All PowerShell scripts parse successfully.'
