local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local Monitor = YUI.Monitor
local Item = YUI.API and YUI.API.Item
local Spell = YUI.API and YUI.API.Spell
local Unit = YUI.API and YUI.API.Unit
local Combat = YUI.API and YUI.API.Combat
local Talent = YUI.API and YUI.API.Talent
local CooldownViewer = YUI.API and YUI.API.CooldownViewer
local SpecialResources = YHUD.SpecialResources
local Bloodlust = YUI.Bloodlust
local ResourceCatalog = YHUD.ResourceCatalog
if not Monitor then return end

local Sources = YHUD.Sources or {}
YHUD.Sources = Sources

local SLOT_SOURCE_TYPE = "yhud.inventory-slot-cooldown"
local SPELL_SOURCE_TYPE = "spell-cooldown"
local ITEM_SOURCE_TYPE = "item-cooldown"
local RESOURCE_SOURCE_TYPE = "yhud.unit-power"
local CHARGE_RESOURCE_SOURCE_TYPE = "yhud.spell-charge-resource"
local PLAYER_AURA_RESOURCE_SOURCE_TYPE = "yhud.player-aura-stack-resource"
local TARGET_AURA_RESOURCE_SOURCE_TYPE = "yhud.target-aura-stack-resource"
local SIMULATED_RESOURCE_SOURCE_TYPE = "yhud.simulated-stack-resource"
local RUNE_RESOURCE_SOURCE_TYPE = "yhud.rune-cooldown-resource"
local SPELL_COUNT_RESOURCE_SOURCE_TYPE = "yhud.spell-count-resource"
local ADAPTIVE_AURA_RESOURCE_SOURCE_TYPE = "yhud.adaptive-aura-resource"
local STAGGER_RESOURCE_SOURCE_TYPE = "yhud.stagger-resource"
local ABSORB_RESOURCE_SOURCE_TYPE = "yhud.absorb-resource"
local AURA_DURATION_RESOURCE_SOURCE_TYPE = "yhud.aura-duration-resource"
local IRONFUR_RESOURCE_SOURCE_TYPE = "yhud.ironfur-timer-resource"
local SWING_RESOURCE_SOURCE_TYPE = "yhud.player-swing"
local BUFF_TIMER_SOURCE_TYPE = YHUD.CAST_BUFF_TIMER_SOURCE_TYPE
    or "yhud.cast-buff-timer"
local SPELL_EVENT_WINDOW_SOURCE_TYPE = YHUD.SPELL_EVENT_WINDOW_SOURCE_TYPE
    or "yhud.spell-event-window"
local PLAYER_AURA_SOURCE_TYPE = YHUD.PLAYER_AURA_SOURCE_TYPE
    or "yhud.player-aura"
local OFFICIAL_AURA_SOURCE_TYPE = "yhud.official-cdm-aura"
local BLOODLUST_SOURCE_TYPE = "yhud.bloodlust-window"
local FILTERED_AURA_RESOURCE_TYPES = {
    [PLAYER_AURA_RESOURCE_SOURCE_TYPE] = true,
    [TARGET_AURA_RESOURCE_SOURCE_TYPE] = true,
    [ADAPTIVE_AURA_RESOURCE_SOURCE_TYPE] = true,
    [AURA_DURATION_RESOURCE_SOURCE_TYPE] = true,
}
local PLAYER_FILTERED_AURA_RESOURCE_TYPES = {
    [PLAYER_AURA_RESOURCE_SOURCE_TYPE] = true,
    [ADAPTIVE_AURA_RESOURCE_SOURCE_TYPE] = true,
    [AURA_DURATION_RESOURCE_SOURCE_TYPE] = true,
}
local TRANSIENT_REHYDRATE_TYPES = {
    [SPELL_SOURCE_TYPE] = true,
    [OFFICIAL_AURA_SOURCE_TYPE] = true,
    [RESOURCE_SOURCE_TYPE] = true,
    [CHARGE_RESOURCE_SOURCE_TYPE] = true,
    [RUNE_RESOURCE_SOURCE_TYPE] = true,
    [AURA_DURATION_RESOURCE_SOURCE_TYPE] = true,
    [IRONFUR_RESOURCE_SOURCE_TYPE] = true,
    [SWING_RESOURCE_SOURCE_TYPE] = true,
}
local GLOBAL_RECOVERY_CATEGORY = Constants
    and Constants.SpellCooldownConsts
    and Constants.SpellCooldownConsts.GLOBAL_RECOVERY_CATEGORY
    or 133
local SPELL_BUNDLE_KINDS = { "defensive", "interruptControl" }
local EQUIPMENT_TRIGGER_BUNDLE_ENTRY_KEY =
    YHUD.EQUIPMENT_AURA_BUNDLE_ENTRY_KEY or "bundle:equipment-auras"
local EQUIPMENT_TRIGGER_BUNDLE_MONITOR_ID =
    YHUD.EQUIPMENT_AURA_BUNDLE_MONITOR_ID
    or "monitor:bundle:equipment-auras"
local AURA_APPLICATION_MAX_SETTLE_DELAY = 0.2
local RESOURCE_WORLD_SETTLE_DELAY = 0.5
local AURA_CONTROL_RETRY_DELAY = 0.3
local AURA_CONTROL_RETRY_LIMIT = 50

Sources.handles = Sources.handles or {}
Sources.timedWindows = Sources.timedWindows or Sources.buffTimers or {}
Sources.buffTimers = Sources.timedWindows
Sources.bloodlustSourceKeys = Sources.bloodlustSourceKeys or {}
Sources.racialSignature = Sources.racialSignature or {}
Sources.bundleSignature = Sources.bundleSignature or {}
Sources.activeResourceKeys = Sources.activeResourceKeys or {}
Sources.resourcePresetScratch = Sources.resourcePresetScratch or {}
Sources.activeResourceProjectionKeys = Sources.activeResourceProjectionKeys or {}
Sources.resourceProjectionScratch = Sources.resourceProjectionScratch or {}
Sources.auraApplicationMaxCache = Sources.auraApplicationMaxCache or {}
Sources.talentMaxCache = Sources.talentMaxCache or {}
Sources.talentMaxRetryCount = 0
Sources.activeTraitSpellScratch = Sources.activeTraitSpellScratch or {}
Sources.auraApplicationMaxSpellIDs =
    Sources.auraApplicationMaxSpellIDs or {}
Sources.auraApplicationMaxRefreshPending =
    Sources.auraApplicationMaxRefreshPending == true
Sources.auraApplicationMaxSettleRequested =
    Sources.auraApplicationMaxSettleRequested == true
Sources.auraApplicationMaxSettleTimer =
    Sources.auraApplicationMaxSettleTimer or nil
Sources.resourceWorldSettleTimer = Sources.resourceWorldSettleTimer or nil
Sources.resourceWorldSettlePending =
    Sources.resourceWorldSettlePending == true
Sources.auraControlRefreshTimer = Sources.auraControlRefreshTimer or nil
Sources.auraControlRecoveryPending =
    Sources.auraControlRecoveryPending == true
Sources.auraControlRetryCount =
    type(Sources.auraControlRetryCount) == "number"
    and Sources.auraControlRetryCount or 0
if type(Sources.auraIdentityTrusted) ~= "boolean" then
    Sources.auraIdentityTrusted = nil
end
Sources.activeTrinketItemBySlot = Sources.activeTrinketItemBySlot or {}
Sources.activeTrinketProjectionSignature =
    type(Sources.activeTrinketProjectionSignature) == "string"
    and Sources.activeTrinketProjectionSignature or nil
Sources.activeTrinketProjectionPending =
    Sources.activeTrinketProjectionPending == true
Sources.bloodlustSnapshot = Sources.bloodlustSnapshot or {
    active = false,
    startTime = 0,
    duration = 40,
    revision = 0,
}
Sources.active = Sources.active == true

local function ProfileNowMS()
    if YHUD.performanceDiagnosticsEnabled ~= true
        or type(debugprofilestop) ~= "function" then
        return nil
    end
    local ok, value = pcall(debugprofilestop)
    return ok and type(value) == "number" and value or nil
end

local function AddPerformanceStat(field, amount)
    if YHUD.Stats then YHUD.Stats:Add(field, amount) end
end

local function FinishPerformanceStat(field, startedAt)
    if not startedAt then return end
    local finishedAt = ProfileNowMS()
    if finishedAt then
        AddPerformanceStat(field, math.max(0, finishedAt - startedAt))
    end
end

local function AuraControlRefreshTimerCallback()
    Sources.auraControlRefreshTimer = nil
    Sources:FlushAuraControlRefresh()
end

local function AuraApplicationMaxSettleTimerCallback()
    Sources.auraApplicationMaxSettleTimer = nil
    Sources:FlushAuraApplicationMaxSettle()
end

local function ResourceWorldSettleTimerCallback()
    Sources.resourceWorldSettleTimer = nil
    local watchdog = YUI.CPUWatchdog
    if watchdog and watchdog.sceneCapture then
        return watchdog:MeasureSceneTask("yhud.resource-world-settle", Sources.FlushResourceWorldSettle, Sources)
    end
    Sources:FlushResourceWorldSettle()
end

local function SafeNumber(value)
    local security = YUI.API and YUI.API.Security
    if security and security.SafeNumber then
        return security.SafeNumber(value)
    end
    return type(value) == "number" and value or nil
end

local function ResetRacialSignature(signature)
    for index = 1, tonumber(signature.count) or 0 do
        signature[index] = nil
    end
    signature.raceToken = nil
    signature.classToken = nil
    signature.count = nil
end

local function ResetBundleSignature(signature)
    for index = 1, tonumber(signature.count) or 0 do
        signature[index] = nil
    end
    signature.count = nil
end

local function BuildLegacySpellSourceRecords(spellIDs)
    local result = {}
    for index = 1, #(type(spellIDs) == "table" and spellIDs or {}) do
        local spellID = tonumber(spellIDs[index])
        if spellID then
            result[#result + 1] = {
                spellID = spellID,
                runtimeSpellID = spellID,
                chargeSpellID = spellID,
                aliases = { spellID },
                sourceKey = "spell:" .. tostring(spellID),
                signature = tostring(spellID) .. ":" .. tostring(spellID)
                    .. ":" .. tostring(spellID),
            }
        end
    end
    return result
end

local function GetEnabledBundleSources(catalog, profile, bundleKind)
    if catalog and catalog.GetEnabledSpellBundleSources then
        return catalog:GetEnabledSpellBundleSources(profile, bundleKind)
    end
    if catalog and catalog.GetEnabledSpellBundleSpells then
        return BuildLegacySpellSourceRecords(
            catalog:GetEnabledSpellBundleSpells(profile, bundleKind)
        )
    end
    return {}
end

local function GetEnabledActiveTrinketSources(catalog, profile)
    if catalog and catalog.GetEnabledActiveTrinketSources then
        return catalog:GetEnabledActiveTrinketSources(profile)
    end
    return {}
end

local function BuildActiveTrinketProjectionSignature(sources)
    local slot13
    local slot14
    if type(sources) ~= "table" then
        return "13\002\00114\002"
    end
    for index = 1, #sources do
        local source = sources[index]
        local equipSlot = SafeNumber(source and source.equipSlot)
        local signature = source and source.signature
        if source.kind == "active-timer" and equipSlot == 13 then
            slot13 = tostring(source.sourceKey or "") .. "\002"
                .. tostring(signature or "")
        elseif source.kind == "active-timer" and equipSlot == 14 then
            slot14 = tostring(source.sourceKey or "") .. "\002"
                .. tostring(signature or "")
        end
    end
    return "13\002" .. tostring(slot13 or "") .. "\00114\002"
        .. tostring(slot14 or "")
end

local function GetEnabledRacialSources(catalog, profile)
    if catalog and catalog.GetEnabledPlayerRacialSources then
        return catalog:GetEnabledPlayerRacialSources(profile)
    end
    if catalog and catalog.GetEnabledPlayerRacialSpells then
        return BuildLegacySpellSourceRecords(
            catalog:GetEnabledPlayerRacialSpells(profile)
        )
    end
    return {}
end


local function IsInCombat()
    return Combat and Combat.InCombatLockdown
        and Combat.InCombatLockdown() == true
        or YHUD.View and YHUD.View.inCombat == true
        or false
end

local function UpdateBundleSignature(signature, catalog, profile)
    if not (catalog and profile) then
        local changed = (tonumber(signature.count) or 0) > 0
        ResetBundleSignature(signature)
        return changed
    end
    local previousCount = tonumber(signature.count) or 0
    local count = 0
    local changed = false
    for kindIndex = 1, #SPELL_BUNDLE_KINDS do
        local sources = GetEnabledBundleSources(
            catalog,
            profile,
            SPELL_BUNDLE_KINDS[kindIndex]
        )
        for index = 1, #sources do
            count = count + 1
            local source = sources[index]
            local value = tostring(source.sourceKey or "") .. "\002"
                .. tostring(source.signature or "")
            if signature[count] ~= value then
                signature[count] = value
                changed = true
            end
        end
    end
    local racialSources = GetEnabledRacialSources(catalog, profile)
    for index = 1, #racialSources do
        count = count + 1
        local source = racialSources[index]
        local value = tostring(source.sourceKey or "") .. "\002"
            .. tostring(source.signature or "")
        if signature[count] ~= value then
            signature[count] = value
            changed = true
        end
    end
    for index = count + 1, previousCount do
        signature[index] = nil
        changed = true
    end
    if previousCount ~= count then changed = true end
    signature.count = count
    return changed
end

local function PositiveSpellID(value)
    value = tonumber(value)
    if value and value > 0 and value == math.floor(value) then
        return value
    end
end

local function IsRetryableAuraApplicationMaxFailure(code)
    return code == nil
        or code == "restricted"
        or code == "unavailable"
        or code == "invalid-max"
        or code == "api-error"
        or code == "api-unavailable"
end

local function SpellSourceMatches(source, firstSpellID, secondSpellID)
    if type(source) ~= "table" then return false end
    local function Matches(value)
        value = PositiveSpellID(value)
        return value ~= nil
            and (value == firstSpellID or value == secondSpellID)
    end
    if Matches(source.spellID) or Matches(source.runtimeSpellID)
        or Matches(source.chargeSpellID) then
        return true
    end
    for index = 1, #(type(source.aliases) == "table"
        and source.aliases or {}) do
        if Matches(source.aliases[index]) then return true end
    end
    return false
end

local function FindEnabledSpellFamily(catalog, profile, baseSpellID, overrideSpellID)
    if not (catalog and profile) then return nil end
    for kindIndex = 1, #SPELL_BUNDLE_KINDS do
        local sources = GetEnabledBundleSources(
            catalog,
            profile,
            SPELL_BUNDLE_KINDS[kindIndex]
        )
        for index = 1, #sources do
            if SpellSourceMatches(sources[index], baseSpellID, overrideSpellID) then
                return sources[index]
            end
        end
    end
    local racialSources = GetEnabledRacialSources(catalog, profile)
    for index = 1, #racialSources do
        if SpellSourceMatches(
            racialSources[index],
            baseSpellID,
            overrideSpellID
        ) then
            return racialSources[index]
        end
    end
end

local function BuildHotSpellDefinition(source, handle, baseSpellID, overrideSpellID)
    local canonicalSpellID = PositiveSpellID(source and source.spellID)
        or baseSpellID
    if not canonicalSpellID then return nil end
    local runtimeSpellID = overrideSpellID
        or baseSpellID
        or PositiveSpellID(source and source.runtimeSpellID)
        or canonicalSpellID
    local previousParams = handle and handle.source and handle.source.params
        or handle and handle.params
    local previousRuntimeSpellID = previousParams
        and PositiveSpellID(previousParams.spellID)
    local aliases = {}
    local seen = {}
    local function Add(value)
        value = PositiveSpellID(value)
        if value and not seen[value] then
            seen[value] = true
            aliases[#aliases + 1] = value
        end
    end
    Add(canonicalSpellID)
    Add(baseSpellID)
    Add(runtimeSpellID)
    Add(overrideSpellID)
    for index = 1, #(type(source.aliases) == "table"
        and source.aliases or {}) do
        local alias = PositiveSpellID(source.aliases[index])
        if alias ~= previousRuntimeSpellID
            or alias == canonicalSpellID
            or alias == baseSpellID
            or alias == overrideSpellID then
            Add(alias)
        end
    end
    table.sort(aliases)
    local signature = table.concat({
        tostring(runtimeSpellID),
        tostring(runtimeSpellID),
        table.concat(aliases, ","),
        source and source.hasCharges == true and "1" or "0",
    }, ":")
    return {
        sourceKey = source.sourceKey
            or ("spell:" .. tostring(canonicalSpellID)),
        identity = canonicalSpellID,
        params = {
            spellID = runtimeSpellID,
            chargeSpellID = runtimeSpellID,
            hasCharges = source and source.hasCharges == true,
            identities = aliases,
            signature = signature,
        },
    }
end

local function CreateResourceState(params)
    local structuralMax = tonumber(params.segmentCountFallback)
    if structuralMax then structuralMax = math.floor(structuralMax + 0.5) end
    return {
        sourceKind = "resource",
        unit = "player",
        resourceId = params.resourceId,
        classFile = params.classFile,
        specID = params.specID,
        powerType = params.powerType,
        powerToken = params.powerToken,
        nameKey = params.nameKey,
        color = params.color,
        valueKind = params.valueKind,
        segmentCountFallback = structuralMax,
        structuralMax = structuralMax,
        value = nil,
        maxValue = nil,
        valueRaw = nil,
        maxValueRaw = nil,
        rawValuesAvailable = false,
        percentRaw = nil,
        colorRaw = nil,
        partialFraction = nil,
        displayValue = nil,
        chargedPointMask = nil,
        available = false,
        secret = false,
        opaqueRevision = 0,
    }
end

local function ReadResource(source, state)
    local _, changed = Unit.ReadPowerDisplay(
        "player",
        source.params.powerType,
        state
    )
    local params = source.params
    local partialFraction
    local displayValue
    if state.secret ~= true and params.providerKind == "unit-power-partial"
        and Unit.ReadPowerPartialFraction then
        partialFraction = Unit.ReadPowerPartialFraction(
            "player",
            params.powerType,
            params.partialScale,
            params.partialSource
        )
        if type(partialFraction) == "number" and type(state.value) == "number" then
            displayValue = state.value + partialFraction
        end
    end
    if state.partialFraction ~= partialFraction
        or state.displayValue ~= displayValue then
        state.partialFraction = partialFraction
        state.displayValue = displayValue
        changed = true
    end
    local chargedPointMask
    if params.chargedPowerPoints == true and Unit.ReadChargedPowerPointMask then
        local mask, available = Unit.ReadChargedPowerPointMask(
            "player",
            state.structuralMax or params.segmentCountFallback
        )
        if available == true then chargedPointMask = mask end
    end
    if state.chargedPointMask ~= chargedPointMask then
        state.chargedPointMask = chargedPointMask
        changed = true
    end
    if state.valueKind == "discrete" and state.secret ~= true then
        local structuralMax = type(state.maxValue) == "number"
            and state.maxValue or nil
        if structuralMax and structuralMax >= 1 and structuralMax <= 100
            and structuralMax % 1 == 0
            and state.structuralMax ~= structuralMax then
            state.structuralMax = structuralMax
            changed = true
        end
    end
    return changed == true
end

local function GetResourceIdentity(params)
    return params.powerToken
end

local function ClearResourceTransient(_, state)
    state.valueRaw = nil
    state.maxValueRaw = nil
    state.rawValuesAvailable = false
    state.percentRaw = nil
    state.colorRaw = nil
end

local function CreatePlayerAuraState()
    return {
        sourceKind = "aura",
        spellID = nil,
        icon = nil,
        startTime = 0,
        duration = 0,
        modRate = 1,
        isEnabled = true,
        available = false,
        resolved = false,
        secret = false,
        displayCount = nil,
    }
end

local function ReadPlayerAura(source, state)
    local _, changed = Unit.ReadPlayerAuraDisplay(
        source.params.spellIDs,
        state
    )
    return changed == true
end

local function GetPlayerAuraIdentity(params)
    return params.identity
end

local function CreateOfficialAuraState(params)
    return {
        sourceKind = "aura",
        spellID = params.spellID,
        icon = params.icon,
        startTime = 0,
        duration = 0,
        modRate = 1,
        isEnabled = true,
        available = false,
        resolved = false,
        secret = false,
        displayCount = nil,
        cooldownActive = false,
        chargeActive = false,
        durationMode = "none",
        durationObject = nil,
        opaqueRevision = 0,
        viewerAuraInstanceID = nil,
        viewerAuraUnit = nil,
        viewerAuraRefreshRevision = nil,
        backendStatus = "idle",
    }
end

local function ClearOfficialAuraTransient(_, state)
    state.durationObject = nil
end

local function ReadOfficialAura(source, state)
    local officialState, officialChanged, code = CooldownViewer:ReadAuraDisplay(
        source.params.category,
        source.params.cooldownID,
        state
    )
    if officialState then
        local status = code or "official"
        local statusChanged = state.backendStatus ~= status
            or state.resolved ~= true
        state.resolved = true
        state.backendStatus = status
        return officialChanged == true or statusChanged
    end

    local status = code or "official-unavailable"
    local changed = state.sourceKind ~= "aura"
        or state.available ~= false
        or state.resolved ~= false
        or state.isEnabled ~= true
        or state.secret ~= false
        or state.cooldownActive ~= false
        or state.chargeActive ~= false
        or state.durationMode ~= "none"
        or state.durationObject ~= nil
        or state.viewerAuraInstanceID ~= nil
        or state.viewerAuraUnit ~= nil
        or state.viewerAuraRefreshRevision ~= nil
        or state.backendStatus ~= status
    state.sourceKind = "aura"
    state.available = false
    state.resolved = false
    state.isEnabled = true
    state.secret = false
    state.cooldownActive = false
    state.chargeActive = false
    state.durationMode = "none"
    state.durationObject = nil
    state.viewerAuraInstanceID = nil
    state.viewerAuraUnit = nil
    state.viewerAuraRefreshRevision = nil
    state.backendStatus = status
    return changed
end

local function GetOfficialAuraIdentity(params)
    return "aura:cdm:" .. tostring(params.cooldownID)
end

local function CreateBloodlustState(params)
    return {
        sourceKind = "aura",
        spellID = params.spellID,
        icon = params.icon,
        startTime = 0,
        duration = 0,
        modRate = 1,
        isEnabled = true,
        available = false,
        resolved = true,
        secret = false,
        displayCount = nil,
    }
end

local function ReadBloodlust(_, state)
    local snapshot = Sources.bloodlustSnapshot
    local active = snapshot.active == true
    local startTime = active and (tonumber(snapshot.startTime) or 0) or 0
    local duration = active and (tonumber(snapshot.duration) or 40) or 0
    local changed = state.startTime ~= startTime
        or state.duration ~= duration
        or state.available ~= active
        or state.resolved ~= true
        or state.isEnabled ~= true
        or state.secret ~= false
    state.startTime = startTime
    state.duration = duration
    state.modRate = 1
    state.available = active
    state.resolved = true
    state.isEnabled = true
    state.secret = false
    return changed
end

local function GetBloodlustIdentity(params)
    return params.identity
end

local function CancelTimedWindow(sourceKey)
    local runtime = Sources.timedWindows[sourceKey]
    if not runtime then return false end
    local timer = runtime.timer
    if timer and timer.Cancel then timer:Cancel() end
    Sources.timedWindows[sourceKey] = nil
    return true
end

local function ScheduleTimedWindow(source, expiryReason)
    CancelTimedWindow(source.key)
    local duration = tonumber(source.params.durationSeconds)
    if not duration or duration <= 0 then return false end
    if not (C_Timer and C_Timer.NewTimer) then
        if Sources.timedWindowTimerUnavailableReported ~= true
            and YHUD.Diagnostics then
            Sources.timedWindowTimerUnavailableReported = true
            YHUD.Diagnostics:Record(
                "timed-window-schedule",
                "timer-api-unavailable"
            )
        end
        return false
    end
    local token = {}
    local runtime = {
        token = token,
        timer = nil,
    }
    Sources.timedWindows[source.key] = runtime
    runtime.timer = C_Timer.NewTimer(duration, function()
        local current = Sources.timedWindows[source.key]
        if current and current.token == token then
            current.timer = nil
            Monitor:QueueSource(source.key, expiryReason)
        end
    end)
    if not runtime.timer then
        Sources.timedWindows[source.key] = nil
    end
    return runtime.timer ~= nil
end

local function CreateTimedWindowState(params, sourceKind)
    return {
        sourceKind = sourceKind,
        spellID = params.spellID,
        icon = params.icon,
        startTime = 0,
        duration = tonumber(params.durationSeconds) or 0,
        isEnabled = true,
        available = false,
        resolved = true,
        secret = false,
        displayCount = nil,
    }
end

local function ReadTimedWindow(
    source,
    state,
    reason,
    triggerReason,
    expiryReason
)
    local now = type(GetTime) == "function" and GetTime() or 0
    local duration = tonumber(source.params.durationSeconds) or 0
    local changed = state.duration ~= duration
        or state.resolved ~= true
    state.duration = duration
    state.resolved = true
    if reason == triggerReason then
        if not ScheduleTimedWindow(source, expiryReason) then
            local wasAvailable = state.available == true
                or (tonumber(state.startTime) or 0) ~= 0
            state.startTime = 0
            state.available = false
            return changed or wasAvailable
        end
        state.startTime = now
        state.available = true
        return true
    end
    if state.available
        and now >= (tonumber(state.startTime) or 0) + duration then
        state.available = false
        state.startTime = 0
        CancelTimedWindow(source.key)
        return true
    end
    return changed
end

local function CreateBuffTimerState(params)
    return CreateTimedWindowState(params, "buff-timer")
end

local burstPotionIcons = {
    [1236616] = 7548911, [1236994] = 7548916, [1295132] = 7816859,
    [1236998] = 7548915, [1238443] = 7548908, [1295015] = 7816861,
}
local function CaptureBuffTimerIcon(source, event, unit, guid, spellID)
    if source.params.sourceIdentity ~= "buff-timer:burst-potion" then return end
    source.pendingBuffIcon = nil
    if type(issecretvalue) == "function" and issecretvalue(spellID) then return end
    if type(spellID) == "number" then
        source.pendingBuffIcon = burstPotionIcons[spellID]
    end
end

local function ReadBuffTimer(source, state, reason)
    if reason == "buff-timer-cast" then
        state.icon = source.pendingBuffIcon or source.params.icon
        source.pendingBuffIcon = nil
    end
    return ReadTimedWindow(
        source,
        state,
        reason,
        "buff-timer-cast",
        "buff-timer-expired"
    )
end

local function GetBuffTimerIdentity(params)
    local triggerSpellIDs = params.triggerSpellIDs
    if type(triggerSpellIDs) == "table" and #triggerSpellIDs > 0 then
        local identities = {}
        local seen = {}
        for index = 1, #triggerSpellIDs do
            local spellID = tonumber(triggerSpellIDs[index])
            if spellID and not seen[spellID] then
                seen[spellID] = true
                identities[#identities + 1] = spellID
            end
        end
        if #identities > 0 then
            identities[#identities + 1] = params.sourceIdentity
            return identities
        end
    end
    return params.sourceIdentity or params.spellID
end

function Sources:RegisterBuffTimerSourceType()
    if self.buffTimerSourceTypeRegistered then return true end
    local sourceType, code = Monitor:RegisterSourceType(
        BUFF_TIMER_SOURCE_TYPE,
        {
            createState = CreateBuffTimerState,
            getIdentity = GetBuffTimerIdentity,
            read = ReadBuffTimer,
            events = {
                {
                    event = "UNIT_SPELLCAST_SUCCEEDED",
                    unit = "player",
                    identityArg = 3,
                    identityReason = "buff-timer-cast",
                    capture = CaptureBuffTimerIcon,
                },
            },
        }
    )
    if not sourceType and code ~= "source-type-exists" then
        if YHUD.Stats then YHUD.Stats:Add("sourceErrors") end
        return nil, code
    end
    self.buffTimerSourceTypeRegistered = true
    return true
end

function Sources:RegisterSpellEventWindowSourceType()
    local common = Monitor.CommonSources
    if not (common and common.RegisterSpellEventWindowSourceType) then return nil, "source-unavailable" end
    return common:RegisterSpellEventWindowSourceType()
end

function Sources:RegisterPlayerAuraSourceType()
    if self.playerAuraSourceTypeRegistered then return true end
    if not (Unit and Unit.ReadPlayerAuraDisplay) then
        return nil, "aura-api-unavailable"
    end
    local sourceType, code = Monitor:RegisterSourceType(
        PLAYER_AURA_SOURCE_TYPE,
        {
            createState = CreatePlayerAuraState,
            getIdentity = GetPlayerAuraIdentity,
            read = ReadPlayerAura,
            events = {
                {
                    event = "UNIT_AURA",
                    unit = "player",
                    all = true,
                    reason = "player-aura",
                },
            },
        }
    )
    if not sourceType and code ~= "source-type-exists" then
        if YHUD.Stats then YHUD.Stats:Add("sourceErrors") end
        return nil, code
    end
    self.playerAuraSourceTypeRegistered = true
    return true
end

function Sources:RegisterOfficialAuraSourceType()
    if self.officialAuraSourceTypeRegistered then return true end
    if not (CooldownViewer and CooldownViewer.ReadAuraDisplay) then
        return nil, "official-aura-api-unavailable"
    end
    local sourceType, code = Monitor:RegisterSourceType(
        OFFICIAL_AURA_SOURCE_TYPE,
        {
            createState = CreateOfficialAuraState,
            getIdentity = GetOfficialAuraIdentity,
            read = ReadOfficialAura,
            afterDispatch = ClearOfficialAuraTransient,
            events = {
                {
                    event = CooldownViewer and CooldownViewer.AURA_REFRESH_EVENT
                        or "YUI_COOLDOWN_VIEWER_AURA_REFRESH",
                    identityArgs = { 1, 2 },
                    identityReason = "official-aura-refresh",
                    allWhenIdentityMissing = true,
                    missingAllReason = "official-aura-runtime-ready",
                },
            },
        }
    )
    if not sourceType and code ~= "source-type-exists" then
        if YHUD.Stats then YHUD.Stats:Add("sourceErrors") end
        return nil, code
    end
    self.officialAuraSourceTypeRegistered = true
    return true
end

function Sources:RegisterBloodlustSourceType()
    if self.bloodlustSourceTypeRegistered then return true end
    if not Bloodlust then return nil, "bloodlust-service-unavailable" end
    local sourceType, code = Monitor:RegisterSourceType(
        BLOODLUST_SOURCE_TYPE,
        {
            createState = CreateBloodlustState,
            getIdentity = GetBloodlustIdentity,
            read = ReadBloodlust,
        }
    )
    if not sourceType and code ~= "source-type-exists" then
        if YHUD.Stats then YHUD.Stats:Add("sourceErrors") end
        return nil, code
    end
    self.bloodlustSourceTypeRegistered = true
    return true
end

function Sources:RegisterSlotSourceType()
    local common = Monitor.CommonSources
    if not common then return nil, "common-sources-unavailable" end
    return common:RegisterSlotSourceType()
end

function Sources:RegisterSpellSourceType()
    local common = Monitor.CommonSources
    if not common then return nil, "common-sources-unavailable" end
    return common:RegisterSpellSourceType()
end

function Sources:RegisterItemSourceType()
    local common = Monitor.CommonSources
    if not common then return nil, "common-sources-unavailable" end
    return common:RegisterItemSourceType()
end

function Sources:RegisterResourceSourceType()
    if self.resourceSourceTypeRegistered then return true end
    if not (Unit and Unit.ReadPowerDisplay and ResourceCatalog) then
        return nil, "resource-api-unavailable"
    end
    local sourceType, code = Monitor:RegisterSourceType(RESOURCE_SOURCE_TYPE, {
        createState = CreateResourceState,
        getIdentity = GetResourceIdentity,
        read = ReadResource,
        afterDispatch = ClearResourceTransient,
        events = {
            {
                event = "UNIT_POWER_FREQUENT",
                unit = "player",
                identityArg = 2,
                identityReason = "resource-value",
            },
            {
                event = "UNIT_MAXPOWER",
                unit = "player",
                identityArg = 2,
                identityReason = "resource-max",
            },
            {
                event = "UNIT_DISPLAYPOWER",
                unit = "player",
                all = true,
                reason = "resource-display",
            },
            {
                event = "UNIT_POWER_POINT_CHARGE",
                unit = "player",
                all = true,
                reason = "resource-point-charge",
            },
            {
                event = "PLAYER_ENTERING_WORLD",
                all = true,
                reason = "resource-context",
            },
            YUI.IsForever and {
                event = "PLAYER_TARGET_CHANGED",
                all = true,
                reason = "resource-target",
            } or nil,
        },
    })
    if not sourceType and code ~= "source-type-exists" then
        if YHUD.Stats then YHUD.Stats:Add("sourceErrors") end
        return nil, code
    end
    self.resourceSourceTypeRegistered = true
    return true
end

local function RegisterSpecialSourceType(typeId, definition)
    local sourceType, code = Monitor:RegisterSourceType(typeId, definition)
    return sourceType ~= nil or code == "source-type-exists"
end

function Sources:RegisterSpecialResourceSourceTypes()
    if self.specialResourceSourceTypesRegistered then return true end
    if not (SpecialResources and SpecialResources.CreateState
        and SpecialResources.ClearTransient) then
        return nil, "special-resource-api-unavailable"
    end
    local chargeOK = RegisterSpecialSourceType(CHARGE_RESOURCE_SOURCE_TYPE, {
        createState = SpecialResources.CreateState,
        getIdentity = SpecialResources.GetSpellIdentity,
        read = SpecialResources.ReadCharge,
        afterDispatch = SpecialResources.ClearTransient,
        events = {
            { event = "SPELL_UPDATE_CHARGES", all = true },
        },
    })
    local playerAuraOK = RegisterSpecialSourceType(
        PLAYER_AURA_RESOURCE_SOURCE_TYPE,
        {
            createState = SpecialResources.CreateState,
            getIdentity = SpecialResources.GetSpellIdentity,
            read = SpecialResources.ReadAura,
            afterDispatch = SpecialResources.ClearTransient,
            events = {
                { event = "UNIT_AURA", unit = "player", all = true },
            },
        }
    )
    local targetAuraOK = RegisterSpecialSourceType(
        TARGET_AURA_RESOURCE_SOURCE_TYPE,
        {
            createState = SpecialResources.CreateState,
            getIdentity = SpecialResources.GetSpellIdentity,
            read = SpecialResources.ReadAura,
            afterDispatch = SpecialResources.ClearTransient,
            events = {
                { event = "UNIT_AURA", unit = "target", all = true },
                { event = "PLAYER_TARGET_CHANGED", all = true },
                {
                    event = "UNIT_FACTION",
                    units = { "player", "target" },
                    all = true,
                    reason = "target-aura-context",
                },
            },
        }
    )
    local simulatedOK = RegisterSpecialSourceType(
        SIMULATED_RESOURCE_SOURCE_TYPE,
        {
            createState = SpecialResources.CreateState,
            getIdentity = SpecialResources.GetSimulatorIdentity,
            read = SpecialResources.ReadSimulated,
            afterDispatch = SpecialResources.ClearTransient,
            events = {
                {
                    event = CooldownViewer and CooldownViewer.AURA_REFRESH_EVENT
                        or "YUI_COOLDOWN_VIEWER_AURA_REFRESH",
                    identityArgs = { 1, 2 },
                    identityReason = "simulated-aura-refresh",
                },
            },
        }
    )
    local runeOK = RegisterSpecialSourceType(RUNE_RESOURCE_SOURCE_TYPE, {
        createState = SpecialResources.CreateState,
        getIdentity = function(params) return params.resourceId end,
        read = SpecialResources.ReadRunes,
        afterDispatch = SpecialResources.ClearTransient,
        events = {
            { event = "RUNE_POWER_UPDATE", all = true },
        },
    })
    local spellCountOK = RegisterSpecialSourceType(
        SPELL_COUNT_RESOURCE_SOURCE_TYPE,
        {
            createState = SpecialResources.CreateState,
            getIdentity = SpecialResources.GetSpellIdentity,
            read = SpecialResources.ReadSpellCount,
            afterDispatch = SpecialResources.ClearTransient,
            events = {
                { event = "SPELL_UPDATE_USES", all = true },
            },
        }
    )
    local adaptiveAuraOK = RegisterSpecialSourceType(
        ADAPTIVE_AURA_RESOURCE_SOURCE_TYPE,
        {
            createState = SpecialResources.CreateState,
            getIdentity = SpecialResources.GetSpellIdentity,
            read = SpecialResources.ReadAdaptiveAura,
            afterDispatch = SpecialResources.ClearTransient,
            events = {
                { event = "UNIT_AURA", unit = "player", all = true },
            },
        }
    )
    local staggerOK = RegisterSpecialSourceType(STAGGER_RESOURCE_SOURCE_TYPE, {
        createState = SpecialResources.CreateState,
        getIdentity = function(params) return params.resourceId end,
        read = SpecialResources.ReadStagger,
        afterDispatch = SpecialResources.ClearTransient,
        events = {
            { event = "UNIT_ABSORB_AMOUNT_CHANGED", unit = "player", all = true },
            { event = "UNIT_HEALTH", unit = "player", all = true },
            { event = "UNIT_MAXHEALTH", unit = "player", all = true },
        },
    })
    local absorbOK = RegisterSpecialSourceType(ABSORB_RESOURCE_SOURCE_TYPE, {
        createState = SpecialResources.CreateState,
        getIdentity = function(params) return params.resourceId end,
        read = SpecialResources.ReadAbsorb,
        afterDispatch = SpecialResources.ClearTransient,
        events = {
            { event = "UNIT_AURA", unit = "player", all = true },
            { event = "UNIT_ABSORB_AMOUNT_CHANGED", unit = "player", all = true },
            { event = "UNIT_HEALTH", unit = "player", all = true },
            { event = "UNIT_MAXHEALTH", unit = "player", all = true },
        },
    })
    local auraDurationOK = RegisterSpecialSourceType(
        AURA_DURATION_RESOURCE_SOURCE_TYPE,
        {
            createState = SpecialResources.CreateState,
            getIdentity = SpecialResources.GetAuraDurationIdentity,
            read = SpecialResources.ReadAuraDuration,
            afterDispatch = SpecialResources.ClearTransient,
            events = {
                { event = "UNIT_AURA", unit = "player", all = true },
                {
                    event = CooldownViewer and CooldownViewer.AURA_REFRESH_EVENT
                        or "YUI_COOLDOWN_VIEWER_AURA_REFRESH",
                    identityArgs = { 1, 2 },
                    identityReason = "aura-duration-refresh",
                    allWhenIdentityMissing = true,
                    missingAllReason = "aura-duration-runtime-ready",
                },
            },
        }
    )
    local ironfurOK = RegisterSpecialSourceType(
        IRONFUR_RESOURCE_SOURCE_TYPE,
        {
            createState = SpecialResources.CreateState,
            getIdentity = function(params) return params.resourceId end,
            read = SpecialResources.ReadIronfur,
            afterDispatch = SpecialResources.ClearTransient,
        }
    )
    self.specialResourceSourceTypesRegistered = chargeOK
        and playerAuraOK and targetAuraOK and simulatedOK
        and runeOK and spellCountOK and adaptiveAuraOK
        and staggerOK and absorbOK and auraDurationOK and ironfurOK
    return self.specialResourceSourceTypesRegistered
end

function Sources:RegisterSourceTypes()
    local slotOK = self:RegisterSlotSourceType()
    local spellOK = self:RegisterSpellSourceType()
    local itemOK = self:RegisterItemSourceType()
    local resourceOK = self:RegisterResourceSourceType()
    local specialResourceOK = self:RegisterSpecialResourceSourceTypes()
    if YHUD.SwingTimers then YHUD.SwingTimers:RegisterSourceType() end
    if YHUD.Ammo then YHUD.Ammo:RegisterSourceType() end
    local buffTimerOK = self:RegisterBuffTimerSourceType()
    local spellEventWindowOK = self:RegisterSpellEventWindowSourceType()
    local playerAuraOK = self:RegisterPlayerAuraSourceType()
    local officialAuraOK = self:RegisterOfficialAuraSourceType()
    local bloodlustOK = self:RegisterBloodlustSourceType()
    return slotOK == true
        or spellOK == true
        or itemOK == true
        or resourceOK == true
        or specialResourceOK == true
        or buffTimerOK == true
        or spellEventWindowOK == true
        or playerAuraOK == true
        or officialAuraOK == true
        or bloodlustOK == true
end

function Sources:OnSourceState(state, sourceKey, _, forced)
    if YHUD.Model then
        return YHUD.Model:OnSourceState(state, sourceKey, forced == true)
    end
    return false
end

function Sources:OnBloodlustWindow(state, reason)
    local snapshot = self.bloodlustSnapshot
    snapshot.active = state and state.active == true
    snapshot.startTime = state and tonumber(state.startTime) or 0
    snapshot.duration = state and tonumber(state.duration) or 40
    snapshot.revision = state and tonumber(state.revision) or 0
    for sourceKey in pairs(self.bloodlustSourceKeys) do
        Monitor:QueueSource(sourceKey, reason or "bloodlust-window")
    end
end

function Sources:OnPlayerDead()
    local snapshot = self.bloodlustSnapshot
    if snapshot.active ~= true then return false end
    snapshot.active = false
    snapshot.startTime = 0
    for sourceKey in pairs(self.bloodlustSourceKeys) do
        Monitor:QueueSource(sourceKey, "bloodlust-player-dead")
    end
    return true
end

function Sources:SetBloodlustConsumer(enabled)
    enabled = enabled == true
    if enabled and not Bloodlust then return false end
    if enabled and not self.bloodlustHandle then
        self.bloodlustSnapshot.active = false
        self.bloodlustSnapshot.startTime = 0
        self.bloodlustSnapshot.duration = 40
        local handle, code = Bloodlust:Acquire(self, "OnBloodlustWindow")
        self.bloodlustHandle = handle
        if not handle and YHUD.Diagnostics then
            YHUD.Diagnostics:Record("bloodlust-acquire", code)
        end
    elseif not enabled and self.bloodlustHandle then
        Bloodlust:Release(self.bloodlustHandle)
        self.bloodlustHandle = nil
        self.bloodlustSnapshot.active = false
        self.bloodlustSnapshot.startTime = 0
        self.bloodlustSnapshot.duration = 40
    end
    return enabled == (self.bloodlustHandle ~= nil)
end

local function ResolveSource(profile, sourceKey, monitorIds)
    local monitor
    local entry
    for index = 1, #(type(monitorIds) == "table" and monitorIds or {}) do
        local candidate = profile.monitors[monitorIds[index]]
        local candidateEntry = candidate
            and profile.entries[candidate.entryKey] or nil
        local nativeOfficial = candidateEntry
            and candidateEntry.origin == "official-cdm"
            and YHUD.IsOfficialNativeView
            and YHUD:IsOfficialNativeView(
                candidateEntry.officialCategory,
                candidate.view
            )
            and candidate.visibilityMode ~= "always"
        if candidateEntry and not nativeOfficial then
            monitor = candidate
            entry = candidateEntry
            break
        end
    end
    if not entry then return nil end

    if YHUD.Ammo and entry.sourceType == YHUD.Ammo.SOURCE_TYPE then
        if YHUD.Ammo:IsApplicable(rawget(profile, "_yhudSpecKey")
            or YHUD:GetCurrentSpecKey()) then
            return YHUD.Ammo.SOURCE_TYPE, "player", {}
        end
        return nil
    elseif entry.sourceType == SLOT_SOURCE_TYPE then
        local slotID = tonumber(entry.slotId)
        if slotID then
            return SLOT_SOURCE_TYPE, slotID, { slotID = slotID }
        end
    elseif entry.sourceType == SPELL_SOURCE_TYPE then
        local spellID = tonumber(
            entry.runtimeSpellId
                or entry.overrideTooltipSpellId
                or entry.overrideSpellId
                or entry.spellId
        )
        local chargeSpellID = tonumber(
            entry.chargeSpellId
                or entry.overrideSpellId
                or entry.spellId
                or spellID
        )
        if spellID then
            local hasCharges = entry.charges == true
            return SPELL_SOURCE_TYPE, spellID, {
                spellID = spellID,
                chargeSpellID = chargeSpellID or spellID,
                hasCharges = hasCharges,
                signature = table.concat({
                    tostring(spellID),
                    tostring(chargeSpellID or spellID),
                    hasCharges and "1" or "0",
                }, ":"),
            }
        end
    elseif entry.sourceType == ITEM_SOURCE_TYPE then
        local itemID = tonumber(entry.itemId)
        if itemID then
            local itemIDs = entry.itemIds
            local signature = type(itemIDs) == "table"
                and table.concat(itemIDs, ",") or tostring(itemID)
            return ITEM_SOURCE_TYPE, itemID, {
                itemID = itemID,
                itemIDs = itemIDs,
                signature = signature,
            }
        end
    elseif entry.sourceType == BUFF_TIMER_SOURCE_TYPE then
        local spellID = tonumber(entry.spellId)
        local durationSeconds = tonumber(entry.durationSeconds)
        if spellID and durationSeconds then
            local sourceIdentity = entry.sourceIdentity or spellID
            local triggerSpellIDs = entry.triggerSpellIds
            if entry.sourceIdentity == "buff-timer:burst-potion" then
                -- Refresh saved versions of the built-in group without changing single-potion timers.
                triggerSpellIDs = { 1236616, 1236994, 1295132, 1236998, 1238443, 1295015 }
            end
            local triggerSignature = type(triggerSpellIDs) == "table"
                and table.concat(triggerSpellIDs, ",") or ""
            return BUFF_TIMER_SOURCE_TYPE, sourceIdentity, {
                spellID = spellID,
                sourceIdentity = sourceIdentity,
                triggerSpellIDs = triggerSpellIDs,
                durationSeconds = durationSeconds,
                icon = entry.sourceIdentity == "buff-timer:burst-potion" and 7548911 or entry.icon,
                signature = triggerSignature,
            }
        end
    elseif entry.sourceType == SPELL_EVENT_WINDOW_SOURCE_TYPE then
        local spellID = tonumber(entry.spellId)
        local durationSeconds = tonumber(entry.durationSeconds)
        local triggerSpellIDs = entry.triggerSpellIds
        if spellID and durationSeconds and type(triggerSpellIDs) == "table"
            and #triggerSpellIDs > 0 then
            local triggerSignature = table.concat(triggerSpellIDs, ",")
            return SPELL_EVENT_WINDOW_SOURCE_TYPE, triggerSignature, {
                spellID = spellID,
                triggerSpellIDs = triggerSpellIDs,
                durationSeconds = durationSeconds,
                icon = entry.icon,
                signature = triggerSignature,
            }
        end
    elseif entry.sourceType == PLAYER_AURA_SOURCE_TYPE then
        if YHUD.CanUseFilteredAuraDisplay
            and YHUD:IsFilteredAuraMonitor(entry, monitor)
            and YHUD:CanUseFilteredAuraDisplay() then
            return nil
        end
        if entry.origin ~= "official-cdm"
            and YHUD.GetFilteredAuraScopeKey
            and YHUD:GetFilteredAuraScopeKey(entry)
                == YHUD.FILTERED_AURA_SCOPE_TARGET_HARMFUL then
            return nil
        end
        local spellIDs = {}
        local seen = {}
        local function AddSpellID(value)
            value = tonumber(value)
            if value and value > 0 and not seen[value] then
                seen[value] = true
                spellIDs[#spellIDs + 1] = value
            end
        end
        AddSpellID(entry.overrideTooltipSpellId)
        AddSpellID(entry.overrideSpellId)
        AddSpellID(entry.spellId)
        for index = 1, #(type(entry.spellIds) == "table"
            and entry.spellIds or {}) do
            AddSpellID(entry.spellIds[index])
        end
        for index = 1, #(type(entry.linkedSpellIds) == "table"
            and entry.linkedSpellIds or {}) do
            AddSpellID(entry.linkedSpellIds[index])
        end
        if #spellIDs > 0 then
            table.sort(spellIDs)
            if entry.sourceIdentity == "bloodlust-heroism" then
                return BLOODLUST_SOURCE_TYPE, entry.sourceIdentity, {
                    identity = entry.sourceIdentity,
                    spellID = tonumber(entry.spellId) or spellIDs[1],
                    icon = entry.icon,
                    signature = "bloodlust-window",
                }
            end
            if entry.origin == "official-cdm"
                and (entry.officialCategory == "trackedBuff"
                    or entry.officialCategory == "trackedBar")
                and tonumber(entry.cooldownId) then
                local cooldownID = tonumber(entry.cooldownId)
                return OFFICIAL_AURA_SOURCE_TYPE,
                    "aura:cdm:" .. tostring(cooldownID),
                    {
                        category = entry.officialCategory,
                        cooldownID = cooldownID,
                        spellID = tonumber(entry.overrideTooltipSpellId)
                            or tonumber(entry.overrideSpellId)
                            or tonumber(entry.spellId)
                            or spellIDs[1],
                        spellIDs = spellIDs,
                        icon = entry.icon,
                        signature = table.concat(spellIDs, ","),
                    }
            end
            return PLAYER_AURA_SOURCE_TYPE, sourceKey, {
                identity = sourceKey,
                spellIDs = spellIDs,
                signature = table.concat(spellIDs, ","),
            }
        end
    end
    return nil
end

local function ActiveTrinketViewMatches(sources)
    local view = YHUD.View
    local context = view and view.layoutProjectionContext
    return BuildActiveTrinketProjectionSignature(
        context and context.equipmentTriggerProjection
    ) == sources.activeTrinketProjectionSignature
end

function Sources:SyncActiveTrinketView()
    local view = YHUD.View
    if not (view and view.active and view.ApplyConfig) then return false end
    if ActiveTrinketViewMatches(self) then
        self.activeTrinketProjectionPending = false
        return false
    end
    if IsInCombat() then
        self.activeTrinketProjectionPending = true
        return false
    end
    -- Compare the existing view snapshot, not freshly queried equipment data.
    -- Source-only settles may already have advanced the backend signature.
    local applied = view:ApplyConfig(self.profile) == true
    self.activeTrinketProjectionPending = not applied
    return applied
end

function Sources:ApplyConfig(profile, deferTrinketView)
    if not self.active then return false end
    local ok = self:RegisterSourceTypes()
    if not ok then return false end

    self.profile = profile
    local sourceIndex = YHUD.ProfileModel
        and YHUD.ProfileModel:BuildSourceIndex(profile, true)
        or { sources = {} }
    local desired = {}
    local simulatedSourceKey
    local simulatedID
    local simulatedBridgeCategory
    local simulatedBridgeCooldownID
    local simulatedBridgeAuraIdentity
    local ironfurSourceKey
    self.filteredAuraVisibilityRecovery = false
    local talentMaxRetryPending = false
    local auraApplicationMaxRetryPending = false
    local activeAuraApplicationMaxSpellIDs = {}
    for sourceKey, monitorIds in pairs(sourceIndex.sources) do
        local typeId, identity, params = ResolveSource(profile, sourceKey, monitorIds)
        if typeId then
            desired[sourceKey] = {
                typeId = typeId,
                identity = identity,
                params = params,
            }
        end
    end

    local monitorCatalog = YHUD.MonitorCatalog
    local racialContextEnabled = type(profile.racials) == "table"
        and profile.racials.enabled == true
        and type(profile.entries) == "table"
        and type(profile.entries["racial:bundle"]) == "table"
    self.racialContextEnabled = racialContextEnabled
    if monitorCatalog then
        local racialSources = GetEnabledRacialSources(monitorCatalog, profile)
        for index = 1, #racialSources do
            local source = racialSources[index]
            local spellID = source.runtimeSpellID or source.spellID
            local sourceKey = source.sourceKey
                or ("spell:" .. tostring(source.spellID or spellID))
            if not desired[sourceKey] then
                desired[sourceKey] = {
                    typeId = SPELL_SOURCE_TYPE,
                    identity = source.spellID or spellID,
                    params = {
                        spellID = spellID,
                        chargeSpellID = source.chargeSpellID or spellID,
                        hasCharges = source.hasCharges == true,
                        identities = source.aliases,
                        signature = source.signature,
                    },
                }
            end
        end
    end
    if monitorCatalog then
        for kindIndex = 1, #SPELL_BUNDLE_KINDS do
            local bundleSources = GetEnabledBundleSources(
                monitorCatalog,
                profile,
                SPELL_BUNDLE_KINDS[kindIndex]
            )
            for index = 1, #bundleSources do
                local source = bundleSources[index]
                local spellID = source.runtimeSpellID or source.spellID
                local sourceKey = source.sourceKey
                    or ("spell:" .. tostring(source.spellID or spellID))
                if not desired[sourceKey] then
                    desired[sourceKey] = {
                        typeId = SPELL_SOURCE_TYPE,
                        identity = source.spellID or spellID,
                        params = {
                            spellID = spellID,
                            chargeSpellID = source.chargeSpellID or spellID,
                            hasCharges = source.hasCharges == true,
                            identities = source.aliases,
                            signature = source.signature,
                        },
                    }
                end
            end
        end
    end
    local activeTrinketSources = GetEnabledActiveTrinketSources(
        monitorCatalog,
        profile
    )
    for index = 1, #activeTrinketSources do
        local source = activeTrinketSources[index]
        local sourceKey = source.sourceKey
        local spellID = PositiveSpellID(source.spellID)
        local durationSeconds = type(source.durationSeconds) == "number"
            and source.durationSeconds or nil
        if sourceKey and spellID and durationSeconds
            and durationSeconds > 0 then
            desired[sourceKey] = {
                typeId = BUFF_TIMER_SOURCE_TYPE,
                identity = source.sourceIdentity or sourceKey,
                params = {
                    spellID = spellID,
                    sourceIdentity = source.sourceIdentity or sourceKey,
                    triggerSpellIDs = source.triggerSpellIDs,
                    durationSeconds = durationSeconds,
                    icon = source.icon,
                    signature = source.signature,
                },
            }
        end
    end
    self.activeTrinketProjectionSignature =
        BuildActiveTrinketProjectionSignature(activeTrinketSources)
    UpdateBundleSignature(self.bundleSignature, monitorCatalog, profile)
    if racialContextEnabled
        and monitorCatalog
        and monitorCatalog.UpdatePlayerRacialSignature then
        monitorCatalog:UpdatePlayerRacialSignature(self.racialSignature)
    else
        ResetRacialSignature(self.racialSignature)
    end

    if ResourceCatalog then
        local classFile, specID = ResourceCatalog:GetCurrentContext()
        local talentContext = tostring(classFile) .. ":" .. tostring(specID)
        if self.talentMaxContext ~= talentContext then
            self.talentMaxContext = talentContext
            self.talentMaxCache = {}
            self.talentMaxRetryCount = 0
        end
        local presets = ResourceCatalog:GetResourceUnion(profile, nil, true)
        local needsActiveTraitSpells = false
        for index = 1, #presets do
            local provider = presets[index].provider
            if provider and (provider.talentMaxSpellID
                    or provider.reducedMaxSpellID) then
                needsActiveTraitSpells = true
                break
            end
        end
        local activeTraitSpells = self.activeTraitSpellScratch
        local activeTraitSpellsComplete = false
        if needsActiveTraitSpells then
            if Talent and Talent.ReadActiveTraitSpellSet then
                activeTraitSpells, activeTraitSpellsComplete =
                    Talent.ReadActiveTraitSpellSet(activeTraitSpells)
            else
                for spellID in pairs(activeTraitSpells) do
                    activeTraitSpells[spellID] = nil
                end
            end
        end
        for index = 1, #presets do
            local preset = presets[index]
            local provider = preset.provider or { kind = "unit-power" }
            local providerKind = provider.kind or "unit-power"
            if provider.auraBackend == "filtered-only" then
                self.filteredAuraVisibilityRecovery = true
            end
            local typeId = RESOURCE_SOURCE_TYPE
            local identity = preset.powerToken
            if providerKind == "spell-charges" then
                typeId = CHARGE_RESOURCE_SOURCE_TYPE
                identity = provider.spellID
            elseif providerKind == "unit-aura-stacks" then
                typeId = provider.unit == "target"
                    and TARGET_AURA_RESOURCE_SOURCE_TYPE
                    or PLAYER_AURA_RESOURCE_SOURCE_TYPE
                identity = provider.spellID
            elseif providerKind == "simulated-stacks" then
                typeId = SIMULATED_RESOURCE_SOURCE_TYPE
                identity = provider.simulatorID
                simulatedSourceKey = preset.sourceKey
                simulatedID = provider.simulatorID
            elseif providerKind == "rune-cooldowns" then
                typeId = RUNE_RESOURCE_SOURCE_TYPE
                identity = preset.id
            elseif providerKind == "spell-count" then
                typeId = SPELL_COUNT_RESOURCE_SOURCE_TYPE
                identity = provider.spellID
            elseif providerKind == "adaptive-aura-stacks" then
                typeId = ADAPTIVE_AURA_RESOURCE_SOURCE_TYPE
                identity = provider.spellID
            elseif providerKind == "stagger" then
                typeId = STAGGER_RESOURCE_SOURCE_TYPE
                identity = preset.id
            elseif providerKind == "absorb" then
                typeId = ABSORB_RESOURCE_SOURCE_TYPE
                identity = preset.id
            elseif providerKind == "aura-duration" then
                typeId = AURA_DURATION_RESOURCE_SOURCE_TYPE
                identity = provider.spellID
            elseif providerKind == "ironfur-timers" then
                typeId = IRONFUR_RESOURCE_SOURCE_TYPE
                identity = preset.id
                ironfurSourceKey = preset.sourceKey
            elseif providerKind == "swing-timer" and YHUD.SwingTimers then
                typeId = YHUD.SwingTimers.SOURCE_TYPE
                identity = provider.swingHand
            end
            local bridgeCategory
            local bridgeCooldownID
            local bridgeIdentity
            local bridgeAuraIdentity
            if (providerKind == "unit-aura-stacks"
                    or providerKind == "aura-duration"
                    or providerKind == "absorb"
                    or providerKind == "simulated-stacks")
                and provider.bridge == true
                and CooldownViewer and CooldownViewer.ResolveAuraStackSource then
                local bridge = CooldownViewer:ResolveAuraStackSource(
                    provider.spellID
                )
                if bridge then
                    bridgeCategory = bridge.category
                    bridgeCooldownID = bridge.cooldownID
                    bridgeIdentity = tostring(bridgeCategory)
                        .. ":" .. tostring(bridgeCooldownID)
                    if providerKind == "aura-duration" then
                        identity = bridgeIdentity
                    end
                end
            end
            local effectiveFallbackMax = provider.fallbackMax
            local maxApplicationsSpellID = PositiveSpellID(
                provider.maxApplicationsSpellID
            )
            local talentMaxSpellID = PositiveSpellID(
                provider.talentMaxSpellID
            )
            local talentMaxResolved = talentMaxSpellID
                and activeTraitSpellsComplete == true
            local talentMaxActive = talentMaxResolved
                and activeTraitSpells[talentMaxSpellID] == true
            if maxApplicationsSpellID then
                activeAuraApplicationMaxSpellIDs[maxApplicationsSpellID] = true
                local dynamicMax
                local maxReason = "api-unavailable"
                if Spell and Spell.ReadMaxCumulativeAuraApplications then
                    dynamicMax, maxReason =
                        Spell.ReadMaxCumulativeAuraApplications(
                            maxApplicationsSpellID
                        )
                end
                if dynamicMax then
                    self.auraApplicationMaxCache[maxApplicationsSpellID] =
                        dynamicMax
                    effectiveFallbackMax = dynamicMax
                elseif talentMaxResolved then
                    effectiveFallbackMax = talentMaxActive
                        and provider.talentMax or provider.fallbackMax
                else
                    effectiveFallbackMax =
                        self.auraApplicationMaxCache[maxApplicationsSpellID]
                        or effectiveFallbackMax
                end
                if not dynamicMax
                    and IsRetryableAuraApplicationMaxFailure(maxReason) then
                    auraApplicationMaxRetryPending = true
                end
            elseif talentMaxSpellID then
                if talentMaxResolved then
                    effectiveFallbackMax = talentMaxActive
                        and provider.talentMax or provider.fallbackMax
                    self.talentMaxCache[preset.sourceKey] = effectiveFallbackMax
                else
                    effectiveFallbackMax = self.talentMaxCache[preset.sourceKey]
                        or provider.fallbackMax
                    talentMaxRetryPending = true
                end
            end
            if providerKind == "simulated-stacks" then
                simulatedBridgeCategory = bridgeCategory
                simulatedBridgeCooldownID = bridgeCooldownID
                if bridgeCooldownID then
                    bridgeAuraIdentity = "aura:cdm:"
                        .. tostring(bridgeCooldownID)
                end
                simulatedBridgeAuraIdentity = bridgeAuraIdentity
            end
            local reducedMaxSpellID = PositiveSpellID(
                provider.reducedMaxSpellID
            )
            local reducedMaxActive = false
            if reducedMaxSpellID then
                if activeTraitSpellsComplete == true then
                    reducedMaxActive =
                        activeTraitSpells[reducedMaxSpellID] == true
                else
                    reducedMaxActive = nil
                end
            end
            local runtimeSignature = table.concat({
                providerKind,
                tostring(provider.spellID or provider.simulatorID or ""),
                tostring(provider.unit or ""),
                tostring(provider.auraBackend or ""),
                tostring(effectiveFallbackMax or ""),
                tostring(reducedMaxActive),
                tostring(provider.reducedMax or ""),
                tostring(provider.switchAuraSpellID or ""),
                tostring(provider.alternateSpellID or ""),
                tostring(provider.alternateMax or ""),
                tostring(provider.capFraction or ""),
                tostring(provider.partialSource or ""),
                tostring(provider.partialScale or ""),
                tostring(provider.safetyPollInterval or ""),
                tostring(provider.chargedPowerPoints == true),
                tostring(bridgeCategory or ""),
                tostring(bridgeCooldownID or ""),
            }, ":")
            desired[preset.sourceKey] = {
                typeId = typeId,
                identity = identity,
                params = {
                    resourceId = preset.id,
                    classFile = preset.classFile,
                    specID = preset.specID,
                    powerType = preset.powerType,
                    powerToken = preset.powerToken,
                    nameKey = preset.nameKey,
                    descriptionKey = preset.descriptionKey,
                    color = preset.color,
                    valueKind = preset.valueKind,
                    segmentCountFallback = preset.segmentCountFallback,
                    providerKind = providerKind,
                    swingHand = provider.swingHand,
                    unit = provider.unit,
                    spellID = provider.spellID,
                    simulatorID = provider.simulatorID,
                    fallbackMax = effectiveFallbackMax,
                    maxApplicationsSpellID = maxApplicationsSpellID,
                    talentMaxSpellID = provider.talentMaxSpellID,
                    talentMax = provider.talentMax,
                    reducedMaxActive = reducedMaxActive,
                    reducedMax = provider.reducedMax,
                    switchAuraSpellID = provider.switchAuraSpellID,
                    alternateSpellID = provider.alternateSpellID,
                    alternateMax = provider.alternateMax,
                    capFraction = provider.capFraction,
                    partialSource = provider.partialSource,
                    partialScale = provider.partialScale,
                    safetyPollInterval = provider.safetyPollInterval,
                    chargedPowerPoints = provider.chargedPowerPoints == true,
                    chargedColor = provider.chargedColor,
                    requirePlayerSource = provider.requirePlayerSource,
                    auraBackend = provider.auraBackend,
                    bridgeCategory = bridgeCategory,
                    bridgeCooldownID = bridgeCooldownID,
                    bridgeIdentity = bridgeIdentity,
                    bridgeAuraIdentity = bridgeAuraIdentity,
                    signature = runtimeSignature,
                },
            }
        end
    end

    if SpecialResources and SpecialResources.ConfigureSimulator then
        SpecialResources:ConfigureSimulator(
            simulatedSourceKey,
            simulatedID,
            simulatedBridgeCategory,
            simulatedBridgeCooldownID,
            simulatedBridgeAuraIdentity
        )
    end
    if SpecialResources and SpecialResources.ConfigureIronfur then
        SpecialResources:ConfigureIronfur(ironfurSourceKey)
    end

    local bloodlustSourceKeys = {}
    for sourceKey, definition in pairs(desired) do
        if definition.typeId == BLOODLUST_SOURCE_TYPE then
            bloodlustSourceKeys[sourceKey] = true
        end
    end
    self.bloodlustSourceKeys = bloodlustSourceKeys
    self:SetBloodlustConsumer(next(bloodlustSourceKeys) ~= nil)

    for sourceKey, handle in pairs(self.handles) do
        local definition = desired[sourceKey]
        if not definition
            or handle.active ~= true
            or handle._yhudTypeId ~= definition.typeId
            or handle._yhudIdentity ~= definition.identity
            or handle._yhudDuration ~= definition.params.durationSeconds
            or handle._yhudSignature ~= definition.params.signature then
            CancelTimedWindow(sourceKey)
            Monitor:ReleaseSource(handle)
            self.handles[sourceKey] = nil
        end
    end

    for sourceKey, definition in pairs(desired) do
        if not self.handles[sourceKey] then
            local acquired, code = Monitor:AcquireSource(
                self,
                sourceKey,
                definition.typeId,
                definition.params,
                "OnSourceState"
            )
            if acquired then
                acquired._yhudTypeId = definition.typeId
                acquired._yhudIdentity = definition.identity
                acquired._yhudDuration = definition.params.durationSeconds
                acquired._yhudSignature = definition.params.signature
                self.handles[sourceKey] = acquired
                if definition.params.maxApplicationsSpellID
                    or definition.params.talentMaxSpellID then
                    Monitor:QueueSource(
                        acquired.source or sourceKey,
                        "aura-max-config",
                        true
                    )
                end
            else
                if YHUD.Stats then YHUD.Stats:Add("sourceErrors") end
                if YHUD.Diagnostics then
                    YHUD.Diagnostics:Record("source-acquire", code)
                end
            end
        end
    end
    if YHUD.SwingTimers and YHUD.SwingTimers.SyncNativeSuppression then
        YHUD.SwingTimers:SyncNativeSuppression(self.handles)
    end
    self.auraApplicationMaxRefreshPending =
        auraApplicationMaxRetryPending == true
    for sourceKey in pairs(self.talentMaxCache) do
        if not desired[sourceKey] then self.talentMaxCache[sourceKey] = nil end
    end
    self.talentMaxRefreshPending = talentMaxRetryPending
    if not talentMaxRetryPending then self.talentMaxRetryCount = 0 end
    if talentMaxRetryPending and self.talentMaxRetryCount < 3
        and not self.auraApplicationMaxSettleTimer then
        self.auraApplicationMaxSettleRequested = true
    end
    self.auraApplicationMaxSpellIDs = activeAuraApplicationMaxSpellIDs
    self:ArmAuraApplicationMaxSettle()
    if self.SyncResourceProjectionSignature then
        self:SyncResourceProjectionSignature()
    end
    local viewApplied = false
    if deferTrinketView ~= true then
        viewApplied = self:SyncActiveTrinketView()
    end
    return true, viewApplied
end

local function ResourceProjectionMatches(keys, presets)
    if #keys ~= #presets then return false end
    for index = 1, #presets do
        if keys[index] ~= presets[index].sourceKey then return false end
    end
    return true
end

local function StoreResourceProjection(keys, presets)
    for index = 1, #presets do keys[index] = presets[index].sourceKey end
    for index = #keys, #presets + 1, -1 do keys[index] = nil end
end

local function ResourceProjectionEnabled(profile)
    for _, group in pairs(profile and profile.groups and profile.groups.items or {}) do
        if group.layout == "resource" and group.enabled == true then return true end
    end
    return false
end

function Sources:SyncResourceProjectionSignature()
    if not (self.profile and ResourceCatalog)
        or not ResourceProjectionEnabled(self.profile) then
        for index = #self.activeResourceKeys, 1, -1 do
            self.activeResourceKeys[index] = nil
        end
        for index = #self.activeResourceProjectionKeys, 1, -1 do self.activeResourceProjectionKeys[index] = nil end
        return false
    end
    local presets = ResourceCatalog:GetResourceUnion(
        self.profile,
        self.resourcePresetScratch,
        false,
        self.activeResourceProjectionKeys
    )
    StoreResourceProjection(self.activeResourceKeys, presets)
    return true
end

function Sources:ApplyResourceFormProjection(reason)
    if not (self.active and self.profile and ResourceCatalog) then return false end
    if not ResourceProjectionEnabled(self.profile) then return false end
    if YHUD.View and YHUD.View.designMode
        and YHUD.View.resourcePreviewFormKey then
        return false
    end
    if YHUD.Stats then YHUD.Stats:Add("resourceFormRequests") end
    local classFile = ResourceCatalog:GetCurrentContext()
    if classFile ~= "DRUID" then return false end
    local presets = ResourceCatalog:GetResourceUnion(
        self.profile,
        self.resourcePresetScratch,
        false,
        self.resourceProjectionScratch
    )
    local projectionMatches = #self.activeResourceProjectionKeys == #self.resourceProjectionScratch
    if projectionMatches then
        for index = 1, #self.resourceProjectionScratch do
            if self.activeResourceProjectionKeys[index] ~= self.resourceProjectionScratch[index] then
                projectionMatches = false break
            end
        end
    end
    if projectionMatches then
        if YHUD.Stats then YHUD.Stats:Add("resourceFormNoops") end
        return false
    end
    StoreResourceProjection(self.activeResourceKeys, presets)
    for index = 1, #self.resourceProjectionScratch do self.activeResourceProjectionKeys[index] = self.resourceProjectionScratch[index] end
    for index = #self.activeResourceProjectionKeys, #self.resourceProjectionScratch + 1, -1 do self.activeResourceProjectionKeys[index] = nil end
    if YHUD.View and YHUD.View.ApplyResourceProjection then
        YHUD.View:ApplyResourceProjection(self.profile, presets)
    end
    for index = 1, #presets do
        Monitor:QueueSource(
            presets[index].sourceKey,
            reason or "resource-form",
            true
        )
        if YHUD.Stats then YHUD.Stats:Add("resourceFormForcedReads") end
    end
    if YHUD.Stats then YHUD.Stats:Add("resourceFormChanges") end
    return true
end

function Sources:OnResourceFormChanged(_, unit)
    if unit and unit ~= "player" then return false end
    return self:ApplyResourceFormProjection("resource-form")
end

function Sources:CancelResourceWorldSettle()
    local timer = self.resourceWorldSettleTimer
    self.resourceWorldSettleTimer = nil
    self.resourceWorldSettlePending = false
    if timer and timer.Cancel then timer:Cancel() end
    return timer ~= nil
end

function Sources:ScheduleResourceWorldSettle()
    self:CancelResourceWorldSettle()
    local projectionEnabled = ResourceProjectionEnabled(self.profile)
    local timerAvailable = C_Timer and C_Timer.NewTimer ~= nil
    if not (self.active and self.profile and ResourceCatalog)
        or not projectionEnabled
        or not timerAvailable then
        return false
    end
    local watchdog = YUI.CPUWatchdog
    if watchdog and watchdog.sceneCapture then watchdog:SceneTaskScheduled("yhud.resource-world-settle") end
    self.resourceWorldSettleTimer = C_Timer.NewTimer(
        RESOURCE_WORLD_SETTLE_DELAY,
        ResourceWorldSettleTimerCallback
    )
    return self.resourceWorldSettleTimer ~= nil
end

function Sources:FlushResourceWorldSettle(confirmedOutOfCombat)
    self.resourceWorldSettleTimer = nil
    if not (self.active and self.profile and ResourceCatalog)
        or not ResourceProjectionEnabled(self.profile) then
        self.resourceWorldSettlePending = false
        return false
    end
    if confirmedOutOfCombat ~= true and IsInCombat() then
        self.resourceWorldSettlePending = true
        return true
    end

    self.resourceWorldSettlePending = false
    local presets = ResourceCatalog:GetResourceUnion(
        self.profile,
        self.resourcePresetScratch
    )
    local projectionChanged = not ResourceProjectionMatches(
        self.activeResourceKeys,
        presets
    )
    local applied, viewApplied = self:ApplyConfig(self.profile)
    if applied ~= true then return false end

    if projectionChanged and not viewApplied and YHUD.View
        and YHUD.View.ApplyResourceProjection then
        presets = ResourceCatalog:GetResourceUnion(
            self.profile,
            self.resourcePresetScratch
        )
        YHUD.View:ApplyResourceProjection(self.profile, presets)
    end

    local refreshedCount = 0
    for index = 1, #self.activeResourceKeys do
        local sourceKey = self.activeResourceKeys[index]
        local handle = self.handles[sourceKey]
        if handle and handle.active == true then
            local processed = Monitor:RefreshSourceNow(
                sourceKey,
                "resource-world-settle",
                true
            )
            if processed == true then
                refreshedCount = refreshedCount + 1
            end
        end
    end
    return viewApplied or projectionChanged or refreshedCount > 0
end

function Sources:CancelAuraApplicationMaxSettle()
    local timer = self.auraApplicationMaxSettleTimer
    self.auraApplicationMaxSettleTimer = nil
    self.auraApplicationMaxSettleRequested = false
    if timer and timer.Cancel then timer:Cancel() end
    return timer ~= nil
end

function Sources:RequestAuraApplicationMaxSettle()
    self:CancelAuraApplicationMaxSettle()
    self.auraApplicationMaxSettleRequested = true
    self.talentMaxRetryCount = 0
    return true
end

function Sources:ArmAuraApplicationMaxSettle()
    local hasDynamicMaximum =
        next(self.auraApplicationMaxSpellIDs or {}) ~= nil
    if not hasDynamicMaximum and not self.talentMaxRefreshPending then
        self:CancelAuraApplicationMaxSettle()
        return false
    end
    if self.auraApplicationMaxSettleRequested ~= true then return false end

    self.auraApplicationMaxSettleRequested = false
    if not (self.active and C_Timer and C_Timer.NewTimer) then return false end
    self.auraApplicationMaxSettleTimer = C_Timer.NewTimer(
        AURA_APPLICATION_MAX_SETTLE_DELAY,
        AuraApplicationMaxSettleTimerCallback
    )
    return self.auraApplicationMaxSettleTimer ~= nil
end

function Sources:FlushAuraApplicationMaxSettle()
    self.auraApplicationMaxSettleTimer = nil
    if not self.active then return false end
    if self.talentMaxRefreshPending and self.profile then
        self.talentMaxRetryCount = self.talentMaxRetryCount + 1
        self:ApplyConfig(self.profile, YHUD.RequestContextRefresh ~= nil)
        if YHUD.RequestContextRefresh then
            YHUD:RequestContextRefresh("talent-max-settle")
        end
    end
    if not next(self.auraApplicationMaxSpellIDs or {}) then return false end
    local changed = self:RefreshAuraApplicationMaxCache("aura-max-settle")
    return changed == true
end

function Sources:OnResourceContextChanged()
    if self.active then
        self:CancelResourceWorldSettle()
        self:RequestAuraApplicationMaxSettle()
        if YHUD.RequestContextRefresh then
            return YHUD:RequestContextRefresh("resource-context")
        end
        return YHUD:Refresh("resource-context")
    end
end

function Sources:RefreshAuraApplicationMaxCache(reason)
    if not self.active then
        return false, false
    end
    if not (Spell and Spell.ReadMaxCumulativeAuraApplications) then
        if next(self.auraApplicationMaxSpellIDs or {}) then
            self.auraApplicationMaxRefreshPending = true
        end
        return false, false
    end
    local changed = false
    local complete = true
    for spellID in pairs(self.auraApplicationMaxSpellIDs or {}) do
        local ok, value, code = pcall(
            Spell.ReadMaxCumulativeAuraApplications,
            spellID
        )
        if not ok then
            value = nil
            code = "api-error"
        end
        if value then
            if self.auraApplicationMaxCache[spellID] ~= value then
                self.auraApplicationMaxCache[spellID] = value
                changed = true
            end
        elseif IsRetryableAuraApplicationMaxFailure(code) then
            complete = false
        end
    end
    if complete then
        self.auraApplicationMaxRefreshPending = false
    else
        self.auraApplicationMaxRefreshPending = true
    end
    if changed then
        if YHUD.RequestContextRefresh then
            YHUD:RequestContextRefresh(reason or "aura-max-spellbook")
        elseif self.profile then
            self:ApplyConfig(self.profile)
        end
    end
    return changed, complete
end

function Sources:OnRacialContextChanged()
    if not self.active then return false end
    local catalog = YHUD.MonitorCatalog
    local changed = UpdateBundleSignature(
        self.bundleSignature,
        catalog,
        self.profile
    )
    if self.racialContextEnabled == true
        and catalog
        and catalog.UpdatePlayerRacialSignature then
        local raceToken, _, _, racialChanged =
            catalog:UpdatePlayerRacialSignature(self.racialSignature)
        if raceToken and racialChanged == true then changed = true end
    end
    if changed ~= true then return false end
    if YHUD.RequestContextRefresh then
        return YHUD:RequestContextRefresh("racial-context")
    end
    return YHUD:Refresh("racial-context")
end

function Sources:OnSpellbookContextChanged()
    local maxChanged = self:RefreshAuraApplicationMaxCache(
        "aura-max-spellbook"
    )
    local racialChanged = self:OnRacialContextChanged()
    return maxChanged == true or racialChanged == true
end

function Sources:OnWorldContextChanged(_, isInitialLogin, isReloadingUi)
    local loginEntry = isInitialLogin == true or isReloadingUi == true
    local maxChanged = self:RefreshAuraApplicationMaxCache("aura-max-world")
    local racialChanged = self:OnRacialContextChanged()
    local scheduled = false
    if loginEntry or self.filteredAuraVisibilityRecovery then
        scheduled = self:ScheduleResourceWorldSettle()
    end
    local auraRecovered = false
    if self.auraIdentityTrusted == false then
        auraRecovered = self:OnAuraControlContextChanged(
            "PLAYER_ENTERING_WORLD"
        )
    end
    return maxChanged == true
        or racialChanged == true
        or scheduled == true
        or auraRecovered == true
end

function Sources:CancelAuraControlRefresh()
    local timer = self.auraControlRefreshTimer
    self.auraControlRefreshTimer = nil
    self.auraControlRecoveryPending = false
    self.auraControlRetryCount = 0
    if timer and timer.Cancel then timer:Cancel() end
    return timer ~= nil
end

function Sources:FlushAuraControlRefresh()
    self.auraControlRefreshTimer = nil
    if not self.active then return false end

    AddPerformanceStat("auraControlFlushes")
    local reconciled = false
    local displayCount = 0
    local trusted = Unit and Unit.IsPlayerHelpfulAuraIdentityTrusted
        and Unit.IsPlayerHelpfulAuraIdentityTrusted() == true
    local previousTrust = self.auraIdentityTrusted
    self.auraIdentityTrusted = trusted
    local view = YHUD.View
    if view and view.ReconcilePlayerHelpfulFilteredAuraDisplays
        and previousTrust ~= trusted
        and not (previousTrust == nil and trusted == true) then
        reconciled, displayCount =
            view:ReconcilePlayerHelpfulFilteredAuraDisplays(trusted)
        if displayCount and displayCount > 0 then
            AddPerformanceStat("auraControlDisplayRefreshes", displayCount)
        end
    end

    if not trusted then
        local retryCount = self.auraControlRetryCount or 0
        local newTimer = C_Timer and C_Timer.NewTimer
        if self.auraControlRecoveryPending == true
            and retryCount < AURA_CONTROL_RETRY_LIMIT
            and type(newTimer) == "function" then
            self.auraControlRetryCount = retryCount + 1
            self.auraControlRefreshTimer = newTimer(
                AURA_CONTROL_RETRY_DELAY,
                AuraControlRefreshTimerCallback
            )
            if self.auraControlRefreshTimer then return true end
        end
        self.auraControlRecoveryPending = false
        self.auraControlRetryCount = 0
        return reconciled == true
    end

    self.auraControlRecoveryPending = false
    self.auraControlRetryCount = 0

    local queued = false
    local queueCount = 0
    for index = 1, #self.activeResourceKeys do
        local sourceKey = self.activeResourceKeys[index]
        local handle = self.handles[sourceKey]
        if handle
            and PLAYER_FILTERED_AURA_RESOURCE_TYPES[handle._yhudTypeId] then
            Monitor:QueueSource(sourceKey, "aura-control-context", true)
            queued = true
            queueCount = queueCount + 1
        end
    end
    if queueCount > 0 then
        AddPerformanceStat("auraControlSourceQueues", queueCount)
    end
    return reconciled == true or queued
end

function Sources:OnAuraControlContextChanged(event, unit)
    if not self.active then return false end
    if (event == "UNIT_ENTERING_VEHICLE"
        or event == "UNIT_ENTERED_VEHICLE"
        or event == "UNIT_EXITED_VEHICLE"
        or event == "UNIT_FACTION")
        and unit ~= "player" then
        return false
    end

    AddPerformanceStat("auraControlEvents")
    local trusted = Unit and Unit.IsPlayerHelpfulAuraIdentityTrusted
        and Unit.IsPlayerHelpfulAuraIdentityTrusted() == true
    if trusted == false and self.auraIdentityTrusted ~= false then
        self.auraIdentityTrusted = false
        local view = YHUD.View
        if view and view.ReconcilePlayerHelpfulFilteredAuraDisplays then
            view:ReconcilePlayerHelpfulFilteredAuraDisplays(false)
        end
    end
    if event == "PLAYER_CONTROL_LOST"
        or event == "UNIT_ENTERING_VEHICLE"
        or event == "UNIT_ENTERED_VEHICLE" then
        self:CancelAuraControlRefresh()
        return true
    end

    self.auraControlRecoveryPending = true
    if self.auraControlRefreshTimer then
        if event == "PLAYER_CONTROL_GAINED"
            or event == "UNIT_EXITED_VEHICLE"
            or event == "UNIT_FACTION"
            or event == "CINEMATIC_STOP"
            or event == "PLAYER_ENTERING_WORLD" then
            self.auraControlRetryCount = 0
        end
        AddPerformanceStat("auraControlCoalesced")
        return true
    end
    self.auraControlRetryCount = 0
    if C_Timer and C_Timer.NewTimer then
        self.auraControlRefreshTimer = C_Timer.NewTimer(
            0,
            AuraControlRefreshTimerCallback
        )
        return self.auraControlRefreshTimer ~= nil
    end
    return self:FlushAuraControlRefresh()
end

local function ActiveTrinketBundleEnabled(profile)
    local entry = type(profile) == "table" and profile.entries
        and profile.entries[EQUIPMENT_TRIGGER_BUNDLE_ENTRY_KEY]
    if not entry or entry.bundleEnabled == false then return false end
    local monitor = type(profile.monitors) == "table"
        and profile.monitors[EQUIPMENT_TRIGGER_BUNDLE_MONITOR_ID]
    return monitor
        and monitor.entryKey == EQUIPMENT_TRIGGER_BUNDLE_ENTRY_KEY
        and monitor.enabled ~= false
        or false
end

local function DeferActiveTrinketProjection(sources)
    if sources.activeTrinketProjectionPending ~= true then
        sources.activeTrinketProjectionPending = true
        AddPerformanceStat("activeTrinketCombatDeferred")
    end
    return true
end

local function SyncActiveTrinketProjection(sources)
    if not sources.active or not sources.profile
        or not ActiveTrinketBundleEnabled(sources.profile) then
        return false
    end
    if IsInCombat() then
        return DeferActiveTrinketProjection(sources)
    end

    local projection = GetEnabledActiveTrinketSources(
        YHUD.MonitorCatalog,
        sources.profile
    )
    local signature = BuildActiveTrinketProjectionSignature(projection)
    if signature == sources.activeTrinketProjectionSignature then
        if sources:SyncActiveTrinketView() then return true end
        AddPerformanceStat("activeTrinketNoops")
        return false
    end

    local startedAt = ProfileNowMS()
    local sourcesApplied, viewApplied = sources:ApplyConfig(sources.profile)
    if sourcesApplied then
        AddPerformanceStat("activeTrinketProjectionApplies")
    end
    FinishPerformanceStat("activeTrinketProjectionMS", startedAt)
    return viewApplied or sourcesApplied
end

function Sources:OnActiveTrinketEquipmentChanged(_, slotID)
    slotID = SafeNumber(slotID)
    if not self.active or (slotID ~= 13 and slotID ~= 14)
        or not ActiveTrinketBundleEnabled(self.profile) then
        return false
    end
    AddPerformanceStat("activeTrinketEvents")
    self.activeTrinketItemBySlot[slotID] = nil
    if IsInCombat() then
        return DeferActiveTrinketProjection(self)
    end
    return SyncActiveTrinketProjection(self)
end

function Sources:OnActiveTrinketItemData(_, itemID, success)
    if not self.active or not ActiveTrinketBundleEnabled(self.profile) then
        return false
    end
    AddPerformanceStat("activeTrinketEvents")
    if success ~= true then return false end

    itemID = SafeNumber(itemID)
    if not itemID then
        if IsInCombat() then
            return DeferActiveTrinketProjection(self)
        end
        return false
    end
    if self.activeTrinketItemBySlot[13] == itemID
        or self.activeTrinketItemBySlot[14] == itemID then
        if self:SyncActiveTrinketView() then return true end
        AddPerformanceStat("activeTrinketNoops")
        return false
    end
    if IsInCombat() then
        return DeferActiveTrinketProjection(self)
    end
    if not (Item and Item.GetInventoryItemID) then return false end

    local matched = false
    for slotID = 13, 14 do
        local equippedItemID = SafeNumber(
            Item.GetInventoryItemID("player", slotID)
        )
        if equippedItemID == itemID then
            self.activeTrinketItemBySlot[slotID] = itemID
            matched = true
        end
    end
    if not matched then
        AddPerformanceStat("activeTrinketNoops")
        return false
    end
    return SyncActiveTrinketProjection(self)
end

function Sources:RebindSpellFamily(baseSpellID, overrideSpellID)
    if not self.active then return false end
    baseSpellID = PositiveSpellID(baseSpellID)
    overrideSpellID = PositiveSpellID(overrideSpellID)
    if not baseSpellID and not overrideSpellID then return false end

    local catalog = YHUD.MonitorCatalog
    local source = FindEnabledSpellFamily(
        catalog,
        self.profile,
        baseSpellID,
        overrideSpellID
    )
    if not source then return false end

    local sourceKey = source.sourceKey
        or ("spell:" .. tostring(source.spellID or baseSpellID))
    local current = self.handles[sourceKey]
    local definition = BuildHotSpellDefinition(
        source,
        current,
        baseSpellID,
        overrideSpellID
    )
    if not definition then return false end

    if current and current.active == true
        and current._yhudTypeId == SPELL_SOURCE_TYPE
        and current._yhudIdentity == definition.identity
        and current._yhudSignature == definition.params.signature then
        Monitor:QueueSource(
            current.source or sourceKey,
            "spell-override",
            true
        )
        UpdateBundleSignature(self.bundleSignature, catalog, self.profile)
        return true
    end

    if current then
        Monitor:ReleaseSource(current)
        self.handles[sourceKey] = nil
    end
    local acquired, code = Monitor:AcquireSource(
        self,
        sourceKey,
        SPELL_SOURCE_TYPE,
        definition.params,
        "OnSourceState"
    )
    if not acquired then
        if YHUD.Stats then YHUD.Stats:Add("sourceErrors") end
        if YHUD.Diagnostics then
            YHUD.Diagnostics:Record("source-hot-rebind", code)
        end
        return false
    end
    acquired._yhudTypeId = SPELL_SOURCE_TYPE
    acquired._yhudIdentity = definition.identity
    acquired._yhudSignature = definition.params.signature
    self.handles[sourceKey] = acquired
    Monitor:QueueSource(
        acquired.source or sourceKey,
        "spell-override",
        true
    )
    UpdateBundleSignature(self.bundleSignature, catalog, self.profile)
    return true
end

function Sources:OnSpellBundleOverrideChanged(_, baseSpellID, overrideSpellID)
    return self:RebindSpellFamily(baseSpellID, overrideSpellID)
end

function Sources:OnCombatStateChanged(event)
    local startedAt = ProfileNowMS()
    AddPerformanceStat("combatStateEvents")
    local edgeEventField = event == "PLAYER_REGEN_DISABLED"
        and "combatEntryEvents" or "combatExitEvents"
    local edgeElapsedField = event == "PLAYER_REGEN_DISABLED"
        and "combatEntryMS" or "combatExitMS"
    AddPerformanceStat(edgeEventField)
    local inCombat
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    end
    if self.active and YHUD.View and YHUD.View.RefreshGlows then
        YHUD.View:RefreshGlows(inCombat)
    end
    if event == "PLAYER_REGEN_ENABLED" and self.active
        and self.resourceWorldSettlePending == true then
        self:FlushResourceWorldSettle(true)
    end
    if event == "PLAYER_REGEN_ENABLED" and self.active
        and self.activeTrinketProjectionPending == true then
        self.activeTrinketProjectionPending = false
        SyncActiveTrinketProjection(self)
    end
    if (event == "PLAYER_REGEN_ENABLED" or self.filteredAuraVisibilityRecovery)
        and self.active and Unit and Unit.SupportsFilteredAuraDisplay
        and Unit.SupportsFilteredAuraDisplay() == true then
        for index = 1, #self.activeResourceKeys do
            local sourceKey = self.activeResourceKeys[index]
            local handle = self.handles[sourceKey]
            if handle and FILTERED_AURA_RESOURCE_TYPES[handle._yhudTypeId] then
                AddPerformanceStat("combatAuraQueues")
                Monitor:QueueSource(
                    sourceKey,
                    "aura-visibility-public",
                    true
                )
            end
        end
    end
    if event == "PLAYER_REGEN_ENABLED" and self.active
        and self.filteredAuraVisibilityRecovery then
        self:ScheduleResourceWorldSettle()
    end
    if event == "PLAYER_REGEN_ENABLED" and self.active
        and self.talentMaxRefreshPending == true then
        self:RequestAuraApplicationMaxSettle()
        self:ArmAuraApplicationMaxSettle()
    end
    if event == "PLAYER_REGEN_ENABLED" and self.active
        and self.auraApplicationMaxRefreshPending == true then
        AddPerformanceStat("auraMaxRecoveryAttempts")
        local changed, complete = self:RefreshAuraApplicationMaxCache(
            "aura-max-access"
        )
        if changed == true then
            AddPerformanceStat("auraMaxRecoveryChanged")
            if YHUD.RequestContextRefresh then
                AddPerformanceStat("combatContextRequests")
            end
        elseif complete == true then
            AddPerformanceStat("auraMaxRecoveryUnchanged")
        else
            AddPerformanceStat("auraMaxRecoveryDeferred")
        end
    end
    FinishPerformanceStat("combatStateMS", startedAt)
    FinishPerformanceStat(edgeElapsedField, startedAt)
end

function Sources:RegisterContextEvents()
    if self.contextEventsRegistered then return true end
    local Event = YUI.Event
    if not (Event and Event.On) then return false end
    local playerClass = ResourceCatalog and ResourceCatalog:GetCurrentContext()
    if playerClass == "DRUID" then
        Event:On(
            "UPDATE_SHAPESHIFT_FORM",
            "OnResourceFormChanged",
            self,
            {
                moduleId = YHUD.PRODUCT_ID,
                traceName = "YHUD.ResourceForms",
            }
        )
        Event:On(
            "UNIT_DISPLAYPOWER",
            "OnResourceFormChanged",
            self,
            {
                unit = "player",
                moduleId = YHUD.PRODUCT_ID,
                traceName = "YHUD.ResourceForms",
            }
        )
    end
    Event:On(
        "PLAYER_SPECIALIZATION_CHANGED",
        "OnResourceContextChanged",
        self,
        {
            unit = "player",
            moduleId = YHUD.PRODUCT_ID,
            traceName = "YHUD.Resources",
        }
    )
    Event:On(
        "TRAIT_CONFIG_UPDATED",
        "OnResourceContextChanged",
        self,
        {
            moduleId = YHUD.PRODUCT_ID,
            traceName = "YHUD.Resources",
        }
    )
    Event:On(
        "PLAYER_TALENT_UPDATE",
        "OnResourceContextChanged",
        self,
        {
            moduleId = YHUD.PRODUCT_ID,
            traceName = "YHUD.Resources",
        }
    )
    Event:On(
        "ACTIVE_COMBAT_CONFIG_CHANGED",
        "OnResourceContextChanged",
        self,
        {
            moduleId = YHUD.PRODUCT_ID,
            traceName = "YHUD.Resources",
        }
    )
    Event:On(
        "SPELLS_CHANGED",
        "OnSpellbookContextChanged",
        self,
        {
            moduleId = YHUD.PRODUCT_ID,
            traceName = "YHUD.Racials",
        }
    )
    if YUI.IsRetail or YUI.IsForever then
        Event:On(
            "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED",
            "OnSpellBundleOverrideChanged",
            self,
            {
                moduleId = YHUD.PRODUCT_ID,
                traceName = "YHUD.SpellBundles",
            }
        )
        Event:On(
            "PLAYER_EQUIPMENT_CHANGED",
            "OnActiveTrinketEquipmentChanged",
            self,
            {
                moduleId = YHUD.PRODUCT_ID,
                traceName = "YHUD.ActiveTrinkets",
            }
        )
        Event:On(
            "ITEM_DATA_LOAD_RESULT",
            "OnActiveTrinketItemData",
            self,
            {
                moduleId = YHUD.PRODUCT_ID,
                traceName = "YHUD.ActiveTrinkets",
            }
        )
    end
    Event:On(
        "PLAYER_ENTERING_WORLD",
        "OnWorldContextChanged",
        self,
        {
            moduleId = YHUD.PRODUCT_ID,
            traceName = "YHUD.Resources",
        }
    )
    for _, event in ipairs({
        "PLAYER_CONTROL_LOST",
        "PLAYER_CONTROL_GAINED",
        "UPDATE_VEHICLE_ACTIONBAR",
        "UPDATE_OVERRIDE_ACTIONBAR",
        "UPDATE_POSSESS_BAR",
        "CINEMATIC_STOP",
    }) do
        Event:On(
            event,
            "OnAuraControlContextChanged",
            self,
            {
                moduleId = YHUD.PRODUCT_ID,
                traceName = "YHUD.AuraControl",
            }
        )
    end
    for _, event in ipairs({
        "UNIT_ENTERING_VEHICLE",
        "UNIT_ENTERED_VEHICLE",
        "UNIT_EXITED_VEHICLE",
        "UNIT_FACTION",
    }) do
        Event:On(
            event,
            "OnAuraControlContextChanged",
            self,
            {
                unit = "player",
                moduleId = YHUD.PRODUCT_ID,
                traceName = "YHUD.AuraControl",
            }
        )
    end
    Event:On(
        "PLAYER_DEAD",
        "OnPlayerDead",
        self,
        {
            moduleId = YHUD.PRODUCT_ID,
            traceName = "YHUD.Bloodlust",
        }
    )
    Event:On(
        "PLAYER_REGEN_DISABLED",
        "OnCombatStateChanged",
        self,
        {
            moduleId = YHUD.PRODUCT_ID,
            traceName = "YHUD.CombatState",
        }
    )
    Event:On(
        "PLAYER_REGEN_ENABLED",
        "OnCombatStateChanged",
        self,
        {
            moduleId = YHUD.PRODUCT_ID,
            traceName = "YHUD.CombatState",
        }
    )
    self.contextEventsRegistered = true
    return true
end

function Sources:Enable(profile)
    self:CancelResourceWorldSettle()
    self:CancelAuraApplicationMaxSettle()
    self:CancelAuraControlRefresh()
    self.active = true
    self.auraIdentityTrusted = Unit
        and Unit.IsPlayerHelpfulAuraIdentityTrusted
        and Unit.IsPlayerHelpfulAuraIdentityTrusted() == true
    self:RegisterContextEvents()
    return self:ApplyConfig(profile)
end

function Sources:EnableResourceOnly(profile)
    self:CancelResourceWorldSettle()
    self:CancelAuraApplicationMaxSettle()
    self:CancelAuraControlRefresh()
    self.active = true
    self.auraIdentityTrusted = nil
    -- Resource source types own their exact UNIT_POWER/spell/Aura events.
    -- Do not register the ordinary monitor/context event surface here.
    return self:ApplyConfig(profile)
end

function Sources:Refresh(reason, rehydrateTransient)
    if not self.active then return false end
    for sourceKey, handle in pairs(self.handles) do
        Monitor:QueueSource(
            sourceKey,
            reason or "yhud-refresh",
            rehydrateTransient == true
                and TRANSIENT_REHYDRATE_TYPES[handle._yhudTypeId] == true
        )
    end
    return true
end

function Sources:Disable()
    self:CancelResourceWorldSettle()
    self:CancelAuraApplicationMaxSettle()
    self:CancelAuraControlRefresh()
    self.auraIdentityTrusted = nil
    self.active = false
    self.talentMaxRefreshPending = false
    self.talentMaxRetryCount = 0
    self.talentMaxCache = {}
    self.talentMaxContext = nil
    self.auraApplicationMaxRefreshPending = false
    self.activeTrinketItemBySlot[13] = nil
    self.activeTrinketItemBySlot[14] = nil
    self.activeTrinketProjectionSignature = nil
    self.activeTrinketProjectionPending = false
    self.racialContextEnabled = false
    ResetRacialSignature(self.racialSignature)
    ResetBundleSignature(self.bundleSignature)
    self.profile = nil
    self.auraApplicationMaxSpellIDs = {}
    for index = #self.activeResourceProjectionKeys, 1, -1 do self.activeResourceProjectionKeys[index] = nil end
    for index = #self.resourceProjectionScratch, 1, -1 do self.resourceProjectionScratch[index] = nil end
    for index = #self.activeResourceKeys, 1, -1 do
        self.activeResourceKeys[index] = nil
    end
    for index = #self.resourcePresetScratch, 1, -1 do
        self.resourcePresetScratch[index] = nil
    end
    for sourceKey in pairs(self.timedWindows) do
        CancelTimedWindow(sourceKey)
    end
    Monitor:ReleaseSourceOwner(self)
    self.bloodlustSourceKeys = {}
    self:SetBloodlustConsumer(false)
    if SpecialResources and SpecialResources.DisableSimulator then
        SpecialResources:DisableSimulator()
    end
    if SpecialResources and SpecialResources.CancelChargeRetries then
        SpecialResources:CancelChargeRetries()
    end
    if SpecialResources and SpecialResources.DisableIronfur then
        SpecialResources:DisableIronfur()
    end
    if Bloodlust and Bloodlust.ReleaseOwner then
        Bloodlust:ReleaseOwner(self)
    end
    if YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(self)
    end
    self.contextEventsRegistered = false
    for sourceKey in pairs(self.handles) do
        self.handles[sourceKey] = nil
    end
    if YHUD.SwingTimers and YHUD.SwingTimers.SyncNativeSuppression then
        YHUD.SwingTimers:SyncNativeSuppression(nil)
    end
end

Sources:RegisterSourceTypes()
