@echo off
chcp 65001 >nul
setlocal

REM BongoCat DLL Updater
REM Find the newest Assembly-CSharp.dll downloaded within the last 24 hours
REM under the user's Downloads folder and overwrite the one in the game folder.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\ps1\bongocat_dll_update.ps1"

endlocal
pause
