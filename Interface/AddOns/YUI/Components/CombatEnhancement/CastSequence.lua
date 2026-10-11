local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not (YUI and (YUI.IsRetail or YUI.IsWrath or YUI.IsForever)) then return end

local CombatEnhancement = YUI.CombatEnhancement
if not (CombatEnhancement and CombatEnhancement.RegisterSubFeature) then return end

local SpellAPI = (YUI.API and YUI.API.Spell) or YUI.WOW_API
local CombatAPI = (YUI.API and YUI.API.Combat) or YUI.WOW_API
local SecurityAPI = YUI.API and YUI.API.Security

local CastSequence = {
    id = "castSequence",
    order = 30,
}

local FEATURE_KEY = CombatEnhancement.FEATURE_KEY or "CombatEnhancement"
local LAYOUT_ID = "yui.component.combat_enhancement.cast_sequence"
local FRAME_NAME = "YUI_CombatEnhancement_CastSequenceFrame"
local MODULE_ID = "component:CombatEnhancement"

local DEFAULT_DIRECTION = "right"
local DEFAULT_MAX_COUNT = 8
local DEFAULT_ICON_SIZE = 40
local DEFAULT_ICON_SPACING = 6
local DEFAULT_ICON_EXPIRE_TIME = 8
local MIN_MAX_COUNT = 1
local MAX_MAX_COUNT = 20
local MIN_ICON_SIZE = 20
local MAX_ICON_SIZE = 80
local MIN_ICON_SPACING = 0
local MAX_ICON_SPACING = 24
local MIN_ICON_EXPIRE_TIME = 0
local MAX_ICON_EXPIRE_TIME = 60
local DEFAULT_ICON_TEXTURE = 134400
local ANIMATION_DURATION = 0.18

local PHASE_CASTING = "casting"
local PHASE_CHANNELING = "channeling"
local PHASE_EMPOWERING = "empowering"
local PHASE_FINISHED = "finished"

local SECTION_WIDTH = 620
local COLUMN_GAP = 24
local COLUMN_WIDTH = math.floor((SECTION_WIDTH - COLUMN_GAP) / 2)
local LABEL_WIDTH = 112
local LABEL_GAP = 10
local BODY_WIDTH = COLUMN_WIDTH - LABEL_WIDTH - LABEL_GAP
local INPUT_WIDTH = 52
local VALUE_GAP = 10

local VALID_DIRECTIONS = {
    right = true,
    left = true,
    up = true,
    down = true,
}

local CAST_UNIT_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_FAILED_QUIET",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_EMPOWER_STOP",
}

local CAST_NORMAL_EVENTS = {
    "UNIT_SPELLCAST_SENT",
}

local PREVIEW_ICONS = {
    { texture = "Interface\\Icons\\Spell_Nature_Lightning", failed = false },
    { texture = "Interface\\Icons\\Spell_Fire_Fireball02", failed = true },
    { texture = "Interface\\Icons\\Ability_Rogue_Eviscerate", failed = false },
}

local featureActive = false
local eventsRegistered = false
local eventFrame
local queueFrame
local layoutRegistered = false
local registeringLayout = false
local layoutPreviewActive = false
local appliedFrameWidth
local appliedFrameHeight
local entries = {}
local previewEntries = {}
local pendingCasts = {}
local pendingCastOrder = {}
local activeChannelSpellID
local freeIcons = {}
local allIcons = {}
local nextSequence = 0
local spellTextureCache = {}
local spellNameCache = {}
local EventOwner = {}
local AnimationOwner = {}
local RegisterLayout
local IsPreviewMode
local CancelEntryExpiry
local ScheduleEntryExpiry
local RescheduleEntryExpiries

CastSequence.defaults = {
    castSequenceEnabled = false,
    castSequenceDirection = DEFAULT_DIRECTION,
    castSequenceMaxCount = DEFAULT_MAX_COUNT,
    castSequenceIconSize = DEFAULT_ICON_SIZE,
    castSequenceIconSpacing = DEFAULT_ICON_SPACING,
    castSequenceIconExpireTime = DEFAULT_ICON_EXPIRE_TIME,
}

local function T(key, fallback)
    if CombatEnhancement.T then
        return CombatEnhancement:T(key, fallback)
    end
    return fallback or key
end

local function ClampNumber(value, minValue, maxValue, fallback)
    local numberValue = tonumber(value)
    if not numberValue then numberValue = fallback end
    if not numberValue then numberValue = minValue end
    if numberValue < minValue then return minValue end
    if numberValue > maxValue then return maxValue end
    return numberValue
end

local function ClampInteger(value, minValue, maxValue, fallback)
    return math.floor(ClampNumber(value, minValue, maxValue, fallback) + 0.5)
end

local function IsSecretValue(value)
    if SecurityAPI and SecurityAPI.IsSecretValue then
        return SecurityAPI.IsSecretValue(value) == true
    end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, value)
        return ok and secret == true
    end
    return false
end

local function SafeNumber(value)
    if value == nil or IsSecretValue(value) then return nil end
    local ok, numberValue = pcall(tonumber, value)
    if ok and not IsSecretValue(numberValue) then
        return numberValue
    end
    return nil
end

local function SafeString(value)
    if value == nil or IsSecretValue(value) then return nil end
    local ok, stringValue = pcall(tostring, value)
    if ok and not IsSecretValue(stringValue) and stringValue ~= "" then
        return stringValue
    end
    return nil
end

local function SafeBoolean(value)
    if value == nil or IsSecretValue(value) then return nil end
    return value == true
end

local function NormalizeDirection(value)
    value = tostring(value or DEFAULT_DIRECTION):lower()
    if VALID_DIRECTIONS[value] then
        return value
    end
    return DEFAULT_DIRECTION
end

function CastSequence:NormalizeDB(db)
    if type(db) ~= "table" then db = self.defaults end
    db.castSequenceEnabled = db.castSequenceEnabled == true
    db.castSequenceDirection = NormalizeDirection(db.castSequenceDirection)
    db.castSequenceMaxCount = ClampInteger(db.castSequenceMaxCount, MIN_MAX_COUNT, MAX_MAX_COUNT, DEFAULT_MAX_COUNT)
    db.castSequenceIconSize = ClampInteger(db.castSequenceIconSize, MIN_ICON_SIZE, MAX_ICON_SIZE, DEFAULT_ICON_SIZE)
    db.castSequenceIconSpacing = ClampInteger(db.castSequenceIconSpacing, MIN_ICON_SPACING, MAX_ICON_SPACING, DEFAULT_ICON_SPACING)
    db.castSequenceIconExpireTime = ClampInteger(db.castSequenceIconExpireTime, MIN_ICON_EXPIRE_TIME, MAX_ICON_EXPIRE_TIME, DEFAULT_ICON_EXPIRE_TIME)
    return db
end

local function GetDB(db)
    if type(db) ~= "table" and CombatEnhancement.GetDB then
        db = CombatEnhancement:GetDB()
    end
    return CastSequence:NormalizeDB(db)
end

local function CreateGUIFrame(parent, opts)
    local GUI2 = YUI.GUI2
    if GUI2 and GUI2.CreateFrame then
        return GUI2:CreateFrame(parent, opts)
    end
    if not CreateFrame then return nil end
    opts = opts or {}
    local frame = CreateFrame(opts.type or opts.frameType or "Frame", opts.name, parent, opts.template)
    if opts.width and opts.height then frame:SetSize(opts.width, opts.height) end
    if opts.mouse ~= nil then frame:EnableMouse(opts.mouse and true or false) end
    return frame
end

local function CreateIconSlot(parent, opts)
    local GUI2 = YUI.GUI2 or YUI.GUI
    if not (GUI2 and parent) then return nil end

    if GUI2.CreateIconSlot then
        local ok, slot = pcall(GUI2.CreateIconSlot, GUI2, parent, opts)
        if ok and slot then return slot end
    end

    local App = GUI2.Application
    if App and App.CreateIconSlot then
        local ok, slot = pcall(App.CreateIconSlot, App, parent, opts)
        if ok and slot then return slot end
    end

    return nil
end

local function ResolveQueueSize(db)
    if type(db) ~= "table" then
        db = GetDB(db)
    end
    local size = db.castSequenceIconSize
    local step = size + db.castSequenceIconSpacing
    local count = db.castSequenceMaxCount
    local length = size + math.max(count - 1, 0) * step
    local direction = db.castSequenceDirection
    if direction == "up" or direction == "down" then
        return size, length
    end
    return length, size
end

local function ToLayoutPlacement(point, relative, relativePoint, x, y)
    return {
        version = 1,
        anchor = {
            point = point or "CENTER",
            relative = relative or "UIParent",
            relativePoint = relativePoint or point or "CENTER",
        },
        offset = {
            x = x or 0,
            y = y or 0,
        },
    }
end

local function GetDefaultPlacement()
    return ToLayoutPlacement("CENTER", "UIParent", "CENTER", 0, -80)
end

local function ApplyDefaultPoint(frame)
    if not (frame and UIParent) then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -80)
end

local function RefreshLayoutFrame()
    if layoutRegistered and YUI.Layout and YUI.Layout.RefreshFrame then
        YUI.Layout:RefreshFrame(LAYOUT_ID)
    end
end

local function ApplyQueueFrameSize(db)
    local frame = queueFrame
    if not frame then return end
    if type(db) ~= "table" then
        db = GetDB(db)
    end
    local width, height = ResolveQueueSize(db)
    if appliedFrameWidth ~= width or appliedFrameHeight ~= height then
        frame:SetSize(width, height)
        appliedFrameWidth = width
        appliedFrameHeight = height
        RefreshLayoutFrame()
    end
end

local function EnsureFrame()
    if queueFrame then return queueFrame end
    if not UIParent then return nil end

    local width, height = ResolveQueueSize()
    local frame = CreateGUIFrame(UIParent, {
        name = FRAME_NAME,
        width = width,
        height = height,
        strata = "MEDIUM",
        level = 20,
        mouse = false,
        clamped = true,
    })
    if not frame then return nil end

    ApplyDefaultPoint(frame)
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    frame:Hide()

    queueFrame = frame
    appliedFrameWidth = width
    appliedFrameHeight = height

    if RegisterLayout and not layoutRegistered and not registeringLayout then
        RegisterLayout()
    end

    return frame
end

local function StopTargetAnimation(frame)
    local Animation = YUI.Animation
    if not (Animation and frame) then return end
    if Animation.StopTarget then
        Animation:StopTarget(frame, "move", false)
        Animation:StopTarget(frame, "pop", false)
        Animation:StopTarget(frame, "remove", false)
    end
end

local function ReleaseIconFrame(frame)
    if not frame or frame.yuiCastSequenceFree then return end
    StopTargetAnimation(frame)
    if frame.yuiCastSequenceEntry and CancelEntryExpiry then
        CancelEntryExpiry(frame.yuiCastSequenceEntry)
    end
    frame.yuiCastSequenceEntry = nil
    frame.yuiCastSequenceFree = true
    if frame.SetAlpha then frame:SetAlpha(1) end
    if frame.SetScale then frame:SetScale(1) end
    if frame.SetState then frame:SetState("normal") end
    if frame.SetIcon then frame:SetIcon(DEFAULT_ICON_TEXTURE) end
    if frame.icon and frame.icon.SetVertexColor then
        frame.icon:SetVertexColor(1, 1, 1, 1)
    end
    frame:Hide()
    freeIcons[#freeIcons + 1] = frame
end

local function AcquireIconFrame(db)
    if type(db) ~= "table" then
        db = GetDB(db)
    end
    local frame = table.remove(freeIcons)
    if frame then
        frame.yuiCastSequenceFree = false
    else
        frame = CreateIconSlot(EnsureFrame(), {
            size = db.castSequenceIconSize,
            icon = DEFAULT_ICON_TEXTURE,
            fallbackIcon = DEFAULT_ICON_TEXTURE,
            variant = "surface",
            shape = "square",
            padding = 2,
            animate = false,
        })
        if not frame then return nil end
        frame.yuiCastSequenceFree = false
        if frame.EnableMouse then frame:EnableMouse(false) end
        allIcons[#allIcons + 1] = frame
    end

    frame:SetParent(EnsureFrame())
    frame:SetSize(db.castSequenceIconSize, db.castSequenceIconSize)
    if queueFrame and queueFrame.GetFrameLevel and frame.SetFrameLevel then
        frame:SetFrameLevel((queueFrame:GetFrameLevel() or 0) + 1)
    end
    return frame
end

local function ApplyIconVisual(entry, db)
    if not (entry and entry.frame) then return end
    if type(db) ~= "table" then
        db = GetDB(db)
    end
    local frame = entry.frame
    -- Keep the IconSlot theme size in sync when pooled slots are resized.
    if frame.SetIconAppearance and frame.gui2IconBaseSize ~= db.castSequenceIconSize then
        frame:SetIconAppearance({ size = db.castSequenceIconSize })
    end
    frame:SetSize(db.castSequenceIconSize, db.castSequenceIconSize)
    if frame.SetScale then frame:SetScale(1) end
    if frame.SetIcon then
        frame:SetIcon(entry.texture or DEFAULT_ICON_TEXTURE)
    elseif frame.icon then
        frame.icon:SetTexture(entry.texture or DEFAULT_ICON_TEXTURE)
    end
    if frame.SetState then
        frame:SetState(entry.failed and "danger" or "normal")
    end
    if frame.icon and frame.icon.SetVertexColor then
        if entry.failed then
            frame.icon:SetVertexColor(1, 0.45, 0.45, 1)
        else
            frame.icon:SetVertexColor(1, 1, 1, 1)
        end
    end
end

local function SetIconPoint(frame, x, y)
    if not (frame and queueFrame) then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", queueFrame, "TOPLEFT", x or 0, y or 0)
    frame.yuiCastSequenceX = x or 0
    frame.yuiCastSequenceY = y or 0
end

local function GetIconPoint(frame)
    if frame and frame.GetPoint and frame:GetNumPoints() > 0 then
        local _, _, _, x, y = frame:GetPoint(1)
        return x or 0, y or 0
    end
    return (frame and frame.yuiCastSequenceX) or 0, (frame and frame.yuiCastSequenceY) or 0
end

local function CapturePositions()
    local positions = {}
    for _, entry in ipairs(entries) do
        local frame = entry.frame
        if frame then
            local x, y = GetIconPoint(frame)
            positions[frame] = { x = x, y = y }
        end
    end
    return positions
end

local function ResolvePosition(db, index)
    if type(db) ~= "table" then
        db = GetDB(db)
    end
    local step = db.castSequenceIconSize + db.castSequenceIconSpacing
    local maxCount = db.castSequenceMaxCount
    local direction = db.castSequenceDirection
    if direction == "left" then
        return (maxCount - index) * step, 0
    elseif direction == "up" then
        return 0, -((maxCount - index) * step)
    elseif direction == "down" then
        return 0, -((index - 1) * step)
    end
    return (index - 1) * step, 0
end

local function ResolveDirectionStep(db)
    if type(db) ~= "table" then
        db = GetDB(db)
    end
    local step = db.castSequenceIconSize + db.castSequenceIconSpacing
    local direction = db.castSequenceDirection
    if direction == "left" then
        return -step, 0
    elseif direction == "up" then
        return 0, step
    elseif direction == "down" then
        return 0, -step
    end
    return step, 0
end

local function AnimateTo(frame, fromX, fromY, toX, toY, fadeIn, onFinished)
    local Animation = YUI.Animation
    if not (Animation and Animation.Tween and frame) then
        SetIconPoint(frame, toX, toY)
        if frame.SetAlpha then frame:SetAlpha(1) end
        if frame.Show then frame:Show() end
        if onFinished then onFinished() end
        return
    end

    SetIconPoint(frame, fromX, fromY)
    if frame.Show then frame:Show() end
    Animation:Tween({
        target = frame,
        owner = AnimationOwner,
        key = "move",
        duration = ANIMATION_DURATION,
        easing = "out",
        effects = {
            fadeIn and { type = "alpha", from = 0, to = 1 } or { type = "alpha", from = frame.GetAlpha and frame:GetAlpha() or 1, to = 1 },
            { type = "translation", fromX = 0, fromY = 0, toX = toX - fromX, toY = toY - fromY },
        },
        onFinished = function()
            SetIconPoint(frame, toX, toY)
            if frame.SetAlpha then frame:SetAlpha(1) end
            if onFinished then onFinished() end
        end,
    })
end

local function FadeOutAndRelease(frame)
    local Animation = YUI.Animation
    if not frame then return end
    if Animation and Animation.StopTarget then
        Animation:StopTarget(frame, "move", false)
        Animation:StopTarget(frame, "pop", false)
    end
    if Animation and Animation.FadeOut then
        Animation:FadeOut(frame, {
            owner = AnimationOwner,
            key = "remove",
            duration = ANIMATION_DURATION,
            easing = "out",
            onFinished = function()
                ReleaseIconFrame(frame)
                if queueFrame and #entries == 0 and (not IsPreviewMode or not IsPreviewMode()) then
                    queueFrame:Hide()
                end
            end,
        })
    else
        ReleaseIconFrame(frame)
        if queueFrame and #entries == 0 and (not IsPreviewMode or not IsPreviewMode()) then
            queueFrame:Hide()
        end
    end
end

local function LayoutEntryFrames(db, animate, oldPositions, newEntry, removedEntries)
    local frame = EnsureFrame()
    if not frame then return end

    if type(db) ~= "table" then
        db = GetDB(db)
    end
    ApplyQueueFrameSize(db)

    for index, entry in ipairs(entries) do
        entry.frame = entry.frame or AcquireIconFrame(db)
        local icon = entry.frame
        if icon then
            icon.yuiCastSequenceEntry = entry
            ApplyIconVisual(entry, db)
            local targetX, targetY = ResolvePosition(db, index)
            local old = oldPositions and oldPositions[icon]
            local isNew = entry == newEntry and not old
            if animate then
                if isNew then
                    local stepX, stepY = ResolveDirectionStep(db)
                    local startX, startY = targetX - stepX, targetY - stepY
                    if icon.SetAlpha then icon:SetAlpha(0) end
                    AnimateTo(icon, startX, startY, targetX, targetY, true)
                elseif old then
                    AnimateTo(icon, old.x, old.y, targetX, targetY, false)
                else
                    SetIconPoint(icon, targetX, targetY)
                    if icon.SetAlpha then icon:SetAlpha(1) end
                    icon:Show()
                end
            else
                StopTargetAnimation(icon)
                SetIconPoint(icon, targetX, targetY)
                if icon.SetAlpha then icon:SetAlpha(1) end
                if icon.SetScale then icon:SetScale(1) end
                icon:Show()
            end
        end
    end

    if type(removedEntries) == "table" then
        for _, entry in ipairs(removedEntries) do
            if CancelEntryExpiry then
                CancelEntryExpiry(entry)
            end
            local icon = entry.frame
            entry.frame = nil
            if animate then
                FadeOutAndRelease(icon)
            else
                ReleaseIconFrame(icon)
            end
        end
    end

    frame:Show()
end

local function ReleasePreviewFrames()
    for _, entry in ipairs(previewEntries) do
        ReleaseIconFrame(entry.frame)
        entry.frame = nil
    end
end

local function HideEntryFrames()
    for _, entry in ipairs(entries) do
        if entry.frame then
            StopTargetAnimation(entry.frame)
            entry.frame:Hide()
        end
    end
end

local function RenderPreview(db)
    if type(db) ~= "table" then
        db = GetDB(db)
    end
    EnsureFrame()
    ApplyQueueFrameSize(db)
    HideEntryFrames()

    local previewCount = db.castSequenceMaxCount
    local iconCount = #PREVIEW_ICONS
    for index = 1, previewCount do
        local data = PREVIEW_ICONS[((index - 1) % iconCount) + 1]
        local entry = previewEntries[index]
        if not entry then
            entry = {}
            previewEntries[index] = entry
        end
        entry.texture = data.texture
        entry.failed = data.failed == true
        entry.frame = entry.frame or AcquireIconFrame(db)
        ApplyIconVisual(entry, db)
        local x, y = ResolvePosition(db, index)
        StopTargetAnimation(entry.frame)
        SetIconPoint(entry.frame, x, y)
        if entry.frame.SetAlpha then entry.frame:SetAlpha(1) end
        if entry.frame.SetScale then entry.frame:SetScale(1) end
        entry.frame:Show()
    end

    for index = #previewEntries, previewCount + 1, -1 do
        local entry = previewEntries[index]
        if entry then
            ReleaseIconFrame(entry.frame)
            previewEntries[index] = nil
        end
    end

    if queueFrame then queueFrame:Show() end
end

local function ClearQueue()
    if YUI.Animation and YUI.Animation.StopOwner then
        YUI.Animation:StopOwner(AnimationOwner, false)
    end

    for _, entry in ipairs(entries) do
        if CancelEntryExpiry then
            CancelEntryExpiry(entry)
        end
    end
    for _, icon in ipairs(allIcons) do
        ReleaseIconFrame(icon)
    end
    for _, entry in ipairs(previewEntries) do
        entry.frame = nil
    end
    for index = #entries, 1, -1 do
        entries[index] = nil
    end
    for castGUID in pairs(pendingCasts) do
        pendingCasts[castGUID] = nil
    end
    for index = #pendingCastOrder, 1, -1 do
        pendingCastOrder[index] = nil
    end
    activeChannelSpellID = nil
    if queueFrame then queueFrame:Hide() end
end

IsPreviewMode = function()
    if layoutPreviewActive then return true end
    return YUI.Layout and YUI.Layout.IsEditing and YUI.Layout:IsEditing()
end

local function ShouldShowQueue(db)
    if type(db) ~= "table" then
        db = GetDB(db)
    end
    if IsPreviewMode() then return true end
    return featureActive and db.castSequenceEnabled == true and #entries > 0
end

local function EntryHasCastGUID(entry, castGUID)
    if not (entry and castGUID) then return false end
    return entry.castGUID == castGUID
end

local function IsEntryActive(entry)
    return entry and entry.phase ~= PHASE_FINISHED
end

local function EntryHasActiveCastBarID(entry, spellID, castBarID, expectedPhase)
    if not (entry and spellID and castBarID) then return false end
    if not IsEntryActive(entry) then return false end
    if entry.spellID ~= spellID then return false end
    if expectedPhase and entry.phase ~= expectedPhase then return false end
    return entry.castBarID == castBarID
end

local function RememberEntryIdentifiers(entry, castGUID, castBarID)
    if not entry then return end
    if castGUID and not entry.castGUID then entry.castGUID = castGUID end
    if castBarID then entry.castBarID = castBarID end
end

local function FindEntry(castGUID)
    if not castGUID then return nil end
    for _, entry in ipairs(entries) do
        if EntryHasCastGUID(entry, castGUID) then
            return entry
        end
    end
    return nil
end

local function FindActiveEntryByCastBarID(spellID, castBarID, expectedPhase)
    if not (spellID and castBarID) then return nil end
    for _, entry in ipairs(entries) do
        if EntryHasActiveCastBarID(entry, spellID, castBarID, expectedPhase) then
            return entry
        end
    end
    return nil
end

local function FindRelatedEntry(spellID, castGUID, castBarID, expectedPhase)
    if castGUID then
        local entry = FindEntry(castGUID)
        if entry then return entry end

        local unbound = FindActiveEntryByCastBarID(spellID, castBarID, expectedPhase)
        if unbound and not unbound.castGUID then
            return unbound
        end
        return nil
    end

    return FindActiveEntryByCastBarID(spellID, castBarID, expectedPhase)
end

local function RefreshExistingEntry(entry, db, castGUID, castBarID, failed)
    if not entry then return nil end
    RememberEntryIdentifiers(entry, castGUID, castBarID)
    if failed ~= nil and entry.failed ~= (failed == true) then
        entry.failed = failed == true
        ApplyIconVisual(entry, db)
    end
    return entry
end

local function FindEntryIndex(entry)
    if not entry then return nil end
    for index, existing in ipairs(entries) do
        if existing == entry then
            return index
        end
    end
    return nil
end

CancelEntryExpiry = function(entry)
    if not entry then return end
    entry.expireToken = (entry.expireToken or 0) + 1
    if entry.expireTimer and entry.expireTimer.Cancel then
        entry.expireTimer:Cancel()
    end
    entry.expireTimer = nil
end

local function ExpireEntry(entry, token)
    if not entry then return end
    if token and entry.expireToken ~= token then return end

    local index = FindEntryIndex(entry)
    if not index then return end

    local db = GetDB()
    local oldPositions = CapturePositions()
    table.remove(entries, index)
    CancelEntryExpiry(entry)

    if IsPreviewMode and IsPreviewMode() then
        ReleaseIconFrame(entry.frame)
        entry.frame = nil
        return
    end

    LayoutEntryFrames(db, true, oldPositions, nil, { entry })
end

ScheduleEntryExpiry = function(entry, db)
    if not entry then return end
    if type(db) ~= "table" then
        db = GetDB(db)
    end
    CancelEntryExpiry(entry)

    local expireTime = db.castSequenceIconExpireTime
    if expireTime <= 0 or not C_Timer then return end

    local token = (entry.expireToken or 0) + 1
    entry.expireToken = token

    local function OnExpire()
        if entry.expireToken ~= token then return end
        entry.expireTimer = nil
        ExpireEntry(entry, token)
    end

    if C_Timer.NewTimer then
        entry.expireTimer = C_Timer.NewTimer(expireTime, OnExpire)
    elseif C_Timer.After then
        C_Timer.After(expireTime, OnExpire)
    end
end

RescheduleEntryExpiries = function(db)
    if type(db) ~= "table" then
        db = GetDB(db)
    end
    for _, entry in ipairs(entries) do
        ScheduleEntryExpiry(entry, db)
    end
end

local function RememberPendingCast(castGUID, spellID)
    if not (castGUID and spellID) then return end
    if not pendingCasts[castGUID] then
        pendingCastOrder[#pendingCastOrder + 1] = castGUID
    end
    pendingCasts[castGUID] = spellID

    while #pendingCastOrder > 40 do
        local oldCastGUID = table.remove(pendingCastOrder, 1)
        if oldCastGUID then
            pendingCasts[oldCastGUID] = nil
        end
    end
end

local function ClearPendingCast(castGUID)
    if castGUID then
        pendingCasts[castGUID] = nil
    end
end

local function ConsumePendingCastForStart(castGUID, spellID)
    if castGUID and pendingCasts[castGUID] then
        pendingCasts[castGUID] = nil
        return
    end
    if not spellID then return end

    for index = #pendingCastOrder, 1, -1 do
        local pendingCastGUID = pendingCastOrder[index]
        if pendingCasts[pendingCastGUID] == spellID then
            pendingCasts[pendingCastGUID] = nil
            return
        end
    end
end

local function TakePendingCast(castGUID)
    if not castGUID then return nil end
    local spellID = pendingCasts[castGUID]
    pendingCasts[castGUID] = nil
    return spellID
end

local function ResolveSpellTexture(spellID)
    local cached = spellTextureCache[spellID]
    if cached then
        return cached
    end
    local texture = DEFAULT_ICON_TEXTURE
    if SpellAPI and SpellAPI.GetTexture then
        texture = SpellAPI.GetTexture(spellID) or DEFAULT_ICON_TEXTURE
    end
    spellTextureCache[spellID] = texture
    return texture
end

local function ResolveSpellName(spellID)
    local cached = spellNameCache[spellID]
    if cached then
        return cached
    end
    local name
    if SpellAPI and SpellAPI.GetInfo then
        local info = SpellAPI.GetInfo(spellID)
        if info and info.name then
            name = info.name
        end
    end
    if not name and SpellAPI and SpellAPI.GetName then
        name = SpellAPI.GetName(spellID)
    end
    if type(name) == "string" and name ~= "" then
        spellNameCache[spellID] = name
        return name
    end
    return nil
end

local function PruneEntries(db, oldPositions, animate)
    if type(db) ~= "table" then
        db = GetDB(db)
    end
    local removed = {}
    while #entries > db.castSequenceMaxCount do
        removed[#removed + 1] = table.remove(entries)
    end
    return removed
end

local function CreateEntry(spellID, castGUID, castBarID, phase, failed)
    local db = GetDB()
    if db.castSequenceEnabled ~= true or not spellID then return nil end

    ReleasePreviewFrames()
    local oldPositions = CapturePositions()
    nextSequence = nextSequence + 1
    local entry = {
        seq = nextSequence,
        castGUID = castGUID,
        castBarID = castBarID,
        spellID = spellID,
        texture = ResolveSpellTexture(spellID),
        name = ResolveSpellName(spellID),
        failed = failed == true,
        phase = phase or PHASE_FINISHED,
    }
    entry.frame = AcquireIconFrame(db)
    if not entry.frame then return nil end
    RememberEntryIdentifiers(entry, castGUID, castBarID)
    table.insert(entries, 1, entry)

    local removed = PruneEntries(db, oldPositions, true)
    LayoutEntryFrames(db, true, oldPositions, entry, removed)
    ScheduleEntryExpiry(entry, db)
    return entry
end

local function AddStartedEntry(spellID, castGUID, castBarID, phase)
    local db = GetDB()
    if db.castSequenceEnabled ~= true or not spellID then return nil end

    local entry = FindRelatedEntry(spellID, castGUID, castBarID, phase)
    if entry then
        return RefreshExistingEntry(entry, db, castGUID, castBarID, nil)
    end

    return CreateEntry(spellID, castGUID, castBarID, phase, nil)
end

local function FinishEntry(spellID, castGUID, castBarID, failed, expectedPhase)
    local db = GetDB()
    if db.castSequenceEnabled ~= true then return nil end

    local entry = FindRelatedEntry(spellID, castGUID, castBarID, expectedPhase)
    if not entry then return nil end

    if entry.phase ~= PHASE_FINISHED then
        if expectedPhase and entry.phase ~= expectedPhase then
            return entry
        end
        entry.phase = PHASE_FINISHED
    end
    return RefreshExistingEntry(entry, db, castGUID, castBarID, failed)
end

local function OnSpellEvent(event, ...)
    CastSequence:HandleSpellEvent(event, ...)
end

local function OnSpellFrameEvent(_, event, ...)
    CastSequence:HandleSpellEvent(event, ...)
end

local function RefreshEventState(db)
    db = GetDB(db)
    local shouldAttach = featureActive and db.castSequenceEnabled == true
    if shouldAttach and not eventsRegistered then
        if YUI.Event and YUI.Event.On then
            for _, eventName in ipairs(CAST_UNIT_EVENTS) do
                YUI.Event:On(eventName, OnSpellEvent, EventOwner, {
                    unit = "player",
                    traceName = "CombatEnhancement:CastSequence:" .. eventName,
                    moduleId = MODULE_ID,
                })
            end
            for _, eventName in ipairs(CAST_NORMAL_EVENTS) do
                YUI.Event:On(eventName, OnSpellEvent, EventOwner, {
                    traceName = "CombatEnhancement:CastSequence:" .. eventName,
                    moduleId = MODULE_ID,
                })
            end
            eventsRegistered = "eventbus"
            return
        end

        if CreateFrame then
            eventFrame = eventFrame or CreateFrame("Frame")
            for _, eventName in ipairs(CAST_UNIT_EVENTS) do
                local ok = pcall(eventFrame.RegisterUnitEvent, eventFrame, eventName, "player")
                if not ok then
                    pcall(eventFrame.RegisterEvent, eventFrame, eventName)
                end
            end
            for _, eventName in ipairs(CAST_NORMAL_EVENTS) do
                pcall(eventFrame.RegisterEvent, eventFrame, eventName)
            end
            eventFrame:SetScript("OnEvent", OnSpellFrameEvent)
            eventsRegistered = "frame"
        end
    elseif not shouldAttach and eventsRegistered then
        if eventsRegistered == "eventbus" and YUI.Event and YUI.Event.OffOwner then
            YUI.Event:OffOwner(EventOwner)
        elseif eventsRegistered == "frame" and eventFrame then
            for _, eventName in ipairs(CAST_UNIT_EVENTS) do
                pcall(eventFrame.UnregisterEvent, eventFrame, eventName)
            end
            for _, eventName in ipairs(CAST_NORMAL_EVENTS) do
                pcall(eventFrame.UnregisterEvent, eventFrame, eventName)
            end
            eventFrame:SetScript("OnEvent", nil)
        end
        eventsRegistered = false
    end
end

function CastSequence:HandleSpellEvent(event, unit, arg2, arg3, arg4, arg5, arg6)
    if unit ~= "player" then return end

    local safeCastGUID
    local safeCastBarID
    local safeSpellID
    local complete
    if event == "UNIT_SPELLCAST_SENT" then
        safeCastGUID = SafeString(arg3)
        safeSpellID = SafeNumber(arg4)
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        safeCastGUID = SafeString(arg2)
        safeSpellID = SafeNumber(arg3)
        complete = SafeBoolean(arg4)
        safeCastBarID = SafeNumber(arg6)
    elseif event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        safeCastGUID = SafeString(arg2)
        safeSpellID = SafeNumber(arg3)
        safeCastBarID = SafeNumber(arg5)
    else
        safeCastGUID = SafeString(arg2)
        safeSpellID = SafeNumber(arg3)
        safeCastBarID = SafeNumber(arg4)
    end

    if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        activeChannelSpellID = nil
    end

    if not safeSpellID then return end

    if event == "UNIT_SPELLCAST_SENT" then
        RememberPendingCast(safeCastGUID, safeSpellID)
    elseif event == "UNIT_SPELLCAST_START" then
        ConsumePendingCastForStart(safeCastGUID, safeSpellID)
        AddStartedEntry(safeSpellID, safeCastGUID, safeCastBarID, PHASE_CASTING)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        ConsumePendingCastForStart(safeCastGUID, safeSpellID)
        activeChannelSpellID = safeSpellID
        AddStartedEntry(safeSpellID, safeCastGUID, safeCastBarID, PHASE_CHANNELING)
    elseif event == "UNIT_SPELLCAST_EMPOWER_START" then
        ConsumePendingCastForStart(safeCastGUID, safeSpellID)
        AddStartedEntry(safeSpellID, safeCastGUID, safeCastBarID, PHASE_EMPOWERING)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local pendingSpellID = TakePendingCast(safeCastGUID)
        local spellID = safeSpellID or pendingSpellID
        local existing = FindRelatedEntry(spellID, safeCastGUID, safeCastBarID)
        if existing then
            if existing.phase == PHASE_CASTING then
                existing.phase = PHASE_FINISHED
            end
            RefreshExistingEntry(existing, GetDB(), safeCastGUID, safeCastBarID, false)
        elseif activeChannelSpellID == spellID then
            return
        elseif pendingSpellID then
            CreateEntry(spellID, safeCastGUID, safeCastBarID, PHASE_FINISHED, false)
        end
    elseif event == "UNIT_SPELLCAST_STOP" then
        ClearPendingCast(safeCastGUID)
        FinishEntry(safeSpellID, safeCastGUID, safeCastBarID, nil, PHASE_CASTING)
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        ClearPendingCast(safeCastGUID)
        FinishEntry(safeSpellID, safeCastGUID, safeCastBarID, nil, PHASE_CHANNELING)
    elseif event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_FAILED_QUIET"
        or event == "UNIT_SPELLCAST_INTERRUPTED" then
        ClearPendingCast(safeCastGUID)
        FinishEntry(safeSpellID, safeCastGUID, safeCastBarID, true)
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        ClearPendingCast(safeCastGUID)
        FinishEntry(
            safeSpellID,
            safeCastGUID,
            safeCastBarID,
            complete == nil and nil or complete == false,
            PHASE_EMPOWERING
        )
    end
end

function CastSequence:RefreshRuntime(db)
    if YUI.Layout and YUI.Layout.InvalidateAnchorProvider then
        YUI.Layout:InvalidateAnchorProvider(LAYOUT_ID)
    end
    db = GetDB(db)
    EnsureFrame()
    RegisterLayout()
    RefreshEventState(db)

    if not ShouldShowQueue(db) then
        ReleasePreviewFrames()
        if queueFrame then queueFrame:Hide() end
        return
    end

    if IsPreviewMode() then
        RenderPreview(db)
        return
    end

    ReleasePreviewFrames()
    LayoutEntryFrames(db, false)
end

local function OpenCastSequenceSettings()
    if CombatEnhancement.OpenSettingsTab then
        return CombatEnhancement:OpenSettingsTab("castSequence")
    end
    if YUI.Settings and YUI.Settings.OpenComponentFeature then
        YUI.Settings:OpenComponentFeature(FEATURE_KEY)
        return true
    end
    if YUI.Components and YUI.Components.OpenFeatureSettings then
        YUI.Components:OpenFeatureSettings(FEATURE_KEY)
        return true
    end
    return false
end

local function OpenLayoutEditMode()
    if CombatAPI and CombatAPI.InCombatLockdown and CombatAPI.InCombatLockdown() then
        return
    end

    EnsureFrame()
    RegisterLayout()

    if YUI.Layout and YUI.Layout.OpenEditMode then
        if YUI.Layout:OpenEditMode(FEATURE_KEY) == false then return end
    end
    -- Opening edit mode closes settings and clears its previews first.
    layoutPreviewActive = true
    RenderPreview(GetDB())
    RefreshLayoutFrame()
    if YUI.Layout and YUI.Layout.RefreshEditSessionEntry then
        YUI.Layout:RefreshEditSessionEntry(LAYOUT_ID)
    end
    if YUI.Layout and YUI.Layout.SetEditMoverVisible then
        YUI.Layout:SetEditMoverVisible(LAYOUT_ID, true)
    end
    if YUI.Layout and YUI.Layout.SelectFrame then
        YUI.Layout:SelectFrame(LAYOUT_ID, true)
    end
end

function RegisterLayout()
    if registeringLayout then return end
    registeringLayout = true
    local frame = EnsureFrame()
    if not frame then
        registeringLayout = false
        return
    end

    if not (YUI.Layout and YUI.Layout.RegisterFrame) then
        ApplyDefaultPoint(frame)
        registeringLayout = false
        return
    end

    if layoutRegistered then
        registeringLayout = false
        return
    end

    YUI.Layout:RegisterFrame(LAYOUT_ID, {
        frame = frame,
        title = T("layout.cast_sequence", "施法序列"),
        category = "component",
        defaultPlacement = GetDefaultPlacement,
        movable = true,
        snap = true,
        anchorTargets = { "UIParent" },
        minWidth = MIN_ICON_SIZE,
        minHeight = MIN_ICON_SIZE,
        getMoverBounds = function()
            return ResolveQueueSize(GetDB())
        end,
        isEnabled = function()
            local db = GetDB()
            local editing = YUI.Layout and YUI.Layout.IsEditing and YUI.Layout:IsEditing()
            return editing or layoutPreviewActive or (db.castSequenceEnabled == true and featureActive)
        end,
        openPluginSettings = OpenCastSequenceSettings,
        onEnterEditMode = function()
            layoutPreviewActive = true
            RenderPreview(GetDB())
        end,
        onExitEditMode = function()
            layoutPreviewActive = false
            ReleasePreviewFrames()
            local db = GetDB()
            if ShouldShowQueue(db) then
                LayoutEntryFrames(db, false)
            elseif queueFrame then
                queueFrame:Hide()
            end
        end,
        onApply = function()
            ApplyQueueFrameSize(GetDB())
            CastSequence:RefreshRuntime()
        end,
    })
    layoutRegistered = true
    registeringLayout = false
end

local function BuildDirectionOptions()
    return {
        { text = T("settings.cast_sequence_direction_right", "向右"), value = "right" },
        { text = T("settings.cast_sequence_direction_left", "向左"), value = "left" },
        { text = T("settings.cast_sequence_direction_up", "向上"), value = "up" },
        { text = T("settings.cast_sequence_direction_down", "向下"), value = "down" },
    }
end

local function AddAlignedFieldGroup(options, label, fields, layout)
    layout = type(layout) == "table" and layout or {}
    options[#options + 1] = { type = "divider", label = label, alignLeft = true, width = SECTION_WIDTH }
    options[#options + 1] = {
        type = "custom",
        retainedFields = fields,
        width = SECTION_WIDTH,
        render = function(parent, x, y, width)
            local Settings = YUI.Settings
            if not (Settings and Settings.RenderAlignedFields) then
                return SECTION_WIDTH, 1
            end

            local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                x = x,
                y = y,
                width = math.min(width or SECTION_WIDTH, SECTION_WIDTH),
                columns = layout.columns or 2,
                labelPosition = layout.labelPosition or "top",
                columnGap = layout.columnGap or COLUMN_GAP,
                labelWidth = layout.labelWidth or LABEL_WIDTH,
                labelGap = layout.labelGap or LABEL_GAP,
                bodyWidth = layout.bodyWidth or BODY_WIDTH,
                valueWidth = layout.valueWidth or INPUT_WIDTH,
                valueGap = layout.valueGap or VALUE_GAP,
                rowHeight = layout.rowHeight or 32,
                rowGap = layout.rowGap or 10,
                fields = fields,
            })
            return gridWidth, gridHeight
        end,
    }
end

local function AddAlignedFieldRow(options, fields, layout)
    layout = type(layout) == "table" and layout or {}
    options[#options + 1] = {
        type = "custom",
        retainedFields = fields,
        width = SECTION_WIDTH,
        render = function(parent, x, y, width)
            local Settings = YUI.Settings
            if not (Settings and Settings.RenderAlignedFields) then
                return SECTION_WIDTH, 1
            end

            local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                x = x,
                y = y,
                width = math.min(width or SECTION_WIDTH, SECTION_WIDTH),
                columns = layout.columns or 1,
                labelPosition = layout.labelPosition or "top",
                columnGap = layout.columnGap or COLUMN_GAP,
                labelWidth = layout.labelWidth or LABEL_WIDTH,
                labelGap = layout.labelGap or LABEL_GAP,
                bodyWidth = layout.bodyWidth or BODY_WIDTH,
                valueWidth = layout.valueWidth or INPUT_WIDTH,
                valueGap = layout.valueGap or VALUE_GAP,
                rowHeight = layout.rowHeight or 32,
                rowGap = layout.rowGap or 10,
                fields = fields,
            })
            return gridWidth, gridHeight
        end,
    }
end

local function RefreshAfterLayoutSettingChange(db)
    local oldPositions = CapturePositions()
    local removed = PruneEntries(db, oldPositions, false)
    ReleasePreviewFrames()
    LayoutEntryFrames(db, true, oldPositions, nil, removed)
    CastSequence:RefreshRuntime(db)
end

function CastSequence:BuildOptions(db)
    db = GetDB(db)
    RegisterLayout()

    local options = {}
    AddAlignedFieldRow(options, {
        {
            type = "checkbox",
            label = T("settings.cast_sequence_enabled", "启用"),
            get = function() return db.castSequenceEnabled == true end,
            settingsToggle = "castSequence",
            searchKey = "settings.cast_sequence_enabled",
            set = function(value)
                db.castSequenceEnabled = value == true
                RefreshEventState(db)
                if db.castSequenceEnabled then
                    CastSequence:RefreshRuntime(db)
                else
                    ClearQueue()
                end
            end,
        },
    })

    AddAlignedFieldGroup(options, T("settings.cast_sequence_general", "施法序列"), {
        {
            type = "button",
            label = "",
            text = T("settings.cast_sequence_open_layout", "编辑位置"),
            onClick = OpenLayoutEditMode,
        },
        {
            type = "dropdown",
            label = T("settings.cast_sequence_direction", "队列方向"),
            options = BuildDirectionOptions,
            default = DEFAULT_DIRECTION,
            get = function() return db.castSequenceDirection end,
            set = function(value)
                db.castSequenceDirection = NormalizeDirection(value)
                RefreshAfterLayoutSettingChange(db)
            end,
        },
        {
            type = "slider",
            label = T("settings.cast_sequence_max_count", "最大数量"),
            min = MIN_MAX_COUNT,
            max = MAX_MAX_COUNT,
            step = 1,
            get = function() return db.castSequenceMaxCount end,
            set = function(value)
                db.castSequenceMaxCount = ClampInteger(value, MIN_MAX_COUNT, MAX_MAX_COUNT, DEFAULT_MAX_COUNT)
                RefreshAfterLayoutSettingChange(db)
            end,
        },
        {
            type = "slider",
            label = T("settings.cast_sequence_icon_size", "图标尺寸"),
            min = MIN_ICON_SIZE,
            max = MAX_ICON_SIZE,
            step = 1,
            get = function() return db.castSequenceIconSize end,
            set = function(value)
                db.castSequenceIconSize = ClampInteger(value, MIN_ICON_SIZE, MAX_ICON_SIZE, DEFAULT_ICON_SIZE)
                RefreshAfterLayoutSettingChange(db)
            end,
        },
        {
            type = "slider",
            label = T("settings.cast_sequence_icon_spacing", "图标间隔"),
            min = MIN_ICON_SPACING,
            max = MAX_ICON_SPACING,
            step = 1,
            get = function() return db.castSequenceIconSpacing end,
            set = function(value)
                db.castSequenceIconSpacing = ClampInteger(value, MIN_ICON_SPACING, MAX_ICON_SPACING, DEFAULT_ICON_SPACING)
                RefreshAfterLayoutSettingChange(db)
            end,
        },
        {
            type = "slider",
            label = T("settings.cast_sequence_icon_expire_time", "图标消失时间"),
            min = MIN_ICON_EXPIRE_TIME,
            max = MAX_ICON_EXPIRE_TIME,
            step = 1,
            get = function() return db.castSequenceIconExpireTime end,
            set = function(value)
                db.castSequenceIconExpireTime = ClampInteger(value, MIN_ICON_EXPIRE_TIME, MAX_ICON_EXPIRE_TIME, DEFAULT_ICON_EXPIRE_TIME)
                RescheduleEntryExpiries(db)
            end,
        },
    })

    return options
end

function CastSequence:OnFeatureToggle(enabled, db)
    featureActive = enabled == true
    db = GetDB(db)
    RefreshEventState(db)
    if featureActive then
        self:RefreshRuntime(db)
    else
        layoutPreviewActive = false
        ClearQueue()
    end
end

function CastSequence:OnSettingsLeave(db)
    if not (YUI.Layout and YUI.Layout.IsEditing and YUI.Layout:IsEditing()) then
        layoutPreviewActive = false
        ReleasePreviewFrames()
    end
    self:RefreshRuntime(db)
end

CombatEnhancement.CastSequence = CastSequence
CombatEnhancement:RegisterSubFeature(CastSequence)


-- Resolve disabled targets without creating widgets or starting feature runtime.
if YUI.Layout and YUI.Layout.RegisterAnchorProvider then
    local function ResolveColdAnchor(id)
        local components = YUI.Components
        local db = components and components.CopyConfigSnapshot and components:CopyConfigSnapshot(
            CombatEnhancement.CONFIG_KEY, CombatEnhancement.defaults, CombatEnhancement.PRODUCT_ID)
        if not db then return nil end
        db = CastSequence:NormalizeDB(db)
        local width, height = ResolveQueueSize(db)
        return GetDefaultPlacement(), width, height, 1
    end
    YUI.Layout:RegisterAnchorProvider(LAYOUT_ID, {name=FRAME_NAME, resolve=ResolveColdAnchor})
end
