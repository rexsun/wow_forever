local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- Your debuffs on your target: the ones YOU put there, which are the ones you
-- have to keep up. Not the target's whole debuff list - a Shadow Word: Pain
-- ticking away under six other people's is exactly what this is for.
--
-- Reading them on Forever takes care, because aura data is hidden while an
-- addon restriction is in force, and the two ways of asking behave differently:
--
--   C_UnitAuras.GetAuraDataByIndex  RequiresUnitAuraAccess, FailureMode Error.
--                                   Raises when locked. Only ever called
--                                   through ns.AuraAt, which catches it.
--   C_UnitAuras.GetUnitAuraBySpellID  RequiresNonSecretAura: "does not raise a
--                                   blocked action error - instead, protected
--                                   APIs will return no values." Safe to ask
--                                   any time, so it's tried when the scan is
--                                   blocked.
--
-- Whatever comes back, a number that arrives secret becomes nil (ns.Secrets
-- .Number), so an icon can appear with no countdown under it rather than the
-- whole frame erroring.

local MAX_ICONS = 6
local WARNING = 3      -- seconds left when the countdown turns red
local DEBUFF_FILTER = "HARMFUL|PLAYER"

local frame

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------

-- The plain scan: everything you cast on the unit, in the game's own order.
-- Returns the number found; zero can mean "none" or "not allowed to look".
local function ScanDebuffs(unit, list)
  local n = 0
  for i = 1, 40 do
    local found, icon, _, duration, expires, name, stacks, mine =
      ns.AuraAt(unit, i, DEBUFF_FILTER)
    if not found or n == MAX_ICONS then
      break
    end
    -- The filter should have done this, but the caster is checked anyway: an
    -- old client's filter behaves differently, and someone else's Sunder
    -- Armor in your row is worse than useless.
    if mine ~= false then
      n = n + 1
      local slot = list[n] or {}
      list[n] = slot
      slot.icon, slot.duration, slot.expires = icon, duration, expires
      slot.name, slot.stacks = name, stacks
    end
  end
  return n
end

-- The fallback: ask for each harmful spell you know, one at a time. Slower and
-- narrower - it can only find what's in your spellbook - but it answers while
-- the scan is locked out.
local function QueryDebuffs(unit, list, from)
  local query = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
  if not query then
    return from
  end
  local n = from
  for _, spell in ipairs(ns.HarmfulSpellIDs()) do
    if n == MAX_ICONS then
      break
    end
    local ok, aura = pcall(query, unit, spell.spellID)
    if ok and aura and ns.CastByPlayer(aura) then
      n = n + 1
      local slot = list[n] or {}
      list[n] = slot
      slot.icon = aura.icon or spell.icon
      slot.duration = ns.Secrets.Number(aura.duration)
      slot.expires = ns.Secrets.Number(aura.expirationTime)
      slot.name = aura.name or spell.name
      slot.stacks = ns.Secrets.Number(aura.applications)
    end
  end
  return n
end

-- sourceUnit can itself be withheld, so this never assumes it can be compared.
function ns.CastByPlayer(aura)
  local ok, mine = pcall(function()
    return aura.sourceUnit == "player"
  end)
  return ok and mine
end

-- Harmful spells you know that could leave something on a target, with their
-- IDs. Cached: the spellbook only changes when you learn something.
local harmfulCache
function ns.HarmfulSpellIDs()
  if harmfulCache then
    return harmfulCache
  end
  harmfulCache = {}
  local spells = ns.ScanSpellbook(true)
  for _, spell in ipairs(spells) do
    if spell.spellID and spell.helpful == false then
      harmfulCache[#harmfulCache + 1] = spell
    end
  end
  return harmfulCache
end

function ns.ForgetSpellbook()
  harmfulCache = nil
end

function ns.ReadTargetDebuffs(state)
  state.list = state.list or {}
  local unit = "target"
  state.count = 0
  state.name = nil
  local B = ns.Secrets.Bool
  local exists = UnitExists and B(UnitExists(unit), false)
  local canAttack = UnitCanAttack and B(UnitCanAttack("player", unit), false)
  if not exists or not canAttack then
    return state
  end
  state.name = UnitName(unit)
  local n = ScanDebuffs(unit, state.list)
  if n == 0 then
    -- Either nothing of yours is on it, or the scan was refused. Asking by
    -- spell ID costs nothing when the answer is the same.
    n = QueryDebuffs(unit, state.list, 0)
  end
  state.count = n
  return state
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function Countdown(slot, now)
  if not slot.expires or not slot.duration or slot.duration <= 0 then
    return nil -- no readable timer: show the icon, say nothing about time
  end
  return slot.expires - now
end

function ns.UpdateTargetTimers(now)
  if not frame or not frame:IsShown() then
    return
  end
  for i = 1, frame.state.count do
    local remaining = Countdown(frame.state.list[i], now)
    local timer = frame.icons[i].timer
    if not remaining then
      timer:SetText("")
    else
      timer:SetText(ns.FormatRemaining(remaining))
      if remaining <= WARNING then
        timer:SetTextColor(1, 0.3, 0.3)
      else
        timer:SetTextColor(1, 1, 1)
      end
    end
  end
end

-- Locking, unlocking and every refresh pass through here, so a failure in it
-- must never take them with it: whatever Forever does to aura access, moving
-- your frames has to keep working.
function ns.RenderTargetDebuffs()
  local ok, err = pcall(ns.DrawTargetDebuffs)
  if not ok and not ns.targetWarned then
    ns.targetWarned = true
    ns.Print("couldn't read the target's debuffs: " .. tostring(err))
  end
end

function ns.DrawTargetDebuffs()
  if not frame then
    return
  end
  local state = ns.ReadTargetDebuffs(frame.state)
  local wanted = ns.db.showTargetDebuffs and state.count > 0
  -- Unlocked, it stays put so you can drag it somewhere sensible.
  frame:SetShown(wanted or (ns.db.showTargetDebuffs and not ns.db.locked))

  frame.label:SetText(state.name or "No target")
  for i = 1, MAX_ICONS do
    local icon = frame.icons[i]
    local slot = i <= state.count and state.list[i]
    if slot then
      icon:Show()
      icon.texture:SetTexture(slot.icon)
      icon.stacks:SetText((slot.stacks or 0) > 1 and slot.stacks or "")
    else
      icon:Hide()
    end
  end
  ns.UpdateTargetTimers(GetTime())
end

function ns.CaptureTargetPosition()
  if not frame then
    return
  end
  local point, _, relative, x, y = frame:GetPoint()
  if point and x and y then
    ns.db.targetPosition = { point, relative, x, y }
  end
end

function ns.ApplyTargetPosition()
  if not frame then
    return
  end
  local p = ns.db.targetPosition
  frame:ClearAllPoints()
  frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

function ns.SetTargetLocked(locked)
  if not frame then
    return
  end
  frame:EnableMouse(not locked)
  frame.bg:SetShown(not locked)
  frame.label:SetShown(not locked)
  ns.RenderTargetDebuffs()
end

function ns.CreateTargetFrame()
  if frame then
    return frame
  end
  local size = ns.db.targetIconSize or 30
  frame = CreateFrame("Frame", "ForeverUIFramesTargetDebuffs", UIParent)
  frame:SetSize(MAX_ICONS * (size + 4), size + 16)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ns.CaptureTargetPosition()
  end)
  frame.state = { list = {}, count = 0 }

  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetAllPoints()
  frame.bg:SetColorTexture(0.30, 0.76, 1.00, 0.15)
  frame.bg:Hide()

  frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.label:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 2, 2)
  frame.label:Hide()

  frame.icons = {}
  for i = 1, MAX_ICONS do
    local icon = CreateFrame("Frame", nil, frame)
    icon:SetSize(size, size)
    icon:SetPoint("LEFT", (i - 1) * (size + 4), 0)

    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- trim the icon's border

    local edge = icon:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0, 0, 0, 1)

    icon.timer = icon:CreateFontString(nil, "OVERLAY", "ForeverUIFramesTinyFont")
    icon.timer:SetPoint("BOTTOM", 0, -1)

    icon.stacks = icon:CreateFontString(nil, "OVERLAY", "ForeverUIFramesTinyFont")
    icon.stacks:SetPoint("TOPRIGHT", 1, 1)

    icon:Hide()
    frame.icons[i] = icon
  end

  ns.targetFrame = frame
  ns.ApplyTargetPosition()
  ns.SetTargetLocked(ns.db.locked)
  return frame
end

function ns.ApplyTargetSize()
  if not frame then
    return
  end
  local size = ns.db.targetIconSize or 30
  frame:SetSize(MAX_ICONS * (size + 4), size + 16)
  for i, icon in ipairs(frame.icons) do
    icon:SetSize(size, size)
    icon:SetPoint("LEFT", (i - 1) * (size + 4), 0)
  end
end
