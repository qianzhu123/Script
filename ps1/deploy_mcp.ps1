$ErrorActionPreference = "Stop"

# deploy_mcp.ps1 — 把一个 MCP 配置同时部署到 Claude Code、Codex，
# 并输出 Cherry Studio 可直接导入的标准 JSON。
#
# 用法（交互式，逐项问答）：
#   powershell -ExecutionPolicy Bypass -File "deploy_mcp.ps1"
#   或通过 bat/deploy_mcp.bat 双击启动。
#
# 仅修改：C:\Users\Light\.claude.json、C:\Users\Light\.codex\config.toml
# 以及把 Cherry 导入 JSON 写到 output\mcp-<name>.json。
# 写入前对两个目标文件做 .bak 备份。

# ---------- 路径与常量 ----------
$ClaudeJson = "C:\Users\Light\.claude.json"
$CodexToml  = "C:\Users\Light\.codex\config.toml"
$Stamp      = (Get-Date).ToString("yyyyMMdd-HHmmss")
$OutDir     = Join-Path $PSScriptRoot "..\output"
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

function Write-Section($t) { Write-Host "`n==== $t ====" -ForegroundColor Cyan }
function Write-Ok($t)     { Write-Host "[OK] $t" -ForegroundColor Green }
function Write-Warn($t)    { Write-Host "[!!] $t" -ForegroundColor Yellow }
function Confirm-Yes($q) {
    $a = Read-Host "$q [y/N]"
    return ($a.Trim() -match '^(y|yes)$')
}

# ---------- 收集输入 ----------
Write-Section "MCP 部署工具（Claude Code + Codex + Cherry Studio）"
$Name    = (Read-Host "MCP 名称 (如 mobile-mcp)").Trim()
if (-not $Name -or $Name -notmatch '^[A-Za-z0-9_-]+$') { Write-Error "名称非法：仅允许字母数字下划线连字符"; exit 1 }

$Type = (Read-Host "类型 [1]stdio(默认) [2]sse [3]http").Trim()
$Type = switch ($Type) { "2" {"sse"} "3" {"http"} default {"stdio"} }

$Command = ""
$Args    = ""
$Url     = ""
$Env     = @()
if ($Type -eq "stdio") {
    $Command = (Read-Host "启动命令 (如 npx / uvx / python / .cmd 路径)").Trim()
    $ArgsRaw = (Read-Host "参数，空格分隔 (如 -y @mobilenext/mobile-mcp@latest)").Trim()
    # 把 ArgsRaw 切成数组，保留引号处理
    $Args = ($ArgsRaw -split '\s+' | Where-Object { $_ -ne '' }) -join "`n"
} else {
    $Url = (Read-Host "服务 URL (如 http://localhost:8651/sse)").Trim()
}

# 可选 env
Write-Host "环境变量（可选，每行 KEY=VALUE，空行结束）："
while ($true) {
    $line = Read-Host "  env>"
    if (-not $line.Trim()) { break }
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
        $Env += $line.Trim()
    } else {
        Write-Warn "忽略不规范行：$line"
    }
}

$ScopeRaw = (Read-Host "Claude Code 作用域 [1]user(全局,默认) [2]local(仅当前目录)").Trim()
$Scope = ($ScopeRaw -eq "2") ? "local" : "user"

# 汇总确认
Write-Section "确认"
Write-Host "名称  : $Name"
Write-Host "类型  : $Type"
if ($Type -eq "stdio") {
    Write-Host "命令  : $Command"
    Write-Host "参数  : $(($Args -split "`n") -join ' ')"
} else {
    Write-Host "URL   : $Url"
}
if ($Env.Count -gt 0) { Write-Host "环境  :"; $Env | ForEach-Object { Write-Host "    $_" } }
Write-Host "作用域: $Scope"
if (-not (Confirm-Yes "确认部署？")) { Write-Warn "已取消"; exit 0 }

# 备份
Copy-Item $ClaudeJson "$ClaudeJson.bak-$Stamp" -Force
Copy-Item $CodexToml  "$CodexToml.bak-$Stamp"  -Force
Write-Ok "已备份 .claude.json / config.toml -> .bak-$Stamp"

# ---------- 1. Claude Code (.claude.json) ----------
try {
    $cj = Get-Content $ClaudeJson -Raw | ConvertFrom-Json
} catch { Write-Error "解析 .claude.json 失败：$_" }

# 确保 mcpServers 节点存在
if (-not $cj.PSObject.Properties['mcpServers']) {
    $cj | Add-Member -NotePropertyName mcpServers -NotePropertyValue (New-Object PSCustomObject)
}
# 删除同名旧条目
if ($cj.mcpServers.PSObject.Properties[$Name]) {
    $cj.mcpServers.PSObject.Properties.Remove($Name)
    Write-Warn "Claude: 移除旧条目 $Name"
}
$entry = [ordered]@{}
if ($Type -eq "stdio") {
    $entry["type"] = "stdio"
    $entry["command"] = $Command
    $entry["args"] = ($Args -split "`n" | Where-Object { $_ -ne '' })
} else {
    $entry["type"] = $Type
    $entry["url"]  = $Url
}
if ($Env.Count -gt 0) {
    $envObj = [ordered]@{}
    foreach ($e in $Env) {
        $k,$v = $e -split '=',2
        $envObj[$k] = $v
    }
    $entry["env"] = $envObj
}
$cj.mcpServers | Add-Member -NotePropertyName $Name -NotePropertyValue ([PSCustomObject]$entry)
$cj | ConvertTo-Json -Depth 32 | Set-Content $ClaudeJson -Encoding UTF8
Write-Ok "Claude Code: $Name 已写入 $ClaudeJson"
Write-Host "    若作用域=local，可改用： claude mcp add -s local $Name -- （命令）" -ForegroundColor DarkGray

# ---------- 2. Codex (config.toml) ----------
$toml = Get-Content $CodexToml -Raw
# 移除同名旧块（[mcp_servers.<name>] 到下一个 [ 开头或文件末尾）
$pattern = "(?ms)^\[mcp_servers\.$Name\]\r?\n.*?(?=^\[|\z)"
if ($toml -match $pattern) {
    $toml = $toml -replace $pattern, ""
    Write-Warn "Codex: 移除旧条目 $Name"
}
# 把新块统一追加到文件末尾，避免插入到 [projects.*] 等非 mcp 表之间造成解析歧义
$blockLines = New-Object System.Collections.Generic.List[string]
$blockLines.Add("[mcp_servers.$Name]")
if ($Type -eq "stdio") {
    $blockLines.Add("type = `"stdio`"")
    $blockLines.Add("command = '$Command'")
    $argArr = $Args -split "`n" | Where-Object { $_ -ne '' }
    $argStr = ($argArr | ForEach-Object { '"' + $_ + '"' }) -join ", "
    $blockLines.Add("args = [$argStr]")
} else {
    $blockLines.Add("type = `"$Type`"")
    $blockLines.Add("url = `"$Url`"")
}
if ($Env.Count -gt 0) {
    # 用内联表 env = { K = "V" }，避免子表 [mcp_servers.x.env] 污染其后的顶层表
    $pairs = @()
    foreach ($e in $Env) {
        $k,$v = $e -split '=',2
        $pairs += "$k = `"$v`""
    }
    $blockLines.Add("env = { " + ($pairs -join ", ") + " }")
}
if (-not $toml.EndsWith("`r`n")) { $toml += "`r`n" }
$toml += ($blockLines -join "`r`n") + "`r`n"
Set-Content $CodexToml -Value $toml -Encoding UTF8
Write-Ok "Codex: $Name 已写入 $CodexToml"

# ---------- 3. Cherry Studio 导入 JSON ----------
$cherry = [ordered]@{
    mcpServers = [ordered]@{}
}
$ce = [ordered]@{}
if ($Type -eq "stdio") {
    $ce["command"] = $Command
    $ce["args"] = $Args -split "`n" | Where-Object { $_ -ne '' }
} else {
    $ce["type"] = $Type
    $ce["url"]  = $Url
}
if ($Env.Count -gt 0) {
    $envObj = [ordered]@{}
    foreach ($e in $Env) { $k,$v = $e -split '=',2; $envObj[$k] = $v }
    $ce["env"] = $envObj
}
$cherry.mcpServers[$Name] = $ce
$cherryJson = $cherry | ConvertTo-Json -Depth 32
$cherryFile = Join-Path $OutDir "mcp-$Name.json"
$cherryJson | Set-Content $cherryFile -Encoding UTF8

Write-Section "Cherry Studio 导入 JSON"
Write-Host $cherryJson -ForegroundColor White
Write-Host "`n已保存到：$cherryFile"

# ---------- 完成指引 ----------
Write-Section "完成"
Write-Ok "Claude Code  ：已写入 .claude.json — 重启 Claude Code 后用 `claude mcp list` 验证"
Write-Ok "Codex       ：已写入 config.toml — 重启 Codex 后用 `codex mcp list` 验证"
Write-Ok "Cherry Studio：复制上方 JSON → 设置 → MCP 服务器 → 导入，或新建后粘贴"
Write-Host "`n三端命令本体相同，仅因各自文件格式不同分别落地。" -ForegroundColor DarkGray
