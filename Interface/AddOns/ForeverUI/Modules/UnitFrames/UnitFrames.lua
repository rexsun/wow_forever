local _, ns = ...

-- Player, target, target-of-target, pet and focus frames.
--
-- Each frame is one secure button so clicking targets and right-clicking opens
-- the unit menu; everything drawn on it is plain and updated from events.
-- Frames are built once at login, never during combat, and RegisterUnitWatch
-- shows and hides them as their unit comes and goes - which is the only way to
-- hide a secure frame mid-fight without asking the game's permission.

local module = ns.RegisterModule({
  name = "UnitFrames",
  title = "Unit Frames",
})

local HEALTH_TEXT = {
  { label = "Nothing", value = "none" },
  { label = "Current", value = "current" },
  { label = "Percent", value = "percent" },
  { label = "Current and percent", value = "currentPercent" },
  { label = "Current / max", value = "currentMax" },
  { label = "Missing health", value = "deficit" },
}
-- Mana, rage or energy as words on the power bar (sprutorgel, 1 Oct 2026).
local POWER_TEXT = {
  { label = "Nothing", value = "none" },
  { label = "Current", value = "current" },
  { label = "Percent", value = "percent" },
  { label = "Current and percent", value = "currentPercent" },
  { label = "Current / max", value = "currentMax" },
}
module.POWER_TEXT = POWER_TEXT

-- Each frame: its unit, its label in move mode, and where it starts.
local UNITS = {
  { key = "player", unit = "player", label = "Player", default = { "BOTTOM", "BOTTOM", -230, 240 } },
  { key = "target", unit = "target", label = "Target", default = { "BOTTOM", "BOTTOM", 230, 240 } },
  { key = "targettarget", unit = "targettarget", label = "Target of target", small = true,
    default = { "BOTTOM", "BOTTOM", 400, 240 } },
  { key = "pet", unit = "pet", label = "Pet", small = true, default = { "BOTTOM", "BOTTOM", -400, 240 } },
  { key = "focus", unit = "focus", label = "Focus", small = true,
    default = { "BOTTOM", "BOTTOM", -230, 330 }, needs = "focusUnit" },
}

module.defaults = {
  hideBlizzardFrames = true,
  width = 130,
  height = 44,
  smallWidth = 120,
  smallHeight = 28,
  healthText = "currentPercent",
  classColor = true,
  showPower = true,
  castBars = true,
  castBarHeight = 18,
  castIcon = true,          -- the spell's icon beside the cast bar
  castTime = true,          -- "1.2 / 2.5" on the cast bar
  castLatency = true,       -- your own casts: the lag you can cast ahead of
  frameBackground = true,   -- the dark panel behind each frame (off = transparent)

  -- Text
  showName = true,
  nameAnchor = "left",      -- left | center | right
  nameLength = 0,           -- 0 = the whole name
  nameColor = "white",      -- white | class
  nameSize = 0,             -- 0 = the font's own size
  showLevel = false,        -- "70" (and "+" for elites) before the name
  showHealthText = true,
  healthAnchor = "right",   -- left | center | right
  healthSize = 0,
  powerText = "none",       -- none | current | percent | currentPercent | currentMax
  powerTextAnchor = "center", -- left | center | right, on the power bar
  powerTextSize = 9,        -- the power bar is thin: small text by default

  -- Bars
  barTexture = "",          -- "" = the Appearance page's texture
  healthColorMode = "class",-- class | reaction | green | custom | gradient
  healthCustomColor = { 0.20, 0.62, 0.28 },
  fillDirection = "left",   -- left | right
  powerHeight = 18,         -- percent of the frame's height
  powerPosition = "bottom", -- bottom | top

  -- Background and border
  backgroundStyle = "dark", -- dark | light | transparent | class | custom
  backgroundColor = { 0.08, 0.08, 0.10 },
  backgroundOpacity = 85,   -- percent
  borderStyle = "thin",     -- none | thin | thick
  borderColorMode = "black",-- black | class | custom
  borderColor = { 0, 0, 0 },
  mouseoverHighlight = true,
  lowHealthThreshold = 20,  -- percent; 0 turns the warning off
  lowHealthColor = { 0.85, 0.15, 0.15 },
  powerClassColor = false,  -- power bar in the unit's class colour, not its power type's
  petHappiness = true,      -- hunters: the game's happy / content / unhappy face beside the pet frame

  -- Buffs and debuffs (Auras.lua). Which frames show them is per frame:
  -- target and focus until their tab says otherwise.
  showBuffs = true,
  showDebuffs = true,
  onlyMyDebuffs = false,    -- target, focus, target of target: just the ones you cast
  auraPosition = "above",   -- before 0.4.33: both kinds; now the fallback
  debuffPosition = "above", -- above | below | left | right
  buffPosition = "above",
  auraTextSize = 10,        -- stack counts and seconds left on the icons
  hideBlizzardBuffs = false,-- the game's buff/debuff bar, top right
  showIncoming = true,      -- incoming heals past the end of the health bar
  showShields = true,       -- shields (absorbs) past those
  auraSize = 22,
  smallAuraSize = 18,
  auraTimers = true,        -- seconds left, drawn by the game on each icon
  maxBuffs = 10,
  maxDebuffs = 10,
  units = {},    -- per-frame on/off: units.pet = false
  unitOpts = {}, -- per-frame overrides: unitOpts.target = { width = 160, healthText = "percent" }
}


local frames = {}
local testMode = false
local hiddenParent


-- Blizzard's own portraits and bars. Put away the same way as everything
-- else: under a hidden parent, and off the list of frames the game
-- repositions, or they come straight back.
local BLIZZARD_FRAMES = {
  "PlayerFrame", "TargetFrame", "TargetFrameToT", "PetFrame", "FocusFrame",
  "ComboFrame", "PlayerFrameAlternateManaBar", "TargetFrameSpellBar",
  "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4",
}

local function HideBlizzardFrames()
  hiddenParent = hiddenParent or CreateFrame("Frame")
  hiddenParent:Hide()
  local hidden = {}
  for _, name in ipairs(BLIZZARD_FRAMES) do
    local frame = _G[name]
    if frame then
      if UIPARENT_MANAGED_FRAME_POSITIONS then
        UIPARENT_MANAGED_FRAME_POSITIONS[name] = nil
      end
      -- Protected frames are faded, not re-parented: being blocked taints us
      -- and then our own action buttons stop casting.
      ns.Skin.Conceal(frame, hiddenParent)
      hidden[#hidden + 1] = name
    end
  end
  module.hiddenBlizzard = hidden
  return hidden
end
module.HideBlizzardFrames = HideBlizzardFrames

local function Settings()
  return ns.db.modules.UnitFrames
end

-- One frame's value for `key`: its own override if it has one, else the
-- shared setting. The Player, Target... tabs write overrides; General writes
-- the shared values every frame follows until told otherwise.
local function Opt(key, unitKey, fallback)
  local settings = Settings()
  local own = settings.unitOpts and settings.unitOpts[unitKey]
  if own and own[key] ~= nil then
    return own[key]
  end
  if fallback ~= nil then
    return settings[fallback]
  end
  return settings[key]
end
module.Opt = Opt

function module.FrameSize(info)
  local settings = Settings()
  local w = info.small and settings.smallWidth or settings.width
  local h = info.small and settings.smallHeight or settings.height
  local own = settings.unitOpts and settings.unitOpts[info.key]
  if own then
    w, h = own.width or w, own.height or h
  end
  return w, h
end

function module.UnitEnabled(key)
  local units = Settings().units
  return not (units and units[key] == false)
end

-- Is this state below the low-health line? Health can be secret, so the
-- sum is attempted in a guard; refused, the answer is simply "no".
function module.IsLowHealth(state, threshold)
  if not threshold or threshold <= 0 or state.dead or state.canMeasure == false then
    return false
  end
  local ok, low = ns.Secrets.Measure(function()
    return state.healthMax > 0 and (state.health / state.healthMax * 100) <= threshold
  end)
  return ok and low or false
end

---------------------------------------------------------------------------
-- Reading a unit
---------------------------------------------------------------------------

local function Abbreviate(value)
  if value >= 1000000 then
    return ("%.1fm"):format(value / 1000000)
  elseif value >= 1000 then
    return ("%.1fk"):format(value / 1000)
  end
  return tostring(value)
end
module.Abbreviate = Abbreviate

-- Pure: the tests drive this directly rather than through the game.
function module.HealthText(mode, health, maxHealth)
  maxHealth = math.max(maxHealth or 0, 1)
  local percent = math.floor(health / maxHealth * 100 + 0.5)
  if mode == "none" then
    return ""
  elseif mode == "current" then
    return Abbreviate(health)
  elseif mode == "percent" then
    return ("%d%%"):format(percent)
  elseif mode == "currentMax" then
    return ("%s / %s"):format(Abbreviate(health), Abbreviate(maxHealth))
  elseif mode == "deficit" then
    local missing = maxHealth - health
    return missing > 0 and ("-%s"):format(Abbreviate(missing)) or ""
  end
  return ("%s  %d%%"):format(Abbreviate(health), percent)
end

local function ReadUnit(frame)
  local unit = frame.unit
  if testMode then
    return frame.testState
  end
  if not UnitExists(unit) then
    return nil
  end
  local _, class = UnitClass(unit)
  local state = frame.state
  state.name = UnitName(unit) or "?"
  state.class = class
  -- These may be secret values: store them, never compute with them unless
  -- canMeasure says the client is letting us.
  state.health = UnitHealth(unit)
  state.healthMax = UnitHealthMax(unit)
  state.canMeasure = ns.Secrets.CanMeasureHealth(unit)
  state.dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) or false
  state.power = UnitPower(unit)
  state.powerMax = UnitPowerMax(unit)
  state.powerToken = select(2, UnitPowerType(unit))
  state.canMeasurePower = ns.Secrets.CanMeasurePower(unit, UnitPowerType(unit))
  state.isPlayer = UnitIsPlayer(unit)
  state.reaction = UnitIsFriend and UnitIsFriend("player", unit) and "friendly" or "hostile"
  local okLevel, level = pcall(UnitLevel, unit)
  state.level = okLevel and type(level) == "number" and level or nil
  local okClass, classification = pcall(UnitClassification or function() return nil end, unit)
  classification = okClass and ns.Secrets.String(classification) or nil   -- secret: can't be compared
  state.elite = classification == "elite" or classification == "rareelite" or classification == "worldboss"
  return state
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
--
-- Two halves, shared by the real frames and the live preview on the options
-- page, so the preview can never drift from what the frames actually do:
--
--   module.Style(frame, key)        the look: texture, border, background,
--                                   fonts, where the text sits, fill, power size
--   module.Paint(frame, state, key) the unit: values, colours, the words

local ANCHOR = { left = "LEFT", center = "CENTER", right = "RIGHT" }

-- The health colour a mode asks for. "gradient" needs the percentage, which
-- can be secret: then it falls back to class colour rather than guessing.
local function Gradient(pct)
  if pct >= 0.5 then
    local t = (pct - 0.5) * 2          -- yellow to green
    return 1 - t * 0.8, 0.82 + t * 0.03, 0.15
  end
  local t = pct * 2                    -- red to yellow
  return 0.90, 0.15 + t * 0.67, 0.15
end

local function HealthColor(state, key)
  local settings = Settings()
  if state.dead then
    return ns.Colors.Get("status", "healthDead")
  end
  local mode = Opt("healthColorMode", key)
  if mode == nil then
    mode = settings.classColor and "class" or "green"
  end
  if mode == "custom" then
    local c = settings.healthCustomColor or { 0.2, 0.62, 0.28 }
    return c[1], c[2], c[3]
  elseif mode == "gradient" and state.canMeasure ~= false then
    local ok, pct = ns.Secrets.Measure(function()
      return state.healthMax > 0 and state.health / state.healthMax or nil
    end)
    if ok and pct then
      return Gradient(math.max(0, math.min(1, pct)))
    end
    -- refused: fall through to class colour below
  elseif mode == "reaction" then
    if state.isPlayer then
      return ns.Colors.Get("reaction", state.reaction == "hostile" and "hostile" or "friendly")
    end
    return ns.Colors.Get("reaction", state.reaction or "hostile")
  elseif mode == "green" then
    if state.isPlayer then
      return ns.Colors.Get("status", "health")
    end
    return ns.Colors.Get("reaction", state.reaction or "hostile")
  end
  -- class (and the gradient's fallback): players by class, others by reaction
  if state.isPlayer and state.class then
    return ns.Colors.Class(state.class, true)   -- painted, never calculated with
  end
  return ns.Colors.Get("reaction", state.reaction or "hostile")
end
module.HealthColor = HealthColor

-- Trim a name to n characters without cutting a multi-byte one in half.
function module.TrimName(name, n)
  -- A secret name can be shown but not cut: shown whole.
  if not n or n <= 0 or not ns.Secrets.String(name) then
    return name
  end
  local out, count = {}, 0
  for char in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    count = count + 1
    if count > n then
      return table.concat(out)
    end
    out[#out + 1] = char
  end
  return name
end

-- The parts every unit frame has, real or pretend.
function module.BuildParts(frame)
  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetAllPoints()
  frame.edges = {}
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    frame.edges[side] = frame:CreateTexture(nil, "BORDER")
  end
  -- The HIGHLIGHT layer shows by itself while the mouse is over a button.
  frame.hl = frame:CreateTexture(nil, "HIGHLIGHT")
  frame.hl:SetAllPoints()
  frame.hl:SetColorTexture(1, 1, 1, 0.12)
  frame.health = CreateFrame("StatusBar", nil, frame)
  frame.power = CreateFrame("StatusBar", nil, frame)
  frame.name = frame.health:CreateFontString(nil, "OVERLAY")
  frame.healthText = frame.health:CreateFontString(nil, "OVERLAY")
  -- The power text sits on a layer of its own above both bars: on a thin
  -- power bar the words stand taller than the bar, and must not be drawn
  -- under the health bar beside it.
  frame.powerTextLayer = CreateFrame("Frame", nil, frame)
  frame.powerTextLayer:SetAllPoints(frame.power)
  frame.powerText = frame.powerTextLayer:CreateFontString(nil, "OVERLAY")
  -- The raid mark, over the top edge in the middle, as Blizzard's frames do.
  frame.raidMark = frame.health:CreateTexture(nil, "OVERLAY", nil, 7)
  frame.raidMark:SetSize(20, 20)
  frame.raidMark:SetPoint("CENTER", frame, "TOP", 0, 0)
  frame.raidMark:Hide()
  -- Rounded corners (General > Appearance > Corners, "Round unit frames"):
  -- the frame's own fill and edges take the shape; Style keeps the bars and
  -- the hover tint clear of the curve, and re-runs when the corners change.
  frame.borderEdges = frame.edges
  if ns.Skin and ns.Skin.Roundable then
    ns.Skin.Roundable(frame, { group = "roundUnitFrames", onShape = function(f)
      if f.fuiStyleKey and not f.fuiStyling then module.Style(f, f.fuiStyleKey) end
    end })
  end
end

local function SetFontSize(fs, role, size)
  local path, base, outline = ns.Media.Role(role)
  fs:SetFont(path, (size and size > 0) and size or base, outline or "")
end

function module.BarTexture()
  local name = Settings().barTexture
  if name and name ~= "" then
    return ns.Media.TexturePath(name)
  end
  return ns.Media.StatusBarTexture()
end

function module.Style(frame, key)
  local settings = Settings()
  local w, h = frame:GetWidth(), frame:GetHeight()
  frame.fuiStyleKey = key
  frame.fuiStyling = true

  -- Border: none, a 1-pixel line, or 2.
  local t = ({ none = 0, thin = 1, thick = 2 })[settings.borderStyle or "thin"] or 1
  local e = frame.edges
  for side, tex in pairs(e) do
    tex:ClearAllPoints()
    tex:SetShown(t > 0)
    if side == "TOP" or side == "BOTTOM" then
      tex:SetPoint(side .. "LEFT"); tex:SetPoint(side .. "RIGHT"); tex:SetHeight(math.max(t, 1))
    else
      tex:SetPoint("TOP" .. side); tex:SetPoint("BOTTOM" .. side); tex:SetWidth(math.max(t, 1))
    end
  end
  local inset = math.max(t, 1)
  -- Rounded: the rim is the border's thickness, and the bars sit in from
  -- the corners far enough to stay inside the curve.
  frame.fuiEdgeWidth = t > 0 and t or nil
  local radius = ns.Skin and ns.Skin.EffectiveRadius and ns.Skin.EffectiveRadius(frame) or 0
  inset = inset + (ns.Skin and ns.Skin.CornerClearance and ns.Skin.CornerClearance(radius) or 0)
  frame.hl:ClearAllPoints()
  frame.hl:SetPoint("TOPLEFT", frame, "TOPLEFT", radius > 0 and inset or 0, radius > 0 and -inset or 0)
  frame.hl:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", radius > 0 and -inset or 0, radius > 0 and inset or 0)

  -- Power bar: its share of the height, along the bottom or the top.
  local powerH = math.max(2, math.floor(h * (settings.powerHeight or 18) / 100))
  frame.power:ClearAllPoints()
  frame.health:ClearAllPoints()
  local showPower = Opt("showPower", key) and true or false
  frame.powerWanted = showPower
  if settings.powerPosition == "top" then
    frame.power:SetPoint("TOPLEFT", inset, -inset)
    frame.power:SetPoint("TOPRIGHT", -inset, -inset)
    frame.health:SetPoint("TOPLEFT", inset, -(inset + (showPower and powerH or 0)))
    frame.health:SetPoint("BOTTOMRIGHT", -inset, inset)
  else
    frame.power:SetPoint("BOTTOMLEFT", inset, inset)
    frame.power:SetPoint("BOTTOMRIGHT", -inset, inset)
    frame.health:SetPoint("TOPLEFT", inset, -inset)
    frame.health:SetPoint("BOTTOMRIGHT", -inset, inset + (showPower and powerH or 0))
  end
  frame.power:SetHeight(powerH)

  local texture = module.BarTexture()
  frame.health:SetStatusBarTexture(texture)
  frame.power:SetStatusBarTexture(texture)
  local reverse = settings.fillDirection == "right"
  if frame.health.SetReverseFill then frame.health:SetReverseFill(reverse) end
  if frame.power.SetReverseFill then frame.power:SetReverseFill(reverse) end

  -- Text: which fonts, what size, where. Name on the top line at its
  -- anchor; health text on the same line at its own anchor, or dropped to
  -- the bottom line when both want the same spot.
  SetFontSize(frame.name, "unitName", Opt("nameSize", key))
  SetFontSize(frame.healthText, "unitHealth", Opt("healthSize", key))
  local nameAt = ANCHOR[Opt("nameAnchor", key) or "left"] or "LEFT"
  local healthAt = ANCHOR[Opt("healthAnchor", key) or "right"] or "RIGHT"
  local pad = { LEFT = 4, CENTER = 0, RIGHT = -4 }
  frame.name:ClearAllPoints()
  frame.healthText:ClearAllPoints()
  local twoLines = h >= 30
  if twoLines then
    frame.name:SetPoint("TOP" .. (nameAt == "CENTER" and "" or nameAt), frame.health, "TOP" .. (nameAt == "CENTER" and "" or nameAt), pad[nameAt], -3)
  else
    frame.name:SetPoint(nameAt, frame.health, nameAt, pad[nameAt], 0)
  end
  if healthAt == nameAt and twoLines then
    local p = "BOTTOM" .. (healthAt == "CENTER" and "" or healthAt)
    frame.healthText:SetPoint(p, frame.health, p, pad[healthAt], 3)
  elseif twoLines then
    local p = "TOP" .. (healthAt == "CENTER" and "" or healthAt)
    frame.healthText:SetPoint(p, frame.health, p, pad[healthAt], -3)
  else
    frame.healthText:SetPoint(healthAt, frame.health, healthAt, pad[healthAt], 0)
  end
  frame.name:SetJustifyH(nameAt)
  frame.healthText:SetJustifyH(healthAt)
  -- Power text: on the power bar, at its own anchor.
  if frame.powerText then
    if frame.powerTextLayer.SetFrameLevel and frame.health.GetFrameLevel then
      frame.powerTextLayer:SetFrameLevel(math.max(frame.health:GetFrameLevel() or 0, frame.power:GetFrameLevel() or 0) + 2)
    end
    SetFontSize(frame.powerText, "unitHealth", Opt("powerTextSize", key))
    local powerAt = ANCHOR[Opt("powerTextAnchor", key) or "center"] or "CENTER"
    frame.powerText:ClearAllPoints()
    frame.powerText:SetPoint(powerAt, frame.power, powerAt, pad[powerAt], 0)
    frame.powerText:SetJustifyH(powerAt)
  end
  frame.name:SetShown(Opt("showName", key) ~= false)
  frame.healthText:SetShown(Opt("showHealthText", key) ~= false)
  frame.hl:SetShown(settings.mouseoverHighlight ~= false)
  frame.styledW = w
  -- The edges were just laid out full length: shorten them to the curve.
  if ns.Skin and ns.Skin.ShapePanel then ns.Skin.ShapePanel(frame) end
  frame.fuiStyling = nil
end

-- Background and border colours depend on the unit (class tint), so they
-- are set with the rest of the paint.
local function PaintChrome(frame, state)
  local settings = Settings()
  local style = settings.backgroundStyle or "dark"
  if settings.frameBackground == false then
    style = "transparent"
  end
  local alpha = (settings.backgroundOpacity or 85) / 100
  if style == "transparent" then
    frame.bg:SetColorTexture(0, 0, 0, 0)
  elseif style == "light" then
    frame.bg:SetColorTexture(0.35, 0.35, 0.38, alpha)
  elseif style == "class" and state and state.class then
    local r, g, b = ns.Colors.Class(state.class)
    frame.bg:SetColorTexture(r * 0.25, g * 0.25, b * 0.25, alpha)
  elseif style == "custom" then
    local c = settings.backgroundColor or { 0.08, 0.08, 0.10 }
    frame.bg:SetColorTexture(c[1], c[2], c[3], alpha)
  else
    frame.bg:SetColorTexture(0.08, 0.08, 0.10, alpha)
  end
  local r, g, b = 0, 0, 0
  if settings.borderColorMode == "class" and state and state.class then
    r, g, b = ns.Colors.Class(state.class, true)
  elseif settings.borderColorMode == "class" and state then
    r, g, b = HealthColor(state, frame.info and frame.info.key)
  elseif settings.borderColorMode == "custom" then
    local c = settings.borderColor or { 0, 0, 0 }
    r, g, b = c[1], c[2], c[3]
  end
  for _, tex in pairs(frame.edges) do
    tex:SetColorTexture(r, g, b, 1)
  end
  if ns.Skin and ns.Skin.SetRimColor then ns.Skin.SetRimColor(frame, r, g, b, 1) end
end

---------------------------------------------------------------------------
-- Health you are not allowed to read
---------------------------------------------------------------------------
--
-- On Forever a unit's health is a secret: the game will show it but not
-- let an addon do sums with it. So on a real frame the number, the gradient
-- and the low-health warning are all handed to the game to work out -- the
-- same way the party grids do it -- rather than computed here. The preview
-- on the options page has plain numbers and takes the ordinary path.

local function Engine()
  return ns.Frames and ns.Frames.Secrets
end

local function PercentCurve()
  local engine = Engine()
  return engine and engine.PercentCurve and engine.PercentCurve()
end

-- The words, for a unit whose health is secret. False if this client can't.
function module.SecretHealthText(fs, unit, mode)
  if mode == "none" then
    fs:SetText("")
    return true
  end
  return pcall(function()
    local curve = PercentCurve()
    local pct = UnitHealthPercent and (curve and UnitHealthPercent(unit, true, curve) or UnitHealthPercent(unit))
    if mode == "percent" and pct then
      fs:SetFormattedText("%.0f%%", pct)
    elseif mode == "current" then
      fs:SetText(UnitHealth(unit))
    elseif mode == "currentMax" then
      fs:SetFormattedText("%s / %s", UnitHealth(unit), UnitHealthMax(unit))
    elseif mode == "deficit" and C_StringUtil and C_StringUtil.TruncateWhenZero and UnitHealthMissing then
      fs:SetText(C_StringUtil.TruncateWhenZero(UnitHealthMissing(unit)))
    elseif pct then
      fs:SetFormattedText("%s  %.0f%%", UnitHealth(unit), pct)
    else
      error("no way to show health on this client")
    end
  end)
end

-- The same for power: the game draws the number it won't let us read.
function module.SecretPowerText(fs, unit, mode)
  if mode == "none" then
    fs:SetText("")
    return true
  end
  return pcall(function()
    local curve = PercentCurve()
    local pct = UnitPowerPercent and (curve and UnitPowerPercent(unit, nil, false, curve) or UnitPowerPercent(unit))
    if mode == "percent" and pct then
      fs:SetFormattedText("%.0f%%", pct)
    elseif mode == "current" then
      fs:SetText(UnitPower(unit))
    elseif mode == "currentMax" then
      fs:SetFormattedText("%s / %s", UnitPower(unit), UnitPowerMax(unit))
    elseif pct then
      fs:SetFormattedText("%s  %.0f%%", UnitPower(unit), pct)
    else
      error("no way to show power on this client")
    end
  end)
end

-- Power as words. Pure, like HealthText: the same formats, without the
-- "missing" one, which nobody reads off a mana bar.
function module.PowerText(mode, power, maxPower)
  if mode == nil or mode == "none" or mode == "deficit" then
    return ""
  end
  return module.HealthText(mode, power, maxPower)
end

-- A colour curve that is `base` above the threshold and `low` at or below
-- it, built once per combination and kept.
local stepCurves = {}
local function StepCurve(threshold, low, base)
  if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then
    return nil
  end
  local key = ("%d:%.2f,%.2f,%.2f:%.2f,%.2f,%.2f"):format(threshold, low[1], low[2], low[3], base[1], base[2], base[3])
  if stepCurves[key] ~= nil then
    return stepCurves[key] or nil
  end
  local ok, curve = pcall(function()
    local c = C_CurveUtil.CreateColorCurve()
    local t = threshold / 100
    c:AddPoint(0, CreateColor(low[1], low[2], low[3], 1))
    c:AddPoint(t, CreateColor(low[1], low[2], low[3], 1))
    c:AddPoint(math.min(1, t + 0.001), CreateColor(base[1], base[2], base[3], 1))
    c:AddPoint(1, CreateColor(base[1], base[2], base[3], 1))
    return c
  end)
  stepCurves[key] = ok and curve or false
  return ok and curve or nil
end

-- Health you can't read: let the game pick the colour from a curve.
local function PaintSecretHealthColor(frame, state, key)
  local settings = Settings()
  local unit = frame.unit
  if state.dead or not unit or not UnitHealthPercent then
    return false
  end
  local mode = Opt("healthColorMode", key)
  return pcall(function()
    local curve
    if mode == "gradient" then
      local engine = Engine()
      curve = engine and engine.HealthColorCurve and engine.HealthColorCurve()
    elseif (settings.lowHealthThreshold or 0) > 0 then
      local r, g, b = HealthColor(state, key)
      curve = StepCurve(settings.lowHealthThreshold, settings.lowHealthColor or { 0.85, 0.15, 0.15 }, { r, g, b })
    end
    if not curve then
      error("no curve")
    end
    frame.health:SetStatusBarColor(UnitHealthPercent(unit, true, curve):GetRGB())
  end)
end

function module.Paint(frame, state, key)
  local settings = Settings()
  PaintChrome(frame, state)
  -- The bar takes the values as they come, secret or not.
  ns.Secrets.SetBar(frame.health, state.health, state.healthMax)
  local readable = state.canMeasure ~= false and ns.Secrets.Measure(function()
    return state.health / math.max(state.healthMax, 1)
  end)
  if readable and module.IsLowHealth(state, settings.lowHealthThreshold) then
    local c = settings.lowHealthColor or { 0.85, 0.15, 0.15 }
    frame.health:SetStatusBarColor(c[1], c[2], c[3])
  elseif readable or not PaintSecretHealthColor(frame, state, key) then
    frame.health:SetStatusBarColor(HealthColor(state, key))
  end

  local name = module.TrimName(state.name, Opt("nameLength", key))
  if Opt("showLevel", key) and state.level then
    local level = state.level == -1 and "??" or tostring(state.level)
    name = ("%s%s %s"):format(level, state.elite and "+" or "", name or "")
  end
  frame.name:SetText(name)
  if Opt("nameColor", key) == "class" and state.class then
    frame.name:SetTextColor(ns.Colors.Class(state.class, true))
  else
    frame.name:SetTextColor(1, 1, 1)
  end

  -- Health text. Current health can be secret even when the question about
  -- max health says otherwise, so the sum is attempted inside a protected
  -- call, and a frame that fails once stops trying.
  local mode = Opt("healthText", key)
  if state.canMeasure ~= false and not frame.measureFailed then
    local ok, text = pcall(module.HealthText, mode, state.health, state.healthMax)
    if ok then
      frame.healthText:SetText(text)
    else
      frame.measureFailed = true
    end
  end
  if state.canMeasure == false or frame.measureFailed then
    -- Secret: the game draws the number it won't let us read.
    if not (frame.unit and module.SecretHealthText(frame.healthText, frame.unit, mode)) then
      frame.healthText:SetText("")
    end
  end

  -- "has any power at all" is a comparison, so it goes through the same guard.
  local hasPower = true
  if state.canMeasurePower ~= false then
    local ok, result = ns.Secrets.Measure(function() return state.powerMax > 0 end)
    hasPower = not ok or result
  end
  local showPower = frame.powerWanted and state.powerMax ~= nil and hasPower
  frame.power:SetShown(showPower and true or false)
  if showPower then
    ns.Secrets.SetBar(frame.power, state.power, state.powerMax)
    if settings.powerClassColor and state.isPlayer and state.class then
      frame.power:SetStatusBarColor(ns.Colors.Class(state.class, true))
    else
      frame.power:SetStatusBarColor(ns.Colors.Power(state.powerToken))
    end
  end

  -- Power text, guarded the same way as the health text.
  if frame.powerText then
    local powerMode = Opt("powerText", key) or "none"
    local wantText = showPower and powerMode ~= "none"
    frame.powerText:SetShown(wantText and true or false)
    if wantText then
      local done = false
      if state.canMeasurePower ~= false and not frame.powerMeasureFailed then
        local ok, text = pcall(module.PowerText, powerMode, state.power, state.powerMax)
        if ok then
          frame.powerText:SetText(text)
          done = true
        else
          frame.powerMeasureFailed = true
        end
      end
      if not done and not (frame.unit and module.SecretPowerText(frame.powerText, frame.unit, powerMode)) then
        frame.powerText:SetText("")
      end
    end
  end
end

function module.Render(frame)
  local state = ReadUnit(frame)
  if not state then
    if module.RenderPrediction then module.RenderPrediction(frame, nil) end
    frame.health:SetValue(0)
    frame.name:SetText("")
    frame.healthText:SetText("")
    if frame.powerText then frame.powerText:SetText("") end
    return
  end
  if frame.styledW ~= frame:GetWidth() then
    module.Style(frame, frame.info.key)
  end
  module.Paint(frame, state, frame.info.key)
  if module.RenderPrediction then module.RenderPrediction(frame, state) end
  if frame.raidMark then ns.Secrets.PaintRaidMark(frame.raidMark, frame.unit) end
end

---------------------------------------------------------------------------
-- Cast bars
---------------------------------------------------------------------------

local function StopCast(frame, castGUID, channelStop)
  if castGUID == nil and channelStop == nil then
    ns.Casting.End(frame.cast)   -- switching off, or the unit went away
  else
    ns.Casting.Stop(frame.cast, castGUID, channelStop)
  end
end

-- Everything that reads or times the cast lives in Core/Casting.lua, where
-- it is kept clear of arithmetic on secret values.
-- Your own casts: how much of the bar's end is only lag, so you can start
-- the next cast there. World latency against the cast's length, in a guard
-- because a cast's times can be secret.
local function ShowLatency(frame, info)
  local zone = frame.cast.latency
  if not zone then
    return
  end
  zone:Hide()
  if frame.unit ~= "player" or not Settings().castLatency or info.channelling or not GetNetStats then
    return
  end
  local world = select(4, GetNetStats()) or 0
  local ok, fraction = ns.Secrets.Measure(function()
    local total = info.endMs - info.startMs
    return total > 0 and math.min(1, world / total) or 0
  end)
  if ok and fraction and fraction > 0 then
    zone:SetWidth(math.max(1, frame.cast:GetWidth() * fraction))
    zone:Show()
  end
end
module.ShowLatency = ShowLatency

local function StartCast(frame, channelling, castGUID)
  if not Opt("castBars", frame.info.key) then
    StopCast(frame) -- switching them off mid-cast should clear what's on screen
    return
  end
  local info = ns.Casting.Read(frame.unit, channelling, castGUID)
  if not info then
    StopCast(frame)
    return
  end
  ns.Casting.Begin(frame.cast, info)
  local settings = Settings()
  frame.cast.icon:SetShown(settings.castIcon ~= false)
  frame.cast.timer:SetShown(settings.castTime ~= false)
  ShowLatency(frame, info)
end

local function CastOnUpdate(cast)
  if cast.castInfo then
    ns.Casting.Tick(cast)
  end
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

-- Hunters: how the pet feels (Altiokis, 1 Oct 2026: "How do I see the pet
-- happiness bar"). Blizzard's pet frame shows it, and that frame is put away
-- with the rest, so the face went with it. The game's own happiness template
-- does the work here -- its icon, its events, its tooltip (mood, damage,
-- loyalty, diet) -- hung beside our pet frame. It shows only for a hunter's
-- pet; a warlock's demon has no happiness to show.
function module.BuildHappiness(frame)
  if frame.happiness or not (C_PetInfo and C_PetInfo.GetPetHappiness) then
    return frame.happiness
  end
  local ok, face = pcall(CreateFrame, "Frame", nil, frame, "PetFrameHappinessTemplate")
  if not ok or not face then
    return nil
  end
  face:SetSize(20, 20)
  face:SetPoint("LEFT", frame, "RIGHT", 3, 0)
  frame.happiness = face
  module.ApplyHappiness(frame)
  return face
end

function module.ApplyHappiness(frame)
  local face = frame and frame.happiness
  if not face then return end
  if Settings().petHappiness == false then
    face:UnregisterAllEvents()
    face:Hide()
    return
  end
  face:RegisterEvent("UNIT_HAPPINESS")
  face:RegisterEvent("UNIT_PET")
  if face.UpdateHappiness then pcall(face.UpdateHappiness, face) end
end

local function BuildFrame(info)
  local settings = Settings()
  local width, height = module.FrameSize(info)

  local frame = CreateFrame("Button", "ForeverUI" .. info.key, UIParent, "SecureUnitButtonTemplate")
  frame:SetSize(width, height)
  frame:SetAttribute("unit", info.unit)
  frame:SetAttribute("*type1", "target")
  frame:SetAttribute("*type2", "togglemenu")
  frame:RegisterForClicks("AnyUp")
  frame.unit, frame.info = info.unit, info
  frame.state = {}

  module.BuildParts(frame)

  -- Cast bar hangs below its frame and moves with it.
  local cast = CreateFrame("StatusBar", nil, frame)
  cast:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
  cast:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -2)
  cast:SetHeight(settings.castBarHeight)
  cast:Hide()
  cast.bg = cast:CreateTexture(nil, "BACKGROUND")
  cast.bg:SetAllPoints()
  cast.bg:SetColorTexture(ns.Colors.Get("ui", "backdrop"))
  cast.icon = cast:CreateTexture(nil, "ARTWORK")
  cast.icon:SetPoint("RIGHT", cast, "LEFT", -2, 0)
  cast.icon:SetSize(settings.castBarHeight, settings.castBarHeight)
  cast.text = cast:CreateFontString(nil, "OVERLAY")
  cast.text:SetPoint("LEFT", 4, 0)
  ns.Media.SetFont(cast.text, "unitName")
  cast.timer = cast:CreateFontString(nil, "OVERLAY")
  cast.timer:SetPoint("RIGHT", -4, 0)
  ns.Media.SetFont(cast.timer, "unitHealth")
  cast.latency = cast:CreateTexture(nil, "OVERLAY")
  cast.latency:SetPoint("TOPRIGHT")
  cast.latency:SetPoint("BOTTOMRIGHT")
  cast.latency:SetColorTexture(0.85, 0.15, 0.15, 0.55)
  cast.latency:Hide()
  cast:SetScript("OnUpdate", CastOnUpdate)
  frame.cast = cast

  RegisterUnitWatch(frame)
  ns.RegisterMover(info.key, info.label .. " frame", frame, info.default)
  frames[info.key] = frame
  module.Style(frame, info.key)
  module.BuildAuras(frame)
  if info.key == "pet" then module.BuildHappiness(frame) end
  return frame
end

local function ApplySize(frame)
  local settings = Settings()
  local info = frame.info
  local width, height = module.FrameSize(info)
  frame:SetSize(width, height)
  module.Style(frame, info.key)
  frame.cast:SetHeight(settings.castBarHeight)
  frame.cast.icon:SetSize(settings.castBarHeight, settings.castBarHeight)
  ns.UpdateMoverSize(info.key, width, height)
  module.BuildAuras(frame)
  module.ApplyAuras(frame)
end

-- A frame switched off on its tab stops watching its unit and hides; on
-- again, it goes back to showing whenever its unit exists. Out of combat
-- only: these are secure frames.
local function ApplyEnabled(frame)
  if testMode then
    return
  end
  if module.UnitEnabled(frame.info.key) then
    RegisterUnitWatch(frame)
  else
    UnregisterUnitWatch(frame)
    frame:Hide()
  end
end
module.ApplyEnabled = ApplyEnabled

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local UNIT_EVENTS = {
  UNIT_HEALTH = true, UNIT_MAXHEALTH = true,
  UNIT_POWER_UPDATE = true, UNIT_MAXPOWER = true, UNIT_DISPLAYPOWER = true,
  UNIT_NAME_UPDATE = true, UNIT_FLAGS = true,
}

local CAST_START = { UNIT_SPELLCAST_START = false, UNIT_SPELLCAST_CHANNEL_START = true }
-- true = the stop of a channel, false = the stop of a cast
local CAST_STOP = {
  UNIT_SPELLCAST_STOP = false, UNIT_SPELLCAST_FAILED = false,
  UNIT_SPELLCAST_INTERRUPTED = false, UNIT_SPELLCAST_CHANNEL_STOP = true,
}

local function RenderAll()
  for _, frame in pairs(frames) do
    module.Render(frame)
  end
end

-- Which frames' auras belong to someone new after each of these.
local AURA_OWNERS = {
  PLAYER_TARGET_CHANGED = { "target", "targettarget" },
  PLAYER_FOCUS_CHANGED = { "focus" },
  UNIT_PET = { "pet" },
}
local function NewUnitAuras(keys)
  for _, key in ipairs(keys) do
    if frames[key] then module.UpdateAuras(frames[key]) end
  end
end
module.RenderAll = RenderAll

local watcher

function module:OnInit()
  -- 0.4.29-0.4.32 had one "Where they go" for both kinds: someone who chose
  -- "below" keeps it for both.
  local s = Settings()
  if s and not s.aurasSplit then
    if s.auraPosition == "below" then
      s.debuffPosition, s.buffPosition = "below", "below"
    end
    s.aurasSplit = true
  end
  watcher = CreateFrame("Frame")
  watcher:SetScript("OnEvent", function(_, event, unit, castGUID)
    if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" or event == "UNIT_PET"
      or event == "RAID_TARGET_UPDATE" then
      RenderAll()
      if AURA_OWNERS[event] then NewUnitAuras(AURA_OWNERS[event]) end
      return
    end
    if event == "UNIT_TARGET" then
      if unit == "target" then NewUnitAuras({ "targettarget" }) end
      return
    end
    if UNIT_EVENTS[event] then
      for _, frame in pairs(frames) do
        if frame.unit == unit then
          module.Render(frame)
        end
      end
      return
    end
    local channelling = CAST_START[event]
    if channelling ~= nil then
      for _, frame in pairs(frames) do
        if frame.unit == unit then
          StartCast(frame, channelling, castGUID)
        end
      end
    elseif CAST_STOP[event] ~= nil then
      for _, frame in pairs(frames) do
        if frame.unit == unit then
          StopCast(frame, castGUID, CAST_STOP[event])
        end
      end
    end
  end)
  module.watcher = watcher
end

function module:OnEnable()
  ns.WhenOutOfCombat(function()
    for _, info in ipairs(UNITS) do
      if (not info.needs or ns.Compat.HasFeature(info.needs)) and not frames[info.key] then
        BuildFrame(info)
      end
    end
    for _, frame in pairs(frames) do
      frame:Show()
      ApplySize(frame)
      ApplyEnabled(frame)
    end
    if ns.db.modules.UnitFrames.hideBlizzardFrames then
      HideBlizzardFrames()
    end
    if module.ApplyBlizzardBuffs then module.ApplyBlizzardBuffs() end
    RenderAll()
  end)

  watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
  watcher:RegisterEvent("PLAYER_FOCUS_CHANGED")
  watcher:RegisterEvent("UNIT_PET")
  pcall(watcher.RegisterEvent, watcher, "RAID_TARGET_UPDATE")
  pcall(watcher.RegisterEvent, watcher, "UNIT_TARGET")
  -- Incoming heals and shields (Prediction.lua); either may not exist here.
  for _, event in ipairs({ "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED" }) do
    if pcall(watcher.RegisterEvent, watcher, event) then UNIT_EVENTS[event] = true end
  end
  for event in pairs(UNIT_EVENTS) do
    watcher:RegisterEvent(event)
  end
  for event in pairs(CAST_START) do
    watcher:RegisterEvent(event)
  end
  for event in pairs(CAST_STOP) do
    watcher:RegisterEvent(event)
  end
end

function module:OnDisable()
  watcher:UnregisterAllEvents()
  ns.WhenOutOfCombat(function()
    for _, frame in pairs(frames) do
      UnregisterUnitWatch(frame)
      frame:Hide()
    end
  end)
end


function module:Refresh()
  ns.WhenOutOfCombat(function()
    if module.ApplyBlizzardBuffs then module.ApplyBlizzardBuffs() end
    for _, frame in pairs(frames) do
      ApplyEnabled(frame)
      ApplySize(frame)
    end
    module.ApplyHappiness(frames.pet)
    RenderAll()
  end)
end

-- Mock units so the frames can be arranged solo.
function module:SetTestMode(on)
  testMode = on and true or false
  for key, frame in pairs(frames) do
    if testMode then
      frame.testState = {
        name = frame.info.label, class = "PRIEST", isPlayer = true,
        health = key == "target" and 4200 or 7400, healthMax = 9000,
        power = 3100, powerMax = 5000, powerToken = "MANA", reaction = "friendly",
        canMeasure = true, canMeasurePower = true,
      }
      UnregisterUnitWatch(frame)
      frame:Show()
    else
      frame.testState = nil
      RegisterUnitWatch(frame)
    end
    module.Render(frame)
  end
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------

-- The options page: a General tab that every frame follows, then a tab per
-- frame (Player, Target, Target of Target, Pet, Focus) where a value can be
-- set for that frame alone, then Cast Bars. Laid out from the owner's
-- mock-up. Party and raid frames are the grids (Heal / Tank / DPS at the top
-- of the menu), and the tab says so rather than pretending to hold them.
--
-- A per-frame tab reads through to General until something on it is
-- changed: the rows show the value the frame is actually drawn with, and
-- editing one makes it that frame's own. "Follow General again" clears them.
local function Choices(...)
  local list, args = {}, { ... }
  for i = 1, #args, 2 do
    list[#list + 1] = { label = args[i], value = args[i + 1] }
  end
  return function() return list end
end
local ANCHORS       = Choices("Left", "left", "Centre", "center", "Right", "right")
local NAME_COLORS   = Choices("White", "white", "Class colour", "class")
local HEALTH_COLORS = Choices("Class colour", "class", "Friend or foe", "reaction", "Green", "green",
  "Your colour", "custom", "Gradient by health", "gradient")
local FILLS         = Choices("Left to right", "left", "Right to left", "right")
local POWER_AT      = Choices("Along the bottom", "bottom", "Along the top", "top")
local BACKGROUNDS   = Choices("Dark", "dark", "Light", "light", "See-through", "transparent",
  "Class tint", "class", "Your colour", "custom")
local BORDERS       = Choices("None", "none", "Thin", "thin", "Thick", "thick")
local BORDER_COLORS = Choices("Black", "black", "Class colour", "class", "Your colour", "custom")
local AURA_AT       = Choices("Above the frame", "above", "Below the frame", "below",
  "Left of the frame", "left", "Right of the frame", "right")
local function TEXTURES()
  local list = { { label = "Same as Appearance", value = "" } }
  for _, name in ipairs(ns.Media.List("texture")) do
    list[#list + 1] = { label = name, value = name }
  end
  return list
end

-- The grids' "Healing / Tanking / DPS" title strips: on unless switched off.
local function GridTitleStore()
  return setmetatable({}, {
    __index = function() return ns.db.gridTitles ~= false end,
    __newindex = function(_, _, value) ns.db.gridTitles = value and true or false end,
  })
end

local function UnitStore(key)
  return setmetatable({}, {
    __index = function(_, field)
      local settings = Settings()
      local own = settings.unitOpts and settings.unitOpts[key]
      if own and own[field] ~= nil then
        return own[field]
      end
      return settings[field]
    end,
    __newindex = function(_, field, value)
      local settings = Settings()
      settings.unitOpts = settings.unitOpts or {}
      settings.unitOpts[key] = settings.unitOpts[key] or {}
      settings.unitOpts[key][field] = value
    end,
  })
end

-- units[key] is nil for on and false for off; a checkbox wants true/false.
local function EnabledStore(key)
  return setmetatable({}, {
    __index = function() return module.UnitEnabled(key) end,
    __newindex = function(_, _, value)
      local settings = Settings()
      settings.units = settings.units or {}
      -- Not `value and nil or false`: that is false whichever way you tick
      -- it (`true and nil` is nil, and `nil or false` is false), so a frame
      -- switched off could never be switched back on (reported on
      -- CurseForge, 24 Sept 2026).
      if value then
        settings.units[key] = nil
      else
        settings.units[key] = false
      end
    end,
  })
end

-- A frame's "Show buffs and debuffs": its own choice, else whether that
-- frame shows them as standard (target and focus do).
local function AuraStore(key)
  return setmetatable({}, {
    __index = function() return module.AurasOn(key) end,
    __newindex = function(_, _, value) UnitStore(key).auras = value and true or false end,
  })
end

-- Icon size reads through to the size for this kind of frame.
local function AuraSizeStore(info)
  return setmetatable({}, {
    __index = function() return module.AuraSize(info) end,
    __newindex = function(_, _, value) UnitStore(info.key).auraSize = value end,
  })
end

-- Which frame's overrides exist, for the tab's note.
local function Overridden(key)
  local own = Settings().unitOpts and Settings().unitOpts[key]
  if not own then return 0 end
  local n = 0
  for _ in pairs(own) do n = n + 1 end
  return n
end

local function UnitTab(info)
  local key, tab, store = info.key, info.key, UnitStore(info.key)
  local sizeKeyW = info.small and "smallWidth" or "width"
  local sizeKeyH = info.small and "smallHeight" or "height"
  return {
    { type = "heading", tab = tab, tabLabel = info.label, label = info.label .. " frame",
      subtitle = "Settings for this one frame. Anything left alone follows General.", icon = "unitframes" },
    { type = "checkbox", tab = tab, label = "Show this frame", store = function() return EnabledStore(key) end,
      key = "enabled", desc = "Off, and the frame is gone even when its unit exists." },
    { type = "heading", tab = tab, label = "Size", columns = 2, icon = "layout" },
    { type = "stepper", tab = tab, key = "width", label = "Width", min = 80, max = 320, step = 10,
      store = function()
        local st = UnitStore(key)
        -- width/height read the shared size for this frame's class of frame
        return setmetatable({}, { __index = function(_, f)
          local own = Settings().unitOpts and Settings().unitOpts[key]
          if own and own[f] ~= nil then return own[f] end
          return Settings()[f == "width" and sizeKeyW or sizeKeyH]
        end, __newindex = function(_, f, v) st[f] = v end })
      end },
    { type = "stepper", tab = tab, key = "height", label = "Height", min = 18, max = 80, step = 2,
      store = function()
        local st = UnitStore(key)
        return setmetatable({}, { __index = function(_, f)
          local own = Settings().unitOpts and Settings().unitOpts[key]
          if own and own[f] ~= nil then return own[f] end
          return Settings()[f == "width" and sizeKeyW or sizeKeyH]
        end, __newindex = function(_, f, v) st[f] = v end })
      end },
    { type = "heading", tab = tab, label = "Health and power", columns = 2, icon = "heal" },
    { type = "cycler", tab = tab, key = "healthText", label = "Health text", store = function() return store end,
      choices = function() return HEALTH_TEXT end },
    { type = "checkbox", tab = tab, key = "showName", label = "Show name", store = function() return store end },
    { type = "checkbox", tab = tab, key = "showHealthText", label = "Show health text", store = function() return store end },
    { type = "cycler", tab = tab, key = "healthColorMode", label = "Health colour", store = function() return store end,
      choices = HEALTH_COLORS },
    { type = "cycler", tab = tab, key = "nameAnchor", label = "Name position", store = function() return store end,
      choices = ANCHORS },
    { type = "checkbox", tab = tab, key = "showPower", label = "Show power bar", store = function() return store end },
    { type = "cycler", tab = tab, key = "powerText", label = "Power text", store = function() return store end,
      choices = function() return POWER_TEXT end },
    { type = "checkbox", tab = tab, key = "castBars", label = "Show cast bar", store = function() return store end },
    { type = "heading", tab = tab, label = "Buffs and debuffs", columns = 2, icon = "auras" },
    { type = "checkbox", tab = tab, key = "auras", label = "Show buffs and debuffs",
      store = function() return AuraStore(key) end,
      desc = "The switch for this frame. What kind, how big and where are below and on General." },
    { type = "checkbox", tab = tab, key = "showBuffs", label = "Buffs", store = function() return store end },
    { type = "checkbox", tab = tab, key = "showDebuffs", label = "Debuffs", store = function() return store end },
    { type = "cycler", tab = tab, key = "debuffPosition", label = "Debuffs go", store = function() return store end,
      choices = AURA_AT },
    { type = "cycler", tab = tab, key = "buffPosition", label = "Buffs go", store = function() return store end,
      choices = AURA_AT },
    { type = "stepper", tab = tab, key = "auraSize", label = "Icon size", min = 12, max = 40, step = 2,
      store = function() return AuraSizeStore(info) end },
    { type = "action", tab = tab, label = "Follow General again", icon = "reset", width = 220,
      desc = "Clears this frame's own settings so it takes General's.",
      labelFor = function()
        local n = Overridden(key)
        return n > 0 and ("Follow General again (%d own)"):format(n) or "Follow General again"
      end,
      onClick = function()
        if Settings().unitOpts then Settings().unitOpts[key] = nil end
        module:Refresh()
        ns.RefreshOptions()
      end },
  }
end

---------------------------------------------------------------------------
-- Live preview on the options page: a player and a target frame drawn from
-- the current settings, at true size, so a change is seen before it lands.
---------------------------------------------------------------------------

local preview

local PREVIEW_UNITS = {
  { key = "player", name = "Skuri", level = 70, class = "DRUID", health = 15240, healthMax = 15240, power = 5000, powerMax = 5000, powerToken = "MANA", isPlayer = true },
  { key = "target", name = "Training Dummy", class = nil, health = 184500, healthMax = 1230000, power = 0, powerMax = 0, isPlayer = false, reaction = "hostile", level = 72, elite = true },
  { key = "targettarget", name = "Kupho", level = 70, class = "MAGE", health = 2841, healthMax = 3000, power = 2000, powerMax = 4000, powerToken = "MANA", isPlayer = true, small = true },
  { key = "focus", name = "Panz", level = 69, class = "WARRIOR", health = 900, healthMax = 3124, power = 60, powerMax = 100, powerToken = "RAGE", isPlayer = true, small = true },
}

local function PreviewFrame(parent, spec)
  local f = CreateFrame("Frame", nil, parent)
  module.BuildParts(f)
  f.label = parent:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(f.label, "general")
  f.label:SetTextColor(unpack(ns.Colors.ui.textDim))
  f.spec = spec
  f.info = { key = spec.key, small = spec.small }
  return f
end

local PREVIEW_LABELS = { player = "Player frame", target = "Target frame",
  targettarget = "Target of target", focus = "Focus" }

function module.RefreshPreview()
  if not preview then return end
  local y = -28
  for _, f in ipairs(preview.frames) do
    local spec = f.spec
    local w, h = module.FrameSize(f.info)
    local scale = math.min(1, (preview.width - 16) / w)
    f:SetSize(w * scale, h * scale)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", preview, "TOPLEFT", 8, y - 16)
    f.label:ClearAllPoints()
    f.label:SetPoint("TOPLEFT", preview, "TOPLEFT", 8, y)
    local on = module.UnitEnabled(spec.key)
    f.label:SetText(PREVIEW_LABELS[spec.key] .. (on and "" or "  (off)"))
    module.Style(f, spec.key)
    module.Paint(f, {
      name = spec.name, class = spec.class, health = spec.health, healthMax = spec.healthMax,
      power = spec.power, powerMax = spec.powerMax, powerToken = spec.powerToken,
      isPlayer = spec.isPlayer, reaction = spec.reaction, level = spec.level, elite = spec.elite,
      canMeasure = true, canMeasurePower = true, dead = false,
    }, spec.key)
    f:SetShown(on)
    y = on and (y - 16 - h * scale - 14) or (y - 22)
  end
  preview:SetHeight(-y + 8)
end

function module.BuildPreview(parent, x, y, width)
  preview = CreateFrame("Frame", nil, parent)
  preview:SetPoint("TOPLEFT", x, y)
  preview.width = math.min(width, 360)
  preview:SetSize(preview.width, 200)
  ns.Skin.Panel(preview, { color = { 0.02, 0.04, 0.08, 1 } })
  local title = preview:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(title, "header")
  title:SetPoint("TOPLEFT", 8, -8)
  title:SetText("Live preview")
  ns.Skin.AccentText(title)
  local sub = preview:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(sub, "general")
  sub:SetPoint("LEFT", title, "RIGHT", 8, 0)
  sub:SetText("Your changes, as the frames will draw them.")
  sub:SetTextColor(unpack(ns.Colors.ui.textDim))
  preview.frames = {}
  for _, spec in ipairs(PREVIEW_UNITS) do
    preview.frames[#preview.frames + 1] = PreviewFrame(preview, spec)
  end
  module.RefreshPreview()
  module.preview = preview
  return preview:GetHeight()
end

local function BuildOptions()
  local list = {
    { type = "heading", label = "Unit Frames", subtitle = "Customize how unit frames look, behave, and what information they show." },

    -- General ---------------------------------------------------------
    { type = "heading", tab = "general", tabLabel = "General", label = "General settings",
      subtitle = "Every frame follows these until its own tab says otherwise.", icon = "general" },
    { type = "custom", tab = "general", build = function(parent, x, y, width)
      return module.BuildPreview(parent, x, y, width)
    end, refresh = function() module.RefreshPreview() end },
    { type = "heading", tab = "general", label = "Frame sizes", columns = 2, icon = "layout" },
    { type = "stepper", tab = "general", key = "width", label = "Player and target width", min = 120, max = 320, step = 10 },
    { type = "stepper", tab = "general", key = "height", label = "Player and target height", min = 26, max = 80, step = 2 },
    { type = "stepper", tab = "general", key = "smallWidth", label = "Small frame width", min = 80, max = 220, step = 10 },
    { type = "stepper", tab = "general", key = "smallHeight", label = "Small frame height", min = 18, max = 48, step = 2 },

    { type = "heading", tab = "general", label = "Text", columns = 2, icon = "general" },
    { type = "checkbox", tab = "general", key = "showName", label = "Show names" },
    { type = "checkbox", tab = "general", key = "showHealthText", label = "Show health text",
      desc = "The 100%, 15.2k and the rest." },
    { type = "cycler", tab = "general", key = "nameAnchor", label = "Name position", choices = ANCHORS },
    { type = "cycler", tab = "general", key = "healthAnchor", label = "Health text position", choices = ANCHORS },
    { type = "cycler", tab = "general", key = "nameColor", label = "Name colour", choices = NAME_COLORS },
    { type = "cycler", tab = "general", key = "healthText", label = "Health text", choices = function() return HEALTH_TEXT end },
    { type = "stepper", tab = "general", key = "nameLength", label = "Name length", min = 0, max = 20, step = 1,
      desc = "0 shows the whole name." },
    { type = "checkbox", tab = "general", key = "showLevel", label = "Show level",
      desc = "Before the name, with + for elites." },
    { type = "stepper", tab = "general", key = "nameSize", label = "Name size", min = 0, max = 24, step = 1,
      desc = "0 uses the font's own size." },
    { type = "stepper", tab = "general", key = "healthSize", label = "Health text size", min = 0, max = 24, step = 1,
      desc = "0 uses the font's own size." },

    { type = "heading", tab = "general", label = "Bars", columns = 2, icon = "xpbar" },
    { type = "cycler", tab = "general", key = "barTexture", label = "Bar texture", choices = TEXTURES },
    { type = "cycler", tab = "general", key = "healthColorMode", label = "Health colour", choices = HEALTH_COLORS },
    { type = "color", tab = "general", key = "healthCustomColor", label = "Your health colour",
      desc = "Used when Health colour is Your colour." },
    { type = "cycler", tab = "general", key = "fillDirection", label = "Bars fill", choices = FILLS },
    { type = "stepper", tab = "general", key = "lowHealthThreshold", label = "Low health threshold %", min = 0, max = 60, step = 5,
      desc = "0 turns the warning colour off." },
    { type = "color", tab = "general", key = "lowHealthColor", label = "Low health colour" },
    { type = "checkbox", tab = "general", key = "showPower", label = "Show power bars" },
    { type = "checkbox", tab = "general", key = "showIncoming", label = "Incoming heals",
      desc = "A pale green stretch past the end of the health bar: heals on their way." },
    { type = "checkbox", tab = "general", key = "showShields", label = "Shields",
      desc = "A pale white stretch past that: how much a shield (Power Word: Shield...) will soak." },
    { type = "checkbox", tab = "general", key = "powerClassColor", label = "Power bar colour by class" },
    { type = "checkbox", tab = "general", key = "petHappiness", label = "Pet happiness (hunters)",
      desc = "The game's happy / content / unhappy face beside the pet frame. Point at it for damage, loyalty and diet." },
    { type = "stepper", tab = "general", key = "powerHeight", label = "Power bar height %", min = 10, max = 40, step = 2 },
    { type = "cycler", tab = "general", key = "powerPosition", label = "Power bar", choices = POWER_AT },
    { type = "cycler", tab = "general", key = "powerText", label = "Power text", choices = function() return POWER_TEXT end,
      desc = "Mana, rage or energy as words on the power bar, like the health text." },
    { type = "cycler", tab = "general", key = "powerTextAnchor", label = "Power text position", choices = ANCHORS },
    { type = "stepper", tab = "general", key = "powerTextSize", label = "Power text size", min = 0, max = 24, step = 1,
      desc = "0 uses the font's own size." },
    { type = "checkbox", tab = "general", key = "castBars", label = "Show cast bars" },
    { type = "checkbox", tab = "general", key = "hideBlizzardFrames", label = "Hide Blizzard's unit frames", reload = true },

    { type = "heading", tab = "general", label = "Buffs and debuffs", columns = 2, icon = "auras" },
    { type = "note", tab = "general", label = "On the target and focus frames as standard; each frame's own tab switches them on or off (the player's are already top right, on the game's buff bar). The game draws them, so they keep working in a fight. Hover one for what it is; right-click one of your own buffs to cancel it." },
    { type = "checkbox", tab = "general", key = "showBuffs", label = "Show buffs" },
    { type = "checkbox", tab = "general", key = "showDebuffs", label = "Show debuffs",
      desc = "Their border is the dispel colour: blue magic, green poison, purple curse, brown disease." },
    { type = "checkbox", tab = "general", key = "onlyMyDebuffs", label = "Only debuffs I cast",
      desc = "On the target, focus and target of target. Your own frame and your pet's show everything on them." },
    { type = "cycler", tab = "general", key = "debuffPosition", label = "Debuffs go", choices = AURA_AT,
      desc = "Each kind on its own side of the frame. On the same side, buffs sit beyond the debuffs." },
    { type = "cycler", tab = "general", key = "buffPosition", label = "Buffs go", choices = AURA_AT },
    { type = "stepper", tab = "general", key = "auraTextSize", label = "Text size on the icons", min = 6, max = 20, step = 1,
      desc = "The stack count and the seconds left." },
    { type = "stepper", tab = "general", key = "auraSize", label = "Icon size", min = 12, max = 40, step = 2,
      desc = "Player and target." },
    { type = "stepper", tab = "general", key = "smallAuraSize", label = "Small frame icon size", min = 12, max = 32, step = 2,
      desc = "Focus, pet and target of target." },
    { type = "stepper", tab = "general", key = "maxDebuffs", label = "Most debuffs", min = 1, max = 10, step = 1 },
    { type = "stepper", tab = "general", key = "maxBuffs", label = "Most buffs", min = 1, max = 10, step = 1 },
    { type = "checkbox", tab = "general", key = "auraTimers", label = "Seconds left on each icon" },
    { type = "checkbox", tab = "general", key = "hideBlizzardBuffs", label = "Hide the game's buff bar (top right)",
      desc = "Edit Mode can't hide it. Your own frame then shows your buffs (its tab can turn them off). Turning it back on takes a reload.",
      reload = true },

    { type = "heading", tab = "general", label = "Background and border", columns = 2, icon = "appearance" },
    { type = "cycler", tab = "general", key = "backgroundStyle", label = "Background", choices = BACKGROUNDS },
    { type = "stepper", tab = "general", key = "backgroundOpacity", label = "Background opacity %", min = 0, max = 100, step = 5 },
    { type = "color", tab = "general", key = "backgroundColor", label = "Your background colour",
      desc = "Used when Background is Your colour." },
    { type = "cycler", tab = "general", key = "borderStyle", label = "Border", choices = BORDERS },
    { type = "cycler", tab = "general", key = "borderColorMode", label = "Border colour", choices = BORDER_COLORS },
    { type = "color", tab = "general", key = "borderColor", label = "Your border colour",
      desc = "Used when Border colour is Your colour." },
    { type = "checkbox", tab = "general", key = "mouseoverHighlight", label = "Mouseover highlight" },

    { type = "heading", tab = "general", label = "Layout and positioning", columns = 2, icon = "framemgmt" },
    { type = "checkbox", tab = "general", key = "moverGrid", scope = "core", label = "Snap to grid",
      desc = "Dragged frames land on an 8-pixel grid." },
    { type = "action", tab = "general", label = "Move frames now", icon = "framemgmt", width = 200,
      desc = "Drag handles for every frame. Done when finished.",
      onClick = function() ns.ToggleMovers(true) end },
    { type = "action", tab = "general", label = "Reset frame positions", icon = "reset", width = 200,
      desc = "Every unit frame back where the standard puts it.",
      onClick = function()
        for _, info in ipairs(UNITS) do ns.ResetMover(info.key) end
      end },

    { type = "action", tab = "general", label = "Reset this section", icon = "reset", width = 200,
      desc = "General back to the shipped defaults, and every frame switched back on. Each frame's own size and looks are kept.",
      onClick = function()
        local settings = Settings()
        for k, v in pairs(module.defaults) do
          if k ~= "units" and k ~= "unitOpts" then
            settings[k] = type(v) == "table" and ns.CopyTable(v) or v
          end
        end
        -- A frame switched off is a frame someone may not find again: a
        -- reset brings them all back.
        settings.units = {}
        module:Refresh()
        ns.RefreshOptions()
      end },
  }
  for _, info in ipairs(UNITS) do
    for _, entry in ipairs(UnitTab(info)) do
      list[#list + 1] = entry
    end
  end
  local more = {
    -- Party and raid: the grids ------------------------------------------
    { type = "heading", tab = "party", tabLabel = "Party & Raid", label = "Party and raid frames", icon = "roles",
      subtitle = "These are the Healing, Tanking and DPS grids." },
    { type = "note", tab = "party", label = "Party and raid frames are the role grids: one set of frames per role, each with its own clicks, indicators and layout. Their growth direction, spacing, anchor and everything else live in the role's own window." },
    { type = "checkbox", tab = "party", key = "gridTitles", label = "Show role titles on the grids",
      desc = "The Healing, Tanking and DPS strip across the top of each grid. Off, and only the coloured border says which is which.",
      store = GridTitleStore,
      apply = function() if ns.Frames and ns.Frames.ApplyGridTitles then ns.Frames.ApplyGridTitles() end end },
    { type = "action", tab = "party", label = "Open the Healing grid", icon = "heal", width = 220,
      onClick = function() if ns.OpenRoleWindow then ns.OpenRoleWindow("healer") end end },
    { type = "action", tab = "party", label = "Open the Tanking grid", icon = "tank", width = 220,
      onClick = function() if ns.OpenRoleWindow then ns.OpenRoleWindow("tank") end end },
    { type = "action", tab = "party", label = "Open the DPS grid", icon = "dps", width = 220,
      onClick = function() if ns.OpenRoleWindow then ns.OpenRoleWindow("dps") end end },

    -- Cast bars -----------------------------------------------------------
    { type = "heading", tab = "cast", tabLabel = "Cast Bars", label = "Cast bars", icon = "castbar",
      subtitle = "The bar under each frame while its unit casts. Your own big cast bar is the Cast Bar module." },
    { type = "heading", tab = "cast", label = "Cast bar", columns = 2, icon = "castbar" },
    { type = "stepper", tab = "cast", key = "castBarHeight", label = "Cast bar height", min = 10, max = 34, step = 2 },
    { type = "checkbox", tab = "cast", key = "castIcon", label = "Show cast icon" },
    { type = "checkbox", tab = "cast", key = "castTime", label = "Show cast time text" },
    { type = "checkbox", tab = "cast", key = "castLatency", label = "Latency prediction",
      desc = "A red end on your own bar for the lag you can cast ahead of." },

    -- Profiles ------------------------------------------------------------
    { type = "heading", tab = "profiles", tabLabel = "Profiles", label = "Profiles", icon = "profiles",
      subtitle = "Save, load and share your settings." },
    { type = "note", tab = "profiles", label = "Unit frame settings live in your ForeverUI profile with everything else. Switch, copy, export or import on the Profiles page." },
    { type = "action", tab = "profiles", label = "Open the Profiles page", icon = "profiles", width = 220,
      onClick = function() ns.OpenOptions("profiles") end },
  }
  for _, entry in ipairs(more) do list[#list + 1] = entry end
  return list
end
module.options = BuildOptions()

module.frames = frames
module.UNITS = UNITS
module.HEALTH_TEXT = HEALTH_TEXT
