--[[ LibAuraContainer-1.0: Emulated/ButtonExtras

The button elements beyond the core display of Emulated/Button.lua, added
through its seam (Button.DefineElement, Button.methods, Button.onNew,
Button.beforeVisibility, Button.afterVisibility, Button.kit).

  CasterName            a FontString element: the caster's name from the
                        record's casterGUID (Emulated/Store.lua sets it)
  AuraBorder            the 12.1.0 names: SetAuraBorder replaces every dispel
                        texture with one; Get/Clear act on that set
  AuraSymbol            the 12.1.0 names of the DispelTypeText methods
  pandemic regions      a list of regions shown while inside the window (12.1.0:
                        Add returns the index, duplicates allowed, Remove by
                        region or index)
  animation families    PandemicEnter/Active/Leave, AuraAssigned, AuraShown:
                        lists of AnimationGroups, 12.1.5 style (Add returns
                        nothing and rejects a group already listed, Remove
                        takes the group)

PANDEMIC
  The window is [expirationTime - 0.3 * duration, expirationTime): the last
  30 % of the aura's duration, worked out from the held record alone (no
  client reads, no cache: the same record always gives the same window, a
  refreshed one moves it). timeMod is not applied (it is 1 for the
  periodic effects pandemic concerns). It is only worked out while the button
  has a pandemic region or pandemic animation (nothing else can show it);
  the first one added joins silently, without animations.
  st.inPandemic is the state the last pass saw. The next edge (window start,
  else window end) is one clock entry keyed by the button, replaced on every
  pass and dropped when there is none (no window, cleared, past the end).
  An edge runs the pandemic step as an update.

STATE (in the button state st)
  pandemicRegions, and one list per animation family (FAMILIES[i].list);
  inPandemic.
]]

local Private = LibStub("LibAuraContainer-1.0-Private")
if not Private.loading or Private.LAC.IsNative then return end
local LAC = Private.LAC

local Button, Clock = Private.Button, Private.Clock
local kit, methods = Button.kit, Button.methods
local states, checkRegion, descendsFrom, reject = kit.states, kit.checkRegion, kit.descendsFrom, kit.reject

local ASSIGNMENT, UPDATE = LAC.UpdateMode.Assignment, LAC.UpdateMode.Update
local ENCHANT = LAC.AuraDataType.ItemEnchantment

------------------------------------------------------------------ caster name

-- The caster's name and realm, or nil when the client does not know them.
-- Classic has no UnitNameFromGUID: a caster that has a unit token now is named
-- by UnitName (NPCs included); otherwise GetPlayerInfoByGUID, players only.
local function lookUpName(guid)
	if UnitNameFromGUID then return UnitNameFromGUID(guid) end
	local token = UnitTokenFromGUID and UnitTokenFromGUID(guid)
	if token then return UnitName(token) end
	local _, _, _, _, _, name, realm = GetPlayerInfoByGUID(guid)
	return name, realm
end

local function casterLabel(guid, o)
	if guid == nil then return nil end
	local name, realm = lookUpName(guid)
	if name == nil or name == UNKNOWNOBJECT then return nil end
	local label = name
	if o.showRealmName and realm ~= nil and realm ~= "" then label = name .. "-" .. realm end
	if o.useClassColors then
		local _, classFile = UnitClassFromGUID(guid)
		local color = classFile and RAID_CLASS_COLORS[classFile]
		if color then label = color:WrapTextInColorCode(label) end
	end
	return label
end

Button.DefineElement({
	name = "CasterName", widget = "FontString",
	schema = {
		{ "showRealmName", kit.boolean, default = false },
		{ "useClassColors", kit.boolean, default = false },
	},
	show = function(st, fontString, o)
		local label = casterLabel(st.aura and st.aura.casterGUID, o)
		if label then fontString:SetText(label) end
		fontString:SetShown(label ~= nil)
	end,
})

------------------------------------------------------------------ 12.1.0 names

function methods:GetAuraBorder()
	return methods.GetDispelTypeTexture(self, 1)
end

function methods:SetAuraBorder(texture, options)
	kit.addDispelTexture(self, texture, options, "SetAuraBorder", true)
end

function methods:ClearAuraBorder()
	methods.ClearDispelTypeTextures(self)
end

methods.GetAuraSymbol = methods.GetDispelTypeText
methods.SetAuraSymbol = methods.SetDispelTypeText
methods.ClearAuraSymbol = methods.ClearDispelTypeText

------------------------------------------------------------------ animation lists

-- Families in the order their lists are named in the state; `pandemic` ones
-- make the button track its pandemic window.
local FAMILIES = {
	{ name = "PandemicEnterAnimation", list = "pandemicEnter", pandemic = true },
	{ name = "PandemicActiveAnimation", list = "pandemicActive", pandemic = true },
	{ name = "PandemicLeaveAnimation", list = "pandemicLeave", pandemic = true },
	{ name = "AuraAssignedAnimation", list = "assigned" },
	{ name = "AuraShownAnimation", list = "shown" },
}

local function playAll(groups)
	for _, animationGroup in ipairs(groups) do animationGroup:Play() end
end

local function stopAll(groups)
	for _, animationGroup in ipairs(groups) do animationGroup:Stop() end
end

local function find(list, object)
	for i, v in ipairs(list) do
		if v == object then return i end
	end
end

-- Argument check for animation groups: one of the button's, animating only the button and its regions.
local function checkAnimationGroup(button, animationGroup)
	local ok, reason = checkRegion(button, animationGroup, "AnimationGroup")
	if not ok then return false, reason end
	for _, animation in ipairs({ animationGroup:GetAnimations() }) do
		local target = animation:GetTarget()
		if target ~= button and not descendsFrom(target, button) then
			return false, "an animation of the group targets a region outside the button"
		end
	end
	return true
end

------------------------------------------------------------------ pandemic

local function hasPandemicDisplay(st)
	if st.pandemicRegions[1] ~= nil then return true end
	for _, family in ipairs(FAMILIES) do
		if family.pandemic and st[family.list][1] ~= nil then return true end
	end
	return false
end

-- The share of an aura's duration, at its end, that a refresh carries over.
local PANDEMIC_SHARE = 0.3

-- Window start and end for the held aura, or nil.
local function windowOf(aura)
	if aura == nil or aura.auraType == ENCHANT then return nil end
	local ends, length = aura.expirationTime or 0, aura.duration or 0
	if ends <= 0 or length <= 0 then return nil end
	return ends - PANDEMIC_SHARE * length, ends
end

local onEdge

-- Re-reads the window, stores whether the button is inside it now and moves
-- the button's clock entry to the next edge. Returns the old and new state.
local function trackWindow(button, st)
	local wasInside = st.inPandemic
	local start, ends
	if hasPandemicDisplay(st) then start, ends = windowOf(st.aura) end
	local now = GetTime()
	local inside, nextEdge = false, nil
	if start then
		inside = now >= start and now < ends
		if now < start then
			nextEdge = start
		elseif inside then
			nextEdge = ends
		end
	end
	st.inPandemic = inside
	if nextEdge then
		Clock.Schedule(st.clock, button, nextEdge, onEdge)
	else
		Clock.Cancel(st.clock, button)
	end
	return wasInside, inside
end

-- The pandemic step of a display pass: regions follow the window; an
-- assignment restarts the animations, an update plays the crossing.
local function showPandemic(button, st, mode)
	local wasInside, inside = trackWindow(button, st)
	for _, region in ipairs(st.pandemicRegions) do region:SetShown(inside) end
	local enters = inside and (mode == ASSIGNMENT or not wasInside)
	local leaves = mode ~= ASSIGNMENT and wasInside and not inside
	if mode == ASSIGNMENT or leaves then stopAll(st.pandemicActive) end
	if enters then
		playAll(st.pandemicEnter)
		playAll(st.pandemicActive)
	end
	if leaves then playAll(st.pandemicLeave) end
end

function onEdge(button)
	showPandemic(button, states[button], UPDATE)
end

-- The first pandemic display joins the window's current state without animations.
local function joinPandemic(button, st, hadDisplay)
	if not hadDisplay then trackWindow(button, st) end
end

------------------------------------------------------------------ the pass and the state

Button.onNew[#Button.onNew + 1] = function(st)
	st.pandemicRegions = {}
	for _, family in ipairs(FAMILIES) do st[family.list] = {} end
	st.inPandemic = false
end

-- Pandemic and assigned animations start before the button's own
-- visibility changes, shown animations after it (as in 12.1.5).
Button.beforeVisibility[#Button.beforeVisibility + 1] = function(button, st, mode)
	showPandemic(button, st, mode)
	if mode == ASSIGNMENT then
		stopAll(st.assigned)
		if st.aura then playAll(st.assigned) end
	end
end

Button.afterVisibility[#Button.afterVisibility + 1] = function(button, st, wasShown)
	if st.aura == nil then
		stopAll(st.shown)
	elseif not wasShown then
		playAll(st.shown)
	end
end

------------------------------------------------------------------ public methods

-- Returns the region's index; a region may be added twice.
function methods:AddPandemicRegion(region)
	local ok, reason = checkRegion(self, region, "Region")
	if not ok then reject("AddPandemicRegion", reason) end
	local st = states[self]
	local hadDisplay = hasPandemicDisplay(st)
	local list = st.pandemicRegions
	list[#list + 1] = region
	joinPandemic(self, st, hadDisplay)
	region:SetShown(st.inPandemic)
	return #list
end

-- An index removes that entry, a region its first occurrence.
function methods:RemovePandemicRegion(regionOrIndex)
	local list = states[self].pandemicRegions
	local at
	if type(regionOrIndex) == "number" then
		if list[regionOrIndex] ~= nil then at = regionOrIndex end
	else
		at = find(list, regionOrIndex)
	end
	if at then table.remove(list, at) end
end

function methods:ClearPandemicRegions()
	wipe(states[self].pandemicRegions)
end

for _, family in ipairs(FAMILIES) do
	local adder, listName = "Add" .. family.name, family.list

	methods[adder] = function(self, animationGroup)
		local ok, reason = checkAnimationGroup(self, animationGroup)
		if not ok then reject(adder, reason) end
		local st = states[self]
		local list = st[listName]
		if find(list, animationGroup) then reject(adder, "the animation group is already added") end
		local hadDisplay = hasPandemicDisplay(st)
		list[#list + 1] = animationGroup
		if family.pandemic then joinPandemic(self, st, hadDisplay) end
	end

	methods["Remove" .. family.name] = function(self, animationGroup)
		local list = states[self][listName]
		local at = find(list, animationGroup)
		if at then table.remove(list, at) end
	end

	methods["Clear" .. family.name .. "s"] = function(self)
		wipe(states[self][listName])
	end
end
