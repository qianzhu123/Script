@echo off
chcp 65001 >nul
setlocal

REM Launcher for merge_markdown.ps1
REM Merges Markdown documents or folders into a single folder
REM (README.md + assets/) with relative image paths rewritten to assets/.

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%..\ps1\merge_markdown.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"

endlocal
pause
