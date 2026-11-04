local YUI=_G.YUI
local Settings,GUI=YUI and YUI.Settings,YUI and YUI.GUI2
local C=Settings and Settings.SoundCenter
if not (C and GUI) then return end
local Form=GUI.Form
local S,P
local ROW_HEIGHT,ROW_GAP=56,0
local ICON_SIZE,TEXT_LEFT=38,78
local SCOPE_ICON_SIZE,SCOPE_ICON_STEP=16,20
local scopeIconCrop={0.08,0.92,0.08,0.92}
local sections={'class','events','buffs','racial'}
local sectionStyles={
    class={icon='library',color='color.state.info'},
    events={icon='spell-alert',color='color.text.accent'},
    buffs={icon='raid-star',color='color.state.success'},
    racial={icon='users',color='color.badge.pink'},
}
local results={'all','add','keep','skip'}
local function T(key) return C.Text('preset.'..key) end
local function Text(parent,value,size,color) return GUI:CreateText(parent,value,size or 'font.size.md',color or 'color.text.primary','LEFT') end
local function TextWidth(text) return text:GetUnboundedStringWidth() end
local function ClassOptions()
    local values,seen={{value='all',text=T('allClasses')}},{}
    for _,group in ipairs(C:SelectionGroups()) do
        for _,spec in ipairs(group.specs or {}) do
            local info=spec.classInfo
            if info and not seen[info.token] then
                seen[info.token]=true
                values[#values+1]={value=info.token,text=info.name or info.token,icon=info.icon,texCoord=info.iconTexCoord}
            end
        end
    end
    return values
end
local function Name(row)
    if row.rule.trigger.extension then
        local name=S.EditorModel:ObjectInfo(row.rule.object,row.rule.trigger.extension)
        return name
    end
    if row.rule.object.kind=='event' then
        local e=S.EventDefinitions.byID[row.rule.object.id]
        return e and S.EventDefinitions:Text(e.id) or row.name
    end
    return YUI.API.Spell.GetName(row.rule.object.id) or row.name
end
local function RaceName(token)
    local api=YUI.API.Racial
    local info=api and api.GetRaceInfo and token and api.GetRaceInfo(token)
    return info and info.raceName or token or T('general')
end
local function Scope(row,expanded)
    if row.race then
        if not row.rule.specs then return RaceName(row.race),{} end
        local scope,icons=Scope({rule=row.rule},expanded)
        return RaceName(row.race)..' · '..scope,icons
    end
    if not row.rule.specs then return T('general'),{} end
    if YUI.IsForever and S.ForeverCatalog then
        local labels,icons=S.ForeverCatalog:ScopePresentation(Settings,row.rule)
        return #labels>0 and table.concat(labels,' / ') or T('general'),icons
    end
    local chosen,classes,order,icons={},{},{},{}
    for _,key in ipairs(row.rule.specs) do chosen[key]=true end
    for _,group in ipairs(C:SelectionGroups()) do
        for _,spec in ipairs(group.specs or {}) do
            local info=spec.classInfo
            local class=classes[info.token]
            if not class then
                class={name=info.name or info.token,total=0,labels={}};classes[info.token]=class;order[#order+1]=class
            end
            class.total=class.total+1
            if chosen[info.token..':'..spec.specID] then
                class.labels[#class.labels+1]=spec.displayName
                icons[#icons+1]=spec
            end
        end
    end
    local labels={}
    for _,class in ipairs(order) do
        if #class.labels>0 then
            labels[#labels+1]=not expanded and #class.labels==class.total and string.format(T('allSpecs'),class.name)
                or class.name..' · '..table.concat(class.labels,' / ')
        end
    end
    return #labels>0 and table.concat(labels,' / ') or T('general'),icons
end
local function DisplayRule(cell)
    local item=cell.outcome
    return item and item.status=='keep' and item.kept[1] or cell.row.rule
end
local function ResultDetail(item,enabled)
    if item.status=='skip' then return C:ErrorText(item.code) end
    if item.status=='keep' then
        return #item.kept>1 and T('keepMultiple') or T(item.kept[1].enabled~=false and 'keepOn' or 'keepOff')
    end
    return item.partial and T('partial') or T(enabled and 'addOn' or 'addOff')
end
function C:OpenPresets()
    -- Suite Settings loads before Voice; acquire its services on first use.
    local sound=YUI.Sound
    if not (sound and sound.Presets) then return end
    S,P=sound,sound.Presets
    local frame=self.presetDialog
    if not frame then
        frame=GUI:CreatePanel(self:GetModalParent(),{width=960,height=600,surface='color.surface.popup',border='color.popup.border',shadow=true})
        self.presetDialog=frame;frame:EnableMouse(true);frame:Hide()
        local refreshTheme=frame.RefreshTheme
        function frame:RefreshTheme()
            if refreshTheme then refreshTheme(self) end
            local r,g,b=GUI:GetColor('color.surface.popup')
            self:SetBackdropColor(r,g,b,1)
        end
        frame:RefreshTheme()
        frame.title=Text(frame,T('title'),'font.size.title','color.text.accent');frame.title:SetPoint('TOPLEFT',16,-12)
        GUI:CreateCloseButton(frame,function() frame:Hide() end):SetPoint('TOPRIGHT',-12,-12)
        frame.policy=Text(frame,T('policy'),nil,'color.text.secondary');frame.policy:SetPoint('TOPLEFT',16,-40);frame.policy:SetPoint('TOPRIGHT',-16,-40);frame.policy:SetHeight(18);frame.policy:SetWordWrap(false)
        frame.section='class';frame.class='all';frame.tier='all';frame.query='';frame.selected={};frame.cells={};frame.bulk={};frame.headers={}
        frame.stage='select';frame.result='all';frame.categoryButtons={};frame.resultButtons={}
        frame.steps=Text(frame,'',nil,'color.text.secondary');frame.steps:SetPoint('TOPRIGHT',-44,-17);frame.steps:SetHeight(20);frame.steps:SetWordWrap(false)
        function frame:HideRowTip(owner)
            local tip=self.rowTip
            if tip and (not owner or tip.owner==owner) then tip.owner=nil;tip:Hide() end
        end
        function frame:ShowRowTip(owner)
            self:HideRowTip()
            local row=owner.row;if not row then return end
            local function Truncated(text) return TextWidth(text)>text:GetWidth()+1 end
            local available,code=P:Availability(row)
            if available and not owner.outcome and not owner.scopeInIcons and not (Truncated(owner.name) or Truncated(owner.scope) or Truncated(owner.when) or Truncated(owner.voice)) then return end
            local tip=self.rowTip
            if not tip then
                tip=GUI:CreatePanel(self,{surface='color.surface.popup',border='color.popup.border',shadow=true})
                self.rowTip=tip;tip:EnableMouse(false)
                local refresh=tip.RefreshTheme
                function tip:RefreshTheme()
                    if refresh then refresh(self) end
                    local r,g,b=GUI:GetColor('color.surface.popup');self:SetBackdropColor(r,g,b,1)
                end
                tip.title=Text(tip,'','font.size.lg','color.text.heading');tip.title:SetPoint('TOPLEFT',12,-10);tip.title:SetWordWrap(true)
                tip.body=Text(tip,'',nil,'color.text.secondary');tip.body:SetPoint('TOPLEFT',tip.title,'BOTTOMLEFT',0,-6);tip.body:SetWordWrap(true)
                tip.warning=Text(tip,'',nil,'color.tooltip.warning');tip.warning:SetPoint('TOPLEFT',tip.body,'BOTTOMLEFT',0,-6);tip.warning:SetWordWrap(true)
            end
            local lines={T('scope')..Scope(row,true)}
            if Truncated(owner.when) then lines[#lines+1]=T('column.when')..': '..S.EditorModel:TriggerLabel(row.rule) end
            if Truncated(owner.voice) then lines[#lines+1]=T('column.voice')..': '..S.EditorModel:SoundLabel(DisplayRule(owner).sound) end
            if owner.outcome then
                local item=owner.outcome
                if item.status~='skip' then lines[#lines+1]=T('result.'..item.status)..': '..ResultDetail(item,self.enabled) end
                if item.status=='add' then
                    for _,rule in ipairs(item.rules) do lines[#lines+1]=T('newScope')..Scope({rule=rule,race=row.race},true) end
                elseif item.status=='keep' then
                    for _,rule in ipairs(item.kept) do
                        lines[#lines+1]=Scope({rule=rule,race=row.race},true)..' · '..S.EditorModel:SoundLabel(rule.sound)..' · '..T(rule.enabled~=false and 'on' or 'off')
                    end
                end
            end
            local width=math.min(360,self:GetWidth()-32)
            tip:SetWidth(width)
            tip.title:SetWidth(width-24);tip.title:SetText(Name(row));tip.title:SetHeight(tip.title:GetStringHeight())
            tip.body:SetWidth(width-24);tip.body:SetText(table.concat(lines,'\n'));tip.body:SetHeight(tip.body:GetStringHeight())
            tip.warning:SetWidth(width-24);tip.warning:SetText(not available and C:ErrorText(code) or '');tip.warning:SetShown(not available)
            tip.warning:SetHeight(tip.warning:GetStringHeight())
            local height=28+tip.title:GetHeight()+tip.body:GetHeight()+(not available and 6+tip.warning:GetHeight() or 0)
            tip:SetHeight(height)
            -- Stay clear of the hovered row; prefer the list area over its controls.
            local rowTop=self.listTop+(owner.listIndex-1)*self.rowStep-self.scroll:GetVerticalScroll()
            local below=rowTop+self.rowHeight+6
            local above=rowTop-height-6
            local y=below+height<=self.listTop+self.scroll:GetHeight() and below or above
            if y<16 then y=below end
            tip:ClearAllPoints();tip:SetPoint('TOPRIGHT',self,'TOPRIGHT',-16,-y)
            tip:SetFrameStrata(self:GetFrameStrata());tip:SetFrameLevel(self.scroll.child:GetFrameLevel()+20)
            tip.owner=owner;tip:RefreshTheme();tip:Show()
        end
        function frame:Invalidate()
            self.prepared=nil;self.stage='select';self.primary:SetText(T('preview'));self.primary:SetDisabled(false);self.status:SetText('')
        end
        frame.tabs=GUI:CreateFrame(frame,{width=700,height=48});frame.tabs:SetPoint('TOPLEFT',16,-64)
        local function Navigation(parent,keys,target,change)
            for _,key in ipairs(keys) do
                local button=Form:CreateButton(parent,{text='',height=48,tone='default',onClick=function() change(key) end})
                local style=parent==frame.tabs and sectionStyles[key]
                local textLeft=style and 48 or 10
                button.contentLeft=textLeft
                button.label=Text(button,T(parent==frame.tabs and 'category.'..key or 'result.'..key),nil,style and style.color)
                button.label:SetPoint('TOPLEFT',textLeft,-6);button.label:SetPoint('TOPRIGHT',-10,-6);button.label:SetHeight(18);button.label:SetWordWrap(false)
                button.count=Text(button,'',nil,'color.text.secondary');button.count:SetPoint('BOTTOMLEFT',textLeft,5);button.count:SetPoint('BOTTOMRIGHT',-10,5);button.count:SetHeight(18);button.count:SetWordWrap(false)
                if style then
                    button.categoryIcon=GUI:CreateIcon(button,{texture=GUI:GetUIIcon(style.icon,28),width=28,height=28,crop=false})
                    button.categoryIcon:SetPoint('LEFT',10,0)
                    local refresh=button.RefreshTheme
                    function button:RefreshTheme()
                        if refresh then refresh(self) end
                        self.categoryIcon:SetVertexColor(GUI:GetColor(style.color))
                    end
                    button:RefreshTheme()
                end
                target[key]=button
            end
        end
        function frame:SelectSection(value)
            if self.stage~='select' then return end
            self.section=value;self.query='';self.search:SetValue('',true);self:RefreshRows()
        end
        Navigation(frame.tabs,sections,frame.categoryButtons,function(value) frame:SelectSection(value) end)
        frame.resultTabs=GUI:CreateFrame(frame,{width=700,height=48})
        Navigation(frame.resultTabs,results,frame.resultButtons,function(value) frame.result=value;frame:RefreshRows() end)
        frame.summary=Text(frame,'','font.size.lg','color.text.accent');frame.summary:SetHeight(22);frame.summary:SetWordWrap(false)
        frame.summaryDetail=Text(frame,'',nil,'color.text.secondary');frame.summaryDetail:SetHeight(18);frame.summaryDetail:SetWordWrap(false)
        frame.confirmPolicy=Text(frame,T('confirmPolicy'),nil,'color.text.secondary');frame.confirmPolicy:SetWordWrap(true)
        frame.categoryScope=Text(frame,'',nil,'color.text.secondary');frame.categoryScope:SetHeight(28);frame.categoryScope:SetWordWrap(false)
        frame.classPicker=Form:CreateDropdown(frame,{width=156,height=28,options=ClassOptions,
            get=function() return frame.class end,set=function(value) frame.class=value;frame:RefreshRows() end})
        frame.classPicker:SetPoint('TOPLEFT',16,-124)
        frame.tierPicker=Form:CreateDropdown(frame,{width=136,height=28,options={{value='all',text=T('allTiers')},{value='core',text=T('core')},{value='extended',text=T('extended')}},
            get=function() return frame.tier end,set=function(value) frame.tier=value;frame:RefreshRows() end})
        frame.tierPicker:SetPoint('LEFT',frame.classPicker,'RIGHT',8,0)
        frame.search=Form:CreateEditBox(frame,{width=250,height=28,placeholder=T('search'),searchPlaceholder=true,onChange=function(_,value)
            frame.query=(value or ''):match('^%s*(.-)%s*$'):lower();frame:RefreshRows()
        end})
        frame.search:SetPoint('LEFT',frame.tierPicker,'RIGHT',8,0)
        frame.bulkLabel=Text(frame,T('currentList'),nil,'color.text.secondary');frame.bulkLabel:SetPoint('TOPLEFT',16,-166);frame.bulkLabel:SetWordWrap(false)
        for _,mode in ipairs({'core','all','none'}) do
            local button=Form:CreateButton(frame,{text=T('select.'..mode),width=78,height=26,tone='default',fontSizeKey='font.size.md',onClick=function()
                if frame.stage~='select' then return end
                for _,row in ipairs(frame.filtered) do frame.selected[row.key]=mode=='all' or mode=='core' and row.core or nil end
                frame:Invalidate();frame:PaintRows()
            end})
            frame.bulk[mode]=button
        end
        frame.range=Text(frame,'',nil,'color.text.secondary');frame.range:SetWordWrap(false)
        for _,key in ipairs({'object','when','voice','result'}) do
            frame.headers[key]=Text(frame,T('column.'..key),nil,'color.text.secondary')
            frame.headers[key]:SetWordWrap(false)
        end
        frame.scroll=GUI:CreateScrollFrame(frame,{width=900,height=280,autoHide=true})
        local child=frame.scroll.child
        for i=1,10 do
            local cell=Form:CreateButton(child,{height=ROW_HEIGHT,text='',tone='default',selectedSurface='color.surface.panel',selectedBorder='color.border.subtle',onClick=function(owner,button)
                if frame.stage=='select' and owner.row and button=='LeftButton' then
                    frame.selected[owner.row.key]=not frame.selected[owner.row.key] or nil;frame:Invalidate();frame:PaintRows()
                end
            end})
            cell.gui2SurfaceToken='color.surface.panel';cell.gui2BorderToken='color.border.subtle'
            cell.gui2HoverSurfaceToken='color.surface.raised';cell.gui2HoverBorderToken='color.border.default'
            cell.gui2PressedSurfaceToken='color.surface.raised';cell.gui2PressedBorderToken='color.border.default'
            for _,edge in ipairs({'top','left','right'}) do cell.gui2Borders[edge]:SetAlpha(0) end
            frame.cells[i]=cell;cell:EnableMouse(true)
            cell.check=Form:CreateCheckbox(cell,{width=24,height=28,get=function() return cell.row and frame.selected[cell.row.key] end,set=function(value)
                if frame.stage=='select' and cell.row then frame.selected[cell.row.key]=value or nil;frame:Invalidate();frame:PaintRows() end
            end})
            cell.check:SetPoint('LEFT',4,0)
            cell.icon=GUI:CreateIconSlot(cell,{size=ICON_SIZE});cell.icon:SetPoint('LEFT',cell.check,'RIGHT',4,0)
            cell.name=Text(cell,'','font.size.lg');cell.name:SetWordWrap(false);cell.name:SetHeight(20);cell.name:SetJustifyV('TOP')
            cell.scope=Text(cell,'',nil,'color.text.secondary');cell.scope:SetWordWrap(false);cell.scope:SetHeight(18);cell.scope:SetJustifyV('BOTTOM')
            cell.scopeIcons={}
            cell.when=Text(cell,'');cell.when:SetWordWrap(false)
            cell.voice=Text(cell,'');cell.voice:SetWordWrap(false)
            cell.play=Form:CreateIconButton(cell,{size=26,icon=GUI:GetSettingsIcon('play'),tooltip=C.Text('preview'),onClick=function()
                frame:HideRowTip()
                if cell.row then
                    local rule=DisplayRule(cell)
                    if rule.sound.kind=='voice' then C:PreviewVoice(rule.sound.value) else S.EditorModel:Preview(rule) end
                end
            end})
            cell.result=Text(cell,'',nil,'color.text.accent');cell.result:SetHeight(20);cell.result:SetWordWrap(false)
            cell.detail=Text(cell,'',nil,'color.text.secondary');cell.detail:SetHeight(18);cell.detail:SetWordWrap(false)
            cell.tier=Text(cell,'',nil,'color.text.secondary');cell.tier:SetHeight(18);cell.tier:SetJustifyV('BOTTOM')
            cell:HookScript('OnEnter',function(owner) frame:ShowRowTip(owner) end)
            local function HideTip(owner) frame:HideRowTip(owner) end
            cell:HookScript('OnLeave',HideTip);cell:HookScript('OnHide',HideTip)
        end
        frame.empty=Text(child,C.Text('empty'),nil,'color.text.secondary');frame.empty:SetPoint('TOPLEFT',4,-15)
        frame.status=Text(frame,'',nil,'color.text.accent');frame.status:SetPoint('BOTTOMLEFT',16,52);frame.status:SetPoint('BOTTOMRIGHT',-16,52);frame.status:SetHeight(20);frame.status:SetWordWrap(false)
        frame.total=Text(frame,'');frame.total:SetPoint('BOTTOMLEFT',16,22);frame.total:SetWidth(124);frame.total:SetWordWrap(false)
        frame.breakdown=Text(frame,'',nil,'color.text.secondary');frame.breakdown:SetHeight(18);frame.breakdown:SetWordWrap(false)
        frame.enabledPicker=Form:CreateDropdown(frame,{width=148,height=28,options={{value=true,text=T('enabled')},{value=false,text=T('disabled')}},
            get=function() return frame.enabled end,set=function(value) frame.enabled=value;frame:Invalidate();frame:RefreshRows() end})
        frame.enabledPicker:SetPoint('BOTTOMLEFT',148,16)
        frame.cancel=Form:CreateButton(frame,{width=84,height=30,text=C.Text('cancel'),tone='default',onClick=function() frame:Hide() end})
        frame.cancel:SetPoint('BOTTOMRIGHT',-164,16)
        frame.back=Form:CreateButton(frame,{width=112,height=30,text=T('back'),tone='default',onClick=function()
            local scroll=frame.selectionScroll or 0
            frame:Invalidate();frame:RefreshRows();frame.scroll:SetVerticalScroll(scroll);frame:PaintRows()
        end})
        frame.primary=Form:CreateButton(frame,{width=140,height=30,text=T('preview'),tone='accent',onClick=function()
            if not frame:IsShown() then return end
            if frame.stage=='select' then
                local prepared,code=P:Prepare(frame.selected,frame.enabled)
                if not prepared then frame.status:SetText(code=='rule-budget-exceeded' and T('budget') or C:ErrorText(code));return end
                frame.selectionScroll=frame.scroll:GetVerticalScroll();frame.search:ClearFocus()
                frame.prepared=prepared;frame.stage='confirm';frame.result='all';frame.status:SetText('');frame:RefreshRows()
                return
            end
            local prepared=frame.prepared
            if not prepared or prepared.counts.added==0 then return end
            local before,code=S.RuleStore:Read();if not before then frame.status:SetText(C:ErrorText(code));return end
            frame.committing=true
            local ok,why=P:Commit(prepared)
            frame.committing=nil
            if not ok then frame:Invalidate();frame:RefreshRows();frame.status:SetText(C:ErrorText(why));return end
            local view=C.view
            if view and prepared.counts.added>0 then
                view.undo={token=S.RuleStore:BeginEdit(),rules=before}
                view.undoButton:SetText(T('undo'));view.undoButton:Show()
                view.status:SetText(string.format(T('done'),prepared.counts.added));view:RefreshRows()
            end
            frame:Hide()
        end})
        frame.primary:SetPoint('BOTTOMRIGHT',-16,16)
        function frame:Layout()
            local width=self:GetWidth()-46
            local confirm=self.stage=='confirm'
            local resultWidth=confirm and math.floor(width*.21) or 0
            local triggerWidth,voiceWidth=math.floor(width*(confirm and .19 or .24)),math.floor(width*(confirm and .26 or .32))
            local objectWidth=width-triggerWidth-voiceWidth-resultWidth
            self.textLeft=confirm and 50 or TEXT_LEFT
            self.columns={width=width,object=objectWidth,when=triggerWidth,voice=voiceWidth,result=resultWidth}
            local classShown=not confirm and self.section=='class'
            self.classPicker:SetShown(classShown)
            self.categoryScope:SetShown(not confirm and not classShown)
            self.categoryScope:SetText(T('scope.'..self.section));self.categoryScope:ClearAllPoints();self.categoryScope:SetPoint('TOPLEFT',16,-124);self.categoryScope:SetWidth(156)
            for _,control in ipairs({self.tabs,self.tierPicker,self.search,self.bulkLabel,self.enabledPicker}) do control:SetShown(not confirm) end
            for _,button in pairs(self.bulk) do button:SetShown(not confirm) end
            for _,control in ipairs({self.summary,self.summaryDetail,self.resultTabs,self.confirmPolicy,self.back}) do control:SetShown(confirm) end
            local navWidth=(self:GetWidth()-32-18)/4
            self.tabs:SetWidth(self:GetWidth()-32)
            self.resultTabs:ClearAllPoints();self.resultTabs:SetPoint('TOPLEFT',16,-122);self.resultTabs:SetWidth(self:GetWidth()-32)
            for i,key in ipairs(sections) do
                local button=self.categoryButtons[key];button:ClearAllPoints();button:SetPoint('TOPLEFT',(i-1)*(navWidth+6),0);button:SetWidth(navWidth)
                button.label:SetText(T('category.'..key))
                if TextWidth(button.label)>navWidth-button.contentLeft-10 then button.label:SetText(T('categoryShort.'..key)) end
            end
            for i,key in ipairs(results) do
                local button=self.resultButtons[key];button:ClearAllPoints();button:SetPoint('TOPLEFT',(i-1)*(navWidth+6),0);button:SetWidth(navWidth)
            end
            self.steps:SetText(T(confirm and 'step.confirm' or 'step.select'));self.steps:SetWidth(TextWidth(self.steps))
            -- On compact dialogs the step belongs below the title, not over it.
            self.steps:ClearAllPoints()
            self.steps:SetPoint('TOPRIGHT',-44,self:GetWidth()<760 and -40 or -17)
            self.policy:SetShown(self:GetWidth()>=760)
            self.summary:ClearAllPoints();self.summary:SetPoint('TOPLEFT',16,-66);self.summary:SetWidth(self:GetWidth()-32)
            self.summaryDetail:ClearAllPoints();self.summaryDetail:SetPoint('TOPLEFT',16,-94);self.summaryDetail:SetWidth(self:GetWidth()-32)
            self.confirmPolicy:ClearAllPoints();self.confirmPolicy:SetPoint('TOPLEFT',16,-178);self.confirmPolicy:SetWidth(self:GetWidth()-32);self.confirmPolicy:SetHeight(self.confirmPolicy:GetStringHeight())
            self.tierPicker:ClearAllPoints()
            self.tierPicker:SetPoint('TOPLEFT',180,-124)
            self.search:ClearAllPoints();self.search:SetPoint('LEFT',self.tierPicker,'RIGHT',8,0)
            self.search:SetWidth(self:GetWidth()-340)
            local x=16+TextWidth(self.bulkLabel)+12
            for _,mode in ipairs({'core','all','none'}) do
                local button=self.bulk[mode]
                button:SetWidth(math.max(66,TextWidth(button.text)+20))
                button:ClearAllPoints();button:SetPoint('TOPLEFT',x,-160)
                x=x+button:GetWidth()+8
            end
            self.rangeWidth=TextWidth(self.range)
            local wrap=x+self.rangeWidth+8>self:GetWidth()-16
            local rangeY=confirm and 0 or wrap and 192 or 166
            self.range:ClearAllPoints();self.range:SetPoint('TOPRIGHT',-16,-rangeY)
            self.range:SetShown(not confirm)
            self.headerY=confirm and math.max(216,184+self.confirmPolicy:GetHeight()) or wrap and 216 or 190
            self.listTop=self.headerY+22
            local positions={object=self.textLeft,when=objectWidth+8,voice=objectWidth+triggerWidth+8,result=objectWidth+triggerWidth+voiceWidth+8}
            local widths={object=objectWidth-self.textLeft-8,when=triggerWidth-16,voice=voiceWidth-16,result=resultWidth-16}
            for key,label in pairs(self.headers) do
                label:SetShown(key~='result' or confirm)
                label:ClearAllPoints();label:SetPoint('TOPLEFT',16+positions[key],-self.headerY);label:SetWidth(math.max(1,widths[key]))
            end
            local compact=self:GetWidth()<800
            local footerHeight=compact and 112 or 84
            local available=self:GetHeight()-self.listTop-footerHeight
            local visible=math.max(1,math.floor((available+ROW_GAP)/(ROW_HEIGHT+ROW_GAP)))
            self.rowStep=math.floor((available+ROW_GAP)/visible)
            self.rowHeight=self.rowStep-ROW_GAP
            self.scroll:ClearAllPoints();self.scroll:SetPoint('TOPLEFT',16,-self.listTop);self.scroll:SetPoint('TOPRIGHT',-16,-self.listTop)
            self.scroll:SetHeight(visible*self.rowStep-ROW_GAP)
            self.scroll.child:SetWidth(width)
            GUI:FitScrollContent(self.scroll,math.max(1,#self.filtered*self.rowStep-ROW_GAP))
            self.status:ClearAllPoints();self.status:SetPoint('BOTTOMLEFT',16,footerHeight-20);self.status:SetPoint('BOTTOMRIGHT',-16,footerHeight-20)
            local primaryWidth=math.max(140,TextWidth(self.primary.text)+24)
            self.primary:SetWidth(primaryWidth);self.primary:ClearAllPoints();self.primary:SetPoint('BOTTOMRIGHT',-16,16)
            self.cancel:ClearAllPoints();self.cancel:SetPoint('BOTTOMRIGHT',self.primary,'BOTTOMLEFT',-8,0);self.cancel:SetShown(not confirm)
            self.back:SetWidth(math.max(112,TextWidth(self.back.text)+24));self.back:ClearAllPoints();self.back:SetPoint('BOTTOMRIGHT',self.primary,'BOTTOMLEFT',-8,0)
            local totalWidth=compact and self:GetWidth()-32 or self:GetWidth()-primaryWidth-(confirm and self.back:GetWidth()+48 or 296)
            self.total:ClearAllPoints();self.total:SetPoint('BOTTOMLEFT',16,compact and 68 or 40);self.total:SetWidth(totalWidth)
            self.breakdown:ClearAllPoints();self.breakdown:SetPoint('TOPLEFT',self.total,'BOTTOMLEFT',0,-4);self.breakdown:SetWidth(totalWidth)
            self.enabledPicker:ClearAllPoints();self.enabledPicker:SetPoint('BOTTOMLEFT',compact and 16 or totalWidth+28,16)
        end
        function frame:PaintRows()
            self:HideRowTip()
            local confirm=self.stage=='confirm'
            local count,current=0,0;local bySection,totals={},{}
            for _,row in ipairs(P:Rows()) do
                totals[row.section]=(totals[row.section] or 0)+1
                if self.selected[row.key] then count=count+1;bySection[row.section]=(bySection[row.section] or 0)+1 end
            end
            for _,row in ipairs(self.filtered) do if self.selected[row.key] then current=current+1 end end
            local parts={}
            for _,key in ipairs(sections) do
                local n=bySection[key] or 0
                local button=self.categoryButtons[key];button.count:SetText(string.format(T('categoryCount'),totals[key] or 0,n));button:SetSelected(self.section==key)
                if TextWidth(button.count)>button:GetWidth()-button.contentLeft-10 then button.count:SetText(string.format(T('categoryCompact'),n,totals[key] or 0)) end
                if n>0 then parts[#parts+1]=T(key)..' '..n end
            end
            self.breakdown:SetText(confirm and T(self.enabled and 'newOn' or 'newOff') or table.concat(parts,' · '))
            self.total:SetText(string.format(T('selected'),count));self.range:SetText(string.format(T('range'),#self.filtered,current))
            self.bulk.core:SetDisabled(#self.filtered==0);self.bulk.all:SetDisabled(#self.filtered==0);self.bulk.none:SetDisabled(current==0)
            if confirm then
                local n=self.prepared.counts
                self.summary:SetText(string.format(T('summary'),n.added))
                self.summaryDetail:SetText(string.format(T('reviewCounts'),count,n.skipped,n.unavailable))
                self.primary:SetText(n.added>0 and string.format(T('confirm'),n.added) or T('nothingNew'))
                local counts={all=count,add=0,keep=n.skipped,skip=n.unavailable}
                for _,item in ipairs(self.prepared.outcomes) do if item.status=='add' then counts.add=counts.add+1 end end
                for _,key in ipairs(results) do local button=self.resultButtons[key];button.count:SetText(string.format(T('items'),counts[key]));button:SetSelected(self.result==key) end
            end
            self.primary:SetDisabled(count==0 or self.prepared and self.prepared.counts.added==0)
            self.empty:SetText(T(not confirm and self.query~='' and 'emptySearch' or 'emptyResults'));self.empty:SetWordWrap(true);self.empty:SetWidth(self:GetWidth()-62)
            self.empty:SetShown(#self.filtered==0)
            if self.rangeWidth~=TextWidth(self.range) then self:Layout() end
            local offset=math.floor(self.scroll:GetVerticalScroll()/self.rowStep)
            local columns=self.columns
            local width=columns.width
            for i,cell in ipairs(self.cells) do
                local index=offset+i;local row=self.filtered[index];cell.row=row;cell.listIndex=index
                cell.outcome=confirm and row and self.outcomes[row.key] or nil
                if row then
                    cell:ClearAllPoints();cell:SetPoint('TOPLEFT',0,-(index-1)*self.rowStep);cell:SetSize(width,self.rowHeight)
                    cell.check:SetValue(self.selected[row.key]==true,true)
                    cell.check:SetShown(not confirm);cell:SetSelected(not confirm and self.selected[row.key]==true)
                    cell.icon:ClearAllPoints();cell.icon:SetPoint('LEFT',confirm and 4 or 32,0)
                    local icon=row.rule.trigger.extension and select(2,S.EditorModel:ObjectInfo(row.rule.object,row.rule.trigger.extension))
                    cell.icon:SetIcon(icon or row.rule.object.kind~='event' and YUI.API.Spell.GetTexture(row.rule.object.id) or row.icon)
                    cell.tier:SetText(T(row.core and 'core' or 'extended'));cell.tier:SetWidth(TextWidth(cell.tier))
                    GUI:SetTextColorKey(cell.tier,row.core and 'color.text.accent' or 'color.tooltip.subheading')
                    cell.name:ClearAllPoints();cell.name:SetPoint('TOPLEFT',cell.icon,'TOPRIGHT',8,0)
                    cell.name:SetText(Name(row));cell.name:SetWidth(columns.object-self.textLeft-8)
                    cell.tier:ClearAllPoints();cell.tier:SetPoint('TOPLEFT',cell.name,'BOTTOMLEFT',0,0)
                    local scope,icons=Scope(row)
                    local scopeWidth=columns.object-self.textLeft-cell.tier:GetWidth()-16
                    local iconCount=math.min(#icons,4,math.max(0,math.floor((scopeWidth-24)/SCOPE_ICON_STEP)))
                    for n=1,math.max(iconCount,#cell.scopeIcons) do
                        local icon=cell.scopeIcons[n]
                        if not icon then
                            icon=GUI:CreateIcon(cell,{width=SCOPE_ICON_SIZE,height=SCOPE_ICON_SIZE,texture=134400})
                            cell.scopeIcons[n]=icon
                        end
                        icon:SetShown(n<=iconCount)
                        if n<=iconCount then
                            local entry=icons[n]
                            local native=YUI.IsForever and entry.classInfo.icon or entry.nativeIcon or entry.icon
                            local api=YUI.API.Icons
                            local data=not YUI.IsForever and api and api.GetScopedSpecIcon and api.GetScopedSpecIcon(entry.specID,native,'settings')
                            if data and data.custom==false then native=data.texture or native;data=nil end
                            if not (data and api.ApplyIcon and api.ApplyIcon(icon,data)) then
                                icon:SetTexture(native or entry.icon);icon:SetTexCoord(unpack(YUI.IsForever and entry.classInfo.iconTexCoord or scopeIconCrop))
                            end
                            icon:ClearAllPoints();icon:SetPoint('BOTTOMLEFT',cell.tier,'BOTTOMRIGHT',8+(n-1)*SCOPE_ICON_STEP,0)
                        end
                    end
                    cell.scope:ClearAllPoints();cell.scope:SetPoint('TOPLEFT',cell.tier,'TOPRIGHT',8+iconCount*SCOPE_ICON_STEP,0)
                    cell.scopeInIcons=not YUI.IsForever and iconCount>0 and iconCount==#icons
                    cell.scope:SetText(cell.scopeInIcons and (row.race and RaceName(row.race) or '') or scope);cell.scope:SetWidth(scopeWidth-iconCount*SCOPE_ICON_STEP)
                    cell.when:ClearAllPoints();cell.when:SetPoint('LEFT',cell,'LEFT',columns.object+8,0);cell.when:SetWidth(columns.when-16)
                    cell.when:SetText(S.EditorModel:TriggerLabel(row.rule))
                    cell.play:ClearAllPoints();cell.play:SetPoint('LEFT',cell,'LEFT',columns.object+columns.when+8,0)
                    cell.voice:ClearAllPoints();cell.voice:SetPoint('LEFT',cell.play,'RIGHT',8,0);cell.voice:SetWidth(columns.voice-50)
                    cell.voice:SetText(S.EditorModel:SoundLabel(DisplayRule(cell).sound))
                    cell.result:SetShown(confirm);cell.detail:SetShown(confirm)
                    if confirm then
                        local item=cell.outcome
                        cell.result:ClearAllPoints();cell.result:SetPoint('TOPLEFT',cell.name,'TOPLEFT',columns.object+columns.when+columns.voice+8-self.textLeft,0);cell.result:SetWidth(columns.result-16)
                        cell.result:SetText(T('result.'..item.status));GUI:SetTextColorKey(cell.result,item.status=='add' and 'color.text.accent' or item.status=='skip' and 'color.tooltip.warning' or 'color.tooltip.subheading')
                        cell.detail:ClearAllPoints();cell.detail:SetPoint('TOPLEFT',cell.result,'BOTTOMLEFT',0,0);cell.detail:SetWidth(columns.result-16);cell.detail:SetText(ResultDetail(item,self.enabled))
                    end
                    cell:Show()
                else cell:Hide() end
            end
        end
        function frame:RefreshRows()
            local core,extended={},{}
            self.outcomes={}
            if self.stage=='confirm' then
                for _,item in ipairs(self.prepared.outcomes) do
                    self.outcomes[item.row.key]=item
                    if self.result=='all' or self.result==item.status then core[#core+1]=item.row end
                end
            else for _,row in ipairs(P:Rows()) do
                local matches=row.section==self.section and (self.section~='class' or self.class=='all' or row.class==self.class)
                    and (self.tier=='all' or (self.tier=='core')==row.core)
                if matches and (self.query=='' or (Name(row)..' '..row.name..' '..S.EditorModel:SoundLabel(row.rule.sound)..' '..S.EditorModel:TriggerLabel(row.rule)..' '..Scope(row)..' '..Scope(row,true)..' '..tostring(row.rule.object.id)..' '..table.concat(row.aliases or {},' ')):lower():find(self.query,1,true)) then
                    local bucket=row.core and core or extended;bucket[#bucket+1]=row
                end
            end end
            self.filtered=core;for _,row in ipairs(extended) do self.filtered[#self.filtered+1]=row end
            self:HideRowTip()
            self.scroll:SetVerticalScroll(0)
            self:Layout();self:PaintRows();self:Layout()
        end
        frame.scroll:HookScript('OnVerticalScroll',function() frame:PaintRows() end)
        frame:SetScript('OnHide',function()
            frame.search:ClearFocus();frame.prepared=nil;frame.outcomes={}
            for _,cell in ipairs(frame.cells) do cell.outcome=nil end
            YUI.Event:OffOwner(frame);S:StopPreview()
            frame:HideRowTip()
        end)
        function frame:OnChanged()
            if self.committing then return end
            local reviewing=self.stage=='confirm'
            self:Invalidate();self:RefreshRows()
            if reviewing then self.status:SetText(T('changed')) end
        end
        frame:SetScript('OnShow',function()
            for _,event in ipairs({'YUI_SOUND_RULES_CHANGED','YUI_SOUND_CONTEXT_CHANGED','YUI_SOUND_ENTRIES_CHANGED','YUI_SOUND_PACKS_CHANGED'}) do
                YUI.Event:On(event,'OnChanged',frame,{moduleId='sound.settings'})
            end
        end)
    end
    frame:SetParent(self:GetModalParent());frame:ClearAllPoints();frame:SetPoint('CENTER',self:GetModalParent())
    frame:SetFrameStrata(self:GetModalParent():GetFrameStrata());frame:SetFrameLevel(self:GetModalParent():GetFrameLevel()+40)
    frame:SetSize(math.max(560,math.min(1000,self:GetModalParent():GetWidth()-24)),math.max(440,math.min(660,self:GetModalParent():GetHeight()-24)))
    frame.tabs:SetWidth(frame:GetWidth()-32)
    local _,key=S.EditorModel:CurrentSpec()
    frame.class=(self.view and self.view.designSpec or ''):match('^([^:]+):') or key and key:match('^([^:]+):') or 'all'
    frame.selected=P:DefaultSelection(frame.class);frame.section='class';frame.tier='all';frame.enabled=true;frame.query=''
    frame.selectionScroll=0;frame:Invalidate();frame.search:SetValue('',true)
    frame.classPicker:RefreshOptions();frame.classPicker:SetValue(frame.class,true);frame.tierPicker:SetValue('all',true);frame.enabledPicker:SetValue(true,true)
    frame:RefreshRows();frame:Show()
    local scrim=GUI:ShowModalScrim(frame)
    if scrim then scrim:SetParent(frame:GetParent());scrim:ClearAllPoints();scrim:SetAllPoints(frame:GetParent()) end
    return frame
end
