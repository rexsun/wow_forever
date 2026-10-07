local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- Extra panels (docs/vuhdo-parity.md, phase 2 - VuhDo's "up to 10 panels").
--
-- Each panel is one more movable set of ordinary frames, same clicks and
-- indicators as the main grid, showing only part of the group:
--
--   tanks     main tanks, main assists and anyone set as a tank
--   healers   anyone set as a healer
--   group     one or more raid groups ("1" or "1,2")
--   class     one class ("PRIEST")
--   names     players you name, in that order
--   targets   your target, their target, your focus - the units VuhDo shows
--             as "Targets", clickable like everyone else
--
-- All filtering is the game's own secure group header (groupFilter,
-- roleFilter, nameList), so nothing here needs a secure snippet, and nothing
-- changes in a fight: panels are built and edited out of combat only.

local MAX_PANELS = 10
local SPACING = 2
ns.MAX_PANELS = MAX_PANELS

if ns.DEFAULTS.panels == nil then ns.DEFAULTS.panels = {} end

ns.PANEL_KINDS = {
  tanks = "Tanks",
  healers = "Healers",
  group = "Raid group",
  class = "Class",
  names = "Named players",
  targets = "Targets",
}

local TARGET_UNITS = { "target", "targettarget", "focus" }

local built = {}     -- index -> { anchor, header, units = { button... } }

local function Panels()
  if type(ns.db.panels) ~= "table" then ns.db.panels = {} end
  return ns.db.panels
end
ns.PanelList = Panels

local function Label(entry)
  local kind = ns.PANEL_KINDS[entry.kind] or entry.kind
  if entry.kind == "group" then return "Group " .. tostring(entry.value or "") end
  if entry.kind == "class" then
    local names = LOCALIZED_CLASS_NAMES_MALE
    return (names and names[entry.value]) or tostring(entry.value or kind)
  end
  if entry.kind == "names" then
    local first = tostring(entry.value or ""):match("^[^,]*") or ""
    return first ~= "" and ("Named: " .. first .. (entry.value:find(",", 1, true) and ", ..." or "")) or kind
  end
  return kind
end
ns.PanelLabel = Label

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

-- Returns the new panel's index, or nil (full, or nothing to show).
function ns.AddPanel(kind, value)
  if not ns.PANEL_KINDS[kind] then return nil end
  if (kind == "group" or kind == "class" or kind == "names")
    and (type(value) ~= "string" or value:gsub("%s", "") == "") then
    return nil
  end
  local list = Panels()
  if #list >= MAX_PANELS then return nil end
  if kind == "class" then value = value:upper() end
  if kind == "names" then
    local names = {}
    for raw in value:gmatch("[^,]+") do
      local name = raw:gsub("^%s+", ""):gsub("%s+$", "")
      if name ~= "" then names[#names + 1] = name end
    end
    value = table.concat(names, ",")
    if value == "" then return nil end
  end
  local offset = #list * 30
  list[#list + 1] = {
    kind = kind, value = value, shown = true, horizontal = false,
    position = { "CENTER", "CENTER", -260 + offset, 120 - offset },
  }
  list[#list].name = Label(list[#list])
  ns.SetSetting("panels", list)
  return #list
end

function ns.RemovePanel(index)
  local list = Panels()
  if not list[index] then return false end
  table.remove(list, index)
  ns.SetSetting("panels", list)
  return true
end

function ns.SetPanelField(index, field, value)
  local entry = Panels()[index]
  if not entry then return false end
  entry[field] = value
  ns.SetSetting("panels", Panels())
  return true
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local function CapturePosition(index)
  local set, entry = built[index], Panels()[index]
  if not set or not entry then return end
  local point, _, relative, x, y = set.anchor:GetPoint()
  if point and x and y then
    entry.position = { point, relative, x, y }
  end
end

function ns.CapturePanelPositions()
  for index in pairs(built) do CapturePosition(index) end
end

local function Build(index)
  if built[index] then return built[index] end
  local anchor = CreateFrame("Frame", "ForeverUIFramesPanelAnchor" .. index, UIParent)
  anchor:SetSize(ns.db.frameWidth or 120, 16)
  anchor:SetFrameStrata("MEDIUM")
  anchor:SetMovable(true)
  anchor:SetClampedToScreen(true)
  anchor:RegisterForDrag("LeftButton")
  anchor:SetScript("OnDragStart", function(self)
    if not InCombatLockdown() then self:StartMoving() end
  end)
  anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    CapturePosition(index)
  end)
  anchor.bg = anchor:CreateTexture(nil, "BACKGROUND")
  anchor.bg:SetAllPoints()
  anchor.bg:SetColorTexture(0.07, 0.07, 0.09, 0.85)
  anchor.rule = anchor:CreateTexture(nil, "BORDER")
  anchor.rule:SetPoint("TOPLEFT", -1, 1)
  anchor.rule:SetPoint("BOTTOMRIGHT", 1, -1)
  anchor.rule:SetColorTexture(0.30, 0.76, 1.00, 0.95)
  anchor.label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  anchor.label:SetPoint("CENTER")
  anchor.label:SetTextColor(0.30, 0.76, 1.00)

  local header = CreateFrame("Frame", "ForeverUIFramesPanelHeader" .. index, anchor, "SecureGroupHeaderTemplate")
  header:SetAttribute("template", "ForeverUIFramesUnitButtonTemplate")
  header:SetAttribute("showPlayer", true)
  header:SetAttribute("showParty", true)
  header:SetAttribute("showRaid", true)
  header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -SPACING)
  header.fuiPanel = index

  local units = {}
  for i, unit in ipairs(TARGET_UNITS) do
    local button = CreateFrame("Button", ("ForeverUIFramesPanel%dUnit%d"):format(index, i), anchor,
      "ForeverUIFramesUnitButtonTemplate")
    button.fuiPanelUnit = unit
    button:Hide()
    units[i] = button
  end

  built[index] = { anchor = anchor, header = header, units = units }
  return built[index]
end

-- Panel buttons for units outside the roster ("target", "focus") are routed
-- like the focus frame: by UnitIsUnit rather than by roster token.
function ns.IsPanelUnitButton(button)
  return button ~= nil and button.fuiPanelUnit ~= nil
end

local function ApplyOne(index, entry)
  local set = Build(index)
  local anchor, header = set.anchor, set.header
  local width, height = ns.FrameSize()
  local show = entry.shown ~= false
  anchor:SetSize(width, 16)
  anchor:SetScale((ns.db.scale or 1) * (entry.scale or 1))
  anchor.label:SetText((entry.name or Label(entry)) .. " - drag")
  local p = entry.position or { "CENTER", "CENTER", 0, 0 }
  anchor:ClearAllPoints()
  anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  anchor:SetShown(show)

  local horizontal = entry.horizontal and true or false
  local isTargets = entry.kind == "targets"
  -- The roster filter: exactly one of these, the rest cleared.
  header:SetAttribute("groupFilter", nil)
  header:SetAttribute("roleFilter", nil)
  header:SetAttribute("nameList", nil)
  header:SetAttribute("strictFiltering", nil)
  header:SetAttribute("sortMethod", "INDEX")
  if entry.kind == "tanks" then
    header:SetAttribute("roleFilter", "MAINTANK,MAINASSIST,TANK")
  elseif entry.kind == "healers" then
    header:SetAttribute("roleFilter", "HEALER")
  elseif entry.kind == "group" or entry.kind == "class" then
    header:SetAttribute("groupFilter", tostring(entry.value or ""))
  elseif entry.kind == "names" then
    header:SetAttribute("nameList", tostring(entry.value or ""))
    header:SetAttribute("sortMethod", "NAMELIST")
  end
  header:SetAttribute("showSolo", entry.kind == "names")
  header:SetAttribute("point", horizontal and "LEFT" or "TOP")
  header:SetAttribute("xOffset", horizontal and SPACING or 0)
  header:SetAttribute("yOffset", horizontal and 0 or -SPACING)
  header:SetAttribute("minWidth", width)
  header:SetShown(show and not isTargets)
  local i, child = 1, header:GetAttribute("child1")
  while child do
    child:SetSize(width, height)
    i = i + 1
    child = header:GetAttribute("child" .. i)
  end

  -- The targets strip.
  local previous
  for n, button in ipairs(set.units) do
    button:SetSize(width, height)
    button:ClearAllPoints()
    if not previous then
      button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -SPACING)
    elseif horizontal then
      button:SetPoint("TOPLEFT", previous, "TOPRIGHT", SPACING, 0)
    else
      button:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -SPACING)
    end
    previous = button
    if show and isTargets then
      button:SetAttribute("unit", TARGET_UNITS[n])
      RegisterUnitWatch(button)
    else
      UnregisterUnitWatch(button)
      button:Hide()
    end
  end
end

local function HideOne(index)
  local set = built[index]
  if not set then return end
  set.anchor:Hide()
  set.header:Hide()
  for _, button in ipairs(set.units) do
    UnregisterUnitWatch(button)
    button:Hide()
  end
end

-- Everything here touches secure frames, so it waits for the end of a fight.
function ns.ApplyPanels()
  ns.WhenOutOfCombat(function()
    local list = Panels()
    for index = 1, MAX_PANELS do
      if list[index] then
        ApplyOne(index, list[index])
      else
        HideOne(index)
      end
    end
    ns.SetPanelsLocked(ns.db.locked)
    if ns.ApplyBindings then ns.ApplyBindings() end
  end)
end

function ns.SetPanelsLocked(locked)
  for index, set in pairs(built) do
    local on = Panels()[index] ~= nil
    set.anchor:EnableMouse(on and not locked)
    set.anchor.bg:SetShown(not locked)
    set.anchor.rule:SetShown(not locked)
    set.anchor.label:SetShown(not locked)
  end
end

function ns.PanelFrames(index)
  return built[index]
end

-- Target of target has no events of its own: redraw the strips twice a second.
local ticker = CreateFrame("Frame")
local since = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
  since = since + elapsed
  if since < 0.5 then return end
  since = 0
  for _, set in pairs(built) do
    for _, button in ipairs(set.units) do
      if button.unit and button:IsShown() then ns.Refresh(button) end
    end
  end
end)

ns.SETTING_APPLY.panels = function() ns.ApplyPanels() end
