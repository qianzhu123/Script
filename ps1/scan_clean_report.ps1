$ErrorActionPreference = 'SilentlyContinue'
$desktop = [Environment]::GetFolderPath('Desktop')
$report = Join-Path $desktop 'clean.md'
$user = $env:USERPROFILE

function Format-Size([double]$bytes) {
  if ($null -eq $bytes) { return '0 B' }
  if ($bytes -ge 1GB) { return ('{0:N2} GB' -f ($bytes / 1GB)) }
  if ($bytes -ge 1MB) { return ('{0:N2} MB' -f ($bytes / 1MB)) }
  if ($bytes -ge 1KB) { return ('{0:N2} KB' -f ($bytes / 1KB)) }
  return ('{0:N0} B' -f $bytes)
}

function Get-DirSize([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  try {
    return (Get-ChildItem -LiteralPath $path -Force -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
  } catch { return $null }
}

$items = New-Object System.Collections.Generic.List[object]
function Add-Candidate($Name, $Path, $Type, $Risk, $CleanScript, $Note) {
  $size = Get-DirSize $Path
  if ($null -ne $size -and $size -gt 0) {
    $script:items.Add([pscustomobject]@{
      Name=$Name; Path=$Path; Type=$Type; SizeBytes=[int64]$size; Size=(Format-Size $size); Risk=$Risk; Note=$Note; CleanScript=$CleanScript
    }) | Out-Null
  }
}

Add-Candidate '用户临时目录 TEMP' $env:TEMP '缓存/临时文件' '低-中（关闭正在使用的软件后清理）' @'
# 清理当前用户 TEMP（建议先关闭软件）
Get-ChildItem -LiteralPath $env:TEMP -Force -ErrorAction SilentlyContinue |
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
'@ '应用安装包、解压残留、运行时临时文件，通常可清理；个别正在使用文件会删除失败。'

Add-Candidate 'Windows 临时目录' 'C:\Windows\Temp' '系统缓存/临时文件' '低-中（建议管理员运行）' @'
# 管理员 PowerShell 中运行
Get-ChildItem -LiteralPath 'C:\Windows\Temp' -Force -ErrorAction SilentlyContinue |
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
'@ '系统及安装程序临时文件。'

Add-Candidate 'Windows 更新下载缓存' 'C:\Windows\SoftwareDistribution\Download' '系统更新缓存' '中（清理后 Windows Update 可能重新下载）' @'
# 管理员 PowerShell 中运行：清理 Windows Update 下载缓存
Stop-Service wuauserv -Force
Stop-Service bits -Force
Get-ChildItem -LiteralPath 'C:\Windows\SoftwareDistribution\Download' -Force -ErrorAction SilentlyContinue |
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Start-Service bits
Start-Service wuauserv
'@ 'Windows 更新包下载缓存，不是个人文件。'

Add-Candidate '缩略图缓存' (Join-Path $user 'AppData\Local\Microsoft\Windows\Explorer') '系统缓存' '低（会自动重建）' @'
# 关闭资源管理器后清理缩略图缓存
Stop-Process -Name explorer -Force
Remove-Item -LiteralPath "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
Start-Process explorer.exe
'@ '图片/视频缩略图数据库，会自动重建。'

Add-Candidate '回收站（C盘）' 'C:\$Recycle.Bin' '已删除文件' '中-高（清空后难恢复，请确认）' @'
# 清空所有驱动器回收站（谨慎）
Clear-RecycleBin -Force
'@ '已删除但仍占空间的文件。清理前务必检查回收站内容。'

Add-Candidate 'Chrome 缓存' (Join-Path $user 'AppData\Local\Google\Chrome\User Data\Default\Cache') '浏览器缓存' '低（关闭浏览器后清理）' @'
# 关闭 Chrome 后运行
Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
'@ '网页缓存，可重建。注意脚本不删除书签/账号。'

Add-Candidate 'Chrome Code Cache' (Join-Path $user 'AppData\Local\Google\Chrome\User Data\Default\Code Cache') '浏览器缓存' '低' @'
Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
'@ 'Chrome JS/WASM 代码缓存。'

Add-Candidate 'Edge 缓存' (Join-Path $user 'AppData\Local\Microsoft\Edge\User Data\Default\Cache') '浏览器缓存' '低（关闭浏览器后清理）' @'
Stop-Process -Name msedge -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
'@ 'Microsoft Edge 网页缓存。'

Add-Candidate 'Edge Code Cache' (Join-Path $user 'AppData\Local\Microsoft\Edge\User Data\Default\Code Cache') '浏览器缓存' '低' @'
Stop-Process -Name msedge -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
'@ 'Edge 代码缓存。'

Add-Candidate 'NVIDIA 驱动安装缓存 Downloader' 'C:\ProgramData\NVIDIA Corporation\Downloader' '驱动安装缓存' '低-中（不影响当前驱动）' @'
Remove-Item -LiteralPath 'C:\ProgramData\NVIDIA Corporation\Downloader\*' -Recurse -Force -ErrorAction SilentlyContinue
'@ 'NVIDIA 驱动下载包缓存。'

Add-Candidate 'NVIDIA DXCache' (Join-Path $user 'AppData\Local\NVIDIA\DXCache') '显卡 shader 缓存' '低（会重建，游戏首次进入可能稍慢）' @'
Remove-Item -LiteralPath "$env:LOCALAPPDATA\NVIDIA\DXCache\*" -Recurse -Force -ErrorAction SilentlyContinue
'@ 'DirectX shader 缓存。'

Add-Candidate 'NVIDIA GLCache' (Join-Path $user 'AppData\Local\NVIDIA\GLCache') '显卡 shader 缓存' '低' @'
Remove-Item -LiteralPath "$env:LOCALAPPDATA\NVIDIA\GLCache\*" -Recurse -Force -ErrorAction SilentlyContinue
'@ 'OpenGL shader 缓存。'

Add-Candidate 'pip 缓存' (Join-Path $user 'AppData\Local\pip\Cache') '开发工具缓存' '低' @'
python -m pip cache purge
'@ 'Python pip 包下载缓存。'

Add-Candidate 'npm 缓存' (Join-Path $user 'AppData\Local\npm-cache') '开发工具缓存' '低' @'
npm cache clean --force
'@ 'Node.js npm 包缓存。'

Add-Candidate 'Yarn 缓存' (Join-Path $user 'AppData\Local\Yarn\Cache') '开发工具缓存' '低' @'
yarn cache clean
'@ 'Yarn 包缓存。'

Add-Candidate 'pnpm store' (Join-Path $user 'AppData\Local\pnpm\store') '开发工具缓存/包仓库' '中（会重新下载依赖）' @'
pnpm store prune
'@ 'pnpm 全局内容寻址依赖仓库，建议 prune 而不是直接删除。'

Add-Candidate 'NuGet 缓存/全局包' (Join-Path $user '.nuget\packages') '开发工具缓存/依赖包' '中（项目下次构建会重新下载）' @'
dotnet nuget locals all --clear
'@ '.NET NuGet 包缓存/全局包。'

Add-Candidate 'Gradle 缓存' (Join-Path $user '.gradle\caches') '开发工具缓存/构建缓存' '中（下次构建重新下载/重建）' @'
# 关闭 IDE/Gradle 后运行
Remove-Item -LiteralPath "$env:USERPROFILE\.gradle\caches\*" -Recurse -Force -ErrorAction SilentlyContinue
'@ 'Android/Java Gradle 依赖与构建缓存。'

Add-Candidate 'Maven 本地仓库' (Join-Path $user '.m2\repository') '开发工具缓存/依赖包' '中（下次构建重新下载）' @'
# 谨慎：会删除 Maven 本地依赖仓库
Remove-Item -LiteralPath "$env:USERPROFILE\.m2\repository\*" -Recurse -Force -ErrorAction SilentlyContinue
'@ 'Maven 依赖缓存。'

Add-Candidate 'Docker 数据目录（WSL 后端）' (Join-Path $user 'AppData\Local\Docker\wsl') '容器镜像/卷/缓存' '高（可能包含镜像、容器、卷数据）' @'
# 建议用 Docker 命令清理未使用对象，先查看：docker system df
# 清理未使用镜像/容器/网络/构建缓存：
docker system prune -a
# 如确认要清理未使用卷：docker volume prune
'@ 'Docker Desktop WSL 数据，可能很大，但卷中可能有重要数据。'

Add-Candidate 'VS Code 扩展目录' (Join-Path $user '.vscode\extensions') '开发工具扩展/缓存' '中（删除会移除扩展）' @'
# 先列出扩展：code --list-extensions
# 卸载不需要扩展：code --uninstall-extension 发布者.扩展名
'@ '不是纯缓存；占用大时可卸载不用的扩展。'

Add-Candidate 'VS Code Cache' (Join-Path $user 'AppData\Roaming\Code\Cache') '开发工具缓存' '低' @'
Stop-Process -Name Code -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$env:APPDATA\Code\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
'@ 'VS Code 缓存。'

Add-Candidate 'JetBrains caches/logs' (Join-Path $user 'AppData\Local\JetBrains') 'IDE 缓存/索引' '中（索引会重建，首次打开较慢）' @'
# 关闭 JetBrains IDE 后，建议在 IDE 菜单 File > Invalidate Caches
Get-ChildItem $env:LOCALAPPDATA\JetBrains -Directory | ForEach-Object {
  Remove-Item -LiteralPath (Join-Path $_.FullName 'caches') -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Join-Path $_.FullName 'log') -Recurse -Force -ErrorAction SilentlyContinue
}
'@ 'JetBrains IDE 缓存、索引、日志等。'

Add-Candidate 'Unity Cache' (Join-Path $user 'AppData\Local\Unity\cache') '开发/游戏引擎缓存' '低-中' @'
Remove-Item -LiteralPath "$env:LOCALAPPDATA\Unity\cache\*" -Recurse -Force -ErrorAction SilentlyContinue
'@ 'Unity 资源导入/下载缓存。'

# 大文件扫描（只列出，不给删除脚本，避免误删个人文件）
$largeFiles = @()
foreach ($root in @($user, 'C:\ProgramData')) {
  if (Test-Path $root) {
    $largeFiles += Get-ChildItem -LiteralPath $root -Force -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Length -ge 1GB } |
      Sort-Object Length -Descending |
      Select-Object -First 30 FullName, Length
  }
}
$largeFiles = $largeFiles | Sort-Object Length -Descending | Select-Object -First 30

# 目录体积排行（常见根目录的一级子目录）
$topDirs = @()
foreach ($root in @($user, 'C:\ProgramData', 'C:\Windows', 'C:\')) {
  if (Test-Path $root) {
    foreach ($d in (Get-ChildItem -LiteralPath $root -Force -Directory -ErrorAction SilentlyContinue)) {
      $s = Get-DirSize $d.FullName
      if ($s -gt 0) { $topDirs += [pscustomobject]@{Path=$d.FullName; SizeBytes=[int64]$s; Size=(Format-Size $s)} }
    }
  }
}
$topDirs = $topDirs | Sort-Object SizeBytes -Descending | Select-Object -First 50
$items = $items | Sort-Object SizeBytes -Descending
$totalCandidates = ($items | Measure-Object SizeBytes -Sum).Sum
$cdrive = Get-PSDrive C

$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine('# C盘空间扫描报告（未执行任何清理）')
[void]$md.AppendLine('')
[void]$md.AppendLine("生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$md.AppendLine("当前用户：$user")
[void]$md.AppendLine("C盘剩余空间：$(Format-Size $cdrive.Free)；已用：$(Format-Size $cdrive.Used)")
[void]$md.AppendLine("候选项合计（可能含父子目录重叠，不能简单相加）：$(Format-Size $totalCandidates)")
[void]$md.AppendLine('')
[void]$md.AppendLine('> 本报告只扫描并写入建议，没有执行删除/清理。请只复制你确认安全的脚本手动运行。')
[void]$md.AppendLine('')
[void]$md.AppendLine('## 1. 可清理/可管理候选项（按占用排序）')
[void]$md.AppendLine('')
[void]$md.AppendLine('| 排名 | 名称 | 类型 | 大小 | 路径 | 风险 | 说明 |')
[void]$md.AppendLine('|---:|---|---|---:|---|---|---|')
$i=1
foreach ($it in $items) {
  $p = ($it.Path -replace '\|','\|')
  [void]$md.AppendLine(('| {0} | {1} | {2} | {3} | `{4}` | {5} | {6} |' -f $i, $it.Name, $it.Type, $it.Size, $p, $it.Risk, $it.Note))
  $i++
}

[void]$md.AppendLine('')
[void]$md.AppendLine('## 2. 每个候选项对应的 PowerShell 清理脚本')
[void]$md.AppendLine('')
[void]$md.AppendLine('> 注意：执行前请关闭相关软件；涉及“中/高风险”的项目请先备份或确认无重要数据。')
foreach ($it in $items) {
  [void]$md.AppendLine('')
  [void]$md.AppendLine("### $($it.Name) — $($it.Size)")
  [void]$md.AppendLine(('- 路径：`{0}`' -f $it.Path))
  [void]$md.AppendLine("- 类型：$($it.Type)")
  [void]$md.AppendLine("- 风险：$($it.Risk)")
  [void]$md.AppendLine("- 说明：$($it.Note)")
  [void]$md.AppendLine('```powershell')
  [void]$md.AppendLine($it.CleanScript.Trim())
  [void]$md.AppendLine('```')
}

[void]$md.AppendLine('')
[void]$md.AppendLine('## 3. 扫描到的大文件（仅列出，不建议直接脚本删除）')
[void]$md.AppendLine('')
[void]$md.AppendLine('| 排名 | 大小 | 路径 | 建议 |')
[void]$md.AppendLine('|---:|---:|---|---|')
$i=1
foreach ($f in $largeFiles) {
  [void]$md.AppendLine(('| {0} | {1} | `{2}` | 先确认是不是个人文件/虚拟磁盘/安装包；建议移动到其他盘或手动删除。 |' -f $i, (Format-Size $f.Length), $f.FullName))
  $i++
}

[void]$md.AppendLine('')
[void]$md.AppendLine('## 4. C盘目录体积排行（用于定位大户，不代表都能清理）')
[void]$md.AppendLine('')
[void]$md.AppendLine('| 排名 | 大小 | 路径 | 备注 |')
[void]$md.AppendLine('|---:|---:|---|---|')
$i=1
foreach ($d in $topDirs) {
  [void]$md.AppendLine(('| {0} | {1} | `{2}` | 请人工判断；Program Files、Windows、用户文档目录通常不要直接删除。 |' -f $i, $d.Size, $d.Path))
  $i++
}

[void]$md.AppendLine('')
[void]$md.AppendLine('## 5. 额外安全清理建议')
[void]$md.AppendLine('')
[void]$md.AppendLine('1. 优先使用 Windows 自带：设置 → 系统 → 存储 → 临时文件。建议选择“临时文件、缩略图、传递优化文件”等。')
[void]$md.AppendLine('2. 不要手动删除 `C:\Windows\WinSxS`。如需系统组件清理，请管理员运行：')
[void]$md.AppendLine('```powershell')
[void]$md.AppendLine('DISM.exe /Online /Cleanup-Image /StartComponentCleanup')
[void]$md.AppendLine('```')
[void]$md.AppendLine('3. 如果不用休眠，可管理员运行以下命令释放 `hiberfil.sys`（会禁用休眠/快速启动）：')
[void]$md.AppendLine('```powershell')
[void]$md.AppendLine('powercfg -h off')
[void]$md.AppendLine('```')
[void]$md.AppendLine('4. 大型个人文件、虚拟机、游戏、工程目录建议移动到其他盘或外置硬盘，不建议用脚本批量删除。')

Set-Content -LiteralPath $report -Value $md.ToString() -Encoding UTF8
Write-Host "REPORT=$report"
Write-Host "CANDIDATES=$($items.Count)"
Write-Host "TOTAL_CANDIDATE_SIZE=$(Format-Size $totalCandidates)"
$items | Select-Object -First 15 Name,Size,Path,Type | Format-Table -AutoSize
