local _, YUI = ...
YUI = YUI or _G.YUI
local M = YUI and YUI.Monitor
local Sources = M and M.CommonSources
if not Sources or (YUI.IsRetail ~= true and YUI.IsForever ~= true) then return end
local KEY, TYPE = 'native-aura-signal:cdm:365362', 'native-aura-signal'
local generation=0
local bindings = setmetatable({}, { __mode = 'k' })
local hooked = setmetatable({}, { __mode = 'k' })
local viewers = setmetatable({}, { __mode = 'k' })
local owners = setmetatable({}, { __mode = 'k' })
local Bind
local CommitMemberLoss
local ReconcileMembers
local LOSS_TASK = 'native-aura-loss'
local function CancelLoss(source)
    source.state.lossFrame = nil
    source.state.fullUpdateLoss = nil
    source.state.nativeIdentityUnknown=nil
    source.state.nativeLastAddedID=nil
    source.state.nativeSelfMemberID=nil
    M:CancelTask(source, LOSS_TASK)
    local members=source.state.nativeMemberStates
    if members then
        for _,member in pairs(members) do
            member.present,member.lossFrame,member.auraUnit=nil,nil,nil
            member.requireAbsent=nil
            M:CancelTask(source,member.taskKey)
        end
    end
end
local viewerNames = { 'BuffIconCooldownViewer', 'BuffBarCooldownViewer' }
local directIdentityFields = { 'linkedSpellID', 'overrideSpellID', 'overrideTooltipSpellID' }
local function Public(value)
    if type(issecretvalue) == 'function' and issecretvalue(value) then return nil end
    return value
end
local function Call(method, ...)
    if type(method) ~= 'function' then return nil end
    local ok, value = pcall(method, ...)
    if ok then return Public(value) end
end
-- Only a successful, public owner read can distinguish absence from unknown.
-- Never inspect the native aura instance ID or an aura's restricted fields.
local function SelfPresence(frame)
    if type(frame.GetAuraDataUnit)~='function' then return end
    local ok,unit=pcall(frame.GetAuraDataUnit,frame)
    if not ok or type(issecretvalue)=='function' and issecretvalue(unit) then return end
    if unit=='player' then return true end
    if unit==nil then return false end
end
local function PositiveID(value)
    value=Public(value)
    if type(value)=='number' and value>0 and value<math.huge and value%1==0 then return value end
end
-- A multi-aura item is one native identity. Its display spell and members have
-- different roles; neither the base spell nor a linked spell is a second item.
function Sources:DescribeNativeAuraCatalogEntry(entry)
    if YUI.IsRetail~=true and YUI.IsForever~=true then return end
    if entry.sourceCategory~='trackedBuff' and entry.sourceCategory~='trackedBar' or entry.equipSlot then return end
    local linked=Public(entry.linkedSpellIDs)
    if type(linked)~='table' or #linked<2 or #linked>32 then return end
    local cooldownID,base=PositiveID(entry.cooldownID),PositiveID(entry.spellID)
    if not cooldownID or not base then return end
    local display=PositiveID(entry.overrideTooltipSpellID) or PositiveID(entry.overrideSpellID) or base
    local members,links,aliases={[base]=true,[display]=true},{},{}
    local override=PositiveID(entry.overrideSpellID)
    if override then members[override]=true end
    for index,id in ipairs(linked) do
        id=PositiveID(id)
        if not id or links[id] then return end
        links[id]=true;members[id]=true
    end
    local spell=YUI.API and YUI.API.Spell
    local name=spell and Call(spell.GetName,display)
    local aggregate=type(name)=='string' and name~=''
    local namesComplete=aggregate
    for id in pairs(members) do
        -- Names only select aliases inside this exact cooldownID, never identify
        -- or merge independent native items.
        local memberName=spell and Call(spell.GetName,id)
        if type(memberName)~='string' or memberName=='' then namesComplete=false end
        if name and memberName==name then aliases[#aliases+1]=id
        else aggregate=false end
    end
    table.sort(aliases)
    local catalog=YUI.IsForever and YUI.API and YUI.API.ForeverAuraIdentities
    local family=catalog and catalog.totems[cooldownID]
    local auraIDs,castIDs
    if family then
        auraIDs,castIDs={},{}
        for _,id in ipairs(family.auras) do if members[id] then auraIDs[#auraIDs+1]=id end end
        for _,id in ipairs(family.casts) do if members[id] then castIDs[id]=true end end
    end
    return {id=display,cooldownID=cooldownID,base=base,members=members,links=links,
        memberIDs=aliases,aggregate=aggregate,namesComplete=namesComplete,selfAura=Public(entry.selfAura)==true,
        recipientAuraIDs=auraIDs,castIDs=castIDs}
end
local function ActiveAuraID(frame,source)
    local aura=PositiveID(Call(frame.GetAuraSpellID,frame))
    local linked=PositiveID(Call(frame.GetLinkedSpell,frame))
    -- linkedSpellID is the native dynamic match, not overrideTooltipSpellID.
    -- Conflicting public identities indicate an intermediate native update.
    if aura and linked and aura~=linked then return end
    local id=aura or linked
    if id and source.params.nativeMembers[id] then return id end
end
local function TraceEdge(stage,source,frame)
    local trace=YUI.Sound and YUI.Sound.DebugTiming
    if not (trace and trace.enabled) then return end
    local state=source.state
    local binding=frame and bindings[frame]
    trace:Record(stage,source.params.spellID,trace:Identity(frame),
        binding and trace:Identity(binding.viewer),frame and Public(frame.cooldownID),
        state.sequence,state.present,state.lossFrame~=nil,state.generation,
        state.auraUnit,frame and Call(frame.GetAuraDataUnit,frame),source.params.nativeSelfAura,state.nativeSelfPresent)
end
local function ID(frame)
    local id = Public(frame.cooldownID)
    if type(id) == 'number' and id > 0 and id < math.huge and id % 1 == 0 then return id end
end
local function Source(key)
    local source = M.Data.sources[key or KEY]
    return source and source.consumerCount > 0 and source or nil
end
local function Unique(frame, source)
    local info = Call(frame.GetCooldownInfo, frame)
    if type(info) ~= 'table' or Public(info.spellID) ~= (source.params.nativeBase or 365350) then return false end
    local linked, count = Public(info.linkedSpellIDs), 0
    if source.params.nativeCooldownID then
        if ID(frame)~=source.params.nativeCooldownID or type(linked)~='table' then return false end
        local display=PositiveID(info.overrideTooltipSpellID) or PositiveID(info.overrideSpellID) or PositiveID(info.spellID)
        if display~=source.params.spellID then return false end
        for key,value in pairs(linked) do
            value=PositiveID(value)
            if type(Public(key))~='number' or not value or not source.params.nativeLinks[value] then return false end
            count=count+1
            if count>32 then return false end
        end
        local expected=0
        for id in pairs(source.params.nativeLinks) do
            local occurrences=0
            for _,value in pairs(linked) do if Public(value)==id then occurrences=occurrences+1 end end
            if occurrences~=1 then return false end
            expected=expected+1
        end
        return count==expected
    end
    if source.params.nativeDirect then
        if type(issecretvalue)=='function' and issecretvalue(info.linkedSpellIDs) then return false end
        if linked~=nil and type(linked)~='table' then return false end
        if linked and next(linked)~=nil then return false end
        for _,key in ipairs(directIdentityFields) do
            if type(issecretvalue)=='function' and issecretvalue(info[key]) then return false end
            local value=Public(info[key])
            if value~=nil and value~=0 and value~=source.params.spellID then return false end
        end
        return source.params.spellID==source.params.nativeBase
    end
    if type(linked) ~= 'table' then return false end
    for key, value in pairs(linked) do
        if type(Public(key)) ~= 'number' or Public(value) ~= source.params.spellID then return false end
        count = count + 1
        if count > 1 then return false end
    end
    return count == 1
end
local function Invalidate(frame)
    local binding = bindings[frame]
    local source = binding and Source(binding.key)
    if source then TraceEdge('aura-invalidate',source,frame) end
    bindings[frame] = nil
    if source then
        CancelLoss(source)
        source.state.present, source.state.nativeEvent = nil, nil
        source.state.auraUnit = nil
        source.state.nativeAuraID = nil
        source.state.targetBaselineReset = nil
        source.state.nativeSelfPresent = nil
        source.state.issue = 'native-aura-binding-unavailable'
        M:RefreshSourceNow(source, 'native-aura-signal', true)
        M:QueueSource(source, 'native-aura-rebind')
    end
end
local function OnIdentity(frame, _, forceSet)
    local binding = bindings[frame]
    local source = binding and Source(binding.key)
    if source and binding and ID(frame) == binding.id and (Public(forceSet) == false or Unique(frame, source)) then return end
    if binding then Invalidate(frame) end
    local rebound = owners[frame] and Bind(owners[frame],frame)
    if rebound then
        local source=rebound; if source then M:QueueSource(source,'native-aura-rebind') end
    end
end
local function CommitLoss(source)
    local state = source.state
    local frame = state.lossFrame
    local fullUpdateLoss=state.fullUpdateLoss
    TraceEdge('loss-wake',source,frame)
    state.lossFrame = nil
    state.fullUpdateLoss = nil
    local binding = frame and bindings[frame]
    if Source(source.key) ~= source or not binding or binding.key ~= source.key
        or binding.generation ~= state.generation then return end
    if ID(frame) ~= binding.id then Invalidate(frame); return end
    if Call(binding.viewer.IsShown, binding.viewer) ~= true then
        state.present, state.nativeEvent, state.issue = nil, nil, 'native-aura-viewer-hidden'
        state.auraUnit = nil
        state.targetBaselineReset = nil
        state.nativeSelfPresent = nil
        M:RefreshSourceNow(source, 'native-aura-signal', true)
        return
    end
    if fullUpdateLoss and SelfPresence(frame)~=false then
        state.nativeSelfPresent=nil
        return
    end
    if state.present ~= true then return end
    state.sequence = state.sequence + 1
    state.present, state.nativeEvent, state.issue = false, 'auraRemoved', nil
    TraceEdge('loss-commit',source,frame)
    state.auraUnit = nil
    if source.params.nativeSelfAura then state.nativeSelfPresent=false end
    M:RefreshSourceNow(source, 'native-aura-signal', true)
end
local function PublishMember(source,member,event)
    local state=source.state
    state.sequence=state.sequence+1
    state.nativeAuraID,state.nativeEventAuraID=member.id,member.id
    state.present,state.nativeEvent,state.issue=member.present,event,nil
    state.auraUnit=member.auraUnit
    state.nativeIdentityUnknown=nil
    M:RefreshSourceNow(source,'native-aura-signal',true)
end
CommitMemberLoss=function(source,member)
    local frame=member.lossFrame
    member.lossFrame=nil
    local binding=frame and bindings[frame]
    if Source(source.key)~=source or not binding or binding.key~=source.key
        or binding.generation~=source.state.generation then return end
    if ID(frame)~=binding.id then Invalidate(frame);return end
    if member.requireAbsent and SelfPresence(frame)~=false then
        member.requireAbsent=nil
        source.state.nativeSelfPresent=nil
        return
    end
    member.requireAbsent=nil
    if Call(binding.viewer.IsShown,binding.viewer)~=true then
        CancelLoss(source)
        source.state.present,source.state.nativeEvent,source.state.issue=nil,nil,'native-aura-viewer-hidden'
        M:RefreshSourceNow(source,'native-aura-signal',true)
        return
    end
    if member.present~=true then return end
    member.present=false
    if source.params.nativeSelfMembers then source.state.nativeSelfPresent=false end
    PublishMember(source,member,'auraRemoved')
end
local function MemberEdge(frame,source,present,identity,requireAbsent)
    local state=source.state
    local id=identity or ActiveAuraID(frame,source)
    local member=id and state.nativeMemberStates[id]
    if not member then
        if state.nativeIdentityUnknown then return end
        CancelLoss(source)
        state.present,state.nativeEvent,state.nativeAuraID=nil,nil,nil
        state.nativeIdentityUnknown=true
        state.sequence=state.sequence+1
        M:RefreshSourceNow(source,'native-aura-signal',true)
        return
    end
    member.auraUnit=Call(frame.GetAuraDataUnit,frame)
    if present then
        member.lossFrame=nil
        member.requireAbsent=nil
        M:CancelTask(source,member.taskKey)
        if source.params.nativeSelfMembers then
            state.nativeSelfPresent,state.nativeSelfMemberID=true,id
        end
        if member.present==true and state.nativeLastAddedID==id then return end
        member.present=true
        state.nativeLastAddedID=id
        PublishMember(source,member,'auraAdded')
    elseif member.present==nil then
        member.present=false
        PublishMember(source,member,nil)
    elseif member.present==true and not member.lossFrame then
        member.lossFrame=frame
        member.requireAbsent=requireAbsent
        local ok,code=M:ScheduleTask(source,member.taskKey,GetTime()+0.001,member.commit)
        if not ok then
            CancelLoss(source)
            state.present,state.nativeEvent,state.issue=nil,nil,code
            M:RefreshSourceNow(source,'native-aura-signal',true)
        end
    end
end
local function CreateState(params)
    generation=generation+1
    local state={sequence=0,generation=generation,issue='native-aura-binding-unavailable'}
    if params and params.nativeCooldownID and not params.nativeAggregate then
        state.nativeMemberStates={}
        for id in pairs(params.nativeMembers) do
            local member={id=id,taskKey=LOSS_TASK..':'..id}
            member.commit=function(source) CommitMemberLoss(source,member) end
            state.nativeMemberStates[id]=member
        end
    end
    return state
end
local function Edge(frame, present)
    local binding = bindings[frame]
    local source = binding and Source(binding.key)
    local trace=YUI.Sound and YUI.Sound.DebugTiming
    if trace and trace.enabled then
        trace:Record('native-edge-dispatch',trace:Identity(frame),Public(frame.cooldownID),present,
            binding and binding.key,binding and binding.generation,source and source.state.generation)
    end
    if not source or not binding or binding.generation~=source.state.generation then return end
    if ID(frame) ~= binding.id then Invalidate(frame); return end
    local state = source.state
    TraceEdge(present and 'native-gain' or 'native-loss',source,frame)
    if Call(binding.viewer.IsShown, binding.viewer) ~= true then
        CancelLoss(source)
        state.present, state.nativeEvent, state.issue = nil, nil, 'native-aura-viewer-hidden'
        state.auraUnit = nil
        state.targetBaselineReset = nil
        state.nativeSelfPresent = nil
        M:RefreshSourceNow(source, 'native-aura-signal', true)
        return
    end
    if state.nativeMemberStates then return MemberEdge(frame,source,present) end
    if present then
        if state.lossFrame then TraceEdge('loss-cancel-by-gain',source,frame) end
        CancelLoss(source)
        -- Keep the observed owner across target changes; the native viewer can
        -- also display target auras, whose baseline must still be discarded.
        state.auraUnit = Call(frame.GetAuraDataUnit, frame)
        state.targetBaselineReset = nil
        if source.params.nativeSelfAura then state.nativeSelfPresent=SelfPresence(frame) end
    else
        -- Native removal precedes replacement gains in the same UNIT_AURA update.
        -- Keep the committed presence until the shared one-shot task settles it.
        if state.present == nil then
            -- Switching to an existing target aura refreshes the native binding
            -- without an applied alert. Its real removed alert still identifies
            -- the old instance's unit here, before native instance cleanup.
            local targetLoss = state.targetBaselineReset and Call(frame.GetAuraDataUnit, frame) == 'target'
            state.targetBaselineReset = nil
            if not targetLoss then state.present = false; return end
            -- Recover only the pending loss baseline, never synthesize a gain.
            state.present, state.auraUnit = true, 'target'
        end
        if state.present == true and not state.lossFrame then
            state.lossFrame = frame
            -- A due-now task can run before later aura events in this same frame.
            -- Per-rule confirmation delays belong to the sound consumer;
            -- the shared source only coalesces same-frame replacements.
            local ok, code = M:ScheduleTask(source, LOSS_TASK, GetTime() + 0.001, CommitLoss)
            TraceEdge(ok and 'loss-queued' or 'loss-queue-failed',source,frame)
            if not ok then
                state.lossFrame = nil
                state.present, state.nativeEvent, state.issue = nil, nil, code
                M:RefreshSourceNow(source, 'native-aura-signal', true)
            end
        end
        return
    end
    if state.present == present then return end
    state.sequence = state.sequence + 1
    state.present, state.nativeEvent, state.issue = present, present and 'auraAdded' or 'auraRemoved', nil
    M:RefreshSourceNow(source, 'native-aura-signal', true)
end
local function Gain(frame) Edge(frame, true) end
local function Loss(frame) Edge(frame, false) end
-- Native item refreshes can fill the identity after UNIT_AURA without an alert.
-- Only reviewed families and public ownership establish recipient presence.
ReconcileMembers=function(frame)
    local binding=bindings[frame]
    local source=binding and Source(binding.key)
    if not source or not source.params.nativeSelfMembers or binding.generation~=source.state.generation then return end
    local state=source.state
    if ID(frame)~=binding.id or not Unique(frame,source) then Invalidate(frame);return end
    if Call(binding.viewer.IsShown,binding.viewer)~=true then
        CancelLoss(source);state.nativeSelfPresent=nil;return
    end
    local present=SelfPresence(frame)
    if present==nil then CancelLoss(source);state.nativeSelfPresent=nil;return end
    local id
    if present then id=ActiveAuraID(frame,source) else id=state.nativeSelfMemberID end
    if present and id then
        local recipient=false
        for _,candidate in ipairs(source.params.nativeRecipientIDs) do if candidate==id then recipient=true end end
        if not recipient then return end
    end
    if present and not id then return end -- retain a known absence until identity arrives
    local previous=state.nativeSelfPresent
    if previous~=nil and present~=previous and id then
        MemberEdge(frame,source,present,id,not present)
    elseif previous==nil and present and id then
        local member=state.nativeMemberStates[id]
        member.present,member.auraUnit=true,'player'
        state.nativeLastAddedID=id
    end
    state.nativeSelfPresent=present
    if present then state.nativeSelfMemberID=id end
end
Bind = function(viewer, frame, source)
    if not source then
        for _, candidate in pairs(M.Data.sources) do
            if candidate.sourceType.id == TYPE and candidate.consumerCount > 0 then
                local bound = Bind(viewer, frame, candidate)
                if bound then return bound end
            end
        end
        return false
    end
    local combat = YUI.API and YUI.API.Combat
    if not source or not frame or not combat or Call(combat.InCombatLockdown) ~= false then return false end
    if type(hooksecurefunc) ~= 'function'
        or type(frame.TriggerAuraAppliedAlert) ~= 'function' or type(frame.TriggerAuraRemovedAlert) ~= 'function'
        or type(frame.SetCooldownID) ~= 'function' then bindings[frame] = nil; return false end
    owners[frame] = viewer
    local installed = hooked[frame] or {}
    hooked[frame] = installed
    for _, pair in ipairs({ { 'TriggerAuraAppliedAlert', Gain }, { 'TriggerAuraRemovedAlert', Loss }, { 'SetCooldownID', OnIdentity } }) do
        if not installed[pair[1]] then
            local ok = pcall(hooksecurefunc, frame, pair[1], pair[2])
            if not ok then return false end
            installed[pair[1]] = true
        end
    end
    local id = ID(frame)
    if source.params.nativeSelfMembers and type(frame.RefreshData)=='function' and not installed.RefreshData then
        installed.RefreshData=pcall(hooksecurefunc,frame,'RefreshData',ReconcileMembers) or nil
    end
    if not id or not Unique(frame, source) then
        local old=bindings[frame]
        if old and old.key==source.key then bindings[frame]=nil end
        return false
    end
    local previous=bindings[frame]
    if previous and previous.id==id and previous.viewer==viewer and previous.key==source.key and previous.generation==source.state.generation then return source end
    bindings[frame] = { id = id, viewer = viewer, key = source.key, generation=source.state.generation }
    -- Initial binding/rebinding is a baseline, never an applied alert. Keep a
    -- continuous baseline across the pool rebuild caused by a full aura update.
    if source.params.nativeSelfAura and source.state.nativeSelfPresent==nil then
        source.state.nativeSelfPresent=SelfPresence(frame)
    end
    if source.params.nativeSelfMembers then ReconcileMembers(frame) end
    TraceEdge('aura-bind',source,frame)
    return source
end
local function Acquired(viewer, frame)
    local source=Bind(viewer,frame)
    if source then M:QueueSource(source,'native-aura-rebind') end
end
local function NativeLayoutChanged(viewer)
    if YUI.IsForever then
        for frame,binding in pairs(bindings) do
            if binding.viewer==viewer then ReconcileMembers(frame) end
        end
    end
    for _,source in pairs(M.Data.sources) do
        if (source.sourceType.id==TYPE or source.sourceType.id=='native-equipment-aura') and source.consumerCount>0 then
            M:QueueSource(source,'native-aura-layout')
        end
    end
end
local layoutObservers=setmetatable({},{__mode='k'})
local function TraceAuraUpdate(viewer,unit,update)
    local trace=YUI.Sound and YUI.Sound.DebugTiming
    if not (trace and trace.enabled) then return end
    update=Public(update)
    local readable=type(update)=='table' and not (issecrettable and issecrettable(update))
    trace:Record('native-aura-update',trace:Identity(viewer),Public(unit),readable,
        readable and update.isFullUpdate,readable and Public(update.addedAuras)~=nil,
        readable and Public(update.updatedAuraInstanceIDs)~=nil,
        readable and Public(update.removedAuraInstanceIDs)~=nil)
    for frame,binding in pairs(bindings) do
        local source=binding.viewer==viewer and Source(binding.key)
        if source then TraceEdge('aura-update-state',source,frame) end
    end
end
local function OnAuraUpdate(viewer,unit,update)
    TraceAuraUpdate(viewer,unit,update)
    update=Public(update)
    if Public(unit)~='player' or type(update)~='table'
        or issecrettable and issecrettable(update) then return end
    if YUI.IsForever then
        for frame,binding in pairs(bindings) do
            if binding.viewer==viewer then ReconcileMembers(frame) end
        end
    end
    if Public(update.isFullUpdate)~=true then return end
    -- Native OnUnitAura returns after RefreshLayout for a full update, omitting
    -- both alert callbacks. Reconcile only an explicit self aura with one native
    -- identity, after the native layout has finished; target/member auras stay on
    -- their existing callback paths. Unchanged presence is not a refresh event.
    for frame,binding in pairs(bindings) do
        local source=binding.viewer==viewer and Source(binding.key)
        if source and source.params.nativeSelfAura and binding.generation==source.state.generation then
            local state=source.state
            if ID(frame)~=binding.id or not Unique(frame,source) then
                Invalidate(frame)
            elseif Call(viewer.IsShown,viewer)~=true then
                Edge(frame,false)
            else
                local previous=state.nativeSelfPresent
                local present=SelfPresence(frame)
                state.nativeSelfPresent=present
                if present~=nil and previous~=nil and present~=previous then
                    TraceEdge(present and 'full-update-gain' or 'full-update-loss',source,frame)
                    Edge(frame,present)
                    if not present and state.lossFrame==frame then state.fullUpdateLoss=true end
                end
            end
        end
    end
end
local function ObserveLayout(viewer)
    if layoutObservers[viewer] or type(hooksecurefunc)~='function' then return end
    layoutObservers[viewer]=true
    for _,method in ipairs({'RefreshLayout','RefreshData'}) do
        if type(viewer[method])=='function' then pcall(hooksecurefunc,viewer,method,NativeLayoutChanged) end
    end
    if type(viewer.OnUnitAura)=='function' then pcall(hooksecurefunc,viewer,'OnUnitAura',OnAuraUpdate) end
end
function Sources:RefreshNativeAuraBindings()
    NativeLayoutChanged()
end
local function Read(source, state, reason)
    if reason == 'native-aura-signal' then return true end
    local previousIssue = state.issue
    local found = false
    local combat = YUI.API and YUI.API.Combat
    if not combat or Call(combat.InCombatLockdown) ~= false then return false end
    -- Rebuild membership from the active pool; released frames may retain their old ID.
    for frame,binding in pairs(bindings) do
        if binding.key==source.key then bindings[frame]=nil end
    end
    for _, name in ipairs(viewerNames) do
        local viewer = _G[name]
        if viewer then
            if not viewers[viewer] and type(viewer.OnAcquireItemFrame) == 'function' and type(hooksecurefunc) == 'function' then
                viewers[viewer] = pcall(hooksecurefunc, viewer, 'OnAcquireItemFrame', Acquired) or nil
                ObserveLayout(viewer)
            end
            local pool = viewer.itemFramePool
            if pool and type(pool.EnumerateActive) == 'function' then
                pcall(function()
                    local count = 0
                    for frame in pool:EnumerateActive() do
                        count = count + 1; if count > 256 then break end
                        found = (Bind(viewer, frame, source) and Call(viewer.IsShown, viewer) == true) or found
                    end
                end)
            end
        end
    end
    state.issue = nil
    if not found then state.issue = 'native-aura-binding-unavailable' end
    if not found then
        CancelLoss(source)
        state.nativeSelfPresent=nil
        state.present, state.nativeEvent, state.auraUnit, state.targetBaselineReset = nil, nil, nil, nil
        state.nativeAuraID=nil
    end
    if state.issue~=previousIssue and YUI.Event and YUI.Event.Emit then YUI.Event:Emit('YUI_MONITOR_SOURCE_STATUS_CHANGED',source.key) end
    return state.issue ~= previousIssue
end
function Sources:DescribeNativeAuraSignal(spellID, unit, event, readNativeAuraEntries)
    if unit ~= 'cdm' or (event ~= 'auraAdded' and event ~= 'auraRemoved') then return nil end
    local auraID, base, direct, multi, selfAura = 365362, 365350, false, nil, false
    if spellID ~= auraID or YUI.IsForever then
        local api = YUI.API and YUI.API.CooldownViewer
        if not api or not api.ReadEntries then return nil end
        local entries
        if YUI.IsRetail and readNativeAuraEntries then entries=readNativeAuraEntries()
        else entries=api:ReadEntries({includeHidden=true,allowUnlearned=true,rawCatalog=YUI.IsForever==true}) end
        local selected
        for index, entry in ipairs(type(entries)=='table' and entries or {}) do
            if index>512 then break end
            if entry.sourceCategory=='trackedBuff' or entry.sourceCategory=='trackedBar' then
                local native=self:DescribeNativeAuraCatalogEntry(entry)
                local linked=entry.linkedSpellIDs
                local isDirect=(linked==nil or type(linked)=='table' and #linked==0) and entry.spellID==spellID
                    and (not entry.overrideSpellID or entry.overrideSpellID==spellID)
                    and (not entry.overrideTooltipSpellID or entry.overrideTooltipSpellID==spellID)
                if native and native.members[spellID] then
                    if selected and (not multi or multi.cooldownID~=native.cooldownID) then return nil end
                    selected,multi=entry,native
                    auraID=native.id
                elseif isDirect or type(linked)=='table' and #linked==1 and
                    (entry.spellID==spellID or linked[1]==spellID) then
                    local candidateAura=isDirect and spellID or linked[1]
                    if selected and (multi or selected.spellID~=entry.spellID or auraID~=candidateAura) then return nil end
                    selected=entry
                    auraID,direct=candidateAura,isDirect
                end
            end
        end
        if not selected then return nil end
        base=selected.spellID
        selfAura=Public(selected.selfAura)==true
        if type(auraID)~='number' or type(base)~='number' then return nil end
    end
    if not self.nativeAuraSignalRegistered then
        local registered, code = M:RegisterSourceType(TYPE, {
            createState = CreateState,
            read = Read, onEvent = function(source, state, event)
                TraceEdge(event,source,nil)
                if event == 'PLAYER_ENTERING_WORLD'
                    or event=='PLAYER_TARGET_CHANGED' and state.auraUnit~='player' then
                    CancelLoss(source)
                    state.present, state.nativeEvent = nil, nil
                    state.auraUnit = nil
                    state.nativeAuraID = nil
                    state.targetBaselineReset = event == 'PLAYER_TARGET_CHANGED' or nil
                    state.nativeSelfPresent = nil
                    state.sequence = state.sequence + 1
                    M:RefreshSourceNow(source, 'native-aura-signal', true)
                end
                return true
            end,
            events = { { event = 'PLAYER_ENTERING_WORLD', all = true },
                { event = 'PLAYER_TARGET_CHANGED', all = true },
                { event = 'PLAYER_REGEN_ENABLED', all = true }, { event = 'ADDON_LOADED', all = true },
                { event = 'CVAR_UPDATE', all = true }, { event = 'PLAYER_SPECIALIZATION_CHANGED', all = true } },
        })
        if not registered and code ~= 'source-type-exists' then return nil, code end
        self.nativeAuraSignalRegistered = true
    end
    if multi then
        local auraIDs=multi.castIDs and multi.castIDs[spellID] and multi.recipientAuraIDs
        if auraIDs and #auraIDs==0 then return nil,'native-aura-binding-unavailable' end
        return {key='native-aura-signal:cdm-entry:'..multi.cooldownID,type=TYPE,
            nativeAuraID=auraIDs and auraIDs[1] or not multi.aggregate and (spellID==multi.base and multi.id or spellID) or nil,
            nativeAuraIDs=auraIDs,
            nativeAuraUnit=not multi.aggregate and multi.namesComplete and multi.selfAura and 'player' or nil,
            params={spellID=multi.id,unit='cdm',nativeBase=multi.base,nativeCooldownID=multi.cooldownID,
                nativeMembers=multi.members,nativeLinks=multi.links,nativeAggregate=multi.aggregate,
                nativeRecipientIDs=multi.recipientAuraIDs,
                nativeSelfMembers=multi.selfAura and multi.recipientAuraIDs and #multi.recipientAuraIDs>0 or nil}}
    end
    return { key = 'native-aura-signal:cdm:'..auraID, type = TYPE, params = { spellID = auraID, unit = 'cdm', nativeBase = base, nativeDirect=direct, nativeSelfAura=selfAura } }
end
-- Equipment presets own a slot, not the item or aura captured during setup.
local EQUIPMENT_TYPE='native-equipment-aura'
local equipmentBindings=setmetatable({},{__mode='k'})
local equipmentHooks=setmetatable({},{__mode='k'})
local equipmentViewers=setmetatable({},{__mode='k'})
local equipmentGeneration=0
local function Equipped(slot)
    local item=YUI.API and YUI.API.Item
    local id=item and Call(item.GetInventoryItemID,'player',slot)
    if type(id)=='number' and id>0 then return id end
end
local function EquipmentIdentity(frame,slot)
    local info=Call(frame.GetCooldownInfo,frame)
    return type(info)=='table' and Public(info.equipSlot)==slot and ID(frame) or nil
end
local function EquipmentEdge(frame,present)
    local b=equipmentBindings[frame]
    local source=b and Source(b.key)
    if not source or source.state.generation~=b.generation then return end
    local state=source.state
    if Equipped(source.params.equipSlot)~=b.itemID or EquipmentIdentity(frame,source.params.equipSlot)~=b.id
        or Call(b.viewer.IsShown,b.viewer)~=true then
        equipmentBindings[frame]=nil
        state.nativeEvent=nil;state.issue='native-aura-binding-unavailable';state.entries[b.id]=nil
        M:RefreshSourceNow(source,'native-equipment-edge',true)
        M:QueueSource(source,'equipment-rebind')
        return
    end
    if state.entries[b.id]==present then return end
    state.entries[b.id]=present
    state.sequence=state.sequence+1;state.nativeEvent=present and 'auraAdded' or 'auraRemoved';state.issue=nil
    M:RefreshSourceNow(source,'native-equipment-edge',true)
end
local function EquipmentGain(frame) EquipmentEdge(frame,true) end
local function EquipmentLoss(frame) EquipmentEdge(frame,false) end
local function EquipmentRebind(frame)
    local b=equipmentBindings[frame]
    if b then
        local source=Source(b.key)
        if source and source.state.generation==b.generation then
            if EquipmentIdentity(frame,source.params.equipSlot)==b.id and Equipped(source.params.equipSlot)==b.itemID then return end
            source.state.entries[b.id]=nil;source.state.nativeEvent=nil
            M:QueueSource(source,'equipment-rebind')
        end
        equipmentBindings[frame]=nil
    end
    for _,source in pairs(M.Data.sources) do
        if source.sourceType.id==EQUIPMENT_TYPE and source.consumerCount>0 then M:QueueSource(source,'equipment-rebind') end
    end
end
local function EquipmentAcquired(viewer,frame)
    local active=false
    for _,source in pairs(M.Data.sources) do if source.sourceType.id==EQUIPMENT_TYPE and source.consumerCount>0 then active=true;break end end
    if not active then return end
    -- Acquisition may precede SetCooldownID; hook once and resolve on the queued read.
    if not equipmentHooks[frame] and type(hooksecurefunc)=='function' and type(frame.SetCooldownID)=='function' then
        equipmentHooks[frame]={identity=pcall(hooksecurefunc,frame,'SetCooldownID',EquipmentRebind)}
    end
    EquipmentRebind(frame)
end
local function ReadEquipment(source,state,reason)
    if reason=='native-equipment-edge' then return true end
    local itemID=Equipped(source.params.equipSlot)
    if state.itemID~=itemID then
        state.itemID=itemID;state.entries={};state.nativeEvent=nil
        for frame,b in pairs(equipmentBindings) do if b.generation==source.state.generation then equipmentBindings[frame]=nil end end
    end
    local combat=YUI.API and YUI.API.Combat
    if not combat or Call(combat.InCombatLockdown)~=false then
        state.nativeEvent=nil;state.issue='native-aura-binding-unavailable';return true
    end
    local previousIssue=state.issue
    local found,activeIDs=false,{}
    for frame,b in pairs(equipmentBindings) do if b.key==source.key then equipmentBindings[frame]=nil end end
    if itemID then
        for _,name in ipairs(viewerNames) do
            local viewer=_G[name]
            if viewer then
                ObserveLayout(viewer)
                if not equipmentViewers[viewer] and type(hooksecurefunc)=='function' and type(viewer.OnAcquireItemFrame)=='function' then
                    equipmentViewers[viewer]=pcall(hooksecurefunc,viewer,'OnAcquireItemFrame',EquipmentAcquired) or nil
                end
                local pool=viewer.itemFramePool
                if pool and type(pool.EnumerateActive)=='function' then
                    pcall(function()
                        local count=0
                        for frame in pool:EnumerateActive() do
                            count=count+1;if count>256 then break end
                            local id=EquipmentIdentity(frame,source.params.equipSlot)
                            if id and type(hooksecurefunc)=='function' then
                                local h=equipmentHooks[frame] or {};equipmentHooks[frame]=h
                                if not h.identity and type(frame.SetCooldownID)=='function' then h.identity=pcall(hooksecurefunc,frame,'SetCooldownID',EquipmentRebind) end
                                if not h.gain and type(frame.TriggerAuraAppliedAlert)=='function' then h.gain=pcall(hooksecurefunc,frame,'TriggerAuraAppliedAlert',EquipmentGain) end
                                if not h.loss and type(frame.TriggerAuraRemovedAlert)=='function' then h.loss=pcall(hooksecurefunc,frame,'TriggerAuraRemovedAlert',EquipmentLoss) end
                                if h.identity and h.gain and h.loss then
                                    equipmentBindings[frame]={key=source.key,generation=state.generation,id=id,itemID=itemID,viewer=viewer}
                                    activeIDs[id]=true
                                    found=Call(viewer.IsShown,viewer)==true or found
                                end
                            end
                        end
                    end)
                end
            end
        end
    end
    for id in pairs(state.entries) do if not activeIDs[id] then state.entries[id]=nil end end
    state.issue=not found and 'native-aura-binding-unavailable' or nil
    if not found then state.nativeEvent=nil end
    if state.issue~=previousIssue and YUI.Event and YUI.Event.Emit then YUI.Event:Emit('YUI_MONITOR_SOURCE_STATUS_CHANGED',source.key) end
    return true
end
function Sources:DescribeEquipmentAura(slot,event)
    if (slot~=13 and slot~=14) or (event~='auraAdded' and event~='auraRemoved') then return nil,'invalid-equipment-aura' end
    if not self.equipmentAuraRegistered then
        local ok,code=M:RegisterSourceType(EQUIPMENT_TYPE,{
            createState=function() equipmentGeneration=equipmentGeneration+1;return {sequence=0,entries={},generation=equipmentGeneration,issue='native-aura-binding-unavailable'} end,
            read=ReadEquipment,
            onEvent=function(source,state,event)
                if event=='PLAYER_EQUIPMENT_CHANGED' or event=='PLAYER_ENTERING_WORLD' or event=='PLAYER_SPECIALIZATION_CHANGED' then
                    state.entries={};state.nativeEvent=nil
                    for frame,b in pairs(equipmentBindings) do if b.generation==source.state.generation then equipmentBindings[frame]=nil end end
                end
                return true
            end,
            events={{event='PLAYER_EQUIPMENT_CHANGED',all=true},{event='PLAYER_ENTERING_WORLD',all=true},
                {event='PLAYER_REGEN_ENABLED',all=true},{event='PLAYER_SPECIALIZATION_CHANGED',all=true},
                {event='CVAR_UPDATE',all=true},{event='ADDON_LOADED',all=true}}
        })
        if not ok and code~='source-type-exists' then return nil,code end
        self.equipmentAuraRegistered=true
    end
    return {key='equipment-aura:player:'..slot,type=EQUIPMENT_TYPE,params={equipSlot=slot,unit='player'}}
end
return Sources
