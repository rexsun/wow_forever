local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD or YUI.IsForever ~= true then return end

local Hawk = {
    SOURCE_TYPE = "yhud.forever-summon-hawk",
    SOURCE_KEY = "forever-summon-hawk",
}
YHUD.SummonHawk = Hawk

local BASE_SPELL = 1293241
local CAST_IDS = { BASE_SPELL, 1293525, 1293526, 1293527 }
local CASTS, SUMMONS = {}, { [1293248] = true, [1312637] = true }
for _, id in ipairs(CAST_IDS) do CASTS[id] = true end
local DURATION, WARNING, CAST_HISTORY = 18, 3, 16
local NATIVE_MATCH_WINDOW, NATIVE_SETTLE_DELAY = 5, 0.001
local TIMER_KEYS = { "hawk-clock-1", "hawk-clock-2" }
local LOSS_KEYS = { "hawk-loss-1", "hawk-loss-2" }
local Monitor

local function Public(value)
    local security = YUI.API and YUI.API.Security
    local isSecret = security and security.IsSecretValue or _G.issecretvalue
    if isSecret and isSecret(value) then return nil end
    return value
end

local function NumberIdentity(value)
    value = Public(value)
    return type(value) == "number" and value or nil
end

local function CreateState(params)
    local slots = {}
    for index = 1, 2 do
        slots[index] = {
            sourceKind = "buff-timer", spellID = BASE_SPELL, icon = params and params.icon,
            startTime = 0, duration = 0, modRate = 1,
            available = false, resolved = true, isEnabled = true, secret = false,
            expiring = false, revision = 0,
            index = index, clockVersion = 0,
        }
    end
    return { slots = slots, seenCasts = {}, castOrder = {}, castCursor = 0,
        nativeRead = {}, nativeStarts = {} }
end

function Hawk:GetSlotState(state, slot)
    if state and state.slots and (slot == 1 or slot == 2) then return state.slots[slot] end
end

local function CancelLoss(source, slot)
    if not slot.lossPending then return end
    slot.lossPending = nil
    Monitor:CancelTask(source, LOSS_KEYS[slot.index])
end

local function ClearSlot(source, slot)
    if not slot.available then return false end
    Monitor:CancelTask(source, TIMER_KEYS[slot.index])
    CancelLoss(source, slot)
    slot.clockVersion = slot.clockVersion + 1
    slot.castAt, slot.endAt, slot.nativeSlot, slot.nativeSpellID = nil, nil, nil, nil
    slot.spellID, slot.startTime, slot.duration = BASE_SPELL, 0, 0
    slot.available, slot.expiring = false, false
    slot.revision = slot.revision + 1
    return true
end

local function ArmClock(source, slot)
    -- One cancellable wake per eagle. The warning edge rearms it for expiry.
    local version, expiring = slot.clockVersion, slot.expiring
    local due = expiring and slot.endAt or slot.endAt - WARNING
    if not Monitor:ScheduleTask(source, TIMER_KEYS[slot.index], due, function(owner, _, now)
        if owner.consumerCount > 0 and slot.clockVersion == version and slot.expiring == expiring and now >= due then
            Monitor:RefreshSourceNow(owner, "summon-hawk-clock")
        end
    end) then
        ClearSlot(source, slot)
    end
end

local function SetClock(source, slot, start, duration, now)
    CancelLoss(source, slot)
    slot.clockVersion = slot.clockVersion + 1
    slot.startTime, slot.duration, slot.endAt = start, duration, start + duration
    slot.available, slot.expiring = true, now >= slot.endAt - WARNING
    slot.revision = slot.revision + 1
    ArmClock(source, slot)
    return true
end

local function AdvanceClocks(source, state, now)
    local changed = false
    for _, slot in ipairs(state.slots) do
        if slot.available then
            if now >= slot.endAt then
                changed = ClearSlot(source, slot) or changed
            elseif not slot.expiring and now >= slot.endAt - WARNING then
                slot.expiring = true
                slot.revision = slot.revision + 1
                ArmClock(source, slot)
                changed = true
            end
        end
    end
    return changed
end

local function AcceptCast(state, guid)
    guid = Public(guid)
    if type(guid) ~= "string" or guid == "" then return true end
    if state.seenCasts[guid] then return false end
    local index = state.castCursor % CAST_HISTORY + 1
    local previous = state.castOrder[index]
    if previous then state.seenCasts[previous] = nil end
    state.castOrder[index], state.seenCasts[guid], state.castCursor = guid, true, index
    return true
end

local function Cast(source, state, unit, guid, spellID)
    spellID = NumberIdentity(spellID)
    if Public(unit) ~= "player" or not CASTS[spellID] or not AcceptCast(state, guid) then return false end
    local now = GetTime()
    AdvanceClocks(source, state, now)
    local first, second = state.slots[1], state.slots[2]
    local slot = first
    if first.available and (not second.available or second.endAt < first.endAt) then slot = second end

    -- Retire the native association before the new cast gets its own clock.
    slot.castAt, slot.spellID = now, spellID
    slot.nativeSlot, slot.nativeSpellID = nil, nil
    return SetClock(source, slot, now, DURATION, now)
end

local function ReadNative(state, nativeSlot, now)
    local totem = YUI.API and YUI.API.Totem
    if not totem or not totem.ReadSlot then return nil end
    local sample = state.nativeRead
    local present = totem.ReadSlot(nativeSlot, sample)
    if present ~= true then return present end
    local id, start, duration = sample.spellID, sample.start, sample.duration
    if not (SUMMONS[id] or CASTS[id]) then return nil end
    if not start or start < 0 or start > now or start ~= start then return nil end
    if not duration or not (duration > 0 and start + duration < math.huge) then return nil end
    -- This source publishes ordinary seconds. Skip observations at other rates.
    if sample.rate ~= nil and sample.rate ~= 1 then return nil end
    return true, id, start, duration
end

local function BindNative(source, state, nativeSlot, id, start, duration, now)
    local lastStart = state.nativeStarts[nativeSlot]
    if (lastStart and start <= lastStart) or start + duration <= now then return false end
    local candidate
    for _, slot in ipairs(state.slots) do
        if slot.available and slot.endAt > now and not slot.nativeSlot
            and start >= slot.castAt and start - slot.castAt <= NATIVE_MATCH_WINDOW
            and (not CASTS[id] or id == BASE_SPELL or id == slot.spellID) then
            if candidate then return false end -- Ambiguous timing: keep both estimates.
            candidate = slot
        end
    end
    if not candidate then return false end
    state.nativeStarts[nativeSlot] = start
    candidate.nativeSlot, candidate.nativeSpellID = nativeSlot, id
    if candidate.startTime == start and candidate.duration == duration then return false end
    return SetClock(source, candidate, start, duration, now)
end

local function ScheduleLoss(source, state, slot, now)
    if slot.lossPending then return end
    local version, nativeSlot = slot.clockVersion, slot.nativeSlot
    local function ConfirmLoss(owner)
        if owner.consumerCount <= 0 or slot.clockVersion ~= version or slot.lossPending ~= ConfirmLoss then return end
        slot.lossPending = nil
        local current = GetTime()
        local present, id, start, duration = ReadNative(state, nativeSlot, current)
        if present == false or (present == true and start > state.nativeStarts[nativeSlot]) then
            ClearSlot(owner, slot)
            if present then BindNative(owner, state, nativeSlot, id, start, duration, current) end
            Monitor:RefreshSourceNow(owner, "summon-hawk-native-loss")
        end
    end
    if Monitor:ScheduleTask(source, LOSS_KEYS[slot.index], now + NATIVE_SETTLE_DELAY, ConfirmLoss) then
        slot.lossPending = ConfirmLoss
    end
end

local function ObserveNative(source, state, nativeSlot, now)
    local present, id, start, duration = ReadNative(state, nativeSlot, now)
    if present == nil then return false end
    for _, slot in ipairs(state.slots) do
        if slot.nativeSlot == nativeSlot then
            local boundStart = state.nativeStarts[nativeSlot]
            if present == false or start > boundStart then
                ScheduleLoss(source, state, slot, now)
            elseif start == boundStart and id == slot.nativeSpellID then
                CancelLoss(source, slot)
                if start + duration <= now then return ClearSlot(source, slot) end
                if slot.duration ~= duration then return SetClock(source, slot, start, duration, now) end
            end
            return false
        end
    end
    if present then return BindNative(source, state, nativeSlot, id, start, duration, now) end
    return false
end

local function OnEvent(source, state, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then return Cast(source, state, ...) end
    if event == "PLAYER_TOTEM_UPDATE" then
        local nativeSlot = NumberIdentity(...)
        if nativeSlot == 2 or nativeSlot == 3 then return ObserveNative(source, state, nativeSlot, GetTime()) end
        return false
    end
    if event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then
        local first = ClearSlot(source, state.slots[1])
        return ClearSlot(source, state.slots[2]) or first
    end
    return false
end

local function Read(source, state, reason)
    -- Synchronous events are dispatched by this read after mutating either slot.
    local advanced = AdvanceClocks(source, state, GetTime())
    return advanced or reason ~= "summon-hawk-clock"
end

function Hawk.RegisterSourceType()
    if Hawk.registered then return true end
    Monitor = YUI.Monitor
    if not Monitor then return nil, "monitor-unavailable" end
    local registered, code = Monitor:RegisterSourceType(Hawk.SOURCE_TYPE, {
        createState = CreateState,
        getIdentity = function() return CAST_IDS end,
        read = Read, onEvent = OnEvent,
        events = {
            { event = "UNIT_SPELLCAST_SUCCEEDED", unit = "player", identityArg = 3,
                mapIdentity = NumberIdentity, synchronous = true },
            { event = "PLAYER_TOTEM_UPDATE", all = true, synchronous = true },
            { event = "PLAYER_DEAD", all = true, synchronous = true },
            { event = "PLAYER_ENTERING_WORLD", all = true, synchronous = true },
        },
    })
    if not registered and code ~= "source-type-exists" then return nil, code end
    Hawk.registered = true
    return true
end
