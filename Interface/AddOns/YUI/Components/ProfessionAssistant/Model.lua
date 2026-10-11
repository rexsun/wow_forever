local _, YUI = ...
if not YUI.IsForever then return end
local M = {}
YUI.ProfessionAssistantModel = M

function M.New()
    return { slots = {}, quality = 2, maxLevel = 1 }
end

function M.Contains(state, guid)
    for i = 1, 9 do
        local entry = state.slots[i]
        if entry and not entry.done and entry.item.guid == guid then return i end
    end
end

function M.Capacity(state)
    local count = 0
    for i = 1, 9 do
        local entry = state.slots[i]
        if not entry or entry.done then count = count + 1 end
    end
    return count
end

function M.Add(state, item)
    if not item or M.Contains(state, item.guid) or M.Capacity(state) == 0 then return false end
    -- Only a successful addition starts the next batch; pending equipment survives.
    for i = 1, 9 do
        if state.slots[i] and state.slots[i].done then state.slots[i] = nil end
    end
    for i = 1, 9 do
        if not state.slots[i] then
            state.slots[i] = { item = item }
            return true
        end
    end
    return false
end

function M.Next(state)
    for i = 1, 9 do
        local entry = state.slots[i]
        if entry and not entry.done then return entry, i end
    end
end

function M.Reconcile(state, byGUID, busyGUID)
    for i = 1, 9 do
        local entry = state.slots[i]
        if entry and not entry.done and entry.item.guid ~= busyGUID then
            if byGUID[entry.item.guid] then entry.item = byGUID[entry.item.guid]
            else state.slots[i] = nil end
        end
    end
end

function M.Filter(state, items, automatic)
    local lowest, current = nil, false
    for _, item in ipairs(items) do
        if item.level <= state.maxLevel then
            lowest = math.min(lowest or item.quality, item.quality)
            if item.quality <= state.quality then current = true end
        end
    end
    if lowest and (automatic or not current) then state.quality = lowest end
    local result = {}
    for _, item in ipairs(items) do
        if item.level <= state.maxLevel and item.quality <= state.quality then result[#result + 1] = item end
    end
    return result
end

function M.Complete(state, guid, loot)
    local index = M.Contains(state, guid)
    if not index then return false end
    state.slots[index].done = true
    state.slots[index].loot = loot or {}
    return true
end

-- Source identity is mandatory: unrelated corpse loot must never become a result.
function M.OwnsLoot(attempt, sources)
    if not attempt or not attempt.succeeded then return false end
    for _, guid in ipairs(sources) do if guid ~= attempt.guid then return false end end
    return #sources > 0
end
