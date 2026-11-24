local _, YUI = ...
if not YUI or not (YUI.IsRetail or YUI.IsForever) then return end
local A = {}
YUI.API.Bags = A
local S = YUI.API.Security
local metadata = {}
-- 国服 wowf 1.60.1.70938 / zhCN，使用 wowdata sql 查询本机 DB2。
-- SELECT x.ItemID, e.Charges FROM ItemXItemEffect x
-- JOIN ItemEffect e ON e.ID = x.ItemEffectID JOIN Item i ON i.ID = x.ItemID
-- LEFT JOIN ItemSparse s ON s.ID = x.ItemID
-- WHERE e.TriggerType = 0 AND (e.Charges < -1 OR e.Charges > 0
--   OR (e.Charges = -1 AND i.ClassID IN (2,4) AND i.InventoryType <> 0 AND s.ID IS NOT NULL))
-- ORDER BY x.ItemID
-- -1 也常用于普通一次性消耗品，只为有 ItemSparse 记录和装备部位的武器、护甲读取提示。
-- 表中保留带符号的上限，剩余次数只认真实槽位的次数行。
local chargeLimits = {
    [836]=-10, [872]=30, [1186]=-10, [1187]=-5, [1191]=-10, [1262]=-5, [1402]=-5,
    [1403]=-10, [1472]=-10, [1533]=-3, [1612]=-5, [1622]=-3, [1700]=-3, [1851]=-5,
    [1912]=-10, [1918]=-5, [1995]=-3, [3251]=-10, [3441]=-10, [3507]=-5, [4376]=-5,
    [4381]=-10, [4386]=-5, [4388]=-5, [4403]=-8, [4444]=5, [4546]=-3, [5251]=5,
    [5387]=1, [5613]=3, [5880]=-5, [7247]=10, [7667]=-5, [8051]=10, [9449]=3,
    [10444]=2, [10577]=6, [10831]=-5, [11582]=-5, [11702]=30, [12300]=-5, [12323]=-5,
    [12815]=-5, [12906]=-4, [12928]=10, [13508]=-3, [13514]=-3, [15723]=-3, [15736]=-10,
    [15778]=-3, [15826]=-10, [15875]=-5, [15908]=3, [15911]=3, [15913]=3, [15914]=3,
    [15915]=3, [15916]=3, [15917]=3, [15919]=3, [15920]=3, [15921]=3, [15922]=3,
    [15923]=3, [16991]=-20, [18149]=-20, [18150]=-20, [18637]=-10, [20387]=-3, [20397]=-5,
    [20398]=-5, [20399]=-5, [20409]=-5, [20410]=-5, [20411]=-5, [20413]=-5, [20414]=-5,
    [20744]=-5, [20745]=-5, [20746]=-5, [20747]=-5, [20748]=-5, [20749]=-5, [20750]=-5,
    [21267]=-3, [21325]=-3, [21713]=-88, [21813]=-10, [21829]=-10, [21833]=-10, [21834]=-10,
    [23163]=-5, [23379]=-3, [191272]=-3, [204572]=1, [211848]=-5, [219963]=-4, [219965]=-4,
    [219983]=-4, [219984]=-4, [219985]=-4, [219986]=-4, [219987]=-4, [219988]=-4, [219989]=-4,
    [219990]=-4, [219991]=-4, [219992]=-4, [219993]=-4, [219994]=-4, [219995]=-4, [219996]=-4,
    [219997]=-4, [219998]=-4, [220053]=-4, [220054]=-4, [220055]=-4, [220056]=-4, [220057]=-4,
    [220058]=-4, [220059]=-4, [220060]=-4, [220061]=-4, [220062]=-4, [220063]=-4, [220064]=-4,
    [220065]=-4, [220066]=-4, [220067]=-4, [220068]=-4, [220069]=-4, [220070]=-4, [220071]=-4,
    [220072]=-4, [220073]=-4, [220074]=-4, [220075]=-4, [220076]=-4, [220077]=-4, [220078]=-4,
    [220079]=-4, [220080]=-4, [220081]=-4, [220082]=-4, [220083]=-4, [220084]=-4, [220085]=-4,
    [220086]=-4, [220087]=-4, [220088]=-4, [220089]=-4, [220090]=-4, [220091]=-4, [220092]=-4,
    [220093]=-4, [220094]=-4, [220095]=-4, [220096]=-4, [220097]=-4, [220098]=-4, [220099]=-4,
    [220100]=-4, [220101]=-4, [220102]=-4, [220103]=-4, [220104]=-4, [220105]=-4, [220106]=-4,
    [224806]=-5, [224893]=-2, [226856]=-3, [227286]=-2, [227768]=3, [228980]=-5, [232611]=-5,
    [233197]=-3, [233213]=-10, [233215]=-10, [233216]=-10, [233217]=-10, [233226]=-10, [233250]=-3,
    [233996]=-5, [234142]=-200, [234180]=2, [260802]=-8, [260806]=3, [260810]=3, [260819]=3,
    [260820]=3, [260821]=3, [260828]=3, [260829]=3, [260830]=3, [264163]=3, [266158]=3,
    [266253]=3, [266254]=3, [267272]=3, [267298]=3, [270298]=5, [273817]=20, [274918]=-5,
    [275633]=-5, [275688]=-5, [278194]=-5, [279395]=-6, [282720]=-5, [284666]=-5, [285104]=-5,
    [287979]=-5,
    -- 主动使用、最后一次消耗物品的单次装备。
    [4750]=-1, [4760]=-1, [4762]=-1, [4956]=-1, [5230]=-1, [5231]=-1, [5408]=-1,
    [5409]=-1, [12443]=-1, [205218]=-1, [205420]=-1, [206376]=-1, [206381]=-1, [206382]=-1,
    [206383]=-1, [206384]=-1, [206385]=-1, [206386]=-1, [206387]=-1, [206388]=-1, [206389]=-1,
    [206390]=-1, [206391]=-1, [206954]=-1, [208414]=-1, [208689]=-1, [208849]=-1, [208851]=-1,
    [210195]=-1, [210534]=-1, [211472]=-1, [213513]=-1, [213594]=-1, [220915]=-1, [225838]=-1,
    [227444]=-1, [277518]=-1,
}
-- wowf 1.60.1.70938. Regenerate from item use spells via Docs/Products/YBags/forever-camp-items.md.
local camp = {
    [279938]=true, [279940]=true, [279941]=true, [279943]=true, [279944]=true, [279945]=true,
    [279947]=true, [279948]=true, [279949]=true, [279950]=true, [279951]=true, [279952]=true,
    [279955]=true, [279956]=true, [279957]=true, [279959]=true, [279960]=true, [279961]=true,
    [279962]=true, [279964]=true, [279965]=true, [279966]=true, [279967]=true, [279968]=true,
    [279969]=true, [279970]=true, [279972]=true, [279973]=true, [279974]=true, [279976]=true,
    [279978]=true, [279979]=true, [279981]=true, [279982]=true, [279985]=true, [279987]=true,
    [279988]=true, [279989]=true, [279990]=true,
}
local function Number(value) return S.SafeNumber(value) end
local function String(value) return S.SafeString(value) end
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and not S.IsSecretValue(value) then return value end
end
local function Visible(frame)
    return frame and not frame:IsForbidden() and S.SafeBoolean(frame:IsShown()) == true
end
function A.InCombat() return S.SafeBoolean(S.InCombatLockdown()) ~= false end
local function ReadableTable(value)
    return type(value)=="table" and not S.IsSecretValue(value) and S.CanAccessTable(value)~=false
end
-- Read only during capture of a blocked native click.
function A.ItemUseMouseFocus()
    local mouse=String(Call(GetMouseButtonClicked))
    local foci=Call(GetMouseFoci)
    local focus=ReadableTable(foci) and foci[1]
    if not ReadableTable(focus) or Call(focus.IsForbidden,focus)~=false then return nil,nil,mouse end
    local parent=Call(focus.GetParent,focus)
    return focus,ReadableTable(parent) and parent or nil,mouse
end
function A.ItemUseButtonSlot(button)
    if Call(button.IsForbidden,button)~=false then return end
    return Number(Call(button.GetBagID,button)),Number(Call(button.GetID,button))
end
function A.ItemUseCombatState()
    return S.SafeBoolean(Call(UnitAffectingCombat,"player")),S.SafeBoolean(Call(S.InCombatLockdown))
end
function A.CursorBusy()
    if type(GetCursorInfo)=="function" then
        local ok,kind=pcall(GetCursorInfo)
        if not ok or S.IsSecretValue(kind) then return true end
        return kind~=nil
    end
    return type(CursorHasItem)=="function" and S.SafeBoolean(CursorHasItem())~=false
end
function A.CursorKind() return String(Call(GetCursorInfo)) end
function A.HandleModifiedClick(link)
    return S.SafeBoolean(Call(HandleModifiedItemClick,link))==true
end
function A.PlayerPortrait(texture)
    if not texture or type(SetPortraitTexture)~="function" then return false end
    return pcall(SetPortraitTexture,texture,"player")
end
function A.PlayerName()
    local unit=YUI.API.Unit
    local fn=unit and unit.GetCharacterName or YUI.IsForever and NameUtil and NameUtil.FormatUnitNameForDisplay or UnitName
    return String(Call(fn,"player"))
end
function A.CharacterInfo()
    local result={}
    if type(UnitClass)=="function" then
        local ok,_,class=pcall(UnitClass,"player")
        if ok then result.classFile=String(class) end
    end
    if type(UnitRace)=="function" then
        local ok,_,race=pcall(UnitRace,"player")
        if ok then result.raceFile=String(race) end
    end
    result.sex=Number(Call(UnitSex,"player"))
    return result
end
function A.GuildIdentity()
    if type(GetGuildInfo)~="function" then return nil end
    local ok,name,_,_,realm=pcall(GetGuildInfo,"player")
    name=ok and String(name)
    if not name or name=="" then return nil end
    realm=String(realm)
    if not realm or realm=="" then realm=String(Call(GetNormalizedRealmName)) or String(Call(GetRealmName)) end
    if not realm then return nil end
    return {name=name,realm=realm,key=realm..":"..name}
end
function A.BagSlotType(id)
    local reagent=S.SafeBoolean(Call(ContainerFrame_IsReagentBag,id))
    if reagent~=nil then return reagent and "reagent" or "bag" end
    local constants=Constants and Constants.InventoryConstants
    local reagentSlots=Number(constants and constants.NumReagentBagSlots) or Number(NUM_REAGENTBAG_SLOTS) or 0
    if (YUI.IsRetail or reagentSlots>0) and Enum and Enum.BagIndex and id==Enum.BagIndex.ReagentBag then return "reagent" end
    return "bag"
end
function A.SpaceKey(id,family,kind)
    if A.IsKeyring(id) then return "keyring" end
    family=Number(family) or 0
    -- On Forever a profession bag keeps its family even in the material socket.
    if (family==0 or not YUI.IsForever) and (kind==nil or kind=="bags") and A.BagSlotType(id)=="reagent" then
        return "reagent"
    end
    return family~=0 and "family:"..family or "normal"
end
function A.ItemCount(id)
    local fn=C_Item and C_Item.GetItemCount or GetItemCount
    return Number(Call(fn,id,false,false,false,false))
end
function A.InventoryItem(slot)
    if type(GetInventoryItemID)~="function" or type(GetInventoryItemCount)~="function" then return nil,"unavailable" end
    local exists=S.SafeBoolean(Call(C_Item and C_Item.DoesItemExist,{equipmentSlotIndex=slot}))
    if exists==false then return nil end
    if exists~=true then return nil,"pending" end
    local id=Number(Call(GetInventoryItemID,"player",slot))
    local count=Number(Call(GetInventoryItemCount,"player",slot))
    if not id or id<1 or id~=math.floor(id) or not count or count<1 or count~=math.floor(count) then return nil,"pending" end
    return {itemID=id,count=count}
end
local function InventoryEntries(slots)
    local entries={}
    for _,slot in ipairs(slots) do
        local item,err=A.InventoryItem(slot)
        if err then return nil end
        if item then entries[#entries+1]=item end
    end
    return entries
end
function A.ReadEquipment(bankBags)
    if type(IsLoggedIn)=="function" and S.SafeBoolean(Call(IsLoggedIn))~=true then return nil end
    local slots={}
    if bankBags then
        if A.Context()~="bank" then return nil end
        local bags=A.BankBags("bank");if #bags==0 then return nil end
        for _,bag in ipairs(bags) do if bag>0 then
            local slot=Number(Call(C_Container and C_Container.ContainerIDToInventoryID,bag))
            if slot then slots[#slots+1]=slot end
        end end
    else
        local first=Number(Call(C_Container and C_Container.ContainerIDToInventoryID,1))
        if not first or first<1 or first>64 then return nil end
        for slot=0,first-1 do slots[#slots+1]=slot end
        for _,socket in ipairs(A.BagSockets()) do slots[#slots+1]=socket.inventoryID end
    end
    return InventoryEntries(slots)
end
function A.BagState(inventoryID)
    local ok,rawID=pcall(GetInventoryItemID,"player",inventoryID)
    if not ok or S.IsSecretValue(rawID) then return nil,"pending" end
    if rawID==nil or rawID==0 then
        local readable,icon=pcall(GetInventoryItemTexture,"player",inventoryID)
        if readable and not S.IsSecretValue(icon) and (icon==nil or icon==0) then return nil end
        return nil,"pending"
    end
    local itemID=Number(rawID)
    if not itemID or itemID<1 or itemID~=math.floor(itemID) then return nil,"pending" end
    local link=String(Call(GetInventoryItemLink,"player",inventoryID))
    local guid=String(Call(C_Item and C_Item.GetItemGUID,{equipmentSlotIndex=inventoryID}))
    if not link and not guid then return nil,"pending" end
    -- An equipped bag is a single item, even if the equipment stack APIs have no count for its socket.
    return {itemID=itemID,link=link,guid=guid,count=1,classID=1,equipLoc="INVTYPE_BAG",family=0,maxStack=1}
end
function A.UnequipBag(inventoryID)
    if A.InCombat() or A.CursorBusy() or type(PickupBagFromSlot)~="function" then return false end
    local ok=pcall(PickupBagFromSlot,inventoryID)
    return ok and A.CursorBusy()
end
function A.RestoreBag(inventoryID)
    if A.InCombat() or not A.CursorBusy() or type(PutItemInBag)~="function" then return false end
    local ok=pcall(PutItemInBag,inventoryID)
    return ok and not A.CursorBusy()
end
local function Attachment(entries,fn,...)
    local ok,name,id,icon,count,_,_,currency=pcall(fn,...)
    if not ok or S.IsSecretValue(id) or S.IsSecretValue(name) or S.IsSecretValue(icon) or S.IsSecretValue(count) or S.IsSecretValue(currency) then return false end
    if currency==true then return true end
    if id==nil then return name==nil and icon==nil and (count==nil or count==0) end
    id,count=Number(id),Number(count)
    if not id or id<1 or not count or count<1 then return false end
    entries[#entries+1]={itemID=id,count=count}
    return true
end
function A.ReadMail(outgoing,mailIndex)
    local entries={}
    local complete=true
    local limit=Number(outgoing and ATTACHMENTS_MAX_SEND or ATTACHMENTS_MAX_RECEIVE) or 16
    if limit<1 or limit>32 then return nil end
    if outgoing then
        if type(GetSendMailItem)~="function" then return nil end
        for slot=1,limit do if not Attachment(entries,GetSendMailItem,slot) then return nil end end
    else
        if type(GetInboxNumItems)~="function" or type(GetInboxItem)~="function" or type(GetInboxHeaderInfo)~="function" then return nil end
        local ok,loaded,total=pcall(GetInboxNumItems)
        if not ok or S.IsSecretValue(total) then return nil end
        loaded,total=Number(loaded),Number(total)
        if not loaded or loaded<0 or loaded>3000 then return nil end
        complete=not total or loaded>=total
        if mailIndex and (type(mailIndex)~="number" or mailIndex~=math.floor(mailIndex) or mailIndex<1 or mailIndex>loaded) then return nil end
        for mail=mailIndex or 1,mailIndex or loaded do
            local valid,_,_,_,_,_,_,days=pcall(GetInboxHeaderInfo,mail);days=valid and Number(days)
            if not days or days<0 then return nil end
            local first=#entries+1
            for slot=1,limit do if not Attachment(entries,GetInboxItem,mail,slot) then return nil end end
            for n=first,#entries do entries[n].expires=math.floor(time()+days*86400) end
        end
    end
    return entries,complete
end
function A.ReadReturnedMail(index)
    index=Number(index);if not index then return nil end
    if type(GetInboxHeaderInfo)~="function" then return nil end
    local ok,_,_,sender=pcall(GetInboxHeaderInfo,index)
    sender=ok and String(sender)
    if not sender then return nil end
    local entries=A.ReadMail(false,index)
    if entries then for _,item in ipairs(entries) do item.expires=nil end end
    return sender,entries
end
function A.LegacyAuctions()
    local legacy=S.SafeBoolean(Call(IsUsingLegacyAuctionClient))
    return legacy==true or not (C_AuctionHouse and type(C_AuctionHouse.GetNumOwnedAuctions)=="function")
end
function A.RequestOwnedAuctions()
    local fn=A.LegacyAuctions() and GetOwnerAuctionItems or C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions
    if type(fn)~="function" then return false end
    if A.LegacyAuctions() then return pcall(fn) end
    return pcall(fn,{})
end
function A.ReadAuctions()
    local entries={}
    local complete=true
    if A.LegacyAuctions() then
        if type(GetNumAuctionItems)~="function" then return nil end
        local ok,listed,total=pcall(GetNumAuctionItems,"owner")
        local size=ok and Number(listed)
        if S.IsSecretValue(total) or not size or size<0 or size>10000 or type(GetAuctionItemInfo)~="function" then return nil end
        complete=not Number(total) or size>=Number(total)
        for index=1,size do
            local ok,_,_,count,_,_,_,_,_,_,_,_,_,_,_,_,_,id=pcall(GetAuctionItemInfo,"owner",index)
            id,count=ok and Number(id),Number(count)
            if not id or not count or count<1 then return nil end
            entries[#entries+1]={itemID=id,count=count}
        end
    else
        local size=Number(Call(C_AuctionHouse.GetNumOwnedAuctions))
        if not size or size<0 or size>10000 then return nil end
        for index=1,size do
            local item=Call(C_AuctionHouse.GetOwnedAuctionInfo,index)
            if not S.CanAccessTable(item) then return nil end
            local active=Enum and Enum.AuctionStatus and Enum.AuctionStatus.Active
            local status=Number(item.status)
            if active==nil or status==nil then return nil end
            if status==active then
                if not S.CanAccessTable(item.itemKey) then return nil end
                local id,count=Number(item.itemKey.itemID),Number(item.quantity)
                if not id or id<1 or not count or count<1 then return nil end
                local remaining=Number(item.timeLeftSeconds)
                entries[#entries+1]={itemID=id,count=count,expires=remaining and math.floor(time()+remaining) or nil}
            end
        end
    end
    return entries,complete
end
function A.ReadVoid()
    if type(GetVoidItemInfo)~="function" or S.SafeBoolean(Call(CanUseVoidStorage))~=true then return nil end
    local entries={}
    for page=1,2 do for slot=1,80 do
        local ok,id,icon=pcall(GetVoidItemInfo,page,slot)
        if not ok or S.IsSecretValue(id) or S.IsSecretValue(icon) then return nil end
        if id~=nil then
            id=Number(id);if not id or id<1 then return nil end
            entries[#entries+1]={itemID=id,count=1}
        elseif icon~=nil then return nil end
    end end
    return entries
end
function A.RegisterMailSend(callback)
    if type(SendMail)~="function" or type(hooksecurefunc)~="function" then return false end
    hooksecurefunc("SendMail",callback)
    return true
end
function A.RegisterMailReturn(callback)
    if type(ReturnInboxItem)~="function" or type(hooksecurefunc)~="function" then return false end
    hooksecurefunc("ReturnInboxItem",callback)
    return true
end
function A.StorageOpen(kind)
    if kind=="mail" then return Visible(MailFrame) or false end
    if kind=="auctions" then return Visible(AuctionHouseFrame) or Visible(AuctionFrame) or false end
    local id=Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.VoidStorageBanker
    return kind=="void" and id~=nil and S.SafeBoolean(Call(C_PlayerInteractionManager and C_PlayerInteractionManager.IsInteractingWithNpcOfType,id))==true or false
end
function A.ClearNewItem(bag,slot)
    if C_NewItems and type(C_NewItems.RemoveNewItem)=="function" then Call(C_NewItems.RemoveNewItem,bag,slot) end
end
function A.CharacterAppearance(character)
    local race=String(character.raceFile)
    local sex=Number(character.sex)
    local raceAtlas
    if race and (sex==2 or sex==3) then
        local aliases={scourge="undead",highmountaintauren="highmountain",lightforgeddraenei="lightforged",zandalaritroll="zandalari",earthendwarf="earthen",harronir="haranir"}
        local key=race:lower();key=aliases[key] or key
        local gender=sex==2 and "male" or "female"
        raceAtlas=String(Call(GetRaceAtlas,race:lower(),gender)) or ((YUI.IsRetail and "raceicon128-" or "raceicon-")..key.."-"..gender)
    end
    local class=String(character.classFile)
    local classAtlas=class and String(Call(GetClassAtlas,class:lower()))
    if C_Texture and type(C_Texture.GetAtlasInfo)=="function" then
        if raceAtlas and not Call(C_Texture.GetAtlasInfo,raceAtlas) then raceAtlas=nil end
        if classAtlas and not Call(C_Texture.GetAtlasInfo,classAtlas) then classAtlas=nil end
    end
    local colors=CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local color=class and colors and colors[class]
    return raceAtlas,classAtlas,color and Number(color.r) or 1,color and Number(color.g) or 1,color and Number(color.b) or 1
end
local function ItemFamily(id,link)
    -- Native placement on Forever 1.60.1.71037 confirms the herb bag accepts Incense Candle.
    if YUI.IsForever and id==279962 then return 32 end
    return Number(Call(C_Item and C_Item.GetItemFamily or GetItemFamily,link or id)) or 0
end
function A.CursorItem()
    if type(GetCursorInfo)~="function" then return nil end
    local ok,kind,id,link=pcall(GetCursorInfo)
    if not ok or String(kind)~="item" then return nil end
    id=Number(id);link=String(link)
    if not id then return nil end
    local info=YUI.API.Item.GetInfo(link or id)
    return {itemID=id,link=link,classID=type(info)=="table" and Number(info.classID),subClassID=type(info)=="table" and Number(info.subclassID),
        equipLoc=type(info)=="table" and String(info.equipLoc),isCraftingReagent=type(info)=="table" and S.SafeBoolean(info.isCraftingReagent),
        family=ItemFamily(id,link)}
end
function A.ClassOptions()
    local options={}
    for id=0,20 do
        local name=String(Call(C_Item and C_Item.GetItemClassInfo,id))
        if name and name~="" then options[#options+1]={value=id,text=name} end
    end
    return options
end
function A.Now() return GetTime() end
function A.MoneyText(amount,fontHeight)
    amount=math.max(0,math.floor(Number(amount) or 0))
    local text=String(Call(C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString,amount,fontHeight or 12))
    if text then return text end
    text=String(Call(GetMoneyString,amount)) or String(Call(GetCoinTextureString,amount,fontHeight or 12))
    if text then return text end
    local gold=math.floor(amount/10000)
    local silver=math.floor(amount/100)%100
    local copper=amount%100
    return string.format("%d|TInterface\\MoneyFrame\\UI-GoldIcon:12|t %d|TInterface\\MoneyFrame\\UI-SilverIcon:12|t %d|TInterface\\MoneyFrame\\UI-CopperIcon:12|t",gold,silver,copper)
end
function A.CurrencyInfo(id)
    local info=Call(C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo,id)
    if not S.CanAccessTable(info) then return nil end
    local name=String(info.name)
    if not name or name=="" then return nil end
    return {kind="currency",id=id,name=name,icon=Number(info.iconFileID),count=Number(info.quantity),max=Number(info.maxQuantity)}
end
function A.CurrencyList()
    local result,expanded={},{}
    local namespace=C_CurrencyInfo
    if not namespace or type(namespace.GetCurrencyListInfo)~="function" then return result end
    local index=1
    local size=math.min(2000,Number(Call(namespace.GetCurrencyListSize)) or 0)
    while index<=size do
        local info=Call(namespace.GetCurrencyListInfo,index)
        if S.CanAccessTable(info) then
            if S.SafeBoolean(info.isHeader)==true then
                if S.SafeBoolean(info.isHeaderExpanded)==false and type(namespace.ExpandCurrencyList)=="function" then
                    local name=String(info.name)
                    Call(namespace.ExpandCurrencyList,index,true)
                    local current=Call(namespace.GetCurrencyListInfo,index)
                    if S.CanAccessTable(current) and String(current.name)==name and S.SafeBoolean(current.isHeaderExpanded)==true then
                        expanded[#expanded+1]={index=index,name=name}
                    end
                    size=math.min(2000,Number(Call(namespace.GetCurrencyListSize)) or size)
                end
            else
                local id=Number(info.currencyID)
                local value=id and A.CurrencyInfo(id)
                if value then result[#result+1]=value end
            end
        end
        index=index+1
    end
    for n=#expanded,1,-1 do
        local header=expanded[n]
        local current=Call(namespace.GetCurrencyListInfo,header.index)
        if S.CanAccessTable(current) and String(current.name)==header.name and S.SafeBoolean(current.isHeader)==true then
            Call(namespace.ExpandCurrencyList,header.index,false)
        end
    end
    return result
end
function A.Context()
    if Visible(MerchantFrame) then return "merchant" end
    if Visible(BankFrame) or Visible(GuildBankFrame) then return "bank" end
    if Visible(TradeFrame) then return "trade" end
    if Visible(MailFrame) then return "mail" end
    if Visible(AuctionHouseFrame) or Visible(AuctionFrame) or Visible(ItemUpgradeFrame) then return "other" end
    return "travel"
end
function A.NpcInteractionState(interactionType)
    local id=Number(interactionType)
    if id==nil then return nil end
    return S.SafeBoolean(Call(C_PlayerInteractionManager and C_PlayerInteractionManager.IsInteractingWithNpcOfType,id))
end
function A.GetCarryBags(includeKeys)
    local ids, seen = {}, {}
    local function Add(id)
        if type(id)=="number" and not seen[id] then ids[#ids+1]=id;seen[id]=true end
    end
    for id=0,NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do Add(id) end
    local reagent=Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
    local reagentSlots=reagent and Number(Call(C_Container.GetContainerNumSlots,reagent))
    if reagentSlots and reagentSlots>0 then Add(reagent) end
    if includeKeys and KEYRING_CONTAINER and (Number(Call(C_Container.GetContainerNumSlots,KEYRING_CONTAINER)) or 0)>0 then Add(KEYRING_CONTAINER) end
    return ids
end
function A.BagSockets()
    -- Equipped sockets exist even when their containers have zero capacity.
    local count=Number(NUM_TOTAL_EQUIPPED_BAG_SLOTS) or (Number(NUM_BAG_SLOTS) or 4)+(Number(NUM_REAGENTBAG_SLOTS) or 0)
    local constants=Constants and Constants.InventoryConstants
    if constants then count=math.max(count,(Number(constants.NumBagSlots) or 0)+(Number(constants.NumReagentBagSlots) or 0)) end
    local sockets={}
    for id=1,count do
        local inventoryID=Number(Call(C_Container.ContainerIDToInventoryID,id))
        if inventoryID then
            local kind=A.BagSlotType(id)
            local background
            if type(GetInventorySlotInfo)=="function" then
                local ok,_,texture=pcall(GetInventorySlotInfo,kind=="reagent" and "ReagentBag0Slot" or "Bag"..(id-1).."Slot")
                if ok then
                    local fileID=Number(texture)
                    background=fileID and fileID>0 and fileID or String(texture)
                    if background=="" then background=nil end
                end
            end
            local icon=Number(Call(GetInventoryItemTexture,"player",inventoryID))
            if icon and icon<=0 then icon=nil end
            local itemID=icon and Number(Call(GetInventoryItemID,"player",inventoryID))
            local link=icon and String(Call(GetInventoryItemLink,"player",inventoryID))
            local quality=icon and Number(Call(GetInventoryItemQuality,"player",inventoryID))
            if icon and quality==nil and (link or itemID) then
                local info=YUI.API.Item.GetInfo(link or itemID)
                quality=type(info)=="table" and Number(info.quality) or nil
            end
            sockets[#sockets+1]={bag=id,inventoryID=inventoryID,kind=kind,itemID=itemID,link=link,quality=quality,
                background=background or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag",icon=icon}
        end
    end
    return sockets
end
function A.CanEquipBag(kind,item)
    if not item then return false end
    -- Uncached item metadata is left to the native inventory-slot validation.
    if item.classID==nil then return true end
    if item.classID~=1 and item.equipLoc~="INVTYPE_BAG" then return false end
    -- The Forever material socket uses the client's equipment validation.
    if YUI.IsForever and kind=="reagent" then return true end
    if item.subClassID==nil then return true end
    local reagent=item.classID==1 and item.subClassID==11
    return kind=="reagent" and reagent or kind~="reagent" and not reagent
end
function A.IsKeyring(id) return KEYRING_CONTAINER and id==KEYRING_CONTAINER or false end
function A.IsBagOpen(id) return S.SafeBoolean(Call(IsBagOpen,id))==true end
function A.BankTabs(kind)
    if not (C_Bank and Enum and Enum.BankType) then return {} end
    local bankType=kind=="shared" and Enum.BankType.Account or Enum.BankType.Character
    if not bankType or S.SafeBoolean(Call(C_Bank.CanViewBank,bankType))~=true then return {} end
    local tabs=Call(C_Bank.FetchPurchasedBankTabData,bankType)
    local result,seen={},{}
    local bankIndexes=YUI.IsForever and kind~="shared" and Enum.BagIndex
    local first=bankIndexes and Number(bankIndexes.CharacterBankTab_1)
    local last=bankIndexes and Number(bankIndexes.CharacterBankTab_9)
    if S.CanAccessTable(tabs) then
        for index,tab in ipairs(tabs) do
            if S.CanAccessTable(tab) then
                local id=Number(tab.ID)
                if id and id==math.floor(id) and not seen[id] and (not first or not last or id>=first and id<=last) then
                    seen[id]=true
                    result[#result+1]={id=id,name=String(tab.name),index=index,icon=Number(tab.icon)}
                end
            end
        end
    end
    return result
end
function A.BankBags(kind)
    local ids={}
    for _,tab in ipairs(A.BankTabs(kind)) do ids[#ids+1]=tab.id end
    return ids
end
function A.IsBankBagSocketContainer(id)
    local indices=YUI.IsForever and Enum and Enum.BagIndex
    if not indices then return false end
    local container=Number(indices.Characterbanktab)
    return container~=nil and Number(id)==container
end
local function BankWindow(kind)
    return kind=="guild" and GuildBankFrame or kind=="bank" and BankFrame or nil
end
function A.BankWindowShown(kind)
    return Visible(BankWindow(kind))
end
function A.FirstPersonalBankBag()
    local indices=YUI.IsForever and Enum and Enum.BagIndex
    return indices and Number(indices.CharacterBankTab_1)
end
local function ReadPurchasedPersonalBankTabs()
    local character=Enum and Enum.BankType and Enum.BankType.Character
    if character~=nil then return Number(Call(C_Bank and C_Bank.FetchNumPurchasedBankTabs,character)) end
end
local bankPanelHook,finishedPersonalBank,trackedPersonalBank
local bankWindowShownCallbacks={}
function A.IsOpeningFirstPersonalBank(beforeShow)
    local frame=BankFrame
    if not bankPanelHook or not frame or finishedPersonalBank==frame or (not beforeShow and not Visible(frame)) then return false end
    local purchased=ReadPurchasedPersonalBankTabs()
    return not purchased or purchased<1
end
function A.BankWindowReady()
    local kind=A.ActiveBankKind()
    if kind=="shared" then return true end
    local first=kind=="bank" and A.FirstPersonalBankBag()
    if not first then return false end
    local purchased=ReadPurchasedPersonalBankTabs()
    if not purchased or purchased<1 then return false end
    local capacity=Number(Call(C_Container and C_Container.GetContainerNumSlots,first))
    return capacity~=nil and capacity>0 and capacity<=512
end
function A.CanUsePersonalBank()
    local bankType=Enum and Enum.BankType and Enum.BankType.Character
    return bankType~=nil and S.SafeBoolean(Call(C_Bank and C_Bank.CanUseBank,bankType))==true
end
function A.GetCarrySortRightToLeft()
    return S.SafeBoolean(Call(C_Container and C_Container.GetSortBagsRightToLeft))
end
function A.SetCarrySortRightToLeft(enabled)
    local setter=C_Container and C_Container.SetSortBagsRightToLeft
    if type(enabled)~="boolean" or type(setter)~="function" then return false end
    -- A successful call requests the preference change. The readback can lag.
    local ok,result=pcall(setter,enabled)
    return ok and not S.IsSecretValue(result) and result~=false
end
function A.SortCarryBags()
    local sort=C_Container and C_Container.SortBags
    if A.InCombat() or A.CursorBusy() or type(sort)~="function" then return false end
    local ok,result=pcall(sort)
    return ok and not S.IsSecretValue(result) and result~=false
end
function A.SortPersonalBank()
    if not YUI.IsForever or A.InCombat() or A.CursorBusy() or not A.BankWindowShown("bank")
        or not A.CanUsePersonalBank() or Call(BankFrame.GetActiveBankType,BankFrame)~=Enum.BankType.Character
        or type(C_Container and C_Container.SortBank)~="function" then return false end
    local ok=pcall(C_Container.SortBank,Enum.BankType.Character)
    return ok
end
local function CharacterBankSockets()
    if not YUI.IsForever or not A.BankWindowShown("bank") or not (Enum and Enum.BagIndex and Enum.BankType and C_Bank)
        or Call(BankFrame.GetActiveBankType,BankFrame)~=Enum.BankType.Character then return end
    return Number(Enum.BagIndex.Characterbanktab),Enum.BankType.Character
end
function A.CanActivateFreePersonalBankTab()
    local _,bankType=CharacterBankSockets()
    if bankType==nil or ReadPurchasedPersonalBankTabs()~=0
        or S.SafeBoolean(Call(C_Bank.CanPurchaseBankTab,bankType))~=true then return false end
    local offer=Call(C_Bank.FetchNextPurchasableBankTabData,bankType)
    return ReadableTable(offer) and Number(offer.tabCost)==0
end
function A.BankBagBar()
    local container,bankType=CharacterBankSockets()
    if not container then return end
    local maximum=Number(Call(C_Bank.FetchMaxNumBankTabs,bankType))
    local purchased=Number(Call(C_Bank.FetchNumPurchasedBankTabs,bankType))
    if not maximum or maximum<1 or maximum>9 or maximum~=math.floor(maximum) then return end
    if purchased and (purchased<0 or purchased>maximum or purchased~=math.floor(purchased)) then purchased=nil end
    local nextTab=purchased and purchased>=1 and purchased<maximum and Call(C_Bank.FetchNextPurchasableBankTabData,bankType)
    local price,affordable
    if S.CanAccessTable(nextTab) then price,affordable=Number(nextTab.tabCost),S.SafeBoolean(nextTab.canAfford) end
    return container,maximum,purchased,price,affordable
end
function A.InitBankBagPurchase(button)
    local _,bankType=CharacterBankSockets()
    if bankType==nil or A.InCombat() then return false end
    button:SetAttribute("overrideBankType",bankType)
    return true
end
function A.BankBagContainer(slot)
    slot=Number(slot)
    if not slot or slot~=math.floor(slot) then return end
    local container,bankType=CharacterBankSockets()
    local first=container and Number(Enum.BagIndex.CharacterBankTab_1)
    local purchased=first and Number(Call(C_Bank.FetchNumPurchasedBankTabs,bankType))
    if purchased and slot>=2 and slot<=purchased then return first+slot-1,container end
end
function A.BankBagInstalled(bag)
    bag=Number(bag)
    local first=Enum and Enum.BagIndex and Number(Enum.BagIndex.CharacterBankTab_1)
    if not first or not bag or bag<=first then return end
    local slot=bag-first+1
    local _,container=A.BankBagContainer(slot)
    if not container then return end
    local item,err=A.Slot(container,slot)
    if not err then return item~=nil end
end
function A.BankSocketQuality(container,slot,item)
    local location={bagID=container,slotIndex=slot}
    local quality=Number(Call(C_Item and C_Item.GetItemQuality,location))
    if quality~=nil then return quality end
    if item.quality~=nil then return item.quality end
    local info=YUI.API.Item.GetInfo(item.link or item.itemID)
    return S.CanAccessTable(info) and Number(info.quality) or nil
end
function A.BankPurchasePending()
    return Call(StaticPopup_FindVisible,"CONFIRM_BUY_BANK_TAB") and true or false
end
function A.MoveBankBag(slot)
    if A.InCombat() or A.Context()~="bank" or not A.CanUsePersonalBank() then return false end
    slot=Number(slot)
    if not slot or slot<2 or slot~=math.floor(slot) then return false end
    local container,bankType=CharacterBankSockets()
    local purchased=container and Number(Call(C_Bank.FetchNumPurchasedBankTabs,bankType))
    if not purchased or slot>purchased then return false end
    local holding=A.CursorBusy()
    if holding then
        local cursor=A.CursorItem()
        if not cursor or cursor.classID~=1 and cursor.equipLoc~="INVTYPE_BAG" then return false end
    end
    local installed,err=A.Slot(container,slot)
    if err or installed and installed.locked then return false end
    if not installed and not holding then return false end
    return A.Pickup(container,slot)
end
function A.ItemOnCursorFromSlot(container,slot,itemID,requireLocation)
    local cursor=Call(C_Cursor and C_Cursor.GetCursorItem)
    if S.CanAccessTable(cursor) then
        local bag,index=Number(cursor.bagID),Number(cursor.slotIndex)
        if bag and index then return bag==container and index==slot end
        if Number(cursor.equipmentSlotIndex) then return false end
    end
    -- A missing location is inconclusive when two physical stacks share an ID.
    if requireLocation then return nil end
    if type(GetCursorInfo)~="function" then return false end
    local ok,kind,id=pcall(GetCursorInfo)
    return ok and String(kind)=="item" and Number(id)==itemID
end
function A.CancelBankBagPickup(container,slot,itemID)
    if not A.CursorBusy() then return true end
    if A.InCombat() or not A.ItemOnCursorFromSlot(container,slot,itemID) then return false end
    Call(ClearCursor)
    if not A.CursorBusy() then return true end
    if A.ItemOnCursorFromSlot(container,slot,itemID) and A.CanUsePersonalBank() then
        local _,activeContainer=A.BankBagContainer(slot)
        local item,err=A.Slot(container,slot)
        if activeContainer==container and not err and (not item or item.itemID==itemID) then
            A.Pickup(container,slot)
        end
    end
    return not A.CursorBusy()
end
function A.HookBankWindowShown(callback)
    if not YUI.IsForever then return false end
    if not bankPanelHook then
        bankPanelHook=S.SafeHook("Bags.BankPanelShown",_G,"ShowUIPanel",function(frame)
            if not frame then return end
            local kind
            if frame==BankFrame then
                kind="bank"
                if Visible(frame) then
                    -- The native OnShow has returned, even if the server still owes us its first tab.
                    if trackedPersonalBank~=frame then
                        frame:HookScript("OnHide",function(owner)
                            if finishedPersonalBank==owner then finishedPersonalBank=nil end
                        end)
                        trackedPersonalBank=frame
                    end
                    finishedPersonalBank=frame
                end
            elseif frame==GuildBankFrame then kind="guild"
            else return end
            for handler in pairs(bankWindowShownCallbacks) do handler(kind) end
        end)
    end
    if bankPanelHook and callback then bankWindowShownCallbacks[callback]=true end
    return bankPanelHook
end
local parkedBanks,bankAnchorHooks={},setmetatable({},{__mode="k"})
local function MoveBankOffscreen(frame,state)
    state.moving=true
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT",UIParent,"TOPRIGHT",32,32)
    state.moving=nil
end
function A.ParkBankWindow(kind)
    local frame=BankWindow(kind)
    if not YUI.IsForever or A.InCombat() or not Visible(frame) or not frame.IsProtected or frame:IsProtected() then return false end
    if parkedBanks[kind] then return parkedBanks[kind].frame==frame end
    if kind=="bank" then
        local character=Enum and Enum.BankType and Enum.BankType.Character
        if character==nil or not C_Bank or Call(C_Bank.CanViewBank,character)~=true
            or Call(frame.GetActiveBankType,frame)~=character or not A.BankWindowReady() then return false end
    end
    if not bankAnchorHooks[frame] then
        -- The panel manager can re-anchor a shown bank while arranging other panels.
        if not S.SafeHook("YBags.BankAnchor",frame,"SetPoint",function(owner)
            local state=parkedBanks[kind]
            if state and state.frame==owner and not state.moving and not owner:IsForbidden() and not owner:IsProtected() then
                MoveBankOffscreen(owner,state)
            end
        end) then return false end
        bankAnchorHooks[frame]=true
    end
    local state={frame=frame,points={},alpha=frame:GetAlpha(),clamped=frame:IsClampedToScreen()}
    for i=1,frame:GetNumPoints() do state.points[i]={frame:GetPoint(i)} end
    parkedBanks[kind]=state
    frame:SetAlpha(0)
    frame:SetClampedToScreen(false)
    MoveBankOffscreen(frame,state)
    return true
end
function A.RestoreBankWindow(kind)
    local state=parkedBanks[kind]
    if not state then return false end
    parkedBanks[kind]=nil
    local frame=state.frame
    if frame:IsForbidden() then return false end
    frame:ClearAllPoints()
    for _,point in ipairs(state.points) do frame:SetPoint((unpack or table.unpack)(point,1,5)) end
    frame:SetClampedToScreen(state.clamped)
    frame:SetAlpha(state.alpha)
    return true
end
function A.CloseBankWindow(kind)
    local frame=BankWindow(kind)
    if not A.InCombat() and Visible(frame) and type(HideUIPanel)=="function" then HideUIPanel(frame) end
end
function A.InitCharacterBankButton(button,bag,slot)
    local bankType=Enum and Enum.BankType and Number(Enum.BankType.Character)
    if A.InCombat() or bankType==nil or not button.Init then return false end
    button:Init(bankType,bag,slot)
    return true
end
function A.CurrentGuildTab()
    return Number(Call(GetCurrentGuildBankTab))
end
function A.GuildTabCount()
    local count=Number(Call(GetNumGuildBankTabs))
    if count and count>=0 and count<= (Number(MAX_GUILDBANK_TABS) or 8) and count==math.floor(count) then return count end
end
function A.GuildTab(tab)
    if type(GetGuildBankTabInfo)~="function" then return nil end
    local ok,name,icon,view,deposit,limit,remaining=pcall(GetGuildBankTabInfo,tab)
    if not ok then return nil end
    return {id=tab,index=tab,name=String(name),icon=Number(icon) or String(icon),view=S.SafeBoolean(view)==true,
        deposit=S.SafeBoolean(deposit)==true,limit=Number(limit),remaining=Number(remaining)}
end
function A.GuildTabs()
    local result={}
    for tab=1,A.GuildTabCount() or 0 do
        local info=A.GuildTab(tab)
        if info then result[#result+1]=info end
    end
    return result
end
local function ViewableGuildTab(tab)
    tab=Number(tab)
    if not tab or tab<1 or tab~=math.floor(tab) or tab>(A.GuildTabCount() or 0) then return false end
    local info=A.GuildTab(tab)
    return info and info.view
end
function A.QueryGuildPage(tab)
    if A.InCombat() or not A.BankWindowShown("guild") or not ViewableGuildTab(tab)
        or type(QueryGuildBankTab)~="function" then return false end
    return pcall(QueryGuildBankTab,tab)
end
function A.SelectGuildTab(tab)
    if A.InCombat() or not A.BankWindowShown("guild") or not ViewableGuildTab(tab)
        or type(SetCurrentGuildBankTab)~="function" or type(QueryGuildBankTab)~="function" then return false end
    if A.CursorBusy() and not (YUI.IsForever and A.CursorItem()) then return false end
    if A.CurrentGuildTab()~=tab then pcall(SetCurrentGuildBankTab,tab) end
    if A.CurrentGuildTab()~=tab then return false end
    -- Selection is already real even if the subsequent request fails.
    local requested=pcall(QueryGuildBankTab,tab)
    return true,requested
end
local function GuildActionReady(tab)
    return not A.InCombat() and A.BankWindowShown("guild") and A.CurrentGuildTab()==tab
end
function A.GuildItemAction(tab,slot,take)
    if not GuildActionReady(tab) then return false end
    local callback=PickupGuildBankItem
    if take then callback=AutoStoreGuildBankItem end
    if type(callback)~="function" then return false end
    return pcall(callback,tab,slot)
end
function A.SplitGuildItem(tab,slot,count)
    if not GuildActionReady(tab) or type(SplitGuildBankItem)~="function" then return false end
    return pcall(SplitGuildBankItem,tab,slot,count)
end
function A.CanDeposit(item,kind)
    if not item then return false end
    if kind=="guild" then
        if item.bound==nil then return nil end
        return item.bound==false
    end
    if not (C_Bank and C_Bank.IsItemAllowedInBankType and ItemLocation and Enum and Enum.BankType) then return false end
    local bankType=kind=="shared" and Enum.BankType.Account or Enum.BankType.Character
    if not bankType then return false end
    local location=ItemLocation:CreateFromBagAndSlot(item.bag,item.slot)
    return S.SafeBoolean(Call(C_Bank.IsItemAllowedInBankType,bankType,location))==true
end
local function ContainerItemInfo(bag,slot)
    local ok,info=pcall(C_Container.GetContainerItemInfo,bag,slot)
    if not ok or S.IsSecretValue(info) then return nil,"restricted" end
    if info==nil then return nil end
    if not S.CanAccessTable(info) then return nil,"restricted" end
    return info
end
local chargePatterns
local function ChargePattern(format)
    local first,last=format:find("%%1%$d")
    if not first then first,last=format:find("%%d") end
    if not first then return nil end
    local prefix=format:sub(1,first-1):gsub("(%W)","%%%1")
    local suffix=format:sub(last+1):gsub("(%W)","%%%1")
    return "^"..prefix.."(%d+)"..suffix.."$"
end
function A.ReadSlotCharges(bag,slot)
    if not YUI.IsForever or not C_TooltipInfo then return nil end
    local data=Call(C_TooltipInfo.GetBagItem,bag,slot)
    if not S.CanAccessTable(data) or not S.CanAccessTable(data.lines) then return nil end
    if not chargePatterns then
        local format=String(ITEM_SPELL_CHARGES)
        if not format then return nil end
        chargePatterns={}
        local forms=format:match("|4([^;]+);")
        if forms then
            for form in forms:gmatch("[^:]+") do
                chargePatterns[#chargePatterns+1]=ChargePattern((format:gsub("|4[^;]+;",function() return form end)))
            end
        else chargePatterns[1]=ChargePattern(format) end
    end
    for _,line in ipairs(data.lines) do
        local text=S.CanAccessTable(line) and String(line.leftText)
        if text then
            if text==ITEM_SPELL_CHARGES_NONE then return 0 end
            for _,pattern in ipairs(chargePatterns) do
                local value=text:match(pattern)
                if value then return tonumber(value) end
            end
        end
    end
end
function A.SlotQuestState(bag,slot)
    local quest=Call(C_Container.GetContainerItemQuestInfo,bag,slot)
    if not S.CanAccessTable(quest) then return false end
    if Number(quest.questID) then
        local active=S.SafeBoolean(quest.isActive)
        if active==false then return true,"starter" end
        if active==true then return true,"item" end
        return true
    end
    if S.SafeBoolean(quest.isQuestItem)==true then return true,"item" end
    return false
end

function A.Slot(bag,slot)
    local info,err=ContainerItemInfo(bag,slot)
    if not info then return nil,err end
    local id,count=Number(info.itemID),Number(info.stackCount)
    if not id or not count or count<1 then return nil,"restricted" end
    local link=String(info.hyperlink) or String(Call(C_Container.GetContainerItemLink,bag,slot))
    local key=link or tostring(id)
    local detail=metadata[key]
    if not detail then
        local raw=YUI.API.Item.GetInfo(link or id)
        detail={itemID=id,name=String(info.itemName) or String(Call(YUI.API.Item.GetName,id)) or "",icon=Number(info.iconFileID),quality=Number(info.quality)}
        if type(raw)=="table" then
            detail.name=String(raw.name) or detail.name;detail.quality=Number(raw.quality) or detail.quality
            detail.classID=Number(raw.classID);detail.subClassID=Number(raw.subclassID)
            detail.subType=String(raw.subType);detail.equipLoc=String(raw.equipLoc)
            detail.level=Number(raw.level);detail.maxStack=Number(raw.stackCount) or 1;detail.price=Number(raw.sellPrice)
            detail.bindType=Number(raw.bindType)
            if YUI.IsRetail and detail.bindType==2 and C_Item
                and S.SafeBoolean(Call(C_Item.IsItemBindToAccountUntilEquip,link or id))==true then
                detail.bindType=Enum and Enum.ItemBind and Enum.ItemBind.ToBnetAccountUntilEquipped or 9
            end
            if detail.classID==2 or detail.classID==4 then detail.level=Number(Call(YUI.API.Item.GetLevel,link or id)) or detail.level end
            detail.loaded=detail.name~=""
            detail.isCraftingReagent=S.SafeBoolean(raw.isCraftingReagent)
        end
        if YUI.IsForever and camp[id] then detail.system="camp"
        elseif YUI.IsRetail and C_Item and S.SafeBoolean(Call(C_Item.IsDecorItem,link or id))==true then detail.system="housing" end
        if detail.loaded then metadata[key]=detail end
    end
    local result={}
    for field,value in pairs(detail) do result[field]=value end
    result.bag,result.slot,result.itemID,result.link,result.count=bag,slot,id,link,count
    result.key=tostring(bag)..":"..slot
    local limit=YUI.IsForever and chargeLimits[id]
    if limit then
        if not detail.chargeSpellID then
            local ok,_,spellID=pcall(YUI.API.Item.GetSpell,id)
            if ok then detail.chargeSpellID=Number(spellID) end
        end
        result.chargeSpellID=detail.chargeSpellID
        result.maxCharges=math.abs(limit)
        result.chargeConsumable=limit<0 or result.classID==0
        result.charges=A.ReadSlotCharges(bag,slot)
    end
    result.locked=S.SafeBoolean(info.isLocked)~=false
    result.bound=S.SafeBoolean(info.isBound)
    result.quest,result.questVisual=A.SlotQuestState(bag,slot)
    result.new=C_NewItems and S.SafeBoolean(Call(C_NewItems.IsNewItem,bag,slot))==true or false
    result.family=ItemFamily(id,link)
    if C_Item and type(C_Item.GetItemGUID)=="function" then
        result.guid=String(Call(C_Item.GetItemGUID,{bagID=bag,slotIndex=slot}))
    end
    return result
end
-- Use item IDs only to select candidates. Confirm the copy by its carried
-- location or its physical slot tooltip.
function A.EquipmentSetCandidates()
    local byItem={}
    if not YUI.IsForever or not C_EquipmentSet then return byItem end
    local ids=Call(C_EquipmentSet.GetEquipmentSetIDs)
    if not S.CanAccessTable(ids) then return byItem end
    local sorted=Call(SortEquipmentSetIDs,ids)
    if S.CanAccessTable(sorted) then ids=sorted end
    for order,rawID in ipairs(ids) do
        local id=Number(rawID)
        local name=id and String(Call(C_EquipmentSet.GetEquipmentSetInfo,id))
        local items=name and name~="" and Call(C_EquipmentSet.GetItemIDs,id)
        if S.CanAccessTable(items) then
            local set={id=id,name=name,order=order,items=items}
            for _,candidate in pairs(items) do
                local itemID=Number(candidate)
                if itemID and itemID>0 then
                    local list=byItem[itemID]
                    if not list then list={};byItem[itemID]=list end
                    if list[#list]~=set then list[#list+1]=set end
                end
            end
        end
    end
    return byItem
end
local function GearSetAtSlot(bag,slot,sets,locations,itemID)
    -- Packed locations use the client's bag flag and slot bit offset.
    local bagFlag=Number(ITEM_INVENTORY_LOCATION_BAGS)
    local playerFlag=Number(ITEM_INVENTORY_LOCATION_PLAYER)
    local offset=Number(ITEM_INVENTORY_BAG_BIT_OFFSET)
    if not (bagFlag and playerFlag and offset and C_EquipmentSet and C_EquipmentSet.GetItemLocations) then return end
    local slotsPerBag=2^offset
    if bag<0 or slot<1 or slot>=slotsPerBag then return end
    local packed=bagFlag+bag*slotsPerBag+slot
    local earlierUnavailable=false
    for _,set in ipairs(sets) do
        local byLocation=locations[set.id]
        if byLocation==nil then
            local saved=Call(C_EquipmentSet.GetItemLocations,set.id)
            byLocation=false
            if S.CanAccessTable(saved) then
                byLocation={}
                for equipSlot,location in pairs(saved) do
                    local key=Number(location)
                    local savedID=Number(set.items[equipSlot])
                    if key and savedID and savedID>0 then byLocation[key]=savedID end
                end
            end
            locations[set.id]=byLocation
        end
        if not byLocation then
            earlierUnavailable=true
        elseif byLocation[packed]==itemID or byLocation[packed+playerFlag]==itemID then
            return set,earlierUnavailable
        end
    end
end
local function TooltipFormat(value)
    if not value then return nil end
    local start,finish=value:find("%s",1,true)
    if not start then start,finish=value:find("%1$s",1,true) end
    if not start then return nil end
    local function Escape(text) return (text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])","%%%1")) end
    return "^"..Escape(value:sub(1,start-1)).."(.+)"..Escape(value:sub(finish+1)).."$"
end
local function SkipListSpace(text,at)
    local _,finish=text:find("^%s*",at)
    at=finish+1
    -- Ideographic space, narrow no-break space, and no-break space.
    local nextChar=text:sub(at,at+2)
    while nextChar=="\227\128\128" or nextChar=="\226\128\175" or nextChar:sub(1,2)=="\194\160" do
        local width=nextChar:sub(1,2)=="\194\160" and 2 or 3
        _,finish=text:find("^%s*",at+width)
        at=finish+1
        nextChar=text:sub(at,at+2)
    end
    return at
end
local function AfterListSeparator(text,at)
    at=SkipListSpace(text,at)
    if at>#text then return at end
    if text:sub(at,at)=="," then return SkipListSpace(text,at+1) end
    local char=text:sub(at,at+2)
    if char=="，" or char=="、" then return SkipListSpace(text,at+3) end
    local delimiter=String(LIST_DELIMITER)
    if delimiter and #delimiter>0 and text:sub(at,at+#delimiter-1)==delimiter then
        return SkipListSpace(text,at+#delimiter)
    end
end
local function GearSetFromList(text,sets)
    local at,best=SkipListSpace(text,1),nil
    while at<=#text do
        local match,nextAt
        for _,set in ipairs(sets) do
            local length=#set.name
            if (not match or length>#match.name) and text:sub(at,at+length-1)==set.name then
                local after=AfterListSeparator(text,at+length)
                if after then match,nextAt=set,after end
            end
        end
        if not match then return nil end
        if not best or match.order<best.order then best=match end
        at=nextAt
    end
    return best
end
local gearSetPattern,tradeTimePattern
function A.ReadGearState(bag,slot,sets,checkTrade,locations,itemID)
    if not (YUI.IsForever and (sets or checkTrade)) then return nil,nil,false end
    local locationSet,earlierUnavailable
    if sets and locations and itemID then locationSet,earlierUnavailable=GearSetAtSlot(bag,slot,sets,locations,itemID) end
    local checkSetTooltip=sets and (not locationSet or earlierUnavailable)
    if locationSet and not checkSetTooltip and not checkTrade then return nil,locationSet,true end
    if not C_TooltipInfo then return nil,locationSet,false end
    local payload=Call(C_TooltipInfo.GetBagItem,bag,slot)
    if not S.CanAccessTable(payload) or not S.CanAccessTable(payload.lines) or #payload.lines==0 then return nil,locationSet,false end
    gearSetPattern=gearSetPattern or TooltipFormat(String(EQUIPMENT_SETS))
    tradeTimePattern=tradeTimePattern or TooltipFormat(String(BIND_TRADE_TIME_REMAINING))
    local tradeType=Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.TradeTimeRemaining
    local matchedSet,trade=locationSet,nil
    for _,line in ipairs(payload.lines) do
        if S.CanAccessTable(line) then
            local text=String(line.leftText)
            if checkSetTooltip and gearSetPattern and text then
                local list=text:match(gearSetPattern)
                local set=list and GearSetFromList(list,sets)
                if set and (not matchedSet or set.order<matchedSet.order) then matchedSet=set end
            end
            if checkTrade and (tradeType and Number(line.type)==tradeType or text and tradeTimePattern and text:match(tradeTimePattern)) then
                trade=true
            end
        end
    end
    return trade,matchedSet,true
end
function A.CanWearEquipment(itemID,link)
    if not Number(itemID) or not (C_PlayerInfo and C_PlayerInfo.CanUseItem) then return false end
    local info=Call(YUI.API.Item.GetInfo,link or itemID)
    local required=S.CanAccessTable(info) and Number(info.minLevel)
    if not required then return nil end -- Retry when item data arrives.
    if required>0 then
        local level=Number(Call(UnitLevel,"player"))
        if not level or level<required then return false end
    end
    return S.SafeBoolean(Call(C_PlayerInfo.CanUseItem,itemID))==true
end
function A.EquippedLevel(slot)
    if C_Item and C_Item.GetCurrentItemLevel and ItemLocation and ItemLocation.CreateFromEquipmentSlot then
        local location=ItemLocation:CreateFromEquipmentSlot(slot)
        local current=Number(Call(C_Item.GetCurrentItemLevel,location))
        if current and current>0 then return current end
    end
    local link=String(Call(YUI.API.Item.GetInventoryItemLink,"player",slot))
    local level=link and Number(Call(YUI.API.Item.GetLevel,link))
    if level and level>0 then return level end
    return nil,Number(Call(YUI.API.Item.GetInventoryItemID,"player",slot))
end
local function BankBagSocket(bag,kind)
    if not YUI.IsForever or kind and kind~="bank" then return end
    local indices=Enum and Enum.BagIndex
    local first=indices and Number(indices.CharacterBankTab_1)
    local last=indices and Number(indices.CharacterBankTab_9)
    -- The first tab has built-in space. Later tabs use bags on the native socket container.
    if first and last and bag>first and bag<=last then
        return Number(indices.Characterbanktab),bag-first+1
    end
end
local function ReadBagDomain(bag,kind)
    local ok,_,rawFamily=pcall(C_Container.GetContainerNumFreeSlots,bag)
    if not ok or S.IsSecretValue(rawFamily) then return nil,"restricted" end
    local family=Number(rawFamily)
    if rawFamily~=nil and family==nil then return nil,"restricted" end
    local container,slot=BankBagSocket(bag,kind)
    if container then
        local info=ContainerItemInfo(container,slot)
        local itemID=info and Number(info.itemID)
        if not itemID or itemID<1 then return nil,"restricted" end
        local readable,id,_,_,_,_,class,subclass=pcall(YUI.API.Item.GetInfoInstant,itemID)
        class,subclass=Number(class),Number(subclass)
        if not readable or Number(id)~=itemID or class==nil or subclass==nil then
            return nil,"pending",itemID
        end
        if class==1 and subclass==11 then return family or 0,"reagent" end
        kind="bank"
    end
    if family==nil then return nil,"restricted" end
    return family,A.SpaceKey(bag,family,kind)
end
function A.ReadBag(bag,contentsOnly,kind)
    local capacity=Number(Call(C_Container.GetContainerNumSlots,bag))
    if not capacity or capacity<0 or capacity>512 then return nil,"restricted" end
    if YUI.IsForever and A.IsKeyring(bag) then
        -- The native keyring reveals rows of four instead of every physical slot.
        local visible=Number(Call(GetKeyRingSize))
        if visible and visible>=0 and visible<=capacity then capacity=visible end
    end
    if capacity==0 then return {},0,0 end
    local family,space,pending
    if not contentsOnly then
        family,space,pending=ReadBagDomain(bag,kind)
        if family==nil then return nil,space,pending end
    end
    local slots={}
    for slot=1,capacity do
        local item,err=A.Slot(bag,slot)
        if err then return nil,err end
        slots[slot]=item
    end
    return slots,capacity,family,space
end
function A.Fits(item,bag,checkLive)
    if not bag or not item then return false end
    local family,space=bag.family,bag.space
    if checkLive and bag.kind=="bank" and BankBagSocket(bag.id,bag.kind) then
        family,space=ReadBagDomain(bag.id,bag.kind)
        if family==nil then return false end
    end
    space=space or A.SpaceKey(bag.id,family,bag.kind)
    if space=="keyring" then return item.classID==13 end
    if space~="reagent" and family==0 then return true end
    if item.classID==1 or item.classID==11 or item.equipLoc=="INVTYPE_BAG" or item.equipLoc=="INVTYPE_QUIVER" then
        return false
    end
    if space=="reagent" then return item.isCraftingReagent==true end
    local band=bit and bit.band or bit32 and bit32.band
    return family and band and band(item.family or 0,family)>0 or false
end
function A.InitializeButton(button,container,bag,slot)
    if A.InCombat() then return false end
    if YUI.IsForever and A.IsKeyring(bag) then
        button.containerFrame=container
        button:SetBagID(bag);button:SetID(slot);button:SetIsExtended(false)
        if button.extendedFrame then button.extendedFrame:Hide() end
        button:Show()
    elseif YUI.IsForever then button:Initialize(container,bag,slot)
    else button:Initialize(bag,slot) end
    return true
end
function A.HasNativeSlotLock(button)
    return button.IsExtended and S.SafeBoolean(button:IsExtended())==true
end
function A.RecheckNativeSlotLock(button,bag,slot)
    if A.InCombat() or not button.UpdateExtended or Number(Call(button.GetBagID,button))~=bag
        or Number(Call(button.GetID,button))~=slot then return false end
    local locked=S.SafeBoolean(Call(button.IsExtended,button))
    if locked~=true then return locked==false end
    local ok=pcall(button.UpdateExtended,button)
    return ok and S.SafeBoolean(Call(button.IsExtended,button))==false
end
function A.RegisterItemTooltip(callback)
    local processor=TooltipDataProcessor
    local itemType=Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    if not processor or type(processor.AddTooltipPostCall)~="function" or itemType==nil then return false end
    processor.AddTooltipPostCall(itemType,callback)
    return true
end
function A.UpdateCooldown(button,item)
    if button.UpdateCooldown and not item.empty and not item.held then button:UpdateCooldown(true)
    elseif button.Cooldown then button.Cooldown:Hide() end
end
function A.UpdateButtonState(button,item)
    if button.BagIndicator then button.BagIndicator:Hide() end
    if button.UpgradeIcon then button.UpgradeIcon:Hide() end
    if button.IconQuestTexture then button.IconQuestTexture:Hide() end
    if button.UpdateNewItem then button:UpdateNewItem(item.quality) end
    if item.empty or item.held or not item.new then
        if button.BattlepayItemTexture then button.BattlepayItemTexture:Hide() end
        if button.NewItemTexture then button.NewItemTexture:Hide() end
        if button.flash then button.flash:Hide() end
        if button.flashAnim then button.flashAnim:Stop() end
        if button.newitemglowAnim then button.newitemglowAnim:Stop() end
    end
    if button.SyncAppearanceWithHasItem then button:SyncAppearanceWithHasItem() end
    if not YUI.IsForever and button.UpdateJunkItem and MerchantFrame then button:UpdateJunkItem(item.quality,item.price==0)
    elseif button.JunkIcon then button.JunkIcon:Hide() end
    A.UpdateCooldown(button,item)
    if button.UpdateItemContextMatching then button:UpdateItemContextMatching() end
end
function A.Pickup(bag,slot) return pcall(C_Container.PickupContainerItem,bag,slot) end
function A.Split(bag,slot,count) return pcall(C_Container.SplitContainerItem,bag,slot,count) end
function A.ActiveBankKind()
    if not Visible(BankFrame) or not BankFrame.GetActiveBankType or not (Enum and Enum.BankType) then return nil end
    local bankType=Number(Call(BankFrame.GetActiveBankType,BankFrame))
    if bankType==nil then return nil end
    if bankType==Enum.BankType.Character then return "bank" end
    if bankType==Enum.BankType.Account then return "shared" end
end
function A.PlaceCursor(context)
    if A.InCombat() or not A.CursorBusy() or A.Context()~=context then return false end
    local callback,slot
    if context=="merchant" then callback=SellCursorItem
    elseif context=="trade" or context=="mail" then
        local read=context=="trade" and GetTradePlayerItemInfo or GetSendMailItem
        callback=context=="trade" and ClickTradeButton or ClickSendMailItemButton
        if type(read)~="function" then return false end
        local limit=context=="trade" and 6 or Number(ATTACHMENTS_MAX_SEND) or 12
        for n=1,limit do
            local ok,name,texture=pcall(read,n)
            if not ok or S.IsSecretValue(name) or S.IsSecretValue(texture) then return false end
            if name==nil and texture==nil then slot=n;break end
        end
        if not slot then return false end
    end
    if type(callback)~="function" then return false end
    local ok=pcall(callback,slot)
    return ok and not A.CursorBusy()
end
function A.IsNonEquippable(item)
    if not item.loaded then return false end
    local location=item.equipLoc
    return location=="" or location=="INVTYPE_NON_EQUIP" or location=="INVTYPE_NON_EQUIP_IGNORE"
end
function A.Delete(bag,slot)
    if A.InCombat() or A.CursorBusy() or A.Context()~="travel" then return false end
    local item=A.Slot(bag,slot)
    if not item or item.quality~=0 or item.quest or item.locked or not A.IsNonEquippable(item) then return false end
    C_Container.PickupContainerItem(bag,slot)
    if not CursorHasItem() then return false end
    DeleteCursorItem()
    if CursorHasItem() then C_Container.PickupContainerItem(bag,slot);return false end
    return true
end
function A.EquipBag(sourceBag,sourceSlot,targetBag)
    if A.InCombat() or A.CursorBusy() then return false end
    local inventoryID=Call(C_Container.ContainerIDToInventoryID,targetBag)
    if not Number(inventoryID) then return false end
    C_Container.PickupContainerItem(sourceBag,sourceSlot)
    if not CursorHasItem() then return false end
    PutItemInBag(inventoryID)
    if CursorHasItem() then C_Container.PickupContainerItem(sourceBag,sourceSlot) end
    return not CursorHasItem()
end
function A.Conflict()
    for _,name in ipairs({"Baganator","Bagnon","EllesmereUIBags"}) do
        if YUI.API.System.IsAddOnLoaded(name) then return name end
    end
end
function A.InvalidateItem(id)
    for key,value in pairs(metadata) do if value.itemID==id then metadata[key]=nil end end
end
function A.Reset() metadata={} end
