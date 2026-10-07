local _, ns = ...

-- One options window for the whole UI. Categories down the left; each page is
-- built from a declarative schema so modules describe their settings instead
-- of drawing widgets:
--
--   module.options = {
--     { type = "checkbox", key = "showPets", label = "Show pets" },
--     { type = "stepper",  key = "width", label = "Width", min = 80, max = 220, step = 10 },
--     { type = "cycler",   key = "sort", label = "Sort by", choices = {...} },
--   }
--
-- Every widget is a plain frame dressed by Core/Skin.lua. Blizzard's option
-- templates are deliberately unused: they carry the stone-and-gold artwork
-- this UI exists to replace, and they differ between game versions.

-- The window, to the owner's mock-up: a tall header with the emblem, the
-- title and a tagline, a search box on the right; an icon sidebar with the
-- chosen page lit; the page as a big title, a subtitle, and cards -- one
-- per section -- each row carrying a description under its label; and a
-- footer with a help line, Apply and Close.
local WIDTH   = 960
local HEIGHT  = 690
local HEADER  = 56          -- title strip
local SIDEBAR = 190         -- category column
local FOOTER  = 52
-- The painted plate has its own wells: the castle scene fills the top, the
-- page sits in the plank board under it, the candle and the quill sit in the
-- bottom corners. The page is laid into that board so the art frames it.
local CONTENT_TOP = 150     -- the page starts under the castle scene
local SPAN_TRIM   = 78      -- the board stops short of the lanterns on the right
local SPAN = WIDTH - SIDEBAR - SPAN_TRIM   -- the width the pages get
local PAD     = 16          -- page inset, and the gutter on the right
local CARD    = 14          -- inset inside a card
local ROW     = 30
local TOP     = -12


-- The painted skin (owner's mock-up, art from ChatGPT in Media/skin): the
-- window is a painted plate, the cards are parchment, and anything written
-- ON parchment is dark ink rather than the light text used on the wood.
local SKIN = ns.MEDIA_PATH .. "skin\\"
local INK       = { 0.20, 0.12, 0.05 }
local INK_DIM   = { 0.38, 0.28, 0.17 }
local INK_EDGE  = { 0.30, 0.20, 0.10, 1 }
local INK_ICON  = { 0.38, 0.22, 0.72 }
local PURPLE    = { 0.56, 0.36, 1.00 }
local GOLD      = { 0.95, 0.78, 0.42 }
local LILAC     = { 0.80, 0.66, 1.00 }
-- Lilac is for the dark wood; on parchment it was hard to read (goldfish117
-- on CurseForge, 30 Sept 2026: "The purple text for the Action Bar options
-- is really hard to read"). Values written on a card use this deep ink.
local INK_PURPLE = { 0.33, 0.13, 0.60 }

-- The painted window is set in Friz Quadrata, the game's own serif, at the
-- role's size -- whatever font the rest of the UI has been given.
local SERIF = "Fonts\\FRIZQT__.TTF"
local function OptionFont(fs, role)
  if not fs then return end
  local _, size, outline = ns.Media.Role(role or "general")
  fs:SetFont(SERIF, size or 12, outline or "")
end

-- Is this region drawn on parchment? A card marks itself; its rows are its
-- children, or its children's children.
local function OnParchment(parent)
  local f = parent
  for _ = 1, 4 do
    if not f then return false end
    if f.isParchment then return true end
    f = f.GetParent and f:GetParent() or nil
  end
  return false
end
ns.OnParchment = OnParchment

local panel
local pages = {}
ns.optionsPages = pages -- so tests (and other modules) can reach a page's rows

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------

-- Buttons in the painted window: dark wood with a gold edge on the plate,
-- tan with a brown edge on parchment. The lit one is purple on both.
local LIT = { bg = { 0.26, 0.10, 0.52, 0.97 }, border = { 0.70, 0.48, 1.00, 1 }, text = { 1, 1, 1 } }
local BRASS = { 0.66, 0.50, 0.26, 1 }
local WOOD_BUTTON = {
  idle  = { bg = { 0.08, 0.08, 0.10, 0.92 }, border = { 0.30, 0.27, 0.24, 1 }, text = { 0.94, 0.92, 0.88 } },
  hover = { bg = { 0.14, 0.12, 0.16, 0.95 }, border = { 0.62, 0.48, 0.90, 1 }, text = { 1, 1, 1 } },
  active = LIT,
}
local TAN_BUTTON = {
  idle  = { bg = { 0.07, 0.06, 0.08, 0.94 }, border = BRASS, text = { 0.95, 0.91, 0.84 } },
  hover = { bg = { 0.13, 0.10, 0.16, 0.96 }, border = { 0.92, 0.74, 0.38, 1 }, text = { 1, 1, 1 } },
  active = LIT,
}
ns.OptionPalettes = { wood = WOOD_BUTTON, tan = TAN_BUTTON }

-- A text field or read-out box, matched to what it sits on.
local function FieldColors(parent)
  if OnParchment(parent) then
    return { color = { 0.07, 0.06, 0.08, 0.94 }, borderColor = BRASS }, { 0.95, 0.91, 0.84 }
  end
  return { color = { 0.05, 0.04, 0.06, 0.55 }, borderColor = { 0.66, 0.50, 0.26, 0.9 } }, { 0.95, 0.91, 0.84 }
end

local function Button(parent, width, text, onClick)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(width, 22)
  button.palette = OnParchment(parent) and TAN_BUTTON or WOOD_BUTTON
  ns.Skin.Button(button)
  OptionFont(button.text)
  button:SetText(text)
  button:SetScript("OnClick", onClick)
  return button
end
ns.OptionButton = Button

local function Label(parent, x, y, text, role)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  OptionFont(fs, role or "general")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetText(text)
  if OnParchment(parent) then
    fs:SetTextColor(unpack(INK))
    fs:SetShadowColor(0, 0, 0, 0)
  else
    fs:SetTextColor(unpack(ns.Colors.ui.text))
  end
  return fs
end

-- A bigger font than any role carries: the page title, the window title.
local function BigFont(fs, size)
  local _, _, outline = ns.Media.Role("header")
  fs:SetFont(SERIF, size, outline or "")
end

-- The dim line under a row's label ("Adjust the overall size of the UI.").
-- Rows with one take an extra 14px.
local function Description(parent, x, y, text)
  if not text then
    return nil
  end
  local fs = Label(parent, x, y, text)
  fs:SetTextColor(unpack(OnParchment(parent) and INK_DIM or ns.Colors.ui.textDim))
  return fs
end

local function RowHeight(entry)
  return ROW + (entry.desc and 14 or 0)
end

-- Where a row's value lives: a module's own settings, a core setting on
-- ns.db, or wherever the entry's `store` function points (e.g. db.media).
local function Store(entry)
  if entry.store then
    return entry.store()
  elseif entry.scope == "core" then
    return ns.db
  end
  return ns.db.modules[entry.moduleName]
end

local function Changed(entry)
  if ns.TouchProfile then ns.TouchProfile() end   -- for "Last modified" on the Profiles page
  local module = entry.moduleName and ns.GetModule(entry.moduleName)
  if module and module.Refresh then
    module:Refresh()
  end
  if entry.reload then
    ns.RequestReload(entry.label)
  end
  if entry.apply then
    entry.apply()
  end
  ns.RefreshOptions()
end

-- A slider: a track, an accent fill up to the thumb, the thumb, and the
-- value in a box at the end. Dragging the thumb (or clicking the track)
-- sets the value in steps.
local function MakeSlider(parent, width, entry)
  local slider = CreateFrame("Frame", nil, parent)
  slider:SetSize(width, 20)
  slider:EnableMouse(true)
  local track = slider:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT", 0, 0); track:SetPoint("RIGHT", 0, 0); track:SetHeight(6)
  track:SetColorTexture(0.32, 0.21, 0.10, 0.9)
  local fill = slider:CreateTexture(nil, "BORDER")
  fill:SetPoint("LEFT", 0, 0); fill:SetHeight(6); fill:SetWidth(1)
  fill:SetColorTexture(PURPLE[1], PURPLE[2], PURPLE[3], 1)
  local thumb = CreateFrame("Frame", nil, slider)
  thumb:SetSize(16, 16)
  ns.Skin.Panel(thumb, { color = { 0.30, 0.15, 0.58, 1 }, borderColor = { 0.95, 0.80, 0.45, 1 } })
  thumb:SetPoint("CENTER", slider, "LEFT", 0, 0)
  slider.track, slider.fill, slider.thumb = track, fill, thumb

  local function Fraction()
    local v = Store(entry)[entry.key] or entry.min
    return math.max(0, math.min(1, (v - entry.min) / (entry.max - entry.min)))
  end
  function slider:Paint()
    local w = self:GetWidth() or width
    local f = Fraction()
    fill:SetWidth(math.max(1, f * w))
    thumb:ClearAllPoints()
    thumb:SetPoint("CENTER", self, "LEFT", f * w, 0)
  end
  local function SetFromX(x)
    local left = slider:GetLeft()
    local w = slider:GetWidth()
    if not left or not w or w <= 0 then return end
    local scale = slider:GetEffectiveScale() or 1
    local f = math.max(0, math.min(1, (x / scale - left) / w))
    local v = entry.min + f * (entry.max - entry.min)
    v = math.floor(v / entry.step + 0.5) * entry.step
    Store(entry)[entry.key] = math.max(entry.min, math.min(entry.max, v))
    Changed(entry)
  end
  function slider:SetFromCursor()
    if GetCursorPosition then
      local x = GetCursorPosition()
      SetFromX(x)
    end
  end
  slider:SetScript("OnMouseDown", function(self)
    self.dragging = true
    self:SetFromCursor()
  end)
  slider:SetScript("OnMouseUp", function(self) self.dragging = nil end)
  slider:SetScript("OnUpdate", function(self)
    if self.dragging then
      if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        self.dragging = nil
      else
        self:SetFromCursor()
      end
    end
  end)
  slider.SetValueFromX = SetFromX
  return slider
end

-- A dropdown: the current choice with an arrow; clicking opens a list of
-- the choices under it, in the same clothes.
local dropdownList
local function OpenDropdown(button, entry)
  if not dropdownList then
    dropdownList = CreateFrame("Frame", "ForeverUIDropdownList", UIParent)
    dropdownList:SetFrameStrata("TOOLTIP")
    ns.Skin.Panel(dropdownList, { color = { 0.10, 0.06, 0.03, 0.97 }, borderColor = { 0.90, 0.70, 0.34, 1 } })
    dropdownList.items = {}
    dropdownList:Hide()
  end
  if dropdownList:IsShown() and dropdownList.owner == button then
    dropdownList:Hide()
    return
  end
  local choices = entry.choices() or {}
  local width = button:GetWidth() or 200
  for i, choice in ipairs(choices) do
    local item = dropdownList.items[i]
    if not item then
      item = CreateFrame("Button", nil, dropdownList)
      item:SetHeight(24)
      item.palette = WOOD_BUTTON
      ns.Skin.Button(item, { justify = "LEFT" })
      OptionFont(item.text)
      dropdownList.items[i] = item
    end
    item:SetWidth(width - 4)
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", 2, -(2 + (i - 1) * 25))
    item:SetText(choice.label)
    ns.Skin.SetSelected(item, choice.value == Store(entry)[entry.key])
    item:SetScript("OnClick", function()
      Store(entry)[entry.key] = choice.value
      dropdownList:Hide()
      Changed(entry)
    end)
    item:Show()
  end
  for i = #choices + 1, #dropdownList.items do
    dropdownList.items[i]:Hide()
  end
  dropdownList:SetSize(width, #choices * 25 + 4)
  dropdownList:ClearAllPoints()
  dropdownList:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
  dropdownList.owner = button
  dropdownList:Show()
end
ns.OpenDropdown = OpenDropdown

-- A colour swatch: the colour in a bordered box, clicked to open the
-- game's own colour picker. The value is stored as { r, g, b }.
local function MakeColor(page, entry, y, x, right)
  x, right = x or PAD, right or PAD
  Label(page, x, y - 4, entry.label)
  Description(page, x, y - 20, entry.desc)
  local swatch = CreateFrame("Button", nil, page)
  swatch:SetSize(54, 20)
  swatch:SetPoint("TOPRIGHT", page, "TOPRIGHT", -right, y - 1)
  ns.Skin.Panel(swatch, { color = { 0, 0, 0, 1 } })
  local fill = swatch:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("TOPLEFT", 2, -2)
  fill:SetPoint("BOTTOMRIGHT", -2, 2)
  swatch.fill = fill

  local function Current()
    local c = Store(entry)[entry.key] or { 1, 1, 1 }
    return c[1] or 1, c[2] or 1, c[3] or 1
  end
  local function Apply(r, g, b)
    Store(entry)[entry.key] = { r, g, b }
    fill:SetColorTexture(r, g, b, 1)
    Changed(entry)
  end
  swatch.SetColor = Apply
  swatch:SetScript("OnClick", function()
    local r, g, b = Current()
    local picker = _G.ColorPickerFrame
    if not picker then
      ns.Print("this client has no colour picker.")
      return
    end
    local info = {
      r = r, g = g, b = b, hasOpacity = false,
      swatchFunc = function()
        local nr, ng, nb = picker:GetColorRGB()
        if nr then Apply(nr, ng, nb) end
      end,
      cancelFunc = function() Apply(r, g, b) end,
    }
    -- Newer clients take the whole description; older ones want the fields
    -- set on the frame and the panel shown by hand.
    if picker.SetupColorPickerAndShow then
      pcall(picker.SetupColorPickerAndShow, picker, info)
    else
      picker.func, picker.cancelFunc, picker.hasOpacity = info.swatchFunc, info.cancelFunc, false
      picker.previousValues = { r = r, g = g, b = b }
      if picker.SetColorRGB then pcall(picker.SetColorRGB, picker, r, g, b) end
      -- Shown directly rather than through ShowUIPanel. The panel manager
      -- is Blizzard's, and calling into it from our click taints it for the
      -- rest of the session -- after which opening the character sheet
      -- throws, because its status bar text compares a secret value and is
      -- only allowed to while untainted. The colour picker does not need
      -- the panel manager to appear.
      picker:Show()
    end
  end)
  entry.widget = swatch
  entry.refresh = function()
    fill:SetColorTexture(Current())
  end
end

-- The text box on its own, with no label and no anchor: the caller sizes
-- and places it. Stored as a plain string; Enter or losing focus commits it.
local function MakeInputBox(page, entry)
  local box = CreateFrame("EditBox", nil, page)
  box:SetSize(entry.width or 240, 22)
  box:SetAutoFocus(false)
  OptionFont(box, "general")
  box:SetTextInsets(6, 6, 0, 0)
  local fieldLook, fieldInk = FieldColors(page)
  ns.Skin.Panel(box, fieldLook)
  box:SetTextColor(unpack(fieldInk))
  box.hint = box:CreateFontString(nil, "OVERLAY")
  OptionFont(box.hint, "general")
  box.hint:SetPoint("LEFT", 6, 0)
  box.hint:SetText(entry.hint or "")
  box.hint:SetTextColor(unpack(ns.Colors.ui.textDim))
  local function Commit(self)
    Store(entry)[entry.key] = self:GetText() or ""
    self.hint:SetShown((self:GetText() or "") == "")
    self:ClearFocus()
    Changed(entry)
  end
  box:SetScript("OnEnterPressed", Commit)
  box:SetScript("OnEditFocusLost", Commit)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnTextChanged", function(self)
    self.hint:SetShown((self:GetText() or "") == "")
  end)
  entry.widget = box
  entry.refresh = function()
    if box:HasFocus() then return end
    local value = Store(entry)[entry.key] or ""
    box:SetText(value)
    box.hint:SetShown(value == "")
  end
  return box
end

-- A full-width row: the label on the left, the box against the right edge.
local function MakeInput(page, entry, y, x, right)
  x, right = x or PAD, right or PAD
  Label(page, x, y - 4, entry.label)
  Description(page, x, y - 20, entry.desc)
  local box = MakeInputBox(page, entry)
  box:SetPoint("TOPRIGHT", page, "TOPRIGHT", -right, y - 1)
  return box
end

-- A block a module draws itself (the nameplate preview). `entry.build` is
-- handed the parent, the x/y to start at and the width it may use, and
-- returns the height it took.
local function MakeCustom(page, entry, y, x, width)
  local height = entry.build(page, x or PAD, y, width or (SPAN - 2 * PAD - 2 * CARD)) or 0
  entry.height = height
  return height
end

-- A checkbox with `switch = true` is a pill switch instead of a box, with
-- the label and description beside it.
local function MakeSwitchRow(page, entry, y, x)
  x = x or PAD
  -- `get`/`set` let a switch front something that isn't a plain true/false
  -- setting (the unit tooltips' switch sets a mode).
  local sw = ns.Skin.Switch(page, PURPLE, function(on)
    if entry.set then
      entry.set(on)
    else
      Store(entry)[entry.key] = on and true or false
    end
    Changed(entry)
  end)
  sw:SetSize(40, 20)
  sw.knob:SetSize(16, 16)
  sw:SetPoint("TOPLEFT", x, y - 2)
  -- A tick in the empty half when it's on, as in the mock-up: without it the
  -- switch reads as a box.
  local tick = sw:CreateTexture(nil, "OVERLAY")
  tick:SetSize(16, 16)
  tick:SetPoint("LEFT", 2, 0)
  tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  tick:SetVertexColor(LILAC[1], LILAC[2], LILAC[3], 1)
  sw.tick = tick
  local setOn = sw.SetOn
  function sw:SetOn(on)
    local result = setOn(self, on)
    tick:SetShown(self.on)
    return result
  end
  local text = Label(page, x + 52, y - 4, entry.label)
  Description(page, x + 52, y - 20, entry.desc)
  entry.widget = sw
  entry.refresh = function()
    if entry.get then
      sw:SetOn(entry.get() and true or false)
    else
      sw:SetOn(Store(entry)[entry.key] and true or false)
    end
    text:SetText(entry.label)
  end
  return sw
end

local function MakeCheckbox(page, entry, y, x)
  if entry.switch then
    return MakeSwitchRow(page, entry, y, x)
  end
  x = x or PAD
  local box = CreateFrame("CheckButton", nil, page)
  box:SetSize(20, 20)
  box:SetPoint("TOPLEFT", x, y - 2)
  box.accent, box.edge, box.edgeLit = { 0.40, 0.18, 0.78, 1 }, BRASS, { 0.92, 0.74, 0.38, 1 }
  ns.Skin.Checkbox(box)
  box:SetSize(22, 22)
  box:SetScript("OnClick", function(self)
    Store(entry)[entry.key] = self:GetChecked() and true or false
    Changed(entry)
  end)
  local text = Label(page, x + 28, y - 5, entry.label)
  Description(page, x + 28, y - 21, entry.desc)
  entry.widget = box
  entry.refresh = function()
    box:SetChecked(Store(entry)[entry.key] and true or false)
    if box.Paint then
      box:Paint(box)
    end
    text:SetText(entry.label)
  end
  return box
end

-- Steppers and cyclers put their label on the left and their control against
-- the page's right edge, so nothing depends on the window's width.
-- A stepper with `slider = true` is drawn as a slider instead of - value +:
-- label and description on the left, the track and the value in its box on
-- the right (the XP Bar page, to the owner's mock-up).
local SLIDER_W = 240
local function MakeSliderRow(page, entry, y, x, right)
  x, right = x or PAD, right or PAD
  Label(page, x, y - 4, entry.label)
  Description(page, x, y - 20, entry.desc)
  local value = CreateFrame("Frame", nil, page)
  value:SetSize(64, 26)
  value:SetPoint("TOPRIGHT", page, "TOPRIGHT", -right, y + 1)
  local valueLook, valueInk = FieldColors(page)
  ns.Skin.Panel(value, valueLook)
  value.text = value:CreateFontString(nil, "OVERLAY")
  OptionFont(value.text, "general")
  value.text:SetPoint("CENTER")
  value.text:SetTextColor(unpack(valueInk))
  value.text:SetShadowColor(0, 0, 0, 0)
  local slider = MakeSlider(page, entry.sliderWidth or SLIDER_W, entry)
  slider:SetPoint("RIGHT", value, "LEFT", -16, 0)
  -- A faint rule under the row, as between the mock-up's rows.
  local rule = page:CreateTexture(nil, "BORDER")
  rule:SetPoint("TOPLEFT", x, y - RowHeight(entry) + 4)
  rule:SetPoint("RIGHT", page, "RIGHT", -right, 0)
  rule:SetHeight(ns.Media.Pixel())
  rule:SetColorTexture(INK_EDGE[1], INK_EDGE[2], INK_EDGE[3], 0.25)
  entry.widget = { slider = slider, value = value.text }
  entry.refresh = function()
    local v = Store(entry)[entry.key]
    value.text:SetText(entry.format and entry.format(v) or tostring(v))
    slider:Paint()
  end
end

local function MakeStepper(page, entry, y, x, right)
  if entry.slider then
    return MakeSliderRow(page, entry, y, x, right)
  end
  x, right = x or PAD, right or PAD
  Label(page, x, y - 4, entry.label)
  Description(page, x, y - 20, entry.desc)
  local minus = Button(page, 24, "-", nil)
  minus:SetPoint("TOPRIGHT", page, "TOPRIGHT", -(right + 96), y - 1)
  local plus = Button(page, 24, "+", nil)
  plus:SetPoint("TOPRIGHT", page, "TOPRIGHT", -right, y - 1)

  local value = page:CreateFontString(nil, "OVERLAY")
  OptionFont(value, "general")
  value:SetPoint("LEFT", minus, "RIGHT", 4, 0)
  value:SetPoint("RIGHT", plus, "LEFT", -4, 0)
  value:SetJustifyH("CENTER")
  value:SetTextColor(unpack(OnParchment(page) and INK_PURPLE or LILAC))

  local function change(direction)
    local store = Store(entry)
    local v = (store[entry.key] or entry.min) + direction * entry.step
    v = math.floor(v / entry.step + 0.5) * entry.step
    store[entry.key] = math.max(entry.min, math.min(entry.max, v))
    Changed(entry)
  end
  minus:SetScript("OnClick", function() change(-1) end)
  plus:SetScript("OnClick", function() change(1) end)

  entry.widget = { minus = minus, plus = plus, value = value }
  entry.refresh = function()
    local v = Store(entry)[entry.key]
    value:SetText(entry.format and entry.format(v) or tostring(v))
  end
end

local function MakeCycler(page, entry, y, x, right)
  x, right = x or PAD, right or PAD
  Label(page, x, y - 4, entry.label)
  Description(page, x, y - 20, entry.desc)
  local button = Button(page, 200, "", nil)
  button:SetScript("OnClick", function(self) OpenDropdown(self, entry) end)
  button:SetPoint("TOPRIGHT", page, "TOPRIGHT", -right, y - 1)
  button.text:SetJustifyH("LEFT")
  button.text:ClearAllPoints()
  button.text:SetPoint("LEFT", 8, 0)
  button.text:SetPoint("RIGHT", -20, 0)
  local arrow = button:CreateFontString(nil, "OVERLAY")
  OptionFont(arrow, "general")
  arrow:SetPoint("RIGHT", -8, 0)
  arrow:SetText("v")
  arrow:SetTextColor(unpack(GOLD))
  button.arrow = arrow
  entry.widget = button
  entry.refresh = function()
    local current = Store(entry)[entry.key]
    local shown = tostring(current)
    for _, choice in ipairs(entry.choices() or {}) do
      if choice.value == current then
        shown = choice.label
      end
    end
    button:SetText(shown)
  end
end

local function MakeAction(page, entry, y, x)
  x = x or PAD
  local button = Button(page, entry.width or 200, entry.label, entry.onClick)
  button:SetPoint("TOPLEFT", x, y - 1)
  if entry.desc then
    -- A tile: an icon on the left, the label up top, the description under it.
    button:SetHeight(ROW + 14)
    local textX = 10
    if entry.texture then
      -- A game texture as it is (the raid marks), not one of our glyphs.
      local icon = button:CreateTexture(nil, "ARTWORK")
      icon:SetSize(26, 26)
      icon:SetTexture(entry.texture)
      icon:SetPoint("LEFT", 10, 0)
      textX = 42
    elseif entry.icon then
      local icon = ns.Skin.Icon(button, entry.icon, 26, LILAC)
      icon:SetPoint("LEFT", 10, 0)
      textX = 42
    end
    button.text:ClearAllPoints()
    button.text:SetPoint("TOPLEFT", textX, -7)
    button.text:SetJustifyH("LEFT")
    local desc = button:CreateFontString(nil, "OVERLAY")
    OptionFont(desc, "dataText")
    desc:SetPoint("TOPLEFT", textX, -24)
    desc:SetPoint("RIGHT", button, "RIGHT", -6, 0)
    desc:SetJustifyH("LEFT")
    if desc.SetWordWrap then desc:SetWordWrap(false) end
    desc:SetText(entry.desc)
    desc:SetTextColor(0.70, 0.66, 0.60)
  end
  entry.widget = button
  entry.refresh = function()
    button:SetText(entry.labelFor and entry.labelFor() or entry.label)
    if entry.isSelected then ns.Skin.SetSelected(button, entry.isSelected()) end
  end
end

-- COLUMNS. A heading with `columns = n` lays the rows of its card side by
-- side, n to a line, each as a block: label, description, and the control
-- under them at the column's full width. This is how the mock-up's cards
-- read -- UI Scale | Font | Bar Texture across one line.
local COL_H = { checkbox = 44, stepper = 82, cycler = 84, action = 50, note = 40, color = 44, input = 66 }

local function ColumnStepper(parent, entry, x, y, w)
  Label(parent, x, y, entry.label)
  Description(parent, x, y - 16, entry.desc)
  local slider = MakeSlider(parent, w - 70, entry)
  slider:SetPoint("TOPLEFT", x, y - 40)
  local value = CreateFrame("Frame", nil, parent)
  value:SetSize(60, 26)
  value:SetPoint("LEFT", slider, "RIGHT", 10, 0)
  local valueLook, valueInk = FieldColors(parent)
  ns.Skin.Panel(value, valueLook)
  value.text = value:CreateFontString(nil, "OVERLAY")
  OptionFont(value.text, "general")
  value.text:SetPoint("CENTER")
  value.text:SetTextColor(unpack(valueInk))
  value.text:SetShadowColor(0, 0, 0, 0)
  entry.widget = { slider = slider, value = value.text }
  entry.refresh = function()
    local v = Store(entry)[entry.key]
    value.text:SetText(entry.format and entry.format(v) or tostring(v))
    slider:Paint()
  end
end

local function ColumnCycler(parent, entry, x, y, w)
  Label(parent, x, y, entry.label)
  Description(parent, x, y - 16, entry.desc)
  local button = Button(parent, w, "", nil)
  button:SetHeight(28)
  button:SetPoint("TOPLEFT", x, y - 38)
  button:SetScript("OnClick", function(self) OpenDropdown(self, entry) end)
  button.text:SetJustifyH("LEFT")
  button.text:ClearAllPoints()
  button.text:SetPoint("LEFT", 8, 0)
  button.text:SetPoint("RIGHT", -20, 0)
  local arrow = button:CreateFontString(nil, "OVERLAY")
  OptionFont(arrow, "general")
  arrow:SetPoint("RIGHT", -8, 0)
  arrow:SetText("v")
  arrow:SetTextColor(unpack(GOLD))
  button.arrow = arrow
  entry.widget = button
  entry.refresh = function()
    local current = Store(entry)[entry.key]
    local shown = tostring(current)
    for _, choice in ipairs(entry.choices() or {}) do
      if choice.value == current then shown = choice.label end
    end
    button:SetText(shown)
  end
end

local function ColumnCheckbox(parent, entry, x, y)
  MakeCheckbox(parent, entry, y, x)
end

local function ColumnAction(parent, entry, x, y, w)
  entry.width = w
  MakeAction(parent, entry, y, x)
end

-- A text box in a column card: label and hint above, the box filling the
-- column under them, rather than pinned to the card's right edge.
local function ColumnInput(parent, entry, x, y, w)
  Label(parent, x, y, entry.label)
  Description(parent, x, y - 16, entry.desc)
  local box = MakeInputBox(parent, entry)
  box:SetSize(w, 22)
  box:SetPoint("TOPLEFT", x, y - 36)
end

-- Parchment laid in nine pieces cut from the one painted sheet. Stretching
-- the square over a wide card smeared its grain into planks; this way the
-- torn corners stay their true size, the edges stretch only along their
-- length, and the calm middle of the sheet fills the rest.
local PARCH_CUT = 0.12      -- corner width, as a fraction of the sheet
local PARCH_SIZE = 28       -- corner width on screen
local function Parchment(frame)
  local c, s = PARCH_CUT, PARCH_SIZE
  local cuts = { { 0, c }, { c, 1 - c }, { 1 - c, 1 } }
  local pieces = {}
  for row = 1, 3 do
    for col = 1, 3 do
      local t = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
      t:SetTexture(SKIN .. "parchment")
      t:SetTexCoord(cuts[col][1], cuts[col][2], cuts[row][1], cuts[row][2])
      pieces[(row - 1) * 3 + col] = t
    end
  end
  local tl, t, tr, l, m, r, bl, b, br = unpack(pieces)
  tl:SetPoint("TOPLEFT"); tl:SetSize(s, s)
  tr:SetPoint("TOPRIGHT"); tr:SetSize(s, s)
  bl:SetPoint("BOTTOMLEFT"); bl:SetSize(s, s)
  br:SetPoint("BOTTOMRIGHT"); br:SetSize(s, s)
  t:SetPoint("TOPLEFT", tl, "TOPRIGHT"); t:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  b:SetPoint("TOPLEFT", bl, "TOPRIGHT"); b:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  l:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); l:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
  r:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); r:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  m:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT"); m:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
  frame.parchment = pieces
  return pieces
end

-- The pieces a hand-built page needs to look exactly like a schema page: the
-- same parchment, the same fonts and inks, and the same row makers (so a
-- checkbox or slider there IS the one on every other page, refresh and all).
-- An entry handed to a row maker needs `moduleName` (or `store`) so it knows
-- where its value lives.
-- The hand-built pages' text: the general font at a size, an optional colour.
-- (CastBar, Keybinds, Modules and Profiles each carried an identical copy.)
local function PageFont(fs, size, color)
  fs:SetFont(ns.Media.Role("general"), size, "")
  if color then fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
  return fs
end

local function PageText(parent, size, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  PageFont(fs, size, color)
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

ns.OptionsKit = {
  PageFont = PageFont, PageText = PageText,
  Parchment = Parchment, Button = Button, Label = Label, Description = Description,
  BigFont = BigFont, OptionFont = OptionFont, FieldColors = FieldColors,
  MakeCheckbox = MakeCheckbox, MakeStepper = MakeStepper, MakeCycler = MakeCycler,
  MakeAction = MakeAction,
  INK = INK, INK_DIM = INK_DIM, INK_EDGE = INK_EDGE, INK_ICON = INK_ICON,
  GOLD = GOLD, LILAC = LILAC, PURPLE = PURPLE, ROW = ROW, RowHeight = RowHeight,
}

-- One card: a dark box with the blue edge and a header strip. Rows go
-- inside it; the card is sized to them once the section ends.
local function OpenCard(page, y, title, icon)
  local card = CreateFrame("Frame", nil, page)
  card:SetPoint("TOPLEFT", PAD, y)
  card:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
  ns.Skin.Panel(card, { color = { 1, 1, 1, 1 }, borderColor = { 0, 0, 0, 0 } })
  card.bg:SetColorTexture(0, 0, 0, 0)
  Parchment(card)
  card.isParchment = true
  local head = CreateFrame("Frame", nil, card)
  head:SetPoint("TOPLEFT", 1, -1)
  head:SetPoint("TOPRIGHT", -1, -1)
  head:SetHeight(32)
  head.isParchment = true
  local rule = head:CreateTexture(nil, "BORDER")
  rule:SetPoint("BOTTOMLEFT", 10, 0); rule:SetPoint("BOTTOMRIGHT", -10, 0); rule:SetHeight(ns.Media.Pixel())
  rule:SetColorTexture(INK_EDGE[1], INK_EDGE[2], INK_EDGE[3], 0.45)
  local mark = ns.Skin.Icon(head, icon or "general", 20, INK_ICON)
  mark:SetPoint("LEFT", 12, 0)
  local text = head:CreateFontString(nil, "OVERLAY")
  BigFont(text, 17)
  text:SetPoint("LEFT", mark, "RIGHT", 10, 0)
  text:SetText(title)
  text:SetTextColor(unpack(INK))
  text:SetShadowColor(0, 0, 0, 0)
  card.title, card.head = text, head
  return card
end

-- Builds one page from a schema and remembers the refreshers. The first
-- heading is the page's title (big, with the note under it as a subtitle);
-- every heading after that opens a card.
-- Lays a list of entries into `container`, starting at `startY`, and
-- returns the y it finished at. `page` is where the refreshers and cards
-- are collected, so a tabbed page's sub-pages all report to one owner.
local function LayOut(container, schema, startY, page, pageTitle)
  local y = startY
  local first = pageTitle ~= nil
  local card, cardY   -- the open card and the y inside it
  local columns, col, colTop, colTallest = nil, 0, nil, 0
  local function CloseCard()
    if card then
      if columns and col > 0 then
        cardY = colTop - colTallest
      end
      card:SetHeight(-cardY + CARD)
      y = y - card:GetHeight() - 12
      card, cardY = nil, nil
      columns, col, colTop, colTallest = nil, 0, nil, 0
    end
  end
  -- Where the next column block goes, and its width.
  local function NextColumn(kind)
    local inner = (SPAN - 2 * PAD - 16) - 2 * CARD
    local w = (inner - (columns - 1) * 16) / columns
    if col == 0 then
      colTop = cardY
      colTallest = 0
    end
    local x = CARD + col * (w + 16)
    local h = COL_H[kind] or 60
    if h > colTallest then colTallest = h end
    col = col + 1
    local at = colTop
    if col >= columns then
      cardY = colTop - colTallest
      col = 0
      colTallest = 0
    end
    return x, at, w
  end
  -- A row that arrives with no card open (a module page with one heading)
  -- gets a card called Settings, so every row on every page sits in one.
  local function Target()
    if not card then
      card = OpenCard(container, y, "Settings")
      page.cards[#page.cards + 1] = card
      cardY = -(32 + 12)
    end
    return card, cardY, CARD
  end
  local function Advance(h)
    if card then cardY = cardY - h else y = y - h end
  end

  for _, entry in ipairs(schema) do
    if not entry.shown or entry.shown() then
      if entry.type == "heading" then
        if first then
          -- In the painted header when the page has one; otherwise on top.
          local host = page.head or container
          local hy = page.head and -18 or y
          local title = Label(host, PAD, hy, pageTitle or entry.label, "header")
          BigFont(title, 30)
          title:SetTextColor(1, 0.97, 0.92)
          page.title = title
          if not page.head then y = y - 30 end
          if entry.subtitle then
            local sub = Label(host, PAD, hy - 38, entry.subtitle)
            sub:SetTextColor(0.86, 0.82, 0.76)
            page.tagline = sub
            if not page.head then y = y - 22 end
          end
          -- The page's own action (Restore Defaults), on the right of the title.
          if entry.pageAction then
            local action = entry.pageAction
            local button = Button(host, action.width or 150, action.label, nil)
            button:SetHeight(24)
            -- Beside the search box on the painted header, on the same line:
            -- the header's own top-right corner is where the search box
            -- sits, and the two were drawn on top of each other.
            local search = page.head and _G.ForeverUIOptionsSearch
            if search then
              button:SetPoint("LEFT", search, "RIGHT", 8, 0)
            else
              button:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PAD, hy - 4)
            end
            button:SetScript("OnClick", function() action.run() end)
            page.pageAction = button
          end
          first = false
        else
          CloseCard()
          card = OpenCard(container, y, entry.label, entry.icon)
          page.cards[#page.cards + 1] = card
          cardY = -(32 + 12)
          columns = entry.columns
          -- A heading can carry one action in its header, on the right.
          if entry.action then
            local action = entry.action
            local button = Button(card.head, action.width or 150, action.label, nil)
            button:SetHeight(24)
            button:SetPoint("RIGHT", card.head, "RIGHT", -10, 0)
            button:SetScript("OnClick", function() action.run() end)
            card.action = button
          end
        end
      elseif columns and card and entry.type ~= "note" then
        -- In a column card every row is a block.
        local x, at, w = NextColumn(entry.type)
        if entry.type == "stepper" then
          ColumnStepper(card, entry, x, at, w)
        elseif entry.type == "cycler" then
          ColumnCycler(card, entry, x, at, w)
        elseif entry.type == "checkbox" then
          ColumnCheckbox(card, entry, x, at)
        elseif entry.type == "color" then
          -- MakeColor's last argument is the swatch's distance from the
          -- card's RIGHT edge: the right end of this column, not its left x
          -- (that put column 0's swatch over column 1, and column 1's in 0).
          MakeColor(card, entry, at, x, (SPAN - 2 * PAD - 16) - x - w)
        elseif entry.type == "action" then
          ColumnAction(card, entry, x, at, w)
        elseif entry.type == "input" then
          ColumnInput(card, entry, x, at, w)
        else
          -- Nothing knows how to draw this kind in a column card. Say so
          -- rather than laying out an empty gap where a row should be.
          ns.Print(("options: a %s row can't sit in a card with columns (%s)")
            :format(tostring(entry.type), tostring(entry.label)))
        end
      elseif entry.type == "note" then
        local parent, at, inset
        if not page.subtitle and not card then
          parent, at, inset = container, y, PAD   -- the first note is the subtitle, outside any card
        else
          parent, at, inset = Target()
        end
        local text = entry.labelFor and entry.labelFor() or entry.label
        local note = Label(parent, inset, at, text)
        note:SetPoint("RIGHT", parent, "RIGHT", -inset, 0)
        note:SetJustifyH("LEFT")
        note:SetTextColor(unpack(OnParchment(parent) and INK_DIM or ns.Colors.ui.textDim))
        if not page.subtitle and not card then
          note:SetTextColor(0.75, 0.80, 0.86)
          page.subtitle = note
        end
        entry.widget = note
        if entry.labelFor then
          entry.refresh = function() note:SetText(entry.labelFor()) end
        end
        -- Long notes wrap; make room for the lines they take.
        -- (Measured on the text shown -- a labelFor note has no label.)
        local lines = math.max(1, math.ceil((#(type(text) == "string" and text or "") * 5.2) / (SPAN - 2 * PAD - 2 * inset)))
        Advance(14 * lines + 12)
      elseif entry.type == "checkbox" then
        local parent, at, inset = Target()
        MakeCheckbox(parent, entry, at, inset)
        Advance(RowHeight(entry))
      elseif entry.type == "stepper" then
        local parent, at, inset = Target()
        MakeStepper(parent, entry, at, inset, inset)
        Advance(RowHeight(entry))
      elseif entry.type == "cycler" then
        local parent, at, inset = Target()
        MakeCycler(parent, entry, at, inset, inset)
        Advance(RowHeight(entry))
      elseif entry.type == "color" then
        local parent, at, inset = Target()
        MakeColor(parent, entry, at, inset, inset)
        Advance(RowHeight(entry))
      elseif entry.type == "input" then
        local parent, at, inset = Target()
        MakeInput(parent, entry, at, inset, inset)
        Advance(RowHeight(entry))
      elseif entry.type == "custom" and entry.bare then
        -- A page that lays itself out (the Profiles page): straight onto the
        -- page, full width, no card around it.
        CloseCard()
        card = nil
        local h = MakeCustom(container, entry, y, PAD, SPAN - 24 - 2 * PAD)
        y = y - h - 10
      elseif entry.type == "custom" then
        local parent, at, inset = Target()
        local w = (parent == page) and (SPAN - 2 * PAD) or (SPAN - 2 * PAD - 2 * CARD)
        Advance(MakeCustom(parent, entry, at, inset, w) + 10)
      elseif entry.type == "action" then
        local parent, at, inset = Target()
        MakeAction(parent, entry, at, inset)
        Advance(entry.desc and (ROW + 18) or ROW)
      end
      if entry.refresh then
        page.entries[#page.entries + 1] = entry
      end
    end
  end
  CloseCard()
  -- Size the scroll child to the content, so the wheel has somewhere to go.
  -- At least the viewport's height, so short pages don't wobble.
  return y
end

-- Builds one page from a schema and remembers the refreshers. The first
-- heading is the page's title (big, with the note under it as a subtitle);
-- every heading after that opens a card.
--
-- TABS. An entry carrying `tab = "enemy"` belongs to that tab; the page
-- grows a strip of tab buttons and one sub-page each, and only the chosen
-- one is shown. Entries with no tab (the title, a note) stay above the
-- strip and are always there. A page with no tabbed entry is laid out flat,
-- exactly as before.
local function BuildPage(page, schema, pageTitle)
  page.entries = {}
  page.cards = {}

  local order, byTab, plain = {}, {}, {}
  for _, entry in ipairs(schema) do
    if entry.tab then
      if not byTab[entry.tab] then
        byTab[entry.tab] = {}
        order[#order + 1] = { key = entry.tab, label = entry.tabLabel or entry.tab }
      elseif entry.tabLabel then
        for _, t in ipairs(order) do
          if t.key == entry.tab then t.label = entry.tabLabel end
        end
      end
      local list = byTab[entry.tab]
      list[#list + 1] = entry
    else
      plain[#plain + 1] = entry
    end
  end

  local y = LayOut(page, plain, TOP, page, pageTitle)
  local viewport = HEIGHT - HEADER - FOOTER - 16

  if #order == 0 then
    page:SetHeight(math.max(viewport, -y + PAD))
    return
  end

  -- The tab strip, then a sub-page under it for each tab.
  page.tabs, page.tabPages = {}, {}
  -- Tabs take the width their label needs and wrap onto another row when
  -- the strip runs out: nine fixed-width tabs used to run off the page.
  local stripY = y - 4
  local x, row = PAD, 0
  local limit = SPAN - 24 - PAD
  for _, tab in ipairs(order) do
    local width = math.max(72, math.floor(#tab.label * 6.2) + 26)
    if x + width > limit and x > PAD then
      x, row = PAD, row + 1
    end
    local button = Button(page, width, tab.label, nil)
    button:SetHeight(26)
    button:SetPoint("TOPLEFT", x, stripY - row * 30)
    button.tabKey = tab.key
    page.tabs[tab.key] = button
    x = x + width + 4
  end
  local stripBottom = stripY - row * 30
  for _, tab in ipairs(order) do
    local sub = CreateFrame("Frame", nil, page)
    sub:SetPoint("TOPLEFT", 0, stripBottom - 32)
    sub:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    sub:SetHeight(1)
    page.tabPages[tab.key] = sub
    local endY = LayOut(sub, byTab[tab.key], 0, page)
    sub.contentHeight = -endY + PAD
    sub:SetHeight(math.max(1, sub.contentHeight))
    sub:Hide()
  end

  function page.SelectTab(key)
    page.selectedTab = key
    for name, sub in pairs(page.tabPages) do
      sub:SetShown(name == key)
      ns.Skin.SetSelected(page.tabs[name], name == key)
    end
    local sub = page.tabPages[key]
    local content = (-stripBottom + 32) + (sub and sub.contentHeight or 0) + PAD
    page:SetHeight(math.max(viewport, content))
    if page.scroll and page.scroll.SetVerticalScroll then page.scroll:SetVerticalScroll(0) end
  end
  for _, tab in ipairs(order) do
    page.tabs[tab.key]:SetScript("OnClick", function() page.SelectTab(tab.key) end)
  end
  page.SelectTab(order[1].key)
end

---------------------------------------------------------------------------
-- Core pages
---------------------------------------------------------------------------

local function MediaChoices(kind)
  return function()
    local list = {}
    for _, name in ipairs(ns.Media.List(kind)) do
      list[#list + 1] = { label = name, value = name }
    end
    return list
  end
end

local function CoreSchema()
  local schema = {
    { type = "heading", label = "General", subtitle = "Core settings for ForeverUI." },
    { type = "note", label = "One flat, movable interface for World of Warcraft: Forever -- action bars, unit frames, a cast bar, a square minimap, the quest tracker, chat and nameplates, all in one set. Pick a module on the left to set it up. Type /fui for the full list of commands." },

    -- Moving frames, resetting positions, the setup and "Healing only" live on
    -- Quick Setup now; the Everything / Frames only / No frames sets on the
    -- Modules page (consolidation, 25 Sept 2026). General is the look.
    { type = "heading", label = "Appearance", columns = 3, icon = "appearance" },
    { type = "stepper", scope = "core", key = "scale", label = "UI Scale", desc = "Adjust the overall size of the UI.",
      min = 0.6, max = 1.6, step = 0.05,
      format = function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end,
      apply = function() ns.ApplyMoverPositions() end },
    { type = "cycler", key = "font", label = "Font", desc = "Global font for all text.",
      store = function() return ns.db.media end,
      choices = MediaChoices("font"),
      apply = function() ns.RefreshAllModules() end },
    { type = "cycler", key = "texture", label = "Bar Texture", desc = "Texture used for status bars.",
      store = function() return ns.db.media end,
      choices = MediaChoices("statusbar"),
      apply = function() ns.RefreshAllModules() end },

    -- Gnatz_0815 on CurseForge, 28 Sept 2026: "rounded corners ... a UI
    -- that was different from the sharp, angular style". Windows and panels
    -- first, then the action buttons and unit frames (each with its own
    -- switch); nameplates, the minimap and the other bars stay square.
    { type = "heading", label = "Corners", columns = 2, icon = "appearance" },
    { type = "checkbox", scope = "core", key = "roundCorners", label = "Rounded corners",
      desc = "Windows, panels and buttons with rounded corners. Off: square, as before.",
      apply = function() ns.Skin.ApplyCorners() end },
    { type = "stepper", scope = "core", key = "cornerRadius", label = "Corner size",
      desc = "How round. Small boxes and buttons stay gentler than windows.",
      min = 2, max = 16, step = 1,
      apply = function() ns.Skin.ApplyCorners() end },
    { type = "checkbox", scope = "core", key = "roundButtons", label = "Round the action buttons too",
      desc = "The spell icon moves in a pixel or two to stay inside the curve.",
      apply = function() ns.Skin.ApplyCorners() end },
    { type = "checkbox", scope = "core", key = "roundUnitFrames", label = "Round the unit frames too",
      desc = "Player, target, focus and the rest. The bars move in to stay inside the curve.",
      apply = function() ns.Skin.ApplyCorners() end },

    -- Altiokis on CurseForge, 28 Sept 2026: "it crashes when i try to play
    -- with controller" (Core/Controller.lua).
    { type = "heading", label = "Controller", icon = "general" },
    -- Labels in plain words (Altiokis, 28 Sept 2026: "I'm confused about the
    -- follow the game, not sure what that means").
    { type = "cycler", scope = "core", key = "controllerMode", label = "Controller or keyboard?",
      desc = "Leave it on Automatic: it switches by itself when you play with a controller.",
      choices = function()
        return { { value = "auto", label = "Automatic" }, { value = "on", label = "Always controller" },
          { value = "off", label = "Always keyboard + mouse" } }
      end,
      apply = function() if ns.ControllerCheck then ns.ControllerCheck() end end },
    { type = "note", labelFor = function()
        local on = ns.ControllerActive and ns.ControllerActive()
        local mode = ns.ControllerSetting and ns.ControllerSetting() or "auto"
        local how = mode == "auto"
          and "Automatic means: if the game is in controller mode (a controller turned on in Esc > Options > "
            .. "Controller, and you're playing with it), ForeverUI switches to controller mode too. Nothing to set. "
          or ""
        return how .. (on
          and "Right now: controller mode. The game's own controller bars, bag, buffs and radial menu are in "
            .. "charge; ForeverUI's action bars, bag window, micro bar and XP bar step aside. Unit frames, the healing "
            .. "grids, quests, nameplates and the rest of the look stay."
          or "Right now: keyboard and mouse, all of ForeverUI in use.")
          .. " Switching either way asks for a reload."
      end },

    { type = "heading", label = "Interface Options", columns = 2, icon = "general" },
    -- The loot window is an Edit Mode frame on Forever: ForeverUI never moves
    -- it (moving Edit Mode frames from an addon taints them). This is the
    -- game's own switch; otherwise Esc > Edit Mode moves it (owner, 26 Sept
    -- 2026: it opened over the action bars).
    { type = "checkbox", key = "lootUnderMouse", label = "Open the loot window at the mouse",
      desc = "The game's own setting. Off: it opens where Edit Mode puts it (Esc > Edit Mode to move it).",
      store = function()
        return setmetatable({}, {
          __index = function() return GetCVarBool and GetCVarBool("lootUnderMouse") or false end,
          __newindex = function(_, _, value)
            ns.SetCVar("lootUnderMouse", value and "1" or "0")
          end,
        })
      end },
    { type = "checkbox", scope = "core", key = "minimapButton", label = "Show the minimap button",
      desc = "Display the ForeverUI button near the minimap.",
      apply = function() ns.UpdateMinimapButton() end },
    { type = "checkbox", scope = "core", key = "hideIssueReporter", label = "Hide the beta Issue Reporter",
      desc = "Off = tucked top-left (green icon).",
      apply = function() ns.ApplyIssueReporter() end },

    { type = "heading", label = "Border colour", icon = "appearance" },
    { type = "note", label = "The edge on everything ForeverUI draws -- the micro bar, the quest tracker, the minimap, chat, bags and the rest. Click the swatch for the colour wheel." },
    { type = "color", scope = "core", key = "accentColor", label = "Border colour",
      desc = "Applies everywhere, straight away.",
      apply = function() ns.ApplyAccentColor() end },
    { type = "action", label = "Back to blue", width = 200, desc = "The colour it shipped with.",
      icon = "reset",
      onClick = function()
        ns.db.accentColor = { unpack(ns.Colors.defaultAccent, 1, 3) }
        ns.ApplyAccentColor()
        ns.RefreshOptions()
      end },

  }
  -- Info (who made it, how to reach him) at the bottom of General rather
  -- than a sidebar row of its own.
  if ns.InfoSchema then
    for i, entry in ipairs(ns.InfoSchema()) do
      if i == 1 and entry.type == "heading" then
        schema[#schema + 1] = { type = "heading", label = entry.label or "Info", icon = entry.icon or "info" }
      else
        schema[#schema + 1] = entry
      end
    end
  end
  return schema
end

local function ModulesSchema()
  local schema = { { type = "heading", label = "Modules" } }
  ns.ForEachModule(function(module, name)
    schema[#schema + 1] = {
      type = "action",
      width = 260,
      label = module.title or name,
      labelFor = function()
        return ("%s: %s"):format(module.title or name, ns.IsModuleEnabled(name) and "on" or "off")
      end,
      onClick = function()
        ns.SetModuleEnabled(name, not ns.IsModuleEnabled(name))
        ns.RefreshOptions()
      end,
    }
  end)
  return schema
end


---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function SelectPage(key)
  panel.selected = key
  for name, page in pairs(pages) do
    local frame = page.scroll or page
    frame:SetShown(name == key)
    if page.head then page.head:SetShown(name == key) end
    if name == key and page.scroll and page.scroll.SetVerticalScroll then
      page.scroll:SetVerticalScroll(0)   -- always open a page at the top
    end
    if panel.tabs[name] then
      local tab = panel.tabs[name]
      ns.Skin.SetSelected(tab, name == key)
      if name == key then
        ns.Skin.SetPanelColor(tab, { 0.26, 0.12, 0.52, 0.95 })
        ns.Skin.SetBorderColor(tab, PURPLE)
        tab.text:SetTextColor(1, 1, 1)
      end
      if tab.mark then tab.mark:SetShown(name == key) end
    end
  end
end


function ns.RefreshOptions()
  if not panel or not panel:IsShown() then
    return
  end
  for _, page in pairs(pages) do
    for _, entry in ipairs(page.entries or {}) do
      entry.refresh()
    end
  end
  ns.RefreshRoleSwitches()
end

-- Sidebar entries carry a small icon, as in the mock-up. Game icons, so
-- nothing has to ship; any page not listed gets the gear.
local PAGE_ICONS = {
  ["role:Heal"] = "heal", ["role:Tank"] = "tank", ["role:DPS"] = "dps",
  quick = "star", general = "general", info = "info", modules = "modules", profiles = "profiles",
  UnitFrames = "unitframes", CastBar = "castbar", ActionBars = "actionbars",
  Keybinds = "keybinds", XPBar = "xpbar", Quests = "quests", Minimap = "minimap",
  Nameplates = "nameplates", Chat = "chat", Bags = "bags", MicroBar = "microbar",
  Frames = "unitframes", Arrow = "map", Tooltips = "info", QuestForever = "quests", Cooldowns = "spells", Kicks = "target", Markers = "target",
}

local TAB_H = 24
local TAB_MIN_H = 16        -- the tightest a row gets and still reads (27 rows fit)
-- The column's floor: the well stops 106 above the panel's foot and Reset to
-- Defaults (28 tall, 6 in) sits at the bottom of it, with a gap above.
local TABS_TOP = HEADER + 18
local TABS_BOTTOM = HEIGHT - (106 + 6 + 28 + 8)

-- The sidebar's entries, in order, laid out from the top; a search hides
-- the ones that don't match and closes the gaps.
--
-- Every module with settings adds a row, and at twenty rows the list ran
-- down under Reset to Defaults (owner, 23 Sept 2026: "this steps on each
-- other"). So the rows close up just enough to fit the room there is: full
-- height while they fit, tighter as pages are added, never under the button.
local function LayoutTabs()
  local shown = 0
  for _, tab in ipairs(panel.tabOrder) do
    if tab:IsShown() then shown = shown + 1 end
  end
  local step = TAB_H + 2
  if shown > 0 then
    step = math.max(TAB_MIN_H + 1, math.min(step, math.floor((TABS_BOTTOM - TABS_TOP) / shown)))
  end
  local y = -TABS_TOP
  for _, tab in ipairs(panel.tabOrder) do
    if tab:IsShown() then
      tab:ClearAllPoints()
      tab:SetPoint("TOPLEFT", 20, y)
      tab:SetHeight(step - 2)
      y = y - step
    end
  end
  panel.tabStep = step
end

-- The search box: type, and the sidebar keeps only the pages whose name or
-- whose settings mention it; the first match is opened.
local function ApplySearch(query)
  query = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local firstMatch
  for _, tab in ipairs(panel.tabOrder) do
    local key
    for k, t in pairs(panel.tabs) do if t == tab then key = k end end
    local hit = query == "" or (tab.label or ""):lower():find(query, 1, true) ~= nil
    if not hit and key and pages[key] then
      for _, entry in ipairs(pages[key].entries or {}) do
        local label = (entry.label or "") .. " " .. (entry.desc or "")
        if label:lower():find(query, 1, true) then hit = true break end
      end
    end
    tab:SetShown(hit)
    if hit and query ~= "" and not firstMatch and key and pages[key] then firstMatch = key end
  end
  LayoutTabs()
  if firstMatch then SelectPage(firstMatch) end
end

local function MakeTab(key, label, color, onClick)
  local tab = Button(panel, SIDEBAR - 38, label, onClick)
  tab:SetHeight(TAB_H)
  tab.text:ClearAllPoints()
  tab.text:SetPoint("LEFT", 36, 0)
  tab.text:SetJustifyH("LEFT")
  -- The Icons8 glyph, tinted the role's colour for a role, accent otherwise.
  local icon = ns.Skin.Icon(tab, PAGE_ICONS[key] or "general", 18, color or LILAC)
  icon:SetPoint("LEFT", 10, 0)
  if not color and icon.SetDesaturated then
    icon:SetDesaturated(true)   -- the glyphs are blue; grey first, then lilac
    icon:SetVertexColor(LILAC[1] * 1.15, LILAC[2] * 1.15, LILAC[3] * 1.15)
  end
  tab.icon = icon
  -- The lit one carries a bar of accent down its left edge.
  local mark = tab:CreateTexture(nil, "OVERLAY")
  mark:SetPoint("TOPLEFT"); mark:SetPoint("BOTTOMLEFT"); mark:SetWidth(3)
  mark:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
  mark:Hide()
  tab.mark = mark
  if color then
    tab.keepTextColor = true
    tab.text:SetTextColor(unpack(color))
    tab:HookScript("OnEnter", function() tab.text:SetTextColor(unpack(color)) end)
    tab:HookScript("OnLeave", function() tab.text:SetTextColor(unpack(color)) end)
  end
  tab.label = label
  panel.tabOrder[#panel.tabOrder + 1] = tab
  return tab
end

local function AddPage(key, label, schema)
  -- A scroll frame fills the page area; the real content is its child. Long
  -- pages (Action Bars especially) used to run off the bottom of the window
  -- with no way to reach the last rows -- now the wheel scrolls them.
  local scroll = CreateFrame("ScrollFrame", nil, panel)
  scroll:SetPoint("TOPLEFT", SIDEBAR + 8, -CONTENT_TOP)
  scroll:SetPoint("BOTTOMRIGHT", -(16 + SPAN_TRIM), FOOTER + 34)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange() or 0
    local current = self:GetVerticalScroll() or 0
    self:SetVerticalScroll(math.max(0, math.min(range, current - delta * ROW * 2)))
  end)

  local page = CreateFrame("Frame", nil, scroll)
  page:SetWidth(SPAN - 24)
  page:SetHeight(HEIGHT)   -- BuildPage sets the real height once it's laid out
  if scroll.SetScrollChild then scroll:SetScrollChild(page) end
  page.scroll = scroll

  -- The crest and the page's title sit in the painted header, beside the
  -- castle, and stay put while the page under them scrolls.
  local head = CreateFrame("Frame", nil, panel)
  head:SetPoint("TOPLEFT", SIDEBAR + 8, -(HEADER + 10))
  head:SetSize(440, 80)
  page.head = head

  pages[key] = page
  BuildPage(page, schema, label)
  head:Hide()   -- SelectPage shows the open page's
  if page.title then
    local host = page.head or page
    local crest = host:CreateTexture(nil, "ARTWORK")
    crest:SetTexture(SKIN .. "crest")
    crest:SetSize(76, 76)
    crest:SetPoint("TOPLEFT", PAD - 12, page.head and 0 or TOP + 8)
    local glyph = ns.Skin.Icon(host, PAGE_ICONS[key] or "general", 32, { 0.85, 0.80, 1.00 }, "OVERLAY")
    glyph:SetPoint("CENTER", crest, "CENTER", 0, 0)
    page.crest, page.crestGlyph = crest, glyph
    -- Title and tagline step right to clear it.
    for _, fs in ipairs({ page.title, page.tagline }) do
      if fs then
        local point, rel, relPoint, x, y = fs:GetPoint()
        fs:ClearAllPoints()
        fs:SetPoint(point or "TOPLEFT", rel or host, relPoint or "TOPLEFT", (x or PAD) + 70, (y or 0) - 4)
      end
    end
  end
  page.label = label

  local tab = MakeTab(key, label, nil, function() SelectPage(key) end)
  panel.tabs[key] = tab
  LayoutTabs()
  return page
end

-- Role colours: healing is green, tanking orange, DPS red.
local ROLE_GREEN  = { 0.30, 0.85, 0.40 }
local ROLE_ORANGE = { 1.00, 0.55, 0.15 }
local ROLE_PURPLE = { 0.66, 0.42, 1.00 }

-- A left-nav entry that runs an action instead of opening a page (used for the
-- Heal / Tank / DPS role buttons at the top). Coloured, and its colour is kept
-- through hover/select so the role stays obvious.
-- A role row in the sidebar: the glyph and the name open that role's window,
-- and the switch on the right puts that role's GRID up or down without
-- opening anything. The switches are independent -- any combination of the
-- three grids can be on at once, which is the whole point of them. Two jobs in one row, which is why the switch is its own frame --
-- a click on it never reaches the row behind it.
local function AddNavAction(label, color, onClick, roleKey)
  local tab = MakeTab("role:" .. label, label, color, onClick)
  panel.tabs["role:" .. label] = tab
  if roleKey then
    tab.roleKey = roleKey
    tab.roleSwitch = ns.Skin.Switch(tab, color, function(on)
      -- On means on screen now, solo too (ns.Frames.GridState).
      if ns.Frames and ns.Frames.SetGridState then
        ns.Frames.SetGridState(roleKey, on and "always" or "off")
      elseif ns.Frames and ns.Frames.SetGridShown then
        ns.Frames.SetGridShown(roleKey, on)
      end
    end)
    tab.roleSwitch:SetPoint("RIGHT", -8, 0)
    -- Room for it, so a long name never runs under the switch.
    tab.text:SetPoint("RIGHT", -42, 0)
  end
  LayoutTabs()
  return tab
end

-- The switches show what is actually up, which is not necessarily what was
-- last clicked here: the bars can also be turned on from their own page, from
-- /fui rolebars, and by the first run deciding for itself.
function ns.RefreshRoleSwitches()
  if not panel then
    return
  end
  for _, tab in pairs(panel.tabs or {}) do
    if tab.roleSwitch then
      tab.roleSwitch:SetOn(ns.Frames and ns.Frames.IsGridShown
        and ns.Frames.IsGridShown(tab.roleKey) or false)
    end
  end
end

-- Open the party/raid frame settings for a role. All three are real windows.
-- This picks which one you are EDITING; it does not change which grids are on
-- screen -- that is the switch on the right of the row.
local function OpenRole(mode)
  if not ns.Frames then
    ns.Print("the party & raid frames aren't loaded.")
    return
  end
  local shown = ns.Frames.optionsPanel and ns.Frames.optionsPanel:IsShown()
  if ns.Frames.SetMode then
    ns.Frames.SetMode(mode)   -- rebuilds + reopens the window if it was open
  end
  if not shown and ns.Frames.ToggleOptions then
    ns.Frames.ToggleOptions() -- ...open it if it wasn't
  end
  -- Get the big ForeverUI window out of the way -- the role window replaces it,
  -- and its Back button brings this one back.
  if panel then
    panel:Hide()
  end
end
ns.OpenRoleWindow = OpenRole

-- Where the window was last dragged (sprutorgel on CurseForge, 29 Sept
-- 2026: "when foreverui menu opens, it will remember its last position?").
-- Kept with the frame positions in ns.db.movers, so the macro backup carries
-- it through the beta's saving bug like the rest of the layout.
local OPTIONS_POS = "optionsWindow"

local function PlacePanel(frame)
  frame:ClearAllPoints()
  local pos = ns.db and type(ns.db.movers) == "table" and ns.db.movers[OPTIONS_POS]
  if type(pos) == "table" and type(pos[1]) == "string" and type(pos[2]) == "string"
    and tonumber(pos[3]) and tonumber(pos[4]) then
    frame:SetPoint(pos[1], UIParent, pos[2], tonumber(pos[3]), tonumber(pos[4]))
  else
    frame:SetPoint("CENTER")
  end
end
ns.PlaceOptionsWindow = PlacePanel

local function RememberPanel(frame)
  if not (ns.db and frame.GetPoint) then return end
  local point, _, relativePoint, x, y = frame:GetPoint(1)
  if type(point) ~= "string" or not tonumber(x) or not tonumber(y) then return end
  ns.db.movers = type(ns.db.movers) == "table" and ns.db.movers or {}
  ns.db.movers[OPTIONS_POS] = { point, relativePoint or point, math.floor(x + 0.5), math.floor(y + 0.5) }
end
ns.RememberOptionsWindow = RememberPanel

local function CreatePanel()
  panel = CreateFrame("Frame", "ForeverUIOptions", UIParent)
  panel:SetSize(WIDTH, HEIGHT)
  PlacePanel(panel)
  panel:SetFrameStrata("DIALOG")
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:SetClampedToScreen(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    RememberPanel(self)
  end)
  panel:SetScript("OnShow", function()
    ns.Skin.FitToScreen(panel)
    ns.RefreshOptions()
  end)
  panel:Hide()
  table.insert(UISpecialFrames, "ForeverUIOptions")

  ns.Skin.Panel(panel, { color = { 0, 0, 0, 1 }, borderColor = INK_EDGE })
  -- The painted plate. 1536x1024 art laid into the top of a 1024x1024
  -- texture, so the art ends two-thirds of the way down; the sides are
  -- trimmed a little to keep its proportions in a 960x690 window.
  local plate = panel:CreateTexture(nil, "BACKGROUND", nil, -7)
  plate:SetAllPoints()
  plate:SetTexture(SKIN .. "window-plate")
  local artH = 1.0
  plate:SetTexCoord(0, 1, 0, 683 / 1024 * artH)
  panel.plate = plate

  -- The header: emblem, "ForeverUI 0.3.2" with the tagline under it, the
  -- search box, the X.
  local header = ns.Skin.Header(panel, "", function() panel:Hide() end)
  header:SetHeight(HEADER)
  ns.Skin.SetPanelColor(header, { 0, 0, 0, 0 })
  -- The crest: the owner's drawn badge, square, with the black around it
  -- cut away so it sits on the painted header rather than in a box.
  header.logo:SetSize(44, 44)
  header.logo:SetTexture(ns.MEDIA_PATH .. "foreverui-crest")
  header.logo:ClearAllPoints()
  header.logo:SetPoint("LEFT", 14, 0)
  -- The name and the tagline are one drawn picture, in the same wax crayon as
  -- the crest, instead of two lines of type. The art is 512x256 with the
  -- lettering in the top 173 rows, so it is cropped with texcoords and drawn
  -- at its own 512:173 shape; the version number keeps its own small text.
  header.text:Hide()
  local wordmark = header:CreateTexture(nil, "OVERLAY")
  wordmark:SetTexture(ns.MEDIA_PATH .. "foreverui-wordmark")
  wordmark:SetTexCoord(0, 1, 0, 173 / 256)
  wordmark:SetSize(136, 46)
  wordmark:SetPoint("LEFT", header.logo, "RIGHT", 10, 0)
  header.wordmark = wordmark
  local version = header:CreateFontString(nil, "OVERLAY")
  OptionFont(version, "general")
  version:SetPoint("BOTTOMLEFT", wordmark, "BOTTOMRIGHT", 8, 8)
  version:SetText(ns.VERSION)
  ns.Skin.AccentText(version)
  header.tagline = version
  header.close:SetSize(30, 30)
  header.close:ClearAllPoints()
  header.close:SetPoint("RIGHT", -12, 0)

  local search = CreateFrame("EditBox", "ForeverUIOptionsSearch", header)
  -- Over the foot of the castle scene, as in the mock-up.
  search:SetSize(170, 24)
  search:SetPoint("TOP", panel, "TOPLEFT", 612, -108)
  search:SetAutoFocus(false)
  OptionFont(search, "general")
  search:SetTextInsets(30, 8, 0, 0)
  ns.Skin.Panel(search, (FieldColors(header)))
  search.glass = ns.Skin.Icon(search, "search", 16)
  search.glass:SetPoint("LEFT", 8, 0)
  search.hint = search:CreateFontString(nil, "OVERLAY")
  OptionFont(search.hint, "general")
  search.hint:SetPoint("LEFT", 30, 0)
  search.hint:SetText("Search settings...")
  search.hint:SetTextColor(unpack(ns.Colors.ui.textDim))
  search:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    self.hint:SetShown(text == "")
    ApplySearch(text)
  end)
  search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  panel.search = search

  -- The category column sits in its own slightly darker well.
  local well = CreateFrame("Frame", nil, panel)
  -- It stops above the painted candle and mug rather than covering them.
  well:SetPoint("TOPLEFT", 14, -(HEADER + 10))
  well:SetPoint("BOTTOMLEFT", 14, 106)
  well:SetWidth(SIDEBAR - 26)
  -- The painted wooden column shows through; only a faint dark wash so the
  -- menu reads clearly over the grain.
  ns.Skin.Panel(well, { color = { 0, 0, 0, 0.18 }, border = false })
  panel.sidebar = well

  -- Reset to Defaults, at the foot of the column.
  -- Two clicks: it empties the whole profile, which is not a thing to do by
  -- brushing past it.
  local reset
  reset = Button(well, SIDEBAR - 24, "Reset to Defaults", function()
    if reset.armed then
      reset.armed = nil
      reset:SetText("Reset to Defaults")
      ns.ResetProfile()
      ns.Print("profile reset to defaults.")
    else
      reset.armed = true
      reset:SetText("Click again to confirm")
      if C_Timer and C_Timer.After then
        C_Timer.After(4, function() reset.armed = nil; reset:SetText("Reset to Defaults") end)
      end
    end
  end)
  reset:SetHeight(28)
  reset:SetPoint("BOTTOM", well, "BOTTOM", 0, 6)
  panel.resetButton = reset

  -- The footer: a help line, Apply, Close.
  local footer = CreateFrame("Frame", nil, panel)
  footer:SetPoint("BOTTOMLEFT", 1, 1)
  footer:SetPoint("BOTTOMRIGHT", -1, 1)
  footer:SetHeight(FOOTER)
  ns.Skin.Panel(footer, { color = { 0, 0, 0, 0 }, border = false })
  local help = footer:CreateFontString(nil, "OVERLAY")
  OptionFont(help, "general")
  help:SetPoint("LEFT", 246, 18)
  help:SetText("Need help? Type /fui for commands.")
  local helpIcon = ns.Skin.Icon(footer, "info", 16)
  helpIcon:SetPoint("RIGHT", help, "LEFT", -6, 0)
  help:SetTextColor(unpack(ns.Colors.ui.textDim))

  local closeButton = Button(footer, 110, "Close", function() panel:Hide() end)
  closeButton:SetHeight(32)
  -- On the painted ledge between the mug and the scroll.
  -- On the painted ledge between the mug and the scroll.
  closeButton:SetPoint("RIGHT", footer, "LEFT", 696, 18)
  closeButton.palette = { idle = LIT, active = LIT,
    hover = { bg = { 0.40, 0.22, 0.72, 1 }, border = { 0.95, 0.80, 0.45, 1 }, text = { 1, 1, 1 } } }
  ns.Skin.PaintButton(closeButton)
  local apply = Button(footer, 110, "Apply", function()
    ns.RefreshAllModules()
    ns.RefreshOptions()
    ns.Print("settings applied.")
  end)
  apply:SetHeight(32)
  apply:SetPoint("RIGHT", closeButton, "LEFT", -10, 0)
  panel.footer, panel.applyButton, panel.closeButton = footer, apply, closeButton

  -- The quill, the books and the "A Better Azeroth" scroll are cut out of
  -- the plate and laid again on top, so the page scrolls BEHIND them rather
  -- than over them. The layer takes no clicks.
  local front = CreateFrame("Frame", nil, panel)
  front:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
  front:SetSize(WIDTH * 448 / 1536, HEIGHT * 416 / 1024)
  front:SetFrameLevel(panel:GetFrameLevel() + 40)
  if front.EnableMouse then front:EnableMouse(false) end
  local props = front:CreateTexture(nil, "ARTWORK")
  props:SetAllPoints()
  props:SetTexture(SKIN .. "corner-props")
  props:SetTexCoord(0, 448 / 512, 0, 416 / 512)
  panel.frontProps = props

  panel.tabs = {}
  panel.tabOrder = {}

  -- Quick Setup first: the things people do most, one click each (the
  -- owner's list, 25 Sept 2026). /fui opens on it.
  if ns.QuickPageSchema then
    AddPage("quick", "Quick Setup", ns.QuickPageSchema())
  end

  -- Roles at the very top of the menu: Heal / Tank / DPS, colour-coded.
  AddNavAction("Heal", ROLE_GREEN, function() OpenRole("healer") end, "healer")
  AddNavAction("Tank", ROLE_ORANGE, function() OpenRole("tank") end, "tank")
  AddNavAction("DPS", ROLE_PURPLE, function() OpenRole("dps") end, "dps")

  -- A module's options as a page: each entry copied and told whose it is.
  -- Every module page gets the same Restore Defaults, top right of the
  -- page's own header (25 Sept 2026 - only XP Bar, the Arrow and Bags had
  -- one), unless the module already has one of its own on a card.
  local function ModuleSchema(module, name)
    local schema = {}
    local hasOwn
    for _, entry in ipairs(module.options) do
      local copy = {}
      for k, v in pairs(entry) do
        copy[k] = v
      end
      copy.moduleName = entry.moduleName or name
      schema[#schema + 1] = copy
      if copy.action and copy.action.label == "Restore Defaults" then hasOwn = true end
    end
    local title = schema[1]
    if title and title.type == "heading" and not hasOwn and type(module.defaults) == "table" then
      title.pageAction = { label = "Restore Defaults", run = function() ns.RestoreModuleDefaults(name) end }
    end
    return schema
  end

  -- Another page's entries as a tab of this one (consolidation, 25 Sept
  -- 2026): Keybinds and the Cooldown Manager under Action Bars, Kick Alerts
  -- under Nameplates. Each keeps its own moduleName, so its settings still
  -- save and refresh where they always did.
  local function AsTab(schema, entries, tab, tabLabel, moduleName)
    for _, entry in ipairs(entries or {}) do
      local copy = {}
      for k, v in pairs(entry) do copy[k] = v end
      copy.tab, copy.tabLabel = tab, tabLabel
      copy.moduleName = copy.moduleName or moduleName
      schema[#schema + 1] = copy
    end
    return schema
  end

  -- The quest helper sits up here with the roles, not down among the
  -- modules: it is the thing a levelling player comes looking for.
  local questHelper = ns.GetModule("QuestForever")
  if questHelper and questHelper.options then
    AddPage("QuestForever", questHelper.title or "QuestForever", ModuleSchema(questHelper, "QuestForever"))
  end

  AddPage("general", "General", CoreSchema())
  AddPage("modules", "Modules", ns.ModulesPageSchema and ns.ModulesPageSchema() or ModulesSchema())
  AddPage("profiles", "Profiles", ns.ProfilesPageSchema and ns.ProfilesPageSchema() or ns.ProfilesSchema())

  -- Modules that brought their own settings get a page each. The frame engine
  -- is the exception: it's reached through the Heal/Tank/DPS buttons above, not
  -- a "Party & Raid Frames" entry.
  ns.ForEachModule(function(module, name)
    -- A module with a page written for it by hand uses that instead of its
    -- list of options (the Cast Bar's, drawn from the owner's mock-up).
    local custom = (name == "CastBar" and ns.CastBarPageSchema)
      or (name == "Quests" and ns.QuestsPageSchema)
      or (name == "Bags" and ns.BagsPageSchema) or nil
    if custom then
      local schema = custom()
      -- Hand-built pages get the same Restore Defaults (Bags has its own).
      if name ~= "Bags" and schema[1] and schema[1].type == "heading" and type(module.defaults) == "table" then
        schema[1].pageAction = { label = "Restore Defaults", run = function() ns.RestoreModuleDefaults(name) end }
      end
      AddPage(name, module.title or name, schema)
    elseif name == "ActionBars" and module.options then
      local schema = ModuleSchema(module, name)
      if ns.KeybindsPageSchema then
        local keybinds = ns.KeybindsPageSchema()
        table.remove(keybinds, 1)   -- its page title: the tab's label says it
        AsTab(schema, keybinds, "keybinds", "Keybinds", "ActionBars")
      end
      local cooldowns = ns.GetModule("Cooldowns")
      if cooldowns and cooldowns.options then
        AsTab(schema, cooldowns.options, "cooldowns", "Cooldown Manager", "Cooldowns")
      end
      AddPage(name, module.title or name, schema)
    elseif name == "Nameplates" and module.options then
      local schema = ModuleSchema(module, name)
      local kicks = ns.GetModule("Kicks")
      if kicks and kicks.options then
        AsTab(schema, kicks.options, "kicks", "Kick alerts", "Kicks")
      end
      AddPage(name, module.title or name, schema)
    elseif module.options and name ~= "Frames" and name ~= "QuestForever"
      and name ~= "Kicks" and name ~= "Cooldowns" then
      AddPage(name, module.title or name, ModuleSchema(module, name))
    end
  end)

  SelectPage(ns.QuickPageSchema and "quick" or "general")
  ns.optionsPanel = panel
end

-- Pages that became part of another (consolidation, 25 Sept 2026): asking
-- for them by their old name opens their new home, on their tab.
-- A module's settings back to how they shipped (the Restore Defaults on
-- every module page). Whether it is on stays as it is. It asks twice: the
-- first click says what it will do, a second within five seconds does it.
local restoreAsked = {}
function ns.RestoreModuleDefaults(name, now)
  local module = ns.GetModule(name)
  local settings = ns.db.modules[name]
  if not (module and type(module.defaults) == "table" and settings) then return false end
  local clock = GetTime and GetTime() or 0
  if not now and not (restoreAsked[name] and clock - restoreAsked[name] <= 5) then
    restoreAsked[name] = clock
    ns.Print(("click Restore Defaults again to put every %s setting back as it shipped."):format(module.title or name))
    return false
  end
  restoreAsked[name] = nil
  local needsReload
  for key, value in pairs(module.defaults) do
    -- A module's own content (ForeverAuras' auras) is not a "setting".
    if key ~= "enabled" and not (module.keepOnRestore and module.keepOnRestore[key]) then
      local fresh = type(value) == "table" and ns.CopyTable(value) or value
      if settings[key] ~= value and type(value) ~= "table" then
        for _, entry in ipairs(module.options or {}) do
          if entry.key == key and entry.reload and not entry.store then needsReload = true end
        end
      end
      settings[key] = fresh
    end
  end
  if module.Refresh then pcall(module.Refresh, module) end
  ns.Print(("%s: every setting back as it shipped."):format(module.title or name))
  if needsReload then ns.RequestReload((module.title or name) .. " defaults") end
  if ns.RefreshOptions then ns.RefreshOptions() end
  return true
end

local PAGE_HOME = {
  Keybinds = { "ActionBars", "keybinds" },
  Cooldowns = { "ActionBars", "cooldowns" },
  Kicks = { "Nameplates", "kicks" },
  info = { "general" },
}
ns.PAGE_HOME = PAGE_HOME

function ns.OpenOptions(category)
  if not panel then
    CreatePanel()
  end
  local tab
  if category and not pages[category] and PAGE_HOME[category] then
    category, tab = PAGE_HOME[category][1], PAGE_HOME[category][2]
  end
  -- No page named: Quick Setup, the front door. A name nobody knows: General.
  if not category then
    category = pages.quick and "quick" or "general"
  end
  category = pages[category] and category or "general"
  if panel:IsShown() and panel.selected == category and not tab then
    panel:Hide()
    return
  end
  SelectPage(category)
  local page = pages[category]
  if tab and page and page.SelectTab and page.tabPages and page.tabPages[tab] then
    page.SelectTab(tab)
  end
  panel:Show()
  ns.RefreshOptions()
end

---------------------------------------------------------------------------
-- A plain text popup, used for profile export and import.
---------------------------------------------------------------------------

local textPopup

function ns.ShowTextPopup(title, text, onAccept)
  if not textPopup then
    textPopup = CreateFrame("Frame", "ForeverUITextPopup", UIParent)
    textPopup:SetSize(520, 260)
    textPopup:SetPoint("CENTER")
    textPopup:SetFrameStrata("FULLSCREEN_DIALOG")
    textPopup:EnableMouse(true)
    textPopup:SetMovable(true)
    textPopup:RegisterForDrag("LeftButton")
    textPopup:SetScript("OnDragStart", textPopup.StartMoving)
    textPopup:SetScript("OnDragStop", textPopup.StopMovingOrSizing)
    table.insert(UISpecialFrames, "ForeverUITextPopup")
    ns.Skin.Panel(textPopup, { color = { 0.06, 0.06, 0.08, 0.96 } })
    textPopup.title = ns.Skin.Header(textPopup, "", function() textPopup:Hide() end).text

    local scroll = CreateFrame("ScrollFrame", "ForeverUITextPopupScroll", textPopup, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -38)
    scroll:SetPoint("BOTTOMRIGHT", -34, 44)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    -- No cap: a whole setup pasted back must arrive whole.
    if edit.SetMaxLetters then edit:SetMaxLetters(0) end
    edit:SetAutoFocus(false)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetWidth(460)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(edit)
    textPopup.edit = edit

    textPopup.accept = Button(textPopup, 120, "", function()
      if textPopup.onAccept then
        textPopup.onAccept(textPopup.edit:GetText())
      end
      textPopup:Hide()
    end)
    textPopup.accept:SetPoint("BOTTOMRIGHT", -16, 14)

    local close = Button(textPopup, 100, "Close", function() textPopup:Hide() end)
    close:SetPoint("BOTTOMLEFT", 16, 14)
  end

  textPopup.title:SetText(title)
  textPopup.edit:SetText(text or "")
  textPopup.edit:HighlightText()
  textPopup.onAccept = onAccept
  textPopup.accept:SetShown(onAccept ~= nil)
  textPopup.accept:SetText(onAccept and "Import" or "")
  textPopup:Show()
  textPopup.edit:SetFocus()
end
