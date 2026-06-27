@echo off
setlocal

set "SERVER_DIR=D:\tools\Security\Reverse\Android\tools\jadx-mcp-server"
set "SERVER_SCRIPT=jadx_mcp_server.py"

echo 正在启动JADX MCP服务(HTTP模式)...
echo 服务目录: %SERVER_DIR%
echo Endpoint: http://127.0.0.1:8651/mcp
echo.

if not exist "%SERVER_DIR%\%SERVER_SCRIPT%" (
  echo [错误] 未找到服务脚本: "%SERVER_DIR%\%SERVER_SCRIPT%".
  echo 请验证安装路径。
  pause
  exit /b 1
)

where uv >nul 2>&1
if errorlevel 1 (
  echo [错误] "uv" 不在PATH中。
  echo 请安装uv或将其加入PATH后重试。
  pause
  exit /b 1
)

cd /d "%SERVER_DIR%"
uv --directory "%SERVER_DIR%" run "%SERVER_SCRIPT%" --http

if errorlevel 1 (
  echo.
  echo [错误] JADX MCP服务启动失败。
  pause
  exit /b 1
)

endlocal
