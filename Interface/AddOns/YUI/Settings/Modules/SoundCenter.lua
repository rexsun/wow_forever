local YUI = _G.YUI
local Settings, GUI = YUI and YUI.Settings, YUI and YUI.GUI2
if not (Settings and GUI) or Settings.SoundCenter then return end
local Center = {}
Settings.SoundCenter = Center
local Form = GUI.Form
local dropdownIconCrop = {0.08, 0.92, 0.08, 0.92}
local function T(key) return YUI.Locale:Get('Core')['sound.center.'..key] end
Center.Text = T
function Center:ReviewTransfer(prepared, accept, cancel, owner, profileName)
    local labels, lines = YUI.Locale:Get('Core'), {}
    if profileName then lines[#lines+1]=string.format(labels['sound.share.profile_target'],profileName) end
    for _, entry in ipairs(prepared.entries) do
        local snapshot=entry.snapshot
        if entry.id=='core.sound.legacy' then
            lines[#lines+1]=string.format(labels['sound.share.legacy_counts'],snapshot.converted,snapshot.pending,snapshot.unchanged)
            lines[#lines+1]=labels['sound.share.legacy_recovery']
        elseif entry.id=='core.sound' then
            local counts=snapshot.counts
            lines[#lines+1]=snapshot.mode=='replace'
                and string.format(labels['sound.share.replace_effect'],counts.removed or 0) or labels['sound.share.incremental_effect']
            lines[#lines+1]=string.format(labels['sound.share.counts'],counts.added or 0,counts.updated or 0,counts.preserved or 0,counts.unchanged or 0)
            lines[#lines+1]=labels[(snapshot.scope.kind=='profile' or snapshot.scope.includeGeneral) and 'sound.share.has_general' or 'sound.share.no_general']
        else
            local label=owner and owner.moduleLabels and owner.moduleLabels[entry.id] or entry.id
            lines[#lines+1]=string.format(labels['sound.share.selected_module'],label)
        end
    end
    lines[#lines+1]=labels['sound.share.preferences_kept']
    return Settings:ShowConfigTransferReview(lines,accept,cancel,owner)
end
function Center:Share(action)
    local view = self.view
    if action == 'export' then
        self:ShowSoundExport()
    elseif action == 'import' then
        Settings:ShowConfigTransferImport({ layoutOwner=self:GetModalParent(), profileName = T('title'), localShare = true,
            context = { moduleIds = { 'core.sound' }, soundImportMode = 'incremental' },
            configureImport = function(owner)
                owner.reserveShare:Hide()
                if owner.yhudImportSpecs then owner.yhudImportSpecs:Hide() end
                owner.soundShareMode:SetWidth(340)
            end,
            reviewPrepared = function(prepared, accept, cancel, owner)
                Center:ReviewTransfer(prepared,accept,cancel,owner)
            end })
    end
end
function Center:ObjectTitle(name,object,extension)
    extension=extension or object.kind=='equipmentAura' or YUI.Sound.EditorModel:PotionBuff(object)
    local kind=extension and 'presetTag' or object.kind=='totem' and 'totem' or object.kind=='aura' and 'aura' or object.kind=='spell' and 'spell' or 'item'
    local r,g,b=GUI:GetColor(extension and 'color.badge.orange' or kind=='aura' and 'color.badge.purple' or kind=='spell' and 'color.badge.green' or 'color.text.accent')
    local color=string.format('|cff%02x%02x%02x',math.floor(r*255),math.floor(g*255),math.floor(b*255))
    return name..'  '..color..T(kind)..'|r'
end
function Center:ErrorText(code,detail)
    if code=='runtime-apply-failed' then
        local reason=type(detail)=='table' and detail.reason
        return T('invalid')..' ('..(type(reason)=='string' and reason or code)..')'
    end
    if code=='charge-not-multiple' then return T('chargeNotMultiple') end
    if code=='charge-capability-unknown' then return T('chargeCapabilityUnknown') end
    if code=='invalid-forecast-duration' then return T('forecastDurationRequired') end
    if code=='aura-sound-file-required' then return T('auraRecordingRequired') end
    if code=='aura-sound-combat-pending' then return T('auraRegistrationPending') end
    if code=='aura-sound-registration-pending' then return T('auraRegistrationScheduled') end
    if code=='aura-sound-delay-unavailable' then return T('auraDelayUnavailable') end
    if code=='aura-sound-registration-failed' or code=='aura-sound-unavailable' then return T('auraRegistrationFailed') end
    if code=='aura-sound-removal-failed' then return T('auraRemovalFailed') end
    if code=='game-sound-disabled' then return T('gameSoundDisabled') end
    if code=='spell-not-known' then return T('racialUnavailable') end
    if code=='native-aura-binding-unavailable' then return T('nativeAuraUnavailable') end
    if code=='native-aura-viewer-hidden' then return T('nativeAuraHidden') end
    if code=='native-totem-unavailable' or code=='native-totem-viewer-hidden' then return T('totemRequirement') end
    local keys={['conflicting-entry']='conflictingReminder',['stale-editor']='stale',['stale-preview']='stale',['stale_preview']='stale',
        ['stale_import']='stale',['profile_changed']='stale',['combat']='combat',
        ['in_combat']='combat',['combat-lockdown']='combat',['combat_lockdown']='combat',
        ['incomplete-timeline']='incompleteAudio',['unsupported-entry-client']='unsupportedVersion',
        ['prediction-duration-unavailable']='predictionUnknown',['missing-recording']='incompleteAudio',
        ['tts-unavailable']='ttsUnavailable',['tts-voice-unavailable']='ttsUnavailable',
        ['tts-events-unavailable']='ttsUnavailable',['completion-unavailable']='playbackUnknown',
        ['completion-schedule-failed']='playbackUnknown',['forecast-stop-unavailable']='playbackUnknown'}
    return T(keys[code] or 'invalid')
end
function Center:PreviewVoice(id)
    local ok,code=YUI.Sound:PreviewEntry(id)
    if not ok and code then
        self:Message(code)
        if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(self:ErrorText(code),1,0.2,0.2) end
    end
    return ok,code
end
function Center:Message(code)
    if self.view then self.view.status:SetText(self:ErrorText(code)); self.view:RefreshRows() end
end
function Center:AuraBindingText(rule)
    if rule.object.kind~='aura' and rule.object.kind~='equipmentAura' then return end
    local sound=YUI.Sound
    local engine=sound.Runtime and sound.Runtime.engine
    local key=sound.RuleModel:Key(rule)
    for _,binding in ipairs(engine and engine.bindings or {}) do
        if sound.RuleModel:Key(binding.rule)==key then
            local source=binding.handle and binding.handle.source
            local state=source and source.state
            local issue=binding.issue or state and state.issue
            if issecretvalue and issecretvalue(issue) then return T('nativeAuraUnavailable') end
            if issue=='native-aura-viewer-hidden' then return T('nativeAuraHidden') end
            if binding.nativeAuraUnit then
                if issue then return self:ErrorText(issue) end
                if not binding.directAuraRegistered then return T('auraRegistrationScheduled') end
            end
            local typeID=source and source.sourceType and source.sourceType.id
            if state and not issue and (typeID=='native-aura-signal' or typeID=='native-equipment-aura') then
                return T('nativeAuraBound')
            end
        end
    end
    return T('nativeAuraUnavailable')
end
function Center:RuleNotice(rule)
    local engine=YUI.Sound.Runtime and YUI.Sound.Runtime.engine
    for _,issue in ipairs(engine and engine.issues or {}) do
        if issue.key==YUI.Sound.RuleModel:Key(rule) then return self:ErrorText(issue.reason),'warning' end
    end
    if YUI.Sound.RuleStore:HasFamilyNotice(rule) then return T('familyDuplicateNotice'),'warning' end
    if rule.sound.kind=='forecast' then
        local ids={'VC-6b86b273','VC-d4735e3a','VC-4e074085','VC-4b227777','VC-ef2d127d','VC-e7f6c011','VC-7902699b','VC-2c624232','VC-19581e27','VC-4a44dc15'}
        local client=YUI.IsRetail and 'mainline' or YUI.IsWrath and 'wrath' or 'mists'
        for i=1,rule.sound.countdown do
            local entry=YUI.Sound.entries[ids[i]]
            if entry and not entry.clients[client] then return T('unsupportedVersion') end
        end
    end
    for _,binding in ipairs(engine and engine.bindings or {}) do
        if binding.rule.object.id==rule.object.id and binding.rule.trigger.event==rule.trigger.event then
            if binding.playbackIssue then return self:ErrorText(binding.playbackIssue) end
            if binding.auraPlaybackIssue then return self:ErrorText(binding.auraPlaybackIssue),'warning' end
            if (rule.trigger.extension=='boiling-point' or rule.trigger.extension=='bone-shield') and binding.issue then return self:ErrorText(binding.issue),'warning' end
            local state=binding.handle and binding.handle.source and binding.handle.source.state
            if state and state.stackIssue and rule.trigger.extension=='bone-shield' and rule.sound.introKind~='none' then return T('boneShieldCDM'),'warning' end
            if state and (state.issue=='native-aura-binding-unavailable' or state.issue=='native-aura-viewer-hidden') then
                return self:ErrorText(state.issue),'warning'
            end
            for _,key in ipairs({'cooldownStateSecret','chargeStateSecret'}) do
                local value=state and state[key]
                if not (issecretvalue and issecretvalue(value)) and value==true then return T('cooldownRestricted') end
            end
        end
    end
    if rule.object.kind=='aura' then
        for _,binding in ipairs(engine and engine.bindings or {}) do
            if binding.rule.object.id==rule.object.id and binding.rule.trigger.event==rule.trigger.event and binding.fallbackRequired then
                if not binding.directAuraID then return T('auraFileRequired'),'warning' end
            end
        end
    end
    if rule.trigger.event~='charge' then return nil end
    if YUI.IsRetail~=true then return T('nativeChargeUnavailable') end
    if YUI.Sound.EditorModel:HasCharges(rule.object)==false then return nil end
    local getter=C_CVar and C_CVar.GetCVarBool or GetCVarBool
    if type(getter)=='function' then
        local ok,enabled=pcall(getter,'cooldownViewerEnabled')
        if ok and not (issecretvalue and issecretvalue(enabled)) and enabled==false then return T('nativeChargeUnavailable') end
    end
    for _,binding in ipairs(engine and engine.bindings or {}) do
        if binding.rule.trigger.event=='charge' and binding.rule.object.id==rule.object.id
            and binding.handle.source.state.issue then return T('nativeChargeUnavailable') end
    end
end
function Center:GetModalParent() return self.modalHost or Settings.Elements.frame end

function Center:CloseChildren()
    for _, panel in pairs({self.editor, self.exportDialog, self.legacyPanel, GUI.VoicePicker and GUI.VoicePicker.dialog}) do
        panel:Hide()
    end
    local transfer = Settings.ConfigTransferDialog
    if transfer and transfer.options and transfer.options.layoutOwner == self:GetModalParent() then transfer:Hide() end
    if Settings.CloseSpecMultiSelectDropdown then
        if self.editor then Settings:CloseSpecMultiSelectDropdown(self.editor, 'sound-host-close') end
        if self.exportDialog then Settings:CloseSpecMultiSelectDropdown(self.exportDialog, 'sound-host-close') end
    end
    YUI.Sound:StopPreview()
end

function Center:ActivateView(view, host)
    if self.view and self.view ~= view then self.view:Hide() end
    if self.modalHost ~= host then self:CloseChildren() end
    self.view, self.modalHost = view, host
    -- Shared child dialogs are reused, but belong to the active host.
    for _, panel in pairs({self.editor, self.exportDialog, self.legacyPanel}) do
        panel:SetParent(host); panel:ClearAllPoints(); panel:SetPoint('CENTER', host)
        panel:SetFrameStrata(host:GetFrameStrata()); panel:SetFrameLevel(host:GetFrameLevel()+40)
    end
end

function Center:CloseDesignerWindow()
    if self.designerWindow then self.designerWindow:Hide() end
end

function Center:HandleDesignerEscape()
    local host=self.designerWindow
    if not host or not host:IsShown() then return false end
    local specOwner=Settings.Elements.specMultiSelectOwner
    local specPanel=specOwner and (specOwner==self.editor or specOwner==self.exportDialog) and Settings.Elements.specMultiSelectPanel
    local frames={GUI.VoicePicker and GUI.VoicePicker.dialog or false, Settings.reviewPanel or false, specPanel or false, self.editor or false, self.exportDialog or false, self.legacyPanel or false, Settings.ConfigTransferDialog or false}
    for _, panel in ipairs(frames) do
        if panel and panel:IsShown() then panel:Hide(); return true end
    end
    if self.view and self.view.preferences and self.view.preferences:IsShown() then
        self.view.preferences:Hide(); self.view.main:Show(); return true
    end
    host:Hide(); return true
end

function Center:OpenFromDesigner()
    local product=YUI.Sound and YUI.Sound.storageProductId
    if not product then return nil,'sound-unavailable' end
    local host=self.designerWindow
    if not host then
        host=GUI:CreatePanel(UIParent,{name='YUI_SoundDesignerWindow',width=1040,height=700,surface='color.surface.popup',border='color.popup.border',shadow=true})
        self.designerWindow=host
        host:SetPoint('CENTER'); host:SetFrameStrata('FULLSCREEN_DIALOG'); host:SetFrameLevel(900); host:EnableMouse(true); host:Hide()
        local notice=GUI:CreateText(host,T('designerScope'),'font.size.md','color.text.accent','LEFT')
        notice:SetPoint('TOPLEFT',20,-54); notice:SetPoint('TOPRIGHT',-46,-54); notice:SetHeight(24)
        local independent=GUI:CreateText(host,T('designerIndependent'),'font.size.sm','color.text.secondary','LEFT')
        host.scopeNotice,host.independentNotice=notice,independent
        independent:SetPoint('TOPLEFT',20,-80); independent:SetHeight(22)
        GUI:CreateCloseButton(host,function() host:Hide() end):SetPoint('TOPRIGHT',-12,-12)
        function host:OnProfileChanged() Center:CloseDesignerWindow() end
        function host:OnModuleDisabled(_,id) if id=='sound.runtime' then Center:CloseDesignerWindow() end end
        host:SetScript('OnHide',function()
            Center:CloseChildren()
            if host.view then host.view:Hide() end
            if host.database and host.database.UnregisterAllCallbacks then host.database.UnregisterAllCallbacks(host) end
            host.database=nil
            if YUI.Event then YUI.Event:OffOwner(host) end
            if Center.modalHost==host then Center.modalHost=nil; Center.view=nil end
        end)
    end
    local width=math.min(1040,UIParent:GetWidth()-48)
    local height=math.min(700,UIParent:GetHeight()-64)
    host:SetSize(width,height)
    if self.view and self.view~=host.view then self.view:Hide() end
    if not host.view then host.view=self:Create(host,width-40,height-36); host.view.designerHost=true; host.view:SetPoint('TOPLEFT',20,-18) end
    self:ActivateView(host.view,host)
    host.view:SetSize(width-40,height-36)
    if host.view.preferences then host.view.preferences:Hide() end
    host.view.main:Show()
    host.scopeNotice:Show();host.independentNotice:Show()
    host:Show(); host.view:Show(); host.view:Refresh()
    local db=YUI.DB:GetAceDB(product)
    if db and db.RegisterCallback and host.database~=db then
        host.database=db
        for _,event in ipairs({'OnProfileChanged','OnProfileCopied','OnProfileReset'}) do db.RegisterCallback(host,event,'OnProfileChanged') end
    end
    if YUI.Event then YUI.Event:On('YUI_MODULE_DISABLED','OnModuleDisabled',host) end
    return true
end
local function SpecIcon(spec)
    -- GetSpecSelectionGroups carries Talent API textures, not themed output.
    local native=spec.nativeIcon or spec.icon
    local api=YUI.API and YUI.API.Icons
    local data=api and api.GetScopedSpecIcon and api.GetScopedSpecIcon(spec.specID,native,'settings')
    if data and data.custom==false then native=data.texture or native;data=nil end
    return native,data
end
function Center:CloseSpecDropdown(control)
    local menu=GUI.DropdownFrame
    if menu and menu.anchor==control then GUI:CloseDropdown(false); return true end
end
function Center:RefreshSpecDropdown(control)
    local menu=GUI.DropdownFrame
    local reopen=menu and menu.anchor==control and menu:IsShown()
    control:RefreshOptions()
    if reopen then
        self:CloseSpecDropdown(control)
        local click=control:GetScript('OnClick')
        if click then click(control) end
    end
end
function Center:SpecOptions(category)
    local options={{text=T(category=='unified' and 'all' or 'allSpecs'),value='all'}}
    if category=='unified' then options[#options+1]={text=T('general'),value='general',icon=132996,texCoord=dropdownIconCrop} end
    for _,group in ipairs(Settings:GetSpecSelectionGroups({})) do
        for _,spec in ipairs(group.specs or {}) do
            local name=spec.classInfo.name..' · '..spec.displayName
            local color=RAID_CLASS_COLORS and RAID_CLASS_COLORS[spec.classInfo.token]
            if color then name=string.format('|cff%02x%02x%02x%s|r',math.floor(color.r*255),math.floor(color.g*255),math.floor(color.b*255),name) end
            local native,iconData=SpecIcon(spec)
            options[#options+1]={text=name,
                specID=spec.specID,classFile=spec.classInfo.token,value=spec.classInfo.token..':'..spec.specID,
                icon=native,iconData=iconData,texCoord=not iconData and dropdownIconCrop or nil}
        end
    end
    if category then
        local rules=YUI.Sound.RuleStore:Read() or {}
        for _,option in ipairs(options) do
            local count=0
            for _,rule in ipairs(rules) do
                local applies=option.value=='all' or not rule.specs
                if rule.specs then
                    for _,key in ipairs(rule.specs) do if key==option.value then applies=true end end
                else
                    for _,key in ipairs(rule.exceptSpecs or {}) do if key==option.value then applies=false end end
                end
                if category=='unified' and (option.value=='all' or option.value=='general' and rule.category=='general' or option.value~='general' and rule.category=='class' and applies) or rule.category==category and applies then count=count+1 end
            end
            if count>0 then
                local r,g,b=GUI:GetColor('color.badge.green')
                local color=string.format('|cff%02x%02x%02x',math.floor(r*255),math.floor(g*255),math.floor(b*255))
                option.text=string.format(T('categoryCount'),option.text..color,count)..'|r'
            end
        end
    end
    return options
end
function Center:PickerOptions(kind)
    local options=self:SpecOptions()
    options[1].text=T('allObjects')
    table.insert(options,2,{text=T('general'),value='general',icon=132996,texCoord=dropdownIconCrop})
    if (kind=='spell' or kind=='aura') and YUI.IsRetail then
        table.insert(options,3,{text=T('racial'),value='racial',icon=136225,texCoord=dropdownIconCrop})
    end
    local current=Settings:GetCurrentSpecSelectionKey()
    for _,option in ipairs(options) do
        if option.value==current then option.text=option.text..T('browseCurrent') end
    end
    return options
end
local function Text(parent,text,size,color)
    return GUI:CreateText(parent,text,size or 'font.size.md',color or 'color.text.primary','LEFT')
end
local function Button(parent,key,click,width,tone)
    return Form:CreateButton(parent,{text=T(key),height=30,width=width or 100,tone=tone or 'default',onClick=click})
end
local function IconButton(parent,key,icon,click)
    return Form:CreateIconButton(parent,{size=26,icon=GUI:GetSettingsIcon(icon),tooltip=T(key),onClick=click})
end
local function SetPreference(key,value)
    local sound=YUI.Sound
    local prefs,code=sound:GetPreferences()
    if not prefs then Center:Message(code); return end
    prefs[key]=value
    local ok; ok,code=sound:SetPreferences(prefs)
    if not ok then Center:Message(code) end
    return ok
end
Center.SetPreference=SetPreference

function Center:ShowSoundExport()
    local frame=self.exportDialog
    if not frame then
        frame=GUI:CreatePanel(self:GetModalParent(),{width=580,height=280,surface='color.surface.popup',border='color.popup.border'})
        self.exportDialog=frame; frame:SetPoint('CENTER'); frame:SetFrameStrata('DIALOG'); frame:EnableMouse(true)
        frame.values={}
        Text(frame,T('exportTitle'),'font.size.lg'):SetPoint('TOPLEFT',20,-20)
        GUI:CreateCloseButton(frame,function() frame:Hide() end):SetPoint('TOPRIGHT',-12,-12)
        Text(frame,T('applicableSpecs')):SetPoint('TOPLEFT',20,-68)
        local labels=YUI.Locale:Get('Core')
        frame.specPicker=Settings:CreateSpecMultiSelectDropdown(frame,{owner=frame,width=540,height=34,panelWidth=500,panelHeight=280,
            label=T('applicableSpecs'),defaultSelected=false,value=frame.values,
            selectAllText=labels['settings.config_transfer.select_all'],clearText=labels['settings.config_transfer.clear_all'],
            armorLabels={cloth=labels['settings.config_sets.armor.cloth'],leather=labels['settings.config_sets.armor.leather'],mail=labels['settings.config_sets.armor.mail'],plate=labels['settings.config_sets.armor.plate']},
            summaryFormatter=function()
                local count,total=0,0
                for _,group in ipairs(Settings:GetSpecSelectionGroups({})) do
                    for _,spec in ipairs(group.specs or {}) do
                        total=total+1
                        if frame.values[spec.key or (spec.classInfo.token..':'..spec.specID)] then count=count+1 end
                    end
                end
                return count==total and total>0 and T('allSpecs') or string.format(T('exportSpecCount'),count)
            end,
            set=function(values) frame.values=values; frame:RefreshCount() end})
        frame.specPicker:SetPoint('TOPLEFT',20,-94)
        frame.specPicker:HookScript('OnMouseUp',function(anchor)
            local popup=Settings.Elements.specMultiSelectPanel
            if Settings.Elements.specMultiSelectOwner==frame and popup and popup:IsShown() then
                popup:ClearAllPoints();popup:SetPoint('TOPLEFT',anchor,'BOTTOMLEFT',0,-8)
                popup:SetFrameStrata('TOOLTIP');popup:SetFrameLevel(9100)
            end
        end)
        frame.general=Form:CreateCheckbox(frame,{text=labels['sound.share.include_general'],width=540,
            get=function() return frame.includeGeneral end,set=function(value) frame.includeGeneral=value;frame:RefreshCount() end})
        frame.general:SetPoint('TOPLEFT',20,-146)
        frame.count=Text(frame,'');frame.count:SetPoint('TOPLEFT',20,-194)
        frame.primary=Form:CreateButton(frame,{text=labels['settings.config_transfer.generate'],width=190,height=34,onClick=function()
            frame:RefreshCount()
            if not frame.exportCount or frame.exportCount==0 then return end
            local value,detail=Settings.ConfigTransfer:BuildExport({'core.sound'},frame.context)
            if not value then Center:Message(detail);return end
            frame:Hide();Settings:ShowCopyPopup(T('exportTitle'),value)
        end})
        Form:StyleDialogPrimary(frame.primary)
        frame.primary:SetPoint('BOTTOMRIGHT',-20,16)
        function frame:RefreshCount()
            local specs={};for key,enabled in pairs(self.values) do if enabled then specs[#specs+1]=key end end;table.sort(specs)
            self.context={moduleIds={'core.sound'},soundSpecs=specs,includeGeneralSounds=self.includeGeneral==true}
            local rules,code=YUI.Sound.RuleStore:Read()
            if rules then rules,code=YUI.Sound.RuleModel:Export(rules,specs,self.includeGeneral==true) end
            self.exportCount=rules and #rules or nil
            self.count:SetText(rules and string.format(T('exportRuleCount'),#rules) or tostring(code))
            self.primary:SetDisabled(not rules or #rules==0)
        end
        frame:SetScript('OnHide',function() Settings:CloseSpecMultiSelectDropdown(frame,'export-close') end)
    end
    for key in pairs(frame.values) do frame.values[key]=nil end
    local selected=self.view and self.view.designSpec
    for _,group in ipairs(Settings:GetSpecSelectionGroups({})) do
        for _,spec in ipairs(group.specs or {}) do
            local key=spec.key or (spec.classInfo.token..':'..spec.specID)
            if not selected or selected=='all' or selected==key then frame.values[key]=true end
        end
    end
    frame.includeGeneral=selected=='all' or selected=='general';frame.general:SetValue(frame.includeGeneral,true);frame.specPicker:Refresh()
    local parent=self:GetModalParent()
    frame:SetParent(parent);frame:ClearAllPoints();frame:SetPoint('CENTER')
    frame:SetFrameStrata(parent:GetFrameStrata())
    frame:SetFrameLevel(math.max(parent:GetFrameLevel(),self.view and self.view:GetFrameLevel() or 0)+40)
    frame:RefreshCount();frame:Show()
    local scrim=GUI:ShowModalScrim(frame)
    if scrim then scrim:SetParent(parent);scrim:ClearAllPoints();scrim:SetAllPoints(parent) end
end

function Center:CreatePreferences(view)
    if view.preferences then return view.preferences end
    local panel=GUI:CreateFrame(view); panel:SetAllPoints(view); view.preferences=panel
    local scroll=GUI:CreateScrollFrame(panel,{autoHide=true,width=view:GetWidth()-18,height=view:GetHeight()})
    scroll:SetPoint('TOPLEFT'); scroll:SetPoint('BOTTOMRIGHT',-18,0)
    local body=scroll.child
    local title=Text(panel,T('settings'),'font.size.lg'); title:SetPoint('TOPLEFT',0,-8);title:SetHeight(28)
    local back=Form:CreateTextLink(body,{text='← '..T('back'),width=100,height=24,onClick=function() panel:Hide(); view.main:Show(); YUI.Sound:StopPreview() end})
    back:SetParent(panel);back:SetPoint('TOPRIGHT',-34,-8)
    scroll:ClearAllPoints();scroll:SetPoint('TOPLEFT',0,-48);scroll:SetPoint('BOTTOMRIGHT',-18,0)
    local packTitle=Text(body,T('pack'),'font.size.md'); packTitle:SetPoint('TOPLEFT',0,-8)
    panel.packCards={}
    local cardHeight,cardGap=96,12
    local function ShowPackTooltip(card)
        GUI.Tooltip:Show(card,{title=card.title:GetText(),content=function(tip)
            tip:AddLine(card.metadata:GetText())
            tip:AddLine(card.description:GetText())
            tip:AddLine(card.count:GetText())
        end,actions=YUI.Sound.voicePacks[card.packId] and {{text=T('randomPreview')}} or nil})
    end
    local function HidePackTooltip(card) GUI.Tooltip:Hide(card) end
    local sections={}
    for _,key in ipairs({'packPlayback','missingVoice','queueSettings'}) do
        local section=GUI:CreateFrame(body); sections[key]=section
        section.title=Text(section,T(key),'font.size.md'); section.title:SetPoint('TOPLEFT',0,-10)
        section.line=GUI:CreateDivider(section,100,1);section.line:SetPoint('TOPLEFT');section.line:SetPoint('TOPRIGHT')
    end
    local function Field(parent,key,create)
        local box=GUI:CreateFrame(parent,{height=70})
        box.label=Text(box,T(key),'font.size.md','color.text.secondary'); box.label:SetPoint('TOPLEFT')
        box.control=create(box); box.control:SetPoint('TOPLEFT',0,-26)
        return box
    end
    local function Drop(parent,key,options,get,set)
        return Field(parent,key,function(box) return Form:CreateDropdown(box,{width=280,height=34,options=options,get=get,set=set}) end)
    end
    local function Pref(key) return function() return YUI.Sound:GetPreferences()[key] end end
    local function channels()
        local options={}
        local api=YUI.API and YUI.API.Sound
        for _,key in ipairs({'Master','SFX','Dialog','Music','Ambience'}) do
            local volume=api and api.GetChannelVolume and api.GetChannelVolume(key)
            local label=YUI.Locale:Get('Core')['sound.channel.'..key:lower()]
            options[#options+1]={text=string.format(T('channelVolume'),label,volume~=nil and (volume..'%') or T('channelVolumeUnknown')),value=key}
        end
        return options
    end
    local channel=Drop(sections.packPlayback,'channel',channels,Pref('channel'),function(v) SetPreference('channel',v) end)
    panel.channel=channel.control
    local preview=Field(sections.packPlayback,'previewEntry',function(box)
        return Form:CreateButton(box,{text=T('browsePreview'),height=34,width=240,onClick=function()
            GUI.VoicePicker:Open(Center:GetModalParent(),{previewOnly=true,
                preview=function(id) Center:PreviewVoice(id) end,stopPreview=function() YUI.Sound:StopPreview() end})
        end})
    end)
    local randomPreview=Form:CreateButton(preview,{text=T('randomPreview'),height=34,width=120,onClick=function()
        local ok,code=YUI.Sound:PreviewRandomEntry()
        if not ok and code then Center:Message(code) end
    end})
    panel.randomPreview=randomPreview
    local fallback=Drop(sections.missingVoice,'fallback',{
        {text=T('fallbackBoth'),value='both'},{text=T('fallbackDefault'),value='default'},
        {text=T('fallbackTTS'),value='tts'},{text=T('fallbackNone'),value='none'}},nil,function(value)
        local p=YUI.Sound:GetPreferences(); p.fallbackDefault=value=='both' or value=='default'; p.fallbackTTS=value=='both' or value=='tts'
        local ok,code=YUI.Sound:SetPreferences(p); if not ok then Center:Message(code) end
    end)
    panel.fallback=fallback.control
    local ttsBody=GUI:CreateFrame(body)
    local ttsTitle=Text(ttsBody,T('ttsSettings')); ttsTitle:SetPoint('TOPLEFT',0,-10)
    local ttsLine=GUI:CreateDivider(ttsBody,100,1);ttsLine:SetPoint('TOPLEFT');ttsLine:SetPoint('TOPRIGHT')
    local voiceOptions={{text=T('systemVoice'),value='system'}}
    for _,voice in ipairs(YUI.Sound.Runtime.tts:GetVoices()) do voiceOptions[#voiceOptions+1]={text=voice.name,value=voice.id} end
    local voice=Drop(ttsBody,'voice',voiceOptions,Pref('ttsVoice'),function(v) SetPreference('ttsVoice',v) end)
    panel.voice=voice.control
    local sliders={}
    for _,definition in ipairs({{'rate',-10,10},{'volume',0,100}}) do
        local key,minimum,maximum=unpack(definition)
        sliders[key]=Field(ttsBody,key,function(box) return Form:CreateSlider(box,{width=280,inline=true,inputWidth=56,min=minimum,max=maximum,step=1,
            get=Pref(key),set=function(value) SetPreference(key,value) end}) end)
    end
    local dedup=Drop(sections.queueSettings,'dedup',{{text=T('dedupMerge'),value=true},{text=T('dedupQueue'),value=false}},Pref('dedup'),function(v) SetPreference('dedup',v) end)
    panel.dedup=dedup.control
    local expiry=Field(sections.queueSettings,'expiry',function(box) return Form:CreateEditBox(box,{width=120,height=34,
        onChange=function(_,value) local n=tonumber(value); if n and n>=1 and n<=60 then SetPreference('expiry',n) end end}) end)
    panel.notice=Text(body,'','font.size.md','color.state.warning')
    local function Place(box,x,y,width)
        box:ClearAllPoints(); box:SetPoint('TOPLEFT',x,-y); box:SetWidth(width)
        box.label:SetWidth(width); box.control:SetWidth(width)
        if box.control.slider and box.control.inputBox then
            box.control.slider:ClearAllPoints(); box.control.slider:SetPoint('LEFT',box.control,'LEFT',0,0)
            box.control.slider:SetWidth(width-66)
            box.control.inputBox:ClearAllPoints(); box.control.inputBox:SetPoint('RIGHT',box.control,'RIGHT',0,0)
        end
    end
    function panel:Refresh()
        local sound,prefs=YUI.Sound,YUI.Sound:GetPreferences()
        if not prefs then return end
        local width=math.max(300,view:GetWidth()-28); body:SetWidth(width)
        local columns=width>600 and 2 or 1; local cell=(width-(columns-1)*16)/columns
        local packs={}
        for id,info in pairs(sound.knownVoicePacks) do
            packs[#packs+1]={id=id,pack=sound.voicePacks[id],info=sound:GetVoicePackInfo(id)}
        end
        for id,pack in pairs(sound.voicePacks) do
            if not sound.knownVoicePacks[id] then packs[#packs+1]={id=id,pack=pack,info=sound:GetVoicePackInfo(id)} end
        end
        table.sort(packs,function(a,b) if a.id==b.id then return false elseif a.id=='yui.default' then return true elseif b.id=='yui.default' then return false end; return a.id<b.id end)
        for i,entry in ipairs(packs) do
            local card=self.packCards[i]
            if not card then
                card=Form:CreateButton(body,{height=cardHeight,text='',tone='default',onClick=function(button)
                    local sound=YUI.Sound
                    if not sound.voicePacks[button.packId] then return end
                    local prefs,code=sound:GetPreferences()
                    if not prefs then Center:Message(code);return end
                    if prefs.voicePackId~=button.packId and not SetPreference('voicePackId',button.packId) then return end
                    local ok;ok,code=sound:PreviewRandomEntry()
                    if not ok and code then Center:Message(code) end
                end})

                card.icon=GUI:CreateIconSlot(card,{size=36,crop=false});card.icon:SetPoint('TOPLEFT',12,-12)
                card.title=Text(card,'','font.size.md'); card.title:SetPoint('TOPLEFT',58,-12);card.title:SetHeight(18);card.title:SetWordWrap(false)
                card.metadata=Text(card,'','font.size.md','color.text.primary');card.metadata:SetPoint('TOPLEFT',58,-34);card.metadata:SetHeight(18);card.metadata:SetWordWrap(false)
                card.description=Text(card,'','font.size.md','color.text.primary');card.description:Hide()
                card.count=Text(card,'','font.size.md','color.text.primary'); card.count:SetPoint('BOTTOMLEFT',12,10);card.count:SetHeight(28);card.count:SetWordWrap(true)
                card:HookScript('OnEnter',ShowPackTooltip);card:HookScript('OnLeave',HidePackTooltip);card:HookScript('OnHide',HidePackTooltip)
                card.download=Form:CreateButton(card,{height=26,width=86,text=T('downloadPack'),onClick=function()
                    if card.downloadURL then Settings:ShowCopyPopup(T('downloadPack'),card.downloadURL) end
                end})
                card.download:SetPoint('BOTTOMRIGHT',-12,8)
                self.packCards[i]=card
            end
            local recordings,defaults=0,0
            local defaultPack=sound.voicePacks['yui.default']
            for id in pairs(sound.entries) do
                if entry.pack and entry.pack.entries[id] then recordings=recordings+1
                elseif prefs.fallbackDefault~=false and defaultPack and defaultPack.entries[id] then defaults=defaults+1 end
            end
            card.packId=entry.id;card.downloadURL=entry.info.downloadURL
            card:SetWidth(cell); card:ClearAllPoints(); card:SetPoint('TOPLEFT',((i-1)%columns)*(cell+16),-38-math.floor((i-1)/columns)*(cardHeight+cardGap))
            local icon=entry.info.icon
            if not entry.pack then icon='Interface\\Icons\\INV_Misc_QuestionMark'
            elseif entry.id=='yui.default' and YUI.Assets then icon=YUI.Assets:Core('images\\YUI-LOGO-300.png')
            elseif entry.pack and entry.info.addonIcon then icon=entry.info.addonIcon end
            card.icon:SetIcon(icon or 136183)
            if entry.pack then card.icon.icon:SetTexCoord(0,1,0,1)
            else card.icon.icon:SetTexCoord(.08,.92,.08,.92) end
            card.title:SetWidth(cell-70); card.title:SetText(sound:GetVoicePackLabel(entry.id))
            card.metadata:SetWidth(cell-70)
            local function Colored(value,key)
                local r,g,b=GUI:GetColor(key)
                return string.format('|cff%02x%02x%02x%s|r',math.floor(r*255),math.floor(g*255),math.floor(b*255),value)
            end
            card.metadata:SetText(string.format(T('packMetadata'),Colored(entry.info.author or T('unknownAuthor'),'color.badge.orange'),Colored(entry.info.language=='zhCN' and T('mandarin') or entry.info.language or T('unknownLanguage'),'color.badge.green'))..(entry.info.version and '  '..entry.info.version or ''))
            card.description:SetText(entry.info.descriptionKey and T(entry.info.descriptionKey) or entry.info.description or '')
            card.count:SetWidth(cell-(not entry.pack and card.downloadURL and 120 or 24))
            card.count:SetText(not entry.pack and Colored(T('packNotInstalled'),'color.badge.orange') or entry.id=='yui.default' and string.format(T('defaultVoiceCount'),recordings) or string.format(T('packCoverage'),recordings,defaults))
            card.download:SetShown(not entry.pack and card.downloadURL~=nil)
            card:SetSelected(entry.pack~=nil and prefs.voicePackId==entry.id); card:Show()
        end
        for i=#packs+1,#self.packCards do self.packCards[i]:Hide() end
        local y=54+math.ceil(#packs/columns)*(cardHeight+cardGap)
        self.notice:ClearAllPoints(); self.notice:SetPoint('TOPLEFT',0,-y); self.notice:SetText(not sound.voicePacks[prefs.voicePackId] and T('missingPack') or '')
        if not sound.voicePacks[prefs.voicePackId] then y=y+32 end
        local playback=sections.packPlayback; playback:SetSize(width,columns==2 and 120 or 200); playback:ClearAllPoints(); playback:SetPoint('TOPLEFT',0,-y)
        Place(channel,0,38,cell); Place(preview,columns==2 and cell+16 or 0,columns==2 and 38 or 118,cell)
        preview.control:SetWidth((cell-8)/2); preview.control:SetText(T('browsePreview'))
        randomPreview:SetWidth((cell-8)/2);randomPreview:ClearAllPoints();randomPreview:SetPoint('LEFT',preview.control,'RIGHT',8,0)
        y=y+(columns==2 and 120 or 200)
        local missing=sections.missingVoice; missing:SetSize(width,120); missing:ClearAllPoints(); missing:SetPoint('TOPLEFT',0,-y)
        Place(fallback,0,38,cell)
        y=y+120
        ttsBody:ClearAllPoints();ttsBody:SetPoint('TOPLEFT',0,-y);ttsBody:SetSize(width,columns==2 and 200 or 280);ttsBody:Show()
        Place(voice,0,38,cell);Place(sliders.rate,0,118,cell)
        Place(sliders.volume,columns==2 and cell+16 or 0,columns==2 and 118 or 198,cell)
        y=y+(columns==2 and 200 or 280)
        local queue=sections.queueSettings; queue:SetSize(width,columns==2 and 120 or 200); queue:ClearAllPoints(); queue:SetPoint('TOPLEFT',0,-y)
        Place(dedup,0,38,cell); Place(expiry,columns==2 and cell+16 or 0,columns==2 and 38 or 118,cell); expiry.control:SetWidth(cell)
        GUI:FitScrollContent(scroll,y+(columns==2 and 120 or 200))
        self.fallback:SetValue(prefs.fallbackDefault and (prefs.fallbackTTS and 'both' or 'default') or (prefs.fallbackTTS and 'tts' or 'none'),true)
        self.channel:RefreshOptions()
        self.channel:SetValue(prefs.channel,true); self.voice:SetValue(prefs.ttsVoice,true); self.dedup:SetValue(prefs.dedup,true)
        sliders.rate.control:SetValue(prefs.rate,true); sliders.volume.control:SetValue(prefs.volume,true); expiry.control:SetValue(prefs.expiry,true)
    end
    panel:SetScript('OnShow',function()
        view.status:Hide();scroll:SetVerticalScroll(0)
        if view.designerHost and Center.designerWindow then Center.designerWindow.scopeNotice:Hide();Center.designerWindow.independentNotice:Hide() end
        panel:Refresh()
    end)
    panel:SetScript('OnHide',function()
        view.status:Show(); YUI.Sound:StopPreview(); expiry.control:ClearFocus()
        if view.designerHost and Center.designerWindow then Center.designerWindow.scopeNotice:Show();Center.designerWindow.independentNotice:Show() end
    end)
    panel:Hide(); return panel
end

function Center:OpenLegacyRecovery()
    local panel = self.legacyPanel
    local parent = self:GetModalParent()
    if not parent then return end
    if not panel then
        panel = GUI:CreatePanel(parent, { width = 650, height = 470, surface = 'color.surface.popup', border = 'color.popup.border', shadow = true })
        self.legacyPanel = panel; panel:SetPoint('CENTER'); panel:EnableMouse(true); panel.offset = 0; panel.rows = {}
        local title = Text(panel, T('legacyTitle'), 'font.size.lg'); title:SetPoint('TOPLEFT', 18, -16)
        local close = GUI:CreateCloseButton(panel, function() panel:Hide() end); close:SetPoint('TOPRIGHT', -12, -12)
        local note = Text(panel, T('legacyNote'), 'font.size.md', 'color.text.secondary'); note:SetPoint('TOPLEFT', 18, -46)
        panel.note = note; note:SetWordWrap(true)
        panel.status = Text(panel, '', 'font.size.md', 'color.state.warning'); panel.status:SetPoint('BOTTOMLEFT', 18, 16)
        local previous = Button(panel, 'previous', function() panel.offset = math.max(0, panel.offset - panel.capacity); panel:Refresh() end, 90)
        previous:SetPoint('BOTTOMRIGHT', -118, 12)
        local nextPage = Button(panel, 'next', function() panel.offset = panel.offset + panel.capacity; panel:Refresh() end, 90)
        nextPage:SetPoint('BOTTOMRIGHT', -18, 12)
        for i = 1, 5 do
            local row = GUI:CreateFrame(panel, { height = 64 }); panel.rows[i] = row
            row:SetPoint('TOPLEFT', 18, -88 - (i - 1) * 64)
            row.label = Text(row, '', 'font.size.md'); row.label:SetPoint('TOPLEFT', 0, -4)
            row.detail = Text(row, '', 'font.size.md', 'color.text.secondary'); row.detail:SetPoint('TOPLEFT', 0, -27)
            row.detail:SetWordWrap(true)
            row.edit = Button(row, 'edit', function()
                local item = row.item
                local edit, code = YUI.Sound.EditorModel:BeginRecovery(item.provider, item.key)
                if not edit then panel.status:SetText(Center:ErrorText(code)); return end
                panel:Hide()
                local editor = Center:OpenEditor(nil, edit.rule.category, edit.rule.specs and edit.rule.specs[1])
                if editor then editor.edit = edit; editor.step = 1; editor:Refresh() end
            end, 70)
            row.edit:SetPoint('RIGHT', -112, 0)
            row.disable = Button(row, 'legacyDisable', function()
                local item = row.item
                Settings:ShowConfirmPopup(T('legacyDisableConfirm'), function()
                    local ok, code = item.provider:DisableLegacy(item.key, YUI.Sound.Runtime)
                    panel.status:SetText(ok and '' or Center:ErrorText(code)); panel:Refresh()
                end, { ownerFrame = panel, dismissWithOwner = true })
            end, 104)
            row.disable:SetPoint('RIGHT', 0, 0)
        end
        function panel:Refresh()
            local items = {}
            for _, provider in pairs(YUI.Sound.LegacyMigration and YUI.Sound.LegacyMigration.providers or {}) do
                if provider.GetRecoveryItems then for _, item in ipairs(provider:GetRecoveryItems()) do items[#items + 1] = item end end
            end
            local width = math.min(760, parent:GetWidth() - 24)
            local height = math.min(470, parent:GetHeight() - 24)
            self.capacity = math.max(1, math.min(5, math.floor((height - 140) / 64)))
            self.offset = math.min(self.offset, math.max(0, #items - self.capacity))
            self:SetSize(width, height); self.note:SetWidth(width - 36)
            self.status:SetWidth(math.max(60, width - 240))
            for index, row in ipairs(self.rows) do
                local item = index <= self.capacity and items[self.offset + index] or nil
                row.item = item; row:SetShown(item ~= nil)
                row:SetWidth(width - 36); row.label:SetWidth(width - 240); row.detail:SetWidth(width - 240)
                if item then
                    row.label:SetText(item.record.raw.sound or T('missingEntry'))
                    local reasons = { ['reserve-legacy-sound'] = 'legacyReserve', ['legacy-sound-conflict'] = 'legacyConflict',
                        ['muted-legacy-sound'] = 'legacyMuted' }
                    row.detail:SetText(item.record.spec .. ' · ' .. T(reasons[item.reason] or 'legacyUnknown'))
                end
            end
            previous:SetDisabled(self.offset == 0); nextPage:SetDisabled(self.offset + self.capacity >= #items)
            if #items == 0 then self.status:SetText(T('legacyComplete')) end
        end
        panel:SetScript('OnHide', function() YUI.Sound:StopPreview() end)
        if parent.HookScript then
            parent:HookScript('OnHide', function() panel:Hide() end)
            parent:HookScript('OnSizeChanged', function() if panel:IsShown() then panel:Refresh() end end)
        end
        if panel.EnableKeyboard then
            panel:EnableKeyboard(true)
            panel:SetScript('OnKeyDown', function(owner, key)
                if owner.SetPropagateKeyboardInput then owner:SetPropagateKeyboardInput(key ~= 'ESCAPE') end
                if key == 'ESCAPE' then owner:Hide() end
            end)
        end
    end
    panel:SetFrameStrata(parent:GetFrameStrata()); panel:SetFrameLevel(parent:GetFrameLevel() + 20)
    panel:Refresh(); panel:Show()
    local scrim = GUI:ShowModalScrim(panel)
    if scrim then scrim:SetParent(parent); scrim:ClearAllPoints(); scrim:SetAllPoints(parent) end
end

function Center:Create(parent,width,height)
    local view=GUI:CreateFrame(parent,{width=width,height=height})
    view.category='class'; view.query=''; view.offset=0; view.rows={}
    view.designSpec=Settings.ConfigSets and Settings.ConfigSets:GetCurrentSpecializationKey() or 'all'
    local main=GUI:CreateFrame(view,{width=width,height=height-28}); main:SetPoint('TOPLEFT'); main:SetPoint('BOTTOMRIGHT',-18,28); view.main=main
    local title=Text(main,T('title'),GUI.Fonts.size_title,'color.text.heading'); title:SetFont(GUI.Fonts.header,GUI.Fonts.size_title,'OUTLINE'); title:SetPoint('TOPLEFT',0,0)
    local disabledText=Text(main,YUI.Locale:Get('Core')['settings.nav.toggle.disabled_content'],'font.size.lg','color.text.secondary')
    disabledText:SetPoint('CENTER',main,'CENTER',0,-16); disabledText:Hide()
    local legacy = Button(main, 'legacyTitle', function() Center:OpenLegacyRecovery() end, 130)
    legacy:SetPoint('TOPLEFT', 120, 0)
    local master=Form:CreateSwitch(main,{variant='compact',get=function() return YUI.Sound:GetPreferences().enabled end,
        set=function(value) SetPreference('enabled',value) end}); master:SetPoint('TOPRIGHT',-108,-5)
    local masterLabel=Text(main,T('enabled')); masterLabel:SetPoint('RIGHT',master,'LEFT',-8,0)
    local pack=IconButton(main,'settings','settings',function() main:Hide(); Center:CreatePreferences(view):Show() end)
    pack:SetSize(30,30); pack:SetPoint('TOPRIGHT',0,-42)
    local share=Form:CreateTextLink(main,{text=T('importExport'),width=96,height=24,
        colorKey='color.text.primary',onClick=function(owner)
            GUI:OpenDropdown(owner,{
                {text=T('export'),func=function() Center:Share('export') end},
                {text=T('import'),func=function() Center:Share('import') end},
            },nil,nil,130)
        end})
    share:SetPoint('TOPRIGHT',0,0)
    local packLabel=Text(main,'','font.size.md','color.text.secondary'); packLabel:SetPoint('RIGHT',pack,'LEFT',-10,0); packLabel:SetJustifyH('RIGHT'); packLabel:SetWordWrap(false)
    local spec=Form:CreateSpecDropdown(main,{width=260,height=34,menuWidth=300,options=function() return Center:SpecOptions('unified') end,
        get=function() return view.designSpec end,set=function(value) view.designSpec=value; view.offset=0; view:RefreshRows() end})
    spec:SetPoint('TOPRIGHT',0,-108)
    local search=Form:CreateEditBox(main,{width=260,height=34,placeholder=T('search'),searchPlaceholder=true,onChange=function(_,value)
        view.query=value or ''; view.offset=0; if view.RefreshRows then view:RefreshRows() end
    end})
    search:SetPoint('LEFT',spec,'RIGHT',8,0)
    view.searchInput=search
    local add=Button(main,'add',function() Center:OpenEditor(nil,view.designSpec=='general' and 'general' or 'class',view.designSpec=='general' and 'all' or view.designSpec) end,112,'accent')
    add:SetRelief('hairline')
    add.gui2SurfaceToken='color.badge.orange'; add.gui2HoverSurfaceToken='color.badge.orange.hover'; add.gui2PressedSurfaceToken='color.badge.orange.pressed'
    add.gui2TextColorKey='color.text.primary'; add.gui2HoverTextColorKey='color.text.primary'; add.gui2PressedTextColorKey='color.text.primary'
    add:SetState('normal')
    add:SetPoint('TOPRIGHT',0,-158); add:SetHeight(34)
    local headers={}
    for _,key in ipairs({'object','when','content','actions'}) do headers[key]=Text(main,T(key),'font.size.md','color.text.secondary') end
    local mainScroll=GUI:CreateScrollFrame(main,{width=width-18,height=height-250,autoHide=true})
    mainScroll:SetPoint('TOPLEFT',0,-222); mainScroll:SetPoint('BOTTOMRIGHT',0,0)
    local list=mainScroll.child
    view.listScroll=mainScroll
    if mainScroll.HookScript then mainScroll:HookScript('OnVerticalScroll',function() if view.PaintRows then view:PaintRows() end end) end
    local empty=Text(list,T('empty'),'font.size.md','color.text.secondary'); empty:SetPoint('TOPLEFT',0,-20)
    view.status=Text(view,'','font.size.md','color.text.secondary'); view.status:SetPoint('BOTTOMLEFT',0,0)
    local undo
    undo=Button(view,'undo',function()
        if not view.undo then return end
        local ok,code=YUI.Sound.RuleStore:CommitEdit(view.undo.token,view.undo.rules,YUI.Sound.Runtime)
        if ok then view.undo=nil; undo:Hide(); view.status:SetText(''); view:RefreshRows() else Center:Message(code) end
    end,110)
    undo:SetPoint('BOTTOMRIGHT',0,-4); undo:Hide()
    for index=1,12 do
        local row=GUI:CreatePanel(list,{height=82,width=width,surface='color.surface.panel',border='color.border.subtle'})
        view.rows[index]=row
        row:EnableMouse(true)
        row:SetScript('OnEnter',function(owner)
            if GameTooltip and owner.rule then
                GameTooltip:SetOwner(owner,'ANCHOR_RIGHT'); GameTooltip:SetText(owner.name:GetText())
                GameTooltip:AddLine(' ')
                local r,g,b=GUI:GetColor(owner.kind.gui2ColorKey or 'color.text.secondary')
                GameTooltip:AddLine(T('tooltipType')..owner.kind:GetText(),r,g,b,true)
                GameTooltip:AddLine(T('tooltipScope')..(owner.tooltipScope or ''),1,1,1,true)
                GameTooltip:AddLine(T('tooltipTrigger')..owner.when:GetText(),1,1,1,true)
                local bindingText=Center:AuraBindingText(owner.rule)
                if bindingText then GameTooltip:AddLine(T('tooltipBinding')..bindingText,1,1,1,true) end
                GameTooltip:AddLine(' ')
                GameTooltip:AddLine(T('tooltipPlayback')..owner.sound:GetText(),1,1,1,true)
                GameTooltip:AddLine(T('tooltipSource')..owner.soundKind:GetText(),1,1,1,true)
                if owner.noticeWarning then
                    r,g,b=GUI:GetColor('color.state.warning')
                    GameTooltip:AddLine(' '); GameTooltip:AddLine(owner.noticeHelp or owner.loadSummary or '',r,g,b,true)
                end
                GameTooltip:Show()
            end
        end)
        local function HideRowTooltip(owner) if GameTooltip and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end end
        row:SetScript('OnLeave',HideRowTooltip); row:SetScript('OnHide',HideRowTooltip)
        row.icon=GUI:CreateIcon(row,{width=32,height=32,texture=134400}); row.icon:SetPoint('LEFT',8,0)
        row.name=Text(row,'','font.size.md'); row.name:SetPoint('TOPLEFT',row.icon,'TOPRIGHT',8,0); row.name:SetWordWrap(false)
        row.kind=Text(row,'','font.size.md','color.text.secondary'); row.kind:SetPoint('BOTTOMLEFT',row.icon,'BOTTOMRIGHT',8,0)
        row.when=Text(row,'','font.size.md'); row.when:SetWordWrap(false)
        row.sound=Text(row,'','font.size.md','color.text.secondary'); row.sound:SetWordWrap(true)
        row.soundKind=Text(row,'','font.size.md','color.text.secondary')
        row.load=Text(row,'','font.size.md','color.text.secondary'); row.load:SetWordWrap(false)
        row.noticeLink=Form:CreateTextLink(row,{text='',width=180,height=16,colorKey='color.state.warning',onClick=function()
            local api=YUI.API and YUI.API.CooldownViewer
            local ok,code
            local designer=YUI.YHUD and YUI.YHUD.DesignerUI
            if view.designerHost and designer and designer.active then
                ok=designer:OpenBlizzardCooldownSettings()
            elseif api and api.OpenSettings then ok,code=api:OpenSettings() end
            if not ok then Center:Message(code or 'unavailable') end
        end})
        if row.noticeLink.text then
            row.noticeLink.text:ClearAllPoints();row.noticeLink.text:SetPoint('LEFT',0,0)
            row.noticeLink.text:SetJustifyH('LEFT')
        end
        if row.noticeLink.underline then row.noticeLink.underline:Hide() end
        row.noticeLink:HookScript('OnEnter',function()
            if row.noticeLink.underline then row.noticeLink.underline:Show() end
            row:GetScript('OnEnter')(row)
        end)
        row.noticeLink:HookScript('OnLeave',function() if row.noticeLink.underline then row.noticeLink.underline:Hide() end; HideRowTooltip(row) end)

        row.specIcons={}
        for i=1,4 do row.specIcons[i]=GUI:CreateIcon(row,{width=16,height=16,texture=134400}) end
        row.delete=IconButton(row,'delete','trash-2',function()
            local store=YUI.Sound.RuleStore; local before=store:BeginEdit()
            local ok,code=YUI.Sound.EditorModel:Change(row.index,'delete')
            if ok then view.undo={token=store:BeginEdit(),rules=before.rules}; undo:Show(); view.status:SetText(T('deleted')); view:RefreshRows()
            else Center:Message(code) end
        end)
        row.delete:SetPoint('RIGHT',-6,0)
        row.edit=IconButton(row,'edit','pencil',function() Center:OpenEditor(row.index) end)
        row.edit:SetPoint('RIGHT',row.delete,'LEFT',-4,0)
        row.preview=IconButton(row,'preview','play',function()
            local ok=YUI.Sound.EditorModel:Preview(row.rule)
            if not ok then view.status:SetText(T('unavailable')); view:RefreshRows() end
        end)
        row.preview:SetPoint('RIGHT',row.edit,'LEFT',-4,0)
        row.toggle=Form:CreateSwitch(row,{variant='compact',set=function()
            local ok,code=YUI.Sound.EditorModel:Change(row.index,'toggle'); if not ok then Center:Message(code) end
        end})
        row.toggle:SetPoint('RIGHT',row.preview,'LEFT',-8,0)
    end
    function view:RefreshRows()
        local sound,rows=YUI.Sound,{}
        local rules=sound.RuleStore:Read() or {}
        local specNames={}
        for _,group in ipairs(Settings:GetSpecSelectionGroups({})) do
            for _,entry in ipairs(group.specs or {}) do specNames[entry.classInfo.token..':'..entry.specID]=entry end
        end
        for index,rule in ipairs(rules) do
            local inSpec=self.designSpec=='all' or not rule.specs
            if rule.specs then for _,value in ipairs(rule.specs) do if value==self.designSpec then inSpec=true end end
            else for _,value in ipairs(rule.exceptSpecs or {}) do if value==self.designSpec then inSpec=false end end end
            local displaySpec=tonumber((self.designSpec or ''):match(':(%d+)$')) or sound.EditorModel:RuleSpec(rule)
            local name,icon=sound.EditorModel:ObjectInfo(rule.object,rule.trigger.extension,displaySpec)
            local when,content=sound.EditorModel:TriggerLabel(rule,displaySpec),sound.EditorModel:SoundLabel(rule.sound)
            if (self.designSpec=='all' or self.designSpec=='general' and rule.category=='general' or self.designSpec~='general' and rule.category=='class' and inSpec)
                and (self.query=='' or (name..' '..when..' '..content):lower():find(self.query:lower(),1,true)) then
                local load={}
                local icons={}
                for _,key in ipairs(rule.specs or {}) do
                    local entry=specNames[key]; load[#load+1]=entry and entry.displayName or key
                    if entry and entry.icon then icons[#icons+1]=entry end
                end
                local chosen={}; for _,key in ipairs(rule.specs or {}) do chosen[key]=true end
                local allSpecs=rule.specs~=nil and next(specNames)~=nil
                for key in pairs(specNames) do if not chosen[key] then allSpecs=false; break end end
                if allSpecs then load={T('allSpecs')}; icons={} end
                if rule.exceptSpecs then
                    local excluded={}; for _,key in ipairs(rule.exceptSpecs) do excluded[#excluded+1]=specNames[key] and specNames[key].displayName or key end
                    load={string.format(T('exceptSpecs'),table.concat(excluded,' / '))}
                end
                local tooltipScope={}
                for _,key in ipairs(rule.specs or {}) do
                    local entry=specNames[key]
                    local color=entry and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classInfo.token]
                    local label=entry and entry.displayName or key
                    if color then label=string.format('|cff%02x%02x%02x%s|r',math.floor(color.r*255),math.floor(color.g*255),math.floor(color.b*255),label) end
                    tooltipScope[#tooltipScope+1]=label
                end
                local notice,severity=Center:RuleNotice(rule)
                local noticeHelp=(notice==T('nativeAuraUnavailable') or notice==T('nativeAuraHidden') or notice==T('boneShieldCDM')) and T('nativeAuraUnavailableHelp') or nil
                rows[#rows+1]={tooltipScope=(not allSpecs and not rule.exceptSpecs and #tooltipScope>0) and table.concat(tooltipScope,' / ') or (#load>0 and table.concat(load,' · ') or T('unlimited')),index=index,rule=rule,name=name,icon=icon,when=when,content=content,icons=icons,notice=notice,noticeHelp=noticeHelp,noticeWarning=notice~=nil and severity~='info',
                    load=notice or (#load>0 and table.concat(load,' · ') or T('unlimited'))}
            end
        end
        local function Rank(rule)
            if rule.trigger.extension or rule.object.kind=='equipmentAura' or rule.object.kind=='itemGroup' or YUI.Sound.EditorModel:PotionBuff(rule.object) then return 1 end
            return rule.object.kind=='aura' and 2 or rule.object.kind=='spell' and 3 or 4
        end
        table.sort(rows,function(a,b)
            local left,right=Rank(a.rule),Rank(b.rule)
            return left<right or (left==right and a.index<b.index)
        end)
        spec:RefreshOptions(); spec:SetValue(self.designSpec,true)
        self.filteredRows=rows
        local w=self:GetWidth()-18
        local roomyFilters=w>=720
        local compactHeader=self.designerHost and w>=900
        local tightHeader=not self.designerHost and w>=640 and not legacy:IsShown()
        self.headerY=self.designerHost and (compactHeader and 142 or 176) or (tightHeader and 86 or 130)
        self.listTop=self.headerY+22
        self.rowHeight=w>600 and 48 or 78
        local footerHeight=(self.status:GetText()~='' or undo:IsShown()) and 28 or 4
        main:ClearAllPoints(); main:SetPoint('TOPLEFT'); main:SetPoint('BOTTOMRIGHT',-18,footerHeight)
        main:SetSize(w,self:GetHeight()-footerHeight)
        mainScroll:ClearAllPoints(); mainScroll:SetPoint('TOPLEFT',0,-self.listTop); mainScroll:SetPoint('BOTTOMRIGHT',0,0)
        mainScroll:SetSize(w,math.max(self.rowHeight,self:GetHeight()-footerHeight-self.listTop)); list:SetWidth(w)
        GUI:FitScrollContent(mainScroll,math.max(self.rowHeight,#rows*self.rowHeight))
        local maxScroll=math.max(0,list:GetHeight()-mainScroll:GetHeight())
        mainScroll:SetVerticalScroll(math.min(mainScroll:GetVerticalScroll() or 0,maxScroll))
        local filterY=self.designerHost and (compactHeader and 98 or 132) or (tightHeader and 40 or 84)
        pack:ClearAllPoints();pack:SetPoint('TOPRIGHT',compactHeader and -120 or 0,compactHeader and -filterY or (self.designerHost and -90 or -42))
        packLabel:SetWidth(compactHeader and 140 or math.max(90,w-50))
        if tightHeader then
            pack:ClearAllPoints();pack:SetPoint('TOPRIGHT',-220,0)
            packLabel:SetWidth(math.min(180,w-470))
        end
        local specWidth=compactHeader and 220 or (roomyFilters and 260 or 240)
        spec:ClearAllPoints();spec:SetPoint('TOPLEFT',0,-filterY);spec:SetWidth(specWidth)
        search:SetWidth(math.max(90,math.min(290,w-specWidth-(compactHeader and 322 or 136))))
        add:ClearAllPoints();add:SetPoint('TOPRIGHT',0,-filterY)
        self:PaintRows()
    end
    function view:PaintRows()
        local rows=self.filteredRows or {}
        local w=self:GetWidth()-18
        local scroll=mainScroll.GetVerticalScroll and mainScroll:GetVerticalScroll() or 0
        local capacity=math.min(12,math.ceil(mainScroll:GetHeight()/self.rowHeight)+1)
        self.offset=math.max(0,math.floor(scroll/self.rowHeight))
        if self.paintedRows==rows and self.paintedOffset==self.offset and self.paintedWidth==w and self.paintedHeight==mainScroll:GetHeight() then return end
        self.paintedHeight=mainScroll:GetHeight()
        self.paintedRows,self.paintedOffset,self.paintedWidth=rows,self.offset,w
        local wide=w>600
        local available=w-150
        local nameWidth=math.floor(available*(wide and 1.1/3 or .50))
        local whenWidth=wide and math.floor(available/3) or available-nameWidth
        local contentWidth=math.max(40,available-nameWidth-whenWidth)
        headers.object:ClearAllPoints(); headers.object:SetPoint('TOPLEFT',8,-self.headerY)
        headers.when:ClearAllPoints(); headers.when:SetPoint('TOPLEFT',nameWidth+8,-self.headerY)
        headers.content:ClearAllPoints(); headers.content:SetPoint('TOPLEFT',nameWidth+whenWidth+16,-self.headerY); headers.content:SetShown(wide)
        headers.actions:ClearAllPoints(); headers.actions:SetPoint('TOPRIGHT',-80,-self.headerY)
        for index,row in ipairs(self.rows) do
            local item=index<=capacity and rows[self.offset+index]
            if item then
                local dimmed=not item.rule.enabled or item.noticeWarning
                row.index,row.rule=item.index,item.rule; row:SetSize(w,self.rowHeight); row:ClearAllPoints(); row:SetPoint('TOPLEFT',0,-(self.offset+index-1)*self.rowHeight)
                row.name:SetText(item.name); row.name:SetWidth(nameWidth-52); row.icon:SetTexture(item.icon); row.icon:SetAlpha(dimmed and .45 or 1)
                row.name:ClearAllPoints();row.name:SetPoint('TOPLEFT',48,-8)
                row.kind:ClearAllPoints();row.kind:SetPoint('TOPLEFT',48,-26)
                for _,label in ipairs({row.name,row.kind,row.when,row.load,row.sound}) do
                    label:SetHeight(16);label:SetJustifyV('MIDDLE');label:SetAlpha(dimmed and .5 or 1)
                end
                row.kind:SetText(T((item.rule.object.kind=='equipmentAura' or item.rule.object.kind=='itemGroup' or YUI.Sound.EditorModel:PotionBuff(item.rule.object)) and 'presetTag' or item.rule.trigger.extension and ((item.rule.trigger.extension=='boiling-point' or item.rule.trigger.extension=='bone-shield') and 'presetTag' or 'forecastTag') or item.rule.object.kind=='totem' and 'totem' or item.rule.object.kind=='aura' and 'aura' or item.rule.object.kind=='spell' and 'spell' or 'item'))
                local colorKey=(item.rule.trigger.extension or item.rule.object.kind=='equipmentAura' or item.rule.object.kind=='itemGroup' or YUI.Sound.EditorModel:PotionBuff(item.rule.object)) and 'color.badge.orange' or item.rule.object.kind=='aura' and 'color.badge.purple' or item.rule.object.kind=='spell' and 'color.badge.green' or 'color.text.secondary'
                if row.kind.gui2ColorKey~=colorKey then GUI:SetTextColorKey(row.kind,colorKey) end
                row.kind:SetWidth(nameWidth-52)
                row.when:ClearAllPoints(); row.when:SetPoint('TOPLEFT',nameWidth+8,-8); row.when:SetWidth(whenWidth-12)
                row.load:ClearAllPoints(); row.load:SetPoint('TOPLEFT',nameWidth+8,-26); row.load:SetWidth(whenWidth-12)
                row.noticeWarning=item.noticeWarning; row.noticeHelp=item.noticeHelp
                GUI:SetTextColorKey(row.load,item.noticeWarning and 'color.state.warning' or 'color.text.secondary')
                if item.noticeWarning then row.load:SetAlpha(1) end
                row.loadSummary=item.load; row.tooltipScope=item.tooltipScope
                row.load:SetText(wide and #item.icons>4 and not item.notice and ('+'..(#item.icons-4)) or item.load)
                if wide and #item.icons>4 and not item.notice then row.load:ClearAllPoints(); row.load:SetPoint('TOPLEFT',nameWidth+92,-26) end
                row.load:SetShown(not item.noticeHelp and (not wide or #item.icons==0 or #item.icons>4 or item.notice~=nil))
                row.noticeLink:ClearAllPoints();row.noticeLink:SetPoint('TOPLEFT',nameWidth+8,-26)
                row.noticeLink:SetWidth(whenWidth-12);row.noticeLink:SetText(item.notice or '')
                row.noticeLink:SetShown(item.noticeHelp~=nil)
                for i,icon in ipairs(row.specIcons) do
                    icon:SetAlpha(dimmed and .45 or 1)
                    icon:ClearAllPoints(); icon:SetPoint('TOPLEFT',nameWidth+8+(i-1)*20,-26)
                    icon:SetShown(wide and item.icons[i]~=nil and not item.notice)
                    if item.icons[i] then
                        local entry=item.icons[i]
                        local api=YUI.API and YUI.API.Icons
                        local native,data=SpecIcon(entry)
                        if not (data and api and api.ApplyIcon and api.ApplyIcon(icon,data)) then
                            icon:SetTexture(native); icon:SetTexCoord(unpack(dropdownIconCrop))
                        end
                    end
                end
                row.sound:ClearAllPoints(); row.sound:SetPoint('TOPLEFT',wide and nameWidth+whenWidth+16 or nameWidth+8,wide and -8 or -44); row.sound:SetWidth(wide and contentWidth-12 or whenWidth-12); row.sound:SetHeight(32)
                row.soundKind:ClearAllPoints(); row.soundKind:SetPoint('TOPLEFT',nameWidth+whenWidth+16,-44); row.soundKind:SetWidth(contentWidth-12); row.soundKind:SetShown(false)
                row.soundKind:SetText(T((item.rule.sound.kind=='eventWindow' or item.rule.sound.kind=='boneShield') and 'presetTag' or item.rule.sound.kind=='forecast' and 'forecastTag' or item.rule.sound.kind=='voice' and 'voiceEntry' or item.rule.sound.kind))
                row.when:SetText(item.when); row.sound:SetText(item.content); row.toggle:SetValue(item.rule.enabled,true); row:Show()
            else row:Hide() end
        end
        empty:SetShown(#rows==0)
    end
    function view:Refresh()
        local sound=YUI.Sound; local prefs=sound:GetPreferences(); if not prefs then return end
        local database=YUI.DB:GetAceDB(sound.storageProductId)
        local profileName=database and database:GetCurrentProfile()
        if self.profileName and (self.database~=database or self.profileName~=profileName) then
            if Center.editor then Center.editor:Hide() end
            if Center.legacyPanel then Center.legacyPanel:Hide() end
            if GUI.VoicePicker.dialog then GUI.VoicePicker.dialog:Hide() end
            self.undo=nil; undo:Hide()
        end
        self.database,self.profileName=database,profileName
        master:SetValue(prefs.enabled,true)
        local selected=sound.voicePacks[prefs.voicePackId]
        local pending = 0
        for _, provider in pairs(sound.LegacyMigration and sound.LegacyMigration.providers or {}) do
            if provider.GetRecoveryCount then pending = pending + provider:GetRecoveryCount() end
        end
        legacy:SetShown(pending > 0)
        local pr,pg,pb=GUI:GetColor(selected and 'color.badge.green' or 'color.badge.orange')
        local packHex=string.format('%02x%02x%02x',math.floor(pr*255),math.floor(pg*255),math.floor(pb*255))
        packLabel:SetText(T('pack')..' · |cff'..packHex..(selected and (selected.names[YUI.Locale:Current()] or selected.names.enUS) or T('missingPack'))..'|r')

        self:RefreshRows()
        local enabled=prefs.enabled~=false
        disabledText:SetShown(not enabled)
        for _,control in ipairs({pack,packLabel,share}) do control:SetShown(enabled) end
        legacy:SetShown(enabled and pending>0)
        if not enabled then
            if self.preferences then self.preferences:Hide(); main:Show() end
            if Center.editor then Center.editor:Hide() end
            self.status:Hide(); undo:Hide()
        else self.status:Show(); undo:SetShown(self.undo~=nil) end
        local categoryEnabled=enabled
        mainScroll:SetShown(categoryEnabled)
        for _,control in ipairs({search,add,spec,list}) do control:SetShown(categoryEnabled) end
        for key,header in pairs(headers) do header:SetShown(categoryEnabled and (key~='content' or self:GetWidth()-18>600)) end
        if self.preferences and self.preferences:IsShown() then self.preferences:Refresh() end
    end
    function view:RequestRefresh()
        if YUI.Monitor then
            YUI.Monitor:ScheduleTask(self,'sound-ui-refresh',GetTime()+0.05,self.Refresh)
        else self:Refresh() end
    end
    function view:OnSoundContextChanged()
        self:RequestRefresh()
        if Center.editor and Center.editor:IsShown() and Center.editor.edit then Center.editor:Refresh() end
    end
    function view:RefreshSpecIcons()
        Center:RefreshSpecDropdown(spec)
        self.paintedRows=nil
        self:PaintRows()
    end
    function view:OnIconScopeChanged(_,scope)
        if not scope or scope=='settings' then self:RefreshSpecIcons() end
    end
    function view:OnCVarChanged(_,name)
        if name=='cooldownViewerEnabled' then self:RequestRefresh() end
    end
    view:SetScript('OnSizeChanged',function() if view.Refresh then view:Refresh() end end)
    view:SetScript('OnShow',function()
        Center:ActivateView(view, view == (Center.designerWindow and Center.designerWindow.view) and Center.designerWindow or Settings.Elements.frame)
        local sources=YUI.Monitor and YUI.Monitor.CommonSources
        if sources and sources.RefreshNativeAuraBindings then sources:RefreshNativeAuraBindings() end
        YUI.Event:OffOwner(view)
        for _,event in ipairs({'YUI_SOUND_RULES_CHANGED','YUI_SOUND_PREFERENCES_CHANGED','YUI_SOUND_PACKS_CHANGED','YUI_SOUND_ENTRIES_CHANGED','YUI_SOUND_BINDING_STATUS_CHANGED','GET_ITEM_INFO_RECEIVED','YUI_MONITOR_SOURCE_STATUS_CHANGED'}) do
            YUI.Event:On(event,'RequestRefresh',view,{moduleId='sound.settings'})
        end
        YUI.Event:On('YUI_SOUND_CONTEXT_CHANGED','OnSoundContextChanged',view,{moduleId='sound.settings'})
        YUI.Event:On('YUI_APPEARANCE_ICON_SET_CHANGED','RefreshSpecIcons',view,{moduleId='sound.settings'})
        YUI.Event:On('YUI_APPEARANCE_ICON_SCOPE_CHANGED','OnIconScopeChanged',view,{moduleId='sound.settings'})
        YUI.Event:On('CVAR_UPDATE','OnCVarChanged',view,{moduleId='sound.settings'})
        view:Refresh()
    end)
    view:SetScript('OnHide',function()
        Center:CloseSpecDropdown(spec)
        YUI.Event:OffOwner(view); if YUI.Monitor then YUI.Monitor:CancelTasks(view) end; YUI.Sound:StopPreview(); search:ClearFocus()
        if Center.view==view then Center:CloseChildren() end
        if Center.editor then Center.editor:Hide() end
        if GUI.VoicePicker.dialog then GUI.VoicePicker.dialog:Hide() end
    end)
    view:Hide(); return view
end

function Center:Render(parent)
    Settings:RenderConfig(parent,{{type='custom',render=function()
    local viewport=Settings.Elements.scrollFrame
    local view=parent.yuiSoundCenter or self:Create(parent,math.max(320,parent:GetWidth()-40),400)
    self:CloseDesignerWindow()
    -- ClearConfig detaches cached custom views when changing settings pages.
    view:SetParent(parent)
    if view.preferences then view.preferences:Hide() end
    view.main:Show()
    self:ActivateView(view, Settings.Elements.frame)
    parent.yuiSoundCenter=view; view.container=parent
    local function layout()
        if parent.soundLayoutActive then return end
        parent.soundLayoutActive=true
        local height=viewport and viewport:GetHeight() or 500
        parent:SetHeight(height)
        view:SetSize(math.max(320,parent:GetWidth()-40),math.max(1,height-28))
        view:ClearAllPoints(); view:SetPoint('TOPLEFT',20,-20)
        if Settings.RefreshCurrentModuleScroll then Settings:RefreshCurrentModuleScroll(false) end
        parent.soundLayoutActive=nil
    end
    if not parent.soundSizeHook and parent.HookScript then
        parent.soundSizeHook=true
        parent:HookScript('OnSizeChanged',function() if view:IsShown() then layout() end end)
        if viewport then viewport:HookScript('OnSizeChanged',function() if view:IsShown() then layout() end end) end
    end
    layout(); view:Show(); view:Refresh()
    return view:GetWidth(),math.max(1,view:GetHeight()-27)
    end}})
end
