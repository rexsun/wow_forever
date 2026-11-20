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
function Actions:Protected(item)
    local config=B:GetConfig()
    return not item or item.locked or item.quest or config.favorites[tostring(item.itemID)] or config.locks[item.key]
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
    if A.Context()~="travel" or A.InCombat() or A.CursorBusy() or self.queue or item.quality~=0 or self:Protected(item) then self:CancelDelete();return false end
    local fresh=A.Slot(item.bag,item.slot)
    if not fresh or fresh.quality~=0 or fresh.quest or fresh.locked then self:CancelDelete();return true end
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
    for _,id in ipairs(ids) do
        local bag=B.Model.bags[id]
        if id~=excludedBag and bag and A.Fits(item,bag) and (not space or (bag.space or A.SpaceKey(id,bag.family,bag.kind))==space) then
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
function Actions:MakeSplitGroups(item,size,parts)
    local plan=self:MakeSplit(item,size,parts)
    if not plan then return nil end
    local chunks={}
    if plan.remainder>0 then chunks[1]=plan.remainder end
    for _=1,parts do chunks[#chunks+1]=size end
    local rounds,steps,nextTarget={},{},0
    local function Divide(source,first,last,total,depth)
        if first==last then return end
        local middle=math.floor((first+last)/2)
        local amount=0;for n=middle+1,last do amount=amount+chunks[n] end
        nextTarget=nextTarget+1
        local target=plan.steps[nextTarget].target
        local operation={source=source,target=target,count=amount,sourceCount=total,itemID=item.itemID,link=item.link}
        rounds[depth]=rounds[depth] or {};rounds[depth][#rounds[depth]+1]=operation;steps[#steps+1]=operation
        Divide(source,first,middle,total-amount,depth+1)
        Divide(target,middle+1,last,amount,depth+1)
    end
    Divide({bag=item.bag,slot=item.slot},1,#chunks,item.count,1)
    plan.rounds,plan.steps=rounds,steps
    return plan
end
local function SlotKey(item) return tostring(item.bag)..":"..item.slot end
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
    self:Stop()
    local w=B.View.windows.player
    if w and w.open and not plan.progressiveGroups then B.View:Layout(w,false) end
    return ok
end
function Actions:StartSelection(plan)
    if not plan or self.queue or self.nativeSort or A.InCombat() or A.CursorBusy() or not self:SelectionValid(plan.selection) then return false end
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
local function TimedOut()
    local transfer=Actions.transferResult
    Actions:Stop("timeout")
    if not transfer then B:Notify("error.timeout") end
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
function Actions:StartGroups(plan)
    if self.queue or self.nativeSort or A.InCombat() or A.CursorBusy() or not plan or not plan.rounds then return false end
    self:CancelDelete();self.queue,self.kind,self.groupPlan,self.roundIndex=plan.steps,"split-groups",plan,1
    B:RefreshSortSpace()
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
local function ConfirmSplitOperation(self,op)
        if op.confirmed then return end
        local source=A.Slot(op.source.bag,op.source.slot)
        local target=B.Deposit:ReadTarget(op.target)
        if not source or source.itemID~=op.itemID or source.link~=op.link or source.count~=op.sourceCount-op.count or source.locked
            or not target or target.itemID~=op.itemID or target.link~=op.link or target.count~=op.count or target.locked then return end
        if op.sourceGUID and source.guid~=op.sourceGUID then self:Stop();return end
        if self.selection and op.sourceGUID and not target.guid then return end
        self:SelectionConfirmed(source,op);self:SelectionConfirmed(target,op)
        if self.selection and self.selection.progressiveGroups then B:MarkSplitReceipt(op) end
        B.View:ConfirmSplitPlacement(target)
        if target.new then A.ClearNewItem(target.bag,target.slot) end
        op.confirmed=true;self.roundRemaining=self.roundRemaining-1
end
function Actions:ConfirmGroups(single)
    if self.sendingRound or not self.roundWaiting then return end
    if single then ConfirmSplitOperation(self,single) else for _,op in ipairs(self.roundWaiting) do ConfirmSplitOperation(self,op) end end
    if not self.groupPlan then return end
    if self.roundRemaining>0 then return end
    if self.timeout then self.timeout:Cancel();self.timeout=nil;B.Stats.timers=math.max(0,B.Stats.timers-1) end
    self.roundWaiting=nil;self.roundIndex=self.roundIndex+1;self:SendSplitRound()
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
    if changed then B.Model.revision=B.Model.revision+1;B.View:Invalidate(true);B:RefreshVisible(true) end
    return changed
end
function Actions:IsSortingBank()
    return self.nativeSort=="bank" or self.kind=="bank-sort" or self.kind=="bank-restack"
end
function Actions:BlocksItemInput()
    return self.sortRound~=nil or self.kind=="deposit" or self.kind=="bag-remove" or self:IsSortingBank()
        or self.selection and self.selection.progressiveGroups or false
end
function Actions:IsPersonalBatch()
    local queue=self.queue
    return self.kind=="deposit" and queue and #queue>1 and queue[1].personalTransfer==true
end
function Actions:Start(steps,kind,transferTotal)
    if self.queue or self.nativeSort or A.InCombat() or A.CursorBusy() or #steps==0 and kind~="bag-remove" then return false end
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
    local transfer=self.transferResult
    if transfer then
        transfer.confirmed=transfer.confirmed+waiting.source.count-waiting.expectedSource
        if self:IsPersonalBatch() then B.View:ShowTransferProgress(transfer) end
    end
    if self.selection then
        if self.selection.progressiveGroups then
            self:SelectionConfirmed(source,op)
            B:MarkSplitReceipt(op)
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
function Actions:Stop(reason)
    local wasRunning=self.queue~=nil or self.nativeSort~=nil
    local personalBatch=self:IsPersonalBatch()
    if self.guildInterrupted and reason=="timeout" then reason="cancelled" end
    local sortRound=self.sortRound
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
        if sortRound then
            B.View:FinishSortLayout(sortRound)
        elseif bankSorting then B.BankView:Refresh("bank",true)
        elseif sorting or removing then B.View:Invalidate();B:RefreshVisible(true) end
        if blocked then B.View:RefreshItemInputs() end
        B.View:UpdateGrouping()
        if B.bankOpen or B.guildOpen then B.BankView:UpdateBankControls(true) end
        if wasRunning then B:InvalidateSortSpace(true) end
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

local function SortCanPlace(round)
    return Actions.sortRound==round and not A.InCombat() and (not round.bank or B.bankOpen and A.CanUsePersonalBank())
end

local function ReturnSortPickup(source,round)
    local origin,err=A.Slot(source.bag,source.slot)
    if err or not SortCanPlace(round) or origin and (not source.guid or origin.guid~=source.guid
        or not B.Classification:SameStack(origin,source)) then return end
    if A.ItemOnCursorFromSlot(source.bag,source.slot,source.itemID,true)==true then
        A.Pickup(source.bag,source.slot)
    end
end

local function SendSortMove(op,round)
    local from,to=op.source,op.target
    local source,sourceError=A.Slot(from.bag,from.slot)
    local target,targetError=A.Slot(to.bag,to.slot)
    local sourceBag,targetBag=B.Model.bags[from.bag],B.Model.bags[to.bag]
    if sourceError or targetError or not MatchesSortItem(source,from,op.sourceCount,op.guid)
        or Actions:Protected(source) or B:GetConfig().locks[SlotKey(to)]
        or not A.Fits(source,targetBag,round.bank) then return end
    if target then
        if Actions:Protected(target) then return end
        if op.combine then
            if not MatchesSortItem(target,source,op.targetCount,op.targetGUID or to.guid)
                or target.count+(op.count or source.count)>target.maxStack then return end
        elseif not op.swapTarget or not MatchesSortItem(target,op.swapTarget,op.swapTarget.count,op.swapTarget.guid)
            or not A.Fits(target,sourceBag,round.bank) then return end
    elseif op.swapTarget or op.combine then return end
    local picked
    if op.count then picked=A.Split(from.bag,from.slot,op.count)
    else picked=A.Pickup(from.bag,from.slot) end
    if not picked or not SortCanPlace(round) or not A.CursorBusy() then return end
    -- Pickup and split can dispatch callbacks. Compare the live destination
    -- against the pre-pickup snapshot before issuing the second native call.
    local current,err=A.Slot(to.bag,to.slot)
    if not SortCanPlace(round) or not A.ItemOnCursorFromSlot(from.bag,from.slot,source.itemID) then return end
    if err or B:GetConfig().locks[SlotKey(to)] or not target and current
        or target and (not MatchesSortItem(current,target,target.count,target.guid) or Actions:Protected(current)) then
        ReturnSortPickup(source,round)
        return
    end
    A.Pickup(to.bag,to.slot)
    if Actions.sortRound~=round then return end
    if A.CursorBusy() then
        -- Some clients leave the displaced item on the cursor after a swap.
        -- A rejected drop may instead leave our original stack in hand.
        if (op.swapTarget and A.ItemOnCursorFromSlot(to.bag,to.slot,target.itemID))
            or A.ItemOnCursorFromSlot(from.bag,from.slot,source.itemID) then
            A.Pickup(from.bag,from.slot)
        end
        if A.CursorBusy() then return end
    end
    return {source=source,target=target,to=to,moved=op.count or source.count,combine=op.combine}
end

local function SendSortRound(actions,steps)
    local round=actions.sortRound
    round.receipts,round.bags={},{}
    round.sending=true
    actions.queue=steps
    local clock=YUI.API.System.GetTimePreciseSec
    local deadline=clock and clock()
    if deadline then deadline=deadline+.002 end
    for _,op in ipairs(steps) do
        if round.remaining<=0 then actions:Stop();B:Notify("error.operation");return false end
        if A.CursorBusy() or A.InCombat() or round.bank and (not B.bankOpen or not A.CanUsePersonalBank()) then
            actions:Stop();return false
        end
        local receipt=SendSortMove(op,round)
        if actions.sortRound~=round then return false end
        if not receipt then actions:Stop();B:Notify("error.changed");return false end
        round.receipts[#round.receipts+1]=receipt
        round.remaining=round.remaining-1
        round.bags[op.source.bag],round.bags[op.target.bag]=true,true
        if #round.receipts>=actions.sortRoundLimit or deadline and (clock() or deadline)>=deadline then break end
    end
    round.sending=nil
    actions.timeout=C_Timer.NewTimer(3,TimedOut)
    B.Stats.timers=B.Stats.timers+1
    B:QueueFlush()
    return true
end

function Actions:ConfirmSortRound()
    local round=self.sortRound
    if not round or round.sending or not round.receipts or #round.receipts==0 then return end
    if A.InCombat() or A.CursorBusy() or round.bank and (not B.bankOpen or not A.CanUsePersonalBank()) then
        self:Stop();return
    end
    for _,receipt in ipairs(round.receipts) do
        local from,to=receipt.source,receipt.to
        local a,b=B.Model.bags[from.bag],B.Model.bags[to.bag]
        if not B.Runtime.readable[from.bag] or not B.Runtime.readable[to.bag]
            or from.slot>a.capacity or to.slot>b.capacity then return end
        local oldTarget=receipt.target
        local destCount=receipt.moved+(receipt.combine and oldTarget.count or 0)
        local destGUID
        if receipt.combine then destGUID=oldTarget.guid
        elseif receipt.moved==from.count then destGUID=from.guid end
        if not MatchesSortItem(b.slots[to.slot],from,destCount,destGUID) then return end
        local source=a.slots[from.slot]
        if oldTarget and not receipt.combine then
            if not MatchesSortItem(source,oldTarget,oldTarget.count,oldTarget.guid) then return end
        elseif receipt.moved<from.count then
            if not MatchesSortItem(source,from,from.count-receipt.moved,from.guid) then return end
        elseif source then return end
    end
    self.timeout:Cancel()
    self.timeout=nil
    B.Stats.timers=B.Stats.timers-1
    local steps=self:PlanSortRound(round.bank,self.sortRoundLimit)
    if #steps==0 then self:Stop("complete");return end
    SendSortRound(self,steps)
end

function Actions:SortInventory(bank)
    if not B.active or self.queue or self.nativeSort or A.InCombat() or A.CursorBusy() then return false end
    self:CancelDelete()
    if B.Stats.pendingRefresh then B:Flush() end
    local steps=self:PlanSortRound(bank,self.sortRoundLimit)
    if #steps==0 then
        local w=B.View:ResetSortLayout(bank,true)
        if w then B.View:Layout(w,true) end
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
    self.sortRound={bank=bank,remaining=capacity*4}
    self.queue,self.index=steps,1
    B:RefreshSortSpace()
    B.View:CloseItemSplitDialogs()
    B.View:RefreshItemInputs()
    if B.bankOpen or B.guildOpen then B.BankView:UpdateBankControls(true) end
    return SendSortRound(self,steps)
end

function Actions:Sort()
    if A.InCombat() or A.CursorBusy() or self.queue or self.nativeSort then return false end
    if YUI.IsForever then return self:SortInventory(false) end
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
