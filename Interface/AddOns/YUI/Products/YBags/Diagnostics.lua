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

-- Cold diagnostics only: never write to or walk the native frame hierarchy.
local function StateText(text,limit)
    if #text<=limit then return text end
    while limit>0 do
        local nextByte=text:byte(limit+1)
        if not nextByte or nextByte<128 or nextByte>=192 then break end
        limit=limit-1
    end
    return text:sub(1,limit)
end
local function StateValue(value)
    local S=YUI.API.Security
    if S.IsSecretValue(value) then return "restricted" end
    local kind=type(value)
    if kind=="boolean" then return value and "true" or "false" end
    if kind=="number" then return S.SafeNumber(value) and tostring(value) or "unknown" end
    if kind=="string" then return StateText(value:gsub("[\r\n|]"," "),48) end
    return "unknown"
end
local function StateField(object,key)
    local S=YUI.API.Security
    if S.IsSecretValue(object) then return nil,"restricted" end
    if object==nil then return nil,"unavailable" end
    local ok,value=pcall(function() return object[key] end)
    if not ok then return nil,"unavailable" end
    if S.IsSecretValue(value) then return nil,"restricted" end
    return value,value==nil and "missing" or nil
end
local function StateMethod(object,key)
    local method,reason=StateField(object,key)
    if type(method)~="function" then return reason or "unavailable" end
    local forbidden=StateField(object,"IsForbidden")
    if type(forbidden)=="function" then
        local ok,value=pcall(forbidden,object)
        if not ok or YUI.API.Security.IsSecretValue(value) or value==true then return "unavailable" end
    end
    local ok,value=pcall(method,object)
    return ok and StateValue(value) or "unavailable"
end
local function StateSecurity(object,key)
    local _,reason=StateField(object,key)
    if reason and reason~="missing" then return reason end
    if type(issecurevariable)~="function" then return "unavailable" end
    local ok,secure,source=pcall(issecurevariable,object,key)
    if not ok or YUI.API.Security.IsSecretValue(secure) then return "unknown" end
    if secure==true then return reason=="missing" and "secure-nil" or "secure" end
    if secure==false then return "tainted:"..StateValue(source) end
    return "unknown"
end

function Diagnostics:DescribeItemUseState(button,data)
    local actions,view,runtime=B.Actions,B.View,B.Runtime
    local bankPanel=StateField(BankFrame,"BankPanel")
    local lines={"YBags item-use state v1"}
    local function Add(label,value) lines[#lines+1]=label.."="..value end
    local function Field(label,object,key)
        local value,reason=StateField(object,key)
        Add(label,reason or StateValue(value))
    end
    local function Present(label,object,key)
        local value,reason=StateField(object,key)
        Add(label,reason and reason~="missing" and reason or StateValue(value~=nil))
    end
    Add("active",StateValue(B.active))
    Add("combat",StateMethod(YUI.API.Security,"InCombatLockdown"))
    Add("blockedInput",StateMethod(actions,"BlocksItemInput"))
    Field("action",actions,"kind")
    Present("sortRound",actions,"sortRound")
    Present("carryBatch",actions,"carryBatch")
    Present("finalCarryBatch",runtime,"finalCarryBatch")
    Field("progressiveGroups",StateField(actions,"selection"),"progressiveGroups")
    Present("bagDrag",B.BankView,"bagDrag")
    Field("guildRoute",view,"guildBagBlocked")
    Field("inputRoute",data,"inputRoute")
    Field("bag",data,"bag");Field("slot",data,"slot")
    Field("itemID",StateField(data,"item"),"itemID")
    local input=button and view and view.itemInputs and view.itemInputs[button]
    Add("inputEnabled",StateMethod(input,"IsMouseClickEnabled"))
    for _,name in ipairs({"AuctionHouseFrame","MerchantFrame","BankFrame","GuildBankFrame","MailFrame","TradeFrame"}) do
        Add(name..".shown",StateMethod(_G[name],"IsShown"))
    end
    Add("BankPanel.shown",StateMethod(bankPanel,"IsShown"))
    Add("BankPanel.visible",StateMethod(bankPanel,"IsVisible"))
    for _,key in ipairs({"bagID","GetBagID","SetBagID","OnClick"}) do
        Add("button."..key,StateSecurity(button,key))
    end
    Add("AH.displayMode",StateSecurity(AuctionHouseFrame,"displayMode"))
    Add("AH.IsListingAuctions",StateSecurity(AuctionHouseFrame,"IsListingAuctions"))
    Add("BankPanel.bankType",StateSecurity(bankPanel,"bankType"))
    Add("Bank.GetActiveBankType",StateSecurity(BankFrame,"GetActiveBankType"))
    Add("UseContainerItem",StateSecurity(C_Container,"UseContainerItem"))
    Add("LocationFactory",StateSecurity(ItemLocation,"CreateFromBagAndSlot"))
    for _,key in ipairs({"IsModifiedClick","MerchantFrame_ResetRefundItem","ContainerFrameItemButton_OnClick",
        "BankUtil_IsAccountBankDepositRefundable","ItemLocation","ItemLocationMixin"}) do
        Add(key,StateSecurity(_G,key))
    end
    local text=table.concat(lines,"\n")
    return #text<=2048 and text or StateText(text,2036).."\n[truncated]"
end

local function CurrentItemUseState()
    local ok,state=pcall(Diagnostics.DescribeItemUseState,Diagnostics)
    local clockOK,at=pcall(time)
    local buildOK,version,build=pcall(GetBuildInfo)
    return "\n\nCurrent state at export (not the error-time snapshot)\n"
        .."sampledAt="..(clockOK and StateValue(at) or "unknown")
        .." build="..(buildOK and StateValue(version).."."..StateValue(build) or "unknown").."\n"
        ..(ok and state or "unavailable")
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
        return string.format("YUI %s\n%s",version and version~="" and version or "unknown",collector:FormatRecord(record,session))..CurrentItemUseState()
    end
    local version,build=GetBuildInfo()
    local combat,lockdown=YUI.API.Bags.ItemUseCombatState()
    local system=YUI.API.System
    local instanceType,difficulty,mapID
    if system and system.GetCombatLogContext then instanceType,difficulty,mapID=system.GetCombatLogContext() end
    return string.format("YUI %s · WoW %s.%s\n%s\nlayout=%s combat=%s lockdown=%s instanceType=%s mapID=%s difficultyID=%s",
        self:AddonVersion() or "unknown",version,build,B:T("help.no_report"),B:GetConfig().layout,
        ValueText(combat),ValueText(lockdown),ValueText(instanceType),ValueText(mapID),ValueText(difficulty))..CurrentItemUseState()
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
    local ok,state=pcall(self.DescribeItemUseState,self,button,data)
    return table.concat(lines,"\n"),rightClickWindow,fallback==true,ok and state or "YBags item-use state unavailable"
end
