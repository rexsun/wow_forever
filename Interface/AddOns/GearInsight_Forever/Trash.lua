-- 物品快速摧毁助手「清背包」（11-14 用户「做一个物品快速摧毁助手，可以拍物品价值最低的从低到高，一键摧毁」）
--   ① 「装备」大类里的「清背包」页（key = trash，UI.lua grp_gear 的 members）：
--        扫背包 0 ~ NUM_BAG_SLOTS（C_Container.* 优先，退回旧 GetContainerItemInfo 等；钥匙链 -2 不扫，身上穿的不扫 → 已装备的天然不在列表里）
--        价值 = 单价 × 堆叠数；单价：ns.Prices（Prices.lua，HOLD，不在包里时跳过）的拍卖行扫描价 → 玩家手填价 → GetItemInfo 的商人回收价
--        从低到高排：单价 0（卖不了钱）最前，再按总价、品质、名字、格子；物品信息还没缓存的排最后（「读取中」，不能点）
--        每行：图标（悬停 = 游戏自带的物品提示；Shift + 点 = 发链接）、名字（品质色）、数量、单价、总价、价格来源、「摧毁」按钮；右键一行 = 加入不摧毁名单
--        顶部大按钮「摧毁最便宜的：<物品> ×N（价值 X）」= 摧毁列表第一项，摧毁后列表刷新、第一项换成下一件
--   ② 默认不列出（页脚写「已隐藏 N 件：…」）：
--        任务物品（classID 12 / 背包接口报的任务物品）、炉石、专业 / 职业工具（剥皮刀、矿工锄、铁匠锤、扳手、附魔棒、鱼竿、潜行者工具、萨满图腾…）、
--        背包 / 箭袋（classID 1 / 11）、钥匙（13）、施法材料（5：传送符文 / 神圣蜡烛…单价低，一键很容易误删）、弹药（6：猎人的箭和子弹）、
--        坐骑 / 宠物（15 下的 5 / 2）、卖不了钱的蓝色以上（多半是坐骑 / 特殊物品）、
--        灵魂碎片（定：排除。术士的资源，卖不了钱、会排在最前面，一键就没了；多余的术士自己在背包里删）、
--        魔法造物（水 / 面包 / 法力宝石 / 治疗石 / 灵魂石 / 火焰石 / 法术石，设置可改成列出）、紫色及以上（设置可打开）、不摧毁名单里的
--        不摧毁名单：右键一行加入，存 ns.db.trash.keep[物品 ID]；设置里「清空」、/gi 摧毁 清空名单
--   ③ 安全：
--        · 只在按钮的 OnClick（硬件事件）里调 PickupContainerItem + DeleteCursorItem；斜杠命令 / 事件 / 计时器里一律不摧毁。一次点击只摧毁一格
--        · 点之前重读那一格：物品 / 数量变了 → 不动，刷新列表让玩家再看一眼；格子锁着（交易 / 邮寄中）→ 不动
--        · ClearCursor → 拿起 → 核对光标上的物品 ID 和列表一致，不一致 → ClearCursor 放回原格并报错，什么都不删
--        · 绿色（优秀）及以上：第一次点只把按钮变成「再点一次确认」，3 秒内再点同一件才摧毁；白色 / 灰色直接摧毁
--        · 战斗中按钮全灰、点了也只提示
--        · 「输入 DELETE」确认框：经典客户端 FrameXML 里那个框（StaticPopup DELETE_GOOD_ITEM，蓝色及以上要打字）是把物品拖到世界里时
--          由 DELETE_ITEM_CONFIRM 事件弹出的，确认后才调 DeleteCursorItem；DeleteCursorItem 本身不弹框（wiki：确认是默认界面做的）。
--          正式服 9.x 起它要求硬件事件、每次硬件事件只删一件 —— 我们本来就是一次点击一格。无限客户端是新引擎，没实测过：
--          调完光标上还拿着那件 → 等 0.3 秒：期间弹了确认框（DELETE_ITEM_CONFIRM / StaticPopup 可见）→ 不替玩家填字、不替他点，
--          聊天框提示「请在游戏的确认框里自己确认」；没弹框也没删掉 → ClearCursor 放回原格并报错
--   ④ 背包满提示：BAG_UPDATE（合并 0.3 秒）/ BAG_UPDATE_DELAYED 后普通背包空格 = 0 → 聊天框提示一次（每次登录最多一次；登录后 5 秒才开始看），
--        设置「背包满时提示」可关（存 ns.db.trash.fullTip，nil = 开）
--   ⑤ 设置（ns.RegisterSettings，本页右上角「本页设置」+ 设置页索引）：背包满提示 · 列出紫色 · 不列魔法造物 · 清空不摧毁名单
--        存 ns.db.trash = { keep = {}, fullTip / epic / skipConj（nil = 默认：开 / 关 / 开）}
--   ⑥ 命令：/gi 摧毁 | /gi trash 打开本页；/gi 摧毁 清空名单 | 提示开 | 提示关
--   本文件在主插件 HOLD 里：不加载时没有这页 / 不提示 / 没有命令，UI.lua 装备大类成员里的 "trash" 没有对应页 → 不出，其余照旧
local _, ns = ...
local L = function(cn, en) return ns.L(cn, en) end

local T = { gone = {}, list = {}, hidden = {}, offset = 0 }
ns.Trash = T
T.CONFIRM_SEC = 3     -- 绿色及以上：3 秒内再点才摧毁
T.MAX_ROWS = 13
T.GONE_SEC = 3        -- 刚摧毁的格子：背包事件还没到时别再列出来
T.WAIT_SEC = 0.3      -- DeleteCursorItem 后光标上还拿着 → 等这么久看有没有弹确认框
T.LOGIN_DELAY = 5     -- 登录后几秒才开始看背包满

T.HEARTH = { [6948] = true }
T.SOUL_SHARD = 6265
-- 专业 / 职业工具（放包里才生效的那种）
T.TOOLS = {
    [7005] = true,   -- 剥皮小刀
    [2901] = true,   -- 矿工锄
    [5956] = true,   -- 铁匠锤
    [6219] = true,   -- 扳手
    [10498] = true,  -- 侏儒微调器
    [9149] = true,   -- 点金石
    [5060] = true,   -- 潜行者工具
    [6218] = true, [6339] = true, [11130] = true, [11145] = true, [16207] = true,   -- 符文铜棒 / 银棒 / 金棒 / 真银棒 / 奥金棒
    [6256] = true, [6365] = true, [6366] = true, [6367] = true, [12225] = true, [19022] = true, [19970] = true,   -- 鱼竿
    [5175] = true, [5176] = true, [5177] = true, [5178] = true,   -- 萨满 大地 / 火焰 / 水 / 空气图腾
}
-- 魔法造物（法师水 / 面包 / 法力宝石，术士治疗石 / 灵魂石 / 火焰石 / 法术石）
T.CONJURED = {}
for _, id in ipairs({
    5350, 2288, 2136, 3772, 8077, 8078, 8079, 231778,          -- 水（同 MageConjure.lua MC.WATER）
    5349, 1113, 1114, 1487, 8075, 8076, 22895,                 -- 面包（同 MC.FOOD）
    5514, 5513, 8007, 8008,                                    -- 法力宝石
    5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009, 5510, 19010, 19011, 9421, 19012, 19013,   -- 治疗石
    5232, 16892, 16893, 16895, 16896,                          -- 灵魂石
    1254, 13699, 13700, 13701, 5522, 13602, 13603,             -- 火焰石 / 法术石
}) do T.CONJURED[id] = true end

T.QHEX = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000", [6] = "e6cc80", [7] = "00ccff" }
T.POPUPS = { "DELETE_ITEM", "DELETE_GOOD_ITEM", "DELETE_QUEST_ITEM", "DELETE_GOOD_QUEST_ITEM" }

-- ---------- 小工具 ----------
local function now() return (GetTime and GetTime()) or 0 end
local function clean(v)
    if v == nil or (ns.Secret and ns.Secret(v)) then return nil end
    return v
end
local function pass(ok, ...) if ok then return ... end return nil end
local function call(f, ...)
    if type(f) ~= "function" then return nil end
    return pass(pcall(f, ...))
end
local function combat() return InCombatLockdown and InCombatLockdown() and true or false end
T.Combat = combat
local function after(sec, fn)
    if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end
end
local function rg(t, k) return type(t) == "table" and rawget(t, k) or nil end

function T.Money(c)
    c = math.floor((tonumber(c) or 0) + 0.5)
    if ns.Prices and ns.Prices.Money then return ns.Prices.Money(c) end
    local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    if g > 0 then return g .. L("金", "g") .. (s > 0 and (" " .. s .. L("银", "s")) or "") end
    if s > 0 then return s .. L("银", "s") .. (k > 0 and (" " .. k .. L("铜", "c")) or "") end
    return k .. L("铜", "c")
end
function T.Colored(e)
    local hex = T.QHEX[e.q or 1] or "ffffff"
    return "|cff" .. hex .. (e.name or ("#" .. tostring(e.id))) .. "|r"
end
function T.ValueText(v)
    if v == nil then return L("读取中", "loading") end
    if v <= 0 then return L("卖不了钱", "no value") end
    return T.Money(v)
end
function T.SourceText(src)
    if src == "a" then return L("拍卖价", "Auction") end
    if src == "m" then return L("手填价", "Manual") end
    if src == "v" then return L("商人价", "Vendor") end
    if src == "none" then return "-" end
    return "?"
end

-- ---------- 设置（ns.db.trash；nil = 默认值）----------
T.DEFAULTS = { fullTip = true, epic = false, skipConj = true }
function T.DB()
    ns.db.trash = ns.db.trash or {}
    local d = ns.db.trash
    if type(d.keep) ~= "table" then d.keep = {} end
    return d
end
function T.Opt(k)
    if not ns.db then return T.DEFAULTS[k] end
    local v = rawget(T.DB(), k)
    if v == nil then return T.DEFAULTS[k] end
    return v
end
function T.SetOpt(k, v)
    if not ns.db then return end
    v = v and true or false
    if v == T.DEFAULTS[k] then T.DB()[k] = nil else T.DB()[k] = v end
    if T.PageShown() then T.Refresh() end
end
function T.IsKept(id) return ns.db ~= nil and id ~= nil and T.DB().keep[id] == true end
function T.AddKeep(id) if ns.db and id then T.DB().keep[id] = true end end
function T.RemoveKeep(id) if ns.db and id then T.DB().keep[id] = nil end end
function T.KeepCount()
    if not ns.db then return 0 end
    local n = 0
    for _ in pairs(T.DB().keep) do n = n + 1 end
    return n
end
function T.ClearKeep()
    if not ns.db then return 0 end
    local n = T.KeepCount()
    T.DB().keep = {}
    if T.PageShown() then T.Refresh() end
    return n
end

-- ---------- 背包接口（C_Container 优先，退回旧全局函数）----------
local function cc(name)
    local C = rawget(_G, "C_Container")
    local f = type(C) == "table" and C[name] or nil
    if type(f) == "function" then return f end
    return nil
end
function T.NumBags() return tonumber(NUM_BAG_SLOTS) or 4 end
function T.NumSlots(bag)
    return tonumber(call(cc("GetContainerNumSlots") or GetContainerNumSlots, bag)) or 0
end
-- 一格的物品：{ id, count, locked, q, link, icon, noValue } / nil = 空格
function T.SlotInfo(bag, slot)
    local f = cc("GetContainerItemInfo")
    if f then
        local i = call(f, bag, slot)
        if type(i) ~= "table" then return nil end
        local id = tonumber(clean(i.itemID))
        if not id then return nil end
        return { id = id, count = tonumber(clean(i.stackCount)) or 1, locked = clean(i.isLocked) and true or false,
            q = tonumber(clean(i.quality)), link = clean(i.hyperlink), icon = clean(i.iconFileID), noValue = clean(i.hasNoValue) and true or false }
    end
    if not GetContainerItemInfo then return nil end
    local icon, count, locked, q, _, _, link, _, noValue, id = call(GetContainerItemInfo, bag, slot)
    link = clean(link)
    id = tonumber(clean(id)) or (type(link) == "string" and tonumber(link:match("item:(%d+)"))) or nil
    if not id then return nil end
    return { id = id, count = tonumber(clean(count)) or 1, locked = clean(locked) and true or false, q = tonumber(clean(q)),
        link = link, icon = clean(icon), noValue = clean(noValue) and true or false }
end
function T.IsQuestSlot(bag, slot)
    local f = cc("GetContainerItemQuestInfo")
    if f then
        local q = call(f, bag, slot)
        if type(q) == "table" then return (clean(q.isQuestItem) or clean(q.questID)) and true or false end
        return false
    end
    if GetContainerItemQuestInfo then
        local isQ, qid = call(GetContainerItemQuestInfo, bag, slot)
        return (clean(isQ) or clean(qid)) and true or false
    end
    return false
end
-- 普通背包（专业包 / 箭袋不算）的空格数、总格数
function T.FreeSlots()
    local free, total = 0, 0
    local f = cc("GetContainerNumFreeSlots") or GetContainerNumFreeSlots
    for bag = 0, T.NumBags() do
        local n = T.NumSlots(bag)
        if n > 0 then
            local nf, fam = call(f, bag)
            fam = tonumber(fam) or 0
            if fam == 0 then
                total = total + n
                free = free + (tonumber(nf) or 0)
            end
        end
    end
    return free, total
end
local function pickup(bag, slot) return call(cc("PickupContainerItem") or PickupContainerItem, bag, slot) end
local function cursorItem()
    local kind, id = call(GetCursorInfo)
    if clean(kind) ~= "item" then return nil end
    return tonumber(clean(id))
end
T.CursorItem = cursorItem

-- 物品信息：{ known, name, link, q, icon, sell, classID, subID }
function T.ItemInfo(id)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, link, q, _, _, _, _, _, _, icon, sell, classID, subID = call(f, id)
    name = clean(name)
    if not name then
        local gi = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        local _, _, _, _, icon2, cls2, sub2 = call(gi, id)
        if C_Item and C_Item.RequestLoadItemDataByID then call(C_Item.RequestLoadItemDataByID, id) end
        return { known = false, icon = clean(icon2), classID = tonumber(clean(cls2)), subID = tonumber(clean(sub2)) }
    end
    return { known = true, name = name, link = clean(link), q = tonumber(clean(q)), icon = clean(icon), sell = tonumber(clean(sell)) or 0,
        classID = tonumber(clean(classID)), subID = tonumber(clean(subID)) }
end

-- 单价：拍卖行扫描价 → 手填价 → 商人回收价；返回 价（铜，nil = 还不知道）, 来源（"a" / "m" / "v" / "none"）
function T.UnitPrice(id, sell)
    local P = ns.Prices
    if P and P.Get then
        local p = tonumber((call(P.Get, id, "scan")))
        if p and p > 0 then return p, "a" end
        p = tonumber((call(P.Get, id, "manual")))
        if p and p > 0 then return p, "m" end
    end
    if sell == nil then return nil, "?" end
    sell = tonumber(sell) or 0
    if sell > 0 then return sell, "v" end
    return 0, "none"
end

-- ---------- 排除规则 ----------
T.REASONS = { "keep", "quest", "hearth", "tool", "shard", "conj", "epic", "special", "mount", "bag", "key", "reagent", "ammo", "locked" }
T.REASON_TEXT = {
    keep = { "不摧毁名单", "keep list" }, quest = { "任务物品", "quest" }, hearth = { "炉石", "hearthstone" },
    tool = { "专业 / 职业工具", "tools" }, shard = { "灵魂碎片", "soul shards" }, conj = { "魔法造物", "conjured" },
    epic = { "紫色及以上", "epic+" }, special = { "卖不了钱的蓝色以上", "unsellable rare+" }, mount = { "坐骑 / 宠物", "mounts / pets" },
    bag = { "背包 / 箭袋", "bags / quivers" }, key = { "钥匙", "keys" }, reagent = { "施法材料", "reagents" }, ammo = { "弹药", "ammo" },
    locked = { "锁定中", "locked" },
}
function T.ReasonText(k)
    local t = T.REASON_TEXT[k]
    return t and L(t[1], t[2]) or k
end
-- e = { id, q, classID, subID, quest, known, unit, locked }；返回不列出的原因 / nil = 列出
function T.SkipReason(e)
    if T.IsKept(e.id) then return "keep" end
    if e.quest or e.classID == 12 then return "quest" end
    if T.HEARTH[e.id] then return "hearth" end
    if T.TOOLS[e.id] then return "tool" end
    if e.id == T.SOUL_SHARD then return "shard" end
    if e.classID == 1 or e.classID == 11 then return "bag" end
    if e.classID == 13 then return "key" end
    if e.classID == 5 then return "reagent" end
    if e.classID == 6 then return "ammo" end
    if e.classID == 15 and (e.subID == 2 or e.subID == 5) then return "mount" end
    if T.CONJURED[e.id] and T.Opt("skipConj") then return "conj" end
    local q = e.q or 1
    if q >= 4 and not T.Opt("epic") then return "epic" end
    if q >= 3 and e.unit == 0 then return "special" end
    if e.locked then return "locked" end
    return nil
end

-- ---------- 扫描 / 排序 ----------
function T.Less(a, b)
    local ak, bk = a.unit ~= nil, b.unit ~= nil
    if ak ~= bk then return ak end                       -- 读取中的排最后
    local at, bt = a.total or 0, b.total or 0
    if at ~= bt then return at < bt end                  -- 0（卖不了钱）自然最前
    if (a.q or 1) ~= (b.q or 1) then return (a.q or 1) < (b.q or 1) end
    if (a.name or "") ~= (b.name or "") then return (a.name or "") < (b.name or "") end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end
function T.Scan()
    local list, hidden = {}, {}
    local t = now()
    for bag = 0, T.NumBags() do
        for slot = 1, T.NumSlots(bag) do
            local s = T.SlotInfo(bag, slot)
            local g = T.gone[bag .. ":" .. slot]
            if s and g and g.id == s.id and t - g.t < T.GONE_SEC then
                s = nil   -- 刚摧毁的，背包事件还没到
            end
            if s then
                local info = T.ItemInfo(s.id)
                local q = s.q
                if not q or q < 0 then q = info.q end
                local e = { bag = bag, slot = slot, id = s.id, count = s.count or 1, locked = s.locked, link = s.link or info.link,
                    name = info.name or (type(s.link) == "string" and s.link:match("%[(.-)%]")) or nil, q = q, icon = s.icon or info.icon, classID = info.classID, subID = info.subID, known = info.known,
                    quest = T.IsQuestSlot(bag, slot) }
                local sell = nil
                if info.known then sell = s.noValue and 0 or (info.sell or 0) end
                e.unit, e.src = T.UnitPrice(s.id, sell)
                e.total = e.unit and (e.unit * e.count) or nil
                local why = T.SkipReason(e)
                if why then hidden[why] = (hidden[why] or 0) + 1 else list[#list + 1] = e end
            end
        end
    end
    table.sort(list, T.Less)
    T.list, T.hidden = list, hidden
    return list, hidden
end
-- 列表第一项（能点的）
function T.Top()
    local e = T.list[1]
    if e and e.unit ~= nil then return e end
    return nil
end
function T.HiddenText()
    local parts, n = {}, 0
    for _, k in ipairs(T.REASONS) do
        local c = T.hidden[k]
        if c and c > 0 then n = n + c; parts[#parts + 1] = T.ReasonText(k) .. " " .. c end
    end
    if n == 0 then return "" end
    return string.format(L("已隐藏 %d 件：", "%d hidden: "), n) .. table.concat(parts, L("、", ", "))
end

-- ---------- 摧毁（⛔ 只许从按钮的 OnClick 里调：PickupContainerItem / DeleteCursorItem 要硬件事件）----------
local function key(e) return e.bag .. ":" .. e.slot .. ":" .. e.id end
T.Key = key
function T.NeedConfirm(e) return (e.q or 1) >= 2 end
function T.Confirming(e) return e ~= nil and T.confirm ~= nil and T.confirm.key == key(e) and now() - T.confirm.t <= T.CONFIRM_SEC end
function T.PopupShown()
    if not StaticPopup_Visible then return false end
    for _, n in ipairs(T.POPUPS) do
        if call(StaticPopup_Visible, n) then return true end
    end
    return false
end
local function itemText(e)
    return (e.link or T.Colored(e)) .. ((e.count or 1) > 1 and (" ×" .. e.count) or "")
end
function T.Done(e)
    T.gone[e.bag .. ":" .. e.slot] = { id = e.id, t = now() }
    ns.Print(string.format(L("已摧毁 %s（价值 %s）", "Destroyed %s (worth %s)"), itemText(e), T.ValueText(e.total)))
    T.Refresh()
end
-- 返回 true / false, 原因（combat / busy / none / changed / locked / confirm / mismatch / wait）
function T.Destroy(e)
    if combat() then
        ns.Print(L("战斗中不能摧毁物品，脱战再来", "Can't destroy items in combat"))
        return false, "combat"
    end
    if T.busy then return false, "busy" end
    if not e or e.unit == nil then return false, "none" end
    local s = T.SlotInfo(e.bag, e.slot)
    if not s or s.id ~= e.id or (s.count or 1) ~= (e.count or 1) then
        ns.Print(L("背包变了，列表已刷新，再看一眼再点", "Your bags changed - list refreshed, check again"))
        T.confirm = nil
        T.Refresh()
        return false, "changed"
    end
    if s.locked then
        ns.Print(L("这格物品锁着（交易 / 邮寄中？），先放好再来", "That item is locked (trade / mail?)"))
        return false, "locked"
    end
    if T.NeedConfirm(e) and not T.Confirming(e) then
        T.confirm = { key = key(e), t = now() }
        T.RefreshUI()
        local k = key(e)
        after(T.CONFIRM_SEC + 0.05, function()
            if T.confirm and T.confirm.key == k and now() - T.confirm.t >= T.CONFIRM_SEC then T.confirm = nil; T.RefreshUI() end
        end)
        return false, "confirm"
    end
    T.confirm = nil
    if ClearCursor then ClearCursor() end
    pickup(e.bag, e.slot)
    if cursorItem() ~= e.id then
        if ClearCursor then ClearCursor() end   -- 放回原格
        ns.Print("|cffff6060" .. string.format(L("光标上拿到的不是 %s，已放回，什么都没删", "The cursor didn't pick up %s - put back, nothing destroyed"), T.Colored(e)) .. "|r")
        T.Refresh()
        return false, "mismatch"
    end
    T.deleting, T.sawPrompt = e, nil
    call(DeleteCursorItem)
    if cursorItem() == e.id then
        T.busy = true
        after(T.WAIT_SEC, function() T.busy = false; pcall(T.AfterTry, e) end)
        return false, "wait"
    end
    T.deleting = nil
    T.Done(e)
    return true
end
-- DeleteCursorItem 后光标上还拿着：弹了确认框 → 让玩家自己确认；没弹 → 放回报错
function T.AfterTry(e)
    T.deleting = nil
    if cursorItem() ~= e.id then
        local s = T.SlotInfo(e.bag, e.slot)
        if s and s.id == e.id and not s.locked then T.Refresh(); return "back" end
        T.Done(e)
        return "done"
    end
    if T.sawPrompt or T.PopupShown() then
        ns.Print(L("游戏弹出了删除确认框（蓝色及以上要输入 DELETE）：请在框里自己确认；不想删就点取消。插件不替你填字、不替你点",
            "The game asks you to confirm (type DELETE for rare+): confirm it yourself, or cancel. The addon never fills it in for you"))
        return "prompt"
    end
    if ClearCursor then ClearCursor() end
    ns.Print("|cffff6060" .. string.format(L("没能摧毁 %s（游戏没接受），已放回原格", "Couldn't destroy %s (rejected by the game) - put back"), T.Colored(e)) .. "|r")
    T.Refresh()
    return "failed"
end
function T.ClickTop() return T.Destroy(T.Top()) end
function T.KeepEntry(e)
    if not e then return end
    T.AddKeep(e.id)
    ns.Print(string.format(L("已把 %s 加入不摧毁名单，以后不列出（本页设置里可清空）", "%s added to the keep list (clear it in page settings)"), T.Colored(e)))
    T.Refresh()
end

-- ---------- 背包满提示 ----------
function T.CheckFull()
    if T.tipped or not T.ready or not ns.db or not T.Opt("fullTip") then return false end
    local free, total = T.FreeSlots()
    if total == 0 or free > 0 then return false end
    T.tipped = true
    T.Scan()
    local top = T.Top()
    local s = L("背包满了：/gi 摧毁 打开「装备 → 清背包」，按价值从低到高一键摧毁", "Bags full: /gi trash opens Gear > Bag cleanup, cheapest first, one click to destroy")
    if top then s = s .. string.format(L("（现在最便宜的是 %s，价值 %s）", " (cheapest now: %s, worth %s)"), itemText(top), T.ValueText(top.total)) end
    ns.Print(s .. L("。每次登录最多提示一次，/gi 摧毁 提示关", ". Once per login; /gi trash tipoff"))
    return true
end
function T.OnBags()
    pcall(T.CheckFull)
    if T.PageShown() then T.Refresh() end
end

-- ================= 「清背包」页 =================
local ROW_H = 24
local function fs(p, font, x, y, w, justify)
    local t = p:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    t:SetPoint("TOPLEFT", x, y)
    if w then t:SetWidth(w) end
    t:SetJustifyH(justify or "LEFT")
    if t.SetWordWrap then t:SetWordWrap(false) end
    return t
end
function T.ShowTip(owner, e)
    if not e then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local ok = pcall(GameTooltip.SetBagItem, GameTooltip, e.bag, e.slot)
    if not ok and e.link then pcall(GameTooltip.SetHyperlink, GameTooltip, e.link) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(string.format(L("单价 %s（%s）· 总价 %s", "Unit %s (%s) · total %s"), T.ValueText(e.unit), T.SourceText(e.src), T.ValueText(e.total)), 1, 0.82, 0)
    GameTooltip:AddLine(L("右键：加入不摧毁名单", "Right-click: add to keep list"), 0.7, 0.7, 0.7)
    GameTooltip:Show()
end
local function plainBtn(parent, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    if ns.SkinButton then ns.SkinButton(b) end
    return b
end
function T.BuildPage(p)
    T.page = p
    local y = ns.PageHeader(p, L("清背包", "Bag cleanup"), L("按价值从低到高排，一键摧毁最不值钱的", "Cheapest first - destroy junk in one click"))
    p.top = plainBtn(p, 500, 30)
    p.top:SetPoint("TOPLEFT", 12, y)
    p.top:SetScript("OnClick", function() T.ClickTop() end)
    p.top:SetScript("OnEnter", function(self) T.ShowTip(self, T.Top()) end)
    p.top:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.sum = fs(p, "GameFontHighlightSmall", 522, y - 8, 140)
    y = y - 38
    p.hd = {}
    for _, c in ipairs({ { L("物品", "Item"), 40, 240 }, { L("数量", "Qty"), 290, 50, "RIGHT" }, { L("单价", "Unit"), 345, 85, "RIGHT" },
        { L("总价", "Total"), 435, 90, "RIGHT" }, { L("来源", "Source"), 532, 60 } }) do
        local h = fs(p, "GameFontNormalSmall", c[2] + 12, y, c[3], c[4]); h:SetText(c[1]); p.hd[#p.hd + 1] = h
    end
    y = y - 16
    p.rows = {}
    for i = 1, T.MAX_ROWS do
        local ry = y - (i - 1) * ROW_H
        local r = CreateFrame("Button", nil, p)
        r:SetSize(646, ROW_H - 2); r:SetPoint("TOPLEFT", 12, ry)
        if r.RegisterForClicks then r:RegisterForClicks("RightButtonUp") end
        r:SetScript("OnClick", function(self, btn) if btn == "RightButton" then T.KeepEntry(rg(self, "e")) end end)
        local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
        r.icon = CreateFrame("Button", nil, r)
        r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT", 2, 0)
        r.icon.tex = r.icon:CreateTexture(nil, "ARTWORK"); r.icon.tex:SetAllPoints()
        if r.icon.RegisterForClicks then r.icon:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
        r.icon:SetScript("OnEnter", function(self) T.ShowTip(self, rg(r, "e")) end)
        r.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.icon:SetScript("OnClick", function(_, btn)
            local e = rg(r, "e")
            if not e then return end
            if btn == "RightButton" then T.KeepEntry(e)
            elseif IsShiftKeyDown and IsShiftKeyDown() and e.link and ChatEdit_InsertLink then ChatEdit_InsertLink(e.link) end
        end)
        r.name = fs(r, "GameFontHighlight", 28, -4, 255)
        r.count = fs(r, "GameFontHighlight", 290, -4, 50, "RIGHT")
        r.unit = fs(r, "GameFontHighlightSmall", 345, -5, 85, "RIGHT")
        r.total = fs(r, "GameFontHighlightSmall", 435, -5, 90, "RIGHT")
        r.src = fs(r, "GameFontDisableSmall", 532, -5, 60)
        r.del = plainBtn(r, 52, 20); r.del:SetPoint("RIGHT", -2, 0)
        r.del:SetScript("OnClick", function() T.Destroy(rg(r, "e")) end)
        p.rows[i] = r
    end
    p.empty = fs(p, "GameFontDisable", 12, y - 8, 640)
    p.more = fs(p, "GameFontDisableSmall", 12, y - T.MAX_ROWS * ROW_H - 2, 640)
    p.hid = fs(p, "GameFontDisableSmall", 12, y - T.MAX_ROWS * ROW_H - 18, 640)
    if p.EnableMouseWheel then p:EnableMouseWheel(true) end
    p:SetScript("OnMouseWheel", function(_, d) T.Scroll(-(tonumber(d) or 0) * 3) end)
    p.note = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.note:SetPoint("BOTTOMLEFT", 12, 4); p.note:SetWidth(640); p.note:SetJustifyH("LEFT")
    p.note:SetText(L("右键一行 = 加入不摧毁名单（本页设置可清空）· 绿色及以上 3 秒内点两下才摧毁 · 一次只摧毁一格 · 战斗中不能用",
        "Right-click a row = keep list (clear in page settings) · green+ needs a second click within 3s · one slot per click · disabled in combat"))
    T.Refresh()
end
function T.Scroll(d)
    local maxOff = math.max(0, #T.list - T.MAX_ROWS)
    T.offset = math.min(maxOff, math.max(0, (T.offset or 0) + (tonumber(d) or 0)))
    T.RefreshUI()
end
function T.PageShown() return T.page ~= nil and T.page:IsVisible() and true or false end
function T.TopText()
    if combat() then return L("战斗中不能摧毁", "Disabled in combat") end
    local e = T.Top()
    if not e then return L("背包里没有可以摧毁的东西", "Nothing to destroy") end
    if T.Confirming(e) then return string.format(L("再点一次确认摧毁：%s", "Click again to destroy: %s"), itemText(e)) end
    return string.format(L("摧毁最便宜的：%s（价值 %s）", "Destroy cheapest: %s (worth %s)"), T.Colored(e) .. ((e.count or 1) > 1 and (" ×" .. e.count) or ""), T.ValueText(e.total))
end
function T.RefreshUI()
    local p = T.page
    if not p or not rg(p, "rows") then return end
    local fight = combat()
    local top = T.Top()
    p.top:SetText(T.TopText())
    if p.top.SetEnabled then p.top:SetEnabled(top ~= nil and not fight) end
    local free, total = T.FreeSlots()
    p.sum:SetText(string.format(L("背包空格 %d / %d", "Free %d / %d"), free, total))
    local maxOff = math.max(0, #T.list - T.MAX_ROWS)
    if (T.offset or 0) > maxOff then T.offset = maxOff end
    for i, r in ipairs(p.rows) do
        local e = T.list[(T.offset or 0) + i]
        r.e = e
        if e then
            r:Show()
            r.icon.tex:SetTexture(e.icon)
            r.name:SetText(T.Colored(e))
            r.count:SetText(tostring(e.count or 1))
            r.unit:SetText(T.ValueText(e.unit))
            r.total:SetText(T.ValueText(e.total))
            r.src:SetText(T.SourceText(e.src))
            r.del:SetText(T.Confirming(e) and L("确认？", "Sure?") or L("摧毁", "Destroy"))
            if r.del.SetEnabled then r.del:SetEnabled(e.unit ~= nil and not fight) end
        else
            r:Hide()
        end
    end
    if #T.list == 0 then
        p.empty:SetText(L("背包里没有可以摧毁的东西（任务物品 / 炉石 / 工具等默认不列出）", "Nothing to destroy (quest items / hearthstone / tools are never listed)"))
        p.empty:Show()
    else p.empty:Hide() end
    local extra = #T.list - T.MAX_ROWS
    p.more:SetText(extra > 0 and string.format(L("共 %d 件，显示第 %d-%d 件（滚轮翻看）", "%d items, showing %d-%d (scroll)"), #T.list, (T.offset or 0) + 1, math.min(#T.list, (T.offset or 0) + T.MAX_ROWS)) or "")
    p.hid:SetText(T.HiddenText())
end
function T.Refresh()
    T.Scan()
    T.RefreshUI()
end
function T.Open()
    if ns.ToggleMain then
        local f = _G.GearInsightForeverMain
        if f and f:IsShown() and T.PageShown() then return end
        ns.ToggleMain("trash")
    end
end

-- ---------- 事件 ----------
local ev = CreateFrame("Frame")
T.ev = ev
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "DELETE_ITEM_CONFIRM" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnUpdate", function()
    if T.dirty and now() >= (T.dirtyAt or 0) then T.dirty = false; T.OnBags() end
end)
ev:SetScript("OnEvent", function(_, e)
    if e == "PLAYER_LOGIN" then
        after(T.LOGIN_DELAY, function() T.ready = true; T.OnBags() end)
    elseif e == "BAG_UPDATE" or (e == "GET_ITEM_INFO_RECEIVED" and T.PageShown()) then
        T.dirty, T.dirtyAt = true, now() + 0.3
    elseif e == "BAG_UPDATE_DELAYED" then
        T.dirty = false
        T.OnBags()
    elseif e == "DELETE_ITEM_CONFIRM" then
        if T.deleting then T.sawPrompt = true end
    elseif e == "PLAYER_REGEN_DISABLED" then
        T.confirm = nil
        T.RefreshUI()
    elseif e == "PLAYER_REGEN_ENABLED" then
        if T.PageShown() then T.Refresh() end
    end
end)
T._event = ev:GetScript("OnEvent")   -- 测试用

-- ---------- 页 / 设置 / 命令 ----------
ns.RegisterPage({ key = "trash", order = 3.1, title = L("清背包", "Bag cleanup"), tabTitle = L("清背包", "Cleanup"),
    icon = "Interface\\Icons\\INV_Misc_Bag_07",
    build = function(p) T.BuildPage(p) end,
    refresh = function() T.Refresh() end })

if ns.RegisterSettings then
    ns.RegisterSettings({ key = "trash", order = 47, page = "trash", avail = function() return ns.Trash ~= nil end,
        title = function() return L("清背包（物品摧毁助手）", "Bag cleanup") end, short = function() return L("清背包", "Cleanup") end,
        items = {
            { type = "check", id = "trash.full", text = function() return L("背包满时在聊天框提示一次可以用「清背包」（每次登录最多一次）", "When bags are full, mention Bag cleanup in chat (once per login)") end,
              get = function() return T.Opt("fullTip") and true or false end, set = function(v) T.SetOpt("fullTip", v) end },
            { type = "check", id = "trash.epic", text = function() return L("列出紫色（史诗）及以上物品（默认不列）", "List epic and better items (off by default)") end,
              get = function() return T.Opt("epic") and true or false end, set = function(v) T.SetOpt("epic", v) end },
            { type = "check", id = "trash.conj", text = function() return L("不列出魔法造的食物和水（含法力宝石 / 治疗石 / 灵魂石）", "Hide conjured food / water (and mana gems / healthstones / soulstones)") end,
              get = function() return T.Opt("skipConj") and true or false end, set = function(v) T.SetOpt("skipConj", v) end },
            { type = "button", id = "trash.clear", w = 200, text = function() return string.format(L("清空不摧毁名单（%d 件）", "Clear keep list (%d)"), T.KeepCount()) end,
              click = function()
                  local n = T.ClearKeep()
                  ns.Print(string.format(L("不摧毁名单已清空（%d 件）", "Keep list cleared (%d)"), n))
                  if ns.RefreshSettings then ns.RefreshSettings() end
              end },
            { type = "note", text = function() return L("右键「清背包」页上的一行 = 加入不摧毁名单。任务物品、炉石、专业工具、灵魂碎片、施法材料、弹药永远不列出",
                "Right-click a row on the Bag cleanup page to keep that item. Quest items, hearthstone, tools, soul shards, reagents and ammo are never listed") end },
        } })
end

ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash["摧毁"] = function(rest, rawRest)
    local r = (rawRest or ""):gsub("[ \t]+", "")
    local low = (rest or ""):gsub("[ \t]+", "")
    if r == "清空名单" or low == "clear" then
        ns.Print(string.format(L("不摧毁名单已清空（%d 件）", "Keep list cleared (%d)"), T.ClearKeep()))
    elseif r == "提示关" or low == "tipoff" then
        T.SetOpt("fullTip", false)
        ns.Print(L("背包满提示：关（/gi 摧毁 提示开 恢复）", "Full-bag tip: off (/gi trash tipon)"))
    elseif r == "提示开" or low == "tipon" then
        T.SetOpt("fullTip", true)
        ns.Print(L("背包满提示：开", "Full-bag tip: on"))
    else
        T.Open()
    end
end
ns.ExtraSlash.trash = ns.ExtraSlash["摧毁"]
