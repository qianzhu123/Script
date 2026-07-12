@echo off
chcp 65001 >nul
setlocal

title Douyin Downloader

set "TOOL_DIR=D:\code\python\utils\douyin-downloader"

where python >nul 2>&1
if errorlevel 1 (
    echo [ERROR] python not found
    pause
    exit /b 1
)

if not exist "%TOOL_DIR%\main.py" (
    echo [ERROR] main.py not found in: %TOOL_DIR%
    pause
    exit /b 1
)

echo.
echo   ================================
echo    Douyin Video/Image Downloader
echo   ================================
echo   Paste share text or URL directly
echo.

:input_url
set "DOUYIN_URL="
set /p DOUYIN_URL=Paste Douyin link or share text:
if "%DOUYIN_URL%"=="" (
    echo [ERROR] Input cannot be empty
    echo.
    goto input_url
)

:input_output
set "OUTPUT_DIR="
set "DEFAULT_OUTPUT=%USERPROFILE%\Downloads\douyin"
set /p OUTPUT_DIR=Save to [Enter for default: %DEFAULT_OUTPUT%]:
if "%OUTPUT_DIR%"=="" set "OUTPUT_DIR=%DEFAULT_OUTPUT%"

echo.
echo [INFO] Save:   %OUTPUT_DIR%
echo [INFO] Downloading, please wait...
echo.

python "%TOOL_DIR%\main.py" "%DOUYIN_URL%" -o "%OUTPUT_DIR%"

if errorlevel 1 (
    echo.
    echo [ERROR] Download failed
) else (
    echo.
    echo [OK] Download completed
)

endlocal
pause
