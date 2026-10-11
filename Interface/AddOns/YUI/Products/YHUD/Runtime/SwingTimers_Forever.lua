local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
local Monitor = YUI and YUI.Monitor
if not (YHUD and YUI.IsForever == true and Monitor) then return end

local Swing = {}
YHUD.SwingTimers = Swing
Swing.SOURCE_TYPE = "yhud.player-swing"
local Unit = YUI.API and YUI.API.Unit
local swingTypes = Enum and Enum.PlayerSwingType or {}
local HANDS = {
    [swingTypes.MainHand or 0] = "mainhand",
    [swingTypes.OffHand or 1] = "offhand",
    [swingTypes.Ranged or 2] = "ranged",
}

local function Public(value)
    local security = YUI.API and YUI.API.Security
    if security and security.IsSecretValue and security.IsSecretValue(value) then return nil end
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    return value
end

local function Identity(params) return params.swingHand end
local function MapSwing(swingType) return HANDS[Public(swingType)] end
local function CreateState(params)
    return {
        sourceKind = "resource", resourceId = params.resourceId,
        nameKey = params.nameKey, color = params.color, valueKind = "continuous",
        hand = params.swingHand, capabilities = {}, available = true,
        resolved = true, isEnabled = true, secret = false,
        value = 0, maxValue = 1, opaqueRevision = 0,
        startedAt = nil, duration = nil, pending = true,
    }
end

local function Clear(source, state)
    Monitor:CancelTasks(source)
    state.startedAt, state.duration, state.durationResourceRaw = nil, nil, nil
    state.value, state.maxValue = 0, 1
    state.opaqueRevision = state.opaqueRevision + 1
    state.pending = true
end

local function Expire(source)
    Clear(source, source.state)
    Monitor:QueueSource(source, "swing-expired", true)
end

local function Start(source, state, duration)
    duration = Public(duration)
    if type(duration) ~= "number" or duration ~= duration or duration <= 0 or duration >= math.huge then return false end
    state.startedAt, state.duration = GetTime(), duration
    state.value = 1
    state.available, state.weaponEvidence = true, true
    state.initialized = true
    state.opaqueRevision = state.opaqueRevision + 1
    state.pending = true
    Monitor:CancelTasks(source)
    if not Monitor:ScheduleTask(source, "swing-expiry", state.startedAt + duration, Expire) then
        Clear(source, state)
    end
    return true
end

local function Capabilities(state)
    if Unit and Unit.ReadPlayerSwingCapabilities then
        Unit.ReadPlayerSwingCapabilities(state.capabilities)
    end
    local available = state.capabilities[state.hand]
    if available == nil then available = state.weaponEvidence == true end
    if state.available ~= available then state.available, state.pending = available, true end
    return available
end

local function Receive(source, state, event, duration, swingType)
    if event == "PLAYER_SWING" then
        if HANDS[Public(swingType)] ~= state.hand then return false end
        return Start(source, state, duration)
    end
    if event == "UNIT_ATTACK_SPEED" and Public(duration) ~= "player" then return false end
    if event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then
        state.weaponEvidence = nil
        Clear(source, state)
        Capabilities(state)
    elseif event == "WEAPON_SLOT_CHANGED" then
        local running = state.startedAt ~= nil
        state.weaponEvidence = nil
        Clear(source, state)
        if Capabilities(state) and running then
            Start(source, state, state.capabilities[state.hand .. "Duration"])
        end
    elseif not Capabilities(state) and state.startedAt then
        Clear(source, state)
    end
    state.pending = true
    return true
end

local function Read(source, state)
    if not state.initialized then
        Capabilities(state)
        state.initialized = true
    end
    state.durationResourceRaw = nil
    if state.startedAt and state.duration then
        if GetTime() >= state.startedAt + state.duration then
            Clear(source, state)
        else
            local object = state.durationObject
            if not object and C_DurationUtil and C_DurationUtil.CreateDuration then
                local ok, created = pcall(C_DurationUtil.CreateDuration)
                if ok then object, state.durationObject = created, created end
            end
            if object and object.SetTimeFromStart
                and pcall(object.SetTimeFromStart, object, state.startedAt, state.duration, 1) then
                state.durationResourceRaw = object
            end
        end
    end
    local changed = state.pending == true
    state.pending = nil
    return changed
end

function Swing:SyncNativeSuppression(handles)
    local enabled = false
    if handles then
        for _, handle in pairs(handles) do
            if handle.active == true and handle._yhudTypeId == self.SOURCE_TYPE then
                enabled = true
                break
            end
        end
    end
    if enabled == (self.nativeSuppressionClaimed == true) then return true end
    local api = YUI.API and YUI.API.BlizzardUI
    if not (api and api.Acquire and api.Release) then return false, "api-unavailable" end
    local ok, code
    if enabled then
        ok, code = api:Acquire(self, "swingTimers")
    else
        ok, code = api:Release(self, "swingTimers")
    end
    -- The API retains the owner claim on frame failures and retries protected
    -- operations after combat. Validation failures do not change ownership.
    if ok or code == "combat-deferred" or code == "frame-operation-failed" then
        self.nativeSuppressionClaimed = enabled
    end
    return ok, code
end

function Swing:RegisterSourceType()
    if self.registered then return true end
    local registered, code = Monitor:RegisterSourceType(self.SOURCE_TYPE, {
        getIdentity = Identity, createState = CreateState, read = Read, onEvent = Receive,
        events = {
            { event = "PLAYER_SWING", identityArg = 2, mapIdentity = MapSwing, synchronous = true },
            { event = "WEAPON_SLOT_CHANGED", all = true },
            { event = "UNIT_ATTACK_SPEED", units = { "player" }, all = true },
            { event = "PLAYER_ENTERING_WORLD", all = true },
            { event = "PLAYER_DEAD", all = true },
        },
    })
    if not registered and code ~= "source-type-exists" then return nil, code end
    self.registered = true
    return true
end
