local YUI = _G.YUI
local YChat = YUI and YUI.YChat
if not YChat or (YUI.IsForever or YUI.IsRetail) ~= true then return end

local Adapter = YChat.Adapter
if not Adapter then return end
local Animation = YUI.Animation
local Visibility = YUI.Visibility

local ElementFade = {}
YChat.ElementFade = ElementFade

local frameStates = setmetatable({}, { __mode = "k" })
local hoverFrames = setmetatable({}, { __mode = "k" })
local hoverHooks = setmetatable({}, { __mode = "k" })
local editFocusHooks = setmetatable({}, { __mode = "k" })
local nativeHooks = {}
local settingsEventOwner = {}
local integrationEventOwner = {}
local visibilityOwner = {}
local linkedHidden = false
local statsLinkedHidden = false
local fadeConfigured = false
local fadeChatBarConfigured = false
local fadeActive = false
local chatBarLinkActive = false
local statsLinkActive = false
local fadeScope = "solo"
local fadeStatsMode = "none"
local instanceStateKnown = false
local inInstance = false
local instanceType = "unknown"
local groupStateKnown = false
local inGroup = false
local scopeEligible = true
local scopeConditionMatched = true
local statsConditionMatched = false
local scopeContextInitialized = false
local settingsOpen = false
local restrictionOpen = false
local scopeVisibilityHandle
local statsVisibilityHandle
local visibilityWatchRefreshActive = false
local schedulerNow = 0
local nextDueAt
local schedulerTimer
local schedulerWakeAt
local activeAnimations = 0
local RefreshNextDueAt
local ReconcileSchedulerTimer
local SchedulerTimerFired

local DEFAULT_TIME_VISIBLE = 120
local FADE_OUT_DURATION = 0.5
local DEFAULT_FADE_IN_DURATION = 0.15
local SUBMIT_ECHO_GRACE_DURATION = 5
local VALID_FADE_SCOPES = {
    all = true,
    outsideInstance = true,
    insideInstance = true,
    outOfCombat = true,
    solo = true,
}
local VALID_FADE_STATS_MODES = {
    none = true,
    all = true,
    outOfCombat = true,
    inCombat = true,
}

ElementFade.enabled = false
ElementFade.lastReason = "not-started"

local function GetConfig()
    local appearance = YChat:GetAppearance()
    return type(appearance) == "table" and appearance or YChat.Defaults.appearance
end

local function WantsElementFade()
    return fadeActive == true
end

local function UpdateSchedulerNow()
    if type(Adapter.ReadMonotonicTime) == "function" then
        local now = Adapter:ReadMonotonicTime()
        if type(now) == "number" and now > schedulerNow then
            schedulerNow = now
        end
    end
    return schedulerNow
end

local function ReadSettingsOpen()
    local settings = YUI.Settings
    local callback = settings and settings.IsOpen
    if type(callback) ~= "function" then return false end
    local ok, open = pcall(callback, settings)
    return ok and open == true
end

local function ReadVisibilityState(stateKey)
    if not Visibility or type(Visibility.GetState) ~= "function" then return nil end
    local ok, value = pcall(Visibility.GetState, Visibility, stateKey)
    if not ok or type(value) ~= "boolean" then return nil end
    return value
end

local function ReleaseVisibilityHandle(handle)
    if handle and Visibility and type(Visibility.Release) == "function" then
        pcall(Visibility.Release, Visibility, handle)
    end
    return nil
end

local function OnScopeVisibilityChanged()
    if visibilityWatchRefreshActive or ElementFade.enabled ~= true then return end
    ElementFade:OnContextChanged("element-fade-scope-visibility-changed")
end

local function OnStatsVisibilityChanged()
    if visibilityWatchRefreshActive or ElementFade.enabled ~= true then return end
    ElementFade:OnContextChanged("element-fade-stats-visibility-changed")
end

local function ConfigureVisibilityHandle(handle, rule, callback, context)
    if not Visibility
        or type(Visibility.Watch) ~= "function"
        or type(Visibility.Update) ~= "function"
    then
        return ReleaseVisibilityHandle(handle)
    end
    if handle then
        local ok, updated = pcall(Visibility.Update, Visibility, handle, rule)
        if ok and updated == true then return handle end
        handle = ReleaseVisibilityHandle(handle)
    end
    local ok, created = pcall(Visibility.Watch, Visibility, visibilityOwner, rule, callback, {
        moduleId = "ychat",
        context = context,
    })
    return ok and created or nil
end

local function ResetVisibilityState()
    instanceStateKnown = false
    inInstance = false
    instanceType = "unknown"
    groupStateKnown = false
    inGroup = false
    scopeConditionMatched = fadeScope == "all"
    statsConditionMatched = fadeStatsMode == "all"
end

local function RefreshVisibilityState()
    local instance = ReadVisibilityState("instance")
    local combat = ReadVisibilityState("combat")
    local grouped = ReadVisibilityState("group")
    instanceStateKnown = instance ~= nil
    inInstance = instance == true
    instanceType = instance == nil and "unknown" or (instance and "inside" or "outside")
    groupStateKnown = grouped ~= nil
    inGroup = grouped == true
    if fadeScope == "all" then
        scopeConditionMatched = true
    elseif fadeScope == "outsideInstance" then
        scopeConditionMatched = instance == false
    elseif fadeScope == "insideInstance" then
        scopeConditionMatched = instance == true
    elseif fadeScope == "solo" then
        scopeConditionMatched = grouped == false
    else
        scopeConditionMatched = combat == false
    end
    if fadeStatsMode == "all" then
        statsConditionMatched = true
    elseif fadeStatsMode == "outOfCombat" then
        statsConditionMatched = combat == false
    elseif fadeStatsMode == "inCombat" then
        statsConditionMatched = combat == true
    else
        statsConditionMatched = false
    end
end

local function DetachVisibilityWatches()
    visibilityWatchRefreshActive = true
    scopeVisibilityHandle = ReleaseVisibilityHandle(scopeVisibilityHandle)
    statsVisibilityHandle = ReleaseVisibilityHandle(statsVisibilityHandle)
    if Visibility and type(Visibility.ReleaseOwner) == "function" then
        pcall(Visibility.ReleaseOwner, Visibility, visibilityOwner)
    end
    visibilityWatchRefreshActive = false
    ResetVisibilityState()
end

local function RefreshVisibilityWatches()
    visibilityWatchRefreshActive = true
    if not fadeConfigured or ElementFade.enabled ~= true then
        scopeVisibilityHandle = ReleaseVisibilityHandle(scopeVisibilityHandle)
    elseif fadeScope == "outsideInstance" then
        scopeVisibilityHandle = ConfigureVisibilityHandle(
            scopeVisibilityHandle,
            { instance = "inside" },
            OnScopeVisibilityChanged,
            "outsideInstance"
        )
    elseif fadeScope == "insideInstance" then
        scopeVisibilityHandle = ConfigureVisibilityHandle(
            scopeVisibilityHandle,
            { instance = "outside" },
            OnScopeVisibilityChanged,
            "insideInstance"
        )
    elseif fadeScope == "outOfCombat" then
        scopeVisibilityHandle = ConfigureVisibilityHandle(
            scopeVisibilityHandle,
            { combat = "in" },
            OnScopeVisibilityChanged,
            "outOfCombat"
        )
    elseif fadeScope == "solo" then
        scopeVisibilityHandle = ConfigureVisibilityHandle(
            scopeVisibilityHandle,
            { group = "grouped" },
            OnScopeVisibilityChanged,
            "solo"
        )
    else
        scopeVisibilityHandle = ReleaseVisibilityHandle(scopeVisibilityHandle)
    end

    if not fadeConfigured or ElementFade.enabled ~= true then
        statsVisibilityHandle = ReleaseVisibilityHandle(statsVisibilityHandle)
    elseif fadeStatsMode == "outOfCombat" then
        statsVisibilityHandle = ConfigureVisibilityHandle(
            statsVisibilityHandle,
            { combat = "in" },
            OnStatsVisibilityChanged,
            "statsOutOfCombat"
        )
    elseif fadeStatsMode == "inCombat" then
        statsVisibilityHandle = ConfigureVisibilityHandle(
            statsVisibilityHandle,
            { combat = "out" },
            OnStatsVisibilityChanged,
            "statsInCombat"
        )
    else
        statsVisibilityHandle = ReleaseVisibilityHandle(statsVisibilityHandle)
    end

    if fadeConfigured and ElementFade.enabled == true then
        RefreshVisibilityState()
    else
        ResetVisibilityState()
    end
    visibilityWatchRefreshActive = false
end

local function RefreshEffectiveState()
    scopeEligible = scopeConditionMatched == true
    fadeActive = ElementFade.enabled == true
        and fadeConfigured == true
        and scopeEligible == true
        and restrictionOpen == true
    chatBarLinkActive = fadeActive and fadeChatBarConfigured == true
    statsLinkActive = fadeActive
        and fadeStatsMode ~= "none"
        and statsConditionMatched == true
end

local function RefreshConfigState(refreshVisibility, restrictionState)
    local config = GetConfig()
    fadeConfigured = config.fadeElements == true
    fadeChatBarConfigured = config.fadeChatBar == true
    local configuredScope = type(config.fadeScope) == "string" and config.fadeScope or "solo"
    fadeScope = VALID_FADE_SCOPES[configuredScope] and configuredScope or "solo"
    local configuredStatsMode = type(config.fadeStatsMode) == "string"
        and config.fadeStatsMode or "none"
    fadeStatsMode = VALID_FADE_STATS_MODES[configuredStatsMode]
        and configuredStatsMode or "none"
    if refreshVisibility == true then RefreshVisibilityWatches() end
    if type(restrictionState) ~= "string" then
        restrictionState = Adapter:GetRestrictionState()
    end
    restrictionOpen = restrictionState == "OPEN"
    RefreshEffectiveState()
end

local function Clamp01(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function ReadFrameNumber(frame, methodName, fallback, minimum, maximum)
    local method = frame and frame[methodName]
    if type(method) ~= "function" then return fallback end
    local ok, value = pcall(method, frame)
    if not ok or type(value) ~= "number" then return fallback end
    if value < minimum or value > maximum then return fallback end
    return value
end

local function GetFadeDuration()
    return FADE_OUT_DURATION
end

local function GetTimeVisible(frame)
    local config = GetConfig()
    local configured = type(config) == "table" and tonumber(config.fadeDelay) or nil
    if configured and configured >= 10 and configured <= 600 then
        return configured
    end
    return ReadFrameNumber(frame, "GetTimeVisible", DEFAULT_TIME_VISIBLE, 0, 3600)
end

local function GetFadeInDuration()
    local duration = tonumber(_G.CHAT_FRAME_FADE_TIME)
    if not duration or duration < 0 or duration > 5 then
        return DEFAULT_FADE_IN_DURATION
    end
    return duration
end

local function GetOwner(frame)
    local state = frame and frameStates[frame]
    return state and state.owner or nil
end

local function GetOwnerState(frame)
    local owner = GetOwner(frame)
    return owner, owner and frameStates[owner] or nil
end

local function EmitLinkedVisibility(duration, forceStats)
    local main = _G.ChatFrame1
    local owner, state = GetOwnerState(main)
    local hidden = WantsElementFade()
        and chatBarLinkActive
        and owner == main
        and state ~= nil
        and state.hidden == true
    if hidden ~= linkedHidden then
        linkedHidden = hidden
        if YUI.Event and type(YUI.Event.Emit) == "function" then
            YUI.Event:Emit("YUI_CHAT_ELEMENT_FADE", hidden, duration or 0)
        elseif YUI.ChatBar and type(YUI.ChatBar.SetLinkedFadeHidden) == "function" then
            YUI.ChatBar:SetLinkedFadeHidden(hidden, duration or 0)
        end
    end

    local statsHidden = WantsElementFade()
        and statsLinkActive
        and owner == main
        and state ~= nil
        and state.hidden == true
    if forceStats == true or statsHidden ~= statsLinkedHidden then
        statsLinkedHidden = statsHidden
        if YUI.Event and type(YUI.Event.Emit) == "function" then
            YUI.Event:Emit("YUI_CHAT_STATS_FADE", statsHidden, duration or 0)
        end
    end
end

local function CanWriteBody(frame, state)
    if not frame or not state or state.bodyReady ~= true then
        return false, "element-fade-body-alpha-unavailable"
    end
    if type(frame.SetAlpha) ~= "function" then
        return false, "element-fade-body-set-alpha-unavailable"
    end
    if type(Adapter.CanCallProtected) ~= "function"
        or Adapter:CanCallProtected(frame) ~= true
    then
        return false, "element-fade-body-restricted"
    end
    return true
end

local function ApplyMember(frame, state, visibility, cancelNativeFade)
    local writable, writableReason = CanWriteBody(frame, state)
    if not writable then return false, writableReason end

    local appearance = YChat.Appearance
    if not appearance or type(appearance.ApplyElementFade) ~= "function" then
        return false, "appearance-element-fade-unavailable"
    end
    visibility = Clamp01(visibility)
    local ok, applied, reason = pcall(
        appearance.ApplyElementFade,
        appearance,
        frame,
        visibility,
        cancelNativeFade == true
    )
    if not ok or applied ~= true then
        return false, reason or "appearance-element-fade-apply-failed"
    end

    local combatLog = YChat.CombatLog
    if frame == _G.ChatFrame2
        and combatLog
        and type(combatLog.ApplyElementFade) == "function"
    then
        local combatOK, combatApplied, combatReason = pcall(
            combatLog.ApplyElementFade,
            combatLog,
            visibility,
            cancelNativeFade == true
        )
        if not combatOK or combatApplied ~= true then
            return false, combatReason or "combat-log-element-fade-apply-failed"
        end
    end

    local bodyOK = pcall(frame.SetAlpha, frame, state.bodyAlpha * visibility)
    if not bodyOK then return false, "element-fade-body-alpha-write-failed" end
    return true
end

local function CanApplyScope(owner)
    if not owner or not frameStates[owner] then
        return false, "element-fade-owner-unregistered"
    end
    local found = false
    for frame, state in pairs(frameStates) do
        if state.owner == owner then
            found = true
            local writable, reason = CanWriteBody(frame, state)
            if not writable then return false, reason end
        end
    end
    return found, found and nil or "element-fade-scope-empty"
end

local function RestoreScopeMembers(owner, cancelNativeFade)
    local firstReason
    for frame, state in pairs(frameStates) do
        if state.owner == owner then
            local restored, reason = ApplyMember(frame, state, 1, cancelNativeFade)
            if not restored and not firstReason then firstReason = reason end
        end
    end
    return firstReason == nil, firstReason
end

local function CompleteHideRequest(owner, state)
    if not state
        or state.hidden ~= true
        or state.visibility > 0
        or state.animation
    then
        return
    end
    local callback = state.hideCompletion
    state.hideCompletion = nil
    if type(callback) ~= "function" then return end
    local ok, reason = pcall(callback, owner)
    if not ok then
        ElementFade.lastReason = reason or "element-fade-hide-callback-failed"
    end
end

local function FailScopeOpen(owner, reason)
    local state = owner and frameStates[owner]
    if state then
        state.hidden = false
        state.visibility = 1
        state.expired = false
        state.dueAt = nil
        state.animation = nil
        state.hideCompletion = nil
    end
    RestoreScopeMembers(owner, true)
    EmitLinkedVisibility()
    ElementFade.lastReason = reason or "element-fade-scope-fail-open"
    return false, ElementFade.lastReason
end

local function ApplyScope(owner, visibility, cancelNativeFade)
    local applicable, applicableReason = CanApplyScope(owner)
    if not applicable then return false, applicableReason end
    local combatLogApplied = false
    for frame, state in pairs(frameStates) do
        if state.owner == owner then
            local applied, reason = ApplyMember(
                frame,
                state,
                visibility,
                cancelNativeFade
            )
            if not applied then
                RestoreScopeMembers(owner, true)
                return false, reason
            end
            if frame == _G.ChatFrame2 then combatLogApplied = true end
        end
    end
    if owner == _G.ChatFrame1 and not combatLogApplied then
        local combatLog = YChat.CombatLog
        local combatState = combatLog and combatLog.state
        local targets = combatState and combatState.targets
        if combatLog
            and combatLog.enabled == true
            and combatState.applied == true
            and combatState.restorePending ~= true
            and combatState.hidden ~= true
            and targets
            and targets.frame == _G.ChatFrame2
            and targets.tab == _G.ChatFrame2Tab
            and type(combatLog.ApplyElementFade) == "function"
        then
            local ok, applied, reason = pcall(
                combatLog.ApplyElementFade,
                combatLog,
                visibility,
                cancelNativeFade == true
            )
            if not ok or applied ~= true then
                RestoreScopeMembers(owner, true)
                return false, reason or "combat-log-owner-fade-apply-failed"
            end
        end
    end
    return true
end

local function OnTransitionUpdate(value, _, _, handle)
    local owner = handle and handle.target
    local state = owner and frameStates[owner]
    if not state or state.owner ~= owner then return end
    state.visibility = Clamp01(value)
    local applied, reason = ApplyScope(owner, state.visibility, false)
    if not applied then
        if Animation and type(Animation.StopTarget) == "function" then
            Animation:StopTarget(owner, "element-visibility", false)
        end
        FailScopeOpen(owner, reason)
    end
end

local function OnTransitionFinished(handle, reason, finished)
    if activeAnimations > 0 then activeAnimations = activeAnimations - 1 end
    if handle then handle._ychatElementFadeFinished = true end
    local owner = handle and handle.target
    local state = owner and frameStates[owner]
    if not state or state.owner ~= owner then return end
    if state.animation == handle then state.animation = nil end
    if finished == true then
        state.visibility = state.hidden and 0 or 1
        local applied, applyReason = ApplyScope(owner, state.visibility, false)
        if not applied then
            FailScopeOpen(owner, applyReason)
        else
            CompleteHideRequest(owner, state)
        end
    elseif reason and reason ~= "replaced" and reason ~= "stopped" then
        ElementFade.lastReason = reason
    end
end

local function SetOwnerHidden(owner, hidden, reason, duration)
    local state = owner and frameStates[owner]
    if not state or state.owner ~= owner then
        return false, "element-fade-owner-unregistered"
    end
    hidden = WantsElementFade() and hidden == true
    if hidden and state.hoverProxyBlocked == true then
        return FailScopeOpen(owner, "element-fade-hover-proxy-unavailable")
    end
    if not hidden then state.hideCompletion = nil end
    local target = hidden and 0 or 1
    if state.hidden == hidden and not state.animation and state.visibility == target then
        CompleteHideRequest(owner, state)
        return true, false
    end

    local previousHidden = state.hidden
    state.hidden = hidden
    duration = tonumber(duration) or 0
    if duration < 0 then duration = 0 end
    local applied, applyReason = ApplyScope(owner, state.visibility, true)
    if not applied then
        state.hidden = previousHidden
        return FailScopeOpen(owner, applyReason)
    end
    EmitLinkedVisibility(duration)

    if state.visibility == target then
        if Animation and type(Animation.StopTarget) == "function" then
            Animation:StopTarget(owner, "element-visibility", false)
        end
        state.animation = nil
    elseif duration > 0 and Animation and type(Animation.Tween) == "function" then
        activeAnimations = activeAnimations + 1
        local handle = Animation:Tween({
            target = owner,
            owner = ElementFade,
            key = "element-visibility",
            from = state.visibility,
            to = target,
            duration = duration,
            easing = "linear",
            onUpdate = OnTransitionUpdate,
            onFinished = OnTransitionFinished,
        })
        if not handle or handle.noop == true then
            activeAnimations = math.max(0, activeAnimations - 1)
            state.visibility = target
            state.animation = nil
            applied, applyReason = ApplyScope(owner, target, false)
            if not applied then return FailScopeOpen(owner, applyReason) end
        elseif handle._ychatElementFadeFinished ~= true then
            state.animation = handle
        end
    else
        if Animation and type(Animation.StopTarget) == "function" then
            Animation:StopTarget(owner, "element-visibility", false)
        end
        state.visibility = target
        state.animation = nil
        applied, applyReason = ApplyScope(owner, target, false)
        if not applied then return FailScopeOpen(owner, applyReason) end
    end
    ElementFade.lastReason = reason or (hidden
        and "element-fade-hidden"
        or "element-fade-shown")
    CompleteHideRequest(owner, state)
    return true, true
end

local function ResetFrameFadeTimes(frame)
    if not frame or type(frame.ResetAllFadeTimes) ~= "function" then return true end
    local ok = pcall(frame.ResetAllFadeTimes, frame)
    if not ok then ElementFade.lastReason = "element-fade-reset-times-failed" end
    return ok
end

local function BeginInteraction(frame, reason)
    if ElementFade.enabled ~= true or fadeConfigured ~= true then return end
    local owner, state = GetOwnerState(frame)
    if not state then return end
    ResetFrameFadeTimes(frame)
    state.interacting = true
    state.hoverActive = true
    SetOwnerHidden(owner, false, reason, GetFadeInDuration())
end

local function EndHoverInteraction(owner, state)
    state.interacting = false
    if state.hoverActive ~= true then return end
    state.hoverActive = nil
    if state.inputHidePending then return end
    UpdateSchedulerNow()
    -- 悬停唤醒视为新活动；重复的停靠成员淡出回调不能反复续期。
    state.lastMessageAt = schedulerNow
    state.expired = false
    state.dueAt = schedulerNow + GetTimeVisible(owner)
    RefreshNextDueAt()
end

local function OnHoverEnter(object)
    BeginInteraction(hoverFrames[object], "element-fade-hover")
end

local function OnOverlayHoverChanged(frame, hovered)
    if not ElementFade.enabled or not WantsElementFade() then return end
    if hovered == true then
        BeginInteraction(frame, "element-fade-overlay-hover")
        return
    end
    local owner, state = GetOwnerState(frame)
    if not state then return end
    EndHoverInteraction(owner, state)
    if state.expired == true and state.editActive ~= true then
        SetOwnerHidden(owner, true, "element-fade-overlay-leave", GetFadeDuration(owner))
    end
end

local function OnEditFocusGained(editBox)
    if ElementFade.enabled ~= true or fadeConfigured ~= true then return end
    local frame = hoverFrames[editBox]
    local owner, state = GetOwnerState(frame)
    if state then
        ResetFrameFadeTimes(frame)
        state.editStartedExpired = state.expired == true or state.hidden == true
        state.editMessageGeneration = state.messageGeneration or 0
        state.editActive = true
        state.interacting = true
        SetOwnerHidden(owner, false, "element-fade-input-active", GetFadeInDuration())
    end
end

local function OnEditFocusLost(editBox)
    if ElementFade.enabled ~= true or fadeConfigured ~= true then return end
    local frame = hoverFrames[editBox]
    local owner, state = GetOwnerState(frame)
    if not state then return end
    state.editActive = false
    state.interacting = false
    -- Focus can end while the pointer stays over a docked sibling or its controls.
    if not state.inputHidePending and type(Adapter.IsObjectMouseOver) == "function" then
        for object, hoveredFrame in pairs(hoverFrames) do
            if object ~= editBox and GetOwner(hoveredFrame) == owner
                and Adapter:IsObjectMouseOver(object) == true then
                state.interacting = true
                break
            end
        end
    end
    if state.expired == true or state.editStartedExpired == true then
        UpdateSchedulerNow()
        state.lastMessageAt = nil
        state.expired = false
        state.dueAt = schedulerNow + (state.inputHidePending and 0 or GetTimeVisible(owner))
        RefreshNextDueAt()
        ElementFade.lastReason = "element-fade-input-ended-pending"
    end
    state.inputHidePending = nil
end

local function OnEditEnterPressed(editBox)
    if ElementFade.enabled ~= true or fadeConfigured ~= true then return end
    local frame = hoverFrames[editBox]
    local _, state = GetOwnerState(frame)
    if not state or state.editStartedExpired ~= true then return end
    local generation = state.messageGeneration or 0
    local messageArrived = generation ~= (state.editMessageGeneration or generation)
    state.editStartedExpired = false
    state.editMessageGeneration = nil
    if messageArrived then return end
    UpdateSchedulerNow()
    state.lastMessageAt = nil
    state.expired = false
    state.dueAt = schedulerNow + SUBMIT_ECHO_GRACE_DURATION
    RefreshNextDueAt()
    ElementFade.lastReason = "element-fade-submit-echo-pending"
end

local function HookHoverObject(object, frame)
    if not object or type(object.HookScript) ~= "function" then return true end
    hoverFrames[object] = frame
    if hoverHooks[object] == true then return true end
    local ok = pcall(object.HookScript, object, "OnEnter", OnHoverEnter)
    if ok then hoverHooks[object] = true end
    return ok
end

local function HookEditBox(editBox, frame)
    if not editBox or type(editBox.HookScript) ~= "function" then return true end
    hoverFrames[editBox] = frame
    if editFocusHooks[editBox] == true then return true end
    local ok = pcall(editBox.HookScript, editBox, "OnEditFocusGained", OnEditFocusGained)
    if ok then ok = pcall(editBox.HookScript, editBox, "OnEditFocusLost", OnEditFocusLost) end
    if ok then ok = pcall(editBox.HookScript, editBox, "OnEnterPressed", OnEditEnterPressed) end
    if ok then editFocusHooks[editBox] = true end
    return ok
end

local function CaptureBodyAlpha(frame, state)
    if state.bodyReady == true then return true end
    if type(frame.GetAlpha) ~= "function" or type(frame.SetAlpha) ~= "function" then
        return false, "element-fade-body-alpha-unavailable"
    end
    if type(Adapter.CanCallProtected) ~= "function"
        or Adapter:CanCallProtected(frame) ~= true
    then
        return false, "element-fade-body-restricted"
    end
    local ok, alpha = pcall(frame.GetAlpha, frame)
    if not ok or type(alpha) ~= "number" or alpha < 0 or alpha > 1 then
        return false, "element-fade-body-alpha-invalid"
    end
    state.bodyAlpha = alpha
    state.bodyReady = true
    return true
end

local function RegisterFrame(frame)
    if not frame then return end
    local state = frameStates[frame]
    if not state then
        state = {
            hidden = false,
            visibility = 1,
            expired = false,
            interacting = false,
            editActive = false,
            messageGeneration = 0,
        }
        frameStates[frame] = state
    end
    local captured, reason = CaptureBodyAlpha(frame, state)
    if not captured then ElementFade.lastReason = reason end
    state.hoverProxyRequired = type(Adapter.IsTrustedSupportedFrame) == "function"
        and Adapter:IsTrustedSupportedFrame(frame) == true
    state.hoverProxyReady = state.hoverProxyRequired ~= true
    if state.hoverProxyRequired then
        local installed, installReason = false, "element-fade-hover-proxy-api-missing"
        if type(Adapter.InstallInteractionHoverProxy) == "function" then
            installed, installReason = Adapter:InstallInteractionHoverProxy(
                frame,
                OnOverlayHoverChanged
            )
        end
        state.hoverProxyReady = installed == true
        if not installed then ElementFade.lastReason = installReason end
    end
    HookHoverObject(frame, frame)
    HookHoverObject(frame.buttonFrame, frame)
    HookHoverObject(frame.ScrollBar, frame)
    HookHoverObject(frame.ScrollToBottomButton, frame)
    local name
    if type(frame.GetName) == "function" then
        local ok, value = pcall(frame.GetName, frame)
        if ok and type(value) == "string" then name = value end
    end
    local tab = type(name) == "string" and _G[name .. "Tab"] or nil
    HookHoverObject(tab, frame)
    local editBox = frame.editBox
        or (type(name) == "string" and _G[name .. "EditBox"] or nil)
    HookHoverObject(editBox, frame)
    HookEditBox(editBox, frame)
end

local function IsStrictCombatLogFrame(frame)
    local combatLog = YChat.CombatLog
    local state = combatLog and combatLog.state
    local targets = state and state.targets
    if not combatLog
        or combatLog.enabled ~= true
        or not state
        or state.applied ~= true
        or state.restorePending == true
        or state.hidden == true
        or not targets
        or targets.frame ~= frame
        or targets.frame ~= _G.ChatFrame2
        or targets.tab ~= _G.ChatFrame2Tab
    then
        return false
    end
    return true
end

local function RegisterStrictCombatLogFrame()
    local frame = _G.ChatFrame2
    if not IsStrictCombatLogFrame(frame) then return false end
    RegisterFrame(frame)
    return true
end

local function ResolveDesiredOwner(frame)
    local main = _G.ChatFrame1
    if frame == main then return frame end
    if not main or not frameStates[main] then return frame end
    if type(Adapter.ReadAppearanceTabDocked) ~= "function" then return nil end
    local docked = Adapter:ReadAppearanceTabDocked(frame)
    if docked == true then return main end
    if docked == false then return frame end
    return nil
end

local function ResetOwnerState(state)
    state.hidden = false
    state.visibility = 1
    state.expired = false
    state.dueAt = nil
    state.interacting = false
    state.editActive = false
    state.animation = nil
    state.lastMessageAt = nil
    state.editStartedExpired = nil
    state.editMessageGeneration = nil
    state.hideCompletion = nil
    state.inputHidePending = nil
    state.hoverActive = nil
end

local function ReassignOwners()
    for frame, state in pairs(frameStates) do
        local desired = ResolveDesiredOwner(frame)
        if state.owner ~= desired then
            local oldOwner = state.owner
            if oldOwner == frame and Animation and type(Animation.StopTarget) == "function" then
                Animation:StopTarget(frame, "element-visibility", false)
            end
            ApplyMember(frame, state, 1, true)
            state.owner = desired
            state.dueAt = nil
            if desired == frame then
                ResetOwnerState(state)
            elseif oldOwner == frame then
                ResetOwnerState(state)
                state.owner = desired
            end
        end
    end
    for frame, state in pairs(frameStates) do
        if state.owner == frame then state.hoverProxyBlocked = false end
    end
    for _, state in pairs(frameStates) do
        local ownerState = state.owner and frameStates[state.owner]
        if ownerState
            and state.hoverProxyRequired == true
            and state.hoverProxyReady ~= true
        then
            ownerState.hoverProxyBlocked = true
        end
    end
end

local function NativeFadeIn(frame)
    if not ElementFade.enabled or not WantsElementFade() then return end
    local owner, state = GetOwnerState(frame)
    if state then
        state.interacting = true
        state.hoverActive = true
        SetOwnerHidden(owner, false, "element-fade-native-in", GetFadeInDuration())
    end
end

local function NativeFadeOut(frame)
    if not ElementFade.enabled or not WantsElementFade() then return end
    local owner, state = GetOwnerState(frame)
    if state then
        EndHoverInteraction(owner, state)
        if settingsOpen == true then
            SetOwnerHidden(owner, false, "element-fade-settings-open", 0)
        elseif state.expired == true and state.editActive ~= true then
            SetOwnerHidden(owner, true, "element-fade-native-out", GetFadeDuration(owner))
        elseif state.hidden ~= true then
            -- Blizzard recursively fades every docked frame. Each post-hook therefore
            -- only needs to repair the frame that was just mutated; rescanning and
            -- rewriting the whole dock here turns one native transition into O(n^2)
            -- work across all permanent chat windows.
            local memberState = frameStates[frame]
            local applied, reason = memberState
                and ApplyMember(frame, memberState, state.visibility, true)
                or true
            if not applied then FailScopeOpen(owner, reason) end
        end
    end
end

RefreshNextDueAt = function()
    local nextDue
    for frame, state in pairs(frameStates) do
        local dueAt = state.owner == frame and state.dueAt or nil
        if type(dueAt) == "number" and (not nextDue or dueAt < nextDue) then
            nextDue = dueAt
        end
    end
    nextDueAt = nextDue
    if ReconcileSchedulerTimer then ReconcileSchedulerTimer() end
end

local function CancelSchedulerTimer()
    local timer = schedulerTimer
    schedulerTimer = nil
    schedulerWakeAt = nil
    if timer and type(Adapter.CancelOneShotTimer) == "function" then
        return Adapter:CancelOneShotTimer(timer)
    end
    return timer == nil
end

ReconcileSchedulerTimer = function()
    if ElementFade.enabled ~= true
        or not WantsElementFade()
        or type(nextDueAt) ~= "number"
    then
        return CancelSchedulerTimer()
    end
    if schedulerTimer
        and type(schedulerWakeAt) == "number"
        and schedulerWakeAt <= nextDueAt
    then
        return true
    end

    CancelSchedulerTimer()
    if type(Adapter.CreateOneShotTimer) ~= "function" then
        ElementFade.lastReason = "element-fade-scheduler-api-missing"
        return false
    end
    local delay = nextDueAt - schedulerNow
    if delay < 0 then delay = 0 end
    local timer, reason = Adapter:CreateOneShotTimer(delay, SchedulerTimerFired)
    if not timer then
        ElementFade.lastReason = reason or "element-fade-scheduler-create-failed"
        return false
    end
    schedulerTimer = timer
    schedulerWakeAt = nextDueAt
    return true
end

local function RecalculateDueTimes()
    UpdateSchedulerNow()
    for owner, state in pairs(frameStates) do
        if state.owner == owner and type(state.lastMessageAt) == "number" then
            local dueAt = state.lastMessageAt + GetTimeVisible(owner)
            if dueAt <= schedulerNow then
                state.dueAt = nil
                state.expired = true
                if settingsOpen ~= true
                    and state.interacting ~= true
                    and state.editActive ~= true
                then
                    SetOwnerHidden(
                        owner,
                        true,
                        "element-fade-delay-expired",
                        GetFadeDuration(owner)
                    )
                end
            elseif state.expired ~= true then
                state.dueAt = dueAt
            end
        end
    end
    RefreshNextDueAt()
end

SchedulerTimerFired = function()
    local wakeAt = schedulerWakeAt
    schedulerTimer = nil
    schedulerWakeAt = nil
    if type(wakeAt) == "number" and wakeAt > schedulerNow then
        schedulerNow = wakeAt
    end
    UpdateSchedulerNow()
    if not ElementFade.enabled or not WantsElementFade() then return end
    if not nextDueAt or schedulerNow < nextDueAt then
        RefreshNextDueAt()
        return
    end
    for owner, state in pairs(frameStates) do
        local dueAt = state.owner == owner and state.dueAt or nil
        if type(dueAt) == "number" and schedulerNow >= dueAt then
            state.dueAt = nil
            state.expired = true
            if settingsOpen ~= true
                and state.interacting ~= true
                and state.editActive ~= true
            then
                SetOwnerHidden(
                    owner,
                    true,
                    "element-fade-message-expired",
                    GetFadeDuration(owner)
                )
            end
        end
    end
    RefreshNextDueAt()
end

local function InstallNativeHook(name, callback)
    if nativeHooks[name] == true then return true end
    if type(_G[name]) ~= "function" or type(_G.hooksecurefunc) ~= "function" then
        return false
    end
    local ok = pcall(_G.hooksecurefunc, name, callback)
    if ok then nativeHooks[name] = true end
    return ok
end

local function EnsureNativeHooks()
    local fadeIn = InstallNativeHook("FCF_FadeInChatFrame", NativeFadeIn)
    local fadeOut = InstallNativeHook("FCF_FadeOutChatFrame", NativeFadeOut)
    return fadeIn and fadeOut
end

function ElementFade:IsFrameHidden(frame)
    local _, state = GetOwnerState(frame)
    if not state and IsStrictCombatLogFrame(frame) then
        _, state = GetOwnerState(_G.ChatFrame1)
    end
    return fadeActive and state ~= nil and state.hidden == true
end

function ElementFade:GetFrameVisibility(frame)
    local _, state = GetOwnerState(frame)
    if not state and IsStrictCombatLogFrame(frame) then
        _, state = GetOwnerState(_G.ChatFrame1)
    end
    if not fadeActive or not state then return 1 end
    return Clamp01(state.visibility)
end

function ElementFade:IsLinkedHidden()
    return linkedHidden == true
end

function ElementFade:IsStatsLinkedHidden()
    return statsLinkedHidden == true
end

function ElementFade:RestoreAll(reason)
    if Animation and type(Animation.StopOwner) == "function" then
        Animation:StopOwner(ElementFade, false)
    end
    activeAnimations = 0
    nextDueAt = nil
    CancelSchedulerTimer()
    local firstReason
    for frame, state in pairs(frameStates) do
        ResetOwnerState(state)
        local restored, restoreReason = ApplyMember(frame, state, 1, true)
        if not restored and not firstReason then firstReason = restoreReason end
    end
    linkedHidden = true
    statsLinkedHidden = true
    EmitLinkedVisibility()
    self.lastReason = firstReason or reason or "element-fade-restored"
    return firstReason == nil, firstReason
end

local function ShowAllOwners(reason, duration)
    local firstReason
    for owner, state in pairs(frameStates) do
        if state.owner == owner then
            local shown, detail = SetOwnerHidden(
                owner,
                false,
                reason or "element-fade-settings-open",
                duration or 0
            )
            if not shown and not firstReason then firstReason = detail end
        end
    end
    return firstReason == nil, firstReason
end

function ElementFade:OnSettingsVisibilityChanged(open)
    open = open == true
    if settingsOpen == open then return true end
    settingsOpen = open
    if not self.enabled or not WantsElementFade() then return true end
    if open then
        return ShowAllOwners(
            "element-fade-settings-open",
            GetFadeInDuration()
        )
    end
    local firstReason
    for owner, state in pairs(frameStates) do
        if state.owner == owner
            and state.expired == true
            and state.interacting ~= true
            and state.editActive ~= true
        then
            local hidden, detail = SetOwnerHidden(
                owner,
                true,
                "element-fade-settings-closed-expired",
                GetFadeDuration(owner)
            )
            if not hidden and not firstReason then firstReason = detail end
        end
    end
    RefreshNextDueAt()
    return firstReason == nil, firstReason
end

local function OnSettingsVisibilityChanged(_, open)
    ElementFade:OnSettingsVisibilityChanged(open)
end

local function AttachSettingsVisibility()
    settingsOpen = ReadSettingsOpen()
    local event = YUI.Event
    if not (event and type(event.On) == "function") then return false end
    if type(event.OffOwner) == "function" then event:OffOwner(settingsEventOwner) end
    return event:On(
        "YUI_SETTINGS_VISIBILITY_CHANGED",
        OnSettingsVisibilityChanged,
        settingsEventOwner,
        { moduleId = "ychat" }
    ) ~= nil
end

local function DetachSettingsVisibility()
    local event = YUI.Event
    if event and type(event.OffOwner) == "function" then
        event:OffOwner(settingsEventOwner)
    end
    settingsOpen = false
end

local function OnStatsFadeSyncRequest()
    EmitLinkedVisibility(0, true)
end

local function AttachIntegrationRuntime()
    local event = YUI.Event
    if not (event and type(event.On) == "function") then return false end
    if type(event.OffOwner) == "function" then event:OffOwner(integrationEventOwner) end
    return event:On(
        "YUI_CHAT_STATS_FADE_SYNC_REQUEST",
        OnStatsFadeSyncRequest,
        integrationEventOwner,
        { moduleId = "ychat" }
    ) ~= nil
end

local function DetachIntegrationRuntime()
    local event = YUI.Event
    if event and type(event.OffOwner) == "function" then
        event:OffOwner(integrationEventOwner)
    end
end

function ElementFade:RestartCountdown(reason)
    local restored, detail = self:RestoreAll(
        reason or "element-fade-scope-activated-restore"
    )
    UpdateSchedulerNow()
    for owner, state in pairs(frameStates) do
        if state.owner == owner then
            state.lastMessageAt = schedulerNow
            state.dueAt = schedulerNow + GetTimeVisible(owner)
            state.expired = false
        end
    end
    RefreshNextDueAt()
    self.lastReason = reason or "element-fade-scope-activated"
    return restored, detail
end

function ElementFade:SetEnabled(enabled, reason)
    enabled = enabled == true
    if not enabled then
        self.enabled = false
        scopeContextInitialized = false
        DetachSettingsVisibility()
        DetachIntegrationRuntime()
        DetachVisibilityWatches()
        RefreshConfigState()
        return self:RestoreAll(reason or "element-fade-disabled")
    end
    self.enabled = true
    AttachSettingsVisibility()
    AttachIntegrationRuntime()
    self:OnWindowsChanged(reason or "element-fade-enabled")
    return true
end

function ElementFade:OnFrameDiscovered(frame, valid)
    if valid ~= true then
        if self.enabled == true and fadeConfigured == true and IsStrictCombatLogFrame(frame) then
            RegisterFrame(frame)
            ReassignOwners()
            local owner, ownerState = GetOwnerState(frame)
            if owner and ownerState then
                local applied, reason = ApplyScope(
                    owner,
                    ownerState.visibility or 1,
                    true
                )
                if not applied then return FailScopeOpen(owner, reason) end
            end
            EmitLinkedVisibility()
            self.lastReason = "element-fade-combat-log-retained"
            return true
        end
        local state = frameStates[frame]
        if state then
            local owner = state.owner
            if owner == frame and Animation and type(Animation.StopTarget) == "function" then
                Animation:StopTarget(frame, "element-visibility", false)
            end
            ApplyMember(frame, state, 1, true)
            frameStates[frame] = nil
            if owner and owner ~= frame and frameStates[owner] then
                SetOwnerHidden(owner, false, "element-fade-member-invalid", 0)
            end
            RefreshNextDueAt()
        end
        EmitLinkedVisibility()
        return true
    end
    if self.enabled ~= true or fadeConfigured ~= true then return true end
    RegisterFrame(frame)
    return true
end

function ElementFade:OnWindowsChanged(reason)
    if not self.enabled then return true end
    local wasConfigured = fadeConfigured == true
    local wasActive = fadeActive == true
    local hadScopeContext = scopeContextInitialized == true
    local wasScopeEligible = scopeEligible == true
    RefreshConfigState(true)
    if not fadeConfigured then
        scopeContextInitialized = false
        if wasConfigured or wasActive or schedulerTimer or activeAnimations > 0 then
            return self:RestoreAll(reason or "element-fade-config-disabled")
        end
        self.lastReason = reason or "element-fade-config-disabled-idle"
        return true
    end
    local scopeActivated = hadScopeContext
        and wasScopeEligible ~= true
        and scopeEligible == true
    scopeContextInitialized = true
    if WantsElementFade() and not EnsureNativeHooks() then
        self.lastReason = "element-fade-native-hook-pending"
    end
    if type(Adapter.ForEachAppearanceTab) == "function" then
        Adapter:ForEachAppearanceTab(RegisterFrame)
    else
        Adapter:ForEachSupportedFrame(RegisterFrame)
    end
    RegisterStrictCombatLogFrame()
    ReassignOwners()
    if not WantsElementFade() then
        return self:RestoreAll(reason or "element-fade-config-disabled")
    end
    if not wasActive and scopeActivated then
        return self:RestartCountdown(reason or "element-fade-scope-activated")
    end
    RecalculateDueTimes()
    if settingsOpen == true then
        return ShowAllOwners(reason or "element-fade-settings-open", 0)
    end
    local appliedOwners = setmetatable({}, { __mode = "k" })
    for frame, state in pairs(frameStates) do
        local owner = state.owner
        if owner and not appliedOwners[owner] then
            appliedOwners[owner] = true
            local ownerState = frameStates[owner]
            local applied, applyReason = ApplyScope(
                owner,
                ownerState and ownerState.visibility or 1,
                true
            )
            if not applied then FailScopeOpen(owner, applyReason) end
        elseif not owner then
            ApplyMember(frame, state, 1, true)
        end
    end
    EmitLinkedVisibility()
    self.lastReason = reason or "element-fade-windows-changed"
    return true
end

function ElementFade:OnContextChanged(reason)
    if not self.enabled or not fadeConfigured then return true end
    local wasActive = fadeActive == true
    local wasStatsLinkActive = statsLinkActive == true
    local wasChatBarLinkActive = chatBarLinkActive == true
    RefreshVisibilityState()
    RefreshEffectiveState()
    scopeContextInitialized = true

    if wasActive and not fadeActive then
        return self:RestoreAll(reason or "element-fade-context-ineligible")
    end
    if not wasActive and fadeActive then
        return self:RestartCountdown(reason or "element-fade-context-eligible")
    end
    if wasStatsLinkActive ~= (statsLinkActive == true)
        or wasChatBarLinkActive ~= (chatBarLinkActive == true)
    then
        EmitLinkedVisibility()
    end
    self.lastReason = reason or "element-fade-context-unchanged"
    return true
end

function ElementFade:OnRestrictionStateChanged(state)
    local wasOpen = restrictionOpen == true
    RefreshConfigState(false, state)
    if not self.enabled then return true end
    if restrictionOpen ~= true then
        return self:RestoreAll("element-fade-restriction-not-open")
    end
    if wasOpen ~= true and WantsElementFade() then
        return self:RestartCountdown("element-fade-restriction-open")
    end
    return true
end

function ElementFade:OnMessage(frame)
    if not self.enabled or not fadeConfigured or restrictionOpen ~= true then
        return true
    end
    local owner, state = GetOwnerState(frame)
    if state then
        UpdateSchedulerNow()
        state.messageGeneration = (state.messageGeneration or 0) + 1
        state.inputHidePending = nil
        state.editStartedExpired = false
        state.editMessageGeneration = nil
        local fading = true
        if type(frame.GetFading) == "function" then
            local ok, value = pcall(frame.GetFading, frame)
            if ok and type(value) == "boolean" then fading = value end
        end
        state.expired = false
        if fading then
            local visible = GetTimeVisible(frame)
            state.lastMessageAt = schedulerNow
            state.dueAt = schedulerNow + visible
        else
            state.lastMessageAt = nil
            state.dueAt = nil
        end
        RefreshNextDueAt()
        return SetOwnerHidden(
            owner,
            false,
            "element-fade-message",
            GetFadeInDuration()
        )
    end
    return true
end

function ElementFade:RequestHide(frame, reason, force, onComplete)
    if not self.enabled or not WantsElementFade() then
        return false, "element-fade-disabled"
    end
    if settingsOpen == true then
        return false, "element-fade-settings-open"
    end
    frame = frame or _G.ChatFrame1
    local owner, state = GetOwnerState(frame)
    if not owner or not state then
        return false, "element-fade-owner-unavailable"
    end
    state.dueAt = nil
    state.expired = true
    state.hideCompletion = type(onComplete) == "function" and onComplete or nil
    state.inputHidePending = nil
    state.hoverActive = nil
    RefreshNextDueAt()
    if state.editActive == true and force ~= true then
        state.inputHidePending = true
        self.lastReason = reason or "element-fade-hide-pending"
        return true, "pending"
    end
    if force == true then state.editActive = false end
    state.interacting = false
    local applied, detail = SetOwnerHidden(
        owner,
        true,
        reason or "element-fade-hide-requested",
        GetFadeDuration(owner)
    )
    if not applied then state.hideCompletion = nil end
    return applied, detail
end

function ElementFade:GetRuntimeGauges(target)
    target = target or {}
    local hidden = 0
    local registered = 0
    local scopes = 0
    for frame, state in pairs(frameStates) do
        registered = registered + 1
        if state.owner == frame then
            scopes = scopes + 1
            if state.hidden == true then hidden = hidden + 1 end
        end
    end
    target.elementFadeEnabled = WantsElementFade()
    target.elementFadeScope = fadeScope
    target.elementFadeScopeEligible = scopeEligible == true
    target.elementFadeInstanceKnown = instanceStateKnown == true
    target.elementFadeInInstance = inInstance == true
    target.elementFadeInstanceType = instanceType
    target.elementFadeGroupKnown = groupStateKnown == true
    target.elementFadeInGroup = inGroup == true
    target.elementFadeSettingsOpen = settingsOpen == true
    target.elementFadeRestrictionOpen = restrictionOpen == true
    target.elementFadeRegisteredFrames = registered
    target.elementFadeManagedScopes = scopes
    target.elementFadeHiddenFrames = hidden
    target.elementFadeLinkedHidden = linkedHidden == true
    target.elementFadeStatsMode = fadeStatsMode
    target.elementFadeStatsConditionMatched = statsConditionMatched == true
    target.elementFadeStatsLinkedHidden = statsLinkedHidden == true
    target.elementFadeActiveDrivers = activeAnimations > 0 and 1 or 0
    target.elementFadeActiveTimers = schedulerTimer and 1 or 0
    target.elementFadeNextDueScheduled = nextDueAt and 1 or 0
    return target
end
