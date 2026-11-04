local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD or not YHUD.Client or YHUD.Client.assistedHighlight ~= true then return end

local API = YUI.API.AssistedCombat
local GUI = YUI.GUI2
if not (API and API.GetHighlightSpell and API.GetSpellIdentities
    and GUI and GUI.CreateManagedAssistedHighlight
    and GUI.LayoutManagedAssistedHighlight and GUI.SetManagedAssistedHighlightShown) then return end
local Highlight = { active = false, targets = setmetatable({}, { __mode = "k" }) }
YHUD.AssistedHighlight = Highlight
local CALLBACKS = {
    "AssistedCombatManager.OnAssistedHighlightSpellChange",
    "AssistedCombatManager.OnSetUseAssistedHighlight",
    "AssistedCombatManager.RotationSpellsUpdated",
}
Highlight.stats = { reads = 0, writes = 0, flushes = 0, requests = 0 }

local function OnTargetHide(target)
    local record = Highlight.targets[target]
    if record and record.glow and GUI:SetManagedAssistedHighlightShown(record.glow, false) then
        Highlight.stats.writes = Highlight.stats.writes + 1
    end
end

local function OnTargetShow()
    Highlight:Queue()
end

local function OnRecommendation(owner)
    owner:Queue()
end

local function OnRotation(owner)
    owner.aliasesDirty = true
    owner:Queue()
end

function Highlight:OnCombatEnded()
    for target, record in pairs(self.targets) do
        if record.active and record.preparePending then
            self:Prepare(target, record)
        end
    end
    self:Queue()
end

function Highlight:SyncRegistration()
    local view = YHUD.View
    local active = view and view.active == true
        and YHUD:GetConsolePreference("assistedHighlight")
    local hasTargets = false
    if active then
        for _, record in pairs(self.targets) do
            if record.active then hasTargets = true; break end
        end
    end
    local registry = _G.EventRegistry
    if not hasTargets or not registry or not registry.RegisterCallback or not registry.UnregisterCallback then
        if self.active or self.registry then self:Disable() end
        return false
    end
    if self.registry ~= registry then
        if self.registry then self:Disable() end
        for index = 1, #CALLBACKS do
            registry:RegisterCallback(CALLBACKS[index], index == 3 and OnRotation or OnRecommendation, self)
        end
        self.registry = registry
        if YUI.Event then
            YUI.Event:On("PLAYER_REGEN_ENABLED", "OnCombatEnded", self)
        end
    end
    self.active = true
    return true
end

function Highlight:Queue()
    if not self.active then return false end
    self.stats.requests = self.stats.requests + 1
    local bridge = YHUD.NativeBridge
    return bridge and bridge.RequestAssistedHighlightRefresh
        and bridge:RequestAssistedHighlightRefresh() or false
end

function Highlight:Prepare(target, record)
    if InCombatLockdown and InCombatLockdown() then
        record.preparePending = true
        return false
    end
    local runtime = record.runtime
    local width = runtime.itemWidth or runtime.iconWidth or runtime.iconSize or 42
    local height = runtime.itemHeight or runtime.iconHeight or runtime.iconSize or 42
    local level, strata = YHUD.View:GetMonitorDisplayLayer(runtime, record.monitorId)
    level = level and level + 15 or nil
    if not record.glow then
        record.glow = GUI:CreateManagedAssistedHighlight(target, width, height, level, strata, runtime.shape)
    else
        GUI:LayoutManagedAssistedHighlight(record.glow, target, width, height, level, strata, runtime.shape)
    end
    record.preparePending = record.glow == nil or nil
    if record.glow and GUI.AdoptIconSkinEffects then GUI:AdoptIconSkinEffects(target, nil, record.glow) end
    return record.glow ~= nil
end

function Highlight:RefreshIdentity(record)
    local entry = record.entry
    record.spellID, record.baseID, record.overrideID = API.GetSpellIdentities(entry.spellId or entry.spellID or entry.runtimeSpellId)
    record.entryOverrideID = API.GetSpellIdentities(entry.overrideSpellId or entry.overrideSpellID)
end

function Highlight:Bind(target, runtime, monitor, entry, nativeState)
    if not target then return false end
    if not (runtime and runtime.view == "icon" and monitor and monitor.enabled ~= false
        and YHUD:CanConfigureAssistedHighlight(entry)
        and not (monitor.stateEffects and monitor.stateEffects.assistedHighlight == false)) then
        return self:Release(target)
    end
    local record = self.targets[target]
    if not record then
        record = {}
        self.targets[target] = record
        if target.HookScript then
            target:HookScript("OnHide", OnTargetHide)
            target:HookScript("OnShow", OnTargetShow)
        end
    end
    if record.monitorId ~= monitor.id or record.entry ~= entry then OnTargetHide(target) end
    record.runtime, record.monitorId, record.entry = runtime, monitor.id, entry
    record.nativeState = nativeState
    record.active = true
    self:RefreshIdentity(record)
    if not record.spellID and not record.entryOverrideID then return self:Release(target) end
    self:Prepare(target, record)
    self:SyncRegistration()
    self:Queue()
    return true
end

function Highlight:Release(target)
    local record = self.targets[target]
    if not record then return false end
    OnTargetHide(target)
    record.active, record.preparePending = nil, nil
    record.entry, record.runtime, record.nativeState, record.monitorId = nil, nil, nil, nil
    record.spellID, record.baseID, record.overrideID, record.entryOverrideID = nil, nil, nil, nil
    self:SyncRegistration()
    return true
end

local function Matches(record, id)
    return id and (id == record.spellID or id == record.baseID
        or id == record.overrideID or id == record.entryOverrideID)
end

local function IsTargetShown(target)
    local value = target:IsShown()
    local security = YUI.API.Security
    if security and security.SafeBoolean then return security.SafeBoolean(value) == true end
    if type(issecretvalue) == "function" and issecretvalue(value) then return false end
    return value == true
end

function Highlight:Reset()
    self:Disable()
    for _, record in pairs(self.targets) do
        record.active, record.preparePending = nil, nil
        record.entry, record.runtime, record.nativeState, record.monitorId = nil, nil, nil, nil
        record.spellID, record.baseID, record.overrideID, record.entryOverrideID = nil, nil, nil, nil
    end
end

function Highlight:Flush()
    if not self:SyncRegistration() then return false end
    self.stats.flushes = self.stats.flushes + 1
    self.stats.reads = self.stats.reads + 1
    local spellID = API.GetHighlightSpell()
    local id, base, override = API.GetSpellIdentities(spellID)
    local view = YHUD.View
    local suppressed = view.preview == true or view.designMode == true or view.layoutEditMode == true
    for target, record in pairs(self.targets) do
        if record.active then
            if self.aliasesDirty then self:RefreshIdentity(record) end
            local runtime, native = record.runtime, record.nativeState
            local visible = not suppressed and runtime.enabled ~= false
                and runtime.visibilityAllowed ~= false
                and view:IsGroupLevelDisplayAllowed(runtime)
                and IsTargetShown(target)
            if native then
                visible = visible and native.nativeIncluded == true and native.visibilitySuppressed ~= true
            end
            local shown = visible and (Matches(record, id) or Matches(record, base) or Matches(record, override)) == true
            if GUI:SetManagedAssistedHighlightShown(record.glow, shown) then
                self.stats.writes = self.stats.writes + 1
            end
        end
    end
    self.aliasesDirty = nil
    return true
end

function Highlight:Disable()
    if self.registry then
        for index = 1, #CALLBACKS do self.registry:UnregisterCallback(CALLBACKS[index], self) end
        self.registry = nil
    end
    if YUI.Event then YUI.Event:OffOwner(self) end
    self.active, self.aliasesDirty = false, nil
    for target in pairs(self.targets) do OnTargetHide(target) end
end
