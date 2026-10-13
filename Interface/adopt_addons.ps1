<#
.SYNOPSIS
Adopts Interface and WTF from another WoW installation, retaining a local backup.
.DESCRIPTION
Close WoW on both machines first. Run this copy of the script on the destination.
The source must be the game root containing Interface and WTF. If present, Fonts
is merged over destination Fonts; destination-only font files are preserved.
Gameplay settings and UI scale are copied unchanged. Use -Resolution to set the
destination window size and fit the EUI options panel. Requires Windows PowerShell 5.1.
.EXAMPLE
.\Interface\adopt_addons.ps1 \\machine-source\WoW\_classic_beta_
If the share itself points at _classic_beta_, use \\machine-source\WoW instead.
.EXAMPLE
.\Interface\adopt_addons.ps1 \\source\WoW\_classic_beta_ -Resolution 1920x1080
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Source,
    [ValidateSet('1920x1080', '2560x1440', '3840x2160')]
    [string]$Resolution
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-WowClosed {
    $running = @(Get-Process -Name 'Wow*' -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        throw 'Close WoW on this destination machine, then run the script again. No processes will be forcibly stopped.'
    }
}

function Assert-NoLinks([string]$Path) {
    $items = @((Get-Item -LiteralPath $Path -Force)) + @(Get-ChildItem -LiteralPath $Path -Force -Recurse)
    foreach ($item in $items) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Linked files or directories are not supported: $($item.FullName)"
        }
    }
}

function Set-StagedResolution([string]$WtfPath) {
    if (-not $Resolution) { return }
    $configPath = Join-Path $WtfPath 'Config.wtf'
    $config = [IO.File]::ReadAllText($configPath)
    $pattern = '(?im)^SET\s+gxWindowedResolution\s+"[^"]*"[^\r\n]*'
    $line = 'SET gxWindowedResolution "' + $Resolution + '"'
    if ([regex]::IsMatch($config, $pattern)) {
        $config = [regex]::Replace($config, $pattern, $line)
    } else { $config = $config.TrimEnd() + "`r`n" + $line + "`r`n" }
    [IO.File]::WriteAllText($configPath, $config, [Text.UTF8Encoding]::new($false))

    $dimensions = $Resolution.Split('x')
    $width, $height = [int]$dimensions[0], [int]$dimensions[1]
    $preferred = [Math]::Max(1.0, [Math]::Min($height / 1440.0, 2.0))
    $fits = [Math]::Min(($width - 40) / 1500, ($height - 40) / 1154)
    $scale = [Math]::Floor([Math]::Min($preferred, $fits) * 20) / 20
    $scaleText = $scale.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)
    foreach ($file in @(Get-ChildItem -LiteralPath $WtfPath -Filter 'EllesmereUI.lua' -Recurse -File)) {
        $settings = [IO.File]::ReadAllText($file.FullName)
        $panel = '(?m)^\s*\["panelScale"\]\s*=\s*[\d.]+\s*,[^\r\n]*'
        $panelMatches = [regex]::Matches($settings, $panel)
        if ($panelMatches.Count -gt 1) { throw "Ambiguous EUI panel scale: $($file.FullName)" }
        if ($panelMatches.Count -eq 1) {
            $settings = [regex]::Replace($settings, $panel, ('["panelScale"] = ' + $scaleText + ','))
        } elseif ([regex]::IsMatch($settings, '(?m)^\s*EllesmereUIDB\s*=\s*\{')) {
            $settings = [regex]::Replace($settings, '(?m)^(\s*EllesmereUIDB\s*=\s*\{)', ('$1' + "`r`n" + '["panelScale"] = ' + $scaleText + ','))
        } else { throw "Unrecognized EUI saved variables: $($file.FullName)" }
        [IO.File]::WriteAllText($file.FullName, $settings, [Text.UTF8Encoding]::new($false))
    }
    Write-Host "Destination window: $Resolution; EUI options scale: $scaleText; gameplay UI scale retained."
}

if ((Split-Path $PSScriptRoot -Leaf) -ine 'Interface') {
    throw 'Place this script inside the destination game installation''s Interface folder.'
}
$destinationRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent)).TrimEnd('\')
$resolved = Resolve-Path -LiteralPath $Source
if ($resolved.Provider.Name -ne 'FileSystem') { throw 'Source must be a filesystem path.' }
$sourceRoot = $resolved.ProviderPath.TrimEnd('\')
if ($sourceRoot -ieq $destinationRoot -or
    $sourceRoot.StartsWith($destinationRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
    $destinationRoot.StartsWith($sourceRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Source and destination must be separate, non-overlapping game installations.'
}
foreach ($relative in @('Interface', 'Interface\AddOns', 'WTF')) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $relative) -PathType Container)) {
        throw "Source is not a game root: missing $relative. Supply the folder containing Interface and WTF."
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'WTF\Config.wtf') -PathType Leaf)) {
    throw 'Source WTF\Config.wtf is missing; refusing to replace your settings.'
}
Assert-WowClosed
$adoptFolders = @('Interface', 'WTF')
$sourceFonts = Join-Path $sourceRoot 'Fonts'
if (Test-Path -LiteralPath $sourceFonts) {
    if (-not (Test-Path -LiteralPath $sourceFonts -PathType Container)) {
        throw 'Source Fonts must be a directory.'
    }
    $adoptFolders += 'Fonts'
}
foreach ($name in $adoptFolders) {
    Assert-NoLinks (Join-Path $sourceRoot $name)
    $destination = Join-Path $destinationRoot $name
    if (Test-Path -LiteralPath $destination) { Assert-NoLinks $destination }
}
Get-Command robocopy.exe -ErrorAction Stop | Out-Null
Write-Host "Source:      $sourceRoot"
Write-Host "Destination: $destinationRoot"
Write-Host 'Interface and WTF will be replaced after backup. Source Fonts, if present, will be merged with destination Fonts.'

$backupParent = Join-Path $destinationRoot 'addon-backups'
if (Test-Path -LiteralPath $backupParent) {
    if (-not (Test-Path -LiteralPath $backupParent -PathType Container) -or
        ((Get-Item -LiteralPath $backupParent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'addon-backups must be an ordinary directory.'
    }
}
$backupRoot = Join-Path $backupParent ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
$stageRoot = Join-Path $backupRoot 'stage'
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
$movedOriginals = @()
$installed = @()

try {
    foreach ($name in $adoptFolders) {
        Write-Host "Staging $name..."
        $destination = Join-Path $destinationRoot $name
        if ($name -eq 'Fonts' -and (Test-Path -LiteralPath $destination)) {
            & robocopy.exe $destination (Join-Path $stageRoot $name) '/E' '/COPY:DAT' '/DCOPY:DAT' '/XJ' '/R:2' '/W:1' '/NP' ('/LOG:' + (Join-Path $backupRoot 'Fonts-preserve.log')) | Out-Host
            if ($LASTEXITCODE -ge 8) {
                throw "Copy of destination Fonts failed (robocopy exit $LASTEXITCODE). See $backupRoot."
            }
        }
        $copyArgs = @((Join-Path $sourceRoot $name), (Join-Path $stageRoot $name),
            '/E', '/COPY:DAT', '/DCOPY:DAT', '/XJ', '/R:2', '/W:1', '/NP',
            ('/LOG:' + (Join-Path $backupRoot ($name + '-copy.log'))))
        & robocopy.exe @copyArgs | Out-Host
        $copyExitCode = $LASTEXITCODE
        if ($copyExitCode -ge 8) {
            throw "Copy of $name failed (robocopy exit $copyExitCode). See $backupRoot."
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $stageRoot 'WTF\Config.wtf') -PathType Leaf)) {
        throw 'The staged copy is missing WTF\Config.wtf.'
    }
    $stagedScript = Join-Path $stageRoot 'Interface\adopt_addons.ps1'
    if (-not (Test-Path -LiteralPath $stagedScript)) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $stagedScript
    }
    Set-StagedResolution (Join-Path $stageRoot 'WTF')
    Assert-WowClosed
    foreach ($name in $adoptFolders) {
        $destination = Join-Path $destinationRoot $name
        if (Test-Path -LiteralPath $destination) {
            Move-Item -LiteralPath $destination -Destination (Join-Path $backupRoot $name)
            $movedOriginals += $name
        }
    }
    foreach ($name in $adoptFolders) {
        Move-Item -LiteralPath (Join-Path $stageRoot $name) -Destination (Join-Path $destinationRoot $name)
        $installed += $name
    }
} catch {
    $failure = $_.Exception.Message
    $rollbackErrors = @()
    foreach ($name in $installed) {
        try {
            Move-Item -LiteralPath (Join-Path $destinationRoot $name) -Destination (Join-Path $backupRoot ('failed-' + $name))
        } catch { $rollbackErrors += $_.Exception.Message }
    }
    foreach ($name in $movedOriginals) {
        try {
            $restoreTarget = Join-Path $destinationRoot $name
            if (Test-Path -LiteralPath $restoreTarget) { throw "Cannot restore $name because its destination is occupied." }
            Move-Item -LiteralPath (Join-Path $backupRoot $name) -Destination $restoreTarget
        } catch { $rollbackErrors += $_.Exception.Message }
    }
    if ($rollbackErrors.Count -gt 0) {
        throw "$failure Rollback needs attention: $($rollbackErrors -join '; '). Retained files: $backupRoot."
    }
    throw "$failure Original destination folders are unchanged or restored. Retained files: $backupRoot."
}

Write-Host "Done. $($adoptFolders -join ', ') adopted. Backup and copy logs: $backupRoot"
Write-Host 'To restore, close WoW, move the adopted folders aside, then move the backed-up folders into the game root.'
