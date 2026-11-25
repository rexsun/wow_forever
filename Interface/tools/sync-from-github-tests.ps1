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
function Start-DirectoryLock([string]$Path) {
    # A process whose current directory is $Path stops Windows from moving that folder or its parents.
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    return Start-Process -FilePath $powershell -ArgumentList '-NoProfile', '-Command', 'Start-Sleep -Seconds 120' -WorkingDirectory $Path -WindowStyle Hidden -PassThru
}
function Stop-DirectoryLock($Process) {
    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    $Process.WaitForExit()
}
function Commit-Upstream([string]$Message) {
    Invoke-TestGit $upstream @('add', '-A')
    Invoke-TestGit $upstream @('commit', '-q', '-m', $Message)
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('wow sync tests ' + [guid]::NewGuid().ToString('N'))
$upstream = Join-Path $testRoot 'upstream repo'
$global:syncGame = Join-Path $testRoot 'WoW\game root'
$state = Join-Path $testRoot 'private state'
$gitData = Join-Path $testRoot 'git data'
$brokenGitData = Join-Path $gitData 'broken'
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
    Write-File (Join-Path $syncGame 'Interface\Settings\character-ui-source.local.json') '{"enabled": true}'
    Write-File (Join-Path $syncGame 'Interface\AddOns\CharacterUIBaseline\Source.local.lua') 'source = 1'
    Write-File (Join-Path $syncGame 'Fonts\Other.ttf') 'untracked font'
    Write-File (Join-Path $syncGame 'WTF\Config.wtf') "SET gxWindowedResolution `"3440x1440`"`r`nSET uiScale `"0.6`"`r`n"
    $eui = Join-Path $syncGame 'WTF\Account\ACC\SavedVariables\EllesmereUI.lua'
    Write-File $eui "EllesmereUIDB = {`r`n[`"panelScale`"] = 1.5,`r`n[`"marker`"] = `"測試`",`r`n}`r`n"

    $broken = Join-Path $testRoot 'WoW\broken game'
    Write-File (Join-Path $broken 'Wow.exe') ''
    Write-File (Join-Path $broken 'Interface\AddOns\Mine\m.lua') 'mine'
    $failed = $false
    try { Initialize-Checkout $git $broken (Join-Path $testRoot 'no such repo') { $false } $brokenGitData } catch { $failed = $_.Exception.Message -like 'Install failed and was rolled back*' }
    Assert $failed 'Bootstrap from a missing repository must fail with rollback'
    Assert (Test-Path -LiteralPath (Join-Path $broken 'Interface\AddOns\Mine\m.lua')) 'Rollback lost the existing Interface'
    Assert (-not (Test-Path -LiteralPath (Join-Path $broken '.git'))) 'Rollback left a .git folder'
    Assert (-not (Test-Path -LiteralPath $brokenGitData)) 'Rollback left the Git data outside the install'
    $refused = $false
    try { Initialize-Checkout $git $broken $upstream { $true } $brokenGitData } catch { $refused = $_.Exception.Message -like 'Close WoW*' }
    Assert ($refused -and -not (Test-Path -LiteralPath (Join-Path $broken '.git'))) 'Bootstrap must refuse while WoW runs'
    $checks += 4

    $locked = Join-Path $testRoot 'WoW\locked game'
    Write-File (Join-Path $locked 'Wow.exe') ''
    Write-File (Join-Path $locked 'Interface\a.txt') 'top'
    Write-File (Join-Path $locked 'Interface\AddOns\Mine\m.lua') 'mine'
    $lock = Start-DirectoryLock (Join-Path $locked 'Interface\AddOns\Mine')
    $failed = $false
    try { Initialize-Checkout $git $locked $upstream { $false } (Join-Path $gitData 'locked') } catch { $failed = $_.Exception.Message -like '*Close File Explorer windows*' }
    finally { Stop-DirectoryLock $lock }
    Assert $failed 'A locked Interface subfolder must fail with the in-use hint'
    Assert ((Read-File (Join-Path $locked 'Interface\a.txt')) -eq 'top' -and (Test-Path -LiteralPath (Join-Path $locked 'Interface\AddOns\Mine\m.lua'))) 'Partial move was not rolled back'
    Assert (-not (Test-Path -LiteralPath (Join-Path $locked '.git'))) 'Locked rollback left a .git folder'
    $checks += 3

    # Reproduces Install started from a shell whose current directory is Interface.
    $lock = Start-DirectoryLock (Join-Path $syncGame 'Interface')
    try { Initialize-Checkout $git $syncGame $upstream { $false } (Join-Path $gitData 'game') } finally { Stop-DirectoryLock $lock }
    Assert (-not (Test-Path -LiteralPath (Join-Path $syncGame 'addon-backups'))) 'Bootstrap backup written inside the install'
    $backup = @(Get-ChildItem -LiteralPath (Join-Path $testRoot 'WoW Addon Backups\game root') -Directory)[0].FullName
    Assert (Test-Path -LiteralPath (Join-Path $syncGame 'Interface\AddOns\A\a.lua')) 'Bootstrap did not check out addons'
    Assert (-not (Test-Path -LiteralPath (Join-Path $syncGame 'Interface\AddOns\Old'))) 'Bootstrap kept the old Interface'
    Assert (Test-Path -LiteralPath (Join-Path $backup 'Interface\AddOns\Old\o.lua')) 'Old Interface not backed up'
    Assert ((Read-File (Join-Path $syncGame 'Interface\.env')) -eq 'WTF_MAP_VERSION=1') '.env not carried over'
    Assert ((Read-File (Join-Path $syncGame 'Interface\Settings\character-ui-source.local.json')) -eq '{"enabled": true}') 'UI source configuration not carried over'
    Assert ((Read-File (Join-Path $syncGame 'Interface\AddOns\CharacterUIBaseline\Source.local.lua')) -eq 'source = 1') 'UI source metadata not carried over'
    Assert ((Read-File (Join-Path $backup 'Fonts\YUIText.ttf')) -eq 'old font') 'Overwritten font not backed up'
    Assert ((Read-File (Join-Path $syncGame 'Fonts\YUIText.ttf')) -eq 'new font') 'Tracked font not installed'
    Assert ((Read-File (Join-Path $syncGame 'Fonts\Other.ttf')) -eq 'untracked font') 'Untracked font touched'
    Assert (Test-Path -LiteralPath (Join-Path $syncGame '.git') -PathType Leaf) 'Bootstrap must leave only a .git pointer file in the install'
    Assert ((Get-GitPointerTarget $syncGame) -eq (Join-Path $gitData 'game')) 'Bootstrap Git data must live outside the install'
    $checks += 11

    $oldGame = Join-Path $testRoot 'WoW\old game'
    Invoke-TestGit $testRoot @('clone', '-q', $upstream, $oldGame)
    $oldHead = (Invoke-Native $git @('-C', $oldGame, 'rev-parse', 'HEAD')).Output
    $readOnly = { param($Path) @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReadOnly }).Count }
    Assert ((& $readOnly (Join-Path $oldGame '.git')) -gt 0) 'Fixture must have the read-only Git objects Battle.net rejects'
    $taken = Join-Path $gitData 'taken'
    [IO.Directory]::CreateDirectory($taken) | Out-Null
    $refused = $false
    try { Move-GitDataOutOfInstall $git $oldGame $taken | Out-Null } catch { $refused = $_.Exception.Message -like 'Git data is still inside*' }
    Assert ($refused -and (Test-Path -LiteralPath (Join-Path $oldGame '.git') -PathType Container)) 'An occupied destination must leave .git in place'
    $outside = Join-Path $gitData 'old'
    Assert (Move-GitDataOutOfInstall $git $oldGame $outside) 'An in-install .git folder must be moved'
    Assert ((Invoke-Native $git @('-C', $oldGame, 'rev-parse', 'HEAD')).Output -eq $oldHead) 'Moved checkout must keep HEAD'
    Assert ((Invoke-Native $git @('-C', $oldGame, 'status', '--porcelain')).Output -eq '') 'Moved checkout must stay clean'
    Assert ((& $readOnly $oldGame) -eq 0) 'Read-only files left inside the install'
    Assert (@(Get-ChildItem -LiteralPath $oldGame -Force -Filter '.git-moved-*').Count -eq 0) 'Old .git copy left inside the install'
    Assert (-not (Move-GitDataOutOfInstall $git $oldGame $outside)) 'A pointer file must not be moved again'
    $checks += 8

    $cramped = Join-Path $testRoot 'Locked down\WoW\game'
    Write-File (Join-Path $testRoot 'Locked down\WoW Addon Backups') 'a file where the backup folder would go'
    Assert ((Get-AddonBackupRoot $cramped) -eq (Join-Path $cramped 'addon-backups')) 'An unwritable folder beside the install must fall back inside it'
    $checks += 1

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

    $map = "# Private settings aliases.`nWTF_MAP_VERSION=`"1`"`nWTF_TEXT_0000001=`"a`"`n"
    $grown = $map + "WTF_TEXT_0000002=`"b`"`n"
    $decision = Test-PrivateMapUpdate $map $grown
    Assert ($decision.Action -eq 'Replace' -and $decision.Added -eq 1) 'A map with a new alias must replace the local copy'
    Assert ((Test-PrivateMapUpdate $map $map).Action -eq 'Keep') 'An identical map must be kept'
    Assert ((Test-PrivateMapUpdate '' $map).Action -eq 'Replace') 'A missing local map must be replaced'
    Assert ((Test-PrivateMapUpdate $grown $map).Action -eq 'Reject') 'A map that drops an alias must be refused'
    Assert ((Test-PrivateMapUpdate $map ($map -replace '"a"', '"z"')).Action -eq 'Reject') 'A map that changes an alias must be refused'
    Assert ((Test-PrivateMapUpdate $map "'type' is not recognized as an internal or external command,`r`n").Action -eq 'Reject') 'Command output must not pass as a map'
    Assert ((Test-PrivateMapUpdate $map "WTF_TEXT_0000001=`"a`"`n").Action -eq 'Reject') 'A map without its version must be refused'
    $checks += 7

    $mapBytes = [Text.UTF8Encoding]::new($false).GetBytes("WTF_TEXT_0000009=`"測試`"`r`nlast line without newline")
    $encoded = [Convert]::ToBase64String($mapBytes)
    $wrapped = $encoded.Substring(0, 10) + "`r`n" + $encoded.Substring(10) + "`r`n"
    $decoded = ConvertFrom-PrivateMapOutput $wrapped
    Assert ($decoded -is [byte[]] -and [Convert]::ToBase64String($decoded) -eq $encoded) 'Base64 map output must decode to the exact bytes'
    $refused = 0
    foreach ($bad in @('', "Permission denied (publickey).`r`n", 'WTF_MAP_VERSION="1"', 'QUJD=Q')) {
        try { $null = ConvertFrom-PrivateMapOutput $bad } catch { if ($_.Exception.Message -like '*did not send an alias map*') { $refused++ } }
    }
    Assert ($refused -eq 4) 'Output that is not base64 must be refused'
    $checks += 2

    $listener = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $openPort = $listener.LocalEndpoint.Port
    Assert (Test-SourceReachable '127.0.0.1' $openPort 3000) 'A listening port must count as reachable'
    $listener.Stop()
    $started = Get-Date
    Assert (-not (Test-SourceReachable '127.0.0.1' $openPort 3000)) 'A closed port must count as unreachable'
    Assert (-not (Test-SourceReachable 'no-such-host.invalid' 22 3000)) 'An unknown host must count as unreachable'
    Assert (((Get-Date) - $started).TotalSeconds -lt 10) 'Reachability checks must respect their timeout'
    $checks += 4

    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $started = Get-Date
    $timedOut = $false
    try { $null = Invoke-Native $powershell @('-NoProfile', '-Command', 'Start-Sleep -Seconds 60') -TimeoutSeconds 2 }
    catch { $timedOut = $_.Exception.Message -like '*did not finish within 2 seconds*' }
    Assert ($timedOut -and ((Get-Date) - $started).TotalSeconds -lt 20) 'A hung native command must be stopped at its timeout'
    $quick = Invoke-Native $powershell @('-NoProfile', '-Command', 'Write-Output done') -TimeoutSeconds 30
    Assert ($quick.Code -eq 0 -and $quick.Output -eq 'done') 'A timeout must not change a command that finishes'
    $checks += 2

    $global:envPath = Join-Path $syncGame 'Interface\.env'
    Write-File $global:envPath $map
    $global:fetchCalls = 0
    $global:fetchFails = $null
    $global:fetched = $grown + "WTF_TEXT_0000003=`"測試`"`n"
    $fetch = {
        $global:fetchCalls++
        if ($global:fetchFails) { throw $global:fetchFails }
        , [Text.UTF8Encoding]::new($false).GetBytes($global:fetched)
    }
    $global:mapAtRestore = $null
    $restoreWithMap = { $global:mapAtRestore = Read-File $global:envPath; & $restore }
    $mapSync = @{ PrivateMapFetch = $fetch; RestoreAction = $restoreWithMap }

    Write-File (Join-Path $upstream 'Interface\Settings\WTF\global\Config.json') '{"v":5}'
    Commit-Upstream 'settings with a new alias'
    $result = Sync $mapSync
    Assert ($global:fetchCalls -eq 1 -and $result.Restored -and $result.PrivateMap -like 'Updated*') 'A pending restore must fetch the map first'
    Assert ($global:mapAtRestore -eq $global:fetched) 'Restore must run against the fetched map'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($global:envPath)) -eq [Convert]::ToBase64String([Text.UTF8Encoding]::new($false).GetBytes($global:fetched))) 'Fetched map bytes changed on disk'
    $backups = @(Get-ChildItem -LiteralPath $state -Filter 'env-*.bak')
    Assert ($backups.Count -eq 1 -and (Read-File $backups[0].FullName) -eq $map) 'Replaced map must be backed up in the private state'
    $checks += 4

    $result = Sync $mapSync
    Assert ($global:fetchCalls -eq 1 -and $null -eq $result.PrivateMap) 'No pending restore must mean no fetch'
    $checks += 1

    Write-File (Join-Path $upstream 'Interface\Settings\WTF\global\Config.json') '{"v":6}'
    Commit-Upstream 'settings while the source is off'
    $before = Read-File $global:envPath
    $global:fetchFails = 'ssh to source failed: connect to host source port 22: Connection timed out.'
    $result = Sync $mapSync
    Assert ($result.Restored -and $result.PrivateMap -like 'Failed*timed out*') 'An unreachable source must not block the restore'
    Assert ((Read-File $global:envPath) -eq $before) 'A failed fetch must leave the map alone'
    $global:fetchFails = $null
    $checks += 2

    Write-File (Join-Path $upstream 'Interface\Settings\WTF\global\Config.json') '{"v":7}'
    Commit-Upstream 'settings from a shrunken map'
    $global:fetched = $map
    $result = Sync $mapSync
    Assert ($result.PrivateMap -like 'Failed*drops or changes 2*' -and (Read-File $global:envPath) -eq $before) 'A map losing aliases must be refused'
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

    $fakeRoot = Join-Path $testRoot 'restore root'
    $uvLog = Join-Path $testRoot 'uv calls.txt'
    $fakeUv = Join-Path $testRoot 'fake uv.cmd'
    Write-File $fakeUv "@echo %~1 %~2 %~3>>`"$uvLog`"`r`n@if `"%~2`"==`"find`" if exist `"$testRoot\python ready`" exit /b 0`r`n@if `"%~2`"==`"find`" exit /b 2`r`n@if `"%~2`"==`"install`" echo.>`"$testRoot\python ready`"`r`n@exit /b 0`r`n"
    $fakeWatcher = Join-Path $fakeRoot 'Interface\watch_wtf_settings.ps1'
    Write-File $fakeWatcher "param(`$Mode, `$UvPath)`nif (`$env:FAKE_RESTORE_FAIL) { throw 'Settings helper failed; inspect local settings and retry. Mapped account or character folder is missing.' }`nWrite-Output ('Restored 3 settings targets via ' + (Split-Path `$UvPath -Leaf))`n"
    $message = Invoke-DefaultRestore $fakeRoot $fakeUv
    Assert ($message -eq 'Restored 3 settings targets via fake uv.cmd') "Restore success output wrong: $message"
    $calls = @(Get-Content -LiteralPath $uvLog)
    Assert ($calls.Count -eq 2 -and $calls[1] -like 'python install 3.13*') 'Missing Python must be installed once through uv'
    $null = Invoke-DefaultRestore $fakeRoot $fakeUv
    Assert (@(Get-Content -LiteralPath $uvLog).Count -eq 3) 'An installed Python must not be reinstalled'
    $env:FAKE_RESTORE_FAIL = '1'
    $reason = $null
    try { Invoke-DefaultRestore $fakeRoot $fakeUv | Out-Null } catch { $reason = $_.Exception.Message } finally { $env:FAKE_RESTORE_FAIL = $null }
    Assert ($reason -eq 'Settings helper failed; inspect local settings and retry. Mapped account or character folder is missing.') "Restore failure reason lost: $reason"
    Assert ((Get-ResolutionHint 'No uv-managed Python 3.13 or newer was found') -like 'Run: uv python install*') 'Python hint missing'
    $checks += 5
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Test cleanup escaped the temporary directory.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Output "$checks sync checks passed."
