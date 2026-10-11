--[[
	Hello to Kallye Raid Frames
	Last version: 12.1.003c (2026-09-24T02:27:45Z)
]]
local _, ns = ...
local l = ns.I18N;
local isInit = false;
local isLoaded = false;


local defaultOptions = {
	Version = ns.VERSION,

	UpdateHealthColor = true,
	BGColorLow =		{ r= 1, g= 0, b= 0, a = 1 },
	BGColorWarn = 		{ r = 1, g= 1, b= 0, a = .52 },
	BGColorOK =			{ r= .1, g= .1, b= .1, a = .15 },
	RevertBar = false, -- Revert the bar (sRaidFrames like)
	RevertColorLow =		{ r= 1, g= 0, b= 0, a = 1 },
	RevertColorWarn = { r = 1, g= 1, b= 0, a = .8 },
	RevertColorOK =			{ r= 0, g= 1, b= 0, a = 1 },
	LimitLow = 25,
	LimitWarn = 50,
	LimitOk = 75,
	HealthAlpha = 100,

	MoveRoleIcons = true,
	HideDamageIcons = true,
	HideRealm = true,
	IconOnDeath = true,
	FriendsClassColor = false,
	AlphaInRange = 100,
	AlphaNotInRange = ns.DEFAULT_ALPHA_OUTOFRANGE, -- 50
	AlphaNotInCombat = 100, -- 70
	Bar_Texture = "",
	AlphaDispelOverlay = 100, -- 100
	SoloRaidFrame = false,		 -- Show solo raid (useful for testing)
	SoloRaidFrameGroupInRaid = false,

	ActiveUnitDebuffs = true,
	BuffsScale = 0.75,
	MaxBuffs = CompactUnitFrame_GetOptionDisplayOnlyDispellableDebuffs and 8 or ns.DEFAULT_MAXBUFFS,
	BuffsPerLine = 4,
	BuffsOrientation = "LeftThenUp",
	BuffsPosX = 0,
	BuffsPosY = 0,
	BuffsSpacingX = 0,
	BuffsSpacingY = 1,
	BuffsFilter = "auto",
	BuffsHideTooltip = false,
	DebuffsScale = 1.25,
	MaxDebuffs = ns.DEFAULT_MAXDEBUFFS,
	DebuffsPerLine = ns.DEFAULT_MAXDEBUFFS,
	DebuffsOrientation = "RightThenUp",
	DebuffsPosX = 0,
	DebuffsPosY = 0,
	DebuffsSpacingX = 0,
	DebuffsSpacingY = 1,
	DebuffsFilter = "auto",
	DebuffsHideTooltip = false,
	HideBlizzardAuras = true,
	UseTaintMethod = false,

	ActiveNameplatesColor = true,
	FriendsNameplates_Txt_UseColor = "1",
	FriendsNameplates_Txt_Color = { r= .235, g= .941, b= 1, a = 1 },
	FriendsNameplates_Bar_UseColor = ns.HAS_colorNameBySelection and "0" or "1",
	FriendsNameplates_Bar_Color = { r= .235, g= .941, b= 1, a = 1 },
	FriendsNameplates_Bar_Texture = "",
	FriendsNameplates_PvpIcon = "faction",
	FriendsNameplates_Txt_ShowLevel = "12",
	FriendsNameplates_Txt_Level_Color_Under = { r= .251, g= .753, b= .251 },
	FriendsNameplates_Txt_Level_Color_Over = { r= .96, g= .83, b= 0 },

	EnemiesNameplates_Txt_UseColor = "1",
	EnemiesNameplates_Txt_Color = { r= .87, g= 0, b= .05, a = 1 },
	EnemiesNameplates_Bar_UseColor = "0",
	EnemiesNameplates_Bar_Color = { r= .87, g= 0, b= .05, a = 1 },
	EnemiesNameplates_Bar_Texture = "",
	EnemiesNameplates_PvpIcon = "faction",
	EnemiesNameplates_Txt_ShowLevel = "12",
	EnemiesNameplates_Txt_Level_Color_Under = { r= .251, g= .753, b= .251 },
	EnemiesNameplates_Txt_Level_Color_Over = { r= .800, g= .098, b= .098 },

	ActiveRaidIcons = true,
	RaidsIcons_Anchor = "TOPRIGHT",
	RaidsIcons_Size = 12,
	RaidsIcons_PosX = -4,
	RaidsIcons_PosY = -4,

	ShowMsgNormal = true,
	ShowMsgWarning = true,
	ShowMsgError = false,
	HideDisabledModules = true,
	AddonCompartmentFilter = true,

	DebugMode = false,
};




local function SLASH_KRF_command(msgIn)
	if (not isLoaded) then
		ns.AddMsgWarn(l.INIT_FAILED, true);
		return;
	end
	if msgIn == "new" then
		ns.AddMsg(l.WHATSNEW);
	elseif msgIn == "test" then
		ns.DebugFrames();
	elseif msgIn == "edit" then
		ns.ShowEditMode("PartyFrame");
	elseif msgIn == "debug" then
		_G[ns.OPTIONS_NAME].DebugMode = not _G[ns.OPTIONS_NAME].DebugMode;
		ns.AddMsgWarn("Debug mode: "..(_G[ns.OPTIONS_NAME].DebugMode and l.GR.."true" or l.RD.."false"), true);
		SLASH_KRF_command();
	elseif msgIn == "reset" then
		StaticPopup_Show(ns.ADDON_NAME.."_CONFIRM_RESET")
	else
		if Settings then
			Settings.OpenToCategory(ns.CATEGORY_ID);
		else
			InterfaceOptionsFrame_OpenToCategory(ns.TITLE);
		end
		C_Timer.After(1, K_SHARED_UI.RefreshOptions);
	end
end

local function SLASH_CLEAR_command()
	SELECTED_CHAT_FRAME:Clear()
end

-- KRF_OnEvent
local function OnEvent(self, event, ...)
	local arg1 = select(1, ...);
	if (event == "ADDON_LOADED" and arg1 == ns.ADDON_NAME) then
		isLoaded = true;

		if l.UpdateLocales then l.UpdateLocales() end
		ns.SetDefaultOptions(defaultOptions);
		ns.RefreshOptions(defaultOptions);

		if C_AddOns.GetAddOnInfo("RaidFrameAuras") == nil then
			self:UnregisterEvent("ADDON_LOADED");
		end

		-- ! Hooks
		hooksecurefunc("CompactUnitFrame_UpdateName", ns.Hook_UpdateName);
		hooksecurefunc("CompactUnitFrame_UpdateRoleIcon", ns.Hook_UpdateRoleIcon);
		hooksecurefunc("CompactUnitFrame_UpdateHealthColor", ns.Hook_UpdateHealth);
		if (CompactUnitFrame_UpdateHealPrediction) then
			--? Since DragonFlight (10)
			hooksecurefunc("CompactUnitFrame_UpdateHealPrediction", ns.Hook_UpdateHealth);
		else
			--? Classic
			hooksecurefunc("CompactUnitFrame_UpdateHealth", ns.Hook_UpdateHealth);
		end

		if _G[ns.OPTIONS_NAME].AlphaNotInRange ~= ns.DEFAULT_ALPHA_OUTOFRANGE or _G[ns.OPTIONS_NAME].AlphaNotInCombat ~= 100 then
			-- DefaultCompactUnitFrameOptions.fadeOutOfRange = false; -- side effects :/
			hooksecurefunc("CompactUnitFrame_UpdateInRange", ns.Hook_UpdateInRange);
			hooksecurefunc("CompactUnitFrame_UpdateHealthColor", ns.Hook_UpdateInRange);
		end

		-- Load Modules
		foreach(ns.MODULES,
			function(_, module)
				module:Init(_G[ns.OPTIONS_NAME]);
			end
        );

		-- ! Addon Loaded ^^
		if (_G[ns.OPTIONS_NAME].Version ~= defaultOptions.Version) then
			_G[ns.OPTIONS_NAME].Version = defaultOptions.Version;
			if (l.WHATSNEW ~= "") then
				ns.AddMsg(l.WHATSNEW);
			end
		end
		if (_G[ns.OPTIONS_NAME].DebugMode) then
			SLASH_KRF_command()

			local i = 1
			while(ns.optionsFrame["Options"..i])
			do
				ns.SetGradientBg(ns.optionsFrame["Options"..i], {r= .8, g=0, b=0, a = .3})
				i=i+1;
			end
		end

	end
	if (event == "ADDON_LOADED" and arg1 == "RaidFrameAuras") then
		self:UnregisterEvent("ADDON_LOADED");
		ns.CONFLICT_RFA = true
		ns.LoadRaidFramesAuras = nil
		if _G[ns.OPTIONS_NAME].ActiveUnitDebuffs then
			_G[ns.OPTIONS_NAME].ActiveUnitDebuffs = false
			ns.AddMsgErr("RaidFrameAuras detected, Debuffs disabled")
			ns.AddMsgWarn(l.OPTION_RELOAD_REQUIRED)
		end
	end
end -- END KRF_OnEvent

local function InitAddon(frame)

	SlashCmdList["KRF"] = SLASH_KRF_command;
	SLASH_KRF1 = "/krf";
	SLASH_KRF2 = "/kallye";
	SLASH_KRF3 = "/kallyeraidframes";

	if (ns.CONFLICT) then
		ns.AddMsgErr(format(l.CONFLICT_MESSAGE, ns.CONFLICT_WITH));
		return;
	end

	SlashCmdList["CLEAR"] = SLASH_CLEAR_command;
	SLASH_CLEAR1 = "/clear";

	if (isInit or InCombatLockdown()) then return; end

	isInit = true;
	frame:SetScript("OnEvent",
		function(frame, event, ...)
			OnEvent(frame, event, ...);
		end
	);
	frame:RegisterEvent("ADDON_LOADED");
end -- END KRF_OnLoad

do
	local eventsFrame = CreateFrame("Frame", nil, UIParent)
	InitAddon(eventsFrame);
end


local function RequiredReloadOptionsString()
	return tostring(_G[ns.OPTIONS_NAME].SoloRaidFrame)
		..tostring(_G[ns.OPTIONS_NAME].SoloRaidFrameGroupInRaid)
		..tostring(_G[ns.OPTIONS_NAME].RevertBar)
		..tostring(_G[ns.OPTIONS_NAME].UpdateHealthColor)
		..tostring(_G[ns.OPTIONS_NAME].FriendsClassColor)
		..tostring(_G[ns.OPTIONS_NAME].ActiveUnitDebuffs)
		..tostring(_G[ns.OPTIONS_NAME].BuffsScale)
		..tostring(_G[ns.OPTIONS_NAME].MaxBuffs)
		..tostring(_G[ns.OPTIONS_NAME].BuffsPerLine)
		..tostring(_G[ns.OPTIONS_NAME].BuffsOrientation)
		..tostring(_G[ns.OPTIONS_NAME].BuffsPosX)
		..tostring(_G[ns.OPTIONS_NAME].BuffsPosY)
		..tostring(_G[ns.OPTIONS_NAME].BuffsHideTooltip)
		..tostring(_G[ns.OPTIONS_NAME].DebuffsScale)
		..tostring(_G[ns.OPTIONS_NAME].MaxDebuffs)
		..tostring(_G[ns.OPTIONS_NAME].DebuffsPerLine)
		..tostring(_G[ns.OPTIONS_NAME].DebuffsOrientation)
		..tostring(_G[ns.OPTIONS_NAME].DebuffsPosX)
		..tostring(_G[ns.OPTIONS_NAME].DebuffsPosY)
		..tostring(_G[ns.OPTIONS_NAME].DebuffsHideTooltip)
		..tostring(_G[ns.OPTIONS_NAME].HideBlizzardAuras)
		..tostring(_G[ns.OPTIONS_NAME].UseTaintMethod)
		..tostring(_G[ns.OPTIONS_NAME].ActiveRaidIcons)
		..tostring(_G[ns.OPTIONS_NAME].AlphaNotInRange ~= ns.DEFAULT_ALPHA_OUTOFRANGE or _G[ns.OPTIONS_NAME].AlphaNotInCombat ~= 100);
end



StaticPopupDialogs[ns.ADDON_NAME.."_CONFIRM_RESET"] = {
	showAlert = true,
	text = format("%s%s|r\n%s", l.YL, ns.TITLE, CONFIRM_RESET_SETTINGS),
	button1 = ALL_SETTINGS,
	-- button3 = CURRENT_SETTINGS,
	button2 = CANCEL,
	OnAccept = function()
		ns.SetDefaultOptions(defaultOptions, true);
		ReloadUI();
	end,
	-- OnAlt  = function()	end,
	timeout = STATICPOPUP_TIMEOUT,
	timeoutInformationalOnly = false,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,  -- avoid some UI taint
};

function KRFUI.ConfirmReset()
	StaticPopup_Show(ns.ADDON_NAME.."_CONFIRM_RESET")
end

function KRFUI.ResetOptions(optionNamesToReset, optionsToForce)
	ns.ResetOptions(optionNamesToReset, defaultOptions, optionsToForce)
end


function KRFUI.SetUseRaidStylePartyFrames(checked)
	if (EditModeManagerFrame.UseRaidStylePartyFrames) then
		--? EditModeManagerFrame.UseRaidStylePartyFrames, since DragonFlight (10)
		--* > Save options before applying EditMode (hides options), and reload options after
		ns.containerFrame.okay()
		ns.SetUseRaidStylePartyFrames(checked)
		C_Timer.After(1, SlashCmdList["KRF"])
	else
		--? Classic CVar
		ns.SetUseRaidStylePartyFrames(checked)
	end
end
function KRFUI.DebugFrames()
	ns.DebugFrames();
end
function KRFUI.ShowEditMode(window)
	ns.ShowEditMode(window);
end

local refreshOptions = function()
	ns.RefreshOptions(defaultOptions, true);
end
local saveOptions = function()
	ns.SaveOptions(defaultOptions, RequiredReloadOptionsString);
	-- Specific stuff

    -- Secure limits (low <= warn <= ok)
    if _G[ns.OPTIONS_NAME].LimitWarn < _G[ns.OPTIONS_NAME].LimitLow then
        _G[ns.OPTIONS_NAME].LimitWarn = _G[ns.OPTIONS_NAME].LimitLow
    end
    if _G[ns.OPTIONS_NAME].LimitOk < _G[ns.OPTIONS_NAME].LimitWarn then
        _G[ns.OPTIONS_NAME].LimitOk = _G[ns.OPTIONS_NAME].LimitWarn
    end
    -- Reset party health as soon as possible
    ns.ApplyFuncToRaidFrames(ns.RaidFrames_ResetHealth, false);
end
function KRFUI.OptionsContainer_OnLoad(self, scrollFrame, optionsFrame)
	if ns.CONFLICT then
		return;
	end
	ns.containerFrame = self;
	ns.scrollFrame = scrollFrame;
	ns.optionsFrame = optionsFrame;
	self.name = ns.TITLE;
	self.okay = saveOptions;
	self.refresh = refreshOptions;
	-- self.cancel = K_SHARED_UI.RefreshOptions; -- disabled
	ns.InterfaceOptions_AddCategory(self);
	if (ns.scrollFrame ~= nil) then
		local BACKDROP_TOOLTIP = {
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\FriendsFrame\\UI-Toast-Border",
			tile = true,
			tileSize = 8,
			edge = true,
			edgeSize = 8,
			insets = {left = 2, right = 2, top = 2, bottom = 2},
		};

		if (BackdropTemplateMixin) then Mixin(ns.scrollFrame, BackdropTemplateMixin) end
		ns.scrollFrame:SetBackdrop(BACKDROP_TOOLTIP)
	end

	-- Localize FontStrings
	foreach(self,
		function (_, child)
			if type(child) == "table" and child:GetObjectType() == "FontString" then
				child:SetText(l[child:GetText()]);
			end
		end
	);

end

local function ManageOptionsVisibility()
	local HealthOption,
		RevertBarOption,
		SoloRaidOption,
		EditableLayout
			=
			ns.optionsFrame.UpdateHealthColor:GetChecked(),
			ns.optionsFrame.RevertBar:GetChecked(),
			ns.optionsFrame.SoloRaidFrame:GetChecked(),
			ns.CanEditActiveLayout and ns.CanEditActiveLayout()

	if (EditModeManagerFrame.UseRaidStylePartyFrames) then
		-- Edit Mode - Since DragonFlight (10)
		if (EditableLayout == nil) then
			return
		end
		ns.optionsFrame.EditMode:SetShown(EditableLayout)
		ns.optionsFrame.EditModeBtn:SetShown(not EditableLayout)
		if not EditableLayout then
			ns.optionsFrame.EditModeBtn:SetAlpha(EditModeManagerFrame:UseRaidStylePartyFrames() and .4 or 1);
		else
			ns.optionsFrame.EditMode:SetChecked(ns.GetUseRaidStylePartyFrames() == 1 or SoloRaidOption)
			ns.OptionsEnable(ns.optionsFrame.EditMode, not SoloRaidOption, .4);
		end
	else
		-- Classic
		ns.optionsFrame.EditModeBtn:SetShown(false)
		ns.optionsFrame.EditMode:SetChecked(SoloRaidOption or ns.GetUseRaidStylePartyFrames())
		ns.OptionsEnable(ns.optionsFrame.EditMode, not SoloRaidOption, .2);
		ns.optionsFrame.SoloRaidFrameGroupInRaid:SetShown(false)
		ns.OptionsEnable(ns.optionsFrame.BlizzFriendsClassColor, false, .2);
	end

	ns.OptionsEnable(ns.optionsFrame.RevertBar, HealthOption)
	ns.OptionsEnable(ns.optionsFrame.LimitLow , HealthOption);
	ns.OptionsEnable(ns.optionsFrame.LimitWarn, HealthOption);
	ns.OptionsEnable(ns.optionsFrame.LimitOk  , HealthOption);
	-- ns.OptionsSetShownAndEnable(ns.optionsFrame.AlphaDispelOverlay, (CompactPartyFrameMember1 and CompactPartyFrameMember1.DispelOverlay) and true or false  , HealthOption);
	ns.OptionsSetShownAndEnable(ns.optionsFrame.AlphaDispelOverlay, (CompactPartyFrameMember1 and CompactPartyFrameMember1.DispelOverlay) and true or false  , false);

	ns.OptionsSetShownAndEnable(ns.optionsFrame.BGColorLow , not RevertBarOption, HealthOption);
	ns.OptionsSetShownAndEnable(ns.optionsFrame.BGColorWarn, not RevertBarOption, HealthOption);
	ns.OptionsSetShownAndEnable(ns.optionsFrame.BGColorOK  , not RevertBarOption, HealthOption);

	ns.OptionsSetShownAndEnable(ns.optionsFrame.RevertColorLow , RevertBarOption, HealthOption);
	ns.OptionsSetShownAndEnable(ns.optionsFrame.RevertColorWarn, RevertBarOption, HealthOption);
	ns.OptionsSetShownAndEnable(ns.optionsFrame.RevertColorOK  , RevertBarOption, HealthOption);

	local raidFramesDisplayClassColor = GetCVarBool("raidFramesDisplayClassColor")
	if not raidFramesDisplayClassColor and CompactRaidFrame1 then
		raidFramesDisplayClassColor = (CompactRaidFrame1.optionTable.useClassColors) or false
	end
	ns.OptionsSetShownAndEnable(ns.optionsFrame.HealthAlphaText  , not RevertBarOption and raidFramesDisplayClassColor, HealthOption);
	ns.OptionsSetShownAndEnable(ns.optionsFrame.HealthAlpha  , not RevertBarOption and raidFramesDisplayClassColor, HealthOption);

	ns.OptionsEnable(ns.optionsFrame.AddonCompartmentFilter,	not not AddonCompartmentFrame, .1);
end

K_SHARED_UI.AddRefreshOptions(ManageOptionsVisibility)