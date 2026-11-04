local YUI=_G.YUI
local GUI=YUI and YUI.GUI2
if not (GUI and GUI.Form) then return end
local Picker={}
local unpack=unpack or table.unpack
local dropdownIconCrop={0.08,0.92,0.08,0.92}
local cardHeight,rowStep,gridTop=52,60,140
local minCardWidth,rowHeightBudget=160,68
Picker.parents=setmetatable({}, {__mode='k'})
GUI.VoicePicker=Picker
local function T(key)
    return YUI.Locale:Get('Core')[key]
end
local function DefaultClass()
    local unit=YUI.API and YUI.API.Unit
    return unit and unit.GetClassToken and unit.GetClassToken('player') or 'all'
end
local function MatchesClass(entry,class)
    return class=='all' or class=='buffs' and entry.categories and entry.categories.buffs
        or class=='events' and entry.categories and entry.categories.events
        or class=='general' and entry.class==nil or entry.class==class
end
local function MatchesSpec(entry,class,spec)
    if class=='events' then return not spec or entry.eventGroup==spec end
    return class=='buffs' or not spec or class=='special' and entry.packId==spec
        or class~='special' and (not entry.spec or entry.spec==spec)
end
function Picker:CategoryLabel(entry,classLabels,specLabels)
    if entry.class=='special' then
        return T('sound.voice_selector.special')..' · '..YUI.Sound:GetVoicePackLabel(entry.packId)
    end
    local label=entry.class and (classLabels[entry.class] or entry.class) or T('sound.voice_selector.general')
    if entry.spec and specLabels[entry.spec] then label=label..' · '..specLabels[entry.spec] end
    if entry.categories and entry.categories.buffs then
        label=T('sound.voice_selector.buffs')..(entry.class and ' · '..label or '')
    end
    if entry.categories and entry.categories.events then
        label=T('sound.voice_selector.events')..(entry.eventGroup and ' · '..T('sound.event.group.'..entry.eventGroup) or '')
    end
    return label
end

-- Shared by voice cards, picker badges and reminder sources.
function Picker:CreatePackIcon(parent,size)
    local compact=size<=22
    local slot=GUI:CreateIconSlot(parent,{size=size,variant='bare',shape='circle',border=compact and 'medium' or 'none',zoom=0,animate=false})
    if compact and slot.SetIconBorderColor then slot:SetIconBorderColor('color.text.secondary') end
    slot:EnableMouse(false)
    if compact then
        -- 不透明圆底遮住头像透明区域下方的技能图标，圆环和轻阴影各保留一层。
        slot.background=GUI:CreateIcon(slot,{icon=GUI:GetIconAppearancePreset('circle').mask,
            crop=false,fillParent=true,layer='BACKGROUND',subLevel=-7})
        local refreshTheme=slot.RefreshTheme
        function slot:RefreshTheme()
            refreshTheme(self)
            local r,g,b=GUI:GetColor('color.control.bg')
            self.background:SetVertexColor(r,g,b,1)
        end
        slot:RefreshTheme()
        local shadow=GUI:CreateShapeShadow(slot)
        local r,g,b,a=GUI:GetColor('color.overlay.shadow')
        GUI:ApplyShapeShadow(shadow,{enabled=true,shape='circle',color={r,g,b,(a or 1)*.2}},
            {anchor=slot,width=size,height=size,offsetY=-.5,allowLayout=true})
        slot.shadow=shadow and shadow.texture
        return slot
    end
    local silhouette=GUI:GetIconAppearancePreset('circle').mask
    slot.outline=GUI:CreateIcon(slot,{icon=silhouette,crop=false,layer='BACKGROUND',subLevel=1})
    slot.shadow=GUI:CreateIcon(slot,{icon=silhouette,crop=false,layer='BACKGROUND',subLevel=0})
    slot.outline:SetVertexColor(.04,.03,.02,.95);slot.shadow:SetVertexColor(0,0,0,.30)
    slot.outline:SetPoint('CENTER',slot,'CENTER',0,0);slot.shadow:SetPoint('CENTER',slot,'CENTER',0,-.5)
    slot.outline:SetSize(size+2,size+2);slot.shadow:SetSize(size+4,size+4)
    return slot
end

function Picker:SetRowIcon(row,icon)
    local text=YUI.Sound:GetIconText(icon)
    row.icon:SetShown(not text)
    row.textBackground:SetShown(text~=nil)
    row.iconText:SetShown(text~=nil)
    row.iconText:SetText(text or '')
    if text then
        row.iconText:ClearAllPoints()
        row.iconText:SetPoint('CENTER',row.textBackground,'CENTER',0,0)
        row.iconText:SetSize(28,28)
        row.iconText:SetJustifyH('CENTER')
        row.iconText:SetJustifyV('MIDDLE')
        local font=GUI:GetFont('font.family.body')
        local size=GUI:GetMetric('font.size.lg',18)
        row.iconText:SetFont(font,size,'OUTLINE')
        local width=row.iconText:GetStringWidth()
        if width>28 then row.iconText:SetFont(font,math.max(6,size*28/width),'OUTLINE') end
    else
        row.icon:SetTexture(icon or GUI:GetSettingsIcon('sound'))
        if type(icon)=='number' then row.icon:SetTexCoord(unpack(dropdownIconCrop))
        else row.icon:SetTexCoord(0,1,0,1) end
    end
end

local function CreateEntryIcon(row,parent)
    row.iconSlot=GUI:CreateIconSlot(parent,{size=32,variant='bare',shape='roundedSquare',border='none',zoom=0,animate=false})
    row.iconSlot:SetPoint('LEFT',6,0);row.iconSlot:EnableMouse(false)
    row.icon=row.iconSlot.icon
    row.textBackground=GUI:CreatePanel(parent,{width=32,height=32,
        surface='color.voice.textIcon',border=false,radiusKey='layout.radius.icon'})
    row.textBackground:SetPoint('LEFT',6,0)
    row.textBackground:EnableMouse(false); row.textBackground:Hide()
    row.iconText=GUI:CreateText(row.textBackground,'','font.size.lg','color.voice.textIconText','CENTER')
    row.iconText:SetPoint('CENTER',row.textBackground,'CENTER',0,0)
    row.iconText:SetSize(28,28); row.iconText:SetJustifyV('MIDDLE')
    row.iconText:SetWordWrap(false); row.iconText:Hide()
    row.packIcon=Picker:CreatePackIcon(row.iconSlot,22)
    -- Keep the badge above both the masked icon and its alternate text panel.
    row.packIcon:SetFrameLevel(math.max(row.iconSlot:GetFrameLevel(),row.textBackground:GetFrameLevel())+2)
    row.packIcon:SetPoint('BOTTOMRIGHT',row.iconSlot,'BOTTOMRIGHT',7,-6)
end

function Picker.Layout(width,height)
    width=math.max(1,width-28)
    height=math.max(1,height-28)
    local columns=math.max(1,math.min(5,math.floor((width-44)/(minCardWidth+10))))
    local footerHeight=width<520 and 132 or 88
    -- 保留原可见行数的高度预算，让较矮的卡片同时收紧窗口。
    local rows=math.max(1,math.min(10,math.floor((height-gridTop-footerHeight+8)/rowHeightBudget)))
    return {width=width,height=height,columns=columns,rows=rows,maxRows=rows,footerHeight=footerHeight,
        cardWidth=(width-54-(columns-1)*10)/columns}
end

function Picker:Open(parent,options)
    if not parent or not options or (not options.onSelect and not options.previewOnly) or not (YUI.Sound and YUI.Sound.GetEntries) then return nil end
    if self.dialog then self.dialog:Hide() end
    local layout=self.Layout(parent:GetWidth(),parent:GetHeight())
    if layout.width<320 or layout.height<300 then return nil,'parent-too-small' end
    if parent.HookScript and not self.parents[parent] then
        self.parents[parent]=true
        parent:HookScript('OnSizeChanged',function(frame)
            local dialog=Picker.dialog
            if dialog and dialog:IsShown() and dialog:GetParent()==frame then dialog:ResizeFromParent() end
        end)
    end
    if self.dialog then
        self.dialog:SetParent(parent)
        self.dialog:Reset(options,layout)
        return self.dialog
    end
    local dialog=GUI:CreatePanel(parent,{width=layout.width,height=layout.height,
        surface='color.surface.popup',border='color.popup.border',shadow=true})
    self.dialog=dialog
    dialog:SetPoint('CENTER',parent,'CENTER',0,0)
    dialog:SetFrameStrata(parent.GetFrameStrata and parent:GetFrameStrata() or 'DIALOG')
    dialog:SetFrameLevel(parent:GetFrameLevel()+30)
    dialog:EnableMouse(true)
    dialog.options=options
    dialog.selected=options.current
    dialog.class=options.class or DefaultClass()
    dialog.offset=0; dialog.query=''; dialog.rows={}; dialog.specOptions={}
    local function SelectionAvailable()
        if dialog.options and dialog.options.previewOnly then return false end
        if not dialog.selected then return false end
        if YUI.Sound.ParseSpecialVoice and YUI.Sound:ParseSpecialVoice(dialog.selected) then return dialog.options.entryType~='standard' end
        if dialog.options.entryType=='special' then return false end
        for _,entry in ipairs(dialog.baseRows or {}) do if entry.id==dialog.selected then return true end end
        return false
    end
    local title=GUI:CreateText(dialog,T('sound.voice_selector.title'),'font.size.lg','color.text.heading','LEFT')
    dialog.title=title
    title:SetPoint('TOPLEFT',18,-16)
    local close=GUI:CreateCloseButton(dialog,function() dialog:Hide() end)
    close:SetPoint('TOPRIGHT',-14,-12)
    local search=GUI.Form:CreateEditBox(dialog,{width=layout.width-36,height=44,text='',placeholder=T('sound.voice_selector.search'),searchPlaceholder=true,onChange=function(_,value)
        dialog.query=value or ''; dialog.offset=0; if dialog.Refresh then dialog:Refresh() end
    end})
    search:SetScript('OnEscapePressed',function() dialog:Hide() end)
    local classOptions={}
    local spec
    local class=GUI.Form:CreateDropdown(dialog,{width=(layout.width-46)/2,height=44,
        options=function() return classOptions end,get=function() return dialog.class end,set=function(value)
            dialog.class=value; dialog.spec=nil; dialog.offset=0
            if spec then spec:SetValue('all',true); spec:RefreshOptions() end
            if dialog.Refresh then dialog:Refresh() end
        end})
    class:SetPoint('TOPLEFT',18,-56)
    spec=GUI.Form:CreateDropdown(dialog,{width=(layout.width-46)/2,height=44,
        options=function() return dialog.class=='special' and dialog.packOptions or dialog.specOptions[dialog.class] or {{text=T('sound.voice_selector.all'),value='all'}} end,
        get=function() return dialog.spec or 'all' end,set=function(value)
            dialog.spec=value~='all' and value or nil; dialog.offset=0; if dialog.Refresh then dialog:Refresh() end
        end})
    spec:SetPoint('LEFT',class,'RIGHT',10,0)
    search:SetPoint('LEFT',spec,'RIGHT',10,0)
    local viewport=GUI:CreateScrollFrame(dialog,{width=layout.width-54,height=layout.rows*rowStep-8,autoHide=true})
    viewport:SetPoint('TOPLEFT',18,-gridTop)
    local empty=GUI:CreateText(viewport,T('sound.voice_selector.empty'),'font.size.md','color.text.secondary','CENTER')
    empty:SetPoint('CENTER'); empty:SetWidth(layout.width-60)
    local confirm=GUI.Form:CreateButton(dialog,{text=T('sound.voice_selector.confirm'),width=100,height=30,tone='accent',onClick=function()
        if SelectionAvailable() and dialog.options then
            local callback,selected=dialog.options.onSelect,dialog.selected
            dialog:Hide(); callback(selected)
        end
    end})
    GUI.Form:StyleDialogPrimary(confirm)
    confirm:SetPoint('BOTTOMRIGHT',-18,18)
    local cancel=GUI.Form:CreateTextLink(dialog,{text=T('sound.voice_selector.cancel'),width=90,height=34,colorKey='color.text.secondary',onClick=function() dialog:Hide() end})
    cancel:SetPoint('RIGHT',confirm,'LEFT',8*-1,0)
    local exit=GUI.Form:CreateButton(dialog,{text=T('sound.center.exit'),width=90,height=30,onClick=function() dialog:Hide() end})
    exit:SetPoint('BOTTOMRIGHT',-18,18)
    dialog.exitButton=exit;dialog.cancelButton=cancel;dialog.confirmButton=confirm
    local count=GUI:CreateText(dialog,'','font.size.md','color.text.secondary','LEFT')
    count:SetPoint('TOPLEFT',18,-112)
    local footer=GUI:CreateFrame(dialog,{width=layout.width-36,height=56})
    local divider=GUI:CreatePanel(dialog,{width=layout.width-36,height=1,surface='color.border.subtle',border=false})
    divider:EnableMouse(false)
    local selection={}
    dialog.selection=selection
    CreateEntryIcon(selection,footer)
    selection.label=GUI:CreateText(footer,'','font.size.md','color.text.primary','LEFT')
    selection.label:SetPoint('BOTTOMLEFT',footer,'LEFT',48,2);selection.label:SetHeight(28)
    selection.label:SetJustifyV('BOTTOM')
    selection.label:SetWordWrap(true);selection.label:SetNonSpaceWrap(true)
    local detail=GUI:CreateText(footer,'','font.size.sm','color.text.secondary','LEFT')
    detail:SetPoint('TOPLEFT',selection.label,'BOTTOMLEFT',0,-4)
    detail:SetHeight(18);detail:SetWordWrap(false);detail:SetJustifyV('TOP')
    selection.source=detail
    local function LayoutFooter()
        local stacked=layout.width<520
        footer:ClearAllPoints();footer:SetPoint('BOTTOMLEFT',18,layout.footerHeight-70)
        local width=math.max(1,layout.width-(stacked and 36 or 264))
        footer:SetWidth(width)
        selection.label:SetWidth(math.max(1,width-48));detail:SetWidth(math.max(1,width-48))
        divider:ClearAllPoints();divider:SetPoint('BOTTOMLEFT',18,layout.footerHeight-8)
        divider:SetWidth(layout.width-36)
        confirm:SetHeight(34);exit:SetHeight(34)
        confirm:ClearAllPoints();confirm:SetPoint('BOTTOMRIGHT',-18,stacked and 18 or 29)
        exit:ClearAllPoints();exit:SetPoint('BOTTOMRIGHT',-18,stacked and 18 or 29)
    end
    local capacity=layout.columns*layout.rows
    local function MaxOffset()
        return math.max(0,math.ceil(#dialog.choices/layout.columns)-layout.rows)*layout.columns
    end
    local function Wheel(_,delta)
        dialog.offset=math.max(0,math.min(MaxOffset(),dialog.offset-delta*layout.columns))
        viewport:SetVerticalScroll(math.floor(dialog.offset/layout.columns)*rowStep)
        dialog:RefreshRows()
    end
    if viewport.HookScript then viewport:HookScript('OnVerticalScroll',function()
        dialog.offset=math.min(MaxOffset(),math.max(0,math.floor(viewport:GetVerticalScroll()/rowStep))*layout.columns)
        dialog:RefreshRows()
    end) end
    viewport:EnableMouseWheel(true); viewport:SetScript('OnMouseWheel',Wheel)
    for i=1,55 do
        local card=GUI:CreateFrame(viewport.child,{width=layout.cardWidth,height=cardHeight})
        card:SetPoint('TOPLEFT',((i-1)%layout.columns)*(layout.cardWidth+10),-math.floor((dialog.offset+i-1)/layout.columns)*rowStep)
        local row={card=card}; dialog.rows[i]=row
        row.select=GUI.Form:CreateButton(card,{text='',width=layout.cardWidth,height=cardHeight,tone='default',onClick=function()
            if row.entry then
                if not dialog.options.previewOnly then dialog.selected=row.entry.id; dialog:RefreshRows() end
                if dialog.options.previewOnly then dialog.previewEntry=row.entry.id;dialog:RefreshSelection() end
                if dialog.options.preview then dialog.options.preview(row.entry.id,dialog) end
            end
        end})
        row.select:SetPoint('LEFT',0,0)
        CreateEntryIcon(row,row.select)
        row.select.gui2PreserveIconColor=true
        row.label=GUI:CreateText(row.select,'','font.size.md','color.text.primary','CENTER')
        row.label:SetPoint('LEFT',48,0); row.label:SetWidth(layout.cardWidth-54)
        row.label:SetHeight(40); row.label:SetJustifyH('CENTER'); row.label:SetJustifyV('MIDDLE'); row.label:SetWordWrap(true);row.label:SetNonSpaceWrap(true)
        row.source=GUI:CreateText(row.select,'','font.size.sm','color.text.secondary','LEFT')
        row.source:SetPoint('TOPLEFT',44,-29);row.source:SetHeight(16);row.source:SetWordWrap(false)
        row.source:Hide()
        row.select:HookScript('OnEnter',function(owner)
            if row.entry then GUI.Tooltip:Show(owner,{title=row.entry.name,content=function(tip)
                if dialog.searching then tip:AddLine(row.categoryLabel) end
                tip:AddLine(row.recordingSource)
            end}) end
        end)
        local function HideTooltip(owner) GUI.Tooltip:Hide(owner) end
        row.select:HookScript('OnLeave',HideTooltip);row.select:HookScript('OnHide',HideTooltip)
        row.select:EnableMouseWheel(true); row.select:SetScript('OnMouseWheel',Wheel)
    end
    function dialog:RefreshSelection()
        local value=self.options.previewOnly and self.previewEntry or self.selected
        local sound=YUI.Sound
        local entry
        for _,candidate in ipairs(self.baseRows or {}) do if candidate.id==value then entry=candidate;break end end
        local origin=sound.ParseSpecialVoice and sound:ParseSpecialVoice(value)
        local resource=value and sound:ResolveEntry(value,sound:GetPlaybackOptions(self.preferences))
        local source=origin or resource and resource.packId
        selection.label:SetText(entry and entry.name or value and sound:GetEntryLabel(value) or T('sound.voice_selector.title'))
        if value then
            Picker:SetRowIcon(selection,entry and entry.icon or sound:GetEntryIcon(value))
        else
            selection.icon:Hide();selection.textBackground:Hide();selection.iconText:Hide()
        end
        selection.packIcon:SetShown(value~=nil and origin==nil and source~=nil)
        if source then selection.packIcon:SetIcon(sound:GetVoicePackIcon(source)) end
        if origin then
            local label=sound:GetVoicePackLabel(origin)
            local state=not sound:IsVoicePackEnabled(origin,self.preferences) and 'sound.center.packInactive'
                or not resource and 'sound.center.packUnavailable'
            detail:SetText(label..(state and ' · '..T(state) or ''))
        elseif value then
            detail:SetText(resource and (source and sound:GetVoicePackLabel(source) or T('sound.center.tts')) or T('sound.center.packNoRecording'))
        else detail:SetText('') end
    end
    function dialog:RefreshRows()
        if self.paintedChoices==self.choices and self.paintedOffset==self.offset and self.paintedSelection==self.selected and self.paintedWidth==layout.width then return end
        self.paintedChoices,self.paintedOffset,self.paintedSelection,self.paintedWidth=self.choices,self.offset,self.selected,layout.width
        for i,row in ipairs(self.rows) do
            local entry=i<=capacity+layout.columns and self.choices[self.offset+i] or nil
            if row.entry~=entry then GUI.Tooltip:Hide(row.select) end
            row.entry=entry
            if entry then
                row.card:ClearAllPoints(); row.card:SetPoint('TOPLEFT',((i-1)%layout.columns)*(layout.cardWidth+10),-math.floor((self.offset+i-1)/layout.columns)*rowStep)
                row.card:Show(); row.label:SetText(entry.name)
                if GUI.SetTextColorKey then GUI:SetTextColorKey(row.label,'color.text.primary') end
                Picker:SetRowIcon(row,entry.icon)
                local source=entry.sourcePackId or entry.packId
                row.packIcon:SetShown(entry.class~='special' and source~=nil)
                if source then row.packIcon:SetIcon(YUI.Sound:GetVoicePackIcon(source)) end
                row.source:SetText(source and YUI.Sound:GetVoicePackLabel(source) or T(entry.sourceKind=='tts' and 'sound.center.tts' or 'sound.center.packNoRecording'))
                row.recordingSource=row.source:GetText()
                row.label:ClearAllPoints()
                if self.searching then
                    row.categoryLabel=Picker:CategoryLabel(entry,self.classLabels,self.specLabels)
                    row.label:SetPoint('TOPLEFT',48,-3); row.label:SetHeight(26)
                    row.source:ClearAllPoints();row.source:SetPoint('BOTTOMLEFT',48,4)
                    row.source:SetText(row.categoryLabel);row.source:SetJustifyH('CENTER')
                else
                    row.label:SetPoint('LEFT',48,0);row.label:SetHeight(40)
                end
                row.source:SetWidth(layout.cardWidth-54);row.source:SetShown(self.searching)
                row.select:SetSelected(not self.options.previewOnly and entry.id==self.selected)
            else row.card:Hide() end
        end
        if #self.choices==0 then empty:Show() else empty:Hide() end
        confirm:SetDisabled(not SelectionAvailable(),true)
        self:RefreshSelection()
        count:SetText(#self.choices==0 and '0' or (self.offset+1)..'–'..math.min(self.offset+capacity,#self.choices)..' / '..#self.choices)
    end
    function dialog:Refresh()
        self.choices={}
        local query=string.lower(self.query or ''):match('^%s*(.-)%s*$')
        self.searching=query~=''
        local buckets={{},{},{}}
        for _,entry in ipairs(self.baseRows or {}) do
            local classMatch=MatchesClass(entry,self.class)
            local specMatch=MatchesSpec(entry,self.class,self.spec)
            if self.searching then
                if string.find(string.lower(entry.name),query,1,true) then
                    local bucket=buckets[classMatch and (specMatch and 1 or 2) or 3]
                    bucket[#bucket+1]=entry
                end
            elseif classMatch and specMatch then self.choices[#self.choices+1]=entry end
        end
        if self.searching then for _,bucket in ipairs(buckets) do for _,entry in ipairs(bucket) do self.choices[#self.choices+1]=entry end end end
        -- Every filter shares the full catalog's height; only its scroll content changes.
        layout.rows=math.min(layout.maxRows,math.max(2,math.ceil(#(self.baseRows or {})/layout.columns)))
        layout.height=gridTop+layout.rows*rowStep-8+layout.footerHeight
        capacity=layout.columns*layout.rows
        self:SetHeight(layout.height);viewport:SetHeight(layout.rows*rowStep-8)
        LayoutFooter()
        self.offset=math.min(math.floor(self.offset/layout.columns)*layout.columns,MaxOffset())
        viewport.child:SetWidth(layout.width-54); GUI:FitScrollContent(viewport,math.max(1,math.ceil(#self.choices/layout.columns)*rowStep-8))
        viewport:SetVerticalScroll(math.floor(self.offset/layout.columns)*rowStep)
        self:RefreshRows()
    end
    function dialog:RefreshData()
        if not self.options then return end
        local sound=YUI.Sound
        local prefs=sound.GetPreferences and sound:GetPreferences()
        self.preferences=prefs
        local entries=self.options.entryType=='special' and {} or sound:GetEntries({})
        self.specialRows=self.options.entryType=='standard' and {} or sound:GetEnabledSpecialEntries(prefs)
        for _,entry in ipairs(self.specialRows) do entries[#entries+1]=entry end
        self.baseRows=sound.OrderVoiceEntries and sound:OrderVoiceEntries(entries,self.options.matchNames,nil,self.options.preferredID) or entries
        self.packOptions={{text=T('sound.voice_selector.all'),value='all'}}
        for _,id in ipairs(sound:GetEnabledVoicePacks(prefs)) do
            self.packOptions[#self.packOptions+1]={text=sound:GetVoicePackLabel(id),value=id}
        end
        if self.class=='special' and self.spec then
            local found=false
            for _,option in ipairs(self.packOptions) do if option.value==self.spec then found=true;break end end
            if not found then self.spec=nil;spec:SetValue('all',true) end
        end
        local counted={}
        for _,choice in ipairs(self.classChoices or {}) do
            local row={}; for key,value in pairs(choice) do row[key]=value end
            local n=0
            for _,entry in ipairs(entries) do
                if choice.value=='all' or choice.value=='buffs' and entry.categories and entry.categories.buffs
                    or choice.value=='events' and entry.categories and entry.categories.events
                    or choice.value=='general' and entry.class==nil or choice.value==entry.class then n=n+1 end
            end
            row.text=string.format(T('sound.center.categoryCount') or '%s (%d)',choice.text,n)
            counted[#counted+1]=row
        end
        if self.options.entryType~='standard' then table.insert(counted,math.min(2,#counted+1),{
            text=string.format(T('sound.center.categoryCount') or '%s (%d)',T('sound.voice_selector.special'),#self.specialRows),
            value='special',icon=GUI:GetSettingsIcon('sound'),iconSize=18,texCoord={0,1,0,1}}) end
        classOptions=counted
        class:RefreshOptions()
        class:SetDisabled(self.options.entryType=='special',true)
        spec:RefreshOptions()
        self:RefreshTitle(); self:Refresh()
    end
    function dialog:ResizeFromParent()
        local parent=self:GetParent()
        local nextLayout=Picker.Layout(parent:GetWidth(),parent:GetHeight())
        if nextLayout.width<320 or nextLayout.height<300 then self:Hide(); return end
        layout=nextLayout; capacity=layout.columns*layout.rows
        self:SetSize(layout.width,layout.height)
        search:SetWidth((layout.width-56)*0.5); class:SetWidth((layout.width-56)*0.25); spec:SetWidth((layout.width-56)*0.25)
        viewport:SetSize(layout.width-54,layout.rows*rowStep-8); empty:SetWidth(layout.width-60)
        for i,row in ipairs(self.rows) do
            row.card:SetSize(layout.cardWidth,cardHeight); row.card:ClearAllPoints()
            row.card:SetPoint('TOPLEFT',((i-1)%layout.columns)*(layout.cardWidth+10),-math.floor((dialog.offset+i-1)/layout.columns)*rowStep)
            row.select:SetWidth(layout.cardWidth); row.label:SetWidth(layout.cardWidth-54)
        end
        self:Refresh()
    end
    function dialog:RefreshSpecIcons()
        local icons=YUI.API and YUI.API.Icons
        for _,list in pairs(self.specOptions) do
            for _,choice in ipairs(list) do
                if type(choice.value)=='number' then
                    choice.iconData=icons and icons.GetScopedSpecIcon and icons.GetScopedSpecIcon(choice.value,choice.icon,'settings') or nil
                    if choice.iconData and choice.iconData.custom==false then choice.icon=choice.iconData.texture or choice.icon;choice.iconData=nil end
                    choice.texCoord=not choice.iconData and dropdownIconCrop or nil
                end
            end
        end
        spec:RefreshOptions()
    end
    function dialog:OnIconScopeChanged(_,scope)
        if not scope or scope=='settings' then self:RefreshSpecIcons() end
    end
    function dialog:RefreshTitle()
        local heading=T(self.options.previewOnly and 'sound.center.browsePreview' or self.options.entryType=='standard' and 'sound.center.chooseStandardVoice' or self.options.entryType=='special' and 'sound.center.chooseSpecialVoice' or 'sound.voice_selector.title')
        title:SetText(heading)
        title:SetWidth(layout.width-80)
        title:SetWordWrap(false)
    end
    function dialog:Reset(nextOptions,nextLayout)
        self.options=nextOptions; layout=nextLayout
        confirm:SetShown(not nextOptions.previewOnly)
        exit:SetShown(nextOptions.previewOnly==true)
        cancel:SetShown(not nextOptions.previewOnly)
        self:RefreshTitle()
        cancel:ClearAllPoints()
        cancel:SetPoint('RIGHT',confirm,'LEFT',-10,0)
        self.selected=not nextOptions.previewOnly and nextOptions.current or nil;self.previewEntry=nil; self.query=''; self.offset=0; self.spec=nil
        self.class=nextOptions.class or DefaultClass(); self.specOptions={}
        self.classLabels={};self.specLabels={}
        classOptions={{text=T('sound.voice_selector.all'),value='all'},
            {text=T('sound.voice_selector.general'),value='general',icon=132996,texCoord=dropdownIconCrop},
            {text=T('sound.voice_selector.buffs'),value='buffs',icon=135939,texCoord=dropdownIconCrop},
            {text=T('sound.voice_selector.events'),value='events',icon=133471,texCoord=dropdownIconCrop}}
        self.specOptions.events={{text=T('sound.voice_selector.all'),value='all'}}
        for _,group in ipairs({'daily','group','combat','explore'}) do
            self.specOptions.events[#self.specOptions.events+1]={text=T('sound.event.group.'..group),value=group}
        end
        local settings=YUI.Settings
        for _,group in ipairs(settings and settings.GetSpecSelectionGroups and settings:GetSpecSelectionGroups({}) or {}) do
            for _,info in ipairs(group.classes) do
                self.classLabels[info.token]=info.name
                classOptions[#classOptions+1]={text=info.name,value=info.token,icon=info.icon,texCoord=info.iconTexCoord}
                self.specOptions[info.token]={{text=T('sound.voice_selector.all'),value='all'}}
            end
            for _,info in ipairs(group.specs) do
                self.specLabels[info.specID]=info.displayName
                local list=self.specOptions[info.classInfo.token]
                list[#list+1]={text=info.displayName,value=info.specID,icon=info.icon}
            end
        end
        if nextOptions.classes then classOptions=nextOptions.classes end
        if nextOptions.entryType=='special' then classOptions={};self.class='special'
        elseif nextOptions.entryType=='standard' and self.class=='special' then self.class=DefaultClass() end
        self.classChoices=classOptions
        local found=false
        for _,choice in ipairs(classOptions) do if choice.value==self.class then found=true end end
        if not found and nextOptions.entryType~='special' then self.class='all' end
        capacity=layout.columns*layout.rows
        self:SetSize(layout.width,layout.height)
        self:ClearAllPoints(); self:SetPoint('CENTER',self:GetParent(),'CENTER',0,0)
        self:SetFrameLevel(self:GetParent():GetFrameLevel()+30)
        self:SetFrameStrata(self:GetParent().GetFrameStrata and self:GetParent():GetFrameStrata() or 'DIALOG')
        search:SetWidth((layout.width-56)*0.5); search:SetText('')
        class:SetWidth((layout.width-56)*0.25); spec:SetWidth((layout.width-56)*0.25)
        class:SetValue(self.class,true); class:RefreshOptions(); spec:SetValue('all',true); self:RefreshSpecIcons()
        if YUI.Event and YUI.Event.On then
            YUI.Event:On('YUI_SOUND_PREFERENCES_CHANGED','RefreshData',self)
            YUI.Event:On('YUI_SOUND_PACKS_CHANGED','RefreshData',self)
            YUI.Event:On('YUI_SOUND_ENTRIES_CHANGED','RefreshData',self)
            YUI.Event:On('YUI_APPEARANCE_ICON_SET_CHANGED','RefreshSpecIcons',self)
            YUI.Event:On('YUI_APPEARANCE_ICON_SCOPE_CHANGED','OnIconScopeChanged',self)
        end
        viewport:SetSize(layout.width-54,layout.rows*rowStep-8); empty:SetWidth(layout.width-60)
        for i,row in ipairs(self.rows) do
            row.card:SetSize(layout.cardWidth,cardHeight); row.card:ClearAllPoints()
            row.card:SetPoint('TOPLEFT',((i-1)%layout.columns)*(layout.cardWidth+10),-math.floor((dialog.offset+i-1)/layout.columns)*rowStep)
            row.select:SetWidth(layout.cardWidth); row.label:SetWidth(layout.cardWidth-54)
        end
        self:RefreshData(); self:Show()
        local scrim=GUI:ShowModalScrim(self)
        if scrim then
            scrim:SetParent(self:GetParent()); scrim:ClearAllPoints(); scrim:SetAllPoints(self:GetParent())
        end
    end
    dialog:SetScript('OnHide',function()
        search:ClearFocus()
        if dialog.options and dialog.options.stopPreview then dialog.options.stopPreview(dialog) end
        if YUI.Event then YUI.Event:OffOwner(dialog) end
        dialog.options=nil
        dialog.baseRows=nil; dialog.specialRows=nil; dialog.classChoices=nil; dialog.choices={};dialog.preferences=nil;dialog.packOptions=nil
        dialog.classLabels=nil;dialog.specLabels=nil;dialog.searching=nil
        dialog.paintedChoices=nil;dialog.previewEntry=nil
        for _,row in ipairs(dialog.rows) do row.entry=nil;row.recordingSource=nil;row.categoryLabel=nil;GUI.Tooltip:Hide(row.select) end
    end)
    if dialog.EnableKeyboard then
        dialog:EnableKeyboard(true)
        dialog:SetScript('OnKeyDown',function(_,key)
            local handled=key=='ESCAPE' or key=='ENTER'
            if dialog.SetPropagateKeyboardInput then dialog:SetPropagateKeyboardInput(not handled) end
            if key=='ESCAPE' then dialog:Hide()
            elseif key=='ENTER' and SelectionAvailable() and dialog.options then
                local callback,selected=dialog.options.onSelect,dialog.selected
                dialog:Hide(); callback(selected)
            end
        end)
    end
    dialog:Reset(options,layout)
    return dialog
end

return Picker
