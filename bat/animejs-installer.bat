@echo off
chcp 65001 >nul
title Anime.js project installer

echo.
echo ========================================
echo Anime.js project installer
echo ========================================
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0..\ps1\animejs-installer.ps1"

exit /b %errorlevel%