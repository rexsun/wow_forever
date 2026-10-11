local _, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI then return end
YUI.API = YUI.API or {}
-- Also loaded by the toolbox product when another CoreEmbed owns the shared Core.
if YUI.API.Quest then return end
local Quest = {}
YUI.API.Quest = Quest
local Security = YUI.API.Security

-- Cold interaction reads only. Unknown/restricted data always stops automation.
local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value, second = pcall(fn, ...)
    if not ok then return nil end
    if Security and Security.IsSecretValue then
        if Security.IsSecretValue(value) or Security.IsSecretValue(second) then return nil end
    end
    return value, second
end

local function Number(value)
    if Security and Security.IsSecretValue and Security.IsSecretValue(value) then return nil end
    if type(value) ~= "number" or value < 0 or value > 9007199254740991 or value ~= math.floor(value) then return nil end
    return value
end

local function Field(record, key)
    if type(record) ~= "table" then return nil, false end
    if Security and Security.CanAccessTable and not Security.CanAccessTable(record) then return nil, false end
    local ok, value = pcall(function() return record[key] end)
    if not ok or (Security and Security.IsSecretValue and Security.IsSecretValue(value)) then return nil, false end
    return value, true
end

function Quest.CanAct()
    if type(_G.InCombatLockdown) == "function" and Read(_G.InCombatLockdown) ~= false then return false end
    return true
end

local function Call(fn, ...)
    if not Quest.CanAct() or type(fn) ~= "function" then return false end
    if Security and Security.SafeCall then return Security.SafeCall("Quest.Automation", fn, ...) end
    return pcall(fn, ...)
end

function Quest.GetID() return Number(Read(_G.GetQuestID)) end
function Quest.GetNPCGUID()
    local value = Read(_G.UnitGUID, "npc")
    return type(value) == "string" and value or nil
end

-- Gossip uses quest IDs; QUEST_GREETING uses page-local indices on all four clients.
function Quest.GetList(greeting, active)
    local result = {}
    if greeting then
        local count = Number(Read(active and _G.GetNumActiveQuests or _G.GetNumAvailableQuests))
        if not count or count > 64 then return nil end
        for index = 1, count do
            local title, complete = Read(active and _G.GetActiveTitle or _G.GetAvailableTitle, index)
            if type(title) ~= "string" then return nil end
            if active and type(complete) ~= "boolean" and complete ~= 0 and complete ~= 1 then return nil end
            result[index] = { id = index, complete = complete == true or complete == 1 }
        end
    else
        local api = _G.C_GossipInfo
        local list = api and Read(active and api.GetActiveQuests or api.GetAvailableQuests)
        if type(list) ~= "table" then return nil end
        if Security and Security.CanAccessTable and not Security.CanAccessTable(list) then return nil end
        if #list > 64 then return nil end
        for index, record in ipairs(list) do
            local id = Number(Field(record, "questID"))
            local complete, readable = Field(record, "isComplete")
            if not id or id == 0 or not readable or (active and complete ~= nil and type(complete) ~= "boolean") then return nil end
            result[index] = { id = id, complete = complete == true }
        end
    end
    return result
end

function Quest.Select(greeting, active, id)
    if not Number(id) or id == 0 then return false end
    if greeting then return Call(active and _G.SelectActiveQuest or _G.SelectAvailableQuest, id) end
    local api = _G.C_GossipInfo
    return api and Call(active and api.SelectActiveQuest or api.SelectAvailableQuest, id) or false
end

function Quest.Accept()
    -- Preserve native PvP confirmation and already-accepted quest acknowledgement.
    if Read(_G.QuestFlagsPVP) ~= false then return false end
    local auto
    if YUI.IsMists or YUI.IsWrath then
        -- Match the Classic native accept button's acknowledgement flag.
        local readable
        auto, readable = Field(_G.QuestFrame, "autoQuest")
        if not readable then return false end
        if auto == nil then auto = false end
    else
        auto = Read(_G.QuestGetAutoAccept)
    end
    if auto == true then return Call(_G.AcknowledgeAutoAcceptQuest) end
    if auto ~= false then return false end
    return Call(_G.AcceptQuest)
end

local function HasNoExtraCost()
    local money = Number(Read(_G.GetQuestMoneyToGet))
    -- The Classic quest progress UI has no required-currency API.
    local currencies = 0
    if type(_G.GetNumQuestCurrencies) == "function" then
        currencies = Number(Read(_G.GetNumQuestCurrencies))
    elseif not (YUI.IsMists or YUI.IsWrath) then
        return false
    end
    return money == 0 and currencies == 0
end

function Quest.Progress()
    if not HasNoExtraCost() or Read(_G.IsQuestCompletable) ~= true then return false end
    return Call(_G.CompleteQuest)
end

function Quest.Reward()
    if not HasNoExtraCost() then return false end
    local choices = Number(Read(_G.GetNumQuestChoices))
    if choices == nil or choices > 1 then return false end
    return Call(_G.GetQuestReward, choices)
end
