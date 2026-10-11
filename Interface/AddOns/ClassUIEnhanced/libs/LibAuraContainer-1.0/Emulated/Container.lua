--[[ LibAuraContainer-1.0: Emulated/Container

The emulated container: Private.NewContainer, the public container methods
and the checking of their arguments.

INTERFACE

  Private.NewContainer(name, parent, extraTemplates) -> frame
      Core.lua's CreateContainer on classic. A plain Frame from
      CreateFrame("Frame", name, parent, extraTemplates) ("" counts as none)
      carrying the public methods as fields. All scripts and events live on
      its driver child frame (Emulated/Pipeline.lua). Starts enabled, unit
      "none", edit-mode preview on, flow options LAC.Defaults.Layout, with a
      full pass pending (so the first rendered frame sizes it).

  Private.containerStates[frame] -> c, the container's state (weak keys):
      frame, driver, unit, enabled (as passed to SetEnabled; enabled means
      == true), preview (SetEditModePreviewEnabled) and fakeProvider (edit
      mode's provider is active, Pipeline), policy (LAC.AuraProcessingPolicy) and policyOptions
      (the ProcessAura options, defaults filled in; nil under None), flow (field names
      of LAC.Defaults.Layout), groups (registration order), groupByKey /
      slotByKey, displays (groups and slots in the order added),
      enchants (Display.NewEnchants: the item enchantment slots, their sort
      and layout), auras (Store cache), queries / queriesStale (Store), layoutEntries,
      pending / armed / onUpdate / clock and swapToken / swapEvents /
      swapRegistered (Pipeline), parsedGUID (Store).

ARGUMENT CHECKS
  Each public method checks its arguments before changing anything and raises
  "LibAuraContainer-1.0: <Method>: <reason>" at the caller. Options are read
  into the container's own copy (defaults filled in, maps copied), so a
  caller changing its tables later changes nothing. Fields the container does
  not know are ignored.
]]

local Private = LibStub("LibAuraContainer-1.0-Private")
if not Private.loading or Private.LAC.IsNative then return end
local LAC = Private.LAC

local Filter, Display, Store, Pipeline, Button = Private.Filter, Private.Display, Private.Store, Private.Pipeline, Private.Button

Private.containerStates = Private.containerStates or setmetatable({}, { __mode = "k" })
local states = Private.containerStates

local PREFIX = "LibAuraContainer-1.0: "
local EMPTY = {}

------------------------------------------------------------------ checks

-- Raises at the caller of the public method that called it.
local function check(ok, method, reason)
	if not ok then error(PREFIX .. method .. ": " .. tostring(reason), 3) end
	return ok
end

local function isOneOf(values, v)
	for _, allowed in pairs(values) do
		if v == allowed then return true end
	end
	return false
end

local function isNumber(v) return type(v) == "number" end
local function isBoolean(v) return type(v) == "boolean" end
local function isSize(v) return type(v) == "number" and v >= 0 end

local function isFrameCount(v)
	return v == math.huge or (type(v) == "number" and v >= 0 and v % 1 == 0)
end

local function isKey(v) return type(v) == "string" and v ~= "" end

-- Candidate filter fields compared as booleans.
local BOOLEAN_FILTERS = {
	"canApplyAura", "isBossAura", "isBossOrRoleAura", "isFromPlayerOrPlayerPet", "isPriorityAura",
	"isRoleAura", "isStealable", "nameplateShowAll", "nameplateShowPersonal",
}
-- Candidate filter fields that are sets keyed by spell ID or dispel type name.
local SET_FILTERS = { "excludeDispelTypes", "excludeSpellIDs", "includeDispelTypes", "includeSpellIDs" }

local function isProcessedType(v)
	local kinds = AuraUtil and AuraUtil.AuraUpdateChangedType
	return kinds ~= nil and v ~= kinds.None and isOneOf(kinds, v)
end

-- Each reader returns true, value or false, reason.
local function readCandidateFilters(v)
	if v == nil then return true, nil end
	if type(v) ~= "table" then return false, "candidateFilters must be a table or nil" end
	local out = {}
	for _, field in ipairs(SET_FILTERS) do
		local set = v[field]
		if set ~= nil then
			if type(set) ~= "table" then return false, "candidateFilters." .. field .. " must be a table" end
			local own = {}
			for k, x in pairs(set) do own[k] = x end
			out[field] = own
		end
	end
	for _, field in ipairs(BOOLEAN_FILTERS) do
		local flag = v[field]
		if flag ~= nil and not isBoolean(flag) then
			return false, "candidateFilters." .. field .. " must be a boolean"
		end
		out[field] = flag
	end
	if v.maxDuration ~= nil and not isSize(v.maxDuration) then
		return false, "candidateFilters.maxDuration must be a non-negative number"
	end
	out.maxDuration = v.maxDuration
	if v.processedAuraType ~= nil and not isProcessedType(v.processedAuraType) then
		return false, "candidateFilters.processedAuraType must be Buff, Debuff or Dispel (AuraUtil.AuraUpdateChangedType)"
	end
	out.processedAuraType = v.processedAuraType
	return true, out
end

local LAYOUT_FIELDS = {
	elementSpacing = isNumber, lineSpacing = isNumber, groupSpacing = isNumber,
	groupLineSpacing = isNumber, layoutIndex = isNumber, forceNewLine = isBoolean,
	elementWidth = isSize, elementHeight = isSize,
}

-- A group's layout options, or with forEnchants the enchant group's.
local function readLayout(v, forEnchants)
	if v ~= nil and type(v) ~= "table" then return false, "layout must be a table or nil" end
	local defaults = forEnchants and LAC.Defaults.ItemEnchantmentLayout or LAC.Defaults.GroupLayout
	local out = {}
	for field, default in pairs(defaults) do out[field] = default end
	for field, valid in pairs(LAYOUT_FIELDS) do
		local x = v and v[field]
		if x ~= nil then
			if not valid(x) then return false, "layout." .. field .. " has a wrong type or value" end
			out[field] = x
		end
	end
	if forEnchants and v and v.placement ~= nil then
		if not isOneOf(LAC.ItemEnchantmentPlacement, v.placement) then
			return false, "layout.placement must be a LAC.ItemEnchantmentPlacement value"
		end
		out.placement = v.placement
	end
	return true, out
end

-- The ProcessAura policy's options, defaults filled in.
local function readPolicyOptions(v)
	if v ~= nil and type(v) ~= "table" then return false, "options must be a table or nil" end
	local out = {}
	for field, default in pairs(LAC.Defaults.ProcessAuraPolicy) do
		local x = v and v[field]
		if x == nil then
			x = default
		elseif not isBoolean(x) then
			return false, "options." .. field .. " must be a boolean or nil"
		end
		out[field] = x
	end
	return true, out
end

local function readSort(method, direction)
	if not isOneOf(LAC.SortMethod, method) then return false, "sortMethod must be a LAC.SortMethod value" end
	if not isOneOf(LAC.SortDirection, direction) then return false, "sortDirection must be a LAC.SortDirection value" end
	return true, Filter.GetComparator(method, direction)
end

local function readTemplates(v)
	if v == nil then return true, nil end
	if type(v) ~= "table" then return false, "templateNames must be a table or nil" end
	local names = {}
	for i, name in ipairs(v) do
		if type(name) ~= "string" then return false, "templateNames[" .. i .. "] must be a string" end
		names[i] = name
	end
	return true, names[1] and table.concat(names, ", ") or nil
end

-- Group and slot options: the settings Display.NewGroup / NewSlot take.
local function readDisplayOptions(v, defaults, forGroup)
	if v ~= nil and type(v) ~= "table" then return false, "options must be a table or nil" end
	v = v or EMPTY
	local s, ok = {}, nil
	ok, s.templates = readTemplates(v.templateNames)
	if not ok then return false, s.templates end
	if v.initializeFrame ~= nil and type(v.initializeFrame) ~= "function" then
		return false, "initializeFrame must be a function or nil"
	end
	s.initializeFrame = v.initializeFrame
	ok, s.candidateFilters = readCandidateFilters(v.candidateFilters)
	if not ok then return false, s.candidateFilters end
	local method, direction = v.sortMethod, v.sortDirection
	if method == nil then method = defaults.sortMethod end
	if direction == nil then direction = defaults.sortDirection end
	ok, s.comparator = readSort(method, direction)
	if not ok then return false, s.comparator end
	if forGroup then
		s.maxFrameCount = v.maxFrameCount
		if s.maxFrameCount == nil then s.maxFrameCount = defaults.maxFrameCount end
		if not isFrameCount(s.maxFrameCount) then
			return false, "maxFrameCount must be a non-negative integer or math.huge"
		end
		ok, s.layout = readLayout(v.layout)
		if not ok then return false, s.layout end
	end
	return true, s
end

-- The group / slot named `key`, or an error at the caller of the public method.
local function groupOf(self, key, method)
	local c = states[self]
	local group = c.groupByKey[key]
	if group == nil then error(PREFIX .. method .. ": no aura group '" .. tostring(key) .. "'", 3) end
	return c, group
end

local function slotOf(self, key, method)
	local c = states[self]
	local slot = c.slotByKey[key]
	if slot == nil then error(PREFIX .. method .. ": no aura slot '" .. tostring(key) .. "'", 3) end
	return c, slot
end

------------------------------------------------------------------ shared steps

-- A display was added, enabled or disabled.
local function displaysChanged(c)
	Store.ForgetQueries(c)
	Pipeline.UpdateEvents(c)
	Pipeline.RequestFull(c)
end

-- As 12.1.5, also an unchanged value refreshes fully.
-- Events and the refresh are settled before the buttons are cleared, so a Clear
-- that raises (consumer script) is retried by that refresh's reset, or by the
-- next requested pass if it raises there too.
local function setDisplayEnabled(c, display, enabled)
	display.enabled = enabled
	if not enabled then display:ClearMembers() end
	displaysChanged(c)
	if not enabled then display:ReleaseAll() end
end

local function setFilterString(c, display, filterString, compiled)
	if display.filterString == filterString then return end
	display.filterString, display.compiled = filterString, compiled
	display:ClearMembers()
	Store.ForgetQueries(c)
	Pipeline.RequestFull(c)
end

local function setCandidateFilters(c, display, filters)
	display.candidateFilters = filters
	display:ClearMembers()
	Pipeline.UpdateEvents(c)
	Pipeline.RequestFull(c)
end

local function setComparator(c, display, comparator)
	display.comparator = comparator
	display.dirty = true
	Pipeline.RequestAssign(c)
end

-- groups: also listed in c.groups (layout order needs the registration position).
local function register(c, display, byKey, groups)
	if groups then groups[#groups + 1] = display end
	byKey[display.key] = display
	c.displays[#c.displays + 1] = display
	displaysChanged(c)
end

------------------------------------------------------------------ public methods

local methods = {}

function methods:IsEnabled()
	return states[self].enabled == true
end

function methods:SetEnabled(enabled)
	local c = states[self]
	if c.enabled == enabled then return end
	c.enabled = enabled
	Pipeline.UpdateEvents(c)
	Pipeline.RequestFull(c)
end

function methods:GetUnit()
	return states[self].unit
end

function methods:SetUnit(unit)
	check(type(unit) == "string", "SetUnit", "unit must be a string")
	local c = states[self]
	if c.unit == unit then return end
	c.unit = unit
	Pipeline.UpdateEvents(c)
	Pipeline.RequestFull(c)
end

function methods:UpdateAllAuras()
	Pipeline.RequestFull(states[self])
end

function methods:IsEditModePreviewEnabled()
	return states[self].preview
end

-- Re-parses when the change switches the container's aura source.
function methods:SetEditModePreviewEnabled(enabled)
	local c = states[self]
	local before = Store.UsesPreview(c)
	c.preview = enabled == true
	if Store.UsesPreview(c) ~= before then Pipeline.RequestFull(c) end
end

-- Groups

function methods:AddAuraGroup(key, filterString, options)
	local c = states[self]
	check(isKey(key), "AddAuraGroup", "groupKey must be a non-empty string")
	local compiled, why = Filter.Compile(filterString)
	check(compiled, "AddAuraGroup", why)
	check(c.groupByKey[key] == nil, "AddAuraGroup", "aura group '" .. key .. "' already exists")
	local ok, s = readDisplayOptions(options, LAC.Defaults.Group, true)
	check(ok, "AddAuraGroup", s)
	s.filterString, s.compiled, s.clock = filterString, compiled, c.clock
	register(c, Display.NewGroup(self, key, s), c.groupByKey, c.groups)
end

function methods:HasAuraGroup(key)
	return states[self].groupByKey[key] ~= nil
end

function methods:GetAuraGroupFrame(key, index)
	local group = states[self].groupByKey[key]
	return group and group.pool.owned[index] or nil
end

function methods:GetAuraGroupFrameCount(key)
	local group = states[self].groupByKey[key]
	return group and #group.pool.owned or 0
end

function methods:IsAuraGroupEnabled(key)
	local _, group = groupOf(self, key, "IsAuraGroupEnabled")
	return group.enabled
end

function methods:SetAuraGroupEnabled(key, enabled)
	check(isBoolean(enabled), "SetAuraGroupEnabled", "enabled must be a boolean")
	local c, group = groupOf(self, key, "SetAuraGroupEnabled")
	setDisplayEnabled(c, group, enabled)
end

function methods:SetAuraGroupFilterString(key, filterString)
	local c, group = groupOf(self, key, "SetAuraGroupFilterString")
	local compiled, why = Filter.Compile(filterString)
	check(compiled, "SetAuraGroupFilterString", why)
	setFilterString(c, group, filterString, compiled)
end

function methods:SetAuraGroupMaxFrameCount(key, maxFrameCount)
	local c, group = groupOf(self, key, "SetAuraGroupMaxFrameCount")
	check(isFrameCount(maxFrameCount), "SetAuraGroupMaxFrameCount", "maxFrameCount must be a non-negative integer or math.huge")
	if group.maxFrameCount == maxFrameCount then return end
	group.maxFrameCount = maxFrameCount
	group.dirty = true
	Pipeline.RequestAssign(c)
end

function methods:SetAuraGroupCandidateFilters(key, candidateFilters)
	local c, group = groupOf(self, key, "SetAuraGroupCandidateFilters")
	local ok, filters = readCandidateFilters(candidateFilters)
	check(ok, "SetAuraGroupCandidateFilters", filters)
	setCandidateFilters(c, group, filters)
end

function methods:SetAuraGroupSortMethod(key, sortMethod, sortDirection)
	local c, group = groupOf(self, key, "SetAuraGroupSortMethod")
	local ok, comparator = readSort(sortMethod, sortDirection)
	check(ok, "SetAuraGroupSortMethod", comparator)
	setComparator(c, group, comparator)
end

function methods:SetAuraGroupLayout(key, layout)
	local c, group = groupOf(self, key, "SetAuraGroupLayout")
	local ok, own = readLayout(layout)
	check(ok, "SetAuraGroupLayout", own)
	group.layout = own
	Pipeline.RequestLayout(c)
end

-- Slots

function methods:AddAuraSlot(key, filterString, options)
	local c = states[self]
	check(isKey(key), "AddAuraSlot", "slotKey must be a non-empty string")
	local compiled, why = Filter.Compile(filterString)
	check(compiled, "AddAuraSlot", why)
	check(c.slotByKey[key] == nil, "AddAuraSlot", "aura slot '" .. key .. "' already exists")
	local ok, s = readDisplayOptions(options, LAC.Defaults.Slot, false)
	check(ok, "AddAuraSlot", s)
	s.filterString, s.compiled, s.clock = filterString, compiled, c.clock
	local slot = Display.NewSlot(self, key, s)
	register(c, slot, c.slotByKey)
	return slot.button
end

function methods:GetAuraSlotFrame(key)
	local slot = states[self].slotByKey[key]
	return slot and slot.button or nil
end

function methods:IsAuraSlotEnabled(key)
	local _, slot = slotOf(self, key, "IsAuraSlotEnabled")
	return slot.enabled
end

function methods:SetAuraSlotEnabled(key, enabled)
	check(isBoolean(enabled), "SetAuraSlotEnabled", "enabled must be a boolean")
	local c, slot = slotOf(self, key, "SetAuraSlotEnabled")
	setDisplayEnabled(c, slot, enabled)
end

function methods:SetAuraSlotFilterString(key, filterString)
	local c, slot = slotOf(self, key, "SetAuraSlotFilterString")
	local compiled, why = Filter.Compile(filterString)
	check(compiled, "SetAuraSlotFilterString", why)
	setFilterString(c, slot, filterString, compiled)
end

function methods:SetAuraSlotCandidateFilters(key, candidateFilters)
	local c, slot = slotOf(self, key, "SetAuraSlotCandidateFilters")
	local ok, filters = readCandidateFilters(candidateFilters)
	check(ok, "SetAuraSlotCandidateFilters", filters)
	setCandidateFilters(c, slot, filters)
end

function methods:SetAuraSlotSortMethod(key, sortMethod, sortDirection)
	local c, slot = slotOf(self, key, "SetAuraSlotSortMethod")
	local ok, comparator = readSort(sortMethod, sortDirection)
	check(ok, "SetAuraSlotSortMethod", comparator)
	setComparator(c, slot, comparator)
end

-- Item enchantments

local function enchantOf(self, slot, method)
	local c = states[self]
	local e = c.enchants:Get(slot)
	if e == nil then error(PREFIX .. method .. ": no item enchantment for slot " .. tostring(slot), 3) end
	return c, e
end

local function isEnchantSlot(v) return isOneOf(LAC.ItemEnchantmentSlot, v) end

function methods:AddItemEnchantment(slot, options)
	local c = states[self]
	check(isEnchantSlot(slot), "AddItemEnchantment", "slot must be a LAC.ItemEnchantmentSlot value")
	check(c.enchants:Get(slot) == nil, "AddItemEnchantment", "slot " .. tostring(slot) .. " already has an item enchantment")
	check(options == nil or type(options) == "table", "AddItemEnchantment", "options must be a table or nil")
	options = options or EMPTY
	local ok, templates = readTemplates(options.templateNames)
	check(ok, "AddItemEnchantment", templates)
	check(options.initializeFrame == nil or type(options.initializeFrame) == "function",
		"AddItemEnchantment", "initializeFrame must be a function or nil")
	local hidePermanent = options.hidePermanent
	if hidePermanent == nil then hidePermanent = LAC.Defaults.ItemEnchantment.hidePermanent end
	check(isBoolean(hidePermanent), "AddItemEnchantment", "hidePermanent must be a boolean or nil")

	local button = Button.New(self, templates, options.initializeFrame, c.clock)
	c.enchants:Add(slot, button, hidePermanent)
	Pipeline.UpdateEvents(c)
	Pipeline.RequestAssign(c)
	Pipeline.RequestLayout(c)
	return button
end

function methods:GetItemEnchantmentFrame(slot)
	local e = states[self].enchants:Get(slot)
	return e and e.button or nil
end

function methods:IsItemEnchantmentEnabled(slot)
	local _, e = enchantOf(self, slot, "IsItemEnchantmentEnabled")
	return e.enabled
end

function methods:SetItemEnchantmentEnabled(slot, enabled)
	check(isEnchantSlot(slot), "SetItemEnchantmentEnabled", "slot must be a LAC.ItemEnchantmentSlot value")
	check(isBoolean(enabled), "SetItemEnchantmentEnabled", "enabled must be a boolean")
	local c, e = enchantOf(self, slot, "SetItemEnchantmentEnabled")
	-- As 12.1.5, an unchanged value refreshes fully too. Events and the refresh
	-- are settled first, so a Clear that raises below is retried by that
	-- refresh's reset, or by the next requested pass if it raises there too.
	c.enchants:SetEnabled(e, enabled)
	Pipeline.UpdateEvents(c)
	Pipeline.RequestFull(c)
	c.enchants:ClearDisabled(e)
end

function methods:SetItemEnchantmentSortMethod(sortMethod, sortDirection)
	check(isOneOf(LAC.ItemEnchantmentSortMethod, sortMethod), "SetItemEnchantmentSortMethod",
		"sortMethod must be a LAC.ItemEnchantmentSortMethod value")
	check(isOneOf(LAC.SortDirection, sortDirection), "SetItemEnchantmentSortMethod",
		"sortDirection must be a LAC.SortDirection value")
	local c = states[self]
	c.enchants:SetSort(sortMethod == LAC.ItemEnchantmentSortMethod.Duration, sortDirection == LAC.SortDirection.Reverse)
	Pipeline.RequestLayout(c)
end

function methods:SetItemEnchantmentLayout(layout)
	local ok, own = readLayout(layout, true)
	check(ok, "SetItemEnchantmentLayout", own)
	local c = states[self]
	c.enchants.layout = own
	Pipeline.RequestLayout(c)
end

function methods:ResetItemEnchantmentLayout()
	local c = states[self]
	c.enchants.layout = select(2, readLayout(nil, true))
	Pipeline.RequestLayout(c)
end

-- Processing policy. Every call re-parses: the policy decides which
-- records the store keeps (Emulated/Store.lua).

function methods:GetAuraProcessingPolicy()
	return states[self].policy
end

function methods:SetAuraProcessingPolicy(policy, options)
	local c = states[self]
	local P = LAC.AuraProcessingPolicy
	check(isOneOf(P, policy), "SetAuraProcessingPolicy", "policy must be a LAC.AuraProcessingPolicy value")
	local own
	if policy == P.ProcessAura then
		local ok
		ok, own = readPolicyOptions(options)
		check(ok, "SetAuraProcessingPolicy", own)
	else
		check(options == nil, "SetAuraProcessingPolicy", "this policy takes no options")
	end
	c.policy, c.policyOptions = policy, own
	Pipeline.UpdateEvents(c)
	Pipeline.RequestFull(c)
end

-- Flow layout. Every setter re-lays out only when a value changed.

local function setFlow(self, a, va, b, vb, d, vd, e, ve)
	local c = states[self]
	local flow = c.flow
	if flow[a] == va and (b == nil or flow[b] == vb) and (d == nil or flow[d] == vd) and (e == nil or flow[e] == ve) then
		return
	end
	flow[a] = va
	if b then flow[b] = vb end
	if d then flow[d] = vd end
	if e then flow[e] = ve end
	Pipeline.RequestLayout(c)
end

function methods:GetFlowLayoutAxis()
	return states[self].flow.axis
end

function methods:SetFlowLayoutAxis(axis)
	check(isOneOf(LAC.FlowLayoutAxis, axis), "SetFlowLayoutAxis", "axis must be a LAC.FlowLayoutAxis value")
	setFlow(self, "axis", axis)
end

function methods:GetFlowLayoutAnchorPoint()
	return states[self].flow.anchorPoint
end

function methods:SetFlowLayoutAnchorPoint(anchorPoint)
	check(type(anchorPoint) == "string", "SetFlowLayoutAnchorPoint", "anchorPoint must be a string")
	setFlow(self, "anchorPoint", anchorPoint)
end

function methods:GetFlowLayoutGrowthDirection()
	local flow = states[self].flow
	return flow.horizontalGrowthDirection, flow.verticalGrowthDirection
end

function methods:SetFlowLayoutGrowthDirection(horizontal, vertical)
	check(isOneOf(LAC.FlowDirection, horizontal) and isOneOf(LAC.FlowDirection, vertical),
		"SetFlowLayoutGrowthDirection", "directions must be LAC.FlowDirection values")
	setFlow(self, "horizontalGrowthDirection", horizontal, "verticalGrowthDirection", vertical)
end

function methods:GetFlowLayoutPadding()
	local flow = states[self].flow
	return flow.paddingLeft, flow.paddingRight, flow.paddingTop, flow.paddingBottom
end

function methods:SetFlowLayoutPadding(left, right, top, bottom)
	check(isNumber(left) and isNumber(right) and isNumber(top) and isNumber(bottom),
		"SetFlowLayoutPadding", "left, right, top and bottom must be numbers")
	setFlow(self, "paddingLeft", left, "paddingRight", right, "paddingTop", top, "paddingBottom", bottom)
end

function methods:GetFlowLayoutMaximumLineSize()
	return states[self].flow.maximumLineSize
end

function methods:SetFlowLayoutMaximumLineSize(size)
	check(size == nil or isNumber(size), "SetFlowLayoutMaximumLineSize", "size must be a number or nil")
	setFlow(self, "maximumLineSize", size or math.huge)
end

local function defaultFlow(flow)
	for field, value in pairs(LAC.Defaults.Layout) do flow[field] = value end
	return flow
end

function methods:ResetFlowLayoutOptions()
	local c = states[self]
	defaultFlow(c.flow)
	Pipeline.RequestLayout(c)
end

------------------------------------------------------------------ construction

function Private.NewContainer(name, parent, extraTemplates)
	if extraTemplates == "" then extraTemplates = nil end
	local frame = CreateFrame("Frame", name, parent, extraTemplates)
	local c = {
		frame = frame, unit = "none", enabled = true, preview = true, fakeProvider = false,
		policy = LAC.AuraProcessingPolicy.None, flow = defaultFlow({}),
		groups = {}, groupByKey = {}, slotByKey = {}, displays = {},
		auras = {}, queries = {}, queriesStale = true, layoutEntries = {},
		enchants = Display.NewEnchants(),
	}
	c.enchants.layout = select(2, readLayout(nil, true))
	states[frame] = c
	for methodName, fn in pairs(methods) do frame[methodName] = fn end
	Pipeline.Attach(c)
	Pipeline.RequestFull(c)
	return frame
end
