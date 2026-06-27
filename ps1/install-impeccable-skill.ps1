<#
Install only the Codex-compatible Impeccable skill into a project root.

Usage:
  .\install-impeccable-skill.ps1 -ProjectRoot "D:\path\to\project"

If ProjectRoot is not provided, the script will prompt for it.

This script installs only the Codex-compatible provider files:
  .agents\skills\impeccable
  .codex\hooks.json, when the official bundle contains it

It does not create .claude, .cursor, .gemini, or .kiro folders.
It does not require unzip and does not install system packages.
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectRoot
)

$ErrorActionPreference = "Stop"

function Fail($Message) {
    Write-Host "Error: $Message" -ForegroundColor Red
    exit 1
}

function New-TempWorkDir {
    $tempBase = $env:TEMP
    if ([string]::IsNullOrWhiteSpace($tempBase)) { $tempBase = $env:TMP }
    if ([string]::IsNullOrWhiteSpace($tempBase)) { $tempBase = Join-Path $env:USERPROFILE "AppData\Local\Temp" }

    $dir = Join-Path $tempBase ("impeccable-install-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Test-ZipFile($ZipFile) {
    if (-not (Test-Path -LiteralPath $ZipFile)) { return $false }

    $item = Get-Item -LiteralPath $ZipFile
    if ($item.Length -lt 1024) { return $false }

    $fs = [System.IO.File]::OpenRead($ZipFile)
    try {
        $bytes = New-Object byte[] 4
        $read = $fs.Read($bytes, 0, 4)
        if ($read -ne 4) { return $false }
        return ($bytes[0] -eq 0x50 -and $bytes[1] -eq 0x4B)
    }
    finally {
        $fs.Close()
    }
}

function Show-InvalidDownloadHint($OutFile) {
    if (-not (Test-Path -LiteralPath $OutFile)) { return }

    try {
        $length = (Get-Item -LiteralPath $OutFile).Length
        Write-Host "Notice: Downloaded file size: $length bytes"

        if ($length -lt 4096) {
            $raw = Get-Content -LiteralPath $OutFile -Raw -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $preview = $raw
                if ($preview.Length -gt 500) { $preview = $preview.Substring(0, 500) }
                Write-Host "Notice: Downloaded content preview:"
                Write-Host $preview
            }
        }
    }
    catch {
        Write-Host "Notice: Could not inspect invalid download."
    }
}

function Download-With-Curl($Url, $OutFile) {
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) { return $false }

    Write-Host "Notice: Using curl.exe for download."

    & curl.exe -L --fail --silent --show-error --retry 3 --connect-timeout 30 --max-time 300 `
        -H "User-Agent: impeccable-skill-installer" `
        -H "Accept: application/zip,application/octet-stream,*/*" `
        -o $OutFile $Url

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Notice: curl.exe failed with exit code $LASTEXITCODE."
        return $false
    }

    return (Test-ZipFile $OutFile)
}

function Download-With-WebClient($Url, $OutFile) {
    Write-Host "Notice: Using .NET WebClient for download."

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    }
    catch {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    }

    try {
        $client = New-Object System.Net.WebClient
        $client.Headers.Add("User-Agent", "impeccable-skill-installer")
        $client.Headers.Add("Accept", "application/zip,application/octet-stream,*/*")
        $client.DownloadFile($Url, $OutFile)
        return (Test-ZipFile $OutFile)
    }
    catch {
        Write-Host "Notice: .NET WebClient failed. $($_.Exception.Message)"
        return $false
    }
    finally {
        if ($client) { $client.Dispose() }
    }
}

function Download-With-InvokeWebRequest($Url, $OutFile) {
    Write-Host "Notice: Using Invoke-WebRequest for download."

    try {
        $ProgressPreference = "SilentlyContinue"
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -Headers @{
            "User-Agent" = "impeccable-skill-installer"
            "Accept" = "application/zip,application/octet-stream,*/*"
        }
        return (Test-ZipFile $OutFile)
    }
    catch {
        Write-Host "Notice: Invoke-WebRequest failed. $($_.Exception.Message)"
        return $false
    }
}

function Download-File($Url, $OutFile) {
    if (Test-Path -LiteralPath $OutFile) {
        Remove-Item -LiteralPath $OutFile -Force
    }

    if (Download-With-Curl $Url $OutFile) { return }

    if (Test-Path -LiteralPath $OutFile) {
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
    }

    if (Download-With-WebClient $Url $OutFile) { return }

    if (Test-Path -LiteralPath $OutFile) {
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
    }

    if (Download-With-InvokeWebRequest $Url $OutFile) { return }

    Show-InvalidDownloadHint $OutFile
    Fail "Failed to download a valid Impeccable bundle from $Url"
}

function Extract-Zip($ZipFile, $Destination) {
    if (-not (Test-ZipFile $ZipFile)) {
        Show-InvalidDownloadHint $ZipFile
        Fail "The downloaded file is not a valid zip archive: $ZipFile"
    }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
    if ($tar) {
        & tar.exe -xf $ZipFile -C $Destination
        if ($LASTEXITCODE -eq 0) { return }
        Write-Host "Notice: tar.exe extraction failed with exit code $LASTEXITCODE. Falling back to Expand-Archive."
    }

    try {
        Expand-Archive -LiteralPath $ZipFile -DestinationPath $Destination -Force
    }
    catch {
        Fail "Failed to extract Impeccable bundle. $($_.Exception.Message)"
    }
}

function Find-CodexSkillSource($ExtractRoot) {
    $direct = Join-Path $ExtractRoot ".agents\skills\impeccable"
    if (Test-Path -LiteralPath $direct) { return $direct }

    $matches = Get-ChildItem -LiteralPath $ExtractRoot -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\\.agents\\skills\\impeccable$" }

    if ($matches -and $matches.Count -gt 0) {
        return $matches[0].FullName
    }

    return $null
}

function Find-CodexHooksSource($ExtractRoot) {
    $direct = Join-Path $ExtractRoot ".codex\hooks.json"
    if (Test-Path -LiteralPath $direct) { return $direct }

    $matches = Get-ChildItem -LiteralPath $ExtractRoot -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\\.codex\\hooks\.json$" }

    if ($matches -and $matches.Count -gt 0) {
        return $matches[0].FullName
    }

    return $null
}

function Merge-Or-Copy-CodexHooks($SourceHooks, $DestinationHooks) {
    if ([string]::IsNullOrWhiteSpace($SourceHooks)) { return }
    if (-not (Test-Path -LiteralPath $SourceHooks)) { return }

    New-Item -ItemType Directory -Path (Split-Path -Parent $DestinationHooks) -Force | Out-Null

    if (-not (Test-Path -LiteralPath $DestinationHooks)) {
        Copy-Item -LiteralPath $SourceHooks -Destination $DestinationHooks -Force
        Write-Host "Installed Codex hooks into: .codex"
        return
    }

    try {
        $existingRaw = Get-Content -LiteralPath $DestinationHooks -Raw
        $freshRaw = Get-Content -LiteralPath $SourceHooks -Raw
        $existing = $existingRaw | ConvertFrom-Json -Depth 100
        $fresh = $freshRaw | ConvertFrom-Json -Depth 100

        $existingJson = $existing | ConvertTo-Json -Depth 100
        $freshJson = $fresh | ConvertTo-Json -Depth 100

        if ($existingJson -notmatch "skills/impeccable/" -and $existingJson -ne $freshJson) {
            $backup = "$DestinationHooks.bak"
            Copy-Item -LiteralPath $DestinationHooks -Destination $backup -Force
            Write-Host "Notice: Existing Codex hooks were backed up to: $backup"
        }

        Copy-Item -LiteralPath $SourceHooks -Destination $DestinationHooks -Force
        Write-Host "Installed Codex hooks into: .codex"
    }
    catch {
        $backup = "$DestinationHooks.bak"
        Copy-Item -LiteralPath $DestinationHooks -Destination $backup -Force
        Copy-Item -LiteralPath $SourceHooks -Destination $DestinationHooks -Force
        Write-Host "Notice: Existing Codex hooks were not valid JSON or could not be merged."
        Write-Host "Notice: Existing Codex hooks were backed up to: $backup"
        Write-Host "Installed Codex hooks into: .codex"
    }
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Read-Host "Enter the project root path"
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    Fail "Project root path is required."
}

$resolved = Resolve-Path -LiteralPath $ProjectRoot -ErrorAction SilentlyContinue
if (-not $resolved) {
    Fail "Project root does not exist: $ProjectRoot"
}

$ProjectRootPath = $resolved.Path
$workDir = New-TempWorkDir
$zipFile = Join-Path $workDir "impeccable-universal.zip"
$extractDir = Join-Path $workDir "bundle"

Write-Host "Installing only the Codex-compatible Impeccable skill into:"
Write-Host $ProjectRootPath
Write-Host ""
Write-Host "Downloading Impeccable repository archive..."

try {
    Download-File "https://codeload.github.com/pbakaus/impeccable/zip/refs/heads/main" $zipFile

    Write-Host "Extracting Impeccable repository archive..."
    Extract-Zip $zipFile $extractDir

    $sourceSkill = Find-CodexSkillSource $extractDir
    $destSkill = Join-Path $ProjectRootPath ".agents\skills\impeccable"

    if ([string]::IsNullOrWhiteSpace($sourceSkill) -or -not (Test-Path -LiteralPath $sourceSkill)) {
        Fail "The downloaded archive does not contain the Codex skill at dist\agents\.agents\skills\impeccable or .agents\skills\impeccable."
    }

    if (Test-Path -LiteralPath $destSkill) {
        Remove-Item -LiteralPath $destSkill -Recurse -Force
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $destSkill) -Force | Out-Null
    Copy-Item -LiteralPath $sourceSkill -Destination $destSkill -Recurse -Force

    $sourceHooks = Find-CodexHooksSource $extractDir
    $destHooks = Join-Path $ProjectRootPath ".codex\hooks.json"
    Merge-Or-Copy-CodexHooks $sourceHooks $destHooks
}
finally {
    if (Test-Path -LiteralPath $workDir) {
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "Done. The Codex-compatible Impeccable skill was installed under:"
Write-Host "  $ProjectRootPath\.agents\skills\impeccable"
Write-Host ""
Write-Host "Restart Codex in the project root, then run:"
Write-Host "  /skills"
Write-Host '  $impeccable init'

exit 0
