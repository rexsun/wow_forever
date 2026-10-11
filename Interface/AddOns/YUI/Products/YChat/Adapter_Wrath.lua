local YUI = _G.YUI
if not YUI or not YUI.YChat or not YUI.YChat.Adapter then return end

local Adapter = YUI.YChat.Adapter
local Backend = {
    flavor = "wrath",
}

local InCombatLockdown = _G.InCombatLockdown
local pcall = pcall
local type = type

function Backend:CanCallProtected(object)
    if object == nil then return false, "protected-object-missing" end
    local isProtected = object.IsProtected
    if type(isProtected) ~= "function" or type(InCombatLockdown) ~= "function" then
        return false, "protected-check-unsupported"
    end

    local objectOK, protected = pcall(isProtected, object)
    if not objectOK or type(protected) ~= "boolean" then
        return false, "protected-check-unknown"
    end

    local combatOK, inCombat = pcall(InCombatLockdown)
    if not combatOK or type(inCombat) ~= "boolean" then
        return false, "protected-check-unknown"
    end
    if inCombat ~= false then return false, "protected-write-denied" end
    return true
end

function Backend:ReadRestrictionState()
    return "UNSUPPORTED"
end

function Backend:RegisterEvents()
    return 0
end

function Backend:HandleEvent()
    return false
end

Adapter:SetClientBackend(Backend)
