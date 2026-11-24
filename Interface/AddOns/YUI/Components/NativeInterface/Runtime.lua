local _, addonTable = ...
local YUI = _G.YUI or addonTable
local Native = YUI and YUI.NativeInterface
if not Native then return end

local externalOwner = {}
local betaLoginOwner = {}
local betaLoginHandled = false
local betaLoginTimer

local function ApplyBetaReporter()
    betaLoginTimer = nil
    if not Native.runtimeEnabled or not Native:GetConfig().compactBetaReporter then return end
    local frame = _G.PTR_IssueReporter
    if not (frame and frame.Body and frame.SetScale and frame.ClearAllPoints and frame.SetPoint) then return end
    if frame.IsProtected and frame:IsProtected() then return end
    frame:SetScale(0.7)
    frame:ClearAllPoints()
    frame:SetPoint("LEFT", UIParent, "LEFT", 20, -100)
end

local function OnBetaLogin()
    if betaLoginHandled then return end
    betaLoginHandled = true
    YUI.Event:OffOwner(betaLoginOwner)
    -- Run after Blizzard's PLAYER_ENTERING_WORLD initialization, regardless of event order.
    if C_Timer and C_Timer.NewTimer then
        betaLoginTimer = C_Timer.NewTimer(0, ApplyBetaReporter)
    end
end

local function NormalizeTransferPayload(payload, path, fields, layouts)
    if type(payload) ~= "table" or type(payload.data) ~= "table"
        or type(payload.present) ~= "table" or type(payload.layouts) ~= "table"
        or type(payload.layoutPresent) ~= "table" then
        return nil, "invalid_module_payload"
    end
    if type(payload.present[path]) ~= "boolean" then return nil, "unexpected_data_path" end
    for key, present in pairs(payload.present) do
        if key ~= path or type(present) ~= "boolean" then return nil, "unexpected_data_path" end
    end
    for key in pairs(payload.data) do
        if key ~= path or payload.present[path] ~= true then return nil, "unexpected_data_path" end
    end
    if payload.present[path] == true then
        local config = payload.data[path]
        if type(config) ~= "table" then return nil, "invalid_module_payload" end
        if config.hideBagsBar ~= nil then
            if type(config.hideBagsBar) ~= "boolean" then return nil, "invalid_data_field" end
            if config.bagsBarVisibility == nil then
                config.bagsBarVisibility = config.hideBagsBar and "auto" or "show"
            end
            config.hideBagsBar = nil
        end
        -- Accept the retired tooltip field without restoring its former ownership.
        if config.tooltipInstantHide ~= nil then
            if type(config.tooltipInstantHide) ~= "boolean" then return nil, "invalid_data_field" end
            config.tooltipInstantHide = nil
        end
        -- Accept older exports without reviving retired login workarounds.
        if YUI.IsForever == true then
            config.importBetaProfile = nil
            config.restoreDialogueProfile = nil
            config.importBetaEditMode = nil
        end
        for key, value in pairs(config) do
            if fields[key] ~= true then return nil, "unexpected_data_field" end
            if key == "windowMovement" and Native.NormalizeWindowMovement then
                local normalized = Native:NormalizeWindowMovement(value, true)
                if not normalized then return nil, "invalid_data_field" end
                config[key] = normalized
            elseif key == "bagsBarVisibility" then
                if value ~= "auto" and value ~= "hide" and value ~= "show" then return nil, "invalid_data_field" end
            elseif key == "socialFontSize" then
                if not Native:IsValidSocialFontSize(value) then return nil, "invalid_data_field" end
            elseif type(value) ~= "boolean" then return nil, "invalid_data_field" end
        end
        local currentConfig
        for key in pairs(fields) do
            if config[key] == nil then
                if key == "windowMovement" then config[key] = Native:NormalizeWindowMovement(nil)
                elseif key == "friendsEnhancementEnabled" or key == "socialListCompact" or key == "currentGameFirst"
                    or key == "socialFontSize" or key == "characterEnhancementEnabled" or key == "characterBottomTabs" then
                    currentConfig = currentConfig or Native:GetConfig()
                    config[key] = currentConfig[key]
                else config[key] = Native:GetOptionDefault(key) end
            end
        end
    elseif payload.data[path] ~= nil then
        return nil, "unexpected_data_path"
    end

    local layoutSet = {}
    for _, layoutId in ipairs(layouts) do
        layoutSet[layoutId] = true
        if YUI.IsForever == true and layoutId == Native.ERROR_MESSAGES_LAYOUT_ID
            and payload.layoutPresent[layoutId] == nil then
            payload.layoutPresent[layoutId] = false
        end
        if type(payload.layoutPresent[layoutId]) ~= "boolean" then return nil, "unexpected_layout" end
    end
    for layoutId, present in pairs(payload.layoutPresent) do
        if layoutSet[layoutId] ~= true or type(present) ~= "boolean" then return nil, "unexpected_layout" end
    end
    for layoutId in pairs(payload.layouts) do
        if layoutSet[layoutId] ~= true or payload.layoutPresent[layoutId] ~= true then
            return nil, "unexpected_layout"
        end
    end
    if payload.configSets ~= nil then return nil, "unexpected_config_sets" end
    return payload
end

local function OnExternalStateChanged()
    if Native.runtimeEnabled and Native.RefreshRetail then
        Native:RefreshRetail("external-state")
    end
end

local observedSkinMethods = setmetatable({}, { __mode = "k" })
local appliedShells = setmetatable({}, { __mode = "k" })
function Native:HasObservedWindowSkin(frame)
    return frame ~= nil and appliedShells[frame] == true
end

local function OnWindowStyleChanged()
    if Native.runtimeEnabled then Native:RefreshWindowEnhancementControllers() end
end

-- Shell installation strips the original art until reload. A later change
-- to the saved style does not release an already adopted window.
local function OnShellAdopted(key, frame)
    if not frame or appliedShells[frame] then return end
    if (key == "socialui" and frame == _G.SocialUIFrame)
        or (key == "charsheet" and (frame == _G.CharacterFrame or frame == _G.InspectFrame)) then
        appliedShells[frame] = true
        OnWindowStyleChanged()
    end
end

local function ObserveSkinMethod(object, method, callback)
    if type(object) ~= "table" or type(hooksecurefunc) ~= "function" or type(object[method]) ~= "function" then return end
    local installed = observedSkinMethods[object]
    if installed and installed[method] then return end
    if pcall(hooksecurefunc, object, method, callback or OnWindowStyleChanged) then
        installed = installed or {}
        installed[method] = true
        observedSkinMethods[object] = installed
    end
end

local function WatchWindowSkins()
    local ui = _G.EllesmereUI
    local modules = ui and ui._ModuleNS
    local skin = modules and modules.EllesmereUIBlizzardSkin
    if skin then
        ObserveSkinMethod(skin.WSkin, "AdoptShell", OnShellAdopted)
        ObserveSkinMethod(ui, "_WSkinRefreshStyles")
        ObserveSkinMethod(skin, "FriendsCardSet")
        ObserveSkinMethod(skin, "FriendsCardRefresh")
    end
end

local windowAddons = {
    EllesmereUIBlizzardSkin = true, EllesmereUIFriends = true, ElvUI = true,
    Blizzard_SocialUI = true, Blizzard_InspectUI = true, Blizzard_UIPanels_Game = true,
}
local function OnWindowAddon(_, name)
    if not windowAddons[name] then return end
    pcall(WatchWindowSkins)
    OnWindowStyleChanged()
end

local definition = {
    id = Native.MODULE_ID,
    name = "NativeInterface",
    product = Native.PRODUCT_ID,
    scope = Native.SETTINGS_SCOPE,
    owner = Native,
    getEnabled = function()
        return Native.PRODUCT_ID == "suite"
            or (Native.PRODUCT_ID == "ybar" and YUI.IsRetail == true)
    end,
    OnInitialize = function(self)
        self:GetConfig()
        return true
    end,
    OnEnable = function(self)
        self.runtimeEnabled = true
        if YUI.IsForever == true and not betaLoginHandled and YUI.Event and YUI.Event.On then
            YUI.Event:On("PLAYER_ENTERING_WORLD", OnBetaLogin, betaLoginOwner, {
                moduleId = self.MODULE_ID,
                traceName = "NativeInterface:beta-login",
            })
        end
        if YUI.Event and YUI.Event.On and YUI.IsRetail == true then
            YUI.Event:On("YUI_EXTERNAL_STATE_CHANGED", OnExternalStateChanged, externalOwner, {
                moduleId = self.MODULE_ID,
                traceName = "NativeInterface:external-state",
            })
        end
        if YUI.IsForever and (self.ApplySocialListCompact or self.ApplyCharacterBottomTabs)
            and YUI.Event and YUI.Event.On then
            pcall(WatchWindowSkins)
            local options = { moduleId = self.MODULE_ID, traceName = "NativeInterface:window-skins" }
            YUI.Event:On("ADDON_LOADED", OnWindowAddon, externalOwner, options)
            YUI.Event:On("PLAYER_ENTERING_WORLD", OnWindowStyleChanged, externalOwner, options)
        end
        return self:Refresh("enable")
    end,
    OnDisable = function(self)
        self.runtimeEnabled = false
        if YUI.IsForever == true and YUI.Event and YUI.Event.OffOwner then YUI.Event:OffOwner(betaLoginOwner) end
        if betaLoginTimer then betaLoginTimer:Cancel(); betaLoginTimer = nil end
        if YUI.Event and YUI.Event.OffOwner then YUI.Event:OffOwner(externalOwner) end
        if self.ReleaseVisibility then self:ReleaseVisibility() end
        if self.ReleaseBagSortFix then self:ReleaseBagSortFix() end
        if self.ReleaseProfessionsIconFix then self:ReleaseProfessionsIconFix() end
        if self.ReleaseRaidManager then self:ReleaseRaidManager() end
        if self.ReleaseErrorMessages then self:ReleaseErrorMessages() end
        if self.ReleaseQuestLootSparkles then self:ReleaseQuestLootSparkles() end
        if self.RefreshWindowMovement then self:RefreshWindowMovement("disable") end
        if self.ApplySocialListCompact then self:ApplySocialListCompact(false, nil, false, true) end
        if self.ApplyCharacterBottomTabs then self:ApplyCharacterBottomTabs(false) end
        if self.RefreshRetail then self:RefreshRetail("disable") end
        if self.ReleaseTutorial then self:ReleaseTutorial() end
        return true
    end,
    OnProfileChanged = function(self)
        self:GetConfig()
        if self.ResetAllFailures then self:ResetAllFailures() end
        return self:Refresh("profile-changed")
    end,
}

if YUI.Module and YUI.Module.Register then YUI.Module:Register(definition) end

local transfer = YUI.Settings and YUI.Settings.ConfigTransfer
if transfer and transfer.RegisterModule then
    local path = "Components.NativeInterface_Config"
    local fields = {
        hideStatusTrackingBars = true,
        hideMicroMenu = true,
        bagsBarVisibility = true,
        manageBagsBar = true,
    }
    local layouts = {}
    if YUI.IsForever == true then
        fields.compactBetaReporter = true
        fields.fixBagSortButton = true
        fields.fixProfessionsIcon = true
        fields.questLootSparkles = true
        fields.hideRaidManager = true
        fields.manageErrorMessages = true
        fields.friendsEnhancementEnabled = true
        fields.socialListCompact = true
        fields.currentGameFirst = true
        fields.socialFontSize = true
        fields.characterEnhancementEnabled = true
        fields.characterBottomTabs = true
        layouts = { Native.ERROR_MESSAGES_LAYOUT_ID }
        if Native.NormalizeWindowMovement then fields.windowMovement = true end
    end
    if YUI.IsRetail == true then
        fields.hideBuffCollapseButton = true
        fields.manageTopCenterWidget = true
        fields.managePowerBarWidget = true
        fields.suppressSupertrackTutorial = true
        layouts = {
            "yui.component.utilityTools.topCenterWidget",
            "yui.component.utilityTools.powerBarWidget",
        }
    end
    transfer:RegisterModule({
        id = Native.TRANSFER_ID,
        kind = "core",
        label = Native:GetLocaleText("name", "暴雪界面"),
        schemaVersion = 1,
        clients = { retail = YUI.IsRetail == true, mists = false, wrath = YUI.IsWrath == true, forever = YUI.IsForever == true },
        productId = Native.PRODUCT_ID,
        dataPaths = { path },
        fieldWhitelists = { [path] = fields },
        layoutIds = layouts,
        normalize = function(payload)
            return NormalizeTransferPayload(payload, path, fields, layouts)
        end,
        refresh = function()
            Native:GetConfig()
            return Native:Refresh("config-transfer")
        end,
    })
end
