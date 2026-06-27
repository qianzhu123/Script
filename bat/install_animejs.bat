@echo off
chcp 65001 >nul

powershell.exe -ExecutionPolicy Bypass -File "%~dp0..\ps1\install_animejs.ps1"

pause