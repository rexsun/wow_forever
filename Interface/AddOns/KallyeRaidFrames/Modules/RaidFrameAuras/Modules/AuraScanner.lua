local addonName, ns = ...
local l = ns.I18N;

-- * avoid conflict override
if ns.CONFLICT then return; end

local RaidFrameAuras = ns.RaidFrameAuras
if not RaidFrameAuras then return end

local State = ns.State or {}
local Util = ns.Util or {}
local C_UnitAuras = C_UnitAuras
local RawAuraFilters = AuraUtil and AuraUtil.AuraFilters or {}
local GetAuraSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
local GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
local GetUnitAuras = C_UnitAuras and C_UnitAuras.GetUnitAuras
local GetUnitAuraInstanceIDs = C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs
local GetAuraDataByAuraInstanceID = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
local IsAuraFilteredOut = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
local CreateAuraFilterString = AuraUtil and AuraUtil.CreateFilterString
local UnitAuraSortRule = Enum and Enum.UnitAuraSortRule
local UnitAuraSortDirection = Enum and Enum.UnitAuraSortDirection
local NAME_ONLY_SORT_RULE = UnitAuraSortRule and UnitAuraSortRule.NameOnly
local NORMAL_SORT_DIRECTION = UnitAuraSortDirection and UnitAuraSortDirection.Normal
local REVERSE_SORT_DIRECTION = UnitAuraSortDirection and UnitAuraSortDirection.Reverse
local AURA_FILTER_SEPARATOR = "|"
local LONG_BUFF_DURATION_THRESHOLD = 15 * 60
local LATEST_ORDER_INCREMENT = 0.000001
local LONG_BUFF_LONG_DURATION = "long-duration"
local LONG_BUFF_NO_DURATION = "no-duration"
local Unpack = unpack
local GetTime = GetTime
local NoAuraFilters = {}
local NameOrderByID = {}

local LongBuffSpellIDExceptions = {
    -- Restoration Shaman
    [974] = true, -- Earth Shield
    [383648] = true, -- Earth Shield
    [61295] = true, -- Riptide

    -- Holy Paladin
    [53563] = true, -- Beacon of Light
    [156910] = true, -- Beacon of Faith
    [1244893] = true, -- Beacon of the Savior

    -- Preservation Evoker
    [360827] = true, -- Blistering Scales
    [364343] = true, -- Echo
    [366155] = true, -- Reversion
    [367364] = true, -- Reversion (Echo copy)
    [355941] = true, -- Dream Breath
    [373267] = true, -- Lifebind

    -- Short healer effects can be present just before combat starts. During
    -- that transition, WoW can briefly expose incomplete duration data; never
    -- let these short effects become cached as long-buff spell IDs.
    -- Restoration Druid
    [774] = true, -- Rejuvenation
    [155777] = true, -- Germination
    [33763] = true, -- Lifebloom
    [8936] = true, -- Regrowth
    [102351] = true, -- Cenarion Ward
    [102352] = true, -- Cenarion Ward (periodic heal)
    [48438] = true, -- Wild Growth
    [325748] = true, -- Adaptive Swarm

    -- Mistweaver Monk
    [448430] = true, -- Renewing Mist (applied aura)
    [227345] = true, -- Enveloping Mist (applied aura)

    -- Priest
    [139] = true, -- Renew
    [41635] = true, -- Prayer of Mending
    [194384] = true, -- Atonement
}

local function GetUnitCacheGUID(unit)
    if type(UnitGUID) ~= "function" then return nil end
    local guid = UnitGUID(unit)
    if Util.IsSecretValue and Util.IsSecretValue(guid) then return nil end
    return guid
end

local function BumpAuraCacheGeneration(cache)
    if not cache then return end
    State.auraCacheGeneration = (State.auraCacheGeneration or 0) + 1
    cache.generation = State.auraCacheGeneration
end

local AuraFilters = {
    HELPFUL = RawAuraFilters.Helpful or "HELPFUL",
    HARMFUL = RawAuraFilters.Harmful or "HARMFUL",
    PLAYER = RawAuraFilters.Player or "PLAYER",
    RAID = RawAuraFilters.Raid or "RAID",
    CANCELABLE = RawAuraFilters.Cancelable or "CANCELABLE",
    NOT_CANCELABLE = RawAuraFilters.NotCancelable or "NOT_CANCELABLE",
    INCLUDE_NAME_PLATE_ONLY = RawAuraFilters.IncludeNameplateOnly or RawAuraFilters.IncludeNamePlateOnly or "INCLUDE_NAME_PLATE_ONLY",
    EXTERNAL_DEFENSIVE = RawAuraFilters.ExternalDefensive or "EXTERNAL_DEFENSIVE",
    CROWD_CONTROL = RawAuraFilters.CrowdControl or "CROWD_CONTROL",
    RAID_IN_COMBAT = RawAuraFilters.RaidInCombat or "RAID_IN_COMBAT",
    RAID_PLAYER_DISPELLABLE = RawAuraFilters.RaidPlayerDispellable or "RAID_PLAYER_DISPELLABLE",
    BIG_DEFENSIVE = RawAuraFilters.BigDefensive or "BIG_DEFENSIVE",
    -- IMPORTANT is not exposed by AuraUtil.AuraFilters on every 12.0.7 build.
    -- Treat it as optional so a missing category cannot degrade to HELPFUL/HARMFUL.
    IMPORTANT = RawAuraFilters.Important,
}

local function BuildAuraFilter(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local part = select(i, ...)
        if part and part ~= "" then
            parts[#parts + 1] = part
        end
    end

    if CreateAuraFilterString then
        return CreateAuraFilterString(Unpack(parts))
    end

    local filter
    for i = 1, #parts do
        filter = filter and (filter .. AURA_FILTER_SEPARATOR .. parts[i]) or parts[i]
    end
    return filter or ""
end

local function BuildCategoryFilter(auraKind, categoryFilter, playerFilter)
    if not auraKind or not categoryFilter then return nil end
    return BuildAuraFilter(auraKind, categoryFilter, playerFilter)
end

local function AddCategoryFilter(filters, auraKind, categoryFilter, playerFilter)
    local filter = BuildCategoryFilter(auraKind, categoryFilter, playerFilter)
    if not filter then return false end
    filters[#filters + 1] = filter
    return true
end

local PriorityLongBuffExemptionFilters = {}
AddCategoryFilter(PriorityLongBuffExemptionFilters, AuraFilters.HELPFUL, AuraFilters.IMPORTANT)
AddCategoryFilter(PriorityLongBuffExemptionFilters, AuraFilters.HELPFUL, AuraFilters.BIG_DEFENSIVE)
AddCategoryFilter(PriorityLongBuffExemptionFilters, AuraFilters.HELPFUL, AuraFilters.EXTERNAL_DEFENSIVE)

local function BuildHelpfulScanFilter(db)
    return BuildAuraFilter(AuraFilters.HELPFUL, db.directBuffIncludeNameplateOnly and AuraFilters.INCLUDE_NAME_PLATE_ONLY or nil)
end

local function BuildHarmfulScanFilter(db)
    return BuildAuraFilter(AuraFilters.HARMFUL, db.directDebuffIncludeNameplateOnly and AuraFilters.INCLUDE_NAME_PLATE_ONLY or nil)
end

local function IsPlayerInCombat()
    local affectingCombat = UnitAffectingCombat and UnitAffectingCombat("player")
    if affectingCombat then return true end
    local inLockdown = InCombatLockdown and InCombatLockdown()
    return inLockdown ~= nil and inLockdown ~= false
end

function RaidFrameAuras:IsPlayerInCombat()
    return IsPlayerInCombat()
end

local function GetSafeAuraSpellID(auraData)
    local spellID = auraData and auraData.spellId
    if spellID == nil then return nil end
    if Util.IsSecretValue and Util.IsSecretValue(spellID) then return nil end
    spellID = tonumber(spellID)
    if not spellID or spellID ~= spellID or spellID == math.huge or spellID == -math.huge then return nil end
    return spellID
end

-- Blizzard's compact raid frames always display boss-flagged debuffs, even with
-- "only dispellable" or other restrictive filters active. Mirror that so boss
-- mechanics (e.g. dungeon bleeds) cannot be filtered away. isBossAura is a plain
-- boolean flag, but guard against secret values per 12.x combat safety rules.
local function IsBossAura(auraData)
    if not auraData then return false end
    local isBoss = auraData.isBossAura
    if isBoss == nil then return false end
    if Util.IsSecretValue and Util.IsSecretValue(isBoss) then return false end
    return isBoss == true
end

local function IsLongBuffSpellIDException(spellID)
    return spellID ~= nil and LongBuffSpellIDExceptions[spellID] == true
end

local function GetSafeAuraDuration(auraData)
    local duration = auraData and auraData.duration
    if duration == nil then return nil end
    if Util.AsSafeNumber then
        return Util.AsSafeNumber(duration)
    end
    if Util.IsSecretValue and Util.IsSecretValue(duration) then return nil end
    duration = tonumber(duration)
    if not duration or duration ~= duration or duration == math.huge or duration == -math.huge then return nil end
    return duration
end

local function GetLongBuffReason(auraData, db)
    -- 12.x safety: aura duration/expiration values can be secret in combat.
    -- This feature only reads duration while out of combat, then reuses the
    -- cached marker in combat. Never compare duration or expiration values in
    -- combat.
    if IsPlayerInCombat() then return nil end
    if not db or db.directBuffHideLong ~= true then return nil end

    local spellID = GetSafeAuraSpellID(auraData)
    if spellID == nil or IsLongBuffSpellIDException(spellID) then return nil end

    local duration = GetSafeAuraDuration(auraData)
    if duration == nil then return nil end
    if duration == 0 then return LONG_BUFF_NO_DURATION end
    if duration > LONG_BUFF_DURATION_THRESHOLD then return LONG_BUFF_LONG_DURATION end
    return nil
end

local function RememberLongBuffSpellID(auraData, reason)
    local spellID = GetSafeAuraSpellID(auraData)
    if spellID == nil or IsLongBuffSpellIDException(spellID) then return end
    State.longBuffSpellIDs = State.longBuffSpellIDs or {}
    State.longBuffSpellIDs[spellID] = reason or LONG_BUFF_LONG_DURATION
end

local function IsMarkedLongBuff(cache, id, auraData)
    local spellID = GetSafeAuraSpellID(auraData)
    if spellID ~= nil and IsLongBuffSpellIDException(spellID) then return false end

    local marker = cache and cache.longBuffs and cache.longBuffs[id]
    if marker ~= nil then
        return true
    end

    -- If the same spell was safely classified out of combat before, hide newly
    -- seen/re-applied instances during combat without touching duration values.
    -- If spellId is secret, GetSafeAuraSpellID returns nil and this fails closed.
    if not IsPlayerInCombat() then return false end
    if spellID == nil or IsLongBuffSpellIDException(spellID) then return false end

    local spellMarker = spellID ~= nil and State.longBuffSpellIDs and State.longBuffSpellIDs[spellID]
    return spellMarker ~= nil
end

local IsPriorityLongBuffExempt

local function HideMarkedLongBuff(cache, id, unit, db, auraData)
    if not db or db.directBuffHideLong ~= true then return false end
    if not IsMarkedLongBuff(cache, id, auraData) then return false end
    if IsPriorityLongBuffExempt(cache, unit, id) then return false end
    if db.directBuffHideLongOnlyInCombat == true then
        return IsPlayerInCombat()
    end
    return true
end

local function HasAnyLongBuffMarker()
    if State.longBuffSpellIDs and next(State.longBuffSpellIDs) ~= nil then
        return true
    end

    for _, cache in pairs(State.auraCache) do
        if cache and cache.longBuffs and next(cache.longBuffs) ~= nil then
            return true
        end
    end

    return false
end

local function EnsureAuraCacheEntry(unit)
    local entry = State.auraCache[unit]
    if entry then return entry end
    entry = {
        buffs = {},
        debuffs = {},
        defensives = {},
        playerDispellable = {},
        allDispellable = {},
        crowdControls = {},
        categoryScales = {},
        buffData = {},
        debuffData = {},
        buffsByID = {},
        debuffsByID = {},
        longBuffs = {},
        priorityLongBuffExemptions = {},
        orderByID = {},
        latestOrderByID = {},
        nextOrder = 0,
        nextLatestOrder = 0,
        nextUnknownLatestOrder = 0,
        hasFullScan = false,
        generation = 0,
        buffOrderDirty = false,
        debuffOrderDirty = false,
    }
    State.auraCache[unit] = entry
    return entry
end

local function BuildDirectBuffFilters(db)
    local onlyMine = db.directBuffOnlyMine
    local playerFilter = onlyMine and AuraFilters.PLAYER or nil
    if db.directBuffShowAll then
        return onlyMine and { BuildAuraFilter(AuraFilters.HELPFUL, playerFilter) } or nil
    end
    local filters = {}
    if db.directBuffFilterRaid and not (db.directBuffFilterRaidHideInCombat and IsPlayerInCombat()) then
        filters[#filters + 1] = BuildAuraFilter(AuraFilters.HELPFUL, AuraFilters.RAID, playerFilter)
    end
    if db.directBuffFilterRaidInCombat then AddCategoryFilter(filters, AuraFilters.HELPFUL, AuraFilters.RAID_IN_COMBAT, playerFilter) end
    if db.directBuffFilterCancelable then AddCategoryFilter(filters, AuraFilters.HELPFUL, AuraFilters.CANCELABLE, playerFilter) end
    if db.directBuffFilterNotCancelable then AddCategoryFilter(filters, AuraFilters.HELPFUL, AuraFilters.NOT_CANCELABLE, playerFilter) end
    if db.directBuffFilterImportant then AddCategoryFilter(filters, AuraFilters.HELPFUL, AuraFilters.IMPORTANT, playerFilter) end
    if db.directBuffFilterBigDefensive then AddCategoryFilter(filters, AuraFilters.HELPFUL, AuraFilters.BIG_DEFENSIVE, playerFilter) end
    if db.directBuffFilterExternalDefensive then AddCategoryFilter(filters, AuraFilters.HELPFUL, AuraFilters.EXTERNAL_DEFENSIVE, playerFilter) end
    if #filters == 0 then return NoAuraFilters end
    return filters
end

local function BuildDirectDebuffFilters(db)
    local onlyMine = db.directDebuffOnlyMine
    local playerFilter = onlyMine and AuraFilters.PLAYER or nil
    if db.directDebuffShowAll then
        return onlyMine and { BuildAuraFilter(AuraFilters.HARMFUL, playerFilter) } or nil
    end
    local filters = {}
    if db.directDebuffFilterRaid then AddCategoryFilter(filters, AuraFilters.HARMFUL, AuraFilters.RAID, playerFilter) end
    if db.directDebuffFilterRaidInCombat then AddCategoryFilter(filters, AuraFilters.HARMFUL, AuraFilters.RAID_IN_COMBAT, playerFilter) end
    if db.directDebuffFilterCrowdControl then AddCategoryFilter(filters, AuraFilters.HARMFUL, AuraFilters.CROWD_CONTROL, playerFilter) end
    if db.directDebuffFilterImportant then AddCategoryFilter(filters, AuraFilters.HARMFUL, AuraFilters.IMPORTANT, playerFilter) end
    if db.directDebuffDispellableMode == "PLAYER" then AddCategoryFilter(filters, AuraFilters.HARMFUL, AuraFilters.RAID_PLAYER_DISPELLABLE, playerFilter) end
    if #filters == 0 then
        return NoAuraFilters
    end
    return filters
end

local function AddCategoryScaleFilter(filters, optionKey, exclusionFilters, auraKind, categoryFilter, playerFilter)
    local filter = BuildCategoryFilter(auraKind, categoryFilter, playerFilter)
    if not filter then return false end
    filters[#filters + 1] = {
        optionKey = optionKey,
        filter = filter,
        exclusionFilters = exclusionFilters,
    }
    return true
end

local function BuildBuffDefensiveCategoryFilters(playerFilter)
    local filters = {}
    AddCategoryFilter(filters, AuraFilters.HELPFUL, AuraFilters.BIG_DEFENSIVE, playerFilter)
    AddCategoryFilter(filters, AuraFilters.HELPFUL, AuraFilters.EXTERNAL_DEFENSIVE, playerFilter)
    return filters
end

local function BuildBuffCategoryScaleFilters(db)
    local onlyMine = db.directBuffOnlyMine
    local playerFilter = onlyMine and AuraFilters.PLAYER or nil
    local filters = {}
    if db.directBuffFilterImportant then
        AddCategoryScaleFilter(filters, "directBuffFilterImportantScale", BuildBuffDefensiveCategoryFilters(playerFilter), AuraFilters.HELPFUL, AuraFilters.IMPORTANT, playerFilter)
    end
    if db.directBuffFilterBigDefensive then
        AddCategoryScaleFilter(filters, "directBuffFilterBigDefensiveScale", nil, AuraFilters.HELPFUL, AuraFilters.BIG_DEFENSIVE, playerFilter)
    end
    if db.directBuffFilterExternalDefensive then
        AddCategoryScaleFilter(filters, "directBuffFilterExternalDefensiveScale", nil, AuraFilters.HELPFUL, AuraFilters.EXTERNAL_DEFENSIVE, playerFilter)
    end
    return #filters > 0 and filters or nil
end

local function BuildDebuffCategoryScaleFilters(db)
    local playerFilter = db.directDebuffOnlyMine and AuraFilters.PLAYER or nil
    local filters = {}
    if db.directDebuffFilterCrowdControl then
        AddCategoryScaleFilter(filters, "directDebuffFilterCrowdControlScale", nil, AuraFilters.HARMFUL, AuraFilters.CROWD_CONTROL, playerFilter)
    end
    if db.directDebuffFilterImportant then
        local crowdControlFilter = BuildCategoryFilter(AuraFilters.HARMFUL, AuraFilters.CROWD_CONTROL, playerFilter)
        AddCategoryScaleFilter(filters, "directDebuffFilterImportantScale", crowdControlFilter and { crowdControlFilter } or nil, AuraFilters.HARMFUL, AuraFilters.IMPORTANT, playerFilter)
    end
    return #filters > 0 and filters or nil
end

-- Specialized categories that overlap should OR together, but Important must
-- not bring them back when none of their specialized categories are enabled.
local function BuildSpecializedCategoryExclusion(matchFilters, enabledFilters)
    if not matchFilters or #matchFilters == 0 then return nil end
    if enabledFilters and #enabledFilters >= #matchFilters then return nil end
    return {
        matchFilters = matchFilters,
        enabledFilters = enabledFilters or NoAuraFilters,
    }
end

local function AddEnabledSpecializedCategoryFilter(filters, optionEnabled, filter)
    if optionEnabled == true then
        filters[#filters + 1] = filter
    end
end

local function BuildBuffCategoryExclusionFilters(db)
    if db.directBuffShowAll then return nil end
    local playerFilter = db.directBuffOnlyMine and AuraFilters.PLAYER or nil
    local matchFilters = BuildBuffDefensiveCategoryFilters(playerFilter)
    local enabledFilters = {}
    AddEnabledSpecializedCategoryFilter(enabledFilters, db.directBuffFilterBigDefensive, matchFilters[1])
    AddEnabledSpecializedCategoryFilter(enabledFilters, db.directBuffFilterExternalDefensive, matchFilters[2])
    local exclusion = BuildSpecializedCategoryExclusion(matchFilters, enabledFilters)
    return exclusion and { exclusion } or nil
end

local function BuildDebuffCategoryExclusionFilters(db)
    if db.directDebuffShowAll then return nil end
    local playerFilter = db.directDebuffOnlyMine and AuraFilters.PLAYER or nil
    local crowdControlFilter = BuildCategoryFilter(AuraFilters.HARMFUL, AuraFilters.CROWD_CONTROL, playerFilter)
    if not crowdControlFilter then return nil end
    local enabledFilters = {}
    AddEnabledSpecializedCategoryFilter(enabledFilters, db.directDebuffFilterCrowdControl, crowdControlFilter)
    local exclusion = BuildSpecializedCategoryExclusion({ crowdControlFilter }, enabledFilters)
    return exclusion and { exclusion } or nil
end

local function BuildDirectDefensiveFilters(db)
    if State.cachedDefensiveFilters and not State.filtersDirty then return State.cachedDefensiveFilters end
    local filters = {}
    if not db or db.directBuffFilterBigDefensive == true then
        AddCategoryFilter(filters, AuraFilters.HELPFUL, AuraFilters.BIG_DEFENSIVE)
    end
    if not db or db.directBuffFilterExternalDefensive == true then
        AddCategoryFilter(filters, AuraFilters.HELPFUL, AuraFilters.EXTERNAL_DEFENSIVE)
    end
    State.cachedDefensiveFilters = #filters > 0 and filters or nil
    return State.cachedDefensiveFilters
end

local function BuildDirectDispelFilter()
    if State.cachedDispelFilter and not State.filtersDirty then return State.cachedDispelFilter end
    State.cachedDispelFilter = BuildCategoryFilter(AuraFilters.HARMFUL, AuraFilters.RAID_PLAYER_DISPELLABLE)
    return State.cachedDispelFilter
end

local function BuildCrowdControlFilter()
    return BuildCategoryFilter(AuraFilters.HARMFUL, AuraFilters.CROWD_CONTROL)
end

local function ResolveFilters()
    if State.filtersDirty then
        State.cachedBuffFilters = BuildDirectBuffFilters(RaidFrameAuras.db)
        State.cachedDebuffFilters = BuildDirectDebuffFilters(RaidFrameAuras.db)
        State.cachedBuffCategoryScaleFilters = BuildBuffCategoryScaleFilters(RaidFrameAuras.db)
        State.cachedDebuffCategoryScaleFilters = BuildDebuffCategoryScaleFilters(RaidFrameAuras.db)
        State.cachedBuffCategoryExclusionFilters = BuildBuffCategoryExclusionFilters(RaidFrameAuras.db)
        State.cachedDebuffCategoryExclusionFilters = BuildDebuffCategoryExclusionFilters(RaidFrameAuras.db)
        State.cachedCrowdControlFilter = BuildCrowdControlFilter()
        State.cachedBuffScanFilter = BuildHelpfulScanFilter(RaidFrameAuras.db)
        State.cachedDebuffScanFilter = BuildHarmfulScanFilter(RaidFrameAuras.db)
        State.cachedDefensiveFilters = nil
        State.cachedDispelFilter = nil
        State.filtersDirty = false
    end
    return State.cachedBuffFilters,
        State.cachedDebuffFilters,
        BuildDirectDefensiveFilters(RaidFrameAuras.db),
        BuildDirectDispelFilter(),
        State.cachedBuffCategoryScaleFilters,
        State.cachedDebuffCategoryScaleFilters,
        State.cachedCrowdControlFilter,
        State.cachedBuffScanFilter,
        State.cachedDebuffScanFilter,
        State.cachedBuffCategoryExclusionFilters,
        State.cachedDebuffCategoryExclusionFilters
end

local function AuraPassesAnyFilter(unit, auraInstanceID, filters)
    if filters and #filters == 0 then return false end
    if not filters or not IsAuraFilteredOut then return true end
    for i = 1, #filters do
        local ok, filtered = pcall(IsAuraFilteredOut, unit, auraInstanceID, filters[i])
        if ok and not filtered then
            return true
        end
    end
    return false
end

local function AuraPassesFilterStrict(unit, auraInstanceID, filter)
    if not filter or not IsAuraFilteredOut then return false end
    local ok, filtered = pcall(IsAuraFilteredOut, unit, auraInstanceID, filter)
    return ok and not filtered
end

IsPriorityLongBuffExempt = function(cache, unit, auraInstanceID)
    if not cache or not auraInstanceID then return false end
    local exemptions = cache.priorityLongBuffExemptions
    if not exemptions then
        exemptions = {}
        cache.priorityLongBuffExemptions = exemptions
    end

    local exempt = exemptions[auraInstanceID]
    if exempt ~= nil then return exempt == true end

    exempt = false
    for i = 1, #PriorityLongBuffExemptionFilters do
        if AuraPassesFilterStrict(unit, auraInstanceID, PriorityLongBuffExemptionFilters[i]) then
            exempt = true
            break
        end
    end
    exemptions[auraInstanceID] = exempt
    return exempt
end

local function AuraIsExcludedByFilters(unit, auraInstanceID, filters)
    if not filters or #filters == 0 then return false end
    for i = 1, #filters do
        local filter = filters[i]
        if type(filter) == "table" then
            if AuraPassesAnyFilter(unit, auraInstanceID, filter.matchFilters) and not AuraPassesAnyFilter(unit, auraInstanceID, filter.enabledFilters) then
                return true
            end
        elseif AuraPassesFilterStrict(unit, auraInstanceID, filter) then
            return true
        end
    end
    return false
end

local function BoolText(value)
    return value and "yes" or "no"
end

local function DebugValueText(value, fallback)
    if value == nil then return fallback or "nil" end
    if Util.IsSecretValue(value) then return "secret" end
    return tostring(value)
end

local function DebugAuraPassesFilter(labels, unit, auraInstanceID, label, ...)
    for i = 1, select("#", ...) do
        if not select(i, ...) then return end
    end
    if AuraPassesFilterStrict(unit, auraInstanceID, BuildAuraFilter(...)) then
        labels[#labels + 1] = label
    end
end

local function DebugGetAuraFilterLabels(unit, auraInstanceID, kind)
    local labels = {}
    if kind == "buff" then
        DebugAuraPassesFilter(labels, unit, auraInstanceID, "HELPFUL", AuraFilters.HELPFUL)
        DebugAuraPassesFilter(labels, unit, auraInstanceID, "HELPFUL|PLAYER", AuraFilters.HELPFUL, AuraFilters.PLAYER)
        DebugAuraPassesFilter(labels, unit, auraInstanceID, "HELPFUL|RAID", AuraFilters.HELPFUL, AuraFilters.RAID)
        DebugAuraPassesFilter(labels, unit, auraInstanceID, "HELPFUL|RAID_IN_COMBAT", AuraFilters.HELPFUL, AuraFilters.RAID_IN_COMBAT)
        DebugAuraPassesFilter(labels, unit, auraInstanceID, "HELPFUL|CANCELABLE", AuraFilters.HELPFUL, AuraFilters.CANCELABLE)
        DebugAuraPassesFilter(labels, unit, auraInstanceID, "HELPFUL|NOT_CANCELABLE", AuraFilters.HELPFUL, AuraFilters.NOT_CANCELABLE)
        DebugAuraPassesFilter(labels, unit, auraInstanceID, "HELPFUL|IMPORTANT", AuraFilters.HELPFUL, AuraFilters.IMPORTANT)
        DebugAuraPassesFilter(labels, unit, auraInstanceID, "HELPFUL|BIG_DEFENSIVE", AuraFilters.HELPFUL, AuraFilters.BIG_DEFENSIVE)
        DebugAuraPassesFilter(labels, unit, auraInstanceID, "HELPFUL|EXTERNAL_DEFENSIVE", AuraFilters.HELPFUL, AuraFilters.EXTERNAL_DEFENSIVE)
    else
        DebugAuraPassesFilter(labels, unit, auraInstanceID, "HARMFUL", AuraFilters.HARMFUL)
        DebugAuraPassesFilter(labels, unit, auraInstanceID, "HARMFUL|PLAYER", AuraFilters.HARMFUL, AuraFilters.PLAYER)
        DebugAuraPassesFilter(labels, unit, auraInstanceID, "HARMFUL|RAID", AuraFilters.HARMFUL, AuraFilters.RAID)
        DebugAuraPassesFilter(labels, unit, auraInstanceID, "HARMFUL|RAID_IN_COMBAT", AuraFilters.HARMFUL, AuraFilters.RAID_IN_COMBAT)
        DebugAuraPassesFilter(labels, unit, auraInstanceID, "HARMFUL|CROWD_CONTROL", AuraFilters.HARMFUL, AuraFilters.CROWD_CONTROL)
        DebugAuraPassesFilter(labels, unit, auraInstanceID, "HARMFUL|IMPORTANT", AuraFilters.HARMFUL, AuraFilters.IMPORTANT)
        DebugAuraPassesFilter(labels, unit, auraInstanceID, "HARMFUL|RAID_PLAYER_DISPELLABLE", AuraFilters.HARMFUL, AuraFilters.RAID_PLAYER_DISPELLABLE)
    end
    return #labels > 0 and table.concat(labels, ",") or "none"
end

local function DebugLogAuraClassification(cache, unit, auraData, kind)
    local db = RaidFrameAuras.db
    if not db or db.debugMode ~= true then return end

    local id = auraData and auraData.auraInstanceID
    if not id then return end

    local spellID = auraData.spellId
    local scale = cache.categoryScales[id]
    local scaleText = scale and string.format("%.2f", scale) or "1.00"
    local shown
    if kind == "buff" then
        shown = cache.buffs[id] == true
    else
        shown = cache.debuffs[id] == true
    end
    local extra
    if kind == "buff" then
        extra = string.format(
            "defensive=%s longBuff=%s longBuffExempt=%s",
            BoolText(cache.defensives[id] == true),
            BoolText(cache.longBuffs[id] ~= nil),
            BoolText(cache.priorityLongBuffExemptions and cache.priorityLongBuffExemptions[id] == true)
        )
    else
        extra = string.format(
            "bossAura=%s playerDispellable=%s allDispellable=%s crowdControl=%s dispelType=%s",
            BoolText(IsBossAura(auraData)),
            BoolText(cache.playerDispellable[id] == true),
            BoolText(cache.allDispellable[id] == true),
            BoolText(cache.crowdControls[id] == true),
            tostring(auraData.dispelName or "none")
        )
    end

    Util.DebugLog(
        "aura %s unit=%s name=\"%s\" spellId=%s auraId=%s source=%s stacks=%s shown=%s scale=%s filters=[%s] %s",
        kind,
        tostring(unit),
        DebugValueText(auraData.name, ""),
        DebugValueText(spellID),
        tostring(id),
        DebugValueText(auraData.sourceUnit),
        DebugValueText(auraData.applications, "0"),
        BoolText(shown),
        scaleText,
        DebugGetAuraFilterLabels(unit, id, kind),
        extra
    )
end

local function AuraPassesDebuffOnlyMine(unit, auraInstanceID, db)
    if not db.directDebuffOnlyMine then return true end
    return AuraPassesFilterStrict(unit, auraInstanceID, BuildAuraFilter(AuraFilters.HARMFUL, AuraFilters.PLAYER))
end

local function GetMatchedCategoryScale(unit, auraInstanceID, categoryFilters, db)
    if not categoryFilters then return nil end
    local bestScale
    local bestDelta = -1
    for i = 1, #categoryFilters do
        local entry = categoryFilters[i]
        if entry and AuraPassesFilterStrict(unit, auraInstanceID, entry.filter) and (not entry.exclusionFilters or not AuraPassesAnyFilter(unit, auraInstanceID, entry.exclusionFilters)) then
            local scale = Util.ClampCategoryScale(db[entry.optionKey])
            local delta = math.abs(scale - 1)
            if delta > bestDelta then
                bestScale = scale
                bestDelta = delta
            end
        end
    end
    return bestScale
end

local function ClassifyAura(cache, unit, auraData, kind, buffFilters, debuffFilters, defFilters, dispelFilter, db, buffCategoryScaleFilters, debuffCategoryScaleFilters, crowdControlFilter, buffExclusionFilters, debuffExclusionFilters)
    local id = auraData and auraData.auraInstanceID
    if not id then return end
    if kind == "buff" then
        local excluded = AuraIsExcludedByFilters(unit, id, buffExclusionFilters)
        if not IsPlayerInCombat() then
            local longBuffReason = GetLongBuffReason(auraData, db)
            if longBuffReason and IsPriorityLongBuffExempt(cache, unit, id) then
                longBuffReason = nil
            end
            cache.longBuffs[id] = longBuffReason or nil
            if longBuffReason then
                RememberLongBuffSpellID(auraData, longBuffReason)
            end
        end
        if HideMarkedLongBuff(cache, id, unit, db, auraData) then
            excluded = true
        end
        if not excluded and (not buffFilters or AuraPassesAnyFilter(unit, id, buffFilters)) then
            cache.buffs[id] = true
        end
        if not excluded and defFilters and AuraPassesAnyFilter(unit, id, defFilters) then
            cache.defensives[id] = true
        end
        local categoryScale = not excluded and GetMatchedCategoryScale(unit, id, buffCategoryScaleFilters, db) or nil
        cache.categoryScales[id] = categoryScale and categoryScale ~= 1 and categoryScale or nil
        DebugLogAuraClassification(cache, unit, auraData, kind)
    else
        local allDispellable = auraData.dispelName ~= nil
        if allDispellable then
            cache.allDispellable[id] = true
        end
        -- Boss debuffs bypass every visibility filter, just like the default UI.
        local isBoss = IsBossAura(auraData)
        local excluded = not isBoss and AuraIsExcludedByFilters(unit, id, debuffExclusionFilters)
        local passesFilters = not excluded and (not debuffFilters or AuraPassesAnyFilter(unit, id, debuffFilters))
        local passesAllDispellable = not excluded and db.directDebuffDispellableMode == "ALL" and allDispellable and AuraPassesDebuffOnlyMine(unit, id, db)
        if isBoss or passesFilters or passesAllDispellable then
            cache.debuffs[id] = true
        end
        if dispelFilter and AuraPassesAnyFilter(unit, id, { dispelFilter }) then
            cache.playerDispellable[id] = true
        end
        if crowdControlFilter and AuraPassesFilterStrict(unit, id, crowdControlFilter) then
            cache.crowdControls[id] = true
        end
        local categoryScale = not excluded and GetMatchedCategoryScale(unit, id, debuffCategoryScaleFilters, db) or nil
        cache.categoryScales[id] = categoryScale and categoryScale ~= 1 and categoryScale or nil
        DebugLogAuraClassification(cache, unit, auraData, kind)
    end
end

local function UnclassifyAura(cache, id, preserveLongBuff)
    cache.buffs[id] = nil
    cache.debuffs[id] = nil
    if not preserveLongBuff then
        cache.longBuffs[id] = nil
        if cache.priorityLongBuffExemptions then
            cache.priorityLongBuffExemptions[id] = nil
        end
    end
    cache.defensives[id] = nil
    cache.playerDispellable[id] = nil
    cache.allDispellable[id] = nil
    cache.crowdControls[id] = nil
    cache.categoryScales[id] = nil
end

local function SetAuraOrder(cache, id, order)
    if not id then return end
    if cache.orderByID[id] then return end
    order = tonumber(order)
    if not order then
        cache.nextOrder = (cache.nextOrder or 0) + 1
        order = cache.nextOrder
    end
    cache.orderByID[id] = order
    if order > (cache.nextOrder or 0) then
        cache.nextOrder = order
    end
end

local function GetAuraExpirationForSort(auraData)
    local exp = Util.AsSafeNumber(auraData and auraData.expirationTime, 0) or 0
    return exp > 0 and exp or math.huge
end

local function GetAuraAppliedTimeForSort(auraData)
    local exp = Util.AsSafeNumber(auraData and auraData.expirationTime, 0) or 0
    local duration = Util.AsSafeNumber(auraData and auraData.duration, 0) or 0
    if exp > 0 and duration > 0 then
        return exp - duration
    end
    return nil
end

-- 12.0.7 does not expose a native "latest applied" aura sort. Keep exact
-- applied timestamps when they are readable out of combat, then use the time
-- at which UNIT_AURA reports an add/update as a combat-safe best-effort rank.
local function SetLatestAuraOrder(cache, id, auraData, isDelta)
    if Util.IsSecretValue(id) or id == nil then return end

    cache.latestOrderByID = cache.latestOrderByID or {}
    local order
    if not IsPlayerInCombat() then
        order = GetAuraAppliedTimeForSort(auraData)
    end

    if order == nil then
        if not isDelta and cache.latestOrderByID[id] ~= nil then return end

        if isDelta then
            local nextOrder = cache.nextLatestOrder or 0
            if type(GetTime) == "function" then
                order = Util.AsSafeNumber(GetTime())
            end
            if order == nil or order <= nextOrder then
                order = nextOrder + LATEST_ORDER_INCREMENT
            end
        else
            cache.nextUnknownLatestOrder = (cache.nextUnknownLatestOrder or 0) + 1
            order = -1 / cache.nextUnknownLatestOrder
        end
    end

    cache.latestOrderByID[id] = order
    if order > (cache.nextLatestOrder or 0) then
        cache.nextLatestOrder = order
    end
end

local function GetAuraNameForSort(auraData)
    local name = auraData and auraData.name
    if Util.IsSecretValue(name) then return nil end
    return type(name) == "string" and name or nil
end

local function CompareSortValues(aValue, bValue, reverse)
    if aValue == bValue then return nil end
    if reverse then
        return aValue > bValue
    end
    return aValue < bValue
end

local function SortByTimeRemaining(a, b, reverse)
    local aExp = GetAuraExpirationForSort(a)
    local bExp = GetAuraExpirationForSort(b)
    return CompareSortValues(aExp, bExp, reverse)
end

local function SortByReadableName(a, b, reverse)
    local aName = GetAuraNameForSort(a)
    local bName = GetAuraNameForSort(b)
    local aKnown = aName ~= nil
    local bKnown = bName ~= nil
    if aKnown ~= bKnown then
        return aKnown
    end
    if not aKnown then return nil end
    return CompareSortValues(aName, bName, reverse)
end

-- Aura names can be secret during 12.x combat restrictions. Ask Blizzard to
-- perform the name sort, then compare only the returned aura-instance ranks.
local function RefreshNativeNameOrder(unit, scanFilter, reverse)
    Util.WipeTable(NameOrderByID)
    if not GetUnitAuraInstanceIDs or NAME_ONLY_SORT_RULE == nil then return false end

    local sortDirection = reverse and REVERSE_SORT_DIRECTION or NORMAL_SORT_DIRECTION
    if sortDirection == nil then return false end

    Util.PerfCount("LiveAuraCall")
    local ok, auraInstanceIDs = pcall(
        GetUnitAuraInstanceIDs,
        unit,
        scanFilter,
        nil,
        NAME_ONLY_SORT_RULE,
        sortDirection
    )
    if not ok or type(auraInstanceIDs) ~= "table" or Util.IsSecretValue(auraInstanceIDs) then
        return false
    end

    local ranked = pcall(function()
        for i = 1, #auraInstanceIDs do
            local id = auraInstanceIDs[i]
            if not Util.IsSecretValue(id) and id ~= nil then
                NameOrderByID[id] = i
            end
        end
    end)
    if not ranked then
        Util.WipeTable(NameOrderByID)
        return false
    end
    return true
end

local function SortByNativeNameOrder(a, b)
    local aID = a and a.auraInstanceID
    local bID = b and b.auraInstanceID
    local aRank = not Util.IsSecretValue(aID) and aID ~= nil and NameOrderByID[aID] or nil
    local bRank = not Util.IsSecretValue(bID) and bID ~= nil and NameOrderByID[bID] or nil
    local aKnown = aRank ~= nil
    local bKnown = bRank ~= nil
    if aKnown ~= bKnown then
        return aKnown
    end
    if not aKnown then return nil end
    return CompareSortValues(aRank, bRank, false)
end

local function GetAuraScaleForSort(cache, auraData)
    local id = auraData and auraData.auraInstanceID
    return id and cache.categoryScales[id] or 1
end

local function SortByDefaultOrder(cache, a, b, reverse)
    local missingOrder = reverse and -math.huge or math.huge
    local aOrder = cache.orderByID[a and a.auraInstanceID] or missingOrder
    local bOrder = cache.orderByID[b and b.auraInstanceID] or missingOrder
    local sorted = CompareSortValues(aOrder, bOrder, reverse)
    if sorted ~= nil then
        return sorted
    end
    local aID = a and a.auraInstanceID or 0
    local bID = b and b.auraInstanceID or 0
    return CompareSortValues(aID, bID, reverse) or false
end

local function SortByLatestApplied(cache, a, b, reverse)
    local latestOrderByID = cache.latestOrderByID
    local aID = a and a.auraInstanceID
    local bID = b and b.auraInstanceID
    local aApplied = latestOrderByID and not Util.IsSecretValue(aID) and aID ~= nil and latestOrderByID[aID] or nil
    local bApplied = latestOrderByID and not Util.IsSecretValue(bID) and bID ~= nil and latestOrderByID[bID] or nil
    local missingOrder = -math.huge
    local sorted = CompareSortValues(aApplied or missingOrder, bApplied or missingOrder, not reverse)
    if sorted ~= nil then
        return sorted
    end
    return SortByDefaultOrder(cache, a, b, not reverse)
end

local function SortAuras(cache, auraList, sortOrder, bigIconsFirst, reverse, nativeNameOrderAvailable)
    if #auraList <= 1 then return end
    table.sort(auraList, function(a, b)
        if bigIconsFirst then
            local aScale = GetAuraScaleForSort(cache, a)
            local bScale = GetAuraScaleForSort(cache, b)
            if aScale ~= bScale then
                return aScale > bScale
            end
        end
        local sorted
        if sortOrder == "TIME" then
            sorted = SortByTimeRemaining(a, b, reverse)
        elseif sortOrder == "LATEST" then
            sorted = SortByLatestApplied(cache, a, b, reverse)
        elseif sortOrder == "NAME" then
            if nativeNameOrderAvailable then
                sorted = SortByNativeNameOrder(a, b)
            else
                sorted = SortByReadableName(a, b, reverse)
            end
        end
        if sorted ~= nil then
            return sorted
        end
        return SortByDefaultOrder(cache, a, b, reverse)
    end)
end

local function RebuildSortedBuffArray(cache, db, unit)
    Util.WipeTable(State.sortScratchBuffs)
    for id, auraData in pairs(cache.buffsByID) do
        if cache.buffs[id] and not HideMarkedLongBuff(cache, id, unit, db, auraData) then
            State.sortScratchBuffs[#State.sortScratchBuffs + 1] = auraData
        end
    end
    local nativeNameOrderAvailable = false
    if #State.sortScratchBuffs > 1 and db.directBuffSortOrder == "NAME" then
        nativeNameOrderAvailable = RefreshNativeNameOrder(
            unit,
            BuildHelpfulScanFilter(db),
            db.directBuffSortReverse == true
        )
    end
    SortAuras(cache, State.sortScratchBuffs, db.directBuffSortOrder, db.directBuffSortBigIconsFirst == true, db.directBuffSortReverse == true, nativeNameOrderAvailable)
    Util.WipeTable(cache.buffData)
    for i = 1, #State.sortScratchBuffs do
        cache.buffData[i] = State.sortScratchBuffs[i]
    end
    cache.buffOrderDirty = false
end

local function RebuildSortedDebuffArray(cache, db, unit)
    Util.WipeTable(State.sortScratchDebuffs)
    for id, auraData in pairs(cache.debuffsByID) do
        if cache.debuffs[id] then
            State.sortScratchDebuffs[#State.sortScratchDebuffs + 1] = auraData
        end
    end
    local nativeNameOrderAvailable = false
    if #State.sortScratchDebuffs > 1 and db.directDebuffSortOrder == "NAME" then
        nativeNameOrderAvailable = RefreshNativeNameOrder(
            unit,
            BuildHarmfulScanFilter(db),
            db.directDebuffSortReverse == true
        )
    end
    SortAuras(cache, State.sortScratchDebuffs, db.directDebuffSortOrder, db.directDebuffSortBigIconsFirst == true, db.directDebuffSortReverse == true, nativeNameOrderAvailable)
    Util.WipeTable(cache.debuffData)
    for i = 1, #State.sortScratchDebuffs do
        cache.debuffData[i] = State.sortScratchDebuffs[i]
    end
    cache.debuffOrderDirty = false
end

local function RebuildSortedArrays(cache, db, auraType, unit)
    if auraType == "BUFF" then
        RebuildSortedBuffArray(cache, db, unit)
        return
    end
    if auraType == "DEBUFF" then
        RebuildSortedDebuffArray(cache, db, unit)
        return
    end

    RebuildSortedBuffArray(cache, db, unit)
    RebuildSortedDebuffArray(cache, db, unit)
end

local function AddScannedAuraData(
    cache,
    unit,
    db,
    auraType,
    auraTable,
    buffFilters,
    debuffFilters,
    defFilters,
    dispelFilter,
    buffCategoryScaleFilters,
    debuffCategoryScaleFilters,
    crowdControlFilter,
    buffExclusionFilters,
    debuffExclusionFilters,
    auraData
)
    if auraData and auraData.auraInstanceID then
        auraTable[auraData.auraInstanceID] = auraData
        SetAuraOrder(cache, auraData.auraInstanceID)
        local newlyObservedInCombat = cache.preserveLatestOrderDuringScan == true
            and cache.latestOrderByID[auraData.auraInstanceID] == nil
        SetLatestAuraOrder(cache, auraData.auraInstanceID, auraData, newlyObservedInCombat)
        ClassifyAura(
            cache,
            unit,
            auraData,
            auraType,
            buffFilters,
            debuffFilters,
            defFilters,
            dispelFilter,
            db,
            buffCategoryScaleFilters,
            debuffCategoryScaleFilters,
            crowdControlFilter,
            buffExclusionFilters,
            debuffExclusionFilters
        )
    end
end

local function ProcessAuraSlots(
    cache,
    unit,
    db,
    auraType,
    auraTable,
    buffFilters,
    debuffFilters,
    defFilters,
    dispelFilter,
    buffCategoryScaleFilters,
    debuffCategoryScaleFilters,
    crowdControlFilter,
    buffExclusionFilters,
    debuffExclusionFilters,
    continuationToken,
    ...
)
    for i = 1, select("#", ...) do
        local slot = select(i, ...)
        Util.PerfCount("LiveAuraCall")
        local auraData = GetAuraDataBySlot(unit, slot)
        AddScannedAuraData(
            cache,
            unit,
            db,
            auraType,
            auraTable,
            buffFilters,
            debuffFilters,
            defFilters,
            dispelFilter,
            buffCategoryScaleFilters,
            debuffCategoryScaleFilters,
            crowdControlFilter,
            buffExclusionFilters,
            debuffExclusionFilters,
            auraData
        )
    end
    return continuationToken
end

local function AddAuraDataFromDelta(
    cache,
    unit,
    auraData,
    scanBuffs,
    scanDebuffs,
    buffScanFilter,
    debuffScanFilter,
    buffFilters,
    debuffFilters,
    defFilters,
    dispelFilter,
    db,
    buffCategoryScaleFilters,
    debuffCategoryScaleFilters,
    crowdControlFilter,
    buffExclusionFilters,
    debuffExclusionFilters
)
    local id = auraData and auraData.auraInstanceID
    if not id or not IsAuraFilteredOut then return false end

    if scanBuffs and AuraPassesFilterStrict(unit, id, buffScanFilter) then
        cache.buffsByID[id] = auraData
        SetAuraOrder(cache, id)
        SetLatestAuraOrder(cache, id, auraData, true)
        ClassifyAura(cache, unit, auraData, "buff", buffFilters, debuffFilters, defFilters, dispelFilter, db, buffCategoryScaleFilters, debuffCategoryScaleFilters, crowdControlFilter, buffExclusionFilters, debuffExclusionFilters)
        cache.buffOrderDirty = true
        return true
    end

    if scanDebuffs and AuraPassesFilterStrict(unit, id, debuffScanFilter) then
        cache.debuffsByID[id] = auraData
        SetAuraOrder(cache, id)
        SetLatestAuraOrder(cache, id, auraData, true)
        ClassifyAura(cache, unit, auraData, "debuff", buffFilters, debuffFilters, defFilters, dispelFilter, db, buffCategoryScaleFilters, debuffCategoryScaleFilters, crowdControlFilter, buffExclusionFilters, debuffExclusionFilters)
        cache.debuffOrderDirty = true
        return true
    end

    return false
end

local function ProcessAuraSlotPages(
    cache,
    unit,
    db,
    auraType,
    auraTable,
    buffFilters,
    debuffFilters,
    defFilters,
    dispelFilter,
    buffCategoryScaleFilters,
    debuffCategoryScaleFilters,
    crowdControlFilter,
    buffExclusionFilters,
    debuffExclusionFilters,
    scanFilter
)
    local continuationToken
    repeat
        Util.PerfCount("LiveAuraCall")
        continuationToken = ProcessAuraSlots(
            cache,
            unit,
            db,
            auraType,
            auraTable,
            buffFilters,
            debuffFilters,
            defFilters,
            dispelFilter,
            buffCategoryScaleFilters,
            debuffCategoryScaleFilters,
            crowdControlFilter,
            buffExclusionFilters,
            debuffExclusionFilters,
            GetAuraSlots(unit, scanFilter, nil, continuationToken)
        )
    until not continuationToken
end

local function ProcessAuraList(
    cache,
    unit,
    db,
    auraType,
    auraTable,
    buffFilters,
    debuffFilters,
    defFilters,
    dispelFilter,
    buffCategoryScaleFilters,
    debuffCategoryScaleFilters,
    crowdControlFilter,
    buffExclusionFilters,
    debuffExclusionFilters,
    scanFilter
)
    if not GetUnitAuras then return false end
    Util.PerfCount("LiveAuraCall")
    local auras = GetUnitAuras(unit, scanFilter)
    if type(auras) ~= "table" then return false end

    for i = 1, #auras do
        AddScannedAuraData(
            cache,
            unit,
            db,
            auraType,
            auraTable,
            buffFilters,
            debuffFilters,
            defFilters,
            dispelFilter,
            buffCategoryScaleFilters,
            debuffCategoryScaleFilters,
            crowdControlFilter,
            buffExclusionFilters,
            debuffExclusionFilters,
            auras[i]
        )
    end

    return true
end

local function ProcessAuraFullScan(
    cache,
    unit,
    db,
    auraType,
    auraTable,
    buffFilters,
    debuffFilters,
    defFilters,
    dispelFilter,
    buffCategoryScaleFilters,
    debuffCategoryScaleFilters,
    crowdControlFilter,
    buffExclusionFilters,
    debuffExclusionFilters,
    scanFilter
)
    if GetAuraSlots and GetAuraDataBySlot then
        ProcessAuraSlotPages(
            cache,
            unit,
            db,
            auraType,
            auraTable,
            buffFilters,
            debuffFilters,
            defFilters,
            dispelFilter,
            buffCategoryScaleFilters,
            debuffCategoryScaleFilters,
            crowdControlFilter,
            buffExclusionFilters,
            debuffExclusionFilters,
            scanFilter
        )
        return true
    end

    return ProcessAuraList(
        cache,
        unit,
        db,
        auraType,
        auraTable,
        buffFilters,
        debuffFilters,
        defFilters,
        dispelFilter,
        buffCategoryScaleFilters,
        debuffCategoryScaleFilters,
        crowdControlFilter,
        buffExclusionFilters,
        debuffExclusionFilters,
        scanFilter
    )
end

function RaidFrameAuras:ScanUnitFull(unit)
    if not self:IsTrackedUnit(unit) or not UnitExists(unit) or not ((GetAuraSlots and GetAuraDataBySlot) or GetUnitAuras) then
        return false
    end
    Util.PerfCount("ScanUnitFull")
    local perf = Util.PerfBegin("ScanUnitFull")
    local cache = EnsureAuraCacheEntry(unit)
    local currentGUID = GetUnitCacheGUID(unit)
    local preserveLatestOrder = IsPlayerInCombat()
        and currentGUID ~= nil
        and cache.unitGUID ~= nil
        and cache.unitGUID ~= false
        and cache.unitGUID == currentGUID
    cache.unitGUID = currentGUID or false
    Util.WipeTable(cache.buffsByID)
    Util.WipeTable(cache.debuffsByID)
    if not IsPlayerInCombat() then
        Util.WipeTable(cache.longBuffs)
        if cache.priorityLongBuffExemptions then
            Util.WipeTable(cache.priorityLongBuffExemptions)
        end
    end
    Util.WipeTable(cache.buffs)
    Util.WipeTable(cache.debuffs)
    Util.WipeTable(cache.defensives)
    Util.WipeTable(cache.playerDispellable)
    Util.WipeTable(cache.allDispellable)
    Util.WipeTable(cache.crowdControls)
    Util.WipeTable(cache.categoryScales)
    Util.WipeTable(cache.orderByID)
    cache.nextOrder = 0
    cache.latestOrderByID = cache.latestOrderByID or {}
    if not preserveLatestOrder then
        Util.WipeTable(cache.latestOrderByID)
        cache.nextLatestOrder = 0
        cache.nextUnknownLatestOrder = 0
    end
    cache.preserveLatestOrderDuringScan = preserveLatestOrder or nil

    local buffFilters, debuffFilters, defFilters, dispelFilter, buffCategoryScaleFilters, debuffCategoryScaleFilters, crowdControlFilter, buffScanFilter, debuffScanFilter, buffExclusionFilters, debuffExclusionFilters = ResolveFilters()
    local db = self.db
    local scanBuffs = db.showBuffs == true
    local scanDebuffs = db.showDebuffs == true

    if scanBuffs then
        ProcessAuraFullScan(
            cache,
            unit,
            db,
            "buff",
            cache.buffsByID,
            buffFilters,
            debuffFilters,
            defFilters,
            dispelFilter,
            buffCategoryScaleFilters,
            debuffCategoryScaleFilters,
            crowdControlFilter,
            buffExclusionFilters,
            debuffExclusionFilters,
            buffScanFilter
        )
    end

    if scanDebuffs then
        ProcessAuraFullScan(
            cache,
            unit,
            db,
            "debuff",
            cache.debuffsByID,
            buffFilters,
            debuffFilters,
            defFilters,
            dispelFilter,
            buffCategoryScaleFilters,
            debuffCategoryScaleFilters,
            crowdControlFilter,
            buffExclusionFilters,
            debuffExclusionFilters,
            debuffScanFilter
        )
    end
    cache.preserveLatestOrderDuringScan = nil

    for id in pairs(cache.latestOrderByID) do
        if cache.buffsByID[id] == nil and cache.debuffsByID[id] == nil then
            cache.latestOrderByID[id] = nil
        end
    end

    RebuildSortedArrays(cache, db, nil, unit)
    cache.hasFullScan = true
    BumpAuraCacheGeneration(cache)
    Util.PerfEnd("ScanUnitFull", perf)
    return true
end

function RaidFrameAuras:ApplyAuraDelta(unit, updateInfo)
    if not self:IsTrackedUnit(unit) or not updateInfo then return false end
    local cache = EnsureAuraCacheEntry(unit)
    cache.latestOrderByID = cache.latestOrderByID or {}
    if not cache.hasFullScan then return false end
    if self:IsAuraCacheStale(unit, cache) then
        State.auraCache[unit] = nil
        return false
    end

    local buffFilters, debuffFilters, defFilters, dispelFilter, buffCategoryScaleFilters, debuffCategoryScaleFilters, crowdControlFilter, buffScanFilter, debuffScanFilter, buffExclusionFilters, debuffExclusionFilters = ResolveFilters()
    local db = self.db
    local scanBuffs = db.showBuffs == true
    local scanDebuffs = db.showDebuffs == true
    local changed = false

    if updateInfo.addedAuras then
        for _, auraData in ipairs(updateInfo.addedAuras) do
            if AddAuraDataFromDelta(cache, unit, auraData, scanBuffs, scanDebuffs, buffScanFilter, debuffScanFilter, buffFilters, debuffFilters, defFilters, dispelFilter, db, buffCategoryScaleFilters, debuffCategoryScaleFilters, crowdControlFilter, buffExclusionFilters, debuffExclusionFilters) then
                changed = true
            end
        end
    end

    if updateInfo.updatedAuraInstanceIDs then
        for _, id in ipairs(updateInfo.updatedAuraInstanceIDs) do
            if cache.buffsByID[id] then
                if not scanBuffs then
                    cache.buffsByID[id] = nil
                    cache.orderByID[id] = nil
                    cache.latestOrderByID[id] = nil
                    UnclassifyAura(cache, id)
                    cache.buffOrderDirty = true
                    changed = true
                else
                    Util.PerfCount("LiveAuraCall")
                    local fresh = GetAuraDataByAuraInstanceID and GetAuraDataByAuraInstanceID(unit, id)
                    if fresh then
                        cache.buffsByID[id] = fresh
                        SetLatestAuraOrder(cache, id, fresh, true)
                        UnclassifyAura(cache, id, IsPlayerInCombat())
                        ClassifyAura(cache, unit, fresh, "buff", buffFilters, debuffFilters, defFilters, dispelFilter, db, buffCategoryScaleFilters, debuffCategoryScaleFilters, crowdControlFilter, buffExclusionFilters, debuffExclusionFilters)
                        cache.buffOrderDirty = true
                        changed = true
                    end
                end
            elseif cache.debuffsByID[id] then
                if not scanDebuffs then
                    cache.debuffsByID[id] = nil
                    cache.orderByID[id] = nil
                    cache.latestOrderByID[id] = nil
                    UnclassifyAura(cache, id)
                    cache.debuffOrderDirty = true
                    changed = true
                else
                    Util.PerfCount("LiveAuraCall")
                    local fresh = GetAuraDataByAuraInstanceID and GetAuraDataByAuraInstanceID(unit, id)
                    if fresh then
                        cache.debuffsByID[id] = fresh
                        SetLatestAuraOrder(cache, id, fresh, true)
                        UnclassifyAura(cache, id)
                        ClassifyAura(cache, unit, fresh, "debuff", buffFilters, debuffFilters, defFilters, dispelFilter, db, buffCategoryScaleFilters, debuffCategoryScaleFilters, crowdControlFilter, buffExclusionFilters, debuffExclusionFilters)
                        cache.debuffOrderDirty = true
                        changed = true
                    end
                end
            else
                Util.PerfCount("LiveAuraCall")
                local fresh = GetAuraDataByAuraInstanceID and GetAuraDataByAuraInstanceID(unit, id)
                if AddAuraDataFromDelta(cache, unit, fresh, scanBuffs, scanDebuffs, buffScanFilter, debuffScanFilter, buffFilters, debuffFilters, defFilters, dispelFilter, db, buffCategoryScaleFilters, debuffCategoryScaleFilters, crowdControlFilter, buffExclusionFilters, debuffExclusionFilters) then
                    changed = true
                end
            end
        end
    end

    if updateInfo.removedAuraInstanceIDs then
        for _, id in ipairs(updateInfo.removedAuraInstanceIDs) do
            if cache.buffsByID[id] then
                cache.buffsByID[id] = nil
                cache.orderByID[id] = nil
                cache.latestOrderByID[id] = nil
                UnclassifyAura(cache, id)
                cache.buffOrderDirty = true
                changed = true
            elseif cache.debuffsByID[id] then
                cache.debuffsByID[id] = nil
                cache.orderByID[id] = nil
                cache.latestOrderByID[id] = nil
                UnclassifyAura(cache, id)
                cache.debuffOrderDirty = true
                changed = true
            end
        end
    end

    local rebuildBuffs = cache.buffOrderDirty == true
    local rebuildDebuffs = cache.debuffOrderDirty == true

    if rebuildBuffs then
        RebuildSortedArrays(cache, db, "BUFF", unit)
    end
    if rebuildDebuffs then
        RebuildSortedArrays(cache, db, "DEBUFF", unit)
    end
    if rebuildBuffs or rebuildDebuffs then
        BumpAuraCacheGeneration(cache)
        changed = true
    end
    return true, changed
end

function RaidFrameAuras:GetAuraCache(unit)
    return State.auraCache and State.auraCache[unit]
end

function RaidFrameAuras:IsAuraFilterAvailable(filterKey)
    return filterKey ~= nil and AuraFilters[filterKey] ~= nil
end

function RaidFrameAuras:GetUnitCacheGUID(unit)
    return GetUnitCacheGUID(unit)
end

function RaidFrameAuras:IsAuraCacheStale(unit, cache)
    if not cache then return false end
    local cachedGUID = cache.unitGUID
    if cachedGUID == nil then return false end
    local currentGUID = GetUnitCacheGUID(unit)
    return currentGUID ~= nil and currentGUID ~= cachedGUID
end

function RaidFrameAuras:ClearAuraCache(unit)
    if unit and State.auraCache then
        State.auraCache[unit] = nil
    end
end

function RaidFrameAuras:UnclassifyAura(cache, id)
    return UnclassifyAura(cache, id)
end

function RaidFrameAuras:RebuildSortedArrays(cache, db, auraType, unit)
    return RebuildSortedArrays(cache, db, auraType, unit)
end

function RaidFrameAuras:RefreshCombatSensitiveBuffVisibility()
    local db = self.db
    if not db or db.showBuffs ~= true then return false end
    if db.directBuffHideLong ~= true and db.directBuffFilterRaidHideInCombat ~= true then
        return false
    end

    if db.directBuffFilterRaidHideInCombat == true then
        State.filtersDirty = true
    end

    local buffFilters, debuffFilters, defFilters, dispelFilter, buffCategoryScaleFilters, debuffCategoryScaleFilters, crowdControlFilter, _, _, buffExclusionFilters, debuffExclusionFilters = ResolveFilters()
    local preserveLongBuffs = IsPlayerInCombat()
    local changed = false

    for unit, cache in pairs(State.auraCache) do
        if cache and cache.hasFullScan and next(cache.buffsByID) ~= nil then
            for id in pairs(cache.buffsByID) do
                UnclassifyAura(cache, id, preserveLongBuffs)
            end

            for _, auraData in pairs(cache.buffsByID) do
                ClassifyAura(cache, unit, auraData, "buff", buffFilters, debuffFilters, defFilters, dispelFilter, db, buffCategoryScaleFilters, debuffCategoryScaleFilters, crowdControlFilter, buffExclusionFilters, debuffExclusionFilters)
            end

            RebuildSortedArrays(cache, db, nil, unit)
            BumpAuraCacheGeneration(cache)
            changed = true
        end
    end

    return changed
end

function RaidFrameAuras:RefreshLongBuffVisibility()
    local db = self.db
    if not db or db.directBuffHideLong ~= true then return false end

    local inCombat = IsPlayerInCombat()
    if inCombat and not HasAnyLongBuffMarker() then return false end

    local changed = false
    for unit, cache in pairs(State.auraCache) do
        if cache and cache.hasFullScan then
            if inCombat then
                -- Preserve the existing out-of-combat sort order; only remove buffs that
                -- were already marked long before combat. No aura duration, expiration,
                -- name, scale, or sort comparisons are performed here.
                local originalCount = #cache.buffData
                local keptCount = 0
                Util.WipeTable(State.sortScratchBuffs)
                for i = 1, originalCount do
                    local auraData = cache.buffData[i]
                    local id = auraData and auraData.auraInstanceID
                    if id and not HideMarkedLongBuff(cache, id, unit, db, auraData) then
                        keptCount = keptCount + 1
                        State.sortScratchBuffs[keptCount] = auraData
                    end
                end

                if keptCount ~= originalCount then
                    Util.WipeTable(cache.buffData)
                    for i = 1, keptCount do
                        cache.buffData[i] = State.sortScratchBuffs[i]
                    end
                    cache.buffOrderDirty = false
                    BumpAuraCacheGeneration(cache)
                    changed = true
                end
            else
                RebuildSortedArrays(cache, db, nil, unit)
                BumpAuraCacheGeneration(cache)
                changed = true
            end
        end
    end

    return changed
end

function RaidFrameAuras:InvalidateAuraData()
    State.filtersDirty = true
    State.cachedBuffFilters = nil
    State.cachedDebuffFilters = nil
    State.cachedBuffCategoryScaleFilters = nil
    State.cachedDebuffCategoryScaleFilters = nil
    State.cachedBuffCategoryExclusionFilters = nil
    State.cachedDebuffCategoryExclusionFilters = nil
    State.cachedCrowdControlFilter = nil
    State.cachedBuffScanFilter = nil
    State.cachedDebuffScanFilter = nil
    State.cachedDefensiveFilters = nil
    State.cachedDispelFilter = nil
    State.debuffBorderCurve = nil
    State.durationColorCurve = nil
    State.durationHideCurves = {}
    State.expiringBorderColorCurve = nil
    State.expiringCurves = {}
    State.longBuffSpellIDs = {}
    for unit in pairs(State.auraCache) do
        State.auraCache[unit] = nil
    end
end
