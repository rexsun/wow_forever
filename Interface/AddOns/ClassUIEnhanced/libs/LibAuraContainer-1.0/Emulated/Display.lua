--[[ LibAuraContainer-1.0: Emulated/Display

Groups and slots, the two kinds of display a container shows auras in: which
auras each one holds, and which button shows which aura; and the container's
item enchantments.

INTERFACE (Private.Display)

  Display.NewGroup(parent, key, settings) -> group
  Display.NewSlot(parent, key, settings) -> slot
      parent is the container frame (the buttons' parent). settings is the
      container's checked, defaults-filled reading of the options:
        filterString, compiled (Filter.Compile), candidateFilters (or nil),
        comparator (Filter.GetComparator), templates (string or nil),
        initializeFrame (or nil), clock (the container's Private.Clock, for
        the buttons); groups also maxFrameCount and layout.
      NewGroup creates the group's first batch of buttons before it returns, so
      initializeFrame runs BATCH times before the caller has registered the
      group. NewSlot creates the slot's one button.

  Every display (group or slot) has
      .key, .filterString, .compiled, .candidateFilters, .comparator
      .enabled      the container skips disabled displays
      .members      auraInstanceID -> aura record, the auras it holds now
      .dirty        true when Refresh has something to do
    and the methods
      :Offer(unit, aura, policy, engineMatched, stringMatched) -> changed
          Membership as Filter.IsMember decides. A member is stored and marked
          changed for its button; a non-member is dropped. changed is true when
          the display keeps the aura (its place may have moved) or lost it.
          stringMatched: the aura matches the whole filter string already
          (edit-mode preview), so only the policy and candidate filters
          are tested.
      :Drop(auraInstanceID) -> changed
      :ClearMembers()      forgets every aura; buttons keep theirs until the
                           next Refresh or ReleaseAll
      :ReleaseAll()        takes every aura off its button now
      :Refresh(unit) -> LAC.FrameRefreshResult bits
          Binds buttons to the current members: Button.Assign for a new
          binding, Button.Update for a held aura whose record changed, nothing
          for an unchanged one, Button.Clear only for a button that held an
          aura. Slots always return None. When a pass raises (a
          consumer's formatter, curve or animation script), the display's
          next Refresh binds every member afresh, from a consistent pool. Until
          that Refresh runs, a layout-only pass lays out the group's previous
          frames list (cosmetic; the recovering pass lays out again).

  Group only
      .frames         buttons in display order; Refresh replaces the table
      .maxFrameCount, .layout (defaults-filled group layout options)
      .pool.owned     every button, in creation order (GetAuraGroupFrame)
  Slot only
      .button

  Display.NewEnchants() -> enchants
      The item enchantments of one container. Not a display: it
      never sees auras. Fields:
        .frames      buttons of the enabled, active slots in sort order (the
                     layout elements; the table is kept, its contents change)
        .layout      the enchant group's layout options (the container sets
                     it; LAC.Defaults.ItemEnchantmentLayout field names)
      Methods:
        :Add(slot, button, hidePermanent) -> entry   a slot and its button;
                     entry.enabled, entry.button
        :Get(slot) -> entry or nil
        :SetEnabled(entry, enabled)   records the switch and re-sorts
        :ClearDisabled(entry)         clears a disabled slot's button now
        :SetSort(byTime, reverse)     re-sorts at once
        :AnyEnabled() -> bool
        :Refresh() -> LAC.FrameRefreshResult bits   run by every assign
                     pass; re-reads every enabled slot (Emulated/Enchant.lua)
                     and binds its button: a new assignment when the enchant is
                     new, replaced or refreshed to a longer remaining time, else
                     an update; then re-sorts. FrameAssignmentsChanged only
                     when .frames changed (an enchant started or ended, or the
                     order changed), VisibilityChanged on 0 <-> some active.
        :ReleaseAll()  clears every slot's button; the next Refresh starts
                     afresh (duration)

  Display.ApplyLayout(c)
      Layout hand-off: the enabled groups of container state c, in
      registration order, plus the enchant group while any enchant slot is
      enabled, go to Layout.Order and Layout.Apply with c.flow.

POOL
  A group's buttons come from its own pool, BATCH at a time. Taking a button
  pops the free stack (the newest created or released one); giving one back
  pushes it. Buttons released in one pass go back in creation order, so after
  a full reset they are taken newest-created first, as from a fresh pool, and
  a group that never holds more than one button always gets the same one (the
  last of its first batch).
]]

local Private = LibStub("LibAuraContainer-1.0-Private")
if not Private.loading or Private.LAC.IsNative then return end
local LAC = Private.LAC

local Display = {}
Private.Display = Display

local Filter, Button, Layout, Enchant = Private.Filter, Private.Button, Private.Layout, Private.Enchant

local BATCH = 10
local NONE = LAC.FrameRefreshResult.None
local ASSIGNMENTS = LAC.FrameRefreshResult.FrameAssignmentsChanged
local VISIBILITY = LAC.FrameRefreshResult.VisibilityChanged

------------------------------------------------------------------ membership (both kinds)

local Common = {}

function Common:Offer(unit, aura, policy, engineMatched, stringMatched)
	local id = aura.auraInstanceID
	if not Filter.IsMember(unit, aura, self.compiled, self.candidateFilters, policy, engineMatched, stringMatched) then
		return self:Drop(id)
	end
	self.members[id] = aura
	self.changed[id] = true
	self.dirty = true
	return true
end

function Common:Drop(id)
	if self.members[id] == nil then return false end
	self.members[id] = nil
	self.changed[id] = nil
	self.dirty = true
	return true
end

function Common:ClearMembers()
	wipe(self.members)
	wipe(self.changed)
	self.dirty = true
end

local function newDisplay(key, s, kind)
	return setmetatable({
		key = key, enabled = true, dirty = false,
		filterString = s.filterString, compiled = s.compiled,
		candidateFilters = s.candidateFilters, comparator = s.comparator,
		members = {},
		changed = {}, -- auraInstanceID -> true: record changed since its button showed it
	}, kind)
end

------------------------------------------------------------------ pool

local function addBatch(pool)
	for _ = 1, BATCH do
		local button = Button.New(pool.parent, pool.templates, pool.initialize, pool.clock)
		pool.owned[#pool.owned + 1] = button
		pool.free[#pool.free + 1] = button
	end
end

local function takeButton(pool)
	if pool.free[1] == nil then addBatch(pool) end
	local button = pool.free[#pool.free]
	pool.free[#pool.free] = nil
	pool.inUse[button] = true
	return button
end

-- Gives back every button in use that `keep` does not name, in creation order.
-- Returns whether any went back. A button moves to the free stack only once its
-- Clear (which runs consumer scripts) returned, so a raising Clear leaves it in
-- use, to be given back again by the next requested pass.
local function giveBack(pool, keep)
	local any = false
	for _, button in ipairs(pool.owned) do
		if pool.inUse[button] and not keep[button] then
			Button.Clear(button)
			pool.inUse[button] = nil
			pool.free[#pool.free + 1] = button
			any = true
		end
	end
	return any
end

------------------------------------------------------------------ groups

local Group = setmetatable({}, { __index = Common })
Group.__index = Group

local NOTHING = {}

function Display.NewGroup(parent, key, s)
	local group = newDisplay(key, s, Group)
	group.maxFrameCount, group.layout = s.maxFrameCount, s.layout
	group.frames = {}
	group.pool = {
		parent = parent, templates = s.templates, initialize = s.initializeFrame, clock = s.clock,
		owned = {}, free = {}, inUse = {},
	}
	group.buttonOf = {} -- auraInstanceID -> button, as of the last finished Refresh
	group.refreshing = false -- true from the start of a Refresh until it finishes
	-- Scratch tables reused by every Refresh (the next frames and buttonOf are swapped in).
	group.nextFrames, group.nextButtonOf, group.ranked, group.kept = {}, {}, {}, {}
	group.entry = {} -- this group's Layout entry
	addBatch(group.pool)
	return group
end

-- Members in sort order, in the reused `ranked` array; returns how many get a button.
local function rank(group)
	local ranked, n = group.ranked, 0
	for _, aura in pairs(group.members) do
		n = n + 1
		ranked[n] = aura
	end
	for i = #ranked, n + 1, -1 do ranked[i] = nil end
	table.sort(ranked, group.comparator)
	if n > group.maxFrameCount then return group.maxFrameCount end
	return n
end

function Group:Refresh(unit)
	-- A pass that raised (a consumer's formatter, curve or binding) can leave a
	-- button taken but not bound, or given back while still listed: rebind the
	-- whole group from an empty pool instead of trusting that state.
	if self.refreshing then self:ReleaseAll() end
	self.refreshing = true

	local count = rank(self)
	local ranked, old, new, kept = self.ranked, self.frames, self.nextFrames, self.kept
	local buttonOf, nextButtonOf = self.buttonOf, self.nextButtonOf
	wipe(new)
	wipe(kept)
	wipe(nextButtonOf)
	local moved = false

	-- Auras that hold a button keep it, wherever they now stand.
	for place = 1, count do
		local id = ranked[place].auraInstanceID
		local button = buttonOf[id]
		if button then
			new[place], kept[button] = button, true
			moved = moved or old[place] ~= button
			if self.changed[id] then
				self.changed[id] = nil
				Button.Update(button, ranked[place])
			end
		else
			moved = true
		end
	end

	-- Buttons whose aura left go back before any is taken.
	moved = giveBack(self.pool, kept) or moved

	-- The rest are new bindings.
	for place = 1, count do
		local aura = ranked[place]
		local button = new[place]
		if button == nil then
			button = takeButton(self.pool)
			new[place] = button
			self.changed[aura.auraInstanceID] = nil
			Button.Assign(button, unit, aura)
		end
		nextButtonOf[aura.auraInstanceID] = button
	end

	local result = NONE
	if moved or #old ~= count then result = result + ASSIGNMENTS end
	if (#old > 0) ~= (count > 0) then result = result + VISIBILITY end
	wipe(old)
	self.frames, self.nextFrames = new, old
	self.buttonOf, self.nextButtonOf = nextButtonOf, buttonOf
	self.dirty, self.refreshing = false, false
	return result
end

function Group:ReleaseAll()
	-- Counts as an unfinished pass until every button is back: if a Clear raises,
	-- the group's next requested Refresh starts over from an empty pool.
	self.dirty, self.refreshing = true, true
	giveBack(self.pool, NOTHING)
	wipe(self.frames)
	wipe(self.buttonOf)
	wipe(self.changed)
	self.refreshing = false
end

------------------------------------------------------------------ slots

local Slot = setmetatable({}, { __index = Common })
Slot.__index = Slot

function Display.NewSlot(parent, key, s)
	local slot = newDisplay(key, s, Slot)
	slot.button = Button.New(parent, s.templates, s.initializeFrame, s.clock)
	slot.heldID = nil -- auraInstanceID on the button; false while an Assign runs
	return slot
end

function Slot:Refresh(unit)
	local best
	for _, aura in pairs(self.members) do
		if best == nil or self.comparator(aura, best) then best = aura end
	end
	if best == nil then
		if self.heldID ~= nil then self:ReleaseAll() end
	else
		local id = best.auraInstanceID
		if self.heldID ~= id then
			-- false until the Assign returns: if it raises, the button holds some
			-- half-shown aura, so the next requested pass binds afresh or clears it.
			self.heldID = false
			Button.Assign(self.button, unit, best)
			self.heldID = id
		elseif self.changed[id] then
			Button.Update(self.button, best)
		end
		self.changed[id] = nil
	end
	self.dirty = false
	return NONE
end

-- After a full reset the top candidate is bound afresh even if it is the same aura.
function Slot:ReleaseAll()
	self.dirty = true
	if self.heldID ~= nil then
		self.heldID = false -- a raising Clear is retried by the next requested pass
		Button.Clear(self.button)
		self.heldID = nil
	end
end

------------------------------------------------------------------ item enchantments

local ENCHANT = LAC.AuraDataType.ItemEnchantment
local SLOT_ORDER = LAC.ItemEnchantmentSortOrder
local INVENTORY_SLOT = LAC.ItemEnchantmentToInventorySlot
local huge = math.huge

local Enchants = {}
Enchants.__index = Enchants

function Display.NewEnchants()
	return setmetatable({
		entries = {}, bySlot = {}, -- entries in the order added, and by slot
		ranked = {},               -- scratch: the entries behind .frames
		frames = {},
		before = {},               -- scratch: .frames as they were before a Refresh
		byTime = false, reverse = false,
		entry = {},                -- the enchant group's Layout entry
	}, Enchants)
end

function Enchants:Add(slot, button, hidePermanent)
	local e = {
		slot = slot, inventorySlot = INVENTORY_SLOT[slot], button = button, hidePermanent = hidePermanent,
		enabled = true, active = false, expires = false, duration = 0,
	}
	self.entries[#self.entries + 1] = e
	self.bySlot[slot] = e
	return e
end

function Enchants:Get(slot)
	return self.bySlot[slot]
end

function Enchants:AnyEnabled()
	for _, e in ipairs(self.entries) do
		if e.enabled then return true end
	end
	return false
end

-- The slot stays active until its button's Clear returned, so a raising Clear
-- is retried by the next requested re-read or reset; an enchant seen meanwhile
-- binds afresh.
local function deactivate(e)
	e.signature = nil
	Button.Clear(e.button)
	e.active, e.remainingMs, e.expires, e.duration = false, nil, false, 0
end

-- Sort keys set by rank: time (0 when sorting by slot; permanent last),
-- then the slot's sort order, then the slot value.
local function ahead(a, b)
	if a.timeKey ~= b.timeKey then return a.timeKey < b.timeKey end
	if a.orderKey ~= b.orderKey then return a.orderKey < b.orderKey end
	return a.slot < b.slot
end
local function behind(a, b) return ahead(b, a) end

function Enchants:Rank()
	local ranked, frames = self.ranked, self.frames
	wipe(ranked)
	wipe(frames)
	for _, e in ipairs(self.entries) do
		if e.enabled and e.active then
			e.timeKey = self.byTime and (e.expires and e.remainingMs or huge) or 0
			e.orderKey = SLOT_ORDER[e.slot] or huge
			ranked[#ranked + 1] = e
		end
	end
	table.sort(ranked, self.reverse and behind or ahead)
	for i, e in ipairs(ranked) do frames[i] = e.button end
end

function Enchants:SetSort(byTime, reverse)
	self.byTime, self.reverse = byTime, reverse
	self:Rank()
end

-- Only records the switch; ClearDisabled then clears a disabled slot's button
-- (consumer scripts may run there, so the caller does its bookkeeping first).
function Enchants:SetEnabled(e, enabled)
	e.enabled = enabled
	self:Rank()
end

-- If that Clear raises, the slot stays disabled and active, and the next
-- requested reset (ReleaseAll) clears it.
function Enchants:ClearDisabled(e)
	if not e.enabled and e.active then deactivate(e) end
end

-- Reads one slot again and shows the result on its button. A binding is new
-- when the slot's enchant differs from the one last seen (another enchant ID,
-- or a timed one turned permanent or back) or has more time left than last
-- time; GetWeaponEnchantInfo gives no total, so that remaining time becomes the
-- duration until the next new binding.
local function reread(e)
	local present, enchantID, remainingMs, charges, expires = Enchant.Read(e.slot)
	if not present or (e.hidePermanent and not expires) then
		if e.active then deactivate(e) end
		return
	end
	local signature = (enchantID or 0) * 2 + (expires and 1 or 0)
	local renewed = e.signature ~= signature or (expires and remainingMs > e.remainingMs)
	e.active, e.expires, e.remainingMs = true, expires, remainingMs
	if renewed then e.duration = remainingMs / 1000 end
	local record = {
		itemEnchantmentID = enchantID, itemEnchantmentSlot = e.slot, inventorySlot = e.inventorySlot,
		auraType = ENCHANT, applications = charges, duration = e.duration,
		expirationTime = expires and GetTime() + remainingMs / 1000 or 0,
	}
	if renewed then
		-- Unset until the Assign returns, so a raising one is assigned again by the
		-- next requested pass.
		e.signature = nil
		Button.Assign(e.button, "player", record)
		e.signature = signature
	else
		Button.Update(e.button, record)
	end
end

function Enchants:Refresh()
	local frames, before = self.frames, self.before
	for i = 1, #self.entries do before[i] = frames[i] end
	for _, e in ipairs(self.entries) do
		if e.enabled then reread(e) end
	end
	self:Rank()
	-- Only a start, an end or a new order changes what the layout places.
	local result = NONE
	for i = 1, #self.entries do
		if before[i] ~= frames[i] then
			result = ASSIGNMENTS
			break
		end
	end
	if (before[1] ~= nil) ~= (frames[1] ~= nil) then result = result + VISIBILITY end
	return result
end

function Enchants:ReleaseAll()
	-- Every enchant is bound afresh by the next requested pass, even when a Clear
	-- below raises.
	for _, e in ipairs(self.entries) do e.signature = nil end
	for _, e in ipairs(self.entries) do
		if e.active then deactivate(e) end
	end
	wipe(self.ranked)
	wipe(self.frames)
end

------------------------------------------------------------------ layout hand-off

function Display.ApplyLayout(c)
	local entries = c.layoutEntries
	wipe(entries)
	for index, group in ipairs(c.groups) do
		if group.enabled then
			local entry = group.entry
			entry.layout, entry.elements, entry.registrationIndex = group.layout, group.frames, index
			entries[#entries + 1] = entry
		end
	end
	local enchants = c.enchants
	if enchants:AnyEnabled() then
		local entry = enchants.entry
		entry.layout, entry.elements, entry.placement = enchants.layout, enchants.frames, enchants.layout.placement
		entries[#entries + 1] = entry
	end
	Layout.Order(entries)
	Layout.Apply(c.frame, c.flow, entries)
end
