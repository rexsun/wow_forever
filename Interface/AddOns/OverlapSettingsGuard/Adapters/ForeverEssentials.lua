local _, OSG = ...
local adapter = {}
OSG.adapters.ForeverEssentials = adapter

-- Each Forever Essentials feature publishes Get/Cfg/Apply on EllesmereUI; its
-- options page sets Cfg().enabled and then calls Apply, which takes effect at once.
local FEATURES = {
  SpellUprank = "_SpellUprank",
  MapReveal = "_MapReveal",
  MapFade = "_MapFade",
  JunkItems = "_JunkItems",
  ClassicSpellbook = "_ClassicSpellbook",
  ClassicTalents = "_ClassicTalents",
  MapTravel = "_MapTravel",
  ThreatMeter = "_ThreatMeter",
}

local function Feature(key)
  local eui = _G.EllesmereUI
  local api = type(eui) == "table" and eui[FEATURES[key]]
  if not (type(api) == "table" and type(api.Get) == "function"
    and type(api.Cfg) == "function" and type(api.Apply) == "function") then
    return nil, "Forever Essentials " .. key .. " API is unavailable"
  end
  return api
end

function adapter.Knows(key) return FEATURES[key] ~= nil end

function adapter.Read(key)
  local api, problem = Feature(key)
  if not api then return nil, problem end
  return api.Get("enabled") == true
end

function adapter.Revert(key)
  local api, problem = Feature(key)
  if not api then return false, problem end
  api.Cfg().enabled = false
  api.Apply()
  return true, false
end

function adapter.Watch(onChange)
  for key in pairs(FEATURES) do
    local api = Feature(key)
    if api then hooksecurefunc(api, "Apply", onChange) end
  end
end
