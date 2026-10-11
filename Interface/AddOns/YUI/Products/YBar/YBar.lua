local ADDON_NAME = ...
local YUI = _G.YUI
local YBar = {}
local API = YUI.WOW_API
local SystemAPI = YUI.API and YUI.API.System or API
local SecurityAPI = YUI.API and YUI.API.Security or API
local UnitAPI = YUI.API and YUI.API.Unit or API
local GUI2 = YUI.GUI2
local YBarLocale = YUI.Locale and YUI.Locale:Get("YBar") or {}
YUI.YBar = YBar
if YUI.Assets and YUI.Assets.RegisterProductRoot then
    YUI.Assets:RegisterProductRoot("ybar", "Interface\\AddOns\\" .. (ADDON_NAME or YUI.AddonName or "YUI") .. "\\Products\\YBar\\Media")
end
if YUI.RegisterProduct then
    YUI:RegisterProduct({
        id = "ybar",
        title = "Orbit InfoBar · YanForge",
        titleKey = "product.title",
        titleNamespace = "YBar",
        localizedTitles = {
            zhCN = "Orbit 信息条 · 言工坊",
            zhTW = "Orbit 資訊條 · 言工坊",
        },
        shortTitle = "Orbit InfoBar",
        shortTitleKey = "product.short_title",
        shortTitleNamespace = "YBar",
        localizedShortTitles = {
            zhCN = "Orbit 信息条",
            zhTW = "Orbit 資訊條",
        },
        logo = "icons\\logo_32.png",
        smallLogo = "icons\\logo_32.png",
        logoCrop = false,
        notes = "Orbit InfoBar · YanForge",
        notesKey = "product.notes",
        notesNamespace = "YBar",
        localizedNotes = {
            zhCN = "Orbit 信息条 · 言工坊",
            zhTW = "Orbit 資訊條 · 言工坊",
        },
        author = "阿言",
        addonName = ADDON_NAME or YUI.AddonName,
        profileExportPrefix = YUI.CoreMode == "suite" and "!YUI-YBar-v2:" or "!OrbitInfoBar-v2:",
        settingsScope = "ybar",
        settings = {
            enabled = true,
            entry = "ybar.settings",
            commonPages = { "core.profiles", "core.about" },
            minimapIcon = true,
        },
        db = {
            enabled = true,
            savedVariable = YUI.CoreMode == "suite" and "YUI_DB" or "YUI_OrbitInfoBar_DB",
            storageKey = "YBar",
        },
        commands = {
            { alias = "/ybar", action = "openSettings", entry = "ybar.settings" },
        },
    })
end
local LSM = LibStub("LibSharedMedia-3.0")
local YBAR_TEXT_FALLBACK = { 1, 1, 1, 1 }
local YBAR_ACCENT_FALLBACK = { 1, 0.82, 0, 1 }
local YBAR_NATIVE_ICON_TEXCOORDS = { 0.08, 0.92, 0.08, 0.92 }
local PREMADE_GROUP_BOARD_ADDON = "PremadeGroupBoard"
local PREMADE_GROUP_BOARD_SLASH_COMMANDS = { "/pgb", "/premadegroupboard" }
local MEETING_HORN_ADDONS = { "MeetingStone", "MeetingHorn", "MeetingHornHeroic" }
local MEETING_HORN_SLASH_COMMANDS = { "/ms", "/meetingstone", "/mhh", "/mh", "/meetinghornheroic" }

local function GetMeetingHornAddon()
    if not LibStub then return nil end

    local ok, AceAddon = pcall(LibStub, "AceAddon-3.0", true)
    if not ok or not AceAddon or type(AceAddon.GetAddon) ~= "function" then
        return nil
    end

    for _, addonName in ipairs(MEETING_HORN_ADDONS) do
        local addonOk, addon = pcall(AceAddon.GetAddon, AceAddon, addonName, true)
        if addonOk and addon then
            return addon
        end
    end

    return nil
end

local function GetMeetingHornAddonIndex(addonName)
    if type(addonName) ~= "string" then return nil end

    if C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetAddOnInfo then
        local countOk, count = pcall(C_AddOns.GetNumAddOns)
        if countOk and type(count) == "number" then
            for index = 1, count do
                local infoOk, name = pcall(C_AddOns.GetAddOnInfo, index)
                if infoOk and name == addonName then
                    return index
                end
            end
        end
    end

    if GetNumAddOns and GetAddOnInfo then
        local count = GetNumAddOns()
        if type(count) == "number" then
            for index = 1, count do
                local infoOk, name = pcall(GetAddOnInfo, index)
                if infoOk and name == addonName then
                    return index
                end
            end
        end
    end

    return nil
end

local function IsMeetingHornAddonEnabled(addonName)
    local addonIndex = GetMeetingHornAddonIndex(addonName)
    if not addonIndex then return false end

    if C_AddOns and C_AddOns.GetAddOnEnableState then
        local character = UnitGUID and UnitGUID("player") or nil
        local stateOk, state = pcall(C_AddOns.GetAddOnEnableState, addonIndex, character)
        if stateOk and state ~= nil then
            local disabledState = Enum and Enum.AddOnEnableState and Enum.AddOnEnableState.None or 0
            return state > disabledState
        end
    end

    if GetAddOnInfo then
        local infoOk, _, _, _, enabled, loadable = pcall(GetAddOnInfo, addonIndex)
        if infoOk then
            return enabled and loadable ~= false
        end
    end

    return true
end

local function HasMeetingHornAddonEnabled()
    for _, addonName in ipairs(MEETING_HORN_ADDONS) do
        if IsMeetingHornAddonEnabled(addonName) then
            return true
        end
    end

    return false
end

local function RunRegisteredSlashCommand(cmd)
    if type(cmd) ~= "string" or not SlashCmdList then return false end

    local slash, args = cmd:match("^(%S+)%s*(.*)$")
    if not slash then return false end

    local target = slash:upper()
    args = args or ""

    for name, func in pairs(SlashCmdList) do
        if type(func) == "function" then
            local i = 1
            while true do
                local candidate = _G["SLASH_" .. name .. i]
                if not candidate then break end
                if type(candidate) == "string" and candidate:upper() == target then
                    local ok = pcall(func, args)
                    return ok
                end
                i = i + 1
            end
        end
    end

    return false
end

local function EnsurePremadeGroupBoardLoaded()
    if SystemAPI and type(SystemAPI.IsAddOnLoadedSafe) == "function" and SystemAPI.IsAddOnLoadedSafe(PREMADE_GROUP_BOARD_ADDON) then
        return true
    end

    if SystemAPI and type(SystemAPI.LoadAddOn) == "function" then
        local ok, loaded = pcall(SystemAPI.LoadAddOn, PREMADE_GROUP_BOARD_ADDON)
        if ok and loaded then
            return true
        end
    end

    return SystemAPI and type(SystemAPI.IsAddOnLoadedSafe) == "function" and SystemAPI.IsAddOnLoadedSafe(PREMADE_GROUP_BOARD_ADDON) or false
end

local function OpenPremadeGroupBoard()
    if not YUI.IsRetail or not EnsurePremadeGroupBoardLoaded() then
        return false
    end

    if type(_G.PGB_TOGGLE) == "function" then
        local ok = pcall(_G.PGB_TOGGLE)
        if ok then return true end
    end

    local addon = _G.PremadeGroupBoard
    local mainFrame = type(addon) == "table" and addon.MainFrame or nil
    if type(mainFrame) == "table" and type(mainFrame.Toggle) == "function" then
        local ok = pcall(mainFrame.Toggle, mainFrame)
        if ok then return true end
    end

    for _, cmd in ipairs(PREMADE_GROUP_BOARD_SLASH_COMMANDS) do
        if RunRegisteredSlashCommand(cmd) then
            return true
        end
    end

    if API and type(API.RunSlashCmd) == "function" then
        for _, cmd in ipairs(PREMADE_GROUP_BOARD_SLASH_COMMANDS) do
            if API.RunSlashCmd(cmd) then
                return true
            end
        end
    end

    return false
end

function YBar:GetProfile()
    if YUI.DB and YUI.DB.GetProfile then
        local profile = YUI.DB:GetProfile("ybar")
        if type(profile) == "table" then
            return profile
        end
    end
    return nil
end

function YBar:EnsureDB()
    local profile = self:GetProfile()
    if type(profile) ~= "table" then
        return type(self.db) == "table" and self.db or nil
    end

    if type(profile.YBar) ~= "table" then
        profile.YBar = {}
    end
    self.db = profile.YBar
    return self.db
end

function YBar:GetDB()
    return self:EnsureDB()
end

function YBar:IsMissingBundleFontPath(fontPath)
    if type(fontPath) ~= "string" or not fontPath:find("sharedmedia-fonts", 1, true) then
        return false
    end
    local Assets = YUI and YUI.Assets
    return Assets and Assets.IsBundleAvailable and not Assets:IsBundleAvailable("sharedmedia-fonts")
end

function YBar:ResolveFontPath(font, defaultFont, lsm)
    defaultFont = defaultFont or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    if type(font) ~= "string" or font == "" then
        return defaultFont
    end

    if self:IsMissingBundleFontPath(font) then
        return defaultFont
    end

    local isPath = font:find("\\", 1, true) or font:find("/", 1, true)
    if not isPath and lsm and lsm.Fetch then
        local fontPath = lsm:Fetch("font", font, true)
        if type(fontPath) == "string" and fontPath ~= "" then
            if self:IsMissingBundleFontPath(fontPath) then
                return defaultFont
            end
            return fontPath
        end
        return defaultFont
    end

    return font
end

-- 模块列表
YBar.Modules = {}
-- 注册的模块对象 (Name -> ModuleObj)
YBar.RegisteredModules = {}

-- 默认配置
local defaults = {
    enable = true,
    bottomHeight = 21,
    topHeight = 21,
    texture = " |cFFFF00FFY|r|cFFFF6666U|r|cFFFF9900I|r |CFFBA55D3None|r",
    point = "TOP",
    x = 0,
    y = -10,
    bgColor = {1, 1, 1, 1},
    classColor = false,
    fontOutline = false,
    fontShadow = true,
    -- 模块排序配置
    modules = {
        top = {
            "None", "None", "None", "None", "None", "None", "None", "None", "None", "None", "None"
        },
        bottom = {
            "MicroMenu",
            "Stats",
            "Teleports",
            "Professions",
            "Clock",
            "Talents",
            "DurabilityMount",
            "Currency",
            "System",
            "None",
            "None",
        }
    },
    -- 模块个性化配置 (name -> { align = "LEFT", margin = 0 })
    items = {
        MicroMenu = { align = "LEFT", margin = 0 },
        Stats = { align = "RIGHT", margin = 0 },
        Teleports = { align = "RIGHT", margin = 0 },
        Professions = { align = "RIGHT", margin = 0 },
        Clock = { align = "LEFT", margin = 0 },
        Talents = { align = "LEFT", margin = 0 },
        DurabilityMount = { align = "RIGHT", margin = 0 },
        Currency = { align = "RIGHT", margin = 0 },
        System = { align = "RIGHT", margin = 0 },
    },
    -- 中间锚点位置 (1-11)，nil 表示无居中
    center = {
        top = nil,
        bottom = nil
    }
}

if YUI.IsForever then
    defaults.modules.bottom = { "MicroMenu", "Stats", "Clock", "Currency", "System", "None", "None", "None", "None", "None", "None" }
end

YBar.Colors = {
    HEADER_TEXT_COLOR = {r = 1, g = 0.82, b = 0},
    SUBHEADER_TEXT_COLOR = {r = 0, g = 0.6, b = 1},
    BNET_NAME_COLOR = {r = 0, g = 0.6, b = 1}, -- |cff0099ff
    WOW_NAME_COLOR = {r = 1, g = 0.82, b = 0},
    INACTIVE_ZONE_COLOR = {r = 0.6, g = 0.6, b = 0.6}, -- Grey
    ACTIVE_ZONE_COLOR = {r = 0.3, g = 1, b = 0.3}, -- Greenish
    FOOTER_TEXT_COLOR = {r = 0.5, g = 0.5, b = 0.5},
    TOOLTIP_HIGHLIGHT_COLOR = {r = 1, g = 0.82, b = 0},
}

YBar.Colors_Hex = {}
for k, v in pairs(YBar.Colors) do
    YBar.Colors_Hex[k] = CreateColor(v.r, v.g, v.b):GenerateHexColor()
    -- print(k, YBar.Colors_Hex[k])
end

local function GetDefaultSubModuleId(name)
    return "ybar." .. string.lower(tostring(name or ""))
end

function YBar:RegisterLifecycleModule(module, lifecycle)
    if not module or not module.name or not YUI.Module or not YUI.Module.Register then
        return nil
    end

    lifecycle = lifecycle or {}
    local id = lifecycle.id or GetDefaultSubModuleId(module.name)
    module.lifecycleId = id
    module.lifecycleParent = lifecycle.parent or "ybar"
    self.LifecycleModules = self.LifecycleModules or {}
    self.LifecycleModules[id] = module

    return YUI.Module:Register({
        id = id,
        name = lifecycle.name or module.name,
        parent = module.lifecycleParent,
        product = lifecycle.product or "ybar",
        scope = lifecycle.scope or "ybar",
        defaultEnabled = lifecycle.defaultEnabled ~= false,
        owner = module,
        dependencies = lifecycle.dependencies or {"ybar"},
        getEnabled = function(owner)
            return YUI.YBar and YUI.YBar:IsSubModuleEnabled(owner.name)
        end,
        setEnabled = function(owner, enabled)
            if YUI.YBar then
                return YUI.YBar:SetSubModuleEnabled(owner.name, enabled)
            end
            return false
        end,
        OnInitialize = "OnLifecycleInitialize",
        OnEnable = "OnLifecycleEnable",
        OnDisable = "OnLifecycleDisable",
        OnProfileChanged = "OnLifecycleProfileChanged",
        OnConfigChanged = "OnLifecycleConfigChanged",
        OnLayoutChanged = "OnLifecycleLayoutChanged",
    })
end

function YBar:RegisterModule(module, lifecycle)
    if not module or not module.name then
        return nil
    end

    self.RegisteredModules[module.name] = module

    if lifecycle then
        self:RegisterLifecycleModule(module, lifecycle)
    end

    return module
end

function YBar:GetModule(name)
    return self.RegisteredModules[name]
end

function YBar:OpenMeetingHorn()
    if OpenPremadeGroupBoard() then
        return true
    end

    local addon = GetMeetingHornAddon()

    if addon then
        if type(addon.Toggle) == "function" then
            local ok = pcall(addon.Toggle, addon)
            if ok then return true end
        end

        if type(addon.HandleChatCommand) == "function" then
            local ok = pcall(addon.HandleChatCommand, addon, "")
            if ok then return true end
        end

        if type(addon.SlashCommand) == "function" then
            local ok = pcall(addon.SlashCommand, addon, "")
            if ok then return true end
        end
    end

    for _, cmd in ipairs(MEETING_HORN_SLASH_COMMANDS) do
        if RunRegisteredSlashCommand(cmd) then
            return true
        end
    end

    if HasMeetingHornAddonEnabled() and API and type(API.RunSlashCmd) == "function" then
        for _, cmd in ipairs(MEETING_HORN_SLASH_COMMANDS) do
            if API.RunSlashCmd(cmd) then
                return true
            end
        end
    end

    return false
end

function YBar:IsModuleOnBar(name)
    if not self.db or not self.db.modules then return false end
    
    for _, modName in ipairs(self.db.modules.top) do
        if modName == name then return true end
    end
    
    for _, modName in ipairs(self.db.modules.bottom) do
        if modName == name then return true end
    end
    
    return false
end

function YBar:IsSubModuleEnabled(name)
    local module = self.RegisteredModules[name]
    if module and module.brokerName and not module:IsBarItemRenderable() then return false end
    return self:IsEnabled() and self:IsModuleOnBar(name)
end

function YBar:RemoveModuleFromLayout(name)
    if not self.db or not self.db.modules then return false end

    self._moduleLastPositions = self._moduleLastPositions or {}
    local removed = false

    for _, listName in ipairs({"top", "bottom"}) do
        local list = self.db.modules[listName]
        if list then
            for index, modName in ipairs(list) do
                if modName == name then
                    self._moduleLastPositions[name] = { listName = listName, index = index }
                    list[index] = "None"
                    if self.db.center and self.db.center[listName] == index then
                        self.db.center[listName] = nil
                    end
                    removed = true
                end
            end
        end
    end

    return removed
end

function YBar:RestoreModuleToLayout(name)
    if not self.db or not self.db.modules then return false end
    if self.BrokerManager then self.BrokerManager:PreferEntry(name) end
    if self:IsModuleOnBar(name) then return true end

    local last = self._moduleLastPositions and self._moduleLastPositions[name]
    if last and self.db.modules[last.listName] and self.db.modules[last.listName][last.index] == "None" then
        self.db.modules[last.listName][last.index] = name
        return true
    end

    for _, listName in ipairs({"bottom", "top"}) do
        local list = self.db.modules[listName]
        if list then
            for index, modName in ipairs(list) do
                if modName == "None" then
                    list[index] = name
                    return true
                end
            end
        end
    end

    if self.db.modules.bottom then
        table.insert(self.db.modules.bottom, name)
        return true
    end

    return false
end

function YBar:SetSubModuleEnabled(name, enabled)
    if not self.db or not self.db.modules then return false end

    local changed
    if enabled then
        changed = self:RestoreModuleToLayout(name)
    else
        changed = self:RemoveModuleFromLayout(name)
    end

    if changed then
        self:UpdateLayout()
    end

    return changed
end

function YBar:ShouldUpdateModule(name, module)
    if not module then
        return true
    end

    if module._hasError then
        return false
    end

    if not module.lifecycleId then
        return true
    end

    return self:IsSubModuleEnabled(name)
end

function YBar:SyncModuleLifecycles()
    if self.BrokerManager then self.BrokerManager:Sync() end
    if not YUI.Module or not YUI.Module.Enable or not YUI.Module.Disable then
        return
    end

    local parentEnabled = self:IsEnabled()
    for name, module in pairs(self.RegisteredModules) do
        if module.lifecycleId then
            if module._hasError then
                if module.DetachRuntime and not module._ybarErrorRuntimeDetached then
                    module._ybarErrorRuntimeDetached = true
                    xpcall(function()
                        module:DetachRuntime()
                    end, geterrorhandler())
                end
            elseif parentEnabled and self:IsModuleOnBar(name) and (not module.brokerName or module:IsBarItemRenderable()) then
                YUI.Module:Enable(module.lifecycleId)
            else
                YUI.Module:Disable(module.lifecycleId)
            end
        end
    end
end

function YBar:RegisterGUI2Tokens()
    if not GUI2 or not GUI2.RegisterTokenProvider or not GUI2.CreateSolidPaint then
        return
    end
    if self.gui2TokensRegistered then
        return
    end

    if GUI2:RegisterTokenProvider("ybar", function(tokens)
        tokens["color.ybar.text"] = GUI2:CreateSolidPaint(1, 1, 1, 1)
        tokens["color.ybar.panel.hoverBg"] = GUI2:CreateSolidPaint(0, 0, 0, 0.5)
        tokens["color.ybar.panel.hint"] = GUI2:CreateSolidPaint(0.9, 0.1, 0, 0.8)
        tokens["color.ybar.progress.track"] = GUI2:CreateSolidPaint(0.2, 0.2, 0.2, 1)
        tokens["color.ybar.progress.fill"] = GUI2:CreateSolidPaint(1, 1, 1, 0.8)
        tokens["color.ybar.progress.rested"] = GUI2:CreateSolidPaint(0, 0.66, 1, 0.8)
        tokens["color.ybar.micromenu.underline"] = GUI2:CreateSolidPaint(1, 1, 1, 1)
        tokens["color.ybar.tooltip.header"] = GUI2:CreateSolidPaint(1, 0.82, 0, 1)
        tokens["color.ybar.tooltip.subheader"] = GUI2:CreateSolidPaint(0, 0.6, 1, 1)
        tokens["color.ybar.teleports.arrow"] = GUI2:CreateSolidPaint(1, 1, 1, 1)
        tokens["color.ybar.raidmarkers.handle"] = GUI2:CreateSolidPaint(0.6, 0.6, 0.6, 0.8)
    end) then
        self.gui2TokensRegistered = true
    end
end

function YBar:Initialize()
    local traceRecord
    if YUI.Trace and YUI.Trace.Begin then
        traceRecord = YUI.Trace:Begin("Products", "YBar:Initialize", "ybar", {
            moduleId = "ybar",
            phase = "Initialize",
            durationKind = "sync",
            blocking = true,
        })
    end

    if YUI.DB and YUI.DB.RestoreProductProfile then
        YUI.DB:RestoreProductProfile("ybar")
    end

    self:RegisterGUI2Tokens()
    if not self:EnsureDB() then
        if traceRecord and YUI.Trace and YUI.Trace.Finish then
            YUI.Trace:Finish(traceRecord, "skip", nil, "db not ready")
        end
        return
    end

    -- Idempotency check: if frame already exists, just return (or reload DB)
    if self.frame then 
        self:ReloadDB()
        if traceRecord and YUI.Trace and YUI.Trace.Finish then
            YUI.Trace:Finish(traceRecord, "ok", nil, "reload")
        end
        return 
    end

    -- IMPORTANT: When a new profile is created, the active YBar DB might be empty or missing default structure.
    -- We need to ensure it's fully populated with defaults.
    
    self:EnsureDefaults()
    
    self:CreateBar()
    self:LoadModules()
    self:UpdatePosition()

    if traceRecord and YUI.Trace and YUI.Trace.Finish then
        YUI.Trace:Finish(traceRecord, "ok")
    end
end

function YBar:EnsureDefaults()
    local db = self:EnsureDB()
    if type(db) ~= "table" then
        return
    end
    
    -- Ensure modules table exists
    if not db.modules then
        db.modules = {}
    end

    -- Migration: height -> bottomHeight/topHeight
    if db.height then
        if not db.bottomHeight then db.bottomHeight = db.height end
        if not db.topHeight then db.topHeight = db.height end
        db.height = nil
    end

    -- Check and initialize each module list from defaults
    if defaults.modules then
        for k, v in pairs(defaults.modules) do
            if not db.modules[k] then
                db.modules[k] = {}
                for i, name in ipairs(v) do
                    table.insert(db.modules[k], name)
                end
            else
                -- Backfill existing lists to match default length (11)
                local currentLen = #db.modules[k]
                local defaultLen = #v
                if currentLen < defaultLen then
                    for i = currentLen + 1, defaultLen do
                        table.insert(db.modules[k], "None")
                    end
                end
            end
        end
    end
    
    -- Shallow copy other defaults
    for k, v in pairs(defaults) do
        if k ~= "modules" and k ~= "center" and db[k] == nil then
            if k == "items" then
                -- Deep copy items
                db[k] = {}
                for modName, settings in pairs(v) do
                    db[k][modName] = {}
                    for sk, sv in pairs(settings) do
                        db[k][modName][sk] = sv
                    end
                end
            else
                db[k] = v
            end
        end
    end
    
    if not db.items then db.items = {} end
    if not db.center then db.center = {top = nil, bottom = nil} end
    if not db.displayModes then db.displayModes = {} end
    self.db = db
end

function YBar:ReloadDB()
    if self.TeleportRestore then self.TeleportRestore:Cancel() end
    if self.BrokerManager then self.BrokerManager:ResetProfile() end
    -- 1. Ensure defaults are populated for the new profile
    self:EnsureDefaults()
    if not self.db then
        return
    end
    
    -- 2. Update Appearance (colors, textures)
    if self.CurrencyTracking then self.CurrencyTracking.Prepare(self.db) end
    self:UpdateAppearance()
    
    -- 3. Update Position (show/hide based on enable setting)
    self:UpdatePosition()
    
    -- 4. Force Layout Update (re-render modules)
    -- We clear layoutPending to force an update even if one was pending
    self.layoutPending = false
    self:UpdateLayoutImmediate()
    
    -- 5. Notify Modules (Optional: if modules cache their own DB refs)
    for name, module in pairs(self.RegisteredModules) do
        if module.OnDBReload and self:ShouldUpdateModule(name, module) then
            module:OnDBReload()
        elseif module.Update and self:ShouldUpdateModule(name, module) then
            -- Try to force update module content
            module:Update() 
        end
    end
end

function YBar:UpdatePosition()
    if not self.frame then return end

    local enable = self.db.enable
    if enable == nil then enable = true end
    if enable then
        self.frame:Show()
    else
        self.frame:Hide()
    end
    
    -- Notify modules of visibility change
    for name, module in pairs(self.RegisteredModules) do
        if module.Update and self:ShouldUpdateModule(name, module) then
            module:Update()
        end
    end
end

function YBar:SetEnabled(enabled)
    local db = self:EnsureDB()
    if not db then
        return
    end
    db.enable = enabled and true or false
    self.db = db
end

function YBar:IsEnabled()
    local db = self:EnsureDB()
    if not db or db.enable == nil then
        return true
    end
    return db.enable ~= false
end

function YBar:OnLifecycleEnable()
    local housingGuard = self.HousingDashboardGuard
    if housingGuard and housingGuard.Enable then
        housingGuard:Enable()
    end
    if not self.frame then
        return
    end
    self:UpdatePosition()
    self:SyncModuleLifecycles()
    self:UpdateLayout()
end

function YBar:OnLifecycleDisable()
    local housingGuard = self.HousingDashboardGuard
    if housingGuard and housingGuard.Disable then
        housingGuard:Disable()
    end
    if not self.frame then
        return
    end
    self:UpdatePosition()
    self:SyncModuleLifecycles()
end

function YBar:OnLifecycleProfileChanged()
    self:ReloadDB()
end

function YBar:ApplyBarHeights()
    if self.topFrame then
        self.topFrame:SetHeight(self.db.topHeight or 21)
    end
    if self.bottomFrame then
        self.bottomFrame:SetHeight(self.db.bottomHeight or 21)
    end
end

function YBar:QueueBarHeightUpdate()
    self.barHeightPendingInCombat = true
    if self.barHeightEventReg then return end

    self.barHeightEventReg = YUI.Event:Once("PLAYER_REGEN_ENABLED", function()
        self.barHeightEventReg = false
        if not self.barHeightPendingInCombat then return end
        self.barHeightPendingInCombat = false
        self:ApplyBarHeights()
        self:UpdateLayout()
    end)
end

function YBar:UpdateAppearance()
    if not self.frame then return end
    
    local bottomHeight = self.db.bottomHeight or 21
    local topHeight = self.db.topHeight or 21
    local texture = self.db.texture or defaults.texture
    local texFile = LSM:Fetch("statusbar", texture)
    local color = self.db.bgColor or defaults.bgColor
    -- Ensure color is a flat table
    if type(color) == "table" and type(color[1]) == "table" then
        color = color[1]
    end
    
    if self.db.classColor then
        local _, classFilename = UnitAPI.UnitClass("player")
        if classFilename then
            local classColor = UnitAPI.GetClassColor(classFilename)
            if classColor then
                -- Keep alpha from bgColor setting
                color = {classColor.r, classColor.g, classColor.b, color[4] or 0.8}
            end
        end
    end

    local needsHeightUpdate = false
    if self.topFrame and self.topFrame:GetHeight() ~= topHeight then
        needsHeightUpdate = true
    end
    if self.bottomFrame and self.bottomFrame:GetHeight() ~= bottomHeight then
        needsHeightUpdate = true
    end
    if needsHeightUpdate then
        if SecurityAPI.InCombatLockdown() then
            self:QueueBarHeightUpdate()
        else
            self:ApplyBarHeights()
        end
    end

    if self.topFrame then
        if self.topFrame.bg then
            self.topFrame.bg:SetTexture(texFile)
            local r, g, b, a = unpack(color)
            if r and g and b then
                self.topFrame.bg:SetVertexColor(r, g, b, a or 1)
            else
                 -- Fallback if color is invalid
                self.topFrame.bg:SetVertexColor(1, 1, 1, 1)
            end
            self.topFrame.bg:SetTexCoord(0, 1, 1, 0)
        end
    end
    
    if self.bottomFrame then
        if self.bottomFrame.bg then
            self.bottomFrame.bg:SetTexture(texFile)
            local r, g, b, a = unpack(color)
            if r and g and b then
                self.bottomFrame.bg:SetVertexColor(r, g, b, a or 1)
            else
                 -- Fallback if color is invalid
                self.bottomFrame.bg:SetVertexColor(1, 1, 1, 1)
            end
            self.bottomFrame.bg:SetTexCoord(0, 1, 0, 1)
        end
    end
end

function YBar:CreateIconSlot(parent, opts)
    opts = opts or {}
    local app = GUI2 and GUI2.Application
    if not app or not app.CreateIconSlot then
        local icon = GUI2:CreateTexture(parent, { layer = "ARTWORK" })
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetSize(opts.size or 22, opts.size or 22)
        if opts.icon then
            icon:SetTexture(opts.icon)
        end
        return nil, icon
    end

    local padding = opts.padding
    if padding == nil then
        padding = 2
    end

    local slot = app:CreateIconSlot(parent, {
        size = opts.size,
        icon = opts.icon,
        variant = opts.variant,
        shape = opts.shape or "rounded",
        padding = padding,
        selected = opts.selected,
        disabled = opts.disabled,
        count = opts.count,
    })
    if slot.EnableMouse then
        slot:EnableMouse(false)
    end

    self.GUI2IconSlots = self.GUI2IconSlots or {}
    table.insert(self.GUI2IconSlots, slot)
    return slot, slot.icon
end

function YBar:SetIconSlotChromeVisible(slot, visible)
    if not slot then return end

    if slot.ybarDefaultIconSlotVariant == nil then
        slot.ybarDefaultIconSlotVariant = slot.gui2Variant or "surface"
    end
    if slot.ybarDefaultIconSlotSurface == nil then
        slot.ybarDefaultIconSlotSurface = slot.gui2Surface or "color.surface.sunken"
    end

    visible = visible ~= false
    slot.ybarIconSlotChromeHidden = not visible
    slot.gui2IconChromeVisible = visible
    slot.gui2Variant = visible and slot.ybarDefaultIconSlotVariant or "bare"

    if visible and slot.gui2Variant ~= "bare" then
        if GUI2 and GUI2.ApplyBackdrop and slot.SetBackdrop then
            GUI2:ApplyBackdrop(slot, slot.ybarDefaultIconSlotSurface)
        elseif slot.SetBackdropColor and GUI2 and GUI2.GetColor then
            slot:SetBackdropColor(GUI2:GetColor(slot.ybarDefaultIconSlotSurface))
        end
    else
        if slot.SetBackdropColor then
            slot:SetBackdropColor(0, 0, 0, 0)
        end
    end

    if slot.SetState then
        slot:SetState(slot.gui2State or "normal")
    elseif not visible and slot.SetBackdropBorderColor then
        slot:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

function YBar:SetIconSlotTexture(slot, texture, atlas, texCoord)
    local icon = slot and slot.icon
    if not icon then return end

    self:SetIconSlotChromeVisible(slot, true)

    if atlas then
        icon:SetTexture(nil)
        icon:SetAtlas(atlas)
        if texCoord then
            icon:SetTexCoord(unpack(texCoord))
        end
        icon:SetDesaturated(false)
        icon:SetVertexColor(1, 1, 1)
        icon:SetBlendMode("ADD")
    else
        icon:SetTexture(texture)
        if texCoord then
            icon:SetTexCoord(unpack(texCoord))
        else
            icon:SetTexCoord(unpack(YBAR_NATIVE_ICON_TEXCOORDS))
        end
        icon:SetVertexColor(1, 1, 1)
        icon:SetBlendMode("BLEND")
    end
end

function YBar:SetIconSlotIcon(slot, iconData, fallbackTexture)
    local icon = slot and slot.icon
    if not icon then return false end

    local Icons = YUI.API and YUI.API.Icons
    if type(iconData) == "table" and Icons and Icons.ApplyIcon and Icons.ApplyIcon(icon, iconData) then
        self:SetIconSlotChromeVisible(slot, iconData.custom ~= true)
        if iconData.kind == "spec" and iconData.custom ~= true and not iconData.atlas then
            icon:SetTexCoord(unpack(YBAR_NATIVE_ICON_TEXCOORDS))
        end
        icon:SetDesaturated(false)
        icon:SetVertexColor(1, 1, 1)
        icon:SetBlendMode(iconData.atlas and "ADD" or "BLEND")
        return true
    end

    self:SetIconSlotTexture(slot, fallbackTexture or (type(iconData) == "table" and iconData.texture) or iconData)
    return true
end

function YBar:SetIconSlotState(slot, state)
    if slot and slot.SetState then
        slot:SetState(state or "normal")
    end

    local parent = slot and slot.GetParent and slot:GetParent()
    if not parent or not parent.SetFrameLevel or not parent.GetFrameLevel then
        return
    end

    if parent.gui2IconSlotBaseLevel == nil then
        parent.gui2IconSlotBaseLevel = parent:GetFrameLevel()
    end

    if state == "hover" or state == "selected" or state == "active" then
        parent:SetFrameLevel(parent.gui2IconSlotBaseLevel + 10)
    else
        parent:SetFrameLevel(parent.gui2IconSlotBaseLevel)
    end
end

function YBar:RefreshGUI2IconSlots()
    if not self.GUI2IconSlots or not GUI2 then return end

    for i = #self.GUI2IconSlots, 1, -1 do
        local slot = self.GUI2IconSlots[i]
        if not slot or not slot.GetParent or not slot:GetParent() then
            table.remove(self.GUI2IconSlots, i)
        else
            if GUI2.RefreshPrimitive then
                GUI2:RefreshPrimitive(slot)
            end
            if slot.SetState then
                slot:SetState(slot.gui2State or "normal")
            end
            if slot.ybarIconSlotChromeHidden then
                self:SetIconSlotChromeVisible(slot, false)
            end
        end
    end
end

function YBar:CreateStatusText(parent, opts)
    opts = opts or {}
    local app = GUI2 and GUI2.Application
    if not app or not app.CreateStatusText then
        local text = GUI2:CreateText(parent, opts.value or opts.text or "", opts.fontSizeKey or "font.size.sm", opts.colorKey or "color.ybar.text", opts.justifyH or "CENTER")
        text:SetPoint("LEFT", parent, "LEFT", 0, 0)
        text:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        text:SetJustifyH(opts.justifyH or "CENTER")
        return nil, text
    end

    local status = app:CreateStatusText(parent, {
        width = opts.width,
        height = opts.height,
        label = opts.label,
        value = opts.value,
        text = opts.text,
        tone = opts.tone,
        variant = opts.variant,
        single = opts.single,
        justifyH = opts.justifyH,
        fontSizeKey = opts.fontSizeKey,
        valueFontSizeKey = opts.valueFontSizeKey,
        labelFontSizeKey = opts.labelFontSizeKey,
        colorKey = opts.colorKey,
        colorFallback = opts.colorFallback,
        labelColorKey = opts.labelColorKey,
        leftPadding = opts.leftPadding,
        rightPadding = opts.rightPadding,
    })
    status:SetAllPoints(parent)
    if status.EnableMouse then
        status:EnableMouse(false)
    end

    self.GUI2StatusTexts = self.GUI2StatusTexts or {}
    if status.value then
        status.value.gui2StatusOwner = status
    end
    table.insert(self.GUI2StatusTexts, status)
    return status, status.value
end

function YBar:RefreshGUI2StatusTexts()
    if not self.GUI2StatusTexts or not GUI2 then return end

    for i = #self.GUI2StatusTexts, 1, -1 do
        local status = self.GUI2StatusTexts[i]
        if not status or not status.GetParent or not status:GetParent() then
            table.remove(self.GUI2StatusTexts, i)
        else
            if GUI2.RefreshPrimitive then
                GUI2:RefreshPrimitive(status)
            end
            if status.RefreshTheme then
                status:RefreshTheme()
            elseif status.SetTone then
                status:SetTone(status.gui2Tone)
            end
            if status.gui2ValueRawColor and status.value then
                status.value:SetTextColor(unpack(status.gui2ValueRawColor))
            end
        end
    end
end

function YBar:CreateTextPairLine(parent, opts)
    opts = opts or {}
    local line = GUI2:CreateFrame(parent)
    line:SetSize(opts.width or 120, opts.height or 20)
    line.gui2Component = "YBarTextPairLine"

    line.label = GUI2:CreateText(line, opts.label or "", opts.labelFontSizeKey or "font.size.sm", opts.labelColorKey or "color.ybar.text", "LEFT")
    line.value = GUI2:CreateText(line, opts.value or "", opts.valueFontSizeKey or "font.size.sm", opts.valueColorKey or "color.ybar.text", "RIGHT")

    line.label:SetPoint("LEFT", opts.leftPadding or 5, 0)
    line.label:SetJustifyH("LEFT")
    line.label:SetShadowOffset(1, -1)

    line.value:SetPoint("RIGHT", -(opts.rightPadding or 5), 0)
    line.value:SetJustifyH("RIGHT")
    line.value:SetShadowOffset(1, -1)
    line.value:SetWordWrap(false)

    return line
end

local function ClampProgressValue(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function ApplyProgressLineColor(texture, colorKey, fallback)
    if GUI2 and GUI2.GetColor then
        texture:SetColorTexture(GUI2:GetColor(colorKey, fallback))
    else
        texture:SetColorTexture(unpack(fallback))
    end
end

local function ApplyTextureColor(texture, colorKey, fallback, mode)
    if not texture then return end

    if mode == "vertex" then
        if GUI2 and GUI2.GetColor then
            texture:SetVertexColor(GUI2:GetColor(colorKey, fallback))
        else
            texture:SetVertexColor(unpack(fallback))
        end
    else
        if GUI2 and GUI2.GetColor then
            texture:SetColorTexture(GUI2:GetColor(colorKey, fallback))
        else
            texture:SetColorTexture(unpack(fallback))
        end
    end
end

local function ApplyFontStringColor(text, colorKey, fallback)
    if GUI2 and GUI2.GetColor then
        text:SetTextColor(GUI2:GetColor(colorKey, fallback))
    else
        text:SetTextColor(unpack(fallback))
    end
end

function YBar:SetStatusTextColor(status, colorKey, fallback)
    if not status then return end
    status.gui2ValueRawColor = nil
    status.gui2ValueColorKey = colorKey or status.gui2ValueColorKey or "color.ybar.text"
    status.gui2ValueColorFallback = fallback or status.gui2ValueColorFallback
    if status.value then
        ApplyFontStringColor(status.value, status.gui2ValueColorKey, status.gui2ValueColorFallback or { 1, 1, 1, 1 })
    end
end

function YBar:SetStatusTextRawColor(status, r, g, b, a)
    if not status then return end

    status.gui2ValueColorKey = nil
    status.gui2ValueColorFallback = nil
    status.gui2ValueRawColor = { r or 1, g or 1, b or 1, a == nil and 1 or a }
    if status.value then
        status.value:SetTextColor(unpack(status.gui2ValueRawColor))
    end
end

function YBar:CreateThemedText(parent, opts)
    opts = opts or {}
    local colorKey = opts.colorKey or "color.ybar.text"
    local text

    text = GUI2:CreateText(parent, opts.text or "", opts.fontSizeKey or "font.size.sm", colorKey, opts.justifyH or "LEFT")

    text.gui2Component = "YBarThemedText"
    text.gui2ColorKey = colorKey
    text.gui2ColorFallback = opts.fallback or { 1, 1, 1, 1 }

    if opts.fontPath and opts.fontSize then
        text:SetFont(self:ResolveFontPath(opts.fontPath, STANDARD_TEXT_FONT), opts.fontSize, opts.fontFlags or "")
    end
    if opts.shadow then
        text:SetShadowColor(opts.shadowColorR or 0, opts.shadowColorG or 0, opts.shadowColorB or 0, opts.shadowColorA or 1)
        text:SetShadowOffset(opts.shadowOffsetX or 1, opts.shadowOffsetY or -1)
    end
    if opts.wordWrap ~= nil then
        text:SetWordWrap(opts.wordWrap)
    end

    text.RefreshTheme = function(self)
        ApplyFontStringColor(self, self.gui2ColorKey or "color.ybar.text", self.gui2ColorFallback or { 1, 1, 1, 1 })
    end
    text:RefreshTheme()

    self.GUI2ThemedTexts = self.GUI2ThemedTexts or {}
    table.insert(self.GUI2ThemedTexts, text)
    return text
end

function YBar:SetThemedTextColor(text, colorKey, fallback)
    if not text then return end
    local status = text.gui2StatusOwner
    if status then
        self:SetStatusTextColor(status, colorKey, fallback)
        return
    end

    text.gui2RawColor = nil
    text.gui2ColorKey = colorKey or text.gui2ColorKey or "color.ybar.text"
    text.gui2ColorFallback = fallback or text.gui2ColorFallback or YBAR_TEXT_FALLBACK
    ApplyFontStringColor(text, text.gui2ColorKey, text.gui2ColorFallback)
end

function YBar:SetThemedTextRawColor(text, r, g, b, a)
    if not text then return end

    local status = text.gui2StatusOwner
    if status then
        self:SetStatusTextRawColor(status, r, g, b, a)
        return
    end

    text.gui2ColorKey = nil
    text.gui2ColorFallback = nil
    text.gui2RawColor = { r or 1, g or 1, b or 1, a == nil and 1 or a }
    text:SetTextColor(unpack(text.gui2RawColor))
end

function YBar:SetThemedTextAccent(text)
    if not text then return end

    if not text.ybarTextHoverColorActive then
        local status = text.gui2StatusOwner
        text.ybarTextHoverColorActive = true
        text.ybarTextHoverStatus = status
        text.ybarTextHoverColorKey = status and status.gui2ValueColorKey or text.gui2ColorKey
        text.ybarTextHoverColorFallback = status and status.gui2ValueColorFallback or text.gui2ColorFallback
        text.ybarTextHoverRawColor = status and status.gui2ValueRawColor or text.gui2RawColor
        local r, g, b, a = text:GetTextColor()
        text.ybarTextHoverR = r
        text.ybarTextHoverG = g
        text.ybarTextHoverB = b
        text.ybarTextHoverA = a
    end

    if text.gui2StatusOwner then
        self:SetStatusTextColor(text.gui2StatusOwner, "color.baritem.hoverText", YBAR_ACCENT_FALLBACK)
    else
        self:SetThemedTextColor(text, "color.baritem.hoverText", YBAR_ACCENT_FALLBACK)
    end
end

function YBar:RestoreThemedTextColor(text, defaultColorKey, defaultFallback)
    if not text then return end

    if text.ybarTextHoverColorActive then
        local status = text.ybarTextHoverStatus or text.gui2StatusOwner
        local colorKey = text.ybarTextHoverColorKey
        local fallback = text.ybarTextHoverColorFallback
        local rawColor = text.ybarTextHoverRawColor
        local r = text.ybarTextHoverR
        local g = text.ybarTextHoverG
        local b = text.ybarTextHoverB
        local a = text.ybarTextHoverA

        text.ybarTextHoverColorActive = nil
        text.ybarTextHoverStatus = nil
        text.ybarTextHoverColorKey = nil
        text.ybarTextHoverColorFallback = nil
        text.ybarTextHoverRawColor = nil
        text.ybarTextHoverR = nil
        text.ybarTextHoverG = nil
        text.ybarTextHoverB = nil
        text.ybarTextHoverA = nil

        if rawColor then
            self:SetThemedTextRawColor(text, rawColor[1], rawColor[2], rawColor[3], rawColor[4])
        elseif colorKey then
            if status then
                self:SetStatusTextColor(status, colorKey, fallback or defaultFallback or YBAR_TEXT_FALLBACK)
            else
                self:SetThemedTextColor(text, colorKey, fallback or defaultFallback or YBAR_TEXT_FALLBACK)
            end
        else
            text:SetTextColor(r or 1, g or 1, b or 1, a or 1)
        end
        return
    end

    if defaultColorKey then
        if text.gui2StatusOwner then
            self:SetStatusTextColor(text.gui2StatusOwner, defaultColorKey, defaultFallback or YBAR_TEXT_FALLBACK)
        else
            self:SetThemedTextColor(text, defaultColorKey, defaultFallback or YBAR_TEXT_FALLBACK)
        end
    end
end

function YBar:RefreshGUI2ThemedTexts()
    if not self.GUI2ThemedTexts then return end

    for i = #self.GUI2ThemedTexts, 1, -1 do
        local text = self.GUI2ThemedTexts[i]
        if not text or not text.GetParent or not text:GetParent() then
            table.remove(self.GUI2ThemedTexts, i)
        elseif text.RefreshTheme then
            text:RefreshTheme()
            if text.gui2RawColor then
                text:SetTextColor(unpack(text.gui2RawColor))
            end
        end
    end
end

function YBar:CreateThemedTexture(parent, opts)
    opts = opts or {}
    local texture = GUI2:CreateTexture(parent, { layer = opts.layer or "ARTWORK" })
    texture.gui2Component = "YBarThemedTexture"
    texture.gui2ColorKey = opts.colorKey or "color.ybar.text"
    texture.gui2ColorFallback = opts.fallback or { 1, 1, 1, 1 }
    texture.gui2ColorMode = opts.colorMode or ((opts.texture or opts.atlas) and "vertex" or "solid")

    if opts.texture then
        texture:SetTexture(opts.texture)
    elseif opts.atlas then
        texture:SetAtlas(opts.atlas)
    end

    texture.RefreshTheme = function(self)
        ApplyTextureColor(self, self.gui2ColorKey or "color.ybar.text", self.gui2ColorFallback or { 1, 1, 1, 1 }, self.gui2ColorMode)
    end
    texture:RefreshTheme()

    self.GUI2ThemedTextures = self.GUI2ThemedTextures or {}
    table.insert(self.GUI2ThemedTextures, texture)
    return texture
end

function YBar:SetThemedTextureColor(texture, colorKey, fallback)
    if not texture then return end
    texture.gui2ColorKey = colorKey or texture.gui2ColorKey or "color.ybar.text"
    texture.gui2ColorFallback = fallback or texture.gui2ColorFallback or { 1, 1, 1, 1 }
    ApplyTextureColor(texture, texture.gui2ColorKey, texture.gui2ColorFallback, texture.gui2ColorMode)
end

function YBar:RefreshGUI2ThemedTextures()
    if not self.GUI2ThemedTextures then return end

    for i = #self.GUI2ThemedTextures, 1, -1 do
        local texture = self.GUI2ThemedTextures[i]
        if not texture or not texture.GetParent or not texture:GetParent() then
            table.remove(self.GUI2ThemedTextures, i)
        elseif texture.RefreshTheme then
            texture:RefreshTheme()
        end
    end
end

function YBar:CreatePanelHoverChrome(parent, opts)
    opts = opts or {}
    local chrome = {
        parent = parent,
        gui2Component = "YBarPanelHoverChrome",
        bgColorKey = opts.bgColorKey or "color.ybar.panel.hoverBg",
        hintColorKey = opts.hintColorKey or "color.ybar.panel.hint",
        bgFallback = opts.bgFallback or { 0, 0, 0, 0.5 },
        hintFallback = opts.hintFallback or { 0.9, 0.1, 0, 0.8 },
    }

    local bg = GUI2:CreateTexture(parent, { layer = "BACKGROUND" })
    bg:SetAllPoints(parent)
    bg:Hide()
    chrome.bg = bg

    local hint = GUI2:CreateText(parent, opts.hint or "", opts.fontSizeKey or "font.size.md", chrome.hintColorKey, "CENTER")
    hint:SetFont(self:ResolveFontPath(opts.fontPath, STANDARD_TEXT_FONT), opts.fontSize or 14, opts.fontFlags or "OUTLINE")
    hint:SetShadowColor(0, 0, 0, 1)
    hint:SetShadowOffset(1, -1)
    hint:Hide()
    chrome.hint = hint

    chrome.RefreshTheme = function(self)
        ApplyProgressLineColor(self.bg, self.bgColorKey, self.bgFallback)
        ApplyFontStringColor(self.hint, self.hintColorKey, self.hintFallback)
    end

    chrome:RefreshTheme()

    self.GUI2PanelHoverChromes = self.GUI2PanelHoverChromes or {}
    table.insert(self.GUI2PanelHoverChromes, chrome)
    return chrome
end

function YBar:RefreshGUI2PanelHoverChromes()
    if not self.GUI2PanelHoverChromes then return end

    for i = #self.GUI2PanelHoverChromes, 1, -1 do
        local chrome = self.GUI2PanelHoverChromes[i]
        local parent = chrome and chrome.parent
        if not parent or not parent.GetParent or not parent:GetParent() then
            table.remove(self.GUI2PanelHoverChromes, i)
        elseif chrome.RefreshTheme then
            chrome:RefreshTheme()
        end
    end
end

function YBar:CreateMiniProgressLine(parent, opts)
    opts = opts or {}
    local line = GUI2:CreateFrame(parent)
    line:SetSize(opts.width or 1, opts.height or 2)
    line.gui2Component = "YBarMiniProgressLine"
    line.gui2TrackColorKey = opts.trackColorKey or "color.ybar.progress.track"
    line.gui2FillColorKey = opts.fillColorKey or "color.ybar.progress.fill"
    line.gui2ExtraColorKey = opts.extraColorKey or "color.ybar.progress.rested"
    line.gui2TrackFallback = opts.trackFallback or { 0.2, 0.2, 0.2, 1 }
    line.gui2FillFallback = opts.fillFallback or { 1, 1, 1, 0.8 }
    line.gui2ExtraFallback = opts.extraFallback or { 0, 0.66, 1, 0.8 }

    local track = GUI2:CreateTexture(line, { layer = "BORDER" })
    track:SetAllPoints(line)
    line.track = track

    local fill = GUI2:CreateTexture(line, { layer = "ARTWORK" })
    fill:SetPoint("LEFT", line, "LEFT", 0, 0)
    fill:SetHeight(opts.height or 2)
    line.fill = fill

    local extra = GUI2:CreateTexture(line, { layer = "ARTWORK" })
    extra:SetPoint("LEFT", line, "LEFT", 0, 0)
    extra:SetHeight(opts.height or 2)
    line.extra = extra

    line.RefreshTheme = function(self)
        ApplyProgressLineColor(self.track, self.gui2TrackColorKey, self.gui2TrackFallback)
        ApplyProgressLineColor(self.fill, self.gui2FillColorKey, self.gui2FillFallback)
        ApplyProgressLineColor(self.extra, self.gui2ExtraColorKey, self.gui2ExtraFallback)
    end

    line.RefreshValues = function(self)
        local width = self.barWidth or self:GetWidth() or 0
        local height = self:GetHeight() or opts.height or 2
        local primary = ClampProgressValue(self.primaryValue)
        local extraValue = ClampProgressValue(self.extraValue)
        if primary + extraValue > 1 then
            extraValue = 1 - primary
        end

        local primaryWidth = math.floor((width * primary) + 0.5)
        local extraWidth = math.floor((width * extraValue) + 0.5)

        self.fill:ClearAllPoints()
        self.fill:SetPoint("LEFT", self, "LEFT", 0, 0)
        self.fill:SetHeight(height)
        self.fill:SetWidth(primaryWidth)
        if primaryWidth > 0 then self.fill:Show() else self.fill:Hide() end

        self.extra:ClearAllPoints()
        self.extra:SetPoint("LEFT", self, "LEFT", primaryWidth, 0)
        self.extra:SetHeight(height)
        self.extra:SetWidth(extraWidth)
        if extraWidth > 0 then self.extra:Show() else self.extra:Hide() end
    end

    line.SetBarWidth = function(self, width)
        width = tonumber(width) or 0
        if width < 1 then width = 1 end
        self.barWidth = width
        self:SetWidth(width)
        self:RefreshValues()
    end

    line.SetValues = function(self, primary, extraValue)
        self.primaryValue = primary or 0
        self.extraValue = extraValue or 0
        self:RefreshValues()
    end

    line:RefreshTheme()
    line:SetValues(opts.value or 0, opts.extraValue or 0)

    self.GUI2MiniProgressLines = self.GUI2MiniProgressLines or {}
    table.insert(self.GUI2MiniProgressLines, line)
    return line
end

function YBar:RefreshGUI2MiniProgressLines()
    if not self.GUI2MiniProgressLines then return end

    for i = #self.GUI2MiniProgressLines, 1, -1 do
        local line = self.GUI2MiniProgressLines[i]
        if not line or not line.GetParent or not line:GetParent() then
            table.remove(self.GUI2MiniProgressLines, i)
        elseif line.RefreshTheme then
            line:RefreshTheme()
            if line.RefreshValues then
                line:RefreshValues()
            end
        end
    end
end

function YBar:RegisterBarItemHoverText(frame, ...)
    if not frame then return end

    frame.ybarHoverTexts = frame.ybarHoverTexts or {}
    for i = 1, select("#", ...) do
        local text = select(i, ...)
        if text then
            local exists = false
            for _, existing in ipairs(frame.ybarHoverTexts) do
                if existing == text then
                    exists = true
                    break
                end
            end
            if not exists then
                table.insert(frame.ybarHoverTexts, text)
            end
        end
    end
end

function YBar:ApplyBarItemHover(frame)
    if not frame then return end

    if frame.gui2Component == "BarItem" and frame.SetState then
        frame:SetState("hover")
    end

    local texts = frame.ybarHoverTexts
    if not texts then return end
    for i = #texts, 1, -1 do
        local text = texts[i]
        if text and text.GetParent and text:GetParent() then
            self:SetThemedTextAccent(text)
        else
            table.remove(texts, i)
        end
    end
end

function YBar:RestoreBarItemHover(frame)
    if not frame then return end

    local texts = frame.ybarHoverTexts
    if texts then
        for i = #texts, 1, -1 do
            local text = texts[i]
            if text and text.GetParent and text:GetParent() then
                self:RestoreThemedTextColor(text, "color.ybar.text", YBAR_TEXT_FALLBACK)
            else
                table.remove(texts, i)
            end
        end
    end

    if frame.gui2Component == "BarItem" and frame.SetState then
        frame:SetState(frame.gui2Selected and "selected" or "normal")
    end
end

function YBar:CreateBarItem(parent, opts)
    opts = opts or {}
    local app = GUI2 and GUI2.Application
    if not app or not app.CreateBarItem then
        local frame = GUI2:CreateFrame(parent, { type = (opts.clickable or opts.onClick) and "Button" or "Frame", name = opts.name })
        if opts.width and opts.height then
            frame:SetSize(opts.width, opts.height)
        elseif opts.height then
            frame:SetHeight(opts.height)
        elseif opts.width then
            frame:SetWidth(opts.width)
        end
        if opts.onClick then
            frame:RegisterForClicks(opts.clicks or "AnyUp")
            frame:SetScript("OnClick", opts.onClick)
        end
        return frame
    end

    local item = app:CreateBarItem(parent, {
        name = opts.name,
        width = opts.width,
        height = opts.height,
        variant = opts.variant,
        clickable = opts.clickable,
        hoverable = opts.hoverable,
        clicks = opts.clicks,
        onClick = opts.onClick,
        icon = opts.icon,
        iconSize = opts.iconSize,
        iconShape = opts.iconShape,
        iconVariant = opts.iconVariant,
        iconPadding = opts.iconPadding,
        showIcon = opts.showIcon,
        text = opts.text,
        value = opts.value,
        tone = opts.tone,
        state = opts.state,
        selected = opts.selected,
        textColorKey = opts.textColorKey,
        valueColorKey = opts.valueColorKey,
        textFontSizeKey = opts.textFontSizeKey,
        valueFontSizeKey = opts.valueFontSizeKey,
        hoverSurface = opts.hoverSurface,
        hoverBorder = opts.hoverBorder,
        hoverTextColorKey = opts.hoverTextColorKey,
        hoverIcon = opts.hoverIcon,
        textLeftPadding = opts.textLeftPadding,
        textRightPadding = opts.textRightPadding,
        valueRightPadding = opts.valueRightPadding,
        iconLeftPadding = opts.iconLeftPadding,
        gap = opts.gap,
    })
    if item.iconSlot and item.iconSlot.icon and not item.icon then
        item.icon = item.iconSlot.icon
    end

    self.GUI2BarItems = self.GUI2BarItems or {}
    table.insert(self.GUI2BarItems, item)
    return item
end

function YBar:RefreshGUI2BarItems()
    if not self.GUI2BarItems or not GUI2 then return end

    for i = #self.GUI2BarItems, 1, -1 do
        local item = self.GUI2BarItems[i]
        if not item or not item.GetParent or not item:GetParent() then
            table.remove(self.GUI2BarItems, i)
        elseif item.RefreshTheme then
            item:RefreshTheme()
        elseif GUI2.RefreshPrimitive then
            GUI2:RefreshPrimitive(item)
        end
    end
end

-------------------------------------------------------------------------------
-- Display Mode Logic
-------------------------------------------------------------------------------

YBar.displayTimers = {}

function YBar:GetModuleDisplayMode(moduleName)
    if self.db and self.db.displayModes and self.db.displayModes[moduleName] then
        return self.db.displayModes[moduleName]
    end
    return "ALWAYS"
end

function YBar:UpdateDisplayModes()
    -- First, determine which groups should be visible based on mouseover
    local activeGroups = {}
    for name, module in pairs(self.RegisteredModules) do
        if module.frame and module.frame:IsMouseOver() then
            local mode = self:GetModuleDisplayMode(name)
            if mode and string.find(mode, "GROUP") then
                activeGroups[mode] = true
            end
        end
    end

    -- Iterate all registered modules and update their alpha and scripts
    for name, module in pairs(self.RegisteredModules) do
        if module.frame then
            local mode = self:GetModuleDisplayMode(name)
            local frame = module.frame
            
            -- Set Initial Alpha
            if mode == "ALWAYS" then
                frame:SetAlpha(1)
            elseif mode == "MOUSEOVER" then
                -- If mouse is currently over, keep it shown, otherwise hide
                if frame:IsMouseOver() then
                    frame:SetAlpha(1)
                else
                    frame:SetAlpha(0)
                end
            elseif mode and string.find(mode, "GROUP") then
                -- Group Mode: Show if any module in group is hovered
                if activeGroups[mode] then
                    frame:SetAlpha(1)
                else
                    frame:SetAlpha(0)
                end
            else
                 -- Fallback
                 frame:SetAlpha(0)
            end
            
            -- Hook Scripts
            if not frame.displayModeHooked then
                frame:HookScript("OnEnter", function(self)
                    YBar:OnModuleEnter(self)
                end)
                frame:HookScript("OnLeave", function(self)
                    YBar:OnModuleLeave(self)
                end)
                frame.displayModeHooked = true
            end
        end
    end
end

function YBar:OnModuleEnter(frame)
    if not frame then return end
    self:ApplyBarItemHover(frame)
    if not frame.module then return end
    local name = frame.module.name
    local mode = self:GetModuleDisplayMode(name)
    
    if mode == "ALWAYS" then return end
    
    if mode == "MOUSEOVER" then
        -- Cancel hide timer
        if self.displayTimers[name] then
            self.displayTimers[name]:Cancel()
            self.displayTimers[name] = nil
        end
        -- Fade In
        UIFrameFadeIn(frame, 0.2, frame:GetAlpha(), 1)
    elseif string.find(mode, "GROUP") then
        -- Group Mode
        local groupName = mode
        -- Cancel group timer
        if self.displayTimers[groupName] then
            self.displayTimers[groupName]:Cancel()
            self.displayTimers[groupName] = nil
        end
        
        -- Show all modules in this group
        for mName, module in pairs(self.RegisteredModules) do
            local mMode = self:GetModuleDisplayMode(mName)
            if mMode == groupName and module.frame then
                UIFrameFadeIn(module.frame, 0.2, module.frame:GetAlpha(), 1)
            end
        end
    end
end

function YBar:OnModuleLeave(frame)
    if not frame then return end
    self:RestoreBarItemHover(frame)
    if not frame.module then return end
    local name = frame.module.name
    local mode = self:GetModuleDisplayMode(name)
    
    if mode == "ALWAYS" then return end
    
    if mode == "MOUSEOVER" then
        -- Start hide timer
        if self.displayTimers[name] then self.displayTimers[name]:Cancel() end
        self.displayTimers[name] = C_Timer.NewTimer(0.5, function()
            -- Double check if mouse is still over (e.g. over a child frame)
            if frame:IsMouseOver() then
                self.displayTimers[name] = nil
                return
            end
            UIFrameFadeOut(frame, 0.5, frame:GetAlpha(), 0)
            self.displayTimers[name] = nil
        end)
    elseif string.find(mode, "GROUP") then
        -- Group Mode
        local groupName = mode
        -- Start group hide timer
        -- Check if mouse is over any other module in the group?
        -- Actually, we can just start the timer. If mouse enters another module in the group, 
        -- OnModuleEnter will cancel this timer.
        
        if self.displayTimers[groupName] then self.displayTimers[groupName]:Cancel() end
        self.displayTimers[groupName] = C_Timer.NewTimer(0.5, function()
            -- Double check: if any module in the group is still hovered, cancel hide
            for mName, module in pairs(self.RegisteredModules) do
                local mMode = self:GetModuleDisplayMode(mName)
                if mMode == groupName and module.frame and module.frame:IsMouseOver() then
                    self.displayTimers[groupName] = nil
                    return
                end
            end
            
            -- Fade out all modules in this group
            for mName, module in pairs(self.RegisteredModules) do
                local mMode = self:GetModuleDisplayMode(mName)
                if mMode == groupName and module.frame then
                    UIFrameFadeOut(module.frame, 0.5, module.frame:GetAlpha(), 0)
                end
            end
            self.displayTimers[groupName] = nil
        end)
    end
end

function YBar:CreateBar()
    if self.frame then return end

    local container = GUI2:CreateFrame(UIParent, { name = "YUI_OrbitInfoBar_Container" })
    container:SetAllPoints()
    container:SetFrameStrata("MEDIUM")
    -- Container passes clicks through
    container:EnableMouse(false)
    
    self.frame = container
    
    -- Top Bar
    self.topFrame = GUI2:CreateFrame(container, { name = "YUI_OrbitInfoBar_Top" })
    self.topFrame:SetPoint("TOPLEFT", 0, 0)
    self.topFrame:SetPoint("TOPRIGHT", 0, 0)
    
    local bgTop = GUI2:CreateTexture(self.topFrame, { layer = "BACKGROUND" })
    bgTop:SetAllPoints()
    self.topFrame.bg = bgTop
    
    -- Bottom Bar
    self.bottomFrame = GUI2:CreateFrame(container, { name = "YUI_OrbitInfoBar_Bottom" })
    self.bottomFrame:SetPoint("BOTTOMLEFT", 0, 0)
    self.bottomFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    
    local bgBottom = GUI2:CreateTexture(self.bottomFrame, { layer = "BACKGROUND" })
    bgBottom:SetAllPoints()
    self.bottomFrame.bg = bgBottom
    
    self:UpdateAppearance()
end

function YBar:LoadModules()
    -- 初始化所有已注册的模块
    for name, module in pairs(self.RegisteredModules) do
        if module.OnInitialize and not module._ybarInitialized then
            local traceRecord
            if YUI.Trace and YUI.Trace.Begin then
                traceRecord = YUI.Trace:Begin("Products", "YBar module:" .. tostring(name), "OnInitialize", {
                    moduleId = "ybar." .. tostring(name):lower(),
                    phase = "OnInitialize",
                    durationKind = "sync",
                    blocking = true,
                })
            end
            local ok, err = pcall(module.OnInitialize, module)
            if traceRecord and YUI.Trace and YUI.Trace.Finish then
                YUI.Trace:Finish(traceRecord, ok and "ok" or "error", ok and nil or err)
            end
            if ok then
                module._ybarInitialized = true
            elseif geterrorhandler then
                local handler = geterrorhandler()
                if type(handler) == "function" then
                    handler("YBar module init error [" .. tostring(name) .. "]: " .. tostring(err))
                end
            end
        end
    end
    
    self:UpdateLayout()
end

function YBar:UpdateLayout()
    -- YUI:Debug("!! " .. GetTime() .. " YBar UpdateLayout")
    if self.layoutPending then return end
    self.layoutPending = true
    -- 延迟 0.05 秒执行，合并短时间内的多次调用
    C_Timer.After(0.05, function()
        self.layoutPending = false
        self:UpdateLayoutImmediate()
    end)
end

function YBar:UpdateLayoutImmediate()
    if not self.frame then return end
    
    -- 战斗保护：战斗中不更新布局
    if SecurityAPI.InCombatLockdown() then
        self.layoutPendingInCombat = true
        -- 注册事件在战斗结束后更新
        if not self.combatEventReg then
            self.combatEventReg = YUI.Event:Once("PLAYER_REGEN_ENABLED", function()
                if self.layoutPendingInCombat then
                    self.layoutPendingInCombat = false
                    self:UpdateLayout()
                end
                self.combatEventReg = false
            end)
        end
        return
    end
    
    -- 先隐藏所有模块框架，防止出现残留
    for name, module in pairs(self.RegisteredModules) do
        if module.frame then
            module.frame:Hide()
            module.frame:ClearAllPoints()
        end
    end
    
    -- 清理旧的文本对象
    if self.ModuleTexts then
        for _, text in ipairs(self.ModuleTexts) do
            text:Hide()
        end
    end
    self.ModuleTexts = {}
    
    self:RenderRow("top", self.topFrame)
    self:RenderRow("bottom", self.bottomFrame)

    self:SyncModuleLifecycles()

    -- Notify modules of layout change
    for name, module in pairs(self.RegisteredModules) do
        if module.Update and self:ShouldUpdateModule(name, module) then
            module:Update()
        end
    end
    
    self:UpdateDisplayModes()

    if YUI.Module and YUI.Module.NotifyLayoutChanged then
        YUI.Module:NotifyLayoutChanged("ybar", "layout")
    end
end

local function CreateErrorPlaceholder(parent, name)
    local frame = GUI2:CreateFrame(parent)
    frame:SetSize(100, 20)
    frame.ybarErrorPlaceholder = true
    local text = GUI2:CreateText(frame, "", "font.size.md", "color.state.error")
    text:SetPoint("CENTER")
    text:SetText(name .. " Error")
    frame.errorText = text
    return frame
end

local function TurnFrameIntoErrorState(frame, name)
    if not frame then return end
    frame.ybarErrorPlaceholder = true
    frame:SetSize(100, 20)
    -- Hide all child regions
    for _, region in ipairs({frame:GetRegions()}) do
        region:Hide()
    end
    for _, child in ipairs({frame:GetChildren()}) do
        child:Hide()
    end
    -- Create or show error text
    if not frame.errorText then
        local text = GUI2:CreateText(frame, "", "font.size.md", "color.state.error")
        text:SetPoint("CENTER")
        frame.errorText = text
    end
    frame.errorText:SetText(name .. " Error")
    frame.errorText:Show()
    frame:Show()
end

local function MarkModuleErrored(module, frame, name)
    if not module then return end

    module._hasError = true
    if frame then
        frame.ybarErrorPlaceholder = true
    end

    if module.DetachRuntime and not module._ybarErrorRuntimeDetached then
        module._ybarErrorRuntimeDetached = true
        xpcall(function()
            module:DetachRuntime()
        end, geterrorhandler())
    end
end

function YBar:RenderRow(listName, barFrame)
    -- print("RenderRow", listName, barFrame)

    local list = self.db.modules[listName]
    if not list then return end
    
    local centerIdx = self.db.center[listName]
    
    -- Filter active modules and find the active index of the center module
    local activeModules = {}
    local activeCenterIdx = nil
    
    for i, name in ipairs(list) do
        if name ~= "None" then
            local module = self.RegisteredModules[name]
            local renderable = true
            if module and type(module.IsBarItemRenderable) == "function" then
                local ok, result = pcall(module.IsBarItemRenderable, module)
                if ok then
                    renderable = result ~= false
                end
            end
            if renderable then
                table.insert(activeModules, name)
                if i == centerIdx then
                    activeCenterIdx = #activeModules
                end
            elseif module and module.frame then
                module.frame:Hide()
            end
        end
    end
    
    -- Keep track of created frames to use as anchors
    local frames = {}
    
    -- 1. Prepare frames
    local hasActiveModule = false
    for i, name in ipairs(activeModules) do
        local module = self.RegisteredModules[name]
        if module then
            hasActiveModule = true
            local frame = module.frame
            
            -- Reuse existing frame or create new one
            if not frame then
                if module.CreateBarItem then
                    -- YUI:Debug("RenderRow:CreateBarItem", name)
                    local success, result = xpcall(function()
                        return module:CreateBarItem(barFrame)
                    end, geterrorhandler())
                    
                    if success then
                        frame = result
                    else
                        frame = CreateErrorPlaceholder(barFrame, name)
                        module.frame = frame
                        MarkModuleErrored(module, frame, name)
                    end
                    module.frame = frame
                else
                    -- Fallback: Create placeholder
                    frame = CreateErrorPlaceholder(barFrame, name)
                    module.frame = frame
                end
            end
            
            -- Ensure frame is visible and parented correctly
            if frame then
                -- YUI:Debug("RenderRow:Show", name)
                frame:SetParent(barFrame)
                frame:Show()
                frame:ClearAllPoints()
                
                -- Store module reference on frame for width calculation if needed
                frame.module = module
                
                -- Update Module Content
                if module.UpdateBarItem and not module._hasError then
                    local success = xpcall(function()
                        module:UpdateBarItem(frame, barFrame)
                    end, geterrorhandler())
                    
                    if not success then
                        MarkModuleErrored(module, frame, name)
                        TurnFrameIntoErrorState(frame, name)
                    end
                end
                
                frames[i] = frame
            end
        else
            frames[i] = nil -- Placeholder for missing module
        end
    end
    
    if not hasActiveModule then
        barFrame:Hide()
        return
    else
        barFrame:Show()
    end
    
    -- 2. Position frames
    for i, name in ipairs(activeModules) do
        local frame = frames[i]
        if frame then
            local width = frame:GetWidth()
            local module = frame.module
            
            if module and module.GetWidth and not module._hasError then
                 local success, w = xpcall(function()
                     return module:GetWidth()
                 end, geterrorhandler())
                 
                 if success and w then
                     frame:SetWidth(w)
                     width = w
                 elseif not success then
                     MarkModuleErrored(module, frame, name)
                     TurnFrameIntoErrorState(frame, name)
                     width = frame:GetWidth() -- fallback to 100
                 end
            end
            
            if i == activeCenterIdx then
                frame:SetPoint("CENTER", barFrame, "CENTER", 0, 0)
            else
                local settings = self.db.items[name] or {}
                local align = settings.align or "LEFT"
                local margin = settings.margin or 2
                
                if align == "LEFT" then
                    local prevName = activeModules[i-1]
                    local prevAlign = "LEFT"
                    if prevName then
                         local prevSettings = self.db.items[prevName] or {}
                         prevAlign = prevSettings.align or "LEFT"
                    end
                    
                    local isPrevCenter = (activeCenterIdx and i-1 == activeCenterIdx)
                    
                    if i > 1 and not isPrevCenter and prevAlign == "RIGHT" then
                        -- 循环引用：上一模块锚点指向我，而我锚点指向上一模块，强制锚定到中心
                        frame:SetPoint("LEFT", barFrame, "CENTER", margin, 0)
                    elseif i == 1 then
                        frame:SetPoint("LEFT", barFrame, "LEFT", margin, 0)
                    else
                        local prevFrame = frames[i-1]
                        if prevFrame then
                            frame:SetPoint("LEFT", prevFrame, "RIGHT", margin, 0)
                        else
                            frame:SetPoint("LEFT", barFrame, "LEFT", margin, 0)
                        end
                    end
                else -- align == "RIGHT"
                    local nextName = activeModules[i+1]
                    local nextAlign = "LEFT"
                    if nextName then
                         local nextSettings = self.db.items[nextName] or {}
                         nextAlign = nextSettings.align or "LEFT"
                    end
                    
                    local isNextCenter = (activeCenterIdx and i+1 == activeCenterIdx)

                    if i < #activeModules and not isNextCenter and nextAlign == "LEFT" then
                        -- 循环引用：下一模块锚点指向我，而我锚点指向下一模块，强制锚定到中心
                        frame:SetPoint("RIGHT", barFrame, "CENTER", -margin, 0)
                    elseif i == #activeModules then
                        frame:SetPoint("RIGHT", barFrame, "RIGHT", -margin, 0)
                    else
                        local nextFrame = frames[i+1]
                        if nextFrame then
                            frame:SetPoint("RIGHT", nextFrame, "LEFT", -margin, 0)
                        else
                            frame:SetPoint("RIGHT", barFrame, "RIGHT", -margin, 0)
                        end
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Action Host API
-------------------------------------------------------------------------------
local ACTION_HOST_NOOP = ATTRIBUTE_NOOP or ""
local ACTION_HOST_SECURE_KINDS = {
    macro = true,
    spell = true,
    item = true,
    toy = true,
    raidtarget = true,
    worldmarker = true,
    returnhome = true,
    teleporthome = true,
    click = true,
    secure = true,
}

local ACTION_HOST_ATTRS = {
    "type",
    "macrotext",
    "spell",
    "item",
    "toy",
    "marker",
    "action",
    "clickbutton",
    "unit",
    "target",
    "house-neighborhood-guid",
    "house-guid",
    "house-plot-id",
}

local ACTION_HOST_KEYS = {
    left = { suffix = "1", button = "LeftButton" },
    right = { suffix = "2", button = "RightButton" },
    middle = { suffix = "3", button = "MiddleButton" },
    altLeft = { prefix = "alt-", suffix = "1", button = "LeftButton", modifier = "alt" },
    altRight = { prefix = "alt-", suffix = "2", button = "RightButton", modifier = "alt" },
    shiftLeft = { prefix = "shift-", suffix = "1", button = "LeftButton", modifier = "shift" },
    shiftRight = { prefix = "shift-", suffix = "2", button = "RightButton", modifier = "shift" },
    ctrlLeft = { prefix = "ctrl-", suffix = "1", button = "LeftButton", modifier = "ctrl" },
    ctrlRight = { prefix = "ctrl-", suffix = "2", button = "RightButton", modifier = "ctrl" },
}

local ACTION_HOST_KEY_ORDER = {
    "left", "right", "middle",
    "altLeft", "altRight",
    "shiftLeft", "shiftRight",
    "ctrlLeft", "ctrlRight",
}

local function ActionHostInCombat()
    if SecurityAPI and SecurityAPI.InCombatLockdown then
        return SecurityAPI.InCombatLockdown() and true or false
    end
    if InCombatLockdown then
        return InCombatLockdown() and true or false
    end
    return false
end

local function ActionHostIsAltDown()
    return IsAltKeyDown and IsAltKeyDown()
end

local function ActionHostIsShiftDown()
    return IsShiftKeyDown and IsShiftKeyDown()
end

local function ActionHostIsCtrlDown()
    return IsControlKeyDown and IsControlKeyDown()
end

local function ActionHostGetClickKey(actions, button)
    if button == "LeftButton" then
        if ActionHostIsAltDown() and actions and actions.altLeft then return "altLeft" end
        if ActionHostIsShiftDown() and actions and actions.shiftLeft then return "shiftLeft" end
        if ActionHostIsCtrlDown() and actions and actions.ctrlLeft then return "ctrlLeft" end
        return "left"
    elseif button == "RightButton" then
        if ActionHostIsAltDown() and actions and actions.altRight then return "altRight" end
        if ActionHostIsShiftDown() and actions and actions.shiftRight then return "shiftRight" end
        if ActionHostIsCtrlDown() and actions and actions.ctrlRight then return "ctrlRight" end
        return "right"
    elseif button == "MiddleButton" then
        return "middle"
    end
    return nil
end

function YBar:IsSecureActionHostAction(action)
    return type(action) == "table" and ACTION_HOST_SECURE_KINDS[action.kind] == true
end

function YBar:CreateActionHost(owner, opts)
    if not owner then return nil end
    opts = opts or {}

    if not GUI2 or not GUI2.Secure or not GUI2.Secure.CreateActionHost then
        return nil, "GUI2 Secure action host unavailable"
    end

    local host, err = GUI2.Secure:CreateActionHost(owner, {
        secure = opts.secure,
        insecureAction = opts.insecureAction,
        clicks = opts.clicks,
        useOnKeyDown = opts.useOnKeyDown,
        frameLevelOffset = opts.frameLevelOffset,
        afterClick = opts.afterClick,
        onEnter = opts.onEnter,
        onLeave = opts.onLeave,
        actionKeys = ACTION_HOST_KEYS,
        actionKeyOrder = ACTION_HOST_KEY_ORDER,
        actionAttrs = ACTION_HOST_ATTRS,
        secureKinds = ACTION_HOST_SECURE_KINDS,
        noopValue = ACTION_HOST_NOOP,
        inCombat = ActionHostInCombat,
        getClickKey = ActionHostGetClickKey,
    })

    if host then
        host.ybarAfterClick = opts.afterClick
        host.ybarOnEnter = opts.onEnter
        host.ybarOnLeave = opts.onLeave
        host.ybarSecureHost = opts.secure ~= false and not opts.insecureAction
        host.ybarUseOnKeyDown = opts.useOnKeyDown
        owner.actionHost = host
    end

    return host, err
end

function YBar:BindButtonActions(owner, actions, opts)
    if not owner then return nil end
    opts = opts or {}

    local function ForwardOwnerScript(scriptName)
        return function(_, buttonOwner)
            local target = buttonOwner or owner
            local script = target and target.GetScript and target:GetScript(scriptName)
            if script then script(target) end
        end
    end

    local host = owner.actionHost
    if not host then
        host = self:CreateActionHost(owner, {
            clicks = opts.clicks,
            secure = opts.secure,
            useOnKeyDown = opts.useOnKeyDown,
            frameLevelOffset = opts.frameLevelOffset,
            afterClick = opts.afterClick,
            onEnter = opts.onEnter or ForwardOwnerScript("OnEnter"),
            onLeave = opts.onLeave or ForwardOwnerScript("OnLeave"),
        })
    else
        host.ybarAfterClick = opts.afterClick or host.ybarAfterClick
        host.ybarOnEnter = opts.onEnter or host.ybarOnEnter or ForwardOwnerScript("OnEnter")
        host.ybarOnLeave = opts.onLeave or host.ybarOnLeave or ForwardOwnerScript("OnLeave")
        if host.SetActionHostFrameLevel then
            host:SetActionHostFrameLevel()
        end
    end

    if not host then return nil end

    local ok, err = host:SetActions(actions or {})
    if not ok then return nil, err end
    owner.actionHost = host
    return host
end

-------------------------------------------------------------------------------
-- PopIconMenu API
-------------------------------------------------------------------------------
--[[
    创建一个带有图标网格的弹出菜单。
    
    @param anchor (Frame) - 菜单的锚点（通常是点击的按钮）。
    @param data (Table) - 要显示的条目列表。
        Item structure:
        {
            icon = "Interface\\Icons\\...", -- 纹理路径
            text = "Optional Text",         -- 图标旁边/下方的文本（可选）
            onClick = function(btn) ... end, -- 点击处理函数
            tooltip = { title = "Title", lines = {"Line1", "Line2"} } -- 可选的提示信息
        }
    @param options (Table) - 可选配置。
        {
            columns = 1,        -- 列数（默认 1）
            fontSize = 12,      -- 字体大小（默认 12）
            iconSize = 24,      -- 图标大小（默认 24）
            colWidth = 140,     -- 菜单宽度（默认自动计算或固定）
            itemHeight = 24,    -- 每行高度（默认 24）
        }
]]
local function GetPopIconMenuAction(itemData)
    if itemData.action then
        return itemData.action
    end
    if itemData.onClick then
        return {
            kind = "custom",
            onClick = function(_, _, owner)
                itemData.onClick(owner)
            end,
        }
    end
    if itemData.secure or itemData.type1 or itemData.macrotext1 or itemData.spell1 or itemData.item1 then
        local kind = itemData.type1
        if not kind and itemData.macrotext1 then
            kind = "macro"
        elseif not kind and itemData.spell1 then
            kind = "spell"
        elseif not kind and itemData.item1 then
            kind = "item"
        end

        if kind == "macro" then
            return { kind = "macro", macrotext = itemData.macrotext1 }
        elseif kind == "spell" then
            return { kind = "spell", spell = itemData.spell1 }
        elseif kind == "item" then
            return { kind = "item", item = itemData.item1 }
        end
    end
    return nil
end

local function RefreshGUI2PopIconMenuText(text, fallbackColorKey)
    if not text or not GUI2 then return end
    local size = text.gui2FontSize or 12
    text:SetFont(GUI2:GetFont("font.family.body"), size, "")
    text:SetTextColor(GUI2:GetColor(text.gui2ColorKey or fallbackColorKey or "color.text.primary"))
end

local function ApplyGUI2PopIconMenuButtonState(button, state)
    if not button or not GUI2 then return end

    local surface = "color.surface.popup"
    local border = "color.border.subtle"
    if state == "hover" then
        surface = "color.control.hover"
        border = "color.border.accent"
    end

    if button.SetBackdropColor then
        button:SetBackdropColor(GUI2:GetColor(surface))
    end
    button.gui2Surface = surface
    if GUI2.SetBorderColor then
        GUI2:SetBorderColor(button, border)
    end
end

function YBar:RefreshGUI2PopIconMenus()
    local menu = self.GUI2PopIconMenu
    if not menu or not GUI2 then return end

    if GUI2.RefreshPrimitive then
        GUI2:RefreshPrimitive(menu)
    end
    if menu.buttons then
        for _, button in ipairs(menu.buttons) do
            if button:IsShown() then
                local hoverTarget = button.actionHost or button
                local isHover = hoverTarget.IsMouseOver and hoverTarget:IsMouseOver()
                ApplyGUI2PopIconMenuButtonState(button, isHover and "hover" or "normal")
                if button.iconSlot and button.iconSlot.SetState then
                    button.iconSlot:SetState(button.iconSlot.gui2State or "normal")
                end
                RefreshGUI2PopIconMenuText(button.text, "color.text.primary")
                RefreshGUI2PopIconMenuText(button.rText, "color.text.secondary")
            end
        end
    end
end

function YBar:CreateGUI2PopIconMenu(anchor, data, options)
    local app = GUI2 and GUI2.Application
    if not app or not app.CreateIconSlot then return false end

    if self.PopIconMenu then
        self.PopIconMenu:Hide()
    end

    if not self.GUI2PopIconMenu then
        local menu = GUI2:CreatePanel(UIParent, {
            name = "YBarGUI2PopIconMenu",
            width = 140,
            height = 40,
            surface = "color.surface.popup",
            border = "color.popup.border",
            nativeFrameBorder = true,
            nativeFrameBorderStyle = "tooltip",
            shadow = true,
            shadowKey = "shadow.popup.size",
        })
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetClampedToScreen(true)
        menu.buttons = {}

        local closer = GUI2:CreateButtonFrame(menu)
        closer:SetFrameStrata("FULLSCREEN_DIALOG")
        local menuLevel = menu:GetFrameLevel()
        closer:SetFrameLevel(menuLevel > 0 and (menuLevel - 1) or menuLevel)
        closer:SetAllPoints(UIParent)
        closer:RegisterForClicks("AnyUp")
        closer:SetScript("OnClick", function()
            menu:Hide()
        end)
        menu.closer = closer

        menu:SetScript("OnHide", function(self)
            if self.closer then
                self.closer:Hide()
            end
            YUI.HideGameTooltip()
        end)

        self.GUI2PopIconMenu = menu
    end

    local menu = self.GUI2PopIconMenu
    menu:Hide()

    local columns = options.columns or 1
    local iconSize = options.iconSize or 20
    local fontSize = options.fontSize or 12
    local itemHeight = options.itemHeight or 24
    local spacing = 5
    local padding = 8
    local numItems = #data
    local numRows = math.ceil(numItems / columns)
    local colWidth = options.colWidth or 140
    local menuWidth = (colWidth * columns) + (padding * 2) + (spacing * (columns - 1))
    local menuHeight = (itemHeight * numRows) + (padding * 2) + (spacing * (numRows - 1))

    menu:SetSize(menuWidth, menuHeight)

    for i, itemData in ipairs(data) do
        local button = menu.buttons[i]
        if not button then
            button = GUI2:CreateFrame(menu, { template = "BackdropTemplate" })
            GUI2:ApplyBackdrop(button, "color.surface.popup")
            GUI2:CreateBorder(button, "color.border.subtle")
            button.gui2Surface = "color.surface.popup"

            button.iconSlot, button.icon = self:CreateIconSlot(button, {
                size = iconSize,
                variant = options.iconVariant or "surface",
                shape = options.iconShape or "square",
                padding = options.iconPadding == nil and 2 or options.iconPadding,
            })
            if button.iconSlot then
                button.iconSlot:EnableMouse(false)
            end

            button.text = GUI2:CreateText(button, "", "font.size.sm", "color.text.primary", "LEFT")
            button.text:SetWordWrap(false)
            button.text.gui2ColorKey = "color.text.primary"
            button.rText = GUI2:CreateText(button, "", "font.size.sm", "color.text.secondary", "RIGHT")
            button.rText:SetWordWrap(false)
            button.rText.gui2ColorKey = "color.text.secondary"

            local host = self:CreateActionHost(button, {
                onEnter = function(actionHost, owner)
                    ApplyGUI2PopIconMenuButtonState(owner, "hover")
                    if owner.tooltip then
                        GameTooltip:SetOwner(actionHost, "ANCHOR_RIGHT")
                        if owner.tooltip.title then
                            GameTooltip:AddLine(owner.tooltip.title, 1, 1, 1)
                        end
                        if owner.tooltip.lines then
                            for _, line in ipairs(owner.tooltip.lines) do
                                GameTooltip:AddLine(line, 1, 0.82, 0)
                            end
                        end
                        GameTooltip:Show()
                    end
                end,
                onLeave = function(_, owner)
                    ApplyGUI2PopIconMenuButtonState(owner, "normal")
                    YUI.HideGameTooltip()
                end,
                afterClick = function()
                    menu:Hide()
                end,
            })
            if not host then
                return false
            end
            button.actionHost = host

            menu.buttons[i] = button
        end

        button:SetSize(colWidth, itemHeight)
        button.tooltip = itemData.tooltip
        button.text.gui2FontSize = fontSize
        button.rText.gui2FontSize = fontSize
        RefreshGUI2PopIconMenuText(button.text, "color.text.primary")
        RefreshGUI2PopIconMenuText(button.rText, "color.text.secondary")
        button.text:SetText(itemData.text or "")
        button.rText:SetText(itemData.rText or "")

        button.rText:ClearAllPoints()
        button.rText:SetPoint("RIGHT", button, "RIGHT", -4, 0)

        if (itemData.iconData or itemData.icon) and iconSize > 0 then
            if button.iconSlot then
                button.iconSlot:SetSize(iconSize, iconSize)
                button.iconSlot:ClearAllPoints()
                button.iconSlot:SetPoint("LEFT", button, "LEFT", 2, 0)
                button.iconSlot:Show()
                if itemData.iconData then
                    self:SetIconSlotIcon(button.iconSlot, itemData.iconData, itemData.icon)
                else
                    self:SetIconSlotTexture(button.iconSlot, itemData.icon, itemData.atlas, itemData.texCoord)
                end
            end
            button.text:ClearAllPoints()
            if button.iconSlot then
                button.text:SetPoint("LEFT", button.iconSlot, "RIGHT", 5, 0)
            else
                button.text:SetPoint("LEFT", button, "LEFT", 4, 0)
            end
        else
            if button.iconSlot then
                button.iconSlot:Hide()
            end
            button.text:ClearAllPoints()
            button.text:SetPoint("LEFT", button, "LEFT", 4, 0)
        end

        if itemData.rText and itemData.rText ~= "" then
            button.rText:Show()
            button.text:SetPoint("RIGHT", button.rText, "LEFT", -4, 0)
        else
            button.rText:Hide()
            button.text:SetPoint("RIGHT", button, "RIGHT", -4, 0)
        end

        ApplyGUI2PopIconMenuButtonState(button, "normal")
        if button.actionHost then
            button.actionHost:SetAllPoints(button)
            button.actionHost:SetActionHostFrameLevel()
            local action = GetPopIconMenuAction(itemData)
            local ok = button.actionHost:SetActions({ left = action or { kind = "noop" } })
            if not ok then
                return false
            end
        else
            return false
        end

        local row = math.ceil(i / columns) - 1
        local col = (i - 1) % columns
        local x = padding + (col * (colWidth + spacing))
        local y = -(padding + (row * (itemHeight + spacing)))

        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", menu, "TOPLEFT", x, y)
        button:Show()
    end

    for i = numItems + 1, #menu.buttons do
        menu.buttons[i]:Hide()
    end

    menu:ClearAllPoints()
    local _, anchorY = anchor:GetCenter()
    local _, screenHeight = UIParent:GetSize()
    if not anchorY then anchorY = 0 end

    if anchorY < (screenHeight / 2) then
        menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
    else
        menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    end

    if menu.closer then
        menu.closer:Show()
    end
    menu:Show()
    return true
end

function YBar:CreatePopIconMenu(anchor, data, options)
    if not data or #data == 0 then return end
    options = options or {}
    
    local GUI2 = YUI.GUI2

    if SecurityAPI.InCombatLockdown() then
        local coreLocale = YUI.Locale and YUI.Locale:Get("Core") or {}
        YUI:Print(coreLocale["common.combat_unavailable"] or "战斗中不可用")
        return
    end

    if options.gui2 and self:CreateGUI2PopIconMenu(anchor, data, options) then
        return
    end

    if self.GUI2PopIconMenu then
        self.GUI2PopIconMenu:Hide()
    end
    
    -- 1. Create or Reuse Menu Frame
    if not self.PopIconMenu then
        local menu = GUI2:CreateFrame(UIParent, { name = "YBarPopIconMenu", template = "BackdropTemplate" })
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetClampedToScreen(true)
        
        -- Style
        GUI2:CreateBackdrop(menu, {
            surface = "color.surface.popup",
            border = "color.popup.border",
            shadow = false,
            nativeFrameBorder = true,
            nativeFrameBorderStyle = "tooltip",
        })
        GUI2:CreateShadow(menu)
        
        -- Closer (Full screen invisible button)
        local closer = GUI2:CreateButtonFrame(menu)
        closer:SetFrameStrata("FULLSCREEN_DIALOG")
        closer:SetFrameLevel(menu:GetFrameLevel() - 1)
        closer:SetAllPoints(UIParent)
        closer:RegisterForClicks("AnyUp")
        closer:SetScript("OnClick", function()
            menu:Hide()
        end)
        menu.closer = closer
        
        menu.buttons = {}
        self.PopIconMenu = menu
    end
    
    local menu = self.PopIconMenu
    menu:Hide() -- Hide first to reset
    
    -- 2. Configuration
    local columns = options.columns or 1
    local iconSize = options.iconSize or 20
    local fontSize = options.fontSize or 12
    local itemHeight = options.itemHeight or 24
    local spacing = 5
    local padding = 8
    
    -- 3. Create/Update Buttons
    local numItems = #data
    local numRows = math.ceil(numItems / columns)
    
    -- Calculate dimensions
    -- Assuming equal width for columns if width is provided, else dynamic?
    -- For simplicity, let's use fixed column width based on options.width or auto.
    -- If text is present, we need more width.
    
    local colWidth = options.colWidth or 140
    local menuWidth = (colWidth * columns) + (padding * 2) + (spacing * (columns - 1))
    local menuHeight = (itemHeight * numRows) + (padding * 2) + (spacing * (numRows - 1))
        
    menu:SetSize(menuWidth, menuHeight)
    
    -- 4. Populate
    for i, itemData in ipairs(data) do
        local btn = menu.buttons[i]
        if not btn then
            -- PopIconMenu secure menu item buttons must stay on native CreateFrame.
            btn = CreateFrame("Button", nil, menu, "SecureActionButtonTemplate")
            GUI2.Secure:RegisterActionClicks(btn)
            
            -- Icon
            btn.icon = GUI2:CreateTexture(btn, { layer = "ARTWORK" })
            btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn.icon:SetPoint("LEFT", 0, 0) -- Set default point for anchoring
            
            -- Icon Border
            local iconBg = GUI2:CreateFrame(btn, { template = "BackdropTemplate" })
            iconBg:SetAllPoints(btn.icon)
            iconBg:SetFrameLevel(btn:GetFrameLevel())
            GUI2:CreateBorder(iconBg)
            btn.iconBg = iconBg
            
            -- Text
            btn.text = GUI2:CreateText(btn, "", fontSize, "LEFT")
            btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 5, 0)
            btn.text:SetPoint("RIGHT", btn, "RIGHT", -2, 0)

            -- Right Text
            btn.rText = GUI2:CreateText(btn, "", fontSize, "RIGHT")
            btn.rText:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
            
            -- Highlight
            local hl = GUI2:CreateTexture(btn, { layer = "HIGHLIGHT" })
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.1)
            
            btn:SetScript("OnEnter", function(self)
                if self.tooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if self.tooltip.title then
                        GameTooltip:AddLine(self.tooltip.title, 1, 1, 1)
                    end
                    if self.tooltip.lines then
                        for _, line in ipairs(self.tooltip.lines) do
                            GameTooltip:AddLine(line, 1, 0.82, 0)
                        end
                    end
                    GameTooltip:Show()
                end
            end)
            
            btn:SetScript("OnLeave", function(self)
                YUI.HideGameTooltip()
            end)
            
            btn:SetScript("PostClick", function(self, _, down)
                if not GUI2.Secure:ShouldRunActionClick(down) then return end
                if self.onClick then
                    self.onClick(self)
                end
                menu:Hide()
            end)
            
            menu.buttons[i] = btn
        end
        
        -- Update Button Content
        btn:SetSize(colWidth, itemHeight)

        if itemData.iconData or itemData.icon then
            btn.icon:SetSize(iconSize, iconSize)
            btn.icon:SetPoint("LEFT", 0, 0)        
            if itemData.iconData and YUI.API and YUI.API.Icons and YUI.API.Icons.ApplyIcon then
                YUI.API.Icons.ApplyIcon(btn.icon, itemData.iconData)
                if itemData.iconData.kind == "spec" and itemData.iconData.custom ~= true and not itemData.iconData.atlas then
                    btn.icon:SetTexCoord(unpack(YBAR_NATIVE_ICON_TEXCOORDS))
                end
            else
                btn.icon:SetTexture(itemData.icon)
                if itemData.texCoord then
                    btn.icon:SetTexCoord(unpack(itemData.texCoord))
                else
                    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
            end

             -- position text to icon
            btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 5, 0)
            btn.text:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        else
            btn.icon:SetSize(0, 0)
            btn.icon:SetTexture(nil)
            btn.iconBg:SetSize(0, 0)

            -- position text to left
            btn.text:SetPoint("LEFT", btn, "LEFT", 0, 0)
            btn.text:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
        end

        -- set font size
        local font, _, flags = btn.text:GetFont()
        btn.text:SetFont(font, fontSize, "")
        btn.rText:SetFont(font, fontSize, "")

        -- Set Text
        btn.text:SetText(itemData.text or "")
        btn.rText:SetText(itemData.rText or "")

        local action = GetPopIconMenuAction(itemData)
        for _, attr in ipairs(ACTION_HOST_ATTRS) do
            btn:SetAttribute(attr .. "1", nil)
        end
        if self:IsSecureActionHostAction(action) then
            btn.onClick = nil

            btn:SetAttribute("type1", action.type or action.kind)
            btn:SetAttribute("macrotext1", action.macrotext)
            btn:SetAttribute("spell1", action.spell or action.spellID or action.name)
            btn:SetAttribute("item1", action.item or action.itemID)
            btn:SetAttribute("toy1", action.toy or action.toyID or action.id)
            btn:SetAttribute("marker1", action.marker)
            btn:SetAttribute("action1", action.action)
            if action.attributes or action.attrs then
                for attr, value in pairs(action.attributes or action.attrs) do
                    btn:SetAttribute(attr .. "1", value)
                end
            end
            if action.rawAttributes or action.rawAttrs then
                for attr, value in pairs(action.rawAttributes or action.rawAttrs) do
                    btn:SetAttribute(attr, value)
                end
            end
        else
            if action and action.kind == "custom" then
                btn.onClick = function(self)
                    action.onClick(self, "LeftButton", self, action)
                end
            else
                btn.onClick = nil
            end
        end

        btn.tooltip = itemData.tooltip
        
        -- Position
        local row = math.ceil(i / columns) - 1
        local col = (i - 1) % columns
        
        local x = padding + (col * (colWidth + spacing))
        local y = -(padding + (row * (itemHeight + spacing)))
        
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", menu, "TOPLEFT", x, y)
        btn:Show()
    end
    
    -- Hide unused buttons
    for i = numItems + 1, #menu.buttons do
        menu.buttons[i]:Hide()
    end
    
    -- 5. Anchor Menu
    menu:ClearAllPoints()
    
    local anchorX, anchorY = anchor:GetCenter()
    local screenWidth, screenHeight = UIParent:GetSize()

    if not anchorY then anchorY = 0 end
    
    -- Decide vertical position (Top or Bottom half of screen)
    if anchorY < (screenHeight / 2) then
        -- Bottom half: Open UP
        menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
    else
        -- Top half: Open DOWN
        menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    end
    
    menu:Show()
end

if YUI.Module and YUI.Module.Register then
    YUI.Module:Register({
        id = "ybar",
        name = "YBar",
        product = "ybar",
        scope = "ybar",
        defaultEnabled = true,
        owner = YBar,
        dependencies = {"core.db", "core.event", "core.api", "gui", "settings"},
        getEnabled = function(owner)
            return owner:IsEnabled()
        end,
        setEnabled = function(owner, enabled)
            owner:SetEnabled(enabled)
        end,
        OnInitialize = "Initialize",
        OnEnable = "OnLifecycleEnable",
        OnDisable = "OnLifecycleDisable",
        OnProfileChanged = "OnLifecycleProfileChanged",
    })
else
    YUI.Event:Once("YUI_LOGIN_READY", function()
        YBar:Initialize()
    end, YBar, {
        priority = 4000,
        traceName = "YBar:Initialize",
        moduleId = "ybar",
        phase = "YUI_LOGIN_READY",
    })
end

if YUI.Event then
    YUI.Event:On("YUI_DB_READY", function()
        YBar:EnsureDB()
    end, YBar, {
        priority = 4000,
        traceName = "YBar:EnsureDB",
        moduleId = "ybar",
        phase = "YUI_DB_READY",
    })
end

if YUI.Components and YUI.Components.Register then
    YUI.Components:Register({
        id = "ybar",
        kind = "product",
        displayName = YBarLocale["product.short_title"] or "Orbit InfoBar",
        description = YBarLocale["product.notes"] or "Orbit InfoBar · YanForge",
        tags = { "实用功能" },
        settingsMode = "external",
        standalone = true,
        order = 900,
        storageKey = "YBar",
        sourceRoot = "Products\\YBar",
        mediaBundles = { "sharedmedia-statusbars" },
        assetFolders = { "Products\\YBar\\Media" },
        getEnabled = function()
            if YUI.Module and YUI.Module.IsEnabled then
                return YUI.Module:IsEnabled("ybar")
            end
            return YBar:IsEnabled()
        end,
        setEnabled = function(_, enabled)
            if YUI.Module and YUI.Module.SetEnabled then
                return YUI.Module:SetEnabled("ybar", enabled)
            end
            YBar:SetEnabled(enabled)
            return true
        end,
        openSettings = function()
            if YUI.Settings and YUI.Settings.OpenProduct then
                YUI.Settings:OpenProduct("ybar", "ybar.settings")
            elseif YUI.OpenSettings then
                YUI:OpenSettings(YBarLocale["product.short_title"] or "Orbit InfoBar", "ybar")
            end
        end,
    })
end
