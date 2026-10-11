--[[ LibAuraContainer-1.0: Emulated/Clock

Timed callbacks for the buttons of one container: the pandemic window edges
and the duration text colour repaints. A clock has no frame of
its own; its owner calls Clock.Tick on every rendered frame while the clock is
busy (Emulated/Pipeline.lua does this from the container's driver OnUpdate),
so all buttons of a container share one timer.

INTERFACE (Private.Clock)

  Clock.New(wake) -> clock
      wake() runs whenever the clock goes from idle to busy, so the owner can
      start ticking it.
  Clock.Schedule(clock, key, at, fire)
      fire(key) runs on the first Tick at or after GetTime() == at. A key has
      at most one pending callback: scheduling it again replaces the old one.
      Pass a long-lived function, not a new closure per call.
  Clock.Cancel(clock, key)
      Forgets key's pending callback, if any.
  Clock.IsBusy(clock) -> true while any callback is pending.
  Clock.Tick(clock)
      Runs every callback that is due, each once, and forgets it before it
      runs, so a callback may schedule its own key again. A callback scheduled
      for "now" from inside a Tick runs on the next Tick, never the same one.
      A callback that raises ends the Tick with that error; the callbacks it
      cut short are still pending and run on the next Tick.

COST
  Tick returns at once while nothing is due (it remembers the earliest time).
  In steady state nothing is allocated: keys go in and out of the same tables
  and the list of due keys is a reused scratch array.
]]

local Private = LibStub("LibAuraContainer-1.0-Private")
if not Private.loading or Private.LAC.IsNative then return end

local Clock = {}
Private.Clock = Clock

local NEVER = math.huge

function Clock.New(wake)
	return {
		wake = wake,
		times = {},     -- key -> when it is due
		callbacks = {}, -- key -> fire
		pending = 0,
		earliest = NEVER, -- no key is due before this (it may be earlier than needed)
		due = {},       -- scratch: the keys one Tick runs
		dueCount = 0,   -- how many of them the last Tick collected
	}
end

function Clock.Schedule(clock, key, at, fire)
	local isNew = clock.times[key] == nil
	clock.times[key], clock.callbacks[key] = at, fire
	if at < clock.earliest then clock.earliest = at end
	if isNew then
		clock.pending = clock.pending + 1
		if clock.pending == 1 then clock.wake() end
	end
end

function Clock.Cancel(clock, key)
	if clock.times[key] == nil then return end
	clock.times[key], clock.callbacks[key] = nil, nil
	clock.pending = clock.pending - 1
	if clock.pending == 0 then clock.earliest = NEVER end
end

function Clock.IsBusy(clock)
	return clock.pending > 0
end

function Clock.Tick(clock)
	local now = GetTime()
	if now < clock.earliest then return end

	-- Collect first: callbacks change the tables we would be walking. Entries a
	-- raising callback left behind are dropped (their keys are still pending).
	local due, count, nextTime = clock.due, 0, NEVER
	for i = 1, clock.dueCount do due[i] = nil end
	for key, at in pairs(clock.times) do
		if at <= now then
			count = count + 1
			due[count] = key
		elseif at < nextTime then
			nextTime = at
		end
	end
	clock.dueCount = count
	-- While callbacks run, keep the next Tick looking: if one raises, the rest are
	-- still due. After a Tick that ran callbacks the next one scans once more.
	clock.earliest = count > 0 and now or nextTime

	for i = 1, count do
		local key = due[i]
		due[i] = nil
		local at, fire = clock.times[key], clock.callbacks[key]
		-- An earlier callback of this Tick may have moved or cancelled it.
		if at ~= nil and at <= now then
			Clock.Cancel(clock, key)
			fire(key)
		end
	end
end
