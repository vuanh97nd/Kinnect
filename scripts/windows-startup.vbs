Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
root = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName))
shell.CurrentDirectory = root
q = Chr(34)
action = "start"
For Each arg In WScript.Arguments
  If arg = "--check" Then action = "check"
Next
command = q & "C:\Program Files\nodejs\node.exe" & q & " " & q & root & "\scripts\server-manager.mjs" & q & " " & action
shell.Run command, 0, False
