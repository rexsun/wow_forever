local _, OSG = ...
local adapter = {}
OSG.adapters.YUI = adapter

local UTILITY = {
  NameplateOutline = { field = "nameplateOutline", default = true, runtime = "UtilityToolsNameplateOutline" },
  FriendlyNameplates = { field = "syncFriendlyNameplates", default = false, runtime = "UtilityToolsNameplates" },
}

-- YUI v338's Forever catalog uses configuration-specialization IDs, not retail spec IDs.
local CLASSES = {
  WARRIOR = { specs = { 11650, 11657, 11670 }, resources = { "rage" } },
  PALADIN = { specs = { 11486, 11541, 11559 }, resources = { "mana" } },
  HUNTER = { specs = { 11372, 11371, 11370 }, resources = { "mana" } },
  ROGUE = { specs = { 11580, 11573, 11572 }, resources = { "energy", "comboPoints" } },
  PRIEST = { specs = { 11608, 11615, 11622 }, resources = { "mana" } },
  SHAMAN = { specs = { 11326, 11363, 11362 }, resources = { "mana" } },
  MAGE = { specs = { 11582, 11594, 11601 }, resources = { "mana" } },
  WARLOCK = { specs = { 11629, 11636, 11637 }, resources = { "mana" } },
  DRUID = { specs = { 11328, 11347, 11340 }, resources = { "mana", "rage", "energy", "comboPoints" } },
}
local FORMS = {
  caster = { "mana" }, moonkin = { "mana" }, travel = { "mana" },
  cat = { "energy", "comboPoints", "mana" }, bear = { "rage", "mana" },
}
local pendingRefresh = false

local function LiveProfile()
  local yui = _G.YUI
  if not (type(yui) == "table" and type(yui.DB) == "table" and type(yui.DB.GetProfile) == "function") then
    return nil, "YUI database API is unavailable"
  end
  local profile = yui.DB:GetProfile("suite")
  if type(profile) ~= "table" then return nil, "YUI has not finished loading" end
  return profile
end

local function Profiles(live)
  local list, seen = { { name = "active profile", store = live } }, { [live] = true }
  local profiles = type(_G.YUI_DB) == "table" and _G.YUI_DB.profiles
  for name, profile in pairs(type(profiles) == "table" and profiles or {}) do
    if type(profile) == "table" and not seen[profile] then
      seen[profile] = true
      list[#list + 1] = { name = tostring(name), store = profile }
    end
  end
  return list
end

local function UtilityState(key)
  local live, problem = LiveProfile()
  if not live then return nil, problem end
  local spec = UTILITY[key]
  local runtime = _G.YUI[spec.runtime]
  if not (type(runtime) == "table" and type(runtime.Disable) == "function") then
    return nil, "YUI nameplate runtime API is unavailable"
  end
  return { spec = spec, runtime = runtime, profiles = Profiles(live) }
end

local function UtilityOn(profile, spec)
  local store = type(profile.Components) == "table" and profile.Components or {}
  local config = type(store.UtilityTools_Config) == "table" and store.UtilityTools_Config or {}
  local value = config[spec.field]
  if value == nil and spec.field == "syncFriendlyNameplates" then value = store.SyncFriendlyNameplates end
  if value == nil then value = spec.default end
  return value == true
end

local function ResourceState()
  local live, problem = LiveProfile()
  if not live then return nil, problem end
  local hud = _G.YUI.YHUD
  if not (type(hud) == "table" and type(hud.GetConfigProfile) == "function"
    and type(hud.OnLifecycleConfigChanged) == "function") then
    return nil, "YHUD configuration/refresh API is unavailable"
  end
  local canonical = hud:GetConfigProfile()
  if not (type(canonical) == "table" and type(canonical.resources) == "table"
    and type(canonical.resources.byGroup) == "table") then
    return nil, "YHUD resource schema is unavailable"
  end
  local configs, seen = {}, {}
  local function Visit(node, name)
    if type(node) ~= "table" or seen[node] then return end
    seen[node] = true
    if type(node.resources) == "table" and type(node.resources.byGroup) == "table" then
      for _, config in pairs(node.resources.byGroup) do
        if type(config) == "table" then configs[#configs + 1] = { store = config, name = name } end
      end
    end
    for _, child in pairs(node) do Visit(child, name) end
  end
  Visit(canonical, "active HUD")
  for _, profile in ipairs(Profiles(live)) do Visit(profile.store, profile.name) end
  return { hud = hud, configs = configs }
end

local function ResourceOn(config)
  local fallback = config.selectionDefault ~= "none"
  for class, pack in pairs(CLASSES) do
    local byClass = type(config.bySpec) == "table" and config.bySpec[class]
    for _, spec in ipairs(pack.specs) do
      local selected = type(byClass) == "table" and (byClass[tostring(spec)] or byClass[spec]) or {}
      for _, resource in ipairs(pack.resources) do
        local value = type(selected) == "table" and selected[resource]
        if value == true or (value == nil and fallback) then return true end
      end
    end
  end
  local forms = type(config.formOverrides) == "table" and config.formOverrides.DRUID or {}
  for _, spec in ipairs(CLASSES.DRUID.specs) do
    local overrides = type(forms) == "table" and (forms[tostring(spec)] or forms[spec]) or {}
    for form, resources in pairs(FORMS) do
      local override = type(overrides) == "table" and overrides[form]
      local enabled = type(override) == "table" and override.enabled or {}
      for _, resource in ipairs(resources) do
        local value = type(enabled) == "table" and enabled[resource]
        if value == true or (value == nil and fallback) then return true end
      end
    end
  end
  return false
end

local function Ensure(parent, key)
  if type(parent[key]) ~= "table" then parent[key] = {} end
  return parent[key]
end

local function DisableResources(config)
  local bySpec = Ensure(config, "bySpec")
  for class, pack in pairs(CLASSES) do
    local byClass = Ensure(bySpec, class)
    for _, spec in ipairs(pack.specs) do
      local key = tostring(spec)
      if byClass[key] == nil and type(byClass[spec]) == "table" then byClass[key] = byClass[spec] end
      local selected = Ensure(byClass, key)
      for _, resource in ipairs(pack.resources) do selected[resource] = false end
    end
  end
  local forms = Ensure(Ensure(config, "formOverrides"), "DRUID")
  for _, spec in ipairs(CLASSES.DRUID.specs) do
    local key = tostring(spec)
    if forms[key] == nil and type(forms[spec]) == "table" then forms[key] = forms[spec] end
    local overrides = Ensure(forms, key)
    for form, resources in pairs(FORMS) do
      local enabled = Ensure(Ensure(overrides, form), "enabled")
      for _, resource in ipairs(resources) do enabled[resource] = false end
    end
  end
end

function adapter.Knows(key) return UTILITY[key] ~= nil or key == "Resources" end

function adapter.Read(key)
  if key == "Resources" then
    local state, problem = ResourceState()
    if not state then return nil, problem end
    if pendingRefresh then return true end
    for _, config in ipairs(state.configs) do if ResourceOn(config.store) then return true end end
    return false
  end
  local state, problem = UtilityState(key)
  if not state then return nil, problem end
  if state.runtime.enabled then return true end
  for _, profile in ipairs(state.profiles) do
    if UtilityOn(profile.store, state.spec) then return true end
  end
  return false
end

function adapter.Revert(key)
  if key == "Resources" then
    local state, problem = ResourceState()
    if not state then return false, problem end
    local changed = {}
    for _, config in ipairs(state.configs) do
      if ResourceOn(config.store) then
        DisableResources(config.store)
        changed[config.name] = true
      end
    end
    pendingRefresh = true
    local ok, result, reason = pcall(state.hud.OnLifecycleConfigChanged, state.hud)
    if not ok or result == false or (result == nil and reason ~= nil) then
      return false, "YHUD refresh failed: " .. tostring(ok and reason or result)
    end
    pendingRefresh = false
    local names = {}
    for name in pairs(changed) do if name ~= "active HUD" then names[#names + 1] = name end end
    table.sort(names)
    return true, false, names
  end
  local state, problem = UtilityState(key)
  if not state then return false, problem end
  local names = {}
  for _, profile in ipairs(state.profiles) do
    if UtilityOn(profile.store, state.spec) then
      local store = Ensure(profile.store, "Components")
      Ensure(store, "UtilityTools_Config")[state.spec.field] = false
      if key == "FriendlyNameplates" then store.SyncFriendlyNameplates = nil end
      if profile.name ~= "active profile" then names[#names + 1] = profile.name end
    end
  end
  state.runtime:Disable()
  table.sort(names)
  return true, false, names
end

function adapter.Watch(onChange)
  local hud = _G.YUI and _G.YUI.YHUD
  if hud and type(hud.OnLifecycleConfigChanged) == "function" then
    hooksecurefunc(hud, "OnLifecycleConfigChanged", onChange)
  end
end
