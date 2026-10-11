local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI or not YUI.IsRetail then return end

local GUI2 = YUI.GUI2
local Monitor = YUI.ClassExtraMonitor
if not Monitor or not Monitor.RegisterSubFeature then return end

local CoreMonitor = YUI.Monitor
local UnitAPI = (YUI.API and YUI.API.Unit) or YUI.WOW_API or {}
local SpellAPI = (YUI.API and YUI.API.Spell) or YUI.WOW_API or {}
local TalentAPI = (YUI.API and YUI.API.Talent) or YUI.WOW_API or {}
local SecurityAPI = (YUI.API and YUI.API.Security) or YUI.WOW_API or {}
local L = Monitor.L or (YUI.Locale and YUI.Locale:Get("ClassExtraMonitor")) or nil
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local C_Timer = C_Timer

local FEATURE_KEY = Monitor.FEATURE_KEY or "ClassExtraMonitor"
local MODULE_ID = "component:" .. FEATURE_KEY .. ":DevourerTransform"
local LAYOUT_ID = "yui.component.class_extra_monitor.devourer_transform"
local TRANSFORM_BUFF_ID = 1217607
local SOUL_BOMB_SPELL_ID = 1221150
local DEVOURER_SPEC_ID = 1480

local FALLBACK_ICON = "Interface\\Icons\\Ability_DemonHunter_EyeBeam"

local DEFAULT_COUNT_COLOR = { 0.14, 1, 0.18, 1 }
local DEFAULT_TIMER_COLOR = { 1, 1, 1, 1 }
local DEFAULT_ALERT_COLOR = { 1, 0.82, 0.12, 1 }
local DEFAULT_GLOW_COLOR = { 1, 0.917647123336792, 0, 1 }
local DEFAULT_BAR_COLOR = { 0.28, 0.62, 0.95, 0.95 }
local DEFAULT_BAR_ALERT_COLOR = { 1, 0.82, 0.12, 1 }

local DISPLAY_MODE_ICON = "icon"
local DISPLAY_MODE_BAR = "bar"
local DISPLAY_MODE_TEXT = "text"

local VALID_DISPLAY_MODES = {
    icon = true,
    bar = true,
    text = true,
}

local VALID_GLOW_STYLES = {
    none = true,
    soft = true,
    pixel = true,
    button = true,
    autocast = true,
    proc = true,
    pulse = true,
}

local VALID_SOUND_CHANNELS = {
    Master = true,
    SFX = true,
    Music = true,
    Ambience = true,
    Dialog = true,
}

local VALID_ALERT_SOUND_MODES = {
    lsm = true,
    custom = true,
    none = true,
}

local SECTION_WIDTH = 620
local COLUMN_GAP = 24
local LABEL_WIDTH = 112
local LABEL_GAP = 10
local VALUE_GAP = 10
local INPUT_WIDTH = 56
local COLUMN_WIDTH = math.floor((SECTION_WIDTH - COLUMN_GAP) / 2)
local BODY_WIDTH = COLUMN_WIDTH - LABEL_WIDTH - LABEL_GAP
local COUNT_SLOT_HEIGHT = 24
local BAR_COUNT_GAP = 6
local TEXT_MODE_MIN_WIDTH = 112
local TEXT_SLOT_GAP = 2
local TEXT_SLOT_PADDING = 6
local TEXT_WIDTH_PADDING = 16
local UPDATE_INTERVAL = 0.05
local PREVIEW_LEAD_SECONDS = 3

local DevourerTransform = {
    id = "devourerTransform",
    labelKey = "settings.tab_devourer_transform",
    label = "噬灭变身",
    specID = 1480,
    classFile = "DEMONHUNTER",
    order = 10,
}

DevourerTransform.defaults = {
    devourerTransformEnabled = true,
    devourerDisplayMode = DISPLAY_MODE_ICON,
    devourerShowCountText = true,
    devourerEndedHideDelay = 3,
    devourerAlertSecond = 38,
    devourerAlertSound = "raidWarning",
    devourerAlertSoundMode = "lsm",
    devourerAlertLSMSound = "None",
    devourerAlertCustomPath = "",
    devourerAlertSoundModeMigrated = false,
    devourerAlertChannel = "Master",
    devourerIconSize = 42,
    devourerBarIconSize = 34,
    devourerBarWidth = 180,
    devourerBarHeight = 24,
    devourerTimerFontSize = 18,
    devourerCountFontSize = 24,
    devourerGlowStyle = "pixel",
    devourerGlowSize = 1.00,
    devourerGlowLines = 8,
    devourerGlowThickness = 2,
    devourerGlowLength = 20,
    devourerGlowSpeed = 0.25,
    devourerGlowAlpha = 0.90,
    devourerGlowFalloff = 0.30,
    devourerGlowOffsetX = 0,
    devourerGlowOffsetY = 0,
    devourerGlowColor = DEFAULT_GLOW_COLOR,
}

local Widget = {}
local RuntimeMonitor
local featureActive = false
local runtimeActive = false
local layoutPreviewActive = false
local layoutPreviewSuppressed = false
local settingsPreviewActive = false
local activeDB
local glowOptionsExpanded = false
local hideToken = 0
local CancelEndedHide
local StartPreviewUpdate
local StopUpdate
local ResetRuntimeState
local StartTransform

local State = {
    active = false,
    hasLast = false,
    startTime = nil,
    elapsed = 0,
    count = 0,
    alertTriggered = false,
    updateElapsed = 0,
}

local function T(key, fallback)
    return (L and L[key]) or fallback or key
end

local function Round(value)
    value = tonumber(value) or 0
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end

local function ClampNumber(value, minValue, maxValue, fallback)
    value = tonumber(value)
    if value == nil then value = fallback end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function ClampUnit(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback or 1 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function NormalizeGlowSizeValue(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback or DevourerTransform.defaults.devourerGlowSize end
    if value > 5 then
        value = value / 10
    end
    return ClampNumber(value, 0.25, 5, DevourerTransform.defaults.devourerGlowSize)
end

local function NormalizeGlowExpandValue(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback or 0 end
    if value > 1 or value < -1 then
        value = value / 24
    end
    return ClampNumber(value, -1, 1, 0)
end

local function GetColorComponents(value, fallback)
    fallback = fallback or DEFAULT_TIMER_COLOR
    local source = type(value) == "table" and value or fallback
    return
        ClampUnit(source[1] or source.r, fallback[1] or fallback.r or 1),
        ClampUnit(source[2] or source.g, fallback[2] or fallback.g or 1),
        ClampUnit(source[3] or source.b, fallback[3] or fallback.b or 1),
        ClampUnit(source[4] or source.a, fallback[4] or fallback.a or 1)
end

local function NormalizeColorTable(value, fallback)
    local r, g, b, a = GetColorComponents(value, fallback or DEFAULT_GLOW_COLOR)
    return { r, g, b, a }
end

local function SetTextColor(fontString, color)
    if not (fontString and fontString.SetTextColor) then return end
    fontString:SetTextColor(GetColorComponents(color))
end

local function SetFontSize(fontString, size, flags)
    if not (fontString and fontString.GetFont and fontString.SetFont) then return end
    local font = fontString:GetFont()
    fontString:SetFont(font or STANDARD_TEXT_FONT, Round(size), flags)
end

local function IsSecretValue(value)
    if SecurityAPI and SecurityAPI.IsSecretValue then
        return SecurityAPI.IsSecretValue(value) == true
    end
    if type(issecretvalue) ~= "function" then
        return false
    end
    local ok, isSecret = pcall(issecretvalue, value)
    return ok and isSecret == true
end

local function SafeNumber(value)
    if SecurityAPI and SecurityAPI.SafeNumber then
        return SecurityAPI.SafeNumber(value)
    end
    if value == nil or IsSecretValue(value) then
        return nil
    end
    local ok, numberValue = pcall(tonumber, value)
    if ok and numberValue ~= nil and not IsSecretValue(numberValue) then
        return numberValue
    end
    return nil
end

local function SafeBooleanValue(value, fallback)
    if value == nil or IsSecretValue(value) then
        return fallback
    end
    if type(value) == "boolean" then
        return value
    end
    return fallback
end

local function Trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:match("^%s*(.-)%s*$") or ""
end

local function GetNow()
    return GetTime and GetTime() or 0
end

local function ToLayoutPlacement(point, relative, relativePoint, x, y)
    return {
        version = 1,
        anchor = {
            point = point or "CENTER",
            relative = relative or "UIParent",
            relativePoint = relativePoint or point or "CENTER",
        },
        offset = { x = Round(x), y = Round(y) },
    }
end

local function GetDefaultPlacement()
    return ToLayoutPlacement("CENTER", "UIParent", "CENTER", -100, 0)
end

local function GetDB()
    return Monitor:GetDB()
end

local function NormalizeDB(db)
    if type(db) ~= "table" then db = DevourerTransform.defaults end

    db.devourerTransformEnabled = db.devourerTransformEnabled ~= false
    if not VALID_DISPLAY_MODES[db.devourerDisplayMode] then
        db.devourerDisplayMode = DISPLAY_MODE_ICON
    end
    db.devourerShowCountText = db.devourerShowCountText ~= false
    db.devourerEndedHideDelay = ClampNumber(db.devourerEndedHideDelay, 0, 30, DevourerTransform.defaults.devourerEndedHideDelay)
    db.devourerAlertSecond = ClampNumber(db.devourerAlertSecond, 1, 90, DevourerTransform.defaults.devourerAlertSecond)
    if db.devourerAlertSound ~= "none" and db.devourerAlertSound ~= "raidWarning" then
        db.devourerAlertSound = DevourerTransform.defaults.devourerAlertSound
    end
    if db.devourerAlertSoundModeMigrated ~= true then
        db.devourerAlertSoundMode = db.devourerAlertSound == "none" and "none" or "lsm"
        db.devourerAlertLSMSound = DevourerTransform.defaults.devourerAlertLSMSound
        db.devourerAlertSoundModeMigrated = true
    end
    if not VALID_ALERT_SOUND_MODES[db.devourerAlertSoundMode] then
        db.devourerAlertSoundMode = DevourerTransform.defaults.devourerAlertSoundMode
    end
    if type(db.devourerAlertLSMSound) ~= "string" or db.devourerAlertLSMSound == "" then
        db.devourerAlertLSMSound = DevourerTransform.defaults.devourerAlertLSMSound
    end
    if type(db.devourerAlertCustomPath) ~= "string" then
        db.devourerAlertCustomPath = DevourerTransform.defaults.devourerAlertCustomPath
    end
    if not VALID_SOUND_CHANNELS[db.devourerAlertChannel] then
        db.devourerAlertChannel = DevourerTransform.defaults.devourerAlertChannel
    end
    db.devourerIconSize = ClampNumber(db.devourerIconSize, 36, 96, DevourerTransform.defaults.devourerIconSize)
    db.devourerBarIconSize = ClampNumber(db.devourerBarIconSize, 24, 56, DevourerTransform.defaults.devourerBarIconSize)
    db.devourerBarWidth = ClampNumber(db.devourerBarWidth, 120, 360, DevourerTransform.defaults.devourerBarWidth)
    db.devourerBarHeight = ClampNumber(db.devourerBarHeight, 14, 44, DevourerTransform.defaults.devourerBarHeight)
    db.devourerTimerFontSize = ClampNumber(db.devourerTimerFontSize, 12, 48, DevourerTransform.defaults.devourerTimerFontSize)
    db.devourerCountFontSize = ClampNumber(db.devourerCountFontSize, 10, 36, DevourerTransform.defaults.devourerCountFontSize)
    if db.devourerGlowStyle == "soft" then
        db.devourerGlowStyle = "pulse"
    elseif not VALID_GLOW_STYLES[db.devourerGlowStyle] then
        db.devourerGlowStyle = DevourerTransform.defaults.devourerGlowStyle
    end
    db.devourerGlowSize = NormalizeGlowSizeValue(db.devourerGlowSize, DevourerTransform.defaults.devourerGlowSize)
    db.devourerGlowLines = Round(ClampNumber(db.devourerGlowLines, 1, 20, DevourerTransform.defaults.devourerGlowLines))
    db.devourerGlowThickness = Round(ClampNumber(db.devourerGlowThickness, 1, 20, DevourerTransform.defaults.devourerGlowThickness))
    db.devourerGlowLength = Round(ClampNumber(db.devourerGlowLength, 4, 80, DevourerTransform.defaults.devourerGlowLength))
    db.devourerGlowSpeed = ClampNumber(db.devourerGlowSpeed, 0, 3, DevourerTransform.defaults.devourerGlowSpeed)
    db.devourerGlowAlpha = ClampUnit(db.devourerGlowAlpha, DevourerTransform.defaults.devourerGlowAlpha)
    db.devourerGlowFalloff = ClampUnit(db.devourerGlowFalloff, DevourerTransform.defaults.devourerGlowFalloff)
    db.devourerGlowOffsetX = NormalizeGlowExpandValue(db.devourerGlowOffsetX, DevourerTransform.defaults.devourerGlowOffsetX)
    db.devourerGlowOffsetY = NormalizeGlowExpandValue(db.devourerGlowOffsetY, DevourerTransform.defaults.devourerGlowOffsetY)
    db.devourerGlowColor = NormalizeColorTable(db.devourerGlowColor, DevourerTransform.defaults.devourerGlowColor)
    return db
end

DevourerTransform.NormalizeDB = NormalizeDB

local function BuildGlowParams(db)
    db = NormalizeDB(db or GetDB())
    return {
        style = db.devourerGlowStyle,
        size = db.devourerGlowSize,
        lines = db.devourerGlowLines,
        thickness = db.devourerGlowThickness,
        length = db.devourerGlowLength,
        speed = db.devourerGlowSpeed,
        alpha = db.devourerGlowAlpha,
        falloff = db.devourerGlowFalloff,
        offsetX = db.devourerGlowOffsetX,
        offsetY = db.devourerGlowOffsetY,
        color = db.devourerGlowColor,
    }
end

local function ApplyGlowParams(glow, db)
    if glow and glow.SetGlowParams then
        glow:SetGlowParams(BuildGlowParams(db))
    end
end

local function GetSpellIcon()
    if SpellAPI and SpellAPI.GetTexture then
        return SpellAPI.GetTexture(TRANSFORM_BUFF_ID) or SpellAPI.GetTexture(SOUL_BOMB_SPELL_ID) or FALLBACK_ICON
    end
    return FALLBACK_ICON
end

local function IsApplicable()
    if not YUI.IsRetail then
        return false
    end

    local classToken = UnitAPI.GetClassToken and UnitAPI.GetClassToken("player")
    if classToken ~= "DEMONHUNTER" then
        return false
    end

    if not (TalentAPI.GetSpecialization and TalentAPI.GetSpecializationInfo) then
        return false
    end

    local specIndex = SafeNumber(TalentAPI.GetSpecialization())
    if not specIndex then
        return false
    end

    local specID = SafeNumber(TalentAPI.GetSpecializationInfo(specIndex))
    return specID == DEVOURER_SPEC_ID
end

local function SetFrameGroupVisible(group, visible)
    if not group then return end
    if visible then
        group:Show()
    else
        group:Hide()
    end
end

local function FormatElapsed(elapsed)
    return string.format("%.1f", math.max(0, tonumber(elapsed) or 0))
end

local function RefreshLayoutFrame()
    if YUI.Layout and YUI.Layout.RefreshFrame then
        YUI.Layout:RefreshFrame(LAYOUT_ID)
    end
end

local function IsLayoutEditing()
    return YUI.Layout and YUI.Layout.IsEditing and YUI.Layout:IsEditing()
end

local function CaptureSettingsPreviewPlacement(frame)
    if not frame or not UIParent or not frame.GetCenter or not UIParent.GetCenter then return nil end

    local frameX, frameY = frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if not frameX or not frameY or not parentX or not parentY then return nil end

    return ToLayoutPlacement("CENTER", "UIParent", "CENTER", frameX - parentX, frameY - parentY)
end

local function SaveSettingsPreviewPlacement(frame)
    if not (YUI.Layout and YUI.Layout.SetPlacement) then return end

    local placement = CaptureSettingsPreviewPlacement(frame)
    if placement and YUI.Layout:SetPlacement(LAYOUT_ID, placement, true) then
        RefreshLayoutFrame()
    end
end

local function CanDragSettingsPreview()
    if not settingsPreviewActive or layoutPreviewActive or IsLayoutEditing() then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    return true
end

local function SetSettingsPreviewDragEnabled(enabled)
    local frame = Widget.frame
    if not frame or not frame.EnableMouse then return end

    if enabled and settingsPreviewActive and not layoutPreviewActive and not IsLayoutEditing() then
        frame:EnableMouse(true)
        if frame.SetMovable then frame:SetMovable(true) end
        if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
    else
        if frame.StopMovingOrSizing then
            frame:StopMovingOrSizing()
        end
        frame:EnableMouse(false)
    end
end

local function OnSettingsPreviewDragStart(frame)
    if CanDragSettingsPreview() and frame and frame.StartMoving then
        frame:StartMoving()
    end
end

local function OnSettingsPreviewDragStop(frame)
    if frame and frame.StopMovingOrSizing then
        frame:StopMovingOrSizing()
    end

    if settingsPreviewActive and not layoutPreviewActive and not IsLayoutEditing() then
        SaveSettingsPreviewPlacement(frame)
    end
end

local function GetIconCountSlotHeight(db)
    db = NormalizeDB(db or activeDB or GetDB())
    return math.max(COUNT_SLOT_HEIGHT, Round((db.devourerCountFontSize or DevourerTransform.defaults.devourerCountFontSize) + 6))
end

local function GetBarCountSlotWidth(db)
    db = NormalizeDB(db or activeDB or GetDB())
    if db.devourerShowCountText ~= true then
        return 0
    end
    local fontSize = db.devourerCountFontSize or DevourerTransform.defaults.devourerCountFontSize
    return math.max(18, Round(fontSize * 1.35) + 8)
end

local function GetTextVisualMetrics(db)
    db = NormalizeDB(db or activeDB or GetDB())
    local timerFontSize = db.devourerTimerFontSize or DevourerTransform.defaults.devourerTimerFontSize
    local countFontSize = db.devourerCountFontSize or DevourerTransform.defaults.devourerCountFontSize
    local showCountSlot = db.devourerShowCountText == true
    local timerHeight = math.max(1, Round(timerFontSize + TEXT_SLOT_PADDING))
    local countHeight = showCountSlot and math.max(1, Round(countFontSize + TEXT_SLOT_PADDING)) or 0
    local gap = showCountSlot and TEXT_SLOT_GAP or 0
    local width = math.max(
        TEXT_MODE_MIN_WIDTH,
        Round(timerFontSize * 3.6) + TEXT_WIDTH_PADDING,
        showCountSlot and (Round(countFontSize * 3.2) + TEXT_WIDTH_PADDING) or 0
    )
    return width, countHeight + gap + timerHeight, countHeight, timerHeight, gap
end

local function GetVisualSize(db)
    db = NormalizeDB(db or activeDB or GetDB())
    local mode = db.devourerDisplayMode
    if mode == DISPLAY_MODE_ICON then
        local size = db.devourerIconSize
        return size, size + GetIconCountSlotHeight(db)
    elseif mode == DISPLAY_MODE_BAR then
        local barWidth = db.devourerBarWidth
        local barHeight = db.devourerBarHeight
        local countSlotWidth = GetBarCountSlotWidth(db)
        local countGap = countSlotWidth > 0 and BAR_COUNT_GAP or 0
        local countHeight = countSlotWidth > 0 and Round((db.devourerCountFontSize or 0) + 4) or barHeight
        local frameHeight = math.max(barHeight, countHeight)
        return countSlotWidth + countGap + barHeight + barWidth, frameHeight
    end
    local width, height = GetTextVisualMetrics(db)
    return width, height
end

local function EnsureLayoutPreviewState(db)
    db = NormalizeDB(db or activeDB or GetDB())
    if not (IsLayoutEditing() and not layoutPreviewSuppressed and featureActive and db.devourerTransformEnabled == true) then
        return false
    end

    if CancelEndedHide then
        CancelEndedHide()
    end
    local resetPreview = layoutPreviewActive ~= true
    layoutPreviewActive = true
    SetSettingsPreviewDragEnabled(false)
    State.active = false
    State.hasLast = true
    State.count = 2
    if StartPreviewUpdate then
        StartPreviewUpdate(db, resetPreview)
    else
        State.startTime = nil
        State.elapsed = 0
        State.alertTriggered = false
    end
    if Widget.frame then
        Widget.frame:Show()
    end
    return true
end

local function EnsureWidget()
    if Widget.frame then
        return Widget.frame
    end
    if not (GUI2 and GUI2.CreateFrame and GUI2.CreateText and GUI2.CreateIconSlot and GUI2.Data and GUI2.Data.CreateProgressBar and UIParent) then
        return nil
    end

    local frame = GUI2:CreateFrame(UIParent, {
        width = 96,
        height = 96,
        strata = "MEDIUM",
        clampedToScreen = true,
        movable = true,
        mouse = false,
        hidden = true,
    })
    if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
    if frame.SetScript then
        frame:SetScript("OnDragStart", OnSettingsPreviewDragStart)
        frame:SetScript("OnDragStop", OnSettingsPreviewDragStop)
    end
    Widget.frame = frame

    local iconGroup = GUI2:CreateFrame(frame, { allPoints = true, mouse = false })
    Widget.iconGroup = iconGroup

    local iconFrame = GUI2:CreateIconSlot(iconGroup, {
        size = 64,
        icon = GetSpellIcon(),
        shape = "square",
        padding = 0,
        animate = false,
    })
    Widget.iconFrame = iconFrame
    Widget.iconGlow = GUI2:CreateGlow(iconFrame, BuildGlowParams(activeDB or GetDB()))
    if Widget.iconGlow then Widget.iconGlow:Hide() end

    local iconTextLayer = GUI2:CreateFrame(iconGroup, { allPoints = true, mouse = false })
    if iconTextLayer.SetFrameLevel and iconFrame.GetFrameLevel then
        iconTextLayer:SetFrameLevel((iconFrame:GetFrameLevel() or 0) + 12)
    end
    Widget.iconTextLayer = iconTextLayer

    local iconCount = GUI2:CreateText(iconTextLayer, "", 20, "color.text.primary", "CENTER")
    SetTextColor(iconCount, DEFAULT_COUNT_COLOR)
    Widget.iconCount = iconCount

    local iconTimer = GUI2:CreateText(iconTextLayer, "", 28, "color.text.primary", "CENTER")
    iconTimer:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
    SetTextColor(iconTimer, DEFAULT_TIMER_COLOR)
    Widget.iconTimer = iconTimer
    local iconProgress = GUI2.Data:CreateProgressBar(iconFrame, {
        width = 64,
        height = 5,
        value = 0,
        fillColor = DEFAULT_BAR_COLOR,
    })
    Widget.iconProgress = iconProgress

    local barGroup = GUI2:CreateFrame(frame, { allPoints = true, mouse = false })
    Widget.barGroup = barGroup
    local barProgress = GUI2.Data:CreateProgressBar(barGroup, {
        width = 204,
        height = 24,
        value = 0,
        iconPosition = "left",
        icon = GetSpellIcon(),
        roundedIcon = false,
        collapseAdjacentBorder = true,
        fillColor = DEFAULT_BAR_COLOR,
    })
    Widget.barProgress = barProgress
    Widget.barGlow = GUI2:CreateGlow(barProgress, BuildGlowParams(activeDB or GetDB()))
    if Widget.barGlow then Widget.barGlow:Hide() end
    local barTextLayer = GUI2:CreateFrame(barGroup, { allPoints = true, mouse = false })
    if barTextLayer.SetFrameLevel and barProgress.GetFrameLevel then
        barTextLayer:SetFrameLevel((barProgress:GetFrameLevel() or 0) + 12)
    end
    Widget.barTextLayer = barTextLayer
    local barCount = GUI2:CreateText(barTextLayer, "", 18, "color.text.primary", "CENTER")
    SetTextColor(barCount, DEFAULT_COUNT_COLOR)
    Widget.barCount = barCount
    local barTimer = GUI2:CreateText(barTextLayer, "", 22, "color.text.primary", "RIGHT")
    SetTextColor(barTimer, DEFAULT_TIMER_COLOR)
    Widget.barTimer = barTimer

    local textGroup = GUI2:CreateFrame(frame, { allPoints = true, mouse = false })
    Widget.textGroup = textGroup
    local textCountSlot = GUI2:CreateFrame(textGroup, { width = 112, height = 30, mouse = false })
    Widget.textCountSlot = textCountSlot
    local textCount = GUI2:CreateText(textCountSlot, "", 20, "color.text.primary", "CENTER")
    textCount:SetPoint("CENTER", textCountSlot, "CENTER", 0, 0)
    SetTextColor(textCount, DEFAULT_COUNT_COLOR)
    Widget.textCount = textCount
    local textTimerSlot = GUI2:CreateFrame(textGroup, { width = 112, height = 24, mouse = false })
    Widget.textTimerSlot = textTimerSlot
    local textTimer = GUI2:CreateText(textTimerSlot, "", 32, "color.text.primary", "CENTER")
    textTimer:SetPoint("CENTER", textTimerSlot, "CENTER", 0, 0)
    SetTextColor(textTimer, DEFAULT_TIMER_COLOR)
    Widget.textTimer = textTimer

    if YUI.Layout and YUI.Layout.RegisterFrame then
        YUI.Layout:RegisterFrame(LAYOUT_ID, {
            frame = frame,
            title = T("layout.devourer_transform", "噬灭变身"),
            category = "component",
            defaultPlacement = GetDefaultPlacement,
            movable = true,
            snap = true,
            anchorTargets = { "UIParent" },
            minWidth = 36,
            minHeight = 36,
            getMoverBounds = function()
                return GetVisualSize(activeDB or GetDB())
            end,
            isEnabled = function()
                local db = activeDB or GetDB()
                return featureActive and NormalizeDB(db).devourerTransformEnabled == true
            end,
            openPluginSettings = function()
                if YUI.Settings and YUI.Settings.OpenComponentFeature then
                    YUI.Settings:OpenComponentFeature(FEATURE_KEY)
                    return true
                end
                return false
            end,
            onEnterEditMode = function()
                local db = NormalizeDB(activeDB or GetDB())
                layoutPreviewSuppressed = false
                SetSettingsPreviewDragEnabled(false)
                EnsureLayoutPreviewState(db)
                DevourerTransform:RefreshVisual(db)
            end,
            onHideEditModePreview = function()
                layoutPreviewSuppressed = true
                layoutPreviewActive = false
                SetSettingsPreviewDragEnabled(settingsPreviewActive)
                if not settingsPreviewActive then
                    if ResetRuntimeState then
                        ResetRuntimeState(true)
                    else
                        StopUpdate()
                    end
                end
                if RuntimeMonitor and RuntimeMonitor.active == true and RuntimeMonitor.context and StartTransform then
                    StartTransform(RuntimeMonitor.context)
                elseif settingsPreviewActive then
                    DevourerTransform:RefreshVisual(activeDB or GetDB())
                elseif Widget.frame then
                    Widget.frame:Hide()
                end
            end,
            onExitEditMode = function()
                layoutPreviewActive = false
                layoutPreviewSuppressed = false
                settingsPreviewActive = false
                SetSettingsPreviewDragEnabled(false)
                if ResetRuntimeState then
                    ResetRuntimeState(true)
                else
                    StopUpdate()
                end
                if RuntimeMonitor and RuntimeMonitor.active == true and RuntimeMonitor.context and StartTransform then
                    StartTransform(RuntimeMonitor.context)
                elseif Widget.frame then
                    Widget.frame:Hide()
                end
            end,
        })
    else
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -140)
    end

    DevourerTransform:ApplyAppearance(activeDB or GetDB())
    return frame
end

function DevourerTransform:ApplyAppearance(db)
    db = NormalizeDB(db or GetDB())
    activeDB = db

    local frame = EnsureWidget()
    if not frame then return end

    EnsureLayoutPreviewState(db)

    local mode = db.devourerDisplayMode
    SetFrameGroupVisible(Widget.iconGroup, mode == DISPLAY_MODE_ICON)
    SetFrameGroupVisible(Widget.barGroup, mode == DISPLAY_MODE_BAR)
    SetFrameGroupVisible(Widget.textGroup, mode == DISPLAY_MODE_TEXT)

    if mode == DISPLAY_MODE_ICON then
        local size = db.devourerIconSize
        local countSlotHeight = GetIconCountSlotHeight(db)
        frame:SetSize(size, size + countSlotHeight)
        Widget.iconFrame:SetSize(size, size)
        if Widget.iconTextLayer and Widget.iconTextLayer.SetFrameLevel and Widget.iconFrame.GetFrameLevel then
            Widget.iconTextLayer:SetFrameLevel((Widget.iconFrame:GetFrameLevel() or 0) + 12)
        end
        Widget.iconCount:ClearAllPoints()
        Widget.iconCount:SetPoint("BOTTOM", Widget.iconFrame, "TOP", 0, 2)
        Widget.iconCount:SetWidth(math.max(size + 24, 1))
        Widget.iconFrame:ClearAllPoints()
        Widget.iconFrame:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
        Widget.iconTimer:ClearAllPoints()
        Widget.iconTimer:SetPoint("CENTER", Widget.iconFrame, "CENTER", 0, 0)
        SetFontSize(Widget.iconTimer, db.devourerTimerFontSize, "OUTLINE")
        SetFontSize(Widget.iconCount, db.devourerCountFontSize, "OUTLINE")
        if Widget.iconProgress then
            Widget.iconProgress:ClearAllPoints()
            Widget.iconProgress:SetPoint("BOTTOMLEFT", Widget.iconFrame, "BOTTOMLEFT", 0, 0)
            Widget.iconProgress:SetPoint("BOTTOMRIGHT", Widget.iconFrame, "BOTTOMRIGHT", 0, 0)
            Widget.iconProgress:SetBarSize(size, 5)
        end
    elseif mode == DISPLAY_MODE_BAR then
        local barWidth = db.devourerBarWidth
        local barHeight = db.devourerBarHeight
        local iconSize = barHeight
        local countSlotWidth = GetBarCountSlotWidth(db)
        local countGap = countSlotWidth > 0 and BAR_COUNT_GAP or 0
        local countHeight = countSlotWidth > 0 and Round((db.devourerCountFontSize or 0) + 4) or barHeight
        local frameHeight = math.max(barHeight, countHeight)
        frame:SetSize(countSlotWidth + countGap + iconSize + barWidth, frameHeight)
        if Widget.barProgress then
            Widget.barProgress:ClearAllPoints()
            Widget.barProgress:SetPoint("LEFT", frame, "LEFT", countSlotWidth + countGap, 0)
            Widget.barProgress:SetBarSize(
                barWidth + iconSize,
                barHeight,
                iconSize
            )
        end
        if Widget.barTextLayer and Widget.barTextLayer.SetFrameLevel and Widget.barProgress and Widget.barProgress.GetFrameLevel then
            Widget.barTextLayer:SetFrameLevel((Widget.barProgress:GetFrameLevel() or 0) + 12)
        end
        Widget.barCount:ClearAllPoints()
        Widget.barCount:SetPoint("CENTER", frame, "LEFT", countSlotWidth / 2, 0)
        Widget.barCount:SetWidth(math.max(countSlotWidth, 1))
        Widget.barTimer:ClearAllPoints()
        Widget.barTimer:SetPoint("RIGHT", (Widget.barProgress and Widget.barProgress.track) or frame, "RIGHT", -8, 0)
        SetFontSize(Widget.barTimer, math.min(db.devourerTimerFontSize, barHeight + 8), "OUTLINE")
        SetFontSize(Widget.barCount, db.devourerCountFontSize, "OUTLINE")
    else
        local width, height, countHeight, timerHeight, gap = GetTextVisualMetrics(db)
        local showCountSlot = db.devourerShowCountText == true
        local textRoot = Widget.textGroup or frame
        frame:SetSize(width, height)
        if Widget.textCountSlot then
            Widget.textCountSlot:ClearAllPoints()
            Widget.textCountSlot:SetSize(width, math.max(countHeight, 1))
            if showCountSlot then
                Widget.textCountSlot:SetPoint("TOP", textRoot, "TOP", 0, 0)
                Widget.textCountSlot:Show()
            else
                Widget.textCountSlot:Hide()
            end
        end
        if Widget.textTimerSlot then
            Widget.textTimerSlot:ClearAllPoints()
            Widget.textTimerSlot:SetSize(width, timerHeight)
            if showCountSlot and Widget.textCountSlot then
                Widget.textTimerSlot:SetPoint("TOP", Widget.textCountSlot, "BOTTOM", 0, -gap)
            else
                Widget.textTimerSlot:SetPoint("CENTER", textRoot, "CENTER", 0, 0)
            end
            Widget.textTimerSlot:Show()
        end
        Widget.textCount:ClearAllPoints()
        Widget.textCount:SetPoint("CENTER", Widget.textCountSlot or textRoot, "CENTER", 0, 0)
        Widget.textCount:SetWidth(width)
        if Widget.textCount.SetHeight then Widget.textCount:SetHeight(math.max(countHeight, 1)) end
        Widget.textCount:SetJustifyH("CENTER")
        if Widget.textCount.SetWordWrap then Widget.textCount:SetWordWrap(false) end
        Widget.textTimer:ClearAllPoints()
        Widget.textTimer:SetPoint("CENTER", Widget.textTimerSlot or textRoot, "CENTER", 0, 0)
        Widget.textTimer:SetWidth(width)
        if Widget.textTimer.SetHeight then Widget.textTimer:SetHeight(timerHeight) end
        Widget.textTimer:SetJustifyH("CENTER")
        if Widget.textTimer.SetWordWrap then Widget.textTimer:SetWordWrap(false) end
        SetFontSize(Widget.textCount, db.devourerCountFontSize, "OUTLINE")
        SetFontSize(Widget.textTimer, db.devourerTimerFontSize, "OUTLINE")
    end

    ApplyGlowParams(Widget.iconGlow, db)
    ApplyGlowParams(Widget.barGlow, db)
    self:RefreshVisual(db)
    RefreshLayoutFrame()
end

local function ApplyTextValue(fontString, value, show)
    if not fontString then return end
    if show then
        fontString:SetText(value)
        fontString:Show()
    else
        fontString:SetText("")
        fontString:Hide()
    end
end

local function SetProgressBorderColor(progress, alerted)
    if not (progress and GUI2 and GUI2.SetBorderColor) then return end

    local function Apply(frame)
        if not frame then return end
        if alerted then
            GUI2:SetBorderColor(frame, DEFAULT_ALERT_COLOR[1], DEFAULT_ALERT_COLOR[2], DEFAULT_ALERT_COLOR[3], DEFAULT_ALERT_COLOR[4])
        else
            GUI2:SetBorderColor(frame, "color.border.default")
        end
    end

    Apply(progress.track)
    Apply(progress.icon)
end

function DevourerTransform:RefreshVisual(db)
    db = NormalizeDB(db or activeDB or GetDB())
    activeDB = db

    local frame = EnsureWidget()
    if not frame then return end

    if not (State.hasLast or State.active or settingsPreviewActive or layoutPreviewActive) then
        frame:Hide()
        return
    end

    local elapsed = State.elapsed or 0
    local alertSecond = db.devourerAlertSecond
    local alerted = State.alertTriggered == true
    local timerText = FormatElapsed(elapsed)
    local showCount = db.devourerShowCountText == true and (State.count or 0) > 0
    local countText = tostring(State.count or 0)
    local progress = alertSecond > 0 and math.min(1, math.max(0, elapsed / alertSecond)) or 0
    local alpha = (State.active or settingsPreviewActive or layoutPreviewActive) and 1 or 0.45

    frame:SetAlpha(alpha)
    frame:Show()
    SetSettingsPreviewDragEnabled(settingsPreviewActive)

    ApplyTextValue(Widget.iconCount, countText, showCount)
    ApplyTextValue(Widget.barCount, countText, showCount)
    ApplyTextValue(Widget.textCount, countText, showCount)

    if Widget.iconTimer then
        Widget.iconTimer:SetText(timerText)
        SetTextColor(Widget.iconTimer, DEFAULT_TIMER_COLOR)
    end
    if Widget.barTimer then
        Widget.barTimer:SetText(timerText)
        SetTextColor(Widget.barTimer, alerted and DEFAULT_ALERT_COLOR or DEFAULT_TIMER_COLOR)
    end
    if Widget.textTimer then
        Widget.textTimer:SetText(timerText)
        SetTextColor(Widget.textTimer, alerted and DEFAULT_ALERT_COLOR or DEFAULT_TIMER_COLOR)
    end

    if Widget.iconGlow and Widget.iconGlow.SetGlowShown then
        Widget.iconGlow:SetGlowShown(alerted)
    end
    if Widget.iconProgress then
        if alerted then
            Widget.iconProgress:Hide()
        else
            Widget.iconProgress:SetValue(progress)
            if Widget.iconProgress.SetFillColor then
                Widget.iconProgress:SetFillColor(DEFAULT_BAR_COLOR)
            end
            Widget.iconProgress:Show()
        end
    end
    if Widget.barProgress then
        Widget.barProgress:SetValue(progress)
        if Widget.barProgress.SetFillColor then
            Widget.barProgress:SetFillColor(alerted and DEFAULT_BAR_ALERT_COLOR or DEFAULT_BAR_COLOR)
        end
        SetProgressBorderColor(Widget.barProgress, alerted)
        Widget.barProgress:Show()
    end
    if Widget.barGlow and Widget.barGlow.SetGlowShown then
        Widget.barGlow:SetGlowShown(alerted)
    end
end

local function ResolveAlertSoundPath(db)
    db = NormalizeDB(db or activeDB or GetDB())
    if db.devourerAlertSoundMode == "custom" then
        local path = Trim(db.devourerAlertCustomPath)
        if path ~= "" then
            return path
        end
        return nil
    end

    if db.devourerAlertSoundMode == "lsm" and LSM and LSM.Fetch and db.devourerAlertLSMSound ~= "None" then
        local path = LSM:Fetch("sound", db.devourerAlertLSMSound, true)
        if path and path ~= 1 then
            return path
        end
    end
    return nil
end

local function PlaySoundPath(path, channel)
    if type(PlaySoundFile) ~= "function" or type(path) ~= "string" or path == "" then
        return false, "invalid-path"
    end
    channel = VALID_SOUND_CHANNELS[channel] and channel or DevourerTransform.defaults.devourerAlertChannel

    local ok, willPlay = pcall(PlaySoundFile, path, channel)
    local primaryWillPlay = ok and SafeBooleanValue(willPlay, nil) or nil
    if ok and primaryWillPlay ~= false then
        return true, "ok", channel
    end

    if channel ~= "Master" then
        local fallbackOk, fallbackWillPlay = pcall(PlaySoundFile, path, "Master")
        local fallbackCanPlay = fallbackOk and SafeBooleanValue(fallbackWillPlay, nil) or nil
        if fallbackOk and fallbackCanPlay ~= false then
            return true, "ok-master-fallback", "Master"
        end
    end
    return false, "play-failed", channel
end

local function PlayConfiguredSound(db, isTest)
    db = NormalizeDB(db or activeDB or GetDB())
    if db.devourerAlertSoundMode == "none" then
        if isTest and YUI.Print then
            YUI:Print(T("message.no_sound", "No sound selected."))
        end
        return false, "no-sound"
    end

    local path = ResolveAlertSoundPath(db)
    if not path then
        if isTest and YUI.Print then
            YUI:Print(T("message.no_sound", "No sound selected."))
        end
        return false, "no-sound-path"
    end

    local channel = VALID_SOUND_CHANNELS[db.devourerAlertChannel] and db.devourerAlertChannel or DevourerTransform.defaults.devourerAlertChannel
    local played, reason = PlaySoundPath(path, channel)
    if not played and isTest and YUI.Print then
        YUI:Print(T("message.sound_play_failed", "Sound playback failed."))
    end
    return played, reason
end

local function GetAuraElapsed(ctx)
    local trigger = ctx and ctx.t and ctx.t[1]
    local data = trigger and trigger.data
    if type(data) ~= "table" then return 0 end

    local elapsed = SafeNumber(data.elapsed)
    if elapsed then return elapsed end

    local duration = SafeNumber(data.duration)
    local remaining = SafeNumber(data.remaining)
    if duration and remaining then
        return math.max(0, duration - remaining)
    end

    return 0
end

StopUpdate = function()
    if Widget.frame and Widget.frame.SetScript then
        Widget.frame:SetScript("OnUpdate", nil)
    end
    State.updateElapsed = 0
end

local function IsPreviewActive()
    return settingsPreviewActive == true or layoutPreviewActive == true
end

local function GetPreviewStartElapsed(db)
    db = NormalizeDB(db or activeDB or GetDB())
    return math.max(0, (db.devourerAlertSecond or DevourerTransform.defaults.devourerAlertSecond) - PREVIEW_LEAD_SECONDS)
end

local function RefreshPreviewState(db)
    db = NormalizeDB(db or activeDB or GetDB())
    local alertSecond = math.max(1, db.devourerAlertSecond or DevourerTransform.defaults.devourerAlertSecond)
    local startTime = State.startTime or (GetNow() - GetPreviewStartElapsed(db))
    local elapsed = math.max(0, GetNow() - startTime)
    if elapsed > alertSecond then
        elapsed = alertSecond
    end
    local alerted = elapsed >= alertSecond

    State.active = false
    State.hasLast = true
    State.elapsed = elapsed
    if (State.count or 0) <= 0 then
        State.count = 2
    end
    State.alertTriggered = alerted
end

local function OnPreviewUpdate(_, elapsed)
    if not IsPreviewActive() then
        StopUpdate()
        return
    end

    State.updateElapsed = (State.updateElapsed or 0) + (elapsed or 0)
    if State.updateElapsed < UPDATE_INTERVAL then
        return
    end
    State.updateElapsed = 0

    local db = activeDB or GetDB()
    RefreshPreviewState(db)
    DevourerTransform:RefreshVisual(db)
end

StartPreviewUpdate = function(db, resetTimer)
    db = NormalizeDB(db or activeDB or GetDB())
    activeDB = db
    if resetTimer or not State.startTime or State.active then
        State.startTime = GetNow() - GetPreviewStartElapsed(db)
    end
    State.updateElapsed = 0
    RefreshPreviewState(db)
    if Widget.frame and Widget.frame.SetScript then
        Widget.frame:SetScript("OnUpdate", OnPreviewUpdate)
    end
end

CancelEndedHide = function()
    hideToken = hideToken + 1
    return hideToken
end

local ScheduleEndedHide

local function RefreshActiveState(ctx)
    if not State.active then
        return
    end

    State.elapsed = math.max(0, GetNow() - (State.startTime or GetNow()))
    local auraElapsed = GetAuraElapsed(ctx)
    if auraElapsed and auraElapsed > State.elapsed then
        State.elapsed = auraElapsed
    end
end

local function RefreshActiveTimer(ctx)
    if not State.active then
        return
    end

    RefreshActiveState(ctx)
    local db = activeDB or GetDB()
    DevourerTransform:RefreshVisual(db)
end

local function GetAlertSecondConditionValue()
    return NormalizeDB(activeDB or GetDB()).devourerAlertSecond
end

local function OnAlertCondition(ctx)
    if not (ctx and ctx.active and State.active) then
        return
    end
    if State.alertTriggered == true then
        return
    end
    State.alertTriggered = true
    PlayConfiguredSound(activeDB or GetDB())
    DevourerTransform:RefreshVisual(activeDB or GetDB())
end

StartTransform = function(ctx)
    CancelEndedHide()
    EnsureWidget()
    StopUpdate()
    local elapsed = GetAuraElapsed(ctx)
    State.active = true
    State.hasLast = true
    State.startTime = GetNow() - elapsed
    State.elapsed = elapsed
    State.count = 0
    State.alertTriggered = elapsed >= NormalizeDB(activeDB or GetDB()).devourerAlertSecond
    State.updateElapsed = 0
    DevourerTransform:RefreshVisual(activeDB or GetDB())
end

local function EndTransform()
    if State.active and State.startTime then
        State.elapsed = math.max(0, GetNow() - State.startTime)
    end
    State.active = false
    State.startTime = nil
    State.hasLast = State.hasLast == true
    if IsPreviewActive() and StartPreviewUpdate then
        StartPreviewUpdate(activeDB or GetDB(), true)
    else
        StopUpdate()
    end
    DevourerTransform:RefreshVisual(activeDB or GetDB())
    if ScheduleEndedHide then
        ScheduleEndedHide(activeDB or GetDB())
    end
end

ResetRuntimeState = function(hide)
    CancelEndedHide()
    State.active = false
    State.hasLast = false
    State.startTime = nil
    State.elapsed = 0
    State.count = 0
    State.alertTriggered = false
    StopUpdate()
    if hide and Widget.frame then
        Widget.frame:Hide()
    end
end

ScheduleEndedHide = function(db)
    db = NormalizeDB(db or activeDB or GetDB())
    local token = CancelEndedHide()
    local delay = db.devourerEndedHideDelay or DevourerTransform.defaults.devourerEndedHideDelay

    local function HideIfCurrent()
        if token ~= hideToken then return end
        if State.active or settingsPreviewActive or layoutPreviewActive then return end
        ResetRuntimeState(true)
    end

    if delay <= 0 then
        HideIfCurrent()
        return
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(delay, HideIfCurrent)
    else
        HideIfCurrent()
    end
end

local function OnMonitorTrigger(ctx, trigger)
    if not trigger or trigger.id ~= "soulBombCast" then
        return
    end

    if not (ctx and ctx.active and State.active) then
        return
    end

    State.count = (State.count or 0) + 1
    DevourerTransform:RefreshVisual(activeDB or GetDB())
end

local function EnsureRuntimeMonitor()
    if RuntimeMonitor then
        return RuntimeMonitor
    end

    CoreMonitor = CoreMonitor or YUI.Monitor
    if not (CoreMonitor and CoreMonitor.Register) then
        return nil
    end

    RuntimeMonitor = CoreMonitor:Register({
        id = "class_extra_monitor.devourer_transform",
        moduleId = MODULE_ID,
        owner = DevourerTransform,
        state = State,
        load = IsApplicable,
        activation = {
            expression = "t[1]",
            triggers = {
                {
                    id = "transformAura",
                    type = "playerAura",
                    unit = "player",
                    spellID = TRANSFORM_BUFF_ID,
                    icon = GetSpellIcon(),
                },
                {
                    id = "soulBombCast",
                    type = "event",
                    event = "UNIT_SPELLCAST_SUCCEEDED",
                    unit = "player",
                    spellID = SOUL_BOMB_SPELL_ID,
                },
            },
        },
        conditionRules = {
            {
                id = "devourerAlert",
                source = "context.state.elapsed",
                operator = "gte",
                value = GetAlertSecondConditionValue,
                fire = "onEnter",
                actions = {
                    { type = "callback", name = "devourerAlert" },
                },
            },
        },
        conditionActions = {
            devourerAlert = OnAlertCondition,
        },
        conditions = {
            onEnable = function()
                runtimeActive = true
            end,
            onDisable = function()
                runtimeActive = false
                if not settingsPreviewActive and not layoutPreviewActive then
                    ResetRuntimeState(true)
                end
            end,
            onActivate = function(ctx)
                StartTransform(ctx)
            end,
            onDeactivate = function()
                EndTransform()
            end,
            onTrigger = OnMonitorTrigger,
            beforeEvaluate = function(ctx)
                RefreshActiveState(ctx)
            end,
            onUpdate = function(ctx)
                RefreshActiveTimer(ctx)
            end,
        },
        update = {
            interval = UPDATE_INTERVAL,
            activeOnly = true,
        },
        appearance = {
            presenter = {
                ensure = function()
                    EnsureWidget()
                end,
                apply = function()
                    DevourerTransform:ApplyAppearance(activeDB or GetDB())
                end,
                update = function()
                    DevourerTransform:RefreshVisual(activeDB or GetDB())
                end,
                show = function()
                    if Widget.frame then Widget.frame:Show() end
                end,
                hide = function()
                    if Widget.frame then Widget.frame:Hide() end
                end,
                destroy = function()
                    ResetRuntimeState(true)
                end,
            },
        },
    })

    return RuntimeMonitor
end

function DevourerTransform:RefreshRuntime(db)
    db = NormalizeDB(db or GetDB())
    activeDB = db
    self:ApplyAppearance(db)

    local shouldRun = featureActive and db.devourerTransformEnabled == true
    local monitor = EnsureRuntimeMonitor()
    if not monitor then
        runtimeActive = false
        if not settingsPreviewActive and not layoutPreviewActive then
            ResetRuntimeState(true)
        end
        return
    end

    runtimeActive = monitor:SetEnabled(shouldRun) == true
    if not shouldRun and not settingsPreviewActive and not layoutPreviewActive then
        ResetRuntimeState(true)
    elseif shouldRun and not runtimeActive and not settingsPreviewActive and not layoutPreviewActive then
        ResetRuntimeState(true)
    end
end

function DevourerTransform:OnFeatureToggle(enable, db)
    featureActive = enable == true
    if featureActive then
        self:RefreshRuntime(db or GetDB())
    else
        runtimeActive = false
        settingsPreviewActive = false
        layoutPreviewActive = false
        layoutPreviewSuppressed = false
        SetSettingsPreviewDragEnabled(false)
        if RuntimeMonitor then
            RuntimeMonitor:SetEnabled(false)
        end
        ResetRuntimeState(true)
    end
end

local function StartSettingsPreview()
    CancelEndedHide()
    settingsPreviewActive = true
    local db = NormalizeDB(activeDB or GetDB())
    EnsureWidget()
    State.count = 2
    StartPreviewUpdate(db, true)
    SetSettingsPreviewDragEnabled(true)
    DevourerTransform:RefreshVisual(db)
end

local function StopSettingsPreview()
    settingsPreviewActive = false
    SetSettingsPreviewDragEnabled(false)
    if runtimeActive then
        if layoutPreviewActive then
            if StartPreviewUpdate then
                StartPreviewUpdate(activeDB or GetDB(), false)
            end
            DevourerTransform:RefreshVisual(activeDB or GetDB())
            return
        end
        ResetRuntimeState(true)
        if RuntimeMonitor then
            RuntimeMonitor:Refresh("preview-stop")
        end
    elseif not layoutPreviewActive then
        ResetRuntimeState(true)
    end
end

local function ToggleSettingsPreview(button)
    if settingsPreviewActive then
        StopSettingsPreview()
    else
        StartSettingsPreview()
    end
    if button and button.SetText then
        button:SetText(settingsPreviewActive and T("settings.preview_stop", "关闭预览") or T("settings.preview", "预览"))
    end
end

function DevourerTransform:OnSettingsLeave()
    StopSettingsPreview()
end

local function BuildDisplayModeOptions()
    return {
        { text = T("settings.display_mode_icon", "图标"), value = DISPLAY_MODE_ICON },
        { text = T("settings.display_mode_bar", "进度条"), value = DISPLAY_MODE_BAR },
        { text = T("settings.display_mode_text", "文字"), value = DISPLAY_MODE_TEXT },
    }
end

local function BuildGlowStyleOptions()
    return {
        { text = T("settings.glow_style_none", "无"), value = "none" },
        { text = T("settings.glow_style_pixel", "像素线段"), value = "pixel" },
        { text = T("settings.glow_style_button", "按钮发光"), value = "button" },
        { text = T("settings.glow_style_autocast", "自动施法"), value = "autocast" },
        { text = T("settings.glow_style_proc", "触发发光"), value = "proc" },
        { text = T("settings.glow_style_pulse", "脉冲发光"), value = "pulse" },
    }
end

local function BuildGlowOptionsValue(db)
    db = NormalizeDB(db or GetDB())
    return {
        style = db.devourerGlowStyle,
        size = db.devourerGlowSize,
        lines = db.devourerGlowLines,
        thickness = db.devourerGlowThickness,
        length = db.devourerGlowLength,
        speed = db.devourerGlowSpeed,
        alpha = db.devourerGlowAlpha,
        falloff = db.devourerGlowFalloff,
        offsetX = db.devourerGlowOffsetX,
        offsetY = db.devourerGlowOffsetY,
        color = db.devourerGlowColor,
    }
end

local function BuildGlowDefaultsByStyle()
    return {
        pixel = {
            style = "pixel",
            lines = 8,
            thickness = 2,
            length = 20,
            speed = 0.25,
            alpha = 0.90,
            falloff = 0.30,
            offsetX = 0,
            offsetY = 0,
            color = DEFAULT_GLOW_COLOR,
        },
        button = {
            style = "button",
            size = 1.00,
            speed = 0.25,
            alpha = 0.90,
            offsetX = 0,
            offsetY = 0,
            color = DEFAULT_GLOW_COLOR,
        },
        autocast = {
            style = "autocast",
            size = 1.00,
            lines = 8,
            speed = 0.25,
            alpha = 0.90,
            offsetX = 0,
            offsetY = 0,
            color = DEFAULT_GLOW_COLOR,
        },
        proc = {
            style = "proc",
            size = 1.00,
            speed = 0.25,
            alpha = 0.90,
            offsetX = 0,
            offsetY = 0,
            color = DEFAULT_GLOW_COLOR,
        },
        pulse = {
            style = "pulse",
            size = 1.00,
            speed = 0.25,
            alpha = 0.90,
            offsetX = 0,
            offsetY = 0,
            color = DEFAULT_GLOW_COLOR,
        },
    }
end

local function ApplyGlowOptionsValue(db, value)
    db = NormalizeDB(db or GetDB())
    value = type(value) == "table" and value or {}
    local style = value.style == "soft" and "pulse" or value.style
    db.devourerGlowStyle = VALID_GLOW_STYLES[style] and style or DevourerTransform.defaults.devourerGlowStyle
    db.devourerGlowSize = NormalizeGlowSizeValue(value.size, DevourerTransform.defaults.devourerGlowSize)
    db.devourerGlowLines = Round(ClampNumber(value.lines, 1, 20, DevourerTransform.defaults.devourerGlowLines))
    db.devourerGlowThickness = Round(ClampNumber(value.thickness, 1, 20, DevourerTransform.defaults.devourerGlowThickness))
    db.devourerGlowLength = Round(ClampNumber(value.length, 4, 80, DevourerTransform.defaults.devourerGlowLength))
    db.devourerGlowSpeed = ClampNumber(value.speed, 0, 3, DevourerTransform.defaults.devourerGlowSpeed)
    db.devourerGlowAlpha = ClampUnit(value.alpha, DevourerTransform.defaults.devourerGlowAlpha)
    db.devourerGlowFalloff = ClampUnit(value.falloff, DevourerTransform.defaults.devourerGlowFalloff)
    db.devourerGlowOffsetX = NormalizeGlowExpandValue(value.offsetX, DevourerTransform.defaults.devourerGlowOffsetX)
    db.devourerGlowOffsetY = NormalizeGlowExpandValue(value.offsetY, DevourerTransform.defaults.devourerGlowOffsetY)
    db.devourerGlowColor = NormalizeColorTable(value.color, DevourerTransform.defaults.devourerGlowColor)
    DevourerTransform:ApplyAppearance(db)
end

local function BuildGlowControlLabels()
    return {
        type = T("settings.glow_type", "类型"),
        expand = T("settings.glow_params", "参数"),
        collapse = T("settings.glow_params", "参数"),
        params = T("settings.glow_params", "参数"),
        paramsDetail = T("settings.glow_params_detail", "参数详情"),
        noParams = T("settings.glow_no_params", "无可设置参数"),
        none = T("settings.glow_style_none", "无"),
        noneSummary = T("settings.glow_style_none", "无"),
        color = T("settings.glow_color", "发光颜色"),
        size = T("settings.glow_size", "发光尺寸"),
        lines = T("settings.glow_lines", "线段数量"),
        thickness = T("settings.glow_thickness", "线段粗细"),
        length = T("settings.glow_length", "线段长度"),
        speed = T("settings.glow_speed", "旋转速度"),
        alpha = T("settings.glow_alpha", "发光透明"),
        falloff = T("settings.glow_falloff", "外圈衰减"),
        offsetX = T("settings.glow_offset_x", "X 扩展"),
        offsetY = T("settings.glow_offset_y", "Y 扩展"),
        reset = T("settings.glow_reset", "重置"),
        summaryLines = T("settings.glow_summary_lines", "线"),
        summaryThickness = T("settings.glow_summary_thickness", "宽"),
        summaryLength = T("settings.glow_summary_length", "长"),
        summarySpeed = T("settings.glow_summary_speed", "速"),
        summarySize = T("settings.glow_summary_size", "尺寸"),
        summaryAlpha = T("settings.glow_summary_alpha", "透明"),
        summaryOffset = T("settings.glow_summary_offset", "扩展"),
        summaryColor = T("settings.glow_summary_color", "色"),
    }
end

local function RefreshSettingsModule()
    local feature = YUI.Components and YUI.Components.features and YUI.Components.features[FEATURE_KEY]
    if feature and feature.RefreshCurrentModule then
        feature.RefreshCurrentModule()
    end
end

local function BuildAlertSoundModeOptions()
    return {
        { text = T("settings.alert_sound_lsm", "音频库"), value = "lsm" },
        { text = T("settings.alert_sound_custom", "自定义路径"), value = "custom" },
        { text = T("settings.alert_sound_none", "不播放"), value = "none" },
    }
end

local function BuildSoundChannelOptions()
    return {
        { text = T("settings.channel_master", "主声道"), value = "Master" },
        { text = T("settings.channel_sfx", "音效"), value = "SFX" },
        { text = T("settings.channel_dialog", "对话"), value = "Dialog" },
        { text = T("settings.channel_music", "音乐"), value = "Music" },
        { text = T("settings.channel_ambience", "环境"), value = "Ambience" },
    }
end

local function ShowSoundPreviewFailure(_, reason)
    if not YUI.Print then return end
    if reason == "invalid-path" then
        YUI:Print(T("message.no_sound", "No sound selected."))
    elseif reason == "play-failed" then
        YUI:Print(T("message.sound_play_failed", "Sound playback failed."))
    end
end

local function CreateCustomSoundPathControl(parent, item)
    if not (GUI2 and GUI2.CreateFrame and GUI2.Form and GUI2.Form.CreateEditBox and GUI2.Form.CreateSoundPreviewButton) then
        return nil
    end

    local width = item.width or BODY_WIDTH
    local height = item.height or 26
    local buttonSize = item.previewButtonSize or height
    local buttonGap = item.previewButtonGap or 8
    local editWidth = math.max(width - buttonSize - buttonGap, 1)
    local frame = GUI2:CreateFrame(parent, {
        width = width,
        height = height,
    })

    local editbox = GUI2.Form:CreateEditBox(frame, {
        width = editWidth,
        get = item.get,
        set = item.set,
    })
    editbox:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame.editbox = editbox

    local previewButton = GUI2.Form:CreateSoundPreviewButton(frame, {
        size = buttonSize,
        tooltip = T("settings.preview_sound", "试听"),
        getPath = function()
            if editbox.ClearFocus then
                editbox:ClearFocus()
            end
            local path = item.get and item.get() or editbox:GetText()
            return Trim(path)
        end,
        getChannel = item.getChannel,
        getToken = function(_, path)
            return "devourer:custom-sound:" .. tostring(path or "")
        end,
        onPreviewFailed = ShowSoundPreviewFailure,
    })
    previewButton:SetPoint("LEFT", editbox, "RIGHT", buttonGap, 0)
    frame.previewButton = previewButton

    function frame:GetValue()
        return self.editbox and self.editbox.GetValue and self.editbox:GetValue() or ""
    end
    function frame:SetValue(value, silent)
        if self.editbox and self.editbox.SetValue then
            self.editbox:SetValue(value, silent)
        end
    end
    function frame:SetDisabled(disabled)
        self.gui2Disabled = disabled and true or false
        if self.editbox and self.editbox.SetDisabled then
            self.editbox:SetDisabled(self.gui2Disabled)
        end
        if self.previewButton and self.previewButton.SetDisabled then
            self.previewButton:SetDisabled(self.gui2Disabled)
        end
    end
    function frame:RefreshTheme()
        if self.editbox and self.editbox.RefreshTheme then
            self.editbox:RefreshTheme()
        end
        if self.previewButton and self.previewButton.RefreshTheme then
            self.previewButton:RefreshTheme()
        end
    end

    return frame
end

local function AddAlignedFieldGroup(options, label, fields, layout)
    layout = type(layout) == "table" and layout or {}
    if layout.divider ~= false then
        options[#options + 1] = { type = "divider", label = label, alignLeft = true, width = SECTION_WIDTH }
    end
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

function DevourerTransform:BuildOptions(db)
    db = NormalizeDB(db or GetDB())

    local options = {}
    if Monitor.AppendIconDivider then
        Monitor:AppendIconDivider(options, T("settings.devourer_basic", "噬灭变身"), GetSpellIcon, SECTION_WIDTH)
    else
        options[#options + 1] = { type = "divider", label = T("settings.devourer_basic", "噬灭变身"), alignLeft = true, width = SECTION_WIDTH }
    end
    AddAlignedFieldGroup(options, T("settings.devourer_basic", "噬灭变身"), {
        {
            type = "checkbox",
            label = T("settings.devourer_enabled", "启用监控"),
            settingsToggle = "devourerTransform",
            searchKey = "settings.devourer_enabled",
            get = function() return db.devourerTransformEnabled == true end,
            set = function(value)
                db.devourerTransformEnabled = value == true
                DevourerTransform:RefreshRuntime(db)
            end,
        },
        {
            type = "button",
            label = "",
            text = settingsPreviewActive and T("settings.preview_stop", "关闭预览") or T("settings.preview", "预览"),
            bodyWidth = 132,
            onClick = ToggleSettingsPreview,
        },
        {
            type = "dropdown",
            label = T("settings.display_mode", "显示模式"),
            layoutPreset = "inlineSelector",
            options = BuildDisplayModeOptions,
            default = DISPLAY_MODE_ICON,
            get = function() return db.devourerDisplayMode end,
            set = function(value)
                db.devourerDisplayMode = VALID_DISPLAY_MODES[value] and value or DISPLAY_MODE_ICON
                DevourerTransform:ApplyAppearance(db)
            end,
        },
        {
            type = "checkbox",
            label = T("settings.show_count_text", "显示次数"),
            get = function() return db.devourerShowCountText == true end,
            set = function(value)
                db.devourerShowCountText = value == true
                DevourerTransform:ApplyAppearance(db)
            end,
        },
        {
            type = "slider",
            label = T("settings.ended_hide_delay", "结束隐藏延迟"),
            min = 0,
            max = 30,
            step = 0.5,
            get = function() return db.devourerEndedHideDelay end,
            set = function(value)
                db.devourerEndedHideDelay = ClampNumber(value, 0, 30, DevourerTransform.defaults.devourerEndedHideDelay)
                DevourerTransform:RefreshVisual(db)
            end,
        },
    }, { divider = false })

    AddAlignedFieldGroup(options, T("settings.alert", "声音提醒"), {
        {
            type = "dropdown",
            label = T("settings.alert_sound", "播放类型"),
            options = BuildAlertSoundModeOptions,
            default = DevourerTransform.defaults.devourerAlertSoundMode,
            get = function() return db.devourerAlertSoundMode end,
            set = function(value)
                db.devourerAlertSoundMode = VALID_ALERT_SOUND_MODES[value] and value or DevourerTransform.defaults.devourerAlertSoundMode
                RefreshSettingsModule()
            end,
        },
        {
            type = "slider",
            requires = function() return db.devourerAlertSoundMode ~= "none" end,
            label = T("settings.alert_second", "变身几秒播放"),
            min = 1,
            max = 90,
            step = 1,
            get = function() return db.devourerAlertSecond end,
            set = function(value)
                db.devourerAlertSecond = ClampNumber(value, 1, 90, DevourerTransform.defaults.devourerAlertSecond)
                DevourerTransform:RefreshVisual(db)
            end,
        },
        {
            type = "sound",
            requires = function() return db.devourerAlertSoundMode == "lsm" end,
            span = "full",
            label = T("settings.alert_lsm_sound", "选择音频"),
            default = DevourerTransform.defaults.devourerAlertLSMSound,
            noneText = T("settings.alert_lsm_sound_none", "未选择"),
            previewTooltip = T("settings.preview_sound", "试听"),
            getChannel = function() return db.devourerAlertChannel end,
            onPreviewFailed = ShowSoundPreviewFailure,
            get = function() return db.devourerAlertLSMSound end,
            set = function(value)
                db.devourerAlertLSMSound = type(value) == "string" and value or DevourerTransform.defaults.devourerAlertLSMSound
            end,
        },
        {
            type = "custom",
            requires = function() return db.devourerAlertSoundMode == "custom" end,
            span = "full",
            label = T("settings.alert_custom_path", "自定义音频路径"),
            getChannel = function() return db.devourerAlertChannel end,
            get = function() return db.devourerAlertCustomPath end,
            set = function(value)
                db.devourerAlertCustomPath = type(value) == "string" and value or ""
            end,
            render = CreateCustomSoundPathControl,
        },
        {
            type = "dropdown",
            requires = function() return db.devourerAlertSoundMode ~= "none" end,
            label = T("settings.alert_channel", "声道"),
            options = BuildSoundChannelOptions,
            default = DevourerTransform.defaults.devourerAlertChannel,
            get = function() return db.devourerAlertChannel end,
            set = function(value)
                db.devourerAlertChannel = VALID_SOUND_CHANNELS[value] and value or DevourerTransform.defaults.devourerAlertChannel
            end,
        },
    })

    AddAlignedFieldGroup(options, T("settings.appearance", "外观"), {
        {
            type = "slider",
            label = T("settings.icon_size", "图标尺寸"),
            min = 36,
            max = 96,
            step = 1,
            get = function() return db.devourerIconSize end,
            set = function(value)
                db.devourerIconSize = ClampNumber(value, 36, 96, DevourerTransform.defaults.devourerIconSize)
                DevourerTransform:ApplyAppearance(db)
            end,
        },
        {
            type = "slider",
            label = T("settings.bar_width", "条宽度"),
            min = 120,
            max = 360,
            step = 1,
            get = function() return db.devourerBarWidth end,
            set = function(value)
                db.devourerBarWidth = ClampNumber(value, 120, 360, DevourerTransform.defaults.devourerBarWidth)
                DevourerTransform:ApplyAppearance(db)
            end,
        },
        {
            type = "slider",
            label = T("settings.bar_height", "条高度"),
            min = 14,
            max = 44,
            step = 1,
            get = function() return db.devourerBarHeight end,
            set = function(value)
                db.devourerBarHeight = ClampNumber(value, 14, 44, DevourerTransform.defaults.devourerBarHeight)
                DevourerTransform:ApplyAppearance(db)
            end,
        },
        {
            type = "slider",
            label = T("settings.timer_font_size", "秒数字号"),
            min = 12,
            max = 48,
            step = 1,
            get = function() return db.devourerTimerFontSize end,
            set = function(value)
                db.devourerTimerFontSize = ClampNumber(value, 12, 48, DevourerTransform.defaults.devourerTimerFontSize)
                DevourerTransform:ApplyAppearance(db)
            end,
        },
        {
            type = "slider",
            label = T("settings.count_font_size", "次数字号"),
            min = 10,
            max = 36,
            step = 1,
            get = function() return db.devourerCountFontSize end,
            set = function(value)
                db.devourerCountFontSize = ClampNumber(value, 10, 36, DevourerTransform.defaults.devourerCountFontSize)
                DevourerTransform:ApplyAppearance(db)
            end,
        },
    })

    options[#options + 1] = { type = "divider", label = T("settings.glow", "发光"), alignLeft = true, width = SECTION_WIDTH }
    options[#options + 1] = {
        type = "glow",
        label = T("settings.glow", "发光"),
        rowWidth = SECTION_WIDTH,
        width = BODY_WIDTH,
        controlWidth = BODY_WIDTH,
        panelWidth = SECTION_WIDTH - LABEL_WIDTH - LABEL_GAP,
        labelWidth = LABEL_WIDTH,
        gap = LABEL_GAP,
        inputWidth = INPUT_WIDTH,
        styleOptions = BuildGlowStyleOptions,
        labels = BuildGlowControlLabels(),
        default = BuildGlowOptionsValue(DevourerTransform.defaults),
        defaultsByStyle = BuildGlowDefaultsByStyle,
        applyStyleDefaultsOnChange = true,
        get = function()
            return BuildGlowOptionsValue(db)
        end,
        set = function(value)
            ApplyGlowOptionsValue(db, value)
        end,
        getExpanded = function()
            return glowOptionsExpanded == true
        end,
        setExpanded = function(value)
            glowOptionsExpanded = value == true
        end,
        onRequestRefresh = RefreshSettingsModule,
    }

    return options
end

Monitor.DevourerTransform = DevourerTransform
Monitor:RegisterSubFeature(DevourerTransform)
