local _, OSG = ...
local adapter = {}
OSG.adapters.ForeverEssentials = adapter

-- Each Forever Essentials feature publishes Get/Cfg/Apply on EllesmereUI; its
-- options page sets a Cfg() switch (enabled unless named) and then calls Apply,
-- which takes effect at once.
local FEATURES = {
  SpellUprank = { api = "_SpellUprank" },
  MapReveal = { api = "_MapReveal" },
  MapFade = { api = "_MapFade" },
  JunkItems = { api = "_JunkItems" },
  ClassicSpellbook = { api = "_ClassicSpellbook" },
  ClassicTalents = { api = "_ClassicTalents" },
  MapTravel = { api = "_MapTravel" },
  ThreatMeter = { api = "_ThreatMeter" },
  ZoneLevels = { api = "_ZoneLevels" },
  GatherSkill = { api = "_GatherSkill" },
  GatherSkinning = { api = "_GatherSkill", field = "skinning" },
  InGameNavigation = { api = "_InGameNavigation" },
}

local function Field(key) return FEATURES[key].field or "enabled" end

local function Feature(key)
  local eui = _G.EllesmereUI
  local api = type(eui) == "table" and eui[FEATURES[key].api]
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
  return api.Get(Field(key)) == true
end

function adapter.Revert(key)
  local api, problem = Feature(key)
  if not api then return false, problem end
  api.Cfg()[Field(key)] = false
  api.Apply()
  return true, false
end

function adapter.Watch(onChange)
  local watched = {}
  for key in pairs(FEATURES) do
    local api = Feature(key)
    if api and not watched[api] then
      watched[api] = true
      hooksecurefunc(api, "Apply", onChange)
    end
  end
end
