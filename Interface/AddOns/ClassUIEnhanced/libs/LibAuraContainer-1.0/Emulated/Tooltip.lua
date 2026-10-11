--[[ LibAuraContainer-1.0: Emulated/Tooltip

The library's own tooltip frame, LibAuraContainer1Tooltip (a GameTooltipTemplate
frame parented to UIParent), and its style setters. Buttons never use the shared
GameTooltip. Created on first need, then kept for the session.

INTERFACE (Private.Tooltip)

  Tooltip.Show(owner, anchorPoint, offsetX, offsetY, fill)
      Takes the tooltip for `owner` (SetOwner with the anchor) and calls
      fill(tooltip, owner) at once and again every TOOLTIP_UPDATE_TIME seconds
      while the tooltip is shown and still owned by `owner`. fill writes the
      content and returns true, or returns false to hide the tooltip.
  Tooltip.Hide(owner)
      Hides the tooltip if `owner` was the last one to take it.
  Tooltip.GetFrame() -> frame
      The tooltip frame, created if needed (for the tooltip style setters).

  LAC.Inbound.SetTooltipNineSlice(options), SetTooltipTextureSlice(options),
  SetTooltipBackdrop(options), ResetTooltipStyle()
      Options are checked with the button's option checkers
      (Button.kit, so this file loads after Emulated/Button.lua) before the
      frame is touched.

STYLE
  The tooltip wears one of three looks, each a region anchored over the frame:
  the template's NineSlice, a slice texture, or a BackdropTemplate holder
  frame (the last two made on first use). Choosing a look first resets every
  look that exists to neutral (white colours, no texture or backdrop, no
  anchors, hidden), then anchors, dresses and shows the chosen one.

State lives in Private.tooltip (frame, owner, fill, untilRefresh, slice,
backdrop) so a newer copy of the library adopts what an older copy created;
the frame's OnUpdate always calls the active copy's Tooltip.Tick.
]]

local Private = LibStub("LibAuraContainer-1.0-Private")
if not Private.loading or Private.LAC.IsNative then return end

local LAC = Private.LAC

local Tooltip = {}
Private.Tooltip = Tooltip

local FRAME_NAME = "LibAuraContainer1Tooltip"
local DEFAULT_REFRESH = 0.2

-- frame, owner, fill, untilRefresh, slice, backdrop
Private.tooltip = Private.tooltip or {}
local current = Private.tooltip

local function refreshInterval()
	return TOOLTIP_UPDATE_TIME or DEFAULT_REFRESH
end

local function tick(frame, elapsed)
	Private.Tooltip.Tick(frame, elapsed)
end

function Tooltip.GetFrame()
	local frame = current.frame
	if not frame then
		frame = CreateFrame("GameTooltip", FRAME_NAME, UIParent, "GameTooltipTemplate")
		frame:SetFrameStrata("TOOLTIP")
		frame:Hide()
		frame:SetScript("OnUpdate", tick)
		current.frame = frame
	end
	return frame
end

function Tooltip.Tick(frame, elapsed)
	current.untilRefresh = (current.untilRefresh or 0) - elapsed
	if current.untilRefresh > 0 then return end
	current.untilRefresh = refreshInterval()
	local owner = current.owner
	if owner and frame:IsOwned(owner) and not current.fill(frame, owner) then
		frame:Hide()
	end
end

function Tooltip.Show(owner, anchorPoint, offsetX, offsetY, fill)
	local frame = Tooltip.GetFrame()
	frame:SetOwner(owner, anchorPoint, offsetX, offsetY)
	current.owner, current.fill, current.untilRefresh = owner, fill, refreshInterval()
	if not fill(frame, owner) then frame:Hide() end
end

function Tooltip.Hide(owner)
	if current.owner ~= owner then return end
	current.owner, current.fill = nil, nil
	current.frame:Hide()
end

------------------------------------------------------------------ style

local kit = Private.Button.kit
local readOptions, record, reject = kit.readOptions, kit.record, kit.reject
local number, text, asset, boolean = kit.number, kit.text, kit.asset, kit.boolean

-- A colour table (a ColorMixin or plain { r, g, b [, a] }) as an { r, g, b, a } array.
local function colour(v)
	if type(v) ~= "table" then return false, "expected a colour table, got " .. type(v) end
	local alpha = v.a
	if alpha == nil then alpha = 1 end
	if type(v.r) ~= "number" or type(v.g) ~= "number" or type(v.b) ~= "number" or type(alpha) ~= "number" then
		return false, "a colour needs numbers r, g, b and optionally a"
	end
	return true, { v.r, v.g, v.b, alpha }
end

local DRAW_LAYERS = { BACKGROUND = true, BORDER = true, ARTWORK = true, OVERLAY = true, HIGHLIGHT = true }
local function drawLayer(v)
	if DRAW_LAYERS[v] then return true, v end
	return false, "not a draw layer: " .. tostring(v)
end

local function edges(default)
	local fields = {}
	for i, side in ipairs({ "left", "right", "top", "bottom" }) do
		fields[i] = { side, number, default = default, required = default == nil }
	end
	return fields
end

local OFFSETS = { "anchorOffsets", record(edges(0)), default = { left = 0, right = 0, top = 0, bottom = 0 } }

local NINE_SLICE = {
	required = true,
	{ "layoutName", text, required = true },
	{ "borderColor", colour },
	{ "centerColor", colour },
	OFFSETS,
}

local TEXTURE_SLICE = {
	required = true,
	{ "asset", asset, required = true },
	{ "sliceMargins", record(edges(nil)) },
	{ "sliceMode", kit.clientEnum("UITextureSliceMode") },
	{ "color", colour },
	{ "drawLayer", drawLayer },
	{ "drawLayerSublevel", number, default = 0 },
	OFFSETS,
}

local BACKDROP = {
	required = true,
	{ "backdropInfo", record({
		{ "bgFile", asset },
		{ "edgeFile", asset },
		{ "edgeSize", number },
		{ "insets", record(edges(0)) },
		{ "tile", boolean },
		{ "tileEdge", boolean },
		{ "tileSize", number },
	}), required = true },
	{ "borderColor", colour },
	{ "centerColor", colour },
	OFFSETS,
}

-- Each look: find(frame, make) returns its region (making it when `make` and it
-- does not exist yet, else possibly nil), neutral(region) undoes any dressing,
-- dress(region, o) applies checked options.
local NINE = {
	find = function(frame) return frame.NineSlice end,
	neutral = function(nine)
		nine:SetBorderColor(1, 1, 1, 1)
		nine:SetCenterColor(1, 1, 1, 1)
	end,
	dress = function(nine, o)
		NineSliceUtil.ApplyLayoutByName(nine, o.layoutName)
		if o.borderColor then nine:SetBorderColor(unpack(o.borderColor)) end
		if o.centerColor then nine:SetCenterColor(unpack(o.centerColor)) end
	end,
}

local SLICE = {
	find = function(frame, make)
		if make and not current.slice then current.slice = frame:CreateTexture(nil, "BACKGROUND") end
		return current.slice
	end,
	neutral = function(texture)
		texture:ClearTextureSlice()
		texture:SetTexture(nil)
		texture:SetVertexColor(1, 1, 1, 1)
		texture:SetDrawLayer("BACKGROUND", 0)
	end,
	dress = function(texture, o)
		local atlas = type(o.asset) == "string" and C_Texture and C_Texture.GetAtlasInfo(o.asset)
		if atlas then texture:SetAtlas(o.asset) else texture:SetTexture(o.asset) end
		local m = o.sliceMargins
		if m then texture:SetTextureSliceMargins(m.left, m.top, m.right, m.bottom) end
		if o.sliceMode then texture:SetTextureSliceMode(o.sliceMode) end
		if o.color then texture:SetVertexColor(unpack(o.color)) end
		if o.drawLayer then texture:SetDrawLayer(o.drawLayer, o.drawLayerSublevel) end
	end,
}

local BACKDROP_LOOK = {
	find = function(frame, make)
		if make and not current.backdrop then
			local holder = CreateFrame("Frame", nil, frame, "BackdropTemplate")
			holder:SetUsingParentLevel(true)
			current.backdrop = holder
		end
		return current.backdrop
	end,
	neutral = function(holder)
		holder:ClearBackdrop()
		holder:SetBackdropColor(1, 1, 1, 1)
		holder:SetBackdropBorderColor(1, 1, 1, 1)
	end,
	dress = function(holder, o)
		holder:SetBackdrop(o.backdropInfo) -- before the colours, which it would reset
		if o.borderColor then holder:SetBackdropBorderColor(unpack(o.borderColor)) end
		if o.centerColor then holder:SetBackdropColor(unpack(o.centerColor)) end
	end,
}

local LOOKS = { NINE, SLICE, BACKDROP_LOOK }

local function wear(look, o)
	local frame = Tooltip.GetFrame()
	for _, other in ipairs(LOOKS) do
		local region = other.find(frame, false)
		if region then
			other.neutral(region)
			region:ClearAllPoints()
			region:Hide()
		end
	end
	local region = look.find(frame, true)
	local offsets = o.anchorOffsets
	region:SetPoint("TOPLEFT", frame, "TOPLEFT", offsets.left, offsets.top)
	region:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", offsets.right, offsets.bottom)
	look.dress(region, o)
	region:Show()
end

local Inbound = LAC.Inbound

function Inbound.SetTooltipNineSlice(options)
	local ok, o = readOptions(NINE_SLICE, options)
	if not ok then reject("SetTooltipNineSlice", o) end
	wear(NINE, o)
end

function Inbound.SetTooltipTextureSlice(options)
	local ok, o = readOptions(TEXTURE_SLICE, options)
	if not ok then reject("SetTooltipTextureSlice", o) end
	wear(SLICE, o)
end

function Inbound.SetTooltipBackdrop(options)
	local ok, o = readOptions(BACKDROP, options)
	if not ok then reject("SetTooltipBackdrop", o) end
	if o.backdropInfo.bgFile == nil and o.backdropInfo.edgeFile == nil then
		reject("SetTooltipBackdrop", "options.backdropInfo needs bgFile or edgeFile")
	end
	wear(BACKDROP_LOOK, o)
end

function Inbound.ResetTooltipStyle()
	Inbound.SetTooltipNineSlice({ layoutName = "TooltipDefaultLayout", centerColor = TOOLTIP_DEFAULT_BACKGROUND_COLOR })
end
