local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI or not YUI.Components then return end
-- 由常用小工具统一管理设置与生命周期。
if not (YUI.IsRetail or YUI.IsForever) then return end

local Feature = {}
YUI.UtilityToolsNameplates = Feature

local API = YUI.API or {}
local System = API.System or {}
local Security = API.Security or {}
local Frame = API.Frame or {}

local FRIENDLY_PLAYERS_CVAR = "nameplateShowFriendlyPlayers"
local FRIENDLY_NPCS_CVAR = "nameplateShowFriendlyNpcs"
local PLATYNATOR_ADDON_NAME = "Platynator"

local FRIENDLY_PET_CVARS = {
    "nameplateShowFriendlyPlayerMinions",
    "nameplateShowFriendlyPlayerPets",
    "nameplateShowFriendlyPlayerGuardians",
    "nameplateShowFriendlyPlayerTotems",
    "nameplateShowFriendlyMinions",
    "nameplateShowFriendlyPets",
    "nameplateShowFriendlyGuardians",
    "nameplateShowFriendlyTotems",
}

local FRIENDLY_PET_CVAR_SET = {}

local CVAR_WRITE_STATE_WRITABLE = "WRITABLE"
local CVAR_WRITE_STATE_SECURE = "SECURE"
local CVAR_WRITE_STATE_READ_ONLY = "READ_ONLY"
local CVAR_WRITE_STATE_MISSING = "MISSING"
local CVAR_WRITE_STATE_UNKNOWN = "UNKNOWN"

for _, cvar in ipairs(FRIENDLY_PET_CVARS) do
    FRIENDLY_PET_CVAR_SET[cvar] = true
end

local function IsPlatynatorLoaded()
    return YUI.IsRetail and System.IsAddOnLoadedSafe and System.IsAddOnLoadedSafe(PLATYNATOR_ADDON_NAME) or false
end

local function IsCVarEnabled(value)
    return value == "1" or value == 1 or value == true
end

local function IsInCombat()
    if Security.InCombatLockdown then
        return Security.InCombatLockdown() and true or false
    end

    if InCombatLockdown then
        return InCombatLockdown() and true or false
    end

    return false
end

local function GetCVarWriteState(cvar)
    if System.GetCVarWriteState then
        return System.GetCVarWriteState(cvar)
    end

    if System.GetCVarSafe and System.GetCVarSafe(cvar) ~= nil then
        return CVAR_WRITE_STATE_UNKNOWN
    end

    return CVAR_WRITE_STATE_MISSING
end

local function ApplyCVarValue(cvar, value, inCombat)
    if not System.GetCVarSafe then
        return false
    end

    local current = System.GetCVarSafe(cvar)
    if current == nil then
        return false
    end

    value = tostring(value)
    if tostring(current) == value then
        return false
    end

    local state = GetCVarWriteState(cvar)
    if state == CVAR_WRITE_STATE_READ_ONLY or state == CVAR_WRITE_STATE_MISSING then
        return false
    end
    if state == CVAR_WRITE_STATE_SECURE then
        return inCombat
    end
    if state == CVAR_WRITE_STATE_UNKNOWN and inCombat then
        return true
    end
    if state ~= CVAR_WRITE_STATE_WRITABLE and state ~= CVAR_WRITE_STATE_UNKNOWN then
        return false
    end

    if not System.SetCVarSafe then
        return false
    end

    local ok = System.SetCVarSafe(cvar, value)
    return not ok and inCombat
end

local function SuppressFriendlyPetNameplates(inCombat)
    if not IsPlatynatorLoaded() then
        return false
    end

    local retryAfterCombat = false
    for _, cvar in ipairs(FRIENDLY_PET_CVARS) do
        if ApplyCVarValue(cvar, "0", inCombat) then
            retryAfterCombat = true
        end
    end
    return retryAfterCombat
end

local function SyncFriendlyNameplateCVars()
    local value = System.GetCVarSafe and System.GetCVarSafe(FRIENDLY_PLAYERS_CVAR) or nil
    if value == nil then
        return false
    end

    local inCombat = IsInCombat()
    local retryAfterCombat = ApplyCVarValue(FRIENDLY_NPCS_CVAR, value, inCombat)
    if SuppressFriendlyPetNameplates(inCombat) then
        retryAfterCombat = true
    end

    return retryAfterCombat
end

function Feature:SyncCurrentState()
    if not self.enabled then
        return
    end

    self.syncPending = SyncFriendlyNameplateCVars()
end

function Feature:OnCVarUpdate(event, cvar, value)
    if cvar == FRIENDLY_PLAYERS_CVAR then
        self:SyncCurrentState()
    elseif FRIENDLY_PET_CVAR_SET[cvar] then
        local current = System.GetCVarSafe and System.GetCVarSafe(cvar) or value
        if IsCVarEnabled(current) then
            self:SyncCurrentState()
        end
    end
end

function Feature:OnPlayerRegenEnabled()
    if not self.enabled or not self.syncPending then
        return
    end

    self.syncPending = false
    self:SyncCurrentState()
end

function Feature:OnForbiddenNamePlateUnitAdded(event, unit)
    if IsPlatynatorLoaded() and Frame.SuppressPlatynatorFriendlyNamePlate then
        Frame.SuppressPlatynatorFriendlyNamePlate(unit, true)
    end
end

function Feature:OnNamePlateUnitAdded(event, unit)
    if IsPlatynatorLoaded() and Frame.SuppressPlatynatorFriendlyNamePlate then
        Frame.SuppressPlatynatorFriendlyNamePlate(unit, false)
    end
end

function Feature:OnNamePlateUnitRemoved(event, unit)
    if Frame.ClearPlatynatorFriendlyNamePlateSuppression then
        Frame.ClearPlatynatorFriendlyNamePlateSuppression(unit, event == "FORBIDDEN_NAME_PLATE_UNIT_REMOVED")
    end
end

function Feature:Enable()
    if self.enabled then return end
    YUI.Event:OffOwner(self)
    self.enabled = true
    self.syncPending = false

    local platynatorLoaded = IsPlatynatorLoaded()
    if Frame.SetPlatynatorFriendlyNamePlateSuppressionEnabled then
        Frame.SetPlatynatorFriendlyNamePlateSuppressionEnabled(platynatorLoaded)
    end

    self.cvarHandle = YUI.Event:On("CVAR_UPDATE", "OnCVarUpdate", self)
    self.regenHandle = YUI.Event:On("PLAYER_REGEN_ENABLED", "OnPlayerRegenEnabled", self)

    if platynatorLoaded then
        self.nameplateHandle = YUI.Event:On("NAME_PLATE_UNIT_ADDED", "OnNamePlateUnitAdded", self)
        self.forbiddenNameplateHandle = YUI.Event:On("FORBIDDEN_NAME_PLATE_UNIT_ADDED", "OnForbiddenNamePlateUnitAdded", self)
        self.nameplateRemovedHandle = YUI.Event:On("NAME_PLATE_UNIT_REMOVED", "OnNamePlateUnitRemoved", self)
        self.forbiddenNameplateRemovedHandle = YUI.Event:On("FORBIDDEN_NAME_PLATE_UNIT_REMOVED", "OnNamePlateUnitRemoved", self)
    end

    self:SyncCurrentState()
end

function Feature:Disable()
    if not self.enabled then return end
    YUI.Event:OffOwner(self)
    self.enabled = false
    self.syncPending = false

    if Frame.SetPlatynatorFriendlyNamePlateSuppressionEnabled then
        Frame.SetPlatynatorFriendlyNamePlateSuppressionEnabled(false)
    end

    self.cvarHandle = nil
    self.regenHandle = nil
    self.nameplateHandle = nil
    self.forbiddenNameplateHandle = nil
    self.nameplateRemovedHandle = nil
    self.forbiddenNameplateRemovedHandle = nil
end

function Feature:GetStats()
    return {
        enabled = self.enabled == true,
        syncPending = self.syncPending == true,
        listeners = self.enabled and (self.nameplateHandle and 6 or 2) or 0,
    }
end
