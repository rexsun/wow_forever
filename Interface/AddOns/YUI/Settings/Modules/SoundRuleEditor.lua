local YUI=_G.YUI
local Settings,GUI=YUI and YUI.Settings,YUI and YUI.GUI2
local Center=Settings and Settings.SoundCenter
if not (Center and GUI) then return end
local Form,T=GUI.Form,Center.Text
local function DisplaySpec(dialog)
    local selected=dialog.pickerSpec
    return selected and tonumber(selected:match(':(%d+)$')) or YUI.Sound.EditorModel:RuleSpec(dialog.edit.rule)
end
local function Label(parent,key,y)
    local label=GUI:CreateText(parent,T(key),'font.size.md','color.text.primary','LEFT')
    label:SetPoint('TOPLEFT',0,-y); return label
end
local function Button(parent,key,click,width)
    return Form:CreateButton(parent,{text=T(key),height=40,width=width or 120,tone='default',onClick=click})
end
-- Local choice layout; uses GUI2 buttons and never changes shared control semantics.
local function Choices(parent, options, columns, changed, compact)
    local group=GUI:CreateFrame(parent,{width=600,height=110})
    group.buttons={}
    function group:RefreshOptions()
        self.options=type(options)=='function' and options() or options
        for i,item in ipairs(self.options) do
            local button=self.buttons[i]
            if not button then
                button=Form:CreateButton(self,{height=compact and 34 or 46,width=160,text='',tone='default',contentAlign='center',onClick=function(control)
                    if not self.disabled then changed(control.value) end
                end})
                self.buttons[i]=button
            end
            button.value=item.value; button:SetText(item.text); button:Show()
        end
        for i=#self.options+1,#self.buttons do self.buttons[i]:Hide() end
        self:Layout(self:GetWidth())
    end
    function group:Layout(width)
        self:SetWidth(width)
        local n=math.min(columns,math.max(1,math.floor(width/(compact and 100 or 130))))
        local pitch=compact and 42 or 56
        local w=(width-(n-1)*10)/n
        for i,button in ipairs(self.buttons) do
            button:SetWidth(w); button:ClearAllPoints()
            button:SetPoint('TOPLEFT',((i-1)%n)*(w+10),-math.floor((i-1)/n)*pitch)
        end
        self:SetHeight(math.ceil(#(self.options or {})/n)*pitch)
    end
    function group:SetValue(value)
        self.value=value
        for _,button in ipairs(self.buttons) do button:SetSelected(button.value==value) end
    end
    function group:SetDisabled(value)
        self.disabled=value
        for _,button in ipairs(self.buttons) do button:SetDisabled(value) end
    end
    group:RefreshOptions()
    return group
end
local function BindObjectTooltip(target)
    target:HookScript('OnEnter',function(owner)
            if not (GameTooltip and owner.entry) then return end
            local entry=owner.entry; local object=entry.object
            local presentation=YUI.Sound.EditorModel.PresetPresentation[entry.extension]
            local tooltipSpellID=presentation and presentation.tooltipSpellID or entry.displayID or YUI.Sound.EditorModel:DisplayID(object,entry.spec)
            GameTooltip:SetOwner(owner,'ANCHOR_RIGHT')
            if object.kind=='itemGroup' or object.kind=='spellGroup' then
                GameTooltip:SetText(entry.name)
                for _,member in ipairs(YUI.Sound.EditorModel:PotionMembers(object)) do
                    GameTooltip:AddLine('|T'..member.icon..':20:20|t '..member.name,1,1,1,false)
                end
                GameTooltip:Show()
                return
            end
            local shown=false
            if object.kind=='item' and GameTooltip.SetItemByID then shown=pcall(GameTooltip.SetItemByID,GameTooltip,object.id)
            elseif (object.kind=='spell' or object.kind=='aura' or object.kind=='totem') and GameTooltip.SetSpellByID then shown=pcall(GameTooltip.SetSpellByID,GameTooltip,tooltipSpellID)
            elseif (object.kind=='slot' or object.kind=='equipmentAura') and GameTooltip.SetInventoryItem then shown=pcall(GameTooltip.SetInventoryItem,GameTooltip,'player',object.id) end
            local details='ID '..tostring(object.id)
            if not shown then GameTooltip:SetText(entry.name) end
            if not shown then
                details=details:gsub('^ID (.+)$','|cffff4040ID|r |cffffd100%1|r')
                GameTooltip:AddLine(details,1,1,1,false)
            end
            if object.kind=='aura' then
                GameTooltip:AddLine(T('auraSpellDescription'),1,1,1,true)
                GameTooltip:AddLine(T('auraBindingRequired'),1,0.82,0,true)
            end
            GameTooltip:Show()
        end)
        local function hideTip(owner) if GameTooltip and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end end
        target:HookScript('OnLeave',hideTip); target:HookScript('OnHide',hideTip)
end
-- Local surface adjustment: keep theme colors, prevent underlying settings from showing through.
local function SetSoundSurface(panel,detail)
    local original=panel.RefreshTheme
    local function Paint(frame)
        if original then original(frame) end
        local r,g,b=GUI:GetColor('color.surface.popup')
        if detail then
            local dr,dg,db=GUI:GetColor('color.surface.sunken')
            r,g,b=r*0.7+dr*0.3,g*0.7+dg*0.3,b*0.7+db*0.3
        end
        frame:SetBackdropColor(r,g,b,1)
    end
    panel.RefreshTheme=Paint
    Paint(panel)
end
local function Summary(parent,styled)
    local card=styled and GUI:CreatePanel(parent,{height=64,surface='color.surface.sunken',border=false}) or GUI:CreateFrame(parent,{height=56})
    if styled then SetSoundSurface(card,true) end
    card:SetPoint('TOPLEFT'); card:SetPoint('TOPRIGHT')
    if styled then
        card.iconSlot=GUI:CreateIconSlot(card,{size=44,icon=134400,animate=false})
        card.iconSlot:SetPoint('TOPLEFT',10,-10)
        card.icon=card.iconSlot.icon
    else
        card.icon=GUI:CreateIcon(card,{width=36,height=36,texture=134400}); card.icon:SetPoint('TOPLEFT',0,-10)
    end
    card.tooltipTarget=GUI:CreateFrame(card,{width=36,height=36,mouse=true}); card.tooltipTarget:SetPoint('TOPLEFT',card.icon,'TOPLEFT')
    if styled then card.tooltipTarget:ClearAllPoints(); card.tooltipTarget:SetAllPoints(card.iconSlot) end
    BindObjectTooltip(card.tooltipTarget)
    card.label=GUI:CreateText(card,'','font.size.md','color.text.primary','LEFT'); card.label:SetPoint('TOPLEFT',card.iconSlot or card.icon,'TOPRIGHT',12,0)
    card.detail=GUI:CreateText(card,'','font.size.md','color.text.secondary','LEFT'); card.detail:SetPoint('TOPLEFT',card.icon,'BOTTOMRIGHT',12,16); card.detail:SetHeight(16); card.detail:SetJustifyV('BOTTOM')
    card.talentIcon=GUI:CreateIcon(card,{width=16,height=16,texture=134400});card.talentIcon:Hide()
    card.talentName=GUI:CreateText(card,'','font.size.md','color.text.primary','LEFT');card.talentName:Hide()
    card.talentTooltip=GUI:CreateFrame(card,{width=250,height=16,mouse=true});card.talentTooltip:SetPoint('TOPLEFT',card.detail,'TOPLEFT');card.talentTooltip:Hide();BindObjectTooltip(card.talentTooltip)
    return card
end
local function VoiceButton(parent,click,width)
    return Form:CreateButton(parent,{text=T('chooseVoice'),width=width or 300,height=54,tone='default',
        icon=GUI:GetSettingsIcon('sound'),iconSize=28,crop=false,preserveIconColor=true,contentAlign='left',iconGap=12,onClick=click})
end
local function VoicePicker(dialog,field)
    local rule=dialog.edit.rule
    local name=YUI.Sound.EditorModel:ObjectInfo(rule.object,rule.trigger.extension,DisplaySpec(dialog))
    local names={name}
    local presentation=YUI.Sound.EditorModel.PresetPresentation
    local preset=presentation and presentation[rule.trigger.extension]
    local spell=YUI.API and YUI.API.Spell
    if preset and spell and spell.GetName then names[#names+1]=spell.GetName(preset.tooltipSpellID) end
    GUI.VoicePicker:Open(Center:GetModalParent(),{current=rule.sound[field],matchNames=names,
        onSelect=function(id)
            if dialog.edit then
                local selected=dialog.edit.rule.sound
                if selected[field]~=id then
                    YUI.Sound:StopPreview()
                    if field=='value' and selected.kind=='forecast' then selected.introDuration=nil end
                    selected[field]=id
                end
                dialog:RefreshSound()
            end
        end,
        preview=function(id) Center:PreviewVoice(id) end,stopPreview=function() YUI.Sound:StopPreview() end})
end
function Center:OpenEditor(index,category,spec)
    local sound=YUI.Sound
    sound.EditorModel:RefreshCatalog()
    local edit,code=sound.EditorModel:Begin(index,category,spec~='all' and spec or nil)
    if not edit then self:Message(code); return end
    local browseKey=Settings:GetCurrentSpecSelectionKey() or 'all'
    if index then
        if sound.EditorModel:IsRacial(edit.rule.object) then browseKey='racial'
        elseif sound.EditorModel:ObjectCategory(edit.rule.object)=='general' then browseKey='general'
        else
            browseKey=edit.rule.specs and edit.rule.specs[1]
            if not browseKey then
                local definition=sound.EditorModel:Definition(edit.rule.object)
                for _,group in ipairs(Settings:GetSpecSelectionGroups({})) do
                    for _,info in ipairs(group.specs or {}) do
                        for _,id in ipairs(definition and definition.specs or {}) do
                            if id==info.specID then browseKey=browseKey or info.classInfo.token..':'..id end
                        end
                    end
                end
            end
            browseKey=browseKey or 'all'
        end
    end
    local startStep=1
    if index then
        startStep=3
        local _,why=sound.RuleModel:Normalize(edit.rule)
        if why and (why:find('object',1,true) or why=='invalid-slot' or why=='invalid-unit') then startStep=1
        elseif why and (why:find('trigger',1,true) or why:find('threshold',1,true) or why:find('duration',1,true)) then startStep=2 end
    end
    local parent=self:GetModalParent()
    if not parent then return end
    if self.editor then
        self.editor:Hide(); self.editor.kind=sound.EditorModel:PickerKind(edit.rule.object,edit.rule.trigger.extension); self.editor.pickerSpec=browseKey; self.editor.objectFilterKey=nil; self.editor.edit=edit; self.editor.step=startStep; self.editor.reached=index and 3 or 1; self.editor.query=''; self.editor.offset=0
        self.editor.search:SetValue('',true)
        self.editor.errorLabel:SetText('')
        self.editor:Refresh(); self.editor:Show(); self.editor:ShowScrim(); return self.editor
    end
    local dialog=GUI:CreatePanel(parent,{width=parent:GetWidth()-24,height=parent:GetHeight()-24,
        surface='color.surface.popup',border='color.popup.border',shadow=true})
    SetSoundSurface(dialog,false)
    self.editor=dialog; dialog.pickerSpec=browseKey; dialog.edit=edit; dialog.step=startStep; dialog.reached=index and 3 or 1; dialog.query=''; dialog.offset=0; dialog.kind=sound.EditorModel:PickerKind(edit.rule.object,edit.rule.trigger.extension)
    dialog:SetPoint('CENTER'); dialog:SetFrameStrata(parent:GetFrameStrata()); dialog:SetFrameLevel(parent:GetFrameLevel()+20); dialog:EnableMouse(true)
    local header=GUI:CreatePanel(dialog,{height=44,surface='color.surface.panel',border='color.border.subtle'}); header:SetPoint('TOPLEFT'); header:SetPoint('TOPRIGHT')
    local footer=GUI:CreatePanel(dialog,{height=56,surface='color.surface.panel',border='color.border.subtle'}); footer:SetPoint('BOTTOMLEFT'); footer:SetPoint('BOTTOMRIGHT')
    local title=Label(header,index and 'edit' or 'add',16); title:ClearAllPoints(); title:SetPoint('TOPLEFT',18,-16)
    local close=GUI:CreateCloseButton(header,function() dialog:Hide() end); close:SetPoint('TOPRIGHT',-14,-12)
    local pages={}
    local stepper=Form:CreateStepper(dialog,{items={T('stepObject'):gsub('^%d+%s*',''),T('stepTrigger'):gsub('^%d+%s*',''),(T('stepSound'):gsub('^%d+%s*',''))},
        onChange=function(i) dialog.step=i; dialog:Refresh() end})
    stepper:SetPoint('TOPLEFT',18,-52)
    local stepDetails,stepTitles={},{}
    for i=1,3 do
        stepTitles[i]=GUI:CreateText(stepper,T(({ 'stepObject','stepTrigger','stepSound' })[i]):gsub('^%d+%s*',''),'font.size.md','color.text.secondary','LEFT')
        stepTitles[i]:SetWordWrap(false)
        stepTitles[i]:SetJustifyH('LEFT')
        stepDetails[i]=GUI:CreateText(stepper,'','font.size.md','color.text.primary','LEFT')
        stepDetails[i]:SetWordWrap(false)
        stepDetails[i]:SetJustifyH('LEFT')
    end
    function dialog:RefreshStepDetails()
        local width=self:GetWidth()
        local name=sound.EditorModel:ObjectInfo(self.edit.rule.object,self.edit.rule.trigger.extension,DisplaySpec(self))
        stepper:SetWidth(width-36);stepper:SetStep(self.step,self.reached)
        stepper:SetHeight(56)
        local rule=self.edit.rule
        local summaries={rule.object.id~=0 and name or '',
            self.reached>=2 and sound.EditorModel:TriggerLabel(rule,DisplaySpec(self)) or '',
            self.reached>=3 and rule.sound.value~=nil and rule.sound.value~='' and sound.EditorModel:SoundLabel(rule.sound) or ''}
        local cell=(width-60)/3
        for i,detail in ipairs(stepDetails) do
            local hasSummary=summaries[i]~=nil and summaries[i]~=''
            detail:SetText(summaries[i] or '');detail:SetShown(hasSummary)
            detail:ClearAllPoints();detail:SetPoint('TOPLEFT',(i-1)*(cell+12)+32,-26)
            detail:SetSize(math.max(1,cell-40),16)
            local title=stepTitles[i]
            title:ClearAllPoints();title:SetPoint('TOPLEFT',(i-1)*(cell+12)+32,hasSummary and -6 or -16)
            title:SetSize(math.max(1,cell-40),16)
            local step=stepper.steps and stepper.steps[i]
            if step then
                step:SetHeight(56);step.label:Hide()
                step.circle:ClearAllPoints();step.circle:SetPoint('TOPLEFT',0,-12)
            end
        end
    end
    for i=1,3 do
        local page=GUI:CreateFrame(dialog); pages[i]=page
        page:SetPoint('TOPLEFT',18,-120); page:SetPoint('BOTTOMRIGHT',-18,80)
    end
    local errorLabel=GUI:CreateText(footer,'','font.size.md','color.state.warning','LEFT')
    dialog.errorLabel=errorLabel
    errorLabel:SetPoint('LEFT',120,0);errorLabel:SetHeight(36);errorLabel:SetWordWrap(true);errorLabel:SetJustifyV('MIDDLE')
    local cancel=Form:CreateTextLink(dialog,{text=T('cancel'),width=90,height=34,colorKey='color.text.secondary',onClick=function() dialog:Hide() end}); cancel:SetHeight(34); cancel:SetPoint('BOTTOMLEFT',18,10)
    local nextButton=Form:CreateButton(dialog,{text=T('next'),height=34,width=100,tone='accent',onClick=function()
        if dialog.step<3 then dialog.step=dialog.step+1; dialog.reached=math.max(dialog.reached,dialog.step); dialog:Refresh(); return end
        local ok,why,detail=sound.EditorModel:Save(dialog.edit)
        if ok then
            local rule=dialog.edit.rule
            local category=rule.category or sound.EditorModel:ObjectCategory(rule.object)
            local current=Settings:GetCurrentSpecSelectionKey()
            local destination=current or 'all'
            if category=='general' then destination='general'
            elseif rule.specs then
                destination=rule.specs[1] or 'all'
                for _,key in ipairs(rule.specs) do if key==current then destination=current;break end end
            else
                for _,key in ipairs(rule.exceptSpecs or {}) do if key==current then destination='all';break end end
            end
            dialog:Hide()
            if Center.view then
                Center.view.category=category;Center.view.designSpec=destination;Center.view.query=''
                Center.view.searchInput:SetValue('',true);Center.view.status:SetText('');Center.view:Refresh()
            end
        else errorLabel:SetText(Center:ErrorText(why,detail)) end
    end})
    nextButton:SetPoint('BOTTOMRIGHT',-18,10)
    Form:StyleDialogPrimary(nextButton)
    local previous=Button(dialog,'previous',function() dialog.step=math.max(1,dialog.step-1); dialog:Refresh() end,100)
    previous:SetHeight(34); previous:SetPoint('RIGHT',nextButton,'LEFT',-10,0)

    local picker=GUI:CreateFrame(pages[1]); picker:SetAllPoints(pages[1])
    local function KindTab(icon,key)
        return '|T'..icon..':12:12:0:1:64:64:5:59:5:59|t '..T(key)
    end
    local kind=GUI:CreateFrame(picker,{width=600,height=40})
    kind:SetPoint('TOP',picker,'TOP',0,0)
    kind.buttons={}
    for i,entry in ipairs({{icon=135812,key='spell'},{icon=136170,key='aura'},{icon=134829,key='item'}}) do
        local key=entry.key
        local tab=Form:CreateButton(kind,{width=200,height=40,tone='default',fontSizeKey='font.size.lg',
            text=KindTab(entry.icon,key),onClick=function()
                dialog.kind=key; dialog.autoSelect=true; dialog.query=''; dialog.search:SetValue('',true); dialog.offset=0
                kind:SetValue(key); dialog:RefreshObjects()
            end})
        tab:SetPoint('TOPLEFT',(i-1)*108,0)
        tab.indicator=GUI:CreatePanel(tab,{height=2,surface='color.text.accent',border='color.text.accent'})
        tab.indicator:SetPoint('BOTTOMLEFT',0,0); tab.indicator:SetPoint('BOTTOMRIGHT',0,0)
        tab.value=key; kind.buttons[i]=tab
    end
    function kind:SetValue(value)
        for _,tab in ipairs(self.buttons) do
            local selected=tab.value==value
            tab:SetSelected(selected); tab.indicator:SetShown(selected)
        end
    end
    kind:SetValue(dialog.kind)

    local browseLabel=Label(picker,'browseCategory',55)
    browseLabel:SetWidth(76)
    local pickerSpec=Form:CreateSpecDropdown(picker,{width=270,height=34,menuWidth=320,options=function() return Center:PickerOptions(dialog.kind) end,
        get=function() return dialog.pickerSpec or 'all' end,
        set=function(value) dialog.pickerSpec=value; dialog.offset=0; dialog:RefreshObjects() end})
    pickerSpec:SetPoint('TOPLEFT',84,-50); pickerSpec:SetHeight(30)
    function dialog:RefreshSpecIcons() Center:RefreshSpecDropdown(pickerSpec) end
    function dialog:OnIconScopeChanged(_,scope)
        if not scope or scope=='settings' then self:RefreshSpecIcons() end
    end
    function dialog:RegisterIconEvents()
        if not YUI.Event then return end
        YUI.Event:OffOwner(self)
        YUI.Event:On('YUI_APPEARANCE_ICON_SET_CHANGED','RefreshSpecIcons',self,{moduleId='sound.settings'})
        YUI.Event:On('YUI_APPEARANCE_ICON_SCOPE_CHANGED','OnIconScopeChanged',self,{moduleId='sound.settings'})
        self:RefreshSpecIcons()
    end
    dialog:HookScript('OnShow',dialog.RegisterIconEvents)
    local search=Form:CreateEditBox(picker,{width=320,height=34,placeholder=T('browseSearch'),searchPlaceholder=true,onChange=function(_,value)
        dialog.query=value or ''; dialog.offset=0; if dialog.RefreshObjects then dialog:RefreshObjects() end
    end})
    search:SetPoint('LEFT',pickerSpec,'RIGHT',8,0)
    dialog.search=search
    local grid=GUI:CreateScrollFrame(picker,{height=190,autoHide=true}); grid:SetPoint('TOPLEFT',0,-90); grid:SetPoint('BOTTOMRIGHT',-18,110)
    if grid.HookScript then grid:HookScript('OnVerticalScroll',function() if dialog.PaintObjectRows then dialog:PaintObjectRows() end end) end
    local empty=Label(grid,'noObjects',12); empty:SetWidth(440)
    local cards={}
    local function Choose(entry)
        local rule=dialog.edit.rule
        if rule.object.kind==entry.object.kind and rule.object.id==entry.object.id and rule.trigger.extension==entry.extension then return end
        rule.object=sound.EditorModel.Copy(entry.object)
        rule.category=sound.EditorModel:ObjectCategory(entry.object)
        if not entry.extension then
            if rule.category=='general' then rule.specs=nil; rule.exceptSpecs=nil
            elseif entry.specs then
                local desired={}; for _,id in ipairs(entry.specs) do desired[id]=true end
                local specs={}
                for _,group in ipairs(Settings:GetSpecSelectionGroups({})) do
                    for _,info in ipairs(group.specs or {}) do if desired[info.specID] then specs[#specs+1]=info.classInfo.token..':'..info.specID end end
                end
                rule.specs=#specs>0 and specs or {Settings:GetCurrentSpecSelectionKey()}; rule.exceptSpecs=nil
            else rule.specs={dialog.pickerSpec and dialog.pickerSpec:match(':%d+$') and dialog.pickerSpec or Settings:GetCurrentSpecSelectionKey()}; rule.exceptSpecs=nil
            end
        end
        rule.trigger={event=(entry.object.kind=='aura' or entry.object.kind=='equipmentAura') and 'auraAdded' or 'ready'}
        if entry.object.kind=='totem' then rule.trigger={event='totemAdded'} end
        if sound.EditorModel:CastOnly(entry.object) then rule.trigger={event='castAfter',value=0} end
        if entry.extension=='bone-shield' then
            rule.trigger={event='castAfter',value=8,extension=entry.extension};rule.specs={'DEATHKNIGHT:250'};rule.exceptSpecs=nil
            rule.talents={};rule.sound={kind='boneShield',value='VC-a52996f7',ending='VC-a52996f7'}
        elseif entry.extension=='boiling-point' then
            rule.trigger={event='castAfter',value=0,extension=entry.extension}; rule.specs={'DEATHKNIGHT:250'}; rule.exceptSpecs=nil
            rule.talents={}; rule.sound={kind='eventWindow',value='VC-663694e8',ending='',endingKind='none'}
        elseif entry.extension then
            rule.trigger={event='castAfter',value=0,extension=entry.extension}; rule.specs={'MAGE:62'}; rule.exceptSpecs=nil
            rule.talents={[449619]=true}; rule.sound={kind='forecast',value='VC-423839e5',ending='VC-9def7fac',countdown=3,gap=0.2}
        else
            rule.talents={}
            if rule.sound.kind=='forecast' or rule.sound.kind=='eventWindow' or rule.sound.kind=='boneShield' then rule.sound={kind='voice',value=''} end
            if entry.object.kind=='itemGroup' then
                rule.sound={kind='voice',value=entry.object.id=='health-potion' and 'VC-a601c865' or 'VC-9f52f98a'}
            end
        end
        local potion=sound.EditorModel:PotionBuff(rule.object)
        if potion then rule.trigger={event='timerStarted',duration=potion.duration,policy='restart'} end
        dialog:RefreshObjects(); if dialog.RefreshTrigger then dialog:RefreshTrigger() end
    end
    local cardMeasure=GUI:CreateText(grid.child,'汉字宽度测试余','font.size.md','color.text.primary','LEFT');cardMeasure:Hide()
    local cardPitch=46
    local function CardColumns()
        return math.max(1,math.floor((grid:GetWidth()+8)/(math.ceil(cardMeasure:GetStringWidth())+78)))
    end
    for i=1,64 do
        local card=Form:CreateButton(grid.child,{width=180,height=38,text='',contentAlign='left',tone='default',onClick=function(button)
            if button.entry then Choose(button.entry) end
        end})
        BindObjectTooltip(card)
        cards[i]=card
        card.badge=GUI:CreateText(card,'','font.size.md','color.badge.orange','CENTER'); card.badge:SetPoint('BOTTOMLEFT',4,3); card.badge:SetHeight(14); card.badge:SetWordWrap(false)
        local badgeFont,badgeSize=card.badge:GetFont()
        GUI:ApplyFontAppearance(card.badge,{font=badgeFont,size=badgeSize,outline='outlineShadow'})
        card.icon=GUI:CreateIcon(card,{width=32,height=32,texture=134400}); card.icon:SetPoint('LEFT',4,0); card.gui2PreserveIconColor=true
        card.label=GUI:CreateText(card,'','font.size.md','color.text.primary','CENTER')
        card.label:SetPoint('LEFT',card,'LEFT',44,0); card.label:SetHeight(34); card.label:SetJustifyH('CENTER'); card.label:SetJustifyV('MIDDLE'); card.label:SetWordWrap(true)
        card.label:SetNonSpaceWrap(true)
    end
    local idPanel=GUI:CreatePanel(dialog,{width=520,height=340,surface='color.surface.popup',border='color.popup.border',shadow=true})
    SetSoundSurface(idPanel,false)
    idPanel:SetPoint('CENTER'); idPanel:SetFrameLevel(dialog:GetFrameLevel()+20); idPanel:EnableMouse(true)
    local idTitle=Label(idPanel,'objectID',18); idTitle:ClearAllPoints(); idTitle:SetPoint('TOPLEFT',18,-18)
    local RefreshManualPreview
    local custom=Form:CreateEditBox(idPanel,{width=484,height=40,placeholder=T('objectID'),onChange=function() if RefreshManualPreview then RefreshManualPreview() end end}); custom:SetPoint('TOPLEFT',18,-56)
    local idNote=Label(idPanel,'customIDNote',112); idNote:ClearAllPoints(); idNote:SetPoint('TOPLEFT',18,-192); idNote:SetWidth(484); idNote:SetHeight(88); idNote:SetWordWrap(true)
    local idIcon=GUI:CreateIcon(idPanel,{width=32,height=32,texture=134400}); idIcon:SetPoint('TOPLEFT',18,-108)
    local idName=GUI:CreateText(idPanel,'','font.size.md','color.text.primary','LEFT'); idName:SetPoint('LEFT',idIcon,'RIGHT',8,0)
    local idState=GUI:CreateText(idPanel,'','font.size.md','color.text.secondary','LEFT'); idState:SetPoint('TOPLEFT',18,-150); idState:SetWordWrap(true)
    local inputID=Form:CreateTextLink(picker,{text=T('inputID'),width=88,height=24,onClick=function()
        idPanel:SetWidth(math.min(520,dialog:GetWidth()-36)); custom:SetWidth(idPanel:GetWidth()-36); idNote:SetWidth(idPanel:GetWidth()-36)
        idTitle:SetText(T(dialog.kind)..' ID'); custom:SetValue('',true); RefreshManualPreview()
        idPanel:Show(); local scrim=GUI:ShowModalScrim(idPanel)
        if scrim then scrim:SetParent(dialog); scrim:ClearAllPoints(); scrim:SetAllPoints(dialog) end
    end}); inputID:SetPoint('TOPRIGHT',-18,-8)
    local useID=Button(idPanel,'useID',function()
        local id=tonumber(custom:GetText())
        if not id or id<=0 or id>2147483647 or id%1~=0 then RefreshManualPreview(); return end
        local scope=dialog.pickerSpec
        local specID=scope and tonumber(scope:match(':(%d+)$'))
        local entry,why=sound.EditorModel:ManualObject(dialog.kind,id,specID)
        if not entry then RefreshManualPreview(); return end
        Choose(entry)
        if entry.unverified then dialog.edit.rule.enabled=false; errorLabel:SetText(T('unverifiedObject')) end
        idPanel:Hide(); dialog:Refresh()
    end,120); Form:StyleDialogPrimary(useID); useID:SetPoint('BOTTOMRIGHT',-18,14)
    RefreshManualPreview=function()
        local id=tonumber(custom:GetText())
        local scope=dialog.pickerSpec
        local specID=scope and tonumber(scope:match(':(%d+)$'))
        local entry,why=sound.EditorModel:ManualObject(dialog.kind,id,specID)
        local name,icon
        if entry then name,icon=sound.EditorModel:ObjectInfo(entry.object,nil,specID or -1) end
        idIcon:SetTexture(icon or 134400); idName:SetText(name or T('objectID'))
        idName:SetWidth(idPanel:GetWidth()-96); idState:SetWidth(idPanel:GetWidth()-36)
        idState:SetText(T(entry and (entry.unverified and 'manualUnverified' or 'manualKnown') or why=='object-kind-mismatch' and 'manualMismatch' or 'manualInvalid'))
        idNote:SetText(T('customIDNote')); useID:SetDisabled(not entry)
    end
    local cancelID=Form:CreateTextLink(idPanel,{text=T('back'),width=90,height=34,colorKey='color.text.secondary',onClick=function() idPanel:Hide() end}); cancelID:SetPoint('BOTTOMLEFT',18,14)
    idPanel:SetScript('OnHide',function() custom:ClearFocus() end); idPanel:Hide()
    local pickerSummary=Summary(picker,true); pickerSummary:ClearAllPoints(); pickerSummary:SetHeight(60); pickerSummary:SetPoint('BOTTOMLEFT',0,0)
    local summaryLine=GUI:CreateDivider(picker,100,1)
    summaryLine:SetPoint('BOTTOMLEFT',pickerSummary,'TOPLEFT',0,10); summaryLine:SetPoint('RIGHT',picker,'RIGHT',-18,0)
    local triggerScroll=GUI:CreateScrollFrame(pages[2],{width=600,height=300,autoHide=true}); triggerScroll:SetPoint('TOPLEFT'); triggerScroll:SetPoint('BOTTOMRIGHT',-18,0)
    local triggerBody=triggerScroll.child; triggerBody:SetHeight(340)
    local function Events()
        local rule=dialog.edit.rule; local events
        if rule.trigger.extension then events={'castAfter'}
        elseif sound.EditorModel:PotionBuff(rule.object) then events={'timerStarted','timerEnded','timerRemaining'}
        elseif rule.object.kind=='equipmentAura' then events={'auraAdded','auraRemoved'}
        elseif rule.object.kind=='totem' then events={'totemAdded','totemRemoved'}
        elseif rule.object.kind=='aura' then events={'auraAdded','auraRemoved'}
        elseif sound.EditorModel:CastOnly(rule.object) then events={'castAfter'}
        elseif rule.object.kind=='spell' then events={'ready','charge','cooldownStarted','castAfter'}
            if rule.trigger.duration then events[#events+1]=rule.trigger.event end
        elseif rule.object.kind=='item' or rule.object.kind=='slot' then events={'ready'}
        else events={'ready'} end
        local options={}
        for _,event in ipairs(events) do
            local label=rule.object.kind=='equipmentAura' and T(event=='auraAdded' and 'equipmentAuraAdded' or 'equipmentAuraRemoved') or T(event)
            if sound.EditorModel:PotionBuff(rule.object) then label=T(event=='timerStarted' and 'potionUsed' or event=='timerEnded' and 'potionEnded' or 'potionBefore') end
            if event=='ready' then label=sound.EditorModel:TriggerLabel({object=rule.object,trigger={event='ready'}},DisplaySpec(dialog)) end
            if event=='castAfter' then label=T('castChoice')
            elseif event=='auraRemaining' or event=='timerRemaining' then label=string.format(label,'N')
            elseif event=='auraStacks' then label=string.format(label,'≥ / ≤','N') end
            if event~='charge' or YUI.IsRetail then
                options[#options+1]={text=rule.trigger.extension and sound.EditorModel:TriggerLabel(rule) or label,value=event}
            end
        end
        return options
    end
    local triggerSummary=Summary(triggerBody)
    Label(triggerBody,'when',84)
    local event=Choices(triggerBody,Events,2,function(value)
            local rule=dialog.edit.rule
            if rule.trigger.event==value then return end
            local timer=value=='timerStarted' or value=='timerEnded' or value=='timerRemaining'
            rule.trigger={event=value,value=value=='castAfter' and 0 or (value=='auraRemaining' or value=='auraStacks' or value=='timerRemaining') and 3 or nil,
                operator=value=='auraStacks' and 'ge' or nil,duration=timer and (sound.EditorModel:PotionBuff(rule.object) or {}).duration or timer and 20 or nil,policy=timer and 'restart' or nil}
            if value=='auraRemoved' then rule.trigger.lossDelay=sound.EditorModel:DefaultLossDelay(rule.object) end
            dialog:RefreshTrigger()
        end)
    event:SetPoint('TOPLEFT',0,-118)
    local thresholdLabel=Label(triggerBody,'delaySeconds',48)
    local thresholdNote=Label(triggerBody,'zeroImmediate',0)
    local threshold=Form:CreateEditBox(triggerBody,{width=130,height=30,onChange=function(_,value)
        if dialog.edit and not dialog.refreshing then
            local trigger=dialog.edit.rule.trigger
            if trigger.event=='cast' then trigger.event='castAfter' end
            if trigger.event=='auraRemoved' then trigger.lossDelay=tonumber(value) or value
            else trigger.value=tonumber(value) end
        end
    end}); threshold:SetPoint('TOPLEFT',180,-44)
    local operator=Form:CreateDropdown(triggerBody,{width=192,height=30,options={{text=T('ge'),value='ge'},{text=T('le'),value='le'}},
        set=function(value) if dialog.edit then dialog.edit.rule.trigger.operator=value end end})
    operator:SetPoint('LEFT',threshold,'RIGHT',8,0)
    local unitLabel=Label(triggerBody,'unit',94)
    local unit=Form:CreateDropdown(triggerBody,{width=340,height=30,options={
        {text=T('player'),value='player'},{text=T('target'),value='target'},{text=T('focus'),value='focus'}},
        set=function(value) dialog.edit.rule.object.unit=value end})
    unit:SetPoint('TOPLEFT',180,-90)
    local unrestricted=Form:CreateCheckbox(triggerBody,{text=T('unlimited'),width=180,
        get=function() return dialog.edit.rule.specs==nil and dialog.edit.rule.exceptSpecs==nil end,
        set=function(value)
            local rule=dialog.edit.rule; rule.exceptSpecs=nil
            rule.specs=not value and {Settings:GetCurrentSpecSelectionKey()} or nil
            dialog:RefreshTrigger()
        end})
    unrestricted:SetParent(picker); unrestricted:SetPoint('BOTTOMLEFT',0,4)
    local loadSelection={}
    local loadLabel=Label(picker,'applicableSpecs',0)
    loadLabel:ClearAllPoints(); loadLabel:SetPoint('BOTTOMLEFT',0,10)
    local loadPicker=Settings:CreateSpecMultiSelectDropdown(picker,{owner=dialog,label=T('loadSummary'),width=240,height=34,
        defaultSelected=false,value=loadSelection,panelWidth=480,panelHeight=280,
        selectAllText=YUI.Locale:Get('Core')['settings.config_transfer.select_all'],clearText=YUI.Locale:Get('Core')['settings.config_transfer.clear_all'],
        armorLabels={cloth=YUI.Locale:Get('Core')['settings.config_sets.armor.cloth'],leather=YUI.Locale:Get('Core')['settings.config_sets.armor.leather'],mail=YUI.Locale:Get('Core')['settings.config_sets.armor.mail'],plate=YUI.Locale:Get('Core')['settings.config_sets.armor.plate']},
        summaryFormatter=function()
            local names,total={},0
            for _,group in ipairs(Settings:GetSpecSelectionGroups({})) do
                for _,spec in ipairs(group.specs or {}) do
                    total=total+1
                    if loadSelection[spec.key or (spec.classInfo.token..':'..spec.specID)] then names[#names+1]=spec.displayName end
                end
            end
            if total>0 and #names==total then return T('allSpecs') end
            return #names>0 and table.concat(names,' / ') or T('unlimited')
        end,
        set=function(values)
            if not dialog.edit then return end
            local chosen={}; for key,enabled in pairs(values) do if enabled then chosen[#chosen+1]=key end end
            table.sort(chosen); dialog.edit.rule.specs=chosen; dialog.edit.rule.exceptSpecs=nil
            dialog:RefreshTrigger()
        end})
    loadPicker:SetPoint('BOTTOMLEFT',110,0)
    function loadPicker:SetDisabled(disabled)
        self.gui2Disabled=disabled and true or false
        self:EnableMouse(not self.gui2Disabled)
        self:SetAlpha(self.gui2Disabled and 0.5 or 1)
    end
    loadPicker:HookScript('OnMouseUp',function(anchor)
        local panel=Settings.Elements.specMultiSelectPanel
        if anchor.gui2Disabled or Settings.Elements.specMultiSelectOwner~=dialog or not panel or not panel:IsShown() then return end
        panel:ClearAllPoints(); panel:SetPoint('BOTTOMLEFT',anchor,'TOPLEFT',0,8)
        -- Keep the shared popup above its TOOLTIP blocker.
        panel:SetFrameStrata('TOOLTIP'); panel:SetFrameLevel(9100)
    end)

    unrestricted:ClearAllPoints(); unrestricted:SetPoint('LEFT',loadPicker,'RIGHT',12,0)
    local lockedHint=GUI:CreateFrame(picker,{mouse=true})
    lockedHint:SetFrameLevel(loadPicker:GetFrameLevel()+5)
    lockedHint:SetScript('OnEnter',function(owner)
        if GameTooltip then
            GameTooltip:SetOwner(owner,'ANCHOR_RIGHT');GameTooltip:SetText(T('presetSpecLocked'));GameTooltip:Show()
        end
    end)
    local function HideLockedTip(owner) if GameTooltip and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end end
    lockedHint:SetScript('OnLeave',HideLockedTip);lockedHint:SetScript('OnHide',HideLockedTip)
    local loadText=Label(triggerBody,'forecastLoad',236)
    local durationLabel=Label(triggerBody,'timerDuration',278)
    local duration=Form:CreateEditBox(triggerBody,{width=120,height=30,set=function(value)
        if dialog.edit and not dialog.refreshing then dialog.edit.rule.trigger.duration=tonumber(value) end
    end})
    duration:SetPoint('TOPLEFT',180,-274)
    local policyLabel=Label(triggerBody,'timerRepeat',322)
    local policy=Form:CreateDropdown(triggerBody,{width=340,height=30,
        options={{text=T('timerIgnore'),value='ignore'},{text=T('timerRestart'),value='restart'},{text=T('timerParallel'),value='parallel'}},
        set=function(value) if dialog.edit and not dialog.refreshing then dialog.edit.rule.trigger.policy=value end end})
    policy:SetPoint('TOPLEFT',180,-318)

    local soundScroll=GUI:CreateScrollFrame(pages[3],{width=600,height=300,autoHide=true}); soundScroll:SetPoint('TOPLEFT'); soundScroll:SetPoint('BOTTOMRIGHT',-18,0)
    local soundBody=soundScroll.child; soundBody:SetHeight(340)
    local soundSummary=Summary(soundBody)
    soundSummary:Hide()
    local playTitle=Label(soundBody,'soundSource',82)
    local mode=Choices(soundBody,{
        {text=T('voiceEntry'),value='voice'},{text=T('system'),value='system'},
        {text=T('tts'),value='tts'},{text=T('lsm'),value='lsm'},{text=T('custom'),value='custom'}},5,function(value)
        local current=dialog.edit.rule.sound
        if current.kind~=value then dialog.edit.rule.sound={kind=value,value=''} end
        dialog:RefreshSound()
    end,true)
    mode:SetPoint('TOPLEFT',88,0)
    local chooseVoice=VoiceButton(soundBody,function() VoicePicker(dialog,'value') end,300)
    chooseVoice:SetPoint('TOPLEFT',0,-46)
    local soundText=Form:CreateEditBox(soundBody,{width=460,height=30,onChange=function(_,value)
        if dialog.edit and not dialog.refreshing then
            dialog.edit.rule.sound.value=value; dialog:RefreshStepDetails()
        end
    end}); soundText:SetPoint('TOPLEFT',0,-46)
    local inputLabel=Label(soundBody,'playContent',86)
    local sourceHelp=GUI:CreateText(soundBody,'','font.size.md','color.text.secondary','LEFT')
    sourceHelp:SetWordWrap(true)
    local function PreviewEffect(option)
        if not dialog.edit then return end
        local kind,key=option.value:match('^([^:]+):(.+)$')
        if kind~='system' and kind~='lsm' then return end
        sound:StopPreview()
        local ok,why=sound:Submit(sound.Runtime.previewOwner,'preview',{kind=kind,value=key},true)
        errorLabel:SetText(ok and '' or Center:ErrorText(why))
    end
    local function EffectOptions(kind)
        local options=sound:GetSoundChoices({source=kind})
        for _,option in ipairs(options) do
            if option.available~=false and (kind=='system' or kind=='lsm') then
                option.actionFunc=PreviewEffect
                option.actionIcon=130979
                option.actionHighlightTexture=130977
                option.actionOriginalColor=true
                option.actionSize=24
                option.actionIconPadding=4
                option.actionTooltip=T('preview')
            end
        end
        return options
    end
    local effect=Form:CreateDropdown(soundBody,{width=460,height=30,searchable=function() return dialog.edit.rule.sound.kind=='lsm' end,searchPlaceholder=T('soundSearch'),searchEmptyText=T('empty'),options=function()
        local source=dialog.edit.rule.sound.kind
        return EffectOptions(source)
    end,set=function(value)
        local source,key=value:match('^([^:]+):(.+)$')
        if source and key then dialog.edit.rule.sound={kind=source,value=key};dialog:RefreshStepDetails() end
    end}); effect:SetPoint('TOPLEFT',0,-46)
    local introLabel=Label(soundBody,'intro',4)
    local intro=VoiceButton(soundBody,function() VoicePicker(dialog,'value') end,300); intro:SetPoint('TOPLEFT',0,-28)
    local countLabel=Label(soundBody,'countdown',84)
    local countdownOptions={}; for i=1,10 do countdownOptions[i]={text=tostring(i),value=i} end
    local boneTimeOptions={}; for i=1,15 do boneTimeOptions[i]={text=tostring(i),value=i} end
    local countdown=Form:CreateDropdown(soundBody,{width=160,height=30,options=function()
        return dialog.edit and dialog.edit.rule.sound.kind=='boneShield' and boneTimeOptions or countdownOptions
    end,
        set=function(value)
            if not dialog.edit or dialog.refreshing then return end
            local selected=dialog.edit.rule.sound
            local bone=selected.kind=='boneShield'
            if not bone and selected.kind~='forecast' then return end
            if type(value)~='number' or value<1 or value>(bone and 15 or 10) or value%1~=0 then return end
            if bone then
                if dialog.edit.rule.trigger.value==value then return end
                dialog.edit.rule.trigger.value=value
            else
                if selected.countdown==value then return end
                selected.countdown=value
            end
            dialog:RefreshSound()
        end}); countdown:SetPoint('TOPLEFT',0,-110)
    local endingLabel=Label(soundBody,'ending',168)
    local ending=VoiceButton(soundBody,function() VoicePicker(dialog,'ending') end,300); ending:SetPoint('TOPLEFT',0,-194)
    local forecastCards={}
    for i,parts in ipairs({{introLabel,intro},{countLabel,countdown},{endingLabel,ending}}) do
        local card=GUI:CreatePanel(soundBody,{width=200,height=120,surface='color.surface.panel',border='color.border.default'})
        forecastCards[i]=card
        parts[1]:SetParent(card); parts[1]:ClearAllPoints(); parts[1]:SetPoint('TOPLEFT',12,-14)
        parts[2]:SetParent(card); parts[2]:ClearAllPoints(); parts[2]:SetPoint('TOPLEFT',12,-52)
    end
    local segmentControls={}
    for _,definition in ipairs({{card=forecastCards[1],field='value',kind='introKind',voice=intro},
        {card=forecastCards[3],field='ending',kind='endingKind',voice=ending}}) do
        local part=definition
        part.source=Form:CreateDropdown(part.card,{height=32,width=200,options=function()
            return {{text=T('none'),value='none'},{text=T('voiceEntry'),value='voice'},{text=T('system'),value='system'},{text=T('lsm'),value='lsm'}}
        end,
            set=function(kind)
                if not dialog.edit or dialog.refreshing then return end
                local selected=dialog.edit.rule.sound
                if (selected[part.kind] or 'voice')==kind then return end
                sound:StopPreview(); selected[part.kind]=kind; selected[part.field]=''
                if part.field=='value' then selected.introDuration=nil end
                dialog:RefreshSound()
            end})
        part.source:SetPoint('TOPLEFT',12,-42)
        part.effect=Form:CreateDropdown(part.card,{height=34,width=200,searchable=true,
            searchPlaceholder=T('soundSearch'),searchEmptyText=T('empty'),options=function()
                local kind=dialog.edit and dialog.edit.rule.sound[part.kind] or 'voice'
                return kind~='voice' and EffectOptions(kind) or {}
            end,set=function(reference)
                if not dialog.edit or dialog.refreshing then return end
                local kind,key=reference:match('^([^:]+):(.+)$')
                local selected=dialog.edit.rule.sound
                if kind~=selected[part.kind] or not key then return end
                if key~=selected[part.field] then
                    sound:StopPreview(); selected[part.field]=key
                    if part.field=='value' then selected.introDuration=nil end
                end
                dialog:RefreshSound()
            end})
        part.effect:SetPoint('TOPLEFT',12,-84)
        part.voice:ClearAllPoints(); part.voice:SetPoint('TOPLEFT',12,-84)
        segmentControls[#segmentControls+1]=part
    end
    local introDurationLabel=Label(forecastCards[1],'forecastDuration',132)
    introDurationLabel:ClearAllPoints(); introDurationLabel:SetPoint('TOPLEFT',12,-132)
    local introDuration=Form:CreateEditBox(forecastCards[1],{width=180,height=32,onChange=function(_,text)
        if not dialog.edit or dialog.refreshing then return end
        local selected=dialog.edit.rule.sound
        local _,locked=sound.EditorModel:ForecastIntroDuration(selected)
        if locked then return end
        selected.introDuration=text~='' and (tonumber(text) or 0) or nil
    end})
    introDuration:SetPoint('TOPLEFT',12,-156)
    local previewIntro=Button(forecastCards[1],'previewIntro',function()
        if not dialog.edit then return end
        local selected=dialog.edit.rule.sound
        sound:StopPreview()
        local ok,why=sound:Submit(sound.Runtime.previewOwner,'preview',
            {kind=selected.introKind or 'voice',value=selected.value},true)
        errorLabel:SetText(ok and '' or Center:ErrorText(why))
    end,180)
    previewIntro:SetPoint('TOPLEFT',12,-200); previewIntro:SetHeight(34)
    local previewEnding=Button(forecastCards[3],'preview',function()
        if not dialog.edit then return end
        sound:StopPreview()
        local ok,why=sound:PreviewEventWindow(dialog.edit.rule.sound,true)
        errorLabel:SetText(ok and '' or Center:ErrorText(why))
    end,180)
    previewEnding:SetPoint('TOPLEFT',12,-126);previewEnding:SetHeight(34)
    local timeline=Label(soundBody,'forecastWhen',224); timeline:SetWordWrap(true)
    local preview=Button(soundBody,'preview',function()
        local normalized,why=sound.RuleModel:Normalize(dialog.edit.rule)
        local ok
        if normalized then ok,why=sound.EditorModel:Preview(normalized) end
        errorLabel:SetText(ok and '' or (why=='invalid-forecast-duration' and Center:ErrorText(why)
            or T((not dialog.edit.rule.sound.value or dialog.edit.rule.sound.value=='') and 'previewChoose' or 'previewFailed')))
    end,100)
    preview:SetPoint('TOPLEFT',0,-258)
    local stop=Button(soundBody,'stop',function() sound:StopPreview() end,80); stop:SetPoint('LEFT',preview,'RIGHT',10,0)

    function dialog:RefreshObjects()
        self:RefreshStepDetails()
        if not self.edit then return end
        local selected=self.edit.rule
        self.pickerSpec=self.pickerSpec or Settings:GetCurrentSpecSelectionKey() or 'all'
        inputID:SetShown(self.kind~='item'); browseLabel:SetShown(self.kind~='item'); pickerSpec:SetShown(self.kind~='item')
        pickerSpec:SetValue(self.pickerSpec,true)
        search:ClearAllPoints(); if self.kind=='item' then search:SetPoint('TOPLEFT',0,-50) else search:SetPoint('LEFT',pickerSpec,'RIGHT',8,0) end
        search:SetPoint('TOPRIGHT',picker,'TOPRIGHT',-18,-50); search:SetHeight(30)
        local key=self.pickerSpec
        local spec=tonumber(key:match(':(%d+)$'))
        local category=self.kind=='item' and 'general' or (key=='all' or key=='general' or key=='racial') and key or 'class'
        local filterKey=category..':'..tostring(spec)..':'..self.kind..':'..(self.query or '')
        local scrollOffset=self.objectFilterKey==filterKey and grid.GetVerticalScroll and grid:GetVerticalScroll() or 0
        self.objectFilterKey=filterKey
        local choices=sound.EditorModel:Objects(category,self.kind~='item' and spec or nil,self.query,self.kind)
        self.objectChoices=choices
        if self.autoSelect then
            self.autoSelect=nil
            if choices[1] then Choose(choices[1]) else self.edit.rule.object={kind=self.kind,id=0,unit='player'} end
            selected=self.edit.rule
        end
        nextButton:SetDisabled(self.step==1 and sound.EditorModel:PickerKind(selected.object,selected.trigger.extension)~=self.kind or selected.object.id==0)
        self.columns=CardColumns()
        grid.child:SetWidth(grid:GetWidth())
        empty:SetText(T(self.kind=='item' and 'noItems' or 'noObjects')); empty:SetShown(#choices==0)
        local displaySpec=DisplaySpec(self)
        local name,icon=sound.EditorModel:ObjectInfo(selected.object,selected.trigger.extension,displaySpec)
        pickerSummary.tooltipTarget.entry={name=name,object=selected.object,extension=selected.trigger.extension,spec=displaySpec}
        pickerSummary.iconSlot:SetIcon(icon); pickerSummary.label:SetText(Center:ObjectTitle(name,selected.object,selected.trigger.extension)); pickerSummary.label:SetWidth((picker:GetWidth()-18-24)/2-76)
        pickerSummary.label:SetWordWrap(true); pickerSummary.label:SetHeight(math.max(18,pickerSummary.label:GetStringHeight()))
        local details=sound.EditorModel:ObjectDetails(selected.object,selected.trigger.extension,displaySpec)
        pickerSummary.detail:SetWidth((picker:GetWidth()-18-24)/2-76)
        pickerSummary.detail:ClearAllPoints(); pickerSummary.detail:SetPoint('TOPLEFT',pickerSummary.label,'BOTTOMLEFT',0,-4)
        pickerSummary.detail:SetWordWrap(not details:match('^ID '))
        details=details:gsub('^ID (.+)$','|cffff4040ID|r |cffffd100%1|r')
        pickerSummary.detail:SetText(details)
        pickerSummary.talentTooltip.entry={name=sound.EditorModel:ObjectInfo({kind='spell',id=449619}),object={kind='spell',id=449619}}
        pickerSummary.talentTooltip:SetWidth(math.min(pickerSummary.detail:GetWidth(),pickerSummary.detail:GetStringWidth()))
        pickerSummary.talentTooltip:SetShown(selected.trigger.extension=='arcane-soul')
        pickerSummary.talentIcon:SetShown(selected.trigger.extension=='arcane-soul')
        pickerSummary.talentName:SetShown(selected.trigger.extension=='arcane-soul')
        if selected.trigger.extension=='arcane-soul' then
            local prefix,suffix=T('forecastLoad'):match('^(.-)%%s(.-)$')
            local name=YUI.API.Spell.GetName(449619) or '#449619'
            prefix=(prefix or ''):gsub('<$','|cffffd100<|r')
            pickerSummary.detail:SetText(prefix)
            local x=pickerSummary.detail:GetStringWidth()+3
            local icon=pickerSummary.talentIcon
            icon:SetTexture(YUI.API.Spell.GetTexture(449619) or 134400)
            icon:ClearAllPoints();icon:SetPoint('LEFT',pickerSummary.detail,'LEFT',x,0)
            pickerSummary.talentName:ClearAllPoints();pickerSummary.talentName:SetPoint('LEFT',icon,'RIGHT',4,0)
            local ending=(suffix or ''):gsub('^>','>|r')
            pickerSummary.talentName:SetText('|cffffd100'..name..ending)
            pickerSummary.talentTooltip:ClearAllPoints();pickerSummary.talentTooltip:SetPoint('LEFT',icon,'LEFT')
            pickerSummary.talentTooltip:SetWidth(20+pickerSummary.talentName:GetStringWidth())
        else
            pickerSummary.talentTooltip:ClearAllPoints();pickerSummary.talentTooltip:SetPoint('TOPLEFT',pickerSummary.detail,'TOPLEFT')
        end
        local detailHeight=math.max(16,pickerSummary.detail:GetStringHeight())
        pickerSummary.detail:SetHeight(detailHeight)
        local half=(picker:GetWidth()-18-24)/2
        local summaryHeight=math.max(64,10+pickerSummary.label:GetHeight()+4+detailHeight+6)
        pickerSummary:SetSize(half,summaryHeight)
        -- Equal columns: title/label on the first line, detail/selector below.
        loadLabel:ClearAllPoints(); loadLabel:SetPoint('TOPLEFT',pickerSummary,'TOPRIGHT',34,-10)
        loadPicker:ClearAllPoints(); loadPicker:SetPoint('BOTTOMLEFT',pickerSummary,'BOTTOMRIGHT',34,10)
        loadPicker:SetSize(math.max(120,half-20-112-12),24)
        unrestricted:ClearAllPoints(); unrestricted:SetPoint('LEFT',loadPicker,'RIGHT',12,0)
        unrestricted:SetSize(112,24)
        lockedHint:ClearAllPoints();lockedHint:SetPoint('TOPLEFT',loadPicker,'TOPLEFT');lockedHint:SetPoint('BOTTOMRIGHT',unrestricted,'BOTTOMRIGHT')
        summaryLine:ClearAllPoints(); summaryLine:SetPoint('BOTTOMLEFT',pickerSummary,'TOPLEFT',0,8)
        summaryLine:SetPoint('BOTTOMRIGHT',picker,'BOTTOMRIGHT',-18,summaryHeight+8)
        grid:ClearAllPoints(); grid:SetPoint('TOPLEFT',0,-90)
        grid:SetSize(picker:GetWidth()-18,math.max(cardPitch,picker:GetHeight()-pickerSummary:GetHeight()-16-90))
        self.objectCells={}
        for i,entry in ipairs(choices) do
            self.objectCells[i]={entry=entry,column=(i-1)%self.columns,y=math.floor((i-1)/self.columns)*cardPitch}
        end
        local y=math.ceil(#choices/self.columns)*cardPitch
        self.paintedChoices=nil
        GUI:FitScrollContent(grid,math.max(1,y))
        grid:SetVerticalScroll(math.max(0,math.min(scrollOffset,grid.child:GetHeight()-grid:GetHeight())))
        self:PaintObjectRows()
    end
    function dialog:PaintObjectRows()
        if not self.edit then return end
        local selected=self.edit.rule; local choices=self.objectChoices or {}
        self.columns=CardColumns()
        local capacity=math.min(#cards,self.columns*(math.ceil(grid:GetHeight()/cardPitch)+1))
        local width=(grid:GetWidth()-(self.columns-1)*8)/self.columns
        local scroll=grid.GetVerticalScroll and grid:GetVerticalScroll() or 0
        local cells=self.objectCells or {}
        self.offset=0
        for i,cell in ipairs(cells) do
            if cell.y+38>scroll then self.offset=i-1;break end
            self.offset=i
        end
        if self.paintedChoices==choices and self.paintedOffset==self.offset and self.paintedWidth==width and self.paintedHeight==grid:GetHeight() then return end
        self.paintedChoices,self.paintedOffset,self.paintedWidth=choices,self.offset,width
        self.paintedHeight=grid:GetHeight()
        for i,card in ipairs(cards) do
            local cell=i<=capacity and cells[self.offset+i] or nil
            local entry=cell and cell.entry or nil; card.entry=entry
            if entry then
                card:SetWidth(width); card:ClearAllPoints(); card:SetPoint('TOPLEFT',cell.column*(width+8),-cell.y)
                card.label:SetText(entry.extension and entry.name:gsub('%s*·%s*','\n') or entry.name); card.label:SetWidth(width-52); card.icon:SetTexture(entry.icon)
                local preset = entry.extension or entry.object.kind=='itemGroup' or entry.object.kind=='spellGroup'
                card.badge:SetText(preset and T('presetTag') or entry.pvp and 'PvP' or ''); card.badge:SetWidth(32); card.badge:SetShown(card.badge:GetText()~='')
                card.icon:ClearAllPoints()
                card.icon:SetPoint('LEFT',4,0)
                card:SetSelected(entry.object.kind==selected.object.kind and entry.object.id==selected.object.id
                    and entry.extension==selected.trigger.extension); card:Show()
            else card:Hide() end
        end
    end
    function dialog:RefreshTrigger()
        self:RefreshStepDetails()
        self.refreshing=true
        local rule=self.edit.rule; local trigger=rule.trigger
        event:Layout(self:GetWidth()-70); event:RefreshOptions(); event:SetValue(trigger.event=='cast' and 'castAfter' or trigger.event,true); event:SetDisabled(trigger.extension~=nil)
        local y=130+event:GetHeight()
        thresholdLabel:ClearAllPoints(); thresholdLabel:SetPoint('TOPLEFT',0,-y-8)
        threshold:ClearAllPoints(); threshold:SetPoint('TOPLEFT',180,-y)
        local unitLabelY=y+((trigger.value~=nil or trigger.event=='cast' or trigger.event=='auraRemoved') and 52 or 0)
        unit:ClearAllPoints(); unit:SetPoint('TOPLEFT',180,-unitLabelY)
        unitLabel:ClearAllPoints(); unitLabel:SetPoint('TOPLEFT',0,-unitLabelY-8)
        loadText:ClearAllPoints(); loadText:SetPoint('TOPLEFT',0,-unitLabelY-52)
        local castDelay=trigger.event=='cast' or trigger.event=='castAfter'
        local lossDelay=trigger.event=='auraRemoved'
        local hasThreshold=(lossDelay or castDelay or trigger.event=='auraRemaining' or trigger.event=='timerRemaining' or trigger.event=='auraStacks') and not trigger.extension
        thresholdLabel:SetText(T(lossDelay and 'lossDelayMs' or trigger.extension=='bone-shield' and 'boneShieldThreshold' or castDelay and 'delaySeconds' or trigger.event=='auraStacks' and 'stackCount' or 'remainingSeconds'))
        thresholdNote:ClearAllPoints(); thresholdNote:SetPoint('LEFT',threshold,'RIGHT',12,0); thresholdNote:SetShown(hasThreshold and (castDelay or lossDelay) and not trigger.extension)
        thresholdNote:SetText(T(lossDelay and 'lossDelayHint' or 'zeroImmediate'))
        thresholdLabel:SetShown(hasThreshold); threshold:SetShown(hasThreshold); threshold:SetValue(lossDelay and (trigger.lossDelay or 0) or trigger.value or trigger.event=='cast' and 0 or '',true)
        operator:SetShown(trigger.event=='auraStacks'); operator:SetValue(trigger.operator or 'ge',true)
        -- CDM resolves the aura unit; casts and cooldowns belong to the player.
        rule.object.unit=rule.object.kind=='aura' and 'cdm' or 'player'
        unit:Hide(); unitLabel:Hide()
        unitLabel:SetText(T((trigger.event=='cast' or trigger.event=='castAfter') and 'castUnit' or 'unit'))
        unrestricted:SetValue(not rule.specs and not rule.exceptSpecs,true); unrestricted:SetDisabled(trigger.extension~=nil or sound.EditorModel:IsRacial(rule.object))
        local nativeAura = rule.object.kind=='aura'
            and (trigger.event=='auraAdded' or trigger.event=='auraRemoved') and YUI.IsRetail
        for key in pairs(loadSelection) do loadSelection[key]=nil end
        local chosen={}; for _,key in ipairs(rule.specs or {}) do chosen[key]=true end
        local excluded={}; for _,key in ipairs(rule.exceptSpecs or {}) do excluded[key]=true end
        local names={}
        for _,group in ipairs(Settings:GetSpecSelectionGroups({})) do
            for _,entry in ipairs(group.specs or {}) do
                local key=entry.classInfo.token..':'..entry.specID
                local checked=chosen[key] or rule.exceptSpecs and not excluded[key]
                loadSelection[key]=checked and true or false
                if checked then names[#names+1]=entry.displayName end
            end
        end
        loadPicker:Refresh()
        loadPicker:SetDisabled(trigger.extension~=nil or sound.EditorModel:IsRacial(rule.object) or rule.specs==nil and rule.exceptSpecs==nil)
        lockedHint:SetShown(trigger.extension~=nil)
        loadText:SetText(T(trigger.event=='charge' and 'chargeDescription' or 'forecastLoad'))
        if trigger.event=='charge' then
            local charges=sound.EditorModel:HasCharges(rule.object,DisplaySpec(dialog))
            if charges==nil then loadText:SetText(T('chargeCapabilityUnknown')) end
            if charges==true then loadText:SetText(T('chargeDescription')..' '..T('nativeChargeRequirement')) end
        end
        if trigger.extension then loadText:SetText(sound.EditorModel:ObjectDetails(self.edit.rule.object,trigger.extension)) end
        if sound.EditorModel:PotionBuff(rule.object) then loadText:SetText(T('potionTiming')) end
        if rule.object.kind=='totem' then loadText:SetText(T('totemRequirement')) end
        loadText:SetShown(rule.object.kind=='totem' or trigger.extension~=nil or trigger.event=='charge' or sound.EditorModel:PotionBuff(rule.object)~=nil)
        local timer=trigger.duration~=nil and not sound.EditorModel:PotionBuff(rule.object)
        durationLabel:SetShown(timer); duration:SetShown(timer); duration:SetValue(trigger.duration or '',true)
        policyLabel:SetShown(timer); policy:SetShown(timer); policy:SetValue(trigger.policy or 'ignore',true)
        durationLabel:ClearAllPoints(); durationLabel:SetPoint('TOPLEFT',0,-unitLabelY-112)
        duration:ClearAllPoints(); duration:SetPoint('TOPLEFT',180,-unitLabelY-108)
        policyLabel:ClearAllPoints(); policyLabel:SetPoint('TOPLEFT',0,-unitLabelY-164)
        policy:ClearAllPoints(); policy:SetPoint('TOPLEFT',180,-unitLabelY-160)
        GUI:FitScrollContent(triggerScroll,unitLabelY+(timer and 212 or (nativeAura or trigger.extension or trigger.event=='charge') and 100 or 48))
        self.refreshing=nil
    end
    function dialog:RefreshSound()
        self:RefreshStepDetails()
        self.refreshing=true
        local value=self.edit.rule.sound; local bone=value.kind=='boneShield'; local window=value.kind=='eventWindow' or bone; local forecast=value.kind=='forecast' or window
        mode:Layout(soundBody:GetWidth()-88); playTitle:SetShown(not forecast)
        mode:SetShown(not forecast); if not forecast then mode:SetValue(value.kind,true) end
        chooseVoice:SetShown(value.kind=='voice'); chooseVoice:SetText(value.kind=='voice' and value.value~='' and sound:GetEntryLabel(value.value) or T('chooseVoice'))
        local typed=value.kind=='tts' or value.kind=='custom'
        soundText:SetShown(typed); inputLabel:SetShown(not forecast)
        effect:SetShown(value.kind=='system' or value.kind=='lsm')
        if value.kind=='system' or value.kind=='lsm' then effect:RefreshOptions(); effect:SetValue(value.kind..':'..value.value,true) end
        soundText:SetValue(value.value or '',true)
        for _,control in ipairs({introLabel,intro,countLabel,countdown,endingLabel,ending}) do control:SetShown(forecast) end
        for _,card in ipairs(forecastCards) do card:SetShown(forecast) end
        previewEnding:SetShown(window and value.endingKind~='none')
        preview:SetShown(not window);stop:SetShown(not window)
        if forecast then
            countdown:SetShown(not window or bone); countLabel:SetText(T(bone and 'boneShieldThreshold' or window and 'boilingPointDuration' or 'countdown'))
            countdown:RefreshOptions(); countdown:SetValue(bone and self.edit.rule.trigger.value or value.countdown or 3,true)
            introLabel:SetText(T(bone and 'boneShieldStacks' or window and 'windowStart' or 'intro')); endingLabel:SetText(T(bone and 'boneShieldTime' or window and 'windowEnd' or 'ending'))
            introDuration:SetShown(not window and value.introKind~='none'); introDurationLabel:SetShown(not window and value.introKind~='none')
            previewIntro:SetShown(value.introKind~='none');previewIntro:SetText(T(window and 'preview' or 'previewIntro'))
            for _,part in ipairs(segmentControls) do
                local kind=value[part.kind] or 'voice'
                part.source:RefreshOptions(); part.source:SetValue(kind,true)
                part.voice:SetShown(kind=='voice'); part.effect:SetShown(kind=='system' or kind=='lsm')
                part.voice:SetText(value[part.field]~='' and sound:GetEntryLabel(value[part.field]) or T('chooseVoice'))
                if kind=='system' or kind=='lsm' then part.effect:RefreshOptions(); part.effect:SetValue(kind..':'..(value[part.field] or ''),true) end
            end
            local durationValue,locked
            if not window then durationValue,locked=sound.EditorModel:ForecastIntroDuration(value) end
            introDuration:SetValue(durationValue and tostring(durationValue) or '',true)
            introDuration:SetDisabled(locked)
        end
        for _,entry in ipairs({{chooseVoice,value.value},{intro,value.value},{ending,value.ending}}) do
            if entry[1].icon then
                local icon=sound:GetEntryIcon(entry[2])
                if not icon or sound:GetIconText(icon) then icon=GUI:GetSettingsIcon('sound') end
                entry[1].icon:SetTexture(icon)
                if type(icon)=='number' then entry[1].icon:SetTexCoord(.08,.92,.08,.92)
                else entry[1].icon:SetTexCoord(0,1,0,1) end
            end
        end
        timeline:SetShown(forecast); timeline:SetWidth(self:GetWidth()-70)
        if forecast then
            if window then timeline:SetText(sound.EditorModel:SoundLabel(value))
            else
                local digits={}; for n=value.countdown,1,-1 do digits[#digits+1]=n end
                timeline:SetText(sound.EditorModel:ForecastPartLabel(value)..' → '..table.concat(digits,' · ')..' → '..sound.EditorModel:ForecastPartLabel(value,true))
            end
        end
        preview:SetText(T(forecast and 'previewAll' or 'preview'))
        playTitle:ClearAllPoints();playTitle:SetPoint('TOPLEFT',0,-8)
        local controlsY=8+mode:GetHeight()
        local helpKey=value.kind=='tts' and 'helpTTS' or value.kind=='lsm' and 'helpLSM' or value.kind=='custom' and 'helpCustom'
        sourceHelp:SetShown(helpKey~=nil and helpKey~=false)
        sourceHelp:SetText(helpKey and T(helpKey) or '')
        sourceHelp:SetWidth(soundBody:GetWidth()-88)
        sourceHelp:ClearAllPoints(); sourceHelp:SetPoint('TOPLEFT',88,-controlsY-46)
        chooseVoice:ClearAllPoints(); chooseVoice:SetPoint('TOPLEFT',88,-controlsY); chooseVoice:SetHeight(34)
        soundText:ClearAllPoints(); soundText:SetPoint('TOPLEFT',88,-controlsY); soundText:SetHeight(34)
        effect:ClearAllPoints(); effect:SetPoint('TOPLEFT',88,-controlsY); effect:SetHeight(34)
        inputLabel:ClearAllPoints(); inputLabel:SetPoint('TOPLEFT',0,-controlsY-8)
        local wide=self:GetWidth()>=800
        local available=self:GetWidth()-72
        local sideWidth=wide and (available-176)/2 or available
        local heights={256,120,window and 172 or 154}
        local offsets={0,268,400}
        for i,card in ipairs(forecastCards) do
            card:SetSize(wide and i==2 and 156 or sideWidth,heights[i]); card:ClearAllPoints()
            local x=i==1 and 0 or i==2 and sideWidth+10 or sideWidth+176
            card:SetPoint('TOPLEFT',wide and x or 0,wide and 0 or -offsets[i])
        end
        introLabel:SetWidth(sideWidth-24); endingLabel:SetWidth(sideWidth-24)
        countLabel:SetWidth(forecastCards[2]:GetWidth()-24); countLabel:SetWordWrap(true)
        countdown:ClearAllPoints(); countdown:SetPoint('TOPLEFT',12,-76)
        for _,part in ipairs(segmentControls) do
            part.source:SetWidth(sideWidth-24); part.effect:SetWidth(sideWidth-24)
            part.voice:SetWidth(sideWidth-24); part.voice:SetHeight(34)
        end
        introDuration:SetWidth(sideWidth-24); previewIntro:SetWidth(sideWidth-24);previewEnding:SetWidth(sideWidth-24)
        countdown:SetWidth(forecastCards[2]:GetWidth()-24); countdown:SetHeight(34)
        local flowY=wide and 276 or 574
        timeline:ClearAllPoints(); timeline:SetPoint('TOPLEFT',0,-flowY)
        local previewY=flowY+timeline:GetStringHeight()+12
        preview:ClearAllPoints(); preview:SetPoint('TOPLEFT',0,forecast and -previewY or -controlsY)
        GUI:FitScrollContent(soundScroll,forecast and previewY+44 or controlsY+50+(helpKey and sourceHelp:GetStringHeight()+12 or 0))
        if not forecast then
            local contentWidth=soundBody:GetWidth()-88-160
            chooseVoice:SetWidth(contentWidth); soundText:SetWidth(contentWidth); effect:SetWidth(contentWidth)
            preview:ClearAllPoints(); stop:ClearAllPoints(); stop:SetPoint('TOPRIGHT',0,-controlsY); stop:SetSize(64,34)
            preview:SetPoint('RIGHT',stop,'LEFT',-8,0); preview:SetSize(80,34)
        else
            preview:SetSize(120,40); stop:SetSize(80,40); stop:ClearAllPoints(); stop:SetPoint('LEFT',preview,'RIGHT',10,0)
        end
        self.refreshing=nil
    end
    function dialog:ShowScrim()
        local scrim=GUI:ShowModalScrim(self)
        if scrim then scrim:SetParent(self:GetParent()); scrim:ClearAllPoints(); scrim:SetAllPoints(self:GetParent()) end
    end
    function dialog:Refresh()
        if self.lastStep~=self.step then sound:StopPreview(); Settings:CloseSpecMultiSelectDropdown(self,'step-change'); self.lastStep=self.step end
        local parent=Center:GetModalParent()
        local width,height=parent:GetWidth()-28,parent:GetHeight()-28
        self:SetSize(width,height); errorLabel:SetWidth(math.max(100,width-370))
        loadText:SetWidth(width-70); loadText:SetWordWrap(true)
        self:SetFrameStrata(parent:GetFrameStrata()); self:SetFrameLevel(parent:GetFrameLevel()+20)
        title:SetText(T(self.edit.index and 'edit' or 'add'))
        stepper:SetWidth(width-36); stepper:SetStep(self.step,self.reached)
        for i,page in ipairs(pages) do page:SetSize(width-36,height-200); page:SetShown(i==self.step) end
        pages[1]:ClearAllPoints(); pages[1]:SetPoint('TOPLEFT',18,-120); pages[1]:SetPoint('BOTTOMRIGHT',-18,60); pages[1]:SetSize(width-36,height-180)
        picker:SetSize(width-36,height-180)
        local tabWidth=math.min((width-36)*2/3,math.max(240,width-250))
        kind:SetWidth(tabWidth)
        for i,tab in ipairs(kind.buttons) do
            tab:SetWidth(tabWidth/3); tab:ClearAllPoints(); tab:SetPoint('TOPLEFT',(i-1)*tabWidth/3,0)
        end
        grid:SetSize(width-54,math.max(78,height-386))
        triggerScroll:SetSize(width-54,height-200); soundScroll:SetSize(width-54,height-200)
        triggerBody:SetWidth(width-54); soundBody:SetWidth(width-54)
        loadPicker:SetWidth(math.min(260,math.max(160,width-340)))
        search:SetWidth(math.max(120,width-448)); soundText:SetWidth(width-72)
        chooseVoice:SetWidth(width-72); intro:SetWidth(width-72); ending:SetWidth(width-72); effect:SetWidth(width-72)
        previous:SetShown(self.step>1); previous:SetDisabled(self.step==1); nextButton:SetText(T(self.step==3 and 'save' or 'next'))
        self.kind=self.kind or (sound.EditorModel:PickerKind(self.edit.rule.object,self.edit.rule.trigger.extension))
        kind:SetValue(self.kind,true)
        local name,icon=sound.EditorModel:ObjectInfo(self.edit.rule.object,self.edit.rule.trigger.extension,DisplaySpec(self))
        for _,summary in ipairs({triggerSummary,soundSummary}) do
            summary.tooltipTarget.entry={name=name,object=self.edit.rule.object,extension=self.edit.rule.trigger.extension,spec=DisplaySpec(self)}
            summary.label:SetText(Center:ObjectTitle(name,self.edit.rule.object,self.edit.rule.trigger.extension)); summary.label:SetWidth(width-160); summary.detail:SetWidth(width-160); summary.icon:SetTexture(icon)
        end
        triggerSummary.detail:SetText(sound.EditorModel:PotionBuff(self.edit.rule.object) and sound.EditorModel:ObjectDetails(self.edit.rule.object) or (self.edit.rule.trigger.extension and sound.EditorModel:TriggerLabel(self.edit.rule) or T(self.edit.rule.object.kind)))
        soundSummary.detail:SetText(sound.EditorModel:PotionBuff(self.edit.rule.object) and sound.EditorModel:ObjectDetails(self.edit.rule.object)..' · '..sound.EditorModel:TriggerLabel(self.edit.rule,DisplaySpec(self)) or sound.EditorModel:TriggerLabel(self.edit.rule,DisplaySpec(self)))
        self:RefreshObjects(); self:RefreshTrigger(); self:RefreshSound()
    end
    dialog:SetScript('OnHide',function()
        if YUI.Event then YUI.Event:OffOwner(dialog) end
        Center:CloseSpecDropdown(pickerSpec)
        search:ClearFocus(); custom:ClearFocus(); threshold:ClearFocus(); soundText:ClearFocus(); duration:ClearFocus()
        Settings:CloseSpecMultiSelectDropdown(dialog,'editor-close'); sound:StopPreview()
        if GUI.VoicePicker.dialog then GUI.VoicePicker.dialog:Hide() end
        idPanel:Hide(); dialog.edit=nil
    end)
    if parent.HookScript then
        parent:HookScript('OnSizeChanged',function()
            if dialog.edit and dialog:IsShown() then dialog:Refresh() end
        end)
    end
    if dialog.EnableKeyboard then
        dialog:EnableKeyboard(true)
        dialog:SetScript('OnKeyDown',function(owner,key)
            if owner.SetPropagateKeyboardInput then owner:SetPropagateKeyboardInput(key~='ESCAPE') end
            if key=='ESCAPE' then if idPanel:IsShown() then idPanel:Hide() else owner:Hide() end end
        end)
    end
    dialog:Refresh(); dialog:RegisterIconEvents(); dialog:Show(); dialog:ShowScrim()
    return dialog
end
