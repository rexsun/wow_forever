local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local Guard = {}
YHUD.ConflictGuard = Guard

function Guard:Check(options)
    local external = YUI.API and YUI.API.External
    if type(external) ~= "table" or type(external.ResolveCapability) ~= "function" then
        return { blocked = true, status = "unknown", controller = nil, matches = {}, degraded = true, reason = "external-state-unreadable" }
    end
    local ok, snapshot = pcall(external.ResolveCapability, external, "ui.cooldown.controller", options)
    if not ok or type(snapshot) ~= "table" then
        return { blocked = true, status = "unknown", controller = nil, matches = {}, degraded = true, reason = "external-state-unreadable" }
    end
    if snapshot.status == "inactive" and snapshot.active == false then
        return { blocked = false, status = "inactive", controller = nil, matches = {}, degraded = snapshot.degraded == true }
    end
    return {
        blocked = true,
        status = snapshot.status,
        controller = snapshot.controller,
        matches = type(snapshot.matches) == "table" and snapshot.matches or {},
        degraded = snapshot.degraded == true or snapshot.status == "unknown",
        reason = snapshot.status == "active" and "external-cooldown-controller" or "external-state-unreadable",
    }
end
