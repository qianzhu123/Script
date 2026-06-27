@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "PS1_SCRIPT=%SCRIPT_DIR%..\ps1\Install-Remotion.ps1"

if not exist "%PS1_SCRIPT%" (
  echo 未找到PowerShell安装器:
  echo %PS1_SCRIPT%
  pause
  exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo.
  echo Remotion安装失败，退出码: %EXIT_CODE%
  pause
)

exit /b %EXIT_CODE%
