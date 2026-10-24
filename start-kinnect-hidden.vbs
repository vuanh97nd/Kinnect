' Chạy máy chủ Kinnect và Cloudflare Tunnel ở chế độ ẩn (không hiện cửa sổ CMD).
' Địa chỉ cố định: https://app.kinnect.io.vn (cấu hình ở %USERPROFILE%\.cloudflared\config.yml).
' Nhật ký: data\server.log và data\tunnel.log. Dừng bằng stop-kinnect.cmd.
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
Set shell = CreateObject("WScript.Shell")
shell.CurrentDirectory = dir
shell.Run "cmd /c set SECURE_COOKIES=1&& ""C:\Program Files\nodejs\node.exe"" server.js >> data\server.log 2>&1", 0, False
tunnel = fso.GetAbsolutePathName(dir & "\..\..\work\tools\cloudflared.exe")
If fso.FileExists(tunnel) Then
  shell.Run """" & tunnel & """ tunnel --logfile data\tunnel.log run kinnect", 0, False
End If
