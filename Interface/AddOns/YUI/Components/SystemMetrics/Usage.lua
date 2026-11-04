-- Addon-usage formatting and explicit diagnostics shared by system information and addon management.
local YUI = _G.YUI
if not YUI then return end
local existing = YUI.SystemMetricsUsage
local Usage = existing or {}
YUI.SystemMetricsUsage = Usage

if not Usage.ReclaimMemory then
    function Usage.ReclaimMemory()
        if type(gcinfo) ~= "function" or type(collectgarbage) ~= "function" then return nil end
        local before = gcinfo()
        local ok = pcall(collectgarbage, "collect")
        if not ok then return nil end
        return math.max(0, before - gcinfo())
    end
end
if existing then return end

function Usage.Percent(cpu, application, total)
    if cpu == nil or application == nil or total == nil then return nil end
    local denominator = application - total + cpu
    if denominator <= 0 then return nil end
    return cpu / denominator * 100
end

function Usage.FormatPercent(value)
    if value == nil then return "—" end
    if value >= 10 then return string.format("%.0f%%", value) end
    if value >= .1 then return string.format("%.1f%%", value) end
    if value >= .01 then return string.format("%.2f%%", value) end
    return "<0.01%"
end

function Usage.FormatMemory(value)
    if value == nil then return "—" end
    if value > 1024 then return string.format("%.1f mb", value / 1024) end
    return string.format("%.0f kb", value)
end
