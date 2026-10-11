--[[ LibAuraContainer-1.0: Emulated/Store

The container's aura cache and the two ways aura data reaches its displays:
the full parse and the incremental UNIT_AURA payload.

INTERFACE (Private.Store)

  Store.FullParse(c)
      Empties the cache and every display (enabled or not). Then, if
      the container is enabled, asks the client once per distinct engine filter
      (Filter.Compile's .engine) among the enabled displays, reads each aura
      once and offers it to every display behind that engine filter as an
      engine match. Records UnitGUID(c.unit) as c.parsedGUID first
      (Emulated/Pipeline.lua compares it on the unit-swap events).
  Store.ApplyUpdate(c, info) -> changed
      The incremental part (the caller handles a missing payload and
      isFullUpdate): added auras are prepared, cached and offered; updated ones
      re-read (gone = removed); removed ones dropped. Only enabled displays
      take part; the engine part of each filter is checked per aura. changed
      is true when any display's membership changed.
  Store.ForgetQueries(c)
      The set of enabled displays or a filter string changed; the next full
      parse regroups the queries.
  Store.UsesPreview(c) -> bool
      Edit mode's fake aura provider is active (c.fakeProvider, from
      AURA_DATA_PROVIDER_SWITCH) and the container's preview is on
      (c.preview). Then FullParse reads that provider instead: once per
      distinct filter string among the enabled displays, through the client's
      AuraUtil.ForEachAura (classic has no AuraUtil.GetUnitAuras); each record
      is copied, marked as an aura with no casterGUID, classified under the
      policy and offered as matching the whole string. UNIT_AURA payloads are
      not applied then (Emulated/Pipeline.lua drops them).

  Uses from container state c: unit, enabled, policy, policyOptions,
  preview, fakeProvider, displays (every group and slot, in the order they were added), auras (the
  cache), queries and queriesStale; it sets parsedGUID.

PREPARING A RECORD
  Records are the client's AuraData tables, kept by reference. Before a
  display sees one it is marked auraType = LAC.AuraDataType.Aura (the button
  tells auras from item enchantments by it) and, when it has none yet, given
  casterGUID = UnitGUID(sourceUnit), nil without a source unit
  (classic has no GetAuraCasterGUID).

  SHARED RECORDS: a UNIT_AURA payload's addedAuras tables (and any record the
  client hands out more than once) are seen by every container and every
  other addon handling the event. Write into a record only values that are
  identical for every container (auraType, casterGUID). A per-container
  result, e.g. processedAuraType under one container's policy options, needs
  a per-container map keyed by auraInstanceID or a per-container copy of the
  record.

THE PROCESSING POLICY
  Under LAC.AuraProcessingPolicy.ProcessAura each record is classified by the
  client's AuraUtil.ProcessAura with c.policyOptions; the result is stored as
  processedAuraType, and the client's function itself writes debuffType,
  isBuff and isPriorityAura. All of that depends on the container's options,
  so it goes into a record the container owns: a fresh read
  (GetAuraDataByAuraInstanceID returns a new table per call) is classified as
  it is, a payload record is copied first (shallow) and the copy is cached
  and shown.
]]

local Private = LibStub("LibAuraContainer-1.0-Private")
if not Private.loading or Private.LAC.IsNative then return end
local LAC = Private.LAC

local Store = {}
Private.Store = Store

local AURA = LAC.AuraDataType.Aura
local PROCESS_AURA = LAC.AuraProcessingPolicy.ProcessAura

-- Only container-independent values may be written here (see SHARED RECORDS).
local function prepare(aura)
	aura.auraType = AURA
	local source = aura.sourceUnit
	if aura.casterGUID == nil and source ~= nil then aura.casterGUID = UnitGUID(source) end
	return aura
end

local function ownCopy(aura)
	local own = {}
	for k, v in pairs(aura) do own[k] = v end
	return own
end

-- The record a container keeps for `aura`: under the ProcessAura policy a
-- classified record of its own (a copy when `shared`), otherwise `aura` itself.
local function classify(c, aura, shared)
	if c.policy ~= PROCESS_AURA then return aura end
	if shared then aura = ownCopy(aura) end
	local o = c.policyOptions
	aura.processedAuraType = AuraUtil.ProcessAura(aura,
		o.displayOnlyDispellableDebuffs, o.ignoreBuffs, o.ignoreDebuffs, o.ignoreDispelDebuffs)
	return aura
end

-- A fresh read: a new table from the client, so the container's own.
local function read(c, id)
	local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(c.unit, id)
	return aura and classify(c, prepare(aura), false)
end

function Store.ForgetQueries(c)
	c.queriesStale = true
end

-- One query per distinct engine string: { engine = string, displays = { ... } }.
local function groupQueries(c)
	local queries, byEngine = {}, {}
	for _, display in ipairs(c.displays) do
		if display.enabled then
			local engine = display.compiled.engine
			local query = byEngine[engine]
			if query == nil then
				query = { engine = engine, displays = {} }
				byEngine[engine] = query
				queries[#queries + 1] = query
			end
			query.displays[#query.displays + 1] = display
		end
	end
	c.queries, c.queriesStale = queries, false
end

function Store.UsesPreview(c)
	return c.preview == true and c.fakeProvider == true
end

-- The full parse from edit mode's fake provider.
local function parsePreview(c)
	local cache, unit, policy = c.auras, c.unit, c.policy
	local byString, strings = {}, {}
	for _, display in ipairs(c.displays) do
		if display.enabled then
			local filterString = display.filterString
			local list = byString[filterString]
			if list == nil then
				list = {}
				byString[filterString] = list
				strings[#strings + 1] = filterString
			end
			list[#list + 1] = display
		end
	end
	for _, filterString in ipairs(strings) do
		local displays = byString[filterString]
		AuraUtil.ForEachAura(unit, filterString, nil, function(record)
			local id = record.auraInstanceID
			local aura = cache[id]
			if aura == nil then
				aura = ownCopy(record) -- the provider hands out its own tables
				aura.auraType, aura.casterGUID = AURA, nil
				aura = classify(c, aura, false)
				cache[id] = aura
			end
			for _, display in ipairs(displays) do display:Offer(unit, aura, policy, true, true) end
		end, true)
	end
end

function Store.FullParse(c)
	c.parsedGUID = UnitGUID(c.unit)
	local cache = c.auras
	wipe(cache)
	for _, display in ipairs(c.displays) do display:ClearMembers() end
	if c.enabled ~= true then return end
	if Store.UsesPreview(c) then
		parsePreview(c)
		return
	end

	if c.queriesStale then groupQueries(c) end
	local unit, policy = c.unit, c.policy
	for _, query in ipairs(c.queries) do
		local ids = C_UnitAuras.GetUnitAuraInstanceIDs(unit, query.engine)
		for _, id in ipairs(ids or {}) do
			local aura = cache[id]
			if aura == nil then
				aura = read(c, id)
				cache[id] = aura
			end
			if aura then
				for _, display in ipairs(query.displays) do
					display:Offer(unit, aura, policy, true)
				end
			end
		end
	end
end

local function offer(c, aura)
	local changed = false
	for _, display in ipairs(c.displays) do
		if display.enabled and display:Offer(c.unit, aura, c.policy, false) then changed = true end
	end
	return changed
end

local function drop(c, id)
	local changed = false
	for _, display in ipairs(c.displays) do
		if display.enabled and display:Drop(id) then changed = true end
	end
	return changed
end

function Store.ApplyUpdate(c, info)
	local cache, changed = c.auras, false
	if info.addedAuras then
		for _, payload in ipairs(info.addedAuras) do
			local aura = classify(c, prepare(payload), true)
			cache[aura.auraInstanceID] = aura
			changed = offer(c, aura) or changed
		end
	end
	if info.updatedAuraInstanceIDs then
		for _, id in ipairs(info.updatedAuraInstanceIDs) do
			local aura = read(c, id)
			cache[id] = aura
			if aura then
				changed = offer(c, aura) or changed
			else
				changed = drop(c, id) or changed
			end
		end
	end
	if info.removedAuraInstanceIDs then
		for _, id in ipairs(info.removedAuraInstanceIDs) do
			cache[id] = nil
			changed = drop(c, id) or changed
		end
	end
	return changed
end
