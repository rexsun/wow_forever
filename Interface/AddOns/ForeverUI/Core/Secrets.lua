local _, ns = ...

-- Forever hides some unit information from addons. Health, power, casts and
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

-- Fill a bar without touching the numbers. Works whether or not the values
-- are secret, which is why every module should use it rather than its own
-- SetMinMaxValues / SetValue pair.
--
-- Every caller wraps this in a pcall, so when it fails the bar just stays
-- empty and nobody is told why -- which is how every nameplate lost its
-- health bar with no error anywhere. It reports the first failure now, once,
-- and says which call refused.
local barComplaint = false

function secrets.SetBar(bar, current, maximum)
  local okRange, rangeErr = pcall(bar.SetMinMaxValues, bar, 0, maximum)
  if not okRange then
    -- A secret maximum was refused. Fall back to a fixed range and feed the
    -- secret straight in: the bar is then filled in units of health against a
    -- constant scale, which is wrong, so only do it to keep SOMETHING drawn
    -- while the complaint below explains the real problem.
    pcall(bar.SetMinMaxValues, bar, 0, 100)
  end
  local okValue, valueErr = pcall(bar.SetValue, bar, current)
  if (not okRange or not okValue) and not barComplaint then
    barComplaint = true
    if ns.Print then
      ns.Print(("|cffff6666a health bar refused its values:|r %s"):format(
        tostring(rangeErr or valueErr)))
    end
  end
  return okRange and okValue
end

-- True when it's safe to compute with this unit's health (text, percentages,
-- comparisons). False means show the bar and skip the numbers.
function secrets.CanMeasureHealth(unit)
  return not secrets.HealthSecret(unit)
end

function secrets.CanMeasurePower(unit, powerType)
  return not secrets.PowerSecret(unit, powerType)
end

-- A plain number from a value that may be secret, or nil. Forever ships a
-- direct test; older clients get the arithmetic probe.
local function Add0(value)
  return value + 0
end

function secrets.Number(value)
  -- type(), not "== nil": comparing a secret value can throw.
  if type(value) == "nil" then
    return nil
  end
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

-- A plain string from a value that may be a secret string, or nil. A secret
-- string can be shown (SetText) but not compared, lowered, measured or used
-- as a table key - each of those throws (UnitCreatureType on a nameplate
-- in the open world, 25 Sept 2026).
function secrets.String(value)
  if type(value) ~= "string" then
    return nil
  end
  if issecretvalue then
    local ok, isSecret = pcall(issecretvalue, value)
    if not ok or isSecret then
      return nil
    end
  end
  return value
end

-- A plain true/false from a value that may be a secret boolean (testing one
-- throws), or the default.
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
