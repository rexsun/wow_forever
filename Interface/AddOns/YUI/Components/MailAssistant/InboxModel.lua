local YUI = _G.YUI
if not (YUI and YUI.MailAssistant) then return end

local Model = {}
Model.__index = Model
YUI.MailAssistant.InboxModel = Model

-- Mail has no public stable ID. Tokens survive only an unchanged ordered
-- snapshot, an append, or confirmed changes caused by our own commands.
local function Same(left, right)
    return left and right and left.key == right.key
end

local function HasAssets(entry, mode)
    return entry and not entry.restricted
        and (entry.money > 0 or (mode ~= "gold" and #entry.items > 0))
end

local function CanSelect(entry)
    return entry ~= nil and not entry.restricted
end

local function CanDelete(entry)
    return CanSelect(entry) and entry.money == 0 and #entry.items == 0 and entry.deletable == true
end

function Model.New()
    return setmetatable({ entries = {}, selected = {}, queue = {}, retired = {}, serial = 0,
        state = "idle", completed = 0, total = 0, gold = 0 }, Model)
end

function Model:Adopt(snapshot, tokens)
    local entries, retained = {}, {}
    for index, data in ipairs(snapshot) do
        local token = tokens and tokens[index]
        if not token then self.serial = self.serial + 1; token = self.serial end
        entries[index] = { token = token, data = data }
        retained[token] = true
    end
    self.entries = entries
    for token in pairs(self.retired) do
        if not retained[token] then self.retired[token], self.selected[token] = nil, nil end
    end
    if self.pending then
        for index, entry in ipairs(entries) do
            if entry.token == self.pending.token then self.pending.index = index; break end
        end
    end
end

function Model:Reset(snapshot)
    self.selected, self.queue, self.retired = {}, {}, {}
    self.pending, self.anchor, self.mode = nil, nil, nil
    self.batchMode = nil
    self.state, self.reason = "idle", nil
    self.completed, self.total, self.gold = 0, 0, 0
    self:Adopt(snapshot or {})
end

function Model:Invalidate(snapshot, reason)
    local interrupted = self:IsBusy() or next(self.selected) ~= nil or next(self.queue) ~= nil
    self.selected, self.queue, self.retired = {}, {}, {}
    self.pending, self.anchor, self.mode = nil, nil, nil
    self:Adopt(snapshot or {})
    if interrupted then self.state, self.reason = "changed", reason or "changed" end
    return false, interrupted and "changed" or "refreshed"
end

function Model:CountSelected(first, last)
    local count = 0
    for index = first or 1, last or #self.entries do
        local entry = self.entries[index]
        if entry and self.selected[entry.token] then count = count + 1 end
    end
    return count
end

function Model:IsBusy()
    return self.state == "running" or self.pending ~= nil
end

function Model:Select(index, value, range)
    if self:IsBusy() then return false end
    local entry = self.entries[index]
    if not entry or not CanSelect(entry.data) then return false end
    local first = range and self.anchor or index
    first = math.max(1, math.min(first or index, #self.entries))
    for row = math.min(first, index), math.max(first, index) do
        local target = self.entries[row]
        if CanSelect(target.data) then self.selected[target.token] = value and true or nil end
    end
    self.anchor = index
    self.queue, self.mode = {}, nil
    self.state, self.reason = "idle", nil
    return true
end

function Model:SelectPage(first, last)
    if self:IsBusy() then return false end
    for index = first, math.min(last, #self.entries) do self:Select(index, true, false) end
    return true
end

function Model:Clear()
    if self:IsBusy() then return false end
    self.selected, self.queue, self.anchor, self.mode = {}, {}, nil, nil
    self.state, self.reason = "idle", nil
    return true
end

function Model:DeletionCandidates()
    local candidates, unread = {}, 0
    for _, entry in ipairs(self.entries) do
        if self.selected[entry.token] and CanDelete(entry.data) then
            candidates[#candidates + 1] = { token = entry.token, key = entry.data.key }
            if not entry.data.wasRead then unread = unread + 1 end
        end
    end
    return candidates, unread
end

function Model:Start(mode, approved)
    if self:IsBusy() then return false end
    if mode == "delete" then
        -- Destructive batches always require a freshly confirmed, frozen scope.
        local candidates = self:DeletionCandidates()
        if not approved or #approved == 0 or #candidates ~= #approved then return false end
        for index, candidate in ipairs(candidates) do
            if candidate.token ~= approved[index].token or candidate.key ~= approved[index].key then return false end
        end
        self.queue = {}
        self.completed, self.total, self.gold = 0, #approved, 0
        for _, candidate in ipairs(approved) do self.queue[candidate.token] = true end
        self.mode, self.batchMode, self.state, self.reason = mode, mode, "running", nil
        return true
    end
    if self.mode ~= mode or next(self.queue) == nil then
        self.queue = {}
        self.completed, self.total, self.gold = 0, 0, 0
        for _, entry in ipairs(self.entries) do
            if HasAssets(entry.data, mode) and (mode == "gold" or self.selected[entry.token]) then
                self.queue[entry.token] = true
                self.total = self.total + 1
            end
        end
    end
    if next(self.queue) == nil then return false end
    self.mode, self.batchMode, self.state, self.reason = mode, mode, "running", nil
    return true
end

function Model:Stop(reason)
    self.reason = reason or "stopped"
    self.state = self.pending and "stopping" or self.reason
end

function Model:FinishToken(token)
    if self.queue[token] then
        self.queue[token] = nil
        self.completed = self.completed + 1
    end
    if self.mode ~= "gold" then self.selected[token] = nil end
end

function Model:Next(freeSlots, reserve)
    if self.state ~= "running" or self.pending then return nil end
    for index = #self.entries, 1, -1 do
        local entry = self.entries[index]
        if self.queue[entry.token] then
            local data = entry.data
            if self.mode == "delete" then
                if not CanDelete(data) then self:Stop("changed"); return nil end
                self.pending = { index = index, token = entry.token, before = data, kind = "delete" }
                return self.pending
            elseif not HasAssets(data, self.mode) then
                self:FinishToken(entry.token)
            else
                local command = { index = index, token = entry.token, before = data }
                if data.money > 0 then
                    command.kind = "money"
                else
                    local item = data.items[#data.items]
                    if not item.currency and freeSlots <= reserve then
                        self:Stop(freeSlots == 0 and "full" or "reserve")
                        return nil
                    end
                    command.kind, command.slot, command.itemKey = "item", item.slot, item.key
                end
                self.pending = command
                return command
            end
        end
    end
    self.state, self.reason = "done", nil
    return nil
end

local function ExpectedTarget(command, after)
    local before = command.before
    if command.kind == "delete" then return after == nil and CanDelete(before) end
    if not after then
        return command.kind == "money" and #before.items == 0
            or command.kind == "item" and #before.items == 1 and before.money == 0
    end
    if before.identity ~= after.identity then return false end
    if command.kind == "money" then
        return after.money == 0 and before.itemKey == after.itemKey
    end
    if before.money ~= after.money or #before.items ~= #after.items + 1 then return false end
    local skipped, expected = false, {}
    for _, item in ipairs(before.items) do
        if not skipped and item.key == command.itemKey then skipped = true
        else expected[#expected + 1] = item.key end
    end
    table.sort(expected)
    return skipped and table.concat(expected, "\031") == after.itemKey
end

local function MatchSnapshot(model, snapshot, command, removeTarget)
    local entries, tokens, nextIndex = model.entries, {}, 1
    local dropped, target = false, nil
    for _, entry in ipairs(entries) do
        if command and entry.token == command.token then
            if removeTarget then
                if not ExpectedTarget(command, nil) then return nil end
                dropped = true
            else
                target = snapshot[nextIndex]
                if not target or not ExpectedTarget(command, target) then return nil end
                tokens[nextIndex], nextIndex = entry.token, nextIndex + 1
            end
        elseif Same(entry.data, snapshot[nextIndex]) then
            tokens[nextIndex], nextIndex = entry.token, nextIndex + 1
        elseif model.retired[entry.token] and not (model.pending and entry.token == model.pending.token) then
            -- Only an empty row confirmed by our own receipt may disappear later.
            -- The current command still needs an explicit acknowledgement,
            -- including deletion of a row emptied by an earlier collection.
            dropped = true
        else
            return nil
        end
    end
    if dropped then
        -- A moved old row can look like a deletion followed by an append.
        -- Without a stable server ID this receipt is ambiguous, so stop.
        for index = nextIndex, #snapshot do
            for _, entry in ipairs(entries) do
                if Same(entry.data, snapshot[index]) then return nil end
            end
        end
    end
    return tokens, target
end

function Model:Observe(snapshot)
    local unchanged = MatchSnapshot(self, snapshot)
    if unchanged then
        self:Adopt(snapshot, unchanged)
        return true, "unchanged"
    end
    local command = self.pending
    if command then
        local tokens, target = MatchSnapshot(self, snapshot, command, false)
        local removed = false
        if not tokens then
            tokens = MatchSnapshot(self, snapshot, command, true)
            removed = true
        end
        if tokens then
            if command.kind == "money" then self.gold = self.gold + command.before.money end
            if removed or not HasAssets(target, self.mode) then self:FinishToken(command.token) end
            if removed then self.selected[command.token] = nil end
            if command.kind ~= "delete" and not removed and target.money == 0 and #target.items == 0 then
                self.retired[command.token] = true
            end
            self.pending = nil
            self:Adopt(snapshot, tokens)
            if self.state == "stopping" then self.state = self.reason or "stopped" end
            return true, "acknowledged"
        end
    end
    return self:Invalidate(snapshot)
end

function Model:Fail(reason)
    -- Failure may arrive before an inbox update. Reconcile the outstanding
    -- receipt before allowing another command; the runtime bounds this wait.
    self:Stop(reason or "error")
end

Model.HasAssets = HasAssets
Model.CanSelect = CanSelect
Model.CanDelete = CanDelete
