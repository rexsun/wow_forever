local YUI = _G.YUI
if not YUI then return end

local Monitor = YUI.ClassExtraMonitor
if not (Monitor and Monitor.RegisterSubFeature) then return end

local GUI2 = YUI.GUI2
local CoreMonitor
local UnitAPI = (YUI.API and YUI.API.Unit) or YUI.WOW_API or {}
local SpellAPI = (YUI.API and YUI.API.Spell) or YUI.WOW_API or {}
local TalentAPI = (YUI.API and YUI.API.Talent) or YUI.WOW_API or {}
local SecurityAPI = (YUI.API and YUI.API.Security) or YUI.WOW_API or {}
local L = Monitor.L or (YUI.Locale and YUI.Locale:Get("ClassExtraMonitor")) or nil

local FEATURE_KEY = Monitor.FEATURE_KEY or "ClassExtraMonitor"
local MODULE_ID = "component:" .. FEATURE_KEY .. ":BrewmasterElixir"
local MONITOR_ID = "class_extra_monitor.brewmaster_elixir"
local LAYOUT_ID = "yui.component.class_extra_monitor.brewmaster_elixir_icon"

local BREWMASTER_SPEC_ID = 268
local MONK_CLASS_TOKEN = "MONK"
local WISE_ELIXIR_SPELL_ID = 455139
local ELIXIR_COOLDOWN_SPELL_ID = 455180
local ELIXIR_FALLBACK_ICON = "Interface\\Icons\\INV_10_Alchemy2_Elixir_Color4"
local ELIXIR_TRIGGER_COOLDOWN = 15

local DEFAULT_ICON_SIZE = 42
local DEFAULT_FONT_SIZE = 24
local DEFAULT_TEXT_COLOR = { 1, 1, 1, 1 }
local DEFAULT_GLOW_COLOR = { 0.35, 0.78, 1, 1 }

local READY_MODE_GLOW = "glow"
local READY_MODE_DESATURATE = "desaturate"
local READY_MODE_NORMAL = "normal"
local VALID_READY_MODES = {
    glow = true,
    desaturate = true,
    normal = true,
}

local DISPLAY_MODE_ALWAYS = "always"
local DISPLAY_MODE_COMBAT = "combat"
local DISPLAY_MODE_INSTANCE = "instance"
local VALID_DISPLAY_MODES = {
    always = true,
    combat = true,
    instance = true,
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

local SECTION_WIDTH = 620
local LABEL_WIDTH = 112
local LABEL_GAP = 10
local INPUT_WIDTH = 56
local VALUE_GAP = 10
local COLUMN_GAP = 24
local COLUMN_WIDTH = math.floor((SECTION_WIDTH - COLUMN_GAP) / 2)
local BODY_WIDTH = COLUMN_WIDTH - LABEL_WIDTH - LABEL_GAP

local BrewmasterElixir = {
    id = "brewmasterElixir",
    labelKey = "settings.tab_brewmaster_elixir",
    label = "明志灵药",
    specID = BREWMASTER_SPEC_ID,
    classFile = MONK_CLASS_TOKEN,
    order = 20,
}

BrewmasterElixir.defaults = {
    brewmasterElixirEnabled = true,
    brewmasterElixirHideOutOfCombat = true,
    brewmasterElixirDisplayMode = DISPLAY_MODE_COMBAT,
    brewmasterElixirReadyMode = READY_MODE_GLOW,
    brewmasterElixirReadyGlowEnabled = true,
    brewmasterElixirIconSize = DEFAULT_ICON_SIZE,
    brewmasterElixirFontSize = DEFAULT_FONT_SIZE,
    brewmasterElixirGlowStyle = "pixel",
    brewmasterElixirGlowSize = 1.00,
    brewmasterElixirGlowLines = 8,
    brewmasterElixirGlowThickness = 2,
    brewmasterElixirGlowLength = 20,
    brewmasterElixirGlowSpeed = 0.25,
    brewmasterElixirGlowAlpha = 0.90,
    brewmasterElixirGlowFalloff = 0.30,
    brewmasterElixirGlowOffsetX = 0,
    brewmasterElixirGlowOffsetY = 0,
    brewmasterElixirGlowColor = DEFAULT_GLOW_COLOR,
}

local Widget = {}
local RuntimeMonitor
local featureActive = false
local runtimeActive = false
local settingsPreviewActive = false
local layoutPreviewActive = false
local layoutPreviewSuppressed = false
local activeDB
local layoutRegistered = false
local previewButton
local glowOptionsExpanded = false

local ElixirState = {
    lastRemaining = nil,
}

local RefreshRuntime

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
    if value == nil then value = fallback or BrewmasterElixir.defaults.brewmasterElixirGlowSize end
    if value > 5 then
        value = value / 10
    end
    return ClampNumber(value, 0.25, 5, BrewmasterElixir.defaults.brewmasterElixirGlowSize)
end

local function NormalizeGlowExpandValue(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback or 0 end
    if value > 1 or value < -1 then
        value = value / 24
    end
    return ClampNumber(value, -1, 1, 0)
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

local function SafeNumberFromCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then return nil end
    return SafeNumber(value)
end

local function SafeBooleanFromCall(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, ...)
    return ok and value == true
end

local function SafeString(value)
    if value == nil or IsSecretValue(value) then return nil end
    return tostring(value)
end

local function GetColorComponents(value, fallback)
    fallback = fallback or DEFAULT_TEXT_COLOR
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

local function GetDB()
    return Monitor:GetDB()
end

local function NormalizeDB(db)
    if type(db) ~= "table" then db = BrewmasterElixir.defaults end

    db.brewmasterElixirEnabled = db.brewmasterElixirEnabled ~= false
    if not VALID_READY_MODES[db.brewmasterElixirReadyMode] then
        db.brewmasterElixirReadyMode = BrewmasterElixir.defaults.brewmasterElixirReadyMode
    end
    if not VALID_DISPLAY_MODES[db.brewmasterElixirDisplayMode] then
        db.brewmasterElixirDisplayMode = db.brewmasterElixirHideOutOfCombat == true and DISPLAY_MODE_COMBAT or BrewmasterElixir.defaults.brewmasterElixirDisplayMode
    end
    db.brewmasterElixirHideOutOfCombat = db.brewmasterElixirDisplayMode == DISPLAY_MODE_COMBAT
    if db.brewmasterElixirReadyGlowEnabled == nil then
        db.brewmasterElixirReadyGlowEnabled = db.brewmasterElixirReadyMode == READY_MODE_GLOW
    else
        db.brewmasterElixirReadyGlowEnabled = db.brewmasterElixirReadyGlowEnabled == true
    end
    db.brewmasterElixirIconSize = ClampNumber(db.brewmasterElixirIconSize, 28, 96, BrewmasterElixir.defaults.brewmasterElixirIconSize)
    db.brewmasterElixirFontSize = ClampNumber(db.brewmasterElixirFontSize, 10, 36, BrewmasterElixir.defaults.brewmasterElixirFontSize)

    if db.brewmasterElixirGlowStyle == nil and db.brewmasterElixirGlowEnabled == false then
        db.brewmasterElixirGlowStyle = "none"
    elseif db.brewmasterElixirGlowStyle == "soft" then
        db.brewmasterElixirGlowStyle = "pulse"
    elseif not VALID_GLOW_STYLES[db.brewmasterElixirGlowStyle] then
        db.brewmasterElixirGlowStyle = BrewmasterElixir.defaults.brewmasterElixirGlowStyle
    end
    db.brewmasterElixirGlowSize = NormalizeGlowSizeValue(db.brewmasterElixirGlowSize, BrewmasterElixir.defaults.brewmasterElixirGlowSize)
    db.brewmasterElixirGlowLines = Round(ClampNumber(db.brewmasterElixirGlowLines, 1, 20, BrewmasterElixir.defaults.brewmasterElixirGlowLines))
    db.brewmasterElixirGlowThickness = Round(ClampNumber(db.brewmasterElixirGlowThickness, 1, 20, BrewmasterElixir.defaults.brewmasterElixirGlowThickness))
    db.brewmasterElixirGlowLength = Round(ClampNumber(db.brewmasterElixirGlowLength, 4, 80, BrewmasterElixir.defaults.brewmasterElixirGlowLength))
    db.brewmasterElixirGlowSpeed = ClampNumber(db.brewmasterElixirGlowSpeed, 0, 3, BrewmasterElixir.defaults.brewmasterElixirGlowSpeed)
    db.brewmasterElixirGlowAlpha = ClampUnit(db.brewmasterElixirGlowAlpha, BrewmasterElixir.defaults.brewmasterElixirGlowAlpha)
    db.brewmasterElixirGlowFalloff = ClampUnit(db.brewmasterElixirGlowFalloff, BrewmasterElixir.defaults.brewmasterElixirGlowFalloff)
    db.brewmasterElixirGlowOffsetX = NormalizeGlowExpandValue(db.brewmasterElixirGlowOffsetX, BrewmasterElixir.defaults.brewmasterElixirGlowOffsetX)
    db.brewmasterElixirGlowOffsetY = NormalizeGlowExpandValue(db.brewmasterElixirGlowOffsetY, BrewmasterElixir.defaults.brewmasterElixirGlowOffsetY)
    db.brewmasterElixirGlowColor = NormalizeColorTable(db.brewmasterElixirGlowColor, BrewmasterElixir.defaults.brewmasterElixirGlowColor)

    return db
end

BrewmasterElixir.NormalizeDB = NormalizeDB

local function BuildGlowParams(db)
    db = NormalizeDB(db or GetDB())
    return {
        style = db.brewmasterElixirGlowStyle,
        size = db.brewmasterElixirGlowSize,
        lines = db.brewmasterElixirGlowLines,
        thickness = db.brewmasterElixirGlowThickness,
        length = db.brewmasterElixirGlowLength,
        speed = db.brewmasterElixirGlowSpeed,
        alpha = db.brewmasterElixirGlowAlpha,
        falloff = db.brewmasterElixirGlowFalloff,
        offsetX = db.brewmasterElixirGlowOffsetX,
        offsetY = db.brewmasterElixirGlowOffsetY,
        color = db.brewmasterElixirGlowColor,
    }
end

local function IsPlayerMonk()
    if UnitAPI and UnitAPI.GetClassToken then
        return UnitAPI.GetClassToken("player") == MONK_CLASS_TOKEN
    end
    local _, classToken = UnitClass and UnitClass("player")
    classToken = SafeString(classToken)
    return classToken == MONK_CLASS_TOKEN
end

local function GetCurrentSpecID()
    if TalentAPI and TalentAPI.GetCurrentSpecializationInfo then
        local info = TalentAPI.GetCurrentSpecializationInfo()
        local specID = SafeNumber(info and info.specID)
        if specID then return specID end
    end

    if TalentAPI and TalentAPI.GetSpecialization and TalentAPI.GetSpecializationInfo then
        local specIndex = SafeNumber(TalentAPI.GetSpecialization())
        if not specIndex then return nil end
        return SafeNumber(TalentAPI.GetSpecializationInfo(specIndex))
    end

    if GetSpecialization and GetSpecializationInfo then
        local specIndex = SafeNumberFromCall(GetSpecialization)
        if not specIndex then return nil end
        return SafeNumberFromCall(GetSpecializationInfo, specIndex)
    end

    return nil
end

local function IsApplicable()
    return IsPlayerMonk() and GetCurrentSpecID() == BREWMASTER_SPEC_ID
end

local function IsPlayerInCombat()
    return SafeBooleanFromCall(UnitAffectingCombat, "player") == true
end

local function IsPlayerInInstance()
    return SafeBooleanFromCall(IsInInstance) == true
end

local function IsKnownSpell(spellID)
    if SpellAPI and SpellAPI.IsKnownOrInSpellBook then
        local ok, known = pcall(SpellAPI.IsKnownOrInSpellBook, spellID)
        if ok and known == true then return true end
    end
    if SpellAPI and SpellAPI.IsKnown then
        local ok, known = pcall(SpellAPI.IsKnown, spellID)
        if ok and known == true then return true end
    end
    return false
end

local function IsWiseElixirKnown()
    return IsKnownSpell(WISE_ELIXIR_SPELL_ID) or IsKnownSpell(ELIXIR_COOLDOWN_SPELL_ID)
end

local function GetSpellTexture(spellID)
    if SpellAPI and SpellAPI.GetTexture then
        local ok, texture = pcall(SpellAPI.GetTexture, spellID)
        if ok and not IsSecretValue(texture) and texture then
            return texture
        end
    end
    return nil
end

local function GetElixirIcon()
    return GetSpellTexture(WISE_ELIXIR_SPELL_ID) or GetSpellTexture(ELIXIR_COOLDOWN_SPELL_ID) or ELIXIR_FALLBACK_ICON
end

local function GetNow()
    return (GetTime and GetTime()) or 0
end

local function ToLayoutPlacement(point, relativeTo, relativePoint, x, y)
    return {
        version = 1,
        anchor = {
            point = point or "CENTER",
            relative = relativeTo or "UIParent",
            relativePoint = relativePoint or point or "CENTER",
        },
        offset = {
            x = Round(x or 0),
            y = Round(y or 0),
        },
    }
end

local function GetDefaultPlacement()
    return ToLayoutPlacement("CENTER", "UIParent", "CENTER", -100, -66)
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

local function OpenSettings()
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

local function SetGlowShown(glow, shown)
    if not glow then return end
    if glow.SetGlowShown then
        glow:SetGlowShown(shown == true)
    elseif shown then
        glow:Show()
    else
        glow:Hide()
    end
end

local function StopElixirClock()
    ElixirState.lastRemaining = nil
end

local function ClearElixirCooldown()
    if Widget.frame and Widget.frame.SetCooldown then
        Widget.frame:SetCooldown(0, 0)
    elseif Widget.cooldown then
        if Widget.cooldown.Clear then
            Widget.cooldown:Clear()
        elseif Widget.cooldown.SetCooldown then
            Widget.cooldown:SetCooldown(0, 0)
        end
    end
    if Widget.cooldown then
        Widget.cooldown:Hide()
    end
end

local function HideWidget()
    StopElixirClock()
    ClearElixirCooldown()
    SetGlowShown(Widget.glow, false)
    if Widget.text then
        Widget.text:SetText("")
    end
    if Widget.icon and Widget.icon.SetDesaturated then
        Widget.icon:SetDesaturated(false)
    end
    if Widget.frame and not settingsPreviewActive and not layoutPreviewActive then
        Widget.frame:Hide()
    end
end

local function ApplyReadyVisual(db, ready)
    db = NormalizeDB(db or GetDB())
    if Widget.icon and Widget.icon.SetDesaturated then
        Widget.icon:SetDesaturated(false)
    end
    SetGlowShown(Widget.glow, ready and db.brewmasterElixirReadyGlowEnabled == true and db.brewmasterElixirGlowStyle ~= "none")
end

local function ApplyCooldownVisual(db)
    db = NormalizeDB(db or GetDB())
    if Widget.icon and Widget.icon.SetDesaturated then
        Widget.icon:SetDesaturated(true)
    end
    SetGlowShown(Widget.glow, false)
end

local function ApplyAppearance(db)
    db = NormalizeDB(db or GetDB())
    activeDB = db

    local frame = Widget.frame
    if not frame then return end

    local size = db.brewmasterElixirIconSize
    frame:SetSize(size, size)
    if frame.SetIcon then
        frame:SetIcon(GetElixirIcon())
    end
    if Widget.icon then
        Widget.icon:ClearAllPoints()
        Widget.icon:SetAllPoints(frame)
        if Widget.icon.SetTexture then
            Widget.icon:SetTexture(GetElixirIcon())
        end
    end
    if Widget.cooldown then
        Widget.cooldown:ClearAllPoints()
        Widget.cooldown:SetAllPoints(Widget.icon or frame)
    end
    if Widget.textLayer then
        Widget.textLayer:ClearAllPoints()
        Widget.textLayer:SetAllPoints(frame)
    end
    if Widget.text then
        Widget.text:ClearAllPoints()
        Widget.text:SetPoint("CENTER", Widget.textLayer or frame, "CENTER", 0, 0)
        SetFontSize(Widget.text, db.brewmasterElixirFontSize, "OUTLINE")
        SetTextColor(Widget.text, DEFAULT_TEXT_COLOR)
    end
    if Widget.glow and Widget.glow.SetGlowParams then
        Widget.glow:SetGlowParams(BuildGlowParams(db))
    end

    RefreshLayoutFrame()
    Widget.appearanceDirty = false
end

BrewmasterElixir.ApplyAppearance = ApplyAppearance
function BrewmasterElixir:ApplyElixirAppearance(db)
    ApplyAppearance(db)
end

local function EnsureLayoutPreviewState(db)
    db = NormalizeDB(db or activeDB or GetDB())
    if not (IsLayoutEditing() and not layoutPreviewSuppressed and db.brewmasterElixirEnabled == true) then
        return false
    end

    layoutPreviewActive = true
    SetSettingsPreviewDragEnabled(false)
    return true
end

local function ReadSpellCooldown(spellID)
    if not spellID then return nil end
    if SpellAPI and SpellAPI.GetCooldown then
        local ok, cooldown = pcall(SpellAPI.GetCooldown, spellID)
        if ok and type(cooldown) == "table" then
            local startTime = SafeNumber(cooldown.startTime) or 0
            local duration = SafeNumber(cooldown.duration) or 0
            local modRate = SafeNumber(cooldown.modRate) or 1
            if startTime > 0 and duration > 1.5 then
                local now = GetNow()
                local remaining = (startTime + duration) - now
                if remaining > 0 then
                    return {
                        startTime = startTime,
                        duration = duration,
                        remaining = remaining,
                        modRate = modRate,
                    }
                end
            end
        end
    end
    return nil
end

local function GetElixirCooldownWindowData()
    local data
    if RuntimeMonitor and RuntimeMonitor.GetTriggerData then
        data = RuntimeMonitor:GetTriggerData("elixirCooldown")
    end
    if not data then
        CoreMonitor = CoreMonitor or YUI.Monitor
        if CoreMonitor and CoreMonitor.GetTriggerData then
            data = CoreMonitor:GetTriggerData(MONITOR_ID, "elixirCooldown")
        end
    end
    return data
end

local function ReadElixirCooldownWindow()
    local data = GetElixirCooldownWindowData()
    if type(data) ~= "table" then return nil end

    local remaining = SafeNumber(data.remaining)
    local duration = SafeNumber(data.duration)
    local startTime = SafeNumber(data.startTime)
    if not (remaining and remaining > 0 and duration and duration > 0 and startTime) then
        return nil
    end

    return {
        startTime = startTime,
        duration = duration,
        remaining = remaining,
        modRate = 1,
    }
end

local function ReadElixirCooldown()
    local cooldown = ReadSpellCooldown(ELIXIR_COOLDOWN_SPELL_ID) or ReadSpellCooldown(WISE_ELIXIR_SPELL_ID)
    if cooldown then
        return cooldown
    end

    cooldown = ReadElixirCooldownWindow()
    if cooldown then
        return cooldown
    end

    return nil
end

local function FormatRemaining(remaining)
    remaining = math.ceil(math.max(0, tonumber(remaining) or 0))
    if remaining < 60 then
        return tostring(remaining)
    end
    local minutes = math.floor(remaining / 60)
    local seconds = remaining % 60
    return string.format("%d:%02d", minutes, seconds)
end

local function RenderElixirCooldown(db, cooldown)
    db = NormalizeDB(db or GetDB())
    if not cooldown then
        StopElixirClock()
        ClearElixirCooldown()
        if Widget.text then Widget.text:SetText("") end
        ApplyReadyVisual(db, true)
        return
    end

    if Widget.frame and Widget.frame.SetCooldown then
        Widget.frame:SetCooldown(cooldown.startTime, cooldown.duration)
    elseif Widget.cooldown and Widget.cooldown.SetCooldown then
        Widget.cooldown:SetCooldown(cooldown.startTime, cooldown.duration)
    end
    if Widget.cooldown then Widget.cooldown:Show() end
    if Widget.text then Widget.text:SetText(FormatRemaining(cooldown.remaining)) end
    ElixirState.lastRemaining = math.ceil(cooldown.remaining)
    ApplyCooldownVisual(db)
end

local function UpdateElixirCountdown(db)
    if not Widget.frame or not Widget.frame:IsShown() then return end
    local cooldown = ReadElixirCooldown()
    if not cooldown then
        RenderElixirCooldown(db, nil)
        return
    end

    if Widget.text then
        local remaining = math.ceil(cooldown.remaining)
        if remaining ~= ElixirState.lastRemaining then
            ElixirState.lastRemaining = remaining
            Widget.text:SetText(FormatRemaining(remaining))
        end
    end
    ApplyCooldownVisual(db)
end

local function RefreshState(db)
    db = NormalizeDB(db or GetDB())
    local frame = Widget.frame
    if not frame then return end
    if Widget.appearanceDirty then
        ApplyAppearance(db)
    end

    frame:Show()
    SetSettingsPreviewDragEnabled(settingsPreviewActive)
    if settingsPreviewActive or layoutPreviewActive then
        local now = GetNow()
        RenderElixirCooldown(db, {
            startTime = now - 2,
            duration = ELIXIR_TRIGGER_COOLDOWN,
            remaining = ELIXIR_TRIGGER_COOLDOWN - 2,
            modRate = 1,
        })
        return
    end

    RenderElixirCooldown(db, ReadElixirCooldown())
end

local function EnsureWidget()
    if Widget.frame then
        return Widget.frame
    end
    GUI2 = YUI.GUI2
    if not (GUI2 and GUI2.Application and GUI2.Application.CreateCooldownIcon and UIParent) then
        return nil
    end

    local frame = GUI2.Application:CreateCooldownIcon(UIParent, {
        size = DEFAULT_ICON_SIZE,
        icon = GetElixirIcon(),
        shape = "rounded",
    })
    if not frame then return nil end
    if frame.SetFrameStrata then frame:SetFrameStrata("MEDIUM") end
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    if frame.SetMovable then frame:SetMovable(true) end
    if frame.EnableMouse then frame:EnableMouse(false) end
    if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
    if frame.SetScript then
        frame:SetScript("OnDragStart", OnSettingsPreviewDragStart)
        frame:SetScript("OnDragStop", OnSettingsPreviewDragStop)
    end
    frame:Hide()

    local cooldown = frame.cooldown
    if cooldown then
        if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(true) end
        cooldown.noCooldownCount = true
        if cooldown.SetSwipeColor then cooldown:SetSwipeColor(0, 0, 0, 0.62) end
        if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
        cooldown:Hide()
    end

    local textLayer = GUI2:CreateFrame(frame, { allPoints = true, mouse = false })
    if textLayer and textLayer.SetFrameLevel and frame.GetFrameLevel then
        textLayer:SetFrameLevel((frame:GetFrameLevel() or 0) + 8)
    end

    local text = GUI2:CreateText(textLayer or frame, "", DEFAULT_FONT_SIZE, "color.text.primary", "CENTER")
    text:SetPoint("CENTER", textLayer or frame, "CENTER", 0, 0)
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetShadowOffset(1, -1)

    local glow = GUI2.CreateGlow and GUI2:CreateGlow(frame, BuildGlowParams(activeDB or GetDB()))
    if glow and glow.Hide then glow:Hide() end

    Widget.frame = frame
    Widget.icon = frame.icon
    Widget.cooldown = cooldown
    Widget.textLayer = textLayer
    Widget.text = text
    Widget.glow = glow
    Widget.appearanceDirty = true

    if YUI.Layout and YUI.Layout.RegisterFrame then
        YUI.Layout:RegisterFrame(LAYOUT_ID, {
            frame = frame,
            title = T("layout.brewmaster_elixir_icon", "明志灵药图标"),
            category = "component",
            defaultPlacement = GetDefaultPlacement,
            movable = true,
            snap = true,
            anchorTargets = { "UIParent" },
            minWidth = 28,
            minHeight = 28,
            getMoverBounds = function()
                local db = NormalizeDB(activeDB or GetDB())
                local size = db.brewmasterElixirIconSize or DEFAULT_ICON_SIZE
                return size, size
            end,
            isEnabled = function()
                local db = NormalizeDB(activeDB or GetDB())
                return (featureActive or settingsPreviewActive or layoutPreviewActive or IsLayoutEditing()) and db.brewmasterElixirEnabled == true
            end,
            openPluginSettings = OpenSettings,
            onEnterEditMode = function()
                local db = NormalizeDB(activeDB or GetDB())
                layoutPreviewSuppressed = false
                layoutPreviewActive = true
                SetSettingsPreviewDragEnabled(false)
                ApplyAppearance(db)
                RefreshState(db)
            end,
            onHideEditModePreview = function()
                layoutPreviewSuppressed = true
                layoutPreviewActive = false
                SetSettingsPreviewDragEnabled(settingsPreviewActive)
                local db = NormalizeDB(activeDB or GetDB())
                if runtimeActive or settingsPreviewActive then
                    RefreshState(db)
                else
                    HideWidget()
                end
            end,
            onExitEditMode = function()
                layoutPreviewActive = false
                layoutPreviewSuppressed = false
                settingsPreviewActive = false
                SetSettingsPreviewDragEnabled(false)
                if previewButton and previewButton.SetText then
                    previewButton:SetText(T("settings.preview", "预览"))
                end
                local db = NormalizeDB(activeDB or GetDB())
                if runtimeActive then
                    RefreshState(db)
                else
                    HideWidget()
                end
            end,
            onApply = function()
                local db = NormalizeDB(activeDB or GetDB())
                ApplyAppearance(db)
                if layoutPreviewActive then
                    RefreshState(db)
                end
            end,
        })
        layoutRegistered = true
    else
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -216)
    end

    ApplyAppearance(activeDB or GetDB())
    return frame
end

local function ShouldShow(db, applicable)
    db = NormalizeDB(db or GetDB())
    if db.brewmasterElixirEnabled ~= true then return false end
    if settingsPreviewActive or layoutPreviewActive then return true end
    if not featureActive then return false end
    if not applicable then return false end
    if not IsWiseElixirKnown() then return false end

    if ReadElixirCooldown() then return true end

    if db.brewmasterElixirDisplayMode == DISPLAY_MODE_COMBAT then
        return IsPlayerInCombat()
    elseif db.brewmasterElixirDisplayMode == DISPLAY_MODE_INSTANCE then
        return IsPlayerInInstance()
    end
    return true
end

local function RuntimeDB()
    return NormalizeDB(activeDB or GetDB())
end

local function HideMonitorContext(ctx, hideFunc)
    if ctx and ctx.visible == false then return end
    hideFunc()
end

local function OnMonitorTrigger(ctx)
    if ctx and ctx.active then
        RefreshState(RuntimeDB())
    else
        HideWidget()
    end
end

local function UpdatePresenter(ctx)
    if ctx and ctx.active then
        UpdateElixirCountdown(RuntimeDB())
    else
        HideWidget()
    end
end

local function EnsureRuntimeMonitor()
    if RuntimeMonitor then return RuntimeMonitor end
    CoreMonitor = CoreMonitor or YUI.Monitor
    if not (CoreMonitor and CoreMonitor.Register) then return nil end

    RuntimeMonitor = CoreMonitor:Register({
        id = MONITOR_ID,
        moduleId = MODULE_ID,
        owner = BrewmasterElixir,
        load = IsApplicable,
        activation = {
            expression = function()
                return ShouldShow(RuntimeDB(), true)
            end,
            triggers = {
                { id = "refreshWorld", type = "event", event = "PLAYER_ENTERING_WORLD", activation = false },
                { id = "refreshSpec", type = "event", event = "PLAYER_SPECIALIZATION_CHANGED", activation = false },
                { id = "refreshTalent", type = "event", event = "PLAYER_TALENT_UPDATE", activation = false },
                { id = "refreshTraitConfig", type = "event", event = "TRAIT_CONFIG_UPDATED", activation = false },
                { id = "refreshCombatConfig", type = "event", event = "ACTIVE_COMBAT_CONFIG_CHANGED", activation = false },
                { id = "refreshCombatStart", type = "event", event = "PLAYER_REGEN_DISABLED", activation = false },
                { id = "refreshCombatEnd", type = "event", event = "PLAYER_REGEN_ENABLED", activation = false },
                { id = "refreshZone", type = "event", event = "ZONE_CHANGED_NEW_AREA", activation = false },
                {
                    id = "elixirCooldown",
                    type = "event",
                    event = "SPELL_UPDATE_COOLDOWN",
                    spellID = ELIXIR_COOLDOWN_SPELL_ID,
                    duration = ELIXIR_TRIGGER_COOLDOWN,
                    matchBaseSpellID = true,
                    activation = false,
                },
                {
                    id = "cast",
                    type = "event",
                    event = "UNIT_SPELLCAST_SUCCEEDED",
                    unit = "player",
                    spellID = WISE_ELIXIR_SPELL_ID,
                    activation = false,
                },
            },
        },
        conditions = {
            onEnable = function()
                runtimeActive = true
            end,
            onDisable = function()
                runtimeActive = false
                if not settingsPreviewActive and not layoutPreviewActive then
                    HideWidget()
                end
            end,
            onActivate = function()
                EnsureWidget()
                RefreshState(RuntimeDB())
            end,
            onDeactivate = function(ctx)
                HideMonitorContext(ctx, HideWidget)
            end,
            onTrigger = OnMonitorTrigger,
        },
        update = {
            interval = 0.08,
            whileVisible = true,
        },
        appearance = {
            presenter = {
                ensure = function()
                    EnsureWidget()
                end,
                apply = function()
                    ApplyAppearance(RuntimeDB())
                end,
                update = UpdatePresenter,
                show = function()
                    if Widget.frame then Widget.frame:Show() end
                end,
                hide = HideWidget,
                destroy = HideWidget,
            },
        },
    })

    return RuntimeMonitor
end

local function SetRuntimeMonitorEnabled(monitor, enabled)
    if monitor and monitor.SetEnabled then
        return monitor:SetEnabled(enabled) == true
    end
    return false
end

RefreshRuntime = function(db)
    db = NormalizeDB(db or GetDB())
    activeDB = db

    if db.brewmasterElixirEnabled == true and (featureActive or settingsPreviewActive or layoutPreviewActive or IsLayoutEditing()) then
        EnsureWidget()
        ApplyAppearance(db)
    end

    local monitor = EnsureRuntimeMonitor()
    runtimeActive = SetRuntimeMonitorEnabled(monitor, featureActive and db.brewmasterElixirEnabled == true)

    if settingsPreviewActive or layoutPreviewActive then
        if ShouldShow(db, true) then
            RefreshState(db)
        else
            HideWidget()
        end
    elseif not runtimeActive then
        HideWidget()
    end
end

local function UpdatePreviewButton(button, active)
    if button and button.SetText then
        button:SetText(active and T("settings.preview_stop", "关闭预览") or T("settings.preview", "预览"))
    end
end

local function StartSettingsPreview()
    settingsPreviewActive = true
    local db = NormalizeDB(activeDB or GetDB())
    EnsureWidget()
    ApplyAppearance(db)
    RefreshState(db)
    SetSettingsPreviewDragEnabled(true)
end

local function StopSettingsPreview()
    settingsPreviewActive = false
    SetSettingsPreviewDragEnabled(false)
    if layoutPreviewActive then
        RefreshState(activeDB or GetDB())
        return
    end
    RefreshRuntime(activeDB or GetDB())
end

local function TogglePreview(button)
    previewButton = button or previewButton
    if settingsPreviewActive then
        StopSettingsPreview()
    else
        StartSettingsPreview()
    end
    UpdatePreviewButton(previewButton, settingsPreviewActive)
end

local function RefreshSettingsModule()
    local feature = YUI.Components and YUI.Components.features and YUI.Components.features[FEATURE_KEY]
    if feature and feature.RefreshCurrentModule then
        feature.RefreshCurrentModule()
    end
end

function BrewmasterElixir:RefreshRuntime(db)
    RefreshRuntime(db)
end

function BrewmasterElixir:OnFeatureToggle(enable, db)
    featureActive = enable == true
    if not featureActive then
        settingsPreviewActive = false
        layoutPreviewActive = false
        layoutPreviewSuppressed = false
        SetSettingsPreviewDragEnabled(false)
        if RuntimeMonitor then
            RuntimeMonitor:SetEnabled(false)
        end
        runtimeActive = false
        HideWidget()
        return
    end
    RefreshRuntime(db or GetDB())
end

function BrewmasterElixir:OnSettingsLeave(db)
    settingsPreviewActive = false
    SetSettingsPreviewDragEnabled(false)
    UpdatePreviewButton(previewButton, false)
    RefreshRuntime(db or activeDB or GetDB())
end

local function BuildReadyModeOptions()
    return {
        { text = T("settings.elixir_ready_glow", "可用时发光"), value = READY_MODE_GLOW },
        { text = T("settings.elixir_ready_desaturate", "可用时变灰"), value = READY_MODE_DESATURATE },
        { text = T("settings.elixir_ready_normal", "仅显示图标"), value = READY_MODE_NORMAL },
    }
end

local function BuildDisplayModeItems()
    return {
        { text = T("settings.display_mode_always", "始终显示"), value = DISPLAY_MODE_ALWAYS },
        { text = T("settings.display_mode_combat", "战斗中"), value = DISPLAY_MODE_COMBAT },
        { text = T("settings.display_mode_instance", "副本内"), value = DISPLAY_MODE_INSTANCE },
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
        style = db.brewmasterElixirGlowStyle,
        size = db.brewmasterElixirGlowSize,
        lines = db.brewmasterElixirGlowLines,
        thickness = db.brewmasterElixirGlowThickness,
        length = db.brewmasterElixirGlowLength,
        speed = db.brewmasterElixirGlowSpeed,
        alpha = db.brewmasterElixirGlowAlpha,
        falloff = db.brewmasterElixirGlowFalloff,
        offsetX = db.brewmasterElixirGlowOffsetX,
        offsetY = db.brewmasterElixirGlowOffsetY,
        color = db.brewmasterElixirGlowColor,
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
            lines = 4,
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
    db.brewmasterElixirGlowStyle = VALID_GLOW_STYLES[style] and style or BrewmasterElixir.defaults.brewmasterElixirGlowStyle
    db.brewmasterElixirGlowSize = NormalizeGlowSizeValue(value.size, BrewmasterElixir.defaults.brewmasterElixirGlowSize)
    db.brewmasterElixirGlowLines = Round(ClampNumber(value.lines, 1, 20, BrewmasterElixir.defaults.brewmasterElixirGlowLines))
    db.brewmasterElixirGlowThickness = Round(ClampNumber(value.thickness, 1, 20, BrewmasterElixir.defaults.brewmasterElixirGlowThickness))
    db.brewmasterElixirGlowLength = Round(ClampNumber(value.length, 4, 80, BrewmasterElixir.defaults.brewmasterElixirGlowLength))
    db.brewmasterElixirGlowSpeed = ClampNumber(value.speed, 0, 3, BrewmasterElixir.defaults.brewmasterElixirGlowSpeed)
    db.brewmasterElixirGlowAlpha = ClampUnit(value.alpha, BrewmasterElixir.defaults.brewmasterElixirGlowAlpha)
    db.brewmasterElixirGlowFalloff = ClampUnit(value.falloff, BrewmasterElixir.defaults.brewmasterElixirGlowFalloff)
    db.brewmasterElixirGlowOffsetX = NormalizeGlowExpandValue(value.offsetX, BrewmasterElixir.defaults.brewmasterElixirGlowOffsetX)
    db.brewmasterElixirGlowOffsetY = NormalizeGlowExpandValue(value.offsetY, BrewmasterElixir.defaults.brewmasterElixirGlowOffsetY)
    db.brewmasterElixirGlowColor = NormalizeColorTable(value.color, BrewmasterElixir.defaults.brewmasterElixirGlowColor)
    ApplyAppearance(db)
    RefreshRuntime(db)
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

function BrewmasterElixir:BuildOptions(db)
    db = NormalizeDB(db or GetDB())

    local options = {}
    local enabledField = {
            type = "checkbox",
            settingsToggle = "brewmasterElixir",
            searchKey = "settings.brewmaster_elixir_enabled",
            label = T("settings.brewmaster_elixir_enabled", "启用监控"),
            get = function() return db.brewmasterElixirEnabled == true end,
            set = function(value)
                db.brewmasterElixirEnabled = value == true
                RefreshRuntime(db)
            end,
        }
    local previewField = {
            type = "button",
            label = "",
            text = settingsPreviewActive and T("settings.preview_stop", "关闭预览") or T("settings.preview", "预览"),
            bodyWidth = 132,
            onClick = TogglePreview,
        }
    local displayModeField = {
            type = "dropdown",
            label = T("settings.display_mode", "显示模式"),
            layoutPreset = "inlineSelector",
            options = BuildDisplayModeItems,
            bodyWidth = BODY_WIDTH,
            default = BrewmasterElixir.defaults.brewmasterElixirDisplayMode,
            get = function() return db.brewmasterElixirDisplayMode end,
            set = function(value)
                db.brewmasterElixirDisplayMode = VALID_DISPLAY_MODES[value] and value or BrewmasterElixir.defaults.brewmasterElixirDisplayMode
                db.brewmasterElixirHideOutOfCombat = db.brewmasterElixirDisplayMode == DISPLAY_MODE_COMBAT
                RefreshRuntime(db)
            end,
        }
    local iconSizeField = {
            type = "slider",
            label = T("settings.icon_size", "图标尺寸"),
            min = 28,
            max = 96,
            step = 1,
            get = function() return db.brewmasterElixirIconSize end,
            set = function(value)
                db.brewmasterElixirIconSize = ClampNumber(value, 28, 96, BrewmasterElixir.defaults.brewmasterElixirIconSize)
                ApplyAppearance(db)
                RefreshRuntime(db)
            end,
        }
    local fontSizeField = {
            type = "slider",
            label = T("settings.font_size", "文字尺寸"),
            min = 10,
            max = 36,
            step = 1,
            get = function() return db.brewmasterElixirFontSize end,
            set = function(value)
                db.brewmasterElixirFontSize = ClampNumber(value, 10, 36, BrewmasterElixir.defaults.brewmasterElixirFontSize)
                ApplyAppearance(db)
                RefreshRuntime(db)
            end,
        }
    local readyGlowField = {
            type = "checkbox",
            label = T("settings.elixir_ready_glow_enabled", "可用发光"),
            get = function() return db.brewmasterElixirReadyGlowEnabled == true end,
            set = function(value)
                db.brewmasterElixirReadyGlowEnabled = value == true
                if db.brewmasterElixirReadyGlowEnabled then
                    db.brewmasterElixirReadyMode = READY_MODE_GLOW
                elseif db.brewmasterElixirReadyMode == READY_MODE_GLOW then
                    db.brewmasterElixirReadyMode = READY_MODE_NORMAL
                end
                RefreshRuntime(db)
                RefreshSettingsModule()
            end,
        }

    if Monitor.AppendIconDivider then
        Monitor:AppendIconDivider(options, T("settings.brewmaster_elixir", "明志灵药"), GetElixirIcon, SECTION_WIDTH)
    else
        options[#options + 1] = { type = "divider", label = T("settings.brewmaster_elixir", "明志灵药"), alignLeft = true, width = SECTION_WIDTH }
    end
    local basicFields = { enabledField, previewField, displayModeField, iconSizeField, fontSizeField, readyGlowField }
    options[#options + 1] = {
        type = "custom",
        retainedFields = basicFields,
        width = SECTION_WIDTH,
        render = function(parent, x, y, width)
            local Settings = YUI.Settings
            if not (Settings and Settings.RenderAlignedFields) then
                return SECTION_WIDTH, 1
            end

            local availableWidth = math.min(width or SECTION_WIDTH, SECTION_WIDTH)
            local rowGap = 10
            local cursorY = y
            local totalHeight = 0
            local maxWidth = 0
            local function RenderRows(fields, columns)
                local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                    x = x,
                    y = cursorY,
                    width = availableWidth,
                    columns = columns or 2,
                    labelPosition = "top",
                    columnGap = COLUMN_GAP,
                    labelWidth = LABEL_WIDTH,
                    labelGap = LABEL_GAP,
                    bodyWidth = BODY_WIDTH,
                    valueWidth = INPUT_WIDTH,
                    valueGap = VALUE_GAP,
                    rowHeight = 32,
                    rowGap = rowGap,
                    fields = fields,
                })
                maxWidth = math.max(maxWidth, gridWidth or 0)
                totalHeight = totalHeight + (gridHeight or 0) + rowGap
                cursorY = cursorY - (gridHeight or 0) - rowGap
            end

            RenderRows(basicFields, 2)

            return maxWidth, math.max(totalHeight - rowGap, 1)
        end,
    }

    options[#options + 1] = {
        type = "glow",
        label = T("settings.glow", "发光"),
        hidden = function()
            return db.brewmasterElixirReadyGlowEnabled ~= true
        end,
        rowWidth = SECTION_WIDTH,
        width = BODY_WIDTH,
        controlWidth = BODY_WIDTH,
        panelWidth = SECTION_WIDTH - LABEL_WIDTH - LABEL_GAP,
        labelWidth = LABEL_WIDTH,
        gap = LABEL_GAP,
        inputWidth = INPUT_WIDTH,
        styleOptions = BuildGlowStyleOptions,
        labels = BuildGlowControlLabels(),
        default = BuildGlowOptionsValue(BrewmasterElixir.defaults),
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

Monitor.BrewmasterElixir = BrewmasterElixir
Monitor:RegisterSubFeature(BrewmasterElixir)
