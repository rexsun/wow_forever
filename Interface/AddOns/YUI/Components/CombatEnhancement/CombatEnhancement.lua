local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not (YUI and (YUI.IsRetail or YUI.IsWrath or YUI.IsForever)) then return end

local Components = YUI.Components
if not (Components and Components.RegisterFeature) then return end

local FEATURE_KEY = "CombatEnhancement"
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or YUI.ProductId or "suite"
local CONFIG_KEY = "CombatEnhancement_Config"
local DEFAULT_SETTINGS_TAB = "playerPosition"
local SETTINGS_TAB_WIDTH = 620

local L = YUI.Locale and YUI.Locale:Get("CombatEnhancement") or nil
local CombatEnhancement = YUI.CombatEnhancement or {}
YUI.CombatEnhancement = CombatEnhancement

CombatEnhancement.FEATURE_KEY = FEATURE_KEY
CombatEnhancement.PRODUCT_ID = PRODUCT_ID
CombatEnhancement.CONFIG_KEY = CONFIG_KEY
CombatEnhancement.L = L
CombatEnhancement.defaults = CombatEnhancement.defaults or {}
CombatEnhancement.subFeatures = CombatEnhancement.subFeatures or {}
CombatEnhancement.subFeatureOrder = CombatEnhancement.subFeatureOrder or {}
CombatEnhancement.featureActive = CombatEnhancement.featureActive == true

local activeSettingsTab = DEFAULT_SETTINGS_TAB
local Feature

local SETTINGS_TABS = {
    { id = "playerPosition", labelKey = "settings.player_position", fallback = "玩家定位" },
    { id = "targetDistance", labelKey = "settings.target_distance", fallback = "目标距离", placeholderKey = "settings.target_distance_placeholder", placeholderFallback = "目标距离将在后续版本开放。" },
    { id = "castSequence", labelKey = "settings.cast_sequence", fallback = "施法序列", placeholderKey = "settings.cast_sequence_placeholder", placeholderFallback = "施法序列将在后续版本开放。" },
    { id = "combatTimer", labelKey = "settings.combat_timer", fallback = "战斗计时" },
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
    local left = CombatEnhancement.subFeatures[a]
    local right = CombatEnhancement.subFeatures[b]
    local leftOrder = left and left.order or 1000
    local rightOrder = right and right.order or 1000
    if leftOrder == rightOrder then
        return tostring(a) < tostring(b)
    end
    return leftOrder < rightOrder
end

local function FindSettingsTab(id)
    for _, tab in ipairs(SETTINGS_TABS) do
        if tab.id == id then
            return tab
        end
    end
    return nil
end

local function NormalizeSettingsTab(id)
    if FindSettingsTab(id) then
        return id
    end
    return DEFAULT_SETTINGS_TAB
end

local function ClearSettingsPreview()
    if YUI.Settings and YUI.Settings.ClearRightPreview then
        YUI.Settings:ClearRightPreview()
    end
end

function CombatEnhancement:T(key, fallback)
    return T(key, fallback)
end

function CombatEnhancement:IsEnabled()
    return self.featureActive == true
end

function CombatEnhancement:OpenSettingsTab(tabID)
    activeSettingsTab = NormalizeSettingsTab(tabID)

    local opened = false
    if YUI.Settings and YUI.Settings.OpenComponentFeature then
        opened = YUI.Settings:OpenComponentFeature(FEATURE_KEY) and true or false
    elseif Components and Components.OpenFeatureSettings then
        opened = Components:OpenFeatureSettings(FEATURE_KEY) and true or false
    end

    if Feature and Feature.RefreshCurrentModule then
        Feature.RefreshCurrentModule()
    end

    return opened
end

function CombatEnhancement:GetDB()
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

function CombatEnhancement:RegisterSubFeature(subFeature)
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

function CombatEnhancement:RefreshSubFeatures()
    local db = self:GetDB()
    for _, id in ipairs(self.subFeatureOrder) do
        local subFeature = self.subFeatures[id]
        if subFeature and subFeature.RefreshRuntime then
            subFeature:RefreshRuntime(db)
        end
    end
end

local function ToggleCombatEnhancement(enable)
    CombatEnhancement.featureActive = enable == true
    local db = CombatEnhancement:GetDB()
    for _, id in ipairs(CombatEnhancement.subFeatureOrder) do
        local subFeature = CombatEnhancement.subFeatures[id]
        if subFeature and subFeature.OnFeatureToggle then
            subFeature:OnFeatureToggle(CombatEnhancement.featureActive, db)
        end
    end
end

local function GetSubFeatureStates()
    local db = Components:CopyConfigSnapshot(CONFIG_KEY, CombatEnhancement.defaults, PRODUCT_ID)
    if not db then return {} end
    local rows = {}
    local keys = { playerPosition = "playerPositionEnabled", targetDistance = "targetDistanceEnabled",
        castSequence = "castSequenceEnabled", combatTimer = "combatTimerEnabled" }
    for _, tab in ipairs(SETTINGS_TABS) do
        if CombatEnhancement.subFeatures[tab.id] then
            rows[#rows + 1] = { label = T(tab.labelKey, tab.fallback), enabled = db[keys[tab.id]] == true }
            if tab.id == "targetDistance" then
                rows[#rows + 1] = { label = T("settings.target_distance_focus_enabled", "焦点距离"),
                    enabled = db.focusDistanceEnabled == true }
            end
        end
    end
    return rows
end

local function GetOptions()
    local db = CombatEnhancement:GetDB()
    local sections = {}
    for _, tab in ipairs(SETTINGS_TABS) do
        local subFeature = CombatEnhancement.subFeatures[tab.id]
        local options = subFeature and subFeature.BuildOptions and subFeature:BuildOptions(db)
            or { { type = "text", label = T(tab.placeholderKey or "settings.feature_coming_soon",
                tab.placeholderFallback or "该功能将在后续版本开放。") } }
        local details, toggles = YUI.GUI2:SplitFeatureSettingsOptions(options)
        local description = tab.id == "targetDistance" and T("settings.target_distance_shared_note",
            "字体、字号、描边与距离颜色同时用于目标和焦点；开关和位置分别设置。") or nil
        sections[#sections + 1] = { id = tab.id, label = T(tab.labelKey, tab.fallback),
            toggle = toggles[tab.id], options = details, description = description }
        if toggles.focusDistance then
            sections[#sections + 1] = { id = "focusDistance",
                label = T("settings.target_distance_focus_enabled", "焦点距离"),
                toggle = toggles.focusDistance, options = details, description = description }
        end
    end
    return YUI.GUI2:BuildFeatureSettingsLayout(Feature, {
        sections = sections, selected = activeSettingsTab,
        onSelect = function(id, previous)
            local previousFeature = CombatEnhancement.subFeatures[previous == "focusDistance" and "targetDistance" or previous]
            if previousFeature and previousFeature.OnSettingsLeave then previousFeature:OnSettingsLeave(db) end
            activeSettingsTab = id
        end,
        onShowSection = function(id)
            local subFeature = CombatEnhancement.subFeatures[id == "focusDistance" and "targetDistance" or id]
            if subFeature and subFeature.RefreshSettingsPreview then subFeature:RefreshSettingsPreview(db)
            else ClearSettingsPreview() end
        end,
    })
end

local function OnSettingsLeave()
    for _, id in ipairs(CombatEnhancement.subFeatureOrder) do
        local subFeature = CombatEnhancement.subFeatures[id]
        if subFeature and subFeature.OnSettingsLeave then
            subFeature:OnSettingsLeave(CombatEnhancement:GetDB())
        end
    end
end

Feature = {
    id = FEATURE_KEY,
    name = T("name", "战斗增强"),
    description = T("description", "提供战斗场景下的视觉辅助和战斗工具。"),
    default = false,
    settingsMode = "inline",
    product = PRODUCT_ID,
    storageKey = FEATURE_KEY,
    tags = { "战斗辅助" },
    sourceRoot = "Components\\CombatEnhancement",
    assetFolders = { "Components\\CombatEnhancement\\Media" },
    versions = { "forever", "mainline", "wrath" },
    callback = ToggleCombatEnhancement,
    GetOptions = GetOptions,
    GetSubFeatureStates = GetSubFeatureStates,
    OnSettingsLeave = OnSettingsLeave,
}

Components:RegisterFeature(FEATURE_KEY, Feature)
