local YUI = _G.YUI
if not YUI or not YUI.YChat then return end

local YChat = YUI.YChat
local Guard = {}
YChat.ConflictGuard = Guard

local function Evaluate(options)
    local external = YUI.API and YUI.API.External
    if type(external) ~= "table" or type(external.ResolveCapability) ~= "function" then
        return nil
    end
    local snapshot = external:ResolveCapability("ui.chat.controller", options)
    if type(snapshot) ~= "table" then return nil end
    if snapshot.status == "inactive" and snapshot.active == false then
        return { blocked = false, status = "inactive", matches = {}, degraded = snapshot.degraded == true }
    end
    local matches = type(snapshot.matches) == "table" and snapshot.matches or {}
    for index = 1, #matches do
        local match = matches[index]
        if type(match) == "table" then
            match.id = match.addon
            match.label = match.controller
            match.unknown = match.status == "unknown"
        end
    end
    return {
        blocked = true,
        status = snapshot.status,
        controller = snapshot.controller,
        matches = matches,
        degraded = snapshot.degraded == true or snapshot.status == "unknown",
        reason = snapshot.status == "unknown" and "addon-state-unreadable" or "external-chat-controller",
    }
end

function Guard:Check(options)
    local ok, result = pcall(Evaluate, options)
    if ok and type(result) == "table" then return result end
    return {
        blocked = true,
        status = "unknown",
        controller = nil,
        matches = {},
        degraded = true,
        reason = "conflict-guard-error",
    }
end
