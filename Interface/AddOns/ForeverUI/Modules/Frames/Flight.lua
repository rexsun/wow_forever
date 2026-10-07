local ADDON_NAME, FUI = ...   -- ForeverUI's addon name + shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- A flight recorder for one specific fault.
--
-- On at least one client, an addon's saved variables stop being restored at
-- load - permanently, for that addon's folder name - while the same code under
-- a fresh name is fine. Something that happens during ordinary use appears to
-- trigger it, and when it does the addon's own saved data is exactly what goes
-- missing, so it can't hold the evidence. This leaves a plain global,
-- HF_FLIGHT, which a separate tiny addon (tools/recorder) writes into ITS
-- saved variables on the way out. Without that companion installed this costs
-- a small table and nothing else.

HF_FLIGHT = {
  folder = ADDON_NAME,
  events = {},
}

local MAX_EVENTS = 60

function ns.Note(what)
  local events = HF_FLIGHT.events
  events[#events + 1] = ("%s %s"):format(date and date("%H:%M:%S") or "?", tostring(what))
  if #events > MAX_EVENTS then
    table.remove(events, 1)
  end
end

local f = CreateFrame("Frame")
for _, event in ipairs({
  "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
  "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "ADDON_RESTRICTION_STATE_CHANGED",
  "SAVED_VARIABLES_TOO_LARGE", "PLAYER_ENTERING_WORLD",
}) do
  pcall(f.RegisterEvent, f, event)
end

f:SetScript("OnEvent", function(_, event, a, b)
  if event == "ADDON_LOADED" then
    if a == ADDON_NAME then
      -- The one fact everything else is judged against: did ForeverUI's
      -- saved profile come back from disk? (The frames live inside it now.)
      local core = rawget(_G, "ForeverUIDB")
      local seen = type(core) == "table" and type(core.profiles) == "table" and next(core.profiles) ~= nil
      HF_FLIGHT.restoredAtLoad = seen or false
      ns.Note("loaded; saved variables " .. (seen and "PRESENT" or "MISSING"))
    end
  elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" or event == "SAVED_VARIABLES_TOO_LARGE" then
    ns.Note(event .. " " .. tostring(a) .. " " .. tostring(b))
  elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
    ns.Note("restriction " .. tostring(a) .. " -> " .. tostring(b))
  else
    ns.Note(event)
  end
end)
