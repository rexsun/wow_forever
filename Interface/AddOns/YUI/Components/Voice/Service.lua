local addonName, namespace = ...
local YUI = _G.YUI or namespace
local S = YUI and YUI.Sound
if not (S and S.Playback and S.RuleRuntime and S.RuleStore and S.TTS and S.Forecast) then return end
if S.Runtime then return end
local Monitor, API = YUI.Monitor, YUI.API and YUI.API.Sound
if not (Monitor and Monitor.ScheduleTask and API) then return end

S.storageProductId = YUI.GetAddonProductId and YUI:GetAddonProductId(addonName,
    YUI.CoreMode == 'suite' and 'suite' or 'yhud') or YUI.ProductId or 'suite'
local Runtime = { MODULE_ID = 'sound.runtime', previewOwner = {}, context = {}, active = false }
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
    return prefs
end

local function Options(prefs)
    return { packId = prefs.voicePackId, fallbackDefault = prefs.fallbackDefault,
        fallbackTTS = prefs.fallbackTTS, language = prefs.language ~= 'auto' and prefs.language or nil }
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
            if ok then return true end
            Runtime.lastIssue = code
            if not UseNotificationFallback(resource) then return false end
        else
            local play = resource.kind == 'kit' and API.PlayKit or API.PlayFile
            local ok, handle = play(resource.value, prefs.channel)
            if S.DebugTiming and S.DebugTiming.enabled then S.DebugTiming:Record('audio-output',token,ok,resource.kind,resource.value) end
            if ok then
                Runtime.lastFile,Runtime.lastFileAt,Runtime.lastFilePreview=resource.value,GetTime(),resource.preview==true
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

function S:Submit(owner, key, sound, preview)
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
    local ready, code, prefs = self:GetStatus()
    if not ready or (code and not (preview and code == 'sound-disabled')) then return false, code end
    if not prefs then return false, code end
    local issue = API.GetOutputIssue and API.GetOutputIssue()
    if issue then return false, issue end
    local native = YUI.NotificationSound:ResolveNative(options)
    local resource
    if selection.kind == 'native' then resource = native
    else resource, code = Runtime:Resolve(selection, prefs) end
    local resolved = resource ~= nil
    if not resource then resource = native end
    if not resource then return false, code or 'missing-native-sound' end
    if selection.kind ~= 'native' then resource.notificationFallback = native end
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

function S:PreviewRandomEntry()
    self:StopPreview()
    local prefs,code=self:GetPreferences()
    if not prefs then return nil,code end
    local issue=API.GetOutputIssue and API.GetOutputIssue()
    if issue then return nil,issue end
    local pack=self.voicePacks[prefs.voicePackId]
    if not pack then return nil,'missing-recording' end
    local candidates={}
    for _,entry in ipairs(self:GetEntries()) do
        if pack.entries[entry.id] then candidates[#candidates+1]=entry.id end
    end
    if #candidates==0 then return nil,'missing-recording' end
    local resource
    resource,code=self:ResolveEntry(candidates[math.random(#candidates)],
        {packId=prefs.voicePackId,fallbackDefault=false,fallbackTTS=false})
    if not resource then return nil,code end
    resource.preferences,resource.preview=prefs,true
    -- No fallback options: a failed audition must not switch voice packs or use TTS.
    return Runtime.playback:Submit(Runtime.previewOwner,'preview',resource,GetTime()+prefs.expiry)
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

local function PlayRule(rule, binding, segment)
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
        ok,code=S:Submit(binding,stacks and 'bone-stacks' or intro and 'boiling-manual' or 'window-end',
            {kind=kind,value=intro and rule.sound.value or rule.sound.ending})
    elseif rule.sound.kind == 'forecast' then ok,code=S:StartForecast(binding, binding.targetAt, rule.sound)
    else ok,code=S:Submit(binding, 'trigger', rule.sound) end
    binding.lastTriggerAt=GetTime(); binding.playbackIssue=not ok and code or nil
    if S.DebugTiming and S.DebugTiming.enabled then S.DebugTiming:Record('rule-result',S.DebugTiming:Identity(binding),ok,code) end
    if not ok then Runtime.lastIssue=code end
    return ok,code
end

local digits = { 'VC-6b86b273', 'VC-d4735e3a', 'VC-4e074085', 'VC-4b227777', 'VC-ef2d127d',
    'VC-e7f6c011', 'VC-7902699b', 'VC-2c624232', 'VC-19581e27', 'VC-4a44dc15' }
local function ResolveForecastPart(kind,value,options)
    if kind=='voice' then return S:ResolveEntry(value,options) end
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
        queued=#Runtime.playback.queue,busy=Runtime.playback.busy~=nil,
        lastLegacySound=Runtime.lastLegacySound,lastLegacyAt=Runtime.lastLegacyAt,
        lastFile=Runtime.lastFile,lastFileAt=Runtime.lastFileAt,lastFilePreview=Runtime.lastFilePreview,
        lastForecastCancelReason=Runtime.lastForecastCancelReason,lastForecastCancelAt=Runtime.lastForecastCancelAt,
        soundOutputIssue=API.GetOutputIssue and API.GetOutputIssue(),
        rules={},filteredRules={},sourceIssues={}}
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
    if racial and racial.GetEntry(id) then
        id=racial.ResolveKnownSpellID(id)
        if not id then return false,nil end
    end
    id=spell and spell.GetEffectiveSpellID and spell.GetEffectiveSpellID(id) or id
    return id,spell and spell.GetChargeCapability and spell.GetChargeCapability(id)
end

local maintenanceRefresh={PLAYER_REGEN_ENABLED=true,CVAR_UPDATE=true,YUI_MONITOR_SOURCE_STATUS_CHANGED=true}
local function PreservesBindings(reason)
    return maintenanceRefresh[reason]==true or reason=='spell-identity-changed'
end

function Runtime:Apply(rules, reason)
    if not self.preferences then
        local prefs, code = S:GetPreferences()
        if not prefs then return nil, code end
        self.preferences = prefs
    end
    local manager = YUI.Settings and YUI.Settings.ConfigSets
    local context = { spec = manager and manager:GetCurrentSpecializationKey(), talents = {}, spells = {} }
    local spell = YUI.API and YUI.API.Spell
    local traitSet, traitsComplete, traitsRead
    local cached = self.traitSnapshot
    if YUI.IsRetail and context.spec and maintenanceRefresh[reason] and cached and cached.spec == context.spec then
        traitSet, traitsComplete, traitsRead = cached.selected, true, true
    else
        self.traitSnapshot = nil
    end
    local queried = {}
    for _, rule in ipairs(rules) do
        for id in pairs(rule.talents or {}) do
            if not queried[id] then
                queried[id] = true
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
        end
    end
    for _,rule in ipairs(rules) do
        local racial=YUI.API.Racial
        if S.RuleRuntime.IsSelected(rule,context) and (rule.object.kind=='spell'
            or rule.object.kind=='aura' and racial and racial.GetEntry(rule.object.id,'aura'))
            and not context.spells[rule.object.id] then
            local id,charges=SpellIdentity(rule.object.id)
            local previous=self.context.spells and self.context.spells[rule.object.id]
            if charges==nil and PreservesBindings(reason) and previous and previous.id==id
                and not (self.invalidatedSpells and self.invalidatedSpells[rule.object.id]) then
                charges=previous.charges
            end
            context.spells[rule.object.id]={id=id,charges=charges}
        end
    end
    local previousContext, previousBindings = self.context, self.engine.bindings
    self.context = context
    local preserveBindings=PreservesBindings(reason) and self.preferences.enabled
        and previousContext.spec==context.spec
    local ok, code, retained = self.engine:Apply(rules,preserveBindings)
    if not ok then
        self.context = previousContext
        if S.DebugTiming and S.DebugTiming.enabled then S.DebugTiming:Record('context-apply-failed',reason,code) end
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
                and S.RuleRuntime.IsSelected(rule,context) and not bound[S.RuleModel:Key(rule)] then
                unresolved=unresolved or {};unresolved[id]=true
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
    if S.DebugTiming and S.DebugTiming.enabled then
        local kept=0;for _ in pairs(retained) do kept=kept+1 end
        S.DebugTiming:Record('context-apply',reason,#previousBindings,#self.engine.bindings,kept)
    end
    return true
end

function Runtime:Refresh()
    local refreshReason=self.pendingRefreshReason or 'refresh'
    self.pendingRefreshReason=nil
    local spellContextChanged=self.spellContextPending
    self.spellContextPending=nil
    self.pendingSpellIdentities=nil
    Monitor:CancelTask(self, 'context')
    local prefs, code = S:GetPreferences()
    if not prefs then self:Stop(); self.lastIssue = code; return nil, code end
    self.preferences = prefs
    local unit = YUI.API and YUI.API.Unit
    if unit and unit.IsDead and unit.IsDead('player') then self:Stop(); return true end
    S._activeVoicePackId = prefs.voicePackId
    if S.LegacyMigration and S.LegacyMigration:Run(self) then return true end
    local rules
    rules, code = S.RuleStore:Read()
    if not rules then self:Stop(); self.lastIssue = code; return nil, code end
    if S.EditorModel and (spellContextChanged or not S.EditorModel.currentCatalog) then S.EditorModel:RefreshCatalog() end
    local ok,why=self:Apply(rules,refreshReason)
    if ok and spellContextChanged then
        if YUI.Event then YUI.Event:Emit('YUI_SOUND_CONTEXT_CHANGED') end
    end
    return ok,why
end

function Runtime:OnSpellsChanged()
    -- SPELLS_CHANGED also occurs without a talent/identity change. Preserve
    -- delayed casts and playback in that case; no new task or source allocation.
    local changed,pending=nil,self.pendingSpellIdentities
    for base,previous in pairs(self.context.spells or {}) do
        local observed=pending and pending[base] or previous
        local id,charges=SpellIdentity(base)
        if id~=observed.id or charges~=nil and charges~=observed.charges then
            changed=changed or {};changed[base]=true
            if S.DebugTiming and S.DebugTiming.enabled then
                S.DebugTiming:Record('context-spell-change',base,observed.id,id,observed.charges,charges)
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

function Runtime:OnSpellContextChanged(event, unit, changed)
    if unit and unit~='player' and type(unit)=='string' then return end
    self.traitSnapshot = nil
    if event=='spell-identity-changed' and type(changed)=='table' then
        for id in pairs(changed) do
            self.invalidatedSpells=self.invalidatedSpells or {};self.invalidatedSpells[id]=true
        end
        local affected={}
        local racial=YUI.API.Racial
        self.playback:Hold(self)
        for _,binding in ipairs(self.engine.bindings) do
            local object=binding.rule.object
            if changed[object.id] and (object.kind=='spell'
                or object.kind=='aura' and racial and racial.GetEntry(object.id,'aura')) then
                affected[binding]=true
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
    if S.EditorModel then S.EditorModel.currentCatalog=nil end
    self:OnContextChanged(event or 'spell-identity-changed')
end

function Runtime:OnContextChanged(event)
    if self.active then
        local reason=PublicIssue(event) or 'context-changed'
        -- Coalescing may narrow preservation, never upgrade a world/full refresh
        -- to maintenance merely because a maintenance event arrived last.
        if not self.pendingRefreshReason or PreservesBindings(self.pendingRefreshReason)
            or not PreservesBindings(reason) then self.pendingRefreshReason=reason end
        if S.DebugTiming and S.DebugTiming.enabled then S.DebugTiming:Record('context-request',reason,self.pendingRefreshReason) end
        Monitor:ScheduleTask(self, 'context', GetTime() + 0.1, Runtime.Refresh)
    end
end

function Runtime:OnDeath() self:Stop('PLAYER_DEAD') end

function Runtime:OnVoicePackChanged(_,packId)
    if not self.active then return end
    local prefs=S:GetPreferences()
    if not prefs or (prefs.voicePackId~=packId and not (packId=='yui.default' and prefs.fallbackDefault)) then return end
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

function Runtime:Stop(reason)
    if S.DebugTiming and S.DebugTiming.enabled then S.DebugTiming:Record('context-stop',reason) end
    if S.LegacyMigration and S.LegacyMigration.Cancel then S.LegacyMigration:Cancel(self) end
    self.traitSnapshot = nil
    Monitor:CancelTasks(self.previewOwner)
    RecordForecastCancellation(reason)
    self.pendingRefreshReason=nil
    self.spellContextPending=nil
    self.pendingSpellIdentities=nil
    self.invalidatedSpells=nil
    if self.auraPlayback then
        local ok,code=self.auraPlayback:Clear()
        if not ok then self.lastIssue=code end
    end
    self.playback:Hold(self)
    self.forecast:CancelAll()
    self.playback:CancelAll()
    self.engine:Stop()
    Monitor:CancelTasks(self)
    self.playback:ReleaseHold(self)
end

function S:SetPreferences(raw)
    local prefs, code = NormalizePreferences(raw)
    if not prefs then return nil, code end
    local store = PreferenceStore(true)
    if not store then return nil, 'db-not-ready' end
    local db = YUI.DB and YUI.DB.GetAceDB and YUI.DB:GetAceDB(self.storageProductId)
    local characterKey = db and db.keys and db.keys.char
    for key in pairs(defaults) do
        if key ~= 'enabled' or type(characterKey) ~= 'string' then store[key] = prefs[key] end
    end
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

function Runtime:OnEnable()
    if self.active then return end
    self.active = true
    self.notificationStarted = true
    for _, event in ipairs({ 'PLAYER_ENTERING_WORLD',
        'PLAYER_ALIVE', 'PLAYER_UNGHOST', 'PLAYER_REGEN_ENABLED', 'CVAR_UPDATE', 'YUI_MONITOR_SOURCE_STATUS_CHANGED' }) do
        YUI.Event:On(event, 'OnContextChanged', self, { moduleId = self.MODULE_ID })
    end
    YUI.Event:On('PLAYER_DEAD', 'OnDeath', self, { moduleId = self.MODULE_ID })
    YUI.Event:On('YUI_SOUND_PACKS_CHANGED', 'OnVoicePackChanged', self, { moduleId = self.MODULE_ID })
    for _, event in ipairs({'PLAYER_SPECIALIZATION_CHANGED','PLAYER_TALENT_UPDATE'}) do
        YUI.Event:On(event, 'OnSpellContextChanged', self, { moduleId = self.MODULE_ID })
    end
    YUI.Event:On('SPELLS_CHANGED', 'OnSpellsChanged', self, { moduleId = self.MODULE_ID })
    if YUI.IsRetail then YUI.Event:On('TRAIT_CONFIG_UPDATED', 'OnSpellContextChanged', self, { moduleId = self.MODULE_ID }) end
    self:Refresh()
    YUI.Event:Emit('YUI_NOTIFICATION_SOUND_CAPABILITIES_CHANGED')
end

function Runtime:OnDisable()
    self.active = false
    self:Stop()
    YUI.Event:OffOwner(self)
    YUI.Event:Emit('YUI_NOTIFICATION_SOUND_CAPABILITIES_CHANGED')
end

function Runtime:RegisterModule()
    if self.registered or not (YUI.Module and YUI.Module.Register) then return end
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
