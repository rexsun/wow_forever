local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local LevelDisplay = {}
YHUD.LevelDisplay = LevelDisplay

local DEFAULT_LEVEL = 10
local MAX_READS = 2
local HIDE_SCOPES = { all = true, ["non-resource"] = true, native = true }

local function PublicInteger(value, minimum)
    local security = YUI.API and YUI.API.Security
    if security and security.IsSecretValue and security.IsSecretValue(value) then
        return nil
    end
    if type(value) ~= "number" or not (value >= minimum)
        or value == math.huge or value ~= math.floor(value) then
        return nil
    end
    return value
end

local function PublicScope(value)
    local security = YUI.API and YUI.API.Security
    if security and security.IsSecretValue and security.IsSecretValue(value) then return nil end
    return type(value) == "string" and HIDE_SCOPES[value] and value or nil
end

local function WorldReady()
    local lifecycle = YUI.Lifecycle
    return YHUD.startupWorldReady == true
        or (lifecycle and lifecycle.IsReady
            and lifecycle:IsReady("YUI_WORLD_READY") == true)
end

local function Preferences()
    local global = YUI.DB and YUI.DB.GetGlobal
        and YUI.DB:GetGlobal(YHUD.PRODUCT_ID)
    if type(global) ~= "table" then return nil, "account-storage-unavailable" end
    if type(global.consolePreferences) ~= "table" then
        global.consolePreferences = {}
    end
    return global.consolePreferences
end

function YHUD:GetLevelDisplayMaximum()
    if not LevelDisplay.maximum then
        local unit = YUI.API and YUI.API.Unit
        local maximum = unit and unit.GetMaxPlayerLevel and unit.GetMaxPlayerLevel()
        LevelDisplay.maximum = PublicInteger(maximum, DEFAULT_LEVEL) or 100
    end
    return LevelDisplay.maximum
end

function YHUD:GetResourceOnlyBelowLevel()
    if LevelDisplay.threshold == nil then
        local preferences = Preferences()
        local value = preferences and PublicInteger(preferences.resourceOnlyBelowLevel, 0)
        LevelDisplay.threshold = math.min(value or DEFAULT_LEVEL, self:GetLevelDisplayMaximum())
        if preferences then preferences.resourceOnlyBelowLevel = LevelDisplay.threshold end
    end
    return LevelDisplay.threshold
end

function YHUD:SetResourceOnlyBelowLevel(value)
    value = PublicInteger(value, 0)
    if value == nil then return false, "invalid-level-threshold" end
    value = math.min(value, self:GetLevelDisplayMaximum())
    if self:GetResourceOnlyBelowLevel() == value then return true end
    local preferences, code = Preferences()
    if not preferences then return false, code end
    preferences.resourceOnlyBelowLevel = value
    LevelDisplay.threshold = value
    -- A known level stays current through PLAYER_LEVEL_UP, even while off.
    if not LevelDisplay:EnsureInitialLevel() then
        LevelDisplay:RefreshRestriction(true)
    end
    return true
end

function YHUD:GetLowLevelHideScope()
    if LevelDisplay.scope == nil then
        local preferences = Preferences()
        local scope = preferences and preferences.lowLevelHideScope
        LevelDisplay.scope = PublicScope(scope) or "non-resource"
        if preferences then preferences.lowLevelHideScope = LevelDisplay.scope end
    end
    return LevelDisplay.scope
end

function YHUD:SetLowLevelHideScope(scope)
    scope = PublicScope(scope)
    if not scope then
        return false, "invalid-level-hide-scope"
    end
    if self:GetLowLevelHideScope() == scope then return true end
    local preferences, code = Preferences()
    if not preferences then return false, code end
    preferences.lowLevelHideScope = scope
    LevelDisplay.scope = scope
    LevelDisplay:RefreshRestriction(true, true)
    return true
end

function YHUD:IsResourceLevelRestricted()
    return LevelDisplay.restricted == true and LevelDisplay.scope == "all"
end

-- This policy intentionally excludes the designer's presentation bypass.
function YHUD:IsGroupLevelRestricted(group)
    if LevelDisplay.restricted ~= true or type(group) ~= "table" then return false end
    if LevelDisplay.scope == "all" then return true end
    if LevelDisplay.scope == "native" then return group.kind == "official" end
    return group.layout ~= "resource"
end

function LevelDisplay:RefreshRestriction(policyChanged, scopeChanged)
    local restricted = self.active == true and self.threshold > 0
        and self.level ~= nil and self.level < self.threshold or false
    local changed = self.restricted ~= restricted
    self.restricted = restricted
    if not changed and not policyChanged then return false end
    local view = YHUD.View
    if (changed or (scopeChanged and restricted))
        and view and view.active and view.ProjectAllGroupVisibility then
        view:ProjectAllGroupVisibility()
    end
    local resourcesRestricted = YHUD:IsResourceLevelRestricted()
    if self.resourcesRestricted ~= resourcesRestricted then
        self.resourcesRestricted = resourcesRestricted
        local settings = YHUD.BlizzardSettings
        if settings and settings.active and settings.ApplyPersonalResource then
            settings:ApplyPersonalResource("level-display")
        end
    end
    local designer = YHUD.DesignerUI
    if designer and designer.active and designer.RefreshLevelDisplayNotice then
        designer:RefreshLevelDisplayNotice()
    end
    return changed
end

function LevelDisplay:ReadLevel()
    if self.active ~= true or self.threshold <= 0 or self.level ~= nil
        or (self.reads or 0) >= MAX_READS or not WorldReady() then
        return false
    end
    self.reads = (self.reads or 0) + 1
    local unit = YUI.API and YUI.API.Unit
    self.level = PublicInteger(unit and unit.GetPlayerLevel and unit.GetPlayerLevel(), 1)
    return self:RefreshRestriction()
end

function LevelDisplay:EnsureInitialLevel()
    if (self.reads or 0) == 0 then return self:ReadLevel() end
    return false
end

function LevelDisplay:OnWorldReady()
    return self:EnsureInitialLevel()
end

function LevelDisplay:OnEnteringWorld()
    -- Only an unsuccessful initial read permits this one event-based retry.
    if self.reads == 1 then return self:ReadLevel() end
    return false
end

function LevelDisplay:OnLevelUp(_, newLevel)
    if self.active ~= true then return false end
    local level = PublicInteger(newLevel, 1)
    if not level then return false end
    self.level = level
    return self:RefreshRestriction()
end

function LevelDisplay:Enable()
    if self.active then return true end
    self.threshold = YHUD:GetResourceOnlyBelowLevel()
    self.scope = YHUD:GetLowLevelHideScope()
    self.active, self.restricted, self.reads = true, false, 0
    local event = YUI.Event
    if event and event.On then
        local options = { moduleId = YHUD.PRODUCT_ID, traceName = "YHUD.LevelDisplay" }
        event:On("PLAYER_LEVEL_UP", "OnLevelUp", self, options)
        event:On("YUI_WORLD_READY", "OnWorldReady", self, options)
        event:On("PLAYER_ENTERING_WORLD", "OnEnteringWorld", self, options)
    end
    self:EnsureInitialLevel()
    return true
end

function LevelDisplay:Disable()
    if YUI.Event and YUI.Event.OffOwner then YUI.Event:OffOwner(self) end
    self.active, self.level, self.reads, self.restricted = false, nil, 0, false
    self.resourcesRestricted = nil
end
