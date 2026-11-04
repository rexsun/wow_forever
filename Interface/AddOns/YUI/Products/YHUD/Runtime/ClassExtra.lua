local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end
local Extra = { records = {}, previews = {} }
YHUD.ClassExtra = Extra

local function Number(value, fallback, minimum, maximum)
    if type(issecretvalue) == "function" and issecretvalue(value) then return fallback end
    if type(value) ~= "number" or value ~= value or value < minimum or value > maximum then return fallback end
    return value
end
function Extra:Preset(entry)
    if not (YUI.IsRetail and type(entry) == "table" and entry.sourceType == "class-extra-monitor") then return end
    for _, preset in ipairs(YHUD.CLASS_EXTRA_PRESETS or {}) do
        if entry.sourceKey == preset.sourceKey and entry.presetId == preset.presetId then return preset end
    end
end
function Extra:Settings(entry)
    local config = type(entry) == "table" and type(entry.classExtra) == "table" and entry.classExtra or {}
    local ready = config.readyVisibility
    if ready ~= "combat" and ready ~= "instance" then ready = "group" end
    return Number(config.alertSecond, 38, 1, 90), Number(config.endedHideDelay, 3, 0, 30), config.showIconProgress == true, ready
end
function Extra:SettingsLabel(entry)
    local preset = self:Preset(entry)
    return preset and YHUD:T(preset.settingsLabelKey) or nil
end
function Extra:Description(entry)
    local preset = self:Preset(entry)
    if not preset then return nil end
    local text = YHUD:T(preset.logicKey)
    if preset.presetId == "devourer-transform" then
        local alert, delay = self:Settings(entry)
        text = string.format(text, alert, delay)
    end
    return text
end
function Extra:Resolve(entry)
    local preset = self:Preset(entry)
    local common = YUI.Monitor and YUI.Monitor.CommonSources
    if not (preset and common and common.DescribeClassExtra) then return end
    return common:DescribeClassExtra(preset.presetId)
end
local function Replay(record)
    local sources = YHUD.Sources
    local handle = sources and sources.handles[record.key]
    if handle and handle.active then sources:OnSourceState(handle.source.state, record.key, nil, true) end
end
local function ReleaseReadyVisibility(record)
    if record.visibilityHandle then
        YUI.Visibility:Release(record.visibilityHandle)
        record.visibilityHandle = nil
    end
end
local function OnReadyVisibility(record, visible)
    record.readyAllowed = visible == true
    if record.state.extraActive ~= true then Replay(record) end
end
local function SyncReadyVisibility(record, preset)
    local mode = preset.presetId == "brewmaster-elixir" and record.readyVisibility or "group"
    if record.visibilityMode == mode and (mode == "group" or record.visibilityHandle) then return end
    ReleaseReadyVisibility(record)
    record.visibilityMode, record.readyAllowed = mode, mode == "group"
    if mode ~= "group" and YUI.Visibility then
        record.visibilityHandle = YUI.Visibility:Watch(record,
            mode == "combat" and { combat = "in" } or { instance = "inside" }, OnReadyVisibility)
    end
end
function Extra:Configure(profile, desired)
    for key, record in pairs(self.records) do
        if not desired[key] or desired[key].typeId ~= "class-extra-monitor" then
            YUI.Monitor:CancelTasks(record)
            ReleaseReadyVisibility(record)
            self.records[key] = nil
        end
    end
    for _, entry in pairs(profile.entries or {}) do
        local preset = self:Preset(entry)
        if desired[entry.sourceKey] and preset then
            local record = self.records[entry.sourceKey] or { key = entry.sourceKey, state = {} }
            record.alertSecond, record.endedHideDelay, record.showIconProgress, record.readyVisibility = self:Settings(entry)
            self.records[entry.sourceKey] = record
            SyncReadyVisibility(record, preset)
        end
    end
end
function Extra:Project(raw, key)
    local record = self.records[key]
    if not record then return raw end
    local state, now = record.state, GetTime()
    YUI.Monitor:CancelTasks(record)
    local transform = raw.sourceKind == "devourer-transform"
    local retained = transform and raw.hasLast and raw.endedAt and now < raw.endedAt + record.endedHideDelay
    state.sourceKind, state.spellID, state.icon = raw.sourceKind, raw.spellID, raw.icon
    state.startTime = raw.startTime
    state.duration = transform and record.alertSecond or raw.duration
    state.displayCount = transform and raw.displayCount or nil
    state.isEnabled, state.resolved, state.secret = raw.isEnabled, raw.resolved, false
    state.available = transform and (raw.active or retained == true) or raw.available
    state.extraActive, state.elapsedValue, state.session = raw.active, raw.elapsed, raw.session
    state.showIconProgress = record.showIconProgress
    -- Presentation gating never changes readiness or the state shared with sound/Nova.
    state.classExtraVisible = transform or raw.active == true or record.readyAllowed == true
    state.thresholdReached = transform and raw.active and now >= raw.startTime + record.alertSecond
    state.classExtra = true
    -- State changes and deadline edges are infrequent; clocks are rendered by
    -- the existing monitor driver, never by polling the game aura/cooldown API.
    state.extraRevision = (state.extraRevision or 0) + 1
    if transform and raw.active and not state.thresholdReached then
        YUI.Monitor:ScheduleTask(record, "threshold", raw.startTime + record.alertSecond, Replay)
    elseif retained then
        YUI.Monitor:ScheduleTask(record, "retained", raw.endedAt + record.endedHideDelay, Replay)
    end
    return state
end
function Extra:Clear()
    for key, record in pairs(self.records) do
        YUI.Monitor:CancelTasks(record)
        ReleaseReadyVisibility(record)
        self.records[key] = nil
    end
    for slot in pairs(self.clocks) do self:ClearClock(slot) end
    for slot in pairs(self.previews) do self:ClearDesignPreview(slot) end
end

local function SetElapsedProgress(slot, elapsed, duration, force)
    if not slot.SetValue then return end
    local value = duration and duration > 0 and math.min(1, math.max(0, elapsed / duration)) or 0
    if force or slot.value ~= value then slot:SetValue(value, true) end
end
local function PrepareIconProgress(slot, state, runtime)
    local enabled = runtime and runtime.view == "icon" and state.showIconProgress == true
    slot._yhudExtraIconProgressEnabled = enabled == true
    local progress = slot._yhudExtraIconProgress
    if not enabled then
        if progress then progress:Hide() end
        return
    end
    local width = runtime.itemWidth or runtime.iconSize or 42
    if not progress then
        progress = YUI.GUI2.Data:CreateProgressBar(slot, {
            width = width, height = 5, value = 0, animate = false, motion = false,
        })
        slot._yhudExtraIconProgress = progress
    end
    progress:ClearAllPoints()
    progress:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", 0, 0)
    progress:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 0, 0)
    progress:SetBarSize(width, 5)
end
local function RenderIconProgress(slot, state, elapsed, duration, force)
    local progress = slot._yhudExtraIconProgress
    if not progress then return end
    local shown = slot._yhudExtraIconProgressEnabled and state.available == true and elapsed < duration
    if shown then SetElapsedProgress(progress, elapsed, duration, force) end
    if progress:IsShown() ~= shown then progress:SetShown(shown) end
end
local function RenderClock(slot, force)
    local state, runtime = slot._yhudExtraClockState, slot._yhudExtraClockRuntime
    if not state then return end
    local elapsed = state.extraActive and math.max(0, GetTime() - state.startTime) or state.elapsedValue or 0
    local text = runtime and runtime.cooldownText == false and "" or string.format("%.1f", elapsed)
    if runtime and runtime.view == "bar" then
        SetElapsedProgress(slot, elapsed, state.duration, force)
    end
    RenderIconProgress(slot, state, elapsed, state.duration, force)
    if slot._yhudExtraClockValue ~= text and slot._yhudExtraClockText then
        slot._yhudExtraClockText:SetText(text)
    end
    slot._yhudExtraClockValue = text
end
Extra.clocks = {}
local function PreviewVisible(record)
    return record.view.designMode == true
        and record.runtime.enabled ~= false
        and record.runtime.frame:IsShown() and record.slot:IsShown()
end
local function NoVisual() end
function Extra:RefreshClockDriver()
    local enabled = next(self.clocks) ~= nil
    if not enabled then
        for _, record in pairs(self.previews) do
            if PreviewVisible(record) then enabled = true; break end
        end
    end
    if enabled == self.clockDriverEnabled then return end
    self.clockDriverEnabled = enabled
    if enabled and not self.clockDriver then
        self.clockDriver = YUI.Monitor:Register({
            id = "yhud.class-extra-clocks", owner = self,
            activation = { expression = function() return Extra.clockDriverEnabled == true end, triggers = {} },
            update = { interval = 0.05, activeOnly = true },
            appearance = { presenter = {
                ensure = NoVisual, apply = NoVisual, update = NoVisual,
                show = NoVisual, hide = NoVisual, destroy = NoVisual,
            } },
            conditions = { onUpdate = function()
                for slot in pairs(Extra.clocks) do RenderClock(slot) end
                Extra:UpdateDesignPreviews()
            end },
        })
    end
    if self.clockDriver then self.clockDriver:SetEnabled(enabled) end
end
function Extra:ApplyClock(view, slot, state, runtime)
    if state.sourceKind ~= "devourer-transform" then return false end
    if slot.ClearDuration then slot:ClearDuration()
    elseif slot.SetCooldown then slot:SetCooldown(0, 0) end
    slot._yhudCooldownRefreshArmed = false
    local isBar = runtime and runtime.view == "bar"
    if not slot._yhudExtraClockText then
        slot._yhudExtraClockText = YUI.GUI2:CreateText(
            isBar and slot.durationOverlay or slot, "", "font.size.md", "color.text.primary", "CENTER")
        slot._yhudExtraClockTextState = { preserveVisibility = true }
        slot._yhudExtraClockAnchorState = {}
    end
    local label = slot._yhudExtraClockText
    local style = not isBar and runtime and runtime.iconStyle and runtime.iconStyle.cooldownText
    style = style or {
        enabled = not runtime or runtime.cooldownText ~= false,
        font = runtime and runtime.cooldownTextFont,
        size = runtime and runtime.cooldownTextSize,
        outline = runtime and runtime.cooldownTextOutline,
        position = runtime and runtime.cooldownTextPosition,
        anchor = runtime and runtime.cooldownTextAnchor,
        offsetX = runtime and runtime.cooldownTextOffsetX,
        offsetY = runtime and runtime.cooldownTextOffsetY,
        color = runtime and runtime.cooldownTextColor,
    }
    local textState = slot._yhudExtraClockTextState
    textState.preserveAnchors = isBar == true
    YUI.GUI2:ApplyTextStyle(label, style, textState)
    if isBar and slot.PositionDurationTextAnchor then
        slot:PositionDurationTextAnchor(label, style, "time", slot._yhudExtraClockAnchorState)
    end
    -- This binding owns visibility; ClearClock hides the region outside GUI2's
    -- style cache, so every reuse must restore the configured visibility.
    label:SetShown(style.enabled ~= false and (not runtime or runtime.cooldownText ~= false))
    slot._yhudExtraClockState, slot._yhudExtraClockRuntime = state, runtime
    PrepareIconProgress(slot, state, runtime)
    RenderClock(slot, true)
    self.clocks[slot] = state.extraActive and state.available and state.resolved or nil
    self:RefreshClockDriver()
    return true
end
function Extra:ClearClock(slot)
    self.clocks[slot] = nil
    slot._yhudExtraClockState, slot._yhudExtraClockRuntime, slot._yhudExtraClockValue = nil, nil, nil
    if slot._yhudExtraClockText then slot._yhudExtraClockText:Hide() end
    if slot._yhudExtraIconProgress then slot._yhudExtraIconProgress:Hide() end
    slot._yhudExtraIconProgressEnabled = nil
    self:RefreshClockDriver()
end

-- Isolated designer samples: no source acquisition, model writes or sound events.
-- The existing elapsed-clock driver services visible samples as well as live clocks.
function Extra:RenderDesignPreview(record, now, force)
    local state, slot, runtime = record.state, record.slot, record.runtime
    local transform = state.sourceKind == "devourer-transform"
    local lead = math.min(3, record.alert)
    local activeSeconds = transform and lead + 2 or 6
    local cycleSeconds = transform and activeSeconds + record.delay + 1 or 8
    local cycle = math.floor(math.max(0, now - record.startedAt) / cycleSeconds)
    local cycleStart = record.startedAt + cycle * cycleSeconds
    local elapsed = math.max(0, now - cycleStart)
    local phase
    if transform then
        state.extraActive = elapsed < activeSeconds
        state.elapsedValue = record.alert - lead + math.min(elapsed, activeSeconds)
        state.startTime, state.duration = cycleStart - (record.alert - lead), record.alert
        state.thresholdReached = state.extraActive and elapsed >= lead
        state.displayCount = elapsed < lead * 0.5 and 2 or 3
        phase = elapsed < lead and 1 or (state.extraActive and 2
            or (elapsed < activeSeconds + record.delay and 3 or 4))
        state.available = phase ~= 4
        record.timeText = string.format("%.1f", state.elapsedValue)
        if runtime.view == "bar" and phase ~= 4 then
            SetElapsedProgress(slot, state.elapsedValue, record.alert, force)
        end
        RenderIconProgress(slot, state, state.elapsedValue, record.alert, force)
    else
        state.extraActive = elapsed < activeSeconds
        state.startTime = state.extraActive and cycleStart - 9 or 0
        state.duration = state.extraActive and 15 or 0
        state.available = true
        phase = state.extraActive and 1 or 2
        record.timeText = state.extraActive and string.format("%.1f", activeSeconds - elapsed) or ""
    end
    local changed = force or record.phase ~= phase or record.cycle ~= cycle
    if changed then
        record.phase, record.cycle = phase, cycle
        if not transform then
            if state.extraActive then
                if runtime.view == "bar" and slot.SetDurationFromTimes then
                    slot:SetDurationFromTimes(state.startTime, state.duration, 1, slot.gui2DurationReverse == true)
                elseif slot.SetCooldown then
                    slot:SetCooldown(state.startTime, state.duration, 1)
                end
            elseif slot.ClearDuration then slot:ClearDuration()
            elseif slot.SetCooldown then slot:SetCooldown(0, 0) end
        end
        slot:SetAlpha(phase == 4 and 0.25 or record.alpha)
        record.view:ApplyMonitorGlow(slot, record.monitor, state)
        record.view:ApplyIconDesaturation(slot, state)
    end
    local timeText = slot._yhudDesignCooldownText
    if timeText and record.lastTimeText ~= record.timeText then
        timeText:SetText(record.timeText)
        record.lastTimeText = record.timeText
    end
    local countText = slot._yhudDesignCountText
    if countText and record.lastCount ~= state.displayCount then
        countText:SetText(state.displayCount and tostring(state.displayCount) or "")
        record.lastCount = state.displayCount
    end
end

function Extra:UpdateDesignPreviews()
    if next(self.previews) == nil then return end
    local now = GetTime()
    for _, record in pairs(self.previews) do
        if PreviewVisible(record) then self:RenderDesignPreview(record, now) end
    end
    self:RefreshClockDriver()
end

function Extra:StartDesignPreview(view, slot, entry, monitor, runtime)
    local preset = self:Preset(entry)
    if not (preset and view.designMode and slot._yhudDesignProjection
        and runtime and (runtime.view == "icon" or runtime.view == "bar")) then return false end
    local alert, delay, showIconProgress = self:Settings(entry)
    -- Preserve play position across appearance-only projection rebuilds. Parameter
    -- edits restart near the new threshold; leaving the designer drops this cache.
    local timelines = view.classExtraPreviewTimes or {}
    view.classExtraPreviewTimes = timelines
    local timeline = timelines[monitor.id]
    if not timeline or timeline.sourceKey ~= entry.sourceKey
        or timeline.alert ~= alert or timeline.delay ~= delay then
        timeline = { sourceKey = entry.sourceKey, alert = alert, delay = delay, startedAt = GetTime() }
        timelines[monitor.id] = timeline
    end
    local record = {
        slot = slot, view = view, runtime = runtime, monitor = monitor,
        startedAt = timeline.startedAt, alert = alert, delay = delay,
        alpha = slot:GetAlpha(),
        state = { sourceKind = preset.presetId, classExtra = true, classExtraPreview = true, showIconProgress = showIconProgress,
            resolved = true, secret = false, available = true, isEnabled = true },
    }
    PrepareIconProgress(slot, record.state, runtime)
    self.previews[slot] = record
    self:RenderDesignPreview(record, GetTime(), true)
    self:RefreshClockDriver()
    return true
end

function Extra:ClearDesignPreview(slot)
    local record = self.previews[slot]
    if not record then return end
    self.previews[slot] = nil
    if slot._yhudExtraIconProgress then slot._yhudExtraIconProgress:Hide() end
    slot._yhudExtraIconProgressEnabled = nil
    slot:SetAlpha(record.alpha)
    if slot.ClearDuration then slot:ClearDuration()
    elseif slot.SetCooldown then slot:SetCooldown(0, 0) end
    self:RefreshClockDriver()
end

function Extra:HideSettings(inspector)
    for _, row in ipairs(inspector.classExtraSettings or {}) do row.label:Hide(); row.control:Hide() end
    if inspector.classExtraDescription then inspector.classExtraDescription:Hide() end
    if inspector.classExtraParameters then inspector.classExtraParameters:Hide() end
    if inspector.classExtraProgressLabel then inspector.classExtraProgressLabel:Hide(); inspector.classExtraProgressSwitch:Hide() end
    if inspector.classExtraReadyLabel then inspector.classExtraReadyLabel:Hide(); inspector.classExtraReadyDropdown:Hide() end
    inspector.classExtraMonitorId = nil
end
