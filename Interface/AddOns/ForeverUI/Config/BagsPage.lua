local _, ns = ...

-- The Bags page, from the owner's mock-up (23 Sept 2026): the bag window's
-- size and behaviour, its search bar and its currency line down the left; a
-- live preview of your own Combined Backpack and the presets down the right.
-- Every row is the options window's own (ns.OptionsKit), so it saves and
-- refreshes like every other page; the preview redraws from your real bags
-- whenever a setting changes.

local W = 636
local LEFT_W = 330
local RIGHT_X = LEFT_W + 12
local RIGHT_W = W - RIGHT_X

local EDGE = { 0.66, 0.50, 0.26, 1 }
local FILL = { 0.05, 0.04, 0.07, 0.92 }
local HEAD_FILL = { 0.10, 0.07, 0.12, 0.95 }
local TEXT = { 0.94, 0.92, 0.96 }
local DIM = { 0.68, 0.64, 0.72 }

local page = {}

local function Module() return ns.GetModule("Bags") end
local function Settings() return ns.db.modules.Bags end

local function Text(parent, size, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(ns.Media.Role("general"), size, "")
  fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

-- A dark card with a gold edge and a header: icon, title, a line under it.
local function Card(parent, x, y, w, h, icon, title, desc)
  local card = CreateFrame("Frame", nil, parent)
  card:SetSize(w, h)
  card:SetPoint("TOPLEFT", x, y)
  ns.Skin.Panel(card, { color = FILL, borderColor = EDGE })
  local head = card:CreateTexture(nil, "BACKGROUND", nil, 1)
  head:SetPoint("TOPLEFT", 1, -1)
  head:SetPoint("TOPRIGHT", -1, -1)
  head:SetHeight(desc and 44 or 30)
  head:SetColorTexture(HEAD_FILL[1], HEAD_FILL[2], HEAD_FILL[3], HEAD_FILL[4])
  local glyph = ns.Skin.Icon(card, icon, 22, EDGE, "OVERLAY")
  glyph:SetPoint("TOPLEFT", 10, -9)
  local label = Text(card, 15, TEXT)
  ns.OptionsKit.BigFont(label, 15)
  label:SetTextColor(TEXT[1], TEXT[2], TEXT[3])
  label:SetPoint("TOPLEFT", 42, -7)
  label:SetText(title)
  if desc then
    local line = Text(card, 11, DIM)
    line:SetPoint("TOPLEFT", 42, -26)
    line:SetText(desc)
  end
  card.top = desc and -52 or -38
  return card
end

local function Row(card, kind, y, entry)
  local kit = ns.OptionsKit
  entry.moduleName = entry.moduleName or "Bags"
  entry.type = kind
  if kind == "checkbox" then
    kit.MakeCheckbox(card, entry, y, 12)
  elseif kind == "slider" then
    entry.type, entry.slider, entry.sliderWidth = "stepper", true, entry.sliderWidth or 110
    kit.MakeStepper(card, entry, y, 12, 10)
  elseif kind == "cycler" then
    kit.MakeCycler(card, entry, y, 12, 10)
  end
  page.entries[#page.entries + 1] = entry
  return y - kit.RowHeight(entry)
end

local function Percent(v) return ("%d%%"):format(math.floor((v or 1) * 100 + 0.5)) end
local function Plain(v) return tostring(math.floor((v or 0) + 0.5)) end

---------------------------------------------------------------------------
-- The preview: your Combined Backpack in miniature
---------------------------------------------------------------------------

local P = { ICON = 22, GAP = 2, SIDE = 92, HEAD = 26, SEARCH = 22, FOOT = 26 }

local function BuildPreview(parent, w)
  local box = CreateFrame("Frame", nil, parent)
  box:SetSize(w, 232)
  ns.Skin.Panel(box, { color = { 0.03, 0.03, 0.05, 0.94 }, borderColor = ns.Colors.ui.accent })
  local title = Text(box, 12, TEXT)
  local bag = ns.Skin.Icon(box, "bags", 14, nil, "OVERLAY")
  bag:SetPoint("TOPLEFT", 8, -6)
  title:SetPoint("LEFT", bag, "RIGHT", 6, 0)
  title:SetText("Combined Backpack")
  local x = ns.Skin.Icon(box, "close", 10, { 1, 1, 1 }, "OVERLAY")
  x:SetPoint("TOPRIGHT", -8, -8)

  box.search = CreateFrame("Frame", nil, box)
  box.search:SetHeight(P.SEARCH - 4)
  ns.Skin.Panel(box.search, { color = { 0.06, 0.06, 0.08, 1 } })
  box.searchHint = Text(box.search, 10, DIM)
  box.searchHint:SetText("Search items...")
  box.count = Text(box, 10, DIM)

  box.side = CreateFrame("Frame", nil, box)
  box.cats = {}
  for i, cat in ipairs(Module().CATEGORIES or {}) do
    local row = CreateFrame("Frame", nil, box.side)
    row:SetSize(P.SIDE - 6, 20)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
    ns.Skin.Panel(row, { color = { 0.08, 0.08, 0.11, 1 } })
    row.name = Text(row, 10, TEXT)
    row.name:SetPoint("LEFT", 6, 0)
    row.name:SetText(cat.label)
    row.num = Text(row, 10, ns.Colors.ui.accent)
    row.num:SetPoint("RIGHT", -6, 0)
    row.key = cat.key
    box.cats[i] = row
  end

  box.grid = CreateFrame("Frame", nil, box)
  box.slots = {}
  box.foot = CreateFrame("Frame", nil, box)
  box.foot:SetHeight(P.FOOT)
  box.foot:SetPoint("BOTTOMLEFT", 1, 1)
  box.foot:SetPoint("BOTTOMRIGHT", -1, 1)
  box.coins = ns.Skin.Icon(box.foot, "money", 12)
  box.coins:SetPoint("LEFT", 8, 0)
  box.money = Text(box.foot, 11, TEXT)
  box.money:SetPoint("LEFT", box.coins, "RIGHT", 6, 0)
  local clean = Text(box.foot, 10, TEXT)
  clean:SetPoint("RIGHT", -10, 0)
  clean:SetText("Clean Up")
  page.preview = box
  return box
end

local function Slot(box, i)
  local slot = box.slots[i]
  if slot then return slot end
  slot = CreateFrame("Frame", nil, box.grid)
  slot:SetSize(P.ICON, P.ICON)
  ns.Skin.Panel(slot, { color = { 0.05, 0.07, 0.12, 1 }, borderColor = { 0.20, 0.45, 0.85, 1 } })
  slot.icon = slot:CreateTexture(nil, "ARTWORK")
  slot.icon:SetPoint("TOPLEFT", 1, -1)
  slot.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  slot.num = Text(slot, 8, TEXT, "RIGHT")
  slot.num:SetPoint("BOTTOMRIGHT", -1, 1)
  box.slots[i] = slot
  return slot
end

local function PaintPreview()
  local box = page.preview
  if not box then return end
  local s = Settings()
  local bags = Module()
  local snap = bags.Snapshot and bags.Snapshot(60) or { counts = {}, items = {}, used = 0, total = 0 }
  ns.Skin.SetPanelColor(box, { 0.03, 0.03, 0.05, s.bgAlpha or 0.94 })
  local px = ns.Media.Pixel() * math.max(s.borderSize or 1, 1)
  for side, edge in pairs(box.borderEdges or {}) do
    if type(side) == "string" then
      if side == "TOP" or side == "BOTTOM" then edge:SetHeight(px) else edge:SetWidth(px) end
      edge:SetShown((s.borderSize or 1) > 0)
    end
  end
  ns.Skin.ShapePanel(box)   -- the rounded corners' curved edge follows the border

  local y = -P.HEAD
  local searching = s.showSearch ~= false
  box.search:SetShown(searching)
  box.count:ClearAllPoints()
  box.count:SetText(("%d / %d"):format(snap.used or 0, snap.total or 0))
  box.count:SetShown(s.showCount ~= false)
  if searching then
    box.search:ClearAllPoints()
    box.search:SetPoint("TOPLEFT", 6, y)
    box.search:SetPoint("TOPRIGHT", -6, y)
    box.searchHint:ClearAllPoints()
    if s.countSide == "left" then
      box.count:SetPoint("LEFT", box.search, "LEFT", 6, 0)
      box.searchHint:SetPoint("LEFT", 52, 0)
    else
      box.count:SetPoint("RIGHT", box.search, "RIGHT", -6, 0)
      box.searchHint:SetPoint("LEFT", 6, 0)
    end
    y = y - P.SEARCH
  else
    box.count:SetPoint("TOPRIGHT", box, "TOPRIGHT", -24, -8)
  end

  local sides = s.showCategories ~= false
  box.side:SetShown(sides)
  box.side:ClearAllPoints()
  box.side:SetPoint("TOPLEFT", 6, y - 4)
  box.side:SetSize(P.SIDE, 6 * 22)
  for _, row in ipairs(box.cats) do
    row.num:SetText(tostring(snap.counts[row.key] or 0))
    local a = ns.Colors.ui.accent
    if row.key == "all" then
      ns.Skin.SetPanelColor(row, { a[1] * 0.35, a[2] * 0.35, a[3] * 0.35, 1 })
      ns.Skin.SetBorderColor(row, a)
    else
      ns.Skin.SetPanelColor(row, { 0.08, 0.08, 0.11, 1 })
      ns.Skin.SetBorderColor(row, ns.Colors.ui.border)
    end
  end
  local gridX = sides and (6 + P.SIDE + 4) or 6
  local cols = math.max(1, math.floor((box:GetWidth() - gridX - 6 + P.GAP) / (P.ICON + P.GAP)))
  local rows = math.max(1, math.floor((232 - P.HEAD - (searching and P.SEARCH or 0) - P.FOOT - 10 + P.GAP) / (P.ICON + P.GAP)))
  box.grid:ClearAllPoints()
  box.grid:SetPoint("TOPLEFT", gridX, y - 4)
  box.grid:SetSize(cols * (P.ICON + P.GAP), rows * (P.ICON + P.GAP))
  local n = cols * rows
  for i = 1, n do
    local slot = Slot(box, i)
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    slot:ClearAllPoints()
    slot:SetPoint("TOPLEFT", col * (P.ICON + P.GAP), -row * (P.ICON + P.GAP))
    local item = snap.items[i]
    slot.icon:SetTexture(item and item.icon or nil)
    slot.num:SetText(item and (item.count or 0) > 1 and item.count or "")
    slot:Show()
  end
  for i = n + 1, #box.slots do box.slots[i]:Hide() end

  local currency = s.showCurrency ~= false
  box.money:SetShown(currency)
  box.coins:SetShown(currency)
  if currency then
    local ok, copper = pcall(GetMoney or function() return 0 end)
    copper = ok and ns.Secrets.Number(copper) or 0
    box.money:SetFont(ns.Media.Role("general"), s.currencyTextSize or 12, "")
    box.money:SetText(bags.MoneyText and bags.MoneyText(copper) or "")
  end
end

---------------------------------------------------------------------------
-- Presets: named copies of the bag window's look, kept for every character
---------------------------------------------------------------------------

local function Presets()
  ForeverUIDB.bagPresets = ForeverUIDB.bagPresets or {}
  local presets = ForeverUIDB.bagPresets
  if not presets.Default then
    presets.Default = {}
    for _, key in ipairs(Module().PRESET_KEYS) do
      local v = Module().defaults[key]
      presets.Default[key] = v
    end
  end
  return presets
end

local function Refresh()
  local bags = Module()
  if bags and bags.Refresh then bags:Refresh() end
  if ns.RefreshOptions then ns.RefreshOptions() end
end

function ns.LoadBagPreset(name)
  local preset = Presets()[name]
  if not preset then return false end
  local s = Settings()
  for _, key in ipairs(Module().PRESET_KEYS) do
    if preset[key] ~= nil then s[key] = preset[key] end
  end
  s.preset = name
  Refresh()
  return true
end

function ns.SaveBagPreset(name)
  name = name or Settings().preset or "Default"
  local copy = {}
  for _, key in ipairs(Module().PRESET_KEYS) do copy[key] = Settings()[key] end
  Presets()[name] = copy
  Settings().preset = name
  Refresh()
  return name
end

function ns.DuplicateBagPreset()
  local base = Settings().preset or "Default"
  local n, name = 2
  repeat
    name = ("%s %d"):format(base:gsub("%s%d+$", ""), n)
    n = n + 1
  until not Presets()[name]
  return ns.SaveBagPreset(name)
end

function ns.DeleteBagPreset()
  local name = Settings().preset or "Default"
  if name == "Default" then
    ns.Print("the Default preset stays; make a copy with Duplicate.")
    return false
  end
  Presets()[name] = nil
  ns.LoadBagPreset("Default")
  return true
end

function ns.RestoreBagDefaults()
  local s = Settings()
  for _, key in ipairs(Module().PRESET_KEYS) do
    s[key] = Module().defaults[key]
  end
  Refresh()
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local function RefreshPage()
  for _, entry in ipairs(page.entries or {}) do
    entry.refresh()
  end
  PaintPreview()
end

local function Build(parent, x, y)
  local kit = ns.OptionsKit
  page = { entries = {} }
  local root = CreateFrame("Frame", nil, parent)
  root:SetPoint("TOPLEFT", x, y)
  root:SetSize(W, 760)

  local lead = Text(root, 12, DIM)
  lead:SetPoint("TOPLEFT", 0, -8)
  lead:SetText("Basic settings for your bag window.")
  local restore = kit.Button(root, 160, "Restore Defaults", function() ns.RestoreBagDefaults() end)
  restore:SetHeight(26)
  restore:SetPoint("TOPRIGHT", 0, -2)

  -- Left: the window, the search bar, the currency line.
  local window = Card(root, 0, -36, LEFT_W, 272, "bags", "Bag Window",
    "Adjust the size and behavior of the Combined Backpack.")
  local wy = window.top
  wy = Row(window, "slider", wy, { sliderWidth = 96, key = "scale", label = "Scale", min = 0.5, max = 1.5, step = 0.05, format = Percent })
  wy = Row(window, "slider", wy, { sliderWidth = 96, key = "bgAlpha", label = "Background opacity", min = 0.2, max = 1, step = 0.05, format = Percent })
  wy = Row(window, "slider", wy, { sliderWidth = 96, key = "borderSize", label = "Border thickness", min = 0, max = 4, step = 1,
    format = function(v) return Plain(v) .. " px" end })
  wy = Row(window, "checkbox", wy, { key = "locked", label = "Lock window position" })
  wy = Row(window, "checkbox", wy, { key = "rememberCategory", label = "Remember category on open" })
  wy = Row(window, "checkbox", wy, { key = "restoreCategory", label = "Open to last used category" })
  Row(window, "checkbox", wy, { key = "animate", label = "Play open/close animation" })

  local searchTop = -36 - 272 - 10
  local search = Card(root, 0, searchTop, LEFT_W, 178, "search", "Search Bar", "Customize the search bar.")
  local sy = search.top
  sy = Row(search, "checkbox", sy, { key = "showSearch", label = "Show search bar" })
  sy = Row(search, "checkbox", sy, { key = "showCount", label = "Show item count" })
  sy = Row(search, "cycler", sy, { key = "countSide", label = "Item count sits",
    choices = function() return { { label = "Right", value = "right" }, { label = "Left", value = "left" } } end })
  Row(search, "checkbox", sy, { key = "showCategories", label = "Use category filter buttons" })

  local moneyTop = searchTop - 178 - 10
  local money = Card(root, 0, moneyTop, LEFT_W, 208, "money", "Currency Bar",
    "Display and customize the currency display.")
  local my = money.top
  my = Row(money, "checkbox", my, { key = "showCurrency", label = "Show currency bar" })
  my = Row(money, "checkbox", my, { key = "currencyClassColor", label = "Use class color" })
  my = Row(money, "checkbox", my, { key = "coinIcons", label = "Show coin icons" })
  my = Row(money, "slider", my, { key = "currencyTextSize", label = "Text size", min = 8, max = 20, step = 1, format = Plain })
  Row(money, "slider", my, { key = "currencyIconSize", label = "Icon size", min = 8, max = 24, step = 1, format = Plain })

  -- Right: the preview, presets, and whose bags these are.
  local preview = Card(root, RIGHT_X, -36, RIGHT_W, 300, "eye", "Preview",
    "A live preview of your Combined Backpack.")
  local box = BuildPreview(preview, RIGHT_W - 20)
  box:SetPoint("TOPLEFT", 10, preview.top)

  local presetTop = -36 - 300 - 10
  local presets = Card(root, RIGHT_X, presetTop, RIGHT_W, 126, "star", "Presets",
    "Save and load your bag layout and settings.")
  local picker = { key = "preset", label = "Preset", store = function() return Settings() end,
    choices = function()
      local list = {}
      for name in pairs(Presets()) do list[#list + 1] = name end
      table.sort(list, function(a, b)
        if a == "Default" then return true elseif b == "Default" then return false end
        return a < b
      end)
      local out = {}
      for _, name in ipairs(list) do out[#out + 1] = { label = name, value = name } end
      return out
    end,
    apply = function() ns.LoadBagPreset(Settings().preset or "Default") end }
  local py = Row(presets, "cycler", presets.top, picker)
  local bw = math.floor((RIGHT_W - 24 - 12) / 3)
  for i, spec in ipairs({
    { "Save", function() ns.Print(("saved the bag preset \"%s\"."):format(ns.SaveBagPreset())) end },
    { "Duplicate", function() ns.Print(("made \"%s\"."):format(ns.DuplicateBagPreset())) end },
    { "Delete", function() ns.DeleteBagPreset() end },
  }) do
    local b = kit.Button(presets, bw, spec[1], spec[2])
    b:SetHeight(24)
    b:SetPoint("TOPLEFT", 12 + (i - 1) * (bw + 6), py - 4)
  end

  local whichTop = presetTop - 126 - 10
  local which = Card(root, RIGHT_X, whichTop, RIGHT_W, 158, "bags", "Whose Bags")
  local wy2 = which.top
  wy2 = Row(which, "checkbox", wy2, { key = "ownWindow", label = "ForeverUI's own bag window" })
  wy2 = Row(which, "checkbox", wy2, { key = "skin", reload = true, label = "Match Blizzard's bag windows",
    desc = "Only their clothes change; off takes a /reload." })
  local note = Text(which, 10, DIM)
  note:SetPoint("TOPLEFT", 12, wy2 - 2)
  note:SetPoint("RIGHT", which, "RIGHT", -10, 0)
  note:SetText("Off, Blizzard's own bags come back.")

  local height = -(moneyTop - 208) + 10
  root:SetHeight(height)
  RefreshPage()
  return height
end

function ns.BagsPageSchema()
  return {
    { type = "heading", label = "Bags", subtitle = "Your Combined Backpack, your way." },
    { type = "custom", bare = true, build = Build, refresh = RefreshPage },
  }
end
