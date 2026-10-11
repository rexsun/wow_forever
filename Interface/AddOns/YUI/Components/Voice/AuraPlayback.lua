local _, YUI = ...
YUI = _G.YUI or YUI
local S = YUI and YUI.Sound
if not S then return end
local A = {}; A.__index = A; S.AuraPlayback = A
local TASK, DELAY, RETRY_DELAY, MAX_RETRIES = 'aura-sync', 0.5, 0.1, 3

local function Same(a, b)
    return a and b and a.native == b.native and a.event == b.event and a.unit == b.unit
        and a.spellID == b.spellID and a.file == b.file and a.channel == b.channel
        and a.resourceIssue == b.resourceIssue
end

function A.New(api, monitor, event, resolve)
    return setmetatable({ api = api, monitor = monitor, event = event, resolve = resolve,
        desired = {}, registrations = {}, retries = 0 }, A)
end

function A:Listen(enabled)
    if enabled and not self.listening and self.event then
        self.event:On('PLAYER_REGEN_ENABLED', 'OnRegen', self, { moduleId = 'sound.aura-playback' })
        self.listening = true
    elseif not enabled and self.listening then
        self.event:OffOwner(self)
        self.listening = nil
    end
end

-- Bindings can be replaced without replacing their engine-owned sound handles.
function A:Publish()
    for _,wanted in pairs(self.desired) do
        if (wanted.binding.rule.trigger.extension=='boiling-point' or wanted.binding.rule.trigger.extension=='bone-shield') then wanted.binding.issue=nil end
    end
    for key, wanted in pairs(self.desired) do
        local binding, active = wanted.binding, self.registrations[key]
        local oldIssue,oldRegistered=binding.auraPlaybackIssue,binding.directAuraRegistered
        local blocked = not wanted.native or active ~= nil
        if not blocked and binding.fallbackRequired then
            local sequence = binding.handle.source.state.sequence
            if not (issecretvalue and issecretvalue(sequence)) and type(sequence) == 'number' then
                binding.nativeSequence = sequence
            end
        end
        binding.fallbackRequired = blocked or nil
        binding.directAuraID = active and active.id or nil
        local issue=wanted.resourceIssue or wanted.issue
        binding.directAuraRegistered=not wanted.native and active~=nil and Same(active,wanted) or nil
        if binding.nativeAuraUnit and not issue and not binding.directAuraRegistered then
            issue='aura-sound-registration-pending'
        end
        binding.auraPlaybackIssue=issue
        if binding.rule.trigger.extension=='boiling-point' or binding.rule.trigger.extension=='bone-shield' then binding.issue=binding.issue or issue
        else
            local state=binding.handle.source.state
            binding.issue=issue or state.issue or not binding.nativeAuraUnit and state.nativeIdentityUnknown
                and 'native-aura-binding-unavailable' or nil
        end
        if binding.nativeAuraUnit and (oldIssue~=issue or oldRegistered~=binding.directAuraRegistered)
            and self.event and self.event.Emit then
            -- Registration is output state, not a change to the monitored source.
            self.event:Emit('YUI_SOUND_BINDING_STATUS_CHANGED',binding.sourceKey)
        end
    end
end

function A:Schedule(delay)
    local ok, code = self.monitor:ScheduleTask(self, TASK, GetTime() + delay, A.Reconcile)
    self.scheduled = ok and true or nil
    if not ok then
        self.lastIssue = code
        self:Listen(true)
    end
end

function A:OnRegen()
    self.retries = 0
    self:Listen(false)
    self:Schedule(DELAY)
end

function A:Reconcile()
    self.scheduled = nil
    local failed, combatPending, removalFailed = false, false, false
    for key, active in pairs(self.registrations) do
        local wanted = self.desired[key]
        if not wanted or wanted.native or not Same(active, wanted) then
            if self.api.RemoveAura(active.id) then
                self.registrations[key] = nil
            else
                failed, removalFailed = true, true
                if wanted then wanted.issue = 'aura-sound-removal-failed' end
            end
        end
    end
    for key, wanted in pairs(self.desired) do
        if not wanted.native and wanted.file and not self.registrations[key] then
            local id, code = self.api.RegisterAura(wanted.event, wanted.unit, wanted.spellID, wanted.file, wanted.channel)
            if id ~= nil then
                self.registrations[key] = { id = id, event = wanted.event, unit = wanted.unit,
                    spellID = wanted.spellID, file = wanted.file, channel = wanted.channel, native = false }
                wanted.issue = nil
            else
                wanted.issue = code
                if code == 'aura-sound-combat-pending' then combatPending = true
                elseif code == 'aura-sound-registration-failed' then failed = true end
            end
        elseif self.registrations[key] and Same(self.registrations[key], wanted) then
            wanted.issue = nil
        elseif wanted.native and not self.registrations[key] then
            wanted.issue = nil
        end
    end
    self:Publish()
    self.lastIssue = removalFailed and 'aura-sound-removal-failed'
        or combatPending and 'aura-sound-combat-pending'
        or failed and 'aura-sound-registration-failed' or nil
    self:Listen(combatPending or failed)
    if failed and not combatPending and self.retries < MAX_RETRIES then
        self.retries = self.retries + 1
        self:Schedule(RETRY_DELAY)
    elseif not failed and not combatPending then
        self.retries = 0
    end
    return self.lastIssue == nil, self.lastIssue
end

function A:Clear()
    local changed = next(self.desired) ~= nil
    if not changed and next(self.registrations) and self.lastIssue then
        self:Listen(true)
        return nil, self.lastIssue
    end
    for _, wanted in pairs(self.desired) do
        wanted.binding.directAuraID = nil
        wanted.binding.directAuraRegistered = nil
        -- Keep retired bindings gated while cleanup is pending.
        wanted.binding.fallbackRequired = true
    end
    self.desired = {}
    if changed then self.retries = 0 end
    self.monitor:CancelTask(self, TASK)
    self.scheduled = nil
    -- Removal has no registration combat gate; mute/stop attempts cleanup now.
    return self:Reconcile()
end

function A:Sync(bindings, preferences)
    if YUI.IsRetail ~= true or not preferences.enabled then return self:Clear() end
    local desired, changed = {}, false
    for _, binding in ipairs(bindings) do
        local rule = binding.rule
        if rule.trigger.extension=='bone-shield' then
            binding.fallbackRequired=nil;binding.directAuraID=nil;binding.issue=nil
        elseif rule.trigger.extension=='boiling-point' then
            binding.fallbackRequired=nil;binding.directAuraID=nil;binding.issue=nil
        elseif rule.object.kind == 'aura' and (rule.trigger.event == 'auraAdded' or rule.trigger.event == 'auraRemoved') then
            binding.fallbackRequired = true
            local source = binding.handle.source
            self.monitor:RefreshSourceNow(source, 'aura-playback-bind', true)
            local nativeSource = source.sourceType and source.sourceType.id == 'native-aura-signal'
            local native = not not (nativeSource and not binding.nativeAuraUnit)
            local key = S.RuleModel:Key(rule)
            local wanted = { binding = binding, native = native, event = rule.trigger.event,
                unit = binding.nativeAuraUnit or rule.object.unit, spellID = binding.nativeAuraUnit and binding.nativeAuraID or nativeSource
                    and source.params and source.params.spellID or rule.object.id, channel = preferences.channel }
            if not native then
                if binding.nativeAuraUnit and source.state.issue then wanted.resourceIssue=source.state.issue
                elseif binding.nativeAuraUnit and rule.trigger.event=='auraRemoved' and (rule.trigger.lossDelay or 0)>0 then
                    wanted.resourceIssue='aura-sound-delay-unavailable'
                else
                    local resource = self.resolve(rule.sound, preferences)
                    if resource and resource.kind == 'file' then wanted.file = resource.value
                    else wanted.resourceIssue = 'aura-sound-file-required' end
                end
            end
            local previous = self.desired[key]
            if not Same(previous, wanted) then changed = true
            else wanted.issue = previous.issue end
            desired[key] = wanted
        end
    end
    for key, old in pairs(self.desired) do
        if not desired[key] then changed = true end
        if not desired[key] or desired[key].binding ~= old.binding then
            old.binding.directAuraID = nil
            old.binding.directAuraRegistered = nil
            old.binding.fallbackRequired = true
        end
    end
    self.desired = desired
    self:Publish()
    if changed then
        self.retries = 0
        self:Schedule(DELAY)
    end
end
return A
