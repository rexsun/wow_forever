-- 练级 BUFF 补全器 · 物资 + 「从哪来」（11-17 用户「这个练级buff补全器，可以从主城就开始准备，路上碰到还可以刷新」
--   「buff和来源要可视化对应」「物资等」）。按需加载（GearInsight_Forever_Xp）：开经验加成页 / 进主城弹出发前清单时才加载。
--   ① 物资：吃 / 喝（按等级推荐商人档位）、弹药（猎人：箭 / 子弹 + 箭袋）、施法材料（按已学会的技能）、绷带 / 治疗药水 / 法力药水、修理、背包空格
--      规则：够用 = ok（写数量）；快不够 = warn（阈值见 SUP）；没有 = miss（红）；绷带 / 药水是可选的、要花钱 → 没有 = info（灰，同药剂 kit）
--   ② 职业 BUFF（cbuff）：缺的（要 BUFF 模块 BuffAsk.Missing）+ 附近见过的能给的人（BuffAsk.Nearby）→ 点了走 BuffAsk 原来的弹框（点「密他要」才发）
--   ③ 每一行的来源（XC.Sources）：{ icon, tc（职业圆图标裁切）, text, ok（现在用得上 = 亮，用不上 = 灰）, fn（点了做什么）, tip }，能用的排前面
--   数据：物品名 / 等级 / 商人价 = 《无限》客户端 DB2 ItemSparse（wago 1.60.1.70938）；施法材料按经典规则对技能（只在学会了那个技能时才查）
--   ⛔ 不重复造轮子：帐篷 = Camp.lua（CP.Offer 弹请求进队框）、法师水 = MageAskMenu.lua（MA.Ask）、要 BUFF = BuffAsk.lua、卖垃圾 / 清背包 = _Bag 子插件
local _, ns = ...; ns = _G.GearInsightForever or ns
local L = function(cn, en) return ns.L(cn, en) end
local XC = ns.XpCheck
if not XC then return end

-- ---------- 数据 ----------
-- 商人档位：{ 物品, 要求等级, 商人价（铜）, 一份几个 }
local FOOD = { { 4540, 1, 25, 5 }, { 4541, 5, 125, 5 }, { 4542, 15, 500, 5 }, { 4544, 25, 1000, 5 }, { 4601, 35, 2000, 5 }, { 8950, 45, 4000, 5 } }
local WATER = { { 159, 1, 25, 5 }, { 1179, 5, 125, 5 }, { 1205, 15, 500, 5 }, { 1708, 25, 1000, 5 }, { 1645, 35, 2000, 5 }, { 8766, 45, 4000, 5 } }
local CONJ_WATER = { 5350, 2288, 2136, 3772, 8077, 8078, 8079 }   -- 法师造的水（也算喝的）
local CONJ_FOOD = { 5349, 1113, 1114, 1487, 8075, 8076, 22895 }
local ARROW = { { 2512, 1, 10, 200 }, { 2515, 10, 50, 200 }, { 3030, 25, 300, 200 }, { 11285, 40, 1000, 200 } }
local BULLET = { { 2516, 1, 10, 200 }, { 2519, 10, 50, 200 }, { 3033, 25, 300, 200 }, { 11284, 40, 1000, 200 } }
local BANDAGE = { 1251, 2581, 3530, 3531, 6450, 6451, 8544, 8545, 14529 }
local HPOT = { { 118, 1 }, { 858, 3 }, { 929, 12 }, { 1710, 21 }, { 3928, 35 } }
local MPOT = { { 2455, 5 }, { 3385, 14 }, { 3827, 22 }, { 6149, 31 } }
-- 施法材料：{ 物品, 至少带几个, 商人价, { 用到它的技能（学会任意一个才查）} }；灵魂碎片买不到（吸取灵魂杀怪）
local REAGENT = {
    MAGE = { { 17031, 5, 1000, { 3561, 3562, 3563, 3565, 3566, 3567 } }, { 17056, 5, 30, { 130 } }, { 17032, 2, 2000, { 10059, 11416, 11417, 11418, 11419, 11420 } }, { 17020, 10, 1000, { 23028 } } },
    PRIEST = { { 17028, 10, 700, { 21562 } }, { 17029, 10, 1000, { 21564 } } },
    ROGUE = { { 5140, 5, 25, { 1856, 1857 } }, { 5530, 5, 500, { 2094 } } },
    SHAMAN = { { 17030, 1, 2000, { 20608 } } },
    PALADIN = { { 17033, 1, 2000, { 19752 } }, { 21177, 20, 3000, { 25782, 25894, 25898, 25890, 25895, 25899 } } },
    DRUID = { { 17034, 1, 200, { 20484 } }, { 17026, 5, 1000, { 21849, 21850 } } },
    WARLOCK = { { 6265, 3, 0, { 697, 6201, 693, 712 } } },
}
local NAMES = {
    [4540] = { "大块的硬面包", "Tough Hunk of Bread" }, [4541] = { "刚出炉的面包", "Freshly Baked Bread" }, [4542] = { "玉米面包", "Moist Cornbread" },
    [4544] = { "莫高雷香料面包", "Mulgore Spice Bread" }, [4601] = { "软香蕉面包", "Soft Banana Bread" }, [8950] = { "自制樱桃馅饼", "Homemade Cherry Pie" },
    [159] = { "清凉的泉水", "Refreshing Spring Water" }, [1179] = { "冰镇牛奶", "Ice Cold Milk" }, [1205] = { "果汁", "Melon Juice" },
    [1708] = { "蜂蜜饮料", "Sweet Nectar" }, [1645] = { "草莓汁", "Moonberry Juice" }, [8766] = { "晨露酒", "Morning Glory Dew" },
    [2512] = { "劣质箭", "Rough Arrow" }, [2515] = { "锋利的箭", "Sharp Arrow" }, [3030] = { "锐锋箭", "Razor Arrow" }, [11285] = { "锯齿箭", "Jagged Arrow" },
    [2516] = { "轻弹丸", "Light Shot" }, [2519] = { "重弹丸", "Heavy Shot" }, [3033] = { "实心子弹", "Solid Shot" }, [11284] = { "精准弹丸", "Accurate Slugs" },
    [1251] = { "亚麻绷带", "Linen Bandage" }, [118] = { "初级治疗药水", "Minor Healing Potion" }, [858] = { "次级治疗药水", "Lesser Healing Potion" },
    [929] = { "治疗药水", "Healing Potion" }, [1710] = { "强效治疗药水", "Greater Healing Potion" }, [3928] = { "超强治疗药水", "Superior Healing Potion" },
    [2455] = { "初级法力药水", "Minor Mana Potion" }, [3385] = { "次级法力药水", "Lesser Mana Potion" }, [3827] = { "法力药水", "Mana Potion" }, [6149] = { "强效法力药水", "Greater Mana Potion" },
    [17031] = { "传送符文", "Rune of Teleportation" }, [17032] = { "传送门符文", "Rune of Portals" }, [17056] = { "轻羽毛", "Light Feather" }, [17020] = { "魔粉", "Arcane Powder" },
    [17028] = { "圣洁蜡烛", "Holy Candle" }, [17029] = { "神圣蜡烛", "Sacred Candle" }, [5140] = { "闪光粉", "Flash Powder" }, [5530] = { "致盲粉", "Blinding Powder" },
    [17030] = { "十字章", "Ankh" }, [17033] = { "神圣符印", "Symbol of Divinity" }, [21177] = { "王者印记", "Symbol of Kings" }, [17034] = { "枫树种子", "Maple Seed" },
    [17026] = { "野生棘根草", "Wild Thornroot" }, [6265] = { "灵魂碎片", "Soul Shard" }, [4470] = { "普通木柴", "Simple Wood" }, [4471] = { "燧石和火绒", "Flint and Tinder" },
    [211527] = { "舒适的睡袋", "Cozy Sleeping Bag" },
}
local NO_MANA = { WARRIOR = true, ROGUE = true }
-- 阈值：少于 warn 份 = 快不够（黄）
XC.SUP = { eat = 20, drink = 20, ammo = 200, reagent = 0, bandage = 5, hpot = 3, repair = 50, repairBad = 20, space = 4 }
XC.SUP_DATA = { FOOD = FOOD, WATER = WATER, ARROW = ARROW, BULLET = BULLET, REAGENT = REAGENT, NAMES = NAMES }   -- 测试用

local ICON = {
    vendor = "Interface\\Icons\\INV_Misc_Coin_02", ah = "Interface\\Icons\\INV_Misc_Coin_04", tent = "Interface\\Icons\\INV_Misc_Tent",
    fire = "Interface\\Icons\\Spell_Fire_Fire", quest = "Interface\\GossipFrame\\AvailableQuestIcon", cook = "Interface\\Icons\\INV_Misc_Food_15",
    inn = "Interface\\Icons\\Spell_Nature_Sleep", repair = "Interface\\Icons\\Trade_BlackSmithing", sell = "Interface\\Icons\\INV_Misc_Bag_07",
    wait = "Interface\\Icons\\INV_Misc_PocketWatch_01", player = "Interface\\TargetingFrame\\UI-Classes-Circles", hunt = "Interface\\Icons\\Ability_Hunter_Pet_Wolf",
}
XC.SRC_ICON = ICON

-- ---------- 小工具 ----------
local function none() end
local function secret(v) return ns.Secret and ns.Secret(v) end
local function num(v) if v == nil or secret(v) then return nil end return tonumber(v) end
local function now() return GetTime and GetTime() or 0 end
-- 11-17 用户截图「显示不正确数量」：吃的 / 喝的 / 弹药 / 药水全是 0、「没箭袋」，其实包里都有。原因两条：
--   ① 只按固定的商人物品表数（自己钓的鱼 / 做的菜 / 别的箭 / 别的药水都不算）；② 只用老接口 GetItemCount（《无限》客户端里优先 C_Item.GetItemCount）
--   → 改成逐格扫背包 0~4（含箭袋 / 弹药袋），按物品类别（GetItemInfoInstant 的 classID / subClassID）归类；两种数法取大的
local function gic(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    local ok, n = pcall(f or none, id)
    return (ok and num(n)) or 0
end
local scan   -- 这一轮扫到的 { [物品] = 数量 }（XC.Supplies 开头扫一次）
local function count(id)
    local a = gic(id)
    local b = scan and scan[id] or 0
    return a > b and a or b
end
local function level() return num(UnitLevel and UnitLevel("player")) or 1 end
local function myClass() local ok, _, c = pcall(UnitClass or none, "player"); return ok and type(c) == "string" and c or nil end
local function resting() return IsResting and IsResting() and true or false end
local function money(c)
    if ns.Prices and ns.Prices.Money then local ok, s = pcall(ns.Prices.Money, c); if ok and s then return s end end
    if c >= 10000 then return string.format(L("%d金", "%dg"), math.floor(c / 10000)) end
    if c >= 100 then return string.format(L("%d银", "%ds"), math.floor(c / 100)) .. ((c % 100 > 0) and string.format(L("%d铜", "%dc"), c % 100) or "") end
    return string.format(L("%d铜", "%dc"), c)
end
local function iname(id)
    local n = ns.ItemInfo and ns.ItemInfo(id)
    if type(n) == "string" and n ~= "" and not secret(n) then return n end
    local t = NAMES[id]
    return t and L(t[1], t[2]) or ("#" .. id)
end
XC.ItemNameX = iname
local function iicon(id)
    local f = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    local ok, ic = pcall(f or none, id)
    return (ok and ic and not secret(ic)) and ic or "Interface\\Icons\\INV_Misc_QuestionMark"
end
local function known(ids)
    for _, id in ipairs(ids) do
        local ok, k = pcall(IsPlayerSpell or IsSpellKnown or none, id)
        if ok and k and not secret(k) then return true end
    end
    return false
end
-- 11-17「便携」：sh = 短名（宽窗口时图标旁边显示，如「拍卖行」「旅店老板」；放不下整排只剩图标，全文在悬停）
local function src(list, icon, text, ok, fn, tip, tc, sh)
    local e = { icon = icon, text = text, ok = ok and true or false, fn = fn, tip = tip, tc = tc, short = sh }
    list[#list + 1] = e
    return e
end
-- 能用的排前面（同为能用 / 不能用时保持写入顺序 = 优先级）
local function order(list)
    for i, s in ipairs(list) do s.i = i end
    table.sort(list, function(a, b) if a.ok ~= b.ok then return a.ok end return a.i < b.i end)
    return list
end
XC.SrcOrder = order
-- ---------- 11-17 用户截图四条：清单开关（存 xpcheck 表；nil = 默认开，thankAlways 默认关）----------
--   cbDim = 职业 BUFF 图标：身上有的变暗、缺的亮 · srcNav = 商人来源点了插旗导航 · bagHave = 包里有的物品变暗、不算没备好、点图标搜拍卖行
--   shoutBtn = 职业 BUFF 行的「喊」按钮 · thank = 有人加 BUFF 弹框回谢（false = 点过「不再提示」，永久关）· thankAlways = 不喊也回谢
local function opt2(k) return XC.DB()[k] ~= false end
XC.Opt2 = opt2
-- ---------- ② 商人来源：点了插旗到最近的商人（弹药走 ns.Ammo.Nearest，别的走 ReagentSrcData 里的商人坐标）----------
local ZUI = {}   -- 地区名 → 地图 ID（缓存；找不到记 false）
local function zoneUi(cn, en)
    local key = tostring(cn) .. "|" .. tostring(en)
    if ZUI[key] ~= nil then return ZUI[key] or nil end
    local found
    local cur = GetRealZoneText and GetRealZoneText()
    if type(cur) == "string" and not secret(cur) and (cur == cn or cur == en) and C_Map and C_Map.GetBestMapForUnit then
        local ok, ui = pcall(C_Map.GetBestMapForUnit, "player")
        found = ok and num(ui) or nil
    end
    if not found and C_Map and C_Map.GetMapChildrenInfo then
        for _, root in ipairs({ 1414, 1415, 947 }) do
            local ok, list = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
            for _, m in ipairs(ok and type(list) == "table" and list or {}) do
                local n = m.name
                if type(n) == "string" and not secret(n) and (n == cn or n == en) then found = num(m.mapID); break end
            end
            if found then break end
        end
    end
    ZUI[key] = found or false
    return found
end
XC.ZoneUi = zoneUi
-- 从一组 { ui, x, y, name } 里挑最近的（同一块大陆按世界坐标比；比不了 = 同图优先，再按写入顺序）
local function nearestPt(list)
    local T = ns.Trainers or {}
    local pui, px, py
    if T.PlayerPos then pui, px, py = T.PlayerPos() end
    local pw = pui and T.World and T.World(pui, px, py)
    local best, bd
    for i, p in ipairs(list) do
        local d
        local tw = pw and T.World(p.ui, p.x, p.y)
        if pw and tw and tw[1] == pw[1] then d = math.sqrt((tw[2] - pw[2]) ^ 2 + (tw[3] - pw[3]) ^ 2)
        elseif pui and p.ui == pui then d = math.sqrt((p.x - px) ^ 2 + (p.y - py) ^ 2) * 10
        else d = 1e9 + i end
        if not bd or d < bd then best, bd = p, d end
    end
    return best, bd
end
XC.NearestPt = nearestPt
local function pin(p, what)
    ns.ShowOnMap(p.ui, { { p.x, p.y } }, p.name)
    local T = ns.Trainers or {}
    ns.Print(string.format(L("已插旗：%s%s  %s %.1f, %.1f（小地图边上有箭头指路）", "Waypoint: %s%s  %s %.1f, %.1f (follow the minimap arrow)"),
        what and (what .. " ") or "", p.name or "", (T.ZoneName and T.ZoneName(p.ui)) or tostring(p.ui), p.x, p.y))
    XC.lastNav = p
    return true
end
-- kind：1 = 箭，2 = 子弹（按等级档位只找卖得到这一档的商人）
function XC.NavAmmo(kind)
    if not ns.Ammo and ns.ClassLoad then pcall(ns.ClassLoad) end
    local A = ns.Ammo
    if not (A and A.Nearest) then ns.Print(L("弹药商资料没加载（职业子插件），稍后再点", "Ammo vendor data not loaded yet - try again")); return false end
    local tier = A.Tier and A.Tier(kind, level())
    local ok, res = pcall(A.Nearest, kind, 1, tier and tier[1])
    local first = ok and res and res[1]
    if not first then ns.Print(L("没有找到你这个阵营的弹药商资料；打开一次卖弹药的商人窗口，插件会记下来", "No ammo vendors known for your faction")); return false end
    return pin(first.t, kind == 2 and L("枪械商", "Gunsmith") or L("弓箭商", "Bowyer"))
end
-- ids：按顺序试这些物品的商人（吃的没数据时用同档的水：旅店老板 / 杂货商两样都卖）
function XC.NavVendor(ids, what)
    local R = ns.ReagentSrc
    local list = {}
    for _, id in ipairs(type(ids) == "table" and ids or { ids }) do
        local d = R and R.items and R.items[id]
        for _, v in ipairs(d and d.v or {}) do
            local ui = zoneUi(v[3], v[4])
            if ui and v[5] and v[6] then list[#list + 1] = { ui = ui, x = v[5], y = v[6], name = L(v[1], v[2]) } end
        end
        if list[1] then break end
    end
    local p = nearestPt(list)
    if not p then
        ns.Print(string.format(L("没有找到%s的位置资料：主城问卫兵（旅店 / 杂货商）", "No location data for %s: ask a city guard"), what or L("商人", "a vendor")))
        return false
    end
    return pin(p, what)
end
local function navTip(t) return (t and (t .. "  ") or "") .. L("点击插旗导航", "Click to set a waypoint") end
-- ---------- ③ 拍卖行搜索（⛔ 只搜不买；不改写暴雪拍卖行的函数，只用它的搜索框 + 搜索按钮；有 Auctionator 优先走它的接口）----------
local function ahFrame()
    for _, n in ipairs({ "AuctionHouseFrame", "AuctionFrame" }) do
        local f = rawget(_G, n)
        if f and f.IsShown and f:IsShown() then return f, n end
    end
end
function XC.AHSearch(name)
    if type(name) ~= "string" or secret(name) or name == "" then return false, "noname" end
    if not ahFrame() then
        XC.ahPending = name
        ns.Print(string.format(L("到拍卖行后再点，会自动搜索：%s", "Open the Auction House - it will search for %s automatically"), name))
        return false, "closed"
    end
    XC.ahPending = nil
    local A = rawget(_G, "Auctionator")
    local api = type(A) == "table" and type(A.API) == "table" and A.API.v1
    if type(api) == "table" then
        local f = api.MultiSearchExact or api.MultiSearch
        if f and pcall(f, "GearInsight", { name }) then return true, "auctionator" end
    end
    local ah = rawget(_G, "AuctionHouseFrame")
    local bar = ah and ah.IsShown and ah:IsShown() and ah.SearchBar
    if bar and bar.SearchBox and bar.SearchButton then
        bar.SearchBox:SetText(name)
        bar.SearchButton:Click()
        return true, "blizzard"
    end
    local box, btn = rawget(_G, "BrowseName"), rawget(_G, "BrowseSearchButton")
    if box and btn then
        local br, tab = rawget(_G, "AuctionFrameBrowse"), rawget(_G, "AuctionFrameTab1")
        if br and br.IsShown and not br:IsShown() and tab and tab.Click then tab:Click() end
        box:SetText(name)
        btn:Click()
        return true, "classic"
    end
    return false, "nobox"
end
local ahEv = CreateFrame("Frame")
XC._ahEv = ahEv
pcall(ahEv.RegisterEvent, ahEv, "AUCTION_HOUSE_SHOW")
pcall(ahEv.RegisterEvent, ahEv, "PLAYER_REGEN_ENABLED")
ahEv:SetScript("OnEvent", function(_, e)
    if e == "AUCTION_HOUSE_SHOW" then
        local n = XC.ahPending
        if not n then return end
        local function go() if XC.ahPending == n then XC.AHSearch(n) end end
        if C_Timer and C_Timer.After then C_Timer.After(1, go) else go() end
    elseif e == "PLAYER_REGEN_ENABLED" and XC.ThankFlush then pcall(XC.ThankFlush) end
end)
-- 物品图标点了搜拍卖行（bagHave 开着才挂）
local function ahFn(id)
    if not opt2("bagHave") then return nil end
    return function() XC.AHSearch(iname(id)) end
end
-- 本城有没有卖它的商人（ReagentSrcData 里的商人坐标，和现在所在地区同名才算「本城」）
local function cityVendor(id)
    local R = ns.ReagentSrc
    local d = R and R.items and R.items[id]
    local zone = GetRealZoneText and GetRealZoneText()
    if not (d and d.v and type(zone) == "string") then return nil end
    for _, v in ipairs(d.v) do
        if v[3] == zone or v[4] == zone then return string.format("%s (%.0f, %.0f)", L(v[1], v[2]), v[5] or 0, v[6] or 0) end
    end
end
-- 商人来源：在主城 / 旅店（休息状态）= 亮；在野外 = 灰（回城买）
-- nav：点了做什么（不给 = 按物品 id 找卖它的商人）；navIds = 找商人时依次试的物品
local function vendorSrc(list, what, id, price, per, sh, nav, navIds)
    local here = cityVendor(id)
    local t = what .. (price and price > 0 and ("  " .. money(price) .. (per and per > 1 and ("/" .. per) or "")) or "")
    local e = src(list, ICON.vendor, (here and (L("本城 ", "Here: ") .. here) or what) .. (here and "" or (price and price > 0 and ("  " .. money(price)) or "")),
        resting(), nil, t .. (resting() and "" or L("（回主城买）", " (buy in town)")), nil, sh or L("商人", "Vendor"))
    if opt2("srcNav") then
        local label = sh or L("商人", "Vendor")
        e.fn = nav or function() return XC.NavVendor(navIds or { id }, label) end
        e.nav, e.clickTip = true, navTip()
    end
    return e
end
local function ahSrc(list, what, id)
    local p = id and ns.Prices and ns.Prices.Get and ns.Prices.Get(id)
    local e = src(list, ICON.ah, L("拍卖行", "Auction House") .. (p and ("  " .. money(p)) or ""), resting(), nil,
        (what and (what .. "  ") or "") .. (resting() and L("主城拍卖行买", "Buy at the Auction House") or L("回主城拍卖行买", "Buy at the AH in town")), nil, L("拍卖行", "AH"))
    e.fn = id and ahFn(id) or nil
    if e.fn then e.item, e.clickTip = id, L("点击：拍卖行搜这个（拍卖行没开 = 打开时自动搜）", "Click: search the AH for it (searches when you open the AH)") end
    return e
end
-- 包里有的物品来源：变暗（已经有了，不用再补）；点了搜拍卖行
local function bagSrc(list, id, n, tip, sh, ok)
    local e = src(list, iicon(id), iname(id) .. " ×" .. n, ok ~= false, nil, tip or L("包里有", "In your bags"), nil, sh or ("×" .. n))
    if opt2("bagHave") then
        e.dim, e.have, e.item = true, true, id
        e.fn = ahFn(id)
        e.clickTip = L("包里有（变暗）· 点击：拍卖行搜这个", "In your bags (dimmed) · Click: search the AH")
    end
    return e
end
local function best(tiers, lv)
    local b
    for _, t in ipairs(tiers) do if t[2] <= lv then b = t end end
    return b
end
-- ---------- 扫背包 ----------
local function cfn(k) return (C_Container and C_Container[k]) or rawget(_G, k) end
local function nbags() return num(NUM_BAG_SLOTS) or 4 end
local function slots(bag) local ok, n = pcall(cfn("GetContainerNumSlots") or none, bag); return (ok and num(n)) or 0 end
local function slotItem(bag, slot)
    local f = cfn("GetContainerItemInfo")
    if not f then return nil end
    local ok, a, b, _, _, _, _, link, _, _, id = pcall(f, bag, slot)
    if not ok then return nil end
    if type(a) == "table" then return num(a.itemID), num(a.stackCount) or 1 end
    id = num(id)
    if not id and type(link) == "string" and not secret(link) then id = tonumber(link:match("item:(%d+)")) end
    return id, num(b) or 1
end
-- 11-18 卡顿 / 内存（用户截图插件 143 MB、「有点卡顿」）：出发前清单 / 经验加成页开着时每 2 秒整页重算一遍，
--   每次都逐格读背包（一格一次 GetContainerItemInfo，游戏里每次返回一张新表）→ 一分钟上千张表。
--   改成：定时刷新（XC.scanReuse = true，只有那两个 OnUpdate 里设）时，背包没动过（没来 BAG_UPDATE）就用上一轮扫的结果；
--   背包一动（BAG_UPDATE / BAG_UPDATE_DELAYED / 换图）就作废，最多也只用 BAG_REUSE_MAX 秒。手动刷新 / 其它调用照旧每次现扫
XC.BAG_REUSE_MAX = 30
local bagCache, bagAny, bagAt
local bagEv = CreateFrame("Frame")
for _, e in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "PLAYERBANKSLOTS_CHANGED" }) do pcall(bagEv.RegisterEvent, bagEv, e) end
bagEv:SetScript("OnEvent", function() bagCache = nil end)
XC._bagEv = bagEv   -- 测试用
function XC.BagScan()
    if XC.scanReuse and bagCache and bagAt and now() - bagAt <= XC.BAG_REUSE_MAX then return bagCache, bagAny end
    local by, any = XC.BagScanNow()
    bagCache, bagAny, bagAt = by, any, now()
    return by, any
end
function XC.BagScanNow()
    local by, any = {}, false
    for bag = 0, nbags() do
        for slot = 1, slots(bag) do
            local id, n = slotItem(bag, slot)
            if id then by[id] = (by[id] or 0) + (n or 1); any = true end
        end
    end
    return by, any
end
local function meta(id)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local ok, _, _, _, _, _, c, s = pcall(f or none, id)
    if ok then return num(c), num(s) end
end
XC.ItemMeta = meta
local function inList(list, id)
    for _, x in ipairs(list) do if (type(x) == "table" and x[1] or x) == id then return true end end
    return false
end
local function has(str, words)
    if type(str) ~= "string" or secret(str) then return false end
    for _, w in ipairs(words) do if str:find(w, 1, true) then return true end end
    return false
end
local function spellOf(id)
    local f = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    local ok, n = pcall(f or none, id)
    return ok and type(n) == "string" and not secret(n) and n or nil
end
local function rawName(id) local n = ns.ItemInfo and ns.ItemInfo(id); return type(n) == "string" and not secret(n) and n or nil end
-- 食物和饮料（消耗品 0 / 5）：先查已知表，再看使用效果的法术名（进食 / 喝水 / 点心）；都读不到算吃的
local W_BOTH, W_DRINK, W_FOOD = { "点心", "Refreshment" }, { "喝水", "饮用", "饮料", "Drink" }, { "进食", "Food" }
function XC.FoodKind(id)
    if inList(FOOD, id) or inList(CONJ_FOOD, id) then return "eat" end
    if inList(WATER, id) or inList(CONJ_WATER, id) then return "drink" end
    local sp = spellOf(id)
    if has(sp, W_BOTH) then return "both" end
    if has(sp, W_DRINK) then return "drink" end
    return "eat"
end
-- 药水（消耗品 0 / 1）：治疗 / 法力 / 别的（迅捷、怒气…不算）；名字和法术都读不到 → 算治疗
local W_MANA, W_HEAL = { "法力", "Mana" }, { "治疗", "Healing", "Heal" }
function XC.PotKind(id)
    if inList(HPOT, id) then return "hp" end
    if inList(MPOT, id) then return "mp" end
    local nm, sp = rawName(id), spellOf(id)
    if has(nm, W_MANA) or has(sp, W_MANA) then return "mp" end
    if has(nm, W_HEAL) or has(sp, W_HEAL) then return "hp" end
    if not nm and not sp then return "hp" end
    return nil
end
-- 归类：{ eat = { 物品… }, drink, arrow, bullet, band, hp, mp }（每类按数量从多到少）
function XC.Goods(by)
    local g = { eat = {}, drink = {}, arrow = {}, bullet = {}, band = {}, hp = {}, mp = {} }
    for id, n in pairs(by or {}) do
        local c, sc = meta(id)
        local k
        if c == 0 and sc == 5 then k = XC.FoodKind(id)
        elseif c == 6 and (sc == 2 or sc == 3) then k = (sc == 3) and "bullet" or "arrow"
        elseif c == 0 and sc == 7 then k = "band"
        elseif c == 0 and sc == 1 then k = XC.PotKind(id) end
        if k == "both" then g.eat[#g.eat + 1] = id; g.drink[#g.drink + 1] = id
        elseif k then g[k][#g[k] + 1] = id end
    end
    for _, l in pairs(g) do table.sort(l, function(a, b) if by[a] ~= by[b] then return by[a] > by[b] end return a < b end) end
    return g
end
-- 合并「扫到的这一类」和「已知物品表」（扫不到背包的旧环境只剩表）
local function merge(a, b)
    local out, seen = {}, {}
    for _, l in ipairs({ a or {}, b or {} }) do
        for _, x in ipairs(l) do local id = type(x) == "table" and x[1] or x; if not seen[id] then seen[id] = true; out[#out + 1] = id end end
    end
    return out
end
-- 箭袋 / 弹药袋：1~4 号包的格子类型（1 = 箭袋，2 = 弹药袋）或装着的包是「箭袋」类（11）；包格位置按接口算（新客户端不是 20~23）
local function bagInv(bag)
    local f = cfn("ContainerIDToInventoryID")
    if f then local ok, id = pcall(f, bag); if ok and num(id) then return num(id) end end
    return 19 + bag
end
function XC.HasQuiver()
    local free = cfn("GetContainerNumFreeSlots")
    for bag = 1, nbags() do
        local ok, _, fam = pcall(free or none, bag)
        fam = ok and num(fam)
        if fam and fam > 0 and fam % 4 > 0 then return true end
        local ok2, id = pcall(GetInventoryItemID or none, "player", bagInv(bag))
        if ok2 and num(id) and meta(num(id)) == 11 then return true end
    end
    return false
end
local function sum(ids)
    local n = 0
    for _, x in ipairs(ids) do n = n + count(type(x) == "table" and x[1] or x) end
    return n
end
local function bagSrcs(list, ids, maxN)
    local c = 0
    for _, x in ipairs(ids) do
        local id = type(x) == "table" and x[1] or x
        local n = count(id)
        if n > 0 and c < (maxN or 2) then c = c + 1; bagSrc(list, id, n) end
    end
end
-- 「0/20」：够了只写数量（「30」），没够写「有/建议」
local function frac(n, need) if n >= need then return tostring(n) end return n .. "/" .. need end
local function st3(n, warn, opt)
    if n <= 0 then return opt and "info" or "miss" end
    if n < warn then return "warn" end
    return "ok"
end

-- ---------- 附近的法师（法师水 / 面包）：BuffAsk 记的附近玩家里挑法师；点了走右键菜单那套 MA.Ask（点了才密，10 分钟同一个法师一次）----------
local function mageSrc(list)
    local BA = ns.BuffAsk
    if not (BA and BA.near) or myClass() == "MAGE" then return end
    local t = now()
    for _, v in pairs(BA.near) do
        if v.cls == "MAGE" and t - v.t <= (BA.NEAR_TTL or 120) then
            local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS.MAGE
            local nm = (v.who or ""):gsub("%-.*$", "")
            src(list, ICON.player, string.format(L("法师 %s", "Mage %s"), nm), true,
                function() if ns.MageAskMenu and ns.MageAskMenu.Ask then ns.MageAskMenu.Ask(v.who, v.lv) end end,
                L("附近的法师：点了密他要水 / 面包（和右键菜单「找他要水」一样，10 分钟同一个人一次）", "Nearby mage: click to whisper for water / food"), tc, L("法师", "Mage ") .. nm)
            return
        end
    end
end

-- ---------- 物资 ----------
local function row(key, st, text, sl, extra)
    local r = { key = key, st = st, text = text, src = order(sl) }
    if extra then for k, v in pairs(extra) do r[k] = v end end
    return r
end
function XC.Supplies()
    local out, lv, cls = {}, level(), myClass()
    if lv >= ((num(GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60)) then return out end
    local function on(k) return XC.ItemOn(k) end
    local any
    scan, any = XC.BagScan()
    local G = XC.Goods(scan)
    XC.lastGoods = G   -- 测试 / 诊断用
    -- 吃 / 喝
    if on("sfood") then
        for _, w in ipairs({ { "eat", FOOD, CONJ_FOOD, L("吃的", "Food") }, { "drink", WATER, CONJ_WATER, L("喝的", "Drink") } }) do
            if not (w[1] == "drink" and NO_MANA[cls or ""]) then
                local ids = merge(G[w[1]], any and {} or merge(w[2], w[3]))
                local n = sum(ids)
                local b = best(w[2], lv)
                local sl = {}
                bagSrcs(sl, ids)
                mageSrc(sl)
                local wb = best(WATER, lv)
                vendorSrc(sl, L("旅店 / 杂货商：", "Innkeeper / vendor: ") .. iname(b[1]), b[1], b[3], b[4], L("旅店老板", "Innkeeper"), nil, { b[1], wb and wb[1] or 159, 159 })
                local need = XC.SUP[w[1]]
                out[#out + 1] = row(w[1], st3(n, need), string.format(L("%s %d 个", "%s: %d"), w[4], n) .. (n < need and string.format(L("（建议带 %d 个以上：%s）", " (bring %d+: %s)"), need, iname(b[1])) or ""), sl,
                    { title = w[4], icon = iicon(b[1]), short = w[4] .. " " .. frac(n, need), tiny = frac(n, need), n = n })
            end
        end
    end
    -- 弹药（猎人）
    if on("ammo") and cls == "HUNTER" then
        local ok, id = pcall(GetInventoryItemID or none, "player", 18)
        local sub
        if ok and num(id) then
            local ok2, _, _, _, _, _, c, s = pcall((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant or none, id)
            sub = ok2 and num(c) == 2 and num(s) or nil
        end
        local tiers = (sub == 3) and BULLET or ARROW
        local ids = merge((sub == 3) and G.bullet or G.arrow, any and {} or tiers)
        local n, b = sum(ids), best(tiers, lv)
        local quiver = XC.HasQuiver()
        local sl = {}
        bagSrcs(sl, ids)
        local akind = (sub == 3) and 2 or 1
        local function goAmmo() return XC.NavAmmo(akind) end
        vendorSrc(sl, (sub == 3 and L("枪械商：", "Gunsmith: ") or L("弓箭商：", "Bowyer: ")) .. iname(b[1]), b[1], b[3], b[4], sub == 3 and L("枪械商", "Gunsmith") or L("弓箭商", "Bowyer"), goAmmo)
        if not quiver then
            local q = src(sl, ICON.vendor, L("没有箭袋 / 弹药袋（装一个射速更快）", "No quiver / ammo pouch"), false, nil, L("弓箭商 / 枪械商有卖，也可以任务拿", "Sold by bowyers / gunsmiths"), nil, L("箭袋", "Quiver"))
            if opt2("srcNav") then q.fn, q.nav, q.clickTip = goAmmo, true, navTip() end
        end
        out[#out + 1] = row("ammo", st3(n, XC.SUP.ammo), string.format(L("弹药 %d 发", "Ammo: %d"), n) .. (n < XC.SUP.ammo and string.format(L("（建议 %d 发以上）", " (bring %d+)"), XC.SUP.ammo) or "")
            .. (quiver and "" or L(" · 没箭袋", " · no quiver")), sl, { title = L("弹药", "Ammo"), icon = iicon(b[1]), n = n, quiver = quiver,
            short = L("弹药 ", "Ammo ") .. frac(n, XC.SUP.ammo) .. (quiver and "" or L(" · 无箭袋", " · no quiver")), tiny = frac(n, XC.SUP.ammo) })
    end
    -- 施法材料（学会了用它的技能才查）
    if on("reagent") then
        for _, e in ipairs(REAGENT[cls or ""] or {}) do
            if known(e[4]) then
                local n = count(e[1])
                local sl = {}
                bagSrcs(sl, { e[1] })
                if e[3] > 0 then vendorSrc(sl, L("施法材料商：", "Reagent vendor: ") .. iname(e[1]), e[1], e[3], nil, L("材料商", "Reagents"))
                else src(sl, ICON.hunt, L("吸取灵魂打怪拿", "Drain Soul on a dying mob"), true, nil, L("怪死前对它吸取灵魂", "Channel Drain Soul as it dies"), nil, L("吸取灵魂", "Drain Soul")) end
                out[#out + 1] = row("reagent", st3(n, e[2]), string.format(L("%s %d 个", "%s: %d"), iname(e[1]), n) .. (n < e[2] and string.format(L("（建议带 %d 个）", " (bring %d)"), e[2]) or ""), sl,
                    { title = L("施法材料", "Reagents"), icon = iicon(e[1]), short = iname(e[1]) .. " " .. frac(n, e[2]), tiny = frac(n, e[2]), n = n })
            end
        end
    end
    -- 绷带 / 药水（可选：没有 = 灰）
    if on("potion") then
        local bids, hids = merge(G.band, any and {} or BANDAGE), merge(G.hp, any and {} or HPOT)
        local nb, nh = sum(bids), sum(hids)
        local sl = {}
        bagSrcs(sl, bids, 1); bagSrcs(sl, hids, 1)
        local hb = best(HPOT, lv)
        src(sl, ICON.cook, L("急救自己做绷带（布）", "Craft bandages with First Aid"), false, nil, L("学了急救：用布做绷带", "First Aid: make bandages from cloth"), nil, L("急救自做", "First Aid"))
        ahSrc(sl, iname(hb[1]), hb[1])
        local txt = string.format(L("绷带 %d · 治疗药水 %d", "Bandages %d · healing potions %d"), nb, nh)
        local sh = string.format(L("绷带 %d · 药水 %d", "Bandage %d · potion %d"), nb, nh)
        local nm = 0
        if not NO_MANA[cls or ""] then
            local mids = merge(G.mp, any and {} or MPOT)
            nm = sum(mids)
            bagSrcs(sl, mids, 1)
            txt = txt .. string.format(L(" · 法力药水 %d", " · mana potions %d"), nm)
            sh = sh .. string.format(L(" · 蓝 %d", " · mana %d"), nm)
        end
        local n = nb + nh
        out[#out + 1] = row("potion", (n <= 0 and "info") or ((nb < XC.SUP.bandage and nh < XC.SUP.hpot) and "warn") or "ok", txt, sl,
            { title = L("绷带 / 药水", "Bandages / potions"), icon = iicon(1251), short = sh, tiny = nb .. "·" .. nh, nb = nb, nh = nh, nm = nm })
    end
    -- 修理
    if on("repair") then
        local lo
        for slot = 1, 18 do
            local ok, cur, mx = pcall(GetInventoryItemDurability or none, slot)
            cur, mx = ok and num(cur), ok and num(mx)
            if cur and mx and mx > 0 then local p = cur / mx * 100; if not lo or p < lo then lo = p end end
        end
        if lo then
            lo = math.floor(lo + 0.5)
            local sl = {}
            src(sl, ICON.repair, L("武器商 / 护甲商修理", "Repair at a weapon / armor vendor"), resting(), nil, L("主城武器 / 护甲商人「修理」按钮", "Use the repair button at a smith"), nil, L("武器商", "Smith"))
            out[#out + 1] = row("repair", (lo <= XC.SUP.repairBad and "miss") or (lo <= XC.SUP.repair and "warn") or "ok",
                string.format(L("最低耐久 %d%%", "Lowest durability %d%%"), lo) .. (lo <= XC.SUP.repair and L("（出发前修一下）", " (repair before you go)") or ""), sl,
                { title = L("修理", "Repair"), icon = ICON.repair, short = string.format(L("耐久 %d%%", "Durability %d%%"), lo), tiny = lo .. "%" })
        end
    end
    -- 背包空格
    if on("space") and ns.BagFreeSlots then
        local ok, free, total = pcall(ns.BagFreeSlots)
        free = ok and num(free)
        if free then
            local sl = {}
            src(sl, ICON.sell, L("清背包（按价值从低到高）", "Bag cleanup (cheapest first)"), true,
                function() if ns.BagLoad and ns.BagLoad(false) and ns.ToggleMain then ns.ToggleMain("trash") end end, L("点了打开 GearInsight 清背包页", "Opens the GearInsight bag cleanup page"), nil, L("清背包", "Clean up"))
            src(sl, ICON.vendor, L("商人处卖垃圾（商人助手）", "Sell junk at a vendor (merchant helper)"), resting(), nil, L("打开商人窗口时右边的 GearInsight 商人助手", "The GearInsight panel next to the merchant window"), nil, L("卖垃圾", "Sell junk"))
            out[#out + 1] = row("space", (free <= 0 and "miss") or (free <= XC.SUP.space and "warn") or "ok",
                string.format(L("背包空格 %d", "Free bag slots: %d"), free) .. ((total and num(total)) and ("/" .. total) or ""), sl,
                { title = L("背包空格", "Bag space"), icon = ICON.sell, short = L("空格 ", "Free ") .. free .. ((total and num(total)) and ("/" .. total) or ""), tiny = tostring(free) })
        end
    end
    return out
end

-- ---------- 职业 BUFF（cbuff）：缺的 ← 附近能给的人 ----------
-- 附近能给 k 这一类 BUFF 的人（BuffAsk.Note 记的，最近见到的在前）
local function nearby(BA, k)
    local ty, out, t = BA.BY_K and BA.BY_K[k], {}, now()
    if not (ty and BA.near) then return out end
    for _, v in pairs(BA.near) do
        if t - v.t <= (BA.NEAR_TTL or 120) and v.t <= t and v.cls == ty.cls and (not v.lv or v.lv >= ty.lv) then out[#out + 1] = v end
    end
    table.sort(out, function(a, b) return a.t > b.t end)
    return out
end
XC.Nearby = nearby
-- 点「牧师 XX」：走要 BUFF 原来的弹框（BA.ShowField：点「密他要」才发；同一个人 10 分钟一次），不另外发言
--   11-18 k = 点的是哪一种 BUFF（圣骑士祝福逐种去要：只问这一种）；BA.AskNext 在（新组队信标）：
--   同一个图标再点一次 = 换附近下一个能给的人（用户「附近有别人点第二次就切换人啊」），跳过 10 分钟内密过的
function XC.AskNear(who, k)
    local BA = ns.BuffAsk
    if not BA then return false, "gone" end
    if k and BA.AskNext then return BA.AskNext({ [k] = true }, XC.cbAvoid and XC.cbAvoid[k]) end
    local v = BA.near and BA.near[who]
    if not v then return false, "gone" end
    if BA.RecentlyAsked(who) or BA.SeenRecently(who) then
        ns.Print(string.format(L("10 分钟内已经问过 %s 了", "Already asked %s in the last 10 minutes"), (BA.Short and BA.Short(who)) or who))
        return false, "asked"
    end
    local list = BA.CanGive(v.cls, v.lv, k and { [k] = true } or BA.Missing(), who)
    if #list == 0 then return false, "nothing" end
    BA.ShowField({ who = who, cls = v.cls, lv = v.lv, list = list, want = BA.WantOf and BA.WantOf(list) or nil })
    return true
end
-- 职业 BUFF 图标的悬停里加的几行：现在点了问谁 / 附近还有几个（再点换人）/ 圣骑士一人一种 / 当前称呼（右键改）
local function cbTip(BA, t, g, n, cur)
    local lines = {}
    if cur then lines[#lines + 1] = string.format(L("小框里现在是 %s；再点一次换成 %s", "Prompt shows %s; click again for %s"), (BA.Short and BA.Short(cur)) or cur, (g.who or ""):gsub("%-.*$", "")) end
    lines[#lines + 1] = L("点了弹「要 BUFF」小框，点「密他要」才发（同一个人 10 分钟一次）", "Opens the buff prompt; it only whispers if you click")
    if n > 1 then lines[#lines + 1] = string.format(L("附近还有 %d 个能给，再点换人", "%d more nearby can give it - click again to switch"), n - 1) end
    if t.fam == "bless" then lines[#lines + 1] = L("一个圣骑士只能给你挂一种祝福：不同的祝福要找不同的圣骑士", "One Paladin keeps only one blessing on you: get each blessing from a different Paladin") end
    if ns.CallTip then lines[#lines + 1] = ns.CallTip() end
    return table.concat(lines, "\n")
end
function XC.ClassBuffs()
    local BA = ns.BuffAsk
    if not (BA and BA.Missing and BA.TYPES) or not XC.ItemOn("cbuff") then return nil end
    local ok, miss = pcall(BA.Missing)
    if not ok or type(miss) ~= "table" then return nil end
    local sl, names, have, missK = {}, {}, false, {}
    -- 11-17 用户截图「职业BUFF 缺N」：右边改成 BUFF 自己的图标 —— 缺的亮、身上已经有的变暗（cbDim，默认开）
    local dimOn = opt2("cbDim")
    local cls = myClass()
    -- 11-18 「祝福要齐全」：力量 / 智慧 / 王者各一个图标、各找各的圣骑士（一个圣骑士只能给你挂一种）→ 已经被前面图标占了的圣骑士后面不再排
    local usedP, newGivers = {}, BA.PeekGiver ~= nil
    XC.cbAvoid = {}
    local curO = BA.frame and BA.frame.IsShown and BA.frame:IsShown() and BA.cur or nil
    -- 11-19 主城卡顿闸：身上的祝福一轮只读一次，传给每种 BUFF 的 PeekGiver（原来每个圣骑士 × 每种祝福各读一遍）
    local from
    if newGivers and BA.BlessFrom then
        for _, t in ipairs(BA.TYPES) do
            if t.fam == "bless" and miss[t.k] then from = BA.BlessFrom() or false; break end
        end
    end
    for _, t in ipairs(BA.TYPES) do
        if miss[t.k] then
            names[#names + 1] = L(t.cn, t.en)
            missK[#missK + 1] = t.k
            local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[t.cls]
            local cn = BA.CLS_CN and BA.CLS_CN[t.cls]
            local cname = type(cn) == "table" and L(cn[1], cn[2]) or tostring(cn or t.cls)
            local want = { [t.k] = true }
            local v, n, cur
            if newGivers then
                local avoid = (t.fam == "bless") and usedP or nil
                if avoid then local c = {}; for w in pairs(avoid) do c[w] = true end; XC.cbAvoid[t.k] = c end
                cur = (curO and not curO.dungeon and not curO.sample and curO.want and BA.WantKey and BA.WantKey(curO.want) == t.k) and curO.who or nil
                local all
                v, all = BA.PeekGiver(want, avoid, cur, from)
                n = #all
                if not v and cur then v = { who = cur, cls = t.cls } end   -- 只有框里这一个
            else
                local list = nearby(BA, t.k)
                v, n = list[1], #list
            end
            local e
            if v then
                have = true
                if t.fam == "bless" then usedP[v.who] = true end
                local nm = (v.who or ""):gsub("%-.*$", "")
                local k = t.k
                e = src(sl, ICON.player, string.format("%s %s → %s", cname, nm, L(t.cn, t.en)), true,
                    function() XC.AskNear(v.who, k) end, cbTip(BA, t, v, n, cur ~= v.who and cur or nil), tc, nm)
                e.callMenu = true
            else
                local tip = L("碰到能给的人会自动弹框问你（要 BUFF 模块）", "The buff module prompts you when one passes by")
                if t.fam == "bless" and next(usedP) then
                    tip = L("附近的圣骑士已经排给了别的祝福（一个圣骑士只能给你挂一种），这种要再找一个圣骑士", "Nearby Paladins are already used for another blessing (one each); find another Paladin") .. "\n" .. tip
                elseif t.fam == "bless" then
                    tip = L("一个圣骑士只能给你挂一种祝福：不同的祝福要找不同的圣骑士", "One Paladin keeps only one blessing on you") .. "\n" .. tip
                end
                if ns.CallTip then tip = tip .. "\n" .. ns.CallTip() end
                e = src(sl, ICON.player, string.format(L("附近没有%s（%s）", "No %s nearby (%s)"), cname, L(t.cn, t.en)), false, nil, tip, tc, L("无", "No ") .. cname)
                e.callMenu = true
            end
            if dimOn then e.icon, e.tc, e.lit, e.bk = XC.BuffIcon(t), nil, true, t.k end
        end
    end
    if dimOn then
        for _, t in ipairs(BA.TYPES) do
            if not miss[t.k] and BA.Useful(t, cls) then
                local e = src(sl, XC.BuffIcon(t), L(t.cn, t.en) .. L("：身上有了", ": active"), false, nil, L("已经有了（图标变暗）", "Already on you (dimmed)"), nil, L(t.cn, t.en))
                e.dim, e.have, e.bk = true, true, t.k
            end
        end
    end
    if not names[1] then
        return row("cbuff", "ok", L("该有的职业 BUFF 都在", "You have the class buffs you can use"), sl, { title = L("职业 BUFF", "Class buffs") })
    end
    -- 附近有人能给 = 红（现在就能补）；附近没人 = 灰（不算缺，碰到会弹框）
    return row("cbuff", have and "miss" or "info", L("缺：", "Missing: ") .. table.concat(names, L("、", ", ")), sl,
        { title = L("职业 BUFF", "Class buffs"), srcText = have and sl[1].text or nil, nMiss = #names, missK = missK })
end

-- BUFF 图标：先问客户端（第一级法术的图标），读不到用经典图标
local BUFF_ICON = { fort = "Interface\\Icons\\Spell_Holy_WordFortitude", int = "Interface\\Icons\\Spell_Holy_MagicalSentry",
    motw = "Interface\\Icons\\Spell_Nature_Regeneration", might = "Interface\\Icons\\Spell_Holy_FistOfJustice",
    wis = "Interface\\Icons\\Spell_Holy_SealOfWisdom", kings = "Interface\\Icons\\Spell_Magic_MageArmor" }
XC.BUFF_ICON = BUFF_ICON
function XC.BuffIcon(t)
    local id = t.ids and t.ids[1]
    local f = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
    if id and f then
        local ok, ic = pcall(f, id)
        if ok and ic ~= nil and not secret(ic) then return ic end
    end
    return BUFF_ICON[t.k] or "Interface\\Icons\\INV_Misc_QuestionMark"
end
-- ③ 这一项要的东西包里已经有了（经验药剂 / 药剂武器油「包里有没用」、经验食物「包里有」）→ 清单里变暗、不算没备好
function XC.InBag(it)
    if not (it and opt2("bagHave")) then return false end
    if it.use and not it.use.trinket and (tonumber(it.use.n) or 1) > 0 then return true end
    if it.key == "food" and XC.Foods then
        local ok, have = pcall(XC.Foods)
        return (ok and type(have) == "table" and have[1] ~= nil) and true or false
    end
    return false
end

-- ---------- ④ 喊 BUFF（11-17 用户「喊 BUFF 模式」）：点「喊」（硬件事件里）在 /说（11-19 起可选 /大喊）发一句带位置 + 缺什么；副本里发队伍 ----------
--   ⛔ 不带插件名、不带任何标识（网易DD 11-13）；同一句 10 秒内只喊一次（11-18 用户截图「10S一次吧」，原 60 秒）
XC.SHOUT_CD, XC.THANK_ARM, XC.THANK_TTL, XC.THANK_GAP, XC.THANK_PEND = 10, 600, 20, 300, 60
local function bk(k) local BA = ns.BuffAsk; return BA and BA.BY_K and BA.BY_K[k] end
local function joinK(ks, chat)   -- chat = 发出去的话（11-19 走对外说话语言）
    local n = {}
    for _, k in ipairs(ks or {}) do local t = bk(k); if t then n[#n + 1] = chat and ns.ChatName(t.cn, t.en) or L(t.cn, t.en) end end
    return table.concat(n, (chat and ns.ChatL or L)("、", ", "))
end
XC.JoinBuffs = joinK
-- 位置：客户端有地图标记链接（C_Map.SetUserWaypoint + GetUserWaypointHyperlink）就附链接（发完还原原来的标记），否则「地区名 坐标」
function XC.LocText()
    local T = ns.Trainers or {}
    local ui, x, y
    if T.PlayerPos then ui, x, y = T.PlayerPos() end
    local zone = ui and T.ZoneName and T.ZoneName(ui)
    if type(zone) ~= "string" or secret(zone) then zone = GetRealZoneText and GetRealZoneText() end
    if type(zone) ~= "string" or secret(zone) then zone = nil end
    zone = zone and ns.ChatZone(zone)   -- 11-19 地区名是客户端语言：和对外说话语言不一样就不写（坐标 / 地图标记照发）
    if not (ui and x and y) then return zone end
    if C_Map and C_Map.SetUserWaypoint and C_Map.GetUserWaypointHyperlink and UiMapPoint and UiMapPoint.CreateFromCoordinates
        and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(ui)) then
        local prev = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
        local link
        if pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(ui, x / 100, y / 100)) then
            local ok, l = pcall(C_Map.GetUserWaypointHyperlink)
            if ok and type(l) == "string" and not secret(l) then link = l end
        end
        if prev then pcall(C_Map.SetUserWaypoint, prev) elseif C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
        if link then return (zone and (zone .. " ") or "") .. link end
    end
    return string.format("%s %d,%d", zone or "", math.floor(x + 0.5), math.floor(y + 0.5))
end
function XC.ShoutText(ks)
    local names = joinK(ks, true)
    if names == "" then return nil end
    local loc = XC.LocText()
    local t = string.format(ns.ChatL("求BUFF义父：%s", "Buffs please, friend: %s"), names) .. (loc and loc ~= "" and (" @" .. loc) or "")
    return ns.ApplyCall and ns.ApplyCall(t) or t   -- 11-18 GI-307 称呼可改
end
-- 11-19 用户「可以选普通白色或者大喊」：副本外喊 BUFF 用 /说（白字，默认）还是 /大喊，存 ns.db.xpcheck.shoutYell（true = 大喊；nil = 说）
--   入口：「喊」按钮 / 职业 BUFF 图标 / 职业 BUFF 行右键的小菜单（和称呼放一起，当前那个打勾）；副本里有队伍照旧发队伍 / 团队
function XC.ShoutYell() return XC.DB().shoutYell == true end
function XC.SetShoutYell(v) XC.DB().shoutYell = v and true or nil end
local CHAN_TXT = { SAY = { "说（白字）", "Say (white)" }, YELL = { "大喊", "Yell" }, PARTY = { "队伍", "Party" }, RAID = { "团队", "Raid" } }
function XC.ShoutChanText(chan)
    local c = CHAN_TXT[chan or (XC.ShoutYell() and "YELL" or "SAY")]
    return c and L(c[1], c[2]) or tostring(chan)
end
-- 频道：副本里（有队伍）发团队 / 队伍，其余 /说 或 /大喊（玩家选的）
function XC.ShoutChan()
    local inInst = IsInInstance and IsInInstance()
    if inInst then
        if IsInRaid and IsInRaid() then return "RAID" end
        if (IsInGroup and IsInGroup()) or ((num(GetNumGroupMembers and GetNumGroupMembers()) or 0) > 0) then return "PARTY" end
    end
    return XC.ShoutYell() and "YELL" or "SAY"
end
-- 右键小菜单：频道两项（当前的打勾）+ 称呼那几项（Settings.lua 的 ns.CallMenuItems）
local CHECK = "|TInterface\\Buttons\\UI-CheckBox-Check:14:14|t"
function XC.ShoutMenuItems(anchor, after)
    local y = XC.ShoutYell()
    local function chan(on, v, cn, en)
        return { text = (on and CHECK or "|TInterface\\Buttons\\UI-CheckBox-Up:14:14|t") .. L(cn, en), fn = function()
            XC.SetShoutYell(v)
            ns.Print(L("喊 BUFF 的频道改成：", "Buff request channel: ") .. XC.ShoutChanText() .. L("（副本里照旧发队伍）", " (party chat in dungeons)"))
            if type(after) == "function" then pcall(after) end
        end }
    end
    local items = { chan(not y, false, "频道：说（白字）", "Channel: Say (white)"), chan(y, true, "频道：大喊", "Channel: Yell") }
    for _, it in ipairs(ns.CallMenuItems and ns.CallMenuItems(anchor, after) or {}) do items[#items + 1] = it end
    return items
end
function XC.ShoutMenu(anchor, after)
    if not ns.PopMenu then return ns.CallMenu and ns.CallMenu(anchor, after) end
    return ns.PopMenu(anchor or UIParent, string.format(L("喊 BUFF：%s · 称呼：%s", "Ask: %s · address: %s"), XC.ShoutChanText(), ns.CallWord and ns.CallWord() or ""),
        XC.ShoutMenuItems(anchor, after))
end
local function canChat()
    local BA = ns.BuffAsk
    if BA and BA.CanChat then return BA.CanChat() end
    return not (InCombatLockdown and InCombatLockdown())
end
-- 点「喊」：ks = 缺的几类（ClassBuffs 的 missK）
function XC.Shout(ks)
    if type(ks) ~= "table" or not ks[1] then return false, "none" end
    local key = table.concat(ks, ",")
    local t = now()
    if XC.shoutKey == key and XC.shoutT and t - XC.shoutT < XC.SHOUT_CD then
        ns.Print(string.format(L("刚喊过了，%d 秒后才能再喊同一句", "Just asked - wait %d s before asking again"), math.ceil(XC.SHOUT_CD - (t - XC.shoutT))))
        return false, "cd"
    end
    if not canChat() then ns.Print(L("现在发不了（战斗中 / 聊天受限），过一会儿再点", "Can't send right now (combat / chat locked)")); return false, "chat" end
    local text = XC.ShoutText(ks)
    if not text then return false, "none" end
    local DC = ns.DungeonChat
    if DC and DC.CutBytes then text = DC.CutBytes(text, DC.MAX_BYTES or 255) end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local chan = XC.ShoutChan()
    if not (send and pcall(send, text, chan)) then return false, "send" end
    XC.shoutKey, XC.shoutT, XC.shoutAt = key, t, t
    XC.thankWant = {}
    for _, k in ipairs(ks) do XC.thankWant[k] = true end
    XC.thankPrev = XC.ThankScan()   -- 喊之前身上有的不算「新加的」
    return true, chan, text
end

-- ---------- ④ 有人给我加了 BUFF → 弹框回谢（点「谢谢他」才私聊）----------
--   只在「喊过 10 分钟内」或「总是回谢」时看；施法者读不到 / 是自己 / 不是玩家 = 不弹；同一个人 5 分钟一次；战斗中攒着、脱战再弹（过期就算了）
local ID2K
local function idMap()
    if ID2K then return ID2K end
    local BA = ns.BuffAsk
    if not (BA and BA.TYPES) then return nil end
    ID2K = {}
    for _, t in ipairs(BA.TYPES) do for _, id in ipairs(t.ids) do ID2K[id] = t.k end end
    return ID2K
end
local function nameK(n)
    local BA = ns.BuffAsk
    if not (BA and BA.TYPES and BA.SpellName) then return nil end
    for _, t in ipairs(BA.TYPES) do
        for _, id in ipairs(t.ids) do if BA.SpellName(id) == n then return t.k end end
    end
end
-- 身上这几类 BUFF：{ [k] = 施法单位 or false }；读不到（秘密值 / 接口不在）= nil
function XC.ThankScan()
    local map = idMap()
    if not map then return nil end
    local out = {}
    for i = 1, 40 do
        local name, id, srcU
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or type(a) ~= "table" then break end
            name, id, srcU = a.name, a.spellId, a.sourceUnit
        elseif UnitBuff then
            local r = { pcall(UnitBuff, "player", i) }
            if not r[1] or r[2] == nil then break end
            name, srcU, id = r[2], r[8], r[11]
        else return nil end
        if secret(id) or secret(name) then return nil end
        if secret(srcU) then srcU = nil end
        local k = (tonumber(id) and map[tonumber(id)]) or (type(name) == "string" and nameK(name)) or nil
        if k and not out[k] then out[k] = (type(srcU) == "string" and srcU ~= "") and srcU or false end
    end
    return out
end
-- 11-23 用户「收到BUFF还是有的时候不弹感谢窗」：原来只有「喊」过才看，要 BUFF 弹框里密人 / 副本里队伍里要（组队信标 BA.ArmThank）不算 → 也挂上
--   askWant[k] = { who = 密的那个人（队伍里要 = 队里能给的那个人）, t }；施法者读不到（路人不在队里、不是目标，sourceUnit 为空）就算他给的
XC.askWant = {}
function XC.ThankArmAsk(who, list)
    if not ns.db or XC.DB().thank == false then return end
    if not XC.ThankArmed() or not XC.thankPrev then XC.thankPrev = XC.ThankScan() end   -- 密之前身上有的不算「新加的」
    local t = now()
    XC.askAt = t
    for _, x in ipairs(list or {}) do
        local k = type(x) == "table" and x.k or x
        if k then XC.askWant[k] = { who = who, t = t } end
    end
end
local function askOf(k)
    local a = XC.askWant[k]
    return a and now() - a.t <= XC.THANK_ARM and a or nil
end
function XC.ThankArmed()
    if not ns.db or XC.DB().thank == false then return false end
    if XC.DB().thankAlways == true then return true end
    if XC.askAt and now() - XC.askAt <= XC.THANK_ARM then return true end
    return (XC.shoutAt and now() - XC.shoutAt <= XC.THANK_ARM) and true or false
end
local function wantK(k)
    if askOf(k) then return true end
    if XC.shoutAt and now() - XC.shoutAt <= XC.THANK_ARM and XC.thankWant and XC.thankWant[k] then return true end
    if XC.DB().thankAlways == true then
        local BA, t = ns.BuffAsk, bk(k)
        return (BA and t and BA.Useful(t, myClass())) and true or false
    end
    return false
end
local function giver(u)
    if not u or u == "player" then return nil end
    local function b(f, ...) if not f then return nil end local ok, v = pcall(f, ...); if ok and not secret(v) then return v end end
    if b(UnitIsUnit, u, "player") or not b(UnitIsPlayer, u) then return nil end
    local DC = ns.DungeonChat
    local who = DC and DC.FullName and DC.FullName(u)
    if type(who) ~= "string" or secret(who) then who = b(UnitName, u) end
    if type(who) ~= "string" or secret(who) or who == "" then return nil end
    return who
end
-- UNIT_AURA（主插件 XpCheck.lua 的事件里调）
function XC.ThankAura()
    if not XC.ThankArmed() then XC.thankPrev = nil; return end
    local cur = XC.ThankScan()
    if not cur then return end
    local prev = XC.thankPrev
    XC.thankPrev = cur
    if not prev then return end
    local by = {}
    for k, u in pairs(cur) do
        if prev[k] == nil and wantK(k) then
            local who = giver(u)
            local a = askOf(k)
            if not who and u == false and a and type(a.who) == "string" then who = a.who end   -- 11-23 读不到施法者：算密的那个人给的
            XC.askWant[k] = nil
            if who then by[who] = by[who] or {}; table.insert(by[who], k) end
        end
    end
    for who, ks in pairs(by) do XC.ThankOffer(who, ks) end
end
XC.thanked = {}
function XC.ThankOffer(who, ks)
    local t = now()
    local last = XC.thanked[who]
    if last and t - last < XC.THANK_GAP then return false, "gap" end
    if InCombatLockdown and InCombatLockdown() then XC.thankPend = { who = who, ks = ks, t = t }; return false, "combat" end
    XC.thanked[who] = t
    XC.ThankShow(who, ks)
    return true
end
function XC.ThankFlush()
    local p = XC.thankPend
    XC.thankPend = nil
    if not p or now() - p.t > XC.THANK_PEND or XC.DB().thank == false then return false end
    return XC.ThankOffer(p.who, p.ks)
end
XC.THANK_TXT = {
    { "谢谢义父的%s~", "Thanks for the %s!" }, { "收到%s啦，谢谢义父！", "Got the %s, thank you!" },
    { "%s收到，多谢义父~", "%s received, much appreciated!" }, { "感谢义父的%s！", "Thank you for the %s!" },
}
function XC.ThankText(ks)
    local p = XC.THANK_TXT[math.random(#XC.THANK_TXT)]
    local t = string.format(ns.ChatL(p[1], p[2]), joinK(ks, true))
    return ns.ApplyCall and ns.ApplyCall(t) or t
end
local function shortName(who) return (tostring(who or ""):gsub("%-.*$", "")) end
function XC.ThankSend()
    local c = XC.thankCur
    if not c then return false end
    XC.ThankHide()
    if not canChat() then ns.Print(L("现在发不了私聊（战斗中 / 聊天受限）", "Can't whisper right now")); return false end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    return (send and pcall(send, XC.ThankText(c.ks), "WHISPER", nil, c.who)) and true or false
end
function XC.ThankHide()
    XC.thankCur = nil
    if XC.thankFrame then XC.thankFrame:Hide() end
end
function XC.ThankNever()
    XC.ThankHide()
    XC.DB().thank = false
    if ns.CloseHint then
        ns.CloseHint("xpThank", L("加 BUFF 回谢框已永久关闭；想找回：设置 →「窗口与提醒」→「加 BUFF 回谢框」，或经验加成设置「补全器」里勾回来",
            "Buff thank-you prompt turned off; turn it back on in Settings > Windows & reminders, or in the XP helper settings"))
    end
end
function XC.ThankShow(who, ks)
    local f = XC.thankFrame
    if not f then
        f = CreateFrame("Frame", "GearInsightForeverXpThank", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(300, 70); f:SetFrameStrata("DIALOG"); f:SetPoint("TOP", UIParent, "TOP", 0, -200)
        f:SetMovable(true); if f.EnableMouse then f:EnableMouse(true) end
        if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        if f.SetBackdrop then
            pcall(f.SetBackdrop, f, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            f:SetBackdropColor(0.05, 0.06, 0.08, 0.95); f:SetBackdropBorderColor(0.25, 0.9, 0.35, 0.8)
        end
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); f.text:SetPoint("TOPLEFT", 10, -10); f.text:SetWidth(280); f.text:SetJustifyH("LEFT")
        local function btn(label, w, x, fn)
            local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            if ns.SkinButton then ns.SkinButton(b) end
            b:SetSize(w, 22); b:SetPoint("BOTTOMLEFT", x, 8); b:SetText(label)
            b:SetScript("OnClick", fn)
            return b
        end
        f.yes = btn(L("谢谢他", "Thank them"), 84, 10, function() XC.ThankSend() end)
        f.no = btn(L("不用", "No"), 64, 100, function() XC.ThankHide() end)
        f.never = btn(L("不再提示", "Never"), 96, 170, function() XC.ThankNever() end)
        f:SetScript("OnUpdate", function(self, el)
            self.age = (self.age or 0) + (el or 0)
            if self.age >= XC.THANK_TTL then XC.ThankHide() end
        end)
        XC.thankFrame = f
    end
    XC.thankCur = { who = who, ks = ks }
    f.text:SetText(string.format(L("%s 给你加了 %s", "%s buffed you: %s"), shortName(who), joinK(ks)))
    f.age = 0
    f:Show()
    return f
end

-- ---------- 检查器里每一项（帐篷 / 营火 / 睡袋 / 食物 / 经验药剂 / 药剂武器油 / 休息经验）的来源 ----------
function XC.Sources(r)
    if r.src then return r.src end
    local sl, k, ok = {}, r.key, r.st == "ok" or r.st == "warn"
    if k == "tent" then
        if ok then src(sl, ICON.tent, L("在帐篷旁休息过", "Rested by a tent"), true, nil, nil, nil, L("帐篷", "Tent"))
        elseif r.near then src(sl, ICON.tent, string.format(L("附近：%s 的帐篷", "%s's tent nearby"), r.near), true,
            function() if ns.Camp and ns.Camp.Offer then ns.Camp.Offer(r.near) end end, L("点了弹「请求进队蹭露营」小框（点了才发）", "Opens the tent invite prompt"), nil, r.near)
        elseif r.st == "info" then src(sl, ICON.wait, r.text, false, nil, nil, nil, L("冷却", "CD"))
        else src(sl, ICON.tent, L("别人的帐篷（鼠标指一下）", "Someone's tent (mouse over it)"), false, nil, L("鼠标指到帐篷，插件弹窗帮你请求进队", "Mouse over a tent to ask for an invite"), nil, L("蹭帐篷", "Tent")) end
    elseif k == "fire" then
        if ok then src(sl, ICON.fire, L("身边有营火", "Campfire nearby"), true, nil, nil, nil, L("营火", "Fire")) end
        local w, f = count(4470), count(4471)
        src(sl, iicon(4471), string.format(L("燧石 %d · 木柴 %d", "Flint %d · wood %d"), f, w), f > 0 and w > 0, nil, L("学了烹饪：自己生火", "With Cooking: light a fire"), nil, L("生火", "Light"))
        vendorSrc(sl, L("杂货商：燧石和火绒 / 普通木柴", "Trade goods: flint / wood"), 4471, 135, nil, L("杂货商", "Vendor"))
    elseif k == "bag" then
        local n = count(211527)
        if ok then src(sl, ICON.inn, L("躺过睡袋", "Rested in a bag"), true, nil, nil, nil, L("睡袋", "Bag")) end
        if n > 0 then bagSrc(sl, 211527, n, r.st == "info" and r.text or L("找个安全地方铺开", "Deploy it somewhere safe"), nil, r.st ~= "info") end
        if r.action then src(sl, ICON.quest, L("睡袋任务线", "Sleeping bag quests"), false, r.action, r.text, nil, L("任务线", "Quests")) end
    elseif k == "food" then
        if ok then src(sl, r.icon or ICON.cook, r.text, true, nil, nil, nil, L("生效", "On")) end
        local have, make = XC.Foods()
        for i = 1, math.min(2, #have) do bagSrc(sl, have[i].item, have[i].n, L("包里有：吃一个", "In your bags - eat one")) end
        if make[1] then src(sl, ICON.cook, L("能做：", "Cook: ") .. iname(make[1].item), #make[1].short == 0, nil, #make[1].short == 0 and L("材料齐了，营火边做", "Mats ready - cook at a fire") or L("还缺材料", "Missing mats"), nil, L("能做", "Cook")) end
        ahSrc(sl, L("经验食物", "XP food"), make[1] and make[1].item or nil)
    elseif k == "boost" or k == "kit" then
        if ok then src(sl, r.icon or XC.ICON[k], r.text, true, nil, nil, nil, L("生效", "On")) end
        if r.use and not r.use.trinket then
            local e = bagSrc(sl, r.use.item, r.use.n or 1, r.use.fx)
            e.text = r.use.name .. " ×" .. (r.use.n or 1)
        elseif r.use then src(sl, iicon(r.use.item), r.use.name, true, nil, r.use.fx, nil, L("坠饰", "Neck")) end
        if k == "kit" and not ok then
            local okK, kit = pcall(XC.Kit, nil, level())
            for _, part in ipairs(okK and { kit.el, kit.wp } or {}) do
                for _, e in pairs(part and part.best or {}) do ahSrc(sl, iname(e.item) .. " " .. XC.KitFx(e), e.item); break end
            end
        end
    elseif k == "rest" then
        src(sl, ICON.inn, L("旅店 / 主城下线攒", "Log out in an inn / city"), resting(), nil, L("在旅店 / 主城 / 睡袋里下线", "Log out in an inn, city or sleeping bag"), nil, L("旅店", "Inn"))
    end
    r.src = order(sl)
    return r.src
end

-- ---------- 设置（本子插件加载后登记；经验加成页「每项开关」/ 设置页索引里都能找到）----------
--   合计显示 total / 出发前清单 prep / 职业 BUFF + 物资各类开关（存 xpcheck.items，和检查器各项同一张表）。放子插件里省主插件登录内存
XC.SUP_KEYS = { "cbuff", "sfood", "ammo", "reagent", "potion", "repair", "space" }
XC.SUP_NAMES = { cbuff = { "职业BUFF", "Class buffs" }, sfood = { "吃喝", "Food/drink" }, ammo = { "弹药", "Ammo" }, reagent = { "施法材料", "Reagents" },
    potion = { "绷带/药水", "Bandage/potion" }, repair = { "修理", "Repair" }, space = { "背包空格", "Bag space" } }
if ns.RegisterSettings then
    local items = {
        { type = "check", id = "xp.total", text = function() return L("显示经验加成合计（页顶 / 提醒条 / 聊天框：经验 +N%，悬停看每项）", "Show the XP bonus total (page / bar / chat; hover for each source)") end,
          get = function() return XC.DB().total ~= false end, set = function(v) XC.Set("total", v) end },
        { type = "check", id = "xp.prep", text = function() return L("进主城 / 旅店时弹「出发前清单」（离开自动收起，回来再弹）", "Show the departure checklist in towns / inns (closes when you leave)") end,
          get = function() return XC.DB().prep ~= false end, set = function(v) XC.DB().prep = v and true or false end },
        { type = "label", id = "xp.supLabel", w = 60, text = function() return L("补全：", "Also:") end },
    }
    for i, k in ipairs(XC.SUP_KEYS) do
        items[#items + 1] = { type = "check", inline = i ~= 5 or nil, indent = (i == 5) and 60 or nil, id = "xp.sup." .. k, step = function() return ns.zh and 104 or 120 end,
            text = function() local t = XC.SUP_NAMES[k]; return L(t[1], t[2]) end,
            get = function() return XC.ItemOn(k) end, set = function(v) XC.SetItem(k, v) end }
    end
    -- 11-17 用户截图四条（默认都开；回谢默认只在喊过 BUFF 之后 10 分钟内）
    local function chk(id, key, cn, en, indent)
        items[#items + 1] = { type = "check", id = id, indent = indent, text = function() return L(cn, en) end,
            get = function() return opt2(key) end, set = function(v) if v then XC.DB()[key] = nil else XC.DB()[key] = false end; if XC.Prep and XC.Prep.Refresh then XC.Prep.Refresh() end end }
    end
    chk("xp.cbDim", "cbDim", "职业 BUFF：身上已有的图标变暗，缺的保持亮", "Class buffs: dim the ones you already have")
    chk("xp.srcNav", "srcNav", "商人来源（弓箭商 / 旅店 / 杂货商…）：点一下插旗导航到最近的", "Vendor sources: click to set a waypoint to the nearest one")
    chk("xp.bagHave", "bagHave", "包里已有的物品：图标变暗、不算「没备好」；点物品图标搜拍卖行", "Items in your bags: dimmed, not counted as missing; click an item icon to search the AH")
    chk("xp.shoutBtn", "shoutBtn", "职业 BUFF 行显示「喊」按钮（点了在 /说 或 /大喊 求 BUFF，带位置；右键「喊」选频道；副本里发队伍）", "Show the \"Ask\" button on the class buff row (Say or Yell with your location; right-click it to pick)")
    chk("xp.thank", "thank", "有人给我加 BUFF 时弹框回谢（点「谢谢他」才私聊；默认只在喊过之后 10 分钟内）", "When someone buffs you, offer to thank them (default: only within 10 min of asking)")
    items[#items + 1] = { type = "check", id = "xp.thankAlways", indent = 18, text = function() return L("总是回谢（不喊也弹）", "Always (even without asking)") end,
        get = function() return XC.DB().thankAlways == true end, set = function(v) XC.DB().thankAlways = v and true or nil end }
    ns.RegisterSettings({ key = "xpmore", order = 70.5, page = "xp", avail = function() return ns.XpCheck ~= nil end,
        title = function() return L("练级补全器（合计 / 出发前清单 / 职业 BUFF / 物资）", "Leveling helper (total / checklist / class buffs / supplies)") end,
        short = function() return L("补全器", "Helper") end, items = items })
end
