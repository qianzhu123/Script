@echo off
chcp 65001 >nul
echo Clearing Explorer Open With history...
taskkill /f /im explorer.exe >nul 2>&1
timeout /t 1 /nobreak >nul
del /f /s /q "%appdata%\Microsoft\Windows\Recent\AutomaticDestinations\*" >nul 2>&1
del /f /s /q "%appdata%\Microsoft\Windows\Recent\CustomDestinations\*" >nul 2>&1
start explorer.exe
echo Done. Right-click a.txt file, choose Open with, and select Code.exe manually if needed.
pause
