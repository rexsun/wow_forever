local YUI=_G.YUI
if not YUI then return end
local M=YUI.CharacterMoney
if type(M)=="table" and type(M.API_VERSION)=="number" and M.API_VERSION>=3 and type(M.Record)=="function" and type(M.Summary)=="function" and type(M.AppendTooltip)=="function" and type(M.RememberCharacter)=="function" then return end
local S=YUI.API.Security
M=type(M)=="table" and M or {}
YUI.CharacterMoney=M
M.API_VERSION=3
local fields={"money","class","faction","guid","updated","client"}
local function Read(callback,...)
    if type(callback)~="function" then return nil end
    local ok,value=pcall(callback,...);if ok then return value end
end
local function Client()
    return YUI.IsForever and "forever" or YUI.IsRetail and "mainline" or YUI.IsMists and "mists" or "wrath"
end
local function Realm(value) return type(value)=="string" and value:gsub("%s",""):lower() or "" end
local function PlayerName()
    local unit=YUI.API.Unit
    local fn=unit and unit.GetCharacterName or YUI.IsForever and NameUtil and NameUtil.FormatUnitNameForDisplay or UnitName
    return S.SafeString(Read(fn,"player"))
end
function M:RememberCharacter(scope,character)
    if type(character)~="table" or character.client~=Client() then return end
    local name,realm,guid=S.SafeString(character.name),S.SafeString(character.realm),S.SafeString(character.guid)
    if not name or name=="" or not realm or realm=="" or not guid or guid=="" then return end
    local global=YUI.DB:GetGlobal(scope);if not global then return end
    global.Gold=global.Gold or {};global.Gold[realm]=global.Gold[realm] or {}
    local data=global.Gold[realm];data.names=data.names or {}
    if data.names[guid]~=name then data.names[guid]=name end
end
local function FullNames(scope,currentRealm,global)
    local index={}
    if not YUI.IsForever then return index end
    local separator=Constants and Constants.CharacterNameSeparatorConsts and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "
    local function Add(name,realm,guid)
        name=S.SafeString(name);realm=S.SafeString(realm)
        if not name or not realm then return end
        local split=name:find(separator,1,true)
        if not split or split==1 or split+#separator>#name then return end
        local key=Realm(realm);local names=index[key]
        if not names then names={short={},guid={}};index[key]=names end
        local short=name:sub(1,split-1)
        local previous=names.short[short]
        if previous==nil or previous==name then names.short[short]=name else names.short[short]=false end
        if guid then names.guid[guid]=name end
    end
    for realm,data in pairs(global and global.Gold or {}) do
        if type(data)=="table" then
            for name in pairs(data.money or {}) do
                if not data.client or not data.client[name] or data.client[name]=="forever" then Add(name,realm,data.guid and data.guid[name]) end
            end
            for guid,name in pairs(data.names or {}) do Add(name,realm,guid) end
        end
    end
    local db=YUI.DB.GetAceDB and YUI.DB:GetAceDB(scope)
    local sv=db and db.sv
    for _,key in ipairs({"char","profileKeys"}) do for character in pairs(sv and sv[key] or {}) do
        if type(character)=="string" then
            local name,realm=character:match("^(.-) %- (.+)$")
            Add(name or character,realm or currentRealm)
        end
    end end
    return index
end
function M:Record(scope)
    local money=S.SafeNumber(Read(GetMoney))
    local realm=S.SafeString(Read(GetRealmName))
    local name=PlayerName()
    if not money or money<0 or not realm or realm=="" or not name or name=="" then return nil end
    local global=YUI.DB:GetGlobal(scope);if not global then return nil end
    global.Gold=global.Gold or {}
    local data=global.Gold[realm]
    if not data then data={};global.Gold[realm]=data end
    for _,key in ipairs(fields) do data[key]=data[key] or {} end
    local _,class=UnitClass("player")
    class=S.SafeString(class) or data.class[name]
    local faction=S.SafeString(Read(UnitFactionGroup,"player")) or data.faction[name]
    local guid=S.SafeString(Read(UnitGUID,"player")) or data.guid[name]
    local client=Client()
    self:RememberCharacter(scope,{name=name,realm=realm,guid=guid,client=client})
    local short=client=="forever" and S.SafeString(Read(UnitName,"player"))
    if short and short~=name and data.money[short]~=nil and not data.guid[short] then
        -- A legacy short key is ambiguous when surnames are enabled. Retain its
        -- contents without treating it as a second, identified character.
        data.legacyNames=data.legacyNames or {}
        local record={};for _,key in ipairs(fields) do record[key]=data[key][short];data[key][short]=nil end
        data.legacyNames[short]=record
    end
    if guid and data.guid[name]~=guid then for previous,previousGUID in pairs(data.guid) do
        if previous~=name and previousGUID==guid and (not data.client[previous] or data.client[previous]==client) then
            for _,key in ipairs(fields) do data[key][previous]=nil end
        end
    end end
    if data.money[name]==money and data.class[name]==class and data.faction[name]==faction
        and data.guid[name]==guid and data.client[name]==client then return money end
    data.money[name],data.class[name],data.faction[name]=money,class,faction
    data.guid[name],data.updated[name],data.client[name]=guid,Read(time) or 0,client
    return money
end
function M:Summary(scope)
    local currentRealm=S.SafeString(Read(GetRealmName)) or ""
    local currentName=PlayerName()
    local currentGUID=S.SafeString(Read(UnitGUID,"player"))
    local realms={[Realm(currentRealm)]=true}
    local connected=Read(GetAutoCompleteRealms)
    if S.CanAccessTable(connected) then for _,name in ipairs(connected) do
        name=S.SafeString(name);if name then realms[Realm(name)]=true end
    end end
    local global=YUI.DB:GetGlobal(scope)
    local fullNames=FullNames(scope,currentRealm,global)
    local candidates,byGUID={},{}
    for realm,data in pairs(global and global.Gold or {}) do
        if realms[Realm(realm)] and type(data)=="table" then
            for name,amount in pairs(data.money or {}) do
                local money=S.SafeNumber(amount)
                local client=data.client and data.client[name]
                if type(name)=="string" and money and money>=0 and (not client or client==Client()) then
                    local guid=data.guid and data.guid[name]
                    local names=fullNames[Realm(realm)]
                    local displayName=names and (guid and names.guid[guid] or names.short[name]) or name
                    displayName=displayName or name
                    local row={name=displayName,realm=realm,money=money,class=data.class and data.class[name],faction=data.faction and data.faction[name],
                        guid=guid,updated=data.updated and data.updated[name] or 0,
                        current=displayName==currentName and Realm(realm)==Realm(currentRealm) and (not guid or not currentGUID or guid==currentGUID)}
                    if guid then
                        local previous=byGUID[guid]
                        if not previous or row.current or not previous.current and (row.updated>previous.updated
                            or row.updated==previous.updated and realm..name<previous.realm..previous.name) then byGUID[guid]=row end
                    else candidates[#candidates+1]=row end
                end
            end
        end
    end
    for _,row in pairs(byGUID) do candidates[#candidates+1]=row end
    table.sort(candidates,function(a,b)
        if a.money~=b.money then return a.money>b.money end
        if a.realm~=b.realm then return a.realm<b.realm end
        return a.name<b.name
    end)
    local result={rows=candidates,total=0,Alliance=0,Horde=0,multipleRealms=false}
    for _,row in ipairs(candidates) do
        result.total=result.total+row.money
        if row.faction=="Alliance" or row.faction=="Horde" then result[row.faction]=result[row.faction]+row.money end
        if Realm(row.realm)~=Realm(currentRealm) then result.multipleRealms=true end
    end
    return result
end
function M:AppendTooltip(tooltip,scope,labels,formatMoney)
    self:Record(scope)
    local summary=self:Summary(scope)
    tooltip:AddLine(labels.characters)
    for _,row in ipairs(summary.rows) do
        local color=(CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[row.class]
        local name=row.name..(summary.multipleRealms and " "..row.realm or "")
        if row.faction=="Alliance" or row.faction=="Horde" then
            name="|TInterface\\FriendsFrame\\PlusManz-"..row.faction..":14|t "..name
        end
        if row.current then name=name.." |TInterface\\COMMON\\Indicator-Green:12|t" end
        tooltip:AddDoubleLine(name,formatMoney(row.money),color and color.r or 1,color and color.g or 1,color and color.b or 1,1,1,1)
    end
    if summary.Alliance>0 and summary.Horde>0 then
        tooltip:AddLine(" ")
        tooltip:AddDoubleLine(labels.alliance,formatMoney(summary.Alliance),.2,.7,1,1,1,1)
        tooltip:AddDoubleLine(labels.horde,formatMoney(summary.Horde),1,.3,.3,1,1,1)
    end
    tooltip:AddLine(" ");tooltip:AddDoubleLine(labels.total,formatMoney(summary.total),1,1,1,1,1,1)
    return summary.total
end
