local YUI = _G.YUI
if not YUI or not YUI.YMap then return end

local YMap = YUI.YMap
local Diagnostics = {
    enabled = false,
    detailEnabled = false,
    samples = {},
}
YMap.HotDiagnostics = Diagnostics

local clock = debugprofilestop or function() return 0 end

function Diagnostics:SetEnabled(enabled, detailEnabled)
    self.enabled = enabled == true
    self.detailEnabled = self.enabled and detailEnabled == true or false
    if not self.enabled then
        self.samples = {}
    end
end

function Diagnostics:Begin()
    if self.enabled ~= true then return nil, nil end
    return clock(), nil
end

function Diagnostics:Finish(name, startedAt)
    if self.enabled ~= true or type(startedAt) ~= "number" then return false end
    local sample = self.samples[name]
    if type(sample) ~= "table" then
        sample = { count = 0, totalMs = 0, maxMs = 0 }
        self.samples[name] = sample
    end
    local elapsed = math.max(0, clock() - startedAt)
    sample.count = sample.count + 1
    sample.totalMs = sample.totalMs + elapsed
    if elapsed > sample.maxMs then sample.maxMs = elapsed end
    return true
end

function Diagnostics:Detail(name, value)
    if self.enabled ~= true or self.detailEnabled ~= true then return false end
    self.samples[name] = value
    return true
end

function Diagnostics:GetSnapshot(target)
    target = type(target) == "table" and target or {}
    for name, sample in pairs(self.samples) do
        if type(sample) == "table" then
            target[name] = {
                count = sample.count,
                totalMs = sample.totalMs,
                maxMs = sample.maxMs,
            }
        else
            target[name] = sample
        end
    end
    return target
end
