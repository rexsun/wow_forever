local _, ns = ...

-- Your own cast bar. A flat bar you can put anywhere: the spell's name on the
-- left, the seconds left and the total on the right, the icon beside it if
-- you want one. Blizzard's is put away.
--
-- Reading and timing the cast is Core/Casting.lua's job; this module only
-- draws the bar and decides where it goes.

local module = ns.RegisterModule({
  name = "CastBar",
  title = "Cast Bar",
})

module.defaults = {
  width = 300,
  height = 40,
  showIcon = true,
  showName = true,
  showTimer = true,
  hideBlizzard = true,
  -- The look. Texture and colours are the bar's own, so a cast bar can be
  -- told apart from a health bar at a glance.
  barTexture = "",              -- "" = whatever the UI's bar texture is
  barColor = { 0.25, 0.55, 0.85 },
  channelColor = { 0.30, 0.70, 0.60 },
  safeColor = { 0.55, 0.55, 0.55 },   -- a cast nobody can interrupt
  backgroundColor = { 0, 0, 0, 0.75 },
  borderColor = { 0.22, 0.22, 0.26 },
  borderStyle = "thin",         -- none | thin | thick
  -- The spark at the leading edge, and the band showing how much of the cast
  -- is already in flight to the server.
  showSpark = false,
  showLatency = false,
  locked = false,
}

module.options = {
  { type = "heading", label = "Cast bar" },
  { type = "stepper", key = "width", label = "Width", min = 120, max = 700, step = 10 },
  { type = "stepper", key = "height", label = "Height", min = 12, max = 40, step = 2 },
  { type = "checkbox", key = "showIcon", label = "Show the spell's icon" },
  { type = "checkbox", key = "showTimer", label = "Show the time" },
  { type = "checkbox", key = "hideBlizzard", label = "Hide Blizzard's cast bar", reload = true },
  { type = "note", label = "Drag it with /fui move; /fui test shows a pretend cast to line it up." },
}

-- Both names Blizzard has used for it.
local BLIZZARD = { "PlayerCastingBarFrame", "CastingBarFrame", "PetCastingBarFrame" }

local bar, iconHolder, driver
local testing = false

local function Settings()
  return ns.db.modules.CastBar
end

local function HideBlizzard()
  if not Settings().hideBlizzard then
    return 0
  end
  local hidden = 0
  for _, name in ipairs(BLIZZARD) do
    if _G[name] and ns.Skin.Conceal(_G[name]) then
      hidden = hidden + 1
    end
  end
  module.hiddenBlizzard = hidden
  return hidden
end

local function Layout()
  local settings = Settings()
  bar:SetSize(settings.width, settings.height)
  ns.UpdateMoverSize("castbar", settings.width, settings.height)
  ns.Media.SetFont(bar.text, "unitName")
  ns.Media.SetFont(bar.timer, "unitHealth")
  bar.timer:SetShown(settings.showTimer)
  bar.text:SetShown(settings.showName ~= false)
  iconHolder:SetSize(settings.height, settings.height)
  iconHolder:SetShown(settings.showIcon)
  module.ApplyLook()
end

-- Texture, colours, border and the two extras. Kept apart from the size so
-- the options page can repaint without moving anything.
function module.ApplyLook()
  if not bar then
    return
  end
  local s = Settings()
  local texture = s.barTexture
  bar:SetStatusBarTexture((texture and texture ~= "" and ns.Media.TexturePath(texture))
    or ns.Media.StatusBarTexture())
  module.PaintBar()

  local bg = s.backgroundColor or { 0, 0, 0, 0.75 }
  ns.Skin.SetPanelColor(bar, { bg[1], bg[2], bg[3], bg[4] or 0.75 })

  local edge = s.borderColor or { 0.22, 0.22, 0.26 }
  local style = s.borderStyle or "thin"
  local alpha = style == "none" and 0 or 1
  ns.Skin.SetBorderColor(bar, { edge[1], edge[2], edge[3], alpha })
  for _, tex in ipairs(bar.borderEdges or {}) do
    local thick = style == "thick" and 2 or ns.Media.Pixel()
    if tex:GetHeight() and tex:GetHeight() <= 2 then tex:SetHeight(thick) end
    if tex:GetWidth() and tex:GetWidth() <= 2 then tex:SetWidth(thick) end
  end

  -- The spark rides the end of the fill; the latency band sits against the
  -- right-hand end, both only while something is casting.
  if not bar.spark then
    local spark = bar:CreateTexture(nil, "OVERLAY")
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetBlendMode("ADD")
    spark:SetWidth(20)
    spark:SetPoint("TOP", bar:GetStatusBarTexture(), "TOPRIGHT", 0, 4)
    spark:SetPoint("BOTTOM", bar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, -4)
    bar.spark = spark
  end
  bar.spark:SetShown(s.showSpark and bar:IsShown() and bar.castInfo ~= nil)

  if not bar.latency then
    local band = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    band:SetColorTexture(0.85, 0.20, 0.20, 0.45)
    band:SetPoint("TOPRIGHT")
    band:SetPoint("BOTTOMRIGHT")
    bar.latency = band
  end
  module.UpdateLatency()
end

-- The bar's colour for what it is showing: a cast, a channel, or one that
-- cannot be interrupted.
function module.PaintBar()
  if not bar then
    return
  end
  local s = Settings()
  local info = bar.castInfo
  local c = s.barColor or { 0.25, 0.55, 0.85 }
  if info then
    -- Can be a secret boolean: tested through the guard, never directly.
    if ns.Secrets.Bool(info.notInterruptible, false) then
      c = s.safeColor or c
    elseif info.channelling then
      c = s.channelColor or c
    end
  end
  bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
end

-- How much of the cast is already gone by the time the server hears about
-- it: drawn as a band against the end of the bar.
function module.UpdateLatency()
  if not bar or not bar.latency then
    return
  end
  local s = Settings()
  if not s.showLatency or not bar.castInfo or not GetNetStats then
    bar.latency:Hide()
    return
  end
  local _, _, _, world = GetNetStats()
  local lag = tonumber(world) or 0
  local info = bar.castInfo
  local span = ns.Secrets.Number(info.endMs) and ns.Secrets.Number(info.startMs)
    and (ns.Secrets.Number(info.endMs) - ns.Secrets.Number(info.startMs)) or nil
  if not span or span <= 0 or lag <= 0 then
    bar.latency:Hide()
    return
  end
  local width = (bar:GetWidth() or 0) * math.min(1, lag / span)
  bar.latency:SetWidth(math.max(1, width))
  bar.latency:Show()
end

local function Build()
  bar = CreateFrame("StatusBar", "ForeverUICastBar", UIParent)
  ns.Skin.Panel(bar, { color = { 0, 0, 0, 0.75 }, square = true })
  bar:SetStatusBarTexture(ns.Media.StatusBarTexture())

  bar.text = bar:CreateFontString(nil, "OVERLAY")
  bar.text:SetPoint("LEFT", 6, 0)
  bar.text:SetPoint("RIGHT", bar, "RIGHT", -70, 0)
  bar.text:SetJustifyH("LEFT")
  bar.text:SetTextColor(unpack(ns.Colors.ui.text))

  bar.timer = bar:CreateFontString(nil, "OVERLAY")
  bar.timer:SetPoint("RIGHT", -6, 0)
  bar.timer:SetJustifyH("RIGHT")
  bar.timer:SetTextColor(unpack(ns.Colors.ui.text))

  -- The icon sits in its own square to the left, so it can be squared and
  -- bordered like everything else.
  iconHolder = CreateFrame("Frame", nil, bar)
  iconHolder:SetPoint("RIGHT", bar, "LEFT", -4, 0)
  ns.Skin.Panel(iconHolder, { color = { 0, 0, 0, 1 }, square = true })
  bar.icon = iconHolder:CreateTexture(nil, "ARTWORK")
  local px = ns.Media.Pixel()
  bar.icon:SetPoint("TOPLEFT", px, -px)
  bar.icon:SetPoint("BOTTOMRIGHT", -px, px)
  bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  bar:SetScript("OnUpdate", function(self)
    if self.castInfo then
      ns.Casting.Tick(self)
    end
  end)
  -- A hidden frame stops ticking, so a cast that vanishes early was hidden
  -- by someone; the trace records who.
  bar:HookScript("OnHide", function(self)
    if self.castInfo then
      ns.Casting.Trace("hidden-while-casting", debugstack and debugstack(2, 6, 0) or "?")
    end
  end)
  bar:Hide()

  ns.RegisterMover("castbar", "Cast bar", bar, { "BOTTOM", "BOTTOM", 0, 300 })
  ns.SetMoverLocked("castbar", Settings().locked)   -- Cast Bar > "Lock it where it is"
  module.bar, module.iconHolder = bar, iconHolder
end

local START = {
  UNIT_SPELLCAST_START = false,
  UNIT_SPELLCAST_DELAYED = false,
  UNIT_SPELLCAST_CHANNEL_START = true,
  UNIT_SPELLCAST_CHANNEL_UPDATE = true,
}
-- true = the stop of a channel, false = the stop of a cast
local STOP = {
  UNIT_SPELLCAST_STOP = false,
  UNIT_SPELLCAST_FAILED = false,
  UNIT_SPELLCAST_INTERRUPTED = false,
  UNIT_SPELLCAST_CHANNEL_STOP = true,
}
-- Watched only so the trace shows them; they change nothing on the bar.
local WATCH = {
  "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_FAILED_QUIET",
  "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

local function OnEvent(_, event, unit, castGUID, spellID)
  if unit ~= "player" or testing then
    return
  end
  ns.Casting.Trace(event, castGUID, spellID, bar:IsShown() and "shown" or "hidden")
  local channelling = START[event]
  if channelling ~= nil then
    local info = ns.Casting.Read("player", channelling, castGUID)
    if info then
      ns.Casting.Begin(bar, info)
      -- The engine paints in the house colours; this bar has its own.
      module.ApplyLook()
    else
      ns.Casting.End(bar)
    end
  elseif STOP[event] ~= nil then
    -- Only for the cast on the bar: a late stop for the one before it, which
    -- arrives after the new cast has started, is not ours to act on.
    ns.Casting.Stop(bar, castGUID, STOP[event])
    if bar.spark then bar.spark:Hide() end
    if bar.latency then bar.latency:Hide() end
  end
end

function module:OnEnable()
  if not bar then
    Build()
  end
  Layout()
  HideBlizzard()
  driver = driver or CreateFrame("Frame")
  for event in pairs(START) do
    pcall(driver.RegisterEvent, driver, event)
  end
  for event in pairs(STOP) do
    pcall(driver.RegisterEvent, driver, event)
  end
  for _, event in ipairs(WATCH) do
    pcall(driver.RegisterEvent, driver, event)
  end
  driver:SetScript("OnEvent", OnEvent)
  module.driver = driver
end

function module:OnDisable()
  if driver then
    driver:UnregisterAllEvents()
  end
  if bar then
    ns.Casting.End(bar)
  end
end

module.needsReload = true -- Blizzard's bar only comes back on a reload

function module:Refresh()
  if ns.SetMoverLocked then ns.SetMoverLocked("castbar", Settings().locked) end
  if bar then
    Layout()
    HideBlizzard()
  end
end

-- A pretend cast, so the bar can be placed without finding something to cast.
function module:SetTestMode(on)
  testing = on and true or false
  if not bar then
    return
  end
  if testing then
    local now = ns.Casting.NowMs()
    ns.Casting.Begin(bar, {
      name = "Lesser Heal", icon = "Interface\\Icons\\Spell_Holy_LesserHeal",
      startMs = now, endMs = now + 2500, channelling = false, notInterruptible = false,
    })
    bar.castInfo.test = true
  else
    ns.Casting.End(bar)
  end
end
