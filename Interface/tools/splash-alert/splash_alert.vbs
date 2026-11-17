Option Explicit

' Starts Splash Alert with no console window. Arguments: uv.exe path, log file path.
Dim shell, files, scriptPath, command
If WScript.Arguments.Count <> 2 Then WScript.Quit 2
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
scriptPath = files.BuildPath(files.GetParentFolderName(WScript.ScriptFullName), "splash_alert.py")
command = Quote(WScript.Arguments(0)) & " run --python 3.13 " & Quote(scriptPath) _
    & " --log-file " & Quote(WScript.Arguments(1)) & " run"
WScript.Quit shell.Run(command, 0, True)

Function Quote(value)
    If InStr(value, Chr(34)) > 0 Then WScript.Quit 2
    Quote = Chr(34) & value & Chr(34)
End Function
