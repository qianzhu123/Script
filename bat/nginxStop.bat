@echo off
title Nginx - Stop...
chcp 65001 >nul

echo [1/2] stopping...
nginx.exe -s quit

:: 2seconds processexit
timeout /t 2 >nul

:: check process toolclean
tasklist /fi "imagename eq nginx.exe" | findstr /i "nginx.exe" > nul
if %errorlevel% equ 0 (
 echo [2/2] clean process...
 taskkill /f /t /im nginx.exe >nul 2>&1
)

echo.
echo [DONE] Nginx service securityclose.
timeout /t 3 >nul
exit