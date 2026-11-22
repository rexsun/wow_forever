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

local function AgeMs(now,at)
    return at and math.floor(math.max(0,now-at)*1000+.5) or "unknown"
end

local function ValueText(value)
    return value==nil and "unknown" or tostring(value)
end

function Diagnostics:AddonVersion()
    local system=YUI.API.System
    if not system or not system.GetAddOnMetadata then return end
    local ok,version=pcall(system.GetAddOnMetadata,B.ADDON_NAME,"Version")
    if ok then return YUI.API.Security.SafeString(version) end
end

function Diagnostics:HelpHistory()
    local collector=_G.YUI_ErrorCollector
    if collector and collector.GetYBagsItemUseReport then return collector:GetYBagsItemUseReport() end
end

function Diagnostics:HelpReport(record,session)
    if record and session then
        local collector=_G.YUI_ErrorCollector
        local version=record.ybagsVersion
        return string.format("YUI %s\n%s",version and version~="" and version or "unknown",collector:FormatRecord(record,session))
    end
    local version,build=GetBuildInfo()
    local combat,lockdown=YUI.API.Bags.ItemUseCombatState()
    local system=YUI.API.System
    local instanceType,difficulty,mapID
    if system and system.GetCombatLogContext then instanceType,difficulty,mapID=system.GetCombatLogContext() end
    return string.format("YUI %s · WoW %s.%s\n%s\nlayout=%s combat=%s lockdown=%s instanceType=%s mapID=%s difficultyID=%s",
        self:AddonVersion() or "unknown",version,build,B:T("help.no_report"),B:GetConfig().layout,
        ValueText(combat),ValueText(lockdown),ValueText(instanceType),ValueText(mapID),ValueText(difficulty))
end

function Diagnostics:NoteConfig(source)
    self.configSource,self.configAt=source,YUI.API.Bags.Now()
end

function Diagnostics:DescribeBlockedItemUse(helpOnly, confirmedOnly)
    local A=YUI.API.Bags
    local focus,parent,mouse=A.ItemUseMouseFocus()
    local view=B.View
    local button=focus and view.itemInputs[focus] and focus
    if not button and focus and parent and view.itemInputs[parent]==focus then button=parent end
    local data=B.active and button and view.buttonData[button]
    local window=data and data.window and data.window.open and data.window or nil
    local rightClickWindow=mouse=="RightButton" and window and window.id or nil
    local player=view.windows.player
    local fallback=not confirmedOnly and rightClickWindow~="player" and B.active and player and player.open
        and (not window or window==player) and (not mouse or mouse=="" or mouse=="RightButton")
    if helpOnly and rightClickWindow~="player" and not fallback then return end
    local now=A.Now()
    local system=YUI.API.System
    local instanceType,difficulty,mapID,instanceName
    if system then instanceType,difficulty,mapID,instanceName=system.GetCombatLogContext() end
    local combat,lockdown=A.ItemUseCombatState()
    local lines={
        ("YBags item-use context (mouse focus at block) | active=%s mouse=%s combat=%s lockdown=%s combatEndedMs=%s"):format(
            tostring(B.active==true),mouse and mouse~="" and mouse or "unknown",ValueText(combat),ValueText(lockdown),AgeMs(now,B.Runtime.combatEndedAt)),
    }
    if window then
        local bag,slot=A.ItemUseButtonSlot(button)
        lines[#lines+1]=("focus=YBags window=%s bag=%s slot=%s itemID=%s nativeBag=%s nativeSlot=%s"):format(
            window.id,data.bag or "unknown",data.slot or "unknown",data.item.itemID or "unknown",bag or "unknown",slot or "unknown")
        local native=view.itemBindings[button]
        if native then
            local binding="initial"
            if native.previousBag~=nil then
                binding=(native.previousBag==native.bag and native.previousSlot==native.slot) and "same-slot" or "rebind"
            end
            lines[#lines+1]=("binding=%s bindAgeMs=%s previousBag=%s previousSlot=%s"):format(
                binding,AgeMs(now,native.at),native.previousBag or "unknown",native.previousSlot or "unknown")
        else
            lines[#lines+1]="binding=unknown"
        end
    else
        lines[#lines+1]="focus=unknown bag=unknown slot=unknown itemID=unknown"
    end
    lines[#lines+1]=("layout=%s config=%s configAgeMs=%s"):format(B:GetConfig().layout,self.configSource or "none",AgeMs(now,self.configAt))
    lines[#lines+1]=("instanceType=%s mapID=%s difficultyID=%s instanceName=%s"):format(
        instanceType or "unknown",mapID or "unknown",difficulty or "unknown",instanceName or "unknown")
    return table.concat(lines,"\n"),rightClickWindow,fallback==true
end
