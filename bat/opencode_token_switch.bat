@echo off
chcp 65001 >nul
setlocal

REM Securely replace only the apiKey value in the global OpenCode JSONC config.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\ps1\opencode_token_switch.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" echo OpenCode token switch failed.
pause

endlocal & exit /b %EXIT_CODE%
