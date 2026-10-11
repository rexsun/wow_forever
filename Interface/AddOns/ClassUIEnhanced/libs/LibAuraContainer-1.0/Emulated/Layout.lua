--[[ LibAuraContainer-1.0: Emulated/Layout

The flow layout that positions group frames inside the container. Keeps no
state.

INTERFACE (Private.Layout)

  Group entries are tables the caller builds:
      entry.layout     the group's layout options (LAC.Defaults.GroupLayout /
                       Defaults.ItemEnchantmentLayout field names); nil, or a
                       nil field, means that field's default
      entry.elements   array of regions, laid out in array order; their size is
                       element:GetSize() unless layout.elementWidth /
                       elementHeight override it
      entry.registrationIndex   aura groups: the group's position among all
                       groups added to the container (1-based, disabled ones
                       included)
      entry.placement  the item-enchantment group only, instead of
                       registrationIndex: an LAC.ItemEnchantmentPlacement value
                       (anything but AfterAuraGroups means BeforeAuraGroups)

  Layout.Order(entries) -> entries
      Sorts the array in place and returns it. Each entry gets a
      slot number (registrationIndex; the item-enchantment group's is
      -math.huge for BeforeAuraGroups, math.huge for AfterAuraGroups) and a
      position (layout.layoutIndex, or its slot number when unset). Entries go
      by position; equal positions by slot number. So the enchant group without
      a layoutIndex is first or last, and with one it sits at that position,
      ahead of (Before) or behind (After) aura groups at the same position.

  Layout.Compute(options, groups, place) -> width, height
      Pure placement pass over ordered entries. options holds the
      container's flow options (LAC.Defaults.Layout field names: axis,
      anchorPoint, horizontal/verticalGrowthDirection, padding*,
      maximumLineSize); a nil field means its default. Calls
      place(element, x, y) (required) for every element, with x/y the
      offsets from the container's anchorPoint to the element's same point.
      Returns the container size, at least 1x1.

  Layout.Apply(container, options, groups) -> width, height
      Compute, then anchors each element to the container at anchorPoint
      (ClearAllPoints + one SetPoint, never relative to another element) and
      sizes the container.
]]

local Private = LibStub("LibAuraContainer-1.0-Private")
if not Private.loading or Private.LAC.IsNative then return end
local LAC = Private.LAC

local Layout = {}
Private.Layout = Layout

local abs, max, huge = math.abs, math.max, math.huge

local FLOW_DEFAULTS = LAC.Defaults.Layout
local GROUP_DEFAULTS = LAC.Defaults.GroupLayout
local VERTICAL = LAC.FlowLayoutAxis.Vertical
local RIGHT, DOWN = LAC.FlowDirection.Right, LAC.FlowDirection.Down
local AFTER = LAC.ItemEnchantmentPlacement.AfterAuraGroups

-- The value of `key` in `t`, or the default when t or the field is nil.
local function option(t, key, defaults)
	local v = t and t[key]
	if v == nil then v = defaults[key] end
	return v
end

------------------------------------------------------------------ order

local slotOf, positionOf = {}, {}

-- Insertion sort on the precomputed (position, slot) pair; group lists are short.
function Layout.Order(entries)
	for _, e in ipairs(entries) do
		local slot = e.registrationIndex
		if slot == nil then slot = e.placement == AFTER and huge or -huge end
		slotOf[e] = slot
		positionOf[e] = e.layout and e.layout.layoutIndex or slot
	end
	for i = 2, #entries do
		local moving = entries[i]
		local pos, slot = positionOf[moving], slotOf[moving]
		local j = i
		while j > 1 do
			local other = entries[j - 1]
			local otherPos = positionOf[other]
			if otherPos < pos or (otherPos == pos and slotOf[other] < slot) then break end
			entries[j] = other
			j = j - 1
		end
		entries[j] = moving
	end
	for _, e in ipairs(entries) do slotOf[e], positionOf[e] = nil, nil end
	return entries
end

------------------------------------------------------------------ placement

--[[ Two passes.

splitLines walks the ordered groups and cuts the flow into line records. A
record lists its elements with their distance from the line's start (padding
not included), and keeps:
  gap      space between the previous line and this one (unused for line 1)
  thick    the largest element extent across the line
  reach    the furthest any element ends along the line, for the size
  fill     how much of the line counts toward maximumLineSize: element
           lengths, the element spacing after each, and group spacing. A
           record only cuts when fill > 0 and the next element (or a group's
           leading spacing) would take it past the limit. A fill that has
           dropped to <= 0 (negative spacing) starts counting afresh at the
           next element.
  pen      where the next element starts along the line

Compute then stacks the records across, turns distances into signed x/y
offsets (a growth direction is +1/-1, the sign of WoW's offsets that way)
and takes the size from the records. ]]

local function newRecord(lines, gap)
	local record = { gap = gap, thick = 0, reach = 0, fill = 0, pen = 0, n = 0, items = {}, at = {} }
	lines[#lines + 1] = record
	return record
end

local function splitLines(groups, limit, vertical)
	local lines, line = {}, nil
	for _, group in ipairs(groups) do
		local elements, opts = group.elements, group.layout
		if #elements > 0 then
			local spacing = option(opts, "elementSpacing", GROUP_DEFAULTS)
			local wrapGap = option(opts, "lineSpacing", GROUP_DEFAULTS)
			local breakGap = option(opts, "groupLineSpacing", GROUP_DEFAULTS)
			local lead = option(opts, "groupSpacing", GROUP_DEFAULTS)
			local forcedWidth, forcedHeight = opts and opts.elementWidth, opts and opts.elementHeight

			if line == nil then
				line = newRecord(lines, 0)
			elseif option(opts, "forceNewLine", GROUP_DEFAULTS) then
				line = newRecord(lines, breakGap)
			elseif lead > 0 then
				if line.fill > 0 and line.fill + lead > limit then
					line = newRecord(lines, breakGap)
				else
					line.pen, line.fill = line.pen + lead, line.fill + lead
				end
			end

			for _, element in ipairs(elements) do
				local w, h = element:GetSize()
				w, h = forcedWidth or w, forcedHeight or h
				local long, thick = w, h
				if vertical then long, thick = h, w end

				if line.fill > 0 and line.fill + long > limit then
					line = newRecord(lines, wrapGap)
				end
				local n = line.n + 1
				line.n, line.items[n], line.at[n] = n, element, line.pen
				local ends = long
				if line.fill > 0 then ends = line.fill + long end
				if ends > line.reach then line.reach = ends end
				if thick > line.thick then line.thick = thick end
				line.fill = ends + spacing
				line.pen = line.pen + long + spacing
			end
		end
	end
	return lines
end

-- Padding on the side a growth direction starts from, then on the side it ends at.
local function edges(forward, positiveStart, positiveEnd, negativeStart, negativeEnd)
	if forward then return positiveStart, positiveEnd end
	return negativeStart, negativeEnd
end

function Layout.Compute(options, groups, place)
	local vertical = option(options, "axis", FLOW_DEFAULTS) == VERTICAL
	local xSign = option(options, "horizontalGrowthDirection", FLOW_DEFAULTS)
	local ySign = option(options, "verticalGrowthDirection", FLOW_DEFAULTS)
	local left, right = option(options, "paddingLeft", FLOW_DEFAULTS), option(options, "paddingRight", FLOW_DEFAULTS)
	local top, bottom = option(options, "paddingTop", FLOW_DEFAULTS), option(options, "paddingBottom", FLOW_DEFAULTS)
	local xFrom, xTo = edges(xSign == RIGHT, left, right, right, left)
	local yFrom, yTo = edges(ySign == DOWN, top, bottom, bottom, top)

	local lines = splitLines(groups, option(options, "maximumLineSize", FLOW_DEFAULTS), vertical)

	-- Lengths along a line map to x on the horizontal axis and to y on the vertical one.
	local alongFrom, alongTo, acrossFrom, acrossTo = xFrom, xTo, yFrom, yTo
	if vertical then alongFrom, alongTo, acrossFrom, acrossTo = yFrom, yTo, xFrom, xTo end

	local longest, deepest = 0, -huge
	local depth = acrossFrom
	for k, line in ipairs(lines) do
		if k > 1 then depth = depth + lines[k - 1].thick + line.gap end
		for i = 1, line.n do
			local along = alongFrom + line.at[i]
			if vertical then
				place(line.items[i], depth * xSign, along * ySign)
			else
				place(line.items[i], along * xSign, depth * ySign)
			end
		end
		longest = max(longest, line.reach)
		deepest = max(deepest, abs(depth) + line.thick)
	end

	local alongSize = alongFrom + longest + alongTo
	local acrossSize = max(acrossFrom, deepest) + acrossTo
	if vertical then
		return max(acrossSize, 1), max(alongSize, 1)
	end
	return max(alongSize, 1), max(acrossSize, 1)
end

function Layout.Apply(container, options, groups)
	local point = option(options, "anchorPoint", FLOW_DEFAULTS)
	local width, height = Layout.Compute(options, groups, function(element, x, y)
		element:ClearAllPoints()
		element:SetPoint(point, container, point, x, y)
	end)
	container:SetSize(width, height)
	return width, height
end
