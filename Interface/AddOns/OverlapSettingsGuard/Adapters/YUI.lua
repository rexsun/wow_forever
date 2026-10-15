local _, OSG = ...
local adapter = {}
OSG.adapters.YUI = adapter

local UTILITY = {
  NameplateOutline = { field = "nameplateOutline", default = true, runtime = "UtilityToolsNameplateOutline" },
  FriendlyNameplates = { field = "syncFriendlyNameplates", default = false, runtime = "UtilityToolsNameplates" },
}

-- Forever uses configuration-specialization IDs, not retail spec IDs.
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
local pendingRefresh = {}
local PLAYER_RESOURCES = { PlayerHealth = { "health" }, PlayerCast = { "cast" } }

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
  local configs, castGroups, nativeCast, seen = {}, {}, {}, {}
  local function Visit(node, name)
    if type(node) ~= "table" or seen[node] then return end
    seen[node] = true
    local groups = type(node.groups) == "table" and node.groups.items
    for _, group in pairs(type(groups) == "table" and groups or {}) do
      if type(group) == "table" and group.layout == "resource" and group.contentPolicy == "cast-only" then
        castGroups[#castGroups + 1] = { store = group, name = name }
      end
    end
    if type(node.playerCast) == "table" then
      nativeCast[#nativeCast + 1] = { store = node.playerCast, name = name }
    end
    if type(node.resources) == "table" and type(node.resources.byGroup) == "table" then
      for _, config in pairs(node.resources.byGroup) do
        if type(config) == "table" then configs[#configs + 1] = { store = config, name = name } end
      end
    end
    for _, child in pairs(node) do Visit(child, name) end
  end
  Visit(canonical, "active HUD")
  for _, profile in ipairs(Profiles(live)) do Visit(profile.store, profile.name) end
  return { hud = hud, configs = configs, castGroups = castGroups, nativeCast = nativeCast }
end

local function ResourceOn(config, key)
  local fallback = key == "Resources" and config.selectionDefault ~= "none"
  for class, pack in pairs(CLASSES) do
    local byClass = type(config.bySpec) == "table" and config.bySpec[class]
    for _, spec in ipairs(pack.specs) do
      local selected = type(byClass) == "table" and (byClass[tostring(spec)] or byClass[spec]) or {}
      for _, resource in ipairs(PLAYER_RESOURCES[key] or pack.resources) do
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
      for _, resource in ipairs(PLAYER_RESOURCES[key] or resources) do
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

local function DisableResources(config, resourceKey)
  local bySpec = Ensure(config, "bySpec")
  for class, pack in pairs(CLASSES) do
    local byClass = Ensure(bySpec, class)
    for _, spec in ipairs(pack.specs) do
      local key = tostring(spec)
      if byClass[key] == nil and type(byClass[spec]) == "table" then byClass[key] = byClass[spec] end
      local selected = Ensure(byClass, key)
      for _, resource in ipairs(PLAYER_RESOURCES[resourceKey] or pack.resources) do selected[resource] = false end
    end
  end
  local forms = Ensure(Ensure(config, "formOverrides"), "DRUID")
  for _, spec in ipairs(CLASSES.DRUID.specs) do
    local key = tostring(spec)
    if forms[key] == nil and type(forms[spec]) == "table" then forms[key] = forms[spec] end
    local overrides = Ensure(forms, key)
    for form, resources in pairs(FORMS) do
      local enabled = Ensure(Ensure(overrides, form), "enabled")
      for _, resource in ipairs(PLAYER_RESOURCES[resourceKey] or resources) do enabled[resource] = false end
    end
  end
end

function adapter.Knows(key) return UTILITY[key] ~= nil or key == "Resources" or PLAYER_RESOURCES[key] ~= nil end

function adapter.Read(key)
  if key == "Resources" or PLAYER_RESOURCES[key] then
    local state, problem = ResourceState()
    if not state then return nil, problem end
    if pendingRefresh[key] then return true end
    for _, config in ipairs(state.configs) do if ResourceOn(config.store, key) then return true end end
    if key == "PlayerCast" then
      for _, group in ipairs(state.castGroups) do if group.store.enabled ~= false then return true end end
      for _, config in ipairs(state.nativeCast) do if config.store.hideNative == true then return true end end
    end
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
  if key == "Resources" or PLAYER_RESOURCES[key] then
    local state, problem = ResourceState()
    if not state then return false, problem end
    local changed = {}
    for _, config in ipairs(state.configs) do
      if ResourceOn(config.store, key) then
        DisableResources(config.store, key)
        changed[config.name] = true
      end
    end
    if key == "PlayerCast" then
      for _, group in ipairs(state.castGroups) do
        if group.store.enabled ~= false then
          group.store.enabled = false
          changed[group.name] = true
        end
      end
      for _, config in ipairs(state.nativeCast) do
        if config.store.hideNative == true then
          config.store.hideNative = false
          changed[config.name] = true
        end
      end
    end
    pendingRefresh[key] = true
    local ok, result, reason = pcall(state.hud.OnLifecycleConfigChanged, state.hud)
    if not ok or result == false or (result == nil and reason ~= nil) then
      return false, "YHUD refresh failed: " .. tostring(ok and reason or result)
    end
    pendingRefresh[key] = nil
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
