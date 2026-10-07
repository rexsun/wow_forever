local _, ns = ...

-- The quest guide: click a quest in ForeverUI's quest list and this says, in
-- plain words, what to do - not Blizzard's page of story.
--
--   [11] Preparation for Ceremony                       428 yd
--   GOAL   Bring 6 Azure Feathers and 6 Bronze Feathers to Eyahn Eagletalon.
--   WHAT TO DO
--    1  Loot Azure Feather from Windfury Sorceress            0/6
--    2  Loot Bronze Feather from Windfury Matriarch           0/6
--   WHEN IT'S DONE   Hand in to Eyahn Eagletalon (Thunder Bluff)
--   [Arrow to next step] [Show on map] [Share] [Abandon] [Blizzard's log]
--
-- The goal line is the game's own one-line summary of the quest. The steps
-- come from QuestForever when it is switched on (who to kill, what drops
-- what, where) and from the game's objective lines when it isn't. Click a
-- step and the waypoint arrow points at the nearest place for it. The owner's
-- ask, 24 Sept 2026: "a screen when people clicked this that actually told
-- them what they need to do as a list".

local module = ns.GetModule("Quests")
if not module then
  return
end

local GOLD = { 1, 0.82, 0 }
local GREEN = { 0.35, 0.85, 0.40 }
local DIM = { 0.62, 0.64, 0.70 }
local WIDTH = 380
local PAD = 12

local guide
local stepRows = {}
local current            -- the quest ID on show

local function Safe(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if ok then return a, b, c end
  return nil
end

local function Text(parent, role, color)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(fs, role or "general")
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  if fs.SetWordWrap then fs:SetWordWrap(true) end
  local c = color or { 0.92, 0.92, 0.94 }
  fs:SetTextColor(c[1], c[2], c[3])
  return fs
end

local function Label(parent, text)
  local fs = Text(parent, "general", DIM)
  fs:SetText(text)
  return fs
end

-- QuestForever, when it is switched on and loaded.
-- QuestForever's data, whenever it's loaded: running (the quest helper's
-- pins on), or loaded by the Dungeons tab with the pins off -- a dungeon's
-- quests open here either way (27 Sept 2026).
local function Helper()
  local qf = _G.QuestForever
  if qf and qf.HowTo then return qf end
  return nil
end
module.GuideHelper = Helper

-- The quest as the log has it (module.ReadQuests), or nil when it's gone.
local function FromLog(questID)
  for _, q in ipairs(module.ReadQuests and module.ReadQuests(true) or {}) do
    if q.id == questID then return q end
  end
  return nil
end

-- The game's one-line objective ("Bring 6 Azure Feathers ... to ..."):
-- the second thing GetQuestLogQuestText gives, for the selected quest. The
-- log's selection is put back afterwards.
local function Goal(q)
  if not GetQuestLogQuestText then return nil end
  local log = C_QuestLog
  local before = log and log.GetSelectedQuest and Safe(log.GetSelectedQuest)
  if log and log.SetSelectedQuest then
    Safe(log.SetSelectedQuest, q.id)
  elseif SelectQuestLogEntry and q.logIndex then
    Safe(SelectQuestLogEntry, q.logIndex)
  end
  local _, objectives = Safe(GetQuestLogQuestText)
  if before and log and log.SetSelectedQuest then Safe(log.SetSelectedQuest, before) end
  if type(objectives) ~= "string" or (issecretvalue and issecretvalue(objectives)) or objectives == "" then
    return nil
  end
  return objectives
end

-- The steps: QuestForever's plain words, or the game's objective lines.
local function Steps(q)
  local qf = Helper()
  if qf and qf.Quest(q.id) then
    local steps = qf.HowTo(qf.Quest(q.id), qf.inLog[q.id])
    if #steps > 0 then return steps, true end
  end
  local steps = {}
  for _, o in ipairs(q.objectives or {}) do
    steps[#steps + 1] = { text = o.text, done = o.done, names = {} }
  end
  return steps, false
end

local function MapName(mapID)
  local info = mapID and C_Map and Safe(C_Map.GetMapInfo, mapID)
  return type(info) == "table" and info.name or nil
end

local function HandInLine(q)
  local qf = Helper()
  local who, map = nil, nil
  if qf and qf.HandIn then who, map = qf.HandIn(q.id) end
  if who then
    local where = MapName(map)
    return ("Hand in to %s%s"):format(who, where and (" (" .. where .. ")") or "")
  end
  if q.complete then return "Hand it in to whoever gave it to you." end
  return nil
end

---------------------------------------------------------------------------
-- The quest line (owner, 26 Sept 2026: "show them where they are in a quest
-- line ... the entire branch ... what they need and what they don't")
---------------------------------------------------------------------------

local LINE_ROWS = 14   -- steps shown before "+N more"
local ICON = {
  done = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t",
  ready = "|TInterface\\GossipFrame\\ActiveQuestIcon:12:12|t",
  log = "|TInterface\\GossipFrame\\IncompleteQuestIcon:12:12|t",
  now = "|TInterface\\GossipFrame\\AvailableQuestIcon:12:12|t",
  later = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:12:12|t",
  closed = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12|t",
}
module.LINE_ICON = ICON   -- the Dungeons window marks its quests the same way
local WHY = {
  ["needs an earlier quest"] = "after an earlier step",
  trivial = "too low to show",
  repeatable = "repeatable",
  profession = "profession",
  ["not offered"] = "not offered yet",
  reputation = "needs reputation",
  holiday = "holiday not on now",
}

-- What one step of the line says on the right.
function module.LineStatus(step)
  if step.status == "done" then return "|cff59d966done|r" end
  if step.status == "ready" then return "|cff59d966hand it in|r" end
  if step.status == "log" then return "in your log" end
  if step.status == "now" then return "|cffffd100take it now|r" end
  if step.status == "closed" then return "|cff8a8a94other branch taken|r" end
  if step.why == "level" then return ("|cff8a8a94level %d|r"):format(step.req or 1) end
  return "|cff8a8a94" .. (WHY[step.why] or step.why or "later") .. "|r"
end

-- A quest not in your log, as far as QuestForever knows it: enough for the
-- guide to show where it's picked up and the line it belongs to.
local function Preview(questID)
  local qf = Helper()
  local rec = qf and qf.Quest and qf.Quest(questID)
  if not rec then return nil end
  return { id = questID, title = rec.name, level = rec.level, preview = true }
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

local function Say(text) ns.Print(text) end

function module.GuideArrow(questID)
  local qf = Helper()
  if not qf then
    Say("switch on QuestForever (/fui qf) and the arrow can point you there.")
    return false
  end
  -- A route someone walked for it (yours, or the curated one): the arrow
  -- walks it point by point, then on to the objective (QuestForever/Curation.lua).
  local state = qf.inLog and qf.inLog[questID]
  if state and not state.complete and qf.Route and qf.FollowRoute and #qf.Route(questID) > 0 then
    local ok, first, total = qf.FollowRoute(questID)
    if ok then
      Say(("arrow: following the route, point %d of %d, then the objective."):format(first, total))
      return true
    end
  end
  -- Not in your log yet: to whoever gives it.
  local who
  if not (qf.inLog and qf.inLog[questID]) and qf.PointToStart then
    who = qf.PointToStart(questID)
  else
    who = qf.PointTo(questID)
  end
  if who then
    Say(("arrow: %s."):format(who))
    return true
  end
  Say("QuestForever doesn't know where that is yet.")
  return false
end

local function StepArrow(questID, step)
  local qf = Helper()
  if not qf then
    Say("switch on QuestForever (/fui qf) and the arrow can point you there.")
    return
  end
  local map, x, y, who = qf.StepTarget(questID, step)
  if map then
    qf.SetWaypoint(map, x, y)
    Say(("arrow: %s."):format(who or step.text))
  else
    module.GuideArrow(questID)
  end
end

-- The map is the game's to open (see ns.Skin.OpenHint): the arrow is set to
-- the next step, and the player is told which key shows the map. (The
-- guide's own "Map" button opens it through the game's button instead.)
function module.GuideShowMap(questID)
  module.GuideArrow(questID)
  return ns.Skin.OpenHint("map")
end

local function Share(questID)
  if C_QuestLog and C_QuestLog.IsPushableQuest and not Safe(C_QuestLog.IsPushableQuest, questID) then
    Say("that quest can't be shared.")
    return
  end
  if QuestLogPushQuest then
    if C_QuestLog and C_QuestLog.SetSelectedQuest then Safe(C_QuestLog.SetSelectedQuest, questID) end
    Safe(QuestLogPushQuest)
  end
end

-- Abandoning is for good, so the game's own confirmation asks first.
local function Abandon(questID)
  if not (C_QuestLog and C_QuestLog.SetSelectedQuest and C_QuestLog.SetAbandonQuest) then
    module.OpenLog()
    return
  end
  Safe(C_QuestLog.SetSelectedQuest, questID)
  Safe(C_QuestLog.SetAbandonQuest)
  local name = C_QuestLog.GetAbandonQuest and Safe(C_QuestLog.GetAbandonQuest)
  if StaticPopup_Show then
    Safe(StaticPopup_Show, "ABANDON_QUEST", name or "")
  end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function StepRow(i)
  local row = stepRows[i]
  if row then return row end
  row = CreateFrame("Button", nil, guide.body)
  row:RegisterForClicks("AnyUp")
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(1, 1, 1, 0)
  row.num = Text(row, "general", GOLD)
  row.num:SetPoint("TOPLEFT", 2, -3)
  row.num:SetWidth(18)
  row.num:SetJustifyH("CENTER")
  row.progress = Text(row, "general", DIM)
  row.progress:SetPoint("TOPRIGHT", -4, -3)
  row.progress:SetJustifyH("RIGHT")
  row.text = Text(row)
  row.text:SetPoint("TOPLEFT", 26, -3)
  row.text:SetPoint("RIGHT", row.progress, "LEFT", -8, 0)
  row:SetScript("OnEnter", function(self)
    self.bg:SetColorTexture(1, 1, 1, 0.05)
    if GameTooltip and self.step and not self.step.done then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("Click: the arrow points to the nearest place for this", 1, 1, 1)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(1, 1, 1, 0)
    if GameTooltip then GameTooltip:Hide() end
  end)
  row:SetScript("OnClick", function(self)
    if self.step and current then StepArrow(current, self.step) end
  end)
  stepRows[i] = row
  return row
end

local lineRows = {}
local function LineRow(i)
  local row = lineRows[i]
  if row then return row end
  row = CreateFrame("Button", nil, guide.body)
  row:RegisterForClicks("AnyUp")
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(1, 1, 1, 0)
  row.status = Text(row, "general", DIM)
  row.status:SetPoint("TOPRIGHT", -4, -2)
  row.status:SetJustifyH("RIGHT")
  row.text = Text(row)
  row.text:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
  row.text:SetWordWrap(false)
  row:SetScript("OnEnter", function(self)
    self.bg:SetColorTexture(1, 1, 1, 0.05)
    if GameTooltip and self.step then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.step.name or "?", 1, 1, 1)
      GameTooltip:AddLine("Click: open this quest here", 0.8, 0.8, 0.8)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(1, 1, 1, 0)
    if GameTooltip then GameTooltip:Hide() end
  end)
  row:SetScript("OnClick", function(self)
    if self.step and self.step.id ~= current then module.ShowGuide(self.step.id) end
  end)
  lineRows[i] = row
  return row
end

local function Button(parent, label, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(22)
  ns.Skin.Button(b)
  b:SetText(label)
  local fs = b.GetFontString and b:GetFontString()
  local w = (fs and fs.GetStringWidth and fs:GetStringWidth() or (#label * 6)) + 16
  b:SetWidth(math.max(60, w))
  b:SetScript("OnClick", onClick)
  return b
end

local function Build()
  guide = CreateFrame("Frame", "ForeverUIQuestGuide", UIParent)
  guide:SetSize(WIDTH, 300)
  guide:SetFrameStrata("HIGH")
  guide:SetClampedToScreen(true)
  guide:SetMovable(true)
  guide:EnableMouse(true)
  ns.Skin.Panel(guide, { color = { 0.03, 0.03, 0.05, 0.96 }, borderColor = ns.Colors.ui.accent })
  local header = ns.Skin.Header(guide, "Quest guide")
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() guide:StartMoving() end)
  header:SetScript("OnDragStop", function() guide:StopMovingOrSizing() end)
  if UISpecialFrames then table.insert(UISpecialFrames, "ForeverUIQuestGuide") end  -- Escape closes it

  local body = CreateFrame("Frame", nil, guide)
  body:SetPoint("TOPLEFT", PAD, -40)
  body:SetPoint("RIGHT", -PAD, 0)
  body:SetHeight(10)
  guide.body = body

  guide.title = Text(body, "header", GOLD)
  guide.distance = Text(body, "general", DIM)
  guide.distance:SetJustifyH("RIGHT")
  guide.sub = Text(body, "general", DIM)
  guide.goalLabel = Label(body, "GOAL")
  guide.goal = Text(body)
  guide.stepsLabel = Label(body, "WHAT TO DO")
  guide.none = Text(body, "general", DIM)
  guide.doneLabel = Label(body, "WHEN IT'S DONE")
  guide.done = Text(body)
  -- "Quest line: step 2 of 5 - see the whole chain" (QuestChain.lua).
  local chainLink = CreateFrame("Button", nil, body)
  chainLink:SetHeight(16)
  chainLink.text = Text(chainLink, "general")
  chainLink.text:SetPoint("LEFT", 0, 0)
  chainLink:SetScript("OnClick", function() if current and module.ShowChain then module.ShowChain(current) end end)
  chainLink:SetScript("OnEnter", function(self) self.text:SetAlpha(0.8) end)
  chainLink:SetScript("OnLeave", function(self) self.text:SetAlpha(1) end)
  guide.chainLink = chainLink
  -- A note and a route for the quest (QuestForever/Curation.lua).
  guide.noteLabel = Label(body, "NOTE")
  guide.note = Text(body, "general", { 1, 0.9, 0.62 })
  guide.routeLabel = Label(body, "ROUTE")
  guide.route = Text(body, "general", DIM)
  local editLink = CreateFrame("Button", nil, body)
  editLink:SetHeight(16)
  editLink.text = Text(editLink, "general")
  ns.Skin.AccentText(editLink.text)
  editLink.text:SetPoint("LEFT", 0, 0)
  editLink:SetScript("OnClick", function()
    guide.editing = not guide.editing
    if current then module.ShowGuide(current, true) end
  end)
  guide.editLink = editLink
  guide.edit = module.BuildEditPanel(body)
  guide.lineLabel = Label(body, "QUEST LINE")
  guide.lineMore = Text(body, "general", DIM)
  guide.hint = Text(body, "general", DIM)
  -- Its own switch, where it's seen: open this when a quest is picked up.
  local auto = CreateFrame("Button", nil, body)
  auto:SetHeight(16)
  auto.text = Text(auto, "general", DIM)
  auto.text:SetPoint("LEFT", 0, 0)
  auto:SetScript("OnClick", function()
    local s, key = ns.db.modules.Quests, module.AutoGuideKey()
    s[key] = not module.AutoGuideOn()
    module.PaintAutoLine()
  end)
  auto:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
  auto:SetScript("OnLeave", function(self) self.text:SetTextColor(DIM[1], DIM[2], DIM[3]) end)
  guide.auto = auto

  local bar = CreateFrame("Frame", nil, guide)
  bar:SetPoint("BOTTOMLEFT", PAD, PAD)
  bar:SetPoint("BOTTOMRIGHT", -PAD, PAD)
  bar:SetHeight(22)
  guide.buttons = bar
  guide.buttonByLabel = {}
  local prev
  -- "Map" and "Blizzard's log" open the game's own windows through its own
  -- buttons (ns.Skin.OpenOver) -- the map with the arrow already set.
  for _, spec in ipairs({
    { "Arrow", function() if current then module.GuideArrow(current) end end },
    { "Map", nil, "map", function() if current then module.GuideArrow(current) end end },
    { "Share", function() if current then Share(current) end end },
    { "Abandon", function() if current then Abandon(current) end end },
    { "Blizzard's log", nil, "questlog" },
  }) do
    local b = Button(bar, spec[1], spec[2])
    if spec[3] then ns.Skin.OpenOver(b, spec[3], spec[4]) end
    guide.buttonByLabel[spec[1]] = b
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("LEFT", 0, 0) end
    prev = b
  end

  -- Keep up with kills and loot while it's open.
  guide:RegisterEvent("QUEST_LOG_UPDATE")
  guide:RegisterEvent("QUEST_REMOVED")
  guide:SetScript("OnEvent", function()
    if guide:IsShown() and current then module.ShowGuide(current, true) end
  end)
  guide:Hide()
end

-- Lay a line of text out at y (going down); returns the next y.
local function Place(fs, y, x, width)
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", x or 0, y)
  fs:SetWidth(width or (WIDTH - PAD * 2))
  fs:Show()
  return y - math.ceil(fs:GetStringHeight() or 14) - 4
end

---------------------------------------------------------------------------
-- Notes and routes (owner, 27 Sept 2026: "make a way that I can improve
-- routes and notes on the questing application"). What is typed here is
-- kept by QuestForever (Curation.lua); the owner's own is folded into what
-- everyone gets by tools/quest_curate.lua, and anyone's goes out with
-- /fui qf export.
---------------------------------------------------------------------------

local function EditBox(parent, width, hint)
  local box = CreateFrame("EditBox", nil, parent)
  box:SetSize(width, 22)
  box:SetAutoFocus(false)
  ns.Media.SetFont(box, "general")
  ns.Skin.Panel(box, { color = { 0.04, 0.03, 0.05, 0.94 }, borderColor = { 0.3, 0.32, 0.38 } })
  box:SetTextInsets(6, 6, 0, 0)
  box.hint = Text(box, "general", DIM)
  box.hint:SetPoint("LEFT", 6, 0)
  box.hint:SetText(hint)
  box:SetScript("OnTextChanged", function(self) self.hint:SetShown((self:GetText() or "") == "") end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return box
end

function module.BuildEditPanel(parent)
  local panel = CreateFrame("Frame", nil, parent)
  panel:SetHeight(120)
  local inner = WIDTH - PAD * 2
  panel.beta = Text(panel, "general", { 1, 0.6, 0.2 })
  panel.beta:SetPoint("TOPLEFT", 0, 0)
  panel.beta:SetWidth(inner)
  panel.beta:SetText("BETA - for developer use. What you add is kept on this computer, but this beta "
    .. "client forgets it when the game restarts: press Share before you log out and it reaches us.")
  panel.noteBox = EditBox(panel, inner - 70, "Your tip for this quest")
  panel.noteBox:SetMaxLetters(400)
  panel.noteBox:SetPoint("TOPLEFT", panel.beta, "BOTTOMLEFT", 0, -6)
  panel.saveNote = Button(panel, "Save", function() module.GuideSaveNote(panel.noteBox:GetText()) end)
  panel.saveNote:SetPoint("LEFT", panel.noteBox, "RIGHT", 6, 0)
  panel.noteBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    module.GuideSaveNote(self:GetText())
  end)
  panel.pointBox = EditBox(panel, inner, "Label for the next point (optional): \"up the ramp\"")
  panel.pointBox:SetMaxLetters(60)
  panel.pointBox:SetPoint("TOPLEFT", panel.noteBox, "BOTTOMLEFT", 0, -8)
  panel.pointBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    module.GuideAddPoint(self:GetText())
  end)
  panel.add = Button(panel, "Add point here", function() module.GuideAddPoint(panel.pointBox:GetText()) end)
  panel.add:SetPoint("TOPLEFT", panel.pointBox, "BOTTOMLEFT", 0, -6)
  panel.undo = Button(panel, "Undo point", function() module.GuideUndoPoint() end)
  panel.undo:SetPoint("LEFT", panel.add, "RIGHT", 6, 0)
  panel.clear = Button(panel, "Clear route", function() module.GuideClearRoute() end)
  panel.clear:SetPoint("LEFT", panel.undo, "RIGHT", 6, 0)
  panel.share = Button(panel, "Share", function() if ns.ShareWithForeverUI then ns.ShareWithForeverUI() end end)
  panel.share:SetPoint("LEFT", panel.clear, "RIGHT", 6, 0)
  panel.points = Text(panel, "general", DIM)
  panel.points:SetPoint("TOPLEFT", panel.add, "BOTTOMLEFT", 0, -6)
  panel.points:SetWidth(inner)
  panel:Hide()
  return panel
end

function module.GuideSaveNote(text)
  local qf = Helper()
  if not (qf and qf.SetNote and current) then return false end
  qf.SetNote(current, text)
  Say((text or ""):match("%S") and "tip saved. Share (or /fui share) sends it to us." or "tip removed.")
  module.ShowGuide(current, true)
  return true
end

function module.GuideAddPoint(label)
  local qf = Helper()
  if not (qf and qf.AddRoutePoint and current) then return false end
  local point, n = qf.AddRoutePoint(current, label)
  if not point then
    Say("couldn't add a point: " .. tostring(n))
    return false
  end
  Say(("route point %d added where you stand."):format(n))
  if guide and guide.edit then guide.edit.pointBox:SetText("") end
  module.ShowGuide(current, true)
  return true
end

function module.GuideUndoPoint()
  local qf = Helper()
  if qf and qf.UndoRoutePoint and current and qf.UndoRoutePoint(current) then
    module.ShowGuide(current, true)
    return true
  end
  Say("no route point of yours to take back.")
  return false
end

function module.GuideClearRoute()
  local qf = Helper()
  if qf and qf.ClearRoute and current and qf.ClearRoute(current) then
    Say("your route for this quest is cleared.")
    module.ShowGuide(current, true)
    return true
  end
  Say("you have no route of your own on this quest.")
  return false
end

local function PointsText(qf, route)
  local lines = {}
  for i, p in ipairs(route) do
    local where = MapName(p[1])
    lines[#lines + 1] = ("%d.  %s %.1f, %.1f%s"):format(i, where or ("map " .. tostring(p[1])),
      p[2] * 100, p[3] * 100, (p[4] and p[4] ~= "") and ("  -  " .. p[4]) or "")
  end
  return table.concat(lines, "\n")
end

-- NOTE, ROUTE and (when editing) the edit panel, laid out from y down.
function module.PlaceNotes(q, qf, y, inner)
  local note, whose, route, rwhose = nil, nil, {}, nil
  if qf and qf.Note and not q.preview then
    note, whose = qf.Note(q.id)
    route, rwhose = qf.Route(q.id)
  end
  if note then
    guide.noteLabel:SetText(whose == "yours" and "YOUR NOTE" or "NOTE")
    y = Place(guide.noteLabel, y)
    guide.note:SetText(note)
    y = Place(guide.note, y) - 4
  else
    guide.noteLabel:Hide(); guide.note:Hide()
  end
  if #route > 0 then
    y = Place(guide.routeLabel, y)
    local following, index = nil, nil
    if qf.Following then following, index = qf.Following() end
    local walk = following == q.id and ("  -  on point %d"):format(index) or ""
    guide.route:SetText(("%d point%s, walked by %s. The Arrow button follows it.%s"):format(
      #route, #route == 1 and "" or "s", rwhose == "yours" and "you" or "ForeverUI", walk))
    y = Place(guide.route, y) - 4
  else
    guide.routeLabel:Hide(); guide.route:Hide()
  end
  local panel = guide.edit
  if guide.editing and qf and qf.SetNote and not q.preview then
    if not panel.noteBox:HasFocus() then
      local mine = qf.Store and qf.Store("notes")[q.id]
      panel.noteBox:SetText(mine or "")
    end
    panel.points:SetText(#route > 0 and PointsText(qf, route)
      or "Walk the way you'd tell a friend to go, and add a point at each turn.")
    local pointsH = math.ceil(panel.points:GetStringHeight() or 14)
    local betaH = math.ceil(panel.beta:GetStringHeight() or 28)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", 0, y)
    panel:SetWidth(inner)
    panel:SetHeight(betaH + 6 + 22 + 8 + 22 + 6 + 22 + 6 + pointsH)
    panel:Show()
    y = y - panel:GetHeight() - 8
  else
    panel:Hide()
  end
  return y
end

-- Show (or refresh) the guide for a quest. `quiet`: a refresh, not a click.
function module.ShowGuide(questID, quiet)
  if not guide then Build() end
  -- A quest you haven't picked up yet (from the quest line or the tracker's
  -- Next tab) is shown as a preview: who gives it, and its line.
  local q = FromLog(questID) or Preview(questID)
  if not q then
    if not quiet then Say("that quest isn't in your log any more.") end
    guide:Hide()
    return false
  end
  current = questID
  if not quiet and not guide:IsShown() then
    guide:ClearAllPoints()
    if module.list and module.list:IsShown() then
      guide:SetPoint("TOPRIGHT", module.list, "TOPLEFT", -8, 0)
    else
      guide:SetPoint("CENTER", UIParent, "CENTER", -200, 60)
    end
  end
  local inner = WIDTH - PAD * 2
  local y = 0

  guide.title:SetText(((q.level and q.level > 0) and ("[%d] "):format(q.level) or "") .. (q.title or "?"))
  guide.distance:SetText(module.DistanceText and module.DistanceText(q.yards) or "")
  guide.distance:ClearAllPoints()
  guide.distance:SetPoint("TOPRIGHT", 0, y - 2)
  y = Place(guide.title, y, 0, inner - 70)

  local qf = Helper()
  local xp = qf and qf.Quest(q.id) and qf.Quest(q.id).xp
  local subParts = {}
  if q.header then subParts[#subParts + 1] = q.header end
  if xp then subParts[#subParts + 1] = ("%d xp"):format(xp) end
  if q.complete then subParts[#subParts + 1] = "|cff59d966complete|r" end
  if q.preview then
    local rec = qf and qf.Quest(q.id)
    local place = rec and qf.StartPlaces and qf.StartPlaces(rec)[1]
    subParts[#subParts + 1] = place and place[4] and ("not in your log - from %s"):format(place[4])
      or "not in your log"
  end
  guide.sub:SetText(table.concat(subParts, "  -  "))
  y = Place(guide.sub, y) - 4
  local pos = qf and qf.ChainPosition and qf.ChainPosition(q.id)
  if pos then
    guide.chainLink.text:SetText(("|cffffd100Quest line:|r step %d of %d  -  |cff4dc3ffsee the whole chain|r")
      :format(pos.step, pos.total))
    guide.chainLink:ClearAllPoints()
    guide.chainLink:SetPoint("TOPLEFT", 0, y)
    guide.chainLink:SetWidth(inner)
    guide.chainLink:Show()
    y = y - 22
  else
    guide.chainLink:Hide()
  end
  if q.preview then
    guide.goalLabel:Hide(); guide.goal:Hide(); guide.stepsLabel:Hide(); guide.none:Hide()
    guide.doneLabel:Hide(); guide.done:Hide()
    for _, row in ipairs(stepRows) do row:Hide() end
  end

  local goal = (not q.preview) and Goal(q)
  if goal then
    y = Place(guide.goalLabel, y)
    guide.goal:SetText(goal)
    y = Place(guide.goal, y) - 6
  else
    guide.goalLabel:Hide(); guide.goal:Hide()
  end

  -- A preview has no steps of its own: QuestForever knows it, so no hint.
  local fromHelper = true
  if not q.preview then
  y = Place(guide.stepsLabel, y)
  local steps
  steps, fromHelper = Steps(q)
  local shown = 0
  for i, step in ipairs(steps) do
    local row = StepRow(i)
    row.step = step
    row.num:SetText(step.done and "|cff59d966v|r" or tostring(i))
    local progress = step.progress and step.progress:match("(%d+%s*/%s*%d+)") or ""
    row.progress:SetText(progress)
    row.text:SetText(step.text or "?")
    local c = step.done and DIM or { 0.92, 0.92, 0.94 }
    row.text:SetTextColor(c[1], c[2], c[3])
    local h = math.max(18, math.ceil(row.text:GetStringHeight() or 14) + 6)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, y)
    row:SetSize(inner, h)
    row:Show()
    y = y - h
    shown = i
  end
  for i = shown + 1, #stepRows do stepRows[i]:Hide() end
  if shown == 0 then
    guide.none:SetText(q.complete and "Nothing left to do - just hand it in." or "The game lists no objectives for this one.")
    y = Place(guide.none, y)
  else
    guide.none:Hide()
  end
  y = y - 6

  local handIn = HandInLine(q)
  if handIn then
    y = Place(guide.doneLabel, y)
    guide.done:SetText(handIn)
    local c = q.complete and GREEN or { 0.92, 0.92, 0.94 }
    guide.done:SetTextColor(c[1], c[2], c[3])
    y = Place(guide.done, y) - 4
  else
    guide.doneLabel:Hide(); guide.done:Hide()
  end
  end   -- not a preview

  y = module.PlaceNotes(q, qf, y, inner)

  -- The line this quest belongs to, when there is more than this one step.
  local line = (qf and qf.Chain) and qf.Chain(q.id) or {}
  local drawn = 0
  if #line > 1 then
    y = Place(guide.lineLabel, y)
    for i, step in ipairs(line) do
      if i > LINE_ROWS then break end
      local row = LineRow(i)
      row.step = step
      local indent = math.min(step.depth or 0, 6) * 10
      local name = ((step.level or 0) > 0 and ("[%d] "):format(step.level) or "") .. (step.name or "?")
      if step.current then name = "|cffffd100" .. name .. "|r" end
      row.text:ClearAllPoints()
      row.text:SetPoint("TOPLEFT", 2 + indent, -2)
      row.text:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
      row.text:SetText((ICON[step.status] or "") .. " " .. name)
      local dim = step.status == "done" or step.status == "closed" or step.status == "later"
      local c = dim and DIM or { 0.92, 0.92, 0.94 }
      if step.current then c = { 1, 1, 1 } end
      row.text:SetTextColor(c[1], c[2], c[3])
      row.status:SetText(module.LineStatus(step))
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 0, y)
      row:SetSize(inner, 18)
      row:Show()
      y = y - 18
      drawn = i
    end
    if #line > LINE_ROWS then
      guide.lineMore:SetText(("+ %d more steps in this line"):format(#line - LINE_ROWS))
      y = Place(guide.lineMore, y)
    else
      guide.lineMore:Hide()
    end
    y = y - 6
  else
    guide.lineLabel:Hide(); guide.lineMore:Hide()
  end
  for i = drawn + 1, #lineRows do lineRows[i]:Hide() end

  if not fromHelper then
    guide.hint:SetText("Switch on QuestForever (/fui qf) for who to kill, what drops what, and where.")
    y = Place(guide.hint, y)
  else
    guide.hint:Hide()
  end

  -- Everyone's, marked BETA (owner, 27 Sept 2026: "a beta field of some
  -- kind that says for developer use only"). What players make comes back
  -- through Share and is folded in by hand (tools/quest_curate.lua).
  if qf and qf.SetNote and not q.preview then
    guide.editLink.text:SetText(guide.editing and "Done editing the tip and route"
      or "Add a tip or a route for this quest  |cffff9933BETA - for developer use|r")
    guide.editLink:ClearAllPoints()
    guide.editLink:SetPoint("TOPLEFT", 0, y - 2)
    guide.editLink:SetWidth(inner)
    guide.editLink:Show()
    y = y - 20
  else
    guide.editLink:Hide()
  end

  module.PaintAutoLine()
  guide.auto:ClearAllPoints()
  guide.auto:SetPoint("TOPLEFT", 0, y - 2)
  guide.auto:SetWidth(inner)
  y = y - 22

  guide.body:SetHeight(-y)
  guide:SetHeight(40 + (-y) + 22 + PAD * 2)
  guide:Show()
  return true
end

-- Whether the guide opens by itself on a quest you pick up. Two switches:
-- one for keyboard and mouse (on unless turned off) and one for the
-- controller (off unless turned on) -- with a pad the guide is a window you
-- can't close with B, popping up over the game at every quest giver
-- (Altiokis on CurseForge, 2 Oct 2026). Whichever matches how you are
-- playing right now is the one read and the one changed.
local function PadNow()
  return (ns.GamepadUIActive and ns.GamepadUIActive()) or (ns.ControllerActive and ns.ControllerActive()) or false
end
function module.AutoGuideKey()
  return PadNow() and "guideOnAcceptPad" or "guideOnAccept"
end
function module.AutoGuideOn()
  local s = ns.db and ns.db.modules and ns.db.modules.Quests
  if not s then return false end
  if module.AutoGuideKey() == "guideOnAcceptPad" then return s.guideOnAcceptPad == true end
  return s.guideOnAccept ~= false
end

function module.PaintAutoLine()
  if not guide then return end
  local on = module.AutoGuideOn()
  local fmt = PadNow() and "Opens when you pick up a quest (controller): %s  (click to change)"
    or "Opens when you pick up a quest: %s  (click to change)"
  guide.auto.text:SetText(fmt:format(on and "on" or "off"))
end

-- Pick a quest up and the guide opens on it. QUEST_ACCEPTED carries the
-- quest ID first on some clients and second (after the log index) on
-- others, so whichever of the two is in the log is the one. A moment's
-- wait: the log can lag the event.
local acceptWatcher = CreateFrame("Frame")
acceptWatcher:RegisterEvent("QUEST_ACCEPTED")
acceptWatcher:SetScript("OnEvent", function(_, _, a, b)
  local s = ns.db and ns.db.modules and ns.db.modules.Quests
  if not (s and module.AutoGuideOn() and s.ownList ~= false and ns.IsModuleEnabled("Quests")) then return end
  local function Open()
    for _, id in pairs({ b or false, a or false }) do   -- not ipairs: b is often nil
      if type(id) == "number" and not (issecretvalue and issecretvalue(id)) and FromLog(id) then
        module.ShowGuide(id)
        return
      end
    end
  end
  if C_Timer and C_Timer.After then C_Timer.After(0.3, Open) else Open() end
end)
module.acceptWatcher = acceptWatcher

function module.HideGuide()
  if guide then guide:Hide() end
  current = nil
end

function module.GuideShown()
  return guide ~= nil and guide:IsShown(), current
end
