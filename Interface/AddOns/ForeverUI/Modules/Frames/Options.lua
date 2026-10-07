local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- The /hf window. Plain insecure UI: it edits the active profile and asks
-- Bindings.lua / Layout.lua to apply changes (after combat, where needed).
--
-- Categories down the left, one page each:
--   Click-casting  your spells on the left, bound clicks on the right. To bind,
--                  hold the modifiers you want and click a spell with the mouse
--                  button you want. Shift + right-click Renew binds Shift+Right.
--   General        scale, out-of-range fade, lock/reset, preview party or raid
--   Layout         raid groups per row, raid frames on/off, hide Blizzard's frames
--   On the frames  incoming heals, dispels, HoTs, HoT length
--   Profiles       switch, create, copy, delete; each character remembers its own

local ROW_HEIGHT = 26
local SIDEBAR = 190          -- category list on the left, with icons
local HEADER_H = 56          -- the title strip: emblem, role, tagline, search
local FOOTER_H = 92          -- the action tiles and the status row
local CONTENT_X = 14         -- page-relative: pages already start after the sidebar
local COLUMN_TWO = CONTENT_X + 226
local COLUMN_WIDTH = 214
local LIST_HEIGHT = 318
local TOP = -16              -- first row of content inside a page
local CONTROL_X = 296        -- where a stepper's minus button sits
local VALUE_X = 340
local PLUS_X = 372

-- The click-actions offered depend on the role. Healer: target/menu/focus (the
-- heal itself is the "Put X on left click" button). Tank: engage/taunt/assist.
local HEAL_ACTIONS = {
  { label = "Target", binding = { kind = "target" } },
  { label = "Unit menu", binding = { kind = "menu" } },
  { label = "Set focus", binding = { kind = "focus" } },
}
local RAID_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local TANK_ACTIONS = {
  { label = "Engage", binding = { kind = "engage" }, icon = "engage" },
  { label = "+ Taunt", binding = { kind = "engage" }, taunt = true, icon = "taunt" },
  { label = "Assist", binding = { kind = "assist" }, icon = "assist" },
  { label = "Menu", binding = { kind = "menu" }, icon = "menu" },
  { label = "Focus", binding = { kind = "focus" }, icon = "focus" },
  -- Marks go on the mob that player is on (your own frame: your target).
  { label = "Skull", binding = { kind = "mark", marker = 8 }, texture = RAID_ICON .. "8" },
  { label = "Cross", binding = { kind = "mark", marker = 7 }, texture = RAID_ICON .. "7" },
  { label = "Moon", binding = { kind = "mark", marker = 5 }, texture = RAID_ICON .. "5" },
}
ns.ACTIONS = TANK_ACTIONS
local function CurrentActions()
  return ns.GetMode() == "tank" and TANK_ACTIONS or HEAL_ACTIONS
end

local CATEGORIES = {
  { key = "bindings",   label = "Click-casting" },
  { key = "general",    label = "General" },
  { key = "appearance", label = "Appearance" },
  { key = "layout",     label = "Layout" },
  { key = "indicators", label = "On the frames" },
  { key = "auras",      label = "Auras" },
  { key = "roles",      label = "Roles" },
  -- No Profiles page: the frames save into ForeverUI's profile (ForeverUI > Profiles).
}
-- More pages are added from OptionsExtra.lua, before the window is first built.
ns.FRAME_CATEGORIES = CATEGORIES
ns.FRAME_PAGE_ICONS = {}
ns.FRAME_PAGE_BUILDERS = {}

-- Flat dark, one-pixel borders, a single blue accent - the same look
-- ForeverUI wears, so the two sit together on screen. HealForever keeps its own
-- copy of the palette so it stays a standalone addon.
ns.THEME = {
  bg      = { 0.02, 0.05, 0.09, 0.97 },  -- the window behind the cards: deep navy
  card    = { 0.04, 0.08, 0.13, 1 },
  inset   = { 0.03, 0.06, 0.10, 0.95 },  -- scroll lists and edit boxes
  rule    = { 0.14, 0.42, 0.66, 1 },     -- borders: the blue edge
  accent  = { 0.30, 0.76, 1.00 },
  heading = { 0.30, 0.76, 1.00 },        -- card titles
  label   = { 0.92, 0.92, 0.94 },
  value   = { 0.30, 0.76, 1.00 },
  note    = { 0.62, 0.62, 0.66 },
  hover   = { 1, 1, 1, 0.07 },
  select  = { 0.30, 0.76, 1.00, 0.20 },
}
local THEME = ns.THEME
local BASE_THEME = {}
for k, v in pairs(THEME) do BASE_THEME[k] = { unpack(v) } end
local HEADING_FONT = "Fonts\\FRIZQT__.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local panel
local panelRole            -- the role the open window belongs to
-- Defined further down, used above it: the rows are built before the helper.
local WindowRole, WindowSetBinding
local showHarmful = false  -- flipped on in tank mode at build time
-- Downranking. Off, the list shows one row per spell and clicking it casts
-- your highest rank, which is what almost everyone wants almost always. On,
-- every rank gets its own row, so a healer can put Lesser Heal(Rank 2) on a
-- click to save mana. Kept in the profile, because someone who downranks
-- does it on every character.

-- Which click is being edited: pick one on the right, then a spell on the
-- left. Two clicks, nothing to type, nothing to submit.
local selectedClick = "1"
local selectedModifier = "" -- "", "shift-", "alt-ctrl-" ...

---------------------------------------------------------------------------
-- Small widgets (built by hand: no reliance on Blizzard option templates)
---------------------------------------------------------------------------

-- One-pixel edges on all four sides. Textures rather than SetBackdrop:
-- backdrops need BackdropTemplate on newer clients and don't on older ones.
local function Border(frame, color)
  local edges = {}
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local tex = frame:CreateTexture(nil, "BORDER")
    tex:SetColorTexture(unpack(color or THEME.rule))
    if side == "TOP" then
      tex:SetPoint("TOPLEFT"); tex:SetPoint("TOPRIGHT"); tex:SetHeight(1)
    elseif side == "BOTTOM" then
      tex:SetPoint("BOTTOMLEFT"); tex:SetPoint("BOTTOMRIGHT"); tex:SetHeight(1)
    elseif side == "LEFT" then
      tex:SetPoint("TOPLEFT"); tex:SetPoint("BOTTOMLEFT"); tex:SetWidth(1)
    else
      tex:SetPoint("TOPRIGHT"); tex:SetPoint("BOTTOMRIGHT"); tex:SetWidth(1)
    end
    edges[#edges + 1] = tex
  end
  frame.edges = edges
  return edges
end

local function SetBorderColor(frame, color)
  for _, tex in ipairs(frame.edges or {}) do
    tex:SetColorTexture(unpack(color))
  end
end

local function Fill(frame, color, layer)
  local tex = frame:CreateTexture(nil, layer or "BACKGROUND")
  tex:SetAllPoints()
  tex:SetColorTexture(unpack(color))
  frame.fill = tex
  return tex
end

local BUTTON_BG     = { 0.14, 0.14, 0.17, 1 }
local BUTTON_HOVER  = { 0.18, 0.20, 0.24, 1 }
local BUTTON_ACTIVE = { 0.10, 0.22, 0.30, 1 }
local BASE_BUTTONS = { { unpack(BUTTON_BG) }, { unpack(BUTTON_HOVER) }, { unpack(BUTTON_ACTIVE) } }
local function SetButtonColors(bg, hover, active)
  for i = 1, 4 do BUTTON_BG[i], BUTTON_HOVER[i], BUTTON_ACTIVE[i] = bg[i], hover[i], active[i] end
end

-- The healer window is painted (ChatGPT art in ForeverUI/Media/skin): a
-- moonlit forest plate, and the cards are dark glass over its stone board.
-- Asked for when a window is built, not when this file loads: standalone,
-- FUI.MEDIA_PATH is only set by Standalone.lua, which loads after this.
local function SkinPath()
  return (FUI.MEDIA_PATH or "Interface\\AddOns\\ForeverUI\\Media\\") .. "skin\\"
end
local HEALER_THEME = {
  bg      = { 0, 0, 0, 0 },
  card    = { 0.02, 0.08, 0.09, 0.80 },
  inset   = { 0.01, 0.05, 0.06, 0.88 },
  rule    = { 0.22, 0.52, 0.44, 0.95 },
  label   = { 0.90, 0.95, 0.93 },
  note    = { 0.60, 0.72, 0.70 },
}
local TANK_THEME = {
  bg      = { 0, 0, 0, 0 },
  card    = { 0.05, 0.03, 0.02, 0.82 },
  inset   = { 0.03, 0.02, 0.01, 0.90 },
  rule    = { 0.55, 0.30, 0.10, 0.95 },
  label   = { 0.96, 0.92, 0.86 },
  note    = { 0.74, 0.62, 0.50 },
}

-- Each painted role window: its plate and crest (ChatGPT art), palette, and
-- where the menu, title and page sit on the painting. A role without an
-- entry keeps the flat window.
local ROLE_SKINS = {
  healer = {
    plate = "healer-plate", crest = "healer-leaf", logo = "foreverui-logo-green", size = { 1230, 840 },
    theme = HEALER_THEME,
    buttons = { { 0.02, 0.07, 0.08, 0.88 }, { 0.05, 0.14, 0.13, 0.95 }, { 0.06, 0.30, 0.16, 0.95 } },
    save = { 0.08, 0.46, 0.24, 1 }, status = { 0.01, 0.04, 0.05, 0.55 },
    well = { 30, -76, 198, 330 }, page = { 250, -204, -156 }, block = { 262, -70 }, tabW = 182,
  },
  tank = {
    plate = "tank-plate", crest = "tank-crest", logo = "foreverui-logo-orange", size = { 1230, 860 },
    theme = TANK_THEME,
    buttons = { { 0.05, 0.03, 0.02, 0.90 }, { 0.14, 0.07, 0.03, 0.95 }, { 0.36, 0.16, 0.03, 0.95 } },
    save = { 0.72, 0.34, 0.04, 1 }, status = { 0.03, 0.02, 0.01, 0.55 },
    well = { 30, -120, 186, 310 }, page = { 248, -220, -140 }, block = { 252, -112 }, tabW = 170,
  },
}
ROLE_SKINS.dps = {
  plate = "dps-plate", crest = "dps-crest", logo = "foreverui-logo-purple", size = { 1330, 887 },
  -- The plate's own painted line, cut out and set in the status row.
  motto = { "dps-motto", 476, 38, 550 / 1024, 44 / 64 }, searchRight = -214,
  theme = {
    bg      = { 0, 0, 0, 0 },
    card    = { 0.05, 0.03, 0.09, 0.82 },
    inset   = { 0.03, 0.02, 0.06, 0.90 },
    rule    = { 0.45, 0.30, 0.75, 0.95 },
    label   = { 0.95, 0.93, 1.00 },
    note    = { 0.70, 0.64, 0.82 },
  },
  buttons = { { 0.05, 0.03, 0.09, 0.90 }, { 0.12, 0.07, 0.20, 0.95 }, { 0.28, 0.12, 0.52, 0.95 } },
  save = { 0.40, 0.18, 0.78, 1 }, status = { 0.03, 0.02, 0.05, 0.55 },
  well = { 150, -146, 160, 306 }, page = { 342, -266, -160 }, block = { 344, -154 }, tabW = 146,
}
ns.ROLE_SKINS = ROLE_SKINS

local function PaintButton(button)
  local accent = { THEME.accent[1], THEME.accent[2], THEME.accent[3], 1 }
  if button.selected then
    button.fill:SetColorTexture(unpack(BUTTON_ACTIVE))
    SetBorderColor(button, accent)
    button.label:SetTextColor(unpack(THEME.accent))
  elseif button.hovered then
    button.fill:SetColorTexture(unpack(BUTTON_HOVER))
    SetBorderColor(button, accent)
    button.label:SetTextColor(unpack(THEME.label))
  else
    button.fill:SetColorTexture(unpack(BUTTON_BG))
    SetBorderColor(button, THEME.rule)
    button.label:SetTextColor(unpack(THEME.label))
  end
end

-- A flat button, drawn here rather than taken from Blizzard's templates:
-- those carry the stone-and-gold artwork this window is replacing.
local function Button(parent, width, text, onClick)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(width, 22)
  Fill(button, BUTTON_BG)
  Border(button)

  local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("CENTER")
  label:SetPoint("LEFT", 6, 0)
  label:SetPoint("RIGHT", -6, 0)
  label:SetJustifyH("CENTER")
  button.label = label
  -- Keep the template's interface: every caller still uses :SetText.
  function button:SetText(value)
    self.label:SetText(value)
  end
  function button:GetText()
    return self.label:GetText()
  end

  button:SetText(text)
  button:SetScript("OnClick", onClick)
  button:SetScript("OnEnter", function(self) self.hovered = true; PaintButton(self) end)
  button:SetScript("OnLeave", function(self) self.hovered = false; PaintButton(self) end)
  PaintButton(button)
  button.Paint = PaintButton
  return button
end

-- Mark one button in a set as the current one (category tabs, modifier keys).
local function SetSelected(button, selected)
  button.selected = selected and true or false
  PaintButton(button)
end

local function Percent(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end
local function Seconds(v) return ("%ds"):format(v) end
local function Plain(v) return tostring(v) end

-- "Label      [-]  value  [+]"
local function Stepper(page, y, label, key, min, max, step, format)
  local text = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("TOPLEFT", CONTENT_X + 6, y)
  text:SetText(label)
  text:SetTextColor(unpack(THEME.label))

  local value = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  value:SetPoint("TOP", page, "TOPLEFT", VALUE_X, y)
  value:SetTextColor(unpack(ns.THEME.value))

  local function change(direction)
    local v = ns.db[key] + direction * step
    v = math.floor(v / step + 0.5) * step -- no 1.1000000001 drift
    ns.SetSetting(key, math.max(min, math.min(max, v)))
  end

  local minus = Button(page, 26, "-", function() change(-1) end)
  minus:SetPoint("TOPLEFT", CONTROL_X, y + 3)
  local plus = Button(page, 26, "+", function() change(1) end)
  plus:SetPoint("TOPLEFT", PLUS_X, y + 3)

  local control = { minus = minus, plus = plus, value = value }
  function control.refresh()
    value:SetText(format(ns.db[key]))
  end
  panel.controls[key] = control
  return control
end

-- `opts.get` / `opts.set` let a checkbox front a setting that isn't a boolean
-- (the mana bar is a height: ticked means 5 pixels, unticked means none).
local function Checkbox(page, y, label, key, opts)
  opts = opts or {}
  local box = CreateFrame("CheckButton", nil, page)
  box:SetSize(24, 24)
  box:SetPoint("TOPLEFT", opts.x or CONTENT_X, y + 5)
  box:SetSize(18, 18)
  Fill(box, THEME.inset)
  Border(box)
  box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  box:SetHighlightTexture(WHITE)
  local tick = box:GetCheckedTexture()
  if tick then
    tick:SetVertexColor(unpack(THEME.accent))
  end
  local hover = box:GetHighlightTexture()
  if hover then
    hover:SetVertexColor(1, 1, 1, 0.10)
  end
  box:SetScript("OnClick", function(self)
    local checked = self:GetChecked() and true or false
    ns.SetSetting(key, opts.set and opts.set(checked) or checked)
    if opts.set then
      ns.RefreshOptions() -- a second control may show the same setting
    end
  end)

  local text = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("LEFT", box, "RIGHT", 4, 0)
  text:SetText(label)
  text:SetTextColor(unpack(THEME.label))

  local control = { box = box }
  function control.refresh()
    local value = ns.db[key]
    box:SetChecked(opts.get and opts.get(value) or (not opts.get and value and true or false))
  end
  panel.controls[opts.name or key] = control
  return control
end

-- A button that cycles through a list of values: simpler and more reliable
-- than a dropdown, and there are only a few choices for each of these.
local function Cycler(page, y, label, key, choices)
  local text = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("TOPLEFT", CONTENT_X + 6, y)
  text:SetText(label)
  text:SetTextColor(unpack(THEME.label))

  local button = Button(page, 170, "", function()
    local current = ns.db[key]
    local index = 1
    for i, choice in ipairs(choices) do
      if choice.value == current then index = i end
    end
    ns.SetSetting(key, choices[index % #choices + 1].value)
  end)
  button:SetPoint("TOPLEFT", CONTROL_X - 46, y + 3)

  local control = { button = button }
  function control.refresh()
    local shown = "?"
    for _, choice in ipairs(choices) do
      if choice.value == ns.db[key] then shown = choice.label end
    end
    button:SetText(shown)
  end
  panel.controls[key] = control
  return control
end

-- The narrow right-hand column: a label with its control under it (a cycler
-- or a colour), or a label with - value + on the same line (a stepper).
-- Everything is placed from `x`, the column's left edge.
local COLUMN_W = 240

local function ColumnLabel(page, x, y, label)
  local text = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("TOPLEFT", x, y)
  text:SetText(label)
  text:SetTextColor(unpack(THEME.label))
  return text
end

local function ColumnCycler(page, x, y, label, key, choices)
  ColumnLabel(page, x, y, label)
  local button = Button(page, COLUMN_W, "", function()
    local current, index = ns.db[key], 1
    for i, choice in ipairs(choices) do
      if choice.value == current then index = i end
    end
    ns.SetSetting(key, choices[index % #choices + 1].value)
  end)
  button:SetPoint("TOPLEFT", x, y - 18)
  local control = { button = button }
  function control.refresh()
    local shown = "?"
    for _, choice in ipairs(choices) do
      if choice.value == ns.db[key] then shown = choice.label end
    end
    button:SetText(shown)
  end
  panel.controls[key] = control
  return control
end

local function ColumnStepper(page, x, y, label, key, min, max, step, format)
  ColumnLabel(page, x, y, label)
  local value = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  value:SetPoint("TOP", page, "TOPLEFT", x + COLUMN_W - 44, y)
  value:SetTextColor(unpack(ns.THEME.value))
  local function change(direction)
    local v = (ns.db[key] or min) + direction * step
    v = math.floor(v / step + 0.5) * step
    ns.SetSetting(key, math.max(min, math.min(max, v)))
  end
  local minus = Button(page, 22, "-", function() change(-1) end)
  minus:SetPoint("TOPLEFT", x + COLUMN_W - 88, y + 3)
  local plus = Button(page, 22, "+", function() change(1) end)
  plus:SetPoint("TOPLEFT", x + COLUMN_W - 22, y + 3)
  local control = { minus = minus, plus = plus, value = value }
  function control.refresh()
    value:SetText(format(ns.db[key] or min))
  end
  panel.controls[key] = control
  return control
end

-- The game's colour picker, starting at r, g, b; `apply` gets each pick and,
-- on cancel, the colour it started from.
local function OpenColorPicker(r, g, b, apply)
  local picker = _G.ColorPickerFrame
  if not picker then
    ns.Print("this client has no colour picker.")
    return
  end
  local info = {
    r = r, g = g, b = b, hasOpacity = false,
    swatchFunc = function()
      local nr, ng, nb = picker:GetColorRGB()
      if nr then apply(nr, ng, nb) end
    end,
    cancelFunc = function() apply(r, g, b) end,
  }
  if picker.SetupColorPickerAndShow then
    pcall(picker.SetupColorPickerAndShow, picker, info)
  else
    -- Shown directly, never through ShowUIPanel: calling Blizzard's panel
    -- manager from our click taints it (see ForeverUI's Config/GUI.lua).
    picker.func, picker.cancelFunc, picker.hasOpacity = info.swatchFunc, info.cancelFunc, false
    picker.previousValues = { r = r, g = g, b = b }
    if picker.SetColorRGB then pcall(picker.SetColorRGB, picker, r, g, b) end
    picker:Show()
  end
end
ns.OpenColorPicker = OpenColorPicker

-- A colour: the swatch opens the game's colour picker.
local function ColumnSwatch(page, x, y, label, key)
  ColumnLabel(page, x, y, label)
  local swatch = CreateFrame("Button", nil, page)
  swatch:SetSize(54, 18)
  swatch:SetPoint("TOPLEFT", x + COLUMN_W - 54, y + 3)
  Fill(swatch, { 0, 0, 0, 1 })
  Border(swatch)
  local fill = swatch:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("TOPLEFT", 2, -2)
  fill:SetPoint("BOTTOMRIGHT", -2, 2)
  local function Current()
    local c = ns.db[key] or { 1, 1, 1 }
    return c[1] or 1, c[2] or 1, c[3] or 1
  end
  local function Apply(r, g, b)
    ns.SetSetting(key, { r, g, b })
  end
  swatch:SetScript("OnClick", function()
    local r, g, b = Current()
    OpenColorPicker(r, g, b, Apply)
  end)
  local control = { swatch = swatch }
  function control.refresh()
    fill:SetColorTexture(Current())
  end
  panel.controls[key] = control
  return control
end

-- A titled white card. Controls are still placed by their own offsets; the
-- card is drawn behind them, which keeps every page's code simple.
local function Card(page, y, height, title, x, width)
  x, width = x or (CONTENT_X - 6), width or 540

  local border = page:CreateTexture(nil, "BACKGROUND")
  border:SetPoint("TOPLEFT", x, y + 22)
  border:SetSize(width, height)
  local fill = page:CreateTexture(nil, "BACKGROUND", nil, 1)
  fill:SetPoint("TOPLEFT", border, "TOPLEFT", 1, -1)
  fill:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -1, 1)
  fill:SetColorTexture(unpack(THEME.card))
  if (THEME.card[4] or 1) < 1 then
    -- See-through card: a solid backing would show through it, so the edge
    -- is four one-pixel lines instead.
    border:SetColorTexture(0, 0, 0, 0)
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
      local e = page:CreateTexture(nil, "BORDER")
      e:SetColorTexture(unpack(THEME.rule))
      if side == "TOP" or side == "BOTTOM" then
        e:SetPoint(side .. "LEFT", border, side .. "LEFT"); e:SetPoint(side .. "RIGHT", border, side .. "RIGHT"); e:SetHeight(1)
      else
        e:SetPoint("TOP" .. side, border, "TOP" .. side); e:SetPoint("BOTTOM" .. side, border, "BOTTOM" .. side); e:SetWidth(1)
      end
    end
  else
    border:SetColorTexture(unpack(THEME.rule))
  end

  if title then
    local heading = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("TOPLEFT", border, "TOPLEFT", 12, -8)
    heading:SetText(title)
    heading:SetFont(HEADING_FONT, 15)
    heading:SetTextColor(unpack(THEME.heading))
  end
  return border
end

-- Kept for pages that only want a title inside a card they already drew.
local function Heading(page, y, text)
  local heading = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  heading:SetPoint("TOPLEFT", CONTENT_X, y)
  heading:SetText(text)
  heading:SetFont(HEADING_FONT, 15)
  heading:SetTextColor(unpack(THEME.heading))
  return heading
end

-- Body text that isn't a control label.
local function Note(page, fontObject)
  local note = page:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlight")
  note:SetTextColor(unpack(ns.THEME.note))
  return note
end

local function MakeScrollList(page, x, width, height, y)
  width, height = width or COLUMN_WIDTH, height or LIST_HEIGHT
  local scroll = CreateFrame("ScrollFrame", nil, page)
  scroll:SetSize(width, height)
  scroll:SetPoint("TOPLEFT", x, y or (TOP - 26))

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(width, 1)
  scroll:SetScrollChild(content)

  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
    local target = self:GetVerticalScroll() - delta * ROW_HEIGHT * 3
    self:SetVerticalScroll(math.min(maxScroll, math.max(0, target)))
  end)

  local bg = scroll:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(unpack(THEME.inset))

  local outline = scroll:CreateTexture(nil, "BORDER")
  outline:SetPoint("TOPLEFT", -1, 1)
  outline:SetPoint("BOTTOMRIGHT", 1, -1)
  outline:SetColorTexture(THEME.rule[1], THEME.rule[2], THEME.rule[3], 0.5)

  return scroll, content
end

local function RowAt(pool, content, i, onClick, width)
  local row = pool[i]
  if not row then
    row = CreateFrame("Button", nil, content)
    row:SetSize(width or COLUMN_WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row:RegisterForClicks("AnyUp")
    if onClick then
      row:SetScript("OnClick", onClick)
    end

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 3, 0)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", -24, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetTextColor(unpack(THEME.label))

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(unpack(THEME.hover))

    pool[i] = row
  end
  row:Show()
  return row
end

local function HideFrom(pool, first)
  for i = first, #pool do
    pool[i]:Hide()
  end
end

---------------------------------------------------------------------------
-- Click-casting page
--
-- Laid out the way a healer thinks about it: pick the modifier you'll hold,
-- see the five mouse buttons under it, click a box, then click the spell.
---------------------------------------------------------------------------

local MODIFIERS = {
  { label = "None",           prefix = "" },
  { label = "Shift",          prefix = "shift-" },
  { label = "Ctrl",           prefix = "ctrl-" },
  { label = "Ctrl + Shift",   prefix = "ctrl-shift-" },
  { label = "Alt",            prefix = "alt-" },
  { label = "Alt + Shift",    prefix = "alt-shift-" },
  { label = "Alt + Ctrl",     prefix = "alt-ctrl-" },
  { label = "Alt+Ctrl+Shift", prefix = "alt-ctrl-shift-" },
}

local MOUSE_KEYS = {
  { label = "Left",     suffix = "1" },
  { label = "Right",    suffix = "2" },
  { label = "Middle",   suffix = "3" },
  { label = "Button 4", suffix = "4" },
  { label = "Button 5", suffix = "5" },
  { label = "Button 6", suffix = "6" },
  { label = "Button 7", suffix = "7" },
  { label = "Button 8", suffix = "8" },
  { label = "Wheel Up",   suffix = "wheelup" },
  { label = "Wheel Down", suffix = "wheeldown" },
  -- A gaming mouse's extra buttons arrive as function keys rather than as
  -- mouse buttons, so these are how the rest of a twelve-button mouse gets
  -- bound. Like the wheel, they are only taken while your mouse is on a
  -- frame, and do their usual job everywhere else.
  { label = "F16",        suffix = "f16" },
  { label = "F17",        suffix = "f17" },
  { label = "F18",        suffix = "f18" },
  { label = "F19",        suffix = "f19" },
  { label = "Num Pad *",  suffix = "numpadstar" },
  { label = "Page Up",    suffix = "pageup" },
  { label = "Page Down",  suffix = "pagedown" },
}
ns.MOUSE_KEYS = MOUSE_KEYS

-- The window's building blocks, for pages written in other files
-- (OptionsExtra.lua: Healer tools, Status, Panels, Buff Watch). They all
-- write into the one shared panel.controls table, so RefreshOptions reaches
-- their controls like everyone else's.
ns.OptionsParts = {
  Button = Button, Card = Card, Heading = Heading, Note = Note,
  Checkbox = Checkbox, Cycler = Cycler, Stepper = Stepper,
  Fill = Fill, Border = Border, Plain = Plain,
  Controls = function() return panel and panel.controls end,
  THEME = ns.THEME, TOP = TOP, CONTENT_X = CONTENT_X,
  MODIFIERS = MODIFIERS, MOUSE_KEYS = MOUSE_KEYS,
}

-- Three columns, page-relative.
local MOD_X, MOD_W = 14, 150
local KEY_X, KEY_W = 178, 330
local SPELL_X, SPELL_W = 522, 300
local KEY_ROW = 32          -- one binding per row, with its spell's icon
local KEY_LABEL_W = 84
local CLICK_LIST_HEIGHT = 300
local function ClickCardH()  -- the tank page is taller: its Keybinds card carries a header row
  local mode = ns.GetMode()
  if ROLE_SKINS[mode] then
    return mode == "healer" and 530 or 500
  end
  return mode == "tank" and 544 or 458
end

-- The click itself decides the key: modifiers held + which mouse button.
local function OnSpellRowClick(row, mouseButton)
  local plainRightClick = mouseButton == "RightButton" and not IsShiftKeyDown()
    and not IsControlKeyDown() and not IsAltKeyDown()

  -- Right-click removes a spell you typed in.
  if row.manual and plainRightClick then
    ns.RemoveManualSpell(row.spellName)
    ns.RefreshOptions()
    return
  end

  -- Plain left-click fills the box you picked on the left.
  if mouseButton == "LeftButton" and not IsShiftKeyDown() and not IsControlKeyDown()
    and not IsAltKeyDown() then
    local copy = {}
    for k, v in pairs(row.binding) do copy[k] = v end
    WindowSetBinding(selectedClick, copy)
    ns.Print(("%s -> %s (saved)"):format(ns.DescribeKey(selectedClick),
      ns.SpellLabel(row.binding) or row.binding.kind))
    ns.RefreshOptions()
    return
  end

  -- Modifier + click still binds that exact combination directly.
  ns.BindFromClick(row.binding, mouseButton)
  ns.RefreshOptions()
end

local function RefreshSpells()
  local rows = panel.spellRows
  local n = 0

  -- Target unit and Open unit menu used to sit at the top of this list, one
  -- stray click from replacing the heal on left click - which is exactly what
  -- kept happening. They're buttons under the boxes now.
  local spells, _, couldRead = ns.ScanSpellbook(showHarmful)
  table.sort(spells, function(a, b) return a.name < b.name end)
  local filter = panel.spellFilter or ""

  -- One row. `rank` nil means the plain spell, which casts your highest.
  local function AddRow(spell, rank)
    n = n + 1
    local row = RowAt(rows, panel.spellContent, n, OnSpellRowClick, SPELL_W)
    if not row.plus then
      row.plus = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      row.plus:SetPoint("RIGHT", -8, 0)
      row.plus:SetText("+")
      row.plus:SetTextColor(unpack(THEME.accent))
      row.icon:SetSize(22, 22)
    end
    row.binding = { kind = "spell", spell = spell.name, rank = rank,
      their = ns.IsAimedAtTheirTarget(spell.name, spell.helpful) or nil }
    row.spellName = spell.name
    row.manual = spell.manual and not rank
    row.icon:SetTexture(spell.icon)
    if not spell.icon then
      row.icon:SetColorTexture(0.20, 0.20, 0.24, 1)
    end
    if rank then
      -- Indented and dimmed, so the ranks read as belonging to the spell
      -- above them rather than as more spells.
      row.text:SetText(("   %s  |cff8a8a94%s|r"):format(spell.name, rank))
    elseif spell.manual then
      row.text:SetText(spell.name .. "  |cff8a8a94(typed)|r")
    else
      row.text:SetText(spell.name)
    end
    if spell.helpful then
      row.text:SetTextColor(unpack(ns.THEME.label))
    else
      row.text:SetTextColor(0.90, 0.40, 0.40) -- harmful
    end
  end

  for _, spell in ipairs(spells) do
    if filter == "" or spell.name:lower():find(filter, 1, true) then
      AddRow(spell)
      -- Downranking: every rank below the highest gets its own row, so it
      -- can be bound to a click of its own. The highest is the plain row
      -- above, which stays a bare name and follows you as you level.
      if ns.db.showRanks and #(spell.ranks or {}) > 1 then
        for i = #spell.ranks - 1, 1, -1 do
          AddRow(spell, spell.ranks[i].rank)
        end
      end
    end
  end

  HideFrom(rows, n + 1)
  panel.spellContent:SetHeight(math.max(1, n * ROW_HEIGHT))
  panel.spellbookNote:SetShown(not couldRead)
  panel.spellCount:SetText(("%d spells"):format(n))
end

-- What to show in a row's box for the binding it holds.
local function BindingText(binding)
  if not binding then
    return ""
  elseif binding.kind == "target" then
    return "target"
  elseif binding.kind == "menu" then
    return "menu"
  elseif binding.kind == "focus" then
    return "set focus"
  elseif binding.kind == "assist" then
    return "their target"
  elseif binding.kind == "engage" then
    return binding.spell and ("engage + " .. ns.SpellLabel(binding)) or "engage"
  elseif binding.kind == "mark" then
    local names = { [8] = "skull", [7] = "cross", [6] = "square", [5] = "moon", [4] = "triangle",
      [3] = "diamond", [2] = "circle", [1] = "star" }
    if binding.marker == 0 then return "clear their mark" end
    return (names[binding.marker] or "mark") .. " on their target"
  elseif binding.kind == "macro" then
    -- The first line says enough to recognise it.
    local first = (binding.macro or ""):match("^[^\n]*") or ""
    return "macro: " .. (first:len() > 24 and (first:sub(1, 23) .. "...") or first)
  end
  -- The rank is part of what is bound, so it is part of what the row says.
  -- A click showing "Lesser Heal" and casting rank 2 would be a lie.
  if binding.their then
    return (ns.SpellLabel(binding) or "") .. " |cffff6666> mob|r"
  end
  return ns.SpellLabel(binding) or ""
end
ns.BindingText = BindingText

-- One mouse button: a dim label with a box under it, like the panel this
-- borrows its shape from.
local function MouseRow(page, i, entry)
  local row = panel.bindingRows[i]
  if row then
    return row
  end
  -- Inside the scrolling list, so the rows are placed from its own top and
  -- the card underneath never has to grow. Seventeen bindable keys would run
  -- off the bottom of the window otherwise.
  local host = panel.bindingContent or page
  local y = (host == page)
    and (TOP - 40 - (ns.GetMode() == "tank" and 44 or 0) - (i - 1) * KEY_ROW)
    or (-(i - 1) * KEY_ROW)
  local labelX = (host == page) and KEY_X or 0

  local label = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("TOPLEFT", labelX, y - 9)
  label:SetWidth(KEY_LABEL_W - 6)
  label:SetJustifyH("LEFT")
  label:SetText(entry.label)
  label:SetTextColor(unpack(THEME.note))

  row = CreateFrame("Button", nil, host)
  row:SetSize(KEY_W - KEY_LABEL_W - 34, 28)
  row:SetPoint("TOPLEFT", labelX + KEY_LABEL_W, y)
  row:RegisterForClicks("AnyUp")
  Fill(row, THEME.inset)
  Border(row)

  -- The bound spell's icon at the left of the box, and a small button at
  -- the row's end: x clears a bound row, + picks an empty one to fill.
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(22, 22)
  row.icon:SetPoint("LEFT", 3, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.icon:Hide()
  row.action = Button(host, 28, "+", nil)
  row.action:SetHeight(28)
  row.action:SetPoint("LEFT", row, "RIGHT", 6, 0)
  row.action:SetScript("OnClick", function()
    local key = selectedModifier .. entry.suffix
    if ns.db.bindings[key] then
      WindowSetBinding(key, nil)   -- x: clear
    else
      selectedClick = key       -- +: pick, then click a spell
    end
    ns.RefreshOptions()
  end)

  row.selection = row:CreateTexture(nil, "BACKGROUND", nil, 1)
  row.selection:SetAllPoints()
  row.selection:SetColorTexture(unpack(THEME.select))
  row.selection:Hide()

  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints()
  highlight:SetColorTexture(unpack(THEME.hover))

  row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.value:SetPoint("LEFT", 8, 0)
  row.value:SetPoint("RIGHT", -64, 0)
  row.value:SetJustifyH("LEFT")
  row.SetIconShown = function(self, texture)
    if texture then
      self.icon:SetTexture(texture)
      self.icon:Show()
      self.value:SetPoint("LEFT", 30, 0)
    else
      self.icon:Hide()
      self.value:SetPoint("LEFT", 8, 0)
    end
  end

  row.kind = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.kind:SetPoint("RIGHT", -8, 0)
  row.kind:SetJustifyH("RIGHT")
  row.kind:SetTextColor(unpack(THEME.note))

  row.suffix = entry.suffix
  row:SetScript("OnClick", function(self, mouseButton)
    if mouseButton == "RightButton" then
      WindowSetBinding(selectedModifier .. self.suffix, nil) -- right-click clears
    else
      selectedClick = selectedModifier .. self.suffix
    end
    ns.RefreshOptions()
  end)
  panel.bindingRows[i] = row
  return row
end

-- Read and write through the window's own role, never through whatever is
-- loaded at this instant.
function WindowRole()
  return panelRole or ns.GetMode()
end
ns.OptionsRole = WindowRole

function WindowSetBinding(key, binding, source)
  local role = WindowRole()
  if role == ns.GetMode() then
    return ns.SetBinding(key, binding, source)
  end
  return ns.WithMode(role, function() ns.SetBinding(key, binding, source) end)
end

local function RefreshBindings()
  local bindings = ns.BindingsFor(WindowRole())
  local _, known = ns.ScanSpellbook(true)

  for i, modifier in ipairs(MODIFIERS) do
    SetSelected(panel.modifierButtons[i], modifier.prefix == selectedModifier)
  end

  for i, entry in ipairs(MOUSE_KEYS) do
    local row = panel.bindingRows[i]
    local key = selectedModifier .. entry.suffix
    local binding = bindings[key]
    local text = BindingText(binding)

    row.selection:SetShown(key == selectedClick)
    SetBorderColor(row, key == selectedClick
      and { THEME.accent[1], THEME.accent[2], THEME.accent[3], 1 } or THEME.rule)

    row.value:SetText(text == "" and "|cff5a5a64Empty|r" or text)
    local iconTexture = binding and binding.kind == "spell" and known[binding.spell] and known[binding.spell].icon
    if row.SetIconShown then row:SetIconShown(iconTexture or nil) end
    if row.action then
      row.action:SetText(binding and "x" or "+")
      row.action.label:SetTextColor(binding and 0.95 or THEME.accent[1], binding and 0.45 or THEME.accent[2], binding and 0.45 or THEME.accent[3])
    end
    if binding and binding.kind == "spell" then
      row.kind:SetText("Spell")
      if known[binding.spell] then
        row.value:SetTextColor(unpack(THEME.label))
      else
        row.value:SetTextColor(0.95, 0.45, 0.45) -- you don't have this spell
      end
    elseif binding then
      row.kind:SetText("Command")
      row.value:SetTextColor(unpack(THEME.label))
    else
      row.kind:SetText("")
      row.value:SetTextColor(unpack(THEME.note))
    end
  end

  panel.clickHint:SetText(("Filling |cff4dc2ff%s|r - now click a spell on the right"):format(
    ns.DescribeKey(selectedClick)))
  if panel.bindingsHeading then
    local which = "None"
    for _, modifier in ipairs(MODIFIERS) do
      if modifier.prefix == selectedModifier then which = modifier.label end
    end
    panel.bindingsHeading:SetText(("Bindings |cff8a8a94(%s)|r"):format(which))
  end

  local used = 0
  for _ in pairs(bindings) do used = used + 1 end
  panel.bindingCount:SetText(("%d bound, saved in ForeverUI profile \"%s\""):format(
    used, ns.ActiveProfileName()))
end

local function BuildBindingsPage(page)
  panel.bindingRows, panel.spellRows, panel.modifierButtons = {}, {}, {}
  local CLICK_CARD_H = ClickCardH()

  -- Every role gets the Keybinds card now; the healer's plain three-card
  -- layout gave way to the owner's painted mock-up (2026-09-21).
  do
    -- One Keybinds card over the modifier and binding columns, headed by a
    -- glyph, the title and a line under it; the two columns get tab-styled
    -- headings inside it.
    local card = Card(page, TOP - 22, CLICK_CARD_H, nil, MOD_X - 6, KEY_X + KEY_W - MOD_X + 12)
    local glyph = FUI.Skin.Icon(page, "keybinds", 28, THEME.accent, "OVERLAY")
    glyph:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -8)
    local kTitle = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    kTitle:SetPoint("TOPLEFT", glyph, "TOPRIGHT", 10, 0)
    kTitle:SetFont(HEADING_FONT, 18)
    kTitle:SetText("Keybinds")
    kTitle:SetTextColor(1, 1, 1)
    local kSub = Note(page, "GameFontHighlightSmall")
    kSub:SetPoint("TOPLEFT", kTitle, "BOTTOMLEFT", 0, -2)
    kSub:SetText("Bind spells, macros or actions to keys and mouse buttons.")
    local kRule = page:CreateTexture(nil, "BORDER")
    kRule:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -46); kRule:SetPoint("TOPRIGHT", card, "TOPRIGHT", -1, -46); kRule:SetHeight(1)
    kRule:SetColorTexture(THEME.rule[1], THEME.rule[2], THEME.rule[3], 0.6)
    -- The tab-styled headings.
    local modTab = Button(page, MOD_W, "Modifier Key", nil)
    modTab:SetHeight(24)
    modTab:SetPoint("TOPLEFT", MOD_X, TOP - 52)
    SetSelected(modTab, true)
    local keyTab = Button(page, 120, "Mouse Key", nil)
    keyTab:SetHeight(24)
    keyTab:SetPoint("LEFT", modTab, "RIGHT", 4, 0)
    panel.modTab, panel.keyTab = modTab, keyTab
    Card(page, TOP - 22, CLICK_CARD_H, "Your Spells", SPELL_X - 6, SPELL_W + 12)
  end
  local tankShift = (ns.GetMode() ~= "dps" or ROLE_SKINS.dps) and 44 or 0   -- the Keybinds header takes a row
  -- The painted tank window is shorter than the flat one: its list shows
  -- nine rows (it scrolls) and everything under it comes up to meet it.
  local mode = ns.GetMode()
  local lift = ((mode == "tank" or mode == "dps") and ROLE_SKINS[mode]) and 34 or 0

  for i, modifier in ipairs(MODIFIERS) do
    local button = Button(page, MOD_W, modifier.label, function()
      selectedModifier = modifier.prefix
      selectedClick = selectedModifier .. (selectedClick:match("(%d)$") or "1")
      ns.RefreshOptions()
    end)
    button:SetHeight(28)
    button:SetPoint("TOPLEFT", MOD_X, TOP - 42 - tankShift - (i - 1) * 32)
    panel.modifierButtons[i] = button
  end

  local modNote = Note(page, "GameFontHighlightSmall")
  modNote:SetPoint("TOPLEFT", MOD_X, TOP - 310 - tankShift)
  modNote:SetWidth(MOD_W)
  modNote:SetJustifyH("LEFT")
  modNote:SetText("Hold this while you click a frame in the game.")

  do
    panel.bindingsHeading = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.bindingsHeading:SetPoint("TOPLEFT", KEY_X, TOP - 56)
    panel.bindingsHeading:SetFont(HEADING_FONT, 14)
    panel.bindingsHeading:SetTextColor(1, 1, 1)
    -- The healer's card says which modifier on its tab row; the painted
    -- mock-up has no second heading under the Mouse Key tab.
    panel.bindingsHeading:SetShown(not ROLE_SKINS[ns.GetMode()])
    local clearAll = Button(page, 80, "Clear All", function()
      for _, entry in ipairs(MOUSE_KEYS) do
        WindowSetBinding(selectedModifier .. entry.suffix, nil)
      end
      ns.RefreshOptions()
    end)
    clearAll:SetHeight(24)
    clearAll:SetPoint("TOPLEFT", KEY_X + KEY_W - 80, TOP - 52)
    panel.clearAllButton = clearAll
  end
  -- The bindings scroll. Ten rows fit the card; there are seventeen keys, and
  -- the window cannot grow to hold them all at once.
  local listTop = TOP - 40 - tankShift
  local listHeight = 316 + ((mode == "tank" and not ROLE_SKINS.tank) and 44 or 0) - (lift > 0 and 32 or 0)
  panel.bindingScroll, panel.bindingContent =
    MakeScrollList(page, KEY_X, KEY_W - 8, listHeight, listTop)
  for i, entry in ipairs(MOUSE_KEYS) do
    MouseRow(page, i, entry)
  end
  panel.bindingContent:SetHeight(math.max(1, #MOUSE_KEYS * KEY_ROW))

  panel.clickHint = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.clickHint:SetPoint("TOPLEFT", KEY_X, TOP - 366 - tankShift + lift)
  panel.clickHint:SetWidth(KEY_W)
  panel.clickHint:SetJustifyH("LEFT")

  local clear = Note(page, "GameFontHighlightSmall")
  clear:SetPoint("TOPLEFT", KEY_X, TOP - 382 - tankShift + lift)
  clear:SetWidth(KEY_W)
  clear:SetJustifyH("LEFT")
  clear:SetText("Right-click a box, or its x, to clear it.")
  clear:SetShown(not ROLE_SKINS[ns.GetMode()])   -- painted pages are tight; the x says it
  local actionsTop = TOP - 416 - tankShift + (ns.GetMode() == "tank" and 34 or 0) + lift

  -- Deliberate, separated, and never adjacent to the spell list. The list
  -- depends on the role and wraps three-to-a-row, so tank's five fit.
  local actions = CurrentActions()
  for i, action in ipairs(actions) do
    local button = Button(page, (KEY_W - 12) / 3, action.label, function()
      local binding = ns.CopyTable(action.binding)
      if action.taunt then
        binding.spell = ns.BestTauntSpell() -- nil for a class without one: plain engage
      end
      WindowSetBinding(selectedClick, binding, "action button")
      ns.RefreshOptions()
    end)
    button:SetPoint("TOPLEFT",
      KEY_X + ((i - 1) % 3) * ((KEY_W - 12) / 3 + 6),
      actionsTop - math.floor((i - 1) / 3) * 30)
    if action.icon or action.texture then
      button:SetHeight(28)
      local ic
      if action.texture then
        ic = button:CreateTexture(nil, "ARTWORK")
        ic:SetSize(16, 16)
        ic:SetTexture(action.texture)
      else
        ic = FUI.Skin.Icon(button, action.icon, 16, THEME.accent)
      end
      ic:SetPoint("LEFT", 8, 0)
      button.label:ClearAllPoints()
      button.label:SetPoint("LEFT", 28, 0)
      button.label:SetPoint("RIGHT", -4, 0)
      button.label:SetJustifyH("LEFT")
    end
  end
  local gridRows = math.ceil(#actions / 3)
  local belowGrid = actionsTop - gridRows * 30 - 4

  -- Healer: the class heal on left click. Tank: the engage/taunt clicks.
  -- DPS: the group utility -- what you press on someone ELSE mid-fight.
  panel.healButton = Button(page, KEY_W, "", function()
    local spell = ns.ApplyClassDefaults(true)
    local role = ns.GetMode()
    if role == "tank" then
      ns.Print(spell == "engage" and "left click engages whatever is on that player."
        or spell and ("left click engages; right click engages and casts %s."):format(spell)
        or "couldn't find a taunt for your class in your spellbook.")
    elseif role == "dps" then
      ns.Print(spell and ("left click casts %s on them."):format(spell)
        or "couldn't find a dispel or a group spell for your class -- pick one on the right.")
    elseif spell then
      ns.Print(("left click now casts %s."):format(spell))
    else
      ns.Print("couldn't find a healing spell for your class in your spellbook.")
    end
    ns.RefreshOptions()
  end)
  panel.healButton:SetPoint("TOPLEFT", KEY_X, belowGrid)

  -- Tank only: does the selected spell land on the player, or on what they pulled?
  panel.aimButton = Button(page, KEY_W, "", function()
    local binding = ns.db.bindings[selectedClick]
    if binding and binding.kind == "spell" then
      local copy = ns.CopyTable(binding)
      copy.their = (not binding.their) or nil
      WindowSetBinding(selectedClick, copy, "aim button")
      ns.RefreshOptions()
    end
  end)
  panel.aimButton:SetPoint("TOPLEFT", KEY_X, belowGrid - 26)
  panel.aimButton:SetShown(ns.GetMode() == "tank")

  panel.bindingCount = Note(page, "GameFontHighlightSmall")
  panel.bindingCount:SetPoint("TOPLEFT", KEY_X, TOP - 398 - tankShift + lift)
  panel.bindingCount:SetShown(ns.GetMode() ~= "tank")   -- the status row carries it
  panel.bindingCount:SetWidth(KEY_W)
  panel.bindingCount:SetJustifyH("LEFT")

  panel.spellCount = Note(page, "GameFontHighlightSmall")
  panel.spellCount:SetPoint("TOPLEFT", SPELL_X, TOP - 22)

  -- Search the spells: the list keeps only the names that mention it.
  local spellSearch = CreateFrame("EditBox", nil, page)
  spellSearch:SetSize(SPELL_W, 26)
  spellSearch:SetPoint("TOPLEFT", SPELL_X, TOP - 40)
  spellSearch:SetAutoFocus(false)
  spellSearch:SetFontObject("GameFontHighlight")
  spellSearch:SetTextInsets(26, 6, 0, 0)
  Fill(spellSearch, THEME.inset)
  Border(spellSearch)
  spellSearch.glass = FUI.Skin.Icon(spellSearch, "search", 14, THEME.accent, "OVERLAY")
  spellSearch.glass:SetPoint("LEFT", 7, 0)
  spellSearch.hint = Note(page, "GameFontHighlight")
  spellSearch.hint:SetPoint("LEFT", spellSearch, "LEFT", 26, 0)
  spellSearch.hint:SetText("Search spells...")
  spellSearch:SetScript("OnTextChanged", function(self)
    panel.spellFilter = (self:GetText() or ""):lower()
    self.hint:SetShown(panel.spellFilter == "")
    ns.RefreshOptions()
  end)
  spellSearch:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  spellSearch:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  panel.spellSearch = spellSearch

  panel.spellScroll, panel.spellContent =
    MakeScrollList(page, SPELL_X, SPELL_W, CLICK_LIST_HEIGHT, TOP - 74)

  panel.spellbookNote = Note(page, "GameFontHighlightSmall")
  panel.spellbookNote:SetPoint("TOPLEFT", SPELL_X, TOP - 372)
  panel.spellbookNote:SetWidth(SPELL_W)
  panel.spellbookNote:SetJustifyH("LEFT")
  panel.spellbookNote:SetText("This client's spellbook can't be read, so type your spells in below.")
  panel.spellbookNote:Hide()

  -- Type any spell, macro or item name. Needed when a client's spellbook
  -- can't be read, and handy for spells you haven't learned yet.
  local addLabel = Note(page, "GameFontHighlightSmall")
  addLabel:SetPoint("TOPLEFT", SPELL_X, TOP - 392)
  addLabel:SetText("Add a spell by name")

  local box = CreateFrame("EditBox", nil, page)
  box:SetSize(SPELL_W - 60, 26)
  box:SetPoint("TOPLEFT", SPELL_X, TOP - 410)
  box:SetAutoFocus(false)
  box:SetMaxLetters(40)
  box:SetFontObject("GameFontHighlight")
  box:SetTextInsets(6, 6, 0, 0)
  local boxBg = box:CreateTexture(nil, "BACKGROUND")
  boxBg:SetAllPoints()
  boxBg:SetColorTexture(unpack(THEME.inset))
  Border(box)
  box:SetScript("OnEscapePressed", box.ClearFocus)
  panel.spellBox = box

  local function addTyped()
    if ns.AddManualSpell(box:GetText()) then
      box:SetText("")
      ns.RefreshOptions()
    else
      ns.Print("type a spell name that isn't in the list already.")
    end
  end
  box:SetScript("OnEnterPressed", addTyped)

  local addButton = Button(page, 54, "Add", addTyped)
  addButton:SetHeight(26)
  addButton:SetPoint("LEFT", box, "RIGHT", 6, 0)
  addButton.fill:SetColorTexture(unpack(ROLE_SKINS[ns.GetMode()] and ROLE_SKINS[ns.GetMode()].save or { 0.16, 0.50, 0.85, 1 }))

  -- Under the cards: the two things you press rarely.
  panel.harmfulToggle = Button(page, SPELL_W, "", function()
    showHarmful = not showHarmful
    ns.RefreshOptions()
  end)
  panel.harmfulToggle:SetPoint("TOPLEFT", SPELL_X, TOP - CLICK_CARD_H - 12)
  panel.harmfulToggle:Hide()   -- the footer's tile clicks it
  panel.controls.showHarmful = panel.harmfulToggle

  panel.rankToggle = Button(page, SPELL_W, "", function()
    ns.SetSetting("showRanks", not ns.db.showRanks)
    ns.RefreshOptions()
  end)
  panel.rankToggle:SetPoint("TOPLEFT", SPELL_X, TOP - CLICK_CARD_H - 44)
  panel.rankToggle:Hide()      -- likewise, clicked from the footer
  panel.controls.showRanks = panel.rankToggle

  local reset = Button(page, KEY_W, "Reset every binding", function()
    ns.db.bindings = ns.CopyTable(ns.DEFAULT_BINDINGS)
    ns.ApplyBindings()
    ns.RefreshOptions()
  end)
  reset:SetPoint("TOPLEFT", KEY_X, TOP - CLICK_CARD_H - 12)
  reset:Hide()                 -- likewise
  panel.controls.resetBindings = reset
end

---------------------------------------------------------------------------
-- General / Layout / Indicators pages
---------------------------------------------------------------------------

local function BuildGeneralPage(page)
  Card(page, TOP, ns.standalone and 110 or 84, nil)
  Card(page, TOP - 120, 60, nil)
  Heading(page, TOP, "Frames")
  Stepper(page, TOP - 26, "Frame scale", "scale", 0.6, 1.6, 0.1, Percent)
  Stepper(page, TOP - 54, "Out-of-range fade", "rangeAlpha", 0.1, 0.9, 0.1, Percent)

  -- Moving (and locking) the frames is the footer's Move frames tile, one
  -- button on every page; this page used to carry two more that did the same.
  local preview = Button(page, 130, "Preview: party", function()
    ns.SetSetting("previewRaid", not ns.db.previewRaid)
  end)
  preview:SetPoint("BOTTOMLEFT", CONTENT_X, 14)
  panel.controls.preview = preview

  -- Inside ForeverUI there is one minimap button, ForeverUI's (General);
  -- this one is the standalone HealForever / TankForever's.
  if ns.standalone then
    Checkbox(page, TOP - 90, "Show the minimap button", "minimapButton")
  end
  -- A Mac's "natural scrolling" flips the wheel the game hears. Ticked, the
  -- way you roll is the binding that fires.
  Checkbox(page, TOP - 118, "Reverse the mouse wheel (Mac natural scrolling)", "reverseWheel")

  local reset = Button(page, 120, "Reset position", function()
    if InCombatLockdown() then
      ns.Print("can't move frames in combat.")
      return
    end
    ns.ResetPosition()
  end)
  reset:SetPoint("BOTTOMRIGHT", -14, 14)
end

local MEDIA = ns.MEDIA

local BAR_TEXTURES = {
  { label = "Smooth", value = MEDIA .. "bar-smooth" },
  { label = "Flat", value = MEDIA .. "bar-flat" },
  { label = "Glossy", value = MEDIA .. "bar-glossy" },
  { label = "Gradient", value = MEDIA .. "bar-gradient" },
  { label = "Ridged", value = MEDIA .. "bar-ridged" },
  { label = "Dim", value = MEDIA .. "bar-dim" },
  { label = "Blizzard", value = "Interface\\TargetingFrame\\UI-StatusBar" },
  { label = "Raid frame", value = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
}
-- The painted fills (ChatGPT art, grey so the bar colour tints them).
for _, name in ipairs({ "sheen", "vines", "energy", "swirl", "metal", "runic", "marble", "heartbeat", "honeycomb", "dotted", "starry", "braid" }) do
  BAR_TEXTURES[#BAR_TEXTURES + 1] = { label = name:sub(1, 1):upper() .. name:sub(2), value = MEDIA .. "fill-" .. name }
end

local FRAME_STYLES = {
  { label = "Bar (name left)", value = "bar" },
  { label = "Grid (big centred %)", value = "grid" },
}

local HEALTH_TEXT = {
  { label = "Missing health", value = "deficit" },
  { label = "Percent", value = "percent" },
  { label = "Current health", value = "current" },
  { label = "Nothing", value = "none" },
}

local BAR_COLORS = {
  { label = "Green for everyone", value = "green" },
  { label = "Class colours", value = "class" },
  { label = "This grid's colour", value = "role" },
  { label = "My own colour", value = "custom" },
}

local ANCHORS = {
  { label = "Left", value = "left" },
  { label = "Centre", value = "center" },
  { label = "Right", value = "right" },
}

local FILL_DIRECTIONS = {
  { label = "Left to right", value = "left" },
  { label = "Right to left", value = "right" },
  { label = "Bottom to top", value = "up" },
}

local BORDER_COLORS = {
  { label = "Black", value = "black" },
  { label = "Class colour", value = "class" },
  { label = "White", value = "white" },
  { label = "This grid's colour", value = "role" },
}

local function NameLength(v) return (v or 0) == 0 and "All" or tostring(v) end
local function SameAsFont(v) return (v or 0) == 0 and "Auto" or tostring(v) end
local function Off(v) return (v or 0) == 0 and "Off" or (v .. "%") end
local function Pixels(v) return (v or 0) == 0 and "None" or (v .. " px") end
local function Percent100(v) return (v or 100) .. "%" end

local NAME_TEXT = {
  { label = "Player's name", value = "name" },
  { label = "Their class", value = "class" },
  { label = "Nothing", value = "none" },
}

-- Bar backgrounds as picture tiles: the plain ones first, then the painted
-- surfaces (ChatGPT art, Media/bg-*.tga).
local BG_TILES = {
  { label = "None", value = "none" },
  { label = "Dark plate", value = "dark" },
  { label = "Solid", value = "solid" },
  { label = "Class", value = "class" },
  { label = "Grid colour", value = "role" },
  { label = "Charcoal", value = "tex:charcoal" }, { label = "Gradient", value = "tex:gradient" },
  { label = "Glass", value = "tex:glass" }, { label = "Carbon", value = "tex:carbon" },
  { label = "Metal", value = "tex:metal" }, { label = "Runes", value = "tex:runes" },
  { label = "Wood", value = "tex:wood" }, { label = "Slate", value = "tex:slate" },
  { label = "Diagonal", value = "tex:diagonal" }, { label = "Hex", value = "tex:hex" },
  { label = "Dots", value = "tex:dots" }, { label = "Pulse", value = "tex:pulse" },
  { label = "Nebula", value = "tex:nebula" }, { label = "Leaves", value = "tex:leaves" },
  { label = "Embers", value = "tex:embers" }, { label = "Frost", value = "tex:frost" },
}

-- A list that opens under its button, each choice with a sample: the bar
-- textures show their own fill, so you pick what you can see.
local openList
local function Dropdown(page, x, y, w, key, choices, sample)
  local button = Button(page, w, "", nil)
  button:SetHeight(26)
  button:SetPoint("TOPLEFT", x, y)
  button.label:ClearAllPoints()
  button.label:SetPoint("LEFT", sample and 96 or 10, 0)
  button.label:SetPoint("RIGHT", -24, 0)
  button.label:SetJustifyH("LEFT")
  local arrow = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  arrow:SetPoint("RIGHT", -8, 0)
  arrow:SetText("v")
  arrow:SetTextColor(unpack(THEME.accent))
  local swatch
  if sample then
    swatch = button:CreateTexture(nil, "ARTWORK")
    swatch:SetPoint("LEFT", 6, 0)
    swatch:SetSize(80, 14)
  end
  local list
  button:SetScript("OnClick", function()
    if openList and openList ~= list then openList:Hide() end
    if not list then
      list = CreateFrame("Frame", nil, button)
      list:SetFrameStrata("FULLSCREEN_DIALOG")
      list:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
      -- A long list opens in two columns, so it stays inside the window.
      local perCol = #choices > 12 and math.ceil(#choices / 2) or #choices
      local cols = math.ceil(#choices / perCol)
      list:SetSize(w * cols + 2 * (cols - 1), perCol * 24 + 4)
      Fill(list, { 0.02, 0.02, 0.03, 0.97 })
      Border(list)
      for i, choice in ipairs(choices) do
        local row = Button(list, w - 4, choice.label, function()
          ns.SetSetting(key, choice.value)
          list:Hide()
        end)
        row:SetHeight(22)
        row:SetPoint("TOPLEFT", 2 + math.floor((i - 1) / perCol) * (w + 2), -2 - ((i - 1) % perCol) * 24)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", sample and 96 or 10, 0)
        row.label:SetJustifyH("LEFT")
        if sample then
          local t = row:CreateTexture(nil, "ARTWORK")
          t:SetPoint("LEFT", 6, 0)
          t:SetSize(80, 12)
          sample(t, choice.value)
        end
      end
      list:Hide()
    end
    list:SetShown(not list:IsShown())
    openList = list:IsShown() and list or nil
  end)
  local control = { button = button }
  function control.refresh()
    local shown = "?"
    for _, choice in ipairs(choices) do
      if choice.value == ns.db[key] then shown = choice.label end
    end
    button:SetText(shown)
    if swatch then sample(swatch, ns.db[key]) end
  end
  panel.controls["dd:" .. key] = control
  return control
end

local function TextureSample(t, value)
  t:SetTexture(value)
  t:SetVertexColor(0.18, 0.72, 0.26)
end

local function StyleSample(t, value)
  t:SetColorTexture(0.18, 0.72, 0.26, value == "grid" and 0.6 or 1)
end

-- The background tiles: a picture of each, the chosen one lit.
local function TileGrid(page, x, y, perRow, tileW, tileH)
  local tiles = {}
  for i, choice in ipairs(BG_TILES) do
    local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
    local tile = CreateFrame("Button", nil, page)
    tile:SetSize(tileW, tileH)
    tile:SetPoint("TOPLEFT", x + col * (tileW + 6), y - row * (tileH + 18))
    Border(tile)
    local art = tile:CreateTexture(nil, "ARTWORK")
    art:SetPoint("TOPLEFT", 1, -1)
    art:SetPoint("BOTTOMRIGHT", -1, 1)
    local v = choice.value
    if v:sub(1, 4) == "tex:" then
      art:SetTexture(ns.BAR_BG_PATH .. v:sub(5))
    elseif v == "none" then
      art:SetColorTexture(0, 0, 0, 0.25)
    elseif v == "role" then
      local c = ns.RoleLook().accent
      art:SetColorTexture(c[1] * 0.3, c[2] * 0.3, c[3] * 0.3, 1)
    elseif v == "class" then
      art:SetColorTexture(0.30, 0.20, 0.10, 1)
    elseif v == "dark" then
      art:SetColorTexture(0.12, 0.12, 0.12, 1)
    end
    tile.art = art
    local label = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOP", tile, "BOTTOM", 0, -2)
    label:SetText(choice.label)
    label:SetTextColor(unpack(THEME.note))
    tile:SetScript("OnClick", function() ns.SetSetting("barBackground", v) end)
    tile.value = v
    tiles[#tiles + 1] = tile
  end
  local control = {}
  function control.refresh()
    for _, tile in ipairs(tiles) do
      local on = tile.value == ns.db.barBackground
      SetBorderColor(tile, on and { THEME.accent[1], THEME.accent[2], THEME.accent[3], 1 } or THEME.rule)
      if tile.value == "solid" then
        local c = ns.db.barBackgroundColor or { 0.12, 0.12, 0.12 }
        tile.art:SetColorTexture(c[1], c[2], c[3], 1)
      end
    end
  end
  panel.controls["tiles:barBackground"] = control
  return control
end

-- A small live preview of this grid: plain (never secure) frames drawn by
-- the grid's own code, redrawn whenever a setting changes.
local function LivePreview(page, x, y, w, h)
  local holder = CreateFrame("Frame", nil, page)
  holder:SetPoint("TOPLEFT", x, y)
  holder:SetSize(w, h)
  local buttons = {}
  local role = panelRole
  for i = 1, 14 do
    local b = CreateFrame("Button", nil, holder, "ForeverUIFramesUnitButtonBaseTemplate")
    b:EnableMouse(false)
    b.gridRole = role
    b.previewState = ns.SimMember and ns.SimMember(i) or { name = "Preview " .. i, health = 1, healthMax = 1 }
    b.previewState.unit = nil
    buttons[i] = b
  end
  local control = {}
  function control.refresh()
    local fw, fh = ns.db.frameWidth or 120, ns.db.frameHeight or 36
    local colW = (w - 8) / 2
    local scale = math.min(1, colW / fw, ((h - 6) / 7) / (fh + 4))
    for i, b in ipairs(buttons) do
      b:SetScale(scale)
      b:SetSize(fw, fh)
      b:ClearAllPoints()
      local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
      b:SetPoint("TOPLEFT", holder, "TOPLEFT", (col * (colW + 8)) / scale, -(row * (fh + 4)))
      ns.StyleButton(b)
      pcall(ns.Render, b, b.previewState)
    end
  end
  panel.controls["livePreview"] = control
  return control
end

local APPEARANCE_TABS = {
  { key = "health", label = "Health Bar" },
  { key = "power", label = "Power Bar" },
  { key = "text", label = "Text" },
  { key = "borders", label = "Borders" },
  { key = "size", label = "Size" },
}

local function BuildAppearancePage(page)
  -- Sub-tabs across the top, the owner's mock-up: one page per part of the bar.
  local tabs, panes = {}, {}
  local function Show(key)
    for k, pane in pairs(panes) do pane:SetShown(k == key) end
    for k, tab in pairs(tabs) do SetSelected(tab, k == key) end
    if openList then openList:Hide(); openList = nil end
  end
  for i, t in ipairs(APPEARANCE_TABS) do
    local tab = Button(page, 108, t.label, function() Show(t.key) end)
    tab:SetHeight(24)
    tab:SetPoint("TOPLEFT", CONTENT_X - 6 + (i - 1) * 112, TOP + 6)
    tabs[t.key] = tab
    local pane = CreateFrame("Frame", nil, page)
    pane:SetPoint("TOPLEFT", 0, -34)
    pane:SetPoint("BOTTOMRIGHT")
    panes[t.key] = pane
  end
  panel.appearanceTabs = tabs

  -- HEALTH BAR: style, texture, background tiles | colours, advanced,
  -- transparency | live preview.
  local p = panes.health
  local A, B, C = CONTENT_X, CONTENT_X + 290, CONTENT_X + 538
  Card(p, TOP, 470, nil, A - 6, 278)
  Card(p, TOP, 470, nil, B - 6, 240)
  Card(p, TOP, 470, nil, C - 6, 280)
  local function head(x, y, text)
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetFont(HEADING_FONT, 15)
    fs:SetTextColor(unpack(THEME.heading))
    fs:SetText(text)
  end
  head(A, TOP, "Bar Style")
  Dropdown(p, A, TOP - 22, 260, "frameStyle", FRAME_STYLES, StyleSample)
  head(A, TOP - 58, "Bar Texture")
  Dropdown(p, A, TOP - 80, 260, "barTexture", BAR_TEXTURES, TextureSample)
  head(A, TOP - 116, "Bar Background")
  TileGrid(p, A, TOP - 138, 4, 60, 30)

  COLUMN_W = 226
  head(B, TOP, "Bar Colours")
  ColumnCycler(p, B, TOP - 22, "Colour by", "barColor", BAR_COLORS)
  ColumnSwatch(p, B, TOP - 72, "Full health (own colour)", "barCustomColor")
  ColumnSwatch(p, B, TOP - 98, "Low health", "lowHealthColor")
  ColumnStepper(p, B, TOP - 122, "    ...at or below", "lowHealthThreshold", 0, 90, 5, Off)
  ColumnSwatch(p, B, TOP - 148, "Critical health", "critHealthColor")
  ColumnStepper(p, B, TOP - 172, "    ...at or below", "critHealthThreshold", 0, 60, 5, Off)
  ColumnSwatch(p, B, TOP - 198, "Background", "barBackgroundColor")
  head(B, TOP - 232, "Advanced")
  Checkbox(p, TOP - 256, "Gradient fill", "barGradient", { x = B })
  Checkbox(p, TOP - 280, "Show loss (health lost in red)", "showLoss", { x = B })
  Checkbox(p, TOP - 304, "Animate on heal", "animateHeal", { x = B })
  Checkbox(p, TOP - 328, "Blend green to yellow to red", "healthColor", { x = B })
  head(B, TOP - 362, "Transparency")
  ColumnStepper(p, B, TOP - 388, "Health fill", "healthAlpha", 10, 100, 10, Percent100)
  ColumnStepper(p, B, TOP - 414, "Background", "barOpacity", 0, 100, 10, Percent100)

  head(C, TOP, "Live Preview")
  LivePreview(p, C, TOP - 26, 268, 430)

  -- POWER BAR
  p = panes.power
  Card(p, TOP, 120, nil)
  Heading(p, TOP, "Power bar")
  Checkbox(p, TOP - 28, "Show a mana bar under each frame", "powerBarHeight", {
    name = "showMana",
    get = function(height) return (height or 0) > 0 end,
    set = function(checked) return checked and 5 or 0 end,
  })
  Stepper(p, TOP - 56, "Mana bar height", "powerBarHeight", 0, 10, 1, Plain)

  -- TEXT
  p = panes.text
  Card(p, TOP, 470, nil)
  Heading(p, TOP, "Text")
  Cycler(p, TOP - 26, "Written on the frame", "nameText", NAME_TEXT)
  Cycler(p, TOP - 54, "Health text", "healthText", HEALTH_TEXT)
  Stepper(p, TOP - 82, "Font size", "fontSize", 8, 18, 1, Plain)
  Stepper(p, TOP - 110, "Health text size", "healthFontSize", 0, 18, 1, SameAsFont)
  Cycler(p, TOP - 138, "Name position", "nameAnchor", ANCHORS)
  Stepper(p, TOP - 166, "Name length", "nameLength", 0, 20, 1, NameLength)
  Cycler(p, TOP - 194, "Health text position", "healthAnchor", ANCHORS)
  Checkbox(p, TOP - 224, "Colour names by class instead of the bar", "classColorNames")
  local names = Checkbox(p, TOP - 252, "Show names on the frames", "nameText",
    { name = "showNames", get = function(value) return value ~= "none" end })
  names.box:SetScript("OnClick", function(self)
    ns.SetNamesShown(self:GetChecked() and true or false)
  end)
  local numbers = Checkbox(p, TOP - 252, "Show health text", "healthText",
    { name = "showHealthText", x = CONTENT_X + 250, get = function(value) return value ~= "none" end })
  numbers.box:SetScript("OnClick", function(self)
    ns.SetHealthTextShown(self:GetChecked() and true or false)
  end)

  -- BORDERS
  p = panes.borders
  Card(p, TOP, 100, nil)
  Heading(p, TOP, "Border")
  Stepper(p, TOP - 26, "Border", "borderSize", 0, 2, 1, Pixels)
  Cycler(p, TOP - 54, "Border colour", "borderColor", BORDER_COLORS)

  -- SIZE
  p = panes.size
  Card(p, TOP, 130, nil)
  Heading(p, TOP, "Frame size")
  Stepper(p, TOP - 26, "Width", "frameWidth", 80, 220, 10, Plain)
  Stepper(p, TOP - 54, "Height", "frameHeight", 24, 64, 2, Plain)
  Cycler(p, TOP - 82, "Bars fill", "fillDirection", FILL_DIRECTIONS)
  local note = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", CONTENT_X, TOP - 140)
  note:SetTextColor(unpack(THEME.note))
  note:SetText("Size changes wait for the end of combat.")

  Show("health")
end

local SORT_MODES = {
  { label = "Group order", value = "index" },
  { label = "Name", value = "name" },
  { label = "Class", value = "class" },
  { label = "Raid group", value = "group" },
  { label = "Role (Main Tank first)", value = "role" },
  { label = "My role order (Roles page)", value = "roles" },
}

local function BuildLayoutPage(page)
  Card(page, TOP, 162, nil)
  Card(page, TOP - 168, 84, nil)
  Card(page, TOP - 258, 116, nil)
  Heading(page, TOP, "Arrangement")
  Cycler(page, TOP - 26, "Sort by", "sortMode", SORT_MODES)
  Checkbox(page, TOP - 54, "Reverse the order", "sortReverse")
  Checkbox(page, TOP - 80, "Stack main tanks at the top", "tanksFirst")
  Checkbox(page, TOP - 106, "Lay each group out in a row instead of a column", "horizontal")
  Checkbox(page, TOP - 132, "Show pets next to the party", "showPets")

  Heading(page, TOP - 168, "Raid")
  Stepper(page, TOP - 194, "Groups per row", "groupsPerRow", 1, 8, 1, Plain)
  Checkbox(page, TOP - 222, "Show all raid groups when in a raid", "useRaidFrames")

  Heading(page, TOP - 258, "Blizzard's frames")
  Checkbox(page, TOP - 284, "Hide Blizzard's party frames", "hideBlizzardParty")
  Checkbox(page, TOP - 310, "Hide Blizzard's raid frames (keeps the raid tools panel)", "hideBlizzardRaid")

  local note = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", CONTENT_X, TOP - 338)
  note:SetTextColor(unpack(THEME.note))
  note:SetText("Turning those back off needs a /reload. Roles in Classic come from raid Main Tank assignments.")

  Card(page, TOP - 384, 84, nil)
  Heading(page, TOP - 384, "Focus group")
  Checkbox(page, TOP - 410, "Focus group: a frame for whoever you focus, plus players you pin", "showFocus")
  Stepper(page, TOP - 438, "Size next to the main frames", "focusScale", 0.8, 2.0, 0.1, Percent)
end

-- Every indicator a frame can carry, each with its own switch. `set`/`get`
-- adapt settings that aren't plain true/false. The ones marked `elsewhere`
-- have their switch on that page instead (they used to be on both, 25 Sept
-- 2026): they aren't drawn here, but Everything on / off still covers them,
-- so off is still a bare bar.
local INDICATORS = {
  { "Names", "nameText", special = "names", elsewhere = "Appearance" },
  { "Health text (percent / missing)", "healthText", special = "health", elsewhere = "Appearance" },
  { "Mana bar", "powerBarHeight", get = function(v) return (v or 0) > 0 end,
    set = function(on) return on and 5 or 0 end, elsewhere = "Appearance" },
  { "Yellow, then red, as health drops", "healthColor", elsewhere = "Appearance" },
  { "Fade players out of range", "fadeRange" },
  { "Highlight my current target", "showTargetBorder" },
  { "Role marker (T / M / H / R)", "showRole", elsewhere = "Roles" },
  { "Red border on whoever has aggro", "showThreat" },
  { "Incoming heals", "showIncoming" },
  { "Overhealing", "showOverheal" },
  { "Overheal lane (shows waste past the end)", "overhealLane" },
  -- second column
  { "Debuffs I can dispel", "showDispel" },
  { "...drawn by the game in combat", "gameDispels" },
  { "My HoTs and shields (the HoT row)", "showHots" },
  { "...drawn by the game (real timers, in combat too)", "gameHots" },
  { "...kept showing in combat", "inferHots" },
  { "Everyone's buffs & HoTs, drawn by the game (test)", "gameBuffs" },
  { "...only in combat", "gameBuffsCombatOnly" },
  { "Watched auras (Auras page)", "showWatch" },
  { "Missing buffs", "showMissingBuffs" },
  { "My debuffs on my target (own row)", "showTargetDebuffs" },
  { "Focus group (your focus + pinned players)", "showFocus", elsewhere = "Layout" },
  { "What my clicks cast, in the tooltip", "clickTooltip" },
}
ns.INDICATORS = INDICATORS

-- Tank mode adds its own rows to the "On each frame" list.
local TANK_INDICATORS = {
  { "Who they are fighting (enemy name)", "showTheirTarget" },
  { "Threat meter: how close to pulling my target", "showThreatMeter" },
  { "...with the percent", "showThreatPercent" },
  { "Loose players listed at the top (clickable)", "looseList" },
  { "AGGRO alarm in the middle of the screen", "threatAlert" },
  { "...with a warning sound", "threatSound" },
  { "...and when my target isn't on me", "alertLostTarget" },
}

-- ...and DPS mode its own (OnYou.lua).
local DPS_INDICATORS = {
  { "IT'S ON YOU in the middle of the screen when my target turns on me (groups)", "onYouAlert" },
  { "...with a warning sound", "onYouSound" },
}

-- The list actually shown depends on the role.
local function CurrentIndicators()
  local extra = ({ tank = TANK_INDICATORS, dps = DPS_INDICATORS })[ns.GetMode()]
  if not extra then
    return INDICATORS
  end
  local combined = {}
  for _, item in ipairs(INDICATORS) do combined[#combined + 1] = item end
  for _, item in ipairs(extra) do combined[#combined + 1] = item end
  return combined
end

-- Everything on, or everything off, in one go.
function ns.SetAllIndicators(on)
  for _, item in ipairs(CurrentIndicators()) do
    if item.special == "names" then
      ns.SetNamesShown(on)
    elseif item.special == "health" then
      ns.SetHealthTextShown(on)
    elseif item.set then
      ns.SetSetting(item[2], item.set(on))
    else
      ns.SetSetting(item[2], on)
    end
  end
end

local function BuildIndicatorsPage(page)
  local items = {}
  for _, item in ipairs(CurrentIndicators()) do
    if not item.elsewhere then items[#items + 1] = item end
  end
  local split = math.ceil(#items / 2)          -- how many sit in the first column

  -- The shell first, at the top where it can be found: the coloured border
  -- and title strip around this grid. People who want bars and nothing else
  -- were having to ask for it.
  local look = ns.ROLE_CHROME and ns.ROLE_CHROME[ns.GetMode()] or nil
  local label = (look and look.label) or "this grid"
  local SHELL_H = 54
  Card(page, TOP, SHELL_H, nil, CONTENT_X - 6, 500)
  Heading(page, TOP, ("The %s window"):format(label))
  Checkbox(page, TOP - 26, ("Show the %s border and title bar"):format(label), "showChrome",
    { name = "showChrome" })

  local top = TOP - SHELL_H - 14                -- everything else moves down
  local afterRows = top - 2 - split * 24 - 12   -- y just below the two columns
  Card(page, top, 30 + split * 24, nil, CONTENT_X - 6, 500)
  Heading(page, top, "On each frame - tick what you want to see")
  for i, item in ipairs(items) do
    local column = i > split and 1 or 0
    local row = column == 1 and (i - split) or i
    Checkbox(page, top - 2 - row * 24, item[1], item[2],
      { name = item[2], x = CONTENT_X + column * 250, get = item.get, set = item.set })
  end
  local elsewhere = Note(page, "GameFontHighlightSmall")
  elsewhere:SetPoint("TOPLEFT", CONTENT_X, afterRows - 4)
  elsewhere:SetWidth(240)
  elsewhere:SetJustifyH("LEFT")
  elsewhere:SetText("Names, health text, mana bar and colours: Appearance. Role badges: Roles. "
    .. "Focus group: Layout. Everything on / off covers those too.")
  local allOn = Button(page, 120, "Everything on", function() ns.SetAllIndicators(true) end)
  allOn:SetPoint("TOPLEFT", CONTENT_X + 250, afterRows)
  local allOff = Button(page, 120, "Everything off", function() ns.SetAllIndicators(false) end)
  allOff:SetPoint("TOPLEFT", CONTENT_X + 376, afterRows)

  Stepper(page, afterRows - 30, "Count as a HoT up to", "hotMaxDuration", 15, 120, 15, Seconds)
  Stepper(page, afterRows - 56, "Target debuff icon size", "targetIconSize", 18, 48, 2, Plain)
  -- How much of the bar the overheal lane keeps back.
  Stepper(page, afterRows - 82, "Overheal lane width", "overhealLanePercent", 5, 40, 5,
    function(v) return ((v or 15) .. "%") end)
  -- The game's tooltip follows the cursor, which on a grid means it covers
  -- the frame you are pointing at. Beside the grid, or not at all.
  Cycler(page, afterRows - 108, "Tooltip when hovering a frame", "frameTooltip", {
    { value = "cursor", label = "At the cursor" },
    { value = "frame", label = "Beside the frames" },
    { value = "off", label = "Don't show one" },
  })

  -- Missing buffs: one switch, then a line per buff your class hands out.
  local buffTop = afterRows - 140
  Card(page, buffTop, 96, nil, CONTENT_X - 6, 500)
  Heading(page, buffTop, "Which buffs count as missing (click to switch)")
  panel.buffRows = {}
  for i = 1, 3 do
    local row = CreateFrame("Button", nil, page)
    row:SetSize(440, 20)
    row:SetPoint("TOPLEFT", CONTENT_X + 4, buffTop - 4 - i * 22)
    row:RegisterForClicks("AnyUp")
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(unpack(THEME.hover))
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", 4, 0)
    row.text:SetJustifyH("LEFT")
    row:SetScript("OnClick", function(self)
      if self.spell and self.known then
        ns.SetGroupBuff(self.spell, not self.on)
      end
    end)
    panel.buffRows[i] = row
  end
  panel.buffNote = Note(page, "GameFontHighlightSmall")
  panel.buffNote:SetPoint("TOPLEFT", CONTENT_X + 8, buffTop - 28)
  panel.buffNote:SetWidth(440)
  panel.buffNote:SetJustifyH("LEFT")
  panel.controls.groupBuffs = { refresh = function()
    local choices = ns.GroupBuffChoices()
    for i, row in ipairs(panel.buffRows) do
      local choice = choices[i]
      row:SetShown(choice ~= nil)
      if choice then
        row.spell, row.known, row.on = choice.entry.spell, choice.known, choice.on
        if not choice.known then
          row.text:SetText("|cff5a5a64" .. choice.label .. "  (not learned yet)|r")
        elseif choice.on then
          row.text:SetText("|cff4dc2ffon|r    " .. choice.label)
        else
          row.text:SetText("|cff8a8a94off|r   " .. choice.label)
        end
      end
    end
    panel.buffNote:SetShown(#choices == 0)
    panel.buffNote:SetText("Your class doesn't hand out a group buff, so there is nothing to track here.")
  end }
end

---------------------------------------------------------------------------
-- Roles page: say who is what, because Classic usually can't
---------------------------------------------------------------------------

local ROLE_LABELS = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage", MELEE = "Melee", RANGED = "Ranged",
  MAINTANK = "Main Tank", MAINASSIST = "Main Assist" }

local function RefreshRoles()
  local page = panel.pages.roles
  local names = ns.GroupNames()
  for i, name in ipairs(names) do
    local row = RowAt(panel.roleRows, page.content, i, function(self, mouseButton)
      -- In a group the game hides names, and a role you set is kept by
      -- name: say so instead of failing silently.
      if issecretvalue and issecretvalue(self.playerName) then
        ns.Print("in a group the game hides names, so roles can't be set by hand here. "
          .. "The game's own role (dungeon finder or role check) is used, and Frame order still sorts by it.")
        return
      end
      if mouseButton == "RightButton" then
        ns.ToggleFocusName(self.playerName)
      else
        ns.CycleManualRole(self.playerName)
      end
      ns.RefreshOptions()
    end, COLUMN_WIDTH + 120)
    row.playerName = name
    row.icon:SetColorTexture(0, 0, 0, 0)
    local manual = ns.db.manualRoles and ns.db.manualRoles[name]
    if manual then
      local mark = ns.ROLE_MARKS[manual]
      row.text:SetText(("%s   |cff%02x%02x%02x%s|r  |cff8a8a94(set by you)|r"):format(name,
        math.floor(mark[2] * 255), math.floor(mark[3] * 255), math.floor(mark[4] * 255), ROLE_LABELS[manual] or manual))
    else
      row.text:SetText(name .. "   |cff8a8a94automatic|r")
    end
    if ns.IsFocusName(name) then
      row.text:SetText(row.text:GetText() .. "   |cffffd133[Focus]|r")
    end
  end
  HideFrom(panel.roleRows, #names + 1)
  for i, row in ipairs(panel.orderRows or {}) do
    local role = ns.RoleOrder()[i]
    row.text:SetText(("%d.  %s"):format(i, ROLE_LABELS[role] or role))
  end
  if panel.orderState then
    panel.orderState:SetText(ns.db.sortMode == "roles" and "|cff4de64dIn use|r - Layout > Sort by"
      or "Not in use - press an arrow, or set Layout > Sort by to \"My role order\"")
  end
  page.content:SetHeight(math.max(1, #names * ROW_HEIGHT))
end

local function BuildRolesPage(page)
  -- The list is shorter than the other pages' (a party fits, a raid
  -- scrolls) to make room for the badges underneath it.
  local ROLE_LIST_H = 180
  Card(page, TOP - 16, ROLE_LIST_H + 56, nil, CONTENT_X - 6, COLUMN_WIDTH + 132)
  local help = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  help:SetPoint("TOPLEFT", CONTENT_X, TOP)
  help:SetTextColor(unpack(THEME.label))
  help:SetText("Left-click a player to set their role. Right-click to put them in your Focus group (Layout).")

  local listLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  listLabel:SetPoint("TOPLEFT", CONTENT_X, TOP - 20)
  listLabel:SetTextColor(unpack(THEME.heading))
  listLabel:SetText("Your group")
  page.listLabel = listLabel

  page.scroll, page.content = MakeScrollList(page, CONTENT_X, COLUMN_WIDTH + 120, ROLE_LIST_H, TOP - 46)
  panel.roleRows = {}

  -- Role badges on every frame (owner, 23 Sept 2026): on or off, a badge or
  -- the old letter, where it sits - inside the frame or hanging off either
  -- side of it - and how big.
  local x, y0 = CONTENT_X, TOP - ROLE_LIST_H - 86
  Card(page, y0, 204, nil, CONTENT_X - 6, COLUMN_WIDTH + 132)
  Heading(page, y0, "Role badges on the frames")
  for i, badge in ipairs({ "tank", "healer", "dps" }) do
    local art = page:CreateTexture(nil, "ARTWORK")
    art:SetSize(22, 22)
    art:SetPoint("TOPLEFT", x + 236 + (i - 1) * 32, y0 + 2)
    art:SetTexture(ns.RoleBadgeTexture(badge))
  end
  Checkbox(page, y0 - 28, "Show each player's role", "showRole", { name = "roles:showRole", x = x })

  local looks = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  looks:SetPoint("TOPLEFT", x, y0 - 58)
  looks:SetTextColor(unpack(THEME.label))
  looks:SetText("Looks like")
  page.roleStyles = {}
  for i, choice in ipairs({ { "icon", "Badge" }, { "letter", "Letter" } }) do
    local button = Button(page, 70, choice[2], function() ns.SetSetting("roleStyle", choice[1]) end)
    button:SetPoint("TOPLEFT", x + 90 + (i - 1) * 76, y0 - 54)
    button.style = choice[1]
    page.roleStyles[i] = button
  end

  -- Where: the frame in the middle (a green strip, like a health bar) with
  -- its nine places, and a column of three outside it on each side.
  local where = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  where:SetPoint("TOPLEFT", x, y0 - 86)
  where:SetTextColor(unpack(THEME.label))
  where:SetText("Where")
  local mapTop = y0 - 104
  local strip = page:CreateTexture(nil, "ARTWORK")
  strip:SetPoint("TOPLEFT", x + 40, mapTop + 3)
  strip:SetSize(108, 62)
  strip:SetColorTexture(0.18, 0.45, 0.22, 0.55)
  local MAP = {
    { "OUTTOPLEFT", "TOPLEFT", "TOP", "TOPRIGHT", "OUTTOPRIGHT" },
    { "OUTLEFT", "LEFT", "CENTER", "RIGHT", "OUTRIGHT" },
    { "OUTBOTTOMLEFT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT", "OUTBOTTOMRIGHT" },
  }
  local COLUMN_X = { 0, 44, 78, 112, 156 }
  page.rolePlaces = {}
  for row, keys in ipairs(MAP) do
    for column, key in ipairs(keys) do
      local cell = Button(page, 30, "", function() ns.SetSetting("rolePosition", key) end)
      cell:SetHeight(16)
      cell:SetPoint("TOPLEFT", x + COLUMN_X[column], mapTop - (row - 1) * 20)
      page.rolePlaces[key] = cell
    end
  end
  for _, spot in ipairs({ { -2, "outside" }, { 62, "on the frame" }, { 152, "outside" } }) do
    local label = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x + spot[1], mapTop - 64)
    label:SetTextColor(unpack(THEME.note))
    label:SetText(spot[2])
  end
  page.rolePlace = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  page.rolePlace:SetPoint("TOPLEFT", x + 200, mapTop + 2)
  page.rolePlace:SetWidth(130)
  page.rolePlace:SetJustifyH("LEFT")
  page.rolePlace:SetTextColor(unpack(ns.THEME.value))

  local sizeLabel = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  sizeLabel:SetPoint("TOPLEFT", x + 200, mapTop - 26)
  sizeLabel:SetTextColor(unpack(THEME.label))
  sizeLabel:SetText("Size")
  local smaller = Button(page, 22, "-", function()
    ns.SetSetting("roleSize", math.max(8, (ns.db.roleSize or 12) - 1))
  end)
  smaller:SetPoint("TOPLEFT", x + 200, mapTop - 44)
  page.roleSize = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  page.roleSize:SetPoint("TOP", page, "TOPLEFT", x + 244, mapTop - 47)
  page.roleSize:SetTextColor(unpack(ns.THEME.value))
  local bigger = Button(page, 22, "+", function()
    ns.SetSetting("roleSize", math.min(32, (ns.db.roleSize or 12) + 1))
  end)
  bigger:SetPoint("TOPLEFT", x + 266, mapTop - 44)
  panel.controls.roleBadges = { refresh = function()
    for _, button in ipairs(page.roleStyles) do
      SetSelected(button, button.style == (ns.db.roleStyle or "icon"))
    end
    local current = ns.db.rolePosition or "TOPLEFT"
    for key, cell in pairs(page.rolePlaces) do
      SetSelected(cell, key == current)
    end
    page.rolePlace:SetText(ns.ROLE_PLACE_LABELS[current] or current)
    page.roleSize:SetText(ns.db.roleSize or 12)
  end }

  local note = Note(page, "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", CONTENT_X + COLUMN_WIDTH + 146, TOP - 20)
  note:SetWidth(200)
  note:SetJustifyH("LEFT")
  note:SetText("Classic has no specs to read, so the game rarely knows who the tank is. "
    .. "What you set here is remembered by name and shows as the player's role badge. "
    .. "You can also type  /fui frames role Name tank")

  -- Frame order: which role sits on top, and the switch that uses it.
  local orderX = CONTENT_X + COLUMN_WIDTH + 146
  local orderLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  orderLabel:SetPoint("TOPLEFT", orderX, TOP - 130)
  orderLabel:SetTextColor(unpack(THEME.heading))
  orderLabel:SetText("Frame order")
  panel.orderRows = {}
  for i = 1, 4 do
    local y = TOP - 130 - i * 26
    local text = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", orderX, y - 4)
    text:SetTextColor(unpack(THEME.label))
    -- Moving a role means you want this order: switch it on rather than
    -- leave the arrows doing nothing you can see (owner, 25 Sept 2026).
    local function Move(delta)
      ns.MoveRoleOrder(i, delta)
      if ns.db.sortMode ~= "roles" then
        ns.SetSetting("sortMode", "roles")
      end
      ns.RefreshOptions()
    end
    local up = Button(page, 24, "^", function() Move(-1) end)
    up:SetPoint("TOPLEFT", orderX + 110, y)
    local down = Button(page, 24, "v", function() Move(1) end)
    down:SetPoint("TOPLEFT", orderX + 138, y)
    panel.orderRows[i] = { text = text, up = up, down = down }
  end
  -- Whether this order is used is Layout's "Sort by" (one switch, not two);
  -- this line says which it is now.
  panel.orderState = Note(page, "GameFontHighlight")
  panel.orderState:SetPoint("TOPLEFT", orderX, TOP - 270)
  panel.orderState:SetWidth(200)
  panel.orderState:SetJustifyH("LEFT")
  local orderNote = Note(page, "GameFontHighlightSmall")
  orderNote:SetPoint("TOPLEFT", orderX, TOP - 316)
  orderNote:SetWidth(200)
  orderNote:SetJustifyH("LEFT")
  orderNote:SetText("Top of the list is the top frame. Anyone you haven't set is placed by their class. "
    .. "Frames can only be re-ordered out of combat.")

end

---------------------------------------------------------------------------
-- Auras page: watch any spell, in any corner
---------------------------------------------------------------------------

local selectedWatch = 1

-- The icon a watched spell will show, for its swatch. A spell this character
-- doesn't know (another class's shield, a boss debuff) may have none to ask
-- for; a question mark stands in.
local function SpellIcon(name)
  for _, get in ipairs({ C_Spell and C_Spell.GetSpellTexture, GetSpellTexture }) do
    if get then
      local ok, texture = pcall(get, name)
      if ok and texture then
        return texture
      end
    end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function RefreshAuras()
  local page = panel.pages.auras
  local list = ns.db.auraWatch
  if selectedWatch > #list then
    selectedWatch = #list
  end

  for i, entry in ipairs(list) do
    local row = RowAt(panel.watchRows, page.content, i, function(self)
      selectedWatch = self.watchIndex
      ns.RefreshOptions()
    end)
    row.watchIndex = i
    row.icon:SetColorTexture(0, 0, 0, 0)
    local mark = i == selectedWatch and "|cff4dc2ff> |r" or "   "
    row.text:SetText(("%s%s |cff999999%s|r"):format(mark, entry.spell,
      ns.WATCH_CORNER_LABELS[entry.corner]))
  end
  HideFrom(panel.watchRows, #list + 1)
  page.content:SetHeight(math.max(1, #list * ROW_HEIGHT))

  local entry = list[selectedWatch]
  local shown = entry ~= nil
  for _, control in ipairs(page.entryControls) do
    control:SetShown(shown)
  end
  page.empty:SetShown(not shown)
  if entry then
    page.chosen:SetText(("Settings for |cff4dc2ff%s|r"):format(entry.spell))
    for corner, cell in pairs(page.places) do
      SetSelected(cell, corner == (entry.corner or 1))
    end
    if entry.dx or entry.dy then
      page.nudgeValue:SetText(("%+d,%+d"):format(entry.dx or 0, entry.dy or 0))
    else
      page.nudgeValue:SetText("")
    end
    local default = ns.db.auraSize or 13
    page.sizeValue:SetText(entry.size or default)
    page.sizeNote:SetText(entry.size and "its own size" or "the default")
    local c = entry.color or { 1, 1, 1 }
    for _, swatch in ipairs(page.swatches) do
      local style = swatch.style
      if style == "icon" then
        swatch.art:SetTexture(SpellIcon(entry.spell))
        swatch.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        swatch.art:SetVertexColor(1, 1, 1, 1)
      elseif style == "color" then
        swatch.art:SetColorTexture(c[1], c[2], c[3], 1)
      else
        swatch.art:SetTexture(ns.ShapeTexture(style))
        swatch.art:SetTexCoord(0, 1, 0, 1)
        swatch.art:SetVertexColor(c[1], c[2], c[3], 1)
      end
      SetSelected(swatch, style == (entry.style or "icon"))
    end
    page.lookLabel:SetText("Looks like: " .. (ns.WATCH_STYLE_LABELS[entry.style or "icon"] or "Spell icon"))
    page.colorFill:SetColorTexture(c[1], c[2], c[3], 1)
    page.timer:SetText(({ down = "Timer: down", up = "Timer: up", off = "Timer: off" })[entry.timer]
      or "Timer: default")
    page.who:SetText(ns.WATCH_WHO_LABELS[entry.mine] or "Anyone's")
  end
end

local LIBRARY_X = COLUMN_TWO + COLUMN_WIDTH + 18
local LIBRARY_W = 214
local libraryFilter = ""

-- The built-in list of Classic spells, grouped, with headings you can't click
-- and spells you can. Clicking one starts watching it.
local function RefreshLibrary()
  local page = panel.pages.auras
  local rows = ns.LibraryRows(libraryFilter)
  local watched = {}
  for _, entry in ipairs(ns.db.auraWatch) do
    watched[entry.spell] = true
  end

  for i, row in ipairs(rows) do
    local button = RowAt(panel.libraryRows, page.libraryContent, i, function(self)
      if self.spell and ns.AddWatch(self.spell) then
        selectedWatch = #ns.db.auraWatch
        ns.RefreshOptions()
      end
    end, LIBRARY_W)
    button.spell = row.spell
    button.icon:SetTexture(nil)
    if row.header then
      button.icon:SetColorTexture(0, 0, 0, 0)
      button.text:SetText(row.header)
      button.text:SetTextColor(unpack(THEME.accent))
    else
      button.icon:SetColorTexture(0.20, 0.20, 0.24, 1)
      local mark = watched[row.spell] and "|cff5a5a64 (watched)|r" or ""
      button.text:SetText(row.spell .. mark)
      button.text:SetTextColor(unpack(THEME.label))
    end
  end
  HideFrom(panel.libraryRows, #rows + 1)
  page.libraryContent:SetHeight(math.max(1, #rows * ROW_HEIGHT))
end

local function BuildAurasPage(page)
  Card(page, TOP - 16, LIST_HEIGHT + 46, nil, CONTENT_X - 6, COLUMN_WIDTH + 12)
  Card(page, TOP - 16, LIST_HEIGHT + 46, nil, COLUMN_TWO - 6, COLUMN_WIDTH + 12)
  Card(page, TOP - 16, LIST_HEIGHT + 46, nil, LIBRARY_X - 6, LIBRARY_W + 12)

  local libraryLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  libraryLabel:SetPoint("TOPLEFT", LIBRARY_X, TOP - 20)
  libraryLabel:SetTextColor(unpack(THEME.heading))
  libraryLabel:SetText("Classic spells - click to watch")

  local search = CreateFrame("EditBox", nil, page)
  search:SetSize(LIBRARY_W, 22)
  search:SetPoint("TOPLEFT", LIBRARY_X, TOP - 40)
  search:SetAutoFocus(false)
  search:SetMaxLetters(40)
  search:SetFontObject("GameFontHighlight")
  search:SetTextInsets(6, 6, 0, 0)
  local searchBg = search:CreateTexture(nil, "BACKGROUND")
  searchBg:SetAllPoints()
  searchBg:SetColorTexture(unpack(THEME.inset))
  Border(search)
  search:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
  end)
  search:SetScript("OnTextChanged", function(self)
    libraryFilter = self:GetText() or ""
    RefreshLibrary()
  end)
  page.librarySearch = search

  page.libraryScroll, page.libraryContent =
    MakeScrollList(page, LIBRARY_X, LIBRARY_W, LIST_HEIGHT - 24, TOP - 66)
  panel.libraryRows = {}
  local help = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  help:SetPoint("TOPLEFT", CONTENT_X, TOP)
  help:SetPoint("RIGHT", -16, 0)
  help:SetJustifyH("LEFT")
  help:SetTextColor(unpack(THEME.label))
  help:SetText("Watch any spell anywhere on the frame, as its icon or a symbol - someone else's shield, a boss debuff, your own buff.")

  local listLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  listLabel:SetPoint("TOPLEFT", CONTENT_X, TOP - 20)
  listLabel:SetTextColor(unpack(THEME.heading))
  listLabel:SetText("Watched (higher sits nearer its corner)")
  page.listLabel = listLabel

  page.scroll, page.content = MakeScrollList(page, CONTENT_X, COLUMN_WIDTH, LIST_HEIGHT - 22, TOP - 46)
  panel.watchRows = {}

  local box = CreateFrame("EditBox", nil, page)
  box:SetSize(COLUMN_WIDTH - 60, 22)
  box:SetPoint("TOPLEFT", COLUMN_TWO, TOP - 22)
  box:SetAutoFocus(false)
  box:SetMaxLetters(40)
  box:SetFontObject("GameFontHighlight")
  box:SetTextInsets(6, 6, 0, 0)
  local boxBg = box:CreateTexture(nil, "BACKGROUND")
  boxBg:SetAllPoints()
  boxBg:SetColorTexture(unpack(THEME.inset))
  box:SetScript("OnEscapePressed", box.ClearFocus)
  page.newSpell = box

  local function addTyped()
    if ns.AddWatch(box:GetText()) then
      box:SetText("")
      selectedWatch = #ns.db.auraWatch
      ns.RefreshOptions()
    else
      ns.Print("type a spell name that isn't already watched.")
    end
  end
  box:SetScript("OnEnterPressed", addTyped)

  local add = Button(page, 54, "Add", addTyped)
  add:SetPoint("LEFT", box, "RIGHT", 6, 0)

  page.starter = Button(page, COLUMN_WIDTH, "Add the starter set for my class", function()
    local n = ns.ApplyStarterWatch(true)
    ns.Print(n and ("added %d spells to the watch list."):format(n)
      or "those are all being watched already.")
    ns.RefreshOptions()
  end)
  page.starter:SetPoint("TOPLEFT", COLUMN_TWO, TOP - 326)

  page.chosen = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  page.chosen:SetPoint("TOPLEFT", COLUMN_TWO, TOP - 60)
  page.chosen:SetTextColor(unpack(THEME.heading))

  page.empty = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  page.empty:SetPoint("TOPLEFT", COLUMN_TWO, TOP - 60)
  page.empty:SetTextColor(unpack(THEME.note))
  page.empty:SetText("Type a spell name above to start watching it.")

  local x = COLUMN_TWO
  local controls = { page.chosen }
  local function Keep(control)
    controls[#controls + 1] = control
    return control
  end
  local function Label(y, text, dx)
    local label = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x + (dx or 0), y)
    label:SetTextColor(unpack(THEME.label))
    label:SetText(text)
    return Keep(label)
  end

  -- Where on the frame: a little map of it, five across and three down.
  -- Click a square to put the spell there; several in one square sit side by
  -- side. The numbers are ns.WATCH_CORNERS' places, laid out as they sit.
  Label(TOP - 80, "Where on the frame")
  local GRID = {
    { 1, 10, 5, 11, 2 },   -- along the top
    { 7, 12, 9, 13, 8 },   -- across the middle
    { 3, 14, 6, 15, 4 },   -- along the bottom
  }
  page.places = {}
  for row, corners in ipairs(GRID) do
    for column, corner in ipairs(corners) do
      local cell = Keep(Button(page, 24, "", function()
        ns.SetWatchField(selectedWatch, "corner", corner)
      end))
      cell:SetHeight(16)
      cell:SetPoint("TOPLEFT", x + (column - 1) * 27, TOP - 96 - (row - 1) * 19)
      cell.corner = corner
      page.places[corner] = cell
    end
  end

  -- And from there, a pixel at a time in any direction.
  Label(TOP - 160, "Nudge")
  local NUDGES = { { "<", -1, 0 }, { ">", 1, 0 }, { "^", 0, 1 }, { "v", 0, -1 } }
  for i, nudge in ipairs(NUDGES) do
    local arrow = Keep(Button(page, 22, nudge[1], function()
      ns.NudgeWatch(selectedWatch, nudge[2], nudge[3])
    end))
    arrow:SetHeight(18)
    arrow:SetPoint("TOPLEFT", x + 40 + (i - 1) * 25, TOP - 157)
  end
  page.nudgeValue = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  page.nudgeValue:SetPoint("TOPLEFT", x + 139, TOP - 160)
  page.nudgeValue:SetTextColor(unpack(THEME.note))
  Keep(page.nudgeValue)
  local centre = Keep(Button(page, 40, "Reset", function()
    ns.SetWatchField(selectedWatch, "dx", nil)
    ns.SetWatchField(selectedWatch, "dy", nil)
  end))
  centre:SetHeight(18)
  centre:SetPoint("TOPLEFT", x + 174, TOP - 157)

  -- Size: its own, or the role's default (set below the lists).
  Label(TOP - 80, "Size", 136)
  local smaller = Keep(Button(page, 22, "-", function() ns.StepWatchSize(selectedWatch, -1) end))
  smaller:SetPoint("TOPLEFT", x + 136, TOP - 96)
  page.sizeValue = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  page.sizeValue:SetPoint("TOP", page, "TOPLEFT", x + 173, TOP - 99)
  page.sizeValue:SetTextColor(unpack(ns.THEME.value))
  Keep(page.sizeValue)
  local bigger = Keep(Button(page, 22, "+", function() ns.StepWatchSize(selectedWatch, 1) end))
  bigger:SetPoint("TOPLEFT", x + 188, TOP - 96)
  page.sizeNote = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  page.sizeNote:SetPoint("TOPLEFT", x + 136, TOP - 122)
  page.sizeNote:SetTextColor(unpack(THEME.note))
  Keep(page.sizeNote)

  -- What it looks like: the spell's icon, a square, or a symbol, each drawn
  -- in this entry's colour so you see exactly what the frame will show.
  page.lookLabel = Label(TOP - 182, "")
  page.swatches = {}
  for i, style in ipairs(ns.WATCH_STYLES) do
    local swatch = Keep(Button(page, 15, "", function()
      ns.SetWatchField(selectedWatch, "style", style)
    end))
    swatch:SetHeight(15)
    swatch:SetPoint("TOPLEFT", x + (i - 1) * 16, TOP - 198)
    swatch.art = swatch:CreateTexture(nil, "ARTWORK")
    swatch.art:SetPoint("TOPLEFT", 2, -2)
    swatch.art:SetPoint("BOTTOMRIGHT", -2, 2)
    swatch.style = style
    swatch:SetScript("OnEnter", function(self)
      self.hovered = true
      self:Paint()
      page.lookLabel:SetText("Looks like: " .. ns.WATCH_STYLE_LABELS[style])
    end)
    swatch:SetScript("OnLeave", function(self)
      self.hovered = false
      self:Paint()
      ns.RefreshOptions()
    end)
    page.swatches[i] = swatch
  end

  -- Its colour (for the square and the symbols), and its timer.
  page.color = Keep(Button(page, 104, "Colour", function()
    local entry = ns.db.auraWatch[selectedWatch]
    if not entry then return end
    local c = entry.color or { 1, 1, 1 }
    local index = selectedWatch
    ns.OpenColorPicker(c[1], c[2], c[3], function(r, g, b)
      ns.SetWatchField(index, "color", { r, g, b })
    end)
  end))
  page.color:SetPoint("TOPLEFT", x, TOP - 220)
  page.colorFill = page.color:CreateTexture(nil, "ARTWORK")
  page.colorFill:SetSize(12, 12)
  page.colorFill:SetPoint("LEFT", 6, 0)

  page.timer = Keep(Button(page, 104, "", function()
    ns.CycleWatch(selectedWatch, "timer")
  end))
  page.timer:SetPoint("TOPLEFT", x + 110, TOP - 220)

  page.who = Keep(Button(page, COLUMN_WIDTH, "", function()
    ns.CycleWatch(selectedWatch, "mine")
  end))
  page.who:SetPoint("TOPLEFT", x, TOP - 246)

  local up = Keep(Button(page, 104, "Higher priority", function()
    selectedWatch = ns.MoveWatch(selectedWatch, -1)
    ns.RefreshOptions()
  end))
  up:SetPoint("TOPLEFT", x, TOP - 272)

  local down = Keep(Button(page, 104, "Lower", function()
    selectedWatch = ns.MoveWatch(selectedWatch, 1)
    ns.RefreshOptions()
  end))
  down:SetPoint("TOPLEFT", x + 110, TOP - 272)

  local remove = Keep(Button(page, COLUMN_WIDTH, "Stop watching this spell", function()
    ns.RemoveWatch(selectedWatch)
    ns.RefreshOptions()
  end))
  remove:SetPoint("TOPLEFT", x, TOP - 298)

  page.entryControls = controls

  -- For every indicator on this role's frames at once: the watched spells
  -- (unless one has its own size or timer) and your HoT row.
  local y0 = TOP - LIST_HEIGHT - 70
  Card(page, y0, 118, nil, CONTENT_X - 6, LIBRARY_X + LIBRARY_W - CONTENT_X + 12)
  Heading(page, y0, "Every indicator on these frames")
  ColumnStepper(page, CONTENT_X, y0 - 30, "Size", "auraSize", ns.AURA_SIZE_MIN, ns.AURA_SIZE_MAX, 1,
    function(v) return v .. " px" end)
  ColumnStepper(page, CONTENT_X + 262, y0 - 30, "Timer text size", "auraTimerSize", 6, 20, 1, Plain)
  ColumnCycler(page, CONTENT_X, y0 - 56, "Timer", "auraTimer", {
    { value = "down", label = "Counts down (time left)" },
    { value = "up", label = "Counts up (time since cast)" },
    { value = "off", label = "No timer" },
  })
  local places = {}
  for corner, label in ipairs(ns.WATCH_CORNER_LABELS) do
    places[corner] = { value = corner, label = label }
  end
  ColumnCycler(page, CONTENT_X + 262, y0 - 56, "Your HoT row sits at", "hotRowCorner", places)
end


---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

local function SelectPage(name)
  panel.selectedPage = name
  for _, category in ipairs(CATEGORIES) do
    local key = category.key
    panel.pages[key]:SetShown(key == name)
    SetSelected(panel.tabs[key], key == name)
    if panel.tabs[key].mark then panel.tabs[key].mark:SetShown(key == name) end
    if panel.settingsColumn and panel.settingsColumn[key] then
      SetSelected(panel.settingsColumn[key], key == name)
    end
  end
end

function ns.RefreshOptions()
  if panel and panel.TitleText then
    panel.TitleText:SetText(ns.RoleLook().title)
  end
  if not panel or not panel:IsShown() then
    return
  end
  RefreshSpells()
  RefreshBindings()
  RefreshAuras()
  RefreshLibrary()
  RefreshRoles()
  for _, control in pairs(panel.controls) do
    if type(control) == "table" and control.refresh then
      control.refresh()
    end
  end
  panel.controls.preview:SetText(ns.db.previewRaid and "Preview: raid" or "Preview: party")
  panel.harmfulToggle:SetText(showHarmful and "Hide harmful spells" or "Show harmful spells")
  if panel.rankToggle then
    panel.rankToggle:SetText(ns.db.showRanks and "Hide spell ranks" or "Show spell ranks")
  end
  if panel.rankTile then
    panel.rankTile:SetText(ns.db.showRanks and "Hide spell ranks" or "Show spell ranks")
  end
  if panel.harmfulTile then panel.harmfulTile:SetText(showHarmful and "Hide harmful spells" or "Show harmful spells") end

  panel.saveNote:SetText(ns.SaveSummary())
  panel.moveButton:SetText(ns.db.locked and "Move frames" or "Lock frames")
  if ns.GetMode() == "dps" then
    local helper = ns.BestUtilitySpell()
    panel.healButton:SetText(helper and ("Set up DPS clicks (%s)"):format(helper)
      or "Set up DPS clicks (dispels, kicks, assists)")
  elseif ns.GetMode() == "tank" then
    local taunt = ns.BestTauntSpell()
    panel.healButton:SetText(taunt and ("Set up tank clicks (taunt: %s)"):format(taunt)
      or "Set up tank clicks (engage)")
    if panel.aimButton then
      local aimed = ns.db.bindings[selectedClick]
      if aimed and aimed.kind == "spell" then
        panel.aimButton:SetText(aimed.their and "Lands on: THEIR TARGET (click to change)"
          or "Lands on: THE PLAYER (click to change)")
      else
        panel.aimButton:SetText("Pick a box with a spell to choose who it lands on")
      end
      panel.aimButton:Show()
    end
  else
    local heal = ns.BestHealSpell()
    panel.healButton:SetText(heal and ("Put %s on left click"):format(heal)
      or "No healing spell found for your class")
    if panel.aimButton then panel.aimButton:Hide() end
  end

  if InCombatLockdown() and ns.HasPending() then
    panel.status:SetText("|cffff9900In combat - changes apply when combat ends.|r")
  else
    panel.status:SetText("")
  end
end

-- Everything the window says about a role, in one place. Adding DPS meant
-- either a third "tank and ... or ..." at every one of these, or this.
local ROLE_LOOK = {
  healer = { title = "Healer", tagline = "Heal Smarter. Play Longer.",
             line = "Keep them standing. Read the room.",
             motto = "Life flows through everything.",
             slogan = "HEAL\nCLEANSE\nSUSTAIN",
             icon = "heal", accent = { 0.30, 0.85, 0.40 } },
  tank   = { title = "Tank", tagline = "Play Smarter. Tank Stronger.",
             line = "Hold the line. Control the fight.",
             slogan = "SURVIVE\nCONTROL\nPROTECT",
             icon = "tank", accent = { 1.00, 0.55, 0.15 } },
  dps    = { title = "DPS", tagline = "Adapt. Overcome. Dominate.",
             line = "Deal damage. Support your group.",
             motto = "MORE DAMAGE. A BRIGHTER TOMORROW.",
             slogan = "DAMAGE\nDISPEL\nCONTROL\nCONTRIBUTE",
             icon = "dps", accent = { 0.66, 0.42, 1.00 } },
}
ns.ROLE_LOOK = ROLE_LOOK

function ns.RoleLook(role)
  return ROLE_LOOK[role or ns.GetMode()] or ROLE_LOOK.healer
end

local function CreatePanel()
  -- Colour the whole window by role: healer green, tank orange, DPS red.
  -- THEME drives every accent, heading and highlight here, so tinting it
  -- before the widgets are built makes the whole section that colour.
  local roleAccent = ns.RoleLook().accent
  -- Which role this window is FOR, fixed when it is built.
  --
  -- Everything here used to read ns.db.bindings -- whatever role happened to
  -- be loaded. With three grids that is not the same thing: SetupLayout loads
  -- each role in turn and refreshes the options along the way, so an open
  -- Tank window could repaint itself from the DPS grid's settings and show
  -- every click as Empty. The bindings were on disk the whole time.
  panelRole = ns.GetMode()
  local skin = ROLE_SKINS[panelRole]
  local painted = skin ~= nil
  for k, v in pairs(BASE_THEME) do THEME[k] = { unpack(v) } end
  SetButtonColors(BASE_BUTTONS[1], BASE_BUTTONS[2], BASE_BUTTONS[3])
  if painted then
    for k, v in pairs(skin.theme) do THEME[k] = { unpack(v) } end
    SetButtonColors(skin.buttons[1], skin.buttons[2], skin.buttons[3])
  end
  THEME.accent = roleAccent
  THEME.heading = roleAccent
  THEME.value = roleAccent
  THEME.select = { roleAccent[1], roleAccent[2], roleAccent[3], 0.20 }

  -- A plain frame, not BasicFrameTemplate: that template is the stone-and-gold
  -- artwork this window exists to get away from.
  local tank = ns.GetMode() == "tank"
  -- A tank's spells are aimed at the mob, and the game calls those harmful, so
  -- the filter that keeps a healer's list clean was hiding exactly the spells a
  -- tank came here for: Growl, Demoralizing Roar, Taunt, Earth Shock. They had
  -- to be typed in by hand. The list opens with them shown in tank mode; the
  -- toggle still works, and healer mode still opens without them.
  showHarmful = tank
  panel = CreateFrame("Frame", "ForeverUIFramesOptions", UIParent)
  if painted then
    panel:SetSize(skin.size[1], skin.size[2])
  else
    panel:SetSize(tank and 1230 or 1040, tank and 800 or 640)
  end
  panel:SetPoint("CENTER")
  panel:SetFrameStrata("DIALOG")
  panel:SetMovable(true)
  panel:SetClampedToScreen(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  panel:SetScript("OnShow", ns.RefreshOptions)
  panel:HookScript("OnShow", function() ns.panelShownAt = GetTime and GetTime() or 0 end)
  -- The window has been seen closing itself the moment it opens. Whatever
  -- does it leaves a stack, and that stack is the whole diagnosis. Only a
  -- close within two seconds of opening counts -- Esc, the x and the slash
  -- toggle are just closes -- and the stacks stay in memory: they used to go
  -- into the profile, five at a time, and out with every profile export.
  panel:HookScript("OnHide", function()
    if ns.db then ns.db.panelHides = nil end
    if ns.expectHide then
      return
    end
    local now = GetTime and GetTime() or 0
    if not ns.panelShownAt or now - ns.panelShownAt > 2 then
      return
    end
    local stack = debugstack and debugstack(2) or "?"
    ns.lastPanelHide = { when = now, stack = stack }
    ns.panelHides = ns.panelHides or {}
    table.insert(ns.panelHides, 1, { stack = stack:sub(1, 1500) })
    ns.panelHides[6] = nil
    if ns.db and ns.db.debugHide then
      ns.Print("options window hidden by:")
      for line in stack:gmatch("[^\n]+") do
        ns.Print("  " .. line)
      end
    end
  end)
  panel:Hide()
  table.insert(UISpecialFrames, "ForeverUIFramesOptions") -- Esc closes it

  Fill(panel, THEME.bg)
  Border(panel)
  if painted then
    -- The painting, the whole window. 1536x1024 laid into the top 683 rows
    -- of a 1024 texture.
    local plate = panel:CreateTexture(nil, "BACKGROUND", nil, -7)
    plate:SetAllPoints()
    plate:SetTexture(SkinPath() .. skin.plate)
    plate:SetTexCoord(0, 1, 0, 683 / 1024)
    panel.plate = plate
    SetBorderColor(panel, { 0, 0, 0, 0 })
  end

  -- Title bar: a slightly lighter strip, an accent rule under it, the name on
  -- the left and a close button on the right.
  local bar = panel:CreateTexture(nil, "ARTWORK")
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", -1, -1)
  bar:SetHeight(HEADER_H)
  bar:SetColorTexture(unpack(painted and { 0, 0, 0, 0 } or THEME.card))

  -- The emblem, as on the big ForeverUI window.
  local logo = panel:CreateTexture(nil, "OVERLAY")
  logo:SetSize(52, 26)
  logo:SetPoint("LEFT", bar, "LEFT", 16, 0)
  logo:SetTexture(FUI.MEDIA_PATH and (FUI.MEDIA_PATH .. "foreverui-logo") or "Interface\\AddOns\\ForeverUI\\Media\\foreverui-logo")
  logo:SetVertexColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
  panel.logo = logo

  local barRule = panel:CreateTexture(nil, "OVERLAY")
  barRule:SetPoint("TOPLEFT", bar, "BOTTOMLEFT")
  barRule:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT")
  barRule:SetHeight(1)
  barRule:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], painted and 0 or 0.55)

  -- Back to the big ForeverUI menu: this window replaced it (ForeverUI hid it
  -- when you picked the role), so a way home that isn't just closing.
  local back = Button(panel, 70, "< Menu", function()
    ns.expectHide = true
    panel:Hide()
    ns.expectHide = nil
    if FUI.OpenOptions then
      FUI.OpenOptions()
    end
  end)
  back:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 8)
  back:SetHeight(22)
  panel.backButton = back

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, 2)
  -- Named for the role, not the old addon: "Healer" or "Tank".
  title:SetText(ns.RoleLook().title)
  title:SetFont(HEADING_FONT, painted and 32 or 20)
  title:SetTextColor(1, 1, 1)
  panel.TitleText = title

  local tagline = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  tagline:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  tagline:SetText(painted and ns.RoleLook().tagline:upper() or ns.RoleLook().tagline)
  if painted then tagline:SetFont(HEADING_FONT, 13) end
  tagline:SetTextColor(unpack(THEME.note))
  panel.tagline = tagline

  local version = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  version:SetPoint("LEFT", title, "RIGHT", 8, 0)
  -- "v" on purpose. ForeverUI hunts the whole interface for text that looks
  -- like map coordinates (two one-decimal numbers) and hides whatever frame it
  -- hangs off; "0.14.1" reads to it as "0.1 4.1", and it hid this window every
  -- fifth of a second. A letter in front is not a coordinate.
  version:SetText(ns.VersionLabel())
  panel.versionText = version
  version:SetTextColor(unpack(THEME.accent))
  if painted then
    version:SetFont(HEADING_FONT, 16)
    logo:SetSize(84, 42)
    -- The logo art turned to the role's colour; tinting the blue original
    -- only muddies it.
    logo:SetTexture(FUI.MEDIA_PATH and (FUI.MEDIA_PATH .. skin.logo) or logo:GetTexture())
    logo:SetVertexColor(1, 1, 1)
    logo:ClearAllPoints()
    logo:SetPoint("LEFT", bar, "LEFT", 22, -4)
  end

  panel.pages, panel.tabs, panel.controls = {}, {}, {}

  local close = Button(panel, 30, "X", function()
    ns.expectHide = true
    panel:Hide()
    ns.expectHide = nil
  end)
  close:SetPoint("RIGHT", bar, "RIGHT", -12, 0)
  close:SetHeight(30)

  -- The search box: type, and the sidebar keeps the pages that mention it.
  local search = CreateFrame("EditBox", nil, panel)
  search:SetSize(280, 30)
  search:SetPoint("RIGHT", close, "LEFT", -14, 0)
  if painted and skin.searchRight then
    -- Clear of the plate's painted words in the top-right corner.
    search:ClearAllPoints()
    search:SetPoint("RIGHT", panel, "TOPRIGHT", skin.searchRight, -(HEADER_H / 2 + 1))
  end
  search:SetAutoFocus(false)
  search:SetFontObject("GameFontHighlight")
  search:SetTextInsets(30, 8, 0, 0)
  Fill(search, THEME.inset)
  Border(search)
  search.glass = FUI.Skin.Icon(search, "search", 16, THEME.accent, "OVERLAY")
  search.glass:SetPoint("LEFT", 8, 0)
  search.hint = search:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  search.hint:SetPoint("LEFT", 30, 0)
  search.hint:SetText("Search settings...")
  search.hint:SetTextColor(unpack(THEME.note))
  search:SetScript("OnTextChanged", function(self)
    local q = (self:GetText() or ""):lower()
    self.hint:SetShown(q == "")
    for _, category in ipairs(CATEGORIES) do
      local tab = panel.tabs[category.key]
      if tab then tab:SetShown(q == "" or category.label:lower():find(q, 1, true) ~= nil) end
    end
    if panel.LayoutTabs then panel.LayoutTabs() end
  end)
  search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  panel.search = search

  -- The category list on the left, in its own darker well, each with a
  -- glyph: the game's icon drained of colour and tinted the role's colour.
  local well = CreateFrame("Frame", nil, panel)
  if painted then
    -- The painted stone panel in the plate's upper left.
    well:SetPoint("TOPLEFT", skin.well[1], skin.well[2])
    well:SetSize(skin.well[3], skin.well[4])
  else
    well:SetPoint("TOPLEFT", 1, -(HEADER_H + 1))
    well:SetPoint("BOTTOMLEFT", 1, FOOTER_H + 1)
    well:SetWidth(SIDEBAR)
  end
  Fill(well, painted and { 0, 0, 0, 0 } or THEME.card)
  local wellEdge = well:CreateTexture(nil, "BORDER")
  wellEdge:SetPoint("TOPRIGHT"); wellEdge:SetPoint("BOTTOMRIGHT"); wellEdge:SetWidth(1)
  wellEdge:SetColorTexture(THEME.rule[1], THEME.rule[2], THEME.rule[3], painted and 0 or 0.6)
  panel.sidebar = well

  local ICONS = {
    bindings = "clickcasting", general = "general", appearance = "appearance", layout = "layout",
    indicators = "unitframes", auras = "auras", roles = "roles",
  }
  panel.tabOrder = {}
  -- Each tab takes 40 pixels while they fit; with more pages than the
  -- painted well holds, they close up to fit it (never under 24).
  function panel.LayoutTabs()
    local shown = 0
    for _, tab in ipairs(panel.tabOrder) do
      if tab:IsShown() then shown = shown + 1 end
    end
    local room = (well.GetHeight and well:GetHeight() or 0) - 12
    local step = 40
    if shown > 0 and room > 0 then
      step = math.max(24, math.min(40, math.floor(room / shown)))
    end
    local ty = -8
    for _, tab in ipairs(panel.tabOrder) do
      if tab:IsShown() then
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", well, "TOPLEFT", 8, ty)
        tab:SetHeight(step - 4)
        ty = ty - step
      end
    end
    panel.tabStep = step
  end
  for _, category in ipairs(CATEGORIES) do
    local key = category.key
    local page = CreateFrame("Frame", nil, panel)
    if painted then
      page:SetPoint("TOPLEFT", skin.page[1], skin.page[2])
      page:SetPoint("BOTTOMRIGHT", skin.page[3], FOOTER_H + 4)
    else
      page:SetPoint("TOPLEFT", SIDEBAR + 12, -(HEADER_H + 8 + (tank and 80 or 0)))
      page:SetPoint("BOTTOMRIGHT", -(12 + (tank and 198 or 0)), FOOTER_H + 4)
    end
    page.controls = panel.controls -- one shared table; every page adds to it
    panel.pages[key] = page

    local button = Button(panel, painted and skin.tabW or SIDEBAR - 16, category.label, function() SelectPage(key) end)
    button:SetHeight(36)
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", 40, 0)
    button.label:SetPoint("RIGHT", -6, 0)
    button.label:SetJustifyH("LEFT")
    local icon = FUI.Skin.Icon(button, ICONS[key] or ns.FRAME_PAGE_ICONS[key] or "general", 20, THEME.accent)
    icon:SetPoint("LEFT", 10, 0)
    button.icon = icon
    local mark = button:CreateTexture(nil, "OVERLAY")
    mark:SetPoint("TOPLEFT"); mark:SetPoint("BOTTOMLEFT"); mark:SetWidth(3)
    mark:SetColorTexture(unpack(THEME.accent))
    mark:Hide()
    button.mark = mark
    panel.tabs[key] = button
    panel.tabOrder[#panel.tabOrder + 1] = button
  end
  panel.LayoutTabs()

  if painted then
    -- The crest, "Healer" and its line, on the dark left end of the painted
    -- banner (the owner's mock-up).
    local block = CreateFrame("Frame", nil, panel)
    block:SetPoint("TOPLEFT", skin.block[1], skin.block[2])
    block:SetSize(560, 110)
    local leaf = block:CreateTexture(nil, "ARTWORK")
    leaf:SetSize(96, 96)
    leaf:SetPoint("LEFT", 0, 0)
    leaf:SetTexture(SkinPath() .. skin.crest)
    local big = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    big:SetPoint("TOPLEFT", leaf, "TOPRIGHT", 10, -16)
    big:SetFont(HEADING_FONT, 34)
    big:SetText(ns.RoleLook().title)
    big:SetTextColor(1, 1, 1)
    big:SetShadowColor(0, 0, 0, 1); big:SetShadowOffset(2, -2)
    local line = block:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    line:SetPoint("TOPLEFT", big, "BOTTOMLEFT", 0, -6)
    line:SetFont(HEADING_FONT, 17)
    line:SetText(ns.RoleLook().motto or ns.RoleLook().line)
    line:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
    line:SetShadowColor(0, 0, 0, 1); line:SetShadowOffset(1, -1)
    panel.titleBlock = block
  end

  if tank and not painted then
    -- The title block over the page: the shield, "Tank", the tagline, and
    -- the slogan on the right -- the owner's mock-up.
    local block = CreateFrame("Frame", nil, panel)
    block:SetPoint("TOPLEFT", SIDEBAR + 12, -(HEADER_H + 8))
    block:SetPoint("TOPRIGHT", -12, -(HEADER_H + 8))
    block:SetHeight(72)
    Fill(block, { 0.06, 0.04, 0.02, 1 })
    Border(block)
    local shield = FUI.Skin.Icon(block, ns.RoleLook().icon, 44, THEME.accent)
    shield:SetPoint("LEFT", 16, 0)
    local big = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    big:SetPoint("TOPLEFT", shield, "TOPRIGHT", 14, 0)
    big:SetFont(HEADING_FONT, 24)
    big:SetText(ns.RoleLook().title)
    big:SetTextColor(1, 1, 1)
    local line = block:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    line:SetPoint("TOPLEFT", big, "BOTTOMLEFT", 0, -4)
    line:SetText(ns.RoleLook().line)
    line:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
    local slogan = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    slogan:SetPoint("RIGHT", -24, 0)
    slogan:SetFont(HEADING_FONT, 14)
    slogan:SetJustifyH("RIGHT")
    slogan:SetText(ns.RoleLook().slogan)
    slogan:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
    panel.titleBlock = block

    -- The settings column on the right: the same pages as the sidebar, one
    -- click away from any page, and a word from the addon under them.
    local column = CreateFrame("Frame", nil, panel)
    column:SetPoint("TOPRIGHT", -12, -(HEADER_H + 8 + 80))
    column:SetPoint("BOTTOMRIGHT", -12, FOOTER_H + 4)
    column:SetWidth(186)
    Fill(column, THEME.card)
    Border(column)
    local colHead = column:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colHead:SetPoint("TOPLEFT", 40, -14)
    colHead:SetFont(HEADING_FONT, 15)
    colHead:SetText("Tank Settings")
    colHead:SetTextColor(1, 1, 1)
    local colGear = FUI.Skin.Icon(column, "general", 20, THEME.accent)
    colGear:SetPoint("RIGHT", colHead, "LEFT", -8, 0)
    local colRule = column:CreateTexture(nil, "BORDER")
    colRule:SetPoint("TOPLEFT", 1, -44); colRule:SetPoint("TOPRIGHT", -1, -44); colRule:SetHeight(1)
    colRule:SetColorTexture(THEME.rule[1], THEME.rule[2], THEME.rule[3], 0.6)
    panel.settingsColumn = { }
    for i, category in ipairs(CATEGORIES) do
      local b = Button(column, 186 - 20, category.label, function() SelectPage(category.key) end)
      b:SetHeight(36)
      b:SetPoint("TOPLEFT", 10, -54 - (i - 1) * 42)
      b.label:ClearAllPoints()
      b.label:SetPoint("LEFT", 38, 0)
      b.label:SetPoint("RIGHT", -6, 0)
      b.label:SetJustifyH("LEFT")
      local ic = FUI.Skin.Icon(b, ICONS[category.key] or "general", 18, THEME.accent)
      ic:SetPoint("LEFT", 10, 0)
      panel.settingsColumn[category.key] = b
    end
    local quote = CreateFrame("Frame", nil, column)
    quote:SetPoint("BOTTOMLEFT", 10, 10)
    quote:SetPoint("BOTTOMRIGHT", -10, 10)
    quote:SetHeight(110)
    Fill(quote, THEME.inset)
    Border(quote)
    local qText = quote:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    qText:SetPoint("TOPLEFT", 12, -12)
    qText:SetPoint("RIGHT", -12, 0)
    qText:SetJustifyH("LEFT")
    qText:SetText("\"A smooth tanking UI lets you focus on what matters -- the fight.\"")
    qText:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
    local qWho = quote:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    qWho:SetPoint("BOTTOMLEFT", 12, 12)
    qWho:SetText("-- ForeverUI")
    qWho:SetTextColor(unpack(THEME.note))
    panel.quote = quote
  end

  -- The emblem again at the foot of the column, with the role and version.
  local foot = panel:CreateTexture(nil, "OVERLAY")
  foot:SetSize(56, 28)
  foot:SetPoint("BOTTOMLEFT", well, "BOTTOMLEFT", 14, 36)
  foot:SetShown(not painted)
  foot:SetTexture(logo:GetTexture())
  foot:SetVertexColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
  local footText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  footText:SetPoint("BOTTOMLEFT", foot, "BOTTOMRIGHT", 10, 4)
  footText:SetJustifyH("LEFT")
  footText:SetShown(not painted)
  footText:SetText(("|cffffffff%s|r\n%s\nOne UI. Total Control."):format(
    ns.RoleLook().title, ns.VersionLabel()))
  footText:SetTextColor(unpack(THEME.note))

  BuildBindingsPage(panel.pages.bindings)
  BuildGeneralPage(panel.pages.general)
  BuildAppearancePage(panel.pages.appearance)
  BuildLayoutPage(panel.pages.layout)
  BuildIndicatorsPage(panel.pages.indicators)
  BuildAurasPage(panel.pages.auras)
  BuildRolesPage(panel.pages.roles)
  for _, category in ipairs(CATEGORIES) do
    local build = ns.FRAME_PAGE_BUILDERS[category.key]
    if build and panel.pages[category.key] then
      build(panel.pages[category.key])
    end
  end

  -- Footer: a row of wide action tiles over a status row with the save
  -- buttons -- the mock-up's two-tier foot.
  local footerRule = panel:CreateTexture(nil, "ARTWORK")
  footerRule:SetPoint("BOTTOMLEFT", 1, FOOTER_H)
  footerRule:SetPoint("BOTTOMRIGHT", -1, FOOTER_H)
  footerRule:SetHeight(1)
  footerRule:SetColorTexture(THEME.rule[1], THEME.rule[2], THEME.rule[3], painted and 0 or 0.6)
  local statusRule = panel:CreateTexture(nil, "ARTWORK")
  statusRule:SetPoint("BOTTOMLEFT", 1, 42)
  statusRule:SetPoint("BOTTOMRIGHT", -1, 42)
  statusRule:SetHeight(1)
  statusRule:SetColorTexture(THEME.rule[1], THEME.rule[2], THEME.rule[3], 0.6)
  local statusFill = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
  statusFill:SetPoint("BOTTOMLEFT", 1, 1)
  statusFill:SetPoint("BOTTOMRIGHT", -1, 1)
  statusFill:SetHeight(41)
  statusFill:SetColorTexture(unpack(painted and skin.status or THEME.card))
  if painted and skin.motto then
    local m = skin.motto
    local motto = panel:CreateTexture(nil, "ARTWORK")
    motto:SetSize(m[2], m[3])
    motto:SetPoint("BOTTOM", panel, "BOTTOM", -20, 3)
    motto:SetTexture(SkinPath() .. m[1])
    motto:SetTexCoord(0, m[4], 0, m[5])
    panel.motto = motto
  end

  panel.saveButton = Button(panel, 130, "Save now", function()
    ns.Note("clicked Save now")
    ns.SaveNow()
    ns.Print(("frame settings saved in ForeverUI profile \"%s\" for %s."):format(
      ns.ActiveProfileName(), ns.CharacterKey()))
    ns.RefreshOptions()
  end)
  panel.saveButton:SetPoint("BOTTOMRIGHT", -12, 8)
  panel.saveButton:SetHeight(28)
  panel.saveButton.fill:SetColorTexture(unpack(painted and skin.save or { 0.16, 0.50, 0.85, 1 }))

  panel.reloadButton = Button(panel, 128, "Save and reload UI", function()
    ns.Note("clicked Save and reload UI (addon calls ReloadUI)")
    -- Only the positions, which are plain reads and writes. Not SaveNow():
    -- it ends by re-applying every setting, which rebuilds the grids, and
    -- this client refuses a reload asked for in the same click as that
    -- (ADDON_ACTION_BLOCKED Reload(), caught in the setup wizard). Settings
    -- are saved as you go; the reload is what writes them to disk.
    ns.CapturePosition()
    ns.CaptureTargetPosition()
    ns.CaptureFocusPosition()
    -- The Forever beta forgets saved settings over a reload; write the macro
    -- backup now (ForeverUI only -- Core/MacroBackup.lua) so nothing just
    -- changed is lost. Macro text only: no frames change, so the reload in
    -- this same click is still allowed.
    local backup = FUI.MacroBackup
    if backup then pcall(backup.Write) end
    if ReloadUI then
      ReloadUI()
    end
  end)
  panel.reloadButton:SetPoint("RIGHT", panel.saveButton, "LEFT", -8, 0)
  panel.reloadButton:SetHeight(28)
  panel.reloadButton:SetWidth(150)

  -- Moving the frames is the thing people come looking for, so it lives in
  -- the footer where every page can reach it rather than on one page.
  local function MoveFrames()
    if InCombatLockdown() then
      ns.Print("can't move frames in combat.")
      return
    end
    ns.SetLockedEverywhere(not ns.db.locked)
    if ns.db.locked then
      ns.Print("frames locked.")
      ns.RefreshOptions()
    else
      ns.Print("drag the blue box to move the frames; right-click it to reset. Click Move frames again when you're done.")
      panel:Hide() -- out of the way, so the box can be dragged
    end
  end
  -- The three tiles across the foot: Reset every binding, Show harmful
  -- spells, Move frames -- the same width, each with a glyph.
  -- (Their order is panel.tiles below.)
  local function Tile(label, icon, onClick)
    local tile = Button(panel, 1, label, onClick)
    tile:SetHeight(38)
    local glyph = FUI.Skin.Icon(tile, icon, 18, THEME.accent)
    glyph:SetPoint("RIGHT", tile.label, "LEFT", -10, 0)
    tile.label:ClearAllPoints()
    tile.label:SetPoint("CENTER", 12, 0)
    tile.glyph = glyph
    return tile
  end
  panel.moveButton = Tile("Move frames", "framemgmt", MoveFrames)
  panel.resetTile = Tile("Reset every binding", "reset", function()
    if panel.controls.resetBindings then panel.controls.resetBindings:Click() end
  end)
  panel.harmfulTile = Tile("Show harmful spells", "eye", function()
    if panel.controls.showHarmful then panel.controls.showHarmful:Click() end
  end)
  -- Downranking is a healer's tool, so it sits with the other rarely-pressed
  -- switches rather than cluttering the spell list itself.
  panel.rankTile = Tile("Show spell ranks", "spells", function()
    if panel.controls.showRanks then panel.controls.showRanks:Click() end
  end)
  panel.tiles = { panel.resetTile, panel.harmfulTile, panel.rankTile, panel.moveButton }

  -- The footer splits evenly between however many tiles there are.
  local GAP = 10
  local function LayOutTiles(self, width)
    local count = #self.tiles
    local w = (width - 24 - (count - 1) * GAP) / count
    for i, tile in ipairs(self.tiles) do
      tile:SetWidth(w)
      tile:ClearAllPoints()
      tile:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 12 + (i - 1) * (w + GAP), 48)
    end
  end
  panel.LayOutTiles = LayOutTiles
  panel:HookScript("OnSizeChanged", LayOutTiles)
  LayOutTiles(panel, 1040)

  panel.saveNote = Note(panel, "GameFontHighlightSmall")
  panel.saveNote:SetPoint("LEFT", back, "RIGHT", 12, 0)
  panel.saveNote:SetPoint("RIGHT", panel.reloadButton, "LEFT", -10, 0)
  panel.saveNote:SetJustifyH("LEFT")

  panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.status:SetPoint("BOTTOMLEFT", back, "TOPLEFT", 0, 46)
  panel.status:Hide()
  panel.status:SetJustifyH("LEFT")
  panel.status:SetTextColor(unpack(THEME.label))

  SelectPage("bindings")
  ns.optionsPanel = panel
end

-- page: a category key. Asking for the page that's already open closes the window.
-- The bindings and indicators pages are laid out for the current role, so a
-- role switch tears the panel down; it rebuilds for the new role next open.
function ns.RebuildOptions()
  if panel then
    local wasShown = panel:IsShown()
    panel:Hide()
    panel:SetParent(nil)
    panel = nil
    if wasShown then
      ns.ToggleOptions("bindings")
    end
  end
end

function ns.ToggleOptions(page)
  if not panel then
    CreatePanel()
  end
  page = page or "bindings"
  if not panel.pages[page] then
    page = "bindings"
  end
  if panel:IsShown() and panel.selectedPage == page then
    panel:Hide()
    return
  end
  SelectPage(page)
  panel:Show()
  ns.Note("options opened: " .. tostring(page))
  ns.RefreshOptions()
end

-- Learning a spell or changing talents while the window is open.
local watcher = CreateFrame("Frame")
ns.RegisterEvent(watcher, "SPELLS_CHANGED")
watcher:SetScript("OnEvent", function()
  ns.RefreshOptions()
end)
