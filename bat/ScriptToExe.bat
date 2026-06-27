@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>nul

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PROJECT_DIR=%%~fI"
set "PS1_SCRIPT=%PROJECT_DIR%\ps1\ScriptToExe.ps1"

if not exist "%PS1_SCRIPT%" (
  echo [错误] 未找到PowerShell转换器:
  echo %PS1_SCRIPT%
  set "EXIT_CODE=2"
  goto END
)

set "SOURCE_PATH=%~1"
if not defined SOURCE_PATH (
  set /p "SOURCE_PATH=请输入源脚本路径(.bat/.cmd/.ps1/.py): "
)
set "SOURCE_PATH=%SOURCE_PATH:"=%"
if not defined SOURCE_PATH (
  echo [错误] 必须提供源脚本路径。
  set "EXIT_CODE=3"
  goto END
)

set "ICON_PATH=%~2"
if "%~2"=="" if "%~3"=="" (
  set /p "ICON_PATH=请输入ICO图标路径，或直接回车使用默认图标: "
)
set "ICON_PATH=%ICON_PATH:"=%"

set "OUTPUT_NAME=%~3"
if "%~3"=="" (
  set /p "OUTPUT_NAME=请输入输出exe名称，或直接回车使用源脚本名: "
)
set "OUTPUT_NAME=%OUTPUT_NAME:"=%"

set "POWERSHELL_EXE=powershell.exe"
where powershell.exe >nul 2>nul
if errorlevel 1 (
  where pwsh.exe >nul 2>nul
  if errorlevel 1 (
    echo [错误] 未找到powershell.exe或pwsh.exe。
    set "EXIT_CODE=4"
    goto END
  )
  set "POWERSHELL_EXE=pwsh.exe"
)

if defined ICON_PATH (
  if defined OUTPUT_NAME (
    "%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1_SCRIPT%" -ScriptPath "%SOURCE_PATH%" -IconPath "%ICON_PATH%" -OutputName "%OUTPUT_NAME%"
  ) else (
    "%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1_SCRIPT%" -ScriptPath "%SOURCE_PATH%" -IconPath "%ICON_PATH%"
  )
) else (
  if defined OUTPUT_NAME (
    "%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1_SCRIPT%" -ScriptPath "%SOURCE_PATH%" -OutputName "%OUTPUT_NAME%"
  ) else (
    "%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1_SCRIPT%" -ScriptPath "%SOURCE_PATH%"
  )
)
set "EXIT_CODE=%ERRORLEVEL%"

:END
echo.
if "%EXIT_CODE%"=="0" (
  echo [完成] 可执行文件和快捷方式已创建在源脚本旁边。
) else (
  echo [失败] 转换失败，退出码: %EXIT_CODE%
)
if /i not "%DAILY_WEB_TERMINAL%"=="1" if /i not "%DAILY_WEB_NO_PAUSE%"=="1" pause
exit /b %EXIT_CODE%
