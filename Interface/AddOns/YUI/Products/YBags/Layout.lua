local YUI = _G.YUI
local B = YUI and YUI.YBags
if not B then return end
local Layout = {}
B.Layout = Layout
local function Space(item) return item.space or ((item.family or 0)~=0 and "family:"..item.family or "normal") end
local function BagTypeOrder(item)
    -- Occupied cells carry the item's family, not the container's family.
    local space=item.space or (item.empty and Space(item)) or "normal"
    if space=="normal" then return 1 end
    if space=="reagent" then return 3 end
    return 2
end
local function SingleCellLess(a,b)
    if a.bag~=b.bag then
        local aType,bType=BagTypeOrder(a),BagTypeOrder(b)
        if aType~=bType then return aType<bType end
        return a.bag<b.bag
    end
    return a.slot<b.slot
end
local function HeldCell(item)
    local hole={}
    for key,value in pairs(item) do if key~="members" then hole[key]=value end end
    hole.empty,hole.held=true,true
    return hole
end
function Layout:RefreshAggregate(group,live,fixed)
    local total,representative=0,nil
    for _,member in ipairs(group.members) do
        local current=live and live[member.uid] or not live and member
        if current and B.Classification:SameStack(current,group) then
            total=total+current.count
            if fixed then
                if current.bag==group.bag and current.slot==group.slot then representative=current end
            elseif not representative or representative.locked and not current.locked
                or (not representative.locked==not current.locked and (current.count<representative.count
                    or current.count==representative.count and (current.bag<representative.bag
                        or current.bag==representative.bag and current.slot<representative.slot))) then representative=current end
        end
    end
    if not representative then return false end
    local uid=group.uid
    for key,value in pairs(representative) do group[key]=value end
    group.uid,group.physicalUID,group.displayCount=uid,representative.uid,total
    group.key=tostring(representative.bag)..":"..representative.slot
    return true
end
function Layout:Aggregate(items,expanded,separated)
    local result,groups,live={},{},{}
    local locks=B:GetConfig().locks
    for _,item in ipairs(items) do
        local key=B.Classification:StackKey(item)
        local individual=separated and separated[item.key]
        individual=individual and individual.itemID==item.itemID and individual.link==item.link and (not individual.guid or individual.guid==item.guid)
        if key and not individual and not (expanded and expanded[key]) and not locks[item.key] then
            local identity=(item.section or "other").."\031"..(item.group or "").."\031"..key
            local group=groups[identity]
            if not group then
                group={};for field,value in pairs(item) do group[field]=value end
                group.uid,group.stackKey,group.members="group:"..identity,key,{}
                groups[identity]=group;result[#result+1]=group
            end
            group.members[#group.members+1]=item
        else result[#result+1]=item end
    end
    for _,item in ipairs(result) do
        if item.members then self:RefreshAggregate(item) end
        live[item.uid]=item
    end
    return result,live
end
function Layout:OrderSplits(items,placements)
    if not placements or not next(placements) then return items end
    local bySlot,children,placed,anchored,aggregates,leading={},{},{},{},{},{}
    for _,item in ipairs(items) do if not item.empty then
        bySlot[tostring(item.bag)..":"..item.slot]=item
        if item.members then aggregates[(item.section or "other").."\031"..(item.group or "").."\031"..item.stackKey]=item end
    end end
    for key,placement in pairs(placements) do
        local item,source=bySlot[key],bySlot[placement.source]
        if item and placement.stackKey then
            source=aggregates[(item.section or "other").."\031"..(item.group or "").."\031"..placement.stackKey] or source
        end
        if item and source and item~=source and item.itemID==placement.itemID and item.link==placement.link
            and (placement.stackKey or not placement.sourceGUID or source.guid==placement.sourceGUID) and (not placement.guid or item.guid==placement.guid)
            and item.group==source.group and item.section==source.section then
            local bucket=placement.stackKey and source.members and leading or children
            local list=bucket[source]
            if not list then list={};bucket[source]=list end
            list[#list+1]={item=item,order=placement.order};placed[item]=true
            local anchor=placement.anchor
            local before=anchor and bySlot[anchor.before]
            if before and before~=source and not anchored[source] and B.Classification:SameStack(before,source)
                and (not anchor.guid or anchor.guid==before.guid) then
                local preceding=children[before]
                if not preceding then preceding={};children[before]=preceding end
                preceding[#preceding+1]={item=source,order=-1};placed[source]=true;anchored[source]=true
            end
        end
    end
    for _,list in pairs(children) do table.sort(list,function(a,b) return a.order<b.order end) end
    for _,list in pairs(leading) do table.sort(list,function(a,b)
        if a.item.count~=b.item.count then return a.item.count<b.item.count end
        return a.order<b.order
    end) end
    local result,emitted,pending={},{},{}
    local function Emit(item)
        pending[1]=item
        while #pending>0 do
            local current=table.remove(pending)
            if not emitted[current] then
                emitted[current]=true
                local first=leading[current]
                if first then for _,entry in ipairs(first) do
                    if not emitted[entry.item] then emitted[entry.item]=true;result[#result+1]=entry.item end
                end end
                result[#result+1]=current
                local list=children[current]
                if list then for n=#list,1,-1 do pending[#pending+1]=list[n].item end end
            end
        end
    end
    for _,item in ipairs(items) do if not placed[item] then Emit(item) end end
    -- Stale slot relationships may form cycles; every cell must still appear once.
    for _,item in ipairs(items) do if not emitted[item] then Emit(item) end end
    return result
end
function Layout:EmptyGroups(empties,aggregate)
    local groups,order={},{}
    for _,item in ipairs(empties) do
        if item.empty then
            local key=Space(item);local group=groups[key]
            if not group then group={key=key,items={}};groups[key]=group;order[#order+1]=group end
            group.items[#group.items+1]=item
        end
    end
    table.sort(order,function(a,b) if a.key=="normal" then return b.key~="normal" end;if b.key=="normal" then return false end;return a.key<b.key end)
    for _,group in ipairs(order) do
        if aggregate then
            local first=group.items[1]
            group.items={{empty=true,aggregate=#group.items,bag=first.bag,slot=first.slot,family=first.family,space=group.key}}
        end
    end
    return order
end

function Layout:MaxColumns(available,config)
    return math.max(3,math.min(24,math.floor((available-28)/(config.slotSize+3))))
end
function Layout:Columns(count, available, config, current)
    local limit = self:MaxColumns(available,config)
    local wanted = config.autoSize and 12 or config.columns
    return math.min(limit, math.max(config.autoSize and current or 0, wanted))
end
function Layout:Build(items, empties, config, cols, collapsed, query)
    local nodes, step, y = {}, config.slotSize+3, 0
    local function Cell(item, x, rowY) nodes[#nodes+1]={kind="item",item=item,x=x,y=rowY,h=step,section=item.section,group=item.group} end
    if config.layout == "single" then
        local cells={}
        for _, item in ipairs(items) do cells[#cells+1]=item end
        if config.emptyMode=="one" then
            for _,item in ipairs(empties) do if not item.empty then cells[#cells+1]=item end end
            for _,group in ipairs(self:EmptyGroups(empties,true)) do cells[#cells+1]=group.items[1] end
        else for _, item in ipairs(empties) do cells[#cells+1]=item end end
        table.sort(cells,SingleCellLess)
        for n,item in ipairs(cells) do Cell(item,((n-1)%cols)*step,math.floor((n-1)/cols)*step) end
        return nodes, math.ceil(#cells/cols)*step
    end
    local sections={}
    for _, id in ipairs(B.Classification.sections) do sections[id]={} end
    for _, item in ipairs(items) do sections[item.section or "other"][#sections[item.section or "other"]+1]=item end
    for _,item in ipairs(sections.system) do sections.other[#sections.other+1]=item end
    sections.system={}
    local gridWidth=cols*step-3
    local bandX, bandY, bandHeight, bandCollapsed = 0, 0, 0, nil
    local soleHeading
    local function FinishBand()
        if soleHeading and not soleHeading.collapsed then
            soleHeading.w,soleHeading.divider=gridWidth,true
        end
        if bandHeight>0 then y=bandY+bandHeight+4 end
        bandX, bandHeight, bandCollapsed = 0, 0, nil
        soleHeading=nil
        bandY=y
    end
    for _, id in ipairs(B.Classification.sections) do
        local list=sections[id]
        if #list>0 then
            table.sort(list,function(a,b)
                if id=="other" and (a.section=="system")~=(b.section=="system") then return a.section=="system" end
                return B.Classification:Compare(a,b)
            end)
            list=self:OrderSplits(list,config.splitPlacements)
            local count=0;for _,item in ipairs(list) do if not item.held then count=count+1 end end
            local groups,order={},{}
            for _,item in ipairs(list) do
                local group=id=="other" and item.group=="" and "misc" or item.group
                if not groups[group] then groups[group]={};order[#order+1]=group end
                groups[group][#groups[group]+1]=item
            end
            local showSubnames=config.showSubnames and id~="recent" and id~="junk" and id~="system"
            local isCollapsed=collapsed[id]==true
            local small=(id=="material" or id=="other") and (isCollapsed or #list<=cols)
            local groupWidths,packedWidth={},0
            if small and not collapsed[id] then
                for _,group in ipairs(order) do
                    local width=#groups[group]*step-3
                    if showSubnames and group~="" then width=math.max(width,B.Appearance:TextWidth(B.Appearance:GroupText(group),"label")+2) end
                    groupWidths[group]=width;packedWidth=packedWidth+width+3
                end
            end
            local headingWidth=B.Appearance:HeadingWidth(id,count,collapsed[id])
            if small and packedWidth-3>gridWidth then small=false end
            local width=small and math.min(gridWidth,math.max(headingWidth,packedWidth-3)) or gridWidth
            -- Compact collapsed headings share a row with each other, never an open block.
            if not small or bandX+width>gridWidth or bandHeight>0 and bandCollapsed~=isCollapsed then FinishBand() end
            bandCollapsed=isCollapsed
            local startX, startY=bandX,bandY
            local heading={kind="heading",section=id,x=startX,y=startY,w=width,h=16,count=count,collapsed=isCollapsed,divider=false}
            nodes[#nodes+1]=heading
            soleHeading=bandHeight==0 and heading or nil
            local localY,x=16,0
            if not collapsed[id] then
                local rows,row={},nil
                local function Row()
                    row={cells={},labels={}};rows[#rows+1]=row;x=0
                end
                Row()
                local afterSeparateRow
                for _, group in ipairs(order) do
                    local members=groups[group]
                    local fixed=id=="equipment" and B.Classification:IsFixedGearGroup(group)
                    local separateRow=id=="equipment" and group==B.Classification.tradeGroup
                    local showLabel=group~="" and (showSubnames or fixed)
                    if small then
                        if showLabel then row.labels[#row.labels+1]={text=group,x=x,w=groupWidths[group]} end
                        for n,item in ipairs(members) do row.cells[#row.cells+1]={item=item,x=x+(n-1)*step} end
                        x=x+groupWidths[group]+3
                    else
                        if x>0 and (separateRow or afterSeparateRow) then Row() end
                        local at=1
                        while at<=#members do
                            if x>=cols then Row() end
                            local count=math.min(#members-at+1,cols-x)
                            if showLabel and at==1 then
                                row.labels[#row.labels+1]={text=group,x=x*step,w=(separateRow and cols or count)*step-3}
                            end
                            for k=0,count-1 do row.cells[#row.cells+1]={item=members[at+k],x=(x+k)*step} end
                            at,x=at+count,x+count
                        end
                    end
                    afterSeparateRow=separateRow
                end
                for rowIndex,entry in ipairs(rows) do
                    if rowIndex==1 and #entry.labels>0 then localY=localY+1 end
                    local caption=#entry.labels>0 and 14 or 0
                    for _,text in ipairs(entry.labels) do
                        caption=math.max(caption,B.Appearance:WrappedTextHeight(B.Appearance:GroupText(text.text),text.w))
                    end
                    for _,text in ipairs(entry.labels) do nodes[#nodes+1]={kind="label",section=id,text=text.text,x=startX+text.x,y=startY+localY,w=text.w,h=caption} end
                    for _,cell in ipairs(entry.cells) do Cell(cell.item,startX+cell.x,startY+localY+caption) end
                    localY=localY+step+caption
                end
                localY=localY-3
            end
            bandHeight=math.max(bandHeight,localY)
            bandX=bandX+width+8
            if not small then FinishBand() end
        end
    end
    FinishBand()
    if #empties>0 then
        local count=0;for _,item in ipairs(empties) do if item.empty then count=count+1 end end
        nodes[#nodes+1]={kind="heading",section="empty",x=0,y=y,w=cols*step-3,h=16,count=count,collapsed=collapsed.empty==true,divider=not collapsed.empty};y=y+16
        if not collapsed.empty then
            local groups=self:EmptyGroups(empties,config.emptyMode=="one")
            local index=0
            for _,item in ipairs(empties) do if not item.empty then Cell(item,(index%cols)*step,y+math.floor(index/cols)*step);index=index+1 end end
            for _,group in ipairs(groups) do
                for _,item in ipairs(group.items) do
                    Cell(item,(index%cols)*step,y+math.floor(index/cols)*step)
                    index=index+1
                end
            end
            y=y+math.ceil(index/cols)*step
        end
    end
    return nodes,y
end
local function Identity(item,domain)
    local key=tostring(item.link or item.itemID)..":"..tostring(item.bound)
    return domain and domain.."\031"..key or key
end
local function SlotKey(item) return tostring(item.bag)..":"..item.slot end
local function PositionDomain(item,section,group)
    local part=(item.classID==2 or item.classID==4) and (item.equipLoc or "") or ""
    return (section or item.section or "other").."\031"..(group or item.group or "").."\031"..part.."\031"..Space(item)
end
local function ReplacementKey(item,domain,section,group)
    if item.new then return nil end
    if item.classID==2 or item.classID==4 then
        if not item.equipLoc or item.equipLoc=="" then return nil end
        return domain or PositionDomain(item,section,group)
    end
    return domain
end
function Layout:Retain(previous,items,empties,live,personalTransfer)
    local byUID,oldUID,candidates,used,byGUID,oldGUID={},{},{},{},{},{}
    local bySlot,replacements,remaining,matched={},{},{},{}
    local domains=personalTransfer and {}
    for _,item in ipairs(items) do
        byUID[item.uid]=item;bySlot[SlotKey(item)]=item
        if domains then domains[item]=PositionDomain(item) end
        local key=domains and domains[item] or item.section or "other"
        remaining[key]=(remaining[key] or 0)-1
    end
    for _,node in ipairs(previous) do
        local item=node.item
        if item and item.uid then
            oldUID[item.uid]=true;if item.guid then oldGUID[item.guid]=true end
            -- Explicit placements are projected into the empty area separately.
            if byUID[item.uid] or not live[item.uid] then
                if domains then domains[node]=PositionDomain(item,node.section,node.group) end
                local key=domains and domains[node] or node.section or item.section or "other"
                remaining[key]=(remaining[key] or 0)+1
            end
        end
    end
    for _,item in ipairs(items) do
        if not oldUID[item.uid] then
            if item.guid then byGUID[item.guid]=item end
            local domain=domains and domains[item]
            local identity=Identity(item,domain);local bucket=candidates[identity]
            if not bucket then bucket={next=1};candidates[identity]=bucket end
            bucket[#bucket+1]=item
            local key=ReplacementKey(item,domain)
            if key and not (item.guid and oldGUID[item.guid]) then
                local group=replacements[key]
                if not group then group={next=1};replacements[key]=group end
                group[#group+1]=item
            end
        end
    end
    local function Take(bucket)
        if not bucket then return nil end
        while bucket.next<=#bucket do
            local item=bucket[bucket.next];bucket.next=bucket.next+1
            if not item.new and not used[item.uid] and not (item.guid and oldGUID[item.guid]) then return item end
        end
    end
    -- Resolve every surviving/returning identity before assigning replacements.
    for _,node in ipairs(previous) do
        local old=node.item
        if old and old.uid then
            local current=byUID[old.uid]
            if not current and not live[old.uid] then
                current=old.guid and byGUID[old.guid]
                if current and used[current.uid] then current=nil end
                if not current then current=Take(candidates[Identity(old,domains and domains[node])]) end
            end
            if current and not used[current.uid] then matched[node]=current;used[current.uid]=true end
        end
    end
    -- Prefer a compatible same-slot exchange; a delayed return can also replace
    -- its held cell. Compatible non-held positions take precedence over holes.
    for pass=1,3 do
        for _,node in ipairs(previous) do
            local old=node.item
            if old and old.uid and not matched[node] and not live[old.uid] and (pass==1 or (old.held==true)==(pass==3)) then
                local key=ReplacementKey(old,domains and domains[node],node.section,node.group)
                if key then
                    local current
                    if pass==1 then
                        current=bySlot[SlotKey(old)]
                        if current and (used[current.uid] or oldUID[current.uid] or current.guid and oldGUID[current.guid] or ReplacementKey(current,domains and domains[current])~=key) then current=nil end
                    else current=Take(replacements[key]) end
                    if current then matched[node]=current;used[current.uid]=true end
                end
            end
        end
    end
    local emptyByKey,reserved,freeBySpace={},{},{}
    for _,item in ipairs(empties) do
        emptyByKey[SlotKey(item)]=item
        local key=Space(item);local group=freeBySpace[key]
        if not group then group={next=1};freeBySpace[key]=group end
        group[#group+1]=item
    end
    local function Reserve(item)
        -- A disappearing aggregate may still have an occupied representative slot.
        if item.physicalUID and B.Model.byUID[item.physicalUID] then return nil end
        local key=SlotKey(item)
        local empty=emptyByKey[key]
        if not empty or reserved[key] or Space(empty)~=Space(item) then
            local group=freeBySpace[Space(item)]
            if not group then return nil end
            while group.next<=#group and reserved[SlotKey(group[group.next])] do group.next=group.next+1 end
            empty=group[group.next]
        end
        if empty then reserved[SlotKey(empty)]=true end
        return empty
    end
    local projection,adjusted={},{}
    for _,node in ipairs(previous) do
        local old=node.item
        if old and old.uid then
            local current=matched[node]
            if current then
                -- A surviving identity can be reclassified. Build places it in its new group.
                if not personalTransfer or node.section==current.section and node.group==current.group then
                    adjusted[#adjusted+1]={kind="item",item=current,x=node.x,y=node.y,h=node.h,section=node.section,group=node.group}
                end
            elseif not live[old.uid] and not B.Classification:IsFixedGearGroup(node.group) then
                local key=domains and domains[node] or node.section or old.section or "other"
                local empty=(remaining[key] or 0)>0 and Reserve(old)
                if empty then
                    remaining[key]=remaining[key]-1
                    local hole=HeldCell(old);hole.bag,hole.slot=empty.bag,empty.slot;hole.space=Space(empty)
                    projection[#projection+1]=hole
                    adjusted[#adjusted+1]={kind="item",item=hole,x=node.x,y=node.y,h=node.h,section=node.section,group=node.group}
                end
            end
        else adjusted[#adjusted+1]=node end
    end
    for _,item in ipairs(items) do projection[#projection+1]=item end
    local free={}
    for _,item in ipairs(empties) do if not reserved[SlotKey(item)] then free[#free+1]=item end end
    return projection,free,adjusted
end
function Layout:KeepPositions(previous, current, live)
    local known, result,headings,previousHeadings = {}, {},{},{}
    for _, node in ipairs(previous) do
        if node.kind=="item" and node.item.uid then known[node.item.uid]=node end
        if node.kind=="heading" then previousHeadings[node.section]=true end
    end
    for _,node in ipairs(current) do if node.kind=="heading" then
        if not previousHeadings[node.section] then return current end
        headings[node.section]=node
    end end
    -- A last retained cell can disappear without introducing any new item
    -- identity. In that case its subgroup label must disappear as well.
    local labelIndex=1
    for _,node in ipairs(previous) do
        if node.kind=="label" then
            while current[labelIndex] and current[labelIndex].kind~="label" do labelIndex=labelIndex+1 end
            local label=current[labelIndex]
            if not label or label.section~=node.section or label.text~=node.text then return current end
            labelIndex=labelIndex+1
        end
    end
    for i=labelIndex,#current do if current[i].kind=="label" then return current end end
    for _, node in ipairs(current) do
        if node.kind=="item" and not node.item.empty then
            local previousNode=known[node.item.uid]
            if not previousNode or previousNode.section~=node.section or previousNode.group~=node.group then return current end
        end
    end
    for _, node in ipairs(previous) do
        if node.kind=="item" and not node.item.empty then
            local nextItem=live[node.item.uid]
            local copy={kind="item",item=nextItem or HeldCell(node.item),x=node.x,y=node.y,h=node.h,section=node.section,group=node.group}
            result[#result+1]=copy
        elseif node.kind=="heading" then
            local heading=headings[node.section]
            if not heading or heading.collapsed~=node.collapsed or heading.w~=node.w or heading.h~=node.h then return current end
            local copy=B:Copy(node);copy.count=heading.count;result[#result+1]=copy
        else result[#result+1]=node end
    end
    -- Physical empty slots may change after a return; never reuse stale bindings.
    local empties={};local count=0
    for _,node in ipairs(current) do if node.item and node.item.empty and not node.item.held then empties[#empties+1]=node.item end end
    for index,node in ipairs(result) do
        if node.item and node.item.empty and not node.item.held then
            count=count+1;if not empties[count] or Space(node.item)~=Space(empties[count]) then return current end
            node={kind="item",item=empties[count],x=node.x,y=node.y,h=node.h,section=node.section,group=node.group}
            -- Replace only this node; previous geometry remains an immutable snapshot.
            result[index]=node
        end
    end
    if count~=#empties then return current end
    local cells=0;for _,node in ipairs(result) do if node.item then cells=cells+1 end end
    local expected=0;for _,node in ipairs(current) do if node.item then expected=expected+1 end end
    if cells~=expected then return current end
    return result
end
