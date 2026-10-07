local _, ns = ...

-- /fui quests probe
--
-- Before building a Questie-style quest module on the game's own data, find
-- out what the Forever client actually hands an addon where you stand (owner,
-- 24 Sept 2026: "Could we create a Questie type modular Quest ... can we pull
-- that based on public data"). Public quest databases are either unlicensed
-- (Questie) or GPL and 2006-era (the MaNGOS ones); the client itself carries
-- Blizzard's live quest data for every map through these functions:
--
--   C_QuestLine.GetAvailableQuestLines(map)   quests you can pick up, with x/y
--   C_QuestLine.GetQuestLineQuests(line)      a whole chain, in order
--   C_QuestLog.GetQuestsOnMap(map)            your active quests' map spots
--   C_QuestLog.GetNextWaypoint(quest)         where to go next for a quest
--
-- Whether Blizzard filled them in for Forever's zones is the question. This
-- asks each one for your map and the maps above it, and shows every answer -
-- including "missing", "refused" and "secret" - in a window to copy.

local module = ns.GetModule("Quests")

local function S(value)
  if issecretvalue and issecretvalue(value) then return "<secret>" end
  return tostring(value)
end

local function Coord(value)
  if issecretvalue and issecretvalue(value) then return "<secret>" end
  if type(value) ~= "number" then return "?" end
  return ("%.1f"):format(value * 100)
end

-- pcall that also says why: "missing" when the function isn't there at all.
local function Ask(t, name, ...)
  local fn = t and t[name]
  if type(fn) ~= "function" then return false, "missing" end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then return false, "refused: " .. tostring(a):gsub("^.-:%d+: ", "") end
  return true, a, b, c, d
end

local function MapName(id)
  local ok, info = Ask(C_Map, "GetMapInfo", id)
  return ok and type(info) == "table" and S(info.name) or "?", ok and type(info) == "table" and info.parentMapID or nil
end

-- The maps to ask: where you are, then each map above it (zone, continent).
function module.ProbeMaps()
  local maps = {}
  local ok, id = Ask(C_Map, "GetBestMapForUnit", "player")
  local depth = 0
  while ok and type(id) == "number" and id > 0 and depth < 4 do
    local name, parent = MapName(id)
    maps[#maps + 1] = { id = id, name = name }
    id, depth = parent, depth + 1
  end
  if ok then
    return maps, nil
  end
  return maps, id -- the refusal, for the report
end

local FLAGS = { "isImportant", "isCampaign", "isLocalStory", "isDaily", "isQuestStart", "inProgress", "isHidden" }

function module.ProbeReport()
  local lines = {}
  local function add(fmt, ...) lines[#lines + 1] = fmt:format(...) end
  local build = GetBuildInfo and select(2, GetBuildInfo()) or "?"
  add("ForeverUI quest probe - client build %s", S(build))
  local maps, why = module.ProbeMaps()
  if #maps == 0 then
    add("No map for the player: %s", S(why or "none"))
  end
  local firstLine
  for _, map in ipairs(maps) do
    add("")
    add("== Map %d: %s", map.id, map.name)
    local ok, quests = Ask(C_QuestLine, "GetAvailableQuestLines", map.id)
    if not ok then
      add("  available quests: %s", S(quests))
    else
      quests = type(quests) == "table" and quests or {}
      add("  available quests: %d", #quests)
      for i, q in ipairs(quests) do
        if i > 10 then add("    ... and %d more", #quests - 10); break end
        local flags = {}
        for _, f in ipairs(FLAGS) do
          if q[f] == true then flags[#flags + 1] = f:gsub("^is", ""):lower() end
        end
        add("    %s [%s] at %s,%s  line %s \"%s\"%s", S(q.questName), S(q.questID), Coord(q.x), Coord(q.y),
          S(q.questLineID), S(q.questLineName), #flags > 0 and ("  (" .. table.concat(flags, ", ") .. ")") or "")
        firstLine = firstLine or q.questLineID
      end
    end
    local okOn, onMap = Ask(C_QuestLog, "GetQuestsOnMap", map.id)
    if not okOn then
      add("  your quests on this map: %s", S(onMap))
    else
      onMap = type(onMap) == "table" and onMap or {}
      add("  your quests on this map: %d", #onMap)
      for i, q in ipairs(onMap) do
        if i > 5 then break end
        add("    quest %s at %s,%s", S(q.questID), Coord(q.x), Coord(q.y))
      end
    end
    local okForce, forced = Ask(C_QuestLine, "GetForceVisibleQuests", map.id)
    add("  always-shown quests: %s", okForce and tostring(type(forced) == "table" and #forced or 0) or S(forced))
    local okPoi, pois = Ask(C_AreaPoiInfo, "GetAreaPOIForMap", map.id)
    add("  map points of interest: %s", okPoi and tostring(type(pois) == "table" and #pois or 0) or S(pois))
  end
  if firstLine and not (issecretvalue and issecretvalue(firstLine)) then
    local ok, chain = Ask(C_QuestLine, "GetQuestLineQuests", firstLine)
    add("")
    add("Chain of quest line %s: %s", S(firstLine),
      ok and (tostring(type(chain) == "table" and #chain or 0) .. " quests") or S(chain))
  end
  -- Your tracked quest: where does the game say to go next?
  add("")
  local okTrack, tracked = Ask(C_SuperTrack, "GetSuperTrackedQuestID")
  if okTrack and type(tracked) == "number" and tracked > 0 then
    local ok, wMap, wx, wy = Ask(C_QuestLog, "GetNextWaypoint", tracked)
    add("Tracked quest %s: next waypoint %s", S(tracked),
      ok and (wMap and ("map " .. S(wMap) .. " at " .. Coord(wx) .. "," .. Coord(wy)) or "none") or S(wMap))
    local okText, text = Ask(C_QuestLog, "GetNextWaypointText", tracked)
    if okText and text then add("  waypoint text: %s", S(text)) end
  else
    add("Tracked quest: %s", okTrack and "none (track one to test waypoints)" or S(tracked))
  end
  local okNum, count = Ask(C_QuestLog, "GetNumQuestLogEntries")
  add("Quest log entries: %s", okNum and S(count) or S(count))
  return lines
end

-- The questline data may need asking for first; give it a moment, then show.
function module.Probe(delay)
  for _, map in ipairs((module.ProbeMaps())) do
    Ask(C_QuestLine, "RequestQuestLinesForMap", map.id)
  end
  local function show()
    local lines = module.ProbeReport()
    module.lastProbe = lines
    if ns.ShowTextPopup then
      ns.ShowTextPopup("Quest probe", table.concat(lines, "\n"))
    end
    ns.Print(("quest probe: %d lines - copy them from the window."):format(#lines))
  end
  if C_Timer and C_Timer.After and (delay or 1.5) > 0 then
    C_Timer.After(delay or 1.5, show)
  else
    show()
  end
end
