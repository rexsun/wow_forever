local _, ns = ...

-- The Profiles page: a list on the left, the chosen profile on the right,
-- export and import along the bottom. Laid out from the owner's mock-up.
--
-- Two things in the mock-up cannot exist in WoW and are left out on purpose:
-- addons cannot read or write files, so there is no "export to folder",
-- "import files" or drag-and-drop -- profiles travel as text you copy and
-- paste -- and there is no network, so "Shared with me" is "Imported":
-- profiles somebody sent you as text and you pasted in.

local W = 636                 -- the page's usable width (the painted board)
local LIST_W, GAP = 372, 12
local DETAIL_W = W - LIST_W - GAP
local ROW_H, HEAD_H = 26, 26
local MIN_ROWS = 10

-- The painted window's palette: dark panels, brass edges, purple for what
-- is chosen.
local ACCENT = { 0.74, 0.58, 1.00 }
local GOLD   = { 1.00, 0.82, 0.25 }
local TEXT   = { 0.92, 0.92, 0.94 }
local DIM    = { 0.70, 0.66, 0.60 }
local RED    = { 0.92, 0.30, 0.30 }
local EDGE   = { 0.66, 0.50, 0.26, 1 }
local FILL   = { 0.06, 0.05, 0.07, 0.90 }
local ROW_ALT = { 1, 1, 1, 0.03 }
local ROW_SEL = { 0.32, 0.14, 0.62, 0.60 }

local ROLE_LOOK = {
  healer = { label = "Healer",    icon = "heal", color = { 0.30, 0.85, 0.40 } },
  tank   = { label = "Tank",      icon = "tank", color = { 1.00, 0.55, 0.15 } },
  dps    = { label = "Damage",    icon = "dps",  color = { 0.66, 0.42, 1.00 } },
  all    = { label = "All Roles", logo = true,   color = ACCENT },
}

local TABS = {
  { key = "all",      label = "All Profiles", icon = "profiles" },
  { key = "mine",     label = "Mine",         icon = "char" },
  { key = "imported", label = "Imported",     icon = "download" },
  { key = "defaults", label = "Defaults",     icon = "star" },
}

local view = {
  tab = "all",
  sort = "name",
  ascending = true,
  search = "",
  selected = nil,         -- a profile name, or "preset:<key>" on the Defaults tab
  editing = false,
  confirmDelete = nil,
}
ns.profilesView = view    -- for the tests

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

local function IsPreset(key)
  return type(key) == "string" and key:find("^preset:") ~= nil
end

-- The rows the list shows right now, filtered and sorted.
function ns.ProfileRows()
  local rows = {}
  local needle = view.search:lower()
  if view.tab == "defaults" then
    for _, preset in ipairs(ns.PROFILE_PRESETS) do
      if needle == "" or preset.name:lower():find(needle, 1, true) then
        rows[#rows + 1] = { key = "preset:" .. preset.key, name = preset.name, role = preset.role,
          version = ns.VERSION, modified = nil, preset = preset }
      end
    end
    return rows
  end
  for _, name in ipairs(ns.ProfileNames()) do
    local meta = ns.ProfileMeta(name)
    local keep = view.tab == "all"
      or (view.tab == "mine" and meta.source ~= "imported")
      or (view.tab == "imported" and meta.source == "imported")
    if keep and (needle == "" or name:lower():find(needle, 1, true)) then
      rows[#rows + 1] = { key = name, name = name, role = ns.ProfileRole(name),
        version = meta.version or "?", modified = meta.modified or 0, favorite = meta.favorite }
    end
  end
  local ROLE_ORDER = { healer = 1, tank = 2, dps = 3, all = 4 }
  table.sort(rows, function(a, b)
    -- Favourites first, whatever the sort.
    if (a.favorite and true or false) ~= (b.favorite and true or false) then
      return a.favorite and true or false
    end
    local x, y
    if view.sort == "role" then
      x, y = ROLE_ORDER[a.role] or 9, ROLE_ORDER[b.role] or 9
    elseif view.sort == "version" then
      x, y = a.version, b.version
    elseif view.sort == "modified" then
      x, y = a.modified or 0, b.modified or 0
    else
      x, y = a.name:lower(), b.name:lower()
    end
    if x == y then
      return a.name:lower() < b.name:lower()
    end
    if view.ascending then
      return x < y
    end
    return x > y
  end)
  return rows
end

local function Date(t, withTime)
  if not t or t == 0 or not date then
    return "-"
  end
  return date(withTime and "%b %d, %Y  %H:%M" or "%b %d, %Y", t)
end

---------------------------------------------------------------------------
-- Drawing helpers
---------------------------------------------------------------------------

-- Shared with the other hand-built pages (GUI.lua); looked up when called,
-- because this file loads before the kit.
local function Text(...) return ns.OptionsKit.PageText(...) end

local function Box(parent, w, h, fill, edge)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  ns.Skin.Panel(f, { color = fill or FILL, borderColor = edge or EDGE })
  return f
end

-- A flat button with a glyph and a label. `style`: nil, "primary", "danger".
local function Button(parent, w, h, label, icon, style, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  ns.Skin.Button(b, { role = "general" })
  if icon then
    b.glyph = ns.Skin.Icon(b, icon, 14, style == "danger" and RED or TEXT, "OVERLAY")
  end
  -- The glyph sits just left of the words, so it moves whenever they change:
  -- placed once, a longer label ran straight under it.
  local setText = b.SetText
  function b:SetText(text)
    setText(self, text)
    if self.glyph then
      self.glyph:ClearAllPoints()
      self.glyph:SetPoint("RIGHT", self.text, "CENTER", -(self.text:GetStringWidth() or 40) / 2 - 6, 0)
    end
  end
  b:SetText(label)
  local function Paint(self, hot)
    if style == "primary" then
      ns.Skin.SetPanelColor(self, hot and { 0.40, 0.20, 0.74, 1 } or { 0.28, 0.12, 0.56, 1 })
      ns.Skin.SetBorderColor(self, ACCENT)
    elseif style == "danger" then
      ns.Skin.SetPanelColor(self, hot and { 0.30, 0.06, 0.08, 1 } or { 0.16, 0.03, 0.05, 1 })
      ns.Skin.SetBorderColor(self, RED)
      self.text:SetTextColor(RED[1], RED[2], RED[3])
    end
  end
  if style then
    b:HookScript("OnEnter", function(self) Paint(self, true) end)
    b:HookScript("OnLeave", function(self) Paint(self, false) end)
    Paint(b, false)
  end
  b.Repaint = Paint
  b:SetScript("OnClick", onClick)
  return b
end

-- A role as the list and the detail show it: glyph, or the infinity mark for
-- "All Roles", and the word.
local function SetRoleLook(icon, logo, label, role)
  local look = ROLE_LOOK[role] or ROLE_LOOK.all
  if look.logo then
    icon:Hide()
    logo:Show()
  else
    logo:Hide()
    ns.Skin.SetIcon(icon, look.icon, look.color)
    icon:Show()
  end
  if label then
    label:SetText(look.label)
  end
end

local function Logo(parent, w, h)
  local tex = parent:CreateTexture(nil, "ARTWORK")
  tex:SetTexture(ns.MEDIA_PATH .. "foreverui-logo")
  tex:SetSize(w, h)
  return tex
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local page    -- the parts, built once

local function Select(key)
  view.selected = key
  view.editing = false
  view.confirmDelete = nil
end

local function Refresh() end   -- replaced below once the page exists
local function RefreshPage()
  Refresh()
end

local function BuildTabs(parent, y)
  page.tabs = {}
  local x = 0
  for _, spec in ipairs(TABS) do
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(spec.key == "all" and 118 or 96, 30)
    tab:SetPoint("TOPLEFT", x, y)
    tab.glyph = ns.Skin.Icon(tab, spec.icon, 16, TEXT, "OVERLAY")
    tab.glyph:SetPoint("LEFT", 8, 0)
    tab.label = Text(tab, 13, TEXT)
    tab.label:SetPoint("LEFT", 30, 0)
    tab.label:SetText(spec.label)
    tab.line = tab:CreateTexture(nil, "OVERLAY")
    tab.line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    tab.line:SetPoint("BOTTOMLEFT")
    tab.line:SetPoint("BOTTOMRIGHT")
    tab.line:SetHeight(2)
    tab.key = spec.key
    tab:SetScript("OnClick", function()
      view.tab = spec.key
      Select(nil)
      RefreshPage()
    end)
    page.tabs[#page.tabs + 1] = tab
    x = x + tab:GetWidth() + 4
  end

  -- Search, then New Profile, on the right.
  local newButton = Button(parent, 118, 28, "New Profile", "plus", "primary", function()
    local name = ns.NewProfile()
    view.tab = "mine"
    Select(name)
    view.editing = true   -- a new profile wants a name straight away
    RefreshPage()
  end)
  newButton:SetPoint("TOPRIGHT", parent, "TOPLEFT", W, y)
  page.newButton = newButton

  local search = CreateFrame("EditBox", nil, parent)
  search:SetSize(W - x - 118 - 30, 26)
  search:SetPoint("TOPRIGHT", newButton, "TOPLEFT", -8, -1)
  search:SetAutoFocus(false)
  ns.Media.SetFont(search, "general")
  ns.Skin.Panel(search, { color = { 0.04, 0.03, 0.05, 0.94 }, borderColor = EDGE })
  search:SetTextInsets(24, 6, 0, 0)
  local lens = ns.Skin.Icon(search, "search", 12, DIM, "OVERLAY")
  lens:SetPoint("LEFT", 7, 0)
  search.hint = Text(search, 12, DIM)
  search.hint:SetPoint("LEFT", 24, 0)
  search.hint:SetText("Search profiles...")
  search:SetScript("OnTextChanged", function(self)
    view.search = self:GetText() or ""
    self.hint:SetShown(view.search == "")
    RefreshPage()
  end)
  search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  page.search = search

  local rule = parent:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 0.6)
  rule:SetPoint("TOPLEFT", 0, y - 31)
  rule:SetSize(W, 1)
end

local COLUMNS = {
  { key = "star",     label = "",              x = 6,   w = 22 },
  { key = "name",     label = "Name",          x = 32,  w = 130 },
  { key = "role",     label = "Role",          x = 166, w = 92 },
  { key = "version",  label = "Version",       x = 260, w = 44 },
  { key = "modified", label = "Last Modified", x = 300, w = 72 },
}

local function BuildList(parent, y)
  local list = Box(parent, LIST_W, HEAD_H + ROW_H * MIN_ROWS + 2)
  list:SetPoint("TOPLEFT", 0, y)
  page.list = list

  page.headers = {}
  for _, col in ipairs(COLUMNS) do
    if col.label ~= "" then
      local head = CreateFrame("Button", nil, list)
      head:SetSize(col.w, HEAD_H)
      head:SetPoint("TOPLEFT", col.x, -1)
      head.text = Text(head, 12, DIM)
      head.text:SetPoint("LEFT", 0, 0)
      head:SetScript("OnClick", function()
        if view.sort == col.key then
          view.ascending = not view.ascending
        else
          view.sort, view.ascending = col.key, col.key ~= "modified"
        end
        RefreshPage()
      end)
      head.col = col
      page.headers[#page.headers + 1] = head
    end
  end
  local rule = list:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 0.6)
  rule:SetPoint("TOPLEFT", 1, -HEAD_H)
  rule:SetSize(LIST_W - 2, 1)

  page.rows = {}
  page.empty = Text(list, 12, DIM, "CENTER")
  page.empty:SetPoint("TOP", list, "TOP", 0, -HEAD_H - 20)
end

local function Row(i)
  local row = page.rows[i]
  if row then
    return row
  end
  row = CreateFrame("Button", nil, page.list)
  row:SetSize(LIST_W - 2, ROW_H)
  row:SetPoint("TOPLEFT", 1, -HEAD_H - 1 - (i - 1) * ROW_H)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.star = CreateFrame("Button", nil, row)
  row.star:SetSize(20, 20)
  row.star:SetPoint("LEFT", 5, 0)
  row.star.glyph = ns.Skin.Icon(row.star, "star", 14, GOLD, "OVERLAY")
  row.star.glyph:SetPoint("CENTER")
  row.name = Text(row, 13, TEXT)
  row.name:SetPoint("LEFT", 31, 0)
  row.name:SetWidth(130)
  row.roleIcon = ns.Skin.Icon(row, "heal", 14, TEXT, "OVERLAY")
  row.roleIcon:SetPoint("LEFT", 166, 0)
  row.roleLogo = Logo(row, 22, 11)
  row.roleLogo:SetPoint("LEFT", 162, 0)
  row.role = Text(row, 12, TEXT)
  row.role:SetPoint("LEFT", 188, 0)
  row.version = Text(row, 12, DIM)
  row.version:SetPoint("LEFT", 260, 0)
  row.modified = Text(row, 12, DIM)
  row.modified:SetPoint("LEFT", 300, 0)
  -- "in use" goes after the name, where there is room, not over the date.
  row.active = Text(row, 10, ACCENT)
  row.active:SetPoint("LEFT", row.name, "LEFT", 0, 0)
  row:SetScript("OnClick", function(self)
    Select(self.key)
    RefreshPage()
  end)
  row:SetScript("OnEnter", function(self) if self.key ~= view.selected then self.bg:SetColorTexture(1, 1, 1, 0.06) end end)
  row:SetScript("OnLeave", function() RefreshPage() end)
  page.rows[i] = row
  return row
end

local function MetaRow(parent, y, label)
  local l = Text(parent, 12, DIM)
  l:SetPoint("TOPLEFT", 14, y)
  l:SetText(label)
  local v = Text(parent, 12, TEXT)
  v:SetPoint("TOPLEFT", 110, y)
  v:SetWidth(DETAIL_W - 124)
  return v
end

local NAMES = { "Skuri", "Kupho", "Shado", "Felo", "Elro", "Phal", "Isht", "Miss", "Adel",
  "Shur", "Emer", "Badw", "Vini", "Elec", "Gale" }

local function BuildDetail(parent, y)
  local d = Box(parent, DETAIL_W, 470)
  d:SetPoint("TOPLEFT", LIST_W + GAP, y)
  page.detail = d

  d.icon = ns.Skin.Icon(d, "heal", 34, TEXT, "OVERLAY")
  d.icon:SetPoint("TOPLEFT", 12, -12)
  d.logo = Logo(d, 44, 22)
  d.logo:SetPoint("TOPLEFT", 8, -18)
  d.title = Text(d, 18, TEXT)
  d.title:SetPoint("TOPLEFT", 58, -12)
  d.title:SetWidth(DETAIL_W - 96)
  d.subtitle = Text(d, 12, TEXT)
  d.subtitle:SetPoint("TOPLEFT", 58, -36)
  d.star = CreateFrame("Button", nil, d)
  d.star:SetSize(22, 22)
  d.star:SetPoint("TOPRIGHT", -10, -12)
  d.star.glyph = ns.Skin.Icon(d.star, "star", 18, GOLD, "OVERLAY")
  d.star.glyph:SetPoint("CENTER")
  d.star:SetScript("OnClick", function()
    if view.selected and not IsPreset(view.selected) then
      local meta = ns.ProfileMeta(view.selected)
      ns.SetProfileFavorite(view.selected, not meta.favorite)
      RefreshPage()
    end
  end)
  d.description = Text(d, 12, DIM)
  d.description:SetPoint("TOPLEFT", 14, -62)
  d.description:SetWidth(DETAIL_W - 28)
  d.description:SetJustifyV("TOP")

  -- Editing: a name and a description, in place.
  d.nameBox = CreateFrame("EditBox", nil, d)
  d.nameBox:SetSize(DETAIL_W - 110, 24)
  d.nameBox:SetPoint("TOPLEFT", 56, -10)
  d.nameBox:SetAutoFocus(false)
  ns.Media.SetFont(d.nameBox, "general")
  ns.Skin.Panel(d.nameBox, { color = { 0.04, 0.03, 0.05, 0.94 }, borderColor = ACCENT })
  d.nameBox:SetTextInsets(6, 6, 0, 0)
  d.descBox = CreateFrame("EditBox", nil, d)
  d.descBox:SetSize(DETAIL_W - 28, 24)
  d.descBox:SetPoint("TOPLEFT", 14, -60)
  d.descBox:SetAutoFocus(false)
  ns.Media.SetFont(d.descBox, "general")
  ns.Skin.Panel(d.descBox, { color = { 0.04, 0.03, 0.05, 0.94 }, borderColor = EDGE })
  d.descBox:SetTextInsets(6, 6, 0, 0)
  d.descHint = Text(d.descBox, 11, DIM)
  d.descHint:SetPoint("LEFT", 6, 0)
  d.descHint:SetText("A line about what this profile is for")
  d.descBox:SetScript("OnTextChanged", function(self) d.descHint:SetShown((self:GetText() or "") == "") end)

  local divider = d:CreateTexture(nil, "ARTWORK")
  divider:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 0.5)
  divider:SetPoint("TOPLEFT", 12, -96)
  divider:SetSize(DETAIL_W - 24, 1)

  d.meta = {
    version  = MetaRow(d, -106, "Version:"),
    modified = MetaRow(d, -124, "Last modified:"),
    created  = MetaRow(d, -142, "Created:"),
    author   = MetaRow(d, -160, "Author:"),
    basedOn  = MetaRow(d, -178, "Based on:"),
  }

  local previewLabel = Text(d, 12, TEXT)
  previewLabel:SetPoint("TOPLEFT", 14, -204)
  previewLabel:SetText("Preview")
  d.preview = Box(d, DETAIL_W - 28, 112, { 0, 0, 0, 0.5 }, { 0.40, 0.30, 0.16, 1 })
  d.preview:SetPoint("TOPLEFT", 14, -222)
  d.cells = {}
  local cols, rows, gap = 3, 5, 3
  local cw = math.floor((DETAIL_W - 28 - 12 - (cols - 1) * gap) / cols)
  local ch = 17
  for r = 1, rows do
    for c = 1, cols do
      local i = (r - 1) * cols + c
      local cell = d.preview:CreateTexture(nil, "ARTWORK")
      cell:SetPoint("TOPLEFT", 6 + (c - 1) * (cw + gap), -6 - (r - 1) * (ch + gap))
      cell:SetSize(cw, ch)
      local label = Text(d.preview, 10, { 1, 1, 1 }, "CENTER")
      label:SetPoint("CENTER", cell, "CENTER", 0, 1)
      label:SetText(NAMES[i])
      local hp = d.preview:CreateTexture(nil, "OVERLAY")
      hp:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", 1, 1)
      hp:SetSize(math.max(2, (cw - 2) * (0.35 + ((i * 37) % 60) / 100)), 2)
      hp:SetColorTexture(0.20, 0.60, 1.00, 1)
      d.cells[i] = cell
    end
  end

  -- Actions.
  d.apply = Button(d, DETAIL_W - 28, 32, "Apply Profile", "play", "primary", function()
    local key = view.selected
    if IsPreset(key) then
      local name = ns.CreateFromPreset(key:sub(8))
      if name then
        view.tab = "mine"
        Select(name)
        ns.Print(("made profile \"%s\" -- Apply Profile to use it."):format(name))
      end
    elseif key then
      ns.UseProfile(key)
    end
    RefreshPage()
  end)
  d.apply:SetPoint("TOPLEFT", 14, -346)

  local half = math.floor((DETAIL_W - 28 - 8) / 2)
  d.edit = Button(d, half, 28, "Edit", "edit", nil, function()
    if view.editing then
      -- Save.
      local key = view.selected
      local newName = (d.nameBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
      local meta = ns.ProfileMeta(key)
      if meta then
        meta.description = d.descBox:GetText() or ""
      end
      if newName ~= "" and newName ~= key then
        local ok, err = ns.RenameProfile(key, newName)
        if ok then
          view.selected = newName
        else
          ns.Print(err)
        end
      end
      view.editing = false
    else
      view.editing = true
    end
    RefreshPage()
  end)
  d.edit:SetPoint("TOPLEFT", 14, -384)
  d.duplicate = Button(d, half, 28, "Duplicate", "copy", nil, function()
    local copy = view.selected and not IsPreset(view.selected) and ns.DuplicateProfile(view.selected)
    if copy then
      Select(copy)
      if view.tab == "imported" then view.tab = "all" end
    end
    RefreshPage()
  end)
  d.duplicate:SetPoint("TOPLEFT", 14 + half + 8, -384)

  d.delete = Button(d, DETAIL_W - 28, 28, "Delete", "trash", "danger", function()
    local key = view.selected
    if not key or IsPreset(key) then
      return
    end
    if view.confirmDelete ~= key then
      view.confirmDelete = key          -- a second click, so one slip loses nothing
      RefreshPage()
      return
    end
    if ns.DeleteProfile(key) then
      Select(nil)
    else
      ns.Print("the Default profile can't be deleted.")
      view.confirmDelete = nil
    end
    RefreshPage()
  end)
  d.delete:SetPoint("TOPLEFT", 14, -420)
end

local function Card(parent, x, y, w, h, icon, title, sub)
  local card = Box(parent, w, h)
  card:SetPoint("TOPLEFT", x, y)
  local glyph = ns.Skin.Icon(card, icon, 26, ACCENT, "OVERLAY")
  glyph:SetPoint("TOPLEFT", 12, -12)
  local t = Text(card, 15, TEXT)
  t:SetPoint("TOPLEFT", 48, -10)
  t:SetText(title)
  local s = Text(card, 11, DIM)
  s:SetPoint("TOPLEFT", 48, -30)
  s:SetText(sub)
  return card
end

local function BuildTransfer(parent, y)
  local w = math.floor((W - GAP) / 2)
  local export = Card(parent, 0, y, w, 96, "upload", "Export Profiles", "Share your profiles or back them up.")
  page.exportSelected = Button(export, 158, 28, "Export Selected", "upload", nil, function()
    local key = view.selected
    if key and not IsPreset(key) then
      ns.ShowTextPopup(("Export \"%s\" -- copy this text"):format(key), ns.ExportProfile(key))
    else
      ns.Print("pick a profile in the list first.")
    end
  end)
  page.exportSelected:SetPoint("BOTTOMLEFT", 12, 12)
  local all = Button(export, 158, 28, "Export All", "upload", nil, function()
    ns.ShowTextPopup("Every profile -- copy this text to back them up", ns.ExportAllProfiles())
  end)
  all:SetPoint("BOTTOMLEFT", 12 + 158 + 8, 12)
  page.exportAll = all

  local import = Card(parent, w + GAP, y, w, 96, "download", "Import Profiles",
    "Paste one someone shared, or a backup.")
  page.importButton = Button(import, w - 24, 28, "Paste to Import", "download", nil, function()
    ns.ShowTextPopup("Paste a profile (or a backup), then Import", "", function(text)
      local names, err = ns.ImportProfilesAsNew(text)
      if not names then
        ns.Print(err)
        return
      end
      view.tab = "imported"
      Select(names[1])
      ns.Print(("imported %d profile%s: %s. Nothing you had was changed."):format(#names,
        #names == 1 and "" or "s", table.concat(names, ", ")))
      RefreshPage()
    end)
  end)
  page.importButton:SetPoint("BOTTOMLEFT", 12, 12)

  local note = Text(parent, 11, DIM)
  note:SetPoint("TOPLEFT", 0, y - 104)
  note:SetWidth(W)
  note:SetText("WoW addons can't read or write files, so profiles travel as text: export copies a block of "
    .. "text you can send anyone; import pastes one in. Each character remembers the profile it used last.")
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

function Refresh()
  if not page then
    return
  end
  local active = ns.ActiveProfileName()

  for _, tab in ipairs(page.tabs) do
    local on = tab.key == view.tab
    tab.line:SetShown(on)
    tab.label:SetTextColor(on and ACCENT[1] or TEXT[1], on and ACCENT[2] or TEXT[2], on and ACCENT[3] or TEXT[3])
    ns.Skin.SetIcon(tab.glyph, tab.glyph.iconName, on and ACCENT or TEXT)
  end
  for _, head in ipairs(page.headers) do
    local arrow = view.sort == head.col.key and (view.ascending and "  ^" or "  v") or ""
    head.text:SetText(head.col.label .. arrow)
  end

  local rows = ns.ProfileRows()
  -- Keep a selection: the active profile, else the first row.
  local found = false
  for _, r in ipairs(rows) do
    if r.key == view.selected then found = true end
  end
  if not found then
    view.selected = nil
    for _, r in ipairs(rows) do
      if r.key == active then view.selected = r.key end
    end
    view.selected = view.selected or (rows[1] and rows[1].key)
  end

  for i, r in ipairs(rows) do
    local row = Row(i)
    row.key = r.key
    row:Show()
    local selected = r.key == view.selected
    if selected then
      row.bg:SetColorTexture(ROW_SEL[1], ROW_SEL[2], ROW_SEL[3], ROW_SEL[4])
    elseif i % 2 == 0 then
      row.bg:SetColorTexture(ROW_ALT[1], ROW_ALT[2], ROW_ALT[3], ROW_ALT[4])
    else
      row.bg:SetColorTexture(0, 0, 0, 0)
    end
    row.name:SetText(r.key == active and (r.name .. "  |cff4dc3ff(in use)|r") or r.name)
    SetRoleLook(row.roleIcon, row.roleLogo, row.role, r.role)
    row.version:SetText(r.version or "")
    row.modified:SetText(r.preset and "built in" or Date(r.modified))
    row.active:SetText("")
    row.star:SetShown(not r.preset)
    ns.Skin.SetIcon(row.star.glyph, "star", r.favorite and GOLD or { 0.35, 0.38, 0.45, 1 })
    row.star:SetScript("OnClick", function()
      ns.SetProfileFavorite(r.key, not r.favorite)
      RefreshPage()
    end)
  end
  for i = #rows + 1, #page.rows do
    page.rows[i]:Hide()
  end
  page.list:SetHeight(HEAD_H + 2 + ROW_H * math.max(MIN_ROWS, #rows))
  page.empty:SetShown(#rows == 0)
  page.empty:SetText(view.tab == "imported" and "Nothing imported yet. Paste a profile below."
    or "No profiles match.")

  -- The detail panel.
  local d = page.detail
  local key = view.selected
  local preset = IsPreset(key) and ns.ProfilePreset(key:sub(8))
  d:SetShown(key ~= nil)
  if not key then
    return
  end
  local role, title, meta
  if preset then
    role, title = preset.role, preset.name
    meta = { version = ns.VERSION, description = preset.description, author = "ForeverUI",
      basedOn = "Standard" }
  else
    role, title, meta = ns.ProfileRole(key), key, ns.ProfileMeta(key)
  end
  local look = ROLE_LOOK[role] or ROLE_LOOK.all
  SetRoleLook(d.icon, d.logo, nil, role)
  d.title:SetText(title)
  d.subtitle:SetText(preset and "Built-in starting point" or (look.label == "All Roles" and "All-roles profile"
    or (look.label .. " profile")))
  d.star:SetShown(not preset)
  ns.Skin.SetIcon(d.star.glyph, "star", (meta.favorite and GOLD) or { 0.35, 0.38, 0.45, 1 })
  d.description:SetText(meta.description ~= "" and meta.description
    or (preset and "" or "No description yet. Edit to add one."))

  local editing = view.editing and not preset
  d.title:SetShown(not editing)
  d.description:SetShown(not editing)
  d.nameBox:SetShown(editing)
  d.descBox:SetShown(editing)
  if editing and not d.nameBox:HasFocus() and not d.descBox:HasFocus() then
    d.nameBox:SetText(key)
    d.descBox:SetText(meta.description or "")
  end

  d.meta.version:SetText(meta.version or "-")
  d.meta.modified:SetText(preset and "-" or Date(meta.modified, true))
  d.meta.created:SetText(preset and "-" or Date(meta.created))
  d.meta.author:SetText((meta.author == ns.MetaAuthor()) and ("You (" .. meta.author .. ")") or (meta.author or "-"))
  d.meta.basedOn:SetText(meta.basedOn or (key == "Default" and "Standard") or "-")

  local c = look.color
  for i, cell in ipairs(d.cells) do
    local shade = 0.55 + (i % 3) * 0.12
    cell:SetColorTexture(c[1] * shade, c[2] * shade, c[3] * shade, 1)
  end

  -- Buttons say what they will do for THIS row.
  if preset then
    d.apply:SetText("Make a Profile from This")
  elseif key == active then
    d.apply:SetText("In Use")
  else
    d.apply:SetText("Apply Profile")
  end
  d.apply:SetEnabled(preset ~= nil and preset ~= false or key ~= active)
  d.edit:SetShown(not preset)
  d.duplicate:SetShown(not preset)
  d.delete:SetShown(not preset and key ~= "Default")
  d.edit:SetText(editing and "Save" or "Edit")
  d.delete:SetText(view.confirmDelete == key and "Click again to delete" or "Delete")
end


---------------------------------------------------------------------------
-- The schema: a title, and the page drawing itself
---------------------------------------------------------------------------

function ns.ProfilesPageSchema()
  return {
    { type = "heading", label = "Profiles", subtitle = "Save, share and manage your ForeverUI profiles." },
    { type = "custom", bare = true, build = function(parent, x, y)
      page = {}
      local root = CreateFrame("Frame", nil, parent)
      root:SetPoint("TOPLEFT", x, y)
      root:SetSize(W, 700)
      page.root = root
      BuildTabs(root, 0)
      BuildList(root, -44)
      BuildDetail(root, -44)
      BuildTransfer(root, -44 - 470 - 14)
      Refresh()
      -- Tabs, list and detail, the export and import cards, the note under
      -- them, and room to scroll the last of it clear of the footer.
      return 44 + 470 + 14 + 96 + 40
    end,
      refresh = function() Refresh() end },
  }
end
