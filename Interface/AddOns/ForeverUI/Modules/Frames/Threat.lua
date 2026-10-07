local _, FUI = ...
FUI.Frames = FUI.Frames or {}
local ns = FUI.Frames

-- The alarm.
--
-- The frames say who is in trouble; this says it where you are already
-- looking. One line in the middle of the screen, and a sound the first time
-- it happens:
--
--     AGGRO: Frosty x2, Healbot          someone who isn't a tank has a mob
--     NOT ON YOU: Defias Pillager        you are fighting it and it isn't yours
--
-- It is rebuilt from what the frames already worked out (button.state), so it
-- costs nothing extra and can't disagree with them.

local SOUND_GAP = 3 -- seconds between alarm sounds, however bad it gets
local frame, lastSound, lastCount = nil, 0, 0

function ns.CaptureAlertPosition()
  if not frame then
    return
  end
  local point, _, relative, x, y = frame:GetPoint()
  if point and x and y then
    ns.db.alertPosition = { point, relative, x, y }
  end
end

function ns.ApplyAlertPosition()
  if not frame then
    return
  end
  local p = ns.db.alertPosition or ns.DEFAULTS.alertPosition
  frame:ClearAllPoints()
  frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

function ns.SetAlertLocked(locked)
  if not frame then
    return
  end
  frame:EnableMouse(not locked)
  frame.bg:SetShown(not locked)
  if not locked then
    frame.text:SetText("|cffff2222AGGRO: Frosty x2|r  (threat alarm - drag)")
    frame:Show()
  else
    ns.UpdateThreatAlert()
  end
end

function ns.CreateThreatAlert()
  if frame then
    return frame
  end
  frame = CreateFrame("Frame", "ForeverUIFramesAlert", UIParent)
  frame:SetSize(520, 40)
  frame:SetFrameStrata("HIGH")
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ns.CaptureAlertPosition()
  end)
  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetAllPoints()
  frame.bg:SetColorTexture(1, 0.1, 0.1, 0.18)
  frame.bg:Hide()
  frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  frame.text:SetPoint("CENTER")
  frame.text:SetShadowOffset(2, -2)
  frame:Hide()
  ns.alertFrame = frame
  ns.ApplyAlertPosition()
  ns.SetAlertLocked(ns.db.locked)
  return frame
end

-- Everyone who has a mob and shouldn't, worst first. Focus frames repeat
-- people from the main group, so each name counts once.
function ns.LoosePlayers()
  local list, seen = {}, {}
  -- In a group names are SECRET: no table key, no "<", no concatenation.
  -- Those are counted by unit instead and listed without a name.
  ns.ForEachButton(function(button)
    local s = button.state
    local name = s and s.name
    if issecretvalue and issecretvalue(name) then name = nil end
    local key = name or (button.unit and ("unit:" .. button.unit))
    if s and s.loose and key and not seen[key] and not (s.dead or s.ghost or s.offline) then
      seen[key] = true
      list[#list + 1] = { name = name, mobs = s.mobCount or 0, unit = button.unit }
    end
  end)
  table.sort(list, function(a, b)
    if a.mobs ~= b.mobs then
      return a.mobs > b.mobs
    end
    return (a.name or a.unit or "") < (b.name or b.unit or "")
  end)
  return list
end

-- Are you fighting something that is on somebody else? Asked about you and
-- your target, which the game answers even where it hides most things.
local function LostMyTarget()
  if not (UnitAffectingCombat and UnitThreatSituation and UnitCanAttack) then
    return false
  end
  local B = ns.Secrets.Bool
  if not B(UnitAffectingCombat("player"), false) or not B(UnitExists("target"), false)
    or not B(UnitCanAttack("player", "target"), false) or B(UnitIsDead("target"), false) then
    return false
  end
  local status = UnitThreatSituation("player", "target")
  return status ~= nil and status < 2
end

local function Sound()
  if not ns.db.threatSound or not PlaySound then
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

function ns.UpdateThreatAlert()
  if ns.UpdateLooseList then
    ns.UpdateLooseList() -- the same list, as clickable slots
  end
  if not frame or not ns.db.locked then
    return
  end
  if not ns.db.threatAlert or not ns.db.showThreat then
    frame:Hide()
    lastCount = 0
    return
  end
  local loose = ns.LoosePlayers()
  if #loose > 0 then
    local parts = {}
    for i, entry in ipairs(loose) do
      if i > 4 then
        parts[#parts + 1] = ("+%d more"):format(#loose - 4)
        break
      end
      local who = entry.name or "someone"
      parts[#parts + 1] = entry.mobs > 1 and ("%s x%d"):format(who, entry.mobs) or who
    end
    frame.text:SetText("|cffff2222AGGRO:|r |cffffffff" .. table.concat(parts, ", ") .. "|r")
    frame:Show()
    if #loose > lastCount then
      Sound() -- only when it gets worse, not on every refresh
    end
    lastCount = #loose
    return
  end
  lastCount = 0
  local ok, lost = pcall(LostMyTarget)
  if ok and lost and ns.db.alertLostTarget then
    -- The name may be a secret string: handed to the font string, never read.
    frame.text:SetFormattedText("|cffffaa22NOT ON YOU:|r %s", UnitName("target"))
    frame:Show()
  else
    frame:Hide()
  end
end
