local addonName, ns = ...
local l = ns.I18N;

-- * avoid conflict override
if ns.CONFLICT then return; end



local RaidFrameAuras = ns.RaidFrameAuras
if not RaidFrameAuras then
    RaidFrameAuras = CreateFrame("Frame", "RFA_Core_K") -- FIXME:RFA
    ns.RaidFrameAuras = RaidFrameAuras
end

ns.addonName = addonName
do
    local addonVersion
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        addonVersion = C_AddOns.GetAddOnMetadata(addonName, "Version")
    elseif GetAddOnMetadata then
        addonVersion = GetAddOnMetadata(addonName, "Version")
    end
    ns.ADDON_VERSION = addonVersion or ""
end
ns.DB_VERSION = 1403
ns.frameNameCounter = ns.frameNameCounter or 0

function RaidFrameAuras:NextFrameName(suffix)
    ns.frameNameCounter = (ns.frameNameCounter or 0) + 1
    suffix = tostring(suffix or "Frame"):gsub("[^%w_]", "")
    if suffix == "" then
        suffix = "Frame"
    end
    return "RFA_" .. suffix .. "_" .. ns.frameNameCounter
end

function RaidFrameAuras:CreateNamedFrame(frameType, suffix, parent, template, id)
    return CreateFrame(frameType, self:NextFrameName(suffix or frameType), parent, template, id)
end

function RaidFrameAuras:CreatePrivateFrame(frameType, suffix, parent, template, id)
    if type(suffix) ~= "string" then
        parent, template, id = suffix, parent, template
    end
    return CreateFrame(frameType, nil, parent, template, id)
end

ns.State = ns.State or {
    frameStates = setmetatable({}, { __mode = "k" }),
    hookedFrames = setmetatable({}, { __mode = "k" }),
    hookedContainers = setmetatable({}, { __mode = "k" }),
    auraCache = {},
    trackedFrames = setmetatable({}, { __mode = "k" }),
    trackedFrameList = {},
    unitFrames = {},
    rosterGUIDs = {},
    scanQueue = {},
    scanQueued = {},
    trackedTimerIcons = setmetatable({}, { __mode = "k" }),
    refreshBurstToken = 0,
    filtersDirty = true,
    cachedBuffCategoryScaleFilters = nil,
    cachedDebuffCategoryScaleFilters = nil,
    cachedBuffCategoryExclusionFilters = nil,
    cachedDebuffCategoryExclusionFilters = nil,
    cachedCrowdControlFilter = nil,
    durationHideCurves = {},
    expiringCurves = {},
    sortScratchBuffs = {},
    sortScratchDebuffs = {},
    longBuffSpellIDs = {},
    objectiveCarriers = {},
    frameSizeRefreshPending = setmetatable({}, { __mode = "k" }),
}

local State = ns.State

function RaidFrameAuras:Initialize()
    if self.initialized then return end
    self.initialized = true
    self:InitializeDatabase()
    if self.InitializeMasque then
        self:InitializeMasque()
    end

    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_CompactRaidFrames")
    elseif UIParentLoadAddOn then
        pcall(UIParentLoadAddOn, "Blizzard_CompactRaidFrames")
    end

    self:TryHookCompactContainers()
    self:TryHookCompactFrames()
    self:RegisterEvent("PLAYER_LOGIN")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    self:RegisterEvent("UNIT_AURA")
    pcall(self.RegisterEvent, self, "EDIT_MODE_LAYOUTS_UPDATED")

    if self.RegisterOptions then
        self:RegisterOptions()
    end
    if self.InitializeObjectiveCarriers then
        self:InitializeObjectiveCarriers()
    end

    self:ApplySettings(true)
    self:ForEachTrackedFrame(function(frame)
        self:HookFrameScripts(frame)
    end)
end

RaidFrameAuras:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName == addonName then
            -- Embedded in KallyeRaidFrames: wait for ns.LoadRaidFramesAuras()
            if not ns.LoadRaidFramesAuras then
                -- self:Initialize() -- FIXME::RFA
            end
        elseif loadedName == "Blizzard_CompactRaidFrames" and self.initialized then
            self:ScheduleRefreshBurst("layout")
        elseif loadedName == "Masque" and self.initialized then
            local masqueChanged = false
            if self.InitializeMasque then
                masqueChanged = self:InitializeMasque() == true
            end
            if masqueChanged then
                self:ScheduleRefreshBurst("layout")
            end
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        if self.PrintBlizzardAuraCVarLoginReminder then
            -- self:PrintBlizzardAuraCVarLoginReminder() -- FIXME:RFA
        end
        return
    end

    if event == "UNIT_AURA" then
        local Util = ns.Util
        local perf = Util and Util.PerfBegin and Util.PerfBegin("UnitAura")
        local unit, updateInfo = ...

        if self:IsTrackedUnit(unit) then
            local changed = false

            if not updateInfo or updateInfo.isFullUpdate then
                changed = self:ScanUnitFull(unit) == true
            else
                local ok, deltaChanged = self:ApplyAuraDelta(unit, updateInfo)

                if ok then
                    changed = deltaChanged == true
                else
                    if Util and Util.PerfCount then
                        Util.PerfCount("UnitAuraFullScanFallback")
                    end
                    changed = self:ScanUnitFull(unit) == true
                end
            end

            if changed then
                self:RefreshUnit(unit)
            elseif Util and Util.PerfCount then
                Util.PerfCount("UnitAuraRefreshSkipped")
            end
        end

        if Util and Util.PerfEnd then
            Util.PerfEnd("UnitAura", perf)
        end
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        if self.RefreshCombatSensitiveBuffVisibility then
            self:RefreshCombatSensitiveBuffVisibility()
        elseif self.RefreshLongBuffVisibility then
            self:RefreshLongBuffVisibility()
        end
        self:ScheduleRefreshBurst("combat")
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if self.InvalidateAuraData then
            self:InvalidateAuraData()
        end
        if self.ProcessPendingMasqueUpdate then
            self:ProcessPendingMasqueUpdate()
        end
        if self.ProcessPendingPrivateAuraAnchors then
            self:ProcessPendingPrivateAuraAnchors()
        end
        self:ScheduleRefreshBurst("combat")
        return
    end

    if event == "EDIT_MODE_LAYOUTS_UPDATED" then
        State.layoutVersion = (State.layoutVersion or 0) + 1
        self:ScheduleRefreshBurst("layout")
        return
    end

    if event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_SPECIALIZATION_CHANGED" then
        self:ScheduleRefreshBurst(event == "PLAYER_ENTERING_WORLD" and "world" or "refresh")
    elseif event == "GROUP_ROSTER_UPDATE" then
        self:ScheduleRefreshBurst("roster")
    end
end)

RaidFrameAuras:RegisterEvent("ADDON_LOADED")
