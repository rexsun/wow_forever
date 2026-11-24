local YUI = _G.YUI
if not YUI or not YUI.IsForever then return end
YUI.API = YUI.API or {}
if YUI.API.QuestItems then return end
local QuestItems = {}
YUI.API.QuestItems = QuestItems
local Security = YUI.API.Security
-- Quest 1920 and both use items verified on Forever 1.60.1.70862.
-- Only explicit missing identities are supplemented; no bag discovery.
local COMPATIBILITY = { [1920] = { 7308, 7247 } }
local COMPATIBILITY_ITEMS = {}
local EMPTY = {}
for _, ids in pairs(COMPATIBILITY) do
    for _, itemID in ipairs(ids) do COMPATIBILITY_ITEMS[itemID] = true end
end

-- Forever 1.60.1.70245, 15666a6e67938a1ab5caf041406464251db111ca.
-- Cold, event-coalesced reads. Missing/restricted native data returns nil.
-- ReadLog allocates one bounded quest-log snapshot.
local function Read(fn, ...)
    if type(fn) ~= "function" then return nil, nil, nil, nil, false end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil, nil, nil, nil, false end
    if Security and (Security.IsSecretValue(a) or Security.IsSecretValue(b)
        or Security.IsSecretValue(c) or Security.IsSecretValue(d)) then return nil, nil, nil, nil, false end
    return a, b, c, d, true
end

local function Number(value)
    return Security and Security.SafeNumber(value) or nil
end

local function Integer(value)
    value = Number(value)
    if value and value >= 0 and value <= 9007199254740991 and value == math.floor(value) then return value end
end

local function Field(record, key)
    if not (Security and Security.CanAccessTable(record)) then return nil end
    local ok, value = pcall(function() return record[key] end)
    if ok and not Security.IsSecretValue(value) then return value end
end

local function Length(record) return #record end
local function ArrayCount(record)
    if not (Security and Security.CanAccessTable(record)) then return nil end
    local count = Integer(Read(Length, record))
    if count and count <= 500 then return count end
end

-- Only the session's active custom mode can replace native watch membership.
-- These are optional integration interfaces, not a second owner of its state.
local TRACKING_METHODS = { "QuestLogSnapshot", "QuestInArea", "IsQuestFiltered", "AutoTrackOn" }
local function CustomTracker()
    local parent, tracker = _G.EllesmereUI, _G.EllesmereUIQuestTracker
    local registry = Field(parent, "_ModuleNS")
    local namespace = Field(registry, "EllesmereUIQuestTracker")
    if not Field(_G, "_EQT_DB") or Read(Field(namespace, "UseCustomTracker")) ~= true
        or Read(Field(tracker, "Cfg"), "enabled") ~= true then return nil end
    for _, key in ipairs(TRACKING_METHODS) do
        if type(Field(tracker, key)) ~= "function" then return nil end
    end
    if type(Field(parent, "CharData")) ~= "function" then return nil end
    return tracker, parent
end

local function CustomWatches(native)
    local tracker, parent = CustomTracker()
    if not tracker then return native end
    local state, _, _, _, stateOK = Read(Field(parent, "CharData"), "questTracker")
    if not stateOK or (state ~= nil and not Security.CanAccessTable(state)) then return native end
    local untracked, pinned = Field(state, "ctUntracked"), Field(state, "ctPinned")
    if state and (not Security.CanAccessTable(untracked) or not Security.CanAccessTable(pinned)) then return native end
    local rows, headers, _, _, snapshotOK = Read(Field(tracker, "QuestLogSnapshot"))
    local count = snapshotOK and ArrayCount(rows)
    if not count or not Security.CanAccessTable(headers) then return native end
    local auto, _, _, _, autoOK = Read(Field(tracker, "AutoTrackOn"))
    if not autoOK then return native end
    local tracked = {}
    for index = 1, count do
        local info = Field(rows, index)
        local id = Integer(Field(info, "questID"))
        if not Security.CanAccessTable(info) or (not id and Field(info, "isHeader") ~= true) then return native end
        if id and id > 0 and Field(info, "isHeader") ~= true and Field(untracked, id) ~= true then
            local selected = native[id] == true
            if not selected and Field(info, "isHidden") ~= true and Field(info, "isTask") ~= true
                and Field(info, "isBounty") ~= true then
                selected = Field(pinned, id) == true
                if not selected and auto == true then
                    local inArea, _, _, _, areaOK = Read(Field(tracker, "QuestInArea"), info, Field(headers, id))
                    if not areaOK then return native end
                    selected = inArea == true
                end
            end
            if selected then
                local filtered, _, _, _, filterOK = Read(Field(tracker, "IsQuestFiltered"), id)
                if not filterOK then return native end
                if not filtered then tracked[id] = true end
            end
        end
    end
    return tracked
end

local trackingCallback
local trackingHooks = setmetatable({}, { __mode = "k" })
local observed, observedCount = {}, nil

local function TrackingChanged()
    if trackingCallback then trackingCallback() end
end

local function ObserveList(ids)
    if not trackingCallback or not CustomTracker() then return end
    local count = ArrayCount(ids)
    if not count then return end
    local changed = count ~= observedCount
    for index = 1, count do
        local id = Integer(Field(ids, index))
        if not id or id == 0 then return end
        if not observed[id] then changed = true end
    end
    if not changed then return end
    wipe(observed)
    for index = 1, count do observed[Field(ids, index)] = true end
    observedCount = count
    TrackingChanged()
end

function QuestItems.WatchTracking(callback)
    trackingCallback = callback
    local tracker = _G.EllesmereUIQuestTracker
    if not callback or not (Security and Security.CanAccessTable(tracker)) then return false end
    local hooks = trackingHooks[tracker]
    if hooks and hooks.complete then return false end
    if not hooks then hooks = {}; trackingHooks[tracker] = hooks end
    local attached = false
    local function Attach(object, key, handler)
        if not hooks[key] and type(Field(object, key)) == "function" then
            hooks[key] = Security.SafeHook("QuestItems.Tracking." .. key, object, key, handler)
            attached = attached or hooks[key]
        end
    end
    Attach(tracker, "SortQuestList", ObserveList)
    Attach(tracker, "Set", TrackingChanged)
    Attach(tracker, "RefreshCustom", TrackingChanged)
    Attach(Field(tracker, "CustomQuestActions"), "Untrack", TrackingChanged)
    Attach(_G, "_EQT_RefreshAll", TrackingChanged)
    hooks.complete = hooks.SortQuestList and hooks.Set and hooks.RefreshCustom and hooks.Untrack and hooks._EQT_RefreshAll
    return attached
end

function QuestItems.StopTracking()
    trackingCallback = nil
    wipe(observed)
    observedCount = nil
end

function QuestItems.IsCompatibilityItem(itemID)
    return COMPATIBILITY_ITEMS[Integer(itemID) or 0] == true
end

function QuestItems.GetCompatibilityCount(itemID)
    if not QuestItems.IsCompatibilityItem(itemID) then return nil end
    local item = YUI.API.Item
    return Integer(Read(item and item.GetCount, itemID, false, true, false, false))
end

local function CompatibilityItem(itemID)
    local count = QuestItems.GetCompatibilityCount(itemID)
    if not count or count == 0 then return nil, nil, count end
    local item = YUI.API.Item
    local info = Read(item and item.GetInfo, itemID)
    local link, texture = Field(info, "link"), Field(info, "texture")
    if type(link) == "string" and Integer(tonumber(link:match("item:(%d+)"))) == itemID
        and (type(texture) == "number" or type(texture) == "string") then
        return link, texture, count
    end
    return nil, nil, count
end

function QuestItems.IsInside(questID)
    local value = Read(_G.C_Minimap and _G.C_Minimap.IsInsideQuestBlob, questID)
    -- Forever 1.60.1.71037: quest 5561 reports false in Kodo Graveyard.
    -- AreaTable 596 and player map 1443 are verified; names stay localized.
    -- Only supplement a readable false, never missing/restricted native data.
    if questID == 5561 and value == false then
        local map = _G.C_Map
        if Integer(Read(map and map.GetBestMapForUnit, "player")) == 1443 then
            local area = Read(map and map.GetAreaInfo, 596)
            local subzone = Read(_G.GetSubZoneText)
            if type(area) == "string" and area ~= "" and type(subzone) == "string" and subzone == area then
                return true
            end
        end
    end
    if type(value) == "boolean" then return value end
end

-- Global read failures return nil. Individual failures preserve the last
-- confirmed items for that quest and allow other quests to refresh.
-- pending[itemID] is true for missing item data and false for an unreadable count.
function QuestItems.ReadLog(previous)
    local api = _G.C_QuestLog
    if not api then return nil end
    local count = Integer(Read(api.GetNumQuestLogEntries))
    local watches = Integer(Read(api.GetNumQuestWatches))
    if not count or not watches or count > 500 or watches > 500 then return nil end
    local tracked = {}
    for index = 1, watches do
        local questID = Integer(Read(api.GetQuestIDForQuestWatchIndex, index))
        if not questID then return nil end
        tracked[questID] = true
    end
    tracked = CustomWatches(tracked)
    local result, pending = {}, nil
    local incomplete, previousByQuest
    local function Retain(questID, index, itemID, compatibility)
        if not previous or #previous == 0 then return end
        if not previousByQuest then
            previousByQuest = {}
            for _, row in ipairs(previous) do
                local group = previousByQuest[row.questID]
                if not group then group = {}; previousByQuest[row.questID] = group end
                group[#group + 1] = row
            end
        end
        for _, row in ipairs(previousByQuest[questID] or EMPTY) do
            if not itemID or (row.itemID == itemID and (row.compatibility == true) == compatibility) then
                result[#result + 1] = { questID = questID, index = index, itemID = row.itemID,
                    link = row.link, texture = row.texture, charges = row.charges, compatibility = row.compatibility,
                    title = row.title, tracked = tracked[questID] == true, inside = QuestItems.IsInside(questID) }
                if itemID then return true end
            end
        end
    end
    for index = 1, count do
        local info = Read(api.GetInfo, index)
        local questID = Integer(Field(info, "questID"))
        if not questID and Field(info, "isHeader") ~= true then
            questID = Integer(Read(api.GetQuestIDForLogIndex, index))
            if not questID then incomplete = true end
        end
        if questID and questID > 0 then
            local link, texture, charges, showWhenComplete, readable = Read(_G.GetQuestLogSpecialItemInfo, index)
            local complete = Read(api.IsComplete, questID)
            local itemID = type(link) == "string" and Integer(tonumber(link:match("item:(%d+)"))) or nil
            if itemID == 0 then itemID = nil end
            if not readable or type(complete) ~= "boolean" or ((link ~= nil or texture ~= nil) and not itemID) then
                incomplete = true
                Retain(questID, index)
            else
                local nativeItemID
                local title = Field(info, "title")
                if itemID and (not complete or showWhenComplete == true) then
                    if texture == nil then
                        local item = YUI.API.Item
                        texture = Read(item and item.GetIcon, itemID)
                    end
                    if type(texture) == "number" or type(texture) == "string" then
                        nativeItemID = itemID
                        result[#result + 1] = { questID = questID, index = index, itemID = itemID,
                            link = link, texture = texture, charges = Integer(charges),
                            title = type(title) == "string" and title or "", tracked = tracked[questID] == true,
                            inside = QuestItems.IsInside(questID) }
                    else
                        pending = pending or {}
                        pending[itemID] = true
                        if Retain(questID, index, itemID, false) then nativeItemID = itemID end
                    end
                end
                local compatibility = COMPATIBILITY[questID]
                if not complete and compatibility then
                    for _, compatibilityID in ipairs(compatibility) do
                        if compatibilityID ~= nativeItemID then
                            local itemLink, icon, uses = CompatibilityItem(compatibilityID)
                            if itemLink then
                                result[#result + 1] = { questID = questID, index = index, itemID = compatibilityID,
                                    link = itemLink, texture = icon, charges = uses, compatibility = true,
                                    title = type(title) == "string" and title or "", tracked = tracked[questID] == true,
                                    inside = QuestItems.IsInside(questID) }
                            elseif uses ~= 0 then
                                pending = pending or {}
                                pending[compatibilityID] = pending[compatibilityID] or uses ~= nil
                                Retain(questID, index, compatibilityID, true)
                            end
                        end
                    end
                end
            end
        end
    end
    return result, pending, incomplete
end

-- Native cooldowns resolve the current quest index without allocating a table.
-- Compatibility rows use their actual item ID through the shared item adapter.
function QuestItems.GetCooldown(questID, itemID)
    if itemID ~= nil then
        if not QuestItems.IsCompatibilityItem(itemID) then return nil, nil, false end
        local item = YUI.API.Item
        local cooldown = Read(item and item.GetCooldown, itemID)
        local startAt, duration = Number(Field(cooldown, "startTime")), Number(Field(cooldown, "duration"))
        local enabled = Field(cooldown, "isEnabled")
        return startAt, duration, (enabled == true or enabled == 1) and startAt ~= nil and duration ~= nil
    end
    local index = Integer(Read(_G.C_QuestLog and _G.C_QuestLog.GetLogIndexForQuestID, questID))
    if not index or index == 0 then return nil, nil, false end
    local a, b, enabled = Read(_G.GetQuestLogSpecialItemCooldown, index)
    a, b = Number(a), Number(b)
    return a, b, (enabled == true or enabled == 1) and a ~= nil and b ~= nil
end
