local _, ns = ...
local l = ns.I18N;

local DEFAULT_RAIDHEALTHBAR_TEXTURE = 423819

function ns.InterfaceOptions_AddCategory(frame, addOn, position)
	if not Settings or not Settings.RegisterCanvasLayoutSubcategory then
		return InterfaceOptions_AddCategory(frame, addOn, position)
	end
    -- cancel is no longer a default option. May add menu extension for this.
    frame.OnCommit = frame.okay;
    frame.OnDefault = frame.default;
    frame.OnRefresh = frame.refresh;

    if frame.parent then -- for subcategories
        local category = Settings.GetCategory(frame.parent);
        local subcategory, layout = Settings.RegisterCanvasLayoutSubcategory(category, frame, frame.name, frame.name);
        subcategory.ID = frame.name;
        return subcategory, category;
    else
        local category, layout = Settings.RegisterCanvasLayoutCategory(frame, frame.name, frame.name);
        -- category.ID = frame.name;
        Settings.RegisterAddOnCategory(category);
		ns.CATEGORY_ID = category:GetID()
        return category;
    end
end

function ns.RemoveOldOptions(options)
	-- Since 11.1.501
	if  options.BuffsVertical ~= nil then
		options.BuffsOrientation = options.BuffsVertical and "UpThenLeft" or options.BuffsOrientation
		options.BuffsVertical = nil
	end
	if  options.DebuffsVertical ~= nil then
		options.DebuffsOrientation = options.DebuffsVertical and "UpThenRight" or options.DebuffsOrientation
		options.DebuffsVertical = nil
	end
end

local startsWith = {
	pla = true, -- player
	par = true, -- party
	rai = true, -- raid
	pet = true
}
local function UnitInPartyOrRaid(frame)
	return startsWith[strsub(frame.displayedUnit, 1, 3)];
	-- return UnitInParty(Unit) or UnitInRaid(Unit) or UnitIsUnit(Unit, "player")
end

local function KRF_UnitIsConnected(frame)
	if ns.IsDebugFramesTimerActive then
		return not frame._testUnitDisconnected;
	end
	return UnitIsConnected(frame.unit);
end

local function KRF_UnitIsDeadOrGhost(frame)
	if ns.IsDebugFramesTimerActive then
		return (frame._testHealthPercentage == 0 and not frame._testUnitDisconnected);
	end
	return UnitIsDeadOrGhost(frame.unit);
end

local function FrameIsCompact(frame)
	local getName = frame:GetName();
	return getName ~=nil and strsub(getName, 0, 7) == "Compact"
end

local function mergeRGBA(r1, g1, b1, a1, r2, g2, b2, a2, percent)
	return r1*(1-percent) + r2*percent, g1*(1-percent) + g2*percent, b1*(1-percent) + b2*percent, a1*(1-percent) + a2*percent
end
local function mergeColors(color1, color2, percent)
	return mergeRGBA(color1.r, color1.g, color1.b, color1.a, color2.r, color2.g, color2.b, color2.a, percent)
end
local function darken(r, g, b, percent, alpha)
	-- return r*(1-percent), g*(1-percent), b*(1-percent), alpha or 1
	return mergeRGBA(r, g, b, alpha or 1, 0, 0, 0, alpha or 1, percent)
end
local function lighten(r, g, b, percent, alpha)
	-- return r*(1-percent) + percent, g*(1-percent) + percent, b*(1-percent) + percent, alpha or 1
	return mergeRGBA(r, g, b, alpha or 1, 1, 1, 1, alpha or 1, percent)
end

local function KRF_GetClassColor(unit)
	local unitClass = select(2,UnitClass(unit))
	local classColors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
	if not unitClass or not classColors[unitClass] then
		if unit:find("pet") then
			local ownerUnit = unit:gsub("pet", "")
			if ownerUnit == "" then ownerUnit = "player" end
			unitClass = select(2,UnitClass(ownerUnit))
			if unitClass then
				return classColors[unitClass]
			end
		end
		return classColors["HUNTER"]
	end
	return classColors[unitClass]
end

ns.IsSecretValue = issecretvalue or function(_) return false end
--[[
! Managing Alpha depending on range
- Alpha not in range
- then alpha out of combat
- Disabled if alpha values are equals to blizzard default (100% / ns.DEFAULT_ALPHA_OUTOFRANGE%)
]]
function ns.Hook_UpdateInRange(frame)
	if UnitInPartyOrRaid(frame) and FrameIsCompact(frame) and not frame:IsForbidden() then
		local inRangeAlpha = InCombatLockdown() and 1 or math.min(_G[ns.OPTIONS_NAME].AlphaNotInCombat/100, 1)
		local outOfRangeAlpha = math.min(_G[ns.OPTIONS_NAME].AlphaNotInRange/100, 1)

		local isInRange = UnitInRange(frame.displayedUnit)
		if C_Spell.IsSpellInRange(1229376, frame.displayedUnit) then
		-- if UnitIsUnit(frame.displayedUnit, "player") then
			isInRange = true
		end
		-- Since Midnight (12)
		if (issecretvalue) then
			-- secret fallback (frame:GetAlpha() secret)
			frame:SetAlphaFromBoolean(isInRange, inRangeAlpha, outOfRangeAlpha)
			frame.background:SetAlphaFromBoolean(isInRange, inRangeAlpha, outOfRangeAlpha)
			return
		end

		if UnitIsUnit(frame.displayedUnit, "player") then
			isInRange = true
		end
		local newAlpha = isInRange and inRangeAlpha or outOfRangeAlpha
		if (floor(frame:GetAlpha()*100) ~= floor(newAlpha*100)) then
			frame:SetAlpha(newAlpha);
			frame.background:SetAlpha(newAlpha);
		end
	end
end

local _curveRegular, _curveRevert
-- Since Midnight (12)
local function initCurve(revert)
	local BGColorOK=revert and _G[ns.OPTIONS_NAME].RevertColorOK or _G[ns.OPTIONS_NAME].BGColorOK;
	local BGColorWarn=revert and _G[ns.OPTIONS_NAME].RevertColorWarn or _G[ns.OPTIONS_NAME].BGColorWarn;
	local BGColorLow=revert and _G[ns.OPTIONS_NAME].RevertColorLow or _G[ns.OPTIONS_NAME].BGColorLow;
	local pLimitLow = _G[ns.OPTIONS_NAME].LimitLow / 100;
	local pLimitWarn = _G[ns.OPTIONS_NAME].LimitWarn / 100;
	local pLimitOk = _G[ns.OPTIONS_NAME].LimitOk / 100;
	local curve = C_CurveUtil.CreateColorCurve();
	curve:SetType(Enum.LuaCurveType.Linear);
	curve:AddPoint(pLimitLow, CreateColor(BGColorLow.r, BGColorLow.g, BGColorLow.b, BGColorLow.a or 1));
	curve:AddPoint(pLimitWarn, CreateColor(BGColorWarn.r, BGColorWarn.g, BGColorWarn.b, BGColorWarn.a or 1));
	curve:AddPoint(pLimitOk, CreateColor(BGColorOK.r, BGColorOK.g, BGColorOK.b, BGColorOK.a or 1));
	return curve
end
local function curveRegular()
	if (not _curveRegular and C_CurveUtil) then
		_curveRegular = initCurve(false)
	end
	return _curveRegular
end
local function curveRevert()
	if (not _curveRevert and C_CurveUtil) then
		_curveRevert = initCurve(true)
	end
	return _curveRevert
end

local function GetHPSeverity(unit, percent, revert, isTest)
	local BGColorOK=revert and _G[ns.OPTIONS_NAME].RevertColorOK or _G[ns.OPTIONS_NAME].BGColorOK;
	local BGColorWarn=revert and _G[ns.OPTIONS_NAME].RevertColorWarn or _G[ns.OPTIONS_NAME].BGColorWarn;
	local BGColorLow=revert and _G[ns.OPTIONS_NAME].RevertColorLow or _G[ns.OPTIONS_NAME].BGColorLow;
	local pLimitLow = _G[ns.OPTIONS_NAME].LimitLow / 100;
	local pLimitWarn = _G[ns.OPTIONS_NAME].LimitWarn / 100;
	local pLimitOk = _G[ns.OPTIONS_NAME].LimitOk / 100;

	if curveRegular() and not isTest then
		local color = UnitHealthPercent(unit, false, revert and curveRevert() or curveRegular());
		-- if isTest then -- BUG?
		-- 	color = revert and curveRevert():Evaluate(percent) or curveRegular():Evaluate(percent)
		-- end
		return color:GetRGBA()
	end

	percent = percent / 100
	if percent > pLimitOk then
		return BGColorOK.r, BGColorOK.g, BGColorOK.b, BGColorOK.a or 1;
	elseif percent > pLimitWarn then
		return mergeColors(BGColorWarn, BGColorOK, (percent - pLimitWarn)/ (pLimitOk - pLimitWarn));
	elseif percent > pLimitLow then
		return mergeColors(BGColorLow, BGColorWarn, (percent - pLimitLow) / (pLimitWarn - pLimitLow));
	else
		return BGColorLow.r, BGColorLow.g, BGColorLow.b, BGColorLow.a or 1;
	end
end

local function applyBarTexture(frame, texture, default)
    if (texture == "") then
        if (frame._lastTexture ~= nil) then
            frame._lastTexture = nil
            frame:SetStatusBarTexture(default)
        end
        return
    end
    frame._lastTexture = texture
    frame:SetStatusBarTexture(tonumber(texture) or texture)
end

local function unitHealthValues(displayedUnit, health, isTest)
	local unitHealthMax
	local healthPercentage
	local healthLost
	if isTest then
		unitHealthMax = 100
		healthPercentage = ceil((health / unitHealthMax * 100))
		healthLost = unitHealthMax - health
	else
		health = UnitHealth(displayedUnit)
		unitHealthMax = UnitHealthMax(displayedUnit)
		-- Since Midnight (12.0)
		if (UnitHealthPercent) then
			-- healthPercentage = UnitHealthPercent(displayedUnit, nil, curve) -- FIXME only curve
			healthPercentage = GetUnitTotalModifiedMaxHealthPercent(displayedUnit)
			healthLost = UnitHealthMissing(displayedUnit)
		else
			healthPercentage = ceil((health / unitHealthMax * 100))
			healthLost = unitHealthMax - health
		end
	end
	return health, unitHealthMax, healthPercentage, healthLost
end

--- DispelOverlay can be a userdata where metatable exposes SetAlpha but the C binding rejects self ("bad self").
--- Try direct SetAlpha, then fall back to visible regions/child frames when self is truly a Frame.
---@param dispelOverlay Frame|Texture|Region|nil
---@param alpha number 0..1
local function DispelOverlay_SetAlpha(dispelOverlay, alpha)
	if not dispelOverlay then
		return
	end
	local function pack(...) return { ... } end
	local function safeGetRegions(f)
		local ok, list = pcall(function()
			return pack(f:GetRegions())
		end)
		return ok and list or {}
	end
	local function safeGetChildren(f)
		local ok, list = pcall(function()
			return pack(f:GetChildren())
		end)
		return ok and list or {}
	end
	local function try(r)
		if not r then
			return false
		end
		return pcall(function()
			r:SetAlpha(alpha)
		end)
	end
	if try(dispelOverlay) then
		return
	end
	for _, r in ipairs(safeGetRegions(dispelOverlay)) do
		try(r)
	end
	for _, child in ipairs(safeGetChildren(dispelOverlay)) do
		DispelOverlay_SetAlpha(child, alpha)
	end
end

--- Rearranges the overlay frames: heal predictions / absorb, and dispelOverlay (with alpha)
---@param frame table The main unit or group frame (CompactUnitFrame).
---@param healthBar table The health bar associated with this frame (healthBar or healthBarRevert)
---@param invert boolean Whether to invert the bar/overlay orientation
local function RearrangeOverlayFrames(frame, healthBar, invert)
	local hb = healthBar
	local hbS = hb:GetStatusBarTexture()

	local LEFT, RIGHT, deltaGlow, deltaLeft, deltaRight = "LEFT", "RIGHT", 7, 0, -8
	if invert then
		LEFT, RIGHT, deltaGlow, deltaLeft, deltaRight = "RIGHT", "LEFT", -12, 8, 0
	end

	if frame.DispelOverlay then
		local dispelOverlay = frame.DispelOverlay
		DispelOverlay_SetAlpha(dispelOverlay, _G[ns.OPTIONS_NAME].AlphaDispelOverlay / 100)

		if invert then
			local okUsing, usingParent = pcall(function()
				return dispelOverlay:IsUsingParentLevel()
			end)
			if okUsing and usingParent then
				local newFrameLevel = frame.powerBar:GetFrameLevel()+1
				pcall(function()
					dispelOverlay:SetUsingParentLevel(false)
				end)
				pcall(function()
					dispelOverlay:SetFrameLevel(newFrameLevel)
				end)
				if frame.dispelDebuffFrames then
					for _, debuffFrame in ipairs(frame.dispelDebuffFrames) do
						debuffFrame:SetFrameLevel(newFrameLevel)
					end
				end
			end
		end
	end

	local _, rel = frame.overAbsorbGlow:GetPoint(1)

	if invert or hb ~= rel then
		-- If inverted or if setting changed
		-- TODO: How to refresh only once while inverted?

		-- HealPrediction Always on the right of HealthBar
		local drawLayer = invert and "ARTWORK" or "BORDER"
		frame.myHealPrediction:ClearAllPoints();
		frame.myHealPrediction:SetPoint("TOP"..LEFT, hbS, "TOPRIGHT")
		frame.myHealPrediction:SetPoint("BOTTOM"..LEFT, hbS, "BOTTOMRIGHT")
		frame.myHealPrediction:SetDrawLayer(drawLayer, 5)

		frame.otherHealPrediction:ClearAllPoints();
		frame.otherHealPrediction:SetDrawLayer(drawLayer, 5)
		frame.otherHealPrediction:SetPoint("TOP"..LEFT, frame.myHealPrediction, "TOP"..LEFT)
		frame.otherHealPrediction:SetPoint("BOTTOM"..LEFT, frame.myHealPrediction, "BOTTOM"..LEFT)

		frame.totalAbsorb:ClearAllPoints()
		frame.totalAbsorb:SetPoint("TOP"..LEFT, frame.otherHealPrediction, "TOP"..RIGHT)
		frame.totalAbsorb:SetPoint("BOTTOM"..LEFT, frame.otherHealPrediction, "BOTTOM"..RIGHT)
		frame.totalAbsorb:SetDrawLayer(drawLayer, 5)
		frame.totalAbsorbOverlay:SetDrawLayer(drawLayer, 6)

		frame.overAbsorbGlow:ClearAllPoints()
		frame.overAbsorbGlow:SetPoint("BOTTOM"..LEFT, hb, "BOTTOM"..RIGHT, -deltaGlow, 0)
		frame.overAbsorbGlow:SetPoint("TOP"..LEFT, hb, "TOP"..RIGHT, -deltaGlow, 0)
		frame.overHealAbsorbGlow:ClearAllPoints()
		frame.overHealAbsorbGlow:SetPoint("BOTTOM"..RIGHT, hb, "BOTTOM"..LEFT, deltaGlow, 0)
		frame.overHealAbsorbGlow:SetPoint("TOP"..RIGHT, hb, "TOP"..LEFT, deltaGlow, 0)
	end
end
--[[
! Managing Health color: background
]]
local function UpdateHealth_Regular(frame, health, isTest)
	if not frame:IsForbidden() and frame.background and UnitInPartyOrRaid(frame) and FrameIsCompact(frame) then
		frame.background:SetVertexColor(1,1,1)
		local c = KRF_GetClassColor(frame.unit);
		if c and frame.optionTable.useClassColors then
			frame.healthBar:SetStatusBarColor(darken(c.r, c.g, c.b, 0, _G[ns.OPTIONS_NAME].HealthAlpha / 100))
		end
		if frame.healthBarRevert and frame.healthBarRevert:IsShown() then
			frame.healthBar:Show()
			frame.healthBarRevert:Hide()
		end
		if not KRF_UnitIsConnected(frame) then
			-- Disconnected
			frame.healthBar:SetValue(0);
			frame.background:SetColorTexture(darken(_G[ns.OPTIONS_NAME].BGColorLow.r, _G[ns.OPTIONS_NAME].BGColorLow.g, _G[ns.OPTIONS_NAME].BGColorLow.b, .6, .4));
			ns.Hook_UpdateName(frame, true);
			ns.UpdateNameRaidColor(frame);
		elseif KRF_UnitIsDeadOrGhost(frame) then
			-- Dead
			frame.healthBar:SetValue(0);
			frame._wasDead = true;
			if (_G[ns.OPTIONS_NAME].IconOnDeath) then
				ns.Hook_UpdateName(frame, true);
			end
			ns.UpdateNameRaidColor(frame);
			frame.background:SetColorTexture(darken(c.r, c.g, c.b, .7, .8));
		else
			-- Alive
			local unitHealthMax, healthPercentage, healthLost
			health, unitHealthMax, healthPercentage, healthLost = unitHealthValues(frame.displayedUnit, health, isTest)
			frame.healthBar:SetMinMaxValues(0, unitHealthMax)
			applyBarTexture(frame.healthBar, _G[ns.OPTIONS_NAME].Bar_Texture, DEFAULT_RAIDHEALTHBAR_TEXTURE)
			frame.background:SetColorTexture(GetHPSeverity(frame.displayedUnit, healthPercentage, false, isTest))
			if frame._wasDead then
				if (_G[ns.OPTIONS_NAME].IconOnDeath) then
					ns.Hook_UpdateName(frame, true);
				end
				ns.UpdateNameRaidColor(frame);
				frame._wasDead = false;
			end
			if (frame.optionTable.displayHealPrediction) then
				RearrangeOverlayFrames(frame, frame.healthBar, false)
			end
		end
	end
end

--[[
! Managing Health color: reverted bar
]]
local function UpdateHealth_Reverted(frame, health, isTest)
	if not frame:IsForbidden() and UnitInPartyOrRaid(frame) and FrameIsCompact(frame) then
		local c = KRF_GetClassColor(frame.unit);

		if c and frame and frame.background and frame.optionTable.useClassColors then
			frame.background:SetVertexColor(1,1,1)
			frame.background:SetColorTexture(darken(c.r, c.g, c.b, .7, .8));
			frame.name:SetShadowColor(c.r, c.g, c.b, .3);
		end

		if not frame.healthBarRevert then
			frame.healthBarRevert = CreateFrame("StatusBar", nil, frame)
			frame.healthBarRevert:SetAllPoints(frame.healthBar)
			frame.healthBarRevert:SetStatusBarTexture(_G[ns.OPTIONS_NAME].Bar_Texture or DEFAULT_RAIDHEALTHBAR_TEXTURE, "ARTWORK")
			frame.healthBarRevert:GetStatusBarTexture():SetHorizTile(true)
			frame.healthBarRevert:GetStatusBarTexture():SetVertTile(true)
			frame.healthBarRevert:SetUsingParentLevel(true)
		end
		frame.healthBar:Hide()
		frame.healthBarRevert:Show()

		if not KRF_UnitIsConnected(frame) then
			-- Disconnected
			frame.healthBarRevert:SetValue(0);
			frame.background:SetColorTexture(darken(_G[ns.OPTIONS_NAME].RevertColorLow.r, _G[ns.OPTIONS_NAME].RevertColorLow.g, _G[ns.OPTIONS_NAME].RevertColorLow.b, .6, .4));
			ns.Hook_UpdateName(frame, true);
			ns.UpdateNameRaidColor(frame);
		elseif KRF_UnitIsDeadOrGhost(frame) then
			-- Dead
			frame.healthBarRevert:SetValue(0);
			frame._wasDead = true;
			if (_G[ns.OPTIONS_NAME].IconOnDeath) then
				ns.Hook_UpdateName(frame, true);
			end
			ns.UpdateNameRaidColor(frame);
		else
			-- Alive
			local unitHealthMax, healthPercentage, healthLost
			health, unitHealthMax, healthPercentage, healthLost = unitHealthValues(frame.displayedUnit, health, isTest)
			frame.healthBarRevert:SetMinMaxValues(0, unitHealthMax)
			applyBarTexture(frame.healthBarRevert, _G[ns.OPTIONS_NAME].Bar_Texture, DEFAULT_RAIDHEALTHBAR_TEXTURE)
			frame.healthBarRevert:GetStatusBarTexture():SetVertexColor(GetHPSeverity(frame.displayedUnit, healthPercentage, true, isTest))

			if frame._wasDead then
				if (_G[ns.OPTIONS_NAME].IconOnDeath) then
					ns.Hook_UpdateName(frame, true);
				end
				ns.UpdateNameRaidColor(frame);
				frame._wasDead = false;
			end

			-- Set reverted value
			if (frame.optionTable.smoothHealthUpdates ) then
				frame.healthBarRevert:SetSmoothedValue(healthLost);
			else
				frame.healthBarRevert:SetValue(healthLost);
			end

			if (frame.optionTable.displayHealPrediction) then
				RearrangeOverlayFrames(frame, frame.healthBarRevert, true)
			end
		end
	end
end

--[[
! Managing Health & Alpha
- Normal or revert, depending on option
]]
function ns.Hook_UpdateHealth(frame, health, isTest)
	if _G[ns.OPTIONS_NAME].UpdateHealthColor and not frame:IsForbidden() then
		if not _G[ns.OPTIONS_NAME].RevertBar then
			UpdateHealth_Regular(frame, health, isTest)
		else
			UpdateHealth_Reverted(frame, health, isTest)
		end
	end
end

--[[
! UpdateRoleIcon
- Role icon on top left
- Role icon visible only for tanks / heals
- Reposition name accordingly
]]
function ns.Hook_UpdateRoleIcon(frame)
	if not frame:IsForbidden() and (_G[ns.OPTIONS_NAME].HideDamageIcons or _G[ns.OPTIONS_NAME].MoveRoleIcons) then
		local icon = frame.roleIcon;
		if not icon then
			return;
		end

		local offset = icon:GetWidth() / 4

		if _G[ns.OPTIONS_NAME].MoveRoleIcons then
			icon:ClearAllPoints();
			icon:SetPoint("TOPLEFT", -offset-2, offset-2);
			frame.name:SetPoint("TOPLEFT", 5, -5);
			icon:SetDrawLayer("ARTWORK", 3)
		end

		local role = UnitGroupRolesAssigned(frame.unit);
		if _G[ns.OPTIONS_NAME].HideDamageIcons and role == "DAMAGER" then
			icon:Hide();
		end
	end
end

local GetUnitNameSafe = function(unit, showServerName)
	local name, server = UnitName(unit);
	if ( type(server) ~= "nil") then
		if ( showServerName ) then
			return string.format("%s-%s", name, server);
		end
		local relationship = UnitRealmRelationship(unit);
		if (relationship ~= LE_REALM_RELATION_VIRTUAL) then
			return string.format("%s%s", name, FOREIGN_SERVER_LABEL);
		end
	end
	return name;
end

--[[
! Manage player names (partyframes & nameplates)
- Hide realm
- Add death icon (option)
- Call to ns.UpdateNameRaidColor (only inside hook)
]]
function ns.Hook_UpdateName(frame, calledOutsideHook)
	if frame:IsForbidden() or not UnitPlayerControlled(frame.displayedUnit) then
		return
	end

	if not calledOutsideHook then
		ns.UpdateNameRaidColor(frame)
	end

	local name = frame.name
	local dead = (_G[ns.OPTIONS_NAME].IconOnDeath and KRF_UnitIsDeadOrGhost(frame)) and l.RT8 or ""

	if _G[ns.OPTIONS_NAME].HideRealm then
		name:SetText(string.format("%s%s", dead, GetUnitNameSafe(frame.displayedUnit, false)))
	elseif _G[ns.OPTIONS_NAME].IconOnDeath then
		name:SetText(string.format("%s%s", dead, GetUnitNameSafe(frame.displayedUnit, true)))
	end
end

--[[
! Update Raid/Party frames color
]]
function ns.UpdateNameRaidColor(frame)
    if not frame:IsForbidden() and UnitPlayerControlled(frame.displayedUnit) and FrameIsCompact(frame) then
        local name = frame.name;
        local c = KRF_GetClassColor(frame.displayedUnit)
        -- Party / Raid Frames
        if _G[ns.OPTIONS_NAME].FriendsClassColor then
            if KRF_UnitIsDeadOrGhost(frame) then
                local lowColor = (not _G[ns.OPTIONS_NAME].RevertBar) and _G[ns.OPTIONS_NAME].BGColorLow or _G[ns.OPTIONS_NAME].RevertColorLow;
                name:SetVertexColor(lowColor.r, lowColor.g, lowColor.b, lowColor.a or 1);
                name:SetShadowColor(lowColor.r, lowColor.g, lowColor.b, 0.2);
            else
                if c then
                    local r, g, b = c.r, c.g, c.b;
                    if (not _G[ns.OPTIONS_NAME].RevertBar) then
                        r, g, b = lighten(r, g, b, 0.20);
                    end
                    name:SetVertexColor(r, g, b);
                    name:SetShadowColor(r, g, b, 0.2);
                end
                name:SetAlpha(KRF_UnitIsConnected(frame) and 1 or 0.5);
            end
        end
    end
end

function ns.ApplyFuncToRaidFrames(func, ...)
	for member = 1, 80 do -- Pets included
		local frame = _G["CompactRaidFrame"..member];
		if frame and frame:IsVisible() then
			func(frame, ...);
		end
	end
	for member = 1, 5 do
		local frame = _G["CompactPartyFrameMember"..member];
		if frame and frame:IsVisible() then
			func(frame, ...);
		end
		frame = _G["CompactPartyFramePet"..member];
		if frame and frame:IsVisible() then
			func(frame, ...);
		end
	end
	for raid = 1, 8 do
		if _G["CompactRaidGroup"..raid] ~= nil and _G["CompactRaidGroup"..raid]:IsVisible() then
			for member = 1, 5 do
				local frame = _G["CompactRaidGroup"..raid.."Member"..member];
				if frame == nil or not frame:IsVisible() then
					break;
				end
				func(frame, ...);
			end
		end
	end
end

function ns.RaidFrames_ResetHealth(frame, testMode)
	local health = UnitHealth(frame.displayedUnit);
	-- frame:SetMinMaxValues(0, unitHealthMax)
	local healthBar = _G[ns.OPTIONS_NAME].RevertBar and frame.healthBarRevert or frame.healthBar
	healthBar:SetMinMaxValues(0, UnitHealthMax(frame.displayedUnit))
	if testMode then
		if frame._testHealthPercentage == nil then
			frame._testHealthPercentage = fastrandom(0, 100)
		end

		if frame._testHealthPercentage == 0 and not frame._testUnitDisconnected then
			frame._testUnitDisconnected = true;
			frame.statusText:SetText(PLAYER_OFFLINE);
			ns.Hook_UpdateHealth(frame, 0, true);
			return
		end
		frame._testUnitDisconnected = nil;
		local unitHealthMax = 100 -- UnitHealthMax(frame.displayedUnit);
		frame._testHealthPercentage = (frame._testHealthPercentage == 0) and 100 or math.max(0, frame._testHealthPercentage - 5);
		health = ceil(unitHealthMax * frame._testHealthPercentage / 100);
		if frame._testHealthPercentage <= 0 then
			frame.statusText:SetText(DEAD);
		else
			frame.statusText:SetText(format("%d%%", frame._testHealthPercentage));
		end
		-- healthBar:SetMinMaxValues(0, unitHealthMax)
		if ( frame.optionTable.smoothHealthUpdates ) then
			healthBar:SetMinMaxSmoothedValue(0, unitHealthMax)
		else
			healthBar:SetMinMaxValues(0, unitHealthMax)
		end
	end
	healthBar:SetValue(health);
	ns.Hook_UpdateHealth(frame, health, testMode);
end

function ns.DebugFrames()
	ns.IsDebugFramesTimerActive = not ns.IsDebugFramesTimerActive;
	if ns.IsDebugFramesTimerActive then
		ns.AddMsgWarn(l.OPTION_DEBUG_ON_MESSAGE);
		ns.optionsFrame.Debug.Text:SetText(l.OPTION_DEBUG_OFF);
		ns.optionsFrame.Debug.tooltipText = l.OPTION_DEBUG_OFF;
		PlaySound(SOUNDKIT.IG_MAINMENU_OPEN, "Master")
		ns.LoopDebug();
	else
		ns.AddMsgWarn(l.OPTION_DEBUG_OFF_MESSAGE);
		if (issecretvalue ~= nil) then
			ns.AddMsgWarn(l.OPTION_RELOAD_REQUIRED) -- IF OPTION REVERT AND MIDNIGHT
		end
		ns.optionsFrame.Debug.Text:SetText(l.OPTION_DEBUG_ON);
		ns.optionsFrame.Debug.tooltipText = l.OPTION_DEBUG_ON;
		PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE, "Master")
	end
end
function ns.LoopDebug()
	if ns.IsDebugFramesTimerActive then
		ns.ApplyFuncToRaidFrames(ns.RaidFrames_ResetHealth, true);
		C_Timer.After(.5, ns.LoopDebug);
	else
		ns.ApplyFuncToRaidFrames(ns.RaidFrames_ResetHealth, false);
	end
end


