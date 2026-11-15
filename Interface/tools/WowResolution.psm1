Set-StrictMode -Version Latest

# AGENTS.md: every setting in this pack is maintained for exactly these three displays.
$script:SupportedResolutions = @(
    @{ Name = '1920x1080'; Width = 1920; Height = 1080 },
    @{ Name = '2560x1440'; Width = 2560; Height = 1440 },
    @{ Name = '3840x2160'; Width = 3840; Height = 2160 }
)

function Get-SupportedResolutions { return @($script:SupportedResolutions | ForEach-Object { $_.Name }) }

function ConvertFrom-ResolutionText([string]$Text) {
    if ($Text -notmatch '^\s*(\d{3,5})\s*x\s*(\d{3,5})\s*$') { return $null }
    return @{ Width = [int]$Matches[1]; Height = [int]$Matches[2] }
}

<#
.SYNOPSIS
Returns the largest supported resolution that fits inside Width x Height, or 1920x1080 for smaller displays.
.DESCRIPTION
Fitting rather than nearest keeps the restored window inside the screen: 3440x1440 maps to 2560x1440,
1920x1200 to 1920x1080 and 2560x1600 to 2560x1440.
#>
function ConvertTo-SupportedResolution([int]$Width, [int]$Height) {
    if ($Width -le 0 -or $Height -le 0) { throw "Invalid display size ${Width}x${Height}." }
    $fit = @($script:SupportedResolutions | Where-Object { $_.Width -le $Width -and $_.Height -le $Height })
    if ($fit.Count -eq 0) { return $script:SupportedResolutions[0].Name }
    return $fit[-1].Name
}

<#
.SYNOPSIS
Reads the window resolution the game saved in Config.wtf; $null when absent, "auto" or malformed.
#>
function Get-ConfigResolution([string]$ConfigPath) {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return $null }
    $config = [IO.File]::ReadAllText($ConfigPath)
    foreach ($cvar in @('gxWindowedResolution', 'gxFullscreenResolution')) {
        $match = [regex]::Match($config, '(?im)^SET\s+' + $cvar + '\s+"([^"]*)"')
        if ($match.Success) {
            $size = ConvertFrom-ResolutionText $match.Groups[1].Value
            if ($size) { return ('{0}x{1}' -f $size.Width, $size.Height) }
        }
    }
    return $null
}

<#
.SYNOPSIS
Returns the primary display's current mode in physical pixels, independent of Windows display scaling.
#>
function Get-DisplayResolution {
    if (-not ('WowResolution.NativeDisplay' -as [type])) {
        Add-Type -Namespace WowResolution -Name NativeDisplay -MemberDefinition @'
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra;
    public int dmFields; public int dmPositionX; public int dmPositionY; public int dmDisplayOrientation;
    public int dmDisplayFixedOutput; public short dmColor; public short dmDuplex; public short dmYResolution;
    public short dmTTOption; public short dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight;
    public int dmDisplayFlags; public int dmDisplayFrequency; public int dmICMMethod; public int dmICMIntent;
    public int dmMediaType; public int dmDitherType; public int dmReserved1; public int dmReserved2;
    public int dmPanningWidth; public int dmPanningHeight;
}
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
'@
    }
    $mode = New-Object WowResolution.NativeDisplay+DEVMODE
    $mode.dmSize = [Runtime.InteropServices.Marshal]::SizeOf($mode)
    # -1 is ENUM_CURRENT_SETTINGS; a null device name selects the primary display.
    if ([WowResolution.NativeDisplay]::EnumDisplaySettings($null, -1, [ref]$mode) -and $mode.dmPelsWidth -gt 0) {
        return ('{0}x{1}' -f $mode.dmPelsWidth, $mode.dmPelsHeight)
    }
    $controller = @(Get-CimInstance Win32_VideoController | Where-Object { $_.CurrentHorizontalResolution -gt 0 } | Select-Object -First 1)
    if ($controller.Count -eq 1) {
        return ('{0}x{1}' -f $controller[0].CurrentHorizontalResolution, $controller[0].CurrentVerticalResolution)
    }
    throw 'The display resolution could not be detected.'
}

<#
.SYNOPSIS
Largest EllesmereUI options-panel scale (0.05 steps, 1.0-2.0 preferred) that keeps the 1500x1154 panel on screen.
#>
function Get-EuiPanelScale([string]$Resolution) {
    $size = ConvertFrom-ResolutionText $Resolution
    if (-not $size) { throw "Invalid resolution '$Resolution'." }
    $preferred = [Math]::Max(1.0, [Math]::Min($size.Height / 1440.0, 2.0))
    $fits = [Math]::Min(($size.Width - 40) / 1500, ($size.Height - 40) / 1154)
    return [Math]::Floor([Math]::Min($preferred, $fits) * 20) / 20
}

function Write-TextIfChanged([string]$Path, [string]$Original, [string]$Updated) {
    if ($Updated -ceq $Original) { return $false }
    [IO.File]::WriteAllText($Path, $Updated, [Text.UTF8Encoding]::new($false))
    return $true
}

<#
.SYNOPSIS
Sets gxWindowedResolution in WTF\Config.wtf and fits every EllesmereUI options panel under WTF to it.
.DESCRIPTION
Gameplay UI scale is deliberately left alone. Every file is validated before any is written. Files are
rewritten only when their content changes. Returns the number of files changed.
#>
function Set-WowResolution {
    param(
        [Parameter(Mandatory = $true)][string]$WtfPath,
        [Parameter(Mandatory = $true)][string]$Resolution
    )
    if ($Resolution -notin (Get-SupportedResolutions)) {
        throw "Unsupported resolution '$Resolution'; use one of $((Get-SupportedResolutions) -join ', ')."
    }
    $configPath = Join-Path $WtfPath 'Config.wtf'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw 'WTF\Config.wtf is missing.' }
    $writes = @()

    $config = [IO.File]::ReadAllText($configPath)
    $pattern = '(?im)^SET\s+gxWindowedResolution\s+"[^"]*"[^\r\n]*'
    $line = 'SET gxWindowedResolution "' + $Resolution + '"'
    $updatedConfig = if ([regex]::IsMatch($config, $pattern)) {
        [regex]::Replace($config, $pattern, $line)
    } else { $config.TrimEnd() + "`r`n" + $line + "`r`n" }
    $writes += , @($configPath, $config, $updatedConfig)

    $scaleText = (Get-EuiPanelScale $Resolution).ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)
    foreach ($file in @(Get-ChildItem -LiteralPath $WtfPath -Filter 'EllesmereUI.lua' -Recurse -File)) {
        $settings = [IO.File]::ReadAllText($file.FullName)
        $panel = '(?m)^\s*\["panelScale"\]\s*=\s*[\d.]+\s*,[^\r\n]*'
        $panelMatches = [regex]::Matches($settings, $panel)
        if ($panelMatches.Count -gt 1) { throw "Ambiguous EUI panel scale: $($file.FullName)" }
        $updated = if ($panelMatches.Count -eq 1) {
            [regex]::Replace($settings, $panel, ('["panelScale"] = ' + $scaleText + ','))
        } elseif ([regex]::IsMatch($settings, '(?m)^\s*EllesmereUIDB\s*=\s*\{')) {
            [regex]::Replace($settings, '(?m)^(\s*EllesmereUIDB\s*=\s*\{)', ('$1' + "`r`n" + '["panelScale"] = ' + $scaleText + ','))
        } else { throw "Unrecognized EUI saved variables: $($file.FullName)" }
        $writes += , @($file.FullName, $settings, $updated)
    }

    $changed = 0
    foreach ($write in $writes) {
        if (Write-TextIfChanged $write[0] $write[1] $write[2]) { $changed++ }
    }
    return $changed
}

Export-ModuleMember -Function Get-SupportedResolutions, ConvertTo-SupportedResolution, Get-ConfigResolution,
    Get-DisplayResolution, Get-EuiPanelScale, Set-WowResolution
