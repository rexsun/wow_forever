local _, ns = ...
local l = ns.I18N;

-- * avoid conflict override
if ns.CONFLICT then return; end

local function noop() end;
local Hook_CompactPartyFrame_UpdateVisibility = noop
local Hook_CompactRaidFrameManager_UpdateContainerVisibility = noop
local SoloRaid_GetDisplayedAllyFrames = noop
local SoloRaid_CompactRaidFrameContainer_OnEvent = noop

if (EditModeManagerFrame.UseRaidStylePartyFrames) then
    --[[
    ! Solo Raid Frames main, since DragonFlight (10)
    - Show Raid Frames if solo
    ]]
    Hook_CompactPartyFrame_UpdateVisibility = function()
        if (not IsInGroup() and not IsInRaid()) then
            if InCombatLockdown() then
                C_Timer.After(1, Hook_CompactPartyFrame_UpdateVisibility);
                return
            end
            CompactPartyFrame:SetShown(true);
        end
    end

    --[[
    ! Solo Party Frames in raid, since DragonFlight (10)
    - Show both Party and Raid Frames in Raid
    ]]
    Hook_CompactRaidFrameManager_UpdateContainerVisibility = function()
        local cacheOptions = ns.Module.cacheOptions
        if (cacheOptions.SoloRaidFrameGroupInRaid and IsInRaid()) then
            if InCombatLockdown() then
                C_Timer.After(1, Hook_CompactRaidFrameManager_UpdateContainerVisibility);
                return
            end
            CompactPartyFrame:SetShown(true);
        end
    end

    function ns.ShowEditMode(window)
        if (not EditModeManagerFrame.UseRaidStylePartyFrames) then
            return;
        end
        ShowUIPanel(EditModeManagerFrame);
        if window == "PartyFrame" then
            -- Works but can throw an error...
            C_EditMode.SetAccountSetting(Enum.EditModeAccountSetting.ShowPartyFrames, 1);
            --EditModeManagerFrame:SelectSystem(PartyFrame);
            PartyFrame:SelectSystem();
            PartyFrame:HighlightSystem();
        end
    end
    function ns.CanEditActiveLayout()
        local LibEditModeOverride = LibStub("LibEditModeOverride-1.0")
        if not LibEditModeOverride:IsReady() then return nil end
        LibEditModeOverride:LoadLayouts()
        return LibEditModeOverride:CanEditActiveLayout();
    end

    function ns.GetUseRaidStylePartyFrames()
        local LibEditModeOverride = LibStub("LibEditModeOverride-1.0")
        if not LibEditModeOverride:IsReady() then return nil end
        LibEditModeOverride:LoadLayouts()
        return LibEditModeOverride:GetFrameSetting(PartyFrame, Enum.EditModeUnitFrameSetting.UseRaidStylePartyFrames)
    end

    local MAX_RETRIES, SECS_BETWEEN = 3, 2
    function ns.SetUseRaidStylePartyFrames(setting, retryCount)
        if setting == nil then return end
        local LibEditModeOverride = LibStub("LibEditModeOverride-1.0")
        -- if edit mode not ready: retry
        if not LibEditModeOverride:IsReady() then
            retryCount = retryCount or 0
            if retryCount > MAX_RETRIES then return end
            C_Timer.After(SECS_BETWEEN, function() ns.SetUseRaidStylePartyFrames(setting, retryCount+1) end)
            return
        end
        if type(setting) == "boolean" then
            setting = setting and 1 or 0
        end
        LibEditModeOverride:LoadLayouts()
        if LibEditModeOverride:CanEditActiveLayout() then
            LibEditModeOverride:SetFrameSetting(PartyFrame, Enum.EditModeUnitFrameSetting.UseRaidStylePartyFrames, setting)
            if InCombatLockdown() then
                LibEditModeOverride:SaveOnly()
                return
            end
            LibEditModeOverride:ApplyChanges()
        end
    end

else

    --[[
    ! Solo Party Frames Classic
    - Show Party/Raid Frames even if solo
    ]]
    local Blizzard_GetDisplayedAllyFrames = GetDisplayedAllyFrames; -- protect original behavior
    SoloRaid_GetDisplayedAllyFrames = function()
        -- Call original default behavior
        local daf = Blizzard_GetDisplayedAllyFrames()

        if not daf then
            return 'party'
        else
            return daf
        end
    end
    local Blizzard_CompactRaidFrameContainer_OnEvent = CompactRaidFrameContainer_OnEvent;  -- protect original behavior
    SoloRaid_CompactRaidFrameContainer_OnEvent = function(self, event, ...)
        -- Call original default behavior
        Blizzard_CompactRaidFrameContainer_OnEvent(self, event, ...)

        -- If all these are true, then the above call already did the TryUpdate
        local unit = ... or ""
        if ( unit == "player" or strsub(unit, 1, 4) == "raid" or strsub(unit, 1, 5) == "party" ) then
            return
        end
        -- Always update the RaidFrame
        if ( event == "UNIT_PET" ) and ( self.displayPets ) then
            CompactRaidFrameContainer_TryUpdate(self)
        end
    end

    function ns.GetUseRaidStylePartyFrames()
        return GetCVarBool("useCompactPartyFrames")
    end
    function ns.SetUseRaidStylePartyFrames(setting)
        SetCVar("useCompactPartyFrames", setting);
    end

end

-- Will be used in standalone addon
local function getInfo(self)
    if (EditModeManagerFrame.UseRaidStylePartyFrames and not EditModeManagerFrame:UseRaidStylePartyFrames()) then
        --? Edit Mode - Since DragonFlight (10)
        if l.OPTION_RAIDSTYLE_ACTION then
            ns.AddMsgWarn(ns.TITLE.." - "..l.OPTION_RAIDSTYLE_ACTION, true);
        end
        ns.ShowEditMode("PartyFrame");
    else
        ns.AddMsg(l.MSG_LOADED);
    end
end

local function onSaveOptions(self, options)
    if (options.SoloRaidFrame) then
        if (EditModeManagerFrame.UseRaidStylePartyFrames and not EditModeManagerFrame:UseRaidStylePartyFrames()) then
			--? Edit Mode - Since DragonFlight (10)
            if not ns.CanEditActiveLayout() then
                -- Can't Edit Active Layout: display manual action
                if l.OPTION_RAIDSTYLE_ACTION then
                    ns.AddMsgWarn(ns.TITLE.." - "..l.OPTION_RAIDSTYLE_ACTION, true);
                end
                return
            end

            if l.OPTION_RAIDSTYLE_WARNING then
                ns.AddMsgWarn(ns.TITLE.." - "..l.OPTION_RAIDSTYLE_WARNING, true);
            end
            ns.SetUseRaidStylePartyFrames(1)
        end
        -- ? Classic > SRF works in every case (doesn't need to set useCompactPartyFrames cvar)
    end
end
local function onInit(self, options)
    if (options.SoloRaidFrame or options.SoloRaidFrameGroupInRaid) then
        if (EditModeManagerFrame.UseRaidStylePartyFrames) then
            --? Edit Mode - Since DragonFlight (10)
            if options.SoloRaidFrame then
                hooksecurefunc(CompactPartyFrame, "UpdateVisibility", Hook_CompactPartyFrame_UpdateVisibility);
            end
            if options.SoloRaidFrameGroupInRaid then
                hooksecurefunc("CompactRaidFrameManager_UpdateContainerVisibility", Hook_CompactRaidFrameManager_UpdateContainerVisibility)
            end
        else
            --? Classic
            CompactRaidFrameManager:Show()
            CompactRaidFrameManager.Hide = function() end
            CompactRaidFrameContainer:Show()
            CompactRaidFrameContainer.Hide = function() end

            GetDisplayedAllyFrames = SoloRaid_GetDisplayedAllyFrames;
            CompactRaidFrameContainer_OnEvent = SoloRaid_CompactRaidFrameContainer_OnEvent;
        end
		-- Delay to let EditMode to be loaded
		C_Timer.After(0, function() onSaveOptions(self, options) end)
    end

end

local module = ns.Module:new(onInit, "Soloraid");
module:SetOnSaveOptions(onSaveOptions);
module:SetGetInfo(getInfo);