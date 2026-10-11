-- GUI2 workbench and temporary canvas input. No provider actions are forwarded.
local Designer={}
Designer.__index=Designer
local labels={Clock="clock",Stats="stats",System="system",MicroMenu="micro_menu",Professions="professions",
    Talents="talents",Teleports="teleports",Currency="gold_bags",CurrencyTracker="currency_tracker",
    SeasonCrests="season_crests",DurabilityMount="durability_mount",MeetingStone="meeting_stone",
    RaidMarkers="raid_markers",BugSack="bugsack",Shard="shard",EquipmentSets="equipment"}
local icons={Clock=134376,Stats=135884,System=132320,MicroMenu=133742,Professions=136243,Talents=237538,
    Teleports=346292,Currency=133784,CurrencyTracker=133784,SeasonCrests=135884,DurabilityMount=136241,
    MeetingStone=134419,RaidMarkers=134420,BugSack=134063,Shard=135759,EquipmentSets=135026}
local badgeColors={"color.border.accent","color.badge.orange","color.badge.green","color.badge.purple","color.state.warning"}
-- Keep adjacent toggles compact without changing provider-owned option tables.
local function CompactCheckboxes(items, width)
    local result, pending = {}, nil
    for _,item in ipairs(items)do
        if item.type=="checkbox" then
            if pending then
                local children={}
                for i,source in ipairs({pending,item})do
                    local copy={};for key,value in pairs(source)do copy[key]=value end
                    copy.width=width;children[i]=copy
                end
                result[#result]={type="row",gap=12,rowGap=8,children=children}
                pending=nil
            else
                result[#result+1]=item;pending=item
            end
        else
            pending=nil;result[#result+1]=item
        end
    end
    return result
end
function Designer.New(bridge)
    local self=setmetatable({bridge=bridge,gui=bridge.yui.GUI2,L=bridge.yui.Locale:Get("YBar"),
        rows={},overlays={},itemOverlays={},overlayPool={},itemPool={},scope="bar",selected="top",tab="layout",snap=true},Designer)
    self.options=bridge.lib.Options.New(self)
    self:Build()
    return self
end
function Designer:T(key)
    if key=="save_exit"then return self.options.C["common.save_and_exit"]end
    if key=="discard" or key=="cancel"then return self.options.C["common.cancel"]end
    return self.L["designer."..key]
end
function Designer:ModuleTitle(kind)
    if kind:sub(1,7)=="Broker:" then return kind:sub(8) end
    return labels[kind] and self.L["ybar.module."..labels[kind]] or kind
end
function Designer:InstanceTitle(id)
    local db=self.bridge:GetModel()
    local inst=db.instances[id]
    if not inst then return self:T("unloaded") end
    local title=self:ModuleTitle(inst.moduleType)
    local cap=self.bridge.adapters[inst.moduleType]
    return cap and cap.multi and title.." "..self.bridge.lib.Model.Ordinal(db,id) or title
end
function Designer:BarTitle(id)
    local bar=self.bridge:GetModel().bars[id]
    if id=="top" or id=="bottom" then return self:T(id) end
    return bar and (bar.name or id) or self:T("unplaced")
end
function Designer:BarChoices(unplaced)
    local result={}
    if unplaced then result[1]={text=self:T("unplaced"),value="unplaced"} end
    for _,id in ipairs(self.bridge:GetModel().barOrder) do result[#result+1]={text=self:BarTitle(id),value=id} end
    return result
end
function Designer:Button(parent,text,width,callback,tone)
    return self.gui.Form:CreateButton(parent,{text=text,width=width,height=28,tone=tone or "neutral",onClick=callback})
end
function Designer:SolidButton(button,token)
    button.solidToken=token
    if button.solidPaint then button.solidPaint(button);return end
    local gui=self.gui
    if gui.Form.SetButtonRelief then gui.Form:SetButtonRelief(button,"hairline")end
    local function paint(frame,hovered,pressed)
        local token=frame.solidToken
        if frame.SetBackdropColor then frame:SetBackdropColor(gui:GetColor(token))end
        gui:SetBorderColor(frame,pressed and "color.border.strong" or hovered and "color.text.primary" or token)
        frame:SetAlpha(frame.gui2Disabled and 0.48 or pressed and 0.88 or 1)
        if frame.SetTextColor then frame:SetTextColor(gui:GetColor("color.text.primary"))end
    end
    button.solidPaint=paint
    local refresh=button.RefreshTheme
    button.RefreshTheme=function(frame)if refresh then refresh(frame)end;paint(frame,frame:IsMouseOver(),false)end
    button:HookScript("OnEnter",function(frame)paint(frame,true,false)end)
    button:HookScript("OnLeave",function(frame)paint(frame,false,false)end)
    button:HookScript("OnMouseDown",function(frame)paint(frame,true,true)end)
    button:HookScript("OnMouseUp",function(frame)paint(frame,frame:IsMouseOver(),false)end)
    paint(button)
end
function Designer:InsertionAtCursor(barId)
    local bar=self.bridge:GetModel().bars[barId]
    if not bar then return end
    local x,y=GetCursorPosition();local scale=UIParent:GetEffectiveScale();x,y=x/scale,y/scale
    local vertical=bar.orientation=="vertical"
    local last
    for _,id in ipairs(bar.items)do
        local view=self.bridge.runtime.views[id]
        local frame=view and view.displayFrame
        if frame and frame:IsShown()then
            local cx,cy=frame:GetCenter()
            local factor=frame:GetEffectiveScale()/scale
            if cx and cy then
                if vertical and y>cy*factor or not vertical and x<cx*factor then return id,false end
                last=id
            end
        end
    end
    return last,true
end
function Designer:AutoScroll(scroll)
    local function update(frame)
        local bar=frame.ScrollBar
        if bar then bar:SetShown(frame:GetVerticalScrollRange()>1)end
    end
    scroll:HookScript("OnScrollRangeChanged",update)
    scroll:HookScript("OnSizeChanged",update)
    scroll:HookScript("OnShow",update)
    update(scroll)
end
function Designer:RequestCancel()
    local session=self.bridge.session
    if not session or not session:IsDirty()then if session then session:Discard()end;return end
    if not self.cancelDialog then
        local frame=self.gui.Form:CreateSaveChangesDialog(self:ModalParent(),{
            locale=self.options.C,onResolve=function(action)
                self.cancelDialog:Hide()
                if action=="save"then self:Save()
                elseif action=="discard"then self.bridge.session:Discard()end
            end})
        frame:SetScript("OnHide",function()self.modalShield:Hide()end)
        self.cancelDialog=frame
    end
    self:ModalParent():Show();self.cancelDialog:Show();self.cancelDialog:ClearAllPoints();self.cancelDialog:SetPoint("CENTER",UIParent,"CENTER",0,0)
end
function Designer:Paint(parent,key,layer)
    local texture=self.gui:CreateTexture(parent,nil,layer or "ARTWORK")
    self.gui:SetTexturePaintKey(texture,key)
    return texture
end
-- Floating windows are built once; settings controls retain the existing renderer.
function Designer:Movable(panel,handle)
    panel:SetClampedToScreen(true);panel:SetMovable(true);panel:EnableMouse(true)
    handle:EnableMouse(true);handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart",function()panel:StartMoving()end)
    handle:SetScript("OnDragStop",function()panel:StopMovingOrSizing()end)
end
function Designer:Window(width,height)
    local panel=self.gui:CreatePanel(UIParent,{width=width,height=height,
        surface="color.surface.popup",border="color.popup.border",shadow=true})
    panel:SetFrameStrata("DIALOG");panel:SetFrameLevel(120);panel:Hide()
    local head=self.gui:CreateFrame(panel,{height=48});head:SetPoint("TOPLEFT");head:SetPoint("TOPRIGHT")
    self:Movable(panel,head)
    panel.heading=self.gui:CreateText(head,"",15,"color.text.primary")
    panel.heading:SetPoint("TOPLEFT",14,-8);panel.heading:SetHeight(16);panel.heading:SetWidth(width-62);panel.heading:SetJustifyH("LEFT")
    panel.subtitle=self.gui:CreateText(head,"","font.size.md","color.text.primary")
    panel.subtitle:SetPoint("TOPLEFT",14,-29);panel.subtitle:SetWidth(width-62);panel.subtitle:SetJustifyH("LEFT")
    local close=self.gui:CreateCloseButton(head,function()panel:Hide()end);close:ClearAllPoints();close:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-12,-8);panel.close=close
    local divider=self:Paint(head,"color.border.subtle")
    divider:SetHeight(self.gui.mult or 1);divider:SetPoint("BOTTOMLEFT",14,0);divider:SetPoint("BOTTOMRIGHT",-14,0)
    return panel
end
function Designer:Near(panel,target,atCursor)
    local w,h=panel:GetWidth(),panel:GetHeight()
    local sw,sh=UIParent:GetWidth(),UIParent:GetHeight()
    if atCursor then
        local x,y=GetCursorPosition();local scale=UIParent:GetEffectiveScale();x,y=x/scale,y/scale
        local left=x+12;local bottom=y-h-12
        if left+w>sw-8 then left=x-w-12 end
        if bottom<38 then bottom=y+12 end
        panel:ClearAllPoints();panel:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",
            math.max(8,math.min(left,sw-w-8)),math.max(38,math.min(bottom,sh-h-38))+h)
        return
    end
    local function rect(frame)
        if not frame or not frame:IsShown() then return end
        local l,r,t,b=frame:GetLeft(),frame:GetRight(),frame:GetTop(),frame:GetBottom()
        if not l or not r or not t or not b then return end
        local scale=frame:GetEffectiveScale()/UIParent:GetEffectiveScale()
        return {l*scale,b*scale,r*scale,t*scale}
    end
    local anchor=rect(target) or {sw/2,sh/2,sw/2,sh/2}
    local candidates={{anchor[1],anchor[2]-h-12},{anchor[3]+12,anchor[4]-h},
        {anchor[1]-w-12,anchor[4]-h},{anchor[1],anchor[4]+12}}
    local blockers={anchor}
    for _,host in pairs(self.bridge.bars) do local r=rect(host);if r then blockers[#blockers+1]=r end end
    for _,host in ipairs({self.frame,self.help}) do local r=rect(host);if r then blockers[#blockers+1]=r end end
    local best,score
    for _,point in ipairs(candidates) do
        local x=math.max(8,math.min(point[1],sw-w-8))
        local y=math.max(38,math.min(point[2],sh-h-38))
        local cost=math.abs(x-anchor[1])+math.abs(y+h-anchor[4])
        for i,r in ipairs(blockers) do
            cost=cost+math.max(0,math.min(x+w,r[3])-math.max(x,r[1]))*
                math.max(0,math.min(y+h,r[4])-math.max(y,r[2]))*(i==1 and 100 or 2)
        end
        if not score or cost<score then best,score={x,y},cost end
    end
    panel:ClearAllPoints();panel:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",best[1],best[2]+h)
end
-- Popup transitions share the visible source's top-left, in UIParent units.
function Designer:PopupPosition()
    for _,panel in ipairs({self.quick,self.detail,self.menu,self.picker})do
        if panel and panel:IsShown()then
            local left,top=panel:GetLeft(),panel:GetTop()
            if left and top then
                local scale=panel:GetEffectiveScale()/UIParent:GetEffectiveScale()
                return {left*scale,top*scale}
            end
        end
    end
end
function Designer:PlacePopup(panel,position)
    if not position then return false end
    local scale=panel:GetEffectiveScale()/UIParent:GetEffectiveScale()
    local width,height=panel:GetWidth()*scale,panel:GetHeight()*scale
    local x=math.max(8,math.min(position[1],UIParent:GetWidth()-width-8))
    local y=math.min(UIParent:GetHeight()-8,math.max(position[2],height+8))
    panel:ClearAllPoints();panel:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",x/scale,y/scale)
    return true
end
function Designer:SelectedTarget()
    if self.liveSettings then
        local view=self.bridge.runtime.views[self.selected]
        return view and view.displayFrame or self.frame
    end
    return self.scope=="instance" and self.itemOverlays[self.selected] or self.overlays[self.selected] or self.frame
end
function Designer:ClosePopups()
    for _,panel in ipairs({self.quick,self.detail,self.picker,self.menu}) do panel:Hide();panel:StopMovingOrSizing() end
    self.insert=nil;self.pendingPlacement=nil
end
function Designer:HandleEscape()
    if not self.visible then return end
    if self.cancelDialog and self.cancelDialog:IsShown()then self.cancelDialog:Hide();return end
    if self.dialog and self.dialog:IsShown()then self.dialog:Hide();return end
    if self.syncFrame and self.syncFrame:IsShown()then self.syncFrame:Hide();return end
    if self.drag then self:StopDrag(true);return end
    for _,panel in ipairs({self.menu,self.picker,self.detail,self.quick})do
        if panel:IsShown()then panel:Hide();return end
    end
    if self.selected then self.scope,self.selected="bar",nil;self:RefreshCanvas();return end
    self:RequestCancel()
end
function Designer:Build()
    local gui=self.gui
    self.dimmer=gui:CreateFrame(UIParent,{strata="HIGH",level=900,mouse=false,hidden=true})
    self.dimmer:SetAllPoints(UIParent);self.dimmer:EnableMouse(false)
    self.dimmer:EnableKeyboard(true);self.dimmer:SetPropagateKeyboardInput(true)
    self.dimmer:SetScript("OnKeyDown",function(frame,key)
        if self.bridge:InCombat()then return end
        frame:SetPropagateKeyboardInput(key~="ESCAPE")
        if key=="ESCAPE"then self:HandleEscape()end
    end)
    self.dimmer:SetScript("OnKeyUp",function(frame)if not self.bridge:InCombat()then frame:SetPropagateKeyboardInput(true)end end)
    self.dimmer:SetScript("OnShow",function(frame)if not self.bridge:InCombat()then frame:SetPropagateKeyboardInput(true)end end)
    local shade=self:Paint(self.dimmer,"color.overlay.shadow","BACKGROUND");shade:SetAllPoints(self.dimmer)
    local panel=gui:CreatePanel(UIParent,{width=450,height=186,surface="color.surface.popup",border="color.popup.border",shadow=true})
    self.frame=panel;panel:SetFrameStrata("DIALOG");panel:SetFrameLevel(40)
    panel:SetPoint("CENTER",UIParent,"CENTER",0,0);panel:Hide()
    local header=gui:CreateFrame(panel,{height=48});header:SetPoint("TOPLEFT");header:SetPoint("TOPRIGHT")
    self:Movable(panel,header)
    local brand=self.bridge.yui.Settings.CelestialSeries
    local logo=gui:CreateIcon(header,{icon=brand and brand:GetIcon("ybar",32) or 135759,size=24,crop=false});logo:SetPoint("LEFT",12,0)
    local title=gui:CreateText(header,brand and brand:GetTitle("ybar",self:T("bars")) or "Orbit",16,"color.text.primary")
    title:SetPoint("LEFT",logo,"RIGHT",6,0)
    self.save_exitButton=self:Button(header,self:T("save_exit"),102,function()self:Save()end,"success")
    self.save_exitButton:SetPoint("RIGHT",-12,0)
    self.discardButton=self:Button(header,self:T("discard"),92,function()self:RequestCancel()end)
    self.discardButton:SetPoint("RIGHT",self.save_exitButton,"LEFT",-6,0)
    local buttons={{"new_bar",function()self:AddBar()end},{"global_settings",function()self:Select("global");self:OpenDetails()end},
        {"position_anchors",function()self:EditMode()end}}
    for index,spec in ipairs(buttons) do
        local button=self:Button(panel,self:T(spec[1]),138,spec[2]);button:SetPoint("BOTTOMLEFT",12+(index-1)*144,82)
        self:SolidButton(button,({"color.state.success","color.badge.purple","color.badge.orange"})[index])
    end
    self.state=gui:CreateText(panel,"","font.size.md","color.text.primary");self.state:SetPoint("TOPRIGHT",-12,-46)
    self.help=gui:CreateFrame(panel,{width=426,height=64})
    self.help:SetPoint("BOTTOMLEFT",12,8);self.help:Hide()
    local hint=gui:CreateText(self.help,self:T("gesture_help"),"font.size.md","color.text.primary")
    hint:SetPoint("CENTER");hint:SetWidth(426);hint:SetHeight(52);hint:SetWordWrap(true)
    self.quick=self:Window(340,292)
    self.quickContent=gui:CreateFrame(self.quick,{width=312,height=170});self.quickContent:SetPoint("TOPLEFT",14,-62)
    self.quickWidgets={}
    self.addModuleButton=self:Button(self.quick,self:T("add_module"),156,function()self:OpenPicker(self.selected)end)
    self.addModuleButton:SetPoint("BOTTOMLEFT",12,10);self:SolidButton(self.addModuleButton,"color.state.success")
    self.moreButton=self:Button(self.quick,self:T("more_actions"),136,function()self:OpenMenu(self.scope,self.selected)end)
    self.moreButton:SetPoint("BOTTOMLEFT",12,10)
    self.deleteBarButton=self:Button(self.quick,self:T("delete_bar"),136,function()self:DeleteBar(self.selected)end,"danger")
    self.deleteBarButton:SetPoint("BOTTOMLEFT",12,10);self.deleteBarButton:Hide()
    self.detailsButton=self:Button(self.quick,self:T("details"),156,function()self:OpenDetails()end)
    self.detailsButton:SetPoint("BOTTOMRIGHT",-12,10)
    self:SolidButton(self.detailsButton,"color.border.accent")
    self.detail=self:Window(480,320);self.heading=self.detail.heading
    self.tabGroups={}
    for scope,keys in pairs({instance={"contents","appearance"},bar={"appearance","layout"}}) do
        local items={};for _,key in ipairs(keys) do items[#items+1]={text=self:T(key),value=key}end
        local tabs=gui.Form:CreateUnderlineTabs(self.detail,{width=260,height=32,gap=8,equalWidth=true,fontSizeKey="font.size.lg",
            showBaseline=true,items=items,value=keys[1],set=function(value)self.tab=value;self:RenderInspector()end})
        tabs:SetPoint("TOP",self.detail,"TOP",0,-52);self.tabGroups[scope]=tabs
    end
    self.scroll=gui:CreateScrollFrame(self.detail,{childWidth=440})
    self.scroll:SetPoint("TOPLEFT",12,-90);self.scroll:SetPoint("BOTTOMRIGHT",-24,48)
    self:AutoScroll(self.scroll)
    self.content=self.scroll.child;self.content.yuiConfigScrollFrame=self.scroll
    self.content.yuiConfigAfterRender=function(content,height)
        local chrome=self.scope=="global" and 118 or 150
        local limit=math.max(240,math.min(self.tab=="appearance" and 620 or 560,UIParent:GetHeight()-88))
        self.detail:SetHeight(math.max(240,math.min(height+chrome,limit)))
        content:SetHeight(math.max(height+12,self.detail:GetHeight()-chrome))
    end
    local back=self:Button(self.detail,self:T("back_layout"),156,function()
        local scope,id=self.scope,self.selected
        if self.liveSettings then
            local ok=self.bridge:OpenDesigner()
            if ok then self:Select(scope,id,false)end
        else
            local position=self:PopupPosition()
            self.detail:Hide();self:Select(scope,id,false);self:PlacePopup(self.quick,position)
        end
    end)
    self.backButton=back
    self.detail:EnableKeyboard(true)
    self.detail:SetPropagateKeyboardInput(true)
    self.detail:SetScript("OnKeyDown",function(frame,key)
        if self.bridge:InCombat()then return end
        frame:SetPropagateKeyboardInput(not (self.liveSettings and key=="ESCAPE"))
        if self.liveSettings and key=="ESCAPE"then self:HandleEscape()end
    end)
    self.detail:HookScript("OnHide",function()if self.liveSettings then self.bridge:CloseModuleSettings()end end)
    back:SetPoint("BOTTOMRIGHT",-12,10)
    self.restoreAppearance=self:Button(self.detail,self:T("inherit_all"),160,function()self.options:RestoreAppearance(self.scope,self.selected)end)
    self.restoreAppearance:SetPoint("BOTTOMLEFT",12,10)
    self.syncAppearance=self:Button(self.detail,self:T("sync"),120,function()self:OpenSync(self.scope,self.selected)end)
    self.syncAppearance:SetPoint("LEFT",self.restoreAppearance,"RIGHT",8,0)
    local detailRule=self:Paint(self.detail,"color.border.subtle")
    detailRule:SetHeight(gui.mult or 1);detailRule:SetPoint("BOTTOMLEFT",14,46);detailRule:SetPoint("BOTTOMRIGHT",-14,46)
    self.picker=self:Window(492,520)
    local search=gui.Form:CreateEditBox(self.picker,{width=456,height=28,get=function()return self.search or ""end,
        set=function(value)self.search=value;self:RefreshLibrary()end})
    search:SetPoint("TOPLEFT",14,-56);self.searchBox=search
    self.library=gui:CreateScrollFrame(self.picker,{width=456,childWidth=456})
    self:AutoScroll(self.library)
    self.library:SetPoint("TOPLEFT",14,-94);self.library:SetPoint("BOTTOMRIGHT",-22,12)
    self.menu=self:Window(250,260);self.menuButtons={}
    self.menu:SetScript("OnHide",function()
        for _,button in pairs(self.menuButtons)do button:SetScript("OnClick",nil)end
    end)
    self.picker:SetScript("OnHide",function()
        self.insert=nil
        for _,row in ipairs(self.rows)do row.action=nil;row:Hide()end
        if self.brokerHeader then self.brokerHeader:Hide();self.brokerHeader:SetScript("OnClick",nil)end
    end)
end
function Designer:Show()
    self.visible=true
    self.dimmer:Show()
    self:FitViewport()
    self.frame:Show();self.help:Show()
    if self.bridge.yui.Settings and self.bridge.yui.Settings.Close then self.bridge.yui.Settings:Close() end
    self.bridge.yui.Event:OffOwner(self)
    self.bridge.yui.Event:On("YUI_LAYOUT_EDIT_MODE_CLOSED",function()
        if self.bridge.session and self.bridge.session.state=="editing" then self.movingInLayout=nil;self:Show() end
    end,self)
    self:Refresh()
end
function Designer:Hide()
    if self.visible==false then return end
    if self.inspectorRefresh then self.inspectorRefresh:Cancel();self.inspectorRefresh=nil end
    self.visible=false
    self:StopDrag(true)
    self:ClosePopups();self.help:Hide();self.help:StopMovingOrSizing()
    self.frame:Hide();self.frame:StopMovingOrSizing()
    self.dimmer:Hide()
    if self.cancelDialog then self.cancelDialog:Hide()end
    if self.dialog then self.dialog:Hide() end
    if self.syncFrame then self.syncFrame:Hide() end
    if self.modalShield then self.modalShield:Hide() end
    self.bridge.yui.Event:OffOwner(self)
    for _,overlay in pairs(self.overlays) do overlay:Hide();overlay.handle:Hide() end
    for _,overlay in pairs(self.itemOverlays) do overlay:Hide() end
    for _,host in pairs(self.bridge.bars) do
        if host.ybarOriginalLevel and not self.bridge:InCombat() then
            host:SetFrameLevel(host.ybarOriginalLevel)
            host:SetFrameStrata(host.ybarOriginalStrata or "MEDIUM")
        end
    end
    for _,view in pairs(self.bridge.runtime and self.bridge.runtime.views or {}) do view.module.RunConfigEdit=nil end
    self.bridge.yui.Settings:ClearConfig(self.content)
    self.quickContent.options=nil
    for _,widget in pairs(self.quickWidgets)do widget.item=nil end
    for _,row in ipairs(self.rows)do row.action=nil;row:Hide()end
        if self.brokerHeader then self.brokerHeader:Hide()end
    for _,button in pairs(self.menuButtons)do button:SetScript("OnClick",nil)end
end
function Designer:Select(scope,id,atCursor)
    self:ClosePopups();self.scope,self.selected=scope,id
    self:RefreshCanvas()
    if scope=="global" then return end
    self.quick:Show();self:RenderQuick();self:Near(self.quick,self:SelectedTarget(),atCursor~=false)
end
function Designer:OpenDetails()
    local position=self:PopupPosition()
    self.quick:Hide();self.menu:Hide();self.picker:Hide()
    self.tab=self.scope=="instance" and "contents" or "appearance"
    self.detail:Show();self:RenderInspector()
    if not self:PlacePopup(self.detail,position)then self:Near(self.detail,self:SelectedTarget(),false)end
end
function Designer:RenderQuick()
    if not self.quick:IsShown() then return end
    local db=self.bridge:GetModel()
    local options
    if self.scope=="instance" and db.instances[self.selected] then
        self.quick.heading:SetText(self:InstanceTitle(self.selected))
        local _,barId=self.bridge.lib.Model.FindBar(db,self.selected)
        self.quick.subtitle:SetText(self:BarTitle(barId).." · "..self:T("layout"))
        options=self.options:QuickInstance(self.selected)
        self.moreButton:SetText(self:T("more_actions"))
        self.moreButton:SetScript("OnClick",function()self:OpenMenu("instance",self.selected)end)
        self.moreButton:Hide();self.deleteBarButton:Hide()
        local id=self.selected
        local _,barId=self.bridge.lib.Model.FindBar(db,id)
        local function action(key,fn,tone)
            return {type="button",label=self:T(key),width=154,onClick=fn,tone=tone}
        end
        if barId then
            options[#options+1]={type="row",children={
                action("insert_before",function()self:OpenPicker(barId,id,false)end),
                action("insert_after",function()self:OpenPicker(barId,id,true)end)}}
        end
        local remove={type="row",children={}}
        if barId then remove.children[#remove.children+1]=action("remove_from_bar",function()
            self:ClosePopups();self.bridge.session:Apply(function(value)return self.bridge.lib.Model.Move(value,id,nil)end,id);self:Refresh()
        end,"danger")end
        if self.bridge.adapters[db.instances[id].moduleType]then
            remove.children[#remove.children+1]=action("delete_instance",function()self:DeleteInstance(id)end,"danger")
        end
        if #remove.children>0 then options[#options+1]=remove end
    elseif self.scope=="bar" and db.bars[self.selected] then
        self.quick.heading:SetText(self:BarTitle(self.selected));self.quick.subtitle:SetText(self:T("layout"))
        options=self.options:QuickBar(self.selected)
        if db.bars[self.selected].kind=="independent" then
            local id=self.selected
            options[#options+1]={type="button",label=self:T("delete_bar"),width=312,tone="danger",onClick=function()self:DeleteBar(id)end}
        end
        self.moreButton:Hide();self.deleteBarButton:SetShown(db.bars[self.selected].kind=="independent")
    else self.quick:Hide();return end
    self.addModuleButton:SetShown(self.scope=="bar")
    self.deleteBarButton:Hide()
    self:RenderPanelTitle(self.quick)
    self:RenderQuickControls(options)
end
function Designer:RenderPanelTitle(panel)
    local db=self.bridge:GetModel()
    panel.subtitle:Hide()
    panel.close:ClearAllPoints();panel.close:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-12,-16)
    panel.heading:ClearAllPoints();panel.heading:SetPoint("LEFT",panel,"TOPLEFT",42,-24)
    if not panel.titleIcon then
        panel.titleIcon=self.gui:CreateIconSlot(panel,{size=20,padding=0,icon=134400})
        panel.titleIcon:SetPoint("TOPLEFT",14,-14)
        panel.titleBadge=self.gui:CreateFrame(panel,{width=18,height=18})
        panel.titleBadge:SetPoint("TOPLEFT",14,-15)
        panel.titleBadge.fill=self:Paint(panel.titleBadge,badgeColors[1],"BACKGROUND")
        panel.titleBadge.fill:SetAllPoints(panel.titleBadge)
        panel.titleBadge.text=self.gui:CreateText(panel.titleBadge,"","font.size.md","color.text.primary")
        panel.titleBadge.text:SetPoint("CENTER")
    end
    panel.titleIcon:SetShown(self.scope=="instance");panel.titleBadge:SetShown(self.scope=="bar")
    if self.scope=="instance" then
        local kind=db.instances[self.selected].moduleType
        local view=self.bridge.runtime.views[self.selected];local module=view and view.module
        panel.titleIcon:SetIcon(module and module.GetSettingsIcon and module:GetSettingsIcon() or icons[kind] or 134063)
    else
        for number,id in ipairs(db.barOrder)do if id==self.selected then
            panel.titleBadge.text:SetText(tostring(number))
            self.gui:SetTexturePaintKey(panel.titleBadge.fill,badgeColors[(number-1)%#badgeColors+1]);break
        end end
    end
end
-- Quick controls are persistent: dragging a slider never rebuilds its frame.
function Designer:RenderQuickControls(options)
    self.quickContent.options=options
    for _,widget in pairs(self.quickWidgets)do widget.used=false end
    local function control(item,x,y)
        local key=item.type..":"..item.label
        local widget=self.quickWidgets[key]
        if not widget then
            if item.type=="button" then
                widget=self:Button(self.quickContent,item.label,item.width,function()end,item.tone)
                widget:SetScript("OnClick",function()if widget.item and widget.item.onClick then widget.item.onClick()end end)
            elseif item.type=="slider" then
                widget=self.gui.Form:CreateSlider(self.quickContent,{width=item.width,inline=true,inputWidth=62,min=item.min,max=item.max,step=item.step,
                    set=function(value)if widget and widget.item then widget.item.set(value)end end})
                widget.fieldLabel=self.gui:CreateText(widget,item.label,"font.size.md","color.text.primary")
                widget.fieldLabel:SetPoint("BOTTOMLEFT",widget,"TOPLEFT",0,7)
            elseif item.type=="checkbox" or item.type=="dropdown" then
                local factory=item.type=="checkbox" and "CreateCheckbox" or "CreateDropdown"
                widget=self.gui.Form[factory](self.gui.Form,self.quickContent,{width=item.width,
                    label=item.type=="checkbox" and item.label or nil,options=item.options,
                    get=function()return widget and widget.item and widget.item.get()end,
                    set=function(value)if widget and widget.item then widget.item.set(value)end end})
                if item.type=="dropdown" then
                    widget.fieldLabel=self.gui:CreateText(widget,item.label,"font.size.md","color.text.primary")
                    widget.fieldLabel:SetPoint("BOTTOMLEFT",widget,"TOPLEFT",0,7)
                end
            else
                widget=self.gui:CreateText(self.quickContent,item.label,"font.size.md","color.text.primary")
                widget:SetWidth(item.width);widget:SetWordWrap(true);widget:SetHeight(32);widget:SetJustifyH("LEFT")
            end
            self.quickWidgets[key]=widget
        end
        widget.item=item;widget.used=true;widget:ClearAllPoints();widget:SetPoint("TOPLEFT",x,-y-((item.type=="slider" or item.type=="dropdown") and 22 or 0));widget:Show()
        if item.type=="slider" then widget:SetValue(item.get(),true)
        elseif item.type=="checkbox" or item.type=="dropdown" then widget:SetValue(item.get(),true)
        elseif item.type=="button" then widget:SetSelected(item.selected==true)end
        return (item.type=="slider" or item.type=="dropdown") and 62 or item.type=="text" and 38 or 36
    end
    local y=0
    for _,item in ipairs(options)do
        if item.type=="row" then
            local x=0
            for _,child in ipairs(item.children)do control(child,x,y);x=x+child.width+4 end
            y=y+42
        else y=y+control(item,0,y)end
    end
    for _,widget in pairs(self.quickWidgets)do if not widget.used then widget:Hide();widget.item=nil end end
    self.quick:SetHeight(y+98)
end
function Designer:DeleteBar(id)
    local bar=self.bridge:GetModel().bars[id]
    if not bar or bar.kind~="independent" then return end
    self:Confirm("delete_bar_detail",function()
        self:ClosePopups()
        self.bridge.session:Apply(function(db)return self.bridge.lib.Model.DeleteBar(db,id)end)
        self.scope,self.selected="bar",nil;self:Refresh()
    end)
end
function Designer:OpenMenu(scope,id,atCursor)
    self:ClosePopups();self.scope,self.selected=scope,id;self:RefreshCanvas()
    local db,M=self.bridge:GetModel(),self.bridge.lib.Model
    local entries={}
    if scope=="instance" and db.instances[id] then
        local bar,barId,index=M.FindBar(db,id)
        if bar then
            entries[#entries+1]={"insert_before",function()self:OpenPicker(barId,id,false)end}
            entries[#entries+1]={"insert_after",function()self:OpenPicker(barId,id,true)end}
            entries[#entries+1]={"remove_from_bar",function()
                self:ClosePopups();self.bridge.session:Apply(function(value)return M.Move(value,id,nil)end,id);self:Refresh()
            end,"danger"}
        end
        local cap=self.bridge.adapters[db.instances[id].moduleType]
        if cap then entries[#entries+1]={"delete_instance",function()self:DeleteInstance(id)end,"danger"}end
        self.menu.heading:SetText(self:InstanceTitle(id))
    elseif scope=="bar" and db.bars[id] then
        local reference,after=self:InsertionAtCursor(id)
        entries[#entries+1]={"add_module",function()self:OpenPicker(id,reference,after)end}
        if db.bars[id].kind=="independent" then entries[#entries+1]={"delete_bar",function()self:DeleteBar(id)end,"danger"}end
        self.menu.heading:SetText(self:BarTitle(id))
    else return end
    entries[#entries+1]={"details",function()self:OpenDetails()end}
    for _,button in pairs(self.menuButtons)do button:Hide()end
    for i,spec in ipairs(entries) do
        local key=i..":"..(spec[3]or "neutral")
        local button=self.menuButtons[key]
        if not button then button=self:Button(self.menu,"",222,function()end,spec[3]);self.menuButtons[key]=button end
        if spec[1]=="add_module" then self:SolidButton(button,"color.state.success")
        elseif spec[1]=="details" then self:SolidButton(button,"color.border.accent")end
        button:SetText(self:T(spec[1]));button:SetScript("OnClick",spec[2]);button:SetPoint("TOPLEFT",14,-48-(i-1)*34);button:Show()
    end
    self.menu:SetHeight(60+#entries*34);self.menu:Show();self:Near(self.menu,self:SelectedTarget(),atCursor~=false)
end
function Designer:OpenPicker(barId,reference,after)
    if not self.bridge:GetModel().bars[barId] then return end
    local position=self:PopupPosition()
    self:ClosePopups();self.insert={barId=barId,reference=reference,after=after}
    self.scope,self.selected="bar",barId;self.search=""
    self.searchBox:SetValue("",true)
    self.picker.heading:SetText(self:T("insert_module"))
    self.picker.subtitle:SetText(self:BarTitle(barId).." · "..(reference and
        self:InstanceTitle(reference).." · "..self:T(after and "next" or "previous") or self:T("bar_end")))
    self.picker:Show();self:RefreshCanvas();self:RefreshLibrary()
    if not self:PlacePopup(self.picker,position)then self:Near(self.picker,self.overlays[barId],true)end
end
function Designer:DeleteInstance(id)
    if not self.bridge:GetModel().instances[id] then return end
    local _,barId=self.bridge.lib.Model.FindBar(self.bridge:GetModel(),id)
    local instance=self.bridge:GetModel().instances[id]
    local cap=self.bridge.adapters[instance.moduleType]
    self:Confirm("delete_instance_detail",function()
        self:ClosePopups()
        self.bridge.session:Apply(function(db)return self.bridge.lib.Model.DeleteInstance(db,id)end)
        self:Select("bar",barId or "top")
    end)
end
function Designer:RefreshLibrary()
    if not self.picker:IsShown() or not self.insert then return end
    local db=self.bridge:GetModel()
    local names={};for kind in pairs(self.bridge.adapters)do names[#names+1]=kind end
    table.sort(names,function(a,b)
        local ab,bb=a:sub(1,7)=="Broker:",b:sub(1,7)=="Broker:"
        if ab~=bb then return not ab end
        return self:ModuleTitle(a)<self:ModuleTitle(b)
    end)
    local count,column,y=0,0,0
    local searching=self.search and self.search~=""
    local expanded=self.brokersExpanded or searching
    local function entry(title,status,kind,id,barId)
        count=count+1
        local card=self.rows[count]
        if not card then
            card=self.gui:CreateFrame(self.library.child,{type="Button",width=148,height=102,mouse=true})
            card:RegisterForClicks("LeftButtonUp")
            self.gui:CreateBorder(card,"color.border.subtle")
            card.background=self:Paint(card,"color.surface.raised","BACKGROUND");card.background:SetAllPoints(card)
            card.icon=self.gui:CreateIconSlot(card,{size=32,padding=0,icon=134400});card.icon:SetPoint("TOP",0,-8)
            card.text=self.gui:CreateText(card,"","font.size.md","color.text.heading")
            card.text:SetPoint("TOP",0,-40);card.text:SetWidth(132);card.text:SetHeight(24);card.text:SetWordWrap(true);card.text:SetJustifyH("CENTER")
            card.badge=self.gui:CreateFrame(card,{width=14,height=14});card.badge:SetPoint("TOPLEFT",8,-65)
            card.badge.fill=self:Paint(card.badge,"color.border.accent");card.badge.fill:SetAllPoints(card.badge)
            card.badge.text=self.gui:CreateText(card.badge,"",12,"color.badge.text");card.badge.text:SetPoint("CENTER")
            card.status=self.gui:CreateText(card,"","font.size.md","color.text.secondary")
            card.status:SetHeight(16);card.status:SetWordWrap(false)
            card.actionText=self.gui:CreateText(card,"","font.size.md","color.text.primary")
            card.actionText:SetPoint("BOTTOM",0,5)
            if card.actionText.GetFont then
                local font,size=card.actionText:GetFont()
                if font and size then card.actionText:SetFont(font,size,"OUTLINE")end
            end
            card:SetScript("OnClick",function(frame)if frame.action then frame.action()end end)
            card:SetScript("OnEnter",function(frame)
                self.gui:SetBorderColor(frame,frame.actionColor);frame.actionText:Show()
                if GameTooltip then
                    GameTooltip:SetOwner(frame,"ANCHOR_RIGHT");GameTooltip:SetText(frame.text:GetText())
                    GameTooltip:AddLine(frame.description,1,1,1,true)
                    GameTooltip:AddLine(frame.status:GetText(),0.7,0.7,0.7,true)
                    GameTooltip:AddLine(frame.actionText:GetText(),1,1,1,true);GameTooltip:Show()
                end
            end)
            local function leave(frame)
                self.gui:SetBorderColor(frame,"color.border.subtle");frame.actionText:Hide()
                if GameTooltip and GameTooltip:GetOwner()==frame then GameTooltip:Hide()end
            end
            card:SetScript("OnLeave",leave)
            card:SetScript("OnHide",function(frame)leave(frame);frame.action=nil end)
            self.rows[count]=card
        end
        card:ClearAllPoints();card:SetPoint("TOPLEFT",column*154,-y);card:Show()
        card.text:SetText(title);card.status:SetText(status)
        local ordinal
        if barId then for i,value in ipairs(db.barOrder)do if value==barId then ordinal=i;break end end end
        card.badge:SetShown(ordinal~=nil);card.status:ClearAllPoints()
        if ordinal then
            card.badge.text:SetText(tostring(ordinal))
            self.gui:SetTexturePaintKey(card.badge.fill,badgeColors[(ordinal-1)%#badgeColors+1])
            card.status:SetWidth(0)
            local textWidth=math.min(card.status:GetStringWidth(),113)
            card.badge:ClearAllPoints();card.badge:SetPoint("TOPLEFT",(148-19-textWidth)/2,-65)
            card.status:SetPoint("LEFT",card.badge,"RIGHT",5,0);card.status:SetWidth(textWidth);card.status:SetJustifyH("LEFT")
        else card.status:SetPoint("TOP",0,-64);card.status:SetWidth(132);card.status:SetJustifyH("CENTER")end
        if card.status.SetTextColor then card.status:SetTextColor(self.gui:GetColor(status==self:T("unplaced") and "color.state.success" or "color.text.secondary"))end
        local module=self.bridge.ybar.RegisteredModules[kind]
        card.icon:SetIcon(module and module.GetSettingsIcon and module:GetSettingsIcon() or icons[kind] or 134063)
        card.actionColor=barId and "color.border.accent" or "color.state.success"
        card.actionText:SetText(self:T(barId and "move_here" or not id and self.bridge.adapters[kind].multi and "new_instance" or "add_short"))
        if card.actionText.SetTextColor then card.actionText:SetTextColor(self.gui:GetColor(card.actionColor))end
        local helpKey=kind:sub(1,7)=="Broker:" and "broker" or labels[kind] or "generic"
        card.description=self:T("card_help."..helpKey)
        card.action=function()self:InsertModule(kind,id)end
        card.actionText:Hide();self.gui:SetBorderColor(card,"color.border.subtle")
        if card:IsMouseOver()then card:GetScript("OnEnter")(card)end
        column=column+1;if column==3 then column=0;y=y+108 end
    end
    if self.brokerHeader then self.brokerHeader:Hide()end
    local header=false
    for _,kind in ipairs(names)do
        local broker=kind:sub(1,7)=="Broker:"
        if broker and not header then
            header=true
            if column>0 then column=0;y=y+108 end
            if not self.brokerHeader then
                self.brokerHeader=self:Button(self.library.child,"",456,function()end)
                self.brokerHeader:SetHeight(40)
            end
            local group=self.brokerHeader
            group:ClearAllPoints();group:SetPoint("TOPLEFT",0,-y);group:Show()
            group:SetText(self.L["ybar.module.broker"].."  ·  "..self:T(expanded and "collapse_group" or "expand_group"))
            group:SetScript("OnClick",function()
                self.brokersExpanded=not expanded
                if searching then self.search="";self.searchBox:SetValue("",true)end
                self:RefreshLibrary()
            end)
            y=y+48
        end
        if (not broker or expanded) and (not searching or self:ModuleTitle(kind):lower():find(self.search:lower(),1,true))then
            local cap=self.bridge.adapters[kind];local found=false
            for _,id in ipairs(db.instanceOrder)do
                if db.instances[id].moduleType==kind then
                    found=true;local _,barId=self.bridge.lib.Model.FindBar(db,id)
                    entry(self:InstanceTitle(id),self:BarTitle(barId),kind,id,barId)
                end
            end
            if cap.multi or not found then entry(self:ModuleTitle(kind),self:T(cap.multi and "multiple_instances" or "unplaced"),kind)end
        end
    end
    for i=count+1,#self.rows do self.rows[i].action=nil;self.rows[i]:Hide()end
    self.library.child:SetHeight(math.max(y+(column>0 and 108 or 0),1))
end
function Designer:InsertModule(kind,id)
    local target=self.insert
    if not target then return end
    local creating=id==nil
    local ok=self.bridge.session:Apply(function(db)
        if not db.bars[target.barId] then return false end
        local cap=self.bridge.adapters[kind];if not cap then return false end
        if id and target.reference==id then return true end
        id=id or self.bridge.lib.Model.Add(db,kind,cap.defaultConfig or {},self.bridge.adapters)
        if not id then return false,"instance-limit" end
        -- Resolve the insertion reference after removing the moved item.
        local old,oldId=self.bridge.lib.Model.FindBar(db,id)
        if creating or not old then db.instances[id].alignment="LEFT" end
        local centered=oldId==target.barId and old and old.centerInstanceId==id
        self.bridge.lib.Model.Move(db,id,nil)
        local index
        if target.reference then
            local _,owner,at=self.bridge.lib.Model.FindBar(db,target.reference)
            if owner~=target.barId then return false,"missing-reference"end
            index=at+(target.after and 1 or 0)
        end
        local conflict=kind=="BugSack" and "Broker:BugSack" or kind=="Broker:BugSack" and "BugSack"
        if conflict then for _,other in ipairs(db.instanceOrder)do
            if db.instances[other].moduleType==conflict then self.bridge.lib.Model.Move(db,other,nil)end
        end end
        local moved,reason=self.bridge.lib.Model.Move(db,id,target.barId,index)
        if moved and centered then db.bars[target.barId].centerInstanceId=id end
        return moved,reason
    end)
    if ok then
        self:Select("instance",id,false)
        -- The queued runtime refresh has not necessarily moved the view yet.
        self:Near(self.quick,self.overlays[target.barId],false)
        self.pendingPlacement=id
    else self.state:SetText(self:T("insert_failed"))end
end
function Designer:Refresh()
    if self.liveSettings then self:RenderInspector();return end
    if self:DeferInspectorWhileDragging() then return end
    if not self.visible or not self.bridge.session or self.drag then return end
    local db=self.bridge:GetModel()
    if self.scope=="instance" and not db.instances[self.selected] or self.scope=="bar" and self.selected and not db.bars[self.selected]then
        self:ClosePopups();self.scope,self.selected="bar",nil
    end
    self.state:SetText("")
    self:RefreshCanvas();self:RenderQuick();self:RenderInspector();self:RefreshLibrary()
    if self.pendingPlacement then
        local id=self.pendingPlacement;self.pendingPlacement=nil
        if self.scope=="instance" and self.selected==id and self.quick:IsShown()then
            self:Near(self.quick,self.itemOverlays[id] or self:SelectedTarget(),false)
        end
    end
end
function Designer:DeferInspectorWhileDragging()
    local picker=self.gui.ColorPicker
    if self.inspectorScope==self.scope and self.inspectorId==self.selected and self.inspectorTab==self.tab
        and picker and picker.DeferRefresh and picker:DeferRefresh(self.content,function()
            if self.visible then self:Refresh() end
        end) then
        if self.inspectorRefresh then self.inspectorRefresh:Cancel();self.inspectorRefresh=nil end
        return true
    end
    local focus=GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    local editing=false
    if self.inspectorScope==self.scope and self.inspectorId==self.selected and self.inspectorTab==self.tab then
        local parent=focus
        while parent do
            if parent==self.content then editing=true;break end
            parent=parent.GetParent and parent:GetParent()
        end
    end
    if not editing and not (IsMouseButtonDown and IsMouseButtonDown("LeftButton")) then return false end
    if not self.inspectorRefresh then
        self.inspectorRefresh=C_Timer.NewTimer(0.05,function()
            self.inspectorRefresh=nil
            if self.visible then
                if not self:DeferInspectorWhileDragging() then
                    if self.liveSettings then self:RenderInspector()else self:Refresh()end
                end
            end
        end)
    end
    return true
end
function Designer:RenderInspector()
    if not self.visible or self.drag or not self.detail:IsShown()then return end
    if self:DeferInspectorWhileDragging() then return end
    if self.inspectorRefresh then self.inspectorRefresh:Cancel();self.inspectorRefresh=nil end
    self.inspectorScope,self.inspectorId,self.inspectorTab=self.scope,self.selected,self.tab
    local options
    if self.scope=="instance" then
        if not self.bridge:GetModel().instances[self.selected]then self.detail:Hide();return end
        self.heading:SetText(self:InstanceTitle(self.selected))
        local _,barId=self.bridge.lib.Model.FindBar(self.bridge:GetModel(),self.selected)
        self.detail.subtitle:SetText(self:BarTitle(barId))
        options=self.options:Instance(self.selected,self.tab)
    elseif self.scope=="bar" then
        if not self.bridge:GetModel().bars[self.selected]then self.detail:Hide();return end
        self.heading:SetText(self:BarTitle(self.selected));self.detail.subtitle:SetText(self:T("details"))
        options=self.options:Bar(self.selected,self.tab)
    else
        self.heading:SetText(self:T("global_settings"));self.detail.subtitle:SetText(self:T("module_defaults"))
        options=self.options:Appearance("global")
    end
    if self.scope~="global" then self:RenderPanelTitle(self.detail)
    else
        if self.detail.titleIcon then self.detail.titleIcon:Hide();self.detail.titleBadge:Hide()end
        self.detail.heading:ClearAllPoints();self.detail.heading:SetPoint("TOPLEFT",14,-8);self.detail.subtitle:Show()
        self.detail.close:ClearAllPoints();self.detail.close:SetPoint("TOPRIGHT",self.detail,"TOPRIGHT",-12,-8)
    end
    self.restoreAppearance:SetText(self:T(self.scope=="bar" and "restore_global" or "restore_bar"))
    self.backButton:SetText(self:T(self.liveSettings and "edit_layout" or "back_layout"))
    self:SolidButton(self.backButton,self.liveSettings and "color.border.accent" or "color.control.bg")
    local appearance=self.tab=="appearance" and self.scope~="global"
    self.restoreAppearance:SetShown(appearance);self.syncAppearance:SetShown(appearance)
    -- Provider checkbox rows may assume the full settings-page width.
    local compact={}
    for _,item in ipairs(options)do
        local checks=item.type=="row" and item.children and #item.children>0
        if checks then
            for _,child in ipairs(item.children)do if child.type~="checkbox"then checks=false;break end end
        end
        if checks then
            for _,child in ipairs(item.children)do compact[#compact+1]=child end
        else compact[#compact+1]=item end
    end
    options=CompactCheckboxes(compact,194)
    local controls={dropdown=true,slider=true,editbox=true,color=true,button=true}
    local normalized={}
    for i,item in ipairs(options)do
        if item.type=="editbox" and item.label then normalized[#normalized+1]={type="text",label=item.label,width=400,noWrap=true} end
        if controls[item.type]then
            local copy={};for key,value in pairs(item)do copy[key]=value end
            copy.width=400;copy.inlineLabel=false
            if copy.type=="slider"then copy.inline=true;copy.inputWidth=56 end
            options[i]={type="row",gap=12,rowGap=10,children={copy}}
        end
        normalized[#normalized+1]=options[i]
    end
    options=normalized
    local required=440
    local function measure(items)
        for _,item in ipairs(items)do
            if item.type=="row" then
                local width=0
                for _,child in ipairs(item.children or {})do width=width+(child.width or 220)+(item.gap or 20)end
                required=math.max(required,width+20)
            elseif item.type=="custom" or item.type=="custom-gui" then required=math.max(required,(item.width or 520)+40)end
        end
    end
    measure(options)
    self.detail:SetWidth(required+40);self.content:SetWidth(required)
    self.heading:SetWidth(required-22);self.detail.subtitle:SetWidth(required-22)
    for _,item in ipairs(options)do
        if item.type=="divider" or item.type=="text" then item.width=math.min(item.width or required-40,required-40)end
    end
    for scope,tabs in pairs(self.tabGroups)do
        tabs:SetWidth(260);tabs:SetShown(scope==self.scope);if scope==self.scope then tabs:SetValue(self.tab,true)end
    end
    self.scroll:SetPoint("TOPLEFT",12,self.scope=="global" and -58 or -90)
    local offset=self.scroll:GetVerticalScroll()
    self.bridge.yui.Settings:ClearConfig(self.content);self.bridge.yui.Settings:RenderConfig(self.content,options)
    self.scroll:SetVerticalScroll(math.min(offset,self.scroll:GetVerticalScrollRange()))
end
function Designer:NewBarPosition()
    local obstacles={}
    for _,host in pairs(self.bridge.bars)do obstacles[#obstacles+1]=host end
    for _,panel in ipairs({self.frame,self.help,self.quick,self.detail,self.picker})do obstacles[#obstacles+1]=panel end
    local sw,sh=UIParent:GetWidth(),UIParent:GetHeight()
    for y=sh-160,120,-84 do
        for x=40,sw-310,310 do
            local free=true
            for _,host in ipairs(obstacles)do
                if host:IsShown() then
                    local scale=host:GetEffectiveScale()/UIParent:GetEffectiveScale()
                    local l,r,b,t=host:GetLeft(),host:GetRight(),host:GetBottom(),host:GetTop()
                    if l and r and b and t and x<r*scale+12 and x+270>l*scale-12 and y-32<t*scale+44 and y+32>b*scale-12 then free=false;break end
                end
            end
            if free then return x,y end
        end
    end
end
function Designer:AddBar()
    local x,y=self:NewBarPosition()
    if not x then self.state:SetText(self:T("no_free_space"));return end
    local id
    self:ClosePopups()
    local ok=self.bridge.session:Apply(function(db)
        local number=db.nextBarId or 1
        id=self.bridge.lib.Model.AddBar(db,self:T("independent").." "..number)
        if not id then return false,"bar-limit"end
        db.bars[id].placement={anchor={point="TOPLEFT",relative="UIParent",relativePoint="BOTTOMLEFT"},offset={x=x,y=y}}
        return true
    end)
    if ok then self.scope,self.selected="bar",id;self:Refresh()else self.state:SetText(self:T("insert_failed"))end
end
function Designer:Duplicate(source)
    local id
    self.bridge.session:Apply(function(db)
        local inst=db.instances[source]
        id=self.bridge.lib.Model.Add(db,inst.moduleType,inst.config,self.bridge.adapters)
        if not id then return false,"instance-limit" end
        db.instances[id].appearance=self.bridge.lib.Model.Copy(inst.appearance)
        local _,barId,index=self.bridge.lib.Model.FindBar(db,source)
        return self.bridge.lib.Model.Move(db,id,barId,index and index+1)
    end)
    if id then self:Select("instance",id) end
end
function Designer:Confirm(key,callback)
    if not self.dialog then
        local frame=self.gui:CreatePanel(self:ModalParent(),{width=400,height=154})
        frame:SetPoint("CENTER");frame:SetFrameStrata("FULLSCREEN_DIALOG");frame:EnableMouse(true)
        frame.message=self.gui:CreateText(frame,"",14);frame.message:SetPoint("TOPLEFT",18,-18);frame.message:SetWidth(360)
        local cancel=self:Button(frame,self:T("cancel"),150,function()frame:Hide()end);cancel:SetPoint("BOTTOMLEFT",18,18)
        local accept=self:Button(frame,self:T("confirm"),150,function()local action=frame.accept;frame:Hide();if action then action()end end)
        accept:SetPoint("BOTTOMRIGHT",-18,18);self.dialog=frame
        frame:SetScript("OnHide",function()frame.accept=nil;self.modalShield:Hide()end)
    end
    self:ModalParent():Show()
    self.dialog.message:SetText(self:T(key));self.dialog.accept=callback;self.dialog:Show();self:Near(self.dialog,self:SelectedTarget(),true)
end
function Designer:FitViewport()
    self.detail:SetHeight(math.max(240,math.min(self.detail:GetHeight(),UIParent:GetHeight()-88)))
    self.picker:SetHeight(math.max(220,math.min(520,UIParent:GetHeight()-88)))
end
function Designer:ModalParent()
    if not self.modalShield then
        local shield=self.gui:CreateFrame(UIParent)
        shield:SetAllPoints(UIParent);shield:SetFrameStrata("FULLSCREEN_DIALOG");shield:SetFrameLevel(100)
        shield:EnableMouse(true);shield:EnableMouseWheel(true)
        self.modalShield=shield
    end
    return self.modalShield
end
function Designer:Save()
    local ok,reason=self.bridge.session:Save()
    if not ok then self.state:SetText(self:T("save_failed").." · "..tostring(reason)) end
end
function Designer:EditMode()
    local layout=self.bridge.yui.Layout
    if not layout or self.bridge:InCombat() then return end
    self:StopDrag(true);self:ClosePopups();self.help:Hide();self.movingInLayout=true;self.dimmer:Hide()
    for _,overlay in pairs(self.overlays) do overlay:Hide();overlay.handle:Hide() end
    for _,overlay in pairs(self.itemOverlays) do overlay:Hide() end
    self.frame:Hide()
    if layout:OpenEditMode("ybar") then
        self.bridge.layoutOpened=true
        local _,barId=self.bridge.lib.Model.FindBar(self.bridge:GetModel(),self.selected)
        barId=self.scope=="bar" and self.selected or barId
        if barId and barId~="top" and barId~="bottom" then layout:SelectFrame("ybar."..barId,true) end
    else self.movingInLayout=nil;self.dimmer:Show();self.frame:Show();self.help:Show();self:RefreshCanvas() end
end
function Designer:RefreshCanvas()
    if self.liveSettings then return end
    if not self.visible or self.movingInLayout or self.bridge:InCombat() then return end
    local bridge,gui=self.bridge,self.gui
    local db=bridge:GetModel()
    local M=bridge.lib.Model
    local _,parentId=M.FindBar(db,self.selected)
    local selectedBar=self.scope=="bar" and self.selected or parentId
    local picker=gui.ColorPicker and gui.ColorPicker.frame
    local previewingBorder=self.scope=="bar" and self.tab=="appearance" and self.detail:IsShown()
        and picker and picker:IsShown()
    if picker and not self.colorPickerHooked then
        self.colorPickerHooked=true
        picker:HookScript("OnHide",function()
            if self.visible then self:RefreshCanvas() end
        end)
    end
    for id,overlay in pairs(self.overlays) do
        if not db.bars[id] then
            overlay:Hide();overlay.handle:Hide();self.overlays[id]=nil;self.overlayPool[#self.overlayPool+1]=overlay
        end
    end
    for id,overlay in pairs(self.itemOverlays) do
        local b=M.FindBar(db,id)
        if not db.instances[id] or not b then overlay:Hide() end
        if not db.instances[id] then self.itemOverlays[id]=nil;self.itemPool[#self.itemPool+1]=overlay end
    end
    for _,barId in ipairs(db.barOrder) do
        local host=bridge.bars[barId]
        if host then
            host.ybarOriginalLevel=host.ybarOriginalLevel or host:GetFrameLevel()
            host.ybarOriginalStrata=host.ybarOriginalStrata or host:GetFrameStrata()
            host:SetFrameStrata("DIALOG")
            host:SetFrameLevel(selectedBar==barId and 50 or 20)
            local overlay=self.overlays[barId]
            if not overlay then
                overlay=table.remove(self.overlayPool) or gui:CreateButtonFrame(UIParent,{width=100,height=22})
                gui:CreateBorder(overlay,"color.border.subtle")
                overlay:SetFrameStrata("DIALOG");overlay:EnableMouse(true)
                overlay:RegisterForClicks("AnyUp");overlay:RegisterForDrag("LeftButton")
                overlay:SetScript("OnClick",function(_,button)
                    if self.drag or self.suppressClick then return end
                    if button=="RightButton" then self:OpenMenu("bar",barId,true)else self:Select("bar",barId,true)end
                end)
                overlay:SetScript("OnMouseDown",function()self.suppressClick=nil end)
                overlay:SetScript("OnDragStart",function()self:StartBarDrag(barId)end)
                overlay:SetScript("OnDragStop",function()self:StopDrag()end)
                overlay.handle=overlay.handle or gui.Form:CreateButton(overlay,{text="",width=148,height=28,
                    tone="neutral",textLeftPadding=30,textRightPadding=18,contentAlign="left"})
                overlay.handle:RegisterForClicks("AnyUp")
                overlay.handle:SetScript("OnMouseDown",function()self.suppressClick=nil end)
                overlay.handle:SetScript("OnClick",function(_,button)
                    if self.drag or self.suppressClick then return end
                    if button=="RightButton"then self:OpenMenu("bar",barId,true)else self:Select("bar",barId,true)end
                end)
                overlay.handle:RegisterForDrag("LeftButton")
                overlay.handle:SetScript("OnDragStart",function()self:StartBarDrag(barId)end)
                overlay.handle:SetScript("OnDragStop",function()self:StopDrag()end)
                overlay.empty=overlay.empty or self:Button(overlay,self:T("add_module"),156,function()end)
                overlay.empty:SetPoint("CENTER")
                overlay.empty:SetScript("OnClick",function()self:OpenPicker(barId)end)
                if not overlay.badge then
                    overlay.badge=gui:CreateFrame(overlay.handle,{width=20,height=20})
                    overlay.badge:SetPoint("LEFT",4,0)
                    overlay.badge.fill=self:Paint(overlay.badge,badgeColors[1],"BACKGROUND");overlay.badge.fill:SetAllPoints(overlay.badge)
                    overlay.badge.text=gui:CreateText(overlay.badge,"",12,"color.badge.text");overlay.badge.text:SetPoint("CENTER")
                end
                self.overlays[barId]=overlay
            end
            overlay:ClearAllPoints();overlay:SetAllPoints(host)
            overlay:SetFrameLevel(selectedBar==barId and 80 or 70)
            gui:SetBorderColor(overlay,0,0,0,0)
            if not overlay.selectionOutline then
                overlay.selectionOutline=gui:CreateFrame(overlay,{mouse=false,radius=0})
                gui:CreateBorder(overlay.selectionOutline,"color.border.accent")
            end
            overlay.selectionOutline:SetAllPoints(overlay)
            overlay.selectionOutline:SetShown(selectedBar==barId and not previewingBorder)
            gui:SetBorderColor(overlay.handle,self.scope=="bar" and self.selected==barId and "color.border.accent" or "color.border.subtle")
            overlay.handle:SetText(self:BarTitle(barId))
            overlay.handle:SetFrameLevel(110)
            for number,id in ipairs(db.barOrder)do if id==barId then
                overlay.badge.text:SetText(tostring(number));gui:SetTexturePaintKey(overlay.badge.fill,badgeColors[(number-1)%#badgeColors+1]);break
            end end
            overlay.empty:SetShown(#db.bars[barId].items==0)
            overlay.handle:ClearAllPoints()
            if barId=="top" or (host:GetTop() or 0)>UIParent:GetHeight()-32 then
                overlay.handle:SetPoint("TOPLEFT",overlay,"BOTTOMLEFT",0,-2)
            else overlay.handle:SetPoint("BOTTOMLEFT",overlay,"TOPLEFT",0,2) end
            overlay.handle:SetShown(selectedBar==barId);overlay:Show()
            for _,id in ipairs(db.bars[barId].items) do
                local view=bridge.runtime.views[id]
                local target=view and view.displayFrame
                if view and view.moduleType=="System" and view.module.content
                    and view.module.content:GetParent()~=view.module.frame and view.module.content:IsShown() then
                    target=view.module.content
                end
                if target and target:IsShown() then
                    local item=self.itemOverlays[id]
                    if not item then
                        item=table.remove(self.itemPool) or gui:CreateButtonFrame(overlay,{width=50,height=20})
                        item:EnableMouse(true);item:RegisterForClicks("AnyUp");item:RegisterForDrag("LeftButton")
                        gui:CreateBorder(item,0,0,0,0)
                        item:SetScript("OnClick",function(_,button)
                            if self.drag or self.suppressClick then return end
                            if button=="RightButton" then self:OpenMenu("instance",id,true)
                            else self:Select("instance",id,true);if IsAltKeyDown and IsAltKeyDown() then self:OpenDetails() end end
                        end)
                        item:SetScript("OnDragStart",function()self:StartModuleDrag(id,item)end)
                        item:SetScript("OnDragStop",function()self:StopDrag()end)
                        item:SetScript("OnMouseDown",function()self.suppressClick=nil end)
                        self.itemOverlays[id]=item
                    end
                    item:SetParent(overlay);item:ClearAllPoints();item:SetAllPoints(target);item:SetFrameLevel(100)
                    if not item.selectedFill then
                        item.selectedFill=self:Paint(item,"color.control.active","BACKGROUND");item.selectedFill:SetAllPoints(item)
                        item.selectedFill:SetAlpha(0.2)
                    end
                    item.selectedFill:SetShown(self.scope=="instance" and self.selected==id)
                    if self.scope=="instance" and self.selected==id then gui:SetBorderColor(item,"color.text.accent") else gui:SetBorderColor(item,0,0,0,0) end
                    item:Show()
                elseif self.itemOverlays[id] then self.itemOverlays[id]:Hide() end
            end
        end
    end
end
function Designer:StartBarDrag(id)
    if self.bridge:GetModel().bars[id].kind~="independent" then return end
    local layout=self.bridge.yui.Layout
    if not layout or not layout.BeginDirectDrag then return end
    self:ClosePopups();self.scope,self.selected="bar",id
    self.suppressClick=true
    self:RefreshCanvas()
    local ok=layout:BeginDirectDrag("ybar."..id,{snap=self.snap})
    if ok then self.drag={kind="bar",id=id} end
end
-- Cursor coordinates, hit testing and the insertion marker share UIParent units.
function Designer:RestoreDragGap()
    for frame,saved in pairs(self.gapFrames or {}) do
        frame:ClearAllPoints()
        for _,point in ipairs(saved.points) do frame:SetPoint(unpack(point)) end
    end
    self.gapFrames=nil;self.gapBar=nil;self.gapIndex=nil
end
function Designer:PreviewDragGap(barId,index,target,before)
    if self.gapBar==barId and self.gapIndex==index then return end
    self:RestoreDragGap()
    if not barId then return end
    self.gapBar,self.gapIndex=barId,index
    self.gapFrames={}
    local db=self.bridge:GetModel()
    local vertical=db.bars[barId].orientation=="vertical"
    local ordinal=0
    for _,id in ipairs(db.bars[barId].items) do
        if id~=self.drag.id then
            ordinal=ordinal+1
            if ordinal==index-1 or ordinal==index then
                local view=self.bridge.runtime.views[id]
                local frame=view and view.displayFrame
                local near=true
                if target and frame and frame~=target then
                    local scale=frame:GetEffectiveScale()/UIParent:GetEffectiveScale()
                    local targetScale=target:GetEffectiveScale()/UIParent:GetEffectiveScale()
                    local edge=vertical and (before and target:GetTop() or target:GetBottom()) or (before and target:GetLeft() or target:GetRight())
                    local neighbor=vertical and (ordinal<index and frame:GetBottom() or frame:GetTop()) or (ordinal<index and frame:GetRight() or frame:GetLeft())
                    near=edge and neighbor and math.abs(edge*targetScale-neighbor*scale)<32
                end
                if frame and frame:IsShown() and near then
                    local cx,cy=frame:GetCenter()
                    local saved={points={},cx=cx,cy=cy}
                    for n=1,frame:GetNumPoints() do saved.points[n]={frame:GetPoint(n)} end
                    self.gapFrames[frame]=saved
                    local delta=ordinal<index and -10 or 10
                    frame:ClearAllPoints()
                    for _,point in ipairs(saved.points) do
                        frame:SetPoint(point[1],point[2],point[3],point[4]+(vertical and 0 or delta),point[5]+(vertical and -delta or 0))
                    end
                end
            end
        end
    end
end
function Designer:DragTarget(x,y)
    local db=self.bridge:GetModel()
    local best,bestLevel
    for _,barId in ipairs(db.barOrder) do
        local host,overlay=self.bridge.bars[barId],self.overlays[barId]
        if host and overlay and overlay:IsShown() then
            local scale=host:GetEffectiveScale()/UIParent:GetEffectiveScale()
            local l,r,t,b=host:GetLeft(),host:GetRight(),host:GetTop(),host:GetBottom()
            if l and r and t and b then
                l,r,t,b=l*scale,r*scale,t*scale,b*scale
                if barId=="top" then b=b-18 elseif barId=="bottom" then t=t+18 end
                local level=overlay:GetFrameLevel()
                if x>=l and x<=r and y>=b and y<=t and (not bestLevel or level>bestLevel) then
                    best,bestLevel=barId,level
                end
            end
        end
    end
    if not best then return end
    local vertical=db.bars[best].orientation=="vertical"
    local index,last=1,nil
    for _,id in ipairs(db.bars[best].items) do
        if id~=self.drag.id then
            local view=self.bridge.runtime.views[id]
            local frame=view and view.displayFrame
            if frame then
                local cx,cy=frame:GetCenter()
                local original=self.gapFrames and self.gapFrames[frame]
                if original then cx,cy=original.cx,original.cy end
                local scale=frame:GetEffectiveScale()/UIParent:GetEffectiveScale()
                if cx and cy and ((vertical and y>cy*scale) or (not vertical and x<cx*scale)) then
                    return best,index,frame,true
                end
                last=frame
            end
            index=index+1
        end
    end
    return best,index,last,false
end
function Designer:UpdateModuleDrag()
    if not self.drag or self.drag.kind~="instance" then return end
    local scale=UIParent:GetEffectiveScale()
    local x,y=GetCursorPosition();x,y=x/scale,y/scale
    local barId,index,target,before=self:DragTarget(x,y)
    local boundary
    if barId then
        local db=self.bridge:GetModel()
        local previous,nextId,ordinal=nil,nil,0
        for _,id in ipairs(db.bars[barId].items)do
            if id~=self.drag.id then
                ordinal=ordinal+1
                if ordinal==index-1 then previous=id end
                if ordinal==index then nextId=id;break end
            end
        end
        local direction=self.options:Alignment(self.drag.id)
        local adjacent=(direction=="RIGHT" and nextId) or previous or nextId
        local view=adjacent and self.bridge.runtime.views[adjacent]
        if direction=="RIGHT" and not nextId then boundary="end";target=nil
        elseif direction=="LEFT" and not previous then boundary="start";target=nil
        elseif view then target=view.displayFrame;before=adjacent==nextId end
    end
    self.dropBar,self.dropIndex=barId,index
    local label=barId and self:BarTitle(barId).." · "..index or self:T("drop_invalid")
    self.ghost.status:SetText(label)
    local width=math.max(110,math.min(260,math.max(self.ghost.text:GetStringWidth()+38,self.ghost.status:GetStringWidth()+16)))
    self.ghost:SetWidth(width)
    local gx=x-width/2
    local gy=y+18
    if gy+40>UIParent:GetHeight()-4 then
        gx=x-width-64;gy=y-20
        if gx<4 then gx=x+80 end
    end
    gx=math.min(gx,UIParent:GetWidth()-width-4)
    self.ghost:ClearAllPoints();self.ghost:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",math.max(4,gx),math.min(gy,UIParent:GetHeight()-44))
    self.ghost.icon:ClearAllPoints();self.ghost.icon:SetPoint("CENTER",UIParent,"BOTTOMLEFT",x,y)
    self.dropMarker:Hide();self.dropOutline:Hide()
    if boundary then self:RestoreDragGap()else self:PreviewDragGap(barId,index,target,before)end
    if not barId then return end
    local host=self.bridge.bars[barId]
    local vertical=self.bridge:GetModel().bars[barId].orientation=="vertical"
    self.dropOutline:ClearAllPoints();self.dropOutline:SetAllPoints(host);self.dropOutline:Show()
    local hostScale=host:GetEffectiveScale()/UIParent:GetEffectiveScale()
    local x,y=host:GetLeft()*hostScale,host:GetTop()*hostScale
    if boundary=="end"then
        if vertical then y=host:GetBottom()*hostScale+4 else x=host:GetRight()*hostScale-4 end
    elseif not boundary and target then
        local scale=target:GetEffectiveScale()/UIParent:GetEffectiveScale()
        local offset=before and -10 or 10
        if vertical then y=(before and target:GetTop() or target:GetBottom())*scale-offset
        else x=(before and target:GetLeft() or target:GetRight())*scale+offset end
    end
    self.dropMarker:ClearAllPoints();self.dropMarker:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",x,y)
    self.dropMarker:SetSize(vertical and host:GetWidth()*hostScale or 4,vertical and 4 or host:GetHeight()*hostScale)
    self.dropMarker:Show()
end
function Designer:StartModuleDrag(id,source)
    if self.bridge:InCombat() or self.drag then return end
    self:ClosePopups();self.suppressClick=true
    if not self.ghost then
        self.ghost=self.gui:CreatePanel(UIParent,{width=170,height=40,surface="color.surface.popup",border="color.popup.border"})
        self.ghost:SetFrameStrata("FULLSCREEN_DIALOG");self.ghost:EnableMouse(false)
        self.ghost.icon=self.gui:CreateIconSlot(UIParent,{size=30,padding=0,icon=134400})
        self.ghost.icon:SetFrameStrata("FULLSCREEN_DIALOG");self.ghost.icon:EnableMouse(false)
        self.ghost.text=self.gui:CreateText(self.ghost,"",13);self.ghost.text:SetPoint("TOPLEFT",6,-5)
        self.ghost.text:SetWidth(224);self.ghost.text:SetJustifyH("LEFT");self.ghost.text:SetWordWrap(false)
        self.ghost.status=self.gui:CreateText(self.ghost,"","font.size.md","color.text.primary");self.ghost.status:SetPoint("BOTTOMLEFT",6,4)
        self.ghost.status:SetWidth(244);self.ghost.status:SetJustifyH("LEFT");self.ghost.status:SetWordWrap(false)
        self.dropMarker=self.gui:CreateFrame(UIParent)
        self.dropMarker:SetFrameStrata("FULLSCREEN_DIALOG");self.dropMarker:EnableMouse(false)
        local fill=self:Paint(self.dropMarker,"color.border.accent");fill:SetAllPoints(self.dropMarker)
        self.dropOutline=self.gui:CreateFrame(UIParent)
        self.dropOutline:SetFrameStrata("DIALOG");self.dropOutline:SetFrameLevel(90);self.dropOutline:EnableMouse(false)
        self.gui:CreateBorder(self.dropOutline,"color.border.accent")
    end
    local kind=self.bridge:GetModel().instances[id].moduleType
    local module=self.bridge.ybar.RegisteredModules[kind]
    self.ghost.icon:SetIcon(module and module.GetSettingsIcon and module:GetSettingsIcon() or icons[kind] or 134063)
    self.ghost.text:SetText(self:InstanceTitle(id))
    self.drag={kind="instance",id=id}
    self.ghost:Show();self.ghost.icon:Show();self:UpdateModuleDrag()
    self.dragTicker=C_Timer.NewTicker(1/30,function()self:UpdateModuleDrag()end)
end
function Designer:StopDrag(cancel)
    local drag=self.drag
    if not drag then return end
    if drag.kind=="instance" and not cancel then self:UpdateModuleDrag() end
    self:RestoreDragGap()
    self.drag=nil
    if self.dragTicker then self.dragTicker:Cancel();self.dragTicker=nil end
    if drag.kind=="bar" then self.bridge.yui.Layout:EndDirectDrag(cancel)
    else
        self.ghost:Hide();self.ghost.icon:Hide();self.dropMarker:Hide();self.dropOutline:Hide()
        if not cancel and not self.bridge:InCombat() and self.dropBar then
            local barId,index=self.dropBar,self.dropIndex
            self.bridge.session:Apply(function(value)return self.bridge.lib.Model.Move(value,drag.id,barId,index)end,drag.id)
            self.scope,self.selected="instance",drag.id
        end
        self.dropBar,self.dropIndex=nil,nil
    end
    if not cancel then self:Refresh() end
end
function Designer:OpenSync(scope,id)
    local bridge,M=self.bridge,self.bridge.lib.Model
    local frame=self.syncFrame
    if not frame then
        frame=self.gui:CreatePanel(self:ModalParent(),{width=550,height=440});frame:SetPoint("CENTER")
        frame:SetFrameStrata("FULLSCREEN_DIALOG");frame:EnableMouse(true)
        frame.scroll=self.gui:CreateScrollFrame(frame,{width=500,height=360,childWidth=500})
        frame.scroll:SetPoint("TOPLEFT",12,-12);frame.scroll:SetPoint("BOTTOMRIGHT",-38,60)
        self:AutoScroll(frame.scroll)
        frame.scroll.child.yuiConfigScrollFrame=frame.scroll
        frame.scroll.child.yuiConfigAfterRender=function(child,height)
            frame:SetHeight(math.max(260,math.min(height+84,440,UIParent:GetHeight()-76)))
            child:SetHeight(math.max(height+20,frame:GetHeight()-72))
        end
        local cancel=self:Button(frame,self:T("cancel"),160,function()frame:Hide()end);cancel:SetPoint("BOTTOMLEFT",16,14)
        local apply=self:Button(frame,self:T("apply_sync"),160,function()if frame.apply then frame.apply()end end);apply:SetPoint("BOTTOMRIGHT",-16,14)
        self.syncFrame=frame
        frame:SetScript("OnHide",function()
            frame.apply=nil;self.modalShield:Hide()
            bridge.yui.Settings:ClearConfig(frame.scroll.child)
        end)
    end
    local fields,targets={},{}
    local mode="copy"
    local db=bridge:GetModel()
    local keys=scope=="bar" and {"surface","padding","appearance"} or {"font","size","outline","shadow","colorMode","color","display","iconSize","iconBackground","iconGap"}
    local cap=scope=="instance" and bridge.adapters[db.instances[id].moduleType]
    local options={{type="text",label=self:T("sync_fields"),style="header"}}
    for _,key in ipairs(keys) do
        if not cap or cap.appearance[key] then
            fields[key]=true
            options[#options+1]={type="checkbox",label=self:T(key),width=220,get=function()return fields[key]end,set=function(v)fields[key]=v end}
        end
    end
    if scope=="instance" then
        options[#options+1]={type="dropdown",label=self:T("sync_mode"),width=220,options=self.options:Choices({"copy","inherit"}),get=function()return mode end,set=function(v)mode=v end}
    end
    options[#options+1]={type="divider",label=self:T("sync_targets"),width=440,alignLeft=true}
    local candidates=scope=="bar" and db.barOrder or db.instanceOrder
    local _,sourceBar=M.FindBar(db,id)
    local function choose(which)
        for _,target in ipairs(candidates) do
            if target~=id then
                local _,barId=M.FindBar(db,target)
                targets[target]=which=="all" or which=="same_bar" and sourceBar and sourceBar==barId or false
            end
        end
        bridge.yui.Settings:ClearConfig(frame.scroll.child);bridge.yui.Settings:RenderConfig(frame.scroll.child,options)
    end
    options[#options+1]={type="row",children={
        {type="button",label=self:T("all"),width=130,onClick=function()choose("all")end},
        {type="button",label=self:T("same_bar"),width=130,disabled=scope=="bar",onClick=function()choose("same_bar")end},
        {type="button",label=self:T("clear"),width=130,onClick=function()choose("clear")end}}}
    for _,target in ipairs(candidates) do
        if target~=id then
            options[#options+1]={type="checkbox",label=scope=="bar" and self:BarTitle(target) or self:InstanceTitle(target),width=440,
                get=function()return targets[target]==true end,set=function(v)targets[target]=v end}
        end
    end
    options=CompactCheckboxes(options,214)
    frame.apply=function()
        local selectedKeys,selectedTargets={},{}
        for _,key in ipairs(keys) do if fields[key] then selectedKeys[#selectedKeys+1]=key end end
        for _,target in ipairs(candidates) do if targets[target] then selectedTargets[#selectedTargets+1]=target end end
        local skipped=0
        local ok=(bridge.session or bridge.settingsSession):Apply(function(value)
            if scope=="instance" then
                local success,detail=M.Sync(value,id,selectedTargets,selectedKeys,mode,bridge.adapters)
                if success then skipped=detail end
                return success,detail
            end
            for _,target in ipairs(selectedTargets) do
                for _,key in ipairs(selectedKeys) do value.bars[target][key]=M.Copy(value.bars[id][key]) end
            end
        end)
        if ok then
            frame:Hide()
            if skipped>0 then self:Confirm("sync_skipped",function()end) end
        end
    end
    bridge.yui.Settings:ClearConfig(frame.scroll.child);bridge.yui.Settings:RenderConfig(frame.scroll.child,options)
    self:ModalParent():Show();frame:Show();self:Near(frame,self:SelectedTarget(),true)
end
local owner=_G.YUI and _G.YUI.YBar
if owner then
    owner.LayoutLibraries=owner.LayoutLibraries or {}
    owner.LayoutLibraries.Designer=Designer
end
return Designer
