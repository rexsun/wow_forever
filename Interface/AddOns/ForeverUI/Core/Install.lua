local _, ns = ...

-- The first thing anyone sees: one window, six steps.
--
--   1  Welcome           what ForeverUI is, and the three grids side by side
--   2  How much of it?   the whole interface, the frames only, or no frames
--   3  How big?          interface scale
--   4  How do you play?  which grid (or grids) to put up
--   5  Levelling?        QuestForever, the quest helper, on or off
--   6  Ready             what applying will do, and who to tell when it breaks
--
-- This used to be two windows -- a welcome note from the author, then a
-- six-page installer behind it whose own first page was a bare "Welcome" and
-- whose last question asked the role question a second time. Now it is one,
-- and every step either asks something or shows something.
--
-- It can be run again from the General page or /fui install. It never deletes
-- a profile, and it never moves anything: positions come from the standard
-- layout, which already has all three grids placed.

local wizard
local state = {
  page = 1,
  scale = 1,
  loadout = "everything",
  roles = { healer = true },   -- which grids go up
  primary = "healer",          -- the one the options open on
  multi = false,               -- more than one grid at once
  quests = true,               -- QuestForever: quests on the map while you level
  dontShow = false,
}

local ROLE_ORDER = { "healer", "dps", "tank" }   -- the order the cards are laid out

local PAGES = {
  { key = "welcome", title = "Welcome" },
  { key = "amount",  title = "How much of it?" },
  { key = "size",    title = "How big?" },
  -- No frames, no grids: nothing to ask.
  { key = "role",    title = "How do you play?", skip = function() return state.loadout == "ui" end },
  { key = "quests",  title = "Levelling?" },
  { key = "ready",   title = "Ready", finish = true },
}

---------------------------------------------------------------------------
-- Choices
---------------------------------------------------------------------------

local function ChosenRoles()
  local list = {}
  for _, role in ipairs({ "healer", "tank", "dps" }) do
    if state.roles[role] then
      list[#list + 1] = role
    end
  end
  return list
end

-- Pick a role card. One at a time unless the player has asked for several,
-- and never none: an empty choice would put up no grids and look broken.
function ns.InstallerPickRole(role)
  if state.multi then
    local on = not state.roles[role]
    if not on and #ChosenRoles() == 1 then
      return   -- the last one stays
    end
    state.roles[role] = on or nil
    if on then
      state.primary = role
    elseif state.primary == role then
      state.primary = ChosenRoles()[1]
    end
  else
    state.roles = { [role] = true }
    state.primary = role
  end
end

function ns.InstallerSetMulti(on)
  state.multi = on and true or false
  if not state.multi then
    -- Back to one: keep the one they were last looking at.
    state.roles = { [state.primary or "healer"] = true }
  end
end

-- 50% to 200% in steps of 5.
function ns.InstallerSetScale(value)
  value = math.max(0.5, math.min(2, value or 1))
  state.scale = math.floor(value * 20 + 0.5) / 20
  return state.scale
end

-- Walk to the next page that has something to ask. The role page bows out
-- when the player has said they don't want frames, and stepping has to skip
-- it both ways rather than stranding them on a page with nothing on it.
function ns.InstallerStep(from, direction)
  local page = from
  for _ = 1, #PAGES do
    local nextPage = page + direction
    if nextPage < 1 or nextPage > #PAGES then
      return page
    end
    page = nextPage
    local skip = PAGES[page].skip
    if not (skip and skip()) then
      return page
    end
  end
  return page
end

-- What applying would do, in words: the dry run's whole output, and the
-- first line of a real one.
local function Plan()
  local roles = {}
  for _, role in ipairs({ "healer", "tank", "dps" }) do
    if state.roles[role] then roles[#roles + 1] = role end
  end
  return ("scale %d%%, loadout \"%s\", grids: %s, opens on %s, quest helper %s"):format(
    math.floor(state.scale * 100 + 0.5), state.loadout,
    state.loadout == "ui" and "none (frames left to the game)" or table.concat(roles, " + "),
    tostring(state.primary), state.quests and "on" or "off")
end
ns.InstallerPlan = Plan

local function Apply()
  if state.dry then
    ns.Print("|cffffd100test run|r -- nothing was changed. Applying would set: " .. Plan())
    return
  end
  ns.db.scale = state.scale
  -- A new player has nothing to catch up on: no "What's new" until the next update.
  ns.db.whatsNewSeen = ns.VERSION
  -- Straight away, not only after the next reload.
  if ns.ApplyMoverPositions then pcall(ns.ApplyMoverPositions) end
  -- How much of ForeverUI runs at all, before anything else.
  if ns.ApplyLoadout then
    ns.ApplyLoadout(state.loadout)
  end
  -- The quest helper is its own question, whatever the loadout.
  if ns.GetModule("QuestForever") and ns.IsModuleEnabled("QuestForever") ~= (state.quests and true or false) then
    ns.SetModuleEnabled("QuestForever", state.quests and true or false)
  end
  ns.RefreshAllModules()
  if state.loadout ~= "ui" then
    local frames = ns.Frames
    if frames and frames.SetGridShown then
      for _, role in ipairs({ "healer", "tank", "dps" }) do
        frames.SetGridShown(role, state.roles[role] == true)
      end
    end
    if ns.ChooseFramesRole then
      ns.ChooseFramesRole(state.primary)
    end
  end
  ns.db.installed = true
  -- Back the answers up right away, not at the next check.
  if ns.MacroBackup and C_Timer and C_Timer.After then
    C_Timer.After(2, function() pcall(ns.MacroBackup.Write, true) end)
  end
end

-- Start from what's already set, so running it again proposes what you have
-- rather than quietly undoing it.
local function Seed()
  state.page = 1
  state.scale = (ns.db and ns.db.scale) or 1
  state.loadout = (ns.CurrentLoadout and ns.CurrentLoadout()) or "everything"
  state.dontShow = false
  state.quests = ns.IsModuleEnabled("QuestForever") and true or false
  local frames = ns.Frames
  local shown = frames and frames.ShownGrids and frames.ShownGrids() or {}
  state.roles = {}
  for _, role in ipairs(shown) do
    state.roles[role] = true
  end
  local mode = frames and frames.GetMode and frames.GetMode() or "healer"
  if #shown == 0 then
    state.roles[mode] = true
  end
  state.primary = state.roles[mode] and mode or ChosenRoles()[1]
  state.multi = #ChosenRoles() > 1
end

---------------------------------------------------------------------------
-- Drawing helpers
---------------------------------------------------------------------------

local W, H = 920, 600
local FOOTER = 60

local ACCENT = { 0.30, 0.76, 1.00 }
local GOLD   = { 1.00, 0.82, 0.25 }
local TEXT   = { 0.92, 0.92, 0.94 }
local DIM    = { 0.62, 0.64, 0.70 }
local CARD_BG   = { 0.03, 0.06, 0.10, 0.92 }
local CARD_EDGE = { 0.16, 0.26, 0.36, 1 }
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local CHECK  = "Interface\\Buttons\\UI-CheckBox-Check"

local function RoleColor(role)
  local chrome = ns.Frames and ns.Frames.ROLE_CHROME and ns.Frames.ROLE_CHROME[role]
  if chrome then
    return chrome.color
  end
  return ({ healer = { 0.30, 0.85, 0.40 }, tank = { 1.00, 0.55, 0.15 }, dps = { 0.66, 0.42, 1.00 } })[role] or ACCENT
end

local function Text(parent, size, color, justify, outline)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  local path = ns.Media.Role("general")
  fs:SetFont(path, size, outline or "")
  fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetJustifyV("TOP")
  return fs
end

local function Rect(parent, color, layer, sub)
  local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
  tex:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
  return tex
end

-- Edges drawn by hand so a selected card can have a thicker one.
local function Edges(frame, color, thickness)
  frame.edges = frame.edges or {}
  local e = frame.edges
  if not e.top then
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
      e[side] = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    end
  end
  local t = thickness or 1
  e.top:ClearAllPoints();    e.top:SetPoint("TOPLEFT");     e.top:SetPoint("TOPRIGHT");       e.top:SetHeight(t)
  e.bottom:ClearAllPoints(); e.bottom:SetPoint("BOTTOMLEFT"); e.bottom:SetPoint("BOTTOMRIGHT"); e.bottom:SetHeight(t)
  e.left:ClearAllPoints();   e.left:SetPoint("TOPLEFT");    e.left:SetPoint("BOTTOMLEFT");    e.left:SetWidth(t)
  e.right:ClearAllPoints();  e.right:SetPoint("TOPRIGHT");  e.right:SetPoint("BOTTOMRIGHT");  e.right:SetWidth(t)
  for _, tex in pairs(e) do
    tex:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
  end
end

local function Box(parent, w, h, bg, edge)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  local fill = Rect(f, bg or CARD_BG, "BACKGROUND", -8)
  fill:SetAllPoints()
  f.fill = fill
  Edges(f, edge or CARD_EDGE, 1)
  return f
end

-- A card you click to choose. `color` is its own (a role's) or the accent.
local function Card(parent, w, h, color)
  local card = CreateFrame("Button", nil, parent)
  card:SetSize(w, h)
  card.fill = Rect(card, CARD_BG, "BACKGROUND", -8)
  card.fill:SetAllPoints()
  card.color = color or ACCENT
  function card:SetChosen(on)
    self.chosen = on and true or false
    local c = self.color
    if self.chosen then
      Edges(self, { c[1], c[2], c[3], 1 }, 2)
      self.fill:SetColorTexture(c[1] * 0.10, c[2] * 0.10 + 0.02, c[3] * 0.10 + 0.04, 0.95)
    else
      local dim = self.roleEdge and { c[1] * 0.55, c[2] * 0.55, c[3] * 0.55, 1 } or CARD_EDGE
      Edges(self, dim, 1)
      self.fill:SetColorTexture(CARD_BG[1], CARD_BG[2], CARD_BG[3], CARD_BG[4])
    end
  end
  card:SetScript("OnEnter", function(self)
    if not self.chosen then Edges(self, self.color, 1) end
  end)
  card:SetScript("OnLeave", function(self) self:SetChosen(self.chosen) end)
  card:SetChosen(false)
  return card
end

-- A column of ticked lines.
local function Checklist(parent, x, y, width, lines, color, size)
  local rowH = (size or 13) + 9
  for i, line in ipairs(lines) do
    local tick = parent:CreateTexture(nil, "ARTWORK")
    tick:SetSize(16, 16)
    tick:SetPoint("TOPLEFT", x, y - (i - 1) * rowH)
    tick:SetTexture(CHECK)
    tick:SetDesaturated(true)
    tick:SetVertexColor(color[1], color[2], color[3], 1)
    local fs = Text(parent, size or 13, TEXT)
    fs:SetPoint("TOPLEFT", x + 22, y - (i - 1) * rowH - 1)
    fs:SetWidth(width - 22)
    fs:SetText(line)
  end
  return #lines * rowH
end

---------------------------------------------------------------------------
-- The pretend party: the same few names on every preview
---------------------------------------------------------------------------

local NAMES = { "Skuri", "Kupho", "Shado", "Panz", "Cons", "Felo", "Elro", "Phal", "Vera", "Leaf",
  "Isht", "Miss", "Adel", "Veno", "Ereg", "Shur", "Emer", "Badw", "Zala", "Fura",
  "Vini", "Elec", "Gale", "Arax", "Dorl" }
local CLASS = {
  { 0.20, 0.45, 0.90 }, { 0.30, 0.70, 0.30 }, { 0.75, 0.70, 0.22 }, { 0.52, 0.28, 0.78 },
  { 0.82, 0.22, 0.28 }, { 0.70, 0.44, 0.24 }, { 0.88, 0.42, 0.62 }, { 0.90, 0.52, 0.14 },
  { 0.55, 0.56, 0.60 }, { 0.18, 0.62, 0.78 },
}
-- What each grid marks on a frame: a heal on the healer's, a threat mark on
-- the tank's, a target on the damage dealer's. Same party, three readings.
local MARKS = {
  healer = { "heal", "heal", "auras" },
  tank   = { "tank", "taunt", "target" },
  dps    = { "dps", "target", "focus" },
}

-- opts: cols, rows, cellW, cellH, gap, font, headers, role, offset
local function MiniGrid(parent, opts)
  local cols, rows = opts.cols, opts.rows
  local cw, ch, gap = opts.cellW, opts.cellH, opts.gap or 3
  local top = opts.headers and 14 or 0
  local grid = CreateFrame("Frame", nil, parent)
  grid:SetSize(cols * cw + (cols - 1) * gap, top + rows * ch + (rows - 1) * gap)
  if opts.headers then
    for c = 1, cols do
      local head = Text(grid, math.max(9, (opts.font or 10) - 1), DIM, "CENTER")
      head:SetPoint("TOPLEFT", (c - 1) * (cw + gap), 0)
      head:SetWidth(cw)
      head:SetText("Group " .. c)
    end
  end
  local marks = MARKS[opts.role or "healer"]
  for r = 1, rows do
    for c = 1, cols do
      local i = (opts.offset or 0) + (c - 1) * rows + r
      local color = CLASS[(i * 7) % #CLASS + 1]
      local x, y = (c - 1) * (cw + gap), -(top + (r - 1) * (ch + gap))
      local cell = Rect(grid, { color[1] * 0.80, color[2] * 0.80, color[3] * 0.80, 1 }, "ARTWORK", 1)
      cell:SetPoint("TOPLEFT", x, y)
      cell:SetSize(cw, ch)
      local gloss = Rect(grid, { 1, 1, 1, 0.07 }, "ARTWORK", 2)
      gloss:SetPoint("TOPLEFT", x, y)
      gloss:SetSize(cw, ch * 0.45)
      local name = Text(grid, opts.font or 10, { 1, 1, 1 })
      name:SetPoint("TOPLEFT", x + 3, y - 2)
      name:SetText(NAMES[(i - 1) % #NAMES + 1])
      -- health along the bottom
      local barH = math.max(2, math.floor(ch * 0.13))
      local track = Rect(grid, { 0, 0, 0, 0.55 }, "ARTWORK", 3)
      track:SetPoint("BOTTOMLEFT", grid, "TOPLEFT", x + 2, y - ch + 2)
      track:SetSize(cw - 4, barH)
      local hp = 0.35 + ((i * 37) % 62) / 100
      local fillColor = (i % 5 == 0) and { 0.20, 0.55, 1.00 } or ((i % 7 == 0) and { 0.95, 0.30, 0.30 } or { 0.25, 0.85, 0.35 })
      local fill = Rect(grid, fillColor, "ARTWORK", 4)
      fill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT")
      fill:SetSize(math.max(1, (cw - 4) * math.min(1, hp)), barH)
      if i % 3 ~= 1 and ch >= 16 then
        local glyph = ns.Skin.Icon(grid, marks[(i % #marks) + 1], math.floor(ch * 0.62), { 1, 1, 1, 0.9 }, "OVERLAY")
        glyph:SetPoint("RIGHT", cell, "RIGHT", -2, -1)
      end
    end
  end
  return grid
end

-- A whole interface in miniature: world, bars, chat, map, quests, and the
-- party frames if they are part of the deal.
local function MiniUI(parent, w, h, withFrames)
  local ui = CreateFrame("Frame", nil, parent)
  ui:SetSize(w, h)
  local world = Rect(ui, { 0.10, 0.14, 0.09, 1 }, "BACKGROUND", -7)
  world:SetAllPoints()
  if withFrames then
    local grid = MiniGrid(ui, { cols = 5, rows = 5, cellW = 16, cellH = 9, gap = 1, font = 6, role = "healer" })
    grid:SetPoint("TOPLEFT", 6, -6)
  end
  local map = ui:CreateTexture(nil, "ARTWORK")
  map:SetTexture(CIRCLE)
  map:SetVertexColor(0.30, 0.42, 0.26, 1)
  map:SetSize(40, 40)
  map:SetPoint("TOPRIGHT", -6, -6)
  local quests = Box(ui, 70, 50, { 0, 0, 0, 0.7 }, { 0.2, 0.3, 0.4, 1 })
  quests:SetPoint("TOPRIGHT", -6, -50)
  for i = 1, 4 do
    local line = Rect(quests, i == 1 and GOLD or { 0.85, 0.70, 0.30, 0.8 }, "ARTWORK")
    line:SetPoint("TOPLEFT", 5, -5 - (i - 1) * 11)
    line:SetSize(40 + (i * 13) % 20, 3)
  end
  local chat = Box(ui, 78, 36, { 0, 0, 0, 0.7 }, { 0.2, 0.3, 0.4, 1 })
  chat:SetPoint("BOTTOMLEFT", 6, 6)
  for i = 1, 3 do
    local line = Rect(chat, { 0.8, 0.8, 0.8, 0.6 }, "ARTWORK")
    line:SetPoint("TOPLEFT", 5, -6 - (i - 1) * 9)
    line:SetSize(50 - i * 6, 2)
  end
  local glyphs = { "spells", "heal", "tank", "dps", "target", "focus", "auras", "taunt", "engage", "assist", "bags", "map" }
  for row = 1, 2 do
    for col = 1, 6 do
      local slot = Box(ui, 14, 14, { 0.06, 0.06, 0.10, 1 }, { 0.3, 0.3, 0.4, 1 })
      slot:SetPoint("BOTTOM", ui, "BOTTOM", (col - 3.5) * 16, 6 + (2 - row) * 16)
      local g = ns.Skin.Icon(slot, glyphs[(row - 1) * 6 + col], 10, CLASS[(row * 6 + col) % #CLASS + 1])
      g:SetPoint("CENTER")
    end
  end
  for i, color in ipairs({ { 0.25, 0.85, 0.35 }, { 0.20, 0.45, 0.95 } }) do
    local bar = Rect(ui, color, "ARTWORK")
    bar:SetPoint("BOTTOM", ui, "BOTTOM", 0, 44 + (2 - i) * 5)
    bar:SetSize(56, 4)
  end
  return ui
end

-- Logo, title, gold subtitle, a line of explanation: the top of pages 2-5.
local function PageHeader(page, title, subtitle, line)
  local logo = page:CreateTexture(nil, "ARTWORK")
  logo:SetSize(128, 64)
  logo:SetPoint("TOPLEFT", 24, -14)
  logo:SetTexture(ns.MEDIA_PATH .. "foreverui-logo")
  page.heading = Text(page, 30, ACCENT)
  page.heading:SetPoint("TOPLEFT", 172, -10)
  page.heading:SetText(title)
  page.subtitle = Text(page, 18, GOLD)
  page.subtitle:SetPoint("TOPLEFT", 172, -48)
  page.subtitle:SetText(subtitle or "")
  page.line = Text(page, 13, TEXT)
  page.line:SetPoint("TOPLEFT", 172, -76)
  page.line:SetWidth(W - 172 - 160)
  page.line:SetSpacing(3)
  page.line:SetText(line or "")
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------

local builders = {}

builders.welcome = function(page)
  local LEFT_W = 390

  local logo = page:CreateTexture(nil, "ARTWORK")
  logo:SetSize(160, 80)
  logo:SetPoint("TOP", page, "TOPLEFT", 24 + LEFT_W / 2, -6)
  logo:SetTexture(ns.MEDIA_PATH .. "foreverui-logo")
  page.logo = logo

  local mark = Text(page, 44, TEXT, "CENTER", "")
  mark:SetPoint("TOP", page, "TOPLEFT", 24 + LEFT_W / 2, -84)
  mark:SetText("Forever|cff4dc3ffUI|r")

  local tagline = Text(page, 17, ACCENT, "CENTER")
  tagline:SetPoint("TOP", mark, "BOTTOM", 0, -6)
  tagline:SetText("One character. Every role. Your way.")

  local version = Text(page, 11, DIM, "CENTER")
  version:SetPoint("TOP", tagline, "BOTTOM", 0, -8)
  page.version = version

  local about = Text(page, 13, TEXT)
  about:SetPoint("TOPLEFT", 24, -196)
  about:SetWidth(LEFT_W)
  about:SetSpacing(3)
  about:SetText("One interface built for healers, tanks and damage dealers. Run one, two or all three "
    .. "role grids at once. Each is its own set of party frames, with its own spells, "
    .. "clicks and layout, saved for that role.")

  local features = {
    { icon = "roles", title = "Role-Specific Grids",
      text = "Healing, Tanking and DPS, each with its own click-casting, keybinds and indicators." },
    { icon = "gear", title = "Fully Customizable",
      text = "Change spells, layout, colours and behaviour any time with /fui." },
    { logo = true, title = "Use Any Combination",
      text = "One grid, two, or all three at once. Your setup, your choice." },
    { icon = "profiles", title = "Nothing is Permanent",
      text = "Just a few questions to get you started. Everything can be changed later with /fui." },
  }
  local y = -268
  for _, f in ipairs(features) do
    local icon
    if f.logo then
      icon = page:CreateTexture(nil, "ARTWORK")
      icon:SetTexture(ns.MEDIA_PATH .. "foreverui-logo")
      icon:SetSize(32, 16)
      icon:SetPoint("TOPLEFT", 24, y - 4)
    else
      icon = ns.Skin.Icon(page, f.icon, 26, ACCENT)
      icon:SetPoint("TOPLEFT", 27, y)
    end
    local title = Text(page, 15, ACCENT)
    title:SetPoint("TOPLEFT", 66, y)
    title:SetText(f.title)
    local body = Text(page, 12, DIM)
    body:SetPoint("TOPLEFT", 66, y - 20)
    body:SetWidth(LEFT_W - 48)
    body:SetText(f.text)
    y = y - 58
  end

  -- The three grids on one party, side by side.
  local x0, panelW, gapX = 440, 146, 10
  for i, role in ipairs({ "healer", "tank", "dps" }) do
    local color = RoleColor(role)
    local chrome = ns.Frames and ns.Frames.ROLE_CHROME and ns.Frames.ROLE_CHROME[role]
    local panel = Box(page, panelW, 262, { 0.02, 0.03, 0.05, 0.88 }, color)
    Edges(panel, color, 2)
    panel:SetPoint("TOPLEFT", x0 + (i - 1) * (panelW + gapX), -60)
    local glyph = ns.Skin.Icon(panel, chrome and chrome.icon or role, 18, color)
    glyph:SetPoint("TOPLEFT", 8, -7)
    local label = Text(panel, 16, color)
    label:SetPoint("TOPLEFT", 32, -7)
    label:SetText(chrome and chrome.label or role)
    local grid = MiniGrid(panel, { cols = 2, rows = 5, cellW = 63, cellH = 38, gap = 4, font = 12,
      headers = true, role = role })
    grid:SetPoint("TOPLEFT", 8, -32)
  end

  local caption = Text(page, 18, { 0.85, 0.88, 0.92, 0.9 }, "RIGHT")
  caption:SetPoint("TOPRIGHT", page, "TOPRIGHT", -30, -348)
  caption:SetSpacing(6)
  caption:SetText("Same group.\nThree perspectives.\nTotal control.")
  local swash = Rect(page, { 0.85, 0.88, 0.92, 0.55 })
  swash:SetPoint("TOPRIGHT", caption, "BOTTOMRIGHT", -10, -8)
  swash:SetSize(140, 2)

  -- Nothing was read at load. A first run and the Forever beta's
  -- saved-settings bug look the same from in here, so the note speaks to
  -- both -- and a player who set this up yesterday learns it isn't them.
  if ns.savedRestored == false then
    caption:Hide(); swash:Hide()
    local amber = { 1.00, 0.72, 0.30 }
    local note = Box(page, 458, 118, { 0.10, 0.06, 0.02, 0.92 }, amber)
    Edges(note, amber, 1)
    note:SetPoint("TOPRIGHT", page, "TOPRIGHT", -24, -334)
    local head = Text(note, 14, amber)
    head:SetPoint("TOPLEFT", 12, -10)
    head:SetText("Set ForeverUI up before?")
    local body = Text(note, 12, TEXT)
    body:SetPoint("TOPLEFT", 12, -30)
    body:SetWidth(434)
    body:SetSpacing(2)
    body:SetText("Then your settings weren't lost by ForeverUI. The Forever beta has a bug that stops the game "
      .. "reading any addon's saved settings after a restart (and after /reload, once they've been saved). "
      .. "Until Blizzard fixes it, the community tool ForeverSVFix restores them. Type /fui saved for the details.")
    page.savedNote = note
  end
end

local LOADOUT_CARDS = {
  { key = "everything", title = "Everything", sub = "The full ForeverUI experience.",
    lines = { "Action bars", "Unit frames and the three role grids", "Bags and inventory",
      "Chat and minimap", "Quest tracker and nameplates" } },
  { key = "frames", title = "Frames only", sub = "Just the party and raid frames.",
    lines = { "Party and raid frames for every role", "Role indicators: heals, threat, dispels",
      "Clean and lightweight", "Bars, bags, chat and map left to the game" } },
  { key = "ui", title = "No frames", sub = "Everything except the party frames.",
    lines = { "Bars, bags, chat, map and quests", "Party frames left to the game, VuhDo or Grid",
      "Turn the grids on later with /fui" } },
}

builders.amount = function(page)
  PageHeader(page, "How much of it?", "The whole interface, or just the frames you need?",
    "ForeverUI can set up everything, or only the parts you want.\nYou can always change this later with /fui.")
  page.cards = {}
  local cardW, gap = 280, 20
  local x0 = (W - (3 * cardW + 2 * gap)) / 2
  for i, spec in ipairs(LOADOUT_CARDS) do
    local card = Card(page, cardW, 340)
    card:SetPoint("TOPLEFT", x0 + (i - 1) * (cardW + gap), -128)
    card.key = spec.key
    local title = Text(card, 22, TEXT)
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText(spec.title)
    local sub = Text(card, 13, ACCENT)
    sub:SetPoint("TOPLEFT", 16, -40)
    sub:SetText(spec.sub)
    local preview = Box(card, cardW - 24, 150, { 0, 0, 0, 0.5 }, { 0.2, 0.3, 0.4, 1 })
    preview:SetPoint("TOPLEFT", 12, -64)
    if spec.key == "frames" then
      local grid = MiniGrid(preview, { cols = 5, rows = 5, cellW = 48, cellH = 24, gap = 3, font = 10 })
      grid:SetPoint("CENTER")
    else
      local ui = MiniUI(preview, cardW - 28, 146, spec.key == "everything")
      ui:SetPoint("CENTER")
    end
    Checklist(card, 16, -228, cardW - 28, spec.lines, TEXT, 13)
    card:SetScript("OnClick", function()
      state.loadout = spec.key
      ns.RenderInstaller()
    end)
    page.cards[i] = card
  end
end

builders.size = function(page)
  PageHeader(page, "How big?", "", "Smaller fits more on screen; larger is easier to read.")
  page.cards = {}
  local specs = {
    { key = "small", value = 0.85, title = "Smaller", sub = "Fits more on screen.",
      lines = { "More units visible", "Smaller text and elements", "Best for large groups and high resolutions" },
      grid = { cols = 5, rows = 5, cellW = 46, cellH = 22, gap = 3, font = 9 } },
    { key = "large", value = 1.25, title = "Larger", sub = "Easier to read.",
      lines = { "Larger text and elements", "Easier to read in combat", "Best for lower resolutions or accessibility" },
      grid = { cols = 3, rows = 3, cellW = 76, cellH = 40, gap = 4, font = 14 } },
  }
  local cardW, gap = 380, 30
  local x0 = (W - (2 * cardW + gap)) / 2
  for i, spec in ipairs(specs) do
    local card = Card(page, cardW, 296)
    card:SetPoint("TOPLEFT", x0 + (i - 1) * (cardW + gap), -118)
    card.value = spec.value
    local title = Text(card, 22, TEXT)
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText(spec.title)
    local sub = Text(card, 13, ACCENT)
    sub:SetPoint("TOPLEFT", 16, -40)
    sub:SetText(spec.sub)
    local preview = Box(card, cardW - 24, 150, { 0, 0, 0, 0.5 }, { 0.2, 0.3, 0.4, 1 })
    preview:SetPoint("TOPLEFT", 12, -64)
    local grid = MiniGrid(preview, spec.grid)
    grid:SetPoint("CENTER")
    Checklist(card, 16, -226, cardW - 28, spec.lines, ACCENT, 13)
    card:SetScript("OnClick", function()
      ns.InstallerSetScale(spec.value)
      ns.RenderInstaller()
    end)
    page.cards[i] = card
  end

  -- The fine control, under the two cards.
  local label = Text(page, 13, ACCENT, "CENTER")
  label:SetPoint("TOP", page, "TOP", 0, -428)
  page.scaleLabel = label

  local slider = CreateFrame("Slider", nil, page)
  slider:SetSize(360, 16)
  slider:SetPoint("TOP", page, "TOP", 0, -450)
  slider:SetOrientation("HORIZONTAL")
  slider:SetMinMaxValues(50, 200)
  slider:SetValueStep(5)
  if slider.SetObeyStepOnDrag then
    slider:SetObeyStepOnDrag(true)
  end
  local track = Rect(slider, { 0.22, 0.28, 0.36, 1 }, "BACKGROUND")
  track:SetPoint("LEFT")
  track:SetPoint("RIGHT")
  track:SetHeight(4)
  local thumb = slider:CreateTexture(nil, "OVERLAY")
  thumb:SetTexture(CIRCLE)
  thumb:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
  thumb:SetSize(16, 16)
  slider:SetThumbTexture(thumb)
  slider:SetScript("OnValueChanged", function(_, value)
    if page.settingSlider then
      return
    end
    ns.InstallerSetScale((value or 100) / 100)
    ns.RenderInstaller()
  end)
  page.slider = slider
  for _, mark in ipairs({ 50, 100, 200 }) do
    local tick = Text(page, 11, DIM, "CENTER")
    tick:SetPoint("TOP", slider, "BOTTOMLEFT", 360 * (mark - 50) / 150, -4)
    tick:SetText(mark .. "%")
  end
end

local ROLE_CARDS = {
  healer = { title = "Healer", sub = "Keep your group alive.", icon = "heal",
    lines = { "Healing-focused party and raid frames", "HoTs, incoming heals and overhealing",
      "Dispel and cleanse indicators", "Click-cast any spell on anyone" } },
  dps = { title = "Damage", sub = "Deal damage. Support your group.", icon = "dps",
    lines = { "Party frames that stay out of your way", "Debuffs and dispels you can act on",
      "Target and focus at a glance", "Click-cast your utility spells" } },
  tank = { title = "Tank", sub = "Hold the line. Control the fight.", icon = "tank",
    lines = { "Threat and aggro on every frame", "An alarm when a mob gets loose",
      "The loose list: what isn't on you", "Click a frame to taunt what hits them" } },
}

builders.role = function(page)
  PageHeader(page, "How do you play?", "Choose your primary layout.",
    "We'll set up the interface for your role now. You can enable more roles later, "
    .. "and even run several grids at the same time.")
  page.cards = {}
  local cardW, gap = 280, 20
  local x0 = (W - (3 * cardW + 2 * gap)) / 2
  for i, role in ipairs(ROLE_ORDER) do
    local spec, color = ROLE_CARDS[role], RoleColor(role)
    local card = Card(page, cardW, 340, color)
    card.roleEdge = true
    card.role = role
    card:SetPoint("TOPLEFT", x0 + (i - 1) * (cardW + gap), -128)
    local icon = ns.Skin.Icon(card, spec.icon, 38, color)
    icon:SetPoint("TOPLEFT", 14, -14)
    local title = Text(card, 24, color)
    title:SetPoint("TOPLEFT", 62, -12)
    title:SetText(spec.title)
    local sub = Text(card, 13, TEXT)
    sub:SetPoint("TOPLEFT", 62, -42)
    sub:SetText(spec.sub)
    local preview = Box(card, cardW - 24, 150, { 0, 0, 0, 0.5 }, { color[1] * 0.4, color[2] * 0.4, color[3] * 0.4, 1 })
    preview:SetPoint("TOPLEFT", 12, -66)
    local grid = MiniGrid(preview, { cols = 5, rows = 5, cellW = 48, cellH = 23, gap = 3, font = 9,
      headers = true, role = role })
    grid:SetPoint("CENTER")
    Checklist(card, 16, -230, cardW - 28, spec.lines, color, 13)
    card:SetScript("OnClick", function()
      ns.InstallerPickRole(role)
      ns.RenderInstaller()
    end)
    card:SetChosen(false)
    page.cards[i] = card
  end
end

-- "Levelling?": QuestForever, the quest helper, on or off.
function ns.InstallerSetQuests(on)
  state.quests = on and true or false
end

builders.quests = function(page)
  PageHeader(page, "Levelling?", "Want quests shown on your map while you level?",
    "QuestForever marks where to pick quests up, where to hand them in and where the mobs and items are.\n"
    .. "You can switch it on or off any time with /fui qf.")
  page.cards = {}
  local specs = {
    { on = true, title = "Yes, show me", sub = "Quests on the map and minimap.",
      lines = { "\"!\" where to pick a quest up", "\"?\" where to hand it in",
        "Dots where the mobs and items are", "Click one and the arrow points the way" } },
    { on = false, title = "No thanks", sub = "The map stays as the game draws it.",
      lines = { "Nothing added to the map or minimap", "No quest data loaded at all",
        "Turn it on later: /fui qf" } },
  }
  local cardW, gap = 380, 30
  local x0 = (W - (2 * cardW + gap)) / 2
  for i, spec in ipairs(specs) do
    local card = Card(page, cardW, 260)
    card:SetPoint("TOPLEFT", x0 + (i - 1) * (cardW + gap), -128)
    local title = Text(card, 22, TEXT)
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText(spec.title)
    local sub = Text(card, 13, ACCENT)
    sub:SetPoint("TOPLEFT", 16, -40)
    sub:SetText(spec.sub)
    local mark = card:CreateTexture(nil, "ARTWORK")
    mark:SetSize(48, 48)
    mark:SetPoint("TOPRIGHT", -16, -14)
    if not (mark.SetAtlas and pcall(mark.SetAtlas, mark, spec.on and "QuestNormal" or "QuestTurnin")) then
      mark:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    end
    if not spec.on and mark.SetDesaturated then mark:SetDesaturated(true) end
    Checklist(card, 16, -90, cardW - 28, spec.lines, spec.on and ACCENT or DIM, 14)
    card:SetScript("OnClick", function()
      ns.InstallerSetQuests(spec.on)
      ns.RenderInstaller()
    end)
    page.cards[i] = card
  end
end

builders.ready = function(page)
  PageHeader(page, "You're set.", "Here's what happens when you apply.",
    "Apply sets your scale and puts up your grids; then one reload finishes it. "
    .. "Nothing else moves: the layout is the standard one, and all of it can be changed later with /fui.")

  local summary = Box(page, 420, 300)
  summary:SetPoint("TOPLEFT", 24, -128)
  local head = Text(summary, 16, ACCENT)
  head:SetPoint("TOPLEFT", 16, -14)
  head:SetText("Your setup")
  page.summaryRows = {}
  local rows = { { icon = "interface", key = "amount" }, { icon = "layout", key = "size" },
    { icon = "roles", key = "grids" }, { icon = "quests", key = "quests" }, { icon = "reset", key = "reload" } }
  for i, row in ipairs(rows) do
    local icon = ns.Skin.Icon(summary, row.icon, 22, ACCENT)
    icon:SetPoint("TOPLEFT", 16, -50 - (i - 1) * 48)
    local label = Text(summary, 12, DIM)
    label:SetPoint("TOPLEFT", 50, -48 - (i - 1) * 48)
    local value = Text(summary, 15, TEXT)
    value:SetPoint("TOPLEFT", 50, -66 - (i - 1) * 48)
    value:SetWidth(350)
    page.summaryRows[row.key] = { label = label, value = value }
  end

  local author = Box(page, 440, 300)
  author:SetPoint("TOPRIGHT", -24, -128)
  local logo = author:CreateTexture(nil, "ARTWORK")
  logo:SetTexture(ns.MEDIA_PATH .. "foreverui-logo")
  logo:SetSize(48, 24)
  logo:SetPoint("TOPLEFT", 14, -14)
  local by = Text(author, 16, ACCENT)
  by:SetPoint("TOPLEFT", 70, -16)
  local info = ns.INFO or {}
  by:SetText(("Built by %s"):format(info.author or "Solindius"))
  local beta = Text(author, 13, TEXT)
  beta:SetPoint("TOPLEFT", 16, -52)
  beta:SetWidth(408)
  beta:SetSpacing(3)
  beta:SetText(("This is a beta, made for %s and nothing else. Forever goes live on %s, and the plan "
    .. "is to have this steady by then. If something breaks, tell me. \"The tank grid went blank "
    .. "when I zoned\" is a perfectly good bug report."):format(info.client or "World of Warcraft: Forever",
    info.release or "6 November"))
  local tag = Text(author, 20, GOLD)
  tag:SetPoint("TOPLEFT", 16, -170)
  tag:SetText(info.battleTag or "")
  local tagLabel = Text(author, 11, DIM)
  tagLabel:SetPoint("BOTTOMLEFT", tag, "TOPLEFT", 0, 4)
  tagLabel:SetText("BattleTag, for a friend request")
  local copy = CreateFrame("Button", nil, author)
  copy:SetSize(190, 30)
  copy:SetPoint("BOTTOMLEFT", 16, 16)
  ns.Skin.Button(copy, { role = "general" })
  copy:SetText("Copy my BattleTag")
  copy:SetScript("OnClick", function() if ns.CopyBattleTag then ns.CopyBattleTag() end end)
  page.copyTag = copy
end

---------------------------------------------------------------------------
-- Refresh what is on screen from `state`
---------------------------------------------------------------------------

local LOADOUT_WORDS = { everything = "Everything", frames = "Frames only", ui = "Everything except the party frames" }

local function GridsLine()
  local parts = {}
  for _, role in ipairs({ "healer", "tank", "dps" }) do
    if state.roles[role] then
      local c = RoleColor(role)
      local label = ns.Frames and ns.Frames.ROLE_CHROME and ns.Frames.ROLE_CHROME[role]
      local function byte(v) return math.floor(v * 255 + 0.5) end
      parts[#parts + 1] = ("|cff%02x%02x%02x%s|r"):format(byte(c[1]), byte(c[2]), byte(c[3]),
        label and label.label or role)
    end
  end
  return table.concat(parts, " + ")
end

local refresh = {}

refresh.welcome = function(page)
  page.version:SetText(("ForeverUI %s, running on %s."):format(ns.VERSION or "?",
    ns.Compat and ns.Compat.Describe and ns.Compat.Describe() or "Forever"))
end

refresh.amount = function(page)
  for _, card in ipairs(page.cards) do
    card:SetChosen(card.key == state.loadout)
  end
end

refresh.size = function(page)
  local pct = math.floor(state.scale * 100 + 0.5)
  page.subtitle:SetText(("Interface scale: |cffffd140%d%%|r"):format(pct))
  page.scaleLabel:SetText(("Interface Scale: |cffffd140%d%%|r"):format(pct))
  page.cards[1]:SetChosen(state.scale < 1)
  page.cards[2]:SetChosen(state.scale > 1)
  page.settingSlider = true
  page.slider:SetValue(pct)
  page.settingSlider = false
end

refresh.role = function(page)
  for _, card in ipairs(page.cards) do
    card:SetChosen(state.roles[card.role] == true)
  end
end

refresh.quests = function(page)
  page.cards[1]:SetChosen(state.quests == true)
  page.cards[2]:SetChosen(state.quests ~= true)
end

refresh.ready = function(page)
  local rows = page.summaryRows
  rows.amount.label:SetText("How much")
  rows.amount.value:SetText(LOADOUT_WORDS[state.loadout] or state.loadout)
  rows.size.label:SetText("Interface scale")
  rows.size.value:SetText(("%d%%"):format(math.floor(state.scale * 100 + 0.5)))
  rows.grids.label:SetText("Grids on screen")
  rows.grids.value:SetText(state.loadout == "ui" and "None: the party frames are left to the game" or GridsLine())
  rows.quests.label:SetText("Quests on the map")
  rows.quests.value:SetText(state.quests and "QuestForever on" or "Off (/fui qf turns it on)")
  rows.reload.label:SetText("Then")
  if state.applied then
    rows.reload.value:SetText("|cff66ff66Applied.|r Reload now to finish.")
  else
    rows.reload.value:SetText("Apply, then one reload to put it all in place")
  end
end

-- The page currently showing, as words: for the tests, and for anyone
-- reading /fui install in a bug report.
local function Describe()
  local key = PAGES[state.page].key
  if key == "amount" then
    local entry = ns.Loadout and ns.Loadout(state.loadout)
    return ("How much of it? %s -- %s"):format(LOADOUT_WORDS[state.loadout] or "?", entry and entry.note or "")
  elseif key == "size" then
    return ("How big? Interface scale: %d%%"):format(math.floor(state.scale * 100 + 0.5))
  elseif key == "role" then
    return ("How do you play? %s"):format(GridsLine())
  elseif key == "quests" then
    return ("Levelling? Quests on the map: %s"):format(state.quests and "yes" or "no")
  elseif key == "ready" then
    return ("Ready: %s, %d%%, %s"):format(LOADOUT_WORDS[state.loadout] or "?",
      math.floor(state.scale * 100 + 0.5), GridsLine())
  end
  return "Welcome to ForeverUI"
end
ns.InstallerDescribe = Describe

function ns.RenderInstaller()
  if not wizard then
    return
  end
  local page = PAGES[state.page]
  for key, frame in pairs(wizard.pages) do
    frame:SetShown(key == page.key)
  end
  if refresh[page.key] then
    refresh[page.key](wizard.pages[page.key])
  end
  wizard.body:SetText(Describe())

  -- Footer: on the welcome page, the don't-show box sits where Back would.
  local first = state.page == 1
  wizard.back:SetShown(not first)
  wizard.dontShow:SetShown(first)
  wizard.dontShowLabel:SetShown(first)
  wizard.dontShow:SetChecked(state.dontShow)
  if wizard.dontShow.Paint then wizard.dontShow:Paint() end
  wizard.multi:SetShown(page.key == "role")
  wizard.multiLabel:SetShown(page.key == "role")
  wizard.multiNote:SetShown(page.key == "role")
  wizard.multi:SetChecked(state.multi)
  if wizard.multi.Paint then wizard.multi:Paint() end
  if page.finish and state.dry then
    wizard.next:SetText(state.applied and "Close test" or "Apply (test)")
  elseif page.finish then
    wizard.next:SetText(state.applied and "Reload now" or "Apply")
  else
    wizard.next:SetText("Next  >")
  end
  wizard.back:SetEnabled(not state.applied)

  -- Step dots: a page that is skipped is still a step, just one you jump.
  for i, dot in ipairs(wizard.dots) do
    local c = i <= state.page and ACCENT or { 0.30, 0.32, 0.38 }
    dot:SetVertexColor(c[1], c[2], c[3], 1)
    dot:SetSize(i == state.page and 13 or 10, i == state.page and 13 or 10)
  end
  wizard.stepText:SetText(("Step %d of %d"):format(state.page, #PAGES))
  if state.dry then
    wizard.testBanner:SetText("TEST RUN -- as a new player, nothing will be changed")
  elseif state.fresh then
    wizard.testBanner:SetText("TEST -- as a new player; Apply really applies")
  else
    wizard.testBanner:SetText("")
  end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

-- Closed without applying. It counts as seen only if the box says so:
-- otherwise it comes back next login, which is what an unticked
-- "Don't show this again" means. Applying always counts.
local function Seen()
  if state.dry then
    return   -- a test run leaves no trace, not even "seen"
  end
  if ns.db and (state.dontShow or state.applied) then
    ns.db.installed = true
  end
end

local function Dismiss()
  wizard:Hide()
end

local function CreateWizard()
  wizard = CreateFrame("Frame", "ForeverUIInstaller", UIParent)
  wizard:SetSize(W, H)
  wizard:SetPoint("CENTER")
  wizard:SetFrameStrata("FULLSCREEN_DIALOG")
  wizard:EnableMouse(true)
  wizard:SetMovable(true)
  wizard:SetClampedToScreen(true)
  wizard:RegisterForDrag("LeftButton")
  wizard:SetScript("OnDragStart", wizard.StartMoving)
  wizard:SetScript("OnDragStop", wizard.StopMovingOrSizing)
  wizard:SetScript("OnHide", Seen)
  table.insert(UISpecialFrames, "ForeverUIInstaller")  -- Escape closes it
  -- Mostly opaque: the world shows faintly through, as in the mock-ups.
  ns.Skin.Panel(wizard, { color = { 0.02, 0.04, 0.08, 0.93 }, borderColor = { 0.16, 0.45, 0.70, 1 } })
  ns.Skin.Header(wizard, "Welcome to ForeverUI", Dismiss)

  -- The page area, between the header and the footer.
  local content = CreateFrame("Frame", nil, wizard)
  content:SetPoint("TOPLEFT", 0, -32)
  content:SetPoint("BOTTOMRIGHT", 0, FOOTER)
  wizard.content = content
  wizard.pages = {}
  for _, page in ipairs(PAGES) do
    local frame = CreateFrame("Frame", nil, content)
    frame:SetAllPoints()
    frame:SetSize(W, H - 32 - FOOTER)
    builders[page.key](frame)
    frame:Hide()
    wizard.pages[page.key] = frame
  end
  wizard.logo = wizard.pages.welcome.logo

  -- An invisible line of text saying where we are: what the tests read, and
  -- what a screen reader would.
  wizard.body = Text(wizard, 1, { 0, 0, 0, 0 })
  wizard.body:SetPoint("BOTTOMLEFT", 0, 0)
  wizard.body:Hide()

  local rule = Rect(wizard, { 0.16, 0.45, 0.70, 0.6 })
  rule:SetPoint("BOTTOMLEFT", 1, FOOTER)
  rule:SetPoint("BOTTOMRIGHT", -1, FOOTER)
  rule:SetHeight(1)

  -- Step dots, top right, clear of every page's own content.
  wizard.dots = {}
  for i = 1, #PAGES do
    local dot = wizard:CreateTexture(nil, "OVERLAY")
    dot:SetTexture(CIRCLE)
    dot:SetPoint("CENTER", wizard, "TOPRIGHT", -150 + (i - 1) * 22, -50)
    wizard.dots[i] = dot
  end
  -- Only ever says anything during a test run (/fui test setup).
  wizard.testBanner = Text(wizard, 12, GOLD, "RIGHT")
  wizard.testBanner:SetPoint("TOPRIGHT", wizard, "TOPRIGHT", -44, -9)
  wizard.stepText = Text(wizard, 12, ACCENT, "CENTER")
  wizard.stepText:SetPoint("TOP", wizard, "TOPRIGHT", -106, -62)

  wizard.back = CreateFrame("Button", nil, wizard)
  wizard.back:SetSize(170, 36)
  wizard.back:SetPoint("BOTTOMLEFT", 16, 12)
  ns.Skin.Button(wizard.back, { role = "header" })
  wizard.back:SetText("<  Back")
  wizard.back:SetScript("OnClick", function()
    state.page = ns.InstallerStep(state.page, -1)
    ns.RenderInstaller()
  end)

  wizard.next = CreateFrame("Button", nil, wizard)
  wizard.next:SetSize(210, 36)
  wizard.next:SetPoint("BOTTOMRIGHT", -16, 12)
  ns.Skin.Button(wizard.next, { role = "header" })
  -- The one filled button: the way forward. The skin repaints buttons flat
  -- on hover, so the fill is put back after it every time.
  local function PaintNext(self, hot)
    ns.Skin.SetPanelColor(self, hot and { 0.10, 0.42, 0.80, 1 } or { 0.05, 0.30, 0.62, 1 })
    ns.Skin.SetBorderColor(self, ACCENT)
  end
  wizard.next:HookScript("OnEnter", function(self) PaintNext(self, true) end)
  wizard.next:HookScript("OnLeave", function(self) PaintNext(self, false) end)
  PaintNext(wizard.next, false)
  wizard.next:SetScript("OnClick", function()
    if PAGES[state.page].finish then
      -- Two clicks, on purpose. Applying rebuilds the grids, and on this
      -- client a reload asked for in the same click as that is refused
      -- ("Interface action failed because of an AddOn") -- tested. A click
      -- that does nothing but reload is allowed. So: apply, then reload.
      if not state.applied then
        Apply()
        state.applied = true
        ns.RenderInstaller()
        return
      end
      if state.dry then
        wizard:Hide()   -- nothing to reload: nothing changed
        return
      end
      -- Nothing but the reload in this click: hiding the wizard first got
      -- the reload refused in the client (ADDON_ACTION_BLOCKED Reload()),
      -- and the reload takes the window down anyway. The macro backup is
      -- only macro text, so writing it here doesn't count against that.
      if ns.MacroBackup then pcall(ns.MacroBackup.Write, true) end
      if ReloadUI then
        ReloadUI()
      end
      return
    end
    state.page = ns.InstallerStep(state.page, 1)
    ns.RenderInstaller()
  end)

  -- "Don't show this again", page one only.
  wizard.dontShow = CreateFrame("CheckButton", nil, wizard)
  wizard.dontShow:SetSize(18, 18)
  wizard.dontShow:SetPoint("BOTTOMLEFT", 20, 21)
  ns.Skin.Checkbox(wizard.dontShow)
  wizard.dontShow:SetScript("OnClick", function(self)
    state.dontShow = self:GetChecked() and true or false
    if self.Paint then self:Paint() end
  end)
  wizard.dontShowLabel = Text(wizard, 13, DIM)
  wizard.dontShowLabel:SetPoint("LEFT", wizard.dontShow, "RIGHT", 10, 0)
  wizard.dontShowLabel:SetText("Don't show this again")

  -- "Several grids at once", the role page only.
  wizard.multi = CreateFrame("CheckButton", nil, wizard)
  wizard.multi:SetSize(18, 18)
  wizard.multi:SetPoint("BOTTOM", wizard, "BOTTOM", -180, 30)
  ns.Skin.Checkbox(wizard.multi)
  wizard.multi:SetScript("OnClick", function(self)
    ns.InstallerSetMulti(self:GetChecked())
    ns.RenderInstaller()
  end)
  wizard.multiLabel = Text(wizard, 14, TEXT)
  wizard.multiLabel:SetPoint("LEFT", wizard.multi, "RIGHT", 10, 0)
  wizard.multiLabel:SetText("I want more than one role grid now")
  wizard.multiNote = Text(wizard, 11, DIM)
  wizard.multiNote:SetPoint("TOPLEFT", wizard.multiLabel, "BOTTOMLEFT", 0, -4)
  wizard.multiNote:SetText("You can also switch grids on later, beside Heal, Tank and DPS in the menu.")

  ns.installer = wizard
end

-- As big as the screen comfortably allows, up to half again: this is the
-- first thing anyone sees, and at the plain 1:1 of the options window it
-- comes out postage-stamp small on a big monitor.
local function Size()
  local w = UIParent and UIParent:GetWidth() or W
  local h = UIParent and UIParent:GetHeight() or H
  local scale = math.min(1.5, (w * 0.82) / W, (h * 0.86) / H)
  wizard:SetScale(scale > 0 and scale or 1)
end

-- What a player who has never run ForeverUI starts from.
local function SeedFresh()
  state.page = 1
  state.scale = 1
  state.loadout = "everything"
  state.roles = { healer = true }
  state.primary = "healer"
  state.multi = false
  state.quests = true
  state.dontShow = false
end

-- `again` means the player asked for it; otherwise it's the first login.
-- opts (testing, see Core/Testing.lua):
--   fresh  start from a new player's defaults, not from your settings
--   dry    walk through it without changing anything
function ns.ShowInstaller(again, opts)
  opts = opts or {}
  if not wizard then
    CreateWizard()
  end
  state.fresh = opts.fresh and true or false
  state.dry = opts.dry and true or false
  if state.fresh then
    SeedFresh()
  else
    Seed()
  end
  state.applied = false
  if again and not state.fresh then
    ns.Print("running setup again - your profile is kept; only scale and which grids are up can change.")
  end
  Size()
  ns.RenderInstaller()
  wizard:Show()
end

-- The old welcome window is this wizard's first page now. Kept by name for
-- /fui info welcome and the Info page.
function ns.ShowWelcome(force)
  if not force and ns.db and ns.db.installed then
    return false
  end
  ns.ShowInstaller(force)
  return true
end

function ns.DismissWelcome()
  state.dontShow = true
  if wizard then
    wizard:Hide()
  end
end

-- For the tests and for /fui install: the wizard's own logic, without the frames.
ns.installerState = state
ns.ApplyInstaller = function()
  Apply()
  state.applied = true
end
ns.InstallerPages = PAGES
