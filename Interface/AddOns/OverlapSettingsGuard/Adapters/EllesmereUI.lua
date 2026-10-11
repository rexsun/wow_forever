local _, OSG = ...
local adapter = {}
OSG.adapters.EllesmereUI = adapter
local pendingRefresh = false

local function State()
  local db = _G.EllesmereUIDB
  if not (type(db) == "table" and type(db.profiles) == "table"
    and type(_G._ENP_RefreshAllSettings) == "function") then
    return nil, "EllesmereUI nameplate database/refresh API is unavailable"
  end
  return db
end

local function Copies(db)
  local copies, seen = {}, {}
  local function Visit(node, name)
    if type(node) ~= "table" or seen[node] then return end
    seen[node] = true
    if node.showClassPower == true then
      copies[#copies + 1] = { store = node, key = "showClassPower", name = name }
    end
    for key, value in pairs(node) do
      if type(key) == "string" and value == true
        and key:match("^EllesmereUINameplates[%c]showClassPower$") then
        copies[#copies + 1] = { store = node, key = key, name = name }
      end
    end
    for _, child in pairs(node) do Visit(child, name) end
  end
  for name, profile in pairs(db.profiles) do Visit(profile, tostring(name)) end
  Visit(db, "saved spec presets")
  return copies
end

function adapter.Knows(key) return key == "NameplatePower" end

function adapter.Read()
  local db, problem = State()
  if not db then return nil, problem end
  return pendingRefresh or #Copies(db) > 0
end

function adapter.Revert()
  local db, problem = State()
  if not db then return false, problem end
  local changed = {}
  for _, copy in ipairs(Copies(db)) do
    copy.store[copy.key] = false
    changed[copy.name] = true
  end
  pendingRefresh = true
  local ok, result = pcall(_G._ENP_RefreshAllSettings)
  if not ok then return false, "EllesmereUI nameplate refresh failed: " .. tostring(result) end
  pendingRefresh = false
  local names = {}
  for name in pairs(changed) do names[#names + 1] = name end
  table.sort(names)
  return true, false, names
end

function adapter.Watch(onChange)
  if type(_G._ENP_RefreshAllSettings) == "function" then
    hooksecurefunc("_ENP_RefreshAllSettings", onChange)
  end
end
