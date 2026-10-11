local YUI = _G.YUI
local S = YUI and YUI.Settings
if not S then return end

local CelestialSeries = S.CelestialSeries or {}
S.CelestialSeries = CelestialSeries
CelestialSeries.NAV_ICON_SIZE = 26

local DEFINITIONS = {
    toolbox = {
        brand = "Nova",
        productRoot = "Toolbox",
        gradientStart = { 0.082, 0.522, 0.875 },
        gradientEnd = { 0.263, 0.722, 0.925 },
    },
    ybar = {
        brand = "Orbit",
        productRoot = "YBar",
        gradientStart = { 0.667, 0.275, 0.918 },
        gradientEnd = { 0.773, 0.439, 0.945 },
    },
    yactionbar = {
        brand = "Flare",
        productRoot = "YActionBar",
        gradientStart = { 0.894, 0.176, 0.318 },
        gradientEnd = { 0.941, 0.294, 0.392 },
    },
    yhud = {
        brand = "Halo",
        productRoot = "YHUD",
        gradientStart = { 0.949, 0.545, 0.090 },
        gradientEnd = { 0.973, 0.678, 0.259 },
    },
}

local ICON_SOURCE_SIZES = {
    [16] = 32,
    [32] = 32,
    [64] = 32,
    [128] = 128,
    [256] = 32,
}

function CelestialSeries:GetTitle(productId, localizedSuffix)
    local definition = DEFINITIONS[productId]
    if not definition then return nil end

    local brand = definition.brand
    local helper = YUI and YUI.F
    if helper and type(helper.GetGradientText) == "function" then
        brand = helper:GetGradientText(
            brand,
            definition.gradientStart,
            definition.gradientEnd
        )
    end

    localizedSuffix = tostring(localizedSuffix or "")
    if localizedSuffix == "" then
        return brand
    end
    return brand .. " |cffffffff" .. localizedSuffix .. "|r"
end
function CelestialSeries:GetIcon(productId, size)
    local definition = DEFINITIONS[productId]
    local sourceSize = ICON_SOURCE_SIZES[tonumber(size)]
    if not definition or not sourceSize then return nil end

    local relativePath = "icons\\logo_" .. tostring(sourceSize) .. ".png"
    local assets = YUI and YUI.Assets
    local registeredRoot = assets and assets.productRoots
        and assets.productRoots[productId]
    if registeredRoot and assets.Product then
        return assets:Product(productId, relativePath)
    end

    local addonRoot = assets and assets.GetAddonRoot
        and assets:GetAddonRoot()
        or ("Interface\\AddOns\\" .. ((YUI and YUI.AddonName) or "YUI"))
    return addonRoot .. "\\Products\\" .. definition.productRoot
        .. "\\Media\\" .. relativePath
end
