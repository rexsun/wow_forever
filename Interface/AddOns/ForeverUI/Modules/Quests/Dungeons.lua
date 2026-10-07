local _, ns = ...

-- The Dungeons tab (owner, 27 Sept 2026: "build the Dungeons tab with what
-- we have").
--
-- Where each piece comes from:
--   the dungeons, their names in your language, the level range the game
--   suggests and the group size -- the game's own group finder
--   (C_LFGList.GetActivityInfoTable), which has Forever's new dungeons too;
--   where the door is and which quests belong to it -- QuestForever
--   (QF.Dungeon / QF.DungeonQuests: QuestieDB's Forever data), loaded for
--   the tab whether or not the quest helper's map pins are on.
-- Forever's new dungeons have no door or quests in the data yet; the window
-- says so instead of guessing.
--
-- Nothing here opens a Blizzard window (see ns.Skin.OpenHint): the list is
-- our own frame, and the arrow is QuestForever's waypoint.

local module = ns.GetModule("Quests")
if not module then
  return
end

local DUNGEON_CATEGORY = 2
-- Forever's own dungeons (group finder instance IDs): no data for them in
-- QuestieDB yet, but they are real and listed.
local FOREVER_NEW = { [2959] = true, [2998] = true, [2999] = true, [3065] = true }
-- Season of Discovery instances the client still carries in its tables.
-- Forever Guide counts 35 dungeons (26 Classic + 9 new), which leaves these
-- out; not verified in game.
local NOT_ON_FOREVER = { [2784] = true, [2875] = true }
local SCAN_TO = 2200

local GOLD = { 1, 0.82, 0 }
local DIM = { 0.62, 0.64, 0.70 }
local WHITE = { 0.92, 0.92, 0.94 }

-- QuestForever holds the doors and quests. The tab needs its DATA, not the
-- quest helper's map pins (27 Sept 2026: the owner keeps the helper off, and
-- the tab said "switch on the quest helper"): `load` loads the addon without
-- starting it -- only the Dungeons tab and window ask, never in combat, so
-- nobody who doesn't open the tab loads anything.
local whyNot   -- why QuestForever wouldn't load, for the window to say
local function Helper(load)
  local qf = _G.QuestForever
  if not qf and load and not (InCombatLockdown and InCombatLockdown()) then
    local loader = ns.GetModule("QuestForever")
    if loader and loader.Load then qf, whyNot = loader.Load() end
  end
  if qf and qf.Dungeon then return qf end
  return nil
end

-- "Scarlet Monastery - Graveyard" / "Stratholme (Main Gate)" -> the dungeon,
-- whatever the language, when a dungeon has wings.
local function BaseName(name)
  local base = name:match("^(.-)%s+%-%s+.+$") or name:match("^(.-)%s*%(.+%)%s*$")
  return (base and base ~= "") and base or name
end

local cached, cachedWithHelper
-- Every dungeon the group finder knows, one entry per instance (wings folded
-- in), lowest level first. Read once per session -- the table doesn't change
-- -- and again if the quest helper is switched on or off, since it decides
-- which instances are real dungeons.
function module.DungeonList(refresh)
  local helperOn = Helper() ~= nil
  if cached and not refresh and cachedWithHelper == helperOn then return cached end
  cachedWithHelper = helperOn
  local list, byMap = {}, {}
  local lfg = C_LFGList
  if not (lfg and lfg.GetActivityInfoTable) then
    cached = list
    return list
  end
  local qf = Helper()
  for id = 1, SCAN_TO do
    local ok, info = pcall(lfg.GetActivityInfoTable, id)
    if ok and type(info) == "table" and info.categoryID == DUNGEON_CATEGORY and type(info.fullName) == "string"
      and type(info.mapID) == "number" and not NOT_ON_FOREVER[info.mapID] then
      local map = info.mapID
      local known = FOREVER_NEW[map] or (qf and qf.Dungeon(map)) or not qf
      if known then
        local entry = byMap[map]
        local lo, hi = tonumber(info.minLevelSuggestion) or 0, tonumber(info.maxLevelSuggestion) or 0
        if not entry then
          entry = { map = map, name = info.fullName, min = lo, max = hi, players = info.maxNumPlayers,
            wings = {}, new = FOREVER_NEW[map] or false }
          byMap[map] = entry
          list[#list + 1] = entry
        else
          -- Wings: the dungeon's own name. "Lower/Upper Blackrock Spire"
          -- share an instance and have no common part to cut back to.
          if BaseName(entry.name) == BaseName(info.fullName) then
            entry.name = BaseName(entry.name)
          else
            local d = qf and qf.Dungeon(map)
            entry.name = d and d.name or entry.name
          end
          if lo > 0 and (entry.min == 0 or lo < entry.min) then entry.min = lo end
          if hi > entry.max then entry.max = hi end
        end
        entry.wings[#entry.wings + 1] = { name = info.fullName, min = lo, max = hi }
      end
    end
  end
  table.sort(list, function(a, b)
    if a.min ~= b.min then return a.min < b.min end
    return a.name < b.name
  end)
  cached = list
  return list
end

-- The game's own colours for "how hard is this for you".
local function LevelColor(entry)
  local mid = math.floor(((entry.min or 0) + (entry.max or 0)) / 2)
  if GetQuestDifficultyColor and mid > 0 then
    local ok, c = pcall(GetQuestDifficultyColor, mid)
    if ok and type(c) == "table" and c.r then return c.r, c.g, c.b end
  end
  return GOLD[1], GOLD[2], GOLD[3]
end

-- What to say when there's no QuestForever to ask. The game answers
-- "DISABLED" when it's switched off in the AddOns list (the owner's own
-- setup, 27 Sept 2026).
local function NoHelperText()
  if whyNot == "DISABLED" then
    return "Needs QuestForever (the quest data), which is switched off in the game's AddOns list (AddOns button at character select)."
  end
  return "Needs QuestForever (the quest data), which isn't installed."
end

local function Range(entry)
  if (entry.min or 0) <= 0 then return "" end
  if entry.max and entry.max > entry.min then return ("%d-%d"):format(entry.min, entry.max) end
  return tostring(entry.min)
end

---------------------------------------------------------------------------
-- Rows in the quest list's Dungeons tab
---------------------------------------------------------------------------

local dungeonRows = {}

local function DungeonRow(body, i, rowH)
  local row = dungeonRows[i]
  if row then return row end
  row = CreateFrame("Button", nil, body)
  row:RegisterForClicks("AnyUp")
  row:SetHeight(rowH)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(1, 1, 1, 0)
  row.count = row:CreateFontString(nil, "OVERLAY")
  row.count:SetPoint("RIGHT", -10, 0)
  ns.Media.SetFont(row.count, "general")
  row.count:SetTextColor(DIM[1], DIM[2], DIM[3])
  row.title = row:CreateFontString(nil, "OVERLAY")
  row.title:SetPoint("LEFT", 10, 0)
  row.title:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
  row.title:SetJustifyH("LEFT")
  row.title:SetWordWrap(false)
  ns.Media.SetFont(row.title, "general")
  row:SetScript("OnEnter", function(self)
    self.bg:SetColorTexture(1, 1, 1, 0.05)
    if GameTooltip and self.entry then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText(self.entry.name, 1, 1, 1)
      GameTooltip:AddLine("Click: the dungeon - its quests and where the door is", 0.6, 0.8, 1)
      GameTooltip:AddLine("Right-click: arrow to the entrance", 0.6, 0.8, 1)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(1, 1, 1, 0)
    if GameTooltip then GameTooltip:Hide() end
  end)
  row:SetScript("OnClick", function(self, button)
    if not self.entry then return end
    if button == "RightButton" then
      module.DungeonArrow(self.entry)
    else
      module.ShowDungeon(self.entry)
    end
  end)
  dungeonRows[i] = row
  return row
end

-- Which dungeons the tab shows: the ones for your level -- all 25 at once
-- ran the panel up over the minimap (27 Sept 2026) -- unless you asked for
-- all of them. "For your level": not already beneath you, and not more than
-- a dozen levels ahead.
local showAll = false
local function ForMyLevel(list)
  if showAll then return list end
  local level = UnitLevel and tonumber(UnitLevel("player")) or 0
  if not level or level <= 0 then return list end
  local out = {}
  for _, entry in ipairs(list) do
    local lo, hi = entry.min or 0, entry.max or 0
    if lo <= 0 or ((hi == 0 or hi >= level - 2) and lo <= level + 12) then
      out[#out + 1] = entry
    end
  end
  return out
end
module.DungeonsForMyLevel = ForMyLevel

local toggleRow
local function ToggleRow(body, rowH)
  if toggleRow then return toggleRow end
  toggleRow = CreateFrame("Button", nil, body)
  toggleRow:SetHeight(rowH)
  toggleRow.text = toggleRow:CreateFontString(nil, "OVERLAY")
  toggleRow.text:SetPoint("LEFT", 10, 0)
  ns.Media.SetFont(toggleRow.text, "general")
  ns.Skin.AccentText(toggleRow.text)
  toggleRow:SetScript("OnClick", function()
    showAll = not showAll
    module.RefreshList()
  end)
  return toggleRow
end

-- Lay the dungeons out in the list body from y; returns the new y.
function module.PaintDungeonRows(body, y, rowH)
  Helper(true)   -- the first time the tab is opened
  local all = module.DungeonList()
  local list = ForMyLevel(all)
  local qf = Helper()
  for i, entry in ipairs(list) do
    local row = DungeonRow(body, i, rowH)
    row.entry = entry
    local range = Range(entry)
    row.title:SetText((range ~= "" and ("[%s] "):format(range) or "") .. entry.name
      .. (entry.new and " |cff4dc3ffnew|r" or ""))
    row.title:SetTextColor(LevelColor(entry))
    local counts = qf and qf.DungeonQuestCounts and qf.DungeonQuestCounts(entry.map)
    if counts and counts.now + counts.log > 0 then
      row.count:SetText(("|cffffd100%d|r quest%s"):format(counts.now + counts.log, counts.now + counts.log == 1 and "" or "s"))
    elseif counts and counts.total > 0 then
      row.count:SetText(("%d quests"):format(counts.total))
    else
      row.count:SetText("")
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -y)
    row:Show()
    y = y + rowH
  end
  for i = #list + 1, #dungeonRows do dungeonRows[i]:Hide() end
  if #all > #list or showAll then
    local toggle = ToggleRow(body, rowH)
    toggle.text:SetText(showAll and "Only the ones for my level" or ("Show all %d dungeons"):format(#all))
    toggle:ClearAllPoints()
    toggle:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
    toggle:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -y)
    toggle:Show()
    y = y + rowH
  elseif toggleRow then
    toggleRow:Hide()
  end
  return y, #all
end

function module.HideDungeonRows()
  for _, row in ipairs(dungeonRows) do row:Hide() end
  if toggleRow then toggleRow:Hide() end
end

---------------------------------------------------------------------------
-- The arrow
---------------------------------------------------------------------------

function module.DungeonArrow(entry)
  local qf = Helper(true)
  if not qf then
    ns.Print(NoHelperText())
    return false
  end
  local where = qf.PointToEntrance(entry.map)
  if where then
    ns.Print(("arrow: the entrance to %s, in %s."):format(entry.name, where))
    return true
  end
  ns.Print(("the entrance to %s isn't known yet%s."):format(entry.name,
    entry.new and " - it's new in Forever" or ""))
  return false
end

---------------------------------------------------------------------------
-- The dungeon window
---------------------------------------------------------------------------

local WIDTH, PAD, ROW, MAX_ROWS = 360, 14, 18, 24
local win, current
local questRows = {}

local function Text(parent, role, color)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(fs, role or "general")
  fs:SetJustifyH("LEFT")
  local c = color or WHITE
  fs:SetTextColor(c[1], c[2], c[3])
  return fs
end

local function QuestRow(i)
  local row = questRows[i]
  if row then return row end
  row = CreateFrame("Button", nil, win.body)
  row:RegisterForClicks("AnyUp")
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(1, 1, 1, 0)
  row.status = Text(row, "general", DIM)
  row.status:SetPoint("TOPRIGHT", -4, -2)
  row.status:SetJustifyH("RIGHT")
  row.text = Text(row)
  row.text:SetPoint("TOPLEFT", 2, -2)
  row.text:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
  row.text:SetWordWrap(false)
  row:SetScript("OnEnter", function(self)
    self.bg:SetColorTexture(1, 1, 1, 0.05)
    if GameTooltip and self.quest then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.quest.name or "?", 1, 1, 1)
      GameTooltip:AddLine("Click: the quest and its whole line", 0.8, 0.8, 0.8)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(1, 1, 1, 0)
    if GameTooltip then GameTooltip:Hide() end
  end)
  row:SetScript("OnClick", function(self)
    if self.quest and module.ShowGuide then module.ShowGuide(self.quest.id) end
  end)
  questRows[i] = row
  return row
end

local function Build()
  win = CreateFrame("Frame", "ForeverUIDungeonGuide", UIParent)
  win:SetSize(WIDTH, 200)
  win:SetFrameStrata("HIGH")
  win:SetClampedToScreen(true)
  win:SetMovable(true)
  win:EnableMouse(true)
  ns.Skin.Panel(win, { color = { 0.03, 0.03, 0.05, 0.96 }, borderColor = ns.Colors.ui.accent })
  local header = ns.Skin.Header(win, "Dungeon")
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() win:StartMoving() end)
  header:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
  if UISpecialFrames then table.insert(UISpecialFrames, "ForeverUIDungeonGuide") end   -- Escape closes it

  local body = CreateFrame("Frame", nil, win)
  body:SetPoint("TOPLEFT", PAD, -40)
  body:SetPoint("RIGHT", -PAD, 0)
  body:SetHeight(10)
  win.body = body
  win.title = Text(body, "header", GOLD)
  win.sub = Text(body, "general", DIM)
  win.wings = Text(body, "general", DIM)
  win.wings:SetWordWrap(true)
  win.doorLabel = Text(body, "general", GOLD)
  win.doorLabel:SetText("ENTRANCE")
  win.door = Text(body)
  win.door:SetWordWrap(true)
  win.questLabel = Text(body, "general", GOLD)
  win.questLabel:SetText("QUESTS TO TAKE IN")
  win.none = Text(body, "general", DIM)
  win.none:SetWordWrap(true)
  win.more = Text(body, "general", DIM)

  local arrow = CreateFrame("Button", nil, win)
  arrow:SetHeight(22)
  ns.Skin.Button(arrow)
  arrow:SetText("Arrow to the entrance")
  arrow:SetWidth(170)
  arrow:SetPoint("BOTTOMLEFT", PAD, PAD)
  arrow:SetScript("OnClick", function() if current then module.DungeonArrow(current) end end)
  win.arrow = arrow

  -- Keep the statuses current while it's open.
  win:RegisterEvent("QUEST_LOG_UPDATE")
  win:RegisterEvent("QUEST_TURNED_IN")
  win:SetScript("OnEvent", function()
    if win:IsShown() and current then module.ShowDungeon(current, true) end
  end)
  win:Hide()
  module.dungeonWindow = win
end

local function Place(fs, y)
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", 0, y)
  fs:SetWidth(WIDTH - PAD * 2)
  fs:Show()
  return y - math.max(14, math.ceil(fs:GetStringHeight() or 14)) - 2
end

function module.ShowDungeon(entry, quiet)
  if not entry then return false end
  if not win then Build() end
  current = entry
  local qf = Helper(true)
  if not quiet and not win:IsShown() then
    win:ClearAllPoints()
    if module.list and module.list:IsShown() then
      win:SetPoint("TOPRIGHT", module.list, "TOPLEFT", -8, 0)
    else
      win:SetPoint("CENTER", UIParent, "CENTER", -200, 60)
    end
  end
  local y = 0
  win.title:SetText(entry.name)
  win.title:SetTextColor(LevelColor(entry))
  y = Place(win.title, y)
  local parts = {}
  local range = Range(entry)
  if range ~= "" then parts[#parts + 1] = "levels " .. range end
  if entry.players and entry.players > 0 then parts[#parts + 1] = ("%d players"):format(entry.players) end
  if entry.new then parts[#parts + 1] = "|cff4dc3ffnew in Forever|r" end
  win.sub:SetText(table.concat(parts, "  -  "))
  y = Place(win.sub, y) - 2
  if #entry.wings > 1 then
    local names = {}
    for _, wing in ipairs(entry.wings) do
      names[#names + 1] = ("%s (%s)"):format(wing.name, Range(wing))
    end
    win.wings:SetText(table.concat(names, "\n"))
    y = Place(win.wings, y) - 4
  else
    win.wings:Hide()
  end

  y = Place(win.doorLabel, y - 4)
  local d = qf and qf.Dungeon(entry.map)
  local doors = d and d.entrances or {}
  if #doors > 0 then
    local lines = {}
    for _, door in ipairs(doors) do
      local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(door[1])
      lines[#lines + 1] = ("%s  (%.1f, %.1f)"):format(info and info.name or "?", door[2] * 100, door[3] * 100)
    end
    if d.learnedDoor then
      lines[#lines + 1] = "|cff8a8a94(recorded when you walked in - Share sends it in for everyone)|r"
    end
    win.door:SetText(table.concat(lines, "\n"))
    win.arrow:Enable()
  else
    win.door:SetText(not qf and NoHelperText()
      or entry.new and "New in Forever - where its door is isn't known yet."
      or "Not known.")
    win.arrow:Disable()
  end
  y = Place(win.door, y) - 6

  y = Place(win.questLabel, y)
  local quests = qf and qf.DungeonQuests(entry.map) or {}
  local drawn = 0
  for i, q in ipairs(quests) do
    if i > MAX_ROWS then break end
    local row = QuestRow(i)
    row.quest = q
    local icon = module.LINE_ICON and module.LINE_ICON[q.status] or ""
    row.text:SetText(icon .. " " .. ((q.level or 0) > 0 and ("[%d] "):format(q.level) or "") .. (q.name or "?"))
    local dim = q.status == "done" or q.status == "closed" or q.status == "later"
    local c = dim and DIM or WHITE
    row.text:SetTextColor(c[1], c[2], c[3])
    row.status:SetText(module.LineStatus and module.LineStatus(q) or "")
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, y)
    row:SetSize(WIDTH - PAD * 2, ROW)
    row:Show()
    y = y - ROW
    drawn = i
  end
  for i = drawn + 1, #questRows do questRows[i]:Hide() end
  if #quests == 0 then
    win.none:SetText(not qf and ""
      or entry.new and "New in Forever - its quests aren't in the data yet."
      or "None for your character.")
    y = Place(win.none, y)
  else
    win.none:Hide()
  end
  if #quests > MAX_ROWS then
    win.more:SetText(("+ %d more"):format(#quests - MAX_ROWS))
    y = Place(win.more, y)
  else
    win.more:Hide()
  end

  win.body:SetHeight(-y)
  win:SetHeight(40 + (-y) + 22 + PAD * 2 + 6)
  win:Show()
  return true
end

function module.HideDungeon()
  if win then win:Hide() end
end
