@echo off
chcp 65001 >nul
echo ���������ļ�������򿪷�ʽ����...
taskkill /f /im explorer.exe >nul 2>&1
timeout /t 1 /nobreak >nul
del /f /s /q "%appdata%\Microsoft\Windows\Recent\AutomaticDestinations\*" >nul 2>&1
del /f /s /q "%appdata%\Microsoft\Windows\Recent\CustomDestinations\*" >nul 2>&1
start explorer.exe
echo ������ɣ����Ҽ� .txt �ļ� �� �򿪷�ʽ �� �ֶ�ѡ����·���� Code.exe
pause