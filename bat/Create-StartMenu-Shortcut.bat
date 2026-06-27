@echo off
setlocal EnableExtensions DisableDelayedExpansion

title copyshortcut starting

set "STARTMENU=C:\Users\Light\AppData\Roaming\Microsoft\Windows\Start Menu\Programs"

echo.
echo === copyshortcut starting ===
echo target location: %STARTMENU%
echo.
echo Enter.lnkfile fullPath.
echo path.
echo.

set /p "SOURCE=shortcutPath: "

if not defined SOURCE (
 echo InputPath.
 pause
 exit /b 1
)

set "SOURCE=%SOURCE:"=%"

if not defined SOURCE (
 echo InputvalidPath.
 pause
 exit /b 1
)

if /I not "%SOURCE:~-4%"==".lnk" (
 echo file.lnkshortcut.
 pause
 exit /b 1
)

if not exist "%SOURCE%" (
 echo filedoes not exist:
 echo %SOURCE%
 pause
 exit /b 1
)

if not exist "%STARTMENU%" (
 echo Target file does not exist:
 echo %STARTMENU%
 pause
 exit /b 1
)

for %%I in ("%SOURCE%") do set "FILENAME=%%~nxI"
set "DEST=%STARTMENU%\%FILENAME%"

copy /Y "%SOURCE%" "%DEST%" >nul
set "ERR=%ERRORLEVEL%"

if not "%ERR%"=="0" (
 echo copyshortcutFailed.
 pause
 exit /b %ERR%
)

echo.
echo shortcutcopySuccess:
echo %DEST%
echo.
echo Win shortcut.
echo.
pause
exit /b 0
