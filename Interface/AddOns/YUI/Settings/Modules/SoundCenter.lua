local YUI = _G.YUI
local Settings, GUI = YUI and YUI.Settings, YUI and YUI.GUI2
if not (Settings and GUI) or Settings.SoundCenter then return end
local Center = {}
Settings.SoundCenter = Center
local Form = GUI.Form
local dropdownIconCrop = {0.08, 0.92, 0.08, 0.92}
local foreverTextKeys={applicableSpecs='applicableClasses',allSpecs='allClasses',unlimited='allClasses',exportSpecCount='exportClassCount',
    loadSummary='classLoadSummary',loadSpecs='applicableClasses',manualKnown='classManualKnown',customIDNote='classCustomIDNote',conflictingReminder='classConflictingReminder'}
local function T(key) return YUI.Locale:Get('Core')['sound.center.'..(YUI.IsForever and foreverTextKeys[key] or key)] end
Center.Text = T
function Center:SelectionKey(key)
    local f=YUI.IsForever and YUI.Sound.ForeverCatalog
    return f and f:ClassKey(key) or key
end
function Center:SelectionGroups()
    local f=YUI.IsForever and YUI.Sound.ForeverCatalog
    return f and f:SelectionGroups(Settings) or Settings:GetSpecSelectionGroups({})
end
function Center:ScopeIncludes(rule,key,fallback)
    local f=YUI.IsForever and YUI.Sound.ForeverCatalog
    if f then return f:IncludesClass(rule,key) end
    return fallback
end
function Center:ExpandSelection(values)
    local f=YUI.IsForever and YUI.Sound.ForeverCatalog
    local keys={}
    for key,enabled in pairs(values) do
        if enabled then
            if f then for _,spec in ipairs(f:ClassSpecs(key)) do keys[#keys+1]=spec end
            else keys[#keys+1]=key end
        end
    end
    table.sort(keys);return keys
end
function Center:ReviewTransfer(prepared, accept, cancel, owner, profileName)
    local labels, lines = YUI.Locale:Get('Core'), {}
    if profileName then lines[#lines+1]=string.format(labels['sound.share.profile_target'],profileName) end
    for _, entry in ipairs(prepared.entries) do
        local snapshot=entry.snapshot
        if entry.id=='core.sound.legacy' then
            lines[#lines+1]=string.format(labels['sound.share.legacy_counts'],snapshot.converted,snapshot.pending,snapshot.unchanged)
            lines[#lines+1]=labels['sound.share.legacy_recovery']
        elseif entry.id=='product.yhud.selection' and YUI.YHUD and YUI.YHUD.Sharing
            and YUI.YHUD.Sharing.AppendGraphicalPreviewLines then
            YUI.YHUD.Sharing:AppendGraphicalPreviewLines(lines,snapshot)
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
function Center:ErrorText(code,detail,fallback)
    if code=='special-voice-inactive' then return T('specialVoiceInactive') end
    if code=='special-voice-unavailable' then return T('specialVoiceUnavailable') end
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
    return T(keys[code] or fallback or 'invalid')
end
function Center:RuntimeIssueText(code,binding)
    if code=='native-aura-binding-unavailable' and YUI.IsForever then
        local params=binding and binding.handle and binding.handle.source and binding.handle.source.params
        local api=YUI.API and YUI.API.Spell
        if params and params.nativeSelfAura and params.nativeBase and api and api.GetKnownState then
            local known=api.GetKnownState(params.nativeBase)
            if not (issecretvalue and issecretvalue(known)) and known==false then return T('spellUnavailable') end
        end
    end
    local keys={['spell-not-known']='spellUnavailable',['spell-cast-unavailable']='castUnavailable',['spell-known-unknown']='spellAvailabilityUnknown',
        ['spell-identity-changed']='spellIdentityPending',['unsupported-condition']='conditionUnavailable',
        ['native-charge-unavailable']='nativeChargeUnavailable'}
    if keys[code] then return T(keys[code]) end
    return self:ErrorText(code,nil,'monitorUnavailable')
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
function Center:SoundContent(selection,packId)
    local sound,help,seen=YUI.Sound,{},{}
    local function VoiceLabel(value)
        local label=sound:GetEntryLabel(value)
        local origin=sound:ParseSpecialVoice(value)
        if not origin or (packId and sound:HasVoiceRecording(value,packId)
            or not packId and sound:IsVoicePackEnabled(origin) and sound:HasVoiceRecording(value,origin)) then return label end
        local state=sound:GetVoicePackState(origin)
        local status,key='specialVoiceUnavailable','specialVoiceUnavailableHelp'
        if state=='not-installed' then status,key='specialVoiceNotInstalled','specialVoiceNotInstalledHelp'
        elseif state=='disabled' or sound:HasVoiceRecording(value,origin) then status,key='specialVoiceInactive','specialVoiceMutedHelp'
        elseif state=='not-loaded' then key='packReloadHelp'
        elseif state=='not-registered' then key='packRegistrationHelp'
        elseif state~='ready' then key='packUnavailableHelp'
        else
            local pack=sound:GetVoicePack(origin)
            local client=YUI.IsForever and 'forever' or YUI.IsRetail and 'mainline' or YUI.IsWrath and 'wrath' or 'mists'
            if pack.clients and not pack.clients[client] then key='unsupportedVersion' end
        end
        local identity=origin..':'..key
        if not seen[identity] then
            seen[identity]=true
            help[#help+1]=string.format(T('specialVoicePack'),sound:GetVoicePackLabel(origin))..'\n'..T(key)
        end
        local r,g,b=GUI:GetColor('color.state.warning')
        return string.format('|cff%02x%02x%02x%s|r',math.floor(r*255),math.floor(g*255),math.floor(b*255),T(status))
    end
    local content=sound.EditorModel:SoundLabel(selection,VoiceLabel)
    return content,#help>0 and table.concat(help,'\n\n') or nil
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
            if issue then return self:RuntimeIssueText(issue,binding) end
            if binding.nativeAuraUnit then
                if not binding.directAuraRegistered then return T('auraRegistrationScheduled') end
                if rule.object.unit=='received' then return T('receivedBuffRegistered') end
            end
            local typeID=source and source.sourceType and source.sourceType.id
            if state and not issue and (typeID=='native-aura-signal' or typeID=='native-equipment-aura') then
                return T('nativeAuraBound')
            end
        end
    end
    return T('nativeAuraUnavailable')
end
function Center:ToolboxNotice(rule)
    local toolbox=YUI.ClassExtraMonitor
    local detail=toolbox and toolbox.GetSoundNotice and toolbox:GetSoundNotice(rule)
    if not detail then return end
    local spec=detail.kind=='devourer-transform' and 'DEMONHUNTER:1480' or 'DEATHKNIGHT:250'
    local applies=not rule.specs
    for _,key in ipairs(rule.specs or {}) do if key==spec or key==spec:match('^(.-):') then applies=true end end
    for _,key in ipairs(rule.exceptSpecs or {}) do if key==spec or key==spec:match('^(.-):') then applies=false end end
    if not applies then return end
    local segment
    if detail.kind=='devourer-transform' then segment=string.format(T('toolboxDevourer'),detail.seconds)
    else
        local parts={}
        if detail.manual then parts[#parts+1]=T('toolboxManual') end
        if detail.ending then parts[#parts+1]=T('toolboxEnding') end
        segment=table.concat(parts,' / ')
    end
    local prefs=YUI.Sound:GetPreferences()
    local overlaps=detail.overlaps and rule.enabled~=false and prefs.enabled~=false
    return T(overlaps and 'toolboxOverlap' or 'toolboxConfigured'),overlaps and 'warning' or 'info',
        string.format(T('toolboxHelp'),segment)
end

function Center:RuleNotice(rule)
    if rule.object.kind=='event' then
        local definitions=YUI.Sound.EventDefinitions
        local available,reason=definitions:Availability(rule.object.id)
        if not available then return definitions:Text(reason),'warning' end
        local events=YUI.Sound.Runtime and YUI.Sound.Runtime.events
        local binding=events and events.bindings[rule.object.id]
        if binding and binding.playbackIssue then return self:RuntimeIssueText(binding.playbackIssue),'warning' end
        if reason=='limited' then return definitions:Text('limited.'..rule.object.id),'info' end
        return nil
    end
    local engine=YUI.Sound.Runtime and YUI.Sound.Runtime.engine
    local function MatchesBinding(binding)
        if rule.object.unit=='received' or binding.rule.object.unit=='received' then
            return YUI.Sound.RuleModel:Key(binding.rule)==YUI.Sound.RuleModel:Key(rule)
        end
        return binding.rule.object.id==rule.object.id and binding.rule.trigger.event==rule.trigger.event
    end
    for _,issue in ipairs(engine and engine.issues or {}) do
        if issue.key==YUI.Sound.RuleModel:Key(rule) then return self:RuntimeIssueText(issue.reason),'warning' end
    end
    if YUI.Sound.RuleStore:HasFamilyNotice(rule) then return T('familyDuplicateNotice'),'warning','duplicate' end
    if rule.sound.kind=='forecast' then
        local ids={'VC-6b86b273','VC-d4735e3a','VC-4e074085','VC-4b227777','VC-ef2d127d','VC-e7f6c011','VC-7902699b','VC-2c624232','VC-19581e27','VC-4a44dc15'}
        local client=YUI.IsForever and 'forever' or YUI.IsRetail and 'mainline' or YUI.IsWrath and 'wrath' or 'mists'
        for i=1,rule.sound.countdown do
            local entry=YUI.Sound.entries[ids[i]]
            if entry and not entry.clients[client] then return T('unsupportedVersion') end
        end
    end
    for _,binding in ipairs(engine and engine.bindings or {}) do
        if MatchesBinding(binding) then
            if binding.playbackIssue then return self:RuntimeIssueText(binding.playbackIssue,binding) end
            if binding.auraPlaybackIssue then return self:RuntimeIssueText(binding.auraPlaybackIssue,binding),'warning' end
            if (rule.trigger.extension=='boiling-point' or rule.trigger.extension=='bone-shield') and binding.issue then return self:RuntimeIssueText(binding.issue,binding),'warning' end
            local state=binding.handle and binding.handle.source and binding.handle.source.state
            if state and state.stackIssue and rule.trigger.extension=='bone-shield' and rule.sound.introKind~='none' then return T('boneShieldCDM'),'warning' end
            if state and (state.issue=='native-aura-binding-unavailable' or state.issue=='native-aura-viewer-hidden') then
                return self:RuntimeIssueText(state.issue,binding),'warning'
            end
            for _,key in ipairs({'cooldownStateSecret','chargeStateSecret'}) do
                local value=state and state[key]
                if not (issecretvalue and issecretvalue(value)) and value==true then return T('cooldownRestricted') end
            end
        end
    end
    if rule.object.kind=='aura' then
        for _,binding in ipairs(engine and engine.bindings or {}) do
            if MatchesBinding(binding) and binding.fallbackRequired then
                if not binding.directAuraID and not (rule.object.unit=='received' and binding.directAuraRegistered) then
                    return T('auraFileRequired'),'warning'
                end
            end
        end
    end
    if rule.trigger.event~='charge' then return nil end
    if YUI.IsRetail~=true and YUI.IsForever~=true then return T('nativeChargeUnavailable') end
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
    for _, panel in pairs({self.editor, self.exportDialog, self.legacyPanel, self.presetDialog, GUI.VoicePicker and GUI.VoicePicker.dialog}) do
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
    for _, panel in pairs({self.editor, self.exportDialog, self.legacyPanel, self.presetDialog}) do
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
    local frames={GUI.VoicePicker and GUI.VoicePicker.dialog or false, Settings.reviewPanel or false, specPanel or false, self.editor or false, self.exportDialog or false, self.legacyPanel or false, self.presetDialog or false, Settings.ConfigTransferDialog or false}
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
            local restoreView=Center.modalHost==host and Center.view==host.view
            Center:CloseChildren()
            if host.view then host.view:Hide() end
            if host.database and host.database.UnregisterAllCallbacks then host.database.UnregisterAllCallbacks(host) end
            host.database=nil
            if YUI.Event then YUI.Event:OffOwner(host) end
            if Center.modalHost==host then Center.modalHost=nil; Center.view=nil end
            local returnView=host.returnView
            host.returnView=nil
            -- Restore the explicit Hide performed when opening the separate window.
            -- A detached view is restored by Render after ClearConfig has finished.
            if restoreView and returnView and returnView:GetParent() then returnView:Show() end
        end)
    end
    local width=math.min(1040,UIParent:GetWidth()-48)
    local height=math.min(700,UIParent:GetHeight()-64)
    host:SetSize(width,height)
    if self.view and self.view~=host.view then host.returnView=self.view; self.view:Hide() end
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
    if YUI.IsForever then return spec.classInfo.icon or spec.icon end
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
    if category=='unified' and (YUI.IsRetail or YUI.IsForever) then options[#options+1]={text=T('events'),value='events',icon=134400,texCoord=dropdownIconCrop} end
    if category=='unified' then options[#options+1]={text=T('general'),value='general',icon=132996,texCoord=dropdownIconCrop} end
    for _,group in ipairs(self:SelectionGroups()) do
        for _,spec in ipairs(group.specs or {}) do
            local name=YUI.IsForever and spec.classInfo.name or spec.classInfo.name..' · '..spec.displayName
            local color=RAID_CLASS_COLORS and RAID_CLASS_COLORS[spec.classInfo.token]
            if color then name=string.format('|cff%02x%02x%02x%s|r',math.floor(color.r*255),math.floor(color.g*255),math.floor(color.b*255),name) end
            local native,iconData=SpecIcon(spec)
            options[#options+1]={text=name,
                specID=spec.specID,classFile=spec.classInfo.token,value=YUI.IsForever and spec.key or spec.classInfo.token..':'..spec.specID,
                icon=native,iconData=iconData,texCoord=YUI.IsForever and spec.classInfo.iconTexCoord or not iconData and dropdownIconCrop or nil}
        end
    end
    if category then
        local rules=YUI.Sound.RuleStore:Read() or {}
        for index,option in ipairs(options) do
            local count=0
            for _,rule in ipairs(rules) do
                local applies=option.value=='all' or not rule.specs
                if rule.specs then
                    for _,key in ipairs(rule.specs) do if key==option.value then applies=true end end
                else
                    for _,key in ipairs(rule.exceptSpecs or {}) do if key==option.value then applies=false end end
                end
                applies=self:ScopeIncludes(rule,option.value,applies)
                if category=='unified' and (option.value=='all' or option.value=='events' and rule.object and rule.object.kind=='event' or option.value=='general' and rule.category=='general' or option.value~='general' and option.value~='events' and rule.category=='class' and applies) or rule.category==category and applies then count=count+1 end
            end
            option.reminderCount,option.listOrder=count,index
            if count>0 then
                local r,g,b=GUI:GetColor('color.badge.green')
                local color=string.format('|cff%02x%02x%02x',math.floor(r*255),math.floor(g*255),math.floor(b*255))
                option.text=string.format(T('categoryCount'),option.text..color,count)..'|r'
            end
        end
        table.sort(options,function(a,b)
            if (a.reminderCount>0)~=(b.reminderCount>0) then return a.reminderCount>0 end
            return a.listOrder<b.listOrder
        end)
    end
    return options
end
function Center:PickerOptions(kind)
    if kind=='event' then
        local definitions=YUI.Sound.EventDefinitions
        local options={{text=T('events'),value='events'}}
        for _,group in ipairs(definitions.groups) do options[#options+1]={text=definitions:Text('group.'..group),value='events:'..group} end
        return options
    end
    local options=self:SpecOptions()
    options[1].text=T('allObjects')
    table.insert(options,2,{text=T('general'),value='general',icon=132996,texCoord=dropdownIconCrop})
    if (kind=='spell' or kind=='aura') and (YUI.IsRetail or YUI.IsForever) then
        table.insert(options,3,{text=T('racial'),value='racial',icon=136225,texCoord=dropdownIconCrop})
        if kind=='aura' then table.insert(options,4,{text=T('buffs'),value='buffs',icon=135939,texCoord=dropdownIconCrop}) end
    end
    local current=self:SelectionKey(Settings:GetCurrentSpecSelectionKey())
    local currentClass=type(current)=='string' and current:match('^([^:]+):')
    if currentClass then
        local first,remaining={},{}
        for _,option in ipairs(options) do
            local target=(option.value=='all' or option.value=='general' or option.value=='racial' or option.value=='buffs'
                or option.classFile==currentClass) and first or remaining
            target[#target+1]=option
        end
        for _,option in ipairs(remaining) do first[#first+1]=option end
        options=first
    end
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
        frame.specPicker=Settings:CreateSpecMultiSelectDropdown(frame,{owner=frame,groups=function() return Center:SelectionGroups() end,width=540,height=34,panelWidth=500,panelHeight=280,
            label=T('applicableSpecs'),defaultSelected=false,value=frame.values,
            selectAllText=labels['settings.config_transfer.select_all'],clearText=labels['settings.config_transfer.clear_all'],
            armorLabels={cloth=labels['settings.config_sets.armor.cloth'],leather=labels['settings.config_sets.armor.leather'],mail=labels['settings.config_sets.armor.mail'],plate=labels['settings.config_sets.armor.plate']},
            summaryFormatter=function()
                local count,total=0,0
                for _,group in ipairs(Center:SelectionGroups()) do
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
            local specs=Center:ExpandSelection(self.values)
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
    for _,group in ipairs(Center:SelectionGroups()) do
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
    local cardHeight,cardGap=104,12
    panel.packTitle=packTitle
    panel.dropMarker=GUI:CreatePanel(body,{width=3,height=cardHeight,surface='color.border.accent',border=false})
    panel.dropMarker:EnableMouse(false);panel.dropMarker:Hide()
    local packStateKeys={['not-installed']='packNotInstalled',disabled='packDisabled',
        ['not-loaded']='packNotLoaded',['not-registered']='packNotRegistered',unavailable='packUnavailable'}
    local packStateHelpKeys={['not-installed']='packInstallHelp',disabled='packEnableHelp',
        ['not-loaded']='packReloadHelp',['not-registered']='packRegistrationHelp',unavailable='packUnavailableHelp'}
    local function AddPackStatus(tip,card)
        if card.packState=='ready' then
            if not card.isFallback then tip:AddLine(card.statusText) end
        else
            tip:AddLine(card.tooltipStatus)
            tip:AddLine(T(card.rank and 'packSelectedSkipped' or 'packInactive'),'action')
            tip:AddLine(T(packStateHelpKeys[card.packState] or 'packUnavailableHelp'),'action')
        end
    end
    local previewFloatLimit=12
    local function ReleasePreviewFloat(handle)
        local frame=handle.target
        frame.previewHandle=nil;frame.label:SetText('');frame:Hide()
    end
    local function ClearCardPreview(card)
        if YUI.Animation and card.previewOwner then YUI.Animation:StopOwner(card.previewOwner) end
        for _,frame in ipairs(card.previewFloats or {}) do
            frame.previewHandle=nil;frame.label:SetText('');frame:Hide()
        end
    end
    local function UpdateDragPreview(preview)
        local x,y=GetCursorPosition()
        local scale=UIParent:GetEffectiveScale()
        if scale<=0 then return end
        preview:ClearAllPoints()
        preview:SetPoint('CENTER',UIParent,'BOTTOMLEFT',x/scale,y/scale)
    end
    function panel:ShowDragPreview(card)
        local preview=self.dragPreview
        if not preview then
            preview=GUI:CreatePanel(UIParent,{width=32,height=32,surface='color.surface.popup',border='color.border.accent'})
            preview:EnableMouse(false);preview:SetFrameStrata('TOOLTIP');preview:SetFrameLevel(100)
            preview.icon=GUI:CreateIcon(preview,{width=30,height=30})
            preview.icon:SetPoint('CENTER');self.dragPreview=preview
        end
        preview.icon:SetTexture(card.icon.icon:GetTexture())
        preview.icon:SetTexCoord(0,1,0,1)
        UpdateDragPreview(preview);preview:Show()
        preview:SetScript('OnUpdate',UpdateDragPreview)
    end
    function panel:EndDrag()
        self.draggedPack=nil;self.dragRank=nil;self.dropRank=nil;self.dropCard=nil
        if self.dragPreview then self.dragPreview:SetScript('OnUpdate',nil);self.dragPreview:Hide() end
        self.dropMarker:Hide();packTitle:SetText(T('pack'))
        for _,card in ipairs(self.packCards) do card:SetAlpha(1) end
    end
    function panel:ShowDropTarget(card)
        if not self.draggedPack then return end
        local last=#YUI.Sound:GetEnabledVoicePacks()
        self.dropRank=math.max(1,math.min(card.rank or last,last));self.dropCard=card
        local target,after=card,not card.rank or card.rank>self.dragRank
        if not card.rank then
            for _,candidate in ipairs(self.packCards) do if candidate.rank==last then target=candidate;break end end
        end
        self.dropMarker:ClearAllPoints()
        local point=after and 'TOPRIGHT' or 'TOPLEFT'
        self.dropMarker:SetPoint(point,target,point,0,0)
        self.dropMarker:SetFrameLevel(target:GetFrameLevel()+5);self.dropMarker:Show()
        packTitle:SetText(string.format(T('packDropHint'),self.dropRank))
    end
    function panel:LeaveDropTarget(card)
        if self.draggedPack and self.dropCard==card then
            self.dropRank=nil;self.dropCard=nil;self.dropMarker:Hide();packTitle:SetText(T('packDragging'))
        end
    end
    function panel:ClearPreviewFloats()
        self:EndDrag();self.suppressAudition=nil
        for _,card in ipairs(self.packCards) do ClearCardPreview(card);card:SetAlpha(1) end
    end
    function panel:FloatPreview(card,id)
        local animation=YUI.Animation
        if not id or not self:IsShown() or not card:IsShown() or not animation then return end
        card.previewFloats=card.previewFloats or {}
        card.previewOwner=card.previewOwner or {}
        card.previewFloatIndex=(card.previewFloatIndex or 0)%previewFloatLimit+1
        local frame=card.previewFloats[card.previewFloatIndex]
        if not frame then
            frame=GUI:CreateFrame(card,{height=22})
            frame:SetFrameLevel(card:GetFrameLevel()+5);frame:EnableMouse(false)
            frame.label=Text(frame,'','font.size.md','color.text.accent')
            frame.label:SetAllPoints(frame);frame.label:SetWordWrap(false)
            card.previewFloats[card.previewFloatIndex]=frame
        end
        if frame.previewHandle then frame.previewHandle:Stop() end
        frame.label:SetText(YUI.Sound:GetEntryLabel(id))
        local width=math.min(card:GetWidth()-32,frame.label:GetStringWidth()+8)
        frame:SetWidth(width);frame:ClearAllPoints()
        frame:SetPoint('BOTTOMLEFT',card,'BOTTOMLEFT',math.random(16,math.max(16,math.floor(card:GetWidth()-width-16))),math.random(8,20))
        frame:SetAlpha(1);frame:Show()
        -- Reuse the shared tween driver; repeated native groups would accumulate on these pooled frames.
        frame.previewHandle=animation:FloatText(frame,{owner=card.previewOwner,driver='tween',duration=1.1,
            distance=54,toX=math.random(-12,12),onFinished=ReleasePreviewFloat})
        if frame.previewHandle.noop or frame.previewHandle._completed then ReleasePreviewFloat(frame.previewHandle) end
    end
    local function ShowPackTooltip(card)
        if panel.draggedPack then panel:ShowDropTarget(card);return end
        GUI.Tooltip:Show(card,{title=YUI.Sound:GetVoicePackLabel(card.packId),content=function(tip)
            tip:AddLine(card.metadata:GetText())
            local description=card.description:GetText()
            if description~='' then tip:AddSpace();tip:AddLine(description,'action') end
            tip:AddSpace()
            if card.tooltipCount then tip:AddLine(card.tooltipCount);tip:AddSpace() end
            AddPackStatus(tip,card)
            if card.rank then tip:AddLine(T('packDragHint'),'action') end
        end,actions=YUI.Sound:GetVoicePack(card.packId) and {{text=T('randomPreview')}} or nil})
    end
    local function HidePackTooltip(card) GUI.Tooltip:Hide(card);panel:LeaveDropTarget(card) end
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
        local ok,code,id=YUI.Sound:PreviewRandomEntry()
        if ok then
            for _,card in ipairs(panel.packCards) do
                if card.packId==YUI.Sound:GetPreferences().voicePackId then panel:FloatPreview(card,id);break end
            end
        end
        if not ok and code then Center:Message(code) end
    end})
    panel.randomPreview=randomPreview
    sections.missingVoice.title:Hide()
    panel.fallback=Form:CreateCheckbox(sections.missingVoice,{text=T('packMissingTTS'),
        get=Pref('fallbackTTS'),set=function(v) SetPreference('fallbackTTS',v) end})
    panel.fallback:SetPoint('TOPLEFT',0,-16)
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
    local function Place(box,x,y,width)
        box:ClearAllPoints(); box:SetPoint('TOPLEFT',x,-y); box:SetWidth(width)
        box.label:SetWidth(width); box.control:SetWidth(width)
        if box.control.slider and box.control.inputBox then
            box.control.slider:ClearAllPoints(); box.control.slider:SetPoint('LEFT',box.control,'LEFT',0,0)
            box.control.slider:SetWidth(width-66)
            box.control.inputBox:ClearAllPoints(); box.control.inputBox:SetPoint('RIGHT',box.control,'RIGHT',0,0)
        end
    end
    function panel:SaveOrder(order)
        local ok=SetPreference('voicePackOrder',order)
        if ok then self:Refresh();view:RefreshRows() end
        return ok
    end
    function panel:MovePack(id,target)
        if not YUI.Sound:IsVoicePackEnabled(id) then return end
        local order={}
        for _,packId in ipairs(YUI.Sound:GetEnabledVoicePacks()) do if packId~=id then order[#order+1]=packId end end
        table.insert(order,math.max(1,math.min(#order+1,target)),id)
        return self:SaveOrder(order)
    end
    function panel:TogglePack(id,enabled)
        if id=='yui.default' then return end
        local order={}
        local fallbackRank
        for _,packId in ipairs(YUI.Sound:GetEnabledVoicePacks()) do
            if packId~=id then
                order[#order+1]=packId
                if packId=='yui.default' then fallbackRank=#order end
            end
        end
        if enabled then table.insert(order,fallbackRank or #order+1,id) end
        return self:SaveOrder(order)
    end
    function panel:Refresh()
        if self.draggedPack then self:EndDrag() end
        local sound,prefs=YUI.Sound,YUI.Sound:GetPreferences()
        if not prefs then return end
        local width=math.max(300,view:GetWidth()-28); body:SetWidth(width)
        local columns=width>=540 and 3 or width>=360 and 2 or 1
        local cell=(width-(columns-1)*12)/columns
        local fieldColumns=width>600 and 2 or 1
        local fieldWidth=(width-(fieldColumns-1)*16)/fieldColumns
        local ranks={}
        for rank,id in ipairs(sound:GetEnabledVoicePacks(prefs)) do ranks[id]=rank end
        local packs,seen={},{}
        local function AddPack(id,listOrder)
            id=sound:GetVoicePackId(id)
            if seen[id] then return end
            packs[#packs+1]={id=id,pack=sound:GetVoicePack(id),info=sound:GetVoicePackInfo(id),listOrder=listOrder or math.huge}
            seen[id]=true
        end
        for id,info in pairs(sound:GetRecommendedVoicePacks()) do
            AddPack(id,info.listOrder)
        end
        for id in pairs(sound.voicePacks) do AddPack(id) end
        for id in pairs(sound.voicePackMetadata or {}) do AddPack(id) end
        for id in pairs(ranks) do AddPack(id) end
        table.sort(packs,function(a,b)
            if ranks[a.id] or ranks[b.id] then return (ranks[a.id] or math.huge)<(ranks[b.id] or math.huge) end
            if (a.pack~=nil)~=(b.pack~=nil) then return a.pack~=nil end
            if a.listOrder~=b.listOrder then return a.listOrder<b.listOrder end
            return a.id<b.id
        end)
        local standardEntries=sound:GetEntries()
        for i,entry in ipairs(packs) do
            local card=self.packCards[i]
            if not card then
                card=Form:CreateButton(body,{height=cardHeight,text='',tone='default',onClick=function(button)
                    local sound=YUI.Sound
                    if panel.suppressAudition or button.suppressClick or not sound:GetVoicePack(button.packId) then return end
                    local ok,code,id=sound:PreviewRandomEntry(button.packId)
                    if ok then panel:FloatPreview(button,id) end
                    if not ok and code then Center:Message(code) end
                end})

                card.icon=GUI.VoicePicker:CreatePackIcon(card,40);card.icon:SetPoint('TOPLEFT',12,-12)
                card.priority=Text(card.icon,'','font.size.md','color.text.accent');card.priority:SetPoint('CENTER',card.icon,'BOTTOM',0,0)
                card.priority:SetJustifyH('CENTER');card.priority:SetSize(40,18)
                GUI:ApplyFontAppearance(card.priority,{outline='outlineShadow',size=GUI.Fonts.size_md or 14})
                card.unavailableMark=Text(card.icon,'!','font.size.md','color.badge.orange')
                card.unavailableMark:SetPoint('TOPRIGHT',2,2);card.unavailableMark:SetSize(12,18)
                GUI:ApplyFontAppearance(card.unavailableMark,{outline='outlineShadow',size=GUI.Fonts.size_md or 14})
                card.title=Text(card,'','font.size.md'); card.title:SetPoint('TOPLEFT',62,-12);card.title:SetHeight(18);card.title:SetWordWrap(false)
                card.metadata=Text(card,'','font.size.md','color.text.primary');card.metadata:Hide()
                card.description=Text(card,'','font.size.md','color.text.primary');card.description:Hide()
                card.count=Text(card,'','font.size.md','color.text.primary'); card.count:SetPoint('TOPLEFT',62,-35);card.count:SetHeight(18);card.count:SetWordWrap(false)
                card.status=Text(card,'','font.size.sm','color.badge.orange');card.status:SetPoint('TOPLEFT',62,-54);card.status:SetHeight(16)
                card.toggle=Form:CreateSwitch(card,{variant='compact',set=function(value) panel:TogglePack(card.packId,value) end})
                card.toggle:SetPoint('BOTTOMRIGHT',-12,12)
                card.fallbackLabel=Text(card,T('packFallback'),'font.size.sm','color.text.primary')
                card.fallbackLabel:SetPoint('BOTTOMRIGHT',-12,12);card.fallbackLabel:SetHeight(18)
                card.toggle:HookScript('OnEnter',function(owner)
                    if panel.draggedPack then panel:ShowDropTarget(card);return end
                    GUI.Tooltip:Show(owner,{title=sound:GetVoicePackLabel(card.packId),content=function(tip) AddPackStatus(tip,card) end})
                end)
                card.toggle:HookScript('OnLeave',function(owner) GUI.Tooltip:Hide(owner);panel:LeaveDropTarget(card) end)
                card.toggle:HookScript('OnHide',function(owner) GUI.Tooltip:Hide(owner) end)
                card.sortButtons={}
                for n,delta in ipairs({-1,1}) do
                    local arrow=Form:CreateTextLink(card,{width=20,height=20,text=delta<0 and '‹' or '›',colorKey='color.text.secondary',
                        tooltip=T(delta<0 and 'packMoveEarlier' or 'packMoveLater'),onClick=function()
                            if card.rank then panel:MovePack(card.packId,card.rank+delta) end
                        end})
                    if arrow.underline then arrow.underline:Hide() end
                    arrow:SetPoint('BOTTOMLEFT',12+(n-1)*24,10)
                    arrow:HookScript('OnEnter',function(owner) if panel.draggedPack then GUI.Tooltip:Hide(owner);panel:ShowDropTarget(card) end end)
                    arrow:HookScript('OnLeave',function() panel:LeaveDropTarget(card) end)
                    card.sortButtons[n]=arrow
                end
                card:RegisterForDrag('LeftButton')
                card:HookScript('OnMouseDown',function() card.suppressClick=nil;panel.suppressAudition=nil end)
                card:SetScript('OnDragStart',function()
                    card.suppressClick=true;panel.suppressAudition=true
                    if not card.rank then return end
                    panel.draggedPack=card.packId;panel.dragRank=card.rank;card:SetAlpha(.45);GUI.Tooltip:Hide(card)
                    panel:ShowDragPreview(card)
                    panel:ShowDropTarget(card)
                end)
                card:SetScript('OnDragStop',function()
                    local id=panel.draggedPack
                    if not id then return end
                    local rank
                    for _,target in ipairs(panel.packCards) do
                        if target:IsShown() and target:IsMouseOver() then
                            panel:ShowDropTarget(target);rank=panel.dropRank;break
                        end
                    end
                    panel:EndDrag()
                    if rank then panel:MovePack(id,rank) end
                end)
                card:HookScript('OnEnter',ShowPackTooltip);card:HookScript('OnLeave',HidePackTooltip);card:HookScript('OnHide',HidePackTooltip)
                card:HookScript('OnHide',ClearCardPreview)
                card.download=Form:CreateButton(card,{height=26,width=86,text=T('downloadPack'),textLeftPadding=4,textRightPadding=4,onClick=function()
                    if card.downloadURL then Settings:ShowCopyPopup(T('downloadPack'),card.downloadURL) end
                end,tooltip=T('downloadPack')})
                card.download:SetPoint('BOTTOMRIGHT',-12,8)
                card.download:HookScript('OnEnter',function() panel:ShowDropTarget(card) end)
                card.download:HookScript('OnLeave',function() panel:LeaveDropTarget(card) end)
                self.packCards[i]=card
            end
            local recordings,specialRecordings=0,0
            if entry.pack then
                for _,voice in ipairs(standardEntries) do
                    if sound:HasVoiceRecording(voice.id,entry.id) then recordings=recordings+1 end
                end
                specialRecordings=#sound:GetSpecialEntries(entry.id)
            end
            GUI.Tooltip:Hide(card);GUI.Tooltip:Hide(card.toggle)
            if card.packId~=entry.id or not entry.pack then
                ClearCardPreview(card)
            end
            card.packId=entry.id;card.downloadURL=entry.info.downloadURL
            card.packState=sound.GetVoicePackState and sound:GetVoicePackState(entry.id)
                or entry.pack and 'ready' or 'unavailable'
            local canDownload=card.packState=='not-installed' and card.downloadURL~=nil
            card:SetWidth(cell); card:ClearAllPoints(); card:SetPoint('TOPLEFT',((i-1)%columns)*(cell+12),-38-math.floor((i-1)/columns)*(cardHeight+cardGap))
            local icon=sound:GetVoicePackIcon(entry.id)
            local builtinIcon=entry.info.builtinIcon and YUI.Assets and YUI.Assets:Component('Voice',entry.info.builtinIcon)
            if not icon then icon=entry.info.names and 136183 or 'Interface\\Icons\\INV_Misc_QuestionMark' end
            card.icon:SetIcon(icon or 136183)
            if builtinIcon or entry.info.icon or entry.info.addonIcon then card.icon.icon:SetTexCoord(0,1,0,1)
            else card.icon.icon:SetTexCoord(.08,.92,.08,.92) end
            card.rank=ranks[entry.id]
            card.isFallback=entry.id=='yui.default'
            card.priority:SetText(card.rank or '');card.priority:SetShown(card.rank~=nil)
            local name,author=sound:GetVoicePackLabel(entry.id),entry.info.author or T('unknownAuthor')
            card.title:SetWidth(cell-74); card.title:SetText(name)
            card.metadata:SetWidth(cell-70)
            local function Colored(value,key)
                local r,g,b=GUI:GetColor(key)
                return string.format('|cff%02x%02x%02x%s|r',math.floor(r*255),math.floor(g*255),math.floor(b*255),value)
            end
            card.metadata:SetText(string.format(T('packMetadata'),Colored(author,'color.text.primary'),Colored(entry.info.language=='zhCN' and T('mandarin') or entry.info.language or T('unknownLanguage'),'color.badge.green'))..(entry.info.version and ' · '..entry.info.version or ''))
            card.description:SetText(entry.info.descriptionKey and T(entry.info.descriptionKey) or entry.info.description or '')
            card.count:SetWidth(cell-74)
            local standardCount=Colored(recordings,'color.badge.green')
            card.tooltipCount=entry.pack and (specialRecordings>0
                and string.format(T('packCount'),standardCount,Colored(specialRecordings,'color.badge.pink'))
                or string.format(T('packStandardCount'),standardCount)) or nil
            card.count:SetText(author..(entry.pack and ' · '..standardCount..(specialRecordings>0 and ' + '..Colored(specialRecordings,'color.badge.pink') or '') or ''))
            card.statusText=card.isFallback and T('packFallback') or entry.pack and T(card.rank and 'packEnabled' or 'packInactive') or T(packStateKeys[card.packState] or 'packUnavailable')
            card.tooltipStatus=Colored(card.statusText,'color.badge.orange')
            card.status:SetText(card.statusText);card.status:SetShown(not card.isFallback and not entry.pack)
            card.status:SetWidth(cell-74);card.status:SetWordWrap(false)
            card.unavailableMark:SetShown(not card.isFallback and not entry.pack)
            card.toggle:SetShown(not card.isFallback and (entry.pack~=nil or card.rank~=nil or card.packState~='not-installed'));card.toggle:SetValue(card.rank~=nil,true)
            card.fallbackLabel:SetShown(card.isFallback)
            for n,arrow in ipairs(card.sortButtons) do
                arrow:SetShown(card.rank~=nil)
                arrow:SetDisabled(not card.rank or (n==1 and card.rank==1 or n==2 and card.rank>=#sound:GetEnabledVoicePacks(prefs)),true)
            end
            card.download:SetShown(canDownload)
            card.download:SetText(T(card.rank and 'downloadPackShort' or 'downloadPack'))
            card.download:SetWidth(card.rank and 56 or 86);card.download:ClearAllPoints();card.download:SetPoint('BOTTOMRIGHT',card.rank and -52 or -12,8)
            card:SetSelected(card.rank~=nil); card:Show()
        end
        for i=#packs+1,#self.packCards do self.packCards[i]:Hide() end
        local y=54+math.ceil(#packs/columns)*(cardHeight+cardGap)
        local playback=sections.packPlayback; playback:SetSize(width,fieldColumns==2 and 120 or 200); playback:ClearAllPoints(); playback:SetPoint('TOPLEFT',0,-y)
        Place(channel,0,38,fieldWidth); Place(preview,fieldColumns==2 and fieldWidth+16 or 0,fieldColumns==2 and 38 or 118,fieldWidth)
        preview.control:SetWidth((fieldWidth-8)/2); preview.control:SetText(T('browsePreview'))
        randomPreview:SetWidth((fieldWidth-8)/2);randomPreview:ClearAllPoints();randomPreview:SetPoint('LEFT',preview.control,'RIGHT',8,0)
        y=y+(fieldColumns==2 and 120 or 200)
        local missing=sections.missingVoice; missing:SetSize(width,60); missing:ClearAllPoints(); missing:SetPoint('TOPLEFT',0,-y)
        self.fallback:SetWidth(width)
        y=y+60
        ttsBody:ClearAllPoints();ttsBody:SetPoint('TOPLEFT',0,-y);ttsBody:SetSize(width,fieldColumns==2 and 200 or 280);ttsBody:Show()
        Place(voice,0,38,fieldWidth);Place(sliders.rate,0,118,fieldWidth)
        Place(sliders.volume,fieldColumns==2 and fieldWidth+16 or 0,fieldColumns==2 and 118 or 198,fieldWidth)
        y=y+(fieldColumns==2 and 200 or 280)
        local queue=sections.queueSettings; queue:SetSize(width,fieldColumns==2 and 120 or 200); queue:ClearAllPoints(); queue:SetPoint('TOPLEFT',0,-y)
        Place(dedup,0,38,fieldWidth); Place(expiry,fieldColumns==2 and fieldWidth+16 or 0,fieldColumns==2 and 38 or 118,fieldWidth); expiry.control:SetWidth(fieldWidth)
        GUI:FitScrollContent(scroll,y+(fieldColumns==2 and 120 or 200))
        self.fallback:SetValue(prefs.fallbackTTS,true)
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
        panel:ClearPreviewFloats()
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
    view.designSpec=Center:SelectionKey(Settings.ConfigSets and Settings.ConfigSets:GetCurrentSpecializationKey()) or 'all'
    local main=GUI:CreateFrame(view,{width=width,height=height-28}); main:SetPoint('TOPLEFT'); main:SetPoint('BOTTOMRIGHT',-18,28); view.main=main
    local title=Text(main,T('title'),GUI.Fonts.size_title,'color.text.heading'); title:SetFont(GUI.Fonts.header,GUI.Fonts.size_title,'OUTLINE'); title:SetPoint('TOPLEFT',0,0)
    if YUI.IsForever then
        view.betaBadge=GUI.Data:CreateBadge(main,{text=YUI.Locale:Get('Core')['settings.general.beta.label'],
            variant='flat',tone='orange',fontSizeKey='font.size.md',height=22,paddingX=8})
        view.betaBadge:SetPoint('LEFT',title,'RIGHT',8,0)
    end
    local disabledText=Text(main,YUI.Locale:Get('Core')['settings.nav.toggle.disabled_content'],'font.size.lg','color.text.secondary')
    disabledText:SetPoint('CENTER',main,'CENTER',0,-16); disabledText:Hide()
    local legacy = Button(main, 'legacyTitle', function() Center:OpenLegacyRecovery() end, 130)
    if view.betaBadge then legacy:SetPoint('LEFT',view.betaBadge,'RIGHT',12,0)
    else legacy:SetPoint('TOPLEFT',120,0) end
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
    local packSummary=GUI:CreateFrame(main,{width=180,height=30});packSummary:SetPoint('RIGHT',pack,'LEFT',-10,0)
    view.packSummary=packSummary;packSummary.icons={}
    local packLabel=Text(packSummary,'','font.size.md','color.text.secondary');packLabel:SetJustifyH('RIGHT');packLabel:SetWordWrap(false)
    packSummary.label=packLabel
    local packOverflow=Text(packSummary,'','font.size.md','color.text.primary');packOverflow:SetWordWrap(false);packOverflow:Hide()
    packSummary.overflow=packOverflow
    for i=1,5 do packSummary.icons[i]=GUI.VoicePicker:CreatePackIcon(packSummary,22);packSummary.icons[i]:Hide() end
    packSummary:EnableMouse(true)
    packSummary:SetScript('OnEnter',function(owner)
        GUI.Tooltip:Show(owner,{title=T('pack'),content=function(tip)
            local sound=YUI.Sound
            for i,id in ipairs(sound:GetEnabledVoicePacks(sound:GetPreferences())) do
                tip:AddLine(i..'. '..sound:GetVoicePackLabel(id))
            end
        end})
    end)
    local function HidePackTooltip(owner) GUI.Tooltip:Hide(owner) end
    packSummary:SetScript('OnLeave',HidePackTooltip);packSummary:SetScript('OnHide',HidePackTooltip)
    function view:RefreshPackSummary()
        GUI.Tooltip:Hide(packSummary)
        local sound=YUI.Sound
        local order=sound:GetEnabledVoicePacks(sound:GetPreferences())
        packLabel:ClearAllPoints();packLabel:SetPoint('RIGHT',0,0);packLabel:SetWidth(packSummary:GetWidth())
        packOverflow:Hide()
        for _,icon in ipairs(packSummary.icons) do icon:Hide();icon.packId=nil end
        if #order<=1 then
            local r,g,b=GUI:GetColor('color.text.primary')
            local color=string.format('|cff%02x%02x%02x',math.floor(r*255),math.floor(g*255),math.floor(b*255))
            packLabel:SetText(T('pack')..' · '..color..(order[1] and sound:GetVoicePackLabel(order[1]) or T('none'))..'|r')
            return
        end
        packLabel:SetText(T('pack')..' ·')
        local labelWidth=packLabel:GetStringWidth()
        packOverflow:SetText('+'..(#order-1))
        if labelWidth+8+22+6+packOverflow:GetStringWidth()>packSummary:GetWidth() then
            packLabel:SetText('');labelWidth=0
        end
        local visible=math.max(1,math.min(#order,#packSummary.icons,math.floor((packSummary:GetWidth()-labelWidth-8+4)/26)))
        local overflowWidth=0
        if visible<#order then
            repeat
                packOverflow:SetText('+'..(#order-visible));overflowWidth=packOverflow:GetStringWidth()
                if labelWidth+8+visible*26-4+6+overflowWidth<=packSummary:GetWidth() or visible==1 then break end
                visible=visible-1
            until false
            packOverflow:SetWidth(overflowWidth);packOverflow:SetHeight(18);packOverflow:Show()
        end
        local totalWidth=labelWidth+8+visible*26-4+(overflowWidth>0 and 6+overflowWidth or 0)
        local left=packSummary:GetWidth()-totalWidth
        packLabel:ClearAllPoints();packLabel:SetPoint('LEFT',left,0);packLabel:SetWidth(labelWidth)
        for i=1,visible do
            local icon=packSummary.icons[i];icon.packId=order[i];icon:SetIcon(sound:GetVoicePackIcon(order[i]))
            icon:ClearAllPoints();icon:SetPoint('LEFT',packSummary,'LEFT',left+labelWidth+8+(i-1)*26,0);icon:Show()
        end
        if overflowWidth>0 then packOverflow:ClearAllPoints();packOverflow:SetPoint('RIGHT',0,0) end
    end
    local spec=Form:CreateSpecDropdown(main,{width=260,height=34,menuWidth=300,options=function() return Center:SpecOptions('unified') end,
        get=function() return view.designSpec end,set=function(value) view.designSpec=value; view.offset=0; view:RefreshRows() end})
    spec:SetPoint('TOPRIGHT',0,-108)
    local search=Form:CreateEditBox(main,{width=260,height=34,placeholder=T('search'),searchPlaceholder=true,onChange=function(_,value)
        view.query=value or ''; view.offset=0; if view.RefreshRows then view:RefreshRows() end
    end})
    search:SetPoint('LEFT',spec,'RIGHT',8,0)
    view.searchInput=search
    local add=Button(main,'add',function() Center:OpenEditor(nil,view.designSpec=='events' and 'events' or view.designSpec=='general' and 'general' or 'class',(view.designSpec=='general' or view.designSpec=='events') and 'all' or view.designSpec) end,112,'accent')
    add:SetRelief('hairline')
    add.gui2SurfaceToken='color.badge.orange'; add.gui2HoverSurfaceToken='color.badge.orange.hover'; add.gui2PressedSurfaceToken='color.badge.orange.pressed'
    add.gui2TextColorKey='color.text.primary'; add.gui2HoverTextColorKey='color.text.primary'; add.gui2PressedTextColorKey='color.text.primary'
    add:SetState('normal')
    add:SetPoint('TOPRIGHT',0,-158); add:SetHeight(34)
    local presets=Button(main,'preset.open',function() Center:OpenPresets() end,112)
    presets:SetHeight(add:GetHeight());presets:SetRelief('hairline')
    presets.gui2SurfaceToken='color.interaction.fill';presets.gui2HoverSurfaceToken='color.interaction.primaryHover';presets.gui2PressedSurfaceToken='color.interaction.primaryPressed'
    presets.gui2TextColorKey='color.text.primary';presets.gui2HoverTextColorKey='color.text.primary';presets.gui2PressedTextColorKey='color.text.primary'
    presets:SetState('normal')
    presets:SetPoint('RIGHT',add,'LEFT',-8,0)
    presets:SetShown(YUI.Sound.Presets~=nil)
    view.presetButton=presets
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
    view.undoButton=undo
    for index=1,12 do
        local row=GUI:CreatePanel(list,{height=82,width=width,surface='color.surface.panel',border='color.border.subtle'})
        view.rows[index]=row
        row:EnableMouse(true)
        row:SetScript('OnEnter',function(owner)
            if GameTooltip and owner.rule then
                GameTooltip:SetOwner(owner,'ANCHOR_RIGHT'); GameTooltip:SetText(owner.name:GetText())
                GameTooltip:AddLine(' ')
                local r,g,b=GUI:GetColor(owner.kind.gui2ColorKey or 'color.text.secondary')
                GameTooltip:AddLine(GUI.Tooltip:ColorText(T('tooltipType'),'secondary')..owner.kind:GetText(),r,g,b,true)
                GameTooltip:AddLine(GUI.Tooltip:ColorText(T('tooltipScope'),'secondary')..(owner.tooltipScope or ''),1,1,1,true)
                GameTooltip:AddLine(GUI.Tooltip:ColorText(T('tooltipTrigger'),'secondary')..owner.when:GetText(),1,1,1,true)
                local bindingText=Center:AuraBindingText(owner.rule)
                if bindingText then GameTooltip:AddLine(T('tooltipBinding')..bindingText,1,1,1,true) end
                GameTooltip:AddLine(' ')
                local parts=owner.soundSources and owner.soundSources.parts or {}
                local index=1
                while index<=#parts do
                    local part=parts[index]
                    local label=part.entryLabel
                    if part.digit then
                        local digits={tostring(part.digit)}
                        local following=parts[index+1]
                        while following and following.digit and following.packId==part.packId
                            and following.kind==part.kind and following.issue==part.issue do
                            index=index+1;digits[#digits+1]=tostring(following.digit);following=parts[index+1]
                        end
                        label=table.concat(digits,T('countdownSeparator'))
                    end
                    if not (owner.specialVoiceHelp and part.issue and YUI.Sound:ParseSpecialVoice(part.value)) then
                        GameTooltip:AddLine((part.role and GUI.Tooltip:ColorText(part.role,'secondary')..'  ' or '')
                            ..label..' · '..GUI.Tooltip:ColorText(part.label,part.issue and 'secondary' or 'action'),1,1,1,true)
                    end
                    index=index+1
                end
                if owner.specialVoiceHelp then
                    r,g,b=GUI:GetColor('color.state.warning')
                    GameTooltip:AddLine(' '); GameTooltip:AddLine(owner.specialVoiceHelp,r,g,b,true)
                end
                if owner.noticeWarning then
                    local reason=owner.noticeReason
                    local help=owner.noticeHelp or not reason and owner.loadSummary
                    if reason and reason~=bindingText or help then
                        r,g,b=GUI:GetColor('color.state.warning')
                        GameTooltip:AddLine(' ')
                        if reason and reason~=bindingText then GameTooltip:AddLine(reason,r,g,b,true) end
                        if help then GameTooltip:AddLine(help,r,g,b,true) end
                    end
                end
                GameTooltip:Show()
            end
        end)
        local function HideRowTooltip(owner) if GameTooltip and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end end
        row:SetScript('OnLeave',HideRowTooltip); row:SetScript('OnHide',HideRowTooltip)
        row.icon=GUI:CreateIcon(row,{width=32,height=32,texture=134400}); row.icon:SetPoint('TOPLEFT',8,-8)
        row.name=Text(row,'','font.size.md'); row.name:SetPoint('TOPLEFT',row.icon,'TOPRIGHT',8,0); row.name:SetWordWrap(false)
        row.kind=Text(row,'','font.size.md','color.text.secondary'); row.kind:SetPoint('BOTTOMLEFT',row.icon,'BOTTOMRIGHT',8,0)
        row.when=Text(row,'','font.size.md'); row.when:SetWordWrap(false)
        row.sound=Text(row,'','font.size.md','color.text.secondary')
        row.soundKind=Text(row,'','font.size.md','color.text.secondary')
        row.sourceIcons={}
        for i=1,3 do row.sourceIcons[i]=GUI.VoicePicker:CreatePackIcon(row,14) end
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
            row.noticeLink.text:ClearAllPoints();row.noticeLink.text:SetPoint('BOTTOMLEFT',0,0)
            row.noticeLink.text:SetJustifyH('LEFT');row.noticeLink.text:SetJustifyV('BOTTOM')
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
            if ok then view.undo={token=store:BeginEdit(),rules=before.rules}; undo:SetText(T('undo')); undo:Show(); view.status:SetText(T('deleted')); view:RefreshRows()
            else Center:Message(code) end
        end)
        row.delete:SetPoint('RIGHT',-6,0)
        row.edit=IconButton(row,'edit','pencil',function() Center:OpenEditor(row.index) end)
        row.edit:SetPoint('RIGHT',row.delete,'LEFT',-4,0)
        row.preview=IconButton(row,'preview','play',function()
            local ok,code=YUI.Sound.EditorModel:Preview(row.rule)
            if not ok then
                local special=code=='special-voice-inactive' or code=='special-voice-unavailable'
                local message=special and Center:ErrorText(code) or T('unavailable')
                view.specialPreview=special and {value=row.rule.sound.value,message=message} or nil
                view.status:SetText(message); view:RefreshRows()
            end
        end)
        row.preview:SetPoint('RIGHT',row.edit,'LEFT',-4,0)
        row.toggle=Form:CreateSwitch(row,{variant='compact',set=function()
            local ok,code=YUI.Sound.EditorModel:Change(row.index,'toggle'); if not ok then Center:Message(code) end
        end})
        row.toggle:SetPoint('RIGHT',row.preview,'LEFT',-8,0)
    end
    function view:RefreshRows()
        local sound,rows=YUI.Sound,{}
        local query=(self.query or ''):match('^%s*(.-)%s*$'):lower()
        local prefs=sound:GetPreferences()
        local preview=self.specialPreview
        if preview then
            if self.status:GetText()~=preview.message then self.specialPreview=nil
            elseif sound:ResolveEntry(preview.value,sound:GetPlaybackOptions(prefs)) then
                self.specialPreview=nil;self.status:SetText('')
            end
        end
        local rules=sound.RuleStore:Read() or {}
        local specNames={}
        for _,group in ipairs(Settings:GetSpecSelectionGroups({})) do
            for _,entry in ipairs(group.specs or {}) do specNames[entry.classInfo.token..':'..entry.specID]=entry end
        end
        for index,rule in ipairs(rules) do
            local inSpec=self.designSpec=='all' or not rule.specs
            if rule.specs then for _,value in ipairs(rule.specs) do if value==self.designSpec then inSpec=true end end
            else for _,value in ipairs(rule.exceptSpecs or {}) do if value==self.designSpec then inSpec=false end end end
            inSpec=Center:ScopeIncludes(rule,self.designSpec,inSpec)
            local displayScope=query~='' and not inSpec and 'all' or self.designSpec
            local displaySpec=tonumber((displayScope or ''):match(':(%d+)$')) or sound.EditorModel:RuleSpec(rule)
            if YUI.IsForever and sound.ForeverCatalog then displaySpec=sound.ForeverCatalog:BrowseSpec(displayScope) or sound.EditorModel:RuleSpec(rule) end
            local name,icon=sound.EditorModel:ObjectInfo(rule.object,rule.trigger.extension,displaySpec)
            local when=sound.EditorModel:TriggerLabel(rule,displaySpec)
            local content,specialVoiceHelp=Center:SoundContent(rule.sound)
            local soundSources=sound.EditorModel:SoundSources(rule.sound,prefs)
            if (query~='' or self.designSpec=='all' or self.designSpec=='events' and rule.object.kind=='event' or self.designSpec=='general' and rule.category=='general' or self.designSpec~='general' and self.designSpec~='events' and rule.category=='class' and inSpec)
                and (query=='' or (name..' '..when..' '..content):lower():find(query,1,true)) then
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
                if YUI.IsForever and sound.ForeverCatalog then
                    load,icons=sound.ForeverCatalog:ScopePresentation(Settings,rule)
                    tooltipScope=load
                end
                local reason,severity,noticeKind=Center:RuleNotice(rule)
                local notice=reason
                local noticeHelp=(reason==T('nativeAuraUnavailable') or reason==T('nativeAuraHidden') or reason==T('boneShieldCDM')) and T('nativeAuraUnavailableHelp') or nil
                local noticeReason
                if reason and severity~='info' and noticeKind~='duplicate' then
                    notice,noticeReason=T('currentlyUnavailable'),reason
                elseif not notice then notice,severity,noticeHelp=Center:ToolboxNotice(rule) end
                rows[#rows+1]={soundSources=soundSources,tooltipScope=(not allSpecs and not rule.exceptSpecs and #tooltipScope>0) and table.concat(tooltipScope,' / ') or (#load>0 and table.concat(load,' · ') or T('unlimited')),index=index,rule=rule,name=name,icon=icon,when=when,content=content,specialVoiceHelp=specialVoiceHelp,icons=icons,notice=notice,noticeReason=noticeReason,noticeHelp=noticeHelp,noticeWarning=notice~=nil and severity~='info',
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
        local stackedActions=YUI.Sound.Presets and w<610
        self.headerY=self.designerHost and (compactHeader and 142 or 176) or (tightHeader and 86 or 130)
        if stackedActions then self.headerY=self.headerY+44 end
        self.listTop=self.headerY+22
        self.rowHeight=w>600 and 64 or 100
        local footerHeight=(self.status:GetText()~='' or undo:IsShown()) and 28 or 4
        main:ClearAllPoints(); main:SetPoint('TOPLEFT'); main:SetPoint('BOTTOMRIGHT',-18,footerHeight)
        main:SetSize(w,self:GetHeight()-footerHeight)
        mainScroll:ClearAllPoints(); mainScroll:SetPoint('TOPLEFT',0,-self.listTop); mainScroll:SetPoint('BOTTOMRIGHT',0,0)
        mainScroll:SetSize(w,math.max(self.rowHeight,self:GetHeight()-footerHeight-self.listTop)); list:SetWidth(w)
        GUI:FitScrollContent(mainScroll,math.max(self.rowHeight,#rows*self.rowHeight))
        local maxScroll=math.max(0,list:GetHeight()-mainScroll:GetHeight())
        mainScroll:SetVerticalScroll(math.min(mainScroll:GetVerticalScroll() or 0,maxScroll))
        local filterY=self.designerHost and (compactHeader and 98 or 132) or (tightHeader and 40 or 84)
        pack:ClearAllPoints();pack:SetPoint('TOPRIGHT',compactHeader and (YUI.Sound.Presets and -240 or -120) or 0,compactHeader and -filterY or (self.designerHost and -90 or -42))
        packSummary:SetWidth(compactHeader and 140 or math.max(90,w-50))
        if tightHeader then
            pack:ClearAllPoints();pack:SetPoint('TOPRIGHT',-220,0)
            packSummary:SetWidth(math.min(180,w-470))
        end
        self:RefreshPackSummary()
        local specWidth=compactHeader and 220 or (roomyFilters and 260 or 240)
        spec:ClearAllPoints();spec:SetPoint('TOPLEFT',0,-filterY);spec:SetWidth(specWidth)
        local presetWidth=YUI.Sound.Presets and 120 or 0
        search:SetWidth(math.max(90,math.min(290,w-specWidth-(stackedActions and 8 or (compactHeader and 322 or 136)+presetWidth))))
        add:ClearAllPoints();add:SetPoint('TOPRIGHT',0,-filterY-(stackedActions and 44 or 0))
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
            if GameTooltip and GameTooltip:IsOwned(row) then GameTooltip:Hide() end
            local item=index<=capacity and rows[self.offset+index]
            if item then
                local dimmed=not item.rule.enabled or item.noticeWarning
                row.index,row.rule=item.index,item.rule; row:SetSize(w,self.rowHeight); row:ClearAllPoints(); row:SetPoint('TOPLEFT',0,-(self.offset+index-1)*self.rowHeight)
                row.name:SetText(item.name); row.name:SetWidth(nameWidth-52); row.icon:SetTexture(item.icon); row.icon:SetAlpha(dimmed and .45 or 1)
                row.icon:ClearAllPoints()
                if wide then row.icon:SetPoint('LEFT',8,0) else row.icon:SetPoint('TOPLEFT',8,-8) end
                row.name:ClearAllPoints();row.name:SetPoint('TOPLEFT',row.icon,'TOPRIGHT',8,0)
                row.kind:ClearAllPoints();row.kind:SetPoint('BOTTOMLEFT',row.icon,'BOTTOMRIGHT',8,0)
                for _,label in ipairs({row.name,row.kind,row.when,row.load,row.sound}) do
                    label:SetHeight(16);label:SetJustifyV('BOTTOM');label:SetAlpha(dimmed and .5 or 1)
                end
                row.name:SetJustifyV('TOP');row.when:SetJustifyV('TOP')
                row.kind:SetText(T(item.rule.object.kind=='event' and 'event' or (item.rule.object.kind=='equipmentAura' or item.rule.object.kind=='itemGroup' or YUI.Sound.EditorModel:PotionBuff(item.rule.object)) and 'presetTag' or item.rule.trigger.extension and ((item.rule.trigger.extension=='boiling-point' or item.rule.trigger.extension=='bone-shield') and 'presetTag' or 'forecastTag') or item.rule.object.kind=='totem' and 'totem' or item.rule.object.kind=='aura' and 'aura' or item.rule.object.kind=='spell' and 'spell' or 'item'))
                local colorKey=(item.rule.trigger.extension or item.rule.object.kind=='equipmentAura' or item.rule.object.kind=='itemGroup' or YUI.Sound.EditorModel:PotionBuff(item.rule.object)) and 'color.badge.orange' or item.rule.object.kind=='aura' and 'color.badge.purple' or item.rule.object.kind=='spell' and 'color.badge.green' or 'color.text.secondary'
                if row.kind.gui2ColorKey~=colorKey then GUI:SetTextColorKey(row.kind,colorKey) end
                row.kind:SetWidth(nameWidth-52)
                row.when:ClearAllPoints(); row.when:SetPoint('TOPLEFT',row.icon,'TOPLEFT',nameWidth,0); row.when:SetWidth(whenWidth-12)
                row.load:ClearAllPoints(); row.load:SetPoint('BOTTOMLEFT',row.icon,'BOTTOMLEFT',nameWidth,0); row.load:SetWidth(whenWidth-12)
                row.noticeWarning=item.noticeWarning; row.noticeReason=item.noticeReason; row.noticeHelp=item.noticeHelp
                row.specialVoiceHelp=item.specialVoiceHelp
                GUI:SetTextColorKey(row.load,item.noticeWarning and 'color.state.warning' or 'color.text.secondary')
                if item.noticeWarning then row.load:SetAlpha(1) end
                row.loadSummary=item.load; row.tooltipScope=item.tooltipScope
                row.load:SetText(wide and #item.icons>4 and not item.notice and ('+'..(#item.icons-4)) or item.load)
                if wide and #item.icons>4 and not item.notice then row.load:ClearAllPoints(); row.load:SetPoint('BOTTOMLEFT',row.icon,'BOTTOMLEFT',nameWidth+84,0) end
                row.load:SetShown(not item.noticeHelp and (not wide or #item.icons==0 or #item.icons>4 or item.notice~=nil))
                row.noticeLink:ClearAllPoints();row.noticeLink:SetPoint('BOTTOMLEFT',row.icon,'BOTTOMLEFT',nameWidth,0)
                row.noticeLink:SetWidth(whenWidth-12);row.noticeLink:SetText(item.notice or '')
                row.noticeLink:SetShown(item.noticeHelp~=nil)
                for i,icon in ipairs(row.specIcons) do
                    icon:SetAlpha(dimmed and .45 or 1)
                    icon:ClearAllPoints(); icon:SetPoint('BOTTOMLEFT',row.icon,'BOTTOMLEFT',nameWidth+(i-1)*20,0)
                    icon:SetShown(wide and item.icons[i]~=nil and not item.notice)
                    if item.icons[i] then
                        local entry=item.icons[i]
                        local api=YUI.API and YUI.API.Icons
                        local native,data=SpecIcon(entry)
                        if not (data and api and api.ApplyIcon and api.ApplyIcon(icon,data)) then
                            icon:SetTexture(native); icon:SetTexCoord(unpack(YUI.IsForever and entry.classInfo.iconTexCoord or dropdownIconCrop))
                        end
                    end
                end
                row.sound:ClearAllPoints()
                if wide then row.sound:SetPoint('TOPLEFT',row.icon,'TOPLEFT',nameWidth+whenWidth+8,0)
                else row.sound:SetPoint('TOPLEFT',nameWidth+8,-44) end
                row.sound:SetWidth(wide and contentWidth-12 or whenWidth-12); row.sound:SetHeight(wide and 16 or 32)
                row.sound:SetJustifyV('TOP');row.sound:SetWordWrap(not wide)
                row.soundSources=item.soundSources
                local sourceX=wide and nameWidth+whenWidth+16 or nameWidth+8
                local iconCount=math.min(3,#item.soundSources.packIds)
                for i,icon in ipairs(row.sourceIcons) do
                    icon:ClearAllPoints()
                    if wide then icon:SetPoint('BOTTOMLEFT',row.icon,'BOTTOMLEFT',sourceX-8+(i-1)*17,0)
                    else icon:SetPoint('TOPLEFT',sourceX+(i-1)*17,-80) end
                    icon:SetShown(i<=iconCount)
                    if i<=iconCount then icon:SetIcon(YUI.Sound:GetVoicePackIcon(item.soundSources.packIds[i])) end
                end
                row.soundKind:ClearAllPoints()
                if wide then row.soundKind:SetPoint('BOTTOMLEFT',row.icon,'BOTTOMLEFT',sourceX-8+iconCount*17,0)
                else row.soundKind:SetPoint('TOPLEFT',sourceX+iconCount*17,-80) end
                row.soundKind:SetWidth(math.max(20,(wide and contentWidth or whenWidth)-12-iconCount*17));row.soundKind:SetHeight(16);row.soundKind:SetShown(true)
                row.soundKind:SetJustifyV(wide and 'BOTTOM' or 'MIDDLE');row.soundKind:SetWordWrap(false)
                row.soundKind:SetText(item.soundSources.label)
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
            if self.preferences then self.preferences:ClearPreviewFloats() end
            if Center.editor then Center.editor:Hide() end
            if Center.legacyPanel then Center.legacyPanel:Hide() end
            if Center.presetDialog then Center.presetDialog:Hide() end
            if GUI.VoicePicker.dialog then GUI.VoicePicker.dialog:Hide() end
            self.undo=nil; undo:Hide()
        end
        self.database,self.profileName=database,profileName
        master:SetValue(prefs.enabled,true)
        local pending = 0
        for _, provider in pairs(sound.LegacyMigration and sound.LegacyMigration.providers or {}) do
            if provider.GetRecoveryCount then pending = pending + provider:GetRecoveryCount() end
        end
        legacy:SetShown(pending > 0)
        self:RefreshRows()
        local enabled=prefs.enabled~=false
        disabledText:SetShown(not enabled)
        for _,control in ipairs({pack,packSummary,share}) do control:SetShown(enabled) end
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
        if Center.editor and Center.editor:IsShown() and Center.editor.edit then
            Center.editor.objectCache=nil; Center.editor:Refresh()
        end
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
    function view:OnVoicePackAddonLoaded(_,name)
        for _,info in pairs(YUI.Sound.knownVoicePacks) do
            if info.addonName==name then self:RequestRefresh();return end
        end
        for _,info in pairs(YUI.Sound.voicePackMetadata or {}) do
            if info.addonName==name then self:RequestRefresh();return end
        end
    end
    view:SetScript('OnSizeChanged',function() if view.Refresh then view:Refresh() end end)
    view:SetScript('OnShow',function()
        Center:ActivateView(view, view == (Center.designerWindow and Center.designerWindow.view) and Center.designerWindow or Settings.Elements.frame)
        local sources=YUI.Monitor and YUI.Monitor.CommonSources
        if sources and sources.RefreshNativeAuraBindings then sources:RefreshNativeAuraBindings() end
        YUI.Event:OffOwner(view)
        for _,event in ipairs({'YUI_CLASS_EXTRA_MONITOR_SETTINGS_CHANGED','YUI_SOUND_RULES_CHANGED','YUI_SOUND_PREFERENCES_CHANGED','YUI_SOUND_PACKS_CHANGED','YUI_SOUND_ENTRIES_CHANGED','YUI_SOUND_BINDING_STATUS_CHANGED','GET_ITEM_INFO_RECEIVED','YUI_MONITOR_SOURCE_STATUS_CHANGED'}) do
            YUI.Event:On(event,'RequestRefresh',view,{moduleId='sound.settings'})
        end
        YUI.Event:On('YUI_SOUND_CONTEXT_CHANGED','OnSoundContextChanged',view,{moduleId='sound.settings'})
        YUI.Event:On('YUI_APPEARANCE_ICON_SET_CHANGED','RefreshSpecIcons',view,{moduleId='sound.settings'})
        YUI.Event:On('YUI_APPEARANCE_ICON_SCOPE_CHANGED','OnIconScopeChanged',view,{moduleId='sound.settings'})
        YUI.Event:On('CVAR_UPDATE','OnCVarChanged',view,{moduleId='sound.settings'})
        YUI.Event:On('ADDON_LOADED','OnVoicePackAddonLoaded',view,{moduleId='sound.settings'})
        view:Refresh()
    end)
    view:SetScript('OnHide',function()
        if view.preferences then view.preferences:ClearPreviewFloats() end
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
