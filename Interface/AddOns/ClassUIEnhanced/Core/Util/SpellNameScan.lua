--[[
    SpellNameScan — resolve a spell NAME to every spell id that carries it.

    No API lists the ids sharing a name, and aura names are secret while auras
    are, so a by-name custom aura (CustomSpells, `by_name`) must hand its
    AuraContainer an id set built ahead of time.  This walks the whole spell id
    range once with C_Spell.GetSpellName and keeps ids ONLY for the names
    something asked for; there is no full name table.  Results go straight into
    the one common cache, `private.profile.aura_name_cache[name]`, which every
    consumer reads.  A name already in that cache is never asked for again
    (CustomSpells), so the walk runs only for a new or changed entry, never per
    build.

    The walk is paced by TIME, not by a count: up to BUDGET_MS of each rendered
    frame, the way Plater's spell cache does (Plater_Auras.lua lazyBuildSpellCache,
    25 ms).  It pauses in combat.  A name asked for mid-walk keeps collecting
    through the wrap back to where it joined, so every name sees every id once.
--]]

local _
---@type string, private
local addonName, private = ...

---@class private : table
---@field SpellNameScan spellnamescan

---@class spellnamescan : table
---@field Request fun(name: string)
---@field IsPending fun(name: string): boolean

---@type spellnamescan
---@diagnostic disable-next-line: missing-fields
local scan = {}
private.SpellNameScan = scan

---Spell ids the client cannot be asked about: the query takes the client down
---(PTR, beta and WoW Forever data).  The same four as Plater's
---`spellBlacklist` and DetailsFramework's `ignoredSpellIDs`, both upstream
---master 2026-10-05.
local BAD_SPELL_IDS = {
    [255616] = true,
    [1249911] = true,
    [1251678] = true,
    [1251535] = true,
}

-- ponytail: fixed ceiling like Plater/DF (retail's highest spell id is
-- 1 323 054 as of 12.1.0); raise it when retail ids pass it.
local LAST_SPELL_ID = 1500000
-- The user's frame-time cap is 5-10 ms; the clock is read every CHUNK ids, so a
-- frame overshoots the budget by at most CHUNK lookups.
local BUDGET_MS = 5
local CHUNK = 64

---name -> the id set being collected for it
---@type table<string, table<number, true>>
local collecting = {}
---name -> `visited` value at which the name has seen every id once
---@type table<string, number>
local doneAt = {}
local cursor = 1
---Ids walked since load, across laps; doneAt is measured in it.
local visited = 0
local driver = CreateFrame("Frame")

local step

---Walk ids until the frame's budget is spent, then hand out every name that
---has completed a full lap.
step = function()
    if InCombatLockdown() then return end
    local deadline = debugprofilestop() + BUDGET_MS
    local i = cursor
    repeat
        for _ = 1, CHUNK do
            if not BAD_SPELL_IDS[i] then
                local name = C_Spell.GetSpellName(i)
                local set = name and collecting[name]
                if set then set[i] = true end
            end
            i = i + 1
            if i > LAST_SPELL_ID then i = 1 end
        end
        visited = visited + CHUNK
    until debugprofilestop() >= deadline
    cursor = i

    local finished = false
    for name, at in pairs(doneAt) do
        if visited >= at then
            private.profile.aura_name_cache[name] = collecting[name]
            collecting[name] = nil
            doneAt[name] = nil
            finished = true
        end
    end
    if not next(doneAt) then driver:SetScript("OnUpdate", nil) end
    if finished then private.Callback.Trigger("OnSpellNamesResolved") end
end

---Start collecting the ids named `name`.  A no-op while it is already being
---collected.  The caller checks the cache first.
---@param name string
scan.Request = function(name)
    if collecting[name] then return end
    collecting[name] = {}
    doneAt[name] = visited + LAST_SPELL_ID
    -- A per-frame driver, against the no-deferral rule on purpose: a 1.5 M-id
    -- walk cannot run inside one frame.  Self-clearing like Anchoring's
    -- pendingWatcherFrame: the OnUpdate exists only while a name is wanted.
    driver:SetScript("OnUpdate", step)
end

---Is `name` still being collected?  The Tracking tab's "resolving" badge.
---@param name string
---@return boolean
scan.IsPending = function(name)
    return collecting[name] ~= nil
end
