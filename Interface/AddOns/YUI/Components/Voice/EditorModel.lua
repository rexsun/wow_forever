local _, YUI = ...
YUI = _G.YUI or YUI
local S = YUI and YUI.Sound
if not S then return end
local E = {}
local recoveryEdits = setmetatable({}, { __mode = 'k' })
S.EditorModel = E
E.PresetPresentation={['bone-shield']={tooltipSpellID=195181},['arcane-soul']={tooltipSpellID=451038},['boiling-point']={tooltipSpellID=1265968}}
-- Only confirmed specialization relationships; never merge spells by name.
E.SpellFamilies={
    [65]={[432459]=375576,[200025]=53563},
    [264]={[443454]=378081},
}
E.SpellFamilyScopes={[65]='PALADIN:65',[264]='SHAMAN:264'}
function E:CanonicalSpellID(id,spec)
    local families=YUI.IsRetail and self.SpellFamilies[spec]
    return families and families[id] or id
end
local function Text(key) return YUI.Locale:Get('Core')['sound.center.' .. key] end
local function Client() return YUI.IsRetail and 'mainline' or YUI.IsWrath and 'wrath' or 'mists' end
local function Copy(raw)
    if type(raw)~='table' then return raw end
    local value={}; for key,item in pairs(raw) do value[key]=Copy(item) end; return value
end
E.Copy=Copy
-- Same use-spell IDs and durations as YHUD's quick timed buff presets.
E.PotionBuffs={
    {kind='spellGroup',id='burst-potion',duration=30},
    {id=1236616,duration=30}, -- Light's Potential
    {id=1236994,duration=30}, -- Recklessness
    {id=1236551,duration=18}, -- Invisibility
}
function E:PotionBuff(object)
    if not YUI.IsRetail then return end
    for _,preset in ipairs(self.PotionBuffs) do if (preset.kind or 'spell')==object.kind and preset.id==object.id then return preset end end
end
function E:PickerKind(object,extension)
    if extension or object.kind=='equipmentAura' or object.kind=='totem' or self:PotionBuff(object) then return 'aura' end
    if object.kind=='slot' or object.kind=='itemGroup' then return 'item' end
    return object.kind
end
function E:Definition(object)
    for _,row in ipairs(S.ObjectDefinitions or {}) do
        if row.client==Client() and row.kind==object.kind and row.id==object.id then return row end
    end
end
function E:CastOnly(object)
    local row=self:Definition(object)
    return row and row.castOnly==true or false
end
function E:ObjectCategory(object)
    return (self:IsRacial(object) or self:PotionBuff(object) or object.kind=='equipmentAura' or object.kind=='slot'
        or object.kind=='item' or object.kind=='itemGroup') and 'general' or 'class'
end
function E:IsRacial(object)
    local racial=YUI.API and YUI.API.Racial
    return racial and racial.GetEntry(object.id,object.kind)~=nil or false
end
function E:CurrentSpec()
    local manager=YUI.Settings and YUI.Settings.ConfigSets
    local key=manager and manager.GetCurrentSpecializationKey and manager:GetCurrentSpecializationKey()
    return type(key)=='string' and tonumber(key:match(':(%d+)$')),key
end
function E:RuleSpec(rule)
    local current,key=self:CurrentSpec()
    if rule.specs then
        for _,value in ipairs(rule.specs) do if value==key then return current end end
        return tonumber(rule.specs[1]:match(':(%d+)$')) or -1
    end
    for _,value in ipairs(rule.exceptSpecs or {}) do if value==key then return -1 end end
    return current
end
function E:DisplayID(object,spec)
    if object.kind~='spell' then return object.id end
    local api=YUI.API.Spell
    local racial=YUI.API.Racial
    if self:IsRacial(object) then return racial.ResolveKnownSpellID(object.id) or object.id end
    if spec==nil then
        local definition=self:Definition(object)
        local specs=object.specs or definition and definition.specs
        if specs then
            local current=self:CurrentSpec();spec=-1
            for _,id in ipairs(specs) do if id==current then spec=current; break end end
        end
    end
    local id=self:CanonicalSpellID(object.id,spec or self:CurrentSpec())
    return api.GetEffectiveSpellID and api.GetEffectiveSpellID(id,spec) or id
end
function E:RefreshCatalog()
    self.displayIDs=nil
    if self.currentCatalog and self.currentCatalog.spec~=self:CurrentSpec() then self.currentCatalog=nil end
    if not YUI.IsRetail or InCombatLockdown and InCombatLockdown() then return end
    local manager=YUI.Settings and YUI.Settings.ConfigSets
    local key=manager and manager.GetCurrentSpecializationKey and manager:GetCurrentSpecializationKey()
    local spec=type(key)=='string' and tonumber(key:match(':(%d+)$'))
    local api=YUI.API and YUI.API.CooldownViewer
    if not spec or not api or not api.ReadEntries then return end
    local entries=api:ReadEntries({includeHidden=true,allowUnlearned=true})
    if type(entries)~='table' or #entries==0 then return end
    local rows,seen,nativeAliases,nativeEntries={},{},{},{}
    local common=YUI.Monitor and YUI.Monitor.CommonSources
    local function Add(kind,id,charges,native)
        if issecretvalue and issecretvalue(id) then return end
        if issecretvalue and issecretvalue(charges) then charges=nil end
        if type(id)~='number' or id<1 or id==math.huge or id%1~=0 or #rows>=512 then return end
        local identity=kind..':'..id
        if seen[identity] then return end
        seen[identity]=true
        rows[#rows+1]={kind=kind,id=id,charges=charges,specs={spec},client='mainline',
            nativeCooldownID=native and native.cooldownID,memberIDs=native and native.memberIDs}
    end
    for index,entry in ipairs(entries) do
        if index>512 then break end
        if entry.sourceCategory=='essential' or entry.sourceCategory=='utility' then
            if not entry.equipSlot then Add('spell',entry.spellID,entry.charges) end
        elseif not entry.equipSlot and not tostring(entry.sourceCategory):match('^equipSlot') then
            local native=common and common.DescribeNativeAuraCatalogEntry and common:DescribeNativeAuraCatalogEntry(entry)
            if native then
                Add('aura',native.id,nil,native)
                nativeEntries[native.id]=native
                for id in pairs(native.members) do nativeAliases[id]=native.id end
            elseif type(entry.linkedSpellIDs)=='table' and #entry.linkedSpellIDs>0 then
                for index,id in ipairs(entry.linkedSpellIDs) do
                    if index>32 then break end
                    Add('aura',id)
                end
            elseif (entry.sourceCategory=='trackedBuff' or entry.sourceCategory=='trackedBar')
                and (entry.linkedSpellIDs==nil or type(entry.linkedSpellIDs)=='table' and #entry.linkedSpellIDs==0)
                and (not entry.overrideSpellID or entry.overrideSpellID==entry.spellID)
                and (not entry.overrideTooltipSpellID or entry.overrideTooltipSpellID==entry.spellID) then
                Add('aura',entry.spellID)
            end
        end
    end
    self.currentCatalog={spec=spec,rows=rows,nativeAliases=nativeAliases,nativeEntries=nativeEntries}
end
function E:HasCharges(object,spec)
    if object.kind~='spell' then return false end
    if spec==nil then
        local definition=self:Definition(object)
        if definition and definition.specs then
            spec=-1
            local current=self:CurrentSpec()
            for _,id in ipairs(definition.specs) do if id==current then spec=current; break end end
        end
    end
    local id=self:DisplayID(object,spec)
    local current=self:CurrentSpec()
    local api=YUI.API.Spell
    if (not spec or spec==current) and api.GetChargeCapability then
        local capability=api.GetChargeCapability(id)
        if capability~=nil then return capability end
    end
    -- Native/catalog charge flags describe recharge storage, not the number
    -- of uses granted by the selected talents. Never promote them to capacity.
    if YUI.IsRetail then return nil end
    for _,definition in ipairs(self.currentCatalog and self.currentCatalog.rows or {}) do
        if (not spec or spec==current) and self.currentCatalog.spec==current and definition.kind=='spell' and definition.id==object.id and type(definition.charges)=='boolean' then return definition.charges end
    end
    for _,definition in ipairs(S.ObjectDefinitions or {}) do
        if definition.client==Client() and definition.kind=='spell' and definition.id==id then return definition.charges end
    end
end
function E:ObjectInfo(object, extension, spec)
    local kind,id=object.kind,self:DisplayID(object,spec)
    local name,icon
    if kind=='spellGroup' then name,icon=Text('burstPotionBuff'),7548911
    elseif extension=='bone-shield' then name,icon=Text('boneShield'),YUI.API.Spell.GetTexture(195181)
    elseif extension=='boiling-point' then name,icon=Text('boilingPoint'),YUI.API.Spell.GetTexture(1265968)
    elseif extension then name,icon=Text('arcaneForecast'),YUI.API.Spell.GetTexture(451038)
    elseif kind=='equipmentAura' then name,icon=Text(id==13 and 'trinketAura1' or 'trinketAura2'),YUI.API.Item.GetInventoryItemTexture and YUI.API.Item.GetInventoryItemTexture('player',id) or 134400
    elseif kind=='slot' then name,icon=Text(id==13 and 'upperTrinket' or 'lowerTrinket'),YUI.API.Item.GetInventoryItemTexture and YUI.API.Item.GetInventoryItemTexture('player',id) or 134400
    elseif kind=='itemGroup' then name,icon=Text(id=='health-potion' and 'healthPotion' or 'burstPotion'),id=='health-potion' and 134829 or 7548911
    elseif kind=='item' then
        name=YUI.API.Item.GetName(id); icon=YUI.API.Item.GetIcon(id)
    else name=YUI.API.Spell.GetName(id); icon=YUI.API.Spell.GetTexture(id) end
    return name or ('#'..tostring(id)),icon or object.icon or 134400
end
function E:PotionMembers(object)
    local ids
    if (object.kind=='spellGroup' or object.kind=='itemGroup') and object.id=='burst-potion' then
        ids={241308,241288,271887,241292,241296,271890}
    elseif object.kind=='itemGroup' then
        local common=YUI.Monitor and YUI.Monitor.CommonSources
        local group=common and common.GetPresetItemGroup and common:GetPresetItemGroup(object.id)
        ids=group and group.params.itemIDs
    end
    local rows,seen={},{}
    for _,id in ipairs(ids or {}) do
        local name=YUI.API.Item.GetName(id) or ('#'..id)
        if not seen[name] then
            seen[name]=true
            rows[#rows+1]={name=name,icon=YUI.API.Item.GetIcon(id) or 134400}
        end
    end
    return rows
end
function E:ObjectDetails(object,extension,spec)
    local potion=self:PotionBuff(object)
    if potion then return string.format(Text('potionSummary'),potion.duration) end
    if extension=='bone-shield' then return Text('boneShieldDetails') end
    if extension=='boiling-point' then return Text('boilingPointDetails') end
    if extension then return string.format(Text('forecastLoad'),'|cffffd100'..(YUI.API.Spell.GetName(449619) or '#449619')..'|r') end
    if object.kind=='aura' then
        for _,row in ipairs(self:Objects('class',nil,'','aura')) do
            for _,id in ipairs(row.memberIDs or {}) do
                if id==object.id and #row.memberIDs>1 then
                    table.sort(row.memberIDs)
                    return 'ID '..table.concat(row.memberIDs,' / '),true
                end
            end
        end
    end
    if object.kind=='slot' or object.kind=='equipmentAura' then
        local api=YUI.API.Item;local id=api.GetInventoryItemID and api.GetInventoryItemID('player',object.id)
        return id and api.GetName(id) or Text('emptyTrinket')
    end
    local common=YUI.Monitor and YUI.Monitor.CommonSources
    local group=common and object.kind=='itemGroup' and common.GetPresetItemGroup and common:GetPresetItemGroup(object.id)
    if group then
        local names,seen={},{}
        for _,id in ipairs(group.params.itemIDs) do
            local name=YUI.API.Item.GetName(id) or ('#'..id)
            if not seen[name] then names[#names+1]=name; seen[name]=true end
        end
        return table.concat(names,' / ')
    end
    local display=self:DisplayID(object,spec)
    return object.kind=='itemGroup' and Text(object.id=='health-potion' and 'healthPotion' or 'burstPotion') or ('ID '..tostring(object.id)..(display~=object.id and (' → '..display) or ''))
end
function E:Objects(category,spec,query,kind)
    local rows,seen={},{}
    local catalog=self.currentCatalog
    local native=not spec or catalog and spec==catalog.spec
    local currentSpec=category=='all' and self:CurrentSpec() or nil
    local function Add(object,extension)
        -- Unresolved Build 69814 native links must not return via the live catalog.
        if object.kind=='aura' and (object.id==434112 or object.id==439841) then return end
        local alias=native and catalog and catalog.nativeAliases and catalog.nativeAliases[object.id]
        if object.kind=='aura' and alias and alias~=object.id then return end
        local entry=object.kind=='aura' and native and catalog and catalog.nativeEntries and catalog.nativeEntries[object.id]
        local displayKind=self:PickerKind(object,extension)
        if kind and displayKind~=kind and not (kind=='item' and (object.kind=='slot' or object.kind=='itemGroup')) then return end
        if self:IsRacial(object) then
            if category~='racial' and category~='all' then return end
            local member=YUI.API.Racial.GetEntry(object.id)
            object={kind=object.kind,id=object.kind=='spell' and member.spellID or object.id}
        elseif category=='racial' then return end
        local objectCategory=self:ObjectCategory(object)
        if category=='general' and objectCategory~='general' or category=='class' and objectCategory~='class' then return end
        if object.kind=='spell' and not extension and spec then
            local id=self:CanonicalSpellID(object.id,spec)
            if id~=object.id then
                object=Copy(object);object.id=id
            end
        end
        local name,icon=self:ObjectInfo(object,extension,spec)
        local identity=object.kind..':'..object.id..':'..tostring(extension)
        if seen[identity] then return end
        seen[identity]=true
        local sorting=spec and object.sortBySpec and object.sortBySpec[spec] or object.sortBase or {}
        rows[#rows+1]={object={kind=object.kind,id=object.id,unit=object.kind=='aura' and 'cdm' or 'player'},name=name,icon=icon,
            displayID=self:DisplayID(object,spec),extension=extension,category=self:ObjectCategory(object),specs=object.specs,order=object.order or 1000,pvp=sorting.pvp==true,cooldown=sorting.cooldown,
            nativeCooldownID=entry and entry.cooldownID,nativeMemberIDs=entry and entry.memberIDs}
        if currentSpec and objectCategory=='class' then
            for _,id in ipairs(object.specs or {}) do
                if id==currentSpec then rows[#rows].currentSpec=true; break end
            end
        end
    end
    local racial=YUI.API and YUI.API.Racial
    if racial and (category=='racial' or category=='all' or category=='general') then
        for _,member in ipairs(racial.GetEntries()) do
            Add({kind='spell',id=member.spellID})
            if racial.GetEntry(member.spellID,'aura') then Add({kind='aura',id=member.spellID}) end
        end
    end
    if YUI.IsRetail and kind=='aura' and category~='class' then
        Add({kind='equipmentAura',id=13,order=-9});Add({kind='equipmentAura',id=14,order=-8})
        for i,preset in ipairs(self.PotionBuffs) do
            if preset.kind=='spellGroup' or preset.id==1236551 then Add({kind=preset.kind or 'spell',id=preset.id,order=-8+i}) end
        end
    end
    if category~='class' then
        Add({kind='slot',id=13,order=-4}); Add({kind='slot',id=14,order=-3})
        if YUI.IsRetail then
            Add({kind='itemGroup',id='health-potion',order=-2}); Add({kind='itemGroup',id='burst-potion',order=-1})
        end
    end
    if category~='general' and category~='racial' and YUI.IsRetail and (not spec or spec==62) then
        Add({kind='spell',id=365350,specs={62},order=-10},'arcane-soul')
    end
    if category~='general' and category~='racial' and YUI.IsRetail and (not spec or spec==250) then
        Add({kind='spell',id=195181,specs={250},order=-11},'bone-shield')
        Add({kind='spell',id=1265968,specs={250},order=-10},'boiling-point')
    end
    for _,object in ipairs(S.ObjectDefinitions or {}) do
        if object.client==Client() and not self:PotionBuff(object) then
            local matches=not spec or not object.specs
            for _,id in ipairs(object.specs or {}) do if id==spec then matches=true end end
            if matches then Add(object) end
        end
    end
    if category~='general' and catalog and (not spec or spec==catalog.spec) then
        for _,object in ipairs(catalog.rows) do if not self:PotionBuff(object) then Add(object) end end
    end
    table.sort(rows,function(a,b)
        if a.currentSpec~=b.currentSpec then return a.currentSpec==true end
        if a.order~=b.order then return a.order<b.order end
        if a.pvp~=b.pvp then return not a.pvp end
        if a.cooldown~=b.cooldown then return (a.cooldown or -1)>(b.cooldown or -1) end
        if a.name~=b.name then return a.name<b.name end
        return tostring(a.object.id)<tostring(b.object.id)
    end)
    -- Native relationships take precedence over name-only presentation groups.
    local result,byName={},{}
    local preferred={}
    for _,object in ipairs(catalog and catalog.rows or {}) do
        if object.kind=='aura' then preferred[object.id]=true end
    end
    for _,row in ipairs(rows) do
        local id=row.object.id
        local name=row.name
        local canGroup=row.object.kind=='aura' and not row.extension and name~='#'..tostring(id)
            and not (self.auraMergeExceptions and self.auraMergeExceptions[id])
        local groupKey=name..':'..row.object.unit..':'..tostring(row.pvp)..':'..tostring(row.nativeCooldownID or '')
        local previous=canGroup and byName[groupKey]
        if previous then
            previous.memberIDs[#previous.memberIDs+1]=id
            if preferred[id] and not preferred[previous.object.id] then previous.object.id=id; previous.icon=row.icon end
            if previous.specs and row.specs then
                for _,specID in ipairs(row.specs) do
                    local exists=false
                    for _,old in ipairs(previous.specs) do if old==specID then exists=true end end
                    if not exists then previous.specs[#previous.specs+1]=specID end
                end
            else previous.specs=nil end
        else
            row.memberIDs=row.nativeMemberIDs and #row.nativeMemberIDs>0 and Copy(row.nativeMemberIDs) or {id}; row.specs=Copy(row.specs)
            result[#result+1]=row
            if canGroup then byName[groupKey]=row end
        end
    end
    local filtered={}
    for _,row in ipairs(result) do
        local matches=not query or query=='' or row.name:lower():find(query:lower(),1,true)
        if query and row.object.kind=='spell' and spec then
            local families=YUI.IsRetail and self.SpellFamilies[spec] or {}
            local baseName=YUI.API.Spell.GetName(row.object.id)
            if baseName and baseName:lower():find(query:lower(),1,true) then matches=true end
            for alias,base in pairs(families) do
                if base==row.object.id then
                    local name=YUI.API.Spell.GetName(alias)
                    if tostring(alias):find(query,1,true) or name and name:lower():find(query:lower(),1,true) then matches=true end
                end
            end
        end
        if query and tostring(row.displayID):find(query,1,true) then matches=true end
        for _,id in ipairs(row.memberIDs) do
            if query and tostring(id):find(query,1,true) then matches=true end
        end
        if matches then filtered[#filtered+1]=row end
    end
    return filtered
end
function E:ManualObject(kind,id,spec)
    if (kind~='spell' and kind~='aura') or type(id)~='number' or id%1~=0 or id<1 or id>2147483647 then return nil,'invalid-object' end
    if kind=='spell' then
        local racial=YUI.API.Racial
        local member=racial and racial.GetEntry(id)
        -- nil/all deliberately preserves the entered ID; explicit specs resolve
        -- against their own mapping, never the current character by accident.
        id=member and member.spellID or spec and spec>0 and YUI.API.Spell.GetBaseSpellID and YUI.API.Spell.GetBaseSpellID(id,spec) or id
        id=self:CanonicalSpellID(id,spec)
    end
    local exact,other=false,false
    for _,definitions in ipairs({S.ObjectDefinitions or {},self.currentCatalog and self.currentCatalog.rows or {}}) do
        for _,row in ipairs(definitions) do
            if row.client==Client() and (row.id==id or row.kind=='spell' and self:DisplayID(row)==id) then
                if row.kind==kind then exact=true else other=true end
            end
        end
    end
    if other and not exact then return nil,'object-kind-mismatch' end
    local name=YUI.API.Spell.GetName(id)
    return {object={kind=kind,id=id,unit=kind=='aura' and 'cdm' or 'player'},unverified=not exact or not name}
end
function E:TriggerLabel(rule,spec)
    local lossDelay=tonumber(rule.trigger.lossDelay) or 0
    if rule.trigger.event=='auraRemoved' and lossDelay>0 then
        return string.format(Text('auraLossDelayed'),tostring(lossDelay))
    end
    if rule.object.kind=='equipmentAura' then return Text(rule.trigger.event=='auraAdded' and 'equipmentAuraAdded' or 'equipmentAuraRemoved') end
    if rule.trigger.extension=='bone-shield' then return string.format(Text('boneShieldWhen'),rule.trigger.value or '?') end
    if rule.trigger.extension=='boiling-point' then return Text('boilingPointWhen') end
    if rule.trigger.extension then return Text('forecastWhen') end
    local trigger=rule.trigger
    if trigger.event=='cast' or trigger.event=='castAfter' and trigger.value==0 then return Text('castImmediate') end
    if self:PotionBuff(rule.object) and trigger.duration then
        return trigger.event=='timerRemaining' and string.format(Text('potionBefore'),trigger.value) or Text(trigger.event=='timerStarted' and 'potionUsed' or 'potionEnded')
    end
    if trigger.event=='ready' then
        local charges=self:HasCharges(rule.object,spec or self:RuleSpec(rule))
        return Text(charges==true and 'fullCharges' or 'cooldownReady')
    end
    local label=Text(trigger.event)
    if trigger.event=='castAfter' or trigger.event=='auraRemaining' or trigger.event=='timerRemaining' then return string.format(label,trigger.value) end
    if trigger.event=='auraStacks' then return string.format(label,trigger.operator=='ge' and '≥' or '≤',trigger.value) end
    return label
end
function E:ForecastPartLabel(sound,ending)
    local kind=ending and (sound.endingKind or 'voice') or (sound.introKind or 'voice')
    local value=ending and sound.ending or sound.value
    if kind=='none' then return Text('none') end
    if not value or value=='' then return Text('playContent') end
    if kind=='voice' then return S:GetEntryLabel(value) end
    if kind=='system' and S.GetSoundChoices then
        for _,choice in ipairs(S:GetSoundChoices({source=kind})) do
            if choice.value==kind..':'..value then return choice.text end
        end
    end
    return value
end
function E:ForecastIntroDuration(sound)
    local prefs=S:GetPreferences()
    return S:GetForecastIntroDuration(sound,prefs and {packId=prefs.voicePackId,
        fallbackDefault=prefs.fallbackDefault,fallbackTTS=false})
end
function E:SoundLabel(sound)
    if sound.kind=='boneShield' or sound.kind=='eventWindow' then
        return self:ForecastPartLabel(sound)..' / '..self:ForecastPartLabel(sound,true)
    end
    if sound.kind=='voice' then return S:GetEntryLabel(sound.value) end
    if sound.kind=='forecast' then
        local digits={}
        for i=sound.countdown,1,-1 do digits[#digits+1]=tostring(i) end
        return self:ForecastPartLabel(sound)..' → '..table.concat(digits,Text('countdownSeparator'))..' → '..self:ForecastPartLabel(sound,true)
    end
    return sound.value
end
function E:Preview(rule)
    S:StopPreview()
    if rule.sound.kind=='eventWindow' or rule.sound.kind=='boneShield' then return S:PreviewEventWindow(rule.sound) end
    if rule.sound.kind=='forecast' then
        local duration=self:ForecastIntroDuration(rule.sound)
        if not duration then return nil,'invalid-forecast-duration' end
        return S:StartForecast(S.Runtime.previewOwner,GetTime()+duration+(rule.sound.introKind=='none' and 0 or rule.sound.gap)+rule.sound.countdown+S.FORECAST_VOICE_LEAD,rule.sound)
    end
    return S:Submit(S.Runtime.previewOwner,'preview',rule.sound,true)
end
function E:DefaultLossDelay(object)
    return S.RuleModel:DefaultLossDelay(object)
end
function E:Begin(index,category,spec)
    local token,code=S.RuleStore:BeginEdit(); if not token then return nil,code end
    if index and not token.rules[index] then return nil,'stale-editor' end
    local object={kind=category=='general' and 'slot' or 'spell',id=category=='general' and 13 or 0,unit='player'}
    if not index then
        if category=='general' then spec=nil
        elseif not spec and YUI.Settings and YUI.Settings.GetCurrentSpecSelectionKey then spec=YUI.Settings:GetCurrentSpecSelectionKey() end
        local specId=type(spec)=='string' and tonumber(spec:match(':(%d+)$')) or nil
        for _,candidate in ipairs(self:Objects(category or 'class',specId,nil,category=='general' and 'item' or 'spell')) do
            if not candidate.extension then object=Copy(candidate.object); break end
        end
    end
    local event=object.kind=='aura' and 'auraAdded' or 'ready'
    return {token=token,index=index,rule=index and Copy(token.rules[index]) or {
        object=object,trigger={event=event},
        category=category or 'class',enabled=true,talents={},
        specs=category~='general' and spec and {spec} or nil,sound={kind='voice',value=''} }}
end
function E:Save(edit)
    local rule,code=S.RuleModel:Normalize(edit.rule); if not rule then return nil,code end
    if rule.sound.kind=='forecast' then
        local duration,locked=self:ForecastIntroDuration(rule.sound)
        if not duration then return nil,'invalid-forecast-duration' end
        if locked then rule.sound.introDuration=nil end
    end
    local rules=Copy(edit.token.rules)
    rules[edit.index or (#rules+1)]=rule
    local recovery = recoveryEdits[edit]
    if recovery then
        local ok, why = recovery.provider:CommitRecovery(recovery.prepared, edit.token, rules, S.Runtime)
        if ok then recoveryEdits[edit] = nil end
        return ok, why
    end
    return S.RuleStore:CommitEdit(edit.token,rules,S.Runtime)
end
function E:BeginRecovery(provider, key)
    local prepared, code = provider:PrepareRecovery(key)
    if not prepared then return nil, code end
    local edit, why = self:Begin(nil, prepared.rule.category, prepared.rule.specs and prepared.rule.specs[1])
    if not edit then return nil, why end
    edit.rule = prepared.rule
    recoveryEdits[edit] = { provider = provider, prepared = prepared }
    return edit
end
function E:Change(index,action)
    local token,code=S.RuleStore:BeginEdit(); if not token then return nil,code end
    if not token.rules[index] then return nil,'stale-editor' end
    if action=='delete' then table.remove(token.rules,index)
    else token.rules[index].enabled=not token.rules[index].enabled end
    return S.RuleStore:CommitEdit(token,token.rules,S.Runtime)
end
return E
