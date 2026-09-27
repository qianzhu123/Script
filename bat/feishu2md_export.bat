@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM Feishu to Markdown Export
REM Credentials are loaded from a private local file.
REM Credential file format:
REM   line 1: app id
REM   line 2: app secret
REM
REM Input supports:
REM   1. One Feishu URL
REM   2. Multiple Feishu URLs pasted together with any separator text
REM   3. A local text file path that contains Feishu URLs
REM URLs are extracted by matching Feishu links that start with https://.
REM ============================================================

set "CREDENTIAL_FILE=D:/data/privatedata/api/feishu.txt"
set "DEFAULT_OUTPUT_DIR=C:/Users/Light/Downloads"

set "INPUT_VALUE=%~1"
set "OUTPUT_DIR=%~2"
set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%..\"
set "TOOL_MODE="
set "TOOL_EXE="
set "GO_PACKAGE=github.com/Wsine/feishu2md/cmd@main"
set "FEISHU_APP_ID="
set "FEISHU_APP_SECRET="
set "LINE_NO=0"
set "TOTAL_COUNT=0"
set "FAILED_COUNT=0"
set "TMP_CONFIG_LOG=%TEMP%\feishu2md_config_%RANDOM%_%RANDOM%.log"
set "TMP_INPUT_FILE=%TEMP%\feishu2md_input_%RANDOM%_%RANDOM%.txt"
set "TMP_URL_FILE=%TEMP%\feishu2md_urls_%RANDOM%_%RANDOM%.txt"

echo ========================================
echo Feishu to Markdown Export
echo ========================================
echo.

if not exist "%CREDENTIAL_FILE%" (
    echo Error: credential file was not found.
    echo Path: "%CREDENTIAL_FILE%"
    echo The file must contain the app id on line 1 and the app secret on line 2.
    pause
    exit /b 1
)

for /f "usebackq tokens=* delims=" %%A in ("%CREDENTIAL_FILE%") do (
    set /a LINE_NO+=1
    if !LINE_NO! EQU 1 set "FEISHU_APP_ID=%%A"
    if !LINE_NO! EQU 2 set "FEISHU_APP_SECRET=%%A"
)

if "%FEISHU_APP_ID%"=="" (
    echo Error: app id is missing in credential file line 1.
    echo Path: "%CREDENTIAL_FILE%"
    pause
    exit /b 1
)

if "%FEISHU_APP_SECRET%"=="" (
    echo Error: app secret is missing in credential file line 2.
    echo Path: "%CREDENTIAL_FILE%"
    pause
    exit /b 1
)

if "%INPUT_VALUE%"=="" (
    set /p "INPUT_VALUE=Feishu URL(s) or input file path: "
)

if "%INPUT_VALUE%"=="" (
    echo.
    echo Error: at least one Feishu URL or an input file path is required.
    pause
    exit /b 1
)

if "%OUTPUT_DIR%"=="" (
    set /p "OUTPUT_DIR=Output directory [default: %DEFAULT_OUTPUT_DIR%]: "
)

if "%OUTPUT_DIR%"=="" (
    set "OUTPUT_DIR=%DEFAULT_OUTPUT_DIR%"
)

if not exist "%OUTPUT_DIR%" (
    mkdir "%OUTPUT_DIR%"
    if errorlevel 1 (
        echo.
        echo Error: failed to create output directory.
        pause
        exit /b 1
    )
)

REM Resolve feishu2md executable from local locations or PATH.
if exist "%SCRIPT_DIR%feishu2md.exe" (
    set "TOOL_MODE=exe"
    set "TOOL_EXE=%SCRIPT_DIR%feishu2md.exe"
)

if not defined TOOL_MODE if exist "%PROJECT_ROOT%feishu2md.exe" (
    set "TOOL_MODE=exe"
    set "TOOL_EXE=%PROJECT_ROOT%feishu2md.exe"
)

if not defined TOOL_MODE if exist "%PROJECT_ROOT%tools\feishu2md.exe" (
    set "TOOL_MODE=exe"
    set "TOOL_EXE=%PROJECT_ROOT%tools\feishu2md.exe"
)

if not defined TOOL_MODE (
    where feishu2md >nul 2>nul
    if not errorlevel 1 (
        set "TOOL_MODE=exe"
        set "TOOL_EXE=feishu2md"
    )
)

if not defined TOOL_MODE (
    where go >nul 2>nul
    if not errorlevel 1 set "TOOL_MODE=go"
)

if not defined TOOL_MODE (
    echo.
    echo Error: feishu2md.exe or Go was not found.
    echo Put feishu2md.exe in one of these locations:
    echo   %SCRIPT_DIR%
    echo   %PROJECT_ROOT%
    echo   %PROJECT_ROOT%tools\
    echo Or add feishu2md.exe or Go to PATH.
    pause
    exit /b 1
)

REM Build a temporary input text file.
if exist "%INPUT_VALUE%" (
    copy /y "%INPUT_VALUE%" "%TMP_INPUT_FILE%" >nul
    if errorlevel 1 (
        echo.
        echo Error: failed to read input file.
        echo Path: "%INPUT_VALUE%"
        pause
        exit /b 1
    )
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-Content -LiteralPath $env:TMP_INPUT_FILE -Value $env:INPUT_VALUE -Encoding UTF8" >nul 2>nul
    if errorlevel 1 (
        echo.
        echo Error: failed to prepare input text.
        pause
        exit /b 1
    )
)

REM Extract Feishu URLs. Separators can be any characters.
REM The regex intentionally matches known Feishu path styles instead of relying on commas or spaces.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$text = Get-Content -LiteralPath '%TMP_INPUT_FILE%' -Raw; $pattern = 'https://[A-Za-z0-9.-]+/(?:(?:wiki/settings|drive/folder|wiki|docx|docs|base|sheets|mindnotes|file)/[A-Za-z0-9][A-Za-z0-9_./?=%%&:#-]*)'; [regex]::Matches($text, $pattern) ^| ForEach-Object { $_.Value.Trim().TrimEnd(''', '"', ',', ';', ':', '.', ')', ']', '}', '，', '；', '。', '）', '】', '》') } ^| Select-Object -Unique ^| Set-Content -LiteralPath '%TMP_URL_FILE%' -Encoding UTF8" >nul 2>nul
if errorlevel 1 (
    echo.
    echo Error: failed to extract URLs from input.
    del "%TMP_INPUT_FILE%" >nul 2>nul
    pause
    exit /b 1
)

del "%TMP_INPUT_FILE%" >nul 2>nul

if not exist "%TMP_URL_FILE%" (
    echo.
    echo Error: no valid Feishu URL was found.
    pause
    exit /b 1
)

for %%A in ("%TMP_URL_FILE%") do if %%~zA EQU 0 (
    echo.
    echo Error: no valid Feishu URL was found.
    del "%TMP_URL_FILE%" >nul 2>nul
    pause
    exit /b 1
)

echo.
echo Loading credentials from private file...
echo Saving credentials for feishu2md...

if /I "%TOOL_MODE%"=="go" (
    go run %GO_PACKAGE% config --appId "%FEISHU_APP_ID%" --appSecret "%FEISHU_APP_SECRET%" > "%TMP_CONFIG_LOG%" 2>&1
) else (
    "%TOOL_EXE%" config --appId "%FEISHU_APP_ID%" --appSecret "%FEISHU_APP_SECRET%" > "%TMP_CONFIG_LOG%" 2>&1
)

if errorlevel 1 (
    echo.
    echo Error: failed to save credentials.
    echo The config command log was saved to:
    echo "%TMP_CONFIG_LOG%"
    echo Do not share that log because it may contain credentials.
    del "%TMP_URL_FILE%" >nul 2>nul
    pause
    exit /b 1
)

del "%TMP_CONFIG_LOG%" >nul 2>nul

echo.
echo Running export...
echo Output: "%OUTPUT_DIR%"
echo Tool: "%TOOL_MODE%"
echo.

for /f "usebackq tokens=* delims=" %%U in ("%TMP_URL_FILE%") do (
    set "CURRENT_URL=%%U"
    call :TrimVar CURRENT_URL
    if defined CURRENT_URL (
        set /a TOTAL_COUNT+=1
        call :ExportOne
        if errorlevel 1 (
            set /a FAILED_COUNT+=1
        )
    )
)

del "%TMP_URL_FILE%" >nul 2>nul

echo.
echo ========================================
echo Export summary
echo ========================================
echo Total URLs: !TOTAL_COUNT!
echo Failed URLs: !FAILED_COUNT!
echo Output directory:
echo "%OUTPUT_DIR%"
echo.

if !TOTAL_COUNT! EQU 0 (
    echo Error: no valid URL was found.
    pause
    exit /b 1
)

if !FAILED_COUNT! GTR 0 (
    echo Export finished with errors.
    pause
    exit /b 1
)

echo Export completed successfully.
pause
exit /b 0

:ExportOne
set "CURRENT_MODE=single"
set "URL_CHECK=!CURRENT_URL!"
if not "!URL_CHECK:/drive/folder/=!"=="!URL_CHECK!" set "CURRENT_MODE=batch"
if not "!URL_CHECK:/wiki/settings/=!"=="!URL_CHECK!" set "CURRENT_MODE=wiki"

echo ----------------------------------------
echo URL: "!CURRENT_URL!"
echo Mode: "!CURRENT_MODE!"

if /I "%TOOL_MODE%"=="go" (
    if /I "!CURRENT_MODE!"=="batch" (
        go run %GO_PACKAGE% dl --batch -o "%OUTPUT_DIR%" "!CURRENT_URL!"
    ) else if /I "!CURRENT_MODE!"=="wiki" (
        go run %GO_PACKAGE% dl --wiki -o "%OUTPUT_DIR%" "!CURRENT_URL!"
    ) else (
        go run %GO_PACKAGE% dl -o "%OUTPUT_DIR%" "!CURRENT_URL!"
    )
) else (
    if /I "!CURRENT_MODE!"=="batch" (
        "%TOOL_EXE%" dl --batch -o "%OUTPUT_DIR%" "!CURRENT_URL!"
    ) else if /I "!CURRENT_MODE!"=="wiki" (
        "%TOOL_EXE%" dl --wiki -o "%OUTPUT_DIR%" "!CURRENT_URL!"
    ) else (
        "%TOOL_EXE%" dl -o "%OUTPUT_DIR%" "!CURRENT_URL!"
    )
)

if errorlevel 1 (
    echo Result: failed
    exit /b 1
)

echo Result: success
exit /b 0

:TrimVar
setlocal EnableDelayedExpansion
set "VALUE=!%~1!"
:TrimLeft
if defined VALUE if "!VALUE:~0,1!"==" " (
    set "VALUE=!VALUE:~1!"
    goto TrimLeft
)
:TrimRight
if defined VALUE if "!VALUE:~-1!"==" " (
    set "VALUE=!VALUE:~0,-1!"
    goto TrimRight
)
endlocal & set "%~1=%VALUE%"
exit /b 0
