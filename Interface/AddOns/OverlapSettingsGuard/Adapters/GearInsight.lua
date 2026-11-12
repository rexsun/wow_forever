local _, OSG = ...

local adapter = {}
OSG.adapters.GearInsight = adapter

local KEYS = { FriendlyNameplates = true, CombatHUD = true, LevelingStats = true, ActionBarEditing = true,
  GuildChatLevel = true }
-- GearInsight 1.0.x reads these straight from its saved table and treats nil as on. They are
-- written to GearInsightForeverDB so early rules work before GearInsight publishes ns.db;
-- InitDB keeps an existing table, and Layer.DB() only fills nil fields.
local SETTINGS = {
  -- helperV=2 marks GearInsight's one-time migration as done; otherwise it forces helper back on.
  LayerNetwork = { section = "layer", values = { on = false, pub = false, helper = false, helperV = 2 },
    apply = function(gi) if type(gi.Layer) == "table" and type(gi.Layer.SyncPub) == "function" then gi.Layer.SyncPub() end end },
  LayerAutoAccept = { section = "layer", values = { autoAccept = false } },
  LayerAutoInvite = { section = "layer", values = { autoHelp = false } },
  LayerAutoLeave = { section = "layer", values = { autoLeave = false } },
  -- Restore reopens friendly nameplates only if GearInsight itself closed them.
  CityPlates = { section = "cityPlates", values = { on = false },
    apply = function(gi) if type(gi.CityPlates) == "table" and type(gi.CityPlates.Restore) == "function" then gi.CityPlates.Restore() end end },
  -- qm.thanks is the only switch UI.lua checks before loading the Group module in a group.
  GroupAutoLoad = { section = "qm", values = { thanks = false } },
  ItemLevel = { section = "ui", values = { ilvl = false },
    apply = function(gi) if type(gi.ItemLevel) == "table" and type(gi.ItemLevel.RefreshAll) == "function" then gi.ItemLevel.RefreshAll() end end },
}
local CHAT_SETTERS = { "SetEnabled", "SetWhisperOn", "SetPartyOn" }
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
  elseif key == "GuildChatLevel" then
    local chat = gi.GuildChatLevel
    if type(chat) ~= "table" then return "GearInsight GuildChatLevel is unavailable" end
    for _, name in ipairs({ "Enabled", "WhisperOn", "PartyOn", "SetEnabled", "SetWhisperOn", "SetPartyOn" }) do
      if type(chat[name]) ~= "function" then return "GearInsight GuildChatLevel." .. name .. " is unavailable" end
    end
  end
end

local function SavedDB()
  local gi = Live()
  if gi then return gi.db end
  if type(_G.GearInsightForeverDB) == "table" then return _G.GearInsightForeverDB end
end

local function ReadSetting(spec)
  local db = SavedDB()
  local section = db and db[spec.section]
  for field, value in pairs(spec.values) do
    if type(section) ~= "table" or section[field] ~= value then return true end
  end
  return false
end

local function RevertSetting(spec)
  local db = SavedDB()
  if not db then
    _G.GearInsightForeverDB = {}
    db = _G.GearInsightForeverDB
  end
  if type(db[spec.section]) ~= "table" then db[spec.section] = {} end
  for field, value in pairs(spec.values) do db[spec.section][field] = value end
  local gi = Live()
  if gi and spec.apply then
    local ok, err = pcall(spec.apply, gi)
    if not ok then return false, "GearInsight refresh failed: " .. tostring(err) end
  end
  return true, false
end

function adapter.Knows(key)
  return KEYS[key] == true or SETTINGS[key] ~= nil
end

function adapter.Read(key)
  if SETTINGS[key] then return ReadSetting(SETTINGS[key]) end
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
    local chat = gi.GuildChatLevel
    return (chat.Enabled() or chat.WhisperOn() or chat.PartyOn()) and true or false
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
  if SETTINGS[key] then return RevertSetting(SETTINGS[key]) end
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
    -- The chat filters read their switches per message, so no reload is needed.
    for _, name in ipairs(CHAT_SETTERS) do gi.GuildChatLevel[name](false) end
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
    { gi.QM, "PlatesOnOpen" }, { gi.QM, "PlatesOnClose" }, { gi.GuildChatLevel, "SetEnabled" },
    { gi.GuildChatLevel, "SetWhisperOn" }, { gi.GuildChatLevel, "SetPartyOn" }, { gi.Layer, "SetPub" },
    { gi.CityPlates, "SetOn" }, { gi.ItemLevel, "SetOn" } }) do
    local target, name = spec[1], spec[2]
    if type(target) == "table" and type(target[name]) == "function" then
      hooksecurefunc(target, name, onChange)
    end
  end
end
