local _, YUI = ...
YUI = _G.YUI or YUI
if not (YUI and YUI.Sound) then return end
local S=YUI.Sound
local Playback={}
Playback.__index=Playback
S.Playback=Playback

function Playback.New(adapter)
    assert(type(adapter)=='table' and adapter.now and adapter.schedule and adapter.cancel and adapter.play)
    return setmetatable({adapter=adapter,queue={},owners={},pending={},serial=0,
        stats={submitted=0,expired=0,rejected=0,completed=0,canceled=0}},Playback)
end

function Playback:_Finish(receipt,reason)
    if self.busy~=receipt then return end
    self.adapter.cancel(self,'completion')
    self.busy=nil
    self.pending[receipt.owner][receipt.key]=nil
    if not next(self.pending[receipt.owner]) then self.pending[receipt.owner]=nil end
    if reason=='finished' or reason=='stopped' then self.stats.completed=self.stats.completed+1
    else self.stats.rejected=self.stats.rejected+1 end
    if self.adapter.result then pcall(self.adapter.result,receipt,reason) end
    self:Pump()
end

function Playback:_Stop(receipt)
    if receipt and receipt.resource.preview and receipt.resource.kind=='tts' and self.adapter.stopPreviewTTS then
        local called, stopped = pcall(self.adapter.stopPreviewTTS, receipt.token)
        return called and stopped == true
    end
    if not (receipt and receipt.handle and self.adapter.stop) then return false end
    local called, stopped = pcall(self.adapter.stop, receipt.handle)
    return called and stopped == true
end

function Playback:_Unavailable(receipt,reason)
    receipt.unavailable=true
    self.adapter.cancel(self,'completion')
    if self.adapter.result then pcall(self.adapter.result,receipt,reason) end
end

function Playback:_ScheduleCheck(at)
    local called,ok=pcall(self.adapter.schedule,self,'completion',at,Playback._Check)
    if called and ok==true then return true end
    local receipt=self.busy
    if receipt then
        if self:_Stop(receipt) then self:_Finish(receipt,'stopped')
        else self:_Unavailable(receipt,'completion-schedule-failed') end
    end
    return false
end

function Playback:Hold(owner)
    self.owners[owner] = true
end

function Playback:ReleaseHold(owner)
    self.owners[owner] = nil
    self:Pump()
end

function Playback:PreemptFile()
    local receipt = self.busy
    if not receipt then return true end
    -- An active utterance has no independently stoppable file handle.
    -- Keep its receipt until its own completion event releases the queue.
    if not receipt.handle then return false end
    if not self:_Stop(receipt) then return false end
    self:_Finish(receipt, 'preempted')
    return true
end

function Playback:_Check()
    local receipt=self.busy
    if not receipt then return end
    local now=self.adapter.now()
    if receipt.handle and self.adapter.isPlaying then
        local called,playing=pcall(self.adapter.isPlaying,receipt.handle)
        if called and playing==false then self:_Finish(receipt,'stopped'); return end
        if called and playing==true then self:_ScheduleCheck(now+0.1); return end
    end
    if now>=receipt.deadline then
        -- Unknown playback cannot safely release the next serialized request.
        if receipt.resource.duration and self:_Stop(receipt) then self:_Finish(receipt,'stopped'); return end
        self:_Unavailable(receipt,'completion-unavailable')
        return
    end
    self:_ScheduleCheck(now+0.1)
end

function Playback:Complete(token, success)
    if self.busy and self.busy.token==token then self:_Finish(self.busy,success==false and 'play-failed' or 'finished') end
end

function Playback:Pump()
    if self.busy or self.pumping or next(self.owners) then return end
    self.pumping=true
    while not self.busy and #self.queue>0 do
        local job=table.remove(self.queue,1)
        local now=self.adapter.now()
        if now>job.expiresAt then
            self.pending[job.owner][job.key]=nil
            if not next(self.pending[job.owner]) then self.pending[job.owner]=nil end
            self.stats.expired=self.stats.expired+1
        else
            self.serial=self.serial+1
            local receipt={owner=job.owner,key=job.key,token=self.serial,resource=job.resource,
                deadline=job.expiresAt+(job.resource.duration or 0)}
            self.busy=receipt
            local called,ok,handle=pcall(self.adapter.play,job.resource,receipt.token)
            if self.busy==receipt then
                if not called or not ok then self:_Finish(receipt,'play-failed')
                else
                    receipt.handle=handle
                    receipt.deadline=job.expiresAt+(job.resource.duration or 0)
                    self:_ScheduleCheck(now+(job.resource.duration or 0.1))
                end
            end
        end
    end
    self.pumping=nil
end

function Playback:Submit(owner,key,resource,expiresAt)
    local now=self.adapter.now()
    if owner==nil or type(key)~='string' or type(resource)~='table' or type(expiresAt)~='number'
        or expiresAt~=expiresAt or expiresAt==math.huge or expiresAt<now then return false,'invalid-request' end
    if resource.duration~=nil and (type(resource.duration)~='number' or resource.duration~=resource.duration
        or resource.duration<=0 or resource.duration>86400) then return false,'invalid-request' end
    if self.pending[owner] and self.pending[owner][key] then return false,'duplicate-request' end
    if self.busy and self.busy.unavailable then return false,'completion-unavailable' end
    if #self.queue>=128 then self.stats.rejected=self.stats.rejected+1; return false,'queue-budget' end
    self.pending[owner]=self.pending[owner] or {}
    self.pending[owner][key]=true
    self.queue[#self.queue+1]={owner=owner,key=key,resource=resource,expiresAt=expiresAt}
    self.stats.submitted=self.stats.submitted+1
    self:Pump()
    return true
end

function Playback:CancelOwner(owner)
    local pending=self.pending[owner]
    for i=#self.queue,1,-1 do
        if self.queue[i].owner==owner then
            if pending then pending[self.queue[i].key]=nil end
            table.remove(self.queue,i); self.stats.canceled=self.stats.canceled+1
        end
    end
    local receipt=self.busy
    if receipt and receipt.owner==owner then
        if self:_Stop(receipt) then
            self.adapter.cancel(self,'completion')
            self.busy=nil
        else
            -- TTS or a failed file stop retains its completion receipt so
            -- canceling a page cannot release overlapping ordinary speech.
            receipt.canceled=true
            if pending and not next(pending) then self.pending[owner]=nil end
            return
        end
    end
    self.pending[owner]=nil
    self:Pump()
end

function Playback:CancelAll()
    self:Hold(self)
    for owner in pairs(self.pending) do self:CancelOwner(owner) end
    self:ReleaseHold(self)
end

return Playback
