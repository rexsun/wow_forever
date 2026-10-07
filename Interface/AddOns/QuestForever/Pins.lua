-- QuestForever's pins: on the world map (through the map's own data-provider
-- system, the way Blizzard adds its own pins) and on the minimap (small
-- frames placed from the distance between you and each pin).

local QF = QuestForever

-- "!" to pick up, "?" to hand in: the game's own quest marks, with plain
-- fallbacks if a client doesn't have the atlas.
local LOOK = {
  available  = { atlas = "QuestNormal",  file = "Interface\\GossipFrame\\AvailableQuestIcon" },
  high       = { atlas = "QuestNormal",  file = "Interface\\GossipFrame\\AvailableQuestIcon", grey = true },
  turnin     = { atlas = "QuestTurnin",  file = "Interface\\GossipFrame\\ActiveQuestIcon" },
  unfinished = { atlas = "QuestTurnin",  file = "Interface\\GossipFrame\\ActiveQuestIcon", grey = true },
  objective  = { file = "Interface\\COMMON\\Indicator-Yellow", small = true },
  itemstart  = { file = "Interface\\Icons\\INV_Misc_Note_02", small = true },
  path       = { file = "Interface\\COMMON\\Indicator-Gray", tiny = true },
  route      = { file = "Interface\\COMMON\\Indicator-Green", small = true },
}
QF.LOOK = LOOK

local function Paint(texture, kind)
  local look = LOOK[kind] or LOOK.available
  local drawn = look.atlas and texture.SetAtlas and pcall(texture.SetAtlas, texture, look.atlas)
  if not drawn then
    texture:SetTexture(look.file)
  end
  if texture.SetDesaturated then texture:SetDesaturated(look.grey and true or false) end
  texture:SetAlpha((look.grey or look.tiny) and 0.7 or 1)
end
QF.Paint = Paint

local function Size(kind)
  local size = QF.Setting("iconSize") or 16
  local look = LOOK[kind]
  if look and look.tiny then return math.max(4, math.floor(size * 0.35)) end
  return (look and look.small) and math.max(6, math.floor(size * 0.55)) or size
end

local WORDS = {
  available = "Quests to pick up", high = "Quests (too high for you yet)",
  turnin = "Hand in", unfinished = "Hand in (not finished yet)", objective = "Objective",
  route = "Route",
  itemstart = "Drops an item that starts a quest", path = "Walks this way",
}

local function LevelColor(level)
  if GetQuestDifficultyColor and level and level > 0 then
    local ok, c = pcall(GetQuestDifficultyColor, level)
    if ok and type(c) == "table" and c.r then return c.r, c.g, c.b end
  end
  return 1, 0.82, 0
end

-- The quest's steps under its name: done ones ticked and dim, the one this
-- spot is for marked, the rest plain.
function QF.AddSteps(tooltip, questID, who)
  local q = QF.Quest(questID)
  if not q then return end
  local steps = QF.HowTo(q, QF.inLog[questID])
  for i, step in ipairs(steps) do
    if i > 6 then break end
    local here = false
    if who and not step.done then
      for _, name in ipairs(step.names or {}) do
        if who:find(name, 1, true) then here = true break end
      end
    end
    local text = step.text
    if step.progress and step.progress ~= step.text then text = text .. " - " .. step.progress end
    if step.done then
      tooltip:AddLine("  v " .. text, 0.4, 0.8, 0.4)
    elseif here then
      tooltip:AddLine("  > " .. text, 1, 1, 1)
    else
      tooltip:AddLine("  - " .. text, 0.75, 0.75, 0.75)
    end
  end
end

function QF.ShowTooltip(owner, pin)
  if not GameTooltip or not pin then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(pin.who and pin.who ~= "" and pin.who or (WORDS[pin.kind] or "?"), 1, 1, 1)
  GameTooltip:AddLine(WORDS[pin.kind] or "", 0.3, 0.76, 1)
  local list = pin.quests or { { name = pin.name, level = pin.level } }
  for i, q in ipairs(list) do
    if i > 12 then
      GameTooltip:AddLine(("...and %d more"):format(#list - 12), 0.6, 0.6, 0.6)
      break
    end
    local r, g, b = LevelColor(q.level)
    local label = (q.level and q.level > 0) and ("[%d] %s"):format(q.level, q.name or "?") or (q.name or "?")
    if q.xp and pin.kind ~= "objective" and pin.kind ~= "path" then
      GameTooltip:AddDoubleLine(label, ("%d xp"):format(q.xp), r, g, b, 0.6, 0.6, 0.6)
    else
      GameTooltip:AddLine(label, r, g, b)
    end
    if q.item then GameTooltip:AddLine("  from " .. q.item, 0.8, 0.8, 0.8) end
    if pin.kind == "objective" or pin.kind == "path" or pin.kind == "unfinished" then
      QF.AddSteps(GameTooltip, q.id, pin.who)
    elseif q.progress then
      GameTooltip:AddLine("  " .. q.progress, 0.8, 0.8, 0.8)
    end
  end
  GameTooltip:AddLine("Click: point the waypoint arrow here", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------

-- The pin mixin. Filled in from Blizzard's own pin mixin once the world map
-- exists (it loads on demand); the XML template names this table.
QuestForeverPinMixin = QuestForeverPinMixin or {}
local PinMixin = QuestForeverPinMixin

function PinMixin:OnLoad()
  if self.UseFrameLevelType then pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_AREA_POI") end
  if self.SetScalingLimits then pcall(self.SetScalingLimits, self, 1, 1.0, 1.2) end
end

function PinMixin:OnAcquired(pin)
  self.pin = pin
  local size = Size(pin.kind)
  self:SetSize(size, size)
  Paint(self.Texture, pin.kind)
  self:SetPosition(pin.x, pin.y)
end

function PinMixin:OnMouseEnter() QF.ShowTooltip(self, self.pin) end
function PinMixin:OnMouseLeave() if GameTooltip then GameTooltip:Hide() end end
function PinMixin:OnClick()
  local map = self:GetMap()
  if self.pin and map then QF.SetWaypoint(map:GetMapID(), self.pin.x, self.pin.y) end
end

local Provider = {}
QF.MapProvider = Provider

function Provider:RemoveAllData()
  self:GetMap():RemoveAllPinsByTemplate("QuestForeverPinTemplate")
end

-- Playing with a controller (CurseForge: "QuestForever is being blocked from
-- an action only available to the Blizzard UI", 28 Sept 2026; Altiokis again
-- on 1 Oct: "hit L to open the quest log, I get a QuestForever error every
-- time, that disables the addon"). On Forever the quest log IS the world map
-- (QuestMapFrame sits inside it), and with the controller interface on, the
-- game's navigation scans the open map's frames and steers between them.
-- Every pin we put there -- made, placed and painted by our code -- carries
-- QuestForever's fingerprints, and the navigation pass that touches one runs
-- as QuestForever; the next protected thing it does is blocked, and the
-- game offers to switch QuestForever off. Filling the map's pin pool ahead
-- of time (the 28 Sept fix) only kept us from MAKING frames there; the pins
-- were still ours. So with the controller interface on, QuestForever stays
-- off the world map altogether. The minimap, tooltips and the arrow carry on.
local function GamepadUI()
  if InputUtil and InputUtil.IsGamepadUIEnabled then
    local ok, on = pcall(InputUtil.IsGamepadUIEnabled)
    if ok then return on and true or false end
  end
  return false
end
QF.GamepadUI = GamepadUI

local onMap = false   -- whether any of our pins are on the world map now

function Provider:RefreshAllData()
  if GamepadUI() then
    -- Pins left from keyboard play are put away; nothing new is placed.
    if onMap then
      onMap = false
      pcall(self.RemoveAllData, self)
    end
    return
  end
  self:RemoveAllData()
  onMap = false
  if not QF.running or not QF.Setting("onWorldMap") then return end
  local map = self:GetMap()
  local mapID = map and map:GetMapID()
  for _, pin in ipairs(QF.PinsFor(mapID)) do
    -- One refusal (a client whose map works differently) stops the rest
    -- quietly rather than raising an error for every pin, every redraw.
    local ok, err = pcall(map.AcquirePin, map, "QuestForeverPinTemplate", pin)
    if not ok then
      QF.mapError = tostring(err)
      break
    end
    onMap = true
  end
end

local providerAdded = false
local function AddProvider()
  if providerAdded or not WorldMapFrame or not MapCanvasDataProviderMixin then return end
  -- Blizzard's pin mixin supplies SetPosition and the rest; ours on top.
  if MapCanvasPinMixin then
    for key, fn in pairs(MapCanvasPinMixin) do
      if PinMixin[key] == nil then PinMixin[key] = fn end
    end
  end
  for key, fn in pairs(MapCanvasDataProviderMixin) do
    if Provider[key] == nil then Provider[key] = fn end
  end
  local ok = pcall(WorldMapFrame.AddDataProvider, WorldMapFrame, Provider)
  providerAdded = ok
end
QF.AddProvider = AddProvider

local function RefreshMap()
  -- With the controller interface on, our quest events never touch an open
  -- map (see above); the map's own redraw puts any old pins away.
  if providerAdded and WorldMapFrame and WorldMapFrame:IsShown() and not GamepadUI() then
    pcall(Provider.RefreshAllData, Provider)
  end
end

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------

-- Yards across the minimap at each zoom level, outdoors and in.
local OUTDOOR = { [0] = 466.6667, 400, 333.3333, 266.6667, 200, 133.3333 }
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }

local pool, used = {}, 0
local current = { map = nil, pins = {} }

local function Frame(i)
  local f = pool[i]
  if f then return f end
  f = CreateFrame("Button", nil, Minimap)
  f:SetFrameStrata("MEDIUM")
  f:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 5)
  f.Texture = f:CreateTexture(nil, "OVERLAY")
  f.Texture:SetAllPoints()
  f:SetScript("OnEnter", function(self) QF.ShowTooltip(self, self.pin) end)
  f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  f:SetScript("OnClick", function(self)
    if self.pin and current.map then QF.SetWaypoint(current.map, self.pin.x, self.pin.y) end
  end)
  pool[i] = f
  return f
end

local function HideFrom(first)
  for i = first, #pool do pool[i]:Hide() end
end

-- Where a map position sits on the minimap, in pixels from its centre, or
-- nil when it is off the edge. Map positions are turned into yards with the
-- map's own size; y on a map grows southwards, on screen it grows up.
function QF.MinimapOffset(mapID, px, py, x, y, width, height)
  if not (width and height and width > 0 and height > 0) then return nil end
  local dx = (x - px) * width
  local dy = (y - py) * height
  local zoom = Minimap.GetZoom and Minimap:GetZoom() or 0
  local indoors = IsIndoors and IsIndoors()
  local yards = (indoors and INDOOR or OUTDOOR)[zoom] or OUTDOOR[0]
  local w, h = Minimap:GetWidth() or 140, Minimap:GetHeight() or 140
  local scale = w / yards
  local ox, oy = dx * scale, -dy * scale
  if GetCVar and GetCVar("rotateMinimap") == "1" and GetPlayerFacing then
    local ok, facing = pcall(GetPlayerFacing)
    if ok and type(facing) == "number" and not (issecretvalue and issecretvalue(facing)) then
      local s, c = math.sin(facing), math.cos(facing)
      ox, oy = ox * c - oy * s, ox * s + oy * c
    end
  end
  if math.abs(ox) > w / 2 or math.abs(oy) > h / 2 then return nil end
  return ox, oy
end

local function UpdateMinimap()
  if not QF.running or not QF.Setting("onMinimap") or not Minimap then
    HideFrom(1)
    return
  end
  local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
  if not okMap or not mapID then HideFrom(1) return end
  if mapID ~= current.map then
    current.map = mapID
    current.pins = QF.PinsFor(mapID)
  end
  local okPos, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
  if not okPos or not pos then HideFrom(1) return end
  local px, py = pos:GetXY()
  if not px or (issecretvalue and issecretvalue(px)) then HideFrom(1) return end
  local okSize, width, height = pcall(C_Map.GetMapWorldSize, mapID)
  if not okSize then HideFrom(1) return end
  used = 0
  for _, pin in ipairs(current.pins) do
    local ox, oy = QF.MinimapOffset(mapID, px, py, pin.x, pin.y, width, height)
    if ox then
      used = used + 1
      local f = Frame(used)
      f.pin = pin
      local size = Size(pin.kind)
      f:SetSize(size, size)
      Paint(f.Texture, pin.kind)
      f:ClearAllPoints()
      f:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
      f:Show()
      if used >= 80 then break end
    end
  end
  HideFrom(used + 1)
end
QF.UpdateMinimap = UpdateMinimap

local ticker = CreateFrame("Frame")
local since = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
  since = since + elapsed
  if since < 0.2 then return end
  since = 0
  UpdateMinimap()
end)
ticker:Hide()

---------------------------------------------------------------------------
-- Following changes
---------------------------------------------------------------------------

QF.OnChange(function()
  current.map = nil   -- rebuild the minimap's list on the next tick
  RefreshMap()
end)

local mapWatcher = CreateFrame("Frame")
mapWatcher:RegisterEvent("ADDON_LOADED")
mapWatcher:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == "Blizzard_WorldMap" and QF.running then AddProvider() end
end)

function QF.StartPins()
  AddProvider()
  ticker:Show()
  RefreshMap()
end

function QF.StopPins()
  ticker:Hide()
  HideFrom(1)
  if providerAdded and WorldMapFrame then
    pcall(Provider.RemoveAllData, Provider)
  end
end
