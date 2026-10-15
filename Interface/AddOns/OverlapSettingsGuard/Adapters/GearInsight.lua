local _, OSG = ...

local adapter = {}
OSG.adapters.GearInsight = adapter

local KEYS = { FriendlyNameplates = true, CombatHUD = true, LevelingStats = true, ActionBarEditing = true }
local EDITS = { "ApplyAll", "PlaceMissing", "Restore", "AssignSlotKey", "ApplyKeyTemplate", "RestoreStolen" }
local locks = {}

local function Live()
  local gi = _G.GearInsightForever
  if type(gi) == "table" and type(gi.db) == "table" then return gi end
end

local function Shown(frame)
  return frame and frame:IsShown() or false
end

local function OwnerLoaded(name)
  return C_AddOns.IsAddOnLoaded(name) and true or false
end

local function MissingAPI(gi, key)
  if key == "CombatHUD" and (type(gi.KeysHud) ~= "table" or type(gi.KeysHud.Toggle) ~= "function") then
    return "GearInsight KeysHud.Toggle is unavailable"
  elseif key == "FriendlyNameplates" and (type(gi.QM) ~= "table" or type(gi.QM.PlatesOnClose) ~= "function") then
    return "GearInsight QM.PlatesOnClose is unavailable"
  elseif key == "ActionBarEditing" then
    for _, name in ipairs(EDITS) do
      if type(gi.Keys) ~= "table" or type(gi.Keys[name]) ~= "function" then
        return "GearInsight Keys." .. name .. " is unavailable"
      end
    end
  end
end

function adapter.Knows(key)
  return KEYS[key] == true
end

function adapter.Read(key)
  local gi = Live()
  if not gi then return nil, "GearInsight has not finished loading" end
  local problem = MissingAPI(gi, key)
  if problem then return nil, problem end
  if key == "FriendlyNameplates" then
    local q = gi.db.qm or {}
    return q.autoPlates ~= false or q.platesWeOpened ~= nil
  elseif key == "CombatHUD" then
    return gi.db.keysHud == true or Shown(gi.KeysHud.frame)
  elseif key == "LevelingStats" then
    return not gi.db.leveling or gi.db.leveling.shown ~= false or Shown(_G.GearInsightForeverLeveling)
  elseif key == "ActionBarEditing" then
    for _, name in ipairs(EDITS) do
      if not locks[name] or gi.Keys[name] ~= locks[name] then return true end
    end
    return false
  end
  return nil, "unknown GearInsight setting"
end

local function LockEdit(gi, name)
  local original = gi.Keys[name]
  local wrapper = function(...)
    if not OwnerLoaded("YUI") then return original(...) end
    print("|cffff9933OverlapSettingsGuard|r YUI owns action bars and keybindings; use YUI to edit them.")
    -- GearInsight's UI expects numeric counts and lists from these two actions.
    if name == "ApplyKeyTemplate" then return 0, {}, {} end
    if name == "RestoreStolen" then return 0 end
    return false, "YUI owns action bars and keybindings"
  end
  locks[name] = wrapper
  gi.Keys[name] = wrapper
end

function adapter.Revert(key)
  local gi = Live()
  if not gi then return false, "GearInsight has not finished loading" end
  local problem = MissingAPI(gi, key)
  if problem then return false, problem end
  if key == "FriendlyNameplates" then
    gi.db.qm = gi.db.qm or {}
    gi.QM.PlatesOnClose()
    gi.db.qm.autoPlates = false
  elseif key == "CombatHUD" then
    gi.KeysHud.Toggle(false)
  elseif key == "LevelingStats" then
    gi.db.leveling = gi.db.leveling or {}
    if _G.GearInsightForeverLeveling then _G.GearInsightForeverLeveling:Hide() end
    gi.db.leveling.shown = false
  elseif key == "ActionBarEditing" then
    for _, name in ipairs(EDITS) do
      if gi.Keys[name] ~= locks[name] then LockEdit(gi, name) end
    end
  else
    return false, "unknown GearInsight setting"
  end
  local on, detail = adapter.Read(key)
  if on ~= false then return false, detail or "GearInsight did not disable the feature" end
  return true, false
end

function adapter.Watch(onChange)
  local gi = Live()
  if not gi then return end
  for _, spec in ipairs({ { gi, "ToggleLeveling" }, { gi.KeysHud, "Toggle" },
    { gi.QM, "PlatesOnOpen" }, { gi.QM, "PlatesOnClose" } }) do
    local target, name = spec[1], spec[2]
    if type(target) == "table" and type(target[name]) == "function" then
      hooksecurefunc(target, name, onChange)
    end
  end
end
