local _, OSG = ...
local adapter = {}
OSG.adapters.Lueur = adapter

-- Lueur keeps its namespace private and publishes no refresh API, so the saved table
-- is the only control. Its marker settings default to on: a missing value counts as on.
local FIELDS = {
  NodeHerbs = "nodeHerbs",
  NodeOre = "nodeOre",
}

function adapter.Knows(key) return FIELDS[key] ~= nil end

function adapter.Read(key)
  return type(_G.LueurDB) ~= "table" or _G.LueurDB[FIELDS[key]] ~= false
end

-- Lueur's first minimap scan runs at PLAYER_LOGIN, so a write before login needs no reload.
function adapter.Revert(key)
  if type(_G.LueurDB) ~= "table" then _G.LueurDB = {} end
  _G.LueurDB[FIELDS[key]] = false
  return true, IsLoggedIn() == true
end

function adapter.Watch() end
