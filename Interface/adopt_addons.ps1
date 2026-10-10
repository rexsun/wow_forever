<#
.SYNOPSIS
Adopts Interface and WTF from another WoW installation, retaining a local backup.
.DESCRIPTION
Close WoW on both machines first. Run this copy of the script on the destination.
The source must be the game root containing Interface and WTF. Fonts are excluded.
Settings, including UI scale, are copied unchanged. Requires Windows PowerShell 5.1.
.EXAMPLE
.\Interface\adopt_addons.ps1 \\machine-source\WoW\_classic_beta_
If the share itself points at _classic_beta_, use \\machine-source\WoW instead.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Source
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
foreach ($name in @('Interface', 'WTF')) {
    Assert-NoLinks (Join-Path $sourceRoot $name)
    $destination = Join-Path $destinationRoot $name
    if (Test-Path -LiteralPath $destination) { Assert-NoLinks $destination }
}
Get-Command robocopy.exe -ErrorAction Stop | Out-Null
Write-Host "Source:      $sourceRoot"
Write-Host "Destination: $destinationRoot"
Write-Host 'Interface and WTF will be replaced after backup. Fonts are excluded.'

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
    foreach ($name in @('Interface', 'WTF')) {
        Write-Host "Staging $name..."
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
    Assert-WowClosed
    foreach ($name in @('Interface', 'WTF')) {
        $destination = Join-Path $destinationRoot $name
        if (Test-Path -LiteralPath $destination) {
            Move-Item -LiteralPath $destination -Destination (Join-Path $backupRoot $name)
            $movedOriginals += $name
        }
    }
    foreach ($name in @('Interface', 'WTF')) {
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

Write-Host "Done. Interface and WTF adopted. Backup and copy logs: $backupRoot"
Write-Host 'To restore, close WoW, move the adopted folders aside, then move the backed-up Interface and WTF into the game root.'
