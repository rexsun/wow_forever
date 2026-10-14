[CmdletBinding()]
param(
    [ValidateSet('Watch', 'Export', 'Review', 'Restore', 'Install', 'Uninstall')]
    [string]$Mode = 'Watch',
    [ValidateRange(1, 60)]
    [int]$PollSeconds = 2,
    [ValidateRange(2, 120)]
    [int]$StableSeconds = 6,
    [string]$UvPath,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:GameRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent)).TrimEnd('\')
$script:Helper = Join-Path $PSScriptRoot 'tools\wtf_settings.py'

function Get-InstallationId([string]$Root) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Root.ToLowerInvariant())
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').Substring(0, 16).ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Initialize-SettingsEnvironment {
    param([string]$Path = (Join-Path $PSScriptRoot '.env'))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    $found = $false
    foreach ($line in Get-Content -LiteralPath $path -Encoding UTF8) {
        if ($line -match '^\s*(?:export\s+)?WTF_SETTINGS_STATE_DIR\s*=\s*(.*)$') {
            if ($found) { throw 'Duplicate WTF_SETTINGS_STATE_DIR in .env.' }
            $found = $true
            $value = $Matches[1].Trim()
            if ($value.StartsWith('"')) {
                $value = ConvertFrom-Json -InputObject $value
            } elseif ($value.StartsWith("'")) {
                if (-not $value.EndsWith("'") -or $value.Length -lt 2) { throw 'Invalid quoted .env value.' }
                $value = $value.Substring(1, $value.Length - 2)
            } else {
                $value = ($value -split ' #', 2)[0].TrimEnd()
            }
            $env:WTF_SETTINGS_STATE_DIR = [Environment]::ExpandEnvironmentVariables($value)
        }
    }
}

function Get-PrivateStateDirectory {
    if ($env:WTF_SETTINGS_STATE_DIR) {
        if (-not [IO.Path]::IsPathRooted($env:WTF_SETTINGS_STATE_DIR)) { throw 'WTF_SETTINGS_STATE_DIR must be an absolute private path.' }
        return [IO.Path]::GetFullPath($env:WTF_SETTINGS_STATE_DIR)
    }
    return Join-Path $env:LOCALAPPDATA ('WowSettings\' + (Get-InstallationId $script:GameRoot))
}

function Test-InstallationRunning([string]$Root) {
    foreach ($process in @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Wow%.exe'")) {
        if (-not $process.ExecutablePath) {
            throw 'A WoW process path is unavailable; closure cannot be confirmed.'
        }
        if ((Split-Path $process.ExecutablePath -Parent) -ieq $Root) { return $true }
    }
    return $false
}

function Get-WtfSignature([string]$Root) {
    $path = Join-Path $Root 'WTF'
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw 'WTF directory is missing.' }
    $lines = foreach ($file in @(Get-ChildItem -LiteralPath $path -File -Recurse | Sort-Object FullName)) {
        '{0}|{1}|{2}' -f $file.FullName, $file.Length, $file.LastWriteTimeUtc.Ticks
    }
    return ($lines -join "`n")
}

function Wait-WtfStable {
    param(
        [string]$Root,
        [int]$Seconds,
        [scriptblock]$ProcessProbe,
        [scriptblock]$SleepAction = { param($Milliseconds) Start-Sleep -Milliseconds $Milliseconds },
        [int]$Attempts = 180
    )
    $previous = Get-WtfSignature $Root
    $quiet = 0
    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        & $SleepAction 1000
        if (& $ProcessProbe) { return $false }
        $current = Get-WtfSignature $Root
        if ($current -ceq $previous) { $quiet++ } else { $quiet = 0 }
        if ($quiet -ge $Seconds) { return $true }
        $previous = $current
    }
    throw 'WTF did not settle before the export timeout.'
}

function Invoke-SettingsHelper([string]$Action, [switch]$ValidateOnly) {
    $uv = if ($UvPath) { $UvPath } else { (Get-Command uv -ErrorAction Stop).Source }
    $arguments = @('run', '--no-project', 'python', $script:Helper, $Action, '--game-root', $script:GameRoot, '--state', (Get-PrivateStateDirectory))
    if ($ValidateOnly) { $arguments += '--dry-run' }
    & $uv @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Settings helper failed; inspect local settings and retry.' }
}

function Write-WatcherLog([string]$Message) {
    $directory = Get-PrivateStateDirectory
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $log = Join-Path $directory 'watcher.log'
    if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 1MB) {
        Move-Item -LiteralPath $log -Destination ($log + '.old') -Force
    }
    Add-Content -LiteralPath $log -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
}

function Watch-Installation {
    param(
        [scriptblock]$ProcessProbe,
        [scriptblock]$ExportAction,
        [scriptblock]$SleepAction = { param($Milliseconds) Start-Sleep -Milliseconds $Milliseconds },
        [int]$Interval = 2,
        [int]$IterationLimit = 0,
        [switch]$SkipInitialExport
    )
    $pending = -not $SkipInitialExport
    $iteration = 0
    while ($IterationLimit -eq 0 -or $iteration -lt $IterationLimit) {
        try {
            if (& $ProcessProbe) {
                $pending = $true
            } elseif ($pending) {
                if (& $ExportAction) { $pending = $false }
            }
        } catch {
            Write-WatcherLog 'Export deferred: game state or settings validation failed. Retrying in 30 seconds.'
            & $SleepAction 30000
        }
        $iteration++
        & $SleepAction ($Interval * 1000)
    }
}

function Invoke-SettingsRestore {
    $id = Get-InstallationId $script:GameRoot
    $taskName = 'WoWSettings-' + $id
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    $resumeTask = $task -and $task.State -eq 'Running'
    $mutex = New-Object Threading.Mutex($false, ('Local\WoWSettings-' + $id))
    $owned = $false
    try {
        if ($resumeTask) { Stop-ScheduledTask -TaskName $taskName }
        try { $owned = $mutex.WaitOne(5000) } catch [Threading.AbandonedMutexException] { $owned = $true }
        if (-not $owned) { throw 'Stop the foreground settings watcher before restoring. No live settings were changed.' }
        if (Test-InstallationRunning $script:GameRoot) { throw 'Close this installation before restoring settings.' }
        if (-not (Wait-WtfStable -Root $script:GameRoot -Seconds $StableSeconds -ProcessProbe { Test-InstallationRunning $script:GameRoot })) {
            throw 'WoW restarted; restore cancelled.'
        }
        Invoke-SettingsHelper 'restore' -ValidateOnly:$DryRun
    } finally {
        if ($owned) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
        if ($resumeTask) {
            $directory = Get-PrivateStateDirectory
            [IO.Directory]::CreateDirectory($directory) | Out-Null
            [IO.File]::WriteAllText((Join-Path $directory 'skip-initial-export'), 'restore')
            Start-ScheduledTask -TaskName $taskName
        }
    }
}

function Install-WatcherTask {
    $uv = (Get-Command uv -ErrorAction Stop).Source
    $id = Get-InstallationId $script:GameRoot
    $taskName = 'WoWSettings-' + $id
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $shell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $scriptPath = Join-Path $PSScriptRoot 'watch_wtf_settings.ps1'
    $action = New-ScheduledTaskAction -Execute $shell -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Mode Watch -UvPath "{1}"' -f $scriptPath, $uv) -WorkingDirectory $PSScriptRoot
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Export anonymous WoW settings after exit; leave Git staging and commits manual.' -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Write-Output 'Installed and started the current-user settings watcher. No automatic Git writes.'
}

Initialize-SettingsEnvironment
if ($MyInvocation.InvocationName -eq '.') { return }

$probe = { Test-InstallationRunning $script:GameRoot }
switch ($Mode) {
    'Install' { Install-WatcherTask }
    'Uninstall' {
        $taskName = 'WoWSettings-' + (Get-InstallationId $script:GameRoot)
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Output 'Watcher removed; exported settings and the private alias map are retained.'
    }
    'Review' { Invoke-SettingsHelper 'review' }
    'Restore' { Invoke-SettingsRestore }
    'Export' {
        if (& $probe) { throw 'Close this installation before exporting settings.' }
        if (Wait-WtfStable -Root $script:GameRoot -Seconds $StableSeconds -ProcessProbe $probe) {
            Invoke-SettingsHelper 'export' -ValidateOnly:$DryRun
        } else { throw 'WoW restarted; export deferred.' }
    }
    'Watch' {
        $mutex = New-Object Threading.Mutex($false, ('Local\WoWSettings-' + (Get-InstallationId $script:GameRoot)))
        $owned = $false
        try {
            try { $owned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
            if (-not $owned) { throw 'A watcher for this installation is already running.' }
            Write-WatcherLog 'Watcher started.'
            $skipPath = Join-Path (Get-PrivateStateDirectory) 'skip-initial-export'
            $skipInitial = Test-Path -LiteralPath $skipPath
            if ($skipInitial) { Remove-Item -LiteralPath $skipPath }
            Watch-Installation -ProcessProbe $probe -Interval $PollSeconds -SkipInitialExport:$skipInitial -ExportAction {
                if (-not (Wait-WtfStable -Root $script:GameRoot -Seconds $StableSeconds -ProcessProbe $probe)) { return $false }
                Invoke-SettingsHelper 'export' -ValidateOnly:$DryRun | Out-Host
                Write-WatcherLog 'Anonymous settings exported. Git index and history untouched.'
                return $true
            }
        } finally {
            if ($owned) { $mutex.ReleaseMutex() }
            $mutex.Dispose()
        }
    }
}
