-- 掉落的「常驻」部分（11-12 重构第 3 期：从 PageLoot.lua 拆出来留在主插件里，掉落页本身和整张掉落表在按需加载的 GearInsight_Forever_Plan）
--   1. 物品鼠标提示：加一行「掉落：副本 · 首领」和心愿单标记；第一行是英文名时换成中文
--      —— 只查常驻索引 ns.LootIdx（LootIndexData.lua：物品 → 副本 / 首领 / 中文名），不加载子插件
--   2. 心愿单提醒：进副本 / 开打首领 / 拾取窗口。拾取只看物品编号，不要数据；
--      进副本、开打首领要列出装备名 → 心愿单非空、而且副本名 / 首领名在索引里对得上时才加载子插件，交给 PageLoot.lua 里的原逻辑
--   3. 鼠标指向野外稀有怪（Pack.lua 调 ns.RareLines）：先查常驻的稀有怪编号表，是稀有怪才加载子插件出「刷新 + 掉落」两行
-- 合并打包时（没有子插件文件夹）行为相同：ns.PlanLoad 直接返回 true。
local _, ns = ...

local X = ns.LootIdx or { d = {}, it = {}, rare = {}, zh = {} }

local function wish() ns.db.wish = ns.db.wish or {}; return ns.db.wish end
local function isWished(id) return wish()[id] and true or false end

-- 物品 → 副本名、首领名（各 { 中文, 英文 }）；不在掉落表里 → nil
local RARES = { "野外稀有", "World Rares" }
local function where(id)
    local c = id and X.it[id]
    if not c then return nil end
    if c < 0 then
        local s = X.rare[-c]
        if type(s) ~= "string" then return nil end
        local zh, en = s:match("^([^\t]*)\t?(.*)$")
        return RARES, { zh, en ~= "" and en or nil }
    end
    local d = X.d[math.floor(c / 1000)]
    local b = d and d[3][c % 1000]
    if not b then return nil end
    return d, b
end
ns.LootWhere = where   -- 测试用
local function nm(x) return ns.L(x[1], x[2]) end

-- ---------- 提醒 ----------
local function notice(msg)
    ns.Print(msg)
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
        RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
end
ns.LootNotice = notice   -- PageLoot.lua 的进副本 / 首领提醒也用它

local function sameName(a, x)
    if not a or a == "" then return false end
    return a == x[1] or a:lower() == (x[2] or ""):lower()
end
local function hasWish() return ns.db and ns.db.wish and next(ns.db.wish) ~= nil end

-- 进副本：副本名在索引里 + 心愿单非空 → 加载子插件，按整张掉落表列「本副本能掉」
local function onEnterInstance()
    if not IsInInstance or not IsInInstance() then return end
    if not hasWish() then return end
    local name = GetInstanceInfo and GetInstanceInfo()
    for _, d in ipairs(X.d) do
        if sameName(name, d) then
            if ns.PlanLoad and ns.PlanLoad() and ns.LootWishEnter then ns.LootWishEnter() end
            return
        end
    end
end

-- 开打首领：首领名在索引里 + 心愿单非空 → 同上
local function onEncounter(encName)
    if not hasWish() then return end
    for _, d in ipairs(X.d) do
        for _, b in ipairs(d[3]) do
            if sameName(encName, b) then
                if ns.PlanLoad and ns.PlanLoad() and ns.LootWishEncounter then ns.LootWishEncounter(encName) end
                return
            end
        end
    end
end

local function onLoot()
    if not GetNumLootItems then return end
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id and isWished(id) then notice(ns.L("心愿单装备掉了：", "Wishlist item dropped: ") .. link) end
    end
end

-- ---------- 物品鼠标提示 ----------
local function addItemLine(tt, id)
    if not id or tt.__gifItem == id then return end
    local d, b = where(id)
    if not d then return end
    tt.__gifItem = id
    tt:AddLine("|cff33ff99GI|r " .. ns.L("掉落：", "Drops: ") .. nm(d) .. " · " .. nm(b), 1, 0.82, 0.4)
    if isWished(id) then tt:AddLine("|cff33ff99GI|r " .. ns.L("在你的心愿单里", "On your wishlist"), 1, 0.82, 0) end
    tt:Show()
end
ns._LootAddItemLine = addItemLine   -- 测试用

local function zhName(id) return id and X.zh and X.zh[id] or nil end

local function hookItems()
    if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
            local id = data and data.id
            if ns.Secret(id) or not id then return end
            if ns.TranslateTip then pcall(ns.TranslateTip, tt, zhName(id)) end
            pcall(addItemLine, tt, id)
        end)
    end
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt then
            tt:HookScript("OnTooltipCleared", function(self) self.__gifItem = nil end)
            if tt:HasScript("OnTooltipSetItem") then
                tt:HookScript("OnTooltipSetItem", function(self)
                    local _, link = self:GetItem()
                    if ns.Secret(link) then return end
                    local id = link and tonumber(link:match("item:(%d+)"))
                    if ns.TranslateTip and not (TooltipDataProcessor and Enum and Enum.TooltipDataType) then
                        pcall(ns.TranslateTip, self, zhName(id))
                    end
                    addItemLine(self, id)
                end)
            end
        end
    end
end

table.insert(ns.modules, function()
    pcall(hookItems)
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:RegisterEvent("ENCOUNTER_START")
    f:RegisterEvent("LOOT_OPENED")
    local function onEvent(_, e, a, b)
        if e == "ENCOUNTER_START" then pcall(onEncounter, b)
        elseif e == "LOOT_OPENED" then pcall(onLoot)
        else C_Timer.After(2, function() pcall(onEnterInstance) end) end
    end
    f:SetScript("OnEvent", onEvent)
    ns._wishEvent = onEvent
end)

-- ---------- 鼠标指向野外稀有怪 ----------
-- 真函数在 PageLoot.lua（ns.RareLinesFull）：要刷新点 / 掉率 / 物品品质，都在按需加载的数据里。
-- 这里先用常驻的稀有怪编号表挡掉绝大多数单位（不是稀有怪 = 直接 nil，不加载）
function ns.RareLines(npcId)
    if not npcId or not X.rare[npcId] then return nil end
    if not (ns.PlanLoad and ns.PlanLoad()) then return nil end
    return ns.RareLinesFull and ns.RareLinesFull(npcId) or nil
end
