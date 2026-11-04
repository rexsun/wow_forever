local _, YUI = ...
YUI = _G.YUI or YUI
if not YUI then return end
YUI.API = YUI.API or {}
local A = {}
YUI.API.SoundEvents = A
local function Public(value) return not (issecretvalue and issecretvalue(value)) end
local function Bool(value) if Public(value) and type(value)=='boolean' then return value end end
local function Number(value) if Public(value) and type(value)=='number' and value==value then return value end end
local function Text(value) if Public(value) and type(value)=='string' then return value end end
function A.Available(id)
    if id=='quest-complete' then return C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.IsComplete and true or false end
    if id=='mail-received' then return type(HasNewMail)=='function' end
    if id=='bags-full' then return C_Container and C_Container.GetContainerNumFreeSlots and true or false end
    if id=='repair-needed' then return type(GetInventoryItemDurability)=='function' end
    if id=='teammate-dead' or id=='tank-dead' or id=='healer-dead' then return type(UnitIsDeadOrGhost)=='function' end
    if id=='rare-found' then return type(UnitClassification)=='function' end
    if id=='queue-ready' then return YUI.IsRetail or type(GetBattlefieldStatus)=='function' end
    return true
end
function A.QuestStates(out)
    local count=C_QuestLog and C_QuestLog.GetNumQuestLogEntries and Number(C_QuestLog.GetNumQuestLogEntries()) or 0
    for index=1,math.min(count,1000) do
        local info=C_QuestLog.GetInfo(index)
        local id=info and Number(info.questID)
        if id and id>0 and Bool(info.isHeader)~=true then out[id]=Bool(C_QuestLog.IsComplete(id)) end
    end
end
function A.Mail() return HasNewMail and Bool(HasNewMail()) end
function A.BagsFull()
    local total=0
    for bag=0,4 do
        local free,family=C_Container.GetContainerNumFreeSlots(bag)
        free,family=Number(free),Number(family)
        if free==nil or family==nil then return nil end
        if family==0 then total=total+free end
    end
    return total==0
end
function A.NeedsRepair(threshold)
    local minimum
    for slot=1,19 do
        local current,maximum=GetInventoryItemDurability(slot)
        current,maximum=Number(current),Number(maximum)
        if current and maximum and maximum>0 then
            local percent=current/maximum*100
            minimum=minimum and math.min(minimum,percent) or percent
        end
    end
    if minimum then return minimum<threshold end
end
function A.IsRaid() return IsInRaid and Bool(IsInRaid())==true end
function A.Exists(unit) return UnitExists and Bool(UnitExists(unit))==true end
function A.IsPlayer(unit) return UnitIsUnit and Bool(UnitIsUnit(unit,'player'))==true end
function A.Dead(unit) if A.Exists(unit) then return Bool(UnitIsDeadOrGhost(unit)) end end
function A.Role(unit)
    local role=UnitGroupRolesAssigned and Text(UnitGroupRolesAssigned(unit))
    if role=='TANK' or role=='HEALER' or role=='DAMAGER' then return role end
end
function A.QueueStates(out)
    for index=1,MAX_BATTLEFIELD_QUEUES or 3 do out['pvp:'..index]=GetBattlefieldStatus and Text(GetBattlefieldStatus(index))=='confirm' or false end
end
function A.RareUnit(unit)
    if not A.Exists(unit) or A.Dead(unit)~=false then return end
    local class=UnitClassification and Text(UnitClassification(unit))
    if class~='rare' and class~='rareelite' then return end
    local guid=UnitGUID and Text(UnitGUID(unit))
    if guid and guid:match('^Creature%-') then return guid end
end
-- Only nearby minimap kill markers with a public creature identity qualify.
-- The atlas allowlist deliberately excludes generic events and treasures.
local rareAtlases={VignetteKill=true, VignetteKillElite=true}
function A.RareVignette(guid,onMinimap)
    if not YUI.IsRetail or not Text(guid) or Bool(onMinimap)~=true then return end
    local info=C_VignetteInfo and C_VignetteInfo.GetVignetteInfo and C_VignetteInfo.GetVignetteInfo(guid)
    if not info then return end
    local atlas,object=Text(info.atlasName),Text(info.objectGUID)
    if atlas and rareAtlases[atlas] and Bool(info.isDead)==false and object and object:match('^Creature%-') then return object end
end
function A.RareBaseline(visit)
    if not YUI.IsRetail or not (C_VignetteInfo and C_VignetteInfo.GetVignettes) then return end
    local guids=C_VignetteInfo.GetVignettes()
    if not Public(guids) or type(guids)~='table' then return end
    for index=1,math.min(#guids,512) do
        local guid=Text(guids[index])
        local info=guid and C_VignetteInfo.GetVignetteInfo(guid)
        if info and Bool(info.onMinimap)==true then visit(A.RareVignette(guid,true)) end
    end
end
