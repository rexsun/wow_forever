local YUI = _G.YUI
if not YUI or not YUI.YChat then return end

local YChat = YUI.YChat
local MetadataRing = {}
YChat.MetadataRing = MetadataRing

local DEFAULT_CAPACITY = 128
local HARD_CAPACITY = 1000
local floor = math.floor
local type = type
local tableCreate = table.create

local ringsByFrame = setmetatable({}, { __mode = "k" })
local Ring = {}
Ring.__index = Ring

local function NewArray(capacity)
    if type(tableCreate) == "function" then return tableCreate(capacity) end
    return {}
end

local function ClampCapacity(value)
    value = floor(tonumber(value) or DEFAULT_CAPACITY)
    if value < 1 then return 1 end
    if value > HARD_CAPACITY then return HARD_CAPACITY end
    return value
end

local function PhysicalIndex(ring, bufferIndex)
    return ((ring.head + bufferIndex - 2) % ring.capacity) + 1
end

local function ClearSlot(ring, slot)
    local entry = ring.entries[slot]
    if entry ~= nil and ring.slotByEntry[entry] == slot then ring.slotByEntry[entry] = nil end
    ring.entries[slot] = nil
    ring.times[slot] = nil
    ring.labels[slot] = nil
    ring.sequences[slot] = nil
    ring.directions[slot] = nil
end

local function ValidateNewEntry(ring, entry)
    if entry == nil then return ring:Invalidate("MISSING_ENTRY") end
    local existingSlot = ring.slotByEntry[entry]
    if existingSlot and ring.entries[existingSlot] == entry then
        return ring:Invalidate("DUPLICATE")
    end
    return true
end

local function StoreSlot(ring, slot, entry, timestamp, label, direction)
    local previousEntry = ring.entries[slot]
    if previousEntry ~= nil and ring.slotByEntry[previousEntry] == slot then
        ring.slotByEntry[previousEntry] = nil
    end
    ring.nextSequence = ring.nextSequence + 1
    ring.entries[slot] = entry
    ring.times[slot] = timestamp
    ring.labels[slot] = label
    ring.sequences[slot] = ring.nextSequence
    ring.directions[slot] = direction
    if entry ~= nil then ring.slotByEntry[entry] = slot end
    return ring.nextSequence
end

function Ring:Capacity()
    return self.capacity
end

function Ring:Count()
    return self.count
end

function Ring:IsValid()
    return self.valid == true
end

function Ring:GetInvalidReason()
    return self.invalidReason
end

function Ring:Reset()
    for slot = 1, self.capacity do ClearSlot(self, slot) end
    self.head = 1
    self.count = 0
    self.nextSequence = 0
    self.valid = true
    self.invalidReason = nil
    return true
end

function Ring:Invalidate(reason)
    for slot = 1, self.capacity do ClearSlot(self, slot) end
    self.head = 1
    self.count = 0
    self.valid = false
    self.invalidReason = reason or "INVALID"
    return false, self.invalidReason
end

function Ring:PushFront(entry, timestamp, label)
    return self:Append(entry, timestamp, label)
end

function Ring:Append(entry, timestamp, label)
    if not self.valid then return false, self.invalidReason end
    if entry == nil then return self:Invalidate("MISSING_ENTRY") end
    local entries = self.entries
    local slotByEntry = self.slotByEntry
    local times = self.times
    local labels = self.labels
    local sequences = self.sequences
    local directions = self.directions
    local existingSlot = slotByEntry[entry]
    if existingSlot and entries[existingSlot] == entry then
        return self:Invalidate("DUPLICATE")
    end

    local capacity = self.capacity
    local count = self.count
    local head = self.head
    if count == 0 then
        head = 1
        self.head = head
        self.count = 1
    elseif count < capacity then
        head = head > 1 and head - 1 or capacity
        self.head = head
        self.count = count + 1
    else
        head = head > 1 and head - 1 or capacity
        self.head = head
    end

    local previousEntry = entries[head]
    if previousEntry ~= nil and slotByEntry[previousEntry] == head then
        slotByEntry[previousEntry] = nil
    end
    local sequence = self.nextSequence + 1
    self.nextSequence = sequence
    entries[head] = entry
    times[head] = timestamp
    labels[head] = label
    sequences[head] = sequence
    directions[head] = "front"
    slotByEntry[entry] = head
    return true, sequence
end

function Ring:PushBack(entry, timestamp, label)
    if not self.valid then return false, self.invalidReason end
    local entryOK, entryReason = ValidateNewEntry(self, entry)
    if not entryOK then return false, entryReason end
    if self.count >= self.capacity then return false, "FULL" end

    local slot
    if self.count == 0 then
        self.head = 1
        slot = 1
    else
        slot = PhysicalIndex(self, self.count + 1)
    end
    self.count = self.count + 1

    local sequence = StoreSlot(self, slot, entry, timestamp, label, "back")
    return true, sequence
end

function Ring:Backfill(entry, timestamp, label)
    return self:PushBack(entry, timestamp, label)
end

function Ring:GetByBufferIndex(bufferIndex)
    if not self.valid or type(bufferIndex) ~= "number" then return nil end
    bufferIndex = floor(bufferIndex)
    if bufferIndex < 1 or bufferIndex > self.count then return nil end

    local slot = PhysicalIndex(self, bufferIndex)
    return self.entries[slot], self.sequences[slot], self.times[slot], self.labels[slot], self.directions[slot]
end

function Ring:GetByBufferIndexInCallback(bufferIndex)
    if not self.valid or bufferIndex < 1 or bufferIndex > self.count then return nil end
    local slot = ((self.head + bufferIndex - 2) % self.capacity) + 1
    return self.entries[slot], self.sequences[slot], self.times[slot], self.labels[slot], self.directions[slot]
end

function Ring:GetDisplayMetadataInCallback(bufferIndex)
    if not self.valid or bufferIndex < 1 or bufferIndex > self.count then return nil end
    local slot = ((self.head + bufferIndex - 2) % self.capacity) + 1
    return self.entries[slot], self.labels[slot]
end

function Ring:GetByVisibleIndex(visibleIndex, scrollOffset)
    if type(visibleIndex) ~= "number" then return nil end
    if type(scrollOffset) ~= "number" then scrollOffset = 0 end
    return self:GetByBufferIndex(visibleIndex + scrollOffset)
end

function Ring:Find(entry)
    if not self.valid or entry == nil then return nil end
    local slot = self.slotByEntry[entry]
    if not slot or self.entries[slot] ~= entry then return nil end
    return self.entries[slot], self.sequences[slot], self.times[slot], self.labels[slot], self.directions[slot]
end

function Ring:Relabel(formatter)
    if not self.valid or type(formatter) ~= "function" then
        return false, self.valid and "FORMATTER_INVALID" or self.invalidReason
    end
    for index = 1, self.count do
        local slot = PhysicalIndex(self, index)
        local timestamp = self.times[slot]
        if timestamp == nil then
            self.labels[slot] = nil
        else
            local ok, label = pcall(formatter, timestamp)
            if not ok or type(label) ~= "string" or label == "" then
                return false, "RELABEL_FAILED"
            end
            self.labels[slot] = label
        end
    end
    return true
end

function MetadataRing:Create(capacity)
    capacity = ClampCapacity(capacity)
    local ring = setmetatable({
        capacity = capacity,
        head = 1,
        count = 0,
        nextSequence = 0,
        valid = true,
        invalidReason = nil,
        entries = NewArray(capacity),
        times = NewArray(capacity),
        labels = NewArray(capacity),
        sequences = NewArray(capacity),
        directions = NewArray(capacity),
        slotByEntry = setmetatable({}, { __mode = "k" }),
    }, Ring)
    return ring
end

function MetadataRing:EnsureForFrame(frame, capacity)
    if frame == nil then return nil, false end
    local ring = ringsByFrame[frame]
    local wanted = ClampCapacity(capacity)
    if ring and ring:Capacity() == wanted and ring:IsValid() then return ring, false end

    ring = self:Create(wanted)
    ringsByFrame[frame] = ring
    return ring, true
end

function MetadataRing:GetForFrame(frame)
    return frame and ringsByFrame[frame] or nil
end

function MetadataRing:ReleaseFrame(frame)
    if frame == nil then return false end
    local existed = ringsByFrame[frame] ~= nil
    ringsByFrame[frame] = nil
    return existed
end

MetadataRing.DEFAULT_CAPACITY = DEFAULT_CAPACITY
MetadataRing.HARD_CAPACITY = HARD_CAPACITY
