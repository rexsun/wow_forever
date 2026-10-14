$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\watch_wtf_settings.ps1')

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$script:states = @($true, $true, $false, $false, $true, $false, $false)
$script:position = 0
$script:exports = 0
Watch-Installation -ProcessProbe { $value = $script:states[$script:position]; $script:position++; return $value } -ExportAction { $script:exports++; return $true } -SleepAction {} -IterationLimit 7
Assert ($script:exports -eq 2) 'Each session must export once after exit.'

$script:exports = 0
Watch-Installation -ProcessProbe { return $false } -ExportAction { $script:exports++; return $true } -SleepAction {} -IterationLimit 3
Assert ($script:exports -eq 1) 'Startup with a closed game must export a baseline once.'

$script:exports = 0
Watch-Installation -ProcessProbe { return $false } -ExportAction { $script:exports++; return ($script:exports -ge 2) } -SleepAction {} -IterationLimit 3
Assert ($script:exports -eq 2) 'Interrupted exports must retry and then stop.'

$script:exports = 0
Watch-Installation -ProcessProbe { return $false } -ExportAction { $script:exports++; return $true } -SleepAction {} -IterationLimit 3 -SkipInitialExport
Assert ($script:exports -eq 0) 'Resume after restore must preserve the selected bundle.'
$script:states = @($false, $true, $false)
$script:position = 0
Watch-Installation -ProcessProbe { $value = $script:states[$script:position]; $script:position++; return $value } -ExportAction { $script:exports++; return $true } -SleepAction {} -IterationLimit 3 -SkipInitialExport
Assert ($script:exports -eq 1) 'Resume must still capture the next session.'

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('wtf-watcher-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $testRoot 'WTF')) | Out-Null
try {
    Set-Content -LiteralPath (Join-Path $testRoot 'WTF\Config.wtf') -Value 'SET uiScale "0.8"'
    $result = Wait-WtfStable -Root $testRoot -Seconds 2 -ProcessProbe { return $false } -SleepAction {} -Attempts 3
    Assert $result 'Stable files must permit export.'
    $result = Wait-WtfStable -Root $testRoot -Seconds 2 -ProcessProbe { return $true } -SleepAction {} -Attempts 3
    Assert (-not $result) 'Restart during the settling interval must cancel export.'
    $script:changes = 0
    $result = Wait-WtfStable -Root $testRoot -Seconds 2 -ProcessProbe { return $false } -SleepAction {
        $script:changes++
        if ($script:changes -eq 1) { Add-Content -LiteralPath (Join-Path $testRoot 'WTF\Config.wtf') -Value 'changed' }
    } -Attempts 4
    Assert ($result -and $script:changes -eq 3) 'New writes must reset the quiet interval.'
} finally {
    $resolvedTest = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedTest.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Test cleanup escaped the temporary directory.' }
    Remove-Item -LiteralPath $resolvedTest -Recurse -Force
}

$tokens = $null
$errors = $null
$null = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\watch_wtf_settings.ps1'), [ref]$tokens, [ref]$errors)
Assert ($errors.Count -eq 0) 'Watcher must parse in Windows PowerShell.'

function Get-CimInstance { return $script:fakeProcesses }
$script:fakeProcesses = @([pscustomobject]@{ ExecutablePath = (Join-Path $script:GameRoot 'WowB.exe') })
Assert (Test-InstallationRunning $script:GameRoot) 'This installation must be detected.'
$script:fakeProcesses = @([pscustomobject]@{ ExecutablePath = 'C:\OtherWoW\WowB.exe' })
Assert (-not (Test-InstallationRunning $script:GameRoot)) 'Other installations must not prevent exports.'
$script:fakeProcesses = @([pscustomobject]@{ ExecutablePath = $null })
$blocked = $false
try { Test-InstallationRunning $script:GameRoot | Out-Null } catch { $blocked = $true }
Assert $blocked 'Unreadable process paths must block export.'

$restoreRoot = Join-Path ([IO.Path]::GetTempPath()) ('wtf-restore-wrapper-' + [guid]::NewGuid().ToString('N'))
$originalLocalData = $env:LOCALAPPDATA
$originalWtfState = $env:WTF_SETTINGS_STATE_DIR
$env:WTF_SETTINGS_STATE_DIR = $null
$originalGameRoot = $script:GameRoot
$env:LOCALAPPDATA = Join-Path $restoreRoot 'private'
$script:GameRoot = Join-Path $restoreRoot 'game'
$script:DryRun = $true
$script:taskState = 'Running'
$script:simulateRunning = $false
$script:simulateFailure = $false
$script:calls = New-Object 'Collections.Generic.List[string]'
function Get-ScheduledTask { return [pscustomobject]@{ State = $script:taskState } }
function Stop-ScheduledTask { $script:calls.Add('stop') }
function Start-ScheduledTask {
    $script:calls.Add('start')
    $skip = Join-Path $env:LOCALAPPDATA ('WowSettings\' + (Get-InstallationId $script:GameRoot) + '\skip-initial-export')
    Assert (Test-Path -LiteralPath $skip) 'Resume must skip initial export.'
}
function Test-InstallationRunning { return $script:simulateRunning }
function Wait-WtfStable { $script:calls.Add('stable'); return $true }
function Invoke-SettingsHelper {
    param([string]$Action, [switch]$ValidateOnly)
    Assert ($Action -eq 'restore' -and $ValidateOnly) 'Restore must dispatch the dry-run helper.'
    $script:calls.Add('restore')
    if ($script:simulateFailure) { throw 'Simulated helper failure' }
}
try {
    Invoke-SettingsRestore
    Assert (($script:calls -join ',') -eq 'stop,stable,restore,start') 'Restore must stop, validate, restore and resume the scheduled watcher.'
    $script:calls.Clear()
    $script:simulateRunning = $true
    $blocked = $false
    try { Invoke-SettingsRestore } catch { $blocked = $true }
    Assert ($blocked -and ($script:calls -join ',') -eq 'stop,start') 'Running game must block restore and resume the watcher.'
    $script:calls.Clear()
    $script:simulateRunning = $false
    $script:simulateFailure = $true
    $blocked = $false
    try { Invoke-SettingsRestore } catch { $blocked = $true }
    Assert ($blocked -and ($script:calls -join ',') -eq 'stop,stable,restore,start') 'Failed restore must resume the watcher.'
    $script:calls.Clear()
    $script:simulateFailure = $false
    $script:taskState = 'Ready'
    Invoke-SettingsRestore
    Assert (($script:calls -join ',') -eq 'stable,restore') 'Restore must leave a stopped watcher stopped.'
    $envFile = Join-Path $restoreRoot '.env'
    $privateDir = Join-Path $restoreRoot 'custom-private'
    [IO.File]::WriteAllText($envFile, ('WTF_SETTINGS_STATE_DIR=' + "'" + $privateDir + "'"))
    Initialize-SettingsEnvironment -Path $envFile
    Assert ((Get-PrivateStateDirectory) -eq $privateDir) 'PowerShell must load private-state mappings from .env.'
    $env:WTF_SETTINGS_STATE_DIR = 'relative-private'
    $blocked = $false
    try { Get-PrivateStateDirectory | Out-Null } catch { $blocked = $true }
    Assert $blocked 'Relative private-state directories must be rejected.'
    [IO.File]::WriteAllText($envFile, ('WTF_SETTINGS_STATE_DIR=' + "'" + $privateDir + "'`nWTF_SETTINGS_STATE_DIR='duplicate'"))
    $blocked = $false
    try { Initialize-SettingsEnvironment -Path $envFile } catch { $blocked = $true }
    Assert $blocked 'Duplicate .env configuration variables must be rejected.'
} finally {
    $env:LOCALAPPDATA = $originalLocalData
    $env:WTF_SETTINGS_STATE_DIR = $originalWtfState
    $script:GameRoot = $originalGameRoot
    $resolvedRestore = [IO.Path]::GetFullPath($restoreRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedRestore.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Restore-test cleanup escaped the temporary directory.' }
    if (Test-Path -LiteralPath $resolvedRestore) { Remove-Item -LiteralPath $resolvedRestore -Recurse -Force }
}
Write-Output '19 watcher/restore lifecycle, .env, stability, process and syntax checks passed.'
