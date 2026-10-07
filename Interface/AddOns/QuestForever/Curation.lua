-- Notes and routes (owner, 27 Sept 2026: "make a way that I can improve
-- routes and notes on the questing application").
--
-- Anyone can keep a note on a quest and walk a route for it, from the quest
-- guide: "Add point here" drops a point where you stand, in order. The arrow
-- then walks the route - it points at the next point, moves on by itself
-- when you reach it, and after the last one points at the objective as
-- usual. Route points show on the map as numbered green dots.
--
-- What the owner curates ships to everyone: tools/quest_curate.lua reads his
-- saved notes and routes (read only) and writes them into Curated.lua, which
-- every copy of QuestForever loads. A player's own note or route for a quest
-- wins over the curated one. /fui qf export carries notes and routes too, so
-- a player's can be sent in and folded the same way.
--
-- Nothing here reads a secret value: positions come from the map API and are
-- checked (QF.Here).

local QF = _G.QuestForever
if not QF then return end
local CURATED = _G.QuestForeverCurated or { notes = {}, routes = {} }
QF.curated = CURATED

local MAX_NOTE = 400
local MAX_POINTS = 30
local REACHED_YARDS = 12       -- close enough to count a route point as reached
local REACHED_SHARE = 0.004    -- ...in map units, when the map's size is unknown

---------------------------------------------------------------------------
-- Notes
---------------------------------------------------------------------------

-- The note for a quest and whose it is ("yours" or "ForeverUI"), or nil.
function QF.Note(id)
  local mine = QF.Store("notes")[id]
  if type(mine) == "string" and mine ~= "" then return mine, "yours" end
  local curated = CURATED.notes and CURATED.notes[id]
  if type(curated) == "string" and curated ~= "" then return curated, "ForeverUI" end
  return nil
end

-- Set (or, with nothing, remove) your note for a quest.
function QF.SetNote(id, text)
  if type(id) ~= "number" then return false end
  text = type(text) == "string" and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if #text > MAX_NOTE then text = text:sub(1, MAX_NOTE) end
  QF.Store("notes")[id] = text ~= "" and text or nil
  QF.Changed()
  return true
end

---------------------------------------------------------------------------
-- Routes: { { map, x, y, label }, ... } in walking order
---------------------------------------------------------------------------

local function Mine(id)
  local routes = QF.Store("routes")
  return routes[id]
end

-- The route for a quest (yours, else the curated one), and whose it is.
function QF.Route(id)
  local mine = Mine(id)
  if type(mine) == "table" and #mine > 0 then return mine, "yours" end
  local curated = CURATED.routes and CURATED.routes[id]
  if type(curated) == "table" and #curated > 0 then return curated, "ForeverUI" end
  return {}, nil
end

-- Drop a point where you stand. Starting your own route on a quest that has
-- a curated one starts from a copy of it, so a fix is an edit, not a redo.
function QF.AddRoutePoint(id, label)
  if type(id) ~= "number" then return nil, "no quest" end
  local map, x, y = QF.Here()
  if not (map and x) then return nil, "the game won't say where you are here" end
  local routes = QF.Store("routes")
  local route = routes[id]
  if type(route) ~= "table" or #route == 0 then
    route = {}
    local curated = CURATED.routes and CURATED.routes[id]
    for _, p in ipairs(type(curated) == "table" and curated or {}) do
      route[#route + 1] = { p[1], p[2], p[3], p[4] }
    end
    routes[id] = route
  end
  if #route >= MAX_POINTS then return nil, ("a route holds %d points"):format(MAX_POINTS) end
  label = type(label) == "string" and label:gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 60) or ""
  local point = { map, math.floor(x * 10000 + 0.5) / 10000, math.floor(y * 10000 + 0.5) / 10000,
    label ~= "" and label or nil }
  route[#route + 1] = point
  QF.Changed()
  return point, #route
end

function QF.UndoRoutePoint(id)
  local route = Mine(id)
  if type(route) ~= "table" or #route == 0 then return false end
  table.remove(route)
  if #route == 0 then QF.Store("routes")[id] = nil end
  QF.Changed()
  return true
end

function QF.ClearRoute(id)
  if Mine(id) == nil then return false end
  QF.Store("routes")[id] = nil
  QF.StopRoute(id)
  QF.Changed()
  return true
end

---------------------------------------------------------------------------
-- Following a route with the arrow
---------------------------------------------------------------------------

local following   -- { id = questID, index = next point }
local ticker

local function Yards(map, dx, dy)
  local fn = C_Map and C_Map.GetMapWorldSize
  if fn then
    local ok, w, h = pcall(fn, map)
    if ok and type(w) == "number" and type(h) == "number" and w > 0 then
      return math.sqrt((dx * w) ^ 2 + (dy * h) ^ 2)
    end
  end
  return nil
end

local function Reached(p, map, x, y)
  if not (map and x) or p[1] ~= map then return false end
  local yards = Yards(map, p[2] - x, p[3] - y)
  if yards then return yards <= REACHED_YARDS end
  return math.sqrt((p[2] - x) ^ 2 + (p[3] - y) ^ 2) <= REACHED_SHARE
end

local function Aim()
  if not following then return end
  local route = QF.Route(following.id)
  local p = route[following.index]
  if p then
    QF.SetWaypoint(p[1], p[2], p[3])
  else
    -- Walked it all: on to the quest itself.
    local id = following.id
    QF.StopRoute()
    QF.PointTo(id)
  end
end

-- One look at where you are: at the point? On to the next.
function QF.RouteTick()
  if not following then return end
  if not QF.inLog[following.id] then QF.StopRoute() return end
  local route = QF.Route(following.id)
  local p = route[following.index]
  if not p then Aim() return end
  local map, x, y = QF.Here()
  if Reached(p, map, x, y) then
    following.index = following.index + 1
    Aim()
  end
end

-- Walk the route: start at the point nearest you (a route half walked
-- doesn't send you back to its start), then on in order.
function QF.FollowRoute(id)
  local route = QF.Route(id)
  if #route == 0 then return false end
  local map, x, y = QF.Here()
  local start, best = 1, nil
  for i, p in ipairs(route) do
    if p[1] == map and x then
      local d = (p[2] - x) ^ 2 + (p[3] - y) ^ 2
      if not best or d < best then start, best = i, d end
    end
  end
  following = { id = id, index = start }
  Aim()
  if not ticker and C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(0.5, QF.RouteTick)
  end
  return true, start, #route
end

function QF.StopRoute(id)
  if id and following and following.id ~= id then return end
  following = nil
  if ticker and ticker.Cancel then ticker:Cancel() end
  ticker = nil
end

-- The quest whose route is being walked, and the next point's number.
function QF.Following()
  if not following then return nil end
  return following.id, following.index
end

---------------------------------------------------------------------------
-- Sending them in
---------------------------------------------------------------------------

-- Lines for /fui qf export, alongside the learned places:
--   N;<quest>;<note>
--   R;<quest>;<map>;<x*10000>;<y*10000>;<label>   (one per point, in order)
function QF.ExportEdits()
  local lines = {}
  local ids = {}
  for id in pairs(QF.Store("notes")) do ids[id] = true end
  for id in pairs(QF.Store("routes")) do ids[id] = true end
  local sorted = {}
  for id in pairs(ids) do sorted[#sorted + 1] = id end
  table.sort(sorted)
  for _, id in ipairs(sorted) do
    local note = QF.Store("notes")[id]
    if type(note) == "string" and note ~= "" then
      lines[#lines + 1] = ("N;%d;%s"):format(id, (note:gsub("[\r\n]+", " "):gsub(";", ",")))
    end
    for _, p in ipairs(QF.Store("routes")[id] or {}) do
      lines[#lines + 1] = ("R;%d;%d;%d;%d;%s"):format(id, p[1], math.floor(p[2] * 10000 + 0.5),
        math.floor(p[3] * 10000 + 0.5), ((p[4] or ""):gsub(";", ",")))
    end
  end
  return table.concat(lines, "\n"), #lines
end
