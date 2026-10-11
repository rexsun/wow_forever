local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD or YUI.IsRetail == false then return end

local Conditions = YHUD.Conditions
local SoundService = YUI.Sound
local CombatAPI = YUI.API and YUI.API.Combat or YUI.WOW_API
local RuntimeSound = YHUD.Sound or {}
YHUD.Sound = RuntimeSound

local PLAY_COOLDOWN = 0.35
local MIN_COOLDOWN_ACTIVE_SECONDS = 0.75
local COOLDOWN_ACTIVE_KEY = {}
local COOLDOWN_STARTED_AT_KEY = {}

RuntimeSound.observed = RuntimeSound.observed
    or setmetatable({}, { __mode = "k" })

local function GetRuntimeTime()
    if CombatAPI and CombatAPI.GetTime then
        return tonumber(CombatAPI.GetTime()) or 0
    end
    return 0
end

function RuntimeSound:Reset()
    self.observed = setmetatable({}, { __mode = "k" })
end

function RuntimeSound:Compile(profile, monitor)
    if SoundService and SoundService.RuleStore then return nil end
    local capabilities = YHUD:GetMonitorSoundCapabilities(profile, monitor)
    if not capabilities then return nil end
    local compiled = {
        kind = capabilities.kind,
        rules = {},
    }
    if YHUD.LegacySoundMigration then YHUD.LegacySoundMigration:CaptureIdentity(profile, monitor, compiled) end
    local sourceRules = type(monitor.sound) == "table"
        and monitor.sound.rules or nil
    for index = 1, #(sourceRules or {}) do
        local rule = sourceRules[index]
        local condition = type(rule) == "table" and rule.condition or nil
        local conditionType = type(condition) == "table"
            and condition.type or nil
        if YHUD:IsMonitorSoundConditionSupported(
            profile,
            monitor,
            conditionType
        ) then
            compiled.rules[#compiled.rules + 1] = {
                conditionType = conditionType,
                sound = type(rule.sound) == "string" and rule.sound or nil,
            }
        end
    end
    return #compiled.rules > 0 and compiled or nil
end

local function ResolveProtectedCooldownState(
    compiled,
    state,
    observed
)
    if compiled.kind ~= "cooldown" then return nil, nil end
    if type(state) == "table" and state.secret == true then
        local previousActive = observed[COOLDOWN_ACTIVE_KEY]
        if previousActive ~= nil then
            return previousActive == true, true
        end
        return false, false
    end

    local active, known = Conditions:Evaluate(
        Conditions.SELF_COOLDOWN,
        compiled.kind,
        state
    )
    if known ~= true then
        local previousActive = observed[COOLDOWN_ACTIVE_KEY]
        if previousActive ~= nil then
            return previousActive == true, true
        end
        return false, false
    end

    active = active == true
    local previousActive = observed[COOLDOWN_ACTIVE_KEY]
    if previousActive == nil then
        observed[COOLDOWN_ACTIVE_KEY] = active
        observed[COOLDOWN_STARTED_AT_KEY] = active
            and GetRuntimeTime() or nil
        return active, true
    end

    if active then
        if previousActive ~= true
            or type(observed[COOLDOWN_STARTED_AT_KEY]) ~= "number" then
            observed[COOLDOWN_STARTED_AT_KEY] = GetRuntimeTime()
        end
        observed[COOLDOWN_ACTIVE_KEY] = true
        return true, true
    end

    if previousActive == true then
        local startedAt = observed[COOLDOWN_STARTED_AT_KEY]
        if type(startedAt) == "number"
            and type(state) == "table"
            and state.sourceKind == "spell" then
            local elapsed = GetRuntimeTime() - startedAt
            if elapsed < MIN_COOLDOWN_ACTIVE_SECONDS then
                return true, true
            end
        end
    end

    observed[COOLDOWN_ACTIVE_KEY] = false
    observed[COOLDOWN_STARTED_AT_KEY] = nil
    return false, true
end

function RuntimeSound:Observe(
    monitor,
    compiled,
    state,
    auraResolved,
    auraPresent,
    persistentSlot,
    suppressed,
    chargeCompleted
)
    if SoundService and SoundService.RuleStore then return false end
    if type(monitor) ~= "table" or type(compiled) ~= "table"
        or not Conditions then
        return false
    end
    if suppressed == true then
        self.observed[monitor] = nil
        return false
    end

    local observed = self.observed[monitor]
    if not observed then
        observed = {}
        self.observed[monitor] = observed
    end
    local protectedCooldownActive, protectedCooldownKnown =
        ResolveProtectedCooldownState(
            compiled,
            state,
            observed
        )
    local trustedChargeCompletion = chargeCompleted == true
        and compiled.kind == "cooldown"
        and protectedCooldownKnown == true
        and type(state) == "table"
        and state.sourceKind == "spell"
        and state.available == true
        and state.secret ~= true
    local chargeStillRecovering = trustedChargeCompletion
        and state.chargeActive == true
    if trustedChargeCompletion and not chargeStillRecovering then
        protectedCooldownActive = false
        observed[COOLDOWN_ACTIVE_KEY] = false
        observed[COOLDOWN_STARTED_AT_KEY] = nil
    end
    local soundPersistentSlot = compiled.kind == "aura"
        and true or persistentSlot
    local played = false
    for index = 1, #compiled.rules do
        local rule = compiled.rules[index]
        local matched, known
        if compiled.kind == "cooldown"
            and (rule.conditionType == Conditions.SELF_READY
                or rule.conditionType == Conditions.SELF_COOLDOWN) then
            known = protectedCooldownKnown == true
            if known then
                matched = rule.conditionType == Conditions.SELF_COOLDOWN
                    and protectedCooldownActive == true
                    or rule.conditionType == Conditions.SELF_READY
                        and protectedCooldownActive ~= true
            else
                matched = false
            end
        elseif type(state) == "table" and state.secret == true then
            matched, known = false, false
        else
            matched, known = Conditions:Evaluate(
                rule.conditionType,
                compiled.kind,
                state,
                auraResolved,
                auraPresent,
                soundPersistentSlot
            )
        end
        local previous = observed[rule.conditionType]
        local playResult
        if not known then
            observed[rule.conditionType] = nil
        else
            local current = matched == true
            local completedReady = trustedChargeCompletion
                and rule.conditionType == Conditions.SELF_READY
                and previous == false
            if previous == false and (matched == true or completedReady)
                and (SoundService and SoundService.Runtime and SoundService.Runtime.preferences
                    and SoundService.Runtime.preferences.enabled == true
                    or not (SoundService and SoundService.Runtime and SoundService.Runtime.preferences)
                        and YHUD.monitorSoundEnabled ~= false)
                and rule.sound
                and SoundService and SoundService.Play then
                local migrated = YHUD.LegacySoundMigration and YHUD.LegacySoundMigration:IsSuppressed(compiled, rule.conditionType)
                if not migrated then
                playResult = SoundService:Play(
                    rule.sound,
                    nil,
                    PLAY_COOLDOWN
                )
                if playResult == true and SoundService.Runtime then
                    SoundService.Runtime.lastLegacySound=rule.sound
                    SoundService.Runtime.lastLegacyAt=GetRuntimeTime()
                end
                played = playResult == true or played
                end
            end
            if trustedChargeCompletion
                and rule.conditionType == Conditions.SELF_READY then
                current = not chargeStillRecovering
            end
            observed[rule.conditionType] = current
        end
    end
    return played
end
