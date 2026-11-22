local YUI=_G.YUI
local B=YUI and YUI.YBags
if not B then return end
local V,G,A=B.View,YUI.GUI2,YUI.API.Bags
local function Text(parent,text,x,y)
    local label=G:CreateText(parent,text,12,"color.text.primary");label:SetPoint("TOPLEFT",x,y);label:SetJustifyH("LEFT");return label
end
local function Button(parent,text,x,y,width,callback)
    local button=B.Appearance:Button(parent,{text=text,width=width or 110,onClick=callback})
    button:SetPoint("TOPLEFT",x,y);button:SetScript("OnClick",callback);return button
end

local function StopHelpPulse(w)
    if w.helpPulse then
        w.helpPulse:Stop();w.helpPulse=nil
        w.helpGlyph:SetAlpha(1)
    end
end

function V:HideHelp(w)
    if not w.helpPanel then return end
    if w.helpPanel:IsShown() then w.helpPanel:Hide() end
    StopHelpPulse(w)
end

function V:ResetHelpAlert()
    if self.helpTimer then self.helpTimer:Cancel();self.helpTimer=nil end
    self.helpAlertPending=nil
    local w=self.windows.player
    if not w or not w.helpMark then return end
    StopHelpPulse(w)
    w.helpUnread=nil;w.helpMark:Hide()
end

function V:ClearItemUseHelp()
    self:ResetHelpAlert()
    local w=self.windows.player
    if w and w.helpPanel and w.helpPanel:IsShown() then self:RefreshHelp(w) end
end

function V:SignalItemUseHelp(confirmed)
    local w=self.windows.player
    if not B.active or not w or not w.helpMark then return end
    local alert=confirmed~=false and not w.helpUnread
    if not alert and not w.helpPanel:IsShown() then return end
    if alert then self.helpAlertPending=true end
    if self.helpTimer then return end
    -- The protected error callback only queues work on the next frame.
    self.helpTimer=C_Timer.NewTimer(0,function()
        self.helpTimer=nil
        local alertPending=self.helpAlertPending
        self.helpAlertPending=nil
        if not B.active then return end
        if w.helpPanel:IsShown() then self:RefreshHelp(w);return end
        if not alertPending then return end
        w.helpUnread=true;w.helpMark:Show()
        local animation=YUI.Animation
        if w.root:IsVisible() and animation then
            w.helpPulse=animation:Play(w.helpGlyph,{driver="native",effects={
                {type="alpha",order=1,from=1,to=.25,duration=.26},
                {type="alpha",order=2,from=.25,to=1,duration=.26},
                {type="alpha",order=3,from=1,to=.25,duration=.26},
                {type="alpha",order=4,from=.25,to=1,duration=.26},
            }})
        end
    end)
end

function V:RefreshHelp(w)
    local record,_,current=B.Diagnostics:HelpHistory()
    local title=B.pendingNativeBags and "help.switch_pending" or not record and "help.no_report" or current and "help.blocked" or "help.saved"
    w.helpPanel.status:SetText(B:T(title))
    w.helpPanel.copy:SetText(B:T(record and "help.copy_report" or "help.copy_environment"))
    w.helpPanel.environment:SetShown(record~=nil and not current)
    w.helpPanel.switch:SetEnabled(not B.pendingNativeBags)
end

function V:CreateHelp(w)
    local help=G:CreateButtonFrame(w.header,{width=22,height=22,frameLevel=w.header:GetFrameLevel()+1})
    help:SetPoint("RIGHT",w.settings,"LEFT",-1,0)
    local glyph=G:CreateText(help,"?",14,"color.text.heading");glyph:SetPoint("CENTER")
    local mark=G:CreateText(help,"•",13,"color.state.warning");mark:SetPoint("TOPRIGHT",0,2);mark:Hide()
    w.helpButton,w.helpMark,w.helpGlyph=help,mark,glyph
    help:SetScript("OnEnter",function(button)
        GameTooltip:SetOwner(button,"ANCHOR_RIGHT");GameTooltip:SetText(B:T("help.title"));GameTooltip:Show()
    end)
    help:SetScript("OnLeave",function() GameTooltip:Hide() end)

    local panel=G:CreateFrame(UIParent,{width=382,height=178,hidden=true,mouse=true})
    w.helpPanel=panel
    panel:SetFrameStrata("DIALOG");panel:SetClampedToScreen(true)
    panel:SetPoint("TOPRIGHT",help,"BOTTOMRIGHT",0,-8)
    self:RegisterEscape(panel)
    local heading=G:CreateText(panel,B:T("help.title"),14,"color.text.heading")
    heading:SetPoint("LEFT",panel,"TOPLEFT",14,-21);heading:SetJustifyH("LEFT")
    local close=B.Appearance:Button(panel,{text=B:T("action.close"),width=76,onClick=function() panel:Hide() end})
    close:SetPoint("RIGHT",panel,"TOPRIGHT",-14,-21)
    G.WindowAppearance:Register(panel,{themeProvider=function() return B:GetConfig().skin=="native" and "native" or "dark" end,
        heading=heading,role="helper",nativeLayout="Dialog",noTopBar=true,nativeBorderOverflow=true})
    local introduction=Text(panel,B:T("help.beta"),14,-41)
    introduction:SetWidth(354);introduction:SetWordWrap(true)
    panel.status=Text(panel,"",14,-77)
    panel.status:SetWidth(354);panel.status:SetWordWrap(true)
    local function ShowReport(record,session)
        YUI.Settings:ShowMultilineCopyPopup(B:T("help.copy_title"),B.Diagnostics:HelpReport(record,session))
    end
    panel.copy=Button(panel,B:T("help.copy_environment"),14,-113,173,function()
        local record,session=B.Diagnostics:HelpHistory()
        ShowReport(record,session)
    end)
    Button(panel,B:T("help.reload"),195,-113,173,function()
        YUI.Settings:ShowConfirmPopup(B:T(A.InCombat() and "help.reload_combat" or "help.reload_confirm"),function()
            YUI.API.Frame.ReloadUI()
        end,{titleText=B:T("help.reload"),ownerFrame=panel,dismissWithOwner=true})
    end)
    panel.switch=Button(panel,B:T("help.switch"),14,-141,173,function()
        YUI.Settings:ShowConfirmPopup(B:T(A.InCombat() and "help.switch_combat" or "help.switch_confirm"),function()
            B:RequestNativeBags()
            if panel:IsShown() then self:RefreshHelp(w) end
        end,{titleText=B:T("help.switch"),ownerFrame=panel,dismissWithOwner=true})
    end)
    panel.environment=Button(panel,B:T("help.copy_environment"),195,-141,173,function() ShowReport() end)

    help:SetScript("OnClick",function()
        if panel:IsShown() then panel:Hide();return end
        self:ResetHelpAlert()
        self:RefreshHelp(w)
        G.WindowAppearance:Refresh(panel);panel:Show()
    end)
end

local function MenuOutsideClick()
    local menu=V.menu
    if not menu or not menu:IsShown() or menu:IsMouseOver() then return end
    if menu.owner and menu.owner~=UIParent and menu.owner:IsMouseOver() then return end
    menu:Hide()
end
local function CompactIconRows(rows)
    local hasIcon=false
    for _,row in ipairs(rows) do
        if not row.action or row.checked~=nil then return false end
        if row.icon then hasIcon=true end
    end
    return hasIcon
end
local function StyleRowHighlight(highlight,native)
    if native then
        highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        highlight:SetBlendMode("ADD")
    else
        highlight:SetColorTexture(G:GetColor("color.control.hover"))
        highlight:SetBlendMode("BLEND")
    end
end
local function RefreshMenuHighlights(menu)
    local native=B:GetConfig().skin=="native"
    for n=1,menu.rowCount or 0 do
        StyleRowHighlight(menu.rows[n].menuHighlight,native)
    end
end
local function MenuRowEnter(button)
    button.menuHighlight:SetShown(button.action~=nil and button:IsEnabled())
end
local function MenuRowLeave(button)
    button.menuHighlight:Hide()
end
function V:Menu(owner,rows,outside,fitText,actionContext)
    if A.InCombat() then return end
    if self.directoryPanel then self.directoryPanel:Hide() end
    if not self.menu then
        self.menu=G:CreateFrame(UIParent,{width=240,height=100,hidden=true,mouse=true})
        self.menu:SetFrameStrata("FULLSCREEN_DIALOG");self.menu.rows={}
        self.menu.scroll=G:CreateFrame(self.menu,{type="ScrollFrame",width=220,height=100})
        self.menu.content=G:CreateFrame(self.menu.scroll,{width=220,height=100});self.menu.scroll:SetScrollChild(self.menu.content)
        self.menu.scroll:SetScript("OnMouseWheel",function(frame,delta)
            frame:SetVerticalScroll(math.max(0,math.min(frame:GetVerticalScroll()-delta*50,math.max(0,(self.menu.contentHeight or 0)-frame:GetHeight()))))
        end)
        self.menu.scroll:EnableMouseWheel(true)
        self.menu:SetScript("OnShow",function(menu)
            YUI.Event:On("GLOBAL_MOUSE_DOWN",MenuOutsideClick,menu);menu.listening=true;B.Stats.listeners=B.Stats.listeners+1
        end)
        self.menu:SetScript("OnHide",function(menu)
            YUI.Event:OffOwner(menu)
            if menu.listening then B.Stats.listeners=math.max(0,B.Stats.listeners-1);menu.listening=nil end
            menu.owner,menu.actionContext=nil,nil
            for _,button in ipairs(menu.rows) do button.action=nil;button.menuHighlight:Hide() end
        end)
        self:RegisterEscape(self.menu)
        G.WindowAppearance:Register(self.menu,{themeProvider=function() return B:GetConfig().skin=="native" and "native" or "dark" end,
            role="helper",nativeLayout="Dialog",noTopBar=true,onRefresh=RefreshMenuHighlights})
    end
    local menu=self.menu
    menu.owner,menu.actionContext=owner,actionContext;menu:ClearAllPoints()
    local width=fitText and 0 or 240
    local valueWidth=0
    local compact=fitText and CompactIconRows(rows)
    local margin=compact and 6 or 10
    local rowHeight=(compact or rows[1] and rows[1].valueText) and 22 or 26
    menu.scroll:ClearAllPoints();menu.scroll:SetPoint("TOPLEFT",margin,-9)
    menu:SetClampedToScreen(true)
    for n,row in ipairs(rows) do
        local button=menu.rows[n]
        if not button then
            button=G:CreateButtonFrame(menu.content,{width=220,height=26})
            button.text=Text(button,"",8,-4);button.text:SetJustifyH("LEFT");button.text:SetWordWrap(false)
            button.check=G:CreateTexture(button,nil,"ARTWORK");button.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            button.check:SetSize(13,13);button.check:SetPoint("LEFT",7,0);button.check:Hide()
            button.menuHighlight=G:CreateTexture(button,nil,"BACKGROUND")
            button.menuHighlight:SetAllPoints();button.menuHighlight:Hide()
            button:SetScript("OnEnter",MenuRowEnter)
            button:SetScript("OnLeave",MenuRowLeave)
            button:SetScript("OnHide",MenuRowLeave)
            button:SetScript("OnClick",function(self)
                local action,context=self.action,menu.actionContext
                if action then
                    menu:Hide()
                    if context then action(context) else action() end
                end
            end);menu.rows[n]=button
        end
        button:ClearAllPoints();button:SetPoint("TOPLEFT",0,-(n-1)*rowHeight)
        button:SetHeight(rowHeight)
        button.text:SetText(row.text);button.action=row.action;button:SetEnabled(row.action~=nil)
        button.check:SetShown(row.checked==true)
        local iconInset=(compact or row.valueText and row.checked==nil) and 6 or 25
        if row.icon then
            if not button.icon then
                button.icon=G:CreateIconSlot(button,{size=16,variant="bare",shape="roundedSquare",border="none",zoom=.09,animate=false})
                button.icon:EnableMouse(false)
            end
            button.icon:ClearAllPoints();button.icon:SetPoint("LEFT",iconInset,0)
            B.Appearance:IdentityIcon(button.icon,row.icon,.09);button.icon:Show()
        elseif button.icon then button.icon:Hide() end
        if row.valueText then
            if not button.value then
                button.value=G:CreateText(button,"",12,"color.text.secondary")
                button.value:SetPoint("RIGHT",-8,0);button.value:SetJustifyH("RIGHT");button.value:SetWordWrap(false)
            end
            button.value:SetWidth(0);button.value:SetText(row.valueText);button.value:Show()
            valueWidth=math.max(valueWidth,math.ceil(button.value:GetStringWidth()))
        elseif button.value then button.value:Hide() end
        local inset=compact and iconInset+20 or row.icon and iconInset+22 or row.checked~=nil and 25 or 9
        button.textInset=inset
        button.text:ClearAllPoints();button.text:SetPoint("LEFT",inset,0)
        if fitText then
            button.text:SetWidth(0)
            width=math.max(width,math.ceil(button.text:GetStringWidth())+inset+2*margin+10)
        end
        G:SetTextColorKey(button.text,row.action and "color.text.primary" or "color.text.secondary");button:Show()
        button.menuHighlight:SetShown(row.action~=nil and menu:IsShown() and button:IsMouseOver())
    end
    for n=#rows+1,#menu.rows do menu.rows[n].action=nil;menu.rows[n]:Hide() end
    local valueSpace=valueWidth>0 and valueWidth+6 or 0
    if fitText then width=math.min(math.max(80,width+valueSpace),UIParent:GetWidth()-16) end
    local rowWidth=width-2*margin
    menu:SetWidth(width);menu.scroll:SetWidth(rowWidth);menu.content:SetWidth(rowWidth)
    for n=1,#rows do
        local button=menu.rows[n]
        button:SetWidth(rowWidth)
        button.text:SetWidth(math.max(1,rowWidth-10-button.textInset-(rows[n].valueText and valueSpace or 0)))
        if rows[n].valueText then button.value:SetWidth(valueWidth) end
    end
    local left=outside and outside:GetLeft()
    if left and left>=width+8 then menu:SetPoint("TOPRIGHT",outside,"TOPLEFT",-8,0)
    elseif outside and outside:GetRight() and UIParent:GetWidth()-outside:GetRight()>=width+8 then menu:SetPoint("TOPLEFT",outside,"TOPRIGHT",8,0)
    elseif outside then menu:SetPoint("TOPLEFT",outside,"BOTTOMLEFT",0,-6)
    else menu:SetPoint("TOPLEFT",owner,"BOTTOMLEFT",0,-4) end
    menu.rowCount=#rows
    menu.contentHeight=#rows*rowHeight
    local height=math.min(menu.contentHeight,UIParent:GetHeight()-50)
    menu.content:SetHeight(math.max(1,menu.contentHeight));menu.scroll:SetHeight(math.max(1,height));menu.scroll:SetVerticalScroll(0)
    menu:SetHeight(height+18);G.WindowAppearance:Refresh(menu);menu:Show()
end
function V:Dialog(title,fields,confirm,buttonText,preview)
    if A.InCombat() then return end
    if not self.dialog then
        local f=G:CreateFrame(UIParent,{width=390,height=220,hidden=true,mouse=true})
        f:SetPoint("CENTER");f:SetFrameStrata("FULLSCREEN_DIALOG");f.inputs={};self.dialog=f
        f.title=Text(f,"",18,-12);f.title:SetWidth(354);f.title:SetJustifyH("CENTER")
        f.previewText=Text(f,"",14,-120)
        f.submit=Button(f,"",14,-170,170,function()
            local values={}
            for n=1,f.count do values[n]=f.inputs[n].edit:GetText() end
            local callback=f.confirm
            if callback and callback(values)~=false then f:Hide() end
        end)
        f.cancel=Button(f,B:T("action.cancel"),200,-170,170,function() f:Hide() end)
        f:SetScript("OnHide",function() f.confirm=nil;f.preview=nil;for _,field in ipairs(f.inputs) do field.edit:ClearFocus() end end)
        self:RegisterEscape(f)
        G.WindowAppearance:Register(f,{themeProvider=function() return B:GetConfig().skin=="native" and "native" or "dark" end,heading=f.title,role="helper",noTopBar=true})
    end
    local f=self.dialog
    f.preview=nil;f.title:SetText(title);f.count=#fields;f.confirm=confirm
    for n,field in ipairs(fields) do
        if not f.inputs[n] then
            local edit=B.Appearance:Edit(f,{width=210});edit:SetPoint("TOPLEFT",156,-42-(n-1)*34)
            f.inputs[n]={edit=edit,label=Text(f,"",14,-43-(n-1)*34)}
        end
        local control=f.inputs[n];control.label:SetText(field.label);control.edit:SetText(tostring(field.value or ""));control.edit:Show();control.label:Show()
        control.edit:SetNumeric(field.numeric==true);control.edit:SetMaxLetters(field.max or 2048)
        control.edit:SetScript("OnEscapePressed",function() f:Hide() end)
        control.edit:SetScript("OnTextChanged",function()
            if not f.preview then return end
            local values={};for index=1,f.count do values[index]=f.inputs[index].edit:GetText() end
            local text,valid=f.preview(values)
            f.previewText:SetText(text);f.submit:SetEnabled(valid==true)
        end)
    end
    for n=#fields+1,#f.inputs do f.inputs[n].edit:Hide();f.inputs[n].label:Hide() end
    local y=-44-#fields*34
    f.previewText:ClearAllPoints();f.previewText:SetPoint("TOPLEFT",14,y)
    f.previewText:SetShown(preview~=nil)
    if preview then y=y-28 end
    f.submit:ClearAllPoints();f.submit:SetPoint("TOPLEFT",14,y);f.submit:SetText(buttonText or B:T("action.confirm"))
    f.cancel:ClearAllPoints();f.cancel:SetPoint("TOPLEFT",200,y)
    f:SetHeight(-y+42);f.preview=preview;f.submit:SetEnabled(true)
    if preview and f.inputs[1] then f.inputs[1].edit:GetScript("OnTextChanged")() end
    G.WindowAppearance:Refresh(f);f:Show()
end
local directoryRowHeight=30
function V:Directory(owner)
    if A.InCombat() then return end
    if self.directoryPanel and self.directoryPanel:IsShown() then self.directoryPanel:Hide();return end
    if self.menu then self.menu:Hide() end
    if not self.directoryPanel then
        local panel=G:CreateFrame(UIParent,{width=292,height=140,hidden=true,mouse=true})
        self.directoryPanel=panel;panel.rows={};panel.tabs={};panel.kind="bags"
        panel:SetFrameStrata("FULLSCREEN_DIALOG");panel:SetClampedToScreen(true)
        panel.header=G:CreateFrame(panel,{width=292,height=20})
        panel.title=G:CreateText(panel.header,B:T("action.offline"),13,"color.text.heading")
        panel.close=G:CreateButtonFrame(panel.header,{template="UIPanelCloseButton",width=22,height=22,frameLevel=panel.header:GetFrameLevel()+1})
        panel.close:SetScript("OnClick",function() panel:Hide() end)
        panel.content=G:CreateFrame(panel,{width=268,height=100,mouseWheel=true})
        panel.scroll=G:CreateVirtualScrollBar(panel,{width=10,onFirstIndexChanged=function(first)
            panel.first=first;self:PaintDirectory()
        end})
        panel.content:SetScript("OnMouseWheel",function(_,delta)
            if panel.scroll:IsShown() then panel.scroll:SetScrollState(panel.first-delta*3,#panel.entries,panel.visible) end
        end)
        panel.empty=Text(panel.content,B:T("cache.none"),8,-12)
        for n,kind in ipairs({"bags","bank","shared","guild"}) do
            local tab=G:CreateButtonFrame(panel,{width=64,height=24});panel.tabs[n]=tab;tab.kind=kind
            tab:SetPoint("TOPLEFT",12+(n-1)*67,-32)
            tab.text=G:CreateText(tab,B:T("directory."..kind),12,"color.text.secondary");tab.text:SetAllPoints()
            tab.line=G:CreateTexture(tab,"color.text.heading","OVERLAY");tab.line:SetHeight(2);tab.line:SetPoint("BOTTOMLEFT",3,0);tab.line:SetPoint("BOTTOMRIGHT",-3,0)
            B.Appearance:Hover(tab)
            tab:SetScript("OnClick",function(button) panel.kind=button.kind;panel.first=1;self:RenderDirectory() end)
        end
        panel:SetScript("OnShow",function()
            YUI.Event:On("GLOBAL_MOUSE_DOWN",function()
                if not panel:IsMouseOver() and not (panel.owner and panel.owner:IsMouseOver()) then panel:Hide() end
            end,panel)
            panel.listening=true;B.Stats.listeners=B.Stats.listeners+1
        end)
        panel:SetScript("OnHide",function()
            YUI.Event:OffOwner(panel)
            if panel.listening then B.Stats.listeners=math.max(0,B.Stats.listeners-1);panel.listening=nil end
            panel.owner,panel.entries=nil,nil
            for _,row in ipairs(panel.rows) do row.key=nil;row.rowHighlight:Hide() end
        end)
        self:RegisterEscape(panel)
        G.WindowAppearance:Register(panel,{themeProvider=function() return B:GetConfig().skin=="native" and "native" or "dark" end,
            heading=panel.title,role="helper",noTopBar=true,nativeBorderOverflow=true,onRefresh=function(frame)
                local native=B:GetConfig().skin=="native"
                for _,row in ipairs(frame.rows) do StyleRowHighlight(row.rowHighlight,native) end
            end})
    end
    local panel=self.directoryPanel;panel.owner=owner;panel.first=1;panel:ClearAllPoints()
    local root=self.windows.player.root
    if root:GetLeft()>=300 then panel:SetPoint("TOPRIGHT",root,"TOPLEFT",-8,0)
    else panel:SetPoint("TOPLEFT",root,"TOPRIGHT",8,0) end
    self:RenderDirectory();G.WindowAppearance:Refresh(panel);panel:Show()
end
function V:RenderDirectory()
    local panel=self.directoryPanel
    if not panel.owner then return end
    local entries={}
    for _,entry in ipairs(B.Cache:Directory(panel.kind)) do
        if B.Cache:GetContainer(entry.key,panel.kind) then entries[#entries+1]=entry end
    end
    local available={bags=true,bank=true}
    for _,kind in ipairs({"shared","guild"}) do available[kind]=#B.Cache:Directory(kind)>0 end
    local m=B.Appearance:Metrics();local tabIndex=0
    for _,tab in ipairs(panel.tabs) do
        tab:SetShown(available[tab.kind]==true);tab.line:SetShown(tab.kind==panel.kind)
        if available[tab.kind] then
            tab:ClearAllPoints();tab:SetPoint("TOPLEFT",m.left+tabIndex*58,-m.headerTop-m.headerHeight-6);tab:SetSize(54,24);tabIndex=tabIndex+1
        end
        G:SetTextColorKey(tab.text,tab.kind==panel.kind and "color.text.heading" or "color.text.secondary")
    end
    local top=m.headerTop+m.headerHeight+32
    local width=math.max(244,m.left+m.right+tabIndex*58)
    local visible=math.min(12,math.max(1,math.floor((UIParent:GetHeight()-top-m.bottom-32)/directoryRowHeight)))
    panel.entries,panel.visible=entries,visible
    panel.first=math.max(1,math.min(panel.first,#entries-visible+1))
    local height=math.max(1,math.min(#entries,visible))*directoryRowHeight
    local contentWidth=width-m.left-m.right-(#entries>visible and 14 or 0)
    panel:SetSize(width,top+height+m.bottom);B.Appearance:LayoutHeader(panel,width);panel.title:SetWidth(width-64)
    panel.content:ClearAllPoints();panel.content:SetPoint("TOPLEFT",m.left,-top);panel.content:SetSize(contentWidth,height)
    panel.scroll:ClearAllPoints();panel.scroll:SetPoint("TOPRIGHT",-m.right,-top);panel.scroll:SetHeight(height)
    panel.scroll:SetScrollState(panel.first,#entries,visible,true)
    self:PaintDirectory()
end
function V:PaintDirectory()
    local panel=self.directoryPanel
    local entries=panel.entries
    if not entries then return end
    local count=math.min(panel.visible,#entries-panel.first+1)
    for n=1,count do
        local index=panel.first+n-1
        local entry=entries[index]
        local row=panel.rows[n]
        if not row then
            row=G:CreateButtonFrame(panel.content,{width=220,height=directoryRowHeight});panel.rows[n]=row
            row:SetPoint("TOPLEFT",0,-(n-1)*directoryRowHeight)
            row.portrait=B.Appearance:Portrait(row,24);row.portrait:SetPoint("LEFT",4,0)
            row.classIcon=B.Appearance:ClassIconSlot(row,14)
            row.classIcon:SetPoint("LEFT",34,0)
            row.stripe=G:CreateTexture(row,"color.control.hover","BACKGROUND");row.stripe:SetAllPoints();row.stripe:SetAlpha(.08)
            row.name=G:CreateText(row,"",13,"color.text.primary");row.name:SetJustifyH("LEFT");row.name:SetWordWrap(false)
            G:ApplyFontAppearance(row.name,{size=13,outline="shadow"})
            row.check=G:CreateTexture(row,nil,"OVERLAY");row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check");row.check:SetSize(16,16);row.check:SetPoint("RIGHT",-4,0)
            row.rowHighlight=G:CreateTexture(row,nil,"BORDER")
            row.rowHighlight:SetAllPoints(row);row.rowHighlight:Hide()
            StyleRowHighlight(row.rowHighlight,B:GetConfig().skin=="native")
            row:SetScript("OnEnter",function(button)
                button.rowHighlight:Show()
                if button.name.IsTruncated and button.name:IsTruncated() then
                    GameTooltip:SetOwner(button,"ANCHOR_RIGHT");GameTooltip:SetText(button.name:GetText());GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave",function(button) button.rowHighlight:Hide();GameTooltip:Hide() end)
            row:SetScript("OnHide",function(button) button.rowHighlight:Hide() end)
            row:SetScript("OnClick",function(button)
                local key,kind=button.key,panel.kind;panel:Hide()
                if key==B.Cache.playerKey and kind=="bags" then self:ShowPlayer();self:FocusWindow(self.windows.player)
                else self:ShowCache(key,kind) end
            end)
        end
        local key,character=entry.key,entry.data
        local race,_,r,g,b=A.CharacterAppearance(character)
        B.Appearance:IdentityIcon(row.portrait,entry.kind and (entry.kind=="guild" and 133784 or 133785) or race and "atlas:"..race or 133785,.03)
        local hasClass=not entry.kind and B.Appearance:ClassIcon(row.classIcon,character.classFile)
        row.classIcon:SetShown(hasClass==true);row.stripe:SetShown(index%2==0)
        row.nameLeft=hasClass and 54 or 34
        row.name:ClearAllPoints();row.name:SetPoint("LEFT",row.nameLeft,0)
        local suffix=entry.kind=="shared" and B:T("cache.local_account")
        row.name.gui2ColorKey=nil;row.name:SetTextColor(r,g,b,1);row.name:SetText(character.name..(suffix and suffix~="" and " "..suffix or ""));row.key=key
        row:SetWidth(panel.content:GetWidth());row.name:SetWidth(panel.content:GetWidth()-row.nameLeft-24)
        local window=key==B.Cache.playerKey and panel.kind=="bags" and self.windows.player or self.windows[key..":"..panel.kind]
        row.check:SetShown(window and window.open==true or false);row:Show()
    end
    for n=count+1,#panel.rows do panel.rows[n].key=nil;panel.rows[n]:Hide() end
    panel.empty:SetShown(count==0)
end
function V:ItemMenu(owner,item)
    B.Actions:CancelDelete()
    local c=B:GetConfig();local id=tostring(item.itemID)
    local rows={
        {text=B:T(c.favorites[id] and "action.unfavorite" or "action.favorite"),action=function() c.favorites[id]=not c.favorites[id] or nil;B:ConfigChanged() end},
        {text=B:T(c.locks[item.key] and "action.unlock" or "action.lock"),action=function() c.locks[item.key]=not c.locks[item.key] or nil;B:ConfigChanged() end},
        {text=B:T("action.auto_category"),action=function() c.manual[id]=nil;B:ConfigChanged() end},
    }
    if item.new then rows[#rows+1]={text=B:T("action.seen"),action=function() A.ClearNewItem(item.bag,item.slot);item.new=false;B.Model:Tag(item);V:Invalidate();B:RefreshVisible(true) end} end
    for _,rule in ipairs(B.Model.compiled or {}) do
        local target=rule.id
        rows[#rows+1]={text=rule.name or target,action=function() c.manual[id]=target;B:ConfigChanged() end}
    end
    if (item.maxStack or 1)>1 and (item.displayCount or item.count)>1 then rows[#rows+1]={text=B:T("split.batch"),action=function() self:Split(item,owner,true) end} end
    self:Menu(owner,rows)
end
function V:Split(item,owner,batch)
    if A.InCombat() or A.CursorBusy() or B.Actions.queue or not item or (item.maxStack or 1)<=1 then return end
    local selection=B.Actions:Selection(item)
    if not selection or selection.count<2 then return end
    if not self.split then
        local f=G:CreateFrame(UIParent,{width=292,height=108,hidden=true,mouse=true})
        f:SetFrameStrata("FULLSCREEN_DIALOG");f:SetClampedToScreen(true);self.split=f
        self:RegisterEscape(f)
        f.header=G:CreateFrame(f,{height=20})
        f.title=G:CreateText(f.header,"",13,"color.text.heading");B.Appearance:Text(f.title,"heading")
        f.close=G:CreateButtonFrame(f.header,{template="UIPanelCloseButton",width=22,height=22,frameLevel=f.header:GetFrameLevel()+1})
        f.close:SetScript("OnClick",function() f:Hide() end)
        f.chrome={root=f,header=f.header,title=f.title,close=f.close}
        f.item=B.Appearance:Item(f,false);f.item:EnableMouse(false);f.item:SetSize(32,32)
        f.sizeLabel=Text(f,B:T("split.quantity"),16,-30)
        f.edit=B.Appearance:Edit(f,{width=76,max=6});f.edit:SetPoint("TOPLEFT",16,-44);f.edit:SetNumeric(true)
        f.total=Text(f,"",102,-49)
        f.extract=Button(f,B:T("split.extract"),16,-86,92,function() self:CommitSplit("extract") end)
        f.extract:SetScript("OnEnter",function(button)
            if f.identity then GameTooltip:SetOwner(button,"ANCHOR_BOTTOMRIGHT");GameTooltip:SetText(string.format(B:T("split.extract_hint"),math.min(f.identity.count,f.identity.maxStack)));GameTooltip:Show() end
        end)
        f.extract:SetScript("OnLeave",function() GameTooltip:Hide() end)
        f.submit=Button(f,B:T("action.split"),116,-86,92,function() self:CommitSplit("place") end)
        f.batch=Button(f,B:T("split.batch"),216,-86,94,function() self:OpenSplitGroups() end)
        f.partsLabel=Text(f,B:T("split.parts"),16,-84)
        f.parts=B.Appearance:Edit(f,{width=64,max=6});f.parts:SetPoint("TOPLEFT",110,-79);f.parts:SetNumeric(true)
        f.previewText=Text(f,"",16,-114);f.previewText:SetWordWrap(true)
        f.back=Button(f,B:T("action.back"),16,-144,92,function() f.previewMode=false;self:PreviewSplit() end)
        f.confirm=Button(f,B:T("split.confirm"),216,-144,94,function() self:CommitSplit("groups") end)
        f.parts:SetScript("OnTextChanged",function() self:PreviewSplit() end)
        f.parts:SetScript("OnEnterPressed",function() self:CommitSplit("groups") end)
        f.parts:SetScript("OnEscapePressed",function() f:Hide() end)
        f.edit:SetScript("OnTextChanged",function() self:PreviewSplit() end)
        f.edit:SetScript("OnEnterPressed",function()
            if IsAltKeyDown() then self:OpenSplitGroups() else self:CommitSplit(f.previewMode and "groups" or "place") end
        end)
        f.edit:SetScript("OnEscapePressed",function() f:Hide() end)
        f:SetScript("OnHide",function() GameTooltip:Hide();f.identity=nil;f.owner=nil;f.edit:ClearFocus();f.parts:ClearFocus() end)
        G.WindowAppearance:Register(f,{themeProvider=function() return B:GetConfig().skin=="native" and "native" or "dark" end,
            heading=f.title,role="helper",nativeBorderOverflow=true,noTopBar=true})
    end
    local f=self.split
    f.identity=selection
    f.owner,f.previewMode=owner,false
    f.title:SetText(item.name)
    -- The readonly preview has no container mixin; occupancy is visual state only.
    SetItemButtonTexture(f.item,item.icon);f.item.hasItem=true;SetItemButtonCount(f.item,0)
    if SetItemButtonQuality then SetItemButtonQuality(f.item,item.quality) end
    B.Appearance:CellAppearance(f.item,false,item);f.item:Show()
    f.edit:SetText("1");self:PreviewSplit()
    f:ClearAllPoints()
    if owner then f:SetPoint("BOTTOMRIGHT",owner,"TOPRIGHT",0,6) else f:SetPoint("CENTER") end
    GameTooltip:Hide();G.WindowAppearance:Refresh(f);f:Show();f.edit:SetFocus();f.edit:HighlightText()
    if batch then self:OpenSplitGroups() end
end
function V:LayoutSplit(f)
    local m=B.Appearance:Metrics();local width=316;local inner=width-m.left-m.right
    local top=m.headerTop+m.headerHeight+10
    local function Place(control,x,y,w,h)
        control:ClearAllPoints();control:SetPoint("TOPLEFT",f,"TOPLEFT",x,-y)
        if w then control:SetWidth(w) end;if h then control:SetHeight(h) end
    end
    f:SetWidth(width);B.Appearance:LayoutHeader(f.chrome,width)
    f.title:ClearAllPoints();f.title:SetPoint("LEFT",f.header,"LEFT",m.left,0);f.title:SetWidth(inner-26);f.title:SetJustifyH("LEFT")
    Place(f.item,m.left,top+4,36,36)
    Place(f.sizeLabel,m.left+48,top,inner-48,14)
    Place(f.edit,m.left+48,top+18,80,22);f.edit:SetJustifyH("CENTER")
    Place(f.total,m.left+136,top+18,inner-136,22);f.total:SetJustifyV("MIDDLE")
    local actionTop=top+52
    if f.previewMode then
        local partsWidth=B.Appearance:TextWidth(B:T("split.parts"),"label")
        Place(f.partsLabel,m.left,actionTop,partsWidth,22);f.partsLabel:SetJustifyV("MIDDLE")
        Place(f.parts,m.left+partsWidth+8,actionTop,64,22)
        local previewHeight=B.Appearance:WrappedTextHeight(f.previewText:GetText(),inner)
        Place(f.previewText,m.left,actionTop+30,inner,previewHeight)
        actionTop=actionTop+30+previewHeight+10
    end
    local buttonWidth=math.floor((inner-12)/3)
    Place(f.extract,m.left,actionTop,buttonWidth,26)
    Place(f.submit,m.left+buttonWidth+6,actionTop,buttonWidth,26)
    Place(f.batch,m.left+2*buttonWidth+12,actionTop,inner-2*buttonWidth-12,26)
    Place(f.back,m.left,actionTop,buttonWidth,26)
    Place(f.confirm,width-m.right-128,actionTop,128,26)
    f:SetHeight(actionTop+26+m.bottom)
    B.Appearance:Surface(f.chrome)
end
function V:OpenSplitGroups()
    local f=self.split
    if not f or not f.identity then return end
    local size=tonumber(f.edit:GetText())
    if not size or size<1 then return end
    f.previewMode=true;f.parts:SetText(tostring(math.floor(f.identity.count/size)));self:PreviewSplit();f.parts:SetFocus();f.parts:HighlightText()
end
function V:PreviewSplit()
    local f=self.split
    if not f or not f.identity then return end
    local size=tonumber(f.edit:GetText())
    local item=f.identity
    local valid=size and size==math.floor(size) and size>0 and size<=item.count
    local single=valid and B.Actions:MakeSelection(item,size,"place")
    local extract=valid and B.Actions:MakeSelection(item,size,"extract")
    f.extract:SetEnabled(type(extract)=="table");f.submit:SetEnabled(type(single)=="table")
    f.batch:SetEnabled(valid and size<=item.maxStack and type(single)=="table" or false)
    f.sizeLabel:SetText(B:T(f.previewMode and "split.size" or "split.quantity"))
    f.total:SetText(string.format(B:T("split.total"),item.count))
    for _,control in ipairs({f.extract,f.submit,f.batch}) do control:SetShown(not f.previewMode) end
    for _,control in ipairs({f.partsLabel,f.parts,f.previewText,f.back,f.confirm}) do control:SetShown(f.previewMode==true) end
    if f.previewMode then
        local parts=tonumber(f.parts:GetText())
        local plan=valid and parts and B.Actions:MakeSelection(item,size,"groups",parts)
        f.confirm:SetEnabled(type(plan)=="table")
        f.previewText:SetText(plan and string.format(B:T("split.result"),parts,size,plan.remainder,plan.needed) or B:T("split.no_space"))
    end
    self:LayoutSplit(f)
end
function V:CommitSplit(mode)
    local f=self.split
    local identity=f and f.identity
    if not identity or A.InCombat() or A.CursorBusy() or B.Actions.queue then return false end
    if not B.Actions:SelectionValid(identity) then B:Notify("error.changed");f:Hide();return false end
    local size=tonumber(f.edit:GetText())
    if not size or size~=math.floor(size) or size<1 or size>identity.count then return false end
    local plan
    if mode=="groups" then
        local parts=tonumber(f.parts:GetText())
        plan=parts and B.Actions:MakeSelection(identity,size,mode,parts)
    else plan=B.Actions:MakeSelection(identity,size,mode) end
    if not plan then B:Notify("split.no_space");return false end
    -- Capture all input before hiding; native splitting also closes its dialog first.
    f:Hide()
    local success=B.Actions:StartSelection(plan)
    if not success then B:Notify("error.operation") end
    return success
end
function V:RenderBagBar(w)
    w.bagButtons=w.bagButtons or {}
    if not w.showBags then w.hoverBag=nil;for _,button in ipairs(w.bagButtons) do button:UnlockHighlight();button:Hide() end;return end
    local index=0
    for _,socket in ipairs(A.BagSockets()) do
        local id=socket.bag
            index=index+1
            local button=w.bagButtons[index]
            if not button then
                -- Combat-created ItemButtons can taint later item clicks. The
                -- post-combat layout will render any sockets still missing.
                if A.InCombat() then break end
                button=B.Appearance:Item(w.root,false);button.image=button.icon
                B.Cache.tooltipBags[button]=true
                button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
                button:SetScript("OnMouseDown",function() self:FocusWindow(w);B.Actions:CancelDelete() end)
                button:RegisterForDrag("LeftButton")
                button:SetScript("OnReceiveDrag",function(owner)
                    if A.InCombat() or B.Actions.queue then return end
                    local cursorType=GetCursorInfo()
                    if cursorType~="item" then return end
                    local cursor=A.CursorItem()
                    if cursor and not A.CanEquipBag(owner.kind,cursor) then return end
                    B.Runtime:CallNative(PutItemInBag,owner.inventoryID)
                    B.Runtime:CloseNativeBags()
                end)
                button:RegisterForClicks("LeftButtonUp","RightButtonUp")
                button:SetScript("OnClick",function(owner,mouse)
                    if mouse=="RightButton" then
                        if owner.equipped then B.BagRemoval:Start(owner.bag) end
                    else local receive=owner:GetScript("OnReceiveDrag");receive(owner) end
                end)
                button:SetScript("OnDragStart",function(owner)
                    if owner.equipped and not A.InCombat() and not A.CursorBusy() and not B.Actions:BlocksItemInput() then
                        B.Runtime:CallNative(PickupBagFromSlot,owner.inventoryID)
                        if A.CursorBusy() then w.dragBag=owner.bag;self:Paint(w) end
                        B.Runtime:CloseNativeBags()
                    end
                end)
                button:SetScript("OnEnter",function(owner)
                    w.hoverBag=owner.bag;owner:LockHighlight();self:Paint(w)
                    if self:ItemTooltipBlocked() then GameTooltip:Hide();return end
                    GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
                    local title=B:T(owner.kind=="reagent" and "bag.reagent_slot" or "bag.normal_slot")
                    if owner.equipped then
                        GameTooltip:SetInventoryItem("player",owner.inventoryID)
                        if owner.kind=="reagent" then
                            local r,g,b=G:GetColor("color.state.success")
                            if GameTooltipTextLeft1 then GameTooltipTextLeft1:SetTextColor(r,g,b) end
                            GameTooltip:AddLine(title,r,g,b)
                        else GameTooltip:AddLine(title) end
                    else
                        if owner.kind=="reagent" then GameTooltip:SetText(title,G:GetColor("color.state.success"))
                        else GameTooltip:SetText(title) end
                        GameTooltip:AddLine(B:T("bag.equip_empty"))
                    end
                    if owner.itemID then B.Cache:AppendTooltip(owner);GameTooltip:AddLine(B:T("bag.remove_hint")) end
                    GameTooltip:Show()
                end)
                button:SetScript("OnLeave",function(owner) w.hoverBag=nil;owner:UnlockHighlight();self:Paint(w);GameTooltip:Hide() end)
                w.bagButtons[index]=button
            end
            local m=B.Appearance:Metrics();local size=math.min(32,B:GetConfig().slotSize)
            B.Appearance:SizeIcon(button,size);button.bag=id;button:ClearAllPoints();button:SetPoint("BOTTOMLEFT",w.root,"TOPLEFT",m.left+(index-1)*size,4)
            button.inventoryID,button.equipped,button.kind=socket.inventoryID,socket.icon~=nil,socket.kind
            button.itemID,button.link=socket.itemID,socket.link
            local background=B.client=="forever" and B.Appearance.bagSocketBackground or socket.background
            button.icon:ClearAllPoints();button.icon:SetPoint("CENTER",0,0)
            B.Appearance:BagSocketArtwork(button,socket.icon or background,size,socket.quality,not socket.icon)
            button:Show()
    end
    for n=index+1,#w.bagButtons do w.bagButtons[n]:Hide() end
end
local function OpenCurrencySettings()
    if YUI.IsForever then return B:OpenSettings("bags","currencies") end
    return B:OpenSettings("currencies")
end
function V:CurrencyMenu(owner)
    if A.InCombat() then return end
    GameTooltip:Hide()
    local rows,tracked={},{}
    for _,entry in ipairs(B:GetConfig().tracked) do tracked[entry.kind..":"..entry.id]=true end
    for _,entry in ipairs(B.Currency:Candidates("")) do
        local kind,id=entry.kind,entry.id
        local selected=tracked[kind..":"..id]==true
        rows[#rows+1]={text=entry.name or tostring(id),icon=entry.icon or 134400,checked=selected,action=function()
            if selected then B.Currency:Untrack(kind,id) else B.Currency:Track(kind,id) end
            self:UpdateCurrencies();self:CurrencyMenu(owner)
        end}
    end
    rows[#rows+1]={text=B:T("currency.custom_manage"),action=OpenCurrencySettings}
    self:Menu(owner,rows,self.windows.player and self.windows.player.root)
    self.menu:ClearAllPoints();self.menu:SetPoint("BOTTOMRIGHT",owner,"TOPRIGHT",0,6)
end
function V:RenderCurrencies(w,width)
    local pitch=B.Appearance:Metrics().footerRow
    local money=YUI.API.Security.SafeNumber(GetMoney()) or 0
    if w.moneyValue~=money then w.money:SetText(A.MoneyText(money,12));w.moneyValue=money end
    local moneyWidth=w.money:GetStringWidth()
    if w.moneyHit and (w.moneyHitWidth~=moneyWidth or w.moneyHitHeight~=pitch) then
        w.moneyHit:SetSize(moneyWidth+6,pitch);w.moneyHitWidth,w.moneyHitHeight=moneyWidth,pitch
    end
    width=math.max(80,width-math.max(100,moneyWidth+14)-8-self.currencyLeftInset)
    local values=B.Currency:Tracked()
    local x,row=0,0
    for n,entry in ipairs(values) do
        local button=w.currencyButtons[n]
        if not button then
            button=G:CreateButtonFrame(w.currencyHost,{height=pitch,width=60})
            button.ybagsArtworkAnchor="LEFT"
            button.icon=G:CreateTexture(button,nil,"ARTWORK");button.icon:SetSize(15,15);button.icon:SetPoint("LEFT",0,0)
            button.text=G:CreateText(button,"",12,"color.text.primary");button.text:SetPoint("LEFT",button.icon,"RIGHT",4,0)
            button.text:SetJustifyH("LEFT");button.text:SetJustifyV("MIDDLE")
            button:SetScript("OnEnter",function(owner)
                local value=owner.entry
                GameTooltip:SetOwner(owner,"ANCHOR_TOP");GameTooltip:SetText(value.name or "")
                if value.max and value.max>0 then GameTooltip:AddDoubleLine(B:T("currency.cap"),tostring(value.max)) end
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave",function() GameTooltip:Hide() end)
            button:RegisterForClicks("LeftButtonUp","RightButtonUp")
            button:SetScript("OnClick",function(owner,mouse)
                if mouse=="RightButton" then self:Menu(owner,{
                    {text=B:T("currency.untrack"),action=function() B.Currency:Untrack(owner.entry.kind,owner.entry.id);self:UpdateCurrencies() end},
                    {text=B:T("currency.first"),action=function() B.Currency:First(owner.entry.kind,owner.entry.id);self:UpdateCurrencies() end},
                }) else OpenCurrencySettings() end
            end)
            w.currencyButtons[n]=button
        end
        local icon=entry.icon or 134400
        button.icon:SetTexture(icon)
        B.Appearance:Artwork(button,button.icon,icon,15)
        button.text:SetText(tostring(entry.count or "?"));local size=15+4+math.ceil(button.text:GetStringWidth())+6
        if x>0 and x+size>width then x=0;row=row+1 end
        button:SetWidth(size);button:ClearAllPoints();button:SetPoint("BOTTOMLEFT",x,row*pitch);button.entry=entry;button:Show();x=x+size
    end
    for n=#values+1,#w.currencyButtons do w.currencyButtons[n]:Hide() end
    w.currencyHost:SetSize(width,(row+1)*pitch)
    return (row+1)*pitch+1
end
function V:UpdateCurrencies()
    local w=self.windows.player
    if w and w.open then self:Layout(w,false) end
end
function V:CanQuickGuildDeposit(w)
    local available=w and w==self.windows["live-guild"] and w.open and w.guildMode=="items" and w.page and w.page==A.CurrentGuildTab()
        and not A.CursorBusy() and not B.Actions.queue and not B.Actions.nativeSort
        and A.BankWindowShown("guild") and B.Deposit:Available("guild")
    local f=self.guildDepositDialog
    local plan=f and f.plan
    if plan and (plan.window~=w or plan.page~=w.page or plan.context~=w.guildInventory or plan.guild~=B.Cache.guildKey
        or plan.withdraw and not B.Deposit:CanGuildWithdrawPreset(plan.page) or not plan.withdraw and not available) then
        f:Hide()
    end
    return available
end

local function SameDepositPlan(preview,current)
    if #preview~=#current then return false end
    for i,step in ipairs(preview) do
        local now=current[i]
        if step.itemID~=now.itemID or step.link~=now.link or step.guid~=now.guid or step.count~=now.count
            or step.quality~=now.quality or step.bound~=now.bound or step.charges~=now.charges
            or step.sourceCount~=now.sourceCount or step.targetCount~=now.targetCount
            or step.source.bag~=now.source.bag or step.source.slot~=now.source.slot
            or step.autoStore~=now.autoStore or (step.target==nil)~=(now.target==nil)
            or step.target and (step.target.bag~=now.target.bag or step.target.slot~=now.target.slot) then return false end
    end
    return true
end

local function OpenDepositSettings(kind)
    if not YUI.IsForever then return B:OpenSettings("deposit") end
    if kind=="guild" then return B:OpenSettings("guild") end
    return B:OpenSettings("bank",kind=="shared" and "shared" or "personal")
end
local function ShowDepositActions(owner,kind,page)
    local rule=B:GetConfig().deposit[kind]
    local actions={}
    local function AddAction(key,query)
        local steps,count,skipped=B.Deposit:Plan(kind,rule,query,page)
        local row={text=count~=nil and string.format(B:T(key),count) or B:T("deposit.count_pending")}
        if #steps>0 then
            row.action=function() return B.Actions:Start(steps,"deposit") end
        end
        actions[#actions+1]=row
        return skipped
    end
    local skipped=AddAction("deposit.put")
    local query=V.windows.player and V.windows.player.query
    if query and query~="" then AddAction("deposit.search",query) end
    actions[#actions+1]={text=B:T("action.settings"),action=function() OpenDepositSettings(kind) end}
    if skipped and skipped>0 then actions[#actions+1]={text=string.format(B:T("deposit.skipped"),skipped)} end
    V:Menu(owner,actions)
end

local function WithdrawalAccess(limit,remaining)
    if limit==0 then return B:T("deposit.only_store"),"color.state.danger" end
    if limit==-1 and remaining==-1 then return B:T("deposit.unlimited"),"color.state.success" end
    if limit and limit>0 and remaining and remaining>=0 and remaining<=limit then
        if remaining==0 then return B:T("deposit.withdraw_spent"),"color.state.danger" end
        return string.format(B:T("deposit.withdraw_quota"),remaining,limit),"color.state.warning"
    end
    return B:T("deposit.unknown"),"color.state.warning"
end

function V:GuildBatchNeedsReview(requested,spaceShort)
    return spaceShort or (requested or 0)>100
end

local function GuildTransferPlan(w,selection,withdraw)
    local tab=A.GuildTab(w.page)
    if not tab or not tab.view or not withdraw and not tab.deposit then return end
    local rule=B:GetConfig().deposit.guild
    local query,preset,label
    if selection=="rule" then
        label=string.format(B:T("deposit.by_rule"),B:T("deposit."..rule.mode))
    elseif selection=="search" then
        query=V.windows.player and V.windows.player.query
        if not query or query=="" then return end
        label=string.format(B:T("deposit.from_search"),query:gsub("|","||"))
    else
        preset=selection
        label=B:T("bank.preset."..preset)
    end
    local steps,count,requested,skipped,spaceShort
    if withdraw then
        steps,count,requested,spaceShort=B.Deposit:PlanGuildWithdrawPreset(w.page,preset)
    else
        steps,count,skipped,requested=B.Deposit:Plan("guild",rule,query,w.page,preset,true)
        spaceShort=requested and count and requested>count
    end
    if count==nil then B:Notify("deposit.count_pending");return end
    local name=tab.name and tab.name~="" and tab.name:gsub("|","||") or string.format(B:T("bank.page"),w.page)
    return {window=w,page=w.page,context=w.guildInventory,guild=B.Cache.guildKey,selection=selection,
        withdraw=withdraw,requested=requested or count,spaceShort=spaceShort or false,
        name=name,label=label,keep=not preset and rule.keep or nil,limit=tab.limit,remaining=tab.remaining,steps=steps,count=count,skipped=skipped or 0}
end

local function StartGuildTransfer(plan)
    if plan.withdraw then return B.Actions:Start(plan.steps,"deposit",plan.count) end
    -- Keep the confirmed permissions on every step if the rank changes mid-transfer.
    local quota={limit=plan.limit,remaining=plan.remaining}
    for _,step in ipairs(plan.steps) do step.guildQuota=quota end
    return B.Actions:Start(plan.steps,"deposit",plan.count)
end

local DepositLines=B.Deposit.GuildDepositLines

local function WrapConfirmationText(text,value,width)
    text:SetWidth(width);text:SetHeight(0)
    text:SetWordWrap(true);text:SetNonSpaceWrap(true);text:SetText(value)
    return math.ceil(text:GetStringHeight())
end

local function LayoutDepositLines(f,lines,width)
    local child=f.scroll.child
    child:SetWidth(width)
    local top=WrapConfirmationText(f.summary,f.summary:GetText(),width)+8
    -- All amounts share one right edge and the longest amount reserves the column.
    local amountWidth=0
    for _,line in ipairs(lines) do
        if line.quantity then
            f.measure:SetText("×"..line.quantity)
            amountWidth=math.max(amountWidth,math.ceil(f.measure:GetStringWidth())+4)
        end
    end
    for index,line in ipairs(lines) do
        local row=f.rows[index]
        if not row then
            row=G:CreateFrame(child,{})
            row.icon=G:CreateIconSlot(row,{size=22,variant="bare"})
            row.icon:EnableMouse(false);row.icon:SetPoint("LEFT")
            row.name=Text(row,"",0,0)
            row.amount=Text(row,"",0,0);row.amount:ClearAllPoints();row.amount:SetPoint("RIGHT")
            row.amount:SetJustifyH("RIGHT");row.amount:SetWordWrap(false)
            f.rows[index]=row
        end
        row:ClearAllPoints();row:SetPoint("TOPLEFT",child,"TOPLEFT",0,-top)
        local item=line.quantity~=nil
        local left=item and 29 or 0
        row.icon:SetShown(item)
        if item then B.Appearance:IdentityIcon(row.icon,line.icon or 134400,.03) end
        row.name:ClearAllPoints();row.name:SetPoint("LEFT",row,"LEFT",left,0)
        local height=WrapConfirmationText(row.name,line.label,math.max(1,width-left-amountWidth-8))
        local r,g,b
        if line.quality then r,g,b=YUI.API.Item.GetQualityColor(line.quality) end
        if r and g and b then
            row.name.gui2ColorKey=nil;row.name:SetTextColor(r,g,b,1)
        else G:SetTextColorKey(row.name,"color.text.primary") end
        row.amount:SetWidth(math.max(1,amountWidth));row.amount:SetText(item and "×"..line.quantity or "")
        height=math.max(22,height)+6
        row:SetSize(width,height);row:Show();top=top+height
    end
    for index=#lines+1,#f.rows do f.rows[index]:Hide() end
    child:SetHeight(top)
    return top
end

local function PaintGuildConfirmation(f,plan,changed,scrollOffset)
    local m=B.Appearance:Metrics()
    local scale=f.GetEffectiveScale and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()/f:GetEffectiveScale() or 1
    local width=math.min(452,math.floor(UIParent:GetWidth()*scale)-24)
    local screenHeight=math.floor(UIParent:GetHeight()*scale)
    if scrollOffset and f:GetWidth()==width and f.screenHeight==screenHeight and f.metrics==m and f.scale==scale then return end
    f.screenHeight,f.metrics,f.scale=screenHeight,m,scale
    if f.plan~=plan then
        f.lines=DepositLines(plan.steps)
        if #f.lines==0 then f.lines[1]={label=B:T(plan.withdraw and "bank.transfer_empty" or "deposit.none")} end
        f.plan=plan
    end
    local inner=width-m.left-m.right
    f:SetWidth(width);B.Appearance:LayoutHeader(f.chrome,width)
    f.title:SetWidth(inner-48)
    f.title:SetText(string.format(B:T(plan.withdraw and "deposit.from_page" or "deposit.to_page"),plan.name))
    local permission,tone
    if not plan.withdraw and not (plan.limit==-1 and plan.remaining==-1) then
        permission,tone=WithdrawalAccess(plan.limit,plan.remaining)
    end
    if plan.spaceShort or plan.requested>100 then
        local warning=plan.spaceShort and string.format(B:T("deposit.space_warning"),plan.requested,plan.count)
            or string.format(B:T("deposit.large_batch"),plan.count)
        permission=permission and permission.."\n"..warning or warning
        tone=tone or "color.state.warning"
    end
    if not permission then
        if plan.withdraw then permission,tone=B:T("deposit.review_changes"),"color.state.warning"
        else permission,tone=WithdrawalAccess(plan.limit,plan.remaining) end
    end
    G:SetTextColorKey(f.permission,tone)
    local top=m.headerTop+m.headerHeight+12
    f.permission:ClearAllPoints();f.permission:SetPoint("TOPLEFT",m.left,-top)
    top=top+WrapConfirmationText(f.permission,permission,inner)+9
    local summary={plan.label}
    if plan.keep and plan.keep>0 then summary[#summary+1]=B:T("deposit.keep").." "..plan.keep end
    if plan.skipped>0 then summary[#summary+1]=string.format(B:T("deposit.skipped"),plan.skipped) end
    f.summary:SetText(table.concat(summary," · "))
    f.notice:SetShown(changed==true)
    if changed then
        f.notice:ClearAllPoints();f.notice:SetPoint("TOPLEFT",m.left,-top)
        top=top+WrapConfirmationText(f.notice,B:T("deposit.updated"),inner)+6
    else f.notice:SetText("") end
    f.submit:SetText(string.format(B:T(plan.withdraw and "deposit.confirm_withdraw" or "deposit.confirm"),plan.count))
    f.submit:SetEnabled(plan.count>0)
    f.measure:SetText(f.submit:GetText())
    local submitWidth=math.ceil(f.measure:GetStringWidth())+32
    local cancelWidth=B.Appearance:TextWidth(f.cancel:GetText(),"heading")+28
    local stacked=submitWidth+cancelWidth+8>inner
    local footer=stacked and 58 or 26
    local listWidth=inner-28 -- keep the scrollbar clear of the quantity column and frame edge
    local content=LayoutDepositLines(f,f.lines,listWidth)
    local available=screenHeight-32-top-footer-m.bottom-12
    local visible=math.max(1,math.min(252,content,available))
    f.scroll:ClearAllPoints();f.scroll:SetPoint("TOPLEFT",m.left,-top)
    f.scroll:SetSize(listWidth,visible)
    if f.scroll.UpdateScrollChildRect then f.scroll:UpdateScrollChildRect() end
    f.scroll:SetVerticalScroll(math.min(scrollOffset or 0,content-visible))
    f:SetHeight(top+visible+12+footer+m.bottom)
    f.submit:ClearAllPoints();f.cancel:ClearAllPoints()
    local firstWidth=stacked and inner or math.max(submitWidth,math.floor((inner-8)/2))
    f.submit:SetPoint("BOTTOMLEFT",m.left,m.bottom+(stacked and 32 or 0));f.submit:SetSize(firstWidth,26)
    f.cancel:SetPoint("BOTTOMRIGHT",-m.right,m.bottom);f.cancel:SetSize(stacked and inner or inner-firstWidth-8,26)
    if f.SetClampRectInsets then
        if B:GetConfig().skin=="native" then f:SetClampRectInsets(-8,4,16,-8)
        else f:SetClampRectInsets(0,0,0,0) end
    end
    G.WindowAppearance:Refresh(f)
    B.Appearance:Surface(f.chrome)
    f:Show()
end

local function ConfirmGuildDeposit(f)
    local old=f.plan
    if not old then return end
    local w=old.window
    if w.page~=old.page or w.guildInventory~=old.context or B.Cache.guildKey~=old.guild
        or old.withdraw and not B.Deposit:CanGuildWithdrawPreset(old.page) or not old.withdraw and not V:CanQuickGuildDeposit(w) then
        f:Hide();return
    end
    local plan=GuildTransferPlan(w,old.selection,old.withdraw)
    if not plan then f:Hide();return end
    if old.limit~=plan.limit or old.remaining~=plan.remaining or old.name~=plan.name or old.label~=plan.label
        or old.keep~=plan.keep or old.count~=plan.count or old.skipped~=plan.skipped or old.requested~=plan.requested
        or old.spaceShort~=plan.spaceShort or not SameDepositPlan(old.steps,plan.steps) then
        PaintGuildConfirmation(f,plan,true);return
    end
    if plan.count==0 then return end
    f:Hide()
    return StartGuildTransfer(plan)
end

local function GuildConfirmation(w)
    if V.guildDepositDialog then return V.guildDepositDialog end
    local f=G:CreateFrame(w.root,{width=452,height=328,hidden=true,mouse=true})
    V.guildDepositDialog=f
    f:SetPoint("CENTER",w.root,"CENTER");f:SetFrameStrata("FULLSCREEN_DIALOG");f:SetClampedToScreen(true)
    f.header=G:CreateFrame(f,{height=20,mouse=true})
    f.title=G:CreateText(f.header,"",13,"color.text.heading");B.Appearance:Text(f.title,"heading")
    f.close=G:CreateButtonFrame(f.header,{template="UIPanelCloseButton",width=22,height=22})
    f.close:SetScript("OnClick",function() f:Hide() end)
    f.chrome={root=f,header=f.header,title=f.title,close=f.close}
    f.header:SetScript("OnEnter",function(header)
        if f.title:IsTruncated() then GameTooltip:SetOwner(header,"ANCHOR_TOP");GameTooltip:SetText(f.title:GetText());GameTooltip:Show() end
    end)
    f.header:SetScript("OnLeave",function(header) if GameTooltip:IsOwned(header) then GameTooltip:Hide() end end)
    f.permission=G:CreateText(f,"",16,"color.state.warning");f.permission:SetJustifyH("LEFT")
    f.notice=G:CreateText(f,"",13,"color.state.warning");f.notice:SetJustifyH("LEFT")
    f.scroll=G:CreateScrollFrame(f,{width=1,height=1,childWidth=1,mouseWheel=true,autoHide=true})
    f.summary=Text(f.scroll.child,"",0,0);G:SetTextColorKey(f.summary,"color.text.secondary")
    f.measure=G:CreateText(f,"",12);f.measure:SetWordWrap(false);f.measure:Hide()
    f.rows={}
    f.submit=Button(f,"",16,-287,234,function() ConfirmGuildDeposit(f) end)
    f.cancel=Button(f,B:T("action.cancel"),264,-287,170,function() f:Hide() end)
    local function Reflow()
        if f.plan and f:IsShown() then PaintGuildConfirmation(f,f.plan,f.notice:IsShown(),f.scroll:GetVerticalScroll()) end
    end
    f:SetScript("OnShow",function()
        YUI.Event:On("PLAYER_REGEN_DISABLED",function() f:Hide() end,f)
        YUI.Event:On("DISPLAY_SIZE_CHANGED",Reflow,f)
        YUI.Event:On("UI_SCALE_CHANGED",Reflow,f)
        B.Stats.listeners=B.Stats.listeners+3
    end)
    f:SetScript("OnHide",function()
        if not f.plan then return end
        if GameTooltip:IsOwned(f.header) then GameTooltip:Hide() end
        f.plan,f.lines=nil,nil
        YUI.Event:OffOwner(f);B.Stats.listeners=math.max(0,B.Stats.listeners-3)
        -- An ancestor hide also dispatches OnHide. Do not reshow on the next bank visit.
        if f:IsShown() then f:Hide() end
    end)
    V:RegisterEscape(f)
    G.WindowAppearance:Register(f,{themeProvider=function() return B:GetConfig().skin=="native" and "native" or "dark" end,
        heading=f.title,role="helper",nativeBorderOverflow=true,noTopBar=true})
    return f
end

local function RunGuildTransfer(w,selection,withdraw)
    if V.guildDepositDialog then V.guildDepositDialog:Hide() end
    if withdraw then
        if not B.Deposit:CanGuildWithdrawPreset(w.page) then return end
    elseif not V:CanQuickGuildDeposit(w) then return end
    local plan=GuildTransferPlan(w,selection,withdraw)
    if not plan then return end
    if (withdraw or plan.limit==-1 and plan.remaining==-1) and not V:GuildBatchNeedsReview(plan.requested,plan.spaceShort) then
        if plan.count==0 then B:Notify(withdraw and "bank.transfer_empty" or "deposit.none");return end
        return StartGuildTransfer(plan)
    end
    PaintGuildConfirmation(GuildConfirmation(w),plan)
end

function V:QuickGuildPreset(owner,w,preset,withdraw)
    if not B.Deposit:IsGuildPreset(preset) then return end
    if self.menu then self.menu:Hide() end
    return RunGuildTransfer(w,preset,withdraw)
end

local function GuildDepositMenu(owner,w,page)
    if w.page~=page or not V:CanQuickGuildDeposit(w) then return end
    if V.guildDepositDialog then V.guildDepositDialog:Hide() end
    local context=w.guildInventory
    local rule=B:GetConfig().deposit.guild
    local mode=rule.mode
    local query=V.windows.player and V.windows.player.query
    local rows={}
    local function Add(selection,label)
        rows[#rows+1]={text=label,action=function()
            if w.guildInventory~=context or w.page~=page or not V:CanQuickGuildDeposit(w) then return end
            if selection=="rule" and B:GetConfig().deposit.guild.mode~=mode
                or selection=="search" and (not V.windows.player or V.windows.player.query~=query) then
                return GuildDepositMenu(owner,w,page)
            end
            return RunGuildTransfer(w,selection)
        end}
    end
    Add("rule",string.format(B:T("deposit.by_rule"),B:T("deposit."..mode)))
    if query and query~="" then Add("search",string.format(B:T("deposit.from_search"),query:gsub("|","||"))) end
    rows[#rows+1]={text=B:T("action.settings"),action=function() OpenDepositSettings("guild") end}
    V:Menu(owner,rows,nil,true)
end

function V:DepositMenu(owner,selectedKind,page)
    if selectedKind=="guild" then
        local w=self.windows["live-guild"]
        if w then GuildDepositMenu(owner,w,page) end
        return
    end
    local rows={}
    for _,kind in ipairs({"bank","shared","guild"}) do
        if (not selectedKind or kind==selectedKind) and B.Deposit:Available(kind) then
            local guildWindow=kind=="guild" and YUI.IsForever and self.windows["live-guild"]
            if kind~="guild" or not YUI.IsForever then
                rows[#rows+1]={text=B:T("cache."..kind),action=function() ShowDepositActions(owner,kind,page) end}
            elseif self:CanQuickGuildDeposit(guildWindow) then
                local tab=guildWindow.page
                rows[#rows+1]={text=B:T("cache.guild"),action=function() GuildDepositMenu(owner,guildWindow,tab) end}
            end
        end
    end
    self:Menu(owner,rows)
end
function V:Toolbar(w,width)
    if A.InCombat() then return end
    width=width or w.root:GetWidth()
    local m=B.Appearance:Metrics()
    local inner=width-m.left-m.right
    local capacityWidth=width>=440 and 115 or 72
    local step=B.Appearance.toolbarStep
    local headerStep=18
    local limit=YUI.IsForever and math.max(1,math.min(7,math.floor((inner-45-capacityWidth-78)/step)))
        or math.max(4,math.min(7,math.floor((width-180)/26)))
    local hasKeyring=KEYRING_CONTAINER and B.Model.bags[KEYRING_CONTAINER]
    local headerButtons={w.directory,w.bags}
    local shown,actions=YUI.IsForever and {} or headerButtons,{}
    if YUI.IsForever then
        w.keys:SetShown(not not hasKeyring)
        if hasKeyring then headerButtons[#headerButtons+1]=w.keys end
        for n,button in ipairs(headerButtons) do
            button:SetSize(headerStep,m.headerHeight-2)
            button:ClearAllPoints();button:SetPoint("LEFT",w.header,"LEFT",m.left+(n-1)*headerStep,0);button:Show()
        end
    end
    local function AddTool(button,available,label,callback)
        if not available then button:Hide()
        elseif YUI.IsForever then actions[#actions+1]={button=button,title=B:T(label),onClick=callback}
        else shown[#shown+1]=button end
    end
    local assistant=YUI.ProfessionAssistant
    if not YUI.IsForever then AddTool(w.keys,hasKeyring) end
    AddTool(w.assistant,assistant and assistant.IsAvailable and assistant:IsAvailable(),"action.enchant",function()
        if assistant and assistant.Open then assistant:Open() end
    end)
    local extensions={}
    for id,definition in pairs(B.toolbarActions) do
        if not definition.isAvailable or definition.isAvailable() then extensions[#extensions+1]={id=id,definition=definition} end
    end
    table.sort(extensions,function(a,b) local ao,bo=a.definition.order or 0,b.definition.order or 0;if ao~=bo then return ao<bo end;return a.id<b.id end)
    for _,entry in ipairs(extensions) do
        local definition=entry.definition
        actions[#actions+1]={title=definition.title or entry.id,icon=definition.icon,onClick=definition.onClick}
    end
    w.extensions=w.extensions or {}
    local remaining={}
    local overflow=not YUI.IsForever or #shown+#actions>limit
    local nextExtension=0
    for _,entry in ipairs(actions) do
        if #shown>=limit-(overflow and 1 or 0) then
            remaining[#remaining+1]={text=entry.title,action=entry.onClick,icon=entry.icon}
            if entry.button then entry.button:Hide() end
        elseif entry.button then shown[#shown+1]=entry.button
        else
            nextExtension=nextExtension+1
            local button=w.extensions[nextExtension]
            if not button then
                button=B.Appearance:Icon(w.toolbarHost,{asset=134400,command=YUI.IsForever and "toolbar"});button.icon=button.image
                button:SetScript("OnClick",function(owner) B.Actions:CancelDelete();if owner.action then owner.action() end end)
                button:SetScript("OnEnter",function(owner) GameTooltip:SetOwner(owner,"ANCHOR_RIGHT");GameTooltip:SetText(owner.label or "");GameTooltip:Show() end)
                button:SetScript("OnLeave",function() GameTooltip:Hide() end)
                w.extensions[nextExtension]=button
            end
            button.action,button.label=entry.onClick,entry.title
            local icon=entry.icon or 134400
            button.icon:SetTexture(icon)
            B.Appearance:Artwork(button,button.icon,icon,18)
            shown[#shown+1]=button
        end
    end
    for n=nextExtension+1,#w.extensions do w.extensions[n]:Hide() end
    if #remaining>0 then
        if not w.more then
            w.more=B.Appearance:Icon(w.toolbarHost,{asset="Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up",command=YUI.IsForever and "toolbar"})
            if YUI.IsForever then
                w.more:SetScript("OnEnter",function(owner) GameTooltip:SetOwner(owner,"ANCHOR_RIGHT");GameTooltip:SetText(B:T("action.more"));GameTooltip:Show() end)
                w.more:SetScript("OnLeave",function() GameTooltip:Hide() end)
            end
            w.more:SetScript("OnClick",function() self:Menu(w.more,w.overflow) end)
        end
        w.overflow=remaining;shown[#shown+1]=w.more
    elseif w.more then w.more:Hide() end
    if YUI.IsForever then
        w.search:SetWidth(math.min(150,math.max(78,inner-45-capacityWidth-#shown*step)))
        w.capacity:SetWidth(inner-45-w.search:GetWidth()-#shown*step);w.capacity:SetWordWrap(false)
        for n,button in ipairs(shown) do
            button:SetWidth(step)
            button:ClearAllPoints();button:SetPoint("RIGHT",w.search,"LEFT",-6-(#shown-n)*step,0);button:Show()
        end
        local titleWidth=width-2*math.max(w.helpButton and 80 or 54,m.left+#headerButtons*headerStep+4)
        w.title:SetWidth(titleWidth)
        w.drag:ClearAllPoints();w.drag:SetPoint("CENTER",w.header,"CENTER",0,0);w.drag:SetSize(titleWidth,m.headerHeight)
        return
    end
    for n,button in ipairs(shown) do button:ClearAllPoints();button:SetPoint("LEFT",w.header,"LEFT",m.headerInset+(n-1)*23,0);button:Show() end
    local left=m.headerInset+#shown*23+3
    local titleWidth=math.max(50,width-left-56)
    w.title:ClearAllPoints();w.title:SetPoint("LEFT",w.header,"LEFT",left,0);w.title:SetWidth(titleWidth);w.title:SetWordWrap(false);w.title:SetJustifyH("CENTER")
    w.drag:ClearAllPoints();w.drag:SetPoint("LEFT",w.header,"LEFT",left,0);w.drag:SetSize(titleWidth,m.headerHeight)
end
