@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

REM ============================================================
REM FFmpeg Format Converter
REM Input source file path + target format, output to same dir
REM Output filename gets _replaced suffix, does not overwrite original
REM ============================================================

echo ===============================================
echo FFmpeg formatconverter
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

set "TARGET="
set /p "TARGET=Enter format(mp4/mkv/avi/mov/mp3): "
set "TARGET=!TARGET:.=!"
if "!TARGET!"=="" (
 echo [ERROR] formatcannot be empty.
 goto :end
)

for %%F in ("!SRC!") do (
 set "FDIR=%%~dpF"
 set "FNAME=%%~nF"
)
set "OUT=!FDIR!!FNAME!_replaced.!TARGET!"

echo.
echo Source file: !SRC!
echo Output: !OUT!
echo.

set "CONFIRM="
set /p "CONFIRM=Startconvert? (Y/N): "
if /i not "!CONFIRM!"=="Y" goto :Cancelled.

echo.
echo [RUNNING] convert...
ffmpeg -i "!SRC!" "!OUT!"
if errorlevel 1 (
 echo.
 echo [FAILED] convertERROR,checkformatcompatibility.
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