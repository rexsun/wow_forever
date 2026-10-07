local _, FUI = ...
FUI.Frames = FUI.Frames or {}
local ns = FUI.Frames

-- "IT'S ON YOU" -- the damage dealer's alarm (DPS Forever, 27 Sept 2026).
--
-- The tank's alarm reads threat, and in a group this client hides threat.
-- What a damage dealer needs to know is simpler anyway: the thing you are
-- hitting has turned round and is hitting you. That is "is my target's
-- target me?" -- UnitIsUnit("targettarget", "player") -- and in a group that
-- answer is a SECRET boolean: it can't be tested, only handed on. So the
-- warning is always there while you fight in a group, and the game sets its
-- alpha from the secret answer (ns.Secrets.Choose -> EvaluateColorValueFromBoolean):
-- fully shown when it's on you, invisible when it isn't. Nothing is ever read.
--
-- The sound needs a yes or no, so it only plays when the answer is plain.
-- Solo it stays quiet: on your own everything is on you.

local SOUND_GAP = 3
local TICK = 0.2
local frame, driver, lastSound, wasOnYou = nil, nil, 0, false

local function Wanted()
  return ns.db and ns.db.onYouAlert and ns.GetMode and ns.GetMode() == "dps"
end

-- Fighting something that can be fought, in a group. All plain questions,
-- guarded anyway: the answer is "no" whenever the game won't say.
local function Fighting()
  local B = ns.Secrets.Bool
  if not (IsInGroup and B(IsInGroup(), false)) then
    return false
  end
  return B(UnitAffectingCombat("player"), false)
    and B(UnitExists("target"), false)
    and B(UnitCanAttack("player", "target"), false)
    and not B(UnitIsDead("target"), true)
end

local function Sound()
  if not ns.db.onYouSound or not PlaySound then
    return
  end
  local now = GetTime()
  if now - lastSound < SOUND_GAP then
    return
  end
  lastSound = now
  local kit = SOUNDKIT and (SOUNDKIT.RAID_WARNING or SOUNDKIT.ALARM_CLOCK_WARNING_3)
  pcall(PlaySound, kit or 8959, "Master")
end

function ns.UpdateOnYou()
  if not frame then
    return
  end
  if not ns.db.locked then
    return   -- being dragged: the sample text stays up
  end
  if not Wanted() or not Fighting() then
    frame:Hide()
    wasOnYou = false
    return
  end
  local onYou = UnitIsUnit("targettarget", "player")
  frame:SetAlpha(ns.Secrets.Choose(onYou, 1, 0, 0))
  -- The name may be secret too: handed to the font string, never read.
  frame.text:SetFormattedText("|cffff3333IT'S ON YOU:|r %s", UnitName("target"))
  frame:Show()
  local plain = ns.Secrets.Bool(onYou, nil)
  if plain == true and not wasOnYou then
    Sound()
  end
  wasOnYou = plain == true
end

function ns.CaptureOnYouPosition()
  if not frame then
    return
  end
  local point, _, relative, x, y = frame:GetPoint()
  if point and x and y then
    ns.db.onYouPosition = { point, relative, x, y }
  end
end

function ns.ApplyOnYouPosition()
  if not frame then
    return
  end
  local p = ns.db.onYouPosition or ns.DEFAULTS.onYouPosition
  frame:ClearAllPoints()
  frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

function ns.SetOnYouLocked(locked)
  if not frame then
    return
  end
  frame:EnableMouse(not locked)
  frame.bg:SetShown(not locked)
  if not locked then
    frame:SetAlpha(1)
    frame.text:SetText("|cffff3333IT'S ON YOU:|r Defias Pillager  (drag to move)")
    frame:Show()
  else
    ns.UpdateOnYou()
  end
end

function ns.CreateOnYou()
  if frame then
    return frame
  end
  frame = CreateFrame("Frame", "ForeverUIFramesOnYou", UIParent)
  frame:SetSize(520, 44)
  frame:SetFrameStrata("HIGH")
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ns.CaptureOnYouPosition()
  end)
  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetAllPoints()
  frame.bg:SetColorTexture(1, 0.1, 0.1, 0.18)
  frame.bg:Hide()
  frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  frame.text:SetPoint("CENTER")
  frame.text:SetShadowOffset(2, -2)
  frame:Hide()
  ns.onYouFrame = frame
  ns.ApplyOnYouPosition()

  -- Who your target is fighting changes without an event of its own, so a
  -- light tick while you are in combat, and the events that start and stop it.
  driver = CreateFrame("Frame")
  local elapsed = 0
  driver:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed >= TICK then
      elapsed = 0
      ns.UpdateOnYou()
    end
  end)
  driver:Hide()
  local events = CreateFrame("Frame")
  for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE" }) do
    pcall(events.RegisterEvent, events, event)
  end
  events:SetScript("OnEvent", function(_, event)
    local fighting = event == "PLAYER_REGEN_DISABLED" or (event ~= "PLAYER_REGEN_ENABLED" and InCombatLockdown())
    driver:SetShown(fighting and Wanted() and true or false)
    ns.UpdateOnYou()
  end)
  ns.onYouDriver, ns.onYouEvents = driver, events

  ns.SetOnYouLocked(ns.db.locked)
  return frame
end
