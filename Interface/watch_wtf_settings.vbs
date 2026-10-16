Option Explicit

Dim shell, files, scriptPath, command
If WScript.Arguments.Count <> 1 Then WScript.Quit 2
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
scriptPath = files.BuildPath(files.GetParentFolderName(WScript.ScriptFullName), "watch_wtf_settings.ps1")
command = Quote(shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")) _
    & " -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File " _
    & Quote(scriptPath) & " -Mode Watch -UvPath " & Quote(WScript.Arguments(0))
WScript.Quit shell.Run(command, 0, True)

Function Quote(value)
    If InStr(value, Chr(34)) > 0 Then WScript.Quit 2
    Quote = Chr(34) & value & Chr(34)
End Function
