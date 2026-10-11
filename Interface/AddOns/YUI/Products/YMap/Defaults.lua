local YUI = _G.YUI
if not YUI then return end

local YMap = YUI.YMap or {}
YUI.YMap = YMap

YMap.PRODUCT_ID = "ymap"
YMap.STORAGE_KEY = "YMap"
YMap.SETTINGS_ENTRY = "ymap.settings"
YMap.LAYOUT_ID = "yui.product.ymap.minimap"
YMap.BELOW_WIDGET_LAYOUT_ID = "yui.product.ymap.belowWidget"
YMap.VERSION = "1.0.0"

YMap.Defaults = {
    enabled = false,
    version = 1,
    markers = { enabled = true },
    worldEvents = { enabled = true, summaryRows = 2, summaryPerRow = 4, showRewarded = true,
        showSeasonCurrencies = true, defaultCollapsed = false, summarySeriesEnabled = {}, discoveredSeries = {} },
    worldMap = {
        enabled = true,
        scale = 1,
        rememberPosition = true,
        fadeWhenMoving = false,
        movingAlpha = 0.8,
        reveal = { enabled = true, tint = true, color = { 0.65, 0.75, 1, 0.65 } },
        directionLine = {
            enabled = false, style = "solid", thickness = 2,
            color = { 17/255, 197/255, 245/255, 0.38 }, dotSize = 3, dotSpacing = 8,
        },
        position = nil,
        coordinates = {
            player = true,
            cursor = true,
        },
    },
    minimap = {
        enabled = true,
        style = "square",
        size = 175,
        scale = 1,
        hideZoomButtons = true,
        zoneTextAlignment = "center",
        nativeAppearance = {
            hideClock = true,
            hideCalendar = false,
            zoneNameFontSize = 14,
        },
        squareAppearance = {
            borderWidth = 1,
            borderColor = { 0.22, 0.26, 0.32, 1 },
            zoneNameMode = "hover",
            zoneNameFontSize = 11,
            clockMode = "never",
            clockPosition = "TOPRIGHT",
            clock = { font = "inherit", fontSize = 0, outline = "inherit", shadow = "inherit",
                customColor = false, color = {1,1,1,1}, layoutMode = "auto", offsetX = 0, offsetY = 0,
                autoOffsetX = 0, autoOffsetY = 0 },
            zoneName = { font = "inherit", outline = "inherit", shadow = "inherit",
                customColor = false, color = {1,1,1,1}, layoutMode = "auto", position = "TOP", offsetX = 0, offsetY = 0,
                autoOffsetX = 0, autoOffsetY = 0 },
            metrics = {
                enabled = false, showFPS = true, showLatency = true,
                displayMode = "always", position = "BOTTOM", fontSize = 11,
                font = "inherit", outline = "inherit", shadow = "inherit", customColor = false,
                color = {1,1,1,1}, fpsColor = {1,1,1,1}, latencyColor = {1,1,1,1}, spacing = 12,
                displayStyle = "STANDARD", fpsBadBelow = 25, fpsSmoothFrom = 40,
                latencySmoothBelow = 200, latencyBadFrom = 500,
                colorSmooth = {1,1,1,1}, colorLag = {.91,.85,.06,1}, colorBad = {.85,.04,.04,1},
                layoutMode = "auto", offsetX = 0, offsetY = 0, autoOffsetX = 0, autoOffsetY = 0,
            },
            coordinates = {
                enabled = false,
                displayMode = "always",
                position = "BOTTOM",
                fontSize = 11,
                font = "inherit", outline = "inherit", shadow = "inherit", customColor = false,
                color = {1,1,1,1}, layoutMode = "auto", offsetX = 0, offsetY = 0, autoOffsetX = 0, autoOffsetY = 0,
            },
        },
        queue = {
            customLayout = true,
            size = 18,
            anchor = "BOTTOMLEFT",
            offsetX = -5,
            offsetY = -5,
        },
        squareElements = {
            expansion = {
                hidden = false,
                anchor = "BOTTOMLEFT",
                offsetX = 20,
                offsetY = 3,
                scale = 0.65,
            },
            tracking = {
                hidden = true,
                anchor = "BOTTOMLEFT",
                offsetX = 3,
                offsetY = 3,
                scale = 1,
                rightClickOpen = true,
                rightClickHint = false,
            },
            calendar = {
                hidden = false,
                anchor = "TOPRIGHT",
                offsetX = -2,
                offsetY = -2,
                scale = 1,
            },
            mail = {
                hidden = false,
                anchor = "TOPRIGHT",
                offsetX = -28,
                offsetY = -3,
                scale = 1,
            },
            crafting = {
                hidden = false,
                anchor = "TOPRIGHT",
                offsetX = -50,
                offsetY = -3,
                scale = 1,
            },
            difficulty = {
                hidden = false,
                anchor = "TOPLEFT",
                offsetX = -3,
                offsetY = 1,
                scale = 1,
                textStyle = "zh",
            },
        },
        belowWidget = {
            width = 200,
        },
        statusBars = {
            experienceEnabled = false,
            reputationEnabled = false,
            position = "bottom",
            thickness = 12,
            texture = "yui-g1",
            experienceColor = { 0.58, 0, 0.55, 1 },
            borderWidth = 1,
            borderColor = { 0, 0, 0, 1 },
            backgroundColor = { 0, 0, 0, 1 },
            mapGap = 2,
            barGap = 1,
            textDisplay = "hover",
        },
    },
    buttonDrawer = {
        enabled = true,
        iconSize = 28,
        spacingX = 4,
        spacingY = 4,
        expandMode = "hoverIcon",
        layoutDirection = "rightDown",
        itemsPerLine = 8,
        panelBackground = "transparent",
        panelPadding = 4,
        triggerSize = 20,
        triggerVisibility = "always",
        triggerPosition = "bottomRight",
        triggerOffsetX = 2,
        triggerOffsetY = 2,
    },
    migrations = {
        legacyMapComponents = 0,
        belowWidgetPlacement = 0,
        buttonDrawerAnchor = 0,
        squareElementOffsets = 1,
        queueOffsets = 1,
        squareAppearanceDisplay = 0,
    },
}

if YUI.IsForever then
    YMap.Defaults.minimap.squareElements.diel = {
        hidden = false, anchor = "BOTTOMRIGHT", offsetX = -2, offsetY = -2, scale = 0.75,
    }
end

local function CopyValue(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, child in pairs(value) do
        copy[CopyValue(key)] = CopyValue(child)
    end
    return copy
end

local function FillDefaults(target, defaults)
    if type(target) ~= "table" or type(defaults) ~= "table" then
        return target
    end
    for key, defaultValue in pairs(defaults) do
        local value = target[key]
        if value == nil then
            target[key] = CopyValue(defaultValue)
        elseif type(value) == "table" and type(defaultValue) == "table" then
            FillDefaults(value, defaultValue)
        end
    end
    return target
end

function YMap:CopyValue(value)
    return CopyValue(value)
end

function YMap:MergeDefaults(db)
    -- Missing markers on saved layouts still identify legacy screen offsets.
    -- New layouts already use the outward offsets shown by the settings UI.
    if type(db) == "table" and type(db.minimap) == "table" then
        db.migrations = type(db.migrations) == "table" and db.migrations or {}
        if type(db.minimap.squareElements) == "table" and db.migrations.squareElementOffsets == nil then
            db.migrations.squareElementOffsets = 0
        end
        if type(db.minimap.queue) == "table" and db.migrations.queueOffsets == nil then
            db.migrations.queueOffsets = 0
        end
    end
    return FillDefaults(db, self.Defaults)
end
