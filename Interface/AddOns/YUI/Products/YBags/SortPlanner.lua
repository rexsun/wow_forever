local YUI=_G.YUI
local B=YUI and YUI.YBags
if not B then return end
local A=YUI.API.Bags
local C=B.Classification

local function BeforePosition(a,b)
    if a.bag~=b.bag then return a.bag<b.bag end
    return a.slot<b.slot
end

local function Snapshot(actions,bank,locks,preview,packQuestItems)
    local ids=preview and preview.ids or bank and A.BankBags("bank") or A.GetCarryBags(false)
    local bags=preview and preview.bags or B.Model.bags
    local rejected=not preview and actions.sortRound and actions.sortRound.rejectedRoutes
    local runtime,seen,domains=B.Runtime,{},{}
    for _,id in ipairs(ids) do
        local bag=bags[id]
        if bag and not seen[id] and runtime.readable[id]==true
            and (not bank or runtime.kind[id]=="bank") then
            seen[id]=true
            local family=bag.family or 0
            local key=bag.space=="reagent" and "reagent" or family
            local priority=key=="reagent" and 1 or family~=0 and 2 or 0
            domains[#domains+1]={bag=bag,key=key,priority=priority,slots={},items={},empty={},
                rejected=rejected and rejected[id]}
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
                and not actions:SortProtected(item,packQuestItems) and A.Fits(item,bag)) then
                local cell={bag=bag.id,slot=slot,domain=domain,item=item}
                domain.slots[#domain.slots+1]=cell
                if item then
                    -- Quest stacks can fill slots, but cannot donate to merges or material routing.
                    if not item.quest and item.classID~=12 then items[#items+1]=cell end
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

local function ReagentMergeSources(groups)
    local sources={}
    for _,group in ipairs(groups) do
        local ordinary,reagent=group.byDomain[0],group.byDomain.reagent
        if ordinary and #ordinary+(reagent and #reagent or 0)>1 then
            for _,cell in ipairs(ordinary) do
                if cell.item.count<cell.item.maxStack then sources[cell]=true end
            end
        end
    end
    return sources
end

local function PlanSpecialEmpties(domains,items,priority,limit,groups,reverse)
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
    local mergeSources=groups and ReagentMergeSources(groups)
    local replan=false
    for _,domain in ipairs(destinations) do
        local empty=domain.empty
        local nextSlot,lastSlot,increment=1,#empty,1
        if reverse then nextSlot,lastSlot,increment=lastSlot,nextSlot,-1 end
        -- Scan the donor index once per bag, never once per empty slot.
        for _,source in ipairs(donors) do
            if not used[source] and (not domain.rejected or not domain.rejected[source.item.itemID])
                and A.Fits(source.item,domain.bag) then
                local step=MakeStep(source,empty[nextSlot])
                step.professionRoute=priority==2 or nil
                steps[#steps+1]=step
                -- Crossing a previous planning boundary is safe unless a
                -- newly placed partial can change the next merge decision.
                replan=replan or mergeSources and mergeSources[source]
                if (not mergeSources or replan) and #steps%limit==0 then return steps end
                used[source]=true
                if nextSlot==lastSlot then break end
                nextSlot=nextSlot+increment
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

local placementSections={general=1,consumable=2,equipment=4,material=5,system=6,other=7,junk=8}

local function PlacementLess(a,b)
    if a.sectionOrder~=b.sectionOrder then return a.sectionOrder<b.sectionOrder end
    if a.groupOrder~=b.groupOrder then return a.groupOrder<b.groupOrder end
    if a.group~=b.group then return a.group<b.group end
    if a.priority~=b.priority then return a.priority<b.priority end
    if a.level~=b.level then return a.level>b.level end
    local x,y=a.item,b.item
    if x.itemID~=y.itemID then return x.itemID<y.itemID end
    if x.link~=y.link then return x.link<y.link end
    if (x.bound==true)~=(y.bound==true) then return x.bound~=true end
    if x.quality~=y.quality then return (x.quality or -1)<(y.quality or -1) end
    if x.charges~=y.charges then return (x.charges or -1)<(y.charges or -1) end
    return (x.maxStack or 1)<(y.maxStack or 1)
end

local function AddPlacementDonor(cell)
    local rank=cell.rank
    if not rank or rank==cell.wanted then return end
    local donors=cell.donors
    if not donors[rank] then donors[rank]={} end
    donors[rank][cell]=true
end

local function KeepMovablePlacementCells(cells)
    local kept=0
    for _,cell in ipairs(cells) do
        if not cell.pinned and not (cell.stackPeer and cell.stackPeer.pinned) then
            kept=kept+1
            cells[kept]=cell
        end
    end
    for index=#cells,kept+1,-1 do cells[index]=nil end
end

local function SetPlacementTargets(plan,slots,reverse,config)
    local items,donors,identities={},{},{}
    local hasConflicts=false
    for _,cell in ipairs(slots) do
        cell.donors=donors
        if cell.item then
            local item=B:Copy(cell.item)
            local section,group,order=item.section,item.group,item.groupOrder
            if not section or section=="recent" then section,group,order=C:Classify(item,config,B.Model.compiled,true) end
            cell.item,cell.group,cell.groupOrder=item,group,order
            cell.sectionOrder=section=="other" and group=="quest" and 3 or placementSections[section] or 7
            cell.priority=section=="general" and group=="favorites" and C:QuickAccessOrder(item.itemID) or 0
            cell.level=section=="equipment" and (item.level or -1) or 0
            items[#items+1]=cell

            local first=identities[item.itemID]
            local peer=first
            while peer and not C:SameStack(peer.item,item) do peer=peer.nextIdentity end
            if peer then
                cell.stackPeer=peer
                if PlacementLess(peer,cell) or PlacementLess(cell,peer) then
                    peer.pinned,hasConflicts=true,true
                end
            else
                cell.nextIdentity=first
                identities[item.itemID]=cell
            end
        end
    end
    if hasConflicts then
        -- An identical pickup can merge or be refused even when the two items
        -- have different display categories. Keep these positions reserved.
        KeepMovablePlacementCells(items)
        KeepMovablePlacementCells(slots)
    end
    plan.scopes[#plan.scopes+1]=slots
    table.sort(items,PlacementLess)
    local offset=reverse and #slots-#items or 0
    local previous,rank=nil,0
    for index,cell in ipairs(items) do
        if not previous or PlacementLess(previous,cell) then rank=rank+1 end
        cell.rank,slots[offset+index].wanted=rank,rank
        previous=cell
    end
    for _,cell in ipairs(slots) do
        AddPlacementDonor(cell)
        if cell.wanted and cell.wanted~=cell.rank then plan.targets[#plan.targets+1]=cell end
    end
end

local function PlanDirectionalPlacement(domains,reverse,config,verify)
    local ordinarySlots,plan={},{targets={},dirtyBags={},scopes={},bags={}}
    for _,domain in ipairs(domains) do
        local bag=domain.bag
        plan.bags[bag.id]={capacity=bag.capacity,family=bag.family,space=bag.space}
        if domain.priority>0 then
            SetPlacementTargets(plan,domain.slots,reverse,config)
        else
            for _,cell in ipairs(domain.slots) do ordinarySlots[#ordinarySlots+1]=cell end
        end
    end
    SetPlacementTargets(plan,ordinarySlots,reverse,config)
    if verify or #plan.targets>0 then return plan end
end

function B.Actions:PlanPlacementSteps(plan)
    local steps,used={},{}
    local misplaced=false
    for pass=1,2 do
        for _,target in ipairs(plan.targets) do
            if target.rank~=target.wanted then
                misplaced=true
                local donors=target.donors[target.wanted]
                if donors and not target.pending and not used[target] and (not target.item)==(pass==1) then
                    local source
                    for cell in pairs(donors) do
                        if not cell.pending and not used[cell] and not C:SameStack(cell.item,target.item)
                            and (not source or BeforePosition(cell,source)) then source=cell end
                    end
                    if source then
                        local step=MakeStep(source,target)
                        step.placementSource,step.placementTarget=source,target
                        steps[#steps+1]=step
                        used[source],used[target]=true,true
                    end
                end
            end
        end
    end
    return steps,misplaced
end

local function ConfirmPlacementCell(cell,rank)
    if cell.rank and cell.rank~=cell.wanted then cell.donors[cell.rank][cell]=nil end
    local item=B.Model.bags[cell.bag].slots[cell.slot]
    cell.item,cell.rank,cell.pending=item and B:Copy(item),rank,nil
    AddPlacementDonor(cell)
end

function B.Actions:ConfirmPlacementStep(op)
    local source,target=op.placementSource,op.placementTarget
    local sourceRank=source.rank
    ConfirmPlacementCell(source,target.rank)
    ConfirmPlacementCell(target,sourceRank)
end

local function AddMaterialPair(wave,source,destination)
    if not A.Fits(source.item,destination.domain.bag) then return false end
    local operation=MakeStep(source,destination,nil,true)
    operation.materialPaired=true
    wave[#wave+1]=operation
    destination.item=B:Copy(destination.item)
    destination.item.count=destination.item.count+source.item.count
    return true
end

local function MaterialWaves(group,target,firstSource,limit)
    local donors=group.byDomain[0]
    if not donors or not donors[#donors] or donors[#donors].item~=firstSource then return nil,"source-not-normal" end
    local sources,room={},target.item.maxStack-target.item.count
    -- Match the direct planner's donor order. Stop at an exact fill so
    -- any excess donors are left in the same slots for later compaction.
    for index=#donors,1,-1 do
        local cell=donors[index]
        if not C:SameStack(cell.item,target.item) or not A.Fits(cell.item,target.domain.bag) then
            return nil,"incompatible-source"
        end
        if cell.item.count>room then return nil,"needs-partial-stack" end
        if math.floor((#sources+2)/2)>limit then return nil,"round-limit" end
        sources[#sources+1]=cell
        room=room-cell.item.count
        if room==0 then break end
    end
    if #sources<3 then return nil,"fewer-than-three-donors" end
    for index,cell in ipairs(sources) do
        sources[index]={bag=cell.bag,slot=cell.slot,domain=cell.domain,item=B:Copy(cell.item)}
    end

    local material={bag=target.bag,slot=target.slot,domain=target.domain,item=B:Copy(target.item)}
    local waves={}
    while #sources>0 do
        local wave,nextSources={},{}
        local count=#sources
        -- Keep the destination in its original material slot. Pair it with
        -- one donor in even-sized waves and pair the remaining donors locally.
        if count%2==1 then
            if not AddMaterialPair(wave,sources[count],material) then return nil,"incompatible-source" end
            count=count-1
        end
        for index=1,count,2 do
            local destination=sources[index]
            if not AddMaterialPair(wave,sources[index+1],destination) then return nil,"incompatible-source" end
            nextSources[#nextSources+1]=destination
        end
        waves[#waves+1]=wave
        sources=nextSources
    end
    return waves
end

local function PlanMaterialWaves(steps,groups,limit)
    local candidates={}
    for _,group in ipairs(groups) do
        local target,count
        for _,cell in ipairs(group.targets) do
            if cell.domain.key=="reagent" then target,count=cell,(count or 0)+1 end
        end
        if count==1 then candidates[target.item]={group=group,target=target} end
    end
    local waves,extra={},0
    local paired=false
    for _,step in ipairs(steps) do
        local candidate=candidates[step.target]
        local planned,reason
        if candidate then planned,reason=MaterialWaves(candidate.group,candidate.target,step.source,limit)
        else reason="multiple-targets" end
        local fits=planned and #steps+extra+#planned[1]-1<=limit
        if fits then
            for index=2,#planned do
                if #(waves[index] or {})+#planned[index]>limit then fits=false;break end
            end
        end
        if fits then
            paired=true
            extra=extra+#planned[1]-1
            for index,wave in ipairs(planned) do
                waves[index]=waves[index] or {}
                for _,operation in ipairs(wave) do waves[index][#waves[index]+1]=operation end
            end
        else
            step.materialFallback=reason or "round-limit"
            waves[1]=waves[1] or {}
            waves[1][#waves[1]+1]=step
        end
    end
    return paired and waves or nil
end

local function PlanPriorityCompaction(domains,items,groups,limit,allowMaterialWaves,reverse)
    for priority=domains[1] and domains[1].priority or 0,1,-1 do
        local steps=PlanMerges(groups,priority,limit)
        if #steps>0 then
            local waves=allowMaterialWaves and priority==1 and PlanMaterialWaves(steps,groups,limit)
            if allowMaterialWaves and priority~=1 then
                for _,step in ipairs(steps) do step.materialFallback="profession-bag" end
            end
            return waves and waves[1] or steps,"material-merge",waves or nil
        end
        local routeGroups=allowMaterialWaves and priority==1 and groups
        steps=PlanSpecialEmpties(domains,items,priority,limit,routeGroups,reverse)
        if #steps>0 then return steps,"material-route" end
    end
end

local function PlanCompaction(domains,items,limit,allowMaterialWaves,reverse)
    local groups=IndexPartials(items)
    local steps,phase,waves=PlanPriorityCompaction(domains,items,groups,limit,allowMaterialWaves,reverse)
    if steps then return steps,phase,waves end
    return PlanMerges(groups,0,limit)
end

local function CategoryGroups(groups,reserved)
    local ready,deferred,index={},{},0
    for _,group in ipairs(groups) do
        local cells,bySlot,wait={},{},false
        for _,cell in ipairs(group.byDomain[0] or {}) do
            if cell.item.count<(cell.item.maxStack or 1) then
                local key=cell.bag..":"..cell.slot
                cell.item=B:Copy(cell.item)
                cells[#cells+1]=cell
                bySlot[key]=cell
                wait=wait or reserved and reserved[key]
            end
        end
        if #cells>1 then
            index=index+1
            local queue=wait and deferred or ready
            queue[#queue+1]={cells=cells,bySlot=bySlot,moves={},nextMove=1,queued=true,index=index}
        end
    end
    if #ready>0 then return {ready=ready,deferred=reserved and deferred,head=1,issued=0} end
end

local function ProjectMaterialWaves(domains,waves)
    local bySlot,reserved={},{}
    for _,domain in ipairs(domains) do
        for _,cell in ipairs(domain.slots) do bySlot[cell.bag..":"..cell.slot]=cell end
    end
    -- These are private snapshot cells. Items shared with the live model are read-only.
    for _,wave in ipairs(waves) do
        for _,op in ipairs(wave) do
            local from,to=op.source.bag..":"..op.source.slot,op.target.bag..":"..op.target.slot
            local source,target=bySlot[from],bySlot[to]
            local amount=op.count or op.sourceCount
            reserved[from],reserved[to]=true,true
            if amount==op.sourceCount then source.item=nil
            else
                source.item=B:Copy(source.item)
                source.item.count=op.sourceCount-amount
            end
            target.item=B:Copy(target.item)
            target.item.count=op.targetCount+amount
        end
    end
    local items={}
    for _,domain in ipairs(domains) do
        domain.items,domain.empty={},{}
        for _,cell in ipairs(domain.slots) do
            cell.mergeKey=nil
            if cell.item then
                domain.items[#domain.items+1]=cell
                items[#items+1]=cell
            else domain.empty[#domain.empty+1]=cell end
        end
    end
    return items,reserved
end

function B.Actions:BeginCategoryMerges(limit,allowMaterialWaves)
    local config=B:GetConfig()
    local player=B.View.windows.player
    if (player and player.layout or config.layout)~="category" then return end
    local domains,items=Snapshot(self,false,config.locks)
    local groups=IndexPartials(items)
    local prioritySteps,phase,waves=PlanPriorityCompaction(domains,items,groups,limit,allowMaterialWaves)
    if prioritySteps then
        if waves then
            local projected,reserved=ProjectMaterialWaves(domains,waves)
            local projectedGroups=IndexPartials(projected)
            -- If specialty work remains, preserve its original turn before ordinary merges.
            if not PlanPriorityCompaction(domains,projected,projectedGroups,limit,false) then
                local state=CategoryGroups(projectedGroups,reserved)
                if state then return nil,state,phase,waves end
            end
        end
        return prioritySteps,nil,phase,waves
    end

    local state=CategoryGroups(groups)
    if state then return nil,state end
    return {}
end

function B.Actions:PlanCategoryMergeGroup(group,limit)
    local cells={}
    for _,cell in ipairs(group.cells) do
        if cell.item then cells[#cells+1]=cell end
    end
    local steps=PlanMerges(IndexPartials(cells),0,limit)
    for _,op in ipairs(steps) do
        local from,to=op.source,op.target
        local source=group.bySlot[from.bag..":"..from.slot]
        local target=group.bySlot[to.bag..":"..to.slot]
        op.mergePredecessor,op.mergeTargetPredecessor=source.previous,target.previous
        source.previous,target.previous=op,op
        -- Plan the next pass against private counts. The send path still
        -- waits for both real slot receipts before it can use those counts.
        local amount=op.count or from.count
        if amount<from.count then
            source.item=B:Copy(from)
            source.item.count=from.count-amount
        else source.item=nil end
        target.item=B:Copy(to)
        target.item.count=to.count+amount
    end
    return steps
end

function B.Actions:PlanSortRound(bank,limit,allowMaterialWaves,direction)
    if limit==nil then limit=12 end
    if type(limit)~="number" or not (limit>=1) then return {} end
    limit=math.floor(math.min(limit,32))
    local config=B:GetConfig()
    local directional=YUI.IsForever and not bank and direction
    local domains,items=Snapshot(self,bank,config.locks,nil,directional)
    local reverse=directional=="reverse"
    local steps,phase,waves=PlanCompaction(domains,items,limit,allowMaterialWaves,reverse)
    if #steps>0 then return steps,phase,waves end

    if directional then
        local verify=self.sortRound and self.sortRound.replanned
        return {},nil,nil,PlanDirectionalPlacement(domains,reverse,config,verify)
    end

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
