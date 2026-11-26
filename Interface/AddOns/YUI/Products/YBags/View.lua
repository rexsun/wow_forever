local YUI = _G.YUI
local B = YUI and YUI.YBags
if not B then return end
local G,A,S=YUI.GUI2,YUI.API.Bags,YUI.API.Security
local V={windows={},windowOrder={},buttonData=setmetatable({}, {__mode="k"}),itemInputs=setmetatable({}, {__mode="k"}),
    itemBindings=setmetatable({}, {__mode="k"}),
    equippedLevels={},waitingEquipment={},equipmentRevision=0}
local nativeSlotLocks=setmetatable({}, {__mode="k"})
B.View=V
V.currencyLeftInset=2
local windowBase,windowStride=20,20
local function CancelTransferLayout(w)
    if w.transferLayoutTimer then
        w.transferLayoutTimer:Cancel()
        w.transferLayoutTimer=nil
        B.Stats.timers=B.Stats.timers-1
    end
    w.nextTransferLayout=nil
    w.transferButtons,w.transferChanges=nil,nil
end
local function WindowMouseDown()
    for n=#V.windowOrder,1,-1 do
        local w=V.windowOrder[n]
        if w.open and w.root:IsShown() and (w.root:IsMouseOver()
            or (w.liveBank=="guild" and B.GuildServices:IsMouseOverNavigation(w))) then
            V:FocusWindow(w)
            return
        end
    end
end
function V:FocusWindow(w)
    if A.InCombat() then return end
    if self.windowOrder[#self.windowOrder]==w then return end
    for n=#self.windowOrder,1,-1 do if self.windowOrder[n]==w then table.remove(self.windowOrder,n);break end end
    self.windowOrder[#self.windowOrder+1]=w
    local level=windowBase
    for _,window in ipairs(self.windowOrder) do
        if S.SafeNumber(window.root:GetFrameLevel())~=level then window.root:SetFrameLevel(level) end
        local highest=S.SafeNumber(window.root:GetHighestFrameLevel(true))
        level=math.max(level+windowStride,(highest or level)+3)
    end
    if not self.focusListening then
        YUI.Event:On("GLOBAL_MOUSE_DOWN",WindowMouseDown,self);self.focusListening=true;B.Stats.listeners=B.Stats.listeners+1
    end
end
function V:ForgetWindow(w)
    for n=#self.windowOrder,1,-1 do if self.windowOrder[n]==w then table.remove(self.windowOrder,n);break end end
    if #self.windowOrder==0 and self.focusListening then
        YUI.Event:OffOwner(self);self.focusListening=nil;B.Stats.listeners=math.max(0,B.Stats.listeners-1)
    end
end
local icons={offline=134400,bag=133633,key=134237,sort=655994,
    category=134327,single=133633,close=130775,delete=130775,add=132599,enchant=132853}
local atlases={sort="bags-button-autosort-up"}
local sortSpaceColorKey,sortSpaceColor="color.ybags.sortSpace",{.69,.90,.74,1}
local function Texture(parent,asset,width,height)
    local t=G:CreateTexture(parent,nil,"ARTWORK");t:SetTexture(asset);t:SetSize(width,height);return t
end
local function Label(parent,text,size,color)
    local label=G:CreateText(parent,text,size or 12,color or "color.text.primary")
    label:SetJustifyH("LEFT")
    return label
end
local function Tooltip(button,text)
    GameTooltip:SetOwner(button,"ANCHOR_RIGHT");GameTooltip:SetText(text);GameTooltip:Show()
end
local function PrepareRecentClearHint(button,title)
    local hint=Label(button,B:T("action.clear_recent_hint"),12,"color.state.success")
    B.Appearance:Text(hint,"heading")
    hint:SetPoint("LEFT",title,"LEFT")
    hint:SetAlpha(0)
    button.recentClearHint=hint
    local hovered=false
    local function ShowHint(shown)
        if hovered==shown then return end
        hovered=shown
        title:SetAlpha(shown and 0 or 1)
        hint:SetAlpha(shown and 1 or 0)
    end
    local function ResetHint() ShowHint(false) end
    button:SetScript("OnEnter",function() ShowHint(true) end)
    button:SetScript("OnLeave",ResetHint)
    button:SetScript("OnHide",ResetHint)
    local parent=button:GetParent()
    local onHide=parent:GetScript("OnHide")
    parent:SetScript("OnHide",function(owner)
        ResetHint()
        if onHide then onHide(owner) end
    end)
end
local function Icon(parent,id,label,callback,atlas,command,size)
    local button=id=="close" and G:CreateButtonFrame(parent,{width=22,height=22,frameLevel=parent:GetFrameLevel()+1,template="UIPanelCloseButton"})
        or B.Appearance:Icon(parent,{asset=icons[id],atlas=atlas or atlases[id],
            iconSize=id=="sort" and 28 or size,pressedAtlas=id=="sort" and "bags-button-autosort-down" or nil,
            playerPortrait=id=="offline" and not atlas,command=command})
    button:SetScript("OnClick",function() B.Actions:CancelDelete();callback(button) end)
    button:SetScript("OnEnter",function() Tooltip(button,B:T(label)) end)
    local function HideTooltip() GameTooltip:Hide() end
    if id=="sort" or command=="toolbar" then button:HookScript("OnLeave",HideTooltip)
    else button:SetScript("OnLeave",HideTooltip) end
    return button
end
local function ShowSortTooltip(w)
    GameTooltip:SetOwner(w.sort,"ANCHOR_RIGHT")
    GameTooltip:SetText(B:T("action.sort"))
    GameTooltip:AddLine(B:T("action.sort_space_help"),1,1,1,true)
    if w.sortSpace then
        local r,g,b=G:GetColor(sortSpaceColorKey,sortSpaceColor)
        GameTooltip:AddLine(string.format(B:T("action.sort_space_estimate"),w.sortSpace),r,g,b)
    end
    GameTooltip:Show()
end
function V:SetSortSpace(count)
    local w=self.windows.player
    if not w or not w.sortSpaceLabel then return end
    count=S.SafeNumber(count)
    count=count and count>=1 and math.floor(count) or nil
    if w.sortSpace==count then return end
    w.sortSpace=count
    w.sortSpaceLabel:SetText(count and string.format("+%d",count) or "")
    w.sortSpaceLabel:SetShown(count~=nil)
    if w.open and w.sort:IsMouseOver() and GameTooltip:IsOwned(w.sort) then ShowSortTooltip(w) end
end
local function RestoreCombinedPool(w)
    local slots=w.combinedSlots
    if not slots or not slots.normalPool then return end
    for _,button in ipairs(w.pool) do button:Hide() end
    w.pool,slots.normalPool=slots.normalPool,nil
end

function V:ClearWindow(w)
    B.Appearance:SetTradeSweep(w)
    B.Appearance:SetRecentSweep(w)
    RestoreCombinedPool(w)
    local combined=w.combinedSlots
    if combined then
        for _,button in pairs(combined.spares) do
            button:Hide();self.buttonData[button]=nil;nativeSlotLocks[button]=nil
        end
        combined.items,combined.nodes,combined.bySlot=nil,nil,nil
        combined.drawn={}
    end
    if w.combatLoot then
        self:HideCombatLoot(w)
        for _,button in pairs(w.combatLoot.bySlot) do self.buttonData[button]=nil;nativeSlotLocks[button]=nil end
        w.combatLoot.prepared={}
    end
    w.combatLootItems,w.combatLootNodes=nil,nil
    w.nodes={};w.items=nil;w.projectedLive=nil;w.cols=0;w.prepared=false;w.pendingGrouping=nil
    if not B.active then w.splitPlacements,w.splitAnchors,w.splitSequence={},{},0 end
    for _,pool in ipairs({w.pool,w.cachePool,w.labels,w.alternates}) do
        for _,button in ipairs(pool) do
            button:Hide();self.buttonData[button]=nil
            if nativeSlotLocks[button] then nativeSlotLocks[button]=nil end
        end
    end
end
function V:RegisterEscape(frame)
    if frame.ybagsEscapeName then return end
    -- Keep addon windows in the native post-casting close path. Registering
    -- a Lua ESC handler re-sorts the shared secure handler array in addon context.
    frame:EnableKeyboard(false)
    self.escapeIndex=(self.escapeIndex or 0)+1
    local name="YUIBagsEscape"..self.escapeIndex
    frame.ybagsEscapeName=name;_G[name]=frame
    UISpecialFrames[#UISpecialFrames+1]=name
end
-- A special popup claims native ESC before CloseAllWindows closes the bank.
-- Keep the non-interactive frame out of the layout of visible dialog boxes.
function V:SetGuildTransferEscape(active)
    if not StaticPopupSpecial_Show or not StaticPopupSpecial_Hide then return end
    local frame=self.guildTransferEscape
    if active then
        if not frame then
            frame=G:CreateFrame(UIParent,{width=1,height=1,hidden=true,mouse=false})
            frame.hideOnEscape=true
            frame.dialogInfo={AnchorDialogFrame=function(owner) owner:SetPoint("CENTER",UIParent) end}
            frame:SetScript("OnHide",function() B.Actions:InterruptGuildTransfer() end)
            self.guildTransferEscape=frame
        end
        StaticPopupSpecial_Show(frame)
    elseif frame and frame:IsShown() then
        StaticPopupSpecial_Hide(frame)
    end
end
local guildScrollGutter=12

local function SyncGuildScrollBar(w)
    local visible=math.max(1,math.floor(w.scroll:GetHeight()))
    local overflow=math.max(0,math.ceil(w.totalHeight-w.scroll:GetHeight()))
    w.guildScrollBar:SetScrollState(1+math.ceil(w.scroll:GetVerticalScroll()),visible+overflow,visible,true)
end

local function LayoutGuildScrollBar(w,height,visible)
    if w.guildMode~="items" or w.page or height<=visible then
        if w.guildScrollBar then w.guildScrollBar:Hide() end
        return
    end
    if not w.guildScrollBar then
        local bar=G:CreateVirtualScrollBar(w.root,{width=guildScrollGutter-2,onFirstIndexChanged=function(first)
            if A.InCombat() then SyncGuildScrollBar(w);return end
            B.Actions:CancelDelete()
            w.scroll:SetVerticalScroll(math.min(first-1,w.totalHeight-w.scroll:GetHeight()))
            V:Paint(w)
        end})
        bar:SetPoint("TOPLEFT",w.scroll,"TOPRIGHT",2,0)
        bar:SetScript("OnMouseWheel",w.scroll:GetScript("OnMouseWheel"))
        w.guildScrollBar=bar
    end
    w.guildScrollBar:SetHeight(visible)
    SyncGuildScrollBar(w)
end

function V:NewWindow(id,title)
    local config=B:GetConfig()
    local root=G:CreateFrame(UIParent,{name=id=="player" and "YUIBagsWindow" or nil,width=534,height=500,hidden=true,mouse=true,movable=true})
    root:SetFrameStrata("HIGH");root:SetFrameLevel(windowBase);root:SetClampedToScreen(true)
    root:SetPoint("CENTER",UIParent,"CENTER",id=="player" and 250 or -260,0)
    local positionKey=(id=="player" or id=="keyring" or id=="live-bank" or id=="live-guild") and id or "cache"
    local w={id=id,root=root,pool={},cachePool={},labels={},nodes={},query="",collapsed=id=="player" and config.collapsed or {},cols=0,provider={},positionKey=positionKey}
    if id=="player" then w.alternates={} end
    w.provider.IsCombinedBagContainer=function() return false end
    self.windows[id]=w
    w.header=G:CreateFrame(root,{width=534,height=20})
    w.title=Label(w.header,title,14,"color.text.heading");w.title:SetPoint("CENTER");w.title:SetJustifyH("CENTER")
    w.drag=G:CreateFrame(w.header,{width=260,height=20,mouse=true});w.drag:SetPoint("CENTER");w.drag:RegisterForDrag("LeftButton")
    w.drag:SetScript("OnDragStart",function() self:FocusWindow(w);B.Actions:CancelDelete();root:StartMoving() end)
    w.drag:SetScript("OnDragStop",function()
        root:StopMovingOrSizing()
        local point,_,relative,x,y=root:GetPoint()
        B:GetConfig().position[positionKey]={point=point,relative=relative,x=x,y=y}
    end)
    local position=config.position[positionKey]
    if position and type(position.point)=="string" and type(position.x)=="number" and type(position.y)=="number" then
        root:ClearAllPoints();root:SetPoint(position.point,UIParent,position.relative or position.point,position.x,position.y)
    end
    w.close=Icon(w.header,"close","action.close",function() root:Hide() end);w.close:SetPoint("RIGHT",-8,0)
    if id=="player" or id=="live-bank" or id=="live-guild" then
        w.nativeClose=w.close
        w.minimalClose=G:CreateCloseButton(w.header,w.close:GetScript("OnClick"))
        w.minimalClose:SetFrameLevel(w.header:GetFrameLevel()+1)
        w.minimalClose:RegisterForClicks("LeftButtonUp")
        w.minimalClose:HookScript("OnEnter",function(button) Tooltip(button,B:T("action.close")) end)
        w.minimalClose:HookScript("OnLeave",function() GameTooltip:Hide() end)
        w.minimalClose:Hide()
    end
    w.settings=B.Appearance:SettingsButton(w.header,function(owner,mouse)
        B.Actions:CancelDelete()
        local kind=w.liveBank or w.kind
        if kind=="guild" and mouse=="RightButton" and self:CanQuickGuildDeposit(w) then
            return self:DepositMenu(owner,"guild",w.page)
        end
        if kind=="guild" then return B:OpenSettings("guild") end
        if kind=="bank" then return B:OpenSettings("bank","personal") end
        if kind=="shared" then return B:OpenSettings("bank","shared") end
        return B:OpenSettings("bags","layout")
    end)
    w.settings:SetPoint("RIGHT",w.close,"LEFT",-1,0)
    w.capacity=Label(root,"",12);w.capacity:SetPoint("TOPLEFT",10,-43)
    local personalBank=id=="live-bank"
    w.sort=Icon(root,"sort",personalBank and "action.sort_bank" or "action.sort",function()
        if personalBank then B.Actions:SortBank() else B.Actions:Sort() end
    end)
    w.sort:SetPoint("TOPRIGHT",-8,-35)
    w.sort:SetSize(32,32)
    if YUI.IsForever and id=="player" then
        w.sortSpaceLabel=G:CreateText(w.sort,"",10,sortSpaceColorKey,"CENTER")
        G:SetTextColorKey(w.sortSpaceLabel,sortSpaceColorKey,sortSpaceColor)
        w.sortSpaceLabel:SetPoint("BOTTOM",w.sort,"BOTTOM",0,-3)
        w.sortSpaceLabel:Hide()
        w.sort:SetScript("OnEnter",function() ShowSortTooltip(w) end)
    end
    w.search=B.Appearance:Edit(root,{width=150,placeholder=B:T("action.search")});w.search:SetPoint("RIGHT",w.sort,"LEFT",-7,0)
    w.search:SetScript("OnTextChanged",function(edit,user)
        if edit.placeholder then edit.placeholder:SetShown(edit:GetText()=="") end
        if user then w.query=edit:GetText();if w.liveBank then self:Layout(w,true) else self:Paint(w) end end
    end)
    w.search:SetScript("OnEscapePressed",function(edit)
        if B.Actions:InterruptGuildTransfer() then edit:ClearFocus();return end
        edit:SetText("");w.query="";edit:ClearFocus()
        if w.liveBank then self:Layout(w,true) else self:Paint(w) end
    end)
    w.scroll=G:CreateFrame(root,{type="ScrollFrame",width=510,height=380,mouseWheel=true})
    w.scroll:SetPoint("TOPLEFT",10,-71)
    w.content=G:CreateFrame(w.scroll,{width=510,height=380});w.scroll:SetScrollChild(w.content)
    -- Retail's native item template asks its parent whether to draw combined bag slot art.
    if YUI.IsRetail then w.content.IsCombinedBagContainer=w.provider.IsCombinedBagContainer end
    w.scroll:SetScript("OnMouseWheel",function(_,delta)
        if A.InCombat() then return end
        local frame=w.scroll
        B.Actions:CancelDelete()
        frame:SetVerticalScroll(math.max(0,math.min(frame:GetVerticalScroll()-delta*82,math.max(0,(w.totalHeight or 0)-frame:GetHeight()))))
        if w.guildScrollBar and w.guildScrollBar:IsShown() then SyncGuildScrollBar(w) end
        self:Paint(w)
    end)
    w.money=Label(root,"",12);w.money:SetPoint("BOTTOMRIGHT",-10,10)
    if id=="player" then
        w.moneyHit=G:CreateButtonFrame(root,{height=20,width=100})
        w.moneyHit:SetPoint("CENTER",w.money,"CENTER")
        w.moneyHit:SetScript("OnEnter",function(owner) B.Currency:MoneyTooltip(owner) end)
        w.moneyHit:SetScript("OnLeave",function() GameTooltip:Hide() end)
        w.moneyHit:RegisterForClicks("RightButtonUp")
        w.moneyHit:SetScript("OnClick",function(owner,mouse) if mouse=="RightButton" then self:CurrencyMenu(owner) end end)
    end
    w.currencyHost=G:CreateFrame(root,{width=350,height=24})
    if id=="player" then w.currencyHost:SetPoint("TOPLEFT",w.scroll,"BOTTOMLEFT",V.currencyLeftInset,-1)
    else w.currencyHost:SetPoint("BOTTOMLEFT",10,7) end
    w.currencyButtons={}
    root:SetScript("OnHide",function()
        if w.id=="player" or w.liveBank then B.BankView:ClearPresetPreview() end
        if w.id=="player" then self:HideHelp(w) end
        if w.combatLoot then self:HideCombatLoot(w);w.combatLoot.revision=nil end
        if w.capacityEquipmentChanged then
            YUI.Event:OffOwner(w.capacity)
            B.Stats.listeners=math.max(0,B.Stats.listeners-1)
            w.capacitySockets=nil
        end
        B.Appearance:SetTradeSweep(w)
        B.Appearance:SetRecentSweep(w)
        self:ForgetWindow(w)
        CancelTransferLayout(w)
        w.open,w.autoOpenedBy=false,nil
        if w.sortSpaceLabel and B.SortSpaceVisibility then B:SortSpaceVisibility(false) end
        if w.liveBank=="bank" and B.Actions:IsPersonalBatch() then
            B.Actions:Stop()
        elseif w.liveBank=="guild" then
            B.Actions:InterruptGuildTransfer()
            B.BankView:CancelGuildSplit()
            B.GuildInventory:Clear(w)
            B.GuildServices:Close(w)
            w.cachedGuildPages=nil
        end
        if w.liveBank=="bank" and StackSplitFrame then
            local owner=StackSplitFrame.owner
            local data=owner and self.buttonData[owner]
            if data and data.window==w then B.BankView:DismissStackSplit(owner) end
        end
        local sortRound=B.Actions.sortRound
        if sortRound and (sortRound.bank and w.liveBank=="bank" or not sortRound.bank and w.id=="player") then
            B.Actions:Stop()
        elseif w.id=="player" and (B.Actions.kind=="split" or B.Actions.kind=="split-groups" or B.Actions.kind=="extract" or B.Actions.kind=="bag-remove") then B.Actions:Stop() end
        B.Actions:CancelDelete()
        GameTooltip:Hide()
        w.pinnedSlots,w.splitAnchors,w.expandedItems={},{},{}
        w.reflowStacks,w.dragSource,w.dragBag,w.hoverBag=nil,nil,nil,nil
        if w.id=="player" and B.active then
            -- Keep confirmed independent stacks. Pending placements only
            -- describe where a split was expected to land in this view.
            if w.splitPlacements then
                for key,placement in pairs(w.splitPlacements) do
                    if not placement.stackKey then w.splitPlacements[key]=nil end
                end
            end
        else
            w.splitPlacements,w.splitSequence={},0
        end
        if w.id~="player" or not B.active or not w.prepared then self:ClearWindow(w) end
        for _,button in ipairs(w.bagButtons or {}) do button:UnlockHighlight() end
        if self.menu then self.menu:Hide() end
        if self.directoryPanel then self.directoryPanel:Hide() end
        if self.split then self.split:Hide() end
        if w.liveBank then B.BankView:WindowHidden(w.liveBank) end
        if w.liveBank=="guild" then self:RefreshGuildBagRoute() end
    end)
    root:SetScript("OnShow",function()
        if w.sortSpaceLabel and B.SortSpaceVisibility then B:SortSpaceVisibility(true) end
        if w.capacityEquipmentChanged then
            w.capacitySockets=nil
            YUI.Event:On("BAG_CONTAINER_UPDATE",w.capacityEquipmentChanged,w.capacity)
            B.Stats.listeners=B.Stats.listeners+1
        end
        self:FocusWindow(w)
        if w.liveBank=="guild" then self:RefreshGuildBagRoute() end
    end)
    self:RegisterEscape(root)
    G.WindowAppearance:Register(root,{themeProvider=function() return B:GetConfig().skin=="native" and "native" or "dark" end,
        heading=w.title,role="helper",noTopBar=true,nativeBorderOverflow=true})
    return w
end
local function ToggleCarryBagBar(w)
    w.showBags=not w.showBags
    V:RenderBagBar(w)
    V:Layout(w,true)
end
function V:EnsurePlayer()
    if self.windows.player then return self.windows.player end
    local w=self:NewWindow("player",string.format(B:T("window.bags"),A.PlayerName() or ""))
    self:CreateHelp(w)
    w.toolbarHost=YUI.IsForever and w.root or w.header
    local function Tool(parent,id,label,callback,atlas)
        local size=YUI.IsForever and parent==w.header and 16 or nil
        return Icon(parent,id,label,callback,atlas,YUI.IsForever and "toolbar",size)
    end
    local raceAtlas=A.CharacterAppearance(B.Cache.player or A.CharacterInfo())
    w.directory=Tool(w.header,"offline","action.offline",function(button) self:Directory(button) end,raceAtlas)
    w.bags=Tool(w.header,"bag","action.bagbar",function() ToggleCarryBagBar(w) end)
    -- An equal-size replacement may leave the physical slot model unchanged.
    w.capacityEquipmentChanged=function()
        w.capacitySockets=nil
        if w.open and not A.InCombat() then self:RenderCapacity(w) end
    end
    w.keys=Tool(w.header,"key","action.keyring",function() self:ToggleKeyring() end)
    w.assistant=Tool(w.toolbarHost,"enchant","action.enchant",function()
        local feature=YUI.ProfessionAssistant
        if feature and feature.Open then feature:Open() end
    end)
    w.assistant:SetShown(YUI.IsForever==true)
    w.keys:SetShown(KEYRING_CONTAINER~=nil and B.Model.bags[KEYRING_CONTAINER]~=nil)
    return w
end
function V:ApplySkin(skipLayout)
    B.Appearance:Refresh()
    for _,w in pairs(self.windows) do
        G.WindowAppearance:Refresh(w.root);w.root:SetAlpha(B:GetConfig().opacity)
        if w.open and not skipLayout then self:Layout(w,false) end
        if w.guildInventory then B.GuildInventory:RefreshHighlights(w) end
    end
    if self.menu then G.WindowAppearance:Refresh(self.menu) end
    if self.directoryPanel then self:RenderDirectory();G.WindowAppearance:Refresh(self.directoryPanel) end
    if self.dialog then G.WindowAppearance:Refresh(self.dialog) end
    if self.split then G.WindowAppearance:Refresh(self.split);if self.split.identity then self:PreviewSplit() end end
end
function V:LoadProfile()
    if A.InCombat() then self.pendingProfile=true;return end
    self.pendingProfile=nil
    local config=B:GetConfig()
    for _,w in pairs(self.windows) do
        w.layout=nil;w.collapsed=w.id=="player" and config.collapsed or {};w.nodes={};w.cols=0
        local position=config.position[w.positionKey]
        w.root:ClearAllPoints()
        if position then w.root:SetPoint(position.point,UIParent,position.relative,position.x,position.y)
        elseif w.id=="keyring" and self.windows.player then w.root:SetPoint("TOPRIGHT",self.windows.player.root,"TOPLEFT",-8,0)
        else w.root:SetPoint("CENTER",UIParent,"CENTER",w.id=="player" and 250 or -260,0) end
    end
    self:ApplySkin()
end
function V:Invalidate(keepSplits)
    for _,w in pairs(self.windows) do
        w.nodes={};w.pinnedSlots={};w.expandedItems={};w.reflowStacks=nil;w.cols=0;w.layoutKey=nil;w.prepared=false
        if not keepSplits then w.splitPlacements,w.splitAnchors={},{} end
    end
    B.Actions:CancelDelete()
end
function V:ResetSortLayout(bank,keepSplits)
    local w=self.windows[bank and "live-bank" or "player"]
    if not w then return end
    local resetSplits=not keepSplits and (next(w.splitPlacements or {}) or next(w.splitAnchors or {}))
    local changed=w.keptSortPositions or next(w.pinnedSlots or {}) or next(w.expandedItems or {}) or resetSplits
    if changed then
        w.pinnedSlots,w.expandedItems={},{}
        if resetSplits then w.splitPlacements,w.splitAnchors={},{} end
        w.reflowStacks,w.keptSortPositions=nil,nil
        w.reflow=true
        if not w.open then w.prepared=false end
        return w
    end
end
function V:FinishSortLayout(round)
    self:ResetSortLayout(round.bank)
    local w=self.windows[round.bank and "live-bank" or "player"]
    if w then w.reflow=true;w.prepared=false end
    if round.otherChanged then B:RefreshVisible(true);return end
    if w and w.open then self:Layout(w,true)
    elseif not round.bank then self:PreparePlayer() end
    for _,cached in pairs(self.windows) do
        if cached.open and cached.owner==B.Cache.playerKey and cached.owner
            and cached.kind==(round.bank and "bank" or "bags") then self:Layout(cached,true) end
    end
end
function V:Items(w)
    if w.liveBank then return B.BankView:Items(w)
    elseif w.id=="player" then
        local ids=A.GetCarryBags(false)
        return B.Model:List(ids)
    elseif w.id=="keyring" then return B.Model:List(KEYRING_CONTAINER and {KEYRING_CONTAINER} or {})
    else return B.Cache:GetItems(w.owner,w.kind) end
end
function V:PinSlot(target,item,window)
    local w=window or self.windows.player
    if not w or not w.open then return end
    w.pinnedSlots=w.pinnedSlots or {}
    w.pinnedSlots[tostring(target.bag)..":"..target.slot]={itemID=item.itemID,link=item.link}
end
function V:ExpandItem(item)
    local w=self.windows.player
    local key=B.Classification:StackKey(item)
    if not w or not key then return end
    w.expandedItems=w.expandedItems or {}
    if not w.expandedItems[key] then
        w.expandedItems[key]=true
        if w.open and not A.InCombat() then self:Layout(w,true) end
    end
end
function V:PlaceSplit(target,source,identity)
    local w=self.windows.player
    if not w then return end
    w.splitPlacements=w.splitPlacements or {}
    local key=tostring(source.bag)..":"..source.slot
    local parent=w.splitPlacements[key]
    identity=identity or source
    local root=parent and parent.source or key
    w.splitAnchors=w.splitAnchors or {}
    local anchor=w.splitAnchors[root]
    if not anchor then
        anchor={};w.splitAnchors[root]=anchor
        local previous,origin
        for _,node in ipairs(w.nodes) do
            local item=node.item
            if item and not item.empty and tostring(item.bag)..":"..item.slot==root then origin=item;break end
        end
        for _,node in ipairs(w.nodes) do
            local item=node.item
            if item and not item.empty and B.Classification:SameStack(item,origin) then
                if tostring(item.bag)..":"..item.slot==root then
                    if previous then anchor.before=tostring(previous.bag)..":"..previous.slot;anchor.guid=previous.guid end
                    break
                end
                previous=item
            end
        end
    end
    w.splitSequence=(w.splitSequence or 0)+1
    w.splitPlacements[tostring(target.bag)..":"..target.slot]={source=root,anchor=anchor,
        itemID=identity.itemID,link=identity.link,sourceGUID=parent and parent.sourceGUID or source.guid or identity.sourceGUID,order=w.splitSequence}
end
function V:ConfirmSplitPlacement(item)
    local w=self.windows.player
    local entry=w and w.splitPlacements and w.splitPlacements[tostring(item.bag)..":"..item.slot]
    if entry and entry.itemID==item.itemID and entry.link==item.link then entry.guid=entry.guid or item.guid end
end
function V:InteractionStacks(w)
    if w.id~="player" or (w.layout or B:GetConfig().layout)~="category" then return false end
    local runtime=B.Runtime
    if B.bankOpen or B.guildOpen or runtime.socketOpen or runtime.merchantOpen or runtime.tradeOpen
        or runtime.mailOpen or runtime.auctionOpen then return true end
    local context=A.Context()
    return context=="bank" and B.bankOpen==nil and B.guildOpen==nil or context=="merchant" and runtime.merchantOpen==nil
        or context=="trade" and runtime.tradeOpen==nil or context=="mail" and runtime.mailOpen==nil
        or runtime.auctionOpen==nil and A.StorageOpen("auctions")
end
function V:Grouping(w,physicalStacks)
    return not physicalStacks and not w.liveBank and w.id~="keyring" and (w.layout or B:GetConfig().layout)=="category" and B:GetConfig().aggregateItems~=false
end
function V:SeparateItems(selection,items)
    local w=self.windows.player
    if not w then return end
    w.splitPlacements=w.splitPlacements or {}
    if selection.stackKey then
        w.reflowStacks=w.reflowStacks or {};w.reflowStacks[selection.stackKey]=selection.members[1]
    end
    local source=selection.members[1]
    for _,item in ipairs(items) do
        local previous=w.splitPlacements[tostring(item.bag)..":"..item.slot]
        w.splitSequence=(w.splitSequence or 0)+1
        w.splitPlacements[tostring(item.bag)..":"..item.slot]={itemID=item.itemID,link=item.link,guid=item.guid,
            stackKey=selection.stackKey,source=tostring(source.bag)..":"..source.slot,anchor=previous and previous.anchor,order=w.splitSequence,count=item.count}
    end
end
function V:RememberCursor(button,item)
    local data=button and self.buttonData[button]
    item=item or data and data.item
    local w=self.windows.player
    if w and item and not item.empty and A.CursorBusy() then
        w.dragSource={bag=item.bag,slot=item.slot,itemID=item.itemID,link=item.link,guid=item.guid,
            stackKey=item.stackKey or B.Classification:StackKey(item)}
        local bag=B.Model.bags[item.bag]
        local source=bag and bag.slots[item.slot]
        B.Model.recentCursor=source and source.guid and source.itemID==item.itemID and source.link==item.link and source or nil
        self:RefreshItemInputs()
    end
end
function V:ReturnToGroup(button)
    local data=self.buttonData[button];local w=data and data.window
    local source=w and w.dragSource
    if not source or not data.item.members or B.Actions:IsVirtualChargeGroup(data.item) or A.InCombat() or B.Actions.queue then return false end
    local cursor=A.CursorItem()
    if not cursor or cursor.itemID~=source.itemID or source.stackKey~=data.item.stackKey
        or cursor.link and cursor.link~=source.link then return false end
    local current,err=A.Slot(source.bag,source.slot)
    if err or current and (data.item.maxStack==1 and not source.guid
        or not B.Classification:SameStack(current,data.item,data.item.ignoreDisplayBinding)
        or source.guid and current.guid~=source.guid) then return false end
    if A.Pickup(source.bag,source.slot) and not A.CursorBusy() then
        if w.splitPlacements then w.splitPlacements[tostring(source.bag)..":"..source.slot]=nil end
        w.dragSource=nil
        w.reflowStacks=w.reflowStacks or {};w.reflowStacks[source.stackKey]=data.item
        B:MarkBag(source.bag);self:Layout(w,false);return true
    end
    return false
end
local function CurrentSelectionSlot(key)
    local bag,slot=key:match("^(-?%d+):(%d+)$");bag=B.Model.bags[tonumber(bag)]
    return bag and bag.slots[tonumber(slot)]
end
function V:ReconcileSelections(w)
    if w.id~="player" or not w.splitPlacements or not next(w.splitPlacements) or A.InCombat() or A.CursorBusy()
        or B.Actions.queue or B.Stats.pendingRefresh then return nil end
    local dirty=false
    for key,entry in pairs(w.splitPlacements) do if entry.stackKey then
        local item=CurrentSelectionSlot(key)
        if not item or item.itemID~=entry.itemID or item.link~=entry.link or entry.guid and item.guid~=entry.guid
            or entry.count and entry.count~=item.count then dirty=true;break end
    end end
    if not dirty then return nil end
    local byGUID={}
    for _,id in ipairs(A.GetCarryBags(false)) do
        local bag=B.Model.bags[id]
        if bag then for _,item in pairs(bag.slots) do if item.guid then byGUID[item.guid]=item end end end
    end
    local result,missing,changed={},{},{}
    for key,entry in pairs(w.splitPlacements) do
        local item=entry.guid and byGUID[entry.guid] or not entry.guid and CurrentSelectionSlot(key)
        if item and item.itemID==entry.itemID and item.link==entry.link then
            local target=tostring(item.bag)..":"..item.slot
            if entry.stackKey and (target~=key or entry.count and entry.count~=item.count) then changed[entry.stackKey]=item end
            entry.count=item.count;result[target]=entry
        else
            local current=CurrentSelectionSlot(key)
            missing[#missing+1]={key=key,entry=entry,pending=current and not current.guid and current.itemID==entry.itemID and current.link==entry.link}
        end
    end
    -- An absent item may be offered in trade. Keep its identity until a related
    -- merge is observed, so cancelling trade can restore the independent icon.
    for _,value in ipairs(missing) do
        if not result[value.key] and (value.pending or not changed[value.entry.stackKey]) then result[value.key]=value.entry end
    end
    w.splitPlacements=result
    return next(changed) and changed or nil
end
function V:UpdateGrouping()
    local w=self.windows.player
    if not w or not w.open then return end
    local physicalStacks=self:InteractionStacks(w)
    if w.physicalStacks==physicalStacks and w.grouping==self:Grouping(w,physicalStacks) then w.pendingGrouping=nil;return end
    if A.InCombat() or A.CursorBusy() or B.Actions.queue then w.pendingGrouping=true;return end
    w.pendingGrouping=nil;self:Layout(w,false)
end
function V:DropEmpty(button)
    local data=self.buttonData[button]
    if not data or A.InCombat() or B.Actions.queue then return false end
    local bankDrag=B.BankView.bagDrag
    if not data.item.empty then
        if bankDrag then return B.BankView:DropBagDrag() end
        return false
    end
    local item=data.item
    local profession=YUI.IsForever and data.window.id=="player" and item.space and item.space:sub(1,7)=="family:"
    local cursor=A.CursorItem()
    if not cursor and not (profession and A.CursorKind()=="item") then
        return bankDrag and B.BankView:DropBagDrag() or false
    end
    local target={bag=item.bag,slot=item.slot}
    if item.aggregate then
        local ids=item.bagScoped and {item.bag} or data.window.liveBank=="bank" and A.BankBags("bank")
            or data.window.id=="keyring" and {KEYRING_CONTAINER} or A.GetCarryBags(false)
        -- The player chose this domain explicitly. Let the client validate the drop.
        local candidate=not profession and cursor or nil
        target=B.Actions:FreeSlot(candidate,ids,nil,item.space,bankDrag and bankDrag.bag or data.window.dragBag)
    end
    if bankDrag then return B.BankView:DropBagDrag(target) end
    if not target or target.bag==data.window.dragBag
        or not profession and not A.Fits(cursor,B.Model.bags[target.bag]) then return false end
    local occupied,err=A.Slot(target.bag,target.slot)
    if occupied or err then return false end
    local moving=data.window.dragSource
    local ok=A.Pickup(target.bag,target.slot)
    if ok and not A.CursorBusy() then
        local w=data.window
        if (w.layout or B:GetConfig().layout)=="category" then
            local source=moving
            local placements=w.splitPlacements
            if source and placements then
                local key=tostring(source.bag)..":"..source.slot
                local entry=placements[key]
                if entry then
                    placements[key]=nil
                    placements[tostring(target.bag)..":"..target.slot]=entry
                end
            end
            w.dragSource=nil;w.reflow=true
        elseif cursor then self:PinSlot(target,cursor,w) end
        B:MarkBag(target.bag);return true
    end
    return false
end
local capacityOrder={"normal","special","reagent"}
local capacityTitles={normal="capacity.normal",special="empty.special",reagent="empty.reagent"}
local capacityIconSize=14
local backpackIcon=DEFAULT_BACKPACK_TEXTURE or "Interface\\Buttons\\Button-Backpack-Up"
local capacityRecipe=G.IconSkins:Resolve({skinId="minimal-circle",skinOptions={
    ["minimal-circle"]={border="medium",shadow=true,zoom=.03},
}},B.PRODUCT_ID)

local function CapacityTooltip(button,force)
    local entry=button.entry
    local freeSlots=entry.total-entry.used
    local changed=force or freeSlots~=button.tooltipFree or entry.total~=button.tooltipTotal
    local rows=button.tooltipRows
    local count=0
    if entry.freeByBag then
        if not rows then rows={};button.tooltipRows=rows end
        local w=button.window
        if w.id=="player" and not w.capacitySockets then w.capacitySockets=A.BagSockets() end
        for _,socket in ipairs(w.capacitySockets or w.sockets) do
            local id=socket.bag
            local free=id and entry.freeByBag[id]
            local bag=free and B.Model.bags[id]
            if bag and B.Runtime.readable[id] and (w.id=="player" or socket.hasBag and socket:IsShown()) then
                local name=socket.link and socket.link:match("|h%[(.-)%]|h")
                if not name and socket.itemID then name=S.SafeString(YUI.API.Item.GetName(socket.itemID)) end
                count=count+1
                local row=rows[count]
                if not row then row={};rows[count]=row end
                local index=socket.index or id
                if row.index~=index or row.name~=name or row.free~=free or row.total~=bag.capacity then
                    row.index,row.name,row.free,row.total=index,name,free,bag.capacity
                    changed=true
                end
            end
        end
    end
    if not changed and count==button.tooltipCount then return end
    button.tooltipFree,button.tooltipTotal,button.tooltipCount=freeSlots,entry.total,count
    GameTooltip:SetOwner(button,"ANCHOR_TOP")
    GameTooltip:SetText(B:T(capacityTitles[button.kind]))
    local remaining=B:T("capacity.remaining")
    GameTooltip:AddLine(string.format(remaining,freeSlots,entry.total))
    for i=1,count do
        local row=rows[i]
        local label=("#%d  %s"):format(row.index,row.name and row.name~="" and row.name or B:T("empty.special"))
        GameTooltip:AddDoubleLine(label,string.format(remaining,row.free,row.total))
    end
    GameTooltip:Show()
end

local function CapacityButton(w,key)
    local button=G:CreateButtonFrame(w.root,{height=16})
    button.kind,button.window=key,w
    button.image=G:CreateIconSlot(button,{size=capacityIconSize,variant="bare",shape=capacityRecipe.shape,
        border=capacityRecipe.border,zoom=capacityRecipe.zoom,animate=false})
    button.image:EnableMouse(false)
    button.image:SetPoint("LEFT")
    button.image:SetIconBorderColor(capacityRecipe.borderColor)
    local shadow=G:CreateShapeShadow(button.image)
    G:ApplyShapeShadow(shadow,{enabled=true,shape=capacityRecipe.shape,color=capacityRecipe.shadowColor},
        {anchor=button.image,width=capacityIconSize,height=capacityIconSize,allowLayout=true})
    button.label=Label(button,"",12)
    button:SetScript("OnEnter",function(owner) CapacityTooltip(owner,true) end)
    local function HideTooltip(owner)
        if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
    end
    button:SetScript("OnLeave",HideTooltip)
    button:SetScript("OnHide",HideTooltip)
    if w.id=="player" then
        button:SetScript("OnClick",function()
            if not w.open or A.InCombat() then return end
            B.Actions:CancelDelete()
            ToggleCarryBagBar(w)
        end)
    else
        button:SetMouseClickEnabled(false)
        button:SetMouseMotionEnabled(true)
    end
    return button
end

local function PickCapacityIcon(stats,id,source)
    local bag=id and B.Model.bags[id]
    if not bag or bag.capacity<=0 or not source then return end
    local key=bag.space=="reagent" and "reagent" or (bag.space or "normal")=="normal" and "normal" or "special"
    local entry=stats[key]
    local size=key=="normal" and bag.capacity or 0
    if not entry.bag or size>entry.size or size==entry.size and id<entry.bag then
        entry.bag,entry.size,entry.icon=id,size,source
    end
end

function V:RenderCapacity(w)
    local stats=w.capacityStats
    if not stats then return end
    for _,key in ipairs(capacityOrder) do
        local entry=stats[key]
        entry.bag,entry.icon=nil,nil
    end
    if w.liveBank=="bank" then
        for _,socket in ipairs(w.sockets) do
            local icon=socket.socketArtwork
            if socket.hasBag and socket:IsShown() and icon~=134400 and icon~=0 and icon~=B.Appearance.bagSocketBackground then
                PickCapacityIcon(stats,socket.bag,icon)
            end
        end
        -- The built-in bank contributes slots but has no equipped bag artwork.
        if stats.normal.total>0 and not stats.normal.icon then stats.normal.icon=icons.bag end
    else
        PickCapacityIcon(stats,0,backpackIcon)
        w.capacitySockets=w.capacitySockets or A.BagSockets()
        for _,socket in ipairs(w.capacitySockets) do PickCapacityIcon(stats,socket.bag,socket.icon) end
    end
    w.capacityButtons=w.capacityButtons or {}
    local skin=B:GetConfig().skin
    local scale=w.root.GetEffectiveScale and w.root:GetEffectiveScale() or 1
    local owner=GameTooltip:GetOwner()
    local width=0
    for _,key in ipairs(capacityOrder) do
        local entry,button=stats[key],w.capacityButtons[key]
        if entry.total>0 then
            if not button then button=CapacityButton(w,key);w.capacityButtons[key]=button end
            button.entry=entry
            if entry.icon and button.image.ybagsIdentitySource~=entry.icon then
                B.Appearance:IdentityIcon(button.image,entry.icon,capacityRecipe.zoom)
            end
            local free=entry.total-entry.used
            local textChanged=button.freeSlots~=free
            if textChanged then
                button.freeSlots=free
                button.label:SetText(tostring(free))
            end
            local inset=entry.icon and capacityIconSize+2 or 0
            if button.labelInset~=inset then
                button.labelInset=inset
                button.image:SetShown(entry.icon~=nil)
                button.label:ClearAllPoints();button.label:SetPoint("LEFT",inset,0)
            end
            local styleChanged=button.capacitySkin~=skin or button.capacityScale~=scale
            if textChanged or styleChanged then
                button.capacitySkin,button.capacityScale=skin,scale
                button.labelWidth=math.ceil(button.label:GetStringWidth())
            end
            local buttonWidth=inset+button.labelWidth
            if button.capacityWidth~=buttonWidth then
                button.capacityWidth=buttonWidth
                button:SetWidth(buttonWidth)
            end
            if not button:IsShown() then button:Show() end
            width=width+buttonWidth+4
            if owner==button then CapacityTooltip(button,styleChanged) end
        elseif button and button:IsShown() then button:Hide() end
    end
    local budget=w.capacity:GetWidth()
    local wrap=width-4>budget
    local x,y=0,wrap and 8 or 0
    for _,key in ipairs(capacityOrder) do
        local button=w.capacityButtons[key]
        if stats[key].total>0 then
            if y>0 and x>0 and x+button.capacityWidth>budget then x,y=0,-8 end
            if button.capacityX~=x or button.capacityY~=y then
                button.capacityX,button.capacityY=x,y
                button:ClearAllPoints();button:SetPoint("LEFT",w.capacity,"LEFT",x,y)
            end
            x=x+button.capacityWidth+4
        end
    end
end

function V:CapacityText(w)
    local stats={normal={used=0,total=0},reagent={used=0,total=0},special={used=0,total=0}}
    if w.id=="player" or w.liveBank=="bank" then stats.special.freeByBag={} end
    for _,list in ipairs({w.items,w.empties}) do for _,item in ipairs(list) do
        local space=item.space or "normal"
        local key="special"
        if space=="normal" or w.id=="keyring" then key="normal" elseif space=="reagent" then key="reagent" end
        local entry=stats[key];entry.total=entry.total+1;if not item.empty then entry.used=entry.used+1 end
        if entry.freeByBag then
            local free=entry.freeByBag[item.bag] or 0
            entry.freeByBag[item.bag]=item.empty and free+1 or free
        end
    end end
    w.capacityStats=stats
    if w.id=="player" or w.liveBank=="bank" then return "" end
    local text=stats.normal.used.." / "..stats.normal.total.." "..B:T("unit.slots")
    for _,key in ipairs({"reagent","special"}) do
        local entry=stats[key]
        if entry.total>0 then text=text.."  |A:"..(key=="reagent" and "bags-icon-reagents" or "bags-icon-profession-goods")..":12:12|a "..entry.used.." / "..entry.total end
    end
    return text
end
-- A bank bag can report the destination before the source has settled.
-- Keep the previous displayed stack until the two-sided receipt is accepted.
local function ReceivedItem(item,waiting)
    if item and B.Actions.equipmentTransfer then
        waiting=B.Actions.equipmentTransfer.targets[item.key]
    end
    if not item or not waiting then return item end
    local op=waiting.operation
    if not op or not op.personalTransfer or item.bag~=op.target.bag or item.slot~=op.target.slot
        or item.itemID~=op.itemID or item.count==op.targetCount then return item end
    waiting.displayPending=true
    if op.targetCount==0 then return nil end
    if not waiting.displayStack then
        waiting.displayStack=B:Copy(item)
        waiting.displayStack.count=op.targetCount
    end
    return waiting.displayStack
end
local function BuildInventoryLayout(w,config,cols,force,reflow,grouping,transferLayout)
    local projection,emptyProjection={},{}
    local free=w.empties
    local waiting=YUI.IsForever and config.layout=="category" and (w.id=="player" or w.liveBank=="bank")
        and B.Actions:IsPersonalBatch() and (B.Actions.waiting or B.Actions.equipmentTransfer)
    w.pinnedSlots=w.pinnedSlots or {}
    for _,physical in ipairs(w.items) do
        local item=physical
        if waiting then item=ReceivedItem(physical,waiting) end
        if item then
            local pinned=w.pinnedSlots[item.key]
            if pinned and pinned.itemID==item.itemID and pinned.link==item.link then emptyProjection[#emptyProjection+1]=item
            else projection[#projection+1]=item end
        else
            -- Only the projection sees the pre-receipt vacancy. Keep the
            -- physical inventory and capacity counters on the real bag state.
            if free==w.empties then
                free={}
                for i,empty in ipairs(w.empties) do free[i]=empty end
            end
            local bag=B.Model.bags[physical.bag]
            free[#free+1]={empty=true,bag=physical.bag,slot=physical.slot,space=bag.space,family=bag.family}
        end
    end
    local live=B.Model.byUID
    if grouping then
        projection,live=B.Layout:Aggregate(projection,w.expandedItems,w.splitPlacements,w.id=="player")
        if not w.owner then setmetatable(live,{__index=B.Model.byUID}) end
    end
    w.projectedLive=live
    local previous=w.nodes
    local retainSlots=w.id=="player" or w.liveBank=="bank"
    local keepPositions=not force and config.layout=="category" and w.layoutKey==config.layout..":"..cols
    w.keptSortPositions=retainSlots and keepPositions or nil
    if keepPositions and retainSlots then
        local first=B.Actions.queue and B.Actions.queue[1]
        projection,free,previous=B.Layout:Retain(w.nodes,projection,free,live,
            YUI.IsForever and (transferLayout or first and first.personalTransfer))
        -- Containers change the bag topology; their removed icons are not useful
        -- retained drop targets. Return those reserved cells to the empty area.
        for _,item in ipairs(projection) do if item.held and (item.classID==1 or item.equipLoc=="INVTYPE_BAG") then
            reflow=reflow or {};reflow["container:"..tostring(item.uid)]=item
        end end
        if reflow then
            local retained={}
            for _,item in ipairs(projection) do
                local discard=false
                if item.held then for _,prototype in pairs(reflow) do
                    if B.Classification:SameStack(item,prototype,prototype.ignoreDisplayBinding) then discard=true;break end
                end end
                if discard then free[#free+1]={empty=true,bag=item.bag,slot=item.slot,family=item.family,space=item.space}
                else retained[#retained+1]=item end
            end
            projection=retained
        end
    end
    for _,item in ipairs(free) do emptyProjection[#emptyProjection+1]=item end
    table.sort(emptyProjection,function(a,b) return a.bag==b.bag and a.slot<b.slot or a.bag<b.bag end)
    local nodes,height=B.Layout:Build(projection,emptyProjection,config,cols,w.collapsed,w.query)
    if keepPositions and not reflow and (retainSlots or w.id=="keyring") and #w.nodes>0 then
        nodes=B.Layout:KeepPositions(previous,nodes,live)
        height=0;for _,node in ipairs(nodes) do height=math.max(height,node.y+node.h) end
    end
    return nodes,height,projection,emptyProjection
end
function V:Layout(w,force,transferLayout)
    force=force or w.reflow;w.reflow=nil
    if not w.open then return end
    if w.liveBank=="guild" then self:RefreshGuildBagRoute() end
    if A.InCombat() then w.deferred=true;self:Patch(w,true);return end
    RestoreCombinedPool(w)
    if w.combatLoot then self:HideCombatLoot(w) end
    w.deferred=nil
    force=force or w.id=="player" and (B.Actions.nativeSort==true or B.Actions.kind=="sort")
        or w.liveBank=="bank" and B.Actions:IsSortingBank()
    local previousReady=w.readyPages
    local items,empties,container=self:Items(w)
    w.items,w.empties=items or {},empties or {}
    local reflow=w.reflowStacks;w.reflowStacks=nil
    local changed=self:ReconcileSelections(w)
    if changed then
        reflow=reflow or {};for key,item in pairs(changed) do reflow[key]=item end
    end
    local profile=B:GetConfig()
    local personalBank=YUI.IsForever and (w.liveBank=="bank" or w.owner and w.kind=="bank")
    local guildBank=w.liveBank=="guild"
    local guildView=guildBank or YUI.IsForever and w.owner and w.kind=="guild"
    local m=B.Appearance:Metrics()
    local top=m.contentTop
    local screenWidth,screenHeight=UIParent:GetWidth(),UIParent:GetHeight()
    local maxWindowHeight=screenHeight-48
    local config=setmetatable({layout=w.id=="keyring" and "single" or w.layout or profile.layout},{__index=profile})
    config.combinedWrapSpecialBags=YUI.IsForever and w.id=="player" and profile.combinedWrapSpecialBags==true
    if personalBank then
        for key,value in pairs(profile.bankView) do config[key]=value end
    elseif guildView then
        config.slotSize=profile.guildView.slotSize
        config.showSubnames=profile.guildView.showSubnames
    end
    if w.owner and w.kind=="guild" then config.emptyMode="one" end
    if guildBank then
        -- UIParent dimensions are already in UI units. Only the window's
        -- scale relative to its parent needs to be taken out of the budget.
        local scale=w.root.GetScale and w.root:GetScale() or 1
        screenWidth,screenHeight=screenWidth/scale,screenHeight/scale
        config.layout=w.page and "single" or "category"
        config.slotSize=math.min(config.slotSize,math.max(1,math.floor((screenWidth-m.left-m.right-guildScrollGutter-45)/14)))
    end
    w.effectiveLayout,w.slotSize=config.layout,(personalBank or guildView) and config.slotSize or nil
    if YUI.IsForever and w.id=="player" then
        w.combinedConfig=config.layout=="single" and config.emptyMode=="one" and
            {layout="single",emptyMode="one",slotSize=config.slotSize,combinedWrapSpecialBags=config.combinedWrapSpecialBags} or nil
    end
    config.splitPlacements=w.splitPlacements
    local physicalStacks=self:InteractionStacks(w)
    local grouping=self:Grouping(w,physicalStacks)
    if (A.CursorBusy() or B.Actions.queue) and w.grouping~=nil then
        grouping,physicalStacks=w.grouping,w.physicalStacks
    end
    if w.grouping~=grouping or w.physicalStacks~=physicalStacks then force=true end
    w.grouping,w.physicalStacks=grouping,physicalStacks
    w.transferPhysical=(w.id=="player" or w.liveBank=="bank") and not grouping and config.emptyMode=="all"
    local available=personalBank and screenWidth-32 or math.min(screenWidth*.65,900)
    local cols=guildBank and 14 or B.Layout:Columns(#w.items+#w.empties,available,config,w.cols)
    if w.id=="keyring" then cols=math.min(cols,4) end
    w.cols=cols
    local nodes,height,projection,emptyProjection
    if guildBank then
        nodes,height={},0
        if w.guildMode=="items" then
            nodes,height=B.GuildInventory:Build(w,w.items,w.empties,config,cols)
        end
    else
        nodes,height,projection,emptyProjection=BuildInventoryLayout(w,config,cols,force,reflow,grouping,transferLayout)
    end
    w.nodes,w.totalHeight,w.layoutKey=nodes,height,config.layout..":"..cols
    local gridWidth=cols*(config.slotSize+3)-3
    local width=gridWidth+m.left+m.right+(guildBank and guildScrollGutter or 0)
    local minWidth=w.liveBank and 440 or w.id=="keyring" and 250 or w.id=="player" and YUI.IsForever and 312 or 0
    width=math.max(minWidth,width)
    if guildBank then width=math.min(width,screenWidth) end
    -- A category receipt normally changes only the grid. Reuse the measured
    -- chrome while its width, bank availability and column budget still fit.
    if transferLayout and not force and w.footerHeight and width==w.root:GetWidth() and gridWidth==w.scroll:GetWidth()
        and previousReady==w.readyPages and (w.id=="player" or w.liveBank=="bank") then
        local maxBody=math.max(80,maxWindowHeight-top-w.footerHeight-m.bottom)
        if not config.autoSize or height<=maxBody or cols>=B.Layout:MaxColumns(available,config) then
            local visible=math.max(80,math.min(height+1,maxBody))
            local windowHeight=top+visible+w.footerHeight+m.bottom
            if w.root:GetHeight()~=windowHeight then w.root:SetHeight(windowHeight) end
            if w.scroll:GetHeight()~=visible then w.scroll:SetHeight(visible) end
            w.content:SetSize(gridWidth,math.max(height,visible))
            local maxScroll=math.max(0,height-visible)
            if w.scroll:GetVerticalScroll()>maxScroll then w.scroll:SetVerticalScroll(maxScroll) end
            self:CapacityText(w)
            self:RenderCapacity(w)
            B.Stats.layouts=B.Stats.layouts+1
            self:Paint(w,true)
            return
        end
    end
    if w.showBags then self:RenderBagBar(w) end
    w.search:SetWidth(math.max(80,math.min(150,width-220)))
    B.Appearance:LayoutHeader(w,width)
    if w.id=="player" then self:Toolbar(w,width)
    else
        local titleWidth=math.max(60,width-(w.id=="keyring" and 112 or 180))
        w.title:ClearAllPoints();w.title:SetPoint("CENTER",w.header,"CENTER",0,0);w.title:SetWidth(titleWidth);w.title:SetWordWrap(false)
        w.drag:ClearAllPoints();w.drag:SetPoint("CENTER",w.header,"CENTER",0,0);w.drag:SetSize(titleWidth,m.headerHeight)
    end
    if w.id~="player" then
        w.search:ClearAllPoints()
        if w.liveBank=="bank" then w.search:SetPoint("RIGHT",w.sort,"LEFT",-7,0)
        else w.search:SetPoint("RIGHT",w.root,"TOPRIGHT",-m.right,-m.toolsTop-m.toolsHeight/2) end
    end
    w.sort:ClearAllPoints();w.sort:SetPoint("TOPRIGHT",-m.right,-m.toolsTop)
    w.capacity:ClearAllPoints();w.capacity:SetPoint("LEFT",w.root,"TOPLEFT",m.left,-m.toolsTop-m.toolsHeight/2)
    w.money:ClearAllPoints();w.money:SetPoint("RIGHT",w.root,"BOTTOMRIGHT",-m.right,m.bottom+m.footerRow/2)
    local footer=w.id=="player" and self:RenderCurrencies(w,gridWidth) or w.id=="keyring" and 4
        or w.liveBank=="bank" and 42 or m.footerRow
    local outside=0
    if guildBank then
        footer,outside=B.GuildServices:FooterMetrics(w,width,m)
        local headerSpace=screenHeight-outside-footer-m.bottom-(config.slotSize+3)
        w.guildTabRowLimit=B.BankView:GuildTabRowLimit(headerSpace,m)
        top=B.BankView:GuildBodyTop(w,m)
    end
    w.footerHeight=footer
    local maxBody=math.max(80,maxWindowHeight-top-footer-m.bottom)
    if not guildBank and config.autoSize and height>maxBody then
        local limit=B.Layout:MaxColumns(available,config)
        while height>maxBody and cols<limit do
            cols=cols+1;nodes,height=B.Layout:Build(projection,emptyProjection,config,cols,w.collapsed,w.query)
        end
        w.cols,w.nodes,w.totalHeight,w.layoutKey=cols,nodes,height,config.layout..":"..cols
        gridWidth=cols*(config.slotSize+3)-3;width=math.max(minWidth,gridWidth+m.left+m.right)
        w.header:SetWidth(width)
        if w.id=="player" then self:Toolbar(w,width);footer=self:RenderCurrencies(w,gridWidth);w.footerHeight=footer end
        maxBody=math.max(80,maxWindowHeight-top-footer-m.bottom)
    end
    local visible,windowHeight
    if guildBank then
        local chrome=B.BankView:GuildHeaderBudget(w,width,m)+footer+m.bottom
        local pitch=config.slotSize+3
        local limit=screenHeight-outside
        -- Keep the 48-unit screen gutter while space permits. On a short
        -- screen give one item row priority over the gutter.
        windowHeight=math.max(1,math.min(chrome+7*pitch,limit,math.max(limit-48,chrome+pitch)))
        visible=math.max(1,windowHeight-top-footer-m.bottom)
    else
        local minBody=w.id=="keyring" and config.slotSize+3 or 80
        visible=math.max(minBody,math.min(height+1,maxBody))
        windowHeight=top+visible+footer+m.bottom
    end
    w.root:SetSize(width,windowHeight)
    B.Appearance:Surface(w)
    w.content:SetSize(gridWidth,math.max(height,visible));w.scroll:SetSize(gridWidth,visible)
    w.scroll:ClearAllPoints();w.scroll:SetPoint("TOPLEFT",m.left,-top)
    if w.id=="player" and YUI.IsForever and w.effectiveLayout=="category" then w.scrollLeft,w.scrollTop=m.left,top end
    w.scroll:SetVerticalScroll(math.min(w.scroll:GetVerticalScroll(),math.max(0,height-visible)))
    if guildBank then LayoutGuildScrollBar(w,height,visible) end
    local capacity=self:CapacityText(w)
    w.capacity:SetText(container and not container.complete and B:T("cache.partial").." · "..capacity or capacity)
    if not items then w.capacity:SetText(B:T("cache.unknown")) end
    if w.liveBank then
        w.sort:SetShown(w.liveBank=="bank")
        B.BankView:LayoutHeader(w,width,m)
    elseif w.id=="player" then
        if not YUI.IsForever then w.capacity:SetWidth(math.max(1,width-m.left-m.right-w.search:GetWidth()-45)) end
        self:RenderCapacity(w)
    else
        w.sort:Hide()
        w.money:SetText(container and container.updated and date("%m-%d %H:%M",container.updated) or "")
        w.cacheTimestamp=container and container.updated
    end
    B.Stats.layouts=B.Stats.layouts+1
    self:Paint(w,transferLayout and not force)
    if w.id=="player" then w.prepared=true end
end
local function NeedsPhysicalStack(view,data)
    local item=data.item
    return item.members and view:InteractionStacks(data.window)
end
local function IsCarriedWindow(w)
    return not w.owner and (w.id=="player" or w.id=="keyring")
end
local function GuildBagBlocked(view)
    if not YUI.IsForever or not B.active or not B.guildOpen then return false end
    if B.Deposit.bagDeposit then return true end
    local guild=view.windows["live-guild"]
    if not guild or not guild.open then return B.Runtime.bankPresentation=="guild" end
    local page=guild.page
    -- Slot snapshots are irrelevant to native auto-deposit, including first-use empty tabs.
    return A.InCombat() or guild.guildMode~="items" or not page or not A.BankWindowShown("guild")
        or A.CurrentGuildTab()~=page or not B.Deposit.guildOwner or not B.Deposit:GuildPermission(page)
end
local function GuildDestinations()
    local targets={}
    for _,tab in ipairs(A.GuildTabs()) do
        if tab.view and tab.deposit and B.Deposit.guildOwner and B.Deposit:GuildPermission(tab.id) then
            targets[#targets+1]=tab
        end
    end
    return targets
end
local function SameDestinations(previous)
    local current=GuildDestinations()
    if #previous~=#current then return false end
    for n,tab in ipairs(current) do
        local old=previous[n]
        if tab.id~=old.id or tab.name~=old.name or tab.icon~=old.icon then return false end
    end
    return true
end
local function SameChoiceStack(item,source)
    return item and not item.empty and not item.held and not item.members and item.bag==source.bag
        and item.slot==source.slot and item.guid==source.guid and item.itemID==source.itemID
        and item.link==source.link and item.count==source.count
end
local function RefreshWindowItemInputs(view,w,cursor,merchantCursor)
    for _,button in ipairs(w.pool) do
        if button:IsShown() then view:UpdateItemInput(button,cursor,merchantCursor) end
    end
    local loot=w.combatLoot
    if loot and loot.frame:IsShown() then
        for _,button in ipairs(loot.prepared) do
            if button:IsShown() then view:UpdateItemInput(button,cursor,merchantCursor) end
        end
    end
end

function V:RefreshGuildBagRoute(metadataUpdated)
    if B.Deposit.bagDeposit then B.Deposit:CheckBagDeposit() end
    local blocked=GuildBagBlocked(self)
    local menu=self.menu
    local choice=menu and menu.actionContext
    if choice and choice.guildTargets then
        local w=self.windows["live-guild"]
        if not blocked or not w or not w.open or w.guildMode~="items" or w.page or w.cachedGuildPages~=choice.session
            or metadataUpdated and not SameDestinations(choice.guildTargets) then
            menu:Hide()
        end
    end
    if blocked==self.guildBagBlocked then return end
    self.guildBagBlocked=blocked
    for _,w in pairs(self.windows) do
        if w.open and IsCarriedWindow(w) then RefreshWindowItemInputs(self,w) end
    end
end
local function ChooseGuildDestination(view,owner)
    local w=view.windows["live-guild"]
    if B.Deposit.bagDeposit then B:Notify("guild.bag_waiting");return end
    if not w or not w.open or w.guildMode~="items" or w.page or not A.BankWindowShown("guild") then
        B:Notify("guild.bag_select_destination");return
    end
    if A.CursorBusy() or B.Actions.queue or B.Actions.nativeSort then B:Notify("bank.transfer_busy");return end
    local session=w.cachedGuildPages
    local binding=view.buttonData[owner]
    local source,reason=B.Deposit:BagDepositSource(binding and binding.item)
    if not source then B:Notify(reason);return end
    local choice={source=source,guildTargets=GuildDestinations(),session=session}
    local rows={}
    for _,tab in ipairs(choice.guildTargets) do
        local id=tab.id
        local name=tab.name and tab.name~="" and tab.name:gsub("|","||") or string.format(B:T("bank.page"),id)
        rows[#rows+1]={text=string.format(B:T("guild.bag_deposit_to"),name),icon=tab.icon,action=function(clicked)
            if clicked~=choice or not B.active or not B.guildOpen or not w.open or w.cachedGuildPages~=session
                or w.guildMode~="items" or w.page or A.InCombat() or not A.BankWindowShown("guild") then return end
            if A.CursorBusy() or B.Actions.queue or B.Actions.nativeSort then B:Notify("bank.transfer_busy");return end
            local data=view.buttonData[owner]
            if not data or not data.window.open or not owner:IsShown() or not SameChoiceStack(data.item,source) then
                B:Notify("error.changed");return
            end
            local current,changed=B.Deposit:BagDepositSource(source)
            if not current then B:Notify(changed);return end
            if B.Deposit:GuildPermission(id) and B.BankView:Select(w,id) then B.Deposit:StartBagDeposit(source,session,id)
            else B:Notify("guild.bag_select_destination") end
        end}
    end
    if #rows==0 then B:Notify("guild.bag_no_destination");return end
    GameTooltip:Hide()
    view:Menu(owner,rows,nil,true,choice)
end
local function HasItemMenu(window)
    return not (YUI.IsForever and window.id=="player" and window.effectiveLayout=="single")
end

function V:UpdateItemInput(button,cursor,merchantCursor)
    local data=self.buttonData[button]
    local input=self.itemInputs[button]
    if not data or not input then return end
    local item=data.item
    local left,right=false,false
    local inCombat=A.InCombat()
    -- A deferred aggregate is still bound to just one physical stack.
    if item and not item.held and NeedsPhysicalStack(self,data) then
        left,right=true,true
    elseif item and not item.held and not inCombat and (B.Actions:BlocksItemInput() or B.BankView.bagDrag) then
        left,right=true,true
    elseif item and not item.held and not inCombat and data.window.liveBank~="bank" then
        if cursor==nil then cursor=A.CursorBusy() end
        -- The native slot handles merchant purchases and their confirmation dialogs.
        if item.empty and cursor and merchantCursor==nil then merchantCursor=A.CursorKind()=="merchant" end
        left=item.empty and (not cursor or not merchantCursor)
            or cursor and item.members and data.window.dragSource~=nil
            or IsShiftKeyDown() and (item.count>1 or (item.displayCount or 0)>1) and not cursor
        if item.empty then right=not cursor
        elseif IsAltKeyDown() then right=HasItemMenu(data.window)
        else right=item.quality==0 and A.IsNonEquippable(item) and A.Context()=="travel" and not B.Actions:Protected(item) end
    end
    if self.guildBagBlocked and IsCarriedWindow(data.window) then right=true end
    local route=(left and 1 or 0)+(right and 2 or 0)
    if data.inputRoute==route then return end
    if left and right then input:SetPassThroughButtons("MiddleButton","Button4","Button5")
    elseif left then input:SetPassThroughButtons("RightButton","MiddleButton","Button4","Button5")
    elseif right then input:SetPassThroughButtons("LeftButton","MiddleButton","Button4","Button5") end
    input:SetMouseClickEnabled(route~=0)
    data.inputRoute=route
end
function V:RefreshItemInputs(cursorChanged)
    -- Start installs the input guard, and newly painted buttons inherit it in Bind.
    -- Picking up and dropping each queued item cannot change that guard.
    if cursorChanged and B.Actions:IsPersonalBatch() and not A.InCombat() then return end
    local cursor=A.CursorBusy()
    local merchantCursor=cursor and A.CursorKind()=="merchant"
    for _,w in pairs(self.windows) do
        if not cursor then
            w.dragSource=nil
            if w.dragBag then w.dragBag=nil;if w.open then self:Paint(w) end end
        end
        if w.open then RefreshWindowItemInputs(self,w,cursor,merchantCursor) end
    end
end
function V:CloseItemSplitDialogs()
    if self.split and self.split:IsShown() then self.split:Hide() end
    local owner=StackSplitFrame and StackSplitFrame.owner
    if owner and self.buttonData[owner] then B.BankView:DismissStackSplit(owner) end
end
local function RefreshCooldownPool(view,pool)
    for _,button in ipairs(pool) do
        local data=view.buttonData[button]
        if data and button:IsShown() and not data.item.empty and not data.item.held then
            A.UpdateCooldown(button,data.item)
            B.Appearance:ItemCooldownText(button)
        end
    end
end
function V:RefreshCooldowns()
    for _,w in pairs(self.windows) do
        if w.open or w.prepared then RefreshCooldownPool(self,w.pool) end
        if w.combatLoot and w.combatLoot.frame:IsShown() then RefreshCooldownPool(self,w.combatLoot.prepared) end
    end
end
function V:ItemInputClick(button,mouse)
    local data=self.buttonData[button]
    local item=data and data.item
    if not item or item.held or A.InCombat() or B.Actions:BlocksItemInput() then return end
    if B.BankView.bagDrag then
        if mouse=="LeftButton" then self:DropEmpty(button) else B.BankView:DropBagDrag() end
        return
    end
    if NeedsPhysicalStack(self,data) then self:UpdateGrouping()
    elseif mouse=="LeftButton" and item.empty and A.CursorBusy() then self:DropEmpty(button)
    elseif mouse=="LeftButton" and item.members and A.CursorBusy() then self:ReturnToGroup(button)
    elseif IsAltKeyDown() and mouse=="RightButton" and not item.empty then
        if HasItemMenu(data.window) then self:ItemMenu(button,item) end
    elseif mouse=="RightButton" and self.guildBagBlocked and IsCarriedWindow(data.window) then
        if item.empty then return end
        if IsShiftKeyDown() or IsControlKeyDown and IsControlKeyDown() then A.HandleModifiedClick(item.link);return end
        ChooseGuildDestination(self,button)
    elseif IsShiftKeyDown() and mouse=="LeftButton" and not item.empty and (item.count>1 or (item.displayCount or 0)>1) and not A.CursorBusy() then
        if not A.HandleModifiedClick(item.link) then self:Split(item,button) end
    elseif mouse=="RightButton" and not item.empty and item.quality==0 then B.Actions:DeleteClick(item,button) end
end
function V:EmptyTooltip(button,item)
    if not item.empty then return false end
    local space=item.space or "normal"
    if space=="normal" then GameTooltip:Hide()
    else
        local key=space=="reagent" and "reagent" or space=="keyring" and "keyring" or "special"
        Tooltip(button,B:T("empty."..key))
    end
    return true
end
function V:ItemTooltipBlocked() return self.split and self.split:IsShown() end
function V:InstallItemInput(button)
    -- Keep inherited item scripts on the native button. The overlay only
    -- takes clicks while this window owns them.
    local input=G:CreateButtonFrame(button,{mouse=false,frameLevel=button:GetFrameLevel()+2})
    input:SetAllPoints();input:SetMouseMotionEnabled(false)
    input:RegisterForClicks("LeftButtonUp","RightButtonUp")
    input:RegisterForDrag("LeftButton")
    input:SetScript("OnClick",function(_,mouse) self:ItemInputClick(button,mouse) end)
    input:SetScript("OnDragStart",function()
        local data=self.buttonData[button]
        if data and data.item and not B.Actions:BlocksItemInput() and not B.BankView.bagDrag and NeedsPhysicalStack(self,data) then
            self:UpdateGrouping()
        end
    end)
    input:SetScript("OnReceiveDrag",function()
        if A.CursorBusy() or B.BankView.bagDrag then self:ItemInputClick(button,"LeftButton") end
    end)
    self.itemInputs[button]=input
end
local function AppendDragQuantity(view,data)
    local item=data.item
    if item.members and #item.members>1 and not NeedsPhysicalStack(view,data) then
        GameTooltip:AddLine(string.format(B:T("stack.drag_quantity"),item.displayCount,item.count),1,.82,0)
    end
end
function V:CreateItem(w,live,parent)
    local button
    if live=="bank" then
        button=B.Appearance:Item(w.content,false,"CamelotBankItemButtonTemplate")
        button:HookScript("OnHide",function(owner)
            B.BankView:DismissStackSplit(owner)
            local menu=self.menu
            if menu and menu.owner==owner and menu.actionContext and menu.actionContext.guildTargets then menu:Hide() end
        end)
        button:HookScript("OnReceiveDrag",function() B.BankView:DropBagDrag() end)
        button:HookScript("OnClick",function(_,mouse) if mouse=="LeftButton" then B.BankView:DropBagDrag() end end)
        self:InstallItemInput(button)
    elseif live then
        button=B.Appearance:Item(parent or w.content,true)
        self:InstallItemInput(button)
        button:HookScript("OnClick",function(owner,mouse)
            B.Actions:CancelDelete()
            if mouse=="LeftButton" then self:RememberCursor(owner) end
        end)
        button:HookScript("OnDragStart",function(owner) self:RememberCursor(owner) end)
        local enter,leave=button:GetScript("OnEnter"),button:GetScript("OnLeave")
        button:SetScript("OnEnter",function(owner)
            if B.guildOpen and IsCarriedWindow(w) then self:RefreshGuildBagRoute() end
            self:UpdateItemInput(owner)
            if self:ItemTooltipBlocked() then GameTooltip:Hide();return end
            local data=self.buttonData[owner]
            if not data or self:EmptyTooltip(owner,data.item) then return end
            if enter then enter(owner) else GameTooltip:SetOwner(owner,"ANCHOR_RIGHT");GameTooltip:SetBagItem(data.item.bag,data.item.slot) end
            B.Cache:AppendTooltip(data.item);AppendDragQuantity(self,data);GameTooltip:Show()
        end)
        local update=button.UpdateTooltip
        if type(update)=="function" then
            button.UpdateTooltip=function(owner,...)
                if self:ItemTooltipBlocked() then GameTooltip:Hide();return end
                update(owner,...)
                local data=self.buttonData[owner]
                if data and not data.item.empty then
                    B.Cache:AppendTooltip(data.item)
                    AppendDragQuantity(self,data)
                    if B.Actions.deleteButton==owner then GameTooltip:AddLine(B.Actions:DeleteHint(),1,.4,.3) end
                    GameTooltip:Show()
                end
            end
        end
        button:SetScript("OnLeave",function(owner) if leave then leave(owner) end;if B.Actions.deleteButton==owner then B.Actions:CancelDelete() end end)
    else
        button=B.Appearance:Item(w.content,false)
        button:SetScript("OnClick",nil);button:SetScript("OnDragStart",nil);button:SetScript("OnReceiveDrag",nil)
        button:SetScript("OnEnter",function(owner)
            if self:ItemTooltipBlocked() then GameTooltip:Hide();return end
            local data=self.buttonData[owner]
            if data and self:EmptyTooltip(owner,data.item) then return end
            if data and not data.item.empty then
                GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
                if data.item.link then GameTooltip:SetHyperlink(data.item.link) else GameTooltip:SetItemByID(data.item.itemID) end
                B.Cache:AppendTooltip(data.item);GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave",function() GameTooltip:Hide() end)
        button.UpdateTooltip=button:GetScript("OnEnter")
        if w.liveBank=="guild" then B.BankView:SetupGuildCell(button) end
    end
    if w.id=="player" then button.ybagsArtworkAnchor="LEFT" end
    button.deleteMark=G:CreateFrame(button,{mouse=false,hidden=true});button.deleteMark:SetAllPoints()
    local mark=Texture(button.deleteMark,icons.delete,15,15);mark:SetPoint("TOPRIGHT",-1,-1)
    for _,edge in ipairs({"TOP","BOTTOM","LEFT","RIGHT"}) do
        local border=G:CreateTexture(button.deleteMark,nil,"OVERLAY");border:SetColorTexture(1,.15,.1,1)
        if edge=="TOP" or edge=="BOTTOM" then border:SetHeight(2);border:SetPoint(edge.."LEFT");border:SetPoint(edge.."RIGHT")
        else border:SetWidth(2);border:SetPoint("TOP"..edge);border:SetPoint("BOTTOM"..edge) end
    end
    button.badge=Label(button,"",13);button.badge.gui2ColorKey=nil;button.badge:SetPoint("TOPLEFT",1,-1)
    button.badge:SetWordWrap(false)
    button.slotLock=Label(button,"",10);button.slotLock:SetPoint("BOTTOMLEFT",1,1)
    button.bindBadge=Label(button,B:T("item.bind_on_equip"),11);button.bindBadge:SetPoint("BOTTOMLEFT",2,2)
    button.bindBadge.gui2ColorKey=nil
    button.bindBadge:Hide()
    B.Stats.pool=B.Stats.pool+1
    return button
end
local equipSlots={INVTYPE_HEAD=1,INVTYPE_NECK=2,INVTYPE_SHOULDER=3,INVTYPE_BODY=4,INVTYPE_CHEST=5,INVTYPE_ROBE=5,
    INVTYPE_WAIST=6,INVTYPE_LEGS=7,INVTYPE_FEET=8,INVTYPE_WRIST=9,INVTYPE_HAND=10,INVTYPE_FINGER=11,INVTYPE_TRINKET=13,
    INVTYPE_CLOAK=15,INVTYPE_WEAPON=16,INVTYPE_2HWEAPON=16,INVTYPE_WEAPONMAINHAND=16,INVTYPE_SHIELD=17,
    INVTYPE_WEAPONOFFHAND=17,INVTYPE_HOLDABLE=17,INVTYPE_RANGED=18,INVTYPE_RANGEDRIGHT=18,INVTYPE_THROWN=18,INVTYPE_RELIC=18,INVTYPE_TABARD=19}
local onEquip=Enum and Enum.ItemBind and Enum.ItemBind.OnEquip or 2
local upgradeArrow="|A:bags-greenarrow:0:0:2:2|a"
function V:InvalidateEquipmentBadges()
    self.equippedLevels,self.waitingEquipment={},{}
    self.equipmentRevision=self.equipmentRevision+1
    local player=self.windows.player
    if player and player.open then self:Patch(player) end
    for _,w in pairs(self.windows) do
        local pool=w.liveBank=="bank" and w.pool or (w.liveBank=="guild" or w.kind=="guild") and w.cachePool
        if w.open and pool then
            for _,button in ipairs(pool) do
                local data=self.buttonData[button]
                if data and button:IsShown() and not data.item.empty then self:RefreshEquipmentText(button,data) end
            end
        end
    end
end
function V:EquippedLevel(slot)
    if self.equippedLevels[slot]==nil then
        local level,pendingID=A.EquippedLevel(slot)
        self.equippedLevels[slot]=level or false
        if pendingID then self.waitingEquipment[pendingID]=true end
    end
    return self.equippedLevels[slot]
end
function V:ItemBadgeText(button,w,data,item,slotSize)
    local style=B.Appearance:ItemTextStyle(slotSize)
    local restyled=data.textStyle~=style
    if restyled then B.Appearance:ApplyItemText(button,style) end
    local class,level,loc,bind=item.classID,item.level,item.equipLoc,item.bindType
    if w.liveBank=="guild" or w.kind=="guild" then
        class,level,loc,bind=B.GuildInventory:BadgeFields(item,data,self.equipmentRevision)
    end
    data.badgeBindType=bind
    level=not item.empty and (class==2 or class==4) and B.Classification.HasEquipSlot(loc) and level
    level=level and level>1 and level or nil
    local compare=w.id=="player" or w.liveBank=="bank" or w.liveBank=="guild" and not item.guildCached
    local slot=level and compare and equipSlots[loc] or nil
    if slot==18 and YUI.IsRetail then slot=16 end
    local revision=slot and self.equipmentRevision
    local candidate=slot and (item.link or item.itemID)
    local arrowBudget=slot and YUI.IsForever and slotSize or nil
    if restyled or data.levelText==nil or data.level~=level or data.upgradeSlot~=slot
        or data.equipmentRevision~=revision or data.arrowBudget~=arrowBudget or data.upgradeCandidate~=candidate then
        data.level,data.upgradeSlot,data.equipmentRevision=level,slot,revision
        data.arrowBudget,data.upgradeCandidate=arrowBudget,candidate
        local text=level and tostring(level) or ""
        if slot then
            local equipped=self:EquippedLevel(slot)
            local second=(slot==11 or slot==13) and self:EquippedLevel(slot+1)
            local wearable
            if equipped and level>equipped or second and level>second then
                wearable=A.CanWearEquipment(item.itemID,item.link)
                if wearable==nil and item.itemID then self.waitingEquipment[item.itemID]=true end
            end
            if wearable then
                if arrowBudget then
                    local size=math.min(style.arrow,math.floor(arrowBudget-2-B.Appearance:TextWidth(text,"level",style)))
                    if size>=6 then text=text..string.format("|A:bags-greenarrow:%d:%d:0:1|a",size,size) end
                else text=upgradeArrow..text end
            end
        end
        data.levelText=text
    end
    data.textStyle=style
    return data.levelText
end
local function ShowEquipmentBadges(button,data,item,visible)
    local showLevel=visible and data.badge~=""
    if data.badgeVisible~=showLevel then button.badge:SetShown(showLevel);data.badgeVisible=showLevel end
    local showBind=visible and not item.empty and data.locked=="" and data.badgeBindType==onEquip and item.bound==false
    if data.bindVisible~=showBind then button.bindBadge:SetShown(showBind);data.bindVisible=showBind end
    if button.chargeBadge then
        local showCharges=visible and data.shownCharges~=nil
        local paired=showCharges and showBind and data.chargesOnEquipment
        if paired and (data.pairStyle~=data.textStyle or data.pairCharges~=data.shownCharges) then
            button.bindBadge:SetScale(1)
            button.chargeBadge:SetScale(1)
            local width=button.bindBadge:GetStringWidth()+button.chargeBadge:GetStringWidth()
            if width>button:GetWidth()-5 then
                local scale=(button:GetWidth()-5)/width
                button.bindBadge:SetScale(scale)
                button.chargeBadge:SetScale(scale)
            end
            data.pairStyle,data.pairCharges=data.textStyle,data.shownCharges
        elseif not paired and data.pairStyle then
            button.bindBadge:SetScale(1)
            button.chargeBadge:SetScale(1)
            data.pairStyle,data.pairCharges=nil,nil
        end
        if data.chargesVisible~=showCharges then
            button.chargeBadge:SetShown(showCharges)
            data.chargesVisible=showCharges
        end
    end
end
local function BindCharges(button,data,item)
    local charges=not item.empty and not item.held and item.charges or nil
    if charges==nil then data.shownCharges=nil;return end
    local equipment=item.classID==2 or item.classID==4
    local badge=button.chargeBadge
    if not badge then
        badge=Label(button,"",11)
        badge.gui2ColorKey=nil
        badge:SetWordWrap(false)
        badge:SetTextColor(.68,.89,.92,1)
        G:ApplyFontAppearance(badge,data.textStyle.bind)
        button.chargeBadge=badge
    end
    if data.chargesOnEquipment~=equipment then
        badge:ClearAllPoints()
        if equipment then badge:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-2,1)
        else badge:SetPoint("TOPLEFT",button,"TOPLEFT",1,-1) end
        data.chargesOnEquipment=equipment
    end
    if data.shownCharges~=charges then
        badge:SetText(string.format(B:T("item.charge_count"),charges))
        data.shownCharges=charges
    end
end
local function ShowExperienceFoodBadge(button,item,visible)
    local badge=button.experienceFoodBadge
    local shown=visible and not item.empty and B.Classification.IsExperienceFood(item.itemID)
    if shown and not badge and not A.InCombat() then
        badge=G:CreateTexture(button,{atlas="bonus-objective-star",width=14,height=14,layer="OVERLAY",subLevel=2})
        badge:SetPoint("TOPLEFT",button,"TOPLEFT",1,-1)
        button.experienceFoodBadge=badge
    end
    if badge and badge:IsShown()~=shown then badge:SetShown(shown) end
end
function V:RefreshEquipmentText(button,data)
    local badge=self:ItemBadgeText(button,data.window,data,data.item,data.size or button:GetWidth())
    if data.badge~=badge then button.badge:SetText(badge);data.badge=badge end
    ShowEquipmentBadges(button,data,data.item,data.alpha==1 and not data.item.held)
end
function V:RefreshItemText()
    for button,data in pairs(self.buttonData) do
        if data.item and button:IsShown() then
            self:RefreshEquipmentText(button,data)
            B.Appearance:ItemCooldownText(button)
        end
    end
end
local recipeClass=Enum and Enum.ItemClass and Enum.ItemClass.Recipe or 9
function V:ResetRecipeStates()
    self.recipeStates,self.bankRecipeStates,self.recipePending={},{},{}
end
V:ResetRecipeStates()
function V:RecipeTint(w,item)
    if item.classID~=recipeClass or not item.link or item.held or w.owner or not w.root:IsShown() then return end
    local config=B:GetConfig()
    if not config.tintKnownRecipes and not config.tintUnusableRecipes then return end
    local inBank=w.liveBank~=nil
    local states=inBank and self.bankRecipeStates or self.recipeStates
    local state=states[item.link]
    if state==nil and not A.InCombat() then
        local ReadState=YUI.API.Item.RecipeLearningState
        state=ReadState and ReadState(item.link,inBank)
        -- Late tooltip data is retried on the next item/profession update or reopen.
        states[item.link]=state or false
        if state==nil and item.itemID then self.recipePending[item.itemID]=true end
    end
    if state=="known" and config.tintKnownRecipes or state=="unusable" and config.tintUnusableRecipes then return state end
end
function V:RefreshRecipeTints()
    for button,data in pairs(self.buttonData) do
        if data.item and data.window and data.window.open and button:IsShown() then
            local tint=self:RecipeTint(data.window,data.item)
            if data.recipeTint~=tint then
                B.Appearance:CellAppearance(button,data.item.empty==true,data.item,tint)
                data.recipeTint=tint
            end
        end
    end
end
-- The native Count can be rewritten by a physical-slot update between receipts.
-- While splitting a projected stack, show its confirmed remainder on its own label.
local function ShowSplitCount(button,data,count)
    local label=button.splitCountLabel
    if not label then
        label=Label(button,"",12)
        label:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-2,1)
        label:SetWordWrap(false)
        button.splitCountLabel=label
    end
    if data.splitCountStyle~=data.textStyle then
        G:ApplyFontAppearance(label,data.textStyle.count)
        data.splitCountStyle=data.textStyle
    end
    if button.splitCount~=count then
        label:SetText(count)
        label:SetShown(count>1)
        button.splitCount=count
    end
    button.Count:SetAlpha(0)
    label:SetAlpha(data.alpha or 1)
end
function V:BeginSplitDisplay(w,plan)
    if not plan.selection.groupUID then return end
    for _,button in ipairs(w.pool) do
        local data=self.buttonData[button]
        if button:IsShown() and data and data.item and data.item.uid==plan.selection.groupUID then
            ShowSplitCount(button,data,plan.unseparated)
            return
        end
    end
end
local function IsPresetSource(bags,item)
    local slots=bags[item.bag]
    local source=slots and slots[item.slot]
    return source and source.itemID==item.itemID and source.link==item.link
end

local function PaintPresetHighlight(preview,w,button,item)
    local sources=preview.sources[w]
    local show
    if sources and item and not (item.empty or item.held or item.guildCached) then
        show=IsPresetSource(sources,item)
        if not show and item.members then
            for _,member in ipairs(item.members) do
                if IsPresetSource(sources,member) then show=true;break end
            end
        end
    end
    if show and not preview.shown[button] then
        local marker=button.ybagsPresetHighlight
        if not marker then
            marker={}
            button.ybagsPresetHighlight=marker
        end
        B.Appearance:ShowNewItemGlow(button,marker)
        preview.shown[button]=marker
    elseif not show and preview.shown[button] then
        B.Appearance:HideNewItemGlow(preview.shown[button])
        preview.shown[button]=nil
    end
end

function V:ShowPresetPreview(bank,deposit,withdraw)
    local preview=self.presetPreview or {sources={},shown={}}
    self.presetPreview=preview
    local player=self.windows.player
    preview.sources[bank]=withdraw
    if player then preview.sources[player]=deposit end
    for _,w in ipairs({bank,player}) do
        for _,pool in ipairs({w.pool,w.cachePool}) do
            for _,button in ipairs(pool) do
                local data=self.buttonData[button]
                if data or preview.shown[button] then
                    local visible=w.open and data and button:IsShown()
                    PaintPresetHighlight(preview,w,button,visible and data.item)
                end
            end
        end
    end
end

function V:ClearPresetPreview()
    local preview=self.presetPreview
    if not preview then return end
    for _,marker in pairs(preview.shown) do B.Appearance:HideNewItemGlow(marker) end
    self.presetPreview=nil
end

function V:Bind(button,w,node,item,hidden)
    item=item or node.item
    local menu=self.menu
    if menu and menu.owner==button and menu.actionContext and menu.actionContext.guildTargets
        and not SameChoiceStack(item,menu.actionContext.source) then menu:Hide() end
    if w.liveBank=="guild" and B.BankView.guildSplit then B.BankView:CancelGuildSplit(button,item) end
    local data=self.buttonData[button]
    if not data then data={};self.buttonData[button]=data end
    local binding=data.bag~=item.bag or data.slot~=item.slot
    local initialized=false
    if w.liveBank=="bank" and not item.held and self.itemInputs[button] then
        if binding or not data.item or data.item.link~=item.link or data.count~=item.count or item.locked then
            B.BankView:DismissStackSplit(button)
        end
        if binding and not A.InitCharacterBankButton(button,item.bag,item.slot) then
            button:Hide()
            self.buttonData[button]=nil
            return
        end
        initialized=binding
    end
    if button.Initialize and binding and not item.held and A.InCombat() then w.deferred=true;return end
    button.ybagsSpace=item.empty and (item.space or "normal") or nil
    if button.Initialize and binding and not item.held then
        if A.InitializeButton(button,w.provider,item.bag,item.slot) then
            initialized=true
            if YUI.IsForever and w.id=="player" then nativeSlotLocks[button]=A.HasNativeSlotLock(button) or nil end
        end
    end
    if initialized then
        -- The native frame retains its slot when pooled visual data is cleared.
        local native=self.itemBindings[button]
        if not native then native={};self.itemBindings[button]=native end
        native.previousBag,native.previousSlot=native.bag,native.slot
        native.bag,native.slot,native.at=item.bag,item.slot,A.Now()
    end
    local texture=item.empty and "Interface\\PaperDoll\\UI-Backpack-EmptySlot" or item.icon
    local count=item.aggregate or (not item.empty and (item.displayCount or item.count)) or 0
    local otherBag=w.hoverBag~=nil and item.bag~=w.hoverBag
    if item.aggregate and (w.dragBag or w.hoverBag) then
        count=0
        for _,empty in ipairs(w.empties) do
            if empty.space==item.space and (not item.bagScoped or empty.bag==item.bag)
                and (w.dragBag and empty.bag~=w.dragBag or not w.dragBag and empty.bag==w.hoverBag) then count=count+1 end
        end
        otherBag=count==0
    elseif item.members and w.hoverBag and not w.dragBag then
        count=0
        for _,member in ipairs(item.members) do
            local current=w.owner and member or B.Model.byUID[member.uid]
            if current and current.bag==w.hoverBag and B.Classification:SameStack(current,item,item.ignoreDisplayBinding) then
                count=count+current.count
            end
        end
        otherBag=count==0
    end
    local changed=false
    if binding or data.texture~=texture then SetItemButtonTexture(button,texture);data.texture=texture;changed=true end
    local showOne=w.owner and w.kind=="guild" and item.aggregate==1 or false
    local split=B.Actions.selection
    local projected=split and split.progressiveGroups and w.id=="player" and item.members and item.uid==split.selection.groupUID
    local restoreCount=button.splitCount~=nil and not projected
    if restoreCount then
        button.splitCountLabel:Hide()
        button.splitCount=nil
        button.Count:SetAlpha(data.alpha or 1)
    end
    if binding or restoreCount or data.count~=count or data.showOne~=showOne then
        SetItemButtonCount(button,count)
        if showOne and button.Count then button.Count:SetText("1");button.Count:Show() end
        data.count,data.showOne=count,showOne;changed=true
    end
    if binding or data.quality~=item.quality then if SetItemButtonQuality then SetItemButtonQuality(button,item.quality) end;data.quality=item.quality;changed=true end
    local desaturated=item.held==true or item.locked==true
    if binding or data.held~=desaturated then if SetItemButtonDesaturated then SetItemButtonDesaturated(button,desaturated) end;data.held=desaturated;changed=true end
    if binding or data.hasItem~=(not item.empty) then
        if button.SetHasItem then button:SetHasItem(not item.empty) else button.hasItem=not item.empty end
        data.hasItem=not item.empty;changed=true
    end
    button.itemID=item.itemID
    if binding or data.stateID~=item.itemID or data.stateEmpty~=item.empty or data.stateNew~=item.new or data.stateQuest~=item.quest then
        A.UpdateButtonState(button,item)
        data.stateID,data.stateEmpty,data.stateNew,data.stateQuest=item.itemID,item.empty,item.new,item.quest
    end
    local slotSize=w.slotSize or B:GetConfig().slotSize
    local resized=data.size~=slotSize and not A.InCombat()
    local badge=self:ItemBadgeText(button,w,data,item,resized and slotSize or data.size or slotSize)
    if projected and (button.splitCountLabel or not A.InCombat()) then ShowSplitCount(button,data,split.unseparated) end
    BindCharges(button,data,item)
    if data.badge~=badge then button.badge:SetText(badge);data.badge=badge;changed=true end
    if data.badgeQuality~=item.quality then
        local r,g,b=YUI.API.Item.GetQualityColor(item.quality)
        r,g,b=S.SafeNumber(r) or 1,S.SafeNumber(g) or 1,S.SafeNumber(b) or 1
        button.badge:SetTextColor(r,g,b,1);button.bindBadge:SetTextColor(r,g,b,1);data.badgeQuality=item.quality
    end
    local locked=w.liveBank~="guild" and w.kind~="guild" and not item.empty and HasItemMenu(w)
        and B:GetConfig().locks[item.key] and "|T134237:10|t" or ""
    if data.locked~=locked then button.slotLock:SetText(locked);data.locked=locked;changed=true end
    if changed then B.Stats.writes=B.Stats.writes+1 end
    if data.x~=node.x or data.y~=node.y then
        button:ClearAllPoints();button:SetPoint("TOPLEFT",node.content or w.content,"TOPLEFT",node.x,-node.y)
        data.x,data.y=node.x,node.y
    end
    data.item,data.bag,data.slot,data.window=item,item.bag,item.slot,w
    data.revision=item.revision
    self:UpdateItemInput(button)
    local bound=data
    if resized then button:SetSize(slotSize,slotSize);bound.size=slotSize end
    local space=item.empty and item.space or nil
    local tint=self:RecipeTint(w,item)
    if changed or resized or data.space~=space or data.recipeTint~=tint then
        B.Appearance:CellAppearance(button,item.empty==true,item,tint)
    end
    local questVisual=item.questVisual and self.itemInputs[button] and not item.empty and not item.held and item.questVisual or nil
    B.Appearance:CellQuest(button,questVisual)
    data.space,data.recipeTint=space,tint
    local match=item.empty or B.Classification:Matches(item,w.query)
    local dimmed=otherBag
    if item.empty and w.dragBag then
        dimmed=item.bag==w.dragBag
        if item.aggregate then
            dimmed=true
            for _,empty in ipairs(w.empties) do
                if empty.bag~=w.dragBag and empty.space==item.space then dimmed=false;break end
            end
        end
    elseif w.dragBag then dimmed=false end
    local alpha=match and (dimmed and .2 or 1) or .18
    if binding or changed or bound.alpha~=alpha then
        B.Appearance:CellAlpha(button,alpha)
        bound.alpha=alpha
    end
    local showBadges=match and not dimmed and not item.held
    ShowEquipmentBadges(button,data,item,showBadges)
    if YUI.IsForever then ShowExperienceFoodBadge(button,item,showBadges) end
    if w.liveBank=="guild" then B.GuildInventory:PaintHighlight(w,button,item)
    elseif button.ybagsGuildLocate then B.GuildInventory:ReleaseHighlight(button) end
    if self.presetPreview then PaintPresetHighlight(self.presetPreview,w,button,not hidden and item) end
    if bound.mouse~=(not item.held) then button:EnableMouse(not item.held);bound.mouse=not item.held end
    if hidden then
        if button:IsShown() then button:Hide() end
    elseif not button:IsShown() then button:Show() end
end
-- Display the physical slot during a batch; keep its original layout node
-- intact so the final category layout can retain vacated positions.
local function TransferCell(item,category,section,group)
    local bag=B.Model.bags[item.bag]
    local current=bag and bag.slots[item.slot]
    if category then current=ReceivedItem(current,B.Actions.waiting) end
    if current and (not category or current.section==section and current.group==group) then return current end
    if item.empty then return item end
    return {empty=true,bag=item.bag,slot=item.slot,space=item.space}
end
-- Layout recreates empty cells. Match an ordinary vacancy by slot, and a
-- retained vacancy by both slot and original identity; aggregates need a rebind.
local function SameTransferCell(data,item)
    if data.item==item then return data.revision==item.revision end
    if not item.empty or not data.item.empty or item.aggregate or data.item.aggregate
        or data.bag~=item.bag or data.slot~=item.slot or data.space~=item.space then return false end
    if item.held or data.item.held then
        return item.held==data.item.held and item.uid==data.item.uid and data.revision==item.revision
    end
    return not item.uid and not data.item.uid
end
-- Inserting one head item can shift every visible row below it. Keep each
-- existing native button with its physical slot across that change of order.
local function ReuseTransferButtons(view,w,low,high)
    local byBag,indices={},{}
    for _,pool in ipairs({w.pool,w.cachePool}) do
        for index,button in ipairs(pool) do
            local data=view.buttonData[button]
            if data then
                local slots=byBag[data.bag]
                if not slots then slots={};byBag[data.bag]=slots end
                slots[data.slot]=button
            end
            indices[button]=index
        end
    end
    local liveCount,heldCount=0,0
    for _,node in ipairs(w.nodes) do
        if node.kind=="item" and node.y+node.h>=low and node.y<=high then
            local item=node.item
            local pool,index,live
            if item.held then
                heldCount=heldCount+1
                pool,index=w.cachePool,heldCount
            else
                liveCount=liveCount+1
                pool,index,live=w.pool,liveCount,w.liveBank=="bank" and "bank" or true
            end
            local button=byBag[item.bag] and byBag[item.bag][item.slot]
            local old=indices[button]
            if old and old~=index and pool[old]==button then
                while #pool<index do pool[#pool+1]=view:CreateItem(w,live) end
                local other=pool[index]
                pool[index],pool[old]=button,other
                indices[button],indices[other]=index,old
            end
        end
    end
end
local function PrepareAlternateButtons(view,w,node,data,count,slotSize)
    local item=data.item
    data.combatGroup,data.firstAlternate,data.lastAlternate=nil,nil,nil
    if not item.members or #item.members<2 then return count end
    -- Every spare has its own native slot binding and the visible cell's position.
    data.combatGroup,data.firstAlternate=item,count+1
    for _,member in ipairs(item.members) do
        if member.bag~=item.bag or member.slot~=item.slot then
            count=count+1
            local button=w.alternates[count]
            if not button then button=view:CreateItem(w,true);w.alternates[count]=button end
            local binding=view.buttonData[button]
            if not binding or binding.bag~=member.bag or binding.slot~=member.slot
                or binding.x~=node.x or binding.y~=node.y or binding.size~=slotSize then
                view:Bind(button,w,node,member,true)
            end
        end
    end
    data.lastAlternate=count
    return count
end

local function CreateCombatLoot(view,w)
    local frame=G:CreateFrame(w.root,{hidden=true})
    local text=B:T("section.recent")
    local frames=B.Appearance:RecentCaptionFrames(text)
    local titleText=frames and frames[0] or text
    local title=Label(frame,titleText,12,"color.text.heading")
    B.Appearance:Text(title,"heading")
    title:SetPoint("TOPLEFT",B.Appearance.headingInset,-1)
    local scroll=G:CreateFrame(frame,{type="ScrollFrame",mouseWheel=true})
    scroll:SetPoint("TOPLEFT",0,-16)
    local content=G:CreateFrame(scroll,{width=1,height=1})
    scroll:SetScrollChild(content)
    local loot={frame=frame,title=title,titleText=titleText,scroll=scroll,content=content,bySlot={},prepared={},represented=setmetatable({}, {__mode="k"}),node={content=content}}
    local titleWidth=B.Appearance:HeadingWidth("recent",0,false)
    local hintWidth=B.Appearance:TextWidth(B:T("action.clear_recent_hint"),"heading")
    local clear=G:CreateButtonFrame(frame,{height=16,width=math.max(titleWidth,hintWidth)})
    clear:SetPoint("TOPLEFT")
    clear:RegisterForClicks("LeftButtonUp")
    PrepareRecentClearHint(clear,title)
    clear:SetScript("OnClick",function()
        GameTooltip:Hide()
        for _,button in ipairs(loot.prepared) do
            local data=view.buttonData[button]
            local bag=B.Model.bags[data.bag]
            data.combatLootOriginal=bag and bag.slots[data.slot]
        end
        view:HideCombatLoot(w)
        B.Actions:ClearRecent(A.GetCarryBags(false))
    end)
    scroll:SetScript("OnMouseWheel",function(owner,delta)
        local offset=math.max(0,math.min(owner:GetVerticalScroll()-delta*loot.pitch,content:GetHeight()-owner:GetHeight()))
        owner:SetVerticalScroll(offset)
    end)
    w.combatLoot=loot
    return loot
end

function V:HideCombatLoot(w)
    local loot=w.combatLoot
    if not loot.frame:IsShown() then return end
    loot.frame:Hide()
    for _,button in ipairs(loot.prepared) do if button:IsShown() then button:Hide() end end
    if loot.replacedHeading then loot.replacedHeading:Show();loot.replacedHeading=nil end
    w.scroll:ClearAllPoints();w.scroll:SetPoint("TOPLEFT",w.scrollLeft,-w.scrollTop)
    w.scroll:SetHeight(loot.viewHeight)
    w.root:SetHeight(loot.windowHeight)
end

local function PrepareCombatLoot(view,w,slotSize)
    if w.combatLootItems==w.items and w.combatLootNodes==w.nodes then return end
    w.combatLootItems,w.combatLootNodes=w.items,w.nodes
    local loot=w.combatLoot
    local viewHeight,windowHeight=w.scroll:GetHeight(),w.root:GetHeight()
    local extraHeight=slotSize+22
    local shrink=math.min(viewHeight-1,math.max(0,windowHeight+extraHeight-UIParent:GetHeight()))
    local covered={}
    -- A slot already represented by the normal layout keeps its place, even
    -- when the scroll viewport has clipped it or Paint has not bound it yet.
    for _,node in ipairs(w.nodes) do
        if node.kind=="item" and not node.item.held then
            covered[node.item.bag..":"..node.item.slot]=true
        end
    end
    local count=0
    for _,items in ipairs({w.items,w.empties}) do
        for _,item in ipairs(items) do
            local key=item.bag..":"..item.slot
            if not covered[key] then
                loot=loot or CreateCombatLoot(view,w)
                local button=loot.bySlot[key]
                if not button then button=view:CreateItem(w,true,loot.content);loot.bySlot[key]=button end
                local data=view.buttonData[button]
                if not data or data.size~=slotSize then
                    loot.node.x,loot.node.y=0,0
                    view:Bind(button,w,loot.node,item,true)
                    data=view.buttonData[button]
                end
                data.combatLootOriginal=item
                count=count+1;loot.prepared[count]=button
            end
        end
    end
    if not loot then return end
    for index=count+1,#loot.prepared do loot.prepared[index]=nil end
    local existingGUIDs={}
    for _,item in ipairs(w.items) do if item.guid then existingGUIDs[item.guid]=true end end
    loot.existingGUIDs=existingGUIDs
    loot.revision,loot.visibleCount=nil,nil
    loot.pitch,loot.columns=slotSize+3,w.cols
    loot.windowHeight,loot.viewHeight=windowHeight,viewHeight
    loot.extraHeight,loot.shrink=extraHeight,shrink
    local width=w.scroll:GetWidth()
    loot.frame:ClearAllPoints();loot.frame:SetPoint("TOPLEFT",w.root,"TOPLEFT",w.scrollLeft,-w.scrollTop)
    loot.frame:SetSize(width,loot.extraHeight-3)
    loot.scroll:SetSize(width,loot.pitch)
    loot.content:SetSize(width,loot.pitch)
    loot.scroll:SetVerticalScroll(0)
end

local function PatchCombatLoot(view,w)
    local loot=w.combatLoot
    if not loot then return end
    local revision=B.Model.revision
    local scrolled=w.scroll:GetVerticalScroll()>0
    if loot.revision==revision and loot.query==w.query and loot.scrolled==scrolled then return end
    local queryChanged=loot.query~=w.query
    loot.revision,loot.query,loot.scrolled=revision,w.query,scrolled
    local arrivals=B.Model.combatArrivals
    local represented=loot.represented
    for item in pairs(represented) do represented[item]=nil end
    if arrivals then
        for _,button in ipairs(w.pool) do
            local data=view.buttonData[button]
            if data and button:IsShown() and not data.item.empty then
                local item=data.item
                if item.members then
                    for _,member in ipairs(item.members) do if arrivals[member] then represented[member]=true end end
                elseif arrivals[item] then represented[item]=true end
            end
        end
    end
    local count=0
    for _,button in ipairs(loot.prepared) do
        local data=view.buttonData[button]
        local bag=B.Model.bags[data.bag]
        local item=bag and bag.slots[data.slot]
        if item and arrivals and arrivals[item] and not represented[item] and item~=data.combatLootOriginal
            and not (item.guid and loot.existingGUIDs[item.guid]) then
            local x,y=(count%loot.columns)*loot.pitch,math.floor(count/loot.columns)*loot.pitch
            if data.item~=item or data.revision~=item.revision or data.x~=x or data.y~=y or queryChanged or button:IsShown()==scrolled then
                loot.node.x,loot.node.y=x,y
                view:Bind(button,w,loot.node,item,scrolled)
            end
            count=count+1
        elseif button:IsShown() then button:Hide() end
    end
    if count==0 or scrolled then view:HideCombatLoot(w);return end
    local height=math.ceil(count/loot.columns)*loot.pitch
    if loot.content:GetHeight()~=height then loot.content:SetHeight(height) end
    local maxScroll=height-loot.pitch
    if loot.scroll:GetVerticalScroll()>maxScroll then loot.scroll:SetVerticalScroll(maxScroll) end
    if loot.visibleCount~=count then
        loot.visibleCount=count
        loot.title:SetText(count>loot.columns and loot.titleText.." · "..count or loot.titleText)
    end
    if not loot.frame:IsShown() then
        B.Appearance:SetRecentSweep(w)
        for _,label in ipairs(w.labels) do
            if label.section=="recent" and label:IsShown() then
                label:Hide();loot.replacedHeading=label;break
            end
        end
        w.scroll:ClearAllPoints();w.scroll:SetPoint("TOPLEFT",loot.frame,"BOTTOMLEFT",0,-3)
        w.scroll:SetHeight(loot.viewHeight-loot.shrink)
        w.root:SetHeight(loot.windowHeight+loot.extraHeight-loot.shrink)
        loot.frame:Show()
    end
end

local function PrepareCombinedSlots(view,w)
    local slots=w.combinedSlots
    local top=w.scroll:GetVerticalScroll()
    if slots and slots.items==w.items and slots.nodes==w.nodes and slots.top==top then return end
    if not slots then
        slots={spares={},first={},second={},drawn={}}
        w.combinedSlots=slots
    end
    local bySlot={}
    for _,button in ipairs(w.pool) do
        local data=view.buttonData[button]
        if data and button:IsShown() then bySlot[data.bag..":"..data.slot]=button end
    end
    local slotSize=w.combinedConfig.slotSize
    -- A counted vacancy represents several slots, but a native click must
    -- always address the slot that actually received the item.
    for _,items in ipairs({w.items,w.empties}) do
        for _,item in ipairs(items) do
            local key=item.bag..":"..item.slot
            if not bySlot[key] then
                local button=slots.spares[key]
                if not button then button=view:CreateItem(w,true);slots.spares[key]=button end
                local data=view.buttonData[button]
                if not data or data.size~=slotSize then view:Bind(button,w,{x=0,y=0},item,true) end
                bySlot[key]=button
            end
        end
    end
    slots.bySlot,slots.columns,slots.revision=bySlot,w.cols,B.Model.revision
    slots.items,slots.nodes,slots.top=w.items,w.nodes,top
end

local function RefreshCombinedSlots(view,w)
    local slots=w.combinedSlots
    if not w.combinedConfig or not slots or not slots.bySlot or slots.revision==B.Model.revision then return false end
    local items,empties=view:Items(w)
    local nodes,height=B.Layout:Build(items,empties,w.combinedConfig,slots.columns,w.collapsed,w.query)
    local top=w.scroll:GetVerticalScroll()
    local visible=w.scroll:GetHeight()
    local pool=w.pool==slots.first and slots.second or slots.first
    local revision=B.Model.revision
    local count=0
    for _,node in ipairs(nodes) do
        local item=node.item
        local button=slots.bySlot[item.bag..":"..item.slot]
        if button then
            if node.y+node.h>=top-42 and node.y<=top+visible+42 then
                view:Bind(button,w,node,item)
                count=count+1;pool[count]=button;slots.drawn[button]=revision
            elseif not item.empty then
                local data=view.buttonData[button]
                if data.item~=item or data.revision~=item.revision then view:Bind(button,w,data,item,true) end
            end
        end
    end
    for index=count+1,#pool do pool[index]=nil end
    for _,button in ipairs(w.pool) do if slots.drawn[button]~=revision then button:Hide() end end
    slots.normalPool=slots.normalPool or w.pool
    w.pool,w.nodes,w.totalHeight,w.items,w.empties=pool,nodes,height,items,empties
    local contentHeight=math.max(height,visible+top)
    if w.content:GetHeight()~=contentHeight then w.content:SetHeight(contentHeight) end
    slots.revision=revision
    return true
end

function V:Paint(w,transferLayout)
    if not w.open then return end
    if A.InCombat() then B.Appearance:SetRecentSweep(w);self:Patch(w);return end
    RestoreCombinedPool(w)
    w.transferButtons=nil
    local top=w.scroll:GetVerticalScroll()
    local bottom=top+w.scroll:GetHeight()
    local low,high=top-42,bottom+42
    if transferLayout and w.transferPhysical then ReuseTransferButtons(self,w,low,high) end
    local liveIndex,cacheIndex,labelIndex,alternateCount=0,0,0,0
    local transferring=w.transferPhysical and B.Actions:IsPersonalBatch()
    local slotSize=w.slotSize or B:GetConfig().slotSize
    local tradeLabel,tradeFrames,recentLabel,recentFrames
    for _,node in ipairs(w.nodes) do
        if node.y+node.h>=low and node.y<=high then
            if node.kind=="item" then
                local live=not node.item.held and (w.liveBank=="bank" and "bank" or w.id=="player" or w.id=="keyring")
                local pool
                if live then liveIndex=liveIndex+1;pool=w.pool else cacheIndex=cacheIndex+1;pool=w.cachePool end
                local index=live and liveIndex or cacheIndex
                if not pool[index] then if A.InCombat() then return end;pool[index]=self:CreateItem(w,live) end
                local button=pool[index]
                local item=node.item
                if transferring then
                    item=TransferCell(item,YUI.IsForever and w.effectiveLayout=="category",node.section,node.group)
                end
                local data=self.buttonData[button]
                if transferLayout and data and button:IsShown() and data.size==slotSize
                    and SameTransferCell(data,item) then
                    if data.x~=node.x or data.y~=node.y then
                        button:ClearAllPoints();button:SetPoint("TOPLEFT",w.content,"TOPLEFT",node.x,-node.y)
                        data.x,data.y=node.x,node.y
                    end
                    data.item=item
                else
                    self:Bind(button,w,node,item)
                    data=self.buttonData[button]
                end
                if data then
                    data.layoutSection,data.layoutGroup=node.section,node.group
                    if live and w.alternates then alternateCount=PrepareAlternateButtons(self,w,node,data,alternateCount,slotSize) end
                end
            else
                labelIndex=labelIndex+1
                local button=w.labels[labelIndex]
                if not button then
                    button=G:CreateButtonFrame(w.content,{width=100,height=18})
                    button:RegisterForClicks("LeftButtonUp","RightButtonUp")
                    button.text=Label(button,"",12);button.text:SetPoint("LEFT")
                    button.text:SetPoint("RIGHT");button.text:SetWordWrap(false)
                    button.text:SetNonSpaceWrap(false)
                    if button.text.SetMaxLines then button.text:SetMaxLines(1) end
                    local heading=button
                    button.fold=G:CreateDivider(button,{label="",height=16,collapsible=true,lineGap=8,
                        expandedSuffix=B.Appearance.expandedSuffix,collapsedSuffix=B.Appearance.collapsedSuffix,
                        expandTooltip=B:T("action.expand"),collapseTooltip=B:T("action.collapse"),onToggle=function(collapsed,owner)
                        if heading.section=="recent" then return end
                        if A.InCombat() then owner:SetCollapsed(w.collapsed[heading.section],true);return end
                        if heading.section then
                            GameTooltip:Hide()
                            w.collapsed[heading.section]=collapsed;w.nodes={};self:Layout(w,true)
                        end
                    end})
                    button.fold:SetAllPoints();B.Appearance:Text(button.fold.gui2DividerText,"heading")
                    button.fold.gui2DividerText:SetJustifyV("MIDDLE")
                    button.fold.arrow=G:CreateGlyph(button.fold,{glyph="dropdownDown",size=12,colorKey="color.text.heading"})
                    button.fold.arrow:SetPoint("LEFT",button.fold.gui2DividerText,"RIGHT",6,0)
                    local divider=button.fold
                    divider.hover=G:CreateTexture(divider,"color.control.hover","BACKGROUND")
                    divider.hover:SetPoint("TOPLEFT",-2,1);divider.hover:SetPoint("BOTTOMLEFT",-2,-1);divider.hover:SetAlpha(.18);divider.hover:Hide()
                    local enter,leave=divider:GetScript("OnEnter"),divider:GetScript("OnLeave")
                    divider:SetScript("OnEnter",function(owner)
                        if heading.section=="recent" then return end
                        owner.hover:Show();enter(owner)
                        if button.transfer then
                            GameTooltip:AddLine(B:T(w.liveBank=="bank" and "bank.group_withdraw" or "bank.group_deposit"))
                            GameTooltip:Show()
                        end
                    end)
                    divider:SetScript("OnLeave",function(owner) owner.hover:Hide();leave(owner) end)
                    divider:SetScript("OnHide",function(owner) owner.hover:Hide() end)
                    divider:SetScript("OnMouseUp",function(owner,mouse)
                        if mouse=="RightButton" and button.transfer then
                            GameTooltip:Hide();B.Deposit:TransferCategory(w,button.section)
                        elseif mouse=="LeftButton" and heading.section and heading.section~="recent" and not A.InCombat() then
                            owner:SetCollapsed(not owner:GetCollapsed())
                        end
                    end)
                    button:SetScript("OnClick",function(owner,mouse)
                        if mouse=="RightButton" and owner.transfer then
                            GameTooltip:Hide();B.Deposit:TransferCategory(w,owner.transferSection,owner.transferGroup)
                        elseif mouse=="LeftButton" and owner.section=="recent" and w.id=="player" then
                            GameTooltip:Hide();B.Actions:ClearRecent(A.GetCarryBags(false))
                        end
                    end)
                    button:SetScript("OnEnter",function(owner)
                        if owner.transfer then
                            Tooltip(owner,owner.fullText)
                            GameTooltip:AddLine(B:T(w.liveBank=="bank" and "bank.group_withdraw" or "bank.group_deposit"))
                            GameTooltip:Show()
                        elseif owner.labelClipped then Tooltip(owner,owner.fullText) end
                    end)
                    button:SetScript("OnLeave",function() GameTooltip:Hide() end)
                    button.recentTitle=G:CreateButtonFrame(divider,{width=40,height=16})
                    button.recentTitle:SetPoint("LEFT",0,0)
                    button.recentTitle:SetScript("OnClick",function(_,mouse) button:GetScript("OnClick")(button,mouse) end)
                    w.labels[labelIndex]=button
                end
                local text=node.kind=="heading" and B.Appearance:HeadingText(node.section,node.count,node.collapsed) or B.Appearance:GroupText(node.text)
                local caption=node.caption or text
                local trade=w.id=="player" and node.kind=="label" and node.text==B.Classification.tradeGroup
                local recentHeading=node.kind=="heading" and node.section=="recent"
                local recent=recentHeading and w.id=="player"
                local frames=trade and B.Appearance:TradeCaptionFrames(caption) or recent and B.Appearance:RecentCaptionFrames(caption)
                local data=self.buttonData[button]
                if not data then data={};self.buttonData[button]=data end
                if data.text~=caption or data.captionFrames~=frames then
                    button.text:SetText(trade and frames and frames[0] or caption or "")
                    button.fold:SetLabel(recent and frames and frames[0] or caption or "")
                    data.text,data.captionFrames=caption,frames
                end
                if frames and node.y<bottom and node.y+node.h>top then
                    if trade then tradeLabel,tradeFrames=button.text,frames
                    else recentLabel,recentFrames=button.fold.gui2DividerText,frames end
                end
                button.fullText=text
                button.labelClipped=node.clipped
                button.section=node.kind=="heading" and node.section or nil
                button.transferSection,button.transferGroup=node.section,node.kind=="label" and node.text or nil
                button.transfer=YUI.IsForever and B.bankOpen and (w.id=="player" or w.liveBank=="bank")
                    and node.section~=nil and node.section~="recent" and node.section~="empty"
                local width=node.w or 100
                if data.x~=node.x or data.y~=node.y or data.w~=width or data.h~=node.h then
                    button:SetSize(width,node.h);button.text:SetHeight(node.h);button:ClearAllPoints();button:SetPoint("TOPLEFT",node.x,-node.y)
                    data.x,data.y,data.w,data.h=node.x,node.y,width,node.h
                end
                if not button:IsShown() then button:Show() end
                if data.kind~=node.kind then
                    G:SetTextColorKey(button.text,node.kind=="heading" and "color.text.heading" or "color.text.secondary")
                    B.Appearance:Text(button.text,node.kind=="heading" and "heading" or "label");data.kind=node.kind
                    button.text:ClearAllPoints();button.text:SetPoint("LEFT",node.kind=="heading" and B.Appearance.headingInset or 0,0);button.text:SetPoint("RIGHT")
                    button.text:SetJustifyV(node.kind=="heading" and "MIDDLE" or "TOP")
                    button.text:SetShown(node.kind=="label")
                end
                button:EnableMouse(node.kind=="label" and (button.transfer or button.labelClipped))
                button.text:SetShown(node.kind=="label")
                button.fold:EnableMouse(node.kind=="heading" and not recentHeading)
                button.fold:SetShown(node.kind=="heading")
                if recent and not button.recentTitle.recentClearHint then
                    PrepareRecentClearHint(button.recentTitle,button.fold.gui2DividerText)
                end
                button.recentTitle:SetShown(recent)
                if data.recentHeading~=recentHeading then
                    button.fold.arrow:SetShown(not recentHeading)
                    local anchor=recent and button.recentTitle or recentHeading and button.fold.gui2DividerText or button.fold.arrow
                    button.fold.gui2DividerLine:ClearAllPoints()
                    button.fold.gui2DividerLine:SetPoint("LEFT",anchor,"RIGHT",8,0)
                    button.fold.gui2DividerLine:SetPoint("RIGHT",0,0)
                    if recentHeading then button.fold:SetCollapsed(false,true) end
                    data.recentHeading=recentHeading
                end
                local titleWidth
                if node.kind=="heading" then
                    titleWidth=B.Appearance:HeadingWidth(node.section,node.count,node.collapsed)
                    if recent then titleWidth=math.max(titleWidth,B.Appearance:TextWidth(B:T("action.clear_recent_hint"),"heading")) end
                end
                local lineShown=titleWidth~=nil and node.divider==true and width-titleWidth-8>=48
                if data.lineShown~=lineShown then button.fold.gui2DividerLine:SetShown(lineShown);data.lineShown=lineShown end
                if titleWidth then
                    local hoverWidth=math.min(width,titleWidth+4)
                    if data.hoverWidth~=hoverWidth then button.fold.hover:SetWidth(hoverWidth);data.hoverWidth=hoverWidth end
                    if recentHeading then
                        if recent then button.recentTitle:SetSize(math.min(width,titleWidth),node.h) end
                    else
                        button.fold:SetCollapsed(node.collapsed,true)
                        if data.arrowCollapsed~=node.collapsed then
                            button.fold.arrow.icon:SetRotation(node.collapsed and math.pi/2 or 0);data.arrowCollapsed=node.collapsed
                        end
                    end
                end
            end
        end
    end
    if tradeLabel or w.tradeSweep then B.Appearance:SetTradeSweep(w,tradeLabel,tradeFrames) end
    if recentLabel or w.recentSweep then B.Appearance:SetRecentSweep(w,recentLabel,recentFrames) end
    for _,entry in ipairs({{w.pool,liveIndex},{w.cachePool,cacheIndex},{w.labels,labelIndex}}) do
        for n=entry[2]+1,#entry[1] do
            local button=entry[1][n]
            if button.ybagsGuildLocate then B.GuildInventory:ReleaseHighlight(button) end
            if self.presetPreview and self.presetPreview.shown[button] then PaintPresetHighlight(self.presetPreview,w,button) end
            button:Hide();self.buttonData[button]=nil
            if nativeSlotLocks[button] then nativeSlotLocks[button]=nil end
        end
    end
    if w.alternates then
        for n=alternateCount+1,#w.alternates do
            local button=w.alternates[n]
            self.buttonData[button]=nil
            if nativeSlotLocks[button] then nativeSlotLocks[button]=nil end
        end
    end
    if YUI.IsForever and w.id=="player" and w.effectiveLayout=="category" then PrepareCombatLoot(self,w,slotSize) end
    if w.combinedConfig then PrepareCombinedSlots(self,w) end
end
function V:MarkTransferSlot(w,bag,slot)
    if not w.transferPhysical then return end
    local changes=w.transferChanges or {}
    w.transferChanges=changes
    local slots=changes[bag] or {}
    changes[bag]=slots
    slots[slot]=true
end
function V:MarkTransferWindow(updates,bag,occupiedDelta,topology,structural,changedSlots)
    local w
    if bag.kind=="bank" then w=self.windows["live-bank"]
    elseif bag.kind=="bags" then w=self.windows[bag.id==KEYRING_CONTAINER and "keyring" or "player"] end
    if not w or not w.open or updates[w]=="layout" then return end
    -- Aggregate drop targets and changes to the available slots require a new projection.
    if topology then updates[w]="layout";return end
    if changedSlots and w.transferPhysical then
        for _,slot in ipairs(changedSlots) do self:MarkTransferSlot(w,bag.id,slot) end
    end
    local category=YUI.IsForever and w.effectiveLayout=="category" and (w.liveBank=="bank" or w.id=="player")
    if not w.transferPhysical and not category then updates[w]="layout";return end
    if occupiedDelta~=0 and w.capacityStats then
        local key=bag.space=="normal" and "normal" or bag.space=="reagent" and "reagent" or "special"
        local entry=w.capacityStats[key]
        entry.used=entry.used+occupiedDelta
        if entry.freeByBag and entry.freeByBag[bag.id] then
            entry.freeByBag[bag.id]=entry.freeByBag[bag.id]-occupiedDelta
        end
        if updates[w]~="category" then updates[w]="capacity" end
    elseif not updates[w] then updates[w]="cells" end
    if category and (not w.transferPhysical or structural) then updates[w]="category" end
end
local transferLayoutInterval=.16
local function RefreshTransferCategory(view,w)
    if w.transferLayoutTimer then return false end
    local now=GetTime()
    local first=B.Actions.queue[1]
    local destination=(w.liveBank=="bank")==(first.target.kind=="bank")
    -- The source already shows cleared cells in place. It can reconcile its
    -- retained positions less frequently than the growing destination.
    local interval=destination and transferLayoutInterval or .4
    local delay=w.nextTransferLayout and w.nextTransferLayout-now or (destination and 0 or interval)
    if delay<=0 then
        w.nextTransferLayout=now+interval
        view:Layout(w,false,true)
        return true
    end
    local transfer=B.Actions.transferResult
    w.transferLayoutTimer=C_Timer.NewTimer(delay,function()
        w.transferLayoutTimer=nil
        B.Stats.timers=B.Stats.timers-1
        if B.active and w.open and transfer==B.Actions.transferResult and B.Actions:IsPersonalBatch() then
            w.nextTransferLayout=GetTime()+interval
            view:Layout(w,false,true)
        end
    end)
    B.Stats.timers=B.Stats.timers+1
    return false
end
local function PatchTransferButton(view,w,button)
    local data=view.buttonData[button]
    if data and button:IsShown() then
        local item=TransferCell(data.item,YUI.IsForever and w.effectiveLayout=="category",data.layoutSection,data.layoutGroup)
        if not SameTransferCell(data,item) then view:Bind(button,w,data,item) end
    end
end
local function VisibleTransferButtons(view,w)
    local byBag=w.transferButtons
    if byBag then return byBag end
    byBag={}
    for _,pool in ipairs({w.pool,w.cachePool}) do
        for _,button in ipairs(pool) do
            local data=view.buttonData[button]
            if data and button:IsShown() then
                local slots=byBag[data.bag] or {}
                byBag[data.bag]=slots
                slots[data.slot]=button
            end
        end
    end
    w.transferButtons=byBag
    return byBag
end
function V:PatchTransferWindows(updates)
    for w,change in pairs(updates) do
        local changes=w.transferChanges
        w.transferChanges=nil
        if change=="layout" or A.InCombat() then self:Layout(w,false)
        elseif not (change=="category" and RefreshTransferCategory(self,w)) then
            if change=="capacity" or change=="category" then self:RenderCapacity(w) end
            if w.transferPhysical and changes then
                local byBag=VisibleTransferButtons(self,w)
                for id,slots in pairs(changes) do
                    local buttons=byBag[id]
                    if buttons then
                        for slot in pairs(slots) do
                            if buttons[slot] then PatchTransferButton(self,w,buttons[slot]) end
                        end
                    end
                end
            end
        end
    end
end
function V:ShowTransferProgress(transfer)
    local w=self.windows["live-bank"]
    if not w or not w.open then return end
    w.transferTitle=w.transferTitle or w.title:GetText()
    w.title:SetText(string.format("%s  ·  %d/%d",w.transferTitle,transfer.confirmed,transfer.total))
end
function V:FinishTransferDisplay()
    local bank=self.windows["live-bank"]
    if bank and bank.transferTitle then
        bank.title:SetText(bank.transferTitle)
        bank.transferTitle=nil
    end
    for _,w in pairs(self.windows) do
        CancelTransferLayout(w)
        if B.active and w.open and (w.liveBank~="bank" or B.bankOpen) then
            local personal=YUI.IsForever and (w.id=="player" or w.liveBank=="bank")
            self:Layout(w,false,personal)
        end
    end
end
local function SwapAggregateButton(view,w,index,button,data,item)
    if not data.firstAlternate then return end
    for n=data.firstAlternate,data.lastAlternate do
        local spare=w.alternates[n]
        local binding=view.buttonData[spare]
        if binding and binding.bag==item.bag and binding.slot==item.slot then
            button:Hide()
            w.pool[index],w.alternates[n]=spare,button
            binding.combatGroup,binding.firstAlternate,binding.lastAlternate=data.combatGroup,data.firstAlternate,data.lastAlternate
            data.combatGroup,data.firstAlternate,data.lastAlternate=nil,nil,nil
            A.UpdateCooldown(spare,item)
            B.Appearance:ItemCooldownText(spare)
            return spare,binding
        end
    end
end
function V:Patch(w,structural)
    if w.liveBank then return
    elseif w.owner then
        local container=B.Cache:GetContainer(w.owner,w.kind)
        if not container then return end
        for _,button in ipairs(w.cachePool) do
            local data=self.buttonData[button]
            if data and button:IsShown() and not data.item.empty then
                local item=data.item
                local valid=true
                if item.members then
                    for index=#item.members,1,-1 do
                        local member=item.members[index]
                        local bag=container.bags[tostring(member.bag)]
                        local current=bag and bag.slots[member.slot]
                        if current and B.Classification:SameStack(current,item) then item.members[index]=current
                        else table.remove(item.members,index);w.deferred=true end
                    end
                    if w.deferred and not A.InCombat() then self:Layout(w,true);return end
                    valid=B.Layout:RefreshAggregate(item)
                    if not valid then button:Hide();w.deferred=true end
                end
                local bag=container.bags[tostring(item.bag)]
                local current=valid and (item.members and item or bag and bag.slots[item.slot])
                if current and current.itemID==data.item.itemID and current.link==data.item.link then self:Bind(button,w,{item=current,x=data.x,y=data.y}) end
            end
        end
        if w.cacheTimestamp~=container.updated then w.money:SetText(container.updated and date("%m-%d %H:%M",container.updated) or "");w.cacheTimestamp=container.updated end
        return
    end
    local inCombat=A.InCombat()
    if inCombat and structural and RefreshCombinedSlots(self,w) then return end
    for index,button in ipairs(w.pool) do
        local data=self.buttonData[button]
        if data and button:IsShown() then
            local item=data.item
            local group=data.combatGroup or item.members and item
            local current
            local preparedBags=inCombat and data.combatGroup and B.Model.bags
            if group and B.Layout:RefreshAggregate(group,B.Model.byUID,inCombat,preparedBags) then
                if data.bag==group.bag and data.slot==group.slot then current=group
                else
                    local spare,binding=SwapAggregateButton(self,w,index,button,data,group)
                    if spare then button,data,current=spare,binding,group
                    elseif not inCombat then current=group end
                end
            elseif not group then
                local bag=B.Model.bags[data.bag]
                current=bag and bag.slots[data.slot]
            end
            if current then self:Bind(button,w,data,current)
            elseif not item.empty then
                self:Bind(button,w,data,{empty=true,held=true,bag=data.bag,slot=data.slot,space=item.space})
            end
        end
    end
    if inCombat and w.id=="player" and w.effectiveLayout=="category" then PatchCombatLoot(self,w) end
end
function V:Refresh(structural,splitDisplay)
    for _,w in pairs(self.windows) do
        if w.open then
            if w.id=="player" and splitDisplay then
                self:Layout(w,false)
            elseif not (w.id=="player" and B.Actions.selection and B.Actions.selection.progressiveGroups) then
                local changed=not structural and self:ReconcileSelections(w)
                if changed then w.reflowStacks=changed end
                if structural or changed then self:Layout(w,false)
                else
                    self:Patch(w)
                    if w.id=="player" then
                        local m=B.Appearance:Metrics()
                        local height=self:RenderCurrencies(w,w.root:GetWidth()-m.left-m.right)
                        if height~=w.footerHeight then self:Layout(w,false) end
                    end
                end
            end
        elseif w.id=="player" and not w.prepared and not A.InCombat() then self:PreparePlayer()
        end
    end
end
function V:PreparePlayer()
    if not B.active or A.InCombat() then return false end
    local w=self:EnsurePlayer()
    if w.open or w.prepared then return true end
    self:ApplySkin(true);w.open=true
    local ok,message=pcall(self.Layout,self,w,true)
    w.open=false
    if not ok then error(message,0) end
    return true
end
function V:RecheckNativeSlotLocks(bag,capacity)
    if not next(nativeSlotLocks) or A.InCombat() or not self.windows.player.open then return end
    for button in pairs(nativeSlotLocks) do
        local data=self.buttonData[button]
        if not data then
            nativeSlotLocks[button]=nil
        elseif data.bag==bag and data.slot<=capacity and not data.item.held and button:IsShown()
            and A.RecheckNativeSlotLock(button,bag,data.slot) then
            nativeSlotLocks[button]=nil
        end
    end
end
function V:QueueNativeSlotLockReads()
    if not next(nativeSlotLocks) or A.InCombat() or not self.windows.player.open then return end
    local queued={}
    for button in pairs(nativeSlotLocks) do
        local data=self.buttonData[button]
        if not data then
            nativeSlotLocks[button]=nil
        elseif button:IsShown() and not data.item.held and not queued[data.bag] then
            queued[data.bag]=true
            B:MarkBag(data.bag)
        end
    end
end
function V:ShowPlayer(opener)
    if not B.active then return false end
    if A.InCombat() then
        local w=self.windows.player
        if not w or not w.prepared then return false end
        if not w.open then w.autoOpenedBy=opener end
        w.open=true;w.root:Show();self:Patch(w,true);return true
    end
    local w=self:EnsurePlayer();local wasOpen=w.open
    if not wasOpen then
        w.autoOpenedBy=opener
        w.cols=0;self:ResetRecipeStates()
        B:RefreshTimedGear()
    end
    w.open=true;w.root:Show();self:ApplySkin(true);self:RenderBagBar(w);self:Layout(w,not wasOpen)
    if not wasOpen then self:QueueNativeSlotLockReads() end
    return true
end
function V:HidePlayer(opener)
    local w=self.windows.player
    if w and (opener==nil or w.autoOpenedBy==opener) then w.root:Hide() end
end
function V:Toggle() local w=self.windows.player;if w and w.open then self:HidePlayer();return true else return self:ShowPlayer() end end
function V:HideAll()
    local player=self.windows.player
    self:ResetHelpAlert()
    if player then self:HideHelp(player) end
    if self.menu then self.menu:Hide() end
    if self.directoryPanel then self.directoryPanel:Hide() end
    if self.dialog then self.dialog:Hide() end
    if self.split then self.split:Hide() end
    for _,w in pairs(self.windows) do
        w.prepared=false
        if w.root:IsShown() then w.root:Hide() else self:ClearWindow(w) end
    end
end
function V:CloseCaches(owner)
    for _,w in pairs(self.windows) do if w.owner and (not owner or w.owner==owner) then w.root:Hide() end end
end
function V:ShowCache(owner,kind)
    if A.InCombat() then return end
    local character
    owner,character=B.Cache:Resolve(owner,kind)
    if not character then return end
    local id=owner..":"..kind
    local title=string.format(B:T("window."..kind),character.name)
    local w=self.windows[id]
    if not w then
        for oldID,candidate in pairs(self.windows) do
            if candidate.owner and not candidate.open then self.windows[oldID]=nil;self.windows[id]=candidate;w=candidate;w.id=id;w.title:SetText(title);w.collapsed={};w.query="";w.search:SetText("");w.layout=nil;break end
        end
    end
    w=w or self:NewWindow(id,title)
    w.owner,w.kind,w.open=owner,kind,true;w.root:Show();self:ApplySkin(true);self:Layout(w,true)
end
function V:ShowBank(kind) self:ShowCache(B.Cache.playerKey,kind or "bank") end
function V:BankClosed()
    local w=self.windows.player
    if w and w.open then self:Paint(w) end
end
function V:ToggleKeyring()
    if A.InCombat() then return end
    if not KEYRING_CONTAINER or not B.Model.bags[KEYRING_CONTAINER] then return end
    local w=self.windows.keyring or self:NewWindow("keyring",string.format(B:T("window.keyring"),A.PlayerName() or ""))
    if w.open then w.root:Hide();return end
    if not B:GetConfig().position.keyring then
        local player=self.windows.player
        w.root:ClearAllPoints()
        if player then w.root:SetPoint("TOPRIGHT",player.root,"TOPLEFT",-8,0) else w.root:SetPoint("CENTER") end
    end
    w.layout="single";w.open=true;w.root:Show();self:Layout(w,true)
end
