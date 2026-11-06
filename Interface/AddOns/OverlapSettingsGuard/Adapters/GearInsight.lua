local _, OSG = ...

local adapter = {}
OSG.adapters.GearInsight = adapter

local KEYS = { FriendlyNameplates = true, CombatHUD = true, LevelingStats = true, ActionBarEditing = true,
  GuildChatLevel = true }
local EDITS = { "PlaceMissing", "Restore", "AssignSlotKey", "ApplyKeyTemplate", "RestoreStolen",
  "PlaceSpellAt", "ClearSlot", "ClearSpellEverywhere", "ResetMainBar", "UnbindKey" }
adapter.EDITS = EDITS
-- GearInsight's UI reads numeric counts and lists from these actions; ResetMainBar's caller
-- treats nil as "in combat".
local LOCKED_RESULTS = {
  ApplyKeyTemplate = function() return 0, {}, {} end,
  RestoreStolen = function() return 0 end,
  ResetMainBar = function() return 0, {} end,
}
local locks = {}
local warnedMissing = {}

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

local function WarnMissingEdit(name)
  if warnedMissing[name] then return end
  warnedMissing[name] = true
  print("|cffff9933OverlapSettingsGuard|r GearInsight Keys." .. name .. " no longer exists; review the action-bar lock list.")
end

local function MissingAPI(gi, key)
  if key == "CombatHUD" and (type(gi.KeysHud) ~= "table" or type(gi.KeysHud.Toggle) ~= "function") then
    return "GearInsight KeysHud.Toggle is unavailable"
  elseif key == "FriendlyNameplates" then
    -- QM lives in a load-on-demand module, so its absence is normal until that module loads.
    local groupLoaded = C_AddOns.IsAddOnLoaded("GearInsight_Forever_Group")
    if (gi.QM ~= nil or groupLoaded) and (type(gi.QM) ~= "table" or type(gi.QM.PlatesOnClose) ~= "function") then
      return "GearInsight QM.PlatesOnClose is unavailable"
    end
  elseif key == "ActionBarEditing" and type(gi.Keys) ~= "table" then
    return "GearInsight Keys is unavailable"
  elseif key == "GuildChatLevel" and (type(gi.GuildChatLevel) ~= "table"
    or type(gi.GuildChatLevel.Enabled) ~= "function" or type(gi.GuildChatLevel.SetEnabled) ~= "function") then
    return "GearInsight GuildChatLevel is unavailable"
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
    -- Without platesV3, the Group module's one-time migration would set autoPlates back to true.
    -- A pending toggle can only be released once QM exists.
    return q.autoPlates ~= false or q.platesV3 == nil or (gi.QM ~= nil and q.platesWeOpened ~= nil)
  elseif key == "CombatHUD" then
    return gi.db.keysHud == true or Shown(gi.KeysHud.frame)
  elseif key == "LevelingStats" then
    return not gi.db.leveling or gi.db.leveling.shown ~= false or Shown(_G.GearInsightForeverLeveling)
  elseif key == "ActionBarEditing" then
    for _, name in ipairs(EDITS) do
      local edit = gi.Keys[name]
      if type(edit) ~= "function" then
        WarnMissingEdit(name)
      elseif edit ~= locks[name] then
        return true
      end
    end
    return false
  elseif key == "GuildChatLevel" then
    return gi.GuildChatLevel.Enabled() and true or false
  end
  return nil, "unknown GearInsight setting"
end

local function LockEdit(gi, name)
  local original = gi.Keys[name]
  local wrapper = function(...)
    if not OwnerLoaded("YUI") then return original(...) end
    print("|cffff9933OverlapSettingsGuard|r YUI owns action bars and keybindings; use YUI to edit them.")
    if LOCKED_RESULTS[name] then return LOCKED_RESULTS[name]() end
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
    if gi.QM then gi.QM.PlatesOnClose() end
    gi.db.qm.autoPlates = false
    gi.db.qm.platesV3 = 1
  elseif key == "CombatHUD" then
    gi.KeysHud.Toggle(false)
  elseif key == "LevelingStats" then
    gi.db.leveling = gi.db.leveling or {}
    if _G.GearInsightForeverLeveling then _G.GearInsightForeverLeveling:Hide() end
    gi.db.leveling.shown = false
  elseif key == "ActionBarEditing" then
    for _, name in ipairs(EDITS) do
      local edit = gi.Keys[name]
      if type(edit) == "function" and edit ~= locks[name] then LockEdit(gi, name) end
    end
  elseif key == "GuildChatLevel" then
    -- The chat filter reads Enabled() per message, so no reload is needed.
    gi.GuildChatLevel.SetEnabled(false)
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
    { gi.QM, "PlatesOnOpen" }, { gi.QM, "PlatesOnClose" }, { gi.GuildChatLevel, "SetEnabled" } }) do
    local target, name = spec[1], spec[2]
    if type(target) == "table" and type(target[name]) == "function" then
      hooksecurefunc(target, name, onChange)
    end
  end
end
