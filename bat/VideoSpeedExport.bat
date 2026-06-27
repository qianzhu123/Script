@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS1_PATH=%SCRIPT_DIR%..\ps1\VideoSpeedExport.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
 echo.
 echo scriptFailed,exit code %EXIT_CODE%.
)

echo.
pause
exit /b %EXIT_CODE%
