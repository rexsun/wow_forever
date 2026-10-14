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
Write-Output '10 watcher lifecycle/stability/process/syntax checks passed.'
