$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\watch_wtf_settings.ps1')

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('wtf helper ' + [guid]::NewGuid().ToString('N'))
$originalHelper = $script:Helper
$originalState = $env:WTF_SETTINGS_STATE_DIR
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
try {
    $script:Helper = Join-Path $testRoot 'console probe.py'
    $env:WTF_SETTINGS_STATE_DIR = $testRoot + '\'
    [IO.File]::WriteAllText($script:Helper, @'
import ctypes
import json
import sys

print(json.dumps({"console": ctypes.windll.kernel32.GetConsoleWindow(), "args": sys.argv[1:]}))
if sys.argv[1] == "fail":
    sys.stdout.write("x" * 100000)
    sys.stderr.write("y" * 100000)
    sys.exit(7)
'@)
    $result = (Invoke-SettingsHelper 'export' -ValidateOnly) | ConvertFrom-Json
    Assert ($result.console -eq 0) 'Helper must run without a console window.'
    Assert (($result.args -join '|') -ceq ('export|--game-root|' + $script:GameRoot + '|--state|' + $env:WTF_SETTINGS_STATE_DIR + '|--dry-run')) 'Helper arguments must preserve spaces and trailing backslashes.'
    $blocked = $false
    try { Invoke-SettingsHelper 'fail' | Out-Null } catch { $blocked = $_.Exception.Message -like 'Settings helper failed*' }
    Assert $blocked 'Nonzero helper exit must fail without deadlocking on full stdout/stderr pipes.'
} finally {
    $script:Helper = $originalHelper
    $env:WTF_SETTINGS_STATE_DIR = $originalState
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Test cleanup escaped the temporary directory.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Output '3 helper console, argument and failure checks passed.'
