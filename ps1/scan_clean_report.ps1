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

Add-Candidate 'usertempDirectory TEMP' $env:TEMP 'cache/tempfile' 'low-medium(close applications clean)' @'
# cleancurrentuser TEMP(recommendation closeapplications)
Get-ChildItem -LiteralPath $env:TEMP -Force -ErrorAction SilentlyContinue |
 Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
'@ 'applicationinstaller//Run tempfile, clean; file Failed.'

Add-Candidate 'Windows tempDirectory' 'C:\Windows\Temp' 'systemcache/tempfile' 'low-medium(recommendation Run)' @'
# PowerShell Run
Get-ChildItem -LiteralPath 'C:\Windows\Temp' -Force -ErrorAction SilentlyContinue |
 Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
'@ 'system installertempfile.'

Add-Candidate 'Windows Updatedownloadcache' 'C:\Windows\SoftwareDistribution\Download' 'systemUpdatecache' ' (clean Windows Update download)' @'
# PowerShell Run:clean Windows Update downloadcache
Stop-Service wuauserv -Force
Stop-Service bits -Force
Get-ChildItem -LiteralPath 'C:\Windows\SoftwareDistribution\Download' -Force -ErrorAction SilentlyContinue |
 Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Start-Service bits
Start-Service wuauserv
'@ 'Windows Update downloadcache, file.'

Add-Candidate 'thumbnailcache' (Join-Path $user 'AppData\Local\Microsoft\Windows\Explorer') 'systemcache' ' (automaticrebuild)' @'
# close cleanthumbnailcache
Stop-Process -Name explorer -Force
Remove-Item -LiteralPath "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
Start-Process explorer.exe
'@ 'image/videothumbnail, automaticrebuild.'

Add-Candidate 'Recycle Bin(C)' 'C:\$Recycle.Bin' ' file' 'low-medium(,)' @'
# driver Recycle Bin(caution)
Clear-RecycleBin -Force
'@ ' file.clean checkRecycle Bin.'

Add-Candidate 'Chrome cache' (Join-Path $user 'AppData\Local\Google\Chrome\User Data\Default\Cache') 'browsercache' ' (closebrowser clean)' @'
# close Chrome Run
Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
'@ 'web pagecache, rebuild. script/.'

Add-Candidate 'Chrome Code Cache' (Join-Path $user 'AppData\Local\Google\Chrome\User Data\Default\Code Cache') 'browsercache' ' ' @'
Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
'@ 'Chrome JS/WASM cache.'

Add-Candidate 'Edge cache' (Join-Path $user 'AppData\Local\Microsoft\Edge\User Data\Default\Cache') 'browsercache' ' (closebrowser clean)' @'
Stop-Process -Name msedge -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
'@ 'Microsoft Edge web pagecache.'

Add-Candidate 'Edge Code Cache' (Join-Path $user 'AppData\Local\Microsoft\Edge\User Data\Default\Code Cache') 'browsercache' ' ' @'
Stop-Process -Name msedge -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
'@ 'Edge cache.'

Add-Candidate 'NVIDIA driverInstallcache Downloader' 'C:\ProgramData\NVIDIA Corporation\Downloader' 'driverInstallcache' 'low-medium(currentdriver)' @'
Remove-Item -LiteralPath 'C:\ProgramData\NVIDIA Corporation\Downloader\*' -Recurse -Force -ErrorAction SilentlyContinue
'@ 'NVIDIA driverdownload cache.'

Add-Candidate 'NVIDIA DXCache' (Join-Path $user 'AppData\Local\NVIDIA\DXCache') 'GPU shader cache' ' (rebuild,)' @'
Remove-Item -LiteralPath "$env:LOCALAPPDATA\NVIDIA\DXCache\*" -Recurse -Force -ErrorAction SilentlyContinue
'@ 'DirectX shader cache.'

Add-Candidate 'NVIDIA GLCache' (Join-Path $user 'AppData\Local\NVIDIA\GLCache') 'GPU shader cache' ' ' @'
Remove-Item -LiteralPath "$env:LOCALAPPDATA\NVIDIA\GLCache\*" -Recurse -Force -ErrorAction SilentlyContinue
'@ 'OpenGL shader cache.'

Add-Candidate 'pip cache' (Join-Path $user 'AppData\Local\pip\Cache') 'developer toolscache' ' ' @'
python -m pip cache purge
'@ 'Python pip downloadcache.'

Add-Candidate 'npm cache' (Join-Path $user 'AppData\Local\npm-cache') 'developer toolscache' ' ' @'
npm cache clean --force
'@ 'Node.js npm cache.'

Add-Candidate 'Yarn cache' (Join-Path $user 'AppData\Local\Yarn\Cache') 'developer toolscache' ' ' @'
yarn cache clean
'@ 'Yarn cache.'

Add-Candidate 'pnpm store' (Join-Path $user 'AppData\Local\pnpm\store') 'developer toolscache/repository' ' (download)' @'
pnpm store prune
'@ 'pnpm repository,recommendation prune.'

Add-Candidate 'NuGet cache/' (Join-Path $user '.nuget\packages') 'developer toolscache/' ' (project download)' @'
dotnet nuget locals all --clear
'@ '.NET NuGet cache/.'

Add-Candidate 'Gradle cache' (Join-Path $user '.gradle\caches') 'developer toolscache/cache' ' (download/rebuild)' @'
# close IDE/Gradle Run
Remove-Item -LiteralPath "$env:USERPROFILE\.gradle\caches\*" -Recurse -Force -ErrorAction SilentlyContinue
'@ 'Android/Java Gradle cache.'

Add-Candidate 'Maven localrepository' (Join-Path $user '.m2\repository') 'developer toolscache/' ' (download)' @'
# caution: Maven local repository
Remove-Item -LiteralPath "$env:USERPROFILE\.m2\repository\*" -Recurse -Force -ErrorAction SilentlyContinue
'@ 'Maven cache.'

Add-Candidate 'Docker Directory(WSL)' (Join-Path $user 'AppData\Local\Docker\wsl') '//cache' ' (//)' @'
# recommendation Docker commandclean,:docker system df
# clean///cache:
docker system prune -a
# clean:docker volume prune
'@ 'Docker Desktop WSL,,.'

Add-Candidate 'VS Code Directory' (Join-Path $user '.vscode\extensions') 'developer tools/cache' ' ()' @'
# :code --list-extensions
# :code --uninstall-extension. 
'@ ' cache;used by.'

Add-Candidate 'VS Code Cache' (Join-Path $user 'AppData\Roaming\Code\Cache') 'developer toolscache' ' ' @'
Stop-Process -Name Code -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$env:APPDATA\Code\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
'@ 'VS Code cache.'

Add-Candidate 'JetBrains caches/logs' (Join-Path $user 'AppData\Local\JetBrains') 'IDE cache/' ' (rebuild, open)' @'
# close JetBrains IDE,recommendation IDE File > Invalidate Caches
Get-ChildItem $env:LOCALAPPDATA\JetBrains -Directory | ForEach-Object {
 Remove-Item -LiteralPath (Join-Path $_.FullName 'caches') -Recurse -Force -ErrorAction SilentlyContinue
 Remove-Item -LiteralPath (Join-Path $_.FullName 'log') -Recurse -Force -ErrorAction SilentlyContinue
}
'@ 'JetBrains IDE cache//log.'

Add-Candidate 'Unity Cache' (Join-Path $user 'AppData\Local\Unity\cache') '/cache' 'low-medium' @'
Remove-Item -LiteralPath "$env:LOCALAPPDATA\Unity\cache\*" -Recurse -Force -ErrorAction SilentlyContinue
'@ 'Unity /downloadcache.'

# filescan(, script, file)
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

# directory(directoryDirectory)
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
[void]$md.AppendLine('# C scanreport(run clean)')
[void]$md.AppendLine('')
[void]$md.AppendLine("generated at:$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$md.AppendLine("currentuser:$user")
[void]$md.AppendLine("C free space:$(Format-Size $cdrive.Free);used:$(Format-Size $cdrive.Used)")
[void]$md.AppendLine("candidates (directory,):$(Format-Size $totalCandidates)")
[void]$md.AppendLine('')
[void]$md.AppendLine('> report scan recommendation, run/clean. copy security scriptmanualRun.')
[void]$md.AppendLine('')
[void]$md.AppendLine('## 1. clean/candidates(used by)')
[void]$md.AppendLine('')
[void]$md.AppendLine('| rank | name | type | size | Path | risk | note |')
[void]$md.AppendLine('|---:|---|---|---:|---|---|---|')
$i=1
foreach ($it in $items) {
 $p = ($it.Path -replace '\|','\|')
 [void]$md.AppendLine(('| {0} | {1} | {2} | {3} | `{4}` | {5} | {6} |' -f $i, $it.Name, $it.Type, $it.Size, $p, $it.Risk, $it.Note))
 $i++
}

[void]$md.AppendLine('')
[void]$md.AppendLine('## 2. candidates PowerShell cleanscript')
[void]$md.AppendLine('')
[void]$md.AppendLine('> :run closerelatedapplications; "/risk" project.')
foreach ($it in $items) {
 [void]$md.AppendLine('')
 [void]$md.AppendLine("### $($it.Name) - $($it.Size)")
 [void]$md.AppendLine(('- Path:`{0}`' -f $it.Path))
 [void]$md.AppendLine("- type:$($it.Type)")
 [void]$md.AppendLine("- risk:$($it.Risk)")
 [void]$md.AppendLine("- note:$($it.Note)")
 [void]$md.AppendLine('```powershell')
 [void]$md.AppendLine($it.CleanScript.Trim())
 [void]$md.AppendLine('```')
}

[void]$md.AppendLine('')
[void]$md.AppendLine('## 3. scan file(only, recommendation script)')
[void]$md.AppendLine('')
[void]$md.AppendLine('| rank | size | Path | recommendation |')
[void]$md.AppendLine('|---:|---:|---|---|')
$i=1
foreach ($f in $largeFiles) {
 [void]$md.AppendLine(('| {0} | {1} | `{2}` | confirm first file/virtual disk/installer;recommendationmove to another drive manual. |' -f $i, (Format-Size $f.Length), $f.FullName))
 $i++
}

[void]$md.AppendLine('')
[void]$md.AppendLine('## 4. C directory(, clean)')
[void]$md.AppendLine('')
[void]$md.AppendLine('| rank | size | Path | |')
[void]$md.AppendLine('|---:|---:|---|---|')
$i=1
foreach ($d in $topDirs) {
 [void]$md.AppendLine(('| {0} | {1} | `{2}` | ;Program Files/Windows/user directorydo not. |' -f $i, $d.Size, $d.Path))
 $i++
}

[void]$md.AppendLine('')
[void]$md.AppendLine('## 5. securitycleanrecommendation')
[void]$md.AppendLine('')
[void]$md.AppendLine('1. Windows : -> system -> storage -> tempfile.recommendationselect"tempfile/thumbnail/delivery optimizationfile".')
[void]$md.AppendLine('2. do notmanual `C:\Windows\WinSxS`. system clean, Run:')
[void]$md.AppendLine('```powershell')
[void]$md.AppendLine('DISM.exe /Online /Cleanup-Image /StartComponentCleanup')
[void]$md.AppendLine('```')
[void]$md.AppendLine('3., Run commandrelease `hiberfil.sys`(disable hibernation/Start):')
[void]$md.AppendLine('```powershell')
[void]$md.AppendLine('powercfg -h off')
[void]$md.AppendLine('```')
[void]$md.AppendLine('4. large file///Directoryrecommendationmove to another drive, recommendation scriptbulk delete.')

Set-Content -LiteralPath $report -Value $md.ToString() -Encoding UTF8
Write-Host "REPORT=$report"
Write-Host "CANDIDATES=$($items.Count)"
Write-Host "TOTAL_CANDIDATE_SIZE=$(Format-Size $totalCandidates)"
$items | Select-Object -First 15 Name,Size,Path,Type | Format-Table -AutoSize
