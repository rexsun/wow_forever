local _, ns = ...
local l = ns.I18N;

-- * avoid conflict override
if ns.CONFLICT then return; end


ns.FORCE_USE_MAXBUFFS_TAINT_METHOD = nil -- maxBuffs only
if (issecretvalue ~= nil) then
	-- Since Midnight (12)
	ns.FORCE_USE_MAXBUFFS_TAINT_METHOD = false
elseif CompactUnitFrame_GetOptionDisplayOnlyDispellableDebuffs == nil then
	-- Classic
	ns.FORCE_USE_MAXBUFFS_TAINT_METHOD = true
end

local DEFAULT_MAXBUFFS = ns.DEFAULT_MAXBUFFS or 3
local DEFAULT_MAXDEBUFFS = DEFAULT_MAXBUFFS
local DEFAULT_BUFFS_PER_LINE = 3

local DEFAULT_BUFF_SIZE = 11
local DEFAULT_DEBUFF_SIZE = 11
local MAX_TRACKED_AURAS = 40
local BLIZZARD_BUFF_BASE_OFFSET_X = -3
local BLIZZARD_BUFF_BASE_OFFSET_Y = 2
local BLIZZARD_DEBUFF_BASE_OFFSET_X = 3
local BLIZZARD_DEBUFF_BASE_OFFSET_Y = 2
local BLIZZARD_POWERBAR_OFFSET_Y = 8

local BLIZZARD_AURA_CVARS = {
	"raidFramesDisplayBuffs",
	"raidFramesDisplayDebuffs",
}

local ORIENTATION_TO_LAYOUT = {
	LeftThenUp = {
		lineAxis = "HORIZONTAL",
		horizontalDirection = "BACKWARD",
		verticalDirection = "FORWARD",
		anchorPoint = "BOTTOMRIGHT",
	},
	UpThenLeft = {
		lineAxis = "VERTICAL",
		horizontalDirection = "BACKWARD",
		verticalDirection = "FORWARD",
		anchorPoint = "BOTTOMRIGHT",
	},
	RightThenUp = {
		lineAxis = "HORIZONTAL",
		horizontalDirection = "FORWARD",
		verticalDirection = "FORWARD",
		anchorPoint = "BOTTOMLEFT",
	},
	UpThenRight = {
		lineAxis = "VERTICAL",
		horizontalDirection = "FORWARD",
		verticalDirection = "FORWARD",
		anchorPoint = "BOTTOMLEFT",
	},
}

local inCombat = InCombatLockdown()

local FILTER_SUFFIX_OVERRIDES = { RAID = "RAID", RAID_IN_COMBAT = "RAID_IN_COMBAT" }

local function ResolveFilterString(prefix, filterOption)
	local suffix = FILTER_SUFFIX_OVERRIDES[filterOption] or (inCombat and "RAID_IN_COMBAT" or "RAID")
	return prefix.."|"..suffix
end

--? Options are in screen axes; the container lays out in flow axes, which swap with the orientation.
local function ResolveSpacing(orientation, spacingX, spacingY)
	local layout = ORIENTATION_TO_LAYOUT[orientation] or ORIENTATION_TO_LAYOUT.LeftThenUp
	if layout.lineAxis == "VERTICAL" then
		return spacingY, spacingX
	end
	return spacingX, spacingY
end

local function getEnumValue(enumTable, ...)
	if not enumTable then return nil end
	for i = 1, select("#", ...) do
		local key = select(i, ...)
		if enumTable[key] ~= nil then
			return enumTable[key]
		end
	end
	return nil
end

local function resolveFlowLayoutEnums()
	--[[
	AnchorUtil.FlowLayoutAxis={Vertical=1, Horizontal=0}
	AnchorUtil.FlowDirection={Down=1, Right=1, Left=1, Up=1}
	]]
	local anchorEnum = AnchorUtil
	local axisEnum = anchorEnum and anchorEnum.FlowLayoutAxis
	local directionEnum = anchorEnum and anchorEnum.FlowDirection
	if not axisEnum or not directionEnum then
		return nil
	end

	return {
		axisHorizontal = getEnumValue(axisEnum, "Horizontal", "HORIZONTAL", "X"),
		axisVertical = getEnumValue(axisEnum, "Vertical", "VERTICAL", "Y"),
		directionForward = getEnumValue(directionEnum, "Up", "Right", "Forward", "FORWARD", "Positive"),
		directionBackward = getEnumValue(directionEnum, "Down", "Left", "Backward", "BACKWARD", "Negative"),
	}
end

local function toFlowLayoutAxis(enumValues, value)
	if not enumValues then return nil end
	if value == "VERTICAL" then
		return enumValues.axisVertical
	end
	return enumValues.axisHorizontal
end

local function toFlowLayoutDirection(enumValues, value)
	if not enumValues then return nil end
	if value == "BACKWARD" then
		return enumValues.directionBackward
	end
	return enumValues.directionForward
end

local AuraContainer = ns.UD_AuraContainer or {
	options = nil,
	enabled = false,
	hooksInstalled = false,
	frameState = setmetatable({}, { __mode = "k" }),
}

local function IsAuraContainer_Supported()
	return not not AuraContainerSortDirection
end

local function SafeSetCVar(name, value)
	if not SetCVar or value == nil then return false end
	local ok = pcall(SetCVar, name, value)
	return ok == true
end

local function applyBlizzardAuraCVarPolicy(hide)
	local value = hide and "0" or "1"
	for _, cvarName in ipairs(BLIZZARD_AURA_CVARS) do
		SafeSetCVar(cvarName, value)
	end
end

local function scaleToSize(baseSize, scale)
	scale = tonumber(scale) or 1
	return math.max(4, math.min(80, math.floor(baseSize * scale + 0.5)))
end

local function FrameIsCompact(frame)
	if issecretvalue(frame) or frame:IsForbidden() then
		return true
	end
	local getName = frame:GetName();
	return getName ~=nil and strsub(getName, 0, 7) == "Compact"
end

local function getFrameUnit(frame)
	if not frame then return nil end
	return frame.unit or frame.displayedUnit or (frame.GetAttribute and frame:GetAttribute("unit"))
end

local function FrameIsPet(frame)
	local unit = getFrameUnit(frame)
	if not unit then return false end
	return UnitIsMinion(unit)
end

local function FrameIsCompactNoPet(frame)
	return FrameIsCompact(frame) and not FrameIsPet(frame)
end

local function safeCreateAuraContainer(parent)
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	if ok and container then
		return container
	end

	ok, container = pcall(CreateFrame, "AuraContainer", nil, parent)
	if ok then
		return container
	end

	return nil
end

local function getOrCreateAuraContainerState(frame)
	local state = AuraContainer.frameState[frame]
	if state then
		return state
	end

	state = {
		buffContainer = nil,
		debuffContainer = nil,
		hasBuffGroup = false,
		hasDebuffGroup = false,
		unit = nil,
	}
	AuraContainer.frameState[frame] = state
	return state
end

local function clearContainerGroups(container)
	if not container then return end
	if type(container.ClearAuraGroups) == "function" then
		pcall(container.ClearAuraGroups, container)
	end
end

local function hideContainer(container)
	if not container then return end
	clearContainerGroups(container)
	container:Hide()
end



local function addGroupIfNeeded(state, container, groupKey, filterString, maxCount, iconSize, isMouseEnabled, isBuff)
	if not container or type(container.AddAuraGroup) ~= "function" then
		return false
	end

	local hasGroup = isBuff and state.hasBuffGroup or state.hasDebuffGroup
	if hasGroup then
		return true
	end

	local options = {
		maxFrameCount = math.max(0, math.min(MAX_TRACKED_AURAS, tonumber(maxCount) or 0)),
		sortMethod = AuraContainerSortMethod.Default,
		sortDirection = AuraContainerSortDirection.Normal,
		initializeFrame = function(auraButton)
			auraButton:SetSize(iconSize, iconSize)

			local texture = auraButton:CreateTexture()
			texture:SetAllPoints()
			auraButton:SetIcon(texture)

			auraButton.Cooldown = CreateFrame ("cooldown", "$parentCooldown", auraButton, "CooldownFrameTemplate")
			local iconOffset = 0
			-- PixelUtil.SetPoint (auraButton.Cooldown, "TOPLEFT", auraButton, "TOPLEFT", -iconOffset, iconOffset)
			-- PixelUtil.SetPoint (auraButton.Cooldown, "TOPRIGHT", auraButton, "TOPRIGHT", iconOffset, iconOffset)
			-- PixelUtil.SetPoint (auraButton.Cooldown, "BOTTOMLEFT", auraButton, "BOTTOMLEFT", -iconOffset, -iconOffset)
			-- PixelUtil.SetPoint (auraButton.Cooldown, "BOTTOMRIGHT", auraButton, "BOTTOMRIGHT", iconOffset, -iconOffset)
			auraButton.Cooldown:EnableMouse (false)
			if auraButton.Cooldown.EnableMouseMotion then
				auraButton.Cooldown:EnableMouseMotion (false)
			end
			auraButton.Cooldown:SetHideCountdownNumbers(true)
			auraButton.Cooldown:SetCountdownAbbrevThreshold(60)
			auraButton.Cooldown:SetMinimumCountdownDuration(0)
			auraButton.Cooldown:SetReverse(true)
			auraButton:SetDurationCooldown(auraButton.Cooldown)


			auraButton:EnableMouse(isMouseEnabled)
			if (isMouseEnabled) then
				auraButton:SetCancelAuraButtons("RightButtonUp")
			end
		end,
	}

	local ok = pcall(container.AddAuraGroup, container, groupKey, filterString, options)
	if not ok then
		return false
	end

	if isBuff then
		state.hasBuffGroup = true
	else
		state.hasDebuffGroup = true
	end
	return true
end

local function applyContainerFlowLayout(container, orientation, wrap)
	if not container then
		return false
	end

	local layout = ORIENTATION_TO_LAYOUT[orientation] or ORIENTATION_TO_LAYOUT.LeftThenUp
	local enumValues = resolveFlowLayoutEnums()
	if not enumValues then
		return false
	end

	local axis = toFlowLayoutAxis(enumValues, layout.lineAxis)
	local horizontalDirection = toFlowLayoutDirection(enumValues, layout.horizontalDirection)
	local verticalDirection = toFlowLayoutDirection(enumValues, layout.verticalDirection)
	if axis == nil or not horizontalDirection or not verticalDirection then
		return false
	end

	container:SetFlowLayoutAxis(axis)
	container:SetFlowLayoutGrowthDirection(horizontalDirection, verticalDirection)
	container:SetFlowLayoutAnchorPoint(layout.anchorPoint)
	container:SetFlowLayoutMaximumLineSize(math.max(1, tonumber(wrap) or 1))

	return true
end

local function applyGroupLayout(container, groupKey, orientation, wrapElements, iconSize, elementSpacing, lineSpacing)
	local layout = ORIENTATION_TO_LAYOUT[orientation] or ORIENTATION_TO_LAYOUT.LeftThenUp
	local layoutOptions = {
		elementWidth = iconSize,
		elementHeight = iconSize,
		elementSpacing = elementSpacing,
		lineSpacing = lineSpacing,
		layoutIndex = 1,
	}
	local wrap = wrapElements * (iconSize+elementSpacing)

	if not applyContainerFlowLayout(container, orientation, wrap) then
		-- Fallback for intermediate API variants.
		layoutOptions.growthDirection = layout.horizontalDirection == "BACKWARD" and
			(layout.lineAxis == "VERTICAL" and "UP_LEFT" or "LEFT_UP") or
			(layout.lineAxis == "VERTICAL" and "UP_RIGHT" or "RIGHT_UP")
		layoutOptions.wrapAfter = math.max(1, tonumber(wrap) or 1)
	end

	container:SetAuraGroupLayout(groupKey, layoutOptions)
	return true
	-- local ok = pcall(container.SetAuraGroupLayout, container, groupKey, layoutOptions)
	-- return ok == true
end

local function setContainerAnchor(container, frame, orientation, posX, posY)
	if not container or not frame then return end
	local layout = ORIENTATION_TO_LAYOUT[orientation] or ORIENTATION_TO_LAYOUT.LeftThenUp
	local anchorPoint = layout.anchorPoint or "BOTTOMRIGHT"
	container:ClearAllPoints()
	container:SetPoint(anchorPoint, frame, anchorPoint, tonumber(posX) or 0, tonumber(posY) or 0)
end

local function AuraContainerRefreshFrame(frame)
	if not frame or not IsAuraContainer_Supported() or not FrameIsCompactNoPet(frame) then
		return
	end

	local state = getOrCreateAuraContainerState(frame)
	if not AuraContainer.enabled or not AuraContainer.options then
		hideContainer(state.buffContainer)
		hideContainer(state.debuffContainer)
		state.hasBuffGroup = false
		state.hasDebuffGroup = false
		state.unit = nil
		return
	end

	local unit = getFrameUnit(frame)
	if not unit then
		return
	end

	local options = AuraContainer.options
	local maxBuffs = math.max(0, tonumber(options.MaxBuffs) or 0)
	local maxDebuffs = math.max(0, tonumber(options.MaxDebuffs) or 0)
	local buffSize = scaleToSize(DEFAULT_BUFF_SIZE, options.BuffsScale)
	local debuffSize = scaleToSize(DEFAULT_DEBUFF_SIZE, options.DebuffsScale)
	local buffsSpacingX = tonumber(options.BuffsSpacingX) or 0
	local buffsSpacingY = tonumber(options.BuffsSpacingY) or 1
	local debuffsSpacingX = tonumber(options.DebuffsSpacingX) or 0
	local debuffsSpacingY = tonumber(options.DebuffsSpacingY) or 1
	local buffMouseEnabled = options.BuffsHideTooltip ~= true
	local debuffMouseEnabled = options.DebuffsHideTooltip ~= true

	local hasPowerBar = frame.powerBar and frame.powerBar:IsShown()
	local powerBarOffsetY = hasPowerBar and BLIZZARD_POWERBAR_OFFSET_Y or 0

	if maxBuffs > 0 then
		if not state.buffContainer then
			state.buffContainer = safeCreateAuraContainer(frame)
			state.hasBuffGroup = false
		end
		local buffContainer = state.buffContainer
		if buffContainer then
			pcall(buffContainer.SetUnit, buffContainer, unit)
			pcall(buffContainer.SetAuraGroupMaxFrameCount, buffContainer, "kbd_buffs", maxBuffs)

			local buffsElemSpacing, buffsLineSpacing = ResolveSpacing(options.BuffsOrientation, buffsSpacingX, buffsSpacingY)
			if addGroupIfNeeded(state, buffContainer, "kbd_buffs", "HELPFUL|RAID_IN_COMBAT", maxBuffs, buffSize, buffMouseEnabled, true) then
				applyGroupLayout(buffContainer, "kbd_buffs", options.BuffsOrientation, options.BuffsPerLine, buffSize, buffsElemSpacing, buffsLineSpacing)
			end
			local filterString = ResolveFilterString("HELPFUL", options.BuffsFilter)
			buffContainer:SetAuraGroupFilterString("kbd_buffs", filterString)
			setContainerAnchor(
				buffContainer,
				frame,
				options.BuffsOrientation,
				BLIZZARD_BUFF_BASE_OFFSET_X + (tonumber(options.BuffsPosX) or 0),
				BLIZZARD_BUFF_BASE_OFFSET_Y + (tonumber(options.BuffsPosY) or 0) + powerBarOffsetY
			)
			buffContainer:Show()
		end
	else
		hideContainer(state.buffContainer)
		state.hasBuffGroup = false
	end

	if maxDebuffs > 0 then
		if not state.debuffContainer then
			state.debuffContainer = safeCreateAuraContainer(frame)
			state.hasDebuffGroup = false
		end
		local debuffContainer = state.debuffContainer
		if debuffContainer then
			pcall(debuffContainer.SetUnit, debuffContainer, unit)
			pcall(debuffContainer.SetAuraGroupMaxFrameCount, debuffContainer, "kbd_debuffs", maxDebuffs)

			local debuffsElemSpacing, debuffsLineSpacing = ResolveSpacing(options.DebuffsOrientation, debuffsSpacingX, debuffsSpacingY)
			if addGroupIfNeeded(state, debuffContainer, "kbd_debuffs", "HARMFUL|RAID_IN_COMBAT", maxDebuffs, debuffSize, debuffMouseEnabled, false) then
				applyGroupLayout(debuffContainer, "kbd_debuffs", options.DebuffsOrientation, options.DebuffsPerLine, debuffSize, debuffsElemSpacing, debuffsLineSpacing)
			end
			local filterString = ResolveFilterString("HARMFUL", options.DebuffsFilter)
			debuffContainer:SetAuraGroupFilterString("kbd_debuffs", filterString)
			setContainerAnchor(
				debuffContainer,
				frame,
				options.DebuffsOrientation,
				BLIZZARD_DEBUFF_BASE_OFFSET_X + (tonumber(options.DebuffsPosX) or 0),
				BLIZZARD_DEBUFF_BASE_OFFSET_Y + (tonumber(options.DebuffsPosY) or 0) + powerBarOffsetY
			)
			if type(debuffContainer.Show) == "function" then
				debuffContainer:Show()
			end
		end
	else
		hideContainer(state.debuffContainer)
		state.hasDebuffGroup = false
	end

	state.unit = unit
end

local function AuraContainerRefreshAllFrames()
	for i = 1, 40 do
		AuraContainerRefreshFrame(_G["CompactRaidFrame" .. i])
	end

	for group = 1, 8 do
		for member = 1, 5 do
			AuraContainerRefreshFrame(_G["CompactRaidGroup" .. group .. "Member" .. member])
		end
	end

	for i = 1, 5 do
		AuraContainerRefreshFrame(_G["CompactPartyFrameMember" .. i])
		AuraContainerRefreshFrame(_G["CompactArenaFrameMember" .. i])
	end
end

local function AuraContainerEnsureHooks()
	if AuraContainer.hooksInstalled then
		return
	end

	if type(CompactUnitFrame_UpdateAll) == "function" then
		hooksecurefunc("CompactUnitFrame_UpdateAll", AuraContainerRefreshFrame)
	end

	if type(CompactUnitFrame_SetUnit) == "function" then
		hooksecurefunc("CompactUnitFrame_SetUnit", AuraContainerRefreshFrame)
	end
	
	local eventFrame = CreateFrame("Frame")

	eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
	eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

	eventFrame:SetScript("OnEvent", function(self, event)
		local previousInCombat = inCombat
		if event == "PLAYER_REGEN_DISABLED" then
			inCombat = true
		elseif event == "PLAYER_REGEN_ENABLED" then
			inCombat = false
		end
		if previousInCombat ~= inCombat then
			AuraContainerRefreshAllFrames()
		end
	end)

	AuraContainer.hooksInstalled = true
end

local function AuraContainerDisable()
	AuraContainer.enabled = false
	AuraContainer.options = nil

	for frame, state in pairs(AuraContainer.frameState) do
		if FrameIsCompactNoPet(frame) then
			hideContainer(state.buffContainer)
			hideContainer(state.debuffContainer)
			state.hasBuffGroup = false
			state.hasDebuffGroup = false
			state.unit = nil
		end
	end
end

local function ApplyAuraContainer(options)
	if not IsAuraContainer_Supported() then
		AuraContainerDisable()
		return false
	end

	AuraContainerEnsureHooks()
	AuraContainer.options = options
	AuraContainer.enabled = options and options.ActiveUnitDebuffs ~= false
	applyBlizzardAuraCVarPolicy(AuraContainer.enabled and options.HideBlizzardAuras == true)
	AuraContainerRefreshAllFrames()
	return true
end

		-- ! Blizzard original method modified, from CompactUnitFrame / Midnight
		function ns.CompactUnitFrame_UpdateAurasInternalMidnight(frame, unitAuraUpdateInfo)
			if frame.isLootObject then
				return;
			end
			if frame.buffFrames == nil then
				return;
			end

			local displayOnlyDispellableDebuffs = CompactUnitFrame_GetOptionDisplayOnlyDispellableDebuffs(frame, frame.optionTable);
			local ignoreBuffs = not frame.buffFrames or not frame.optionTable.displayBuffs or frame.maxBuffs == 0;
			local displayDebuffs = CompactUnitFrame_GetOptionDisplayDebuffs(frame, frame.optionTable);
			local ignoreDebuffs = not frame.debuffFrames or not displayDebuffs or frame.maxDebuffs == 0;
			local ignoreDispelDebuffs = ignoreDebuffs or not frame.dispelDebuffFrames or not frame.optionTable.displayDispelDebuffs or frame.maxDispelDebuffs == 0;

			-- modification start
			local cacheOptions = ns.Module.cacheOptions
			local maxBuffs = cacheOptions.MaxBuffs
			local maxDebuffs = cacheOptions.MaxDebuffs
			local debuffsChanged = not ignoreBuffs;
			local buffsChanged = not ignoreDebuffs;
			-- modification end

			if debuffsChanged then
				local frameNum = 1;
				-- local maxDebuffs = frame.maxDebuffs; -- modification
				frame.debuffs:Iterate(function(auraInstanceID, aura)
					if frameNum > maxDebuffs then
						return true;
					end

					if CompactUnitFrame_IsAuraInstanceIDBlocked(frame, auraInstanceID) then
						return false;
					end

					-- local debuffFrame = frame.debuffFrames[frameNum];
					-- ns.CompactUnitFrame_UtilSetDebuff(frame, debuffFrame, aura);
					frameNum = frameNum + 1;

					return false;
				end);

				CompactUnitFrame_HideAllDebuffs(frame, frameNum);
				CompactUnitFrame_UpdatePrivateAuras(frame);
			end

			if buffsChanged then
				local frameNum = 1;

				local buffAuraInstanceIDToSkip;
				if frame.CenterDefensiveBuff then
					if CompactUnitFrame_GetOptionShowBigDefensive(frame) and frame.bigDefensives:Size() ~= 0 then
						local bigDefensiveAura = frame.bigDefensives:GetTop();
						buffAuraInstanceIDToSkip = bigDefensiveAura.auraInstanceID;
						-- ns.CompactUnitFrame_UtilSetBuff(frame.CenterDefensiveBuff, bigDefensiveAura);
					-- else
						-- frame.CenterDefensiveBuff:Hide();
					end
				end
				-- local maxBuffs = frame.maxBuffs; -- modification
				frame.buffs:Iterate(function(auraInstanceID, aura)
					if frameNum > maxBuffs then
						return true;
					end

					if aura.auraInstanceID ~= buffAuraInstanceIDToSkip then
						local buffFrame = frame.buffFrames[frameNum];
						ns.CompactUnitFrame_UtilSetBuff(buffFrame, aura);
						frameNum = frameNum + 1;
					end

					return false;
				end);

				CompactUnitFrame_HideAllBuffs(frame, frameNum);
			end
			-- modification (remove dispelsChanged)
			ns.Hook_ManageBuffs(frame);
			ns.Hook_ManageDebuffs(frame);
		end
--[[
! Manage buffs
- Scale buffs / debuffs
]]
		-- ! Blizzard original method modified, from CompactUnitFrame
		-- * alternative safe method (else maxBuffs taints frame)
		function ns.CompactUnitFrame_UpdateAurasInternal(frame, unitAuraUpdateInfo)
			if frame.isLootObject then
				return;
			end
			if frame.buffFrames == nil then
				return;
			end
			-- -- FIXME: Midnight HotFix
			if ns.FORCE_USE_MAXBUFFS_TAINT_METHOD == false then
				ns.CompactUnitFrame_UpdateAurasInternalMidnight(frame, unitAuraUpdateInfo)
				return;
			end

			local displayOnlyDispellableDebuffs = CompactUnitFrame_GetOptionDisplayOnlyDispellableDebuffs(frame, frame.optionTable);
			local ignoreBuffs = not frame.buffFrames or not frame.optionTable.displayBuffs or frame.maxBuffs == 0;
			local displayDebuffs = CompactUnitFrame_GetOptionDisplayDebuffs(frame, frame.optionTable);
			local ignoreDebuffs = not frame.debuffFrames or not displayDebuffs or frame.maxDebuffs == 0;
			local ignoreDispelDebuffs = ignoreDebuffs or not frame.dispelDebuffFrames or not frame.optionTable.displayDispelDebuffs or frame.maxDispelDebuffs == 0;

			-- modification start
			local cacheOptions = ns.Module.cacheOptions
			local maxBuffs = cacheOptions.MaxBuffs
			local maxDebuffs = cacheOptions.MaxDebuffs
			local debuffsChanged = not ignoreBuffs;
			local buffsChanged = not ignoreDebuffs;
			-- modification end

			if debuffsChanged then
				local frameNum = 1;
				-- local maxDebuffs = frame.maxDebuffs; -- modification
				frame.debuffs:Iterate(function(auraInstanceID, aura)
					if frameNum > maxDebuffs then
						return true;
					end

					if CompactUnitFrame_IsAuraInstanceIDBlocked(frame, auraInstanceID) then
						return false;
					end

					local debuffFrame = frame.debuffFrames[frameNum];
					-- ns.CompactUnitFrame_UtilSetDebuff(debuffFrame, aura);
					frameNum = frameNum + 1;

					if aura.isBossAura then
						-- Boss auras are about twice as big as normal debuffs, so we may need to display fewer buffs
						local bossDebuffScale = (debuffFrame.baseSize + BOSS_DEBUFF_SIZE_INCREASE)/debuffFrame.baseSize;
						maxDebuffs = maxDebuffs - (bossDebuffScale - 1);
					end

					return false;
				end);

				CompactUnitFrame_HideAllDebuffs(frame, frameNum);
				CompactUnitFrame_UpdatePrivateAuras(frame);
			end

			if buffsChanged then
				local frameNum = 1;
				-- local maxBuffs = frame.maxBuffs; -- modification
				frame.buffs:Iterate(function(auraInstanceID, aura)
					if frameNum > maxBuffs then
						return true;
					end
					local buffFrame = frame.buffFrames[frameNum];
					ns.CompactUnitFrame_UtilSetBuff(buffFrame, aura); -- modification
					frameNum = frameNum + 1;

					return false;
				end);

				CompactUnitFrame_HideAllBuffs(frame, frameNum);
			end
			-- modification (remove dispelsChanged)
		end

-- Store frames waiting for combat end
local pendingFrames = {}



local OrientationEnum = {
    LeftThenUp = "LeftThenUp",
    UpThenLeft = "UpThenLeft",
    RightThenUp = "RightThenUp",
    UpThenRight = "UpThenRight"
}

local function anchorPoints(frameIdx, lineSize, orientation)
	local isNewLine = (lineSize ~= nil) and (math.fmod(frameIdx-1, lineSize) == 0)
	local relatedIdx = isNewLine and (frameIdx-lineSize) or (frameIdx-1)

	local alignments = {
		-- orientation =  point, relatedPoint, newLineRelatedPoint
		[OrientationEnum.LeftThenUp] = { "BOTTOMRIGHT", "BOTTOMLEFT", "TOPRIGHT" },
		[OrientationEnum.UpThenLeft] = { "BOTTOMRIGHT", "TOPRIGHT", "BOTTOMLEFT" },
		[OrientationEnum.RightThenUp]= { "BOTTOMLEFT", "BOTTOMRIGHT", "TOPLEFT" },
		[OrientationEnum.UpThenRight]= { "BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT" },
	}
	local selectedAlignment = alignments[orientation] or alignments[OrientationEnum.LeftThenUp]

	local point, relatedPoint =
		selectedAlignment[1],
		(not isNewLine) and selectedAlignment[2] or selectedAlignment[3];
	return isNewLine, point, relatedIdx, relatedPoint
end

--- Manage the display and scaling of buffs & debuffs on group frames.
--- @param param table Object containing all parameters
--- @meta param.frame frame Frame on which buffs and debuffs are displayed
--- @meta param.frameType string Frame type (e.g., "Buffs" or "Debuffs")
--- @meta param.maxCount number Maximum number of icons to display
--- @meta param.lineSize number Number of icons per line
--- @meta param.useTaintMethod boolean
--- @meta param.orientation string Icon orientation (e.g., "LeftThenUp")
--- @meta param.posX number Position X relative to the first icon
--- @meta param.posY number Position Y relative to the first icon
--- @meta param.blizzardOrientation string Blizzard's default orientation for buffs or debuffs
--- @meta param.defaultMax number Default maximum number of icons to display
local function ManageUnitFrames(param)
	if ns.FORCE_USE_MAXBUFFS_TAINT_METHOD ~= nil then
		param.useTaintMethod = ns.FORCE_USE_MAXBUFFS_TAINT_METHOD
	end
	if not FrameIsCompact(param.frame) or FrameIsPet(param.frame) or param.frame:IsForbidden() then
		return
	end
    local frameName = param.frame:GetName() .. param.frameType
	-- if InCombatLockdown() then
	-- 	pendingFrames[frameName] = param
	-- 	return
	-- end

	local BLIZZARD_MAX_PROP = "max"..param.frameType.."s" -- frame.maxBuffs / .maxDebuffs / .maxDispelDebuff
	local defaultMaxProp = "defaultMax"..param.frameType.."s" -- save BLizzard MAX first time
	param.frame[defaultMaxProp] = param.frame[defaultMaxProp] or param.frame[BLIZZARD_MAX_PROP]

	-- Reposition first icon if necessary
	if param.posX ~= 0 or param.posY ~= 0 then
		local firstChild = param.frameChilds[1]
		local attr = firstChild:GetAttribute("_firstPoint")
		if attr == nil then
			local point, relativeTo, relativePoint, xOfs, yOfs = firstChild:GetPoint()
			firstChild:SetAttribute("_firstPoint", {
				point = point,
				relativeTo = relativeTo,
				relativePoint = relativePoint,
				xOfs = xOfs or 0,
				yOfs = yOfs or 0
			})
			attr = firstChild:GetAttribute("_firstPoint")
		end
		firstChild:ClearAllPoints()
		firstChild:SetPoint(
			attr.point,
			attr.relativeTo,
			attr.relativePoint,
			attr.xOfs + param.posX,
			attr.yOfs + param.posY
		)
	end

	if param.maxCount > param.frame[defaultMaxProp] or param.lineSize < param.maxCount or param.orientation ~= param.blizzardOrientation then
		-- add missing icons and re-SetPoints
		-- start loop at first icon not matching blizz positioning
		local loopStart = math.min(param.defaultMax + 1, param.lineSize + 1)
		if param.orientation ~= param.blizzardOrientation or param.posX ~= 0 or param.posY ~= 0 then
			loopStart = 2
		end
		for childIdx = loopStart, param.maxCount do
			local isNewChild = false
			local child = _G[frameName .. childIdx]
			if not _G[frameName .. childIdx] then
				child = CreateFrame("Button", frameName .. childIdx, param.frame, "Compact" .. param.frameType .. "Template")
				child:SetScale(param.scale)
				if param.frameChilds[childIdx] == nil then
					param.frameChilds[childIdx] = child
				end
				isNewChild = true
			end
			local isNewLine, point, relativeIdx, relativePoint = anchorPoints(childIdx, param.lineSize, param.orientation)
			if isNewChild or isNewLine or param.orientation ~= param.blizzardOrientation then
				child:ClearAllPoints();
				child:SetPoint(point, _G[frameName .. relativeIdx], relativePoint)
			end
		end
	end

	if InCombatLockdown() then
		pendingFrames[frameName] = param
		return
	end

	if param.useTaintMethod and param.maxCount ~= param.frame[BLIZZARD_MAX_PROP] then
		param.frame[BLIZZARD_MAX_PROP] = param.maxCount -- ! Taints frame
	end

	-- rescaling
    local lastScale = param.frame:GetAttribute("_lastScale") or 1
    if lastScale ~= param.scale then
		for _, child in ipairs(param.frameChilds) do
			child:SetScale(param.scale);
		end
		param.frame:SetAttribute("_lastScale", param.scale)
    end
end

-- Event handler for combat end
function ns.OnCombatEnd()
	for frameName, param in pairs(pendingFrames) do
		ManageUnitFrames(param)
		pendingFrames[frameName] = nil
	end
end

function ns.Hook_ManageBuffs(frame)
    local cacheOptions = ns.Module.cacheOptions
    local max = cacheOptions.MaxBuffs
    local scale = cacheOptions.BuffsScale
	local slotsPerLine = cacheOptions.BuffsPerLine
	local useTaintMethod = cacheOptions.UseTaintMethod
	if ns.FORCE_USE_MAXBUFFS_TAINT_METHOD ~= nil then
		useTaintMethod = ns.FORCE_USE_MAXBUFFS_TAINT_METHOD
	end
	local orientation = cacheOptions.BuffsOrientation or OrientationEnum.LeftThenUp
	local posX = cacheOptions.BuffsPosX or 0
	local posY = cacheOptions.BuffsPosY or 0

	ManageUnitFrames({
		frame = frame,
		frameChilds = frame.buffFrames,
		frameType = "Buff",
		defaultMax = DEFAULT_MAXBUFFS,
		maxCount = max,
		scale = scale,
		lineSize = slotsPerLine,
		useTaintMethod = useTaintMethod,
		blizzardOrientation = OrientationEnum.LeftThenUp,
		orientation = orientation,
		posX = posX,
		posY = posY,
		retries = 0
	})
end

function ns.Hook_ManageDebuffs(frame)
    local cacheOptions = ns.Module.cacheOptions
    local max = cacheOptions.MaxDebuffs
    local scale = cacheOptions.DebuffsScale
	local slotsPerLine = cacheOptions.DebuffsPerLine
	local useTaintMethod = cacheOptions.UseTaintMethod
	if ns.FORCE_USE_MAXBUFFS_TAINT_METHOD ~= nil then
		useTaintMethod = ns.FORCE_USE_MAXBUFFS_TAINT_METHOD
	end
	local orientation = cacheOptions.DebuffsOrientation or OrientationEnum.RightThenUp
	local posX = cacheOptions.DebuffsPosX or 0
	local posY = cacheOptions.DebuffsPosY or 0

	ManageUnitFrames({
		frame = frame,
		frameChilds = frame.debuffFrames,
		frameType = "Debuff",
		defaultMax = DEFAULT_MAXDEBUFFS,
		maxCount = max,
		scale = scale,
		lineSize = slotsPerLine,
		useTaintMethod = useTaintMethod,
		blizzardOrientation = OrientationEnum.RightThenUp,
		orientation = orientation,
		posX = posX,
		posY = posY,
		retries = 0
	})
end

function ns.CompactUnitFrame_UtilSetDebuff(frame, debuffFrame, aura)
	if not C_CurveUtil then
		CompactUnitFrame_UtilSetDebuff(frame, debuffFrame, aura)
		return
	end
	debuffFrame.filter = aura.isRaid and AuraUtil.AuraFilters.Raid or nil;
	debuffFrame.icon:SetTexture(aura.icon);
	-- FIXME: Show count only if aura.applications > 1 ?
	-- debuffFrame.count:Show();
	debuffFrame.count:SetText(aura.applications);
	debuffFrame.auraInstanceID = aura.auraInstanceID;
	-- local enabled = aura.expirationTime and aura.expirationTime ~= 0;
	-- if enabled then
	-- 	local startTime = aura.expirationTime - aura.duration;
	-- 	CooldownFrame_Set(debuffFrame.cooldown, startTime, aura.duration, true);
	-- else
	-- 	CooldownFrame_Clear(debuffFrame.cooldown);
	-- end

	AuraUtil.SetAuraBorderColor(debuffFrame.border, aura.dispelName);
	debuffFrame.isBossBuff = aura.isBossAura and aura.isHelpful;

	-- local size = CompactUnitFrame_GetDebuffSize(frame, debuffFrame, aura);
	-- debuffFrame:SetSize(size, size);
	debuffFrame:Show();
end
function ns.CompactUnitFrame_UtilSetBuff(buffFrame, aura)
	if not C_CurveUtil then
		CompactUnitFrame_UtilSetBuff(buffFrame, aura)
		return
	end
	buffFrame.icon:SetTexture(aura.icon);
	-- FIXME: Show count only if aura.applications > 1 ?
	-- buffFrame.count:Show();
	buffFrame.count:SetText(aura.applications);
	buffFrame.auraInstanceID = aura.auraInstanceID
	-- local enabled = aura.expirationTime and aura.expirationTime ~= 0;
	-- if enabled then
	-- 	local startTime = aura.expirationTime - aura.duration;
	-- 	CooldownFrame_Set(buffFrame.cooldown, startTime, aura.duration, true);
	-- else
	-- 	CooldownFrame_Clear(buffFrame.cooldown);
	-- end
	buffFrame:Show();
end

-- Will be used in standalone addon
local function getInfo(self)
    ns.AddMsg(l.MSG_LOADED);
end

local function isEnabled(options)
	if IsAuraContainer_Supported() then
		return options.ActiveUnitDebuffs ~= false
	end

	if ns.LoadRaidFramesAuras then
		return options.ActiveUnitDebuffs ~= false
	end
    return ns.HAS_SECRETS ~= true and options.ActiveUnitDebuffs ~= false
		and (
			options.BuffsScale ~= 1
			or options.MaxBuffs   ~= DEFAULT_MAXBUFFS
			or options.BuffsPerLine < DEFAULT_MAXBUFFS
			or options.BuffsOrientation
			or options.BuffsPosX
			or options.BuffsPosY
			or options.DebuffsScale ~= 1
			or options.MaxDebuffs   ~= DEFAULT_MAXDEBUFFS
			or options.DebuffsPerLine < DEFAULT_MAXDEBUFFS
			or options.DebuffsOrientation
			or options.DebuffsPosX
			or options.DebuffsPosY
		)
end

-- Determine appropriate hook
-- If positions are modified, we have to hook reposition method instead
local function determineAppropriateHook(setMaxHookName, lineSize, maxIcons, defaultMaxIcons, notDefaultAlign, posX, posY)
	if notDefaultAlign or lineSize < maxIcons or lineSize < defaultMaxIcons or posX ~= 0 or posY ~= 0 then
		return "DefaultCompactUnitFrameSetup"
	end
	return setMaxHookName
end

function ns.isFlickerWarningShowed(options)
	local buffsHook = determineAppropriateHook("", options.BuffsPerLine, options.MaxBuffs, DEFAULT_MAXBUFFS, options.BuffsOrientation ~= "LeftThenUp", options.BuffsPosX, options.BuffsPosY)
	local debuffsHook = determineAppropriateHook("", options.DebuffsPerLine, options.MaxDebuffs, DEFAULT_MAXDEBUFFS, options.DebuffsOrientation ~= "RightThenUp", options.DebuffsPosX, options.DebuffsPosY)
	return buffsHook..debuffsHook ~= ""
end
local function onSaveOptions(self, options)
	if IsAuraContainer_Supported() then
		ApplyAuraContainer(options)
		return
	end

	if ns.LoadRaidFramesAuras then
		if isEnabled(options) then
			if not ns._UnitDebuffsHooked then
				ns._UnitDebuffsHooked = true
				ns.LoadRaidFramesAuras(options)
			elseif ns.SyncRaidFramesAuras then
				ns.SyncRaidFramesAuras(options)
			end
		elseif ns._UnitDebuffsHooked and ns.SyncRaidFramesAuras then
			ns.SyncRaidFramesAuras(options)
		end
		return
	end
	-- Until Midnight (12)
    if not ns._UnitDebuffsHooked and isEnabled(options) then
        ns._UnitDebuffsHooked = true
		local buffsHook = determineAppropriateHook("CompactUnitFrame_SetMaxBuffs", options.BuffsPerLine, options.MaxBuffs, DEFAULT_MAXBUFFS, options.BuffsOrientation ~= "LeftThenUp", options.BuffsPosX, options.BuffsPosY)
		local debuffsHook = determineAppropriateHook("CompactUnitFrame_SetMaxDebuffs", options.DebuffsPerLine, options.MaxDebuffs, DEFAULT_MAXDEBUFFS, options.DebuffsOrientation ~= "RightThenUp", options.DebuffsPosX, options.DebuffsPosY)
		local useTaintMethod = options.UseTaintMethod
		if ns.FORCE_USE_MAXBUFFS_TAINT_METHOD ~= nil then
			useTaintMethod = ns.FORCE_USE_MAXBUFFS_TAINT_METHOD
		end
        hooksecurefunc(buffsHook, ns.Hook_ManageBuffs)
        hooksecurefunc(debuffsHook, ns.Hook_ManageDebuffs)
		if not useTaintMethod and (options.MaxBuffs ~= DEFAULT_MAXBUFFS or options.MaxDebuffs ~= DEFAULT_MAXDEBUFFS) then
			-- manage max buffs / debuffs changed, safer but experimental
			hooksecurefunc("CompactUnitFrame_UpdateAuras", ns.CompactUnitFrame_UpdateAurasInternal)
		end

		-- Register combat end event, callback out of combat
		local frame = CreateFrame("Frame")
		frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		frame:SetScript("OnEvent", function(self, event)
			if event == "PLAYER_REGEN_ENABLED" then
				ns.OnCombatEnd()
			end
		end)
    end
end

local function onInit(self, options)
    onSaveOptions(self, options);
end
local module = ns.Module:new(onInit, "UnitDebuffs");

module:SetOnSaveOptions(onSaveOptions);
module:SetGetInfo(getInfo);

