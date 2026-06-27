@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>nul
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PROJECT_DIR=%%~fI"
if not defined DAILY_PROJECT_DIR set "DAILY_PROJECT_DIR=%PROJECT_DIR%"
if not defined DAILY_OUTPUT_DIR set "DAILY_OUTPUT_DIR=%PROJECT_DIR%\output"
if not defined DAILY_TEMP_DIR set "DAILY_TEMP_DIR=%PROJECT_DIR%\temp"
set "PS1=%PROJECT_DIR%\ps1\Scan-CleanReport.ps1"
set "REPORT_DIR=%DAILY_OUTPUT_DIR%\disk-clean"
set "EXIT_CODE=0"
if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%" >nul 2>nul
if not exist "%DAILY_TEMP_DIR%" mkdir "%DAILY_TEMP_DIR%" >nul 2>nul
set "REPORT=%REPORT_DIR%\clean-d.md"
echo ============================================================
echo  每日磁盘清理 - D盘 (仅扫描，不删除)
echo ============================================================
echo [信息] 报告: %REPORT%
echo [信息] 临时目录: %DAILY_TEMP_DIR%
echo.
if not exist "%PS1%" (
  echo [错误] 未找到PowerShell脚本: %PS1%
  set "EXIT_CODE=2"
  goto END
)
set "POWERSHELL_EXE=powershell.exe"
where powershell.exe >nul 2>nul
if errorlevel 1 (
  where pwsh.exe >nul 2>nul
  if errorlevel 1 (
    echo [错误] 未找到powershell.exe或pwsh.exe。
    set "EXIT_CODE=3"
    goto END
  ) else set "POWERSHELL_EXE=pwsh.exe"
)
"%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -DriveLetter D -ReportPath "%REPORT%" -TempDir "%DAILY_TEMP_DIR%"
set "EXIT_CODE=%ERRORLEVEL%"
:END
echo.
if "%EXIT_CODE%"=="0" (
  echo [完成] D盘任务完成。报告: %REPORT%
) else (
  echo [失败] D盘任务失败。退出码: %EXIT_CODE%
)
if /i not "%DAILY_WEB_TERMINAL%"=="1" if /i not "%DAILY_WEB_NO_PAUSE%"=="1" pause
exit /b %EXIT_CODE%


