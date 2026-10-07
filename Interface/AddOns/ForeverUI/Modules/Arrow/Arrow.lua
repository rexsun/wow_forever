local _, ns = ...

-- The waypoint arrow (owner, 23 Sept 2026): "when I am on a quest or I have
-- marked a point that I am going to, put an arrow pointing the way above the
-- head of the character ... make sure the arrow is 3D ... give varieties".
--
-- It points at, in order: the pin you dropped on the map, the quest you are
-- tracking (clicked in the log or the tracker), or - if you let it - the
-- nearest quest in your log. The arrows are ChatGPT's (white and grey 3D art,
-- Media/arrows/arrow-<style>.tga), tinted to any colour and turned in place.
--
-- The sums use the player's own position and facing, never another unit's,
-- and every reading goes through a guard: a value the client hides, or a
-- question it won't answer (facing, in an instance), hides the arrow rather
-- than pointing it somewhere wrong.

local module = ns.RegisterModule({
  name = "Arrow",
  title = "Waypoint Arrow",
})

-- What the game's Key Bindings window calls ForeverUI's keys (Bindings.xml).
_G.BINDING_HEADER_FOREVERUI = "ForeverUI"
_G.BINDING_NAME_FOREVERUI_TOGGLE_ARROW = "Waypoint arrow on/off"

module.STYLES = { "classic", "chevron", "crystal", "rounded", "double", "spear" }
module.STYLE_LABELS = {
  classic = "Classic", chevron = "Chevron", crystal = "Crystal",
  rounded = "Rounded", double = "Double chevron", spear = "Spear",
}

module.defaults = {
  shown = true,          -- the quick on/off: /fui arrow, a key, the page's top switch
  style = "classic",
  color = { 1.00, 0.82, 0.20 },  -- quest gold
  size = 56,
  alpha = 1,
  target = "auto",       -- auto (pin, then tracked, then nearest) | pin | quest
  showDistance = true,
  showLabel = true,
  arriveRange = 8,       -- yards: close enough to a pin to put the arrow away
  hideInCombat = false,
}

local frame, arrow, distance, label
local atan2 = math.atan2 or math.atan

local function Settings()
  return ns.db.modules.Arrow
end

function module.ArrowTexture(style)
  return ns.MEDIA_PATH .. "arrows\\arrow-" .. (style or "classic")
end

local function Plain(value)
  return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end

local function Try(fn, ...)
  if not fn then return nil end
  local results = { pcall(fn, ...) }
  if not results[1] then return nil end
  return unpack(results, 2)
end

local function XY(point)
  if type(point) ~= "table" then return nil end
  if point.GetXY then
    local x, y = point:GetXY()
    return x, y
  end
  return point.x, point.y
end

---------------------------------------------------------------------------
-- Where things are
---------------------------------------------------------------------------

-- The player: which map, and where on it (0..1 across and down).
local function PlayerPosition()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then
    return nil
  end
  local map = Try(C_Map.GetBestMapForUnit, "player")
  if not Plain(map) then return nil end
  local x, y = XY(Try(C_Map.GetPlayerMapPosition, map, "player"))
  if not (Plain(x) and Plain(y)) or (x == 0 and y == 0) then return nil end
  return map, x, y
end
module.PlayerPosition = PlayerPosition

-- A spot on a map in world yards: north is +x and west is +y, as the game
-- keeps them. The continent too, so two spots can be compared at all.
local function World(map, x, y)
  if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
    local continent, pos = Try(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    local wx, wy = XY(pos)
    if Plain(wx) and Plain(wy) then
      return continent, wx, wy
    end
  end
  return nil
end

-- The pin you dropped on the map.
local function Pin()
  if not (C_Map and C_Map.HasUserWaypoint and C_Map.GetUserWaypoint) then return nil end
  if not Try(C_Map.HasUserWaypoint) then return nil end
  local point = Try(C_Map.GetUserWaypoint)
  if type(point) ~= "table" then return nil end
  local x, y = XY(point.position)
  if not (Plain(point.uiMapID) and Plain(x) and Plain(y)) then return nil end
  return { map = point.uiMapID, x = x, y = y, name = "Map pin", pin = true }
end

-- Where a quest wants you next, however this client will say it.
local function QuestSpot(questID, playerMap)
  if C_QuestLog and C_QuestLog.GetNextWaypoint then
    local map, x, y = Try(C_QuestLog.GetNextWaypoint, questID)
    if Plain(map) and Plain(x) and Plain(y) then
      return map, x, y
    end
  end
  if C_QuestLog and C_QuestLog.GetQuestsOnMap and playerMap then
    for _, info in ipairs(Try(C_QuestLog.GetQuestsOnMap, playerMap) or {}) do
      if info.questID == questID and Plain(info.x) and Plain(info.y) then
        return playerMap, info.x, info.y
      end
    end
  end
  if QuestPOIGetIconInfo and playerMap then
    local _, x, y = Try(QuestPOIGetIconInfo, questID)
    if Plain(x) and Plain(y) then
      return playerMap, x, y
    end
  end
  return nil
end
module.QuestSpot = QuestSpot

local function QuestTitle(questID)
  local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and Try(C_QuestLog.GetTitleForQuestID, questID)
  return type(title) == "string" and title or "Quest"
end

-- The quest you are tracking; failing that, if asked, the nearest in the log.
local function Quest(playerMap, allowNearest)
  local tracked = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
    and Try(C_SuperTrack.GetSuperTrackedQuestID)
  local candidates = {}
  if Plain(tracked) and tracked > 0 then
    candidates[1] = tracked
  elseif allowNearest then
    local quests = ns.GetModule("Quests")
    local list = quests and quests.ReadQuests and Try(quests.ReadQuests) or {}
    table.sort(list, function(a, b) return (a.yards or math.huge) < (b.yards or math.huge) end)
    for _, q in ipairs(list) do
      candidates[#candidates + 1] = q.id
    end
  end
  for _, questID in ipairs(candidates) do
    local map, x, y = QuestSpot(questID, playerMap)
    if map then
      return { map = map, x = x, y = y, name = QuestTitle(questID), questID = questID }
    end
  end
  return nil
end

function module.Target(playerMap)
  local mode = Settings().target or "auto"
  if mode ~= "quest" then
    local pin = Pin()
    if pin or mode == "pin" then
      return pin
    end
  end
  return Quest(playerMap, mode == "auto")
end

-- Which way, and how far: the turn from where you face (radians, turning
-- left is positive, as the game counts facing) and the distance in yards.
function module.Bearing(map, px, py, target)
  local c1, ax, ay = World(map, px, py)
  local c2, bx, by = World(target.map, target.x, target.y)
  local north, west
  if ax and bx and c1 == c2 then
    north, west = bx - ax, by - ay
  elseif target.map == map and C_Map and C_Map.GetMapWorldSize then
    -- Same map, no world positions: the map's own size in yards.
    local w, h = Try(C_Map.GetMapWorldSize, map)
    if not (Plain(w) and Plain(h)) or w <= 0 then return nil end
    north, west = (py - target.y) * h, (px - target.x) * w
  else
    return nil
  end
  local yards = math.sqrt(north * north + west * west)
  return atan2(west, north), yards
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function Hide()
  if frame then frame:Hide() end
  module.showing = nil
end

local function Paint()
  local s = Settings()
  local size = s.size or 56
  frame:SetSize(size, size + 30)
  arrow:SetSize(size, size)
  arrow:SetTexture(module.ArrowTexture(s.style))
  local c = s.color or module.defaults.color
  arrow:SetVertexColor(c[1], c[2], c[3], 1)
  frame:SetAlpha(s.alpha or 1)
  distance:SetShown(s.showDistance ~= false)
  label:SetShown(s.showLabel ~= false)
  if ns.UpdateMoverSize then
    ns.UpdateMoverSize("arrow", size, size + 30)
  end
end
module.Paint = Paint

function module.Update()
  if not frame then return end
  local s = Settings()
  if s.shown == false then
    return Hide()
  end
  if s.hideInCombat and InCombatLockdown and InCombatLockdown() then
    return Hide()
  end
  local map, px, py = PlayerPosition()
  if not map then return Hide() end
  local target = module.Target(map)
  if not target then return Hide() end
  local bearing, yards = module.Bearing(map, px, py, target)
  local facing = GetPlayerFacing and Try(GetPlayerFacing)
  if not (bearing and Plain(facing)) then return Hide() end
  if target.pin and yards <= (s.arriveRange or 8) then
    return Hide()
  end
  module.lastRotation = bearing - facing
  arrow:SetRotation(module.lastRotation)
  distance:SetText(("%d yd"):format(math.floor(yards + 0.5)))
  label:SetText(target.name or "")
  module.showing, module.lastTarget, module.lastYards = true, target, yards
  frame:Show()
end

local function Build()
  frame = CreateFrame("Frame", "ForeverUIArrow", UIParent)
  frame:SetFrameStrata("MEDIUM")
  frame:SetSize(56, 86)
  arrow = frame:CreateTexture(nil, "ARTWORK")
  arrow:SetPoint("TOP")
  distance = frame:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(distance, "dataText")
  distance:SetPoint("TOP", arrow, "BOTTOM", 0, -2)
  distance:SetTextColor(1, 1, 1)
  label = frame:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(label, "dataText")
  label:SetPoint("TOP", distance, "BOTTOM", 0, -1)
  label:SetTextColor(0.85, 0.85, 0.85)
  frame:Hide()
  -- Above the character: the camera keeps you a little below the middle of
  -- the screen, so a bit above the middle is over your head. /fui move puts
  -- it exactly where you want it.
  ns.RegisterMover("arrow", "Waypoint arrow", frame, { "CENTER", "CENTER", 0, 150 })
  module.frame, module.arrow, module.distance, module.label = frame, arrow, distance, label

  -- Twenty times a second is smooth enough to turn with you.
  local clock = 0
  local ticker = CreateFrame("Frame")
  ticker:SetScript("OnUpdate", function(_, elapsed)
    clock = clock + (elapsed or 0)
    if clock >= 0.05 then
      clock = 0
      if module.enabledNow then pcall(module.Update) end
    end
  end)
  module.ticker = ticker
end

function module:OnEnable()
  if not frame then
    Build()
  end
  module.enabledNow = true
  Paint()
  module.Update()
end

function module:OnDisable()
  module.enabledNow = false
  Hide()
end

function module:Refresh()
  if not frame then return end
  Paint()
  module.Update()
end

-- On and off in one go (owner, 23 Sept 2026: "make a way for me to turn the
-- arrow on and off"): /fui arrow, a key in the game's Key Bindings under
-- ForeverUI, or the switch at the top of its page. `state` true/false sets
-- it; nil flips it.
function module.Toggle(state)
  local s = Settings()
  if state == nil then
    state = s.shown == false
  end
  s.shown = state and true or false
  if frame then module.Update() end
  if s.shown and not module.showing then
    ns.Print("waypoint arrow on - it shows when you have a map pin or a tracked quest.")
  else
    ns.Print(("waypoint arrow %s."):format(s.shown and "on" or "off"))
  end
  if ns.RefreshOptions then ns.RefreshOptions() end
  return s.shown
end

-- Why isn't it showing? /fui arrow why
function module.Why()
  local lines = {}
  local map, px, py = PlayerPosition()
  lines[#lines + 1] = map and ("you: map %d at %.3f, %.3f"):format(map, px, py) or "you: this client won't say where you are"
  local facing = GetPlayerFacing and Try(GetPlayerFacing)
  lines[#lines + 1] = Plain(facing) and ("facing: %.2f"):format(facing) or "facing: hidden here (instances hide it)"
  local target = map and module.Target(map)
  if target then
    local _, yards = module.Bearing(map, px, py, target)
    lines[#lines + 1] = ("pointing at: %s%s"):format(target.name or "?",
      yards and (" (%d yd)"):format(math.floor(yards + 0.5)) or " - but can't work out the way")
  else
    lines[#lines + 1] = "pointing at: nothing - drop a pin on the map or track a quest"
  end
  for _, line in ipairs(lines) do ns.Print(line) end
  return lines
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------

local function Percent(v) return ("%d%%"):format(math.floor((v or 1) * 100 + 0.5)) end

function module.RestoreDefaults()
  local s = Settings()
  for key, value in pairs(module.defaults) do
    s[key] = type(value) == "table" and { unpack(value) } or value
  end
  module:Refresh()
  if ns.RefreshOptions then ns.RefreshOptions() end
end

module.options = {
  { type = "heading", label = "Waypoint Arrow", subtitle = "Points the way to your quest or map pin." },
  { type = "heading", label = "Arrow", icon = "map",
    action = { label = "Restore Defaults", run = function() module.RestoreDefaults() end } },
  { type = "checkbox", switch = true, key = "shown", label = "Show the waypoint arrow",
    desc = "Also: /fui arrow, or a key under ForeverUI in the game's Key Bindings." },
  { type = "custom", height = 96, build = function(page, x, y, width)
      return ns.ArrowStylePicker and ns.ArrowStylePicker(page, x, y, width) or 0
    end,
    refresh = function() if ns.RefreshArrowStylePicker then ns.RefreshArrowStylePicker() end end },
  { type = "color", key = "color", label = "Colour", desc = "Any colour: the arrows are drawn in white and tinted." },
  { type = "stepper", slider = true, key = "size", label = "Size", desc = "How big the arrow is.",
    min = 24, max = 128, step = 2 },
  { type = "stepper", slider = true, key = "alpha", label = "Opacity", desc = "How solid it is.",
    min = 0.2, max = 1, step = 0.05, format = Percent },
  { type = "cycler", key = "target", label = "Point to", desc = "What the arrow follows.",
    choices = function()
      return {
        { label = "Map pin, then my quest", value = "auto" },
        { label = "Only my map pin", value = "pin" },
        { label = "Only my quest", value = "quest" },
      }
    end },
  { type = "stepper", slider = true, key = "arriveRange", label = "Arrived at", desc = "Put the arrow away this close to a pin.",
    min = 3, max = 40, step = 1, format = function(v) return (v or 8) .. " yd" end },
  { type = "checkbox", switch = true, key = "showDistance", label = "Show the distance", desc = "Yards to go, under the arrow." },
  { type = "checkbox", switch = true, key = "showLabel", label = "Show where it's pointing", desc = "The quest's name, or \"Map pin\"." },
  { type = "checkbox", switch = true, key = "hideInCombat", label = "Hide in combat", desc = "Out of the way while you fight." },
  { type = "note", label = "It sits above your character; drag it exactly where you want with /fui move. Track a quest by clicking it in the tracker or the quest log, or drop a pin on the world map. /fui arrow turns it on and off." },
}

-- The styles side by side, each drawn in your colour; click one to use it.
local picker
function ns.ArrowStylePicker(page, x, y, width)
  local kit = ns.OptionsKit
  picker = { cells = {} }
  local heading = page:CreateFontString(nil, "OVERLAY")
  kit.OptionFont(heading, "general")
  heading:SetPoint("TOPLEFT", x, y - 4)
  heading:SetText("Style")
  heading:SetTextColor(kit.INK[1], kit.INK[2], kit.INK[3])
  local count = #module.STYLES
  local cell = math.min(74, math.floor((width - 10) / count) - 6)
  for i, style in ipairs(module.STYLES) do
    local button = kit.Button(page, cell, "", function()
      Settings().style = style
      module:Refresh()
      if ns.RefreshOptions then ns.RefreshOptions() end
    end)
    button:SetHeight(cell)
    button:SetPoint("TOPLEFT", x + (i - 1) * (cell + 6), y - 24)
    local art = button:CreateTexture(nil, "ARTWORK")
    art:SetPoint("TOPLEFT", 6, -6)
    art:SetPoint("BOTTOMRIGHT", -6, 6)
    art:SetTexture(module.ArrowTexture(style))
    button.art, button.style = art, style
    local name = page:CreateFontString(nil, "OVERLAY")
    kit.OptionFont(name, "dataText")
    name:SetPoint("TOP", button, "BOTTOM", 0, -2)
    name:SetText(module.STYLE_LABELS[style])
    name:SetTextColor(kit.INK_DIM[1], kit.INK_DIM[2], kit.INK_DIM[3])
    picker.cells[i] = button
  end
  ns.RefreshArrowStylePicker()
  return cell + 44
end

function ns.RefreshArrowStylePicker()
  if not picker then return end
  local s = Settings()
  local c = s.color or module.defaults.color
  for _, button in ipairs(picker.cells) do
    button.art:SetVertexColor(c[1], c[2], c[3], 1)
    if ns.Skin and ns.Skin.SetSelected then
      ns.Skin.SetSelected(button, button.style == s.style)
    end
  end
end
