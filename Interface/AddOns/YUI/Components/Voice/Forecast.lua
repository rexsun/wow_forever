local _, YUI = ...
YUI = _G.YUI or YUI
if not (YUI and YUI.Sound) then return end
local S=YUI.Sound
local Forecast={}
Forecast.__index=Forecast
S.Forecast=Forecast

-- The adapter plays/stops only this service's file handles. It may interrupt
-- ordinary owned files, but must never globally stop the game's TTS queue.
function Forecast.New(monitor,adapter)
    assert(monitor and monitor.ScheduleTask and monitor.CancelTasks)
    assert(adapter and adapter.now and adapter.play and adapter.stop)
    return setmetatable({monitor=monitor,adapter=adapter,owners={},
        stats={started=0,played=0,late=0,failed=0,canceled=0}},Forecast)
end

local function Release(occurrence)
    local self=occurrence.manager
    self.monitor:CancelTasks(occurrence)
    occurrence.active=false
    local owned=self.owners[occurrence.owner]
    if owned and owned[occurrence.key]==occurrence then
        owned[occurrence.key]=nil
        if not next(owned) then self.owners[occurrence.owner]=nil end
    end
    if occurrence.handle then
        local stopped=false
        if self.adapter.isPlaying then
            local called,playing=pcall(self.adapter.isPlaying,occurrence.handle)
            stopped=called and playing==false
        end
        if not stopped then
            local called,result=pcall(self.adapter.stop,occurrence.handle)
            stopped=called and result==true
        end
        if not stopped then
            -- Retain the handle and queue hold until a later explicit attempt
            -- can establish that playback stopped. Never overlap unknown audio.
            self.blocked=occurrence
            self.lastIssue='forecast-stop-unavailable'
            return false
        end
        occurrence.handle=nil
    end
    if self.adapter.release then
        local called,result=pcall(self.adapter.release,occurrence)
        if not called or result==false then
            self.blocked=occurrence; self.lastIssue='forecast-release-failed'; return false
        end
    end
    if self.current==occurrence then self.current=nil end
    if self.blocked==occurrence then self.blocked=nil end
    return true
end

-- Unknown ending lengths are checked only while this occurrence owns playback.
-- A bounded deadline also covers clients without a usable playback-state API.
local function CheckEnding(occurrence,_,now)
    if not occurrence.active then return end
    local self=occurrence.manager
    if occurrence.handle and self.adapter.isPlaying then
        local called,playing=pcall(self.adapter.isPlaying,occurrence.handle)
        if called and playing==false then occurrence.handle=nil; Release(occurrence); return end
    end
    if now>=occurrence.endingDeadline then Release(occurrence); return end
    if not self.monitor:ScheduleTask(occurrence,'release',now+0.1,CheckEnding) then
        self.stats.failed=self.stats.failed+1; Release(occurrence)
    end
end

local function PlaySegment(occurrence,key,now)
    if not occurrence.active then return end
    local self=occurrence.manager
    if self.blocked then Release(occurrence); return end
    local job=occurrence.jobs[tonumber(key)]
    if not job then Release(occurrence); return end
    -- A frame can arrive a little after a scheduled boundary. If the next
    -- boundary has already arrived, skip instead of replaying a stale segment.
    local nextJob=occurrence.jobs[tonumber(key)+1]
    local latest=job.at+0.25
    if nextJob then
        latest=math.min(latest,nextJob.at)
        if job.segment=='intro' then latest=math.min(latest,nextJob.at-job.duration) end
    end
    if now>latest then self.stats.late=self.stats.late+1; return end
    if self.adapter.preemptFiles then
        local called,ok=pcall(self.adapter.preemptFiles,occurrence)
        if not called or ok~=true then
            self.stats.failed=self.stats.failed+1; Release(occurrence); return
        end
    end
    if self.current and self.current~=occurrence and not Release(self.current) then
        self.stats.failed=self.stats.failed+1; Release(occurrence); return
    end
    if occurrence.handle then
        local called,stopped=pcall(self.adapter.stop,occurrence.handle)
        if not called or stopped~=true then
            self.stats.failed=self.stats.failed+1; Release(occurrence); return
        end
        occurrence.handle=nil
    end
    local called,ok,handle=pcall(self.adapter.play,job,occurrence)
    if not called or not ok or type(handle)~='number' then
        self.stats.failed=self.stats.failed+1; Release(occurrence); return
    end
    occurrence.handle=handle
    self.current=occurrence
    self.stats.played=self.stats.played+1
    if not nextJob then
        occurrence.endingDeadline=now+300
        local scheduled=self.monitor:ScheduleTask(occurrence,'release',now+(job.duration or 0.1),job.duration and Release or CheckEnding)
        if not scheduled then self.stats.failed=self.stats.failed+1; Release(occurrence) end
    end
end

function Forecast:Start(owner,key,definition)
    if owner==nil or type(key)~='string' or key=='' or type(definition)~='table' then return nil,'invalid-forecast' end
    if self.blocked and not Release(self.blocked) then return nil,self.lastIssue end
    local jobs,code=S:BuildForecast(definition.targetAt,definition.countdown,definition.gap,
        definition.introduction,definition.ending,definition.digits,self.adapter.now())
    -- Replacement must invalidate an older occurrence even when this new one
    -- cannot resolve all its recordings. Never play the old target by accident.
    self:Cancel(owner,key)
    if self.blocked then return nil,self.lastIssue end
    if not jobs then return nil,code end
    if #jobs==0 then return nil,'expired-forecast' end
    local occurrence={manager=self,owner=owner,key=key,jobs=jobs,active=true}
    local owned=self.owners[owner] or {}; self.owners[owner]=owned; owned[key]=occurrence
    for index,job in ipairs(jobs) do
        local ok,why=self.monitor:ScheduleTask(occurrence,tostring(index),job.at,PlaySegment)
        if not ok then Release(occurrence); return nil,why end
    end
    local last=jobs[#jobs]
    local ok,why=self.monitor:ScheduleTask(occurrence,'release',last.at+(last.duration or 0.25),Release)
    if not ok then Release(occurrence); return nil,why end
    self.stats.started=self.stats.started+1
    return true
end

function Forecast:Cancel(owner,key)
    local owned=self.owners[owner]
    local occurrence=owned and owned[key]
    if not occurrence then return false end
    local released=Release(occurrence); self.stats.canceled=self.stats.canceled+1
    return released
end

function Forecast:CancelOwner(owner)
    local owned=self.owners[owner]
    if not owned then return end
    for key in pairs(owned) do self:Cancel(owner,key) end
end

function Forecast:CancelAll()
    for owner in pairs(self.owners) do self:CancelOwner(owner) end
    if self.blocked then Release(self.blocked) end
end

return Forecast
