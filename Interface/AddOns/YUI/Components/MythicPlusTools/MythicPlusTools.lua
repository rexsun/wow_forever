local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI or not YUI.IsRetail then return end

local Components = YUI.Components
if not Components or not Components.RegisterFeature then return end

local FEATURE_KEY = "MythicPlusTools"
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or YUI.ProductId or "suite"
local CONFIG_KEY = "MythicPlusTools_Config"
local DEFAULT_SETTINGS_TAB = "battleRes"

local L = YUI.Locale and YUI.Locale:Get("MythicPlusTools") or nil
local Tools = YUI.MythicPlusTools or {}
YUI.MythicPlusTools = Tools

Tools.FEATURE_KEY = FEATURE_KEY
Tools.PRODUCT_ID = PRODUCT_ID
Tools.CONFIG_KEY = CONFIG_KEY
Tools.L = L
Tools.defaults = Tools.defaults or {}
Tools.subFeatures = Tools.subFeatures or {}
Tools.subFeatureOrder = Tools.subFeatureOrder or {}
Tools.featureActive = Tools.featureActive == true

local activeSettingsTab = DEFAULT_SETTINGS_TAB
local Feature

local SETTINGS_TABS = {
    { id = "battleRes", labelKey = "settings.battle_res", fallback = "战复监控" },
    { id = "keystoneTools", labelKey = "settings.keystone_tools", fallback = "钥石工具" },
    { id = "pveEnhancement", labelKey = "settings.pve_enhancement", fallback = "PVE界面扩展" },
    { id = "teleportAnnouncement", labelKey = "settings.teleport_announcement", fallback = "传送喊话" },
}

local function T(key, fallback)
    return (L and L[key]) or fallback or key
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

local function MergeDefaults(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then
        return
    end

    for key, value in pairs(source) do
        if target[key] == nil then
            target[key] = CopyDefaultValue(value)
        elseif type(target[key]) == "table" and type(value) == "table" then
            MergeDefaults(target[key], value)
        end
    end
end

local function SortSubFeatures(a, b)
    local left = Tools.subFeatures[a]
    local right = Tools.subFeatures[b]
    local leftOrder = left and left.order or 1000
    local rightOrder = right and right.order or 1000
    if leftOrder == rightOrder then
        return tostring(a) < tostring(b)
    end
    return leftOrder < rightOrder
end

function Tools:T(key, fallback)
    return T(key, fallback)
end

function Tools:IsEnabled()
    return self.featureActive == true
end

function Tools:GetDB()
    local db
    if Components and Components.EnsureConfig then
        db = Components:EnsureConfig(CONFIG_KEY, self.defaults, PRODUCT_ID)
    end
    if type(db) ~= "table" then
        db = self.defaults
    end

    for _, id in ipairs(self.subFeatureOrder) do
        local subFeature = self.subFeatures[id]
        if subFeature and subFeature.NormalizeDB then
            subFeature:NormalizeDB(db)
        end
    end
    return db
end

function Tools:RegisterSubFeature(subFeature)
    if type(subFeature) ~= "table" or type(subFeature.id) ~= "string" or subFeature.id == "" then
        return false
    end

    local id = subFeature.id
    if not self.subFeatures[id] then
        self.subFeatureOrder[#self.subFeatureOrder + 1] = id
    end
    self.subFeatures[id] = subFeature
    table.sort(self.subFeatureOrder, SortSubFeatures)

    MergeDefaults(self.defaults, subFeature.defaults)

    if self.featureActive and subFeature.OnFeatureToggle then
        subFeature:OnFeatureToggle(true, self:GetDB())
    end
    return true
end

function Tools:RefreshSubFeatures()
    local db = self:GetDB()
    for _, id in ipairs(self.subFeatureOrder) do
        local subFeature = self.subFeatures[id]
        if subFeature and subFeature.RefreshRuntime then
            subFeature:RefreshRuntime(db)
        end
    end
end

local function ToggleMythicPlusTools(enable)
    Tools.featureActive = enable == true
    local db = Tools:GetDB()
    for _, id in ipairs(Tools.subFeatureOrder) do
        local subFeature = Tools.subFeatures[id]
        if subFeature and subFeature.OnFeatureToggle then
            subFeature:OnFeatureToggle(Tools.featureActive, db)
        end
    end
end

local function GetSubFeatureStates()
    local db = Components:CopyConfigSnapshot(CONFIG_KEY, Tools.defaults, PRODUCT_ID)
    if not db then return {} end
    local rows = {}
    local function Add(labelKey, fallback, key)
        rows[#rows + 1] = { label = T(labelKey, fallback), enabled = db[key] == true }
    end
    if Tools.subFeatures.battleRes then Add("settings.battle_res", "战复监控", "battleResEnabled") end
    if Tools.subFeatures.keystoneTools then
        Add("settings.auto_keystone", "自动插钥石", "keystoneAutoInsertEnabled")
        Add("settings.auto_announce_new_keystone", "自动通报新钥石", "keystoneAutoAnnounceEnabled")
    end
    if Tools.subFeatures.pveEnhancement then Add("settings.pve_enhancement", "PVE界面扩展", "pveEnhancementEnabled") end
    if YUI.TeleportAnnouncement and YUI.TeleportAnnouncement.GetScopeSnapshot then
        local scope = YUI.TeleportAnnouncement:GetScopeSnapshot()
        local row = { label = T("settings.teleport_announcement", "传送喊话"), independent = true }
        if scope then row.enabled = scope ~= "off" end
        rows[#rows + 1] = row
    end
    return rows
end

local function GetOptions()
    local db = Tools:GetDB()
    local sections = {}
    for _, tab in ipairs(SETTINGS_TABS) do
        local subFeature = Tools.subFeatures[tab.id]
        local options = tab.id == "teleportAnnouncement" and YUI.TeleportAnnouncement:GetOptions()
            or subFeature and subFeature.BuildOptions and subFeature:BuildOptions(db)
            or { { type = "text", label = T("settings.feature_coming_soon", "该功能将在后续版本开放。") } }
        local details, toggles = YUI.GUI2:SplitFeatureSettingsOptions(options)
        local section = { id = tab.id, label = T(tab.labelKey, tab.fallback),
            toggle = toggles[tab.id], options = details,
            description = T("settings.description." .. tab.id) }
        if tab.id == "keystoneTools" then
            section.id = "keystoneAutoInsert"
            section.label = T("settings.auto_keystone", "自动插钥石")
            section.toggle = toggles.keystoneAutoInsert
            section.pageKey = "keystoneTools"
            sections[#sections + 1] = section
            section = { id = "keystoneAutoAnnounce", label = T("settings.keystone_announce", "钥石通报"),
                toggle = toggles.keystoneAutoAnnounce, options = details, pageKey = "keystoneTools",
                description = section.description }
        elseif tab.id == "teleportAnnouncement" then
            for _, item in ipairs(details) do
                if item.type == "dropdown" then
                    item.onChange = function()
                        if Feature.settingsLayout then Feature.settingsLayout:RefreshStates() end
                    end
                end
            end
            section.group = YUI.Locale:Get("Core")["settings.general.subfeature_shared"] or "Shared feature"
            section.getState = function()
                local scope = YUI.TeleportAnnouncement:GetScopeSnapshot()
                if scope then return scope ~= "off" end
            end
        end
        sections[#sections + 1] = section
    end
    return YUI.GUI2:BuildFeatureSettingsLayout(Feature, {
        sections = sections, selected = activeSettingsTab, retainPages = true,
        onSelect = function(id, previous)
            local previousFeature = Tools.subFeatures[(previous == "keystoneAutoInsert" or previous == "keystoneAutoAnnounce")
                and "keystoneTools" or previous]
            if previousFeature and previousFeature.OnSettingsLeave then previousFeature:OnSettingsLeave(db) end
            activeSettingsTab = id
        end,
    })
end

local function OnSettingsLeave()
    for _, id in ipairs(Tools.subFeatureOrder) do
        local subFeature = Tools.subFeatures[id]
        if subFeature and subFeature.OnSettingsLeave then
            subFeature:OnSettingsLeave(Tools:GetDB())
        end
    end
end

Feature = {
    id = FEATURE_KEY,
    name = T("name", "大秘境工具"),
    description = T("description", "提供大秘境相关的实用辅助功能。"),
    default = true,
    settingsMode = "inline",
    product = PRODUCT_ID,
    tags = { "战斗辅助", "实用功能" },
    callback = ToggleMythicPlusTools,
    GetOptions = GetOptions,
    GetSubFeatureStates = GetSubFeatureStates,
    OnSettingsLeave = OnSettingsLeave,
}

Components:RegisterFeature(FEATURE_KEY, Feature)
