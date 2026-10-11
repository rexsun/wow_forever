local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local Glow = YHUD.Glow or {}
YHUD.Glow = Glow

local Conditions = YHUD.Conditions

function Glow:SupportsMonitor(profile, monitor)
    return YHUD:GetMonitorGlowCapabilities(profile, monitor) ~= nil
end

function Glow:HasCondition(config, conditionType)
    local rules = type(config) == "table" and config.rules
    if type(rules) ~= "table" then return false end
    for index = 1, #rules do
        local condition = type(rules[index]) == "table"
            and rules[index].condition or nil
        if type(condition) == "table" and condition.type == conditionType then
            return true
        end
    end
    return false
end

function Glow:Compile(profile, monitor)
    local capabilities = YHUD:GetMonitorGlowCapabilities(profile, monitor)
    if not capabilities then return nil end
    local compiled = {
        kind = capabilities.kind,
        nativeProc = capabilities.nativeProc == true,
        nativeConfig = capabilities.nativeProc == true
            and YHUD:GetEffectiveNativeProcGlow(profile, monitor) or nil,
        rules = {},
        hasCombatOnly = false,
    }
    local sourceRules = type(monitor.glow) == "table"
        and monitor.glow.rules or nil
    for index = 1, #(sourceRules or {}) do
        local rule = sourceRules[index]
        local condition = type(rule) == "table" and rule.condition or nil
        local conditionType = type(condition) == "table"
            and condition.type or nil
        if YHUD:IsMonitorGlowConditionSupported(
            profile,
            monitor,
            conditionType
        ) and type(rule.appearance) == "table"
            and rule.appearance.style ~= "none" then
            compiled.rules[#compiled.rules + 1] = {
                conditionType = conditionType,
                appearance = rule.appearance,
                combatOnly = rule.combatOnly == true,
            }
            compiled.hasCombatOnly = compiled.hasCombatOnly
                or rule.combatOnly == true
        end
    end
    if compiled.nativeConfig
        and compiled.nativeConfig.combatOnly == true then
        compiled.hasCombatOnly = true
    end
    return compiled
end

function Glow:Resolve(
    compiled,
    state,
    inCombat,
    preview,
    nativeSignal,
    auraResolved,
    auraPresent,
    persistentSlot
)
    if type(compiled) ~= "table" then return nil end
    if nativeSignal == nil then
        nativeSignal = type(state) == "table"
            and state.sourceKind == "spell"
            and state.activationOverlay == true
    end
    local nativeConfig = compiled.nativeConfig
    if nativeSignal == true and nativeConfig
        and (nativeConfig.combatOnly ~= true or inCombat) then
        return nativeConfig.mode == "custom" and "native-custom"
            or "native-default",
            nativeConfig.appearance
    end
    for index = 1, #compiled.rules do
        local rule = compiled.rules[index]
        if (rule.combatOnly ~= true or inCombat)
            and (preview or Conditions and Conditions:Matches(
                rule.conditionType,
                compiled.kind,
                state,
                auraResolved,
                auraPresent,
                persistentSlot
            )) then
            return "custom-rule", rule.appearance
        end
    end
    return nil
end

function Glow:Evaluate(profile, monitor, state, preview, inCombat)
    local compiled = type(monitor) == "table"
        and monitor._yhudGlowRuntime or self:Compile(profile, monitor)
    local kind, appearance = self:Resolve(
        compiled,
        state,
        inCombat == true,
        preview == true
    )
    return kind ~= nil, appearance, kind
end
