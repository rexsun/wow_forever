local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not (YUI and (YUI.IsRetail or YUI.IsWrath or YUI.IsForever)) then return end

local CombatEnhancement = YUI.CombatEnhancement
if not (CombatEnhancement and CombatEnhancement.RegisterSubFeature) then return end

local UnitAPI = YUI.API and YUI.API.Unit
local GUI2 = YUI.GUI2
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local TargetDistance = {
    id = "targetDistance",
    order = 20,
}

local FEATURE_KEY = CombatEnhancement.FEATURE_KEY or "CombatEnhancement"
local TARGET_LAYOUT_ID = "yui.component.combat_enhancement.target_distance"
local FOCUS_LAYOUT_ID = "yui.component.combat_enhancement.focus_distance"
local TARGET_FRAME_NAME = "YUI_CombatEnhancement_TargetDistanceFrame"
local FOCUS_FRAME_NAME = "YUI_CombatEnhancement_FocusDistanceFrame"
local RUNTIME_FRAME_NAME = "YUI_CombatEnhancement_DistanceRuntimeDriver"

local DEFAULT_FONT = "default"
local DEFAULT_FONT_SIZE = 18
local MIN_FONT_SIZE = 10
local MAX_FONT_SIZE = 48
local DEFAULT_FRAME_WIDTH = 110
local DEFAULT_FRAME_HEIGHT = 32
local UPDATE_INTERVAL = 0.2
local MAX_VISIBLE_MIN_RANGE = 60
local HIDE_AT_MIN_RANGE = 70
local TEXT_STYLE_NONE = "none"
local TEXT_STYLE_SHADOW = "shadow"
local TEXT_STYLE_OUTLINE_SHADOW = "outline_shadow"
local DEFAULT_TEXT_STYLE = TEXT_STYLE_OUTLINE_SHADOW
local VALID_TEXT_STYLES = {
    [TEXT_STYLE_NONE] = true,
    [TEXT_STYLE_SHADOW] = true,
    [TEXT_STYLE_OUTLINE_SHADOW] = true,
    outline = true,
    thick = true,
    thick_shadow = true,
}

local SECTION_WIDTH = 620
local COLUMN_GAP = 24
local COLUMN_WIDTH = math.floor((SECTION_WIDTH - COLUMN_GAP) / 2)
local LABEL_WIDTH = 112
local LABEL_GAP = 10
local BODY_WIDTH = COLUMN_WIDTH - LABEL_WIDTH - LABEL_GAP
local INPUT_WIDTH = 52
local VALUE_GAP = 10

local RANGE_BUCKETS = {
    { key = "range_00_05", labelKey = "settings.target_distance_color_range_00_05", label = "0-5 码", max = 5, defaultColor = { 0.35, 1.00, 0.52, 1 } },
    { key = "range_05_10", labelKey = "settings.target_distance_color_range_05_10", label = "5-10 码", max = 10, defaultColor = { 0.49, 0.95, 0.47, 1 } },
    { key = "range_10_15", labelKey = "settings.target_distance_color_range_10_15", label = "10-15 码", max = 15, defaultColor = { 0.68, 0.91, 0.42, 1 } },
    { key = "range_15_20", labelKey = "settings.target_distance_color_range_15_20", label = "15-20 码", max = 20, defaultColor = { 0.86, 0.86, 0.36, 1 } },
    { key = "range_20_25", labelKey = "settings.target_distance_color_range_20_25", label = "20-25 码", max = 25, defaultColor = { 1.00, 0.78, 0.31, 1 } },
    { key = "range_25_30", labelKey = "settings.target_distance_color_range_25_30", label = "25-30 码", max = 30, defaultColor = { 1.00, 0.62, 0.27, 1 } },
    { key = "range_30_35", labelKey = "settings.target_distance_color_range_30_35", label = "30-35 码", max = 35, defaultColor = { 1.00, 0.45, 0.25, 1 } },
    { key = "range_35_40", labelKey = "settings.target_distance_color_range_35_40", label = "35-40 码", max = 40, defaultColor = { 1.00, 0.30, 0.25, 1 } },
    { key = "range_40_plus", labelKey = "settings.target_distance_color_range_40_plus", label = "40+ 码", defaultColor = { 1.00, 0.22, 0.22, 1 } },
    { key = "unknown", labelKey = "settings.target_distance_color_unknown", label = "未知", defaultColor = { 0.62, 0.68, 0.76, 1 } },
}

local RANGE_BUCKETS_BY_KEY = {}
for _, bucket in ipairs(RANGE_BUCKETS) do
    RANGE_BUCKETS_BY_KEY[bucket.key] = bucket
end

local INDICATORS = {
    {
        unit = "target",
        enabledKey = "targetDistanceEnabled",
        layoutID = TARGET_LAYOUT_ID,
        frameName = TARGET_FRAME_NAME,
        titleKey = "layout.target_distance",
        titleFallback = "目标距离",
        defaultY = -120,
    },
    {
        unit = "focus",
        enabledKey = "focusDistanceEnabled",
        layoutID = FOCUS_LAYOUT_ID,
        frameName = FOCUS_FRAME_NAME,
        titleKey = "layout.focus_distance",
        titleFallback = "焦点距离",
        defaultY = -160,
    },
}
local TARGET_INDICATOR = INDICATORS[1]
local FOCUS_INDICATOR = INDICATORS[2]

local featureActive = false
local runtimeDriver
local runtimeRunning = false
local activeRuntimeDB
local updateElapsed = UPDATE_INTERVAL
local eventFrame
local eventsRegistered = false
local EventOwner = {}
local RegisterIndicatorLayout

local EVENT_NAMES = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "UNIT_TARGET",
    "ZONE_CHANGED_NEW_AREA",
}

local function T(key, fallback)
    local value
    if CombatEnhancement.T then
        value = CombatEnhancement:T(key)
    end
    if type(value) == "string" and value ~= "" and value ~= key then
        return value
    end
    return fallback or key
end

local function Round(value)
    value = tonumber(value) or 0
    return math.floor(value + 0.5)
end

local function ClampNumber(value, minValue, maxValue, fallback)
    value = tonumber(value)
    if value == nil then value = fallback end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function ClampColorComponent(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function NormalizeTextStyle(value)
    if VALID_TEXT_STYLES[value] then
        return value
    end
    return DEFAULT_TEXT_STYLE
end

local function CopyColor(color)
    return {
        color and color[1] or 1,
        color and color[2] or 1,
        color and color[3] or 1,
        color and color[4] or 1,
    }
end

local function NormalizeColor(value, defaultColor)
    defaultColor = defaultColor or RANGE_BUCKETS_BY_KEY.unknown.defaultColor
    if type(value) ~= "table" then
        return CopyColor(defaultColor)
    end

    value[1] = ClampColorComponent(value[1] or value.r, defaultColor[1])
    value[2] = ClampColorComponent(value[2] or value.g, defaultColor[2])
    value[3] = ClampColorComponent(value[3] or value.b, defaultColor[3])
    value[4] = ClampColorComponent(value[4] or value.a, defaultColor[4])
    return value
end

local function BuildDefaultRangeColors()
    local colors = {}
    for _, bucket in ipairs(RANGE_BUCKETS) do
        colors[bucket.key] = CopyColor(bucket.defaultColor)
    end
    return colors
end

TargetDistance.defaults = {
    targetDistanceEnabled = true,
    focusDistanceEnabled = false,
    targetDistanceFont = DEFAULT_FONT,
    targetDistanceFontSize = DEFAULT_FONT_SIZE,
    targetDistanceTextStyle = DEFAULT_TEXT_STYLE,
    targetDistanceRangeColors = BuildDefaultRangeColors(),
}

local function NormalizeRangeColors(value)
    if type(value) ~= "table" then
        value = {}
    end

    for _, bucket in ipairs(RANGE_BUCKETS) do
        value[bucket.key] = NormalizeColor(value[bucket.key], bucket.defaultColor)
    end
    return value
end

function TargetDistance:NormalizeDB(db)
    if type(db) ~= "table" then db = self.defaults end
    db.targetDistanceEnabled = db.targetDistanceEnabled ~= false
    db.focusDistanceEnabled = db.focusDistanceEnabled == true
    if type(db.targetDistanceFont) ~= "string" or db.targetDistanceFont == "" then
        db.targetDistanceFont = DEFAULT_FONT
    end
    db.targetDistanceFontSize = ClampNumber(db.targetDistanceFontSize, MIN_FONT_SIZE, MAX_FONT_SIZE, DEFAULT_FONT_SIZE)
    db.targetDistanceTextStyle = NormalizeTextStyle(db.targetDistanceTextStyle)
    db.targetDistanceRangeColors = NormalizeRangeColors(db.targetDistanceRangeColors)
    return db
end

local function GetDB(db)
    if type(db) ~= "table" and CombatEnhancement.GetDB then
        db = CombatEnhancement:GetDB()
    end
    return TargetDistance:NormalizeDB(db)
end

local function UnitExistsCompat(unit)
    local api = UnitAPI or (YUI.API and YUI.API.Unit) or YUI.WOW_API
    if api and api.UnitExists then
        return api.UnitExists(unit) == true
    end
    if UnitExists then
        return UnitExists(unit) == true
    end
    return false
end

local function GetBucketKeyForDistance(yards)
    yards = tonumber(yards)
    if not yards then return "unknown" end
    for _, bucket in ipairs(RANGE_BUCKETS) do
        if bucket.max and yards <= bucket.max then
            return bucket.key
        end
    end
    return "range_40_plus"
end

local function GetBucketKeyForMinRange(yards)
    yards = tonumber(yards)
    if not yards then return "unknown" end
    if yards >= 40 then return "range_40_plus" end
    if yards >= 35 then return "range_35_40" end
    if yards >= 30 then return "range_30_35" end
    if yards >= 25 then return "range_25_30" end
    if yards >= 20 then return "range_20_25" end
    if yards >= 15 then return "range_15_20" end
    if yards >= 10 then return "range_10_15" end
    if yards >= 5 then return "range_05_10" end
    return "range_00_05"
end

local function ShouldHideRangeEstimate(minRange, maxRange)
    minRange = tonumber(minRange)
    maxRange = tonumber(maxRange)
    if not minRange then return false end
    if minRange >= HIDE_AT_MIN_RANGE then return true end
    return minRange > MAX_VISIBLE_MIN_RANGE and not maxRange
end

local function ResolveRangeEstimateText(minRange, maxRange, source)
    minRange = tonumber(minRange)
    maxRange = tonumber(maxRange)

    if ShouldHideRangeEstimate(minRange, maxRange) then
        return nil, nil
    end

    if source == "UnitDistanceSquared" and minRange then
        return tostring(Round(minRange)), GetBucketKeyForMinRange(minRange)
    end

    if source == "InteractDistance" then
        if minRange and not maxRange then
            return ">" .. tostring(Round(minRange)), GetBucketKeyForMinRange(minRange)
        end
        if maxRange and not minRange then
            return "<=" .. tostring(Round(maxRange)), GetBucketKeyForDistance(maxRange)
        end
    end

    if minRange and maxRange then
        return tostring(Round(minRange)) .. " - " .. tostring(Round(maxRange)), GetBucketKeyForMinRange(minRange)
    end
    if minRange then
        return tostring(Round(minRange)) .. "+", GetBucketKeyForMinRange(minRange)
    end
    if maxRange then
        return "<=" .. tostring(Round(maxRange)), GetBucketKeyForDistance(maxRange)
    end

    return nil, nil
end

local function ResolveDistanceText(indicator)
    if indicator.previewActive then
        return "30 - 35", "range_30_35"
    end
    if not UnitExistsCompat(indicator.unit) then
        return nil, nil
    end

    if UnitAPI and UnitAPI.GetRangeEstimate then
        local minRange, maxRange, source = UnitAPI.GetRangeEstimate(indicator.unit)
        return ResolveRangeEstimateText(minRange, maxRange, source)
    end

    return nil, nil
end

local function GetColorForBucket(db, bucketKey)
    if type(db) ~= "table" then
        db = GetDB(db)
    end
    local bucket = RANGE_BUCKETS_BY_KEY[bucketKey] or RANGE_BUCKETS_BY_KEY.unknown
    local colors = db.targetDistanceRangeColors
    return NormalizeColor(colors and colors[bucket.key], bucket.defaultColor)
end

local function SetTextColor(fontString, color)
    if not (fontString and fontString.SetTextColor) then return end
    color = NormalizeColor(color, RANGE_BUCKETS_BY_KEY.unknown.defaultColor)
    fontString:SetTextColor(color[1], color[2], color[3], color[4])
end

local function GetDefaultFontPath()
    if GUI2 and GUI2.GetFont then
        local font = GUI2:GetFont("font.family.body")
        if type(font) == "string" and font ~= "" then return font end
    end
    if GameFontNormalHuge and GameFontNormalHuge.GetFont then
        local font = GameFontNormalHuge:GetFont()
        if font then return font end
    end
    if GameFontNormal and GameFontNormal.GetFont then
        local font = GameFontNormal:GetFont()
        if font then return font end
    end
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

local function ResolveFontPath(fontName)
    if type(fontName) == "string" and (fontName:find("\\", 1, true) or fontName:find("/", 1, true)) then return fontName end
    if fontName ~= DEFAULT_FONT and LSM and LSM.Fetch then
        local path = LSM:Fetch("font", fontName, true)
        if type(path) == "string" and path ~= "" then
            return path
        end
    end
    return GetDefaultFontPath()
end

local function GetTextStyleFontFlags(style)
    style = NormalizeTextStyle(style)
    if style == TEXT_STYLE_OUTLINE_SHADOW or style == "outline" then
        return "OUTLINE"
    elseif style == "thick" or style == "thick_shadow" then
        return "THICKOUTLINE"
    end
    return nil
end

local function ApplyTextShadow(fontString, style)
    if not fontString then return end
    style = NormalizeTextStyle(style)
    if style == TEXT_STYLE_SHADOW or style == TEXT_STYLE_OUTLINE_SHADOW or style == "thick_shadow" then
        if fontString.SetShadowColor then fontString:SetShadowColor(0, 0, 0, 1) end
        if fontString.SetShadowOffset then fontString:SetShadowOffset(1, -1) end
    else
        if fontString.SetShadowOffset then fontString:SetShadowOffset(0, 0) end
    end
end

local function ToLayoutPlacement(point, relative, relativePoint, x, y)
    return {
        version = 1,
        anchor = {
            point = point or "CENTER",
            relative = relative or "UIParent",
            relativePoint = relativePoint or point or "CENTER",
        },
        offset = {
            x = x or 0,
            y = y or 0,
        },
    }
end

local function GetDefaultPlacement(indicator)
    return ToLayoutPlacement("CENTER", "UIParent", "CENTER", 0, indicator.defaultY)
end

local function ApplyDefaultPoint(indicator, frame)
    if not (frame and UIParent) then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, indicator.defaultY)
end

local function ApplyRuntimeLayer(frame)
    if not frame then return end
    if frame.SetFrameStrata then frame:SetFrameStrata("MEDIUM") end
    if frame.SetFrameLevel then frame:SetFrameLevel(10) end
end

local function EnsureIndicatorFrame(indicator)
    if indicator.frame then
        return indicator.frame
    end
    if not (CreateFrame and UIParent) then
        return nil
    end

    local frame = CreateFrame("Frame", indicator.frameName, UIParent)
    frame:SetSize(DEFAULT_FRAME_WIDTH, DEFAULT_FRAME_HEIGHT)
    ApplyDefaultPoint(indicator, frame)
    ApplyRuntimeLayer(frame)
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    frame:EnableMouse(false)

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    if text.SetFont then
        text:SetFont(GetDefaultFontPath(), DEFAULT_FONT_SIZE, GetTextStyleFontFlags(DEFAULT_TEXT_STYLE))
    end
    ApplyTextShadow(text, DEFAULT_TEXT_STYLE)

    indicator.frame = frame
    indicator.text = text
    indicator.visible = false
    frame:Hide()
    if RegisterIndicatorLayout and not indicator.layoutRegistered and not indicator.registeringLayout then
        RegisterIndicatorLayout(indicator)
    end
    return frame
end

local function EnsureRuntimeDriver()
    if runtimeDriver then return runtimeDriver end
    if not CreateFrame then return nil end
    runtimeDriver = CreateFrame("Frame", RUNTIME_FRAME_NAME)
    runtimeDriver:Hide()
    return runtimeDriver
end

local function RefreshLayoutFrames()
    if not (YUI.Layout and YUI.Layout.RefreshFrame) then return end
    for index = 1, #INDICATORS do
        local indicator = INDICATORS[index]
        if indicator.layoutRegistered then
            YUI.Layout:RefreshFrame(indicator.layoutID)
        end
    end
end

function TargetDistance:MeasureLayoutSize(fontSize)
    return math.max(DEFAULT_FRAME_WIDTH, fontSize * 5), math.max(DEFAULT_FRAME_HEIGHT, fontSize + 14)
end

local function ApplyIndicatorAppearance(indicator, db)
    local frame = EnsureIndicatorFrame(indicator)
    if not (frame and indicator.text) then return end

    db = GetDB(db)
    local fontName = db.targetDistanceFont
    local fontSize = db.targetDistanceFontSize
    local textStyle = db.targetDistanceTextStyle
    if indicator.appliedFont ~= fontName
        or indicator.appliedFontSize ~= fontSize
        or indicator.appliedTextStyle ~= textStyle
        or indicator.appliedMonochrome ~= (db.targetDistanceMonochrome == true) then
        if indicator.text.SetFont then
            local fontPath = ResolveFontPath(fontName)
            local flags = GetTextStyleFontFlags(textStyle)
            if db.targetDistanceMonochrome then flags = flags and flags .. ",MONOCHROME" or "MONOCHROME" end
            local ok
            if GUI2 and GUI2.FontStyle and GUI2.FontStyle.TryFont then
                ok = GUI2.FontStyle.TryFont(indicator.text, fontPath, fontSize, flags)
            else
                local called, applied = pcall(indicator.text.SetFont, indicator.text, fontPath, fontSize, flags)
                ok = called and applied ~= false
            end
            if not ok and fontPath ~= GetDefaultFontPath() then
                pcall(indicator.text.SetFont, indicator.text, GetDefaultFontPath(), fontSize, flags)
            end
        end
        ApplyTextShadow(indicator.text, textStyle)
        indicator.appliedFont = fontName
        indicator.appliedFontSize = fontSize
        indicator.appliedTextStyle = textStyle
        indicator.appliedMonochrome = db.targetDistanceMonochrome == true
        frame:SetSize(TargetDistance:MeasureLayoutSize(fontSize))
    end
    ApplyRuntimeLayer(frame)
end

local function ApplyAppearance(db)
    db = GetDB(db)
    for index = 1, #INDICATORS do
        ApplyIndicatorAppearance(INDICATORS[index], db)
    end
end

-- One logical target for the target/focus shared style; never enumerate frames.
if GUI2 and GUI2.FontStyle then
    local Style = GUI2.FontStyle
    local keys = { "targetDistanceFont", "targetDistanceFontSize", "targetDistanceTextStyle", "targetDistanceMonochrome" }
    local function RawFontDB()
        local profile = YUI.DB and YUI.DB:GetProfile(CombatEnhancement.PRODUCT_ID)
        local store = profile and (profile.Components or profile.YBox)
        return store and store[CombatEnhancement.CONFIG_KEY], profile
    end
    Style:Register("combat_distance", function()
        local db, profile = RawFontDB()
        if not db then return nil end
        local group = { targets = {}, label = T("name", "战斗增强") }
        group.current = function()
            local current, currentProfile = RawFontDB()
            return current == db and currentProfile == profile
        end
        local function Read()
            local effect = Style.Decode(NormalizeTextStyle(db.targetDistanceTextStyle), nil, db.targetDistanceMonochrome)
            effect.font = ResolveFontPath(db.targetDistanceFont or DEFAULT_FONT)
            effect.size = db.targetDistanceFontSize or DEFAULT_FONT_SIZE
            return effect
        end
        group.snapshot = function()
            local copy = {}
            for _, key in ipairs(keys) do copy[key] = db[key] end
            return copy
        end
        local function Refresh()
            -- Cold disabled targets update configuration without creating indicators.
            if featureActive then ApplyAppearance(db); RefreshLayoutFrames(); TargetDistance:RefreshRuntime(db) end
        end
        group.apply = function(changes)
            if not group.current() then return false, "stale" end
            local patch = changes.shared
            if not patch then return false, "missing" end
            local current = Read()
            local defaults = { font = DEFAULT_FONT, size = DEFAULT_FONT_SIZE, outline = "OUTLINE", shadow = true, monochrome = false }
            for key, value in pairs(patch.values or {}) do current[key] = value end
            for key in pairs(patch.reset or {}) do current[key] = defaults[key] end
            if patch.values.font ~= nil or patch.reset and patch.reset.font then db.targetDistanceFont = current.font end
            if patch.values.size ~= nil or patch.reset and patch.reset.size then db.targetDistanceFontSize = current.size end
            if patch.values.outline ~= nil or patch.values.shadow ~= nil or patch.reset and (patch.reset.outline or patch.reset.shadow) then
                local base = current.outline == "THICKOUTLINE" and "thick" or current.outline == "OUTLINE" and "outline" or "none"
                db.targetDistanceTextStyle = current.shadow and (base == "none" and "shadow" or base .. "_shadow") or base
            end
            if patch.values.monochrome ~= nil then db.targetDistanceMonochrome = current.monochrome end
            if patch.reset and patch.reset.monochrome then db.targetDistanceMonochrome = nil end
            Refresh(); return true
        end
        group.restore = function(snapshots)
            if not group.current() then return false, "stale" end
            for _, key in ipairs(keys) do db[key] = snapshots.shared[key] end
            Refresh(); return true
        end
        group.targets[1] = { id = "shared", label = T("settings.target_distance_font_target", "目标/焦点距离"),
            capabilities = { font = true, size = true, outline = true, shadow = true, monochrome = true },
            minSize = MIN_FONT_SIZE, maxSize = MAX_FONT_SIZE, read = Read,
            parent = function(key)
                local defaults = { font = GetDefaultFontPath(), size = DEFAULT_FONT_SIZE, outline = "OUTLINE", shadow = true, monochrome = false }
                return defaults[key]
            end }
        return group
    end)
end

local function StopRuntimeUpdates()
    if runtimeDriver and runtimeRunning then
        runtimeDriver:SetScript("OnUpdate", nil)
        runtimeDriver:Hide()
    end
    runtimeRunning = false
    activeRuntimeDB = nil
    updateElapsed = UPDATE_INTERVAL
end

local function ResetIndicatorCache(indicator)
    indicator.lastText = nil
    indicator.lastBucketKey = nil
end

local function HideIndicator(indicator)
    ResetIndicatorCache(indicator)
    if indicator.frame and indicator.visible then
        indicator.frame:Hide()
    end
    indicator.visible = false
end

local function IsIndicatorEnabled(indicator, db)
    return db[indicator.enabledKey] == true
end

local function ShouldTrackIndicator(indicator, db)
    return featureActive and IsIndicatorEnabled(indicator, db) and UnitExistsCompat(indicator.unit)
end

local function RefreshIndicatorDisplay(indicator, db)
    local frame = EnsureIndicatorFrame(indicator)
    if not (frame and indicator.text) then return false end

    local text, bucketKey = ResolveDistanceText(indicator)
    if not text then
        HideIndicator(indicator)
        return false
    end

    ApplyIndicatorAppearance(indicator, db)
    if text ~= indicator.lastText then
        indicator.text:SetText(text)
        indicator.lastText = text
    end
    if bucketKey ~= indicator.lastBucketKey then
        SetTextColor(indicator.text, GetColorForBucket(db, bucketKey))
        indicator.lastBucketKey = bucketKey
    end
    if not indicator.visible then
        frame:Show()
        indicator.visible = true
    end
    return true
end

local cpuWatchdog = YUI.CPUWatchdog
local function OnRuntimeUpdate(frame, elapsed)
    updateElapsed = updateElapsed + (tonumber(elapsed) or 0)
    if updateElapsed < UPDATE_INTERVAL then return end
    local cpuStartedAt = cpuWatchdog and cpuWatchdog.timingActive and cpuWatchdog:BeginProbeTiming()
    updateElapsed = 0
    local db = activeRuntimeDB or GetDB()
    local hasTrackedIndicator = false
    for index = 1, #INDICATORS do
        local indicator = INDICATORS[index]
        if not indicator.previewActive and ShouldTrackIndicator(indicator, db) then
            hasTrackedIndicator = true
            RefreshIndicatorDisplay(indicator, db)
        elseif not indicator.previewActive then
            HideIndicator(indicator)
        end
    end
    if not hasTrackedIndicator then
        StopRuntimeUpdates()
    end
    if cpuStartedAt then cpuWatchdog:EndProbeTiming("component.target-distance", cpuStartedAt) end
end

local function StartRuntimeUpdates(db)
    local driver = EnsureRuntimeDriver()
    if not (driver and driver.SetScript) then return end
    activeRuntimeDB = db
    if runtimeRunning then return end
    updateElapsed = 0
    driver:SetScript("OnUpdate", OnRuntimeUpdate)
    driver:Show()
    runtimeRunning = true
end

local function HasTrackedRuntimeIndicator(db)
    for index = 1, #INDICATORS do
        local indicator = INDICATORS[index]
        if not indicator.previewActive and ShouldTrackIndicator(indicator, db) then
            return true
        end
    end
    return false
end

local function SetIndicatorLayoutPreview(indicator, active)
    indicator.previewActive = active == true
    local db = GetDB()
    if indicator.previewActive or ShouldTrackIndicator(indicator, db) then
        RefreshIndicatorDisplay(indicator, db)
    else
        HideIndicator(indicator)
    end
    if HasTrackedRuntimeIndicator(db) then
        StartRuntimeUpdates(db)
    else
        StopRuntimeUpdates()
    end
end

if cpuWatchdog and cpuWatchdog.RegisterProbe then
    cpuWatchdog:RegisterProbe("component.target-distance", {
        localeKey = "cpu_watch.probe.target_distance",
        kind = "frame",
        getTarget = function() return runtimeDriver end,
        snapshot = function()
            return {
                running = runtimeRunning,
                targetVisible = TARGET_INDICATOR.visible == true,
                focusVisible = FOCUS_INDICATOR.visible == true,
            }
        end,
    })
end

local function OpenTargetDistanceSettings()
    if YUI.Settings and YUI.Settings.OpenComponentFeature then
        YUI.Settings:OpenComponentFeature(FEATURE_KEY)
        return true
    end
    if YUI.Components and YUI.Components.OpenFeatureSettings then
        YUI.Components:OpenFeatureSettings(FEATURE_KEY)
        return true
    end
    return false
end

RegisterIndicatorLayout = function(indicator)
    if indicator.registeringLayout then return end
    indicator.registeringLayout = true
    local frame = EnsureIndicatorFrame(indicator)
    if not frame then
        indicator.registeringLayout = false
        return
    end

    if not (YUI.Layout and YUI.Layout.RegisterFrame) then
        ApplyDefaultPoint(indicator, frame)
        indicator.registeringLayout = false
        return
    end

    if indicator.layoutRegistered then
        indicator.registeringLayout = false
        return
    end

    YUI.Layout:RegisterFrame(indicator.layoutID, {
        frame = frame,
        title = T(indicator.titleKey, indicator.titleFallback),
        category = "component",
        defaultPlacement = function()
            return GetDefaultPlacement(indicator)
        end,
        movable = true,
        snap = true,
        anchorTargets = { "UIParent" },
        minWidth = DEFAULT_FRAME_WIDTH,
        minHeight = DEFAULT_FRAME_HEIGHT,
        isEnabled = function()
            local editing = YUI.Layout and YUI.Layout.IsEditing and YUI.Layout:IsEditing()
            if editing then return true end
            return IsIndicatorEnabled(indicator, GetDB()) and (featureActive or indicator.previewActive)
        end,
        openPluginSettings = OpenTargetDistanceSettings,
        onEnterEditMode = function()
            SetIndicatorLayoutPreview(indicator, true)
        end,
        onExitEditMode = function()
            SetIndicatorLayoutPreview(indicator, false)
        end,
        onApply = function()
            ApplyIndicatorAppearance(indicator, GetDB())
        end,
    })
    indicator.layoutRegistered = true
    indicator.registeringLayout = false
end

local function RegisterLayouts()
    for index = 1, #INDICATORS do
        RegisterIndicatorLayout(INDICATORS[index])
    end
end

function TargetDistance:RefreshRuntime(db)
    if YUI.Layout and YUI.Layout.InvalidateAnchorProvider then
        YUI.Layout:InvalidateAnchorProvider(TARGET_LAYOUT_ID)
        YUI.Layout:InvalidateAnchorProvider(FOCUS_LAYOUT_ID)
    end
    db = GetDB(db)
    RegisterLayouts()

    local hasTrackedIndicator = false
    for index = 1, #INDICATORS do
        local indicator = INDICATORS[index]
        if indicator.previewActive then
            RefreshIndicatorDisplay(indicator, db)
        elseif ShouldTrackIndicator(indicator, db) then
            hasTrackedIndicator = true
            RefreshIndicatorDisplay(indicator, db)
        else
            HideIndicator(indicator)
        end
    end
    if hasTrackedIndicator then
        StartRuntimeUpdates(db)
    else
        StopRuntimeUpdates()
    end
end

local function OnRuntimeEvent()
    TargetDistance:RefreshRuntime()
end

local function AttachEvents()
    if eventsRegistered then return end

    if YUI.Event and YUI.Event.On then
        for _, eventName in ipairs(EVENT_NAMES) do
            local options = {
                traceName = "CombatEnhancement:TargetDistance:" .. eventName,
                moduleId = "component:CombatEnhancement",
            }
            if eventName == "UNIT_TARGET" then
                options.unit = "player"
            end
            YUI.Event:On(eventName, OnRuntimeEvent, EventOwner, options)
        end
        eventsRegistered = "eventbus"
        return
    end

    if CreateFrame then
        eventFrame = eventFrame or CreateFrame("Frame")
        for _, eventName in ipairs(EVENT_NAMES) do
            if eventName == "UNIT_TARGET" and eventFrame.RegisterUnitEvent then
                local ok = pcall(eventFrame.RegisterUnitEvent, eventFrame, eventName, "player")
                if not ok then
                    pcall(eventFrame.RegisterEvent, eventFrame, eventName)
                end
            else
                pcall(eventFrame.RegisterEvent, eventFrame, eventName)
            end
        end
        eventFrame:SetScript("OnEvent", OnRuntimeEvent)
        eventsRegistered = "frame"
    end
end

local function DetachEvents()
    if eventsRegistered == "eventbus" and YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(EventOwner)
    elseif eventsRegistered == "frame" and eventFrame then
        for _, eventName in ipairs(EVENT_NAMES) do
            pcall(eventFrame.UnregisterEvent, eventFrame, eventName)
        end
        eventFrame:SetScript("OnEvent", nil)
    end
    eventsRegistered = false
end

local function AddAlignedFieldGroup(options, label, fields, layout)
    layout = type(layout) == "table" and layout or {}
    options[#options + 1] = { type = "divider", label = label, alignLeft = true, width = SECTION_WIDTH }
    options[#options + 1] = {
        type = "custom",
        retainedFields = fields,
        width = SECTION_WIDTH,
        render = function(parent, x, y, width)
            local Settings = YUI.Settings
            if not (Settings and Settings.RenderAlignedFields) then
                return SECTION_WIDTH, 1
            end

            local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                x = x,
                y = y,
                width = math.min(width or SECTION_WIDTH, SECTION_WIDTH),
                columns = layout.columns or 2,
                labelPosition = layout.labelPosition or "top",
                columnGap = layout.columnGap or COLUMN_GAP,
                labelWidth = layout.labelWidth or LABEL_WIDTH,
                labelGap = layout.labelGap or LABEL_GAP,
                bodyWidth = layout.bodyWidth or BODY_WIDTH,
                valueWidth = layout.valueWidth or INPUT_WIDTH,
                valueGap = layout.valueGap or VALUE_GAP,
                rowHeight = layout.rowHeight or 32,
                rowGap = layout.rowGap or 10,
                fields = fields,
            })
            return gridWidth, gridHeight
        end,
    }
end

local function AddAlignedFieldRow(options, fields, layout)
    layout = type(layout) == "table" and layout or {}
    options[#options + 1] = {
        type = "custom",
        retainedFields = fields,
        width = SECTION_WIDTH,
        render = function(parent, x, y, width)
            local Settings = YUI.Settings
            if not (Settings and Settings.RenderAlignedFields) then
                return SECTION_WIDTH, 1
            end

            local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                x = x,
                y = y,
                width = math.min(width or SECTION_WIDTH, SECTION_WIDTH),
                columns = layout.columns or 1,
                labelPosition = layout.labelPosition or "top",
                columnGap = layout.columnGap or COLUMN_GAP,
                labelWidth = layout.labelWidth or LABEL_WIDTH,
                labelGap = layout.labelGap or LABEL_GAP,
                bodyWidth = layout.bodyWidth or BODY_WIDTH,
                valueWidth = layout.valueWidth or INPUT_WIDTH,
                valueGap = layout.valueGap or VALUE_GAP,
                rowHeight = layout.rowHeight or 32,
                rowGap = layout.rowGap or 10,
                fields = fields,
            })
            return gridWidth, gridHeight
        end,
    }
end

local function BuildRangeColorFields(db)
    local fields = {}
    for _, bucket in ipairs(RANGE_BUCKETS) do
        if bucket.key ~= "unknown" then
            local key = bucket.key
            local label = T(bucket.labelKey, bucket.label)
            local defaultColor = bucket.defaultColor
            fields[#fields + 1] = {
                type = "color",
                label = label,
                layoutPreset = "compactColor",
                default = defaultColor,
                hasAlpha = true,
                get = function()
                    return db.targetDistanceRangeColors[key]
                end,
                set = function(value)
                    db.targetDistanceRangeColors[key] = NormalizeColor(value, defaultColor)
                    TargetDistance:RefreshRuntime(db)
                end,
            }
        end
    end
    return fields
end

local function BuildTextStyleOptions()
    return {
        { text = T("settings.target_distance_text_style_none", "无"), value = TEXT_STYLE_NONE },
        { text = T("settings.target_distance_text_style_shadow", "阴影"), value = TEXT_STYLE_SHADOW },
        { text = T("settings.target_distance_text_style_outline_shadow", "描边加阴影"), value = TEXT_STYLE_OUTLINE_SHADOW },
    }
end

function TargetDistance:BuildOptions(db)
    db = GetDB(db)
    RegisterLayouts()

    local options = {}

    AddAlignedFieldRow(options, {
        {
            type = "checkbox",
            label = T("settings.target_distance_target_enabled", "目标距离"),
            settingsToggle = "targetDistance",
            searchKey = "settings.target_distance_target_enabled",
            get = function() return db.targetDistanceEnabled end,
            set = function(value)
                db.targetDistanceEnabled = value == true
                TargetDistance:RefreshRuntime(db)
                RefreshLayoutFrames()
            end,
        },
        {
            type = "checkbox",
            label = T("settings.target_distance_focus_enabled", "焦点距离"),
            settingsToggle = "focusDistance",
            searchKey = "settings.target_distance_focus_enabled",
            get = function() return db.focusDistanceEnabled end,
            set = function(value)
                db.focusDistanceEnabled = value == true
                TargetDistance:RefreshRuntime(db)
                RefreshLayoutFrames()
            end,
        },
    }, { columns = 2 })

    local textFields = {
        {
            type = GUI2 and GUI2.Form and GUI2.Form.CreateFontStyle and "custom" or "font",
            label = GUI2 and GUI2.Form and GUI2.Form.CreateFontStyle and YUI.Locale:Get("Core")["font_style.text"] or T("settings.target_distance_font", "字体"),
            minControlWidth = 96,
            default = DEFAULT_FONT,
            prependOptions = function()
                return {
                    {
                        text = T("settings.target_distance_font_default", "默认"),
                        value = DEFAULT_FONT,
                        fontPath = GetDefaultFontPath(),
                    },
                }
            end,
            get = function() return db.targetDistanceFont end,
            render = function(parent, _, width)
                return GUI2.Form:CreateFontStyle(parent, { key = "combat_distance:shared", width = width })
            end,
            set = function(value)
                db.targetDistanceFont = type(value) == "string" and value ~= "" and value or DEFAULT_FONT
                for index = 1, #INDICATORS do
                    INDICATORS[index].appliedFont = nil
                end
                ApplyAppearance(db)
                RefreshLayoutFrames()
                TargetDistance:RefreshRuntime(db)
            end,
        },
        {
            type = GUI2 and GUI2.Form and GUI2.Form.CreateFontStyle and "custom" or "slider",
            label = T("settings.target_distance_font_size", "文本尺寸"),
            min = MIN_FONT_SIZE,
            max = MAX_FONT_SIZE,
            step = 1,
            get = function() return db.targetDistanceFontSize end,
            render = function(parent, spec, width)
                local slider = GUI2.Form:CreateSlider(parent, {
                    width = width, min = MIN_FONT_SIZE, max = MAX_FONT_SIZE, step = 1,
                    inline = true, inputWidth = INPUT_WIDTH, get = spec.get, set = spec.set,
                })
                GUI2.FontStyle:BindValue(slider, "combat_distance:shared", "size")
                return slider
            end,
            set = function(value)
                db.targetDistanceFontSize = ClampNumber(value, MIN_FONT_SIZE, MAX_FONT_SIZE, DEFAULT_FONT_SIZE)
                ApplyAppearance(db)
                RefreshLayoutFrames()
                TargetDistance:RefreshRuntime(db)
                if GUI2 and GUI2.FontStyle then GUI2.FontStyle:RefreshControls() end
            end,
        },
    }
    if GUI2 and GUI2.Form and GUI2.Form.CreateFontStyle then table.remove(textFields, 2) end
    AddAlignedFieldGroup(options, T("settings.target_distance_appearance", "共享显示样式"), textFields)

    if not (GUI2 and GUI2.Form and GUI2.Form.CreateFontStyle) then
        AddAlignedFieldRow(options, {{ type = "dropdown", label = T("settings.target_distance_text_style", "描边阴影"),
            options = BuildTextStyleOptions, get = function() return db.targetDistanceTextStyle end,
            set = function(value) db.targetDistanceTextStyle = NormalizeTextStyle(value); ApplyAppearance(db); RefreshLayoutFrames(); TargetDistance:RefreshRuntime(db) end }})
    end
    AddAlignedFieldGroup(options, T("settings.target_distance_range_colors", "共享范围颜色"), BuildRangeColorFields(db), {
        columns = 2,
        columnGap = 18,
        labelWidth = 72,
        labelGap = 8,
        bodyWidth = 114,
    })

    return options
end

function TargetDistance:OnFeatureToggle(enabled, db)
    featureActive = enabled == true
    if featureActive then
        AttachEvents()
        self:RefreshRuntime(db)
    else
        if GUI2 and GUI2.FontStyle and GUI2.FontStyle.CloseForProvider then GUI2.FontStyle:CloseForProvider("combat_distance") end
        DetachEvents()
        StopRuntimeUpdates()
        for index = 1, #INDICATORS do
            local indicator = INDICATORS[index]
            indicator.previewActive = false
            HideIndicator(indicator)
        end
    end
    RefreshLayoutFrames()
end

function TargetDistance:OnSettingsLeave(db)
    if GUI2 and GUI2.FontStyle and GUI2.FontStyle.CloseForProvider then GUI2.FontStyle:CloseForProvider("combat_distance") end
    self:RefreshRuntime(db)
end

CombatEnhancement.TargetDistance = TargetDistance
CombatEnhancement:RegisterSubFeature(TargetDistance)




-- Resolve disabled targets without creating widgets or starting feature runtime.
if YUI.Layout and YUI.Layout.RegisterAnchorProvider then
    local function ResolveColdAnchor(id)
        local components = YUI.Components
        local db = components and components.CopyConfigSnapshot and components:CopyConfigSnapshot(
            CombatEnhancement.CONFIG_KEY, CombatEnhancement.defaults, CombatEnhancement.PRODUCT_ID)
        if not db then return nil end
        db = TargetDistance:NormalizeDB(db)
        local indicator = id == TARGET_LAYOUT_ID and TARGET_INDICATOR or FOCUS_INDICATOR
        local width, height = TargetDistance:MeasureLayoutSize(db.targetDistanceFontSize)
        return GetDefaultPlacement(indicator), width, height, 1
    end
    for _, indicator in ipairs(INDICATORS) do
        YUI.Layout:RegisterAnchorProvider(indicator.layoutID, {name=indicator.frameName, resolve=ResolveColdAnchor})
    end
end
