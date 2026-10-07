-- Quest lines and what to do next (owner, 26 Sept 2026: "provide quest
-- guides to tell people what quest they should get next and also show them
-- where they are in a quest line ... the entire branch").
--
-- The data already says, for every quest, which quests must be done first
-- (all of them, or any one) and which it rules out. Turned around, that is
-- also which quests each one opens. From that:
--
--   QF.Chain(id)    the whole line a quest belongs to - what came before,
--                   what comes after, side branches - each step marked done,
--                   in your log, ready to take now, not yet, or closed to you.
--   QF.Suggest(n)   quests you can pick up now, nearest first.
--   QF.PointToStart(id)  the arrow to where a quest is picked up.
--
-- Nothing here reads anything the game hides: quests done and in the log,
-- your level, race and class - all plain.

local QF = _G.QuestForever
if not QF then return end
local D = _G.QuestForeverData

local MAX_LINE = 30      -- steps shown for one line; hub quests open dozens
local MAX_UP = 25        -- steps walked back to the start

local function Contains(list, value)
  if not list or not value then return false end
  for item in list:gmatch("[^,]+") do
    if item == value then return true end
  end
  return false
end

-- Could this character ever take it: faction, race and class. (Level,
-- earlier quests and the rest are about WHEN, not whether.)
local function ForMe(q)
  local me = QF.me
  if not q then return false end
  if q.side == 1 and me.faction ~= "Alliance" then return false end
  if q.side == 2 and me.faction ~= "Horde" then return false end
  if q.races and not Contains(q.races, me.race) then return false end
  if q.classes and not Contains(q.classes, me.class) then return false end
  return true
end
QF.ForMe = ForMe

-- Which quests each quest opens: the prerequisites turned around, built
-- once from the raw records (fields 10 and 11: all-of, any-of).
local followers
local function Followers(id)
  if not followers then
    followers = {}
    for qid, raw in pairs(D.Q) do
      -- By index, not ipairs: an "any of" quest has nil in the first slot,
      -- and ipairs stops at it.
      for slot = 10, 11 do
        local field = raw[slot]
        if field then
          for text in tostring(field):gmatch("%d+") do
            local pre = tonumber(text)
            local list = followers[pre]
            if not list then list = {}; followers[pre] = list end
            list[#list + 1] = qid
          end
        end
      end
    end
  end
  return followers[id] or {}
end
QF.Followers = Followers
function QF.ForgetFollowers() followers = nil end

local function Before(q)
  local list = {}
  for _, pre in ipairs(QF.IdList(q.preAll)) do list[#list + 1] = pre end
  for _, pre in ipairs(QF.IdList(q.preAny)) do
    -- "Any one of": only the ones this character could have done.
    if ForMe(QF.Quest(pre)) then list[#list + 1] = pre end
  end
  return list
end

-- Where one quest stands for you.
--   "done", "ready" (in the log, complete), "log", "now" (can take it),
--   "later" (reason: an earlier quest, your level...), "closed" (you took
--   the other branch).
local function Status(q)
  if QF.IsDone(q.id) then return "done" end
  local state = QF.inLog[q.id]
  if state then return state.complete and "ready" or "log" end
  local ok, why = QF.IsAvailable(q)
  if ok then return "now" end
  if why == "took another" then return "closed", why end
  return "later", why
end
QF.Status = Status

-- The whole line `id` is part of, in order: the start first, each step's
-- `depth` its distance from the start, so side branches share a depth.
function QF.Chain(id)
  local q0 = QF.Quest(id)
  if not q0 then return {} end
  local set, order = {}, {}
  local function add(qid)
    if set[qid] or #order >= MAX_LINE then return false end
    local q = QF.Quest(qid)
    if not (q and ForMe(q)) then return false end
    set[qid] = q
    order[#order + 1] = qid
    return true
  end
  add(id)
  -- Back to the start.
  local stack, walked = { id }, 0
  while #stack > 0 and walked < MAX_UP do
    local qid = table.remove(stack)
    for _, pre in ipairs(Before(set[qid] or QF.Quest(qid))) do
      if add(pre) then stack[#stack + 1] = pre; walked = walked + 1 end
    end
  end
  -- Forward from everything so far, nearest first: the steps after this
  -- one, and the other branches off the same line.
  local queue, head = {}, 1
  for _, qid in ipairs(order) do queue[#queue + 1] = qid end
  while head <= #queue and #order < MAX_LINE do
    local qid = queue[head]
    head = head + 1
    for _, nxt in ipairs(Followers(qid)) do
      if add(nxt) then queue[#queue + 1] = nxt end
    end
  end
  -- Depth: the longest path back to a start within the line.
  local depth = {}
  local function Depth(qid, guard)
    if depth[qid] then return depth[qid] end
    if guard > 40 then return 0 end
    local d = 0
    for _, pre in ipairs(Before(set[qid])) do
      if set[pre] then d = math.max(d, Depth(pre, guard + 1) + 1) end
    end
    depth[qid] = d
    return d
  end
  local line = {}
  for _, qid in ipairs(order) do
    local q = set[qid]
    local status, why = Status(q)
    line[#line + 1] = { id = qid, name = q.name, level = q.level or 0, req = q.reqLevel or 1, depth = Depth(qid, 0),
      status = status, why = why, current = qid == id }
  end
  table.sort(line, function(a, b)
    if a.depth ~= b.depth then return a.depth < b.depth end
    if a.level ~= b.level then return a.level < b.level end
    return (a.name or "") < (b.name or "")
  end)
  return line
end

-- Where a quest sits in its line: step N of M along the longest path from
-- the start (side branches share a step number), the line's first quest,
-- and the line itself. nil for a quest on its own.
function QF.ChainPosition(id)
  local line = QF.Chain(id)
  if #line < 2 then return nil end
  local step, total, first = 1, 1, line[1]
  for _, s in ipairs(line) do
    if s.depth + 1 > total then total = s.depth + 1 end
    if s.current then step = s.depth + 1 end
    if s.depth == 0 and not first then first = s end
  end
  if total < 2 then total = #line end   -- all side by side: count them
  return { step = step, total = total, first = first and first.name, line = line }
end

-- Rough yards between two points on one map, when the game says how big it
-- is; otherwise the map-fraction distance, which still sorts correctly.
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

-- Quests you can pick up now on the map you're on, nearest first:
-- { { id, name, level, who, map, x, y, yards }, ... }
function QF.Suggest(limit)
  limit = limit or 5
  QF.ReadPlayer()
  local map, px, py = QF.Here()
  if not map then return {} end
  local best = {}
  for _, entry in ipairs(QF.StartIndex()[map] or {}) do
    local q = QF.Quest(entry.id)
    if q and QF.IsAvailable(q) and not QF.IsHigh(q) then
      local d = px and ((entry.x - px) ^ 2 + (entry.y - py) ^ 2) or 0
      local had = best[entry.id]
      if not had or d < had.d then
        best[entry.id] = { id = entry.id, name = q.name, level = q.level or 0, who = entry.who,
          map = map, x = entry.x, y = entry.y, d = d,
          yards = px and Yards(map, entry.x - px, entry.y - py) or nil }
      end
    end
  end
  local list = {}
  for _, item in pairs(best) do list[#list + 1] = item end
  table.sort(list, function(a, b)
    if a.d ~= b.d then return a.d < b.d end
    return a.id < b.id
  end)
  for i = #list, limit + 1, -1 do list[i] = nil end
  return list
end

-- The arrow to where a quest is picked up (the nearest place on your map,
-- else the first known). Returns who gives it, or nil.
function QF.PointToStart(id)
  local q = QF.Quest(id)
  if not q then return nil end
  local places = QF.StartPlaces(q)
  if #places == 0 then return nil end
  local map, px, py = QF.Here()
  local pick, bestD
  for _, p in ipairs(places) do
    local d = (p[1] == map and px) and ((p[2] - px) ^ 2 + (p[3] - py) ^ 2) or (p[1] == map and 1 or 10)
    if not bestD or d < bestD then pick, bestD = p, d end
  end
  QF.SetWaypoint(pick[1], pick[2], pick[3])
  return pick[4] or "the quest giver"
end
