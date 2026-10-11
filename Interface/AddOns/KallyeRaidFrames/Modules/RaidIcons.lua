local _, ns = ...
local l = ns.I18N;

-- * avoid conflict override
if ns.CONFLICT then return; end

local DEFAULT_RAIDICON_SIZE = ns.DEFAULT_RAIDICON_SIZE or 10


local AnchorsEnum = {
    CENTER = "CENTER",
    TOPLEFT = "TOPLEFT",
    TOPRIGHT = "TOPRIGHT",
    BOTTOMLEFT = "BOTTOMLEFT",
    BOTTOMRIGHT = "BOTTOMRIGHT"
}

-- Will be used in standalone addon
local function getInfo(self)
    ns.AddMsg(l.MSG_LOADED);
end

local function isEnabled(options)
    return options.ActiveRaidIcons ~= false
end

local raidIcons = {}
local function InitRaidIconsTextures(f, size)
	for i = 1, NUM_RAID_ICONS do
		local iconTexture = f:CreateTexture(ns.ADDON_NAME.."UI_RaidIcon"..i, "BACKGROUND");
		iconTexture:Hide();
		-- Since Midnight (12)
		if SetRaidTargetIconTexture then
			iconTexture:SetTexture("Interface/TargetingFrame/UI-RaidTargetingIcons")
		else
			iconTexture:SetTexture("Interface/TargetingFrame/UI-RaidTargetingIcon_"..i);
		end
		iconTexture:SetSize(size, size);
		raidIcons[i] = { texture = iconTexture, visible = false }
	end
end
local function ResizeRaidIconsTextures(size)
	for i = 1, NUM_RAID_ICONS do
		raidIcons[i].texture:SetSize(size, size)
	end
end
local function GetPositions(options)
	local anchor, left, top =
		options.RaidsIcons_Anchor or nil,
		tonumber(options.RaidsIcons_PosX) or 0,
		tonumber(options.RaidsIcons_PosY) or 0
	if not AnchorsEnum[anchor] then
		anchor = AnchorsEnum.CENTER
	end
	return anchor, left, top
end
local function GetUnitFrame(type, group, member)
	if type == "raid" then
		return _G["CompactRaidFrame"..(((group-1)*5) + member )]
	elseif type == "party" then
		return _G["CompactPartyFrameMember".. member]
	else
		return _G["CompactRaidGroup"..group.."Member"..member]
	end
end
local function SetRaidIcons(dontResetPositions, overrideOptions)
	local options = overrideOptions or _G[ns.OPTIONS_NAME];
	foreach (raidIcons,
		function (_, raidIcon)
			raidIcon.visible = false
			raidIcon._previous = dontResetPositions and raidIcon._previous or nil
		end
	)

	local groupType, nbGroups = "raidgroups", 8
	local types = { ["raidgroups"] = 8, ["raid"]= 8, ["party"] = 1 }
	-- detect group type
	for typeName, groups in pairs(types) do
		local unit = GetUnitFrame(typeName, 1, 1)
		if unit and unit:IsVisible() then
			groupType, nbGroups = typeName, groups
			break
		end
	end
	-- Since Midnight (12)
	if SetRaidTargetIconTexture then
		local index = 1
		for group = 1, nbGroups do
			for member = 1, 5 do
				local unitFrame = GetUnitFrame(groupType, group, member)
				if unitFrame and unitFrame:IsVisible() then
					local unit = unitFrame.displayedUnit
					if (unit) then
						local markId = GetRaidTargetIndex(unit)
						if type(markId) ~= "nil" then
							raidIcons[index].visible = true
							raidIcons[index].frame = unitFrame
							SetRaidTargetIconTexture(raidIcons[index].texture, markId)
							index = index + 1
						end
					end
				end
			end
		end
		for idx = index, #raidIcons do
			raidIcons[idx].visible = false
		end
	else
		for group = 1, nbGroups do
			for member = 1, 5 do
				local unitFrame = GetUnitFrame(groupType, group, member)
				if unitFrame and unitFrame:IsVisible() then
					local unit = unitFrame.displayedUnit
					if (unit) then
						local markId = GetRaidTargetIndex(unit)
						if type(markId) ~= "nil" then
							raidIcons[markId].visible = true
							raidIcons[markId].frame = unitFrame
						end
					end
				end
			end
		end
	end
	foreach (raidIcons,
		function (_, raidIcon)
			if raidIcon.visible then
				if raidIcon._previous ~= raidIcon.frame then
					raidIcon._previous = raidIcon.frame
					raidIcon.texture:ClearAllPoints();
					local anchor, left, top = GetPositions(options)
					raidIcon.texture:SetPoint(anchor, raidIcon.frame, anchor, left, top);
					raidIcon.texture:Show();
				end
			elseif raidIcon.frame ~= nil then
				raidIcon.frame = nil
				raidIcon._previous = nil
				raidIcon.texture:Hide()
			end
		end
	)
end


local function OnEvent(self, event, ...)
	if (event == "PLAYER_LOGIN") then
		SetRaidIcons();
	elseif (event == "RAID_TARGET_UPDATE") then
		SetRaidIcons(true);
	elseif (event == "GROUP_ROSTER_UPDATE") then
		-- Error while leaving raid/group?
		if (IsInGroup() or IsInRaid()) then
			C_Timer.After(1, SetRaidIcons)
		end
	--elseif (event == "GROUP_ROSTER_UPDATE") then
		-- If Raid frames moved: replaceraidIcons()
	end
end
local function onSaveOptions(self, options)
	if isEnabled(options) then
		if not ns._RaidIconsHooked then
			ns._RaidIconsHooked = true
			local f = CreateFrame("Frame", nil, UIParent);
			InitRaidIconsTextures(f, options.RaidsIcons_Size or DEFAULT_RAIDICON_SIZE)
			f:RegisterEvent("RAID_TARGET_UPDATE");
			f:RegisterEvent("GROUP_ROSTER_UPDATE");
			f:RegisterEvent("PLAYER_LOGIN");
			f:SetScript("OnEvent", OnEvent);

			-- Direct preview options
			K_SHARED_UI.AddRefreshOptions(
				function(previewOptions)
					if (previewOptions) then
						ResizeRaidIconsTextures(previewOptions.RaidsIcons_Size or DEFAULT_RAIDICON_SIZE)
						SetRaidIcons(false, previewOptions);
					end
				end
			)
		else
			ResizeRaidIconsTextures(options.RaidsIcons_Size or DEFAULT_RAIDICON_SIZE)
			SetRaidIcons()
		end
	end
end

local function onInit(self, options)
    onSaveOptions(self, options);
end
local module = ns.Module:new(onInit, "RaidIcons");

module:SetOnSaveOptions(onSaveOptions);
module:SetGetInfo(getInfo);

