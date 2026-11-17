[CmdletBinding()]
param(
    [ValidateSet('Install', 'Uninstall', 'Status')]
    [string]$Mode = 'Status'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$TaskName = 'WoWSplashAlert'
$LogFile = Join-Path $env:LOCALAPPDATA 'SplashAlert\splash-alert.log'

function Get-SplashAlertProcess {
    # Matched by the auto-start log path, so a calibrate or manual run in a console is left alone.
    Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='uv.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine -like '*splash_alert.py*' -and $_.CommandLine -like "*$LogFile*" }
}

function Stop-SplashAlert {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    # Ending the task stops only its wscript launcher; uv and Python outlive it.
    Get-SplashAlertProcess | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Install-SplashAlert {
    $uv = (Get-Command uv -ErrorAction Stop).Source
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $shell = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $launcher = Join-Path $PSScriptRoot 'splash_alert.vbs'
    $action = New-ScheduledTaskAction -Execute $shell -Argument ('//B //NoLogo "{0}" "{1}" "{2}"' -f $launcher, $uv, $LogFile) -WorkingDirectory $PSScriptRoot
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Splash Alert: flash the screen when the WoW fishing bobber splashes. Listens only; sends no input.' -Force | Out-Null
    Stop-SplashAlert
    Start-ScheduledTask -TaskName $TaskName
    Write-Output "Installed and started. It starts at each sign-in; log: $LogFile"
}

switch ($Mode) {
    'Install' { Install-SplashAlert }
    'Uninstall' {
        Stop-SplashAlert
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Output 'Auto-start removed and Splash Alert stopped. The calibration is kept.'
    }
    'Status' {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        $state = if ($task) { [string]$task.State } else { 'not installed' }
        $running = @(Get-SplashAlertProcess | Where-Object Name -eq 'python.exe').Count -gt 0
        $calibrated = Test-Path -LiteralPath (Join-Path $PSScriptRoot 'calibration.local.json')
        Write-Output "Task: $state; running: $running; calibrated: $calibrated"
        if (-not $calibrated) { Write-Output 'No bite can be detected until you run: uv run splash_alert.py calibrate' }
        if (Test-Path -LiteralPath $LogFile) { Get-Content -LiteralPath $LogFile -Tail 10 }
    }
}
