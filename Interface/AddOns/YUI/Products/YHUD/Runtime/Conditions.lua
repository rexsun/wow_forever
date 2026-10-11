local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local Conditions = YHUD.Conditions or {}
YHUD.Conditions = Conditions

Conditions.SELF_READY = "self-ready"
Conditions.SELF_COOLDOWN = "self-cooldown"
Conditions.AURA_PRESENT = "aura-present"
Conditions.AURA_MISSING = "aura-missing"
Conditions.CONDITION_MET = "condition-met"
Conditions.TIMER_ENDED = "timer-ended"

local function ResolveAuraState(state, auraResolved, auraPresent)
    if auraResolved ~= nil then
        return auraResolved == true, auraPresent == true
    end
    if type(state) ~= "table" or state.sourceKind ~= "aura"
        or state.secret == true or state.resolved ~= true then
        return false, false
    end
    return true, state.available == true
end

function Conditions:Evaluate(
    conditionType,
    kind,
    state,
    auraResolved,
    auraPresent,
    persistentSlot
)
    if conditionType == self.SELF_READY
        or conditionType == self.SELF_COOLDOWN then
        if kind ~= "cooldown" or type(state) ~= "table" then
            return false, false
        end
        local sourceKind = state.sourceKind
        if sourceKind == "spell" then
            if state.available ~= true then return false, false end
        elseif sourceKind == "item" then
            if state.resolved ~= true or state.secret == true
                or state.available ~= true then
                return false, false
            end
        else
            return false, false
        end
        local cooldownActive = state.cooldownActive == true
            or state.chargeActive == true
        return conditionType == self.SELF_READY and not cooldownActive
            or conditionType == self.SELF_COOLDOWN and cooldownActive,
            true
    end

    if kind == "aura" then
        local resolved, present = ResolveAuraState(
            state,
            auraResolved,
            auraPresent
        )
        if not resolved then return false, false end
        if conditionType == self.AURA_PRESENT then return present, true end
        if conditionType == self.AURA_MISSING then
            return not present and persistentSlot == true, true
        end
    end

    if (conditionType == self.CONDITION_MET
            or conditionType == self.TIMER_ENDED)
        and kind == "event-window" then
        if type(state) ~= "table"
            or (state.sourceKind ~= "spell-event-window"
                and state.sourceKind ~= "buff-timer")
            or state.secret == true or state.resolved ~= true then
            return false, false
        end
        local active = state.available == true
        return conditionType == self.CONDITION_MET and active
            or conditionType == self.TIMER_ENDED and not active,
            true
    end
    return false, false
end

function Conditions:Matches(...)
    local matched = self:Evaluate(...)
    return matched == true
end
