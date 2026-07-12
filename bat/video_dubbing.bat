@echo off
chcp 65001 >nul
setlocal

REM Launch the video dubbing PowerShell script
powershell -ExecutionPolicy Bypass -File "%~dp0..\ps1\video_dubbing.ps1" %*

endlocal
pause
