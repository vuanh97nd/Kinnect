' Điểm khởi động chung cho autostart và launcher chạy tay.
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
root = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName))
shell.CurrentDirectory = root
nodeExe = "C:\Program Files\nodejs\node.exe"
exe = fso.GetAbsolutePathName(root & "\..\..\work\tools\cloudflared.exe")
config = root & "\scripts\windows-tunnel.yml"
dataDir = root & "\data"
' Kiểm tra đầy đủ trước khi dừng phiên đang chạy.
For Each required In Array(nodeExe, exe, config, root & "\server.js")
  If Not fso.FileExists(required) Then
    WScript.Echo "Kinnect: missing required file: " & required
    WScript.Quit 1
  End If
Next
For Each arg In WScript.Arguments
  If arg = "--check" Then
    WScript.Echo "Kinnect startup preflight OK; port=3000; server and tunnel files present."
    WScript.Quit 0
  End If
Next
If Not fso.FolderExists(dataDir) Then fso.CreateFolder dataDir
shell.Environment("PROCESS")("SECURE_COOKIES") = "1"
shell.Environment("PROCESS")("PORT") = "3000"
' Dọn phiên cũ trước khi mở server và tunnel mới; không hiện cửa sổ terminal.
shell.Run "cmd /c for /f ""tokens=5"" %p in ('netstat -ano ^| findstr "":3000 "" ^| findstr LISTENING') do taskkill /PID %p /F > nul 2>&1", 0, True
shell.Run "cmd /c taskkill /IM cloudflared.exe /F > nul 2>&1", 0, True
quote = Chr(34)
serverCommand = "cmd /c " & quote & quote & nodeExe & quote & " server.js >> data\startup-server.log 2>&1" & quote
shell.Run serverCommand, 0, False
shell.Run """" & exe & """ tunnel --config """ & config & """ --logfile data\startup-tunnel.log run kinnect", 0, False
