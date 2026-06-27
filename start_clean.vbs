Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = "D:\code\myweb\daily"
WshShell.Run "cmd /c node server.js", 0, False
