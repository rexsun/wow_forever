local YUI = _G.YUI
if not YUI or not YUI.YActionBar then return end

local YAB = YUI.YActionBar
local Guard = {}
YAB.ConflictGuard = Guard

function Guard:Check(options)
    local external = YUI.API and YUI.API.External
    if type(external) ~= "table" or type(external.ResolveCapability) ~= "function" then
        return { blocked = true, status = "unknown", controller = nil, reason = "external-state-unreadable", matches = {}, degraded = true }
    end
    local ok, snapshot = pcall(external.ResolveCapability, external, "ui.actionbar.controller", options)
    if not ok or type(snapshot) ~= "table" then
        return { blocked = true, status = "unknown", controller = nil, reason = "external-state-unreadable", matches = {}, degraded = true }
    end
    if snapshot.status == "inactive" and snapshot.active == false then
        return { blocked = false, status = "inactive", reason = nil, matches = {}, degraded = snapshot.degraded == true }
    end
    return {
        blocked = true,
        status = snapshot.status,
        controller = snapshot.controller,
        reason = snapshot.status == "unknown" and "external-state-unreadable" or "external-actionbar-controller",
        matches = type(snapshot.matches) == "table" and snapshot.matches or {},
        degraded = snapshot.degraded == true or snapshot.status == "unknown",
    }
end
