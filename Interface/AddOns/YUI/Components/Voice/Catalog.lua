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
-- Discovery metadata does not register recordings or change playback preferences.
S.knownVoicePacks = {
    ['yui.default'] = { names={enUS='Yanxi',zhCN='言汐',zhTW='言汐'},
        icon=136183, author='阿言', language='zhCN', listOrder=1 },
    wyjjdb = { names={enUS='忘忧景久',zhCN='忘忧景久',zhTW='忘憂景久'}, icon=134229, author='忘忧景久',language='zhCN',
        addonName='WYJJDB', addonIcon='Interface\\AddOns\\WYJJDB\\Media\\icon.tga', listOrder=2,
        builtinIcon='icons\\wyjjdb.tga' },
    ['voice.e4893b47a0d36bc600d88313'] = {
        names={enUS='桃桃奶兮TTNX语音包',zhCN='桃桃奶兮TTNX语音包',zhTW='桃桃奶兮TTNX语音包'},
        icon=136183, author='桃桃奶兮', language='zhCN', listOrder=3, addonName='YUI_VoicePack_TTNX',
        addonIcon='Interface\\AddOns\\YUI_VoicePack_TTNX\\Icon.tga', builtinIcon='icons\\ttnx.tga' },
}
-- Maintainer-reviewed display content. A pack cannot approve its own metadata.
-- Store the approved text/URL here; never expose replacement content from registration.
local ReviewedMetadata = {
    ['yui.default'] = { descriptionKey='defaultPackDescription' },
    wyjjdb = { descriptionKey='externalPackDescription', downloadURL='https://www.curseforge.com/wow/addons/wyjjdb' },
    ['voice.e4893b47a0d36bc600d88313'] = { downloadURL='https://www.curseforge.com/wow/addons/ttnxmedia' },
}

local function Client()
    if YUI.IsRetail then return "mainline" end
    if YUI.IsWrath then return "wrath" end
    if YUI.IsMists then return "mists" end
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
        local entry={id=id,owner=owner,names={},tts={},clients={},class=raw.class,spec=raw.spec,icon=raw.icon,listOrder=raw.listOrder or 0}
        if type(entry.listOrder)~='number' or entry.listOrder<0 or entry.listOrder~=entry.listOrder
            or entry.listOrder==math.huge or entry.listOrder%1~=0 then return false,'invalid-list-order',id end
        if type(raw.icon)=="table" then
            entry.icon={}
            if not next(raw.icon) then return false,"invalid-icon",id end
            for client,icon in pairs(raw.icon) do
                if client~="mainline" and client~="wrath" and client~="mists" then return false,"invalid-icon-client",id end
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
            if client~="mainline" and client~="wrath" and client~="mists" then return false,"invalid-client",id end
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

-- The origin travels with the saved value, including through config sharing.
-- Local special IDs are immutable; display names and recordings may change.
function S:ParseSpecialVoice(value)
    if type(value)~='string' then return nil end
    local pack,id=value:match('^VS:(.+):(SP%-%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x)$')
    if pack and PackText(pack,128) then return pack,id end
end

function S:IsVoiceReference(value)
    return type(value)=='string' and (value:match('^VC%-%x%x%x%x%x%x%x%x$')~=nil or self:ParseSpecialVoice(value)~=nil)
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
        if kind=='client' and key~='mainline' and key~='wrath' and key~='mists' then return nil end
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
    local ids,clients,classes=CopySet(raw.catalogIds,'id'),CopySet(raw.scope.clients,'client'),CopySet(raw.scope.classes,'class')
    if not ids or not clients or not next(clients) or not classes then return nil end
    local result={schemaVersion=1,catalogVersion=raw.catalogVersion,catalogIds=ids,expectedEntries={},
        scope={mode=mode,clients=clients,classes=classes,general=raw.scope.general},checkedFiles={}}
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

function S:RegisterVoicePack(packId, definition)
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
    if self.rejectedVoicePacks then self.rejectedVoicePacks[packId]=nil end
    if YUI.Event then YUI.Event:Emit("YUI_SOUND_PACKS_CHANGED",packId) end
    return true
end

function S:GetVoicePackInfo(id)
    local info={}
    for key,value in pairs(self.knownVoicePacks[id] or {}) do info[key]=value end
    for key,value in pairs(self.voicePacks[id] or {}) do info[key]=value end
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
    if self.voicePacks[id] then return 'ready' end
    local known=self.knownVoicePacks[id]
    local addonName=known and known.addonName
    if not addonName then return 'not-installed' end
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
    return info.addonIcon or info.icon
end

function S:GetEntryIcon(value)
    local origin,id=self:ParseSpecialVoice(value)
    local entry
    if origin then
        local pack=self.voicePacks[origin]
        entry=pack and pack.specialEntries and pack.specialEntries[id]
    else entry=self.entries[value] end
    local icon=entry and entry.icon
    if type(icon)=='table' then icon=icon[Client()] end
    return icon or origin and self:GetVoicePackIcon(origin)
end

function S:GetEntryLabel(id, language)
    local packId,specialId=self:ParseSpecialVoice(id)
    if packId then
        local pack=self.voicePacks[packId]
        local special=pack and pack.specialEntries and pack.specialEntries[specialId]
        return special and Text(special.names,language or Language()) or DisplayText('voice.entry.specialUnavailable')
    end
    local entry=self.entries[id]
    return entry and Text(entry.names,language or Language()) or id
end

function S:GetSpecialEntries(packId,language)
    local pack=self.voicePacks[packId]
    local rows={}
    if not pack or pack.clients and not pack.clients[Client()] then return rows end
    local packIcon=self:GetVoicePackIcon(packId)
    for id,entry in pairs(pack.specialEntries or {}) do
        rows[#rows+1]={id=self:SpecialVoiceReference(packId,id),name=Text(entry.names,language or Language()),
            icon=entry.icon or packIcon,class='special',listOrder=entry.listOrder,packId=packId}
    end
    table.sort(rows,function(a,b)
        if a.listOrder~=b.listOrder then return a.listOrder<b.listOrder end
        if a.name~=b.name then return a.name<b.name end
        return a.id<b.id
    end)
    return rows
end

-- Recording status always describes the selected pack, independent of fallback.
function S:HasVoiceRecording(value,packId)
    local origin,id=self:ParseSpecialVoice(value)
    local pack=self.voicePacks[packId]
    if not pack or pack.clients and not pack.clients[Client()] then return false end
    if origin then return origin==packId and pack.specialEntries[id]~=nil end
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
function S:OrderVoiceEntries(rows,names,packId)
    local subjects={}
    for _,name in ipairs(names or {}) do
        if type(name)=='string' and name~='' then
            local normalized=MatchName(name)
            subjects[#subjects+1]={name=normalized,subject=Subject(normalized)}
        end
    end
    local buckets={{},{},{},{},{},{}}
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
        row.recorded=self:HasVoiceRecording(entry.id,packId)
        local bucket=buckets[match*2+(row.recorded and 1 or 2)]
        bucket[#bucket+1]=row
    end
    local result={}
    for _,bucket in ipairs(buckets) do for _,row in ipairs(bucket) do result[#result+1]=row end end
    return result
end

function S:GetVoicePackLabel(id, language)
    local pack=self.voicePacks[id] or self.knownVoicePacks[id]
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
            or options.class=="general" and entry.class==nil or entry.class==options.class
        local specMatch=not options.spec or entry.spec==nil or entry.spec==options.spec
        if entry.clients[client] and classMatch and specMatch
            and (query=="" or string.find(string.lower(label),query,1,true)) then
            local icon=entry.icon
            if type(icon)=="table" then icon=icon[client] end
            rows[#rows+1]={id=id,name=label,icon=icon,class=entry.class,spec=entry.spec,listOrder=entry.listOrder}
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
local function ResolveEntry(self,id, options,preview)
    options=options or {}
    local origin,specialId=self:ParseSpecialVoice(id)
    if origin then
        local selected=options.packId or self._activeVoicePackId or 'yui.default'
        if selected~=origin then return nil,'special-voice-inactive' end
        local pack=self.voicePacks[origin]
        if not pack then return nil,'special-voice-unavailable' end
        if pack.clients and not pack.clients[options.client or Client()] then return nil,'unsupported-entry-client' end
        local recording=pack.specialEntries[specialId]
        if not recording or options.unavailablePacks and options.unavailablePacks[origin] then return nil,'special-voice-unavailable' end
        return {kind='file',value=recording.file,duration=recording.duration,entryId=id,
            packId=origin,selectedPackId=selected,fallback=false}
    end
    local entry=self.entries[id]
    if not entry then return nil,"unknown-entry" end
    if not entry.clients[options.client or Client()] and not (preview and next(entry.clients)==nil) then
        return nil,"unsupported-entry-client"
    end
    local selected=options.packId or self._activeVoicePackId or "yui.default"
    local visited={}
    local function File(packId)
        if visited[packId] then return end
        visited[packId]=true
        local pack=self.voicePacks[packId]
        if pack and pack.clients and not pack.clients[options.client or Client()] then return end
        local recording=pack and pack.entries[id]
        if recording and not (options.unavailablePacks and options.unavailablePacks[packId]) then
            return {kind="file",value=recording.file,duration=recording.duration,
                entryId=id,packId=packId,selectedPackId=selected,fallback=packId~=selected}
        end
    end
    local resolved=File(selected)
    if resolved then return resolved end
    if options.fallbackDefault~=false then resolved=File("yui.default") end
    if resolved then return resolved end
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
