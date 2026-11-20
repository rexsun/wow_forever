local YUI=_G.YUI
local B=YUI and YUI.YBags
if not B then return end
local A=YUI.API.Bags
local C=B.Classification

local function BeforePosition(a,b)
    if a.bag~=b.bag then return a.bag<b.bag end
    return a.slot<b.slot
end

local function Snapshot(actions,bank,locks,preview)
    local ids=preview and preview.ids or bank and A.BankBags("bank") or A.GetCarryBags(false)
    local bags=preview and preview.bags or B.Model.bags
    local runtime,seen,domains=B.Runtime,{},{}
    for _,id in ipairs(ids) do
        local bag=bags[id]
        if bag and not seen[id] and runtime.readable[id]==true
            and (not bank or runtime.kind[id]=="bank") then
            seen[id]=true
            local family=bag.family or 0
            local key=bag.space=="reagent" and "reagent" or family
            local priority=key=="reagent" and 1 or family~=0 and 2 or 0
            domains[#domains+1]={bag=bag,key=key,priority=priority,slots={},items={},empty={}}
        end
    end
    table.sort(domains,function(a,b)
        if a.priority~=b.priority then return a.priority>b.priority end
        return a.bag.id<b.bag.id
    end)
    local items={}
    for _,domain in ipairs(domains) do
        local bag=domain.bag
        for slot=1,bag.capacity do
            local item=bag.slots[slot]
            if not locks[bag.id..":"..slot] and (not item or item.loaded~=false and item.link
                and item.itemID and item.count and item.count>0 and not item.held and not item.empty
                and not actions:Protected(item) and A.Fits(item,bag)) then
                local cell={bag=bag.id,slot=slot,domain=domain,item=item}
                domain.slots[#domain.slots+1]=cell
                if item then
                    items[#items+1]=cell
                    domain.items[#domain.items+1]=cell
                else
                    domain.empty[#domain.empty+1]=cell
                end
            end
        end
    end
    return domains,items
end

local function MakeStep(source,target,amount,combine)
    local item,destination=source.item,target.item
    return {
        source=item,
        target=combine and destination or {bag=target.bag,slot=target.slot},
        itemID=item.itemID,link=item.link,sourceCount=item.count,guid=item.guid,bound=item.bound,
        targetCount=destination and destination.count or 0,targetGUID=destination and destination.guid,
        count=amount and amount<item.count and amount or nil,combine=combine,
        swapTarget=not combine and destination or nil,checkSortSlot=true,
    }
end

local function LargerFirst(a,b)
    if a.item.count~=b.item.count then return a.item.count>b.item.count end
    return BeforePosition(a,b)
end

local function IndexPartials(items)
    local groups,ordered={},{}
    for _,cell in ipairs(items) do
        local item=cell.item
        local limit=item.maxStack or 1
        local key=item.count<=limit and C:StackKey(item)
        if key then
            key=key.."\031"..tostring(item.classID).."\031"..tostring(item.family or 0)
                .."\031"..tostring(item.isCraftingReagent==true).."\031"..tostring(item.equipLoc)
            cell.mergeKey=key
            if item.count<limit then
                local group=groups[key]
                if not group then
                    group={targets={},donors={},byDomain={}}
                    groups[key]=group
                    ordered[#ordered+1]=group
                end
                group.targets[#group.targets+1]=cell
            end
        end
    end
    -- Only partial stacks need receivers. Full stacks can still supply an
    -- existing stack in a higher-priority bag.
    for _,cell in ipairs(items) do
        local group=groups[cell.mergeKey]
        if group then
            local key=cell.domain.key
            local queue=group.byDomain[key]
            if not queue then
                queue={key=key,priority=cell.domain.priority}
                group.byDomain[key]=queue
                group.donors[#group.donors+1]=queue
            end
            queue[#queue+1]=cell
        end
    end
    for _,group in ipairs(ordered) do
        table.sort(group.targets,function(a,b)
            if a.domain.priority~=b.domain.priority then return a.domain.priority>b.domain.priority end
            return LargerFirst(a,b)
        end)
        for _,queue in ipairs(group.donors) do
            table.sort(queue,LargerFirst)
            queue.tail=#queue
        end
    end
    return ordered
end

local function MergeSource(group,target,used)
    local best
    for _,queue in ipairs(group.donors) do
        local sameDomain=queue.key==target.domain.key
        if sameDomain or queue.priority<target.domain.priority then
            while queue.tail>0 and used[queue[queue.tail]] do queue.tail=queue.tail-1 end
            local index=queue.tail
            while index>0 do
                local source=queue[index]
                if not used[source] and source~=target then
                    -- Within a domain, fill the larger partial from the smaller one.
                    if sameDomain and source.item.count>target.item.count then break end
                    if C:SameStack(source.item,target.item) and A.Fits(source.item,target.domain.bag) then
                        if not best or source.domain.priority<best.domain.priority
                            or source.domain.priority==best.domain.priority and source.item.count<best.item.count then
                            best=source
                        end
                    end
                    break
                end
                index=index-1
            end
        end
    end
    return best
end

local function PlanMerges(groups,priority,limit)
    local steps,used={},{}
    for _,group in ipairs(groups) do
        for _,target in ipairs(group.targets) do
            if target.domain.priority==priority and not used[target] then
                local source=MergeSource(group,target,used)
                if source then
                    local amount=math.min(source.item.count,target.item.maxStack-target.item.count)
                    steps[#steps+1]=MakeStep(source,target,amount,true)
                    used[source],used[target]=true,true
                    if #steps==limit then return steps end
                end
            end
        end
    end
    return steps
end

local function PlanSpecialEmpties(domains,items,priority,limit)
    local destinations={}
    for _,domain in ipairs(domains) do
        if domain.priority==priority and #domain.empty>0 then destinations[#destinations+1]=domain end
    end
    if #destinations==0 then return {} end
    local donors={}
    for _,cell in ipairs(items) do
        if cell.domain.priority<priority then donors[#donors+1]=cell end
    end
    table.sort(donors,LargerFirst)
    local steps,used={},{}
    for _,domain in ipairs(destinations) do
        local nextSlot=1
        -- Scan the donor index once per bag, never once per empty slot.
        for _,source in ipairs(donors) do
            if not used[source] and A.Fits(source.item,domain.bag) then
                steps[#steps+1]=MakeStep(source,domain.empty[nextSlot])
                if #steps==limit then return steps end
                used[source]=true
                nextSlot=nextSlot+1
                if nextSlot>#domain.empty then break end
            end
        end
    end
    return steps
end

local function ItemOrder(a,b)
    local x,y=a.item,b.item
    if (x.quality==0)~=(y.quality==0) then return y.quality==0 end
    local xClass,yClass=x.classID or 99,y.classID or 99
    if xClass~=yClass then return xClass<yClass end
    if x.itemID~=y.itemID then return x.itemID<y.itemID end
    if x.link~=y.link then return x.link<y.link end
    if (x.bound==true)~=(y.bound==true) then return x.bound~=true end
    if x.count~=y.count then return x.count<y.count end
    return BeforePosition(a,b)
end

local function PositionStep(source,target)
    if not A.Fits(source.item,target.domain.bag) then return end
    local destination=target.item
    if not destination then return MakeStep(source,target) end
    if not A.Fits(destination,source.domain.bag) then return end
    if source.item.itemID~=destination.itemID or source.item.link~=destination.link then
        return MakeStep(source,target)
    end
    -- An ordinary pickup would merge. Transfer the count difference to sort
    -- otherwise interchangeable stacks without swapping their identities.
    if C:SameStack(source.item,destination) and source.item.count~=destination.count
        and (source.item.maxStack or 1)>=math.max(source.item.count,destination.count) then
        if source.item.count<destination.count then source,target=target,source end
        return MakeStep(source,target,source.item.count-target.item.count,true)
    end
end

local function OrderScope(scope,steps,limit)
    table.sort(scope.items,ItemOrder)
    local wanted,positions={},{}
    for index,source in ipairs(scope.items) do
        local target=scope.slots[index]
        wanted[target],positions[source]=source,target
    end
    for _,cell in ipairs(scope.slots) do
        local source=wanted[cell]
        if cell.item and source and source~=cell and cell.item.count==source.item.count
            and C:SameStack(cell.item,source.item) then
            local other=positions[cell]
            wanted[other],wanted[cell]=source,cell
            positions[cell],positions[source]=cell,other
        end
    end
    local used={}
    -- Swapping into a desired occupied slot breaks one edge of a full
    -- permutation cycle. The next confirmed snapshot supplies the new edges.
    for _,target in ipairs(scope.slots) do
        local source=wanted[target]
        if source and source~=target and not used[source] and not used[target] then
            local step=PositionStep(source,target)
            if step then
                steps[#steps+1]=step
                used[source],used[target]=true,true
                if #steps==limit then return end
            end
        end
    end
end

local function PlanCompaction(domains,items,limit)
    local groups=IndexPartials(items)
    for priority=domains[1] and domains[1].priority or 0,1,-1 do
        local steps=PlanMerges(groups,priority,limit)
        if #steps>0 then return steps end
        steps=PlanSpecialEmpties(domains,items,priority,limit)
        if #steps>0 then return steps end
    end
    return PlanMerges(groups,0,limit)
end

function B.Actions:PlanSortRound(bank,limit)
    if limit==nil then limit=12 end
    if type(limit)~="number" or not (limit>=1) then return {} end
    limit=math.floor(math.min(limit,32))
    local config=B:GetConfig()
    local domains,items=Snapshot(self,bank,config.locks)
    local steps=PlanCompaction(domains,items,limit)
    if #steps>0 then return steps end

    local player=B.View.windows.player
    local layout=bank and config.bankView.layout or not bank and (player and player.layout or config.layout)
    -- The category view orders its own cells. Only the combined grid exposes physical order.
    if layout~="single" then return steps end
    local normal={items={},slots={}}
    for _,domain in ipairs(domains) do
        if domain.priority>0 then
            OrderScope(domain,steps,limit)
            if #steps==limit then return steps end
        else
            for _,cell in ipairs(domain.slots) do normal.slots[#normal.slots+1]=cell end
            for _,cell in ipairs(domain.items) do normal.items[#normal.items+1]=cell end
        end
    end
    OrderScope(normal,steps,limit)
    return steps
end

function B.Actions:BeginSortSpace()
    local ids=A.GetCarryBags(false)
    local preview={ids=ids,bags={},gained=0,remaining=0}
    for _,id in ipairs(ids) do
        local bag=B.Model.bags[id]
        if not bag or B.Runtime.readable[id]~=true then return end
        if not preview.bags[id] then
            local slots={}
            for slot,item in pairs(bag.slots) do
                local copy={}
                for key,value in pairs(item) do copy[key]=value end
                slots[slot]=copy
            end
            preview.bags[id]={id=id,capacity=bag.capacity,family=bag.family,space=bag.space,kind=bag.kind,slots=slots}
            preview.remaining=preview.remaining+bag.capacity*4
        end
    end
    return preview
end

function B.Actions:AdvanceSortSpace(preview)
    local domains,items=Snapshot(self,false,B:GetConfig().locks,preview)
    -- Positional ordering only exchanges slots or stack counts within the
    -- same bag domain. The shared compaction rules determine the net space.
    local steps=PlanCompaction(domains,items,self.sortRoundLimit)
    if #steps==0 then return true,preview.gained end
    if #steps>preview.remaining then return true end
    preview.remaining=preview.remaining-#steps
    for _,op in ipairs(steps) do
        local source,target=op.source,op.target
        local from=preview.bags[source.bag].slots
        if op.combine then
            local amount=op.count or source.count
            target.count,source.count=target.count+amount,source.count-amount
            if source.count==0 then
                from[source.slot]=nil
                preview.gained=preview.gained+1
            end
        else
            from[source.slot]=nil
            preview.bags[target.bag].slots[target.slot]=source
            source.bag,source.slot,source.key=target.bag,target.slot,target.bag..":"..target.slot
        end
    end
    return false
end
