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
    local title, description = value:match('^([^\n]+)\n?(.*)$')
    GUI.Tooltip:Show(owner, {title=title, content=description ~= '' and function(body)
        for line in description:gmatch('[^\n]+') do body:AddLine(line, 'body') end
    end or nil})
end
local function HideTip() GameTooltip:Hide() end
local function StateText(key, enabled)
    return GUI.Tooltip:ColorText(T(key), enabled and 'success' or 'secondary')
end
local GRID_STEPS = { 64, 32, 16 }
local GRID_LABELS = { 'grid_sparse', 'grid_medium', 'grid_dense' }
local function ToolbarIcon(name)
    return GUI:GetUIIcon(name == 'cooldown' and 'timer' or name, 16)
end

local function StyleToolbarAction(button, kind)
    local refresh = button.RefreshTheme
    function button:RefreshTheme()
        local r,g,b = GUI:GetColor('color.surface.popup')
        local unavailable = kind=='sound' and HUD.Client and HUD.Client.soundReminders == false
        local tint = kind=='save' and 'color.state.success' or 'color.state.warning'
        local tr,tg,tb = GUI:GetColor(tint)
        if kind=='save' then
            local neutral=(tr+tg+tb)/3
            tr,tg,tb=tr*0.8+neutral*0.2,tg*0.8+neutral*0.2,tb*0.8+neutral*0.2
        end
        local manage = kind=='manage'
        local filled = kind=='save' or manage
        local strength = manage and 0.055 or 0.28
        local hr,hg,hb=GUI:GetColor('color.text.primary')
        local hover={r+(hr-r)*0.045,g+(hg-g)*0.045,b+(hb-b)*0.045,1}
        local function Fill(amount)
            return {r+(tr-r)*amount,g+(tg-g)*amount,b+(tb-b)*amount,1}
        end
        self.gui2SurfaceToken = filled and Fill(strength) or {0,0,0,0}
        self.gui2BorderToken = manage and Fill(0.16) or {0,0,0,0}
        self.gui2HoverSurfaceToken = filled and Fill(strength+(manage and 0.035 or 0.08)) or hover
        self.gui2HoverBorderToken = manage and Fill(0.23) or {0,0,0,0}
        self.gui2PressedSurfaceToken = filled and Fill(strength+(manage and 0.055 or 0.04)) or 'color.control.pressed'
        self.gui2PressedBorderToken = manage and Fill(0.28) or {0,0,0,0}
        self.gui2SelectedSurfaceToken = Fill(0.08)
        self.gui2SelectedBorderToken = Fill(0.16)
        self.gui2SelectedTextColorKey = 'color.state.warning'
        self.gui2TextColorKey = unavailable and 'color.text.disabled'
            or 'color.text.primary'
        self.gui2HoverTextColorKey = self.gui2TextColorKey
        self.gui2PressedTextColorKey = self.gui2HoverTextColorKey
        refresh(self)
    end
    button:RefreshTheme()
end

function UI:GetToolbarViewPreferences()
    if not self.toolbarViewPreferences then
        self.toolbarViewPreferences = {background=true, gridDensity=0}
    end
    return self.toolbarViewPreferences
end

function UI:RefreshToolbarGrid(density)
    if density == 0 or not self.dimmer or not self.toolbar:IsShown() then
        if self.toolbarGrid then self.toolbarGrid:Hide() end
        return
    end
    local grid = self.toolbarGrid
    if not grid then
        grid = GUI:CreateFrame(self.dimmer, {allPoints=true, mouse=false, level=101})
        grid.lines = {}
        self.toolbarGrid = grid
    end
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    local pixel = GUI.GetPixelSize and GUI:GetPixelSize(grid, 1, 1) or GUI.mult or 1
    grid:Show()
    if grid.width == width and grid.height == height and grid.density == density and grid.pixel == pixel then return end
    grid.width, grid.height, grid.density, grid.pixel = width, height, density, pixel
    -- Use one integral physical-pixel interval so scaling cannot alternate cell widths.
    -- Round the pool limit upward to keep unusual display sizes bounded too.
    local stepPixels = math.max(1, math.floor(GRID_STEPS[density] / pixel + 0.5), math.ceil((width + height) / (500 * pixel)))
    local step = stepPixels * pixel
    local centerX = math.floor(width / (2 * pixel)) * pixel
    local centerY = math.floor(height / (2 * pixel)) * pixel
    local count = 0
    local function Line(vertical, index)
        count = count + 1
        local line = grid.lines[count]
        if not line then
            line = GUI:CreateTexture(grid, nil, 'ARTWORK')
            grid.lines[count] = line
        end
        line:ClearAllPoints()
        line:SetPoint('BOTTOMLEFT', grid, 'BOTTOMLEFT', vertical and centerX + index * step or 0, vertical and 0 or centerY + index * step)
        line:SetSize(vertical and pixel or width, vertical and height or pixel)
        GUI:SetTexturePaintKey(line, index == 0 and 'color.accent.primary' or 'color.text.secondary')
        line:SetAlpha(index == 0 and 0.4 or index % 4 == 0 and 0.22 or 0.12)
        line:Show()
    end
    local columns, rows = math.floor(width / (2 * step)), math.floor(height / (2 * step))
    for index = -columns, columns do Line(true, index) end
    for index = -rows, rows do Line(false, index) end
    for index = count + 1, #grid.lines do grid.lines[index]:Hide() end
end

function UI:RefreshToolbarView()
    local preferences = self:GetToolbarViewPreferences()
    if self.dimmer and self.dimmer.shade then self.dimmer.shade:SetShown(preferences.background) end
    if self.backgroundButton then self.backgroundButton:SetSelected(preferences.background) end
    if self.gridButton then
        local density = preferences.gridDensity
        self.gridButton:SetSelected(density > 0)
        self.gridButton:SetText(density > 0 and T(GRID_LABELS[density] .. '_short') or '')
    end
    self:RefreshToolbarGrid(preferences.gridDensity)
end

function UI:ToggleToolbarBackground()
    if self.busyKind then return end
    local preferences = self:GetToolbarViewPreferences()
    preferences.background = not preferences.background
    self:RefreshToolbarView()
end

function UI:CycleToolbarGrid()
    if self.busyKind then return end
    local preferences = self:GetToolbarViewPreferences()
    preferences.gridDensity = (preferences.gridDensity + 1) % 4
    self:RefreshToolbarView()
end

function UI:HideToolbarNotice()
    local notice = self.toolbarNotice
    if not notice then return end
    YUI.Animation:StopOwner(notice, false)
    notice:Hide()
end

function UI:ShowToolbarNotice()
    if self.busyKind or not self.toolbar:IsShown() then return end
    self:HideToolbarNotice()
    local notice = self.toolbarNotice
    if not notice then
        notice = GUI:CreateFrame(self.toolbar, {width=320, height=28, mouse=false})
        notice:SetPoint('TOPRIGHT', self.toolbar, 'BOTTOMRIGHT', -12, -10)
        notice.label = GUI:CreateText(notice, T('coming_soon'), 'font.size.md', 'color.text.primary', 'RIGHT')
        notice.label:SetAllPoints(notice)
        self.toolbarNotice = notice
    end
    notice:SetAlpha(1)
    notice:Show()
    GUI:Animate(notice, {
        owner=notice, key='toolbar-notice', driver='native', easing='out',
        effects={
            {type='alpha', from=0, to=1, duration=0.18, order=1},
            {type='alpha', from=1, to=1, duration=1.8, order=2},
            {type='alpha', from=1, to=0, duration=0.45, order=3},
        },
        onFinished=function(_, _, finished) if finished then notice:Hide() end end,
    })
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

function UI:HideGlobalSettings()
    if self.globalSettingsPanel then self.globalSettingsPanel:Hide() end
end

function UI:ToggleGlobalSettings()
    if self.busyKind or self.libraryImportActive then return end
    local panel = self.globalSettingsPanel
    if panel and panel:IsShown() then self:HideGlobalSettings(); return end
    self:HideSchemePicker(); self:HideSpecializationPicker(); HideTip()
    if self.recommendedLibrary then self.recommendedLibrary:Hide() end
    if Settings.SoundCenter and Settings.SoundCenter.CloseDesignerWindow then Settings.SoundCenter:CloseDesignerWindow() end
    if not panel then
        local left,right=HUD.GlobalSettings:GetConfig()
        local fields={}
        for _,column in ipairs({left,right}) do
            for _,field in ipairs(column) do fields[#fields+1]=field end
        end
        local panelHeight=176+#fields*42
        panel = GUI:CreatePanel(UIParent, {width=440,height=panelHeight,surface='color.surface.popup',border='color.popup.border',shadow=true})
        panel:Hide(); self.globalSettingsPanel=panel
        panel:SetFrameStrata('FULLSCREEN_DIALOG'); panel:SetFrameLevel(660); panel:SetClampedToScreen(true); panel:EnableMouse(true)
        Text(panel,HUD:T('settings.global'),'color.text.heading'):SetPoint('TOPLEFT',16,-16)
        GUI:CreateCloseButton(panel,function() self:HideGlobalSettings() end):SetPoint('TOPRIGHT',-10,-10)
        local description=GUI:CreateText(panel,HUD:T('settings.global.independent'),'font.size.sm','color.text.secondary','LEFT')
        description:SetPoint('TOPLEFT',16,-46); description:SetSize(408,34); description:SetWordWrap(true); description:SetJustifyV('TOP')
        panel.yuiRetainedBindings={}; panel.controls={}
        local body=GUI:CreateFrame(panel,{width=408,height=#fields*42-8}); body:SetPoint('TOPLEFT',16,-90)
        for index,field in ipairs(fields) do
            local isSwitch=field.type=='checkbox'
            local caption=Text(body,field.text or field.label,field.disabled and 'color.text.disabled' or nil)
            caption:SetPoint('TOPLEFT',0,-(index-1)*42); caption:SetSize(isSwitch and 342 or 178,28); caption:SetJustifyV('MIDDLE')
            local options={}
            for key,value in pairs(field) do options[key]=value end
            options.label=nil; options.width=isSwitch and 54 or 220; options.height=28
            local control
            if isSwitch then
                control=GUI.Form:CreateSwitch(body,options)
                control:SetHitRectInsets(-342,0,0,0)
                -- Switches do not opt into the shared retained-value registry.
                panel.yuiRetainedBindings[#panel.yuiRetainedBindings+1]={widget=control,opts=options}
            elseif field.type=='slider' then
                options.inline=true; options.inputWidth=field.valueWidth
                control=GUI.Form:CreateSlider(body,options)
            else
                control=GUI.Form:CreateDropdown(body,options)
                panel.scopeDropdown=control
            end
            control:SetPoint('TOPRIGHT',body,'TOPRIGHT',0,-(index-1)*42)
            panel.controls[index]=control
        end
        local scopeNote=GUI:CreateText(panel,HUD:T('settings.global.level_scope'),'font.size.sm','color.text.secondary','LEFT')
        scopeNote:SetPoint('TOPLEFT',16,-90-#fields*42+4); scopeNote:SetSize(408,30); scopeNote:SetWordWrap(true); scopeNote:SetJustifyV('TOP')
        local divider=GUI:CreateTexture(panel,nil,'ARTWORK'); GUI:SetTexturePaintKey(divider,'color.border.subtle')
        divider:SetPoint('BOTTOMLEFT',16,50); divider:SetSize(408,GUI.mult or 1)
        local immediate=GUI:CreateText(panel,HUD:T('settings.global.immediate'),'font.size.sm','color.text.secondary','LEFT')
        immediate:SetPoint('BOTTOMLEFT',16,20)
        panel.closeButton=GUI.Form:CreateButton(panel,{text=HUD:T('settings.global.close'),width=84,height=28,onClick=function() self:HideGlobalSettings() end})
        panel.closeButton:SetPoint('BOTTOMRIGHT',-16,10)
        panel:EnableKeyboard(true)
        panel:SetScript('OnKeyDown',function(frame,key)
            if not InCombatLockdown() then frame:SetPropagateKeyboardInput(key~='ESCAPE') end
            if key=='ESCAPE' then
                local dropdown=GUI.DropdownFrame
                if dropdown and dropdown:IsShown() and dropdown.anchor==frame.scopeDropdown then GUI:CloseDropdown(false)
                else self:HideGlobalSettings() end
            end
        end)
        panel:SetScript('OnEvent',function(frame)
            local dropdown=GUI.DropdownFrame
            if dropdown and dropdown:IsShown() and dropdown.anchor==frame.scopeDropdown and dropdown:IsMouseOver() then return end
            if not frame:IsMouseOver() and not self.globalSettingsButton:IsMouseOver() then self:HideGlobalSettings() end
        end)
        panel:SetScript('OnShow',function(frame)
            self.globalSettingsButton:SetSelected(true); frame:RegisterEvent('GLOBAL_MOUSE_DOWN')
        end)
        panel:SetScript('OnHide',function(frame)
            self.globalSettingsButton:SetSelected(false); frame:UnregisterEvent('GLOBAL_MOUSE_DOWN'); HideTip()
            local dropdown=GUI.DropdownFrame
            if dropdown and dropdown.anchor==frame.scopeDropdown then GUI:CloseDropdown(false) end
        end)
        HUD.GlobalSettings:Bind('toolbar',panel)
    end
    panel:ClearAllPoints(); panel:SetPoint('TOPLEFT',self.globalSettingsButton,'BOTTOMLEFT',0,-8)
    panel:SetScale(math.min(self.toolbar:GetScale(),(UIParent:GetHeight()-32)/panel:GetHeight())); panel:Show()
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
    picker:SetHeight(picker.viewportHeight+48)
    picker.scroll:SetHeight(picker.viewportHeight)
    GUI:FitScrollContent(picker.scroll,math.max(36, #picker.rows*36))
end

function UI:ToggleSchemePicker()
    if self.busyKind then return end
    if self.schemePicker and self.schemePicker:IsShown() then self:HideSchemePicker(); return end
    self:HideSpecializationPicker(); self:HideGlobalSettings()
    HideTip()
    local picker = self.schemePicker
    if not picker then
        picker = GUI:CreatePanel(UIParent, {width=396,height=266,surface='color.surface.popup',border='color.popup.border',shadow=true})
        self.schemePicker = picker; picker.pool = {}
        picker:SetFrameStrata('FULLSCREEN_DIALOG'); picker:SetFrameLevel(660); picker:EnableMouse(true)
        Text(picker,T('name'),'color.text.secondary'):SetPoint('TOPLEFT',18,-12)
        Text(picker,T('scope'),'color.text.secondary'):SetPoint('TOPLEFT',242,-12)
        picker.scroll = GUI:CreateScrollFrame(picker,{template='UIPanelScrollFrameTemplate',width=368,height=248,childWidth=360,childHeight=248})
        picker.scroll:SetPoint('TOPLEFT',8,-40)
        picker:EnableKeyboard(true)
        picker:SetScript('OnKeyDown',function(frame,key)
            local handled = key=='ESCAPE' or key=='UP' or key=='DOWN' or key=='HOME' or key=='END' or key=='ENTER'
            if not InCombatLockdown() then frame:SetPropagateKeyboardInput(not handled) end
            if not handled then return end
            if key=='ESCAPE' then self:HideSchemePicker(); return end
            if self.busyKind then return end
            local count=#frame.rows
            if count==0 then return end
            local index=frame.highlight or 1
            if key=='ENTER' then
                self:HideSchemePicker()
                self:RequestSwitch(frame.rows[index].id)
                return
            end
            if key=='HOME' then index=1 elseif key=='END' then index=count
            else index=((index-1+(key=='DOWN' and 1 or -1))%count)+1 end
            frame.highlight=index
            for i,row in ipairs(frame.pool) do row:SetSelected(i==index) end
            if index<=#frame.rows then frame.scroll:SetVerticalScroll(math.max(0,math.min((index-1)*36, #frame.rows*36-frame.viewportHeight))) end
        end)
        picker:SetScript('OnHide',function(frame) frame:UnregisterEvent('GLOBAL_MOUSE_DOWN'); HideTip() end)
        picker:SetScript('OnEvent',function(frame)
            if not frame:IsMouseOver() and not self.profileDropdown:IsMouseOver() then frame:Hide() end
        end)
    end
    picker:ClearAllPoints(); picker:SetPoint('TOPLEFT',self.profileDropdown,'BOTTOMLEFT',0,-5)
    picker:SetScale(self.toolbar:GetScale()); picker:Show(); picker:RegisterEvent('GLOBAL_MOUSE_DOWN')
    self:RefreshSchemePicker()
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
    self:RefreshSpellAlertPreview()
end

function UI:LayoutToolbar()
    local bar=self.toolbar; if not bar then return end
    local available=UIParent:GetWidth()-40
    local actions={self.globalSettingsButton,self.globalSoundButton,self.libraryButton,self.layoutButton,self.blizzardCooldownButton}
    local actionWidths,actionsWidth={},12
    for index,control in ipairs(actions) do
        local contentInsets=control==self.globalSettingsButton and 42 or 38
        actionWidths[index]=math.max(96,control.text:GetStringWidth()+contentInsets)
        actionsWidth=actionsWidth+actionWidths[index]+8
    end
    local manageWidth=math.max(80,self.configSetManagerButton.text:GetStringWidth()+12)
    local saveWidth=math.max(124,self.finishButton.text:GetStringWidth()+16)
    local cancelWidth=math.max(60,self.cancelButton.text:GetStringWidth()+12)
    local profileX=180+manageWidth+8
    local specX=profileX+188
    local warningX=specX+232
    local rightWidth=saveWidth+8+cancelWidth
    local width=math.max(940,actionsWidth+rightWidth+36,warningX+20+32+rightWidth+8)
    local rightX=width-rightWidth-8
    bar:SetSize(width,80); bar:SetScale(math.min(1,available/width))
    -- Include the separately anchored mode tabs in the screen boundary.
    bar:SetClampRectInsets(0,0,0,-40/bar:GetScale())
    local function Place(control,x,y,w)
        control:ClearAllPoints(); control:SetPoint('TOPLEFT',bar,'TOPLEFT',x,y)
        if w then control:SetWidth(w) end
    end
    Place(self.toolbarLogo,12,-8)
    self.toolbarTitle:ClearAllPoints(); self.toolbarTitle:SetPoint('LEFT',bar,'TOPLEFT',46,-22); self.toolbarTitle:SetWidth(112)
    Place(self.configSetManagerButton,180,-8,manageWidth)
    Place(self.profileDropdown,profileX,-8,180); Place(self.viewSpecButton,specX,-8,224)
    Place(self.toolbarWarning,warningX,-8,20)
    Place(self.finishButton,rightX,-8,saveWidth); Place(self.cancelButton,rightX+saveWidth+8,-8,cancelWidth)
    local x=12
    for index,control in ipairs(actions) do
        local actionWidth=actionWidths[index]
        Place(control,x,-44,actionWidth)
        x=x+actionWidth+8
    end
    local toolGap=math.floor((rightWidth-168)/4+0.5)
    Place(self.spellAlertPreviewButton,rightX,-44,28); Place(self.backgroundButton,rightX+28+toolGap,-44,28)
    Place(self.gridButton,rightX+56+toolGap*2,-44,56); Place(self.creditsButton,rightX+112+toolGap*3,-44,28)
    Place(self.tutorialButton,rightX+rightWidth-28,-44,28)
    for _,control in ipairs({self.configSetManagerButton,self.globalSettingsButton,self.profileDropdown,self.viewSpecButton,self.globalSoundButton,self.libraryButton,self.layoutButton,self.blizzardCooldownButton,self.finishButton,self.cancelButton,self.spellAlertPreviewButton,self.backgroundButton,self.gridButton,self.creditsButton,self.tutorialButton}) do control:SetHeight(28) end
    local pixel=GUI.mult or 1
    local line=self.toolbarDividers[1]; line:ClearAllPoints(); line:SetPoint('TOPLEFT',bar,'TOPLEFT',168,-8); line:SetSize(pixel,28)
    line=self.toolbarDividers[2]; line:ClearAllPoints(); line:SetPoint('TOPLEFT',bar,'TOPLEFT',1,-40); line:SetSize(width-2,pixel)
    line=self.toolbarDividers[3]; line:ClearAllPoints(); line:SetPoint('TOPLEFT',bar,'TOPLEFT',rightX-16,-44); line:SetSize(pixel,28)
    self:RefreshToolbarView()
    self:RefreshSpellAlertPreview()
end

function UI:CreateDesignerToolbar()
    if self.toolbar then return end
    local bar=GUI:CreatePanel(UIParent,{name='YUI_YHUD_DesignerToolbar',width=1280,height=96,surface='color.surface.popup',border='color.popup.border',shadow=true})
    self.toolbar=bar; bar:SetPoint('TOP',UIParent,'TOP',0,-16); bar:SetFrameStrata('FULLSCREEN_DIALOG'); bar:SetFrameLevel(500); bar:EnableMouse(true); bar:Hide()
    bar:SetMovable(true); bar:SetClampedToScreen(true); bar:RegisterForDrag('LeftButton')
    bar:SetScript('OnDragStart',function(frame)
        if not self.active or self.busyKind then return end
        self:HideSchemePicker(); self:HideSpecializationPicker(); self:HideGlobalSettings(); HideTip()
        frame.dragging=true; frame:StartMoving()
    end)
    bar:SetScript('OnDragStop',function(frame)
        if frame.dragging then frame:StopMovingOrSizing(); frame.dragging=nil end
    end)
    local series=Settings.CelestialSeries
    self.toolbarLogo=GUI:CreateIcon(bar,{icon=series and series:GetIcon('yhud',128) or YUI.Assets:Product('yhud','icons\\logo_128.png'),size=28,crop=false,layer='ARTWORK'})
    self.toolbarTitle=GUI:CreateText(bar,series and series:GetTitle('yhud',HUD:T('product.brand_suffix')) or HUD:T('designer.title'),'font.size.lg','color.text.heading','LEFT')
    self.toolbarTitle:SetWordWrap(false)
    self.toolbarWarning=GUI:CreateFrame(bar,{mouse=true,width=24,height=28})
    local warningHit=self.toolbarWarning
    GUI:CreateIcon(warningHit,{icon='Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew',size=18,crop=false}):SetPoint('CENTER')
    warningHit:Hide()
    warningHit:SetScript('OnEnter',function(frame) Tip(frame,self.toolbarWarningText) end); warningHit:SetScript('OnLeave',HideTip)
    local function Button(text,callback,tone,icon)
        return GUI.Form:CreateButton(bar,{text=text,width=120,height=28,tone=tone or 'default',onClick=callback,
            icon=icon and ToolbarIcon(icon),iconSize=16,crop=false,iconGap=6})
    end
    self.configSetManagerButton=GUI.Form:CreateButton(bar,{text=T('manage'),width=80,height=28,tone='default',textLeftPadding=4,textRightPadding=4,onClick=function()
        if self.busyKind then return end
        self:HideSchemePicker(); self:HideGlobalSettings(); self:OpenConfigSetManagerFromToolbar()
    end})
    self.globalSettingsButton=Button(T('global'),function() self:ToggleGlobalSettings() end,nil,'settings')
    self.globalSettingsButton.gui2IconLeftPadding=6
    self.globalSettingsButton.gui2IconGap=12
    self.globalSettingsButton:SetText(T('global'))
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
    self.viewSpecButton=GUI.Form:CreateButton(bar,{text='-',width=168,height=32,icon=134400,iconSize=20,preserveIconColor=true,contentAlign='left',onClick=function() self:HideSchemePicker(); self:HideGlobalSettings(); self:ToggleSpecializationPicker() end})
    self.viewSpecButton.gui2TextRightPadding=28
    GUI:CreateGlyph(self.viewSpecButton,{glyph='dropdownDown',size=12,colorKey='color.text.secondary'}):SetPoint('RIGHT',-8,0)
    self.globalSoundButton=Button(T('sound'),function()
        self:HideSchemePicker(); self:HideSpecializationPicker(); self:HideGlobalSettings()
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
    end,nil,'sound')
    self.libraryButton=Button(T('library'),function() self:HideSchemePicker(); self:HideGlobalSettings(); self:ToggleRecommendedLibrary() end,nil,'library')
    self.layoutButton=Button(T('anchors'),function() self:HideGlobalSettings(); self:OpenLayoutMode() end,nil,'anchors')
    self.blizzardCooldownButton=Button(T('blizzard'),function() self:HideGlobalSettings(); self:OpenBlizzardCooldownSettings() end,nil,'cooldown')
    self.finishButton=Button(YUI.Locale:Get('Core')['common.save_and_exit'],function() self:SaveAndClose() end,'success')
    self.cancelButton=Button(YUI.Locale:Get('Core')['common.cancel'],function() self:RequestCancelClose() end)
    local function Utility(icon,callback,tooltip)
        local button
        button=Button('',function()
            callback()
            if GUI.Tooltip.owner==button then Tip(button,tooltip()) end
        end,nil,icon)
        button.gui2IconLeftPadding=6
        button:HookScript('OnEnter',function(frame) Tip(frame,tooltip()) end)
        button:HookScript('OnLeave',HideTip)
        StyleToolbarAction(button,'tool')
        return button
    end
    self.spellAlertPreviewButton=Utility('spell-alert',function() self:ToggleSpellAlertPreview() end,function()
        return T('spell_alert_tip',StateText(self.spellAlertPreviewEnabled and 'state_on' or 'state_off',self.spellAlertPreviewEnabled))
            .. '\n' .. self:GetSpellAlertPreviewSourceText()
    end)
    self.backgroundButton=Utility('background',function() self:ToggleToolbarBackground() end,function()
        local enabled=self:GetToolbarViewPreferences().background
        return T('background_tip',StateText(enabled and 'state_on' or 'state_off',enabled))
    end)
    self.gridButton=Utility('grid',function() self:CycleToolbarGrid() end,function()
        local density=self:GetToolbarViewPreferences().gridDensity
        return T('grid_tip',StateText(density>0 and GRID_LABELS[density] or 'state_off',density>0))
    end)
    self.creditsButton=Utility('credits',function() self:ShowToolbarNotice() end,function() return T('credits') end)
    self.tutorialButton=Utility('tutorial',function() self:ShowToolbarNotice() end,function() return T('tutorial') end)
    StyleToolbarAction(self.configSetManagerButton,'manage')
    StyleToolbarAction(self.globalSettingsButton,'tool')
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
        self:HideSpellAlertPreview()
        local preferences=self:GetToolbarViewPreferences()
        preferences.background,preferences.gridDensity=true,0
        self:RefreshToolbarView()
        self:HideToolbarNotice()
        HideTip()
        if bar.dragging then bar:StopMovingOrSizing(); bar.dragging=nil end
        self:HideSchemePicker()
        self:HideGlobalSettings()
        if self.recommendedLibrary then self.recommendedLibrary:Hide() end
        if Settings.SoundCenter and Settings.SoundCenter.CloseDesignerWindow then Settings.SoundCenter:CloseDesignerWindow() end
        YUI.Event:Off('DISPLAY_SIZE_CHANGED','LayoutToolbar',self); YUI.Event:Off('UI_SCALE_CHANGED','LayoutToolbar',self); YUI.Event:Off('YUI_CONFIG_SETS_CHANGED','RefreshToolbarContext',self)
    end)
    self:LayoutToolbar()
end
