local _, ns = ...

-- XP bar. Blizzard's is a wide strip of framed artwork across the bottom of
-- the screen; this is a thin flat line you can put anywhere and read at a
-- glance. Rested experience shows as a lighter band ahead of the fill.
--
-- Every reading is taken inside a guarded call. Forever can hand addons
-- values it won't let them do arithmetic on, and the queries that say so are
-- not always right, so the sum either works or the bar quietly says nothing.

local module = ns.RegisterModule({
  name = "XPBar",
  title = "XP Bar",
})

module.defaults = {
  width = 420,
  height = 10,
  showText = "hover",   -- always | hover | never
  textSize = 11,        -- the XP text's size
  textAlpha = 1,        -- and how solid it is, 0..1
  showRested = true,
  hideAtMax = true,
}

-- Every setting back to how it shipped.
function module.RestoreDefaults()
  local settings = ns.db.modules.XPBar
  for key, value in pairs(module.defaults) do
    settings[key] = value
  end
  module:Refresh()
  if ns.RefreshOptions then
    ns.RefreshOptions()
  end
end

local function Percent(v)
  return ("%d%%"):format(math.floor((v or 1) * 100 + 0.5))
end

-- Sliders, to the owner's mock-up (23 Sept 2026).
module.options = {
  { type = "heading", label = "XP Bar", subtitle = "Customize your experience." },
  { type = "heading", label = "Settings", icon = "general",
    action = { label = "Restore Defaults", run = function() module.RestoreDefaults() end } },
  { type = "stepper", slider = true, key = "width", label = "Width", desc = "Set the width of the XP bar.",
    min = 120, max = 900, step = 10 },
  { type = "stepper", slider = true, key = "height", label = "Height", desc = "Set the height of the XP bar.",
    min = 4, max = 40, step = 1 },
  { type = "stepper", slider = true, key = "textSize", label = "Text Size", desc = "Set the height of the XP text.",
    min = 8, max = 24, step = 1 },
  { type = "stepper", slider = true, key = "textAlpha", label = "Text Opacity",
    desc = "Adjust the transparency of the XP text.", min = 0.1, max = 1, step = 0.05, format = Percent },
  { type = "cycler", key = "showText", label = "Text Position", desc = "Where to display the XP text.",
    choices = function()
      return {
        { label = "On Hover", value = "hover" },
        { label = "Always", value = "always" },
        { label = "Never", value = "never" },
      }
    end },
  { type = "checkbox", switch = true, key = "showRested", label = "Show rested experience",
    desc = "Display the rested XP overlay." },
  { type = "checkbox", switch = true, key = "hideAtMax", label = "Hide at max level",
    desc = "Automatically hide the XP bar when at maximum level." },
  { type = "checkbox", switch = true, key = "hideXpBar", moduleName = "ActionBars", reload = true,
    label = "Hide Blizzard's XP and reputation bars", desc = "Action Bars does the hiding, so it needs Action Bars on." },
  { type = "note", label = "Drag it with /fui move." },
}

local bar, rested, fill, text

local function Settings()
  return ns.db.modules.XPBar
end

local function MaxLevel()
  if GetMaxPlayerLevel then
    return GetMaxPlayerLevel()
  end
  return MAX_PLAYER_LEVEL or 60
end

-- One guarded reading. Everything that needs a sum happens in here.
local function Read()
  return ns.Secrets.Measure(function()
    local current = UnitXP("player") or 0
    local maximum = UnitXPMax("player") or 0
    local bonus = (GetXPExhaustion and GetXPExhaustion()) or 0
    local percent = maximum > 0 and (current / maximum * 100) or 0
    return {
      current = current,
      maximum = maximum,
      rested = bonus,
      percent = percent,
      restedTo = math.min(maximum, current + bonus),
    }
  end)
end
module.Read = Read

local function Comma(n)
  local out = tostring(math.floor(n))
  local swaps = 1
  while swaps > 0 do
    out, swaps = out:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
  end
  return out
end

local function Describe(data)
  local line = ("%s / %s  %d%%"):format(Comma(data.current), Comma(data.maximum),
    math.floor(data.percent + 0.5))
  if data.rested > 0 then
    line = line .. ("  |cff4dc3ff+%s rested|r"):format(Comma(data.rested))
  end
  return line
end
module.Describe = Describe

local function ApplyText(data)
  local mode = Settings().showText
  if mode == "never" or not data then
    text:SetText("")
    return
  end
  text:SetText(Describe(data))
  text:SetShown(mode == "always" or bar.hovered == true)
end

local function Update()
  if not bar then
    return
  end
  local settings = Settings()
  if settings.hideAtMax and (UnitLevel("player") or 1) >= MaxLevel() then
    bar:Hide()
    return
  end
  bar:Show()

  local ok, data = Read()
  if not ok or not data or data.maximum <= 0 then
    -- Restricted values, or a client that won't say: show an empty rail
    -- rather than an error every time the number changes.
    fill:SetMinMaxValues(0, 1)
    fill:SetValue(0)
    rested:SetValue(0)
    text:SetText("")
    module.lastReadFailed = true
    return
  end
  module.lastReadFailed = false

  fill:SetMinMaxValues(0, data.maximum)
  fill:SetValue(data.current)
  rested:SetMinMaxValues(0, data.maximum)
  rested:SetValue(settings.showRested and data.restedTo or 0)
  ApplyText(data)
  module.last = data
end
module.Update = Update

local function Layout()
  local settings = Settings()
  bar:SetSize(settings.width, settings.height)
  ns.UpdateMoverSize("xp", settings.width, settings.height)
  -- Colour goes on after the texture: setting a status bar's texture clears
  -- its colour, which left the bar rendering plain white.
  fill:SetStatusBarTexture(ns.Media.StatusBarTexture())
  rested:SetStatusBarTexture(ns.Media.StatusBarTexture())
  fill:SetStatusBarColor(ns.Colors.Get("status", "experience"))
  rested:SetStatusBarColor(ns.Colors.Get("status", "experienceRested"))
  -- The UI's font for data text, at the bar's own size and opacity.
  local path, _, outline = ns.Media.Role("dataText")
  text:SetFont(path, settings.textSize or 11, outline or "")
  text:SetAlpha(settings.textAlpha or 1)
end
module.Layout = Layout

local function Build()
  bar = CreateFrame("Frame", "ForeverUIXPBar", UIParent)
  ns.Skin.Panel(bar, { color = { 0, 0, 0, 0.8 }, square = true })
  bar:EnableMouse(true)

  -- Rested underneath, current XP on top of it.
  rested = CreateFrame("StatusBar", nil, bar)
  rested:SetPoint("TOPLEFT", 1, -1)
  rested:SetPoint("BOTTOMRIGHT", -1, 1)

  fill = CreateFrame("StatusBar", nil, rested)
  fill:SetAllPoints(rested)

  text = fill:CreateFontString(nil, "OVERLAY")
  text:SetPoint("CENTER")
  text:SetTextColor(unpack(ns.Colors.ui.text))

  bar:SetScript("OnEnter", function(self)
    self.hovered = true
    Update()
  end)
  bar:SetScript("OnLeave", function(self)
    self.hovered = false
    Update()
  end)

  ns.RegisterMover("xp", "XP bar", bar, { "BOTTOM", "BOTTOM", 0, 10 })
  module.bar, module.fill, module.rested, module.text = bar, fill, rested, text

  local driver = CreateFrame("Frame")
  for _, event in ipairs({
    "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_ENTERING_WORLD",
  }) do
    pcall(driver.RegisterEvent, driver, event)
  end
  driver:SetScript("OnEvent", Update)
  module.driver = driver
end

function module:OnEnable()
  if not bar then
    Build()
  end
  bar:Show()
  Layout()
  Update()
end

function module:OnDisable()
  if bar then
    bar:Hide()
  end
end

function module:Refresh()
  if not bar then
    return
  end
  Layout()
  Update()
end
