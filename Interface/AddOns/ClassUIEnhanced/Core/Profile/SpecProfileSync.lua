
--[[
    SpecProfileSync — automatically switches AceDB profiles based on the
    player's current specialization or spec-derived role.

    Priority chain: spec mapping > role mapping > default fallback.

    Role is derived from the spec itself (GetSpecializationRole), NOT from
    group/raid role assignment. Both are evaluated at spec-change time.

    With no spec system (GetNumSpecializations() <= 1, WoW Forever) the active
    dual-spec talent group stands in for the spec, and the role tier is skipped.

    Mappings are stored in public.db.global.spec_profile_sync so they persist
    across profile switches. The feature is gated behind an enabled toggle.

    When this module triggers a profile switch, it sets a flag that
    CooldownLayoutSync reads to suppress CDM layout restore (Blizzard handles
    CDM layout switching natively via SwitchToBestLayoutForSpec).
--]]

local _
---@type string, private
local addonName, private = ...
local public = private.public

---@class private : table
---@field SpecProfileSync specprofilesync

---@class specprofilesync : table
---@field Initialize fun() Registers callbacks for automatic profile switching; called from Init.lua at PLAYER_LOGIN
---@field IsSpecTriggeredSwitch fun(): boolean Returns true if a spec-triggered profile switch is in progress
---@field ConsumeSpecTriggeredSwitch fun(): boolean Returns the flag and clears it; for the one reader that acts on it

---@type specprofilesync
---@diagnostic disable-next-line: missing-fields
local specSync = {}

-- Cached class filename — constant for the entire session
local playerClassFilename = select(2, UnitClass("player"))

-- Guard flags
local switching = false
local specTriggered = false

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

---Return the global settings table for spec profile sync.
---@return table
local function getSettings()
    return public.db.global.spec_profile_sync
end

---Return the spec key for the given spec index (e.g. "WARRIOR-1").
---@param specIndex number
---@return string
local function getSpecKey(specIndex)
    return playerClassFilename .. "-" .. specIndex
end

---Return the mapping key for a dual-spec talent group (e.g. "DRUID-G2"). The
---"G" keeps it apart from spec keys ("DRUID-2") in the same spec_mappings table.
---@param group number
---@return string
local function getTalentGroupKey(group)
    return playerClassFilename .. "-G" .. group
end

---Find the profile that should be active for the current spec/role.
---Returns nil if no mapping matches or the mapped profile no longer exists.
---@return string|nil profileKey
local function getMappedProfile()
    local settings = getSettings()
    local pm = private.ProfileManager
    local profileKeys = pm.GetProfileKeys()

    -- Priority 1: spec mapping. With no spec system the client reports one
    -- pseudo-spec per class, so the active talent group takes its place.
    local specKey, specIndex
    if GetNumSpecializations() > 1 then
        specIndex = C_SpecializationInfo.GetSpecialization()
        if not specIndex or specIndex == 0 then return nil end
        specKey = getSpecKey(specIndex)
    else
        specKey = getTalentGroupKey(C_SpecializationInfo.GetActiveSpecGroup())
    end
    local specProfile = settings.spec_mappings[specKey]
    if specProfile and profileKeys[specProfile] then
        return specProfile
    end

    -- Priority 2: role mapping (role derived from spec). Skipped with no spec
    -- system: the pseudo-spec's role is one fixed value per class, whatever
    -- the talents, so a role mapping would act as a second default.
    local role = specIndex and private.compat.GetSpecializationRole(specIndex)
    if role then
        local roleProfile = settings.role_mappings[role]
        if roleProfile and profileKeys[roleProfile] then
            return roleProfile
        end
    end

    -- Priority 3: default fallback
    local defaultProfile = settings.default_profile
    if defaultProfile and profileKeys[defaultProfile] then
        return defaultProfile
    end

    return nil
end

---Attempt to switch to the mapped profile.
---@param source string debug label for what triggered this
local function trySwitch(source)
    if not private.profile then return end

    local settings = getSettings()
    if not settings.enabled then
        -- Reset here too: the reset below is unreachable once the feature is
        -- switched off, which would strand specTriggered true for the session and
        -- make CooldownLayoutSync skip the CDM restore on every later switch.
        specTriggered = false
        return
    end
    if switching then return end

    -- Reset flag at start of each evaluation
    specTriggered = false

    -- Defer if in combat — profile switch repositions protected frames
    if InCombatLockdown() then
        local function onLeaveCombat()
            private.Callback.Unregister("OnLeaveCombat", onLeaveCombat)
            -- Secrecy outlives lockdown at a dungeon-exit regen, and a switch
            -- re-applies the CDM layout — re-defer past it. trySwitch
            -- re-validates enabled/mapping/current-profile when it runs.
            private.Util.RunWhenSecrecyClears("SpecProfileSync.trySwitch", function()
                trySwitch(source .. "_deferred")
            end)
        end
        private.Callback.Register("OnLeaveCombat", onLeaveCombat)
        private.printdebug("SpecProfileSync: Deferring switch until out of combat (" .. source .. ")")
        return
    end

    local mappedProfile = getMappedProfile()
    if not mappedProfile then return end

    local currentProfile = private.ProfileManager.GetCurrentProfileKey()
    if mappedProfile == currentProfile then return end

    switching = true
    specTriggered = true
    private.printdebug("SpecProfileSync: Switching to", mappedProfile, "(" .. source .. ")")
    private.ProfileManager.SetProfile(mappedProfile)
    switching = false
    -- CooldownLayoutSync.OnProfileChanged consumed the flag inside that
    -- SetProfile call (AceDB fires OnProfileChanged synchronously). The reset at
    -- the top of trySwitch stays as the backstop for a switch nothing read.
end


-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

---Returns true if a spec/role-triggered profile switch is currently in progress.
---Called by CooldownLayoutSync to decide whether to skip CDM layout restore.
---@return boolean
function specSync.IsSpecTriggeredSwitch()
    return specTriggered
end

---Read the flag and clear it, so it covers exactly the switch that set it.
---It used to stay set until the next spec change, so every manual profile
---switch or import in between also skipped the CDM layout restore and its
---reload prompt -- including after the automatic switch at login.
---@return boolean
function specSync.ConsumeSpecTriggeredSwitch()
    local wasTriggered = specTriggered
    specTriggered = false
    return wasTriggered
end

---Register callbacks for automatic profile switching.
---Called from Init.lua in OnEnable() after CooldownLayoutSync.Initialize().
function specSync.Initialize()
    -- Switch profile on spec change
    private.Callback.Register("OnSpecializationChanged", function()
        trySwitch("spec_change")
    end)

    -- Apply correct profile on login (deferred to let all modules initialize)
    C_Timer.After(0, function()
        trySwitch("login")
    end)
end


private.SpecProfileSync = specSync
