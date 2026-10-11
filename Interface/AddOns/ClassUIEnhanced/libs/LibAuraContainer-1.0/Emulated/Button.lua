--[[ LibAuraContainer-1.0: Emulated/Button

The aura button our container hands out: an ordinary Button frame carrying the
public button methods. It shows one aura record on the regions a
consumer binds to it. The caster name,
AuraBorder/AuraSymbol, pandemic and animation elements are added by
Emulated/ButtonExtras.lua through the seam below.

INTERFACE (Private.Button), for the container

  Button.New(container, templates, initialize, clock) -> button
      CreateFrame("Button", nil, container, templates) plus the public methods,
      the built-in OnEnter/OnLeave handlers, one duration object and
      one duration text binding for the button's lifetime. The button
      starts hidden, holding no aura, with no click registration.
      initialize(button), when given (else nil), runs once the methods exist
      and before the button's first display update; an error in it
      goes to the error handler and the button is still returned.
      clock is the container's Private.Clock (Emulated/Clock.lua), shared by
      all its buttons for timed repaints.

  Button.Assign(button, unit, aura)
      Binds `aura` (the client's AuraData record, kept by reference, not copied)
      for `unit` as a new binding: LAC.UpdateMode.Assignment, i.e. a zero
      duration clears the cooldown and bars jump. Shows the button.
  Button.Update(button, aura)
      The bound aura changed (same auraInstanceID, fresh record):
      LAC.UpdateMode.Update, bars move with their interpolation option. The
      container calls this only when the aura really changed.
  Button.Clear(button)
      Unbinds the aura, repaints the elements empty and hides the button.
  Button.GetAura(button) -> unit, aura

  Records with auraType == LAC.AuraDataType.ItemEnchantment (Emulated/Display.lua
  makes them, unit "player") show the equipped item's texture and name (a
  name the client has not loaded yet re-runs the display when it loads), its
  inventory item as tooltip. Nothing is cancelled on click.

HOW THE PIECES FIT
  Per-button state lives in Private.buttonStates[button] (weak keys), never in
  fields of the frame. Single-region elements are described once in ELEMENTS
  (widget type, option schema, how to show the aura); their Get/Set/Clear
  methods are generated from that table. Dispel textures are a list; for
  each, planDispelTexture decides the look (pure) and applyDispelPlan writes it.
  Assign, Update and Clear all go through one show() pass.
  Options are validated and normalised into the button's own copy (defaults
  filled in); Get... returns a copy of that copy.

  Where the client's duration text binding has no SetTextColorCurve
  (classic), the textColor curve is repainted from the button's duration
  object on the clock, every binding update interval, while the button holds
  an aura with a running duration and its DurationText has the option.

SEAM (for Emulated/ButtonExtras.lua, loaded right after this file)
  Button.methods           the public methods every new button gets
  Button.DefineElement(e)  adds a single-region element like those in ELEMENTS
                           (Get/Set/Clear methods included)
  Button.onNew             list of function(st): fill in a new button's state
  Button.beforeVisibility  list of function(button, st, mode), run by every
                           show() pass after the elements, before the button's
                           own SetShown
  Button.afterVisibility   list of function(button, st, wasShown), run last;
                           wasShown is IsShown() from before the pass
  Button.kit               states, checkRegion, descendsFrom, reject,
                           readOptions, boolean, addDispelTexture (shared with
                           the public methods); the option checkers number,
                           text, asset, record, clientEnum (also used by
                           Emulated/Tooltip.lua)

  Button.New installs one dispatcher per built-in script through the
  frame's own SetScript, then gives the button SetScript/GetScript methods that
  keep a consumer's OnEnter/OnLeave in the button state (OnClick is the
  frame's own: there is no built-in click handler). The dispatcher
  runs the built-in handler, then the consumer's. A template's handler found at
  creation counts as the consumer's. HookScript is the frame's own, so hooks run
  after both.
]]

local Private = LibStub("LibAuraContainer-1.0-Private")
if not Private.loading or Private.LAC.IsNative then return end
local LAC = Private.LAC

local Button = {}
Private.Button = Button

Private.buttonStates = Private.buttonStates or setmetatable({}, { __mode = "k" })
local states = Private.buttonStates

local ASSIGNMENT, UPDATE = LAC.UpdateMode.Assignment, LAC.UpdateMode.Update
local ENCHANT = LAC.AuraDataType.ItemEnchantment
local STYLE = LAC.DispelTypeTextureStyle
local Clock = Private.Clock
local PREFIX = "LibAuraContainer-1.0: "

------------------------------------------------------------------ option checking

-- A checker takes a value (never nil) and returns true, normalisedValue or
-- false, reason. Schemas list fields as { name, checker, default =, required = }.

local function isType(...)
	local accepted = {}
	for i = 1, select("#", ...) do accepted[select(i, ...)] = true end
	local expected = table.concat({ ... }, " or ")
	return function(v)
		if accepted[type(v)] then return true, v end
		return false, "expected " .. expected .. ", got " .. type(v)
	end
end

local boolean, number, text = isType("boolean"), isType("number"), isType("string")
local asset = isType("string", "number")

-- Formatters, curves and bindings passed in options. They are kept by reference,
-- also through Get... copies, even when they are plain Lua tables.
local sharedObjects = setmetatable({}, { __mode = "k" })
local objectType = isType("table", "userdata")

local function object(v)
	local ok, reason = objectType(v)
	if not ok then return false, reason end
	if type(v) == "table" then sharedObjects[v] = true end
	return true, v
end

-- `values` returns the enum table, read when checking (client enums may load late).
local function enum(values)
	return function(v)
		for _, allowed in pairs(values() or {}) do
			if v == allowed then return true, v end
		end
		return false, "not a valid value: " .. tostring(v)
	end
end

local function clientEnum(name)
	return enum(function() return Enum[name] end)
end

-- Deep copy of option data; option objects and tables with a metatable are shared.
local function copyValue(v)
	if type(v) ~= "table" or sharedObjects[v] or getmetatable(v) ~= nil then return v end
	local c = {}
	for k, inner in pairs(v) do c[k] = copyValue(inner) end
	return c
end

-- A plain table of data (a colour, a component list), copied.
local function map(v)
	if type(v) ~= "table" then return false, "expected a table, got " .. type(v) end
	return true, copyValue(v)
end

-- Validates `input` against `schema` and returns true, a new table with defaults
-- filled in (unknown fields dropped), or false, reason.
local function readOptions(schema, input)
	if input == nil then
		if schema.required then return false, "options are required" end
		input = {}
	elseif type(input) ~= "table" then
		return false, "options must be a table"
	end
	local out = {}
	for _, field in ipairs(schema) do
		local name, check = field[1], field[2]
		local v = input[name]
		if v == nil then
			if field.required then return false, "options." .. name .. " is required" end
			out[name] = copyValue(field.default)
		else
			local ok, value = check(v)
			if not ok then return false, "options." .. name .. ": " .. value end
			out[name] = value
		end
	end
	return true, out
end

local function record(schema)
	return function(v)
		if type(v) ~= "table" then return false, "expected a table, got " .. type(v) end
		return readOptions(schema, v)
	end
end

-- A table whose every value passes `check`.
local function mapOf(check)
	return function(v)
		if type(v) ~= "table" then return false, "expected a table, got " .. type(v) end
		local out = {}
		for k, inner in pairs(v) do
			local ok, value = check(inner)
			if not ok then return false, "[" .. tostring(k) .. "] " .. value end
			out[k] = value
		end
		return true, out
	end
end

local interpolation = clientEnum("StatusBarInterpolation")

local APPLICATION_BAR = {
	required = true,
	{ "maxApplications", number, required = true },
	{ "minApplications", number, default = 0 },
	{ "interpolation", interpolation },
}

local APPLICATION_COUNT = {
	{ "formatter", object },
}

local DISPEL_TEXT = {
	{ "showWhenHarmful", boolean, default = true },
	{ "showWhenHelpful", boolean, default = false },
	{ "showWithoutDispelType", boolean, default = false },
	{ "customDispelTextMap", mapOf(text) },
}

local TEX_COORDS = {
	{ "left", number, default = 0 },
	{ "right", number, default = 1 },
	{ "top", number, default = 0 },
	{ "bottom", number, default = 1 },
}

local CUSTOM_ASSET = {
	{ "asset", asset, required = true },
	{ "useAtlasSize", boolean, default = false },
	{ "texCoords", record(TEX_COORDS) },
}

local DISPEL_TEXTURE = {
	{ "showAlways", boolean, default = false },
	{ "showWhenHarmful", boolean, default = true },
	{ "showWhenHelpful", boolean, default = false },
	{ "showWithoutDispelType", boolean, default = false },
	{ "stealableFilter", enum(function() return LAC.DispelTypeStealableFilter end) },
	{ "style", enum(function() return STYLE end), default = STYLE.BorderWithIcon },
	{ "customDispelAssetMap", mapOf(record(CUSTOM_ASSET)) },
	{ "customDispelColorMap", mapOf(map) },
	{ "customDispelColorCurve", object },
}

local DURATION_BAR = {
	{ "interpolation", interpolation },
	{ "direction", clientEnum("StatusBarTimerDirection") },
}

local bindingProperty = clientEnum("DurationTextBindingProperty")

local DURATION_TEXT = {
	{ "binding", object },
	{ "textFormatter", object },
	{ "textFormat", record({ { "formatString", text, required = true }, { "components", map, required = true } }) },
	{ "textColor", record({ { "curve", object, required = true }, { "property", bindingProperty, required = true } }) },
}

-- Is `button` one of `region`'s ancestors? false for a missing region.
local function descendsFrom(region, button)
	if region == nil then return false end
	local ancestor = region:GetParent()
	while ancestor ~= nil and ancestor ~= button do
		ancestor = ancestor:GetParent()
	end
	return ancestor ~= nil
end

-- Is `region` a `widget` strictly inside `button`? Returns true or false, reason.
local function checkRegion(button, region, widget)
	if type(region) ~= "table" or type(region.IsObjectType) ~= "function" then
		return false, "expected a " .. widget .. ", got " .. type(region)
	end
	if not region:IsObjectType(widget) then
		return false, "expected a " .. widget .. ", got a " .. tostring(region:GetObjectType())
	end
	if not descendsFrom(region, button) then
		return false, "the region must be a descendant of the button"
	end
	return true
end

-- Raises the error for the caller of a public method; `depth` counts the
-- helpers between that method and this call (default 0).
local function reject(method, reason, depth)
	error(PREFIX .. method .. ": " .. reason, 3 + (depth or 0))
end

------------------------------------------------------------------ item enchantments

local repaint -- function(button): show the held aura again as an update

-- The name of the item in an inventory slot of the player, or nil while the
-- client has not loaded it (the button is then repainted once it has) or the
-- slot is empty (nothing to wait for: the client refuses a load request then).
-- A button waits for one item at a time; a newer request replaces the older.
local function itemName(st, inventorySlot)
	local item = Item:CreateFromEquipmentSlot(inventorySlot)
	if item:IsItemEmpty() then return nil end
	local name = item:GetItemName()
	if name == nil then
		if st.cancelItemLoad then st.cancelItemLoad() end
		local button = st.button
		st.cancelItemLoad = item:ContinueWithCancelOnItemLoad(function()
			st.cancelItemLoad = nil
			repaint(button)
		end)
	end
	return name
end

------------------------------------------------------------------ duration

-- The span the duration object gets for an aura, or nothing for "no expiry".
local function expiry(aura)
	local ends = aura and aura.expirationTime or 0
	if ends > 0 then return ends, aura.duration, aura.timeMod or 1 end
end

-- 90 s still reads "90 s" and 91 s reads "1 m" (likewise 90 m / 91 m, 36 h / 37 h).
-- The step curve therefore moves to the next unit at 1.5 x the unit's length plus one second.
local UNIT_LENGTHS = { { 60, "Minutes" }, { 3600, "Hours" }, { 86400, "Days" } }

-- Built on first use, once per copy of the library: a newer copy that takes
-- over builds its own (its settings may differ), so this is not kept in Private.
local sharedDurationFormatter

local function defaultDurationFormatter()
	local formatter = sharedDurationFormatter
	if formatter then return formatter end
	local Interval = Enum.SecondsFormatterInterval
	local unitCurve = C_CurveUtil.CreateCurve()
	unitCurve:SetType(Enum.LuaCurveType.Step)
	unitCurve:AddPoint(0, Interval.Seconds)
	for _, unit in ipairs(UNIT_LENGTHS) do
		unitCurve:AddPoint(unit[1] * 3 / 2 + 1, Interval[unit[2]])
	end
	formatter = C_StringUtil.CreateSecondsFormatter()
	formatter:SetMinInterval(Interval.Seconds)
	formatter:SetMaxIntervalCurve(unitCurve)
	formatter:SetDesiredUnitCount(1)
	formatter:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
	formatter:SetCanRoundUpLastUnit(true)
	if formatter.SetRounding and Enum.SecondsFormatterRounding then
		formatter:SetRounding(Enum.SecondsFormatterRounding.Truncate)
	end
	sharedDurationFormatter = formatter
	return formatter
end

LAC.Inbound.GetDefaultAuraDurationFormatter = defaultDurationFormatter

-- Readable binding state, copied where the client binding has no Assign.
local BINDING_PROPERTIES = { "ExpiredText", "ZeroDurationText", "TimeModifier", "UpdateInterval" }

-- Sets up the button's own binding from SetDurationText options.
-- Precedence for what the text formats with: textFormat, then textFormatter, then
-- the formatter of a binding the client copies whole (Assign), then the default.
local function configureDurationText(binding, fontString, o)
	local source = o.binding
	local wholeCopy = source ~= nil and binding.Assign ~= nil
	local formatter = o.textFormatter
	if formatter == nil and not wholeCopy then formatter = defaultDurationFormatter() end

	binding:SetToDefaults()
	if wholeCopy then
		binding:Assign(source)
	elseif source then
		for _, property in ipairs(BINDING_PROPERTIES) do
			local read = source["Get" .. property]
			if read then binding["Set" .. property](binding, read(source)) end
		end
	end
	if formatter then binding:SetFormatter(formatter) end
	local textFormat = o.textFormat
	if textFormat then binding:SetTextFormat(textFormat.formatString, textFormat.components) end
	binding:SetFontString(fontString)
end

------------------------------------------------------------------ duration text colour

-- The duration object's reading for each DurationTextBindingProperty, by enum key.
local PROPERTY_READERS = {
	RemainingDuration = "GetRemainingDuration", RemainingPercent = "GetRemainingPercent",
	ElapsedDuration = "GetElapsedDuration", ElapsedPercent = "GetElapsedPercent",
	TotalDuration = "GetTotalDuration", StartTime = "GetStartTime", EndTime = "GetEndTime",
}

local function readerFor(property)
	for key, value in pairs(Enum.DurationTextBindingProperty) do
		if value == property then return PROPERTY_READERS[key] end
	end
end

-- Remembers which curve the button repaints itself (st.colorCurve, st.colorReader);
-- a client binding that can colour its text gets the curve (or loses it) instead.
local function configureTextColor(st, textColor)
	st.colorCurve, st.colorReader = nil, nil
	local binding = st.binding
	if binding.SetTextColorCurve then
		if textColor then
			binding:SetTextColorCurve(textColor.curve, textColor.property)
		elseif binding.ClearTextColorCurve then
			binding:ClearTextColorCurve()
		end
	elseif textColor then
		st.colorCurve, st.colorReader = textColor.curve, readerFor(textColor.property)
	end
end

-- Clock callback (key = the button state): paint now, then again after the
-- binding's update interval while the duration runs.
local function repaintTextColor(st)
	local bound = st.elements.DurationText
	local duration, binding = st.duration, st.binding
	if not (bound and st.colorReader and st.aura) or duration:IsZero() then return end
	local value = duration[st.colorReader](duration, binding:GetTimeModifier())
	bound.region:SetTextColor(st.colorCurve:EvaluateUnpacked(value))
	if not duration:HasExpired() then
		Clock.Schedule(st.clock, st, GetTime() + binding:GetUpdateInterval(), repaintTextColor)
	end
end

local function restartTextColor(st)
	Clock.Cancel(st.clock, st)
	repaintTextColor(st)
end

------------------------------------------------------------------ element display

local function immediate()
	return Enum.StatusBarInterpolation.Immediate
end

-- Bars move with their interpolation option on updates and jump on assignment.
local function barMotion(o, mode)
	if mode == UPDATE and o.interpolation ~= nil then return o.interpolation end
	return immediate()
end

local function stacks(aura)
	return aura and aura.applications or 0
end

local function applicationText(aura, formatter)
	if aura == nil then return "" end
	if formatter then return formatter:FormatNumber(stacks(aura)) end
	return stacks(aura) > 1 and tostring(stacks(aura)) or ""
end

-- The entry of a per-dispel-type map (text, asset or colour) for this aura; "None"
-- stands for no dispel type.
local function byDispelType(perType, aura)
	return perType and perType[aura.dispelName or "None"]
end

-- Rules shared by dispel textures and the dispel text.
local function passesDispelRules(o, aura)
	if aura == nil then return false end
	if o.showAlways then return true end
	local allowed = (o.showWhenHarmful or not aura.isHarmful)
		and (o.showWhenHelpful or not aura.isHelpful)
		and (o.showWithoutDispelType or aura.dispelName ~= nil)
	if allowed and o.stealableFilter ~= nil then
		local wantStealable = o.stealableFilter == LAC.DispelTypeStealableFilter.Stealable
		allowed = wantStealable == (aura.isStealable == true)
	end
	return allowed and true or false
end

local function knownAtlas(name)
	return type(name) == "string" and C_Texture.GetAtlasInfo(name) ~= nil
end

-- The client's debuff display entry for a real dispel type, or nil.
local function displayEntry(dispelName)
	if dispelName == nil or dispelName == "None" then return nil end
	return AuraUtil.GetDebuffDisplayInfoTable()[dispelName]
end

-- Dispel texture looks, per style: what the texture shows. Fields:
--   atlas, atlasSize    an atlas to set
--   file                a file or file ID to set (false: no texture)
--   resetCoords, coords tex coord handling (custom asset only)
--   clientColor         keep the client's border colour instead of white
local LOOKS = {}

-- The first of the candidate atlases the client knows, as a look; nil if none.
local function firstKnownAtlas(a, b)
	if knownAtlas(a) then return { atlas = a, atlasSize = false } end
	if knownAtlas(b) then return { atlas = b, atlasSize = false } end
	return nil
end

-- Border styles: the border atlas of the aura's dispel type ("with icon" tries
-- the type's dispel-icon variant first, then the plain one), else the client's
-- border colour. A type the client lists no entry for borrows the "None" entry.
local function borderLook(aura, withIcon)
	local entries = AuraUtil.GetDebuffDisplayInfoTable()
	local entry = entries[aura.dispelName or "None"] or entries.None
	return firstKnownAtlas(withIcon and entry.dispelAtlas, entry.basicAtlas) or { clientColor = true }
end

LOOKS[STYLE.Border] = function(aura) return borderLook(aura, false) end
LOOKS[STYLE.BorderWithIcon] = function(aura) return borderLook(aura, true) end
LOOKS[STYLE.PreserveAsset] = function() return { clientColor = true } end

-- Icon style: the raid-frame dispel icon, else the type's with-icon border
-- (MoP has the first but not the second, other clients may differ), else nothing.
LOOKS[STYLE.Icon] = function(aura)
	local entry = displayEntry(aura.dispelName)
	if entry == nil then return { file = false } end
	return firstKnownAtlas("RaidFrame-Icon-Debuff" .. aura.dispelName, entry.dispelAtlas) or { file = false }
end

LOOKS[STYLE.CustomAsset] = function(aura, o)
	local custom = byDispelType(o.customDispelAssetMap, aura)
	if custom == nil then return { resetCoords = true, file = false } end
	if knownAtlas(custom.asset) then
		return { resetCoords = true, atlas = custom.asset, atlasSize = custom.useAtlasSize }
	end
	return { resetCoords = true, file = custom.asset, coords = custom.texCoords }
end

local WHITE = { r = 1, g = 1, b = 1, a = 1 }

-- Dispel texture as a pure decision: nil when the texture hides, else its look plus `color`
-- (nil = the client's border colour for `dispelName`).
local function planDispelTexture(o, unit, aura)
	if not passesDispelRules(o, aura) then return nil end
	local plan = LOOKS[o.style](aura, o)
	local color
	if o.customDispelColorCurve then
		color = C_UnitAuras.GetAuraDispelTypeColor(unit, aura.auraInstanceID, o.customDispelColorCurve)
	else
		color = byDispelType(o.customDispelColorMap, aura)
	end
	plan.color = color or (not plan.clientColor and WHITE) or nil
	plan.dispelName = aura.dispelName
	return plan
end

local function applyDispelPlan(texture, plan)
	if plan == nil then
		texture:Hide()
		return
	end
	if plan.resetCoords then texture:ResetTexCoord() end
	if plan.atlas then
		texture:SetAtlas(plan.atlas, plan.atlasSize)
	elseif plan.file ~= nil then
		texture:SetTexture(plan.file or nil)
		local c = plan.coords
		if c then texture:SetTexCoord(c.left, c.right, c.top, c.bottom) end
	end
	local color = plan.color
	if color then
		texture:SetVertexColor(color.r, color.g, color.b, color.a or 1)
	else
		AuraUtil.SetAuraBorderColor(texture, plan.dispelName)
	end
	texture:Show()
end

local function showDispelTexture(st, entry)
	applyDispelPlan(entry.region, planDispelTexture(entry.options, st.unit, st.aura))
end

-- Single-region elements, shown in this order. show(st, region, options, mode).
local ELEMENTS = {
	{
		name = "ApplicationBar", widget = "StatusBar", schema = APPLICATION_BAR,
		show = function(st, bar, o, mode)
			local count, floor = stacks(st.aura), o.minApplications
			bar:SetShown(count >= floor)
			bar:SetMinMaxValues(floor, math.max(1, o.maxApplications))
			bar:SetValue(count, barMotion(o, mode))
		end,
	},
	{
		name = "ApplicationCount", widget = "FontString", schema = APPLICATION_COUNT,
		show = function(st, fontString, o) fontString:SetText(applicationText(st.aura, o.formatter)) end,
	},
	{
		name = "DispelTypeText", widget = "FontString", schema = DISPEL_TEXT,
		show = function(st, fontString, o)
			local aura = st.aura
			local shown = passesDispelRules(o, aura)
			local custom = shown and byDispelType(o.customDispelTextMap, aura)
			if custom == nil then
				-- shown, no text of the consumer's: the client's symbol (and its visibility)
				AuraUtil.SetAuraSymbol(fontString, aura.dispelName)
				return
			end
			fontString:SetText(custom or "")
			fontString:SetShown(shown)
		end,
	},
	{
		name = "DurationCooldown", widget = "Cooldown",
		show = function(st, cooldown, _, mode) cooldown:SetCooldownFromDurationObject(st.duration, mode ~= UPDATE) end,
	},
	{
		name = "DurationText", widget = "FontString", schema = DURATION_TEXT, dropOptions = true,
		bind = function(st, fontString, o)
			configureDurationText(st.binding, fontString, o)
			configureTextColor(st, o.textColor)
		end,
		unbind = function(st)
			st.binding:SetEnabled(false)
			configureTextColor(st, nil)
			Clock.Cancel(st.clock, st)
		end,
		show = function(st)
			st.binding:SetDuration(st.duration)
			st.binding:SetEnabled(not st.duration:IsZero())
			restartTextColor(st)
		end,
	},
	{
		name = "DurationBar", widget = "StatusBar", schema = DURATION_BAR,
		show = function(st, bar, o, mode) bar:SetTimerDuration(st.duration, barMotion(o, mode), o.direction) end,
	},
	{
		name = "Icon", widget = "Texture",
		show = function(st, texture)
			local aura, icon = st.aura, nil
			if aura then
				icon = aura.icon
				if icon == nil and aura.auraType == ENCHANT then icon = GetInventoryItemTexture("player", aura.inventorySlot) end
			end
			texture:SetTexture(icon or QUESTION_MARK_ICON)
		end,
	},
	{
		name = "SpellName", widget = "FontString",
		show = function(st, fontString)
			local aura, name = st.aura, nil
			if aura then
				name = aura.name
				if name == nil and aura.auraType == ENCHANT then name = itemName(st, aura.inventorySlot) end
			end
			fontString:SetText(name or "")
		end,
	},
}

Button.beforeVisibility, Button.afterVisibility = {}, {}

-- The one path every aura change takes: hold the aura, move the duration object,
-- repaint every bound element, then the button's own visibility, with the
-- seam's steps on either side of it.
local function show(button, unit, aura, mode)
	local st = states[button]
	st.unit, st.aura = unit, aura
	local ends, length, rate = expiry(aura)
	if ends then
		st.duration:SetTimeFromEnd(ends, length, rate)
	else
		st.duration:SetTimeSpan(0, 0)
	end
	for _, element in ipairs(ELEMENTS) do
		local bound = st.elements[element.name]
		if bound then element.show(st, bound.region, bound.options, mode) end
	end
	for _, entry in ipairs(st.dispelTextures) do
		showDispelTexture(st, entry)
	end
	for _, step in ipairs(Button.beforeVisibility) do
		step(button, st, mode)
	end
	local wasShown = button:IsShown()
	button:SetShown(aura ~= nil)
	for _, step in ipairs(Button.afterVisibility) do
		step(button, st, wasShown)
	end
end

repaint = function(button)
	local st = states[button]
	show(button, st.unit, st.aura, UPDATE)
end

------------------------------------------------------------------ tooltip, click

local function tooltipAllowed(st)
	return not (st.tooltipHideInCombat and UnitAffectingCombat("player"))
end

local function fillTooltip(tooltip, button)
	local st = states[button]
	local aura = st.aura
	if aura == nil or not tooltipAllowed(st) then return false end
	if aura.auraType == ENCHANT then
		tooltip:SetInventoryItem("player", aura.inventorySlot)
	else
		tooltip:SetUnitAuraByAuraInstanceID(st.unit, aura.auraInstanceID)
	end
	return true
end

local BUILTIN = {
	OnEnter = function(button)
		local st = states[button]
		if st.aura ~= nil and tooltipAllowed(st) then
			Private.Tooltip.Show(button, st.tooltipPoint, st.tooltipX, st.tooltipY, fillTooltip)
		end
	end,
	OnLeave = function(button)
		Private.Tooltip.Hide(button)
	end,
}

-- One dispatcher per script, shared by all buttons: ours first, then the consumer's.
local DISPATCH = {}
for scriptName, handler in pairs(BUILTIN) do
	DISPATCH[scriptName] = function(button, ...)
		handler(button, ...)
		local consumer = states[button].consumerScripts[scriptName]
		if consumer then consumer(button, ...) end
	end
end

------------------------------------------------------------------ public methods

local methods = {}
Button.methods = methods

local function defineElement(element)
	local name = element.name
	local setter = "Set" .. name

	methods["Get" .. name] = function(self)
		local b = states[self].elements[name]
		if b then
			if element.dropOptions then return b.region end
			return b.region, copyValue(b.options)
		end
	end

	methods[setter] = function(self, region, options)
		local st = states[self]
		local ok, reason = checkRegion(self, region, element.widget)
		if not ok then reject(setter, reason) end
		local o
		if element.schema then
			ok, o = readOptions(element.schema, options)
			if not ok then reject(setter, o) end
		end
		st.elements[name] = { region = region, options = o }
		if element.bind then element.bind(st, region, o) end
		element.show(st, region, o, UPDATE)
	end

	methods["Clear" .. name] = function(self)
		local st = states[self]
		if element.unbind then element.unbind(st) end
		st.elements[name] = nil
	end
end

for _, element in ipairs(ELEMENTS) do
	defineElement(element)
end

function Button.DefineElement(element)
	ELEMENTS[#ELEMENTS + 1] = element
	defineElement(element)
end

function methods:GetDispelTypeTextureCount()
	return #states[self].dispelTextures
end

function methods:GetDispelTypeTexture(index)
	local entry = states[self].dispelTextures[index]
	if entry then return entry.region, copyValue(entry.options) end
end

-- Checks the arguments for `method` (errors at its caller), then appends the
-- texture, after dropping every other one when `replace` is set, and
-- returns its index.
local function addDispelTexture(self, texture, options, method, replace)
	local st = states[self]
	local ok, reason = checkRegion(self, texture, "Texture")
	if not ok then reject(method, reason, 1) end
	local o
	ok, o = readOptions(DISPEL_TEXTURE, options)
	if not ok then reject(method, o, 1) end
	if replace then st.dispelTextures = {} end
	local list = st.dispelTextures
	local entry = { region = texture, options = o }
	list[#list + 1] = entry
	showDispelTexture(st, entry)
	return #list
end

-- Returns the new entry's index; the same texture may be added twice.
function methods:AddDispelTypeTexture(texture, options)
	local index = addDispelTexture(self, texture, options, "AddDispelTypeTexture")
	return index
end

-- An index removes that entry, a texture its first occurrence.
function methods:RemoveDispelTypeTexture(textureOrIndex)
	local list = states[self].dispelTextures
	local at
	if type(textureOrIndex) == "number" then
		if list[textureOrIndex] then at = textureOrIndex end
	else
		for i, entry in ipairs(list) do
			if entry.region == textureOrIndex then
				at = i
				break
			end
		end
	end
	if at then table.remove(list, at) end
end

function methods:ClearDispelTypeTextures()
	states[self].dispelTextures = {}
end

-- Classic cannot cancel from an addon button (CancelUnitBuff and
-- CancelItemTempEnchantment are protected there), so the argument is only
-- checked as retail checks it; no click is registered, nothing is kept.
function methods:SetCancelAuraButtons(cancelAuraButtons)
	if cancelAuraButtons == nil then return end
	if type(cancelAuraButtons) ~= "string" then
		reject("SetCancelAuraButtons", "expected a string or nil, got " .. type(cancelAuraButtons))
	end
	if not cancelAuraButtons:find("[^,%s]") then
		reject("SetCancelAuraButtons", "no click token in " .. string.format("%q", cancelAuraButtons))
	end
end

local TOOLTIP_ANCHORS = {}
for _, point in ipairs({
	"ANCHOR_LEFT", "ANCHOR_RIGHT", "ANCHOR_BOTTOMLEFT", "ANCHOR_BOTTOM", "ANCHOR_BOTTOMRIGHT",
	"ANCHOR_TOPLEFT", "ANCHOR_TOP", "ANCHOR_TOPRIGHT", "ANCHOR_CURSOR", "ANCHOR_NONE",
	"ANCHOR_PRESERVE", "ANCHOR_CURSOR_LEFT", "ANCHOR_CURSOR_RIGHT",
}) do
	TOOLTIP_ANCHORS[point] = true
end

function methods:GetTooltipAnchorPoint()
	local st = states[self]
	return st.tooltipPoint, st.tooltipX, st.tooltipY
end

function methods:SetTooltipAnchorPoint(point, offsetX, offsetY)
	if not TOOLTIP_ANCHORS[point] then reject("SetTooltipAnchorPoint", "not a tooltip anchor: " .. tostring(point)) end
	for _, offset in ipairs({ offsetX or 0, offsetY or 0 }) do
		if type(offset) ~= "number" then reject("SetTooltipAnchorPoint", "offsets must be numbers or nil") end
	end
	local st = states[self]
	st.tooltipPoint, st.tooltipX, st.tooltipY = point, offsetX or 0, offsetY or 0
end

function methods:ShouldHideTooltipInCombat()
	return states[self].tooltipHideInCombat
end

function methods:SetHideTooltipInCombat(hideInCombat)
	states[self].tooltipHideInCombat = hideInCombat == true
end

-- The built-in scripts stay installed; a consumer's handler is kept aside.
function methods:SetScript(scriptName, handler)
	local st = states[self]
	if BUILTIN[scriptName] then
		if handler ~= nil and type(handler) ~= "function" then
			reject("SetScript", "handler must be a function or nil")
		end
		st.consumerScripts[scriptName] = handler
		return
	end
	return st.frameSetScript(self, scriptName, handler)
end

function methods:GetScript(scriptName)
	local st = states[self]
	if BUILTIN[scriptName] then return st.consumerScripts[scriptName] end
	return st.frameGetScript(self, scriptName)
end

------------------------------------------------------------------ seam, internal API

Button.onNew = {}
Button.kit = {
	states = states, checkRegion = checkRegion, descendsFrom = descendsFrom, reject = reject,
	readOptions = readOptions, boolean = boolean, addDispelTexture = addDispelTexture,
	-- option checkers, also used by the tooltip style setters (Emulated/Tooltip.lua)
	number = number, text = text, asset = asset, record = record, clientEnum = clientEnum,
}

function Button.New(container, templates, initialize, clock)
	local button = CreateFrame("Button", nil, container, templates)
	local st = {
		button = button, elements = {}, dispelTextures = {}, consumerScripts = {}, clock = clock,
		duration = C_DurationUtil.CreateDuration(),
		binding = C_DurationUtil.CreateDurationTextBinding(),
		tooltipPoint = "ANCHOR_BOTTOMLEFT", tooltipX = 0, tooltipY = 0, tooltipHideInCombat = false,
		frameSetScript = button.SetScript, frameGetScript = button.GetScript,
	}
	states[button] = st
	for _, fill in ipairs(Button.onNew) do fill(st) end
	for scriptName, dispatcher in pairs(DISPATCH) do
		st.consumerScripts[scriptName] = button:GetScript(scriptName)
		st.frameSetScript(button, scriptName, dispatcher)
	end
	for methodName, fn in pairs(methods) do
		button[methodName] = fn
	end
	button:RegisterForClicks()
	if initialize then
		-- The handler runs inside the failing call, so it sees the consumer's stack.
		xpcall(function() initialize(button) end, geterrorhandler())
	end
	show(button, nil, nil, ASSIGNMENT)
	return button
end

function Button.Assign(button, unit, aura)
	show(button, unit, aura, ASSIGNMENT)
end

function Button.Update(button, aura)
	show(button, states[button].unit, aura, UPDATE)
end

-- Repaints the button empty and hides it; harmless on a button that holds nothing.
function Button.Clear(button)
	show(button, nil, nil, ASSIGNMENT)
end

function Button.GetAura(button)
	local st = states[button]
	return st.unit, st.aura
end
