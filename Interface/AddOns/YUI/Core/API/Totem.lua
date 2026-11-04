local _, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI then return end
YUI.API = YUI.API or {}
if YUI.API.Totem then return end

-- Native selection owns identity. This service owns only its timer transaction;
-- it has no spell catalogue, display type, frame hooks, events or polling.
local Totem = {}
YUI.API.Totem = Totem

local function IsSecret(value)
    local security = YUI.API.Security
    if security and security.IsSecretValue then
        return security.IsSecretValue(value) == true
    end
    return _G.issecretvalue and _G.issecretvalue(value) == true or false
end

local function PublicSlot(value)
    if IsSecret(value) or type(value) ~= "number" or value ~= value
        or value <= 0 or value == math.huge or value % 1 ~= 0 then return nil end
    return value
end

function Totem.SupportsDuration()
    return (YUI.IsRetail == true or YUI.IsForever == true)
        and type(_G.GetTotemDuration) == "function"
end

local function Acquire(state, slot)
    local public = PublicSlot(slot)
    state.lastSlotKind = public and "public" or IsSecret(slot) and "secret" or "absent"
    if not public and not IsSecret(slot) then return nil, "slot-unavailable" end
    if not Totem.SupportsDuration() then return nil, "duration-api-unavailable" end
    state.reads = (state.reads or 0) + 1
    local ok, clock = pcall(_G.GetTotemDuration, slot)
    if not ok then
        state.rejections = (state.rejections or 0) + 1
        return nil, "duration-call-failed"
    end
    if clock == nil then
        state.emptyReads = (state.emptyReads or 0) + 1
        return nil, "duration-empty"
    end
    return clock, "ready"
end

local function ClearCandidate(state)
    state.candidate, state.candidateSlot, state.candidateStatus = nil, nil, nil
    state.selectionID, state.selected = nil, nil
end

function Totem.Reset(state, reason)
    if state.clock ~= nil or state.cooldownID ~= nil then
        state.revision = (state.revision or 0) + 1
    end
    state.clock, state.cooldownID, state.slot = nil, nil, nil
    state.pendingSlot, state.retryRevision, state.retryPending, state.pendingRecovery = nil, nil, nil, nil
    state.recoveryRevision = nil
    state.clearPending = nil
    state.phase, state.status = "ended", reason or "ended"
    ClearCandidate(state)
end

function Totem.MarkCleared(state)
    -- ClearTotemData is also the first instruction of a normal refresh.
    -- A replacement is published only after the native selection finishes.
    state.clearPending = true
    ClearCandidate(state)
end

function Totem.StageCandidate(state, slot, origin)
    state.candidateSlot = PublicSlot(slot)
    state.candidate, state.candidateStatus = nil, "slot-unavailable"
    state.candidateOrigin = origin
    if not state.candidateSlot then
        state.candidate, state.candidateStatus = Acquire(state, slot)
    end
end

function Totem.BeginSelection(state, cooldownID, preferredSlot)
    ClearCandidate(state)
    if state.cooldownID and state.cooldownID ~= cooldownID then
        Totem.Reset(state, "identity-changed")
    end
    state.selectionID = cooldownID
    state.recoveryRevision = nil
    state.phase = "refreshing"
    Totem.StageCandidate(state, preferredSlot, "preferred")
end

function Totem.CommitSelection(state, cooldownID)
    if not state.selectionID or state.selectionID ~= cooldownID then return false end
    state.selected = true
    state.commits = (state.commits or 0) + 1
    if state.candidateSlot then
        state.candidate, state.candidateStatus = Acquire(state, state.candidateSlot)
    end
    return true
end

local function Publish(state, cooldownID, slot, clock)
    if state.clock ~= clock or state.cooldownID ~= cooldownID or state.slot ~= slot then
        state.revision = (state.revision or 0) + 1
    end
    state.clock, state.cooldownID, state.slot = clock, cooldownID, slot
    state.pendingSlot, state.retryRevision, state.retryPending, state.pendingRecovery = nil, nil, nil, nil
    state.recoveryRevision = nil
    state.phase, state.status = "active", "ready"
end

local function MarkUnknown(state, cooldownID, slot, status, newSelection)
    -- An opaque refresh is not an end. Keep only the last confirmed public
    -- ownership slot, never its old clock, so Read can reacquire through the API
    -- after verifying the exact native identity is still publicly active.
    local recoverySlot = not slot and state.cooldownID == cooldownID and state.slot or nil
    if not (slot and state.slot == slot and state.cooldownID == cooldownID) then
        if state.clock ~= nil then state.revision = (state.revision or 0) + 1 end
        state.clock, state.slot = nil, slot or recoverySlot
    end
    local pendingSlot = slot or recoverySlot
    if newSelection or state.pendingSlot ~= pendingSlot then state.retryRevision = nil end
    state.cooldownID, state.pendingSlot = cooldownID, pendingSlot
    state.retryPending, state.pendingRecovery = true, recoverySlot ~= nil
    state.phase, state.status = "unknown", status or "candidate-unavailable"
end

function Totem.FinishSelection(state)
    if not state.selectionID then
        ClearCandidate(state)
        return
    end
    if not state.selected then
        Totem.Reset(state, "native-selection-absent")
        return
    end
    local id, slot, clock = state.selectionID, state.candidateSlot, state.candidate
    if clock ~= nil then
        Publish(state, id, slot, clock)
    else
        MarkUnknown(state, id, slot, state.candidateStatus, true)
    end
    state.clearPending = nil
    ClearCandidate(state)
end

function Totem.Read(state, cooldownID, active, slotReadable, slot, refreshRevision)
    refreshRevision = refreshRevision or false
    if state.cooldownID and state.cooldownID ~= cooldownID then
        Totem.Reset(state, "identity-changed")
    end
    if active == false then
        Totem.Reset(state, "inactive")
        return nil, "inactive"
    end
    if state.clearPending or state.phase == "refreshing" then
        if active == true and state.cooldownID == cooldownID then
            return state.clock, "refreshing"
        end
        return nil, "refreshing"
    end
    if slotReadable and not (PublicSlot(slot) or IsSecret(slot)) then
        Totem.Reset(state, "native-slot-absent")
        return nil, "native-slot-absent"
    end
    if active ~= true then return nil, "active-unavailable" end
    if state.recoveryRevision == refreshRevision and state.clock ~= nil
        and (not slotReadable or IsSecret(slot)) then return state.clock, "ready" end
    if slotReadable then
        local clock, code = Acquire(state, slot)
        if clock ~= nil then
            Publish(state, cooldownID, PublicSlot(slot), clock)
            return clock, "ready"
        end
        MarkUnknown(state, cooldownID, PublicSlot(slot), code, false)
    end
    if (not slotReadable or not PublicSlot(slot)) and state.pendingSlot and state.retryPending
        and (state.retryRevision ~= refreshRevision or state.retryRevision == nil) then
        -- One retry at the existing coalesced refresh boundary. No timer loop.
        state.retryRevision = refreshRevision
        local clock, code = Acquire(state, state.pendingSlot)
        if clock ~= nil then
            local recovered = state.pendingRecovery == true
            if recovered then state.recoveries = (state.recoveries or 0) + 1 end
            Publish(state, cooldownID, state.pendingSlot, clock)
            if recovered then state.recoveryRevision = refreshRevision end
            return clock, "ready"
        end
        state.status = code
    end
    if state.cooldownID == cooldownID and state.clock ~= nil
        and state.clearPending ~= true then
        return state.clock, state.phase == "unknown" and "continuing" or "ready"
    end
    return nil, state.status or "slot-unreadable"
end

function Totem.ReadDiagnostics(state, result)
    result = result or {}
    result.phase, result.status = state.phase or "idle", state.status or "unobserved"
    result.cooldownID, result.slot = state.cooldownID, state.slot
    result.hasClock = state.clock ~= nil
    result.lastSlotKind, result.candidateOrigin = state.lastSlotKind, state.candidateOrigin
    result.reads, result.rejections = state.reads or 0, state.rejections or 0
    result.emptyReads, result.commits = state.emptyReads or 0, state.commits or 0
    result.recoveries = state.recoveries or 0
    result.revision = state.revision or 0
    return result
end
