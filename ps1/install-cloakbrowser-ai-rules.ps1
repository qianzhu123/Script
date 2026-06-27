param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectPath
)

$ErrorActionPreference = "Stop"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = Read-Host "Enter the target project path"
}

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    Write-Fail "Project path is required."
    exit 1
}

$ProjectPath = [System.Environment]::ExpandEnvironmentVariables($ProjectPath)
$ProjectPath = $ProjectPath.Trim('"')

if (-not (Test-Path -LiteralPath $ProjectPath)) {
    Write-Info "Target path does not exist. Creating it now."
    New-Item -ItemType Directory -Path $ProjectPath -Force | Out-Null
}

$resolvedProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$rulesFile = Join-Path $resolvedProjectPath "CLOAKBROWSER_AI_RULES.md"
$agentsFile = Join-Path $resolvedProjectPath "AGENTS.md"

$rulesContent = @'
# CloakBrowser Automation Rules for AI Agents

This document is a project-level instruction file for AI coding agents.
Its purpose is to make every CloakBrowser automation script in this project consistent, runnable, and easy to maintain.

## Mandatory Environment Rule

Before running, testing, debugging, or generating commands for any CloakBrowser automation script, the AI agent must activate the Conda environment named `auto`.

Required command on Windows PowerShell:

```powershell
conda activate auto
```

Required command on Windows CMD:

```bat
conda activate auto
```

The AI agent must not suggest running project automation scripts before activating this environment.

## Primary Goal

Use CloakBrowser as the default browser automation runtime for this project when the task involves web automation, browser scripting, login/session preservation, scraping, browser interaction, page screenshots, or Playwright-style browser control.

## Default Python Pattern

Use this pattern for synchronous Python scripts unless the user explicitly requests async code:

```python
from cloakbrowser import launch

browser = launch(
    headless=False,
    humanize=True,
)

try:
    page = browser.new_page()
    page.goto("https://example.com")
    print(page.title())
finally:
    browser.close()
```

## Default Persistent Profile Pattern

When the task requires cookies, login sessions, local storage, browser history, or long-term identity, use a persistent context:

```python
from cloakbrowser import launch_persistent_context

ctx = launch_persistent_context(
    "./browser-profile",
    headless=False,
    humanize=True,
)

try:
    page = ctx.new_page()
    page.goto("https://example.com")
finally:
    ctx.close()
```

## Required Script Header Comment

Every generated CloakBrowser script should include a short header comment like this:

```python
# Runtime requirement:
#   conda activate auto
# This script uses CloakBrowser for browser automation.
```

## Command Generation Rules

When the AI agent provides run commands, it must include environment activation first.

PowerShell example:

```powershell
conda activate auto
python .\script.py
```

CMD example:

```bat
conda activate auto
python script.py
```

## Dependency Rules

Prefer Python unless the user asks for Node.js.

For Python projects, use:

```powershell
conda activate auto
pip install cloakbrowser
```

If GeoIP behavior is required, use:

```powershell
conda activate auto
pip install "cloakbrowser[geoip]"
```

If the browser binary must be installed or refreshed, use:

```powershell
conda activate auto
python -m cloakbrowser install
python -m cloakbrowser info
```

## Browser Configuration Defaults

Unless the user requests otherwise, use these defaults:

- `headless=False`
- `humanize=True`
- Use persistent profiles for login/session tasks.
- Use a stable fingerprint seed for repeated access to the same account or same long-term workflow.
- Use a proxy only when the user explicitly provides one or asks for proxy support.
- Use `geoip=True` only when a proxy is configured and geographic consistency is required.

Example with a stable fingerprint:

```python
browser = launch(
    headless=False,
    humanize=True,
    args=["--fingerprint=12345"],
)
```

Example with proxy and GeoIP:

```python
browser = launch(
    headless=False,
    humanize=True,
    proxy="http://user:pass@host:port",
    geoip=True,
)
```

## Reliability Rules

The AI agent should write automation scripts that are robust and maintainable:

1. Use explicit waits for important elements.
2. Avoid fixed sleep calls unless necessary.
3. Use `try/finally` to close the browser or context.
4. Save screenshots when debugging failures.
5. Log key steps with clear messages.
6. Keep selectors configurable near the top of the script.
7. Keep credentials, tokens, and proxy passwords out of source code.
8. Prefer environment variables for secrets.

## Safety and Compliance Rules

The AI agent must not create scripts for credential stuffing, spam, abuse, unauthorized access, payment fraud, account takeover, or bypassing access controls.

The AI agent may create scripts for legitimate automation, testing, personal workflows, authorized scraping, data collection from permitted sources, and browser-based productivity tasks.

## Project Output Convention

Generated automation scripts should normally be placed in one of these folders if they exist:

- `scripts/`
- `automation/`
- `tools/`

If none of these folders exist, the AI agent should ask before creating a new folder, or create `scripts/` when the user asks for a complete implementation.

## Quick Checklist for AI Agents

Before finalizing any CloakBrowser automation answer, verify:

- The script uses CloakBrowser, not raw Playwright, unless requested.
- The run instructions include `conda activate auto`.
- The script closes the browser or context safely.
- Persistent profile is used when sessions or logins are involved.
- Secrets are not hard-coded.
- The answer is directly runnable in the `auto` Conda environment.
'@

$agentBlockStart = "<!-- CLOAKBROWSER_AI_RULES_START -->"
$agentBlockEnd = "<!-- CLOAKBROWSER_AI_RULES_END -->"
$agentBlock = @"
$agentBlockStart
# CloakBrowser Automation Rule

For browser automation tasks in this project, follow `CLOAKBROWSER_AI_RULES.md`.

Mandatory runtime rule:

```powershell
conda activate auto
```

Do not generate run, test, or debug commands for CloakBrowser scripts without activating the `auto` Conda environment first.
$agentBlockEnd
"@

Write-Info "Writing CloakBrowser AI rules file."
Set-Content -LiteralPath $rulesFile -Value $rulesContent -Encoding UTF8

if (Test-Path -LiteralPath $agentsFile) {
    $existingAgentsContent = Get-Content -LiteralPath $agentsFile -Raw -ErrorAction Stop
    if ($existingAgentsContent.Contains($agentBlockStart) -and $existingAgentsContent.Contains($agentBlockEnd)) {
        Write-Info "Updating existing managed block in AGENTS.md."
        $pattern = "(?s)<!-- CLOAKBROWSER_AI_RULES_START -->.*?<!-- CLOAKBROWSER_AI_RULES_END -->"
        $updatedAgentsContent = [regex]::Replace($existingAgentsContent, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $agentBlock.TrimEnd() })
        Set-Content -LiteralPath $agentsFile -Value $updatedAgentsContent -Encoding UTF8
    }
    else {
        Write-Info "Appending managed block to existing AGENTS.md."
        Add-Content -LiteralPath $agentsFile -Value "`r`n$agentBlock" -Encoding UTF8
    }
}
else {
    Write-Info "Creating AGENTS.md."
    Set-Content -LiteralPath $agentsFile -Value $agentBlock.TrimStart() -Encoding UTF8
}

Write-Host ""
Write-Host "Done."
Write-Host "Project path: $resolvedProjectPath"
Write-Host "Created or updated: $rulesFile"
Write-Host "Created or updated: $agentsFile"
Write-Host ""
Write-Host "Recommended run command:"
Write-Host "conda activate auto"
Write-Host ""
