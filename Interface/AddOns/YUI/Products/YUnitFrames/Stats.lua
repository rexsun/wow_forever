local UF = _G.YUI and _G.YUI.YUnitFrames
if not UF then return end

-- Called only by an explicit diagnostic request; counters contain no unit data.
function UF:GetStats()
    local stats = self.Stats
    return {
        enabled = stats.enabled, pending = stats.pending, listeners = stats.listeners,
        frames = stats.frames, events = stats.events, textWrites = stats.textWrites, valueWrites = stats.valueWrites,
    }
end
