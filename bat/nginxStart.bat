@echo off
title Nginx - starting...
chcp 65001 >nul

:: project 
set TARGET_URL=http://localhost

echo [1/2] check Nginx status...
tasklist /fi "imagename eq nginx.exe" | findstr /i "nginx.exe" > nul
if %errorlevel% equ 0 (
 echo [!] Nginx Run,skipstarting.
) else (
 echo [2/2] Start Nginx service...
 start nginx.exe
 if %errorlevel% neq 0 (
 echo [ERROR] Nginx StartFailed,checkconfigfile
 pause
 exit /b
)
)

echo.
echo [Success] open: %TARGET_URL%
start %TARGET_URL%

:: 3seconds automaticclosescript 
timeout /t 3 >nul
exit