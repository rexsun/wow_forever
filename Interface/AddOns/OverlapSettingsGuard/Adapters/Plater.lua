local _, OSG = ...

local adapter = {}
OSG.adapters.Plater = adapter
local reverting = false

local function LiveProfile()
  local plater = _G.Plater
  return type(plater) == "table" and type(plater.db) == "table" and plater.db.profile or nil
end

local function Profiles(live)
  local copies = { { name = "active", store = live } }
  local stored = type(_G.PlaterDB) == "table" and _G.PlaterDB.profiles
  for name, profile in pairs(type(stored) == "table" and stored or {}) do
    if type(profile) == "table" and not rawequal(profile, live) then
      copies[#copies + 1] = { name = tostring(name), store = profile }
    end
  end
  return copies
end

local function Enabled(key, profile)
  if key == "Resources" then
    local resources = profile.resources_settings
    local settings = type(resources) == "table" and resources.global_settings
    return type(settings) == "table" and settings.show == true
  end
  local saved = profile.saved_cvars
  return type(saved) == "table" and tostring(saved.nameplateShowSelf) == "1"
end

function adapter.Knows(key)
  return key == "Resources" or key == "PersonalBar"
end

function adapter.Read(key)
  local live = LiveProfile()
  if type(live) ~= "table" then return nil, "Plater has not finished loading" end
  if key == "PersonalBar" then
    local value = GetCVar("nameplateShowSelf")
    if value == nil then return nil, "personal nameplate CVar is unavailable" end
    if tostring(value) == "1" then return true end
  end
  for _, copy in ipairs(Profiles(live)) do
    if Enabled(key, copy.store) then return true end
  end
  return false
end

function adapter.Revert(key)
  local live = LiveProfile()
  if type(live) ~= "table" then return false, "Plater has not finished loading" end
  local changed = {}
  for _, copy in ipairs(Profiles(live)) do
    if Enabled(key, copy.store) then
      if key == "Resources" then
        copy.store.resources_settings.global_settings.show = false
      else
        copy.store.saved_cvars.nameplateShowSelf = "0"
      end
      if copy.name ~= "active" then changed[#changed + 1] = copy.name end
    end
  end
  if key == "PersonalBar" then SetCVar("nameplateShowSelf", "0") end
  reverting = true
  local plater = _G.Plater
  local success, problem = pcall(plater.RefreshConfig, plater)
  reverting = false
  if not success then return false, tostring(problem) end
  table.sort(changed)
  return true, false, changed
end

function adapter.Watch(onChange)
  local plater = _G.Plater
  if type(plater) == "table" and type(plater.RefreshConfig) == "function" then
    hooksecurefunc(plater, "RefreshConfig", function()
      if not reverting then onChange() end
    end)
  end
end
