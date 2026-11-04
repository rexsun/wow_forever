local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local Glow = YHUD.Glow or {}
YHUD.Glow = Glow

local Conditions = YHUD.Conditions
local STACK_DRIVER_CONDITION = { operator = "gt", value = 100 }

local function MatchesAuthoredCount(condition, count)
    local value, operator = condition.value, condition.operator
    if operator == "lt" then return count < value end
    if operator == "lte" then return count <= value end
    if operator == "eq" then return count == value end
    if operator == "gte" then return count >= value end
    return operator == "gt" and count > value
end

local function BuildStackRanges(compiled)
    local ranges = {}
    -- This finite public grid describes configuration, never a live Aura.
    -- 101 represents every count above the largest editable threshold.
    for combatIndex = 1, 2 do
        local combat = combatIndex == 2
        local previous
        for count = 0, 101 do
            local winner
            for index = 1, #compiled.rules do
                local rule = compiled.rules[index]
                if rule.stackCondition and (combat or not rule.combatOnly)
                    and MatchesAuthoredCount(rule.stackCondition, count) then
                    winner = rule
                    break
                end
            end
            if winner then
                if previous and previous.rule == winner then
                    previous.maximum = count
                else
                    previous = { rule = winner, minimum = count, maximum = count,
                        inCombat = combat, outOfCombat = not combat }
                    ranges[#ranges + 1] = previous
                end
            else
                previous = nil
            end
        end
    end
    -- Share identical combat/noncombat intervals and their glow objects.
    for index = #ranges, 1, -1 do
        local range = ranges[index]
        for earlier = 1, index - 1 do
            local other = ranges[earlier]
            if other.rule == range.rule and other.minimum == range.minimum
                and other.maximum == range.maximum then
                other.inCombat = other.inCombat or range.inCombat
                other.outOfCombat = other.outOfCombat or range.outOfCombat
                table.remove(ranges, index)
                break
            end
        end
    end
    return ranges
end

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
        stackRuleCount = 0,
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
                stackCondition = conditionType == "aura-stacks" and condition or nil,
                appearance = rule.appearance,
                combatOnly = rule.combatOnly == true,
            }
            compiled.hasCombatOnly = compiled.hasCombatOnly
                or rule.combatOnly == true
            if conditionType == "aura-stacks" then compiled.stackRuleCount = compiled.stackRuleCount + 1 end
        end
    end
    if compiled.nativeConfig
        and compiled.nativeConfig.combatOnly == true then
        compiled.hasCombatOnly = true
    end
    if compiled.stackRuleCount > 1 then compiled.stackRanges = BuildStackRanges(compiled) end
    return compiled
end

function Glow:ConfigureStackSet(parent, target, compiled, width, height, set, skinOwner)
    local gui = YUI.GUI2
    if not (compiled and compiled.stackRanges and gui and gui.CreateAuraApplicationGate
        and gui.ConfigureAuraApplicationRangeClip and gui.CreateFrame and gui.CreateGlow) then return nil end
    if type(width) ~= "number" or type(height) ~= "number"
        or not (width > 0 and width < math.huge and height > 0 and height < math.huge) then return nil end
    set = set or { pieces = {}, parent = parent, target = target }
    set.skinOwner = skinOwner or target
    if not set.gate then
        set.gate = gui:CreateAuraApplicationGate(parent, target, STACK_DRIVER_CONDITION, width, height)
    elseif not gui:ConfigureAuraApplicationGate(set.gate, target, STACK_DRIVER_CONDITION, width, height) then
        return nil
    end
    if not set.gate then return nil end
    for index = 1, math.max(#set.pieces, #compiled.stackRanges) do
        local range, piece = compiled.stackRanges[index], set.pieces[index]
        if range then
            piece = piece or {}
            piece.range = range
            piece.clip = gui:ConfigureAuraApplicationRangeClip(piece.clip, set.gate, parent,
                range.minimum, range.maximum)
            if not piece.clip then return nil end
            -- CreateGlow caches one object per target. Each interval needs its
            -- own stable target so later rules cannot replace earlier glows.
            if not piece.host then
                piece.host = gui:CreateFrame(parent, { mouse = false })
                piece.host:SetAllPoints(target)
            end
            if not piece.glow then
                piece.glow = gui:CreateGlow(piece.host, { hidden = true, restrictedParent = true,
                    trustedWidth = width, trustedHeight = height, skinOwner = skinOwner or target })
            end
            if not piece.glow then return nil end
            local layoutChanged = piece.glow._SetGlowLayoutContext
                and piece.glow:_SetGlowLayoutContext(true, width, height)
            if piece.glow.SetGlowSkinOwner then piece.glow:SetGlowSkinOwner(skinOwner or target) end
            if layoutChanged or piece.appearance ~= range.rule.appearance then
                piece.glow:SetGlowParams(range.rule.appearance)
                piece.appearance = range.rule.appearance
            end
            set.pieces[index] = piece
        elseif piece then
            piece.range = nil
            if piece.shown then
                piece.glow:SetGlowShown(false)
                piece.shown = false
            end
        end
    end
    set.compiled, set.width, set.height = compiled, width, height
    set.released = nil
    return set
end

function Glow:ApplyStackSet(set, inCombat, enabled, targetShape, frameLevel, frameStrata)
    if not set then return false, false end
    local changed, armed = false, false
    targetShape = targetShape or "square"
    for index = 1, #set.pieces do
        local piece = set.pieces[index]
        local range = piece.range
        local shown = enabled == true and range ~= nil
            and (inCombat and range.inCombat or not inCombat and range.outOfCombat) == true
        local glow = piece.glow
        if shown then
            armed = true
            if glow.SetGlowSkinOwner then
                changed = glow:SetGlowSkinOwner(set.skinOwner) or changed
            end
            local shape = range.rule.appearance.style == "proc"
                and (targetShape == "circle" and "circle" or "square") or targetShape
            if piece.shape ~= shape or piece.targetShape ~= targetShape then
                glow:SetGlowShape(shape, targetShape)
                piece.shape, piece.targetShape = shape, targetShape
                changed = true
            end
            if glow._SetGlowLayerContext then
                changed = glow:_SetGlowLayerContext(frameLevel, frameStrata) or changed
            end
            changed = glow:SetGlowClipParent(piece.clip.clip) or changed
        end
        if piece.shown ~= shown then
            glow:SetGlowShown(shown)
            piece.shown, changed = shown, true
        end
    end
    if armed then set.released = nil end
    return changed, armed
end

function Glow:ReleaseStackSet(set)
    if not set or set.released then return end
    self:ApplyStackSet(set, false, false)
    for index = 1, #set.pieces do set.pieces[index].glow:SetGlowClipParent(nil) end
    set.gate.driver:SetValue(0)
    set.gate.lastPublicValue = nil
    set.released = true
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
        and nativeConfig.mode ~= "disabled"
        and (nativeConfig.combatOnly ~= true or inCombat) then
        return nativeConfig.mode == "custom" and "native-custom"
            or "native-default",
            nativeConfig.appearance
    end
    for index = 1, #compiled.rules do
        local rule = compiled.rules[index]
        if (rule.combatOnly ~= true or inCombat)
            and (preview or (rule.stackCondition and compiled.kind == "aura"
                and auraResolved == true and auraPresent == true)
                or Conditions and Conditions:Matches(
                rule.conditionType,
                compiled.kind,
                state,
                auraResolved,
                auraPresent,
                persistentSlot
            )) then
            return "custom-rule", rule.appearance, rule
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
