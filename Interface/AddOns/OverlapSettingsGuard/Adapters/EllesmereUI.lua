local _, OSG = ...
local adapter = {}
OSG.adapters.EllesmereUI = adapter
local pendingRefresh = {}

-- Spec and conditional overrides store "<addon folder>\31<setting path>" keys.
local NIL_SENT = "__SPECOV_NIL__"
local OVERRIDE_PREFIX = {
  NameplatePower = "EllesmereUINameplates\31",
  ClassPower = "EllesmereUIUnitFrames\31",
}
local REFRESH = {
  NameplatePower = "_ENP_RefreshAllSettings",
  ClassPower = "_EUF_ReloadFrames",
}
local NAMEPLATE_FIELDS = { showClassPower = false }

local function NotNone(unset)
  return function(value)
    if value == nil then return unset end
    return value ~= "none" and value ~= NIL_SENT
  end
end

-- Player-frame fields per rule: on(value) tells whether a stored value (nil = the module
-- default, which the profile inherits) shows the display, and off is the value written.
-- The Forever default class power style is "modern"; Forever rogues under the EllesmereUI
-- look read their own style key (UF_RogueCPKey), unset meaning "none". The player power
-- bar is deliberately not guarded: it and YUI's HUD bars may both show.
local PLAYER_FIELDS = {
  ClassPower = {
    classPowerStyle = { on = NotNone(true), off = "none" },
    foreverRogueClassPowerStyle = { on = NotNone(false), off = "none" },
  },
}

local function State(key)
  local db = _G.EllesmereUIDB
  if not (type(db) == "table" and type(db.profiles) == "table"
    and type(_G[REFRESH[key]]) == "function") then
    local what = key == "NameplatePower" and "nameplate" or "unit frame"
    return nil, ("EllesmereUI %s database/refresh API is unavailable"):format(what)
  end
  return db
end

local function OverrideCopies(node, key, name, copies)
  local prefix = OVERRIDE_PREFIX[key]
  local fields = PLAYER_FIELDS[key]
  for field, value in pairs(node) do
    if type(field) == "string" and field:sub(1, #prefix) == prefix then
      local path = field:sub(#prefix + 1)
      local spec = fields and fields[path:match("^player%.(.+)$") or ""]
      if key == "NameplatePower" and path == "showClassPower" and value == true then
        copies[#copies + 1] = { store = node, key = field, off = false, name = name }
      elseif spec and value ~= nil and value ~= NIL_SENT and spec.on(value) then
        copies[#copies + 1] = { store = node, key = field, off = spec.off, name = name }
      end
    end
  end
end

local function PlayerCopies(uf, key, name, copies)
  local player = type(uf.player) == "table" and uf.player or {}
  for field, spec in pairs(PLAYER_FIELDS[key]) do
    if spec.on(player[field]) then
      copies[#copies + 1] = { unitFrames = uf, key = field, off = spec.off, name = name }
    end
  end
end

local function Copies(db, key)
  local copies, seen = {}, {}
  local function Visit(node, name)
    if type(node) ~= "table" or seen[node] then return end
    seen[node] = true
    if key == "NameplatePower" then
      for field, off in pairs(NAMEPLATE_FIELDS) do
        if node[field] == true then copies[#copies + 1] = { store = node, key = field, off = off, name = name } end
      end
    end
    OverrideCopies(node, key, name, copies)
    for _, child in pairs(node) do Visit(child, name) end
  end
  for name, profile in pairs(db.profiles) do
    if PLAYER_FIELDS[key] and type(profile) == "table" then
      local addons = type(profile.addons) == "table" and profile.addons
      local uf = addons and addons.EllesmereUIUnitFrames
      if type(uf) == "table" then PlayerCopies(uf, key, tostring(name), copies) end
    end
    Visit(profile, tostring(name))
  end
  Visit(db, "saved spec presets")
  return copies
end

function adapter.Knows(key) return OVERRIDE_PREFIX[key] ~= nil end

function adapter.Read(key)
  key = key or "NameplatePower"
  local db, problem = State(key)
  if not db then return nil, problem end
  return pendingRefresh[key] or #Copies(db, key) > 0
end

function adapter.Revert(key)
  key = key or "NameplatePower"
  local db, problem = State(key)
  if not db then return false, problem end
  local changed = {}
  for _, copy in ipairs(Copies(db, key)) do
    if copy.unitFrames then
      if type(copy.unitFrames.player) ~= "table" then copy.unitFrames.player = {} end
      copy.store = copy.unitFrames.player
    end
    copy.store[copy.key] = copy.off
    if key == "ClassPower" and copy.key == "classPowerStyle" then copy.store.showClassPowerBar = false end
    changed[copy.name] = true
  end
  pendingRefresh[key] = true
  local ok, result = pcall(_G[REFRESH[key]])
  if not ok then return false, "EllesmereUI refresh failed: " .. tostring(result) end
  pendingRefresh[key] = false
  local names = {}
  for name in pairs(changed) do names[#names + 1] = name end
  table.sort(names)
  return true, false, names
end

function adapter.Watch(onChange)
  local hooked = {}
  for _, name in pairs(REFRESH) do
    if not hooked[name] and type(_G[name]) == "function" then
      hooked[name] = true
      hooksecurefunc(name, onChange)
    end
  end
end
