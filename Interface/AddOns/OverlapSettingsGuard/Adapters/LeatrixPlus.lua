local _, OSG = ...

-- Leatrix Plus keeps its live values in file-local tables and writes LeaPlusDB only at
-- logout, so the only way in is its option checkboxes. They have no names; each one is
-- found by its page and anchor offsets, which do not depend on the game language.
-- Positions are from Leatrix_Plus.lua 1.60.11 (lines 13813-13991). `reload` must match
-- the "*" Leatrix adds to the label of a reload-only option, a second check that the
-- right box was found.
local TESTED_VERSION = "1.60.11"
local PAGE_COUNT = 10
local SPOTS = {
  AutomateQuests = { page = 1, x = 146, y = -92, reload = false },
  AutomateGossip = { page = 1, x = 146, y = -112, reload = false },
  MoveChatEditBoxToTop = { page = 3, x = 146, y = -192, reload = true },
  SetChatFontSize = { page = 3, x = 146, y = -212, reload = true },
  MinimapModder = { page = 5, x = 146, y = -92, reload = true },
  ShowFlightTimes = { page = 7, x = 340, y = -252, reload = true },
}
local LOCK_NOTE = "|n|n|cffff6040Locked off by OverlapSettingsGuard.|r"

local adapter = {}
OSG.adapters.LeatrixPlus = adapter

local boxes = {}
local reverting = false

local function Near(a, b)
  return type(a) == "number" and math.abs(a - b) < 0.5
end

local function VersionNote()
  local version = C_AddOns.GetAddOnMetadata("Leatrix_Plus", "Version") or "?"
  if version == TESTED_VERSION then
    return ""
  end
  return (" (Leatrix Plus %s; positions were taken from %s)"):format(version, TESTED_VERSION)
end

-- Page0..Page9 are the panel's children that fill it and carry a title (`.s`), in the
-- order Leatrix creates them.
local function FindPages(panel)
  local pages = {}
  for _, child in ipairs({ panel:GetChildren() }) do
    if child:GetObjectType() == "Frame" and child.s and child:GetNumPoints() == 2 then
      local _, relativeTo = child:GetPoint(1)
      if relativeTo == panel then
        pages[#pages + 1] = child
      end
    end
  end
  if #pages ~= PAGE_COUNT then
    return nil, ("found %d option pages, expected %d"):format(#pages, PAGE_COUNT)
  end
  return pages
end

local function FindBox(page, spot)
  for _, child in ipairs({ page:GetChildren() }) do
    if child:GetObjectType() == "CheckButton" and child.f then
      local point, relativeTo, _, x, y = child:GetPoint(1)
      if point == "TOPLEFT" and relativeTo == page and Near(x, spot.x) and Near(y, spot.y) then
        local starred = (child.f:GetText() or ""):sub(-1) == "*"
        if starred ~= spot.reload then
          return nil, "the checkbox at that spot is a different option"
        end
        return child
      end
    end
  end
  return nil, "no checkbox at that spot"
end

local function Box(key)
  if boxes[key] then
    return boxes[key]
  end
  local spot = SPOTS[key]
  local panel = _G.LeaPlusGlobalPanel
  if not panel then
    return nil, "Leatrix Plus has no options panel" .. VersionNote()
  end
  local pages, problem = FindPages(panel)
  if not pages then
    return nil, problem .. VersionNote()
  end
  local box
  box, problem = FindBox(pages[spot.page + 1], spot)
  if not box then
    return nil, problem .. VersionNote()
  end
  boxes[key] = box
  return box
end

function adapter.Knows(key)
  return SPOTS[key] ~= nil
end

-- The box's own OnShow re-reads Leatrix's live value without firing OnClick.
function adapter.Read(key)
  local box, problem = Box(key)
  if not box then
    return nil, problem
  end
  local onShow = box:GetScript("OnShow")
  if not onShow then
    return nil, "the checkbox has no OnShow handler" .. VersionNote()
  end
  onShow(box)
  return box:GetChecked() and true or false
end

-- Click() runs Leatrix's own handlers, so its value, the reload button and any feature
-- hooked to the box (Automate quests/gossip) all switch off the normal way. A reload is
-- needed only when the running value, loaded at login into LeaPlusDB, was on.
-- Click() toggles, and a box never shown since login holds a stale state, so the live
-- value is read into the box first.
function adapter.Revert(key)
  local on, problem = adapter.Read(key)
  if on == nil then
    return false, problem
  end
  if not on then
    return true, false
  end
  local box = boxes[key]
  if not box:IsEnabled() then
    return false, "Leatrix Plus has locked the checkbox"
  end
  reverting = true
  local ok, err = pcall(box.Click, box)
  reverting = false
  if not ok then
    return false, tostring(err)
  end
  if adapter.Read(key) then
    return false, "the checkbox did not switch off"
  end
  local running = type(_G.LeaPlusDB) == "table" and _G.LeaPlusDB[key] == "On"
  return true, SPOTS[key].reload and running
end

function adapter.Watch(onChange)
  for key in pairs(SPOTS) do
    local box = Box(key)
    if box then
      box:HookScript("OnClick", function()
        if not reverting then
          onChange()
        end
      end)
      box.tiptext = (box.tiptext or "") .. LOCK_NOTE
    end
  end
  local panel = _G.LeaPlusGlobalPanel
  if panel then
    panel:HookScript("OnHide", onChange)
  end
end
