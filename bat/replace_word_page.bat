@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

set "PS1=%~dp0..\ps1\replace_word_page.ps1"

set "SOURCE_PATH=%~1"
set "SOURCE_PAGE=%~2"
set "TARGET_PATH=%~3"
set "TARGET_PAGE=%~4"
set "OUTPUT_PATH=%~5"

if not exist "%PS1%" goto :missingps1

if not defined SOURCE_PATH goto :run_interactive
if not defined SOURCE_PAGE goto :usage
if not defined TARGET_PATH goto :usage
if not defined TARGET_PAGE goto :usage

set "SOURCE_PATH=%SOURCE_PATH:"=%"
set "SOURCE_PAGE=%SOURCE_PAGE:"=%"
set "TARGET_PATH=%TARGET_PATH:"=%"
set "TARGET_PAGE=%TARGET_PAGE:"=%"
set "OUTPUT_PATH=%OUTPUT_PATH:"=%"

if not exist "%SOURCE_PATH%" goto :source_notfound
if not exist "%TARGET_PATH%" goto :target_notfound

echo.
echo 开始Word页面替换...

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -SourcePath "%SOURCE_PATH%" -SourcePage "%SOURCE_PAGE%" -TargetPath "%TARGET_PATH%" -TargetPage "%TARGET_PAGE%" -OutputPath "%OUTPUT_PATH%"

goto :afterrun

:run_interactive
echo.
echo 开始Word页面替换...
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1%"

:afterrun

set "RC=%errorlevel%"

if "%RC%"=="0" (
    echo.
    echo [完成] Word页面替换完成。
) else (
    echo.
    echo [错误] Word页面替换失败。
)
goto :pauseexit

:usage
echo.
echo 用法:
echo   %~nx0 "source.docx" sourcePage "target.docx" targetPage [output.docx]
echo.
echo 示例:
echo   %~nx0 "D:\template.docx" 2 "D:\target.docx" 5 "D:\target_replaced.docx"
goto :pauseexit

:source_notfound
echo.
echo [错误] 源文件未找到: %SOURCE_PATH%
goto :pauseexit

:target_notfound
echo.
echo [错误] 目标文件未找到: %TARGET_PATH%
goto :pauseexit

:missingps1
echo.
echo [错误] 未找到PowerShell脚本: %PS1%
goto :pauseexit

:pauseexit
echo.
pause
exit /b %RC%
