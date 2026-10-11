local _, ns = ...
local l = ns.I18N;

-- * avoid conflict override
if ns.CONFLICT then return; end

-- Fallback if not set in globals
if ns.HAS_colorNameBySelection == nil then
    --? colorNameBySelection, Since BfA (7)
    ns.HAS_colorNameBySelection = ns.IS_RETAIL or (WOW_PROJECT_ID == (WOW_PROJECT_MAINLINE or 1));
end
ns.IsSecretValue = issecretvalue or function(_) return false end

local DEFAULT_NAMEPLATES_TEXTURE = 137014

local function getClassColors()
	return CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS;
end

local function FrameIsCompact(frame)
	local getName = frame:GetName()
	return getName ~=nil and strsub(getName, 0, 7) == "Compact"
end

local function applyTextColor(name, useColorOption, color, customColor)
    if useColorOption == "1" and color then
        name:SetVertexColor(color.r, color.g, color.b, color.a)
        name:SetShadowColor(color.r, color.g, color.b, 0.2)
    elseif useColorOption == "2" then
        name:SetVertexColor(customColor.r, customColor.g, customColor.b, customColor.a)
        name:SetShadowColor(customColor.r, customColor.g, customColor.b, 0.2)
    end
end
local function BCC(color)
    return string.format("ff%02x%02x%02x", (color.r*255), (color.g*255), (color.b*255));
end

ns.pvpIcons = {
    gemred = "|TInterface/PVPFrame/Icons/prestige-icon-8-1:16|t",
    gemblue = "|TInterface/PVPFrame/Icons/prestige-icon-8-2:16|t",
    gemgreen = "|TInterface/PVPFrame/Icons/prestige-icon-8-3:16|t",
    wolf = "|TInterface/PVPFrame/Icons/prestige-icon-3-3-small:20|t",
    lion = "|TInterface/PVPFrame/Icons/prestige-icon-3-4-small:20|t",
    sword = "|TInterface/PVPFrame/Icons/prestige-icon-1:20|t",
    shield = "|TInterface/PVPFrame/Icons/prestige-icon-2:20|t",
    swords = "|TInterface/PVPFrame/Icons/prestige-icon-3:20|t",
    Alliance = "|TInterface/PVPFrame/PVP-Currency-Alliance:16|t",
    Horde = "|TInterface/PVPFrame/PVP-Currency-Horde:16|t",
}
local function applyIconAndText(unit, name, pvpIconOption, showLevelOption, underLevelColor, overLevelColor)
    local prefix = ""
    if showLevelOption ~= "0" then
        local unitLevel = UnitLevel(unit);
        local levelShowed = "";
        if (showLevelOption == "22" or ns._PlayerLevel ~= unitLevel) then
            levelShowed = unitLevel.." ";
        end
        if (unitLevel > 0 and levelShowed ~= "") then
            if (showLevelOption == "12" or showLevelOption == "22") then
                if (unitLevel < ns._PlayerLevel) then
                    levelShowed = WrapTextInColorCode(levelShowed, BCC(underLevelColor));
                elseif (unitLevel > ns._PlayerLevel) then
                    levelShowed = WrapTextInColorCode(levelShowed, BCC(overLevelColor));
                end
            end
            prefix = levelShowed;
        end
    end
    local isPvP = UnitIsPVP(unit)
    if not issecretvalue(isPvP) and isPvP and pvpIconOption ~= "0" then
        local icon = ns.pvpIcons[pvpIconOption] or ""
        if pvpIconOption == "faction" then
            local faction = UnitFactionGroup(unit)
            icon = ns.pvpIcons[faction] or ""
        end
        if icon ~= "" then
            prefix = icon..prefix;
        end
    end
    if prefix ~= "" or prefix ~= name._previousPrefix then
        name:SetText(string.format("%s%s", prefix, UnitName(unit)))
        name._previousPrefix = prefix
    end
end

local function applyBarTexture(frame, texture, default)
    if (texture ~= "" and frame._lastTexture == texture) then
        return
    end
    if (texture == "") then
        if (frame._lastTexture ~= nil) then
            frame._lastTexture = nil
            frame:SetStatusBarTexture(default)
        end
        return
    end
    frame._lastTexture = texture
    frame:SetStatusBarTexture(texture)
end

local function applyBarColor(healthBar, useColorOption, color, customColor)
    if useColorOption == "1" and color then
        healthBar:SetStatusBarColor(color.r, color.g, color.b, color.a)
    elseif useColorOption == "2" then
        healthBar:SetStatusBarColor(customColor.r, customColor.g, customColor.b, customColor.a)
    end
end

--- Determines the color to use for a nameplate unit.
--- Returns class color for players (detected reliably via GUID to avoid the
--- transient red flash when UnitIsPlayer momentarily returns false on a freshly
--- shown/updated nameplate). Returns nil for a player whose class is not yet
--- resolved, so the caller skips this pass instead of applying the hostile
--- selection color (red).
local function getUnitColor(unit)
    local guid = UnitGUID(unit)
    local isPlayer = UnitIsPlayer(unit)
    if not isPlayer and not ns.IsSecretValue(guid) then
        isPlayer = (guid and strsub(guid, 1, 6) == "Player") or false
    end
    if isPlayer then
        local _, class = UnitClass(unit)
        return class and getClassColors()[class] or nil
    end
    local r, g, b, a = UnitSelectionColor(unit)
    return { r = r, g = g, b = b, a = a }
end

local function filterNameplateBarOption(option)
    if (ns.HAS_colorNameBySelection and option == "1") then
        return "0"
    end
    return option
end


--- Updates the nameplate colors based on user settings.
--- Hook CompactUnitFrame_UpdateName
--- @param frame any The nameplate frame to update.
local function Hook_CUF_UpdateName(frame)
    if frame:IsForbidden() or FrameIsCompact(frame) or not UnitExists(frame.displayedUnit) or _G[ns.OPTIONS_NAME].ActiveNameplatesColor == false then
        return
    end

    local cacheOptions = ns.Module.cacheOptions
    if not UnitIsFriend(frame.displayedUnit, "player") then
        applyBarTexture(frame.healthBar, cacheOptions.EnemiesNameplates_Bar_Texture, DEFAULT_NAMEPLATES_TEXTURE)
    else
        applyBarTexture(frame.healthBar, cacheOptions.FriendsNameplates_Bar_Texture, DEFAULT_NAMEPLATES_TEXTURE)
    end

    local c = getUnitColor(frame.displayedUnit)

    if not UnitIsFriend(frame.displayedUnit, "player") then
        applyTextColor(frame.name, cacheOptions.EnemiesNameplates_Txt_UseColor, c, cacheOptions.EnemiesNameplates_Txt_Color)
        applyIconAndText(frame.displayedUnit, frame.name,
            cacheOptions.EnemiesNameplates_PvpIcon,
            cacheOptions.EnemiesNameplates_Txt_ShowLevel,
            cacheOptions.EnemiesNameplates_Txt_Level_Color_Under,
            cacheOptions.EnemiesNameplates_Txt_Level_Color_Over)
        local optionBarUseColor = filterNameplateBarOption(cacheOptions.EnemiesNameplates_Bar_UseColor)
        applyBarColor(frame.healthBar, optionBarUseColor, c, cacheOptions.EnemiesNameplates_Bar_Color)
    else
        applyTextColor(frame.name, cacheOptions.FriendsNameplates_Txt_UseColor, c, cacheOptions.FriendsNameplates_Txt_Color)
        applyIconAndText(frame.displayedUnit, frame.name,
            cacheOptions.FriendsNameplates_PvpIcon,
            cacheOptions.FriendsNameplates_Txt_ShowLevel,
            cacheOptions.FriendsNameplates_Txt_Level_Color_Under,
            cacheOptions.FriendsNameplates_Txt_Level_Color_Over)
        local optionBarUseColor = filterNameplateBarOption(cacheOptions.FriendsNameplates_Bar_UseColor)
        applyBarColor(frame.healthBar, optionBarUseColor, c, cacheOptions.FriendsNameplates_Bar_Color)
    end
end

--- Re-applies only the health bar color/texture.
--- Hooked to CompactUnitFrame_UpdateHealthColor because Blizzard recolors the
--- bar (red for hostile / threat-based) on health/threat/selection changes,
--- which would otherwise override our class color until the next UpdateName.
local function Hook_CUF_UpdateHealthColor(frame)
    if frame:IsForbidden() or FrameIsCompact(frame) or not UnitExists(frame.displayedUnit) or _G[ns.OPTIONS_NAME].ActiveNameplatesColor == false then
        return
    end

    local cacheOptions = ns.Module.cacheOptions
    local c = getUnitColor(frame.displayedUnit)

    if not UnitIsFriend(frame.displayedUnit, "player") then
        applyBarTexture(frame.healthBar, cacheOptions.EnemiesNameplates_Bar_Texture, DEFAULT_NAMEPLATES_TEXTURE)
        local optionBarUseColor = filterNameplateBarOption(cacheOptions.EnemiesNameplates_Bar_UseColor)
        applyBarColor(frame.healthBar, optionBarUseColor, c, cacheOptions.EnemiesNameplates_Bar_Color)
    else
        applyBarTexture(frame.healthBar, cacheOptions.FriendsNameplates_Bar_Texture, DEFAULT_NAMEPLATES_TEXTURE)
        local optionBarUseColor = filterNameplateBarOption(cacheOptions.FriendsNameplates_Bar_UseColor)
        applyBarColor(frame.healthBar, optionBarUseColor, c, cacheOptions.FriendsNameplates_Bar_Color)
    end
end

local function OnEvent(self, event, ...)
	local arg1 = select(1, ...);
	if (event == "PLAYER_LEVEL_UP") then
        ns._PlayerLevel = arg1;
	end
end

-- Will be used in standalone addon
local function getInfo(self)
    ns.AddMsg(l.MSG_LOADED);
end

local function isEnabled(options)
    return options.ActiveNameplatesColor ~= false
		and (
            (options.FriendsNameplates_Txt_UseColor or "0") ~= "0"
            or (options.FriendsNameplates_Bar_UseColor or "0") ~= "0"
            or (options.FriendsNameplates_PvpIcon or "0") ~= "0"
            or (options.FriendsNameplates_Txt_ShowLevel or "0") ~= "0"
            or (options.FriendsNameplates_Bar_Texture or "0") ~= "0"

            or (options.EnemiesNameplates_Txt_UseColor or "0") ~= "0"
            or (options.EnemiesNameplates_Bar_UseColor or "0") ~= "0"
            or (options.EnemiesNameplates_PvpIcon or "0") ~= "0"
            or (options.EnemiesNameplates_Txt_ShowLevel or "0") ~= "0"
            or (options.EnemiesNameplates_Bar_Texture or "0") ~= "0"
        )
end

local function onSaveOptions(self, options)
    if not ns._NameplatesHooked and isEnabled(options) then
        ns._NameplatesHooked = true;
        hooksecurefunc("CompactUnitFrame_UpdateName", Hook_CUF_UpdateName);
        hooksecurefunc("CompactUnitFrame_UpdateHealthColor", Hook_CUF_UpdateHealthColor);

        ns._PlayerLevel = UnitLevel("player");
        local f = CreateFrame("Frame", nil, UIParent);
        f:RegisterEvent("PLAYER_LEVEL_UP");
        f:SetScript("OnEvent", OnEvent);
    end
end

local function onInit(self, options)
    onSaveOptions(self, options);
end
local module = ns.Module:new(onInit, "NameplatesColor");
module:SetOnSaveOptions(onSaveOptions);
module:SetGetInfo(getInfo);

