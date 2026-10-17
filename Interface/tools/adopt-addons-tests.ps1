$ErrorActionPreference = 'Stop'
$scriptUnderTest = Join-Path (Split-Path $PSScriptRoot -Parent) 'adopt_addons.ps1'
if (-not (Test-Path -LiteralPath $scriptUnderTest)) { throw 'adopt_addons.ps1 does not exist yet.' }
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('adopt addons tests ' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$global:adoptTestGameRunning = $false
$global:adoptTestCopyFails = $false
$global:adoptTestInstallFails = $false
$global:adoptTestFontInstallFails = $false
$global:adoptTestBackupLocked = $false
function Read-Host { param($Prompt) throw "Unexpected interactive prompt: $Prompt" }
function Get-Process { param($Name) if ($global:adoptTestGameRunning) { [pscustomobject]@{ ProcessName = 'WowB' } } }
function robocopy.exe {
    if ($global:adoptTestCopyFails) { $global:LASTEXITCODE = 8; return }
    & "$env:SystemRoot\System32\robocopy.exe" @args | Out-Null
}
function Move-Item {
    param($LiteralPath, $Destination)
    if ($global:adoptTestBackupLocked -and $LiteralPath -like '*\target game\Interface') {
        $global:adoptTestBackupLocked = $false
        throw 'The process cannot access the file because it is being used by another process.'
    }
    if ($global:adoptTestFontInstallFails -and $LiteralPath -like '*stage*' -and $LiteralPath -like '*\Fonts') {
        $global:adoptTestFontInstallFails = $false
        throw 'Simulated font install failure'
    }
    if ($global:adoptTestInstallFails -and $LiteralPath -like '*stage*' -and $LiteralPath -like '*\WTF') {
        $global:adoptTestInstallFails = $false
        throw 'Simulated install failure'
    }
    Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination
}
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Get-SourceSnapshot($Path) {
    return ((Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object FullName | ForEach-Object {
        $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName).Hash
    }) -join "`n")
}
function New-Fixture($Name) {
    $root = Join-Path $testRoot $Name
    $source = Join-Path $root 'source game'
    $target = Join-Path $root 'target game'
    foreach ($path in @('source game\Interface\AddOns', 'source game\WTF', 'target game\Interface\AddOns', 'target game\WTF', 'target game\Fonts')) {
        New-Item -ItemType Directory -Path (Join-Path $root $path) -Force | Out-Null
    }
    Set-Content -LiteralPath (Join-Path $source 'Interface\AddOns\new.txt') -Value 'new'
    New-Item -ItemType Directory -Path (Join-Path $source 'Interface\AddOns\CharacterUIBaseline') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $source 'Interface\Settings') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $source 'Interface\AddOns\CharacterUIBaseline\Source.local.lua') -Value 'local _, baseline = ...; baseline.source = { enabled = true }'
    Set-Content -LiteralPath (Join-Path $source 'Interface\Settings\character-ui-source.local.json') -Value '{"sourceAccount":"portable-test"}'
    New-Item -ItemType Directory -Path (Join-Path $source 'Fonts') -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $source 'Fonts\YUILongZhu.ttf'), [byte[]](0, 1, 0, 0, 255))
    [IO.File]::WriteAllBytes((Join-Path $target 'Fonts\YUILongZhu.ttf'), [byte[]](1, 2, 3))
    Set-Content -LiteralPath (Join-Path $source 'WTF\Config.wtf') -Value 'SET uiScale "0.53333333333333"'
    Set-Content -LiteralPath (Join-Path $target 'Interface\AddOns\old.txt') -Value 'old'
    Set-Content -LiteralPath (Join-Path $target 'WTF\Config.wtf') -Value 'old settings'
    Set-Content -LiteralPath (Join-Path $target 'Fonts\keep.txt') -Value 'font'
    $entry = Join-Path $source 'Interface\adopt_addons.ps1'
    Copy-Item -LiteralPath $scriptUnderTest -Destination $entry
    return @{ Source = $source; Target = $target; Entry = $entry }
}
function Invoke-Adoption($Fixture, $Destination, $Resolution) {
    $sourceBefore = Get-SourceSnapshot $Fixture.Source
    Push-Location -LiteralPath $Fixture.Source
    try {
        if ($Resolution) { & $Fixture.Entry $Destination -Resolution $Resolution }
        else { & $Fixture.Entry -Destination $Destination }
    } finally {
        Pop-Location
        Assert ((Get-SourceSnapshot $Fixture.Source) -eq $sourceBefore) 'Source installation changed'
        Assert (-not (Test-Path -LiteralPath (Join-Path $Fixture.Source 'addon-backups'))) 'Source received backup files'
    }
}
function Invoke-Rejected($Fixture, $Destination, $Resolution, $ExpectedError) {
    $rejected = $false
    try {
        Invoke-Adoption $Fixture $Destination $Resolution
    } catch {
        $rejected = $true
        if ($ExpectedError) {
            Assert ($_.Exception.Message.Contains($ExpectedError)) 'Failure did not identify the locked destination operation'
        }
    }
    Assert $rejected 'Expected rejection'
    Assert (Test-Path -LiteralPath (Join-Path $Fixture.Target 'Interface\AddOns\old.txt')) 'Original Interface lost'
    Assert ((Get-Content -LiteralPath (Join-Path $Fixture.Target 'WTF\Config.wtf') -Raw).Trim() -eq 'old settings') 'Original settings lost'
    Assert ((Get-Content -LiteralPath (Join-Path $Fixture.Target 'Fonts\keep.txt') -Raw).Trim() -eq 'font') 'Destination-only font lost'
    Assert ([BitConverter]::ToString([IO.File]::ReadAllBytes((Join-Path $Fixture.Target 'Fonts\YUILongZhu.ttf'))) -eq '01-02-03') 'Original font lost'
}
$f = New-Fixture 'success'
$before = (Get-FileHash -LiteralPath (Join-Path $f.Source 'WTF\Config.wtf')).Hash
Invoke-Adoption $f $f.Target
Assert (Test-Path -LiteralPath (Join-Path $f.Target 'Interface\AddOns\new.txt')) 'Source addon missing'
Assert ((Get-FileHash -LiteralPath (Join-Path $f.Target 'Fonts\YUILongZhu.ttf')).Hash -eq (Get-FileHash -LiteralPath (Join-Path $f.Source 'Fonts\YUILongZhu.ttf')).Hash) 'Game-root font missing or damaged'
Assert (-not (Test-Path -LiteralPath (Join-Path $f.Target 'Interface\AddOns\old.txt'))) 'Obsolete addon retained'
Assert (Test-Path -LiteralPath (Join-Path $f.Target 'Interface\adopt_addons.ps1')) 'Utility not copied'
Assert (-not (Test-Path -LiteralPath (Join-Path $f.Source 'addon-backups'))) 'Backup written to source'
Assert (Test-Path -LiteralPath (Join-Path $f.Target 'Fonts\keep.txt')) 'Fonts changed'
Assert ((Get-FileHash -LiteralPath (Join-Path $f.Target 'WTF\Config.wtf')).Hash -eq $before) 'Settings changed'
Assert ((Get-FileHash -LiteralPath (Join-Path $f.Source 'WTF\Config.wtf')).Hash -eq $before) 'Source settings changed'
$backups = @(Get-ChildItem -LiteralPath (Join-Path $f.Target 'addon-backups') -Directory)
Assert ($backups.Count -eq 1) 'Expected one backup'
Assert (Test-Path -LiteralPath (Join-Path $backups[0].FullName 'Interface\AddOns\old.txt')) 'Backup addon missing'
Assert ((Get-Content -LiteralPath (Join-Path $backups[0].FullName 'WTF\Config.wtf') -Raw).Trim() -eq 'old settings') 'Backup settings missing'
Invoke-Adoption $f $f.Target
Assert (@(Get-ChildItem -LiteralPath (Join-Path $f.Target 'addon-backups') -Directory).Count -eq 2) 'Repeat run overwrote backup'
foreach ($resolution in @('1920x1080', '2560x1440', '3840x2160')) {
    $f = New-Fixture $resolution
    $saved = Join-Path $f.Source 'WTF\Account\test\SavedVariables'
    New-Item -ItemType Directory -Path $saved -Force | Out-Null
    $eui = Join-Path $saved 'EllesmereUI.lua'
    Set-Content -LiteralPath $eui -Encoding UTF8 -Value @'
EllesmereUIDB = {
["panelScale"] = 1.5,
["ppUIScale"] = 0.64,
["profiles"] = { ["Default"] = { ["marker"] = "測試" } },
}
'@
    $sourceHash = (Get-FileHash -LiteralPath $eui).Hash
    Invoke-Adoption $f $f.Target $resolution
    foreach ($relative in @('Interface\AddOns\CharacterUIBaseline\Source.local.lua', 'Interface\Settings\character-ui-source.local.json')) {
        Assert ((Get-FileHash -LiteralPath (Join-Path $f.Source $relative)).Hash -eq (Get-FileHash -LiteralPath (Join-Path $f.Target $relative)).Hash) 'Private login UI configuration was not adopted intact'
    }
    $config = Get-Content -LiteralPath (Join-Path $f.Target 'WTF\Config.wtf') -Raw
    Assert ($config -match ('SET gxWindowedResolution "' + $resolution + '"')) 'Resolution was not configured'
    Assert ($config -match 'SET uiScale "0.53333333333333"') 'Gameplay UI scale changed'
    $settings = Get-Content -LiteralPath (Join-Path $f.Target 'WTF\Account\test\SavedVariables\EllesmereUI.lua') -Raw -Encoding UTF8
    Assert ($settings -match '\["ppUIScale"\] = 0.64') 'EUI gameplay scale changed'
    Assert ($settings -match '測試') 'Unicode settings damaged'
    Assert ($settings -match '\["panelScale"\]\s*=\s*([\d.]+)') 'Panel scale missing'
    $scale = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
    $dimensions = $resolution.Split('x')
    Assert ((1154 * $scale) -le ([int]$dimensions[1] - 40)) 'EUI options panel exceeds display height'
    Assert ((1500 * $scale) -le ([int]$dimensions[0] - 40)) 'EUI options panel exceeds display width'
    Assert ((Get-FileHash -LiteralPath $eui).Hash -eq $sourceHash) 'Source EUI settings changed'
}
$f = New-Fixture 'invalid EUI settings'
$saved = Join-Path $f.Source 'WTF\Account\test\SavedVariables'
New-Item -ItemType Directory -Path $saved -Force | Out-Null
Set-Content -LiteralPath (Join-Path $saved 'EllesmereUI.lua') -Value 'unrecognized data'
Invoke-Rejected $f $f.Target '1920x1080'
$f = New-Fixture 'missing destination'
Invoke-Rejected $f (Join-Path $testRoot 'absent')
$f = New-Fixture 'wrong working directory'
Push-Location -LiteralPath (Join-Path $f.Source 'Interface')
try {
    $rejected = $false
    try { & $f.Entry $f.Target } catch {
        Assert ($_.Exception.Message -like 'Run from the source game root*') 'Unexpected working-directory error'
        $rejected = $true
    }
    Assert $rejected 'Wrong working directory accepted'
    Assert (Test-Path -LiteralPath (Join-Path $f.Target 'Interface\AddOns\old.txt')) 'Wrong-directory run changed destination'
    Assert (-not (Test-Path -LiteralPath (Join-Path $f.Target 'addon-backups'))) 'Wrong-directory run wrote destination'
} finally { Pop-Location }
$f = New-Fixture 'same root'
Invoke-Rejected $f $f.Source
$f = New-Fixture 'nested destination'
Invoke-Rejected $f (Join-Path $f.Source 'Interface')
$f = New-Fixture 'parent destination'
Invoke-Rejected $f (Split-Path $f.Source -Parent)
$f = New-Fixture 'destination file'
Invoke-Rejected $f (Join-Path $f.Target 'WTF\Config.wtf')
$f = New-Fixture 'missing WTF'
Rename-Item -LiteralPath (Join-Path $f.Source 'WTF') -NewName 'Other'
Invoke-Rejected $f $f.Target
$f = New-Fixture 'running game'
$global:adoptTestGameRunning = $true
Invoke-Rejected $f $f.Target
$global:adoptTestGameRunning = $false
$f = New-Fixture 'copy failure'
$global:adoptTestCopyFails = $true
Invoke-Rejected $f $f.Target
$global:adoptTestCopyFails = $false
$f = New-Fixture 'rollback'
$global:adoptTestInstallFails = $true
Invoke-Rejected $f $f.Target
$f = New-Fixture 'locked destination'
$global:adoptTestBackupLocked = $true
Invoke-Rejected $f $f.Target $null ("Backing up destination '" + (Join-Path $f.Target 'Interface') + "'")
$f = New-Fixture 'font rollback'
$global:adoptTestFontInstallFails = $true
Invoke-Rejected $f $f.Target
$f = New-Fixture 'optional Fonts'
Rename-Item -LiteralPath (Join-Path $f.Source 'Fonts') -NewName 'OtherFonts'
Invoke-Adoption $f $f.Target
Assert ([BitConverter]::ToString([IO.File]::ReadAllBytes((Join-Path $f.Target 'Fonts\YUILongZhu.ttf'))) -eq '01-02-03') 'Fonts changed without source Fonts'
$f = New-Fixture 'empty destination'
$freshTarget = Join-Path $testRoot 'empty destination root'
New-Item -ItemType Directory -Path $freshTarget | Out-Null
Invoke-Adoption $f $freshTarget
Assert (Test-Path -LiteralPath (Join-Path $freshTarget 'Interface\AddOns\new.txt')) 'Empty destination did not receive addons'
Assert (Test-Path -LiteralPath (Join-Path $freshTarget 'WTF\Config.wtf')) 'Empty destination did not receive settings'
Assert (Test-Path -LiteralPath (Join-Path $freshTarget 'Fonts\YUILongZhu.ttf')) 'Empty destination did not receive fonts'
Write-Host "PASS: source-to-destination/repeat use, three resolutions, source/Unicode preservation, font merge, optional Fonts, wrong cwd, overlapping/invalid roots, empty destination, running game, copy failure and rollback. Fixtures: $testRoot"
