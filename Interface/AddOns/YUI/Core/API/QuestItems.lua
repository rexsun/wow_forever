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
-- Cold, event-coalesced reads. Missing/restricted data returns nil, never an
-- inferred map/area result. ReadLog allocates one bounded quest-log snapshot.
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
