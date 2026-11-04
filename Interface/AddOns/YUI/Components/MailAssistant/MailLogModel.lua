local YUI = _G.YUI
local Assistant = YUI and YUI.MailAssistant
if not Assistant then return end

local LogModel = {}
Assistant.MailLogModel = LogModel
LogModel.RETENTION = 90 * 86400
LogModel.LIMIT = 2000

local function ItemKey(item)
    return item.assetKey or item.key
end

local function CopyItem(item, count)
    return { id = item.id, name = item.name, link = item.link, icon = item.icon,
        currency = item.currency, assetKey = ItemKey(item), count = count or item.count }
end

local function Quantities(items)
    local result = {}
    for _, item in ipairs(items) do
        local key = ItemKey(item)
        result[key] = (result[key] or 0) + item.count
    end
    return result
end

-- Only reductions explicitly covered by a take request can be receipts.
-- Reading, returning, deleting, or merely seeing a letter never grants credit.
local function Reduction(before, after, intent)
    if not intent then return nil end
    if after and before.logIdentity ~= after.logIdentity then return nil end
    local money = after and after.money or 0
    if money > before.money or (money ~= before.money and not intent.money) then return nil end
    local remaining = Quantities(after and after.items or {})
    local removed, used, gold = {}, {}, before.money - money
    for _, item in ipairs(before.items) do
        local key = ItemKey(item)
        local left = math.min(item.count, remaining[key] or 0)
        remaining[key] = (remaining[key] or 0) - left
        local delta = item.count - left
        if delta > 0 then
            used[item.key] = (used[item.key] or 0) + delta
            if not intent.all and used[item.key] > (intent.items[item.key] or 0) then return nil end
            removed[#removed + 1] = CopyItem(item, delta)
        end
    end
    for _, count in pairs(remaining) do if count ~= 0 then return nil end end
    local cod = after and after.cod or 0
    if cod > before.cod or (cod ~= before.cod and #removed == 0) then return nil end
    if gold == 0 and #removed == 0 then return nil end
    return { items = removed, used = used, gold = gold, cod = before.cod - cod,
        remainingItems = after and #after.items or 0, remainingGold = money }
end

local Tracker = {}
Tracker.__index = Tracker
function LogModel.NewTracker()
    return setmetatable({ entries = {}, serial = 0, ambiguous = 0 }, Tracker)
end

function Tracker:Reset(snapshot)
    self.entries = {}
    for index, data in ipairs(snapshot or {}) do
        self.serial = self.serial + 1
        self.entries[index] = { token = self.serial, data = data }
    end
end

function Tracker:Begin(kind, index, slot)
    local entry = self.entries[index]
    if not entry then return false end
    local data = entry.data
    if data.money == 0 and #data.items == 0 then return false end
    local intent = not entry.received and entry.intent or nil
    intent = intent or { items = {}, slots = {} }
    entry.received = nil
    if kind == "money" or kind == "all" then intent.money = true end
    if kind == "all" then intent.all = true end
    if kind == "item" then
        local found
        for _, item in ipairs(data.items) do
            if item.slot == slot then
                if not intent.slots[slot] then
                    intent.items[item.key] = (intent.items[item.key] or 0) + item.count
                    intent.slots[slot] = true
                end
                found = true
            end
        end
        if not found then return false end
    end
    entry.intent = intent
    return true
end

function Tracker:ClearIntents()
    for _, entry in ipairs(self.entries) do entry.intent = nil end
end

-- A bounded ordered match detects ambiguous duplicate letters. At most two
-- interpretations are needed: if there is more than one, record neither.
function Tracker:Observe(snapshot)
    local old, memo, states = self.entries, {}, 0
    local function Solve(i, j, dropped)
        local key = i .. ":" .. j .. ":" .. tostring(dropped)
        if memo[key] then return memo[key] end
        states = states + 1
        if states > 4096 then return { count = 2 } end
        local result = { count = 0 }
        memo[key] = result
        if i > #old then
            for tail = j, #snapshot do
                for _, entry in ipairs(old) do
                    if entry.data.key == snapshot[tail].key
                        or (dropped and entry.data.logIdentity == snapshot[tail].logIdentity) then return result end
                end
            end
            result.count = 1
            return result
        end
        local entry, after = old[i], snapshot[j]
        local function Path(nextJ, receipt)
            local nextDropped = dropped or nextJ == j
            local nextState = Solve(i + 1, nextJ, nextDropped)
            if nextState.count > 0 then
                result.count = math.min(2, result.count + nextState.count)
                result.nextJ, result.receipt, result.dropped = nextJ, receipt, nextDropped
            end
        end
        if after and entry.data.key == after.key then Path(j + 1)
        elseif after then
            local receipt = Reduction(entry.data, after, entry.intent)
            if receipt then Path(j + 1, receipt) end
        end
        local removed = Reduction(entry.data, nil, entry.intent)
        if removed then Path(j, removed)
        elseif entry.retired then Path(j) end
        return result
    end
    local match = Solve(1, 1, false)
    if match.count ~= 1 then
        if match.count > 1 then self.ambiguous = self.ambiguous + 1 end
        self:Reset(snapshot)
        return {}, false
    end
    local entries, receipts, j, dropped = {}, {}, 1, false
    for i, entry in ipairs(old) do
        local step = memo[i .. ":" .. j .. ":" .. tostring(dropped)]
        if step.receipt then
            step.receipt.token, step.receipt.before = entry.token, entry.data
            step.receipt.logId = entry.logId
            receipts[#receipts + 1] = step.receipt
            if entry.intent then
                if step.receipt.gold > 0 then entry.intent.money = false end
                for key, count in pairs(step.receipt.used) do
                    entry.intent.items[key] = math.max(0, (entry.intent.items[key] or 0) - count)
                end
                entry.intent.slots = {}
            end
        end
        if step.nextJ > j then
            local data = snapshot[j]
            entries[j] = { token = entry.token, data = data, intent = entry.intent, logId = entry.logId,
                received = entry.received or step.receipt ~= nil,
                retired = entry.retired or (step.receipt and data.money == 0 and #data.items == 0) }
        end
        j, dropped = step.nextJ, step.dropped
    end
    for index = j, #snapshot do
        self.serial = self.serial + 1
        entries[index] = { token = self.serial, data = snapshot[index] }
    end
    self.entries = entries
    return receipts, true
end

function Tracker:SetLogId(token, id)
    for _, entry in ipairs(self.entries) do if entry.token == token then entry.logId = id; return end end
end

function LogModel.Prune(store, now)
    local records, kept = type(store.records) == "table" and store.records or {}, {}
    local nextId = type(store.nextId) == "number" and store.nextId >= 0 and store.nextId < math.huge and store.nextId or 0
    local first = math.max(1, #records - LogModel.LIMIT + 1)
    for index = first, #records do
        local entry = records[index]
        if type(entry) == "table" and type(entry.at) == "number" and entry.at >= now - LogModel.RETENTION and entry.at <= now
            and type(entry.id) == "number" and entry.id > 0 and entry.id < math.huge and type(entry.character) == "string"
            and type(entry.party) == "string" and type(entry.subject) == "string"
            and type(entry.items) == "table" and type(entry.gold) == "number" and entry.gold >= 0 and entry.gold < math.huge
            and (entry.status == "received" or entry.status == "partial" or entry.status == "sent")
            and (entry.direction == "in" or entry.direction == "out") then
            local valid = #entry.items <= 16
            for _, item in ipairs(entry.items) do
                if type(item) ~= "table" or type(item.count) ~= "number" or item.count <= 0 or item.count == math.huge
                    or not (type(item.name) == "string" or type(item.link) == "string" or type(item.id) == "number") then valid = false; break end
            end
            if valid then kept[#kept + 1] = entry; nextId = math.max(nextId, entry.id) end
        end
    end
    store.records, store.nextId = kept, nextId
end

function LogModel.Append(store, entry, now)
    LogModel.Prune(store, now)
    store.nextId = store.nextId + 1
    entry.id, entry.at = store.nextId, now
    store.records[#store.records + 1] = entry
    if #store.records > LogModel.LIMIT then table.remove(store.records, 1) end
    return entry
end

function LogModel.Receive(store, receipt, character, now)
    local record
    if receipt.logId then
        for _, entry in ipairs(store.records) do if entry.id == receipt.logId then record = entry; break end end
    end
    if not record then
        record = LogModel.Append(store, { direction = "in", character = character,
            party = receipt.before.sender, subject = receipt.before.subject, items = {}, gold = 0, cod = 0 }, now)
    end
    for _, item in ipairs(receipt.items) do
        local found
        for _, saved in ipairs(record.items) do
            if ItemKey(saved) == ItemKey(item) then saved.count = saved.count + item.count; found = true; break end
        end
        if not found then record.items[#record.items + 1] = CopyItem(item) end
    end
    record.gold, record.cod = record.gold + receipt.gold, record.cod + receipt.cod
    record.remainingItems, record.remainingGold = receipt.remainingItems, receipt.remainingGold
    record.status = receipt.remainingItems == 0 and receipt.remainingGold == 0 and "received" or "partial"
    record.updatedAt = now
    return record.id
end

function LogModel.Filter(store, filter, now)
    local rows, goldIn, goldOut = {}, 0, 0
    local query = string.lower(filter.query or "")
    local from = filter.from or (filter.days and filter.days > 0 and now - filter.days * 86400) or 0
    if filter.days == 1 and not filter.from then
        local today = _G.date("*t", now)
        today.hour, today.min, today.sec = 0, 0, 0
        from = _G.time(today)
    end
    for index = #store.records, 1, -1 do
        local entry = store.records[index]
        local matches = (not filter.direction or filter.direction == "all" or entry.direction == filter.direction)
            and (not filter.character or filter.character == "all" or entry.character == filter.character)
            and entry.at >= from and (not filter.to or entry.at < filter.to)
        if matches and query ~= "" then
            local haystack = entry.party .. " " .. entry.character .. " " .. entry.subject
            for _, item in ipairs(entry.items) do haystack = haystack .. " " .. (item.name or item.link or "") end
            matches = string.find(string.lower(haystack), query, 1, true) ~= nil
        end
        if matches then
            rows[#rows + 1] = entry
            if entry.direction == "in" then goldIn = goldIn + entry.gold else goldOut = goldOut + entry.gold end
        end
    end
    return rows, goldIn, goldOut
end
