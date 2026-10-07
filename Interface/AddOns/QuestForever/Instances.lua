-- Dungeons: where the door is and which quests to take in (owner, 27 Sept
-- 2026: the dungeon guide). The data is QuestForeverData.D, generated from
-- QuestieDB by tools/build_dungeons.lua and keyed by instance ID -- the same
-- number the game's group finder hands back as an activity's mapID, which is
-- where the list of dungeons, their names and level ranges come from in game.
--
--   QF.Dungeon(instanceID)          { area, name, entrances, questIDs } or nil
--   QF.DungeonQuests(instanceID)    the quests this character could ever take
--                                   for it, each with its status (QF.Status)
--   QF.PointToEntrance(instanceID)  the arrow to the nearest door; its map name
--
-- Forever's new dungeons are not in the data yet: they come back with no
-- door and no quests, and the guide says so rather than guessing.

local QF = _G.QuestForever
if not QF then return end
local D = _G.QuestForeverData

local cache = {}

-- "1436:425,717 1418:652,435" -> { {1436, 0.425, 0.717}, {1418, 0.652, 0.435} }
local function Doors(text)
  local list = {}
  for map, x, y in tostring(text or ""):gmatch("(%d+):(%d+),(%d+)") do
    list[#list + 1] = { tonumber(map), tonumber(x) / 1000, tonumber(y) / 1000 }
  end
  return list
end

function QF.Dungeon(instanceID)
  local hit = cache[instanceID]
  if hit ~= nil then return hit or nil end
  local raw = D and D.D and D.D[instanceID]
  if not raw then
    cache[instanceID] = false
    return nil
  end
  local ids = {}
  for id in tostring(raw[4] or ""):gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
  hit = { id = instanceID, area = raw[1], name = raw[2], entrances = Doors(raw[3]), questIDs = ids }
  cache[instanceID] = hit
  return hit
end

-- The dungeon's quests you could ever take (faction, race, class), with where
-- each stands for you, lowest level first. Quests the data holds but the
-- helper doesn't know are left out: nothing to show for them.
function QF.DungeonQuests(instanceID)
  local d = QF.Dungeon(instanceID)
  local list = {}
  if not d then return list end
  -- Loaded for the Dungeons tab with the map pins off: nothing keeps who you
  -- are and your quest log up to date, so read them now (both are cheap).
  if not QF.running then
    QF.ReadPlayer()
    QF.ReadLog()
  end
  for _, id in ipairs(d.questIDs) do
    local q = QF.Quest(id)
    if q and QF.ForMe(q) then
      local status, why = QF.Status(q)
      list[#list + 1] = { id = id, name = q.name, level = q.level or 0, req = q.reqLevel or 1,
        status = status, why = why }
    end
  end
  table.sort(list, function(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return (a.name or "") < (b.name or "")
  end)
  return list
end

-- How many of them you could act on now: ready to hand in, in your log, or
-- ready to pick up.
function QF.DungeonQuestCounts(instanceID)
  local counts = { total = 0, now = 0, log = 0, done = 0 }
  for _, q in ipairs(QF.DungeonQuests(instanceID)) do
    counts.total = counts.total + 1
    if q.status == "now" then counts.now = counts.now + 1 end
    if q.status == "log" or q.status == "ready" then counts.log = counts.log + 1 end
    if q.status == "done" then counts.done = counts.done + 1 end
  end
  return counts
end

-- The arrow to the door: the nearest one on the map you're on, else the first.
function QF.PointToEntrance(instanceID)
  local d = QF.Dungeon(instanceID)
  if not d or #d.entrances == 0 then return nil end
  local map, px, py = QF.Here()
  local pick, best
  for _, door in ipairs(d.entrances) do
    local dist = (door[1] == map and px) and ((door[2] - px) ^ 2 + (door[3] - py) ^ 2) or 10
    if not best or dist < best then pick, best = door, dist end
  end
  QF.SetWaypoint(pick[1], pick[2], pick[3])
  local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(pick[1])
  return info and info.name or "its zone", pick
end

---------------------------------------------------------------------------
-- The recorder (owner, 27 Sept 2026: "add a recorder for the new dungeons'
-- entrances and quests")
---------------------------------------------------------------------------
--
-- Forever's new dungeons are in no data yet. As people play them, this
-- writes down what the data is missing:
--   the entrance  -- where you stood, outside, just before the game put you
--                    in the dungeon (a position from the last few seconds
--                    before the loading screen);
--   its quests    -- any quest you pick up, or that moves on, while you are
--                    inside it.
-- Only for dungeons the data has no entrance for, and only quests it doesn't
-- already list. Kept in the saved settings (QF.Store("dungeons")), shown on
-- the Dungeons tab straight away, and sent in with the rest: every line of
-- /qf export and ForeverUI's Share gains
--   D;<instanceID>;<map>;<x>;<y>;<quest,quest>;<name>
-- which tools/build_dungeons.lua folds into the data for everyone.
-- Off with the rest of the learning ("learn" in the quest helper settings).

local RECENT = 90            -- seconds: how old the outdoor position may be
local TICK = 2
local lastOutside            -- { map, x, y, time }
local inside                 -- instance ID while inside a dungeon
local progress = {}          -- questID -> objectives fulfilled, seen inside

local function Learning()
  return QF.running and QF.Setting("learn") ~= false
end

local function Recorded()
  return QF.Store and QF.Store("dungeons") or {}
end

local function Record(id)
  local rec = Recorded()
  rec[id] = rec[id] or { quests = {} }
  rec[id].quests = rec[id].quests or {}
  cache[id] = nil
  return rec[id]
end
QF.RecordedDungeons = Recorded

-- The data merged with what was recorded here.
local baseDungeon = QF.Dungeon
function QF.Dungeon(instanceID)
  local d = baseDungeon(instanceID)
  local rec = Recorded()[instanceID]
  if not rec then return d end
  if not d then
    d = { id = instanceID, area = 0, name = rec.name, entrances = {}, questIDs = {}, learned = true }
    cache[instanceID] = d
  end
  if #d.entrances == 0 and rec.map then
    d.entrances = { { rec.map, rec.x, rec.y } }
    d.learnedDoor = true
  end
  local seen = {}
  for _, id in ipairs(d.questIDs) do seen[id] = true end
  for id in pairs(rec.quests) do
    if not seen[id] then d.questIDs[#d.questIDs + 1] = id; seen[id] = true end
  end
  return d
end

local function Fulfilled(questID)
  local log = C_QuestLog
  if not (log and log.GetQuestObjectives) then return nil end
  local ok, list = pcall(log.GetQuestObjectives, questID)
  if not ok or type(list) ~= "table" then return nil end
  local sum = 0
  for _, o in ipairs(list) do
    local n = o.numFulfilled
    if type(n) ~= "number" or (issecretvalue and issecretvalue(n)) then return nil end
    sum = sum + n
  end
  return sum
end

local function SnapshotLog()
  for k in pairs(progress) do progress[k] = nil end
  for id in pairs(QF.inLog) do progress[id] = Fulfilled(id) end
end

local function KnownQuest(instanceID, questID)
  local d = baseDungeon(instanceID)
  if not d then return false end
  for _, id in ipairs(d.questIDs) do
    if id == questID then return true end
  end
  return false
end

-- Where you are, outdoors, every couple of seconds: the entrance is the last
-- of these before the loading screen.
local function Remember()
  if inside then return end
  local ok, map, x, y = pcall(QF.Here)
  if ok and map and x and y then
    lastOutside = { map, x, y, GetTime and GetTime() or 0 }
  end
end

local function Entered()
  local okIn, isIn, kind = pcall(IsInInstance)
  if not (okIn and isIn and (kind == "party" or kind == "raid")) then
    inside = nil
    return
  end
  local ok, name, _, _, _, _, _, _, instanceID = pcall(GetInstanceInfo)
  if not ok or type(instanceID) ~= "number" then return end
  inside = instanceID
  QF.ReadLog()
  SnapshotLog()
  if not Learning() then return end
  local known = baseDungeon(instanceID)
  local rec = Recorded()[instanceID]
  if (known and #known.entrances > 0) or (rec and rec.map) then return end
  local now = GetTime and GetTime() or 0
  if lastOutside and now - lastOutside[4] <= RECENT then
    local r = Record(instanceID)
    r.map, r.x, r.y, r.name = lastOutside[1], lastOutside[2], lastOutside[3], name
  elseif type(name) == "string" then
    Record(instanceID).name = name   -- the quests can still be kept
  end
end

local function QuestInside(questID)
  if not inside or not questID or KnownQuest(inside, questID) then return end
  if not Learning() then return end
  local r = Record(inside)
  if not r.quests[questID] then
    r.quests[questID] = true
    if not r.name then
      local ok, name = pcall(GetInstanceInfo)
      if ok and type(name) == "string" then r.name = name end
    end
  end
end

local function LogChanged()
  if not inside then return end
  QF.ReadLog()
  for id in pairs(QF.inLog) do
    local now = Fulfilled(id)
    local before = progress[id]
    if now and before and now > before then QuestInside(id) end
    progress[id] = now
  end
end

local recorder = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "QUEST_ACCEPTED", "QUEST_LOG_UPDATE" }) do
  pcall(recorder.RegisterEvent, recorder, event)
end
recorder:SetScript("OnEvent", function(_, event, arg1, arg2)
  if not QF.running then return end
  if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
    Entered()
  elseif event == "QUEST_ACCEPTED" then
    -- Classic hands (questLogIndex, questID); newer clients just the ID.
    QuestInside(type(arg2) == "number" and arg2 or arg1)
    if inside then progress[type(arg2) == "number" and arg2 or arg1] = 0 end
  elseif event == "QUEST_LOG_UPDATE" then
    LogChanged()
  end
end)
local elapsed = 0
recorder:SetScript("OnUpdate", function(_, dt)
  elapsed = elapsed + dt
  if elapsed < TICK then return end
  elapsed = 0
  if QF.running then Remember() end
end)
QF.dungeonRecorder = recorder
QF.RecorderState = function() return inside, lastOutside end

-- The recorded dungeons ride along with everything else that's sent in.
local baseExport = QF.ExportLearned
function QF.ExportLearned()
  local text, n = baseExport()
  local lines = {}
  for id, r in pairs(Recorded()) do
    local quests = {}
    for q in pairs(r.quests or {}) do quests[#quests + 1] = q end
    table.sort(quests)
    if r.map or #quests > 0 then
      lines[#lines + 1] = table.concat({ "D", id, r.map or 0,
        r.x and math.floor(r.x * 1000 + 0.5) or 0, r.y and math.floor(r.y * 1000 + 0.5) or 0,
        table.concat(quests, ","), (tostring(r.name or "")):gsub(";", ",") }, ";")
    end
  end
  table.sort(lines)
  if #lines == 0 then return text, n end
  local all = (n > 0 and text ~= "") and (text .. "\n" .. table.concat(lines, "\n")) or table.concat(lines, "\n")
  return all, n + #lines
end
