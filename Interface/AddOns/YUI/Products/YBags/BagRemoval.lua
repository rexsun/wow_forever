local YUI=_G.YUI
local B=YUI and YUI.YBags
if not B then return end
local A=YUI.API.Bags
local R={}
B.BagRemoval=R
local function Key(bag,slot) return tostring(bag)..":"..slot end
local function Same(a,b)
    return a and b and a.itemID==b.itemID and (not b.guid or a.guid==b.guid)
        and (b.guid~=nil or not b.link or a.link==b.link)
end
local function Movable(item,key)
    return not B:GetConfig().locks[key] and (not item or not item.locked)
end
local function Move(steps,source,target,count)
    local item,dest=source.item,target.item
    local old=item.count
    steps[#steps+1]={source={bag=source.bag,slot=source.slot},target={bag=target.bag,slot=target.slot},
        itemID=item.itemID,link=item.link,guid=item.guid,bound=item.bound,sourceCount=old,
        targetCount=dest and dest.count or 0,combine=dest~=nil,count=count<old and count or nil}
    if not dest then
        dest=B:Copy(item);dest.count=0
        if count<old then dest.guid=nil end
        target.item=dest
    end
    dest.count=dest.count+count;item.count=item.count-count
    if item.count==0 then source.item=nil end
end
local function Room(source,target)
    local a,b=source.item,target.item
    if a and b and a.link and b.link and B.Classification:SameStack(a,b) and A.Fits(a,target) then
        return math.max(0,(b.maxStack or 1)-b.count)
    end
    return 0
end
local function Attempt(sources,targets,reserved)
    sources,targets=B:Copy(sources),B:Copy(targets)
    local steps={}
    local reserve
    for _,target in ipairs(targets) do if target.key==reserved then reserve=target;break end end
    if reserve.item then
        local room=0;for _,target in ipairs(targets) do if target~=reserve then room=room+Room(reserve,target) end end
        if room<reserve.item.count then return end
        for _,target in ipairs(targets) do if target~=reserve and reserve.item then
            local count=math.min(reserve.item.count,Room(reserve,target))
            if count>0 then Move(steps,reserve,target,count) end
        end end
    end
    local groups={}
    for _,source in ipairs(sources) do
        local group
        for _,candidate in ipairs(groups) do if B.Classification:SameStack(candidate.ref,source.item) then group=candidate;break end end
        if not group then group={ref=B:Copy(source.item),sources={},remaining=0};groups[#groups+1]=group end
        group.sources[#group.sources+1]=source;group.remaining=group.remaining+source.item.count
    end
    local function Consume(group,target,count)
        for _,source in ipairs(group.sources) do if source.item and count>0 then
            local moved=math.min(source.item.count,count);Move(steps,source,target,moved)
            count=count-moved;group.remaining=group.remaining-moved
        end end
    end
    local bins,empty={},{ }
    for _,target in ipairs(targets) do if target~=reserve and not target.item then empty[#empty+1]=target end end
    for _,group in ipairs(groups) do
        for _,target in ipairs(targets) do if target~=reserve and target.item and group.remaining>0 and group.ref.link
            and B.Classification:SameStack(group.ref,target.item) and A.Fits(group.ref,target) then
            local count=math.min(group.remaining,math.max(0,(target.item.maxStack or 1)-target.item.count))
            if count>0 then Consume(group,target,count) end
        end end
        local left=group.remaining;local max=math.max(1,group.ref.maxStack or 1)
        while left>0 do local count=left%max;if count==0 then count=max end;bins[#bins+1]={group=group,count=count};left=left-count end
    end
    local matches={}
    local function Assign(index,seen)
        for n,target in ipairs(empty) do
            if not seen[n] and A.Fits(bins[index].group.ref,target) then
                seen[n]=true
                if not matches[n] or Assign(matches[n],seen) then matches[n]=index;return true end
            end
        end
        return false
    end
    while true do
        empty={};matches={}
        for _,target in ipairs(targets) do if target~=reserve and not target.item then empty[#empty+1]=target end end
        local fit=#bins<=#empty
        if fit then for n=1,#bins do if not Assign(n,{}) then fit=false;break end end end
        if fit then break end
        local compact
        for pass=1,2 do
            for _,source in ipairs(targets) do if source~=reserve and source.item and (source.space=="normal")== (pass==1) then
                local room=0;for _,target in ipairs(targets) do if target~=source and target~=reserve then room=room+Room(source,target) end end
                if room>=source.item.count then compact=source;break end
            end end
            if compact then break end
        end
        if not compact then return end
        for _,target in ipairs(targets) do if target~=compact and target~=reserve and compact.item then
            local count=math.min(compact.item.count,Room(compact,target))
            if count>0 then Move(steps,compact,target,count) end
        end end
    end
    for n,target in ipairs(empty) do if matches[n] then
        local bin=bins[matches[n]];Consume(bin.group,target,bin.count)
    end end
    return steps,{bag=reserve.bag,slot=reserve.slot}
end
function R:Plan(id,bankSocket)
    local socket
    local bagItem,err
    local kind,ids="bags"
    if bankSocket then
        local bag,container=A.BankBagContainer(bankSocket)
        if not B.bankOpen or not A.CanUsePersonalBank() or not bag then return nil,"error.changed" end
        kind,id,ids="bank",bag,A.BankBags("bank")
        bagItem,err=A.Slot(container,bankSocket)
    else
        for _,entry in ipairs(A.BagSockets()) do if entry.bag==id then socket=entry;break end end
        if not socket or id<=0 then return nil,"error.changed" end
        bagItem,err=A.BagState(socket.inventoryID)
        ids=A.GetCarryBags(false)
    end
    if not bagItem then return nil,err and "bag.remove_pending" or "error.changed" end
    if bagItem.locked then return nil,"bag.remove_locked" end
    if not B.Model.bags[id] or B.Model.bags[id].capacity<1 then return nil,"bag.remove_pending" end
    local sources,targets,choices={},{},{}
    for _,bagID in ipairs(ids) do
        local bag=B.Model.bags[bagID]
        if not bag or B.Runtime.readable[bagID]~=true then
            if not bankSocket or bagID==id or A.BankBagInstalled(bagID)~=false then return nil,"bag.remove_pending" end
            bag=nil
        end
        for slot=1,bag and bag.capacity or 0 do
            local item=bag.slots[slot];local key=Key(bagID,slot)
            local row={bag=bagID,id=bagID,slot=slot,key=key,family=bag.family,kind=bag.kind,space=bag.space,item=item}
            if bagID==id then
                if item then
                    if not Movable(item,key) then return nil,"bag.remove_locked" end
                    if not item.link or not item.loaded then return nil,"bag.remove_pending" end
                    sources[#sources+1]=row
                end
            elseif Movable(item,key) then
                targets[#targets+1]=row
                if bag.space=="normal" and (not item or (item.maxStack or 1)>1 and item.link) then choices[#choices+1]=row end
            end
        end
    end
    table.sort(targets,function(a,b) if (a.space=="normal")~=(b.space=="normal") then return a.space~="normal" end;return a.key<b.key end)
    table.sort(choices,function(a,b) local ac,bc=a.item and a.item.count or 0,b.item and b.item.count or 0;return ac==bc and a.key<b.key or ac<bc end)
    for _,choice in ipairs(choices) do
        local steps,target=Attempt(sources,targets,choice.key)
        if steps then
            return {bag=id,inventoryID=socket and socket.inventoryID,bankSocket=bankSocket,kind=kind,
                item=bagItem,steps=steps,target=target}
        end
        if not choice.item then break end
    end
    return nil,"bag.remove_space"
end
local function Installed(plan)
    if not plan.bankSocket then return A.BagState(plan.inventoryID) end
    local bag,container=A.BankBagContainer(plan.bankSocket)
    if not B.bankOpen or not A.CanUsePersonalBank() or bag~=plan.bag then return nil,true end
    return A.Slot(container,plan.bankSocket)
end
function R:Valid(plan)
    return plan and Same(Installed(plan),plan.item)
end
function R:Start(id,bankSocket)
    local actions=B.Actions
    if not B.active or A.InCombat() or A.CursorBusy() or actions.queue or actions.nativeSort then return false end
    B:ReadAll(false)
    local plan,err=self:Plan(id,bankSocket)
    if not plan then B:Notify(err);return false end
    actions.removalPlan=plan
    if not actions:Start(plan.steps,"bag-remove") then actions.removalPlan=nil;return false end
    return true
end
function R:Finish(plan)
    if not B.active or A.InCombat() or A.CursorBusy() or not self:Valid(plan) then return false end
    local slots,sourceCapacity=A.ReadBag(plan.bag)
    local occupied,err=A.Slot(plan.target.bag,plan.target.slot)
    local _,capacity,family=A.ReadBag(plan.target.bag)
    if not slots or sourceCapacity<1 or next(slots) or occupied or err or not capacity or plan.target.slot>capacity
        or A.SpaceKey(plan.target.bag,family,plan.kind)~="normal" or not Movable(nil,Key(plan.target.bag,plan.target.slot)) then return false end
    plan.sending=true
    local picked
    if plan.bankSocket then picked=A.MoveBankBag(plan.bankSocket) and A.CursorBusy()
    else picked=B.Runtime:CallNative(A.UnequipBag,plan.inventoryID) end
    local placed=picked and A.Pickup(plan.target.bag,plan.target.slot) and not A.CursorBusy()
    if not placed and A.CursorBusy() then
        if plan.bankSocket then
            local _,container=A.BankBagContainer(plan.bankSocket)
            if container then A.CancelBankBagPickup(container,plan.bankSocket,plan.item.itemID) end
        else B.Runtime:CallNative(A.RestoreBag,plan.inventoryID) end
    end
    plan.sending=nil;B.Runtime:CloseNativeBags()
    return placed
end
function R:Confirmed(plan)
    if not plan or plan.sending then return end
    local installed,err=Installed(plan)
    local target,targetError=A.Slot(plan.target.bag,plan.target.slot)
    if err or targetError then return end
    if installed then if not Same(installed,plan.item) then return false end;return end
    if plan.item.guid and target and not target.guid then return end
    return Same(target,plan.item) and target.count==1
end
