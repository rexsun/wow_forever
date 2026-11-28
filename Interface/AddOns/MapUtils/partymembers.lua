local _, MapUtils = ...
local MAX_PARTY = 4
local DOT_SIZE = 22
local UPDATE_INTERVAL = 0.1
local STACK_RADIUS_SQ = 324
local MASK_TEX = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local CROWN_ATLAS = "UI-HUD-UnitFrame-Player-Group-LeaderIcon"
local CROWN_TEX = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local DEAD_MARK = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local TAXI_HORDE = 132268
local TAXI_ALLIANCE = 132239
local FALLBACK_COLOR = {r = 0.45, g = 0.72, b = 1}
local GHOST_COLOR = {r = 0.55, g = 0.55, b = 0.55}
local OFF_COLOR = {r = 0.5, g = 0.5, b = 0.5}
local RACE_ALIASES = {
	["scourge"] = "undead",
	["highmountaintauren"] = "highmountain",
	["lightforgeddraenei"] = "lightforged",
	["zandalaritroll"] = "zandalari",
	["harronir"] = "haranir",
	["earthendwarf"] = "earthen",
}

local Party = {
	["pins"] = {},
	["rects"] = {},
	["entries"] = {},
	["elapsed"] = 0,
	["dirty"] = true,
	["lastMapID"] = nil,
	["lastScale"] = nil,
	["lastWidth"] = nil,
}

MapUtils.PartyMembers = Party

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) == true
end

local function HasAtlas(name)
	return name ~= nil and C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(name) ~= nil
end

local function GetCrownMarkup()
	if CreateAtlasMarkup ~= nil and HasAtlas(CROWN_ATLAS) then
		return CreateAtlasMarkup(CROWN_ATLAS, 14, 14)
	end
	return "|T" .. CROWN_TEX .. ":14:14|t"
end

local function GetClassColor(class)
	if type(class) == "string" and class ~= "" then
		if MapUtils.GetClassColor ~= nil then
			local r, g, b = MapUtils:GetClassColor(class)
			if r ~= nil and g ~= nil and b ~= nil then return {r = r, g = g, b = b} end
		end
		local tab = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
		local c = tab ~= nil and tab[class] or nil
		if c ~= nil then return {r = c.r or 1, g = c.g or 1, b = c.b or 1} end
	end
	return FALLBACK_COLOR
end

local function GetRaceAtlas(race, sex)
	if type(race) ~= "string" or race == "" then return nil end
	local r = strlower(race)
	local gender = sex == 3 and "female" or "male"
	local alias = RACE_ALIASES[r]
	local candidates = alias ~= nil and {r, alias} or {r}
	for i = 1, #candidates do
		local suffix = candidates[i] .. "-" .. gender
		local a128 = "raceicon128-" .. suffix
		if HasAtlas(a128) then return a128 end
		local a64 = "raceicon-" .. suffix
		if HasAtlas(a64) then return a64 end
	end
	return nil
end

local function GetTaxiIcon(faction)
	if faction == "Horde" then return TAXI_HORDE end
	if faction == "Alliance" then return TAXI_ALLIANCE end
	if UnitFactionGroup ~= nil then
		local pf = UnitFactionGroup("player")
		if pf == "Horde" then return TAXI_HORDE end
		if pf == "Alliance" then return TAXI_ALLIANCE end
	end
	return nil
end

function MapUtils:GetPartyMemberInfo(unit, out)
	local info = out or {}
	local name = UnitName ~= nil and UnitName(unit) or unit
	if IsSecret(name) or type(name) ~= "string" or name == "" then name = unit end
	local class = nil
	if UnitClass ~= nil then
		local _, c = UnitClass(unit)
		if not IsSecret(c) and type(c) == "string" then class = c end
	end
	local race = nil
	if UnitRace ~= nil then
		local _, r = UnitRace(unit)
		if not IsSecret(r) and type(r) == "string" then race = r end
	end
	local sex = nil
	if UnitSex ~= nil then
		local s = UnitSex(unit)
		if not IsSecret(s) and type(s) == "number" then sex = s end
	end
	local faction = nil
	if UnitFactionGroup ~= nil then
		local f = UnitFactionGroup(unit)
		if not IsSecret(f) and type(f) == "string" then faction = f end
	end
	local level = nil
	if UnitLevel ~= nil then
		local lv = UnitLevel(unit)
		if not IsSecret(lv) and type(lv) == "number" and lv > 0 then level = lv end
	end
	local taxi = false
	if UnitOnTaxi ~= nil then
		local t = UnitOnTaxi(unit)
		if not IsSecret(t) and (t == true or t == 1) then taxi = true end
	end
	local ghost = false
	if UnitIsGhost ~= nil then
		local g = UnitIsGhost(unit)
		if not IsSecret(g) and (g == true or g == 1) then ghost = true end
	end
	local dead = false
	if UnitIsDeadOrGhost ~= nil then
		local d = UnitIsDeadOrGhost(unit)
		if not IsSecret(d) and (d == true or d == 1) then dead = true end
	elseif UnitIsDead ~= nil then
		local d = UnitIsDead(unit)
		if not IsSecret(d) and (d == true or d == 1) then dead = true end
	end
	local leader = false
	if UnitIsGroupLeader ~= nil then
		local l = UnitIsGroupLeader(unit)
		if not IsSecret(l) and (l == true or l == 1) then leader = true end
	end
	local connected = true
	if UnitIsConnected ~= nil then
		local cn = UnitIsConnected(unit)
		if not IsSecret(cn) and cn == false then connected = false end
	end
	info.unit = unit
	info.name = name
	info.class = class
	info.color = GetClassColor(class)
	info.race = race
	info.sex = sex
	info.faction = faction
	info.level = level
	info.taxi = taxi
	info.ghost = ghost
	info.dead = dead and not ghost
	info.leader = leader
	info.connected = connected
	return info
end

function MapUtils:CreatePartyPin(parent, size)
	local sz = size or DOT_SIZE
	local pin = CreateFrame("Frame", nil, parent)
	pin:SetSize(sz, sz)
	pin.outer = pin:CreateTexture(nil, "BACKGROUND", nil, 0)
	pin.outer:SetAllPoints(pin)
	pin.outer:SetTexture(MASK_TEX)
	pin.outer:SetVertexColor(0, 0, 0, 0.92)
	pin.ring = pin:CreateTexture(nil, "BACKGROUND", nil, 1)
	pin.ring:SetTexture(MASK_TEX)
	pin.innerBg = pin:CreateTexture(nil, "BORDER", nil, 0)
	pin.innerBg:SetTexture(MASK_TEX)
	pin.innerBg:SetVertexColor(0.06, 0.06, 0.08, 1)
	pin.mask = pin:CreateMaskTexture()
	pin.mask:SetTexture(MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	pin.mask:SetAllPoints(pin.innerBg)
	pin.portrait = pin:CreateTexture(nil, "ARTWORK", nil, 0)
	pin.portrait:SetAllPoints(pin.innerBg)
	pin.portrait:AddMaskTexture(pin.mask)
	pin.portrait:Hide()
	pin.icon = pin:CreateTexture(nil, "ARTWORK", nil, 0)
	pin.icon:AddMaskTexture(pin.mask)
	pin.icon:Hide()
	pin.fallback = pin:CreateTexture(nil, "ARTWORK", nil, 0)
	pin.fallback:SetAllPoints(pin.innerBg)
	pin.fallback:SetTexture(MASK_TEX)
	pin.fallback:AddMaskTexture(pin.mask)
	pin.fallback:Hide()
	pin.deadMark = pin:CreateTexture(nil, "OVERLAY", nil, 1)
	pin.deadMark:SetTexture(DEAD_MARK)
	pin.deadMark:Hide()
	pin.crown = pin:CreateTexture(nil, "OVERLAY", nil, 2)
	if pin.crown.SetAtlas ~= nil and HasAtlas(CROWN_ATLAS) then
		pin.crown:SetAtlas(CROWN_ATLAS)
	else
		pin.crown:SetTexture(CROWN_TEX)
	end
	pin.crown:Hide()
	return pin
end

function MapUtils:ApplyPartyPin(pin, info, size, scale)
	if pin == nil or info == nil then return end
	local sc = (scale ~= nil and scale > 0) and scale or 1
	local baseSize = size or DOT_SIZE
	local sz = baseSize / sc
	local ringInset = math.max(1, baseSize * 0.055) / sc
	local innerInset = math.max(2.6, baseSize * 0.16) / sc
	local iconPad = math.max(0.8, (baseSize - baseSize * 0.32) * 0.085) / sc
	local crownSize = (baseSize * 0.58) / sc
	local crownOverlap = (baseSize * 0.24) / sc

	if pin._muSize ~= sz then
		pin._muSize = sz
		pin:SetSize(sz, sz)
		pin.ring:ClearAllPoints()
		pin.ring:SetPoint("TOPLEFT", pin, "TOPLEFT", ringInset, -ringInset)
		pin.ring:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -ringInset, ringInset)
		pin.innerBg:ClearAllPoints()
		pin.innerBg:SetPoint("TOPLEFT", pin, "TOPLEFT", innerInset, -innerInset)
		pin.innerBg:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -innerInset, innerInset)
		pin.icon:ClearAllPoints()
		pin.icon:SetPoint("TOPLEFT", pin.innerBg, "TOPLEFT", -iconPad, iconPad)
		pin.icon:SetPoint("BOTTOMRIGHT", pin.innerBg, "BOTTOMRIGHT", iconPad, -iconPad)
		local markInset = math.max(1, baseSize * 0.05) / sc
		pin.deadMark:ClearAllPoints()
		pin.deadMark:SetPoint("TOPLEFT", pin.innerBg, "TOPLEFT", markInset, -markInset)
		pin.deadMark:SetPoint("BOTTOMRIGHT", pin.innerBg, "BOTTOMRIGHT", -markInset, markInset)
		pin.crown:SetSize(crownSize, crownSize)
		pin.crown:ClearAllPoints()
		pin.crown:SetPoint("BOTTOM", pin, "TOP", 0, -crownOverlap)
	end

	local color = info.color or GetClassColor(info.class)
	local isGhost = info.ghost == true
	local isDead = info.dead == true and not isGhost
	local ringColor = color
	if info.known == false or info.connected == false then
		ringColor = OFF_COLOR
	elseif isGhost then
		ringColor = GHOST_COLOR
	end
	pin.ring:SetVertexColor(ringColor.r, ringColor.g, ringColor.b, 1)

	local taxiIcon = info.taxi and GetTaxiIcon(info.faction) or nil
	if taxiIcon ~= nil then
		if pin._muTex ~= taxiIcon then
			pin._muTex = taxiIcon
			pin.icon:SetTexture(taxiIcon)
		end
		if pin.icon.SetDesaturated ~= nil then pin.icon:SetDesaturated(false) end
		pin.icon:SetVertexColor(1, 1, 1, 1)
		pin.icon:Show()
		pin.portrait:Hide()
		pin.fallback:Hide()
		pin.deadMark:Hide()
	else
		local atlas = GetRaceAtlas(info.race, info.sex)
		if atlas ~= nil and pin.portrait.SetAtlas ~= nil then
			if pin._muAtlas ~= atlas then
				pin._muAtlas = atlas
				pcall(pin.portrait.SetAtlas, pin.portrait, atlas)
			end
			if pin.portrait.SetDesaturated ~= nil then pin.portrait:SetDesaturated(isGhost or isDead) end
			if isGhost then
				pin.portrait:SetVertexColor(0.75, 0.75, 0.75, 1)
			elseif isDead then
				pin.portrait:SetVertexColor(0.65, 0.65, 0.65, 1)
			else
				pin.portrait:SetVertexColor(1, 1, 1, 1)
			end
			pin.portrait:Show()
			pin.icon:Hide()
			pin.fallback:Hide()
		else
			local fc = isGhost and GHOST_COLOR or color
			pin.fallback:SetVertexColor(fc.r, fc.g, fc.b, isDead and 0.65 or 1)
			pin.fallback:Show()
			pin.portrait:Hide()
			pin.icon:Hide()
		end
		pin.deadMark:SetShown(isDead)
	end

	pin.crown:SetShown(info.leader == true)
end

local function GetRect(sourceID, targetID)
	if C_Map == nil or C_Map.GetMapRectOnMap == nil then return nil end
	local key = sourceID .. ":" .. targetID
	local cached = Party.rects[key]
	if cached ~= nil then return cached or nil end
	local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(sourceID, targetID)
	if minX == nil or maxX == nil or minY == nil or maxY == nil or minX == maxX or minY == maxY then
		Party.rects[key] = false
		return nil
	end
	local rect = {minX, maxX, minY, maxY}
	Party.rects[key] = rect
	return rect
end

local function ProjectToTarget(sourceID, targetID, x, y)
	if sourceID == nil or targetID == nil or x == nil or y == nil then return nil, nil end
	if sourceID == targetID then return x, y end
	local direct = GetRect(sourceID, targetID)
	if direct ~= nil then
		return direct[1] + x * (direct[2] - direct[1]), direct[3] + y * (direct[4] - direct[3])
	end
	local curID = sourceID
	local cx, cy = x, y
	for _ = 1, 8 do
		if curID == targetID then return cx, cy end
		local mapInfo = C_Map.GetMapInfo ~= nil and C_Map.GetMapInfo(curID) or nil
		local parentID = mapInfo and mapInfo.parentMapID
		if parentID == nil or parentID == 0 or parentID == curID then break end
		local rect = GetRect(curID, parentID)
		if rect == nil then break end
		cx = rect[1] + cx * (rect[2] - rect[1])
		cy = rect[3] + cy * (rect[4] - rect[3])
		curID = parentID
		if curID == targetID then return cx, cy end
		local inv = GetRect(targetID, curID)
		if inv ~= nil then
			return (cx - inv[1]) / (inv[2] - inv[1]), (cy - inv[3]) / (inv[4] - inv[3])
		end
	end
	return nil, nil
end

local function GetProjectedUnitPos(unit, targetMapID)
	local srcMapID, sx, sy = MapUtils:GetUnitMapPosition(unit)
	if srcMapID ~= nil then
		local px, py = ProjectToTarget(srcMapID, targetMapID, sx, sy)
		if px ~= nil and py ~= nil then return px, py, srcMapID end
	end
	if C_Map ~= nil and C_Map.GetPlayerMapPosition ~= nil then
		local pos = C_Map.GetPlayerMapPosition(targetMapID, unit)
		if pos ~= nil then
			local px, py = pos:GetXY()
			if px ~= nil and py ~= nil and not IsSecret(px) and not IsSecret(py) and (px ~= 0 or py ~= 0) then
				return px, py, srcMapID or targetMapID
			end
		end
	end
	return nil, nil, nil
end

local function IsEnabledForMap(mapID)
	if mapID == nil then return false end
	if MapUtils.IsInstanceMapShown ~= nil and MapUtils:IsInstanceMapShown() then return false end
	if MapUtils.ArePinsHidden ~= nil and MapUtils:ArePinsHidden() then return false end
	if MapUtils.IsPinCategoryEnabled ~= nil and not MapUtils:IsPinCategoryEnabled("PARTYMEMBERPINS") then return false end
	if MapUtils.GetPinScopeShown ~= nil and MapUtils.IsPinScopeAzeroth ~= nil then
		return MapUtils:GetPinScopeShown("PARTYMEMBERPINS", true, MapUtils:IsPinScopeAzeroth(mapID))
	end
	return MapUtils:GetConfig("PARTYMEMBERPINS", true) ~= false
end

local function GetPinLevel(canvas)
	if not InCombatLockdown() and WorldMapFrame ~= nil and WorldMapFrame.GetPinFrameLevelsManager ~= nil then
		local manager = WorldMapFrame:GetPinFrameLevelsManager()
		if manager ~= nil and manager.GetValidFrameLevel ~= nil then
			local ok, level = pcall(manager.GetValidFrameLevel, manager, "PIN_FRAME_LEVEL_GROUP_MEMBER")
			if ok and type(level) == "number" then return level + 2 end
		end
	end
	return canvas:GetFrameLevel() + 35
end

local function AddTooltipMember(info, isFirst)
	local c = info.color or FALLBACK_COLOR
	local title = info.name or info.unit
	if info.leader then title = GetCrownMarkup() .. " " .. title end
	if isFirst then
		GameTooltip:SetText(title, c.r, c.g, c.b)
	else
		GameTooltip:AddLine(" ", 1, 1, 1)
		GameTooltip:AddLine(title, c.r, c.g, c.b)
	end
	if info.level ~= nil then
		GameTooltip:AddLine(format("%s %d", LEVEL or "Level", info.level), 1, 1, 1)
	end
	if info.taxi then
		GameTooltip:AddLine(MapUtils:Trans("LID_ONTAXIFLIGHT"), 1, 0.82, 0)
	elseif info.ghost then
		GameTooltip:AddLine(MapUtils:Trans("LID_GHOST"), 0.72, 0.72, 0.72)
	elseif info.dead then
		GameTooltip:AddLine(DEAD or "Dead", 1, 0.25, 0.25)
	end
	if info.mapID ~= nil and C_Map ~= nil and C_Map.GetMapInfo ~= nil then
		local mapInfo = C_Map.GetMapInfo(info.mapID)
		if mapInfo ~= nil and mapInfo.name ~= nil then
			GameTooltip:AddLine(mapInfo.name, 0.85, 0.85, 0.85)
		end
	end
end

local function OnPinEnter(pin)
	if GameTooltip == nil or pin == nil or pin.member == nil then return end
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	AddTooltipMember(pin.member, true)
	local px = pin._muX
	local py = pin._muY
	local sc = pin._muCanvasScale or 1
	if px ~= nil and py ~= nil then
		local limit = STACK_RADIUS_SQ / (sc * sc)
		for i = 1, #Party.pins do
			local other = Party.pins[i]
			if other ~= nil and other ~= pin and other:IsShown() and other.member ~= nil and other._muX ~= nil and other._muY ~= nil then
				local dx = other._muX - px
				local dy = other._muY - py
				if (dx * dx + dy * dy) <= limit then
					AddTooltipMember(other.member, false)
				end
			end
		end
	end
	GameTooltip:Show()
end

local function OnPinLeave(pin)
	if GameTooltip ~= nil and GameTooltip:IsOwned(pin) then GameTooltip:Hide() end
end

local function AcquireMapPin(canvas, index)
	local pin = Party.pins[index]
	if pin ~= nil then return pin end
	pin = MapUtils:CreatePartyPin(canvas, DOT_SIZE)
	pin:EnableMouse(true)
	if pin.SetMouseClickEnabled ~= nil then pcall(pin.SetMouseClickEnabled, pin, false) end
	pin:SetScript("OnEnter", OnPinEnter)
	pin:SetScript("OnLeave", OnPinLeave)
	pin:SetScript("OnHide", OnPinLeave)
	pin:Hide()
	Party.pins[index] = pin
	return pin
end

function Party.HidePins()
	for i = 1, #Party.pins do
		local pin = Party.pins[i]
		if pin ~= nil and pin:IsShown() then pin:Hide() end
	end
end

function Party.UpdatePins()
	if WorldMapFrame == nil or not WorldMapFrame:IsShown() then
		Party.HidePins()
		return
	end
	if IsInRaid ~= nil and IsInRaid() then
		Party.HidePins()
		return
	end
	local canvas = WorldMapFrame.GetCanvas ~= nil and WorldMapFrame:GetCanvas() or nil
	local mapID = WorldMapFrame.GetMapID ~= nil and WorldMapFrame:GetMapID() or nil
	if canvas == nil or mapID == nil or not IsEnabledForMap(mapID) then
		Party.HidePins()
		return
	end
	local scale = MapUtils.GetCanvasScale ~= nil and MapUtils:GetCanvasScale() or canvas:GetScale()
	local width = canvas:GetWidth() or 0
	local height = canvas:GetHeight() or 0
	if scale == nil or scale <= 0 or width <= 0 or height <= 0 then
		Party.HidePins()
		return
	end

	local oneMap = MapUtils.IsOneMap ~= nil and MapUtils.IsZoneDetailMap ~= nil and MapUtils:IsOneMap() and MapUtils:IsZoneDetailMap(mapID)
	local low = oneMap and -50 or 0
	local high = oneMap and 51 or 1
	local level = GetPinLevel(canvas)
	local count = 0

	for i = 1, MAX_PARTY do
		local unit = "party" .. i
		if UnitExists ~= nil and UnitExists(unit) then
			local px, py, srcMapID = GetProjectedUnitPos(unit, mapID)
			if px ~= nil and py ~= nil and px >= low and px <= high and py >= low and py <= high then
				count = count + 1
				local info = MapUtils:GetPartyMemberInfo(unit, Party.entries[count])
				Party.entries[count] = info
				info.mapID = srcMapID
				info.known = true
				local pin = AcquireMapPin(canvas, count)
				pin.member = info
				if pin:GetFrameLevel() ~= level then pin:SetFrameLevel(level) end
				MapUtils:ApplyPartyPin(pin, info, DOT_SIZE, scale)
				if MapUtils.SetCanvasPinScale ~= nil then MapUtils:SetCanvasPinScale(pin, scale) end
				local cx = width * px
				local cy = -height * py
				pin._muX = cx
				pin._muY = cy
				pin._muCanvasScale = scale
				pin:ClearAllPoints()
				pin:SetPoint("CENTER", canvas, "TOPLEFT", cx, cy)
				if not pin:IsShown() then pin:Show() end
			end
		end
	end

	for i = count + 1, #Party.pins do
		local pin = Party.pins[i]
		if pin ~= nil and pin:IsShown() then pin:Hide() end
	end
end

function MapUtils:RefreshPartyMembers()
	Party.dirty = true
	Party.UpdatePins()
end

if WorldMapFrame ~= nil then
	if MapUtils.CanvasPinLists ~= nil then tinsert(MapUtils.CanvasPinLists, Party.pins) end
	if MapUtils.CanvasPinUpdaters ~= nil then tinsert(MapUtils.CanvasPinUpdaters, Party.UpdatePins) end
	if MapUtils.RegisterRenderLayer ~= nil then
		MapUtils:RegisterRenderLayer("Party pins", function() return Party.pins end)
	end

	local updater = CreateFrame("Frame", nil, WorldMapFrame)
	updater:SetScript("OnUpdate", MapUtils.Profile("partymembers OnUpdate", function(_, elapsed)
		Party.elapsed = Party.elapsed + elapsed
		if Party.elapsed < UPDATE_INTERVAL then return end
		Party.elapsed = 0
		Party.UpdatePins()
	end))
	WorldMapFrame:HookScript("OnShow", function()
		Party.dirty = true
		Party.elapsed = UPDATE_INTERVAL
		Party.UpdatePins()
	end)
	WorldMapFrame:HookScript("OnHide", Party.HidePins)

	local events = CreateFrame("Frame")
	for _, ev in ipairs({"GROUP_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "UNIT_FLAGS", "UNIT_AURA", "UNIT_NAME_UPDATE", "UNIT_CONNECTION"}) do
		pcall(events.RegisterEvent, events, ev)
	end
	events:SetScript("OnEvent", function()
		if WorldMapFrame:IsShown() then
			Party.dirty = true
			Party.UpdatePins()
		end
	end)
end
