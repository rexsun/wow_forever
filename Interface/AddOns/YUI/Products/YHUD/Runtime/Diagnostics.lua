local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local Diagnostics = YHUD.Diagnostics or {}
YHUD.Diagnostics = Diagnostics

Diagnostics.enabled = false
Diagnostics.detailEnabled = false
Diagnostics.nextIndex = 1
Diagnostics.maxEntries = 32
Diagnostics.entries = Diagnostics.entries or {}

local clock = debugprofilestop or function() return 0 end

function Diagnostics:ApplyConfig(profile)
    local config = profile and profile.diagnostics
    self.enabled = config and config.enabled == true or false
    self.detailEnabled = self.enabled and config.detail == true or false
end

function Diagnostics:Begin()
    if self.enabled ~= true then return nil, nil end
    return clock(), nil
end

function Diagnostics:Finish(code, startedAt)
    if self.enabled ~= true or type(startedAt) ~= "number" then return false end
    return self:Record(code, math.max(0, clock() - startedAt))
end

function Diagnostics:Detail(code, value)
    if self.enabled ~= true or self.detailEnabled ~= true then return false end
    return self:Record(code, value)
end

function Diagnostics:Record(code, value)
    if not self.enabled then return false end
    local index = self.nextIndex
    local entry = self.entries[index]
    if not entry then
        entry = {}
        self.entries[index] = entry
    end
    entry.code = code
    entry.value = self.detailEnabled and value or nil
    self.nextIndex = index >= self.maxEntries and 1 or index + 1
    return true
end

function Diagnostics:Clear()
    for index = 1, self.maxEntries do
        local entry = self.entries[index]
        if entry then
            entry.code = nil
            entry.value = nil
        end
    end
    self.nextIndex = 1
end
