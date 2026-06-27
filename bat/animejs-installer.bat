@echo off
chcp 65001 >nul
title Anime.js 项目安装器

echo.
echo ========================================
echo      Anime.js 项目安装器
echo ========================================
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0..\ps1\animejs-installer.ps1"

exit /b %errorlevel%