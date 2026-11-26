-- You Don't Need This
-- Learns which bag items belong to which quests, then tells you when
-- every quest an item is used for has been completed.
-- Copyright (C) 2026 Nick. Licensed under the GNU GPL v3 or later; see LICENSE.md.

local ADDON, ns = ...
local PREFIX = "|cffff6060You Don't Need This|r: "

------------------------------------------------------------------------
-- API compatibility (WoW Forever has a retail-style UI on a classic base,
-- so check for both the C_ namespaced and the old global functions)
------------------------------------------------------------------------
local function IsQuestDone(questID)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(questID)
    elseif IsQuestFlaggedCompleted then
        return IsQuestFlaggedCompleted(questID)
    end
    return false
end

local function IsOnQuest(qid)
    if C_QuestLog and C_QuestLog.IsOnQuest then return C_QuestLog.IsOnQuest(qid) end
    if GetQuestLogIndexByID then return (GetQuestLogIndexByID(qid) or 0) > 0 end
end

local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local GetSlotItemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local NUM_BAGS = NUM_BAG_SLOTS or 4

local function ForEachItemIn(bags, fn)
    for _, bag in ipairs(bags) do
        for slot = 1, (GetNumSlots(bag) or 0) do
            local itemID = GetSlotItemID(bag, slot)
            if itemID then fn(itemID, bag, slot) end
        end
    end
end

local BAGS = {}
for bag = 0, NUM_BAGS do BAGS[#BAGS + 1] = bag end

-- Bank: the main bank (-1) plus the bank bags. Forever has a reagent bag (bag 5), so its bank bags
-- start at Enum.BagIndex.BankBag_1 (6); on clients without one they start right after the bags.
-- Bags that don't exist report 0 slots, so a slot count that's too high does no harm.
local BANK_BAGS = { BANK_CONTAINER or -1 }
do
    local BI = type(Enum) == "table" and type(Enum.BagIndex) == "table" and Enum.BagIndex or nil
    local first = (BI and BI.BankBag_1) or (((BI and BI.ReagentBag) or NUM_BAGS) + 1)
    for i = 0, (tonumber(NUM_BANKBAGSLOTS) or 7) - 1 do BANK_BAGS[#BANK_BAGS + 1] = first + i end
end

local function ForEachBagItem(fn) ForEachItemIn(BAGS, fn) end
-- Only valid while the bank is open.
local function ForEachBankItem(fn) ForEachItemIn(BANK_BAGS, fn) end

-- Pull the item name out of objective text.
-- Handles both "Linen Cloth: 3/10" (classic) and "3/10 Linen Cloth" (retail).
local function ParseObjectiveItemName(text)
    if not text then return nil end
    return text:match("^(.-):%s*%d+%s*/%s*%d+") or text:match("^%d+%s*/%s*%d+%s+(.+)$")
end

-- Returns { { questID=, title=, itemNames={...} }, ... } for the current quest log.
local function ReadQuestLog()
    local quests = {}

    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                local names = {}
                for _, obj in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                    if obj.type == "item" then
                        local n = ParseObjectiveItemName(obj.text)
                        if n then names[#names + 1] = n end
                    end
                end
                quests[#quests + 1] = { questID = info.questID, title = info.title, itemNames = names }
            end
        end
    elseif GetNumQuestLogEntries then
        for i = 1, GetNumQuestLogEntries() do
            local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
            if not isHeader and questID then
                local names = {}
                for j = 1, (GetNumQuestLeaderBoards(i) or 0) do
                    local text, objType = GetQuestLogLeaderBoard(j, i)
                    if objType == "item" then
                        local n = ParseObjectiveItemName(text)
                        if n then names[#names + 1] = n end
                    end
                end
                quests[#quests + 1] = { questID = questID, title = title, itemNames = names }
            end
        end
    end

    return quests
end

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------
local function DB()
    YDNT_DB = YDNT_DB or {}
    YDNT_DB.learned = YDNT_DB.learned or {}   -- [itemID] = { [questID] = questTitle }
    YDNT_DB.titles  = YDNT_DB.titles  or {}   -- [questID] = questTitle
    YDNT_DB.bank    = YDNT_DB.bank    or {}   -- [itemID] = true, the bank as last seen
    YDNT_DB.abandoned = YDNT_DB.abandoned or {} -- [questID] = true, quests this character abandoned
    YDNT_DB.settings = YDNT_DB.settings or {}
    local s = YDNT_DB.settings
    if s.marks == nil then s.marks = true end
    if s.alerts == nil then s.alerts = true end
    if s.questRange == nil then s.questRange = "grey" end -- Quests.lua: "grey" | "green" | "levels"
    if s.questLevels == nil then s.questLevels = 5 end
    if s.questNudge == nil then s.questNudge = true end -- chat line at login / level-up
    if s.questNudgeOnlyMore == nil then s.questNudgeOnlyMore = false end -- login: only if the count went up
    s.minimap = s.minimap or {}                           -- Minimap.lua: { hide = bool, angle = degrees }
    return YDNT_DB
end

-- Account-wide: the player's own verdicts, which hold for every character.
local function Global()
    YDNT_Global = YDNT_Global or {}
    YDNT_Global.overrides = YDNT_Global.overrides or {} -- [itemID] = "ignore" | "keep"
    return YDNT_Global
end

-- Match active quest objectives to items currently in your bags, and remember the link.
local function Learn()
    local db = DB()
    local nameToID = {}
    ForEachBagItem(function(itemID)
        local name = GetItemInfoCompat(itemID)
        if name then nameToID[name] = itemID end
    end)

    for _, q in ipairs(ReadQuestLog()) do
        if q.title then db.titles[q.questID] = q.title end
        for _, itemName in ipairs(q.itemNames) do
            local itemID = nameToID[itemName]
            if itemID then
                db.learned[itemID] = db.learned[itemID] or {}
                db.learned[itemID][q.questID] = q.title or true
            end
        end
    end
end

local bankOpen = false
local function ScanBank()
    local bank = {}
    ForEachBankItem(function(itemID) bank[itemID] = true end)
    DB().bank = bank
end

local function Seed()
    local s = ns.SeedData or {}
    return s.items or {}, s.quests or {}, s.raceMask or {}, s.hidden or {}
end

-- Bit test by arithmetic: Forever race masks use bits above 32, out of reach of bit.band.
local function HasFlag(mask, flag)
    if not mask or mask == 0 or not flag then return true end
    return mask % (2 * flag) >= flag
end

local playerRaceFlag, playerClassFlag
-- Seed quests for another race/class (e.g. the other faction) can never be completed by this
-- character, so they must not keep an item "needed".
local function QuestAppliesToPlayer(qid)
    local _, quests, raceMask = Seed()
    local q = quests[qid]
    if not q then return true end
    if playerRaceFlag == nil then
        playerRaceFlag = raceMask[select(3, UnitRace("player"))] or false
        local classID = select(3, UnitClass("player"))
        playerClassFlag = classID and 2 ^ (classID - 1) or false
    end
    -- Unknown player flag -> assume the quest applies (keeps the item "needed", the safe side).
    return HasFlag(q[2], playerRaceFlag or nil) and HasFlag(q[3], playerClassFlag or nil)
end

-- Quests Questie hides as unobtainable (removed content and the like). A quest this character has
-- had in its quest log is obviously obtainable, so that always wins.
local function IsUnavailable(qid)
    local hidden = select(4, Seed())
    return hidden[qid] and not DB().titles[qid] and not IsOnQuest(qid)
end

-- Quests this character abandoned (from the quest log or the low-level window) won't be completed,
-- so they stop keeping items needed. Picking the quest up again makes it count again.
local function IsAbandoned(qid)
    return DB().abandoned[qid] and not IsOnQuest(qid)
end

-- Record abandons: remember which quest SetAbandonQuest was called for, commit on AbandonQuest.
-- Hooks work whoever calls them (Blizzard's quest log, Quests.lua, other addons).
do
    local pendingAbandon
    local function Commit()
        if pendingAbandon then DB().abandoned[pendingAbandon] = true end
        pendingAbandon = nil
    end
    if C_QuestLog and C_QuestLog.SetAbandonQuest and C_QuestLog.AbandonQuest and C_QuestLog.GetSelectedQuest then
        hooksecurefunc(C_QuestLog, "SetAbandonQuest", function()
            pendingAbandon = C_QuestLog.GetSelectedQuest()
        end)
        hooksecurefunc(C_QuestLog, "AbandonQuest", Commit)
    end
    if SetAbandonQuest and AbandonQuest and GetQuestLogSelection and GetQuestLogTitle then
        hooksecurefunc("SetAbandonQuest", function()
            local index = GetQuestLogSelection()
            pendingAbandon = index and index > 0 and select(8, GetQuestLogTitle(index)) or nil
        end)
        hooksecurefunc("AbandonQuest", Commit)
    end
end

-- All quests we know an item is used for: { [questID] = true }
local function QuestsForItem(itemID)
    local result, any = {}, false
    for _, qid in ipairs(Seed()[itemID] or {}) do
        if QuestAppliesToPlayer(qid) then result[qid] = true; any = true end
    end
    for qid in pairs(DB().learned[itemID] or {}) do result[qid] = true; any = true end
    return any and result or nil
end

-- Only items that exist purely for quests can be "not needed". Trade goods such as Light Leather or
-- Linen Cloth are used by quests too, but also for crafting, selling, etc., so they're never flagged.
-- Quest-only = item class "Quest", or bound as "Quest Item" (bind type 4).
local GetItemInfoInstantCompat = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local QUEST_ITEM_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or LE_ITEM_CLASS_QUESTITEM or 12
local BIND_QUEST = 4

local function IsQuestOnlyItem(itemID)
    if GetItemInfoInstantCompat and select(6, GetItemInfoInstantCompat(itemID)) == QUEST_ITEM_CLASS then
        return true
    end
    return select(14, GetItemInfoCompat(itemID)) == BIND_QUEST
end

-- Returns nil if we know nothing about the item,
-- otherwise notNeeded (bool), openQuestIDs (list), and a reason:
--   "ignored" / "kept" - the player's own verdict (/ydnt ignore, /ydnt keep)
--   "shared"           - every quest is done, but the item has uses outside quests (stays unflagged)
local function ItemStatus(itemID)
    local override = Global().overrides[itemID]
    if override == "keep" then return false, {}, "kept" end
    if override == "ignore" then return true, {}, "ignored" end

    local quests = QuestsForItem(itemID)
    if not quests then return nil end
    local open = {}
    for qid in pairs(quests) do
        if not IsQuestDone(qid) and not IsUnavailable(qid) and not IsAbandoned(qid) then open[#open + 1] = qid end
    end
    if #open == 0 and not IsQuestOnlyItem(itemID) then return false, open, "shared" end
    return #open == 0, open
end

local function QuestName(qid)
    local _, quests = Seed()
    local seeded = quests[qid] and quests[qid][1]
    return DB().titles[qid] or (seeded ~= "" and seeded) or ("quest " .. qid)
end

local function ItemIDFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- An item ID, or an item link shift-clicked into the chat box.
local function ItemIDFromArg(arg)
    return tonumber(arg) or ItemIDFromLink(arg)
end

local function ItemLabel(itemID)
    local _, link = GetItemInfoCompat(itemID)
    return link or ("item " .. itemID)
end

------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------
local function DecorateTooltip(tooltip, itemID)
    local notNeeded, open, reason = ItemStatus(itemID)
    if notNeeded == nil then return end
    if reason == "ignored" then
        tooltip:AddLine("|cffff5959YDNT:|r |cffd8d8d8marked as not needed by you|r", 1, 1, 1, true)
    elseif reason == "kept" then
        tooltip:AddLine("|cffff5959YDNT:|r |cffd8d8d8kept by you|r", 1, 1, 1, true)
    elseif notNeeded then
        -- "YDNT: <the completed quest(s) the item was for>". Quest chains often reuse one name,
        -- so list each name once.
        local names, seen = {}, {}
        for qid in pairs(QuestsForItem(itemID)) do
            local name = QuestName(qid)
            if IsQuestDone(qid) then -- nothing to add
            elseif IsAbandoned(qid) then name = name .. " (abandoned)"
            else name = name .. " (unavailable)" end
            if not seen[name] then seen[name] = true; names[#names + 1] = name end
        end
        table.sort(names)
        tooltip:AddLine("|cffff5959YDNT:|r |cffd8d8d8" .. table.concat(names, ", ") .. "|r", 1, 1, 1, true)
    else
        for _, qid in ipairs(open) do
            tooltip:AddLine("Still needed: " .. QuestName(qid), 0.4, 1, 0.4)
        end
    end
    tooltip:Show()
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if data and data.id then DecorateTooltip(tooltip, data.id) end
    end)
else
    local function hook(tooltip)
        tooltip:HookScript("OnTooltipSetItem", function(self)
            local _, link = self:GetItem()
            local id = ItemIDFromLink(link)
            if id then DecorateTooltip(self, id) end
        end)
    end
    hook(GameTooltip)
    if ItemRefTooltip then hook(ItemRefTooltip) end
end

------------------------------------------------------------------------
-- Overrides: the player's own "I don't need this" / "keep this"
------------------------------------------------------------------------
-- value: "ignore", "keep" or nil (back to automatic)
local function SetOverride(itemID, value)
    Global().overrides[itemID] = value
    if ns.Refresh then ns.Refresh(false, true) end
    if ns.OnOverridesChanged then ns.OnOverridesChanged() end
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
local function ListJunk()
    local seen, count = {}, 0
    ForEachBagItem(function(itemID)
        if seen[itemID] then return end
        seen[itemID] = true
        if ItemStatus(itemID) == true then
            print(PREFIX .. ItemLabel(itemID))
            count = count + 1
        end
    end)
    for itemID in pairs(DB().bank) do
        if not seen[itemID] and ItemStatus(itemID) == true then
            seen[itemID] = true
            print(PREFIX .. ItemLabel(itemID) .. " |cffaaaaaa(in your bank)|r")
            count = count + 1
        end
    end
    if count == 0 then print(PREFIX .. "nothing to throw away.") end
end

-- /ydnt why <item link or ID>: print every link the addon knows for an item and how it judged each.
local function Why(arg)
    local itemID = ItemIDFromArg(arg)
    if not itemID then print(PREFIX .. "usage: /ydnt why <shift-click an item, or an item ID>") return end
    local name = GetItemInfoCompat(itemID)
    print(PREFIX .. ("item %d (%s)"):format(itemID, tostring(name)))

    local items, quests = Seed()
    local any = false
    for _, qid in ipairs(items[itemID] or {}) do
        any = true
        local q = quests[qid]
        print(("  seed: %s [%d] races=%s classes=%s applies=%s done=%s inLog=%s unavailable=%s"):format(
            QuestName(qid), qid, tostring(q and q[2]), tostring(q and q[3]),
            tostring(QuestAppliesToPlayer(qid)), tostring(IsQuestDone(qid)), tostring(IsOnQuest(qid)),
            tostring(not not IsUnavailable(qid))) .. " abandoned=" .. tostring(not not IsAbandoned(qid)))
    end
    for qid in pairs(DB().learned[itemID] or {}) do
        any = true
        print(("  learned: %s [%d] done=%s inLog=%s abandoned=%s"):format(
            QuestName(qid), qid, tostring(IsQuestDone(qid)), tostring(IsOnQuest(qid)),
            tostring(not not IsAbandoned(qid))))
    end
    if not any then print("  no quest links known for this item") end

    local notNeeded, _, reason = ItemStatus(itemID)
    print(("  verdict: %s"):format(
        reason == "ignored" and "you marked it as not needed (/ydnt clear to undo)"
        or reason == "kept" and "you marked it to keep (/ydnt clear to undo)"
        or notNeeded == nil and "unknown item"
        or notNeeded and "you don't need this"
        or reason == "shared" and "quests done, but not a quest-only item (used for other things), so never flagged"
        or "still needed"))
    print(("  race=%s raceFlag=%s tooltipHook=%s questAPI=%s"):format(
        tostring(select(3, UnitRace("player"))), tostring(playerRaceFlag),
        (TooltipDataProcessor and "TooltipDataProcessor" or "OnTooltipSetItem"),
        (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) and "C_QuestLog" or (IsQuestFlaggedCompleted and "global" or "none")))
end

local function OverrideCommand(cmd, arg)
    local itemID = ItemIDFromArg(arg)
    if not itemID then
        print(PREFIX .. ("usage: /ydnt %s <shift-click an item, or an item ID>"):format(cmd))
        return
    end
    if cmd == "ignore" then
        SetOverride(itemID, "ignore")
        print(PREFIX .. ItemLabel(itemID) .. " is now marked as not needed, on all your characters.")
    elseif cmd == "keep" then
        SetOverride(itemID, "keep")
        print(PREFIX .. ItemLabel(itemID) .. " will never be marked, on all your characters.")
    else
        SetOverride(itemID, nil)
        print(PREFIX .. ItemLabel(itemID) .. " is back to automatic.")
    end
end

local HELP = {
    "/ydnt list - items you don't need (bags and bank)",
    "/ydnt why <item> - which quests an item is linked to, and the verdict",
    "/ydnt ignore <item> - mark an item as not needed (e.g. its quest can't be done anymore)",
    "/ydnt keep <item> - never mark this item",
    "/ydnt clear <item> - undo ignore/keep",
    "/ydnt quests - grey/green quests in your log, with an Abandon button for each",
    "/ydnt options - open the settings",
    "/ydnt marks | alerts | minimap - toggle bag marks, alerts or the minimap button",
    "/ydnt scan | reset - rescan now, or clear learned data for this character",
}

SLASH_YOUDONTNEEDTHIS1 = "/ydnt"
SlashCmdList.YOUDONTNEEDTHIS = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "why" then
        Why(rest)
    elseif cmd == "" or cmd == "list" then
        ListJunk()
    elseif cmd == "ignore" or cmd == "keep" or cmd == "clear" then
        OverrideCommand(cmd, rest)
    elseif cmd == "quests" or cmd == "q" then
        if ns.ToggleQuests then ns.ToggleQuests() end
    elseif cmd == "minimap" then
        local m = DB().settings.minimap
        m.hide = not m.hide
        if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
        print(PREFIX .. "minimap button " .. (m.hide and "hidden." or "shown."))
        if ns.OnOverridesChanged then ns.OnOverridesChanged() end
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        if ns.OpenOptions then ns.OpenOptions() end
    elseif cmd == "scan" then
        Learn()
        if bankOpen then ScanBank() end
        if ns.Refresh then ns.Refresh(false, true) end
        print(PREFIX .. "rescanned your quest log and bags.")
    elseif cmd == "reset" then
        local settings = DB().settings
        YDNT_DB = nil
        DB().settings = settings
        print(PREFIX .. "learned data cleared for this character.")
    elseif cmd == "export" and ns.ExportSeed then -- developer build only (Export.lua)
        ns.ExportSeed(function(text) print(PREFIX .. text) end)
    elseif cmd == "marks" or cmd == "alerts" then
        local s = DB().settings
        s[cmd] = not s[cmd]
        print(PREFIX .. (cmd == "marks" and "red bag marks " or "alerts ") .. (s[cmd] and "on." or "off."))
        if ns.Refresh then ns.Refresh(false, true) end
        if ns.OnOverridesChanged then ns.OnOverridesChanged() end
    else
        print(PREFIX .. "commands:")
        for _, line in ipairs(HELP) do print("  " .. line) end
    end
end

------------------------------------------------------------------------
-- Events (throttled, since QUEST_LOG_UPDATE and BAG_UPDATE fire a lot)
------------------------------------------------------------------------
local pending = false
local function ScheduleLearn()
    if pending then return end
    pending = true
    C_Timer.After(1, function()
        pending = false
        Learn()
        if bankOpen then ScanBank() end
        if ns.Refresh then ns.Refresh(true) end -- Bags.lua: bag marks + alerts
    end)
end

-- Shared with the other files
ns.PREFIX = PREFIX
ns.DB = DB
ns.Global = Global
ns.ItemStatus = ItemStatus
ns.ForEachBagItem = ForEachBagItem
ns.SetOverride = SetOverride
ns.ListJunk = ListJunk
ns.ItemLabel = ItemLabel
ns.ItemIDFromLink = ItemIDFromLink
ns.HELP = HELP
ns.IsBankOpen = function() return bankOpen end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("QUEST_LOG_UPDATE")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("BANKFRAME_OPENED")
f:RegisterEvent("BANKFRAME_CLOSED")
f:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        DB(); Global()
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
        return
    end
    ScheduleLearn()
end)
