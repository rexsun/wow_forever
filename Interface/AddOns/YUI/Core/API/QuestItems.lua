local YUI = _G.YUI
if not YUI or not YUI.IsForever then return end
YUI.API = YUI.API or {}
if YUI.API.QuestItems then return end
local QuestItems = {}
YUI.API.QuestItems = QuestItems
local Security = YUI.API.Security

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

function QuestItems.IsInside(questID)
    local value = Read(_G.C_Minimap and _G.C_Minimap.IsInsideQuestBlob, questID)
    if type(value) == "boolean" then return value end
end

function QuestItems.ReadLog()
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
    local result = {}
    for index = 1, count do
        local info = Read(api.GetInfo, index)
        if not (Security and Security.CanAccessTable(info)) then return nil end
        local questID = Integer(Field(info, "questID"))
        if questID and questID > 0 then
            local link, texture, charges, showWhenComplete, readable = Read(_G.GetQuestLogSpecialItemInfo, index)
            local complete = Read(api.IsComplete, questID)
            if not readable or type(complete) ~= "boolean" then return nil end
            if type(link) == "string" and (type(texture) == "number" or type(texture) == "string") then
                local itemID = Integer(tonumber(link:match("item:(%d+)")))
                if itemID and itemID > 0 and (complete == false or (complete == true and showWhenComplete == true)) then
                    local title = Field(info, "title")
                    result[#result + 1] = { questID = questID, index = index, itemID = itemID,
                        link = link, texture = texture, charges = Integer(charges),
                        title = type(title) == "string" and title or "", tracked = tracked[questID] == true,
                        inside = QuestItems.IsInside(questID) }
                end
            end
        end
    end
    return result
end

-- No table allocation on the cooldown event path. Index is resolved from the
-- bound quest ID each time: unrelated log edits must never cool down another item.
function QuestItems.GetCooldown(questID)
    local index = Integer(Read(_G.C_QuestLog and _G.C_QuestLog.GetLogIndexForQuestID, questID))
    if not index or index == 0 then return nil, nil, false end
    local a, b, enabled = Read(_G.GetQuestLogSpecialItemCooldown, index)
    a, b = Number(a), Number(b)
    return a, b, (enabled == true or enabled == 1) and a ~= nil and b ~= nil
end
