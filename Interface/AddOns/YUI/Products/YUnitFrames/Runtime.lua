local ADDON_NAME = ...
local YUI = _G.YUI
local UF = YUI and YUI.YUnitFrames
if not UF then return end
local Security = YUI.API.Security
local owner = {}
local records, nativeParents = {}, setmetatable({}, { __mode = "k" })
local preservedParents = setmetatable({}, { __mode = "k" })
UF.records = records
local Client = UF.Client
local nativeFrames = Client.nativeFrames
local eventDomains, globalEvents = UF.Backend.UnitEvents, UF.Backend.GlobalEvents
local deferred = CreateFrame("Frame") -- event-only: combat deferral and active preview transitions
local parked
local function OnDeferred(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        for _, record in pairs(records) do
            if record.active and record.preview then record.preview = false; UF.View:Paint(record) end
        end
        return
    end
    deferred:UnregisterAllEvents()
    UF.Stats.pending = false
    UF:ApplySettings()
end
deferred:SetScript("OnEvent", OnDeferred)

function UF:InCombat() return Security.InCombatLockdown() == true end
local function SyncPreviewEvents()
    deferred:UnregisterAllEvents()
    if UF.Stats.pending then deferred:RegisterEvent("PLAYER_REGEN_ENABLED") end
    for _, record in pairs(records) do
        if record.active and (record.preview or record.layoutPreview or UF.settingsPreviewUnit) then
            deferred:RegisterEvent("PLAYER_REGEN_DISABLED")
            deferred:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
    end
end

function UF:SetSettingsPreview(unit)
    if self.settingsPreviewUnit == unit then return end
    local previous = self.settingsPreviewUnit
    self.settingsPreviewUnit = unit
    if previous then self:ApplySettings(previous) end
    if unit then self:ApplySettings(unit) end
end

local function Visibility(record, editing)
    if editing then return Client.visibilityPrefix .. "[combat,@" .. record.unit .. ",exists] show; [combat] hide; show" end
    return Client.visibilityPrefix .. "[@" .. record.unit .. ",exists] show; hide"
end
local function Position(unit, index)
    local config = UF:GetDB().units[unit]
    return { anchor = { point = config.point, relative = "UIParent", relativePoint = config.relativePoint },
        offset = { x = config.x, y = config.y - ((index or 1) - 1) * config.spacing } }
end

local function SetNativeHidden(key, hide)
    local frame = _G[nativeFrames[key]]
    if not frame then return end
    local preservedNames = Client.preserveNativeChildren and Client.preserveNativeChildren[key]
    if preservedNames then
      for _, name in ipairs(preservedNames) do
        local child = _G[name]
        if child then
            if hide then
                if not preservedParents[child] and child:GetParent() == frame then
                    preservedParents[child] = frame
                    -- Preserve native anchors, events, scripts and shown state.
                    child:SetParent(UIParent)
                end
            elseif preservedParents[child] then
                if child:GetParent() == UIParent then child:SetParent(preservedParents[child]) end
                preservedParents[child] = nil
            end
        end
      end
    end
    if hide then
        if not parked then parked = YUI.GUI2:CreateFrame(UIParent); parked:Hide() end
        if not nativeParents[frame] then nativeParents[frame] = frame:GetParent() end
        frame:SetParent(parked)
    elseif nativeParents[frame] then
        if frame:GetParent() == parked then frame:SetParent(nativeParents[frame]) end
        nativeParents[frame] = nil
    end
end

local function OnUnitEvent(record, event)
    if not record.active or not UF.Stats.enabled then return end
    UF.Stats.events = UF.Stats.events + 1
    if event == "UNIT_TARGET" and record.parentUnit then UF.View:Paint(record)
    else UF.View:Paint(record, eventDomains[event]) end
    if event == "UNIT_MAXHEALTH" then UF.View:Paint(record, "absorb") end
end

local function BindEvents(record)
    if not record.events then
        record.events = CreateFrame("Frame")
        record.events:SetScript("OnEvent", function(_, event) OnUnitEvent(record, event) end)
    end
    record.events:UnregisterAllEvents()
    for event in pairs(eventDomains) do
        if event == "UNIT_TARGET" and record.parentUnit then record.events:RegisterUnitEvent(event, record.unit, record.parentUnit)
        else record.events:RegisterUnitEvent(event, record.unit) end
    end
end

local function RegisterLayout(record, key, index)
    local Layout = YUI.Layout
    if not Layout then return end
    local id = "yunitframes." .. (record.key or record.unit)
    record.layoutID = id
    local storage = {}
    function storage:identity() return UF:GetDB().units[key] end
    function storage:get() return Position(key, index) end
    function storage:set(_, placement)
        local config = UF:GetDB().units[key]
        local offset = placement.offset
        config.x, config.y = offset.x, offset.y + (index - 1) * config.spacing
        config.point, config.relativePoint = placement.anchor.point, placement.anchor.relativePoint
        return true
    end
    function storage:clear()
        local defaults = UF:DefaultUnit(key)
        local config = UF:GetDB().units[key]
        config.x, config.y = defaults.x, defaults.y
        config.point, config.relativePoint = defaults.point, defaults.relativePoint
        return true
    end
    Layout:RegisterFrame(id, {
        frame = record.frame, title = UF:T("unit." .. key) .. (key == "boss" and " " .. index or ""), category = "product",
        defaultPlacement = function() return Position(key, index) end,
        placementStorage = storage, movable = true, snap = true, anchorTargets = { "UIParent" }, strictAnchorTargets = true,
        isEnabled = function() return UF.Stats.enabled and UF:GetDB().units[key].enabled end,
        onMoverSync = key == "boss" and function(frame)
            if UF:InCombat() then return end
            local spacing = UF:GetDB().units.boss.spacing
            for i = 1, Client.bossCount do
                local sibling = records["boss" .. i]
                if i ~= index and sibling and sibling.active then
                    sibling.frame:ClearAllPoints()
                    sibling.frame:SetPoint("CENTER", frame, "CENTER", 0, (index - i) * spacing)
                end
            end
        end or nil,
        onPlacementCommitted = function()
            if key ~= "boss" then return end
            for i = 1, Client.bossCount do
                local sibling = records["boss" .. i]
                if sibling and sibling.layoutID then Layout:RefreshFrame(sibling.layoutID) end
            end
        end,
        onEnterEditMode = function()
            if UF:InCombat() then return end
            record.layoutPreview = true
            record.preview = true
            UF.View:Configure(record, UF:GetDB().units[key])
            RegisterStateDriver(record.frame, "visibility", Visibility(record, true))
            UF.View:Paint(record)
            SyncPreviewEvents()
        end,
        onExitEditMode = function()
            record.layoutPreview = false
            record.preview = UF.settingsPreviewUnit == key and not UF:InCombat()
            if UF:InCombat() then
                UF.Stats.pending = true; deferred:RegisterEvent("PLAYER_REGEN_ENABLED")
            else
                UF.View:Configure(record, UF:GetDB().units[key])
                RegisterStateDriver(record.frame, "visibility", Visibility(record, record.preview))
            end
            UF.View:Paint(record)
            SyncPreviewEvents()
        end,
        openPluginSettings = function() UF:OpenSettings(key) end,
    })
end

local function BuildRecord(key, index)
    local unit = key == "boss" and "boss" .. index or key
    local record = records[unit]
    if not record then
        record = UF.View:New(UIParent, key == "castbar" and "player" or unit, false, unit)
        record.key = unit
        if key == "castbar" then record.frame:EnableMouse(false) end
        record.parentUnit = key == "targettarget" and "target" or key == "focustarget" and "focus" or nil
        records[unit] = record
        RegisterLayout(record, key, index)
    end
    return record
end

function UF:ApplySettings(unitKey)
    if self:InCombat() then
        self.Stats.pending = true
        deferred:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false, "combat"
    end
    deferred:UnregisterAllEvents(); self.Stats.pending = false
    local db = self:GetDB()
    if not db.units[unitKey] or db.enabled ~= self.Stats.enabled then unitKey = nil end
    self.Stats.enabled = db.enabled
    for _, key in ipairs(self.UnitOrder) do
      if not unitKey or key == unitKey then
        local config = db.units[key]
        local enabled = db.enabled and config.enabled
        for index = 1, key == "boss" and Client.bossCount or 1 do
            local token = key == "boss" and "boss" .. index or key
            local record = records[token]
            if enabled then
                record = record or BuildRecord(key, index)
                record.preview = self.settingsPreviewUnit == key or record.layoutPreview == true
                self.View:Configure(record, config)
                BindEvents(record)
                RegisterStateDriver(record.frame, "visibility", Visibility(record, record.preview))
                if YUI.Layout and record.layoutID then YUI.Layout:RefreshFrame(record.layoutID)
                else
                    record.frame:ClearAllPoints(); record.frame:SetPoint(config.point, UIParent, config.relativePoint, config.x, config.y - (index - 1) * config.spacing)
                end
            elseif record then
                record.events:UnregisterAllEvents()
                UnregisterStateDriver(record.frame, "visibility")
                self.View:Park(record); record.frame:Hide()
                if YUI.Layout and record.layoutID then YUI.Layout:RefreshFrame(record.layoutID) end
            end
        end
        SetNativeHidden(key, enabled and config.hideNative)
      end
    end
    self.Stats.listeners = 0
    for _, record in pairs(records) do
        if record.active then
            self.Stats.listeners = self.Stats.listeners + 1
        end
    end
    SyncPreviewEvents()
    if unitKey then return true end
    YUI.Event:OffOwner(owner)
    if db.enabled then
        for _, event in ipairs(globalEvents) do
            YUI.Event:On(event, function(_, changedUnit)
                if event == "UNIT_PET" and changedUnit ~= "player" then return end
                if event == "PLAYER_TARGET_CHANGED" and records.player then self.View:Paint(records.player, "target") end
                for token, record in pairs(records) do
                    if record.active then
                        if event ~= "PLAYER_TARGET_CHANGED" or token == "target" or token == "targettarget" then self.View:Paint(record) end
                    end
                end
            end, { owner = owner })
        end
    end
    return true
end

function UF:Initialize() self:GetDB() end
function UF:OnLifecycleEnable() return self:ApplySettings() end
function UF:OnLifecycleDisable()
    if self.OnSettingsLeave then self:OnSettingsLeave() end
    return self:ApplySettings()
end
function UF:OnLifecycleProfileChanged()
    self.profile = nil
    local applied, reason = self:ApplySettings()
    if self.RefreshSettings then self:RefreshSettings() end
    return applied, reason
end
function UF:OnLifecycleConfigChanged() return self:ApplySettings() end
function UF:IsEnabled() return self:GetDB().enabled end
function UF:SetEnabled(value, fromLifecycle)
    if self:InCombat() and not fromLifecycle then return false, "combat" end
    self:GetDB().enabled = value == true
    if not fromLifecycle then return YUI.Module:SetEnabled(self.PRODUCT_ID, value == true) end
    return true
end
function UF:OpenSettings(unit)
    if unit then self.selectedUnit = unit end
    return YUI.Settings:OpenProduct(self.PRODUCT_ID, self.SETTINGS_ENTRY)
end

YUI:RegisterProduct({
    id = UF.PRODUCT_ID, title = "YUnitFrames", titleKey = "title", titleNamespace = "YUnitFrames",
    shortTitle = "YUnitFrames", shortTitleKey = "title", shortTitleNamespace = "YUnitFrames",
    notes = "Unit frames", notesKey = "description", notesNamespace = "YUnitFrames", author = "阿言", addonName = ADDON_NAME,
    settingsScope = UF.PRODUCT_ID,
    settings = { enabled = true, entry = UF.SETTINGS_ENTRY, commonPages = { "core.profiles", "core.about" }, minimapIcon = false },
    db = { enabled = false, savedVariable = "YUI_DB", storageKey = UF.STORAGE_KEY }, commands = {},
})
YUI.Module:Register({
    id = UF.PRODUCT_ID, name = "YUnitFrames", product = UF.PRODUCT_ID, scope = UF.PRODUCT_ID, defaultEnabled = Client.defaultEnabled == true, owner = UF,
    dependencies = { "core.db", "core.event", "core.locale", "core.api", "gui", "settings" },
    getEnabled = function(module) return module:IsEnabled() end,
    setEnabled = function(module, enabled) return module:SetEnabled(enabled, true) end,
    OnInitialize = "Initialize", OnEnable = "OnLifecycleEnable", OnDisable = "OnLifecycleDisable",
    OnProfileChanged = "OnLifecycleProfileChanged", OnConfigChanged = "OnLifecycleConfigChanged",
})
YUI.Commands:Register({ id = "yunitframes", productId = "suite", aliases = { "/yuf" }, handler = function() UF:OpenSettings() end })
