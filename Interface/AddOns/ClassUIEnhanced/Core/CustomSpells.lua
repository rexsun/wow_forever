
--[[
    Custom Spell Tracker

    Per-component user-managed spell entries.  This module owns no frames: it
    keeps the entry lists current and hands out a `{[spellID]=true}` inclusion
    map through GetSpellMapFor, and each host draws the spells itself -- the
    four built-in trackers through CDMDataSource.BuildComponentSpellMaps, aura
    Additional Frames through buildAFAuraSpellMap into their AuraContainer
    candidate map, and "spells" Additional Frames through buildAFIconSpellMap
    into the IconTracker's pooled buttons.

    It used to build its own icon/bar pool too, which the pre-migration
    AdditionalFrameManager.applyIconLayout merged in via GetIconsFor.  Both are
    gone, so a pool would now draw every custom spell twice.

    Components participating: CooldownTracker, UtilitiesTracker, BuffTracker,
    BuffTrackerBars, and every Additional Frame.

    Profile shape: each component's settings table holds an optional
    `custom_spells` array of `{ spellID, restrict_to_player?, ranks?, specs? }`
    entries.  `specs` scopes an aura host's entry by spec (onSpec).
    `ranks = "highest"` (WoW Forever's spell ranks, written only by the Tracking
    tab) draws the spell's highest learned rank: GetRankedSpell.
    `by_name = true` (aura hosts, written only by the Tracking tab) matches
    every spell id carrying the spell's name -- all of a buff's ranks,
    including those other players cast.  The ids come from the one common
    cache `profile.aura_name_cache`, filled by SpellNameScan the first time a
    name is asked for; the aura trackers widen the entry's candidate filter
    with them through GetAuraIdSet.  Until the name resolves the entry is its
    single id.  An entry without the field is exactly `spellID`.

    Entries used to carry `unit` and `filter` too, read only by this module's own
    aura frames.  Those stopped being rendered when the aura trackers moved onto
    AuraContainer, which hands the same spell map to every container and lets
    each container's filter string discriminate -- so a custom spell already
    shows on whichever unit and polarity has it, and the two fields could only
    have narrowed that.  Both were dropped from the Options panel; keys left in
    old profiles are ignored.
--]]

local _
---@type string, private
local addonName, private = ...

---@class private : table
---@field CustomSpells customspells

---@class customspells : table
---@field Initialize fun()
---@field GetSpellMapFor fun(componentName: string): table<number, true>
---@field Rebuild fun(componentName: string)
---@field RebuildAll fun()
---@field OnEnable fun(componentName: string)
---@field OnDisable fun(componentName: string)
---@field GetRankedSpell fun(componentName: string, spellID: number): number|nil
---@field IsOnCurrentSpec fun(entry: custom_spell_entry): boolean
---@field GetAuraIdSet fun(componentName: string, spellID: number): table<number, true>|nil
---@field GetAuraIdSetAny fun(spellID: number): table<number, true>|nil
---@field GetNameStamp fun(): number

---@type customspells
---@diagnostic disable-next-line: missing-fields
local customSpells = {}
private.CustomSpells = customSpells

---Per-component record. Only `disabled` lives here now — GetSpellMapFor
---returns an empty map for a component with no record or a disabled one.
---@type table<string, { disabled: boolean }>
local state = {}

---Per aura host: spellID → name of each `by_name` entry GetSpellMapFor
---handed out, so GetAuraIdSet answers without walking the entries.  An index
---into `profile.aura_name_cache`, not a second cache.
---@type table<string, table<number, string>>
local nameIndex = {}

---Bumped whenever what GetAuraIdSet returns can change for an unchanged spell
---map: a name resolved, or a component's by-name index changed.  The slot
---engine's signature covers base ids only, so the aura trackers salt it with
---this.
local nameStamp = 0

---Read-only stand-in for a component with no `custom_spells` list.
local NO_ENTRIES = {}

---Static map of built-in tracker components → tracker kind ("icon"|"bar").
---AdditionalFrame_<id> instances are resolved dynamically from frame_type
---via getComponentKind below.
---@type table<string, string>
local builtinKind = {
    CooldownTracker = "icon",
    UtilitiesTracker = "icon",
    BuffTracker = "icon",
    BuffTrackerBars = "bar",
}

---Should the custom_spells entry be hidden on the current character because
---the spell is not in the player's spellbook? Restriction is on by default;
---users opt out per entry (`restrict_to_player = false`) to keep item-cast
---spells (Hearthstone, trinkets, engineering gadgets — not in the spellbook)
---visible.
---Also hidden when the spell is overridden into a *different* spell on the
---current spec (e.g. a base ability that morphs per spec/talent), since the
---tracked spell isn't the active version there.
---Never on an aura host (`aura`): an aura id is often in no spellbook — a
---debuff the player's poison applies (Amplifying Poison 383414), a buff cast
---by another class — and the player added the entry by hand.  An aura host
---scopes the entry by spec instead (`specs`, onSpec), stamped with the spec it
---was added on.
---Legacy `nil` values are migrated to `true` on entry into `rebuildComponent`.
---Highest learned rank per spell name, from the spellbook (every rank the
---character has is its own spellbook item there).  nil until first asked
---after a RebuildAll, which runs on SPELLS_CHANGED.
---@type table<string, number>|nil
local highestRankByName = nil

---The highest rank of `spellID`'s spell the character has learned, where the
---client has spell ranks (WoW Forever); nil when it has none learned or the
---spell has no ranks (Util.SpellRank reads no digit on retail).
---@param spellID number
---@return number|nil
local function highestLearnedRank(spellID)
    if not highestRankByName then
        highestRankByName = {}
        local best = {}
        local bank = Enum.SpellBookSpellBank.Player
        for line = 1, private.compat.GetNumSpellBookSkillLines() do
            local lineInfo = private.compat.GetSpellBookSkillLineInfo(line)
            if lineInfo and not lineInfo.offSpecID and not lineInfo.shouldHide then
                for slot = lineInfo.itemIndexOffset + 1, lineInfo.itemIndexOffset + lineInfo.numSpellBookItems do
                    local item = private.compat.GetSpellBookItemInfo(slot, bank)
                    if item and item.itemType == Enum.SpellBookItemType.Spell and not item.isPassive
                        and item.spellID and item.name then
                        local rank = private.Util.SpellRank(item.spellID)
                        local n = rank and private.Util.RankNumber(rank)
                        if n and (not best[item.name] or n > best[item.name]) then
                            best[item.name] = n
                            highestRankByName[item.name] = item.spellID
                        end
                    end
                end
            end
        end
    end
    local name = C_Spell.GetSpellName(spellID)
    return name and highestRankByName[name] or nil
end

---Is a custom aura entry shown on the spec `specKey` (CDMDataSource.GetSpecLayerKey)?
---`specs` nil is every spec: an entry from before the field, or one added with
---the Tracking tab's "All specs" box.  An empty table is no spec.  A client with
---no spec system (nil key) shows every entry.
---@param entry custom_spell_entry
---@param specKey string|nil
---@return boolean
local function onSpec(entry, specKey)
    local specs = entry.specs
    return specKey == nil or type(specs) ~= "table" or specs[specKey] == true
end

---@param spellID number
---@param entry custom_spell_entry
---@param aura boolean  the host is an aura tracker (isAuraHost)
---@param specKey string|nil  the current spec's key, read on an aura host only
---@return boolean
local function shouldFilterEntry(spellID, entry, aura, specKey)
    if not spellID then return false end
    -- An aura host scopes by spec instead of by spellbook (see above).
    if aura then return entry ~= nil and not onSpec(entry, specKey) end
    if entry and entry.restrict_to_player ~= false then
        -- "Highest" is usable while any rank of the spell is learned.
        if entry.ranks == "highest" and highestLearnedRank(spellID) then return false end
        if not IsPlayerSpell(spellID) then return true end
        -- IsPlayerSpell returns true for a base spell whenever any of its
        -- overrides is active, so a spell that morphs into a *different* spell
        -- on this spec (Monk Expel Harm 322101 → Serene Vitality 1242468 on
        -- MW/WW — shared icon, no real Expel Harm) would otherwise pass the
        -- filter and draw the shared art. Require the tracked spell to still
        -- be the active version, i.e. not replaced by a different spell here.
        local active = private.compat.GetOverrideSpell(spellID)
        if active and active ~= spellID then return true end
    end
    return false
end

---Do two by-name indexes (nameIndex values) hold the same entries?
---@param a table<number, string>|nil
---@param b table<number, string>|nil
---@return boolean
local function sameIndex(a, b)
    if a == nil or b == nil then return a == b end
    for spellID, name in pairs(a) do
        if b[spellID] ~= name then return false end
    end
    for spellID in pairs(b) do
        if a[spellID] == nil then return false end
    end
    return true
end

-- Forward declarations for functions referenced before their definition site.
local ensureState
local rebuildComponent
local triggerComponentRefresh
local handleProfileChange
local getComponentKind
local getAFSettings
local getProfileSettings
local pruneNameCache

---Extract the additional-frame id from a component name like
---"AdditionalFrame_af_3" → "af_3". Returns nil for non-AF names.
---@param componentName string
---@return string?
local function getAFId(componentName)
    return componentName and componentName:match("^AdditionalFrame_(.+)$")
end

---Look up an additional frame's settings via component name. Returns nil for
---built-in trackers or when the AF id no longer exists in the profile.
---@param componentName string
---@return additional_frame_profile?
getAFSettings = function(componentName)
    local id = getAFId(componentName)
    if not id then return nil end
    local af = private.profile and private.profile.additional_frames
    return af and af[id] or nil
end

---Resolve the settings table that holds custom_spells for a component name.
---For built-in trackers this is profile.components[name]; for AF instances
---it's profile.additional_frames[id].
---@param componentName string
---@return table?
getProfileSettings = function(componentName)
    local afSettings = getAFSettings(componentName)
    if afSettings then return afSettings end
    return private.profile and private.profile.components and private.profile.components[componentName] or nil
end

---Resolve a component's tracker kind ("icon"|"bar"). AF instances derive
---kind from frame_type: "spells"/"buffs" → icon, "bar" → bar.
---@param componentName string
---@return string?
getComponentKind = function(componentName)
    local builtin = builtinKind[componentName]
    if builtin then return builtin end
    local afSettings = getAFSettings(componentName)
    if afSettings then
        return afSettings.frame_type == "bar" and "bar" or "icon"
    end
    return nil
end

---Does the component track auras (BuffTracker, BuffTrackerBars, a `buffs` or
---`bar` Additional Frame)?  shouldFilterEntry scopes by spec there, not by
---spellbook.
---@param componentName string
---@return boolean
local function isAuraHost(componentName)
    if componentName == "BuffTracker" or componentName == "BuffTrackerBars" then return true end
    local afSettings = getAFSettings(componentName)
    return afSettings ~= nil and (afSettings.frame_type == "buffs" or afSettings.frame_type == "bar")
end

---Ensure the per-component record exists.
---@param componentName string
---@return table
ensureState = function(componentName)
    local s = state[componentName]
    if not s then
        s = {}
        state[componentName] = s
    end
    return s
end

---Force a Refresh on the host component (drives layout to pick up newly shown
---or hidden custom aura frames).
---@param componentName string
triggerComponentRefresh = function(componentName)
    local comp = private.ComponentManager and private.ComponentManager.GetComponent and private.ComponentManager.GetComponent(componentName)
    if comp and comp.Refresh then comp.Refresh() end
end

-- ---------------------------------------------------------------------------
-- Entry maintenance
-- ---------------------------------------------------------------------------

---Bring a component's `custom_spells` entries up to the current shape.
---
---Nothing is rendered from here.  Every consumer takes the `{[spellID]=true}`
---map from GetSpellMapFor and draws the spells itself: the four built-in
---trackers through `CDMDataSource.BuildComponentSpellMaps`, aura Additional
---Frames through `buildAFAuraSpellMap` into their AuraContainer candidate map,
---and `spells` Additional Frames through `buildAFIconSpellMap` into the
---IconTracker's pooled buttons.  This module used to build its own frame pool
---as well, which the pre-migration `applyIconLayout` merged in via
---`GetIconsFor`; both are gone, and a pool would now draw every custom spell
---twice.
---
---So the only thing still owed is the legacy `restrict_to_player` migration,
---which `shouldFilterEntry` and the Options panel both read.  `ensureState`
---must run for every participating component: `GetSpellMapFor` returns an
---empty map when a component has no state record.
---@param componentName string
rebuildComponent = function(componentName)
    if not getComponentKind(componentName) then return end
    ensureState(componentName)

    local profileSettings = getProfileSettings(componentName)
    local entries = profileSettings and profileSettings.custom_spells
    if not entries then return end
    for _, entry in ipairs(entries) do
        if entry.restrict_to_player == nil then
            entry.restrict_to_player = true
        end
    end
end

---Iterate every component participating in custom spell tracking — built-in
---trackers plus every additional frame currently configured in the profile.
---@return fun(): string?
local function eachParticipatingComponent()
    local items = {}
    for name in pairs(builtinKind) do
        items[#items + 1] = name
    end
    if private.profile and private.profile.additional_frames then
        for id in pairs(private.profile.additional_frames) do
            items[#items + 1] = "AdditionalFrame_" .. id
        end
    end
    local i = 0
    return function()
        i = i + 1
        return items[i]
    end
end

---Drop every `aura_name_cache` name no `by_name` entry of this profile uses
---any more, so the cache holds only what is tracked.  Skipped while any such
---entry's name cannot be read yet: its name might be one of the keys.
pruneNameCache = function()
    local cache = private.profile and private.profile.aura_name_cache
    if not cache or not next(cache) then return end
    local used = {}
    for componentName in eachParticipatingComponent() do
        if isAuraHost(componentName) then
            local settings = getProfileSettings(componentName)
            local entries = settings and settings.custom_spells
            if entries then
                for _, entry in ipairs(entries) do
                    if entry.by_name and entry.spellID then
                        local name = C_Spell.GetSpellName(entry.spellID)
                        if not name then return end
                        used[name] = true
                    end
                end
            end
        end
    end
    for name in pairs(cache) do
        if not used[name] then cache[name] = nil end
    end
end

customSpells.Rebuild = function(componentName)
    rebuildComponent(componentName)
    triggerComponentRefresh(componentName)
end

customSpells.RebuildAll = function()
    -- The spellbook may have changed (SPELLS_CHANGED): re-read the ranks.
    highestRankByName = nil
    -- Two passes: a component's Refresh can read another component's spell map
    -- through the anchor chain, so every entry list is migrated before any host
    -- is refreshed.
    for componentName in eachParticipatingComponent() do
        rebuildComponent(componentName)
    end
    pruneNameCache()
    for componentName in eachParticipatingComponent() do
        triggerComponentRefresh(componentName)
    end
end

customSpells.OnEnable = function(componentName)
    local s = ensureState(componentName)
    s.disabled = false
    rebuildComponent(componentName)
end

customSpells.OnDisable = function(componentName)
    local s = state[componentName]
    if not s or s.disabled then return end
    s.disabled = true
end

---Return a {[spellID]=true} inclusion map for all custom spell entries for a
---component that pass the shouldFilterEntry check.  Pass directly to
---candidateFilters.includeSpellIDs in AuraContainer.SyncGroup.
---Returns an empty table when the component has no entries or is disabled.
---@param componentName string
---@return table<number, true>
customSpells.GetSpellMapFor = function(componentName)
    local map = {}
    local s = state[componentName]
    if not s or s.disabled then return map end
    local profileSettings = getProfileSettings(componentName)
    -- No early return without entries: the walk below must still clear an
    -- index a previous profile left behind.
    local entries = profileSettings and profileSettings.custom_spells or NO_ENTRIES
    local aura = isAuraHost(componentName)
    local specKey = aura and private.CDMDataSource.GetSpecLayerKey() or nil
    local index
    for _, entry in ipairs(entries) do
        local spellID = entry.spellID
        if spellID and not shouldFilterEntry(spellID, entry, aura, specKey) then
            map[spellID] = true
            if aura and entry.by_name then
                -- nil while the spell's data is not loaded: the entry is its
                -- single id until a later rebuild reads the name.
                local name = C_Spell.GetSpellName(spellID)
                if name then
                    index = index or {}
                    index[spellID] = name
                    local ids = private.profile.aura_name_cache[name]
                    if ids then
                        -- The walk stops at LAST_SPELL_ID and skips the crash
                        -- ids, so it can miss the entry's own id; an empty set
                        -- would match nothing at all.
                        ids[spellID] = true
                    else
                        private.SpellNameScan.Request(name)
                    end
                end
            end
        end
    end
    if not sameIndex(nameIndex[componentName], index) then
        nameStamp = nameStamp + 1
    end
    nameIndex[componentName] = index
    return map
end

---The id set a `by_name` entry of `componentName` matches: every spell id
---carrying its name, from `profile.aura_name_cache`.  nil for any other entry
---and for a name not resolved yet, which the callers read as "no wider set".
---Reads the index the component's last GetSpellMapFor built, which every aura
---host calls before it syncs its containers.
---@param componentName string
---@param spellID number
---@return table<number, true>|nil
customSpells.GetAuraIdSet = function(componentName, spellID)
    local index = nameIndex[componentName]
    local name = index and index[spellID]
    return name and private.profile.aura_name_cache[name] or nil
end

---GetAuraIdSet for a caller that is not one tracker: `spellID` as a `by_name`
---entry of ANY aura host.  CDMAlerts' aura sounds are keyed by spell id
---alone, so a by-name row's alert must ring for every id carrying the name.
---@param spellID number
---@return table<number, true>|nil
customSpells.GetAuraIdSetAny = function(spellID)
    for _, index in pairs(nameIndex) do
        local name = index[spellID]
        if name then return private.profile.aura_name_cache[name] end
    end
    return nil
end

---@return number
customSpells.GetNameStamp = function()
    return nameStamp
end

---Is a custom aura entry shown on the current spec (onSpec)?  The Tracking
---tab's "This spec" box reads it.
---@param entry custom_spell_entry
---@return boolean
customSpells.IsOnCurrentSpec = function(entry)
    return onSpec(entry, private.CDMDataSource.GetSpecLayerKey())
end

---The spell a custom entry is DRAWN as: for a "Highest" entry
---(`ranks = "highest"`) of this component, the highest learned rank of its
---spell, which follows the character as ranks are learned; nil for any other
---entry, including one typed in by id, which is that exact rank.  The entry's
---`spellID` stays the tracker's key (order, config).  IconTracker's
---displaySpell asks this per button.
---@param componentName string
---@param spellID number
---@return number|nil
customSpells.GetRankedSpell = function(componentName, spellID)
    local profileSettings = getProfileSettings(componentName)
    local entries = profileSettings and profileSettings.custom_spells
    if not entries then return nil end
    for i = 1, #entries do
        local entry = entries[i]
        if entry.spellID == spellID and entry.ranks == "highest" then
            return highestLearnedRank(spellID)
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Profile-load wiring
-- ---------------------------------------------------------------------------

---Rebuild every component's pool when the profile changes (segment import,
---profile switch, AceDB reset). The InternalCallback name confirmed via
---`Core/InternalCallback.lua` is `OnProfileChanged`.
handleProfileChange = function()
    customSpells.RebuildAll()
end

if private.Callback and private.Callback.Register then
    private.Callback.Register("OnProfileChanged", handleProfileChange)
    -- Spec swap changes IsPlayerSpell results — re-evaluate the player-spell
    -- filter and the aura entries' spec scope so entries appear
    -- or disappear without a /reload.
    private.Callback.Register("OnSpecializationChanged", function()
        customSpells.RebuildAll()
    end)
    -- A by-name entry's ids landed in aura_name_cache: widen the containers.
    -- The scan pauses in combat, so this never arrives while the aura
    -- trackers' Refresh is bailing on lockdown.
    private.Callback.Register("OnSpellNamesResolved", function()
        nameStamp = nameStamp + 1
        customSpells.RebuildAll()
    end)
end

-- SPELLS_CHANGED catches talent learn/forget and intermediate states where
-- IsPlayerSpell flips without a spec swap. Debounced one frame so a burst of
-- spellbook events coalesces into a single RebuildAll.
do
    local spellbookWatcher = CreateFrame("Frame")
    spellbookWatcher:RegisterEvent("SPELLS_CHANGED")
    local pending = false
    spellbookWatcher:SetScript("OnEvent", function()
        if pending then return end
        pending = true
        C_Timer.After(0, function()
            pending = false
            customSpells.RebuildAll()
        end)
    end)
end

---Initial-load wiring. Built-in trackers (CooldownTracker, UtilitiesTracker,
---BuffTracker, BuffTrackerBars) never have their `OnEnable` called on /reload —
---PLAYER_LOGIN runs `RefreshAllComponents` (which calls `Refresh`, not
---`OnEnable`), and AceDB's `OnProfileChanged` only fires on actual profile
---*switch*, not initial load. Without this, custom_spells entries saved in the
---profile are silently absent until the user toggles a component or switches
---profile. AFs are unaffected because `AdditionalFrameManager.Initialize`
---activates each frame, which routes through `CustomSpells.OnEnable`.
---Called from `Core/Init.lua` after viewers are populated.
customSpells.Initialize = function()
    customSpells.RebuildAll()
end
