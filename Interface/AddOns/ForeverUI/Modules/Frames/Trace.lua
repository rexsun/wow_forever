local _, FUI = ...
FUI.Frames = FUI.Frames or {}
local ns = FUI.Frames

-- A flight recorder for the settings.
--
-- Bindings were going back to defaults across reloads and reading the code
-- had twice pointed at the wrong culprit. This writes a line every time the
-- profile is resolved or the role changes, into the ADDON-level saved
-- variable rather than into the profile -- because if the profile itself is
-- what is being replaced, a trace kept inside it would vanish with the
-- evidence.
--
-- Turn it off with /fui frames trace off. It costs one short string per
-- event and keeps the last 60.

local LIMIT = 60

local function Store()
  local db = rawget(_G, "ForeverUIDB")
  if type(db) ~= "table" then
    return nil
  end
  db.__trace = db.__trace or {}
  return db.__trace
end

local function Describe()
  local db = ns.db
  if type(db) ~= "table" then
    return "db=nil"
  end
  local parts = {}
  for _, role in ipairs({ "healer", "tank", "dps" }) do
    local store = ((db.modes or {})[role] or {}).bindings
    local keys = {}
    if type(store) == "table" then
      for key, binding in pairs(store) do
        keys[#keys + 1] = key .. "=" .. tostring(binding.spell or binding.kind)
      end
      table.sort(keys)
    end
    parts[#parts + 1] = ("%s{%s}"):format(role:sub(1, 1), table.concat(keys, ","))
  end
  local live = {}
  if type(db.bindings) == "table" then
    for key, binding in pairs(db.bindings) do
      live[#live + 1] = key .. "=" .. tostring(binding.spell or binding.kind)
    end
    table.sort(live)
  end
  local cd = {}
  for _, role in ipairs({ "healer", "tank", "dps" }) do
    local marks = ((db.modes or {})[role] or {}).classDefaults
    cd[#cd + 1] = role:sub(1, 1) .. (marks and next(marks) and "Y" or "n")
  end
  return ("mode=%s prof=%s live{%s} %s cd=%s"):format(
    tostring(db.mode), tostring(FUI.ActiveProfileName and FUI.ActiveProfileName() or "?"),
    table.concat(live, ","), table.concat(parts, " "), table.concat(cd, ""))
end

-- What is ACTUALLY on disk for a profile, read from the saved variable
-- rather than from ns.db -- which early in the boot is still a scratch table
-- and will happily describe itself as "the profile".
local function DescribeSaved()
  local db = rawget(_G, "ForeverUIDB")
  if type(db) ~= "table" or type(db.profiles) ~= "table" then
    return "no saved db"
  end
  local names = {}
  for name in pairs(db.profiles) do
    names[#names + 1] = name
  end
  table.sort(names)
  local out = {}
  for _, name in ipairs(names) do
    local frames = (db.profiles[name] or {}).frames
    local roles = {}
    for _, role in ipairs({ "healer", "tank", "dps" }) do
      local b = ((frames or {}).modes or {})[role]
      b = b and b.bindings
      local n = 0
      if type(b) == "table" then for _ in pairs(b) do n = n + 1 end end
      roles[#roles + 1] = role:sub(1, 1) .. n
    end
    out[#out + 1] = ("%s[frames=%s mode=%s %s]"):format(
      name, frames and "yes" or "NO", tostring((frames or {}).mode), table.concat(roles, ""))
  end
  -- The question that matters: is the table we WRITE to actually inside the
  -- table the game SAVES? If it is not, every change is written to something
  -- that never reaches disk, which looks exactly like "it does not save".
  local reachable = "?"
  if ns.db then
    reachable = "no"
    for _, profile in pairs(db.profiles) do
      if rawequal(profile.frames, ns.db) then
        reachable = "YES"
      end
    end
  end

  return ("active=%s reachable=%s | %s"):format(
    tostring(FUI.ActiveProfileName and FUI.ActiveProfileName() or "?"), reachable,
    table.concat(out, " "))
end

function ns.TraceSaved(tag)
  if ns.traceOff then
    return
  end
  local store = Store()
  if store then
    store[#store + 1] = ("%s | %s | SAVED %s"):format(
      date and date("%H:%M:%S") or "?", tag, DescribeSaved())
  end
end

function ns.Trace(tag)
  if ns.traceOff then
    return
  end
  local store = Store()
  if not store then
    return
  end
  store[#store + 1] = ("%s | %s | %s"):format(
    date and date("%H:%M:%S") or "?", tag, Describe())
  while #store > LIMIT do
    table.remove(store, 1)
  end
end

-- Print it back, oldest first.
function ns.ShowTrace()
  local store = Store()
  if not store or #store == 0 then
    ns.Print("no trace yet.")
    return 0
  end
  for _, line in ipairs(store) do
    ns.Print(line)
  end
  return #store
end

function ns.ClearTrace()
  local db = rawget(_G, "ForeverUIDB")
  if type(db) == "table" then
    db.__trace = {}
  end
  ns.Print("trace cleared.")
end
