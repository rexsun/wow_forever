local YUI=_G.YUI
local B=YUI and YUI.YBags
if not B then return end
local A,S=YUI.API.Bags,YUI.API.Security
local D={knownTabs={},guildPages={},guildRequests={}}
B.Deposit=D
local querySpacing,replyWindow=.2,2
-- Auto-store settles across two inventories and can outlive a tab query.
local withdrawalWindow=10
local function ItemPayload(link)
    if type(link)=="string" then return link:match("|H(item:%d+[^|]*)|h") or link:match("^(item:%d+[^|]*)$") end
end
function D:SameGuildLink(first,second)
    local payload=ItemPayload(first)
    return payload~=nil and payload==ItemPayload(second)
end
-- Forever sends context in ItemBonuses only when a bonus list exists. Match
-- only the observed plain link shape. No enchant, suffix, gems, bonuses,
-- modifiers, or unknown tail may be discarded. The spec is viewer metadata.
local function PlainGuildContext(link)
    local payload=ItemPayload(link)
    if payload then return payload:match("^(item:%d+::::::::%d+:)%d+::([1-9]%d*):::::::$") end
end
local function IsGuildContextOmission(source,target)
    local base=PlainGuildContext(source)
    local payload=ItemPayload(target)
    return base~=nil and payload~=nil and payload:match("^(item:%d+::::::::%d+:)%d+:::::::::$")==base
end
function D:GuildStackMatches(source,item,wasEmpty)
    if not item or source.itemID~=item.itemID then return false end
    local origins=self.guildOrigins and self.guildOrigins[item.bag]
    local origin=origins and origins[item.slot]
    if not wasEmpty and origin and IsGuildContextOmission(origin,item.link) then
        local _,expected=PlainGuildContext(origin)
        local _,actual=PlainGuildContext(source.link)
        if actual~=expected then return false end
    end
    if self:SameGuildLink(source.link,item.link) then return true end
    return source.classID==0 and item.classID==0 and source.maxStack and source.maxStack>1 and item.maxStack==source.maxStack
        and (not source.charges or source.charges==0) and (not item.charges or item.charges==0)
        and source.quality~=nil and source.quality==item.quality and source.bound==false
        and IsGuildContextOmission(source.link,item.link)
end
function D:RecordGuildOrigin(source,target)
    local origins=self.guildOrigins[target.bag]
    if source.classID==0 and source.maxStack and source.maxStack>1 and PlainGuildContext(source.link) then
        if not origins then origins={};self.guildOrigins[target.bag]=origins end
        origins[target.slot]=source.link
    elseif origins then origins[target.slot]=nil end
end
function D:GuildEquipmentReceiptCount(op,source,destination)
    if op.guildQuota and not destination and not op.count and op.guid and source.guid==op.guid
        and (source.classID==2 or source.classID==4) and source.maxStack==1 and source.count==1
        and source.bound==false and PlainGuildContext(source.link) then
        return A.ItemCount(source.itemID)
    end
end
function D:GuildEquipmentContextOmitted(waiting,target)
    local source=waiting.source
    return waiting.equipmentCount and waiting.equipmentCount>=1 and source.quality~=nil
        and source.classID==target.classID and source.quality==target.quality and target.maxStack==1
        and IsGuildContextOmission(source.link,target.link)
end
local function SameGuild()
    if not B.guildOpen or not D.guildOwner or D.guildOwner~=B.Cache.guildKey then return false end
    local guild=A.GuildIdentity()
    return guild and D.guildOwner==B.client..":guild:"..guild.key
end
local function CancelQueryTimer()
    if D.queryTimer then
        D.queryTimer:Cancel()
        D.queryTimer=nil
        B.Stats.timers=B.Stats.timers-1
    end
end
function D:ResetGuild()
    self.withdrawal=nil
    self:CancelBagDeposit()
    if B.View and B.View.guildDepositDialog then B.View.guildDepositDialog:Hide() end
    CancelQueryTimer()
    self.knownTabs={}
    self.guildPages={}
    self.guildRequests={}
    self.guildOrigins={}
    self.allowed,self.toQuery,self.slotEvents,self.purchased,self.emptyRead={},{},{},{},{}
    self.overviewChecks,self.departed,self.refreshingEmpty={},{},{}
    self.guildOwner,self.queryTab,self.selectedRequest,self.cursorSource=nil,nil,nil,nil
    self.purchaseIntent,self.purchaseDeadline,self.lastOverview,self.lastSelection=nil,nil,nil,nil
end
local function ReadableTab(tab)
    if not tab or not D.allowed or not D.allowed[tab] or not SameGuild() then return end
    if A.GuildTabCount and tab>(A.GuildTabCount() or 0) then return false end
    local info=A.GuildTab(tab)
    return info and info.view and info
end
local PumpQueries
local function ShowingOverview()
    local w=B.View.windows["live-guild"]
    return w and w.open and not w.page and w.guildMode=="items"
end
-- This evidence only feeds the overview. Physical slot actions still use
-- GetGuildPage / emptyRead, both of which become unavailable on a new query.
local function StartTabRead(tab)
    if D.emptyRead[tab] then D.refreshingEmpty[tab]=true end
    D.emptyRead[tab]=nil
end
local function OverviewEmpty(tab)
    return D.emptyRead[tab] or D.refreshingEmpty[tab]
end
local function RefreshTabSnapshot(tab,locks)
    local old,empty,request=D.guildPages[tab],OverviewEmpty(tab),D.guildRequests[tab]
    D:SnapshotGuild(locks,tab)
    return old~=D.guildPages[tab] or empty~=OverviewEmpty(tab)
        or not ShowingOverview() and request~=D.guildRequests[tab]
end
local function ScheduleQuery(delay)
    if YUI.IsForever and not D.queryTimer and A.QueryGuildPage and not A.InCombat()
        and (D.queryTab or next(D.toQuery) or next(D.overviewChecks)) then
        local timer
        timer=C_Timer.NewTimer(delay,function()
            if D.queryTimer==timer then PumpQueries() end
        end)
        D.queryTimer=timer
        B.Stats.timers=B.Stats.timers+1
    end
end
PumpQueries=function()
    D.queryTimer=nil
    B.Stats.timers=B.Stats.timers-1
    if not SameGuild() or A.InCombat() or not A.BankWindowShown("guild") then return end
    local now=GetTime()
    if D.queryTab then
        local at=D.guildRequests[D.queryTab]
        if at and now-at<replyWindow then ScheduleQuery(replyWindow-(now-at));return end
        D.queryTab=nil
    end
    local current=A.CurrentGuildTab()
    local tab=D.toQuery[current] and current or next(D.toQuery)
    if not tab then
        -- Reconcile an overview source or a recently departed request, one per tick.
        tab=next(D.overviewChecks)
        if tab then
            local relevant=D.departed[tab] or ShowingOverview()
            D.overviewChecks[tab]=nil
            if relevant and RefreshTabSnapshot(tab,false) then B.BankView:Refresh("guild") end
            ScheduleQuery(querySpacing)
        end
        return
    end
    D.toQuery[tab]=nil
    if ReadableTab(tab) then
        D.queryTab=tab
        StartTabRead(tab)
        D.slotEvents[tab]=nil
        D.guildRequests[tab]=now
        if not A.QueryGuildPage(tab) then D.queryTab=nil end
    end
    ScheduleQuery(D.queryTab and replyWindow or querySpacing)
end
function D:UpdateGuildAccess()
    if not SameGuild() then return end
    local tabs=A.GuildTabs()
    local allowed={}
    local operation=B.Actions.queue and B.Actions.queue[B.Actions.index]
    local target=operation and operation.target
    local canContinue
    for _,info in ipairs(tabs) do
        if info.view then
            allowed[info.id]=true
            if not self.allowed[info.id] then self.toQuery[info.id]=true end
            if target and target.bag==info.id then canContinue=info.deposit end
        end
    end
    for id in pairs(self.allowed) do
        if not allowed[id] then
            if self.withdrawal and self.withdrawal.tab==id then self.withdrawal=nil end
            self.knownTabs[id],self.guildPages[id],self.guildRequests[id]=nil,nil,nil
            self.guildOrigins[id]=nil
            self.toQuery[id],self.slotEvents[id],self.purchased[id]=nil,nil,nil
            self.emptyRead[id],self.refreshingEmpty[id]=nil,nil
            self.overviewChecks[id]=nil
            self.departed[id]=nil
            if self.queryTab==id then self.queryTab=nil;CancelQueryTimer() end
            if self.cursorSource==id then self.cursorSource=nil end
            if self.selectedRequest==id then self.selectedRequest=nil end
        end
    end
    self.allowed=allowed
    if target and target.kind=="guild" and not canContinue then B.Actions:Stop() end
    local intent=self.purchaseIntent
    if intent and GetTime()>self.purchaseDeadline then
        self.purchaseIntent=nil
    elseif intent and allowed[intent] and A.GuildTabCount()==intent then
        self.purchased[intent]=true
        self.purchaseIntent=nil
    end
    ScheduleQuery(querySpacing)
end
function D:BeginGuild()
    self:ResetGuild()
    self.guildOwner=B.Cache.guildKey
    if A.GuildTabs then self:UpdateGuildAccess() end
end
-- Call just before submitting the native buy. A cancelled or failed buy grants nothing.
function D:ExpectGuildPurchase(tab)
    local count=A.GuildTabCount and A.GuildTabCount()
    if not YUI.IsForever or not SameGuild() or not count or tab~=count+1 then return false end
    self.purchaseIntent,self.purchaseDeadline=tab,GetTime()+10
    return true
end
-- Overview entry or explicit refresh. Queries never select a background tab.
function D:RequestGuildPages()
    if B.View.guildDepositDialog then B.View.guildDepositDialog:Hide() end
    if not YUI.IsForever or not SameGuild() then return false end
    local now=GetTime()
    if self.lastOverview and now-self.lastOverview<replyWindow then return false end
    self.lastOverview=now
    for tab in pairs(self.allowed) do
        if tab~=self.queryTab then self.toQuery[tab]=true end
    end
    ScheduleQuery(querySpacing)
    return true
end
function D:GetGuildPage(tab)
    if not SameGuild() then return nil,"closed" end
    if not ReadableTab(tab) then return nil,"denied" end
    if self.knownTabs[tab] and not self.guildRequests[tab] then return self.guildPages[tab],"ready" end
    return nil,self.purchased[tab] and "purchased" or "pending"
end
function D:GetGuildOverviewPage(tab)
    local page,state=self:GetGuildPage(tab)
    if state=="pending" or state=="purchased" then
        if self.knownTabs[tab] then return self.guildPages[tab],"refreshing" end
        if OverviewEmpty(tab) then return nil,"observed" end
    end
    return page,state
end
function D:SelectGuildTab(tab)
    if not ReadableTab(tab) or A.InCombat() or not A.BankWindowShown("guild")
        or A.CursorBusy() and not A.CursorItem() then return false end
    local now=GetTime()
    local current=A.CurrentGuildTab()
    local currentRequest=self.guildRequests[current]
    if tab==current and (currentRequest and now-currentRequest<replyWindow
        or self.selectedRequest==tab and self.lastSelection and now-self.lastSelection<querySpacing) then return true end
    local previousRequest,previousEvent=self.guildRequests[tab],self.slotEvents[tab]
    self.slotEvents[tab]=nil
    self.guildRequests[tab]=now
    local selected,requested=A.SelectGuildTab(tab)
    if not selected then
        self.guildRequests[tab],self.slotEvents[tab]=previousRequest,previousEvent
        return false
    end
    if tab~=current and self.withdrawal and self.withdrawal.pickup then self.withdrawal=nil end
    if tab~=current and B.View.guildDepositDialog then B.View.guildDepositDialog:Hide() end
    if A.CursorBusy() and current~=tab and not self.cursorSource then self.cursorSource=current end
    if currentRequest and current~=tab then self.departed[current]=now end
    self.selectedRequest,self.lastSelection=tab,now
    StartTabRead(tab)
    self.overviewChecks[tab]=nil
    self.departed[tab]=nil
    self.toQuery[tab]=requested==false or nil
    if self.toQuery[tab] then ScheduleQuery(querySpacing) end
    return true
end
function D:GuildPermission(tab)
    if self.guildOwner then
        local info=ReadableTab(tab)
        return info and info.deposit or false
    end
    if not B.guildOpen then return false end
    local ok,_,_,view,deposit=pcall(GetGuildBankTabInfo,tab)
    return ok and S.SafeBoolean(view)==true and S.SafeBoolean(deposit)==true
end
-- Only the tooltip for this physical slot can establish the instance binding.
local function GuildSlotBound(tab,slot,id)
    local read=C_TooltipInfo and C_TooltipInfo.GetGuildBankItem
    local bindingLine=Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemBinding
    if not read or not bindingLine then return end
    local ok,tip=pcall(read,tab,slot)
    if not ok or not S.CanAccessTable(tip) or not S.CanAccessTable(tip.lines) then return end
    if S.IsSecretValue(tip.id) or tip.id and S.SafeNumber(tip.id)~=id then return end
    local bound
    for _,line in ipairs(tip.lines) do
        if not S.CanAccessTable(line) or S.IsSecretValue(line.type) then return end
        if S.SafeNumber(line.type)==bindingLine then
            local text=S.SafeString(line.leftText)
            if not text then return end
            if text==ITEM_SOULBOUND then return true end
            if text~=ITEM_BIND_ON_EQUIP then return end
            bound=false
        end
    end
    return bound
end
function D:GuildSlot(tab,slot,readBadges)
    local ok,icon,count,locked,_,quality=pcall(GetGuildBankItemInfo,tab,slot)
    if not ok or S.IsSecretValue(icon) or S.IsSecretValue(count) or S.IsSecretValue(locked) then return nil,"restricted" end
    if icon~=nil and not (S.SafeNumber(icon) or S.SafeString(icon)) or count~=nil and not S.SafeNumber(count) then return nil,"restricted" end
    icon,count=S.SafeNumber(icon) or S.SafeString(icon),S.SafeNumber(count)
    if not icon and (count and count~=0 or S.SafeBoolean(locked)==true) then return nil,"restricted" end
    if not icon then return nil end
    local linkOK,rawLink=pcall(GetGuildBankItemLink,tab,slot)
    local link=linkOK and S.SafeString(rawLink)
    local id=link and tonumber(link:match("item:(%d+)"))
    if not id or not count or count<1 then return nil,"restricted" end
    local raw=YUI.API.Item.GetInfo(link)
    local classID=raw and S.SafeNumber(raw.classID)
    local bindType=raw and S.SafeNumber(raw.bindType)
    local bound,level
    if readBadges then
        if classID==2 or classID==4 then level=B.GuildInventory:LinkLevel(link,raw) end
        if bindType==(Enum and Enum.ItemBind and Enum.ItemBind.OnEquip or 2) then bound=GuildSlotBound(tab,slot,id) end
    elseif readBadges==false then
        -- A lock-only refresh may replace the display record. Preserve its
        -- last observed badges only for the unchanged physical stack.
        local page=self.guildPages[tab]
        local old=page and page.slots[slot]
        if old and old.link==link and old.count==count and old.bindType==bindType then
            bound,level=old.bound,old.level
        end
    end
    return {bag=tab,slot=slot,key="guild:"..tab..":"..slot,itemID=id,link=link,count=count,
        locked=S.SafeBoolean(locked)~=false,quality=S.SafeNumber(quality) or raw and S.SafeNumber(raw.quality),name=raw and raw.name or "",
        icon=icon,maxStack=raw and raw.stackCount or 1,classID=classID,bindType=bindType,bound=bound,level=level,
        isCraftingReagent=raw and S.SafeBoolean(raw.isCraftingReagent),
        subClassID=raw and raw.subclassID,equipLoc=raw and raw.equipLoc,subType=raw and raw.subType,price=raw and raw.sellPrice}
end
-- A missing icon can precede the link update. Require both reads to agree before acting on an empty slot.
function D:ReadGuildActionSlot(tab,slot)
    local item,err=self:GuildSlot(tab,slot)
    if item or err then return item,err end
    local ok,link=pcall(GetGuildBankItemLink,tab,slot)
    if not ok or S.IsSecretValue(link) or link~=nil then return nil,"restricted" end
    return nil
end
-- Only the concrete user-selected empty slot can use this path, never an inferred destination.
function D:CanDropGuildSlot(tab,slot)
    slot=S.SafeNumber(slot)
    if not YUI.IsForever or not self.guildOwner or not slot or slot<1 or slot>98 or slot~=math.floor(slot) or A.InCombat()
        or A.CurrentGuildTab()~=tab or not A.BankWindowShown("guild") or not self:GuildPermission(tab)
        or B.Actions.queue or B.Actions.nativeSort or not A.CursorItem() or type(PickupGuildBankItem)~="function"
        or type(GetGuildBankItemLink)~="function" then return false end
    if (not self.knownTabs[tab] or self.guildRequests[tab]) and not self.purchased[tab] then
        if not self.emptyRead[tab] then return false end
        local cache=B.Cache:GetContainer(self.guildOwner,"guild")
        local last=cache and cache.bags[tostring(tab)]
        if last and last.slots[slot] then return false end
    end
    local current,err=self:ReadGuildActionSlot(tab,slot)
    return not current and not err
end
function D:DropGuildSlot(tab,slot)
    if not self:CanDropGuildSlot(tab,slot) then return false end
    return A.GuildItemAction(tab,slot,false)
end
local function GuildQuotaMatches(operation)
    local quota=operation.guildQuota
    if not quota then return true end
    local tab=A.GuildTab(operation.target.bag)
    return tab and tab.view and tab.deposit and tab.limit==quota.limit and tab.remaining==quota.remaining
end
local function ChoiceVisible(session,tab)
    local w=B.View.windows["live-guild"]
    return B.active and B.guildOpen and SameGuild() and w and w.open and w.cachedGuildPages==session
        and w.guildMode=="items" and w.page==tab and A.CurrentGuildTab()==tab and not A.InCombat()
        and A.BankWindowShown("guild") and A.Context()=="bank" and D:GuildPermission(tab)
end
function D:ReadTarget(target)
    if target.kind=="guild" then
        -- Wait for the page snapshot to catch up before confirming this step
        -- and starting the next one (a bag update can precede the guild update).
        if target.choiceSession and (not ChoiceVisible(target.choiceSession,target.bag)
            or not self:Available("guild",true)) then return nil,"restricted" end
        if not self.knownTabs[target.bag] or self.guildRequests[target.bag] or not self:GuildPermission(target.bag)
            or S.SafeNumber(GetCurrentGuildBankTab())~=target.bag then return nil,"restricted" end
        return self:ReadGuildActionSlot(target.bag,target.slot)
    end
    return A.Slot(target.bag,target.slot)
end
-- A submitted write has a specific non-empty postcondition. Reading that exact
-- cell does not grant permission to write into any other (possibly unknown) cell.
local function WithdrawAllowance(tab)
    local window=B.View.windows["live-guild"]
    if not YUI.IsForever or not B.active or A.InCombat() or not window or not window.open
        or window.guildMode~="items" or not tab or window.page~=tab or A.CurrentGuildTab()~=tab
        or not A.BankWindowShown("guild") or A.Context()~="bank" then return end
    local info=ReadableTab(tab)
    if not info then return end
    local limit,remaining=info.limit,info.remaining
    if limit==-1 and remaining==-1 then return math.huge end
    if limit and limit>0 and limit==math.floor(limit) and remaining and remaining>=0
        and remaining<=limit and remaining==math.floor(remaining) then return remaining end
end

function D:CanGuildWithdrawPreset(page)
    return not B.Actions.queue and not B.Actions.nativeSort and not self.bagDeposit
        and not (self.withdrawal and (self.withdrawal.held or GetTime()<=self.withdrawal.deadline))
        and not A.CursorBusy() and (WithdrawAllowance(page) or 0)>0
        and self.knownTabs[page]==true and not self.guildRequests[page] and self.guildPages[page]~=nil
end

function D:GuildReceiptAllowed(op)
    if op.guildWithdraw then
        return self.knownTabs==op.guildWithdraw and self.guildOwner==op.guildOwner
            and not self.guildRequests[op.source.bag] and WithdrawAllowance(op.source.bag)~=nil
    end
    local target=op.target
    return B.active and not A.InCombat() and SameGuild() and self.guildOwner==op.guildOwner
        and A.BankWindowShown("guild") and A.CurrentGuildTab()==target.bag and self:GuildPermission(target.bag)
        and GuildQuotaMatches(op) and (not target.choiceSession or ChoiceVisible(target.choiceSession,target.bag))
end
function D:ReadGuildReceipt(op)
    if not self:GuildReceiptAllowed(op) then return nil,"session" end
    return self:GuildSlot(op.target.bag,op.target.slot)
end
function D:GuildSourceSlotExists(bag,slot)
    if C_Container and C_Container.GetContainerNumSlots then
        local ok,count=pcall(C_Container.GetContainerNumSlots,bag)
        local capacity=ok and S.SafeNumber(count)
        return capacity and slot>=1 and slot<=capacity
    end
    local slots,capacity=A.ReadBag(bag)
    return slots and type(capacity)=="number" and slot>=1 and slot<=capacity and not slots[slot]
end
function D:RefreshGuildReceipt(op,item)
    local tab,slot=op.target.bag,op.target.slot
    local page=self.guildPages[tab]
    local old=page and page.slots[slot]
    if not old or old.link~=item.link or old.count~=item.count or old.locked
        or not self:Available("guild",true) then
        self:SnapshotGuild(false,tab)
        B.BankView:Refresh("guild")
    end
end
function D:PickupTarget(target,source)
    if target.kind=="guild" then
        if not self:Available("guild",true) or S.SafeNumber(GetCurrentGuildBankTab())~=target.bag then return false end
        -- PickupGuildBankItem also withdraws or swaps. Inspect the cursor and
        -- destination again after picking up the source and before calling it.
        local cursor=A.CursorItem()
        if not cursor then return false end
        local current,err=self:ReadTarget(target)
        if err then return false end
        local operation=B.Actions.queue and B.Actions.queue[B.Actions.index]
        if target.choiceSession and (not operation or not self:SameGuildLink(cursor.link,operation.link)) then return false end
        if operation and (operation.target~=target or operation.itemID~=cursor.itemID or not GuildQuotaMatches(operation)
            or cursor.link and not self:SameGuildLink(cursor.link,operation.link)
            or operation.targetCount~=(current and current.count or 0)) then return false end
        local link=cursor.link or operation and operation.link
        if current then
            if source and not self:SameGuildLink(source.link,current.link) and not self:SameGuildLink(source.link,cursor.link) then return false end
            if current.locked or not self:GuildStackMatches(source or {itemID=cursor.itemID,link=link},current) then return false end
            local limit=operation and operation.guildStackLimit or current.maxStack or 1
            local amount=operation and (operation.count or operation.sourceCount) or 1
            if current.count+amount>limit then return false end
        end
        if type(PickupGuildBankItem)~="function" then return false,false end
        -- 'submitted' means the write was attempted. Even a Lua error after
        -- native dispatch cannot prove the server did not receive the click.
        local ok=pcall(PickupGuildBankItem,target.bag,target.slot)
        return ok,true,operation and self:SameGuildLink(cursor.link,operation.link)
    end
    return A.Pickup(target.bag,target.slot)
end
function D:Available(kind,checkContents)
    if A.InCombat() or A.Context()~="bank" then return false end
    if kind=="guild" then
        local tab=GetCurrentGuildBankTab and S.SafeNumber(GetCurrentGuildBankTab())
        if not tab or not self.knownTabs[tab] or self.guildRequests[tab] or not self:GuildPermission(tab) then return false end
        if checkContents and self.guildOwner then
            -- An all-nil native page can also mean unloading. Check a known occupied slot
            -- before allowing the automatic planner to interpret any nil as free space.
            local page=self.guildPages[tab]
            if page then
                for slot,old in pairs(page.slots) do
                    local current=self:GuildSlot(tab,slot)
                    if current and current.link==old.link then return true end
                end
            end
            return false
        end
        return true
    end
    return B.bankOpen and #A.BankBags(kind)>0 or false
end
local function SlotKey(bag,slot)
    return tostring(bag)..":"..slot
end

local function PersonalBankBlocked()
    if not YUI.IsForever or not B.active or not B.bankOpen then return "bank.transfer_unavailable" end
    if A.InCombat() then return "bank.transfer_busy" end
    local kind=A.ActiveBankKind()
    if not kind then return "bank.transfer_loading" end
    if kind~="bank" or not A.CanUsePersonalBank() then return "bank.transfer_unavailable" end
end
local function PersonalBankOpen()
    return not PersonalBankBlocked()
end

local function LiveBag(id,kind)
    local runtime=B.Runtime
    if runtime.kind[id]==kind and runtime.readable[id] then return B.Model.bags[id] end
end

local function TransferBag(position,kind)
    local ids=kind=="bank" and A.BankBags("bank") or A.GetCarryBags(false)
    for _,id in ipairs(ids) do
        if id==position.bag then
            local bag=LiveBag(id,kind)
            if bag and position.slot>=1 and position.slot<=bag.capacity then return bag end
        end
    end
end

-- 随身工具在无限服被归为制造材料（wowf 1.60.1.71037 Item/ItemSparse）。
local materialTools={
    [4471]=true, [10498]=true, [260811]=true, -- 燧石和火绒、侏儒微调器、侏儒军刀
    [6218]=true, [6339]=true, [11130]=true, [11145]=true, [16207]=true, -- 附魔棒
}
local function KeepOnBatchDeposit(item)
    return YUI.IsForever and B.Classification.IsCampingItem(item)
end

local presets={
    materials=function(item)
        local class=item.classID
        if class~=5 and class~=7 and class~=19 then return false end
        if materialTools[item.itemID] or B.Classification:IsClassSpellReagent(item.itemID) then return false end
        -- The generic reagent class also contains class spell reagents.
        if class==5 then return item.subClassID==0 and item.isCraftingReagent==true end
        return not item.equipLoc or item.equipLoc=="" or item.equipLoc=="INVTYPE_NON_EQUIP_IGNORE"
    end,
    recipes=function(item) return item.classID==9 end,
    consumables=function(item)
        return (item.classID==0 and item.subClassID~=nil or item.classID==3 or item.classID==8)
            and not B.Classification.IsMageScroll(item) and not B.Classification.IsConjured(item)
    end,
    boe=function(item) return B.Classification:IsUnboundEquipment(item) end,
    scrolls=B.Classification.IsMageScroll,
}

local function SameTransferStack(a,b)
    return a.bound==b.bound and B.Classification:SameStack(a,b)
end

local function StillMatchesPreset(preset,source)
    if not preset then return true end
    return presets[preset](source)
        and (preset~="boe" or not A.ReadGearState or A.ReadGearState(source.bag,source.slot,nil,true)~=true)
end

function D:IsGuildPreset(key)
    return presets[key]~=nil
end

local function ValidateTransfer(operation,destination)
    if not PersonalBankOpen() then return false end
    local target=operation.target
    local depositing=target.kind=="bank"
    local bag=TransferBag(target,target.kind)
    if not bag or not TransferBag(operation.source,depositing and "bags" or "bank")
        or B:GetConfig().locks[SlotKey(target.bag,target.slot)] then return false end
    local source=A.Slot(operation.source.bag,operation.source.slot)
    if not source or source.itemID~=operation.itemID or source.link~=operation.link or source.count~=operation.sourceCount
        or source.bound~=operation.bound or operation.guid and source.guid~=operation.guid
        or B.Actions:Protected(source) or not A.Fits(source,bag,true)
        or depositing and not A.CanDeposit(source,"bank") then return false end
    if not StillMatchesPreset(operation.preset,source) then return false end
    local quantity=operation.count or source.count
    if operation.targetCount==0 then return destination==nil and quantity<=(source.maxStack or 1) end
    return destination and destination.count==operation.targetCount and not B.Actions:Protected(destination)
        and SameTransferStack(source,destination) and destination.count+quantity<=(destination.maxStack or 1)
end

function D:Validate(operation,destination)
    if operation.personalTransfer then return ValidateTransfer(operation,destination) end
    local kind=operation.target.kind
    if operation.target.choiceSession and not ChoiceVisible(operation.target.choiceSession,operation.target.bag) then return false end
    if not self:Available(kind,true) then return false end
    local source=A.Slot(operation.source.bag,operation.source.slot)
    if not A.CanDeposit(source,kind) then return false end
    if kind=="guild" then
        if S.SafeNumber(GetCurrentGuildBankTab())~=operation.target.bag or operation.guildOwner~=self.guildOwner
            or operation.guid and source.guid~=operation.guid or operation.quality~=source.quality
            or operation.bound~=source.bound or operation.charges~=source.charges then return false end
        operation.guildStackLimit=source.maxStack or 1
        if (destination and destination.count or 0)+(operation.count or source.count)>operation.guildStackLimit then return false end
        if not GuildQuotaMatches(operation) or not StillMatchesPreset(operation.preset,source) then return false end
        return operation.targetCount==0 and destination==nil or destination and destination.count==operation.targetCount
            and self:GuildStackMatches(source,destination)
    else
        local found=false
        for _,id in ipairs(A.BankBags(kind)) do if id==operation.target.bag and B.Runtime.readable[id] then found=true end end
        if not found or not A.Fits(source,B.Model.bags[operation.target.bag],true) then return false end
    end
    if operation.targetCount==0 then return destination==nil end
    return destination and destination.itemID==operation.itemID and destination.count==operation.targetCount
        and destination.link==operation.link
end

local function AddTargets(targets,kind,bag,existing)
    for slot=1,bag.capacity do
        local item=bag.slots[slot]
        targets[#targets+1]={bag=bag.id,slot=slot,kind=kind,item=item and B:Copy(item),container=bag}
        if existing and item then existing[item.itemID]=true end
    end
end

local function PlanMove(steps,target,item,sourceCount,moved,personalTransfer,preset)
    local dest=target.item
    local targetCount=dest and dest.count or 0
    local op={source={bag=item.bag,slot=item.slot},target={bag=target.bag,slot=target.slot,kind=target.kind},
        itemID=item.itemID,link=item.link,sourceCount=sourceCount,targetCount=targetCount,
        count=moved<sourceCount and moved or nil}
    if personalTransfer then
        op.personalTransfer,op.preset,op.bound,op.guid=true,preset,item.bound,item.guid
        op.equipmentMove=not dest and sourceCount==1 and moved==1 and item.maxStack==1
            and (item.classID==2 or item.classID==4) and item.equipLoc and item.equipLoc~=""
    elseif target.kind=="guild" then
        op.guildOwner,op.preset,op.guid=D.guildOwner,preset,item.guid
        op.name,op.icon,op.quality=item.name,item.icon,item.quality
        op.bound,op.charges=item.bound,item.charges
    end
    steps[#steps+1]=op
    if not dest then
        dest=B:Copy(item)
        dest.bag,dest.slot,dest.key=target.bag,target.slot,SlotKey(target.bag,target.slot)
        target.item=dest
    end
    dest.count=targetCount+moved
    if target.kind=="guild" then dest.link=item.link end
end

function D.PresetSources(steps)
    local sources,total,slots={},0,0
    for _,step in ipairs(steps) do
        local bag,slot=step.source.bag,step.source.slot
        local bySlot=sources[bag]
        if not bySlot then bySlot={};sources[bag]=bySlot end
        if not bySlot[slot] then
            bySlot[slot]=step
            slots=slots+1
        end
        total=total+(step.count or step.sourceCount)
    end
    return total,slots,sources
end

local function WithdrawStackMatches(item,carried)
    if B.Classification:SameStack(item,carried) then return true end
    return item.link~=carried.link and not carried.bound and item.quality==carried.quality
        and item.classID==carried.classID and item.maxStack==carried.maxStack and item.charges==carried.charges
        and D:GuildStackMatches(carried,item,true)
end

local function PlanItem(steps,targets,item,quantity,personalTransfer,preset,guildWithdraw)
    local remaining,sourceCount=quantity,item.count
    local locks=B:GetConfig().locks
    for pass=1,2 do
        for _,target in ipairs(targets) do
            if remaining==0 then return 0 end
            local dest=target.item
            local merge=pass==1 and dest and dest.itemID==item.itemID and not dest.locked
                and (dest.link==item.link or guildWithdraw)
                and (not personalTransfer or SameTransferStack(item,dest) and not B.Actions:Protected(dest))
                and (not guildWithdraw or WithdrawStackMatches(item,dest) and not B.Actions:Protected(dest))
            if (merge or pass==2 and not dest) and A.Fits(item,target.container) and not locks[SlotKey(target.bag,target.slot)] then
                local capacity=(item.maxStack or 1)-(dest and dest.count or 0)
                local moved=math.min(remaining,math.max(0,capacity))
                if moved>0 then
                    PlanMove(steps,target,item,sourceCount,moved,personalTransfer,preset)
                    sourceCount,remaining=sourceCount-moved,remaining-moved
                end
            end
        end
    end
    return remaining
end

local function BestGuildStack(targets,item,quantity,limit)
    local choice,room=nil,0
    for _,target in ipairs(targets) do
        local available=limit-target.item.count
        if available>0 and D:GuildStackMatches(item,target.item) then
            local better
            if available==room then better=target.slot<choice.slot
            elseif available>=quantity then better=room<quantity or available<room
            else better=room<quantity and available>room end
            if better then choice,room=target,available end
        end
    end
    return choice,room
end

-- A new guild slot is shared capacity; a half-stack is useful only to a
-- compatible variant. Reserve blanks across the whole batch before moving
-- the first source, including quantities left after the per-item keep rule.
local function PlanGuildItems(steps,targets,sources,preset)
    if #sources==0 then return 0,0 end
    local groups,byPayload,byID,empty={},{},{},{}
    for _,source in ipairs(sources) do
        local item=source.item
        local limit=item.maxStack or 1
        local key=(ItemPayload(item.link) or item.link).."\031"..limit
        local group=byPayload[key]
        if not group then
            group={item=item,limit=limit,targets={},need=0,reserved=0}
            groups[#groups+1]=group
            byPayload[key]=group
            local variants=byID[item.itemID] or {}
            variants[#variants+1]=group
            byID[item.itemID]=variants
        end
        source.group=group
        group.need=group.need+source.quantity
    end
    local function Assign(group,target)
        group.targets[#group.targets+1]=target
        group.need=group.need-(group.limit-target.item.count)
    end
    -- Count forced matches first. A guild link with omitted context can
    -- match multiple variants, but its available capacity counts only once.
    local ambiguous={}
    for _,target in ipairs(targets) do
        local dest=target.item
        if not dest then empty[#empty+1]=target
        elseif not dest.locked and byID[dest.itemID] then
            local match,multiple
            for _,group in ipairs(byID[dest.itemID]) do
                if dest.count<group.limit and D:GuildStackMatches(group.item,dest) then
                    if match then multiple=true;break end
                    match=group
                end
            end
            if multiple then ambiguous[#ambiguous+1]=target
            elseif match then Assign(match,target) end
        end
    end
    for _,target in ipairs(ambiguous) do
        local best,gain=nil,0
        for _,group in ipairs(byID[target.item.itemID]) do
            local room=group.limit-target.item.count
            local usable=math.max(0,math.min(group.need,room))
            if room>0 and (not best or usable>gain or usable==gain and group.need<best.need)
                and D:GuildStackMatches(group.item,target.item) then
                best,gain=group,usable
            end
        end
        if best then Assign(best,target) end
    end
    local spare=#empty
    -- Each successive blank for a variant contributes at most one stack,
    -- then its final remainder. Take the largest marginal gain each time.
    while spare>0 do
        local best,gain=nil,0
        for _,group in ipairs(groups) do
            local usable=math.min(group.need,group.limit)
            if usable>gain then best,gain=group,usable end
        end
        if not best then break end
        best.reserved=best.reserved+1
        best.need=best.need-gain
        spare=spare-1
    end

    local nextEmpty,total,skipped=1,0,0
    for _,source in ipairs(sources) do
        local item,group=source.item,source.group
        local left,sourceCount=source.quantity,item.count
        while left>0 do
            local choice,room=BestGuildStack(group.targets,item,left,group.limit)
            if group.limit>0 and room<left and (group.reserved>0 or spare>0) then
                choice,room=empty[nextEmpty],group.limit
                nextEmpty=nextEmpty+1
                if group.reserved>0 then group.reserved=group.reserved-1 else spare=spare-1 end
                group.targets[#group.targets+1]=choice
            end
            if not choice then break end
            local moved=math.min(left,room)
            PlanMove(steps,choice,item,sourceCount,moved,false,preset)
            left,sourceCount=left-moved,sourceCount-moved
        end
        total=total+source.quantity-left
        skipped=skipped+left
    end
    return total,skipped
end

-- Build display rows only when a confirmation is painted. Keep fallback
-- artwork and names out of the transaction's source and target identity.
local function ValidIcon(value)
    local id=S.SafeNumber(value)
    if id and id>0 then return id end
    local path=S.SafeString(value)
    if path and path~="" then return path end
end

function D.GuildDepositLines(steps)
    local lines,byVariant={},{}
    for _,step in ipairs(steps) do
        local link=S.SafeString(step.link)
        if link=="" then link=nil end
        -- Without a link, combine only portions of the same physical stack.
        local source=step.source
        local identity=link or source and ("slot:"..source.bag..":"..source.slot)
        local key=identity and table.concat({step.itemID,identity,tostring(step.bound),tostring(step.charges),
            tostring(step.quality)},"\031")
        local line=key and byVariant[key]
        if not line then
            line={itemID=step.itemID,link=link,quality=S.SafeNumber(step.quality),quantity=0,
                label=link and link:match("|Hitem:[^|]+|h%[(.-)%]|h")}
            if line.quality and line.quality<0 then line.quality=nil end
            lines[#lines+1]=line
            if key then byVariant[key]=line end
        end
        line.icon=line.icon or ValidIcon(step.icon)
        if not line.label or line.label=="" then line.label=S.SafeString(step.name) end
        line.quantity=line.quantity+(step.count or step.sourceCount)
    end
    for _,line in ipairs(lines) do
        if not line.icon or not line.quality or not line.label or line.label=="" then
            local ref=line.link or line.itemID
            local info=YUI.API.Item.GetInfo(ref)
            if info then
                line.icon=line.icon or ValidIcon(info.texture)
                local quality=S.SafeNumber(info.quality)
                if not line.quality and quality and quality>=0 then line.quality=quality end
                if not line.label or line.label=="" then line.label=S.SafeString(info.name) end
            end
            if not line.icon and YUI.API.Item.GetIcon then line.icon=ValidIcon(YUI.API.Item.GetIcon(ref)) end
        end
        line.icon=line.icon or 134400
        if not line.label or line.label=="" then line.label=tostring(line.itemID) end
        line.label=line.label:gsub("|","||")
    end
    return lines
end

-- Only an exact physical stack can survive the time between opening the menu
-- and committing its choice. Never search other slots for a replacement.
function D:BagDepositSource(item)
    if not item or type(item.guid)~="string" or item.guid=="" or not item.link or item.link==""
        or not item.bag or not item.slot or not item.count or item.count<1 or item.members or item.held or item.empty then
        return nil,"guild.bag_unverified"
    end
    local source=A.Slot(item.bag,item.slot)
    if not source or source.guid~=item.guid or source.itemID~=item.itemID or source.link~=item.link
        or source.count~=item.count then return nil,"error.changed" end
    if B.Actions:Protected(source) or not A.CanDeposit(source,"guild") then return nil,"guild.bag_ineligible" end
    return source
end
function D:CancelBagDeposit(reason)
    local pending=self.bagDeposit
    if not pending then return end
    self.bagDeposit=nil
    if pending.timer then
        pending.timer:Cancel()
        B.Stats.timers=B.Stats.timers-1
    end
    B.View:RefreshGuildBagRoute()
    if reason then B:Notify(reason) end
end
function D:CheckBagDeposit()
    local p=self.bagDeposit
    if not p then return end
    if not ChoiceVisible(p.session,p.tab) then self:CancelBagDeposit("guild.bag_cancelled")
    elseif A.CursorBusy() or B.Actions.queue or B.Actions.nativeSort then self:CancelBagDeposit("bank.transfer_busy") end
end
function D:TryBagDeposit()
    self:CheckBagDeposit()
    local p=self.bagDeposit
    if not p then return end
    local source,reason=self:BagDepositSource(p.source)
    if not source then self:CancelBagDeposit(reason);return end
    local bag=self:GetGuildPage(p.tab)
    if not bag and (self.emptyRead[p.tab] or self.purchased[p.tab]) then
        self:CancelBagDeposit("guild.bag_manual");return
    end
    if not bag or not self:Available("guild",true) then return end
    self:CancelBagDeposit()
    local targets,steps={},{}
    AddTargets(targets,"guild",bag)
    local moved=PlanGuildItems(steps,targets,{{item=source,quantity=source.count}})
    if moved~=source.count then B:Notify("guild.bag_no_room");return end
    for _,step in ipairs(steps) do
        step.target.choiceSession=p.session
    end
    if not B.Actions:Start(steps,"deposit",source.count) and not A.CursorBusy() then B:Notify("guild.bag_cancelled") end
end
function D:StartBagDeposit(source,session,tab)
    self:CancelBagDeposit()
    local p={source=source,session=session,tab=tab}
    self.bagDeposit=p
    self:TryBagDeposit()
    if self.bagDeposit~=p then return end
    B.View:RefreshGuildBagRoute()
    B:Notify("guild.bag_waiting")
    local deadline=GetTime()+replyWindow+querySpacing
    local function CheckPage()
        if self.bagDeposit~=p then return end
        self:TryBagDeposit()
        if self.bagDeposit~=p then return end
        local remaining=deadline-GetTime()
        if remaining<=0 then self:CancelBagDeposit("guild.bag_timeout");return end
        if not p.queried and A.QueryGuildPage then
            p.queried=true
            A.QueryGuildPage(tab)
        end
        if self.bagDeposit==p then p.timer=C_Timer.NewTimer(remaining,CheckPage) end
    end
    p.timer=C_Timer.NewTimer(querySpacing,CheckPage)
    B.Stats.timers=B.Stats.timers+1
end

local function GuildDepositSources(ids)
    local items={}
    for _,bag in ipairs(ids) do
        local slots,capacity=A.ReadBag(bag,true)
        if not slots then return end
        for slot=1,capacity do
            local item=slots[slot]
            if item then items[#items+1]=item end
        end
    end
    return items
end

function D:Plan(kind,rule,query,page,preset,readLiveSources)
    local matchPreset=preset and presets[preset]
    if preset and (not matchPreset or kind~="guild" or not page or query) then
        if kind=="guild" then return {},0,nil,0 end
        return {},0
    end
    if not self:Available(kind,true) then
        if kind=="guild" then return {} end
        return {},0
    end
    local targets,existing={},{}
    if kind=="guild" then
        local tab=S.SafeNumber(GetCurrentGuildBankTab());local slots={}
        if page and page~=tab then return {} end
        for slot=1,98 do local item,err=self:GuildSlot(tab,slot);if err then return {} end;slots[slot]=item end
        AddTargets(targets,kind,{id=tab,capacity=98,slots=slots},existing)
    else
        for _,id in ipairs(A.BankBags(kind)) do
            local bag=B.Model.bags[id]
            if bag and B.Runtime.readable[id] and (not page or page==id) then
                AddTargets(targets,kind,bag,existing)
            end
        end
    end
    local steps,retained,total,skipped={},{},0,0
    local guildSources=kind=="guild" and {} or nil
    local ids=A.GetCarryBags(false)
    local items
    if kind=="guild" and (readLiveSources or preset) then items=GuildDepositSources(ids)
    else items=B.Model:List(ids) end
    if not items then return {} end
    -- Only the five preset buttons bypass keep/contains. The search action
    -- still applies both settings after matching the player's query.
    local useRule=not preset
    local keepPerItem=useRule and rule.keep or 0
    for _,item in ipairs(items) do
        local protected=KeepOnBatchDeposit(item) or B.Actions:Protected(item)
        local excluded=rule.exclude and rule.exclude~="" and (item.name or ""):find(rule.exclude,1,true)
        if kind=="guild" and (readLiveSources or preset) and not protected and not excluded
            and (not item.loaded or item.classID==nil or not item.link or item.link=="" or not item.maxStack
                or item.classID==0 and item.subClassID==nil
                or preset=="boe" and (item.classID==2 or item.classID==4) and item.bound==nil)
            and A.CanDeposit(item,kind)~=false then return {} end
        local matches
        if matchPreset then matches=matchPreset(item)
        elseif query then matches=query~="" and B.Classification:Matches(item,query)
        else
            matches=rule.mode=="materials" and (item.classID==5 or item.classID==7 or item.classID==19)
                or rule.mode=="existing" and existing[item.itemID] or rule.mode=="custom" and (not rule.classID or item.classID==rule.classID)
        end
        if matches and (kind~="guild" or item.link and item.link~="")
            and not protected and not excluded
            and (not useRule or not rule.contains or rule.contains=="" or (item.name or ""):find(rule.contains,1,true)) then
            local canDeposit=A.CanDeposit(item,kind)
            if kind=="guild" and canDeposit==nil then return {} end
            if canDeposit and (preset~="boe" or StillMatchesPreset(preset,item)) then
                local keep=math.min(item.count,math.max(0,keepPerItem-(retained[item.itemID] or 0)))
                retained[item.itemID]=(retained[item.itemID] or 0)+keep
                local quantity=item.count-keep
                if guildSources then
                    if quantity>0 then guildSources[#guildSources+1]={item=item,quantity=quantity} end
                else
                    local remaining=PlanItem(steps,targets,item,quantity,false,preset)
                    total=total+quantity-remaining
                    skipped=skipped+remaining
                end
            else skipped=skipped+item.count end
        elseif matches then skipped=skipped+item.count
        end
    end
    if guildSources then
        local moved,noRoom=PlanGuildItems(steps,targets,guildSources,preset)
        -- Only quantities admitted after protection, filters and retention reach the planner.
        return steps,moved,skipped+noRoom,moved+noRoom
    end
    return steps,total,skipped
end

local function PersonalTransferBlocked()
    local reason=PersonalBankBlocked()
    if reason then return reason end
    if A.BankPurchasePending() then return "bank.transfer_purchase_pending" end
    local actions=B.Actions
    if actions.queue or actions.nativeSort or B.Runtime.finalCarryBatch and B.Runtime.finalCarryBatch.kind=="bank"
        or actions.externalCarrySort and actions.externalCarrySort.bank
        or A.CursorBusy() or actions:CheckBankSortRecovery() then return "bank.transfer_busy" end
end
function D:CanTransfer()
    return not PersonalTransferBlocked()
end

local function LiveIDs(ids,kind)
    local result,seen,ready={},{},#ids>0
    for _,id in ipairs(ids) do
        if not seen[id] then
            seen[id]=true
            if LiveBag(id,kind) then result[#result+1]=id
            elseif kind~="bank" or A.BankBagInstalled(id)~=false then ready=false end
        end
    end
    return result,ready
end

local function TransferBags()
    local carry,carryReady=LiveIDs(A.GetCarryBags(false),"bags")
    local bank,bankReady=LiveIDs(A.BankBags("bank"),"bank")
    return carry,bank,carryReady and bankReady and not B.Stats.pendingRefresh
end

local function ReadyTransferBags()
    local reason=PersonalTransferBlocked()
    if reason then B:Notify(reason);return end
    local carry,bank,ready=TransferBags()
    if not ready then
        -- The banker can expose purchased tabs after BANKFRAME_OPENED, or a pending
        -- bag update can have left a stale lock or stack in the model.
        B:ReadAll(false)
        reason=PersonalTransferBlocked()
        if reason then B:Notify(reason);return end
        carry,bank=TransferBags()
    end
    if #carry>0 and #bank>0 then return carry,bank end
    B:Notify("bank.transfer_loading")
end

local function TransferQuantity(item,targetKind,quantityFor)
    if item.empty or item.held or not item.link or B.Actions:Protected(item)
        or targetKind=="bank" and KeepOnBatchDeposit(item) then return end
    local quantity=quantityFor(item)
    if quantity and quantity>0 and (targetKind~="bank" or A.CanDeposit(item,"bank")) then return quantity end
end

function D:NotifyTransferResult(key,confirmed,total)
    local message=B:T(key)
    if YUI.Print and type(message)=="string" then
        YUI:Print(string.format(message,confirmed,total,total-confirmed))
    end
end

local function PlanTransfer(items,targetKind,targetIDs,quantityFor,preset)
    local targets,steps,seen={},{},{}
    for _,id in ipairs(targetIDs) do
        local bag=B.Model.bags[id]
        AddTargets(targets,targetKind,bag)
    end
    local total=0
    for _,item in ipairs(items) do
        local quantity=TransferQuantity(item,targetKind,quantityFor)
        if quantity then
            local key=SlotKey(item.bag,item.slot)
            if not seen[key] then
                seen[key]=true
                total=total+quantity
                PlanItem(steps,targets,item,quantity,true,preset)
            end
        end
    end
    return steps,total
end

local function StartTransfer(steps,total)
    if total==0 then B:Notify("bank.transfer_empty");return false end
    if #steps==0 then D:NotifyTransferResult("bank.transfer_space",0,total);return false end
    return B.Actions:Start(steps,"deposit",total)
end

local function PresetQuantity(key)
    local match=presets[key]
    if match then return function(item) if match(item) then return item.count end end end
end

local function CarryTargets()
    local targets,ordinary={},{}
    for _,id in ipairs(A.GetCarryBags(false)) do
        local slots,capacity,family,space=A.ReadBag(id,false,"bags")
        if not slots then return end
        local bag={id=id,kind="bags",slots=slots,capacity=capacity,family=family,space=space}
        AddTargets((family~=0 or space=="reagent") and targets or ordinary,"bags",bag)
    end
    for _,position in ipairs(ordinary) do targets[#targets+1]=position end
    return targets
end

local function WithdrawSource(page,slot,key)
    local item,err=D:GuildSlot(page,slot,key=="boe")
    if not item or err or B.Actions:Protected(item) then return nil,err end
    if not item.classID then return nil,"pending" end
    if not presets[key](item) then return end
    local family=C_Item and C_Item.GetItemFamily or GetItemFamily
    if family then
        local ok,value=pcall(family,item.link)
        item.family=ok and S.SafeNumber(value) or 0
    end
    return item
end

-- Native auto-store can spread one withdrawal across several carried slots.
-- Use explicit placement when only part fits, or auto-store could use a protected slot.
local function WithdrawSpace(item,targets)
    local locks=B:GetConfig().locks
    local allowed,room,best,bestRoom=true,0,nil,0
    for _,target in ipairs(targets) do
        local dest=target.item
        if (not dest or dest.itemID==item.itemID and dest.count<item.maxStack) and A.Fits(item,target.container) then
            if locks[SlotKey(target.bag,target.slot)] or dest and B.Actions:Protected(dest) then
                allowed=false
            elseif not dest or WithdrawStackMatches(item,dest) then
                local space=math.min(item.count,item.maxStack-(dest and dest.count or 0))
                room=room+space
                if space>bestRoom or space==bestRoom and dest and best and not best.item then
                    best,bestRoom=target,space
                end
            end
        end
    end
    if allowed and room>=item.count then return item.count,nil end
    return bestRoom,best
end

-- ItemCount alone cannot distinguish two variants of the same item ID.
-- Require the matching quantity in readable carried slots as well.
local function CarriedVariantCount(item,targets)
    local total=0
    for _,position in ipairs(targets) do
        local carried=position.item
        if carried and carried.itemID==item.itemID and (D:SameGuildLink(item.link,carried.link)
            or D:GuildStackMatches(carried,item,true)) then
            total=total+carried.count
        end
    end
    return total
end

function D:PlanGuildWithdrawPreset(page,key)
    if not presets[key] or not self:CanGuildWithdrawPreset(page) then return end
    local targets=CarryTargets()
    if not targets then return end
    local sources,steps,total={},{},0
    local quota=WithdrawAllowance(page)
    if not quota then return end
    local snapshot=D.guildPages[page]
    for slot=1,98 do
        local old=snapshot.slots[slot]
        if old then
            local item,err=WithdrawSource(page,slot,key)
            if err then return end
            if item and item.link==old.link and item.count==old.count then sources[#sources+1]=item end
        end
    end
    local function LargerStack(a,b)
        if a.count~=b.count then return a.count>b.count end
        return a.slot<b.slot
    end
    table.sort(sources,LargerStack)
    -- With unrestricted bag space, one withdrawal takes one whole source stack.
    -- Capture that quota-limited demand before reserving space or splitting sources.
    local requested=0
    for i=1,math.min(#sources,quota) do requested=requested+sources[i].count end
    while #steps<quota do
        local index,target,moved=nil,nil,0
        for i,item in ipairs(sources) do
            if item.count<=moved then break end
            local amount,position=WithdrawSpace(item,targets)
            if amount>moved then index,target,moved=i,position,amount end
        end
        if not index then break end
        local item=sources[index]
        if target then
            PlanMove(steps,target,item,item.count,moved)
        else
            -- Reserve the space for one native auto-store, which can fill several slots.
            PlanItem({},targets,item,moved,false,key,true)
            steps[#steps+1]={source={bag=page,slot=item.slot},itemID=item.itemID,link=item.link,
                sourceCount=item.count,autoStore=true}
        end
        local op=steps[#steps]
        op.guildWithdraw,op.guildOwner,op.preset=D.knownTabs,D.guildOwner,key
        op.name,op.icon,op.quality=item.name,item.icon,item.quality
        total=total+moved
        if moved==item.count then table.remove(sources,index)
        else item.count=item.count-moved;table.sort(sources,LargerStack) end
    end
    return steps,total,requested,total<requested
end

function D:CountGuildWithdrawPreset(page,key)
    local steps,total,requested,spaceShort=self:PlanGuildWithdrawPreset(page,key)
    return total or 0,steps~=nil,requested or 0,spaceShort or false
end

function D:TransferGuildWithdrawPreset(page,key)
    local steps,total=self:PlanGuildWithdrawPreset(page,key)
    if not steps then return false end
    if #steps==0 then B:Notify("bank.transfer_empty");return false end
    return B.Actions:Start(steps,"deposit",total)
end

local function WithdrawTarget(op,item)
    local pos=op.target
    local slots,capacity,family,space=A.ReadBag(pos.bag,false,"bags")
    if not slots or pos.slot>capacity or B:GetConfig().locks[SlotKey(pos.bag,pos.slot)]
        or not A.Fits(item,{id=pos.bag,kind="bags",family=family,space=space}) then return false end
    local dest=slots[pos.slot]
    if not dest then return op.targetCount==0 end
    return not B.Actions:Protected(dest) and WithdrawStackMatches(item,dest)
        and dest.count==op.targetCount and dest.count+(op.count or item.count)<=item.maxStack,dest.guid
end

function D:SubmitGuildWithdraw(op,waiting)
    local page,slot=op.source.bag,op.source.slot
    if not self:GuildReceiptAllowed(op) or not self.knownTabs[page] then return false end
    local queue=B.Actions.queue
    local allowance=math.min(queue.withdrawRemaining or math.huge,WithdrawAllowance(page) or 0)
    if allowance<1 then return false end
    queue.withdrawRemaining=allowance-1
    local item=WithdrawSource(page,slot,op.preset)
    if not item or item.link~=op.link or item.count~=op.sourceCount then return false end
    waiting.source=item
    waiting.before=A.ItemCount(item.itemID)
    if not waiting.before then return false end
    if op.autoStore then
        local targets=CarryTargets()
        waiting.variantBefore=targets and CarriedVariantCount(item,targets)
        if not waiting.variantBefore then return false end
        local quantity,position=WithdrawSpace(item,targets)
        if position or quantity~=item.count then return false end
        return self:WithdrawGuildItem(item,true,waiting)
    end
    local fits,guid=WithdrawTarget(op,item)
    if not fits then return false end
    waiting.targetGUID=guid
    local picked
    if op.count then picked=A.SplitGuildItem(page,slot,op.count) else picked=self:WithdrawGuildItem(item,false,waiting) end
    local cursor=A.CursorItem()
    if not picked or B.Actions.waiting~=waiting or not self:GuildReceiptAllowed(op)
        or not cursor or cursor.itemID~=item.itemID or not self:SameGuildLink(cursor.link,item.link) then return false end
    local stillFits,currentGUID=WithdrawTarget(op,item)
    if not stillFits or currentGUID~=guid then return false end
    -- An interrupt inside the native pickup can arrive before the cursor becomes visible.
    if B.Actions.guildInterrupted or B.Actions.waiting~=waiting then return false end
    return A.Pickup(op.target.bag,op.target.slot)
end

function D:ConfirmGuildWithdraw(waiting)
    local op=waiting.operation
    if not self:GuildReceiptAllowed(op) then return false end
    if A.CursorBusy() then return end
    local moved=op.count or op.sourceCount
    local source,err=self:GuildSlot(op.source.bag,op.source.slot)
    if err then return end
    if source then
        if source.locked or source.link~=op.link or source.count~=op.sourceCount-moved then return end
    else
        if op.count then return end
        local ok,link=pcall(GetGuildBankItemLink,op.source.bag,op.source.slot)
        if not ok or S.IsSecretValue(link) or link~=nil then return end
    end
    if A.ItemCount(op.itemID)~=waiting.before+moved then return end
    if op.autoStore then
        local targets=CarryTargets()
        if not targets or CarriedVariantCount(waiting.source,targets)~=waiting.variantBefore+moved then return end
    else
        local dest=A.Slot(op.target.bag,op.target.slot)
        if not dest or dest.locked or not WithdrawStackMatches(waiting.source,dest) or dest.count~=op.targetCount+moved
            or waiting.targetGUID and dest.guid~=waiting.targetGUID then return end
    end
    return true
end

local function PlanPersonalPreset(key,quantityFor,carry,bank,withdraw)
    local items=B.Model:List(withdraw and bank or carry)
    return PlanTransfer(items,withdraw and "bags" or "bank",withdraw and carry or bank,quantityFor,key)
end

function D:PreviewPreset(key)
    local quantityFor=PresetQuantity(key)
    if not quantityFor or PersonalTransferBlocked() then return end
    local carry,bank,ready=TransferBags()
    if not ready or #carry==0 or #bank==0 then return end
    local deposit=PlanPersonalPreset(key,quantityFor,carry,bank,false)
    local withdraw=PlanPersonalPreset(key,quantityFor,carry,bank,true)
    return deposit,withdraw
end

function D:TransferPreset(key,withdraw)
    local quantityFor=PresetQuantity(key)
    if not quantityFor then return false end
    local carry,bank=ReadyTransferBags()
    if not carry then return false end
    return StartTransfer(PlanPersonalPreset(key,quantityFor,carry,bank,withdraw==true))
end

function D:TransferCategory(window,section,group)
    if section=="recent" then return false,"unsupported" end
    if type(section)~="string" or section=="" or group~=nil and type(group)~="string"
        or type(window)~="table" or not window.open or window.owner then return false end
    local withdrawing=window.liveBank=="bank"
    if not withdrawing and (window.liveBank or window.id~="player") then return false end
    local config=B:GetConfig()
    local bankLayout=withdrawing and config.bankView and config.bankView.layout
    if (window.effectiveLayout or bankLayout or window.layout or config.layout)~="category" then return false end
    local carry,bank=ReadyTransferBags()
    if not carry or not window.open then return false end
    local items=B.Model:List(withdrawing and bank or carry)
    local steps,total=PlanTransfer(items,withdrawing and "bags" or "bank",withdrawing and carry or bank,function(item)
        if item.section~=section and not (section=="other" and item.section=="system") then return end
        local itemGroup=section=="other" and item.group=="" and "misc" or item.group
        if group and group~="" and itemGroup~=group then return end
        local pinned=window.pinnedSlots and window.pinnedSlots[item.key]
        if pinned and pinned.itemID==item.itemID and pinned.link==item.link then return end
        if B.Classification:Matches(item,window.query) then return item.count end
    end)
    return StartTransfer(steps,total)
end
-- Capture the candidates at dispatch time. The selected tab may change before Flush.
function D:MarkGuildSlots(locks)
    if not self.guildOwner or not A.CurrentGuildTab then return end
    local mode=locks and "locks" or "slots"
    local function Mark(tab)
        if self.allowed[tab] and self.slotEvents[tab]~="slots" then self.slotEvents[tab]=mode end
    end
    local current=A.CurrentGuildTab()
    Mark(current)
    if not locks then
        local waiting=B.Actions.waiting
        if waiting and waiting.equipmentCount and waiting.queryAt and waiting.operation.target.bag==current then
            waiting.postQuerySlots=true
        end
        Mark(self.queryTab)
        Mark(self.cursorSource)
        for tab,at in pairs(self.departed) do
            if GetTime()-at>replyWindow then self.departed[tab]=nil
            elseif not self.slotEvents[tab] then self.overviewChecks[tab]=true end
        end
        if ShowingOverview() then
            for tab in pairs(self.allowed) do
                if not self.slotEvents[tab] and not self.toQuery[tab] then self.overviewChecks[tab]=true end
            end
        end
        ScheduleQuery(querySpacing)
    end
end
function D:GuildCursorChanged()
    local p=self.withdrawal
    if p and p.pickup and not p.batch then
        local cursor=A.CursorItem()
        if cursor and cursor.itemID==p.id then
            if GetTime()<=p.deadline then p.held=true end
        elseif p.held then
            p.held=nil
            if A.CursorBusy() or A.CurrentGuildTab()~=p.tab or not ReadableTab(p.tab) then
                self.withdrawal=nil
            else
                local source=self:GuildSlot(p.tab,p.slot)
                if source and source.link==p.saved.slots[p.slot].link and source.count==p.saved.slots[p.slot].count then
                    self.withdrawal=nil
                else
                    p.deadline=GetTime()+replyWindow
                    B:QueueFlush()
                end
            end
        end
    end
    if self.cursorSource and not A.CursorBusy() then
        if self.allowed[self.cursorSource] then self.toQuery[self.cursorSource]=true end
        self.cursorSource=nil
        ScheduleQuery(querySpacing)
    end
end
function D:FlushGuildSlots()
    local changed=false
    for tab,mode in pairs(self.slotEvents) do
        self.slotEvents[tab]=nil
        if RefreshTabSnapshot(tab,mode=="locks") then changed=true end
    end
    return changed
end
-- The native call can succeed even if the server rejects the withdrawal.
-- Capture the only occupied cell and a live carried count before submitting.
function D:WithdrawGuildItem(item,autoStore,batch)
    local tab,slot=item.bag,item.slot
    self.withdrawal=nil
    local cache=B.Cache:GetContainer(self.guildOwner,"guild")
    local saved=cache and cache.bags[tostring(tab)]
    if saved and next(saved.slots)==slot and next(saved.slots,slot)==nil then
        local old=saved.slots[slot]
        local before=A.ItemCount(item.itemID)
        if old.link==item.link and old.count==item.count and before then
            self.withdrawal={tab=tab,slot=slot,id=item.itemID,before=before,expected=before+item.count,pickup=not autoStore,
                owner=self.guildOwner,saved=saved,batch=batch,deadline=GetTime()+((autoStore or batch) and withdrawalWindow or replyWindow)}
        end
    end
    local ok=A.GuildItemAction(tab,slot,autoStore)
    if not ok then self.withdrawal=nil elseif self.withdrawal then B:QueueFlush() end
    return ok
end

function D:CheckGuildWithdrawal(confirmedBatch)
    local p=self.withdrawal
    if not p or p.batch and p.batch~=confirmedBatch then return end
    local selected=A.CurrentGuildTab()==p.tab
    if (not p.held and GetTime()>p.deadline) or A.InCombat() or self.guildOwner~=p.owner or p.pickup and not selected
        or not A.BankWindowShown("guild") or not ReadableTab(p.tab) then self.withdrawal=nil;return end
    local cache=B.Cache:GetContainer(self.guildOwner,"guild")
    if not cache or cache.bags[tostring(p.tab)]~=p.saved then self.withdrawal=nil;return end
    if p.pickup and A.CursorBusy() then return end
    local carried=A.ItemCount(p.id)
    if carried and (carried<p.before or carried>p.expected) then self.withdrawal=nil;return end
    if carried~=p.expected then return end
    local stillThere,err=self:GuildSlot(p.tab,p.slot)
    if err then return end
    if stillThere then
        -- A bag gain while the original still exists may be unrelated. Do
        -- not pair that gain with an all-nil read caused by leaving the tab.
        if selected then p.gainWhileOccupied=true end
        return
    end
    if p.gainWhileOccupied and not selected then return end
    return self:SnapshotGuild(false,p.tab,p)
end

function D:SnapshotGuild(refreshOnly,tab,withdrawn)
    tab=tab or A.CurrentGuildTab()
    if not ReadableTab(tab) then return end
    local pending=self.guildRequests[tab]
    if refreshOnly and (not self.knownTabs[tab] or pending) then return end
    local bag={id=tab,capacity=98,family=0,slots={}}
    local previous=self.guildPages[tab]
    local changed=not previous
    local lockChanged=false
    for slot=1,98 do
        local item,err=self:GuildSlot(tab,slot,not refreshOnly)
        if withdrawn and not item and not err then
            local ok,link=pcall(GetGuildBankItemLink,tab,slot)
            if not ok or S.IsSecretValue(link) or link~=nil then return end
        end
        if err then
            if not refreshOnly and not withdrawn then
                self.knownTabs[tab],self.guildPages[tab]=nil,nil
                self.emptyRead[tab],self.refreshingEmpty[tab]=nil,nil
            end
            return
        end
        if item then
            item.uid=item.key
            item.space="normal"
        end
        local old=previous and previous.slots[slot]
        if old~=item then
            if not old or not item or old.link~=item.link or old.count~=item.count or old.name~=item.name
                or old.classID~=item.classID or old.quality~=item.quality or old.maxStack~=item.maxStack
                or old.bound~=item.bound or old.level~=item.level or old.bindType~=item.bindType or old.equipLoc~=item.equipLoc
                or old.icon~=item.icon or old.subClassID~=item.subClassID or old.subType~=item.subType or old.price~=item.price then changed=true
            elseif old.locked~=item.locked then lockChanged=true end
        end
        bag.slots[slot]=item
    end
    if refreshOnly then
        if not changed and lockChanged then self.guildPages[tab]=bag end
        return
    end
    if withdrawn and (self.withdrawal~=withdrawn or bag.slots[withdrawn.slot]) then return end
    local origins=self.guildOrigins[tab]
    if origins then
        for slot,link in pairs(origins) do
            local current=bag.slots[slot]
            if not current or not self:SameGuildLink(link,current.link) and not IsGuildContextOmission(link,current.link) then
                origins[slot]=nil
            end
        end
        if not next(origins) then self.guildOrigins[tab]=nil end
    end
    if withdrawn then
        self.withdrawal=nil
        self.knownTabs[tab],self.guildPages[tab]=nil,nil
        self.emptyRead[tab]=tab==A.CurrentGuildTab() and not next(bag.slots) or nil
        self.refreshingEmpty[tab]=not next(bag.slots) or nil
        -- The saved snapshot contained only the withdrawn stack. Reconcile
        -- its cache without granting write readiness or consuming a tab query.
        B.Cache:WriteBag("guild",tab,bag,false)
        return true
    end
    -- The slot event has no tab ID. An unconfirmed all-nil page may still be loading.
    self.refreshingEmpty[tab]=nil
    if not next(bag.slots) then
        self.knownTabs[tab],self.guildPages[tab]=nil,nil
        self.emptyRead[tab]=true
        return
    end
    self.emptyRead[tab]=nil
    self.knownTabs[tab]=true
    self.guildRequests[tab]=nil
    self.departed[tab]=nil
    self.toQuery[tab]=nil
    self.purchased[tab]=nil
    if self.queryTab==tab then
        self.queryTab=nil
        CancelQueryTimer()
        ScheduleQuery(querySpacing)
    end
    if changed or lockChanged then self.guildPages[tab]=bag end
    if changed then B.Cache:WriteBag("guild",tab,bag,false) end
end
