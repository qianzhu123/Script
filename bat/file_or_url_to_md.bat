@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul 2>nul
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PROJECT_DIR=%%~fI"
if not defined DAILY_PROJECT_DIR set "DAILY_PROJECT_DIR=%PROJECT_DIR%"
if not defined DAILY_OUTPUT_DIR set "DAILY_OUTPUT_DIR=%PROJECT_DIR%\output"
if not defined DAILY_TEMP_DIR set "DAILY_TEMP_DIR=%PROJECT_DIR%\temp"
set "MD_OUTPUT_DIR=%DAILY_OUTPUT_DIR%\markdown"
set "MD_TEMP_DIR=%DAILY_TEMP_DIR%\markdown"
if not exist "%MD_OUTPUT_DIR%" mkdir "%MD_OUTPUT_DIR%" >nul 2>nul
if not exist "%MD_TEMP_DIR%" mkdir "%MD_TEMP_DIR%" >nul 2>nul
cd /d "%SCRIPT_DIR%"

echo MarkItDown 文件/网址转Markdown
echo [INFO] Output dir: %MD_OUTPUT_DIR%
echo [INFO] Temp dir:   %MD_TEMP_DIR%
echo.
if not "%~1"=="" (
  set "INPUT_PATH=%~1"
) else (
  set /p "INPUT_PATH=请输入文件路径或URL: "
)
if not defined INPUT_PATH (
  echo 未提供输入。
  goto FAIL
)
set "INPUT_PATH=!INPUT_PATH:"=!"
where markitdown >nul 2>nul
if errorlevel 1 (
  echo 未在PATH中找到markitdown。
  goto FAIL
)
set "IS_URL="
if /I "!INPUT_PATH:~0,7!"=="http://" set "IS_URL=1"
if /I "!INPUT_PATH:~0,8!"=="https://" set "IS_URL=1"
if defined IS_URL goto HANDLE_URL

:HANDLE_FILE
set "SOURCE=!INPUT_PATH!"
if not exist "!SOURCE!" (
  echo 文件未找到:
  echo !SOURCE!
  goto FAIL
)
for %%I in ("!SOURCE!") do (
  set "SRC_FULL=%%~fI"
  set "SRC_DIR=%%~dpI"
  set "SRC_NAME=%%~nI"
)
rem If input is already inside this project, keep output next to it. Otherwise route output to project output\markdown.
set "OUTPUT_DIR=!SRC_DIR!"
echo !SRC_FULL!| findstr /i /b /c:"%DAILY_PROJECT_DIR%" >nul 2>nul
if errorlevel 1 set "OUTPUT_DIR=%MD_OUTPUT_DIR%\"
set "OUTPUT=!OUTPUT_DIR!!SRC_NAME!.md"
call :unique_output OUTPUT

echo.
echo 正在转换文件:
echo !SOURCE!
echo Output:
echo !OUTPUT!
echo.
markitdown "!SOURCE!" -o "!OUTPUT!" 2>"%MD_TEMP_DIR%\markitdown_error_%RANDOM%%RANDOM%.log"
if errorlevel 1 goto FAIL
echo Markdown创建成功: !OUTPUT!
goto OK

:HANDLE_URL
set "URL=!INPUT_PATH!"
set "BASENAME=webpage"
for /f "tokens=1 delims=?#" %%A in ("!URL!") do set "URL_NO_QUERY=%%A"
for %%A in ("!URL_NO_QUERY!") do set "LAST_PART=%%~nxA"
if defined LAST_PART set "BASENAME=!LAST_PART!"
if /I "!BASENAME!"=="" set "BASENAME=webpage"
if /I "!BASENAME!"=="https:" set "BASENAME=webpage"
if /I "!BASENAME!"=="http:" set "BASENAME=webpage"
set "BASENAME=!BASENAME::=_!"
set "BASENAME=!BASENAME:/=_!"
set "BASENAME=!BASENAME:\=_!"
set "BASENAME=!BASENAME:?=_!"
set "BASENAME=!BASENAME:<=_!"
set "BASENAME=!BASENAME:>=_!"
set "BASENAME=!BASENAME:|=_!"
set "BASENAME=!BASENAME:*=_!"
set "BASENAME=!BASENAME:"=_!"
if /I "!BASENAME!"=="index.html" set "BASENAME=webpage"
if /I "!BASENAME!"=="index.htm" set "BASENAME=webpage"
set "OUTPUT=%MD_OUTPUT_DIR%\!BASENAME!.md"
call :unique_output OUTPUT

echo.
echo 正在转换URL:
echo !URL!
echo Output:
echo !OUTPUT!
echo.
markitdown "!URL!" -o "!OUTPUT!" 2>"%MD_TEMP_DIR%\markitdown_error_%RANDOM%%RANDOM%.log"
if errorlevel 1 goto FAIL
echo Markdown创建成功: !OUTPUT!
goto OK

:unique_output
set "VAR=%~1"
set "CAND=!%VAR%!"
if not exist "!CAND!" exit /b 0
for %%I in ("!CAND!") do (
  set "OD=%%~dpI"
  set "ON=%%~nI"
  set "OE=%%~xI"
)
set "STAMP=%date:~0,4%%date:~5,2%%date:~8,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
set "STAMP=!STAMP: =0!"
set "%VAR%=!OD!!ON!_!STAMP!!OE!"
exit /b 0

:FAIL
echo.
echo 转换失败。
if /i not "%DAILY_WEB_TERMINAL%"=="1" if /i not "%DAILY_WEB_NO_PAUSE%"=="1" pause
exit /b 1
:OK
echo.
if /i not "%DAILY_WEB_TERMINAL%"=="1" if /i not "%DAILY_WEB_NO_PAUSE%"=="1" pause
exit /b 0
