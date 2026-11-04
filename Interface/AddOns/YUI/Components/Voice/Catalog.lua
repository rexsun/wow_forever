local ADDON_NAME, YUI = ...
YUI = _G.YUI or YUI
if not (YUI and YUI.Sound) then return end
local S = YUI.Sound
-- Bind these resources to the addon carrying Voice, even when Core loaded elsewhere.
if YUI.Assets and YUI.Assets.RegisterComponentRoot then
    YUI.Assets:RegisterComponentRoot('Voice', 'Interface\\AddOns\\'..ADDON_NAME..'\\Components\\Voice\\Media')
end
S.entries = S.entries or {}
S.voicePacks = S.voicePacks or {}
S.voicePackMetadata = S.voicePackMetadata or {}
-- Discovery metadata does not register recordings or change playback preferences.
S.knownVoicePacks = {
    ['yui.default'] = { names={enUS='Yanxi',zhCN='言汐',zhTW='言汐'},
        icon=136183, author='阿言', language='zhCN', listOrder=1 },
    wyjjdb = { names={enUS='忘忧景久',zhCN='忘忧景久',zhTW='忘憂景久'}, icon=134229, author='忘忧景久',language='zhCN',
        recommendClients={mainline=true,wrath=true,mists=true},
        addonName='WYJJDB', addonIcon='Interface\\AddOns\\WYJJDB\\Media\\icon.tga', listOrder=2,
        builtinIcon='icons\\wyjjdb.tga' },
    ['voice.e4893b47a0d36bc600d88313'] = {
        recommendClients={mainline=true,wrath=true,mists=true},
        names={enUS='桃桃奶兮TTNX语音包',zhCN='桃桃奶兮TTNX语音包',zhTW='桃桃奶兮TTNX语音包'},
        icon=136183, author='桃桃奶兮', language='zhCN', listOrder=3, addonName='YUI_VoicePack_TTNX',
        addonIcon='Interface\\AddOns\\YUI_VoicePack_TTNX\\Icon.tga', builtinIcon='icons\\ttnx.tga' },
    ['voice.f0f55c3f08372f1e189a9b9f'] = {
        recommendClients={mainline=true,wrath=true,mists=true},
        names={enUS='摘风铃的语音包',zhCN='摘风铃的语音包',zhTW='摘风铃的语音包'},
        icon=136183, author='摘风铃', language='zhCN', listOrder=4, addonName='YUI_VoicePack_Ring',
        addonIcon='Interface\\AddOns\\YUI_VoicePack_Ring\\Icon.tga', builtinIcon='icons\\ring.tga' },
}
-- Maintainer-reviewed display content. A pack cannot approve its own metadata.
-- Store the approved text/URL here; never expose replacement content from registration.
local ReviewedMetadata = {
    ['yui.default'] = { descriptionKey='defaultPackDescription' },
    wyjjdb = { descriptionKey='externalPackDescription', downloadURL='https://www.curseforge.com/wow/addons/wyjjdb' },
    ['voice.e4893b47a0d36bc600d88313'] = { descriptionKey='ttnxPackDescription', downloadURL='https://www.curseforge.com/wow/addons/ttnxmedia' },
    ['voice.f0f55c3f08372f1e189a9b9f'] = { descriptionKey='ringPackDescription', downloadURL='https://www.curseforge.com/wow/addons/ring-sharedmedia-yui' },
}

local function Client()
    if YUI.IsForever then return "forever" end
    if YUI.IsRetail then return "mainline" end
    if YUI.IsWrath then return "wrath" end
    if YUI.IsMists then return "mists" end
end

-- Discovery only; keep the full identity catalog for installed and saved packs.
function S:GetRecommendedVoicePacks(client)
    client=client or Client()
    local packs={}
    for id,info in pairs(self.knownVoicePacks) do
        if not info.recommendClients or info.recommendClients[client] then packs[id]=info end
    end
    return packs
end

local function Language()
    local locale=YUI.Locale
    if locale and type(locale.Current)=="function" then return locale:Current() end
    return type(GetLocale)=="function" and GetLocale() or "enUS"
end

local function DisplayText(key)
    return YUI.Locale and YUI.Locale:Get('Core')[key] or key
end

local function Positive(n)
    return type(n)=="number" and n==n and n>0 and n<math.huge
end

-- Short literal labels only; never allow WoW color/texture markup.
function S:GetIconText(icon)
    if type(icon)~="string" or icon:sub(1,5)~="text:" then return nil end
    local text=icon:sub(6)
    if text=="" or text:find("[%z\1-\31\127|]") or text:match("^%s") or text:match("%s$") then return nil end
    local i,count=1,0
    while i<=#text do
        local b=text:byte(i)
        local size=b<128 and 1 or b>=194 and b<=223 and 2 or b>=224 and b<=239 and 3 or b>=240 and b<=244 and 4
        if not size then return nil end
        for j=1,size-1 do
            local c=text:byte(i+j)
            if not c or c<128 or c>191 then return nil end
        end
        local second=text:byte(i+1)
        if size==3 and (b==224 and second<160 or b==237 and second>=160)
            or size==4 and (b==240 and second<144 or b==244 and second>=144) then return nil end
        count=count+1
        if count>4 then return nil end
        i=i+size
    end
    return text
end

local function ValidIcon(icon)
    return Positive(icon) and icon%1==0 and icon<=4294967295 or S:GetIconText(icon)~=nil
end

local function Text(map, lang)
    return type(map)=="table" and (map[lang] or map.enUS) or nil
end

function S:RegisterEntries(owner, definitions)
    if type(owner)~="string" or owner=="" or type(definitions)~="table" then return false,"invalid-entries" end
    local staged={}
    for id,raw in pairs(definitions) do
        if type(id)~="string" or not id:match("^VC%-%x%x%x%x%x%x%x%x$") or self.entries[id]
            or type(raw)~="table" or type(raw.names)~="table" or type(raw.names.enUS)~="string"
            or raw.names.enUS=="" then return false,"invalid-entry",id end
        local entry={id=id,owner=owner,names={},tts={},clients={},class=raw.class,spec=raw.spec,icon=raw.icon,listOrder=raw.listOrder or 0,
            categories={},eventGroup=raw.eventGroup,buffSpellID=raw.buffSpellID,recordingPending=raw.recordingPending==true,factionPart=raw.factionPart==true,retired=raw.retired==true}
        if raw.eventGroup~=nil and raw.eventGroup~='daily' and raw.eventGroup~='group' and raw.eventGroup~='combat' and raw.eventGroup~='explore' then return false,'invalid-entry-categories',id end
        if raw.categories~=nil then
            if type(raw.categories)~='table' then return false,'invalid-entry-categories',id end
            for key,value in pairs(raw.categories) do
                if (key~='buffs' and key~='events') or value~=true then return false,'invalid-entry-categories',id end
                entry.categories[key]=true
            end
        end
        if entry.buffSpellID~=nil and (not Positive(entry.buffSpellID) or entry.buffSpellID%1~=0) then return false,'invalid-buff-spell-id',id end
        if type(entry.listOrder)~='number' or entry.listOrder<0 or entry.listOrder~=entry.listOrder
            or entry.listOrder==math.huge or entry.listOrder%1~=0 then return false,'invalid-list-order',id end
        if type(raw.icon)=="table" then
            entry.icon={}
            if not next(raw.icon) then return false,"invalid-icon",id end
            for client,icon in pairs(raw.icon) do
                if client~="mainline" and client~="wrath" and client~="mists" and client~="forever" then return false,"invalid-icon-client",id end
                if not ValidIcon(icon) then return false,"invalid-icon",id end
                entry.icon[client]=icon
            end
        elseif entry.icon~=nil and not ValidIcon(entry.icon) then return false,"invalid-icon",id end
        for lang,name in pairs(raw.names) do
            if type(lang)~="string" or type(name)~="string" or name=="" then return false,"invalid-name",id end
            entry.names[lang]=name
        end
        for lang,value in pairs(raw.tts or raw.names) do
            if type(lang)~="string" or type(value)~="string" or value=="" then return false,"invalid-tts",id end
            entry.tts[lang]=value
        end
        if type(raw.clients)~="table" then return false,"clients-required",id end
        for client,enabled in pairs(raw.clients) do
            if client~="mainline" and client~="wrath" and client~="mists" and client~="forever" then return false,"invalid-client",id end
            if enabled==true then entry.clients[client]=true end
        end
        staged[id]=entry
    end
    for id,entry in pairs(staged) do self.entries[id]=entry end
    if YUI.Event then YUI.Event:Emit("YUI_SOUND_ENTRIES_CHANGED") end
    return true
end

local function PackText(value, limit)
    return type(value)=='string' and #value<=limit and not value:find('[%z\1-\31\127|]')
end

local function GeneratedId(id)
    return type(id)=='string' and #id==30 and id:match('^voice%.%x+$')~=nil
end
local function GeneratedOwner(owner)
    return type(owner)=='string' and #owner<=62 and owner:match('^YUI_VoicePack_[%w_]+$')~=nil
end
local function SpecialId(id)
    return type(id)=='string' and #id==27 and id:match('^SP%-%x+$')~=nil
end

-- Optional creator protocol. Aliases never grant reviewed text/URL permissions.
function S:CopyVoicePackIdentity(raw,packId)
    if type(raw)~='table' or raw.schemaVersion~=1 or not GeneratedId(packId)
        or type(raw.aliases)~='table' or #raw.aliases>127 then return end
    local copy={schemaVersion=1,aliases={},specialAliases={}}
    local ids={[packId]=true}
    for key,id in pairs(raw.aliases) do
        if type(key)~='number' or key%1~=0 or key<1 or key>#raw.aliases or not GeneratedId(id) or ids[id] then return end
        ids[id]=true;copy.aliases[key]=id
    end
    local count=0
    if raw.specialAliases~=nil and type(raw.specialAliases)~='table' then return end
    for origin,map in pairs(raw.specialAliases or {}) do
        if not ids[origin] or type(map)~='table' then return end
        local out={};copy.specialAliases[origin]=out
        for old,new in pairs(map) do
            count=count+1
            if count>4096 or not SpecialId(old) or not SpecialId(new) then return end
            out[old]=new
        end
    end
    return copy
end

function S:GetVoicePackId(id) return self.voicePackAliases and self.voicePackAliases[id] or id end
function S:GetVoicePack(id)
    local canonical=self:GetVoicePackId(id)
    local actual=self.voicePackBindings and self.voicePackBindings[canonical] or canonical
    return self.voicePacks[actual]
end
function S:GetSpecialVoiceEntry(origin,id)
    local pack=self:GetVoicePack(origin)
    local map=self.voicePackSpecialAliases and self.voicePackSpecialAliases[origin]
    local target=map and map[id]
    if target==false then return end
    return pack and pack.specialEntries and pack.specialEntries[target or id]
end

-- Registration/DB/import only. Playback resolves through the resulting O(1) maps.
function S:RebuildVoicePackIdentities(order)
    local groups,sources,blocked,loadedCounts={},{},{},{}
    local function Add(id,info,loaded)
        local owner=info and info.addonName
        if loaded and owner then
            loadedCounts[owner]=(loadedCounts[owner] or 0)+1
            if loadedCounts[owner]>1 then blocked[owner]=true end
        end
        if not GeneratedId(id) or not GeneratedOwner(owner) then return end
        if loaded and not (info.identity or info.manifest and info.manifest.creatorVersion) then blocked[owner]=true;return end
        if sources[id] and sources[id]~=owner then blocked[owner]=true;blocked[sources[id]]=true;return end
        sources[id]=owner
        local group=groups[owner] or {ids={}};groups[owner]=group
        group.ids[id]=true
        if loaded then group.loaded=info end
    end
    for id,info in pairs(self.knownVoicePacks) do Add(id,info) end
    for id,info in pairs(self.voicePackMetadata) do Add(id,info) end
    for id,owner in pairs(self.voicePackSources or {}) do Add(id,{addonName=owner}) end
    for id,info in pairs(self.voicePacks) do Add(id,info,true) end
    local function AddAliases(pack)
        local group=groups[pack.addonName]
        if group and pack.identity then for _,id in ipairs(pack.identity.aliases) do
            if sources[id] and sources[id]~=pack.addonName then blocked[pack.addonName]=true
            else group.ids[id]=true;sources[id]=pack.addonName end
        end end
    end
    for _,pack in pairs(self.voicePackMetadata) do AddAliases(pack) end
    for _,pack in pairs(self.voicePacks) do AddAliases(pack) end
    local aliases,bindings={},{}
    self.voicePackAnchors=self.voicePackAnchors or {}
    for owner,group in pairs(groups) do
        if not blocked[owner] then
            local canonical
            -- Reviewed catalog identities and explicit author repairs are stable anchors.
            for id in pairs(group.ids) do if self.knownVoicePacks[id] and (not canonical or id<canonical) then canonical=id end end
            local pack=group.loaded
            if not canonical and pack and pack.identity and #pack.identity.aliases>0 then canonical=pack.id end
            local anchor=self.voicePackAnchors[owner]
            if not canonical and group.ids[anchor] then canonical=anchor end
            if not canonical then for _,id in ipairs(order or {}) do if group.ids[id] then canonical=id;break end end end
            if not canonical then for id in pairs(group.ids) do if not canonical or id<canonical then canonical=id end end end
            if canonical then
                self.voicePackAnchors[owner]=canonical
                for id in pairs(group.ids) do aliases[id]=canonical end
                if pack then bindings[canonical]=pack.id end
            end
        end
    end
    local specialMaps={}
    local function AddSpecialMaps(info,loaded)
        if not info.identity or blocked[info.addonName] then return end
        for origin,map in pairs(info.identity.specialAliases) do
            if aliases[origin] and groups[info.addonName] and groups[info.addonName].ids[origin] then
                local out=specialMaps[origin] or {};specialMaps[origin]=out
                for old,new in pairs(map) do
                    if loaded or out[old]==nil then out[old]=new
                    elseif out[old]~=new then out[old]=false end
                end
            end
        end
    end
    for _,info in pairs(self.voicePackMetadata) do AddSpecialMaps(info) end
    for _,info in pairs(self.voicePacks) do AddSpecialMaps(info,true) end
    self.voicePackAliases,self.voicePackBindings,self.voicePackSpecialAliases=aliases,bindings,specialMaps
    self.voicePackIdentityRevision=(self.voicePackIdentityRevision or 0)+1
end

function S:CopyVoicePackSources(raw)
    if type(raw)~='table' then return end
    local result,count={},0
    for id,owner in pairs(raw) do
        count=count+1
        if count>128 or not GeneratedId(id) or not GeneratedOwner(owner) then return end
        local existing=self.voicePacks[id] or self.knownVoicePacks[id] or self.voicePackMetadata[id]
        if existing and existing.addonName~=owner or self.voicePackSources and self.voicePackSources[id] and self.voicePackSources[id]~=owner then return end
        result[id]=owner
    end
    return result
end

function S:CaptureVoicePackSources(rules)
    local result={}
    local function Visit(value)
        if type(value)=='table' then for _,item in pairs(value) do Visit(item) end
        elseif type(value)=='string' then
            local origin=self:ParseSpecialVoice(value)
            if origin and GeneratedId(origin) then
                local info=self:GetVoicePackInfo(origin)
                local owner=info.addonName or self.voicePackSources and self.voicePackSources[origin]
                if GeneratedOwner(owner) then result[origin]=owner end
            end
        end
    end
    Visit(rules)
    return result
end

-- Identity only: cached discovery must never register recordings or approve display content.
function S:CopyVoicePackMetadata(info)
    if type(info)~='table' or type(info.names)~='table' or not PackText(info.names.enUS,256)
        or info.names.enUS=='' then return end
    local copy={names={}}
    for language,name in pairs(info.names) do
        if PackText(language,5) and language:match('^%l%l%u%u$') and PackText(name,256) and name~='' then
            copy.names[language]=name
        end
    end
    for key,limit in pairs({author=256,version=64,addonName=128,language=5}) do
        if PackText(info[key],limit) then copy[key]=info[key] end
    end
    local localIcon=copy.addonName and copy.addonName:match('^[%w_]+$')
        and info.icon=='Interface\\AddOns\\'..copy.addonName..'\\Icon.tga'
    if ValidIcon(info.icon) or localIcon then copy.icon=info.icon end
    if info.identity then copy.identity=self:CopyVoicePackIdentity(info.identity,info.id or info.packId) end
    copy.packId=info.id or info.packId
    return copy
end

function S:PreserveVoicePackIdentity(metadata,previous,packId)
    if not (metadata and previous and previous.addonName==metadata.addonName and previous.identity) then return metadata end
    local history={schemaVersion=1,aliases={},specialAliases={}}
    local seen={[packId]=true}
    for _,identity in ipairs({previous.identity,metadata.identity or {aliases={},specialAliases={}}}) do
        for _,id in ipairs(identity.aliases) do if not seen[id] then history.aliases[#history.aliases+1]=id;seen[id]=true end end
        for origin,map in pairs(identity.specialAliases) do
            local out=history.specialAliases[origin] or {};history.specialAliases[origin]=out
            for old,new in pairs(map) do out[old]=new end
        end
    end
    metadata.identity=self:CopyVoicePackIdentity(history,packId) or metadata.identity or previous.identity
    return metadata
end

-- The origin travels with the saved value, including through config sharing.
-- Local special IDs are immutable; display names and recordings may change.
function S:ParseSpecialVoice(value)
    if type(value)~='string' then return nil end
    local pack,id=value:match('^VS:(.+):(SP%-%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x)$')
    if pack and PackText(pack,128) then return pack,id end
end

function S:IsVoiceReference(value)
    return type(value)=='string' and (value:match('^VC%-%x%x%x%x%x%x%x%x$')~=nil
        or self.factionVoices and self.factionVoices[value]~=nil or self:ParseSpecialVoice(value)~=nil)
end

-- A saved automatic choice resolves to a concrete recording before pack fallback.
function S:GetFactionVoiceTarget(value)
    local group=self.factionVoices and self.factionVoices[value]
    if not group then return nil end
    local unit=YUI.API and YUI.API.Unit
    local faction=unit and unit.UnitFactionGroup and unit.UnitFactionGroup('player')
    return faction=='Alliance' and group.Alliance or group.Horde
end

function S:GetReceivedBuffVoiceID(spellID)
    if YUI.IsRetail and (spellID==32182 or spellID==2825) and self.factionVoices and self.factionVoices['VF:heroism'] then return 'VF:heroism' end
    local client=Client()
    for id,entry in pairs(self.entries) do
        if entry.buffSpellID==spellID and entry.clients[client] and not (YUI.IsForever and entry.foreverLegacy) then return id end
    end
end

function S:SpecialVoiceReference(packId,id)
    if type(packId)~='string' or type(id)~='string' then return nil end
    local value='VS:'..packId..':'..id
    local origin,specialId=self:ParseSpecialVoice(value)
    return origin==packId and specialId==id and value or nil
end

local function CopySet(raw, kind)
    if type(raw)~='table' then return nil end
    local result,count={},0
    for key,value in pairs(raw) do
        count=count+1
        if count>10000 or value~=true or type(key)~='string' then return nil end
        if kind=='id' and not key:match('^VC%-%x%x%x%x%x%x%x%x$') then return nil end
        if kind=='client' and key~='mainline' and key~='wrath' and key~='mists' and key~='forever' then return nil end
        if kind=='class' and (key=='' or not key:match('^[A-Z]+$')) then return nil end
        result[key]=true
    end
    return result
end

local function CopyManifest(raw)
    if type(raw)~='table' or raw.schemaVersion~=1 or not PackText(raw.catalogVersion,128)
        or type(raw.scope)~='table' or type(raw.expectedEntries)~='table' then return nil end
    local mode=raw.scope.mode
    if mode~='all' and mode~='classes' and mode~='sample' or type(raw.scope.general)~='boolean' then return nil end
    if raw.scope.buffs~=nil and type(raw.scope.buffs)~='boolean' then return nil end
    local ids,clients,classes=CopySet(raw.catalogIds,'id'),CopySet(raw.scope.clients,'client'),CopySet(raw.scope.classes,'class')
    if not ids or not clients or not next(clients) or not classes then return nil end
    local result={schemaVersion=1,catalogVersion=raw.catalogVersion,catalogIds=ids,expectedEntries={},
        scope={mode=mode,clients=clients,classes=classes,general=raw.scope.general},checkedFiles={}}
    if raw.scope.buffs~=nil then result.scope.buffs=raw.scope.buffs end
    for id,file in pairs(raw.expectedEntries) do
        if not ids[id] or type(file)~='string' or #file>128 or not file:match('^[a-z0-9_]+%.ogg$') then return nil end
        result.expectedEntries[id]=file
    end
    if raw.checkedFiles~=nil then
        if type(raw.checkedFiles)~='table' then return nil end
        local count=0
        for file,record in pairs(raw.checkedFiles) do
            count=count+1
            if count>10000 or type(file)~='string' or not file:match('^[a-z0-9_]+%.ogg$') or type(record)~='table'
                or record.decoded~=true or not Positive(record.duration) or record.duration>300
                or not Positive(record.size) or not Positive(record.sampleRate)
                or record.channels~=1 and record.channels~=2 then return nil end
            result.checkedFiles[file]={decoded=true,duration=record.duration,size=record.size,
                sampleRate=record.sampleRate,channels=record.channels,peak=Positive(record.peak) and record.peak or nil}
        end
    end
    for _,key in ipairs({'generatedAt','creatorVersion'}) do
        if raw[key]~=nil then if not PackText(raw[key],128) then return nil end; result[key]=raw[key] end
    end
    return result
end

function S:RegisterVoicePack(packId, definition, sourceAddon)
    local function Reject(code)
        if type(packId)=='string' and packId~='' and #packId<=128 then
            self.rejectedVoicePacks=self.rejectedVoicePacks or {}
            self.rejectedVoicePacks[packId]={code=code}
        end
        return false,code
    end
    if not PackText(packId,128) or packId=="" or self.voicePacks[packId] or type(definition)~="table"
        or definition.protocolVersion~=1 or type(definition.entries)~="table" then return Reject("invalid-voice-pack") end
    local pack={id=packId,names={},entries={},language=definition.language}
    if definition.language~=nil and (not PackText(definition.language,5) or not definition.language:match('^%l%l%u%u$')) then return Reject('invalid-pack-language') end
    for key,limit in pairs({author=256,version=64,description=4096,downloadURL=1024,addonName=128}) do
        if definition[key]~=nil then
            if not PackText(definition[key],limit) then return Reject('invalid-pack-metadata') end
            pack[key]=definition[key]
        end
    end
    if definition.icon~=nil then
        local localIcon=type(pack.addonName)=='string' and pack.addonName:match('^[%w_]+$')
            and definition.icon=='Interface\\AddOns\\'..pack.addonName..'\\Icon.tga'
        if not ValidIcon(definition.icon) and not localIcon then return Reject('invalid-pack-icon') end
        pack.icon=definition.icon
    end
    if definition.clients~=nil then
        pack.clients=CopySet(definition.clients,'client')
        if not pack.clients or not next(pack.clients) then return Reject('invalid-pack-clients') end
    end
    if definition.manifest~=nil then
        pack.manifest=CopyManifest(definition.manifest)
        if not pack.manifest then return Reject('invalid-pack-manifest') end
        if pack.clients then
            for client in pairs(pack.clients) do if not pack.manifest.scope.clients[client] then return Reject('inconsistent-pack-clients') end end
            for client in pairs(pack.manifest.scope.clients) do if not pack.clients[client] then return Reject('inconsistent-pack-clients') end end
        else pack.clients=pack.manifest.scope.clients end
    end
    if definition.identity~=nil then
        pack.identity=self:CopyVoicePackIdentity(definition.identity,packId)
        if not pack.identity or not GeneratedOwner(pack.addonName) or sourceAddon~=pack.addonName then return Reject('invalid-pack-identity') end
    end
    if definition.names~=nil and type(definition.names)~='table' then return Reject('invalid-pack-name') end
    for lang,name in pairs(definition.names or {}) do
        if type(lang)~="string" or not PackText(name,256) or name=="" then return Reject("invalid-pack-name") end
        pack.names[lang]=name
    end
    if not pack.names.enUS then return Reject("pack-name-required") end
    for id,raw in pairs(definition.entries) do
        if type(id)~="string" or not id:match("^VC%-%x%x%x%x%x%x%x%x$") or type(raw)~="table" then return Reject("invalid-pack-entry") end
        local file=raw.file
        if (type(file)~="string" or file=="") and (not Positive(file) or file%1~=0) then return Reject("invalid-file") end
        if raw.duration~=nil and not Positive(raw.duration) then return Reject("invalid-duration") end
        if pack.manifest then
            local expected=pack.manifest.expectedEntries[id]
            local checked=expected and pack.manifest.checkedFiles[expected]
            if not checked or checked.duration~=raw.duration or not PackText(file,512) then return Reject('invalid-standard-recording') end
        end
        pack.entries[id]={file=file,duration=raw.duration}
    end
    pack.specialEntries={}
    if definition.specialEntries~=nil then
        if type(definition.specialEntries)~='table' then return Reject('invalid-special-entry') end
        local count=0
        for id,raw in pairs(definition.specialEntries) do
            count=count+1
            if count>512 or type(id)~='string' or not self:SpecialVoiceReference(packId,id)
                or type(raw)~='table' or type(raw.names)~='table' or not PackText(raw.names.enUS,256)
                or raw.names.enUS=='' or not PackText(raw.file,512) or raw.file==''
                or not Positive(raw.duration) or raw.duration>300 then return Reject('invalid-special-entry') end
            local entry={id=id,names={},file=raw.file,duration=raw.duration,icon=raw.icon,listOrder=raw.listOrder or 0}
            if entry.icon~=nil and not ValidIcon(entry.icon) then return Reject('invalid-special-icon') end
            if type(entry.listOrder)~='number' or entry.listOrder~=entry.listOrder or entry.listOrder<0
                or entry.listOrder>=math.huge or entry.listOrder%1~=0 then return Reject('invalid-special-order') end
            for lang,name in pairs(raw.names) do
                if type(lang)~='string' or not PackText(name,256) or name=='' then return Reject('invalid-special-name') end
                entry.names[lang]=name
            end
            if pack.manifest then
                local file=raw.file:match('([^\\/]+)$')
                local checked=file and pack.manifest.checkedFiles[file]
                local path=pack.addonName and 'Interface\\AddOns\\'..pack.addonName..'\\Media\\'..(file or '')
                if not checked or checked.duration~=raw.duration or raw.file~=path then return Reject('invalid-special-recording') end
            end
            pack.specialEntries[id]=entry
        end
    end
    self.voicePacks[packId]=pack
    self.voicePackMetadata[packId]=self:PreserveVoicePackIdentity(self:CopyVoicePackMetadata(pack),self.voicePackMetadata[packId],packId)
    if self.SaveVoicePackMetadata then self:SaveVoicePackMetadata(packId) end
    if self.RestoreVoicePackMetadata then self:RestoreVoicePackMetadata() else self:RebuildVoicePackIdentities() end
    if self.rejectedVoicePacks then self.rejectedVoicePacks[packId]=nil end
    if YUI.Event then YUI.Event:Emit("YUI_SOUND_PACKS_CHANGED",packId) end
    return true
end

function S:GetVoicePackInfo(id)
    id=self:GetVoicePackId(id)
    local info={}
    for key,value in pairs(self.voicePackMetadata[id] or {}) do info[key]=value end
    for key,value in pairs(self.knownVoicePacks[id] or {}) do info[key]=value end
    for key,value in pairs(self:GetVoicePack(id) or {}) do info[key]=value end
    info.builtinIcon=self.knownVoicePacks[id] and self.knownVoicePacks[id].builtinIcon or nil
    -- Every display surface uses these curated fields, including copyable reports.
    local reviewed=ReviewedMetadata[id]
    info.description=reviewed and reviewed.description or nil
    info.descriptionKey=reviewed and reviewed.descriptionKey or nil
    info.downloadURL=reviewed and reviewed.downloadURL or nil
    info.metadataReviewed=reviewed~=nil
    return info
end

function S:GetVoicePackState(id)
    id=self:GetVoicePackId(id)
    if self:GetVoicePack(id) then return 'ready' end
    local known=self.knownVoicePacks[id]
    local saved=self.voicePackMetadata[id]
    local addonName=known and known.addonName or saved and saved.addonName
    if not addonName or addonName=='' then return 'unavailable' end
    local system=YUI.API and YUI.API.System
    if not (system and system.DoesAddOnExist) then return 'unavailable' end
    if not system.DoesAddOnExist(addonName) then return 'not-installed' end
    if system.GetAddOnLoadedState and system.GetAddOnLoadedState(addonName)==true then return 'not-registered' end
    if system.GetAddOnEnabledState and system.GetAddOnEnabledState(addonName)==false then return 'disabled' end
    return 'not-loaded'
end

function S:GetVoicePackIcon(id)
    local info=self:GetVoicePackInfo(id)
    if info.builtinIcon and YUI.Assets then return YUI.Assets:Component('Voice',info.builtinIcon) end
    if id=='yui.default' and YUI.Assets then return YUI.Assets:Core('images\\YUI-LOGO-300.png') end
    local icon=info.addonIcon or info.icon
    if type(icon)=='string' and icon:sub(1,17)=='Interface\\AddOns\\'
        and self:GetVoicePackState(id)=='not-installed' then return 136183 end
    return icon
end

function S:GetEntryIcon(value)
    value=self:GetFactionVoiceTarget(value) or value
    local origin,id=self:ParseSpecialVoice(value)
    local entry
    if origin then
        entry=self:GetSpecialVoiceEntry(origin,id)
    else entry=self.entries[value] end
    local icon=entry and entry.icon
    if type(icon)=='table' then icon=icon[Client()] end
    return icon or origin and self:GetVoicePackIcon(origin)
end

function S:GetEntryLabel(id, language)
    local group=self.factionVoices and self.factionVoices[id]
    if group then return Text(group.names,language or Language()) end
    local packId,specialId=self:ParseSpecialVoice(id)
    if packId then
        local special=self:GetSpecialVoiceEntry(packId,specialId)
        return special and Text(special.names,language or Language()) or DisplayText('voice.entry.specialUnavailable')
    end
    local entry=self.entries[id]
    return entry and Text(entry.names,language or Language()) or id
end

function S:GetSpecialEntries(packId,language)
    packId=self:GetVoicePackId(packId)
    local pack=self:GetVoicePack(packId)
    local rows={}
    if not pack or pack.clients and not pack.clients[Client()] then return rows end
    local packIcon=self:GetVoicePackIcon(packId)
    for id,entry in pairs(pack.specialEntries or {}) do
        rows[#rows+1]={id=self:SpecialVoiceReference(pack.id,id),name=Text(entry.names,language or Language()),
            icon=entry.icon or packIcon,class='special',listOrder=entry.listOrder,packId=packId}
    end
    table.sort(rows,function(a,b)
        if a.listOrder~=b.listOrder then return a.listOrder<b.listOrder end
        if a.name~=b.name then return a.name<b.name end
        return a.id<b.id
    end)
    return rows
end

-- Cold configuration/UI helpers. Validated preferences already include Yanxi.
function S:GetEnabledVoicePacks(prefs)
    prefs=prefs or self.GetPreferences and self:GetPreferences() or {}
    local saved=prefs.voicePackOrder
    if saved and prefs._voicePackOrderRevision~=nil and prefs._voicePackOrderRevision==self.voicePackIdentityRevision then return saved end
    if type(saved)=='table' then
        local normalized,seen={},{}
        for _,id in ipairs(saved) do
            id=self:GetVoicePackId(id)
            if not seen[id] then normalized[#normalized+1]=id;seen[id]=true end
        end
        saved=normalized
    end
    if type(saved)=='table' then
        for _,id in ipairs(saved) do if id=='yui.default' then return saved end end
        local order={}
        for _,id in ipairs(saved) do order[#order+1]=id end
        order[#order+1]='yui.default'
        return order
    end
    local selected=prefs.voicePackId or 'yui.default'
    local order={selected}
    if selected~='yui.default' then order[2]='yui.default' end
    return order
end

function S:IsVoicePackEnabled(packId,prefs)
    packId=self:GetVoicePackId(packId)
    for rank,id in ipairs(self:GetEnabledVoicePacks(prefs)) do if id==packId then return rank end end
end

function S:GetPlaybackOptions(prefs)
    prefs=prefs or self.GetPreferences and self:GetPreferences() or {}
    return {packOrder=self:GetEnabledVoicePacks(prefs),fallbackTTS=prefs.fallbackTTS~=false,
        language=prefs.language~='auto' and prefs.language or nil}
end

function S:GetEnabledSpecialEntries(prefs,language)
    local rows={}
    for _,packId in ipairs(self:GetEnabledVoicePacks(prefs)) do
        for _,entry in ipairs(self:GetSpecialEntries(packId,language)) do rows[#rows+1]=entry end
    end
    return rows
end

-- Recording status always describes the selected pack, independent of fallback.
function S:HasVoiceRecording(value,packId)
    value=self:GetFactionVoiceTarget(value) or value
    local origin,id=self:ParseSpecialVoice(value)
    local pack=self:GetVoicePack(packId)
    if not pack or pack.clients and not pack.clients[Client()] then return false end
    if origin then return self:GetVoicePackId(origin)==self:GetVoicePackId(packId) and self:GetSpecialVoiceEntry(origin,id)~=nil end
    return pack.entries[value]~=nil
end

local aliases={['寒冰屏障']='冰箱',['隱身術']='隱身',['隐身术']='隐身',['操控时间']='操控',
    ['操控時間']='操控',['群体隐身']='群隐',['群體隱身']='群隱',
    ['群体隐形术']='群隐',['群體隱形術']='群隱',['火焰冲击']='火冲',['火焰衝擊']='火衝',
    ['炽热重生']='春哥',['熾熱重生']='春哥'}
local function MatchName(name)
    return string.lower(name):gsub('[%s%p]','')
end
local function Subject(name)
    name=name:gsub('^准备',''):gsub('^準備',''):gsub('就绪$',''):gsub('就緒$','')
        :gsub('^prepare',''):gsub('ready$','')
    return aliases[name] or name
end
local function Matchable(name)
    return #name>=(name:byte(1) and name:byte(1)>=128 and 6 or 3)
end

-- Cold UI work: literal subject matching and six stable buckets, linear in rows.
-- Never scan or allocate matching tables from the playback/event hot path.
function S:OrderVoiceEntries(rows,names,packId,preferredID)
    local subjects={}
    for _,name in ipairs(names or {}) do
        if type(name)=='string' and name~='' then
            local normalized=MatchName(name)
            subjects[#subjects+1]={name=normalized,subject=Subject(normalized)}
        end
    end
    local buckets={{},{},{},{},{},{}}
    local options=not packId and self:GetPlaybackOptions()
    for _,entry in ipairs(rows) do
        local name=MatchName(entry.name)
        local subject=Subject(name)
        local match=2
        for _,monitor in ipairs(subjects) do
            if name==monitor.name then match=0;break end
            if Matchable(monitor.subject) and Matchable(subject) and (subject==monitor.subject
                or subject:find(monitor.subject,1,true) or monitor.subject:find(subject,1,true)) then match=1 end
        end
        local row={}
        for key,value in pairs(entry) do row[key]=value end
        local resource=options and self:ResolveEntry(entry.id,options)
        row.recorded=packId and self:HasVoiceRecording(entry.id,packId) or resource and resource.kind=='file' or false
        row.sourcePackId=resource and resource.packId
        row.sourceKind=resource and resource.kind
        local bucket=buckets[match*2+(row.recorded and 1 or 2)]
        bucket[#bucket+1]=row
    end
    local result={}
    for _,bucket in ipairs(buckets) do for _,row in ipairs(bucket) do result[#result+1]=row end end
    if preferredID then
        for i,row in ipairs(result) do
            if row.id==preferredID then table.remove(result,i);table.insert(result,1,row);break end
        end
    end
    return result
end

function S:GetVoicePackLabel(id, language)
    id=self:GetVoicePackId(id)
    local pack=self:GetVoicePack(id) or self.knownVoicePacks[id] or self.voicePackMetadata[id]
    return pack and Text(pack.names,language or Language()) or DisplayText('voice.pack.unknownName')
end

function S:GetEntries(options)
    options=options or {}
    local rows={}
    local query=string.lower(options.query or "")
    local client=options.client or Client()
    for id,entry in pairs(self.entries) do
        local label=self:GetEntryLabel(id,options.language)
        local classMatch=not options.class or options.class=="all"
              or options.class=='events' and entry.categories and entry.categories.events
            or options.class=='buffs' and entry.categories and entry.categories.buffs or options.class=="general" and entry.class==nil or entry.class==options.class
          local specMatch=options.class=='events' and (not options.spec or entry.eventGroup==options.spec)
              or options.class~='events' and (options.class=='buffs' or not options.spec or entry.spec==nil or entry.spec==options.spec)
        if entry.clients[client] and not (client == 'forever' and entry.foreverLegacy)
            and not entry.factionPart and not entry.retired and classMatch and specMatch
            and (query=="" or string.find(string.lower(label),query,1,true)) then
            local icon=entry.icon
            if type(icon)=="table" then icon=icon[client] end
              rows[#rows+1]={id=id,name=label,icon=icon,class=entry.class,spec=entry.spec,listOrder=entry.listOrder,categories=entry.categories,eventGroup=entry.eventGroup}
        end
    end
    for id,group in pairs(self.factionVoices or {}) do
        local label=self:GetEntryLabel(id,options.language)
        if group.clients[client] and (not options.class or options.class=='all' or options.class=='general' or options.class=='buffs')
            and (query=='' or string.find(string.lower(label),query,1,true)) then
            rows[#rows+1]={id=id,name=label,icon=self:GetEntryIcon(id),listOrder=group.listOrder,categories={buffs=true}}
        end
    end
    table.sort(rows,function(a,b)
        if a.listOrder~=b.listOrder then return a.listOrder<b.listOrder end
        if a.name==b.name then return a.id<b.id end
        return a.name<b.name
    end)
    return rows
end

-- Resolve only. A missing optional pack never rewrites the player's choice.
-- An unsupported client is not a missing recording and cannot fall back.
local function FileResource(self,id,packId,selected,options)
    local pack=self:GetVoicePack(packId)
    if not pack or pack.clients and not pack.clients[options.client or Client()]
        or options.unavailablePacks and options.unavailablePacks[packId] then return end
    local recording=pack.entries[id]
    if recording then
        return {kind='file',value=recording.file,duration=recording.duration,
            entryId=id,packId=packId,selectedPackId=selected,fallback=packId~=selected}
    end
end
local function ResolveEntry(self,id, options,preview)
    options=options or {}
    id=self:GetFactionVoiceTarget(id) or id
    local order=options.packOrder or (not options.packId and self._activeVoicePackOrder)
    local selected=order and order[1] or options.packId or self._activeVoicePackId or 'yui.default'
    local origin,specialId=self:ParseSpecialVoice(id)
    if origin then
        local canonical=self:GetVoicePackId(origin)
        local enabled=not order and self:GetVoicePackId(selected)==canonical
        if order then for _,packId in ipairs(order) do if self:GetVoicePackId(packId)==canonical then enabled=true;break end end end
        if not enabled then return nil,'special-voice-inactive' end
        local pack=self:GetVoicePack(origin)
        if not pack then return nil,'special-voice-unavailable' end
        if pack.clients and not pack.clients[options.client or Client()] then return nil,'unsupported-entry-client' end
        local recording=self:GetSpecialVoiceEntry(origin,specialId)
        if not recording or options.unavailablePacks and options.unavailablePacks[origin] then return nil,'special-voice-unavailable' end
        return {kind='file',value=recording.file,duration=recording.duration,entryId=id,
            packId=origin,selectedPackId=selected,fallback=false}
    end
    local entry=self.entries[id]
    if not entry then return nil,"unknown-entry" end
    if not entry.clients[options.client or Client()] and not (preview and next(entry.clients)==nil) then
        return nil,"unsupported-entry-client"
    end
    if order then
        for _,packId in ipairs(order) do
            local resolved=FileResource(self,id,packId,selected,options)
            if resolved then return resolved end
        end
    else
        local resolved=FileResource(self,id,selected,selected,options)
        if resolved then return resolved end
        if selected~='yui.default' and options.fallbackDefault~=false then
            resolved=FileResource(self,id,'yui.default',selected,options)
            if resolved then return resolved end
        end
    end
    if options.fallbackTTS~=false then
        local value=Text(entry.tts,options.language or Language())
        if value then return {kind="tts",value=value,entryId=id,selectedPackId=selected,fallback=true} end
    end
    return nil,"missing-recording"
end

function S:ResolveEntry(id,options) return ResolveEntry(self,id,options,false) end
-- Explicit audition only: entries awaiting a client decision stay unavailable
-- to normal rules and the client-filtered selection catalog.
function S:ResolvePreviewEntry(id,options) return ResolveEntry(self,id,options,true) end

-- Other sources always require a player-supplied duration, even with metadata.
function S:GetForecastIntroDuration(sound,options)
    if sound.introKind=='none' then return 0,true end
    if (sound.introKind or 'voice')=='voice' then
        local part=self:ResolveEntry(sound.value,options)
        if part and part.kind=='file' and Positive(part.duration) then return part.duration,true end
        if self:ParseSpecialVoice(sound.value) then return 0,true end
    end
    if Positive(sound.introDuration) and sound.introDuration<=86400 then return sound.introDuration,false end
    return nil,false
end

-- Compensate a small part of voice onset latency; the ending stays on targetAt.
S.FORECAST_VOICE_LEAD = 0.08
function S:BuildForecast(targetAt, countdown, gap, introduction, ending, digits, now)
    if not Positive(targetAt) or not Positive(countdown) or countdown%1~=0 or countdown>10
        or type(gap)~="number" or gap~=gap or gap<0 or gap>10
        or type(now)~="number" or now~=now or now==math.huge or now==-math.huge then
        return nil,"invalid-timeline"
    end
    local function Valid(part,needsDuration)
        return type(part)=="table" and (part.kind=="file" or part.kind=="kit")
            and (not needsDuration or Positive(part.duration))
            and (part.duration==nil or Positive(part.duration))
            and ((type(part.value)=="string" and part.value~="") or Positive(part.value))
    end
    if (not Valid(introduction,true) and not (type(introduction)=="table" and introduction.kind=="none"))
        or (not Valid(ending,false) and not (type(ending)=="table" and ending.kind=="none")) or type(digits)~="table" then return nil,"incomplete-timeline" end
    for k=1,countdown do
        if not Valid(digits[k],true) then return nil,"incomplete-timeline" end
    end
    local jobs={}
    local function Add(at,part,segment)
        -- Preview can calculate its introduction exactly at now; tolerate only
        -- floating-point roundoff, never advance a future segment.
        if at>=now-0.000001 then jobs[#jobs+1]={at=math.max(at,now),kind=part.kind,value=part.value,duration=part.duration,segment=segment} end
    end
    if introduction.kind~="none" then Add(targetAt-countdown-gap-introduction.duration-self.FORECAST_VOICE_LEAD,introduction,"intro") end
    for k=countdown,1,-1 do Add(targetAt-k-self.FORECAST_VOICE_LEAD,digits[k],"countdown") end
    if ending.kind~="none" then Add(targetAt,ending,"end") end
    return jobs
end

return S
