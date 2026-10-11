local _, YUI = ...
YUI = _G.YUI or YUI
if not (YUI and YUI.Sound) then return end
local S=YUI.Sound
local TTS={}
TTS.__index=TTS
S.TTS=TTS

local function Public(value)
    if type(issecretvalue)=='function' and issecretvalue(value) then return nil end
    return value
end
local function Number(value)
    value=Public(value)
    return type(value)=='number' and value==value and value<math.huge and value>-math.huge and value or nil
end

function TTS.New(event,api,now)
    return setmetatable({event=event,api=api or C_VoiceChat,now=now or GetTime},TTS)
end

function TTS:GetVoices()
    local api=self.api
    if not (api and api.GetTtsVoices) then return {} end
    local ok,raw=pcall(api.GetTtsVoices)
    if not ok or type(Public(raw))~='table' then return {} end
    local voices={}
    for _,voice in ipairs(raw) do
        if type(Public(voice))=='table' then
            local id,name=Number(voice.voiceID),Public(voice.name)
            if id and id%1==0 and type(name)=='string' then voices[#voices+1]={id=id,name=name} end
        end
    end
    return voices
end

function TTS:GetSystemVoice()
    local voiceType = Enum and Enum.TtsVoiceType and Enum.TtsVoiceType.Standard
    if voiceType ~= nil and C_TTSSettings and C_TTSSettings.GetVoiceOptionID then
        local ok, id = pcall(C_TTSSettings.GetVoiceOptionID, voiceType)
        if ok then return Number(id) end
    end
end

function TTS:OnBookmark(_,id,mark)
    local receipt=self.receipt
    id,mark=Number(id),Public(mark)
    if receipt and id and mark==receipt.mark and receipt.id==nil then receipt.id=id end
end

function TTS:OnFinished(event,id)
    local receipt=self.receipt
    id=Number(id)
    if not receipt or not id or receipt.id~=id then return end
    self.receipt=nil
    self.event:OffOwner(self)
    if receipt.complete then receipt.complete(receipt.token,event=='VOICE_CHAT_TTS_PLAYBACK_FINISHED') end
end

function TTS:Speak(token,text,voiceID,rate,volume,complete)
    if self.receipt then return nil,'tts-busy' end
    if not (self.api and self.api.SpeakText and self.event and self.event.On and self.now) then return nil,'tts-unavailable' end
    text=Public(text); voiceID=Number(voiceID); rate=Number(rate); volume=Number(volume)
    if type(text)~='string' or text=='' or #text>2048 or not voiceID or not rate or not volume
        or type(complete)~='function' then return nil,'invalid-tts-request' end
    local found=false
    for _,voice in ipairs(self:GetVoices()) do if voice.id==voiceID then found=true; break end end
    if not found then return nil,'tts-voice-unavailable' end
    S._ttsSerial=(S._ttsSerial or 0)+1
    local mark='yui_sound_'..S._ttsSerial..'_'..self.now()
    local receipt={token=token,mark=mark,complete=complete}
    self.receipt=receipt
    local events={VOICE_CHAT_TTS_PLAYBACK_BOOKMARK='OnBookmark',VOICE_CHAT_TTS_PLAYBACK_FINISHED='OnFinished',
        VOICE_CHAT_TTS_PLAYBACK_FAILED='OnFinished'}
    for name,method in pairs(events) do
        local ok,listener=pcall(self.event.On,self.event,name,method,self,{moduleId='sound'})
        if not ok or not listener then self.event:OffOwner(self); self.receipt=nil; return nil,'tts-events-unavailable' end
    end
    local escaped=text:gsub('&','&amp;'):gsub('<','&lt;'):gsub('>','&gt;')
    local ok=pcall(self.api.SpeakText,voiceID,'<bookmark mark="'..mark..'"/>'..escaped,rate,volume,false)
    if not ok then self.event:OffOwner(self); self.receipt=nil; return nil,'tts-submit-failed' end
    return true
end

-- Explicit preview cancellation only; ordinary consumer cleanup retains speech ownership.
function TTS:Stop(token)
    local receipt=self.receipt
    if not receipt or receipt.token~=token or not (self.api and self.api.StopSpeakingText) then return false end
    -- Detach first: a synchronous stop event must not finish/pump the coordinator twice.
    self.receipt=nil
    self.event:OffOwner(self)
    local ok=pcall(self.api.StopSpeakingText)
    if not ok then
        self.receipt=receipt
        self.event:On('VOICE_CHAT_TTS_PLAYBACK_BOOKMARK','OnBookmark',self,{moduleId='sound'})
        self.event:On('VOICE_CHAT_TTS_PLAYBACK_FINISHED','OnFinished',self,{moduleId='sound'})
        self.event:On('VOICE_CHAT_TTS_PLAYBACK_FAILED','OnFinished',self,{moduleId='sound'})
    end
    return ok
end

-- Unloading a consumer detaches its callback, not the engine's speech. The
-- service keeps the ownership receipt until a matching completion arrives.
function TTS:Detach(token)
    if self.receipt and self.receipt.token==token then self.receipt.complete=nil; return true end
    return false
end

return TTS
