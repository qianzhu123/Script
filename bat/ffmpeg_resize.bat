@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

REM ============================================================
REM FFmpeg Resolution Resizer
REM Input source file + target resolution, output to same dir
REM Output filename gets _replaced suffix, does not overwrite original
REM ============================================================

echo ===============================================
echo FFmpeg resolution tool
echo ===============================================
echo.

where ffmpeg >nul 2>nul
if errorlevel 1 (
 echo [ERROR] ffmpeg was not found, add it to PATH.
 goto :end
)

set "SRC="
set /p "SRC=Enter Source filePath: "
set "SRC=!SRC:"=!"
if not exist "!SRC!" (
 echo [ERROR] filenot found: !SRC!
 goto :end
)

echo.
echo resolutionExample: 1920x1080 1280x720 854x480
echo -2, 1280x-2
echo.
set "RES="
set /p "RES=Enter resolution(WxH): "
if "!RES!"=="" (
 echo [ERROR] resolutioncannot be empty.
 goto :end
)
set "SCALE=!RES:x=:!"

for %%F in ("!SRC!") do (
 set "FDIR=%%~dpF"
 set "FNAME=%%~nF"
 set "FEXT=%%~xF"
)
set "OUT=!FDIR!!FNAME!_replaced!FEXT!"

echo.
echo Source file: !SRC!
echo resolution: !RES!
echo Output: !OUT!
echo.

set "CONFIRM="
set /p "CONFIRM=starting? (Y/N): "
if /i not "!CONFIRM!"=="Y" goto :Cancelled.

echo.
echo [RUNNING] resolution...
ffmpeg -i "!SRC!" -vf "scale=!SCALE!" "!OUT!"
if errorlevel 1 (
 echo.
 echo [FAILED] processing error.
) else (
 echo.
 echo [DONE] Output: !OUT!
)
goto :end

:Cancelled.
echo Cancelled.led.

:end
echo.
endlocal
pause