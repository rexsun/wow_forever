local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not (YUI and YUI.Components) or YUI.IsMists then return end

local Components = YUI.Components
local ChatInput = YUI.API and YUI.API.ChatInput
local Social = YUI.API and YUI.API.Social
local System = YUI.API and YUI.API.System or YUI.WOW_API
local L = YUI.Locale and YUI.Locale:Get("SocialEnhancement") or {}

local FEATURE_KEY = "SocialEnhancement"
local CONFIG_KEY = "SocialEnhancement_Config"
local TAB_OWNER_ID = "social_enhancement"
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or (_G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME]
        and _G.YUI_CORE_EMBED_STATE[ADDON_NAME].productId)
    or YUI.ProductId or "suite"

local DEFAULTS = { schema = 1, tabCycle = true, rightClick = false }
local LEGACY_TRANSFER_PATHS = {
    ["component.right_plus"] = "RightPlus_Config",
    ["component.tab_chat"] = "TabChat_Config",
}
local featureEnabled = false
local mainlineMenusRegistered = false
local legacyInitialized = false
local legacyFrame
local legacyPreviousOnUpdate
local legacyOnUpdateWrapper
local settingsOwner = {}
local Feature = {}

local function T(key, fallback)
    return type(L) == "table" and L[key] or fallback or key
end

local function Migrate(store)
    if type(store) ~= "table" then return end
    local config = store[CONFIG_KEY]
    if type(config) == "table" and config.schema == 1 then
        config.tabCycle = config.tabCycle == true
        config.rightClick = config.rightClick == true
        return
    end

    local hasTab = store.TabChat ~= nil
    local hasRight = store.RightPlus ~= nil
    local tabCycle = DEFAULTS.tabCycle
    if hasTab then tabCycle = store.TabChat == true end
    local rightClick = DEFAULTS.rightClick
    if hasRight then rightClick = store.RightPlus == true end
    store[CONFIG_KEY] = {
        schema = 1,
        tabCycle = tabCycle,
        rightClick = rightClick,
    }
    if store[FEATURE_KEY] == nil then
        store[FEATURE_KEY] = (hasTab or hasRight) and (tabCycle or rightClick) or true
    end
end

local function ReadLegacyTransferEnabled(source, expectedPath)
    if type(source) ~= "table" or source.schemaVersion ~= 1 then return nil end
    local payload = source.payload
    if type(payload) ~= "table" or type(payload.enabled) ~= "boolean"
        or type(payload.data) ~= "table" or type(payload.present) ~= "table"
        or type(payload.layouts) ~= "table" or next(payload.layouts) ~= nil
        or type(payload.layoutPresent) ~= "table" or next(payload.layoutPresent) ~= nil then
        return nil
    end
    for key in pairs(payload) do
        if key ~= "enabled" and key ~= "data" and key ~= "present"
            and key ~= "layouts" and key ~= "layoutPresent" then
            return nil
        end
    end
    if type(payload.present[expectedPath]) ~= "boolean" then return nil end
    for path, present in pairs(payload.present) do
        if path ~= expectedPath or type(present) ~= "boolean" then return nil end
    end
    for path in pairs(payload.data) do
        if path ~= expectedPath or payload.present[path] ~= true then return nil end
    end
    return payload.enabled
end

local function MergeLegacyTransferModules(aliases)
    if type(aliases) ~= "table" then return nil end
    local tabCycle = DEFAULTS.tabCycle
    local rightClick = DEFAULTS.rightClick
    for aliasId, source in pairs(aliases) do
        local expectedPath = LEGACY_TRANSFER_PATHS[aliasId]
        local enabled = expectedPath and ReadLegacyTransferEnabled(source, expectedPath)
        if enabled == nil then return nil end
        if aliasId == "component.tab_chat" then
            tabCycle = enabled
        elseif aliasId == "component.right_plus" then
            rightClick = enabled
        else
            return nil
        end
    end
    return {
        data = {
            [CONFIG_KEY] = {
                schema = 1,
                tabCycle = tabCycle,
                rightClick = rightClick,
            },
        },
        present = { [CONFIG_KEY] = true },
        layouts = {},
        layoutPresent = {},
        enabled = tabCycle or rightClick,
    }
end

local function GetDB()
    local store = Components:GetStore(PRODUCT_ID)
    if store then Migrate(store) end
    local db = Components:EnsureConfig(CONFIG_KEY, DEFAULTS, PRODUCT_ID)
    if not db then return DEFAULTS end
    db.schema = 1
    db.tabCycle = db.tabCycle == true
    db.rightClick = db.rightClick == true
    return db
end

local function IsAddOnLoaded(name)
    if not (System and type(System.IsAddOnLoaded) == "function") then return false end
    local ok, loaded = pcall(System.IsAddOnLoaded, name)
    return ok and loaded == true
end

local function HasMainlineMenuConflict()
    return (YUI.IsRetail == true or YUI.IsForever == true) and (
        IsAddOnLoaded("NDUI") or IsAddOnLoaded("NDui")
        or IsAddOnLoaded("ElvUI_WindTools")
    )
end

local function GetFullTargetName(name, server)
    if type(name) ~= "string" or name == "" then return nil end
    if type(server) == "string" and server ~= "" then
        local realm = type(_G.GetRealmName) == "function" and _G.GetRealmName() or nil
        if server ~= realm then return name .. "-" .. server end
    end
    return name
end

local function AddFriend(name)
    if Social and type(Social.AddFriend) == "function" then Social.AddFriend(name) end
end

local function InviteToGuild(name)
    if Social and type(Social.InviteToGuild) == "function" then Social.InviteToGuild(name) end
end

local function IsRightClickActive()
    return featureEnabled and GetDB().rightClick and not HasMainlineMenuConflict()
end

local function AddMenuActions(rootDescription, contextData)
    if not IsRightClickActive() or not rootDescription or type(contextData) ~= "table" then return end
    local name = GetFullTargetName(contextData.name, contextData.server)
    if YUI.IsForever then
        -- The native resolver distinguishes surname from realm using menu context.
        name = Social and Social.GetForeverMenuPlayerName and Social.GetForeverMenuPlayerName(contextData)
    end
    if not name then return end
    if type(rootDescription.CreateDivider) == "function" then rootDescription:CreateDivider() end
    if type(rootDescription.CreateButton) == "function" then
        rootDescription:CreateButton(T("menu.add_friend", "Add Friend"), function() AddFriend(name) end)
        rootDescription:CreateButton(T("menu.invite_guild", "Invite to Guild"), function() InviteToGuild(name) end)
    end
end

local function EnsureMainlineMenus()
    if mainlineMenusRegistered then return true end
    local Menu = _G.Menu
    if not (Menu and type(Menu.ModifyMenu) == "function") then return false end
    local menuTypes = {
        "MENU_UNIT_FRIEND", "MENU_UNIT_PLAYER", "MENU_UNIT_RAID_PLAYER",
        "MENU_UNIT_PARTY", "MENU_UNIT_TARGET", "MENU_UNIT_SELF",
    }
    for _, menuType in ipairs(menuTypes) do
        Menu.ModifyMenu(menuType, function(_, rootDescription, contextData)
            if not IsRightClickActive() or not contextData then return end
            if contextData.unit and type(_G.UnitIsPlayer) == "function"
                and not _G.UnitIsPlayer(contextData.unit)
            then
                return
            end
            AddMenuActions(rootDescription, contextData)
        end)
    end
    mainlineMenusRegistered = true
    return true
end

local function RestoreLegacyOnUpdate()
    local dropdown = _G.DropDownList1
    if dropdown and legacyOnUpdateWrapper
        and dropdown:GetScript("OnUpdate") == legacyOnUpdateWrapper
    then
        dropdown:SetScript("OnUpdate", legacyPreviousOnUpdate)
    end
    legacyPreviousOnUpdate = nil
    legacyOnUpdateWrapper = nil
end

local function InstallLegacyOnUpdate()
    local dropdown = _G.DropDownList1
    if not dropdown or legacyOnUpdateWrapper then return false end
    legacyPreviousOnUpdate = dropdown:GetScript("OnUpdate")
    local previous = legacyPreviousOnUpdate
    legacyOnUpdateWrapper = function(self, elapsed)
        if self.YUISocialEnhancementHover then return end
        if type(previous) == "function" then return previous(self, elapsed) end
    end
    dropdown:SetScript("OnUpdate", legacyOnUpdateWrapper)
    return true
end

local function EnsureLegacyMenu()
    if legacyInitialized then return true end
    local dropdown = _G.DropDownList1
    if not (dropdown and type(_G.CreateFrame) == "function") then return false end

    local frame = _G.CreateFrame("Frame", nil, _G.UIParent)
    frame:SetPoint("TOPLEFT", dropdown, "TOPRIGHT", 0, -10)
    frame:SetSize(118, 52)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:Hide()
    legacyFrame = frame

    local actions = {
        { label = T("menu.add_friend", "Add Friend"), callback = AddFriend },
        { label = T("menu.invite_guild", "Invite to Guild"), callback = InviteToGuild },
    }
    frame.buttons = {}
    for index, action in ipairs(actions) do
        local actionRef = action
        local button = _G.CreateFrame("Button", nil, frame, "UIDropDownMenuButtonTemplate")
        button:SetSize(110, 18)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -8 - ((index - 1) * 18))
        button:SetText(actionRef.label)
        button:SetScript("OnClick", function()
            if not IsRightClickActive() then return end
            local menu = _G.UIDROPDOWNMENU_INIT_MENU
            local name = menu and GetFullTargetName(menu.name, menu.server)
            if name then actionRef.callback(name) end
            frame:Hide()
            if type(_G.CloseDropDownMenus) == "function" then _G.CloseDropDownMenus() end
        end)
        button:SetScript("OnEnter", function(self)
            if self.Highlight then self.Highlight:Show() end
            dropdown.YUISocialEnhancementHover = true
        end)
        button:SetScript("OnLeave", function(self)
            if self.Highlight then self.Highlight:Hide() end
            dropdown.YUISocialEnhancementHover = nil
        end)
        frame.buttons[index] = button
    end

    if type(_G.hooksecurefunc) == "function" and type(_G.UnitPopup_ShowMenu) == "function" then
        _G.hooksecurefunc("UnitPopup_ShowMenu", function(dropdownMenu, which, unit)
            frame:Hide()
            if not IsRightClickActive() or (_G.UIDROPDOWNMENU_MENU_LEVEL or 1) > 1 then return end
            local menuName = dropdownMenu and dropdownMenu.GetName and dropdownMenu:GetName()
            local show = (menuName == "FriendsDropDown"
                    and (which == "FRIEND" or which == "CHAT_ROSTER" or which == "RAID"))
                or which == "CHAT_ROSTER" or which == "PLAYER" or which == "PARTY"
                or which == "RAID_PLAYER"
                or ((menuName == "TargetFrameDropDown" or which == "TARGET")
                    and type(_G.UnitIsPlayer) == "function" and _G.UnitIsPlayer(unit))
            if show then frame:Show() end
        end)
    end
    dropdown:HookScript("OnHide", function()
        frame:Hide()
        dropdown.YUISocialEnhancementHover = nil
    end)
    frame:HookScript("OnEnter", function() dropdown.YUISocialEnhancementHover = true end)
    frame:HookScript("OnLeave", function() dropdown.YUISocialEnhancementHover = nil end)
    legacyInitialized = true
    return true
end

local function RefreshRightClick()
    if YUI.IsRetail or YUI.IsForever then
        if featureEnabled and GetDB().rightClick then EnsureMainlineMenus() end
        return
    end
    if not YUI.IsWrath then return end
    if featureEnabled and GetDB().rightClick and EnsureLegacyMenu() then
        InstallLegacyOnUpdate()
    else
        if legacyFrame then legacyFrame:Hide() end
        if _G.DropDownList1 then _G.DropDownList1.YUISocialEnhancementHover = nil end
        RestoreLegacyOnUpdate()
    end
end

local function RefreshTabOwner()
    if not YUI.IsRetail or not ChatInput then return end
    if not featureEnabled then
        ChatInput.UnregisterTabOwner(TAB_OWNER_ID)
        return
    end
    ChatInput.RegisterTabOwner(TAB_OWNER_ID, 100)
    local enabled = GetDB().tabCycle == true
    ChatInput.SetTabOwnerState(TAB_OWNER_ID, { claimed = enabled, enabled = enabled })
end

local function RefreshSettings()
    if Feature.RefreshCurrentModule then Feature:RefreshCurrentModule() end
end

local function IsYChatOwner()
    return ChatInput and ChatInput.GetTabOwner and ChatInput.GetTabOwner() == "ychat"
end

local function GetOptions()
    local options = {}
    if YUI.IsRetail then
        options[#options + 1] = {
            type = "checkbox",
            text = T("settings.tab_cycle", "Use Tab / Shift+Tab to cycle chat targets"),
            tooltip = T("settings.tab_cycle.tooltip", "Cycles through supported group, guild, and world chat targets without changing the input text."),
            width = 520,
            hidden = IsYChatOwner,
            get = function() return GetDB().tabCycle == true end,
            set = function(value)
                GetDB().tabCycle = value == true
                RefreshTabOwner()
                RefreshSettings()
            end,
        }
        options[#options + 1] = {
            type = "text",
            label = T("settings.tab_cycle.ychat", "Tab target switching is managed by YChat."),
            colorKey = "color.state.warning",
            width = 520,
            hidden = function() return not IsYChatOwner() end,
        }
    end
    options[#options + 1] = {
        type = "checkbox",
        text = T("settings.right_click", "Enhance player right-click menus"),
        tooltip = T("settings.right_click.tooltip", "Adds friend and guild-invite actions to supported player menus."),
        width = 520,
        hidden = HasMainlineMenuConflict,
        get = function() return GetDB().rightClick == true end,
        set = function(value)
            GetDB().rightClick = value == true
            RefreshRightClick()
            RefreshSettings()
        end,
    }
    if YUI.IsRetail or YUI.IsForever then
        options[#options + 1] = {
            type = "text",
            label = T("settings.right_click.conflict", "Unavailable because another interface addon manages these menus."),
            colorKey = "color.state.warning",
            width = 520,
            hidden = function() return not HasMainlineMenuConflict() end,
        }
    end
    return options
end

local function SetEnabled(enabled)
    featureEnabled = enabled == true
    GetDB()
    RefreshTabOwner()
    RefreshRightClick()
end

Feature.name = T("feature.name", "Social Enhancement")
Feature.description = YUI.IsForever and T("settings.right_click.tooltip", "Adds friend and guild-invite actions to supported player menus.")
    or T("feature.description", "Tab target switching and optional player-menu social actions.")
Feature.default = true
Feature.product = PRODUCT_ID
Feature.settingsMode = "inline"
Feature.migrate = Migrate
Feature.callback = SetEnabled
Feature.GetOptions = GetOptions
Feature.transfer = {
    dataPaths = { CONFIG_KEY },
    fieldWhitelists = {
        [CONFIG_KEY] = {
            schema = true,
            tabCycle = true,
            rightClick = true,
        },
    },
    importAliases = {
        "component.right_plus",
        "component.tab_chat",
    },
    mergeImportAliases = MergeLegacyTransferModules,
}

Components:RegisterFeature(FEATURE_KEY, Feature)

if YUI.Event and YUI.Event.On then
    YUI.Event:On("YUI_CHAT_TAB_OWNER_CHANGED", RefreshSettings, settingsOwner, {
        moduleId = "component:" .. FEATURE_KEY,
        traceName = "SocialEnhancement:tab-owner-changed",
    })
end
