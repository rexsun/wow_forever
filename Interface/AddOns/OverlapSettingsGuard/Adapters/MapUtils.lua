local _, OSG = ...
local adapter = {}
OSG.adapters.MapUtils = adapter

-- MapUtils keeps its namespace private and publishes no refresh API, so the saved table
-- is the only control. Its settings default to on: a missing value counts as on.
local FIELDS = {
  WorldMapMove = "WORLDMAPMOVE",
  WorldMapScale = "WORLDMAPSCALE",
  WorldMapFade = "WORLDMAPFADE",
  MapReveal = "REVEALMAP",
  PierPins = "WORLDMAPPINS",
}

function adapter.Knows(key) return FIELDS[key] ~= nil end

function adapter.Read(key)
  return type(_G.MAUTTAB) ~= "table" or _G.MAUTTAB[FIELDS[key]] ~= false
end

-- Before login MapUtils has not applied anything yet, so no reload is needed.
function adapter.Revert(key)
  if type(_G.MAUTTAB) ~= "table" then _G.MAUTTAB = {} end
  _G.MAUTTAB[FIELDS[key]] = false
  return true, IsLoggedIn() == true
end

function adapter.Watch() end
