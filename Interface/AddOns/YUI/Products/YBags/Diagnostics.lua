local YUI = _G.YUI
local B = YUI and YUI.YBags
if not B then return end
local Diagnostics={enabled=false,detailEnabled=false,samples={}}
B.Diagnostics=Diagnostics
local clock=debugprofilestop or function() return 0 end
function Diagnostics:Begin()
    if self.enabled ~= true then return nil end
    return clock()
end
function Diagnostics:Finish(name,started)
    if self.enabled ~= true or not started then return end
    local sample=self.samples[name]
    if not sample then sample={count=0,totalMs=0,maxMs=0};self.samples[name]=sample end
    local elapsed=math.max(0,clock()-started)
    sample.count=sample.count+1;sample.totalMs=sample.totalMs+elapsed;sample.maxMs=math.max(sample.maxMs,elapsed)
end
function Diagnostics:Detail(name,value)
    if self.enabled ~= true or self.detailEnabled ~= true then return end
    self.samples[name]=value
end
function Diagnostics:SetEnabled(enabled)
    self.enabled=enabled==true
    if not self.enabled then self.samples={} end
end
function Diagnostics:Report()
    local version,build,_,interface=GetBuildInfo()
    return {client=B.client,version=version,build=build,interface=interface,stats=B:GetStats(),samples=B:Copy(self.samples)}
end
