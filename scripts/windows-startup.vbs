' Autostart duy nhất cho Kinnect. Chạy máy chủ ở cổng 3000 (mặc định) và Cloudflare Tunnel.
' Trước khi khởi động, dọn mọi tiến trình node đang nghe cổng 3000 và mọi cloudflared cũ
' để tránh lỗi EADDRINUSE khi Windows kích hoạt nhiều lần.
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
root = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName))
shell.CurrentDirectory = root
shell.Environment("PROCESS")("SECURE_COOKIES") = "1"
' Dọn tiến trình cũ (ẩn, không chặn). Dấu "> nul 2>&1" để không hiện lỗi khi không có gì để kill.
shell.Run "cmd /c for /f ""tokens=5"" %p in ('netstat -ano ^| findstr "":3000 "" ^| findstr LISTENING') do taskkill /PID %p /F > nul 2>&1", 0, True
shell.Run "cmd /c taskkill /IM cloudflared.exe /F > nul 2>&1", 0, True
shell.Run "cmd /c """"C:\Program Files\nodejs\node.exe"" server.js >> data\startup-server.log 2>&1""", 0, False
exe = fso.GetAbsolutePathName(root & "\..\..\work\tools\cloudflared.exe")
config = root & "\scripts\windows-tunnel.yml"
shell.Run """" & exe & """ tunnel --config """ & config & """ --logfile data\startup-tunnel.log run kinnect", 0, False
