-- 10-20 共建 GI-22「专业：补全图纸出处（哪个商人出售）」—— 游戏内实测图纸出处
-- 《无限》新增图纸有 700 来个 foreverchanges / 经典库都查不到出处，只能靠玩家在游戏里看见：
--   · 打开商人窗口：商人卖的每张图纸（ProfRecipes 第 18 格认得的）记下 商人 ID / 名字 / 地图坐标 / 是否限量
--   · 拾取（副本内外都算）：掉出来的图纸记下 怪 ID / 名字 / 地图坐标
-- 本机马上能看（配方库鼠标提示「你在游戏里见过」）；记录随掉落导出串（GIFD1 的 rs 字段）由更新器上传，
-- 网站汇总后进下一版配方出处（bis_wow/tools/forever_recipe_sources.py 读 /api/wow/forever/recipe-seen）。
-- 不记角色名 / 服务器名；只存 300 条，按 (图纸, 类别, NPC) 去重。
local _, ns = ...

local MAX_SEEN = 300

-- 是不是图纸（配方库第 18 格认得的物品）。11-13 重构第 4 期：配方库 ProfRecipes.lua 搬进按需加载的 GearInsight_Forever_Prof，
--   这里改查主插件常驻的图纸物品 ID 集合（ProfCoreData.lua 的 recipeItems，同一份配方库抽出来的）→ 不用为了认图纸加载整个配方库。
--   只回答「是不是」（true / nil）；调用方（这里两处、ObsVendor.lua）原来也只当真假用
local function recipeOfItem(id)
    local C = ns.ProfCore
    if not id or not (C and C.recipeItems) then return nil end
    return C.recipeItems[id] or nil
end
ns.ProfRecipeOfItem = recipeOfItem

local function npcId(guid)
    if not guid or ns.Secret(guid) then return 0, nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    return tonumber(id) or 0, kind
end

local function where()
    local m = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not m then return 0, 0, 0 end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
    if not ok or not pos then return m, 0, 0 end
    local x, y = pos:GetXY()
    return m, math.floor((x or 0) * 1000 + 0.5) / 10, math.floor((y or 0) * 1000 + 0.5) / 10
end

local function store(rec)
    local db = ns.db
    db.recipeSeen = db.recipeSeen or {}
    local key = rec.it .. ":" .. rec.k .. ":" .. rec.npc
    local old = db.recipeSeen[key]
    if old then
        old.t, old.c = rec.t, (old.c or 1) + (rec.k == "d" and 1 or 0)
        if rec.x > 0 then old.m, old.x, old.y = rec.m, rec.x, rec.y end
        return false
    end
    local n, oldestK, oldestT = 0, nil, math.huge
    for k, v in pairs(db.recipeSeen) do
        n = n + 1
        if (v.t or 0) < oldestT then oldestK, oldestT = k, v.t or 0 end
    end
    if n >= MAX_SEEN and oldestK then db.recipeSeen[oldestK] = nil end
    rec.c = 1
    db.recipeSeen[key] = rec
    return true
end

-- 商人窗口：GetMerchantItemInfo 第 5 个返回值 = 剩余数量（-1 = 不限量）
function ns.ProfSeenMerchant(now)
    if not GetMerchantNumItems or not ns.ProfCore then return 0 end
    local guid = UnitGUID and UnitGUID("npc")
    local id, kind = npcId(guid)
    if id == 0 or (kind ~= "Creature" and kind ~= "Vehicle") then return 0 end
    local name = UnitName and UnitName("npc")
    if name and ns.Secret(name) then name = nil end
    local m, x, y = where()
    local added = 0
    for i = 1, GetMerchantNumItems() do
        local it = GetMerchantItemID and GetMerchantItemID(i)
        if it and not ns.Secret(it) and recipeOfItem(it) then
            local ok, _, _, _, _, avail = pcall(GetMerchantItemInfo, i)
            if store({ k = "v", it = it, npc = id, n = name, m = m, x = x, y = y, lim = (ok and avail and avail >= 0) and 1 or nil, t = now or time() }) then
                added = added + 1
            end
        end
    end
    return added
end

-- 拾取窗口：图纸来源 = 拾取格的来源 GUID（怪 / 箱子）
function ns.ProfSeenLoot(now)
    if not GetNumLootItems or not ns.ProfCore then return 0 end
    local m, x, y = where()
    local added = 0
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local it = link and not ns.Secret(link) and tonumber(link:match("item:(%d+)"))
        if it and recipeOfItem(it) then
            local guid = GetLootSourceInfo and GetLootSourceInfo(slot)
            local id, kind = npcId(guid)
            local name
            for _, u in ipairs({ "target", "mouseover" }) do
                if guid and UnitGUID(u) == guid then name = UnitName(u) end
            end
            if name and ns.Secret(name) then name = nil end
            if store({ k = kind == "GameObject" and "o" or "d", it = it, npc = id, n = name, m = m, x = x, y = y, t = now or time() }) then
                added = added + 1
            end
        end
    end
    return added
end

-- 配方库鼠标提示：这张配方你在游戏里见过的出处
function ns.ProfSeenFor(r)
    local out = {}
    local S = ns.db and ns.db.recipeSeen
    if not S or type(r[18]) ~= "table" then return out end
    local mine = {}
    for _, it in ipairs(r[18]) do mine[it] = true end
    for _, v in pairs(S) do
        if mine[v.it] then out[#out + 1] = v end
    end
    table.sort(out, function(a, b) return (a.t or 0) > (b.t or 0) end)
    return out
end

function ns.ProfSeenLine(v)
    local zone = ""
    if v.m and v.m > 0 and C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, v.m)
        if ok and info and info.name then zone = info.name end
    end
    local xy = (v.x or 0) > 0 and string.format(" %.0f, %.0f", v.x, v.y) or ""
    local who = v.n or ("#" .. tostring(v.npc))
    if v.k == "v" then
        return ns.L("你见过：商人 ", "You saw: vendor ") .. who .. ns.L(" · ", " - ") .. zone .. xy .. (v.lim and ns.L(" · 限量", " - limited") or "")
    end
    return ns.L("你见过：", "You saw: ") .. (v.k == "o" and ns.L("箱子 ", "container ") or ns.L("掉落 ", "drop from ")) .. who
        .. ns.L(" · ", " - ") .. zone .. xy .. ((v.c or 1) > 1 and string.format(ns.L("（%d 次）", " (%d times)"), v.c) or "")
end

-- 随掉落导出串上传：只带 ID / 坐标 / 名字（名字是游戏客户端当前语言）
function ns.ProfSeenExport()
    local S = ns.db and ns.db.recipeSeen
    if not S then return nil end
    local out = {}
    for _, v in pairs(S) do
        out[#out + 1] = { k = v.k, it = v.it, npc = v.npc, n = v.n, m = v.m, x = v.x, y = v.y, lim = v.lim, c = v.c, t = v.t }
    end
    if #out == 0 then return nil end
    table.sort(out, function(a, b) return (a.t or 0) < (b.t or 0) end)
    return out
end

table.insert(ns.modules, function()
    local f = CreateFrame("Frame")
    f:RegisterEvent("MERCHANT_SHOW")
    f:RegisterEvent("LOOT_OPENED")
    ns._profSeenEvent = function(_, e)
        if e == "MERCHANT_SHOW" then pcall(ns.ProfSeenMerchant)
        elseif e == "LOOT_OPENED" then pcall(ns.ProfSeenLoot) end
    end
    f:SetScript("OnEvent", ns._profSeenEvent)
end)
