--[[ LibAuraContainer-1.0: Emulated/Pipeline

When container work runs, the events that feed it, and the container's
clock.

INTERFACE (Private.Pipeline)

  Pipeline.Attach(c)
      Gives container state c its driver: a plain child Frame of the
      container (c.driver) that owns every script and event registration of
      the container. Its OnShow / OnHide fire when the container's
      visibility changes. Also gives c its clock (c.clock,
      Emulated/Clock.lua), which the buttons share for timed repaints.
  Pipeline.RequestFull(c)     re-parse, rebind every button, lay out
  Pipeline.RequestAssign(c)   rebind buttons of the displays marked dirty
  Pipeline.RequestLayout(c)   lay out again
      All work waits for the next rendered frame on which the container is
      visible; any number of requests before then cost one pass.
  Pipeline.UpdateEvents(c)
      Registers the events the container's current state needs and nothing else.
  Pipeline.SetFakeProvider(c, active)
      Records whether edit mode's fake aura provider is active; re-parses
      when that changes which source the container reads.

THE PASS
  Pending work is four flags in c.pending, done in this order:
    parse    Store.FullParse
    reset    every display's ReleaseAll, and the enchants' (c.enchants)
    assign   every enabled, dirty display's Refresh, then the enchants'
             Refresh, which re-reads every enabled slot on every assign pass
             as 12.1.5 does (only while the container is enabled); a
             FrameAssignmentsChanged result adds layout
    layout   Display.ApplyLayout
  then the clock's Tick. The driver has an OnUpdate script only while a pass
  is due or the clock is busy: requesting (or the clock waking) sets it, and
  it is removed once neither holds. While the clock is busy the script stays
  installed from frame to frame (no SetScript per frame).
  Errors: each step clears its flag before it runs, so a step that raises is
  not repeated on the next frame. While the clock is idle the pass also drops
  the script before working, so a raising pass leaves the container idle
  until the next request. While the clock is busy the script stays, so a
  raising step or clock callback does not stop the clock: the next frame finds
  the flags cleared and reaches the Tick (the clock forgets a callback before
  running it).
  Reset: a finished reset is always followed by a rebind and a layout; a
  request made meanwhile (a consumer script inside a button's Clear) only
  sets its flag. If that request was a full one, the rebind and layout wait
  for the next frame's parse and reset. A reset that raised part-way is
  remembered (c.resetUnfinished): the next pass that finds an assign or
  layout pending (a later request, or one made during the failed reset)
  resets again first. So a Clear that keeps raising repeats once per request,
  not once per frame (unless the raising script itself makes a request each
  time). Displays repair a raising Refresh or ReleaseAll on their next
  requested pass (Emulated/Display.lua).
  An idle container costs nothing per frame. The clock does not run while the
  container is hidden; showing it re-binds every button, which re-reads
  what the clock was timing.

EVENTS
  UNIT_AURA (for c.unit): ignored while Store.UsesPreview(c); no
  payload or isFullUpdate -> RequestFull; otherwise Store.ApplyUpdate now
  and RequestAssign if anything changed (a pending full parse makes the
  payload redundant, so it is skipped then).
  AURA_DATA_PROVIDER_SWITCH(useRealDataProvider), registered for the
  container's lifetime -> Pipeline.SetFakeProvider(c, not useRealDataProvider).
  UNIT_FLAGS / UNIT_FACTION (c.unit and the player), while an enabled
  display has a spell-ID candidate filter -> RequestFull.
  Under the ProcessAura policy, PLAYER_ENTERING_WORLD, PLAYER_LEAVING_WORLD,
  PLAYER_REGEN_DISABLED / _ENABLED, PLAYER_SPECIALIZATION_CHANGED ->
  RequestFull (while visible and enabled).
  WEAPON_ENCHANT_CHANGED / WEAPON_SLOT_CHANGED (while visible, enabled and
  an enchant slot is enabled) -> RequestAssign.
  Unit swaps, registered with UNIT_AURA: the events that may make c.unit
  name another unit (swapEventsFor, derived from the lower-cased token and
  kept in c.swapEvents for c.swapToken; c.swapRegistered is the map
  registered now, nil when none). Registered with plain RegisterEvent: the
  unit argument is matched here. Ignored while Store.UsesPreview(c) or
  a full parse is pending; otherwise UnitGUID(c.unit) ~= c.parsedGUID (the
  GUID Store.FullParse saw) -> RequestFull.
]]

local Private = LibStub("LibAuraContainer-1.0-Private")
if not Private.loading or Private.LAC.IsNative then return end
local LAC = Private.LAC

local Pipeline = {}
Private.Pipeline = Pipeline

local Store, Display, Clock = Private.Store, Private.Display, Private.Clock
local band = bit.band
local ASSIGNMENTS = LAC.FrameRefreshResult.FrameAssignmentsChanged

-- Re-checking whether the player may test spell IDs on the unit.
local IDENTITY_EVENTS = { "UNIT_FLAGS", "UNIT_FACTION" }
-- What the client's AuraUtil.ProcessAura answers may change with these.
local POLICY_EVENTS = {
	"PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
	"PLAYER_SPECIALIZATION_CHANGED",
}
local PROCESS_AURA = LAC.AuraProcessingPolicy.ProcessAura
local ENCHANT_EVENTS = { "WEAPON_ENCHANT_CHANGED", "WEAPON_SLOT_CHANGED" }
local IS_ENCHANT_EVENT = { WEAPON_ENCHANT_CHANGED = true, WEAPON_SLOT_CHANGED = true }

------------------------------------------------------------------ unit swaps

-- Tokens that only the player's own choice re-points.
local CHOSEN_UNIT_EVENT = {
	target = "PLAYER_TARGET_CHANGED", focus = "PLAYER_FOCUS_CHANGED", mouseover = "UPDATE_MOUSEOVER_UNIT",
}

-- unit nil: the event counts whatever its arguments; else only for that unit.
local function listen(events, event, unit)
	local current = events[event]
	if unit == nil then
		events[event] = true
	elseif current ~= true then
		current = current or {}
		current[unit] = true
		events[event] = current
	end
end

local function collectSwapEvents(events, token)
	local chosen = CHOSEN_UNIT_EVENT[token]
	if chosen then
		listen(events, chosen)
	elseif token:find("^nameplate%d+$") then
		listen(events, "NAME_PLATE_UNIT_ADDED", token)
		listen(events, "NAME_PLATE_UNIT_REMOVED", token)
	elseif token:find("^boss%d+$") then
		listen(events, "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
	elseif token:find("^arena%d+$") then
		listen(events, "ARENA_OPPONENT_UPDATE", token)
	elseif token:find("^party%d+$") or token:find("^raid%d+$") then
		listen(events, "GROUP_ROSTER_UPDATE")
	elseif token == "pet" then
		listen(events, "UNIT_PET", "player")
	elseif token == "vehicle" then
		listen(events, "UNIT_ENTERED_VEHICLE", "player")
		listen(events, "UNIT_EXITED_VEHICLE", "player")
	else
		local group, n = token:match("^(%a+)pet(%d+)$")
		local watched = token:match("^(.+)target$")
		if group == "party" or group == "raid" then
			listen(events, "UNIT_PET", group .. n)
			collectSwapEvents(events, group .. n)
		elseif watched then
			-- <unit>target: <unit> may change its target or itself be re-pointed.
			listen(events, "UNIT_TARGET", watched)
			collectSwapEvents(events, watched)
		end
	end
end

local function swapEventsFor(unit)
	local events = {}
	collectSwapEvents(events, unit:lower())
	return events
end

------------------------------------------------------------------ requests

local function arm(c)
	if not c.armed then
		c.armed = true
		c.driver:SetScript("OnUpdate", c.onUpdate)
	end
end

local function disarm(c)
	if c.armed then
		c.armed = false
		c.driver:SetScript("OnUpdate", nil)
	end
end

function Pipeline.RequestFull(c)
	local p = c.pending
	p.parse, p.reset, p.assign, p.layout = true, true, true, true
	arm(c)
end

function Pipeline.RequestAssign(c)
	c.pending.assign = true
	arm(c)
end

function Pipeline.RequestLayout(c)
	c.pending.layout = true
	arm(c)
end

------------------------------------------------------------------ the pass

local function run(c)
	local p, clock = c.pending, c.clock
	if not Clock.IsBusy(clock) then disarm(c) end

	-- A reset that raised part-way (a consumer script in a button's Clear) is
	-- done again once anything else is requested.
	if c.resetUnfinished and (p.assign or p.layout) then p.reset = true end
	if p.parse then
		p.parse = false
		Store.FullParse(c)
	end
	if p.reset then
		-- No rebind or layout before the reset finished; a finished reset is
		-- always followed by both. A request made by consumer code during the
		-- loop only sets its flag.
		p.reset, p.assign, p.layout, c.resetUnfinished = false, false, false, true
		for _, display in ipairs(c.displays) do display:ReleaseAll() end
		c.enchants:ReleaseAll()
		p.assign, p.layout, c.resetUnfinished = true, true, false
	end
	-- After a full request made during that reset, the assign and layout stay
	-- pending until the next frame's parse and reset: binding now is wasted.
	if p.assign and not p.reset then
		p.assign = false
		if c.enabled == true then
			for _, display in ipairs(c.displays) do
				if display.enabled and display.dirty and band(display:Refresh(c.unit), ASSIGNMENTS) ~= 0 then
					p.layout = true
				end
			end
			if band(c.enchants:Refresh(), ASSIGNMENTS) ~= 0 then p.layout = true end
		end
	end
	if p.layout and not p.reset then
		p.layout = false
		Display.ApplyLayout(c)
	end
	Clock.Tick(clock)

	if p.parse or p.reset or p.assign or p.layout or Clock.IsBusy(clock) then
		arm(c)
	else
		disarm(c)
	end
end

------------------------------------------------------------------ events

function Pipeline.SetFakeProvider(c, active)
	local before = Store.UsesPreview(c)
	c.fakeProvider = active == true
	if Store.UsesPreview(c) ~= before then Pipeline.RequestFull(c) end
end

local function onUnitSwap(c, wanted, unit)
	if wanted ~= true and not wanted[unit] then return end
	if Store.UsesPreview(c) or c.pending.parse then return end
	if UnitGUID(c.unit) ~= c.parsedGUID then Pipeline.RequestFull(c) end
end

local function onEvent(c, event, unit, info)
	local swap = c.swapRegistered and c.swapRegistered[event]
	if swap then
		onUnitSwap(c, swap, unit)
	elseif event == "UNIT_AURA" then
		if Store.UsesPreview(c) then return end
		if info == nil or info.isFullUpdate then
			Pipeline.RequestFull(c)
		elseif not c.pending.parse and Store.ApplyUpdate(c, info) then
			Pipeline.RequestAssign(c)
		end
	elseif IS_ENCHANT_EVENT[event] then
		Pipeline.RequestAssign(c)
	elseif event == "AURA_DATA_PROVIDER_SWITCH" then
		Pipeline.SetFakeProvider(c, not unit) -- the payload is useRealDataProvider
	else
		Pipeline.RequestFull(c)
	end
end

local function registerIf(driver, events, wanted)
	for _, event in ipairs(events) do
		if wanted then driver:RegisterEvent(event) else driver:UnregisterEvent(event) end
	end
end

function Pipeline.UpdateEvents(c)
	local driver = c.driver
	local live = c.enabled == true and driver:IsVisible()
	local wantAuras, wantIdentity = false, false
	if live then
		for _, display in ipairs(c.displays) do
			if display.enabled then
				wantAuras = true
				local f = display.candidateFilters
				if f and (f.includeSpellIDs or f.excludeSpellIDs) then wantIdentity = true end
			end
		end
	end

	driver:UnregisterEvent("UNIT_AURA")
	if wantAuras then driver:RegisterUnitEvent("UNIT_AURA", c.unit) end
	if c.swapRegistered then
		for event in pairs(c.swapRegistered) do driver:UnregisterEvent(event) end
		c.swapRegistered = nil
	end
	if wantAuras then
		if c.swapToken ~= c.unit then c.swapToken, c.swapEvents = c.unit, swapEventsFor(c.unit) end
		for event in pairs(c.swapEvents) do driver:RegisterEvent(event) end
		c.swapRegistered = c.swapEvents
	end
	for _, event in ipairs(IDENTITY_EVENTS) do
		driver:UnregisterEvent(event)
		if wantIdentity then
			if c.unit == "player" then
				driver:RegisterUnitEvent(event, "player")
			else
				driver:RegisterUnitEvent(event, c.unit, "player")
			end
		end
	end
	registerIf(driver, POLICY_EVENTS, live and c.policy == PROCESS_AURA)
	registerIf(driver, ENCHANT_EVENTS, live and c.enchants:AnyEnabled())
end

local function visibilityChanged(c)
	Pipeline.UpdateEvents(c)
	Pipeline.RequestFull(c)
end

function Pipeline.Attach(c)
	local driver = CreateFrame("Frame", nil, c.frame)
	c.driver = driver
	c.armed = false
	c.pending = { parse = false, reset = false, assign = false, layout = false }
	c.onUpdate = function() run(c) end
	c.clock = Clock.New(function() arm(c) end)
	driver:SetScript("OnEvent", function(_, event, unit, info) onEvent(c, event, unit, info) end)
	driver:RegisterEvent("AURA_DATA_PROVIDER_SWITCH")
	driver:SetScript("OnShow", function() visibilityChanged(c) end)
	driver:SetScript("OnHide", function() visibilityChanged(c) end)
end
