local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI or not YUI.IsRetail then return end

local Components = YUI.Components
if not Components or not Components.RegisterFeature then return end

local GUI2 = YUI.GUI2
local FEATURE_KEY = "ClassExtraMonitor"
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or YUI.ProductId or "suite"
local CONFIG_KEY = "ClassExtraMonitor_Config"
local SETTINGS_TAB_WIDTH = 620
local SETTINGS_LABEL_WIDTH = 112
local SETTINGS_LABEL_GAP = 10
local SETTINGS_SPEC_CONTROL_WIDTH = 232
local SETTINGS_SPEC_ROW_WIDTH = SETTINGS_LABEL_WIDTH + SETTINGS_LABEL_GAP + SETTINGS_SPEC_CONTROL_WIDTH
local ICON_SCOPE_ID = "class_extra_monitor"

local L = YUI.Locale and YUI.Locale:Get("ClassExtraMonitor") or nil
local Monitor = YUI.ClassExtraMonitor or {}
YUI.ClassExtraMonitor = Monitor

Monitor.FEATURE_KEY = FEATURE_KEY
Monitor.PRODUCT_ID = PRODUCT_ID
Monitor.CONFIG_KEY = CONFIG_KEY
Monitor.L = L
Monitor.defaults = Monitor.defaults or {}
Monitor.subFeatures = Monitor.subFeatures or {}
Monitor.subFeatureOrder = Monitor.subFeatureOrder or {}
Monitor.featureActive = Monitor.featureActive == true

local activeSettingsSpecID
local activeSettingsFeatureID
local Feature

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
    local left = Monitor.subFeatures[a]
    local right = Monitor.subFeatures[b]
    local leftOrder = left and left.order or 1000
    local rightOrder = right and right.order or 1000
    if leftOrder == rightOrder then
        return tostring(a) < tostring(b)
    end
    return leftOrder < rightOrder
end

local function SafeNumber(value)
    local num = tonumber(value)
    if num then return num end
    return nil
end

local function NormalizeClassFile(classFile)
    if type(classFile) ~= "string" or classFile == "" then return nil end
    if strupper then return strupper(classFile) end
    return string.upper(classFile)
end

local function GetTalentAPI()
    return YUI.API and YUI.API.Talent or nil
end

local function GetUnitAPI()
    return YUI.API and YUI.API.Unit or nil
end

local function GetCurrentSpecInfo()
    local TalentAPI = GetTalentAPI()
    if TalentAPI and (TalentAPI.GetCurrentConfigurationSpecializationInfo or TalentAPI.GetCurrentSpecializationInfo) then
        local info = (TalentAPI.GetCurrentConfigurationSpecializationInfo or TalentAPI.GetCurrentSpecializationInfo)()
        if type(info) == "table" then
            info.specID = SafeNumber(info.specID)
            info.classFile = NormalizeClassFile(info.classFile)
            return info
        end
    end
    return nil
end

local function GetPlayerClassFile()
    local info = GetCurrentSpecInfo()
    if info and info.classFile then return info.classFile end

    local UnitAPI = GetUnitAPI()
    if UnitAPI and UnitAPI.GetClassToken then
        return NormalizeClassFile(UnitAPI.GetClassToken("player"))
    end
    if UnitClass then
        local _, classFile = UnitClass("player")
        return NormalizeClassFile(classFile)
    end
    return nil
end

local function ResolveClassID(classFile)
    classFile = NormalizeClassFile(classFile)
    if not classFile then return nil end

    local UnitAPI = GetUnitAPI()
    if UnitAPI and UnitAPI.GetClassInfos then
        for _, info in ipairs(UnitAPI.GetClassInfos() or {}) do
            if NormalizeClassFile(info.classFile) == classFile then
                return SafeNumber(info.classID)
            end
        end
    end
    return nil
end

local function ResolveSpecInfo(subFeature)
    if type(subFeature) ~= "table" then return nil end

    local specID = SafeNumber(subFeature.specID)
    if not specID then return nil end

    local classFile = NormalizeClassFile(subFeature.classFile)
    local classID = SafeNumber(subFeature.classID) or ResolveClassID(classFile)
    local specInfo
    local TalentAPI = GetTalentAPI()

    if TalentAPI and (TalentAPI.GetClassConfigurationSpecializations or TalentAPI.GetClassSpecializations) and classID then
        for _, info in ipairs((TalentAPI.GetClassConfigurationSpecializations or TalentAPI.GetClassSpecializations)(classID) or {}) do
            if SafeNumber(info.specID) == specID then
                specInfo = info
                break
            end
        end
    end

    if not specInfo and TalentAPI and TalentAPI.GetSpecializationInfoByID then
        local resolvedSpecID, name, description, icon, role = TalentAPI.GetSpecializationInfoByID(specID)
        if SafeNumber(resolvedSpecID) == specID then
            specInfo = {
                specID = specID,
                name = name,
                description = description,
                icon = icon,
                role = role,
            }
        end
    end

    specInfo = specInfo or {}
    return {
        specID = specID,
        specIndex = SafeNumber(subFeature.specIndex or specInfo.specIndex),
        classID = classID or SafeNumber(specInfo.classID),
        classFile = classFile or NormalizeClassFile(specInfo.classFile),
        name = YUI.Locale and YUI.Locale.GetSpecializationName
            and YUI.Locale:GetSpecializationName(
                specID,
                subFeature.specName or specInfo.name or T(subFeature.labelKey or ("settings.tab_" .. subFeature.id), subFeature.label or tostring(specID))
            )
            or subFeature.specName or specInfo.name or T(subFeature.labelKey or ("settings.tab_" .. subFeature.id), subFeature.label or tostring(specID)),
        icon = subFeature.specIcon or specInfo.icon,
        specOrder = SafeNumber(subFeature.specOrder or subFeature.order) or 1000,
    }
end

local function SortFeatureList(features)
    table.sort(features, function(a, b)
        local leftOrder = SafeNumber(a and a.order) or 1000
        local rightOrder = SafeNumber(b and b.order) or 1000
        if leftOrder ~= rightOrder then return leftOrder < rightOrder end
        return tostring(a and a.id or "") < tostring(b and b.id or "")
    end)
end

local function BuildSupportedSpecEntries()
    local entries = {}
    local bySpecID = {}
    local currentSpec = GetCurrentSpecInfo()
    local currentSpecID = currentSpec and currentSpec.specID or nil
    local playerClassFile = GetPlayerClassFile()

    for _, id in ipairs(Monitor.subFeatureOrder) do
        local subFeature = Monitor.subFeatures[id]
        local spec = ResolveSpecInfo(subFeature)
        if spec then
            local entry = bySpecID[spec.specID]
            if not entry then
                entry = {
                    specID = spec.specID,
                    specIndex = spec.specIndex,
                    classID = spec.classID,
                    classFile = spec.classFile,
                    name = spec.name,
                    icon = spec.icon,
                    specOrder = spec.specOrder,
                    features = {},
                }
                bySpecID[spec.specID] = entry
                entries[#entries + 1] = entry
            else
                entry.classID = entry.classID or spec.classID
                entry.classFile = entry.classFile or spec.classFile
                entry.specIndex = entry.specIndex or spec.specIndex
                entry.icon = entry.icon or spec.icon
                entry.name = entry.name or spec.name
                entry.specOrder = math.min(entry.specOrder or 1000, spec.specOrder or 1000)
            end

            entry.features[#entry.features + 1] = subFeature
        end
    end

    for _, entry in ipairs(entries) do
        SortFeatureList(entry.features)
    end

    table.sort(entries, function(a, b)
        local aBucket = (currentSpecID and a.specID == currentSpecID) and 0
            or (playerClassFile and a.classFile == playerClassFile) and 1
            or 2
        local bBucket = (currentSpecID and b.specID == currentSpecID) and 0
            or (playerClassFile and b.classFile == playerClassFile) and 1
            or 2
        if aBucket ~= bBucket then return aBucket < bBucket end

        local aOrder = SafeNumber(a.specOrder) or 1000
        local bOrder = SafeNumber(b.specOrder) or 1000
        if aOrder ~= bOrder then return aOrder < bOrder end

        local aClass = a.classFile or ""
        local bClass = b.classFile or ""
        if aClass ~= bClass then return aClass < bClass end

        local aIndex = SafeNumber(a.specIndex) or 1000
        local bIndex = SafeNumber(b.specIndex) or 1000
        if aIndex ~= bIndex then return aIndex < bIndex end

        return (a.specID or 0) < (b.specID or 0)
    end)

    return entries
end

local function FindSpecEntry(specID, entries)
    specID = SafeNumber(specID)
    if not specID then return nil end
    entries = entries or BuildSupportedSpecEntries()
    for _, entry in ipairs(entries) do
        if entry.specID == specID then return entry end
    end
    return nil
end

local function NormalizeSettingsSpecID(specID, entries)
    local entry = FindSpecEntry(specID, entries)
    if entry then return entry.specID end
    entries = entries or BuildSupportedSpecEntries()
    return entries[1] and entries[1].specID or nil
end

local function FindSettingsFeature(id, features)
    if type(id) ~= "string" then return nil end
    for _, subFeature in ipairs(features or {}) do
        if subFeature.id == id then return subFeature end
    end
    return nil
end

local function NormalizeSettingsFeatureID(id, features)
    local feature = FindSettingsFeature(id, features)
    if feature then return feature.id end
    feature = features and features[1] or nil
    return feature and feature.id or nil
end

local function LeaveSettingsSpec(specID, db)
    local entry = FindSpecEntry(specID)
    if not entry then return end
    db = db or Monitor:GetDB()
    for _, subFeature in ipairs(entry.features) do
        if subFeature and subFeature.OnSettingsLeave then
            subFeature:OnSettingsLeave(db)
        end
    end
end

function Monitor:T(key, fallback)
    return T(key, fallback)
end

local function ResolveValue(value)
    if type(value) ~= "function" then
        return value
    end
    local ok, result = pcall(value)
    if ok then return result end
    return nil
end

function Monitor:AppendIconDivider(options, label, icon, width)
    if type(options) ~= "table" then return end
    options[#options + 1] = {
        type = "custom",
        width = width or SETTINGS_TAB_WIDTH,
        render = function(parent, x, y, availableWidth)
            local ui = GUI2 or YUI.GUI2
            if not (ui and ui.CreateFrame and ui.CreateIcon and ui.CreateText and ui.CreateTexture) then
                return width or SETTINGS_TAB_WIDTH, 1
            end

            local frameWidth = math.min(availableWidth or width or SETTINGS_TAB_WIDTH, width or SETTINGS_TAB_WIDTH)
            local frameHeight = 26
            local iconSize = 18
            local frame = ui:CreateFrame(parent, {
                width = frameWidth,
                height = frameHeight,
            })
            frame:SetPoint("TOPLEFT", x, y)

            local texture = ResolveValue(icon)
            local title = ResolveValue(label) or ""
            local iconTexture = ui:CreateIcon(frame, {
                icon = texture,
                size = iconSize,
            })
            iconTexture:SetPoint("LEFT", frame, "LEFT", 0, 0)

            local text = ui:CreateText(frame, title, "font.size.md", "color.text.heading")
            text:SetPoint("LEFT", iconTexture, "RIGHT", 8, 0)
            text:SetJustifyH("LEFT")
            text:SetWordWrap(false)

            local line = ui:CreateTexture(frame, { layer = "ARTWORK" })
            line:SetHeight(1)
            line:SetPoint("LEFT", text, "RIGHT", 8, 0)
            line:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
            frame.gui2DividerIconText = text
            frame.gui2DividerIconLine = line

            frame.RefreshTheme = function(divider)
                if divider.gui2DividerIconText then
                    ui:SetTextColorKey(divider.gui2DividerIconText, "color.text.heading")
                end
                local dividerLine = divider.gui2DividerIconLine
                if not dividerLine then return end
                local r, g, b = ui:GetColor("color.text.heading")
                if dividerLine.SetGradient and CreateColor then
                    dividerLine:SetColorTexture(1, 1, 1, 1)
                    dividerLine:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.88), CreateColor(r, g, b, 0.08))
                elseif dividerLine.SetGradientAlpha then
                    dividerLine:SetGradientAlpha("HORIZONTAL", r, g, b, 0.88, r, g, b, 0.08)
                else
                    dividerLine:SetColorTexture(r, g, b, 0.72)
                end
            end
            frame:RefreshTheme()
            if ui.RegisterThemeObject then
                ui:RegisterThemeObject(frame)
            end
            return frameWidth, frameHeight
        end,
    }
end

function Monitor:IsEnabled()
    return self.featureActive == true
end

function Monitor:GetDB()
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

function Monitor:RegisterSubFeature(subFeature)
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

function Monitor:RefreshSubFeatures(db)
    db = db or self:GetDB()
    for _, id in ipairs(self.subFeatureOrder) do
        local subFeature = self.subFeatures[id]
        if subFeature and subFeature.RefreshRuntime then
            subFeature:RefreshRuntime(db)
        end
    end
end

local function ToggleClassExtraMonitor(enable)
    Monitor.featureActive = enable == true
    local db = Monitor:GetDB()
    for _, id in ipairs(Monitor.subFeatureOrder) do
        local subFeature = Monitor.subFeatures[id]
        if subFeature and subFeature.OnFeatureToggle then
            subFeature:OnFeatureToggle(Monitor.featureActive, db)
        end
    end
end

local function SelectSettingsSpec(value)
    local entries = BuildSupportedSpecEntries()
    local nextSpecID = NormalizeSettingsSpecID(value, entries)
    if activeSettingsSpecID ~= nextSpecID then
        local previousSpecID = activeSettingsSpecID
        if previousSpecID then
            LeaveSettingsSpec(previousSpecID, Monitor:GetDB())
        end
        activeSettingsSpecID = nextSpecID
        activeSettingsFeatureID = nil
    end
    return activeSettingsSpecID
end

local function SelectSettingsFeature(value, features)
    local nextFeatureID = NormalizeSettingsFeatureID(value, features)
    if activeSettingsFeatureID ~= nextFeatureID then
        local previous = FindSettingsFeature(activeSettingsFeatureID, features)
        if previous and previous.OnSettingsLeave then
            previous:OnSettingsLeave(Monitor:GetDB())
        end
        activeSettingsFeatureID = nextFeatureID
    end
    return activeSettingsFeatureID
end

local function GetSubFeatureStates()
    local db = Components:CopyConfigSnapshot(CONFIG_KEY, Monitor.defaults, PRODUCT_ID)
    if not db then return {} end
    local rows = {}
    local keys = { devourerTransform = "devourerTransformEnabled", brewmasterElixir = "brewmasterElixirEnabled" }
    for _, id in ipairs(Monitor.subFeatureOrder) do
        local subFeature = Monitor.subFeatures[id]
        if subFeature and keys[id] then
            rows[#rows + 1] = { label = T(subFeature.labelKey, subFeature.label or id), enabled = db[keys[id]] ~= false }
        end
    end
    return rows
end

local function GetOptions()
    local db = Monitor:GetDB()
    local supportedSpecs = BuildSupportedSpecEntries()

    if #supportedSpecs == 0 then
        return { {
            type = "text",
            label = T("settings.no_supported_specs", "暂无可配置的专精监控。"),
            colorKey = "color.text.muted",
        } }
    end

    activeSettingsSpecID = NormalizeSettingsSpecID(activeSettingsSpecID, supportedSpecs)
    local specEntry = FindSpecEntry(activeSettingsSpecID, supportedSpecs)
    activeSettingsFeatureID = NormalizeSettingsFeatureID(activeSettingsFeatureID, specEntry.features)
    local sections, specsByFeature = {}, {}
    for _, entry in ipairs(supportedSpecs) do
        for _, subFeature in ipairs(entry.features) do
            local options = subFeature.BuildOptions and subFeature:BuildOptions(db)
                or { { type = "text", label = T("settings.feature_coming_soon", "该功能将在后续版本开放。") } }
            local details, toggles = GUI2:SplitFeatureSettingsOptions(options)
            sections[#sections + 1] = { id = subFeature.id,
                label = T(subFeature.labelKey, subFeature.label or subFeature.id),
                group = entry.name, specID = entry.specID, icon = entry.icon,
                toggle = toggles[subFeature.id], options = details }
            specsByFeature[subFeature.id] = entry
        end
    end
    return GUI2:BuildFeatureSettingsLayout(Feature, {
        sections = sections, selected = activeSettingsFeatureID,
        onSelect = function(id)
            local entry = specsByFeature[id]
            SelectSettingsSpec(entry.specID)
            SelectSettingsFeature(id, entry.features)
        end,
    })
end

local function OnSettingsLeave()
    local db = Monitor:GetDB()
    for _, id in ipairs(Monitor.subFeatureOrder) do
        local subFeature = Monitor.subFeatures[id]
        if subFeature and subFeature.OnSettingsLeave then
            subFeature:OnSettingsLeave(db)
        end
    end
    activeSettingsSpecID = nil
    activeSettingsFeatureID = nil
end

Feature = {
    id = FEATURE_KEY,
    name = T("name", "职业额外监控"),
    description = T("description", "提供职业专属战斗信息的额外监控。"),
    default = false,
    settingsMode = "inline",
    product = PRODUCT_ID,
    tags = { "战斗辅助" },
    sourceRoot = "Components\\ClassExtraMonitor",
    versions = { "mainline" },
    callback = ToggleClassExtraMonitor,
    GetOptions = GetOptions,
    GetSubFeatureStates = GetSubFeatureStates,
    OnSettingsLeave = OnSettingsLeave,
}

Components:RegisterFeature(FEATURE_KEY, Feature)
