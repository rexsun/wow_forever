-- 11-12 用户「自动要水，自动发水，都做，做好了告诉我怎么用，好好设计」：在 1.0.0「法师吃喝」（DungeonChat.lua，招人页开关）上做完整
--   总开关仍是招人页那个「法师吃喝」（rec.mageAsk，默认关）；右键 = 细项设置（/gi 吃喝 同一个面板）。按当前角色分两半：
--   不是法师 → 帮你要：
--     ① 副本里跟法师开交易 → 私聊他要（1.0.0 原功能，现在按背包缺多少、按等级报能吃的水 / 面包）
--     ② 进副本 / 队伍满 5 人，队里有法师、背包里能吃的水或面包不到一组 → 自动要一次（每个法师 10 分钟最多一次；默认私聊，可改队伍频道）
--     没蓝的职业（战士 / 盗贼）只要面包；德鲁伊按职业算有蓝（变形后能量 / 怒气不算数）
--     ⑤ 11-12 野外（不在副本 / 战场）碰到同阵营法师、背包水不够 → 弹小框问要不要密他（只弹框，点了才发；细项 fieldAsk 默认开，不受总开关管）
--     11-12 实测连发两条后：话术不报数量、弹框三选一（要水 / 要面包 / 都要，记住上次选的）；所有路径经 MW.AskMage，同一法师 10 分钟只发一次；档位统一口径
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
--   11-13 界面重构第 5 期：搬进单独的按需加载子插件 GearInsight_Forever_GroupMage —— 登录时按开关决定加载不加载（GroupParts.lua ns.GroupMageWanted），
--     加载后按开关只注册用得上的那一半事件（MW.SyncEvents）；DC.* 小工具在登录加载的 DungeonChatCore.lua
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
--   req = 物品使用等级；spell = 造它的那一级法术；learn = 法师学会这一级的等级（Data.lua 训练师表，11-12 野外提示用来从法师等级推他造得出哪档）；名字 = ItemSparse zhCN 官方名（游戏里优先用客户端返回的名字，繁体客户端自动是繁体）
--   山泉水 231778（造水术 等级 8，法术 468766，一次 20 瓶）：客户端数据里有、法术书数据标 60 级，没在游戏里见过 → 只在法师背包里真有时才给，不拿来报给法师
MW.WATER = {
    { id = 5350, req = 1, spell = 5504, learn = 4, n = "魔法水", en = "Conjured Water" },
    { id = 2288, req = 5, spell = 5505, learn = 10, n = "魔法淡水", en = "Conjured Fresh Water" },
    { id = 2136, req = 15, spell = 5506, learn = 20, n = "魔法纯净水", en = "Conjured Purified Water" },
    { id = 3772, req = 25, spell = 6127, learn = 30, n = "魔法泉水", en = "Conjured Spring Water" },
    { id = 8077, req = 35, spell = 10138, learn = 40, n = "魔法矿泉水", en = "Conjured Mineral Water" },
    { id = 8078, req = 45, spell = 10139, learn = 50, n = "魔法苏打水", en = "Conjured Sparkling Water" },
    { id = 8079, req = 55, spell = 10140, learn = 60, n = "魔法晶水", en = "Conjured Crystal Water" },
    { id = 231778, req = 55, spell = 468766, learn = 60, n = "山泉水", noAsk = true },
}
MW.FOOD = {
    { id = 5349, req = 1, spell = 587, learn = 6, n = "魔法松饼", en = "Conjured Muffin" },
    { id = 1113, req = 5, spell = 597, learn = 12, n = "魔法面包", en = "Conjured Bread" },
    { id = 1114, req = 15, spell = 990, learn = 22, n = "魔法黑面包", en = "Conjured Rye" },
    { id = 1487, req = 25, spell = 6129, learn = 32, n = "魔法粗面包", en = "Conjured Pumpernickel" },
    { id = 8075, req = 35, spell = 10144, learn = 42, n = "魔法酵母", en = "Conjured Sourdough" },
    { id = 8076, req = 45, spell = 10145, learn = 52, n = "魔法甜面包", en = "Conjured Sweet Roll" },
    { id = 22895, req = 55, spell = 28612, learn = 60, n = "魔法肉桂面包", en = "Conjured Cinnamon Roll" },
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
-- fieldAsk（⑤ 野外遇到法师弹框）跟总开关无关：只弹框、玩家点了才发，默认开
MW.DEFAULTS = { askTrade = true, askAuto = true, askParty = false, reply = true, giveBtn = true, bar = true, fieldAsk = true, thank = true }
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
    if MW.SyncEvents then pcall(MW.SyncEvents) end   -- 11-13 第 5 期：按开关重注册事件
end
function MW.On() return DC.DB().rec.mageAsk and true or false end
function MW.SetOn(v) DC.DB().rec.mageAsk = v and true or nil; if MW.SyncEvents then pcall(MW.SyncEvents) end end
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
-- 这个等级的法师造得出的最高一档（nil = 一档都还没学；noAsk 的山泉水不算）
function MW.MakeBest(list, mageLv)
    local best
    for _, e in ipairs(list) do
        if not e.noAsk and e.learn and (not mageLv or e.learn <= mageLv) then best = e end
    end
    return best
end
-- 报给法师的那一档（所有路径同一口径）：我能吃的最高档；知道法师等级且他还造不到那么高 → 降到他造得出的最高档
local function askTier(list, lv, mageLv)
    local e = MW.BestFor(list, lv, true)
    if mageLv then
        local mk = MW.MakeBest(list, mageLv)
        if mk and e and mk.req < e.req then e = mk end
    end
    return e
end
MW.AskTier = askTier

-- ---------- 要什么：水 / 面包 / 都要（11-12 用户「不要提数量，这个可以选，在对话框，水还是面包，还是都要」）----------
--   弹框三个按钮让玩家选；选过的记下来（ns.db.dchat.mwKind），下次弹框默认它、交易 / 进本 / 满员自动要也按它
--   没蓝职业（战士 / 盗贼）永远只要面包
MW.KINDS = { "water", "food", "both" }
local function kindParts(kind, cls)
    local w = (kind == "water" or kind == "both") and MW.WantsWater(cls)
    local f = (kind == "food" or kind == "both") or not MW.WantsWater(cls)
    return w and true or false, f and true or false
end
MW.KindParts = kindParts
-- 背包缺什么（不到一组）：shortW, shortF
function MW.Short(scan)
    local lv, cls = unitLevel("player"), myClass()
    scan = scan or MW.ScanBags()
    local sw = MW.WantsWater(cls) and MW.Have(MW.WATER, lv, scan) < MW.TARGET
    local sf = MW.Have(MW.FOOD, lv, scan) < MW.TARGET
    return sw and true or false, sf and true or false
end
-- 按背包推荐：缺水推水、都缺推都要；没蓝职业推面包；都不缺 → 有蓝推都要
function MW.Recommend(scan)
    if not MW.WantsWater(myClass()) then return "food" end
    local sw, sf = MW.Short(scan)
    if sw and sf then return "both" end
    if sw then return "water" end
    if sf then return "food" end
    return "both"
end
-- 上次选的（没选过 = nil）；没蓝职业存的是水也当面包
function MW.LastKind()
    local k = DC.DB().mwKind
    if k ~= "water" and k ~= "food" and k ~= "both" then return nil end
    if not MW.WantsWater(myClass()) then return "food" end
    return k
end
function MW.SetLastKind(k) if k == "water" or k == "food" or k == "both" then DC.DB().mwKind = k end end
-- 这次默认要什么：上次选的 > 按背包推荐
function MW.DefaultKind(scan) return MW.LastKind() or MW.Recommend(scan) end

-- 要吃喝的话（⛔ 不报数量）：「法师老板，求点水，谢谢~（我29级：魔法泉水）」
--   mode = "trade"（开了交易：按 kind 要，不管够不够）/ "auto"（自动要：只要 kind 里缺的；一样都不缺 → nil）/ "pick"（弹框里点的：按 kind 要）
--   kind = nil → 上次选的 / 按背包推荐；mageLv = 对方法师等级（知道就按他造得出的口径报档）
function MW.AskText(mode, mageLv, kind)
    local lv, cls = unitLevel("player"), myClass()
    local scan = MW.ScanBags()
    kind = kind or MW.DefaultKind(scan)
    local w, f = kindParts(kind, cls)
    if mode == "auto" then
        local sw, sf = MW.Short(scan)
        if MW.LastKind() == nil then w, f = sw, sf          -- 没选过：缺什么要什么
        elseif kind == "both" then w, f = w and sw, f and sf  -- 选了都要：只要缺的那样
        elseif not ((w and sw) or (f and sf)) then w, f = false, false end
        if not (w or f) then return nil end
    end
    local names = {}
    if w then names[#names + 1] = MW.ItemName(askTier(MW.WATER, lv, mageLv)) end
    if f then names[#names + 1] = MW.ItemName(askTier(MW.FOOD, lv, mageLv)) end
    local what
    if w and f then what = L("点水和面包", "some water and food")
    elseif w then what = L("点水", "some water")
    else what = L("点面包", "some food") end
    local lvTxt = lv and string.format(L("我%d级：", "Lv%d: "), lv) or ""
    return L("法师老板，求", "Could I get ") .. what
        .. L("，谢谢~（", " please? Thanks! (") .. lvTxt .. table.concat(names, " / ") .. L("）", ")")
end

-- 给某个法师发要水私聊的唯一出口：同一个法师 AUTO_CD（10 分钟）内不管哪条路径（交易 / 进本 / 满员 / 野外弹框）只发一次
--   11-12 用户截图：野外弹框开着时满员自动要先发了一条（按我能吃的档），再点弹框又发一条（按他能造的档）→ 连发两条、档位还不一样
function MW.RecentlyAsked(who, t)
    t = t or now()
    local last = who and MW.Asked()[who]
    return (last and last <= t and t - last < MW.AUTO_CD) and true or false
end
function MW.AskMage(who, text, chan)
    if not who or who == "" or not text then return false, "notext" end
    local t = now()
    if MW.RecentlyAsked(who, t) then return false, "asked" end
    local ok
    if chan == "PARTY" then ok = MW.Send(text, "PARTY") else ok = MW.Send(text, "WHISPER", who) end
    if not ok then return false, "send" end
    MW.MarkAsked(who, t)
    -- 弹框正问着同一个法师 → 已经要过了，收起
    if MW.fieldCur and MW.fieldCur.who == who and MW.HideField then MW.HideField() end
    return true
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
    if MW.RecentlyAsked(who, t) then return false end
    -- 种类按弹框里上次选的（没选过按背包缺什么）；档位按「他造得出就报我能吃的最高档」
    local text = MW.AskText("trade", unitLevel("NPC"))
    if not MW.AskMage(who, text) then return false end
    DC.mageAsked[who] = t
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
-- 返回 { 名字… }, { [名字] = 等级 }
function MW.PartyMages()
    local out, lvs = {}, {}
    for _, u in ipairs(groupUnits()) do
        if exists(u) and not isMe(u) and unitClass(u) == "MAGE" then
            local on = UnitIsConnected and call(UnitIsConnected, u)
            if on == nil or clean(on) ~= false then
                local who = DC.FullName(u)
                if who and who ~= "" then out[#out + 1] = who; lvs[who] = unitLevel(u) end
            end
        end
    end
    return out, lvs
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
    local mages, lvs = MW.PartyMages()
    if #mages == 0 then return false, "nomage" end
    if not MW.AskText("auto") then return false, "enough" end
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
    local text = MW.AskText("auto", lvs[target])
    if not MW.AskMage(target, text, MW.Opt("askParty") and "PARTY" or nil) then return false, "send" end
    -- 队里几个法师都算问过了（发队伍频道本来就是问所有人；私聊只问一个，别挨个刷）
    for _, m in ipairs(mages) do MW.MarkAsked(m, t); MW.autoKeys[inst .. "|" .. m] = true end
    MW.pendingAuto = nil
    return true, target
end
-- ================= ⑤ 野外遇到法师：弹框问要不要（不是法师；11-12 用户「野外碰到法师如果包里水不够，自动弹出框提示要」）=================
--   识别：目标 / 鼠标指向 / 友方姓名板出现 / 队友名单变化 —— 都是事件来一个单位查一个，不轮询、不每帧扫
--   条件：不在任何副本 / 战场里；对方是同阵营、在线的玩家法师；我背包里能喝的水不到一组（没蓝职业看面包）；
--         他的等级造得出我能吃的那档（最多比我能吃的最好那档低 FIELD_SLACK 档：差一档的水也比没有强）
--   防打扰：战斗中不弹（脱战不补）；同一个法师 30 分钟一次；任意两次弹框至少隔 5 分钟；「今天别再提示」= 本次登录 + 今天；
--           弹框 60 秒没人理自己收起；进战斗 / 进副本收起
--   ⛔ 只弹框，玩家点「要水 / 要面包 / 都要」才发私聊（走 MW.AskMage → MW.Send：战斗中 / 聊天锁定不发，带不带 [GI组队助手] 跟招人页「带标识」）
MW.FIELD_MAGE_CD = 1800   -- 同一个法师
MW.FIELD_GAP = 300        -- 任意两次弹框
MW.FIELD_TTL = 60         -- 弹框自己收起
MW.FIELD_SLACK = 1
MW.FIELD_LV_DIFF = 5      -- 11-12 用户「等级跟我差不多以及比我高的都能要」：比我低不超过 5 级（或更高）的法师一律弹，不再只看造得出哪档
MW.FIELD_PEEK = 30        -- 看过但不弹的法师（等级不够 / 我背包够），这么久内同一个人不再算
MW.fieldPeek = {}
local function wall() return (time and time()) or 0 end
local function today()
    local d = date or (os and os.date)
    return d and d("%Y-%m-%d") or ""
end
function MW.FieldDB()
    local d = DC.DB()
    d.mwField = d.mwField or {}
    local f = d.mwField
    f.mages = f.mages or {}
    return f
end
function MW.FieldMuted()
    if MW.fieldMuted then return true end
    local f = MW.FieldDB()
    return f.off ~= nil and f.off == today()
end
function MW.FieldMute(v)
    local f = MW.FieldDB()
    if v then MW.fieldMuted = true; f.off = today() else MW.fieldMuted = nil; f.off = nil end
    if MW.optFrame and MW.RefreshSettings then pcall(MW.RefreshSettings) end   -- 11-12 细项面板开着时跟着变（见 RefreshSettings）
end
local function inAnyInstance()
    if not IsInInstance then return false end
    local r = { pcall(IsInInstance) }
    return (r[1] and clean(r[2])) and true or false
end
-- 便宜的先查：开关 / 今天别提示 / 弹框开着 / 5 分钟间隔 / 战斗 / 副本
function MW.FieldGate()
    if not MW.Opt("fieldAsk") then return false, "off" end
    if MW.IsMage() then return false, "mage" end
    if MW.FieldMuted() then return false, "muted" end
    if MW.fieldFrame and MW.fieldFrame:IsShown() then return false, "showing" end
    local f, t = MW.FieldDB(), wall()
    if f.last and f.last <= t and t - f.last < MW.FIELD_GAP then return false, "gap" end
    if combat() then return false, "combat" end
    if inAnyInstance() then return false, "instance" end
    return true
end
-- 我缺什么：有蓝看水、没蓝看面包 → list, 能吃的有几个, 我能吃的最高档（够一组 = nil）
function MW.FieldNeed()
    local lv, cls = unitLevel("player"), myClass()
    local list = MW.WantsWater(cls) and MW.WATER or MW.FOOD
    local have = MW.Have(list, lv, MW.ScanBags())
    if have >= MW.TARGET then return nil end
    return list, have, MW.BestFor(list, lv, true)
end
-- 他造得出、对我有用的那档（nil = 造不出 / 差太多）
function MW.FieldTier(list, mine, mageLv)
    local mk = MW.MakeBest(list, mageLv)
    if not (mk and mine) then return nil end
    if mk.req >= mine.req then return mine end
    local im, ik
    for i, e in ipairs(list) do if e == mine then im = i end; if e == mk then ik = i end end
    if im and ik and im - ik <= MW.FIELD_SLACK then return mk end
    return nil
end
local function bool(v) return clean(v) and true or false end
-- 一个单位来了：是不是该弹框。返回 true / false, 原因
function MW.FieldCheck(u)
    local ok, why = MW.FieldGate()
    if not ok then return false, why end
    if not u or not exists(u) then return false, "nounit" end
    if not bool(call(UnitIsPlayer, u)) or isMe(u) then return false, "notplayer" end
    if unitClass(u) ~= "MAGE" then return false, "notmage" end
    if UnitIsFriend and not bool(call(UnitIsFriend, "player", u)) then return false, "enemy" end
    local mf, pf = clean(call(UnitFactionGroup, u)), clean(call(UnitFactionGroup, "player"))
    if mf and pf and mf ~= pf then return false, "faction" end
    local on = UnitIsConnected and call(UnitIsConnected, u)
    if on ~= nil and clean(on) == false then return false, "offline" end
    local who = DC.FullName(u)
    if not who or who == "" then return false, "noname" end
    local f, t, gt = MW.FieldDB(), wall(), now()
    local last = f.mages[who]
    if last and last <= t and t - last < MW.FIELD_MAGE_CD then return false, "mage_cd" end
    local peek = MW.fieldPeek[who]
    if peek and peek <= gt and gt - peek < MW.FIELD_PEEK then return false, "peek" end
    -- 刚自动要过 / 交易时要过他（MW.Asked，10 分钟）就别再弹
    local asked = MW.Asked()[who]
    if asked and asked <= gt and gt - asked < MW.AUTO_CD then return false, "asked" end
    MW.fieldPeek[who] = gt
    local list, have, mine = MW.FieldNeed()
    if not list then return false, "enough" end
    local lvRaw = tonumber(clean(call(UnitLevel, u)))
    local mageLv = (lvRaw and lvRaw > 0) and lvRaw or 60   -- -1 = 骷髅（高你 10 级以上）= 什么都造得出
    local tier = MW.FieldTier(list, mine, mageLv)
    local myLv = unitLevel("player")
    if not tier and myLv and mageLv >= myLv - MW.FIELD_LV_DIFF then tier = askTier(list, myLv, mageLv) end
    if not tier then return false, "lowlevel" end
    MW.fieldPeek[who] = nil
    MW.ShowField({ who = who, lv = (lvRaw and lvRaw > 0) and lvRaw or nil, mageLv = mageLv, water = (list == MW.WATER), have = have, tier = tier })
    return true, who
end
function MW.FieldText(o)
    local lvTxt = o.lv and string.format(L("（%d 级）", " (Lv%d)"), o.lv) or ""
    local what = o.water and L("水", "water") or L("面包", "food")
    local left = (o.have > 0) and string.format(L("只剩 %d 个", "is down to %d"), o.have) or L("一个都没有了", "is empty")
    local lv = unitLevel("player")
    local can = {}
    if MW.WantsWater(myClass()) then can[#can + 1] = MW.ItemName(askTier(MW.WATER, lv, o.mageLv)) end
    can[#can + 1] = MW.ItemName(askTier(MW.FOOD, lv, o.mageLv))
    return string.format(L("附近有法师 %s%s，你的%s%s，要不要密他要点？", "Mage %s%s is nearby and your %s %s - whisper them?"), short(o.who) or o.who, lvTxt, what, left)
        .. "\n|cff999999" .. L("会报给他：", "Will ask for: ") .. table.concat(can, " / ") .. "|r"
end
-- 弹框里点「要水 / 要面包 / 都要」：点了才发；记下这次选的（下次默认它，自动要也按它）
function MW.FieldSend(kind)
    local o = MW.fieldCur
    if not o then return false end
    kind = kind or MW.DefaultKind()
    if not MW.WantsWater(myClass()) then kind = "food" end
    MW.SetLastKind(kind)
    if MW.RecentlyAsked(o.who) then
        ns.Print(L("10 分钟内已经找 ", "Already asked ") .. (short(o.who) or o.who) .. L(" 要过了，不重复密", " in the last 10 min - not sending again"))
        MW.HideField()
        return false
    end
    if not MW.CanChat() then
        ns.Print(L("现在发不了私聊（战斗中 / 聊天受限），过一会儿再点", "Can't whisper right now (combat / chat locked) - try again in a moment"))
        return false
    end
    local text = MW.AskText("pick", o.mageLv, kind)
    local who = o.who
    if not MW.AskMage(who, text) then return false end
    ns.Print(L("已密 ", "Whispered ") .. (short(who) or who) .. L(" 要吃喝；他开交易给你时，自己点「交易」确认就行", " - when they open a trade, click Trade to accept"))
    MW.HideField()
    return true
end
function MW.HideField()
    MW.fieldCur = nil
    if MW.fieldFrame then MW.fieldFrame:Hide() end
end
local KIND_LABEL = { water = { "要水", "Water" }, food = { "要面包", "Food" }, both = { "都要", "Both" } }
function MW.BuildField()
    if MW.fieldFrame then return MW.fieldFrame end
    local f = CreateFrame("Frame", "GearInsightForeverFieldMage", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(330, 136)
    f:SetFrameStrata("DIALOG")
    if f.SetBackdrop then
        pcall(f.SetBackdrop, f, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.05, 0.06, 0.08, 0.95); f:SetBackdropBorderColor(0.41, 0.8, 0.94, 0.9)
    end
    local pos = MW.FieldDB().pos
    if type(pos) == "table" and pos[1] then f:SetPoint(pos[1], UIParent, pos[1], pos[2] or 0, pos[3] or 0) else f:SetPoint("TOP", UIParent, "TOP", 0, -200) end
    f:SetMovable(true); f:EnableMouse(true)
    if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint()
        if p then MW.FieldDB().pos = { p, x, y } end
    end)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("TOPLEFT", 10, -8)
    title:SetText(L("法师吃喝 · 附近有法师", "Mage food - a mage is nearby"))
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetSize(22, 22); close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() MW.HideField() end)
    -- 11-12 用户「放哪里合适，加上配置，方便用户找到」：框上直接给「设置」（同 /gi 吃喝、设置页「法师吃喝」、小地图右键）
    f.opt = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); f.opt:SetSize(48, 18); f.opt:SetPoint("RIGHT", close, "LEFT", -2, 0)
    f.opt:SetText(L("设置", "Options"))
    f.opt:SetScript("OnClick", function() MW.OpenSettings() end)   -- 弹框在屏幕上方，挂在它上面会出屏 → 居中开
    f.opt:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L("法师吃喝设置", "Mage food & water options"), 1, 0.82, 0)
        GameTooltip:AddLine(L("以后也能在：右侧「组队」页签 → 法师吃喝 · 右键小地图按钮 → 法师吃喝 · /gi 吃喝 · 主界面「设置」→ 全部设置里搜「法师」", "Also under the Group tab > Mage food, the minimap right-click menu, /gi water, or search Settings"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.opt:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); f.text:SetPoint("TOPLEFT", 10, -28); f.text:SetWidth(310); f.text:SetJustifyH("LEFT")
    local function btn(label, w, x, y, onClick, tipB)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(w, 22); b:SetPoint("BOTTOMLEFT", x, y); b:SetText(label)
        b.label = label
        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(self.label, 1, 0.82, 0)
            GameTooltip:AddLine(type(tipB) == "function" and tipB(self) or tipB, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    -- 第一排：要水 / 要面包 / 都要（点哪个发哪种；默认那个高亮）
    f.kinds = {}
    for i, k in ipairs(MW.KINDS) do
        local b = btn(L(KIND_LABEL[k][1], KIND_LABEL[k][2]), 96, 10 + (i - 1) * 104, 36, function() MW.FieldSend(k) end, function(self)
            if self.off then return L("你的职业不用蓝，只要面包", "Your class has no mana - food only") end
            local o = MW.fieldCur
            local t = o and MW.AskText("pick", o.mageLv, k)
            return L("点了才发，私聊他这句：\n", "Sends this whisper (only when you click):\n") .. (t and DC.Tagged(t, DC.MAX_BYTES) or "")
                .. L("\n|cff999999选过的下次默认它；交易 / 进副本 / 满员自动要也按它|r", "\n|cff999999Remembered as the default next time|r")
        end)
        b.kind = k
        f.kinds[k] = b
    end
    -- 第二排：不用 / 今天别再提示
    f.no = btn(L("不用", "No thanks"), 96, 10, 8, function() MW.HideField() end,
        L("关掉这个框；这个法师 30 分钟内不再提示", "Close; this mage won't be suggested again for 30 min"))
    f.mute = btn(L("今天别再提示", "Not today"), 130, 114, 8, function()
        MW.FieldMute(true); MW.HideField()
        ns.Print(L("今天不再提示附近的法师了；明天自动恢复。想现在恢复：主界面「设置」→ 窗口与提醒 点「解除静音」，或右键小地图按钮 →「法师吃喝」重新勾上", "Muted for today - unmute in Settings > Windows, or the minimap right-click menu > Mage food & water"))
    end, L("这次登录和今天都不再弹；明天自动恢复，或者在主界面「设置」→ 窗口与提醒 点「解除静音」", "Muted for this session and today; back tomorrow, or unmute it in Settings > Windows"))
    -- 60 秒没人理自己收起（只在开着时跑）
    f:SetScript("OnUpdate", function(self, el)
        self.age = (self.age or 0) + (el or 0)
        if self.age >= MW.FIELD_TTL then MW.HideField() end
    end)
    f:Hide()
    MW.fieldFrame = f
    return f
end
-- 三个按钮的默认高亮：上次选的 > 按背包推荐（缺水推水、都缺推都要；没蓝职业推面包）
function MW.FieldMarkDefault(f)
    local def = MW.DefaultKind()
    local mana = MW.WantsWater(myClass())
    f.defKind = def
    for k, b in pairs(f.kinds) do
        b.off = ((not mana) and k ~= "food") and true or false   -- 存 false 不存 nil
        if b.SetEnabled then b:SetEnabled(not b.off) end
        local lbl = L(KIND_LABEL[k][1], KIND_LABEL[k][2])
        if k == def then
            b:SetText("|cff33ff99" .. lbl .. "|r")
            if b.LockHighlight then b:LockHighlight() end
        else
            b:SetText(lbl)
            if b.UnlockHighlight then b:UnlockHighlight() end
        end
    end
end
function MW.ShowField(o)
    local f = MW.BuildField()
    MW.fieldCur = o
    local db, t = MW.FieldDB(), wall()
    db.last = t
    db.mages[o.who] = t
    for k, v in pairs(db.mages) do if type(v) ~= "number" or v > t or t - v > MW.FIELD_MAGE_CD then db.mages[k] = nil end end
    db.mages[o.who] = t
    f.text:SetText(MW.FieldText(o))
    MW.FieldMarkDefault(f)
    if f.text.GetStringHeight then
        local h = tonumber(f.text:GetStringHeight())
        if h then f:SetHeight(math.max(136, 98 + h)) end
    end
    f.age = 0
    f:Show()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
    return f
end
-- 事件 → 单位
function MW.OnFieldUnit(u)
    if not MW.Opt("fieldAsk") then return end
    pcall(MW.FieldCheck, u)
end
function MW.FieldRoster()
    if not MW.Opt("fieldAsk") or not MW.FieldGate() then return end
    for _, u in ipairs(groupUnits()) do
        if exists(u) and MW.FieldCheck(u) then return end
    end
end

local function autoSoon(reason, delay)
    if not MW.On() then return end
    if C_Timer and C_Timer.After then C_Timer.After(delay or 2, function() pcall(MW.AutoCheck, reason) end) else pcall(MW.AutoCheck, reason) end
end

-- ================= 法师：发 =================
-- 认「要吃喝」的话：返回 water, food（都 false = 不是）
-- 认「要吃喝」的话 / 「来密我的人」要跳过的私聊：11-13 第 5 期搬进登录加载的 DungeonChatCore.lua（法师吃喝没加载时副本组队也要用），同一个函数
MW.ParseAsk = DC.MageParseAsk
MW.SkipWhisper = DC.MageSkipWhisper

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

-- ---------- ⑥ 交易完成自动道谢（11-12 用户「交易完成自动感谢」；不是法师；细项 thank 默认开、不受总开关管）----------
--   开交易时对方是法师 → 记下来；交易中对方往交易栏放了东西 → 记「给了」；交易真完成（系统提示「交易完成」，
--   或双方都点了交易后窗口关上、没报背包满之类的错）→ 私聊一句谢谢（话术可在设置页「自动私信内容」改，key = mwThanks）
--   同一个法师 3 分钟只谢一次；战斗中 / 聊天锁定不发（MW.Send 管）；带不带 [GI组队助手] 跟招人页「带标识」
MW.THANK_CD = 180
MW.thanked = {}
local THANK_LINES = {
    { "谢谢法师老板的%s~ 祝你游戏愉快！", "Thanks for the %s! Have fun!" },
    { "收到%s啦，谢谢大佬~", "Got the %s - thank you!" },
    { "感谢老板的%s，好人一生平安~", "Thanks a lot for the %s!" },
}
function MW.ThankStart()
    MW.thankCtx = nil
    if not MW.Opt("thank") or MW.IsMage() then return end
    local who, cls = MW.TradeTarget()
    if cls == "MAGE" and who and who ~= "" then MW.thankCtx = { who = who } end
end
-- 对方交易栏里放了什么（法师吃喝分水 / 面包；别的东西只记「给了」）
function MW.ThankScan()
    local c = MW.thankCtx
    if not c then return end
    local got, water, food = false, false, false
    for i = 1, (tonumber(_G.MAX_TRADABLE_ITEMS) or 6) do
        local name = clean(call(GetTradeTargetItemInfo, i))
        if name then
            got = true
            local link = clean(call(GetTradeTargetItemLink, i))
            local id = link and tonumber(tostring(link):match("item:(%d+)"))
            local e = id and BY_ID[id]
            if e then
                for _, w in ipairs(MW.WATER) do if w == e then water = true end end
                for _, f in ipairs(MW.FOOD) do if f == e then food = true end end
            end
        end
    end
    if got then c.got, c.water, c.food = true, c.water or water, c.food or food end
end
function MW.ThankText(c)
    local what = (c.water and c.food) and L("吃喝", "food and water") or (c.water and L("水", "water")) or (c.food and L("面包", "food")) or L("东西", "stuff")
    local mine = ns.MyWhisper and ns.MyWhisper("mwThanks", { ["等级"] = unitLevel("player") })
    if mine and mine ~= "" then return mine end
    local r = THANK_LINES[math.random(#THANK_LINES)]
    return string.format(L(r[1], r[2]), what)
end
function MW.ThankDone()
    local c = MW.thankCtx
    MW.thankCtx = nil
    if not (c and c.got and not c.err) then return false end
    local t = now()
    if MW.thanked[c.who] and MW.thanked[c.who] <= t and t - MW.thanked[c.who] < MW.THANK_CD then return false end
    if not MW.Send(MW.ThankText(c), "WHISPER", c.who) then return false end
    MW.thanked[c.who] = t
    return true
end
function MW.OnThankEvent(e, a1, a2)
    local c = MW.thankCtx
    if not c then return end
    if e == "TRADE_TARGET_ITEM_CHANGED" then MW.ThankScan()
    elseif e == "TRADE_ACCEPT_UPDATE" then
        MW.ThankScan()
        c.both = (tonumber(clean(a1)) == 1 and tonumber(clean(a2)) == 1) or nil
    elseif e == "UI_INFO_MESSAGE" or e == "CHAT_MSG_SYSTEM" then
        local msg = clean((e == "UI_INFO_MESSAGE") and a2 or a1)
        if msg and _G.ERR_TRADE_COMPLETE and msg == ERR_TRADE_COMPLETE then MW.ThankDone() end
    elseif e == "UI_ERROR_MESSAGE" then
        -- 只认交易没成的那几条（背包满 / 取消 / 唯一物品超量）；别的红字（技能没好之类）不算
        local msg = clean(a2)
        for _, k in ipairs({ "ERR_TRADE_BAG_FULL", "ERR_TRADE_TARGET_BAG_FULL", "ERR_TRADE_CANCELLED", "ERR_TRADE_MAX_COUNT_EXCEEDED", "ERR_TRADE_TARGET_MAX_COUNT_EXCEEDED" }) do
            if msg and _G[k] and msg == _G[k] then c.err = true end
        end
    elseif e == "TRADE_CLOSED" then
        -- 双方都点了交易 → 窗口关 = 交易完成（「交易完成」提示有时比关窗晚到：等 0.5 秒，期间报错就不算）
        if c.both then
            if C_Timer and C_Timer.After then C_Timer.After(0.5, function() if MW.thankCtx == c then pcall(MW.ThankDone) end end)
            else MW.ThankDone() end
        elseif C_Timer and C_Timer.After then C_Timer.After(1, function() if MW.thankCtx == c then MW.thankCtx = nil end end)
        else MW.thankCtx = nil end
    end
end

-- 交易开 / 关（DungeonChat 的 TRADE_SHOW 转过来）
function MW.OnTradeShow()
    pcall(MW.ThankStart)   -- ⑥ 道谢不受总开关管
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
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetSize(22, 22); close:SetPoint("TOPRIGHT", 0, 0); f.closeBtn = close
    close:SetScript("OnClick", function()
        MW.orders = {}; MW.barPreview = nil; MW.RefreshBar()
        if f:IsShown() and not combat() then f:Hide() end
        -- 11-12 重构第 1 期：× 只是收起这一轮（下次有人要还会弹），说一声怎么彻底关 / 怎么挪（最多 3 次）
        local C = ns.SlashHint or "/gif"
        if ns.CloseHint then
            ns.CloseHint("mageBar", L("法师提醒条已收起：下次有人要吃喝还会弹出。不想要它 → " .. C .. " 吃喝 取消勾「有人要时弹提醒条」；位置在设置页「窗口与提醒」重置",
                "Request bar dismissed: it pops again on the next request. To turn it off: " .. C .. " water and untick the request bar; reset its position in Settings > Windows & alerts"))
        end
    end)
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
-- 11-12 重构第 1 期（设置页「窗口与提醒」）：提醒条平时没人要就不出，挪不了位置 → 给一个「摆出来」预览 + 重置位置。
--   ⛔ 提醒条上有安全施法按钮：战斗中不建、不显示、不挪（返回 false, "combat"）
function MW.PreviewBar()
    if not MW.IsMage() then return false, "notmage" end
    if combat() then return false, "combat" end
    local f = MW.BuildBar()
    if not f then return false, "combat" end
    MW.barPreview = true
    MW.UpdateCastSpells()
    if #MW.Orders() == 0 then
        f.list:SetText(L("（预览：现在没人要。按住拖到想放的位置，点 × 收起）", "(Preview: no requests right now. Drag to move, × to dismiss)"))
        f.stock:SetText(MW.StockText(MW.ScanBags()))
        f:SetHeight(84)
    end
    f:Show()
    return true
end
function MW.ResetBarPos()
    if combat() then return false, "combat" end
    DC.DB().mwBar = nil
    if MW.bar then MW.bar:ClearAllPoints(); MW.bar:SetPoint("TOP", UIParent, "TOP", 0, -160) end
    return true
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
        if MW.barPreview and MW.IsMage() then return false end   -- 预览中：总开关 / 提醒条关着也先不收（玩家正在摆位置）
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
        if MW.barPreview then return false end   -- 预览中（设置页「摆出来」）：没人要也先不收，等玩家点 ×
        if f:IsShown() then if combat() then MW.pendingBar = true else f:Hide() end end
        return false
    end
    MW.barPreview = nil
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
    -- 11-12 界面重构第 2 期：原设置页「法师吃喝」栏的两份副本并进这里（决定 4），一个开关只留一种叫法 → 用设置页那句（玩家已经认得）；「不受总开关管」写进鼠标提示
    { k = "thank", zh = "法师给了水 / 面包、交易完成后自动私聊道谢", en = "Whisper thanks after a mage trades you food / water",
      tipZh = "法师跟你交易、给了水或面包，交易完成后自动私聊他一句谢谢（话术在下面「法师给水后道谢」里改）。不受总开关管，默认开", tipEn = "Whispers thanks after a mage trades you food / water. Not tied to the master switch; on by default." },
    { k = "fieldAsk", zh = "野外 / 主城碰到法师、背包水不够时弹框问要不要密他（点了才发）", en = "Pop a prompt when a mage is nearby and you're low on water (only sends if you click)",
      tipZh = "不在副本 / 战场时，目标、鼠标指向、姓名板或队友里出现同阵营法师，你背包里能喝的水不到一组（战士 / 盗贼看面包）、他的等级造得出你能用的那档，就弹个小框问你要不要密他。点「要水 / 要面包 / 都要」才发私聊（不报数量，选过的下次默认它）。同一个法师 10 分钟内不管哪条路只密一次。战斗中不弹；同一个法师 30 分钟一次；两次弹框至少隔 5 分钟；框上点「今天别再提示」今天就不弹了",
      tipEn = "Outside instances: when a same-faction mage shows up (target, mouseover, nameplate or party) and you're short, a small prompt asks if you want to whisper them. Nothing is sent unless you click. Never in combat; once per mage per 30 min; at least 5 min between prompts." },
    { head = true, zh = "是法师：帮你发", en = "Mage: hand it out", mage = true },
    { k = "reply", zh = "队友要水时自动回一句", en = "Auto-reply when a party member asks" },
    { k = "giveBtn", zh = "交易窗下面出「一键放入」按钮", en = "Show a one-click \"put in\" button under the trade window" },
    { k = "bar", zh = "有人要时弹提醒条（带造水 / 造食按钮）", en = "Pop a request bar (with Conjure buttons) when someone asks" },
}
MW.OPT_ROWS = OPT_ROWS
-- 11-12 界面重构第 2 期（§6 拍板 4）：法师吃喝的设置做成右侧「组队」抽屉的第三个子页签 [任务组队][副本组队][法师吃喝]，
--   所有入口（/gi 吃喝、小地图右键、招人页按钮右键、野外弹框「设置」、设置页索引「前往」）都指到这里；
--   面板本身还是这个具名框体（GearInsightForeverMageWaterOpts），抽屉里挂进子页签那层；组队抽屉建不起来时照旧独立弹出（兜底）
function MW.BuildSettings()
    local f = MW.optFrame
    if not f then
        f = CreateFrame("Frame", "GearInsightForeverMageWaterOpts", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(430, 60 + 26 * (#OPT_ROWS + 1))
        f:SetFrameStrata("DIALOG"); if f.SetClampedToScreen then f:SetClampedToScreen(true) end   -- 从设置页 / 弹框打开时别出屏
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
        local function check(y, text, get, set, indent, tip)
            local c = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
            c:SetSize(24, 24); c:SetPoint("TOPLEFT", indent or 12, y)
            local fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); fs:SetPoint("LEFT", c, "RIGHT", 4, 0); fs:SetText(text)
            -- 11-12 用户截图：嵌进组队抽屉（约 420 宽）后长句冲出右边 → 右边对齐框边、单行放不下就省略，鼠标提示给全文
            fs:SetPoint("RIGHT", f, "RIGHT", -8, 0); fs:SetJustifyH("LEFT"); if fs.SetWordWrap then fs:SetWordWrap(false) end
            c.text, c.get = fs, get
            c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); MW.RefreshSettings() end)
            do
                c:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(text, 1, 0.82, 0, true)
                    if tip then GameTooltip:AddLine(tip, 1, 1, 1, true) end
                    GameTooltip:Show()
                end)
                c:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
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
                -- 11-12 重构第 1 期：弹框上点了「今天别再提示」后这里还显示勾着（设置页那项已经不勾）→ 两处口径统一：
                --   开着但今天静音 = 不勾 + 文字后面注明；重新勾上 = 撤销静音
                local c = check(y, L(row.zh, row.en), function()
                    if k == "fieldAsk" and MW.FieldMuted() then return false end
                    return MW.Opt(k)
                end, function(v)
                    MW.SetOpt(k, v)
                    -- 野外提示：重新勾上 = 撤销「今天别再提示」；取消勾 = 开着的框收起
                    if k == "fieldAsk" then if v then MW.FieldMute(false) else MW.HideField() end end
                end, 30, row.tipZh and L(row.tipZh, row.tipEn or row.tipZh))
                c.key, c.label = k, L(row.zh, row.en)
                y = y - 26
            end
        end
        -- 11-12 第 2 期：原设置页「自动私信内容」里的「法师给水后道谢」挪到这里（存 ns.db.whispers.mwThanks，键不变）
        local wl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); wl:SetPoint("TOPLEFT", 16, y - 5)
        wl:SetText(L("法师给水后道谢：", "Thanks to mage:"))
        local we = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        we:SetSize(250, 20); we:SetPoint("TOPLEFT", ns.zh and 140 or 160, y - 2)
        we:SetAutoFocus(false); we:SetMaxLetters(200)
        local function wget() return ns.db.whispers and ns.db.whispers.mwThanks end
        local function wsave(self)
            local v = (self:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
            ns.db.whispers = ns.db.whispers or {}
            ns.db.whispers.mwThanks = (v ~= "") and v or nil
        end
        we:SetScript("OnEnterPressed", function(self) wsave(self); self:ClearFocus() end)
        we:SetScript("OnEscapePressed", function(self) self:SetText(wget() or ""); self:ClearFocus() end)
        we:SetScript("OnEditFocusLost", wsave)
        we:SetScript("OnShow", function(self) self:SetText(wget() or "") end)
        we:SetText(wget() or "")
        f.whisper = we
        y = y - 28
        f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.note:SetPoint("TOPLEFT", 14, y - 4); f.note:SetWidth(400); f.note:SetJustifyH("LEFT")
        f.note:SetText(L("施法、放进交易栏、确认交易都要你自己点（暴雪规定）；发出去的话带不带「", "Casting, putting items in and confirming trade need your click; the \"")
            .. DC.TAG .. L("」跟招人页「带标识」走", "\" prefix follows the Tag button"))
        f:SetHeight(-y + 30)
        f.closeBtn = close
        MW.optFrame = f
    end
    return f
end

-- 挂进组队抽屉的「法师吃喝」子页签那层（QuestMates.lua QM.SetMode("mage") 调）：不能拖、不出关闭钮、不画自己的边框
function MW.EmbedSettings(pane)
    local f = MW.BuildSettings()
    if not pane then return f end
    if f.SetParent then f:SetParent(pane) end
    f.embedded = true
    f:ClearAllPoints(); f:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0); f:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, 0)
    -- 11-12 用户截图叠层：独立小窗是 DIALOG 层，嵌进抽屉要跟抽屉同层、比底板高一级
    local pst = pane.GetFrameStrata and pane:GetFrameStrata()
    if pst and f.SetFrameStrata then f:SetFrameStrata(pst) end
    local plv = pane.GetFrameLevel and pane:GetFrameLevel()
    if plv and f.SetFrameLevel then f:SetFrameLevel(plv + 1) end
    if f.SetBackdropBorderColor then f:SetBackdropBorderColor(0, 0, 0, 0) end
    if f.SetMovable then f:SetMovable(false) end
    if f.closeBtn then f.closeBtn:Hide() end
    MW.RefreshSettings()
    f:Show()
    return f
end

function MW.OpenSettings(anchor)
    -- 先走组队抽屉的子页签（会打开主面板 + 右侧「组队」抽屉）
    local QM = ns.QM
    if QM and QM.SetMode and ns.OpenGroupDrawer then
        pcall(ns.OpenGroupDrawer)
        local d = QM.drawer
        if d and d:IsShown() then
            pcall(QM.SetMode, "mage")
            local f = MW.optFrame
            if f and rawget(f, "embedded") and f:IsShown() then return f end
        end
    end
    -- 兜底：独立小窗（和第 2 期以前一样）
    local f = MW.BuildSettings()
    if rawget(f, "embedded") then
        if f.SetParent then f:SetParent(UIParent) end
        f.embedded = nil
        f:SetFrameStrata("DIALOG")
        if f.SetMovable then f:SetMovable(true) end
        if f.closeBtn then f.closeBtn:Show() end
        if f.SetBackdropBorderColor then f:SetBackdropBorderColor(1, 0.82, 0, 0.8) end
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
    for _, c in ipairs(f.checks) do
        c:SetChecked(c.get() and true or false)
        if rawget(c, "key") == "fieldAsk" then
            local muted = MW.Opt("fieldAsk") and MW.FieldMuted()
            c.text:SetText(c.label .. (muted and ("  |cffff9933" .. L("（今天已静音，重新勾上恢复）", "(muted today - tick to resume)") .. "|r") or ""))
        end
    end
end

-- 11-12 第 2 期：设置页「窗口与提醒」那行点了关闭 / 解除静音（或别处改了同一个开关）→ 子页签里的勾跟着刷
if ns.OnSettingsRefresh then ns.OnSettingsRefresh(function() if MW.optFrame then MW.RefreshSettings() end end) end

-- 招人页「法师吃喝」按钮的鼠标提示（DungeonChat 调）
function MW.Tip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:AddLine(L("法师吃喝", "Mage food & water") .. (MW.On() and L("（开）", " (on)") or L("（关）", " (off)")), 1, 0.82, 0)
    GameTooltip:AddLine(L("左键：开 / 关　右键：细项设置（/gi 吃喝 也行）", "Left-click: on / off   Right-click: options (/gi water)"), 0.6, 0.9, 1, true)
    local mage = MW.IsMage()
    GameTooltip:AddLine(L("不是法师 → 帮你要", "Not a mage - asks for you") .. ((not mage) and L("（当前角色）", " (this character)") or ""), 1, 0.82, 0)
    GameTooltip:AddLine(L("副本里跟法师开交易，或进副本 / 队伍满 5 人时队里有法师，背包吃喝不到一组就私聊他要，按你的等级报能吃的水和面包；战士 / 盗贼只要面包；每个法师 10 分钟最多一次", "Whispers the mage for the right tier when you trade them, enter a dungeon or the party fills - only if you're short, max once per 10 min per mage"), 1, 1, 1, true)
    GameTooltip:AddLine(L("野外遇到法师（不受这个开关管，默认开）", "Out in the world (separate from this switch, on by default)"), 1, 0.82, 0)
    GameTooltip:AddLine(L("不在副本时碰到同阵营法师、你的水（战士 / 盗贼看面包）不到一组，弹个小框问要不要密他；点「要水 / 要面包 / 都要」才发（不报数量）。关：右键细项里取消「野外 / 主城碰到法师、背包水不够时弹框…」", "When a mage is nearby and you're short, a small prompt asks if you want to whisper them - nothing is sent unless you click. Turn off in the options (right-click)"), 1, 1, 1, true)
    GameTooltip:AddLine(L("是法师 → 帮你发", "Mage - hands it out") .. (mage and L("（当前角色）", " (this character)") or ""), 1, 0.82, 0)
    GameTooltip:AddLine(L("队友要水自动回一句并弹提醒条（带造水 / 造食按钮）；开交易时交易窗下面出「一键放入」，点一下放好水和面包，你再点「交易」确认", "Auto-replies and pops a request bar with Conjure buttons; a one-click button under the trade window puts the right stacks in - then you click Trade"), 1, 1, 1, true)
    GameTooltip:Show()
end

-- ---------- 事件 ----------
-- 11-13 界面重构第 5 期：原来登录就注册全部 21 个事件 → 按开关只注册用得上的那一半（处理函数一字没改，没注册的那些本来进来也是第一行就回）：
--   不是法师：野外弹框 fieldAsk（默认开）→ FIELD；交易完成道谢 thank（默认开）→ THANK；总开关 rec.mageAsk → ASK（进副本 / 满员自动要、交易时要）
--   是法师：总开关开着 → GIVE（自动回话 / 提醒条 / 一键放入）；关着 = 一个都不注册
--   交易开着 / 有待办（脱战再藏按钮、脱战再弹提醒条、脱战再自动要）/ 提醒条开着时，相关事件先留着，办完再重算
--   TRADE_SHOW 不在这里：在 DungeonChatCore.lua（DC.SyncCore 问 MW.WantTrade）转给 MW.OnTradeShow
MW.EVENTS = {
    field = { "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "PLAYER_REGEN_DISABLED", "GROUP_ROSTER_UPDATE",
        "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" },
    thank = { "TRADE_CLOSED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_ACCEPT_UPDATE", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE", "CHAT_MSG_SYSTEM" },
    ask = { "TRADE_CLOSED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED" },
    give = { "TRADE_CLOSED", "CHAT_MSG_WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
        "BAG_UPDATE_DELAYED", "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED" },
}
-- 原来的全集（21 个）
MW.ALL_EVENTS = { "TRADE_CLOSED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED",
    "CHAT_MSG_WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "BAG_UPDATE_DELAYED", "SPELLS_CHANGED",
    "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "PLAYER_REGEN_DISABLED",
    "TRADE_TARGET_ITEM_CHANGED", "TRADE_ACCEPT_UPDATE", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE", "CHAT_MSG_SYSTEM" }
-- 开交易时要不要 MW.OnTradeShow（DungeonChatCore.lua 的 TRADE_SHOW 问这里）
function MW.WantTrade()
    if not ns.db then return false end
    local mage, on = MW.IsMage(), MW.On()
    if on then return true end
    return (not mage) and MW.Opt("thank") and true or false
end
-- 现在该注册哪些 → { [事件] = true }
function MW.WantedEvents()
    local want = {}
    if not ns.db then return want end
    local mage, on = MW.IsMage(), MW.On()
    local function add(list) for _, e in ipairs(list) do want[e] = true end end
    if not mage and MW.Opt("fieldAsk") then add(MW.EVENTS.field) end
    if not mage and MW.Opt("thank") then add(MW.EVENTS.thank) end
    if not mage and on then add(MW.EVENTS.ask) end
    if mage and on then add(MW.EVENTS.give) end
    -- 办到一半的事别断：交易开着 / 道谢在等交易结果 → 交易那几个；脱战再办的 → 脱战事件；提醒条开着 → 背包变化（刷新 / 收起）
    if MW.tradeOpen or MW.thankCtx then add(MW.EVENTS.thank) end
    if MW.pendingHide or MW.pendingBar or MW.pendingAuto then want.PLAYER_REGEN_ENABLED = true end
    if MW.bar and MW.bar.IsShown and MW.bar:IsShown() then want.BAG_UPDATE_DELAYED = true end
    if MW.fieldFrame and MW.fieldFrame.IsShown and MW.fieldFrame:IsShown() then add(MW.EVENTS.field) end
    return want
end
local ev = CreateFrame("Frame")
MW.ev = ev
function MW.SyncEvents()
    local want = MW.WantedEvents()
    for _, e in ipairs(MW.ALL_EVENTS) do
        if want[e] then pcall(ev.RegisterEvent, ev, e) else pcall(ev.UnregisterEvent, ev, e) end
    end
    MW.wanted = want
    if DC.SyncCore then pcall(DC.SyncCore) end
    return want
end
ev:SetScript("OnEvent", function(_, e, a1, a2)
    -- ⑤ 野外遇到法师：来一个单位查一个（开关关了 OnFieldUnit 第一行就回）
    if e == "PLAYER_TARGET_CHANGED" then MW.OnFieldUnit("target"); return
    elseif e == "UPDATE_MOUSEOVER_UNIT" then MW.OnFieldUnit("mouseover"); return
    elseif e == "NAME_PLATE_UNIT_ADDED" then if type(a1) == "string" then MW.OnFieldUnit(a1) end; return
    elseif e == "PLAYER_REGEN_DISABLED" then if MW.fieldFrame and MW.fieldFrame:IsShown() then MW.HideField() end; return end
    if e == "TRADE_TARGET_ITEM_CHANGED" or e == "TRADE_ACCEPT_UPDATE" or e == "UI_INFO_MESSAGE" or e == "UI_ERROR_MESSAGE" or e == "CHAT_MSG_SYSTEM" then
        pcall(MW.OnThankEvent, e, a1, a2); return
    end
    if e == "TRADE_CLOSED" then pcall(MW.OnThankEvent, e); pcall(MW.OnTradeClosed)
    elseif e == "CHAT_MSG_WHISPER" or e == "CHAT_MSG_PARTY" or e == "CHAT_MSG_PARTY_LEADER" or e == "CHAT_MSG_RAID" or e == "CHAT_MSG_RAID_LEADER" then
        pcall(MW.OnAsk, a1, a2)
    elseif e == "PLAYER_ENTERING_WORLD" or e == "ZONE_CHANGED_NEW_AREA" then
        -- 出了副本：这个副本的「问过了」清掉，下次再进同名副本还能再要
        if not inDungeon() then MW.autoKeys = {} end
        if inAnyInstance() and MW.fieldFrame and MW.fieldFrame:IsShown() then MW.HideField() end
        autoSoon("enter", MW.ENTER_DELAY)
    elseif e == "GROUP_ROSTER_UPDATE" then
        autoSoon("roster", 2)
        pcall(MW.FieldRoster)
    elseif e == "PLAYER_REGEN_ENABLED" then
        if MW.pendingHide then MW.pendingHide = nil; if not MW.tradeOpen and MW.giveBtn then MW.giveBtn:Hide() end end
        if MW.pendingBar then MW.pendingBar = nil; pcall(MW.RefreshBar, true) end
        if MW.pendingAuto then local r = MW.pendingAuto; MW.pendingAuto = nil; autoSoon(r, 2) end
    elseif e == "BAG_UPDATE_DELAYED" then
        if MW.bar and MW.bar:IsShown() then pcall(MW.RefreshBar) end
        if MW.tradeOpen and MW.giveBtn and MW.giveBtn:IsShown() then pcall(MW.RefreshGive) end
    elseif e == "SPELLS_CHANGED" then pcall(MW.UpdateCastSpells) end
    -- 交易收尾 / 脱战补办完：临时留着的事件按开关收回去
    if e == "TRADE_CLOSED" or e == "PLAYER_REGEN_ENABLED" then pcall(MW.SyncEvents) end
end)
MW._event = ev:GetScript("OnEvent")   -- 测试用

-- /gi 吃喝 · /gi water：打开设置
ns.ExtraSlash = ns.ExtraSlash or {}
for _, c in ipairs({ "吃喝", "water", "mw" }) do ns.ExtraSlash[c] = function() MW.OpenSettings() end end

-- 按需加载：加载时登录早就过了 → 现在按开关注册（登录时随组队子插件一起加载也走这里；存档还没好时由 ns.GroupSync 补）
if ns.db then pcall(MW.SyncEvents) end
