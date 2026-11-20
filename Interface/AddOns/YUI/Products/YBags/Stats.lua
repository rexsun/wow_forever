local YUI = _G.YUI
local B = YUI and YUI.YBags
if not B then return end
B.Stats = { enabled=false, reads=0, classified=0, layouts=0, writes=0, flushes=0, pendingRefresh=false,
    listeners=0, timers=0, pool=0, mismatches=0, errors=0, snapshots=0 }
function B:GetStats()
    return self:Copy(self.Stats)
end
