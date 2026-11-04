local _, addon = ...
local YUI = _G.YUI or addon
local M = YUI and YUI.Monitor
local Sources = M and M.CommonSources
if not (YUI and YUI.IsRetail and Sources) then return end

local TYPE = "class-extra-monitor"
local definitions = {
    ["devourer-transform"] = { spellID = 1217607, castSpellID = 1221150 },
    ["brewmaster-elixir"] = { spellID = 455139, cooldownSpellID = 455180, duration = 15 },
}
local function Public(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    return value
end
local function Number(value)
    value = Public(value)
    if type(value) == "number" and value == value and value > -math.huge and value < math.huge then return value end
end
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil, "api-unavailable" end
    local ok, value, code = pcall(fn, ...)
    if not ok then return nil, "query-failed" end
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil, "result-secret" end
    return value, code
end
local function Set(state, key, value)
    if state[key] == value then return false end
    state[key] = value
    return true
end
local function RefreshDeadline(source)
    M:RefreshSourceNow(source, "class-extra-deadline")
end
local function Reset(source, state)
    M:CancelTasks(source)
    source.windowStart, source.castGUID, source.pendingCast = nil, nil, nil
    state.active, state.available, state.hasLast = false, false, false
    state.startTime, state.duration, state.elapsed, state.displayCount = 0, 0, 0, 0
    state.endedAt, state.issue = nil, nil
    state.resetSequence = state.resetSequence + 1
    state.sequence = state.sequence + 1
end
local function ReadTransform(source, state)
    local api = YUI.API and YUI.API.Unit
    local aura, code = Call(api and api.GetPlayerAuraBySpellID, source.params.spellID)
    if code or (aura ~= nil and type(aura) ~= "table") then
        local changed = Set(state, "resolved", false)
        changed = Set(state, "issue", code or "aura-unavailable") or changed
        return changed
    end
    local now, changed = GetTime(), false
    changed = Set(state, "resolved", true) or changed
    changed = Set(state, "issue", nil) or changed
    if aura then
        if not state.active then
            local duration, expiration = Number(aura.duration), Number(aura.expirationTime)
            local elapsed = duration and expiration and math.max(0, duration - math.max(0, expiration - now)) or 0
            state.session = state.session + 1
            state.startTime, state.elapsed = now - elapsed, elapsed
            state.displayCount, state.endedAt, source.castGUID = 0, nil, nil
            state.active, state.available, state.hasLast = true, true, true
            changed = true
        end
    elseif state.active then
        state.active, state.available = false, false
        state.elapsed, state.endedAt = math.max(0, now - state.startTime), now
        changed = true
    end
    return changed
end
local function Known(definition)
    local api = YUI.API and YUI.API.Spell
    local fn = api and (api.IsKnownOrInSpellBook or api.IsKnown)
    local first = Public(Call(fn, definition.spellID))
    local second = Public(Call(fn, definition.cooldownSpellID))
    if first == true or second == true then return true end
    if first == false and second == false then return false end
end
local function ReadElixir(source, state)
    local definition = definitions["brewmaster-elixir"]
    local api = YUI.API and YUI.API.Spell
    local now, startTime, duration, knownCooldown = GetTime()
    for _, id in ipairs({ definition.cooldownSpellID, definition.spellID }) do
        local cooldown = Call(api and api.GetCooldown, id)
        if type(cooldown) == "table" then
            local start, length = Number(cooldown.startTime), Number(cooldown.duration)
            if start and length then
                knownCooldown = true
                if start > 0 and length > 1.5 and start + length > now then
                    startTime, duration = start, length
                    break
                end
            end
        end
    end
    -- Readable cooldowns supersede the event window, including a confirmed ready state.
    -- Discard it so later restricted reads cannot revive an older fallback deadline.
    if knownCooldown then source.windowStart = nil end
    if not startTime and source.windowStart and source.windowStart + definition.duration > now then
        startTime, duration = source.windowStart, definition.duration
    end
    local active, enabled = startTime ~= nil, Known(definition) == true
    local resolved = active or knownCooldown == true
    local changed = Set(state, "active", active)
    changed = Set(state, "available", resolved and enabled) or changed
    changed = Set(state, "resolved", resolved) or changed
    changed = Set(state, "isEnabled", enabled) or changed
    changed = Set(state, "startTime", startTime or 0) or changed
    changed = Set(state, "duration", duration or 0) or changed
    changed = Set(state, "issue", not resolved and "cooldown-unavailable" or nil) or changed
    if active then
        M:ScheduleTask(source, "cooldown-end", startTime + duration, RefreshDeadline)
    else
        source.windowStart = nil
        M:CancelTasks(source)
    end
    return changed
end
local function Read(source, state, reason)
    if reason == "PLAYER_DEAD" then
        Reset(source, state)
        state.resolved = true
        return true
    end
    if reason == "PLAYER_ENTERING_WORLD" then Reset(source, state) end
    local changed
    if source.params.kind == "devourer-transform" then changed = ReadTransform(source, state)
    else changed = ReadElixir(source, state) end
    if source.pendingCast then
        local guid = source.pendingCast
        source.pendingCast = nil
        if state.active and (guid == true or guid ~= source.castGUID) then
            source.castGUID = guid ~= true and guid or nil
            state.displayCount = state.displayCount + 1
            changed = true
        end
    end
    if changed then state.sequence = state.sequence + 1 end
    return changed or reason == "PLAYER_ENTERING_WORLD"
end
local function Receive(source, _, event, first, second, third)
    local definition = definitions[source.params.kind]
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if Public(first) ~= "player" then return false end
        local spellID = Number(third)
        if source.params.kind == "devourer-transform" then
            if spellID ~= definition.castSpellID then return false end
            local guid = Public(second)
            source.pendingCast = type(guid) == "string" and guid or true
        elseif spellID ~= definition.spellID then return false end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        if source.params.kind ~= "brewmaster-elixir" then return false end
        if Number(first) == definition.cooldownSpellID or Number(second) == definition.cooldownSpellID then
            source.windowStart = GetTime()
        elseif Public(first) ~= nil and Number(first) ~= definition.spellID then return false end
    elseif event == "UNIT_AURA" then
        return source.params.kind == "devourer-transform" and Public(first) == "player"
    end
    return true
end
function Sources:DescribeClassExtra(kind)
    local definition = definitions[kind]
    if not definition then return nil, "unsupported-class-extra" end
    if not self.classExtraRegistered then
        local registered, code = M:RegisterSourceType(TYPE, {
            createState = function(params)
                return { sourceKind = params.kind, spellID = params.spellID, icon = params.icon,
                    active = false, available = false, hasLast = false, resolved = false, secret = false,
                    isEnabled = true, startTime = 0, duration = 0, elapsed = 0, displayCount = 0, session = 0, sequence = 0, resetSequence = 0 }
            end,
            read = Read, onEvent = Receive,
            events = {
                { event = "UNIT_AURA", unit = "player", all = true, synchronous = true },
                { event = "UNIT_SPELLCAST_SUCCEEDED", unit = "player", all = true, synchronous = true },
                { event = "SPELL_UPDATE_COOLDOWN", all = true, synchronous = true },
                { event = "PLAYER_ENTERING_WORLD", all = true, synchronous = true },
                { event = "PLAYER_DEAD", all = true, synchronous = true },
                { event = "SPELLS_CHANGED", all = true },
                { event = "ACTIVE_COMBAT_CONFIG_CHANGED", all = true },
                { event = "PLAYER_SPECIALIZATION_CHANGED", unit = "player", all = true },
                { event = "PLAYER_TALENT_UPDATE", all = true },
                { event = "TRAIT_CONFIG_UPDATED", all = true },
                { event = "PLAYER_REGEN_ENABLED", all = true },
            },
        })
        if not registered and code ~= "source-type-exists" then return nil, code end
        self.classExtraRegistered = true
    end
    local api = YUI.API and YUI.API.Spell
    return { key = "class-extra:" .. kind, type = TYPE,
        params = { kind = kind, spellID = definition.spellID,
            icon = api and api.GetTexture and api.GetTexture(definition.spellID) } }
end
