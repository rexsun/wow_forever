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
Native.MIGRATION_VERSION = 2
Native.runtimeEnabled = false

local COMMON_DEFAULTS = {
    hideStatusTrackingBars = false,
    hideMicroMenu = false,
    bagsBarVisibility = "auto",
    _migrationVersion = 2,
}

local RETAIL_DEFAULTS = {
    hideBuffCollapseButton = false,
    manageTopCenterWidget = false,
    managePowerBarWidget = false,
    suppressSupertrackTutorial = true,
}

local COMMON_KEYS = {
    hideStatusTrackingBars = true,
    hideMicroMenu = true,
}

local RETAIL_KEYS = {
    hideBuffCollapseButton = true,
    manageTopCenterWidget = true,
    managePowerBarWidget = true,
    suppressSupertrackTutorial = true,
}

local function ApplyDefaults(config)
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
    if key == "hideRaidManager" then return YUI.IsForever == true end
    if key == "compactBetaReporter" or key == "fixBagSortButton" or key == "fixProfessionsIcon" or key == "questLootSparkles" then return YUI.IsForever == true end
    if key == "bagsBarVisibility" or key == "hideBagsBar" then return true end
    return COMMON_KEYS[key] == true or (YUI.IsRetail == true and RETAIL_KEYS[key] == true)
end

function Native:GetOptionDefault(key)
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
    if config[key] == value then return true, "unchanged" end
    config[key] = value
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
    if self.RefreshQuestLootSparkles then self:RefreshQuestLootSparkles(reason) end
    if self.RefreshWindowMovement then self:RefreshWindowMovement(reason) end
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
    if self.GetQuestLootSparklesDiagnostics then result.questLootSparkles = self:GetQuestLootSparklesDiagnostics() end
    if self.GetWindowMovementDiagnostics then result.windows = self:GetWindowMovementDiagnostics() end
    if self.GetRetailDiagnostics then result.retail = self:GetRetailDiagnostics() end
    if self.GetTutorialDiagnostics then result.tutorial = self:GetTutorialDiagnostics() end
    return result
end
