local _, ns = ...

-- /fui probe dungeons -- what does THIS client know about its dungeons?
--
-- The dungeon guide (owner, 27 Sept 2026: "lets start adding this into the
-- addon") needs Forever's own dungeon list, level ranges, entrances, bosses
-- and boss loot. The game may already carry all of it: Forever runs on the
-- modern engine, with an Encounter Journal (bosses, loot, in every client
-- language) and a group finder (dungeons with level ranges). Whether Blizzard
-- FILLED them for Forever -- nine dungeons exist nowhere else -- can only be
-- asked in the client. This asks, and writes the answers into the saved
-- settings (ForeverUIDB.dungeonProbe), where they can be read after a reload.
-- Read-only: nothing here opens a window or changes anything on screen.

-- pcall itself: ok, then every value (nils included), or false and the error.
local function Try(fn, ...)
  if type(fn) ~= "function" then
    return false, "missing"
  end
  return pcall(fn, ...)
end

-- Plain values only: strings, numbers, booleans and small tables of them.
-- Anything secret, or a function, becomes a string that says so.
local function Plain(value, depth)
  depth = depth or 0
  local kind = type(value)
  if kind == "number" or kind == "boolean" or kind == "nil" then
    if issecretvalue and issecretvalue(value) then
      return "<secret>"
    end
    return value
  elseif kind == "string" then
    if issecretvalue and issecretvalue(value) then
      return "<secret>"
    end
    return value
  elseif kind == "table" and depth < 3 then
    local copy = {}
    for k, v in pairs(value) do
      if type(k) == "string" or type(k) == "number" then
        copy[k] = Plain(v, depth + 1)
      end
    end
    return copy
  end
  return "<" .. kind .. ">"
end

local function ProbeJournal(out)
  local journal = { available = type(EJ_GetNumTiers) == "function", tiers = {} }
  out.journal = journal
  if not journal.available then
    return
  end
  local okTiers, tierCount = Try(EJ_GetNumTiers)
  journal.tierCount = okTiers and Plain(tierCount) or tierCount
  if not okTiers or type(tierCount) ~= "number" then
    return
  end
  for tier = 1, math.min(tierCount, 20) do
    Try(EJ_SelectTier, tier)
    local tierEntry = { index = tier, name = Plain(select(2, Try(EJ_GetTierInfo, tier))), instances = {} }
    journal.tiers[#journal.tiers + 1] = tierEntry
    for _, isRaid in ipairs({ false, true }) do
      for i = 1, 80 do
        local ok, instanceID, name = Try(EJ_GetInstanceByIndex, i, isRaid)
        if not ok or not instanceID then
          break
        end
        local entry = { id = Plain(instanceID), name = Plain(name), raid = isRaid, encounters = {} }
        -- name, description, bgImage, button1, lore, button2, dungeonAreaMapID, link, showDifficulty, mapID
        local okInfo, iName, _, _, _, _, _, areaMapID, _, _, mapID = Try(EJ_GetInstanceInfo, instanceID)
        if okInfo then
          entry.areaMapID, entry.mapID, entry.infoName = Plain(areaMapID), Plain(mapID), Plain(iName)
        end
        Try(EJ_SelectInstance, instanceID)
        for e = 1, 30 do
          local okE, eName, _, encounterID, _, _, _, dungeonEncounterID, uiMapID = Try(EJ_GetEncounterInfoByIndex, e, instanceID)
          if not okE or not eName then
            break
          end
          local boss = { name = Plain(eName), id = Plain(encounterID), dungeonEncounterID = Plain(dungeonEncounterID),
            uiMapID = Plain(uiMapID) }
          Try(EJ_SelectEncounter, encounterID)
          local okN, lootCount = Try(EJ_GetNumLoot)
          boss.loot = okN and Plain(lootCount) or lootCount
          -- The first few items, to see what an entry looks like.
          if okN and type(lootCount) == "number" and C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex then
            boss.sample = {}
            for l = 1, math.min(lootCount, 3) do
              local okL, info = Try(C_EncounterJournal.GetLootInfoByIndex, l)
              if okL then boss.sample[#boss.sample + 1] = Plain(info) end
            end
          end
          entry.encounters[#entry.encounters + 1] = boss
        end
        tierEntry.instances[#tierEntry.instances + 1] = entry
      end
    end
  end
end

local function ProbeGroupFinder(out)
  local finder = {}
  out.finder = finder
  local lfg = C_LFGList
  if lfg and lfg.GetAvailableActivities then
    local ok, ids = Try(lfg.GetAvailableActivities)
    finder.activityCount = ok and type(ids) == "table" and #ids or Plain(ids)
    finder.activities = {}
    if ok and type(ids) == "table" then
      for i = 1, math.min(#ids, 400) do
        local okA, info = Try(lfg.GetActivityInfoTable, ids[i])
        if okA then
          finder.activities[#finder.activities + 1] = { id = ids[i], info = Plain(info) }
        end
      end
    end
  end
  -- Every activity by ID, not just the ones this character can join now: a
  -- low-level character is only offered the zones (27 Sept 2026: 41, all
  -- questing). Dungeons are another category.
  if lfg and lfg.GetActivityInfoTable then
    finder.byId = {}
    for id = 1, 3000 do
      local okA, info = Try(lfg.GetActivityInfoTable, id)
      if okA and type(info) == "table" and info.fullName and info.categoryID ~= 116 then
        finder.byId[#finder.byId + 1] = { id = id, info = Plain(info) }
      end
    end
  end
  -- The dungeon table itself, entry by entry (GetLFGDungeonInfo answers for
  -- any ID, whether or not a queue for it is offered).
  if GetLFGDungeonInfo then
    finder.dungeons = {}
    for id = 1, 3000 do
      local okD, name, typeID, subtype, minLevel, maxLevel, recLevel, minRec, maxRec, expansion, groupID, _, _, maxPlayers, description, _, _, _, _, _, _, _, mapID = Try(GetLFGDungeonInfo, id)
      if okD and name then
        finder.dungeons[#finder.dungeons + 1] = { id = id, name = Plain(name), type = Plain(typeID), sub = Plain(subtype),
          min = Plain(minLevel), max = Plain(maxLevel), rec = Plain(recLevel), minRec = Plain(minRec), maxRec = Plain(maxRec),
          exp = Plain(expansion), group = Plain(groupID), players = Plain(maxPlayers), mapID = Plain(mapID),
          desc = Plain(description) }
      end
    end
  end
  -- The older dungeon finder list, where it exists.
  if GetLFDChoiceOrder then
    local ok, order = Try(GetLFDChoiceOrder)
    finder.lfd = {}
    if ok and type(order) == "table" then
      for i = 1, math.min(#order, 200) do
        local okD, name, typeID, subtype, minLevel, maxLevel, recLevel = Try(GetLFGDungeonInfo, order[i])
        if okD then
          finder.lfd[#finder.lfd + 1] = { id = order[i], name = Plain(name), type = Plain(typeID), sub = Plain(subtype),
            min = Plain(minLevel), max = Plain(maxLevel), rec = Plain(recLevel) }
        end
      end
    end
  end
end

-- Every map the game has: its name and type, and the dungeon entrances on it.
local function ProbeMaps(out)
  local maps, entrances = {}, {}
  out.maps, out.entrances = maps, entrances
  if not (C_Map and C_Map.GetMapInfo) then
    return
  end
  local getEntrances = C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap
  for id = 1, 3000 do
    local ok, info = Try(C_Map.GetMapInfo, id)
    if ok and type(info) == "table" and info.name then
      -- Instances (4) and zones (3) are what the guide needs.
      if info.mapType == 3 or info.mapType == 4 or info.mapType == 5 then
        maps[#maps + 1] = { id = id, name = Plain(info.name), type = info.mapType, parent = info.parentMapID }
      end
      if getEntrances and info.mapType == 3 then
        local okE, list = Try(getEntrances, id)
        if okE and type(list) == "table" then
          for _, e in ipairs(list) do
            local pos = e.position
            local x, y
            if pos and pos.GetXY then
              local okXY, px, py = Try(pos.GetXY, pos)
              if okXY then x, y = Plain(px), Plain(py) end
            end
            entrances[#entrances + 1] = { map = id, name = Plain(e.name), journal = Plain(e.journalInstanceID),
              poi = Plain(e.areaPoiID), x = x, y = y }
          end
        end
      end
    end
  end
end

function ns.ProbeDungeons()
  local out = { when = date and date("%Y-%m-%d %H:%M:%S") or "?", build = { Plain(GetBuildInfo()) } }
  local steps = { ProbeJournal, ProbeGroupFinder, ProbeMaps }
  for _, step in ipairs(steps) do
    local ok, err = pcall(step, out)
    if not ok then
      out.errors = out.errors or {}
      out.errors[#out.errors + 1] = tostring(err)
    end
  end
  if ns.db then
    ns.db.dungeonProbe = out
  end
  local instances = 0
  for _, tier in ipairs(out.journal and out.journal.tiers or {}) do
    instances = instances + #tier.instances
  end
  ns.Print(("dungeon probe: journal %s (%d instances), finder %s activities (%d more by ID, %d dungeon entries), "
    .. "%d maps, %d dungeon entrances. Saved -- /reload to write it to disk."):format(
    out.journal and out.journal.available and "yes" or "no", instances,
    tostring(out.finder and out.finder.activityCount or "no"), #(out.finder and out.finder.byId or {}),
    #(out.finder and out.finder.dungeons or {}), #(out.maps or {}), #(out.entrances or {})))
  return out
end
