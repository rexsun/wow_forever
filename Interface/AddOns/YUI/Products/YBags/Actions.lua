local YUI = _G.YUI
local B = YUI and YUI.YBags
if not B then return end
local A=YUI.API.Bags
local Actions={}
B.Actions=Actions
Actions.sortRoundLimit=6
local guildBatchInterval=.25
local guildBatchSteps=9
local guildBatchPause=6
local function Same(a,b)
    return a and b and a.itemID==b.itemID and a.link==b.link and a.count==b.count and a.bag==b.bag and a.slot==b.slot
end
function Actions:IsVirtualChargeGroup(item)
    return item~=nil and item.members~=nil and item.maxStack==1 and item.charges~=nil
end
function Actions:Protected(item,allowQuestMove)
    local config=B:GetConfig()
    return not item or item.locked or item.quest and not allowQuestMove
        or config.favorites[tostring(item.itemID)] or config.locks[item.key]
end
function Actions:CancelDelete()
    if self.deleteTimer then self.deleteTimer:Cancel();self.deleteTimer=nil;B.Stats.timers=math.max(0,B.Stats.timers-1) end
    local button=self.deleteButton
    self.deleteItem,self.deleteButton=nil,nil
    if button and button.deleteMark then button.deleteMark:Hide() end
    if button and GameTooltip.IsOwned and GameTooltip:IsOwned(button) and button:IsMouseOver() then
        local enter=button:GetScript("OnEnter");if enter then enter(button) end
    end
end
local function DeleteExpired() Actions:CancelDelete() end
function Actions:DeleteHint()
    return self.deleteItem and string.format(B:T("action.delete_again"),self.deleteItem.count)
end
function Actions:DeleteClick(item,button)
    if self:IsVirtualChargeGroup(item) then self:CancelDelete();return true end
    if A.Context()~="travel" or A.InCombat() or A.CursorBusy() or self.queue
        or item.quality~=0 or not A.IsNonEquippable(item) or self:Protected(item) then self:CancelDelete();return false end
    local fresh=A.Slot(item.bag,item.slot)
    if not fresh or fresh.quality~=0 or fresh.quest or fresh.locked or not A.IsNonEquippable(fresh) then self:CancelDelete();return true end
    if self.deleteItem and Same(fresh,self.deleteItem) and Same(item,self.deleteItem) then
        self:CancelDelete()
        if not A.Delete(item.bag,item.slot) then B:Notify("error.operation") end
        return true
    end
    self:CancelDelete()
    self.deleteItem={bag=fresh.bag,slot=fresh.slot,itemID=fresh.itemID,link=fresh.link,count=fresh.count}
    self.deleteButton=button
    if button.deleteMark then button.deleteMark:Show() end
    self.deleteTimer=C_Timer.NewTimer(5,DeleteExpired);B.Stats.timers=B.Stats.timers+1
    GameTooltip:AddLine(self:DeleteHint(),1,.4,.3);GameTooltip:Show()
    return true
end
function Actions:FreeSlot(item,ids,used,space,excludedBag)
    if not item and not space then return end
    for _,id in ipairs(ids) do
        local bag=B.Model.bags[id]
        if id~=excludedBag and bag and (not space or (bag.space or A.SpaceKey(id,bag.family,bag.kind))==space)
            and (not item or A.Fits(item,bag)) then
            for slot=1,bag.capacity do
                local key=tostring(id)..":"..slot
                if not bag.slots[slot] and not B:GetConfig().locks[key] and not (used and used[key]) then return {bag=id,slot=slot,key=key} end
            end
        end
    end
end
function Actions:MakeSplit(item,size,parts)
    if not item or item.maxStack==1 then return nil end
    if self:Protected(item) or size<1 or parts<1 or size~=math.floor(size) or parts~=math.floor(parts) or size*parts>item.count then return nil end
    local remainder=item.count-size*parts
    local needed=parts-(remainder==0 and 1 or 0)
    if needed<1 then return nil end
    local ids=A.GetCarryBags(true)
    local used,steps={},{ }
    for _=1,needed do
        local target=self:FreeSlot(item,ids,used)
        if not target then return nil end
        used[target.key]=true
        steps[#steps+1]={source={bag=item.bag,slot=item.slot},target=target,count=size,itemID=item.itemID,link=item.link,
            sourceCount=item.count-(_-1)*size,guid=item.guid,bound=item.bound}
    end
    return {steps=steps,original=item.count,size=size,parts=parts,remainder=remainder,needed=needed}
end
local function BuildSplitTree(item,size,targets,rounds,steps)
    local nextTarget=0
    local function Divide(source,first,last,total,depth)
        if first==last then return end
        local middle=math.floor((first+last)/2)
        -- Only the leftmost pile can have a different size. Every right
        -- subtree consists of equal requested piles.
        local amount=(last-middle)*size
        nextTarget=nextTarget+1
        local target=targets[nextTarget].target
        local operation={source=source,target=target,count=amount,sourceCount=total,itemID=item.itemID,link=item.link}
        rounds[depth]=rounds[depth] or {};rounds[depth][#rounds[depth]+1]=operation;steps[#steps+1]=operation
        Divide(source,first,middle,total-amount,depth+1)
        Divide(target,middle+1,last,amount,depth+1)
    end
    Divide({bag=item.bag,slot=item.slot},1,#targets+1,item.count,1)
end
function Actions:MakeSplitGroups(item,size,parts)
    local plan=self:MakeSplit(item,size,parts)
    if not plan then return nil end
    local targets=plan.steps
    plan.rounds,plan.steps={},{}
    BuildSplitTree(item,size,targets,plan.rounds,plan.steps)
    return plan
end
local function SlotKey(item) return tostring(item.bag)..":"..item.slot end
local firstPlacementSliceBudgetMs=70
local function InventoryActionTime()
    local clock=YUI.API.System and YUI.API.System.GetTimePreciseSec
    return clock and clock() or A.Now()
end
local function FinishPlacementBatch(plan)
    local timing=plan.firstBatchTiming
    if not timing then return end
    plan.firstBatchTiming=nil
    if not plan.observe then return end
    local at=InventoryActionTime()
    local result=B:Copy(timing)
    result.elapsedMs=(timing.firstSliceMs or 0)+(timing.started and (at-timing.started)*1000 or 0)
    result.started=nil
    result.pausedAt=nil
    plan.observe("first-batch",at,nil,result)
end
local function FinishMaterialTrace(round,reason)
    local trace=round and round.materialTrace
    if not trace then return end
    round.materialTrace=nil
    if trace.observe then trace.observe("finish",InventoryActionTime(),nil,reason) end
end
local function FinishCategoryTrace(state,reason)
    if not state or not state.observe then return end
    local observe=state.observe
    state.observe=nil
    observe("finish",InventoryActionTime(),nil,reason)
end
local function ObserveMoveSlots(trace,op,sourceReady,targetReady)
    local firstSource=sourceReady and not op.sourceReadyReported
    local firstTarget=targetReady and not op.targetReadyReported
    if not firstSource and not firstTarget then return end
    op.sourceReadyReported=op.sourceReadyReported or firstSource
    op.targetReadyReported=op.targetReadyReported or firstTarget
    trace.observe("slots",InventoryActionTime(),op,firstSource,firstTarget)
end
local function BalanceSelectedSplits(plan)
    local sources,order,targets={},{},{}
    for _,op in ipairs(plan.steps) do
        if op.combine or op.count~=plan.size then return end
        local from,to=SlotKey(op.source),SlotKey(op.target)
        if sources[to] or targets[from] or targets[to] then return end
        local group=sources[from]
        if not group then
            group={item={bag=op.source.bag,slot=op.source.slot,count=op.sourceCount,itemID=op.itemID,link=op.link},
                targets={}}
            sources[from]=group;order[#order+1]=group
        end
        targets[to]=true
        group.targets[#group.targets+1]=op
    end
    local steps,rounds={},{}
    for _,group in ipairs(order) do BuildSplitTree(group.item,plan.size,group.targets,rounds,steps) end
    plan.steps,plan.rounds=steps,rounds
end
function Actions:Selection(item)
    if not item or (item.maxStack or 1)<=1 then return nil end
    local selection={members={},count=0,maxStack=item.maxStack or 1,stackKey=B.Classification:StackKey(item),
        itemID=item.itemID,link=item.link,name=item.name,icon=item.icon,quality=item.quality,
        groupUID=item.members and item.uid}
    for _,member in ipairs(item.members or {item}) do
        local current=A.Slot(member.bag,member.slot)
        if not current or not B.Classification:SameStack(current,item) then return nil end
        selection.members[#selection.members+1]=current;selection.count=selection.count+current.count
    end
    return selection
end
function Actions:SelectionValid(selection)
    if (selection.maxStack or 1)<=1 then return false end
    for _,member in ipairs(selection.members) do
        local current=A.Slot(member.bag,member.slot)
        if not Same(current,member) or not B.Classification:SameStack(current,member) or current.locked or current.bound~=member.bound
            or member.guid and current.guid~=member.guid then return false end
    end
    return true
end
function Actions:MakeSelection(selection,size,mode,parts)
    if not selection or (selection.maxStack or 1)<=1 or not size or size~=math.floor(size) or size<1 then return nil end
    local total=selection.count
    local amount=mode=="groups" and size*(parts or 0) or size
    if amount<1 or amount>total or mode=="extract" and size>selection.maxStack
        or mode=="groups" and (not parts or parts<1 or parts~=math.floor(parts) or size>selection.maxStack) then return nil end
    local plan={steps={},outputs={},selection=selection,size=size,parts=parts or math.ceil(size/selection.maxStack),
        original=total,remainder=total-amount,needed=0,mode=mode}
    local sources,occupied={},{}
    for _,member in ipairs(selection.members) do
        if self:Protected(member) then return nil end
        local source=B:Copy(member);sources[#sources+1]=source;occupied[SlotKey(source)]=source
    end
    table.sort(sources,function(a,b) return a.count==b.count and (a.bag==b.bag and a.slot<b.slot or a.bag<b.bag) or a.count<b.count end)
    -- Keep the existing balanced rounds when one physical stack produces many groups.
    if #sources==1 and mode=="groups" and parts>1 then
        local native=self:MakeSplitGroups(sources[1],size,parts)
        if native then
            local cells={[SlotKey(sources[1])]=B:Copy(sources[1])}
            for _,round in ipairs(native.rounds) do for _,op in ipairs(round) do
                local source=cells[SlotKey(op.source)];source.count=source.count-op.count
                local target=B:Copy(source);target.bag,target.slot,target.count,target.guid=op.target.bag,op.target.slot,op.count,nil
                cells[SlotKey(target)]=target
            end end
            local original=SlotKey(sources[1])
            if native.remainder==0 then plan.outputs[#plan.outputs+1]=cells[original] end
            for _,op in ipairs(native.steps) do plan.outputs[#plan.outputs+1]=cells[SlotKey(op.target)] end
            plan.rounds,plan.steps,plan.needed=native.rounds,native.steps,native.needed
            return plan
        end
    end
    local chunks={}
    if mode=="groups" then for _=1,parts do chunks[#chunks+1]=size end
    else
        local remainder=amount%selection.maxStack
        if remainder>0 then chunks[#chunks+1]=remainder end
        for _=1,math.floor(amount/selection.maxStack) do chunks[#chunks+1]=selection.maxStack end
    end
    local function Free(source)
        for _,id in ipairs(A.GetCarryBags(true)) do
            local bag=B.Model.bags[id]
            if bag and A.Fits(source,bag) then for slot=1,bag.capacity do
                local key=tostring(id)..":"..slot
                local virtual=occupied[key]
                if not B:GetConfig().locks[key] and (virtual and virtual.count==0 or not virtual and not bag.slots[slot]) then
                    return {bag=id,slot=slot,count=0,itemID=source.itemID,link=source.link}
                end
            end end
        end
    end
    local function Move(source,target,count)
        local op={source={bag=source.bag,slot=source.slot},target={bag=target.bag,slot=target.slot},
            itemID=source.itemID,link=source.link,bound=source.bound,guid=source.guid,sourceCount=source.count,
            targetCount=target.count,combine=target.count>0}
        if count<source.count then op.count=count end
        plan.steps[#plan.steps+1]=op
        source.count=source.count-count;target.count=target.count+count;occupied[SlotKey(target)]=target
    end
    for _,chunk in ipairs(chunks) do
        local target
        -- Prefer a ready physical stack; selecting it requires no bag mutation.
        for _,source in ipairs(sources) do if not source.selected and source.count==chunk then target=source;break end end
        if not target then
            local larger
            for _,source in ipairs(sources) do if not source.selected and source.count>chunk then larger=source;break end end
            if larger then
                target=Free(larger);if not target then return nil end
                plan.needed=plan.needed+1;Move(larger,target,chunk)
            else
                for _,source in ipairs(sources) do if not source.selected and source.count>0 then target=source;break end end
                if not target then return nil end
                for _,source in ipairs(sources) do
                    if source~=target and not source.selected and source.count>0 and A.Fits(source,B.Model.bags[target.bag]) then
                        Move(source,target,math.min(source.count,chunk-target.count))
                        if target.count==chunk then break end
                    end
                end
                if target.count~=chunk then return nil end
            end
        end
        target.selected=true;plan.outputs[#plan.outputs+1]=target
    end
    return plan
end
function Actions:CompleteSelection()
    local plan=self.selection
    if not plan or not B.active or A.InCombat() or A.CursorBusy() then self:Stop();return false end
    local items={}
    for _,output in ipairs(plan.outputs) do
        local current=A.Slot(output.bag,output.slot)
        if not current or current.count~=output.count or not B.Classification:SameStack(current,plan.selection.members[1])
            or current.locked or output.guid and current.guid~=output.guid then self:Stop();B:Notify("error.changed");return false end
        if not output.displayed then items[#items+1]=current end
    end
    if #items>0 then B.View:SeparateItems(plan.selection,items) end
    local ok=true
    if plan.mode=="extract" then
        local item=items[1]
        ok=A.Pickup(item.bag,item.slot) and A.CursorBusy()
        if ok then B.View:RememberCursor(nil,item) end
    end
    local carryBatch=self.carryBatch
    self:Stop((self.splitBatch or self.serialSplitTrace) and "complete" or nil)
    local w=B.View.windows.player
    if w and w.open and not plan.progressiveGroups and not carryBatch then B.View:Layout(w,false) end
    return ok
end
function Actions:StartSelection(plan)
    if B.Runtime.finalCarryBatch and not self.queue then B:Flush() end
    if not plan or self.queue or self.nativeSort or A.InCombat() or A.CursorBusy() or not self:SelectionValid(plan.selection) then return false end
    if YUI.IsForever and plan.mode=="groups" and not plan.rounds and #plan.steps>0 then BalanceSelectedSplits(plan) end
    self.selection=plan
    local window=B.View.windows.player
    plan.progressiveGroups=plan.mode=="groups" and plan.selection.groupUID~=nil
        and window and window.open and window.grouping and #plan.steps>0
    if plan.progressiveGroups then
        plan.unseparated=plan.original
        B.View:BeginSplitDisplay(window,plan)
        B.View:RefreshItemInputs()
    end
    plan.outputBySlot,plan.sourcesBySlot={},{}
    for _,output in ipairs(plan.outputs) do plan.outputBySlot[SlotKey(output)]=output end
    for _,op in ipairs(plan.steps) do
        local key=SlotKey(op.source);local list=plan.sourcesBySlot[key]
        if not list then list={};plan.sourcesBySlot[key]=list end
        list[#list+1]=op
        -- An intermediate pile may later be split again. Only its final operation
        -- can publish this slot as an independent output.
        if plan.progressiveGroups then
            local source=plan.outputBySlot[key]
            local target=plan.outputBySlot[SlotKey(op.target)]
            if source then source.finalStep=op end
            if target then target.finalStep=op end
        end
    end
    for _,member in ipairs(plan.selection.members) do self:SelectionConfirmed(member) end
    if window and not B.View:Grouping(window) then
        for _,output in ipairs(plan.outputs) do B.View:PlaceSplit(output,plan.selection.members[1]) end
    end
    if #plan.steps==0 then return self:CompleteSelection() end
    if plan.rounds then return self:StartGroups(plan) end
    if YUI.IsForever and plan.mode=="groups" and self.splitObserver then
        local readyAt=InventoryActionTime()
        self.serialSplitTrace={observe=self.splitObserver,readyAt=readyAt}
        self.splitObserver("start",readyAt,nil,"serial")
    end
    return self:Start(plan.steps,plan.mode=="extract" and "extract" or "split")
end
function Actions:SelectionConfirmed(item,step)
    local plan=self.selection
    if not plan or not item then return end
    local key=SlotKey(item);local output=plan.outputBySlot[key]
    if output then
        output.guid=output.guid or item.guid
        if plan.progressiveGroups and not output.displayed and output.finalStep==step and item.count==output.count
            and not item.locked and (not output.guid or output.guid==item.guid)
            and B.Classification:SameStack(item,plan.selection.members[1]) then
            B.View:SeparateItems(plan.selection,{item})
            output.displayed=true
            plan.unseparated=plan.unseparated-item.count
            B.Runtime.splitDisplay=true
            B:QueueFlush()
        end
    end
    local operations=plan.sourcesBySlot[key]
    if operations then for _,op in ipairs(operations) do op.guid=op.guid or item.guid end end
end
local function StopOnTimeout()
    local transfer=Actions.transferResult
    Actions:Stop("timeout")
    if not transfer then B:Notify("error.timeout") end
end
local function TimedOut()
    local round=Actions.sortRound
    local placement=round and round.placement
    if not placement then
        if round and not round.bank and not round.compaction and round.receipts and #round.receipts>0 then
            local timer=Actions.timeout
            round.checkingDeadline=true
            B:Flush()
            round.checkingDeadline=nil
            if Actions.sortRound~=round or Actions.timeout~=timer then return end
        end
        StopOnTimeout();return
    end
    Actions.timeout=nil
    B.Stats.timers=B.Stats.timers-1
    placement.checkingDeadline=true
    if B:MarkPendingPlacementReads(round,true) then B:Flush()
    else Actions:ConfirmSortRound() end
    placement.checkingDeadline=nil
end
local function SetGuildManual(waiting,active)
    if waiting.guildManual==active then return end
    waiting.guildManual=active
    if B.GuildInventory and B.GuildInventory.RefreshManualTarget then B.GuildInventory:RefreshManualTarget() end
end
local function RetireManualOffer(waiting)
    waiting.guildCanOffer=nil
    if waiting.guildManual then
        waiting.guildDeadline=math.min(waiting.guildDeadline,GetTime()+3)
        SetGuildManual(waiting,nil)
    end
end
function Actions:InterruptGuildTransfer()
    if not self.guildTransfer then return false end
    if self.guildInterrupted then return true end
    self.guildInterrupted=true
    local waiting=self.waiting
    if waiting then
        RetireManualOffer(waiting)
        -- SubmitGuildWithdraw rechecks the receipt identity between the
        -- native split/pickup and the bag placement. Leave that cursor alone.
        if waiting.submitting and not waiting.operation.autoStore and A.CursorBusy() then self:Stop() end
    elseif not self.guildDispatch then
        self:Stop()
    end
    return true
end
local function SameManualBaseline(waiting,source,target)
    if not Same(source,waiting.source) or waiting.source.guid and source.guid~=waiting.source.guid then return false end
    if not waiting.target then return not target end
    return target and target.count==waiting.target.count and B.Deposit:GuildStackMatches(source,target)
end
-- This is a second, explicit player action on the original physical cell.
-- The normal receipt path never writes there. Recheck the preset, session,
-- available room and actual bag location both before offering and on click.
local function ManualGuildSource(actions,waiting)
    local op=waiting.operation
    local w=B.View.windows["live-guild"]
    if actions.guildInterrupted or actions.waiting~=waiting or not actions.queue or actions.queue[actions.index]~=op
        or not w or not w.open or w.guildMode~="items" or w.page~=op.target.bag
        or not B.Deposit:GuildReceiptAllowed(op) or not A.CursorBusy() then return end
    local cursor=A.CursorItem()
    if not cursor or cursor.itemID~=op.itemID or not B.Deposit:SameGuildLink(cursor.link,op.link)
        or A.ItemOnCursorFromSlot(op.source.bag,op.source.slot,op.itemID,true)~=true then return end
    local source,sourceError=A.Slot(op.source.bag,op.source.slot)
    local target,targetError=B.Deposit:ReadTarget(op.target)
    if sourceError or targetError or not SameManualBaseline(waiting,source,target) then return end
    -- A carried item can be locked by its own cursor pickup. Player locks,
    -- favorites, quest status and destination locks still apply.
    if source.quest or actions:Protected(waiting.source) or target and actions:Protected(target)
        or not B.Deposit:Validate(op,target) then return end
    return source
end
local function ArmGuildReceipt(actions,waiting)
    waiting.guildDeadline=GetTime()+(waiting.operation.guildWithdraw and 10 or 3)
    local delay=.12
    local function Check()
        if actions.waiting~=waiting then return end
        local now=GetTime()
        actions:Confirm(now>=waiting.guildDeadline)
        if actions.waiting~=waiting then return end
        if now>=waiting.guildDeadline then
            local canOffer=waiting.guildCanOffer and ManualGuildSource(actions,waiting)
            if actions.waiting~=waiting then return end
            if canOffer and not actions.guildInterrupted then
                local target=waiting.operation.target
                waiting.guildCanOffer=nil
                waiting.guildDeadline=now+30
                SetGuildManual(waiting,true)
                if actions.waiting==waiting and waiting.guildManual and YUI.Print then
                    YUI:Print(string.format(B:T("guild.manual_place"),target.bag,math.floor((target.slot-1)/7)+1,(target.slot-1)%7+1))
                end
            elseif waiting.guildManual then actions:Stop();return
            else TimedOut();return end
        end
        if actions.waiting~=waiting then return end
        delay=math.min(delay*2,.75,waiting.guildDeadline-now)
        actions.timeout=C_Timer.NewTimer(delay,Check)
    end
    actions.timeout=C_Timer.NewTimer(delay,Check)
    B.Stats.timers=B.Stats.timers+1
end
function Actions:PlaceWaitingGuildStack(tab,slot)
    local waiting=self.waiting
    if not waiting or not waiting.guildManual then return false end
    local op=waiting.operation
    if op.target.bag~=tab or op.target.slot~=slot then return false end
    if GetTime()>=waiting.guildDeadline then
        self:Confirm(true)
        if self.waiting==waiting then self:Stop() end
        return false
    end
    -- Consume the offer before refreshing the marker or invoking native code.
    -- A nested click or CURSOR_CHANGED cannot submit this action a second time.
    RetireManualOffer(waiting)
    local source=ManualGuildSource(self,waiting)
    if self.waiting~=waiting then return false end
    if not source then self:Confirm();return false end
    waiting.guildDeadline=GetTime()+3
    local _,submitted=B.Deposit:PickupTarget(op.target,source)
    if self.waiting==waiting then self:Confirm() end
    return submitted==true
end
local function SortSettled() Actions:FinishNativeSort() end
local function TrackCarryMove(batch,from,to)
    if not batch then return end
    if batch.kind=="bank" then
        if not batch.bags[from.bag] then B.Cache:RequireLocalBagRead("bank",from.bag,"sort") end
        if from.bag~=to.bag and not batch.bags[to.bag] then B.Cache:RequireLocalBagRead("bank",to.bag,"sort") end
    end
    batch.bags[from.bag],batch.bags[to.bag]=true,true
end
function Actions:StartGroups(plan)
    if self.queue or self.nativeSort or A.InCombat() or A.CursorBusy() or not plan or not plan.rounds then return false end
    self:CancelDelete();self.queue,self.kind,self.groupPlan,self.roundIndex=plan.steps,"split-groups",plan,1
    if YUI.IsForever then self.carryBatch={bags={}};B.View:RefreshItemInputs() end
    B:RefreshSortSpace()
    if YUI.IsForever then return self:StartSplitBatch(plan) end
    return self:SendSplitRound()
end
function Actions:SendSplitRound()
    local round=self.groupPlan and self.groupPlan.rounds[self.roundIndex]
    if not round then if self.selection then return self:CompleteSelection() end;self:Stop();return true end
    if not B.active or A.InCombat() or A.CursorBusy() then self:Stop();return false end
    for _,op in ipairs(round) do
        op.confirmed=nil
        local source=A.Slot(op.source.bag,op.source.slot)
        local target,err=B.Deposit:ReadTarget(op.target)
        if not source or source.itemID~=op.itemID or source.link~=op.link or source.count~=op.sourceCount
            or op.guid and source.guid~=op.guid or self:Protected(source) or target or err then self:Stop();return false end
        op.sourceGUID=source.guid
    end
    local waiting={};self.roundWaiting=waiting;self.roundBySlot={};self.roundRemaining=#round;self.sendingRound=true
    for _,op in ipairs(round) do
        TrackCarryMove(self.carryBatch,op.source,op.target)
        if not A.Split(op.source.bag,op.source.slot,op.count) or not A.CursorBusy() then self:Stop();return false end
        B.Deposit:PickupTarget(op.target)
        if A.CursorBusy() then A.Pickup(op.source.bag,op.source.slot);self:Stop();return false end
        waiting[#waiting+1]=op
        self.roundBySlot[tostring(op.source.bag)..":"..op.source.slot]=op
        self.roundBySlot[tostring(op.target.bag)..":"..op.target.slot]=op
        if not self.selection then B.View:PlaceSplit(op.target,op.source,op) end
    end
    self.sendingRound=nil
    self.timeout=C_Timer.NewTimer(3,TimedOut);B.Stats.timers=B.Stats.timers+1
    self:ConfirmGroups()
    return true
end
function Actions:ConfirmGroupSlot(bag,slot)
    local op=self.roundBySlot and self.roundBySlot[tostring(bag)..":"..slot]
    if op then self:ConfirmGroups(op) end
end
local function ReadSplitReceipt(self,op)
    local source=op.splitSourceReceipt or A.Slot(op.source.bag,op.source.slot)
    local target,targetError=B.Deposit:ReadTarget(op.target)
    local sourceMatches=source and source.itemID==op.itemID and source.link==op.link
        and source.count==op.sourceCount-op.count and not source.locked
    local targetFields=target and target.itemID==op.itemID and target.link==op.link and target.count==op.count
    local targetMatches=targetFields and not target.locked
    local batch=self.splitBatch
    local earlySource
    if batch then
        local sourceReady=sourceMatches and source.bound==op.splitBound and (not op.sourceGUID or source.guid==op.sourceGUID)
        local targetIdentity=targetFields and target.bound==op.splitBound and (not op.sourceGUID or target.guid~=op.sourceGUID)
        if batch.observe then
            ObserveMoveSlots(batch,op,sourceReady,
                targetMatches and targetIdentity and (not self.selection or not op.sourceGUID or target.guid~=nil))
        end
        if sourceReady and op.sourceGUID and not targetError and (not target or targetIdentity) then earlySource=source end
    end
    if not sourceMatches or not targetMatches then return nil,nil,earlySource end
    if op.sourceGUID and source.guid~=op.sourceGUID then
        if source.guid or not self.splitBatch then self:Stop("changed") end
        return
    end
    if self.selection and op.sourceGUID and not target.guid then return nil,nil,earlySource end
    if self.splitBatch and (source.bound~=op.splitBound or target.bound~=op.splitBound
        or op.sourceGUID and target.guid==op.sourceGUID) then self:Stop("changed");return end
    return source,target
end
local function PublishSplitReceipt(self,op,source,target)
    self:SelectionConfirmed(source,op);self:SelectionConfirmed(target,op)
    if self.selection and self.selection.progressiveGroups then B:MarkMoveReceipt(op) end
    B.View:ConfirmSplitPlacement(target)
    if target.new then A.ClearNewItem(target.bag,target.slot) end
end
local function ConfirmSplitOperation(self,op)
    if op.confirmed then return end
    local source,target=ReadSplitReceipt(self,op)
    if not source then return end
    PublishSplitReceipt(self,op,source,target)
    op.confirmed=true;self.roundRemaining=self.roundRemaining-1
end
function Actions:ConfirmGroups(single)
    if self.sendingRound or not self.roundWaiting then return end
    if single then ConfirmSplitOperation(self,single)
    else
        for _,op in ipairs(self.roundWaiting) do
            ConfirmSplitOperation(self,op)
            if not self.groupPlan then return end
        end
    end
    if not self.groupPlan then return end
    if self.roundRemaining>0 then return end
    if self.timeout then self.timeout:Cancel();self.timeout=nil;B.Stats.timers=math.max(0,B.Stats.timers-1) end
    self.roundWaiting=nil;self.roundIndex=self.roundIndex+1;self:SendSplitRound()
end

local function QueueSplitStep(batch,op,readyAt)
    op.splitReadyAt=readyAt
    batch.ready[#batch.ready+1]=op
end
function Actions:StartSplitBatch(plan)
    local started=InventoryActionTime()
    local batch={ready={},head=1,pending={},sourceBarriers={},remaining=#plan.steps,observe=self.splitObserver}
    local producer={}
    for index,op in ipairs(plan.steps) do
        local from,to=SlotKey(op.source),SlotKey(op.target)
        local parent=producer[from]
        op.splitIndex,op.splitParent,op.splitChildren=index,parent and parent.splitIndex,nil
        op.splitSourceKey,op.splitSourceChild,op.splitSourceReceipt=from,nil,nil
        op.splitDeferred,op.splitEarlyReceipt=nil,nil
        op.sourceReadyReported,op.targetReadyReported=nil,nil
        if parent then
            parent.splitChildren=parent.splitChildren or {}
            parent.splitChildren[#parent.splitChildren+1]=op
            if parent.splitSourceKey==from then parent.splitSourceChild=op end
        else
            QueueSplitStep(batch,op,started)
        end
        producer[from],producer[to]=op,op
    end
    self.splitBatch=batch
    if batch.observe then batch.observe("start",started,nil,"balanced") end
    return self:AdvanceSplitBatch()
end
local function SendSplitStep(self,batch,op)
    local from,to=op.source,op.target
    local source=A.Slot(from.bag,from.slot)
    local target,err=B.Deposit:ReadTarget(to)
    local early=op.splitEarlyReceipt
    if not source or source.itemID~=op.itemID or source.link~=op.link or source.count~=op.sourceCount
        or op.guid and source.guid~=op.guid or self:Protected(source) or target or err
        or early and (source.guid~=early.guid or source.bound~=early.bound)
        or B:GetConfig().locks[SlotKey(to)] or not A.Fits(source,B.Model.bags[to.bag]) then return false end
    op.sourceGUID,op.splitBound=source.guid,source.bound
    TrackCarryMove(self.carryBatch,from,to)
    local submitted=InventoryActionTime()
    if batch.observe then batch.observe("submit",submitted,op) end
    if not A.Split(from.bag,from.slot,op.count) or self.splitBatch~=batch or not A.CursorBusy() then return false end
    local current,readError=B.Deposit:ReadTarget(to)
    if not current and not readError and not A.InCombat() and not B:GetConfig().locks[SlotKey(to)]
        and A.ItemOnCursorFromSlot(from.bag,from.slot,op.itemID) then B.Deposit:PickupTarget(to) end
    if self.splitBatch~=batch then return false end
    if A.CursorBusy() then
        if A.ItemOnCursorFromSlot(from.bag,from.slot,op.itemID,true)==true then A.Pickup(from.bag,from.slot) end
        return false
    end
    op.splitDeadline=submitted+3
    batch.pending[#batch.pending+1]=op
    if not self.selection then B.View:PlaceSplit(to,from,op) end
    return true
end
local function WakeSplitBatch()
    Actions.timeout=nil
    B.Stats.timers=math.max(0,B.Stats.timers-1)
    if Actions.splitBatch then B:QueueFlush() end
end
local function ReleaseSplitChildren(batch,op,confirmed)
    local barriers=batch.sourceBarriers
    if barriers[op.splitSourceKey]==op then
        barriers[op.splitSourceKey]=nil
        if op.splitDeferred then QueueSplitStep(batch,op.splitDeferred,confirmed) end
    end
    if not op.splitChildren then return end
    for _,child in ipairs(op.splitChildren) do
        if not op.splitSourceReceipt or child~=op.splitSourceChild then
            local barrier=barriers[child.splitSourceKey]
            -- Even an already confirmed younger move must wait for the
            -- older destination before this source can advance a second time.
            if barrier then barrier.splitDeferred=child
            else QueueSplitStep(batch,child,confirmed) end
        end
    end
end
function Actions:AdvanceSplitBatch()
    local batch=self.splitBatch
    if not batch or self.sendingRound then return end
    if not B.active or A.InCombat() or A.CursorBusy() then self:Stop();return false end
    self.sendingRound=true
    local pending=batch.pending
    local kept=0
    for _,op in ipairs(pending) do
        local source,target,earlySource=ReadSplitReceipt(self,op)
        if self.splitBatch~=batch then return false end
        if source then
            local confirmed=InventoryActionTime()
            if batch.observe then batch.observe("confirm",confirmed,op) end
            PublishSplitReceipt(self,op,source,target)
            if self.splitBatch~=batch then return false end
            ReleaseSplitChildren(batch,op,confirmed)
            batch.remaining=batch.remaining-1
        else
            if InventoryActionTime()>=op.splitDeadline then TimedOut();return false end
            local child=op.splitSourceChild
            if earlySource and child and not op.splitSourceReceipt and not batch.sourceBarriers[op.splitSourceKey] then
                -- This receipt keeps the original source count even after
                -- the next move consumes more from that same physical stack.
                op.splitSourceReceipt=earlySource
                batch.sourceBarriers[op.splitSourceKey]=op
                child.splitEarlyReceipt=earlySource
                QueueSplitStep(batch,child,InventoryActionTime())
            end
            kept=kept+1
            pending[kept]=op
        end
    end
    for index=#pending,kept+1,-1 do pending[index]=nil end
    if batch.remaining==0 then
        if self.selection then return self:CompleteSelection() end
        self:Stop("complete");return true
    end
    -- Break up local command submission without waiting for unrelated receipts.
    local deadline=InventoryActionTime()+.002
    while batch.head<=#batch.ready do
        local op=batch.ready[batch.head]
        if A.InCombat() or A.CursorBusy() or not SendSplitStep(self,batch,op) then
            if self.splitBatch==batch then self:Stop("changed");B:Notify("error.changed") end
            return false
        end
        batch.head=batch.head+1
        if InventoryActionTime()>=deadline then break end
    end
    self.sendingRound=nil
    local expires=pending[1] and pending[1].splitDeadline
    if self.timeout and batch.expires~=expires then
        self.timeout:Cancel();self.timeout=nil;B.Stats.timers=math.max(0,B.Stats.timers-1)
    end
    batch.expires=expires
    if expires and not self.timeout then
        self.timeout=C_Timer.NewTimer(math.max(0,expires-InventoryActionTime()),WakeSplitBatch)
        B.Stats.timers=B.Stats.timers+1
    end
    if batch.head<=#batch.ready or #pending>kept then B:QueueFlush() end
    return true
end
function Actions:FinishNativeSort()
    if not self.nativeSort then return end
    local bank=self.nativeSort=="bank"
    if self.sortTimer then self.sortTimer:Cancel();self.sortTimer=nil;B.Stats.timers=math.max(0,B.Stats.timers-1) end
    self.nativeSort=nil
    if B.active then
        B:ReadAll(false)
        if bank then
            B.BankView:Refresh("bank",true)
            if B.bankOpen and A.CanUsePersonalBank() then
                self:Start(self:PlanRestack(true),"bank-restack")
            end
            B.View:RefreshItemInputs()
        else
            self:Start(self:PlanRestack(),"restack")
            B.View:Invalidate();B:RefreshVisible(true)
        end
    end
end
function Actions:ClearRecent(ids)
    if not B.active then return false end
    if B.Stats.pendingRefresh then B:ReadAll(false) end
    self:CancelDelete()
    local changed=false
    B.Model.recentCursor=nil
    for _,id in ipairs(ids or A.GetCarryBags(true)) do
        local bag=B.Model.bags[id]
        if bag then for _,item in pairs(bag.slots) do
            if item.new then
                A.ClearNewItem(item.bag,item.slot);item.new=false;item.revision=item.revision+1
                B.Model:Tag(item);changed=true
            end
        end end
    end
    if changed then
        B.Model.revision=B.Model.revision+1
        if not A.InCombat() then B.View:Invalidate(true) end
        B:RefreshVisible(true)
    end
    return changed
end
function Actions:IsSortingBank()
    return self.nativeSort=="bank" or self.kind=="bank-sort" or self.kind=="bank-restack"
end
function Actions:BlocksItemInput()
    return self.sortRound~=nil or self.carryBatch~=nil or B.Runtime.finalCarryBatch~=nil
        or self.externalCarrySort and self.externalCarrySort.bank
        or self.kind=="deposit" or self.kind=="bag-remove" or self:IsSortingBank()
        or self.selection and self.selection.progressiveGroups or false
end
function Actions:IsPersonalBatch()
    local queue=self.queue
    return self.kind=="deposit" and queue and #queue>1 and queue[1].personalTransfer==true
end
function Actions:Start(steps,kind,transferTotal)
    if self.queue or self.nativeSort or self.externalCarrySort and self.externalCarrySort.bank
        or A.InCombat() or A.CursorBusy() or #steps==0 and kind~="bag-remove" then return false end
    self:CancelDelete()
    self.queue,self.index,self.kind=steps,1,kind
    B:RefreshSortSpace()
    self.transferResult=transferTotal and {total=transferTotal,confirmed=0} or nil
    local first=steps[1]
    if self.transferResult and self:IsPersonalBatch() then
        self.transferResult.snapshots={owner=B.Cache.player,key=B.Cache.playerKey,touched={},complete={}}
    end
    if kind=="deposit" and first and (first.guildQuota or first.guildWithdraw) then
        self.guildTransfer=true
        B.View:SetGuildTransferEscape(true)
    end
    if self:BlocksItemInput() then
        B.View:CloseItemSplitDialogs()
        B.View:RefreshItemInputs()
    end
    if B.bankOpen or B.guildOpen then B.BankView:UpdateBankControls(true) end
    return self.queue==steps and self:Step()
end
function Actions:MovementBlocked(item)
    if self.kind=="bag-remove" then return not item or item.locked or B:GetConfig().locks[item.key] end
    return self:Protected(item)
end
function Actions:ObserveGuildCursor()
    local waiting=self.waiting
    local operation=self.queue and self.queue[self.index]
    if not operation or not operation.guildOwner or operation.guildWithdraw then return false end
    if not A.CursorBusy() then
        if waiting and (waiting.guildCanOffer or waiting.guildManual) then RetireManualOffer(waiting) end
        return false
    end
    local cursor=A.CursorItem()
    local source=waiting and waiting.source or operation
    -- A positive foreign location is meaningful even for an identical stack.
    -- Missing location data while the client settles does not confirm a move.
    if cursor and (cursor.itemID~=source.itemID or cursor.link and not B.Deposit:SameGuildLink(cursor.link,source.link)
        or A.ItemOnCursorFromSlot(operation.source.bag,operation.source.slot,source.itemID,true)==false) then
        local notifiedByStop=waiting or self.guildDispatch
        self:Stop()
        if not notifiedByStop then B:Notify("guild.bag_check_cursor") end
    end
    return true
end
local function SubmitStep(self)
    local queue,index,transfer=self.queue,self.index,self.transferResult
    local operation=queue and queue[index]
    if operation and operation.guildOwner and (self.waiting or self.timeout or self.guildDispatch or self.guildInterrupted) then return false end
    if not operation then
        if self.removalPlan then
            self.removalFinal=true;self.waiting={removal=true}
            self.timeout=C_Timer.NewTimer(3,TimedOut);B.Stats.timers=B.Stats.timers+1
            if not B.BagRemoval:Finish(self.removalPlan) then self:Stop();B:Notify("error.operation");return false end
            self:Confirm();return true
        end
        if self.selection then return self:CompleteSelection() end
        self:Stop("complete")
        return true
    end
    if not B.active or A.InCombat() or A.CursorBusy()
        or self:IsSortingBank() and (not B.bankOpen or not A.CanUsePersonalBank())
        or self.kind=="deposit" and not operation.personalTransfer and A.Context()~="bank" then self:Stop();return false end
    if self.removalPlan and not B.BagRemoval:Valid(self.removalPlan) then self:Stop();B:Notify("error.changed");return false end
    if operation.guildWithdraw then
        -- Install the receipt before either native call. Synchronous inventory
        -- events cannot confirm or dispatch this operation a second time.
        local waiting={operation=operation,submitting=true}
        self.waiting=waiting
        local submitted=B.Deposit:SubmitGuildWithdraw(operation,waiting)
        if self.waiting~=waiting then return false end
        if not submitted then self:Stop();return false end
        waiting.submitting=nil
        ArmGuildReceipt(self,waiting)
        return true
    end
    local source=A.Slot(operation.source.bag,operation.source.slot)
    local destination,readError=B.Deposit:ReadTarget(operation.target)
    if readError then self:Stop();return false end
    if not source or source.itemID~=operation.itemID or source.link~=operation.link or source.locked or self:MovementBlocked(source)
        or operation.sourceCount and source.count~=operation.sourceCount
        or destination and (destination.locked or self:MovementBlocked(destination)) then self:Stop();return false end
    if operation.checkSortSlot and (B:GetConfig().locks[SlotKey(operation.target)]
        or not operation.combine and not operation.swapTarget and destination
        or not A.Fits(source,B.Model.bags[operation.target.bag],self:IsSortingBank())) then self:Stop();return false end
    if self.kind=="bag-remove" and (destination and not operation.combine
        or B:GetConfig().locks[SlotKey(operation.target)]
        or operation.guid and source.guid~=operation.guid
        or not A.Fits(source,B.Model.bags[operation.target.bag])) then self:Stop();return false end
    if self.kind=="deposit" and not B.Deposit:Validate(operation,destination) then self:Stop();return false end
    if operation.combine and (not destination or (source.maxStack or 1)<=1 or source.charges~=destination.charges
        or source.maxCharges and source.charges==nil or destination.itemID~=operation.itemID or destination.link~=operation.link
        or destination.count~=operation.targetCount or not A.Fits(source,B.Model.bags[destination.bag])) then self:Stop();return false end
    if operation.swapTarget and (not Same(destination,operation.swapTarget)
        or not A.Fits(source,B.Model.bags[destination.bag]) or not A.Fits(destination,B.Model.bags[source.bag])) then self:Stop();return false end
    if (self.kind=="split" or self.kind=="extract") and destination and not operation.combine then self:Stop();return false end
    if operation.guid and source.guid and operation.guid~=source.guid or operation.bound~=nil and operation.bound~=source.bound then self:Stop();return false end
    if operation.count and (operation.count>=source.count or operation.count<1) then self:Stop();return false end
    local equipmentCount=operation.guildQuota and B.Deposit:GuildEquipmentReceiptCount(operation,source,destination)
    local guild=operation.target.kind=="guild"
    local personalActive,cursorFromSource
    if operation.personalTransfer then
        -- Start may reuse the same steps table after a synchronous Stop.
        personalActive=function()
            if self.queue~=queue or self.index~=index or queue[index]~=operation or self.transferResult~=transfer then return false end
            if B.active and B.bankOpen and not A.InCombat() and A.ActiveBankKind()=="bank" and A.CanUsePersonalBank() then return true end
            self:Stop()
            return false
        end
        cursorFromSource=function()
            local cursor=A.CursorItem()
            if not cursor or cursor.itemID~=source.itemID then return false end
            if cursor.link and source.link and not B.Deposit:SameGuildLink(cursor.link,source.link) then return false end
            return A.ItemOnCursorFromSlot(source.bag,source.slot,source.itemID,true)
        end
        if not personalActive() then return false end
        if A.CursorBusy() then self:Stop();return false end
    end
    if guild then self.guildDispatch=operation end
    local trace=self.serialSplitTrace
    if trace then
        operation.splitIndex,operation.splitParent,operation.splitReadyAt=index,index>1 and index-1 or nil,trace.readyAt
        trace.observe("submit",InventoryActionTime(),operation)
    end
    local pickupCallOK
    if operation.count then pickupCallOK=A.Split(source.bag,source.slot,operation.count) else pickupCallOK=A.Pickup(source.bag,source.slot) end
    if personalActive then
        if not personalActive() then return false end
        -- The native call has no receipt. A matching item on the previously
        -- empty cursor may lack a location after a synchronous pickup or split.
        if not pickupCallOK or cursorFromSource()==false then self:Stop();return false end
        if operation.equipmentMove then
            -- A pickup hook can change the intended empty slot before the drop.
            local occupant,err=B.Deposit:ReadTarget(operation.target)
            if not personalActive() then return false end
            if occupant or err then
                if cursorFromSource()==true then A.Pickup(source.bag,source.slot) end
                if personalActive() then self:Stop() end
                return false
            end
        end
    end
    if guild and (self.queue~=queue or queue[self.index]~=operation) then return false end
    if guild and self.guildInterrupted then self:Stop();return false end
    if not A.CursorBusy() then self:Stop();return false end
    if guild and A.ItemOnCursorFromSlot(source.bag,source.slot,source.itemID,true)==false then
        self:Stop();return false
    end
    local targetCallOK,submitted,cursorMatched=B.Deposit:PickupTarget(operation.target,source)
    if guild then
        if self.queue~=queue or queue[self.index]~=operation then return false end
        if not submitted or not operation.guildOwner and A.CursorBusy() then
            -- Restore only an unsubmitted whole stack with a verified origin.
            local cursor=A.CursorBusy() and A.CursorItem()
            if not submitted and not self.guildInterrupted and operation.guildOwner and B.Deposit:GuildReceiptAllowed(operation)
                and not operation.count and cursor and cursor.itemID==source.itemID
                and B.Deposit:SameGuildLink(cursor.link,source.link) and A.ItemOnCursorFromSlot(source.bag,source.slot,source.itemID,true) then
                local origin,err=A.Slot(source.bag,source.slot)
                if not origin and not err and B.Deposit:GuildSourceSlotExists(source.bag,source.slot) then A.Pickup(source.bag,source.slot) end
            end
            self:Stop()
            return false
        end
        self.guildDispatch=nil
    elseif personalActive then
        if not personalActive() then return false end
        if A.CursorBusy() then
            if cursorFromSource()==true then
                A.Pickup(source.bag,source.slot)
                if not personalActive() then return false end
            end
            self:Stop();return false
        end
        if not targetCallOK then self:Stop();return false end
    elseif A.CursorBusy() then
        A.Pickup(source.bag,source.slot)
        if A.CursorBusy() then self:Stop();return false end
    end
    if not self.selection and (self.kind=="split" or self.kind=="extract") then B.View:PlaceSplit(operation.target,source) end
    local moved=operation.count or source.count
    local guildReceipt=operation.target.kind=="guild" and operation.guildOwner~=nil
    local merged=destination and destination.itemID==source.itemID and (destination.link==source.link
        or guildReceipt and B.Deposit:GuildStackMatches(source,destination))
    local expectedTarget=moved
    if merged then
        expectedTarget=destination.count+moved
        if not guildReceipt then expectedTarget=math.min(destination.maxStack or 1,expectedTarget) end
    end
    local expectedSource=source.count-(merged and expectedTarget-destination.count or moved)
    self.waiting={source=source,target=destination,operation=operation,merged=merged,guildReceipt=guildReceipt,
        expectedSource=expectedSource,expectedTarget=expectedTarget,equipmentCount=cursorMatched and equipmentCount,
        targetGUID=destination and destination.guid or not operation.count and source.guid or nil}
    if guildReceipt then
        self.waiting.guildCanOffer=not self.guildInterrupted and self.kind=="deposit" and self.transferResult~=nil and #queue>1 and not operation.count
            and not operation.target.choiceSession and operation.guildQuota~=nil and B.Deposit:IsGuildPreset(operation.preset)
            and A.CursorBusy() or nil
        self:ObserveGuildCursor()
        if not self.waiting then return false end
        ArmGuildReceipt(self,self.waiting)
    elseif not self.equipmentTransfer then
        self.timeout=C_Timer.NewTimer(3,TimedOut);B.Stats.timers=B.Stats.timers+1
    end
    return true
end

-- Independent whole items do not need to wait for each other's bag events.
-- Keep a receipt per physical destination; a native call alone is not a receipt.
local function ArmEquipmentTimeout(actions,round,delay)
    actions.timeout=C_Timer.NewTimer(delay,function()
        if actions.equipmentTransfer~=round then return end
        local left=3-(GetTime()-round.lastProgress)
        if left<=0 then
            round.finalRead=true
            B:Flush()
            if actions.equipmentTransfer~=round then return end
            round.finalRead=nil
            left=3-(GetTime()-round.lastProgress)
        end
        if left<=0 then actions:Stop("timeout") else ArmEquipmentTimeout(actions,round,left) end
    end)
end
function Actions:Step()
    if self.equipmentTransfer or self.waiting and self.waiting.operation and self.waiting.operation.personalTransfer then return false end
    local queue,index=self.queue,self.index
    local first=queue and queue[index]
    if not first or not first.equipmentMove or not queue[index+1] or not queue[index+1].equipmentMove then
        return SubmitStep(self)
    end
    local round={targets={},bags={},sending=true}
    self.equipmentTransfer=round
    local used={}
    local op=first
    while op and op.equipmentMove do
        local from,to=SlotKey(op.source),SlotKey(op.target)
        if used[from] or used[to] or from==to then break end
        used[from],used[to]=true,true
        round.bags[op.source.bag],round.bags[op.target.bag]=true,true
        round.submitting=op
        if not SubmitStep(self) or self.equipmentTransfer~=round then return false end
        round.targets[to]=self.waiting
        self.waiting,round.submitting=nil,nil
        self.index=self.index+1
        op=queue[self.index]
    end
    round.sending=nil
    round.lastProgress=GetTime()
    ArmEquipmentTimeout(self,round,3)
    B.Stats.timers=B.Stats.timers+1
    B:QueueFlush()
    return true
end

function Actions:ConfirmEquipmentTransfer(round,updates)
    if round.sending or self.equipmentTransfer~=round then return end
    if not B.bankOpen or A.InCombat() or A.ActiveBankKind()~="bank" or not A.CanUsePersonalBank() then
        self:Stop()
        return
    end
    local advanced=false
    for key,receipt in pairs(round.targets) do
        local op=receipt.operation
        local from,to=op.source,op.target
        local source,target=B.Model.bags[from.bag],B.Model.bags[to.bag]
        local landed=target and target.slots[to.slot]
        if B.Runtime.readable[from.bag] and B.Runtime.readable[to.bag]
            and source and source.kind==(to.kind=="bank" and "bags" or "bank")
            and target and target.kind==to.kind and from.slot<=source.capacity and to.slot<=target.capacity
            and not source.slots[from.slot] and landed and not landed.locked
            and landed.count==1 and landed.itemID==op.itemID and landed.link==op.link
            and (not receipt.targetGUID or landed.guid==receipt.targetGUID) then
            round.targets[key]=nil
            self.transferResult.confirmed=self.transferResult.confirmed+1
            advanced=true
            if receipt.displayPending then
                local w=B.View.windows[to.kind=="bank" and "live-bank" or "player"]
                if w and w.open and updates[w]~="layout" then
                    B.View:MarkTransferSlot(w,to.bag,to.slot)
                    updates[w]="category"
                end
            end
        end
    end
    if advanced then
        round.lastProgress=GetTime()
        B.View:ShowTransferProgress(self.transferResult)
    end
    if next(round.targets) then return end
    self.timeout:Cancel();self.timeout=nil;B.Stats.timers=B.Stats.timers-1
    self.equipmentTransfer=nil
    self:Step()
end
local function PaceGuildQueue(self,queue,index,batch)
    if self.queue~=queue or self.index~=index then return true end
    if self.guildInterrupted then self:Stop();return true end
    if not queue[index] then return false end
    local delay=guildBatchInterval
    if batch and (index-1)%guildBatchSteps==0 then delay=delay+guildBatchPause end
    local timer
    timer=C_Timer.NewTimer(delay,function()
        if self.timeout~=timer or self.queue~=queue or self.index~=index then return end
        self.timeout=nil
        B.Stats.timers=math.max(0,B.Stats.timers-1)
        if not B.Deposit:GuildReceiptAllowed(queue[index]) then self:Stop();return end
        self:Step()
    end)
    self.timeout=timer
    B.Stats.timers=B.Stats.timers+1
    return true
end

function Actions:Confirm(finalRead)
    if self.equipmentTransfer then return end
    if self.kind=="split-groups" then return self:ConfirmGroups() end
    if self.removalFinal then
        local confirmed=B.BagRemoval:Confirmed(self.removalPlan)
        if confirmed==true then self:Stop()
        elseif confirmed==false then self:Stop();B:Notify("error.changed") end
        return
    end
    local waiting=self.waiting
    if not waiting then return end
    local op=waiting.operation
    if op.guildWithdraw then
        if waiting.submitting then return end
        local confirmed=B.Deposit:ConfirmGuildWithdraw(waiting)
        if self.waiting~=waiting then return end
        if confirmed==false then self:Stop();return end
        if not confirmed then return end
        local queue,index=self.queue,self.index+1
        self.transferResult.confirmed=self.transferResult.confirmed+(op.count or op.sourceCount)
        self.timeout:Cancel();self.timeout=nil;B.Stats.timers=math.max(0,B.Stats.timers-1)
        self.waiting,self.index=nil,index
        if not B.Deposit:CheckGuildWithdrawal(waiting) then B.Deposit:SnapshotGuild(false,op.source.bag) end
        if B.Deposit.withdrawal and B.Deposit.withdrawal.batch==waiting then B.Deposit.withdrawal=nil end
        B.BankView:Refresh("guild")
        if not PaceGuildQueue(self,queue,index,true) then self:Step() end
        return
    end
    local source,sourceError=A.Slot(waiting.operation.source.bag,waiting.operation.source.slot)
    local target,readError
    if waiting.guildReceipt then target,readError=B.Deposit:ReadGuildReceipt(waiting.operation)
    else target,readError=B.Deposit:ReadTarget(waiting.operation.target) end
    if self.waiting~=waiting then return end
    local trace=self.serialSplitTrace
    if trace then
        local expected=waiting.source
        ObserveMoveSlots(trace,op,
            not sourceError and (waiting.expectedSource==0 and not source
                or source and not source.locked and source.itemID==expected.itemID and source.link==expected.link
                    and source.count==waiting.expectedSource and (not expected.guid or expected.guid==source.guid)),
            not readError and target and not target.locked and target.itemID==expected.itemID and target.link==expected.link
                and target.count==waiting.expectedTarget and (not expected.guid or target.guid~=nil)
                and (not waiting.targetGUID or waiting.targetGUID==target.guid))
    end
    if waiting.guildReceipt and readError=="session" then self:Stop();return end
    if (waiting.guildCanOffer or waiting.guildManual) and not readError and not sourceError
        and not SameManualBaseline(waiting,source,target) then RetireManualOffer(waiting) end
    if waiting.guildReceipt and self:ObserveGuildCursor() then return end
    if readError or (waiting.guildReceipt or self.transferResult) and sourceError then return end
    if waiting.operation.personalTransfer then
        if source and waiting.source.guid and not source.guid or target and waiting.targetGUID and not target.guid then return end
        if source and waiting.source.guid and source.guid~=waiting.source.guid
            or target and waiting.targetGUID and target.guid~=waiting.targetGUID then
            self:Stop()
            return
        end
    end
    if self.kind=="extract" or self.selection or self.kind=="bag-remove" then
        if waiting.source.guid and target and not target.guid then return end
        if source and waiting.source.guid and not source.guid or target and waiting.targetGUID and not target.guid then return end
        if source and waiting.source.guid and source.guid~=waiting.source.guid
            or target and waiting.targetGUID and target.guid~=waiting.targetGUID then
            self:Stop();B:Notify("error.changed");return
        end
        if target and target.itemID==waiting.source.itemID and target.link==waiting.source.link then waiting.targetGUID=waiting.targetGUID or target.guid end
    end
    local swapped=waiting.target and not waiting.merged
    local sourceOK=swapped and Same(source,{itemID=waiting.target.itemID,link=waiting.target.link,count=waiting.target.count,
        bag=waiting.source.bag,slot=waiting.source.slot})
        or not swapped and (waiting.expectedSource==0 and not source or source and source.itemID==waiting.source.itemID
        and (source.link==waiting.source.link or waiting.guildReceipt and B.Deposit:SameGuildLink(source.link,waiting.source.link))
        and source.count==waiting.expectedSource and not source.locked)
    if not sourceOK or not target or target.itemID~=waiting.source.itemID
        or target.count~=waiting.expectedTarget or target.locked then return end
    if waiting.guildReceipt then
        if source and waiting.source.guid and source.guid~=waiting.source.guid then return end
        if not source then
            -- A nil item also comes from out-of-range/unavailable containers.
            -- Only a readable bag that still contains this physical slot proves empty.
            if not B.Deposit:GuildSourceSlotExists(waiting.source.bag,waiting.source.slot) then return end
        end
        if not B.Deposit:GuildStackMatches(waiting.source,target,not waiting.target) then
            local omitted=B.Deposit:GuildEquipmentContextOmitted(waiting,target)
            if waiting.equipmentCount and not omitted then waiting.conflict=true end
            if not waiting.queryAt then
                waiting.queryAt=GetTime()
                waiting.querySent=A.QueryGuildPage and A.QueryGuildPage(waiting.operation.target.bag)
                if not finalRead or self.waiting~=waiting then return end
            end
            -- Slot events have no request ID. An unrelated one must not end
            -- a strict equipment/variant receipt ahead of its full reply.
            if finalRead~=true then return end
            if not (omitted and not source and not waiting.conflict and waiting.querySent and waiting.postQuerySlots
                and A.ItemCount(target.itemID)==waiting.equipmentCount-1) then
                self:Stop("guild-details")
                B.Deposit:RefreshGuildReceipt(waiting.operation,target)
                B:MarkBag(waiting.source.bag)
                return
            end
        end
        B.Deposit:RecordGuildOrigin(waiting.source,target)
    elseif target.link~=waiting.source.link then return end
    if trace then
        trace.readyAt=InventoryActionTime()
        trace.observe("confirm",trace.readyAt,op)
    end
    local transfer=self.transferResult
    if transfer then
        transfer.confirmed=transfer.confirmed+waiting.source.count-waiting.expectedSource
        if self:IsPersonalBatch() then B.View:ShowTransferProgress(transfer) end
    end
    if self.selection then
        if self.selection.progressiveGroups then
            self:SelectionConfirmed(source,op)
            B:MarkMoveReceipt(op)
        end
        self:SelectionConfirmed(target,op)
    end
    if self.kind=="split" or self.kind=="extract" then
        B.View:ConfirmSplitPlacement(target)
        if target.new then A.ClearNewItem(target.bag,target.slot) end
    end
    if self.timeout then self.timeout:Cancel();self.timeout=nil;B.Stats.timers=math.max(0,B.Stats.timers-1) end
    local queue,index=self.queue,self.index+1
    self.waiting,self.index=nil,index
    SetGuildManual(waiting,nil)
    if waiting.guildReceipt then
        B.Deposit:RefreshGuildReceipt(waiting.operation,target)
        B:MarkBag(waiting.source.bag)
        if PaceGuildQueue(self,queue,index,waiting.operation.guildQuota) then return end
    end
    if self.kind=="extract" and not self.selection then
        -- Pick up the confirmed independent stack, never its original source.
        local fresh=B.Deposit:ReadTarget(waiting.operation.target)
        if A.InCombat() or A.CursorBusy() or not Same(fresh,target) or fresh.locked or fresh.count~=waiting.expectedTarget
            or waiting.targetGUID and fresh.guid~=waiting.targetGUID then self:Stop();return end
        local ok=A.Pickup(fresh.bag,fresh.slot)
        self:Stop()
        if not ok or not A.CursorBusy() then B:Notify("error.operation") end
        return
    end
    if self.kind=="sort" or self.kind=="bank-sort" then
        self.queue=self:PlanSort(self.kind=="bank-sort");self.index=1
    elseif self.kind=="restack" or self.kind=="bank-restack" then
        self.queue=self:PlanRestack(self.kind=="bank-restack");self.index=1
    end
    self:Step()
end
local function CancelBankRecoveryCheck(recovery)
    if not recovery or not recovery.timer then return end
    recovery.timer:Cancel();recovery.timer=nil
    B.Stats.timers=B.Stats.timers-1
end

function Actions:Stop(reason,carryReconciled)
    if not B.active or not B.bankOpen then CancelBankRecoveryCheck(self.bankSortRecovery) end
    local wasRunning=self.queue~=nil or self.nativeSort~=nil
    local personalBatch=self:IsPersonalBatch()
    if self.guildInterrupted and reason=="timeout" then reason="cancelled" end
    local sortRound=self.sortRound
    local carryBatch=self.carryBatch
    FinishMaterialTrace(sortRound,reason or "interrupted")
    FinishCategoryTrace(sortRound and sortRound.compaction,reason or "interrupted")
    local placement=sortRound and sortRound.placement
    if placement and placement.firstBatchTimer then
        placement.firstBatchTimer:Cancel();placement.firstBatchTimer=nil
        B.Stats.timers=B.Stats.timers-1
    end
    if placement and placement.receiptCheckTimer then
        placement.receiptCheckTimer:Cancel();placement.receiptCheckTimer=nil
        B.Stats.timers=B.Stats.timers-1
    end
    if placement then FinishPlacementBatch(placement) end
    local placementObserver=sortRound and sortRound.placementTrace
    if placementObserver then
        placementObserver("finish",InventoryActionTime(),nil,reason or "interrupted")
    end
    if sortRound and carryBatch and reason~="complete" then
        if not sortRound.bank then self:RememberCarrySortReceipts(sortRound.receipts,sortRound.inFlight)
        else self:RememberBankSortReceipts(sortRound.receipts,sortRound.inFlight) end
    end
    local splitBatch=self.splitBatch
    local splitTrace=splitBatch or self.serialSplitTrace
    self.splitBatch=nil
    self.serialSplitTrace=nil
    if splitTrace and splitTrace.observe then splitTrace.observe("finish",InventoryActionTime(),nil,reason or "interrupted") end
    local bankSorting=self:IsSortingBank()
    local sorting=self.nativeSort or self.kind=="sort" or self.kind=="restack"
    local removing=self.removalPlan~=nil
    local transfer=self.transferResult
    local blocked=self:BlocksItemInput()
    if transfer and transfer.snapshots then B.Cache:FinishTransferSnapshots(transfer) end
    self.equipmentTransfer=nil
    local waiting=self.waiting
    local heldGuildCursor=(self.guildDispatch or waiting and (waiting.guildReceipt or waiting.operation and waiting.operation.guildWithdraw)) and A.CursorBusy()
    if waiting and B.Deposit.withdrawal and B.Deposit.withdrawal.batch==waiting then B.Deposit.withdrawal=nil end
    self.transferResult=nil
    if personalBatch and transfer then B:FinishTransferGear(transfer) end
    if self.sortTimer then self.sortTimer:Cancel();self.sortTimer=nil;B.Stats.timers=math.max(0,B.Stats.timers-1) end
    self.nativeSort=nil
    if self.timeout then self.timeout:Cancel();self.timeout=nil;B.Stats.timers=math.max(0,B.Stats.timers-1) end
    self.queue,self.waiting,self.index,self.kind=nil,nil,nil,nil
    if self.guildTransfer then
        self.guildTransfer,self.guildInterrupted=nil,nil
        B.View:SetGuildTransferEscape(false)
    end
    self.guildDispatch=nil
    self.sortRound=nil
    self.carryBatch=nil
    if waiting then SetGuildManual(waiting,nil) end
    self.groupPlan,self.roundWaiting,self.roundIndex,self.sendingRound=nil,nil,nil,nil
    self.roundBySlot,self.roundRemaining=nil,nil
    if self.selection and self.selection.progressiveGroups and B.active then
        B.Runtime.splitDisplay=true
        B:QueueFlush()
    end
    self.selection=nil
    self.removalPlan,self.removalFinal=nil,nil
    if reason=="guild-details" then B:Notify("guild.bag_details_unconfirmed")
    elseif transfer then
        local key
        if transfer.confirmed==transfer.total then key="bank.transfer_success"
        elseif reason=="complete" then key="bank.transfer_partial"
        elseif reason=="timeout" then key="bank.transfer_timeout"
        else key="bank.transfer_cancelled" end
        B.Deposit:NotifyTransferResult(key,transfer.confirmed,transfer.total)
    end
    if heldGuildCursor then B:Notify("guild.bag_check_cursor") end
    if personalBatch then B.View:FinishTransferDisplay() end
    if B.active then
        if carryBatch then
            if sortRound and sortRound.bank then sortRound.bankFinishReason=reason or "interrupted" end
            if not carryReconciled then B:FinishCarryBatch(carryBatch,sortRound) end
        elseif sortRound then
            B.View:FinishSortLayout(sortRound)
        elseif bankSorting then B.BankView:Refresh("bank",true)
        elseif sorting or removing then B.View:Invalidate();B:RefreshVisible(true) end
        if blocked then B.View:RefreshItemInputs() end
        B.View:UpdateGrouping()
        if B.bankOpen or B.guildOpen then B.BankView:UpdateBankControls(true) end
        if wasRunning and not carryBatch then B:InvalidateSortSpace(true) end
    end
    if not carryBatch or not B.active then
        self:FinishBankSortObservation(sortRound,reason)
    end
end
function Actions:FinishBankSortObservation(round,reason)
    local observe=round and round.bankObserver
    if observe and self.bankSortObserver==observe then
        local scheduler=round.bankPlacementFallback and "shared-placement+batched"
            or round.placementStarted and "shared-placement" or "batched"
        observe(reason or "interrupted",InventoryActionTime(),scheduler,round.bankPlacementPeak)
    end
end
local function SmallerStack(a,b)
    if a.count~=b.count then return a.count<b.count end
    if a.bag~=b.bag then return a.bag<b.bag end
    return a.slot<b.slot
end
local function SortBags(bank)
    local ids=bank and A.BankBags("bank") or A.GetCarryBags(false)
    if bank then
        for i=#ids,1,-1 do
            if not B.Runtime.readable[ids[i]] or B.Runtime.kind[ids[i]]~="bank" then table.remove(ids,i) end
        end
    end
    return ids
end
function Actions:PlanStacks(items)
    local groups,ordered={},{}
    for _,item in ipairs(items or B.Model:List(A.GetCarryBags(false))) do
        if item.link and item.count<(item.maxStack or 1) and not self:Protected(item) then
            local group=groups[item.link]
            if not group then group={};groups[item.link]=group;ordered[#ordered+1]=group end
            group[#group+1]=item
        end
    end
    for _,group in ipairs(ordered) do
        if #group>1 then
            table.sort(group,SmallerStack)
            for i=1,#group-1 do
                local source=group[i]
                for j=#group,i+1,-1 do
                    local target=group[j]
                    if (not source.maxCharges or source.charges~=nil) and B.Classification:SameStack(source,target)
                        and A.Fits(source,B.Model.bags[target.bag]) then
                        local count=math.min(source.count,target.maxStack-target.count)
                        return {{source=source,target=target,count=count<source.count and count or nil,
                            itemID=source.itemID,link=source.link,sourceCount=source.count,targetCount=target.count,combine=true}}
                    end
                end
            end
        end
    end
    return {}
end
local function SingleBagLayout()
    local window=B.View.windows.player
    return (window and window.layout or B:GetConfig().layout)=="single"
end
function Actions:PlanRestack(bank)
    if bank then return {} end
    local items=B.Model:List(A.GetCarryBags(false))
    local steps=self:PlanStacks(items)
    if #steps>0 or not SingleBagLayout() then return steps end

    -- The combined grid displays physical order. Move junk behind other items
    -- without rearranging the native sort wherever it already meets that rule.
    local junk={}
    for _,item in ipairs(items) do
        if not self:Protected(item) then
            if item.quality==0 then
                junk[#junk+1]=item
            else
                for _,target in ipairs(junk) do
                    if (target.itemID~=item.itemID or target.link~=item.link)
                        and A.Fits(item,B.Model.bags[target.bag]) and A.Fits(target,B.Model.bags[item.bag]) then
                        return {{source=item,target=target,swapTarget=target,itemID=item.itemID,link=item.link,sourceCount=item.count}}
                    end
                end
            end
        end
    end
    return steps
end
function Actions:PlanSort(bank)
    local ids=SortBags(bank)
    local items=B.Model:List(ids)
    local candidates={}
    for _,item in ipairs(items) do if not self:Protected(item) then candidates[#candidates+1]=item end end
    local junkLast=bank and B:GetConfig().bankView.layout=="single" or not bank and SingleBagLayout()
    table.sort(candidates,function(a,b)
        if junkLast and (a.quality==0)~=(b.quality==0) then return b.quality==0 end
        if a.classID~=b.classID then return (a.classID or 99)<(b.classID or 99) end
        if a.itemID~=b.itemID then return a.itemID<b.itemID end
        if a.link~=b.link then return tostring(a.link)<tostring(b.link) end
        if (a.bound==true)~=(b.bound==true) then return a.bound~=true end
        if a.count~=b.count then return a.count<b.count end
        return a.bag==b.bag and a.slot<b.slot or a.bag<b.bag
    end)
    local stacks=self:PlanStacks(candidates)
    if #stacks>0 then return stacks end
    local assigned={}
    for _,id in ipairs(ids) do
        local bag=B.Model.bags[id]
        if bag then for slot=1,bag.capacity do
            local target=bag.slots[slot]
            local key=tostring(id)..":"..slot
            if not B:GetConfig().locks[key] and (not target or not self:Protected(target)) then
                for _,item in ipairs(candidates) do
                    if not assigned[item.uid] and A.Fits(item,bag) then
                        assigned[item.uid]=true
                        if not target or target.uid~=item.uid then
                            if not target or A.Fits(target,B.Model.bags[item.bag]) then
                                return {{source=item,target={bag=id,slot=slot},itemID=item.itemID,link=item.link,
                                    swapTarget=target,sourceCount=item.count,guid=item.guid,checkSortSlot=true}}
                            end
                        else break end
                    end
                end
            end
        end end
    end
    return {}
end
-- Slot events can acknowledge the two ends separately. Store the live values
-- read before pickup: ApplyBag can mutate its own item tables in place.
local function MatchesSortItem(current,expected,count,guid)
    return current and not current.locked and current.count==count
        and B.Classification:SameStack(current,expected) and (not guid or current.guid==guid and not current.guidRetained)
end

local function PersonalBankAccessible()
    return A.ActiveBankKind()=="bank" and A.CanUsePersonalBank() and not A.BankPurchasePending()
end

local function BankSortHasAccess()
    return B.active and B.bankOpen and PersonalBankAccessible()
end

local function SortCanPlace(round)
    return Actions.sortRound==round and not A.InCombat() and (not round.bank or BankSortHasAccess())
end

local function RecordSortCall(timing,started,timeKey,countKey,count)
    timing[timeKey]=timing[timeKey]+(InventoryActionTime()-started)*1000
    timing[countKey]=timing[countKey]+(count or 1)
end

local function ReturnSortPickup(source,round,timing)
    if round.bank and (round.cancelled or not SortCanPlace(round)) then
        A.ClearItemCursorFromSlot(source.bag,source.slot,source.itemID)
        return
    end
    local started=timing and InventoryActionTime()
    local origin,err=A.Slot(source.bag,source.slot)
    if timing then RecordSortCall(timing,started,"slotReadMs","slotReadCalls") end
    if not SortCanPlace(round) then
        if round.bank then A.ClearItemCursorFromSlot(source.bag,source.slot,source.itemID) end
        return
    end
    if err or origin and (not source.guid or origin.guid~=source.guid or not B.Classification:SameStack(origin,source)) then return end
    if A.ItemOnCursorFromSlot(source.bag,source.slot,source.itemID,true)==true then
        started=timing and InventoryActionTime()
        A.Pickup(source.bag,source.slot)
        if timing then RecordSortCall(timing,started,"returnToSourceMs","returnToSourceCalls") end
    end
end

local function DirectionChanged(round)
    return round.carryLayout and round.carryLayout~=B:GetConfig().layout
        or round.direction and round.direction~=Actions:DirectionalSort()
        or round.bankLayout and round.bankLayout~=B:GetConfig().bankView.layout
end

function Actions:CancelSortForConfigChange()
    local round=self.sortRound
    if not round or not round.placement and not DirectionChanged(round) then return end
    round.cancelled=true
    B:QueueFlush()
end

function Actions:SortProtected(item,allowQuestMove)
    return self:Protected(item,allowQuestMove) or not allowQuestMove and item.classID==12
end

local function SendSortMove(op,round,timing)
    local from,to=op.source,op.target
    local sourceBag,targetBag=B.Model.bags[from.bag],B.Model.bags[to.bag]
    local placement=round.placement and op.placementSource
    local allowQuestMove=placement and not round.bank and not op.count and not op.combine
    if placement and (not B.Runtime.readable[from.bag] or not B.Runtime.readable[to.bag]
        or not targetBag or to.slot>targetBag.capacity) then return nil,nil,"unreadable" end
    local started=timing and InventoryActionTime()
    local source,sourceError=A.Slot(from.bag,from.slot)
    local target,targetError=A.Slot(to.bag,to.slot)
    if timing then RecordSortCall(timing,started,"slotReadMs","slotReadCalls",2) end
    if sourceError or targetError then return nil,nil,"unreadable" end
    if not MatchesSortItem(source,from,op.sourceCount,op.guid)
        or Actions:SortProtected(source,allowQuestMove) or B:GetConfig().locks[SlotKey(to)]
        or not A.Fits(source,targetBag,round.bank) then return end
    if target then
        if Actions:SortProtected(target,allowQuestMove) or allowQuestMove and B.Classification:SameStack(source,target) then return end
        if op.combine then
            if not MatchesSortItem(target,source,op.targetCount,op.targetGUID or to.guid)
                or target.count+(op.count or source.count)>target.maxStack then return end
        elseif not op.swapTarget or not MatchesSortItem(target,op.swapTarget,op.swapTarget.count,op.swapTarget.guid)
            or not A.Fits(target,sourceBag,round.bank) then return end
    elseif op.swapTarget or op.combine then return end
    if round.bank and (round.cancelled or not SortCanPlace(round)) then return end
    local picked
    started=timing and InventoryActionTime()
    if op.count then picked=A.Split(from.bag,from.slot,op.count)
    else picked=A.Pickup(from.bag,from.slot) end
    if timing then RecordSortCall(timing,started,"sourcePickupMs","sourcePickupCalls") end
    if not picked or not A.CursorBusy() then return end
    if not SortCanPlace(round) then
        if round.bank then A.ClearItemCursorFromSlot(from.bag,from.slot,source.itemID) end
        return
    end
    -- Pickup and split can dispatch callbacks. Compare the live destination
    -- against the pre-pickup snapshot before issuing the second native call.
    started=timing and InventoryActionTime()
    local current,err=A.Slot(to.bag,to.slot)
    if timing then RecordSortCall(timing,started,"slotReadMs","slotReadCalls") end
    if not SortCanPlace(round) then
        if round.bank then A.ClearItemCursorFromSlot(from.bag,from.slot,source.itemID) end
        return
    end
    if not A.ItemOnCursorFromSlot(from.bag,from.slot,source.itemID,round.direction) then return end
    if err or round.cancelled or DirectionChanged(round) or B:GetConfig().locks[SlotKey(to)] or not target and current
        or target and (not MatchesSortItem(current,target,target.count,target.guid) or Actions:SortProtected(current,allowQuestMove)) then
        ReturnSortPickup(source,round,timing)
        return
    end
    local receipt={source=source,target=target,to=to,moved=op.count or source.count,combine=op.combine}
    if round.bank then receipt.bankDeadline=A.Now()+3 end
    -- Native calls can synchronously close or disable the bags. Keep the
    -- outcome verifiable even if Stop runs before this call returns.
    round.inFlight=receipt
    started=timing and InventoryActionTime()
    local called=A.Pickup(to.bag,to.slot)
    if timing then RecordSortCall(timing,started,"targetDropMs","targetDropCalls") end
    if not SortCanPlace(round) or round.bank and round.cancelled then
        if round.bank and A.CursorBusy() then
            A.ClearItemCursorFromSlot(from.bag,from.slot,source.itemID)
            if target and A.CursorBusy() then A.ClearItemCursorFromSlot(to.bag,to.slot,target.itemID) end
        end
        return
    end
    if A.CursorBusy() then
        -- Some clients leave the displaced item on the cursor after a swap.
        -- A rejected drop may instead leave our original stack in hand.
        local requireLocation=round.direction or target and target.itemID==source.itemID
        local displaced=op.swapTarget and A.ItemOnCursorFromSlot(to.bag,to.slot,target.itemID,requireLocation)
        local original=not displaced and A.ItemOnCursorFromSlot(from.bag,from.slot,source.itemID,requireLocation)
        if (displaced or original) and not round.cancelled and not DirectionChanged(round)
            and (not round.bank or SortCanPlace(round)) then
            started=timing and InventoryActionTime()
            local returned=A.Pickup(from.bag,from.slot)
            if timing then RecordSortCall(timing,started,"returnToSourceMs","returnToSourceCalls") end
            if original then
                round.inFlight=nil
                if called and returned and op.professionRoute and not round.bank
                    and not target and not op.count and targetBag.family and targetBag.family~=0 and targetBag.space~="reagent"
                    and SortCanPlace(round) and not A.CursorBusy() then
                    return nil,true
                end
                return
            end
        end
        if A.CursorBusy() then return end
    end
    round.inFlight=nil
    return receipt
end

local function BeginMaterialTrace(actions,round)
    if not actions.materialObserver then return end
    local trace=round.materialTrace
    if not trace then
        trace={observe=actions.materialObserver,issued=0,round=0}
        round.materialTrace=trace
    end
    local at=InventoryActionTime()
    if trace.round==0 and trace.observe then trace.observe("start",at,nil,"priority") end
    trace.readyAt,trace.round=at,trace.round+1
end

local function TraceMaterialSubmit(trace,op,phase,submitted)
    trace.issued=trace.issued+1
    op.mergeIndex,op.mergeReadyAt=trace.issued,trace.readyAt
    op.materialPhase,op.materialRound=phase,trace.round
    trace.observe("submit",submitted,op)
end

local function SendSortRound(actions,steps,phase)
    local round=actions.sortRound
    local plan=round.wavePlan
    local route=plan and plan.phase=="material-route"
    local first=plan and plan.nextStep or 1
    if first==1 then round.receipts,round.bags={},{} end
    round.sending=true
    actions.queue=steps
    if phase and first==1 then BeginMaterialTrace(actions,round) end
    local trace=phase and round.materialTrace
    local clock=YUI.API.System.GetTimePreciseSec
    local deadline=clock and clock()
    if deadline then deadline=deadline+.002 end
    for index=first,#steps do
        local op=steps[index]
        if round.cancelled or DirectionChanged(round) then round.cancelled=true;break end
        if round.remaining<=0 then actions:Stop();B:Notify("error.operation");return false end
        if A.CursorBusy() or not SortCanPlace(round) then
            actions:Stop();return false
        end
        if trace and trace.observe then TraceMaterialSubmit(trace,op,phase,InventoryActionTime()) end
        TrackCarryMove(actions.carryBatch,op.source,op.target)
        local receipt,rejected=SendSortMove(op,round)
        if actions.sortRound~=round then return false end
        if rejected then
            local bagID=op.target.bag
            local routes=round.rejectedRoutes or {}
            local items=routes[bagID] or {}
            round.rejectedRoutes,routes[bagID],items[op.source.itemID]=routes,items,true
        elseif receipt then
            if trace then receipt.materialOperation=op end
            round.receipts[#round.receipts+1]=receipt
        else actions:Stop();B:Notify("error.changed");return false end
        if plan then plan.nextStep=index+1 end
        round.remaining=round.remaining-1
        round.bags[op.source.bag],round.bags[op.target.bag]=true,true
        if not route and #round.receipts>=actions.sortRoundLimit or deadline and (clock() or deadline)>=deadline then break end
    end
    round.sending=nil
    if not actions.timeout then
        actions.timeout=C_Timer.NewTimer(3,TimedOut)
        B.Stats.timers=B.Stats.timers+1
    end
    B:QueueFlush()
    return true
end

local function StartSortWave(actions,steps,phase,waves)
    if phase=="material-route" and B.Model.bags[steps[1].target.bag].space=="reagent" then
        waves={steps}
    end
    if waves then actions.sortRound.wavePlan={waves=waves,index=1,nextStep=1,phase=phase} end
    return SendSortRound(actions,steps,phase)
end

local function ReadSortReceipt(receipt,live,checkOriginal)
    local from,to=receipt.source,receipt.to
    local oldTarget=receipt.target
    local source,target,sourceReadable,targetReadable
    if live then
        local sourceError,targetError
        source,sourceError=A.Slot(from.bag,from.slot)
        target,targetError=A.Slot(to.bag,to.slot)
        sourceReadable,targetReadable=not sourceError,not targetError
    else
        local a,b=B.Model.bags[from.bag],B.Model.bags[to.bag]
        source,target=a and a.slots[from.slot],b and b.slots[to.slot]
        sourceReadable=a and B.Runtime.readable[from.bag] and from.slot<=a.capacity
        targetReadable=b and B.Runtime.readable[to.bag] and to.slot<=b.capacity
    end
    local sourceReady,targetReady
    if sourceReadable then
        if oldTarget and not receipt.combine then
            sourceReady=MatchesSortItem(source,oldTarget,oldTarget.count,oldTarget.guid)
        elseif receipt.moved<from.count then
            sourceReady=MatchesSortItem(source,from,from.count-receipt.moved,from.guid)
        else sourceReady=not source end
    end
    if targetReadable then
        local destCount=receipt.moved+(receipt.combine and oldTarget.count or 0)
        local destGUID
        if receipt.combine then destGUID=oldTarget.guid
        elseif receipt.moved==from.count then destGUID=from.guid end
        targetReady=MatchesSortItem(target,from,destCount,destGUID)
    end
    local original=checkOriginal and sourceReadable and targetReadable
        and MatchesSortItem(source,from,from.count,from.guid)
        and (oldTarget and MatchesSortItem(target,oldTarget,oldTarget.count,oldTarget.guid) or not oldTarget and not target)
    return sourceReady,targetReady,original
end

local function CopyUnsettledReceipt(receipt)
    return {source=receipt.source,target=receipt.target,to={bag=receipt.to.bag,slot=receipt.to.slot},
        moved=receipt.moved,combine=receipt.combine,externalCheck=receipt.externalCheck,bankDeadline=receipt.bankDeadline}
end

local function UnsettledSortReceipts(receipts,inFlight)
    if not inFlight and (not receipts or #receipts==0) then return end
    local pending={}
    for _,receipt in ipairs(receipts or {}) do
        if not receipt.confirmed then pending[#pending+1]=CopyUnsettledReceipt(receipt) end
    end
    if inFlight then pending[#pending+1]=CopyUnsettledReceipt(inFlight) end
    if #pending>0 then return pending end
end

function Actions:RememberBankSortReceipts(receipts,inFlight)
    local pending=UnsettledSortReceipts(receipts,inFlight)
    if not pending then return end
    local bags={}
    for _,receipt in ipairs(pending) do bags[receipt.source.bag],bags[receipt.to.bag]=true,true end
    self.bankSortRecovery={receipts=pending,bags=bags,player=B.Cache.playerKey}
end

function Actions:RememberCarrySortReceipts(receipts,inFlight)
    local pending=UnsettledSortReceipts(receipts,inFlight)
    if not pending then return end
    local recovery=self.carrySortRecovery
    if recovery and recovery.player==B.Cache.playerKey then
        for _,receipt in ipairs(pending) do recovery.receipts[#recovery.receipts+1]=receipt end
        recovery.verify=true
    else
        self.carrySortRecovery={receipts=pending,player=B.Cache.playerKey,verify=true}
    end
end

function Actions:ReconcileCarrySortRecovery(live)
    local recovery=self.carrySortRecovery
    if not recovery then return end
    if recovery.player and B.Cache.playerKey and recovery.player~=B.Cache.playerKey then self.carrySortRecovery=nil;return end
    if not recovery.verify or A.CursorBusy() then return recovery.receipts[1] end
    recovery.verify=nil
    recovery.checkedAt=A.Now()
    local kept=0
    for _,receipt in ipairs(recovery.receipts) do
        local settled
        if receipt.externalCheck then settled=receipt.externalCheck()
        else
            local sourceReady,targetReady=ReadSortReceipt(receipt,live)
            settled=sourceReady and targetReady
        end
        if not settled then
            kept=kept+1
            recovery.receipts[kept]=receipt
        end
    end
    for index=#recovery.receipts,kept+1,-1 do recovery.receipts[index]=nil end
    if kept==0 then self.carrySortRecovery=nil;return end
    return recovery.receipts[1]
end

function Actions:CheckCarrySortRecovery()
    local recovery=self.carrySortRecovery
    if not recovery then return end
    if recovery.checkedAt~=A.Now() and not self.sortRound and not self.carryBatch and not B.Runtime.finalCarryBatch
        and not A.InCombat() and not A.CursorBusy() then
        if B.active then
            B:MarkCarrySortRecovery(nil,nil,true)
            B:Flush()
        else
            recovery.verify=true
            self:ReconcileCarrySortRecovery(true)
        end
    end
    return self.carrySortRecovery and self.carrySortRecovery.receipts[1]
end

local function AdvancePlacement(actions,round)
    local plan,receipts=round.placement,round.receipts
    if plan.verifying then return end
    local observe=plan.observe
    plan.cancelled=plan.cancelled or round.cancelled or DirectionChanged(round)
    local kept,confirmed=0,false
    for _,receipt in ipairs(receipts) do
        local sourceReady,targetReady=ReadSortReceipt(receipt)
        if sourceReady and targetReady then
            if observe then observe("confirm",InventoryActionTime(),receipt.operation) end
            actions:ConfirmPlacementStep(receipt.operation)
            confirmed=true
        else
            kept=kept+1
            receipts[kept]=receipt
        end
    end
    for index=#receipts,kept+1,-1 do receipts[index]=nil end
    if confirmed then plan.needsSteps=true end
    if receipts[1] and receipts[1].expires<=A.Now() then
        if plan.checkingDeadline then
            if plan.cancelled then actions:Stop("interrupted");return end
            if not plan.deadlineRetried then
                for _,receipt in ipairs(receipts) do
                    if receipt.expires>A.Now() then break end
                    if not B.Runtime.readable[receipt.source.bag] or not B.Runtime.readable[receipt.to.bag] then
                        plan.deadlineRetried=true
                        actions.timeout=C_Timer.NewTimer(.12,TimedOut)
                        B.Stats.timers=B.Stats.timers+1
                        return
                    end
                end
            end
            StopOnTimeout()
        end
        return
    end

    local steps,firstStep
    if not plan.cancelled and not plan.firstBatchTimer and (not plan.dispatchRetry or plan.dispatchRetryReady) then
        if plan.firstBatchSteps then
            steps,firstStep=plan.firstBatchSteps,plan.firstBatchNextStep
            plan.firstBatchSteps,plan.firstBatchNextStep=nil,nil
        elseif plan.needsSteps then
            local misplaced
            steps,misplaced=actions:PlanPlacementSteps(plan)
            plan.needsSteps=false
            if #steps==0 and kept==0 then
                if misplaced and not round.bank then actions:Stop("changed");B:Notify("error.changed")
                else
                    plan.verifying,plan.bankFallback=true,misplaced or nil
                    if actions.timeout then
                        actions.timeout:Cancel();actions.timeout=nil;B.Stats.timers=B.Stats.timers-1
                    end
                    if plan.receiptCheckTimer then
                        plan.receiptCheckTimer:Cancel();plan.receiptCheckTimer=nil;B.Stats.timers=B.Stats.timers-1
                    end
                    B:FinishCarryBatch(actions.carryBatch,round)
                end
                return
            end
        end
    end

    if steps and #steps>0 then
        local timing,budgetMs,sliceStarted
        if firstStep then
            timing=plan.firstBatchTiming
            if timing then
                timing.started=InventoryActionTime()
                timing.sliceGapMs=(timing.started-timing.pausedAt)*1000
                timing.pausedAt=nil
            end
        elseif not plan.firstBatchStarted then
            plan.firstBatchStarted=true
            budgetMs=plan.firstBatchBudgetMs
            if observe or budgetMs and #steps>1 then sliceStarted=InventoryActionTime() end
            if observe then
                timing={started=sliceStarted,plannedSteps=#steps,issuedSteps=0,
                    firstSliceBudgetMs=budgetMs,
                    slotReadMs=0,slotReadCalls=0,sourcePickupMs=0,sourcePickupCalls=0,
                    targetDropMs=0,targetDropCalls=0,returnToSourceMs=0,returnToSourceCalls=0}
                plan.firstBatchTiming=timing
            end
        end
        local expires=A.Now()+3
        round.sending=true
        for index=firstStep or 1,#steps do
            local op=steps[index]
            if round.cancelled or DirectionChanged(round) then plan.cancelled=true;break end
            if actions.sortRound~=round then return end
            if not SortCanPlace(round) or A.CursorBusy() then actions:Stop();return end
            if round.remaining<=0 then
                plan.cancelled=true;B:Notify("error.operation");break
            end
            TrackCarryMove(actions.carryBatch,op.source,op.target)
            local submitted=observe and InventoryActionTime()
            local receipt,_,failure=SendSortMove(op,round,timing)
            if actions.sortRound~=round then return end
            if not receipt then
                if failure=="unreadable" and not plan.dispatchRetry and not round.cancelled and not DirectionChanged(round) then
                    plan.dispatchRetry=op
                    B:SchedulePlacementReceiptCheck(round)
                    break
                end
                plan.cancelled=true
                if not round.cancelled and not DirectionChanged(round) then
                    B:Notify(failure=="unreadable" and "error.sort_unreadable" or "error.changed")
                end
                break
            end
            op.placementSource.pending,op.placementTarget.pending=true,true
            receipt.operation,receipt.expires=op,expires
            receipts[#receipts+1]=receipt
            round.remaining=round.remaining-1
            if timing then timing.issuedSteps=timing.issuedSteps+1 end
            if observe then observe("submit",submitted,op) end
            if budgetMs and index<#steps then
                local at=InventoryActionTime()
                local spentMs=(at-sliceStarted)*1000
                if spentMs>=budgetMs then
                    if timing then
                        timing.firstSliceMs,timing.firstSliceSteps=spentMs,index
                        timing.started,timing.pausedAt=nil,at
                    end
                    plan.firstBatchSteps,plan.firstBatchNextStep=steps,index+1
                    plan.firstBatchTimer=C_Timer.NewTimer(0,function()
                        plan.firstBatchTimer=nil
                        B.Stats.timers=B.Stats.timers-1
                        if actions.sortRound==round then actions:ConfirmSortRound() end
                    end)
                    B.Stats.timers=B.Stats.timers+1
                    if observe then observe("yield",at) end
                    break
                end
            end
        end
        round.sending=nil
        if round.bank then round.bankPlacementPeak=math.max(round.bankPlacementPeak or 0,#receipts) end
        if timing and not plan.firstBatchTimer then FinishPlacementBatch(plan) end
        if firstStep and plan.needsSteps and not plan.cancelled then B:QueueFlush() end
    end

    local deadline=receipts[1] and receipts[1].expires
    if deadline~=plan.armedDeadline or deadline and not actions.timeout then
        if actions.timeout then
            actions.timeout:Cancel();actions.timeout=nil;B.Stats.timers=B.Stats.timers-1
        end
        plan.armedDeadline=deadline
        if deadline then
            actions.timeout=C_Timer.NewTimer(math.max(0,deadline-A.Now()),TimedOut)
            B.Stats.timers=B.Stats.timers+1
        end
    end
    if not deadline and plan.cancelled then actions:Stop() end
end

local function StartPlacement(actions,round,plan)
    round.placement,round.receipts=plan,{}
    if round.placementStarted then
        plan.firstBatchStarted=true
    else
        round.placementStarted=true
        round.placementTrace=actions.placementObserver
        plan.firstBatchBudgetMs=not actions.placementFirstBatchUnbounded and firstPlacementSliceBudgetMs or nil
        if round.placementTrace then round.placementTrace("start",InventoryActionTime(),nil,"classified") end
    end
    plan.observe=round.placementTrace
    plan.needsSteps=true
    AdvancePlacement(actions,round)
    return not plan.cancelled
end

local function PlanSortDispatch(actions,bank,direction)
    local allowMaterialWaves=YUI.IsForever and not bank
    if YUI.IsForever and not direction then
        local steps,compaction,phase,waves=actions:BeginCategoryMerges(actions.sortRoundLimit,allowMaterialWaves,bank)
        if steps or compaction then return steps,compaction,allowMaterialWaves and phase or nil,waves end
    end
    local bankPlacement=YUI.IsForever and bank and not (actions.sortRound and actions.sortRound.bankPlacementFallback)
    local steps,phase,waves,placement=actions:PlanSortRound(bank,actions.sortRoundLimit,allowMaterialWaves,direction,bankPlacement)
    return steps,nil,allowMaterialWaves and phase or nil,waves,placement
end

local function CheckPlacementSnapshot(plan)
    for id,expected in pairs(plan.bags) do
        local bag=B.Model.bags[id]
        if not bag or not B.Runtime.readable[id] then return nil,id end
        if bag.capacity~=expected.capacity or bag.family~=expected.family or bag.space~=expected.space then
            return false,nil,true
        end
    end
    for _,scope in ipairs(plan.scopes) do
        for _,cell in ipairs(scope) do
            local item=B.Model.bags[cell.bag].slots[cell.slot]
            local expected=cell.item
            if item and (item.locked or item.guidRetained or item.loaded==false) then return nil,cell.bag end
            if expected then
                if not MatchesSortItem(item,expected,expected.count,expected.guid) then return false end
            elseif item then return false end
        end
    end
    return true
end

-- Called after the existing final bag reads have reached the model, before rendering.
function Actions:ConfirmPlacementLayout(round)
    if self.sortRound~=round then return end
    if round.cancelled or DirectionChanged(round) or not SortCanPlace(round) or A.CursorBusy() then
        self:Stop("interrupted",true);return
    end
    local plan=round.placement
    local complete,unreadable,topologyChanged=CheckPlacementSnapshot(plan)
    if complete and not plan.bankFallback then self:Stop("complete",true);return end
    if unreadable then
        if not plan.finalReadRetried and B.Runtime.kind[unreadable]==(round.bank and "bank" or "bags") then
            plan.finalReadRetried=true
            B.Runtime.finalCarryBatch=self.carryBatch
            for id in pairs(plan.bags) do
                if id==unreadable or not B.Runtime.readable[id] then B:MarkBag(id) end
            end
            return true
        end
        self:Stop("unreadable",true);B:Notify("error.sort_unreadable");return
    end
    if not complete and (topologyChanged or round.replanned or round.remaining<=0) then
        self:Stop("changed",true);B:Notify("error.changed");return
    end
    if not complete then
        round.replanned=true
        if plan.observe then plan.observe("replan",InventoryActionTime()) end
    end
    if plan.bankFallback then round.bankPlacementFallback=true end
    local steps,_,phase,waves,placement=PlanSortDispatch(self,round.bank,round.direction)
    round.placement=nil
    if placement and #placement.targets>0 then
        StartPlacement(self,round,placement)
        return true
    end
    if #steps>0 then
        StartSortWave(self,steps,phase,waves)
        return true
    end
    self:Stop("complete",true)
end

local function QueueMergeGroup(state,group)
    if group.queued then return end
    group.queued=true
    state.ready[#state.ready+1]=group
end

local function ReadyCategoryMerge(group,operation,at)
    operation.mergeReadyAt=at
    group.moves[#group.moves+1]=operation
end

local function LinkCategoryMerges(group,steps,at)
    group.toIssue=#steps
    if #steps==0 then group.exhausted=true end
    for _,operation in ipairs(steps) do
        local first,second=operation.mergePredecessor,operation.mergeTargetPredecessor
        operation.mergeDependencies=0
        if first and not first.mergeConfirmed then
            first.mergeChildren=first.mergeChildren or {}
            first.mergeChildren[#first.mergeChildren+1]=operation
            operation.mergeDependencies=operation.mergeDependencies+1
        end
        if second and second~=first and not second.mergeConfirmed then
            second.mergeChildren=second.mergeChildren or {}
            second.mergeChildren[#second.mergeChildren+1]=operation
            operation.mergeDependencies=operation.mergeDependencies+1
        end
        if operation.mergeDependencies==0 then ReadyCategoryMerge(group,operation,at) end
    end
end

local function WakeCategoryMerges()
    Actions.timeout=nil
    B.Stats.timers=math.max(0,B.Stats.timers-1)
    if Actions.sortRound and Actions.sortRound.compaction then B:QueueFlush() end
end

local function SendTrackedMerge(actions,round,group,operation)
    if round.remaining<=0 then actions:Stop("limit");B:Notify("error.operation");return false end
    if not SortCanPlace(round) or A.CursorBusy() then actions:Stop();return false end
    local submitted=InventoryActionTime()
    local trace=group and round.compaction or round.materialTrace
    if trace and trace.observe then
        if group then
            trace.issued=trace.issued+1
            operation.mergeIndex,operation.mergeGroup=trace.issued,group.index
            trace.observe("submit",submitted,operation)
        else TraceMaterialSubmit(trace,operation,"material-merge",submitted) end
    end
    TrackCarryMove(actions.carryBatch,operation.source,operation.target)
    local receipt=SendSortMove(operation,round)
    if actions.sortRound~=round then return false end
    if not receipt then actions:Stop("changed");B:Notify("error.changed");return false end
    receipt.group,receipt.operation,receipt.expires=group,operation,submitted+3
    round.receipts[#round.receipts+1]=receipt
    round.remaining=round.remaining-1
    return true
end

local function AdvanceParallelMaterial(actions,round,deadline)
    local material=round.parallelMaterial
    local wave=material.waves[material.index]
    if material.nextStep>#wave and material.pending==0 then
        local trace=round.materialTrace
        if trace and trace.observe then
            local released=InventoryActionTime()
            for _,op in ipairs(wave) do trace.observe("release",released,op) end
        end
        material.index,material.nextStep=material.index+1,1
        wave=material.waves[material.index]
        if not wave then
            round.parallelMaterial=nil
            FinishMaterialTrace(round,"complete")
            local state=round.compaction
            for _,group in ipairs(state.deferred) do state.ready[#state.ready+1]=group end
            state.deferred=nil
            return true
        end
        BeginMaterialTrace(actions,round)
    end
    while not round.cancelled and material.nextStep<=#wave and #round.receipts<actions.sortRoundLimit do
        if not SendTrackedMerge(actions,round,nil,wave[material.nextStep]) then return false end
        material.nextStep,material.pending=material.nextStep+1,material.pending+1
        if InventoryActionTime()>=deadline then break end
    end
    return true
end

local function AdvanceCategoryMerges(actions,round)
    local state,receipts=round.compaction,round.receipts
    round.cancelled=round.cancelled or DirectionChanged(round)
    round.sending=true
    local kept=0
    for _,receipt in ipairs(receipts) do
        local sourceReady,targetReady=ReadSortReceipt(receipt)
        local at=InventoryActionTime()
        local operation,group=receipt.operation,receipt.group
        local trace=group and state or round.materialTrace
        if trace and trace.observe then ObserveMoveSlots(trace,operation,sourceReady,targetReady) end
        if sourceReady and targetReady then
            if trace and trace.observe then trace.observe("confirm",InventoryActionTime(),operation) end
            operation.mergeConfirmed=true
            if not group then
                local material=round.parallelMaterial
                material.pending=material.pending-1
            end
            if operation.mergeChildren then
                for _,child in ipairs(operation.mergeChildren) do
                    child.mergeDependencies=child.mergeDependencies-1
                    if child.mergeDependencies==0 then
                        ReadyCategoryMerge(group,child,at)
                        QueueMergeGroup(state,group)
                    end
                end
            end
        else
            if at>=receipt.expires then TimedOut();return false end
            kept=kept+1
            receipts[kept]=receipt
        end
    end
    for index=#receipts,kept+1,-1 do receipts[index]=nil end
    if round.cancelled and #receipts==0 then actions:Stop("interrupted");return true end
    local deadline,yielded=InventoryActionTime()+.002,false
    if not round.cancelled and round.parallelMaterial then
        if not AdvanceParallelMaterial(actions,round,deadline) then return false end
        yielded=InventoryActionTime()>=deadline
    end
    while not round.cancelled and state.head<=#state.ready and #receipts<actions.sortRoundLimit and not yielded do
        local group=state.ready[state.head]
        state.head=state.head+1
        group.queued=nil
        if not group.toIssue or group.toIssue==0 then
            LinkCategoryMerges(group,actions:PlanCategoryMergeGroup(group,actions.sortRoundLimit),InventoryActionTime())
        end
        while not round.cancelled and #receipts<actions.sortRoundLimit and group.nextMove<=#group.moves do
            local operation=group.moves[group.nextMove]
            if not SendTrackedMerge(actions,round,group,operation) then return false end
            group.nextMove=group.nextMove+1
            group.toIssue=group.toIssue-1
            if InventoryActionTime()>=deadline then yielded=true;break end
        end
        if not group.exhausted and (group.toIssue==0 or group.nextMove<=#group.moves) then QueueMergeGroup(state,group) end
        if InventoryActionTime()>=deadline then yielded=true end
    end
    round.sending=nil
    local material=round.parallelMaterial
    if not round.cancelled and state.head>#state.ready then
        if not material and #receipts==0 then actions:Stop("complete");return true end
        -- Finish the ordinary trace as soon as its own work is done.
        if material and #receipts==material.pending and #state.deferred==0 then
            FinishCategoryTrace(state,"complete")
        end
    end

    local expires=receipts[1] and receipts[1].expires
    if actions.timeout and state.expires~=expires then
        actions.timeout:Cancel();actions.timeout=nil;B.Stats.timers=math.max(0,B.Stats.timers-1)
    end
    state.expires=expires
    if expires and not actions.timeout then
        actions.timeout=C_Timer.NewTimer(math.max(0,expires-InventoryActionTime()),WakeCategoryMerges)
        B.Stats.timers=B.Stats.timers+1
    end
    local materialReady=material and material.nextStep<=#material.waves[material.index]
    if not round.cancelled and (#receipts>kept or (materialReady or state.head<=#state.ready)
        and #receipts<actions.sortRoundLimit) then B:QueueFlush() end
    return true
end

local function StartCategoryMerges(actions,round,state,waves)
    round.compaction,round.receipts=state,{}
    actions.queue=state.ready
    if waves then
        round.parallelMaterial={waves=waves,index=1,nextStep=1,pending=0}
        BeginMaterialTrace(actions,round)
    end
    local started=InventoryActionTime()
    state.observe=actions.compactObserver
    if state.observe then state.observe("start",started,nil,"category") end
    return AdvanceCategoryMerges(actions,round)
end

function Actions:ConfirmSortRound()
    local round=self.sortRound
    if not round or round.sending or not round.receipts then return end
    if A.CursorBusy() or not SortCanPlace(round) then
        self:Stop();return
    end
    if round.placement then return AdvancePlacement(self,round) end
    if round.compaction then return AdvanceCategoryMerges(self,round) end
    round.cancelled=round.cancelled or DirectionChanged(round)
    if #round.receipts==0 and not round.rejectedRoutes then
        if round.cancelled then self:Stop() end
        return
    end
    local plan=round.wavePlan
    local wave=plan and plan.waves[plan.index]
    local extend=not round.cancelled and wave and plan.nextStep<=#wave
    local route=plan and plan.phase=="material-route"
    local trace=round.materialTrace
    local observed=trace and trace.observe
    local ready=true
    for _,receipt in ipairs(round.receipts) do
        if not receipt.confirmed then
            local sourceReady,targetReady=ReadSortReceipt(receipt)
            if not sourceReady or not targetReady then
                if not observed and not extend and not route then return end
                ready=false
            elseif route or round.bank then receipt.confirmed=true end
            if observed and receipt.materialOperation then
                local op=receipt.materialOperation
                ObserveMoveSlots(trace,op,sourceReady,targetReady)
                if sourceReady and targetReady and not receipt.materialObserved then
                    receipt.materialObserved=true
                    observed("confirm",InventoryActionTime(),op)
                end
            end
        end
    end
    -- A frame-budget yield can leave disjoint moves from this wave unsent.
    -- Submit them without throwing away earlier receipts or their deadline.
    if extend and not round.checkingDeadline then return SendSortRound(self,wave,plan.phase) end
    if not ready then return end
    if round.cancelled then self:Stop();return end
    if observed and not extend then
        local released=InventoryActionTime()
        for _,receipt in ipairs(round.receipts) do
            if receipt.materialOperation then observed("release",released,receipt.materialOperation) end
        end
    end
    self.timeout:Cancel()
    self.timeout=nil
    B.Stats.timers=B.Stats.timers-1
    if extend then return SendSortRound(self,wave,plan.phase) end
    if plan then
        plan.index,plan.nextStep=plan.index+1,1
        local nextWave=plan.waves[plan.index]
        if nextWave then return SendSortRound(self,nextWave,plan.phase) end
        if not plan.phase then self:Stop("complete");return end
        round.wavePlan=nil
    end
    local steps,compaction,phase,waves,placement=PlanSortDispatch(self,round.bank,round.direction)
    if not phase then FinishMaterialTrace(round,"complete") end
    if compaction then return StartCategoryMerges(self,round,compaction,waves) end
    if placement then return StartPlacement(self,round,placement) end
    if #steps==0 then self:Stop("complete");return end
    StartSortWave(self,steps,phase,waves)
end

local function BankSortSlotRetired(pos)
    local id=pos.bag
    if B.Runtime.kind[id]~="bank" then return false end
    local bag=B.Model.bags[id]
    return B.Runtime.readable[id] and bag and pos.slot>bag.capacity or A.BankBagInstalled(id)==false
end

function Actions:CheckBankSortRecovery()
    local recovery=self.bankSortRecovery
    if recovery and recovery.player~=B.Cache.playerKey then
        CancelBankRecoveryCheck(recovery)
        self.bankSortRecovery=nil;recovery=nil
    end
    local check=self.externalBankSortReceipt
    if not check and not recovery then return false end
    if not PersonalBankAccessible() or A.InCombat() or A.CursorBusy() then
        if recovery then for _,receipt in ipairs(recovery.receipts) do receipt.originalSince=nil end end
        return true
    end
    if check then
        if not check() then return true end
        self.externalBankSortReceipt=nil
    end
    if not recovery then return false end
    local pending,now=recovery.receipts,A.Now()
    local kept,recheck=0,nil
    for _,receipt in ipairs(pending) do
        local expired=now>=receipt.bankDeadline
        local sourceReady,targetReady,original=ReadSortReceipt(receipt,true,expired)
        -- Before the deadline the original contents may just be an old read.
        -- Require a second unlocked read before treating the move as rejected.
        receipt.originalSince=original and (receipt.originalSince or now) or nil
        local settled=sourceReady and targetReady or receipt.originalSince and now>=receipt.originalSince+.10
            or expired and (BankSortSlotRetired(receipt.source) or BankSortSlotRetired(receipt.to))
        if not settled then
            kept=kept+1;pending[kept]=receipt
            local retryAt=not expired and receipt.bankDeadline or receipt.originalSince and receipt.originalSince+.10
            if retryAt and (not recheck or retryAt<recheck) then recheck=retryAt end
        end
    end
    for index=#pending,kept+1,-1 do pending[index]=nil end
    if kept>0 then
        if recheck and not recovery.timer and B.active and B.bankOpen then
            recovery.timer=C_Timer.NewTimer(math.max(0,recheck-now),function()
                recovery.timer=nil
                B.Stats.timers=B.Stats.timers-1
                if self.bankSortRecovery==recovery then B:QueueFlush() end
            end)
            B.Stats.timers=B.Stats.timers+1
        end
        return true
    end
    CancelBankRecoveryCheck(recovery)
    self.bankSortRecovery=nil
    for id in pairs(recovery.bags) do B:MarkBag(id) end
    return false
end

function Actions:SortInventory(bank,direction)
    if self.externalCarrySort and (not bank or self.externalCarrySort.bank) or bank and self:CheckBankSortRecovery() then
        B:Notify("error.carry_sort_busy");return false
    end
    if not B.active or self.queue or self.nativeSort or self.carryBatch or B.Runtime.finalCarryBatch
        or A.InCombat() or A.CursorBusy() then return false end
    self:CancelDelete()
    if not bank then
        local pending=self:CheckCarrySortRecovery()
        if pending then
            local recovery=self.carrySortRecovery
            local from,to=pending.source,pending.to
            if recovery.notified~=pending then
                recovery.notified=pending
                B:Notify("error.sort_receipt_pending",from.bag,from.slot,to.bag,to.slot)
            end
            return false
        end
        local retryRead=false
        for id,kind in pairs(B.Runtime.kind) do
            local bag=B.Model.bags[id]
            if kind=="bags" and B.Runtime.readable[id]==false and (not bag or bag.space~="keyring") then
                retryRead=true
                if self.carrySortReadAt~=A.Now() then B:MarkBag(id) end
            end
        end
        if retryRead and self.carrySortReadAt~=A.Now() then
            self.carrySortReadAt=A.Now()
            B:Flush()
        end
        if retryRead then
            for id,kind in pairs(B.Runtime.kind) do
                local bag=B.Model.bags[id]
                if kind=="bags" and B.Runtime.readable[id]==false and (not bag or bag.space~="keyring") then
                    B:Notify("error.sort_unreadable");return false
                end
            end
        end
    end
    if B.Stats.pendingRefresh then B:Flush() end
    if self.queue or self.nativeSort or self.carryBatch or B.Runtime.finalCarryBatch or A.InCombat() or A.CursorBusy() then return false end
    if bank and not BankSortHasAccess() then return false end
    local bankObserver=bank and self.bankSortObserver
    if bankObserver then bankObserver("start",InventoryActionTime()) end
    local steps,compaction,phase,waves,placement=PlanSortDispatch(self,bank,direction)
    if not compaction and not placement and #steps==0 then
        local w=B.View:ResetSortLayout(bank,true)
        if w then B.View:Layout(w,true) end
        if bankObserver then bankObserver("no-movement",InventoryActionTime()) end
        return true
    end
    self.kind=bank and "bank-sort" or "sort"
    local capacity=0
    for _,id in ipairs(bank and A.BankBags("bank") or A.GetCarryBags(false)) do
        local bag=B.Model.bags[id]
        if B.Runtime.readable[id] and bag then capacity=capacity+bag.capacity end
    end
    -- Bound a single explicit command even if external mutations repeatedly
    -- undo acknowledged moves. Normal merges and permutation cycles use O(n) moves.
    self.sortRound={bank=bank,remaining=capacity*4,direction=direction,carryLayout=not bank and B:GetConfig().layout or nil}
    if bankObserver then self.sortRound.bankObserver=bankObserver end
    if YUI.IsForever then
        self.carryBatch={bags={},kind=bank and "bank" or "bags"}
        if bank then self.sortRound.bankLayout=B:GetConfig().bankView.layout end
    end
    self.queue,self.index=steps or compaction.ready,1
    B:RefreshSortSpace()
    B.View:CloseItemSplitDialogs()
    B.View:RefreshItemInputs()
    if B.bankOpen or B.guildOpen then B.BankView:UpdateBankControls(true) end
    if compaction then return StartCategoryMerges(self,self.sortRound,compaction,waves) end
    if placement then return StartPlacement(self,self.sortRound,placement) end
    return StartSortWave(self,steps,phase,waves)
end

function Actions:DirectionalSort()
    if YUI.IsForever and SingleBagLayout() then return B:GetConfig().combinedSortDirection end
end

function Actions:Sort()
    if A.InCombat() or A.CursorBusy() or self.queue or self.nativeSort then return false end
    if YUI.IsForever then return self:SortInventory(false,self:DirectionalSort()) end
    self:CancelDelete();B.View:Invalidate();B:RefreshVisible(true)
    if next(B:GetConfig().locks)==nil then
        self.nativeSort=true;self.sortTimer=C_Timer.NewTimer(2,SortSettled);B.Stats.timers=B.Stats.timers+1
        local ok=pcall(C_Container.SortBags)
        if not ok then self:Stop();B:Notify("error.operation");return false end
        return true
    end
    return self:Start(self:PlanSort(),"sort")
end
function Actions:SortBank()
    local w=B.View.windows["live-bank"]
    if not w or not w.open or w.readyPages==0 or not B.Deposit:CanTransfer() then return false end
    if YUI.IsForever then return self:SortInventory(true) end
    self:CancelDelete()
    local locks=B:GetConfig().locks
    if next(locks) then
        for _,id in ipairs(A.BankBags("bank")) do
            local bag=B.Model.bags[id]
            for slot=1,bag and bag.capacity or 0 do
                if locks[id..":"..slot] then return self:Start(self:PlanSort(true),"bank-sort") end
            end
        end
    end
    self.nativeSort="bank";self.sortTimer=C_Timer.NewTimer(2,SortSettled);B.Stats.timers=B.Stats.timers+1
    B.View:CloseItemSplitDialogs()
    B.BankView:Refresh("bank",true)
    B.View:RefreshItemInputs()
    if not A.SortPersonalBank() then self:Stop();B:Notify("error.operation");return false end
    return true
end
function Actions:PlanDeposit(target,rule)
    return B.Deposit:Plan(target,rule)
end
