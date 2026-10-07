local _, ns = ...

-- The Quests page, from the owner's mock-up (23 Sept 2026): one parchment
-- sheet titled Quest Tracker with Reset to Default; the quest list's switches
-- across the top beside a painted scroll; then how the tracker looks and its
-- text down the left, and a live preview of your own quests, a tip and the
-- quest-log buttons down the right.
--
-- Every checkbox and slider here is the options window's own (ns.OptionsKit),
-- so it looks, saves and refreshes exactly like every other page.

local W = 636
local IN = 14                      -- inset inside the sheet
local LEFT_W = 370
local RIGHT_X = IN + LEFT_W + 12
local RIGHT_W = W - RIGHT_X - IN

local HEAD_FILL = { 0.27, 0.17, 0.08, 0.88 }
local HEAD_TEXT = { 0.96, 0.89, 0.72 }
local HEAD_DESC = { 0.86, 0.78, 0.62 }
local QUEST_GOLD = { 1.00, 0.82, 0.20 }
local READY = { 0.45, 0.85, 0.40 }

local page = {}

local function Module()
  return ns.GetModule("Quests")
end

local function Settings()
  return ns.db.modules.Quests
end

local function Text(parent, size, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(ns.Media.Role("general"), size, "")
  fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetShadowColor(0, 0, 0, 0)
  return fs
end

-- A card on the sheet: a thin ink edge and a dark header strip with a title
-- (and a line under it), the sheet's own parchment showing through below.
local function Card(parent, x, y, w, h, title, desc)
  local kit = ns.OptionsKit
  local card = CreateFrame("Frame", nil, parent)
  card:SetSize(w, h)
  card:SetPoint("TOPLEFT", x, y)
  card.isParchment = true
  ns.Skin.Panel(card, { color = { 0, 0, 0, 0 }, borderColor = kit.INK_EDGE })
  local head = card:CreateTexture(nil, "BACKGROUND", nil, 1)
  head:SetPoint("TOPLEFT", 1, -1)
  head:SetPoint("TOPRIGHT", -1, -1)
  head:SetHeight(desc and 44 or 30)
  head:SetColorTexture(HEAD_FILL[1], HEAD_FILL[2], HEAD_FILL[3], HEAD_FILL[4])
  local label = Text(card, 16, HEAD_TEXT)
  kit.BigFont(label, 16)
  label:SetTextColor(HEAD_TEXT[1], HEAD_TEXT[2], HEAD_TEXT[3])
  label:SetPoint("TOPLEFT", 12, -7)
  label:SetText(title)
  if desc then
    local line = Text(card, 11, HEAD_DESC)
    line:SetPoint("TOPLEFT", 12, -27)
    line:SetText(desc)
  end
  card.top = desc and -52 or -38   -- where the first row goes
  return card
end

-- One of the options window's own rows, bound to the Quests settings.
local function Row(card, kind, y, entry)
  local kit = ns.OptionsKit
  entry.moduleName = "Quests"
  entry.type = kind
  if kind == "checkbox" then
    kit.MakeCheckbox(card, entry, y, 12)
  elseif kind == "slider" then
    entry.type, entry.slider, entry.sliderWidth = "stepper", true, entry.sliderWidth or 160
    kit.MakeStepper(card, entry, y, 12, 10)
  end
  page.entries[#page.entries + 1] = entry
  return y - kit.RowHeight(entry)
end

---------------------------------------------------------------------------
-- The preview: your own quests, as the tracker would list them
---------------------------------------------------------------------------

local SAMPLE = {
  { title = "A Brighter Tomorrow", line = "0/8 Sunblossom" },
  { title = "Voices in the Wind", complete = true },
  { title = "The Lost Expedition", line = "Speak with Ranger Kael" },
}

local function PreviewQuests()
  local module = Module()
  local ok, quests = pcall(function() return module.FilteredQuests and module.FilteredQuests() end)
  local out = {}
  for _, q in ipairs(ok and type(quests) == "table" and quests or {}) do
    local first = q.objectives and q.objectives[1]
    out[#out + 1] = { title = q.title, complete = q.complete, line = first and first.text or "" }
  end
  return #out > 0 and out or SAMPLE, #out > 0
end

local function BuildPreview(parent, x, y, w)
  local box = CreateFrame("Frame", nil, parent)
  box:SetSize(w, 206)
  box:SetPoint("TOPLEFT", x, y)
  ns.Skin.Panel(box, { color = { 0.06, 0.05, 0.07, 0.94 }, borderColor = ns.OptionsKit.INK_EDGE })
  local title = Text(box, 16, HEAD_TEXT)
  ns.OptionsKit.BigFont(title, 16)
  title:SetTextColor(HEAD_TEXT[1], HEAD_TEXT[2], HEAD_TEXT[3])
  title:SetPoint("TOPLEFT", 12, -8)
  title:SetText("Preview")

  local list = CreateFrame("Frame", nil, box)
  list:SetPoint("TOPLEFT", 8, -34)
  list:SetPoint("BOTTOMRIGHT", -8, 8)
  ns.Skin.Panel(list, { color = { 0.10, 0.08, 0.09, 1 }, borderColor = { 0.45, 0.34, 0.18, 1 } })
  local bar = Text(list, 13, QUEST_GOLD)
  bar:SetPoint("TOPLEFT", 10, -7)
  page.previewCount = bar
  local arrow = ns.Skin.Icon(list, "plus", 12, QUEST_GOLD)
  arrow:SetPoint("TOPRIGHT", -8, -8)
  page.previewArrow = arrow

  page.previewRows = {}
  for i = 1, 3 do
    local mark = Text(list, 18, QUEST_GOLD, "CENTER")
    mark:SetSize(16, 20)
    mark:SetPoint("TOPLEFT", 8, -30 - (i - 1) * 44)
    local name = Text(list, 12, QUEST_GOLD)
    name:SetPoint("TOPLEFT", 30, -30 - (i - 1) * 44)
    name:SetPoint("RIGHT", list, "RIGHT", -8, 0)
    local line = Text(list, 11, { 0.86, 0.84, 0.80 })
    line:SetPoint("TOPLEFT", 30, -46 - (i - 1) * 44)
    line:SetPoint("RIGHT", list, "RIGHT", -8, 0)
    page.previewRows[i] = { mark = mark, name = name, line = line }
  end
  return box
end

local function PaintPreview()
  if not page.previewRows then
    return
  end
  local quests, real = PreviewQuests()
  local collapsed = Settings().collapsed
  page.previewCount:SetText(("Quests (%d)%s"):format(#quests, real and "" or "  - example"))
  for i, row in ipairs(page.previewRows) do
    local q = not collapsed and quests[i]
    if q then
      row.mark:SetText(q.complete and "?" or "!")
      row.name:SetText(q.title)
      if q.complete then
        row.line:SetText("Ready for turn-in")
        row.line:SetTextColor(READY[1], READY[2], READY[3])
      else
        row.line:SetText(q.line or "")
        row.line:SetTextColor(0.86, 0.84, 0.80)
      end
    else
      row.mark:SetText("")
      row.name:SetText("")
      row.line:SetText("")
    end
  end
end

---------------------------------------------------------------------------
-- Reset to Default
---------------------------------------------------------------------------

-- These only take effect after a reload, so resetting one asks for it.
local RELOAD_KEYS = { ownList = true, strip = true, restyleText = true }

function ns.ResetQuestSettings()
  local module = Module()
  local settings = Settings()
  local reload = false
  for key, value in pairs(module.defaults) do
    if RELOAD_KEYS[key] and settings[key] ~= value then
      reload = true
    end
    settings[key] = value
  end
  if module.Refresh then module:Refresh() end
  if ns.RefreshOptions then ns.RefreshOptions() end
  if reload and ns.RequestReload then
    ns.RequestReload("Quest tracker defaults")
  end
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local function Refresh()
  for _, entry in ipairs(page.entries or {}) do
    entry.refresh()
  end
  PaintPreview()
end

local function Build(parent, x, y)
  local kit = ns.OptionsKit
  page = { entries = {} }
  local sheet = CreateFrame("Frame", nil, parent)
  sheet:SetPoint("TOPLEFT", x, y)
  sheet:SetSize(W, 100)
  sheet.isParchment = true
  kit.Parchment(sheet)
  page.sheet = sheet

  local title = Text(sheet, 20, kit.INK)
  kit.BigFont(title, 20)
  title:SetTextColor(kit.INK[1], kit.INK[2], kit.INK[3])
  title:SetPoint("TOPLEFT", IN, -12)
  title:SetText("Quest Tracker")
  local sub = Text(sheet, 12, kit.INK_DIM)
  sub:SetPoint("TOPLEFT", IN, -38)
  sub:SetText("Configure how quests are displayed and tracked.")
  local reset = kit.Button(sheet, 150, "Reset to Default", function() ns.ResetQuestSettings() end)
  reset:SetHeight(26)
  reset:SetPoint("TOPRIGHT", -IN, -14)
  page.reset = reset

  -- The quest list, full width, with the painted scroll on its right.
  local listCard = Card(sheet, IN, -66, W - 2 * IN, 190, "Quest List")
  local art = listCard:CreateTexture(nil, "ARTWORK")
  -- ChatGPT's scroll, 512x282 in the top of its texture (1.816:1).
  art:SetSize(212, 117)
  art:SetPoint("TOPRIGHT", -8, -40)
  art:SetTexture(ns.MEDIA_PATH .. "skin\\quest-scroll")
  art:SetTexCoord(0, 1, 0, 282 / 512)
  local ry = listCard.top
  ry = Row(listCard, "checkbox", ry, { key = "ownList", reload = true,
    label = "Use ForeverUI's quest list (tabs, badges, distances)" })
  ry = Row(listCard, "checkbox", ry, { key = "showCompleted", label = "Show completed quests in the list" })
  ry = Row(listCard, "checkbox", ry, { key = "trackedOnly", label = "Only tracked quests",
    desc = "Off: every quest in your log. On: only tracked ones." })
  Row(listCard, "checkbox", ry, { key = "hide", label = "Hide the quest tracker",
    desc = "Completely hide the on-screen quest tracker." })

  -- Left: how it looks, its text, which quests.
  local top = -66 - 190 - 12
  local look = Card(sheet, IN, top, LEFT_W, 296, "Tracker Appearance",
    "Adjust the size, position, and style of the quest tracker.")
  local ly = look.top
  ly = Row(look, "slider", ly, { key = "width", label = "Width", min = 160, max = 480, step = 10 })
  ly = Row(look, "slider", ly, { key = "height", label = "Height", min = 120, max = 700, step = 20 })
  ly = Row(look, "checkbox", ly, { key = "showHeader", label = "Show the header bar",
    desc = "Display the \"Quests\" title bar." })
  ly = Row(look, "checkbox", ly, { key = "strip", reload = true, label = "Strip Blizzard's headers and artwork",
    desc = "Use a cleaner, modern look." })
  ly = Row(look, "checkbox", ly, { key = "restyleText", reload = true, label = "Use ForeverUI's font",
    desc = "Apply the ForeverUI font to quest text." })
  Row(look, "checkbox", ly, { key = "autoHeight", label = "Fit the panel to the list",
    desc = "The panel grows and shrinks with the list." })

  local textTop = top - 296 - 12
  local styling = Card(sheet, IN, textTop, LEFT_W, 120, "Text Styling",
    "Control the font size and background transparency.")
  local sy = styling.top
  sy = Row(styling, "slider", sy, { key = "fontSize", label = "Text size", min = 8, max = 20, step = 1 })
  Row(styling, "slider", sy, { key = "opacity", label = "Background", min = 0, max = 100, step = 5,
    format = function(v) return ("%d%%"):format(v or 0) end })

  local whichTop = textTop - 120 - 12
  local which = Card(sheet, IN, whichTop, LEFT_W, 210, "Which Quests",
    "Keep the tracker short: the nearest few, the rest in the log.")
  local wy = which.top
  wy = Row(which, "checkbox", wy, { key = "nearbyOnly", label = "Track only the nearest quests",
    desc = "The closest ones stay on screen." })
  wy = Row(which, "slider", wy, { key = "maxShown", label = "How many", min = 3, max = 20, step = 1 })
  -- It only had a slash command (/fui quests guide) before.
  wy = Row(which, "checkbox", wy, { key = "guideOnAccept", label = "Open the quest guide when I pick up a quest",
    desc = "Click any quest in the list to open it yourself." })
  Row(which, "checkbox", wy, { key = "guideOnAcceptPad", label = "...also with a controller" })

  -- Right: the preview, a tip, the quest-log buttons.
  BuildPreview(sheet, RIGHT_X, top, RIGHT_W)

  local tipTop = top - 206 - 12
  local tip = CreateFrame("Frame", nil, sheet)
  tip:SetSize(RIGHT_W, 132)
  tip:SetPoint("TOPLEFT", RIGHT_X, tipTop)
  tip.isParchment = true
  ns.Skin.Panel(tip, { color = { 0, 0, 0, 0 }, borderColor = kit.INK_EDGE })
  local info = ns.Skin.Icon(tip, "info", 18, kit.INK_ICON)
  info:SetPoint("TOPLEFT", 10, -10)
  local tipHead = Text(tip, 14, kit.INK_ICON)
  tipHead:SetPoint("LEFT", info, "RIGHT", 6, 0)
  tipHead:SetText("Tip:")
  local tipText = Text(tip, 11, kit.INK_DIM)
  tipText:SetPoint("TOPLEFT", 12, -34)
  tipText:SetPoint("RIGHT", tip, "RIGHT", -10, 0)
  tipText:SetText("The tracker keeps the nearest few quests on screen; the rest stay in the quest log. "
    .. "Suggestions list low-level or far-off quests you could abandon -- it never drops one for you.\n\n"
    .. "Move it with /fui move, or Move frames on Quick Setup.")

  local logTop = tipTop - 132 - 12
  local log = Card(sheet, RIGHT_X, logTop, RIGHT_W, 134, "Quest Log")
  local buttons = {
    { "Open the quest log", function() Module().OpenLog() end },
    { "Suggest quests to drop", function() Module().SuggestPrune() end },
    { "", function() Module().ToggleCollapsed() end },
  }
  for i, spec in ipairs(buttons) do
    local button = kit.Button(log, RIGHT_W - 24, spec[1], spec[2])
    button:SetHeight(24)
    button:SetPoint("TOPLEFT", 12, -40 - (i - 1) * 30)
    if i == 3 then page.rollButton = button end
  end

  local height = -(whichTop - 210) + IN
  sheet:SetHeight(height)
  Refresh()
  return height
end

function ns.QuestsPageSchema()
  return {
    { type = "heading", label = "Quests", subtitle = "Customize your quest experience." },
    { type = "custom", bare = true, build = Build,
      refresh = function()
        Refresh()
        if page.rollButton then
          page.rollButton:SetText(Settings().collapsed and "Roll the list down" or "Roll the list up")
        end
      end },
  }
end
