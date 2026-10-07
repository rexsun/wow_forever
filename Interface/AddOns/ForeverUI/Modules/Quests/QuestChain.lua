local _, ns = ...

-- The quest chain window (owner, 27 Sept 2026: "an easy way in each quest
-- where the user can see the entire quest chain and where they are in that
-- chain").
--
-- Every quest in the list carries a "2/5" badge when it is part of a line;
-- click it (or "see the whole chain" in the quest guide, or /fui chain) and
-- this opens:
--
--   The Damned                                                     x
--   You're on step 2 of 5  -  1 done
--    1  v [2] The Damned                                      done
--    |      from Shadow Priest Sarvis, Deathknell
--    2  > [3] Scavenging Deathknell            YOU ARE HERE  in your log
--    |
--    3    [5] Marla's Last Wish                         take it now
--    3    [4] Night Web's Hollow                        level 4       (a side branch: same step)
--
-- Steps are numbered by how far along the line they are, so the branches
-- that open at the same point share a number. Click a step for its guide;
-- right-click for the arrow to it (to its quest giver, if you haven't got it).
-- The chain itself comes from QuestForever (QuestForever/Chains.lua).

local module = ns.GetModule("Quests")
if not module then
  return
end

local GOLD = { 1, 0.82, 0 }
local DIM = { 0.62, 0.64, 0.70 }
local WIDTH = 430
local ROW_H = 34
local MAX_VISIBLE = 12
local PAD = 12

local win
local rows = {}
local showing

local ICON = {
  done = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t",
  ready = "|TInterface\\GossipFrame\\ActiveQuestIcon:12:12|t",
  log = "|TInterface\\GossipFrame\\IncompleteQuestIcon:12:12|t",
  now = "|TInterface\\GossipFrame\\AvailableQuestIcon:12:12|t",
  later = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:12:12|t",
  closed = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12|t",
}

local function Text(parent, role, color)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(fs, role or "general")
  fs:SetJustifyH("LEFT")
  local c = color or { 0.92, 0.92, 0.94 }
  fs:SetTextColor(c[1], c[2], c[3])
  return fs
end

local function Helper()
  return module.GuideHelper and module.GuideHelper() or nil
end

local function MapName(mapID)
  if not (mapID and C_Map and C_Map.GetMapInfo) then return nil end
  local ok, info = pcall(C_Map.GetMapInfo, mapID)
  return ok and type(info) == "table" and info.name or nil
end

-- "from Shadow Priest Sarvis, Deathknell", for a step still to take.
local function FromLine(qf, step)
  if step.status == "done" or step.status == "log" or step.status == "ready" then return "" end
  local rec = qf.Quest and qf.Quest(step.id)
  local place = rec and qf.StartPlaces and qf.StartPlaces(rec)[1]
  if not place then return "" end
  local where = MapName(place[1])
  return ("from %s%s"):format(place[4] or "the quest giver", where and (", " .. where) or "")
end
module.ChainFromLine = FromLine

local function Row(i)
  local row = rows[i]
  if row then return row end
  row = CreateFrame("Button", nil, win.child)
  row:RegisterForClicks("AnyUp")
  row:SetHeight(ROW_H)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(1, 1, 1, 0)
  -- The line down the left that joins the steps.
  row.rail = row:CreateTexture(nil, "BORDER")
  row.rail:SetPoint("TOPLEFT", 14, 0)
  row.rail:SetPoint("BOTTOMLEFT", 14, 0)
  row.rail:SetWidth(2)
  local a = ns.Colors.ui.accent
  row.rail:SetColorTexture(a[1], a[2], a[3], 0.35)
  row.num = Text(row, "general", DIM)
  row.num:SetPoint("TOPLEFT", 4, -4)
  row.num:SetWidth(24)
  row.num:SetJustifyH("CENTER")
  row.status = Text(row, "general", DIM)
  row.status:SetPoint("TOPRIGHT", -6, -4)
  row.status:SetJustifyH("RIGHT")
  row.here = Text(row, "general")
  ns.Skin.AccentText(row.here)
  row.here:SetPoint("RIGHT", row.status, "LEFT", -8, 0)
  row.name = Text(row)
  row.name:SetPoint("TOPLEFT", 32, -4)
  row.name:SetPoint("RIGHT", row.here, "LEFT", -6, 0)
  if row.name.SetWordWrap then row.name:SetWordWrap(false) end
  row.from = Text(row, "general", DIM)
  row.from:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
  row.from:SetPoint("RIGHT", -6, 0)
  if row.from.SetWordWrap then row.from:SetWordWrap(false) end
  row:SetScript("OnEnter", function(self)
    if not self.current then self.bg:SetColorTexture(1, 1, 1, 0.05) end
    if GameTooltip and self.step then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.step.name or "?", 1, 1, 1)
      GameTooltip:AddLine("Click: what to do (the quest guide)", 0.8, 0.8, 0.8)
      GameTooltip:AddLine("Right-click: arrow to it", 0.8, 0.8, 0.8)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function(self)
    if not self.current then self.bg:SetColorTexture(1, 1, 1, 0) end
    if GameTooltip then GameTooltip:Hide() end
  end)
  row:SetScript("OnClick", function(self, button)
    local step = self.step
    if not step then return end
    local qf = Helper()
    if button == "RightButton" and qf then
      local who
      if qf.inLog and qf.inLog[step.id] then
        who = qf.PointTo and qf.PointTo(step.id)
      elseif qf.PointToStart then
        who = qf.PointToStart(step.id)
      end
      ns.Print(who and ("arrow to %s."):format(who) or "no place known for that one yet.")
      return
    end
    if module.ShowGuide then module.ShowGuide(step.id) end
  end)
  rows[i] = row
  return row
end

local function Build()
  win = CreateFrame("Frame", "ForeverUIQuestChain", UIParent)
  win:SetSize(WIDTH, 200)
  win:SetFrameStrata("HIGH")
  win:SetClampedToScreen(true)
  win:SetMovable(true)
  win:EnableMouse(true)
  ns.Skin.Panel(win, { color = { 0.03, 0.03, 0.05, 0.96 }, borderColor = ns.Colors.ui.accent })
  local header = ns.Skin.Header(win, "Quest chain", function() module.HideChain() end)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() win:StartMoving() end)
  header:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
  if UISpecialFrames then table.insert(UISpecialFrames, "ForeverUIQuestChain") end  -- Escape closes it

  win.title = Text(win, "header", GOLD)
  win.title:SetPoint("TOPLEFT", PAD, -40)
  win.title:SetPoint("RIGHT", -PAD, 0)
  win.sub = Text(win, "general", DIM)
  win.sub:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -4)
  win.sub:SetPoint("RIGHT", -PAD, 0)

  local scroll = CreateFrame("ScrollFrame", "ForeverUIQuestChainScroll", win, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", PAD, -84)
  scroll:SetPoint("BOTTOMRIGHT", -PAD - 20, PAD + 18)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(WIDTH - PAD * 2 - 20, 10)
  scroll:SetScrollChild(child)
  win.scroll, win.child = scroll, child

  win.hint = Text(win, "general", DIM)
  win.hint:SetPoint("BOTTOMLEFT", PAD, PAD)
  win.hint:SetText("Click a step for what to do; right-click for the arrow to it.")

  win:RegisterEvent("QUEST_LOG_UPDATE")
  win:RegisterEvent("QUEST_TURNED_IN")
  win:SetScript("OnEvent", function()
    if win:IsShown() and showing then module.ShowChain(showing, true) end
  end)
  win:Hide()
end

-- Open the chain a quest belongs to. `quiet`: a refresh, not a click.
function module.ShowChain(questID, quiet)
  local qf = Helper()
  if not (qf and qf.ChainPosition) then
    if not quiet then ns.Print("switch the quest helper on to see quest chains (/fui qf).") end
    return false
  end
  local pos = type(questID) == "number" and qf.ChainPosition(questID)
  if not pos then
    if not quiet then ns.Print("that quest stands on its own - it isn't part of a chain.") end
    if win then win:Hide() end
    return false
  end
  if not win then Build() end
  showing = questID
  if not quiet and not win:IsShown() then
    win:ClearAllPoints()
    local guide = _G.ForeverUIQuestGuide
    if guide and guide:IsShown() then
      win:SetPoint("TOPRIGHT", guide, "TOPLEFT", -8, 0)
    elseif module.list and module.list:IsShown() then
      win:SetPoint("TOPRIGHT", module.list, "TOPLEFT", -8, 0)
    else
      win:SetPoint("CENTER", UIParent, "CENTER", -200, 60)
    end
  end

  local done = 0
  for _, step in ipairs(pos.line) do
    if step.status == "done" then done = done + 1 end
  end
  win.title:SetText(pos.first or "Quest chain")
  win.sub:SetText(("You're on step %d of %d  -  %d of %d quests done"):format(pos.step, pos.total, done, #pos.line))

  local inner = WIDTH - PAD * 2 - 20
  local y = 0
  for i, step in ipairs(pos.line) do
    local row = Row(i)
    row.step = step
    row.current = step.current
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, y)
    row:SetWidth(inner)
    row.num:SetText(tostring((step.depth or 0) + 1))
    local label = ((step.level or 0) > 0 and ("[%d] "):format(step.level) or "") .. (step.name or "?")
    row.name:SetText((ICON[step.status] or "") .. " " .. label)
    local dim = step.status == "done" or step.status == "closed" or step.status == "later"
    local c = step.current and { 1, 1, 1 } or (dim and DIM or { 0.92, 0.92, 0.94 })
    row.name:SetTextColor(c[1], c[2], c[3])
    row.status:SetText(module.LineStatus and module.LineStatus(step) or step.status)
    row.here:SetText(step.current and "YOU ARE HERE" or "")
    row.from:SetText(FromLine(qf, step))
    local a = ns.Colors.ui.accent
    if step.current then
      row.bg:SetColorTexture(a[1], a[2], a[3], 0.14)
    else
      row.bg:SetColorTexture(1, 1, 1, 0)
    end
    -- The rail stops at the last step.
    row.rail:SetShown(i < #pos.line)
    row:Show()
    y = y - ROW_H
  end
  for i = #pos.line + 1, #rows do rows[i]:Hide() end
  win.child:SetHeight(-y)
  local visible = math.min(#pos.line, MAX_VISIBLE)
  win:SetHeight(84 + visible * ROW_H + PAD + 22)
  win:Show()
  return true
end

function module.HideChain()
  if win then win:Hide() end
  showing = nil
end

function module.ChainShown()
  return win ~= nil and win:IsShown(), showing
end

-- The "2/5" a quest wears in the list, or nil when it is on its own.
function module.ChainBadge(questID)
  local qf = Helper()
  local pos = qf and qf.ChainPosition and qf.ChainPosition(questID)
  if not pos then return nil end
  return ("%d/%d"):format(pos.step, pos.total), pos
end
