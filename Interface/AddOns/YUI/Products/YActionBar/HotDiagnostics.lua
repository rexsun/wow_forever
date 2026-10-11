local YUI = _G.YUI
if not YUI or not YUI.YActionBar then return end

local YAB = YUI.YActionBar
local Diagnostics = {}
YAB.HotDiagnostics = Diagnostics

local DEFAULT_SAMPLE_EVERY = 32
local PROC_CAPTURE_LIMIT = 64
local PROC_CAPTURE_AUTO_REPORT_LIMIT = 14
local PROC_CAPTURE_TIMELINE_LIMIT = 16
local PROC_CAPTURE_RESULT_PRIORITY = {
    GLOW_FRAME_MISSING = 1,
    VISUAL_STALE = 2,
    USABLE_STALE = 3,
    IDENTITY_MISS = 4,
}
local DOMAIN_NAMES = {
    "cooldown",
    "charge",
    "uses",
    "state",
    "usable",
    "range",
    "proc",
    "identity",
    "refresh",
}

local function ClearMap(map)
    for key in pairs(map or {}) do map[key] = nil end
end

local function CopyMap(source)
    local target = {}
    for key, value in pairs(source or {}) do target[key] = value end
    return target
end

local function IncrementMap(map, key, amount)
    if not (map and key ~= nil) then return end
    map[key] = (map[key] or 0) + (amount or 1)
end

local function Now()
    local getTime = _G.GetTime
    if type(getTime) ~= "function" then return 0 end
    local ok, value = pcall(getTime)
    return ok and type(value) == "number" and value or 0
end

local function InCombat()
    local adapter = YAB.Adapter
    if adapter and type(adapter.InCombat) == "function" then
        local ok, value = pcall(adapter.InCombat, adapter)
        if ok then return value == true end
    end
    local reader = _G.UnitAffectingCombat
    if type(reader) == "function" then
        local ok, value = pcall(reader, "player")
        if ok and value == true then return true end
    end
    reader = _G.InCombatLockdown
    if type(reader) == "function" then
        local ok, value = pcall(reader)
        if ok then return value == true end
    end
    return false
end

local function NewProcCapture()
    local entries = {}
    for index = 1, PROC_CAPTURE_LIMIT do entries[index] = {} end
    local timeline = {}
    for index = 1, PROC_CAPTURE_TIMELINE_LIMIT do timeline[index] = {} end
    return {
        state = "idle",
        entries = entries,
        head = 1,
        count = 0,
        dropped = 0,
        startedAt = 0,
        result = nil,
        resultPriority = 0,
        triggerEvent = nil,
        finishReason = nil,
        combatSeen = false,
        pendingReport = false,
        focusKey = nil,
        focusSlot = nil,
        focusEventSpellID = nil,
        focusLocked = false,
        showBefore = {},
        showAfter = {},
        timeline = timeline,
        timelineCount = 0,
        timelineDropped = 0,
        lastTimelineSignature = nil,
    }
end

local function ClearProcCaptureEntry(entry)
    entry.elapsed = nil
    entry.event = nil
    entry.phase = nil
    entry.detail = nil
    entry.signature = nil
    entry.protected = nil
end

local function WriteProcCaptureEntry(entry, capture, event, phase, detail, signature, protected)
    entry.elapsed = math.max(0, Now() - (capture.startedAt or 0))
    entry.event = tostring(event or "unknown")
    entry.phase = tostring(phase or "snapshot")
    entry.detail = tostring(detail or "")
    entry.signature = signature
    entry.protected = protected == true
end

local function ClearProcCaptureFocusSummary(capture)
    ClearProcCaptureEntry(capture.showBefore)
    ClearProcCaptureEntry(capture.showAfter)
    capture.timelineCount = 0
    capture.timelineDropped = 0
    capture.lastTimelineSignature = nil
    for index = 1, PROC_CAPTURE_TIMELINE_LIMIT do
        ClearProcCaptureEntry(capture.timeline[index])
    end
end

local function ClearProcCaptureEntries(capture)
    capture.head = 1
    capture.count = 0
    capture.dropped = 0
    for index = 1, PROC_CAPTURE_LIMIT do
        ClearProcCaptureEntry(capture.entries[index])
    end
    capture.focusKey = nil
    capture.focusSlot = nil
    capture.focusEventSpellID = nil
    capture.focusLocked = false
    ClearProcCaptureFocusSummary(capture)
end

local function PrintLine(line)
    if type(YUI.Print) == "function" then
        YUI:Print(line)
    elseif type(_G.print) == "function" then
        _G.print(line)
    end
end

local function NewDomain()
    return {
        events = 0,
        samples = 0,
        sampleMs = 0,
        maxMs = 0,
        maxAtMS = nil,
        candidates = 0,
        buttons = 0,
        changes = 0,
        backendReads = 0,
        writes = 0,
        fallbacks = 0,
        frames = 0,
        sameFrameRepeats = 0,
        eligibleButtons = 0,
        ineligibleButtons = 0,
        activeButtons = 0,
        queued = 0,
        activeMainReads = 0,
        activeMainWrites = 0,
        repeatGCDCandidates = 0,
        chargeInfoReads = 0,
        skippedGCDWrites = 0,
        doneResets = 0,
    }
end

local function ResetDomain(domain)
    domain.events = 0
    domain.samples = 0
    domain.sampleMs = 0
    domain.maxMs = 0
    domain.maxAtMS = nil
    domain.candidates = 0
    domain.buttons = 0
    domain.changes = 0
    domain.backendReads = 0
    domain.writes = 0
    domain.fallbacks = 0
    domain.frames = 0
    domain.sameFrameRepeats = 0
    domain.eligibleButtons = 0
    domain.ineligibleButtons = 0
    domain.activeButtons = 0
    domain.queued = 0
    domain.activeMainReads = 0
    domain.activeMainWrites = 0
    domain.repeatGCDCandidates = 0
    domain.chargeInfoReads = 0
    domain.skippedGCDWrites = 0
    domain.doneResets = 0
    domain.lastFrameStamp = nil
    domain.pendingQueued = false
    domain.pendingFirstReason = nil
    domain.pendingLastReason = nil
    domain.pendingFirstMode = nil
    domain.pendingLastMode = nil
    domain.pendingFirstSource = nil
    domain.pendingLastSource = nil
    domain.pendingMixed = false
    ClearMap(domain.queueReasons)
    ClearMap(domain.queueModes)
    ClearMap(domain.queueSources)
    ClearMap(domain.passReasons)
    ClearMap(domain.passModes)
    ClearMap(domain.passSources)
end

Diagnostics.enabled = false
Diagnostics.sampleEvery = DEFAULT_SAMPLE_EVERY
Diagnostics.gcdMode = "production"
Diagnostics.mode = "detail"
Diagnostics.detailEnabled = false
Diagnostics.domains = {}
Diagnostics.procCapture = Diagnostics.procCapture or NewProcCapture()
Diagnostics.combat = {
    flushes = 0,
    secureApplied = 0,
    structuralApplied = 0,
    externalSpecialQueued = 0,
    fullRefreshQueued = 0,
    driverReasons = {},
    structuralBars = {},
    externalSpecialBars = {},
}
for index = 1, #DOMAIN_NAMES do
    Diagnostics.domains[DOMAIN_NAMES[index]] = NewDomain()
end

function Diagnostics:IsProcCaptureActive()
    local state = self.procCapture and self.procCapture.state
    return state == "armed" or state == "triggered"
end

function Diagnostics:HasProcCaptureFocus()
    return self.procCapture and self.procCapture.focusKey ~= nil
end

function Diagnostics:CanReplaceProcCaptureFocus()
    return self:IsProcCaptureActive()
        and self.procCapture and self.procCapture.focusLocked ~= true
end

function Diagnostics:IsProcCaptureFocus(buttonKey)
    return buttonKey ~= nil and self.procCapture and self.procCapture.focusKey == buttonKey
end

function Diagnostics:SetProcCaptureFocus(buttonKey, slot, eventSpellID, phase)
    if not self:IsProcCaptureActive() or buttonKey == nil then return false end
    local capture = self.procCapture
    local normalizedKey = tostring(buttonKey)
    if capture.focusLocked == true then return capture.focusKey == normalizedKey end
    local sameCandidate = capture.focusKey == normalizedKey
        and capture.focusSlot == slot
        and capture.focusEventSpellID == eventSpellID
    local continuingAfter = phase == "after" and sameCandidate
        and capture.showBefore.event ~= nil and capture.showAfter.event == nil
    if not continuingAfter then
        ClearProcCaptureFocusSummary(capture)
    end
    capture.focusKey = normalizedKey
    capture.focusSlot = slot
    capture.focusEventSpellID = eventSpellID
    return true
end

function Diagnostics:StartProcCapture()
    local capture = self.procCapture
    if YAB.BarManager and YAB.BarManager.CancelProcCaptureFreezeTimer then
        YAB.BarManager:CancelProcCaptureFreezeTimer()
    end
    ClearProcCaptureEntries(capture)
    capture.state = "armed"
    capture.startedAt = Now()
    capture.result = nil
    capture.resultPriority = 0
    capture.triggerEvent = nil
    capture.finishReason = nil
    capture.combatSeen = InCombat()
    capture.pendingReport = false
    if YAB.BarManager and YAB.BarManager.PrimeProcCaptureOverlayBaseline then
        YAB.BarManager:PrimeProcCaptureOverlayBaseline()
    end
    return true
end

function Diagnostics:CancelProcCapture(reason)
    local capture = self.procCapture
    if YAB.BarManager and YAB.BarManager.CancelProcCaptureFreezeTimer then
        YAB.BarManager:CancelProcCaptureFreezeTimer()
    end
    ClearProcCaptureEntries(capture)
    capture.state = "idle"
    capture.startedAt = 0
    capture.result = nil
    capture.resultPriority = 0
    capture.triggerEvent = nil
    capture.finishReason = reason or "cancelled"
    capture.combatSeen = false
    capture.pendingReport = false
    if YAB.BarManager and YAB.BarManager.ClearProcCaptureOverlayBaseline then
        YAB.BarManager:ClearProcCaptureOverlayBaseline()
    end
    return true
end

function Diagnostics:NoteProcCaptureCombatStarted()
    if self:IsProcCaptureActive() then
        self.procCapture.combatSeen = true
    end
end

function Diagnostics:TriggerProcCapture(result, event)
    if not self:IsProcCaptureActive() then return false end
    local capture = self.procCapture
    local priority = PROC_CAPTURE_RESULT_PRIORITY[result] or 0
    if priority > (capture.resultPriority or 0) then
        capture.result = result
        capture.resultPriority = priority
        capture.triggerEvent = event or capture.triggerEvent
    end
    capture.focusLocked = capture.focusKey ~= nil
    if capture.state == "triggered" then return true end
    capture.state = "triggered"
    if YAB.BarManager and YAB.BarManager.ScheduleProcCaptureFreeze then
        YAB.BarManager:ScheduleProcCaptureFreeze()
    else
        self:FreezeProcCapture("scheduler-unavailable")
    end
    return true
end

function Diagnostics:RecordProcCapture(event, phase, detail, result)
    if not self:IsProcCaptureActive() then return false end
    local capture = self.procCapture
    local entryIndex
    if capture.count < PROC_CAPTURE_LIMIT then
        entryIndex = ((capture.head + capture.count - 1) % PROC_CAPTURE_LIMIT) + 1
        capture.count = capture.count + 1
    else
        entryIndex = capture.head
        capture.head = (capture.head % PROC_CAPTURE_LIMIT) + 1
        capture.dropped = capture.dropped + 1
    end
    local entry = capture.entries[entryIndex]
    WriteProcCaptureEntry(entry, capture, event, phase, detail)
    if result then self:TriggerProcCapture(result, event) end
    return true
end

function Diagnostics:RecordProcCaptureKey(kind, event, phase, detail, signature, force)
    if not self:IsProcCaptureActive() then return false end
    local capture = self.procCapture
    if kind == "showBefore" or kind == "showAfter" then
        local entry = capture[kind]
        if entry.event ~= nil then return false end
        WriteProcCaptureEntry(entry, capture, event, phase, detail, signature, true)
        return true
    end
    if kind ~= "timeline" then return false end
    if force ~= true and signature ~= nil and capture.lastTimelineSignature == signature then
        return false
    end

    local entryIndex
    if capture.timelineCount < PROC_CAPTURE_TIMELINE_LIMIT then
        capture.timelineCount = capture.timelineCount + 1
        entryIndex = capture.timelineCount
    else
        local evictIndex = 1
        while evictIndex <= PROC_CAPTURE_TIMELINE_LIMIT
            and capture.timeline[evictIndex].protected == true do
            evictIndex = evictIndex + 1
        end
        if evictIndex > PROC_CAPTURE_TIMELINE_LIMIT then evictIndex = 1 end
        for index = evictIndex, PROC_CAPTURE_TIMELINE_LIMIT - 1 do
            local source = capture.timeline[index + 1]
            local target = capture.timeline[index]
            target.elapsed = source.elapsed
            target.event = source.event
            target.phase = source.phase
            target.detail = source.detail
            target.signature = source.signature
            target.protected = source.protected
        end
        entryIndex = PROC_CAPTURE_TIMELINE_LIMIT
        capture.timelineDropped = capture.timelineDropped + 1
    end
    WriteProcCaptureEntry(capture.timeline[entryIndex], capture, event, phase, detail, signature, force)
    capture.lastTimelineSignature = signature
    return true
end

function Diagnostics:FreezeProcCapture(reason)
    if not self:IsProcCaptureActive() then return false end
    local capture = self.procCapture
    if YAB.BarManager and YAB.BarManager.CancelProcCaptureFreezeTimer then
        YAB.BarManager:CancelProcCaptureFreezeTimer()
    end
    capture.state = "frozen"
    capture.result = capture.result or "NO_ANOMALY"
    capture.finishReason = reason or "complete"
    capture.pendingReport = true
    if YAB.BarManager and YAB.BarManager.ClearProcCaptureOverlayBaseline then
        YAB.BarManager:ClearProcCaptureOverlayBaseline()
    end
    if not InCombat() then
        self:PrintProcCaptureSummary()
    end
    return true
end

function Diagnostics:OnProcCaptureCombatEnded()
    local capture = self.procCapture
    if self:IsProcCaptureActive() and capture.combatSeen == true then
        self:FreezeProcCapture(capture.result and "combat-ended-after-trigger" or "combat-ended")
    end
    if capture.state == "frozen" and capture.pendingReport == true then
        self:PrintProcCaptureSummary()
    end
end

local function FormatProcCaptureEntry(prefix, entry)
    return string.format(
        "YActionBar proc %s +%.3fs %s/%s %s",
        prefix,
        tonumber(entry.elapsed) or 0,
        tostring(entry.event or "unknown"),
        tostring(entry.phase or "snapshot"),
        tostring(entry.detail or "")
    )
end

function Diagnostics:GetProcCaptureSummaryLines()
    local capture = self.procCapture
    if capture.focusKey == nil then
        return self:GetProcCaptureLines(PROC_CAPTURE_AUTO_REPORT_LIMIT)
    end
    local lines = {
        string.format(
            "YActionBar proc capture: result=%s state=%s trigger=%s finish=%s focus=%s slot=%s focusSpell=%s entries=%d dropped=%d summary=%d summaryDropped=%d",
            tostring(capture.result or "PENDING"),
            tostring(capture.state),
            tostring(capture.triggerEvent or "none"),
            tostring(capture.finishReason or "none"),
            tostring(capture.focusKey),
            tostring(capture.focusSlot or "none"),
            tostring(capture.focusEventSpellID or "none"),
            capture.count,
            capture.dropped,
            capture.timelineCount,
            capture.timelineDropped
        ),
    }
    if capture.showBefore.event ~= nil then
        lines[#lines + 1] = FormatProcCaptureEntry("summary SHOW", capture.showBefore)
    end
    if capture.showAfter.event ~= nil then
        lines[#lines + 1] = FormatProcCaptureEntry("summary SHOW", capture.showAfter)
    end
    for index = 1, capture.timelineCount do
        lines[#lines + 1] = FormatProcCaptureEntry("summary", capture.timeline[index])
    end
    return lines
end

function Diagnostics:GetProcCaptureLines(limit)
    local capture = self.procCapture
    limit = tonumber(limit)
    if not limit or limit < 1 then limit = capture.count end
    limit = math.min(math.floor(limit), capture.count)
    local lines = {
        string.format(
            "YActionBar proc capture: result=%s state=%s trigger=%s finish=%s entries=%d dropped=%d",
            tostring(capture.result or "PENDING"),
            tostring(capture.state),
            tostring(capture.triggerEvent or "none"),
            tostring(capture.finishReason or "none"),
            capture.count,
            capture.dropped
        ),
    }
    local skip = capture.count - limit
    for offset = skip, capture.count - 1 do
        local index = ((capture.head + offset - 1) % PROC_CAPTURE_LIMIT) + 1
        local entry = capture.entries[index]
        lines[#lines + 1] = string.format(
            "YActionBar proc +%.3fs %s/%s %s",
            tonumber(entry.elapsed) or 0,
            tostring(entry.event or "unknown"),
            tostring(entry.phase or "snapshot"),
            tostring(entry.detail or "")
        )
    end
    return lines
end

function Diagnostics:PrintProcCaptureReport(limit)
    local lines = self:GetProcCaptureLines(limit)
    for index = 1, #lines do PrintLine(lines[index]) end
    self.procCapture.pendingReport = false
    return true
end

function Diagnostics:PrintProcCaptureSummary()
    local lines = self:GetProcCaptureSummaryLines()
    for index = 1, #lines do PrintLine(lines[index]) end
    self.procCapture.pendingReport = false
    return true
end

local refreshDomain = Diagnostics.domains.refresh
refreshDomain.queueReasons = {}
refreshDomain.queueModes = {}
refreshDomain.queueSources = {}
refreshDomain.passReasons = {}
refreshDomain.passModes = {}
refreshDomain.passSources = {}
refreshDomain.pendingQueued = false
refreshDomain.pendingMixed = false

function Diagnostics:Reset()
    for index = 1, #DOMAIN_NAMES do
        ResetDomain(self.domains[DOMAIN_NAMES[index]])
    end
    local combat = self.combat
    combat.flushes = 0
    combat.secureApplied = 0
    combat.structuralApplied = 0
    combat.externalSpecialQueued = 0
    combat.fullRefreshQueued = 0
    ClearMap(combat.driverReasons)
    ClearMap(combat.structuralBars)
    ClearMap(combat.externalSpecialBars)
end

function Diagnostics:Start(sampleEvery, mode)
    sampleEvery = tonumber(sampleEvery) or DEFAULT_SAMPLE_EVERY
    if sampleEvery < 1 then sampleEvery = 1 end
    if sampleEvery > 1024 then sampleEvery = 1024 end
    self.sampleEvery = math.floor(sampleEvery)
    self.mode = mode == "time" and "time" or "detail"
    self.detailEnabled = self.mode == "detail"
    self:Reset()
    self.enabled = true
    return self.sampleEvery
end

function Diagnostics:Stop()
    self.enabled = false
    self.detailEnabled = false
end

function Diagnostics:IsEnabled()
    return self.enabled == true
end

function Diagnostics:Begin(domainName, trackFrame)
    if self.enabled ~= true then return nil, nil end
    local domain = self.domains[domainName]
    if not domain then return nil, nil end
    domain.events = domain.events + 1
    local detailDomain = self.detailEnabled == true and domain or nil
    if detailDomain and trackFrame == true then
        local getTime = _G.GetTime
        local frameStamp = type(getTime) == "function" and getTime() or nil
        if type(frameStamp) == "number" then
            if domain.lastFrameStamp == frameStamp then
                domain.sameFrameRepeats = domain.sameFrameRepeats + 1
            else
                domain.lastFrameStamp = frameStamp
                domain.frames = domain.frames + 1
            end
        end
    end
    local clock = _G.debugprofilestop
    if type(clock) ~= "function" or domain.events % self.sampleEvery ~= 0 then
        return detailDomain, nil, nil
    end
    return detailDomain, clock(), domain
end

function Diagnostics:RecordRefreshQueue(reason, mode, source)
    if self.enabled ~= true or self.detailEnabled ~= true then return false end
    local domain = self.domains.refresh
    domain.queued = domain.queued + 1
    IncrementMap(domain.queueReasons, reason or "refresh")
    IncrementMap(domain.queueModes, mode or "full")
    IncrementMap(domain.queueSources, source or "unknown")
    reason = reason or "refresh"
    mode = mode or "full"
    source = source or "unknown"
    if domain.pendingQueued ~= true then
        domain.pendingQueued = true
        domain.pendingFirstReason = reason
        domain.pendingFirstMode = mode
        domain.pendingFirstSource = source
        domain.pendingMixed = false
    elseif domain.pendingFirstReason ~= reason
        or domain.pendingFirstMode ~= mode
        or domain.pendingFirstSource ~= source then
        domain.pendingMixed = true
    end
    domain.pendingLastReason = reason
    domain.pendingLastMode = mode
    domain.pendingLastSource = source
    return true
end

function Diagnostics:RecordRefreshPass(domain, reason, mode, source)
    if not domain or domain ~= self.domains.refresh then return false end
    local passReason = reason or "refresh"
    if domain.pendingQueued == true then
        if domain.pendingMixed == true then
            passReason = "mixed"
        else
            passReason = domain.pendingLastReason or domain.pendingFirstReason or passReason
        end
    end
    IncrementMap(domain.passReasons, passReason)
    IncrementMap(domain.passModes, mode or "none")
    IncrementMap(domain.passSources, source or "partial")
    domain.pendingQueued = false
    domain.pendingFirstReason = nil
    domain.pendingLastReason = nil
    domain.pendingFirstMode = nil
    domain.pendingLastMode = nil
    domain.pendingFirstSource = nil
    domain.pendingLastSource = nil
    domain.pendingMixed = false
    return true
end

function Diagnostics:RecordCombatFlush(
    secureApplied,
    structuralApplied,
    fullRefreshQueued,
    driverReasons,
    structuralBars,
    externalSpecialQueued,
    externalSpecialBars
)
    if self.enabled ~= true or self.detailEnabled ~= true then return false end
    local combat = self.combat
    combat.flushes = combat.flushes + 1
    combat.secureApplied = combat.secureApplied + (tonumber(secureApplied) or 0)
    combat.structuralApplied = combat.structuralApplied + (tonumber(structuralApplied) or 0)
    combat.externalSpecialQueued = combat.externalSpecialQueued
        + (tonumber(externalSpecialQueued) or 0)
    if fullRefreshQueued == true then
        combat.fullRefreshQueued = combat.fullRefreshQueued + 1
    end
    for reason, count in pairs(driverReasons or {}) do
        IncrementMap(combat.driverReasons, tostring(reason), tonumber(count) or 1)
    end
    for barId, reason in pairs(structuralBars or {}) do
        IncrementMap(
            combat.structuralBars,
            tostring(barId) .. ":" .. tostring(reason),
            1
        )
    end
    for barId, reason in pairs(externalSpecialBars or {}) do
        IncrementMap(
            combat.externalSpecialBars,
            tostring(barId) .. ":" .. tostring(reason),
            1
        )
    end
    return true
end

function Diagnostics:Finish(domain, started)
    if not domain or type(started) ~= "number" then return end
    local clock = _G.debugprofilestop
    if type(clock) ~= "function" then return end
    local finishedAt = clock()
    local elapsed = finishedAt - started
    if elapsed < 0 then return end
    domain.samples = domain.samples + 1
    domain.sampleMs = domain.sampleMs + elapsed
    if elapsed > domain.maxMs then
        domain.maxMs = elapsed
        domain.maxAtMS = finishedAt
    end
end

function Diagnostics:Add(domain, field, value)
    if not domain or domain[field] == nil then return end
    domain[field] = domain[field] + (tonumber(value) or 0)
end

function Diagnostics:GetSnapshot()
    local snapshot = {
        enabled = self.enabled == true,
        sampleEvery = self.sampleEvery,
        mode = self.mode,
        domains = {},
    }
    for index = 1, #DOMAIN_NAMES do
        local name = DOMAIN_NAMES[index]
        local source = self.domains[name]
        local target = {}
        for key, value in pairs(source) do
            if type(value) == "table" then
                target[key] = CopyMap(value)
            elseif key ~= "lastFrameStamp" then
                target[key] = value
            end
        end
        snapshot.domains[name] = target
    end
    snapshot.combat = {
        flushes = self.combat.flushes,
        secureApplied = self.combat.secureApplied,
        structuralApplied = self.combat.structuralApplied,
        externalSpecialQueued = self.combat.externalSpecialQueued,
        fullRefreshQueued = self.combat.fullRefreshQueued,
        driverReasons = CopyMap(self.combat.driverReasons),
        structuralBars = CopyMap(self.combat.structuralBars),
        externalSpecialBars = CopyMap(self.combat.externalSpecialBars),
    }
    return snapshot
end

local function AppendBreakdown(lines, label, values)
    local entries = {}
    for key, value in pairs(values or {}) do
        entries[#entries + 1] = { key = tostring(key), value = value }
    end
    table.sort(entries, function(left, right)
        if left.value == right.value then return left.key < right.key end
        return left.value > right.value
    end)
    if #entries == 0 then return end
    local parts = {}
    for index = 1, #entries do
        local entry = entries[index]
        parts[index] = entry.key .. "=" .. tostring(entry.value)
    end
    lines[#lines + 1] = label .. " " .. table.concat(parts, " ")
end

function Diagnostics:GetLines()
    local lines = {
        string.format("YActionBar perf: enabled=%s mode=%s sampleEvery=%d", tostring(self.enabled == true), self.mode, self.sampleEvery),
    }
    for index = 1, #DOMAIN_NAMES do
        local name = DOMAIN_NAMES[index]
        local domain = self.domains[name]
        local averageMs = domain.samples > 0 and (domain.sampleMs / domain.samples) or 0
        lines[#lines + 1] = string.format(
            "YActionBar perf %s: events=%d frames=%d sameFrame=%d samples=%d avg=%.4fms max=%.4fms candidates=%d buttons=%d eligible=%d ineligible=%d active=%d changes=%d backendReads=%d writes=%d fallbacks=%d",
            name,
            domain.events,
            domain.frames,
            domain.sameFrameRepeats,
            domain.samples,
            averageMs,
            domain.maxMs,
            domain.candidates,
            domain.buttons,
            domain.eligibleButtons,
            domain.ineligibleButtons,
            domain.activeButtons,
            domain.changes,
            domain.backendReads,
            domain.writes,
            domain.fallbacks
        )
    end
    local cooldown = self.domains.cooldown
    lines[#lines + 1] = string.format(
        "YActionBar perf cooldown detail: gcdMode=%s activeMainReads=%d activeMainWrites=%d repeatGCDCandidates=%d chargeInfoReads=%d skippedGCDWrites=%d doneResets=%d",
        self.gcdMode,
        cooldown.activeMainReads,
        cooldown.activeMainWrites,
        cooldown.repeatGCDCandidates,
        cooldown.chargeInfoReads,
        cooldown.skippedGCDWrites,
        cooldown.doneResets
    )
    local refresh = self.domains.refresh
    local coalesced = refresh.queued - refresh.events
    if coalesced < 0 then coalesced = 0 end
    lines[#lines + 1] = string.format(
        "YActionBar perf refresh queue: queued=%d passes=%d coalesced=%d",
        refresh.queued,
        refresh.events,
        coalesced
    )
    AppendBreakdown(lines, "YActionBar perf refresh queueReasons:", refresh.queueReasons)
    AppendBreakdown(lines, "YActionBar perf refresh queueModes:", refresh.queueModes)
    AppendBreakdown(lines, "YActionBar perf refresh queueSources:", refresh.queueSources)
    AppendBreakdown(lines, "YActionBar perf refresh passReasons:", refresh.passReasons)
    AppendBreakdown(lines, "YActionBar perf refresh passModes:", refresh.passModes)
    AppendBreakdown(lines, "YActionBar perf refresh passSources:", refresh.passSources)
    local combat = self.combat
    lines[#lines + 1] = string.format(
        "YActionBar perf combat flush: flushes=%d secureApplied=%d structuralApplied=%d externalSpecialQueued=%d fullRefreshQueued=%d",
        combat.flushes,
        combat.secureApplied,
        combat.structuralApplied,
        combat.externalSpecialQueued,
        combat.fullRefreshQueued
    )
    AppendBreakdown(lines, "YActionBar perf combat driverReasons:", combat.driverReasons)
    AppendBreakdown(lines, "YActionBar perf combat structuralBars:", combat.structuralBars)
    AppendBreakdown(lines, "YActionBar perf combat externalSpecialBars:", combat.externalSpecialBars)
    return lines
end
