local YUI = _G.YUI
if not YUI then return end

local YHUD = YUI.YHUD
if not YHUD then return end

local Monitor = YUI.Monitor
local Spell = YUI.API and YUI.API.Spell
local Unit = YUI.API and YUI.API.Unit
local CooldownViewer = YUI.API and YUI.API.CooldownViewer
local IsSecretValue = _G.issecretvalue or function() return false end

local SpecialResources = YHUD.SpecialResources or {}
YHUD.SpecialResources = SpecialResources

local WHIRLWIND_SIMULATOR = "fury-whirlwind"
local WHIRLWIND_DURATION = 20
local WHIRLWIND_MAX = 4
local WHIRLWIND_GENERATOR_RETRY_DELAY = 0.15
local WHIRLWIND_GENERATOR_RETRY_WINDOW = 0.30
local SEEN_CAST_LIMIT = 64
local THUNDER_TALENT = 436707
local WIDE_RANGE_TALENT = 203201
local UNHINGED_TALENT = 386628
local BLADESTORM_SPELL = 446035
local BLADESTORM_DURATION = 4

local GENERATORS = {
    [190411] = true,
    [6343] = true,
    [435222] = true,
}

local THUNDER_GENERATORS = {
    [6343] = true,
    [435222] = true,
}

local SPENDERS = {
    [23881] = true,
    [85288] = true,
    [280735] = true,
    [5308] = true,
    [202168] = true,
    [184367] = true,
    [335096] = true,
    [335097] = true,
}

local BLOODTHIRST_VARIANTS = {
    [23881] = true,
    [335096] = true,
}

local IRONFUR_SPELL = 192081
local IRONFUR_BASE_DURATION = 7
local IRONFUR_DURATION_TALENT = 393611
local IRONFUR_DURATION_TALENT_SECONDS = 9
local GUARDIAN_OF_ELUNE_TALENT = 155578
local MANGLE_SPELL = 33917
local FRENZIED_REGENERATION_SPELL = 22842

local simulator = SpecialResources.simulator or {
    id = nil,
    sourceKey = nil,
    value = 0,
    expiresAt = 0,
    timer = nil,
    eventsRegistered = false,
    seen = {},
    seenRing = {},
    seenCursor = 0,
    seenCount = 0,
    nameplateUnits = {},
    pendingGeneratorTimer = nil,
    pendingGeneratorSpellID = nil,
    pendingGeneratorUntil = 0,
    bladestormEndsAt = 0,
    thunderEnabled = false,
    wideRangeEnabled = false,
    unhingedEnabled = false,
    maxValue = WHIRLWIND_MAX,
    duration = WHIRLWIND_DURATION,
}
SpecialResources.simulator = simulator
simulator.seen = simulator.seen or {}
simulator.seenRing = simulator.seenRing or {}
simulator.seenCursor = simulator.seenCursor or 0
simulator.seenCount = simulator.seenCount or 0
simulator.nameplateUnits = simulator.nameplateUnits or {}
simulator.pendingGeneratorUntil = simulator.pendingGeneratorUntil or 0
simulator.bladestormEndsAt = simulator.bladestormEndsAt or 0
simulator.seenOrder = nil
SpecialResources.auraBackendOverride = nil
SpecialResources.shadowMatches = SpecialResources.shadowMatches or 0
SpecialResources.shadowMismatches = SpecialResources.shadowMismatches or 0
SpecialResources.chargeRetryTimers = SpecialResources.chargeRetryTimers or {}
local ironfur = SpecialResources.ironfur or {
    sourceKey = nil,
    entries = {},
    timer = nil,
    eventsRegistered = false,
    guardianOfEluneReady = false,
    guardianOfEluneEnabled = false,
    duration = IRONFUR_BASE_DURATION,
    revision = 0,
}
SpecialResources.ironfur = ironfur
ironfur.entries = ironfur.entries or {}

local ironfurEventOwner = SpecialResources.ironfurEventOwner or {}
SpecialResources.ironfurEventOwner = ironfurEventOwner

local function SafeNumber(value)
    if IsSecretValue(value) or type(value) ~= "number" then return nil end
    return value
end

local function GetTimeNow()
    local value = type(GetTime) == "function" and GetTime() or 0
    return SafeNumber(value) or 0
end

local function IsKnown(spellID)
    return Spell and Spell.IsKnownOrInSpellBook
        and Spell.IsKnownOrInSpellBook(spellID) == true
end

local function CancelIronfurTimer()
    local timer = ironfur.timer
    ironfur.timer = nil
    if timer and timer.Cancel then timer:Cancel() end
end

local function QueueIronfur(reason)
    if ironfur.sourceKey and Monitor and Monitor.QueueSource then
        Monitor:QueueSource(ironfur.sourceKey, reason)
    end
end

local function PruneIronfurEntries(now)
    now = now or GetTimeNow()
    local entries = ironfur.entries
    local write = 1
    for read = 1, #entries do
        local entry = entries[read]
        if entry and entry.expiresAt > now then
            if write ~= read then entries[write] = entry end
            write = write + 1
        end
    end
    local changed = write <= #entries
    for index = #entries, write, -1 do entries[index] = nil end
    if changed then ironfur.revision = ironfur.revision + 1 end
    return changed
end

local function ScheduleIronfurExpiry()
    CancelIronfurTimer()
    local now = GetTimeNow()
    PruneIronfurEntries(now)
    local nearest
    for index = 1, #ironfur.entries do
        local expiresAt = ironfur.entries[index].expiresAt
        if not nearest or expiresAt < nearest then nearest = expiresAt end
    end
    if not nearest then return end
    local delay = math.max(0, nearest - now)
    if C_Timer and C_Timer.NewTimer then
        ironfur.timer = C_Timer.NewTimer(delay, function()
            ironfur.timer = nil
            PruneIronfurEntries(GetTimeNow())
            QueueIronfur("ironfur-expired")
            ScheduleIronfurExpiry()
        end)
    end
end

function ironfurEventOwner:OnSpellcastSucceeded(_, unit, _, spellID)
    if unit ~= "player" then return end
    spellID = SafeNumber(spellID)
    if not spellID then return end
    if spellID == MANGLE_SPELL and ironfur.guardianOfEluneEnabled then
        ironfur.guardianOfEluneReady = true
        return
    end
    if spellID == FRENZIED_REGENERATION_SPELL then
        ironfur.guardianOfEluneReady = false
        return
    end
    if spellID ~= IRONFUR_SPELL or not ironfur.sourceKey then return end
    local duration = ironfur.duration
    if ironfur.guardianOfEluneReady then
        duration = duration + 3
        ironfur.guardianOfEluneReady = false
    end
    local startedAt = GetTimeNow()
    ironfur.entries[#ironfur.entries + 1] = {
        startedAt = startedAt,
        duration = duration,
        expiresAt = startedAt + duration,
    }
    ironfur.revision = ironfur.revision + 1
    ScheduleIronfurExpiry()
    QueueIronfur("ironfur-cast")
end

function ironfurEventOwner:OnPlayerReset()
    CancelIronfurTimer()
    for index = #ironfur.entries, 1, -1 do ironfur.entries[index] = nil end
    ironfur.guardianOfEluneReady = false
    ironfur.revision = ironfur.revision + 1
    QueueIronfur("ironfur-reset")
end

function ironfurEventOwner:OnShapeshiftFormChanged()
    if #ironfur.entries == 0 and ironfur.guardianOfEluneReady ~= true then
        return false
    end
    self:OnPlayerReset()
    return true
end

function SpecialResources:ConfigureIronfur(sourceKey)
    if ironfur.sourceKey == sourceKey
        and (sourceKey ~= nil or ironfur.eventsRegistered ~= true) then
        return true
    end
    if not sourceKey then
        ironfur.sourceKey = nil
        ironfurEventOwner:OnPlayerReset()
        if ironfur.eventsRegistered
            and YUI.Event and YUI.Event.OffOwner then
            YUI.Event:OffOwner(ironfurEventOwner)
        end
        ironfur.eventsRegistered = false
        ironfur.guardianOfEluneEnabled = false
        return true
    end
    ironfurEventOwner:OnPlayerReset()
    ironfur.sourceKey = sourceKey
    ironfur.duration = IsKnown(IRONFUR_DURATION_TALENT)
        and IRONFUR_DURATION_TALENT_SECONDS or IRONFUR_BASE_DURATION
    ironfur.guardianOfEluneEnabled = IsKnown(GUARDIAN_OF_ELUNE_TALENT)
    if not ironfur.eventsRegistered then
        local Event = YUI.Event
        if not (Event and Event.On) then return false end
        local options = {
            moduleId = YHUD.PRODUCT_ID,
            traceName = "YHUD.Ironfur",
        }
        Event:On("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcastSucceeded",
            ironfurEventOwner, {
                moduleId = options.moduleId,
                traceName = options.traceName,
                unit = "player",
            })
        Event:On("PLAYER_DEAD", "OnPlayerReset", ironfurEventOwner, options)
        Event:On("PLAYER_ALIVE", "OnPlayerReset", ironfurEventOwner, options)
        Event:On("PLAYER_UNGHOST", "OnPlayerReset", ironfurEventOwner, options)
        Event:On(
            "UPDATE_SHAPESHIFT_FORM",
            "OnShapeshiftFormChanged",
            ironfurEventOwner,
            options
        )
        ironfur.eventsRegistered = true
    end
    return true
end

function SpecialResources:DisableIronfur()
    CancelIronfurTimer()
    if YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(ironfurEventOwner)
    end
    ironfur.eventsRegistered = false
    ironfur.sourceKey = nil
    for index = #ironfur.entries, 1, -1 do ironfur.entries[index] = nil end
    ironfur.guardianOfEluneReady = false
end

local function CancelSimulatorTimer()
    local timer = simulator.timer
    simulator.timer = nil
    if timer and timer.Cancel then timer:Cancel() end
end

local function CancelWhirlwindGeneratorRetry()
    local timer = simulator.pendingGeneratorTimer
    simulator.pendingGeneratorTimer = nil
    simulator.pendingGeneratorSpellID = nil
    simulator.pendingGeneratorUntil = 0
    if timer and timer.Cancel then timer:Cancel() end
end

local function QueueSimulator(reason)
    if simulator.sourceKey and Monitor and Monitor.QueueSource then
        Monitor:QueueSource(simulator.sourceKey, reason)
    end
end

function SpecialResources:RequestChargeRetry(sourceKey)
    if type(sourceKey) ~= "string" or sourceKey == "" then return false end
    if self.chargeRetryTimers[sourceKey] then return true end
    if not (C_Timer and C_Timer.NewTimer) then
        return Monitor and Monitor.QueueSource
            and Monitor:QueueSource(sourceKey, "charge-retry") == true
    end
    self.chargeRetryTimers[sourceKey] = C_Timer.NewTimer(0, function()
        SpecialResources.chargeRetryTimers[sourceKey] = nil
        if Monitor and Monitor.QueueSource then
            Monitor:QueueSource(sourceKey, "charge-retry")
        end
    end)
    return true
end

function SpecialResources:CancelChargeRetries()
    for sourceKey, timer in pairs(self.chargeRetryTimers) do
        if timer and timer.Cancel then timer:Cancel() end
        self.chargeRetryTimers[sourceKey] = nil
    end
end

local function ClearSeenCasts()
    for castGUID in pairs(simulator.seen) do simulator.seen[castGUID] = nil end
    for index = 1, SEEN_CAST_LIMIT do
        simulator.seenRing[index] = nil
    end
    simulator.seenCursor = 0
    simulator.seenCount = 0
end

local function ClearNameplateUnits()
    for unit in pairs(simulator.nameplateUnits) do
        simulator.nameplateUnits[unit] = nil
    end
end

local function AddNameplateUnit(unit)
    if type(unit) == "string" and unit ~= "" then
        simulator.nameplateUnits[unit] = true
    end
end

local function SeedNameplateUnits()
    ClearNameplateUnits()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    local ok, plates = pcall(C_NamePlate.GetNamePlates, false)
    if not ok or type(plates) ~= "table" then return end
    for index = 1, #plates do
        local plate = plates[index]
        AddNameplateUnit(
            plate and (plate.namePlateUnitToken or plate.unitToken)
        )
    end
end

local function ResetSimulator(reason, clearSeen)
    CancelWhirlwindGeneratorRetry()
    CancelSimulatorTimer()
    local changed = simulator.value ~= 0 or simulator.expiresAt ~= 0
    simulator.value = 0
    simulator.expiresAt = 0
    simulator.bladestormEndsAt = 0
    if clearSeen ~= false then ClearSeenCasts() end
    if changed then QueueSimulator(reason or "simulator-reset") end
end

local function OnSimulatorExpired(timer)
    if simulator.timer ~= timer then return end
    simulator.timer = nil
    simulator.expiresAt = 0
    if simulator.value ~= 0 then
        simulator.value = 0
        QueueSimulator("simulator-expired")
    end
end

local function ScheduleSimulatorExpiry()
    CancelSimulatorTimer()
    local duration = simulator.duration or WHIRLWIND_DURATION
    simulator.expiresAt = GetTimeNow() + duration
    if C_Timer and C_Timer.NewTimer then
        simulator.timer = C_Timer.NewTimer(
            duration,
            OnSimulatorExpired
        )
    end
end

local function RememberCast(castGUID)
    if IsSecretValue(castGUID) or type(castGUID) ~= "string"
        or castGUID == "" then
        return true
    end
    if simulator.seen[castGUID] then return false end
    local cursor = (simulator.seenCursor % SEEN_CAST_LIMIT) + 1
    local evicted = simulator.seenRing[cursor]
    if evicted then
        simulator.seen[evicted] = nil
    else
        simulator.seenCount = simulator.seenCount + 1
    end
    simulator.seenCursor = cursor
    simulator.seenRing[cursor] = castGUID
    simulator.seen[castGUID] = true
    return true
end

local function IsEnemyInRange(unit, spellID)
    if not (Unit and Unit.Exists and Unit.Exists(unit)) then return false end
    if Unit.CanAttack and Unit.CanAttack(unit, "player") ~= true then return false end
    if Unit.IsDead and Unit.IsDead(unit) == true then return false end
    local inRange
    if Spell and Spell.IsInRange then
        inRange = Spell.IsInRange(spellID, unit)
    end
    if inRange ~= nil then return inRange == true end
    if type(CheckInteractDistance) == "function" then
        local wide = THUNDER_GENERATORS[spellID] == true
            and simulator.wideRangeEnabled == true
        local ok, result = pcall(
            CheckInteractDistance,
            unit,
            wide and 2 or 3
        )
        if ok and not IsSecretValue(result) then return result == true end
    end
    return false
end

local function HasEnemyInRange(spellID)
    if IsEnemyInRange("target", spellID) then return true end
    for unit in pairs(simulator.nameplateUnits) do
        if IsEnemyInRange(unit, spellID) then return true end
    end
    return false
end

local function GenerateWhirlwindStacks(reason)
    CancelWhirlwindGeneratorRetry()
    simulator.value = WHIRLWIND_MAX
    ScheduleSimulatorExpiry()
    QueueSimulator(reason or "simulator-generated")
end

local function OnWhirlwindGeneratorRetry(timer)
    if simulator.pendingGeneratorTimer ~= timer then return end
    local spellID = simulator.pendingGeneratorSpellID
    local validUntil = simulator.pendingGeneratorUntil or 0
    simulator.pendingGeneratorTimer = nil
    simulator.pendingGeneratorSpellID = nil
    simulator.pendingGeneratorUntil = 0
    if simulator.id ~= WHIRLWIND_SIMULATOR
        or not spellID or GetTimeNow() > validUntil then
        return
    end
    if HasEnemyInRange(spellID) then
        GenerateWhirlwindStacks("simulator-generated")
    end
end

local function ScheduleWhirlwindGeneratorRetry(spellID)
    CancelWhirlwindGeneratorRetry()
    if not (C_Timer and C_Timer.NewTimer) then return false end
    simulator.pendingGeneratorSpellID = spellID
    simulator.pendingGeneratorUntil = GetTimeNow()
        + WHIRLWIND_GENERATOR_RETRY_WINDOW
    local timer = C_Timer.NewTimer(
        WHIRLWIND_GENERATOR_RETRY_DELAY,
        OnWhirlwindGeneratorRetry
    )
    simulator.pendingGeneratorTimer = timer
    if not timer then
        simulator.pendingGeneratorSpellID = nil
        simulator.pendingGeneratorUntil = 0
        return false
    end
    return true
end

local function ShouldIgnoreSpender(spellID)
    if not simulator.unhingedEnabled
        or BLOODTHIRST_VARIANTS[spellID] ~= true then
        return false
    end
    return GetTimeNow() < (simulator.bladestormEndsAt or 0)
end

function SpecialResources:OnSpellcastSucceeded(_, unit, castGUID, spellID)
    if unit ~= "player" then return end
    spellID = SafeNumber(spellID)
    if not spellID then return end
    if simulator.id ~= WHIRLWIND_SIMULATOR then return end
    local generator = GENERATORS[spellID] == true
    local spender = SPENDERS[spellID] == true
    local bladestorm = spellID == BLADESTORM_SPELL
    if not generator and not spender and not bladestorm then return end
    if generator then
        if THUNDER_GENERATORS[spellID] and not simulator.thunderEnabled then return end
    elseif spender and simulator.value <= 0
        and simulator.pendingGeneratorTimer == nil then
        return
    end
    if not RememberCast(castGUID) then return end
    CancelWhirlwindGeneratorRetry()

    if bladestorm then
        simulator.bladestormEndsAt = simulator.unhingedEnabled
            and (GetTimeNow() + BLADESTORM_DURATION) or 0
        return
    end

    if generator then
        if HasEnemyInRange(spellID) then
            GenerateWhirlwindStacks("simulator-generated")
        else
            ScheduleWhirlwindGeneratorRetry(spellID)
        end
        return
    end

    if simulator.value <= 0 then return end
    if ShouldIgnoreSpender(spellID) then return end
    simulator.value = math.max(0, simulator.value - 1)
    if simulator.value == 0 then
        CancelSimulatorTimer()
        simulator.expiresAt = 0
    end
    QueueSimulator("simulator-consumed")
end

function SpecialResources:OnNameplateAdded(_, unit)
    if simulator.id == WHIRLWIND_SIMULATOR then
        AddNameplateUnit(unit)
    end
end

function SpecialResources:OnNameplateRemoved(_, unit)
    if type(unit) == "string" then
        simulator.nameplateUnits[unit] = nil
    end
end

function SpecialResources:OnPlayerStateReset()
    ResetSimulator("simulator-player-reset", true)
end

function SpecialResources:RegisterSimulatorEvents()
    if simulator.eventsRegistered then return true end
    local Event = YUI.Event
    if not (Event and Event.On) then return false end
    local options = {
        moduleId = YHUD.PRODUCT_ID,
        traceName = "YHUD.SpecialResources",
    }
    local spellcastOptions = {
        moduleId = options.moduleId,
        traceName = options.traceName,
        unit = "player",
    }
    Event:On(
        "UNIT_SPELLCAST_SUCCEEDED",
        "OnSpellcastSucceeded",
        self,
        spellcastOptions
    )
    Event:On("NAME_PLATE_UNIT_ADDED", "OnNameplateAdded", self, options)
    Event:On("NAME_PLATE_UNIT_REMOVED", "OnNameplateRemoved", self, options)
    Event:On("PLAYER_DEAD", "OnPlayerStateReset", self, options)
    Event:On("PLAYER_ALIVE", "OnPlayerStateReset", self, options)
    Event:On("PLAYER_UNGHOST", "OnPlayerStateReset", self, options)
    simulator.eventsRegistered = true
    return true
end

function SpecialResources:ConfigureSimulator(sourceKey, simulatorID)
    if simulatorID ~= WHIRLWIND_SIMULATOR or not sourceKey then
        return self:DisableSimulator()
    end
    CancelWhirlwindGeneratorRetry()
    simulator.bladestormEndsAt = 0
    if simulator.id ~= simulatorID or simulator.sourceKey ~= sourceKey then
        ResetSimulator("simulator-configure", true)
    end
    simulator.id = simulatorID
    simulator.sourceKey = sourceKey
    simulator.maxValue = WHIRLWIND_MAX
    simulator.duration = WHIRLWIND_DURATION
    simulator.thunderEnabled = IsKnown(THUNDER_TALENT)
    simulator.wideRangeEnabled = IsKnown(WIDE_RANGE_TALENT)
    simulator.unhingedEnabled = IsKnown(UNHINGED_TALENT)
    SeedNameplateUnits()
    return self:RegisterSimulatorEvents()
end

function SpecialResources:DisableSimulator()
    local hadSimulator = simulator.id ~= nil or simulator.sourceKey ~= nil
    ResetSimulator("simulator-disable", true)
    simulator.id = nil
    simulator.sourceKey = nil
    simulator.thunderEnabled = false
    simulator.wideRangeEnabled = false
    simulator.unhingedEnabled = false
    simulator.maxValue = WHIRLWIND_MAX
    simulator.duration = WHIRLWIND_DURATION
    ClearNameplateUnits()
    if simulator.eventsRegistered and YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(self)
    end
    simulator.eventsRegistered = false
    return hadSimulator
end

function SpecialResources:SetAuraBackendOverride(mode)
    if mode ~= nil and mode ~= "direct" and mode ~= "bridge" then
        return false, "invalid-backend"
    end
    self.auraBackendOverride = mode
    return true
end

local function CreateState(params)
    local structuralMax = SafeNumber(params.fallbackMax)
        or SafeNumber(params.segmentCountFallback) or 1
    structuralMax = math.max(1, math.min(100, math.floor(structuralMax + 0.5)))
    return {
        sourceKind = "resource",
        providerKind = params.providerKind,
        resourceId = params.resourceId,
        classFile = params.classFile,
        specID = params.specID,
        nameKey = params.nameKey,
        descriptionKey = params.descriptionKey,
        color = params.color,
        valueKind = params.valueKind == "continuous"
            and "continuous" or "discrete",
        segmentCountFallback = structuralMax,
        structuralMax = structuralMax,
        thresholdPolicy = params.thresholdPolicy,
        value = 0,
        maxValue = structuralMax,
        valueRaw = nil,
        maxValueRaw = nil,
        rawValuesAvailable = false,
        percentRaw = nil,
        colorRaw = nil,
        available = true,
        secret = false,
        backendStatus = "initial",
        auraBackend = params.auraBackend or "direct-then-bridge",
        rechargeActive = false,
        rechargeDurationRaw = nil,
        opaqueRevision = 0,
        directState = params.auraBackend == "bridge-only" and nil or {},
        filteredAuraState = {},
        filteredAlternateAuraState = {},
        bridgeState = {},
        chargeState = {
            structuralMax = structuralMax,
            segmentCountFallback = structuralMax,
        },
        castCountState = {},
        percentState = {},
        durationState = {},
        durationBridgeState = {},
        runeDurationObjects = {},
        runeEntries = {},
        runeScratch = {},
        runeReady = {},
        runeDurations = {},
        ironfurDurationObjects = {},
        auraOptions = {
            requirePlayerSource = params.requirePlayerSource == true,
        },
    }
end

local function SetStructuralMax(state, structuralMax)
    structuralMax = SafeNumber(structuralMax) or state.segmentCountFallback
    structuralMax = math.max(1, math.min(100, math.floor(structuralMax + 0.5)))
    if state.structuralMax == structuralMax then return false end
    state.structuralMax = structuralMax
    state.maxValue = structuralMax
    return true
end

local function CommitRawRange(
    state,
    valueRaw,
    maxValueRaw,
    value,
    maxValue,
    secret,
    status
)
    local changed = state.secret ~= (secret == true)
        or state.value ~= value
        or state.maxValue ~= maxValue
        or state.backendStatus ~= status
    state.available = true
    state.secret = secret == true
    state.value = value
    state.maxValue = maxValue
    state.valueRaw = valueRaw
    state.maxValueRaw = maxValueRaw
    -- CommitRawRange is only called after the provider's public availability
    -- gate succeeds. Do not inspect opaque raw values just to rebuild that fact.
    state.rawValuesAvailable = true
    state.percentRaw = nil
    state.backendStatus = status
    state.colorRaw = nil
    if secret then
        state.opaqueRevision = (state.opaqueRevision or 0) + 1
        changed = true
    end
    return changed == true
end

local function CommitValue(state, valueRaw, secret, status, structuralMax)
    local structureChanged = SetStructuralMax(state, structuralMax)
    local value = not secret and SafeNumber(valueRaw) or nil
    if value then
        value = math.max(0, math.min(state.structuralMax, value))
    end
    local changed = structureChanged
        or state.secret ~= (secret == true)
        or state.value ~= value
        or state.backendStatus ~= status
    state.available = true
    state.secret = secret == true
    state.value = value
    state.maxValue = state.structuralMax
    state.backendStatus = status
    state.valueRaw = valueRaw
    state.maxValueRaw = state.structuralMax
    state.rawValuesAvailable = true
    state.percentRaw = nil
    state.colorRaw = nil
    if secret then
        state.opaqueRevision = (state.opaqueRevision or 0) + 1
        changed = true
    end
    return changed == true
end

local function CommitUnresolved(state, status)
    return CommitValue(
        state,
        0,
        false,
        status or "unresolved",
        state.structuralMax
    )
end

local function ReadCharge(source, state, reason)
    local charge = state.chargeState
    local _, _, code = Spell.ReadChargeResourceDisplay(
        source.params.spellID,
        charge
    )
    if charge.available ~= true then
        local rechargeChanged = state.rechargeActive == true
        state.rechargeActive = false
        state.rechargeDurationRaw = nil
        return CommitUnresolved(state, code or "charge-unavailable")
            or rechargeChanged
    end
    local rechargeChanged = state.rechargeActive ~= (charge.rechargeActive == true)
    state.rechargeActive = charge.rechargeActive == true
    state.rechargeDurationRaw = charge.rechargeDurationRaw
    if reason == "SPELL_UPDATE_CHARGES"
        and charge.rechargeDurationRaw == nil then
        SpecialResources:RequestChargeRetry(source.key)
    end
    local changed = CommitValue(
        state,
        charge.valueRaw,
        charge.secret == true,
        "charges",
        charge.structuralMax
    )
    if charge.secret ~= true and charge.rechargeDurationRaw ~= nil then
        state.opaqueRevision = (state.opaqueRevision or 0) + 1
        rechargeChanged = true
    end
    return changed or rechargeChanged
end

local function DetailedDiagnosticsEnabled()
    return YHUD.Diagnostics and YHUD.Diagnostics.detailEnabled == true
end

local function RecordShadowComparison(directState, bridgeState)
    if directState.secret == true or bridgeState.secret == true then return end
    local directValue = SafeNumber(directState.value)
    local bridgeValue = SafeNumber(bridgeState.value)
    if directValue == nil or bridgeValue == nil then return end
    if directValue == bridgeValue then
        SpecialResources.shadowMatches = SpecialResources.shadowMatches + 1
    else
        SpecialResources.shadowMismatches = SpecialResources.shadowMismatches + 1
    end
end

local function CommitFilteredAuraDisplay(state, backendStatus)
    local changed = state.available ~= true
        or state.secret ~= true
        or state.value ~= nil
        or state.valueRaw ~= nil
        or state.backendStatus ~= backendStatus
    state.available = true
    state.secret = true
    state.value = nil
    state.maxValue = state.structuralMax
    state.valueRaw = nil
    state.maxValueRaw = nil
    state.rawValuesAvailable = false
    state.backendStatus = backendStatus
    state.colorRaw = nil
    state.durationResourceRaw = nil
    if changed then state.opaqueRevision = (state.opaqueRevision or 0) + 1 end
    return changed
end

local function SupportsFilteredAuraDisplay()
    if Unit.SupportsFilteredAuraDisplay then
        if Unit.SupportsFilteredAuraDisplay() == true then return true end
    end
    return Unit.SupportsFilteredAuraDurationDisplay
        and Unit.SupportsFilteredAuraDurationDisplay() == true
end

local FILTERED_AURA_ABSENT = {
    ["direct-absent"] = true,
    ["direct-foreign-source"] = true,
}

local function ReadFilteredAuraPublicValue(params, spellID, target, options)
    local _, _, code = Unit.ReadAuraStackDisplay(
        params.unit,
        spellID,
        target,
        options
    )
    if target.secret ~= true and target.available == true
        and type(target.value) == "number" then
        return target.value, true
    end
    if FILTERED_AURA_ABSENT[code] then return 0, true end
    return nil, false
end

local function CommitFilteredAuraApplicationPublic(
    source,
    state,
    structuralMax
)
    local params = source.params
    local value, known = ReadFilteredAuraPublicValue(
        params,
        params.spellID,
        state.filteredAuraState,
        state.auraOptions
    )
    local alternateValue
    local alternateKnown = params.alternateSpellID == nil
    if params.alternateSpellID then
        alternateValue, alternateKnown = ReadFilteredAuraPublicValue(
            params,
            params.alternateSpellID,
            state.filteredAlternateAuraState,
            state.auraOptions
        )
    end

    if known and value > 0 then
        return true, CommitValue(
            state,
            value,
            false,
            "filtered-aura-application",
            structuralMax
        )
    end
    if alternateKnown and alternateValue and alternateValue > 0 then
        return true, CommitValue(
            state,
            alternateValue,
            false,
            "filtered-aura-application",
            structuralMax
        )
    end
    if known and alternateKnown then
        return true, CommitValue(
            state,
            0,
            false,
            "filtered-aura-application",
            structuralMax
        )
    end
    return false, false
end

local function ReadAura(source, state)
    local params = source.params
    if state.auraBackend == "filtered-only" then
        if SupportsFilteredAuraDisplay() then
            -- Public values affect visibility only; the engine owns presentation.
            if Unit.IsAuraRestricted and Unit.IsAuraRestricted() == false then
                local handled, changed = CommitFilteredAuraApplicationPublic(
                    source, state, state.structuralMax
                )
                if handled then return changed end
            end
            return CommitFilteredAuraDisplay(state, "filtered-aura-application")
        end
        return CommitUnresolved(state, "filtered-aura-unavailable")
    end
    local bridgeOnly = state.auraBackend == "bridge-only"
        or params.auraBackend == "bridge-only"
    local auraRestricted = bridgeOnly
        and Unit.IsAuraRestricted
        and Unit.IsAuraRestricted() == true
    if SupportsFilteredAuraDisplay() then
        if not auraRestricted then
            local handled, changed = CommitFilteredAuraApplicationPublic(
                source,
                state,
                state.structuralMax
            )
            if handled then return changed end
        end
        return CommitFilteredAuraDisplay(
            state,
            "filtered-aura-application"
        )
    end
    local override = SpecialResources.auraBackendOverride
    local direct = state.directState
    local directCode
    if not bridgeOnly then
        _, _, directCode = Unit.ReadAuraStackDisplay(
            params.unit,
            params.spellID,
            direct,
            state.auraOptions
        )
    end
    if not bridgeOnly and override ~= "bridge"
        and directCode == nil and direct.available == true then
        if DetailedDiagnosticsEnabled()
            and params.bridgeCategory and params.bridgeCooldownID
            and CooldownViewer and CooldownViewer.ReadAuraStackDisplay then
            CooldownViewer:ReadAuraStackDisplay(
                params.bridgeCategory,
                params.bridgeCooldownID,
                state.bridgeState
            )
            RecordShadowComparison(direct, state.bridgeState)
        end
        return CommitValue(
            state,
            direct.valueRaw,
            direct.secret == true,
            "direct",
            state.structuralMax
        )
    end

    if (bridgeOnly or override ~= "direct") and params.bridgeCategory
        and params.bridgeCooldownID and CooldownViewer
        and CooldownViewer.ReadAuraStackDisplay then
        local bridge = state.bridgeState
        local _, _, bridgeCode = CooldownViewer:ReadAuraStackDisplay(
            params.bridgeCategory,
            params.bridgeCooldownID,
            bridge,
            false,
            bridgeOnly == true
        )
        if bridgeCode == nil and bridge.available == true then
            return CommitValue(
                state,
                bridge.valueRaw,
                bridge.secret == true,
                bridge.backendStatus or "bridge",
                state.structuralMax
            )
        end
    end
    return CommitUnresolved(state, "unresolved")
end

local function ReadSpellCount(source, state)
    local castState = state.castCountState
    local _, _, code = Spell.ReadCastCountResourceDisplay(
        source.params.spellID,
        castState
    )
    if castState.available ~= true then
        return CommitUnresolved(state, code or "cast-count-unavailable")
    end
    return CommitValue(
        state,
        castState.valueRaw,
        castState.secret == true,
        "spell-count",
        state.structuralMax
    )
end

local function GetDurationObject(target, index)
    local object = target[index]
    if object then return object end
    if not (C_DurationUtil and C_DurationUtil.CreateDuration) then return nil end
    local ok, created = pcall(C_DurationUtil.CreateDuration)
    if ok then
        target[index] = created
        return created
    end
    return nil
end

local function CompareRuneEntries(left, right)
    if left.ready ~= right.ready then return left.ready == true end
    if left.finishAt ~= right.finishAt then
        return left.finishAt < right.finishAt
    end
    return left.index < right.index
end

local function ReadRunes(_, state)
    if type(GetRuneCooldown) ~= "function" then
        return CommitUnresolved(state, "rune-api-unavailable")
    end
    local now = GetTimeNow()
    local readyCount = 0
    local entries = state.runeEntries
    local scratch = state.runeScratch
    local timingChanged = false
    for index = 1, 6 do
        local ok, startTime, duration, ready = pcall(GetRuneCooldown, index)
        ready = ok and not not ready
        local entry = entries[index]
        if not entry then
            entry = { index = index }
            entries[index] = entry
        end
        local previousStartTime = entry.startTime
        local previousDuration = entry.duration
        scratch[index] = entry
        entry.ready = ready
        entry.finishAt = math.huge
        entry.durationObject = nil
        entry.startTime = nil
        entry.duration = nil
        entry.countdownStartTime = nil
        entry.countdownDuration = nil
        if ready then
            readyCount = readyCount + 1
        elseif ok and type(startTime) == "number"
            and type(duration) == "number" and duration > 0 then
            local object = GetDurationObject(state.runeDurationObjects, index)
            if object and object.SetTimeFromStart
                and pcall(
                    object.SetTimeFromStart,
                    object,
                    startTime,
                    duration,
                    1
                ) then
                entry.finishAt = startTime + duration
                entry.durationObject = object
                entry.startTime = startTime
                entry.duration = duration
                entry.countdownStartTime = startTime
                entry.countdownDuration = duration
                if startTime > now then
                    entry.countdownStartTime = now
                    entry.countdownDuration = entry.finishAt - now
                end
            end
        end
        if previousStartTime ~= entry.startTime
            or previousDuration ~= entry.duration then
            timingChanged = true
        end
    end
    table.sort(scratch, CompareRuneEntries)
    local cellsChanged = timingChanged
    for position = 1, 6 do
        local entry = scratch[position]
        if state.runeReady[position] ~= entry.ready
            or state.runeDurations[position] ~= (
                entry.durationObject and entry or nil
            ) then
            cellsChanged = true
        end
        state.runeReady[position] = entry.ready
        state.runeDurations[position] = entry.durationObject and entry or nil
    end
    state.cellReadyRaw = state.runeReady
    state.cellDurationsRaw = state.runeDurations
    if cellsChanged then
        state.opaqueRevision = (state.opaqueRevision or 0) + 1
    end
    return CommitValue(state, readyCount, false, "runes", 6)
        or cellsChanged
end

local function ReadIronfur(_, state)
    local now = GetTimeNow()
    PruneIronfurEntries(now)
    local count = #ironfur.entries
    local latestIndex
    local latestExpiry = 0
    for index = 1, count do
        local entry = ironfur.entries[index]
        if entry.expiresAt > latestExpiry then
            latestExpiry = entry.expiresAt
            latestIndex = index
        end
    end
    state.timerEntriesRaw = count > 0 and ironfur.entries or nil
    state.durationResourceRaw = nil
    if latestIndex then
        local entry = ironfur.entries[latestIndex]
        local object = GetDurationObject(state.ironfurDurationObjects, 1)
        if object and object.SetTimeFromStart
            and pcall(object.SetTimeFromStart, object, entry.startedAt,
                entry.duration, 1) then
            state.durationResourceRaw = object
        end
    end
    local revisionChanged = state.ironfurRevision ~= ironfur.revision
    if revisionChanged then
        state.ironfurRevision = ironfur.revision
        state.opaqueRevision = (state.opaqueRevision or 0) + 1
    end
    return CommitRawRange(
        state,
        count,
        1,
        count,
        1,
        false,
        "ironfur-timers"
    ) or revisionChanged
end

local function ReadAdaptiveAura(source, state)
    local params = source.params
    local structuralMax = params.reducedMaxActive == true
        and params.reducedMax or params.fallbackMax
    if SupportsFilteredAuraDisplay() then
        local structureChanged = SetStructuralMax(state, structuralMax)
        local handled, changed = CommitFilteredAuraApplicationPublic(
            source,
            state,
            structuralMax
        )
        if handled then return changed or structureChanged end
        return CommitFilteredAuraDisplay(
            state,
            "filtered-aura-application"
        ) or structureChanged
    end
    local spellID = params.spellID
    if params.switchAuraSpellID and Unit.GetPlayerAuraBySpellID then
        local switchAura = Unit.GetPlayerAuraBySpellID(params.switchAuraSpellID)
        if switchAura then
            spellID = params.alternateSpellID
            structuralMax = params.alternateMax
        end
    end
    local direct = state.directState
    local _, _, code = Unit.ReadAuraStackDisplay(
        params.unit,
        spellID,
        direct,
        state.auraOptions
    )
    if code ~= nil or direct.available ~= true then
        return CommitValue(state, 0, false, code or "direct-absent", structuralMax)
    end
    return CommitValue(
        state,
        direct.valueRaw,
        direct.secret == true,
        "direct",
        structuralMax
    )
end

local function ReadStagger(source, state)
    local direct = state.percentState
    local _, _, code = Unit.ReadStaggerResourceDisplay(
        source.params.unit,
        direct
    )
    if direct.available ~= true then
        return CommitUnresolved(state, code or "stagger-unavailable")
    end
    local value = direct.value
    if direct.secret ~= true and type(value) == "number" then
        value = math.floor(value + 0.5)
    end
    return CommitRawRange(
        state,
        direct.valueRaw,
        direct.maxValueRaw,
        value,
        100,
        direct.secret,
        "stagger"
    )
end

local function ReadAbsorb(source, state)
    local params = source.params
    if params.bridgeCategory and params.bridgeCooldownID and CooldownViewer
        and CooldownViewer.ReadAuraStackDisplay then
        local bridge = state.bridgeState
        local _, _, code = CooldownViewer:ReadAuraStackDisplay(
            params.bridgeCategory, params.bridgeCooldownID, bridge, false, true
        )
        if code == nil and bridge.available == true
            and bridge.rawValuesAvailable == true then
            local changed = CommitRawRange(state, bridge.valueRaw, 100,
                bridge.value, 100, bridge.secret, "absorb-own-percent")
            state.percentRaw = bridge.valueRaw
            return changed
        end
    end
    local direct = state.percentState
    Unit.ReadAbsorbResourceDisplay(params.unit, params.capFraction, direct)
    if direct.available ~= true then
        return CommitUnresolved(state, "absorb-unavailable")
    end
    return CommitRawRange(state, direct.valueRaw, direct.maxValueRaw,
        direct.value, 100, direct.secret, "absorb-total-fallback")
end

local function ReadAuraDuration(source, state)
    local params = source.params
    if SupportsFilteredAuraDisplay() then
        local direct = state.durationState
        local _, _, code = Unit.ReadAuraDurationResourceDisplay(
            params.unit,
            params.spellID,
            direct
        )
        state.durationResourceRaw = nil
        if direct.secret ~= true and direct.available == true then
            return CommitValue(
                state,
                1,
                false,
                "filtered-aura-duration",
                state.structuralMax
            )
        end
        if code == "aura-absent" then
            return CommitValue(
                state,
                0,
                false,
                "filtered-aura-duration",
                state.structuralMax
            )
        end
        return CommitFilteredAuraDisplay(state, "filtered-aura-duration")
    end
    local direct = state.durationState
    local _, directChanged, code = Unit.ReadAuraDurationResourceDisplay(
        params.unit,
        params.spellID,
        direct
    )
    if direct.available == true then
        state.durationResourceRaw = direct.durationResourceRaw
        if directChanged then
            state.opaqueRevision = (state.opaqueRevision or 0) + 1
        end
        return CommitRawRange(
            state,
            direct.valueRaw,
            direct.maxValueRaw,
            direct.value,
            direct.maxValue,
            direct.secret,
            "aura-duration"
        )
    end

    if params.bridgeCategory and params.bridgeCooldownID
        and CooldownViewer and CooldownViewer.ReadAuraDisplay then
        local bridge = state.durationBridgeState
        local _, bridgeChanged, bridgeCode = CooldownViewer:ReadAuraDisplay(
            params.bridgeCategory,
            params.bridgeCooldownID,
            bridge
        )
        if bridge.available == true and bridge.cooldownActive == true
            and bridge.durationObject ~= nil then
            local changed = bridgeChanged == true
                or state.available ~= true
                or state.secret ~= true
                or state.backendStatus ~= "aura-duration-bridge"
            state.available = true
            state.secret = true
            state.value = nil
            state.maxValue = state.structuralMax
            state.valueRaw = nil
            state.maxValueRaw = nil
            state.rawValuesAvailable = true
            state.backendStatus = "aura-duration-bridge"
            state.colorRaw = nil
            state.durationResourceRaw = bridge.durationObject
            if bridgeChanged then
                state.opaqueRevision = (state.opaqueRevision or 0) + 1
            end
            return changed
        end
        code = bridgeCode or code
    end

    state.durationResourceRaw = nil
    return CommitUnresolved(state, code or "aura-duration-unavailable")
end

local function ReadSimulated(_, state)
    return CommitValue(
        state,
        simulator.value,
        false,
        "simulated",
        simulator.maxValue or WHIRLWIND_MAX
    )
end

local function GetSpellIdentity(params)
    return params.spellID
end

local function GetAuraDurationIdentity(params)
    return params.bridgeIdentity or params.spellID
end

local function GetSimulatorIdentity(params)
    return params.bridgeAuraIdentity or params.simulatorID
end

local function ClearTransient(_, state)
    state.valueRaw = nil
    state.maxValueRaw = nil
    state.rawValuesAvailable = false
    state.percentRaw = nil
    state.colorRaw = nil
    state.rechargeDurationRaw = nil
    state.cellReadyRaw = nil
    state.cellDurationsRaw = nil
    state.durationResourceRaw = nil
    state.timerEntriesRaw = nil
    local direct = state.directState
    if direct then direct.valueRaw = nil end
    local filteredAura = state.filteredAuraState
    if filteredAura then filteredAura.valueRaw = nil end
    local filteredAlternateAura = state.filteredAlternateAuraState
    if filteredAlternateAura then filteredAlternateAura.valueRaw = nil end
    local bridge = state.bridgeState
    if bridge then bridge.valueRaw = nil end
    local charge = state.chargeState
    if charge then
        charge.valueRaw = nil
        charge.maxValueRaw = nil
        charge.rechargeDurationRaw = nil
        charge.rawValuesAvailable = false
    end
    local castCount = state.castCountState
    if castCount then
        castCount.valueRaw = nil
        castCount.rawValuesAvailable = false
    end
    local percent = state.percentState
    if percent then
        percent.valueRaw = nil
        percent.maxValueRaw = nil
        percent.rawValuesAvailable = false
        percent.percentRaw = nil
    end
    local duration = state.durationState
    if duration then
        duration.valueRaw = nil
        duration.maxValueRaw = nil
        duration.durationResourceRaw = nil
        duration.rawValuesAvailable = false
    end
    local durationBridge = state.durationBridgeState
    if durationBridge then durationBridge.durationObject = nil end
end

SpecialResources.CreateState = CreateState
SpecialResources.ReadCharge = ReadCharge
SpecialResources.ReadAura = ReadAura
SpecialResources.ReadSpellCount = ReadSpellCount
SpecialResources.ReadRunes = ReadRunes
SpecialResources.ReadIronfur = ReadIronfur
SpecialResources.ReadAdaptiveAura = ReadAdaptiveAura
SpecialResources.ReadStagger = ReadStagger
SpecialResources.ReadAbsorb = ReadAbsorb
SpecialResources.ReadAuraDuration = ReadAuraDuration
SpecialResources.ReadSimulated = ReadSimulated
SpecialResources.GetSpellIdentity = GetSpellIdentity
SpecialResources.GetAuraDurationIdentity = GetAuraDurationIdentity
SpecialResources.GetSimulatorIdentity = GetSimulatorIdentity
SpecialResources.ClearTransient = ClearTransient
