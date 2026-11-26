local YUI = _G.YUI
local B = YUI and YUI.YBags
if not B then return end
local Cache = {}
B.Cache = Cache
Cache.tooltipBags=setmetatable({},{__mode="k"})
local function OnItemTooltip(tooltip)
    if not B.active or tooltip~=GameTooltip or B.View:ItemTooltipBlocked() then return end
    local info=tooltip.processingInfo
    if not info or info.excludeLines then return end
    local owner=tooltip:GetOwner()
    local data=owner and B.View.buttonData[owner]
    local item=data and data.item or Cache.tooltipBags[owner] and owner
    if item and not item.empty then Cache:AppendTooltip(item,tooltip,true) end
end
function Cache:InstallTooltip()
    local api=YUI.API.Bags
    if not self.tooltipHook and api and api.RegisterItemTooltip then self.tooltipHook=api.RegisterItemTooltip(OnItemTooltip) end
end
-- Register the data phase before carrier features attach trailing metadata.
Cache:InstallTooltip()
local fields={"itemID","link","name","icon","quality","count","level","classID","subClassID","subType","equipLoc","price","maxStack","family","system","quest","bound","bindType","guid","isCraftingReagent","charges","maxCharges","chargeConsumable"}
local locations={equipped=true,bankBags=true,mail=true,auctions=true,void=true}
local tooltipLocations={"bags","bank","equipped","mail","auctions","void"}
local function LocationTotals(snapshot)
    local totals,nextExpiry={},nil
    local now=time()
    for _,item in ipairs(snapshot.items or {}) do
        if not item.expires or item.expires>now then
            totals[item.itemID]=(totals[item.itemID] or 0)+item.count
            if item.expires then nextExpiry=math.min(nextExpiry or item.expires,item.expires) end
        end
    end
    snapshot.totals,snapshot.nextExpiry=totals,nextExpiry
end
function Cache:LocationCount(character,kind,id)
    local snapshot=character.locations and character.locations[kind]
    if not snapshot then return 0 end
    if not snapshot.totals or snapshot.nextExpiry and snapshot.nextExpiry<=time() then LocationTotals(snapshot) end
    return snapshot.totals[id] or 0
end
function Cache:WriteLocation(kind,entries,complete)
    if not locations[kind] or not self.player or self.suppressed then return end
    local previous=self.player.locations and self.player.locations[kind]
    if complete==false and previous and previous.complete then return end
    local snapshot={items=entries,updated=time(),revision=(previous and previous.revision or 0)+1,complete=complete~=false}
    LocationTotals(snapshot)
    self.player.locations=self.player.locations or {};self.player.locations[kind]=snapshot
end
function Cache:AddMail(key,entries)
    local character=self.db and self.db.characters[key]
    if not character or character.source~=self.source then return end
    character.locations=character.locations or {}
    local previous=character.locations.mail
    local snapshot={items=B:Copy(previous and previous.items or {}),updated=time(),revision=(previous and previous.revision or 0)+1,complete=previous and previous.complete==true or false}
    for _,item in ipairs(entries) do
        local copy=B:Copy(item);copy.expires=copy.expires or time()+30*86400;snapshot.items[#snapshot.items+1]=copy
    end
    LocationTotals(snapshot);character.locations.mail=snapshot
end
local function AccountKey(character) return character.client..":account:"..character.source end
local function RebuildTotals(container)
    local totals={}
    for _,bag in pairs(container.bags or {}) do for _,item in pairs(bag.slots or {}) do
        totals[item.itemID]=(totals[item.itemID] or 0)+item.count
    end end
    container.totals=totals
end
function Cache:Migrate()
    if self.db.schema>=2 then return end
    for _,character in pairs(self.db.characters) do
        if character.client and character.source and character.containers then
            local shared=character.containers.shared
            if shared then
                local key=AccountKey(character)
                local owner=self.db.shared[key]
                if not owner then owner={name=B:T("window.shared"),source=character.source,client=character.client,container={bags={},totals={},complete=false}};self.db.shared[key]=owner end
                local target=owner.container
                for id,bag in pairs(shared.bags or {}) do
                    local previous=target.bags[id]
                    if not previous or (shared.updated or 0)>(previous.updated or 0) then
                        target.bags[id]=B:Copy(bag);target.bags[id].updated=shared.updated or 0
                    end
                end
                target.updated=math.max(target.updated or 0,shared.updated or 0)
                character.containers.shared=nil
            end
            if character.containers.guild then
                character.legacyContainers=character.legacyContainers or {}
                character.legacyContainers.guild=character.containers.guild
                character.containers.guild=nil
            end
        end
    end
    for _,owner in pairs(self.db.shared) do
        local container=owner.container
        if container then
            container.totals={}
            for _,bag in pairs(container.bags) do for _,item in pairs(bag.slots) do container.totals[item.itemID]=(container.totals[item.itemID] or 0)+item.count end end
        end
    end
    self.db.schema=2
end
function Cache:UpdateGuild()
    local guild=YUI.API.Bags.GuildIdentity()
    local key=guild and B.client..":guild:"..guild.key
    self.guildKey=key
    if self.player then self.player.guildKey=key end
    if key and not self.clearedForSession and not self.db.guilds[key] then
        self.db.guilds[key]={name=guild.name,realm=guild.realm,client=B.client}
    end
    return key
end
function Cache:Resolve(owner,kind)
    if not self.db then return owner,nil end
    local character=self.db and self.db.characters[owner]
    if kind=="shared" then
        if self.db.shared[owner] then return owner,self.db.shared[owner] end
        local key=character and AccountKey(character) or owner
        return key,self.db.shared[key]
    elseif kind=="guild" then
        if self.db.guilds[owner] then return owner,self.db.guilds[owner] end
        local key=character and character.guildKey or owner
        return key,key and self.db.guilds[key]
    end
    return owner,character
end
function Cache:GetContainer(owner,kind)
    local _,record=self:Resolve(owner,kind)
    if not record then return nil end
    if kind=="shared" or kind=="guild" then return record.container end
    return record.containers and record.containers[kind]
end
function Cache:Directory(kind)
    if kind~="shared" and kind~="guild" then
        local result={}
        for _,entry in ipairs(self:List()) do if self:GetContainer(entry.key,kind) then result[#result+1]=entry end end
        return result
    end
    local result={}
    for key,record in pairs(kind=="shared" and self.db.shared or self.db.guilds) do
        if record.client==B.client and record.container then result[#result+1]={key=key,data=record,kind=kind} end
    end
    table.sort(result,function(a,b) return a.key<b.key end)
    return result
end
function Cache:Initialize()
    self.db=B:GetCacheDB()
    self:Migrate()
    -- Saved slot records are authoritative; persisted summary indexes may be stale.
    for _,character in pairs(self.db.characters) do
        if character.client==B.client then
            for _,snapshot in pairs(character.locations or {}) do LocationTotals(snapshot) end
            for _,kind in ipairs({"bags","bank"}) do
                local container=character.containers and character.containers[kind]
                if container then RebuildTotals(container) end
            end
        end
    end
    for _,owners in ipairs({self.db.shared,self.db.guilds}) do for _,owner in pairs(owners) do
        if owner.client==B.client and owner.container then RebuildTotals(owner.container) end
    end end
    local guid=YUI.API.Security.SafeString(UnitGUID("player"))
    local name,realm=UnitFullName("player")
    if B.client=="forever" then name,realm=YUI.API.Bags.PlayerName(),GetRealmName() end
    realm=realm or GetRealmName()
    if not guid or not name then return false end
    self.source=self.db.source or guid..":"..tostring(time())
    self.playerKey=B.client..":"..self.source..":"..guid
    local character=self.db.characters[self.playerKey] or {containers={}}
    character.name,character.realm,character.guid,character.source,character.client=name,realm,guid,self.source,B.client
    character.localAccount=true
    local identity=YUI.API.Bags.CharacterInfo()
    for _,field in ipairs({"classFile","raceFile","sex"}) do character[field]=identity[field] end
    self.player=character
    self.accountKey=AccountKey(character)
    self.suppressed=self.clearedForSession==true
    if not self.suppressed then
        self.db.source=self.source
        self.db.characters[self.playerKey]=character
        for _,record in pairs(self.db.characters) do
            if record.source==self.source then YUI.CharacterMoney:RememberCharacter(B.HOST_ID,record) end
        end
        if not self.db.shared[self.accountKey] then self.db.shared[self.accountKey]={name=B:T("window.shared"),source=self.source,client=B.client} end
    end
    self:UpdateGuild()
    self.tooltipOrder=nil
    return true
end
function Cache:WriteBag(kind,id,bag,complete)
    if not self.player or not bag then return end
    local shared=kind=="shared" or kind=="guild"
    if not shared and self.suppressed then return end
    local ownerKey=kind=="shared" and self.accountKey or kind=="guild" and self.guildKey or self.playerKey
    local _,owner=self:Resolve(ownerKey,kind)
    if not owner then return end
    local container=self:GetContainer(ownerKey,kind)
    if not container then
        container={bags={},complete=false}
        if shared then owner.container=container else owner.containers[kind]=container end
    end
    local totals=container.totals or {};container.totals=totals
    local previous=container.bags[tostring(id)]
    if previous then for _,item in pairs(previous.slots) do local n=(totals[item.itemID] or 0)-item.count;totals[item.itemID]=n~=0 and n or nil end end
    local target={id=id,capacity=bag.capacity,family=bag.family,space=bag.space or YUI.API.Bags.SpaceKey(id,bag.family,kind),updated=time(),slots={}}
    for slot,item in pairs(bag.slots) do
        local record={bag=id,slot=slot,uid=item.uid,revision=item.revision}
        for _,key in ipairs(fields) do record[key]=item[key] end
        target.slots[slot]=record
        totals[item.itemID]=(totals[item.itemID] or 0)+item.count
    end
    container.bags[tostring(id)]=target
    container.revision=container.updated==target.updated and (container.revision or 0)+1 or 1
    container.updated=target.updated
    local pending=owner.pendingBagReads and owner.pendingBagReads[kind]
    if pending then
        pending[id]=nil
        if not next(pending) then
            owner.pendingBagReads[kind]=nil
            if not next(owner.pendingBagReads) then owner.pendingBagReads=nil end
            pending=nil
        end
    end
    container.complete=complete==true and not pending
    B.Stats.snapshots=B.Stats.snapshots+1
end
local function SnapshotOwnerMatches(cache,batch)
    return not cache.suppressed and batch.owner and cache.player==batch.owner and cache.playerKey==batch.key
        and cache.db and cache.db.characters[batch.key]==batch.owner
end
function Cache:RequireLocalBagRead(kind,id,reason)
    local owner=self.player
    if self.suppressed or not owner then return end
    -- Local recovery state survives logout and stays out of exported containers.
    owner.pendingBagReads=owner.pendingBagReads or {}
    local pending=owner.pendingBagReads[kind] or {}
    owner.pendingBagReads[kind]=pending
    pending[id]=reason or pending[id] or true
    local container=self:GetContainer(self.playerKey,kind)
    if container then container.complete=false end
end
function Cache:RequireTransferRead(batch,kind,id)
    if SnapshotOwnerMatches(self,batch) then self:RequireLocalBagRead(kind,id) end
end
function Cache:WriteModelBag(kind,id,bag)
    local transfer=B.Actions.transferResult
    local batch=transfer and transfer.snapshots
    if batch and (kind=="bags" or kind=="bank") then
        local op=B.Actions.queue[B.Actions.index]
        local round=B.Actions.equipmentTransfer
        if batch.touched[id] or round and round.bags[id] or op and (op.source.bag==id or op.target.bag==id) then
            if SnapshotOwnerMatches(self,batch) then batch.touched[id]=kind end
            return
        end
    end
    self:ResumeLocal()
    self:WriteBag(kind,id,bag,false)
end
function Cache:FinishTransferSnapshots(transfer)
    local batch=transfer.snapshots
    transfer.snapshots=nil
    if not batch or not SnapshotOwnerMatches(self,batch) then return end
    for id,kind in pairs(batch.touched) do
        local bag=B.Model.bags[id]
        if bag and bag.kind==kind then
            if B.Runtime.readable[id] and B.Runtime.kind[id]==kind then
                self:WriteBag(kind,id,bag,batch.complete[kind])
            end
        end
    end
    -- Preserve uncertainty after all writes, including when both bags share a container.
    for id,kind in pairs(batch.touched) do
        if B.Runtime.dirty[id] or not B.Runtime.readable[id] or B.Runtime.kind[id]~=kind then
            self:RequireTransferRead(batch,kind,id)
        end
    end
    local actions=B.Actions
    local round=actions.equipmentTransfer
    if round then
        local function RequireEnds(op)
            local targetKind=op.target.kind
            self:RequireTransferRead(batch,targetKind=="bank" and "bags" or "bank",op.source.bag)
            self:RequireTransferRead(batch,targetKind,op.target.bag)
        end
        if round.submitting then RequireEnds(round.submitting) end
        for _,receipt in pairs(round.targets) do RequireEnds(receipt.operation) end
    end
    local op=actions.queue and actions.queue[actions.index]
    if actions.transferResult==transfer and op and op.personalTransfer and
        (actions.waiting or B.Runtime.dirty[op.source.bag] or B.Runtime.dirty[op.target.bag]) then
        local targetKind=op.target.kind
        self:RequireTransferRead(batch,targetKind=="bank" and "bags" or "bank",op.source.bag)
        self:RequireTransferRead(batch,targetKind,op.target.bag)
    end
end
function Cache:Recount(kind)
    local container=self.player and self:GetContainer(self.playerKey,kind)
    if not container then return end
    RebuildTotals(container)
end
function Cache:List()
    local result={}
    for key,character in pairs(self.db and self.db.characters or {}) do
        if character.client==B.client then result[#result+1]={key=key,data=character} end
    end
    table.sort(result,function(a,b)
        if a.data.localAccount~=b.data.localAccount then return a.data.localAccount==true end
        if a.data.realm~=b.data.realm then return a.data.realm<b.data.realm end
        return a.data.name<b.data.name
    end)
    return result
end
function Cache:GetItems(key,kind)
    local container=self:GetContainer(key,kind)
    if not container then return nil end
    local items,empties,ids={},{},{}
    for _,bag in pairs(container.bags) do ids[#ids+1]=bag.id end
    table.sort(ids)
    for _,id in ipairs(ids) do
        local bag=container.bags[tostring(id)]
        local space=bag.space or YUI.API.Bags.SpaceKey(id,bag.family,kind)
        for slot=1,bag.capacity do
            local item=bag.slots[slot]
            if item then
                local copy=B:Copy(item)
                copy.new=false
                copy.key=tostring(id)..":"..slot;copy.uid=copy.uid or "cache:"..copy.key
                copy.space=space
                copy.section,copy.group,copy.groupOrder=B.Classification:Classify(copy,B:GetConfig(),B.Model.compiled)
                items[#items+1]=copy
            else empties[#empties+1]={empty=true,bag=id,slot=slot,family=bag.family or 0,space=space} end
        end
    end
    return items,empties,container
end
-- One guild may have been visited by characters of different ranks. During
-- a live visit even the shared inventory line must respect this viewer's tabs.
local tabTotals=setmetatable({},{__mode="k"})
local function VisibleGuildCount(container,itemID)
    local total=0
    for _,tab in ipairs(YUI.API.Bags.GuildTabs()) do
        local bag=tab.view and container.bags[tostring(tab.id)]
        if bag then
            local counts=tabTotals[bag]
            if not counts then
                counts={}
                for _,item in pairs(bag.slots) do counts[item.itemID]=(counts[item.itemID] or 0)+item.count end
                tabTotals[bag]=counts
            end
            total=total+(counts[itemID] or 0)
        end
    end
    return total
end
function Cache:AppendTooltip(item,tooltip,processed)
    if self.tooltipHook and not processed then return end
    if not self.db or not item then return end
    tooltip=tooltip or GameTooltip
    if item.members and item.charges~=nil and (item.displayCount or 0)>1 then
        tooltip:AddLine(string.format(B:T("item.group_charges"),item.displayCount,item.charges,item.displayCount*item.charges))
    end
    if not self.tooltipOrder then self.tooltipOrder=self:List() end
    local displayLimit=4
    local rows,stores,total={},{shared={},guild={}},0
    for _,entry in ipairs(self.tooltipOrder) do
        local containers=entry.data.containers
        local bags,bank=containers and containers.bags,containers and containers.bank
        local carried,stored=bags and bags.totals and bags.totals[item.itemID] or 0,bank and bank.totals and bank.totals[item.itemID] or 0
        local equipped=self:LocationCount(entry.data,"equipped",item.itemID)+self:LocationCount(entry.data,"bankBags",item.itemID)
        local mail=self:LocationCount(entry.data,"mail",item.itemID)
        local auctions=self:LocationCount(entry.data,"auctions",item.itemID)
        local void=self:LocationCount(entry.data,"void",item.itemID)
        local count=carried+stored+equipped+mail+auctions+void
        if count>0 then
            rows[#rows+1]={key=entry.key,character=entry.data,bags=carried,bank=stored,equipped=equipped,mail=mail,auctions=auctions,void=void,count=count};total=total+count
        end
    end
    for _,kind in ipairs({"shared","guild"}) do for key,owner in pairs(kind=="shared" and self.db.shared or self.db.guilds) do
        local container=owner.container
        local count=owner.client==B.client and container and container.totals and container.totals[item.itemID] or 0
        if count>0 and kind=="guild" and B.guildOpen and key==self.guildKey then count=VisibleGuildCount(container,item.itemID) end
        if count>0 then
            local group=stores[kind]
            group[#group+1]={key=key,name=owner.name,count=count}
            total=total+count
        end
    end end
    if total==0 then return end
    table.sort(rows,function(a,b)
        local aCurrent,bCurrent=a.key==self.playerKey,b.key==self.playerKey
        if aCurrent~=bCurrent then return aCurrent end
        if a.count~=b.count then return a.count>b.count end
        return a.key<b.key
    end)
    local function ByKey(a,b) return a.key<b.key end
    table.sort(stores.guild,ByKey)
    table.sort(stores.shared,ByKey)
    local G=YUI.GUI2
    local hr,hg,hb=G:GetColor("color.text.heading")
    local sr,sg,sb=G:GetColor("color.text.secondary")
    local labelColor=string.format("|cff%02x%02x%02x",math.floor(sr*255+.5),math.floor(sg*255+.5),math.floor(sb*255+.5))
    local function Detail(key,count)
        return labelColor..B:T(key).."|r|cffffffff"..count.."|r"
    end
    tooltip:AddDoubleLine(B:T("inventory.title"),Detail("inventory.total",total),hr,hg,hb,1,1,1)
    for i=1,math.min(#rows,displayLimit) do
        local row=rows[i]
        local character=row.character
        local race,_,r,g,b=YUI.API.Bags.CharacterAppearance(character)
        local label=" "..B.Appearance:TooltipPortrait(race)..character.name
        if not character.localAccount then label=label.." · "..B:T("cache.other_account") end
        if character.realm and character.realm~=GetRealmName() then label=label.." · "..character.realm end
        local parts={}
        for _,kind in ipairs(tooltipLocations) do
            if row[kind]>0 then parts[#parts+1]=Detail("inventory."..kind,row[kind]) end
        end
        tooltip:AddDoubleLine(label,table.concat(parts,"  "),r,g,b,1,1,1)
    end
    if #rows>displayLimit then
        tooltip:AddLine(string.format(B:T("inventory.more_characters"),#rows-displayLimit),sr,sg,sb)
    end
    for i=1,math.min(#stores.guild,displayLimit) do
        local store=stores.guild[i]
        local name=type(store.name)=="string" and store.name~="" and store.name:gsub("|","||") or B:T("window.guild")
        local label=" |A:UI-HUD-MicroMenu-GuildCommunities-GuildColor-Up:16:16|a "..name
        tooltip:AddDoubleLine(label,Detail("inventory.guild",store.count),1,.8,15/255,1,1,1)
    end
    if #stores.guild>displayLimit then
        tooltip:AddLine(string.format(B:T("inventory.more_guilds"),#stores.guild-displayLimit),sr,sg,sb)
    end
    for _,store in ipairs(stores.shared) do
        tooltip:AddDoubleLine("  "..B:T("window.shared"),Detail("inventory.bank",store.count),sr,sg,sb,1,1,1)
    end
end
function Cache:Forget(key)
    if not self.db then return end
    if key then self.db.characters[key]=nil else self.db.characters={} end
    self.tooltipOrder=nil
    if B.View then B.View:CloseCaches(key) end
    if key==nil or key==self.playerKey then
        self.suppressed=true
    end
end
function Cache:ClearPersonalData()
    local db=B:GetCacheDB()
    if not db then return false end
    self.db=db
    -- A clean export must stay clear through late reads, logout and toggling the module.
    self.clearedForSession=true
    self.suppressed=true
    db.shared,db.guilds={},{}
    if self.player then
        self.player.containers={}
        self.player.locations=nil
        self.player.pendingBagReads=nil
    end
    if B.Sync then B.Sync:Disable() end
    self:Forget()
    local view=B.View
    if view then
        local owner=GameTooltip:GetOwner()
        if owner and (view.buttonData[owner] or self.tooltipBags[owner]) then GameTooltip:Hide() end
        if view.directoryPanel then view.directoryPanel:Hide() end
    end
    if B.guildOpen then B.BankView:Refresh("guild") end
    return true
end
function Cache:ResumeLocal()
    if self.db and self.player and not self.suppressed and not self.db.characters[self.playerKey] then
        self.db.characters[self.playerKey]=self.player;self.tooltipOrder=nil
    end
end
function Cache:Merge(payload)
    local clean,valid=B:Plain(payload,0,nil,{left=250000})
    if not valid then return false end
    payload=clean
    if type(payload)~="table" or payload.client~=B.client or type(payload.characters)~="table" or type(payload.source)~="string" or #payload.source>120 or payload.source==self.source then return false end
    local accepted,records=0,0
    local function Integer(value,minimum,maximum)
        return type(value)=="number" and value==math.floor(value) and value>=minimum and value<=maximum
    end
    local sanitized={}
    for key,character in pairs(payload.characters) do
        if type(key)~="string" or #key>220 or type(character)~="table" or character.source~=payload.source or character.client~=B.client
            or type(character.name)~="string" or #character.name>80 or type(character.realm)~="string" or #character.realm>120 or type(character.containers)~="table"
            or type(character.guid)~="string" or #character.guid>80 or key~=B.client..":"..payload.source..":"..character.guid then return false end
        accepted=accepted+1;if accepted>50 then return false end
        local cleanCharacter={name=character.name,realm=character.realm,guid=character.guid,source=payload.source,client=B.client,containers={},locations={}}
        if character.locations~=nil then
            if type(character.locations)~="table" then return false end
            for kind,snapshot in pairs(character.locations) do
                if not locations[kind] or type(snapshot)~="table" or type(snapshot.items)~="table" or not Integer(snapshot.updated,1,time()+300) then return false end
                if snapshot.revision~=nil and not Integer(snapshot.revision,0,2147483647) then return false end
                local clean={items={},updated=snapshot.updated,revision=snapshot.revision or 0,complete=snapshot.complete==true}
                local size=0
                for index,item in pairs(snapshot.items) do
                    records=records+1;size=size+1
                    if records>50000 or not Integer(index,1,50000) or type(item)~="table" or not Integer(item.itemID,1,100000000) or not Integer(item.count,1,100000)
                        or item.expires~=nil and not Integer(item.expires,0,time()+366*86400) then return false end
                    clean.items[index]={itemID=item.itemID,count=item.count,expires=item.expires}
                end
                if #clean.items~=size then return false end
                LocationTotals(clean);cleanCharacter.locations[kind]=clean
            end
        end
        for _,field in ipairs({"classFile","raceFile"}) do
            local value=character[field]
            if value~=nil and (type(value)~="string" or #value>40 or not value:match("^[%a]+$")) then return false end
            cleanCharacter[field]=value
        end
        if character.sex~=nil and not Integer(character.sex,1,3) then return false end
        cleanCharacter.sex=character.sex
        sanitized[key]=cleanCharacter
        for kind,container in pairs(character.containers) do
            if kind~="bags" and kind~="bank" then return false end
            if type(container)~="table" or type(container.bags)~="table" or not Integer(container.updated,1,time()+300) then return false end
            if container.revision~=nil and not Integer(container.revision,0,2147483647) then return false end
            local cleanContainer={bags={},updated=container.updated,revision=container.revision or 0,complete=container.complete==true,totals={}}
            cleanCharacter.containers[kind]=cleanContainer
            local bagCount=0
            for bagKey,bag in pairs(container.bags) do
                bagCount=bagCount+1
                if bagCount>24 or type(bag)~="table" or not Integer(bag.capacity,0,512) or not Integer(bag.id,-100,100) or bagKey~=tostring(bag.id)
                    or not Integer(bag.family or 0,0,2147483647) or type(bag.slots)~="table" then return false end
                local cleanBag={id=bag.id,capacity=bag.capacity,family=bag.family or 0,slots={}}
                if B.client=="forever" and kind=="bank" and bag.space=="reagent" then cleanBag.space="reagent" end
                cleanContainer.bags[bagKey]=cleanBag
                for slot,item in pairs(bag.slots) do
                    records=records+1
                    if records>50000 or not Integer(slot,1,bag.capacity) or type(item)~="table"
                        or not Integer(item.itemID,1,100000000) or not Integer(item.count,1,100000) then return false end
                    for _,field in ipairs({"link","name","subType","equipLoc","system","guid"}) do
                        if item[field]~=nil and (type(item[field])~="string" or #item[field]>1024) then return false end
                    end
                    for _,field in ipairs({"icon","quality","level","classID","subClassID","price","maxStack","family","charges","maxCharges"}) do
                        if item[field]~=nil and not Integer(item[field],0,2147483647) then return false end
                    end
                    local record={bag=bag.id,slot=slot,uid=key..":"..kind..":"..bag.id..":"..slot,name=""}
                    for _,field in ipairs({"quest","bound","isCraftingReagent","chargeConsumable"}) do if item[field]~=nil and type(item[field])~="boolean" then return false end end
                    if item.bindType~=nil and (type(item.bindType)~="number" or item.bindType<0 or item.bindType>255 or item.bindType%1~=0) then return false end
                    for _,field in ipairs(fields) do if type(item[field])~="table" then record[field]=item[field] end end
                    record.name=record.name or ""
                    cleanBag.slots[slot]=record
                    cleanContainer.totals[record.itemID]=(cleanContainer.totals[record.itemID] or 0)+record.count
                end
            end
        end
    end
    for key,character in pairs(sanitized) do
        local existing=self.db.characters[key]
        if not existing then existing={containers={}};self.db.characters[key]=existing end
        if not existing.localAccount then
            existing.name,existing.realm,existing.source,existing.guid,existing.client=character.name,character.realm,character.source,character.guid,B.client
            existing.localAccount=false
            existing.classFile,existing.raceFile,existing.sex=character.classFile,character.raceFile,character.sex
            for kind,container in pairs(character.containers) do
                local previous=existing.containers[kind]
                if not previous or (container.updated>(previous.updated or 0) or container.updated==previous.updated and container.revision>(previous.revision or 0))
                    and (container.complete or not previous.complete) then existing.containers[kind]=B:Copy(container) end
            end
            existing.locations=existing.locations or {}
            for kind,snapshot in pairs(character.locations) do
                local previous=existing.locations[kind]
                if not previous or (snapshot.updated>previous.updated or snapshot.updated==previous.updated and snapshot.revision>(previous.revision or 0))
                    and (snapshot.complete or not previous.complete) then existing.locations[kind]=B:Copy(snapshot) end
            end
        end
    end
    self.tooltipOrder=nil
    return true
end
function Cache:Payload()
    local characters={}
    for key,character in pairs(self.db.characters) do
        if character.source==self.source and character.localAccount then
            local copy={name=character.name,realm=character.realm,guid=character.guid,source=self.source,client=B.client,containers={}}
            copy.classFile,copy.raceFile,copy.sex=character.classFile,character.raceFile,character.sex
            copy.locations=character.locations
            for _,kind in ipairs({"bags","bank"}) do copy.containers[kind]=character.containers[kind] end
            characters[key]=copy
        end
    end
    return {client=B.client,source=self.source,characters=characters}
end
