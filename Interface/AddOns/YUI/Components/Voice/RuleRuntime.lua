local _, YUI = ...
YUI = _G.YUI or YUI
if not (YUI and YUI.Sound and YUI.Sound.RuleModel) then return end
local Model=YUI.Sound.RuleModel
local Runtime={}
Runtime.__index=Runtime
YUI.Sound.RuleRuntime=Runtime
local function IsReady(binding)
    return binding.rule.trigger.event=='ready' or binding.rule.trigger.event=='charge'
        and binding.sourceType=='spell-cooldown'
end
local function EffectiveSpellID(object)
    local id=object.id
    local editor=YUI.Sound.EditorModel
    if editor and editor.CanonicalSpellID then id=editor:CanonicalSpellID(id,editor:CurrentSpec()) end
    local api=YUI.API and YUI.API.Spell
    return api and api.GetEffectiveSpellID and api.GetEffectiveSpellID(id) or id
end

-- Temporary, opt-in timing capture. Owned listener/deadline; no saved variables.
local Timing={enabled=false}
YUI.Sound.DebugTiming=Timing
local timingHooks=setmetatable({},{__mode='k'})
local timingProbes={}
local function TimingPublic(value)
    if type(issecretvalue)=='function' and issecretvalue(value) then return nil end
    return value
end
local function TimingFrameSpell(frame)
    if type(frame.GetSpellID)~='function' then return nil end
    local ok,id=pcall(frame.GetSpellID,frame)
    if ok then
        id=TimingPublic(id)
        if type(id)=='number' then return id end
    end
end
local function TimingAvailable(frame)
    if not Timing.enabled then return end
    local id=TimingFrameSpell(frame)
    if Timing:Watches(id) then Timing:Record('native-available',id) end
end
local function TimingProbeDone(frame)
    if Timing:Watches(frame.timingSpellID) and not frame.timingSetting then
        Timing:Record('probe-done',frame.timingSpellID)
    end
end
function Timing:SampleCooldowns()
    if not self.enabled then return end
    local api=C_Spell
    if not (api and type(api.GetSpellCooldown)=='function') then return end
    for id,probe in pairs(self.cooldownProbes or {}) do
        if not self.enabled then break end
        local ok,info=pcall(api.GetSpellCooldown,id)
        info=ok and TimingPublic(info) or nil
        local active,gcd
        if type(info)=='table' and not (issecrettable and issecrettable(info)) then
            active,gcd=info.isActive,info.isOnGCD
        end
        -- Deliberately no fallback: prove that the ignoreGCD=true call itself works.
        local durationOK,duration=false,nil
        if type(api.GetSpellCooldownDuration)=='function' then
            durationOK,duration=pcall(api.GetSpellCooldownDuration,id,true)
        end
        local setOK,shownOK,shown=false,false,nil
        if durationOK and TimingPublic(duration)~=nil then
            probe.timingSetting=true
            setOK=pcall(probe.SetCooldownFromDurationObject,probe,duration,true)
            probe.timingSetting=false
            if setOK then shownOK,shown=pcall(probe.IsShown,probe) end
        end
        self:Record('api-ready-probe',id,active,gcd,durationOK,setOK,shownOK,shown)
    end
end
function Timing:StartCooldownDiagnostics()
    if not YUI.IsRetail then return end
    self.cooldownProbes={}
    local count=0
    local engine=YUI.Sound.Runtime and YUI.Sound.Runtime.engine
    for _,binding in ipairs(engine and engine.bindings or {}) do
        local rule=binding.rule
        local id=TimingPublic(binding.spellID or rule.object.id)
        if rule.object.kind=='spell' and IsReady(binding) and type(id)=='number'
            and not self.cooldownProbes[id] and count<32 and CreateFrame and UIParent then
            count=count+1
            local probe=timingProbes[count]
            if not probe then
                probe=CreateFrame('Cooldown',nil,UIParent,'CooldownFrameTemplate')
                probe:SetSize(1,1);probe:SetPoint('TOPLEFT',UIParent,'TOPLEFT',-8,-8)
                probe:SetAlpha(0);probe:EnableMouse(false)
                probe:SetScript('OnCooldownDone',TimingProbeDone)
                timingProbes[count]=probe
            end
            probe.timingSpellID=id
            self.cooldownProbes[id]=probe
        end
    end
    self:Record('probe-coverage',count,32)
    -- Snapshot coverage at Start. Re-run Start after changing the native viewer layout.
    for _,name in ipairs({'EssentialCooldownViewer','UtilityCooldownViewer'}) do
        local viewer=_G[name]
        local pool=viewer and viewer.itemFramePool
        local scanned,matched=0,0
        if pool and type(pool.EnumerateActive)=='function' then
            for frame in pool:EnumerateActive() do
                scanned=scanned+1
                if scanned>512 then break end
                local id=TimingFrameSpell(frame)
                if self:Watches(id) then
                    matched=matched+1
                    local supported=type(frame.TriggerAvailableAlert)=='function' and type(hooksecurefunc)=='function'
                    if supported and not timingHooks[frame] then
                        local ok=pcall(hooksecurefunc,frame,'TriggerAvailableAlert',TimingAvailable)
                        if ok then timingHooks[frame]=true end
                    end
                    self:Record('native-watch',id,name,timingHooks[frame]==true)
                end
            end
        end
        self:Record('native-coverage',name,scanned,matched)
    end
    if count>0 and YUI.Event and YUI.Event.On then
        YUI.Event:On('SPELL_UPDATE_COOLDOWN','SampleCooldowns',self)
        self:SampleCooldowns()
    end
end
local function TimingValue(value)
    if type(issecretvalue)=='function' and issecretvalue(value) then return '<secret>' end
    local kind=type(value)
    if kind=='string' then return value:gsub('[\r\n\t]',' '):sub(1,200) end
    if kind=='number' or kind=='boolean' or kind=='nil' then return tostring(value) end
    return '<'..kind..'>'
end
function Timing:Start()
    self:Finish()
    self.rows={};self.identities=setmetatable({},{__mode='k'});self.serial=0
    self.samples={};self.spells={}
    self.started=GetTime();self.enabled=true;self.stopReason=nil
    self:Record('start','sound-timing-v3')
    local engine=YUI.Sound.Runtime and YUI.Sound.Runtime.engine
    for _,binding in ipairs(engine and engine.bindings or {}) do
        local rule=binding.rule
        local source=binding.handle and binding.handle.source
        if rule.object.kind=='spell' then
            self.spells[rule.object.id]=true
            if binding.spellID then self.spells[binding.spellID]=true end
            if source and source.params and source.params.chargeSpellID then self.spells[source.params.chargeSpellID]=true end
        end
        self:Record('binding',self:Identity(binding),rule.id,rule.object.id,rule.trigger.event,
            source and source.key,binding.fallbackRequired,binding.directAuraID,binding.issue)
        self:Record('binding-sound',self:Identity(binding),rule.sound.kind,rule.sound.value)
        local state=source and source.state
        if state then self:Record('binding-state',self:Identity(binding),state.sequence,state.present,state.nativeEvent,state.generation) end
    end
    self:StartCooldownDiagnostics()
    if not self.enabled then return end
    if YUI.Event and YUI.Event.On then YUI.Event:On('UNIT_SPELLCAST_SUCCEEDED','OnCast',self,{unit='player'}) end
    if YUI.Monitor and YUI.Monitor.ScheduleTask then
        local ok=YUI.Monitor:ScheduleTask(self,'debug-timing-stop',GetTime()+600,Timing.Timeout)
        if not ok then self:Finish('capture-schedule-failed') end
    end
end
function Timing:Finish(reason)
    self.enabled=false
    for _,probe in pairs(self.cooldownProbes or {}) do
        probe.timingSpellID=nil
        if probe.Clear then probe:Clear() end
        probe:Hide()
    end
    self.cooldownProbes=nil
    if reason then self.stopReason=reason end
    if YUI.Event and YUI.Event.OffOwner then YUI.Event:OffOwner(self) end
    if YUI.Monitor and YUI.Monitor.CancelTasks then YUI.Monitor:CancelTasks(self) end
end
function Timing:Timeout() self:Finish('capture-limit') end
function Timing:Watches(spellID)
    if not self.enabled or type(issecretvalue)=='function' and issecretvalue(spellID) then return false end
    return self.spells and self.spells[spellID]==true
end
function Timing:OnCast(_,unit,_,spellID)
    if self:Watches(spellID) then self:Record('cast-success',spellID,unit) end
end
function Timing:Identity(object)
    if not object then return nil end
    local id=self.identities[object]
    if not id then self.serial=self.serial+1;id=self.serial;self.identities[object]=id end
    return id
end
function Timing:Record(stage,...)
    if not self.enabled then return end
    if GetTime()-self.started>=600 or #self.rows>=1200 then
        self:Finish('capture-limit');return
    end
    local fields={string.format('%.3f',GetTime()-self.started),stage}
    for index=1,select('#',...) do fields[#fields+1]=TimingValue(select(index,...)) end
    if stage=='ready-observe' or stage=='ready-mode' or stage:sub(1,4)=='api-' then
        local key=stage..':'..fields[3]
        local sample=table.concat(fields,'\t',3)
        if self.samples[key]==sample then return end
        self.samples[key]=sample
    end
    self.rows[#self.rows+1]=table.concat(fields,'\t')
end
function Timing:Stop() self:Record('stop');self:Finish() end
function Timing:Export()
    self:Stop()
    local value='YUI sound-timing-v3 (seconds; capture limited to 600s / 1200 rows; '..(self.stopReason or 'manual-stop')..')\n'..table.concat(self.rows or {},'\n')
    if YUI.Settings and YUI.Settings.ShowCopyPopup then
        YUI.Settings:ShowCopyPopup('YUI Sound Timing',value,{multiline=true})
    end
    return value
end
local function TraceBinding(stage,binding,a,b,c,d)
    if not Timing.enabled then return end
    local rule=binding.rule
    Timing:Record(stage,Timing:Identity(binding),rule.id,rule.object.id,rule.trigger.event,a,b,c,d)
end

local function Public(value)
    if type(issecretvalue)=='function' and issecretvalue(value) then return nil end
    return value
end

local function Number(value)
    value=Public(value)
    if type(value)=='number' and value==value and value~=math.huge and value~=-math.huge then return value end
end

local function Selected(rule,context)
    if rule.enabled==false then return false,'disabled' end
    if rule.specs then
        local found=false
        for _,spec in ipairs(rule.specs) do if context.spec==spec then found=true; break end end
        if not found then return false,'specialization-mismatch' end
    else
        for _,spec in ipairs(rule.exceptSpecs or {}) do if spec==context.spec then return false,'specialization-excluded' end end
    end
    for id,expected in pairs(rule.talents or {}) do
        local actual=context.talents and context.talents[id]
        if actual~=expected then return false,actual==nil and 'talent-unknown' or 'talent-mismatch',id end
    end
    return true
end
Runtime.IsSelected=Selected

function Runtime.New(monitor,resolver,play,context)
    return setmetatable({monitor=monitor,resolver=resolver,play=play,context=context,
        bindings={},enabled=true,stats={observations=0,triggered=0,unknown=0},issues={}},Runtime)
end

local function DelayedCast(binding)
    binding.pendingCast=nil
    local runtime = binding.runtime
    if binding.active and runtime.enabled then
        runtime.stats.triggered = runtime.stats.triggered + 1
        runtime.play(binding.rule, binding)
    end
end

local function AuraDeadline(binding)
    binding.auraWakeAt = nil
    if binding.active and binding.handle then
        binding.runtime.monitor:RefreshSourceNow(binding.handle.source, 'aura-threshold', true)
    end
end

local function TimerRemaining(binding,key)
    if not binding.active or not binding.runtime.enabled then return end
    local source=binding.handle and binding.handle.source
    local timer=source and source.timers and source.timers[key]
    if not timer or GetTime()>timer.endsAt then return end
    binding.runtime.stats.triggered=binding.runtime.stats.triggered+1
    binding.runtime.play(binding.rule,binding)
end

local function ObserveTimer(binding,state)
    local self,rule=binding.runtime,binding.rule
    local sequence=Number(state.sequence)
    if not sequence or sequence==binding.previous then return end
    binding.previous=sequence
    if state.phase=='reset' then self.monitor:CancelTasks(binding); return end
    if state.phase=='started' and rule.trigger.policy=='restart' then self.monitor:CancelTasks(binding) end
    if not self.enabled then return end
    local fire=state.phase=='started' and rule.trigger.event=='timerStarted'
        or state.phase=='ended' and rule.trigger.event=='timerEnded'
        or state.phase=='ended' and rule.trigger.event=='timerRemaining' and rule.trigger.value==0
    if state.phase=='started' and rule.trigger.event=='timerRemaining' then
        local at=Number(state.endsAt)
        if at then
            local ok,code=self.monitor:ScheduleTask(binding,state.timerID,at-rule.trigger.value,TimerRemaining)
            if not ok then binding.issue=code end
        end
    elseif fire then
        self.stats.triggered=self.stats.triggered+1
        self.play(rule,binding)
    end
end

local function CancelAuraLoss(binding)
    if binding.lossSequence then binding.runtime.monitor:CancelTask(binding,'aura-loss-confirm') end
    binding.lossSequence=nil
end
local function NativeMemberPresence(binding,state)
    if Public(state.issue)~=nil then return end
    local members=state.nativeMemberStates
    local member=members and members[binding.nativeAuraID]
    local present=member and Public(member.present)
    if type(present)=='boolean' then return present end
end
local function ConfirmAuraLoss(binding)
    local sequence=binding.lossSequence
    binding.lossSequence=nil
    local source=binding.handle and binding.handle.source
    local state=source and source.state
    if not binding.active or not binding.runtime.enabled or not state
        or Number(state.sequence)~=sequence
        or Public(state.issue)~=nil then return end
    if binding.nativeAuraID then
        if NativeMemberPresence(binding,state)~=false then return end
    elseif Public(state.nativeEvent)~='auraRemoved' then return end
    TraceBinding('aura-loss-confirm',binding,sequence,binding.rule.trigger.lossDelay)
    binding.runtime.stats.triggered=binding.runtime.stats.triggered+1
    binding.runtime.play(binding.rule,binding)
end
local function ObserveNativeMember(binding,state)
    local self,rule=binding.runtime,binding.rule
    local sequence=Number(state.sequence)
    local previousSequence=binding.nativeSequence
    binding.nativeSequence=sequence
    if binding.nativeAuraUnit then
        -- The engine owns exact-member file playback. Native callbacks must not
        -- submit a second sound or require the protected member identity.
        CancelAuraLoss(binding)
        local issue=Public(state.issue)
        if binding.nativeSourceIssue~=issue then
            binding.nativeSourceIssue=issue
            if YUI.Event and YUI.Event.Emit then YUI.Event:Emit('YUI_MONITOR_SOURCE_STATUS_CHANGED',binding.sourceKey) end
        end
        binding.issue=issue or binding.auraPlaybackIssue
        return
    end
    local present=NativeMemberPresence(binding,state)
    local oldIssue=binding.issue
    binding.issue=state.nativeIdentityUnknown and 'native-aura-binding-unavailable' or nil
    if oldIssue~=binding.issue and previousSequence~=nil and sequence~=previousSequence and YUI.Event and YUI.Event.Emit then
        YUI.Event:Emit('YUI_MONITOR_SOURCE_STATUS_CHANGED',binding.sourceKey)
    end
    if present~=false then CancelAuraLoss(binding)
    elseif binding.lossSequence then binding.lossSequence=sequence end
    if not sequence or previousSequence==nil or sequence==previousSequence or present==nil or not self.enabled then return end
    if Number(state.nativeEventAuraID)~=binding.nativeAuraID then return end
    local event=Public(state.nativeEvent)
    if event~=rule.trigger.event then return end
    if event=='auraRemoved' and (rule.trigger.lossDelay or 0)>0 then
        local ok,code=self.monitor:ScheduleTask(binding,'aura-loss-confirm',GetTime()+rule.trigger.lossDelay/1000,ConfirmAuraLoss)
        if ok then binding.lossSequence=sequence else binding.issue=code end
        return
    end
    self.stats.triggered=self.stats.triggered+1
    self.play(rule,binding)
end
local function ObserveAura(binding, state)
    local self, rule = binding.runtime, binding.rule
    TraceBinding('aura-observe',binding,state.sequence,state.nativeEvent,state.present,binding.nativeSequence)
    if binding.nativeAuraID then return ObserveNativeMember(binding,state) end
    if binding.handle and binding.handle.source.sourceType and (binding.handle.source.sourceType.id == 'native-aura-signal' or binding.handle.source.sourceType.id == 'native-equipment-aura' or binding.handle.source.sourceType.id=='native-totem-signal') then
        local sequence = Number(state.sequence)
        local previous = binding.nativeSequence
        binding.nativeSequence = sequence
        if binding.lossSequence and (sequence~=binding.lossSequence or Public(state.nativeEvent)~='auraRemoved'
            or Public(state.issue)~=nil) then
            TraceBinding('aura-loss-cancel',binding,sequence,state.nativeEvent)
            CancelAuraLoss(binding)
        end
        if sequence and previous ~= nil and sequence ~= previous and state.nativeEvent == rule.trigger.event and self.enabled then
            if rule.trigger.event=='auraRemoved' and (rule.trigger.lossDelay or 0)>0 then
                local ok,code=self.monitor:ScheduleTask(binding,'aura-loss-confirm',GetTime()+rule.trigger.lossDelay/1000,ConfirmAuraLoss)
                if ok then binding.lossSequence=sequence else binding.issue=code end
                TraceBinding('aura-loss-queue',binding,sequence,rule.trigger.lossDelay,ok,code)
                return
            end
            TraceBinding('aura-trigger',binding,sequence,previous)
            self.stats.triggered = self.stats.triggered + 1
            self.play(rule, binding)
        end
        return
    end
    local event, present = rule.trigger.event, Public(state.present)
    local identity = Public(state.unitGUID)
    local value, dueAt
    if type(identity) == 'string' and type(present) == 'boolean' then
        if event == 'auraAdded' or event == 'auraRemoved' then value = present
        elseif event=='auraStackUp' or event=='auraStackDown' then
            value=present and Number(state.stacks) or nil
        elseif not present then value = false
        elseif event == 'auraStacks' then
            local count = Number(state.stacks)
            if count then
                if rule.trigger.operator == 'ge' then value = count >= rule.trigger.value
                else value = count <= rule.trigger.value end
            end
        elseif event == 'auraRemaining' then
            local ending = Number(state.expirationTime)
            if ending and ending > 0 then
                local now = GetTime()
                value = ending > now and ending - now <= rule.trigger.value
                if ending - rule.trigger.value > now then dueAt = ending - rule.trigger.value end
            end
        end
    end
    if binding.auraWakeAt ~= dueAt then
        binding.auraWakeAt = dueAt
        if dueAt and self.enabled then
            local ok, code = self.monitor:ScheduleTask(binding, 'aura-threshold', dueAt, AuraDeadline)
            if not ok then binding.auraWakeAt, binding.issue = nil, code end
        else self.monitor:CancelTask(binding, 'aura-threshold') end
    end
    local previous = binding.previous
    local fire = binding.identity == identity and previous ~= nil and value ~= nil
        and (event=='auraStackUp' and value>previous or event=='auraStackDown' and value<previous
            or event == 'auraRemoved' and previous == true and value == false
            or event ~= 'auraRemoved' and previous == false and value == true)
    binding.identity, binding.previous = identity, value
    if fire and self.enabled then
        self.stats.triggered = self.stats.triggered + 1
        self.play(rule, binding)
    end
end

local function CompletionState(binding)
    local api=YUI.API and YUI.API.Spell
    local handle=binding.completionHandle
    if not (api and handle) then return nil end
    local getter=binding.completionMode=='charge' and api.GetChargeDurationObject or api.GetCooldownDurationObject
    local duration=getter and getter(binding.spellID or binding.rule.object.id,true)
    if not duration then return nil end
    local active,resolved=api.ArmCooldownCompletion(handle,duration)
    if resolved==true then return active end
end

local function CancelReady(binding)
    if binding.readyPending then binding.runtime.monitor:CancelTask(binding,'ready-confirm') end
    binding.readyPending=nil
end

local function ConfirmReady(binding)
    binding.readyPending=nil
    local runtime=binding.runtime
    if not binding.active or not runtime.enabled or binding.previous~=true then return end
    local api=YUI.API and YUI.API.Spell
    local id=binding.spellID or binding.rule.object.id
    if EffectiveSpellID(binding.rule.object)~=id then
        binding.previous=nil; return
    end
    local reader=api and (binding.readyHasCharges and api.ReadChargeRuleState or api.ReadCooldownRuleState)
    local active,resolved
    if reader then active,resolved=reader(id) end
    TraceBinding('ready-confirm',binding,active,resolved,binding.previous,id)
    if resolved~=true or type(active)~='boolean' then
        -- An inconclusive recheck must not forget the verified running
        -- cooldown. A later event/completion can retry without polling.
        runtime.stats.unknown=runtime.stats.unknown+1;return
    end
    -- The widget is only a wake-up signal. A fresh public running cooldown
    -- vetoes a cleared duration object, including temporary free casts.
    if active then CompletionState(binding);return end
    if not binding.readyHasCharges then
        local casting,castResolved
        if api.ReadPlayerCastRuleState then casting,castResolved=api.ReadPlayerCastRuleState(id) end
        TraceBinding('ready-cast',binding,casting,castResolved)
        if castResolved~=true then runtime.stats.unknown=runtime.stats.unknown+1;return end
        if casting then return end
    end
    local fallbackAt=binding.readyFallbackAt
    binding.readyFallbackAt=nil
    binding.previous=false
    if fallbackAt and GetTime()-fallbackAt<1.6 then
        TraceBinding('ready-short-filter',binding,GetTime()-fallbackAt)
        return
    end
    TraceBinding('ready-trigger',binding)
    runtime.stats.triggered=runtime.stats.triggered+1
    runtime.play(binding.rule,binding)
end

local function QueueReady(binding)
    if not binding.active or not binding.runtime.enabled or binding.previous~=true or binding.readyPending then return end
    -- GetTime is frame-stable. An epsilon keeps a scheduler flush in this
    -- frame from consuming the candidate; the next frame performs one read.
    local ok,code=binding.runtime.monitor:ScheduleTask(binding,'ready-confirm',GetTime()+0.000001,ConfirmReady)
    TraceBinding('ready-queue',binding,ok,code,binding.previous)
    if ok then binding.readyPending=true else binding.issue=code end
end

local function CooldownCompleted(binding)
    if not binding.active or CompletionState(binding)~=false then return end
    if YUI.IsRetail and binding.rule.object.kind=='spell' then QueueReady(binding);return end
    local wasActive=binding.previous==true
    binding.previous=false
    if wasActive and binding.runtime.enabled then
        binding.runtime.stats.triggered=binding.runtime.stats.triggered+1
        binding.runtime.play(binding.rule,binding)
    end
end

local function Observe(binding,state)
    local self=binding.runtime
    if not binding.active then return end
    self.stats.observations=self.stats.observations+1
    local rule=binding.rule
    local completionActive
    if rule.object.kind=='spell' and IsReady(binding) then
        local api=YUI.API and YUI.API.Spell
        local mode=Public(state.hasCharges)==true and 'charge' or 'cooldown'
        if api and api.AcquireCooldownCompletion and api.ArmCooldownCompletion and api.ReleaseCooldownCompletion then
            if binding.completionHandle and binding.completionMode~=mode then
                api.ReleaseCooldownCompletion(binding.completionHandle);binding.completionHandle=nil
            end
            if not binding.completionHandle then
                binding.completionHandle=api.AcquireCooldownCompletion(binding,binding.spellID or rule.object.id,mode,CooldownCompleted)
                binding.completionMode=mode
            end
            completionActive=CompletionState(binding)
        end
    end
    if binding.handle and binding.handle.source and binding.handle.source.sourceType and binding.handle.source.sourceType.id=='native-charge-signal' then
        local sequence=Number(state.sequence)
        TraceBinding('charge-observe',binding,sequence,binding.nativeSequence)
        local previous=binding.nativeSequence; binding.nativeSequence=sequence
        if sequence and previous~=nil and sequence~=previous and self.enabled then
            TraceBinding('charge-trigger',binding,sequence,previous)
            self.stats.triggered=self.stats.triggered+1; self.play(rule,binding)
        end
        return
    end
    if rule.trigger.extension=='bone-shield' then
        local sequence=Number(state.stackSequence)
        local previous=binding.stackSequence;binding.stackSequence=sequence
        if sequence and previous~=nil and sequence~=previous and self.enabled then
            self.stats.triggered=self.stats.triggered+1;self.play(rule,binding,'stacks')
        end
    end
    if rule.trigger.extension=='boiling-point' then
        local manual,ending=Number(state.manualSequence),Number(state.endSequence)
        local oldManual,oldEnding=binding.manualSequence,binding.endSequence
        local sequence,previous=Number(state.sequence),binding.previous
        binding.previous=sequence
        binding.manualSequence,binding.endSequence=manual,ending
        if not self.enabled or state.phase=='reset' then binding.windowArmed=nil;return end
        if manual and oldManual~=nil and manual~=oldManual then
            self.stats.triggered=self.stats.triggered+1;self.play(rule,binding,'manual')
        end
        if ending and oldEnding~=nil and ending~=oldEnding and binding.windowArmed then
            self.stats.triggered=self.stats.triggered+1;self.play(rule,binding)
        end
        if not state.available then binding.windowArmed=nil
        elseif sequence and previous~=nil and sequence~=previous then binding.windowArmed=true end
        return
    end
    if rule.trigger.extension=='bone-shield' then
        local sequence=Number(state.sequence)
        local previous=binding.previous;binding.previous=sequence
        if not self.enabled or state.phase=='reset' then binding.windowArmed=nil;return end
        if sequence and previous~=nil and sequence~=previous then
            local fire=state.phase=='ended' and binding.windowArmed
            binding.windowArmed=state.phase=='started' or nil
            if fire then self.stats.triggered=self.stats.triggered+1;self.play(rule,binding) end
        end
        return
    end
    if rule.trigger.duration then ObserveTimer(binding,state); return end
    if rule.object.kind=='aura' or rule.object.kind=='equipmentAura' or rule.object.kind=='totem' then ObserveAura(binding,state); return end
    if rule.trigger.event=='cast' or rule.trigger.event=='castAfter' then
        local sequence, at=Number(state.sequence),Number(state.castAt)
        if not sequence or sequence<=0 or not at or sequence==binding.previous then return end
        binding.previous=sequence
        if not self.enabled then return end
        if rule.trigger.extension then
            binding.targetAt=Number(state.targetAt)
            self.stats.triggered=self.stats.triggered+1
            self.play(rule,binding)
        elseif rule.trigger.event=='cast' or rule.trigger.value==0 then
            self.stats.triggered=self.stats.triggered+1
            self.play(rule,binding)
        elseif not binding.pendingCast then
            local ok,code=self.monitor:ScheduleTask(binding,'cast-delay',at+rule.trigger.value,DelayedCast)
            if not ok then binding.issue=code else binding.pendingCast=true end
        end
        return
    end
    if Public(state.secret)==true or Public(state.available)~=true then
        binding.readyStartSequence=Number(state.readyStartSequence) or 0
        binding.previous=nil; self.stats.unknown=self.stats.unknown+1; return
    end
    local value,fire
    if IsReady(binding) or rule.trigger.event=='cooldownStarted' then
        if Public(state.hasCharges)==true and Public(state.chargeReadResolved)==false
            or Public(state.hasCharges)~=true and Public(state.cooldownReadResolved)==false then
            binding.readyStartSequence=Number(state.readyStartSequence) or 0
            binding.previous=nil; self.stats.unknown=self.stats.unknown+1; return
        end
        if Public(state.cooldownStateSecret)==true or Public(state.chargeStateSecret)==true then
            binding.readyStartSequence=Number(state.readyStartSequence) or 0
            binding.previous=nil; self.stats.unknown=self.stats.unknown+1; return
        end
        if Public(state.hasCharges)==true then value=Public(state.chargeActive)
        else value=Public(state.cooldownActive) end
        if rule.object.kind=='slot' then
            local start,duration=Number(state.startTime),Number(state.duration)
            local enabled=Public(state.isEnabled)
            if not start or not duration or enabled==false or enabled==0 or enabled==nil then
                binding.previous=nil; return
            end
            local now=GetTime()
            value=duration>0 and start+duration>now
            if binding.identity~=Number(state.itemID) then binding.slotCooldownEnd=nil end
            if value then
                local spell=YUI.API and YUI.API.Spell
                local gcd=spell and spell.GetCooldown and spell.GetCooldown(61304)
                local gcdStart=gcd and Number(gcd.startTime)
                local gcdDuration=gcd and Number(gcd.duration)
                if gcdStart and gcdDuration then
                    local gcdOnly=gcdDuration>0 and math.abs(start-gcdStart)<0.001
                        and math.abs(duration-gcdDuration)<0.001
                    if gcdOnly then
                        -- A transient GCD cannot arm ready, or end a known longer cooldown early.
                        value=binding.slotCooldownEnd~=nil and binding.slotCooldownEnd>now
                    else binding.slotCooldownEnd=start+duration end
                elseif duration<=2 then
                    -- Unreadable GCD metadata is not evidence of a real short cooldown.
                    binding.previous=nil; return
                else binding.slotCooldownEnd=start+duration end
            else binding.slotCooldownEnd=nil end
        end
        if type(value)~='boolean' then binding.previous=nil; return end
        if YUI.IsRetail and rule.object.kind=='spell' and IsReady(binding) then
            TraceBinding('ready-mode',binding,state.hasCharges,state.maxCharges,state.castCount,state.chargeActive,state.cooldownGCDResolved)
            TraceBinding('ready-observe',binding,value,completionActive,binding.previous,state.spellID)
            local identity=Number(state.spellID)
            local charges=Public(state.hasCharges)==true
            local sequence=Number(state.readyStartSequence) or 0
            local captured=sequence~=binding.readyStartSequence
                and Number(state.readyStartSpellID)==identity
            binding.readyStartSequence=sequence
            local unverifiedStart=not charges and value==true and Public(state.cooldownGCDResolved)==false
            local newCycle=binding.identity~=identity or binding.readyHasCharges~=charges or binding.previous~=true
            if newCycle then
                binding.readyFallbackAt=nil
            end
            if captured or charges or (value==true and Public(state.cooldownGCDResolved)==true) then
                -- Explicit evidence upgrades this cycle; do not filter known short cooldowns.
                binding.readyFallbackAt=nil
            elseif unverifiedStart and completionActive==true then
                -- The ignore-GCD native timer supplies a fallback start. Only newly
                -- armed cycles need the 1.6s filter; preserve an already verified cycle.
                if newCycle then binding.readyFallbackAt=GetTime() end
            end
            if unverifiedStart and completionActive==true then unverifiedStart=false end
            if binding.identity~=identity or binding.readyHasCharges~=charges then
                CancelReady(binding)
                binding.identity,binding.readyHasCharges,binding.previous=identity,charges,value
                if unverifiedStart then binding.previous=nil end
                if completionActive==false then binding.previous=false end
                if not captured or charges then return end
            end
            if captured and not charges then
                if binding.previous~=true then TraceBinding('ready-start-captured',binding,sequence,identity) end
                binding.previous=true
            end
            -- Missing metadata without a running native timer cannot establish a start.
            if unverifiedStart then return end
            if binding.previous==true and (value==false or completionActive==false) then
                QueueReady(binding)
            elseif value==true and completionActive==false then
                -- Expiry does not necessarily update the shared snapshot.
                -- A stale running flag cannot rearm an already completed cycle.
                return
            else binding.previous=value end
            return
        end
        if completionActive~=nil then value=completionActive end
        if IsReady(binding) then fire=binding.previous==true and value==false
        else fire=binding.previous==false and value==true end
    elseif rule.trigger.event=='charge' then
        if Public(state.chargeReadResolved)==false then binding.previous=nil; return end
        if Public(state.chargeCountSecret)==true then binding.previous=nil; return end
        value=Number(state.currentCharges)
        if not value then binding.previous=nil; return end
        fire=binding.previous~=nil and value>binding.previous
    else
        return
    end
    -- New identities are baselines, never fabricated ready/charge edges.
    local identity=Number(state.itemID) or Number(state.spellID)
    if Number(state.groupIdentity) then identity=state.groupIdentity end
    if binding.identity~=identity then fire=false end
    binding.identity,binding.previous=identity,value
    if fire and self.enabled then
        self.stats.triggered=self.stats.triggered+1
        self.play(rule,binding)
    end
end

-- Cold, normalized rule/source comparison; never compare live source state.
local function SameValue(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for key,value in pairs(a) do if not SameValue(value,b[key]) then return false end end
    for key in pairs(b) do if a[key]==nil then return false end end
    return true
end

local function ReleaseBinding(self,binding)
    binding.active=false
    if binding.readyCaptureSource then
        local source=binding.readyCaptureSource
        if binding.readyCaptureEnabled then source.readyConsumers=math.max(0,(source.readyConsumers or 1)-1) end
        binding.readyCaptureSource=nil
    end
    binding.readyPending=nil
    binding.readyFallbackAt=nil
    if binding.completionHandle then
        YUI.API.Spell.ReleaseCooldownCompletion(binding.completionHandle)
        binding.completionHandle=nil
    end
    self.monitor:ReleaseSource(binding.handle)
    self.monitor:CancelTasks(binding)
end

function Runtime:Apply(rules,preserveBindings)
    local normalized,code=Model:NormalizeLibrary(rules)
    if not normalized then return nil,code end
    local staged,issues,acquiredBindings,retained,candidates={},{},{},{},{}
    if preserveBindings then
        for _,binding in ipairs(self.bindings) do
            local rule=binding.rule
            local event=rule.trigger.event
            local spell=rule.object.kind=='spell'
                and (event=='cast' or event=='castAfter' or event=='ready'
                    or event=='charge' or event=='cooldownStarted')
            local nativeAura=rule.object.kind=='aura' and binding.sourceType=='native-aura-signal'
                and binding.nativeAuraUnit=='player' and (event=='auraAdded' or event=='auraRemoved')
                and binding.handle and binding.handle.active
                and self.monitor.Data.sources[binding.sourceKey]==binding.handle.source
            if binding.active and (spell or nativeAura) then
                candidates[Model:Key(rule)]=binding
            end
        end
    end
    for _,rule in ipairs(normalized) do
        if Selected(rule,self.context()) then
            local old=candidates[Model:Key(rule)]
            if old and not SameValue(old.rule,rule) then old=nil end
            local resolved,source,reason=pcall(self.resolver,rule,old)
            if not resolved then
                for _,old in ipairs(acquiredBindings) do self.monitor:ReleaseSource(old.handle) end
                return nil,'source-resolution-failed'
            end
            if not source then issues[#issues+1]={key=Model:Key(rule),reason=reason or 'unsupported-condition'}
            else
                if old and not retained[old] and SameValue(old.rule,rule)
                    and old.sourceKey==source.key and old.sourceType==source.type
                    and SameValue(old.sourceParams,source.params)
                    and old.nativeAuraID==source.nativeAuraID and old.nativeAuraUnit==source.nativeAuraUnit then
                    retained[old]=true;staged[#staged+1]=old
                else
                    local binding={runtime=self,rule=rule,active=false,spellID=source.params and source.params.spellID,
                        sourceKey=source.key,sourceType=source.type,sourceParams=source.params,
                        nativeAuraID=source.nativeAuraID,nativeAuraUnit=source.nativeAuraUnit}
                    local acquired,handle,why=pcall(self.monitor.AcquireSource,self.monitor,binding,source.key,source.type,source.params,Observe)
                    if not acquired or not handle then
                        for _,old in ipairs(acquiredBindings) do self.monitor:ReleaseSource(old.handle) end
                        return nil,acquired and why or 'source-acquisition-failed'
                    end
                    binding.handle=handle; staged[#staged+1]=binding
                    acquiredBindings[#acquiredBindings+1]=binding
                end
            end
        end
    end
    for _,binding in ipairs(self.bindings) do
        if not retained[binding] then ReleaseBinding(self,binding) end
    end
    self.rules,self.bindings,self.issues=normalized,staged,issues
    for _,binding in ipairs(acquiredBindings) do
        binding.active=true
        -- Acquiring an initialized shared source may produce no change on its
        -- next read. Capture its current public state as a silent baseline.
        local source=binding.handle.source
        if YUI.IsRetail and source and binding.rule.object.kind=='spell' and IsReady(binding) then
            binding.readyCaptureEnabled=self.enabled
            if self.enabled then source.readyConsumers=(source.readyConsumers or 0)+1 end
            binding.readyCaptureSource=source
            binding.readyStartSequence=Number(source.state.readyStartSequence) or 0
        end
        if source and source.sourceType and (source.sourceType.id == 'native-aura-signal' or source.sourceType.id=='native-charge-signal') then
            binding.nativeSequence = Number(source.state.sequence)
        end
        if source and binding.rule.trigger.extension=='bone-shield' then binding.stackSequence=Number(source.state.stackSequence) end
        if source and binding.rule.trigger.extension=='boiling-point' then
            binding.manualSequence=Number(source.state.manualSequence)
            binding.endSequence=Number(source.state.endSequence)
        end
        if source and (binding.rule.trigger.extension=='boiling-point' or binding.rule.trigger.extension=='bone-shield') then binding.previous=Number(source.state.sequence) end
        if binding.nativeAuraUnit then
            binding.nativeSourceIssue=Public(source and source.state.issue)
        end
        if source and source.initialized then
            if binding.rule.trigger.duration or binding.rule.trigger.event=='cast' or binding.rule.trigger.event=='castAfter' then
                binding.previous=Number(source.state.sequence)
            end
            Observe(binding,source.state)
        end
    end
    return true,nil,retained
end

function Runtime:Stop(affected)
    local retained={}
    for _,binding in ipairs(self.bindings) do
        if not affected or affected[binding] then ReleaseBinding(self,binding)
        else retained[#retained+1]=binding end
    end
    self.bindings=retained
end

function Runtime:SetEnabled(enabled)
    self.enabled=enabled==true
    for _,binding in ipairs(self.bindings) do
        local source=binding.readyCaptureSource
        if source then
            if binding.readyCaptureEnabled~=self.enabled then
                source.readyConsumers=math.max(0,(source.readyConsumers or 0)+(self.enabled and 1 or -1))
                binding.readyCaptureEnabled=self.enabled
                binding.readyStartSequence=Number(source.state.readyStartSequence) or 0
            end
        end
    end
    if not self.enabled then
        for _,binding in ipairs(self.bindings) do
            self.monitor:CancelTasks(binding)
            binding.readyPending=nil
            binding.readyFallbackAt=nil
            if binding.readyCaptureSource then
                binding.readyStartSequence=Number(binding.readyCaptureSource.state.readyStartSequence) or 0
            end
            binding.lossSequence=nil
            if YUI.IsRetail and binding.rule.object.kind=='spell' and IsReady(binding) then binding.previous=nil end
            binding.auraWakeAt=nil
            binding.pendingCast=nil
            binding.windowArmed=nil
        end
    else
        for _,binding in ipairs(self.bindings) do
            if (binding.rule.object.kind=='aura' or binding.rule.object.kind=='equipmentAura' or binding.rule.object.kind=='totem') and binding.handle.source.initialized then
                ObserveAura(binding,binding.handle.source.state)
            end
        end
    end
end

local function ChargeCapability(id,previous)
    local api=YUI.API and YUI.API.Spell
    local current=api and api.GetChargeCapability and api.GetChargeCapability(id)
    if current~=nil then return current end
    -- An unchanged live binding retains confirmed capacity during restricted reads.
    if previous and previous.spellID==id then
        if previous.sourceType=='spell-cooldown' then return previous.sourceParams.hasCharges end
        if previous.sourceType=='native-charge-signal' then return true end
    end
end

function Runtime.ResolveCommon(rule,previous)
    local o,event=rule.object,rule.trigger.event
    if rule.trigger.extension=='bone-shield' then
        local common=YUI.Monitor and YUI.Monitor.CommonSources
        if not (common and common.DescribeBoneShield) then return nil,'source-unavailable' end
        return common:DescribeBoneShield(rule.trigger.value)
    end
    if rule.trigger.extension=='boiling-point' then
        local common=YUI.Monitor and YUI.Monitor.CommonSources
        if not (common and common.DescribeBoilingPoint) then return nil,'source-unavailable' end
        return common:DescribeBoilingPoint()
    end
    if o.kind=='spell' then
        local racial=YUI.API and YUI.API.Racial
        local id=o.id
        if racial and racial.GetEntry(id) then
            id=racial.ResolveKnownSpellID(id)
            if not id then return nil,'spell-not-known' end
        end
        id=EffectiveSpellID({kind=o.kind,id=id,unit=o.unit})
        o={kind=o.kind,id=id,unit=o.unit}
    end
    local common=YUI.Monitor and YUI.Monitor.CommonSources
    if not common then return nil,'source-unavailable' end
    local racial=YUI.API and YUI.API.Racial
    if o.kind=='aura' and racial and racial.GetEntry(o.id,'aura') and not racial.ResolveKnownSpellID(o.id) then
        return nil,'spell-not-known'
    end
    if o.kind=='totem' then
        if not common.DescribeTotem then return nil,'source-unavailable' end
        return common:DescribeTotem(o.id,event)
    end
    if event=='charge' then
        local useNative=true
        if YUI.IsRetail then
            local charges=ChargeCapability(o.id,previous)
            if charges==nil then return nil,'charge-capability-unknown' end
            useNative=charges==true
        end
        if useNative then
            if not common.DescribeNativeCharge then return nil,'native-charge-unavailable' end
            return common:DescribeNativeCharge(o.id,o.unit)
        end
    end
    if rule.trigger.duration then
        if o.kind=='spellGroup' and not YUI.IsRetail then return nil,'source-unavailable' end
        if not common.RegisterCastTimerSourceType then return nil,'source-unavailable' end
        local ok,code=common:RegisterCastTimerSourceType(); if not ok then return nil,code end
        if o.kind=='spellGroup' then
            local source=common:DescribeCastTimer(1236616,o.unit,rule.trigger.duration,rule.trigger.policy)
            source.key='cast-timer-group:'..o.unit..':'..o.id
            source.params.spellIDs={[1236616]=true,[1236994]=true,[1295132]=true,[1236998]=true,[1238443]=true,[1295015]=true}
            return source
        end
        return common:DescribeCastTimer(o.id,o.unit,rule.trigger.duration,rule.trigger.policy)
    end
    if o.kind=='equipmentAura' then
        if not common.DescribeEquipmentAura then return nil,'source-unavailable' end
        return common:DescribeEquipmentAura(o.id,event)
    end
    if o.kind=='aura' then
        if common.DescribeNativeAuraSignal then
            local signal = common:DescribeNativeAuraSignal(o.id, 'cdm', event)
            if signal then return signal end
        end
        return nil,'native-aura-binding-unavailable'
    end
    if o.kind=='spell' and (event=='cast' or event=='castAfter') then
        if rule.trigger.extension then
            if not common.RegisterCastPredictionSourceType then return nil,'source-unavailable' end
            local typeID,code=common:RegisterCastPredictionSourceType(rule.trigger.extension)
            if not typeID then return nil,code end
            return {key=typeID..':'..o.unit..':'..o.id,type=typeID,
                params={spellID=o.id,unit=o.unit,extension=rule.trigger.extension}}
        end
        local ok,code=common:RegisterCastSourceType(); if not ok then return nil,code end
        return {key='cast:'..o.unit..':'..o.id,type='spell-cast',params={spellID=o.id,unit=o.unit}}
    end
    if event~='ready' and event~='charge' and event~='cooldownStarted' then return nil,'condition-not-connected' end
    if o.kind=='itemGroup' then
        if not common.GetPresetItemGroup then return nil,'source-unavailable' end
        local source,code=common:GetPresetItemGroup(o.id)
        if not source then return nil,code end
        local ok; ok,code=common:RegisterItemGroupSourceType()
        if not ok then return nil,code end
        return source
    end
    if o.kind=='spell' then
        local ok,code=common:RegisterSpellSourceType(); if not ok then return nil,code end
        local hasCharges
        local client=YUI.IsRetail and 'mainline' or YUI.IsWrath and 'wrath' or 'mists'
        for _, object in ipairs(YUI.Sound.ObjectDefinitions or {}) do
            if object.kind=='spell' and object.id==o.id and object.client==client then hasCharges=object.charges; break end
        end
        local current=ChargeCapability(o.id,previous)
        if YUI.IsRetail and current==nil then return nil,'charge-capability-unknown' end
        local editor=YUI.Sound.EditorModel
        if current==nil and editor and editor:DisplayID(rule.object)==o.id then current=editor:HasCharges(rule.object) end
        if current~=nil then hasCharges=current end
        return {key='spell:'..o.id,type='spell-cooldown',params={spellID=o.id,chargeSpellID=o.id,hasCharges=hasCharges}}
    elseif o.kind=='slot' then
        local ok,code=common:RegisterSlotSourceType(); if not ok then return nil,code end
        return {key='slot:'..o.id,type='yhud.inventory-slot-cooldown',params={slotID=o.id}}
    elseif o.kind=='item' then
        local family=common.GetItemFamily and common:GetItemFamily(o.id)
        if family then
            local ok,code=common:RegisterItemGroupSourceType(); if not ok then return nil,code end
            return family
        end
        local ok,code=common:RegisterItemSourceType(); if not ok then return nil,code end
        return {key='item:'..o.id,type='item-cooldown',params={itemID=o.id}}
    end
    return nil,'source-not-connected'
end

return Runtime
