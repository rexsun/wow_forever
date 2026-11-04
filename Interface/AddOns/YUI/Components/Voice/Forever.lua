local _,YUI=...
YUI=_G.YUI or YUI
if not (YUI and YUI.IsForever and YUI.Sound) then return end
local S=YUI.Sound
local F={}
S.ForeverCatalog=F
local function Public(value)
    if type(issecretvalue)=='function' and issecretvalue(value) then return end
    return value
end
local function ID(value)
    value=Public(value)
    if type(value)=='number' and value>0 and value<math.huge and value%1==0 then return value end
end
-- All indexes belong to one complete class snapshot. Historical IDs locate the
-- native row, but only live members and the reviewed base can become casts.
local function Index(index,id,native)
    id=ID(id);if not id then return end
    if index[id]==nil then index[id]=native elseif index[id]~=native then index[id]=false end
end
function F:IndexSpells(catalog)
    local live,history={},{}
    for native,entry in pairs(catalog.castEntries) do
        if entry.sourceCategory=='essential' or entry.sourceCategory=='utility' then
            Index(live,entry.spellID,native);Index(live,entry.overrideSpellID,native)
            Index(live,entry.overrideTooltipSpellID,native)
        end
    end
    local _,key=S.EditorModel:CurrentSpec()
    local class=key and key:match('^([^:]+):')
    for native,row in pairs(S.ForeverSpellIdentities or {}) do
        if row.class==class then
            for _,id in ipairs(row.aliases) do Index(history,id,native) end
        end
    end
    for _,row in ipairs(S.ObjectDefinitions or {}) do
        if row.client=='forever' and row.kind=='spell' and self:Matches(row,catalog.spec) then
            Index(history,row.id,row.nativeCooldownID)
        end
    end
    local book=self:RankBook(catalog)
    if book then
        for native,row in pairs(S.ForeverSpellIdentities or {}) do
            local group=row.class==class and book[row.base]
            if group and group.valid then for _,rankID in ipairs(group.ids) do Index(history,rankID,native) end end
        end
        for native,entry in pairs(catalog.castEntries) do
            if entry.sourceCategory=='essential' or entry.sourceCategory=='utility' then
                local candidates={entry.spellID,entry.overrideSpellID,entry.overrideTooltipSpellID}
                local original=S.ForeverSpellIdentities and S.ForeverSpellIdentities[native]
                if original then candidates[#candidates+1]=original.base end
                for _,id in pairs(candidates) do
                    local group=book[id]
                    if group and group.valid then for _,rankID in ipairs(group.ids) do Index(live,rankID,native) end end
                end
            end
        end
    end
    catalog.castAliases,catalog.castHistory=live,history
end
function F:FindSpell(id)
    local editor=S.EditorModel
    local catalog=editor and editor.currentCatalog
    if not catalog or not self:Matches(catalog,editor:CurrentSpec()) then return nil,nil,false end
    if not catalog.castAliases then self:IndexSpells(catalog) end
    local native=catalog.castAliases[id]
    if native==nil then native=catalog.castHistory[id] end
    if native==nil then return nil,catalog,false end
    local entry=native and catalog.castEntries[native]
    if not entry or (entry.sourceCategory~='essential' and entry.sourceCategory~='utility') then return nil,catalog,true end
    return entry,catalog,true
end
function F:RankBook(catalog)
    if catalog.rankBook~=nil then return catalog.rankBook or nil end
    local api=YUI.API.Spell
    local rows=api and api.ReadRankedPlayerSpellBook and api.ReadRankedPlayerSpellBook()
    catalog.rankBook=false
    if type(rows)~='table' then return end
    local groups,byID={},{}
    for _,row in ipairs(rows) do
        if ID(row.spellID) and ID(row.rank) and type(row.name)=='string' and row.name~=''
            and ID(row.skillLineIndex) and type(row.lowRank)=='boolean' then
            local key=row.skillLineIndex..':'..row.name
            local group=groups[key]
            if not group then group={ids={},ranks={},highestCount=0};groups[key]=group end
            if group.ranks[row.rank] then group.ambiguous=true end
            group.ranks[row.rank]=row.spellID;group.ids[#group.ids+1]=row.spellID
            if not row.lowRank then group.highestCount=group.highestCount+1;group.highest=row.spellID;group.highestRank=row.rank end
            byID[row.spellID]=group
        end
    end
    for _,group in pairs(groups) do
        group.valid=not group.ambiguous and group.highestCount==1
        for rank in pairs(group.ranks) do if not group.highestRank or rank>group.highestRank then group.valid=false end end
        table.sort(group.ids)
    end
    catalog.rankBook=byID
    return byID
end
function F:CooldownID(id)
    local entry,catalog,handled=self:FindSpell(id)
    if not handled then return nil,nil,false end
    if not entry then return nil,'source-unavailable',true end
    local book=self:RankBook(catalog)
    local display=ID(entry.overrideSpellID) or ID(entry.spellID)
    local group=book and book[display]
    if group and group.valid then return group.highest,nil,true end
    -- A collection is not a shared cooldown. Preserve the native current
    -- cooldown identity for item effects, groups and non-ranked abilities.
    return display or id,nil,true
end
function F:DisplayID(id,spec)
    local catalog=S.EditorModel.currentCatalog
    if not catalog or spec and not self:Matches(catalog,spec) then return id end
    local entry=self:FindSpell(id)
    return entry and (ID(entry.overrideSpellID) or ID(entry.spellID)) or id
end
-- Class keys (:0) are UI values only. Persist the existing three tree keys so
-- imports, old deliberate tree restrictions and other products keep semantics.
function F:ClassKey(key)
    local class=type(key)=='string' and key:match('^([^:]+):')
    return class and YUI.API.Talent.ConfigurationCatalog[class] and class..':0' or key
end
function F:ClassSpecs(key)
    local class=type(key)=='string' and key:match('^([^:]+):')
    local entry=class and YUI.API.Talent.ConfigurationCatalog[class]
    local specs={}
    for _,tree in ipairs(entry and entry.trees or {}) do specs[#specs+1]=class..':'..tree.specID end
    return specs
end
function F:BrowseSpec(key)
    local specs=self:ClassSpecs(key)
    return specs[1] and tonumber(specs[1]:match(':(%d+)$'))
end
local function Includes(rule,spec)
    if rule.specs then
        for _,value in ipairs(rule.specs) do if value==spec then return true end end
        return false
    end
    for _,value in ipairs(rule.exceptSpecs or {}) do if value==spec then return false end end
    return true
end
function F:IncludesClass(rule,key)
    if key=='all' then return true end
    for _,spec in ipairs(self:ClassSpecs(key)) do if Includes(rule,spec) then return true end end
    return false
end
function F:SelectionGroups(settings)
    local result={}
    for _,group in ipairs(settings:GetSpecSelectionGroups({})) do
        local copy={};for k,v in pairs(group) do copy[k]=v end
        copy.specs={};copy.classes={};local seen={}
        for _,spec in ipairs(group.specs or {}) do
            local class=spec.classInfo.token
            if YUI.API.Talent.ConfigurationCatalog[class] and not seen[class] then
                seen[class]=true
                local row={};for k,v in pairs(spec) do row[k]=v end
                row.key=class..':0';row.displayName=spec.classInfo.name
                row.icon=spec.classInfo.icon or spec.icon;row.nativeIcon=row.icon
                row.iconData={texture=row.icon,texCoord=spec.classInfo.iconTexCoord or {0.08,0.92,0.08,0.92}}
                row.tooltipText=spec.classInfo.name
                copy.specs[#copy.specs+1]=row
                copy.classes[#copy.classes+1]=spec.classInfo
            end
        end
        if #copy.specs>0 then result[#result+1]=copy end
    end
    return result
end
function F:ScopeSelection(rule)
    local selected={}
    for class in pairs(YUI.API.Talent.ConfigurationCatalog) do
        local key=class..':0';selected[key]=self:IncludesClass(rule,key)
    end
    return selected
end
function F:ScopePresentation(settings,rule)
    local names,icons,seen={}, {}, {}
    local all=true
    local label=YUI.Locale:Get('Core')['sound.center.existingTreeScope']
    local groups=settings:GetSpecSelectionGroups({})
    for _,group in ipairs(groups) do
        for _,entry in ipairs(group.specs or {}) do
            local class=entry.classInfo.token
            if YUI.API.Talent.ConfigurationCatalog[class] and not seen[class] then
                seen[class]=true
                local included,total={},0
                for _,otherGroup in ipairs(groups) do
                    for _,other in ipairs(otherGroup.specs or {}) do
                        if other.classInfo.token==class then
                            total=total+1
                            if Includes(rule,other.key or (class..':'..other.specID)) then included[#included+1]=other.displayName end
                        end
                    end
                end
                if #included<total then all=false end
                if #included>0 then
                    local name=entry.classInfo.name
                    if #included<total then name=string.format(label,name,table.concat(included,' / ')) end
                    names[#names+1]=name;icons[#icons+1]=entry
                end
            end
        end
    end
    if all then return {},{} end
    return names,icons
end
function F:UpdateScope(rule,values)
    local before=self:ScopeSelection(rule)
    local changed=false
    for key,value in pairs(before) do if value~=(values[key]==true) then changed=true end end
    if not changed then return end
    local selected={}
    for class in pairs(YUI.API.Talent.ConfigurationCatalog) do
        local key=class..':0'
        for _,spec in ipairs(self:ClassSpecs(key)) do
            if values[key] and (not before[key] or Includes(rule,spec)) then selected[#selected+1]=spec end
        end
    end
    table.sort(selected)
    rule.specs,rule.exceptSpecs=selected,nil
end
-- CN 1.60.1.70374 splits each element across cooldown and aura directories.
-- For a cast reminder, the element includes the active spells from both.
-- These are reviewed directory relationships, NOT lists of cast IDs. Never
-- infer this relationship from matching names, nor apply it to aura/cooldowns.
local castCompanions={
    [1323823]={cooldownID=200365,companionID=200348,companionSpellID=1323772},
    [1323844]={cooldownID=200367,companionID=200368,companionSpellID=1323849},
    [1323858]={cooldownID=200376,companionID=200377,companionSpellID=1323859},
}
local function CastState(params)
    local members={}
    for _,id in ipairs(params.spellIDs) do members[id]=true end
    return {available=true,spellID=params.spellID,sequence=0,members=members}
end
local function ReceiveCast(source,state,_,unit,guid,spellID)
    unit,guid,spellID=Public(unit),Public(guid),ID(spellID)
    if unit~=source.params.unit or not spellID or not state.members[spellID]
        or type(guid)~='string' or guid=='' or guid==state.castGUID then return false end
    state.castGUID,state.castAt=guid,GetTime()
    state.sequence=state.sequence+1
    source.castPending=true
    return true
end
local function ReadCast(source)
    local changed=source.castPending==true
    source.castPending=nil
    return changed
end
function F:DescribeCast(id,unit)
    local companion=castCompanions[id]
    local entry,catalog,handled=self:FindSpell(id)
    if not entry then return nil,'source-unavailable',handled or companion~=nil end
    companion=castCompanions[entry.spellID] or companion
    if issecretvalue and issecretvalue(entry.linkedSpellIDs) then return nil,'source-unavailable',true end
    local members=Public(entry.linkedSpellIDs)
    -- Ordinary single-spell entries retain their existing effective-spell path.
    if not companion and (members==nil or type(members)=='table' and #members==0)
        and not (S.ForeverSpellIdentities and S.ForeverSpellIdentities[entry.cooldownID]) then return nil,nil,false end
    if unit~='player' then return nil,'source-unavailable',true end
    local api=YUI.API.Spell
    if not (api and api.GetPlayerCastSpellID) then return nil,'source-unavailable',true end
    local candidates,invalid={},false
    local function Add(value)
        if issecretvalue and issecretvalue(value) then invalid=true;return end
        if value==nil then return end
        local safe=ID(value)
        if safe then candidates[safe]=true elseif Public(value)~=0 then invalid=true end
    end
    local function AddEntry(value)
        Add(value.spellID);Add(value.overrideSpellID);Add(value.overrideTooltipSpellID)
        if issecretvalue and issecretvalue(value.linkedSpellIDs) then invalid=true;return end
        local linked=Public(value.linkedSpellIDs)
        if linked~=nil then
            if type(linked)~='table' or #linked>512 then invalid=true;return end
            for _,member in ipairs(linked) do Add(member) end
        end
    end
    AddEntry(entry)
    local historical=S.ForeverSpellIdentities and S.ForeverSpellIdentities[entry.cooldownID]
    if historical then Add(historical.base) end
    if companion and entry.cooldownID==companion.cooldownID then
        local other=catalog.castEntries[companion.companionID]
        if other and ID(other.spellID)==companion.companionSpellID
            and (other.sourceCategory=='trackedBuff' or other.sourceCategory=='trackedBar') then AddEntry(other) end
    end
    if invalid then return nil,'source-unavailable',true end
    local ids,seen,unknown={},{},false
    -- Cache only within this complete catalog snapshot; spell/talent/catalog
    -- notifications replace it. No API calls or allocations on cast events.
    local cache=catalog.castCapabilities
    local book=self:RankBook(catalog)
    for candidate in pairs(candidates) do
        local rankGroup=book and book[candidate]
        if rankGroup and rankGroup.valid then
            -- Explicit ranks in one player skill line plus the native low-rank
            -- flag distinguish rank siblings from same-name spells/effects.
            for _,rankID in ipairs(rankGroup.ids) do
                if not seen[rankID] then ids[#ids+1]=rankID;seen[rankID]=true end
            end
        end
        local actual=cache[candidate]
        if actual==nil then
            actual=api.GetPlayerCastSpellID(candidate)
            if not ID(actual) and Public(actual)~=false then actual='unknown' end
            cache[candidate]=actual
        end
        if actual=='unknown' then unknown=true end
        actual=ID(actual)
        if actual and not seen[actual] then ids[#ids+1]=actual;seen[actual]=true end
    end
    if #ids==0 then return nil,unknown and 'spell-known-unknown' or 'spell-cast-unavailable',true end
    table.sort(ids)
    if #ids==1 then
        local ok,code=YUI.Monitor.CommonSources:RegisterCastSourceType()
        if not ok then return nil,code,true end
        return {key='cast:'..unit..':'..ids[1],type='spell-cast',params={spellID=ids[1],unit=unit}},nil,true
    end
    if not self.castGroupRegistered then
        -- Individual spell rules can coexist with a group without colliding in
        -- the single-identity source index. Active groups have bounded members.
        local ok,code=YUI.Monitor:RegisterSourceType('forever-cast-group',{
            createState=CastState,read=ReadCast,onEvent=ReceiveCast,
            events={{event='UNIT_SPELLCAST_SUCCEEDED',units={'player','target','focus'},all=true,synchronous=true}},
        })
        if not ok and code~='source-type-exists' then return nil,code,true end
        self.castGroupRegistered=true
    end
    -- Membership is part of the key: reconciliation acquires new bindings
    -- before releasing old ones, so changed membership needs a separate source.
    return {key='forever-cast-group:'..unit..':'..id..':'..table.concat(ids,','),type='forever-cast-group',
        params={spellID=id,spellIDs=ids,unit=unit}},nil,true
end

-- Resolve on every display read. Existing spell-data events invalidate editor
-- caches, so newly supplied official Chinese wins without a persisted override.
function F:DisplayName(id,name)
    name=Public(name)
    local locale=YUI.Locale and YUI.Locale:Current() or GetLocale and GetLocale()
    if locale~='zhCN' and locale~='zhTW' then return name end
    local row=S.ForeverSpellNames and S.ForeverSpellNames[id]
    if not row then return name end
    if type(name)=='string' and name:find('[\228-\233][\128-\191][\128-\191]') then return name end
    return row[locale] or name
end
function F:Scopes(spec)
    local catalog=YUI.API.Talent and YUI.API.Talent.ConfigurationCatalog
    for _,class in pairs(catalog or {}) do
        for _,tree in ipairs(class.trees) do
            if tree.specID==spec then
                local scopes={};for _,member in ipairs(class.trees) do scopes[#scopes+1]=member.specID end
                return scopes
            end
        end
    end
    return {spec}
end
function F:Matches(catalog,spec)
    if not spec then return true end
    for _,id in ipairs(catalog.specs or {catalog.spec}) do if id==spec then return true end end
    return false
end
function F:Refresh(editor)
    local spec=editor:CurrentSpec()
    if editor.currentCatalog and not self:Matches(editor.currentCatalog,spec) then editor.currentCatalog=nil end
    if not spec or InCombatLockdown and InCombatLockdown() then return end
    local reader=YUI.API.CooldownViewer
    if not (reader and reader.ReadEntries) then return end
    local ok,entries,meta=pcall(reader.ReadEntries,reader,{rawCatalog=true,includeHidden=true,allowUnlearned=true})
    entries,meta=Public(entries),Public(meta)
    if not ok or type(entries)~='table' or type(meta)~='table' or #entries==0 or #entries>512
        or Public(meta.rawCatalog)~=true or Public(meta.skipped)~=0 or Public(meta.skippedSources)~=0
        or Public(meta.returned)~=#entries or Public(meta.total)~=#entries then return end
    local rows,seen,aliases,nativeEntries={},{},{},{}
    local common=YUI.Monitor and YUI.Monitor.CommonSources
    local scopes=self:Scopes(spec)
    local function Add(kind,id,entry,native)
        id=ID(id);if not id then return end
        local key=kind..':'..id
        if seen[key] then return end
        seen[key]=true
        rows[#rows+1]={client='forever',kind=kind,id=id,specs=scopes,
            nativeCooldownID=entry.cooldownID,memberIDs=native and native.memberIDs or entry.linkedSpellIDs}
    end
    local cooldowns={}
    for _,entry in ipairs(entries) do
        entry=Public(entry)
        if type(entry)~='table' or not ID(entry.cooldownID) or cooldowns[entry.cooldownID] then return end
        cooldowns[entry.cooldownID]=entry
        if not Public(entry.equipSlot) then
            if entry.sourceCategory=='essential' or entry.sourceCategory=='utility' then
                if issecretvalue and (issecretvalue(entry.spellID) or issecretvalue(entry.overrideSpellID)
                    or issecretvalue(entry.overrideTooltipSpellID)) then return end
                local id=ID(entry.spellID)
                local fallback=S.ForeverIdentityFallback and S.ForeverIdentityFallback[entry.cooldownID]
                if not id then
                    id=ID(entry.overrideSpellID) or ID(entry.overrideTooltipSpellID)
                    if not id and fallback and fallback.category==entry.sourceCategory
                        and self:Matches(fallback,spec) then id=fallback.id end
                end
                Add('spell',id,entry)
            elseif entry.sourceCategory=='trackedBuff' or entry.sourceCategory=='trackedBar' then
                local native=common and common.DescribeNativeAuraCatalogEntry and common:DescribeNativeAuraCatalogEntry(entry)
                if native then
                    Add('aura',native.id,entry,native)
                    nativeEntries[native.id]=native
                    for id in pairs(native.members) do aliases[id]=native.id end
                else
                    local linked=Public(entry.linkedSpellIDs)
                    if type(linked)=='table' and #linked==1 then Add('aura',linked[1],entry)
                    elseif not linked or type(linked)=='table' and #linked==0 then
                        Add('aura',entry.overrideTooltipSpellID or entry.overrideSpellID or entry.spellID,entry)
                    end
                end
            end
        end
    end
    -- A complete nonempty native snapshot replaces this class's browse directory.
    -- Empty, restricted and partial reads retain the last valid snapshot.
    editor.currentCatalog={spec=spec,specs=scopes,rows=rows,nativeAliases=aliases,nativeEntries=nativeEntries,
        castEntries=cooldowns,castCapabilities={}}
    self:IndexSpells(editor.currentCatalog)
end

-- Reuse the existing classic vocabulary and recordings without changing either
-- source client's entry scope. Voice choice does not create a monitoring rule.
local classes=YUI.API.Talent and YUI.API.Talent.ConfigurationCatalog or {}
for _,entry in pairs(S.entries or {}) do
    if entry.clients.wrath and (not entry.class or classes[entry.class]) then
        -- Keep old saved voice IDs playable without crowding the reviewed picker.
        if entry.class and not entry.clients.forever then entry.foreverLegacy=true end
        entry.clients.forever=true
        entry.spec=nil
        if type(entry.icon)=='table' and entry.icon.forever==nil then entry.icon.forever=entry.icon.wrath end
    end
end
