@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>nul

echo ============================================================
echo   每日磁盘清理 - C盘 (仅扫描，不删除)
echo   [v2] 优化版: robocopy + 超时 + 跳过全盘扫描
echo ============================================================

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PROJECT_DIR=%%~fI"
if not defined DAILY_PROJECT_DIR set "DAILY_PROJECT_DIR=%PROJECT_DIR%"
if not defined DAILY_OUTPUT_DIR set "DAILY_OUTPUT_DIR=%PROJECT_DIR%\output"
if not defined DAILY_TEMP_DIR set "DAILY_TEMP_DIR=%PROJECT_DIR%\temp"

set "REPORT_DIR=%DAILY_OUTPUT_DIR%\disk-clean"
if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%" >nul 2>nul
if not exist "%DAILY_TEMP_DIR%" mkdir "%DAILY_TEMP_DIR%" >nul 2>nul
set "REPORT=%REPORT_DIR%\clean-c.md"

echo [信息] 报告: %REPORT%
echo.

rem --- Find PowerShell ---
set "PS_EXE=powershell.exe"
where powershell.exe >nul 2>nul
if errorlevel 1 (
    where pwsh.exe >nul 2>nul
    if errorlevel 1 (
        echo [错误] 未找到powershell.exe或pwsh.exe。
        pause
        exit /b 3
    ) else set "PS_EXE=pwsh.exe"
)

rem --- Run inline optimized scan via PowerShell ---
"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
"$drv='C:'; $root='C:\'; $report='%REPORT%'; $timeoutSec=300; $sw=[System.Diagnostics.Stopwatch]::StartNew();" ^
"function fmt($b){if($b-ge1TB){'{0:N2}TB'-f($b/1TB)}elseif($b-ge1GB){'{0:N2}GB'-f($b/1GB)}elseif($b-ge1MB){'{0:N2}MB'-f($b/1MB)}else{'{0:N0}B'-f$b}}" ^
"function esc($t){if(!$t){''}else{$t.Replace('|','\|').Replace(\""`r\"",' ').Replace(\""`n\"",' ')}}" ^
"function gs($p){" ^
"  if(!(Test-Path $p)){return@{B=0L;F=0;Ok=0}}" ^
"  try{$it=Get-Item $p -Force -EA Stop;if(!$it.PSIsContainer){return@{B=[int64]$it.Length;F=1;Ok=1}}}catch{return@{B=0L;F=0;Ok=0}}" ^
"  $tmp=New-TemporaryFile;" ^
"  try{" ^
"    $null=& robocopy.exe $p \\localhost\C$\__x__ /L /E /BYTES /NP /NFL /NDL /NJH /R:0 /W:0 /XJ *>$tmp;" ^
"    $txt=Get-Content $tmp -Raw -EA 0;" ^
"    $sz=0L;$fc=0;" ^
"    if($txt-match'Bytes\s*:\s*([\d,]+)'){$sz=[int64]($Matches[1]-replace',','')}" ^
"    if($txt-match'Files\s*:\s*([\d,]+)'){$fc=[int]($Matches[1]-replace',','')}" ^
"    return@{B=$sz;F=$fc;Ok=1}" ^
"  }catch{return@{B=0L;F=0;Ok=0}}" ^
"  finally{Remove-Item $tmp -Force -EA 0}" ^
"}" ^
"" ^
"Write-Host '[阶段A] 已知大容量路径 (robocopy)...' -ForegroundColor Green;" ^
"[System.Collections.Generic.List[pscustomobject]]$cands=@();" ^
"[System.Collections.Generic.List[string]]$errs=@();" ^

set "EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXIT_CODE%"=="0" (
    echo [完成] C盘任务完成。报告: %REPORT%
) else (
    echo [失败] 退出码: %EXIT_CODE%
)
if /i not "%DAILY_WEB_TERMINAL%"=="1" if /i not "%DAILY_WEB_NO_PAUSE%"=="1" pause
exit /b %EXIT_CODE%