-- 11-12 用户「自动要水，自动发水，都做，做好了告诉我怎么用，好好设计」：在 1.0.0「法师吃喝」（DungeonChat.lua，招人页开关）上做完整
--   总开关仍是招人页那个「法师吃喝」（rec.mageAsk，默认关）；右键 = 细项设置（/gi 吃喝 同一个面板）。按当前角色分两半：
--   不是法师 → 帮你要：
--     ① 副本里跟法师开交易 → 私聊他要（1.0.0 原功能，现在按背包缺多少、按等级报能吃的水 / 面包）
--     ② 进副本 / 队伍满 5 人，队里有法师、背包里能吃的水或面包不到一组 → 自动要一次（每个法师 10 分钟最多一次；默认私聊，可改队伍频道）
--     没蓝的职业（战士 / 盗贼）只要面包；德鲁伊按职业算有蓝（变形后能量 / 怒气不算数）
--   是法师 → 帮你发：
--     ③ 队友私聊 / 队伍里说要水要面包 → 自动回一句 + 弹「有人要吃喝」提醒条（带「造水术」「造食术」一键施法按钮）
--     ④ 跟人开交易 → 交易窗下面出「一键放入」按钮：点一下把对方能吃的最高等级水 / 面包（各一组）放进交易栏，并密他一句
--   ⛔ 受保护 / 要按键的动作一律交给玩家点：
--     · 施法造水 / 造食 = 受保护（CastSpell 只能安全按钮）→ 提醒条上是 SecureActionButton（type=spell），玩家点了才施法
--     · 放进交易栏：右键背包物品进交易栏走的是 UseContainerItem（受保护）→ 也做成安全按钮（type=macro，宏文字「/use 背包 格子」），
--       不用 PickupContainerItem + ClickTradeButton 自动塞：12.x 引擎上这两个有没有被收紧没法离线核实，点一下最稳、绝不弹「插件被禁止」
--     · 确认交易 AcceptTrade 需要硬件事件 → 插件不碰，玩家自己点「交易」
--     · 安全按钮的属性只在脱战改；战斗中按钮由状态驱动自动藏起来（照 Talents.lua 天赋按钮），只认按下（AnyDown，《无限》实测）
--     · 发的话走 DC.Tagged（「[GI组队助手]」前缀，招人页「带标识」可关）；战斗中 / 聊天锁定（C_ChatInfo.InChatMessagingLockdown）不发
--   本文件在组队子插件 HOLD 里：不加载时 DungeonChat.lua 的 1.0.0 老逻辑照旧
local _, ns = ...; ns = _G.GearInsightForever or ns
local L = function(cn, en) return ns.L(cn, en) end
local DC = ns.DungeonChat
if not DC then return end

local MW = { orders = {}, autoKeys = {}, replied = {} }
ns.MageWater = MW
MW.TARGET = 20          -- 一组
MW.AUTO_CD = 600        -- 自动要：同一个法师 10 分钟最多一次
MW.REPLY_CD = 180       -- 法师自动回话：同一个人 3 分钟一次
MW.ORDER_TTL = 300      -- 提醒条上的「有人要」留 5 分钟
MW.ENTER_DELAY = 5      -- 进副本后等几秒（过完读条、队友单位就绪）

-- ---------- 数据：法师造的水 / 面包（无限 1.60.1.70790 ItemSparse + SpellEffect 核对：法术 → 造出的物品 → 使用等级）----------
--   req = 物品使用等级；spell = 造它的那一级法术；名字 = ItemSparse zhCN 官方名（游戏里优先用客户端返回的名字，繁体客户端自动是繁体）
--   山泉水 231778（造水术 等级 8，法术 468766，一次 20 瓶）：客户端数据里有、法术书数据标 60 级，没在游戏里见过 → 只在法师背包里真有时才给，不拿来报给法师
MW.WATER = {
    { id = 5350, req = 1, spell = 5504, n = "魔法水", en = "Conjured Water" },
    { id = 2288, req = 5, spell = 5505, n = "魔法淡水", en = "Conjured Fresh Water" },
    { id = 2136, req = 15, spell = 5506, n = "魔法纯净水", en = "Conjured Purified Water" },
    { id = 3772, req = 25, spell = 6127, n = "魔法泉水", en = "Conjured Spring Water" },
    { id = 8077, req = 35, spell = 10138, n = "魔法矿泉水", en = "Conjured Mineral Water" },
    { id = 8078, req = 45, spell = 10139, n = "魔法苏打水", en = "Conjured Sparkling Water" },
    { id = 8079, req = 55, spell = 10140, n = "魔法晶水", en = "Conjured Crystal Water" },
    { id = 231778, req = 55, spell = 468766, n = "山泉水", noAsk = true },
}
MW.FOOD = {
    { id = 5349, req = 1, spell = 587, n = "魔法松饼", en = "Conjured Muffin" },
    { id = 1113, req = 5, spell = 597, n = "魔法面包", en = "Conjured Bread" },
    { id = 1114, req = 15, spell = 990, n = "魔法黑面包", en = "Conjured Rye" },
    { id = 1487, req = 25, spell = 6129, n = "魔法粗面包", en = "Conjured Pumpernickel" },
    { id = 8075, req = 35, spell = 10144, n = "魔法酵母", en = "Conjured Sourdough" },
    { id = 8076, req = 45, spell = 10145, n = "魔法甜面包", en = "Conjured Sweet Roll" },
    { id = 22895, req = 55, spell = 28612, n = "魔法肉桂面包", en = "Conjured Cinnamon Roll" },
}
local BY_ID = {}
for _, list in ipairs({ MW.WATER, MW.FOOD }) do for _, e in ipairs(list) do BY_ID[e.id] = e end end
MW.BY_ID = BY_ID
-- 没蓝的职业：只要面包（按职业算，不看当前能量类型：熊 / 猫德鲁伊照样要水）
MW.NO_MANA = { WARRIOR = true, ROGUE = true, DEATHKNIGHT = true }

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
local short = DC.Short
local function combat() return InCombatLockdown and InCombatLockdown() and true or false end
local function unitClass(u) local _, c = call(UnitClass, u); return clean(c) end
local function unitClassName(u) local n = call(UnitClass, u); return clean(n) end
local function unitLevel(u) local v = tonumber(clean(call(UnitLevel, u))); if v and v > 0 then return v end return nil end
local function myClass() return unitClass("player") end
function MW.IsMage() return myClass() == "MAGE" end
function MW.WantsWater(cls) return not (cls and MW.NO_MANA[cls]) end

-- ---------- 设置（ns.db.dchat.mw；nil = 默认值）----------
MW.DEFAULTS = { askTrade = true, askAuto = true, askParty = false, reply = true, giveBtn = true, bar = true }
function MW.Opts()
    local d = DC.DB()
    d.mw = d.mw or {}
    return d.mw
end
function MW.Opt(k)
    local v = MW.Opts()[k]
    if v == nil then return MW.DEFAULTS[k] end
    return v
end
function MW.SetOpt(k, v)
    if (v and true or false) == MW.DEFAULTS[k] then MW.Opts()[k] = nil else MW.Opts()[k] = v and true or false end
end
function MW.On() return DC.DB().rec.mageAsk and true or false end
function MW.SetOn(v) DC.DB().rec.mageAsk = v and true or nil end
-- 自动要过的法师 → 时间（GetTime；存进存档：/reload 后不会立刻再要一遍；GetTime 是开机时长，重登也接得上）
function MW.Asked()
    local d = DC.DB()
    d.mwAsk = d.mwAsk or {}
    return d.mwAsk
end
function MW.MarkAsked(who, t)
    local a = MW.Asked()
    a[who] = t
    for k, v in pairs(a) do if type(v) ~= "number" or t - v > 3600 or v > t then a[k] = nil end end
    a[who] = t
end

-- ---------- 物品 ----------
function MW.ItemName(e)
    if not e then return "" end
    local n
    if C_Item and C_Item.GetItemNameByID then n = call(C_Item.GetItemNameByID, e.id) end
    if (type(n) ~= "string" or n == "") and GetItemInfo then n = call(GetItemInfo, e.id) end
    if type(n) == "string" and n ~= "" then return n end
    return L(e.n, e.en or e.n)
end
-- 这个等级能吃 / 喝到的最高一档（noAsk 的不算：要的时候报给法师用）
function MW.BestFor(list, lv, forAsk)
    local best
    for _, e in ipairs(list) do
        if (not lv or e.req <= lv) and not (forAsk and e.noAsk) then best = e end
    end
    return best
end

local function slotInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local t = call(C_Container.GetContainerItemInfo, bag, slot)
        if type(t) == "table" then return clean(t.itemID), clean(t.stackCount) end
        return nil
    end
    if GetContainerItemInfo then
        local r = { pcall(GetContainerItemInfo, bag, slot) }
        if r[1] then return clean(r[11]), clean(r[3]) end
    end
    return nil
end
local function numSlots(bag)
    local f = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    return tonumber(clean(call(f, bag))) or 0
end
-- 背包里所有法师吃喝：[物品ID] = { n = 总数, bag, slot, top = 最大一叠的数量 }
function MW.ScanBags()
    local out = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, numSlots(bag) do
            local id, cnt = slotInfo(bag, slot)
            id, cnt = tonumber(id), tonumber(cnt) or 1
            if id and BY_ID[id] then
                local o = out[id]
                if not o then o = { n = 0, top = 0 }; out[id] = o end
                o.n = o.n + cnt
                if cnt > o.top then o.top, o.bag, o.slot = cnt, bag, slot end
            end
        end
    end
    return out
end
-- 这个等级能吃的这类吃喝背包里一共几个
function MW.Have(list, lv, scan)
    local n = 0
    for _, e in ipairs(list) do
        if (not lv or e.req <= lv) and scan[e.id] then n = n + scan[e.id].n end
    end
    return n
end
-- 法师给 lv 级的人：背包里有的、他能吃的最高一档
function MW.Supply(list, lv, scan)
    for i = #list, 1, -1 do
        local e = list[i]
        if (not lv or e.req <= lv) and scan[e.id] and scan[e.id].n > 0 then return e, scan[e.id] end
    end
    return nil
end

-- ---------- 发话 ----------
function MW.CanChat()
    if combat() then return false end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and call(C_ChatInfo.InChatMessagingLockdown) then return false end
    return true
end
function MW.Send(text, chan, to)
    if not text or not MW.CanChat() then return false end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    return (pcall(send, DC.Tagged(text, DC.MAX_BYTES), chan, nil, to))
end

-- ================= 不是法师：要 =================
local function qty(n)
    if n >= 15 then return L("一组", "a stack of ") end
    return n .. L("个", " ")
end
-- mode = "trade"（开了交易，背包够也要）/ "auto"（自动要：够一组就不要，返回 nil）
function MW.AskText(mode)
    local lv, cls = unitLevel("player"), myClass()
    local wantW = MW.WantsWater(cls)
    local scan = MW.ScanBags()
    local nw = wantW and math.max(0, MW.TARGET - MW.Have(MW.WATER, lv, scan)) or 0
    local nf = math.max(0, MW.TARGET - MW.Have(MW.FOOD, lv, scan))
    if nw == 0 and nf == 0 then
        if mode ~= "trade" then return nil end
        nw, nf = wantW and MW.TARGET or 0, MW.TARGET
    end
    local parts, names = {}, {}
    if nw > 0 then
        parts[#parts + 1] = qty(nw) .. L("水", "water")
        names[#names + 1] = MW.ItemName(MW.BestFor(MW.WATER, lv, true))
    end
    if nf > 0 then
        parts[#parts + 1] = qty(nf) .. L("面包", "food")
        names[#names + 1] = MW.ItemName(MW.BestFor(MW.FOOD, lv, true))
    end
    local lvTxt = lv and string.format(L("我%d级：", "Lv%d: "), lv) or ""
    return L("法师老板，求", "Could I get ") .. table.concat(parts, L("和", " and "))
        .. L("，谢谢~（", " please? Thanks! (") .. lvTxt .. table.concat(names, " / ") .. L("）", ")")
end

local function inDungeon()
    if not IsInInstance then return false end
    local r = { pcall(IsInInstance) }
    if not (r[1] and clean(r[2])) then return false end
    local kind = clean(r[3])
    return kind == nil or kind == "party" or kind == "raid", kind
end
MW.InDungeon = inDungeon

-- ① 交易法师（1.0.0 原功能：只在副本里；同一个法师 DC.MAGE_CD 秒内一次）
function MW.AskOnTrade()
    if not MW.Opt("askTrade") then return false end
    if not inDungeon() then return false end
    if unitClass("NPC") ~= "MAGE" then return false end
    local who = DC.FullName("NPC")
    if not who or who == "" then return false end
    DC.mageAsked = DC.mageAsked or {}
    local t = now()
    if DC.mageAsked[who] and t - DC.mageAsked[who] < DC.MAGE_CD then return false end
    local text = MW.AskText("trade")
    if not MW.Send(text, "WHISPER", who) then return false end
    DC.mageAsked[who] = t
    MW.MarkAsked(who, t)
    return true
end

-- 队友（小队；团队只认 raid1-40）
local function groupUnits()
    local out = {}
    local raid = IsInRaid and call(IsInRaid)
    if clean(raid) then
        for i = 1, 40 do out[#out + 1] = "raid" .. i end
    else
        for i = 1, 4 do out[#out + 1] = "party" .. i end
    end
    return out
end
local function exists(u) return clean(call(UnitExists, u)) and true or false end
local function isMe(u) return clean(call(UnitIsUnit, u, "player")) and true or false end
function MW.PartyMages()
    local out = {}
    for _, u in ipairs(groupUnits()) do
        if exists(u) and not isMe(u) and unitClass(u) == "MAGE" then
            local on = UnitIsConnected and call(UnitIsConnected, u)
            if on == nil or clean(on) ~= false then
                local who = DC.FullName(u)
                if who and who ~= "" then out[#out + 1] = who end
            end
        end
    end
    return out
end

-- ② 进副本 / 满 5 人自动要：key 记「这个副本（或这次满员）× 这个法师」，同一个法师 AUTO_CD 内不再要
function MW.AutoCheck(reason)
    if not MW.On() or not MW.Opt("askAuto") or MW.IsMage() then return false, "off" end
    if not (IsInGroup and call(IsInGroup)) then return false, "solo" end
    if clean(IsInRaid and call(IsInRaid)) then return false, "raid" end
    if combat() then MW.pendingAuto = reason or true; return false, "combat" end
    local inInst = inDungeon()
    local full = DC.PartyCount() >= DC.FULL_N
    if not inInst and not full then return false, "notyet" end
    local mages = MW.PartyMages()
    if #mages == 0 then return false, "nomage" end
    local text = MW.AskText("auto")
    if not text then return false, "enough" end
    local t = now()
    local inst = inInst and (clean(call(GetInstanceInfo)) or "inst") or "full"
    local target
    local asked = MW.Asked()
    for _, m in ipairs(mages) do
        local key = inst .. "|" .. m
        local last = asked[m]
        if not MW.autoKeys[key] and not (last and last <= t and t - last < MW.AUTO_CD) then target = target or m end
    end
    if not target then return false, "asked" end
    local ok
    if MW.Opt("askParty") then ok = MW.Send(text, "PARTY") else ok = MW.Send(text, "WHISPER", target) end
    if not ok then return false, "send" end
    -- 队里几个法师都算问过了（发队伍频道本来就是问所有人；私聊只问一个，别挨个刷）
    for _, m in ipairs(mages) do MW.MarkAsked(m, t); MW.autoKeys[inst .. "|" .. m] = true end
    MW.pendingAuto = nil
    return true, target
end
local function autoSoon(reason, delay)
    if not MW.On() then return end
    if C_Timer and C_Timer.After then C_Timer.After(delay or 2, function() pcall(MW.AutoCheck, reason) end) else pcall(MW.AutoCheck, reason) end
end

-- ================= 法师：发 =================
-- 认「要吃喝」的话：返回 water, food（都 false = 不是）
local NOT_WATER = { "水平", "水晶", "下水道", "水下", "水元素", "水果", "水母", "水手", "水桶", "水泥", "水怪", "水域", "水路", "口水", "灌水", "风水", "水友", "薪水", "水货", "水深", "水草" }
local WATER_W = { "水", "喝的", "喝点", "饮料" }
local FOOD_W = { "面包", "吃的", "吃点", "食物", "粮", "馒头", "饼" }
local BOTH_W = { "吃喝", "吃的喝的", "水和面包", "水跟面包", "水面包" }
local INTENT_W = { "求", "要", "给", "来", "麻烦", "能", "有", "发", "整", "搞", "弄", "谢", "法师", "老板", "大佬", "拜托", "一组", "点", "些", "plz", "pls", "please", "need", "?", "？" }
local NEG_W = { "不用", "不要", "不需要", "够了", "有了", "我有", "不缺", "别给", "不渴", "no need" }
-- 英文按整词认（⛔ 用 a-z 字节范围，别用 %a：跟区域设置走，中文字节可能被当成字母）
local EN_WATER = { "%f[a-z]water%f[^a-z]", "%f[a-z]drinks?%f[^a-z]" }
local EN_FOOD = { "%f[a-z]food%f[^a-z]", "%f[a-z]bread%f[^a-z]" }
local function hasAny(s, words)
    for _, w in ipairs(words) do if s:find(w, 1, true) then return true end end
    return false
end
local function hasPat(s, pats)
    for _, p in ipairs(pats) do if s:find(p) then return true end end
    return false
end
local function stripText(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    return s
end
function MW.ParseAsk(msg)
    if type(msg) ~= "string" or msg == "" then return false, false end
    local tagged = DC.HasTag(msg)
    local s = DC.LowerAscii(stripText(DC.StripTag(msg)))
    -- 法师那边插件回的话（「好的，来交易就给你」「吃喝放好了」）不是要
    if tagged and (s:find("交易", 1, true) or s:find("trade", 1, true) or s:find("稍等", 1, true)) then return false, false end
    if hasAny(s, NEG_W) then return false, false end
    local w = s
    for _, x in ipairs(NOT_WATER) do w = w:gsub(x, "") end
    local both = hasAny(s, BOTH_W)
    local water = both or hasAny(w, WATER_W) or hasPat(s, EN_WATER)
    local food = both or hasAny(s, FOOD_W) or hasPat(s, EN_FOOD)
    if not (water or food) then return false, false end
    -- 很短的一句（「水」「求水」「面包」）直接算；长句要有「求 / 要 / 给 / 麻烦 / ?」这类词；对方插件发来的「法师老板，求…」直接算
    if not (tagged or #s <= 15 or hasAny(s, INTENT_W)) then return false, false end
    return water, food
end
-- 组队招人那边「来密我的人」别把要水的私聊当报名（DungeonChat.OnWhisper 调）
function MW.SkipWhisper(msg)
    local w, f = MW.ParseAsk(msg)
    if w or f then return true end
    return DC.HasTag(msg) and type(msg) == "string" and (msg:find("交易", 1, true) or msg:find("稍等", 1, true)) and true or false
end

-- 聊天作者 → 队友单位（不在队里 = nil）
function MW.UnitOf(author)
    local s = short(clean(author))
    if not s or s == "" then return nil end
    for _, u in ipairs(groupUnits()) do
        if exists(u) then
            local f = DC.FullName(u)
            local n = clean(call(UnitName, u))
            if s == f or s == n or (f and f:match("^[^ ]+") == s) or (n and s:match("^[^ ]+") == n) then return u end
        end
    end
    return nil
end

-- 给这个人：哪一档水 / 面包（背包里有的、他能吃的最高档）
function MW.PlanFor(cls, lv, water, food, scan)
    scan = scan or MW.ScanBags()
    local p = { lv = lv, cls = cls }
    if water == nil then water = true end
    if food == nil then food = true end
    if not MW.WantsWater(cls) then water = false; food = true end
    p.water, p.food = water, food
    if water then p.we, p.ws = MW.Supply(MW.WATER, lv, scan) end
    if food then p.fe, p.fs = MW.Supply(MW.FOOD, lv, scan) end
    return p
end
local function planText(p, withCount)
    local t = {}
    if p.we then t[#t + 1] = MW.ItemName(p.we) .. (withCount and ("×" .. p.ws.top) or "") end
    if p.fe then t[#t + 1] = MW.ItemName(p.fe) .. (withCount and ("×" .. p.fs.top) or "") end
    return table.concat(t, " + ")
end
MW.PlanText = planText
-- 有没有货：要的每一类背包里都有他能吃的（不到一组也先给，法师再补造）
local function planEnough(p)
    if p.water and not p.we then return false end
    if p.food and not p.fe then return false end
    return true
end

-- ③ 有人要
function MW.OnAsk(msg, author)
    if not MW.On() or not MW.IsMage() then return false end
    if not (MW.Opt("reply") or MW.Opt("bar")) then return false end
    author = clean(author)
    local s = short(author)
    if not s or s == short(clean(call(UnitName, "player"))) or s == DC.FullName("player") then return false end
    local u = MW.UnitOf(author)
    if not u then return false end
    local cls = unitClass(u)
    if cls == "MAGE" then return false end
    local water, food = MW.ParseAsk(clean(msg))
    if not (water or food) then return false end
    local lv = unitLevel(u)
    local p = MW.PlanFor(cls, lv, water, food)
    local who = DC.FullName(u) or s
    MW.orders[who] = { who = who, cls = cls, clsName = unitClassName(u), lv = lv, water = p.water, food = p.food, t = now() }
    -- 正在跟他交易：交易窗下面就有按钮，不用再回话
    local t = now()
    if MW.Opt("reply") and MW.tradeWith ~= who and not (MW.replied[who] and t - MW.replied[who] < MW.REPLY_CD) then
        local text
        if planEnough(p) then text = L("好的，来交易就给你（", "Sure - open a trade and I'll put in ") .. planText(p) .. L("）", "")
        else text = L("稍等，我先造一下，好了叫你~", "One sec, conjuring some - I'll ping you") end
        if MW.Send(text, "WHISPER", who) then MW.replied[who] = t end
    end
    if MW.Opt("bar") then MW.RefreshBar(true) end
    return true
end
function MW.Orders()
    local out, t = {}, now()
    for k, o in pairs(MW.orders) do
        if t - o.t > MW.ORDER_TTL then MW.orders[k] = nil else out[#out + 1] = o end
    end
    table.sort(out, function(a, b) return a.t < b.t end)
    return out
end

-- 已知的最高一级造水术 / 造食术
local function known(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown and call(C_SpellBook.IsSpellKnown, id) then return true end
    if IsPlayerSpell and call(IsPlayerSpell, id) then return true end
    if IsSpellKnown and call(IsSpellKnown, id) then return true end
    return false
end
function MW.BestSpell(list)
    for i = #list, 1, -1 do if known(list[i].spell) then return list[i].spell, list[i] end end
    return nil
end

-- ---------- 安全按钮（只在脱战建 / 改属性；战斗中状态驱动藏起来）----------
-- reshow = 脱战后自己再出来（提醒条上的造水 / 造食；交易按钮不要，下次开交易再显示）
local function secureBtn(name, parent, w, h, reshow)
    local b = CreateFrame("Button", name, parent or UIParent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    b:SetSize(w, h)
    if b.RegisterForClicks then b:RegisterForClicks("AnyDown") end
    if RegisterStateDriver and b.SetAttribute then
        b:SetAttribute("_onstate-gimwcombat", reshow and [[ if newstate == "1" then self:Hide() else self:Show() end ]] or [[ if newstate == "1" then self:Hide() end ]])
        RegisterStateDriver(b, "gimwcombat", "[combat] 1; 0")
    end
    return b
end
MW.SecureBtn = secureBtn

-- ④ 交易窗「一键放入」
local function tradeItems()
    local have = {}
    for i = 1, (MAX_TRADABLE_ITEMS or 6) do
        local link = GetTradePlayerItemLink and call(GetTradePlayerItemLink, i)
        local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
        if id then have[id] = true end
    end
    return have
end
function MW.TradeTarget()
    local who = DC.FullName("NPC")
    if (not who or who == "") and _G.TradeFrameRecipientNameText and TradeFrameRecipientNameText.GetText then
        who = clean(call(TradeFrameRecipientNameText.GetText, TradeFrameRecipientNameText))
    end
    return who, unitClass("NPC"), unitLevel("NPC")
end
-- 现在点「一键放入」会放什么：plan + 宏文字（已经在交易栏里的那类不再放）
function MW.GivePlan()
    local who, cls, lv = MW.TradeTarget()
    local o = who and MW.orders[who]
    local p = MW.PlanFor(cls, lv, o and o.water, o and o.food)
    local inTrade = tradeItems()
    local lines = {}
    if p.we and inTrade[p.we.id] then p.we = nil end
    if p.fe and inTrade[p.fe.id] then p.fe = nil end
    if p.we then lines[#lines + 1] = "/use " .. p.ws.bag .. " " .. p.ws.slot end
    if p.fe then lines[#lines + 1] = "/use " .. p.fs.bag .. " " .. p.fs.slot end
    p.who, p.macro = who, table.concat(lines, "\n")
    return p
end
local function giveLabel(p)
    if p.we or p.fe then return L("给他：", "Give: ") .. planText(p, true) end
    return L("背包里没有他能吃的吃喝", "No conjured food / water he can use")
end
function MW.BuildGiveBtn()
    if MW.giveBtn then return MW.giveBtn end
    if combat() then return nil end
    local b = secureBtn("GearInsightForeverMageGive", UIParent, 260, 26)
    b:SetFrameStrata("DIALOG")
    b:SetText(L("给他吃喝", "Give food / water"))
    b:SetScript("PreClick", function(self)
        self.plan = nil
        if combat() then return end
        if not MW.tradeOpen then self:SetAttribute("type", nil); return end
        local p = MW.GivePlan()
        if p.macro == "" then
            self:SetAttribute("type", nil)
            ns.Print(L("背包里没有他能吃的法师吃喝（或已经放进去了），先用「造水术 / 造食术」造一些", "Nothing to give (or already in the trade) - conjure some first"))
            return
        end
        self:SetAttribute("type", "macro")
        self:SetAttribute("macrotext", p.macro)
        self.plan = p
    end)
    b:SetScript("PostClick", function(self)
        local p = self.plan
        self.plan = nil
        if not combat() then self:SetAttribute("type", nil); self:SetAttribute("macrotext", nil) end
        if not p then return end
        ns.Print(L("已放进交易栏：", "Put in the trade: ") .. planText(p, true) .. L("。确认交易请自己点「交易」（暴雪不允许插件替你确认）", ". Click Trade yourself to confirm (addons can't)"))
        if p.who then
            MW.orders[p.who] = nil
            MW.served = p.who
            if MW.Opt("reply") and not MW.tradeReplied then
                MW.tradeReplied = true
                MW.Send(L("吃喝放好了（", "Food / water is in the trade (") .. planText(p, true) .. L("），点交易就行~", ") - just hit Trade"), "WHISPER", p.who)
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0.3, function() pcall(MW.RefreshGive); pcall(MW.RefreshBar) end) end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L("一键放入吃喝", "Put food / water in"), 1, 0.82, 0)
        GameTooltip:AddLine(L("按对方等级挑他能吃的最高一档，水和面包各放一组；战士 / 盗贼只放面包", "Picks the best tier for their level, one stack each; warriors / rogues get food only"), 1, 1, 1, true)
        GameTooltip:AddLine(L("放好后自己点「交易」确认（暴雪规定确认交易必须你本人点）", "Then click Trade yourself to confirm"), 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    MW.giveBtn = b
    return b
end
function MW.RefreshGive()
    local b = MW.giveBtn
    if not b then return end
    local p = MW.GivePlan()
    b:SetText(giveLabel(p))
    if b.SetEnabled and not combat() then b:SetEnabled(p.macro ~= "") end
end
function MW.ShowGive()
    if combat() or not MW.Opt("giveBtn") then return false end
    local b = MW.BuildGiveBtn()
    if not b then return false end
    b:ClearAllPoints()
    local tf = _G.TradeFrame
    if tf and tf.IsShown and tf:IsShown() then b:SetPoint("TOP", tf, "BOTTOM", 0, -4) else b:SetPoint("CENTER", UIParent, "CENTER", 0, -220) end
    MW.RefreshGive()
    b:Show()
    return true
end
function MW.HideGive()
    local b = MW.giveBtn
    if not b then return end
    if combat() then MW.pendingHide = true; return end
    b:Hide()
end

-- 交易开 / 关（DungeonChat 的 TRADE_SHOW 转过来）
function MW.OnTradeShow()
    if not MW.On() then return false end
    MW.tradeOpen, MW.tradeReplied, MW.served = true, nil, nil
    if MW.IsMage() then
        MW.tradeWith = MW.TradeTarget()
        return MW.ShowGive()
    end
    return MW.AskOnTrade()
end
function MW.OnTradeClosed()
    MW.tradeOpen, MW.tradeWith = nil, nil
    MW.HideGive()
    if MW.bar then pcall(MW.RefreshBar) end
end

-- ---------- ③ 提醒条：有人要吃喝 + 造水 / 造食按钮 ----------
local function barPos()
    local d = DC.DB()
    return d.mwBar
end
function MW.BuildBar()
    if MW.bar then return MW.bar end
    if combat() then return nil end
    local f = CreateFrame("Frame", "GearInsightForeverMageBar", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(280, 120)
    f:SetFrameStrata("MEDIUM")
    if f.SetBackdrop then
        pcall(f.SetBackdrop, f, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.05, 0.06, 0.08, 0.92); f:SetBackdropBorderColor(0.41, 0.8, 0.94, 0.9)
    end
    local pos = barPos()
    if type(pos) == "table" and pos[1] then f:SetPoint(pos[1], UIParent, pos[1], pos[2] or 0, pos[3] or 0) else f:SetPoint("TOP", UIParent, "TOP", 0, -160) end
    f:SetMovable(true); f:EnableMouse(true)
    if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
    f:SetScript("OnDragStart", function(self) if not combat() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint()
        if p then DC.DB().mwBar = { p, x, y } end
    end)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("TOPLEFT", 8, -6)
    title:SetText(L("法师吃喝 · 有人要", "Mage food - requests"))
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetSize(22, 22); close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() MW.orders = {}; MW.RefreshBar() end)
    f.list = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.list:SetPoint("TOPLEFT", 8, -24); f.list:SetWidth(264); f.list:SetJustifyH("LEFT")
    f.stock = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.stock:SetPoint("BOTTOMLEFT", 8, 34); f.stock:SetWidth(264); f.stock:SetJustifyH("LEFT")
    -- 造水 / 造食：安全施法按钮（玩家点了才施法）
    local function castBtn(name, list, label, x)
        local b = secureBtn(name, f, 128, 24, true)
        b:SetPoint("BOTTOMLEFT", x, 6)
        b:SetText(label)
        b.list = list
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local id, e = MW.BestSpell(self.list)
            GameTooltip:AddLine(label, 1, 0.82, 0)
            if id then GameTooltip:AddLine(L("点一下施放最高等级（造出：", "Casts your best rank (makes ") .. MW.ItemName(e) .. L("）", ")"), 1, 1, 1, true)
            else GameTooltip:AddLine(L("还没学会", "Not learned yet"), 1, 0.3, 0.3, true) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    f.cw = castBtn("GearInsightForeverMageCastWater", MW.WATER, L("造水术", "Conjure Water"), 8)
    f.cf = castBtn("GearInsightForeverMageCastFood", MW.FOOD, L("造食术", "Conjure Food"), 144)
    f:Hide()
    MW.bar = f
    return f
end
-- 施法按钮的法术：学了新等级 / 建好时更新（只在脱战）
function MW.UpdateCastSpells()
    local f = MW.bar
    if not f or combat() then return end
    for _, b in ipairs({ f.cw, f.cf }) do
        local id = MW.BestSpell(b.list)
        b:SetAttribute("type", id and "spell" or nil)
        b:SetAttribute("spell", id)
        if b.SetEnabled then b:SetEnabled(id ~= nil) end
    end
end
local CLS_ZH = { WARRIOR = "战士", PALADIN = "圣骑士", HUNTER = "猎人", ROGUE = "盗贼", PRIEST = "牧师", SHAMAN = "萨满", MAGE = "法师", WARLOCK = "术士", DRUID = "德鲁伊" }
function MW.BarLines()
    local scan = MW.ScanBags()
    local out = {}
    for i, o in ipairs(MW.Orders()) do
        if i > 5 then break end
        local p = MW.PlanFor(o.cls, o.lv, o.water, o.food, scan)
        local want = {}
        if p.water then want[#want + 1] = L("水", "water") end
        if p.food then want[#want + 1] = L("面包", "food") end
        local what = table.concat(want, L("+", "+"))
        local cn = o.clsName or (o.cls and L(CLS_ZH[o.cls] or o.cls, o.cls)) or ""
        local lack = ""
        if (p.water and not p.we) or (p.food and not p.fe) then lack = L(" |cffff6060缺货|r", " |cffff6060none|r") end
        local lvTxt = o.lv and (" " .. o.lv .. L("级", "")) or ""
        out[#out + 1] = (short(o.who) or o.who) .. lvTxt .. (cn ~= "" and (" " .. cn) or "") .. L("：", ": ") .. what .. lack
    end
    return out, scan
end
function MW.StockText(scan)
    local lv = unitLevel("player")
    local parts = {}
    local we = MW.Supply(MW.WATER, lv, scan)
    local fe = MW.Supply(MW.FOOD, lv, scan)
    parts[#parts + 1] = we and (MW.ItemName(we) .. " " .. scan[we.id].n) or L("没有水", "no water")
    parts[#parts + 1] = fe and (MW.ItemName(fe) .. " " .. scan[fe.id].n) or L("没有面包", "no food")
    return L("背包：", "Bags: ") .. table.concat(parts, " · ")
end
-- show = 新来了一个要的（没建就建、没开就开）；平时只刷新文字，人都给完了就收起来
function MW.RefreshBar(show)
    if not MW.On() or not MW.IsMage() or not MW.Opt("bar") then
        if MW.bar and MW.bar:IsShown() and not combat() then MW.bar:Hide() end
        return false
    end
    local orders = MW.Orders()
    local f = MW.bar
    if not f then
        if not show or #orders == 0 then return false end
        f = MW.BuildBar()
        if not f then MW.pendingBar = true; return false end
        MW.UpdateCastSpells()
    end
    if #orders == 0 then
        if f:IsShown() then if combat() then MW.pendingBar = true else f:Hide() end end
        return false
    end
    local lines, scan = MW.BarLines()
    f.list:SetText(table.concat(lines, "\n"))
    f.stock:SetText(MW.StockText(scan))
    if not combat() then
        f:SetHeight(70 + 14 * #lines)
        if not f:IsShown() then MW.UpdateCastSpells(); f:Show() end
    elseif not f:IsShown() then MW.pendingBar = true end
    return true
end

-- ---------- 设置面板（招人页「法师吃喝」右键 / /gi 吃喝）----------
local OPT_ROWS = {
    { head = true, zh = "不是法师：帮你要", en = "Not a mage: ask for it", mage = false },
    { k = "askTrade", zh = "副本里跟法师开交易时，私聊他要", en = "Whisper the mage when you open a trade (in dungeons)" },
    { k = "askAuto", zh = "进副本 / 队伍满 5 人时自动要（队里有法师、背包不到一组才要）", en = "Ask automatically on entering a dungeon / full party (only if you're short)" },
    { k = "askParty", zh = "自动要改发队伍频道（默认私聊法师）", en = "Ask in party chat instead of whispering" },
    { head = true, zh = "是法师：帮你发", en = "Mage: hand it out", mage = true },
    { k = "reply", zh = "队友要水时自动回一句", en = "Auto-reply when a party member asks" },
    { k = "giveBtn", zh = "交易窗下面出「一键放入」按钮", en = "Show a one-click \"put in\" button under the trade window" },
    { k = "bar", zh = "有人要时弹提醒条（带造水 / 造食按钮）", en = "Pop a request bar (with Conjure buttons) when someone asks" },
}
MW.OPT_ROWS = OPT_ROWS
function MW.OpenSettings(anchor)
    local f = MW.optFrame
    if not f then
        f = CreateFrame("Frame", "GearInsightForeverMageWaterOpts", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(430, 60 + 26 * (#OPT_ROWS + 1))
        f:SetFrameStrata("DIALOG")
        if f.SetBackdrop then
            pcall(f.SetBackdrop, f, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            f:SetBackdropColor(0.05, 0.06, 0.08, 0.97); f:SetBackdropBorderColor(1, 0.82, 0, 0.8)
        end
        f:EnableMouse(true); f:SetMovable(true)
        if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 12, -10)
        title:SetText(L("法师吃喝", "Mage food & water"))
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 0, 0)
        close:SetScript("OnClick", function() f:Hide() end)
        f.checks = {}
        local function check(y, text, get, set, indent)
            local c = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
            c:SetSize(24, 24); c:SetPoint("TOPLEFT", indent or 12, y)
            local fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); fs:SetPoint("LEFT", c, "RIGHT", 4, 0); fs:SetText(text)
            c.text, c.get = fs, get
            c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); MW.RefreshSettings() end)
            f.checks[#f.checks + 1] = c
            return c
        end
        local y = -38
        check(y, L("总开关（和招人页「法师吃喝」按钮是同一个）", "Master switch (same as the Mage food button)"), MW.On, function(v) MW.SetOn(v); if ns.RefreshDungeonPanel then ns.RefreshDungeonPanel() end end)
        y = y - 30
        f.heads = {}
        for _, row in ipairs(OPT_ROWS) do
            if row.head then
                local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); fs:SetPoint("TOPLEFT", 14, y - 4)
                fs.row = row
                f.heads[#f.heads + 1] = fs
                y = y - 24
            else
                local k = row.k
                check(y, L(row.zh, row.en), function() return MW.Opt(k) end, function(v) MW.SetOpt(k, v) end, 30)
                y = y - 26
            end
        end
        f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.note:SetPoint("TOPLEFT", 14, y - 4); f.note:SetWidth(400); f.note:SetJustifyH("LEFT")
        f.note:SetText(L("施法、放进交易栏、确认交易都要你自己点（暴雪规定）；发出去的话带不带「", "Casting, putting items in and confirming trade need your click; the \"")
            .. DC.TAG .. L("」跟招人页「带标识」走", "\" prefix follows the Tag button"))
        f:SetHeight(-y + 30)
        MW.optFrame = f
    end
    f:ClearAllPoints()
    if anchor and anchor.GetCenter then f:SetPoint("BOTTOM", anchor, "TOP", 0, 6) else f:SetPoint("CENTER", UIParent, "CENTER", 0, 80) end
    MW.RefreshSettings()
    f:Show()
    return f
end
function MW.RefreshSettings()
    local f = MW.optFrame
    if not f then return end
    local mage = MW.IsMage()
    for _, fs in ipairs(f.heads) do
        local cur = (fs.row.mage == mage)
        fs:SetText(L(fs.row.zh, fs.row.en) .. (cur and L("（当前角色）", " (this character)") or ""))
        if fs.SetTextColor then if cur then fs:SetTextColor(1, 0.82, 0) else fs:SetTextColor(0.6, 0.6, 0.6) end end
    end
    for _, c in ipairs(f.checks) do c:SetChecked(c.get() and true or false) end
end

-- 招人页「法师吃喝」按钮的鼠标提示（DungeonChat 调）
function MW.Tip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:AddLine(L("法师吃喝", "Mage food & water") .. (MW.On() and L("（开）", " (on)") or L("（关）", " (off)")), 1, 0.82, 0)
    GameTooltip:AddLine(L("左键：开 / 关　右键：细项设置（/gi 吃喝 也行）", "Left-click: on / off   Right-click: options (/gi water)"), 0.6, 0.9, 1, true)
    local mage = MW.IsMage()
    GameTooltip:AddLine(L("不是法师 → 帮你要", "Not a mage - asks for you") .. ((not mage) and L("（当前角色）", " (this character)") or ""), 1, 0.82, 0)
    GameTooltip:AddLine(L("副本里跟法师开交易，或进副本 / 队伍满 5 人时队里有法师，背包吃喝不到一组就私聊他要，按你的等级报能吃的水和面包；战士 / 盗贼只要面包；每个法师 10 分钟最多一次", "Whispers the mage for the right tier when you trade them, enter a dungeon or the party fills - only if you're short, max once per 10 min per mage"), 1, 1, 1, true)
    GameTooltip:AddLine(L("是法师 → 帮你发", "Mage - hands it out") .. (mage and L("（当前角色）", " (this character)") or ""), 1, 0.82, 0)
    GameTooltip:AddLine(L("队友要水自动回一句并弹提醒条（带造水 / 造食按钮）；开交易时交易窗下面出「一键放入」，点一下放好水和面包，你再点「交易」确认", "Auto-replies and pops a request bar with Conjure buttons; a one-click button under the trade window puts the right stacks in - then you click Trade"), 1, 1, 1, true)
    GameTooltip:Show()
end

-- ---------- 事件 ----------
local ev = CreateFrame("Frame")
MW.ev = ev
for _, e in ipairs({ "TRADE_CLOSED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED",
    "CHAT_MSG_WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "BAG_UPDATE_DELAYED", "SPELLS_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e, a1, a2)
    if e == "TRADE_CLOSED" then pcall(MW.OnTradeClosed)
    elseif e == "CHAT_MSG_WHISPER" or e == "CHAT_MSG_PARTY" or e == "CHAT_MSG_PARTY_LEADER" or e == "CHAT_MSG_RAID" or e == "CHAT_MSG_RAID_LEADER" then
        pcall(MW.OnAsk, a1, a2)
    elseif e == "PLAYER_ENTERING_WORLD" or e == "ZONE_CHANGED_NEW_AREA" then
        -- 出了副本：这个副本的「问过了」清掉，下次再进同名副本还能再要
        if not inDungeon() then MW.autoKeys = {} end
        autoSoon("enter", MW.ENTER_DELAY)
    elseif e == "GROUP_ROSTER_UPDATE" then autoSoon("roster", 2)
    elseif e == "PLAYER_REGEN_ENABLED" then
        if MW.pendingHide then MW.pendingHide = nil; if not MW.tradeOpen and MW.giveBtn then MW.giveBtn:Hide() end end
        if MW.pendingBar then MW.pendingBar = nil; pcall(MW.RefreshBar, true) end
        if MW.pendingAuto then local r = MW.pendingAuto; MW.pendingAuto = nil; autoSoon(r, 2) end
    elseif e == "BAG_UPDATE_DELAYED" then
        if MW.bar and MW.bar:IsShown() then pcall(MW.RefreshBar) end
        if MW.tradeOpen and MW.giveBtn and MW.giveBtn:IsShown() then pcall(MW.RefreshGive) end
    elseif e == "SPELLS_CHANGED" then pcall(MW.UpdateCastSpells) end
end)
MW._event = ev:GetScript("OnEvent")   -- 测试用

-- /gi 吃喝 · /gi water：打开设置
ns.ExtraSlash = ns.ExtraSlash or {}
for _, c in ipairs({ "吃喝", "water", "mw" }) do ns.ExtraSlash[c] = function() MW.OpenSettings() end end
