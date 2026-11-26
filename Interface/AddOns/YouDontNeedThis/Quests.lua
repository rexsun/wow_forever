-- You Don't Need This - low-level quest cleanup window
-- Copyright (C) 2026 Nick. Licensed under the GNU GPL v3 or later; see LICENSE.md.
--
-- Lists the grey (and optionally green) quests in your quest log, each with an Abandon button,
-- so you can clear out quests you've outlevelled. Every abandon asks for confirmation first.
-- Open with /ydnt quests, the button on the quest log, the settings panel, or right-click
-- the addon compartment entry.

local _, ns = ...

local ROW_HEIGHT = 24
local MAX_LEVEL_GAP = 60

local function Settings() return ns.DB().settings end

------------------------------------------------------------------------
-- Quest log (feature-detected: C_QuestLog first, then the classic globals)
------------------------------------------------------------------------
-- How many levels below you a quest stays green. Retail: UnitQuestTrivialLevelRange;
-- classic: GetQuestGreenRange. Both are what the quest log uses for its colours.
local function GreenRange()
    if UnitQuestTrivialLevelRange then
        local r = UnitQuestTrivialLevelRange("player")
        if r then return r end
    end
    if GetQuestGreenRange then
        local r = GetQuestGreenRange()
        if r then return r end
    end
    return 8
end

-- "grey", "green" or nil (yellow and up), the same thresholds as GetQuestDifficultyColor.
local function Difficulty(level, playerLevel)
    local below = playerLevel - level
    if below > GreenRange() then return "grey" end
    if below >= 3 then return "green" end
end

local function IsComplete(qid, flag)
    if C_QuestLog and C_QuestLog.IsComplete then return C_QuestLog.IsComplete(qid) end
    return flag == 1 or flag == true
end

-- Returns a list of { questID, title, level, complete, difficulty } and whether any header is
-- collapsed (classic hides the quests under a collapsed header from the API).
local function ReadLog()
    local list, collapsed = {}, false
    local playerLevel = UnitLevel("player") or 1

    local function add(qid, title, level, completeFlag)
        if not qid or qid == 0 or not level or level <= 0 then return end
        list[#list + 1] = {
            questID = qid, title = title or ("quest " .. qid), level = level,
            complete = IsComplete(qid, completeFlag),
            difficulty = Difficulty(level, playerLevel),
        }
    end

    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info then
                if info.isHeader then
                    if info.isCollapsed then collapsed = true end
                elseif not info.isHidden and not info.isTask and not info.isBounty then
                    add(info.questID, info.title, info.level, info.isComplete)
                end
            end
        end
    elseif GetNumQuestLogEntries then
        for i = 1, GetNumQuestLogEntries() do
            local title, level, _, isHeader, isCollapsed, isComplete, _, questID = GetQuestLogTitle(i)
            if isHeader then
                if isCollapsed then collapsed = true end
            else
                add(questID, title, level, isComplete)
            end
        end
    end
    return list, collapsed
end

local function Matches(q, playerLevel)
    local s = Settings()
    if s.questRange == "levels" then return playerLevel - q.level >= s.questLevels end
    local difficulty = Difficulty(q.level, playerLevel)
    if s.questRange == "green" then return difficulty ~= nil end
    return difficulty == "grey"
end

-- playerLevel defaults to the current level; the level-up nudge also asks about the level before.
local function LowQuests(playerLevel)
    playerLevel = playerLevel or UnitLevel("player") or 1
    local all, collapsed = ReadLog()
    local result = {}
    for _, q in ipairs(all) do
        if Matches(q, playerLevel) then result[#result + 1] = q end
    end
    table.sort(result, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.title < b.title
    end)
    return result, collapsed
end

local function LogIndex(qid)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local i = C_QuestLog.GetLogIndexForQuestID(qid)
        if i then return i end
    end
    if GetQuestLogIndexByID then
        local i = GetQuestLogIndexByID(qid)
        if i and i > 0 then return i end
    end
end

-- Abandon one quest by ID. Returns true if the request was sent.
local function Abandon(qid)
    if C_QuestLog and C_QuestLog.SetSelectedQuest and C_QuestLog.SetAbandonQuest and C_QuestLog.AbandonQuest then
        C_QuestLog.SetSelectedQuest(qid)
        C_QuestLog.SetAbandonQuest()
        C_QuestLog.AbandonQuest()
        return true
    end
    local index = LogIndex(qid)
    if index and SelectQuestLogEntry and SetAbandonQuest and AbandonQuest then
        SelectQuestLogEntry(index)
        SetAbandonQuest()
        AbandonQuest()
        return true
    end
    return false
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local function TryTemplate(kind, parent, ...)
    for _, template in ipairs({ ... }) do
        local ok, frame = pcall(CreateFrame, kind, "YouDontNeedThisQuestsFrame", parent, template)
        if ok and frame then return frame, template end
    end
    return CreateFrame(kind, "YouDontNeedThisQuestsFrame", parent)
end

local win, template = TryTemplate("Frame", UIParent, "BasicFrameTemplateWithInset", "BackdropTemplate")
win:SetSize(420, 440)
win:SetPoint("CENTER")
win:SetFrameStrata("HIGH")
win:SetToplevel(true)
win:SetClampedToScreen(true)
win:SetMovable(true)
win:EnableMouse(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
win:Hide()
tinsert(UISpecialFrames, win:GetName()) -- Esc closes it

if template ~= "BasicFrameTemplateWithInset" then
    if win.SetBackdrop then
        win:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
end

local titleText = win.TitleText or win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
if not win.TitleText then titleText:SetPoint("TOP", 0, -8) end
titleText:SetText("Low-level quests")

local hint = win:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
hint:SetPoint("TOPLEFT", 14, -32)
hint:SetPoint("RIGHT", win, "RIGHT", -14, 0)
hint:SetJustifyH("LEFT")
hint:SetText("Quests you've outlevelled. Abandon the ones you won't do.")

-- Range: Grey | Grey + green | N+ levels below
local modeButtons = {}
local function ModeButton(mode, label, width, anchor, x)
    local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    if anchor then b:SetPoint("LEFT", anchor, "RIGHT", x or 4, 0) else b:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8) end
    b:SetText(label)
    b.mode = mode
    b:SetScript("OnClick", function()
        Settings().questRange = mode
        win:Refresh()
    end)
    modeButtons[#modeButtons + 1] = b
    return b
end

local greyButton = ModeButton("grey", "Grey", 60)
local greenButton = ModeButton("green", "Grey + green", 100, greyButton)
local levelsButton = ModeButton("levels", "", 110, greenButton)

local minus = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
minus:SetSize(24, 22)
minus:SetPoint("LEFT", levelsButton, "RIGHT", 4, 0)
minus:SetText("-")
local plus = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
plus:SetSize(24, 22)
plus:SetPoint("LEFT", minus, "RIGHT", 2, 0)
plus:SetText("+")
local function Step(delta)
    local s = Settings()
    s.questLevels = math.max(1, math.min(MAX_LEVEL_GAP, (s.questLevels or 5) + delta))
    s.questRange = "levels"
    win:Refresh()
end
minus:SetScript("OnClick", function() Step(IsShiftKeyDown() and -5 or -1) end)
plus:SetScript("OnClick", function() Step(IsShiftKeyDown() and 5 or 1) end)

local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", greyButton, "BOTTOMLEFT", 0, -10)
scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -34, 64)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(1, 1)
scroll:SetScrollChild(content)

local empty = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
empty:SetPoint("TOPLEFT", 4, -4)
empty:SetText("No quests in this range.")

local status = win:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
status:SetPoint("BOTTOMLEFT", 16, 42)
status:SetPoint("RIGHT", win, "RIGHT", -16, 0)
status:SetJustifyH("LEFT")

local abandonAll = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
abandonAll:SetSize(160, 24)
abandonAll:SetPoint("BOTTOMRIGHT", -14, 12)
abandonAll:SetText("Abandon all listed")

local rows = {}
local shown = {}

-- "Abandon all" leaves quests that are ready to turn in alone: they still pay out XP and rewards.
-- (Their own row's Abandon button still works.)
local function Abandonable()
    local list, ready = {}, 0
    for _, q in ipairs(shown) do
        if q.complete then ready = ready + 1 else list[#list + 1] = q end
    end
    return list, ready
end

local function Row(i)
    if rows[i] then return rows[i] end
    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
    row:EnableMouse(true)

    row.abandon = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.abandon:SetSize(72, 20)
    row.abandon:SetPoint("RIGHT", 0, 0)
    row.abandon:SetText("Abandon")
    row.abandon:SetScript("OnClick", function()
        if not row.questID then return end
        StaticPopup_Show("YDNT_ABANDON_ONE", row.questTitle or "this quest", nil,
            { questID = row.questID, title = row.questTitle, row = row })
    end)

    row.level = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.level:SetPoint("LEFT", 4, 0)
    row.level:SetWidth(30)
    row.level:SetJustifyH("LEFT")

    row.tag = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.tag:SetPoint("RIGHT", row.abandon, "LEFT", -6, 0)

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.level, "RIGHT", 4, 0)
    row.name:SetPoint("RIGHT", row.tag, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        if not self.questID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetHyperlink and GetQuestLink and GetQuestLink(self.questID) then
            GameTooltip:SetHyperlink(GetQuestLink(self.questID))
        else
            GameTooltip:AddLine(self.questTitle)
            GameTooltip:AddLine("Level " .. tostring(self.questLevel), 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    rows[i] = row
    return row
end

local function Color(level)
    if GetQuestDifficultyColor then
        local c = GetQuestDifficultyColor(level)
        if c then return c.r, c.g, c.b end
    end
    return 1, 1, 1
end

function win:Refresh()
    local s = Settings()
    for _, b in ipairs(modeButtons) do
        if b.mode == s.questRange then b:LockHighlight() else b:UnlockHighlight() end
    end
    levelsButton:SetText(("%d+ levels below"):format(s.questLevels))

    local quests, collapsed = LowQuests()
    wipe(shown)
    for i, q in ipairs(quests) do
        shown[i] = q
        local row = Row(i)
        row.questID, row.questTitle, row.questLevel = q.questID, q.title, q.level
        row.level:SetText("[" .. q.level .. "]")
        row.level:SetTextColor(Color(q.level))
        row.name:SetText(q.title)
        row.name:SetTextColor(Color(q.level))
        row.tag:SetText(q.complete and "|cff66ff66Ready|r" or "")
        row.abandon:Enable()
        row:Show()
    end
    for i = #quests + 1, #rows do rows[i]:Hide() end
    empty:SetShown(#quests == 0)
    content:SetSize(math.max(1, scroll:GetWidth()), math.max(1, #quests * ROW_HEIGHT))

    local text = ("%d quest%s listed."):format(#quests, #quests == 1 and "" or "s")
    if collapsed then text = text .. " |cffffd100Expand collapsed quest log sections to include them.|r" end
    status:SetText(text)
    abandonAll:SetEnabled(#(Abandonable()) > 0)
    Settings().lastLowCount = #quests -- for the login nudge
end

StaticPopupDialogs["YDNT_ABANDON_ONE"] = {
    text = "Are you sure you want to abandon \"%s\"?",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, data)
        if data and Abandon(data.questID) then
            print(ns.PREFIX .. "abandoned " .. (data.title or "quest") .. ".")
            -- The row may show another quest by now if the list refreshed meanwhile.
            if data.row and data.row.questID == data.questID then data.row.abandon:Disable() end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["YDNT_ABANDON_ALL"] = {
    text = "%s",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, data)
        local n = 0
        for _, q in ipairs(data or {}) do
            if Abandon(q.questID) then n = n + 1 end
        end
        print(ns.PREFIX .. ("abandoned %d quest%s."):format(n, n == 1 and "" or "s"))
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

abandonAll:SetScript("OnClick", function()
    local list, ready = Abandonable()
    if #list == 0 then return end
    local text = ("Abandon %d quest%s?"):format(#list, #list == 1 and "" or "s")
    if ready > 0 then
        text = text .. ("\n\n%d ready to turn in will be kept."):format(ready)
    end
    StaticPopup_Show("YDNT_ABANDON_ALL", text, nil, list)
end)

-- Keep the list current while it's open (throttled: QUEST_LOG_UPDATE fires constantly).
local pending = false
win:RegisterEvent("QUEST_LOG_UPDATE")
win:RegisterEvent("PLAYER_LEVEL_UP")
win:SetScript("OnEvent", function(self)
    if not self:IsShown() or pending then return end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        if self:IsShown() then self:Refresh() end
    end)
end)
win:SetScript("OnShow", function(self) self:Refresh() end)

function ns.ToggleQuests()
    win:SetShown(not win:IsShown())
end
ns.LowQuests = LowQuests

------------------------------------------------------------------------
-- Key binding (Bindings.xml)
------------------------------------------------------------------------
BINDING_HEADER_YOUDONTNEEDTHIS = "You Don't Need This"
BINDING_NAME_YDNT_TOGGLE_QUESTS = "Toggle low-level quests"
function YouDontNeedThis_ToggleQuests() ns.ToggleQuests() end

------------------------------------------------------------------------
-- Nudges: after login, and when a level-up turns quests low-level
------------------------------------------------------------------------
local LINK = "addon:YouDontNeedThis:quests"
-- Modern ItemRef.lua hands "addon:" links to EventRegistry's "SetItemRef" callback. Without that,
-- an unknown link type would raise an error when clicked, so fall back to plain text.
local clickable = EventRegistry and EventRegistry.RegisterCallback and true or false
if clickable then
    EventRegistry:RegisterCallback("SetItemRef", function(_, link)
        if link == LINK then ns.ToggleQuests() end
    end, win)
end

local function HowToOpen()
    if clickable then return "|cff71d5ff|H" .. LINK .. "|h[Show]|h|r" end
    local key = GetBindingKey and GetBindingKey("YDNT_TOGGLE_QUESTS")
    return "Type /ydnt q" .. (key and (" or press " .. key) or "") .. " to see them."
end

local function Nudge(text)
    if not Settings().questNudge then return end
    print(ns.PREFIX .. text .. " " .. HowToOpen())
end

local nudger = CreateFrame("Frame")
nudger:RegisterEvent("PLAYER_LOGIN")
nudger:RegisterEvent("PLAYER_LOGOUT")
nudger:RegisterEvent("PLAYER_LEVEL_UP")
nudger:SetScript("OnEvent", function(_, event, newLevel)
    if event == "PLAYER_LOGIN" then
        -- Wait for the quest log to be filled in (and after the bag summary from Bags.lua).
        -- Every login by default; with .questNudgeOnlyMore, only when there are more than last time.
        C_Timer.After(6, function()
            local s = Settings()
            local n = #LowQuests()
            if n > 0 and (not s.questNudgeOnlyMore or n > (s.lastLowCount or 0)) then
                Nudge(("you have %d low-level quest%s in your log."):format(n, n == 1 and "" or "s"))
            end
            s.lastLowCount = n
        end)
    elseif event == "PLAYER_LOGOUT" then
        Settings().lastLowCount = #LowQuests()
    else
        newLevel = tonumber(newLevel) or UnitLevel("player")
        C_Timer.After(1, function()
            local before = {}
            for _, q in ipairs(LowQuests(newLevel - 1)) do before[q.questID] = true end
            local now, fresh = LowQuests(newLevel), 0
            for _, q in ipairs(now) do if not before[q.questID] then fresh = fresh + 1 end end
            if fresh > 0 then
                Nudge(("%d quest%s just became low-level (%d in total)."):format(
                    fresh, fresh == 1 and "" or "s", #now))
            end
            if win:IsShown() then win:Refresh() end
        end)
    end
end)

------------------------------------------------------------------------
-- Button on the quest log (only where the classic QuestLogFrame exists)
------------------------------------------------------------------------
if QuestLogFrame then
    local b = CreateFrame("Button", nil, QuestLogFrame, "UIPanelButtonTemplate")
    b:SetSize(110, 20)
    b:SetPoint("TOPRIGHT", QuestLogFrame, "TOPRIGHT", -40, -14)
    b:SetText("Low-level")
    b:SetFrameLevel(QuestLogFrame:GetFrameLevel() + 10)
    b:SetScript("OnClick", ns.ToggleQuests)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("You Don't Need This")
        GameTooltip:AddLine("List your grey/green quests, with an Abandon button for each.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
