@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

REM ============================================================
REM  FFmpeg Format Converter
REM  Converts media files to common formats using FFmpeg.
REM  Output goes to the same directory with _converted suffix.
REM  Original file is never overwritten.
REM ============================================================

where ffmpeg >nul 2>nul
if errorlevel 1 (
    echo [ERROR] ffmpeg not found. Please install FFmpeg and add it to PATH.
    echo         Download: https://ffmpeg.org/download.html
    goto :end
)

echo.
echo   ===================================
echo    FFmpeg Format Converter
echo   ===================================
echo.
echo   Supported output formats:
echo   -----------------------------------
echo    Video:  mp4  mkv  avi  mov  webm  flv  wmv  m4v  ts
echo    Audio:  mp3  wav  flac  aac  ogg  wma  m4a  opus
echo    Image:  gif  webp  png  jpg  bmp  tiff
echo   -----------------------------------
echo.

REM --- Source file ---
set "SRC="
set /p "SRC=Source file path: "
set "SRC=!SRC:"=!"

if not exist "!SRC!" (
    echo [ERROR] File not found: !SRC!
    goto :end
)

REM --- Target format ---
set "TARGET="
set /p "TARGET=Target format (e.g. mp4, gif, mp3): "
set "TARGET=!TARGET:.=!"
set "TARGET=!TARGET: =!"

if "!TARGET!"=="" (
    echo [ERROR] Format cannot be empty.
    goto :end
)

REM --- Parse source file info ---
for %%F in ("!SRC!") do (
    set "FDIR=%%~dpF"
    set "FNAME=%%~nF"
)

set "OUT=!FDIR!!FNAME!_converted.!TARGET!"

echo.
echo   Source:  !SRC!
echo   Output:  !OUT!
echo.

REM --- Confirmation ---
set "CONFIRM="
set /p "CONFIRM=Start conversion? (Y/N): "
if /i not "!CONFIRM!"=="Y" (
    echo Cancelled.
    goto :end
)

echo.
echo [RUNNING] Converting...

REM --- Choose FFmpeg flags based on target format ---
set "FFFLAGS="

if /i "!TARGET!"=="mp4"  set "FFFLAGS=-c:v libx264 -preset medium -crf 23 -c:a aac -b:a 192k"
if /i "!TARGET!"=="mkv"  set "FFFLAGS=-c:v libx264 -preset medium -crf 23 -c:a aac -b:a 192k"
if /i "!TARGET!"=="avi"  set "FFFLAGS=-c:v mpeg4 -q:v 5 -c:a mp3 -b:a 192k"
if /i "!TARGET!"=="mov"  set "FFFLAGS=-c:v libx264 -preset medium -crf 23 -c:a aac -b:a 192k -f mov"
if /i "!TARGET!"=="webm" set "FFFLAGS=-c:v libvpx-vp9 -crf 30 -b:v 0 -c:a libopus -b:a 128k"
if /i "!TARGET!"=="flv"  set "FFFLAGS=-c:v flv -q:v 5 -c:a mp3 -b:a 192k"
if /i "!TARGET!"=="wmv"  set "FFFLAGS=-c:v wmv2 -q:v 5 -c:a wmav2 -b:a 192k"
if /i "!TARGET!"=="m4v"  set "FFFLAGS=-c:v libx264 -preset medium -crf 23 -c:a aac -b:a 192k"
if /i "!TARGET!"=="ts"   set "FFFLAGS=-c:v libx264 -preset medium -crf 23 -c:a aac -b:a 192k -f mpegts"
if /i "!TARGET!"=="mp3"  set "FFFLAGS=-vn -c:a libmp3lame -b:a 320k"
if /i "!TARGET!"=="wav"  set "FFFLAGS=-vn -c:a pcm_s16le"
if /i "!TARGET!"=="flac" set "FFFLAGS=-vn -c:a flac"
if /i "!TARGET!"=="aac"  set "FFFLAGS=-vn -c:a aac -b:a 256k"
if /i "!TARGET!"=="ogg"  set "FFFLAGS=-vn -c:a libvorbis -b:a 192k"
if /i "!TARGET!"=="wma"  set "FFFLAGS=-vn -c:a wmav2 -b:a 192k"
if /i "!TARGET!"=="m4a"  set "FFFLAGS=-vn -c:a aac -b:a 256k"
if /i "!TARGET!"=="opus" set "FFFLAGS=-vn -c:a libopus -b:a 128k"
if /i "!TARGET!"=="gif"  set "FFFLAGS=-vf fps=12,scale=480:-1:flags=lanczos -c:v gif"
if /i "!TARGET!"=="webp" set "FFFLAGS=-vframes 1 -c:v libwebp -quality 90"
if /i "!TARGET!"=="png"  set "FFFLAGS=-vframes 1 -c:v png"
if /i "!TARGET!"=="jpg"  set "FFFLAGS=-vframes 1 -c:v mjpeg -q:v 2"
if /i "!TARGET!"=="bmp"  set "FFFLAGS=-vframes 1 -c:v bmp"
if /i "!TARGET!"=="tiff" set "FFFLAGS=-vframes 1 -c:v tiff"

ffmpeg -y -i "!SRC!" !FFFLAGS! "!OUT!"

if errorlevel 1 (
    echo.
    echo [FAILED] Conversion error. Check format compatibility or ffmpeg output above.
) else (
    echo.
    echo [DONE] Output: !OUT!
)

:end
echo.
endlocal
pause
