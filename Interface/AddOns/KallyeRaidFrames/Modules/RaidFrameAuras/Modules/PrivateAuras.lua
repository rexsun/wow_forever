local addonName, ns = ...
local l = ns.I18N;

-- * avoid conflict override
if ns.CONFLICT then return; end

local RaidFrameAuras = ns.RaidFrameAuras
if not RaidFrameAuras then return end

local Constants = ns.Constants or {}
local DEFAULTS = ns.DEFAULTS or {}
local State = ns.State or {}
local Util = ns.Util or {}
local C_UnitAuras = C_UnitAuras
local AddPrivateAuraAnchor = C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor
local RemovePrivateAuraAnchor = C_UnitAuras and C_UnitAuras.RemovePrivateAuraAnchor
local MAX_PRIVATE_AURA_SLOTS = Constants.MAX_PRIVATE_AURA_SLOTS or 4
local PRIVATE_AURA_FRAME_STRATA = "HIGH"

local function IsPlayerInCombat()
    if RaidFrameAuras.IsPlayerInCombat then
        return RaidFrameAuras:IsPlayerInCombat()
    end
    local affectingCombat = UnitAffectingCombat and UnitAffectingCombat("player")
    if affectingCombat then return true end
    local inLockdown = InCombatLockdown and InCombatLockdown()
    return inLockdown ~= nil and inLockdown ~= false
end

local function DebugLog(text, ...)
    if Util.DebugLog then
        Util.DebugLog(text, ...)
    end
end

local function MarkPrivateAuraRefreshPending()
    State.privateAuraRefreshPending = true
end

local function HasPrivateAuraAPI()
    return type(AddPrivateAuraAnchor) == "function" and type(RemovePrivateAuraAnchor) == "function"
end

local function SafeRemovePrivateAuraAnchor(anchorID)
    if not anchorID or type(RemovePrivateAuraAnchor) ~= "function" then return true end
    local ok, err = pcall(RemovePrivateAuraAnchor, anchorID)
    if not ok then
        DebugLog("private aura anchor remove failed: %s", tostring(err))
    end
    return ok
end

local function ClearAnchorIDs(state)
    local anchorIDs = state and state.privateAuraAnchorIDs
    if not anchorIDs then return true end
    local ok = true
    local failed
    for i = 1, #anchorIDs do
        if not SafeRemovePrivateAuraAnchor(anchorIDs[i]) then
            ok = false
            failed = failed or {}
            failed[#failed + 1] = anchorIDs[i]
        end
    end
    wipe(anchorIDs)
    if failed then
        for i = 1, #failed do
            anchorIDs[i] = failed[i]
        end
        MarkPrivateAuraRefreshPending()
    else
        state.privateAuraUnit = nil
        state.privateAuraAnchorKey = nil
    end
    return ok
end

local function HideHolderFrames(state)
    local frames = state and state.privateAuraFrames
    if not frames then return end
    for i = 1, #frames do
        frames[i]:Hide()
    end
end

local function HasPrivateAuraState(state)
    if not state then return false end
    if state.privateAuraUnit ~= nil or state.privateAuraLayoutKey ~= nil or state.privateAuraAnchorKey ~= nil then
        return true
    end
    if state.privateAuraAnchorIDs and #state.privateAuraAnchorIDs > 0 then
        return true
    end
    return state.privateAuraFrames and #state.privateAuraFrames > 0
end

local function SetFrameLayer(frame, strata, level)
    if not frame then return end
    if strata and frame.rfaPrivateAuraStrata ~= strata then
        frame:SetFrameStrata(strata)
        frame.rfaPrivateAuraStrata = strata
    end
    if level and frame.rfaPrivateAuraLevel ~= level then
        frame:SetFrameLevel(level)
        frame.rfaPrivateAuraLevel = level
    end
end

local function SetHolderGeometry(holder, size, scale)
    if not holder then return end
    size = Util.AsSafeNumber and Util.AsSafeNumber(size, DEFAULTS.debuffSize or 16) or tonumber(size) or DEFAULTS.debuffSize or 16
    if not size or size <= 0 then
        size = DEFAULTS.debuffSize or 16
    end
    scale = Util.AsSafeNumber and Util.AsSafeNumber(scale, 1) or tonumber(scale) or 1
    if not scale or scale <= 0 then
        scale = 1
    end
    local key = tostring(math.floor(size * 100 + 0.5)) .. ":" .. tostring(math.floor(scale * 100 + 0.5))
    if holder.rfaPrivateAuraGeometryKey == key then return end
    holder:SetScale(scale)
    holder:SetSize(size, size)
    holder.rfaLayoutWidth = size
    holder.rfaLayoutHeight = size
    holder.rfaLayoutScale = 1
    holder.rfaPrivateAuraGeometryKey = key
end

local function ConfigureHolder(holder)
    if not holder then return end
    holder:EnableMouse(true)
    if holder.SetMouseClickEnabled then
        holder:SetMouseClickEnabled(false)
    end
    if holder.SetPropagateMouseMotion then
        holder:SetPropagateMouseMotion(true)
    end
    if holder.SetPropagateMouseClicks then
        holder:SetPropagateMouseClicks(true)
    end
end

local function GetPrivateAuraDurationSink()
    if State.privateAuraDurationSink then
        return State.privateAuraDurationSink
    end

    local parent = UIParent or RFA_Core
    local sink = RaidFrameAuras:CreatePrivateFrame("Frame", "PrivateAuraDurationSink", parent)
    sink:SetSize(1, 1)
    sink:ClearAllPoints()
    sink:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", -10000, -10000)
    State.privateAuraDurationSink = sink
    return sink
end

local function EnsurePrivateAuraState(frame)
    local state = RaidFrameAuras:GetFrameState(frame)
    if not state then return nil end
    state.privateAuraFrames = state.privateAuraFrames or {}
    state.privateAuraAnchorIDs = state.privateAuraAnchorIDs or {}
    return state
end

local function CreateHolderFrame(frame)
    local holder = RaidFrameAuras:CreatePrivateFrame("Frame", "PrivateAuraHolder", frame)
    holder.unitFrame = frame
    holder:Hide()
    ConfigureHolder(holder)
    return holder
end

local function EnsureHolderCount(frame, state, count, parent)
    local holders = state.privateAuraFrames
    for i = #holders + 1, count do
        holders[i] = CreateHolderFrame(frame)
    end
    for i = 1, #holders do
        local holder = holders[i]
        if i <= count then
            holder:SetParent(parent or frame)
        else
            holder:Hide()
        end
    end
    return holders
end

function RaidFrameAuras:GetPrivateAuraLayoutConfig(frame, unit)
    local db = RaidFrameAuras.db or DEFAULTS
    local maxSlots = Util.Clamp(db.privateAuraMax, 1, MAX_PRIVATE_AURA_SLOTS, DEFAULTS.privateAuraMax or MAX_PRIVATE_AURA_SLOTS)
    maxSlots = math.min(MAX_PRIVATE_AURA_SLOTS, math.floor(maxSlots + 0.5))
    local baseSize = RaidFrameAuras.GetAuraBaseSize and RaidFrameAuras:GetAuraBaseSize("DEBUFF", frame) or Util.Clamp(db.debuffSize, 4, 80, DEFAULTS.debuffSize or 16)
    local configuredSize = RaidFrameAuras.GetAuraConfiguredSize and RaidFrameAuras:GetAuraConfiguredSize("DEBUFF") or Util.Clamp(db.debuffSize, 4, 80, DEFAULTS.debuffSize or 16)
    configuredSize = Util.AsSafeNumber and Util.AsSafeNumber(configuredSize, baseSize) or tonumber(configuredSize) or baseSize
    local scale = Util.Clamp(db.privateAuraScale, Constants.CATEGORY_SCALE_MIN or 0.5, Constants.CATEGORY_SCALE_MAX or 2, DEFAULTS.privateAuraScale or 1)
    local size = math.max(4, baseSize * scale)
    local holderScale = configuredSize and configuredSize > 0 and (size / configuredSize) or scale
    holderScale = Util.Clamp(holderScale, 0.05, 4, scale)
    local holderSize = size / holderScale
    local anchor = db.privateAuraAnchor or DEFAULTS.privateAuraAnchor or "TOPLEFT"
    local growth = db.privateAuraGrowth or DEFAULTS.privateAuraGrowth or "RIGHT_UP"
    local wrap = Util.Clamp(db.privateAuraWrap, 1, MAX_PRIVATE_AURA_SLOTS, DEFAULTS.privateAuraWrap or 4)
    wrap = math.min(MAX_PRIVATE_AURA_SLOTS, math.floor(wrap + 0.5))
    local paddingX = tonumber(db.debuffPaddingX) or DEFAULTS.debuffPaddingX or 0
    local paddingY = tonumber(db.debuffPaddingY) or DEFAULTS.debuffPaddingY or 0
    local offsetX = tonumber(db.privateAuraOffsetX) or DEFAULTS.privateAuraOffsetX or 0
    local offsetY = tonumber(db.privateAuraOffsetY) or DEFAULTS.privateAuraOffsetY or 0
    local anchorTarget = RaidFrameAuras.GetAuraAnchorTarget and RaidFrameAuras:GetAuraAnchorTarget(frame) or frame
    -- Blizzard's private aura renderer creates its own child frames and can
    -- reset their frame level. Keep holders on HIGH strata so boss debuffs
    -- stay above Blizzard compact frame content regardless of that reset.
    local strata = PRIVATE_AURA_FRAME_STRATA
    local frameLevel = frame and frame.GetFrameLevel and frame:GetFrameLevel() or 1
    local level = frameLevel + (tonumber(db.auraFrameLevel) or DEFAULTS.auraFrameLevel or 35)
    local showCountdown = db.debuffHideSwipe ~= true

    return {
        unit = unit,
        maxSlots = maxSlots,
        size = size,
        scale = scale,
        holderSize = holderSize,
        holderScale = holderScale,
        borderScale = 1 / holderScale,
        anchor = anchor,
        growth = growth,
        wrap = wrap,
        offsetX = offsetX,
        offsetY = offsetY,
        paddingX = paddingX,
        paddingY = paddingY,
        anchorTarget = anchorTarget,
        parent = frame,
        strata = strata,
        level = level,
        showCountdown = showCountdown,
        showNumbers = false,
    }
end

local function BuildPrivateAuraConfig(frame, unit)
    return RaidFrameAuras:GetPrivateAuraLayoutConfig(frame, unit)
end

local function BuildLayoutKey(frame, config)
    return tostring(config.unit)
        .. ":" .. tostring(config.maxSlots)
        .. ":" .. tostring(math.floor((tonumber(config.size) or 0) * 100 + 0.5))
        .. ":" .. tostring(math.floor((tonumber(config.holderSize) or 0) * 100 + 0.5))
        .. ":" .. tostring(math.floor((tonumber(config.holderScale) or 0) * 100 + 0.5))
        .. ":" .. tostring(config.anchor)
        .. ":" .. tostring(config.growth)
        .. ":" .. tostring(config.wrap)
        .. ":" .. tostring(config.offsetX)
        .. ":" .. tostring(config.offsetY)
        .. ":" .. tostring(config.paddingX)
        .. ":" .. tostring(config.paddingY)
        .. ":" .. tostring(config.anchorTarget)
        .. ":" .. tostring(config.strata)
        .. ":" .. tostring(config.level)
        .. ":" .. tostring(config.showCountdown)
        .. ":" .. tostring(config.showNumbers)
        .. ":" .. tostring(State.layoutVersion or 0)
        .. ":" .. tostring(frame and frame:GetFrameLevel() or 0)
end

local function ApplyHolderLayout(frame, state, config)
    local holders = EnsureHolderCount(frame, state, config.maxSlots, config.parent)
    local holderScale = tonumber(config.holderScale) or 1
    if holderScale <= 0 then holderScale = 1 end
    local holderSize = config.holderSize or config.size
    for i = 1, config.maxSlots do
        local holder = holders[i]
        SetHolderGeometry(holder, holderSize, holderScale)
        SetFrameLayer(holder, config.strata, config.level)
        holder.rfaPrivateAuraSlot = i
        holder:Show()
    end
    Util.PositionScaledIconStack(holders, config.maxSlots, {
        relativeTo = config.anchorTarget,
        size = holderSize,
        anchor = config.anchor,
        growth = config.growth,
        wrap = config.wrap,
        offsetX = (config.offsetX or 0) / holderScale,
        offsetY = (config.offsetY or 0) / holderScale,
        paddingX = (config.paddingX or 0) / holderScale,
        paddingY = (config.paddingY or 0) / holderScale,
    })
end

local function BuildIconInfo(holder, config)
    local size = config and (config.holderSize or config.size) or DEFAULTS.debuffSize or 16
    size = math.max(1, math.floor((tonumber(size) or DEFAULTS.debuffSize or 16) + 0.5))
    local borderScale = tonumber(config and config.borderScale) or 1
    return {
        iconWidth = size,
        iconHeight = size,
        borderScale = borderScale,
        iconAnchor = {
            point = "CENTER",
            relativeTo = holder,
            relativePoint = "CENTER",
            offsetX = 0,
            offsetY = 0,
        },
    }
end

local function BuildDurationAnchor(holder, config)
    local sink = GetPrivateAuraDurationSink() or holder
    return {
        point = "CENTER",
        relativeTo = sink,
        relativePoint = "CENTER",
        offsetX = 0,
        offsetY = 0,
    }
end

local function ForceFrameLevelRefresh(frame)
    if not frame then return end
    local level = frame:GetFrameLevel()
    frame:SetFrameLevel(0)
    frame:SetFrameLevel(level)
    frame.rfaPrivateAuraLevel = level
end

local function RegisterPrivateAuraAnchors(state, config, rebindOnly)
    if not HasPrivateAuraAPI() then return false end
    if not config or not config.unit or config.maxSlots <= 0 then return false end
    if not ClearAnchorIDs(state) then return false end

    local holders = state.privateAuraFrames
    local count = math.min(config.maxSlots, holders and #holders or 0)
    if count <= 0 then return false end

    local okCount = 0
    for i = 1, count do
        local holder = holders[i]
        if holder then
            if not rebindOnly then
                holder:Show()
            end
            local ok, anchorID = pcall(AddPrivateAuraAnchor, {
                unitToken = config.unit,
                auraIndex = i,
                parent = holder,
                showCountdownFrame = config.showCountdown,
                showCountdownNumbers = config.showNumbers,
                iconInfo = BuildIconInfo(holder, config),
                durationAnchor = BuildDurationAnchor(holder, config),
                isContainer = false,
            })
            if ok and anchorID then
                state.privateAuraAnchorIDs[#state.privateAuraAnchorIDs + 1] = anchorID
                okCount = okCount + 1
                ForceFrameLevelRefresh(holder)
            elseif not ok then
                DebugLog("private aura anchor add failed unit=%s slot=%s error=%s", tostring(config.unit), tostring(i), tostring(anchorID))
            end
        end
    end

    if okCount > 0 then
        state.privateAuraUnit = config.unit
        state.privateAuraAnchorKey = BuildLayoutKey(nil, config)
        return true
    end
    MarkPrivateAuraRefreshPending()
    return false
end

local function ShouldShowPrivateAuras(frame, unit)
    local db = RaidFrameAuras.db
    if not db or db.enabled ~= true or db.showDebuffs ~= true or db.bossDebuffsEnabled ~= true then
        return false
    end
    if not HasPrivateAuraAPI() then return false end
    if not frame or not Util.IsCompactUnitFrame(frame) then return false end
    if not frame:IsVisible() then return false end
    if not RaidFrameAuras:IsTrackedUnit(unit) or not UnitExists(unit) then return false end
    return true
end

local function RefreshHolderLayers(state, config)
    local holders = state and state.privateAuraFrames
    local count = math.min(config.maxSlots or 0, holders and #holders or 0)
    for i = 1, count do
        local holder = holders[i]
        if holder then
            SetHolderGeometry(holder, config.holderSize or config.size, config.holderScale or 1)
            SetFrameLayer(holder, config.strata, config.level)
            ForceFrameLevelRefresh(holder)
        end
    end
end

function RaidFrameAuras:ClearPrivateAuraAnchors(frame)
    local state = frame and State.frameStates and State.frameStates[frame]
    if not state then return end
    local cleared = ClearAnchorIDs(state)
    if cleared then
        if IsPlayerInCombat() then
            MarkPrivateAuraRefreshPending()
        else
            HideHolderFrames(state)
        end
        state.privateAuraLayoutKey = nil
        state.privateAuraUnit = nil
    end
end

function RaidFrameAuras:ClearStalePrivateAuraAnchors()
    local frameStates = State.frameStates
    if not frameStates then return false end

    if IsPlayerInCombat() then
        MarkPrivateAuraRefreshPending()
        return false
    end

    local cleared = false
    for frame, state in pairs(frameStates) do
        if HasPrivateAuraState(state) then
            local unit = Util.GetFrameUnit(frame) or frame.rfaUnit
            if not ShouldShowPrivateAuras(frame, unit) then
                self:ClearPrivateAuraAnchors(frame)
                cleared = true
            end
        end
    end
    return cleared
end

function RaidFrameAuras:RefreshPrivateAuraAnchors(frame)
    if not frame then return end
    local unit = Util.GetFrameUnit(frame) or frame.rfaUnit
    frame.rfaUnit = unit
    if not ShouldShowPrivateAuras(frame, unit) then
        self:ClearPrivateAuraAnchors(frame)
        return
    end

    local state = EnsurePrivateAuraState(frame)
    if not state then return end
    local config = BuildPrivateAuraConfig(frame, unit)
    local layoutKey = BuildLayoutKey(frame, config)

    if IsPlayerInCombat() then
        local hasHolders = state.privateAuraFrames and #state.privateAuraFrames > 0
        if hasHolders then
            RefreshHolderLayers(state, config)
        end
        if hasHolders and (state.privateAuraUnit ~= unit or not state.privateAuraAnchorIDs or #state.privateAuraAnchorIDs ~= config.maxSlots) then
            RegisterPrivateAuraAnchors(state, config, true)
        end
        if state.privateAuraLayoutKey ~= layoutKey or state.privateAuraAnchorKey ~= BuildLayoutKey(nil, config) then
            MarkPrivateAuraRefreshPending()
        end
        return
    end

    local needsLayout = state.privateAuraLayoutKey ~= layoutKey or not state.privateAuraFrames or #state.privateAuraFrames < config.maxSlots
    if needsLayout then
        ApplyHolderLayout(frame, state, config)
        state.privateAuraLayoutKey = layoutKey
    end

    local anchorKey = BuildLayoutKey(nil, config)
    if state.privateAuraUnit ~= unit or state.privateAuraAnchorKey ~= anchorKey or not state.privateAuraAnchorIDs or #state.privateAuraAnchorIDs ~= config.maxSlots then
        RegisterPrivateAuraAnchors(state, config, false)
    end
end

function RaidFrameAuras:ProcessPendingPrivateAuraAnchors()
    if IsPlayerInCombat() or not State.privateAuraRefreshPending then return end
    State.privateAuraRefreshPending = nil
    self:ClearStalePrivateAuraAnchors()
    if self.ForEachTrackedFrame then
        self:ForEachTrackedFrame(function(frame)
            self:RefreshPrivateAuraAnchors(frame)
        end)
    end
end
