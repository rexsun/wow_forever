local _, ns = ...

-- The Keybinds page, from the owner's mock-up: what binding does on the
-- left, and the sets you have saved on the right.
--
-- Two things in the mock-up cannot exist and are honest here instead: an
-- addon cannot read or write files, so "Export to File" and "Import from
-- File" are export and import as TEXT you copy and paste, and there is no
-- community server behind "Browse Presets", so there is none.

local W = 636
local LEFT_W, GAP = 340, 14
local RIGHT_W = W - LEFT_W - GAP

local ACCENT = { 0.74, 0.58, 1.00 }
local TEXT   = { 0.92, 0.92, 0.94 }
local DIM    = { 0.70, 0.66, 0.60 }
local GREEN  = { 0.45, 0.85, 0.55 }
local RED    = { 0.92, 0.36, 0.36 }
local EDGE   = { 0.66, 0.50, 0.26, 1 }
local FILL   = { 0.06, 0.05, 0.07, 0.90 }

local page = {}

local function AB()
  return ns.GetModule("ActionBars")
end

local function Settings()
  return ns.db.modules.ActionBars
end

-- Shared with the other hand-built pages (GUI.lua); looked up when called,
-- because this file loads before the kit.
local function Text(...) return ns.OptionsKit.PageText(...) end

local function Card(parent, x, y, w, h, icon, title)
  local card = CreateFrame("Frame", nil, parent)
  card:SetSize(w, h)
  card:SetPoint("TOPLEFT", x, y)
  ns.Skin.Panel(card, { color = FILL, borderColor = EDGE })
  local glyph = ns.Skin.Icon(card, icon, 14, ACCENT, "OVERLAY")
  glyph:SetPoint("TOPLEFT", 10, -10)
  local head = Text(card, 13, TEXT)
  head:SetPoint("LEFT", glyph, "RIGHT", 8, 0)
  head:SetText(title)
  card.head = head
  local rule = card:CreateTexture(nil, "ARTWORK")
  rule:SetPoint("TOPLEFT", 10, -28)
  rule:SetPoint("TOPRIGHT", -10, -28)
  rule:SetHeight(ns.Media.Pixel())
  rule:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 0.45)
  return card
end

-- A big button with a glyph over a title and a line of explanation.
local function BigButton(parent, x, y, w, h, icon, title, note, colour, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  b:SetPoint("TOPLEFT", x, y)
  ns.Skin.Panel(b, { color = { 0.09, 0.08, 0.12, 1 }, borderColor = { 0.30, 0.26, 0.36, 1 } })
  local glyph = ns.Skin.Icon(b, icon, 16, colour or ACCENT, "OVERLAY")
  glyph:SetPoint("TOPLEFT", 10, -10)
  b.glyph = glyph
  local head = Text(b, 12, TEXT)
  head:SetPoint("TOPLEFT", 32, -10)
  head:SetPoint("RIGHT", b, "RIGHT", -8, 0)
  head:SetText(title)
  b.head = head
  local sub = Text(b, 9, DIM)
  sub:SetPoint("TOPLEFT", 32, -26)
  sub:SetPoint("RIGHT", b, "RIGHT", -8, 0)
  sub:SetText(note)
  b.sub = sub
  b:SetScript("OnEnter", function(self) ns.Skin.SetBorderColor(self, colour or ACCENT) end)
  b:SetScript("OnLeave", function(self) ns.Skin.SetBorderColor(self, { 0.30, 0.26, 0.36, 1 }) end)
  b:SetScript("OnClick", onClick)
  return b
end

-- A switch with its explanation beside it and a "?" that says more.
local function Behaviour(parent, y, label, note, help, key, onChange)
  local box = CreateFrame("CheckButton", nil, parent)
  box:SetSize(18, 18)
  box:SetPoint("TOPLEFT", 12, y)
  ns.Skin.Checkbox(box)
  local title = Text(parent, 12, TEXT)
  title:SetPoint("LEFT", box, "RIGHT", 8, 0)
  title:SetText(label)
  local sub = Text(parent, 9, DIM)
  sub:SetPoint("TOPLEFT", 170, y - 2)
  sub:SetPoint("RIGHT", parent, "RIGHT", -34, 0)
  sub:SetText(note)

  local mark = CreateFrame("Button", nil, parent)
  mark:SetSize(16, 16)
  mark:SetPoint("TOPRIGHT", -10, y - 1)
  ns.Skin.Panel(mark, { color = { 0.10, 0.09, 0.13, 1 }, borderColor = { 0.30, 0.26, 0.36, 1 } })
  local q = Text(mark, 10, ACCENT, "CENTER")
  q:SetPoint("CENTER")
  q:SetText("?")
  mark:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(label, 1, 1, 1)
    GameTooltip:AddLine(help, 0.8, 0.8, 0.85, true)
    GameTooltip:Show()
  end)
  mark:SetScript("OnLeave", function() GameTooltip:Hide() end)

  box:SetScript("OnClick", function(self)
    Settings()[key] = self:GetChecked() and true or false
    if onChange then onChange() end
    if ns.RefreshKeybindsPage then ns.RefreshKeybindsPage() end
  end)
  page.controls[key] = function()
    box:SetChecked(Settings()[key] ~= false)
    if box.Paint then box:Paint() end
  end
  return box
end

---------------------------------------------------------------------------
-- The saved sets
---------------------------------------------------------------------------

local SET_ROWS = 3

local function SetRow(parent, index)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(RIGHT_W - 20, 54)
  row:SetPoint("TOPLEFT", 10, -36 - (index - 1) * 58)
  ns.Skin.Panel(row, { color = { 0.09, 0.08, 0.12, 1 }, borderColor = { 0.30, 0.26, 0.36, 1 } })
  row.glyph = ns.Skin.Icon(row, "char", 22, ACCENT, "OVERLAY")
  row.glyph:SetPoint("LEFT", 10, 0)
  row.name = Text(row, 12, TEXT)
  row.name:SetPoint("TOPLEFT", 40, -8)
  row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  row.detail = Text(row, 9, DIM)
  row.detail:SetPoint("TOPLEFT", 40, -24)
  row.count = Text(row, 9, GREEN)
  row.count:SetPoint("BOTTOMLEFT", 40, 8)
  row:SetScript("OnClick", function(self)
    if self.setName then
      page.selected = self.setName
      if ns.RefreshKeybindsPage then ns.RefreshKeybindsPage() end
    end
  end)
  return row
end

local function Stamp(when)
  if not when or when == 0 or not date then
    return "never saved"
  end
  return "last saved " .. date("%b %d, %H:%M", when)
end

local function RefreshSets()
  local module = AB()
  local sets = (module and module.KeybindSets and module.KeybindSets()) or {}
  page.sets = sets
  local pages = math.max(1, math.ceil(#sets / SET_ROWS))
  page.pageIndex = math.min(math.max(1, page.pageIndex or 1), pages)
  if page.pager then
    page.pager:SetText(("Page %d of %d"):format(page.pageIndex, pages))
  end
  if not page.selected or not (function()
    for _, set in ipairs(sets) do if set.name == page.selected then return true end end
  end)() then
    page.selected = sets[1] and sets[1].name
  end
  for i, row in ipairs(page.setRows) do
    local set = sets[(page.pageIndex - 1) * SET_ROWS + i]
    row:SetShown(set ~= nil)
    if set then
      row.setName = set.name
      row.name:SetText(set.name)
      -- Built by appending, not from a literal with holes in it: a set
      -- saved before the page existed has no class or level, and a nil in
      -- the middle of a table is what table.concat refuses.
      local parts = {}
      if set.level then parts[#parts + 1] = "Level " .. set.level end
      if set.class then
        parts[#parts + 1] = set.class:sub(1, 1) .. set.class:sub(2):lower()
      end
      if set.active then parts[#parts + 1] = "in use" end
      row.detail:SetText(#parts > 0 and table.concat(parts, "  ") or "saved on this account")
      row.count:SetText(("%d bind%s saved  -  %s"):format(set.count, set.count == 1 and "" or "s", Stamp(set.saved)))
      local chosen = set.name == page.selected
      ns.Skin.SetBorderColor(row, chosen and ACCENT or { 0.30, 0.26, 0.36, 1 })
      ns.Skin.SetPanelColor(row, chosen and { 0.20, 0.12, 0.34, 1 } or { 0.09, 0.08, 0.12, 1 })
      if set.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[set.class] then
        local c = RAID_CLASS_COLORS[set.class]
        ns.Skin.SetIcon(row.glyph, "char", { c.r, c.g, c.b })
      end
    end
  end
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

local function SelectTab(key)
  page.tab = key
  for name, panel in pairs(page.panels or {}) do
    panel:SetShown(name == key)
  end
  for name, tab in pairs(page.tabs or {}) do
    ns.Skin.SetSelected(tab, name == key)
  end
end

local function Refresh()
  for _, fn in pairs(page.controls or {}) do
    fn()
  end
  local module = AB()
  if page.modeButton then
    local on = module and module.GetMode and module.GetMode() == "keys"
    page.modeButton.head:SetText(on and "Disable binding mode" or "Enable binding mode")
    page.modeButton.sub:SetText(on and "Binding is on -- hover and press" or "Click to start binding")
  end
  if page.scopeButton then
    local who = ns.CharacterKey() or "this character"
    page.scopeButton:SetText((Settings().bindingScope or "character") == "account"
      and "All characters (Shared)" or who)
  end
  RefreshSets()
end
ns.RefreshKeybindsPage = Refresh

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

function ns.KeybindsPageSchema()
  return {
    { type = "heading", label = "Keybinds", subtitle = "Bind it. Play it. Live it." },
    { type = "custom", bare = true, build = function(parent, x, y)
      page = { controls = {}, setRows = {}, tabs = {}, panels = {}, pageIndex = 1 }
      local root = CreateFrame("Frame", nil, parent)
      root:SetPoint("TOPLEFT", x, y)
      root:SetSize(W, 560)

      local intro = Text(root, 10, DIM)
      intro:SetPoint("TOPLEFT", 0, 0)
      intro:SetWidth(LEFT_W)
      intro:SetText("Turn binding on, then hover a bar button and press the key you want -- or a mouse button, or the wheel. Every bind is saved into a set you can carry between characters.")

      -- Tabs
      local TABS = {
        { key = "general", label = "General" },
        { key = "options", label = "Binding Options" },
      }
      for i, tab in ipairs(TABS) do
        local b = CreateFrame("Button", nil, root)
        b:SetSize(LEFT_W / #TABS - 4, 24)
        b:SetPoint("TOPLEFT", (i - 1) * (LEFT_W / #TABS + 2), -34)
        ns.Skin.Button(b, { role = "general" })
        b:SetText(tab.label)
        b:SetScript("OnClick", function() SelectTab(tab.key) end)
        page.tabs[tab.key] = b
      end

      -- General: what you do
      local general = CreateFrame("Frame", nil, root)
      general:SetPoint("TOPLEFT", 0, -64)
      general:SetSize(LEFT_W, 300)
      page.panels.general = general

      local quick = Card(general, 0, 0, LEFT_W, 120, "keybinds", "Quick Actions")
      page.modeButton = BigButton(quick, 10, -36, LEFT_W - 20, 36, "play",
        "Enable binding mode", "Click to start binding", GREEN, function()
          local module = AB()
          if module then module.ToggleKeybinds() end
          Refresh()
        end)
      page.clearButton = BigButton(quick, 10, -78, (LEFT_W - 26) / 2, 34, "trash",
        "Clear all", "Every bind, gone", RED, function()
          local module = AB()
          if module then module.ClearAllKeybinds() end
          Refresh()
        end)
      BigButton(quick, 16 + (LEFT_W - 26) / 2, -78, (LEFT_W - 26) / 2, 34, "reset",
        "Save as a set", "Keep these binds", ACCENT, function()
          local module = AB()
          if module and module.SaveKeybindSet then
            local count = module.SaveKeybindSet()
            ns.Print(("%d bind%s saved for %s."):format(count, count == 1 and "" or "s", ns.CharacterKey() or "this character"))
          end
          Refresh()
        end)

      local tip = Card(general, 0, -132, LEFT_W, 92, "info", "Tip")
      local tipText = Text(tip, 10, DIM)
      tipText:SetPoint("TOPLEFT", 12, -36)
      tipText:SetPoint("RIGHT", tip, "RIGHT", -12, 0)
      tipText:SetText("The button under your mouse lights up while binding is on, and its tooltip says what it is bound to. Backspace clears it. Escape, or Done on the panel, finishes.")

      -- Options: how binding behaves
      local options = CreateFrame("Frame", nil, root)
      options:SetPoint("TOPLEFT", 0, -64)
      options:SetSize(LEFT_W, 300)
      page.panels.options = options
      local behave = Card(options, 0, 0, LEFT_W, 186, "general", "Binding Behaviour")
      Behaviour(behave, -40, "Hover to bind", "Point and press",
        "On: point at a button and press the key. Off: click a button to pick it first, then press the key wherever your mouse is.", "hoverBind")
      Behaviour(behave, -64, "Mouse buttons", "Right, middle, side, wheel",
        "Lets a click or the wheel be bound to a button, not just a key.", "allowMouse")
      Behaviour(behave, -88, "Modifiers", "Ctrl, Alt and Shift count",
        "Holding Ctrl, Alt or Shift while you press makes that part of the binding.", "allowModifiers")
      Behaviour(behave, -112, "Key text on buttons", "Show the key in the corner",
        "The bound key is drawn in the corner of each button.", "showKeybinds", function()
          local module = AB()
          if module and module.UpdateAllHotkeys then module.UpdateAllHotkeys() end
        end)
      Behaviour(behave, -136, "Sound on bind", "A click when it takes",
        "Plays a short sound each time a key is bound.", "bindSound")

      -- Saved sets
      local saved = Card(root, LEFT_W + GAP, 0, RIGHT_W, 260, "profiles", "Saved Keybinds")
      page.pager = Text(saved, 9, DIM, "RIGHT")
      page.pager:SetPoint("TOPRIGHT", -34, -13)
      local prev = CreateFrame("Button", nil, saved)
      prev:SetSize(18, 18)
      prev:SetPoint("TOPRIGHT", -14, -10)
      ns.Skin.Button(prev, { role = "general" })
      prev:SetText(">")
      prev:SetScript("OnClick", function()
        page.pageIndex = (page.pageIndex or 1) + 1
        RefreshSets()
      end)

      local scope = Text(saved, 10, DIM)
      scope:SetPoint("TOPLEFT", 12, -36)
      scope:SetText("Saving into:")
      page.scopeButton = CreateFrame("Button", nil, saved)
      page.scopeButton:SetSize(RIGHT_W - 100, 22)
      page.scopeButton:SetPoint("TOPLEFT", 86, -32)
      ns.Skin.Button(page.scopeButton, { role = "general" })
      page.scopeButton:SetScript("OnClick", function()
        local module = AB()
        if module then
          module.SetBindingScope((Settings().bindingScope or "character") == "character" and "account" or "character")
        end
        Refresh()
      end)

      for i = 1, SET_ROWS do
        page.setRows[i] = SetRow(saved, i + 1)
      end

      -- What you can do with the chosen set
      local actions = Card(root, LEFT_W + GAP, -274, RIGHT_W, 96, "modules", "The chosen set")
      BigButton(actions, 10, -36, (RIGHT_W - 26) / 2, 22, "download", "Load it", "", ACCENT, function()
        local module = AB()
        if module and page.selected and module.LoadKeybindSet then
          local ok, applied = module.LoadKeybindSet(page.selected)
          ns.Print(ok and ("%d bind%s loaded from \"%s\"."):format(applied or 0, (applied or 0) == 1 and "" or "s", page.selected)
            or "that set is gone.")
        end
        Refresh()
      end)
      BigButton(actions, 16 + (RIGHT_W - 26) / 2, -36, (RIGHT_W - 26) / 2, 22, "trash", "Delete it", "", RED, function()
        local module = AB()
        if module and page.selected and module.DeleteKeybindSet then
          if module.DeleteKeybindSet(page.selected) then
            ns.Print(("\"%s\" deleted."):format(page.selected))
          else
            ns.Print("the set you are using cannot be deleted.")
          end
        end
        Refresh()
      end)
      BigButton(actions, 10, -64, (RIGHT_W - 26) / 2, 22, "upload", "Copy out", "", ACCENT, function()
        local module = AB()
        if module and module.ExportKeybinds and ns.ShowTextPopup then
          ns.ShowTextPopup("Keybinds (Cmd/Ctrl+C to copy)", module.ExportKeybinds(page.selected))
        end
      end)
      BigButton(actions, 16 + (RIGHT_W - 26) / 2, -64, (RIGHT_W - 26) / 2, 22, "download", "Paste in", "", ACCENT, function()
        ns.ShowTextPopup("Paste a keybind set, then Import", "", function(text)
          local module = AB()
          local ok, result = false, "no action bars module."
          if module and module.ImportKeybinds then
            ok, result = module.ImportKeybinds(text)
          end
          if ok then
            ns.Print(("%d bind%s pasted in."):format(result, result == 1 and "" or "s"))
          else
            ns.Print("could not read that: " .. tostring(result))
          end
          Refresh()
        end)
      end)

      local note = Text(root, 9, DIM)
      note:SetPoint("TOPLEFT", LEFT_W + GAP, -378)
      note:SetWidth(RIGHT_W)
      note:SetText("Sets travel as text, not as files: an addon cannot write to your disk.")

      page.root = root
      -- The buttons the tests reach for, and anything else that wants to
      -- press them without a mouse.
      ns.keybindsPage = page
      SelectTab("general")
      Refresh()
      return 420
    end,
      refresh = function() Refresh() end },
  }
end
