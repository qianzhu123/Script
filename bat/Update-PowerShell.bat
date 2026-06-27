@echo off
setlocal

set "WINGET=winget"
set "WINGET_FOUND=0"
where winget >nul 2>nul
if errorlevel 1 (
 for /f "delims=" %%I in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source"') do set "WINGET=%%I"
 if exist "%WINGET%" set "WINGET_FOUND=1"
 if "%WINGET_FOUND%"=="0" (
 if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe" (
 set "WINGET=%LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe"
 set "WINGET_FOUND=1"
)
)
) else (
 set "WINGET_FOUND=1"
)

if "%WINGET_FOUND%"=="0" (
 echo not foundwinget.
 echo Microsoft StoreinstallerApp Installer retry.
 echo.
 pause
 exit /b 1
)

echo Updatewinget...
echo command: "%WINGET%" source update
echo.
"%WINGET%" source update
echo.

echo winget installerPowerShell:
echo command: "%WINGET%" list --id Microsoft.PowerShell --source winget
echo.
"%WINGET%" list --id Microsoft.PowerShell --source winget
echo.

echo winget PowerShell:
echo command: "%WINGET%" show --id Microsoft.PowerShell --source winget --versions
echo.
"%WINGET%" show --id Microsoft.PowerShell --source winget --versions
echo.

echo wingetUpdatePowerShell...
echo command: "%WINGET%" upgrade --id Microsoft.PowerShell --source winget --include-unknown
echo.
"%WINGET%" upgrade --id Microsoft.PowerShell --source winget --include-unknown
echo.
echo UpdatecommandDone, check.
pause
