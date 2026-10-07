local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- HealForever's own black box.
--
-- BugGrabber is the usual way to see what an addon did wrong, but it can be
-- switched off - and on this account it is - which leaves a player saying "it
-- keeps crashing" and nobody able to say why. So errors are recorded here as
-- well, into saved variables, where they survive a reload and can be read off
-- disk afterwards.
--
-- The previous handler is always called: this watches, it never swallows.

local MAX_ERRORS = 20
local MAX_MESSAGE = 900
local MAX_STACK = 2000

local pending = {}      -- before the database exists
local announced = false

local function Trim(text, limit)
  text = tostring(text or "")
  if #text > limit then
    return text:sub(1, limit) .. " ..."
  end
  return text
end

-- Ours, or someone else's? Both are recorded - an error in another addon that
-- only happens with this one loaded is worth seeing - but only ours is worth
-- interrupting the player about.
local function IsOurs(message, stack)
  local text = (message or "") .. (stack or "")
  return text:find("ForeverUI", 1, true) ~= nil
end

function ns.RecordError(message, stack)
  local entry = {
    when = (time and time()) or 0,
    message = Trim(message, MAX_MESSAGE),
    stack = Trim(stack, MAX_STACK),
    ours = IsOurs(message, stack),
    version = ns.Version and ns.Version() or "?",
  }

  if ns.Note then
    ns.Note("error: " .. tostring(message):sub(1, 120))
  end
  if not ns.db then
    -- Too early: the settings aren't loaded, so hold it in memory until they
    -- are. This is exactly when the interesting errors happen.
    pending[#pending + 1] = entry
    if #pending > MAX_ERRORS then
      table.remove(pending, 1)
    end
    return entry
  end

  ns.db.errors = ns.db.errors or {}
  local list = ns.db.errors

  table.insert(list, 1, entry)
  for i = #list, MAX_ERRORS + 1, -1 do
    list[i] = nil
  end

  if entry.ours and not announced then
    announced = true
    -- This log is the frames' own (the self-test lists it); /fui errors is
    -- ForeverUI's, and only keeps errors whose MESSAGE names ForeverUI.
    ns.Print(("something went wrong inside the party frames. It is written down - %s selftest shows it.")
      :format(ns.standalone and (ns.SLASH or "/hf") or "/fui frames"))
  end
  return entry
end

-- Anything recorded before the database was ready moves in as soon as it is.
function ns.FlushErrors()
  if not ns.db then
    return 0
  end
  ns.db.errors = ns.db.errors or {}
  local moved = #pending
  for i = moved, 1, -1 do
    table.insert(ns.db.errors, 1, pending[i])
    pending[i] = nil
  end
  for i = #ns.db.errors, MAX_ERRORS + 1, -1 do
    ns.db.errors[i] = nil
  end
  return moved
end

function ns.InstallErrorHandler()
  if ns.errorHandlerInstalled or not seterrorhandler then
    return false
  end
  ns.errorHandlerInstalled = true
  local previous = geterrorhandler and geterrorhandler()
  seterrorhandler(function(message)
    -- Recording must never be the thing that breaks: if this throws, the
    -- game's own handler still runs.
    pcall(ns.RecordError, message, debugstack and debugstack(2) or nil)
    if previous then
      return previous(message)
    end
  end)
  return true
end

-- Installed as this file loads, which is as early as it can be: the only code
-- that has run before it is the settings table it needs.
ns.InstallErrorHandler()
