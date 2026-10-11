local YUI = _G.YUI
if not YUI or not YUI.YChat then return end

local YChat = YUI.YChat
local Diagnostics = {}
YChat.HotDiagnostics = Diagnostics

local DEFAULT_SAMPLE_EVERY = 32
local clock = _G.debugprofilestop

Diagnostics.enabled = false
Diagnostics.detailEnabled = false
Diagnostics.sampleEvery = DEFAULT_SAMPLE_EVERY
Diagnostics.events = 0
Diagnostics.samples = 0
Diagnostics.totalMs = 0
Diagnostics.maxMs = 0
Diagnostics.detailWrites = 0

function Diagnostics:Reset()
    self.events = 0
    self.samples = 0
    self.totalMs = 0
    self.maxMs = 0
    self.detailWrites = 0
end

function Diagnostics:Start(sampleEvery, detailEnabled)
    sampleEvery = tonumber(sampleEvery) or DEFAULT_SAMPLE_EVERY
    if sampleEvery < 1 then sampleEvery = 1 end
    if sampleEvery > 1024 then sampleEvery = 1024 end

    self.sampleEvery = math.floor(sampleEvery)
    self.detailEnabled = detailEnabled == true
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

function Diagnostics:Begin()
    if self.enabled ~= true then return nil, nil end

    self.events = self.events + 1
    local detail = self.detailEnabled == true and self or nil
    if type(clock) ~= "function" or self.events % self.sampleEvery ~= 0 then
        return detail, nil
    end

    return detail, clock()
end

function Diagnostics:CanWriteDetail()
    if self.enabled ~= true or self.detailEnabled ~= true then return false end
    self.detailWrites = self.detailWrites + 1
    return true
end

function Diagnostics:Finish(started)
    if self.enabled ~= true or type(started) ~= "number" then return false end
    if type(clock) ~= "function" then return false end

    local elapsed = clock() - started
    if elapsed < 0 then return false end

    self.samples = self.samples + 1
    self.totalMs = self.totalMs + elapsed
    if elapsed > self.maxMs then self.maxMs = elapsed end
    return true
end

function Diagnostics:GetSnapshot(target)
    target = target or {}
    target.enabled = self.enabled == true
    target.detailEnabled = self.detailEnabled == true
    target.sampleEvery = self.sampleEvery
    target.events = self.events
    target.samples = self.samples
    target.totalMs = self.totalMs
    target.maxMs = self.maxMs
    target.detailWrites = self.detailWrites
    return target
end
