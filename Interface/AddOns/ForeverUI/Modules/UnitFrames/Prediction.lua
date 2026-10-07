local _, ns = ...

-- Incoming heals and shields on the unit frames (sprutorgel on CurseForge,
-- 26 Sept 2026: "incoming heals and shield amount on normal unit frames, like
-- player, target etc. if you are not using the healing module").
--
-- The same way the healing grids draw them: the amounts can be secret on
-- Forever, and a secret can be shown but never measured, so nothing here does
-- sums. Each is its own status bar, as wide as the health bar and scaled to
-- the unit's maximum health, starting where the health fill ends - anchored
-- to the fill itself, so it follows it - and clipped at the frame's edge. The
-- shield bar starts where the incoming heal ends.

local module = ns.GetModule("UnitFrames")
if not module then return end

local HEAL = { 0.40, 0.95, 0.50, 0.45 }
local SHIELD = { 0.85, 0.92, 1.00, 0.55 }

local function Bar(frame, key, colour, level)
  local bar = frame[key]
  if bar then return bar end
  local health = frame.health
  bar = CreateFrame("StatusBar", nil, health)
  bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  bar:SetStatusBarColor(colour[1], colour[2], colour[3], colour[4])
  local base = health.GetFrameLevel and health:GetFrameLevel()
  if base and bar.SetFrameLevel then bar:SetFrameLevel(base + level) end
  bar:Hide()
  frame[key] = bar
  return bar
end

-- Hand the game's values straight to the bar, whatever they are; `after` is
-- the texture to start from. nil (no such API, or no unit) hides it.
local function Place(frame, bar, after, value, maximum)
  if type(value) == "nil" or type(maximum) == "nil" or not after then
    bar:Hide()
    return
  end
  local health = frame.health
  local reverse = module.Opt("fillDirection", frame.info.key) == "right"
  bar:ClearAllPoints()
  if reverse then
    bar:SetPoint("TOPRIGHT", after, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", after, "BOTTOMLEFT", 0, 0)
  else
    bar:SetPoint("TOPLEFT", after, "TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", after, "BOTTOMRIGHT", 0, 0)
  end
  if bar.SetReverseFill then bar:SetReverseFill(reverse) end
  bar:SetWidth(health:GetWidth() or 100)
  local ok = pcall(function()
    bar:SetMinMaxValues(0, maximum)
    bar:SetValue(value)
  end)
  bar:SetShown(ok)
end

local function Ask(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

function module.RenderPrediction(frame, state)
  if not (frame and frame.health and frame.info) then return end
  local key = frame.info.key
  local heal = Bar(frame, "fuiIncoming", HEAL, 1)
  local shield = Bar(frame, "fuiShield", SHIELD, 2)
  local unit = frame.unit
  if not state or state.dead or frame.testState or not unit then
    heal:Hide(); shield:Hide()
    return
  end
  local health = frame.health
  if health.SetClipsChildren and not health.fuiClipped then
    pcall(health.SetClipsChildren, health, true)
    health.fuiClipped = true
  end
  local fill = health.GetStatusBarTexture and health:GetStatusBarTexture()
  local maximum = Ask(UnitHealthMax, unit)
  if module.Opt("showIncoming", key) ~= false then
    Place(frame, heal, fill, Ask(UnitGetIncomingHeals, unit), maximum)
  else
    heal:Hide()
  end
  if module.Opt("showShields", key) ~= false then
    local after = heal:IsShown() and heal:GetStatusBarTexture() or fill
    Place(frame, shield, after, Ask(UnitGetTotalAbsorbs, unit), maximum)
  else
    shield:Hide()
  end
end
