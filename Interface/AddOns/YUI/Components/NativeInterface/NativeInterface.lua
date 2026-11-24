local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI then return end

local PRODUCT_ID = YUI.GetAddonProductId
    and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or (YUI.CoreMode == "suite" and "suite" or YUI.ProductId or "suite")
local IS_SUITE = PRODUCT_ID == "suite" and YUI.CoreMode == "suite"
local IS_ORBIT = PRODUCT_ID == "ybar" and YUI.IsRetail == true
if YUI.IsMists == true or not (IS_SUITE or IS_ORBIT) then return end

local Native = YUI.NativeInterface or {}
YUI.NativeInterface = Native

Native.PRODUCT_ID = PRODUCT_ID
Native.SETTINGS_SCOPE = PRODUCT_ID
Native.IS_SUITE = IS_SUITE
Native.MODULE_ID = IS_SUITE and "component.native_interface" or "ybar.native_interface"
Native.SETTINGS_MODULE_ID = IS_SUITE and "suite.settings.native_interface" or "ybar.settings.native_interface"
Native.TRANSFER_ID = IS_SUITE and "core.native_interface" or "ybar.native_interface"
Native.CONFIG_KEY = "NativeInterface_Config"
Native.ERROR_MESSAGES_LAYOUT_ID = "yui.component.nativeInterface.errorMessages"
Native.MIGRATION_VERSION = 3
Native.runtimeEnabled = false

local COMMON_DEFAULTS = {
    hideStatusTrackingBars = false,
    hideMicroMenu = false,
    manageBagsBar = true,
    bagsBarVisibility = "auto",
    _migrationVersion = 3,
}

local RETAIL_DEFAULTS = {
    hideBuffCollapseButton = false,
    manageTopCenterWidget = false,
    managePowerBarWidget = false,
    suppressSupertrackTutorial = true,
}

local FOREVER_WINDOW_DEFAULTS = {
    friendsEnhancementEnabled = true,
    socialListCompact = true,
    currentGameFirst = true,
    socialFontSize = 14,
    characterEnhancementEnabled = true,
    characterBottomTabs = true,
}

local COMMON_KEYS = {
    hideStatusTrackingBars = true,
    hideMicroMenu = true,
    manageBagsBar = true,
}

local RETAIL_KEYS = {
    hideBuffCollapseButton = true,
    manageTopCenterWidget = true,
    managePowerBarWidget = true,
    suppressSupertrackTutorial = true,
}

function Native:IsValidSocialFontSize(size)
    return type(size) == "number" and size >= 11 and size <= 18 and size == math.floor(size)
end

local function ApplyDefaults(config)
    if type(rawget(config, "manageBagsBar")) ~= "boolean" then
        config.manageBagsBar = COMMON_DEFAULTS.manageBagsBar
    end
    local mode = rawget(config, "bagsBarVisibility")
    if mode ~= "auto" and mode ~= "hide" and mode ~= "show" then
        config.bagsBarVisibility = config.hideBagsBar == false and "show" or "auto"
    end
    config.hideBagsBar = nil
    if YUI.IsForever == true then config.importBetaEditMode = nil end
    if YUI.IsForever == true and type(config.compactBetaReporter) ~= "boolean" then
        config.compactBetaReporter = true
    end
    if YUI.IsForever == true and type(config.fixBagSortButton) ~= "boolean" then
        config.fixBagSortButton = true
    end
    if YUI.IsForever == true and type(config.fixProfessionsIcon) ~= "boolean" then
        config.fixProfessionsIcon = true
    end
    if YUI.IsForever == true and type(config.questLootSparkles) ~= "boolean" then
        config.questLootSparkles = true
    end
    if YUI.IsForever == true and type(config.hideRaidManager) ~= "boolean" then
        config.hideRaidManager = false
    end
    if YUI.IsForever == true and type(config.manageErrorMessages) ~= "boolean" then
        config.manageErrorMessages = false
    end
    if YUI.IsForever == true then
        for key, value in pairs(FOREVER_WINDOW_DEFAULTS) do
            if key == "socialFontSize" then
                if not Native:IsValidSocialFontSize(config[key]) then config[key] = value end
            elseif type(rawget(config, key)) ~= "boolean" then config[key] = value end
        end
    end
    for key, value in pairs(COMMON_DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    if YUI.IsRetail == true then
        for key, value in pairs(RETAIL_DEFAULTS) do
            if config[key] == nil then config[key] = value end
        end
    end
    for key in pairs(COMMON_KEYS) do
        if type(config[key]) ~= "boolean" then config[key] = COMMON_DEFAULTS[key] end
    end
    if YUI.IsRetail == true then
        for key in pairs(RETAIL_KEYS) do
            if type(config[key]) ~= "boolean" then config[key] = RETAIL_DEFAULTS[key] end
        end
    end
    config._migrationVersion = Native.MIGRATION_VERSION
    return config
end

function Native:IsOptionSupported(key)
    if FOREVER_WINDOW_DEFAULTS[key] ~= nil then return YUI.IsForever == true end
    if key == "manageErrorMessages" then return YUI.IsForever == true end
    if key == "hideRaidManager" then return YUI.IsForever == true end
    if key == "compactBetaReporter" or key == "fixBagSortButton" or key == "fixProfessionsIcon" or key == "questLootSparkles" then return YUI.IsForever == true end
    if key == "bagsBarVisibility" or key == "hideBagsBar" then return true end
    return COMMON_KEYS[key] == true or (YUI.IsRetail == true and RETAIL_KEYS[key] == true)
end

function Native:GetOptionDefault(key)
    if YUI.IsForever == true and FOREVER_WINDOW_DEFAULTS[key] ~= nil then return FOREVER_WINDOW_DEFAULTS[key] end
    if key == "manageErrorMessages" and YUI.IsForever == true then return false end
    if key == "hideRaidManager" and YUI.IsForever == true then return false end
    if (key == "compactBetaReporter" or key == "fixBagSortButton" or key == "fixProfessionsIcon" or key == "questLootSparkles") and YUI.IsForever == true then return true end
    if COMMON_DEFAULTS[key] ~= nil then return COMMON_DEFAULTS[key] end
    if YUI.IsRetail == true then return RETAIL_DEFAULTS[key] end
    return nil
end

function Native:GetConfig()
    local profile = YUI.DB and YUI.DB.GetProfile and YUI.DB:GetProfile(self.PRODUCT_ID)
    if type(profile) ~= "table" then return ApplyDefaults({}) end
    if self.IS_SUITE and YUI.DB.NormalizeNativeInterfaceProfile then
        YUI.DB:NormalizeNativeInterfaceProfile(profile)
    end
    profile.Components = type(profile.Components) == "table" and profile.Components or {}
    local config = profile.Components[self.CONFIG_KEY]
    if type(config) ~= "table" then
        config = {}
        profile.Components[self.CONFIG_KEY] = config
    end
    return ApplyDefaults(config)
end

local skinKeys = { friends = "socialui", character = "charsheet", inspect = "inspect" }
local windowFrames = { friends = "SocialUIFrame", character = "CharacterFrame", inspect = "InspectFrame" }
local function ReadExternal(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then return nil end
    local security = YUI.API and YUI.API.Security
    if security and security.IsSecretValue and security.IsSecretValue(value) then return nil end
    return value
end

local function WindowSkinController(key)
    local ui = _G.EllesmereUI
    local modules = ui and ui._ModuleNS
    if not modules or _G.EUI_CLIENT_BLOCKED then return end
    local skin = modules.EllesmereUIBlizzardSkin
    if key == "friends" then
        local tile = ui.FriendsKit and ui.FriendsKit._tile
        local host = tile and ReadExternal(tile.Host)
        if host and host.fontKey == "friends" and modules.EllesmereUIFriends then
            local profile = ReadExternal(host.Settings)
            if profile and profile.enabled == true then return "EllesmereUI Friends" end
        end
        if not (skin and ui.IS_FOREVER == true) then return end
        -- The native card hooks survive a reload-pending style change. A
        -- stock-style host can also run just the independently toggled list.
        local decorated = host and host.fontKey == "blizzardSkin" and host.cards == true
        local list = ui.FriendsList
        local style = ReadExternal(ui.GetBlizzWindowStyle, "socialui")
        if decorated or style == "eui" or style == "modern" or style == "blizzard"
            or (style == "off" and ReadExternal(skin.FriendsCardGet, "customTiles") == true
                and list and ReadExternal(list.Available) == true) then
            return "EllesmereUI Blizzard Skins+"
        end
    elseif skin and ui.IS_FOREVER == true then
        local style = ReadExternal(ui.GetBlizzWindowStyle, skinKeys[key])
        if style ~= "modern" and style ~= "eui" and style ~= "blizzard" then return end
        -- Inspect uses its own enable key and the character sheet's latched
        -- look. Avoid calling CharSheetStyle before the provider latches it.
        local db = _G.EllesmereUIDB
        local looks = db and db.blizzWindowSkinStyles
        local sheetStyle = skin._csStyle or (looks and looks.charsheet)
        if not sheetStyle and key == "character" then sheetStyle = style end
        if sheetStyle == nil or sheetStyle == "eui" or sheetStyle == "modern" then return "EllesmereUI Blizzard Skins+" end
    end
end

local function ProfileSkinController(key)
    local engine = _G.ElvUI and _G.ElvUI[1]
    local skins = engine and engine.private and engine.private.skins
    local windows = skins and skins.blizzard
    if not windows or windows.enable ~= true or windows[key] ~= true or engine.Initialized ~= true
        or (key == "friends" and engine.Modern ~= true) then return end
    local module = ReadExternal(engine.GetModule, engine, "Skins", true)
    if module and module.Initialized == true then return "ElvUI" end
end

function Native:GetWindowEnhancementController(key)
    if not YUI.IsForever or not skinKeys[key] then return nil end
    if self.HasObservedWindowSkin and self:HasObservedWindowSkin(_G[windowFrames[key]]) then
        return "EllesmereUI Blizzard Skins+"
    end
    return ReadExternal(WindowSkinController, key) or ReadExternal(ProfileSkinController, key)
end

local lastFriends, lastCharacter, lastInspect
local function ApplyWindowOptions(native, config, forceFriends, forceCharacter)
    local friends = native:GetWindowEnhancementController("friends")
    local character = native:GetWindowEnhancementController("character")
    local inspect = native:GetWindowEnhancementController("inspect")
    local friendsChanged = friends ~= lastFriends
    local characterChanged = character ~= lastCharacter or inspect ~= lastInspect
    lastFriends, lastCharacter, lastInspect = friends, character, inspect
    if native.ApplySocialListCompact and (forceFriends or friendsChanged) then
        config = config or native:GetConfig()
        local enabled = native.runtimeEnabled and config.friendsEnhancementEnabled and not friends
        native:ApplySocialListCompact(enabled and config.socialListCompact, config.socialFontSize,
            enabled and config.currentGameFirst, friends ~= nil)
    end
    if native.ApplyCharacterBottomTabs and (forceCharacter or characterChanged) then
        config = config or native:GetConfig()
        native:ApplyCharacterBottomTabs(native.runtimeEnabled and config.characterEnhancementEnabled and config.characterBottomTabs)
    end
    if not friendsChanged and not characterChanged then return false end
    local settings = YUI.Settings
    if settings and settings.IsOpen and settings:IsOpen() and settings.GetSelectedModule and settings.RefreshSelectedModule then
        local selected = settings:GetSelectedModule()
        if selected and selected.id == "suite.settings.native_interface" then settings:RefreshSelectedModule() end
    end
    return true
end

function Native:RefreshWindowEnhancementControllers()
    if not self.runtimeEnabled then return false end
    return ApplyWindowOptions(self)
end

function Native:SetOption(key, enabled)
    if not self:IsOptionSupported(key) then return false, "unsupported-option" end
    if key == "hideBagsBar" then
        key, enabled = "bagsBarVisibility", enabled == true and "auto" or "show"
    end
    if key == "bagsBarVisibility" and enabled ~= "auto" and enabled ~= "hide" and enabled ~= "show" then
        return false, "invalid-option"
    end
    local config = self:GetConfig()
    local value = key == "bagsBarVisibility" and enabled or enabled == true
    if key == "socialFontSize" then
        if not self:IsValidSocialFontSize(enabled) then return false, "invalid-option" end
        value = enabled
    end
    if config[key] == value then return true, "unchanged" end
    config[key] = value
    if key == "friendsEnhancementEnabled" or key == "socialListCompact" or key == "socialFontSize" or key == "currentGameFirst" then
        ApplyWindowOptions(self, config, true, false)
        return true
    end
    if key == "characterEnhancementEnabled" or key == "characterBottomTabs" then
        ApplyWindowOptions(self, config, false, true)
        return true
    end
    if self.ResetOptionFailure then self:ResetOptionFailure(key) end
    return self:Refresh("option:" .. key)
end

function Native:GetLocaleText(key, fallback)
    local locale = YUI.Locale and YUI.Locale:Get("NativeInterface") or nil
    return locale and locale[key] or fallback or key
end

function Native:OpenSettings()
    local settings = YUI.Settings
    if not settings then return false end
    settings:Open({
        productId = self.PRODUCT_ID,
        scope = self.SETTINGS_SCOPE,
    })
    local module = settings.modulesById and settings.modulesById[self.SETTINGS_MODULE_ID]
    return module and settings:SelectModule(module) ~= false or false
end

function Native:Refresh(reason)
    if self.RefreshVisibility then self:RefreshVisibility(reason) end
    if self.RefreshBagSortFix then self:RefreshBagSortFix(reason) end
    if self.RefreshProfessionsIconFix then self:RefreshProfessionsIconFix(reason) end
    if self.RefreshRaidManager then self:RefreshRaidManager(reason) end
    if self.RefreshErrorMessages then self:RefreshErrorMessages(reason) end
    if self.RefreshQuestLootSparkles then self:RefreshQuestLootSparkles(reason) end
    if self.RefreshWindowMovement then self:RefreshWindowMovement(reason) end
    if self.ApplySocialListCompact or self.ApplyCharacterBottomTabs then
        ApplyWindowOptions(self, self:GetConfig(), true, true)
    end
    if YUI.IsRetail == true then
        if self.RefreshRetail then self:RefreshRetail(reason) end
        if self.RefreshTutorial then self:RefreshTutorial(reason) end
    end
    return true
end

function Native:GetDiagnostics()
    local result = {
        enabled = self.runtimeEnabled == true,
        client = YUI.IsForever and "forever" or (YUI.IsRetail == true and "mainline" or "wrath"),
    }
    if self.GetVisibilityDiagnostics then result.visibility = self:GetVisibilityDiagnostics() end
    if self.GetTooltipFadeDiagnostics then result.tooltipFade = self:GetTooltipFadeDiagnostics() end
    if self.GetBagSortFixDiagnostics then result.bagSortFix = self:GetBagSortFixDiagnostics() end
    if self.GetProfessionsIconFixDiagnostics then result.professionsIconFix = self:GetProfessionsIconFixDiagnostics() end
    if self.GetRaidManagerDiagnostics then result.raidManager = self:GetRaidManagerDiagnostics() end
    if self.GetErrorMessagesDiagnostics then result.errorMessages = self:GetErrorMessagesDiagnostics() end
    if self.GetQuestLootSparklesDiagnostics then result.questLootSparkles = self:GetQuestLootSparklesDiagnostics() end
    if self.GetWindowMovementDiagnostics then result.windows = self:GetWindowMovementDiagnostics() end
    if self.GetSocialListCompactDiagnostics then result.socialList = self:GetSocialListCompactDiagnostics() end
    if self.GetRetailDiagnostics then result.retail = self:GetRetailDiagnostics() end
    if self.GetTutorialDiagnostics then result.tutorial = self:GetTutorialDiagnostics() end
    return result
end
