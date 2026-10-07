local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- A place of their own for the people you can't afford to lose.
--
-- The focus group is a second, separately movable set of frames: the game's
-- own focus target on top, and under it any players you have picked by name.
-- They are ordinary HealForever frames - same click-casting, same indicators -
-- so the tank can sit beside your cast bar while the raid stays where it was.
-- Picked players also keep their usual frame in the main group.

local SPACING = 2
local anchor, header, focusButton

local function Clean(name)
  name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return name ~= "" and name or nil
end

function ns.FocusNames()
  local names, seen = {}, {}
  for _, name in ipairs(ns.db.focusNames or {}) do
    name = Clean(name)
    if name and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  return names
end

function ns.IsFocusName(name)
  for _, listed in ipairs(ns.FocusNames()) do
    if listed == name then
      return true
    end
  end
  return false
end

-- Adds the player, or takes them out if they were already in. Returns whether
-- they are in the focus group afterwards.
function ns.ToggleFocusName(name)
  name = Clean(name)
  if not name then
    return false
  end
  local names, kept, found = ns.FocusNames(), {}, false
  for _, listed in ipairs(names) do
    if listed == name then
      found = true
    else
      kept[#kept + 1] = listed
    end
  end
  if not found then
    kept[#kept + 1] = name
  end
  ns.SetSetting("focusNames", kept)
  return not found
end

function ns.ClearFocusNames()
  ns.SetSetting("focusNames", {})
end

---------------------------------------------------------------------------
-- Where it sits
---------------------------------------------------------------------------

function ns.CaptureFocusPosition()
  if not anchor then
    return
  end
  local point, _, relative, x, y = anchor:GetPoint()
  if point and x and y then
    ns.db.focusPosition = { point, relative, x, y }
  end
end

function ns.ApplyFocusPosition()
  if not anchor or InCombatLockdown() then
    return
  end
  local p = ns.db.focusPosition or ns.DEFAULTS.focusPosition
  anchor:ClearAllPoints()
  anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

function ns.SetFocusLocked(locked)
  if not anchor then
    return
  end
  anchor:EnableMouse(not locked)
  anchor.bg:SetShown(not locked)
  anchor.rule:SetShown(not locked)
  anchor.label:SetShown(not locked)
end

---------------------------------------------------------------------------
-- The frames
---------------------------------------------------------------------------

-- Everything here touches secure frames, so it all waits for the end of a fight.
function ns.ApplyFocus()
  if not anchor then
    return
  end
  ns.WhenOutOfCombat(function()
    local width, height = ns.FrameSize()
    local show = ns.db.showFocus and true or false
    anchor:SetSize(width, 16)
    anchor:SetScale((ns.db.scale or 1) * (ns.db.focusScale or 1))
    anchor:SetShown(show)

    focusButton:SetSize(width, height)
    if show then
      RegisterUnitWatch(focusButton)
    else
      UnregisterUnitWatch(focusButton)
      focusButton:Hide()
    end

    header:SetAttribute("nameList", table.concat(ns.FocusNames(), ","))
    header:SetAttribute("yOffset", -SPACING)
    header:SetAttribute("minWidth", width)
    header:SetShown(show)
    local i, child = 1, header:GetAttribute("child1")
    while child do
      child:SetSize(width, height)
      i = i + 1
      child = header:GetAttribute("child" .. i)
    end
  end)
end

function ns.IsFocusButton(button)
  return button == focusButton or (header ~= nil and button:GetParent() == header)
end

function ns.CreateFocusFrames()
  if anchor then
    return anchor
  end
  anchor = CreateFrame("Frame", "ForeverUIFramesFocusAnchor", UIParent)
  anchor:SetSize(ns.db.frameWidth, 16)
  anchor:SetFrameStrata("MEDIUM")
  anchor:SetMovable(true)
  anchor:SetClampedToScreen(true)
  anchor:RegisterForDrag("LeftButton")
  anchor:SetScript("OnDragStart", function(self)
    if not InCombatLockdown() then
      self:StartMoving()
    end
  end)
  anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ns.CaptureFocusPosition()
  end)

  anchor.bg = anchor:CreateTexture(nil, "BACKGROUND")
  anchor.bg:SetAllPoints()
  anchor.bg:SetColorTexture(0.07, 0.07, 0.09, 0.85)
  anchor.rule = anchor:CreateTexture(nil, "BORDER")
  anchor.rule:SetPoint("TOPLEFT", -1, 1)
  anchor.rule:SetPoint("BOTTOMRIGHT", 1, -1)
  anchor.rule:SetColorTexture(1.00, 0.82, 0.20, 0.95)
  anchor.label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  anchor.label:SetPoint("CENTER")
  anchor.label:SetText("Focus - drag")
  anchor.label:SetTextColor(1.00, 0.82, 0.20)

  -- The game's own focus target. The unit watch shows it only while you have one.
  focusButton = CreateFrame("Button", "ForeverUIFramesFocusUnit", anchor, "ForeverUIFramesUnitButtonTemplate")
  focusButton:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -SPACING)
  focusButton:SetAttribute("unit", "focus")

  -- The players you picked. A header given names shows those names and nobody
  -- else, in the order they were given.
  header = CreateFrame("Frame", "ForeverUIFramesFocusHeader", anchor, "SecureGroupHeaderTemplate")
  header:SetAttribute("template", "ForeverUIFramesUnitButtonTemplate")
  header:SetAttribute("showPlayer", true)
  header:SetAttribute("showSolo", true)
  header:SetAttribute("showParty", true)
  header:SetAttribute("showRaid", true)
  header:SetAttribute("point", "TOP")
  header:SetAttribute("sortMethod", "NAMELIST")
  header:SetAttribute("nameList", "")
  header:SetPoint("TOPLEFT", focusButton, "BOTTOMLEFT", 0, -SPACING)

  ns.focusAnchor, ns.focusHeader, ns.focusButton = anchor, header, focusButton
  ns.ApplyFocusPosition()
  ns.SetFocusLocked(ns.db.locked)
  ns.ApplyFocus()
  return anchor
end
