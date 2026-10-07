local _, FUI = ...
FUI.Frames = FUI.Frames or {}
local ns = FUI.Frames

-- Loose players at the top.
--
-- The obvious way - re-sort the group so whoever has a mob floats up - is not
-- available: the game locks the position and the unit of every clickable
-- frame for the length of a fight, which is exactly when this matters. So the
-- list is its own short stack of slots, built in two layers:
--
--   underneath  a secure button per slot, fixed in place, whose unit is
--               "mouseover" and which carries all your click bindings. It never
--               changes, so combat has nothing to object to. A visibility
--               driver keeps it out of the way outside a fight.
--   on top      an ordinary frame that draws the player (name, mob count,
--               health). Ordinary frames can change freely in combat, so THIS
--               is what gets re-pointed at whoever is loose. It takes mouse
--               movement only - its "unit" makes that player your mouseover -
--               and lets the click fall through to the button below.
--
-- Hover the slot and "mouseover" is the loose player; click and the binding
-- underneath acts on mouseover (or mouseover's target). The result behaves
-- like a frame that re-sorts itself, without anything secure ever moving.

local SLOTS = 5
local SPACING = 2
local holder, slots = nil, {}

local function Size()
  local w, h = ns.FrameSize()
  return w, math.max(18, math.floor(h * 0.7))
end

function ns.CaptureLoosePosition()
  if not holder then
    return
  end
  local point, _, relative, x, y = holder:GetPoint()
  if point and x and y then
    ns.db.loosePosition = { point, relative, x, y }
  end
end

function ns.ApplyLoosePosition()
  if not holder or InCombatLockdown() then
    return
  end
  local p = ns.db.loosePosition or ns.DEFAULTS.loosePosition
  holder:ClearAllPoints()
  holder:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

-- The secure half: sizes, bindings and whether it exists at all. Out of combat only.
function ns.ApplyLooseList()
  if not holder then
    return
  end
  ns.WhenOutOfCombat(function()
    local w, h = Size()
    local on = ns.db.looseList and true or false
    holder:SetSize(w, 14)
    holder:SetScale(ns.db.scale or 1)
    for i, slot in ipairs(slots) do
      slot.button:SetSize(w, h)
      slot.face:SetSize(w, h)
      ns.BindButton(slot.button)
      if RegisterStateDriver then
        if on then
          RegisterStateDriver(slot.button, "visibility", "[combat] show; hide")
        else
          if UnregisterStateDriver then UnregisterStateDriver(slot.button, "visibility") end
          slot.button:Hide()
        end
      else
        slot.button:SetShown(on)
      end
      if not on then
        slot.face:Hide()
      end
      slot.index = i
    end
    ns.UpdateLooseList()
  end)
end

-- Bindings changed: the slot buttons carry them too.
function ns.BindLooseSlots()
  for _, slot in ipairs(slots) do
    ns.BindButton(slot.button)
  end
end

function ns.SetLooseLocked(locked)
  if not holder then
    return
  end
  holder:EnableMouse(not locked)
  holder.bg:SetShown(not locked)
  holder.label:SetShown(not locked)
  ns.UpdateLooseList()
end

local function Paint(slot, entry)
  local face = slot.face
  -- A secret name can still be SHOWN (SetText takes it), just not compared.
  face.name:SetText(entry.name or (entry.unit and UnitName and UnitName(entry.unit)) or "?")
  face.count:SetText(entry.mobs > 1 and ("x" .. entry.mobs) or "")
  if entry.unit and UnitHealth then
    -- Health may be secret: a status bar will draw it, nothing here reads it.
    pcall(ns.Secrets.SetBar, face.health, UnitHealth(entry.unit), UnitHealthMax(entry.unit))
  end
end

-- The free half: who is in which slot. Safe at any time, including mid-fight.
function ns.UpdateLooseList()
  if not holder then
    return
  end
  local sample = not ns.db.locked
  local list = {}
  if ns.db.looseList then
    list = sample and { { name = "Frosty", mobs = 2 }, { name = "Healbot", mobs = 1 } } or ns.LoosePlayers()
  end
  for i, slot in ipairs(slots) do
    local entry = list[i]
    if entry then
      slot.face:SetAttribute("unit", entry.unit) -- hovering this slot = hovering them
      slot.face.unit = entry.unit
      Paint(slot, entry)
      slot.face:Show()
    else
      slot.face:SetAttribute("unit", nil)
      slot.face.unit = nil
      slot.face:Hide()
    end
  end
  holder.title:SetShown(#list > 0)
end

-- Health on the faces moves with the fight.
function ns.TickLooseList()
  for _, slot in ipairs(slots) do
    if slot.face.unit and slot.face:IsShown() and UnitHealth then
      pcall(ns.Secrets.SetBar, slot.face.health, UnitHealth(slot.face.unit), UnitHealthMax(slot.face.unit))
    end
  end
end

function ns.CreateLooseList()
  if holder then
    return holder
  end
  holder = CreateFrame("Frame", "ForeverUIFramesLooseList", UIParent)
  holder:SetSize(ns.db.frameWidth, 14)
  holder:SetFrameStrata("MEDIUM")
  holder:SetMovable(true)
  holder:SetClampedToScreen(true)
  holder:RegisterForDrag("LeftButton")
  holder:SetScript("OnDragStart", function(self)
    if not InCombatLockdown() then
      self:StartMoving()
    end
  end)
  holder:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ns.CaptureLoosePosition()
  end)
  holder.bg = holder:CreateTexture(nil, "BACKGROUND")
  holder.bg:SetAllPoints()
  holder.bg:SetColorTexture(1, 0.1, 0.1, 0.35)
  holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  holder.label:SetPoint("CENTER")
  holder.label:SetText("Loose list - drag")
  holder.title = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  holder.title:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 2, 1)
  holder.title:SetText("|cffff3333LOOSE|r")
  holder.title:Hide()

  local w, h = Size()
  for i = 1, SLOTS do
    local button = CreateFrame("Button", "ForeverUIFramesLooseSlot" .. i, holder, "SecureActionButtonTemplate")
    button:SetSize(w, h)
    button:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -SPACING - (i - 1) * (h + SPACING))
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("unit", "mouseover")
    button:Hide()

    local face = CreateFrame("Frame", nil, UIParent)
    face:SetSize(w, h)
    face:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    face:SetFrameStrata("MEDIUM")
    face:SetFrameLevel((button.GetFrameLevel and button:GetFrameLevel() or 1) + 5)
    if face.SetMouseClickEnabled then
      face:SetMouseClickEnabled(false) -- the click belongs to the button underneath
      face:SetMouseMotionEnabled(true) -- the hover belongs to us: it sets mouseover
    else
      face:EnableMouse(false)
    end
    face.edge = face:CreateTexture(nil, "BACKGROUND")
    face.edge:SetAllPoints()
    face.edge:SetColorTexture(1, 0.10, 0.10, 1)
    face.health = CreateFrame("StatusBar", nil, face)
    face.health:SetPoint("TOPLEFT", 2, -2)
    face.health:SetPoint("BOTTOMRIGHT", -2, 2)
    face.health:SetStatusBarTexture(ns.db.barTexture)
    face.health:SetStatusBarColor(0.55, 0.10, 0.10)
    face.health.bg = face.health:CreateTexture(nil, "BACKGROUND")
    face.health.bg:SetAllPoints()
    face.health.bg:SetColorTexture(0.10, 0.02, 0.02, 1)
    face.name = face.health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    face.name:SetPoint("LEFT", 4, 0)
    face.count = face.health:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    face.count:SetPoint("RIGHT", -4, 0)
    face.count:SetTextColor(1, 0.9, 0.3)
    face:Hide()

    slots[i] = { button = button, face = face }
  end

  ns.looseHolder, ns.looseSlots = holder, slots
  ns.ApplyLoosePosition()
  ns.SetLooseLocked(ns.db.locked)
  ns.ApplyLooseList()
  return holder
end
