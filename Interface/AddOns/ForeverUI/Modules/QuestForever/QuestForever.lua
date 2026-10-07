local _, ns = ...

-- QuestForever, the quest helper: "!" where you can pick a quest up, "?"
-- where you hand one in, dots where the mobs and items for your quests are,
-- on the world map and the minimap. Click one and the waypoint arrow points
-- there.
--
-- The quest data and the map drawing are their own load-on-demand addon
-- (the QuestForever folder, shipped beside ForeverUI), so nobody who leaves
-- this off carries the data in memory. This module is the switch and the
-- settings; it loads the addon when it is turned on and hands it the
-- settings below. Off unless you say yes (the installer asks).

local ADDON = "QuestForever"

local module = ns.RegisterModule({
  name = "QuestForever",
  title = "QuestForever",
})

module.defaults = {
  enabled = false,
  showAvailable = true,
  showTurnIns = true,
  showUnfinished = false,
  showObjectives = true,
  showItemStarts = true,
  showPaths = true,
  tooltips = true,
  learn = true,
  onWorldMap = true,
  onMinimap = true,
  hideTrivial = true,
  showRepeatable = false,
  showProfession = false,
  levelsAhead = 0,
  iconSize = 16,
}

local function Settings()
  return ns.db.modules.QuestForever
end

-- Load the addon if it isn't already. Returns the addon's table, or nil and
-- why not (missing, or switched off in the game's AddOns list).
function module.Load()
  if _G.QuestForever then
    return _G.QuestForever
  end
  local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
  if not load then
    return nil, "this client can't load addons on demand"
  end
  local ok, loaded, reason = pcall(load, ADDON)
  if not ok or not loaded then
    return nil, reason or "the QuestForever folder isn't installed, or it is switched off in the AddOns list"
  end
  return _G.QuestForever
end

-- Loading an addon tells every other addon about it, there and then
-- (ADDON_LOADED). Done at login -- in the middle of our own start, before the
-- world is in -- that reached RXPGuides while its guide window wasn't built
-- yet: "RXPGuides/GuideWindow.lua:380: attempt to perform arithmetic on a nil
-- value", and its quest box never appeared (CurseForge, 27 Sept 2026). So at
-- login the quest helper waits until you're in the world, and a moment more;
-- switched on later, it starts at once.
local deferred
local function StartNow()
  local qf, why = module.Load()
  if not qf then
    module.problem = why
    ns.Print(("QuestForever couldn't start: %s."):format(tostring(why)))
    return
  end
  module.problem = nil
  qf.Start(Settings)
end
module.StartNow = StartNow

function module:OnEnable()
  if not ns.loggingIn then
    return StartNow()
  end
  module.waitingForWorld = true
  if deferred then return end
  deferred = CreateFrame("Frame")
  deferred:RegisterEvent("PLAYER_ENTERING_WORLD")
  deferred:SetScript("OnEvent", function(frame)
    frame:UnregisterAllEvents()
    local function go()
      if module.waitingForWorld and ns.IsModuleEnabled("QuestForever") then
        module.waitingForWorld = false
        StartNow()
      end
    end
    if C_Timer and C_Timer.After then C_Timer.After(1, go) else go() end
  end)
end

function module:OnDisable()
  module.waitingForWorld = false
  if _G.QuestForever then
    _G.QuestForever.Stop()
  end
end

function module:Refresh()
  if _G.QuestForever and _G.QuestForever.running then
    _G.QuestForever.Refresh()
  end
end

function module.Toggle(state)
  local on = ns.IsModuleEnabled("QuestForever")
  if state == nil then state = not on end
  ns.SetModuleEnabled("QuestForever", state)
  ns.Print(state and "QuestForever on: quest givers, hand-ins and objectives on your map and minimap."
    or "QuestForever off.")
  if ns.RefreshOptions then ns.RefreshOptions() end
  return state
end

-- One line for the page: running, and how much it knows.
function module.Status()
  if not ns.IsModuleEnabled("QuestForever") then
    return "Off. Switch it on to see quests on your map while you level."
  end
  if module.problem then
    return "|cffff6666Not running:|r " .. module.problem
  end
  local qf = _G.QuestForever
  local counts = qf and qf.Counts and qf.Counts() or {}
  local line = ("Running. It knows %d quests, %d NPCs and %d objects."):format(
    counts.quests or 0, counts.npcs or 0, counts.objects or 0)
  if (counts.learned or 0) > 0 then
    line = line .. (" You've found %d places the data didn't have."):format(counts.learned)
  end
  return line
end

-- Where players send what they make: a private page on the addon's own
-- site (docs/site/ispress-foreverui/share/). The game can't open a browser
-- or send anything itself, so the link and the text are handed over to copy.
ns.SHARE_URL = "https://ispress.de/foreverui/share/"

-- Everything worth sending, as text: places the data was missing, and your
-- quest tips and routes (Curation.lua). Returns text, places, edit lines.
function module.ShareText()
  local qf = _G.QuestForever
  local text, n, edits, e = "", 0, "", 0
  if qf and qf.ExportLearned then text, n = qf.ExportLearned() end
  if qf and qf.ExportEdits then edits, e = qf.ExportEdits() end
  if e > 0 then text = (n > 0 and (text .. "\n") or "") .. edits end
  return text, n, e
end

-- /fui share, the Share button in the quest guide, /fui qf export: the link,
-- how to add screenshots, and what to paste.
function module.Export()
  local text, n, e = module.ShareText()
  local lines = {
    "Open " .. ns.SHARE_URL .. " in your browser and paste all of this into the box there.",
    "Screenshots: press Print Screen in the game - they are saved in your World of Warcraft",
    "_classic_beta_\\Screenshots folder - and add them on the same page.",
    "",
  }
  if n + e == 0 then
    lines[#lines + 1] = "(Nothing of yours to paste yet - screenshots and ideas are just as welcome.)"
  else
    lines[#lines + 1] = text
  end
  if ns.ShowTextPopup then
    ns.ShowTextPopup(("Share with ForeverUI -- %d places, %d tip and route lines"):format(n, e), table.concat(lines, "\n"))
  end
  return n + e
end
ns.ShareWithForeverUI = function() return module.Export() end

module.options = {
  { type = "heading", label = "QuestForever", subtitle = "Quests on your map while you level",
    icon = "quests" },
  { type = "checkbox", switch = true, key = "enabled", label = "Show quests on the map and minimap",
    desc = "Also: /fui quests helper, or /fui qf.",
    get = function() return ns.IsModuleEnabled("QuestForever") end,
    set = function(on) module.Toggle(on) end },
  { type = "note", labelFor = function() return module.Status() end },

  { type = "heading", label = "What it shows", columns = 2, icon = "map" },
  { type = "checkbox", key = "showAvailable", label = "\"!\" where you can pick a quest up" },
  { type = "checkbox", key = "showTurnIns", label = "\"?\" where you hand a finished quest in" },
  { type = "checkbox", key = "showObjectives", label = "Dots where your quests' mobs, items and objects are" },
  { type = "checkbox", key = "showUnfinished", label = "A grey \"?\" for quests not finished yet" },
  { type = "checkbox", key = "showItemStarts", label = "Where items that start a quest drop" },
  { type = "checkbox", key = "showPaths", label = "Routes of escorts and patrolling targets" },
  { type = "checkbox", key = "tooltips", label = "Quest lines on mobs', NPCs' and objects' tooltips",
    desc = "Hover a mob: which of your quests it's for, and your progress. Hover a quest giver: what they have for you." },
  { type = "checkbox", key = "onWorldMap", label = "On the world map" },
  { type = "checkbox", key = "onMinimap", label = "On the minimap" },

  { type = "heading", label = "Which quests", columns = 2, icon = "quests" },
  { type = "checkbox", key = "hideTrivial", label = "Hide quests far below your level" },
  { type = "checkbox", key = "showRepeatable", label = "Show repeatable quests" },
  { type = "checkbox", key = "showProfession", label = "Show profession quests" },
  { type = "stepper", key = "levelsAhead", label = "Also show quests up to this many levels too high",
    min = 0, max = 5, step = 1 },
  -- Its own section: a slider can't sit in a two-column card (the options
  -- builder refuses it, and said so in chat on the live client).
  { type = "heading", label = "Size", icon = "map" },
  { type = "slider", key = "iconSize", label = "Icon size", min = 10, max = 28, step = 1 },

  { type = "heading", label = "Filling the gaps", icon = "quests" },
  { type = "checkbox", key = "learn", label = "Remember quest givers the data doesn't know",
    desc = "Many quests new in Forever have no known giver yet. Pick one up and QuestForever remembers where." },
  { type = "action", label = "Share what it found", width = 240, icon = "copy",
    desc = "Text to copy and post as a CurseForge comment, so the next update has it for everyone.",
    onClick = function() module.Export() end },

  { type = "note", label = "Click any \"!\", \"?\" or dot and the waypoint arrow points there. "
    .. "Quest data: QuestieDB (Forever), forever-guide-mate and Wowhead - see QuestForever/README.txt." },
}
