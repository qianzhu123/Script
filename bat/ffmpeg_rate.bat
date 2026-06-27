@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

REM ============================================================
REM FFmpeg frame rate and bitrate tool
REM Input source file, optional FPS/video bitrate/audio bitrate params
REM Output to same dir, filename gets _replaced suffix, does not overwrite original
REM ============================================================

echo ===============================================
echo FFmpeg frame rate and bitrate tool
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
echo leave blank(press Enterskip)
echo.
set "FPS="
set /p "FPS=frame rate(30/60): "
set "VB="
set /p "VB=videobitrate(2M/4000k): "
set "AB="
set /p "AB=audiobitrate(128k/192k): "

set "ARGS="
if not "!FPS!"=="" set "ARGS=!ARGS! -r !FPS!"
if not "!VB!"=="" set "ARGS=!ARGS! -b:v !VB!"
if not "!AB!"=="" set "ARGS=!ARGS! -b:a !AB!"

if "!ARGS!"=="" (
 echo [ERROR] arguments.
 goto :end
)

for %%F in ("!SRC!") do (
 set "FDIR=%%~dpF"
 set "FNAME=%%~nF"
 set "FEXT=%%~xF"
)
set "OUT=!FDIR!!FNAME!_replaced!FEXT!"

echo.
echo Source file: !SRC!
echo arguments: !ARGS!
echo Output: !OUT!
echo.

set "CONFIRM="
set /p "CONFIRM=starting? (Y/N): "
if /i not "!CONFIRM!"=="Y" goto :Cancelled.

echo.
echo [RUNNING]...
ffmpeg -i "!SRC!"!ARGS! "!OUT!"
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