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

-- A context edited in YUI's resource manager reads itemsByContext instead of bySpec.
local function ContextResources(context, key)
  if PLAYER_RESOURCES[key] then return PLAYER_RESOURCES[key] end
  local class, form = tostring(context):match("^(%u+):%d+:(.*)$")
  local pack = CLASSES[class]
  if not pack then return {} end
  return FORMS[form] or pack.resources
end

local function GuardedContextItems(config, key)
  local found = {}
  local contexts = type(config.itemsByContext) == "table" and config.itemsByContext or {}
  for context, items in pairs(contexts) do
    local guarded = {}
    for _, resource in ipairs(ContextResources(context, key)) do guarded[resource] = true end
    for _, item in ipairs(type(items) == "table" and items or {}) do
      if type(item) == "table" and guarded[item.id] and item.enabled == true then found[#found + 1] = item end
    end
  end
  return found
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
  return #GuardedContextItems(config, key) > 0
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
  for _, item in ipairs(GuardedContextItems(config, resourceKey)) do item.enabled = false end
end

local function ChatState()
  local live, problem = LiveProfile()
  if not live then return nil, problem end
  local chat = _G.YUI.YChat
  if not (type(chat) == "table" and type(chat.GetMessageFilter) == "function"
    and type(chat.SetMessageFilterEnabled) == "function") then
    return nil, "YChat message filter API is unavailable"
  end
  local active = chat:GetMessageFilter()
  if type(active) ~= "table" then return nil, "YChat has not finished loading" end
  local stored = {}
  for _, profile in ipairs(Profiles(live)) do
    local db = profile.store.YChat
    if type(db) == "table" and db.messageFilter ~= active then
      stored[#stored + 1] = { name = profile.name, db = db }
    end
  end
  return { chat = chat, active = active, stored = stored }
end

-- YChat normalizes a missing filter, or one without enabled == false, to on.
local function StoredChatFilterOn(db)
  return type(db.messageFilter) ~= "table" or db.messageFilter.enabled ~= false
end

local function ReadChatFilter()
  local state, problem = ChatState()
  if not state then return nil, problem end
  if state.active.enabled ~= false then return true end
  for _, profile in ipairs(state.stored) do
    if StoredChatFilterOn(profile.db) then return true end
  end
  return false
end

local function RevertChatFilter()
  local state, problem = ChatState()
  if not state then return false, problem end
  local names = {}
  for _, profile in ipairs(state.stored) do
    if StoredChatFilterOn(profile.db) then
      if type(profile.db.messageFilter) ~= "table" then profile.db.messageFilter = {} end
      profile.db.messageFilter.enabled = false
      if profile.name ~= "active profile" then names[#names + 1] = profile.name end
    end
  end
  if state.active.enabled ~= false then
    local done, reason = state.chat:SetMessageFilterEnabled(false)
    if not done then return false, "YChat refresh failed: " .. tostring(reason) end
  end
  table.sort(names)
  return true, false, names
end

function adapter.Knows(key)
  return UTILITY[key] ~= nil or key == "Resources" or PLAYER_RESOURCES[key] ~= nil or key == "ChatKeywordFilter"
end

function adapter.Read(key)
  if key == "ChatKeywordFilter" then return ReadChatFilter() end
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
  if key == "ChatKeywordFilter" then return RevertChatFilter() end
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
  local chat = _G.YUI and _G.YUI.YChat
  if chat and type(chat.SetMessageFilterEnabled) == "function" then
    hooksecurefunc(chat, "SetMessageFilterEnabled", onChange)
  end
end
