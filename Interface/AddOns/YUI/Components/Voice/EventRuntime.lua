local _, YUI = ...
YUI = _G.YUI or YUI
local S=YUI and YUI.Sound
if not (S and S.EventDefinitions) then return end
local D,A=S.EventDefinitions,YUI.API.SoundEvents
local direct={READY_CHECK='ready-check',ROLE_POLL_BEGIN='role-check',LFG_ROLE_CHECK_SHOW='role-check',
    PARTY_INVITE_REQUEST='group-invite',CONFIRM_SUMMON='summon-request'}
local R={}; R.__index=R
S.EventRuntime=R
local function Public(v) return not (issecretvalue and issecretvalue(v)) end
local function Same(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not Same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
function R.New(events,monitor,submit,cancel)
    return setmetatable({events=events,monitor=monitor,submit=submit,cancel=cancel,bindings={},issues={}},R)
end
function R:Watch(event,method,units)
    return self.events:On(event,method or 'OnEvent',self,{moduleId='sound.runtime',units=units})
end
function R:Stop()
    self.events:OffOwner(self)
    self.monitor:CancelTasks(self)
    for _,binding in pairs(self.bindings) do
        self.monitor:CancelTasks(binding); self.cancel(binding)
    end
    self.bindings={}; self.issues={}; self.signature=nil
    self.questPending=nil
    self.loading=nil
end
function R:UpdateQuests()
    self.questPending=nil
    if not self:Has('quest-complete') then return end
    local states={};A.QuestStates(states)
    for id,complete in pairs(states) do if complete and self.quests[id]==false then self:Fire('quest-complete',1) end end
    self.quests=states
end
local function UpdateQuests(owner) owner:UpdateQuests() end
function R:Has(id) return self.bindings[id]~=nil end
function R:Fire(id,window)
    local binding=self.bindings[id]
    if not binding then return end
    local now=GetTime()
    if binding.lastAt and now-binding.lastAt<(window or 2) then return end
    binding.lastAt=now;binding.serial=(binding.serial or 0)+1
    binding.playbackOK,binding.playbackIssue=self.submit(binding,'event:'..binding.serial,binding.rule.sound)
end
function R:Merge(id)
    local binding=self.bindings[id]
    if not binding or binding.pending then return end
    binding.pending=true
    self.monitor:ScheduleTask(binding,'death',GetTime()+.15,function()
        binding.pending=nil
        if self.bindings[id]==binding then self:Fire(id,.3) end
    end)
end
function R:GroupMatches(binding)
    local scope=binding.rule.trigger.params.scope
    return scope=='all' or (scope=='raid')==A.IsRaid()
end
function R:OnUnit(_,unit)
    if not Public(unit) or type(unit)~='string' or not self.unitsSet[unit] then return end
    local dead=A.Dead(unit)
    local previous=self.dead[unit]
    self.dead[unit]=dead
    if dead~=true or previous~=false or A.IsPlayer(unit) then return end
    local role=A.Role(unit)
    self.roles[unit]=role
    local specific=role=='TANK' and 'tank-dead' or role=='HEALER' and 'healer-dead'
    local binding=specific and self.bindings[specific]
    if binding and self:GroupMatches(binding) then self:Merge(specific)
    elseif self.bindings['teammate-dead'] and self:GroupMatches(self.bindings['teammate-dead']) then self:Merge('teammate-dead') end
end
function R:OnRoster()
    for _,id in ipairs({'teammate-dead','tank-dead','healer-dead'}) do
        local binding=self.bindings[id]
        if binding then self.monitor:CancelTasks(binding);binding.pending=nil;self.cancel(binding) end
    end
    if self.unitFlags then self.events:Off(self.unitFlags);self.events:Off(self.unitHealth) end
    local units={}
    for i=1,A.IsRaid() and 40 or 4 do units[#units+1]=(A.IsRaid() and 'raid' or 'party')..i end
    self.dead,self.roles,self.unitsSet={},{},{}
    for _,unit in ipairs(units) do
        self.unitsSet[unit]=true;self.dead[unit]=A.Dead(unit);self.roles[unit]=A.Role(unit)
    end
    self.unitFlags=self:Watch('UNIT_FLAGS','OnUnit',units)
    self.unitHealth=self:Watch('UNIT_HEALTH','OnUnit',units)
end
function R:OnRoles()
    for unit in pairs(self.unitsSet or {}) do self.roles[unit]=A.Role(unit) end
end
function R:Rare(key,baseline)
    local binding=self.bindings['rare-found']
    if not binding or not key then return end
    local now,last=GetTime(),self.rares[key]
    local cooldown=binding.rule.trigger.params.cooldown
    if last and (cooldown==0 or now-last<cooldown) then return end
    if not last then
        if self.rareCount>=512 then return end
        self.rareCount=self.rareCount+1
    end
    self.rares[key]=now
    if not baseline then self:Fire('rare-found',2) end
end
function R:Baseline(reason)
    self.loading=nil
    if reason then
        self.monitor:CancelTasks(self);self.questPending=nil
        for _,binding in pairs(self.bindings) do self.monitor:CancelTasks(binding);binding.pending=nil;self.cancel(binding) end
    end
    if self:Has('quest-complete') then self.quests={};A.QuestStates(self.quests) end
    -- Pending mail is temporarily unavailable while changing worlds. Keep the
    -- last observed state; restoring the same unread mail is not a new arrival.
    if self:Has('mail-received') and not reason then self.mail=A.Mail() end
    if self:Has('bags-full') then self.bags=A.BagsFull() end
    if self:Has('repair-needed') then self.repair=A.NeedsRepair(self.bindings['repair-needed'].rule.trigger.params.threshold) end
    if self:Has('queue-ready') then self.queues={};A.QueueStates(self.queues);self.proposal=false end
    if self:Has('player-dead') then self.playerDead=A.Dead('player') end
    if self:Has('teammate-dead') or self:Has('tank-dead') or self:Has('healer-dead') then self:OnRoster() end
    if self:Has('rare-found') then
        self.rares=self.rares or {};self.rareCount=self.rareCount or 0
        self:Rare(A.RareUnit('target'),true);self:Rare(A.RareUnit('mouseover'),true)
        for i=1,40 do self:Rare(A.RareUnit('nameplate'..i),true) end
        A.RareBaseline(function(key) self:Rare(key,true) end)
    end
end
function R:Apply(rules,enabled)
    local selected={}
    for _,rule in ipairs(rules) do if rule.object.kind=='event' and rule.enabled and enabled then selected[#selected+1]=rule end end
    if Same(self.signature,selected) then return true end
    self:Stop(); self.signature=selected
    self.rares,self.rareCount=self.rares or {},self.rareCount or 0
    for _,rule in ipairs(selected) do
        local id=rule.object.id
        local available,reason=D:Availability(id)
        if available then self.bindings[id]={rule=rule}
        else self.issues[#self.issues+1]={key=S.RuleModel:Key(rule),object=id,reason=reason} end
    end
    if not next(self.bindings) then return true end
    local watched={}
    local function Watch(event,method)
        if not watched[event] then watched[event]=true;self:Watch(event,method) end
    end
    local sources={
        ['quest-complete']={'QUEST_WATCH_UPDATE','QUEST_LOG_UPDATE'},
        ['mail-received']={'UPDATE_PENDING_MAIL'},['bags-full']={'BAG_UPDATE_DELAYED'},
        ['repair-needed']={'UPDATE_INVENTORY_DURABILITY'},['ready-check']={'READY_CHECK'},
        ['role-check']={'ROLE_POLL_BEGIN'},['group-invite']={'PARTY_INVITE_REQUEST'},
        ['summon-request']={'CONFIRM_SUMMON'},['player-dead']={'PLAYER_DEAD','PLAYER_ALIVE','PLAYER_UNGHOST'},
        ['queue-ready']={'UPDATE_BATTLEFIELD_STATUS'},
        ['rare-found']={'NAME_PLATE_UNIT_ADDED','PLAYER_TARGET_CHANGED','UPDATE_MOUSEOVER_UNIT'},
    }
    for id in pairs(self.bindings) do for _,event in ipairs(sources[id] or {}) do Watch(event) end end
    if self:Has('whisper-received') then Watch('CHAT_MSG_WHISPER');Watch('CHAT_MSG_BN_WHISPER') end
    if self:Has('mail-received') then Watch('PLAYER_LEAVING_WORLD') end
    if YUI.IsRetail then
        if self:Has('queue-ready') then for _,e in ipairs({'LFG_PROPOSAL_SHOW','LFG_PROPOSAL_FAILED','LFG_PROPOSAL_SUCCEEDED'}) do Watch(e) end end
        if self:Has('role-check') then Watch('LFG_ROLE_CHECK_SHOW') end
        if self:Has('rare-found') then Watch('VIGNETTE_MINIMAP_UPDATED') end
    end
    if self:Has('teammate-dead') or self:Has('tank-dead') or self:Has('healer-dead') then
        Watch('GROUP_ROSTER_UPDATE','OnRoster');Watch('PLAYER_ROLES_ASSIGNED','OnRoles')
    end
    Watch('PLAYER_ENTERING_WORLD','Baseline')
    self:Baseline()
    return true
end
function R:NotifyWhisper(event)
    local binding=self.bindings['whisper-received']
    if not binding then return false end
    local params=binding.rule.trigger.params
    if event=='CHAT_MSG_BN_WHISPER' and params.battleNet or event=='CHAT_MSG_WHISPER' and params.character then self:Fire('whisper-received',5) end
    return true
end
function R:OnEvent(event,arg,...)
    if direct[event] then self:Fire(direct[event]);return end
    if event=='CHAT_MSG_WHISPER' or event=='CHAT_MSG_BN_WHISPER' then
        local manager=YUI.WhisperManager
        if manager and manager.IsEventSoundSource and manager:IsEventSoundSource() then return end
        local hidden=select(15,...)
        if not Public(hidden) or hidden then return end
        self:NotifyWhisper(event)
    elseif event=='PLAYER_DEAD' then
        if self.playerDead==false then self.playerDead=true;self:Fire('player-dead') end
    elseif event=='PLAYER_ALIVE' or event=='PLAYER_UNGHOST' then self.playerDead=A.Dead('player')
    elseif event=='QUEST_WATCH_UPDATE' or event=='QUEST_LOG_UPDATE' then
        if not self.questPending then
            self.questPending=true
            self.monitor:ScheduleTask(self,'quests',GetTime()+.05,UpdateQuests)
        end
    elseif event=='PLAYER_LEAVING_WORLD' then self.loading=true
    elseif event=='UPDATE_PENDING_MAIL' then
        if self.loading then return end
        local value=A.Mail()
        if value==true and self.mail==false then self:Fire('mail-received') end
        if value~=nil then self.mail=value end
    elseif event=='BAG_UPDATE_DELAYED' then
        local value=A.BagsFull()
        if value==true and self.bags==false then self:Fire('bags-full') end
        if value~=nil then self.bags=value end
    elseif event=='UPDATE_INVENTORY_DURABILITY' then
        local value=A.NeedsRepair(self.bindings['repair-needed'].rule.trigger.params.threshold)
        if value==true and self.repair==false then self:Fire('repair-needed') end
        if value~=nil then self.repair=value end
    elseif event=='UPDATE_BATTLEFIELD_STATUS' then
        local states={};A.QueueStates(states)
        for id,ready in pairs(states) do if ready and self.queues[id]==false then self:Fire('queue-ready') end end
        self.queues=states
    elseif event=='LFG_PROPOSAL_SHOW' then
        if not self.proposal then self:Fire('queue-ready');self.proposal=true end
    elseif event=='LFG_PROPOSAL_FAILED' or event=='LFG_PROPOSAL_SUCCEEDED' then self.proposal=false
    elseif event=='VIGNETTE_MINIMAP_UPDATED' then self:Rare(A.RareVignette(arg,...))
    elseif event=='NAME_PLATE_UNIT_ADDED' then
        if Public(arg) and type(arg)=='string' and arg:match('^nameplate%d+$') then self:Rare(A.RareUnit(arg)) end
    elseif event=='PLAYER_TARGET_CHANGED' then self:Rare(A.RareUnit('target'))
    elseif event=='UPDATE_MOUSEOVER_UNIT' then self:Rare(A.RareUnit('mouseover')) end
end
return R
