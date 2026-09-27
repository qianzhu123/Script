@echo off
chcp 65001 >nul
setlocal

REM 启动 MCP 三端部署工具（Claude Code + Codex + Cherry Studio）
REM 通过交互式问答收集 MCP 关键信息，一次性写入三个客户端配置。

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\ps1\deploy_mcp.ps1"

endlocal
pause
