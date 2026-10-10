$ErrorActionPreference = 'Stop'
$scriptUnderTest = Join-Path (Split-Path $PSScriptRoot -Parent) 'adopt_addons.ps1'
if (-not (Test-Path -LiteralPath $scriptUnderTest)) { throw 'adopt_addons.ps1 does not exist yet.' }
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('adopt addons tests ' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$global:adoptTestAnswer = 'CLOSED'
$global:adoptTestGameRunning = $false
$global:adoptTestCopyFails = $false
$global:adoptTestInstallFails = $false
function Read-Host { param($Prompt) return $global:adoptTestAnswer }
function Get-Process { param($Name) if ($global:adoptTestGameRunning) { [pscustomobject]@{ ProcessName = 'WowB' } } }
function robocopy.exe {
    if ($global:adoptTestCopyFails) { $global:LASTEXITCODE = 8; return }
    & "$env:SystemRoot\System32\robocopy.exe" @args | Out-Null
}
function Move-Item {
    param($LiteralPath, $Destination)
    if ($global:adoptTestInstallFails -and $LiteralPath -like '*stage*' -and $LiteralPath -like '*\WTF') {
        $global:adoptTestInstallFails = $false
        throw 'Simulated install failure'
    }
    Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination
}
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function New-Fixture($Name) {
    $root = Join-Path $testRoot $Name
    $source = Join-Path $root 'source game'
    $target = Join-Path $root 'target game'
    foreach ($path in @('source game\Interface\AddOns', 'source game\WTF', 'target game\Interface\AddOns', 'target game\WTF', 'target game\Fonts')) {
        New-Item -ItemType Directory -Path (Join-Path $root $path) -Force | Out-Null
    }
    Set-Content -LiteralPath (Join-Path $source 'Interface\AddOns\new.txt') -Value 'new'
    Set-Content -LiteralPath (Join-Path $source 'WTF\Config.wtf') -Value 'SET uiScale "0.53333333333333"'
    Set-Content -LiteralPath (Join-Path $target 'Interface\AddOns\old.txt') -Value 'old'
    Set-Content -LiteralPath (Join-Path $target 'WTF\Config.wtf') -Value 'old settings'
    Set-Content -LiteralPath (Join-Path $target 'Fonts\keep.txt') -Value 'font'
    $entry = Join-Path $target 'Interface\adopt_addons.ps1'
    Copy-Item -LiteralPath $scriptUnderTest -Destination $entry
    return @{ Source = $source; Target = $target; Entry = $entry }
}
function Invoke-Rejected($Fixture, $Source) {
    $rejected = $false
    try { & $Fixture.Entry $Source } catch { $rejected = $true }
    Assert $rejected 'Expected rejection'
    Assert (Test-Path -LiteralPath (Join-Path $Fixture.Target 'Interface\AddOns\old.txt')) 'Original Interface lost'
    Assert ((Get-Content -LiteralPath (Join-Path $Fixture.Target 'WTF\Config.wtf') -Raw).Trim() -eq 'old settings') 'Original settings lost'
}
$f = New-Fixture 'success'
$before = (Get-FileHash -LiteralPath (Join-Path $f.Source 'WTF\Config.wtf')).Hash
& $f.Entry $f.Source
Assert (Test-Path -LiteralPath (Join-Path $f.Target 'Interface\AddOns\new.txt')) 'Source addon missing'
Assert (-not (Test-Path -LiteralPath (Join-Path $f.Target 'Interface\AddOns\old.txt'))) 'Obsolete addon retained'
Assert (Test-Path -LiteralPath $f.Entry) 'Utility not preserved'
Assert (Test-Path -LiteralPath (Join-Path $f.Target 'Fonts\keep.txt')) 'Fonts changed'
Assert ((Get-FileHash -LiteralPath (Join-Path $f.Target 'WTF\Config.wtf')).Hash -eq $before) 'Settings changed'
Assert ((Get-FileHash -LiteralPath (Join-Path $f.Source 'WTF\Config.wtf')).Hash -eq $before) 'Source settings changed'
$backups = @(Get-ChildItem -LiteralPath (Join-Path $f.Target 'addon-backups') -Directory)
Assert ($backups.Count -eq 1) 'Expected one backup'
Assert (Test-Path -LiteralPath (Join-Path $backups[0].FullName 'Interface\AddOns\old.txt')) 'Backup addon missing'
Assert ((Get-Content -LiteralPath (Join-Path $backups[0].FullName 'WTF\Config.wtf') -Raw).Trim() -eq 'old settings') 'Backup settings missing'
& $f.Entry $f.Source
Assert (@(Get-ChildItem -LiteralPath (Join-Path $f.Target 'addon-backups') -Directory).Count -eq 2) 'Repeat run overwrote backup'
$f = New-Fixture 'missing source'
Invoke-Rejected $f (Join-Path $testRoot 'absent')
$f = New-Fixture 'same root'
Invoke-Rejected $f $f.Target
$f = New-Fixture 'missing WTF'
Rename-Item -LiteralPath (Join-Path $f.Source 'WTF') -NewName 'Other'
Invoke-Rejected $f $f.Source
$f = New-Fixture 'running game'
$global:adoptTestGameRunning = $true
Invoke-Rejected $f $f.Source
$global:adoptTestGameRunning = $false
$f = New-Fixture 'declined'
$global:adoptTestAnswer = 'no'
Invoke-Rejected $f $f.Source
$global:adoptTestAnswer = 'CLOSED'
$f = New-Fixture 'copy failure'
$global:adoptTestCopyFails = $true
Invoke-Rejected $f $f.Source
$global:adoptTestCopyFails = $false
$f = New-Fixture 'rollback'
$global:adoptTestInstallFails = $true
Invoke-Rejected $f $f.Source
Write-Host "PASS: adoption, repeat use, backups, unchanged settings/Fonts, invalid sources, running game, cancellation, copy failure and rollback. Fixtures: $testRoot"
