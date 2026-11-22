local YUI = _G.YUI
local B = YUI and YUI.YBags
if not B then return end

local C = {}
B.Classification = C
C.sections = { "recent", "general", "consumable", "equipment", "material", "system", "other", "junk" }
C.tradeGroup = "limited_trade"
local onEquip = Enum and Enum.ItemBind and Enum.ItemBind.OnEquip or 2
-- wowf 1.60.1.70938，核验方式见 Docs/Products/YBags/forever-common-items.md。
local classSpellReagents = {
    [5140]=true, [5530]=true, -- 潜行者：消失、致盲
    [5565]=true, [6265]=true, [16583]=true, -- 术士：召唤、造石、仪式
    [17020]=true, [17031]=true, [17032]=true, -- 法师：团队增益、传送、传送门
    [17056]=true, -- 法师缓落术、牧师漂浮术共用轻羽毛
    [17021]=true, [17026]=true, -- 德鲁伊：野性赐福
    [17034]=true, [17035]=true, [17036]=true, [17037]=true, [17038]=true, -- 德鲁伊：复生
    [17028]=true, [17029]=true, -- 牧师：祷言
    [17030]=true, [17057]=true, [17058]=true, -- 萨满祭司：复生、水下呼吸、水上行走
    [17033]=true, [21177]=true, -- 圣骑士：神圣干涉、强效祝福
}
local hearthstoneID = 6948
local cozySleepingBagID = 211527
local commonItems = {
    -- 法师造水
    [2136]=true, [2288]=true, [3772]=true, [5350]=true, [8077]=true, [8078]=true, [8079]=true, [231778]=true,
    -- 法师造食
    [1113]=true, [1114]=true, [1487]=true, [5349]=true, [8075]=true, [8076]=true, [22895]=true,
    -- 法力宝石
    [5513]=true, [5514]=true, [8007]=true, [8008]=true,
    -- 治疗石（含强化变体）
    [5509]=true, [5510]=true, [5511]=true, [5512]=true, [9421]=true, [19004]=true, [19005]=true,
    [19006]=true, [19007]=true, [19008]=true, [19009]=true, [19010]=true, [19011]=true, [19012]=true, [19013]=true,
    -- 灵魂石
    [5232]=true, [16892]=true, [16893]=true, [16895]=true, [16896]=true,
    -- 火焰石
    [1254]=true, [13699]=true, [13700]=true, [13701]=true,
    -- 法术石
    [5522]=true, [13602]=true, [13603]=true,
}

function C:IsClassSpellReagent(itemID)
    return classSpellReagents[itemID] == true
end

-- 无限服已理解与未理解的法师卷轴，背包分类和银行快捷存取共用。
local mageScrolls = {}
for _, id in ipairs({
    211780,211784,211785,211786,211787,211853,211854,211855,
    213543,213544,213545,213546,213547,281015,281016,281017,281018,
    211800,211953,211954,211955,211956,211957,213548,213549,213550,213551,
    213564,216879,217495,217496,223171,274947,275067,275069,
    277483,277484,277485,277486,277487,277488,277489,277490,277491,277492,277493,
    277494,277495,277496,277497,277498,277499,277500,277501,277502,277503,277504,
}) do mageScrolls[id] = true end
function C.IsMageScroll(item)
    return mageScrolls[item.itemID] == true
end

-- wowf 70959 ItemSparse：遭劫的空箱、各类待填装箱、交付用的密封箱。
local supplyCrates = {[248549]=true}
for id=248682,248699 do supplyCrates[id]=true end
for id=248702,248713 do supplyCrates[id]=true end
for id=248765,248779 do supplyCrates[id]=true end

local function HasEquipSlot(slot)
    return slot ~= nil and slot ~= "" and slot ~= "INVTYPE_NON_EQUIP" and slot ~= "INVTYPE_NON_EQUIP_IGNORE"
end
function C:IsUnboundEquipment(item)
    return (item.classID == 2 or item.classID == 4) and item.bindType == onEquip and item.bound == false
        and not item.gearTrade and HasEquipSlot(item.equipLoc)
end

local setGroupPrefix = "equipment-set:"
function C:SetGroupName(group)
    if group and group:sub(1,#setGroupPrefix)==setGroupPrefix then return group:sub(#setGroupPrefix+1) end
end
function C:IsFixedGearGroup(group)
    return group==self.tradeGroup or self:SetGroupName(group)~=nil
end
local equipmentOrder = { INVTYPE_WEAPON=1, INVTYPE_2HWEAPON=1, INVTYPE_WEAPONMAINHAND=1,
    INVTYPE_WEAPONOFFHAND=2, INVTYPE_SHIELD=2, INVTYPE_HOLDABLE=2, INVTYPE_HEAD=3, INVTYPE_NECK=4,
    INVTYPE_SHOULDER=5, INVTYPE_CLOAK=6, INVTYPE_CHEST=7, INVTYPE_ROBE=7, INVTYPE_WRIST=8,
    INVTYPE_HAND=9, INVTYPE_WAIST=10, INVTYPE_LEGS=11, INVTYPE_FEET=12, INVTYPE_FINGER=13,
    INVTYPE_TRINKET=14, INVTYPE_RANGED=15, INVTYPE_RANGEDRIGHT=15, INVTYPE_THROWN=15,
    INVTYPE_RELIC=15, INVTYPE_BODY=16, INVTYPE_TABARD=17 }
local validSections = {}
for _, id in ipairs(C.sections) do validSections[id] = true end

function C:Compile(rules)
    local result = {}
    for _, rule in ipairs(type(rules) == "table" and rules or {}) do
        if type(rule) == "table" and rule.enabled ~= false and type(rule.id) == "string" and validSections[rule.section] then
            result[#result + 1] = rule
        end
    end
    table.sort(result, function(a,b)
        local ap, bp = tonumber(a.priority) or 0, tonumber(b.priority) or 0
        if ap ~= bp then return ap > bp end
        return a.id < b.id
    end)
    return result
end
function C:RuleMatches(rule, item)
    if type(rule.exclude) == "string" and rule.exclude ~= "" and item.name:find(rule.exclude, 1, true) then return false end
    local checks, matches = 0, 0
    local function Check(value) checks = checks + 1; if value then matches = matches + 1 end end
    if rule.classID ~= nil then Check(item.classID == tonumber(rule.classID)) end
    if rule.quality ~= nil then Check(item.quality == tonumber(rule.quality)) end
    if rule.equipLoc and rule.equipLoc ~= "" then Check(item.equipLoc == rule.equipLoc) end
    if rule.minLevel and rule.minLevel > 0 then Check((item.level or 0) >= rule.minLevel) end
    if rule.contains and rule.contains ~= "" then Check(item.name:find(rule.contains, 1, true) ~= nil) end
    return checks > 0 and (rule.any == true and matches > 0 or matches == checks)
end
function C:Classify(item, config, compiled, ignoreRecent)
    if item.gearTrade then return "equipment", self.tradeGroup, -2 end
    if item.gearSet then return "equipment", setGroupPrefix..item.gearSet.name, -1 end
    if item.quality == 0 then return "junk", "", 0 end
    if item.new and not ignoreRecent then return "recent", "", 0 end
    local itemKey = tostring(item.itemID)
    local manual = config.manual[itemKey]
    for _, rule in ipairs(compiled or {}) do
        if manual == rule.id or (not manual and self:RuleMatches(rule, item)) then
            return rule.section, rule.name or rule.id, tonumber(rule.order) or 0
        end
    end
    if config.favorites[itemKey] or YUI.IsForever and (item.itemID == hearthstoneID or commonItems[item.itemID] or self:IsClassSpellReagent(item.itemID)) then
        return "general", "favorites", 0
    end
    if YUI.IsForever and item.itemID == cozySleepingBagID then return "system", "camp", -2 end
    if item.system then return "system", item.system, 0 end
    local class = item.classID
    if YUI.IsForever and supplyCrates[item.itemID] then return "other", "supply_crates", -2 end
    if item.quest or class == 12 then
        if YUI.IsForever then return "other", "quest", -3 end
        return "general", "quest", 1
    end
    if YUI.IsForever and (C.IsMageScroll(item) or class == 0 and item.subClassID == 4) then
        return "consumable", "scrolls", 4
    end
    if class == 2 or class == 4 then
        if YUI.IsForever and self:IsUnboundEquipment(item) then return "equipment", "boe", math.huge end
        return "equipment", item.equipLoc or "equipment", equipmentOrder[item.equipLoc] or 99
    elseif class == 0 or class == 3 or class == 8 then
        return "consumable", item.subType or "consumable", item.subClassID or 99
    elseif class == 5 or class == 7 or class == 9 or class == 19 then
        return "material", item.subType or "material", item.subClassID or 99
    elseif class == 15 and (item.subClassID == 2 or item.subClassID == 5) then return "general", "collection", 2 end
    return "other", "", 0
end
function C:Matches(item, query)
    if not query or query == "" then return true end
    local haystack = string.lower((item.name or "") .. " " .. (item.subType or "") .. " " .. tostring(item.itemID or ""))
    for token in string.gmatch(string.lower(query), "%S+") do
        local operator, level = token:match("^([<>]=?)(%d+)$")
        if operator then
            local n, value = tonumber(level), item.level or 0
            if operator == ">" and value <= n or operator == ">=" and value < n or operator == "<" and value >= n or operator == "<=" and value > n then return false end
        elseif token == "new" or token == B:T("search.new") then
            if not item.new then return false end
        elseif not haystack:find(token, 1, true) then return false end
    end
    return true
end
-- 这些物品每件独占一格，只允许随身分类背包合并显示。
local singleSlotDisplayItems = {
    [6265]="ignoreBinding", -- 灵魂碎片
    [5523]=true, [5524]=true, [7973]=true, -- 小蚌壳、厚蚌壳、巨型蚌壳
    [18232]=true, -- 修理机器人74A型
}
local function GroupKey(item, allowSingleSlotItems)
    if item.empty or item.held or not item.itemID or item.classID==2 or item.classID==4 then return nil end
    if item.maxCharges and item.charges==nil then return nil end
    local ignoreBinding
    if (item.maxStack or 1)<=1 then
        local listed=allowSingleSlotItems and item.link and item.link~="" and singleSlotDisplayItems[item.itemID]
        local charged=YUI.IsForever and item.charges~=nil and (item.classID==0 or item.chargeConsumable)
        if item.maxStack~=1 or not (listed or charged) or HasEquipSlot(item.equipLoc) then return nil end
        ignoreBinding=listed=="ignoreBinding"
    end
    local binding=ignoreBinding and "" or tostring(item.bound==true)
    return tostring(item.itemID).."\031"..tostring(item.link or "").."\031"..binding.."\031"..tostring(item.quality)
        .."\031"..tostring(item.maxStack).."\031"..tostring(item.charges or ""),ignoreBinding
end
function C:StackKey(item)
    return (GroupKey(item))
end
function C:DisplayGroupKey(item)
    return GroupKey(item,YUI.IsForever)
end
function C:SameStack(a,b,ignoreDisplayBinding)
    return a and b and a.itemID==b.itemID and a.link==b.link and (ignoreDisplayBinding or (a.bound==true)==(b.bound==true))
        and a.quality==b.quality and a.maxStack==b.maxStack and a.charges==b.charges and a.classID==b.classID
end
function C:QuickAccessOrder(itemID)
    if itemID == hearthstoneID then return 1 end
    return classSpellReagents[itemID] and 3 or 2
end
function C:Compare(a,b)
    if a.section == "junk" and b.section == "junk" then
        local av, bv = (a.price or math.huge) * (a.displayCount or a.count), (b.price or math.huge) * (b.displayCount or b.count)
        if av ~= bv then return av < bv end
    end
    if a.groupOrder ~= b.groupOrder then return a.groupOrder < b.groupOrder end
    if a.groupOrder == -1 then
        local ao,bo=a.gearSet and a.gearSet.order or 0,b.gearSet and b.gearSet.order or 0
        if ao~=bo then return ao<bo end
    end
    if a.group ~= b.group then return a.group < b.group end
    if a.itemID and b.itemID then
        if a.itemID~=b.itemID then
            if YUI.IsForever and a.section=="general" and b.section=="general" and a.group=="favorites" then
                local ao,bo=self:QuickAccessOrder(a.itemID),self:QuickAccessOrder(b.itemID)
                if ao~=bo then return ao<bo end
            end
            return a.itemID<b.itemID
        end
        if a.charges~=b.charges then
            if a.charges==nil or b.charges==nil then return b.charges==nil end
            if a.charges==0 or b.charges==0 then return b.charges==0 end
            return a.charges<b.charges
        end
        if a.link~=b.link then return tostring(a.link)<tostring(b.link) end
        if (a.bound==true)~=(b.bound==true) then return a.bound~=true end
        if a.quality~=b.quality then return (a.quality or -1)<(b.quality or -1) end
        if a.count~=b.count then return a.count<b.count end
    end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end
