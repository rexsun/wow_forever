local addonName, ns = ...
local l = ns.I18N;

-- * avoid conflict override
if ns.CONFLICT then return; end

local RaidFrameAuras = ns.RaidFrameAuras
if not RaidFrameAuras then return end

local Constants = ns.Constants or {}
local State = ns.State or {}
local Util = ns.Util or {}
local function T(text, ...)
    return Util.T and Util.T(text, ...) or text
end
local MAX_COMPACT_PARTY_FRAMES = Constants.MAX_COMPACT_PARTY_FRAMES or 5
local MAX_RAID_FRAMES = Constants.MAX_RAID_FRAMES or 40
local PRIMARY_REFRESH_DELAY = 0.05
local FALLBACK_REFRESH_DELAY = 0.35
local GENERIC_REFRESH_DELAY = 0.02
local GENERIC_FALLBACK_DELAY = 0.20
local SCAN_QUEUE_DELAY = 0.01
local SCAN_UNITS_PER_TICK = 4
local BLIZZARD_AURA_CVARS = {
    { name = "raidFramesDisplayBuffs", label = "Blizzard raid-frame buffs" },
    { name = "raidFramesDisplayDebuffs", label = "Blizzard raid-frame debuffs" },
}
local BLIZZARD_AURA_CVAR_CONFIRM_POPUP = "RAIDFRAMEAURAS_CONFIRM_DISABLE_BLIZZARD_AURA_CVARS"
local BLIZZARD_AURA_CVAR_CONFIRM_ALL_POPUP = "RAIDFRAMEAURAS_CONFIRM_DISABLE_ALL_BLIZZARD_AURA_CVARS"
local CHAT_PREFIX = "|cff33ff99RaidFrameAuras|r"

local function IsPlayerInCombat()
    if RaidFrameAuras.IsPlayerInCombat then
        return RaidFrameAuras:IsPlayerInCombat()
    end
    local affectingCombat = UnitAffectingCombat and UnitAffectingCombat("player")
    if affectingCombat then return true end
    local inLockdown = InCombatLockdown and InCombatLockdown()
    return inLockdown ~= nil and inLockdown ~= false
end

local function EnsureRosterState()
    State.trackedFrames = State.trackedFrames or setmetatable({}, { __mode = "k" })
    State.trackedFrameList = State.trackedFrameList or {}
    State.unitFrames = State.unitFrames or {}
    State.rosterGUIDs = State.rosterGUIDs or {}
    State.scanQueue = State.scanQueue or {}
    State.scanQueued = State.scanQueued or {}
end

local function SafeGetUnitGUID(unit)
    if RaidFrameAuras.GetUnitCacheGUID then
        return RaidFrameAuras:GetUnitCacheGUID(unit)
    end
    if type(UnitGUID) ~= "function" then return nil end
    local guid = UnitGUID(unit)
    if Util.IsSecretValue and Util.IsSecretValue(guid) then return nil end
    return guid
end

local function AddUnitFrame(unit, frame)
    if type(unit) ~= "string" then return end
    local frames = State.unitFrames[unit]
    if not frames then
        frames = {}
        State.unitFrames[unit] = frames
    end
    frames[#frames + 1] = frame
end

local function MaybeFlushPerfSummary(reason)
    if not State.perfFlushPending then return end
    if State.refreshBurstPending or State.scanQueuePending then return end
    if State.scanQueue and #State.scanQueue > 0 then return end
    State.perfFlushPending = nil
    Util.PerfFlush(reason or State.perfReason)
end

function RaidFrameAuras:HideUnitFrames(unit)
    EnsureRosterState()
    local frames = State.unitFrames[unit]
    if not frames then return end
    for i = 1, #frames do
        self:HideFrameAuras(frames[i])
    end
end

function RaidFrameAuras:QueueUnitAuraScan(unit, priority)
    if not self:IsTrackedUnit(unit) or not UnitExists(unit) then return false end
    EnsureRosterState()
    if State.scanQueued[unit] then return false end
    State.scanQueued[unit] = true
    if priority then
        table.insert(State.scanQueue, 1, unit)
    else
        State.scanQueue[#State.scanQueue + 1] = unit
    end
    Util.PerfCount("QueueUnitScan")
    self:ScheduleAuraScanQueue()
    return true
end

function RaidFrameAuras:ScheduleAuraScanQueue()
    EnsureRosterState()
    if State.scanQueuePending then return end
    if #State.scanQueue == 0 then
        MaybeFlushPerfSummary(State.perfReason)
        return
    end
    State.scanQueuePending = true
    State.scanQueueToken = (State.scanQueueToken or 0) + 1
    local token = State.scanQueueToken

    local function RunQueue()
        if token ~= State.scanQueueToken then return end
        State.scanQueuePending = false
        RaidFrameAuras:ProcessAuraScanQueue()
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(SCAN_QUEUE_DELAY, RunQueue)
    else
        RunQueue()
    end
end

function RaidFrameAuras:ProcessAuraScanQueue()
    EnsureRosterState()
    local perf = Util.PerfBegin("ScanQueueTick")
    local processed = 0
    while processed < SCAN_UNITS_PER_TICK and #State.scanQueue > 0 do
        local unit = table.remove(State.scanQueue, 1)
        State.scanQueued[unit] = nil
        processed = processed + 1

        if self:IsTrackedUnit(unit) and UnitExists(unit) then
            local cache = State.auraCache and State.auraCache[unit]
            local scanned = true
            if not cache or not cache.hasFullScan or (self.IsAuraCacheStale and self:IsAuraCacheStale(unit, cache)) then
                scanned = self:ScanUnitFull(unit)
                cache = State.auraCache and State.auraCache[unit]
            end
            if scanned ~= false and cache and cache.hasFullScan then
                self:RefreshUnit(unit)
            end
        end
    end
    Util.PerfEnd("ScanQueueTick", perf)

    if #State.scanQueue > 0 then
        self:ScheduleAuraScanQueue()
    else
        MaybeFlushPerfSummary(State.perfReason)
    end
end

function RaidFrameAuras:RefreshFrame(frame, options)
    if not Util.IsCompactUnitFrame(frame) then return end
    Util.PerfCount("RefreshFrame")
    local perf = Util.PerfBegin("RefreshFrame")
    options = options or {}
    local unit = Util.GetFrameUnit(frame)
    frame.rfaUnit = unit
    if not self:IsTrackedUnit(unit) or not frame:IsVisible() then
        self:HideFrameAuras(frame)
        Util.PerfEnd("RefreshFrame", perf)
        return
    end

    local cache = State.auraCache[unit]
    if cache and self.IsAuraCacheStale and self:IsAuraCacheStale(unit, cache) then
        if self.ClearAuraCache then
            self:ClearAuraCache(unit)
        else
            State.auraCache[unit] = nil
        end
        cache = nil
        self:HideFrameAuras(frame)
    end
    if not cache or not cache.hasFullScan then
        if options.allowImmediateScan == true then
            self:ScanUnitFull(unit)
            cache = State.auraCache[unit]
        else
            self:ApplyAuraLayout(frame, "BUFF", 0)
            self:ApplyAuraLayout(frame, "DEBUFF", 0)
            self:QueueUnitAuraScan(unit, true)
            self:HideFrameAuras(frame)
            if self.RefreshPrivateAuraAnchors then
                self:RefreshPrivateAuraAnchors(frame)
            end
            if self.RefreshObjectiveCarrierIcon then
                self:RefreshObjectiveCarrierIcon(frame)
            end
            Util.PerfEnd("RefreshFrame", perf)
            return
        end
    end

    self:ApplyAuraLayout(frame, "BUFF", 0)
    self:ApplyAuraLayout(frame, "DEBUFF", 0)

    if self.db.showBuffs then
        self:UpdateAuraIcons(frame, "BUFF")
    else
        self:HideFrameAuraType(frame, "BUFF")
    end
    if self.db.showDebuffs then
        self:UpdateAuraIcons(frame, "DEBUFF")
    else
        self:HideFrameAuraType(frame, "DEBUFF")
    end
    if self.RefreshPrivateAuraAnchors then
        self:RefreshPrivateAuraAnchors(frame)
    end
    if self.RefreshObjectiveCarrierIcon then
        self:RefreshObjectiveCarrierIcon(frame)
    end
    Util.PerfEnd("RefreshFrame", perf)
end

local function ForEachCompactFrameFromContainer(container, callback, visited)
    if not container then return end
    local frames = container.memberUnitFrames
    if type(frames) == "table" then
        for _, frame in pairs(frames) do
            if Util.IsCompactUnitFrame(frame) and not visited[frame] then
                visited[frame] = true
                callback(frame)
            end
        end
    end
end

local function ForEachDiscoveredCompactFrame(callback)
    if type(callback) ~= "function" then return end
    local visited = {}

    ForEachCompactFrameFromContainer(CompactPartyFrame, callback, visited)
    ForEachCompactFrameFromContainer(CompactArenaFrame, callback, visited)

    for _, prefix in ipairs({ "CompactPartyFrameMember", "CompactArenaFrameMember", "CompactRaidFrame" }) do
        local maxIndex = prefix == "CompactRaidFrame" and MAX_RAID_FRAMES or MAX_COMPACT_PARTY_FRAMES
        for i = 1, maxIndex do
            local frame = _G[prefix .. i]
            if Util.IsCompactUnitFrame(frame) and not visited[frame] then
                visited[frame] = true
                callback(frame)
            end
        end
    end

    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if Util.IsCompactUnitFrame(frame) and not visited[frame] then
                visited[frame] = true
                callback(frame)
            end
        end
    end

    if CompactRaidFrameContainer and type(CompactRaidFrameContainer.flowFrames) == "table" then
        for _, frame in pairs(CompactRaidFrameContainer.flowFrames) do
            if Util.IsCompactUnitFrame(frame) and not visited[frame] then
                visited[frame] = true
                callback(frame)
            end
        end
    end
end

function RaidFrameAuras:RebuildTrackedFrameRegistry()
    EnsureRosterState()
    wipe(State.trackedFrames)
    wipe(State.trackedFrameList)
    wipe(State.unitFrames)

    ForEachDiscoveredCompactFrame(function(frame)
        State.trackedFrames[frame] = true
        State.trackedFrameList[#State.trackedFrameList + 1] = frame
        self:HookFrameScripts(frame)

        local unit = Util.GetFrameUnit(frame)
        frame.rfaUnit = unit
        if self:IsTrackedUnit(unit) then
            AddUnitFrame(unit, frame)
        end
    end)
    State.trackedRegistryReady = true
end

function RaidFrameAuras:ForEachTrackedFrame(callback)
    if type(callback) ~= "function" then return end
    EnsureRosterState()
    if not State.trackedRegistryReady then
        self:RebuildTrackedFrameRegistry()
    end
    for i = 1, #State.trackedFrameList do
        local frame = State.trackedFrameList[i]
        if Util.IsCompactUnitFrame(frame) then
            callback(frame)
        end
    end
end

function RaidFrameAuras:RefreshUnit(unit)
    if not self:IsTrackedUnit(unit) then return end
    EnsureRosterState()
    if not State.trackedRegistryReady then
        self:RebuildTrackedFrameRegistry()
    end
    local frames = State.unitFrames[unit]
    if not frames then return end
    for i = 1, #frames do
        self:RefreshFrame(frames[i])
    end
end

function RaidFrameAuras:RefreshFrames(skipRegistryRebuild)
    local perf = Util.PerfBegin("RefreshFrames")
    if not skipRegistryRebuild then
        self:RebuildTrackedFrameRegistry()
    end
    if not self.db or not self.db.enabled then
        self:ForEachTrackedFrame(function(frame)
            self:HideFrameAuras(frame)
        end)
        Util.PerfEnd("RefreshFrames", perf)
        return
    end
    self:ForEachTrackedFrame(function(frame)
        self:RefreshFrame(frame)
    end)
    Util.PerfEnd("RefreshFrames", perf)
end

function RaidFrameAuras:SyncRosterAuraCaches()
    EnsureRosterState()
    local seen = {}

    local inCombat = IsPlayerInCombat()

    for unit in pairs(State.unitFrames) do
        if self:IsTrackedUnit(unit) and UnitExists(unit) then
            seen[unit] = true
            local guid = SafeGetUnitGUID(unit)
            local previousGUID = State.rosterGUIDs[unit]

            -- 12.x safety: during combat, UnitGUID for restricted units may be
            -- unavailable/secret. Do not convert that into a fake GUID change,
            -- because clearing the aura cache here also drops the out-of-combat
            -- long-buff markers used by "Only in combat" hiding. Resync normally
            -- once the real GUID is available again, or after combat ends.
            if guid == nil and inCombat and previousGUID ~= nil then
                -- Preserve the existing cache and marker tables for the combat pull.
            else
                guid = guid or false
                if previousGUID ~= guid then
                    State.rosterGUIDs[unit] = guid
                    if self.ClearAuraCache then
                        self:ClearAuraCache(unit)
                    else
                        State.auraCache[unit] = nil
                    end
                    self:HideUnitFrames(unit)
                    self:QueueUnitAuraScan(unit, true)
                end
            end
        end
    end

    for unit in pairs(State.rosterGUIDs) do
        if not seen[unit] then
            State.rosterGUIDs[unit] = nil
            State.scanQueued[unit] = nil
            if self.ClearAuraCache then
                self:ClearAuraCache(unit)
            else
                State.auraCache[unit] = nil
            end
            self:HideUnitFrames(unit)
        end
    end
end

local function RunRefreshBurst(reason, isFallback)
    local perf = Util.PerfBegin("RunRefreshBurst")
    State.inRefreshBurst = true
    RaidFrameAuras:TryHookCompactContainers()
    RaidFrameAuras:TryHookCompactFrames()
    RaidFrameAuras:RebuildTrackedFrameRegistry()
    RaidFrameAuras:SyncRosterAuraCaches()
    if RaidFrameAuras.ClearStalePrivateAuraAnchors then
        RaidFrameAuras:ClearStalePrivateAuraAnchors()
    end
    if RaidFrameAuras.RefreshLongBuffVisibility
        and RaidFrameAuras.db
        and RaidFrameAuras.db.directBuffHideLong == true
        and IsPlayerInCombat() then
        -- A combat refresh burst can run a fraction after PLAYER_REGEN_DISABLED
        -- and after Blizzard has reassigned compact frames. Apply the cached
        -- long-buff visibility pass again before painting frames so timing or
        -- boss-pull frame updates cannot leave marked buffs visible. The helper
        -- itself is cheap when no long-buff markers exist and does not rewrite
        -- cache arrays unless it actually removes something.
        RaidFrameAuras:RefreshLongBuffVisibility()
    end
    RaidFrameAuras:RefreshFrames(true)
    State.inRefreshBurst = nil
    Util.PerfEnd("RunRefreshBurst", perf)
    if isFallback then
        MaybeFlushPerfSummary(reason)
    end
end

local function GetRefreshDelays(reason)
    if reason == "roster" or reason == "container" or reason == "world" or reason == "layout" then
        return PRIMARY_REFRESH_DELAY, FALLBACK_REFRESH_DELAY
    end
    return GENERIC_REFRESH_DELAY, GENERIC_FALLBACK_DELAY
end

function RaidFrameAuras:ScheduleRefreshBurst(reason)
    EnsureRosterState()
    reason = reason or "refresh"
    State.trackedRegistryReady = false
    if Util.IsPerfEnabled() then
        Util.PerfReset(reason)
        State.perfFlushPending = true
        State.perfReason = reason
    end
    State.refreshBurstPending = true
    State.refreshBurstToken = (State.refreshBurstToken or 0) + 1
    local token = State.refreshBurstToken
    local primaryDelay, fallbackDelay = GetRefreshDelays(reason)

    local function RunScheduledRefresh(isFallback)
        if token ~= State.refreshBurstToken then return end
        RunRefreshBurst(reason, isFallback)
        if isFallback then
            State.refreshBurstPending = false
            MaybeFlushPerfSummary(reason)
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(primaryDelay, function()
            RunScheduledRefresh(false)
        end)
        C_Timer.After(fallbackDelay, function()
            RunScheduledRefresh(true)
        end)
    else
        RunScheduledRefresh(false)
        State.refreshBurstPending = false
        MaybeFlushPerfSummary(reason)
    end
end

function RaidFrameAuras:TryHookCompactContainers()
    local specs = {
        { frame = CompactPartyFrame, method = "RefreshMembers" },
        { frame = CompactArenaFrame, method = "RefreshMembers" },
        { frame = CompactRaidFrameContainer, method = "TryUpdate" },
    }
    for _, spec in ipairs(specs) do
        local container = spec.frame
        if container and type(container[spec.method]) == "function" and not State.hookedContainers[container] then
            hooksecurefunc(container, spec.method, function()
                RaidFrameAuras:ScheduleRefreshBurst("container")
            end)
            State.hookedContainers[container] = true
        end
    end
end

function RaidFrameAuras:TryHookCompactFrames()
    if self.compactHooksInstalled then return true end
    if type(CompactUnitFrame_UpdateAll) ~= "function" or type(CompactUnitFrame_SetUnit) ~= "function" then
        return false
    end
    hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
        RaidFrameAuras:RefreshFrame(frame)
    end)
    hooksecurefunc("CompactUnitFrame_SetUnit", function(frame)
        RaidFrameAuras:ScheduleRefreshBurst("frame")
    end)
    self.compactHooksInstalled = true
    return true
end

local function GetSafeResizeNumber(value)
    if Util.AsSafeNumber then
        return Util.AsSafeNumber(value)
    end
    if Util.IsSecretValue and Util.IsSecretValue(value) then
        return nil
    end
    value = tonumber(value)
    if (Util.IsSecretValue and Util.IsSecretValue(value)) or not value or value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

local function GetSafePositiveSize(value)
    value = GetSafeResizeNumber(value)
    if not value or value <= 0 then
        return nil
    end
    return value
end

function RaidFrameAuras:HandleFrameSizeChanged(frame, width, height)
    local db = self.db
    if not frame or not db or (db.buffAutoScale ~= true and db.debuffAutoScale ~= true) then
        return
    end

    width = GetSafePositiveSize(width)
    height = GetSafePositiveSize(height)

    local state = self.GetFrameState and self:GetFrameState(frame) or nil
    if state then
        local previousWidth = GetSafeResizeNumber(state.autoScaleLastWidth)
        local previousHeight = GetSafeResizeNumber(state.autoScaleLastHeight)
        if width and height and previousWidth and previousHeight and math.abs(previousWidth - width) < 0.5 and math.abs(previousHeight - height) < 0.5 then
            return
        end
        state.autoScaleLastWidth = width
        state.autoScaleLastHeight = height
        state.buffLayoutCacheKey = nil
        state.debuffLayoutCacheKey = nil
    end

    State.frameSizeRefreshPending = State.frameSizeRefreshPending or setmetatable({}, { __mode = "k" })
    if State.frameSizeRefreshPending[frame] then return end
    State.frameSizeRefreshPending[frame] = true

    local function RefreshResizedFrame()
        State.frameSizeRefreshPending[frame] = nil
        RaidFrameAuras:RefreshFrame(frame)
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, RefreshResizedFrame)
    else
        RefreshResizedFrame()
    end
end

function RaidFrameAuras:HookFrameScripts(frame)
    if not frame or State.hookedFrames[frame] then return end
    frame:HookScript("OnShow", function(shownFrame)
        RaidFrameAuras:RefreshFrame(shownFrame)
    end)
    frame:HookScript("OnHide", function(hiddenFrame)
        RaidFrameAuras:HideFrameAuras(hiddenFrame)
    end)
    frame:HookScript("OnSizeChanged", function(resizedFrame, width, height)
        RaidFrameAuras:HandleFrameSizeChanged(resizedFrame, width, height)
    end)
    State.hookedFrames[frame] = true
end

local function SafeGetCVar(name)
    if not GetCVar then return nil end
    local ok, value = pcall(GetCVar, name)
    if ok then return value end
end

local function SafeSetCVar(name, value)
    if not SetCVar or value == nil then return false end
    local ok = pcall(SetCVar, name, value)
    return ok == true
end

local function PrintCVarMessage(message)
    print(CHAT_PREFIX .. " " .. tostring(message or ""))
end

local function FindBlizzardAuraCVar(name)
    for _, spec in ipairs(BLIZZARD_AURA_CVARS) do
        if spec.name == name then
            return spec
        end
    end
end

local function SetBlizzardAuraCVar(name, value)
    local before = SafeGetCVar(name)
    local ok = SafeSetCVar(name, value)
    local after = SafeGetCVar(name)
    if ok then
        if tostring(before) ~= tostring(after or value) then
            PrintCVarMessage(T("%s changed from %s to %s.", name, tostring(before), tostring(after or value)))
        else
            PrintCVarMessage(T("%s is already %s.", name, tostring(after or value)))
        end
    else
        PrintCVarMessage(T("Could not change %s.", tostring(name)))
    end
    return ok
end

local function GetBlizzardAuraCVarPopupKey(spec)
    return BLIZZARD_AURA_CVAR_CONFIRM_POPUP .. "_" .. tostring(spec and spec.name or "UNKNOWN")
end

local function EnsureDisableBlizzardAuraCVarPopup(spec)
    if not StaticPopupDialogs or not spec then
        return nil
    end
    local popupKey = GetBlizzardAuraCVarPopupKey(spec)
    if StaticPopupDialogs[popupKey] then
        return popupKey
    end

    StaticPopupDialogs[popupKey] = {
        text = T("Raid Frame Auras will set %s to 0. This hides %s until you restore the default. Continue?", spec.name, T(spec.label)),
        button1 = T("Confirm"),
        button2 = T("Cancel"),
        OnAccept = function()
            RaidFrameAuras:SetBlizzardAuraCVarHidden(spec.name, true)
        end,
        OnCancel = function()
            if RaidFrameAuras.RefreshOptionControls then
                RaidFrameAuras:RefreshOptionControls()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    return popupKey
end

local function EnsureDisableAllBlizzardAuraCVarsPopup()
    if not StaticPopupDialogs or StaticPopupDialogs[BLIZZARD_AURA_CVAR_CONFIRM_ALL_POPUP] then
        return BLIZZARD_AURA_CVAR_CONFIRM_ALL_POPUP
    end

    StaticPopupDialogs[BLIZZARD_AURA_CVAR_CONFIRM_ALL_POPUP] = {
        text = T("Raid Frame Auras will set raidFramesDisplayBuffs and raidFramesDisplayDebuffs to 0. This hides Blizzard's built-in raid-frame auras until you restore the defaults. Continue?"),
        button1 = T("Confirm"),
        button2 = T("Cancel"),
        OnAccept = function()
            RaidFrameAuras:SetBlizzardAuraCVarsHidden(true)
        end,
        OnCancel = function()
            if RaidFrameAuras.RefreshOptionControls then
                RaidFrameAuras:RefreshOptionControls()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    return BLIZZARD_AURA_CVAR_CONFIRM_ALL_POPUP
end

function RaidFrameAuras:GetBlizzardAuraCVar(name)
    if not FindBlizzardAuraCVar(name) then return nil end
    return SafeGetCVar(name)
end

function RaidFrameAuras:IsBlizzardAuraCVarHidden(name)
    if not FindBlizzardAuraCVar(name) then return false end
    return tostring(SafeGetCVar(name)) == "0"
end

function RaidFrameAuras:AreBlizzardAuraCVarsHidden()
    for _, spec in ipairs(BLIZZARD_AURA_CVARS) do
        if not self:IsBlizzardAuraCVarHidden(spec.name) then
            return false
        end
    end
    return true
end

function RaidFrameAuras:SetBlizzardAuraCVarHidden(name, hidden)
    local spec = FindBlizzardAuraCVar(name)
    if not spec then return end
    SetBlizzardAuraCVar(spec.name, hidden and "0" or "1")
    if self.RefreshOptionControls then
        self:RefreshOptionControls()
    end
end

function RaidFrameAuras:SetBlizzardAuraCVarsHidden(hidden)
    local value = hidden and "0" or "1"
    for _, spec in ipairs(BLIZZARD_AURA_CVARS) do
        SetBlizzardAuraCVar(spec.name, value)
    end
    if self.RefreshOptionControls then
        self:RefreshOptionControls()
    end
end

function RaidFrameAuras:RequestHideBlizzardAuraCVar(name)
    local spec = FindBlizzardAuraCVar(name)
    if not spec then return end
    local popupKey = EnsureDisableBlizzardAuraCVarPopup(spec)
    if popupKey and StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs[popupKey] then
        StaticPopup_Show(popupKey)
    else
        PrintCVarMessage(T("Could not open the confirmation popup; the CVar was not changed."))
        if self.RefreshOptionControls then
            self:RefreshOptionControls()
        end
    end
end

function RaidFrameAuras:RequestHideBlizzardAuraCVars()
    local popupKey = EnsureDisableAllBlizzardAuraCVarsPopup()
    if popupKey and StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs[popupKey] then
        StaticPopup_Show(popupKey)
    else
        PrintCVarMessage(T("Could not open the confirmation popup; CVars were not changed."))
        if self.RefreshOptionControls then
            self:RefreshOptionControls()
        end
    end
end

function RaidFrameAuras:RestoreBlizzardAuraCVarDefaults()
    self:SetBlizzardAuraCVarsHidden(false)
end

function RaidFrameAuras:PrintBlizzardAuraCVarLoginReminder()
    local disabled = {}
    for _, spec in ipairs(BLIZZARD_AURA_CVARS) do
        if tostring(SafeGetCVar(spec.name)) == "0" then
            disabled[#disabled + 1] = spec.name
        end
    end
    if #disabled > 0 then
        PrintCVarMessage(T("Blizzard raid-frame aura CVars hidden by RFA: %s. Open |cffffd966/rfa|r to restore them if needed.", table.concat(disabled, ", ")))
    end
end
