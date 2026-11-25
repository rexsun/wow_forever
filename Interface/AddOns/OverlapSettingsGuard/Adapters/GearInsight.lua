local _, OSG = ...

local adapter = {}
OSG.adapters.GearInsight = adapter

local KEYS = { FriendlyNameplates = true, CombatHUD = true, LevelingStats = true, ActionBarEditing = true,
  GuildChatLevel = true }
-- GearInsight reads these straight from its saved table and treats nil as on. They are written
-- to GearInsightForeverDB so early rules work before GearInsight publishes ns.db; InitDB keeps an
-- existing table, and its section accessors (Layer.DB, DC.DB, MW.Opts) only fill nil fields.
-- `values` maps a dotted section path to the fields written there; "" is the saved table's root.
local function Call(target, name)
  if type(target) == "table" and type(target[name]) == "function" then target[name]() end
end

local SETTINGS = {
  -- helperV=2 marks GearInsight's one-time migration as done; otherwise it forces helper back on.
  LayerNetwork = { values = { layer = { on = false, pub = false, helper = false, helperV = 2 } },
    apply = function(gi) if type(gi.Layer) == "table" and type(gi.Layer.SyncPub) == "function" then gi.Layer.SyncPub() end end },
  LayerAutoAccept = { values = { layer = { autoAccept = false } } },
  LayerAutoInvite = { values = { layer = { autoHelp = false } } },
  LayerAutoLeave = { values = { layer = { autoLeave = false } } },
  -- Restore reopens friendly nameplates only if GearInsight itself closed them.
  CityPlates = { values = { cityPlates = { on = false } },
    apply = function(gi) if type(gi.CityPlates) == "table" and type(gi.CityPlates.Restore) == "function" then gi.CityPlates.Restore() end end },
  -- qm.thanks gates loading the Group module when a group forms; ui.groupLazy (1.0.1+) gates
  -- loading it at PLAYER_LOGIN.
  GroupAutoLoad = { values = { qm = { thanks = false }, ui = { groupLazy = true } } },
  -- SetSharing also drops messages already queued.
  QuestShare = { values = { qm = { share = false } },
    apply = function(gi) if type(gi.QM) == "table" and type(gi.QM.SetSharing) == "function" then gi.QM.SetSharing(false) end end },
  -- With both off, GroupParts no longer auto-loads GearInsight_Forever_GroupMage for non-Mages. 1.4.x's
  -- soulstone reminder loads it too; BuffAsk's ss = false closes that path.
  MageWater = { values = { ["dchat.mw"] = { fieldAsk = false, thank = false } } },
  -- LR.On() gates every path (whisper, party call-out, GIFLR claims); W and P are a backstop
  -- should a later release stop checking it.
  LowRank = { values = { ui = { lowRank = false, lowRankW = false, lowRankP = false } } },
  -- SyncEvents unregisters the dungeon-entry and nearby-player triggers if the Group module is loaded.
  -- 1.4.x reads a saved dmode (off/ask/auto) before auto, which only decides for saves without one;
  -- ss gates the soulstone reminder, which loads the Mage module in dungeon groups.
  BuffAsk = { values = { buffAsk = { auto = false, field = false, dmode = "off", ss = false } },
    apply = function(gi) Call(gi.BuffAsk, "SyncEvents") end },
  TradeReceipt = { values = { ui = { tradeReceipt = false } } },
  -- Sync swaps a trinket already put on for a mount back; mtBtn.hide removes the carrot icon,
  -- which the Bag module shows whenever a carrot is owned, even with the swap off.
  MountTrinket = { values = { [""] = { mountTrinket = false }, mtBtn = { hide = true } },
    apply = function(gi) Call(gi.MountTrinket, "Sync"); Call(gi.MountTrinket, "BtnUpdate") end },
  AuraRemind = { values = { auraRemind = { on = false } }, apply = function(gi) Call(gi.AuraRemind, "Refresh") end },
  AmmoRemind = { values = { ammoRemind = { on = false } }, apply = function(gi) Call(gi.AmmoRemind, "Update") end },
  -- Prep lives in the load-on-demand Xp module.
  XpPrep = { values = { xpcheck = { prep = false } },
    apply = function(gi) Call(type(gi.XpCheck) == "table" and gi.XpCheck.Prep, "Hide") end },
  -- auto stays at its false default; it is written so a user switch cannot start selling on its own.
  SellJunk = { values = { sellJunk = { panel = false, auto = false } } },
  AuctionPriceTip = { values = { sellJunk = { ahTip = false } } },
  -- No setter exists; both are read whenever a merchant or the auction house opens.
  ProfShopping = { values = { prof = { quick = false, btn = false } } },
  BagButtons = { values = { bagButtons = { show = false } }, apply = function(gi) Call(gi.BagButtons, "ApplyAll") end },
  DungeonNav = { values = { dnav = { on = false } },
    apply = function(gi)
      local frame = type(gi.DungeonNav) == "table" and gi.DungeonNav.frame
      if frame and not gi.DungeonNav.preview then frame:Hide() end
    end },
  -- Refresh hides a floating button that is already up (out of combat; the next one after combat).
  PallyFloat = { values = { pally = { float = false } },
    apply = function(gi) if type(gi.PallyBless) == "table" and type(gi.PallyBless.Refresh) == "function" then gi.PallyBless.Refresh() end end },
  ItemLevel = { values = { ui = { ilvl = false } },
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

local function Section(db, path, create)
  for part in path:gmatch("[^.]+") do
    if type(db[part]) ~= "table" then
      if not create then return nil end
      db[part] = {}
    end
    db = db[part]
  end
  return db
end

local function ReadSetting(spec)
  local db = SavedDB()
  for path, values in pairs(spec.values) do
    local section = db and Section(db, path, false)
    for field, value in pairs(values) do
      if not section or section[field] ~= value then return true end
    end
  end
  return false
end

local function RevertSetting(spec)
  local db = SavedDB()
  if not db then
    _G.GearInsightForeverDB = {}
    db = _G.GearInsightForeverDB
  end
  for path, values in pairs(spec.values) do
    local section = Section(db, path, true)
    for field, value in pairs(values) do section[field] = value end
  end
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
    -- 1.1.x replaced the account-wide leveling.shown with a per-character hide list.
    if type(gi.LevelingShown) == "function" then
      return gi.LevelingShown() and true or Shown(_G.GearInsightForeverLeveling)
    end
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
    if _G.GearInsightForeverLeveling then _G.GearInsightForeverLeveling:Hide() end
    if type(gi.SetLevelingShown) == "function" then
      gi.SetLevelingShown(false)
    else
      gi.db.leveling = gi.db.leveling or {}
      gi.db.leveling.shown = false
    end
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
  for _, spec in ipairs({ { gi, "ToggleLeveling" }, { gi, "SetLevelingShown" }, { gi.KeysHud, "Toggle" },
    { gi.QM, "PlatesOnOpen" }, { gi.QM, "PlatesOnClose" }, { gi.GuildChatLevel, "SetEnabled" },
    { gi.GuildChatLevel, "SetWhisperOn" }, { gi.GuildChatLevel, "SetPartyOn" }, { gi.Layer, "SetPub" },
    { gi.CityPlates, "SetOn" }, { gi.ItemLevel, "SetOn" }, { gi.LowRank, "SetOn" },
    { gi.LowRank, "SetWhisper" }, { gi.LowRank, "SetParty" }, { gi.BuffAsk, "SetOpt" }, { gi.BuffAsk, "SetDMode" },
    { gi.PallyBless, "SetFloat" }, { gi, "SetFeature" }, { gi.TradeReceipt, "SetOn" }, { gi.AuraRemind, "SetOn" },
    { gi.AmmoRemind, "SetOn" }, { gi.DungeonNav, "SetEnabled" }, { gi.SellCfg, "SetOpt" }, { gi.BagButtons, "SetOpt" } }) do
    local target, name = spec[1], spec[2]
    if type(target) == "table" and type(target[name]) == "function" then
      hooksecurefunc(target, name, onChange)
    end
  end
end
