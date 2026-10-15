local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
local Monitor = YUI and YUI.Monitor
if not (YHUD and Monitor and (YUI.IsRetail or YUI.IsForever)) then return end

local Bars = { HEALTH_SOURCE = "yhud.player-health", CAST_SOURCE = "yhud.player-cast" }
YHUD.PlayerBars = Bars
local Unit = YUI.API and YUI.API.Unit
local CHANNEL_COLOR = { r = 0.26, g = 0.72, b = 0.64, a = 1 }
local FAILED_COLOR = { r = 0.79, g = 0.29, b = 0.29, a = 1 }
local EMPOWER_COLOR = { r = 0.86, g = 0.55, b = 0.28, a = 1 }
local TERMINAL = {
    UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_STOP = true, UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_INTERRUPTED = true, PLAYER_DEAD = true,
}
local FAILED = { UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true }
local START = {
    UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_EMPOWER_START = true,
}

local function Public(value)
    local security = YUI.API and YUI.API.Security
    if security and security.IsSecretValue and security.IsSecretValue(value) then return nil end
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    return value
end

local function CreateState(params)
    return {
        sourceKind = "resource", unit = "player", resourceId = params.resourceId,
        nameKey = params.nameKey, color = params.color, valueKind = "continuous",
        available = true, resolved = true, isEnabled = true, secret = false,
        value = 0, maxValue = 1, opaqueRevision = 0,
        castActive = false, castMode = "idle", castStage = 0, castStages = {},
    }
end

local function ClearTransient(_, state)
    state.castDisplayRaw, state.durationResourceRaw = nil, nil
    state.valueRaw, state.maxValueRaw, state.percentRaw = nil, nil, nil
    state.rawValuesAvailable = false
end

local function QueueStage(source)
    Monitor:QueueSource(source, "cast-stage", true)
end

local function Expire(source)
    source.castTerminal = "expired"
    Monitor:QueueSource(source, "cast-expired", true)
end

local function Receive(source, _, event, unit, castGUID)
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_DEAD" then
        source.castGUID, source.castFailureUntil = nil, nil
        source.castTerminal = event == "PLAYER_DEAD" and event or nil
        return true
    end
    if unit ~= "player" then return false end
    castGUID = Public(castGUID)
    if START[event] then
        source.castGUID, source.castTerminal = castGUID, nil
        source.castFailureUntil = nil
    elseif TERMINAL[event] then
        if FAILED[event] and not source.castGUID and not (source.state and source.state.castActive) then return false end
        if castGUID and source.castGUID and castGUID ~= source.castGUID then return false end
        -- A normal STOP following INTERRUPTED must not erase the brief failure.
        if not FAILED[source.castTerminal] then source.castTerminal = event end
    end
    return true
end

local function ReadCast(source, state)
    local info = Unit.GetCastInfo and Unit.GetCastInfo("player")
    local terminal = source.castTerminal
    local newCast = info and info.startTimeMS and source.castStart
        and info.startTimeMS ~= source.castStart
    if terminal and not newCast then info = nil end
    if newCast then source.castTerminal, terminal = nil, nil end
    Monitor:CancelTasks(source)
    state.castDisplayRaw, state.durationResourceRaw = nil, nil
    state.castActive, state.castStage, state.castTotal, state.castTickCount = false, 0, nil, 0
    state.castMode, state.color = "idle", source.params.color
    if info then
        source.castStart = info.startTimeMS
        state.castActive = true
        state.castMode = info.isEmpowered and "empower" or info.isChannel and "channel" or "cast"
        state.color = info.isEmpowered and EMPOWER_COLOR or info.isChannel and CHANNEL_COLOR or source.params.color
        local duration, channel = Unit.ReadCastDisplay(info, state)
        if info.isEmpowered and Unit.ReadPlayerEmpowerStages then
            local stages, total = state.castStages, state.castTotal
            state.castStage = nil
            if total and info.startTimeMS then
                local started = info.startTimeMS / 1000
                local now = GetTime()
                state.castStage = 0
                for index = 1, #stages do
                    if now >= started + stages[index] then state.castStage = index
                    else
                        Monitor:ScheduleTask(source, "cast-stage", started + stages[index], QueueStage)
                        break
                    end
                end
                Monitor:ScheduleTask(source, "cast-expiry", started + total, Expire)
            end
        else
            for index = #state.castStages, 1, -1 do state.castStages[index] = nil end
            if info.endTimeMS then
                Monitor:ScheduleTask(source, "cast-expiry", info.endTimeMS / 1000, Expire)
            end
        end
        state.castDisplayRaw = {
            name = info.displayNameRaw, icon = info.displayTextureRaw,
            duration = duration, channel = channel,
        }
        state.durationResourceRaw = duration
    elseif FAILED[terminal] then
        state.castActive, state.castMode, state.color = true, "failed", FAILED_COLOR
        source.castFailureUntil = source.castFailureUntil or (GetTime() + 0.6)
        state.castDisplayRaw = { name = terminal == "UNIT_SPELLCAST_INTERRUPTED"
            and YHUD:T("player_cast.interrupted", "施法被打断") or YHUD:T("player_cast.failed", "施法失败") }
        Monitor:ScheduleTask(source, "cast-expiry", source.castFailureUntil, Expire)
    else
        source.castStart, source.castGUID, source.castFailureUntil = nil, nil, nil
        for index = #state.castStages, 1, -1 do state.castStages[index] = nil end
    end
    if info then source.castFailureUntil = nil end
    state.value = state.castActive and 1 or 0
    state.opaqueRevision = state.opaqueRevision + 1
    return true
end

function Bars:RegisterSourceTypes()
    if self.registered then return true end
    if not (Unit and Unit.ReadHealthDisplay and Unit.GetCastInfo) then return false end
    local healthOK, healthCode = Monitor:RegisterSourceType(self.HEALTH_SOURCE, {
        getIdentity = function() return "player" end, createState = CreateState, afterDispatch = ClearTransient,
        read = function(_, state) local _, changed = Unit.ReadHealthDisplay("player", state) return changed end,
        events = {
            { event = "UNIT_HEALTH", unit = "player", all = true },
            { event = "UNIT_MAXHEALTH", unit = "player", all = true },
            { event = "PLAYER_ENTERING_WORLD", all = true },
        },
    })
    local events = {
        { event = "PLAYER_ENTERING_WORLD", all = true },
        { event = "PLAYER_DEAD", all = true },
    }
    for _, event in ipairs({
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_DELAYED",
        "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
        "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
    }) do events[#events + 1] = { event = event, unit = "player", all = true } end
    if YUI.IsRetail then
        for _, event in ipairs({ "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP" }) do
            events[#events + 1] = { event = event, unit = "player", all = true }
        end
    end
    local castOK, castCode = Monitor:RegisterSourceType(self.CAST_SOURCE, {
        getIdentity = function() return "player" end, createState = CreateState,
        read = ReadCast, onEvent = Receive, events = events, afterDispatch = ClearTransient,
    })
    self.registered = (healthOK or healthCode == "source-type-exists") and (castOK or castCode == "source-type-exists")
    return self.registered
end

function Bars:SyncNativeSuppression(profile, handles)
    local wanted = false
    if not self.renderFailed and profile and profile.playerCast and profile.playerCast.hideNative == true then
        for _, handle in pairs(handles or {}) do
            if handle.active == true and handle._yhudTypeId == self.CAST_SOURCE then wanted = true break end
        end
    end
    if wanted == (self.nativeSuppressionClaimed == true) then return true end
    local api = YUI.API and YUI.API.BlizzardUI
    if not (api and api.Acquire and api.Release) then return false end
    local ok, code
    if wanted then ok, code = api:Acquire(self, "playerCastBar")
    else ok, code = api:Release(self, "playerCastBar") end
    if ok or code == "combat-deferred" or code == "frame-operation-failed" then self.nativeSuppressionClaimed = wanted end
    return ok, code
end
