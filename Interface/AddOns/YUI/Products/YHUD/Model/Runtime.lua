local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local Model = YHUD.Model or {}
YHUD.Model = Model

Model.DIFF_IDENTITY = 1
Model.DIFF_COOLDOWN = 2
Model.DIFF_AVAILABILITY = 4
Model.DIFF_RESOURCE = 8
Model.states = Model.states or {}

local function CreateState(sourceKey)
    return {
        sourceKey = sourceKey,
        sourceKind = nil,
        slotID = nil,
        spellID = nil,
        chargeSpellID = nil,
        resourceId = nil,
        powerType = nil,
        powerToken = nil,
        nameKey = nil,
        color = nil,
        valueKind = nil,
        structuralMax = nil,
        publicMaxValue = nil,
        itemID = nil,
        icon = nil,
        startTime = 0,
        duration = 0,
        durationMode = "none",
        opaqueRevision = 0,
        cooldownActive = false,
        chargeActive = false,
        currentCharges = nil,
        maxCharges = nil,
        displayCount = nil,
        displayCountRaw = nil,
        countSecret = false,
        activationOverlay = false,
        isEnabled = false,
        available = false,
        resolved = false,
        secret = false,
        durationObject = nil,
        value = nil,
        maxValue = nil,
        valueRaw = nil,
        maxValueRaw = nil,
        rawValuesAvailable = false,
        percentRaw = nil,
        colorRaw = nil,
        partialFraction = nil,
        displayValue = nil,
        chargedPointMask = nil,
        rechargeActive = false,
        rechargeDurationRaw = nil,
        cellReadyRaw = nil,
        cellDurationsRaw = nil,
        durationResourceRaw = nil,
        timerEntriesRaw = nil,
        revision = 0,
    }
end

local function ClearTransientState(state)
    state.castDisplayRaw = nil
    state.durationObject = nil
    state.displayCountRaw = nil
    state.valueRaw = nil
    state.maxValueRaw = nil
    state.rawValuesAvailable = false
    state.percentRaw = nil
    state.colorRaw = nil
    state.rechargeDurationRaw = nil
    state.cellReadyRaw = nil
    state.cellDurationsRaw = nil
    state.durationResourceRaw = nil
    state.timerEntriesRaw = nil
end

local function RecordTransientDispatchError(sourceKey, err)
    local message = "YHUD transient dispatch error ["
        .. tostring(sourceKey) .. "]: " .. tostring(err)
    local event = YUI.Event
    if event and event._RecordError then
        event:_RecordError("YHUD_TRANSIENT_DISPATCH", message)
        return
    end
    if type(geterrorhandler) == "function" then
        local handler = geterrorhandler()
        if type(handler) == "function" then
            pcall(handler, message)
            return
        end
    end
    if YUI.Print then
        YUI:Print(message)
    else
        print(message)
    end
end

function Model:OnSourceState(source, sourceKey, forced)
    if type(source) ~= "table" or type(sourceKey) ~= "string" then return false end
    local state = self.states[sourceKey]
    if not state then
        state = CreateState(sourceKey)
        self.states[sourceKey] = state
    end

    local sourceKind = source.sourceKind
        or (source.slotID and "slot")
        or (source.spellID and "spell")
        or (source.resourceId and "resource")
    local available = source.available == true
    local resolved = source.resolved == true
    local enabled = source.isEnabled ~= false and source.isEnabled ~= 0
    local diff = 0

    if state.sourceKind ~= sourceKind
        or state.slotID ~= source.slotID
        or state.spellID ~= source.spellID
        or state.chargeSpellID ~= source.chargeSpellID
        or state.resourceId ~= source.resourceId
        or state.powerType ~= source.powerType
        or state.powerToken ~= source.powerToken
        or state.nameKey ~= source.nameKey
        or state.color ~= source.color
        or state.valueKind ~= source.valueKind
        or state.itemID ~= source.itemID
        or state.icon ~= source.icon then
        state.sourceKind = sourceKind
        state.slotID = source.slotID
        state.spellID = source.spellID
        state.chargeSpellID = source.chargeSpellID
        state.resourceId = source.resourceId
        state.powerType = source.powerType
        state.powerToken = source.powerToken
        state.nameKey = source.nameKey
        state.color = source.color
        state.valueKind = source.valueKind
        state.itemID = source.itemID
        state.icon = source.icon
        diff = diff + self.DIFF_IDENTITY
        if YHUD.Stats then YHUD.Stats:Add("identityChanges") end
    end

    if sourceKind == "resource" then
        state.castActive, state.castMode, state.castStage = source.castActive, source.castMode, source.castStage
        state.castStages, state.castTotal = source.castStages, source.castTotal
        state.castTickCount = source.castTickCount
        local secret = source.secret == true
        local value = not secret and type(source.value) == "number"
            and source.value or nil
        local maxValue = not secret and type(source.maxValue) == "number"
            and source.maxValue or nil
        local opaqueRevision = tonumber(source.opaqueRevision) or 0
        local structuralMax = type(source.structuralMax) == "number"
            and source.structuralMax or nil
        local publicMaxValue = type(source.publicMaxValue) == "number"
            and source.publicMaxValue or maxValue
        local rechargeActive = source.rechargeActive == true
        local partialFraction = not secret and type(source.partialFraction) == "number"
            and source.partialFraction or nil
        local displayValue = not secret and type(source.displayValue) == "number"
            and source.displayValue or nil
        local chargedPointMask = not secret
            and type(source.chargedPointMask) == "number"
            and source.chargedPointMask or nil
        if state.value ~= value
            or state.maxValue ~= maxValue
            or state.structuralMax ~= structuralMax
            or state.publicMaxValue ~= publicMaxValue
            or state.opaqueRevision ~= opaqueRevision
            or state.rechargeActive ~= rechargeActive
            or state.partialFraction ~= partialFraction
            or state.displayValue ~= displayValue
            or state.chargedPointMask ~= chargedPointMask
            or state.isEnabled ~= enabled then
            state.value = value
            state.maxValue = maxValue
            state.structuralMax = structuralMax
            state.publicMaxValue = publicMaxValue
            state.opaqueRevision = opaqueRevision
            state.rechargeActive = rechargeActive
            state.partialFraction = partialFraction
            state.displayValue = displayValue
            state.chargedPointMask = chargedPointMask
            state.isEnabled = enabled
            diff = diff + self.DIFF_RESOURCE
            if YHUD.Stats then YHUD.Stats:Add("resourceChanges") end
        end
    elseif source.durationMode ~= nil or source.opaqueRevision ~= nil then
        local durationMode = source.durationMode or "none"
        local opaqueRevision = type(source.opaqueRevision) == "number"
            and source.opaqueRevision
            or state.opaqueRevision
        local cooldownActive = source.cooldownActive == true
        local chargeActive = source.chargeActive == true
        local currentCharges = type(source.currentCharges) == "number"
            and source.currentCharges
            or nil
        local maxCharges = type(source.maxCharges) == "number"
            and source.maxCharges
            or nil
        local displayCount = type(source.displayCount) == "number"
            and source.displayCount
            or nil
        local countSecret = source.countSecret == true
        local activationOverlay = source.activationOverlay == true
        if state.durationMode ~= durationMode
            or state.opaqueRevision ~= opaqueRevision
            or state.cooldownActive ~= cooldownActive
            or state.chargeActive ~= chargeActive
            or state.currentCharges ~= currentCharges
            or state.maxCharges ~= maxCharges
            or state.displayCount ~= displayCount
            or state.countSecret ~= countSecret
            or state.activationOverlay ~= activationOverlay
            or state.isEnabled ~= enabled then
            state.durationMode = durationMode
            state.opaqueRevision = opaqueRevision
            state.cooldownActive = cooldownActive
            state.chargeActive = chargeActive
            state.currentCharges = currentCharges
            state.maxCharges = maxCharges
            state.displayCount = displayCount
            state.countSecret = countSecret
            state.activationOverlay = activationOverlay
            state.isEnabled = enabled
            diff = diff + self.DIFF_COOLDOWN
            if YHUD.Stats then YHUD.Stats:Add("cooldownChanges") end
        end
    else
        local startTime = type(source.startTime) == "number" and source.startTime or 0
        local duration = type(source.duration) == "number" and source.duration or 0
        local displayCount = type(source.displayCount) == "number"
            and source.displayCount
            or nil
        local hadOpaqueDuration = state.durationMode ~= nil
        if source.secret == true then
            startTime = 0
            duration = 0
        end
        if state.startTime ~= startTime
            or state.duration ~= duration
            or state.displayCount ~= displayCount
            or state.isEnabled ~= enabled
            or hadOpaqueDuration then
            state.startTime = startTime
            state.duration = duration
            state.displayCount = displayCount
            state.isEnabled = enabled
            state.durationMode = nil
            state.opaqueRevision = nil
            state.cooldownActive = nil
            state.chargeActive = nil
            state.currentCharges = nil
            state.maxCharges = nil
            state.countSecret = false
            state.activationOverlay = false
            diff = diff + self.DIFF_COOLDOWN
            if YHUD.Stats then YHUD.Stats:Add("cooldownChanges") end
        end
    end

    if state.available ~= available
        or state.resolved ~= resolved
        or state.secret ~= (source.secret == true) then
        state.available = available
        state.resolved = resolved
        state.secret = source.secret == true
        diff = diff + self.DIFF_AVAILABILITY
        if YHUD.Stats then YHUD.Stats:Add("availabilityChanges") end
    end

    local forcedReplay = forced == true
    if diff == 0 and not forcedReplay then return false end
    state.durationObject = source.durationObject
    if sourceKind == "spell" and source.countSecret == true then
        state.displayCountRaw = source.displayCountRaw
    end
    if sourceKind == "resource" then
        state.valueRaw = source.valueRaw
        state.maxValueRaw = source.maxValueRaw
        state.rawValuesAvailable = source.rawValuesAvailable == true
        state.percentRaw = source.percentRaw
        state.colorRaw = source.colorRaw
        state.rechargeDurationRaw = source.rechargeDurationRaw
        state.cellReadyRaw = source.cellReadyRaw
        state.cellDurationsRaw = source.cellDurationsRaw
        state.durationResourceRaw = source.durationResourceRaw
        state.timerEntriesRaw = source.timerEntriesRaw
        state.castDisplayRaw = source.castDisplayRaw
    end
    if diff ~= 0 then
        state.revision = state.revision + 1
    end
    local updater = YHUD.Updater
    local transientDispatch = sourceKind == "resource"
        or source.countSecret == true
        or (source.durationMode ~= nil and source.durationMode ~= "none")
    if updater and transientDispatch then
        local ok, err = pcall(updater.Apply, updater, state, diff)
        ClearTransientState(state)
        if not ok then
            if source.resourceId == "cast" and YHUD.PlayerBars then
                YHUD.PlayerBars.renderFailed = true
                YHUD.PlayerBars:SyncNativeSuppression(nil)
            end
            RecordTransientDispatchError(sourceKey, err)
        end
    else
        if updater then updater:Apply(state, diff) end
        ClearTransientState(state)
    end
    return true
end

function Model:GetState(sourceKey)
    return self.states[sourceKey]
end

function Model:Reset()
    for key in pairs(self.states) do
        self.states[key] = nil
    end
end
