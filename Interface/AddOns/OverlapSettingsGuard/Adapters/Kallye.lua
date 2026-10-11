local _, OSG = ...

local adapter = {}
OSG.adapters.Kallye = adapter

function adapter.Knows(key)
  return key == "Nameplates"
end

function adapter.Read(key)
  local settings = _G.KallyeRaidFramesOptions
  if type(settings) ~= "table" then return nil, "Kallye Raid Frames has not finished loading" end
  return settings.ActiveNameplatesColor ~= false
end

function adapter.Revert(key)
  local settings = _G.KallyeRaidFramesOptions
  if type(settings) ~= "table" then return false, "Kallye Raid Frames has not finished loading" end
  settings.ActiveNameplatesColor = false
  return true, false
end

function adapter.Watch(onChange)
  local ui = _G.K_SHARED_UI
  if type(ui) == "table" and type(ui.RefreshOptions) == "function" then
    hooksecurefunc(ui, "RefreshOptions", onChange)
  end
end
