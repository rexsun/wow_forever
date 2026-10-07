local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- Forever hides some unit information from addons (the same rules ForeverUI
-- follows; HealForever keeps its own copy so it stays a standalone addon). Health, power, casts and
-- auras can come back as "secret values": you may hand them straight to a
-- widget (a status bar happily fills from one), but the moment tainted code
-- does arithmetic on one the game throws
--
--   attempt to perform arithmetic on local 'health' (a secret number value)
--
-- So the rule for every module is: never calculate, pass through. Ask here
-- first when you want to show a number, and leave it out when the answer is no.

local secrets = {}
ns.Secrets = secrets

-- Looked up on each call: the table may not exist yet at load, and a client
-- without the restriction never defines it at all.
local function API()
  return C_Secrets
end

function secrets.Enabled()
  local api = API()
  if not api or not api.HasSecretRestrictions then
    return false
  end
  local ok, restricted = pcall(api.HasSecretRestrictions)
  return ok and restricted or false
end

-- Each query is wrapped: these are new APIs, and a missing one must mean
-- "assume secret" rather than an error in the middle of drawing a frame.
local function Ask(query, ...)
  if not secrets.Enabled() then
    return false
  end
  local api = API()
  local fn = api and api[query]
  if not fn then
    return true
  end
  local ok, isSecret = pcall(fn, ...)
  if not ok then
    return true
  end
  return isSecret and true or false
end

-- A unit's raid mark on a texture. The mark comes back SECRET on Forever
-- (even solo), so it can't be compared, looked up or turned into texture
-- coordinates here - but Texture:SetSpriteSheetCell takes a secret cell
-- (SimpleTextureBaseAPI, forever branch: AllowedWhenTainted), and the icons
-- are a 4x4 sheet. No mark is a plain nil. Proved in game 25 Sept 2026: the
-- marks worked, nothing of ours drew them. Returns whether it is shown.
local MARK_SHEET = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
function secrets.PaintRaidMark(texture, unit)
  local ok, index = false, nil
  if unit and GetRaidTargetIndex then
    ok, index = pcall(GetRaidTargetIndex, unit)
  end
  local secret = ok and issecretvalue and issecretvalue(index)
  if not ok or (not secret and (type(index) ~= "number" or index < 1 or index > 8)) then
    texture:Hide()
    return false
  end
  texture:SetTexture(MARK_SHEET)
  if texture.SetSpriteSheetCell and pcall(texture.SetSpriteSheetCell, texture, index, 4, 4) then
    texture:Show()
    return true
  end
  if not secret then   -- an older client: the sums, on a plain number
    local column, row = (index - 1) % 4, math.floor((index - 1) / 4)
    texture:SetTexCoord(column / 4, (column + 1) / 4, row / 4, (row + 1) / 4)
    texture:Show()
    return true
  end
  texture:Hide()
  return false
end

function secrets.HealthSecret(unit)
  return Ask("ShouldUnitHealthMaxBeSecret", unit)
end

function secrets.PowerSecret(unit, powerType)
  return Ask("ShouldUnitPowerBeSecret", unit, powerType or 0)
end

function secrets.IdentitySecret(unit)
  return Ask("ShouldUnitIdentityBeSecret", unit)
end

function secrets.CastSecret(unit)
  return Ask("ShouldUnitSpellCastingBeSecret", unit)
end

function secrets.AurasSecret()
  return Ask("ShouldAurasBeSecret")
end

-- Auras are worse than secret values: on Forever, asking for one while the
-- game has them locked is a hard error out of the API itself, not a value you
-- can quietly ignore -
--
--   GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted
--
-- and the query above cheerfully says they're readable first. So the first
-- refusal stops the frames asking for a few seconds rather than once per aura per
-- unit per tick; leaving combat clears it immediately.
local AURA_RETRY = 5 -- seconds
local blockedUntil = 0

local function Now()
  return (GetTime and GetTime()) or 0
end

-- Auras and cooldowns are hidden while an addon restriction is in force -
-- combat, an encounter, a keystone or a PvP match. The game will say so
-- outright, which beats finding out by being refused.
local AURA_RESTRICTIONS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch" }

function secrets.AurasRestricted()
  local api = C_RestrictedActions
  local types = Enum and Enum.AddOnRestrictionType
  if not api or not api.IsAddOnRestrictionActive or not types then
    return false
  end
  for _, name in ipairs(AURA_RESTRICTIONS) do
    local id = types[name]
    if id then
      local ok, active = pcall(api.IsAddOnRestrictionActive, id)
      if ok and active then
        return true
      end
    end
  end
  return false
end

function secrets.AurasBlocked()
  return blockedUntil > 0 and Now() < blockedUntil
end

function secrets.BlockAuras(seconds)
  if ns.Note then ns.Note("aura read refused by the client") end
  blockedUntil = Now() + (seconds or AURA_RETRY)
end

function secrets.UnblockAuras()
  blockedUntil = 0
end

-- SCALING A NUMBER YOU AREN'T ALLOWED TO MULTIPLY
--
-- UnitHealthPercent hands back a fraction, and its own documentation says it
-- "can be scaled via a curve for display purposes" - which is the only way,
-- because multiplying a secret value by 100 is exactly what the restriction
-- forbids. A curve does the arithmetic on the game's side: feed it the
-- fraction, get the percentage.
--
--   0.0 -> 0      0.87 -> 87      1.0 -> 100
local percentCurve, percentCurveTried

-- The curve is built once, at the first draw. This lets it be built again if
-- the API only shows up later, and lets the tests swap the API underneath.
function secrets.ForgetPercentCurve()
  percentCurve, percentCurveTried = nil, nil
end

function secrets.PercentCurve()
  if percentCurveTried then
    return percentCurve
  end
  percentCurveTried = true
  local api = C_CurveUtil
  if not api or not api.CreateCurve then
    return nil
  end
  local ok, curve = pcall(api.CreateCurve)
  if not ok or not curve then
    return nil
  end
  local added = pcall(function()
    curve:AddPoint(0, 0)
    curve:AddPoint(1, 100)
  end)
  percentCurve = added and curve or nil
  return percentCurve
end

-- Health as a COLOUR. Same idea as the percent curve, but the curve's values
-- are colours, so the game blends green -> yellow -> red from a number we are
-- never shown, and the bar accepts the (secret) result.
secrets.HEALTH_STOPS = {
  { 0.00, 0.85, 0.12, 0.12 },
  { 0.25, 0.85, 0.12, 0.12 },
  { 0.50, 0.95, 0.80, 0.15 },
  { 0.80, 0.18, 0.78, 0.22 },
  { 1.00, 0.18, 0.78, 0.22 },
}
local colorCurve, colorCurveTried

function secrets.ForgetColorCurve()
  colorCurve, colorCurveTried = nil, nil
end

function secrets.HealthColorCurve()
  if colorCurveTried then
    return colorCurve
  end
  colorCurveTried = true
  local api = C_CurveUtil
  if not api or not api.CreateColorCurve or not CreateColor then
    return nil
  end
  local ok, curve = pcall(api.CreateColorCurve)
  if not ok or not curve then
    return nil
  end
  local added = pcall(function()
    for _, stop in ipairs(secrets.HEALTH_STOPS) do
      curve:AddPoint(stop[1], CreateColor(stop[2], stop[3], stop[4], 1))
    end
  end)
  colorCurve = added and curve or nil
  return colorCurve
end

-- The same blend by hand, for a client that lets health be read.
function secrets.HealthColorAt(fraction)
  local stops = secrets.HEALTH_STOPS
  if fraction <= stops[1][1] then
    return stops[1][2], stops[1][3], stops[1][4]
  end
  for i = 2, #stops do
    local a, b = stops[i - 1], stops[i]
    if fraction <= b[1] then
      local t = (fraction - a[1]) / (b[1] - a[1])
      return a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t
    end
  end
  local last = stops[#stops]
  return last[2], last[3], last[4]
end

-- SECRET BOOLEANS
--
-- Not only numbers: once you are grouped, UnitInRange (and unit comparisons)
-- can return a secret boolean, and `if value then` on one throws exactly like
-- arithmetic on a secret number - on every refresh, hundreds of times a second.
--
-- Bool turns a maybe-secret boolean into a plain one, or `default` when the
-- client won't say. The test runs protected; that is the whole trick.
local function Test(value)
  if value then
    return true
  end
  return false
end

function secrets.Bool(value, default)
  local ok, result = pcall(Test, value)
  if ok then
    return result
  end
  return default
end

-- Pick one of two numbers from a boolean that may be secret, without ever
-- looking at it: the game does the choosing (C_CurveUtil), and what comes back
-- goes straight to a widget. Falls back to `whenUnknown` on clients without it.
function secrets.Choose(value, whenTrue, whenFalse, whenUnknown)
  local ok, result = pcall(Test, value)
  if ok then
    return result and whenTrue or whenFalse
  end
  local eval = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
  if eval then
    local okEval, chosen = pcall(eval, value, whenTrue, whenFalse)
    if okEval and type(chosen) ~= "nil" then   -- type(), not ~= nil: chosen can be secret
      return chosen
    end
  end
  return whenUnknown
end

-- Fill a bar without touching the numbers. Works whether or not the values
-- are secret, which is why every module should use it rather than its own
-- SetMinMaxValues / SetValue pair.
-- `glide`: move toward the new value instead of jumping (Forever's status
-- bars take an interpolation, and it works on secret values too).
function secrets.SetBar(bar, current, maximum, glide)
  bar:SetMinMaxValues(0, maximum)
  local ease = glide and Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
  if ease then
    bar:SetValue(current, ease)
  else
    bar:SetValue(current)
  end
end

-- True when it's safe to compute with this unit's health (text, percentages,
-- comparisons). False means show the bar and skip the numbers.
function secrets.CanMeasureHealth(unit)
  return not secrets.HealthSecret(unit)
end

function secrets.CanMeasurePower(unit, powerType)
  return not secrets.PowerSecret(unit, powerType)
end

-- Secret values pass through widgets happily and explode in arithmetic, and
-- the queries above can say "readable" about a value that arrives secret
-- anyway. So anything HealForever intends to compute with goes through here first:
-- back comes a plain number, or nil meaning "show it, don't count it".
local function Add0(value)
  return value + 0
end

function secrets.Number(value)
  -- type(), not "== nil": comparing a secret value can throw.
  if type(value) == "nil" then
    return nil
  end
  -- Forever ships a direct test; older clients get the arithmetic probe.
  if issecretvalue then
    local ok, isSecret = pcall(issecretvalue, value)
    if ok and isSecret then
      return nil
    end
  end
  local ok, number = pcall(Add0, value)
  if ok and type(number) == "number" then
    return number
  end
  return nil
end

-- Run a calculation that touches unit values. Returns false when the client
-- refuses, which is the only reliable test: a query can say a value is
-- readable and the value still arrive secret.
function secrets.Measure(fn, ...)
  local ok, result = pcall(fn, ...)
  return ok, result
end

-- One line for the options window and /fui version, so the restriction is
-- visible rather than mysterious.
function secrets.Describe()
  if not secrets.Enabled() then
    return "This client lets addons read unit values."
  end
  return "This client hides some unit values from addons; bars still fill, but numbers may be blank."
end
