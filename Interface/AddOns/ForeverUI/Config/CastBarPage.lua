local _, ns = ...

-- The Cast Bar page, from the owner's mock-up: size and place on the left,
-- a live preview on the right that casts a pretend spell so the settings can
-- be judged without pulling something, then what the bar shows and how it
-- looks.
--
-- The preview is a real cast bar, built from the same settings as the one in
-- the world -- not a picture of one. Change the height and it changes here.

local W = 636
local COL_W, GAP = 310, 16

local ACCENT = { 0.74, 0.58, 1.00 }
local TEXT   = { 0.92, 0.92, 0.94 }
local DIM    = { 0.70, 0.66, 0.60 }
local EDGE   = { 0.66, 0.50, 0.26, 1 }
local FILL   = { 0.06, 0.05, 0.07, 0.90 }

local page = {}

local function Settings()
  return ns.db.modules.CastBar
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
  local rule = card:CreateTexture(nil, "ARTWORK")
  rule:SetPoint("TOPLEFT", 10, -28)
  rule:SetPoint("TOPRIGHT", -10, -28)
  rule:SetHeight(ns.Media.Pixel())
  rule:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 0.45)
  return card
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------

local function Slider(parent, y, label, key, min, max, step, onChange)
  local text = Text(parent, 12, TEXT)
  text:SetPoint("TOPLEFT", 12, y)
  text:SetText(label)

  local slider = CreateFrame("Slider", nil, parent)
  slider:SetSize(COL_W - 152, 16)
  slider:SetPoint("TOPLEFT", 74, y - 2)
  slider:SetOrientation("HORIZONTAL")
  slider:SetMinMaxValues(min, max)
  slider:SetValueStep(step)
  if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
  ns.Skin.Panel(slider, { color = { 0.10, 0.09, 0.13, 1 }, borderColor = { 0.30, 0.26, 0.36, 1 } })
  local thumb = slider:CreateTexture(nil, "OVERLAY")
  thumb:SetSize(10, 16)
  thumb:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
  slider:SetThumbTexture(thumb)

  local box = CreateFrame("Frame", nil, parent)
  box:SetSize(44, 20)
  box:SetPoint("LEFT", slider, "RIGHT", 8, 0)
  ns.Skin.Panel(box, { color = { 0.09, 0.08, 0.12, 1 }, borderColor = { 0.30, 0.26, 0.36, 1 } })
  box.text = Text(box, 12, ACCENT, "CENTER")
  box.text:SetPoint("CENTER")

  slider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value / step + 0.5) * step
    box.text:SetText(tostring(value))
    if not self.loading then
      Settings()[key] = value
      if onChange then onChange(value) end
      if ns.RefreshCastBarPage then ns.RefreshCastBarPage() end
    end
  end)
  page.controls[key] = function()
    slider.loading = true
    slider:SetValue(Settings()[key] or min)
    box.text:SetText(tostring(Settings()[key] or min))
    slider.loading = nil
  end
  return slider
end

local function Check(parent, x, y, label, key, onChange)
  local box = CreateFrame("CheckButton", nil, parent)
  box:SetSize(18, 18)
  box:SetPoint("TOPLEFT", x, y)
  ns.Skin.Checkbox(box)
  local text = Text(parent, 12, TEXT)
  text:SetPoint("LEFT", box, "RIGHT", 8, 0)
  text:SetText(label)
  box:SetScript("OnClick", function(self)
    Settings()[key] = self:GetChecked() and true or false
    if onChange then onChange() end
    if ns.RefreshCastBarPage then ns.RefreshCastBarPage() end
  end)
  page.controls[key] = function()
    box:SetChecked(Settings()[key] and true or false)
    if box.Paint then box:Paint() end
  end
  return box
end

-- A dropdown of named choices.
local function Choice(parent, y, label, key, choices, onChange)
  local text = Text(parent, 12, TEXT)
  text:SetPoint("TOPLEFT", 12, y)
  text:SetText(label)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(COL_W - 130, 22)
  button:SetPoint("TOPLEFT", 112, y + 3)
  ns.Skin.Button(button, { role = "general" })
  button:SetScript("OnClick", function(self)
    local current = Settings()[key]
    local index = 1
    for i, choice in ipairs(choices) do
      if choice.value == current then index = i end
    end
    local pick = choices[index % #choices + 1]
    Settings()[key] = pick.value
    if onChange then onChange(pick.value) end
    if ns.RefreshCastBarPage then ns.RefreshCastBarPage() end
  end)
  page.controls[key] = function()
    local shown = "?"
    for _, choice in ipairs(choices) do
      if choice.value == Settings()[key] then shown = choice.label end
    end
    button:SetText(shown)
  end
  return button
end

local function Swatch(parent, y, label, key, onChange)
  local text = Text(parent, 12, TEXT)
  text:SetPoint("TOPLEFT", 12, y)
  text:SetText(label)
  local swatch = CreateFrame("Button", nil, parent)
  swatch:SetSize(COL_W - 130, 20)
  swatch:SetPoint("TOPLEFT", 112, y + 2)
  ns.Skin.Panel(swatch, { color = { 0, 0, 0, 1 } })
  local fill = swatch:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("TOPLEFT", 2, -2)
  fill:SetPoint("BOTTOMRIGHT", -2, 2)
  swatch.fill = fill
  swatch:SetScript("OnClick", function()
    local c = Settings()[key] or { 1, 1, 1 }
    local picker = _G.ColorPickerFrame
    if not picker then
      ns.Print("this client has no colour picker.")
      return
    end
    local function Apply(r, g, b)
      Settings()[key] = { r, g, b }
      fill:SetColorTexture(r, g, b, 1)
      if onChange then onChange() end
    end
    local info = {
      r = c[1], g = c[2], b = c[3], hasOpacity = false,
      swatchFunc = function()
        local nr, ng, nb = picker:GetColorRGB()
        if nr then Apply(nr, ng, nb) end
      end,
      cancelFunc = function() Apply(c[1], c[2], c[3]) end,
    }
    if picker.SetupColorPickerAndShow then
      pcall(picker.SetupColorPickerAndShow, picker, info)
    else
      picker.func, picker.cancelFunc, picker.hasOpacity = info.swatchFunc, info.cancelFunc, false
      picker.previousValues = { r = c[1], g = c[2], b = c[3] }
      if picker.SetColorRGB then pcall(picker.SetColorRGB, picker, c[1], c[2], c[3]) end
      picker:Show()
    end
  end)
  page.controls[key] = function()
    local c = Settings()[key] or { 1, 1, 1 }
    fill:SetColorTexture(c[1], c[2], c[3], 1)
  end
  return swatch
end

---------------------------------------------------------------------------
-- The live preview: a real bar, built from the same settings
---------------------------------------------------------------------------

local PREVIEWS = {
  { key = "cast",    label = "A cast",        spell = "Fireball",       icon = 135812, colour = "barColor" },
  { key = "channel", label = "A channel",     spell = "Mind Flay",      icon = 136208, colour = "channelColor" },
  { key = "safe",    label = "Uninterruptible", spell = "Ancient Ward", icon = 136106, colour = "safeColor" },
}

local function PaintPreview()
  local bar, s = page.preview, Settings()
  if not bar then
    return
  end
  local which = PREVIEWS[page.previewIndex or 1]
  local height = math.max(10, math.min(40, s.height or 24))
  local room = (bar:GetParent():GetWidth() or 280) - 24 - (s.showIcon and (height + 6) or 0)
  bar:SetWidth(math.max(80, math.min(room, s.width or 300)))
  bar:SetHeight(height)
  -- Placed by hand rather than centred: the icon hangs off the bar's left,
  -- and a centred bar pushed it outside the card.
  bar:ClearAllPoints()
  bar:SetPoint("LEFT", bar:GetParent(), "LEFT", 12 + (s.showIcon and (height + 6) or 0), 0)
  local texture = s.barTexture
  bar:SetStatusBarTexture((texture and texture ~= "" and ns.Media.TexturePath(texture))
    or ns.Media.StatusBarTexture())
  local c = s[which.colour] or { 0.25, 0.55, 0.85 }
  bar:SetStatusBarColor(c[1], c[2], c[3], 1)
  local bg = s.backgroundColor or { 0, 0, 0, 0.75 }
  ns.Skin.SetPanelColor(bar, { bg[1], bg[2], bg[3], bg[4] or 0.75 })
  local edge = s.borderColor or { 0.22, 0.22, 0.26 }
  ns.Skin.SetBorderColor(bar, { edge[1], edge[2], edge[3], (s.borderStyle or "thin") == "none" and 0 or 1 })
  bar.text:SetText(s.showName ~= false and which.spell or "")
  bar.timer:SetText(s.showTimer and "1.8 / 3.0" or "")
  bar.iconBox:SetShown(s.showIcon and true or false)
  bar.iconBox:SetSize(bar:GetHeight(), bar:GetHeight())
  bar.icon:SetTexture(which.icon)
  bar.spark:SetShown(s.showSpark and true or false)
  bar.latency:SetShown(s.showLatency and true or false)
  bar:SetMinMaxValues(0, 3)
  bar:SetValue(1.8)
  if page.previewLabel then
    page.previewLabel:SetText(which.label)
  end
  for i, tab in ipairs(page.previewTabs or {}) do
    ns.Skin.SetSelected(tab, i == (page.previewIndex or 1))
  end
end

local function BuildPreview(parent, x, y, w)
  local card = Card(parent, x, y, w, 168, "eye", "Live Preview")
  local stage = CreateFrame("Frame", nil, card)
  stage:SetPoint("TOPLEFT", 10, -36)
  stage:SetPoint("TOPRIGHT", -10, -36)
  stage:SetHeight(76)
  ns.Skin.Panel(stage, { color = { 0.04, 0.04, 0.06, 1 }, borderColor = { 0.26, 0.22, 0.34, 1 } })
  local art = stage:CreateTexture(nil, "BACKGROUND", nil, 1)
  art:SetPoint("TOPLEFT", 1, -1)
  art:SetPoint("BOTTOMRIGHT", -1, 1)
  art:SetTexture(ns.MEDIA_PATH .. "skin\\module-preview")
  art:SetAlpha(0.8)

  local bar = CreateFrame("StatusBar", nil, stage)
  ns.Skin.Panel(bar, { color = { 0, 0, 0, 0.75 } })
  bar.text = Text(bar, 11, TEXT)
  bar.text:SetPoint("LEFT", 6, 0)
  bar.timer = Text(bar, 11, TEXT, "RIGHT")
  bar.timer:SetPoint("RIGHT", -6, 0)
  local iconBox = CreateFrame("Frame", nil, bar)
  iconBox:SetPoint("RIGHT", bar, "LEFT", -4, 0)
  ns.Skin.Panel(iconBox, { color = { 0, 0, 0, 1 } })
  bar.icon = iconBox:CreateTexture(nil, "ARTWORK")
  bar.icon:SetPoint("TOPLEFT", 1, -1)
  bar.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  bar.iconBox = iconBox
  local spark = bar:CreateTexture(nil, "OVERLAY")
  spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
  spark:SetBlendMode("ADD")
  spark:SetWidth(18)
  spark:SetPoint("TOP", bar:GetStatusBarTexture(), "TOPRIGHT", 0, 4)
  spark:SetPoint("BOTTOM", bar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, -4)
  bar.spark = spark
  local band = bar:CreateTexture(nil, "ARTWORK", nil, 2)
  band:SetColorTexture(0.85, 0.20, 0.20, 0.45)
  band:SetPoint("TOPRIGHT")
  band:SetPoint("BOTTOMRIGHT")
  band:SetWidth(14)
  bar.latency = band
  page.preview = bar

  page.previewLabel = Text(card, 10, DIM)
  page.previewLabel:SetPoint("TOPLEFT", 12, -118)

  page.previewTabs = {}
  for i, which in ipairs(PREVIEWS) do
    local tab = CreateFrame("Button", nil, card)
    tab:SetSize((w - 28) / #PREVIEWS, 22)
    tab:SetPoint("BOTTOMLEFT", 10 + (i - 1) * ((w - 28) / #PREVIEWS + 2), 10)
    ns.Skin.Button(tab, { role = "general" })
    tab:SetText(which.label)
    tab:SetScript("OnClick", function()
      page.previewIndex = i
      PaintPreview()
    end)
    page.previewTabs[i] = tab
  end
  return 168
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local function Apply()
  local module = ns.GetModule("CastBar")
  if module and module.Refresh then
    module:Refresh()
  end
end

local function Refresh()
  for _, fn in pairs(page.controls or {}) do
    fn()
  end
  PaintPreview()
end
ns.RefreshCastBarPage = Refresh

function ns.CastBarPageSchema()
  return {
    { type = "heading", label = "Cast Bar", subtitle = "Show what's happening. Your way." },
    { type = "custom", bare = true, build = function(parent, x, y)
      page = { controls = {}, previewIndex = 1 }
      local root = CreateFrame("Frame", nil, parent)
      root:SetPoint("TOPLEFT", x, y)
      root:SetSize(W, 520)

      -- Size and place
      local size = Card(root, 0, 0, COL_W, 132, "framemgmt", "Bar Size & Position")
      Slider(size, -40, "Width", "width", 120, 700, 10, Apply)
      Slider(size, -68, "Height", "height", 12, 40, 2, Apply)
      Check(size, 12, -98, "Lock it where it is", "locked", function()
        if ns.SetMoverLocked then ns.SetMoverLocked("castbar", Settings().locked) end
      end)

      -- Live preview
      BuildPreview(root, COL_W + GAP, 0, W - COL_W - GAP)

      -- What it shows
      local show = Card(root, 0, -148, COL_W, 196, "eye", "Display Options")
      Check(show, 12, -40, "The spell's icon", "showIcon", Apply)
      Check(show, 12, -64, "The spell's name", "showName", Apply)
      Check(show, 12, -88, "The cast time (1.8 / 3.0)", "showTimer", Apply)
      Check(show, 12, -112, "The spark at the leading edge", "showSpark", Apply)
      Check(show, 12, -136, "How much is already in flight (latency)", "showLatency", Apply)
      Check(show, 12, -160, "Hide Blizzard's own cast bar", "hideBlizzard", function()
        ns.RequestReload("Hide Blizzard's cast bar")
      end)

      -- How it looks
      local look = Card(root, COL_W + GAP, -180, W - COL_W - GAP, 164, "appearance", "Bar Appearance")
      Choice(look, -40, "Bar texture", "barTexture", (function()
        local list = { { label = "The UI's texture", value = "" } }
        for _, name in ipairs(ns.Media.List("statusbar")) do
          list[#list + 1] = { label = name, value = name }
        end
        return list
      end)(), Apply)
      Swatch(look, -66, "Casting", "barColor", Apply)
      Swatch(look, -92, "Channelling", "channelColor", Apply)
      Swatch(look, -118, "Background", "backgroundColor", Apply)
      Choice(look, -142, "Border", "borderStyle", {
        { label = "None", value = "none" },
        { label = "Thin", value = "thin" },
        { label = "Thick", value = "thick" },
      }, Apply)

      local tip = Text(root, 10, DIM)
      tip:SetPoint("TOPLEFT", 0, -358)
      tip:SetPoint("RIGHT", root, "RIGHT", 0, 0)
      tip:SetText("Drag it where you want with |cff9a6bff/fui move|r. |cff9a6bff/fui test|r casts a pretend spell so you can line it up.")

      page.root = root
      Refresh()
      return 380
    end,
      refresh = function() Refresh() end },
  }
end
