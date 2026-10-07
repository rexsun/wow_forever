-- QuestForever on its own, without ForeverUI.
--
-- With ForeverUI installed, ForeverUI is this addon's load manager (see the
-- TOC): it loads QuestForever when its quest helper is switched on and hands
-- over its settings, and nothing here runs. Without ForeverUI the game loads
-- QuestForever at login, and this starts it with settings of its own and a
-- slash command:
--   /qf          its settings window (CurseForge, 28 Sept 2026: "/qf ... didn't
--                bring settings menu up, it only turned the addon off")
--   /qf on|off   switch it on or off
--   /qf export   the places it learned, to copy and send in

local QF = QuestForever

local function OwnSettings()
  QuestForeverDB = type(QuestForeverDB) == "table" and QuestForeverDB or {}
  local db = QuestForeverDB
  if db.enabled == nil then db.enabled = true end
  return db
end

local function Say(text)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7QuestForever|r: " .. text) end
end

local function ForeverUIPresent()
  return _G.ForeverUI ~= nil
end

-- A plain box to copy the export from.
local box
local function ShowText(text)
  if not box then
    box = CreateFrame("Frame", "QuestForeverExport", UIParent, "BackdropTemplate")
    box:SetSize(520, 300)
    box:SetPoint("CENTER")
    box:SetFrameStrata("DIALOG")
    if box.SetBackdrop then
      box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
      box:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
      box:SetBackdropBorderColor(0.3, 0.76, 1, 1)
    end
    box:EnableMouse(true)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -12)
    scroll:SetPoint("BOTTOMRIGHT", -32, 40)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(470)
    edit:SetAutoFocus(true)
    edit:SetScript("OnEscapePressed", function() box:Hide() end)
    scroll:SetScrollChild(edit)
    box.edit = edit
    local close = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    close:SetSize(100, 22)
    close:SetPoint("BOTTOM", 0, 10)
    close:SetText(CLOSE or "Close")
    close:SetScript("OnClick", function() box:Hide() end)
  end
  box.edit:SetText(text)
  box.edit:HighlightText()
  box:Show()
end
QF.ShowText = ShowText

-- The settings window: the same choices ForeverUI's quest helper page has,
-- built from the game's plain templates so nothing here needs ForeverUI.
local OPTIONS = {
  { head = "What it shows" },
  { key = "showAvailable", label = "\"!\" where you can pick a quest up" },
  { key = "showTurnIns", label = "\"?\" where you hand a finished quest in" },
  { key = "showObjectives", label = "Dots where your quests' mobs, items and objects are" },
  { key = "showUnfinished", label = "A grey \"?\" for quests not finished yet" },
  { key = "showItemStarts", label = "Where items that start a quest drop" },
  { key = "showPaths", label = "Routes of escorts and patrolling targets" },
  { key = "tooltips", label = "Quest lines on mobs', NPCs' and objects' tooltips" },
  { key = "onWorldMap", label = "On the world map" },
  { key = "onMinimap", label = "On the minimap" },
  { head = "Which quests" },
  { key = "hideTrivial", label = "Hide quests far below your level" },
  { key = "showRepeatable", label = "Show repeatable quests" },
  { key = "showProfession", label = "Show profession quests" },
  { key = "levelsAhead", label = "Also show quests this many levels too high", min = 0, max = 5, step = 1 },
  { key = "iconSize", label = "Icon size", min = 10, max = 28, step = 2 },
  { head = "Filling the gaps" },
  { key = "learn", label = "Remember quest givers the data doesn't know" },
}

local window
local function Value(db, key)
  local v = db[key]
  if v == nil then v = QF.DEFAULTS[key] end
  return v
end

local function Label(parent, text, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
  fs:SetText(text)
  fs:SetJustifyH("LEFT")
  return fs
end

local function Changed()
  if QF.running then QF.Refresh() end
end

local function Paint(db)
  if not window then return end
  for _, c in ipairs(window.checks) do c:SetChecked(Value(db, c.key) and true or false) end
  for _, s in ipairs(window.steppers) do s.value:SetText(tostring(Value(db, s.key))) end
  window.power:SetText(db.enabled and "Switch off" or "Switch on")
  window.state:SetText(db.enabled and "|cff7fff7fOn|r" or "|cffff7f7fOff|r")
end

local function ShowOptions(db, switch, export)
  if not window then
    local w = CreateFrame("Frame", "QuestForeverOptions", UIParent, "BackdropTemplate")
    window = w
    w:SetSize(420, 520)
    w:SetPoint("CENTER")
    w:SetFrameStrata("FULLSCREEN_DIALOG")   -- above the game's Options, which can open it
    w:SetClampedToScreen(true)
    w:EnableMouse(true)
    w:SetMovable(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    if w.SetBackdrop then
      w:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
      w:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
      w:SetBackdropBorderColor(0.3, 0.76, 1, 1)
    end
    if UISpecialFrames then table.insert(UISpecialFrames, "QuestForeverOptions") end   -- Escape closes it

    local title = Label(w, "QuestForever", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    w.state = Label(w, "")
    w.state:SetPoint("LEFT", title, "RIGHT", 10, 0)
    local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    w.checks, w.steppers = {}, {}
    local y = -44
    for _, o in ipairs(OPTIONS) do
      if o.head then
        local h = Label(w, o.head, "GameFontNormal")
        h:SetPoint("TOPLEFT", 16, y - 4)
        y = y - 24
      elseif o.min then
        local s = { key = o.key }
        local text = Label(w, o.label)
        text:SetPoint("TOPLEFT", 22, y - 5)
        local minus = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        minus:SetSize(22, 20)
        minus:SetText("-")
        minus:SetPoint("TOPRIGHT", -70, y)
        s.value = Label(w, "")
        s.value:SetPoint("LEFT", minus, "RIGHT", 6, 0)
        local plus = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        plus:SetSize(22, 20)
        plus:SetText("+")
        plus:SetPoint("TOPRIGHT", -16, y)
        local function Step(by)
          local v = math.max(o.min, math.min(o.max, (tonumber(Value(db, o.key)) or o.min) + by))
          db[o.key] = v
          Paint(db)
          Changed()
        end
        minus:SetScript("OnClick", function() Step(-o.step) end)
        plus:SetScript("OnClick", function() Step(o.step) end)
        w.steppers[#w.steppers + 1] = s
        y = y - 24
      else
        local c = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
        c:SetSize(24, 24)
        c:SetPoint("TOPLEFT", 16, y)
        c.key = o.key
        local text = Label(w, o.label)
        text:SetPoint("LEFT", c, "RIGHT", 4, 0)
        c:SetScript("OnClick", function(self)
          db[o.key] = self:GetChecked() and true or false
          Changed()
        end)
        w.checks[#w.checks + 1] = c
        y = y - 24
      end
    end

    w.power = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    w.power:SetSize(120, 22)
    w.power:SetPoint("BOTTOMLEFT", 16, 14)
    w.power:SetScript("OnClick", function() switch(not db.enabled); Paint(db) end)
    local share = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    share:SetSize(160, 22)
    share:SetPoint("BOTTOMRIGHT", -16, 14)
    share:SetText("Share what it found")
    share:SetScript("OnClick", export)
    w:SetHeight(-y + 60)
  end
  Paint(db)
  window:Show()
end
QF.ShowOptions = function() if window then window:Show() end end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function()
  if ForeverUIPresent() then return end
  QF.standalone = true
  local db = OwnSettings()
  if db.enabled then QF.Start(function() return db end) end

  SLASH_QUESTFOREVER1 = "/qf"
  SLASH_QUESTFOREVER2 = "/questforever"
  local function Switch(on)
    db.enabled = on
    if on then
      QF.Start(function() return db end)
      Say("on. Quest givers, hand-ins and objectives on your map and minimap.")
    else
      QF.Stop()
      Say("off. /qf on (or the button in /qf) puts it back.")
    end
  end
  local function Export()
    local text, n = QF.ExportLearned()
    if QF.ExportEdits then
      local edits, e = QF.ExportEdits()
      if e > 0 then text, n = (n > 0 and (text .. "\n") or "") .. edits, n + e end
    end
    if n == 0 then
      Say("nothing learned yet - pick up a quest the map doesn't show and it will be.")
    else
      ShowText("Open https://ispress.de/foreverui/share/ and paste this there:\n\n" .. text)
    end
  end
  SlashCmdList.QUESTFOREVER = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "export" then
      Export()
    elseif msg == "on" or msg == "off" then
      Switch(msg == "on")
      Paint(db)
    elseif msg == "toggle" then
      Switch(not db.enabled)
      Paint(db)
    else
      ShowOptions(db, Switch, Export)
    end
  end

  -- And in the game's Options > AddOns list, where people look first.
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    pcall(function()
      local page = CreateFrame("Frame")
      local head = Label(page, "QuestForever", "GameFontNormalLarge")
      head:SetPoint("TOPLEFT", 16, -16)
      local text = Label(page, "Its settings are in a window of their own. Type /qf, or:")
      text:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -10)
      local open = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
      open:SetSize(200, 24)
      open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -10)
      open:SetText("Open QuestForever settings")
      open:SetScript("OnClick", function() ShowOptions(db, Switch, Export) end)
      Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(page, "QuestForever"))
    end)
  end
end)
