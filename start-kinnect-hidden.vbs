' Launcher chạy tay dùng chung cấu hình với autostart Windows.
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
root = fso.GetParentFolderName(WScript.ScriptFullName)
shell.CurrentDirectory = root
launcher = root & "\scripts\windows-startup.vbs"
shell.Run "wscript.exe """ & launcher & """", 0, False
