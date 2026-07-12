@echo off
chcp 65001 >nul
setlocal

powershell -ExecutionPolicy Bypass -File "%~dp0..\ps1\copy_design_md.ps1"

endlocal
pause
