[CmdletBinding()]
param(
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"

$OpenCodeConfigDirectory = Join-Path "C:\Users\Light" ".config\opencode"
$ConfigPath = Join-Path $OpenCodeConfigDirectory "opencode.jsonc"
$ApiKeyPattern = '(?m)(?<prefix>^[ \t]*"apiKey"[ \t]*:[ \t]*)(?<value>"(?:\\.|[^"\\\r\n])*")'
$ApiKeyRegex = [regex]$ApiKeyPattern

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Read-Utf8Config([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Config file not found: $Path"
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF
    $offset = 0
    if ($hasBom) {
        $offset = 3
    }

    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    try {
        $text = $utf8.GetString($bytes, $offset, $bytes.Length - $offset)
    }
    catch {
        throw "Config file must use valid UTF-8 encoding."
    }

    return [PSCustomObject]@{
        Text   = $text
        HasBom = $hasBom
    }
}

function Get-ApiKeyMatch([string]$Text) {
    $matches = $ApiKeyRegex.Matches($Text)
    if ($matches.Count -ne 1) {
        throw "Expected exactly one apiKey field, but found $($matches.Count). No changes were made."
    }

    return $matches[0]
}

function Get-TokenFingerprint([string]$Token) {
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Token))
        return ([System.BitConverter]::ToString($hash, 0, 6) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Read-HiddenToken {
    $secureToken = Read-Host "Enter the new token (input is hidden)" -AsSecureString
    $pointer = [System.IntPtr]::Zero
    try {
        $pointer = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        if ($pointer -ne [System.IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        }
        if ($null -ne $secureToken) {
            $secureToken.Dispose()
        }
    }
}

function Test-ConfigWithOpenCode([string]$Path) {
    if ($null -eq (Get-Command opencode -ErrorAction SilentlyContinue)) {
        throw "The opencode command was not found in PATH."
    }

    $hadCustomConfig = Test-Path Env:OPENCODE_CONFIG
    $previousCustomConfig = $env:OPENCODE_CONFIG
    try {
        $env:OPENCODE_CONFIG = $Path
        & opencode debug config *> $null
        if ($LASTEXITCODE -ne 0) {
            throw "OpenCode rejected the updated configuration."
        }
    }
    finally {
        if ($hadCustomConfig) {
            $env:OPENCODE_CONFIG = $previousCustomConfig
        }
        else {
            Remove-Item Env:OPENCODE_CONFIG -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-TokenSwitch {
    Write-Host "`nOpenCode token switch" -ForegroundColor White
    Write-Info "Config: $ConfigPath"

    $config = Read-Utf8Config -Path $ConfigPath
    $apiKeyMatch = Get-ApiKeyMatch -Text $config.Text
    try {
        $currentToken = ConvertFrom-Json -InputObject $apiKeyMatch.Groups['value'].Value
    }
    catch {
        throw "The existing apiKey value is not a valid JSON string."
    }

    Write-Info "Current token: length=$($currentToken.Length), sha256=$(Get-TokenFingerprint -Token $currentToken)"

    if ($CheckOnly) {
        Test-ConfigWithOpenCode -Path $ConfigPath
        Write-Ok "The target field and OpenCode configuration are valid."
        return
    }

    $newToken = $null
    $tempPath = $null
    $backupPath = $null
    try {
        $newToken = Read-HiddenToken
        if ([string]::IsNullOrWhiteSpace($newToken)) {
            throw "Token cannot be empty."
        }
        if ($newToken -match '\s') {
            throw "Token cannot contain whitespace."
        }
        if ([string]::Equals($currentToken, $newToken, [System.StringComparison]::Ordinal)) {
            Write-Warn "The new token is identical to the current token. No changes were made."
            return
        }

        Write-Info "New token: length=$($newToken.Length), sha256=$(Get-TokenFingerprint -Token $newToken)"
        $confirmation = (Read-Host "Apply this token? [y/N]").Trim()
        if ($confirmation -notmatch '^(?i:y|yes)$') {
            Write-Warn "Cancelled. No changes were made."
            return
        }

        $encodedToken = ConvertTo-Json -InputObject $newToken -Compress
        $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)
            return $match.Groups['prefix'].Value + $encodedToken
        }
        $updatedText = $ApiKeyRegex.Replace($config.Text, $evaluator, 1)

        $configDirectory = [System.IO.Path]::GetDirectoryName($ConfigPath)
        $operationId = [guid]::NewGuid().ToString('N')
        $tempName = ".opencode-token-switch-$operationId.jsonc"
        $backupName = ".opencode-token-switch-backup-$operationId.jsonc"
        $tempPath = Join-Path $configDirectory $tempName
        $backupPath = Join-Path $configDirectory $backupName
        $encoding = [System.Text.UTF8Encoding]::new([bool]$config.HasBom)
        [System.IO.File]::WriteAllText($tempPath, $updatedText, $encoding)

        Test-ConfigWithOpenCode -Path $tempPath
        [System.IO.File]::Replace($tempPath, $ConfigPath, $backupPath)
        $tempPath = $null
        [System.IO.File]::Delete($backupPath)
        $backupPath = $null

        Write-Ok "Token updated successfully."
        Write-Warn "Quit and restart OpenCode before starting the next session."
    }
    finally {
        if ($null -ne $tempPath -and (Test-Path -LiteralPath $tempPath)) {
            Remove-Item -LiteralPath $tempPath -Force
        }
        if ($null -ne $backupPath -and (Test-Path -LiteralPath $backupPath)) {
            Remove-Item -LiteralPath $backupPath -Force
        }
        $newToken = $null
        $currentToken = $null
    }
}

try {
    Invoke-TokenSwitch
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
