local YUI=_G.YUI
local B=YUI and YUI.YBags
if not B then return end
local A,V,G=YUI.API.Bags,B.View,YUI.GUI2
local W={}
B.BankView=W

local function SessionOpen(kind)
    return B.active and YUI.IsForever and A.BankWindowShown(kind)
        and (kind=="bank" and B.bankOpen or kind=="guild" and B.guildOpen)
end

local function TabName(tab)
    return tab.name and tab.name~="" and tab.name:gsub("|","||") or string.format(B:T("bank.page"),tab.index)
end

local function AddGuildPage(w,bag,items,empties,cached)
    local manual=cached and (B.Deposit.emptyRead[bag.id] or B.Deposit.purchased[bag.id])
    for slot=1,bag.capacity do
        local item=bag.slots[slot]
        if item then
            item.guildCached=cached or nil
            item.new=false
            item.uid=item.key or ("guild:"..bag.id..":"..slot)
            items[#items+1]=item
        elseif w.page then
            empties[#empties+1]={empty=true,bag=bag.id,slot=slot,family=0,space="normal",guildCached=cached or nil,guildManual=manual or nil}
        end
    end
end

function W:Items(w)
    w.tabs=w.liveBank=="bank" and A.BankTabs("bank") or A.GuildTabs()
    local items,empties,ids={},{},{}
    local passing,complete=0,true
    w.pageInfo=nil;w.hasCache=nil;w.crossPageCount=nil
    w.visiblePageCount=0
    w.unreadGuildPages=0
    w.observedGuildEmpty=false
    -- A selected tab may display a read-only historical grid. Overview
    -- counts, filters and locate targets all use this session's ready tabs.
    local overview=w.liveBank=="guild" and not w.page and w.guildMode=="items"
    local readGuildPage=overview and B.Deposit.GetGuildOverviewPage or B.Deposit.GetGuildPage
    local cache=w.liveBank=="guild" and w.page and B.Cache:GetContainer(B.Cache.guildKey,"guild")
    for _,tab in ipairs(w.tabs) do
        if w.page==tab.id then w.pageInfo=tab end
        if tab.view then w.visiblePageCount=w.visiblePageCount+1 end
        if w.liveBank=="bank" or w.page==nil or w.page==tab.id then
            if w.liveBank=="bank" then
                local bag=B.Model.bags[tab.id]
                if B.Runtime.kind[tab.id]=="bank" and B.Runtime.readable[tab.id] and bag and bag.capacity>0 then
                    ids[#ids+1]=tab.id;passing=passing+1
                else complete=false end
            elseif tab.view then
                local cached=false
                local bag,state=readGuildPage(B.Deposit,tab.id)
                if not bag then
                    local displayable=state=="pending" or state=="purchased"
                    local observed=state=="observed" or displayable and (state=="purchased" or B.Deposit.emptyRead[tab.id])
                    local showEmpty=observed and w.guildMode=="items" and w.page==tab.id and A.CurrentGuildTab()==tab.id
                    bag=displayable and not showEmpty and cache and cache.bags[tostring(tab.id)]
                    if bag then
                        -- Cache writes replace the entire page. A view-owned copy can be
                        -- reused while searching, without decorating the saved record.
                        if w.guildMode=="items" then
                            local copy=w.cachedGuildPages[tab.id]
                            if not copy or copy.source~=bag then
                                copy={source=bag,display=B:Copy(bag)}
                                w.cachedGuildPages[tab.id]=copy
                            end
                            bag=copy.display
                        end
                        cached=true
                        w.hasCache=true
                    end
                    complete=false
                    if not bag and not observed then w.unreadGuildPages=w.unreadGuildPages+1 end
                    if not bag and observed and w.page==tab.id and w.guildMode=="items" then
                        w.observedGuildEmpty=true
                        for slot=1,98 do
                            empties[#empties+1]={empty=true,bag=tab.id,slot=slot,space="normal",guildManual=true}
                        end
                    end
                end
                if not cached then w.cachedGuildPages[tab.id]=nil end
                if bag then
                    passing=passing+1
                    if w.guildMode=="items" then AddGuildPage(w,bag,items,empties,cached) end
                end
            else
                w.cachedGuildPages[tab.id]=nil
                if w.page then complete=false end
            end
        end
    end
    if w.liveBank=="bank" then items,empties=B.Model:List(ids) end
    w.readyPages,w.pagesComplete=passing,complete
    return items,empties
end

function W:Select(w,tab)
    if w.liveBank~="guild" or A.InCombat() or B.Actions.queue or B.Actions.nativeSort or not SessionOpen("guild") then return false end
    if A.CursorBusy() and (not tab or not A.CursorItem() or w.guildMode~="items") then return false end
    if tab and not B.Deposit:SelectGuildTab(tab) then return false end
    if not tab then B.Deposit:RequestGuildPages() end
    B.GuildServices:ClearTabTooltip(w)
    self:CancelGuildSplit()
    B.GuildInventory:Clear(w)
    if w.guildMode=="purchase" then w.guildMode="items" end
    if w.page~=tab then w.query="";w.search:SetText("") end
    w.page=tab
    w.scroll:SetVerticalScroll(0)
    V:Layout(w,true)
    return true
end

local function CommandTooltip(button)
    if button.purchase then return end
    GameTooltip:SetOwner(button,"ANCHOR_TOP")
    GameTooltip:SetText(button.tooltip)
    if button.detail then GameTooltip:AddLine(button.detail,.8,.82,.85) end
    GameTooltip:Show()
end
local function SetupCommand(button,click)
    button:SetScript("OnClick",click)
    button:SetScript("OnEnter",CommandTooltip)
    button:SetScript("OnLeave",function() GameTooltip:Hide() end)
    if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end
    return button
end
local tabHeight,tabGap,iconSize,tabInset=34,6,24,7
local minPageWidth=72
local tabChrome=tabInset*2+iconSize+6
local tabRecipe=G.IconSkins:Resolve({skinId="minimal-rounded",skinOptions={
    ["minimal-rounded"]={border="medium",shadow=true,zoom=.03},
}},B.PRODUCT_ID)

local purchaseAtlas="Garr_Building-AddFollowerPlus"
local function PurchaseTabIcon(button)
    local slot=button.purchaseIcon
    if not slot then
        slot=G:CreateFrame(button,{width=iconSize,height=iconSize})
        slot:SetPoint("LEFT",tabInset,0);slot:EnableMouse(false)
        slot.icon=G:CreateTexture(slot);slot.icon:SetAllPoints()
        button.purchaseIcon=slot
    end
    slot:Show()
    if slot.bound then return end
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(purchaseAtlas) then
        slot.icon:SetAtlas(purchaseAtlas,false)
        slot.bound=not slot.icon.GetTexture or not not slot.icon:GetTexture()
    end
    local bound=slot.bound
    if not bound and not slot.plusHorizontal then
        -- A small centered cross stays inside the rounded mask and needs no file or font.
        slot.plusHorizontal=G:CreateTexture(slot,"color.text.heading","OVERLAY")
        slot.plusVertical=G:CreateTexture(slot,"color.text.heading","OVERLAY")
        slot.plusHorizontal:SetPoint("CENTER");slot.plusHorizontal:SetSize(14,4)
        slot.plusVertical:SetPoint("CENTER");slot.plusVertical:SetSize(4,14)
    end
    slot.icon:SetShown(not not bound)
    if slot.plusHorizontal then
        slot.plusHorizontal:SetShown(not bound);slot.plusVertical:SetShown(not bound)
    end
end

local function TabWidth(label)
    -- Leave room for fractional glyph positions after UI scaling.
    return tabChrome+B.Appearance:TextWidth(label,"label")+3
end

local function PackTabs(positions,first,last,available,pageCap)
    local row,nextLeft=1,0
    for i=first,last do
        local pos=positions[i]
        local size=pos.page and math.min(pageCap,pos.wanted) or pos.wanted
        if nextLeft>0 and nextLeft+size>available then row,nextLeft=row+1,0 end
        pos.width=size
        pos.x,pos.y=pos.purchase and available-size or nextLeft,-(row-1)*(tabHeight+tabGap)
        nextLeft=nextLeft+size+tabGap
    end
    return row
end

local function TabRows(w,width,m,mode)
    if #w.tabs==0 or mode=="moneylog" then return 0 end
    local overview=mode=="items" or mode=="purchase"
    local buy=overview and B.GuildServices:CanBuy(w)
    local first=overview and 1 or 2
    local last=#w.tabs+1+(buy and 1 or 0)
    local available=math.max(1,width-m.left-m.right)
    w.guildTabPositions=w.guildTabPositions or {}
    local positions=w.guildTabPositions
    for i=first,last do
        local tab=w.tabs[i-1]
        local purchase=buy and i==last
        local label=tab and TabName(tab) or B:T(purchase and "bank.buy_guild_tab" or "bank.overview")
        local pos=positions[i]
        if not pos then pos={};positions[i]=pos end
        pos.label,pos.page,pos.purchase=label,tab~=nil,purchase
        pos.wanted=math.min(available,math.max(tab and minPageWidth or 0,TabWidth(label)))
    end
    local rows=PackTabs(positions,first,last,available,available)
    local budgetRows=rows
    if w.guildTabRowLimit and rows>w.guildTabRowLimit then
        -- Short screens only: keep as much of each long name as will fit, with
        -- the overview and purchase action still measured at their full widths.
        local low,high=math.min(available,tabChrome+1),math.floor(available)
        while low<high do
            local mid=math.ceil((low+high)/2)
            if PackTabs(positions,first,last,available,mid)<=w.guildTabRowLimit then low=mid
            else high=mid-1 end
        end
        rows=PackTabs(positions,first,last,available,low)
        budgetRows=math.max(rows,w.guildTabRowLimit)
    end
    return rows,first,last,buy,budgetRows
end

local function StripHeight(rows)
    return rows*(tabHeight+tabGap)-tabGap+2
end

-- Maximum body offset for this window's tabs across all modes. The item status
-- contains at most three independently wrapped parts (access, limit, remaining).
local function HeaderExtent(rows,m)
    return m.contentTop+3+StripHeight(rows)+6+3*16+5
end

function W:GuildHeaderBudget(w,width,m)
    local _,_,_,_,rows=TabRows(w,width,m,"items")
    return HeaderExtent(rows or 1,m)
end

function W:GuildTabRowLimit(availableHeaderHeight,m)
    return math.max(1,math.floor((availableHeaderHeight-HeaderExtent(0,m))/(tabHeight+tabGap)))
end

function W:CreateTab(w)
    local button=G:CreateButtonFrame(w.tabStrip,{height=tabHeight})
    local icon=G:CreateIconSlot(button,{size=iconSize,variant="bare",shape=tabRecipe.shape,
        border=tabRecipe.border,zoom=tabRecipe.zoom,animate=false})
    icon:EnableMouse(false)
    icon:SetIconBorderColor(tabRecipe.borderColor)
    icon:SetPoint("LEFT",tabInset,0)
    local shadow=G:CreateShapeShadow(icon)
    G:ApplyShapeShadow(shadow,{enabled=true,shape=tabRecipe.shape,color=tabRecipe.shadowColor},
        {anchor=icon,width=iconSize,height=iconSize,allowLayout=true})
    button.tabIcon=icon
    button.label=G:CreateText(button,"",12,"color.text.secondary")
    B.Appearance:Text(button.label,"label")
    button.label:SetPoint("LEFT",tabInset+iconSize+6,0)
    button.label:SetJustifyH("LEFT")
    button.label:SetWordWrap(false)
    button.active=G:CreateTexture(button,"color.control.hover","BACKGROUND")
    button.active:SetAllPoints();button.active:SetAlpha(.55)
    button.underline=G:CreateTexture(button,"color.text.heading","OVERLAY")
    button.underline:SetPoint("BOTTOMLEFT",2,0);button.underline:SetPoint("BOTTOMRIGHT",-2,0);button.underline:SetHeight(2)
    button:RegisterForClicks("LeftButtonUp","RightButtonUp")
    SetupCommand(button,function(owner,mouse)
        B.GuildServices:ClearTabTooltip(w)
        GameTooltip:Hide()
        if mouse=="RightButton" then
            if owner.page then B.GuildServices:EditTab(w,owner.page) end
        elseif owner.purchase then B.GuildServices:OpenPurchase(w)
        else self:Select(w,owner.page) end
    end)
    button:SetScript("OnEnter",function(owner)
        if owner.page and w.guildServices then B.GuildServices:ShowTabTooltip(w,owner)
        else CommandTooltip(owner) end
    end)
    button:SetScript("OnLeave",function(owner)
        B.GuildServices:ClearTabTooltip(w,owner)
        if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
    end)
    B.Appearance:CommandFeedback(button)
    return button
end

function W:LayoutTabs(w,width,m)
    local strip=w.tabStrip
    local rows,first,last,buy=TabRows(w,width,m,w.guildMode)
    strip:SetShown(rows>0)
    if rows==0 then
        for _,button in pairs(w.tabButtons) do button:Hide() end
        B.GuildServices:ClearTabTooltip(w)
        return
    end
    local available=width-m.left-m.right
    strip:ClearAllPoints();strip:SetPoint("TOPLEFT",m.left,-w.guildTabTop)
    strip:SetSize(available,w.guildTabHeight)
    if not w.tabButtons[1] then w.tabButtons[1]=self:CreateTab(w) end
    for i=first,last do
        local button=w.tabButtons[i]
        if not button then button=self:CreateTab(w);w.tabButtons[i]=button end
        local tab=w.tabs[i-1]
        local purchase=buy and i==last
        local pos=w.guildTabPositions[i]
        local label=pos.label
        button.page=tab and tab.id
        if purchase and not button.purchase and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
        button.purchase=purchase or false
        button.tooltip=not purchase and label or nil
        local allowed=not tab and (purchase or w.visiblePageCount>0) or tab and tab.view
        local selected=purchase and w.guildMode=="purchase" or not purchase and w.guildMode~="purchase" and w.page==button.page
        button.tabIcon:SetShown(not purchase)
        if purchase then
            PurchaseTabIcon(button)
        else
            if button.purchaseIcon then button.purchaseIcon:Hide() end
            B.Appearance:IdentityIcon(button.tabIcon,tab and (tab.icon or 134400) or 132181,tabRecipe.zoom)
        end
        button.tabIcon.icon:SetDesaturated(not allowed)
        button.label:SetText(label)
        B.Appearance:GuildTabSelection(button,selected,allowed,i==1)
        button:SetEnabled(allowed==true);button:SetAlpha(allowed and 1 or .5)
        button.detail=nil
        if tab and not tab.view then button.detail=B:T("bank.denied")
        elseif tab and w.page==tab.id and w.hasCache then button.detail=B:T("bank.guild_snapshot")
        elseif tab and w.page==tab.id and w.observedGuildEmpty then
            button.detail=B:T(B.Deposit.purchased[tab.id] and "bank.guild_new_tab" or "bank.guild_observed_empty")
            if tab.deposit and A.CurrentGuildTab()==tab.id then
                button.detail=button.detail.." · "..B:T("bank.guild_drop_hint")
            end
        elseif tab and not B.Deposit.emptyRead[tab.id] and not B.Deposit.purchased[tab.id]
            and (w.page or not B.Deposit.refreshingEmpty[tab.id])
            and (not B.Deposit.knownTabs[tab.id] or w.page and B.Deposit.guildRequests[tab.id]) then
            button.detail=B:T("bank.guild_items_pending")
        end
        button:SetWidth(pos.width)
        button.label:SetWidth(math.max(1,pos.width-tabChrome))
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT",pos.x,pos.y)
        button:Show()
    end
    if first==2 and w.tabButtons[1] then w.tabButtons[1]:Hide() end
    for i=last+1,#w.tabButtons do w.tabButtons[i]:Hide() end
    B.GuildServices:RefreshTabTooltip(w)
end

local presets={
    {"materials","Interface\\Icons\\INV_Ingot_02"},
    {"recipes",134327},
    {"consumables",134856},
    {"boe","Interface\\Icons\\INV_Chest_Chain_14"},
    {"scrolls",4549171}, -- Forever item 213548.
}
local socketSize,socketStep=28,32
local lockedSocket="atlas:bankslot-icon-lock"

local function SocketTooltip(button)
    local socket=button.socket or button
    GameTooltip:SetOwner(button,"ANCHOR_TOP")
    local shown=socket.hasBag and GameTooltip:SetBagItem(socket.container,socket.index)
    if socket.reagent then
        local r,g,b=G:GetColor("color.state.success")
        local title=B:T("bag.reagent_slot")
        if shown then
            if GameTooltipTextLeft1 then GameTooltipTextLeft1:SetTextColor(r,g,b) end
            GameTooltip:AddLine(title,r,g,b)
        else GameTooltip:SetText(title,r,g,b) end
    end
    if shown or socket.reagent then
        GameTooltip:AddLine(B:T("bag.remove_hint"),.8,.82,.85)
    else
        GameTooltip:SetText(B:T(socket.bought and "bank.bag_slot" or "bank.bag_locked"))
        if socket.bought then GameTooltip:AddLine(B:T("bag.equip_empty"))
        elseif socket.price then
            local available=socket.affordable~=false and 1 or .3
            GameTooltip:AddLine(A.MoneyText(socket.price,12),1,available,available)
        elseif socket.waiting then GameTooltip:AddLine(B:T("bank.loading"))
        else GameTooltip:AddLine(B:T("bank.bag_in_order")) end
    end
    GameTooltip:Show()
end

local function SetSocketHover(w,button)
    local previous=w.hoverSocket
    if previous~=button then
        if previous then previous:UnlockHighlight() end
        if button then button:LockHighlight() end
        w.hoverSocket=button
    end
    local bag=button and button.bag
    if w.hoverBag==bag then return false end
    w.hoverBag=bag
    return true
end

local function QueueBagRelease(drag)
    if W.releasedBagDrag==drag then return end
    W.releasedBagDrag=drag
    B:QueueFlush()
end

local function OnBagMouse(event,mouse)
    local drag=W.bagDrag
    if not drag or mouse~="LeftButton" then return end
    if event=="GLOBAL_MOUSE_DOWN" then
        drag.dropPressed=true
    elseif drag.dropPressed then
        QueueBagRelease(drag)
    end
end

local function TakeBagDrag(self)
    local drag=self.bagDrag
    if not drag then return end
    self.bagDrag=nil
    self.releasedBagDrag=nil
    YUI.Event:OffOwner(self)
    B.Stats.listeners=math.max(0,B.Stats.listeners-2)
    return drag
end

function W:RefreshBagDrag()
    local drag=self.bagDrag
    if drag and (not A.CursorBusy() or not A.ItemOnCursorFromSlot(drag.container,drag.slot,drag.itemID)) then TakeBagDrag(self) end
end

function W:FlushBagDragRelease()
    if self.releasedBagDrag and self.releasedBagDrag==self.bagDrag then self:DropBagDrag() end
end

function W:DropBagDrag(target)
    local drag=TakeBagDrag(self)
    if not drag then return false end
    if target and target.bag~=drag.bag and not A.InCombat() and not B.Actions.queue and SessionOpen("bank")
        and A.ItemOnCursorFromSlot(drag.container,drag.slot,drag.itemID) then
        local bag=B.Model.bags[target.bag]
        local cursor=A.CursorItem()
        local occupied,err=A.Slot(target.bag,target.slot)
        if cursor and bag and bag.space=="normal" and A.Fits(cursor,bag) and not occupied and not err
            and not B:GetConfig().locks[tostring(target.bag)..":"..target.slot] then
            A.Pickup(target.bag,target.slot)
            B:MarkBag(target.bag)
        end
    end
    local cleared=A.CancelBankBagPickup(drag.container,drag.slot,drag.itemID)
    if not cleared and A.ItemOnCursorFromSlot(drag.container,drag.slot,drag.itemID) then B:Notify("error.operation") end
    V:RefreshItemInputs()
    self:UpdateBankControls()
    return true
end

function W:MakeBankSocket(w,index)
    local button=B.Appearance:Item(w.socketBar,false)
    button.image=button.icon
    B.Appearance:SizeIcon(button,socketSize)
    button.icon:ClearAllPoints();button.icon:SetPoint("CENTER")
    button:SetPoint("LEFT",(index-2)*socketStep,0)
    button.index=index
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
    button:SetScript("OnEnter",function(owner)
        if SetSocketHover(w,owner) then V:Paint(w) end
        if V:ItemTooltipBlocked() then GameTooltip:Hide();return end
        SocketTooltip(owner)
    end)
    button:SetScript("OnLeave",function(owner)
        if w.hoverSocket==owner and SetSocketHover(w,nil) then V:Paint(w) end
        if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
    end)
    button:RegisterForClicks("LeftButtonUp","RightButtonUp")
    button:RegisterForDrag("LeftButton")
    local function Move(owner,mouse,dragging)
        if not SessionOpen("bank") or B.Actions.queue or B.Actions.nativeSort then return end
        local drag=self.bagDrag
        if drag then
            if mouse~="RightButton" and owner.bought and owner.index~=drag.slot then A.MoveBankBag(owner.index) end
            self:DropBagDrag()
            return
        end
        if not owner.bought then return end
        if A.CursorBusy() then
            if mouse~="RightButton" then A.MoveBankBag(owner.index) end
        elseif mouse=="RightButton" then
            if owner.hasBag then B.BagRemoval:Start(nil,owner.index) end
        elseif owner.hasBag then
            local bag,container=A.BankBagContainer(owner.index)
            local item=container and A.Slot(container,owner.index)
            if item and not A.InCombat() then
                local slots,capacity=A.ReadBag(bag)
                if not slots or capacity<1 then B:Notify("bag.remove_pending");return end
                if next(slots) then B:Notify("bag.drag_nonempty");return end
                if A.MoveBankBag(owner.index) and A.ItemOnCursorFromSlot(container,owner.index,item.itemID) then
                    -- A click pickup already passed its down event. Only the next click should end it.
                    self.bagDrag={bag=bag,container=container,slot=owner.index,itemID=item.itemID,button=owner,dropPressed=dragging}
                    YUI.Event:On("GLOBAL_MOUSE_DOWN",OnBagMouse,self)
                    YUI.Event:On("GLOBAL_MOUSE_UP",OnBagMouse,self)
                    B.Stats.listeners=B.Stats.listeners+2
                    V:RefreshItemInputs()
                end
            end
        end
    end
    button:SetScript("OnClick",function(owner,mouse) Move(owner,mouse) end)
    button:SetScript("OnDragStart",function(owner) if not A.CursorBusy() then Move(owner,"LeftButton",true) end end)
    button:SetScript("OnDragStop",function(owner)
        local drag=self.bagDrag
        if drag and drag.button==owner then
            -- The destination may receive the drop after the source stops dragging.
            QueueBagRelease(drag)
        end
    end)
    button:SetScript("OnReceiveDrag",function(owner) if A.CursorBusy() then Move(owner) end end)
    return button
end

function W:RenderBankSockets(w,m)
    local container,maximum,purchased,price,affordable=A.BankBagBar()
    w.socketBar:ClearAllPoints();w.socketBar:SetPoint("BOTTOMLEFT",m.left,m.bottom+2)
    w.socketDivider:ClearAllPoints()
    w.socketDivider:SetPoint("BOTTOMLEFT",m.left+4,m.bottom+socketSize+4)
    w.socketDivider:SetPoint("BOTTOMRIGHT",-m.right-4,m.bottom+socketSize+4)
    w.socketBar:Show()
    w.socketDivider:Show()
    -- The base bank is the free first tab. Only purchased extensions take a bag.
    local count=math.max(0,(maximum or 9)-1)
    w.socketBar:SetWidth(math.max(1,count*socketStep))
    local buySocket
    for n=1,count do
        local index=n+1
        local button=w.sockets[n]
        if not button then button=self:MakeBankSocket(w,index);w.sockets[n]=button end
        local bought=purchased~=nil and index<=purchased
        local nextSlot=purchased and purchased>=1 and index==purchased+1 and price~=nil
        local item=bought and A.Slot(container,index)
        local background=bought and B.Appearance.bagSocketBackground or lockedSocket
        local source=item and (item.icon or YUI.API.Item.GetIcon(item.itemID)) or background
        local quality=item and A.BankSocketQuality(container,index,item) or nil
        local bagID=item and (button.container==container and button.bankBagID or A.BankBagContainer(index)) or nil
        local bag=bagID and B.Runtime.kind[bagID]=="bank" and B.Runtime.readable[bagID] and B.Model.bags[bagID]
        button.bankBagID,button.bag=bagID,bag and bag.capacity>0 and bagID or nil
        button.reagent=bag and bag.space=="reagent"
        button.bought,button.container,button.hasBag=bought,container,item~=nil and item~=false
        button.itemID,button.waitingQuality=item and item.itemID,item and quality==nil
        button.price,button.affordable=nextSlot and price or nil,affordable
        button.waiting=not purchased or purchased==0 or index==purchased+1 and price==nil
        B.Appearance:BagSocketArtwork(button,source,socketSize,quality,not item)
        if nextSlot then buySocket=button end
        button:Show()
    end
    for n=count+1,#w.sockets do w.sockets[n]:Hide() end
    if buySocket and not w.buyBag then
        -- Leave the inherited hardware OnClick in charge of the native confirmation.
        local buy=G:CreateButtonFrame(w.socketBar,{width=socketSize,height=socketSize,template="BankPanelPurchaseButtonScriptTemplate",
            frameLevel=w.socketBar:GetFrameLevel()+4,hidden=true})
        if A.InitBankBagPurchase(buy) then
            buy:RegisterForClicks("LeftButtonUp")
            buy:SetScript("OnEnter",SocketTooltip)
            buy:SetScript("OnLeave",function() GameTooltip:Hide() end)
            buy:SetScript("OnReceiveDrag",function() self:DropBagDrag() end)
            if buy.SetMotionScriptsWhileDisabled then buy:SetMotionScriptsWhileDisabled(true) end
            B.Appearance:CommandFeedback(buy)
            w.buyBag=buy
        end
    end
    local buy=w.buyBag
    if buy and buy.socket~=buySocket then
        buy.socket=buySocket
        if buySocket then buy:ClearAllPoints();buy:SetAllPoints(buySocket);buy:Show() else buy:Hide() end
    end
    local hovered=w.hoverSocket
    V:RenderCapacity(w)
    return SetSocketHover(w,hovered and hovered:IsShown() and hovered or nil)
end
function W:RefreshSockets()
    local w=V.windows["live-bank"]
    if w and w.open and not A.InCombat() and self:RenderBankSockets(w,B.Appearance:Metrics()) then V:Paint(w) end
end
function W:SocketNeedsItemInfo(itemID)
    local w=V.windows["live-bank"]
    if not w or not w.open then return false end
    for _,button in ipairs(w.sockets) do
        if button.waitingQuality and button.itemID==itemID then return true end
    end
    return false
end
local function UpdateGuildPresets(w)
    if not w or not w.open or not w.presets then return end
    local deposit=V:CanQuickGuildDeposit(w)
    local enabled=not not (deposit or w.guildMode=="items" and w.page and B.Deposit:CanGuildWithdrawPreset(w.page))
    if w.quickPresetsEnabled~=enabled then
        w.quickPresetsEnabled=enabled
        for _,button in ipairs(w.presets) do
            button:SetEnabled(enabled)
            button:SetAlpha(enabled and 1 or .5)
        end
    end
end
function W:UpdateBankControls(queueChanged)
    local guild=V.windows["live-guild"]
    UpdateGuildPresets(guild)
    -- CURSOR_CHANGED can arrive before the final deposit receipt clears the queue.
    if queueChanged and guild and guild.open and guild.guildServices and guild.guildServices.listening then
        B.GuildServices:UpdateMoney(guild)
    end
    local w=V.windows["live-bank"]
    if not w or not w.open then return end
    local enabled=not A.InCombat() and not A.CursorBusy() and not B.Actions.queue and not B.Actions.nativeSort
    if w.buyBag and w.buyBag.socket and w.purchaseEnabled~=enabled then
        w.purchaseEnabled=enabled;w.buyBag:SetEnabled(enabled)
    end
    local sortEnabled=enabled and w.readyPages>0 and A.CanUsePersonalBank()
    if w.sortEnabled~=sortEnabled then
        w.sortEnabled=sortEnabled;w.sort:SetEnabled(sortEnabled);w.sort:SetAlpha(sortEnabled and 1 or .5)
    end
end

-- Summary status describes the data displayed. An observed empty response is
-- enough to describe the screen; it never grants permission for an automatic move.
local function StatusColor(key,text)
    local r,g,b=G:GetColor(key)
    return string.format("|cff%02x%02x%02x%s|r",math.floor(r*255+.5),math.floor(g*255+.5),math.floor(b*255+.5),text)
end

local function StatusLines(parts,width)
    local text,line,rows="","",1
    for _,part in ipairs(parts) do
        local plain=part:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
        local nextLine=line=="" and plain or line.." · "..plain
        if line~="" and B.Appearance:TextWidth(nextLine,"label")>width then
            text,line,rows=text.."\n"..part,plain,rows+1
        else
            text=text..(line=="" and "" or " · ")..part
            line=nextLine
        end
    end
    return text,rows
end

local function GuildItemStatus(w,width)
    if not w.page then
        if w.visiblePageCount==0 then return StatusColor("color.state.danger",B:T("bank.guild_inaccessible")) end
        local details={}
        if w.unreadGuildPages>0 then details[#details+1]=StatusColor("color.state.warning",string.format(B:T("bank.guild_unread_count"),w.unreadGuildPages)) end
        if #details>0 then return StatusLines(details,width) end
        if w.crossPageCount==0 then return B:T("bank.guild_no_match") end
        if #w.items==0 then return B:T("bank.guild_nothing_seen") end
        return ""
    end
    local page=w.pageInfo
    if not page or page.view==nil or not page.view and not page.name and not page.icon
        and page.limit==nil and page.remaining==nil then return B:T("bank.guild_access_pending") end
    if not page.view then return StatusColor("color.state.danger",B:T("bank.guild_inaccessible")) end
    -- GetGuildBankTabInfo supplies rank access independently of item-slot replies.
    -- Only display the remaining allowance of the native selected tab.
    local limit=page.limit
    if limit and limit< -1 then limit=nil end
    local current=w.page==A.CurrentGuildTab()
    local remaining=current and page.remaining or nil
    if remaining and (remaining< -1 or remaining==-1 and limit~=-1
        or limit and limit>=0 and remaining>limit) then remaining=nil end
    local key,tone
    if limit==0 then
        key=page.deposit and "bank.guild_deposit_only" or "bank.guild_view_locked"
        tone="color.state.danger"
    elseif limit==nil then
        key=page.deposit and "bank.guild_can_deposit" or "bank.guild_no_deposit"
        tone="color.state.warning"
    elseif not page.deposit then
        key,tone="bank.guild_withdraw_only","color.state.warning"
    elseif limit==-1 and remaining==-1 then
        key,tone="bank.guild_full_access","color.state.success"
    else
        key,tone="bank.guild_limited_access","color.state.warning"
    end
    local details={StatusColor(tone,B:T(key))}
    if limit~=0 then
        if limit and limit>0 then details[#details+1]=string.format(B:T("bank.guild_daily_limit"),limit)
        elseif not limit and remaining then details[#details+1]=B:T("bank.guild_unknown_limit") end
        if type(remaining)~="number" then
            local pending=B.Deposit.purchased[w.page] and "bank.guild_new_quota_pending"
                or limit and "bank.guild_unknown_remaining" or "bank.guild_quota_pending"
            details[#details+1]=B:T(pending)
        elseif remaining>=0 then
            local left=string.format(B:T("bank.guild_daily_remaining"),remaining)
            details[#details+1]=remaining==0 and StatusColor("color.state.danger",left) or left
        elseif key~="bank.guild_full_access" then details[#details+1]=B:T("bank.withdraw_unlimited") end
    end
    return StatusLines(details,width)
end

function W:GuildBodyTop(w,m)
    local rows=TabRows(w,w.header:GetWidth(),m,w.guildMode)
    w.guildItemStatus=""
    if rows==0 then return m.toolsTop end
    w.guildTabTop=(w.guildMode=="items" and m.contentTop or m.toolsTop)+3
    w.guildTabHeight=StripHeight(rows)
    w.guildStatusTop=w.guildTabTop+w.guildTabHeight+6
    local statusRows
    if w.guildMode=="items" then
        w.guildItemStatus,statusRows=GuildItemStatus(w,w.header:GetWidth()-m.left-m.right)
    end
    return w.guildStatusTop+(w.guildItemStatus~="" and (statusRows or 1)*16+5 or 2)
end

function W:LayoutHeader(w,width,m)
    if w.liveBank=="bank" then
        local available=A.CanUsePersonalBank() and w.readyPages>0
        local step=B.Appearance.toolbarStep
        for n,button in ipairs(w.presets) do
            button:ClearAllPoints();button:SetPoint("RIGHT",w.search,"LEFT",-8-(#w.presets-n)*step,0)
            button:SetEnabled(available);button:SetAlpha(available and 1 or .5)
        end
        w.capacity:SetWidth(width-m.left-m.right-w.search:GetWidth()-w.sort:GetWidth()-#w.presets*step-19)
        w.capacity:SetWordWrap(false)
        if w.readyPages==0 then w.capacity:SetText(B:T("bank.loading")) end
        self:RenderBankSockets(w,m)
        self:UpdateBankControls()
        return
    end
    self:LayoutTabs(w,width,m)
    local items=w.guildMode=="items" and #w.tabs>0
    UpdateGuildPresets(w)
    w.search:SetShown(items)
    local showDeposit=items and w.page~=nil
    for _,button in ipairs(w.presets) do button:SetShown(showDeposit) end
    local tools=showDeposit and #w.presets*B.Appearance.toolbarStep+12 or 8
    w.capacity:SetWidth(math.max(48,width-m.left-m.right-w.search:GetWidth()-tools))
    w.capacity:SetWordWrap(false)
    if items and w.visiblePageCount>0 then
        local capacity=(w.page and 1 or w.visiblePageCount)*98
        local label
        if w.page and w.hasCache then
            label=string.format(B:T("bank.guild_cached_capacity"),#w.items,capacity)
        elseif w.page and w.unreadGuildPages>0 then
            label=string.format(B:T("bank.guild_unknown_capacity"),capacity)
        else
            label=string.format(B:T(w.pagesComplete and "bank.guild_overview_capacity" or "bank.guild_seen_capacity"),#w.items,capacity)
        end
        if w.crossPageCount~=nil then label=string.format(B:T("bank.matches"),w.crossPageCount) end
        w.capacity:SetText(label)
    end
    w.status:ClearAllPoints();w.status:SetPoint("TOPLEFT",m.left,-(w.guildStatusTop or m.toolsTop))
    w.status:SetWidth(width-m.left-m.right)
    w.status:SetText(w.guildItemStatus or "")
    w.status:SetShown(items and w.guildItemStatus~="")
    w.capacity:SetShown(items and w.visiblePageCount>0 and (not w.page or w.pageInfo and w.pageInfo.view))
    B.GuildServices:Layout(w,width,m)
end

local function GuildPresetTooltip(owner,w,key)
    local tab=w.pageInfo
    if not tab then return end
    local depositText,withdrawText
    if V:CanQuickGuildDeposit(w) then
        local _,count,_,requested=B.Deposit:Plan("guild",B:GetConfig().deposit.guild,nil,tab.id,key)
        local direct=tab.limit==-1 and tab.remaining==-1 and not V:GuildBatchNeedsReview(requested,requested and count and requested>count)
        local action=direct and "bank.guild_deposit_now" or "bank.guild_review_list"
        depositText=count~=nil and string.format(B:T(action),count) or B:T("deposit.count_pending")
    elseif not tab.deposit then
        depositText=B:T("bank.preset_no_deposit")
    else
        depositText=B:T("bank.loading")
    end
    if tab.limit==0 then
        withdrawText=B:T("bank.preset_no_withdraw")
    elseif tab.remaining==0 then
        withdrawText=B:T("bank.preset_quota_spent")
    elseif tab.remaining==nil or tab.limit==nil then
        withdrawText=B:T("bank.guild_quota_pending")
    else
        local count,ready,requested,spaceShort=B.Deposit:CountGuildWithdrawPreset(tab.id,key)
        local action=V:GuildBatchNeedsReview(requested,spaceShort) and "bank.guild_review_withdraw" or "bank.preset_withdraw"
        withdrawText=ready and string.format(B:T(action),count) or B:T("deposit.count_pending")
    end
    G.Tooltip:Show(owner,{anchor="ANCHOR_TOP",title=owner.tooltip,actions={
        {button="LeftButton",text=depositText,textTone="heading"},
        {button="RightButton",text=withdrawText,textTone="heading"},
    },footer={text=B:T("bank.guild_batch_beta"),tone="requirement",spaceBefore=true},content=function(body)
        body:AddLine(string.format(B:T("guild.service.quickTarget"),TabName(tab)))
    end})
end

local function SetupBankPresets(w)
    local guild=w.liveBank=="guild"
    w.presets={}
    for n,preset in ipairs(presets) do
        local key,asset=preset[1],preset[2]
        local button=B.Appearance:Icon(w.root,{asset=asset,command="toolbar"})
        button:SetWidth(B.Appearance.toolbarStep)
        button.tooltip=string.format(B:T("bank.preset_title"),B:T("bank.preset."..key))
        button.detail=B:T("bank.preset_hint."..key)
        w.presets[n]=SetupCommand(button,function(_,mouse)
            G.Tooltip:Hide(button)
            if guild then
                if w.open and w.guildMode=="items" and w.page and not (V.guildDepositDialog and V.guildDepositDialog:IsShown()) then
                    V:QuickGuildPreset(button,w,key,mouse=="RightButton")
                end
            else B.Deposit:TransferPreset(key,mouse=="RightButton") end
        end)
        button:RegisterForClicks("LeftButtonUp","RightButtonUp")
        if guild then
            button:SetPoint("RIGHT",w.search,"LEFT",-8-(#presets-n)*B.Appearance.toolbarStep,0)
        end
        button:SetScript("OnEnter",function(owner)
            if guild then return GuildPresetTooltip(owner,w,key) end
            local deposit,depositReady=B.Deposit:CountPreset(key,false)
            local withdraw,withdrawReady=B.Deposit:CountPreset(key,true)
            local actions
            if depositReady and withdrawReady then
                actions={
                    {button="LeftButton",text=string.format(B:T("bank.preset_deposit"),deposit),textTone="heading"},
                    {button="RightButton",text=string.format(B:T("bank.preset_withdraw"),withdraw),textTone="heading"},
                }
            end
            G.Tooltip:Show(owner,{anchor="ANCHOR_TOP",title=owner.tooltip,actions=actions,content=function(body)
                body:AddLine(owner.detail)
                if not actions then body:AddLine(B:T("bank.loading"),"secondary") end
            end})
        end)
        button:SetScript("OnLeave",function(owner) G.Tooltip:Hide(owner) end)
    end
end
local function SetupPersonalBank(w)
    w.sort:RegisterForClicks("LeftButtonUp")
    SetupBankPresets(w)
    w.sockets={}
    w.socketBar=G:CreateFrame(w.root,{height=socketSize})
    w.socketDivider=B.Appearance:BankDivider(w.root)
end
local function SetupGuildBank(w)
    w.settings.guildDepositWindow=w
    w.settings:HookScript("OnEnter",function(owner)
        if V:CanQuickGuildDeposit(w) then
            G.Tooltip:Show(owner,{anchor="ANCHOR_TOP",title=B:T("action.settings"),actions={
                {button="LeftButton",text=B:T("action.settings"),textTone="heading"},
                {button="RightButton",text=B:T("bank.guild_deposit_rules"),textTone="heading"},
            }})
        end
    end)
    w.tabStrip=G:CreateFrame(w.root,{height=tabHeight+2})
    w.tabButtons={}
    w.status=G:CreateText(w.root,"",12,"color.text.secondary");w.status:SetJustifyH("LEFT");w.status:SetWordWrap(false)
    SetupBankPresets(w)
    B.GuildServices:Setup(w)
end

local legendaryOrange,legendaryGold={1,.5,0},{1,.84,0}

function W:Open(kind)
    if A.InCombat() or not SessionOpen(kind) or not A.ParkBankWindow(kind) then return end
    local id="live-"..kind
    local w=V.windows[id]
    if w and w.open then return true end
    if not w then
        local title=kind=="guild" and B:T("window.guild") or string.format(B:T("window.bank"),A.PlayerName() or "")
        w=V:NewWindow(id,title)
        w.liveBank=kind
        if kind=="bank" then SetupPersonalBank(w) else SetupGuildBank(w) end
    end
    w.page=kind=="guild" and A.CurrentGuildTab() or nil
    if kind=="guild" then
        w.guildMode="items"
        w.cachedGuildPages={}
        local info=w.page and A.GuildTab(w.page)
        if not info or not info.view then w.page=nil end
        local guild=A.GuildIdentity()
        local title=B:T("window.guild")
        if guild and guild.name and guild.name~="" then
            local name=guild.name:gsub("|","||")
            if YUI.F and YUI.F.GetGradientText then name=YUI.F:GetGradientText(name,legendaryOrange,legendaryGold) end
            title=name.." · "..title
        end
        w.title:SetText(title)
    end
    w.query="";w.search:SetText("");w.scroll:SetVerticalScroll(0)
    w.open=true;w.root:Show()
    V:ApplySkin(true)
    V:Layout(w,true)
    return true
end

function W:Refresh(kind,rebuild)
    local w=V.windows["live-"..kind]
    if not w or not w.open or A.InCombat() or not SessionOpen(kind) then return end
    local current=kind=="guild" and A.CurrentGuildTab()
    if current and w.page and w.page~=current then
        B.GuildServices:ClearTabTooltip(w)
        self:CancelGuildSplit()
        B.GuildInventory:Clear(w)
        w.page=current
        w.scroll:SetVerticalScroll(0)
    end
    V:Layout(w,rebuild or kind=="guild")
end

function W:Close(kind)
    if kind=="bank" then self:DropBagDrag() end
    A.RestoreBankWindow(kind)
    local w=V.windows["live-"..kind]
    if w and w.open then w.root:Hide() end
end

function W:WindowHidden(kind)
    if kind=="bank" then
        local w=V.windows["live-bank"]
        if w then SetSocketHover(w,nil) end
        self:DropBagDrag()
    end
    if A.RestoreBankWindow(kind) then A.CloseBankWindow(kind) end
end

local function CanWithdraw(info)
    return info.remaining==-1 or (info.remaining or 0)>0
end

function W:ReadGuildAction(binding)
    if not binding or A.InCombat() or not SessionOpen("guild") or B.Actions.queue or B.Actions.nativeSort then return end
    local w,item=binding.window,binding.item
    local tab=w.page
    if not w.open or not tab or tab~=item.bag or item.guildCached or B.Deposit.guildRequests[tab]
        or A.CurrentGuildTab()~=tab or not B.Deposit.knownTabs[tab] then return end
    if not B.Deposit:GetGuildPage(tab) then return end
    local info=A.GuildTab(tab)
    if not info or not info.view then return end
    local current,err=B.Deposit:ReadGuildActionSlot(tab,item.slot)
    if err or (current==nil)~= (item.empty==true) then return end
    if current and (current.locked or current.link~=item.link or current.count~=item.count) then return end
    return info,current
end

local function SameSplitItem(split,item)
    return item and not item.empty and not item.locked
        and split.bag==item.bag and split.slot==item.slot and split.link==item.link and split.count==item.count
end

function W:DismissStackSplit(button)
    if button and StackSplitFrame and StackSplitFrame.owner==button and StackSplitFrame:IsShown() then StackSplitFrame:Hide() end
end

function W:CancelGuildSplit(button,item)
    local split=self.guildSplit
    if not split or button and split.button~=button or SameSplitItem(split,item) then return end
    self.guildSplit=nil
    self:DismissStackSplit(split.button)
end

function W:SubmitGuildSplit(button,count)
    local split=self.guildSplit
    if not split or split.button~=button then return end
    self.guildSplit=nil
    if not StackSplitFrame or StackSplitFrame.owner~=button or not button:IsVisible() or A.CursorBusy() then return end
    local info,current=self:ReadGuildAction(V.buttonData[button])
    if info and CanWithdraw(info) and SameSplitItem(split,current)
        and type(count)=="number" and count==math.floor(count) and count>=1 and count<current.count then
        return A.SplitGuildItem(current.bag,current.slot,count)
    end
end

function W:GuildClick(button,mouse,drag)
    local binding=V.buttonData[button]
    if not binding then return end
    local w,item=binding.window,binding.item
    local busy=A.CursorBusy()
    if w.guildMode~="items" then return end
    local actions=B.Actions
    local receipt=actions.waiting
    if receipt and receipt.guildManual then
        local target=receipt.operation.target
        if mouse=="LeftButton" and not drag and busy and w.open and w.page==target.bag
            and item.bag==target.bag and item.slot==target.slot and not item.guildCached and not item.guildManual
            and not IsShiftKeyDown() and not IsAltKeyDown() and not (IsControlKeyDown and IsControlKeyDown()) then
            actions:PlaceWaitingGuildStack(target.bag,target.slot)
        end
        return
    end
    if not w.page then
        if not drag and not busy and not item.empty and (mouse=="LeftButton" or mouse=="RightButton") then
            B.GuildInventory:Click(w,item,button)
        end
        return
    end
    if item.guildManual then
        if busy and mouse~="RightButton" and w.page==item.bag and not B.Deposit:DropGuildSlot(item.bag,item.slot) then
            B:Notify(B.Deposit:GuildPermission(w.page) and "bank.guild_wait" or "bank.guild_deposit_denied")
        end
        return
    end
    -- A visible slot update can precede the source-bag event. Reconcile the
    -- final deposit on this click before applying the usual withdrawal checks.
    if mouse=="RightButton" and not drag and not busy and not item.empty and receipt and receipt.guildReceipt then
        local target=receipt.operation.target
        local result=actions.transferResult
        if not result or not actions.queue or actions.index~=#actions.queue or w.page~=target.bag
            or item.slot~=target.slot or item.itemID~=receipt.source.itemID or item.count~=receipt.expectedTarget then return end
        local shownLink=item.link
        actions:Confirm()
        if actions.queue or result.confirmed~=result.total then return end
        binding=V.buttonData[button]
        item=binding and binding.item
        if not binding or binding.window~=w or not w.open or w.guildMode~="items" or w.page~=target.bag
            or not item or item.bag~=target.bag or item.slot~=target.slot
            or item.link~=shownLink or item.count~=receipt.expectedTarget or A.CursorBusy() then return end
    end
    local info,current=self:ReadGuildAction(binding)
    if not info then return end
    local canTake=CanWithdraw(info)
    if not drag and not busy and current and A.HandleModifiedClick(current.link) then return end
    if not drag and type(IsModifiedClick)=="function" and IsModifiedClick("SPLITSTACK") then
        if not busy and canTake and current and current.count>1 and type(SplitGuildBankItem)=="function"
            and StackSplitFrame and StackSplitFrame.OpenStackSplitFrame then
            self.guildSplit={button=button,bag=current.bag,slot=current.slot,link=current.link,count=current.count}
            StackSplitFrame:OpenStackSplitFrame(current.count,button,"BOTTOMLEFT","TOPLEFT")
        end
        return
    end
    if busy then
        if mouse=="RightButton" then return end
        if not info.deposit then B:Notify("bank.guild_deposit_denied");return end
        local cursor=A.CursorItem()
        if not cursor then return end
        if current and not canTake then
            local merges=cursor.itemID==current.itemID and cursor.link==current.link and current.count<current.maxStack
            if not merges then return end
        end
        return A.GuildItemAction(w.page,item.slot,false)
    end
    if current and canTake then return B.Deposit:WithdrawGuildItem(current,mouse=="RightButton") end
end

function W:SetupGuildCell(button)
    button:RegisterForClicks("LeftButtonUp","RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick",function(owner,mouse) self:GuildClick(owner,mouse) end)
    button:SetScript("OnDragStart",function(owner) if not A.CursorBusy() then self:GuildClick(owner,nil,true) end end)
    button:SetScript("OnReceiveDrag",function(owner) if A.CursorBusy() then self:GuildClick(owner,nil,true) end end)
    button.SplitStack=function(owner,count) return self:SubmitGuildSplit(owner,count) end
    button:HookScript("OnHide",function(owner) self:CancelGuildSplit(owner) end)
    button:SetScript("OnEnter",function(owner)
        local binding=V.buttonData[owner]
        if not binding or V:ItemTooltipBlocked() then return end
        B.GuildInventory:Enter(binding.window,owner,binding.item)
        if V:EmptyTooltip(owner,binding.item) then return end
        B.GuildInventory:Tooltip(binding.window,binding.item,owner)
    end)
    button.UpdateTooltip=function(owner)
        local binding=V.buttonData[owner]
        if binding and not binding.item.empty and not V:ItemTooltipBlocked() then
            B.GuildInventory:Tooltip(binding.window,binding.item,owner,true)
        end
    end
end
