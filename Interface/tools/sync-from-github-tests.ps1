$ErrorActionPreference = 'Stop'
$git = (Get-Command git -CommandType Application | Select-Object -First 1).Source
$interfaceRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $interfaceRoot 'sync_from_github.ps1')
Import-Module (Join-Path $PSScriptRoot 'WowResolution.psm1') -Force

function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Invoke-TestGit([string]$Root, [string[]]$Arguments) {
    $result = Invoke-Native $git (@('-C', $Root, '-c', 'user.name=test', '-c', 'user.email=test@example.invalid') + $Arguments)
    if ($result.Code -ne 0) { throw "git $($Arguments -join ' ') failed: $($result.Error)" }
}
function Write-File([string]$Path, [string]$Text) {
    [IO.Directory]::CreateDirectory((Split-Path $Path -Parent)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function Read-File([string]$Path) { return [IO.File]::ReadAllText($Path) }
function Commit-Upstream([string]$Message) {
    Invoke-TestGit $upstream @('add', '-A')
    Invoke-TestGit $upstream @('commit', '-q', '-m', $Message)
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('wow sync tests ' + [guid]::NewGuid().ToString('N'))
$upstream = Join-Path $testRoot 'upstream repo'
$global:syncGame = Join-Path $testRoot 'game root'
$state = Join-Path $testRoot 'private state'
$checks = 0
try {
    foreach ($case in @(
        @(3840, 2160, '3840x2160'), @(3440, 1440, '2560x1440'), @(2560, 1600, '2560x1440'),
        @(1920, 1200, '1920x1080'), @(1366, 768, '1920x1080'), @(5120, 2880, '3840x2160'))) {
        Assert ((ConvertTo-SupportedResolution $case[0] $case[1]) -eq $case[2]) "Snap of $($case[0])x$($case[1]) wrong"
    }
    Assert ((Get-EuiPanelScale '1920x1080') -eq 0.9) 'EUI 1080p scale'
    Assert ((Get-EuiPanelScale '2560x1440') -eq 1.0) 'EUI 1440p scale'
    Assert ((Get-EuiPanelScale '3840x2160') -eq 1.5) 'EUI 4K scale'
    Assert ((Get-DisplayResolution) -match '^\d+x\d+$') 'Display probe format'
    $probeConfig = Join-Path $testRoot 'probe\Config.wtf'
    Write-File $probeConfig "SET gxWindowedResolution `"auto`"`r`nSET gxFullscreenResolution `"2560x1080`"`r`n"
    Assert ((Get-ConfigResolution $probeConfig) -eq '2560x1080') 'Fullscreen fallback when windowed is auto'
    Assert ($null -eq (Get-ConfigResolution (Join-Path $testRoot 'absent.wtf'))) 'Missing Config.wtf'
    $checks += 11

    [IO.Directory]::CreateDirectory($upstream) | Out-Null
    Invoke-TestGit $upstream @('init', '-q', '-b', 'main')
    Copy-Item -LiteralPath (Join-Path (Split-Path $interfaceRoot -Parent) '.gitignore') -Destination (Join-Path $upstream '.gitignore')
    foreach ($relative in @('sync_from_github.ps1', 'tools\WowResolution.psm1')) {
        Write-File (Join-Path $upstream "Interface\$relative") (Read-File (Join-Path $interfaceRoot $relative))
    }
    Write-File (Join-Path $upstream 'Interface\AddOns\A\a.lua') 'a = 1'
    Write-File (Join-Path $upstream 'Interface\AddOns\Gone\g.lua') 'g = 1'
    Write-File (Join-Path $upstream 'Interface\Settings\WTF\global\Config.json') '{"v":1}'
    Write-File (Join-Path $upstream 'Fonts\YUIText.ttf') 'new font'
    Commit-Upstream 'initial'

    Write-File (Join-Path $syncGame 'Wow.exe') ''
    Write-File (Join-Path $syncGame 'Interface\AddOns\Old\o.lua') 'old = 1'
    Write-File (Join-Path $syncGame 'Interface\.env') 'WTF_MAP_VERSION=1'
    Write-File (Join-Path $syncGame 'Fonts\YUIText.ttf') 'old font'
    Write-File (Join-Path $syncGame 'Fonts\Other.ttf') 'untracked font'
    Write-File (Join-Path $syncGame 'WTF\Config.wtf') "SET gxWindowedResolution `"3440x1440`"`r`nSET uiScale `"0.6`"`r`n"
    $eui = Join-Path $syncGame 'WTF\Account\ACC\SavedVariables\EllesmereUI.lua'
    Write-File $eui "EllesmereUIDB = {`r`n[`"panelScale`"] = 1.5,`r`n[`"marker`"] = `"測試`",`r`n}`r`n"

    $broken = Join-Path $testRoot 'broken game'
    Write-File (Join-Path $broken 'Wow.exe') ''
    Write-File (Join-Path $broken 'Interface\AddOns\Mine\m.lua') 'mine'
    $failed = $false
    try { Initialize-Checkout $git $broken (Join-Path $testRoot 'no such repo') { $false } } catch { $failed = $_.Exception.Message -like 'Install failed and was rolled back*' }
    Assert $failed 'Bootstrap from a missing repository must fail with rollback'
    Assert (Test-Path -LiteralPath (Join-Path $broken 'Interface\AddOns\Mine\m.lua')) 'Rollback lost the existing Interface'
    Assert (-not (Test-Path -LiteralPath (Join-Path $broken '.git'))) 'Rollback left a .git folder'
    $refused = $false
    try { Initialize-Checkout $git $broken $upstream { $true } } catch { $refused = $_.Exception.Message -like 'Close WoW*' }
    Assert ($refused -and -not (Test-Path -LiteralPath (Join-Path $broken '.git'))) 'Bootstrap must refuse while WoW runs'
    $checks += 4

    Initialize-Checkout $git $syncGame $upstream { $false }
    $backup = @(Get-ChildItem -LiteralPath (Join-Path $syncGame 'addon-backups') -Directory)[0].FullName
    Assert (Test-Path -LiteralPath (Join-Path $syncGame 'Interface\AddOns\A\a.lua')) 'Bootstrap did not check out addons'
    Assert (-not (Test-Path -LiteralPath (Join-Path $syncGame 'Interface\AddOns\Old'))) 'Bootstrap kept the old Interface'
    Assert (Test-Path -LiteralPath (Join-Path $backup 'Interface\AddOns\Old\o.lua')) 'Old Interface not backed up'
    Assert ((Read-File (Join-Path $syncGame 'Interface\.env')) -eq 'WTF_MAP_VERSION=1') '.env not carried over'
    Assert ((Read-File (Join-Path $backup 'Fonts\YUIText.ttf')) -eq 'old font') 'Overwritten font not backed up'
    Assert ((Read-File (Join-Path $syncGame 'Fonts\YUIText.ttf')) -eq 'new font') 'Tracked font not installed'
    Assert ((Read-File (Join-Path $syncGame 'Fonts\Other.ttf')) -eq 'untracked font') 'Untracked font touched'
    $checks += 7

    $global:restoreCalls = 0
    $global:restoreFails = $null
    $restore = {
        $global:restoreCalls++
        if ($global:restoreFails) { throw $global:restoreFails }
        Write-File (Join-Path $global:syncGame 'WTF\Config.wtf') "SET gxWindowedResolution `"3840x2160`"`r`nSET uiScale `"0.53`"`r`n"
        'Restored 2 settings targets.'
    }
    $global:sleeps = @()
    $sleep = { param($Milliseconds) $global:sleeps += $Milliseconds }
    function Sync([hashtable]$Extra = @{}) {
        $arguments = @{
            Root = $syncGame; StateDirectory = $state; Git = $git; Uv = 'uv.exe'
            ProcessProbe = { $false }; SleepAction = $sleep; RestoreAction = $restore; DisplayProbe = { '3840x2160' }
        }
        foreach ($key in $Extra.Keys) { $arguments[$key] = $Extra[$key] }
        return Invoke-WowSync @arguments
    }
    $configPath = Join-Path $syncGame 'WTF\Config.wtf'

    $result = Sync
    Assert ($result.Fetched -and $null -eq $result.Updated) 'First sync should find the checkout current'
    Assert ($global:restoreCalls -eq 1 -and $result.Restored) 'First sync must restore the bundle'
    Assert ((Get-ConfigResolution $configPath) -eq '2560x1440') 'The pre-restore game setting 3440x1440 must snap to 2560x1440'
    Assert ((Read-File $configPath) -match 'uiScale "0.53"') 'Restored gameplay UI scale must be kept'
    Assert ((Read-File $eui) -match '\["panelScale"\] = 1\.00,' -and (Read-File $eui) -match '測試') 'EUI panel scale or Unicode wrong'
    $checks += 5

    $configHash = (Get-FileHash -LiteralPath $configPath).Hash
    $euiTime = (Get-Item -LiteralPath $eui).LastWriteTimeUtc
    $result = Sync
    Assert ($global:restoreCalls -eq 1) 'An unchanged bundle must not be restored again'
    Assert ((Get-FileHash -LiteralPath $configPath).Hash -eq $configHash) 'Idempotent sync changed Config.wtf'
    Assert ((Get-Item -LiteralPath $eui).LastWriteTimeUtc -eq $euiTime) 'Idempotent sync rewrote EllesmereUI.lua'
    $checks += 3

    Remove-Item -LiteralPath (Join-Path $upstream 'Interface\AddOns\Gone') -Recurse
    Write-File (Join-Path $upstream 'Interface\AddOns\B\b.lua') 'b = 1'
    Write-File (Join-Path $upstream 'Interface\Settings\WTF\global\Config.json') '{"v":2}'
    Commit-Upstream 'update'
    $result = Sync
    Assert ($null -ne $result.Updated) 'New upstream commit not applied'
    Assert (-not (Test-Path -LiteralPath (Join-Path $syncGame 'Interface\AddOns\Gone'))) 'Removed addon still installed'
    Assert (Test-Path -LiteralPath (Join-Path $syncGame 'Interface\AddOns\B\b.lua')) 'Added addon missing'
    Assert ($global:restoreCalls -eq 2) 'Changed bundle not restored'
    Assert ((Get-ConfigResolution $configPath) -eq '2560x1440') 'Resolution not re-fitted after restore'
    $checks += 5

    Write-File $configPath "SET gxWindowedResolution `"1920x1080`"`r`n"
    $null = Sync
    Assert ((Get-ConfigResolution $configPath) -eq '1920x1080') 'In-game change must be adopted'
    Assert ((Read-SyncState $state).appliedResolution -eq '1920x1080') 'Adopted resolution not remembered'
    $null = Sync @{ ResolutionOverride = '3840x2160' }
    Assert ((Get-ConfigResolution $configPath) -eq '3840x2160') 'Fixed resolution not applied'
    $checks += 3

    Write-File (Join-Path $syncGame 'Interface\AddOns\A\a.lua') 'a = "local edit"'
    Write-File (Join-Path $upstream 'Interface\AddOns\A\a.lua') 'a = 2'
    Commit-Upstream 'upstream edit'
    $null = Sync
    $patches = @(Get-ChildItem -LiteralPath $state -Filter 'local-changes-*.patch')
    Assert ($patches.Count -eq 1 -and (Read-File $patches[0].FullName) -match 'local edit') 'Local edit not saved as a patch'
    Assert ((Read-File (Join-Path $syncGame 'Interface\AddOns\A\a.lua')) -eq 'a = 2') 'Local edit not replaced by upstream'
    $checks += 2

    Write-File (Join-Path $upstream 'Interface\Settings\WTF\global\Config.json') '{"v":3}'
    Commit-Upstream 'settings'
    $global:restoreFails = 'Settings helper failed; inspect local settings and retry. Snapshot alias is missing or invalid in the private map.'
    $result = Sync
    Assert (-not $result.Restored -and ($result.Problems -join ' ') -match 'Copy Interface\\\.env') 'Stale .env must produce the copy hint'
    $global:restoreFails = $null
    $result = Sync
    Assert ($result.Restored -and $global:restoreCalls -eq 4) 'Failed restore must be retried at the next sync'
    $checks += 2

    Write-File (Join-Path $upstream 'Interface\Settings\WTF\global\Config.json') '{"v":4}'
    Commit-Upstream 'settings again'
    Remove-Item -LiteralPath (Join-Path $syncGame 'Interface\.env')
    $result = Sync
    Assert (-not $result.Restored -and $global:restoreCalls -eq 4 -and ($result.Problems -join ' ') -match '\.env is missing') 'Missing .env must skip restore'
    Write-File (Join-Path $syncGame 'Interface\.env') 'WTF_MAP_VERSION=1'
    $checks += 1

    $global:probeCalls = 0
    $global:sleeps = @()
    $result = Sync @{ ProcessProbe = { $global:probeCalls++; $global:probeCalls -le 2 } }
    Assert ($global:sleeps.Count -eq 3 -and $global:sleeps[-1] -eq 10000 -and $result.Restored) 'Sync must wait for WoW to close, settle, then continue'
    $checks += 1

    Assert-ConsumerCheckout $git $syncGame
    Write-File (Join-Path $syncGame 'Interface\AddOns\A\a.lua') 'a = "authoring"'
    Invoke-TestGit $syncGame @('commit', '-q', '-am', 'local work')
    $guarded = $false
    try { Assert-ConsumerCheckout $git $syncGame } catch { $guarded = $_.Exception.Message -like '*authoring machine*' }
    Assert $guarded 'Install must refuse a checkout with unpushed commits'
    $result = Sync
    Assert ((Read-File (Join-Path $syncGame 'Interface\AddOns\A\a.lua')) -eq 'a = 2') 'Sync must return to origin'
    Assert ((Invoke-Native $git @('-C', $syncGame, 'branch', '--list', 'sync-backup-*')).Output -match 'sync-backup-') 'Local commits must be kept on a backup branch'
    $checks += 3

    Invoke-TestGit $syncGame @('remote', 'set-url', 'origin', (Join-Path $testRoot 'missing remote'))
    $global:sleeps = @()
    $result = Sync @{ FetchAttempts = 2 }
    Assert (-not $result.Fetched -and ($result.Problems -join ' ') -match 'Fetch failed' -and $global:sleeps.Count -eq 1) 'Offline fetch must retry then continue'
    Assert ($result.Resolution -eq '3840x2160') 'Offline sync must still fit the resolution'
    $checks += 2

    Remove-Item -LiteralPath $configPath
    $result = Sync
    Assert (($result.Problems -join ' ') -match 'Config\.wtf is missing') 'Missing Config.wtf must be reported, not thrown'
    $checks += 1
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Test cleanup escaped the temporary directory.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Output "$checks sync checks passed."
