local _, OSG = ...
local adapter = {}
OSG.adapters.Skinner = adapter
local watched = setmetatable({}, { __mode = "k" })

local function Setting(key)
  for _, rule in ipairs(OSG.policy) do
    if rule.adapter == "Skinner" and rule.key == key then return rule end
  end
end

local function Path(rule, field)
  if rule.root then return { rule.root, field } end
  if rule.namespace then return { field } end
  local path = {}
  for part in field:gmatch("[^.]+") do path[#path + 1] = part end
  return path
end

local function Get(node, path)
  for _, part in ipairs(path) do
    if node == nil then return nil end
    if type(node) ~= "table" then return nil, "Skinner setting contains an invalid parent value" end
    node = node[part]
  end
  return node
end

local function State(rule)
  local skin = _G.Skinner
  if not (type(skin) == "table" and type(skin.db) == "table" and type(skin.db.profile) == "table") then
    return nil, "Skinner database is unavailable"
  end
  local db, saved = skin.db, skin.db.sv or _G.SkinnerDB
  if rule.namespace then
    if type(db.GetNamespace) ~= "function" then return nil, "Skinner namespace API is unavailable" end
    db = db:GetNamespace(rule.namespace, true)
    if not (db and type(db.profile) == "table") then return nil, "Skinner UnitFrames namespace is unavailable" end
    saved = saved and saved.namespaces and saved.namespaces[rule.namespace]
  end
  local copies, seen = {}, {}
  local function Add(profile, name)
    if type(profile) == "table" and not seen[profile] then
      seen[profile] = true
      copies[#copies + 1] = { profile = profile, name = name }
    end
  end
  Add(db.profile, "active profile")
  if not rule.namespace then Add(skin.prdb, "active skin cache") end
  for name, profile in pairs(saved and saved.profiles or {}) do Add(profile, tostring(name)) end
  local defaults = db.defaults and db.defaults.profile or {}
  for _, copy in ipairs(copies) do
    for _, field in ipairs(rule.fields) do
      local path = Path(rule, field)
      local value, problem = Get(copy.profile, path)
      if problem then return nil, problem end
      if value == nil then value, problem = Get(defaults, path) end
      if problem then return nil, problem end
      if value ~= nil and type(value) ~= "boolean" then return nil, "Skinner setting is not boolean: " .. field end
    end
  end
  return { skin = skin, copies = copies, defaults = defaults }
end

function adapter.Knows(key)
  local rule = Setting(key)
  return rule ~= nil and type(rule.fields) == "table" and #rule.fields > 0
end

function adapter.Read(key)
  local rule = Setting(key)
  if not rule then return nil, "unknown Skinner setting" end
  local state, problem = State(rule)
  if not state then return nil, problem end
  for _, copy in ipairs(state.copies) do
    for _, field in ipairs(rule.fields) do
      local path = Path(rule, field)
      local value = Get(copy.profile, path)
      if value == nil then value = Get(state.defaults, path) end
      if (value == true) ~= rule.value then return true end
    end
  end
  return false
end

function adapter.Revert(key)
  local rule = Setting(key)
  if not rule then return false, "unknown Skinner setting" end
  local state, problem = State(rule)
  if not state then return false, problem end
  local names, reload = {}, false
  for _, copy in ipairs(state.copies) do
    local changed = false
    for _, field in ipairs(rule.fields) do
      local path = Path(rule, field)
      local node = copy.profile
      for i = 1, #path - 1 do
        if node[path[i]] == nil then node[path[i]] = {} end
        node = node[path[i]]
      end
      if node[path[#path]] ~= rule.value then changed = true end
      node[path[#path]] = rule.value
      local initialized = state.skin.initialized or {}
      reload = reload or initialized[path[1]] == true or initialized[rule.namespace] == true
      if rule.root == "DisabledSkins" then
        reload = reload or initialized[field:gsub(" %(Lib%)$", "")] == true
      end
    end
    if changed then names[#names + 1] = copy.name end
  end
  if rule.namespace and type(state.skin.GetModule) == "function" then
    local module = state.skin:GetModule(rule.namespace, true)
    reload = reload or (module and module:IsEnabled()) or false
  end
  table.sort(names)
  return true, reload, names
end

function adapter.Watch(onChange)
  local db = _G.Skinner and _G.Skinner.db
  if not (db and type(db.RegisterCallback) == "function") or watched[db] then return end
  watched[db] = true
  for _, event in ipairs({ "OnProfileChanged", "OnProfileCopied", "OnProfileReset" }) do
    db.RegisterCallback(adapter, event, onChange)
  end
end
