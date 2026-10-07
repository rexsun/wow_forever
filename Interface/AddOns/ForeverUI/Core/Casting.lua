local _, ns = ...

-- Reading a cast without doing arithmetic on it.
--
-- On Forever, another unit's cast arrives as secret values: the spell name,
-- the icon, the start and end times. They may be handed straight to a widget
-- -- a bar fills, a label reads -- but the moment addon code divides, subtracts
-- or compares one, it throws, and the throw taints the addon until its own
-- action buttons stop casting. The target frame did exactly that, dividing a
-- start time by a thousand.
--
-- It goes further than arithmetic: a secret boolean cannot even be tested
-- (`if x then` throws), so nothing read from a cast may be branched on. Only
-- type() is safe to ask of a secret value, and only setters are safe to
-- hand one to.
--
-- So a cast is kept in the game's own units (milliseconds) and passed through
-- untouched: the bar's range is the raw start and end, and its value is the
-- clock, which is ours to read. The one place a sum is needed -- the seconds
-- left, for the label -- is tried once inside a guard; if it is refused the
-- label stays blank and the bar still fills, which is most of what a cast
-- bar is for.

local casting = {}
ns.Casting = casting

-- A record of what happened to a cast, for when a bar vanishes with no
-- error to show for it. The last few dozen entries are kept in the saved
-- variables (ns.db.castTrace) so they can be read after a reload, and
-- printed as they happen when tracing is switched on with /fui cast trace.
local TRACE_LIMIT = 40
casting.tracing = false
local NowMs -- defined below

-- Something about a value that is safe to say even when it is secret.
local function Describe(v)
  local kind = type(v)
  if kind == "nil" then
    return "nil"
  end
  if issecretvalue and issecretvalue(v) then
    return kind .. "(secret)"
  end
  if kind == "number" then
    return ("%.0f"):format(v)
  end
  return tostring(v)
end
casting.Describe = Describe

function casting.Trace(what, ...)
  local parts = { what }
  for i = 1, select("#", ...) do
    parts[#parts + 1] = Describe((select(i, ...)))
  end
  local line = ("%.0f %s"):format(NowMs and NowMs() or 0, table.concat(parts, " "))
  if ns.db then
    ns.db.castTrace = ns.db.castTrace or {}
    local trace = ns.db.castTrace
    trace[#trace + 1] = line
    while #trace > TRACE_LIMIT do
      table.remove(trace, 1)
    end
  end
  if casting.tracing then
    ns.Print("|cff888888cast|r " .. line)
  end
end

-- Now, in the game's cast-time units. GetTime() is ours; scaling it is fine.
function NowMs()
  return (GetTime and GetTime() or 0) * 1000
end
casting.NowMs = NowMs

-- What the unit is casting, raw. The two calls return the same things in a
-- different order, so the slots are picked by name. Not `a and f() or g()`:
-- that would keep only the first return.
-- `castGUID` is the ID the START event carried. It is an event argument, so
-- it is never secret -- unlike the ID UnitCastingInfo returns, which is, and
-- which therefore can't be compared with anything.
function casting.Read(unit, channelling, castGUID)
  local info
  if channelling then
    info = { UnitChannelInfo(unit) }
  else
    info = { UnitCastingInfo(unit) }
  end
  -- Not `if not info[1]`: a truth test on a secret throws. type() does not.
  if type(info[1]) == "nil" then
    casting.Trace("read:nothing", unit, channelling and "channel" or "cast")
    return nil
  end
  -- No `x and a or b` on these: `or` tests its left side, and for a channel
  -- info[7] (not interruptible) is a SECRET boolean - "attempt to perform
  -- boolean test on field '?' (a secret boolean value)" (CurseForge report,
  -- 25 Sept 2026). Plain ifs pick the slot without testing its value.
  local notInterruptible, castID
  if channelling then
    notInterruptible = info[7]
  else
    notInterruptible = info[8]
    -- A cast's own ID, so a stop for a cast that has already been replaced
    -- can be told apart from a stop for this one. From the START event, which
    -- is plain; the copy UnitCastingInfo returns is secret on this client and
    -- refuses to be compared. Channels don't have one; they end on their own
    -- stop event.
    if type(castGUID) ~= "nil" then
      castID = castGUID
    else
      castID = info[7]
    end
  end
  casting.Trace("read", unit, channelling and "channel" or "cast",
    "name=", info[1], "start=", info[4], "end=", info[5], "id=", castID)
  return {
    name = info[1],
    icon = info[3],
    startMs = info[4],
    endMs = info[5],
    channelling = channelling and true or false,
    notInterruptible = notInterruptible,
    castID = castID,
  }
end

-- A stop event arrived. End the cast only if it's for this cast: when you
-- cast again quickly, START for the new one can arrive before STOP for the
-- old one, and ending on any stop wipes the new cast off the bar the moment
-- it appears -- "the second cast doesn't work". Comparing IDs can be refused
-- when they are secret; then the stop is taken at its word.
function casting.Stop(bar, castGUID, channelStop)
  local info = bar.castInfo
  if not info then
    casting.Trace("stop:no-cast-on-bar", castGUID)
    return false
  end
  if channelStop then
    if not info.channelling then
      return false   -- a channel's stop doesn't end a cast
    end
  elseif info.channelling then
    return false     -- a cast's stop doesn't end a channel
  elseif type(castGUID) ~= "nil" and type(info.castID) ~= "nil" then
    local ok, same = ns.Secrets.Measure(function()
      return castGUID == info.castID
    end)
    if ok and not same then
      casting.Trace("stop:other-cast", castGUID, "ours=", info.castID)
      return false   -- for a cast this bar has already moved on from
    end
    if not ok then
      casting.Trace("stop:ids-uncomparable", castGUID, "ours=", info.castID)
      -- Both IDs secret and uncomparable: nothing can be known about which
      -- cast this stop is for. Ending the visible cast on a stray stop is
      -- what clipped casts a second in, so leave it; it ends on its own clock.
      return false
    end
  end
  casting.Trace("stop:ending", castGUID, channelStop and "channel" or "cast")
  casting.End(bar)
  return true
end

-- Put a cast on a bar. Everything here is a setter; nothing is computed.
function casting.Begin(bar, info)
  bar.castInfo = info
  bar.secretTiming = nil
  bar.ended = nil
  if bar.text then
    bar.text:SetText(info.name)
  end
  if bar.icon and type(info.icon) ~= "nil" then
    bar.icon:SetTexture(info.icon)
  end
  if bar.timer then
    bar.timer:SetText("")
  end
  bar:SetStatusBarTexture(ns.Media.StatusBarTexture())
  -- Range is the raw start and end; the value will be the clock.
  bar:SetMinMaxValues(info.startMs, info.endMs)
  -- A channel drains rather than fills; the bar can do that itself.
  if bar.SetReverseFill then
    bar:SetReverseFill(info.channelling)
  end
  -- Whether it can be interrupted is a secret boolean on another unit's
  -- cast, and asking is what throws. Ask inside a guard; refused, it is
  -- coloured as an ordinary cast.
  local ok, locked = ns.Secrets.Measure(function()
    return info.notInterruptible and true or false
  end)
  if ok and locked then
    bar:SetStatusBarColor(ns.Colors.Get("status", "uninterruptible"))
  else
    bar:SetStatusBarColor(ns.Colors.Get("status", info.channelling and "channeling" or "casting"))
  end
  bar:SetValue(NowMs())
  bar:Show()
  casting.Trace("begin", info.name, "start=", info.startMs, "end=", info.endMs, "id=", info.castID)
  return bar
end

function casting.End(bar)
  bar.castInfo = nil
  bar.ended = true
  bar.endSecret = nil
  bar:Hide()
end

-- Seconds left and total, as text, or nothing if the numbers are secret.
local function Label(info, nowMs)
  local left = (info.endMs - nowMs) / 1000
  local total = (info.endMs - info.startMs) / 1000
  if left < 0 then
    left = 0
  end
  return ("%.1f / %.1f"):format(left, total)
end

-- Each frame: move the bar along, update the label, notice the end. Returns
-- true while the cast is still running.
function casting.Tick(bar)
  local info = bar.castInfo
  if not info then
    return false
  end
  local nowMs = NowMs()
  bar:SetValue(nowMs)

  if bar.timer and not bar.secretTiming then
    local ok, text = ns.Secrets.Measure(Label, info, nowMs)
    if ok then
      bar.timer:SetText(text)
    else
      -- Refused: this cast's times are secret. Stop asking, and say nothing.
      bar.secretTiming = true
      bar.timer:SetText("")
    end
  end

  -- Has it finished? Comparing a secret end time throws too, so this is
  -- guarded as well; when it is refused, the stop event ends the cast instead.
  local ok, finished = ns.Secrets.Measure(function()
    return nowMs >= info.endMs
  end)
  if ok and finished then
    casting.Trace("tick:finished", "now=", nowMs, "end=", info.endMs)
    casting.End(bar)
    return false
  elseif not ok and not bar.endSecret then
    bar.endSecret = true
    casting.Trace("tick:end-time-secret", "end=", info.endMs)
  end
  return true
end
