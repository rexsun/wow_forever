local YUI=_G.YUI
local B=YUI and YUI.YBags
if not B then return end
local S=YUI.API.Security
local Sync={prefix="YUIBags1"}
B.Sync=Sync
local function Normalize(name)
    if type(name)~="string" then return nil end
    name=name:gsub("%s","")
    if name=="" or #name>160 or name:find("[|:]") then return nil end
    if not name:find("-",1,true) then name=name.."-"..GetNormalizedRealmName() end
    return string.lower(name)
end
local function Cancel(field)
    local timer=Sync[field]
    if timer then timer:Cancel();Sync[field]=nil;B.Stats.timers=math.max(0,B.Stats.timers-1) end
end
local function Send(target,message)
    local ok,result=pcall(C_ChatInfo.SendAddonMessage,Sync.prefix,message,"WHISPER",target)
    result=S.SafeNumber(result)
    local codes=Enum and Enum.SendAddonMessageResult
    if not ok then return false end
    if codes and result~=nil then return result==codes.Success,result==codes.AddonMessageThrottle or result==codes.ChannelThrottle end
    return true
end
local function Pump()
    Sync.sendTimer=nil;B.Stats.timers=math.max(0,B.Stats.timers-1)
    local outgoing=Sync.outgoing
    if not Sync.enabled or not outgoing then return end
    local part=outgoing.part
    local message="D|"..outgoing.nonce.."|"..part.."|"..outgoing.total.."|"..outgoing.text:sub((part-1)*200+1,part*200)
    local sent,throttled=Send(outgoing.target,message)
    if not sent then
        if throttled and (outgoing.retries or 0)<2 then
            outgoing.retries=(outgoing.retries or 0)+1
            Sync.sendTimer=C_Timer.NewTimer(1,Pump);B.Stats.timers=B.Stats.timers+1;return
        end
        Sync.outgoing=nil;return
    end
    outgoing.retries=0
    if part>=outgoing.total then Sync.outgoing=nil;return end
    outgoing.part=part+1
    Sync.sendTimer=C_Timer.NewTimer(.4,Pump);B.Stats.timers=B.Stats.timers+1
end
local function Expired()
    Sync.receiveTimer=nil;B.Stats.timers=math.max(0,B.Stats.timers-1);Sync.incoming=nil;B:Notify("sync.timeout")
end
function Sync:Trust(name)
    local peer=Normalize(name)
    if not peer then return false end
    B:GetCacheDB().peers[peer]=true;return true
end
function Sync:Forget(name)
    local peer=Normalize(name)
    if peer then B:GetCacheDB().peers[peer]=nil end
    if self.incoming and self.incoming.sender==peer then Cancel("receiveTimer");self.incoming=nil end
    if self.outgoing and Normalize(self.outgoing.target)==peer then Cancel("sendTimer");self.outgoing=nil end
end
function Sync:Request(name)
    local peer=Normalize(name)
    if not self.enabled or not peer or not B:GetCacheDB().peers[peer] or self.incoming then return false end
    self.serial=(self.serial or 0)+1
    local nonce=tostring(time()).."-"..self.serial
    self.incoming={sender=peer,nonce=nonce,parts={},bytes=0,count=0}
    self.receiveTimer=C_Timer.NewTimer(300,Expired);B.Stats.timers=B.Stats.timers+1
    if not Send(name,"R|"..nonce) then Cancel("receiveTimer");self.incoming=nil;return false end
    B:Notify("sync.started");return true
end
function Sync:Receive(prefix,message,channel,sender)
    if not self.enabled or prefix~=self.prefix or channel~="WHISPER" then return end
    message,sender=S.SafeString(message),S.SafeString(sender)
    if not message or #message>255 or not sender then return end
    local peer=Normalize(sender)
    if not peer or B:GetCacheDB().peers[peer]~=true then return end
    local request=message:match("^R|([%d%-]+)$")
    local library=LibStub and LibStub("AceSerializer-3.0",true)
    if not library then return end
    if request then
        if #request>40 or self.outgoing then return end
        local now=GetTime()
        self.last=self.last or {}
        if self.last[peer] and now-self.last[peer]<30 then return end
        self.last[peer]=now
        local text=library:Serialize(B.Cache:Payload())
        if #text>131072 then return end
        self.outgoing={target=sender,nonce=request,text=text,total=math.ceil(#text/200),part=1};Pump();return
    end
    local nonce,part,total,data=message:match("^D|([%d%-]+)|(%d+)|(%d+)|(.*)$")
    local incoming=self.incoming
    part,total=tonumber(part),tonumber(total)
    if not incoming or incoming.sender~=peer or nonce~=incoming.nonce or not part or not total or total>656 or part<1 or part>total
        or incoming.total and incoming.total~=total or not data or #data>200 then return end
    incoming.total=total
    if not incoming.parts[part] then incoming.parts[part]=data;incoming.bytes=incoming.bytes+#data;incoming.count=incoming.count+1 end
    if incoming.bytes>131072 then Cancel("receiveTimer");self.incoming=nil;return end
    if incoming.count==total then
        Cancel("receiveTimer");self.incoming=nil
        local ok,payload=library:Deserialize(table.concat(incoming.parts))
        if ok and B.Cache:Merge(payload) then B:Notify("sync.complete") else B:Notify("error.import") end
    end
end
local function OnMessage(_,prefix,message,channel,sender) Sync:Receive(prefix,message,channel,sender) end
function Sync:Enable()
    if self.enabled or B.Cache.clearedForSession or not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix(self.prefix) then return end
    self.enabled=true;YUI.Event:On("CHAT_MSG_ADDON",OnMessage,self)
end
function Sync:Disable()
    self.enabled=false;YUI.Event:OffOwner(self);Cancel("sendTimer");Cancel("receiveTimer")
    self.incoming,self.outgoing,self.last=nil,nil,nil
end
