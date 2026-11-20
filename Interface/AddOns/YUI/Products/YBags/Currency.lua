local YUI=_G.YUI
local B=YUI and YUI.YBags
if not B then return end
local A,S=YUI.API.Bags,YUI.API.Security
local C={}
B.Currency=C
local presets={{id=3402,key="currency.merchant",icon=135725},{id=515,key="currency.darkmoon",icon=134481}}
function C:MoneyTooltip(owner)
    GameTooltip:SetOwner(owner,"ANCHOR_TOPRIGHT");GameTooltip:SetText(B:T("money.title"))
    YUI.CharacterMoney:AppendTooltip(GameTooltip,B.HOST_ID,{characters=B:T("money.characters"),total=B:T("money.total"),
        alliance=B:T("money.alliance"),horde=B:T("money.horde")},function(amount) return A.MoneyText(amount,12) end)
    GameTooltip:AddLine(B:T("money.manage_hint"));GameTooltip:Show()
end
function C:Info(kind,id)
    if kind=="item" then
        local item=YUI.API.Item.GetInfo(id)
        local count=S.SafeNumber(A.ItemCount(id));if count and count<0 then count=nil end
        return {kind=kind,id=id,name=item and item.name or tostring(id),icon=item and item.texture or 134400,
            count=count}
    end
    local info=A.CurrencyInfo(id)
    if info then return info end
    if B.client=="forever" then for _,entry in ipairs(presets) do
        if id==entry.id then return {kind=kind,id=id,name=B:T(entry.key),icon=entry.icon or 134400} end
    end end
    return {kind=kind,id=id,name=tostring(id)}
end
function C:Tracked()
    local values={}
    for _,entry in ipairs(B:GetConfig().tracked) do values[#values+1]=self:Info(entry.kind,entry.id) end
    return values
end
function C:Track(kind,id)
    id=tonumber(id)
    if kind~="item" and kind~="currency" or not id or id<1 or id>=100000000 or id~=math.floor(id) then return false end
    local tracked=B:GetConfig().tracked
    for _,entry in ipairs(tracked) do if entry.kind==kind and entry.id==id then return true end end
    if #tracked>=100 then return false end
    tracked[#tracked+1]={kind=kind,id=id};return true
end
function C:Untrack(kind,id)
    local tracked=B:GetConfig().tracked
    for n=#tracked,1,-1 do if tracked[n].kind==kind and tracked[n].id==id then table.remove(tracked,n) end end
end
function C:First(kind,id)
    self:Untrack(kind,id);table.insert(B:GetConfig().tracked,1,{kind=kind,id=id})
end
function C:Candidates(query)
    local values,seen={},{}
    query=string.lower(query or "")
    local function Add(value)
        local key=value.kind..":"..value.id
        if seen[key] then return end
        seen[key]=true
        if query=="" or string.lower(value.name or ""):find(query,1,true) or tostring(value.id)==query then values[#values+1]=value end
    end
    for _,value in ipairs(A.CurrencyList()) do Add(value) end
    if B.client=="forever" then for _,entry in ipairs(presets) do Add(self:Info("currency",entry.id)) end end
    for _,value in ipairs(B:GetConfig().tracked) do if not seen[value.kind..":"..value.id] then Add(self:Info(value.kind,value.id)) end end
    local id=tonumber(query)
    if id and id>0 and id<100000000 and id==math.floor(id) then
        local info=A.CurrencyInfo(id)
        if info then Add(info) end
    end
    table.sort(values,function(a,b) if a.kind~=b.kind then return a.kind=="currency" end;return a.name<b.name end)
    return values
end
