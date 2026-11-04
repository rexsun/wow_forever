local ADDON_NAME, addonTable = ...
local YUI = _G.YUI
if not (YUI and YUI.Components) then
    YUI = addonTable
end
if not YUI or not YUI.Components then return end

local Components = YUI.Components
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or YUI.ProductId or "suite"
local GUI2 = YUI.GUI2
local S = YUI.Settings
local SystemAPI = YUI.API and YUI.API.System or YUI.WOW_API or {}
local UnitAPI = YUI.API and YUI.API.Unit or YUI.WOW_API or {}
local TalentAPI = YUI.API and YUI.API.Talent or YUI.WOW_API or {}
local SecurityAPI = YUI.API and YUI.API.Security or YUI.API and YUI.API.Combat or YUI.WOW_API or {}
local Icons = YUI.API and YUI.API.Icons
local L = YUI.Locale and YUI.Locale:Get("SpellAlert") or {}
local BuffTimer = YUI.SpellAlert and YUI.SpellAlert.BuffTimer

local FEATURE_KEY = "SpellAlert"
local CONFIG_KEY = "SpellAlert_Config"
local ICON_SCOPE_ID = "settings"
local DISPLAY_CVAR = "displaySpellActivationOverlays"
local OPACITY_CVAR = "spellActivationOverlayOpacity"

local DEFAULT_ALPHA = 100
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local CLASS_ICON_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local CLASS_ICON_TEXCOORD_INSET = 0.07

local FIELD_WIDTH = 320
local FIELD_GAP = 18
local LABEL_WIDTH = 105
local CONTROL_GAP = 0
local SLIDER_VALUE_WIDTH = 52
local SECTION_WIDTH = FIELD_WIDTH * 2 + FIELD_GAP

local ALPHA_GRID_WIDTH = 620
local ALPHA_GRID_COLUMNS = 3
local ALPHA_GRID_GAP = 10
local ALPHA_CELL_HEIGHT = 40
local ALPHA_EDIT_WIDTH = 54
local ALPHA_EDIT_HEIGHT = 26
local ALPHA_ICON_SIZE = 26
local ALPHA_MAX_LETTERS = 3
local BATCH_EDIT_WIDTH = 54
local BATCH_BUTTON_WIDTH = 96

local PREVIEW_BASE_LONG_SIDE = 204.8
local PREVIEW_LAYER_BASE_LEVEL = 100
local PREVIEW_LAYER_FRAME_OFFSET = 18
local PREVIEW_LAYER_MAX_LEVEL = 120

local PREVIEW_SLOTS = { "left", "right", "top" }
local PreviewDefaults = YUI.SpellAlertPreviewDefaults

local defaults = {
    alphaBySpec = {},
    globalScale = 100,
    yOffset = 0,
    textureScale = 100,
    horizontalSpacing = 0,
    verticalSpacing = 0,
}

local ARMOR_GROUPS = {
    { labelKey = "armor.cloth", fallback = "Cloth", classes = { "MAGE", "PRIEST", "WARLOCK" } },
    { labelKey = "armor.leather", fallback = "Leather", classes = { "DEMONHUNTER", "MONK", "ROGUE", "DRUID" } },
    { labelKey = "armor.mail", fallback = "Mail", classes = { "EVOKER", "HUNTER", "SHAMAN" } },
    { labelKey = "armor.plate", fallback = "Plate", classes = { "DEATHKNIGHT", "PALADIN", "WARRIOR" } },
}

local CLASS_TOKENS = {
    "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER",
    "MAGE", "MONK", "PALADIN", "PRIEST", "ROGUE", "SHAMAN",
    "WARLOCK", "WARRIOR",
}

local function GetClassDisplayName(classToken, fallback)
    if YUI.Locale and YUI.Locale.GetClassName then
        return YUI.Locale:GetClassName(classToken, fallback)
    end
    return fallback or classToken or ""
end

local runtimeEnabled = false
local runtimeEventsAttached = false
local frameHooksInstalled = false
local applyingFrameAlpha = false
local managingCVars = false
local restoringCVars = false
local installRetryPending = false
local installRetryCount = 0
local previewEnabled = false
local previewEventsAttached = false
local previewFrame
local previewSettingsOwner
local settingsTab = "layout"
local previewEventOwner = {}
local originalFrameState
local originalCVarState
local Capture = { enabled = false, slashRegistered = false }

local stats = {
    implementationType = "native-enhanced",
    frameHooksInstalled = false,
    frameHookFailures = 0,
    hookAttempts = 0,
    refreshes = 0,
    overlayRefreshes = 0,
    missingFrame = 0,
    currentAlpha = 1,
    cvarWrites = 0,
    cvarWriteFailures = 0,
    cvarRestores = 0,
    previewToggles = 0,
    previewSelections = 0,
    previewCombatBlocks = 0,
    captureEvents = 0,
}

local function T(key, fallback, ...)
    local value = L and L[key]
    if not value or value == "" or value == key then value = fallback or key end
    if select("#", ...) > 0 then
        return string.format(value, ...)
    end
    return value
end

function Capture:Print(message)
    message = tostring(message or "")
    if YUI and type(YUI.Print) == "function" then
        YUI:Print(message)
    elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(message)
    end
end

function Capture:FormatValue(value)
    if value == nil then return "nil" end
    if type(value) == "number" and value ~= math.floor(value) then
        return string.format("%.3f", value)
    end
    return tostring(value)
end

local function ClampNumber(value, minValue, maxValue, fallback)
    value = tonumber(value)
    if value == nil then return fallback end
    value = math.floor(value + 0.5)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function ClampPercent(value, fallback)
    return ClampNumber(value, 0, 100, fallback)
end

local function UseClassicPreviewTextures()
    return YUI.IsMists == true or YUI.IsWrath == true or YUI.IsForever == true
end

local function NormalizeDB(db)
    db = type(db) == "table" and db or {}
    if BuffTimer then BuffTimer.Normalize(db) end
    if type(db.alphaBySpec) ~= "table" then db.alphaBySpec = {} end
    db.globalScale = ClampNumber(db.globalScale, 50, 200, defaults.globalScale)
    db.yOffset = ClampNumber(db.yOffset, -300, 300, defaults.yOffset)
    db.textureScale = ClampNumber(db.textureScale, 50, 200, defaults.textureScale)
    db.horizontalSpacing = ClampNumber(db.horizontalSpacing, -200, 200, defaults.horizontalSpacing)
    db.verticalSpacing = ClampNumber(db.verticalSpacing, -200, 200, defaults.verticalSpacing)

    for key, value in pairs(db.alphaBySpec) do
        local normalized = ClampPercent(value, nil)
        if normalized == nil then
            db.alphaBySpec[key] = nil
        else
            db.alphaBySpec[key] = normalized
        end
    end

    return db
end

local function GetDB()
    if Components and Components.EnsureConfig then
        return NormalizeDB(Components:EnsureConfig(CONFIG_KEY, defaults, PRODUCT_ID) or defaults)
    end
    return NormalizeDB(defaults)
end

local function GetPlayerClassToken()
    local _, classToken
    if UnitAPI.UnitClass then
        _, classToken = UnitAPI.UnitClass("player")
    elseif UnitClass then
        _, classToken = UnitClass("player")
    end
    return classToken or "UNKNOWN"
end

local function BuildSpecKey(classToken, specID)
    return tostring(classToken or "UNKNOWN") .. ":" .. tostring(specID or 0)
end

local function GetActiveSpecKey()
    local classToken = GetPlayerClassToken()
    if (TalentAPI.GetCurrentConfigurationSpecializationInfo or TalentAPI.GetCurrentSpecializationInfo) then
        local info = (TalentAPI.GetCurrentConfigurationSpecializationInfo or TalentAPI.GetCurrentSpecializationInfo)()
        if type(info) == "table" then
            return BuildSpecKey(info.classFile or classToken, info.specID or info.specIndex or info.groupIndex or 0)
        end
    end

    local specIndex = TalentAPI.GetSpecialization and TalentAPI.GetSpecialization() or GetSpecialization and GetSpecialization()
    if specIndex then
        local specID = TalentAPI.GetSpecializationInfo and TalentAPI.GetSpecializationInfo(specIndex)
            or GetSpecializationInfo and GetSpecializationInfo(specIndex)
        return BuildSpecKey(classToken, specID or specIndex)
    end
    return BuildSpecKey(classToken, 0)
end

function Capture:OnEvent(event, spellID, overlayFileDataID, locationType, scale, r, g, b)
    if event ~= "SPELL_ACTIVATION_OVERLAY_SHOW" or not self.enabled then return end

    stats.captureEvents = (stats.captureEvents or 0) + 1
    self:Print(T(
        "capture.event",
        "|cff66c6ffSpellAlert Capture|r spec=%s spellID=%s fileDataID=%s location=%s scale=%s rgb=%s,%s,%s",
        GetActiveSpecKey(),
        self:FormatValue(spellID),
        self:FormatValue(overlayFileDataID),
        self:FormatValue(locationType),
        self:FormatValue(scale),
        self:FormatValue(r),
        self:FormatValue(g),
        self:FormatValue(b)
    ))
end

function Capture:EnsureFrame()
    if self.frame then return self.frame end
    if not CreateFrame then return nil end

    self.frame = CreateFrame("Frame")
    self.frame:SetScript("OnEvent", function(_, event, ...)
        Capture:OnEvent(event, ...)
    end)
    return self.frame
end

function Capture:PrintHelp()
    self:Print(T(
        "capture.help",
        "SpellAlert capture: /yui spellalert capture, /yui spellalert capture off, /yui spellalert status"
    ))
end

function Capture:PrintStatus()
    self:Print(T(
        self.enabled and "capture.status_on" or "capture.status_off",
        self.enabled and "SpellAlert capture is enabled." or "SpellAlert capture is disabled."
    ))
end

function Capture:SetEnabled(enabled)
    enabled = enabled == true
    local frame = self:EnsureFrame()
    if not frame then
        self:Print(T("capture.unavailable", "SpellAlert capture is unavailable in this client state."))
        return false
    end

    if self.enabled == enabled then
        self:PrintStatus()
        return true
    end

    self.enabled = enabled
    stats.captureEnabled = self.enabled
    if self.enabled then
        frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_SHOW")
        self:Print(T("capture.enabled", "SpellAlert capture enabled. Trigger a spell alert to print overlay data."))
    else
        frame:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_SHOW")
        self:Print(T("capture.disabled", "SpellAlert capture disabled."))
    end
    return true
end

function Capture:HandleSlashArgs(msg, direct)
    local text = tostring(msg or ""):lower():match("^%s*(.-)%s*$") or ""
    if not direct then
        if text == "dev clean" then
            return self:CleanPreviewMaterials()
        end
        if text == "spellalert" or text == "spell-alert" then
            text = "status"
        else
            local args = text:match("^spellalert%s+(.+)$") or text:match("^spell%-alert%s+(.+)$")
            if not args then return false end
            text = args
        end
    end

    if text == "" or text == "help" or text == "capture help" then
        self:PrintHelp()
    elseif text == "capture" or text == "capture on" or text == "on" then
        self:SetEnabled(true)
    elseif text == "capture off" or text == "off" then
        self:SetEnabled(false)
    elseif text == "capture status" or text == "status" then
        self:PrintStatus()
    else
        self:PrintHelp()
    end
    return true
end

function Capture:RegisterSlashCommand()
    if self.slashRegistered then return end
    self.slashRegistered = true

    local previousSlashHandler = YUI.HandleSlashCommand
    function YUI:HandleSlashCommand(msg)
        if Capture:HandleSlashArgs(msg, false) then
            return true
        end
        if previousSlashHandler then
            return previousSlashHandler(self, msg)
        end
        return false
    end

    if SlashCmdList then
        _G.SLASH_YUISPELLALERT1 = _G.SLASH_YUISPELLALERT1 or "/yuispellalert"
        SlashCmdList.YUISPELLALERT = function(msg)
            Capture:HandleSlashArgs(msg, true)
        end
    end
end

local function GetConfiguredAlpha(db)
    db = db or GetDB()
    local values = type(db.alphaBySpec) == "table" and db.alphaBySpec or nil
    local alpha = values and values[GetActiveSpecKey()] or nil
    return ClampPercent(alpha, DEFAULT_ALPHA) / 100
end

local function GetCVarValue(name)
    if not name then return nil end
    if SystemAPI.GetCVarSafe then
        return SystemAPI.GetCVarSafe(name)
    elseif SystemAPI.GetCVar then
        local ok, value = pcall(SystemAPI.GetCVar, name)
        if ok then return value end
    elseif C_CVar and C_CVar.GetCVar then
        local ok, value = pcall(C_CVar.GetCVar, name)
        if ok then return value end
    elseif GetCVar then
        local ok, value = pcall(GetCVar, name)
        if ok then return value end
    end
    return nil
end

local function GetCVarBoolValue(name)
    if not name then return false end
    if SystemAPI.GetCVarBool then
        local ok, value = pcall(SystemAPI.GetCVarBool, name)
        if ok and value ~= nil then return value and true or false end
    elseif C_CVar and C_CVar.GetCVarBool then
        local ok, value = pcall(C_CVar.GetCVarBool, name)
        if ok and value ~= nil then return value and true or false end
    elseif GetCVarBool then
        local ok, value = pcall(GetCVarBool, name)
        if ok and value ~= nil then return value and true or false end
    end

    local value = GetCVarValue(name)
    return value == true or value == 1 or value == "1" or value == "true"
end

local function SetCVarValue(name, value)
    if not name then return false end
    local ok = false
    if SystemAPI.SetCVarSafe then
        ok = SystemAPI.SetCVarSafe(name, value) == true
    elseif SystemAPI.SetCVar then
        local success, result = pcall(SystemAPI.SetCVar, name, value)
        ok = success and result ~= false
    elseif C_CVar and C_CVar.SetCVar then
        local success, result = pcall(C_CVar.SetCVar, name, tostring(value))
        ok = success and result ~= false
    elseif SetCVar then
        local success, result = pcall(SetCVar, name, value)
        ok = success and result ~= false
    end

    if ok then
        stats.cvarWrites = (stats.cvarWrites or 0) + 1
    else
        stats.cvarWriteFailures = (stats.cvarWriteFailures or 0) + 1
    end
    return ok
end

local function CaptureOriginalCVarState()
    if originalCVarState then return end
    originalCVarState = {
        display = GetCVarValue(DISPLAY_CVAR),
        opacity = GetCVarValue(OPACITY_CVAR),
    }
end

local function EnsureOverlayCVarsEnabled()
    if not runtimeEnabled or managingCVars or restoringCVars then return end
    CaptureOriginalCVarState()

    managingCVars = true
    local changed = false
    local opacity = tonumber(GetCVarValue(OPACITY_CVAR))
    if opacity ~= nil and opacity <= 0 then
        changed = SetCVarValue(OPACITY_CVAR, "1") or changed
    end
    if not GetCVarBoolValue(DISPLAY_CVAR) then
        changed = SetCVarValue(DISPLAY_CVAR, "1") or changed
    end
    if changed then
        stats.cvarEnforced = (stats.cvarEnforced or 0) + 1
    end
    managingCVars = false
end

local function RestoreOverlayCVars()
    if not originalCVarState then return end

    restoringCVars = true
    if originalCVarState.opacity ~= nil then
        SetCVarValue(OPACITY_CVAR, originalCVarState.opacity)
    end
    if originalCVarState.display ~= nil then
        SetCVarValue(DISPLAY_CVAR, originalCVarState.display)
    end
    originalCVarState = nil
    stats.cvarRestores = (stats.cvarRestores or 0) + 1
    restoringCVars = false
end

local function GetNativeFrameAlpha(frame)
    if Settings and Settings.GetValue then
        local ok, value = pcall(Settings.GetValue, OPACITY_CVAR)
        value = ok and tonumber(value) or nil
        if value then
            if value < 0 then value = 0 end
            if value > 1 then value = 1 end
            return value
        end
    end

    local value = tonumber(GetCVarValue(OPACITY_CVAR))
    if value then
        if value < 0 then value = 0 end
        if value > 1 then value = 1 end
        return value
    end

    if originalFrameState and originalFrameState.alpha ~= nil then
        return originalFrameState.alpha
    end
    return frame and frame.GetAlpha and frame:GetAlpha() or 1
end

local function CopyFramePoints(frame)
    local points = {}
    if frame and frame.GetNumPoints and frame.GetPoint then
        for index = 1, frame:GetNumPoints() do
            local point, relativeTo, relativePoint, x, y = frame:GetPoint(index)
            points[#points + 1] = {
                point = point,
                relativeTo = relativeTo,
                relativePoint = relativePoint,
                x = x or 0,
                y = y or 0,
            }
        end
    end
    return points
end

local function CaptureOriginalFrameState(frame)
    if originalFrameState or not frame then return end
    originalFrameState = {
        alpha = frame.GetAlpha and frame:GetAlpha() or 1,
        scale = frame.GetScale and frame:GetScale() or 1,
        points = CopyFramePoints(frame),
    }
end

local function RestoreOriginalFrameState(frame)
    if not frame then return end
    applyingFrameAlpha = true
    if frame.SetAlpha then frame:SetAlpha(GetNativeFrameAlpha(frame)) end
    applyingFrameAlpha = false

    if originalFrameState then
        if frame.SetScale then frame:SetScale(originalFrameState.scale or 1) end
        if frame.ClearAllPoints then frame:ClearAllPoints() end
        local restoredPoint = false
        for _, point in ipairs(originalFrameState.points or {}) do
            if point.point and frame.SetPoint then
                frame:SetPoint(point.point, point.relativeTo, point.relativePoint, point.x or 0, point.y or 0)
                restoredPoint = true
            end
        end
        if not restoredPoint and frame.SetPoint and UIParent then
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    elseif frame.SetScale then
        frame:SetScale(1)
    end
end

local function ApplyFrameAlpha(frame, db)
    if not (runtimeEnabled and frame and frame.SetAlpha) then return end
    local alpha = GetConfiguredAlpha(db)
    stats.currentAlpha = alpha
    applyingFrameAlpha = true
    frame:SetAlpha(alpha)
    applyingFrameAlpha = false
end

local function ApplyFrameLayout(frame, db)
    if not (runtimeEnabled and frame and UIParent) then return end
    CaptureOriginalFrameState(frame)
    db = db or GetDB()

    if frame.SetScale then
        frame:SetScale((ClampNumber(db.globalScale, 50, 200, defaults.globalScale) or defaults.globalScale) / 100)
    end
    if frame.ClearAllPoints and frame.SetPoint then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, ClampNumber(db.yOffset, -300, 300, defaults.yOffset) or defaults.yOffset)
    end
end

local function PositionEquals(position, key)
    return Enum and Enum.ScreenLocationType and position == Enum.ScreenLocationType[key]
end

local function GetSpacingOffset(position, db)
    local x, y = 0, 0
    local horizontal = ClampNumber(db and db.horizontalSpacing, -200, 200, defaults.horizontalSpacing) or defaults.horizontalSpacing
    local vertical = ClampNumber(db and db.verticalSpacing, -200, 200, defaults.verticalSpacing) or defaults.verticalSpacing

    if PositionEquals(position, "Left") or PositionEquals(position, "LeftOutside") or PositionEquals(position, "TopLeft") then
        x = -horizontal
    elseif PositionEquals(position, "Right") or PositionEquals(position, "RightOutside") or PositionEquals(position, "TopRight") then
        x = horizontal
    end

    if PositionEquals(position, "Top") or PositionEquals(position, "TopLeft") or PositionEquals(position, "TopRight") then
        y = vertical
    elseif PositionEquals(position, "Bottom") then
        y = -vertical
    end

    return x, y
end

local RefreshPreviewLayer
local RefreshPreviewInteractivity
local RefreshPreviewControlsState

local function IsInCombatLockdownSafe()
    if SecurityAPI and SecurityAPI.InCombatLockdown then
        return SecurityAPI.InCombatLockdown() == true
    end
    return InCombatLockdown and InCombatLockdown() == true or false
end

local function GetPreviewLayerBaseLevel(anchor)
    local baseLevel = PREVIEW_LAYER_BASE_LEVEL
    local function IncludeLevel(frame)
        local frameType = type(frame)
        if (frameType == "table" or frameType == "userdata") and frame.GetFrameLevel then
            local ok, level = pcall(frame.GetFrameLevel, frame)
            level = ok and tonumber(level) or nil
            if level and level > baseLevel then
                baseLevel = level
            end
        end
    end

    local elements = YUI.Settings and YUI.Settings.Elements
    if type(elements) == "table" then
        for _, frame in pairs(elements) do
            IncludeLevel(frame)
        end
    end
    IncludeLevel(previewSettingsOwner)

    local current = anchor
    local depth = 0
    while current and depth < 12 do
        IncludeLevel(current)
        current = current.GetParent and current:GetParent() or nil
        depth = depth + 1
    end

    return baseLevel
end

local function ApplyPreviewLayer(frame, offset, anchor)
    if not frame then return end
    if frame.SetFrameStrata then
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
    end
    if frame.SetFrameLevel then
        local level = GetPreviewLayerBaseLevel(anchor) + (offset or 0)
        frame:SetFrameLevel(math.min(level, PREVIEW_LAYER_MAX_LEVEL))
    end
end

local function GetPreviewBaseSize()
    local frame = _G.SpellActivationOverlayFrame
    local width = frame and frame.GetWidth and frame:GetWidth() or nil
    if not width or width <= 0 then
        width = PREVIEW_BASE_LONG_SIDE
    end
    return width, width * 0.5
end

local function GetPreviewSlotTextureCoords(slot)
    if slot == "right" then
        return 1, 0, 0, 1
    end
    return 0, 1, 0, 1
end

local function StopAnimationGroup(group)
    if group and group.Stop then
        group:Stop()
    end
end

local function IsAnimationGroupPlaying(group)
    return group and group.IsPlaying and group:IsPlaying()
end

local function StopPreviewSlotAnimation(button)
    if not button then return end
    StopAnimationGroup(button.previewFade)
    StopAnimationGroup(button.previewPulse)
    if button.SetAlpha then button:SetAlpha(1) end
    if button.SetScale then button:SetScale(1) end
end

local function EnsurePreviewSlotAnimations(button)
    if not button or button.previewAnimationUnsupported then return false end
    if button.previewFade and button.previewPulse then return true end
    if not button.CreateAnimationGroup then
        button.previewAnimationUnsupported = true
        return false
    end

    local ok = pcall(function()
        local fade = button:CreateAnimationGroup()
        local alpha = fade:CreateAnimation("Alpha")
        alpha:SetOrder(1)
        alpha:SetDuration(0.2)
        if alpha.SetFromAlpha then alpha:SetFromAlpha(0) end
        if alpha.SetToAlpha then alpha:SetToAlpha(1) end
        fade:SetScript("OnPlay", function()
            button:SetAlpha(0)
        end)
        fade:SetScript("OnFinished", function()
            button:SetAlpha(1)
            if previewEnabled and not IsInCombatLockdownSafe() and button:IsShown() and button.previewPulse then
                button.previewPulse:Play()
            end
        end)

        local pulse = button:CreateAnimationGroup()
        if pulse.SetLooping then pulse:SetLooping("REPEAT") end

        local grow = pulse:CreateAnimation("Scale")
        grow:SetOrder(1)
        grow:SetDuration(0.5)
        grow:SetScale(1.08, 1.08)
        if grow.SetSmoothing then grow:SetSmoothing("IN_OUT") end

        local shrink = pulse:CreateAnimation("Scale")
        shrink:SetOrder(2)
        shrink:SetDuration(0.5)
        shrink:SetScale(0.9259, 0.9259)
        if shrink.SetSmoothing then shrink:SetSmoothing("IN_OUT") end

        button.previewFade = fade
        button.previewPulse = pulse
    end)

    if not ok then
        button.previewAnimationUnsupported = true
        StopPreviewSlotAnimation(button)
        return false
    end

    return true
end

local function StartPreviewSlotAnimation(button)
    if not button or button.gui2Disabled or IsInCombatLockdownSafe() then
        StopPreviewSlotAnimation(button)
        return
    end
    if button.IsShown and not button:IsShown() then
        StopPreviewSlotAnimation(button)
        return
    end
    if IsAnimationGroupPlaying(button.previewFade) or IsAnimationGroupPlaying(button.previewPulse) then
        return
    end
    if not EnsurePreviewSlotAnimations(button) then return end
    button:SetAlpha(1)
    button:SetScale(1)
    if button.previewFade and button.previewFade.Play then
        button.previewFade:Play()
    elseif button.previewPulse and button.previewPulse.Play then
        button.previewPulse:Play()
    end
end

local function StopPreviewAnimations()
    if not previewFrame then return end
    if previewFrame.slots then
        for _, slot in ipairs(PREVIEW_SLOTS) do
            StopPreviewSlotAnimation(previewFrame.slots[slot])
        end
    end
    if previewFrame.extraSideOverlays then
        StopPreviewSlotAnimation(previewFrame.extraSideOverlays.left)
        StopPreviewSlotAnimation(previewFrame.extraSideOverlays.right)
    end
end

local function StartPreviewAnimations()
    if not previewFrame then return end
    if previewFrame.slots then
        for _, slot in ipairs(PREVIEW_SLOTS) do
            StartPreviewSlotAnimation(previewFrame.slots[slot])
        end
    end
    if previewFrame.extraSideOverlays then
        StartPreviewSlotAnimation(previewFrame.extraSideOverlays.left)
        StartPreviewSlotAnimation(previewFrame.extraSideOverlays.right)
    end
end

local function CreatePreviewSlot(parent, slot)
    local frame = GUI2:CreateFrame(parent, { width = 64, height = 64, mouse = false })
    frame.slot = slot
    if frame.EnableMouse then frame:EnableMouse(false) end
    local texture = GUI2:CreateTexture(frame, { layer = "ARTWORK" })
    texture:SetAllPoints(frame)
    texture:SetVertexColor(1, 1, 1, 1)
    frame.texture = texture
    return frame
end

local function CreatePreviewExtraSideOverlay(parent, side)
    local frame = GUI2:CreateFrame(parent, { width = 64, height = 64 })
    frame.previewExtraSide = side
    if frame.EnableMouse then frame:EnableMouse(false) end

    local texture = GUI2:CreateTexture(frame, { layer = "ARTWORK" })
    texture:SetAllPoints(frame)
    texture:SetVertexColor(1, 1, 1, 1)
    frame.texture = texture
    frame:Hide()
    return frame
end

local function EnsurePreviewFrame()
    if previewFrame then return previewFrame end
    if not (UIParent and GUI2 and GUI2.CreateFrame and GUI2.CreateTexture) then return nil end
    if IsInCombatLockdownSafe() then return nil end

    local frame = GUI2:CreateFrame(UIParent, { width = PREVIEW_BASE_LONG_SIDE, height = PREVIEW_BASE_LONG_SIDE })
    ApplyPreviewLayer(frame, PREVIEW_LAYER_FRAME_OFFSET)
    if frame.EnableMouse then frame:EnableMouse(false) end
    frame:Hide()
    frame.slots = {}

    for _, slot in ipairs(PREVIEW_SLOTS) do
        frame.slots[slot] = CreatePreviewSlot(frame, slot)
    end
    frame.extraSideOverlays = {
        left = CreatePreviewExtraSideOverlay(frame, "left"),
        right = CreatePreviewExtraSideOverlay(frame, "right"),
    }

    previewFrame = frame
    return previewFrame
end

local function LayoutPreviewSlot(button, slot, longSide, shortSide, db)
    if not button then return end
    local textureScale = (ClampNumber(db and db.textureScale, 50, 200, defaults.textureScale) or defaults.textureScale) / 100
    local horizontal = ClampNumber(db and db.horizontalSpacing, -200, 200, defaults.horizontalSpacing) or defaults.horizontalSpacing
    local vertical = ClampNumber(db and db.verticalSpacing, -200, 200, defaults.verticalSpacing) or defaults.verticalSpacing
    local width = (slot == "left" or slot == "right") and shortSide or longSide
    local height = (slot == "left" or slot == "right") and longSide or shortSide

    button:SetSize(width * textureScale, height * textureScale)
    button:ClearAllPoints()
    if slot == "left" then
        button:SetPoint("RIGHT", previewFrame, "LEFT", -horizontal, 0)
    elseif slot == "right" then
        button:SetPoint("LEFT", previewFrame, "RIGHT", horizontal, 0)
    elseif slot == "top" then
        button:SetPoint("BOTTOM", previewFrame, "TOP", 0, vertical)
    end
end

local function LayoutPreviewExtraSideOverlay(overlay, side, longSide, shortSide, db)
    if not overlay then return end
    local textureScale = (ClampNumber(db and db.textureScale, 50, 200, defaults.textureScale) or defaults.textureScale) / 100
    local horizontal = ClampNumber(db and db.horizontalSpacing, -200, 200, defaults.horizontalSpacing) or defaults.horizontalSpacing
    overlay:SetSize(shortSide * textureScale, longSide * textureScale)
    overlay:ClearAllPoints()
    if side == "left" then
        overlay:SetPoint("RIGHT", previewFrame, "LEFT", -shortSide - horizontal, 0)
    else
        overlay:SetPoint("LEFT", previewFrame, "RIGHT", shortSide + horizontal, 0)
    end
end

local function RefreshPreviewExtraSideOverlays(frame, materials, longSide, shortSide, db)
    local overlays = frame and frame.extraSideOverlays
    if not overlays then return end

    for side, overlay in pairs(overlays) do
        local textureID = materials[side == "left" and "extraLeft" or "extraRight"]
        overlay.previewTextureID = textureID
        if textureID then
            LayoutPreviewExtraSideOverlay(overlay, side, longSide, shortSide, db)
            overlay.texture:SetTexture(textureID)
            overlay.texture:SetTexCoord(GetPreviewSlotTextureCoords(side))
            overlay.texture:SetAlpha(1)
            overlay:Show()
        else
            StopPreviewSlotAnimation(overlay)
            overlay:Hide()
        end
    end
end

RefreshPreviewLayer = function(reason)
    if not previewEnabled then return false end
    local frame = EnsurePreviewFrame()
    if not frame then return false end

    local db = GetDB()
    local longSide, shortSide = GetPreviewBaseSize()
    local materials = PreviewDefaults:GetLayout(GetActiveSpecKey(), UseClassicPreviewTextures())
    local scale = (ClampNumber(db.globalScale, 50, 200, defaults.globalScale) or defaults.globalScale) / 100
    local yOffset = ClampNumber(db.yOffset, -300, 300, defaults.yOffset) or defaults.yOffset

    frame:SetSize(longSide, longSide)
    ApplyPreviewLayer(frame, PREVIEW_LAYER_FRAME_OFFSET)
    frame:SetScale(scale)
    frame:SetAlpha(GetConfiguredAlpha(db))
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, yOffset)

    for _, slot in ipairs(PREVIEW_SLOTS) do
        local button = frame.slots and frame.slots[slot]
        if button then
            LayoutPreviewSlot(button, slot, longSide, shortSide, db)
            local textureID = materials[slot]
            button.previewTextureID = textureID
            if textureID then
                button.texture:SetTexture(textureID)
                button.texture:SetTexCoord(GetPreviewSlotTextureCoords(slot))
                button.texture:SetAlpha(1)
                button:Show()
                if BuffTimer then BuffTimer.Preview(button, slot, db.countdown, frame) end
            else
                StopPreviewSlotAnimation(button)
                button:Hide()
                if button.yuiBuffTimerPreview then button.yuiBuffTimerPreview:Hide() end
            end
        end
    end
    RefreshPreviewExtraSideOverlays(frame, materials, longSide, shortSide, db)

    frame:Show()
    RefreshPreviewInteractivity()
    RefreshPreviewControlsState()
    stats.previewRefreshes = (stats.previewRefreshes or 0) + 1
    return true
end

local function HidePreviewLayer()
    StopPreviewAnimations()
    if previewFrame then
        previewFrame:Hide()
    end
end

local function SetPreviewEnabled(enabled, reason)
    enabled = enabled == true
    if enabled and IsInCombatLockdownSafe() then
        stats.previewCombatBlocks = (stats.previewCombatBlocks or 0) + 1
        RefreshPreviewControlsState()
        return false
    end

    if previewEnabled == enabled then
        if enabled then
            RefreshPreviewLayer(reason or "preview-refresh")
        else
            HidePreviewLayer()
        end
        RefreshPreviewControlsState()
        return true
    end

    previewEnabled = enabled
    stats.previewToggles = (stats.previewToggles or 0) + 1
    if previewEnabled then
        RefreshPreviewLayer(reason or "preview-start")
    else
        HidePreviewLayer()
    end
    RefreshPreviewControlsState()
    return true
end

RefreshPreviewInteractivity = function()
    if previewEnabled and not IsInCombatLockdownSafe() then
        StartPreviewAnimations()
    else
        StopPreviewAnimations()
    end
end

local function CaptureOverlayBase(overlay)
    if not overlay then return end
    overlay.yuiSpellAlertBaseWidth = overlay.GetWidth and overlay:GetWidth() or nil
    overlay.yuiSpellAlertBaseHeight = overlay.GetHeight and overlay:GetHeight() or nil
    overlay.yuiSpellAlertBasePoints = CopyFramePoints(overlay)
end

local function RestoreOverlayLayout(overlay)
    if not overlay then return end

    local baseWidth = tonumber(overlay.yuiSpellAlertBaseWidth)
    local baseHeight = tonumber(overlay.yuiSpellAlertBaseHeight)
    if baseWidth and baseHeight and overlay.SetSize then
        overlay:SetSize(baseWidth, baseHeight)
    end

    local points = overlay.yuiSpellAlertBasePoints
    if type(points) == "table" and #points > 0 and overlay.ClearAllPoints and overlay.SetPoint then
        overlay:ClearAllPoints()
        for _, point in ipairs(points) do
            if point.point then
                overlay:SetPoint(point.point, point.relativeTo, point.relativePoint, point.x or 0, point.y or 0)
            end
        end
    end

    overlay.yuiSpellAlertBaseWidth = nil
    overlay.yuiSpellAlertBaseHeight = nil
    overlay.yuiSpellAlertBasePoints = nil
end

local function ApplyOverlayLayout(frame, overlay, position, captureBase, positionOnly)
    if not (runtimeEnabled and frame and overlay) then return end
    if captureBase or not overlay.yuiSpellAlertBasePoints then
        CaptureOverlayBase(overlay)
    end

    local db = GetDB()
    local scale = (ClampNumber(db.textureScale, 50, 200, defaults.textureScale) or defaults.textureScale) / 100
    local baseWidth = tonumber(overlay.yuiSpellAlertBaseWidth)
    local baseHeight = tonumber(overlay.yuiSpellAlertBaseHeight)
    if not positionOnly and baseWidth and baseHeight and overlay.SetSize then
        overlay:SetSize(baseWidth * scale, baseHeight * scale)
    end

    local points = overlay.yuiSpellAlertBasePoints
    if type(points) == "table" and #points > 0 and overlay.ClearAllPoints and overlay.SetPoint then
        local offsetX, offsetY = GetSpacingOffset(position or overlay.position, db)
        offsetX = offsetX + (BuffTimer and BuffTimer.GetInset(overlay) or 0)
        overlay:ClearAllPoints()
        for _, point in ipairs(points) do
            if point.point then
                overlay:SetPoint(
                    point.point,
                    point.relativeTo or frame,
                    point.relativePoint,
                    (point.x or 0) + offsetX,
                    (point.y or 0) + offsetY
                )
            end
        end
    end

    stats.overlayRefreshes = (stats.overlayRefreshes or 0) + 1
end

local function RelayoutTimerOverlay(overlay, position)
    ApplyOverlayLayout(_G.SpellActivationOverlayFrame, overlay, position, false, true)
end

local function RefreshActiveOverlays(frame)
    if not (runtimeEnabled and frame and type(frame.overlaysInUse) == "table") then return end
    for spellID, overlayList in pairs(frame.overlaysInUse) do
        if type(overlayList) == "table" then
            for position, overlay in pairs(overlayList) do
                if overlay and (not overlay.IsShown or overlay:IsShown()) then
                    ApplyOverlayLayout(frame, overlay, position, false)
                    if BuffTimer and not (overlay.animOut and overlay.animOut:IsPlaying()) then
                        BuffTimer.Show(spellID, position, overlay, true)
                    end
                end
            end
        end
    end
end

local function RestoreActiveOverlays(frame)
    if not (frame and type(frame.overlaysInUse) == "table") then return end
    for _, overlayList in pairs(frame.overlaysInUse) do
        if type(overlayList) == "table" then
            for _, overlay in pairs(overlayList) do
                RestoreOverlayLayout(overlay)
            end
        end
    end
end

local function RefreshAll(reason)
    if previewEnabled then
        RefreshPreviewLayer(reason or "refresh")
    end
    if not runtimeEnabled then return false end
    EnsureOverlayCVarsEnabled()
    local frame = _G.SpellActivationOverlayFrame
    if not frame then
        stats.missingFrame = (stats.missingFrame or 0) + 1
        return false
    end
    local db = GetDB()
    stats.refreshes = (stats.refreshes or 0) + 1
    ApplyFrameLayout(frame, db)
    ApplyFrameAlpha(frame, db)
    if BuffTimer then BuffTimer.Configure(frame, db.countdown, runtimeEnabled, RelayoutTimerOverlay) end
    if reason ~= "PLAYER_SPECIALIZATION_CHANGED" and reason ~= "PLAYER_TALENT_UPDATE"
        and reason ~= "ACTIVE_TALENT_GROUP_CHANGED" and reason ~= "ACTIVE_COMBAT_CONFIG_CHANGED" then
        RefreshActiveOverlays(frame)
    end
    if BuffTimer then BuffTimer.LayoutComplete() end
    return true
end

local function GetOverlay(frame, spellID, position)
    local overlays = frame and frame.overlaysInUse
    local overlayList = type(overlays) == "table" and overlays[spellID] or nil
    return type(overlayList) == "table" and overlayList[position] or nil
end

local function InstallFrameHooks(frame)
    if frameHooksInstalled or not frame then return frameHooksInstalled end
    if type(hooksecurefunc) ~= "function" then return false end

    stats.hookAttempts = (stats.hookAttempts or 0) + 1
    local okShow = pcall(hooksecurefunc, frame, "ShowOverlay", function(owner, spellID, texturePath, position)
        if not runtimeEnabled then return end
        local overlay = GetOverlay(owner, spellID, position)
        -- HIDE pauses pulse. A rapid SHOW cancels fade-out without another
        -- OnShow/fade-in, so the native pulse otherwise stays paused.
        if BuffTimer and BuffTimer.IsSupported() and overlay and overlay.pulse and overlay.pulse:IsPaused()
            and not (overlay.animOut and overlay.animOut:IsPlaying())
            and not (overlay.animIn and overlay.animIn:IsPlaying()) then
            overlay.pulse:Play()
        end
        ApplyFrameLayout(owner)
        ApplyFrameAlpha(owner)
        ApplyOverlayLayout(owner, GetOverlay(owner, spellID, position), position, true)
        if BuffTimer then BuffTimer.Show(spellID, position, GetOverlay(owner, spellID, position)) end
    end)
    if not okShow then
        stats.frameHookFailures = (stats.frameHookFailures or 0) + 1
        return false
    end

    if BuffTimer then
        hooksecurefunc(frame, "HideOverlays", function(_, spellID) if runtimeEnabled then BuffTimer.Hide(spellID) end end)
        hooksecurefunc(frame, "HideAllOverlays", function() if runtimeEnabled then BuffTimer.HideAll() end end)
        hooksecurefunc(frame, "ReleaseOverlay", function(_, overlay) if runtimeEnabled then BuffTimer.Release(overlay) end end)
    end

    pcall(hooksecurefunc, frame, "SetAlpha", function(owner)
        if runtimeEnabled and not applyingFrameAlpha then
            ApplyFrameAlpha(owner)
        end
    end)

    frameHooksInstalled = true
    stats.frameHooksInstalled = true
    return true
end

local function TryInstallFrameHooks()
    local frame = _G.SpellActivationOverlayFrame
    if not frame then
        stats.missingFrame = (stats.missingFrame or 0) + 1
        return false
    end
    InstallFrameHooks(frame)
    return true
end

local function ScheduleInstallRetry()
    if installRetryPending or not runtimeEnabled then return end
    if installRetryCount >= 20 then return end
    if not (C_Timer and C_Timer.After) then return end

    installRetryPending = true
    installRetryCount = installRetryCount + 1
    C_Timer.After(0.5, function()
        installRetryPending = false
        if not runtimeEnabled then return end
        if TryInstallFrameHooks() then
            RefreshAll("install-retry")
        else
            ScheduleInstallRetry()
        end
    end)
end

local function OnPreviewRuntimeEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then
        SetPreviewEnabled(false, "preview-combat")
    elseif event == "PLAYER_REGEN_ENABLED" then
        RefreshPreviewInteractivity()
    else
        RefreshPreviewLayer(event or "preview-event")
    end
    RefreshPreviewControlsState()
end

local function AttachPreviewEvents()
    if previewEventsAttached or not (YUI.Event and YUI.Event.On) then return end
    previewEventsAttached = true
    local eventOptions = { traceName = "SpellAlert:preview", moduleId = "component:" .. FEATURE_KEY }
    YUI.Event:On("PLAYER_REGEN_DISABLED", OnPreviewRuntimeEvent, previewEventOwner, eventOptions)
    YUI.Event:On("PLAYER_REGEN_ENABLED", OnPreviewRuntimeEvent, previewEventOwner, eventOptions)
    YUI.Event:On("PLAYER_SPECIALIZATION_CHANGED", OnPreviewRuntimeEvent, previewEventOwner, eventOptions)
    YUI.Event:On("PLAYER_TALENT_UPDATE", OnPreviewRuntimeEvent, previewEventOwner, eventOptions)
    YUI.Event:On("ACTIVE_TALENT_GROUP_CHANGED", OnPreviewRuntimeEvent, previewEventOwner, eventOptions)
    YUI.Event:On("ACTIVE_COMBAT_CONFIG_CHANGED", OnPreviewRuntimeEvent, previewEventOwner, eventOptions)
end

local function DetachPreviewEvents()
    if not previewEventsAttached then return end
    if YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(previewEventOwner)
    end
    previewEventsAttached = false
end

local function AttachRuntimeEvents()
    if runtimeEventsAttached or not (YUI.Event and YUI.Event.On) then return end
    runtimeEventsAttached = true
    local function OnRuntimeEvent(event, ...)
        if not runtimeEnabled then return end
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            OnPreviewRuntimeEvent(event, ...)
            return
        end
        if event == "CVAR_UPDATE" then
            local name = ...
            if name ~= OPACITY_CVAR and name ~= DISPLAY_CVAR then
                return
            end
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_TALENT_UPDATE"
            or event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "ACTIVE_COMBAT_CONFIG_CHANGED" then
            if BuffTimer then BuffTimer.HideAll() end
            OnPreviewRuntimeEvent(event, ...)
        end
        EnsureOverlayCVarsEnabled()
        if TryInstallFrameHooks() then
            RefreshAll(event)
        else
            ScheduleInstallRetry()
        end
    end

    local eventOptions = { traceName = "SpellAlert:refresh", moduleId = "component:" .. FEATURE_KEY }
    YUI.Event:On("YUI_WORLD_READY", OnRuntimeEvent, stats, eventOptions)
    YUI.Event:On("PLAYER_SPECIALIZATION_CHANGED", OnRuntimeEvent, stats, eventOptions)
    YUI.Event:On("PLAYER_TALENT_UPDATE", OnRuntimeEvent, stats, eventOptions)
    YUI.Event:On("CHARACTER_POINTS_CHANGED", OnRuntimeEvent, stats, eventOptions)
    YUI.Event:On("ACTIVE_TALENT_GROUP_CHANGED", OnRuntimeEvent, stats, eventOptions)
    YUI.Event:On("ACTIVE_COMBAT_CONFIG_CHANGED", OnRuntimeEvent, stats, eventOptions)
    YUI.Event:On("SETTINGS_LOADED", OnRuntimeEvent, stats, eventOptions)
    YUI.Event:On("CVAR_UPDATE", OnRuntimeEvent, stats, eventOptions)
    YUI.Event:On("PLAYER_REGEN_DISABLED", OnRuntimeEvent, stats, eventOptions)
    YUI.Event:On("PLAYER_REGEN_ENABLED", OnRuntimeEvent, stats, eventOptions)
end

local function DetachRuntimeEvents()
    if not runtimeEventsAttached then return end
    if YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(stats)
    end
    runtimeEventsAttached = false
end

local function GetClassIconTexCoord(classToken)
    return CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken] or nil
end

local function InsetClassIconTexCoord(texCoord)
    if type(texCoord) ~= "table" then return nil end
    local left = texCoord[1] or 0
    local right = texCoord[2] or 1
    local top = texCoord[3] or 0
    local bottom = texCoord[4] or 1
    local width = right - left
    local height = bottom - top
    local insetX = width * CLASS_ICON_TEXCOORD_INSET
    local insetY = height * CLASS_ICON_TEXCOORD_INSET
    return { left + insetX, right - insetX, top + insetY, bottom - insetY }
end

local function GetClassIcon(classToken)
    local texCoord = GetClassIconTexCoord(classToken)
    if texCoord then
        return CLASS_ICON_TEXTURE, InsetClassIconTexCoord(texCoord), true
    end
    return DEFAULT_ICON, nil, false
end

local function GetClassInfoMap()
    local map = {}
    local classInfos
    if UnitAPI.GetClassInfos then
        classInfos = UnitAPI.GetClassInfos()
    else
        classInfos = {}
        local count = UnitAPI.GetNumClasses and UnitAPI.GetNumClasses() or GetNumClasses and GetNumClasses() or 0
        for index = 1, count do
            local info
            if UnitAPI.GetClassInfo then
                info = UnitAPI.GetClassInfo(index)
            elseif GetClassInfo then
                local className, classFile, classID = GetClassInfo(index)
                info = { className = className, classFile = classFile, classID = classID }
            end
            classInfos[#classInfos + 1] = info
        end
    end

    for index, info in ipairs(classInfos or {}) do
        if type(info) == "table" and info.classFile then
            local icon, iconTexCoord, isClassIcon = GetClassIcon(info.classFile)
            map[info.classFile] = {
                token = info.classFile,
                name = GetClassDisplayName(info.classFile, info.className),
                classID = info.classID or info.id or index,
                icon = icon,
                iconTexCoord = iconTexCoord,
                isClassIcon = isClassIcon,
            }
        end
    end

    if not next(map) then
        for _, token in ipairs(CLASS_TOKENS) do
            local icon, iconTexCoord, isClassIcon = GetClassIcon(token)
            map[token] = {
                token = token,
                name = GetClassDisplayName(token, token),
                icon = icon,
                iconTexCoord = iconTexCoord,
                isClassIcon = isClassIcon,
            }
        end
    end

    return map
end

local function GetOrderedClassGroups()
    local map = GetClassInfoMap()
    local groups = {}
    for _, group in ipairs(ARMOR_GROUPS) do
        local result = { key = group.labelKey, label = T(group.labelKey, group.fallback), classes = {} }
        for _, token in ipairs(group.classes) do
            if map[token] then
                result.classes[#result.classes + 1] = map[token]
            end
        end
        if #result.classes > 0 then
            groups[#groups + 1] = result
        end
    end
    return groups
end

local function GetSpecDisplayName(specID, fallback)
    if YUI.Locale and YUI.Locale.GetSpecializationName then
        return YUI.Locale:GetSpecializationName(specID, fallback)
    end
    return fallback or tostring(specID or "")
end

local function GetNumSpecsForClass(classID)
    if TalentAPI.GetNumSpecializationsForClassID then
        return TalentAPI.GetNumSpecializationsForClassID(classID) or 0
    elseif C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID then
        return C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
    elseif GetNumSpecializationsForClassID then
        return GetNumSpecializationsForClassID(classID) or 0
    end
    return 0
end

local function GetSpecInfoForClass(classID, index)
    if TalentAPI.GetSpecializationInfoForClassID then
        return TalentAPI.GetSpecializationInfoForClassID(classID, index)
    end

    local sex = UnitSex and UnitSex("player") or nil
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoForClassID then
        return C_SpecializationInfo.GetSpecializationInfoForClassID(classID, index, sex)
    elseif GetSpecializationInfoForClassID then
        return GetSpecializationInfoForClassID(classID, index, sex)
    end
    return nil
end

local function GetSpecsForClass(classInfo)
    local specs = {}
    if classInfo and (TalentAPI.GetClassConfigurationSpecializations or TalentAPI.GetClassSpecializations) then
        for _, specInfo in ipairs((TalentAPI.GetClassConfigurationSpecializations or TalentAPI.GetClassSpecializations)(classInfo)) do
            if specInfo.specID then
                local specName = specInfo.name or tostring(specInfo.specID)
                specs[#specs + 1] = {
                    key = BuildSpecKey(specInfo.classFile or classInfo.token, specInfo.specID),
                    specID = specInfo.specID,
                    name = specName,
                    displayName = GetSpecDisplayName(specInfo.specID, specName),
                    icon = specInfo.icon or DEFAULT_ICON,
                    nativeIcon = specInfo.icon,
                    classInfo = classInfo,
                }
            end
        end
    end

    if #specs == 0 and classInfo and classInfo.classID then
        local count = GetNumSpecsForClass(classInfo.classID)
        for index = 1, count do
            local specID, specName, _, specIcon = GetSpecInfoForClass(classInfo.classID, index)
            if specID then
                specName = specName or tostring(specID)
                specs[#specs + 1] = {
                    key = BuildSpecKey(classInfo.token, specID),
                    specID = specID,
                    name = specName,
                    displayName = GetSpecDisplayName(specID, specName),
                    icon = specIcon or DEFAULT_ICON,
                    nativeIcon = specIcon,
                    classInfo = classInfo,
                }
            end
        end
    end

    if #specs == 0 and classInfo and classInfo.token == GetPlayerClassToken() then
        local count = TalentAPI.GetNumSpecializations and TalentAPI.GetNumSpecializations() or 0
        for index = 1, count do
            local specID, specName, specIcon
            if TalentAPI.GetSpecializationInfo then
                specID, specName, _, specIcon = TalentAPI.GetSpecializationInfo(index)
            end
            specID = specID or index
            specName = specName or T("context.spec_fallback", "Spec %d", index)
            specs[#specs + 1] = {
                key = BuildSpecKey(classInfo.token, specID),
                specID = specID,
                name = specName,
                displayName = GetSpecDisplayName(specID, specName),
                icon = specIcon or DEFAULT_ICON,
                nativeIcon = specIcon,
                classInfo = classInfo,
            }
        end
    end

    return specs
end

local function GetClassColor(classInfo)
    if not classInfo then return 1, 1, 1, 1 end
    local color = UnitAPI.GetClassColor and UnitAPI.GetClassColor(classInfo.token)
    if color then
        return color.r or 1, color.g or 1, color.b or 1, 1
    elseif RAID_CLASS_COLORS and RAID_CLASS_COLORS[classInfo.token] then
        local fallback = RAID_CLASS_COLORS[classInfo.token]
        return fallback.r or 1, fallback.g or 1, fallback.b or 1, 1
    end
    return 1, 1, 1, 1
end

local function SetClassTextColor(text, classInfo)
    if text then text:SetTextColor(GetClassColor(classInfo)) end
end

local function SetEditTextColor(edit, key, fallback)
    if not edit then return end
    local r, g, b, a
    if key and GUI2 and GUI2.GetColor then
        r, g, b, a = GUI2:GetColor(key, fallback)
    elseif fallback then
        r, g, b, a = fallback[1], fallback[2], fallback[3], fallback[4] or 1
    else
        r, g, b, a = 1, 1, 1, 1
    end
    edit:SetTextColor(r or 1, g or 1, b or 1, a or 1)
end

local function ConfigureAlphaEdit(edit, getValue, setValue, refresh)
    if edit.SetNumeric then edit:SetNumeric(true) end
    if edit.SetMaxLetters then edit:SetMaxLetters(ALPHA_MAX_LETTERS) end
    if edit.SetTextInsets then edit:SetTextInsets(8, 8, 0, 0) end
    edit:SetJustifyH("CENTER")

    local isSettingText = false
    local showingPlaceholder = false
    local suppressCommit = false

    local function Display()
        local saved = ClampPercent(getValue and getValue(), nil)
        isSettingText = true
        if saved == nil then
            showingPlaceholder = true
            edit:SetText(tostring(DEFAULT_ALPHA))
            SetEditTextColor(edit, "color.text.disabled", { 0.45, 0.45, 0.45, 1 })
        else
            showingPlaceholder = false
            edit:SetText(tostring(saved))
            edit:SetTextColor(1, 1, 1, 1)
        end
        if edit.HighlightText then edit:HighlightText(0, 0) end
        if edit.SetCursorPosition then edit:SetCursorPosition(0) end
        isSettingText = false
    end

    local function Commit()
        local text = showingPlaceholder and "" or edit:GetText()
        local value = ClampPercent(text, nil)
        if setValue then setValue(value) end
        RefreshAll("settings-alpha")
        if refresh then refresh() else Display() end
    end

    edit:SetScript("OnEditFocusGained", function(self)
        if self.gui2Bg then GUI2:SetBorderColor(self.gui2Bg, "color.border.focus") end
        if showingPlaceholder then
            isSettingText = true
            self:SetText("")
            isSettingText = false
            showingPlaceholder = false
        elseif self.HighlightText then
            self:HighlightText()
        end
        self:SetTextColor(1, 1, 1, 1)
    end)

    edit:SetScript("OnEditFocusLost", function(self)
        if self.gui2Bg then GUI2:SetBorderColor(self.gui2Bg, "color.border.default") end
        if suppressCommit then
            suppressCommit = false
            return
        end
        Commit()
    end)

    edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    edit:SetScript("OnEscapePressed", function(self)
        suppressCommit = true
        Display()
        self:ClearFocus()
    end)

    edit:SetScript("OnTextChanged", function(self)
        if isSettingText then return end
        if self:HasFocus() then
            showingPlaceholder = false
            self:SetTextColor(1, 1, 1, 1)
        end
    end)

    Display()
end

local function RenderAlphaCell(parent, x, y, width, entry, refresh)
    local frame = GUI2:CreatePanel(parent, {
        width = width,
        height = ALPHA_CELL_HEIGHT,
        surface = "color.surface.panel",
        border = "color.border.subtle",
    })
    frame:SetPoint("TOPLEFT", x, y)

    local hint = GUI2:CreateText(frame, T("settings.percent_hint", "%"), "font.size.sm", "color.text.secondary")
    hint:SetPoint("RIGHT", frame, "RIGHT", -10, 0)

    local edit = GUI2.Form:CreateEditBox(frame, { width = ALPHA_EDIT_WIDTH, height = ALPHA_EDIT_HEIGHT, autoFocus = false })
    edit:SetPoint("RIGHT", hint, "LEFT", -6, 0)
    ConfigureAlphaEdit(edit, entry.get, entry.set, refresh)

    local icon = GUI2:CreateIconSlot(frame, {
        size = ALPHA_ICON_SIZE,
        icon = entry.icon or DEFAULT_ICON,
        texCoords = entry.iconTexCoord,
        shape = "square",
        variant = "surface",
        padding = entry.specID and 2 or 0,
    })
    icon:SetPoint("LEFT", frame, "LEFT", 10, 0)
    if icon.EnableMouse then icon:EnableMouse(false) end

    if entry.specID and Icons and Icons.GetScopedSpecIcon and Icons.ApplyIcon then
        local iconData = Icons.GetScopedSpecIcon(entry.specID, entry.nativeIcon or entry.icon, ICON_SCOPE_ID)
        if iconData then
            local texture = icon.icon or icon
            Icons.ApplyIcon(texture, iconData)
            if iconData.kind == "spec" and iconData.custom ~= true and not iconData.atlas and Icons.GetNativeSpecTexCoord then
                texture:SetTexCoord(unpack(Icons.GetNativeSpecTexCoord()))
            end
        end
    end

    local label = GUI2:CreateText(frame, entry.label or "", "font.size.md", "color.text.primary")
    label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    label:SetPoint("RIGHT", edit, "LEFT", -8, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    SetClassTextColor(label, entry.classInfo)

    return frame
end

local function RenderAlphaGrid(parent, x, y, width, entries, refresh)
    local gridWidth = width or ALPHA_GRID_WIDTH
    local columns = ALPHA_GRID_COLUMNS
    local cellWidth = math.floor((gridWidth - ((columns - 1) * ALPHA_GRID_GAP)) / columns)
    local rows = math.ceil(#entries / columns)
    if rows < 1 then rows = 1 end

    local height = (rows * ALPHA_CELL_HEIGHT) + ((rows - 1) * ALPHA_GRID_GAP)
    local frame = GUI2:CreateFrame(parent, { width = gridWidth, height = height })
    frame:SetPoint("TOPLEFT", x, y)

    for index, entry in ipairs(entries) do
        local row = math.floor((index - 1) / columns)
        local col = (index - 1) % columns
        RenderAlphaCell(frame, col * (cellWidth + ALPHA_GRID_GAP), -(row * (ALPHA_CELL_HEIGHT + ALPHA_GRID_GAP)), cellWidth, entry, refresh)
    end

    return gridWidth, height
end

local function AddAlphaGrid(options, entries, refresh)
    if not entries or #entries == 0 then return end
    options[#options + 1] = {
        type = "custom",
        render = function(parent, x, y, width)
            return RenderAlphaGrid(parent, x, y, width, entries, refresh)
        end,
    }
end

local function RenderBatchRow(parent, x, y, width, valueTable, entries, refresh)
    local frame = GUI2:CreateFrame(parent, { width = width or ALPHA_GRID_WIDTH, height = 32 })
    frame:SetPoint("TOPLEFT", x, y)

    local labelWidth = GUI2.GetMetric and GUI2:GetMetric("layout.form.labelWidth", 120) or 120
    local gap = GUI2.GetMetric and GUI2:GetMetric("layout.form.gap", 10) or 10
    local controlX = labelWidth + gap

    local labelText = GUI2:CreateText(frame, T("settings.batch", "Batch"), "font.size.md", "color.text.primary")
    labelText:SetPoint("LEFT", frame, "LEFT", 0, 0)
    labelText:SetWidth(labelWidth)
    labelText:SetJustifyH("LEFT")
    labelText:SetWordWrap(false)

    local edit = GUI2.Form:CreateEditBox(frame, { width = BATCH_EDIT_WIDTH, height = ALPHA_EDIT_HEIGHT, autoFocus = false })
    edit:SetPoint("LEFT", frame, "LEFT", controlX, 0)
    if edit.SetNumeric then edit:SetNumeric(true) end
    if edit.SetMaxLetters then edit:SetMaxLetters(ALPHA_MAX_LETTERS) end
    if edit.SetTextInsets then edit:SetTextInsets(8, 8, 0, 0) end
    edit:SetJustifyH("CENTER")

    local hint = GUI2:CreateText(frame, T("settings.percent_hint", "%"), "font.size.sm", "color.text.secondary")
    hint:SetPoint("LEFT", edit, "RIGHT", 6, 0)

    local function GetBatchValue()
        local value = ClampPercent(edit:GetText(), nil)
        if value == nil then
            if edit.SetFocus then edit:SetFocus() end
            if edit.HighlightText then edit:HighlightText() end
        end
        return value
    end

    local function FinishBatch()
        RefreshAll("settings-batch")
        if refresh then refresh() end
    end

    local cursor = hint
    local function AddButton(text, onClick)
        local button = GUI2.Form:CreateButton(frame, {
            text = text,
            width = BATCH_BUTTON_WIDTH,
            height = ALPHA_EDIT_HEIGHT,
            onClick = onClick,
        })
        button:SetPoint("LEFT", cursor, "RIGHT", 8, 0)
        cursor = button
        return button
    end

    AddButton(T("settings.apply_all", "Apply All"), function()
        local value = GetBatchValue()
        if value == nil then return end
        for _, entry in ipairs(entries or {}) do
            valueTable[entry.key] = value
        end
        FinishBatch()
    end)

    AddButton(T("settings.clear_all", "Clear All"), function()
        for key in pairs(valueTable) do
            valueTable[key] = nil
        end
        FinishBatch()
    end)

    return width or ALPHA_GRID_WIDTH, 32
end

local function AddBatchRow(options, valueTable, entries, refresh)
    if type(valueTable) ~= "table" or not entries or #entries == 0 then return end
    options[#options + 1] = {
        type = "custom",
        render = function(parent, x, y, width)
            return RenderBatchRow(parent, x, y, width, valueTable, entries, refresh)
        end,
    }
end

local function BuildAllSpecEntries(db)
    local entries = {}
    for _, group in ipairs(GetOrderedClassGroups()) do
        for _, classInfo in ipairs(group.classes) do
            for _, spec in ipairs(GetSpecsForClass(classInfo)) do
                entries[#entries + 1] = { key = spec.key }
            end
        end
    end
    return entries
end

RefreshPreviewControlsState = function()
    local owner = previewSettingsOwner
    if not owner then return end

    local inCombat = IsInCombatLockdownSafe()
    if owner.toggleButton then
        owner.toggleButton:SetText(previewEnabled and T("preview.stop", "Close Preview") or T("preview.start", "Preview"))
        owner.toggleButton:SetDisabled(inCombat)
    end
    if owner.resetButton then
        owner.resetButton:SetDisabled(inCombat)
    end
    if owner.statusText then
        if inCombat and previewEnabled then
            owner.statusText:SetText(T("preview.status_combat_active", "Preview is unavailable in combat."))
            GUI2:SetTextColorKey(owner.statusText, "color.state.warning")
        elseif inCombat then
            owner.statusText:SetText(T("preview.status_combat", "Preview is unavailable in combat."))
            GUI2:SetTextColorKey(owner.statusText, "color.state.warning")
        elseif previewEnabled then
            local specKey = GetActiveSpecKey()
            local _, placeholder = PreviewDefaults:GetLayout(specKey, UseClassicPreviewTextures())
            local key = UseClassicPreviewTextures() and "preview.status_classic"
                or placeholder and "preview.status_placeholder" or "preview.status_on"
            owner.statusText:SetText(T(key, "Preview active"))
            GUI2:SetTextColorKey(owner.statusText, "color.state.success")
        else
            owner.statusText:SetText("")
            GUI2:SetTextColorKey(owner.statusText, "color.text.secondary")
        end
    end
end

local function ResetCurrentTabSettings(refresh)
    if IsInCombatLockdownSafe() then
        stats.previewCombatBlocks = (stats.previewCombatBlocks or 0) + 1
        RefreshPreviewInteractivity()
        RefreshPreviewControlsState()
        return
    end

    local db = GetDB()
    if settingsTab == "countdown" then
        db.countdown = nil
        BuffTimer.Normalize(db)
    else
        db.alphaBySpec = {}
        db.globalScale = defaults.globalScale
        db.yOffset = defaults.yOffset
        db.textureScale = defaults.textureScale
        db.horizontalSpacing = defaults.horizontalSpacing
        db.verticalSpacing = defaults.verticalSpacing
    end
    RefreshAll("settings-reset")
    refresh()
end

local function CleanPreviewMaterials(reason)
    local db = GetDB()
    db.previewMaterialsBySpec = {}
    stats.previewMaterialResets = (stats.previewMaterialResets or 0) + 1
    if previewEnabled then
        RefreshPreviewLayer(reason or "preview-clean")
    end
    RefreshPreviewControlsState()
    return true
end

function Capture:CleanPreviewMaterials()
    if YUI.IsRetail ~= true then
        self:Print(T("dev.clean_retail_only", "Spell Alert preview material cleanup is only available on Retail."))
        return true
    end

    CleanPreviewMaterials("dev-clean")
    self:Print(T("dev.clean_preview_done", "Spell Alert preview materials restored to defaults."))
    return true
end

YUI.SpellAlert = YUI.SpellAlert or {}
function YUI.SpellAlert:CleanPreviewMaterials()
    if YUI.IsRetail ~= true then
        Capture:Print(T("dev.clean_retail_only", "Spell Alert preview material cleanup is only available on Retail."))
        return false
    end

    CleanPreviewMaterials("dev-clean")
    Capture:Print(T("dev.clean_preview_done", "Spell Alert preview materials restored to defaults."))
    return true
end

function YUI.SpellAlert:ShowCreditPopup()
    local creditPopup = self.creditPopup
    if not creditPopup then
        local panel = GUI2:CreatePanel(UIParent, {
            width = 560, height = 240, surface = "color.surface.popup",
            border = "color.popup.border", shadow = true,
        })
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("FULLSCREEN_DIALOG")
        panel:EnableMouse(true)
        YUI.Settings:RegisterScaleWindow(panel)
        local title = GUI2:CreateText(panel, "SpellAlertTimer（SAT）", "font.size.lg", "color.text.heading")
        title:SetPoint("TOPLEFT", 20, -18)
        local body = GUI2:CreateText(panel, T("credit.description"), "font.size.md", "color.text.primary")
        body:SetPoint("TOPLEFT", 20, -52)
        body:SetWidth(520)
        body:SetWordWrap(true)
        panel.body = body
        local edit = GUI2:CreateEditBox(panel, { width = 520, height = 30 })
        edit:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -20)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() panel:Hide() end)
        edit:SetScript("OnEnterPressed", function() panel:Hide() end)
        panel.edit = edit
        local hint = GUI2:CreateText(panel, T("credit.copy_hint"), "font.size.sm", "color.text.secondary")
        hint:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -10)
        local close = GUI2:CreateCloseButton(panel, function() panel:Hide() end)
        close:SetPoint("TOPRIGHT", -6, -6)
        panel:SetScript("OnHide", function() edit:ClearFocus() end)
        creditPopup = panel
        self.creditPopup = panel
    end
    creditPopup:Show()
    creditPopup:SetHeight(52 + creditPopup.body:GetStringHeight() + 94)
    creditPopup.edit:SetText("https://www.curseforge.com/wow/addons/spellactivationtext")
    creditPopup.edit:SetFocus()
    creditPopup.edit:HighlightText()
end

local function RenderSettingsNavigation(parent, x, y, width, refresh)
    local frameWidth = width or SECTION_WIDTH
    local frame = GUI2:CreateFrame(parent, { width = frameWidth, height = 30 })
    frame:SetPoint("TOPLEFT", x, y)
    frame:SetScript("OnHide", function(self)
        if previewSettingsOwner == self then
            if YUI.SpellAlert.creditPopup then YUI.SpellAlert.creditPopup:Hide() end
            previewSettingsOwner = nil
        end
    end)

    local toggleButton = GUI2.Form:CreateButton(frame, {
        text = T("preview.start", "Preview"),
        width = 118,
        height = ALPHA_EDIT_HEIGHT,
        onClick = function()
            if IsInCombatLockdownSafe() then
                stats.previewCombatBlocks = (stats.previewCombatBlocks or 0) + 1
                RefreshPreviewInteractivity()
                RefreshPreviewControlsState()
                return
            end
            SetPreviewEnabled(not previewEnabled, "settings-toggle")
        end,
    })
    toggleButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -152, 0)
    frame.toggleButton = toggleButton

    local resetButton = GUI2.Form:CreateButton(frame, {
        text = T("preview.reset_spec", "Restore Defaults"),
        width = 142,
        height = ALPHA_EDIT_HEIGHT,
        onClick = function() ResetCurrentTabSettings(refresh) end,
    })
    resetButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    frame.resetButton = resetButton

    local statusText = GUI2:CreateText(frame, "", "font.size.md", "color.text.secondary")
    statusText:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 8)
    statusText:SetJustifyH("RIGHT")
    statusText:SetWordWrap(false)
    frame.statusText = statusText

    if settingsTab == "countdown" then
        local credit = GUI2:CreateText(frame, T("credit.reference"), "font.size.sm", "color.text.secondary")
        credit:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -42)
        credit:SetJustifyH("RIGHT")
        local link = GUI2.Form:CreateTextLink(frame, {
            text = T("credit.link"), width = 300, height = 22,
            fontSizeKey = "font.size.sm",
            onClick = function() YUI.SpellAlert:ShowCreditPopup() end,
        })
        link:SetPoint("TOPRIGHT", credit, "BOTTOMRIGHT", 0, -2)
        link.text:ClearAllPoints()
        link.text:SetPoint("RIGHT", link, "RIGHT", 0, 1)
        link.text:SetJustifyH("RIGHT")
    end

    local tabs = GUI2.Form:CreateUnderlineTabs(frame, {
        items = {
            { text = T("settings.tab_layout"), value = "layout" },
            { text = T("settings.tab_countdown"), value = "countdown" },
        },
        value = settingsTab,
        fontSizeKey = "font.size.lg",
        showBaseline = true,
        baselineHeight = 1,
        baselineColorKey = "color.border.subtle",
        indicatorHeight = 2,
        indicatorColorKey = "color.text.accent",
        width = math.max(100, frameWidth - 290),
        overflow = "scroll",
        gap = 20,
        onChange = function(_, value)
            if settingsTab == value then return end
            settingsTab = value
            refresh()
        end,
    })
    tabs:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    previewSettingsOwner = frame
    RefreshPreviewControlsState()
    return frameWidth, 30
end

local function AddNavigationOptions(options, refresh)
    options[#options + 1] = {
        type = "custom",
        render = function(parent, x, y, width)
            return RenderSettingsNavigation(parent, x, y, width, refresh)
        end,
    }
end

local function AddCountdownOptions(options, db)
    if not BuffTimer then return end
    local config = db.countdown
    local supported = BuffTimer.IsSupported()
    options[#options + 1] = {
        type = "checkbox", label = T("countdown.enabled"), disabled = not supported,
        get = function() return config.enabled end,
        set = function(value) config.enabled = value == true; RefreshAll("countdown-toggle") end,
    }
    if not supported then
        options[#options + 1] = { type = "text", label = T("countdown.unavailable") }
        return
    end
    options[#options + 1] = {
        type = "checkbox", label = T("countdown.priest_avoidance"),
        get = function() return config.priestAvoidance end,
        set = function(value) config.priestAvoidance = value == true; RefreshAll("priest-avoidance") end,
    }
    local fields = {}
    local function RefreshCountdown()
        BuffTimer.Normalize(db)
        RefreshAll("countdown-settings")
    end
    fields[#fields + 1] = {
        type = "font", label = T("countdown.font"), default = BuffTimer.GetDefaultFontName(),
        fontStyleSource="font", get = function() return config.font end,
        set = function(value) config.font = value; RefreshCountdown() end,
    }
    fields[#fields + 1] = {
        type = "dropdown", label = T("countdown.outline"), default = "OUTLINE_SHADOW",
        options = {
            { text = T("countdown.outline_none"), value = "" },
            { text = T("countdown.outline_thin"), value = "OUTLINE" },
            { text = T("countdown.outline_thick"), value = "THICKOUTLINE" },
            { text = T("countdown.outline_shadow"), value = "SHADOW" },
            { text = T("countdown.outline_combined"), value = "OUTLINE_SHADOW" },
        },
        fontStyleSource="outline", get = function() return config.outline end,
        set = function(value) config.outline = value; RefreshCountdown() end,
    }
    fields[#fields + 1] = {
        type = "color", label = T("countdown.color"), hasAlpha = false, default = { 1, 1, 1, 1 },
        fontStyleSource="color", get = function() return config.color end,
        set = function(value) config.color = value; RefreshCountdown() end,
    }
    local function AddSlider(key, minimum, maximum)
        fields[#fields + 1] = {
            type = "slider", fontStyleSource=key, label = T("countdown." .. key), min = minimum, max = maximum, step = 1,
            get = function() return config[key] end,
            set = function(value) config[key] = value; RefreshCountdown() end,
        }
    end
    AddSlider("size", 10, 80)
    AddSlider("sideX", -100, 100)
    AddSlider("sideY", -100, 100)
    AddSlider("topX", -100, 100)
    AddSlider("topY", -100, 100)
    if GUI2.FontStyle and GUI2.FontStyle.MergeOptions then
        GUI2.FontStyle:MergeOptions(fields, {{key="spell_alert:countdown", sources={"font","outline","color","size"}}})
    end
    for i = 1, #fields, 2 do
        for j = i, i + 1 do
            local field = fields[j]
            if field then
            field.inline, field.inlineLabel = true, true
            field.width = FIELD_WIDTH
            field.labelWidth = 130
            field.gap = CONTROL_GAP
            if field.type == "slider" then field.inputWidth = SLIDER_VALUE_WIDTH end
            end
        end
        options[#options + 1] = {
            type = "row", gap = FIELD_GAP, children = { fields[i], fields[i + 1] },
        }
    end
end

local function AddAppearanceOptions(options, db)
    options[#options + 1] = { type = "divider", label = T("settings.appearance", "Appearance"), alignLeft = true, width = SECTION_WIDTH, collapsible = true, collapseKey = "spellalert.appearance" }
    options[#options + 1] = {
        type = "row",
        gap = FIELD_GAP,
        children = {
            {
                type = "slider",
                label = T("settings.global_scale", "Global Scale"),
                inline = true,
                width = FIELD_WIDTH,
                labelWidth = LABEL_WIDTH,
                gap = CONTROL_GAP,
                inputWidth = SLIDER_VALUE_WIDTH,
                min = 50,
                max = 200,
                step = 1,
                get = function() return db.globalScale end,
                set = function(value)
                    db.globalScale = ClampNumber(value, 50, 200, defaults.globalScale)
                    RefreshAll("settings-global-scale")
                end,
            },
            {
                type = "slider",
                label = T("settings.y_offset", "Y Offset"),
                inline = true,
                width = FIELD_WIDTH,
                labelWidth = LABEL_WIDTH,
                gap = CONTROL_GAP,
                inputWidth = SLIDER_VALUE_WIDTH,
                min = -300,
                max = 300,
                step = 1,
                get = function() return db.yOffset end,
                set = function(value)
                    db.yOffset = ClampNumber(value, -300, 300, defaults.yOffset)
                    RefreshAll("settings-y-offset")
                end,
            },
        },
    }
    options[#options + 1] = {
        type = "row",
        gap = FIELD_GAP,
        children = {
            {
                type = "slider",
                label = T("settings.texture_scale", "Texture Scale"),
                inline = true,
                width = FIELD_WIDTH,
                labelWidth = LABEL_WIDTH,
                gap = CONTROL_GAP,
                inputWidth = SLIDER_VALUE_WIDTH,
                min = 50,
                max = 200,
                step = 1,
                get = function() return db.textureScale end,
                set = function(value)
                    db.textureScale = ClampNumber(value, 50, 200, defaults.textureScale)
                    RefreshAll("settings-texture-scale")
                end,
            },
            {
                type = "slider",
                label = T("settings.horizontal_spacing", "Horizontal Gap"),
                inline = true,
                width = FIELD_WIDTH,
                labelWidth = LABEL_WIDTH,
                gap = CONTROL_GAP,
                inputWidth = SLIDER_VALUE_WIDTH,
                min = -200,
                max = 200,
                step = 1,
                get = function() return db.horizontalSpacing end,
                set = function(value)
                    db.horizontalSpacing = ClampNumber(value, -200, 200, defaults.horizontalSpacing)
                    RefreshAll("settings-horizontal-spacing")
                end,
            },
        },
    }
    options[#options + 1] = {
        type = "row",
        gap = FIELD_GAP,
        children = {
            {
                type = "slider",
                label = T("settings.vertical_spacing", "Vertical Gap"),
                inline = true,
                width = FIELD_WIDTH,
                labelWidth = LABEL_WIDTH,
                gap = CONTROL_GAP,
                inputWidth = SLIDER_VALUE_WIDTH,
                min = -200,
                max = 200,
                step = 1,
                get = function() return db.verticalSpacing end,
                set = function(value)
                    db.verticalSpacing = ClampNumber(value, -200, 200, defaults.verticalSpacing)
                    RefreshAll("settings-vertical-spacing")
                end,
            },
        },
    }
end

local Feature = {
    product = PRODUCT_ID,
    id = FEATURE_KEY,
    name = T("feature.name", "Spell Alert Enhancement"),
    description = T("feature.description", "Automatically enables the screen spell alert system while active, then adjusts opacity by specialization and global visual layout."),
    default = true,
    settingsMode = "inline",
    storageKey = FEATURE_KEY,
    sourceRoot = "Components\\SpellAlert",
    versions = { "forever", "mainline", "mists", "wrath" },
    order = 200.5,
    implementationType = "native-enhanced",
}

function Feature:GetEffectiveState()
    if not _G.SpellActivationOverlayFrame and not frameHooksInstalled then
        return {
            effective = true,
            reason = T("state.missing_frame", "The client spell alert frame is not ready yet. It will be applied when the frame becomes available."),
            tone = "warning",
        }
    end
    return { effective = true }
end

function Feature:GetSubFeatureStates()
    if not BuffTimer or not BuffTimer.IsSupported() then return {} end
    local db = Components:CopyConfigSnapshot(CONFIG_KEY, defaults, PRODUCT_ID)
    if not db then return {} end
    local config = type(db.countdown) == "table" and db.countdown or {}
    return { { label = T("countdown.summary", "Buff countdown"), enabled = config.enabled ~= false } }
end

function Feature:GetOptions()
    local db = GetDB()
    local options = {}

    local function Refresh()
        if self.RefreshCurrentModule then
            self:RefreshCurrentModule()
        end
    end

    AddNavigationOptions(options, Refresh)
    if settingsTab == "countdown" then
        AddCountdownOptions(options, db)
        return options
    end

    local allEntries = BuildAllSpecEntries(db)
    AddBatchRow(options, db.alphaBySpec, allEntries, Refresh)

    for _, group in ipairs(GetOrderedClassGroups()) do
        local insertedGroup = false
        for _, classInfo in ipairs(group.classes) do
            local specs = GetSpecsForClass(classInfo)
            if #specs > 0 then
                if not insertedGroup then
                    options[#options + 1] = { type = "divider", label = group.label, alignLeft = true, width = ALPHA_GRID_WIDTH, collapsible = true, collapseKey = "spellalert." .. group.key }
                    insertedGroup = true
                end
                local entries = {}
                for _, spec in ipairs(specs) do
                    local entrySpec = spec
                    entries[#entries + 1] = {
                        key = entrySpec.key,
                        label = entrySpec.displayName or entrySpec.name,
                        icon = entrySpec.icon,
                        iconTexCoord = entrySpec.iconTexCoord,
                        specID = entrySpec.specID,
                        nativeIcon = entrySpec.nativeIcon,
                        classInfo = entrySpec.classInfo,
                        get = function()
                            return db.alphaBySpec[entrySpec.key]
                        end,
                        set = function(value)
                            db.alphaBySpec[entrySpec.key] = value
                        end,
                    }
                end
                AddAlphaGrid(options, entries, nil)
            end
        end
    end

    AddAppearanceOptions(options, db)
    return options
end

function Feature:OnSettingsEnter()
    AttachPreviewEvents()
    RefreshPreviewControlsState()
end

function Feature:OnSettingsLeave()
    SetPreviewEnabled(false, "settings-leave")
    DetachPreviewEvents()
    previewSettingsOwner = nil
end

function Feature.callback(enable)
    runtimeEnabled = enable == true
    if runtimeEnabled then
        installRetryCount = 0
        EnsureOverlayCVarsEnabled()
        AttachRuntimeEvents()
        if TryInstallFrameHooks() then
            RefreshAll("enable")
        else
            ScheduleInstallRetry()
        end
    else
        if BuffTimer then BuffTimer.Configure(_G.SpellActivationOverlayFrame, GetDB().countdown, false) end
        SetPreviewEnabled(false, "disable")
        DetachPreviewEvents()
        DetachRuntimeEvents()
        installRetryPending = false
        local frame = _G.SpellActivationOverlayFrame
        RestoreActiveOverlays(frame)
        RestoreOverlayCVars()
        RestoreOriginalFrameState(frame)
    end
end

function Feature:GetStats()
    stats.countdown = BuffTimer and BuffTimer.GetStats() or nil
    stats.enabled = runtimeEnabled == true
    stats.previewEnabled = previewEnabled == true
    stats.previewPickerShown = false
    stats.previewInCombat = IsInCombatLockdownSafe()
    stats.captureEnabled = Capture.enabled == true
    return stats
end

Capture:RegisterSlashCommand()
Components:RegisterFeature(FEATURE_KEY, Feature)

if GUI2 and GUI2.FontStyle and GUI2.FontStyle.RegisterConfig and BuffTimer then
    GUI2.FontStyle:RegisterConfig("spell_alert", {
        label=function() return T("feature.name") end,
        get=function()
            local db,profile=GUI2.FontStyle.ComponentConfig(PRODUCT_ID,CONFIG_KEY)
            return db and db.countdown,profile
        end,
        refresh=function() RefreshAll("countdown-settings") end,
        targets={{id="countdown",label=function() return T("countdown.title") end,
            available=function() return BuffTimer.IsSupported() end,
            fields={font="font",size="size",color="color",monochrome="monochrome"}, effect="outline",format="flags",
            defaults={font=BuffTimer.GetDefaultFontName(),size=21,color={1,1,1,1},outline="OUTLINE_SHADOW"},
            minSize=10,maxSize=80,hasAlpha=false}},
    })
end
