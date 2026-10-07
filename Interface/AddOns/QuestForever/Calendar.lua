-- Holiday quests only while their holiday is on (CurseForge, 27 Sept 2026:
-- "I see exclamation marks for holidays that are not currently active and it
-- clutters up the map").
--
-- QuestForeverData.HOL (Holidays.lua, generated from QuestieDB) says which
-- quests belong to which holiday. Whether a holiday is on comes from the
-- game's own calendar: today's events of type HOLIDAY, recognised by the
-- calendar's holiday IDs, or failing that by the English name. A quest filed
-- only as "seasonal" counts as on while any holiday but the Darkmoon Faire is.
-- When the calendar can't be read, holiday quests stay hidden -- the clutter
-- was the complaint, and a holiday that's on shows as soon as it can be read.
--
-- It works through QF.IsAvailable, so the map pins, the Next tab and the
-- quest lines all follow: a holiday quest out of season reads "holiday".

local QF = _G.QuestForever
if not QF then return end
local D = _G.QuestForeverData

-- Calendar holiday IDs (Holidays table) and English words, per key.
local BY_ID = {
  [327] = "lunar", [335] = "love", [423] = "love", [181] = "noblegarden", [201] = "children",
  [341] = "midsummer", [372] = "brewfest", [324] = "hallows", [321] = "harvest", [404] = "pilgrim",
  [409] = "deadday", [141] = "winterveil", [374] = "darkmoon", [375] = "darkmoon", [376] = "darkmoon",
  [479] = "darkmoon",
}
local BY_WORD = {
  { "lunar", "lunar" }, { "love is in the air", "love" }, { "noblegarden", "noblegarden" },
  { "children", "children" }, { "midsummer", "midsummer" }, { "brewfest", "brewfest" },
  { "hallow", "hallows" }, { "harvest", "harvest" }, { "pilgrim", "pilgrim" },
  { "dead", "deadday" }, { "winter veil", "winterveil" }, { "darkmoon", "darkmoon" },
  { "scourge", "scourge" },
}

-- The Scourge Invasion's quests: a world event, not a holiday, so not in
-- Holidays.lua -- and shown all year (goldfish117 on CurseForge, 30 Sept
-- 2026: "some scourge invasion quests are still showing up ... 'Investigate
-- the Scourge of Darnassus'"). Only while the calendar lists the invasion.
local EVENT_QUESTS = {}
for _, id in ipairs({ 9085, 9094, 9153, 9260, 9261, 9262, 9263, 9264, 9265, 9292, 9295, 9299, 9300,
  9301, 9302, 9304, 9310, 9317, 9318, 9333, 9334, 9335, 9341, 9343 }) do
  EVENT_QUESTS[id] = "scourge"
end
QF.EVENT_QUESTS = EVENT_QUESTS

local active, readAt, opened = {}, nil, false
local STALE = 600   -- seconds: read the calendar again after this

local function KeyFor(event)
  if type(event) ~= "table" then return nil end
  local key = BY_ID[event.eventID]
  if key then return key end
  local title = type(event.title) == "string" and event.title:lower() or ""
  for _, pair in ipairs(BY_WORD) do
    if title:find(pair[1], 1, true) then return pair[2] end
  end
  return nil
end

-- Today's holidays -> active[key] = true. Returns whether it could read.
function QF.ReadHolidays()
  local cal = C_Calendar
  if not (cal and cal.GetNumDayEvents and cal.GetDayEvent) then return false end
  if not opened and cal.OpenCalendar then
    opened = true
    pcall(cal.OpenCalendar)   -- asks the server for this month; the answer is an event
  end
  local day
  local dt = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime
  if dt then
    local ok, now = pcall(dt)
    if ok and type(now) == "table" then day = now.monthDay end
  end
  if not day then return false end
  local fresh = {}
  local ok, n = pcall(cal.GetNumDayEvents, 0, day)
  if not ok or type(n) ~= "number" then return false end
  for i = 1, n do
    local okE, event = pcall(cal.GetDayEvent, 0, day, i)
    if okE and type(event) == "table" and event.calendarType == "HOLIDAY" then
      local key = KeyFor(event)
      if key then fresh[key] = true end
    end
  end
  active = fresh
  readAt = GetTime and GetTime() or 0
  return true
end

function QF.HolidayOn(key)
  local now = GetTime and GetTime() or 0
  if not readAt or now - readAt > STALE then QF.ReadHolidays() end
  if key == "seasonal" then
    for k in pairs(active) do
      if k ~= "darkmoon" then return true end
    end
    return false
  end
  return active[key] == true
end

function QF.HolidayOf(questID)
  return (D and D.HOL and D.HOL[questID]) or EVENT_QUESTS[questID] or nil
end

local baseAvailable = QF.IsAvailable
function QF.IsAvailable(q)
  local ok, why = baseAvailable(q)
  if not ok then return ok, why end
  local key = q and QF.HolidayOf(q.id)
  if key and not QF.HolidayOn(key) then return false, "holiday" end
  return true
end

-- The calendar answers later than it's asked: redraw when it does, if that
-- changed which holidays are on.
local watcher = CreateFrame("Frame")
pcall(watcher.RegisterEvent, watcher, "CALENDAR_UPDATE_EVENT_LIST")
watcher:SetScript("OnEvent", function()
  local before = {}
  for k in pairs(active) do before[k] = true end
  if not QF.ReadHolidays() then return end
  local changed = false
  for k in pairs(active) do if not before[k] then changed = true end end
  for k in pairs(before) do if not active[k] then changed = true end end
  if changed and QF.running and QF.Refresh then pcall(QF.Refresh) end
end)
QF.calendarWatcher = watcher
