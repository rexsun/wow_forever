local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not (YUI and (YUI.IsRetail or YUI.IsWrath or YUI.IsForever)) then return end

local CombatEnhancement = YUI.CombatEnhancement
if not (CombatEnhancement and CombatEnhancement.RegisterSubFeature) then return end

local CombatAPI = (YUI.API and YUI.API.Combat) or YUI.WOW_API
local GUI2 = YUI.GUI2
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local CombatTimer = {
    id = "combatTimer",
    order = 40,
}

local FEATURE_KEY = CombatEnhancement.FEATURE_KEY or "CombatEnhancement"
local LAYOUT_ID = "yui.component.combat_enhancement.combat_timer"
local FRAME_NAME = "YUI_CombatEnhancement_CombatTimerFrame"
local MODULE_ID = "component:CombatEnhancement"

local DEFAULT_FORMAT = "plain"
local DEFAULT_FONT = "default"
local DEFAULT_FONT_SIZE = 18
local MIN_FONT_SIZE = 10
local MAX_FONT_SIZE = 48
local DEFAULT_TEXT_STYLE = "outline_shadow"
local DEFAULT_COLOR = { 1, 1, 1, 1 }
local DEFAULT_FRAME_WIDTH = 144
local DEFAULT_FRAME_HEIGHT = 34
local PREVIEW_SECONDS = 180
local DEFAULT_OUT_OF_COMBAT_RULE = "hide"
local DEFAULT_OUT_OF_COMBAT_ALPHA = 100
local OUT_OF_COMBAT_DELAY_SECONDS = 3

local VALID_FORMATS = {
    plain = true,
    square = true,
    angle = true,
    seconds = true,
}

local VALID_TEXT_STYLES = {
    none = true,
    shadow = true,
    outline_shadow = true,
}

local VALID_OUT_OF_COMBAT_RULES = {
    hide = true,
    hold3 = true,
    always_reset3 = true,
    always_keep = true,
}

local SECTION_WIDTH = 620
local COLUMN_GAP = 24
local COLUMN_WIDTH = math.floor((SECTION_WIDTH - COLUMN_GAP) / 2)
local LABEL_WIDTH = 112
local LABEL_GAP = 10
local BODY_WIDTH = COLUMN_WIDTH - LABEL_WIDTH - LABEL_GAP
local INPUT_WIDTH = 52
local VALUE_GAP = 10

local featureActive = false
local eventsRegistered = false
local layoutRegistered = false
local registeringLayout = false
local layoutPreviewActive = false
local layoutEditRequested = false
local directPreviewActive = false
local directPreviewDragging = false
local timerFrame
local timerText
local combatTicker
local postCombatTimer
local postCombatTimerGeneration = 0
local combatStartTime
local lastCombatElapsed
local lastCombatEndedAt
local activeRuntimeDB
local lastRenderedText
local appliedFrameAlpha
local appliedFont
local appliedFontSize
local appliedTextStyle
local EventOwner = {}
local DirectPreviewEventOwner = {}
local directPreviewEventRegistered = false
local RegisterLayout

local function T(key, fallback)
    if CombatEnhancement.T then
        return CombatEnhancement:T(key, fallback)
    end
    return fallback or key
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

local function CopyColor(color)
    return {
        color and color[1] or DEFAULT_COLOR[1],
        color and color[2] or DEFAULT_COLOR[2],
        color and color[3] or DEFAULT_COLOR[3],
        color and color[4] or DEFAULT_COLOR[4],
    }
end

local function NormalizeColor(value)
    if type(value) ~= "table" then
        return CopyColor(DEFAULT_COLOR)
    end
    value[1] = ClampColorComponent(value[1] or value.r, DEFAULT_COLOR[1])
    value[2] = ClampColorComponent(value[2] or value.g, DEFAULT_COLOR[2])
    value[3] = ClampColorComponent(value[3] or value.b, DEFAULT_COLOR[3])
    value[4] = ClampColorComponent(value[4] or value.a, DEFAULT_COLOR[4])
    return value
end

local function NormalizeFormat(value)
    if VALID_FORMATS[value] then return value end
    return DEFAULT_FORMAT
end

local function NormalizeFont(value)
    if type(value) == "string" and value ~= "" then return value end
    return DEFAULT_FONT
end

local function NormalizeTextStyle(value)
    if VALID_TEXT_STYLES[value] then return value end
    return DEFAULT_TEXT_STYLE
end

local function NormalizeOutOfCombatRule(value)
    if VALID_OUT_OF_COMBAT_RULES[value] then return value end
    return DEFAULT_OUT_OF_COMBAT_RULE
end

CombatTimer.defaults = {
    combatTimerEnabled = false,
    combatTimerFormat = DEFAULT_FORMAT,
    combatTimerFont = DEFAULT_FONT,
    combatTimerFontSize = DEFAULT_FONT_SIZE,
    combatTimerTextStyle = DEFAULT_TEXT_STYLE,
    combatTimerColor = CopyColor(DEFAULT_COLOR),
    combatTimerOutOfCombatRule = DEFAULT_OUT_OF_COMBAT_RULE,
    combatTimerOutOfCombatAlpha = DEFAULT_OUT_OF_COMBAT_ALPHA,
}

function CombatTimer:NormalizeDB(db)
    if type(db) ~= "table" then db = self.defaults end
    db.combatTimerEnabled = db.combatTimerEnabled == true
    db.combatTimerFormat = NormalizeFormat(db.combatTimerFormat)
    db.combatTimerFont = NormalizeFont(db.combatTimerFont)
    db.combatTimerFontSize = math.floor(ClampNumber(
        db.combatTimerFontSize,
        MIN_FONT_SIZE,
        MAX_FONT_SIZE,
        DEFAULT_FONT_SIZE
    ) + 0.5)
    db.combatTimerTextStyle = NormalizeTextStyle(db.combatTimerTextStyle)
    db.combatTimerColor = NormalizeColor(db.combatTimerColor)
    db.combatTimerOutOfCombatRule = NormalizeOutOfCombatRule(db.combatTimerOutOfCombatRule)
    db.combatTimerOutOfCombatAlpha = math.floor(ClampNumber(
        db.combatTimerOutOfCombatAlpha,
        0,
        100,
        DEFAULT_OUT_OF_COMBAT_ALPHA
    ) + 0.5)
    return db
end

local function GetDB(db)
    if type(db) ~= "table" and CombatEnhancement.GetDB then
        db = CombatEnhancement:GetDB()
    end
    return CombatTimer:NormalizeDB(db)
end

local function GetCurrentTime()
    if CombatAPI and CombatAPI.GetTime then
        local value = CombatAPI.GetTime()
        if type(value) == "number" then return value end
    end
    if GetTime then
        local value = GetTime()
        if type(value) == "number" then return value end
    end
    return 0
end

local function IsPlayerInCombat()
    if CombatAPI and CombatAPI.UnitAffectingCombat then
        return CombatAPI.UnitAffectingCombat("player") == true
    end
    if UnitAffectingCombat then
        return UnitAffectingCombat("player") == true
    end
    return false
end

local function IsCombatLocked()
    if CombatAPI and CombatAPI.InCombatLockdown then
        return CombatAPI.InCombatLockdown() == true
    end
    if InCombatLockdown then
        return InCombatLockdown() == true
    end
    return false
end

function CombatTimer.FormatElapsed(seconds, formatKey)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    formatKey = NormalizeFormat(formatKey)
    if formatKey == "seconds" then
        return tostring(seconds) .. "s"
    end

    local minutes = math.floor(seconds / 60)
    local remainingSeconds = seconds % 60
    local text = string.format("%02d:%02d", minutes, remainingSeconds)
    if formatKey == "square" then
        return "[" .. text .. "]"
    end
    if formatKey == "angle" then
        return "<" .. text .. ">"
    end
    return text
end

local function ResolveFontPath(fontName)
    fontName = NormalizeFont(fontName)
    if fontName ~= DEFAULT_FONT and LSM and LSM.Fetch then
        local path = LSM:Fetch("font", fontName, true)
        if type(path) == "string" and path ~= "" then return path end
    end
    if GUI2 and GUI2.GetFont then
        local path = GUI2:GetFont("font.family.body")
        if type(path) == "string" and path ~= "" then return path end
    end
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

function CombatTimer.ResolveFontPath(fontName)
    return ResolveFontPath(fontName)
end

local function GetFontFlags(textStyle)
    return NormalizeTextStyle(textStyle) == "outline_shadow" and "OUTLINE" or ""
end

local function ApplyTextShadow(fontString, textStyle)
    if not fontString then return end
    textStyle = NormalizeTextStyle(textStyle)
    if textStyle == "shadow" or textStyle == "outline_shadow" then
        if fontString.SetShadowColor then fontString:SetShadowColor(0, 0, 0, 1) end
        if fontString.SetShadowOffset then fontString:SetShadowOffset(1, -1) end
    elseif fontString.SetShadowOffset then
        fontString:SetShadowOffset(0, 0)
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

local function GetDefaultPlacement()
    return ToLayoutPlacement("CENTER", "UIParent", "CENTER", 0, 120)
end

local function ApplyDefaultPoint(frame)
    if not (frame and UIParent) then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
end

local function ApplyRuntimeLayer(frame)
    if not frame then return end
    if frame.SetFrameStrata then frame:SetFrameStrata("MEDIUM") end
    if frame.SetFrameLevel then frame:SetFrameLevel(20) end
end

local function ApplyDirectPreviewLayer(frame)
    if not frame then return end
    if frame.SetFrameStrata then frame:SetFrameStrata("TOOLTIP") end
    if frame.SetFrameLevel then frame:SetFrameLevel(50) end
end

local function RefreshLayoutFrame()
    if layoutRegistered and YUI.Layout and YUI.Layout.RefreshFrame then
        YUI.Layout:RefreshFrame(LAYOUT_ID)
    end
end

local function EnsureFrame()
    if timerFrame then return timerFrame end
    if not (GUI2 and GUI2.CreateFrame and GUI2.CreateText and UIParent) then return nil end

    local frame = GUI2:CreateFrame(UIParent, {
        name = FRAME_NAME,
        width = DEFAULT_FRAME_WIDTH,
        height = DEFAULT_FRAME_HEIGHT,
        strata = "MEDIUM",
        level = 20,
        mouse = false,
        clamped = true,
    })
    if not frame then return nil end

    ApplyDefaultPoint(frame)
    local text = GUI2:CreateText(frame, {
        text = "",
        size = DEFAULT_FONT_SIZE,
        colorKey = "color.text.primary",
        justifyH = "CENTER",
    })
    text.gui2ColorKey = nil
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetJustifyV("MIDDLE")

    timerFrame = frame
    timerText = text
    ApplyRuntimeLayer(frame)
    frame:Hide()
    if RegisterLayout and not layoutRegistered and not registeringLayout then
        RegisterLayout()
    end
    return frame
end

local function ApplyFrameAlpha(alpha)
    local frame = timerFrame
    if not (frame and frame.SetAlpha) then return end
    alpha = ClampNumber(alpha, 0, 1, 1)
    if appliedFrameAlpha == alpha then return end
    frame:SetAlpha(alpha)
    appliedFrameAlpha = alpha
end

function CombatTimer:MeasureLayoutSize(fontSize)
    return math.max(DEFAULT_FRAME_WIDTH, fontSize * 8), math.max(DEFAULT_FRAME_HEIGHT, fontSize + 16)
end

local function ApplyAppearance(db)
    local frame = EnsureFrame()
    if not (frame and timerText) then return end
    db = GetDB(db)

    local fontName = db.combatTimerFont
    local fontSize = db.combatTimerFontSize
    local textStyle = db.combatTimerTextStyle
    if appliedFont ~= fontName or appliedFontSize ~= fontSize or appliedTextStyle ~= textStyle then
        local fontPath = ResolveFontPath(fontName)
        local flags = GetFontFlags(textStyle)
        local ok, applied = pcall(timerText.SetFont, timerText, fontPath, fontSize, flags)
        if not ok or applied == false then
            pcall(timerText.SetFont, timerText, ResolveFontPath(DEFAULT_FONT), fontSize, flags)
        end
        ApplyTextShadow(timerText, textStyle)
        appliedFont = fontName
        appliedFontSize = fontSize
        appliedTextStyle = textStyle
        frame:SetSize(CombatTimer:MeasureLayoutSize(fontSize))
        RefreshLayoutFrame()
    end

    local color = db.combatTimerColor
    timerText:SetTextColor(color[1], color[2], color[3], color[4])
end

local function RenderSeconds(seconds, db)
    if not timerText then return end
    if type(db) ~= "table" then db = GetDB(db) end
    local text = CombatTimer.FormatElapsed(seconds, db.combatTimerFormat)
    if text ~= lastRenderedText then
        timerText:SetText(text)
        lastRenderedText = text
    end
end

local function CancelCombatTicker()
    local ticker = combatTicker
    combatTicker = nil
    if ticker and type(ticker.Cancel) == "function" then
        pcall(ticker.Cancel, ticker)
    end
end

local function CancelPostCombatTimer()
    postCombatTimerGeneration = postCombatTimerGeneration + 1
    local timer = postCombatTimer
    postCombatTimer = nil
    if timer and type(timer.Cancel) == "function" then
        pcall(timer.Cancel, timer)
    end
end

local cpuWatchdog = YUI.CPUWatchdog
local function OnCombatTicker()
    if not combatStartTime then return end
    local cpuStartedAt = cpuWatchdog and cpuWatchdog.timingActive and cpuWatchdog:BeginProbeTiming()
    RenderSeconds(GetCurrentTime() - combatStartTime, activeRuntimeDB)
    if cpuStartedAt then
        cpuWatchdog:EndProbeTiming("component.combat-timer", cpuStartedAt)
    end
end

local function StopCombatTimer()
    CancelCombatTicker()
    CancelPostCombatTimer()
    combatStartTime = nil
    activeRuntimeDB = nil
    lastRenderedText = nil
    lastCombatElapsed = nil
    lastCombatEndedAt = nil
    ApplyFrameAlpha(1)
    if timerFrame then timerFrame:Hide() end
end

local function ShowPreview(db)
    local frame = EnsureFrame()
    if not frame then return end
    CancelCombatTicker()
    CancelPostCombatTimer()
    combatStartTime = nil
    activeRuntimeDB = nil
    lastRenderedText = nil
    ApplyAppearance(db)
    ApplyFrameAlpha(1)
    RenderSeconds(PREVIEW_SECONDS, db)
    frame:Show()
end

local function OnDirectPreviewDragStart(frame)
    if not directPreviewActive or IsCombatLocked() then return end
    if frame and frame.StartMoving then
        frame:StartMoving()
        directPreviewDragging = true
    end
end

local function OnDirectPreviewDragStop(frame)
    if frame and frame.StopMovingOrSizing then frame:StopMovingOrSizing() end
    directPreviewDragging = false
    if not directPreviewActive then return end

    local committed = YUI.Layout and YUI.Layout.CommitFramePosition
        and YUI.Layout:CommitFramePosition(LAYOUT_ID, frame, "combat-timer-preview-drag")
    if not committed and YUI.Layout and YUI.Layout.RefreshFrame then
        YUI.Layout:RefreshFrame(LAYOUT_ID)
    end
    ApplyDirectPreviewLayer(frame)
end

local function SetDirectPreviewDragEnabled(enabled)
    local frame = enabled and EnsureFrame() or timerFrame
    if not frame then return enabled ~= true end
    if enabled then
        if frame.SetMovable then frame:SetMovable(true) end
        if frame.EnableMouse then frame:EnableMouse(true) end
        if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
        frame:SetScript("OnDragStart", OnDirectPreviewDragStart)
        frame:SetScript("OnDragStop", OnDirectPreviewDragStop)
        ApplyDirectPreviewLayer(frame)
        return true
    end

    if directPreviewDragging and frame.StopMovingOrSizing then frame:StopMovingOrSizing() end
    directPreviewDragging = false
    frame:SetScript("OnDragStart", nil)
    frame:SetScript("OnDragStop", nil)
    if frame.RegisterForDrag then frame:RegisterForDrag() end
    if frame.EnableMouse then frame:EnableMouse(false) end
    if frame.SetMovable then frame:SetMovable(false) end
    ApplyRuntimeLayer(frame)
    return true
end

local function DetachDirectPreviewCombatEvent()
    if directPreviewEventRegistered and YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(DirectPreviewEventOwner)
    end
    directPreviewEventRegistered = false
end

local function OnDirectPreviewCombatStart()
    if not directPreviewActive then return end
    directPreviewActive = false
    SetDirectPreviewDragEnabled(false)
    DetachDirectPreviewCombatEvent()
    CombatTimer:RefreshRuntime()
end

local function AttachDirectPreviewCombatEvent()
    if directPreviewEventRegistered or not (YUI.Event and YUI.Event.On) then return end
    YUI.Event:On("PLAYER_REGEN_DISABLED", OnDirectPreviewCombatStart, DirectPreviewEventOwner, {
        traceName = "CombatEnhancement:CombatTimer:DirectPreviewCombatStart",
        moduleId = MODULE_ID,
    })
    directPreviewEventRegistered = true
end

local function StopDirectPositionPreview(db, refreshRuntime)
    directPreviewActive = false
    SetDirectPreviewDragEnabled(false)
    DetachDirectPreviewCombatEvent()
    if refreshRuntime ~= false then
        CombatTimer:RefreshRuntime(db)
    end
end

local function ToggleDirectPositionPreview()
    if directPreviewActive then
        StopDirectPositionPreview(GetDB())
        return
    end
    if IsCombatLocked() then return end
    if YUI.Layout and YUI.Layout.IsEditing and YUI.Layout:IsEditing() then return end

    directPreviewActive = true
    ShowPreview(GetDB())
    SetDirectPreviewDragEnabled(true)
    AttachDirectPreviewCombatEvent()
end

local RefreshOutOfCombatDisplay

local function SchedulePostCombatRefresh(delaySeconds)
    if delaySeconds <= 0 or not (C_Timer and type(C_Timer.NewTimer) == "function") then
        return false
    end

    postCombatTimerGeneration = postCombatTimerGeneration + 1
    local generation = postCombatTimerGeneration
    local function OnPostCombatTimer()
        if generation ~= postCombatTimerGeneration then return end
        postCombatTimer = nil
        if IsPlayerInCombat() then return end
        RefreshOutOfCombatDisplay()
    end

    local ok, timer = pcall(C_Timer.NewTimer, delaySeconds, OnPostCombatTimer)
    if not ok or not timer then return false end
    postCombatTimer = timer
    return true
end

RefreshOutOfCombatDisplay = function(db)
    db = GetDB(db)
    CancelPostCombatTimer()
    if layoutPreviewActive or directPreviewActive or IsPlayerInCombat() then return end
    if not (featureActive and db.combatTimerEnabled == true) then
        StopCombatTimer()
        return
    end

    local frame = EnsureFrame()
    if not frame then return end
    local rule = db.combatTimerOutOfCombatRule
    local hasResult = lastCombatElapsed ~= nil and lastCombatEndedAt ~= nil
    local remaining = 0
    if hasResult then
        remaining = OUT_OF_COMBAT_DELAY_SECONDS - math.max(0, GetCurrentTime() - lastCombatEndedAt)
    end

    if rule == "hide" or (rule == "hold3" and (not hasResult or remaining <= 0)) then
        frame:Hide()
        return
    end

    ApplyAppearance(db)
    ApplyFrameAlpha(db.combatTimerOutOfCombatAlpha / 100)
    if rule == "always_reset3" and (not hasResult or remaining <= 0) then
        RenderSeconds(0, db)
    else
        RenderSeconds(lastCombatElapsed or 0, db)
    end
    frame:Show()

    if hasResult and remaining > 0 and (rule == "hold3" or rule == "always_reset3") then
        if not SchedulePostCombatRefresh(remaining) then
            if rule == "hold3" then
                frame:Hide()
            else
                RenderSeconds(0, db)
            end
        end
    end
end

local function StartCombatTimer(db)
    if directPreviewActive then
        directPreviewActive = false
        SetDirectPreviewDragEnabled(false)
        DetachDirectPreviewCombatEvent()
    end
    if layoutPreviewActive then
        ShowPreview(db)
        return
    end
    local frame = EnsureFrame()
    if not frame then return end
    db = GetDB(db)
    if not (featureActive and db.combatTimerEnabled == true) then
        StopCombatTimer()
        return
    end

    CancelPostCombatTimer()
    if combatStartTime == nil then
        combatStartTime = GetCurrentTime()
        lastCombatElapsed = nil
        lastCombatEndedAt = nil
        lastRenderedText = nil
    end
    activeRuntimeDB = db
    ApplyAppearance(db)
    ApplyFrameAlpha(1)
    RenderSeconds(GetCurrentTime() - combatStartTime, db)
    frame:Show()

    if not combatTicker and C_Timer and type(C_Timer.NewTicker) == "function" then
        local ok, ticker = pcall(C_Timer.NewTicker, 1, OnCombatTicker)
        if ok then combatTicker = ticker end
    end
end

local function FinishCombatTimer(db)
    db = GetDB(db)
    if combatStartTime ~= nil then
        local endedAt = GetCurrentTime()
        lastCombatElapsed = math.max(0, endedAt - combatStartTime)
        lastCombatEndedAt = endedAt
    end
    CancelCombatTicker()
    combatStartTime = nil
    activeRuntimeDB = nil
    lastRenderedText = nil
    RefreshOutOfCombatDisplay(db)
end

local function DetachEvents()
    if eventsRegistered and YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(EventOwner)
    end
    eventsRegistered = false
end

local function OnRuntimeEvent(eventName)
    if eventName == "PLAYER_REGEN_DISABLED" then
        StartCombatTimer()
    elseif eventName == "PLAYER_REGEN_ENABLED" then
        FinishCombatTimer()
    elseif eventName == "PLAYER_ENTERING_WORLD" then
        if IsPlayerInCombat() then
            StartCombatTimer()
        elseif combatStartTime ~= nil then
            FinishCombatTimer()
        else
            RefreshOutOfCombatDisplay()
        end
    end
end

local function AttachEvents()
    if eventsRegistered or not (YUI.Event and YUI.Event.On) then return end
    for _, eventName in ipairs({
        "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
    }) do
        YUI.Event:On(eventName, OnRuntimeEvent, EventOwner, {
            traceName = "CombatEnhancement:CombatTimer:" .. eventName,
            moduleId = MODULE_ID,
        })
    end
    eventsRegistered = true
end

local function RefreshEventState(db)
    db = GetDB(db)
    if featureActive and db.combatTimerEnabled == true then
        AttachEvents()
    else
        DetachEvents()
    end
end

if cpuWatchdog and cpuWatchdog.RegisterProbe then
    cpuWatchdog:RegisterProbe("component.combat-timer", {
        localeKey = "cpu_watch.probe.combat_timer",
        kind = "function",
        getTarget = function() return OnCombatTicker end,
        snapshot = function()
            return {
                running = combatTicker ~= nil,
                postCombatPending = postCombatTimer ~= nil,
                visible = timerFrame and timerFrame:IsShown() == true or false,
                listener = eventsRegistered == true,
            }
        end,
    })
end

local function OpenCombatTimerSettings()
    if CombatEnhancement.OpenSettingsTab then
        return CombatEnhancement:OpenSettingsTab("combatTimer")
    end
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

local function OpenLayoutEditMode()
    if IsCombatLocked() then return end
    if directPreviewActive then StopDirectPositionPreview(GetDB(), false) end
    layoutEditRequested = true
    layoutPreviewActive = true
    EnsureFrame()
    RegisterLayout()
    ShowPreview(GetDB())
    local opened = false
    if YUI.Layout and YUI.Layout.OpenEditMode then
        opened = YUI.Layout:OpenEditMode(FEATURE_KEY) == true
    end
    if opened and YUI.Layout and YUI.Layout.RefreshFrame then
        YUI.Layout:RefreshFrame(LAYOUT_ID)
    end
    if opened and YUI.Layout and YUI.Layout.SelectFrame then
        YUI.Layout:SelectFrame(LAYOUT_ID, true)
    end
    layoutEditRequested = false
    if not opened then
        layoutPreviewActive = false
        CombatTimer:RefreshRuntime()
    end
end

function RegisterLayout()
    if registeringLayout then return end
    registeringLayout = true
    local frame = EnsureFrame()
    if not frame then
        registeringLayout = false
        return
    end
    if not (YUI.Layout and YUI.Layout.RegisterFrame) then
        ApplyDefaultPoint(frame)
        registeringLayout = false
        return
    end
    if layoutRegistered then
        registeringLayout = false
        return
    end

    YUI.Layout:RegisterFrame(LAYOUT_ID, {
        frame = frame,
        title = T("layout.combat_timer", "战斗计时"),
        category = "component",
        defaultPlacement = GetDefaultPlacement,
        movable = true,
        snap = true,
        anchorTargets = { "UIParent" },
        minWidth = DEFAULT_FRAME_WIDTH,
        minHeight = DEFAULT_FRAME_HEIGHT,
        isEnabled = function()
            local db = GetDB()
            local editing = YUI.Layout and YUI.Layout.IsEditing and YUI.Layout:IsEditing()
            return layoutEditRequested or layoutPreviewActive or directPreviewActive
                or (db.combatTimerEnabled == true and (featureActive or editing))
        end,
        openPluginSettings = OpenCombatTimerSettings,
        onEnterEditMode = function()
            layoutPreviewActive = true
            ShowPreview(GetDB())
        end,
        onExitEditMode = function()
            layoutEditRequested = false
            layoutPreviewActive = false
            CombatTimer:RefreshRuntime()
        end,
        onApply = function()
            ApplyAppearance(GetDB())
        end,
    })
    layoutRegistered = true
    registeringLayout = false
end

local function BuildFormatOptions()
    return {
        { text = "00:00", value = "plain" },
        { text = "[00:00]", value = "square" },
        { text = "<00:00>", value = "angle" },
        { text = "180s", value = "seconds" },
    }
end

local function BuildTextStyleOptions()
    return {
        { text = T("settings.combat_timer_text_style_none", "无"), value = "none" },
        { text = T("settings.combat_timer_text_style_shadow", "阴影"), value = "shadow" },
        { text = T("settings.combat_timer_text_style_outline_shadow", "描边加阴影"), value = "outline_shadow" },
    }
end

local function BuildOutOfCombatRuleOptions()
    return {
        { text = T("settings.combat_timer_out_of_combat_rule_hide", "脱战消失"), value = "hide" },
        { text = T("settings.combat_timer_out_of_combat_rule_hold3", "脱战后保持3秒"), value = "hold3" },
        { text = T("settings.combat_timer_out_of_combat_rule_always_reset3", "始终显示（3秒后清零）"), value = "always_reset3" },
        { text = T("settings.combat_timer_out_of_combat_rule_always_keep", "始终显示（不清零）"), value = "always_keep" },
    }
end

local function AddAlignedFieldGroup(options, label, fields)
    options[#options + 1] = { type = "divider", label = label, alignLeft = true, width = SECTION_WIDTH }
    options[#options + 1] = {
        type = "custom",
        retainedFields = fields,
        width = SECTION_WIDTH,
        render = function(parent, x, y, width)
            local Settings = YUI.Settings
            if not (Settings and Settings.RenderAlignedFields) then return SECTION_WIDTH, 1 end
            local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                x = x,
                y = y,
                width = math.min(width or SECTION_WIDTH, SECTION_WIDTH),
                columns = 2,
                labelPosition = "top",
                columnGap = COLUMN_GAP,
                labelWidth = LABEL_WIDTH,
                labelGap = LABEL_GAP,
                bodyWidth = BODY_WIDTH,
                valueWidth = INPUT_WIDTH,
                valueGap = VALUE_GAP,
                rowHeight = 32,
                rowGap = 10,
                fields = fields,
            })
            return gridWidth, gridHeight
        end,
    }
end

local function AddAlignedFieldRow(options, fields)
    options[#options + 1] = {
        type = "custom",
        retainedFields = fields,
        width = SECTION_WIDTH,
        render = function(parent, x, y, width)
            local Settings = YUI.Settings
            if not (Settings and Settings.RenderAlignedFields) then return SECTION_WIDTH, 1 end
            local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                x = x,
                y = y,
                width = math.min(width or SECTION_WIDTH, SECTION_WIDTH),
                columns = 1,
                labelPosition = "top",
                columnGap = COLUMN_GAP,
                labelWidth = LABEL_WIDTH,
                labelGap = LABEL_GAP,
                bodyWidth = BODY_WIDTH,
                valueWidth = INPUT_WIDTH,
                valueGap = VALUE_GAP,
                rowHeight = 32,
                rowGap = 10,
                fields = fields,
            })
            return gridWidth, gridHeight
        end,
    }
end

function CombatTimer:BuildOptions(db)
    db = GetDB(db)
    RegisterLayout()
    local options = {}

    AddAlignedFieldRow(options, {
        {
            type = "checkbox",
            label = T("settings.combat_timer_enabled", "启用"),
            get = function() return db.combatTimerEnabled == true end,
            settingsToggle = "combatTimer",
            searchKey = "settings.combat_timer_enabled",
            set = function(value)
                db.combatTimerEnabled = value == true
                CombatTimer:RefreshRuntime(db)
            end,
        },
    })

    AddAlignedFieldGroup(options, T("settings.combat_timer_general", "战斗计时"), {
        {
            type = "button",
            label = "",
            text = T("settings.combat_timer_open_layout", "编辑位置"),
            onClick = OpenLayoutEditMode,
        },
        {
            type = "button",
            label = "",
            text = T("settings.combat_timer_preview_position", "预览并拖动"),
            onClick = ToggleDirectPositionPreview,
        },
        {
            type = "dropdown",
            label = T("settings.combat_timer_format", "文本格式"),
            options = BuildFormatOptions,
            default = DEFAULT_FORMAT,
            get = function() return db.combatTimerFormat end,
            set = function(value)
                db.combatTimerFormat = NormalizeFormat(value)
                lastRenderedText = nil
                CombatTimer:RefreshRuntime(db)
            end,
        },
        {
            type = "dropdown",
            label = T("settings.combat_timer_out_of_combat_rule", "脱战规则"),
            options = BuildOutOfCombatRuleOptions,
            default = DEFAULT_OUT_OF_COMBAT_RULE,
            get = function() return db.combatTimerOutOfCombatRule end,
            set = function(value)
                db.combatTimerOutOfCombatRule = NormalizeOutOfCombatRule(value)
                CombatTimer:RefreshRuntime(db)
            end,
        },
        {
            type = "slider",
            label = T("settings.combat_timer_out_of_combat_alpha", "脱战透明度"),
            min = 0,
            max = 100,
            step = 1,
            get = function() return db.combatTimerOutOfCombatAlpha end,
            set = function(value)
                db.combatTimerOutOfCombatAlpha = math.floor(ClampNumber(
                    value,
                    0,
                    100,
                    DEFAULT_OUT_OF_COMBAT_ALPHA
                ) + 0.5)
                CombatTimer:RefreshRuntime(db)
            end,
        },
        {
            type = "font",
            label = T("settings.combat_timer_font", "字体"),
            default = DEFAULT_FONT,
            prependOptions = function()
                return {
                    {
                        text = T("settings.combat_timer_font_default", "默认"),
                        value = DEFAULT_FONT,
                        fontPath = ResolveFontPath(DEFAULT_FONT),
                    },
                }
            end,
            get = function() return db.combatTimerFont end,
            set = function(value)
                db.combatTimerFont = NormalizeFont(value)
                appliedFont = nil
                CombatTimer:RefreshRuntime(db)
            end,
        },
        {
            type = "slider",
            label = T("settings.combat_timer_font_size", "文本尺寸"),
            min = MIN_FONT_SIZE,
            max = MAX_FONT_SIZE,
            step = 1,
            get = function() return db.combatTimerFontSize end,
            set = function(value)
                db.combatTimerFontSize = math.floor(ClampNumber(value, MIN_FONT_SIZE, MAX_FONT_SIZE, DEFAULT_FONT_SIZE) + 0.5)
                appliedFontSize = nil
                CombatTimer:RefreshRuntime(db)
            end,
        },
        {
            type = "dropdown",
            label = T("settings.combat_timer_text_style", "描边阴影"),
            options = BuildTextStyleOptions,
            default = DEFAULT_TEXT_STYLE,
            get = function() return db.combatTimerTextStyle end,
            set = function(value)
                db.combatTimerTextStyle = NormalizeTextStyle(value)
                appliedTextStyle = nil
                CombatTimer:RefreshRuntime(db)
            end,
        },
        {
            type = "color",
            label = T("settings.combat_timer_color", "文本颜色"),
            layoutPreset = "compactColor",
            default = DEFAULT_COLOR,
            hasAlpha = true,
            get = function() return db.combatTimerColor end,
            set = function(value)
                db.combatTimerColor = NormalizeColor(value)
                CombatTimer:RefreshRuntime(db)
            end,
        },
    })

    return options
end

function CombatTimer:RefreshRuntime(db)
    if YUI.Layout and YUI.Layout.InvalidateAnchorProvider then
        YUI.Layout:InvalidateAnchorProvider(LAYOUT_ID)
    end
    db = GetDB(db)
    EnsureFrame()
    RegisterLayout()
    ApplyAppearance(db)
    RefreshEventState(db)

    if layoutPreviewActive or directPreviewActive then
        ShowPreview(db)
        if directPreviewActive then SetDirectPreviewDragEnabled(true) end
    elseif featureActive and db.combatTimerEnabled == true and IsPlayerInCombat() then
        StartCombatTimer(db)
    elseif featureActive and db.combatTimerEnabled == true then
        RefreshOutOfCombatDisplay(db)
    else
        StopCombatTimer()
    end
end

function CombatTimer:OnFeatureToggle(enabled, db)
    featureActive = enabled == true
    if featureActive then
        self:RefreshRuntime(db)
    else
        layoutEditRequested = false
        layoutPreviewActive = false
        directPreviewActive = false
        SetDirectPreviewDragEnabled(false)
        DetachDirectPreviewCombatEvent()
        DetachEvents()
        StopCombatTimer()
    end
end

function CombatTimer:OnSettingsLeave(db)
    local editing = YUI.Layout and YUI.Layout.IsEditing and YUI.Layout:IsEditing()
    if not editing and not layoutEditRequested then
        layoutPreviewActive = false
    end
    if directPreviewActive then
        directPreviewActive = false
        SetDirectPreviewDragEnabled(false)
    end
    DetachDirectPreviewCombatEvent()
    self:RefreshRuntime(db)
end

CombatEnhancement.CombatTimer = CombatTimer
CombatEnhancement:RegisterSubFeature(CombatTimer)




-- Resolve disabled targets without creating widgets or starting feature runtime.
if YUI.Layout and YUI.Layout.RegisterAnchorProvider then
    local function ResolveColdAnchor(id)
        local components = YUI.Components
        local db = components and components.CopyConfigSnapshot and components:CopyConfigSnapshot(
            CombatEnhancement.CONFIG_KEY, CombatEnhancement.defaults, CombatEnhancement.PRODUCT_ID)
        if not db then return nil end
        db = CombatTimer:NormalizeDB(db)
        local width, height = CombatTimer:MeasureLayoutSize(db.combatTimerFontSize)
        return GetDefaultPlacement(), width, height, 1
    end
    YUI.Layout:RegisterAnchorProvider(LAYOUT_ID, {name=FRAME_NAME, resolve=ResolveColdAnchor})
end
