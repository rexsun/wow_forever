-- One upstream subscription per event, with independently owned view consumers.
-- This adapter is intentionally limited to the option-free information modules.
local Signals = {}
Signals.__index = Signals

local function Invoke(entry, event, ...)
    if type(entry.handler) == "string" then
        local method = entry.owner[entry.handler]
        if method then return method(entry.owner, event, ...) end
    else return entry.handler(event, ...) end
end

local function Compact(channel)
    if channel.depth > 0 then return end
    local items, count = channel.items, 0
    for i=1,#items do
        local item=items[i]
        if item.active then count=count+1;items[count]=item end
    end
    for i=#items,count+1,-1 do items[i]=nil end
    if count == 0 then
        if channel.timer then channel.timer:Cancel(); channel.timer=nil
        else channel.hub.upstream:OffOwner(channel) end
        channel.hub.channels[channel.event]=nil
    end
end

local function Cancel(entry)
    if not entry.active then return end
    entry.active=false
    Compact(entry.channel)
end

local function Dispatch(channel, event, ...)
    local hub=channel.hub
    hub.dispatchDepth=hub.dispatchDepth+1;hub.generation=hub.generation+1
    channel.depth=channel.depth+1
    -- New subscriptions begin on the next signal, even if registered by a callback.
    local limit=#channel.items
    for i=1,limit do
        local entry=channel.items[i]
        if entry.active then
            if entry.once then entry.active=false end
            local ok,err=pcall(Invoke,entry,event,...)
            if not ok then
                entry.active=false
                if channel.hub.report then pcall(channel.hub.report,err,entry.owner) end
            end
        end
    end
    channel.depth=channel.depth-1
    hub.dispatchDepth=hub.dispatchDepth-1
    Compact(channel)
end

function Signals.New(upstream, report, newTicker)
    return setmetatable({upstream=upstream,report=report,newTicker=newTicker,channels={},data={},generation=0,dispatchDepth=0},Signals)
end
-- Cache only during a fan-out dispatch. Explicit settings/tooltip reads always
-- query the provider, so hidden modules cannot retain an obsolete game sample.
function Signals:ReadData(key,loader,arg)
    if self.dispatchDepth==0 then return loader(arg) end
    local record=self.data[key]
    if not record then record={};self.data[key]=record end
    if record.generation~=self.generation then
        record.a,record.b,record.c=loader(arg);record.generation=self.generation
    end
    return record.a,record.b,record.c
end

function Signals:On(event,handler,owner,options)
    assert(options == nil or next(options) == nil,"unsupported-instance-event-options")
    assert(type(event)=="string" and event~="","invalid-event")
    assert(type(handler)=="function" or (type(handler)=="string" and owner),"invalid-handler")
    local channel=self.channels[event]
    if not channel then
        channel={hub=self,event=event,items={},depth=0,OnSignal=Dispatch}
        self.channels[event]=channel
        local ok,result=pcall(self.upstream.On,self.upstream,event,"OnSignal",channel)
        if not ok or not result then
            self.channels[event]=nil
            error(ok and "event-subscription-failed" or result)
        end
    end
    local entry={channel=channel,handler=handler,owner=owner,active=true,Cancel=Cancel}
    channel.items[#channel.items+1]=entry
    return entry
end

function Signals:Once(event,handler,owner,options)
    local entry=self:On(event,handler,owner,options)
    entry.once=true
    return entry
end

function Signals:OffOwner(owner)
    for _,channel in pairs(self.channels) do
        for _,entry in ipairs(channel.items) do
            if entry.owner==owner then entry.active=false end
        end
        Compact(channel)
    end
end

function Signals:EverySecond(handler,owner)
    local event="clock-tick"
    local channel=self.channels[event]
    if not channel then
        assert(self.newTicker,"missing-clock-scheduler")
        channel={hub=self,event=event,items={},depth=0}
        local ok,timer=pcall(self.newTicker,1,function()Dispatch(channel,event)end)
        if not ok or not timer then error(ok and "clock-subscription-failed" or timer) end
        channel.timer=timer
        self.channels[event]=channel
    end
    local entry={channel=channel,handler=handler,owner=owner,active=true,Cancel=Cancel}
    channel.items[#channel.items+1]=entry
    return entry
end

function Signals:Close()
    for _,channel in pairs(self.channels) do
        for _,entry in ipairs(channel.items) do entry.active=false end
        Compact(channel)
    end
    self.data={}
end
local owner=_G.YUI and _G.YUI.YBar
if owner then
    owner.LayoutLibraries=owner.LayoutLibraries or {}
    owner.LayoutLibraries.Signals=Signals
end
return Signals
