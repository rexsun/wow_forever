local _, ns = ...

-- The quest list ForeverUI draws itself, to the owner's mock-up: a header
-- ("Quests (5)") with a roll-up; tabs All / Zone / Story / Daily; one row
-- per tracked quest -- a badge, "[8] Title", the distance and an arrow --
-- with its objectives underneath, a ring for each and a green tick when it's
-- done; the quest you're following highlighted; and a footer with "Show
-- completed quests" and a cog for the settings.
--
-- It reads the quest log through C_QuestLog, every call guarded: on
-- Forever a title can arrive as a secret string (shown, never matched) and a
-- distance as a secret number (dropped). Blizzard's own tracker is hidden
-- while this is on. Everything is our own frame, so nothing here touches an
-- Edit Mode system.

local module = ns.GetModule("Quests")
if not module then
  return
end

local list                -- the panel
local rows = {}           -- pooled quest rows
local objRows = {}        -- pooled objective lines, per row
local tabs = {}
local state = { tab = "all" }
module.listState = state

local ROW_H, OBJ_H, TAB_H, HEAD_H, FOOT_H = 26, 18, 26, 30, 30
local GOLD = { 1, 0.82, 0 }
local GREEN = { 0.35, 0.85, 0.40 }

local QuestHelper, StepsTooltip

local function Settings()
  return ns.db.modules.Quests
end

---------------------------------------------------------------------------
-- Reading the log
---------------------------------------------------------------------------

local function Safe(fn, ...)
  local ok, a, b, c = pcall(fn, ...)
  if ok then return a, b, c end
  return nil
end

local function Distance(questID)
  local d = module.QuestDistance and module.QuestDistance(questID)
  if type(d) ~= "number" then
    return nil
  end
  local ok, yards = pcall(math.sqrt, d)
  return ok and yards or nil
end

local function DistanceText(yards)
  if not yards then return "" end
  if yards >= 1000 then
    return ("%.1fk yd"):format(yards / 1000)
  end
  return ("%d yd"):format(math.floor(yards + 0.5))
end
module.DistanceText = DistanceText

-- Which quests the game has on its watch list. Ticking the box beside a
-- quest in the log puts it here; it is not where the quests themselves live.
local function WatchedSet()
  local watched = {}
  if not (C_QuestLog and C_QuestLog.GetNumQuestWatches and C_QuestLog.GetQuestIDForQuestWatchIndex) then
    return watched
  end
  for i = 1, Safe(C_QuestLog.GetNumQuestWatches) or 0 do
    local questID = Safe(C_QuestLog.GetQuestIDForQuestWatchIndex, i)
    if questID then
      watched[questID] = true
    end
  end
  return watched
end
module.WatchedSet = WatchedSet

-- Every quest you are on, as a plain table the list can draw.
--
-- This reads the QUEST LOG, not the watch list. Those are different things,
-- and reading the wrong one is why a character with seven quests could be
-- looking at an empty tracker: this client does not tick the watch box when
-- you accept a quest, so the watch list sat at zero while the log had seven
-- entries in it. A tracker that shows nothing while you are carrying seven
-- quests is not tracking, so the log is the source now, and being on the
-- watch list is just a flag each quest carries. Anyone who does want the
-- game's behaviour back has "Only tracked quests" on the Quests page.
-- `all`: every quest in the log, whatever "Only tracked quests" says (the
-- quest guide must find the quest you clicked).
local function Read(all)
  local quests = {}
  if not (C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetNumQuestLogEntries) then
    return quests
  end
  local settings = Settings()
  local watched = WatchedSet()
  local entries = Safe(C_QuestLog.GetNumQuestLogEntries) or 0
  local zone = (GetZoneText and Safe(GetZoneText)) or ""
  local superID = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and Safe(C_SuperTrack.GetSuperTrackedQuestID)
  local header = nil   -- the zone heading these quests are sitting under

  for logIndex = 1, entries do
    local info = Safe(C_QuestLog.GetInfo, logIndex)
    if type(info) == "table" then
      if ns.Secrets.Bool(info.isHeader, false) then
        header = type(info.title) == "string" and info.title or nil
      else
        local questID = ns.Secrets.Number(info.questID)
        local wanted = questID ~= nil
          and (all or settings.trackedOnly ~= true or watched[questID] == true)
        if wanted then
          local q = {
            id = questID,
            logIndex = logIndex,
            title = (type(info.title) == "string" and info.title) or "",
            level = ns.Secrets.Number(info.level),
            complete = C_QuestLog.IsComplete and ns.Secrets.Bool(Safe(C_QuestLog.IsComplete, questID), false) or false,
            daily = (ns.Secrets.Number(info.frequency) or 0) > 0,
            story = ns.Secrets.Bool(info.isStory, false),
            header = header,
            yards = Distance(questID),
            objectives = {},
            watched = watched[questID] == true,
            selected = superID ~= nil and superID == questID,
          }
          q.inZone = q.header ~= nil and q.header == zone
          if C_QuestLog.GetQuestObjectives then
            local objectives = Safe(C_QuestLog.GetQuestObjectives, questID)
            for _, o in ipairs(type(objectives) == "table" and objectives or {}) do
              local text = type(o.text) == "string" and o.text or ""
              q.objectives[#q.objectives + 1] = { text = text, done = ns.Secrets.Bool(o.finished, false) }
            end
          end
          quests[#quests + 1] = q
        end
      end
    end
  end
  return quests
end
module.ReadQuests = Read

local function Passes(q, tab)
  if tab == "next" or tab == "dungeons" then return false end   -- not the log's quests
  if tab == "zone" then return q.inZone end
  if tab == "story" then return q.story end
  if tab == "daily" then return q.daily end
  return true
end

-- Filter to the open tab, then, if you asked for only the nearest few, keep
-- that many. The cap used to be enforced by trimming the game's watch list,
-- which worked while the list was read from it; now that the quest log is the
-- source, the cap has to be applied here or a character with twenty quests
-- would get all twenty down the side of the screen.
local function Filtered(quests)
  local out = {}
  local settings = Settings()
  local showCompleted = settings.showCompleted ~= false
  for _, q in ipairs(quests) do
    if Passes(q, state.tab) and (showCompleted or not q.complete) then
      out[#out + 1] = q
    end
  end

  local max = settings.maxShown or 5
  if not settings.nearbyOnly or #out <= max then
    return out
  end

  -- Nearest first. A distance the client won't give up sorts last rather
  -- than throwing, and a comparison that fails leaves the log's own order.
  local order = {}
  for i, q in ipairs(out) do
    order[q] = i
  end
  pcall(table.sort, out, function(a, b)
    local da, db = a.yards or math.huge, b.yards or math.huge
    if da ~= db then
      return da < db
    end
    return (order[a] or 0) < (order[b] or 0)
  end)
  for i = #out, max + 1, -1 do
    out[i] = nil
  end
  return out
end

-- What the panel would draw right now, for the tests and for /fui quests dump.
function module.FilteredQuests()
  return Filtered(Read())
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function Ring(parent, size)
  local ring = CreateFrame("Frame", nil, parent)
  ring:SetSize(size, size)
  ns.Skin.Border(ring, { 0.6, 0.6, 0.65, 1 })
  return ring
end

local function Badge(parent)
  local badge = CreateFrame("Frame", nil, parent)
  badge:SetSize(20, 20)
  ns.Skin.Panel(badge, { color = { 0.12, 0.10, 0.04, 1 }, borderColor = { 0.7, 0.55, 0.15, 1 } })
  badge.text = badge:CreateFontString(nil, "OVERLAY")
  badge.text:SetPoint("CENTER", 0, 0)
  ns.Media.SetFont(badge.text, "header")
  badge.text:SetText("!")
  badge.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  return badge
end

local function ObjectiveRow(row, index)
  objRows[row] = objRows[row] or {}
  local line = objRows[row][index]
  if line then return line end
  line = CreateFrame("Frame", nil, row)
  line:SetHeight(OBJ_H)
  -- Everything hangs from the top: an objective that wraps grows downward
  -- (Paint sizes the line to its text), and the ring or tick stays beside
  -- its first line instead of floating to the middle of two.
  line.ring = Ring(line, 10)
  line.ring:SetPoint("TOPLEFT", 34, -(OBJ_H - 10) / 2)
  line.tick = line:CreateFontString(nil, "OVERLAY")
  line.tick:SetPoint("TOPLEFT", 32, -2)
  ns.Media.SetFont(line.tick, "general")
  line.tick:SetText("v")
  line.tick:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
  line.text = line:CreateFontString(nil, "OVERLAY")
  line.text:SetPoint("TOPLEFT", 50, -2)
  line.text:SetPoint("RIGHT", -8, 0)
  line.text:SetJustifyH("LEFT")
  line.text:SetJustifyV("TOP")
  ns.Media.SetFont(line.text, "general")
  objRows[row][index] = line
  return line
end

-- QuestForever, when it is switched on and loaded.
QuestHelper = function()
  local qf = _G.QuestForever
  if qf and qf.running and qf.PointTo then return qf end
  return nil
end

-- Hovering a quest: what to do, step by step (from QuestForever).
StepsTooltip = function(row)
  local qf = QuestHelper()
  if not (qf and row.questID and GameTooltip and qf.Quest(row.questID)) then return end
  GameTooltip:SetOwner(row, "ANCHOR_LEFT")
  GameTooltip:SetText(qf.Quest(row.questID).name or "?", GOLD[1], GOLD[2], GOLD[3])
  qf.AddSteps(GameTooltip, row.questID)
  GameTooltip:AddLine("Click: the quest guide  -  Right-click: Blizzard's log", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function Row(index)
  local row = rows[index]
  if row then return row end
  row = CreateFrame("Button", nil, list.body)
  row:SetPoint("LEFT", 0, 0)
  row:SetPoint("RIGHT", 0, 0)
  row:RegisterForClicks("AnyUp")
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(0, 0, 0, 0)
  row.rule = row:CreateTexture(nil, "BORDER")
  row.rule:SetPoint("BOTTOMLEFT", 8, 0)
  row.rule:SetPoint("BOTTOMRIGHT", -8, 0)
  row.rule:SetHeight(ns.Media.Pixel())
  row.rule:SetColorTexture(0.2, 0.22, 0.26, 1)
  row.badge = Badge(row)
  row.badge:SetPoint("TOPLEFT", 8, -3)
  row.title = row:CreateFontString(nil, "OVERLAY")
  row.title:SetPoint("TOPLEFT", 36, -6)
  row.title:SetJustifyH("LEFT")
  -- One line, cut with "..." -- a wrapped title ran into the objectives.
  if row.title.SetWordWrap then row.title:SetWordWrap(false) end
  ns.Media.SetFont(row.title, "general")
  row.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  row.arrow = row:CreateFontString(nil, "OVERLAY")
  row.arrow:SetPoint("TOPRIGHT", -8, -6)
  ns.Media.SetFont(row.arrow, "general")
  row.arrow:SetText(">")
  ns.Skin.AccentText(row.arrow)
  row.distance = row:CreateFontString(nil, "OVERLAY")
  row.distance:SetPoint("RIGHT", row.arrow, "LEFT", -6, 0)
  row.distance:SetJustifyH("RIGHT")
  ns.Media.SetFont(row.distance, "general")
  row.distance:SetTextColor(unpack(ns.Colors.ui.textDim))
  -- "2/5": where this quest is in its line. Click it for the whole chain
  -- (QuestChain.lua). Owner, 27 Sept 2026: "an easy way in each quest
  -- where the user can see the entire quest chain".
  row.chain = CreateFrame("Button", nil, row)
  row.chain:SetHeight(16)
  row.chain:SetPoint("TOPRIGHT", row.distance, "TOPLEFT", -6, 2)
  row.chain:RegisterForClicks("AnyUp")
  row.chain.bg = row.chain:CreateTexture(nil, "BACKGROUND")
  row.chain.bg:SetAllPoints()
  local accent = ns.Colors.ui.accent
  row.chain.bg:SetColorTexture(accent[1], accent[2], accent[3], 0.18)
  row.chain.text = row.chain:CreateFontString(nil, "OVERLAY")
  row.chain.text:SetPoint("CENTER", 0, 0)
  ns.Media.SetFont(row.chain.text, "general")
  ns.Skin.AccentText(row.chain.text)
  row.chain:SetScript("OnClick", function(self)
    local id = self:GetParent().questID
    local shown, which = false, nil
    if module.ChainShown then shown, which = module.ChainShown() end
    if shown and which == id then module.HideChain() elseif module.ShowChain then module.ShowChain(id) end
  end)
  row.chain:SetScript("OnEnter", function(self)
    self.bg:SetAlpha(1.8)
    if GameTooltip and self.pos then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText(("Step %d of %d in this quest line"):format(self.pos.step, self.pos.total), 1, 1, 1)
      if self.pos.first then GameTooltip:AddLine("It starts with " .. self.pos.first, 0.8, 0.8, 0.8) end
      GameTooltip:AddLine("Click: see the whole chain and where you are in it", 0.8, 0.8, 0.8)
      GameTooltip:Show()
    end
  end)
  row.chain:SetScript("OnLeave", function(self)
    self.bg:SetAlpha(1)
    if GameTooltip then GameTooltip:Hide() end
  end)
  row.chain:Hide()
  row.title:SetPoint("RIGHT", row.distance, "LEFT", -6, 0)
  row:SetScript("OnClick", function(self, button)
    if not self.questID then return end
    if button == "RightButton" then
      module.OpenLog()
      return
    end
    -- Left click: the quest guide - what to do, as a list (QuestGuide.lua).
    -- The same quest again closes it.
    local shown, showing = false, nil
    if module.GuideShown then shown, showing = module.GuideShown() end
    if shown and showing == self.questID then
      module.HideGuide()
    elseif module.ShowGuide then
      module.ShowGuide(self.questID)
    end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
      pcall(C_SuperTrack.SetSuperTrackedQuestID, self.questID)
    end
    module.RefreshList()
  end)
  row:SetScript("OnEnter", function(self)
    if not self.selected then self.bg:SetColorTexture(1, 1, 1, 0.04) end
    StepsTooltip(self)
  end)
  row:SetScript("OnLeave", function(self)
    if not self.selected then self.bg:SetColorTexture(0, 0, 0, 0) end
    if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
  end)
  rows[index] = row
  return row
end

-- Quests > Text size reaches this list too (goldfish117 on CurseForge, 30
-- Sept 2026: "The text styling options for the tracker do not appear to work
-- at all" -- they only ever styled Blizzard's tracker, and this list is what
-- shows). 12 is the size it always had.
local function ListSize()
  local s = Settings()
  return math.max(8, math.min(20, tonumber(s and s.fontSize) or 12))
end
module.ListSize = ListSize

local function Sized(fs)
  if not (fs and fs.SetFont) then return end
  local path, _, outline = ns.Media.Role("general")
  fs:SetFont(path, ListSize(), outline or "")
end

local function Paint(row, q)
  row.questID = q.id
  Sized(row.title)
  Sized(row.distance)
  row.selected = q.selected
  local a = ns.Colors.ui.accent
  if q.selected then
    row.bg:SetColorTexture(a[1], a[2], a[3], 0.12)
  else
    row.bg:SetColorTexture(0, 0, 0, 0)
  end
  row.badge.text:SetText(q.complete and "?" or "!")
  row.title:SetText(q.level and ("[%d] %s"):format(q.level, q.title) or q.title)
  row.distance:SetText(DistanceText(q.yards))
  local badge, pos
  if module.ChainBadge then badge, pos = module.ChainBadge(q.id) end
  row.chain.pos = pos
  row.title:ClearAllPoints()
  row.title:SetPoint("TOPLEFT", 36, -6)
  if badge then
    row.chain.text:SetText(badge)
    local w = row.chain.text.GetStringWidth and row.chain.text:GetStringWidth() or (#badge * 6)
    row.chain:SetWidth(math.max(24, (tonumber(w) or 18) + 10))
    row.chain:Show()
    row.title:SetPoint("RIGHT", row.chain, "LEFT", -6, 0)
  else
    row.chain:Hide()
    row.title:SetPoint("RIGHT", row.distance, "LEFT", -6, 0)
  end
  local y = -math.max(ROW_H, ListSize() + 14)
  for i, o in ipairs(q.objectives) do
    local line = ObjectiveRow(row, i)
    Sized(line.text)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", row, "TOPLEFT", 0, y)
    line:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, y)
    line.text:SetText(o.text)
    line.ring:SetShown(not o.done)
    line.tick:SetShown(o.done)
    line.text:SetTextColor(o.done and 0.55 or 0.85, o.done and 0.55 or 0.85, o.done and 0.55 or 0.88)
    line:Show()
    -- As tall as its text: a long objective wraps onto a second line, and
    -- the next one starts below it rather than on top of it.
    local textH = line.text.GetStringHeight and line.text:GetStringHeight() or 0
    local h = math.max(OBJ_H, math.ceil(textH + 4))
    line:SetHeight(h)
    y = y - h
  end
  for i = #q.objectives + 1, #(objRows[row] or {}) do
    objRows[row][i]:Hide()
  end
  local height = -y + 4
  row:SetHeight(height)
  return height
end

local function PaintTabs(quests, nextCount)
  local counts = { all = 0, zone = 0, story = 0, daily = 0 }
  for _, q in ipairs(quests) do
    for key in pairs(counts) do
      if Passes(q, key) then counts[key] = counts[key] + 1 end
    end
  end
  counts.next = nextCount or 0
  counts.dungeons = module.DungeonList and #module.DungeonList() or 0
  for _, tab in ipairs(tabs) do
    tab:SetText(("%s (%d)"):format(tab.label, counts[tab.key] or 0))
    ns.Skin.SetSelected(tab, tab.key == state.tab)
  end
  return counts
end

---------------------------------------------------------------------------
-- What to pick up next (owner, 26 Sept 2026: "tell people what quest they
-- should get next"): the Next tab, and what an empty list shows.
---------------------------------------------------------------------------

local nextRows = {}

-- Quests you can pick up where you are, nearest first; {} without
-- QuestForever (it holds the data).
function module.NextQuests(limit)
  local qf = _G.QuestForever
  if not (qf and qf.running and qf.Suggest) then return {}, false end
  local ok, found = pcall(qf.Suggest, limit or 8)
  return (ok and found) or {}, true
end

local function NextRow(i)
  local row = nextRows[i]
  if row then return row end
  row = CreateFrame("Button", nil, list.body)
  row:RegisterForClicks("AnyUp")
  row:SetHeight(ROW_H)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(1, 1, 1, 0)
  row.badge = row:CreateFontString(nil, "OVERLAY")
  row.badge:SetPoint("LEFT", 10, 0)
  ns.Media.SetFont(row.badge, "general")
  row.badge:SetText("|TInterface\\GossipFrame\\AvailableQuestIcon:14:14|t")
  row.distance = row:CreateFontString(nil, "OVERLAY")
  row.distance:SetPoint("RIGHT", -10, 0)
  ns.Media.SetFont(row.distance, "general")
  row.distance:SetTextColor(0.62, 0.64, 0.70)
  row.title = row:CreateFontString(nil, "OVERLAY")
  row.title:SetPoint("LEFT", 30, 0)
  row.title:SetPoint("RIGHT", row.distance, "LEFT", -6, 0)
  row.title:SetJustifyH("LEFT")
  row.title:SetWordWrap(false)
  ns.Media.SetFont(row.title, "general")
  row.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  row:SetScript("OnEnter", function(self)
    self.bg:SetColorTexture(1, 1, 1, 0.05)
    if GameTooltip and self.item then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText(self.item.name or "?", 1, 1, 1)
      if self.item.who then GameTooltip:AddLine("From " .. self.item.who, 0.8, 0.8, 0.8) end
      GameTooltip:AddLine("Click: arrow to the quest giver", 0.6, 0.8, 1)
      GameTooltip:AddLine("Right-click: where it leads (its quest line)", 0.6, 0.8, 1)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(1, 1, 1, 0)
    if GameTooltip then GameTooltip:Hide() end
  end)
  row:SetScript("OnClick", function(self, button)
    local item = self.item
    if not item then return end
    if button == "RightButton" then
      if module.ShowGuide then module.ShowGuide(item.id) end
      return
    end
    local qf = _G.QuestForever
    local who = qf and qf.PointToStart and qf.PointToStart(item.id)
    ns.Print(who and ("arrow: %s - %s."):format(who, item.name or "?") or "QuestForever doesn't know where that one is picked up.")
  end)
  nextRows[i] = row
  return row
end

-- Lay the suggestions out from y; returns the new y.
local function PaintNext(items, y)
  for i, item in ipairs(items) do
    local row = NextRow(i)
    row.item = item
    row.title:SetText(((item.level or 0) > 0 and ("[%d] "):format(item.level) or "") .. (item.name or "?"))
    row.distance:SetText(DistanceText(item.yards))
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", list.body, "TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", list.body, "TOPRIGHT", 0, -y)
    row:Show()
    y = y + ROW_H
  end
  for i = #items + 1, #nextRows do nextRows[i]:Hide() end
  return y
end

function module.RefreshList()
  if not list or not list:IsShown() then
    return 0
  end
  local settings = Settings()
  local quests = Read()
  local nextItems, helperOn = module.NextQuests(8)
  local counts = PaintTabs(quests, #nextItems)
  module.listCounts = counts
  local shown = Filtered(quests)
  -- Say both numbers when the nearest-few cap is holding some back, so a
  -- header reading 6 above five rows doesn't look like a miscount.
  list.header.title:SetText(#shown < #quests
    and ("Quests (%d of %d)"):format(#shown, #quests)
    or ("Quests (%d)"):format(#quests))
  local y = 0
  local body = list.body
  local collapsed = settings.collapsed
  body:SetShown(not collapsed)
  list.tabRow:SetShown(not collapsed)
  list.footer:SetShown(not collapsed)
  for i, q in ipairs(shown) do
    local row = Row(i)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -y)
    y = y + Paint(row, q)
    row:Show()
  end
  for i = #shown + 1, #rows do
    rows[i]:Hide()
  end
  -- The Dungeons tab (Dungeons.lua): the dungeons, not the log.
  if state.tab == "dungeons" and module.PaintDungeonRows then
    PaintNext({}, 0)
    local count
    y, count = module.PaintDungeonRows(body, 0, ROW_H)
    if count == 0 then
      list.empty:ClearAllPoints()
      list.empty:SetPoint("TOP", body, "TOP", 0, -12)
      list.empty:SetText("This client doesn't list its dungeons.")
      list.empty:Show()
      y = 40
    else
      list.empty:Hide()
    end
    body:SetHeight(math.max(1, y))
    list:SetHeight(collapsed and HEAD_H or (HEAD_H + list.tabRow:GetHeight() + y + FOOT_H + 4))
    list:SetWidth(settings.width)
    if ns.FitMover then ns.FitMover("questList") end
    return 0
  elseif module.HideDungeonRows then
    module.HideDungeonRows()
  end
  -- The Next tab, or an empty log with something to pick up nearby: the
  -- quests you can take here, nearest first.
  local suggest = state.tab == "next"
    or (state.tab == "all" and #shown == 0 and not Settings().trackedOnly and #nextItems > 0)
  if suggest and #nextItems > 0 then
    list.empty:ClearAllPoints()
    list.empty:SetPoint("TOPLEFT", body, "TOPLEFT", 10, -6)
    list.empty:SetText(#shown == 0 and state.tab == "all" and "Quests you can pick up here:"
      or "Pick up next (nearest first):")
    list.empty:Show()
    y = PaintNext(nextItems, 24)
  elseif #shown == 0 then
    PaintNext({}, 0)
    list.empty:ClearAllPoints()
    list.empty:SetPoint("TOP", body, "TOP", 0, -12)
    list.empty:SetText(state.tab == "next"
      and (helperOn and "Nothing to pick up here - try the next zone over."
        or "Switch on the quest helper (Quick Setup) to see what to pick up next.")
      or state.tab == "all"
      and (Settings().trackedOnly and "No tracked quests. Tick a quest in the quest log, or turn \"Only tracked quests\" off."
        or "No quests. Go and pick some up.")
      or "None in this tab.")
    list.empty:Show()
    y = 40
  else
    PaintNext({}, 0)
    list.empty:Hide()
  end
  body:SetHeight(math.max(1, y))
  local total = collapsed and HEAD_H or (HEAD_H + list.tabRow:GetHeight() + y + FOOT_H + 4)
  list:SetHeight(total)
  list:SetWidth(settings.width)
  -- The handle follows, so it never hangs off the side of the panel.
  if ns.FitMover then ns.FitMover("questList") end
  list.footer.completed:SetText((settings.showCompleted ~= false and "Hide" or "Show") .. " completed quests")
  return #shown
end

local function Tab(key, label, x)
  local tab = CreateFrame("Button", nil, list.tabRow)
  tab.key, tab.label = key, label
  tab:SetSize(1, TAB_H - 4)
  ns.Skin.Button(tab)
  tab:SetText(label)
  tab:SetScript("OnClick", function()
    state.tab = key
    module.RefreshList()
  end)
  tabs[#tabs + 1] = tab
  return tab
end

local function Build()
  local ui = ns.Colors.ui
  list = CreateFrame("Frame", "ForeverUIQuestList", UIParent)
  list:SetSize(Settings().width, 200)
  ns.Skin.Panel(list, { color = { 0.03, 0.03, 0.05, 0.92 }, borderColor = ui.accent })
  module.list = list

  local header = CreateFrame("Button", nil, list)
  header:SetPoint("TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", -1, -1)
  header:SetHeight(HEAD_H)
  header:RegisterForClicks("AnyUp")
  header.title = header:CreateFontString(nil, "OVERLAY")
  header.title:SetPoint("LEFT", 10, 0)
  ns.Media.SetFont(header.title, "header")
  header.title:SetTextColor(1, 1, 1)
  header.rule = header:CreateTexture(nil, "BORDER")
  header.rule:SetPoint("BOTTOMLEFT"); header.rule:SetPoint("BOTTOMRIGHT"); header.rule:SetHeight(ns.Media.Pixel())
  ns.Skin.AccentTexture(header.rule, 0.5)
  header.roll = header:CreateFontString(nil, "OVERLAY")
  header.roll:SetPoint("RIGHT", -10, 0)
  ns.Media.SetFont(header.roll, "header")
  header.roll:SetText("-")
  ns.Skin.AccentText(header.roll)
  header:SetScript("OnClick", function() module.ToggleCollapsed() end)
  list.header = header

  local tabRow = CreateFrame("Frame", nil, list)
  tabRow:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
  tabRow:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
  -- Two rows: the log's five tabs, and Dungeons the full width under them
  -- (27 Sept 2026) -- six across a 260-wide panel cut every label short.
  tabRow:SetHeight(TAB_H * 2)
  list.tabRow = tabRow
  local last
  for _, def in ipairs({ { "all", "All" }, { "zone", "Zone" }, { "story", "Story" }, { "daily", "Daily" },
    { "next", "Next" } }) do
    local tab = Tab(def[1], def[2])
    if last then
      tab:SetPoint("TOPLEFT", last, "TOPRIGHT", 2, 0)
    else
      tab:SetPoint("TOPLEFT", tabRow, "TOPLEFT", 4, -2)
    end
    last = tab
  end
  local dungeons = Tab("dungeons", "Dungeons")
  dungeons:SetPoint("TOPLEFT", tabRow, "TOPLEFT", 4, -2 - TAB_H)
  dungeons:SetPoint("TOPRIGHT", tabRow, "TOPRIGHT", -4, -2 - TAB_H)
  tabRow:SetScript("OnSizeChanged", function(self, width)
    local n = #tabs - 1   -- the first row; Dungeons spans the second
    local w = math.floor((width - 8 - 2 * (n - 1)) / n)
    for i = 1, n do tabs[i]:SetWidth(math.max(40, w)) end
  end)

  local body = CreateFrame("Frame", nil, list)
  body:SetPoint("TOPLEFT", tabRow, "BOTTOMLEFT", 0, -2)
  body:SetPoint("TOPRIGHT", tabRow, "BOTTOMRIGHT", 0, -2)
  body:SetHeight(1)
  list.body = body
  list.empty = body:CreateFontString(nil, "OVERLAY")
  list.empty:SetPoint("TOP", body, "TOP", 0, -12)
  ns.Media.SetFont(list.empty, "general")
  list.empty:SetTextColor(unpack(ui.textDim))

  local footer = CreateFrame("Frame", nil, list)
  footer:SetPoint("BOTTOMLEFT", 1, 1)
  footer:SetPoint("BOTTOMRIGHT", -1, 1)
  footer:SetHeight(FOOT_H)
  footer.rule = footer:CreateTexture(nil, "BORDER")
  footer.rule:SetPoint("TOPLEFT"); footer.rule:SetPoint("TOPRIGHT"); footer.rule:SetHeight(ns.Media.Pixel())
  footer.rule:SetColorTexture(0.2, 0.22, 0.26, 1)
  local completed = CreateFrame("Button", nil, footer)
  completed:SetPoint("LEFT", 10, 0)
  completed:SetSize(200, FOOT_H - 6)
  completed.text = completed:CreateFontString(nil, "OVERLAY")
  completed.text:SetPoint("LEFT", 0, 0)
  completed.text:SetJustifyH("LEFT")
  ns.Media.SetFont(completed.text, "general")
  completed.text:SetTextColor(0.85, 0.85, 0.88)
  completed.eye = ns.Skin.Icon(completed, "eye", 14)
  completed.eye:SetPoint("RIGHT", completed.text, "LEFT", -8, 0)
  completed.text:ClearAllPoints()
  completed.text:SetPoint("LEFT", 24, 0)
  completed.SetText = function(self, text) self.text:SetText(text) end
  completed:SetScript("OnClick", function()
    Settings().showCompleted = (Settings().showCompleted == false)
    module.RefreshList()
  end)
  footer.completed = completed
  local cog = CreateFrame("Button", nil, footer)
  cog:SetPoint("RIGHT", -6, 0)
  cog:SetSize(22, 20)
  ns.Skin.Button(cog)
  cog.glyph = ns.Skin.Icon(cog, "general", 14, nil, "OVERLAY")
  cog.glyph:SetPoint("CENTER")
  cog:SetScript("OnClick", function() ns.OpenOptions("Quests") end)
  footer.cog = cog
  list.footer = footer

  local mover = ns.RegisterMover("questList", "Quest list", list, { "RIGHT", "RIGHT", -68, 124 })
  -- Grows down from its top as quests are added (Core/Movers.lua FitToFrame).
  if type(mover) == "table" then mover.growDown = true end

  -- Distances change as you walk; the log tells us the rest.
  local watcher = CreateFrame("Frame")
  for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_WATCH_UPDATE",
    "SUPER_TRACKING_CHANGED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED" }) do
    pcall(watcher.RegisterEvent, watcher, event)
  end
  watcher:SetScript("OnEvent", function() module.RefreshList() end)
  local since = 0
  watcher:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since >= 2 then
      since = 0
      if list:IsShown() then
        for _, row in ipairs(rows) do
          if row:IsShown() and row.questID then
            row.distance:SetText(DistanceText(Distance(row.questID)))
          end
        end
      end
    end
  end)
  list.watcher = watcher
end

-- Called by the Quests module: on when the owner wants the drawn list
-- instead of Blizzard's tracker dressed up.
function module.ShowList(show)
  if show and not list then
    Build()
  end
  if not list then
    return false
  end
  list:SetShown(show and true or false)
  if show then
    module.RefreshList()
  end
  return show and true or false
end
