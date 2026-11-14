local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD or YUI.IsForever ~= true then return end

-- Temporary fixed backend. Restore native routing only by removing this override.
-- Forever CN 1.60.1.70888: CooldownSetSpell 199342 links 400574 to 400573.
local Arcane = {}
YHUD.ArcaneBlast = Arcane
Arcane.SOURCE_TYPE = "yhud.forever-arcane-blast"
Arcane.SOURCE_KEY = "forever-arcane-blast:199342"
local AURA_IDENTITY = "aura:cdm:199342"
local DURATION, MAX_STACKS = 18, 4
Arcane.MAX_STACKS = MAX_STACKS
local CAST_IDS = { 400574, 1239696, 1239697, 1239699, 1239700 }
local CASTS = {}
for _, id in ipairs(CAST_IDS) do CASTS[id] = true end
local hooked = setmetatable({}, { __mode = "k" })
local gainHooked = setmetatable({}, { __mode = "k" })
local Monitor, Viewer
local ReadPresence
local NATIVE_CATEGORIES = { "trackedBuff", "trackedBar" }

local function Public(value)
    if _G.issecretvalue and _G.issecretvalue(value) then return nil end
    return value
end

local function PublicTable(value)
    value = Public(value)
    if type(value) ~= "table" or _G.issecrettable and _G.issecrettable(value) then return nil end
    local security = YUI.API and YUI.API.Security
    if security and security.CanAccessTable and security.CanAccessTable(value) == false then return nil end
    return value
end

local function Method(object, name, ...)
    if not object or type(object[name]) ~= "function" then return false end
    local ok, value = pcall(object[name], object, ...)
    if not ok or _G.issecretvalue and _G.issecretvalue(value) then return false end
    return true, value
end

function Arcane:Matches(entry)
    return YUI.IsForever == true and type(entry) == "table"
        and entry.origin == "official-cdm" and entry.cooldownId == 199342
        and entry.spellId == 400574
        and (entry.officialCategory == "trackedBuff" or entry.officialCategory == "trackedBar")
end

local function MatchesFrame(frame)
    if frame and type(frame.GetViewerFrame) == "function" then
        local ownerOK, owner = Method(frame, "GetViewerFrame")
        local pool = ownerOK and owner and owner.itemFramePool
        local activeOK, active = Method(pool, "IsActive", frame)
        if not activeOK or active ~= true then return false end
    end
    local ok, info = Method(frame, "GetCooldownInfo")
    info = ok and PublicTable(info)
    local idOK, id = Method(frame, "GetCooldownID")
    if not idOK then id = frame and Public(frame.cooldownID) end
    if id ~= 199342 or not info or Public(info.spellID) ~= 400574 then return false end
    local linked = PublicTable(info.linkedSpellIDs)
    return linked ~= nil and #linked == 1 and Public(linked[1]) == 400573
end

local function CancelLoss(source)
    Monitor:CancelTask(source, "native-loss")
    source.lossFrame, source.lossRevision, source.lossConfirmed, source.lossEpoch = nil, nil, nil, nil
end

local function NoteGain(source, frame)
    if source.nativeLive ~= true then
        source.nativeEpoch = (source.nativeEpoch or 0) + 1
        source.nativeLive = true
    end
    source.state.nativeFrames[frame] = source.nativeEpoch
end

local function IsCurrentFrame(frame)
    return Viewer and Viewer.GetRuntimeFrame and frame ~= nil
        and (Viewer:GetRuntimeFrame("trackedBuff", 199342) == frame
            or Viewer:GetRuntimeFrame("trackedBar", 199342) == frame)
end

local function Clear(source)
    local state = source.state
    local changed = state.available == true or state.displayCount ~= nil
    Monitor:CancelTasks(source)
    CancelLoss(source)
    source.nativePresent = nil
    state.available, state.startTime, state.displayCount = false, 0, nil
    state.publicAuraStacks = 0
    return changed
end

local function FinishWindow(source)
    Monitor:RefreshSourceNow(source, "arcane-expired")
end

local function FinishLoss(source)
    local frame, revision, confirmed, epoch = source.lossFrame, source.lossRevision, source.lossConfirmed, source.lossEpoch
    CancelLoss(source)
    if revision ~= source.castRevision or epoch < source.windowEpoch then return end
    local present, current = ReadPresence(source)
    -- Public replacement presence wins. A real removal remains evidence even
    -- after native cleanup releases/reassigns the frame or restricts its data.
    local newerGain = source.nativeLive == true and epoch < source.nativeEpoch
    local replacement = present == true and (not confirmed or current == frame
        or source.state.nativeFrames[current] == nil or newerGain)
    if replacement or newerGain then
        source.nativeFrame, source.nativePresent = current, true
    elseif confirmed or present == false and current == frame and IsCurrentFrame(frame) then
        source.nativeLive = false
        if Clear(source) then Monitor:RefreshSourceNow(source, "arcane-removed", true) end
    elseif current == frame then
        -- Keep the last known presence across an inconclusive reconciliation.
        source.nativePresent = true
    end
end

local function OnNativeRemoved(frame)
    local source = Monitor.Data.sources[Arcane.SOURCE_KEY]
    if not source or source.consumerCount <= 0
        or not IsCurrentFrame(frame) or not MatchesFrame(frame) then return end
    local ok, unit = Method(frame, "GetAuraDataUnit")
    if not ok or unit ~= "player" then return end
    local epoch = source.state.nativeFrames[frame]
    if not epoch then NoteGain(source, frame); epoch = source.nativeEpoch end
    if epoch == source.nativeEpoch then source.nativeLive = false end
    if not source.state.available or epoch < source.windowEpoch then return end
    source.lossFrame, source.lossRevision, source.lossConfirmed = frame, source.castRevision, true
    source.lossEpoch = epoch
    Monitor:ScheduleTask(source, "native-loss", GetTime() + 0.001, FinishLoss)
end

local function OnNativeApplied(frame)
    local source = Monitor.Data.sources[Arcane.SOURCE_KEY]
    if not source or source.consumerCount <= 0
        or not IsCurrentFrame(frame) or not MatchesFrame(frame) then return end
    local ok, unit = Method(frame, "GetAuraDataUnit")
    if ok and unit == "player" then NoteGain(source, frame) end
end

ReadPresence = function(source)
    if not Viewer or not Viewer.GetRuntimeFrame then return nil end
    local selected, playerFrame, absent, unknown
    for _, category in ipairs(NATIVE_CATEGORIES) do
        local frame = Viewer:GetRuntimeFrame(category, 199342)
        if MatchesFrame(frame) then
            if not selected or frame == source.nativeFrame then selected = frame end
            if not hooked[frame] and type(_G.hooksecurefunc) == "function"
                and type(frame.TriggerAuraRemovedAlert) == "function" then
                hooked[frame] = pcall(_G.hooksecurefunc, frame, "TriggerAuraRemovedAlert", OnNativeRemoved) or nil
            end
            if not gainHooked[frame] and type(_G.hooksecurefunc) == "function"
                and type(frame.TriggerAuraAppliedAlert) == "function" then
                gainHooked[frame] = pcall(_G.hooksecurefunc, frame, "TriggerAuraAppliedAlert", OnNativeApplied) or nil
            end
            local ok, unit = Method(frame, "GetAuraDataUnit")
            if ok and unit == "player" then
                local epochs = source.state.nativeFrames
                if epochs[frame] == nil and source.nativeLive == true then epochs[frame] = source.nativeEpoch end
                if not playerFrame or (epochs[frame] or 0) > (epochs[playerFrame] or 0) then playerFrame = frame end
            elseif ok and unit == nil then absent = true
            else unknown = true end
        end
    end
    if playerFrame then return true, playerFrame end
    if absent and not unknown then return false, selected end
    return nil, selected
end

local function ObserveNative(source, reconcile)
    local present, frame = ReadPresence(source)
    local sameFrame = source.nativeFrame == frame
    local previous = sameFrame and source.nativePresent or nil
    source.nativeFrame = frame
    if not sameFrame then source.nativePresent = nil end
    if present == true then NoteGain(source, frame) end
    if present ~= nil then source.nativePresent = present
    elseif not frame then source.nativePresent = nil end
    -- Only a settled native refresh may reconcile an observed player aura.
    -- Initial discovery, a hidden/recycled frame and unknown data are not loss.
    if reconcile and previous == true and present == false
        and source.state.available and not source.lossConfirmed then
        source.lossFrame, source.lossRevision, source.lossConfirmed = frame, source.castRevision, false
        source.lossEpoch = source.nativeEpoch or 0
        Monitor:ScheduleTask(source, "native-loss", GetTime() + 0.001, FinishLoss)
    end
    return false
end

local function Cast(source, state, _, unit, guid, spellID)
    unit, spellID, guid = Public(unit), Public(spellID), Public(guid)
    if unit ~= "player" or not CASTS[spellID] then return false end
    if type(guid) == "string" and guid ~= "" then
        if state.seenCasts[guid] then return false end
        local index = state.castCursor % 16 + 1
        local previous = state.castOrder[index]
        if previous then state.seenCasts[previous] = nil end
        state.castOrder[index], state.seenCasts[guid], state.castCursor = guid, true, index
    end
    source.castRevision = (source.castRevision or 0) + 1
    if source.lossRevision ~= nil then
        local present, frame = ReadPresence(source)
        if (source.lossConfirmed and source.lossEpoch >= source.windowEpoch)
            or present == false and frame == source.lossFrame and source.lossEpoch >= source.windowEpoch
            and IsCurrentFrame(frame) then Clear(source) end
    end
    CancelLoss(source)
    local now = GetTime()
    if not state.available or now >= state.startTime + DURATION then
        Clear(source)
        local epoch = source.nativeEpoch or 0
        source.windowEpoch = source.nativeLive == true and epoch ~= source.windowEpoch and epoch or epoch + 1
        local scheduled, code = Monitor:ScheduleTask(source, "window-end", now + DURATION, FinishWindow)
        state.issue = not scheduled and code or nil
        state.available, state.startTime = scheduled == true, scheduled and now or 0
        state.displayCount = scheduled and 1 or nil
        source.dirty = true
    elseif state.displayCount < MAX_STACKS then
        state.displayCount = state.displayCount + 1
        source.dirty = true
    end
    state.publicAuraStacks = state.displayCount or 0
    return source.dirty == true
end

local function Read(source, state, reason)
    local changed = source.dirty == true
    source.dirty = nil
    if reason == "PLAYER_DEAD" or state.available and GetTime() >= state.startTime + DURATION then
        changed = Clear(source) or changed
    end
    ObserveNative(source, reason == "arcane-native-refresh")
    return changed
end

local function OnEvent(source, state, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then return Cast(source, state, event, ...) end
    return true
end

local function CastIdentity(value)
    value = Public(value)
    return type(value) == "number" and value or nil
end

function Arcane:RegisterSourceType()
    if self.registered then return true end
    Monitor, Viewer = YUI.Monitor, YUI.API and YUI.API.CooldownViewer
    local registered, code = Monitor:RegisterSourceType(self.SOURCE_TYPE, {
        createState = function(params)
            return { sourceKind = "aura", spellID = 400574, icon = params.icon,
                startTime = 0, duration = DURATION, publicAuraStacks = 0, available = false, resolved = true,
                isEnabled = true, secret = false, seenCasts = {}, castOrder = {}, castCursor = 0,
                nativeFrames = setmetatable({}, { __mode = "k" }) }
        end,
        getIdentity = function() return { 400574, 1239696, 1239697, 1239699, 1239700, AURA_IDENTITY } end,
        read = Read, onEvent = OnEvent,
        events = {
            { event = "UNIT_SPELLCAST_SUCCEEDED", unit = "player", identityArg = 3,
                mapIdentity = CastIdentity, synchronous = true, identityReason = "arcane-cast" },
            { event = Viewer and Viewer.AURA_REFRESH_EVENT or "YUI_COOLDOWN_VIEWER_AURA_REFRESH",
                identityArgs = { 1, 2 }, identityReason = "arcane-native-refresh",
                allWhenIdentityMissing = true, missingAllReason = "arcane-native-refresh" },
            { event = "PLAYER_DEAD", all = true, synchronous = true },
            { event = "PLAYER_ENTERING_WORLD", all = true },
            { event = "PLAYER_REGEN_ENABLED", all = true },
        },
    })
    if not registered and code ~= "source-type-exists" then return nil, code end
    self.registered = true
    return true
end
