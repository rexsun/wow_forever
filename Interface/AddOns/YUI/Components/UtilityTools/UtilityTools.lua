local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not (YUI and YUI.Components) then return end

local Components = YUI.Components
local Event = YUI.Event
local FrameAPI = YUI.API and YUI.API.Frame or YUI.WOW_API
local TalentAPI = YUI.API and YUI.API.Talent or YUI.WOW_API
local UnitAPI = YUI.API and YUI.API.Unit or YUI.WOW_API
local Icons = YUI.API and YUI.API.Icons
local Security = YUI.API and YUI.API.Security
local System = YUI.API and YUI.API.System
local GUI2 = YUI.GUI2
local S = YUI.Settings
local L = YUI.Locale and YUI.Locale:Get("UtilityTools") or {}
local LC = YUI.Locale and YUI.Locale:Get("Core") or {}
local Unpack = unpack or table.unpack

local FEATURE_KEY = "UtilityTools"
local CONFIG_KEY = "UtilityTools_Config"
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or (_G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME] and _G.YUI_CORE_EMBED_STATE[ADDON_NAME].productId)
    or YUI.ProductId or "suite"
local IS_MAINLINE = YUI.IsRetail == true
local HAS_NAMEPLATE_SYNC = IS_MAINLINE or YUI.IsForever == true
local BONUS_ROLL_TEST_CURRENCY_ID = 3418
local BONUS_ROLL_ICON_SCOPE_ID = "settings"
local BONUS_ROLL_SPEC_ICON_SIZE = 18
local BONUS_ROLL_NATIVE_ICON_DIMENSION = 64
local BONUS_ROLL_CUSTOM_ICON_DIMENSION = 512

local MODE_BLOCK_ALLOWLIST = "block_allowlist"
local MODE_THROTTLE_ONCE = "throttle_once"
local DEFAULTS = {
    syncFriendlyNameplates = false,
    nameplateOutline = true,
    bonusRoll = {
        rollConfirm = true,
        passConfirm = true,
    },
    macroFrame = {
        enabled = true,
        visibleCount = 50,
    },
    hideErrors = {
        enabled = false,
        mode = MODE_BLOCK_ALLOWLIST,
        throttleWindow = 3,
    },
}

local MACRO_UI_ADDON = "Blizzard_MacroUI"
local MACRO_NATIVE_FRAME_WIDTH = 338
local MACRO_NATIVE_FRAME_HEIGHT = 424
local MACRO_NATIVE_SELECTOR_WIDTH = 319
local MACRO_NATIVE_SELECTOR_HEIGHT = 146
local MACRO_EXTERNAL_WIDTH_PADDING = 40
local MACRO_DEFAULT_VISIBLE_COUNT = 50
local MACRO_LAYOUT_BASE_COLUMNS = 8
local MACRO_LAYOUT_BASE_ROWS = 4
local MACRO_LAYOUT_COLUMN_STEP = 49
local MACRO_LAYOUT_ROW_STEP = 49
local MACRO_LAYOUT_BASE_FRAME_WIDTH = 462
local MACRO_LAYOUT_BASE_FRAME_HEIGHT = 472
local MACRO_LAYOUT_BASE_SELECTOR_WIDTH = 426
local MACRO_LAYOUT_BASE_SELECTOR_HEIGHT = 194
local MACRO_LAYOUTS = {
    [32] = { columns = 8, rows = 4 },
    [40] = { columns = 10, rows = 4 },
    [50] = { columns = 10, rows = 5 },
    [60] = { columns = 10, rows = 6 },
    [80] = { columns = 10, rows = 8 },
}
local MACRO_SELECTOR_PADDING = { 5, 5, 5, 5, 13, 13 }

local featureEnabled = false
local hideErrorsFiltering = false
local originalTryDisplayMessage
local originalPingSystemErrorRegistered
local throttleRecords = {}
local macroFrameApplied = false
local macroFrameOriginals
local macroEventOwner = {}
local macroEventAttached = false
local macroEventFrame
local reloadCommandOwner = {}
local profileOwner = {}
local profileCallbacksRegistered = false
local bonusRollEventOwner = {}
local bonusRollEventsAttached = false
local bonusRollPopupOwner = {}
local bonusRollBindings = {
    roll = {},
    pass = {},
}
local BONUS_ROLL_APPEARANCE = {
    surfaceKey = "color.surface.rewardPopup",
    borderKey = "color.border.rewardPopup",
    titleColorKey = "color.text.rewardHeading",
    messageColorKey = "color.text.primary",
    noteColorKey = "color.text.secondary",
}

local function T(key, fallback)
    if type(L) == "table" and L[key] then
        return L[key]
    end
    return fallback or key
end

local function CT(key, fallback)
    if type(LC) == "table" and LC[key] then
        return LC[key]
    end
    return fallback or key
end

local function OpenUtilityToolsSettings()
    if YUI.Settings and YUI.Settings.OpenComponentFeature then
        YUI.Settings:OpenComponentFeature(FEATURE_KEY)
        return true
    end
    if Components and Components.OpenFeatureSettings then
        Components:OpenFeatureSettings(FEATURE_KEY)
        return true
    end
    return false
end

local function CopyDefaultValue(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}
    for key, item in pairs(value) do
        result[key] = CopyDefaultValue(item)
    end
    return result
end

local function FillMissing(target, defaults)
    if type(target) ~= "table" or type(defaults) ~= "table" then
        return
    end

    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = CopyDefaultValue(value)
        elseif type(target[key]) == "table" and type(value) == "table" then
            FillMissing(target[key], value)
        end
    end
end

local function IsValidMode(mode)
    return mode == MODE_BLOCK_ALLOWLIST or mode == MODE_THROTTLE_ONCE
end

local function NormalizeMacroVisibleCount(value)
    value = tonumber(value)
    if MACRO_LAYOUTS[value] then
        return value
    end
    return MACRO_DEFAULT_VISIBLE_COUNT
end

local function MigrateLegacyHideErrors(config, store)
    if type(config) ~= "table" or type(store) ~= "table" then
        return
    end
    if type(config._migrations) ~= "table" then
        config._migrations = {}
    end
    if config._migrations.hideErrorsV1 then
        return
    end

    local hideConfig = config.hideErrors
    local legacyConfig = type(store.HideErrorMessages_Config) == "table" and store.HideErrorMessages_Config or nil
    if store.HideErrorMessages ~= nil then
        hideConfig.enabled = store.HideErrorMessages == true
    end
    if legacyConfig then
        if IsValidMode(legacyConfig.mode) then
            hideConfig.mode = legacyConfig.mode
        end
        if type(legacyConfig.throttleWindow) == "number" and legacyConfig.throttleWindow > 0 then
            hideConfig.throttleWindow = legacyConfig.throttleWindow
        end
    end

    store.HideErrorMessages = nil
    store.HideErrorMessages_Config = nil
    config._migrations.hideErrorsV1 = true
end

local function NormalizeDB(config)
    if type(config.bonusRoll) ~= "table" then
        config.bonusRoll = CopyDefaultValue(DEFAULTS.bonusRoll)
    end
    if type(config.macroFrame) ~= "table" then
        config.macroFrame = CopyDefaultValue(DEFAULTS.macroFrame)
    end
    if type(config.hideErrors) ~= "table" then
        config.hideErrors = CopyDefaultValue(DEFAULTS.hideErrors)
    end
    FillMissing(config.bonusRoll, DEFAULTS.bonusRoll)
    FillMissing(config.macroFrame, DEFAULTS.macroFrame)
    FillMissing(config.hideErrors, DEFAULTS.hideErrors)

    config.macroFrame.visibleCount = NormalizeMacroVisibleCount(config.macroFrame.visibleCount)

    if not IsValidMode(config.hideErrors.mode) then
        config.hideErrors.mode = MODE_BLOCK_ALLOWLIST
    end
    if type(config.hideErrors.throttleWindow) ~= "number" or config.hideErrors.throttleWindow <= 0 then
        config.hideErrors.throttleWindow = DEFAULTS.hideErrors.throttleWindow
    end
end

local function GetDB()
    local config, store = Components:EnsureConfig(CONFIG_KEY, DEFAULTS, PRODUCT_ID)
    if type(config) ~= "table" then
        return DEFAULTS
    end
    NormalizeDB(config)
    if HAS_NAMEPLATE_SYNC and type(store) == "table" then
        if type(config._migrations) ~= "table" then config._migrations = {} end
        if not config._migrations.syncFriendlyNameplatesV1 then
            if store.SyncFriendlyNameplates ~= nil then
                config.syncFriendlyNameplates = store.SyncFriendlyNameplates == true
            end
            store.SyncFriendlyNameplates = nil
            config._migrations.syncFriendlyNameplatesV1 = true
        end
    end
    MigrateLegacyHideErrors(config, store)
    NormalizeDB(config)
    return config
end

local function IsMacroFrameOptionEnabled()
    local db = GetDB()
    return featureEnabled and db.macroFrame and db.macroFrame.enabled == true
end

local function IsHideErrorsOptionEnabled()
    local db = GetDB()
    return featureEnabled and db.hideErrors and db.hideErrors.enabled == true
end

local IMPORTANT_ERRORS = {}

local function AddImportantError(err)
    if err then IMPORTANT_ERRORS[err] = true end
end

AddImportantError(ERR_INV_FULL)
AddImportantError(ERR_QUEST_LOG_FULL)
AddImportantError(ERR_RAID_GROUP_ONLY)
AddImportantError(ERR_PARTY_LFG_BOOT_LIMIT)
AddImportantError(ERR_PARTY_LFG_BOOT_DUNGEON_COMPLETE)
AddImportantError(ERR_PARTY_LFG_BOOT_IN_COMBAT)
AddImportantError(ERR_PARTY_LFG_BOOT_IN_PROGRESS)
AddImportantError(ERR_PARTY_LFG_BOOT_LOOT_ROLLS)
AddImportantError(ERR_PARTY_LFG_TELEPORT_IN_COMBAT)
AddImportantError(ERR_PET_SPELL_DEAD)
AddImportantError(ERR_PLAYER_DEAD)
AddImportantError(SPELL_FAILED_TARGET_NO_POCKETS)
AddImportantError(ERR_ALREADY_PICKPOCKETED)

local ERR_PARTY_LFG_BOOT_NOT_ELIGIBLE_S_FMT
if ERR_PARTY_LFG_BOOT_NOT_ELIGIBLE_S then
    ERR_PARTY_LFG_BOOT_NOT_ELIGIBLE_S_FMT = format(ERR_PARTY_LFG_BOOT_NOT_ELIGIBLE_S, ".+")
end

local function ClearThrottleRecords()
    for key in pairs(throttleRecords) do
        throttleRecords[key] = nil
    end
end

local function IsImportantError(err)
    if IMPORTANT_ERRORS[err] then
        return true
    end

    if ERR_PARTY_LFG_BOOT_NOT_ELIGIBLE_S_FMT and err and err:find(ERR_PARTY_LFG_BOOT_NOT_ELIGIBLE_S_FMT) then
        return true
    end
    return false
end

local function IsRedErrorColor(r, g, b)
    if not (RED_FONT_COLOR and RED_FONT_COLOR.GetRGB) then
        return r == 1 and g and g < 0.2 and b and b < 0.2
    end

    local redR, redG, redB = RED_FONT_COLOR:GetRGB()
    return r == redR and g == redG and b == redB
end

local function ShouldThrottleMessage(messageType, message, window)
    local now = (GetTime and GetTime()) or 0
    local typeKey = messageType or false
    local typeRecords = throttleRecords[typeKey]
    if not typeRecords then
        typeRecords = {}
        throttleRecords[typeKey] = typeRecords
    end

    local key = message or ""
    local lastShown = typeRecords[key]
    if lastShown and now - lastShown < window then
        return true
    end

    typeRecords[key] = now
    return false
end

local function DisplayRedMessage(self, messageType, message, r, g, b)
    if not message then
        return
    end
    if self.GetMessagesSuppressed and self:GetMessagesSuppressed() then
        return
    end
    if self.TryFlashingExistingMessage and self:TryFlashingExistingMessage(messageType, message) then
        return
    end

    if self.AddMessage then
        self:AddMessage(message, r, g, b, 1.0, messageType)
    end

    if GetGameMessageInfo and messageType then
        local _, soundKitID, voiceID = GetGameMessageInfo(messageType)
        if voiceID and C_Sound and C_Sound.PlayVocalErrorSound then
            C_Sound.PlayVocalErrorSound(voiceID)
        elseif soundKitID and PlaySound then
            PlaySound(soundKitID)
        end
    end
end

local function TryDisplayMessage(self, messageType, message, r, g, b)
    if YUI.IsForever and issecretvalue and (issecretvalue(messageType) or issecretvalue(message)
        or issecretvalue(r) or issecretvalue(g) or issecretvalue(b)) then
        if originalTryDisplayMessage then
            return originalTryDisplayMessage(self, messageType, message, r, g, b)
        end
        return
    end
    if IsRedErrorColor(r, g, b) and not IsImportantError(message) then
        local db = GetDB()
        local hideDB = db.hideErrors or DEFAULTS.hideErrors
        if hideDB.mode == MODE_THROTTLE_ONCE then
            if ShouldThrottleMessage(messageType, message, hideDB.throttleWindow) then
                return
            end
            return DisplayRedMessage(self, messageType, message, r, g, b)
        end
        return
    end

    if originalTryDisplayMessage then
        return originalTryDisplayMessage(self, messageType, message, r, g, b)
    end
end

local function SetPingSystemErrorHidden(hidden)
    if not UIParent then return end

    if hidden then
        if UIParent.IsEventRegistered then
            local ok, registered = pcall(UIParent.IsEventRegistered, UIParent, "PING_SYSTEM_ERROR")
            if ok then
                originalPingSystemErrorRegistered = registered == true
            end
        else
            originalPingSystemErrorRegistered = true
        end

        if UIParent.UnregisterEvent then
            pcall(UIParent.UnregisterEvent, UIParent, "PING_SYSTEM_ERROR")
        end
    else
        if originalPingSystemErrorRegistered and UIParent.RegisterEvent then
            pcall(UIParent.RegisterEvent, UIParent, "PING_SYSTEM_ERROR")
        end
        originalPingSystemErrorRegistered = nil
    end
end

local function ToggleHideErrorsFiltering(enable)
    if not UIErrorsFrame then
        return
    end

    if enable then
        if YUI.IsForever and type(UIErrorsFrame.TryDisplayMessage) ~= "function" then return end
        if not hideErrorsFiltering then
            ClearThrottleRecords()
            originalTryDisplayMessage = UIErrorsFrame.TryDisplayMessage
            UIErrorsFrame.TryDisplayMessage = TryDisplayMessage
            SetPingSystemErrorHidden(true)
            hideErrorsFiltering = true
        end
    else
        if hideErrorsFiltering or UIErrorsFrame.TryDisplayMessage == TryDisplayMessage then
            if UIErrorsFrame.TryDisplayMessage == TryDisplayMessage then
                UIErrorsFrame.TryDisplayMessage = originalTryDisplayMessage
            end
            originalTryDisplayMessage = nil
            SetPingSystemErrorHidden(false)
            ClearThrottleRecords()
            hideErrorsFiltering = false
        end
    end
end

local function CapturePoint(region)
    if not (region and region.GetPoint) then
        return nil
    end
    local point, relativeTo, relativePoint, x, y = region:GetPoint(1)
    return { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y }
end

local function RestorePoint(region, point)
    if not (region and point and region.ClearAllPoints and region.SetPoint) then
        return
    end
    region:ClearAllPoints()
    region:SetPoint(point.point, point.relativeTo, point.relativePoint, point.x or 0, point.y or 0)
end

local function GetMacroSelectorView(selector)
    local scrollBox = selector and selector.ScrollBox
    if scrollBox and type(scrollBox.GetView) == "function" then
        return scrollBox:GetView()
    end
end

local function CaptureSelectorResolvedPadding(selector)
    if not (selector and type(selector.GetPadding) == "function") then return nil end
    local top, bottom, left, right, horizontalSpacing, verticalSpacing = selector:GetPadding()
    return {
        top = top,
        bottom = bottom,
        left = left,
        right = right,
        horizontalSpacing = horizontalSpacing,
        verticalSpacing = verticalSpacing,
    }
end

local function CaptureViewPadding(view)
    if not (view and type(view.GetPadding) == "function") then return nil end
    local padding = view:GetPadding()
    if not padding then return nil end
    return {
        top = type(padding.GetTop) == "function" and padding:GetTop() or nil,
        bottom = type(padding.GetBottom) == "function" and padding:GetBottom() or nil,
        left = type(padding.GetLeft) == "function" and padding:GetLeft() or nil,
        right = type(padding.GetRight) == "function" and padding:GetRight() or nil,
        horizontalSpacing = type(padding.GetHorizontalSpacing) == "function" and padding:GetHorizontalSpacing() or nil,
        verticalSpacing = type(padding.GetVerticalSpacing) == "function" and padding:GetVerticalSpacing() or nil,
    }
end

local function SetSelectorPadding(target, padding)
    if not (target and type(target.SetPadding) == "function" and padding) then return end
    target:SetPadding(
        padding.top,
        padding.bottom,
        padding.left,
        padding.right,
        padding.horizontalSpacing,
        padding.verticalSpacing
    )
end

local function RefreshMacroSelectorView(selector)
    -- Only refresh layout; MacroFrame:Update() rebuilds native macro data callbacks.
    local scrollBox = selector and selector.ScrollBox
    if scrollBox and type(scrollBox.FullUpdate) == "function" then
        scrollBox:FullUpdate(true)
    end
end

local function ApplyMacroSelectorLayout(selector, columns)
    if type(selector.SetCustomStride) == "function" then
        selector:SetCustomStride(columns)
    end
    if type(selector.SetCustomPadding) == "function" then
        selector:SetCustomPadding(Unpack(MACRO_SELECTOR_PADDING))
    end

    local view = GetMacroSelectorView(selector)
    if view and type(view.SetStride) == "function" then
        view:SetStride(columns)
    end
    if view and type(view.SetPadding) == "function" then
        view:SetPadding(Unpack(MACRO_SELECTOR_PADDING))
    end
    if view then RefreshMacroSelectorView(selector) end
end

local function RestoreMacroSelectorLayout(selector, originals)
    if type(selector.SetCustomStride) == "function" then
        selector:SetCustomStride(originals.selectorCustomStride)
    end
    if type(selector.SetCustomPadding) == "function" then
        local padding = originals.selectorCustomPadding
        selector:SetCustomPadding(
            padding.top,
            padding.bottom,
            padding.left,
            padding.right,
            padding.horizontalSpacing,
            padding.verticalSpacing
        )
    end

    local view = GetMacroSelectorView(selector)
    if view and type(view.SetStride) == "function" then
        view:SetStride(originals.selectorViewStride or originals.selectorResolvedStride)
    end
    if view then
        SetSelectorPadding(view, originals.selectorViewPadding or originals.selectorResolvedPadding)
        RefreshMacroSelectorView(selector)
    end
end

local function IsMacroFrameReady()
    return _G.MacroFrame and _G.MacroFrame.MacroSelector
end

local function IsExternalMacroExpansionActive()
    if macroFrameApplied or not IsMacroFrameReady() then
        return false
    end

    local frame = _G.MacroFrame
    local selector = frame.MacroSelector
    local frameWidth = frame.GetWidth and frame:GetWidth() or MACRO_NATIVE_FRAME_WIDTH
    local selectorWidth = selector.GetWidth and selector:GetWidth() or MACRO_NATIVE_SELECTOR_WIDTH
    local selectorHeight = selector.GetHeight and selector:GetHeight() or MACRO_NATIVE_SELECTOR_HEIGHT

    return frameWidth > (MACRO_NATIVE_FRAME_WIDTH + MACRO_EXTERNAL_WIDTH_PADDING)
        or selectorWidth > (MACRO_NATIVE_SELECTOR_WIDTH + MACRO_EXTERNAL_WIDTH_PADDING)
        or selectorHeight > (MACRO_NATIVE_SELECTOR_HEIGHT + MACRO_EXTERNAL_WIDTH_PADDING)
end

local function CaptureMacroOriginals()
    local frame = _G.MacroFrame
    local selector = frame and frame.MacroSelector
    if not (frame and selector) then
        return nil
    end

    local view = GetMacroSelectorView(selector)
    return {
        frameWidth = frame:GetWidth(),
        frameHeight = frame:GetHeight(),
        panelWidth = UIPanelWindows and UIPanelWindows.MacroFrame and UIPanelWindows.MacroFrame.width,
        selectorWidth = selector:GetWidth(),
        selectorHeight = selector:GetHeight(),
        selectorPoint = CapturePoint(selector),
        selectorCustomStride = selector.customStride,
        selectorResolvedStride = type(selector.GetStride) == "function" and selector:GetStride() or nil,
        selectorCustomPadding = {
            top = selector.top,
            bottom = selector.bottom,
            left = selector.left,
            right = selector.right,
            horizontalSpacing = selector.horizontalSpacing,
            verticalSpacing = selector.verticalSpacing,
        },
        selectorResolvedPadding = CaptureSelectorResolvedPadding(selector),
        selectorViewStride = view and type(view.GetStride) == "function" and view:GetStride() or nil,
        selectorViewPadding = CaptureViewPadding(view),
        selectedBackgroundPoint = CapturePoint(_G.MacroFrameSelectedMacroBackground),
        horizontalBarPoint = CapturePoint(_G.MacroHorizontalBarLeft),
        textBackgroundPoint = CapturePoint(_G.MacroFrameTextBackground),
        selectedNameWidth = _G.MacroFrameSelectedMacroName and _G.MacroFrameSelectedMacroName:GetWidth(),
        scrollWidth = _G.MacroFrameScrollFrame and _G.MacroFrameScrollFrame:GetWidth(),
        scrollHeight = _G.MacroFrameScrollFrame and _G.MacroFrameScrollFrame:GetHeight(),
        textWidth = _G.MacroFrameText and _G.MacroFrameText:GetWidth(),
        textHeight = _G.MacroFrameText and _G.MacroFrameText:GetHeight(),
        textButtonWidth = _G.MacroFrameTextButton and _G.MacroFrameTextButton:GetWidth(),
        textButtonHeight = _G.MacroFrameTextButton and _G.MacroFrameTextButton:GetHeight(),
        textBackgroundWidth = _G.MacroFrameTextBackground and _G.MacroFrameTextBackground:GetWidth(),
        textBackgroundHeight = _G.MacroFrameTextBackground and _G.MacroFrameTextBackground:GetHeight(),
    }
end

local function SetMacroPanelWidth(frame, width)
    if SetUIPanelAttribute then
        SetUIPanelAttribute(frame, "width", width)
    elseif UIPanelWindows and UIPanelWindows.MacroFrame then
        UIPanelWindows.MacroFrame.width = width
    end
end

local function ApplyMacroFrameLayout()
    if YUI.IsForever and InCombatLockdown and InCombatLockdown() then return end
    if not IsMacroFrameOptionEnabled() or not IsMacroFrameReady() then
        return
    end

    local frame = _G.MacroFrame
    local selector = frame.MacroSelector
    if not macroFrameApplied then
        if IsExternalMacroExpansionActive() then
            return
        end
        macroFrameOriginals = CaptureMacroOriginals()
        if not macroFrameOriginals then
            return
        end
        macroFrameApplied = true
        frame.yuiUtilityToolsMacroExpanded = true
    end

    local db = GetDB()
    local layout = MACRO_LAYOUTS[db.macroFrame.visibleCount] or MACRO_LAYOUTS[MACRO_DEFAULT_VISIBLE_COUNT]
    local widthDelta = (layout.columns - MACRO_LAYOUT_BASE_COLUMNS) * MACRO_LAYOUT_COLUMN_STEP
    local heightDelta = (layout.rows - MACRO_LAYOUT_BASE_ROWS) * MACRO_LAYOUT_ROW_STEP
    local frameWidth = MACRO_LAYOUT_BASE_FRAME_WIDTH + widthDelta
    local frameHeight = MACRO_LAYOUT_BASE_FRAME_HEIGHT + heightDelta

    frame:SetSize(frameWidth, frameHeight)
    SetMacroPanelWidth(frame, frameWidth)

    selector:ClearAllPoints()
    selector:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -66)
    selector:SetSize(MACRO_LAYOUT_BASE_SELECTOR_WIDTH + widthDelta, MACRO_LAYOUT_BASE_SELECTOR_HEIGHT + heightDelta)
    ApplyMacroSelectorLayout(selector, layout.columns)

    if _G.MacroHorizontalBarLeft then
        _G.MacroHorizontalBarLeft:ClearAllPoints()
        _G.MacroHorizontalBarLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -258 - heightDelta)
    end
    if _G.MacroFrameSelectedMacroBackground then
        _G.MacroFrameSelectedMacroBackground:ClearAllPoints()
        _G.MacroFrameSelectedMacroBackground:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -266 - heightDelta)
    end
    if _G.MacroFrameSelectedMacroName then
        _G.MacroFrameSelectedMacroName:SetWidth(360 + widthDelta)
    end
    if _G.MacroFrameScrollFrame then
        _G.MacroFrameScrollFrame:SetSize(392 + widthDelta, 85)
    end
    if _G.MacroFrameText then
        _G.MacroFrameText:SetSize(392 + widthDelta, 85)
    end
    if _G.MacroFrameTextButton then
        _G.MacroFrameTextButton:SetSize(392 + widthDelta, 85)
    end
    if _G.MacroFrameTextBackground then
        _G.MacroFrameTextBackground:ClearAllPoints()
        _G.MacroFrameTextBackground:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -337 - heightDelta)
        _G.MacroFrameTextBackground:SetSize(428 + widthDelta, 95)
    end

end

local function RestoreMacroFrameLayout()
    if not (macroFrameApplied and macroFrameOriginals and IsMacroFrameReady()) then
        return
    end

    local frame = _G.MacroFrame
    local selector = frame.MacroSelector
    frame:SetSize(macroFrameOriginals.frameWidth or MACRO_NATIVE_FRAME_WIDTH, macroFrameOriginals.frameHeight or MACRO_NATIVE_FRAME_HEIGHT)
    SetMacroPanelWidth(frame, macroFrameOriginals.panelWidth or MACRO_NATIVE_FRAME_WIDTH)

    selector:SetSize(macroFrameOriginals.selectorWidth or MACRO_NATIVE_SELECTOR_WIDTH, macroFrameOriginals.selectorHeight or MACRO_NATIVE_SELECTOR_HEIGHT)
    RestorePoint(selector, macroFrameOriginals.selectorPoint)
    RestoreMacroSelectorLayout(selector, macroFrameOriginals)

    RestorePoint(_G.MacroHorizontalBarLeft, macroFrameOriginals.horizontalBarPoint)
    RestorePoint(_G.MacroFrameSelectedMacroBackground, macroFrameOriginals.selectedBackgroundPoint)
    RestorePoint(_G.MacroFrameTextBackground, macroFrameOriginals.textBackgroundPoint)
    if _G.MacroFrameSelectedMacroName and macroFrameOriginals.selectedNameWidth then
        _G.MacroFrameSelectedMacroName:SetWidth(macroFrameOriginals.selectedNameWidth)
    end
    if _G.MacroFrameScrollFrame then
        _G.MacroFrameScrollFrame:SetSize(macroFrameOriginals.scrollWidth or 286, macroFrameOriginals.scrollHeight or 85)
    end
    if _G.MacroFrameText then
        _G.MacroFrameText:SetSize(macroFrameOriginals.textWidth or 286, macroFrameOriginals.textHeight or 85)
    end
    if _G.MacroFrameTextButton then
        _G.MacroFrameTextButton:SetSize(macroFrameOriginals.textButtonWidth or 286, macroFrameOriginals.textButtonHeight or 85)
    end
    if _G.MacroFrameTextBackground then
        _G.MacroFrameTextBackground:SetSize(macroFrameOriginals.textBackgroundWidth or 322, macroFrameOriginals.textBackgroundHeight or 95)
    end

    frame.yuiUtilityToolsMacroExpanded = nil
    macroFrameApplied = false
    macroFrameOriginals = nil
end

local function OnAddonLoaded(event, addonName)
    if addonName == MACRO_UI_ADDON then
        ApplyMacroFrameLayout()
    end
end

local function IsMacroUILoaded()
    if type(System) == "table" and type(System.GetAddOnLoadedState) == "function" then
        local ok, loaded = pcall(System.GetAddOnLoadedState, MACRO_UI_ADDON)
        if ok and loaded == true then return true end
    end
    return IsMacroFrameReady()
end

local RefreshMacroFrameRuntime

local function AttachMacroEvent()
    if macroEventAttached then
        return
    end

    if Event and Event.On then
        Event:On("ADDON_LOADED", OnAddonLoaded, macroEventOwner, {
            moduleId = "component:" .. FEATURE_KEY,
            traceName = "UtilityTools:macro-ui-loaded",
        })
        if YUI.IsForever then
            Event:On("PLAYER_REGEN_ENABLED", function() RefreshMacroFrameRuntime() end, macroEventOwner)
        end
        macroEventAttached = true
        return
    end

    if CreateFrame then
        macroEventFrame = macroEventFrame or CreateFrame("Frame")
        macroEventFrame:RegisterEvent("ADDON_LOADED")
        macroEventFrame:SetScript("OnEvent", OnAddonLoaded)
        macroEventAttached = true
    end
end

local function DetachMacroEvent()
    if not macroEventAttached then
        return
    end

    if Event and Event.OffOwner then
        Event:OffOwner(macroEventOwner)
    end
    if macroEventFrame then
        macroEventFrame:UnregisterEvent("ADDON_LOADED")
        macroEventFrame:SetScript("OnEvent", nil)
    end
    macroEventAttached = false
end

RefreshMacroFrameRuntime = function()
    if YUI.IsForever and InCombatLockdown and InCombatLockdown() then
        AttachMacroEvent()
        return
    end
    if IsMacroFrameOptionEnabled() then
        AttachMacroEvent()
        if IsMacroUILoaded() then
            ApplyMacroFrameLayout()
        end
    else
        RestoreMacroFrameLayout()
        DetachMacroEvent()
    end
end

local function UtilityPrint(message)
    if type(YUI.Print) == "function" then
        YUI:Print(message)
    elseif type(print) == "function" then
        print(message)
    end
end

local function CloseBonusRollPopup()
    if S and type(S.HideConfirmPopup) == "function" then
        S:HideConfirmPopup(bonusRollPopupOwner)
    end
end

local function GetSafeBonusRollIdentity(frame)
    local spellID = frame and frame.spellID
    if spellID == nil then return nil end
    if Security and type(Security.IsSecretValue) == "function"
        and Security.IsSecretValue(spellID) then
        return nil
    end
    return spellID
end

local function GetLootSpecializationInfo()
    if type(TalentAPI) ~= "table" then
        return nil, T("bonus_roll.spec_unknown", "未知"), nil
    end

    local specID = type(TalentAPI.GetLootSpecialization) == "function"
        and TalentAPI.GetLootSpecialization() or nil
    if Security and type(Security.SafeNumber) == "function" then
        specID = Security.SafeNumber(specID)
    end
    if specID and specID > 0 and type(TalentAPI.GetSpecializationInfoByID) == "function" then
        local resolvedID, name, _, nativeIcon = TalentAPI.GetSpecializationInfoByID(specID)
        if name and not (Security and Security.IsSecretValue and Security.IsSecretValue(name)) then
            if Security and Security.IsSecretValue and Security.IsSecretValue(nativeIcon) then
                nativeIcon = nil
            end
            local displayName = YUI.Locale and YUI.Locale.GetSpecializationName
                and YUI.Locale:GetSpecializationName(resolvedID or specID, name)
                or name
            return resolvedID or specID, displayName, nativeIcon
        end
    end

    local specIndex = type(TalentAPI.GetSpecialization) == "function"
        and TalentAPI.GetSpecialization() or nil
    if Security and type(Security.SafeNumber) == "function" then
        specIndex = Security.SafeNumber(specIndex)
    end
    if specIndex and type(TalentAPI.GetSpecializationInfo) == "function" then
        local resolvedID, name, _, nativeIcon = TalentAPI.GetSpecializationInfo(specIndex)
        if name and not (Security and Security.IsSecretValue and Security.IsSecretValue(name)) then
            if Security and Security.IsSecretValue and Security.IsSecretValue(nativeIcon) then
                nativeIcon = nil
            end
            local displayName = YUI.Locale and YUI.Locale.GetSpecializationName
                and YUI.Locale:GetSpecializationName(resolvedID, name)
                or name
            return resolvedID, displayName, nativeIcon
        end
    end
    return nil, T("bonus_roll.spec_unknown", "未知"), nil
end

local function IsSecretValue(value)
    return Security and type(Security.IsSecretValue) == "function"
        and Security.IsSecretValue(value) == true
end

local function SafeCall(label, func, ...)
    if type(func) ~= "function" then return false, nil end
    if Security and type(Security.SafeCall) == "function" then
        return Security.SafeCall(label, func, ...)
    end
    return pcall(func, ...)
end

local function ReadField(object, key)
    return object[key]
end

local function ReadSafeField(object, key)
    if type(object) ~= "table" or IsSecretValue(object) then return nil end
    local ok, value = SafeCall("UtilityTools:ReadBonusRollField", ReadField, object, key)
    if not ok or IsSecretValue(value) then return nil end
    return value
end

local function ReadSafeNumber(value)
    if Security and type(Security.SafeNumber) == "function" then
        return Security.SafeNumber(value)
    end
    if value == nil or IsSecretValue(value) then return nil end
    local ok, numberValue = pcall(tonumber, value)
    return ok and numberValue or nil
end

local function ReadSafeString(value)
    if Security and type(Security.SafeString) == "function" then
        return Security.SafeString(value)
    end
    if type(value) == "string" and not IsSecretValue(value) then
        return value
    end
    return nil
end

local function ColorByte(value)
    value = math.max(0, math.min(ReadSafeNumber(value) or 1, 1))
    return math.floor(value * 255 + 0.5)
end

local function WrapRGBText(text, r, g, b)
    return string.format(
        "|cff%02x%02x%02x%s|r",
        ColorByte(r),
        ColorByte(g),
        ColorByte(b),
        text
    )
end

local function WrapThemeText(text, colorKey, fallbackR, fallbackG, fallbackB)
    local r, g, b = fallbackR, fallbackG, fallbackB
    if GUI2 and type(GUI2.GetColor) == "function" then
        local ok, resolvedR, resolvedG, resolvedB = SafeCall(
            "UtilityTools:GetBonusRollTextColor",
            GUI2.GetColor,
            GUI2,
            colorKey
        )
        if ok then
            r = ReadSafeNumber(resolvedR) or r
            g = ReadSafeNumber(resolvedG) or g
            b = ReadSafeNumber(resolvedB) or b
        end
    end
    return WrapRGBText(text, r, g, b)
end

local function WrapPlayerClassText(text)
    if type(UnitAPI) == "table"
        and type(UnitAPI.UnitClass) == "function"
        and type(UnitAPI.GetClassColor) == "function" then
        local ok, _, classToken = SafeCall(
            "UtilityTools:GetBonusRollPlayerClass",
            UnitAPI.UnitClass,
            "player"
        )
        classToken = ok and ReadSafeString(classToken) or nil
        if classToken then
            local colorOK, color = SafeCall(
                "UtilityTools:GetBonusRollClassColor",
                UnitAPI.GetClassColor,
                classToken
            )
            if colorOK and type(color) == "table" and not IsSecretValue(color) then
                local r = ReadSafeNumber(ReadSafeField(color, "r"))
                local g = ReadSafeNumber(ReadSafeField(color, "g"))
                local b = ReadSafeNumber(ReadSafeField(color, "b"))
                if r and g and b then
                    return WrapRGBText(text, r, g, b)
                end
            end
        end
    end
    return WrapThemeText(text, "color.class.text", 1, 0.82, 0)
end

local function RoundIconPixel(value)
    value = ReadSafeNumber(value)
    return value and math.floor(value * BONUS_ROLL_CUSTOM_ICON_DIMENSION + 0.5) or nil
end

local function FormatBonusRollSpecIcon(iconData)
    if type(iconData) ~= "table" or IsSecretValue(iconData) then return nil end

    local atlas = ReadSafeString(ReadSafeField(iconData, "atlas"))
    if atlas then
        return string.format(
            "|A:%s:%d:%d:0:0|a",
            atlas,
            BONUS_ROLL_SPEC_ICON_SIZE,
            BONUS_ROLL_SPEC_ICON_SIZE
        )
    end

    local texture = ReadSafeField(iconData, "texture")
    if IsSecretValue(texture) or (type(texture) ~= "number" and type(texture) ~= "string") then
        return nil
    end

    local custom = ReadSafeField(iconData, "custom") == true
    local texCoord = custom and ReadSafeField(iconData, "texCoord") or nil
    if type(texCoord) == "table" then
        local left = RoundIconPixel(ReadSafeField(texCoord, 1))
        local right = RoundIconPixel(ReadSafeField(texCoord, 2))
        local top = RoundIconPixel(ReadSafeField(texCoord, 3))
        local bottom = RoundIconPixel(ReadSafeField(texCoord, 4))
        if left and right and top and bottom and right > left and bottom > top then
            return string.format(
                "|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d|t",
                tostring(texture),
                BONUS_ROLL_SPEC_ICON_SIZE,
                BONUS_ROLL_SPEC_ICON_SIZE,
                BONUS_ROLL_CUSTOM_ICON_DIMENSION,
                BONUS_ROLL_CUSTOM_ICON_DIMENSION,
                left,
                right,
                top,
                bottom
            )
        end
    end

    return string.format(
        "|T%s:%d:%d:0:0:%d:%d:4:60:4:60|t",
        tostring(texture),
        BONUS_ROLL_SPEC_ICON_SIZE,
        BONUS_ROLL_SPEC_ICON_SIZE,
        BONUS_ROLL_NATIVE_ICON_DIMENSION,
        BONUS_ROLL_NATIVE_ICON_DIMENSION
    )
end

local function GetLootSpecializationDisplay()
    local specID, name, nativeIcon = GetLootSpecializationInfo()
    local iconData
    if type(Icons) == "table" and type(Icons.GetScopedSpecIcon) == "function" then
        local ok, result = SafeCall(
            "UtilityTools:GetBonusRollSpecIcon",
            Icons.GetScopedSpecIcon,
            specID,
            nativeIcon,
            BONUS_ROLL_ICON_SCOPE_ID
        )
        if ok and type(result) == "table" and not IsSecretValue(result) then
            iconData = result
        end
    end
    if not iconData and nativeIcon ~= nil and not IsSecretValue(nativeIcon) then
        iconData = {
            texture = nativeIcon,
            texCoord = { 0, 1, 0, 1 },
            custom = false,
        }
    end

    local icon = FormatBonusRollSpecIcon(iconData)
    local coloredName = WrapPlayerClassText(name)
    return icon and (icon .. " " .. coloredName) or coloredName
end

local function FormatBonusRollQuantity(quantity)
    if type(BreakUpLargeNumbers) == "function" then
        local ok, text = SafeCall(
            "UtilityTools:FormatBonusRollQuantity",
            BreakUpLargeNumbers,
            quantity
        )
        text = ok and ReadSafeString(text) or nil
        if text and text ~= "" then return text end
    end
    return tostring(quantity)
end

local function ReadBlizzardBonusRollCountText(currentCountFrame)
    local textRegion = ReadSafeField(currentCountFrame, "Text")
    local getText = ReadSafeField(textRegion, "GetText")
    local ok, text = SafeCall("UtilityTools:GetBonusRollCountText", getText, textRegion)
    text = ok and ReadSafeString(text) or nil
    return text and text ~= "" and text or nil
end

local function IsActiveBonusRollFrame(frame)
    if not frame or ReadSafeField(frame, "state") ~= "prompt" then return false end
    local isShown = ReadSafeField(frame, "IsShown")
    if type(isShown) ~= "function" then return true end
    local ok, shown = SafeCall("UtilityTools:IsBonusRollFrameShown", isShown, frame)
    return ok and shown == true and not IsSecretValue(shown)
end

local function GetBonusRollCurrencyNote(ownerFrame, isTestPreview)
    local frame = ownerFrame
    if isTestPreview and not IsActiveBonusRollFrame(frame) then
        frame = _G.BonusRollFrame
    end

    local useFrameCurrency = frame ~= nil
        and (not isTestPreview or IsActiveBonusRollFrame(frame))
    local currentCountFrame = useFrameCurrency and ReadSafeField(frame, "CurrentCountFrame") or nil
    local currencyID = ReadSafeNumber(ReadSafeField(currentCountFrame, "currencyID"))
    if not currencyID and isTestPreview then
        currencyID = BONUS_ROLL_TEST_CURRENCY_ID
    end

    local currencyAPI = _G.C_CurrencyInfo
    local getCurrencyInfo = ReadSafeField(currencyAPI, "GetCurrencyInfo")
    local ok, currencyInfo = SafeCall(
        "UtilityTools:GetBonusRollCurrencyInfo",
        getCurrencyInfo,
        currencyID
    )
    if ok and type(currencyInfo) == "table" and not IsSecretValue(currencyInfo) then
        local quantity = ReadSafeNumber(ReadSafeField(currencyInfo, "quantity"))
        local iconFileID = ReadSafeNumber(ReadSafeField(currencyInfo, "iconFileID"))
        if quantity and iconFileID then
            local icon = string.format(
                "|T%s:18:18:0:0:64:64:5:59:5:59|t",
                tostring(iconFileID)
            )
            return string.format(
                T("bonus_roll.roll_currency", "剩余ROLL币： %s %s"),
                icon,
                FormatBonusRollQuantity(quantity)
            )
        end
    end

    local blizzardText = ReadBlizzardBonusRollCountText(currentCountFrame)
    if blizzardText then return blizzardText end
    return T("bonus_roll.roll_currency_unavailable", "剩余ROLL币： —")
end

local function ShowBonusRollPopup(kind, ownerFrame, onConfirm, isTestPreview)
    if not (S and type(S.ShowConfirmPopup) == "function") then
        UtilityPrint(T("bonus_roll.popup_unavailable", "确认界面当前不可用，本次操作未执行。"))
        return false
    end

    local isRoll = kind == "roll"
    local message
    if isRoll then
        local specializationLine = string.format(
            T("bonus_roll.roll_specialization", "当前拾取专精：%s"),
            GetLootSpecializationDisplay()
        )
        local questionLine = WrapThemeText(
            T("bonus_roll.roll_question", "确定消耗一次额外奖励机会吗？"),
            "color.state.success",
            0.21,
            0.75,
            0.38
        )
        local currencyLine = GetBonusRollCurrencyNote(ownerFrame, isTestPreview == true)
        message = specializationLine .. "\n\n" .. questionLine .. "\n\n" .. currencyLine
    else
        local passWord = WrapThemeText(
            T("bonus_roll.pass_action_word", "放弃"),
            "color.state.danger",
            0.92,
            0.18,
            0.18
        )
        message = string.format(
            T("bonus_roll.pass_message", "确定%s本次额外奖励机会吗？"),
            passWord
        )
    end
    local action = {
        text = isRoll and T("bonus_roll.confirm_roll", "确定ROLL")
            or T("bonus_roll.confirm_pass", "放弃ROLL"),
        tone = isRoll and "warning" or "danger",
        style = isRoll and "warningFilled" or "dangerFilled",
        width = 122,
        height = 30,
        callback = onConfirm,
    }
    local cancel = {
        text = T("bonus_roll.return", "返回"),
        tone = "default",
        style = "grayFilled",
        width = 100,
        height = 30,
    }

    S:ShowConfirmPopup(message, nil, {
        titleText = isRoll and T("bonus_roll.roll_title", "真的Roll吗？")
            or T("bonus_roll.pass_title", "不Roll了吗？"),
        height = isRoll and 205 or 175,
        messageTopOffset = isRoll and 50 or 65,
        buttonGap = 18,
        buttons = { action, cancel },
        appearance = BONUS_ROLL_APPEARANCE,
        scrimAlpha = 0.55,
        owner = bonusRollPopupOwner,
        ownerFrame = ownerFrame,
        dismissWithOwner = ownerFrame ~= nil,
    })
    return true
end

local function RestoreBonusRollBinding(kind)
    local binding = bonusRollBindings[kind]
    local button = binding and binding.button
    if button and button.GetScript and button.SetScript
        and button:GetScript("OnClick") == binding.wrapper then
        button:SetScript("OnClick", binding.originalOnClick)
    end
    if binding then
        binding.button = nil
        binding.originalOnClick = nil
        binding.wrapper = nil
    end
end

local function IsCurrentBonusRollPrompt(frame, button, spellID)
    if not (frame and button) or _G.BonusRollFrame ~= frame then return false end
    if frame.state ~= "prompt" then return false end
    if frame.IsShown and not frame:IsShown() then return false end
    if button.IsShown and not button:IsShown() then return false end
    if button.IsEnabled and not button:IsEnabled() then return false end

    local currentSpellID = GetSafeBonusRollIdentity(frame)
    return currentSpellID ~= nil and currentSpellID == spellID
end

local function BindBonusRollButton(kind, button)
    local binding = bonusRollBindings[kind]
    if not (binding and button and button.GetScript and button.SetScript) then
        RestoreBonusRollBinding(kind)
        return false
    end
    if binding.button == button and button:GetScript("OnClick") == binding.wrapper then
        return true
    end

    RestoreBonusRollBinding(kind)
    local originalOnClick = button:GetScript("OnClick")
    if type(originalOnClick) ~= "function" then
        return false
    end

    local wrapper
    wrapper = function(self, mouseButton, down)
        local frame = _G.BonusRollFrame
        local spellID = GetSafeBonusRollIdentity(frame)
        if spellID == nil then
            UtilityPrint(T("bonus_roll.prompt_expired", "额外奖励状态已失效，本次操作未执行。"))
            return
        end

        local executed = false
        ShowBonusRollPopup(kind, frame, function()
            if executed then return end
            executed = true
            if not IsCurrentBonusRollPrompt(frame, self, spellID) then
                UtilityPrint(T("bonus_roll.prompt_expired", "额外奖励状态已失效，本次操作未执行。"))
                return
            end
            originalOnClick(self, mouseButton, down)
        end)
    end

    binding.button = button
    binding.originalOnClick = originalOnClick
    binding.wrapper = wrapper
    button:SetScript("OnClick", wrapper)
    return true
end

local function RefreshBonusRollBindings()
    if not IS_MAINLINE then return end
    local db = GetDB()
    local frame = _G.BonusRollFrame
    local prompt = frame and frame.PromptFrame

    if featureEnabled and db.bonusRoll.rollConfirm == true then
        BindBonusRollButton("roll", prompt and prompt.RollButton)
    else
        RestoreBonusRollBinding("roll")
    end
    if featureEnabled and db.bonusRoll.passConfirm == true then
        BindBonusRollButton("pass", prompt and prompt.PassButton)
    else
        RestoreBonusRollBinding("pass")
    end
end

local function OnBonusRollStarted()
    CloseBonusRollPopup()
    RefreshBonusRollBindings()
end

local function OnBonusRollFinished()
    CloseBonusRollPopup()
end

local function AttachBonusRollEvents()
    if bonusRollEventsAttached or not (Event and Event.On) then return end
    Event:On("BONUS_ROLL_STARTED", OnBonusRollStarted, bonusRollEventOwner, {
        moduleId = "component:" .. FEATURE_KEY,
        traceName = "UtilityTools:bonus-roll-started",
    })
    Event:On("BONUS_ROLL_FAILED", OnBonusRollFinished, bonusRollEventOwner, {
        moduleId = "component:" .. FEATURE_KEY,
        traceName = "UtilityTools:bonus-roll-failed",
    })
    Event:On("BONUS_ROLL_RESULT", OnBonusRollFinished, bonusRollEventOwner, {
        moduleId = "component:" .. FEATURE_KEY,
        traceName = "UtilityTools:bonus-roll-result",
    })
    bonusRollEventsAttached = true
end

local function DetachBonusRollEvents()
    if not bonusRollEventsAttached then return end
    if Event and Event.OffOwner then
        Event:OffOwner(bonusRollEventOwner)
    end
    bonusRollEventsAttached = false
end

local function RefreshBonusRollRuntime()
    if not IS_MAINLINE then return end
    CloseBonusRollPopup()
    local db = GetDB()
    local active = featureEnabled
        and (db.bonusRoll.rollConfirm == true or db.bonusRoll.passConfirm == true)
    if active then
        AttachBonusRollEvents()
        RefreshBonusRollBindings()
    else
        RestoreBonusRollBinding("roll")
        RestoreBonusRollBinding("pass")
        DetachBonusRollEvents()
    end
end


local function RefreshNameplateRuntime()
    local runtime = YUI.UtilityToolsNameplates
    if not HAS_NAMEPLATE_SYNC then return end
    local db = GetDB()
    if runtime then
        if featureEnabled and db.syncFriendlyNameplates == true then
            runtime:Enable()
        else
            runtime:Disable()
        end
    end
    local outline = YUI.UtilityToolsNameplateOutline
    if outline then
        if featureEnabled and db.nameplateOutline == true then
            outline:Enable()
        else
            outline:Disable()
        end
    end
end

local function RefreshRuntime()
    ToggleHideErrorsFiltering(IsHideErrorsOptionEnabled())
    RefreshMacroFrameRuntime()
    RefreshBonusRollRuntime()
    RefreshNameplateRuntime()
end

local function ReloadUIFromCommand()
    if FrameAPI and type(FrameAPI.ReloadUI) == "function" then
        FrameAPI.ReloadUI()
        return
    end
    if type(ReloadUI) == "function" then
        ReloadUI()
    end
end

local function NormalizeCommandMessage(message)
    return tostring(message or ""):lower():match("^%s*(.-)%s*$")
end

local function RunBonusRollTestCommand(message)
    message = NormalizeCommandMessage(message)
    if message == "" or message == "test" or message == "test roll" then
        ShowBonusRollPopup("roll", nil, function()
            UtilityPrint(T("bonus_roll.test_roll_confirmed", "ROLL确认界面测试完成；未执行真实ROLL。"))
        end, true)
        return
    end
    if message == "test pass" then
        ShowBonusRollPopup("pass", nil, function()
            UtilityPrint(T("bonus_roll.test_pass_confirmed", "放弃确认界面测试完成；未执行真实放弃。"))
        end)
        return
    end
    UtilityPrint(T("bonus_roll.command_usage", "用法：/yroll test 或 /yroll test pass"))
end

local function RegisterUtilityCommands()
    if not (YUI.Commands and YUI.Commands.Register) then
        return
    end

    YUI.Commands:Register({
        id = "utilitytools.reload",
        productId = PRODUCT_ID,
        aliases = { "/rl" },
        handler = ReloadUIFromCommand,
    })
    if IS_MAINLINE then
        YUI.Commands:Register({
            id = "utilitytools.bonusroll",
            productId = PRODUCT_ID,
            aliases = { "/yroll" },
            handler = RunBonusRollTestCommand,
        })
    end
end

local function ClampNumber(value, minValue, maxValue, fallback)
    value = tonumber(value)
    if not value then
        return fallback
    end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function GetMacroVisibleCountOptions()
    local options = {}
    for _, visibleCount in ipairs({ 32, 40, 50, 60, 80 }) do
        local layout = MACRO_LAYOUTS[visibleCount]
        options[#options + 1] = {
            text = string.format("%d (%d×%d)", visibleCount, layout.columns, layout.rows),
            value = visibleCount,
        }
    end
    return options
end

local function GetModeOptions()
    return {
        { text = T("mode.block_allowlist", "屏蔽非重要红字"), value = MODE_BLOCK_ALLOWLIST },
        { text = T("mode.throttle_once", "节流重复红字"), value = MODE_THROTTLE_ONCE },
    }
end

local sectionCollapsed = {}

local function IsSectionCollapsed(sectionKey)
    return sectionCollapsed[sectionKey] == true
end

local function RefreshFeatureSettings(feature)
    if feature and feature.RefreshCurrentModule then
        feature:RefreshCurrentModule()
    end
end

local function SetSectionCollapsed(feature, sectionKey, collapsed)
    sectionCollapsed[sectionKey] = collapsed == true
    RefreshFeatureSettings(feature)
end

local function CreateSectionDivider(feature, sectionKey, label)
    return {
        type = "divider",
        label = label,
        width = 620,
        alignLeft = true,
        collapsible = true,
        collapsed = IsSectionCollapsed(sectionKey),
        onToggle = function(collapsed)
            SetSectionCollapsed(feature, sectionKey, collapsed)
        end,
    }
end

local function CreateSectionHidden(sectionKey)
    return function()
        return IsSectionCollapsed(sectionKey)
    end
end

local function GetSubFeatureStates()
    local db = Components:CopyConfigSnapshot(CONFIG_KEY, DEFAULTS, PRODUCT_ID)
    if not db then return {} end
    local rows = {}
    if HAS_NAMEPLATE_SYNC then
        rows[#rows + 1] = { label = T("settings.sync_friendly_nameplates", "友方姓名板联动"), enabled = db.syncFriendlyNameplates == true }
        rows[#rows + 1] = { label = T("settings.nameplate_outline", "姓名板文字描边"), enabled = db.nameplateOutline == true }
    end
    if IS_MAINLINE then
        rows[#rows + 1] = { label = T("settings.bonus_roll_confirm_roll", "ROLL 前确认"), enabled = db.bonusRoll.rollConfirm == true }
        rows[#rows + 1] = { label = T("settings.bonus_roll_confirm_pass", "放弃前确认"), enabled = db.bonusRoll.passConfirm == true }
    end
    rows[#rows + 1] = { label = T("settings.macro_frame", "宏命令界面扩展"), enabled = db.macroFrame.enabled == true }
    rows[#rows + 1] = { label = T("settings.hide_errors", "隐藏错误提示"), enabled = db.hideErrors.enabled == true }
    return rows
end

local function GetOptions(feature)
    local db = GetDB()
    local optionWidth = 210
    local fieldWidth = 280
    local macroHidden = CreateSectionHidden("macroFrame")
    local hideErrorsHidden = CreateSectionHidden("hideErrors")
    local bonusRollHidden = CreateSectionHidden("bonusRoll")

    local options = {}
    if IS_MAINLINE then
        options[#options + 1] = CreateSectionDivider(
            feature,
            "bonusRoll",
            T("settings.bonus_roll", "Roll币额外确认")
        )
        options[#options + 1] = {
            type = "row",
            gap = 16,
            hidden = bonusRollHidden,
            children = {
                {
                    type = "checkbox",
                    text = T("settings.bonus_roll_confirm_roll", "ROLL 前确认"),
                    width = optionWidth,
                    get = function() return db.bonusRoll.rollConfirm == true end,
                    set = function(value)
                        db.bonusRoll.rollConfirm = value == true
                        RefreshBonusRollRuntime()
                    end,
                },
                {
                    type = "checkbox",
                    text = T("settings.bonus_roll_confirm_pass", "放弃前确认"),
                    width = optionWidth,
                    get = function() return db.bonusRoll.passConfirm == true end,
                    set = function(value)
                        db.bonusRoll.passConfirm = value == true
                        RefreshBonusRollRuntime()
                    end,
                },
            },
        }
    end

    local commonOptions = {
        CreateSectionDivider(feature, "macroFrame", T("settings.macro_frame", "宏命令界面扩展")),
        {
            type = "row",
            gap = 16,
            hidden = macroHidden,
            children = {
                {
                    type = "checkbox",
                    text = CT("common.enable", "启用"),
                    width = optionWidth,
                    get = function() return db.macroFrame.enabled == true end,
                    set = function(value)
                        db.macroFrame.enabled = value == true
                        RefreshMacroFrameRuntime()
                    end,
                },
                {
                    type = "dropdown",
                    label = T("settings.macro_visible_count", "一屏显示数量"),
                    inlineLabel = true,
                    width = fieldWidth,
                    controlWidth = 154,
                    options = GetMacroVisibleCountOptions(),
                    default = MACRO_DEFAULT_VISIBLE_COUNT,
                    get = function() return db.macroFrame.visibleCount end,
                    set = function(value)
                        db.macroFrame.visibleCount = NormalizeMacroVisibleCount(value)
                        RefreshMacroFrameRuntime()
                    end,
                },
            },
        },
        CreateSectionDivider(feature, "hideErrors", T("settings.hide_errors", "隐藏错误提示")),
        {
            type = "row",
            gap = 16,
            hidden = hideErrorsHidden,
            children = {
                {
                    type = "checkbox",
                    text = CT("common.enable", "启用"),
                    width = optionWidth,
                    get = function() return db.hideErrors.enabled == true end,
                    set = function(value)
                        db.hideErrors.enabled = value == true
                        ToggleHideErrorsFiltering(IsHideErrorsOptionEnabled())
                    end,
                },
            },
        },
        {
            type = "row",
            gap = 16,
            hidden = hideErrorsHidden,
            children = {
                {
                    type = "dropdown",
                    label = T("settings.hide_mode", "错误提示方式"),
                    inlineLabel = true,
                    width = fieldWidth,
                    controlWidth = 154,
                    options = GetModeOptions(),
                    default = MODE_BLOCK_ALLOWLIST,
                    get = function() return db.hideErrors.mode end,
                    set = function(value)
                        db.hideErrors.mode = IsValidMode(value) and value or MODE_BLOCK_ALLOWLIST
                        ClearThrottleRecords()
                        RefreshFeatureSettings(feature)
                    end,
                },
                {
                    type = "slider",
                    label = T("settings.throttle_window", "节流时间"),
                    inline = true,
                    width = fieldWidth,
                    labelWidth = 92,
                    inputWidth = 42,
                    min = 1,
                    max = 10,
                    step = 1,
                    get = function() return db.hideErrors.throttleWindow end,
                    set = function(value)
                        db.hideErrors.throttleWindow = ClampNumber(value, 1, 10, DEFAULTS.hideErrors.throttleWindow)
                        ClearThrottleRecords()
                    end,
                },
            },
        },
    }

    for _, option in ipairs(commonOptions) do
        options[#options + 1] = option
    end

    if HAS_NAMEPLATE_SYNC then
        options[#options + 1] = CreateSectionDivider(feature, "nameplates", T("settings.nameplates", "姓名板"))
        options[#options + 1] = {
            type = "checkbox",
            text = T("settings.sync_friendly_nameplates", "友方姓名板联动"),
            tooltip = T("settings.sync_friendly_nameplates.tooltip", "让友方 NPC 姓名板跟随友方玩家姓名板一起开关。"),
            hidden = CreateSectionHidden("nameplates"),
            get = function() return db.syncFriendlyNameplates == true end,
            set = function(value)
                db.syncFriendlyNameplates = value == true
                RefreshNameplateRuntime()
            end,
        }
        options[#options + 1] = {
            type = "checkbox",
            text = T("settings.nameplate_outline", "姓名板文字描边"),
            tooltip = T("settings.nameplate_outline.tooltip", "为缺少描边的姓名板文字补上描边，保留当前字体、字号及已有粗描边。共享字体也可能影响敌方名字和部分血量文字；战斗中修改会在脱战后生效。"),
            hidden = CreateSectionHidden("nameplates"),
            get = function() return db.nameplateOutline == true end,
            set = function(value)
                db.nameplateOutline = value == true
                RefreshNameplateRuntime()
            end,
        }
    end

    return options
end

local function ToggleFeature(enabled)
    featureEnabled = enabled == true
    RefreshRuntime()
end

local function RegisterProfileCallbacks()
    if profileCallbacksRegistered then return end
    if not (YUI.DB and type(YUI.DB.GetAceDB) == "function") then return end
    local db = YUI.DB:GetAceDB(PRODUCT_ID)
    if not (db and type(db.RegisterCallback) == "function") then return end
    db.RegisterCallback(profileOwner, "OnProfileChanged", "OnProfileChanged")
    db.RegisterCallback(profileOwner, "OnProfileCopied", "OnProfileChanged")
    db.RegisterCallback(profileOwner, "OnProfileReset", "OnProfileChanged")
    profileCallbacksRegistered = true
end

function profileOwner:OnProfileChanged()
    featureEnabled = Components.IsEnabled and Components:IsEnabled(FEATURE_KEY) or false
    RefreshRuntime()
end

Components:RegisterFeature(FEATURE_KEY, {
    name = T("name", "常用小工具"),
    description = T("description", "整合常用的小型界面与游戏辅助功能。"),
    default = true,
    product = PRODUCT_ID,
    storageKey = FEATURE_KEY,
    settingsMode = "inline",
    callback = ToggleFeature,
    GetOptions = GetOptions,
    GetSubFeatureStates = GetSubFeatureStates,
})

if Event and Event.Once then
    Event:Once("YUI_DB_READY", RegisterProfileCallbacks, profileOwner, {
        moduleId = "component:" .. FEATURE_KEY,
        traceName = "UtilityTools:profile-callbacks",
    })
    Event:Once("YUI_LOGIN_READY", RegisterUtilityCommands, reloadCommandOwner, {
        moduleId = "component:" .. FEATURE_KEY,
        traceName = "UtilityTools:commands",
    })
else
    RegisterUtilityCommands()
end
