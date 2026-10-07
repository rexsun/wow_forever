local _, ns = ...

-- The Modules page, from the owner's mock-up: every module as a row with a
-- switch and a gear, a preview of the one you are pointing at, the loadouts
-- as pickable cards, and the profile you are working in -- all on one page.
--
-- The rows are built once and repainted, rather than rebuilt: a module can be
-- switched on or off many times in a sitting, and rebuilding the page each
-- time loses the scroll position and the hover.

local W = 636                       -- the painted board's usable width
local LIST_W, GAP = 372, 12
local SIDE_W = W - LIST_W - GAP
local ROW_H = 46

local ACCENT = { 0.74, 0.58, 1.00 }
local TEXT   = { 0.92, 0.92, 0.94 }
local DIM    = { 0.70, 0.66, 0.60 }
local EDGE   = { 0.66, 0.50, 0.26, 1 }
local FILL   = { 0.06, 0.05, 0.07, 0.90 }
local ROW_BG = { 1, 1, 1, 0.03 }

-- What each module is, in one line. The module files do not carry a
-- description of their own, and a page that just lists names tells a new
-- player nothing.
local ABOUT = {
  ActionBars  = { icon = "actionbars", title = "Action Bars",   desc = "Up to four bars, keybinding by hover." },
  UnitFrames  = { icon = "unitframes", title = "Unit Frames",   desc = "Player, target, target of target, pet and focus." },
  Frames      = { icon = "heal",       title = "Party & Raid",  desc = "Click-cast grids for healing, tanking and damage." },
  CastBar     = { icon = "castbar",    title = "Cast Bar",      desc = "Your casts, where you want them." },
  Minimap     = { icon = "minimap",    title = "Minimap",       desc = "A square map, coordinates and a button bar." },
  Nameplates  = { icon = "nameplates", title = "Nameplates",    desc = "Flat plates over enemies, with cast bars." },
  Quests      = { icon = "quests",     title = "Quest Tracker", desc = "The tracker in a panel that fits its list." },
  Chat        = { icon = "chat",       title = "Chat",          desc = "One square box, emoji, and copy." },
  Bags        = { icon = "bags",       title = "Bags",          desc = "Every bag in one window." },
  MicroBar    = { icon = "microbar",   title = "Micro Bar",     desc = "Character, spells, talents and the rest as tiles." },
  XPBar       = { icon = "xpbar",      title = "XP Bar",        desc = "A thin line instead of a framed strip." },
  Arrow       = { icon = "map",        title = "Waypoint Arrow", desc = "Points the way to your quest or map pin." },
  Tooltips    = { icon = "info",       title = "Tooltips",      desc = "Unit tooltips always, out of combat, or never." },
}

local page, rows = {}, {}
ns.modulesPageRows = rows      -- the tests look at the rows

---------------------------------------------------------------------------
-- Drawing helpers
---------------------------------------------------------------------------

-- Shared with the other hand-built pages (GUI.lua); looked up when called,
-- because this file loads before the kit.
local function Text(...) return ns.OptionsKit.PageText(...) end

local function Box(parent, w, h, fill, edge)
  local f = CreateFrame("Frame", nil, parent)
  if w and h then f:SetSize(w, h) end
  ns.Skin.Panel(f, { color = fill or FILL, borderColor = edge or EDGE })
  return f
end

-- A card with a glyph, a title and a line under it.
local function Card(parent, x, y, w, h, icon, title, sub)
  local card = Box(parent, w, h)
  card:SetPoint("TOPLEFT", x, y)
  local glyph = ns.Skin.Icon(card, icon, 14, ACCENT, "OVERLAY")
  glyph:SetPoint("TOPLEFT", 10, -10)
  local head = Text(card, 13, TEXT)
  head:SetPoint("LEFT", glyph, "RIGHT", 8, 0)
  head:SetText(title)
  card.head = head
  if sub then
    local note = Text(card, 10, DIM, "RIGHT")
    note:SetPoint("TOPRIGHT", -10, -13)
    note:SetText(sub)
    card.note = note
  end
  return card
end

---------------------------------------------------------------------------
-- The module rows
---------------------------------------------------------------------------

local function ShowPreview(name)
  if not page.preview then
    return
  end
  local about = ABOUT[name] or { icon = "general", title = name, desc = "" }
  ns.Skin.SetIcon(page.preview.glyph, about.icon, ACCENT)
  page.preview.title:SetText(about.title)
  page.preview.desc:SetText(about.desc)
  page.preview.state:SetText(ns.IsModuleEnabled(name) and "|cff66dd77running|r" or "|cff888888switched off|r")
  page.previewFor = name
end

local function BuildRow(parent, index, name)
  local about = ABOUT[name] or { icon = "general", title = name, desc = "" }
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(LIST_W - 20, ROW_H)
  row:SetPoint("TOPLEFT", 10, -10 - (index - 1) * (ROW_H + 6))
  row.module = name

  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(unpack(ROW_BG))
  row.bg = bg

  local glyph = ns.Skin.Icon(row, about.icon, 20, ACCENT, "ARTWORK")
  glyph:SetPoint("LEFT", 10, 0)
  row.glyph = glyph

  local title = Text(row, 13, TEXT)
  title:SetPoint("TOPLEFT", 42, -7)
  title:SetText(about.title)
  row.title = title

  local desc = Text(row, 10, DIM)
  desc:SetPoint("TOPLEFT", 42, -24)
  desc:SetPoint("RIGHT", row, "RIGHT", -96, 0)
  desc:SetText(about.desc)

  -- The gear opens that module's own page, which is where everything it can
  -- do actually lives.
  local gear = CreateFrame("Button", nil, row)
  gear:SetSize(26, 26)
  gear:SetPoint("RIGHT", -8, 0)
  ns.Skin.Panel(gear, { color = { 0.10, 0.09, 0.13, 1 }, borderColor = { 0.30, 0.26, 0.36, 1 } })
  local cog = ns.Skin.Icon(gear, "general", 14, ACCENT, "OVERLAY")
  cog:SetPoint("CENTER")
  gear:SetScript("OnClick", function()
    -- The party & raid frames have their own window (the Heal / Tank / DPS
    -- rows); there is no "Frames" page, and this used to land on General.
    if name == "Frames" and ns.OpenRoleWindow and ns.Frames and ns.Frames.GetMode then
      ns.OpenRoleWindow(ns.Frames.GetMode())
    else
      ns.OpenOptions(name)
    end
  end)
  gear:SetScript("OnEnter", function(self) ns.Skin.SetBorderColor(self, ACCENT) end)
  gear:SetScript("OnLeave", function(self) ns.Skin.SetBorderColor(self, { 0.30, 0.26, 0.36, 1 }) end)

  local sw = ns.Skin.Switch(row, ACCENT, function(on)
    ns.SetModuleEnabled(name, on)
    ShowPreview(name)
    if ns.RefreshOptions then ns.RefreshOptions() end
  end)
  sw:SetPoint("RIGHT", gear, "LEFT", -10, 0)
  row.switch = sw

  local state = Text(row, 10, DIM)
  state:SetPoint("RIGHT", sw, "LEFT", -6, 0)
  row.state = state

  row:SetScript("OnEnter", function(self)
    self.bg:SetColorTexture(1, 1, 1, 0.07)
    ShowPreview(self.module)
  end)
  row:SetScript("OnLeave", function(self) self.bg:SetColorTexture(unpack(ROW_BG)) end)
  row:SetScript("OnClick", function(self) self.switch:Click() end)
  return row
end

local function BuildList(root)
  local list = Box(root, LIST_W, 0)
  list:SetPoint("TOPLEFT", 0, 0)
  page.list = list

  local index, height = 0, 0
  ns.ForEachModule(function(_, name)
    index = index + 1
    rows[#rows + 1] = BuildRow(list, index, name)
    height = 10 + index * (ROW_H + 6) + 4
  end)
  list:SetHeight(height)
  return height
end

---------------------------------------------------------------------------
-- The side: preview, loadouts, profile
---------------------------------------------------------------------------

local function BuildPreview(root, y)
  local card = Card(root, LIST_W + GAP, y, SIDE_W, 150, "eye", "Module Preview")
  local frame = Box(card, SIDE_W - 20, 96, { 0.04, 0.04, 0.06, 1 }, { 0.26, 0.22, 0.34, 1 })
  frame:SetPoint("TOPLEFT", 10, -34)
  -- The painted backdrop (ChatGPT, docs/art/module-preview.png). Dimmed, so
  -- the glyph and the words on top of it stay the thing you read.
  local art = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
  art:SetPoint("TOPLEFT", 1, -1)
  art:SetPoint("BOTTOMRIGHT", -1, 1)
  art:SetTexture(ns.MEDIA_PATH .. "skin\\module-preview")
  art:SetAlpha(0.85)
  frame.art = art
  local glyph = ns.Skin.Icon(frame, "modules", 26, ACCENT, "OVERLAY")
  glyph:SetPoint("TOPLEFT", 12, -12)
  local title = Text(frame, 13, TEXT)
  title:SetPoint("TOPLEFT", 48, -14)
  local desc = Text(frame, 10, DIM)
  desc:SetPoint("TOPLEFT", 12, -44)
  desc:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
  desc:SetWordWrap(true)
  local state = Text(frame, 10, DIM)
  state:SetPoint("BOTTOMLEFT", 12, 10)
  page.preview = { frame = frame, glyph = glyph, title = title, desc = desc, state = state }
  return 150
end

local function BuildLoadouts(root, y)
  local card = Card(root, LIST_W + GAP, y, SIDE_W, 46 + #ns.LOADOUTS * 40, "modules",
    "Quick Presets", "a set of modules")
  page.loadouts = {}
  for i, loadout in ipairs(ns.LOADOUTS) do
    local b = CreateFrame("Button", nil, card)
    b:SetSize(SIDE_W - 20, 34)
    b:SetPoint("TOPLEFT", 10, -34 - (i - 1) * 40)
    ns.Skin.Panel(b, { color = { 0.09, 0.08, 0.12, 1 }, borderColor = { 0.30, 0.26, 0.36, 1 } })
    local glyph = ns.Skin.Icon(b, loadout.icon, 16, ACCENT, "OVERLAY")
    glyph:SetPoint("LEFT", 8, 0)
    local label = Text(b, 12, TEXT)
    label:SetPoint("LEFT", glyph, "RIGHT", 8, 6)
    label:SetText(loadout.short)
    local note = Text(b, 9, DIM)
    note:SetPoint("LEFT", glyph, "RIGHT", 8, -7)
    note:SetText(loadout.label)
    b.key = loadout.key
    b:SetScript("OnClick", function()
      local ok, moved = ns.ApplyLoadout(loadout.key)
      if ok then
        ns.Print(("%s -- %d module%s changed."):format(loadout.label, moved, moved == 1 and "" or "s"))
      end
      if ns.RefreshOptions then ns.RefreshOptions() end
    end)
    page.loadouts[#page.loadouts + 1] = b
  end
  return 46 + #ns.LOADOUTS * 40
end

local function BuildProfile(root, y)
  local card = Card(root, LIST_W + GAP, y, SIDE_W, 96, "profiles", "Current Profile")
  local name = Box(card, SIDE_W - 20, 26, { 0.09, 0.08, 0.12, 1 }, { 0.30, 0.26, 0.36, 1 })
  name:SetPoint("TOPLEFT", 10, -34)
  local text = Text(name, 12, TEXT)
  text:SetPoint("LEFT", 8, 0)
  page.profileName = text

  local open = CreateFrame("Button", nil, card)
  open:SetSize(SIDE_W - 20, 24)
  open:SetPoint("TOPLEFT", 10, -66)
  ns.Skin.Button(open, { role = "general" })
  open:SetText("Profiles page")
  open:SetScript("OnClick", function() ns.OpenOptions("profiles") end)
  return 96
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

local function Refresh()
  for _, row in ipairs(rows) do
    local on = ns.IsModuleEnabled(row.module)
    row.switch:SetOn(on)
    row.state:SetText(on and "ON" or "OFF")
    row.state:SetTextColor(on and 0.55 or 0.45, on and 0.85 or 0.45, on and 0.62 or 0.50)
    row.title:SetTextColor(TEXT[1], TEXT[2], TEXT[3])
    if row.glyph.SetDesaturated then row.glyph:SetDesaturated(not on) end
  end
  if page.profileName then
    page.profileName:SetText(ns.ActiveProfileName and ns.ActiveProfileName() or "-")
  end
  if page.loadouts then
    local current = ns.CurrentLoadout and ns.CurrentLoadout()
    for _, b in ipairs(page.loadouts) do
      ns.Skin.SetBorderColor(b, b.key == current and ACCENT or { 0.30, 0.26, 0.36, 1 })
      ns.Skin.SetPanelColor(b, b.key == current and { 0.20, 0.12, 0.34, 1 } or { 0.09, 0.08, 0.12, 1 })
    end
  end
  if page.previewFor then
    ShowPreview(page.previewFor)
  end
end

function ns.ModulesPageSchema()
  return {
    { type = "heading", label = "Modules", subtitle = "Every part of ForeverUI, on or off. A module that is off is left to the game." },
    { type = "custom", bare = true, build = function(parent, x, y)
      page = {}
      for i = #rows, 1, -1 do rows[i] = nil end   -- kept, so the table the tests hold stays the one in use
      local root = CreateFrame("Frame", nil, parent)
      root:SetPoint("TOPLEFT", x, y)
      root:SetSize(W, 600)
      page.root = root
      local listH = BuildList(root)
      local sideY = 0
      sideY = sideY - BuildPreview(root, sideY) - GAP
      sideY = sideY - BuildLoadouts(root, sideY) - GAP
      sideY = sideY - BuildProfile(root, sideY)
      local height = math.max(listH, -sideY)
      root:SetHeight(height)
      ShowPreview(rows[1] and rows[1].module or "ActionBars")
      Refresh()
      return height + 12
    end,
      refresh = function() Refresh() end },
  }
end
