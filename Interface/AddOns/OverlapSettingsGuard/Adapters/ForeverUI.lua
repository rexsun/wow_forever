local _, OSG = ...

-- ForeverUI keeps its settings in profiles: ForeverUIDB.profiles[name], one per profile,
-- and ForeverUIDB.characters maps each character to one. ForeverUI.db is the active
-- profile and is replaced when the profile changes (Core/Profiles.lua), so it is read
-- fresh every time. A locked setting is switched off in the active profile through
-- ForeverUI's own functions, and in every other stored profile by writing the value, so
-- no character can pick it up again by switching or sharing a profile.
local adapter = {}
OSG.adapters.ForeverUI = adapter

local function UI()
  local ui = _G.ForeverUI
  if type(ui) ~= "table" or type(ui.db) ~= "table" or type(ui.modules) ~= "table" then
    return nil
  end
  return ui
end

local function StoredProfiles(ui)
  local db = _G.ForeverUIDB
  local profiles = {}
  if type(db) == "table" and type(db.profiles) == "table" then
    for name, profile in pairs(db.profiles) do
      if type(profile) == "table" and not rawequal(profile, ui.db) then
        profiles[name] = profile
      end
    end
  end
  return profiles
end

local function ModuleSettings(profile, name)
  profile.modules = profile.modules or {}
  profile.modules[name] = profile.modules[name] or {}
  return profile.modules[name]
end

-- Core/Init.lua IsModuleEnabled: a module with no settings counts as on.
local function ModuleOn(profile, name)
  local s = type(profile.modules) == "table" and profile.modules[name]
  return not s or s.enabled ~= false
end

-- Quests/QuestGuide.lua AutoGuideOn: a missing guideOnAccept counts as on, the
-- controller variant only when true.
local function GuideOn(profile)
  local s = type(profile.modules) == "table" and profile.modules.Quests
  if not s then
    return true
  end
  return s.guideOnAccept ~= false or s.guideOnAcceptPad == true
end

local function GuideOff(profile)
  local s = ModuleSettings(profile, "Quests")
  s.guideOnAccept = false
  s.guideOnAcceptPad = false
end

local function LootSellJunkOn(profile)
  local s = type(profile.modules) == "table" and profile.modules.Loot
  return type(s) == "table" and s.sellJunk == true
end

local SETTINGS = {
  -- Modules/Loot/Loot.lua: off by default, read when a vendor opens.
  LootSellJunk = {
    isOn = LootSellJunkOn,
    switchOff = function(profile) ModuleSettings(profile, "Loot").sellJunk = false end,
    switchOffLive = function(ui)
      ModuleSettings(ui.db, "Loot").sellJunk = false
      ui.RefreshOptions()
      return true
    end,
  },
  QuestForeverModule = {
    isOn = function(profile) return ModuleOn(profile, "QuestForever") end,
    switchOff = function(profile) ModuleSettings(profile, "QuestForever").enabled = false end,
    -- Toggle stops QuestForever's pins and refreshes the options page.
    switchOffLive = function(ui)
      local module = ui.modules.QuestForever
      if not (module and module.Toggle) then
        return false, "ForeverUI has no QuestForever module"
      end
      module.Toggle(false)
      return true
    end,
  },
  ArrowModule = {
    isOn = function(profile) return ModuleOn(profile, "Arrow") end,
    switchOff = function(profile) ModuleSettings(profile, "Arrow").enabled = false end,
    switchOffLive = function(ui)
      if not ui.modules.Arrow then
        return false, "ForeverUI has no Arrow module"
      end
      ui.SetModuleEnabled("Arrow", false)
      ui.RefreshOptions()
      return true
    end,
  },
  QuestGuideOnAccept = {
    isOn = GuideOn,
    switchOff = GuideOff,
    switchOffLive = function(ui)
      GuideOff(ui.db)
      local quests = ui.modules.Quests
      if quests and quests.PaintAutoLine then
        quests.PaintAutoLine()
      end
      ui.RefreshOptions()
      return true
    end,
  },
}

function adapter.Knows(key)
  return SETTINGS[key] ~= nil
end

function adapter.Read(key)
  local ui = UI()
  if not ui then
    return nil, "ForeverUI has not finished loading"
  end
  local setting = SETTINGS[key]
  if setting.isOn(ui.db) then
    return true
  end
  for _, profile in pairs(StoredProfiles(ui)) do
    if setting.isOn(profile) then
      return true
    end
  end
  return false
end

-- Returns true, false (ForeverUI asks for its own reload when a module needs one), and
-- the names of the other profiles that were changed.
function adapter.Revert(key)
  local ui = UI()
  if not ui then
    return false, "ForeverUI has not finished loading"
  end
  local setting = SETTINGS[key]
  if setting.isOn(ui.db) then
    local ok, reverted, problem = pcall(setting.switchOffLive, ui)
    if not ok then
      return false, tostring(reverted)
    end
    if not reverted then
      return false, problem
    end
  end
  local changed = {}
  for name, profile in pairs(StoredProfiles(ui)) do
    if setting.isOn(profile) then
      setting.switchOff(profile)
      changed[#changed + 1] = tostring(name)
    end
  end
  table.sort(changed)
  return true, false, changed
end

-- Every options widget, profile switch and module toggle ends in RefreshOptions or
-- SetModuleEnabled. `/fui quests guide` and the guide's "click to change" line skip
-- both; PaintAutoLine catches the second, Guard.lua's ticker the first.
function adapter.Watch(onChange)
  local ui = _G.ForeverUI
  if type(ui) ~= "table" then
    return
  end
  for _, name in ipairs({ "RefreshOptions", "SetModuleEnabled" }) do
    if type(ui[name]) == "function" then
      hooksecurefunc(ui, name, onChange)
    end
  end
  local quests = type(ui.modules) == "table" and ui.modules.Quests
  if quests and type(quests.PaintAutoLine) == "function" then
    hooksecurefunc(quests, "PaintAutoLine", onChange)
  end
end
