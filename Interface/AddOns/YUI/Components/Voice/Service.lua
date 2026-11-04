local addonName, namespace = ...
local YUI = _G.YUI or namespace
local S = YUI and YUI.Sound
if not (S and S.Playback and S.RuleRuntime and S.RuleStore and S.TTS and S.Forecast) then return end
if S.Runtime then return end
local Monitor, API = YUI.Monitor, YUI.API and YUI.API.Sound
if not (Monitor and Monitor.ScheduleTask and API) then return end
local Eligibility=S.SpellEligibility

S.storageProductId = YUI.GetAddonProductId and YUI:GetAddonProductId(addonName,
    YUI.CoreMode == 'suite' and 'suite' or 'yhud') or YUI.ProductId or 'suite'
local Runtime = { MODULE_ID = 'sound.runtime', previewOwner = {}, context = {}, active = false, readyHistory = {} }
S.Runtime = Runtime
local defaults = { enabled = true, voicePackId = 'yui.default', fallbackDefault = true,
    fallbackTTS = true, language = 'auto', ttsVoice = 'system', rate = 0, volume = 80,
    channel = 'Master', dedup = true, expiry = 5 }
local channels = { Master = true, SFX = true, Music = true, Ambience = true, Dialog = true }

local function PreferenceStore(create)
    local DB = YUI.DB
    if not (DB and DB.IsReady and DB:IsReady() and DB.GetGlobal) then return end
    local global = DB:GetGlobal(S.storageProductId)
    if type(global) ~= 'table' then return end
    if global.sound == nil and create then global.sound = {} end
    return type(global.sound) == 'table' and global.sound or nil
end

function S:SaveVoicePackMetadata(packId)
    local info=self:CopyVoicePackMetadata(self.voicePackMetadata[packId])
    if not info then return end
    local store=PreferenceStore(true)
    if not store then return end
    if type(store.voicePackMetadata)~='table' then store.voicePackMetadata={} end
    store.voicePackMetadata[packId]=info
end

function S:RestoreVoicePackMetadata()
    local store=PreferenceStore(false)
    local saved=store and store.voicePackMetadata
    for id,info in pairs(type(saved)=='table' and saved or {}) do
        if type(id)=='string' and id~='' and #id<=128 and not id:find('[%z\1-\31\127|]') then
            local copy=self:CopyVoicePackMetadata(info)
            if not self.voicePacks[id] then self.voicePackMetadata[id]=copy
            else self.voicePackMetadata[id]=self:PreserveVoicePackIdentity(self.voicePackMetadata[id],copy,id) end
        end
    end
    if store and self._voicePackIdentityStore~=store then
        self.voicePackAnchors=type(store.voicePackAnchors)=='table' and store.voicePackAnchors or {}
        self.voicePackSources=self:CopyVoicePackSources(store.voicePackSources or {}) or {}
        self._voicePackIdentityStore=store
    end
    local order=store and (store.voicePackOrder or {store.voicePackId})
    self:RebuildVoicePackIdentities(order)
    if store then store.voicePackAnchors=self.voicePackAnchors end
    -- Registration may happen before Service or the product database is ready.
    for id in pairs(self.voicePacks) do self:SaveVoicePackMetadata(id) end
end

function S:SetVoicePackSources(sources)
    self.voicePackSources=sources
    local store=PreferenceStore(true)
    if store then store.voicePackSources=sources end
    self:RebuildVoicePackIdentities(store and store.voicePackOrder)
end

local function NormalizePreferences(raw)
    local result = {}
    for key, value in pairs(defaults) do
        local candidate = raw and raw[key]
        result[key] = candidate == nil and value or candidate
    end
    for _, key in ipairs({ 'enabled', 'fallbackDefault', 'fallbackTTS', 'dedup' }) do
        if type(result[key]) ~= 'boolean' then return nil, 'invalid-preferences' end
    end
    for key, bounds in pairs({ rate = { -10, 10 }, volume = { 0, 100 }, expiry = { 1, 60 } }) do
        local value = result[key]
        if type(value) ~= 'number' or value ~= value or value < bounds[1] or value > bounds[2] then
            return nil, 'invalid-preferences'
        end
    end
    if not channels[result.channel] or type(result.voicePackId) ~= 'string' or result.voicePackId == ''
        or #result.voicePackId > 128 or type(result.language) ~= 'string'
        or (result.language ~= 'auto' and not result.language:match('^%l%l%u%u$')) then
        return nil, 'invalid-preferences'
    end
    if result.ttsVoice ~= 'system' and (type(result.ttsVoice) ~= 'number' or result.ttsVoice < 0
        or result.ttsVoice % 1 ~= 0) then return nil, 'invalid-preferences' end
    local order=raw and raw.voicePackOrder
    result.voicePackOrder={}
    if order~=nil then
        if type(order)~='table' then return nil,'invalid-preferences' end
        local count,seen=0,{}
        for index,id in pairs(order) do
            if type(index)~='number' or index%1~=0 or index<1 or index>128
                or type(id)~='string' or id=='' or #id>128 or id:find('[%z\1-\31\127|]') or seen[id] then
                return nil,'invalid-preferences'
            end
            seen[id]=true;count=count+1;result.voicePackOrder[index]=id
        end
        if count~=#result.voicePackOrder then return nil,'invalid-preferences' end
        for index=1,count do if not result.voicePackOrder[index] then return nil,'invalid-preferences' end end
    else
        -- Retain the former selection; append Yanxi only when absent.
        result.voicePackOrder[1]=result.voicePackId
    end
    local hasDefault=false
    for _,id in ipairs(result.voicePackOrder) do
        if id=='yui.default' then hasDefault=true;break end
    end
    if not hasDefault then
        if #result.voicePackOrder>=128 then return nil,'invalid-preferences' end
        result.voicePackOrder[#result.voicePackOrder+1]='yui.default'
    end
    result.fallbackDefault=true
    result.voicePackId=result.voicePackOrder[1]
    return result
end

function S:GetPreferences()
    local store = PreferenceStore(false)
    local prefs, code = NormalizePreferences(store)
    if not prefs then return nil, code end
    local db = YUI.DB and YUI.DB.GetAceDB and YUI.DB:GetAceDB(self.storageProductId)
    local key = db and db.keys and db.keys.char
    local character = type(key) == 'string' and store and type(store.characters) == 'table' and store.characters[key]
    if type(character) == 'table' and type(character.enabled) == 'boolean' then
        prefs.enabled = character.enabled
    else
        local old = db and db.global and db.global.consolePreferences
        old = type(old) == 'table' and type(old.characters) == 'table' and key and old.characters[key]
        if type(old) == 'table' and old.soundEnabled == false then prefs.enabled = false end
    end
    prefs.voicePackOrder=self:GetEnabledVoicePacks(prefs)
    prefs.voicePackId=prefs.voicePackOrder[1]
    prefs._voicePackOrderRevision=self.voicePackIdentityRevision
    return prefs
end

local function Options(prefs)
    return S:GetPlaybackOptions(prefs)
end

function Runtime:Resolve(sound, prefs)
    if sound.kind == 'voice' then
        local options = Options(prefs)
        local resource, code = S:ResolveEntry(sound.value, options)
        if resource then resource.options = options end
        return resource, code
    elseif sound.kind == 'tts' then
        return { kind = 'tts', value = sound.value }
    end
    local kind, value, _, code = S:Resolve(sound.kind .. ':' .. sound.value)
    if not kind then return nil, code end
    return { kind = kind, value = value }
end

local PlayResource
local function UseNotificationFallback(resource)
    local fallback = resource.notificationFallback
    if not fallback or resource.notificationFallbackUsed then return false end
    resource.notificationFallbackUsed = true
    resource.kind, resource.value, resource.duration = fallback.kind, fallback.value, nil
    resource.entryId, resource.options, resource.packId = nil, nil, nil
    resource.fallback = true
    return true
end

local function CompleteTTS(token, success)
    local receipt = Runtime.playback.busy
    if success == false and receipt and receipt.token == token and not receipt.canceled
        and UseNotificationFallback(receipt.resource) then
        local ok, handle = PlayResource(receipt.resource, token)
        if ok then
            receipt.resource.notificationFallbackPlayed = true
            receipt.resource.notificationFallbackHandle = handle
            receipt.handle = handle
            Runtime.playback:_ScheduleCheck(GetTime() + 0.1)
            return
        end
    end
    Runtime.playback:Complete(token, success)
end

PlayResource = function(resource, token)
    local binding=resource.readyBinding
    if binding and (not binding.active or Runtime.engine:IsReadySuppressed()
        or resource.readyGeneration~=Runtime.engine.readyGeneration) then return false end
    local prefs = resource.preferences
    while resource do
        if (resource.kind ~= 'tts' or resource.notificationFallback) and API.GetOutputIssue then
            local issue = API.GetOutputIssue()
            if issue then Runtime.lastIssue = issue; return false end
        end
        if resource.kind == 'tts' then
            local voice = prefs.ttsVoice == 'system' and Runtime.tts:GetSystemVoice() or prefs.ttsVoice
            local ok, code = Runtime.tts:Speak(token, resource.value, voice, prefs.rate, prefs.volume, CompleteTTS)
            if S.DebugTiming and S.DebugTiming.enabled then S.DebugTiming:Record('tts-output',token,ok,code,resource.value) end
            -- A synchronous failure event may already have switched this same
            -- receipt to native audio. Preserve its handle in the submit return.
            if resource.notificationFallbackPlayed then return true, resource.notificationFallbackHandle end
            if ok then
                if resource.readyReceipt then
                    resource.readyReceipt.outputAt,resource.readyReceipt.outputKind=GetTime(),'tts-requested'
                end
                return true
            end
            Runtime.lastIssue = code
            if not UseNotificationFallback(resource) then return false end
        else
            local play = resource.kind == 'kit' and API.PlayKit or API.PlayFile
            local ok, handle = play(resource.value, prefs.channel)
            if S.DebugTiming and S.DebugTiming.enabled then S.DebugTiming:Record('audio-output',token,ok,resource.kind,resource.value) end
            if ok then
                Runtime.lastFile,Runtime.lastFileAt,Runtime.lastFilePreview=resource.value,GetTime(),resource.preview==true
                if resource.readyReceipt then
                    resource.readyReceipt.outputAt,resource.readyReceipt.outputKind=GetTime(),resource.kind
                    resource.readyReceipt.outputValue=resource.value
                end
                return true, handle
            end
            local fallback, code
            if resource.entryId and resource.options and resource.packId then
                local options = resource.options
                options.unavailablePacks = options.unavailablePacks or {}
                options.unavailablePacks[resource.packId] = true
                fallback, code = S:ResolveEntry(resource.entryId, options)
            end
            if fallback then
                -- Keep fallback inside the original coordinator receipt.
                resource.kind, resource.value, resource.duration = fallback.kind, fallback.value, fallback.duration
                resource.packId, resource.fallback = fallback.packId, true
            elseif not UseNotificationFallback(resource) then
                Runtime.lastIssue = code or 'play-failed'
                return false
            end
        end
    end
    return false
end

Runtime.tts = S.TTS.New(YUI.Event, C_VoiceChat, GetTime)
Runtime.playback = S.Playback.New({
    now = GetTime,
    schedule = function(owner, key, at, callback) return Monitor:ScheduleTask(owner, key, at, callback) end,
    cancel = function(owner, key) return Monitor:CancelTask(owner, key) end,
    play = PlayResource, stop = API.Stop, isPlaying = API.IsPlaying,
    stopPreviewTTS = function(token) return Runtime.tts:Stop(token) end,
    result = function(_, reason)
        Runtime.lastPlaybackResult = reason
        if YUI.Event then YUI.Event:Emit('YUI_SOUND_PLAYBACK_CHANGED', reason) end
    end,
})
Runtime.forecast = S.Forecast.New(Monitor, {
    now = GetTime, stop = API.Stop, isPlaying = API.IsPlaying,
    play = function(job)
        local play=job.kind=='kit' and API.PlayKit or API.PlayFile
        return play(job.value, Runtime.preferences.channel)
    end,
    preemptFiles = function(occurrence)
        Runtime.playback:Hold(occurrence)
        return Runtime.playback:PreemptFile()
    end,
    release = function(occurrence) Runtime.playback:ReleaseHold(occurrence) end,
})

function S:Submit(owner, key, sound, preview, readyReceipt)
    local ready=not preview and Runtime.engine:IsReadyBinding(owner)
    if ready and (Runtime.engine:IsReadySuppressed() or not owner.active) then return nil,'ready-suppressed' end
    local prefs, code = self:GetPreferences()
    if not prefs then return nil, code end
    if not preview and not prefs.enabled then return nil, 'sound-disabled' end
    if sound.kind ~= 'tts' and API.GetOutputIssue then
        local issue = API.GetOutputIssue()
        if issue then Runtime.lastIssue = issue; return nil, issue end
    end
    local resource
    resource, code = Runtime:Resolve(sound, prefs)
    if not resource then Runtime.lastIssue = code; return nil, code end
    resource.preferences = prefs
    resource.preview = preview == true
    if ready then
        resource.readyBinding,resource.readyGeneration=owner,Runtime.engine.readyGeneration
        resource.readyReceipt=readyReceipt
    end
    if not prefs.dedup then
        Runtime.requestSerial = (Runtime.requestSerial or 0) + 1
        key = key .. ':' .. Runtime.requestSerial
    end
    return Runtime.playback:Submit(owner, key, resource, GetTime() + prefs.expiry)
end

-- Optional public provider: independent of which product loaded shared Core.
local NotificationProvider = { apiVersion = 1 }
S.NotificationProvider = NotificationProvider

function NotificationProvider:GetStatus()
    if not Runtime.active then
        return false, Runtime.notificationStarted and 'module-disabled' or 'provider-not-ready'
    end
    if not (YUI.DB and YUI.DB.IsReady and YUI.DB:IsReady()) then return false, 'provider-not-ready' end
    local prefs, code = S:GetPreferences()
    return true, not prefs and code or not prefs.enabled and 'sound-disabled' or nil, prefs
end

function NotificationProvider:Resolve(selection, options)
    if selection.kind == 'native' then return YUI.NotificationSound:ResolveNative(options) end
    local prefs, code = S:GetPreferences()
    if not prefs then return nil, code end
    return Runtime:Resolve(selection, prefs)
end

function NotificationProvider:GetChoices(source)
    local result = {}
    if source == 'all' or source == 'voice' then
        for _, entry in ipairs(S:GetEntries()) do
            result[#result + 1] = { kind = 'voice', value = entry.id, label = entry.name }
        end
    end
    if source == 'all' or source == 'system' then
        for _, choice in ipairs(S:GetSoundChoices({ source = 'system' })) do
            result[#result + 1] = { kind = 'system', value = choice.value:match('^system:(.+)$'),
                label = choice.text, available = choice.available }
        end
    end
    return result
end

function NotificationProvider:Submit(owner, key, selection, options, preview)
    if selection.kind == 'none' then return false, 'sound-none' end
    local ready, code, prefs = self:GetStatus()
    if not ready or (code and not (preview and code == 'sound-disabled')) then return false, code end
    if not prefs then return false, code end
    local channel = options and options.channel
    if channel == 'Master' or channel == 'SFX' or channel == 'Music' or channel == 'Ambience' or channel == 'Dialog' then
        local overridden = {}
        for name, value in pairs(prefs) do overridden[name] = value end
        overridden.channel = channel
        prefs = overridden
    end
    local issue = API.GetOutputIssue and API.GetOutputIssue()
    if issue then return false, issue end
    local native = YUI.NotificationSound:ResolveNative(options)
    local resource
    if selection.kind == 'native' then resource = native
    else resource, code = Runtime:Resolve(selection, prefs) end
    local resolved = resource ~= nil
    local special=selection.kind=='voice' and S:ParseSpecialVoice(selection.value)~=nil
    if special and not resource then return false,code end
    if not resource then resource = native end
    if not resource then return false, code or 'missing-native-sound' end
    if selection.kind ~= 'native' and not special then resource.notificationFallback = native end
    if not resolved then resource.notificationFallbackUsed = true end
    resource.preferences, resource.preview = prefs, preview == true
    if not prefs.dedup then
        Runtime.requestSerial = (Runtime.requestSerial or 0) + 1
        key = key .. ':' .. Runtime.requestSerial
    end
    return Runtime.playback:Submit(owner, key, resource, GetTime() + prefs.expiry)
end

function NotificationProvider:CancelOwner(owner)
    Runtime.playback:CancelOwner(owner)
    return not (Runtime.playback.busy and Runtime.playback.busy.owner == owner)
end

function S:PreviewEntry(id)
    self:StopPreview()
    return self:Submit(Runtime.previewOwner, 'preview', { kind = 'voice', value = id }, true)
end

function S:PreviewRandomEntry(packId)
    self:StopPreview()
    local prefs,code=self:GetPreferences()
    if not prefs then return nil,code end
    local issue=API.GetOutputIssue and API.GetOutputIssue()
    if issue then return nil,issue end
    packId=packId or self:GetEnabledVoicePacks(prefs)[1]
    local pack=self:GetVoicePack(packId)
    if not pack then return nil,'missing-recording' end
    local candidates={}
    for _,entry in ipairs(self:GetEntries()) do
        if pack.entries[entry.id] then candidates[#candidates+1]=entry.id end
    end
    for _,entry in ipairs(self:GetSpecialEntries(packId)) do candidates[#candidates+1]=entry.id end
    if #candidates==0 then return nil,'missing-recording' end
    local id=candidates[math.random(#candidates)]
    local resource
    resource,code=self:ResolveEntry(id,
        {packId=packId,fallbackDefault=false,fallbackTTS=false})
    if not resource then return nil,code end
    resource.preferences,resource.preview=prefs,true
    -- No fallback options: a failed audition must not switch voice packs or use TTS.
    local ok
    ok,code=Runtime.playback:Submit(Runtime.previewOwner,'preview',resource,GetTime()+prefs.expiry)
    return ok,code,ok and id or nil
end

-- Author auditions bypass fallback at both resolution and actual file playback.
function S:PreviewVoicePackEntry(packId,id)
    self:StopPreview()
    local prefs,code=self:GetPreferences()
    if not prefs then return nil,code end
    local resource
    resource,code=self:ResolveEntry(id,{packId=packId,fallbackDefault=false,fallbackTTS=false})
    if not resource then return nil,code end
    resource.preferences,resource.preview=prefs,true
    return Runtime.playback:Submit(Runtime.previewOwner,'preview',resource,GetTime()+prefs.expiry)
end

function S:PreviewVoicePackForecast(packId,introId,endingId,count)
    self:StopPreview()
    local prefs,code=self:GetPreferences()
    if not prefs then return nil,code end
    count=count or 3
    if type(count)~='number' or count<1 or count>10 or count%1~=0 then return nil,'invalid-forecast' end
    local options={packId=packId,fallbackDefault=false,fallbackTTS=false}
    local intro,ending,recordings
    intro,code=self:ResolveEntry(introId,options)
    if not intro then return nil,code end
    ending,code=self:ResolveEntry(endingId,options)
    if not ending then return nil,code end
    if not intro.duration then return nil,'invalid-forecast-duration' end
    recordings={}
    local digitIds={'VC-6b86b273','VC-d4735e3a','VC-4e074085','VC-4b227777','VC-ef2d127d',
        'VC-e7f6c011','VC-7902699b','VC-2c624232','VC-19581e27','VC-4a44dc15'}
    for index=1,count do
        recordings[index],code=self:ResolveEntry(digitIds[index],options)
        if not recordings[index] then return nil,code end
    end
    Runtime.preferences=prefs
    return Runtime.forecast:Start(Runtime.previewOwner,'pack-preview',{targetAt=GetTime()+intro.duration+count+1,
        countdown=count,gap=0.5,introduction=intro,ending=ending,digits=recordings})
end

function S:StopPreview()
    Monitor:CancelTasks(Runtime.previewOwner)
    Runtime.playback:CancelOwner(Runtime.previewOwner)
    Runtime.forecast:CancelOwner(Runtime.previewOwner)
end

function S:PreviewEventWindow(sound,ending)
    local kind=ending and (sound.endingKind or 'voice') or (sound.introKind or 'voice')
    if kind=='none' then return true end
    return self:Submit(Runtime.previewOwner,'preview',
        {kind=kind,value=ending and sound.ending or sound.value},true)
end

local function PlayRule(rule, binding, segment, readyReceipt)
    if S.DebugTiming and S.DebugTiming.enabled then
        S.DebugTiming:Record('rule-submit',S.DebugTiming:Identity(binding),rule.id,rule.object.id,rule.trigger.event,binding.fallbackRequired,segment)
    end
    if binding.fallbackRequired and rule.trigger.extension~='boiling-point' and rule.trigger.extension~='bone-shield' then return nil,'native-aura-direct-playback' end
    local ok,code
    if rule.sound.kind=='eventWindow' or rule.sound.kind=='boneShield' then
        local stacks=rule.sound.kind=='boneShield' and segment=='stacks'
        local intro=stacks or (rule.trigger.extension=='boiling-point' and segment=='manual')
        local kind=intro and (rule.sound.introKind or 'voice') or (rule.sound.endingKind or 'voice')
        if kind=='none' then return true end
        local function SubmitSegment()
            return S:Submit(binding,stacks and 'bone-stacks' or intro and 'boiling-manual' or 'window-end',
                {kind=kind,value=intro and rule.sound.value or rule.sound.ending})
        end
        ok,code=SubmitSegment()
    elseif rule.sound.kind == 'forecast' then ok,code=S:StartForecast(binding, binding.targetAt, rule.sound)
    else ok,code=S:Submit(binding, 'trigger', rule.sound, nil, readyReceipt) end
    binding.lastTriggerAt=GetTime(); binding.playbackIssue=not ok and code or nil
    if readyReceipt then
        readyReceipt.triggerAt=binding.lastTriggerAt
        readyReceipt.object=rule.object.id
        readyReceipt.event=rule.trigger.event
        readyReceipt.voice=rule.sound.value
        readyReceipt.accepted=ok==true
        readyReceipt.playbackIssue=binding.playbackIssue
        local history=Runtime.readyHistory
        if #history>=8 then table.remove(history,1) end
        history[#history+1]=readyReceipt
    end
    if S.DebugTiming and S.DebugTiming.enabled then S.DebugTiming:Record('rule-result',S.DebugTiming:Identity(binding),ok,code) end
    if not ok then Runtime.lastIssue=code end
    return ok,code
end

local digits = { 'VC-6b86b273', 'VC-d4735e3a', 'VC-4e074085', 'VC-4b227777', 'VC-ef2d127d',
    'VC-e7f6c011', 'VC-7902699b', 'VC-2c624232', 'VC-19581e27', 'VC-4a44dc15' }
local function ResolveForecastPart(kind,value,options)
    if kind=='voice' then
        local resource,code=S:ResolveEntry(value,options)
        if not resource and S:ParseSpecialVoice(value) then return {kind='none'} end
        return resource,code
    end
    if (kind~='system' and kind~='lsm') or type(value)~='string' or value=='' then return nil,'invalid-forecast-sound' end
    local resolved,file,_,why=S:Resolve(kind..':'..value)
    if not resolved then return nil,why end
    return {kind=resolved,value=file}
end
function S:StartForecast(owner, targetAt, sound)
    Runtime.forecast:CancelOwner(owner)
    if type(sound)~='table' or type(sound.countdown)~='number' or sound.countdown<1
        or sound.countdown>10 or sound.countdown%1~=0 then return nil,'invalid-forecast' end
    local prefs, code = self:GetPreferences()
    if not prefs then return nil, code end
    local preview=owner==Runtime.previewOwner
    if not prefs.enabled and not preview then return nil, 'sound-disabled' end
    if not targetAt then return nil, 'prediction-duration-unavailable' end
    local options, recordings = Options(prefs), {}
    options.fallbackTTS=false
    local duration=self:GetForecastIntroDuration(sound,options)
    if not duration then return nil,'invalid-forecast-duration' end
    local introduction,ending={kind='none'},{kind='none'}
    if sound.introKind~='none' then
        introduction,code=ResolveForecastPart(sound.introKind or 'voice',sound.value,options)
        if not introduction then return nil,code end
        introduction.duration=duration
    end
    if sound.endingKind~='none' then
        ending,code=ResolveForecastPart(sound.endingKind or 'voice',sound.ending,options)
        if not ending then return nil,code end
    end
    local resolve=preview and self.ResolvePreviewEntry or self.ResolveEntry
    for index=1,sound.countdown do
        recordings[index],code = resolve(self,digits[index],options)
        if not recordings[index] then return nil,code end
    end
    return Runtime.forecast:Start(owner,'forecast',{targetAt=targetAt,countdown=sound.countdown,gap=sound.gap,
        introduction=introduction,ending=ending,digits=recordings})
end

Runtime.engine = S.RuleRuntime.New(Monitor, S.RuleRuntime.ResolveCommon, PlayRule,
    function() return Runtime.context end)
if S.EventRuntime and (YUI.IsRetail or YUI.IsForever) then
    Runtime.events=S.EventRuntime.New(YUI.Event,Monitor,
        function(owner,key,sound) return S:Submit(owner,key,sound) end,
        function(owner) Runtime.playback:CancelOwner(owner) end)
end
function S:HasEventRule(id) return Runtime.active and Runtime.events and Runtime.events:Has(id) or false end
function S:NotifyWhisperEvent(event)
    return Runtime.active and Runtime.events and Runtime.events:NotifyWhisper(event) or false
end
if S.AuraPlayback then
    Runtime.auraPlayback=S.AuraPlayback.New(API,Monitor,YUI.Event,
        function(sound,prefs) return Runtime:Resolve(sound,prefs) end)
end

-- On-demand, public-only troubleshooting snapshot; never copy raw source states.
local function PublicIssue(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value)=='string' then return value end
end
function S:GetDiagnostics()
    local result={active=Runtime.active,lastIssue=Runtime.lastIssue,lastPlaybackResult=Runtime.lastPlaybackResult,
        refresh={suspended=Runtime.suspended==true,
            preparedApplies=Runtime.engine.stats.preparedApplies or 0,
            partialApplies=Runtime.engine.stats.partialApplies or 0},
        queued=#Runtime.playback.queue,busy=Runtime.playback.busy~=nil,
        lastLegacySound=Runtime.lastLegacySound,lastLegacyAt=Runtime.lastLegacyAt,
        lastFile=Runtime.lastFile,lastFileAt=Runtime.lastFileAt,lastFilePreview=Runtime.lastFilePreview,
        lastForecastCancelReason=Runtime.lastForecastCancelReason,lastForecastCancelAt=Runtime.lastForecastCancelAt,
        soundOutputIssue=API.GetOutputIssue and API.GetOutputIssue(),
        rules={},filteredRules={},sourceIssues={},readyHistory={}}
    for _,receipt in ipairs(Runtime.readyHistory) do
        local copy={}
        for key,value in pairs(receipt) do
            if not (issecretvalue and issecretvalue(value)) then
                local kind=type(value)
                if kind=='string' or kind=='number' or kind=='boolean' then copy[key]=value end
            end
        end
        result.readyHistory[#result.readyHistory+1]=copy
    end
    for _,rule in ipairs(Runtime.engine.rules or {}) do
        local selected,reason,talentID=S.RuleRuntime.IsSelected(rule,Runtime.context)
        if not selected then
            result.filteredRules[#result.filteredRules+1]={object=rule.object.id,event=rule.trigger.event,
                reason=reason,talentID=talentID}
        end
    end
    for _,issue in ipairs(Runtime.engine.issues or {}) do
        result.sourceIssues[#result.sourceIssues+1]={key=issue.key,reason=PublicIssue(issue.reason)}
    end
    if Runtime.events then
        for _,issue in ipairs(Runtime.events.issues) do
            result.sourceIssues[#result.sourceIssues+1]={key=issue.key,reason=issue.reason}
        end
        for _,binding in pairs(Runtime.events.bindings) do
            result.rules[#result.rules+1]={object=binding.rule.object.id,event='occurred',
                voice=binding.rule.sound.value,lastTriggerAt=binding.lastAt,playbackIssue=binding.playbackIssue,route='notification-event'}
        end
    end
    for _,binding in ipairs(Runtime.engine.bindings) do
        local state=binding.handle and binding.handle.source and binding.handle.source.state or {}
        local restricted=false
        for _,key in ipairs({'secret','cooldownStateSecret','chargeStateSecret'}) do
            local value=state[key]
            if not (issecretvalue and issecretvalue(value)) and value==true then restricted=true end
        end
        local memberRestricted=state.nativeIdentityUnknown==true
        restricted=restricted or memberRestricted
        local auraSoundRegistered
        if binding.nativeAuraUnit then auraSoundRegistered=binding.directAuraRegistered==true end
        result.rules[#result.rules+1]={object=binding.rule.object.id,event=binding.rule.trigger.event,
            voice=binding.rule.sound.value,lastTriggerAt=binding.lastTriggerAt,
            playbackIssue=binding.playbackIssue,sourceIssue=PublicIssue((binding.nativeAuraID or binding.rule.trigger.extension=='boiling-point' or binding.rule.trigger.extension=='bone-shield') and binding.issue or state.stackIssue or state.issue),restricted=restricted,
            route=binding.nativeAuraUnit and 'direct-aura-sound' or nil,
            auraSoundRegistered=auraSoundRegistered,
            auraSoundID=binding.nativeAuraUnit and binding.directAuraID or nil,
            auraSpellID=binding.nativeAuraUnit and binding.nativeAuraID or nil,
            auraUnit=binding.nativeAuraUnit}
    end
    return result
end

local function RecordForecastCancellation(reason, owner)
    if owner and Runtime.forecast.owners[owner] or not owner and next(Runtime.forecast.owners) then
        Runtime.lastForecastCancelReason=PublicIssue(reason) or 'runtime-stop'
        Runtime.lastForecastCancelAt=GetTime()
    end
end

local function SpellIdentity(id)
    local spell, racial=YUI.API.Spell,YUI.API.Racial
    local editor=S.EditorModel
    if editor and editor.CanonicalSpellID then id=editor:CanonicalSpellID(id,editor:CurrentSpec()) end
    if racial and racial.GetEntry(id) then
        id=racial.ResolveKnownSpellID(id)
        if not id then return false,nil end
    end
    id=spell and spell.GetEffectiveSpellID and spell.GetEffectiveSpellID(id) or id
    return id,spell and spell.GetChargeCapability and spell.GetChargeCapability(id)
end

local maintenanceRefresh={PLAYER_REGEN_ENABLED=true,CVAR_UPDATE=true,YUI_MONITOR_SOURCE_STATUS_CHANGED=true,
    ['cooldown-layout-changed']=true}
local function PreservesBindings(reason)
    return maintenanceRefresh[reason]==true or reason=='spell-identity-changed'
        or YUI.IsForever and reason=='forever-catalog-changed'
end

local function PrepareRules(runtime,rules)
    local plan={rules=rules,skills={},talents={}}
    local seen={}
    for _,rule in ipairs(rules) do
        if rule.object.kind~='event' then plan.skills[#plan.skills+1]=rule end
        for id in pairs(rule.talents or {}) do
            if not seen[id] then seen[id]=true;plan.talents[#plan.talents+1]=id end
        end
    end
    if runtime.engine.Prepare then
        local token,code=runtime.engine:Prepare(plan.skills)
        if not token then return nil,code end
        plan.prepared=token
    end
    return plan
end

-- One synchronous refresh owns this reader. Never store it on the runtime,
-- context or bindings: the next refresh must observe a new native directory.
local function NewCatalogReader(onlyAuras)
    local api=YUI.API and YUI.API.CooldownViewer
    if not YUI.IsRetail or not api or not api.ReadEntries then return end
    local entries
    return function()
        if entries then return entries end
        local current,detail=api:ReadEntries({includeHidden=true,allowUnlearned=true,
            sourceCategories=onlyAuras and {trackedBuff=true,trackedBar=true} or nil})
        -- Keep the resolver's original 512-entry boundary for large catalogs;
        -- filtering must not admit an Aura formerly beyond that boundary.
        if onlyAuras and type(detail)=='table'
            and (detail.total or 0)+(detail.filteredOut or 0)>512 then
            current,detail=api:ReadEntries({includeHidden=true,allowUnlearned=true})
        end
        -- Failed, empty full catalogs and partial reads may recover before the
        -- next consumer. A complete catalog containing only filtered-out skills
        -- has the same stable absence of Auras as its nonempty full snapshot.
        local complete=detail==nil or type(detail)=='table' and (detail.skipped or 0)==0
            and (detail.skippedSources or 0)==0 and not detail.layoutUnavailable
        if complete and type(current)=='table' and (#current>0
            or onlyAuras and type(detail)=='table' and (detail.filteredOut or 0)>0) then
            entries=current
        end
        return current
    end
end

function Runtime:Apply(rules, reason, plan, readNativeAuraEntries)
    if not self.preferences then
        local prefs, code = S:GetPreferences()
        if not prefs then return nil, code end
        self.preferences = prefs
    end
    if self.preferences.enabled==false then
        local normalized,why=S.RuleModel:NormalizeLibrary(rules)
        if not normalized then return nil,why end
        self:Stop('sound-disabled')
        return true
    end
    local code
    if not plan then plan,code=PrepareRules(self,rules) end
    if not plan then return nil,code end
    readNativeAuraEntries=readNativeAuraEntries or NewCatalogReader()
    local manager = YUI.Settings and YUI.Settings.ConfigSets
    local context = { spec = manager and manager:GetCurrentSpecializationKey(), talents = {}, spells = {} }
    context.eligibility=Eligibility.New(context.spec,self.context.eligibility,PreservesBindings(reason),self)
    if S.DebugTiming and S.DebugTiming.enabled then
        S.DebugTiming:Record('context-begin',reason,S.DebugTiming:Identity(context.eligibility),
            S.DebugTiming:Identity(self.context.eligibility),context.spec,PreservesBindings(reason))
    end
    local spell = YUI.API and YUI.API.Spell
    local traitSet, traitsComplete, traitsRead
    local cached = self.traitSnapshot
    if YUI.IsRetail and context.spec and (maintenanceRefresh[reason] or reason=='spell-identity-changed')
        and cached and cached.spec == context.spec then
        traitSet, traitsComplete, traitsRead = cached.selected, true, true
    else
        self.traitSnapshot = nil
    end
    for _,id in ipairs(plan.talents) do
        if YUI.IsRetail and not traitsRead then
            traitsRead = true
            local talent = YUI.API and YUI.API.Talent
            if talent and talent.ReadActiveTraitSpellSet then
                local ok, selected, complete = pcall(talent.ReadActiveTraitSpellSet, {})
                if ok then
                    traitSet, traitsComplete = selected, complete
                    if type(selected) == 'table' and complete == true then
                        self.traitSnapshot = { spec = context.spec, selected = selected }
                    end
                end
            end
        end
        local known = spell and spell.GetKnownState and spell.GetKnownState(id)
        if not YUI.IsRetail then context.talents[id] = known
        elseif traitSet and traitSet[id] == true or known == true then
            context.talents[id] = true
        elseif traitsComplete == true then context.talents[id] = false end
        -- A spellbook miss cannot disprove a passive trait. An incomplete
        -- trait snapshot stays unknown and cannot satisfy a negative gate.
    end
    for _,rule in ipairs(rules) do
        local racial=YUI.API.Racial
        if S.RuleRuntime.IsSelected(rule,context) and (rule.object.kind=='spell'
            or rule.object.kind=='aura' and racial and racial.GetEntry(rule.object.id,'aura')) then
            local entry=context.spells[rule.object.id]
            if not entry then
                local id,charges=SpellIdentity(rule.object.id)
                local previous=self.context.spells and self.context.spells[rule.object.id]
                if charges==nil and PreservesBindings(reason) and previous and previous.id==id
                    and not (self.invalidatedSpells and self.invalidatedSpells[rule.object.id]==true) then
                    charges=previous.charges
                end
                entry={id=id,charges=charges}
                context.spells[rule.object.id]=entry
            end
            context.eligibility:Track(rule,entry.id)
        end
    end
    context.eligibility:Finish()
    local previousContext, previousBindings = self.context, self.engine.bindings
    self.context = context
    local preserveBindings=PreservesBindings(reason) and self.preferences.enabled
        and previousContext.spec==context.spec
    local unit=YUI.API and YUI.API.Unit
    local dead=unit and unit.IsDead and unit.IsDead('player')
    local skillRules=not dead and plan.skills or {}
    local preserveUnchanged=reason=='cooldown-layout-changed' or reason=='YUI_MONITOR_SOURCE_STATUS_CHANGED'
        or self.cooldownLayoutPending and maintenanceRefresh[reason]
    local ok, retained
    if not dead and plan.prepared then
        local changed=YUI.IsRetail and reason=='spell-identity-changed' and preserveBindings and self.invalidatedSpells or nil
        if changed then
            -- APIs can settle during the debounce, after the event's observation.
            -- Reuse only identities and admission states confirmed by this apply.
            local previousRecords=previousContext.eligibility and previousContext.eligibility.records or {}
            for id,current in pairs(context.spells) do
                local previous=previousContext.spells and previousContext.spells[id]
                local oldKnown,newKnown=previousRecords[id],context.eligibility.records[id]
                if not previous or previous.id~=current.id or previous.charges~=current.charges then
                    changed[id]=true
                elseif not changed[id] and newKnown and (not oldKnown or oldKnown.state~=newKnown.state
                    or oldKnown.base~=newKnown.base or oldKnown.origin~=newKnown.origin) then
                    changed[id]='ready'
                end
            end
        end
        ok,code,retained=self.engine:ApplyPrepared(plan.prepared,preserveBindings,preserveUnchanged,changed,readNativeAuraEntries)
    else
        ok,code,retained=self.engine:Apply(skillRules,preserveBindings,preserveUnchanged,readNativeAuraEntries)
    end
    if not ok then
        self.context = previousContext
        if S.DebugTiming and S.DebugTiming.enabled then
            S.DebugTiming:Record('context-apply-failed',reason,code,S.DebugTiming:Identity(context.eligibility),
                S.DebugTiming:Identity(previousContext.eligibility))
        end
        return nil, code
    end
    self.pendingSpellIdentities=nil
    if self.invalidatedSpells then
        local bound,unresolved={}
        for _,binding in ipairs(self.engine.bindings) do bound[S.RuleModel:Key(binding.rule)]=true end
        for _,rule in ipairs(self.engine.rules) do
            local object,racial=rule.object,YUI.API.Racial
            local id=object.id
            if self.invalidatedSpells[id] and (object.kind=='spell'
                or object.kind=='aura' and racial and racial.GetEntry(id,'aura'))
                and S.RuleRuntime.IsSelected(rule,context) and not bound[S.RuleModel:Key(rule)]
                and not (Eligibility.Applies(rule)
                    and not Eligibility.Allows(context,rule,context.spells[id].id)) then
                unresolved=unresolved or {};unresolved[id]=self.invalidatedSpells[id]
            end
        end
        self.invalidatedSpells=unresolved
    end
    for _, binding in ipairs(previousBindings) do
        if not retained[binding] then
            RecordForecastCancellation(reason or 'rules-applied',binding)
            self.playback:CancelOwner(binding)
            self.forecast:CancelOwner(binding)
        end
    end
    if not self.preferences.enabled then self.engine:Stop() end
    if self.auraPlayback then self.auraPlayback:Sync(self.engine.bindings,self.preferences) end
    if self.events then self.events:Apply(rules,self.active and self.preferences.enabled) end
    if S.DebugTiming and S.DebugTiming.enabled then
        local kept=0;for _ in pairs(retained) do kept=kept+1 end
        S.DebugTiming:Record('context-apply',reason,#previousBindings,#self.engine.bindings,kept,
            S.DebugTiming:Identity(context.eligibility))
    end
    return true
end

function Runtime:Refresh()
    local refreshReason=self.pendingRefreshReason or 'refresh'
    self.pendingRefreshReason=nil
    local spellContextChanged=self.spellContextPending
    self.spellContextPending=nil
    Monitor:CancelTask(self, 'context')
    local prefs, code = S:GetPreferences()
    if not prefs then self:Stop(); self.lastIssue = code; return nil, code end
    self.preferences = prefs
    S._activeVoicePackId = prefs.voicePackId
    S._activeVoicePackOrder = prefs.voicePackOrder
    if not prefs.enabled then
        self.suspended=true
        self:UnbindEvents()
        if self.worldReadyOwner then Monitor:CancelTasks(self.worldReadyOwner) end
        self:Stop('sound-disabled')
        self.worldLoading,self.readyResumeAt,self.readyResuming=nil,nil,nil
        self.loadingScreenActive,self.worldLeaving=nil,nil
        self.engine:SetReadySuppressed(false)
        self.context={spells={}}
        self.rulePlan=nil
        if S.RuleStore.ReleaseRuntime then S.RuleStore:ReleaseRuntime() end
        return true
    end
    self.suspended=nil
    if self.active then self:BindEvents() end
    local layoutPending=self.cooldownLayoutPending
    local viewer=YUI.API and YUI.API.CooldownViewer
    local combat=YUI.API and YUI.API.Combat
    if layoutPending and maintenanceRefresh[refreshReason]
        and combat and combat.InCombatLockdown and combat.InCombatLockdown() then
        return nil,'combat'
    end
    local layoutSignature=viewer and viewer.GetLayoutSignature and viewer:GetLayoutSignature()
    if layoutPending then
        local common=Monitor.CommonSources
        if common and common.RefreshNativeAuraBindings then common:RefreshNativeAuraBindings() end
        -- Dragging changes the native preview first. Retry unresolved rules once
        -- the persisted layout changes; hiding also rechecks visible native pools.
        if refreshReason=='cooldown-layout-changed' and layoutSignature
            and layoutSignature==self.cooldownLayoutSignature and #self.engine.issues==0 then
            self.cooldownLayoutPending=nil
            return true
        end
    end
    if S.LegacyMigration and S.LegacyMigration:Run(self) then return true end
    local rules
    if S.RuleStore.ReadRuntime then rules,code=S.RuleStore:ReadRuntime()
    else rules,code=S.RuleStore:Read() end
    if not rules then self:Stop(); self.lastIssue = code; return nil, code end
    local plan=self.rulePlan
    if not plan or plan.rules~=rules then
        plan,code=PrepareRules(self,rules)
        if not plan then return nil,code end
        self.rulePlan=plan
    end
    local editor=S.EditorModel
    local unchangedLayout=YUI.IsRetail and refreshReason=='spell-identity-changed'
        and layoutSignature and layoutSignature==self.cooldownLayoutSignature
        and editor and editor.currentCatalog
        and (not editor.CurrentSpec or editor.currentCatalog.spec==editor:CurrentSpec())
    local refreshEditor=editor and (YUI.IsForever
        or spellContextChanged and refreshReason~='spell-identity-changed'
        or layoutPending and not unchangedLayout or not editor.currentCatalog)
    if layoutPending and unchangedLayout and not refreshEditor then editor.catalogDirty=true end
    local readNativeAuraEntries=NewCatalogReader(not refreshEditor)
    if refreshEditor then S.EditorModel:RefreshCatalog(readNativeAuraEntries) end
    local ok,why=self:Apply(rules,refreshReason,plan,readNativeAuraEntries)
    if ok then
        self.cooldownLayoutSignature=layoutSignature
        self.cooldownLayoutPending=nil
        if layoutPending and YUI.Event then YUI.Event:Emit('YUI_SOUND_BINDING_STATUS_CHANGED') end
    end
    self.pendingSpellIdentities=nil
    if ok and spellContextChanged then
        if YUI.Event then YUI.Event:Emit('YUI_SOUND_CONTEXT_CHANGED') end
    end
    return ok,why
end

function Runtime:OnCatalogChanged(event)
    if self.spellContextPending then return end
    self.spellContextPending=true
    self:OnContextChanged('forever-catalog-changed')
end

function Runtime:OnSpellsChanged(event)
    if self.suspended then return end
    if YUI.IsForever then self:OnCatalogChanged('SPELLS_CHANGED') end
    -- SPELLS_CHANGED also occurs without a talent/identity change. Preserve
    -- delayed casts and playback in that case; no new task or source allocation.
    local changed,pending=nil,self.pendingSpellIdentities
    local eligibility=self.context.eligibility
    if eligibility then eligibility:BeginObservation() end
    for base,previous in pairs(self.context.spells or {}) do
        local observed=pending and pending[base] or previous
        local id,charges=SpellIdentity(base)
        local identityChanged=id~=observed.id or charges~=nil and charges~=observed.charges
        local knownChanged=eligibility and eligibility:Refresh(base,id,event=='UNIT_PET',event)
        if identityChanged or knownChanged then
            changed=changed or {};changed[base]=identityChanged and true or 'ready'
            if S.DebugTiming and S.DebugTiming.enabled then
                S.DebugTiming:Record('context-spell-change',base,observed.id,id,observed.charges,charges,event,identityChanged,knownChanged)
            end
            pending=pending or {}
            if charges==nil and id==observed.id then charges=observed.charges end
            pending[base]={id=id,charges=charges}
        end
    end
    -- Unresolved owners retry on later notifications, without polling or
    -- advancing the applied baseline before a successful reconciliation.
    if not changed and self.invalidatedSpells and not self.spellContextPending then changed={} end
    if changed then
        self.pendingSpellIdentities=pending
        self:OnSpellContextChanged('spell-identity-changed',nil,changed)
    end
end

function Runtime:OnPetChanged(event,unit)
    if unit and unit~='player' then return end
    self:OnSpellsChanged(event)
end

function Runtime:OnEligibilityRevoked(id)
    self:OnSpellContextChanged('spell-identity-changed',nil,{[id]='ready'})
end

function Runtime:OnSpellContextChanged(event, unit, changed)
    if self.suspended then return end
    if unit and unit~='player' and type(unit)=='string' then return end
    if event~='spell-identity-changed' then self.traitSnapshot = nil end
    if event=='spell-identity-changed' and type(changed)=='table' then
        for id,scope in pairs(changed) do
            self.invalidatedSpells=self.invalidatedSpells or {}
            if self.invalidatedSpells[id]~=true then self.invalidatedSpells[id]=scope end
        end
        local affected={}
        local racial=YUI.API.Racial
        self.playback:Hold(self)
        for _,binding in ipairs(self.engine.bindings) do
            local object=binding.rule.object
            if (changed[object.id]==true or changed[object.id]=='ready' and Eligibility.Applies(binding.rule))
                and (object.kind=='spell'
                or object.kind=='aura' and racial and racial.GetEntry(object.id,'aura')) then
                affected[binding]=true
                if S.DebugTiming and S.DebugTiming.enabled then
                    S.DebugTiming:Record('binding-cancel',S.DebugTiming:Identity(binding),object.id,event,changed[object.id])
                end
                RecordForecastCancellation(event,binding)
                self.playback:CancelOwner(binding)
                self.forecast:CancelOwner(binding)
            end
        end
        -- Release changed identities before the debounce; unrelated edges stay live.
        self.engine:Stop(affected)
        if self.auraPlayback then self.auraPlayback:Sync(self.engine.bindings,self.preferences) end
        self.playback:ReleaseHold(self)
    else
        self:Stop(event or 'spell-identity-changed')
    end
    self.spellContextPending=true
    if S.EditorModel and not YUI.IsForever then
        if event=='spell-identity-changed' and YUI.IsRetail then S.EditorModel.catalogDirty=true
        else S.EditorModel.currentCatalog=nil end
    end
    self:OnContextChanged(event or 'spell-identity-changed')
end

function Runtime:OnContextChanged(event)
    if self.active and not self.suspended then
        local reason=PublicIssue(event) or 'context-changed'
        -- Coalescing may narrow preservation, never upgrade a world/full refresh
        -- to maintenance merely because a maintenance event arrived last.
        if not self.pendingRefreshReason or PreservesBindings(self.pendingRefreshReason)
            or not PreservesBindings(reason) then self.pendingRefreshReason=reason end
        if S.DebugTiming and S.DebugTiming.enabled then S.DebugTiming:Record('context-request',reason,self.pendingRefreshReason) end
        Monitor:ScheduleTask(self, 'context', GetTime() + 0.1, Runtime.Refresh)
    end
end

function Runtime:OnCooldownLayoutChanged()
    if not self.active or self.suspended then return end
    -- Native save callbacks only enqueue owned work; no settings reads/writes here.
    self.cooldownLayoutPending=true
    self:OnContextChanged('cooldown-layout-changed')
end

local function ResumeWorldReady()
    local self=Runtime
    if not self.active or self.readyResuming or self.worldLoading
        or not self.readyResumeAt or GetTime()<self.readyResumeAt then return end
    self.readyResuming=true
    local called,resumed=pcall(self.engine.SetReadySuppressed,self.engine,false)
    self.readyResuming=nil
    if not called then
        self.engine:SetReadySuppressed(true)
        self.lastIssue='ready-resume-failed'
        return
    end
    if resumed then
        self.readyResumeAt=nil
        Monitor:CancelTasks(self.worldReadyOwner)
        if S.DebugTiming and S.DebugTiming.enabled then S.DebugTiming:Record('ready-world-resumed') end
    end
end
-- The task primes a timely baseline; the deadline also recovers on demand if
-- scheduling failed. Re-entrant source reads stay gated until priming finishes.
Runtime.engine.resumeReady=ResumeWorldReady

function Runtime:OnWorldReadyChanged(event)
    self.worldReadyOwner=self.worldReadyOwner or {runtime=self}
    self.engine:SetReadySuppressed(true)
    -- Cancel only queued ready speech. Already-playing files and unrelated
    -- notification, aura and forecast owners keep their existing lifecycle.
    for _,binding in ipairs(self.engine.bindings) do
        if self.engine:IsReadyBinding(binding) then self.playback:CancelQueued(binding) end
    end
    if event=='LOADING_SCREEN_ENABLED' then self.loadingScreenActive=true
    elseif event=='LOADING_SCREEN_DISABLED' then self.loadingScreenActive=false
    elseif event=='PLAYER_LEAVING_WORLD' then self.worldLeaving=true
    else self.worldLeaving=false end
    self.worldLoading=self.loadingScreenActive==true or self.worldLeaving==true
    Monitor:CancelTasks(self.worldReadyOwner)
    if self.worldLoading then self.readyResumeAt=nil
    else
        self.readyResumeAt=GetTime()+2
        local ok,code=Monitor:ScheduleTask(self.worldReadyOwner,'ready-world-resume',self.readyResumeAt,ResumeWorldReady)
        if not ok then self.lastIssue=code end
    end
    if S.DebugTiming and S.DebugTiming.enabled then
        S.DebugTiming:Record('ready-world-suppressed',event,self.worldLoading,self.readyResumeAt,self.engine.readyGeneration)
    end
end

function Runtime:OnEnteringWorld(event)
    if YUI.IsRetail or YUI.IsForever then self:OnWorldReadyChanged(event) end
    if YUI.IsRetail then self:OnSpellContextChanged(event)
    else self:OnContextChanged(event) end
end

function Runtime:OnDeath() self:StopSkills('PLAYER_DEAD') end

function Runtime:OnVoicePackChanged(_,packId)
    if not self.active then return end
    local prefs=S:GetPreferences()
    if not prefs or not S:IsVoicePackEnabled(packId,prefs) then return end
    self:Stop('voice-pack-changed')
    self:Refresh()
end

function Runtime:OnProfileChanged(_, database)
    if database == YUI.DB:GetAceDB(S.storageProductId) then
        self:Stop('profile-changed')
        if self.active then self:Refresh() end
        if YUI.Event and YUI.Event.Emit then YUI.Event:Emit('YUI_SOUND_RULES_CHANGED') end
    end
end

function Runtime:StopSkills(reason)
    if S.DebugTiming and S.DebugTiming.enabled then S.DebugTiming:Record('context-stop',reason) end
    if S.LegacyMigration and S.LegacyMigration.Cancel then S.LegacyMigration:Cancel(self) end
    self.traitSnapshot = nil
    Monitor:CancelTasks(self.previewOwner)
    RecordForecastCancellation(reason)
    self.pendingRefreshReason=nil
    self.cooldownLayoutPending=nil
    self.cooldownLayoutSignature=nil
    self.spellContextPending=nil
    self.pendingSpellIdentities=nil
    self.invalidatedSpells=nil
    if self.context.eligibility then self.context.eligibility:Reset() end
    if self.auraPlayback then
        local ok,code=self.auraPlayback:Clear()
        if not ok then self.lastIssue=code end
    end
    self.playback:Hold(self)
    self.forecast:CancelAll()
    for _,binding in ipairs(self.engine.bindings) do self.playback:CancelOwner(binding) end
    self.playback:CancelOwner(self.previewOwner)
    self.engine:Stop()
    Monitor:CancelTasks(self)
    self.playback:ReleaseHold(self)
end

function Runtime:Stop(reason)
    self:StopSkills(reason)
    if self.events then self.events:Stop() end
    self.playback:CancelAll()
end

function S:SetPreferences(raw)
    -- Keep callers editing the former single-pack fields working, including
    -- callers retaining an older preference snapshot. Order-only writes stay canonical.
    local previous=self:GetPreferences()
    if previous and type(raw)=='table' and type(raw.voicePackOrder)=='table' then
        if raw.voicePackId~=nil and raw.voicePackId~=previous.voicePackId and raw.voicePackId~=raw.voicePackOrder[1] then
            local legacy={};for key,value in pairs(raw) do if key~='voicePackOrder' then legacy[key]=value end end
            raw=legacy
        end
    end
    local prefs, code = NormalizePreferences(raw)
    if not prefs then return nil, code end
    local store = PreferenceStore(true)
    if not store then return nil, 'db-not-ready' end
    local db = YUI.DB and YUI.DB.GetAceDB and YUI.DB:GetAceDB(self.storageProductId)
    local characterKey = db and db.keys and db.keys.char
    for key in pairs(defaults) do
        if key ~= 'enabled' or type(characterKey) ~= 'string' then store[key] = prefs[key] end
    end
    store.voicePackOrder=prefs.voicePackOrder
    self._activeVoicePackOrder=prefs.voicePackOrder
    self._activeVoicePackId=prefs.voicePackId
    if type(characterKey) == 'string' then
        if type(store.characters) ~= 'table' then store.characters = {} end
        if type(store.characters[characterKey]) ~= 'table' then store.characters[characterKey] = {} end
        store.characters[characterKey].enabled = prefs.enabled
    end
    Runtime:Stop()
    if Runtime.active then Runtime:Refresh() end
    if YUI.Event then YUI.Event:Emit('YUI_SOUND_PREFERENCES_CHANGED') end
    return true
end

function Runtime:BindEvents()
    if self.eventsBound then return end
    self.eventsBound=true
    local viewer=YUI.API and YUI.API.CooldownViewer
    if viewer and viewer.WatchLayoutChanges then
        self.cooldownLayoutWatch=viewer:WatchLayoutChanges(self,Runtime.OnCooldownLayoutChanged)
    end
    for _, event in ipairs({ 'PLAYER_ALIVE', 'PLAYER_UNGHOST',
        'PLAYER_REGEN_ENABLED', 'CVAR_UPDATE', 'YUI_MONITOR_SOURCE_STATUS_CHANGED' }) do
        YUI.Event:On(event, 'OnContextChanged', self, { moduleId = self.MODULE_ID })
    end
    YUI.Event:On('PLAYER_DEAD', 'OnDeath', self, { moduleId = self.MODULE_ID })
    YUI.Event:On('YUI_SOUND_PACKS_CHANGED', 'OnVoicePackChanged', self, { moduleId = self.MODULE_ID })
    for _, event in ipairs({'PLAYER_SPECIALIZATION_CHANGED','PLAYER_TALENT_UPDATE'}) do
        YUI.Event:On(event, 'OnSpellContextChanged', self, { moduleId = self.MODULE_ID })
    end
    YUI.Event:On('SPELLS_CHANGED', 'OnSpellsChanged', self, { moduleId = self.MODULE_ID })
    YUI.Event:On('PLAYER_ENTERING_WORLD', 'OnEnteringWorld', self, { moduleId = self.MODULE_ID })
    if YUI.IsRetail or YUI.IsForever then
        for _,event in ipairs({'PLAYER_LEAVING_WORLD','LOADING_SCREEN_ENABLED','LOADING_SCREEN_DISABLED'}) do
            YUI.Event:On(event,'OnWorldReadyChanged',self,{moduleId=self.MODULE_ID})
        end
        local lifecycle=YUI.Lifecycle
        if lifecycle and lifecycle.IsReady then
            self:OnWorldReadyChanged(lifecycle:IsReady('YUI_WORLD_READY') and 'sound-enabled' or 'PLAYER_LEAVING_WORLD')
        end
    end
    if YUI.IsRetail then
        YUI.Event:On('UNIT_PET','OnPetChanged',self,{moduleId=self.MODULE_ID,unit='player'})
        YUI.Event:On('PET_BAR_UPDATE','OnPetChanged',self,{moduleId=self.MODULE_ID})
    end
    if YUI.IsRetail or YUI.IsForever then YUI.Event:On('TRAIT_CONFIG_UPDATED', 'OnSpellContextChanged', self, { moduleId = self.MODULE_ID }) end
    if YUI.IsForever then
        for _,event in ipairs({'COOLDOWN_VIEWER_DATA_LOADED','COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED','COOLDOWN_VIEWER_TABLE_HOTFIXED','SPELL_TEXT_UPDATE'}) do
            YUI.Event:On(event,'OnCatalogChanged',self,{moduleId=self.MODULE_ID})
        end
    end
end

function Runtime:UnbindEvents()
    local viewer=YUI.API and YUI.API.CooldownViewer
    if viewer and viewer.StopWatchingLayoutChanges then viewer:StopWatchingLayoutChanges(self.cooldownLayoutWatch) end
    self.cooldownLayoutWatch=nil
    self.eventsBound=nil
    YUI.Event:OffOwner(self)
end

function Runtime:OnEnable()
    if self.active then return end
    self.active=true
    self.notificationStarted=true
    self:Refresh()
    YUI.Event:Emit('YUI_NOTIFICATION_SOUND_CAPABILITIES_CHANGED')
end

function Runtime:OnDisable()
    self.active = false
    if self.worldReadyOwner then Monitor:CancelTasks(self.worldReadyOwner) end
    self.worldLoading,self.readyResumeAt,self.readyResuming=nil,nil,nil
    self.loadingScreenActive,self.worldLeaving=nil,nil
    self:UnbindEvents()
    self:Stop()
    self.engine:SetReadySuppressed(false)
    self.suspended=nil
    self.rulePlan=nil
    if S.RuleStore.ReleaseRuntime then S.RuleStore:ReleaseRuntime() end
    YUI.Event:Emit('YUI_NOTIFICATION_SOUND_CAPABILITIES_CHANGED')
end

function Runtime:RegisterModule()
    if self.registered then return end
    S:RestoreVoicePackMetadata()
    if not (YUI.Module and YUI.Module.Register) then return end
    self.registered = not not YUI.Module:Register({ id = self.MODULE_ID, product = S.storageProductId,
        owner = self, dependencies = { 'core.db', 'core.event' },
        getEnabled = function() return true end, OnEnable = 'OnEnable', OnDisable = 'OnDisable',
        OnProfileChanged = 'OnProfileChanged' })
end

if YUI.DB and YUI.DB.IsReady and YUI.DB:IsReady() then Runtime:RegisterModule()
elseif YUI.Event and YUI.Event.Once then
    YUI.Event:Once('YUI_DB_READY', 'RegisterModule', Runtime, { moduleId = Runtime.MODULE_ID })
end

return Runtime
