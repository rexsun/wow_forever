local _, YUI = ...
YUI = YUI or _G.YUI
local S = YUI and YUI.Sound
local Model = S and S.RuleModel
if not Model then return end
local Migration = { VERSION = 1, providers = {} }
S.LegacyMigration = Migration
function Migration:RegisterProvider(id, provider)
    if type(id) ~= 'string' or type(provider) ~= 'table' or type(provider.Migrate) ~= 'function' then return nil, 'invalid-legacy-provider' end
    if self.providers[id] then return nil, 'legacy-provider-exists' end
    self.providers[id] = provider
    if S.Runtime and S.Runtime.active then S.Runtime:OnContextChanged() end
    return true
end
function Migration:Run(runtime)
    local applied = false
    for id, provider in pairs(self.providers) do
        local called, ok, code, changed = pcall(provider.Migrate, provider, runtime)
        if not called or ok ~= true then self.lastIssue = { provider = id, reason = called and code or ok }
        else self.lastIssue = nil end
        applied = applied or (called and ok == true and changed == true)
    end
    return applied
end
function Migration:Cancel(runtime)
    for _, provider in pairs(self.providers) do
        if provider.Cancel then provider:Cancel(runtime) end
    end
end
local function Copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}; for k, v in pairs(value) do result[k] = Copy(v) end; return result
end
local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function Applies(rule, spec)
    if rule.specs then
        for _, key in ipairs(rule.specs) do if key == spec then return true end end
        return false
    end
    for _, key in ipairs(rule.exceptSpecs or {}) do if key == spec then return false end end
    return true
end
function Migration:ResolveSound(reference, spec, client)
    if type(reference) ~= 'string' or reference == '' then return nil, 'missing-legacy-sound' end
    local kind, value = reference:match('^(%a+):(.*)$')
    if not kind then kind, value = 'voice', reference end
    if kind ~= 'voice' then
        if kind == 'custom' or kind == 'lsm' or kind == 'system' then return { kind = kind, value = value } end
        return nil, 'unsupported-legacy-sound'
    end
    local class, specID = spec:match('^([^:]+):(%d+)$')
    local match
    for id, entry in pairs(S.entries or {}) do
        if entry.names and entry.names.zhCN == value and entry.clients and entry.clients[client]
            and (not entry.class or entry.class == class) and (not entry.spec or entry.spec == tonumber(specID)) then
            if match then return nil, 'ambiguous-legacy-sound' end
            match = id
        end
    end
    if match then return { kind = 'voice', value = match } end
    return nil, 'missing-legacy-entry'
end
function Migration:Convert(record, client)
    if type(record) ~= 'table' or type(record.spec) ~= 'string' or type(record.raw) ~= 'table' then return nil, 'invalid-legacy-record' end
    if record.assigned ~= true then return nil, 'reserve-legacy-sound' end
    if record.characterMuted == true then return nil, 'muted-legacy-sound' end
    local object = record.object
    if type(object) ~= 'table' then return nil, 'unresolved-legacy-object' end
    local condition = type(record.raw.condition) == 'table' and record.raw.condition.type or record.raw.condition
    local event
    if condition == 'self-ready' then
        if object.kind == 'spell' and type(record.hasCharges) ~= 'boolean' then return nil, 'unknown-legacy-charges' end
        event = object.kind == 'spell' and record.hasCharges and 'charge' or 'ready'
    elseif condition == 'self-cooldown' then event = 'cooldownStarted'
    elseif condition == 'aura-present' then event = 'auraAdded'
    elseif condition == 'aura-missing' then event = 'auraRemoved'
    elseif condition == 'condition-met' and record.fixedTimer == true then event = 'timerStarted'
    elseif condition == 'timer-ended' and record.fixedTimer == true then event = 'timerEnded'
    else return nil, 'unsupported-legacy-condition' end
    if object.kind == 'aura' and record.independentAura ~= true then return nil, 'unverified-legacy-aura-source' end
    local sound, code = self:ResolveSound(record.raw.sound, record.spec, client)
    if not sound then return nil, code end
    local trigger = { event = event }
    if event == 'timerStarted' or event == 'timerEnded' then
        trigger.duration, trigger.policy = record.duration, 'restart'
    end
    return Model:Normalize({ object = Copy(object), trigger = trigger, specs = { record.spec },
        enabled = record.enabled ~= false, sound = sound, talents = Copy(record.talents or {}) })
end
function Migration:Prepare(records, current, client)
    if type(records) ~= 'table' or #records > 4096 then return nil, 'legacy-record-budget' end
    local existing, code = Model:NormalizeLibrary(current)
    if not existing then return nil, code end
    local result = { version = self.VERSION, rules = Copy(existing), converted = {}, recovery = {}, records = Copy(records) }
    local candidates, groups = {}, {}
    for index, record in ipairs(records) do
        local rule, why = self:Convert(record, client)
        if not rule then result.recovery[#result.recovery + 1] = { index = index, reason = why }
        else
            local key = Model:Key(rule)
            local groupKey = key .. '|' .. record.spec
            local group = groups[groupKey]
            if not group then group = { rule = rule, key = key, indices = {} }; groups[groupKey] = group; candidates[#candidates + 1] = group
            elseif not Same(group.rule, rule) then group.conflict = true end
            group.indices[#group.indices + 1] = index
        end
    end
    for _, group in ipairs(candidates) do
        local covered = false
        for _, rule in ipairs(existing) do
            if Model:Key(rule) == group.key and Applies(rule, group.rule.specs[1]) then
                if not Same(rule.sound, group.rule.sound) or rule.enabled ~= group.rule.enabled
                    or not Same(rule.talents, group.rule.talents) then group.conflict = true
                else covered = true end
            end
        end
        if group.conflict then
            for _, index in ipairs(group.indices) do result.recovery[#result.recovery + 1] = { index = index, reason = 'legacy-sound-conflict' } end
        else
            if not covered then result.rules[#result.rules + 1] = group.rule end
            for _, index in ipairs(group.indices) do result.converted[#result.converted + 1] = index end
        end
    end
    local normalized, why = Model:NormalizeLibrary(result.rules)
    if not normalized then return nil, why end
    result.rules = normalized
    return result
end
return Migration
