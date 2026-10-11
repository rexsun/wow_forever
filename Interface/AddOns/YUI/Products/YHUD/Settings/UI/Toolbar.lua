local YUI = _G.YUI
local HUD = YUI and YUI.YHUD
local UI = HUD and HUD.DesignerUI
if not UI then return end
local GUI, Settings, Designer = YUI.GUI2, YUI.Settings, HUD.Designer
local function T(key, ...) local text = HUD:T('designer.toolbar.' .. key); return select('#', ...) > 0 and string.format(text, ...) or text end
local function Text(parent, value, color)
    local text = GUI:CreateText(parent, value, 'font.size.md', color or 'color.text.primary', 'LEFT')
    text:SetWordWrap(false)
    return text
end
local function Tip(owner, value)
    if not value or value == '' then return end
    GameTooltip:SetOwner(owner, 'ANCHOR_RIGHT'); GameTooltip:SetText(value, 0.8, 0.8, 0.8, nil, true); GameTooltip:Show()
end
local function HideTip() GameTooltip:Hide() end

local function StyleToolbarAction(button, kind)
    local refresh = button.RefreshTheme
    function button:RefreshTheme()
        local r,g,b = GUI:GetColor('color.surface.popup')
        local unavailable = kind=='sound' and HUD.Client and HUD.Client.soundReminders == false
        local tint = unavailable and 'color.text.disabled'
            or kind=='sound' and 'color.state.warning' or 'color.state.success'
        local tr,tg,tb = GUI:GetColor(tint)
        if kind=='save' then
            local neutral=(tr+tg+tb)/3
            tr,tg,tb=tr*0.8+neutral*0.2,tg*0.8+neutral*0.2,tb*0.8+neutral*0.2
        end
        local filled = kind=='sound' or kind=='save'
        local strength = kind=='save' and 0.34 or 0.08
        local hr,hg,hb=GUI:GetColor('color.text.primary')
        local hover={r+(hr-r)*0.045,g+(hg-g)*0.045,b+(hb-b)*0.045,1}
        local function Fill(amount)
            return {r+(tr-r)*amount,g+(tg-g)*amount,b+(tb-b)*amount,1}
        end
        self.gui2SurfaceToken = filled and Fill(strength) or {0,0,0,0}
        self.gui2BorderToken = {0,0,0,0}
        self.gui2HoverSurfaceToken = filled and Fill(strength+0.08) or hover
        self.gui2HoverBorderToken = {0,0,0,0}
        self.gui2PressedSurfaceToken = filled and Fill(strength+0.04) or 'color.control.pressed'
        self.gui2PressedBorderToken = {0,0,0,0}
        self.gui2TextColorKey = unavailable and 'color.text.disabled'
            or kind=='sound' and 'color.state.warning' or 'color.text.primary'
        self.gui2HoverTextColorKey = self.gui2TextColorKey
        self.gui2PressedTextColorKey = self.gui2HoverTextColorKey
        refresh(self)
    end
    button:RefreshTheme()
end

function UI:GetToolbarSpecNames(keys)
    if not self.toolbarSpecNames then
        local names = {}
        for _, class in ipairs(HUD.ResourceCatalog:GetClasses() or {}) do
            for _, spec in ipairs(HUD.ResourceCatalog:GetSpecializations(class.classFile) or {}) do
                local key = class.classFile .. ':' .. tostring(spec.specID)
                local short = spec.name or key
                local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class.classFile]
                local colored = color and string.format('|cff%02x%02x%02x%s|r',math.floor(color.r*255),math.floor(color.g*255),math.floor(color.b*255),short) or short
                names[key] = {short = short, colored = colored, full = (class.name or class.className or class.classFile) .. ' · ' .. short}
            end
        end
        self.toolbarSpecNames = names
    end
    local short, full, colored = {}, {}, {}
    for _, key in ipairs(keys or {}) do
        local name = self.toolbarSpecNames[key] or {short=key, full=key}
        full[#full+1] = name.full
        if #short < 2 then short[#short+1] = name.short; colored[#colored+1] = name.colored or name.short end
    end
    local summary = table.concat(short, '、')
    if #(keys or {}) > 2 then summary = summary .. ' +' .. (#keys-2) end
    return summary, table.concat(full, '\n'), table.concat(colored, '、') .. (#(keys or {}) > 2 and ' +' .. (#keys-2) or '')
end

function UI:BuildToolbarSchemeRows()
    local rows, code = HUD.ConfigCatalog:List()
    if not rows then return nil, code end
    local result = {}
    for _, row in ipairs(rows) do
        local assignment = row.assignment or {}
        local scope, full, colored = self:GetToolbarSpecNames(assignment.specKeys)
        if assignment.mode == 'default' then scope, full, colored = T('default'), T('default_help'), nil
        elseif scope == '' then scope, full, colored = T('unassigned'), T('unassigned'), nil end
        local item = {id=row.set.id, name=row.set.name or row.set.id, scope=scope, scopeDisplay=colored or scope, full=full, active=row.active, assignment=assignment}
        if assignment.mode == 'default' then table.insert(result, 1, item) else result[#result+1] = item end
    end
    return result
end

function UI:HideSchemePicker()
    if self.schemePicker then self.schemePicker:Hide() end
end

local function EnsureSchemePickerRow(self, picker, index)
    local row = picker.pool[index]
    if not row then
        row = GUI.Form:CreateButton(picker.scroll.child, {width=360, height=34, text='', onClick=function(button)
            self:HideSchemePicker(); self:RequestSwitch(button.item.id)
        end})
        row.name = Text(row, ''); row.name:SetPoint('LEFT', 10, 0); row.name:SetWidth(140)
        row.gui2SurfaceToken='color.surface.popup'; row.gui2BorderToken='color.surface.popup'
        row.current = Text(row, T('current'), 'color.state.success'); row.current:SetPoint('LEFT', 154, 0); row.current:SetWidth(72)
        row.scope = Text(row, '', 'color.text.secondary'); row.scope:SetPoint('LEFT', 234, 0); row.scope:SetWidth(116)
        row:HookScript('OnEnter', function(button)
            if button.name:IsTruncated() then Tip(button, button.item.name) end
        end)
        row:HookScript('OnLeave', HideTip)
        row.scopeHit=GUI:CreateFrame(row,{mouse=true}); row.scopeHit:SetAllPoints(row.scope)
        row.scopeHit:SetScript('OnEnter',function(frame)
            if row.item.assignment.mode=='default' or #(row.item.assignment.specKeys or {})>2 or row.scope:IsTruncated() then Tip(frame,row.item.full) end
        end)
        row.scopeHit:SetScript('OnLeave',HideTip)
        row.scopeHit:SetScript('OnMouseUp',function(_,button)
            if button=='LeftButton' then self:HideSchemePicker(); self:RequestSwitch(row.item.id) end
        end)
        picker.pool[index] = row
    end
    return row
end

function UI:RefreshSchemePicker()
    local picker = self.schemePicker
    if not picker or not picker:IsShown() then return end
    picker.rows = self:BuildToolbarSchemeRows() or {}
    local session = Designer:GetSession()
    local selected = session and session.setId
    for index, item in ipairs(picker.rows) do
        local row = EnsureSchemePickerRow(self, picker, index)
        row.item = item
        row.name:SetText(item.name); row.scope:SetText(item.scopeDisplay); row.current:SetShown(item.active == true)
        row:SetSelected(item.id == selected)
        row:SetPoint('TOPLEFT', 0, -(index-1)*36); row:Show()
    end
    for index=#picker.rows+1,#picker.pool do picker.pool[index]:Hide() end
    picker.viewportHeight=math.max(36,math.min(8,#picker.rows)*36)
    picker:SetHeight(picker.viewportHeight+94)
    picker.scroll:SetHeight(picker.viewportHeight)
    GUI:FitScrollContent(picker.scroll,math.max(36, #picker.rows*36))
end

function UI:ToggleSchemePicker()
    if self.busyKind then return end
    if self.schemePicker and self.schemePicker:IsShown() then self:HideSchemePicker(); return end
    self:HideSpecializationPicker()
    HideTip()
    local picker = self.schemePicker
    if not picker then
        picker = GUI:CreatePanel(UIParent, {width=396,height=302,surface='color.surface.popup',border='color.popup.border',shadow=true})
        self.schemePicker = picker; picker.pool = {}
        picker:SetFrameStrata('FULLSCREEN_DIALOG'); picker:SetFrameLevel(660); picker:EnableMouse(true)
        Text(picker,T('name'),'color.text.secondary'):SetPoint('TOPLEFT',18,-12)
        Text(picker,T('scope'),'color.text.secondary'):SetPoint('TOPLEFT',242,-12)
        picker.scroll = GUI:CreateScrollFrame(picker,{template='UIPanelScrollFrameTemplate',width=368,height=248,childWidth=360,childHeight=248})
        picker.scroll:SetPoint('TOPLEFT',8,-40)
        local divider=GUI:CreateTexture(picker,nil,'ARTWORK')
        GUI:SetTexturePaintKey(divider,'color.border.subtle')
        divider:SetPoint('BOTTOMLEFT',8,46); divider:SetSize(360,GUI.mult or 1)
        self.configSetManagerButton=GUI.Form:CreateButton(picker,{text=T('manage'),width=360,height=32,contentAlign='left',justifyH='LEFT',textLeftPadding=10,onClick=function()
            if self.busyKind then return end
            self:HideSchemePicker(); self:OpenConfigSetManagerFromToolbar()
        end})
        self.configSetManagerButton:SetPoint('BOTTOMLEFT',8,8)
        self.configSetManagerButton.gui2SurfaceToken='color.surface.popup'
        self.configSetManagerButton.gui2BorderToken='color.surface.popup'
        self.configSetManagerButton.gui2TextColorKey='color.text.primary'
        self.configSetManagerButton:RefreshTheme()
        picker:EnableKeyboard(true)
        picker:SetScript('OnKeyDown',function(frame,key)
            local handled = key=='ESCAPE' or key=='UP' or key=='DOWN' or key=='HOME' or key=='END' or key=='ENTER'
            if not InCombatLockdown() then frame:SetPropagateKeyboardInput(not handled) end
            if not handled then return end
            if key=='ESCAPE' then self:HideSchemePicker(); return end
            if self.busyKind then return end
            local count=#frame.rows+1
            local index=frame.highlight or 1
            if key=='ENTER' then
                self:HideSchemePicker()
                if index==count then self:OpenConfigSetManagerFromToolbar() else self:RequestSwitch(frame.rows[index].id) end
                return
            end
            if key=='HOME' then index=1 elseif key=='END' then index=count
            else index=((index-1+(key=='DOWN' and 1 or -1))%count)+1 end
            frame.highlight=index
            for i,row in ipairs(frame.pool) do row:SetSelected(i==index) end
            self.configSetManagerButton:SetSelected(index==count)
            if index<count then frame.scroll:SetVerticalScroll(math.max(0,math.min((index-1)*36, #frame.rows*36-frame.viewportHeight))) end
        end)
        picker:SetScript('OnHide',function(frame) frame:UnregisterEvent('GLOBAL_MOUSE_DOWN'); HideTip() end)
        picker:SetScript('OnEvent',function(frame)
            if not frame:IsMouseOver() and not self.profileDropdown:IsMouseOver() then frame:Hide() end
        end)
    end
    picker:ClearAllPoints(); picker:SetPoint('TOPLEFT',self.profileDropdown,'BOTTOMLEFT',0,-5)
    picker:SetScale(self.toolbar:GetScale()); picker:Show(); picker:RegisterEvent('GLOBAL_MOUSE_DOWN')
    self:RefreshSchemePicker()
    self.configSetManagerButton:SetSelected(false)
    picker.highlight=1
    for i,row in ipairs(picker.rows) do if row.id==self.profileDropdown:GetValue() then picker.highlight=i break end end
    picker.scroll:SetVerticalScroll(math.max(0,math.min((picker.highlight-1)*36,#picker.rows*36-picker.viewportHeight)))
end

function UI:RefreshToolbarContext()
    if not self.toolbarWarning then return end
    local session = Designer:GetSession(); if not session then return end
    local rows = self:BuildToolbarSchemeRows() or {}
    local current
    for _,row in ipairs(rows) do if row.id==session.setId then current=row break end end
    self.profileDropdown.value=session.setId
    self.profileDropdown:SetText(current and current.name or '')
    self.profileDropdown.fullName=current and current.name
    local reference = Settings.ConfigSets:ResolveAssignment(HUD.ConfigSets.PROVIDER_ID, session.viewSpecKey)
    local warning=''
    if current and reference and (reference.kind~='user' or reference.id~=session.setId) then
        warning=T('warning_short',self:GetToolbarSpecNames({session.viewSpecKey}))
    end
    self.toolbarWarning:SetShown(warning~='')
    self.toolbarWarningText=warning
    self:RefreshSchemePicker()
end

function UI:LayoutToolbar()
    local bar=self.toolbar; if not bar then return end
    local available=UIParent:GetWidth()-40
    local width=792
    bar:SetSize(width,80); bar:SetScale(math.min(1,available/width))
    -- Include the separately anchored mode tabs in the screen boundary.
    bar:SetClampRectInsets(0,0,0,-40/bar:GetScale())
    local function Place(control,x,y,w)
        control:ClearAllPoints(); control:SetPoint('TOPLEFT',bar,'TOPLEFT',x,y)
        if w then control:SetWidth(w) end
    end
    local brandWidth=math.min(112,self.toolbarTitle:GetStringWidth())
    local brandLeft=8+(140-28-6-brandWidth)/2
    Place(self.toolbarLogo,brandLeft,-26)
    self.toolbarTitle:ClearAllPoints(); self.toolbarTitle:SetPoint('LEFT',bar,'TOPLEFT',brandLeft+34,-40); self.toolbarTitle:SetWidth(brandWidth)
    Place(self.toolbarSchemeLabel,168,-15,72); Place(self.toolbarSpecLabel,168,-51,72)
    Place(self.profileDropdown,244,-8,152); Place(self.viewSpecButton,244,-44,152)
    Place(self.toolbarWarning,400,-44,20)
    local x=436
    Place(self.globalSoundButton,x,-8,102); Place(self.libraryButton,x+110,-8,102)
    Place(self.layoutButton,x,-44,102); Place(self.blizzardCooldownButton,x+110,-44,102)
    Place(self.finishButton,width-122,-8,108); Place(self.cancelButton,width-122,-44,108)
    for _,control in ipairs({self.profileDropdown,self.viewSpecButton,self.globalSoundButton,self.libraryButton,self.layoutButton,self.blizzardCooldownButton,self.finishButton,self.cancelButton}) do control:SetHeight(28) end
    for i,pos in ipairs({156,424,width-132}) do
        local line=self.toolbarDividers[i]; line:ClearAllPoints(); line:SetPoint('TOPLEFT',bar,'TOPLEFT',pos,-8); line:SetSize(GUI.mult or 1,64)
    end
end

function UI:CreateDesignerToolbar()
    if self.toolbar then return end
    local bar=GUI:CreatePanel(UIParent,{name='YUI_YHUD_DesignerToolbar',width=1280,height=96,surface='color.surface.popup',border='color.popup.border',shadow=true})
    self.toolbar=bar; bar:SetPoint('TOP',UIParent,'TOP',0,-16); bar:SetFrameStrata('FULLSCREEN_DIALOG'); bar:SetFrameLevel(500); bar:EnableMouse(true); bar:Hide()
    bar:SetMovable(true); bar:SetClampedToScreen(true); bar:RegisterForDrag('LeftButton')
    bar:SetScript('OnDragStart',function(frame)
        if not self.active or self.busyKind then return end
        self:HideSchemePicker(); self:HideSpecializationPicker(); HideTip()
        frame.dragging=true; frame:StartMoving()
    end)
    bar:SetScript('OnDragStop',function(frame)
        if frame.dragging then frame:StopMovingOrSizing(); frame.dragging=nil end
    end)
    local series=Settings.CelestialSeries
    self.toolbarLogo=GUI:CreateIcon(bar,{icon=series and series:GetIcon('yhud',32) or YUI.Assets:Product('yhud','icons\\logo_32.png'),size=28,crop=false,layer='ARTWORK'})
    self.toolbarTitle=GUI:CreateText(bar,series and series:GetTitle('yhud',HUD:T('product.brand_suffix')) or HUD:T('designer.title'),'font.size.lg','color.text.heading','LEFT')
    self.toolbarTitle:SetWordWrap(false)
    self.toolbarSchemeLabel=Text(bar,T('choose')); self.toolbarSpecLabel=Text(bar,T('editing'))
    self.toolbarWarning=GUI:CreateFrame(bar,{mouse=true,width=24,height=28})
    local warningHit=self.toolbarWarning
    GUI:CreateIcon(warningHit,{icon='Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew',size=18,crop=false}):SetPoint('CENTER')
    warningHit:Hide()
    warningHit:SetScript('OnEnter',function(frame) Tip(frame,self.toolbarWarningText) end); warningHit:SetScript('OnLeave',HideTip)
    local function Button(text,callback,tone)
        return GUI.Form:CreateButton(bar,{text=text,width=120,height=32,tone=tone or 'default',onClick=callback})
    end
    self.profileDropdown=GUI.Form:CreateButton(bar,{text='',width=168,height=32,contentAlign='left',justifyH='LEFT',textLeftPadding=12,textRightPadding=28,onClick=function() self:ToggleSchemePicker() end})
    local dropdown=self.profileDropdown
    dropdown.gui2TextColorKey='color.text.primary'
    dropdown.gui2HoverTextColorKey='color.text.primary'
    dropdown:RefreshTheme()
    dropdown.text:ClearAllPoints(); dropdown.text:SetPoint('LEFT',12,0); dropdown.text:SetPoint('RIGHT',-28,0); dropdown.text:SetJustifyH('LEFT')
    GUI:CreateGlyph(dropdown,{glyph='dropdownDown',size=12,colorKey='color.text.secondary'}):SetPoint('RIGHT',-8,0)
    function dropdown:GetValue() return self.value end
    function dropdown:SetValue(value)
        -- Inspector selection refreshes write the current scheme again. Catalog
        -- and specialization changes refresh the toolbar through their own paths.
        if self.value == value then return end
        self.value=value
        UI:RefreshToolbarContext()
    end
    dropdown:HookScript('OnEnter',function(frame)
        if self.schemePicker and self.schemePicker:IsShown() then return end
        if frame.text:IsTruncated() then Tip(frame,frame.fullName) end
    end); dropdown:HookScript('OnLeave',HideTip)
    self.viewSpecButton=GUI.Form:CreateButton(bar,{text='-',width=168,height=32,icon=134400,iconSize=20,preserveIconColor=true,contentAlign='left',onClick=function() self:HideSchemePicker(); self:ToggleSpecializationPicker() end})
    self.viewSpecButton.gui2TextRightPadding=28
    GUI:CreateGlyph(self.viewSpecButton,{glyph='dropdownDown',size=12,colorKey='color.text.secondary'}):SetPoint('RIGHT',-8,0)
    self.globalSoundButton=Button(T('sound'),function()
        self:HideSchemePicker(); self:HideSpecializationPicker()
        if self.recommendedLibrary then self.recommendedLibrary:Hide() end
        if HUD.Client and HUD.Client.soundReminders == false then
            Settings:ShowConfirmPopup(T('sound_unavailable'), nil, {
                owner = HUD.PRODUCT_ID,
                ownerFrame = self.toolbar,
                dismissWithOwner = true,
                titleText = T('sound'),
                buttons = { { text = YUI.Locale:Get('Core')['common.confirm'] } },
            })
            return
        end
        if Settings.SoundCenter then Settings.SoundCenter:OpenFromDesigner() end
    end,'accent')
    self.libraryButton=Button(T('library'),function() self:HideSchemePicker(); self:ToggleRecommendedLibrary() end)
    self.layoutButton=Button(T('anchors'),function() self:OpenLayoutMode() end)
    self.blizzardCooldownButton=Button(T('blizzard'),function() self:OpenBlizzardCooldownSettings() end)
    self.finishButton=Button(YUI.Locale:Get('Core')['common.save_and_exit'],function() self:SaveAndClose() end,'success')
    self.cancelButton=Button(YUI.Locale:Get('Core')['common.cancel'],function() self:RequestCancelClose() end)
    StyleToolbarAction(self.globalSoundButton,'sound')
    StyleToolbarAction(self.libraryButton,'tool')
    StyleToolbarAction(self.layoutButton,'tool')
    StyleToolbarAction(self.blizzardCooldownButton,'tool')
    StyleToolbarAction(self.finishButton,'save')
    StyleToolbarAction(self.cancelButton,'cancel')
    self.toolbarDividers={}
    for i=1,3 do local line=GUI:CreateTexture(bar,nil,'ARTWORK'); GUI:SetTexturePaintKey(line,'color.border.subtle'); self.toolbarDividers[i]=line end
    bar:SetScript('OnShow',function()
        if self.toolbarResetPending then
            bar:ClearAllPoints(); bar:SetPoint('TOP',UIParent,'TOP',0,-16)
            self.toolbarResetPending=nil
        end
        self:LayoutToolbar(); self:RefreshToolbarContext()
        YUI.Event:On('DISPLAY_SIZE_CHANGED','LayoutToolbar',self)
        YUI.Event:On('UI_SCALE_CHANGED','LayoutToolbar',self)
        YUI.Event:On('YUI_CONFIG_SETS_CHANGED','RefreshToolbarContext',self)
    end)
    bar:SetScript('OnHide',function()
        if bar.dragging then bar:StopMovingOrSizing(); bar.dragging=nil end
        self:HideSchemePicker()
        if self.recommendedLibrary then self.recommendedLibrary:Hide() end
        if Settings.SoundCenter and Settings.SoundCenter.CloseDesignerWindow then Settings.SoundCenter:CloseDesignerWindow() end
        YUI.Event:Off('DISPLAY_SIZE_CHANGED','LayoutToolbar',self); YUI.Event:Off('UI_SCALE_CHANGED','LayoutToolbar',self); YUI.Event:Off('YUI_CONFIG_SETS_CHANGED','RefreshToolbarContext',self)
    end)
    self:LayoutToolbar()
end
