@echo off
setlocal EnableExtensions DisableDelayedExpansion

title 复制快捷方式到开始菜单

set "STARTMENU=C:\Users\Light\AppData\Roaming\Microsoft\Windows\Start Menu\Programs"

echo.
echo === 复制快捷方式到开始菜单 ===
echo 目标位置: %STARTMENU%
echo.
echo 请输入现有.lnk文件的完整路径。
echo 路径可以包含引号。
echo.

set /p "SOURCE=快捷方式路径: "

if not defined SOURCE (
  echo 未输入路径。
  pause
  exit /b 1
)

set "SOURCE=%SOURCE:"=%"

if not defined SOURCE (
  echo 未输入有效路径。
  pause
  exit /b 1
)

if /I not "%SOURCE:~-4%"==".lnk" (
  echo 文件必须是.lnk快捷方式。
  pause
  exit /b 1
)

if not exist "%SOURCE%" (
  echo 文件不存在:
  echo %SOURCE%
  pause
  exit /b 1
)

if not exist "%STARTMENU%" (
  echo 目标文件夹不存在:
  echo %STARTMENU%
  pause
  exit /b 1
)

for %%I in ("%SOURCE%") do set "FILENAME=%%~nxI"
set "DEST=%STARTMENU%\%FILENAME%"

copy /Y "%SOURCE%" "%DEST%" >nul
set "ERR=%ERRORLEVEL%"

if not "%ERR%"=="0" (
  echo 复制快捷方式失败。
  pause
  exit /b %ERR%
)

echo.
echo 快捷方式复制成功:
echo %DEST%
echo.
echo 现在可以按Win键搜索此快捷方式。
echo.
pause
exit /b 0
