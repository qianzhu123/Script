@echo off
chcp 65001 >nul 2>&1
setlocal

REM FFmpeg Image Processor PS1 Launcher
REM Calls PowerShell script: ps1/ffmpeg_image.ps1

set PS1FILE=%~dp0..\ps1\ffmpeg_image.ps1

if not exist "%PS1FILE%" (
    echo [错误] 未找到脚本: "%PS1FILE%"
    endlocal
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1FILE%"

endlocal