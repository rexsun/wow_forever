<#
.SYNOPSIS
Keeps this installation's Interface on the repository's main branch, applies its settings bundle and fits the
window resolution to this machine.
.DESCRIPTION
Install (once, with WoW closed): turns the game root into a checkout of the repository when it is not one yet,
records git/uv and an optional fixed resolution, registers a hidden current-user sign-in task and runs one sync.
The previous Interface folder is moved to bootstrap-<timestamp> in the backup folder beside the WoW install
(WoW Addon Backups\<game folder>, see Get-AddonBackupRoot); the Git-ignored private files in it
(Interface\.env and the CharacterUIBaseline source configuration) are carried over.

Sync (what the sign-in task runs): fetch main, wait for WoW to close, move the checkout to main, restore the
Settings\WTF bundle through watch_wtf_settings.ps1 when the bundle changed since its last successful restore,
then set gxWindowedResolution and the EllesmereUI options-panel scale. Tracked local edits are saved as a patch
in the private state directory before they are overwritten. Restore needs Interface\.env copied from the main
machine and an account folder created by logging in once; until then it is retried at every sign-in.

Resolution: a fixed -Resolution chosen at Install wins. Otherwise the game's own setting is adopted whenever it
differs from what this script last wrote (first run, or a change made in game), else the primary display is used.
Values snap to the largest supported size that fits: 1920x1080, 2560x1440 or 3840x2160.

Private map: with -EnvSource user@host (and -EnvSourceKey for a dedicated key) given at Install, every sync with a
pending restore first fetches Interface\.env from that machine over SSH. The fetched map replaces the local one only
when it keeps every alias the local copy has; the old copy is kept in the private state directory. When the source
is off or unreachable the local copy is used and the restore is retried at the next sign-in. -EnvSource off clears
the setting.

Uninstall removes the task only. Status prints configuration, state and the recent log.
.EXAMPLE
.\Interface\sync_from_github.ps1 -Mode Install
.EXAMPLE
.\sync_from_github.ps1 -Mode Install -GameRoot 'D:\Games\World of Warcraft\_forever_' -Resolution 2560x1440
#>
[CmdletBinding()]
param(
    [ValidateSet('Sync', 'Install', 'Uninstall', 'Status')]
    [string]$Mode = 'Sync',
    [string]$GameRoot,
    [string]$Repository = 'https://github.com/rexsun/wow_forever.git',
    [ValidatePattern('^[A-Za-z0-9._/-]+$')]
    [string]$Branch = 'main',
    [ValidateSet('Auto', '1920x1080', '2560x1440', '3840x2160')]
    [string]$Resolution,
    [ValidatePattern('^(off|[A-Za-z0-9._-]+@[A-Za-z0-9._-]+)$')]
    [string]$EnvSource,
    [string]$EnvSourceKey
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:LogPath = $null
# Git-ignored files under Interface that GitHub cannot provide; Install keeps them from the replaced folder.
$PrivateInterfaceFiles = @(
    '.env',
    'Settings\character-ui-source.local.json',
    'AddOns\CharacterUIBaseline\Source.local.lua'
)

<#
.SYNOPSIS
Where backups for this game root go; matches adopt_addons.ps1 and addon_backup_root in tools\character_ui_baseline.py.
.DESCRIPTION
Kept here rather than in a module because Install runs before the game root has a checkout. The folder holding the
WoW install gets 'WoW Addon Backups\<game folder>': outside the Battle.net install, which scans and repairs every file
under it, but on the same volume so folders can be moved in. A game root with no folder above its install keeps the
old in-game 'addon-backups'.
#>
function Get-AddonBackupRoot([string]$GameRoot) {
    $game = [IO.Path]::GetFullPath($GameRoot).TrimEnd('\')
    $install = [IO.Path]::GetDirectoryName($game)
    $outside = if ($install) { [IO.Path]::GetDirectoryName($install) } else { $null }
    if (-not $outside) { return Join-Path $game 'addon-backups' }
    return Join-Path $outside ('WoW Addon Backups\' + [IO.Path]::GetFileName($game))
}

function Get-InstallationId([string]$Root) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Root.ToLowerInvariant())
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').Substring(0, 16).ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Resolve-GameRoot([string]$Requested) {
    $candidate = if ($Requested) { $Requested }
    elseif ((Split-Path $PSScriptRoot -Leaf) -ieq 'Interface') { Split-Path $PSScriptRoot -Parent }
    else { throw 'Supply -GameRoot (the folder containing Wow.exe, Interface and WTF).' }
    $root = [IO.Path]::GetFullPath($candidate).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Game root does not exist: $root" }
    if (@(Get-ChildItem -LiteralPath $root -Filter 'Wow*.exe' -File).Count -eq 0) {
        throw "Not a game root (no Wow*.exe): $root"
    }
    return $root
}

function Get-StateDirectory([string]$Root) {
    return Join-Path $env:LOCALAPPDATA ('WowSettings\' + (Get-InstallationId $Root))
}

function Write-SyncLog([string]$Message) {
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    if (-not $script:LogPath) { return }
    if ((Test-Path -LiteralPath $script:LogPath) -and (Get-Item -LiteralPath $script:LogPath).Length -gt 1MB) {
        Move-Item -LiteralPath $script:LogPath -Destination ($script:LogPath + '.old') -Force
    }
    Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
}

function Invoke-Native([string]$Executable, [string[]]$Arguments, [hashtable]$Environment = @{}, [int]$TimeoutSeconds = 0) {
    $start = New-Object Diagnostics.ProcessStartInfo
    foreach ($name in $Environment.Keys) { $start.EnvironmentVariables[$name] = [string]$Environment[$name] }
    $start.FileName = $Executable
    $start.Arguments = ($Arguments | ForEach-Object {
        '"' + ($_ -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
    }) -join ' '
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if ($TimeoutSeconds -gt 0 -and -not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch { }
            throw "$([IO.Path]::GetFileName($Executable)) did not finish within $TimeoutSeconds seconds."
        }
        $process.WaitForExit()
        return [pscustomobject]@{
            Code   = $process.ExitCode
            Output = $stdout.GetAwaiter().GetResult().TrimEnd("`r", "`n")
            Error  = $stderr.GetAwaiter().GetResult().TrimEnd("`r", "`n")
        }
    } finally { $process.Dispose() }
}

function Get-LastLine([string]$Text) {
    $lines = @($Text -split '\r?\n' | Where-Object { $_.Trim() })
    if ($lines.Count -eq 0) { return '' }
    return $lines[-1].Trim()
}

function Get-GitReason($Result) {
    $text = $Result.Error + "`n" + $Result.Output
    $fatal = @($text -split '\r?\n' | Where-Object { $_ -match '^(fatal|error):' } | Select-Object -First 1)
    $reason = if ($fatal.Count -eq 1) { $fatal[0].Trim() } else { Get-LastLine $text }
    return $reason.TrimEnd('.')
}

function Invoke-Git([string]$Git, [string]$Root, [string[]]$Arguments, [switch]$AllowFailure) {
    $result = Invoke-Native $Git (@('-C', $Root) + $Arguments)
    if ($result.Code -ne 0 -and -not $AllowFailure) {
        throw ("git $($Arguments[0]) failed: " + (Get-GitReason $result))
    }
    return $result
}

function Test-InstallationRunning([string]$Root) {
    foreach ($process in @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Wow%.exe'")) {
        # An unreadable path may be this installation, so it counts as running.
        if (-not $process.ExecutablePath) { return $true }
        if ((Split-Path $process.ExecutablePath -Parent) -ieq $Root) { return $true }
    }
    return $false
}

function Read-SyncState([string]$StateDirectory) {
    $path = Join-Path $StateDirectory 'sync.json'
    $state = @{}
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $json = [IO.File]::ReadAllText($path) | ConvertFrom-Json
        foreach ($property in $json.PSObject.Properties) { $state[$property.Name] = $property.Value }
    }
    return $state
}

function Save-SyncState([string]$StateDirectory, [hashtable]$State) {
    [IO.Directory]::CreateDirectory($StateDirectory) | Out-Null
    $path = Join-Path $StateDirectory 'sync.json'
    $temporary = $path + '.tmp'
    [IO.File]::WriteAllText($temporary, ($State | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $path -Force
}

function Get-StateValue([hashtable]$State, [string]$Name) {
    if ($State.ContainsKey($Name)) { return $State[$Name] }
    return $null
}

function Update-SyncState([hashtable]$State, [hashtable]$Changes) {
    $next = @{}
    foreach ($key in $State.Keys) { $next[$key] = $State[$key] }
    foreach ($key in $Changes.Keys) { $next[$key] = $Changes[$key] }
    return $next
}

function Get-ResolutionHint([string]$Message) {
    if ($Message -match 'alias|\.env|private map') {
        return 'Copy Interface\.env from the main machine again (or Install with -EnvSource so sync fetches it); it gains aliases whenever settings are exported there.'
    }
    if ($Message -match 'Python') {
        return 'Run: uv python install 3.13'
    }
    if ($Message -match 'account or character folder') {
        return 'Log in to the game once with the same account so its WTF folder exists.'
    }
    return 'It will be retried at the next sign-in.'
}

<#
.SYNOPSIS
Chooses the window resolution: fixed override, then a game setting this script did not write, then the last
applied value, then the display. Returns @{ Resolution; Source }.
#>
function Resolve-TargetResolution([string]$Override, [string]$Live, [string]$Applied, [scriptblock]$DisplayProbe) {
    if ($Override -and $Override -ne 'Auto') { return @{ Resolution = $Override; Source = 'fixed' } }
    if ($Live -and $Live -ne $Applied) {
        $size = $Live.Split('x')
        return @{ Resolution = (ConvertTo-SupportedResolution ([int]$size[0]) ([int]$size[1])); Source = "game setting $Live" }
    }
    if ($Applied) { return @{ Resolution = $Applied; Source = 'previous' } }
    $display = & $DisplayProbe
    $size = $display.Split('x')
    return @{ Resolution = (ConvertTo-SupportedResolution ([int]$size[0]) ([int]$size[1])); Source = "display $display" }
}

function Wait-GameClosed([scriptblock]$ProcessProbe, [scriptblock]$SleepAction) {
    $waited = $false
    while ($true) {
        $running = $true
        try { $running = [bool](& $ProcessProbe) } catch { $running = $true }
        if (-not $running) { break }
        if (-not $waited) { Write-SyncLog 'WoW is running; waiting for it to close.' }
        $waited = $true
        & $SleepAction 30000
    }
    # Give the client time to finish writing SavedVariables after it exits.
    if ($waited) { & $SleepAction 10000 }
}

function Update-Checkout([string]$Git, [string]$Root, [string]$Target, [string]$StateDirectory) {
    $head = (Invoke-Git $Git $Root @('rev-parse', '--verify', '--quiet', 'HEAD') -AllowFailure).Output
    $targetCommit = (Invoke-Git $Git $Root @('rev-parse', '--verify', $Target)).Output
    $dirty = (Invoke-Git $Git $Root @('status', '--porcelain', '--untracked-files=no')).Output
    $currentBranch = (Invoke-Git $Git $Root @('symbolic-ref', '--quiet', '--short', 'HEAD') -AllowFailure).Output
    if ($head -eq $targetCommit -and -not $dirty -and $currentBranch -eq $Branch) { return $null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    if ($dirty) {
        [IO.Directory]::CreateDirectory($StateDirectory) | Out-Null
        $patch = Join-Path $StateDirectory ("local-changes-$stamp.patch")
        Invoke-Git $Git $Root @('diff', 'HEAD', '--binary', ('--output=' + $patch)) | Out-Null
        Write-SyncLog "Local edits to tracked files saved to $patch before being replaced."
    }
    if ($head -and (Invoke-Git $Git $Root @('merge-base', '--is-ancestor', 'HEAD', $targetCommit) -AllowFailure).Code -ne 0) {
        Invoke-Git $Git $Root @('branch', '-f', "sync-backup-$stamp", 'HEAD') | Out-Null
        Write-SyncLog "Local commits kept on branch sync-backup-$stamp."
    }
    Invoke-Git $Git $Root @('checkout', '--force', '-B', $Branch, $targetCommit) | Out-Null
    return @{ From = $head; To = $targetCommit }
}

<#
.SYNOPSIS
Makes sure uv has a Python 3.13+ for the settings helper, installing one into uv's user store when none exists.
#>
function Initialize-UvPython([string]$Uv) {
    if ((Invoke-Native $Uv @('python', 'find', '--no-project', '>=3.13')).Code -eq 0) { return }
    Write-SyncLog 'No Python 3.13+ found for uv; installing it with uv python install 3.13.'
    $install = Invoke-Native $Uv @('python', 'install', '3.13')
    if ($install.Code -ne 0) { throw ('uv could not install Python 3.13: ' + (Get-LastLine $install.Error)) }
}

function Get-MapLines([string]$Text) {
    return @($Text.TrimStart([char]0xFEFF) -split '\r?\n' | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ })
}

<#
.SYNOPSIS
Decides whether a fetched alias map may replace the local Interface\.env. Returns @{ Action = Keep|Replace|Reject;
Reason; Added }. The main machine only ever adds aliases, so a map that drops or changes one the local copy has is
the wrong file and is refused.
#>
function Test-PrivateMapUpdate([string]$Current, [string]$Fetched) {
    $lines = @(Get-MapLines $Fetched)
    $foreign = @($lines | Where-Object { -not $_.StartsWith('#') -and $_ -notmatch '^[A-Za-z_][A-Za-z0-9_]*=' })
    if ($lines.Count -eq 0 -or $foreign.Count -gt 0) {
        return [pscustomobject]@{ Action = 'Reject'; Reason = 'the source did not send an alias map.'; Added = 0 }
    }
    if (@($lines | Where-Object { $_ -cmatch '^WTF_MAP_VERSION="?1"?$' }).Count -ne 1) {
        return [pscustomobject]@{ Action = 'Reject'; Reason = 'the fetched map has no WTF_MAP_VERSION 1.'; Added = 0 }
    }
    if ($Fetched -ceq $Current) { return [pscustomobject]@{ Action = 'Keep'; Reason = $null; Added = 0 } }
    $aliasPattern = '^WTF_(TEXT|NUMBER)_\d{7}='
    $fetchedAliases = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($line in $lines) { if ($line -cmatch $aliasPattern) { [void]$fetchedAliases.Add($line) } }
    $currentAliases = @(Get-MapLines $Current | Where-Object { $_ -cmatch $aliasPattern })
    $missing = @($currentAliases | Where-Object { -not $fetchedAliases.Contains($_) }).Count
    if ($missing -gt 0) {
        return [pscustomobject]@{ Action = 'Reject'; Reason = "the fetched map drops or changes $missing alias(es) the local copy has."; Added = 0 }
    }
    return [pscustomobject]@{ Action = 'Replace'; Reason = $null; Added = $fetchedAliases.Count - $currentAliases.Count }
}

function ConvertFrom-PrivateMapOutput([string]$Text) {
    $compact = $Text -replace '\s', ''
    if (-not $compact -or $compact -notmatch '^[A-Za-z0-9+/]+={0,2}$') { throw 'the source did not send an alias map.' }
    try { return , [Convert]::FromBase64String($compact) }
    catch { throw 'the source did not send an alias map.' }
}

function Test-SourceReachable([string]$HostName, [int]$Port = 22, [int]$TimeoutMilliseconds = 5000) {
    $client = New-Object Net.Sockets.TcpClient
    try { return ($client.ConnectAsync($HostName, $Port).Wait($TimeoutMilliseconds) -and $client.Connected) }
    catch { return $false }
    finally { $client.Dispose() }
}

<#
.SYNOPSIS
Reads the main machine's Interface\.env over SSH. The source authorizes this machine's key with a forced command
that prints the file as base64, so the requested command is only a label and no shell between can re-encode the
UTF-8 text. -n closes stdin, which a PowerShell default shell would otherwise wait on.
#>
function Get-PrivateMapFromSource([string]$Source, [string]$Key) {
    # Windows ssh.exe started without a console can ignore ConnectTimeout and hang on a host that is switched off,
    # so reachability is checked first and the call itself has a hard limit.
    $hostName = $Source.Substring($Source.IndexOf('@') + 1)
    if (-not (Test-SourceReachable $hostName)) { throw "$Source does not answer on port 22 (switched off or offline)." }
    $ssh = Find-Tool 'ssh' 'The OpenSSH client (ssh.exe) is not installed.'
    $arguments = @('-n', '-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', '-o', 'ServerAliveInterval=5',
        '-o', 'ServerAliveCountMax=2', '-o', 'StrictHostKeyChecking=accept-new', '-o', 'LogLevel=ERROR')
    if ($Key) { $arguments += @('-i', $Key, '-o', 'IdentitiesOnly=yes') }
    $result = Invoke-Native $ssh ($arguments + @($Source, 'private-map')) -TimeoutSeconds 60
    if ($result.Code -ne 0) {
        $reason = Get-LastLine $result.Error
        if (-not $reason) { $reason = "exit code $($result.Code)" }
        throw "ssh to $Source failed: $($reason.TrimEnd('.'))."
    }
    return , (ConvertFrom-PrivateMapOutput $result.Output)
}

function Update-PrivateMap([string]$Root, [string]$StateDirectory, [byte[]]$Fetched) {
    $path = Join-Path $Root 'Interface\.env'
    try { $text = [Text.UTF8Encoding]::new($false, $true).GetString($Fetched) }
    catch { throw 'the fetched map is not UTF-8.' }
    $current = if (Test-Path -LiteralPath $path -PathType Leaf) { [IO.File]::ReadAllText($path) } else { '' }
    $decision = Test-PrivateMapUpdate $current $text
    if ($decision.Action -eq 'Reject') { throw $decision.Reason }
    if ($decision.Action -eq 'Keep') { return 'Current.' }
    if ($current) {
        [IO.Directory]::CreateDirectory($StateDirectory) | Out-Null
        Copy-Item -LiteralPath $path -Destination (Join-Path $StateDirectory ('env-{0}.bak' -f (Get-Date -Format 'yyyyMMdd-HHmmss')))
        Get-ChildItem -LiteralPath $StateDirectory -Filter 'env-*.bak' | Sort-Object Name -Descending |
            Select-Object -Skip 5 | Remove-Item -Force
    }
    $temporary = $path + '.sync-tmp'
    [IO.File]::WriteAllBytes($temporary, $Fetched)
    Move-Item -LiteralPath $temporary -Destination $path -Force
    return "Updated: $($decision.Added) new alias(es)."
}

# Prefix that marks the one line of the restore child's output carrying its failure reason.
$script:RestoreErrorPrefix = 'RESTORE-ERROR: '

function Invoke-DefaultRestore([string]$Root, [string]$Uv) {
    Initialize-UvPython $Uv
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    # Paths travel as environment variables, so no quoting is needed. The catch keeps the failure reason on one line
    # instead of PowerShell's multi-line error record.
    $command = '$ErrorActionPreference = ''Stop''; try { & $env:WOWSYNC_WATCHER -Mode Restore -UvPath $env:WOWSYNC_UV } ' +
        'catch { [Console]::Out.WriteLine($env:WOWSYNC_PREFIX + $_.Exception.Message); exit 1 }'
    $environment = @{
        WOWSYNC_WATCHER = (Join-Path $Root 'Interface\watch_wtf_settings.ps1')
        WOWSYNC_UV      = $Uv
        WOWSYNC_PREFIX  = $script:RestoreErrorPrefix
    }
    $result = Invoke-Native $powershell @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', $command) $environment
    if ($result.Code -ne 0) {
        $reason = @($result.Output -split '\r?\n' | Where-Object { $_.StartsWith($script:RestoreErrorPrefix) } | Select-Object -Last 1)
        if ($reason.Count -eq 1) { throw $reason[0].Substring($script:RestoreErrorPrefix.Length) }
        throw ('Restore exited with code ' + $result.Code + ': ' + (Get-LastLine ($result.Output + "`n" + $result.Error)))
    }
    return Get-LastLine $result.Output
}

<#
.SYNOPSIS
One sync pass. Collaborators are injectable for tests. Returns a summary object.
#>
function Invoke-WowSync {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$StateDirectory,
        [Parameter(Mandatory = $true)][string]$Git,
        [string]$Uv,
        [string]$ResolutionOverride,
        [scriptblock]$ProcessProbe = { Test-InstallationRunning $Root },
        [scriptblock]$SleepAction = { param($Milliseconds) Start-Sleep -Milliseconds $Milliseconds },
        [scriptblock]$RestoreAction = { Invoke-DefaultRestore $Root $Uv },
        [scriptblock]$DisplayProbe = { Get-DisplayResolution },
        [int]$FetchAttempts = 3,
        [string]$EnvSource,
        [string]$EnvSourceKey,
        [scriptblock]$PrivateMapFetch = { Get-PrivateMapFromSource $EnvSource $EnvSourceKey }
    )
    $state = Read-SyncState $StateDirectory
    $summary = [ordered]@{
        Fetched = $false; Updated = $null; Restored = $false; Resolution = $null; PrivateMap = $null; Problems = @()
    }
    $refreshMap = $EnvSource -or $PSBoundParameters.ContainsKey('PrivateMapFetch')
    $target = "refs/remotes/origin/$Branch"

    for ($attempt = 1; $attempt -le $FetchAttempts; $attempt++) {
        $fetch = Invoke-Git $Git $Root @('fetch', '--no-tags', '--prune', 'origin', "+refs/heads/${Branch}:$target") -AllowFailure
        if ($fetch.Code -eq 0) { $summary.Fetched = $true; break }
        if ($attempt -lt $FetchAttempts) { & $SleepAction 30000 }
    }
    if (-not $summary.Fetched) {
        $summary.Problems += 'Fetch failed: ' + (Get-GitReason $fetch) + '. Using the current checkout.'
        Write-SyncLog $summary.Problems[-1]
    }

    Wait-GameClosed $ProcessProbe $SleepAction
    $wtf = Join-Path $Root 'WTF'
    $configPath = Join-Path $wtf 'Config.wtf'
    $hasConfig = Test-Path -LiteralPath $configPath -PathType Leaf

    $haveTarget = (Invoke-Git $Git $Root @('rev-parse', '--verify', '--quiet', $target) -AllowFailure).Code -eq 0
    if ($haveTarget) {
        $change = Update-Checkout $Git $Root $target $StateDirectory
        if ($change) {
            $summary.Updated = $change
            Write-SyncLog ('Interface updated {0} -> {1}.' -f $(if ($change.From) { $change.From.Substring(0, 7) } else { 'none' }), $change.To.Substring(0, 7))
        } else { Write-SyncLog 'Interface already on the latest commit.' }
    }

    Import-Module (Join-Path $Root 'Interface\tools\WowResolution.psm1') -Force
    $live = if ($hasConfig) { Get-ConfigResolution $configPath } else { $null }

    $tree = (Invoke-Git $Git $Root @('rev-parse', '--verify', '--quiet', 'HEAD:Interface/Settings/WTF') -AllowFailure).Output
    if ($tree -and $tree -ne (Get-StateValue $state 'restoredTree')) {
        # Only a pending restore needs the map, and a source that is switched off must not block the restore.
        if ($refreshMap) {
            try {
                $summary.PrivateMap = Update-PrivateMap $Root $StateDirectory ([byte[]](& $PrivateMapFetch))
                Write-SyncLog ('Interface\.env from the main machine: ' + $summary.PrivateMap)
            } catch {
                $summary.PrivateMap = 'Failed: ' + $_.Exception.Message
                Write-SyncLog ('Interface\.env not refreshed, using the local copy: ' + $_.Exception.Message)
            }
        }
        $skip = if (-not $hasConfig) { 'WTF\Config.wtf is missing; start the game once and log in.' }
        elseif (-not (Test-Path -LiteralPath (Join-Path $Root 'Interface\.env') -PathType Leaf)) {
            'Interface\.env is missing; copy it from the main machine.'
        } elseif (-not $Uv) { 'uv is not installed; install it and run Install again.' }
        else { $null }
        if ($skip) {
            $summary.Problems += "Settings restore skipped: $skip"
            Write-SyncLog $summary.Problems[-1]
        } else {
            try {
                $message = & $RestoreAction
                $summary.Restored = $true
                $state = Update-SyncState $state @{ restoredTree = $tree }
                Write-SyncLog "Settings bundle restored. $message"
            } catch {
                $failure = $_.Exception.Message
                $summary.Problems += "Settings restore failed: $failure $(Get-ResolutionHint $failure)"
                Write-SyncLog $summary.Problems[-1]
            }
        }
    }

    if ($hasConfig) {
        try {
            $choice = Resolve-TargetResolution $ResolutionOverride $live (Get-StateValue $state 'appliedResolution') $DisplayProbe
            $changed = Set-WowResolution -WtfPath $wtf -Resolution $choice.Resolution
            $state = Update-SyncState $state @{ appliedResolution = $choice.Resolution }
            $summary.Resolution = $choice.Resolution
            Write-SyncLog ('Resolution {0} ({1}); {2} file(s) changed.' -f $choice.Resolution, $choice.Source, $changed)
        } catch {
            $summary.Problems += 'Resolution not applied: ' + $_.Exception.Message
            Write-SyncLog $summary.Problems[-1]
        }
    } else {
        $summary.Problems += 'Resolution not applied: WTF\Config.wtf is missing; start the game once.'
        Write-SyncLog $summary.Problems[-1]
    }

    $head = (Invoke-Git $Git $Root @('rev-parse', '--verify', '--quiet', 'HEAD') -AllowFailure).Output
    Save-SyncState $StateDirectory (Update-SyncState $state @{ lastCommit = $head; lastRun = (Get-Date).ToString('o') })
    return [pscustomobject]$summary
}

function Grant-SafeDirectory([string]$Git, [string]$Root) {
    $probe = Invoke-Git $Git $Root @('rev-parse', '--git-dir') -AllowFailure
    if ($probe.Code -eq 0 -or $probe.Error -notmatch 'dubious ownership') { return }
    $path = $Root.Replace('\', '/')
    Invoke-Native $Git @('config', '--global', '--add', 'safe.directory', $path) | Out-Null
    Write-SyncLog "Marked $path as a safe git directory (the folder is owned by another account)."
}

<#
.SYNOPSIS
Renames a file or folder within one volume, or throws with nothing moved.
.DESCRIPTION
Move-Item is avoided because, when a folder below the source is in use, it falls back to copy-then-delete and
leaves the content split between both places.
#>
function Move-PathAtomic([string]$Source, [string]$Destination) {
    if (Test-Path -LiteralPath $Source -PathType Container) { [IO.Directory]::Move($Source, $Destination) }
    else { [IO.File]::Move($Source, $Destination) }
}

<#
.SYNOPSIS
Turns an existing game root into a checkout of the repository. The old Interface contents and any tracked font
the checkout would overwrite are moved or copied to bootstrap-<timestamp> in the backup folder; a failure puts them back.
.DESCRIPTION
The Interface folder itself stays in place: Windows refuses to move a folder that is any process's current
directory, which it is whenever Install is started from inside Interface.
#>
function Initialize-Checkout([string]$Git, [string]$Root, [string]$Repo, [scriptblock]$ProcessProbe) {
    if (& $ProcessProbe) { throw 'Close WoW before installing. Nothing was changed.' }
    $backup = Join-Path (Get-AddonBackupRoot $Root) ('bootstrap-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $interface = Join-Path $Root 'Interface'
    $previous = Join-Path $backup 'Interface'
    $movedItems = New-Object Collections.Generic.List[string]
    $checkoutStarted = $false
    $savedFonts = @()
    try {
        Invoke-Git $Git $Root @('init', '--quiet') | Out-Null
        Grant-SafeDirectory $Git $Root
        Invoke-Git $Git $Root @('remote', 'add', 'origin', $Repo) | Out-Null
        Invoke-Git $Git $Root @('fetch', '--no-tags', 'origin', "+refs/heads/${Branch}:refs/remotes/origin/$Branch") | Out-Null
        [IO.Directory]::CreateDirectory($backup) | Out-Null
        $fonts = (Invoke-Git $Git $Root @('ls-tree', '-r', '--name-only', "origin/$Branch", '--', 'Fonts')).Output
        foreach ($font in @($fonts -split '\r?\n' | Where-Object { $_ })) {
            $existing = Join-Path $Root $font
            if (Test-Path -LiteralPath $existing -PathType Leaf) {
                $saved = Join-Path $backup $font
                [IO.Directory]::CreateDirectory((Split-Path $saved -Parent)) | Out-Null
                Copy-Item -LiteralPath $existing -Destination $saved
                $savedFonts += $font
            }
        }
        [IO.Directory]::CreateDirectory($previous) | Out-Null
        if (Test-Path -LiteralPath $interface) {
            foreach ($item in @(Get-ChildItem -LiteralPath $interface -Force)) {
                Move-PathAtomic $item.FullName (Join-Path $previous $item.Name)
                $movedItems.Add($item.Name)
            }
        }
        $checkoutStarted = $true
        Invoke-Git $Git $Root @('checkout', '--force', '-B', $Branch, "origin/$Branch") | Out-Null
        foreach ($privateFile in $PrivateInterfaceFiles) {
            $kept = Join-Path $previous $privateFile
            if (Test-Path -LiteralPath $kept -PathType Leaf) {
                $target = Join-Path $interface $privateFile
                [IO.Directory]::CreateDirectory((Split-Path $target -Parent)) | Out-Null
                Copy-Item -LiteralPath $kept -Destination $target
                Write-SyncLog "Carried the private Interface\$privateFile over from the previous Interface folder."
            }
        }
        Write-SyncLog "Checkout created. Previous Interface and fonts: $backup"
    } catch {
        $cause = $_.Exception
        while ($cause.InnerException) { $cause = $cause.InnerException }
        $failure = $cause.Message
        if ($cause -is [IO.IOException] -or $cause -is [UnauthorizedAccessException] -or $failure -match 'in use|being used') {
            $failure += ' Close File Explorer windows, editors and other programs using files inside Interface, then retry.'
        }
        if ($checkoutStarted -and (Test-Path -LiteralPath $interface)) {
            $leftovers = Join-Path $backup 'failed-Interface'
            [IO.Directory]::CreateDirectory($leftovers) | Out-Null
            foreach ($item in @(Get-ChildItem -LiteralPath $interface -Force)) {
                Move-PathAtomic $item.FullName (Join-Path $leftovers $item.Name)
            }
        }
        foreach ($name in $movedItems) {
            Move-PathAtomic (Join-Path $previous $name) (Join-Path $interface $name)
        }
        foreach ($font in $savedFonts) {
            Copy-Item -LiteralPath (Join-Path $backup $font) -Destination (Join-Path $Root $font) -Force
        }
        $dotGit = Join-Path $Root '.git'
        if (Test-Path -LiteralPath $dotGit) { Remove-Item -LiteralPath $dotGit -Recurse -Force -Confirm:$false }
        throw "Install failed and was rolled back: $failure"
    }
}

function Get-TaskName([string]$Root) { return 'WoWSync-' + (Get-InstallationId $Root) }

function Register-SyncTask([string]$Root) {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $shell = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $launcher = Join-Path $Root 'Interface\sync_from_github.vbs'
    $action = New-ScheduledTaskAction -Execute $shell -Argument ('//B //NoLogo "{0}"' -f $launcher) -WorkingDirectory (Join-Path $Root 'Interface')
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    # Let the network come up after sign-in; fetch retries cover the rest.
    $trigger.Delay = 'PT30S'
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    # No time limit: a sync started while WoW is open waits for it to close.
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName (Get-TaskName $Root) -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Update WoW Forever addons from GitHub main and fit settings to this display.' -Force | Out-Null
}

function Assert-Writable([string]$Root) {
    $probe = Join-Path $Root ('.sync-write-test-' + [guid]::NewGuid().ToString('N'))
    try { [IO.File]::WriteAllText($probe, ''); Remove-Item -LiteralPath $probe -Force }
    catch { throw "Your account cannot write to $Root. Grant it Modify permission on that folder, then retry." }
}

function Find-Tool([string]$Name, [string]$Hint) {
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    if ($Hint) { throw $Hint }
    return $null
}

<#
.SYNOPSIS
Refuses an existing checkout with uncommitted or unpushed work: Sync force-resets to origin, so it belongs only on
machines that consume the repository, never on the one where addons are updated and committed.
#>
function Assert-ConsumerCheckout([string]$Git, [string]$Root) {
    $exportTask = 'WoWSettings-' + (Get-InstallationId $Root)
    if (Get-ScheduledTask -TaskName $exportTask -ErrorAction SilentlyContinue) {
        throw "The settings export watcher ($exportTask) is installed here, so this is the authoring machine. Sync would overwrite its exports; install it only on machines that just consume the repository."
    }
    Invoke-Git $Git $Root @('fetch', '--no-tags', 'origin', "+refs/heads/${Branch}:refs/remotes/origin/$Branch") | Out-Null
    $dirty = (Invoke-Git $Git $Root @('status', '--porcelain', '--untracked-files=no')).Output
    $ahead = (Invoke-Git $Git $Root @('rev-list', '--count', "refs/remotes/origin/$Branch..HEAD")).Output
    if ($dirty -or [int]$ahead -gt 0) {
        throw 'This checkout has uncommitted or unpushed changes, so it looks like the authoring machine. Sync would reset it to origin; install it only on machines that just consume the repository.'
    }
}

function Install-Sync([string]$Root) {
    Assert-Writable $Root
    $git = Find-Tool 'git' 'Git is required: winget install --id Git.Git -e'
    $probe = { Test-InstallationRunning $Root }
    $script:LogPath = $null
    if (-not (Test-Path -LiteralPath (Join-Path $Root '.git'))) { Initialize-Checkout $git $Root $Repository $probe }
    else {
        Grant-SafeDirectory $git $Root
        Assert-ConsumerCheckout $git $Root
    }

    $inRepo = Join-Path $Root 'Interface\sync_from_github.ps1'
    if ([IO.Path]::GetFullPath($PSCommandPath) -ine $inRepo) {
        # A standalone download only bootstraps; the checked-out copy finishes the install.
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $inRepo, '-Mode', 'Install', '-GameRoot', $Root, '-Branch', $Branch)
        if ($Resolution) { $arguments += @('-Resolution', $Resolution) }
        if ($EnvSource) { $arguments += @('-EnvSource', $EnvSource) }
        if ($EnvSourceKey) { $arguments += @('-EnvSourceKey', $EnvSourceKey) }
        & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') @arguments
        if ($LASTEXITCODE -ne 0) { throw 'The checked-out sync script failed to finish the install.' }
        return
    }

    $stateDirectory = Get-StateDirectory $Root
    [IO.Directory]::CreateDirectory($stateDirectory) | Out-Null
    $script:LogPath = Join-Path $stateDirectory 'sync.log'
    $uv = Find-Tool 'uv' $null
    if (-not $uv) { Write-Warning 'uv was not found; settings restore stays off until you install it (winget install --id astral-sh.uv -e) and run Install again.' }
    else {
        try { Initialize-UvPython $uv } catch { Write-Warning $_.Exception.Message }
    }
    $state = Read-SyncState $stateDirectory
    $override = if ($Resolution) { $Resolution } else { Get-StateValue $state 'resolution' }
    $source = if ($EnvSource -eq 'off') { $null } elseif ($EnvSource) { $EnvSource } else { Get-StateValue $state 'envSource' }
    $sourceKey = if (-not $source) { $null }
    elseif ($EnvSourceKey) { (Resolve-Path -LiteralPath $EnvSourceKey).Path }
    else { Get-StateValue $state 'envSourceKey' }
    Save-SyncState $stateDirectory (Update-SyncState $state @{
        git = $git; uv = $uv; resolution = $override; envSource = $source; envSourceKey = $sourceKey
    })
    Register-SyncTask $Root
    Write-SyncLog "Sign-in task $(Get-TaskName $Root) registered."
    $summary = Invoke-WowSync -Root $Root -StateDirectory $stateDirectory -Git $git -Uv $uv -ResolutionOverride $override `
        -EnvSource $source -EnvSourceKey $sourceKey
    if ($summary.Problems.Count -gt 0) { Write-Warning ('Needs attention: ' + ($summary.Problems -join ' | ')) }
}

function Invoke-ScheduledSync([string]$Root) {
    $stateDirectory = Get-StateDirectory $Root
    [IO.Directory]::CreateDirectory($stateDirectory) | Out-Null
    $script:LogPath = Join-Path $stateDirectory 'sync.log'
    $mutex = New-Object Threading.Mutex($false, ('Local\WoWSync-' + (Get-InstallationId $Root)))
    $owned = $false
    try {
        try { $owned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
        if (-not $owned) { Write-SyncLog 'Another sync is already running.'; return }
        $state = Read-SyncState $stateDirectory
        $git = Get-StateValue $state 'git'
        if (-not $git) { Write-SyncLog 'Sync is not installed for this game root; run -Mode Install first.'; return }
        if (-not (Test-Path -LiteralPath $git)) { $git = Find-Tool 'git' 'Git is not installed.' }
        $uv = Get-StateValue $state 'uv'
        if ($uv -and -not (Test-Path -LiteralPath $uv)) { $uv = Find-Tool 'uv' $null }
        Invoke-WowSync -Root $Root -StateDirectory $stateDirectory -Git $git -Uv $uv -ResolutionOverride (Get-StateValue $state 'resolution') `
            -EnvSource (Get-StateValue $state 'envSource') -EnvSourceKey (Get-StateValue $state 'envSourceKey') | Out-Null
    } catch {
        Write-SyncLog ('Sync failed: ' + $_.Exception.Message)
        throw
    } finally {
        if ($owned) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }

$root = Resolve-GameRoot $GameRoot
switch ($Mode) {
    'Install' { Install-Sync $root }
    'Sync' { Invoke-ScheduledSync $root }
    'Uninstall' {
        Unregister-ScheduledTask -TaskName (Get-TaskName $root) -Confirm:$false -ErrorAction SilentlyContinue
        Write-Output 'Sign-in sync task removed. The checkout, settings and private state are unchanged.'
    }
    'Status' {
        $stateDirectory = Get-StateDirectory $root
        $task = Get-ScheduledTask -TaskName (Get-TaskName $root) -ErrorAction SilentlyContinue
        Write-Output ('Task: ' + $(if ($task) { "$($task.TaskName) ($($task.State))" } else { 'not installed' }))
        Write-Output "State: $stateDirectory"
        (Read-SyncState $stateDirectory).GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Output ('  {0} = {1}' -f $_.Name, $_.Value) }
        $log = Join-Path $stateDirectory 'sync.log'
        if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 20 }
    }
}
