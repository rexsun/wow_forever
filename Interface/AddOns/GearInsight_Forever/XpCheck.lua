-- HOLD：经验加成检查（11-09 用户「同步构思一个这个经验 buff 检查器……露营的 buff、睡袋、包里有没有、任务做不做、食物 buff……
--   一个是检查有没有，二是检查还有多长时间要补，给出很好的提示，整个功能都可以开关」→ 方案确认「可以，开工」）
--   查五类：帐篷经验（含「强化休息」冷却）/ 营火 / 睡袋（背包、精神饱满层数、物品冷却、任务线进度）/ 经验食物（buff、包里、能做）/ 休息经验
--   每项：有没有 + 剩多久 + 缺了怎么补。提示三种：
--     ① 小窗（默认只在缺东西或快到期时自动出来，全齐自己收起；可改一直显示）；点一行出「怎么补」
--     ② 到期提醒：剩 10 分钟 / 2 分钟 / 掉了各一次，屏幕中间一行；战斗中不弹（出战斗补报），副本 / 战场里不提营地类
--     ③ 登录 / 升级 / 出副本聊天框一行汇总；/gi xp 看详情
--   ⛔ 不替玩家吃东西 / 铺睡袋（受保护操作，也不该替）；不发任何密语。
--   已知 ID（用户存档 camp.probe 11-08）：营火在附近 1283391、温馨营火 1229739、强化休息 1229451；睡袋物品 211527。
--   帐篷 = 露营增益 1229741（11-09 探针）；睡袋「精神饱满」/ 经验食物 的 buff ID 还没定：先按名字 + 鼠标提示里带「经验」认，探针把真实 ID 记进存档（/gi xp probe）
local _, ns = ...
local L = ns.L

local XC = {}
ns.XpCheck = XC

XC.IDS = {
    lockout = { [1229451] = true },                     -- 强化休息：1 小时内拿不到帐篷经验
    fire = { [1229739] = true, [1283391] = true },      -- 温馨营火 / 营火在附近
    tent = { [1229741] = true },                        -- 露营增益（11-09 用户 /gi xp probe：29m，和强化休息同时挂）
    bag = {}, food = {},                                -- 探针定了再填
}
XC.NAMES = {
    lockout = { "强化休息", "強化休息" },
    fire = { "营火", "營火", "[Cc]ampfire" },
    tent = { "奖励经验", "獎勵經驗", "露营", "露營", "[Tt]ent", "[Cc]amping" },
    bag = { "精神饱满", "精神飽滿", "[Ww]ell [Rr]ested" },
    food = { "进食充分", "進食充分", "[Ww]ell [Ff]ed" },
}
XC.BAG_ITEM = 211527          -- 舒适的睡袋
XC.WOOD, XC.FLINT = 4470, 4471 -- 普通木柴 / 燧石和火绒
XC.BAG_STACKS = 3
-- 11-09 用户「搞成正式服那种，平时透明，快没了就弹出来提醒（15分钟）帐篷5分钟，睡袋看三层」+「还有5分钟开始高亮，10分钟开始出现」：
--   show = 剩多少秒浮出来（提醒条出现 + 聊天框提醒一次），hi = 剩多少秒开始高亮闪（再提醒一次）；睡袋不满 3 层直接出来并高亮
XC.TH = { default = { show = 900, hi = 300 }, tent = { show = 600, hi = 300 }, food = { show = 180, hi = 60 } }   -- 11-09「食物还剩3分钟再提醒」
local function th(k) return XC.TH[k] or XC.TH.default end
XC.Th = th
XC.KEYS = { "tent", "fire", "bag", "food", "rest" }
XC.TITLE = {
    tent = { "帐篷经验", "Tent XP" }, fire = { "营火", "Campfire" }, bag = { "睡袋", "Sleeping bag" },
    food = { "经验食物", "XP food" }, rest = { "休息经验", "Rested XP" },
}
XC.ICON = {
    tent = "Interface\\Icons\\Spell_Nature_Tranquility", fire = "Interface\\Icons\\Spell_Fire_Fire", bag = "Interface\\Icons\\Spell_Nature_Sleep",
    food = "Interface\\Icons\\INV_Misc_Food_15", rest = "Interface\\Icons\\Spell_Nature_Sleep",
}

local function now() return GetTime and GetTime() or 0 end
local function secret(v) return ns.Secret(v) end
local function str(v) return type(v) == "string" and not secret(v) and v ~= "" and v or nil end
local function num(v) if v == nil or secret(v) then return nil end return tonumber(v) end
local function T(k) local t = XC.TITLE[k]; return L(t[1], t[2]) end

function XC.DB()
    ns.db.xpcheck = ns.db.xpcheck or {}
    return ns.db.xpcheck
end
local function opt(k, def)
    local v = XC.DB()[k]
    if v == nil then return def end
    return v
end
function XC.Enabled() return opt("on", true) end
function XC.ItemOn(k) local t = XC.DB().items; return not (t and t[k] == false) end
function XC.Set(k, v)
    XC.DB()[k] = v
    XC.Update()
end
function XC.SetItem(k, v)
    local d = XC.DB()
    d.items = d.items or {}
    if v then d.items[k] = nil else d.items[k] = false end
    XC.Update()
end

local function anyMatch(s, pats)
    if not s then return false end
    for _, p in ipairs(pats) do if s:find(p) then return true end end
    return false
end

-- ---------- 读 buff ----------
-- 返回 { {name, id, left(秒，nil=不限时), stacks, xp(提示里带经验)} ... }
local function auraTip(i, filter)
    if not (C_TooltipInfo and C_TooltipInfo.GetUnitAura) then return nil end
    local ok, d = pcall(C_TooltipInfo.GetUnitAura, "player", i, filter)
    if not ok or type(d) ~= "table" or type(d.lines) ~= "table" then return nil end
    local t = {}
    for _, ln in ipairs(d.lines) do t[#t + 1] = str(ln.leftText) or "" end
    return table.concat(t, " ")
end
function XC.Auras()
    local out = {}
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        for i = 1, 40 do
            local name, sid, exp, cnt, icon
            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
                if not ok or not a then break end
                name, sid, exp, cnt, icon = a.name, a.spellId, a.expirationTime, a.applications, a.icon
            elseif UnitAura then
                local ok, n, ic, c, _, _, e, _, _, _, s = pcall(UnitAura, "player", i, filter)
                if not ok or not n then break end
                name, sid, exp, cnt, icon = n, s, e, c, ic
            else break end
            name, sid, exp, cnt = str(name), num(sid), num(exp), num(cnt)
            local left = (exp and exp > 0) and math.max(0, exp - now()) or nil
            local a = { name = name, id = sid, left = left, stacks = cnt or 0, icon = (icon and not secret(icon)) and icon or nil }   -- 图标用增益自己的（11-09 截图：帐篷图标客户端里没有，空着）
            -- 读鼠标提示有开销：名字 / ID 已经认出是营火 / 睡袋 / 帐篷 / 强化休息的就不读，只有剩下的才看提示里带不带「经验」
            local known = false
            for _, k in ipairs({ "lockout", "fire", "bag" }) do
                if (sid and XC.IDS[k][sid]) or anyMatch(name, XC.NAMES[k]) then known = true; break end
            end
            -- GI-234 玩家「获得了露营增益，但是没有经验加成」：名字像露营的不一定带经验 → 帐篷类也读提示，
            --   提示读到了就按这一刻写没写经验算（不拿存档里记过的顶，免得同名的没经验效果被当成有）
            if not known and ((sid and XC.IDS.tent[sid]) or anyMatch(name, XC.NAMES.tent)) then
                known = true
                local tip = auraTip(i, filter)
                tip = (tip and tip:gsub("%s", "") ~= "") and tip or nil
                local key = sid or name
                local seen = XC.DB().xpAura
                local hit = tip and (tip:find("经验") or tip:find("經驗") or tip:lower():find("experience")) and true or false
                if hit and key then XC.DB().xpAura = seen or {}; XC.DB().xpAura[key] = true end
                a.tipRead = tip and true or false
                a.xp = hit or (not tip and key and seen and seen[key] and true) or false
            end
            if not known then
                -- 11-09 用户截图「错误报」：食物还剩 2 分钟却报「经验食物没了」—— 提示偶尔读不到（空 / 没加载好），
                --   这一刻食物就认不出来。读到过带「经验」的法术 ID / 名字记下来（存档里），之后提示读不到时按记下的算
                local key = sid or name
                local seen = XC.DB().xpAura
                local tip = auraTip(i, filter)
                local hit = tip and tip ~= "" and (tip:find("经验") or tip:find("經驗") or tip:lower():find("experience"))
                if hit and key then
                    XC.DB().xpAura = seen or {}
                    XC.DB().xpAura[key] = true
                end
                a.xp = (hit or (key and seen and seen[key])) and true or false
            end
            out[#out + 1] = a
        end
    end
    return out
end

local function classify(a)
    for _, k in ipairs({ "lockout", "fire", "bag", "tent", "food" }) do
        local byId = a.id and XC.IDS[k][a.id]
        if byId or anyMatch(a.name, XC.NAMES[k]) then
            if k == "tent" then
                -- GI-234：按 ID 认的，提示读到了却没写经验就不算；只靠名字的，得写着经验（读不到按之前认出过的算）
                if (byId and not (a.tipRead and not a.xp)) or (not byId and a.xp) then return k end
            elseif k ~= "food" or a.xp then return k end
        end
    end
    if a.xp then return "food" end   -- 提示里带「经验」但认不出来的：多半是食物 / 其他经验加成，归到食物那行
    return nil
end

-- 探针：带「经验」或认出来的增益，记 ID / 名字 / 持续时间，定 ID 用
local function probe(a, k)
    local d = XC.DB()
    d.probe = d.probe or {}
    local line = string.format("%s %s:%s %s", k or "?", tostring(a.id or 0), a.name or "?", a.left and math.floor(a.left / 60 + 0.5) .. "m" or "-")
    local key = line:match("^(%S+ [^ ]+)")
    for i, l in ipairs(d.probe) do if l:match("^(%S+ [^ ]+)") == key then d.probe[i] = line; return end end
    if #d.probe >= 40 then table.remove(d.probe, 1) end
    d.probe[#d.probe + 1] = line
end

-- ---------- 背包 / 技能 ----------
local function bag(id) local P = ns.Prof; return (P and P.BagCount and P.BagCount(id)) or 0 end
local function level() return num(UnitLevel and UnitLevel("player")) or 1 end
local function maxLevel() return (num(GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60) end
local function cookRank()
    local P = ns.Prof
    if not (P and P.Skills) then return nil end
    local ok, sk = pcall(P.Skills)
    local c = ok and type(sk) == "table" and sk.cooking
    return c and c.r or nil
end
local function itemCD(id)
    local f = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not f then return 0 end
    local ok, s, d = pcall(f, id)
    s, d = ok and num(s), ok and num(d)
    if not s or not d or s == 0 or d <= 1.5 then return 0 end
    return math.max(0, s + d - now())
end
-- 物品名：客户端缓存里有就用；没缓存（刚登录常见）用我们自己的名字，别显示成数字
local NAMES = { [4470] = { "普通木柴", "Simple Wood" }, [4471] = { "燧石和火绒", "Flint and Tinder" } }
local function itemName(id, zh, en)
    local n = ns.ItemInfo and ns.ItemInfo(id)
    if str(n) then return n end
    if zh then return L(zh, en or zh) end
    if NAMES[id] then return L(NAMES[id][1], NAMES[id][2]) end
    local P = ns.Prof
    local pn = P and P.ItemName and P.ItemName(id)
    if pn and pn ~= tostring(id) then return pn end
    return "#" .. id
end

-- 经验食物：配方成品（ProfRecipes[7]）；包里有的 + 能做的（烹饪够、材料齐）
-- 11-13 重构第 4 期：专业大表 / 配方库按需加载 → 经验食物清单和成品物品读常驻的 ProfCoreData.lua（同一份数据抽出来的）
function XC.Foods()
    local D = ns.ProfCore
    local have, make = {}, {}
    if not (D and D.foods) then return have, make end
    local lv, ck = level(), cookRank()
    for _, f in ipairs(D.foods) do
        local item = ns.ProfFoodItem and ns.ProfFoodItem(f.sp)
        if item and (f.use or 1) <= lv then
            local n = bag(item)
            if n > 0 then have[#have + 1] = { item = item, n = n, use = f.use or 1, f = f } end
            if ck and f.learn <= ck then
                local short = {}
                for _, m in ipairs(f.m or {}) do
                    local b = bag(m[1])
                    if b < m[2] then short[#short + 1] = { m[1], m[2] - b } end
                end
                make[#make + 1] = { item = item, use = f.use or 1, f = f, short = short }
            end
        end
    end
    local function by(a, b) if a.use ~= b.use then return a.use > b.use end return a.item < b.item end
    table.sort(have, by)
    table.sort(make, function(a, b)
        if (#a.short == 0) ~= (#b.short == 0) then return #a.short == 0 end
        return by(a, b)
    end)
    return have, make
end

local function sleepChain()
    for _, c in ipairs(ns.SideChainsData or {}) do if c.item == XC.BAG_ITEM then return c end end
end

local function fmt(sec)
    if not sec then return "" end
    sec = math.floor(sec)
    if sec >= 3600 then return string.format("%d:%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
    if sec >= 60 then return string.format(L("%d 分钟", "%dm"), math.floor(sec / 60 + 0.5)) end
    return string.format(L("%d 秒", "%ds"), sec)
end
XC.Fmt = fmt

local function inInstance()
    if not IsInInstance then return false end
    local ok, inst = pcall(IsInInstance)
    return ok and inst and true or false
end

-- ---------- 核心：算出每项状态 ----------
-- 每项 { key, st = "ok" / "warn" / "miss" / "info", text = 一行, how = { 怎么补… }, left = 秒, action = 函数 }
function XC.Check()
    local res = {}
    local lv = level()
    if lv >= maxLevel() then return res, true end
    local got = {}
    for _, a in ipairs(XC.Auras()) do
        local k = classify(a)
        if k then
            local g = got[k]
            if not g or (a.left or 1e9) > (g.left or 1e9) then got[k] = a end
            probe(a, k)
        elseif a.xp then probe(a, nil) end
    end
    local wild = not inInstance()
    local function add(r) if XC.ItemOn(r.key) then res[#res + 1] = r end end
    local function timed(key, a, label)
        local t = th(key)
        local warn = a.left and a.left <= t.show
        return { key = key, st = warn and "warn" or "ok", left = a.left, hi = (a.left and a.left <= t.hi) or nil, icon = a.icon, stacks = a.stacks,
            text = label .. (a.left and ("  " .. L("剩 ", "") .. fmt(a.left)) or "") }
    end

    -- 帐篷经验
    if got.tent then
        add(timed("tent", got.tent, L("帐篷经验加成中", "Tent XP active")))
    elseif got.lockout then
        add({ key = "tent", st = "info", left = got.lockout.left,
            text = L("帐篷经验冷却中", "Tent XP on cooldown") .. (got.lockout.left and ("  " .. L("还剩 ", "") .. fmt(got.lockout.left)) or ""),
            how = { L("「强化休息」：1 小时内帐篷给不了经验，冷却完再去蹭", "Enhanced rest: no tent XP for 1 hour; come back after it ends") } })
    elseif wild then
        add({ key = "tent", st = "miss", text = L("没有帐篷经验", "No tent XP"),
            how = { L("附近有人放「资深冒险者的探险帐篷」就鼠标指一下，插件弹窗帮你请求进队", "Mouse over someone's adventurer's tent - the addon offers to ask for an invite"),
                L("进队后在帐篷旁坐下（按 X）满 60 秒才拿到经验", "Once grouped, sit (X) next to the tent for 60 seconds") } })
    end

    -- 营火
    if got.fire then
        add({ key = "fire", st = "ok", left = got.fire.left, text = L("在营火边", "By a campfire") .. (got.fire.left and ("  " .. L("剩 ", "") .. fmt(got.fire.left)) or "") })
    elseif wild then
        local ck = cookRank()
        local how = {}
        if ck then
            local w, f = bag(XC.WOOD), bag(XC.FLINT)
            if w > 0 and f > 0 then
                how[#how + 1] = L("包里有木柴和燧石：在安全的地方生火坐下就有", "You have wood and flint: light a fire and sit down")
            else
                local miss = {}
                if f == 0 then miss[#miss + 1] = itemName(XC.FLINT) end
                if w == 0 then miss[#miss + 1] = itemName(XC.WOOD) end
                how[#how + 1] = L("自己生火还缺：", "To light one you need: ") .. table.concat(miss, L("、", ", ")) .. L("（杂货商有卖）", " (trade goods vendor)")
            end
        else
            how[#how + 1] = L("没学烹饪：找队友的营火，或学烹饪自己生火（燧石和火绒 + 普通木柴）", "No Cooking: use a party member's fire, or learn Cooking (flint + wood)")
        end
        add({ key = "fire", st = "miss", text = L("不在营火边", "No campfire"), how = how })
    end

    -- 睡袋
    local bagN = bag(XC.BAG_ITEM)
    if got.bag then
        local s = math.max(1, got.bag.stacks or 1)
        local r = timed("bag", got.bag, string.format(L("精神饱满 %d/%d 层", "Well rested %d/%d"), s, XC.BAG_STACKS))
        if s < XC.BAG_STACKS then
            r.st = "warn"; r.hi = true
            r.how = { L("再躺几分钟叠满 3 层（每满 1 分钟 1 层）", "Lie in the bag a few more minutes for 3 stacks") }
        end
        add(r)
    elseif bagN > 0 then
        local cd = itemCD(XC.BAG_ITEM)
        if cd > 0 then
            add({ key = "bag", st = "info", left = cd, text = L("睡袋冷却中", "Bag on cooldown") .. "  " .. L("还剩 ", "") .. fmt(cd),
                how = { L("冷却好了再铺；队友的睡袋也能躺", "Wait for the cooldown, or use a party member's bag") } })
        elseif wild then
            add({ key = "bag", st = "miss", text = L("睡袋可以铺了", "Sleeping bag ready"),
                how = { L("找个安全地方铺开（读条 15 秒），躺 3 分钟叠满 3 层，经验 +3%，持续 2 小时", "Deploy it somewhere safe (15 s cast), lie 3 minutes for 3 stacks: +3% XP for 2 hours") } })
        end
    elseif lv >= 14 then
        local c = sleepChain()
        local txt, how = L("还没有睡袋", "No sleeping bag yet"), {}
        if c and ns.SideChains and ns.SideChains.Progress then
            local ok, _, n, total = pcall(ns.SideChains.Progress, c)
            if ok and total and total > 0 then
                txt = txt .. string.format(L("  任务线 %d/%d", "  quest line %d/%d"), n, total)
                how[#how + 1] = L("点这一行打开睡袋任务线步骤", "Click to open the sleeping bag quest steps")
            end
        end
        how[#how + 1] = L("做完任务线拿「舒适的睡袋」：躺满 3 分钟经验 +3%，持续 2 小时", "Finish the quest line for the Cozy Sleeping Bag: +3% XP for 2 hours")
        add({ key = "bag", st = "miss", text = txt, how = how,
            action = c and ns.SideChains and ns.SideChains.Show and function() ns.SideChains.Show(c) end or nil })
    end

    -- 经验食物
    if got.food then
        add(timed("food", got.food, (got.food.name or L("经验食物", "XP food")) .. L(" 生效中", " active")))
    else
        local have, make = XC.Foods()
        local how = {}
        if have[1] then
            how[#how + 1] = L("包里有：", "In your bags: ") .. itemName(have[1].item, have[1].f.zh, have[1].f.en) .. " ×" .. have[1].n .. L("，吃一个", " - eat one")
        end
        for i = 1, math.min(2, #make) do
            local m = make[i]
            if #m.short == 0 then
                how[#how + 1] = L("营火边能做：", "Can cook at a fire: ") .. itemName(m.item, m.f.zh, m.f.en) .. L("（材料齐了）", " (mats ready)")
            else
                local s = {}
                for _, x in ipairs(m.short) do s[#s + 1] = itemName(x[1]) .. "×" .. x[2] end
                how[#how + 1] = L("能做 ", "Can cook ") .. itemName(m.item, m.f.zh, m.f.en) .. L("，还缺 ", ", need ") .. table.concat(s, L("、", ", "))
            end
        end
        if #how == 0 then how[1] = L("学烹饪做经验食物，或拍卖行 / 队友那里买", "Learn Cooking for XP food, or buy it from the AH / friends") end
        add({ key = "food", st = "miss", text = have[1] and L("没吃经验食物（包里有）", "No XP food (you have some)") or L("没吃经验食物", "No XP food"), how = how })
    end

    -- 休息经验
    local ex = num(GetXPExhaustion and GetXPExhaustion())
    local mx = num(UnitXPMax and UnitXPMax("player"))
    if mx and mx > 0 then
        local pct = math.floor((ex or 0) / mx * 100 + 0.5)
        local resting = IsResting and IsResting() and true or false
        if pct >= 140 then
            add({ key = "rest", st = "warn", pct = pct, text = string.format(L("休息经验 %d%%（快满了）", "Rested %d%% (almost full)"), pct),
                how = { L("休息经验最多攒到 150%，满了就浪费：先去打怪把它用掉", "Rested XP caps at 150% - go use it before it's wasted") } })
        elseif pct > 0 then
            -- 11-09 用户「最高该有多少」「能提示吗」：提示里写上限 + 怎么攒 + 攒满还要多久（经典规则：旅店 / 主城 / 睡袋下线每 8 小时 +5%，野外 1/4）
            local hrs = math.ceil((150 - pct) / 5 * 8)
            local full = hrs >= 48 and string.format(L("约 %d 天", "~%d days"), math.floor(hrs / 24 + 0.5)) or string.format(L("约 %d 小时", "~%d h"), hrs)
            add({ key = "rest", st = "ok", pct = pct, text = string.format(L("休息经验 %d%%（最多 150%%）", "Rested %d%% (max 150%%)"), pct),
                how = { L("最多攒到 150%（一级半经验），满了不再涨", "Caps at 150% (1.5 levels)"),
                    L("在旅店 / 主城下线、或躺在睡袋里下线：每 8 小时 +5%；野外下线只有 1/4", "Log out in an inn / city / sleeping bag: +5% per 8 h (1/4 in the wild)"),
                    string.format(L("从现在攒满还要%s（在旅店下线算）", "Full in %s (logged out in an inn)"), full) } })
        else
            add({ key = "rest", st = resting and "ok" or "info", pct = 0, text = L("没有休息经验", "No rested XP"),
                how = { L("下线前在旅店 / 主城，或躺在睡袋里下线，能攒休息经验", "Log out in an inn, a city, or your sleeping bag to earn rested XP") } })
        end
    end
    return res, false
end

-- ---------- 提醒 ----------
local warned = {}   -- key → 已提醒到第几档（1 = 浮出来，2 = 高亮）
local hadBuff = {}  -- key → 上次检查时这项在生效
local pending = {}  -- 战斗中攒着，出战斗再报
local missAt = {}   -- key → 第一次读到「缺」的时间（GI-211 防抖）
local MISS_CONFIRM = 4
XC.MISS_CONFIRM = MISS_CONFIRM
local function flash(msg)
    if not opt("warn", true) then return end
    if InCombatLockdown and InCombatLockdown() then pending[#pending + 1] = msg; return end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(msg, 1, 0.82, 0) end
    ns.Print(msg)
    if opt("sound", false) and PlaySound then pcall(PlaySound, 8959) end
end
XC._flash = flash
function XC.Alerts(res)
    local seen = {}
    for _, r in ipairs(res) do
        seen[r.key] = true
        local active = (r.st == "ok" or r.st == "warn") and r.left ~= nil
        if r.st ~= "miss" then missAt[r.key] = nil end
        if active then
            hadBuff[r.key] = true
            local t = th(r.key)
            local lv = { t.show, t.hi }
            for i = #lv, 1, -1 do
                if r.left <= lv[i] and (warned[r.key] or 0) < i then
                    warned[r.key] = i
                    flash(string.format(L("GearInsight：%s 还剩 %s，记得补", "GearInsight: %s ends in %s"), T(r.key), fmt(r.left)))
                    break
                end
            end
            if r.left > t.show then warned[r.key] = nil end
        elseif r.st == "miss" and hadBuff[r.key] and not (missAt[r.key] and now() - missAt[r.key] >= MISS_CONFIRM) then
            -- 「没了」要连着两次都读不到（隔 ≥ MISS_CONFIRM 秒）才报：偶尔一次读空（加载 / 切地图 / 加密值）不算
            missAt[r.key] = missAt[r.key] or now()
        elseif r.st == "miss" and hadBuff[r.key] then
            hadBuff[r.key] = nil; warned[r.key] = nil; missAt[r.key] = nil
            if r.key ~= "tent" and r.key ~= "fire" then   -- 帐篷 / 营火离开就没，不唠叨
                flash(string.format(L("GearInsight：%s 没了", "GearInsight: %s ended"), T(r.key)) .. ((r.how and r.how[1]) and ("  " .. r.how[1]) or ""))
            end
        elseif not active then
            hadBuff[r.key] = nil
        end
    end
end
function XC.Flush()
    local p = pending
    pending = {}
    for _, m in ipairs(p) do flash(m) end
end

-- ---------- 提醒条（11-09 用户「搞成正式服那种，平时透明，快没了就弹出来提醒」）----------
-- 照正式服物资提醒：平时看不见；某项剩到 show 秒浮出来（图标 + 剩余时间），剩到 hi 秒高亮闪；睡袋不满 3 层直接出来并高亮。
-- 左键图标 = 打开经验加成页；右键 = 这一项这次不再弹（补上 / 刷新后恢复）；Shift + 拖 = 挪位置。
-- 「一直半透明」= 生效中的加成常驻半透明显示，快没了的照样亮起来。缺的（没营火 / 没吃食物）不进提醒条，去页里看。
local win
local COLOR = { ok = { 0.25, 0.9, 0.35 }, warn = { 1, 0.82, 0.1 }, miss = { 1, 0.35, 0.3 }, info = { 0.7, 0.7, 0.7 } }
local ICON_SZ, GAP = 36, 8
local IDLE_ALPHA = 0.35
local snooze = {}
XC._snooze = snooze

local function short(sec)
    if not sec then return "" end
    sec = math.max(0, math.floor(sec))
    if sec >= 3600 then return string.format("%dh", math.floor(sec / 3600 + 0.5)) end
    if sec >= 60 then return string.format("%dm", math.floor(sec / 60 + 0.5)) end
    return string.format("%ds", sec)
end
XC.Short = short

local function savePos()
    if not win then return end
    local p, _, _, x, y = win:GetPoint()
    XC.DB().pos = { p or "CENTER", x or 0, y or 0 }
end

-- GI-225 设置页「移动提醒条」/「重置位置」，/gi xp move|reset
function XC.SetMoving(on)
    XC.moving = on and true or false
    XC.hidden = false
    XC.Update()
    if win and win.tip then win.tip:SetShown(XC.moving) end
    if XC.moving then
        ns.Print(L("提醒条已摆出来：按住图标拖到想放的位置，再点一次「锁定位置」", "Reminder bar shown: drag it where you like, then click \"Lock\""))
    end
end
function XC.ResetPos()
    XC.DB().pos = nil
    if win then win:ClearAllPoints(); win:SetPoint("CENTER", UIParent, "CENTER", 0, -150) end
    ns.Print(L("提醒条位置已恢复默认（屏幕中间偏下）", "Reminder bar position reset"))
end

local function buildWin()
    local f = CreateFrame("Frame", "GearInsightForeverXpCheck", UIParent)
    f:SetSize(ICON_SZ, ICON_SZ + 16); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)   -- 11-09 截图：MEDIUM 被主面板（HIGH）盖住看不见
    local pos = XC.DB().pos
    if pos then f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else f:SetPoint("CENTER", UIParent, "CENTER", 0, -150) end
    f:SetMovable(true)
    f.btns = {}
    f.tip = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.tip:SetPoint("BOTTOM", f, "TOP", 0, 8)
    f.tip:SetText(L("拖我挪位置", "Drag to move"))
    f.tip:SetShown(XC.moving == true)
    local acc, tick = 0, 0
    f:SetScript("OnUpdate", function(self, el)
        el = el or 0
        acc = acc + el; tick = tick + el
        local pulse = 0.45 + 0.55 * math.abs(math.sin(acc * 4))
        for _, b in ipairs(self.btns) do
            if b:IsShown() and b.glow:IsShown() then b.glow:SetAlpha(pulse) end
        end
        if tick < 1 then return end
        tick = 0
        for _, b in ipairs(self.btns) do
            local it = b.it
            if b:IsShown() and it and it.left then b.time:SetText(short(it.left - (now() - (self.at or now())))) end
        end
    end)
    return f
end

local function btn(i)
    local b = win.btns[i]
    if b then return b end
    b = CreateFrame("Button", nil, win)
    b:SetSize(ICON_SZ, ICON_SZ)
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    if b.RegisterForDrag then b:RegisterForDrag("LeftButton") end
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetPoint("TOPLEFT", -2, 2); b.bg:SetPoint("BOTTOMRIGHT", 2, -2)   -- 2px 边框：缺 = 红框
    b.bg:SetColorTexture(0, 0, 0, 0.85)
    b.ic = b:CreateTexture(nil, "ARTWORK"); b.ic:SetAllPoints(); b.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    if b.glow.SetBlendMode then b.glow:SetBlendMode("ADD") end
    if b.glow.SetVertexColor then b.glow:SetVertexColor(1, 0.82, 0.1) end
    b.glow:SetPoint("CENTER"); b.glow:SetSize(ICON_SZ * 1.9, ICON_SZ * 1.9); b.glow:Hide()
    b.cnt = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal"); b.cnt:SetPoint("BOTTOMRIGHT", -2, 2)
    b.time = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.time:SetPoint("TOP", b, "BOTTOM", 0, -3)
    -- 11-09 用户截图：亮背景上「缺」字看不清 → 描边
    for _, fs in ipairs({ b.cnt, b.time }) do
        local f, sz = fs:GetFont()
        if f then pcall(fs.SetFont, fs, f, math.max(12, tonumber(sz) or 12), "OUTLINE") end
    end
    b:SetScript("OnEnter", function(self)
        local it = self.it
        if not it or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(T(it.key), 1, 0.82, 0)
        GameTooltip:AddLine(it.text, 1, 1, 1, true)
        for _, h in ipairs(it.how or {}) do GameTooltip:AddLine("· " .. h, 0.8, 0.8, 0.8, true) end
        GameTooltip:AddLine(L("左键：详情  ·  右键：这次不再弹  ·  按住拖动：挪位置", "Left: details · Right: snooze · Drag: move"), 0.5, 0.75, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", function(self, mb)
        local it = self.it
        if not it then return end
        if mb == "RightButton" then snooze[it.key] = true; XC.Update(); return end
        if XC.OpenPage then XC.OpenPage() end
    end)
    -- GI-225「提醒条可以移动」：原来要 Shift+拖，玩家不知道 → 直接按住拖（拖动不会触发点击）
    b:SetScript("OnDragStart", function() win:StartMoving() end)
    b:SetScript("OnDragStop", function() win:StopMovingOrSizing(); savePos() end)
    win.btns[i] = b
    return b
end

-- 进提醒条的：快没了的（warn，没被右键按掉）；「一直半透明」时再加上生效中的
local function barItems(res)
    local t = {}
    local on = opt("win", true) and not XC.hidden
    local always = opt("always", false)
    -- GI-225 移动模式：五项全摆出来给你拖（平时快没了才浮出来，没东西可拖）
    if XC.moving then return res end
    for _, r in ipairs(res) do
        if r.st ~= "warn" then snooze[r.key] = nil end   -- 补上 / 刷新了 → 下次快没了照样弹
        if on then
            -- 快没了才弹：只认有倒计时的 + 睡袋层数（休息经验快满不算「快没了」，去页里看）
            local ending = r.st == "warn" and (r.left or r.key == "bag")
            if ending then
                if not snooze[r.key] then t[#t + 1] = r end
            elseif always then   -- 11-09 用户截图「没看见啊」：一直半透明 = 五项都摆出来（缺的灰掉），不是只摆有倒计时的
                t[#t + 1] = r
            end
        end
    end
    return t
end
XC.BarItems = barItems

function XC.Draw(res)
    local list = barItems(res)
    if #list == 0 then if win then win:Hide() end; return end
    win = win or buildWin()
    XC.win = win
    win.at = now()
    for i, r in ipairs(list) do
        local b = btn(i)
        b.it = r
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", win, "TOPLEFT", (i - 1) * (ICON_SZ + GAP), 0)
        b.ic:SetTexture(r.icon or XC.ICON[r.key])
        local dim = (r.st == "miss" or r.st == "info")
        if b.ic.SetDesaturated then b.ic:SetDesaturated(dim) end
        b.cnt:SetText((r.key == "bag" and (r.stacks or 0) > 0) and (r.stacks .. "/" .. XC.BAG_STACKS) or "")
        local ending = r.st == "warn" and (r.left or r.key == "bag")
        -- 11-09 用户截图「缺了高亮啊」：缺的不透明 + 红框 + 红字；生效中的半透明；快没了的不透明 + 金圈闪；冷却中的半透明灰
        local miss = r.st == "miss"
        b:SetAlpha((ending or miss) and 1 or IDLE_ALPHA)
        -- 11-10 用户截图「没了直接出高亮边框」：缺的也套闪动光圈（红色），快没了的照旧金色
        b.glow:SetShown((r.hi or miss) and true or false)
        if b.glow.SetVertexColor then
            if miss then b.glow:SetVertexColor(1, 0.25, 0.2) else b.glow:SetVertexColor(1, 0.82, 0.1) end
        end
        if miss then b.bg:SetColorTexture(1, 0.2, 0.15, 0.95)
        elseif ending then b.bg:SetColorTexture(1, 0.82, 0.1, 0.9)
        else b.bg:SetColorTexture(0, 0, 0, 0.85) end
        local c = (r.hi or miss) and COLOR.miss or (r.st == "warn" and COLOR.warn) or (dim and COLOR.info) or { 1, 1, 1 }
        local label = (r.left and short(r.left)) or (r.pct and (r.pct .. "%")) or (r.st == "miss" and L("缺", "-")) or ""
        b.time:SetText(label); b.time:SetTextColor(c[1], c[2], c[3])
        b:Show()
    end
    for i = #list + 1, #win.btns do win.btns[i]:Hide() end
    win:SetWidth(#list * (ICON_SZ + GAP) - GAP)
    win:Show()
end

function XC.Update()
    if not ns.db then return end
    if not XC.Enabled() then if win then win:Hide() end; return end
    -- GI-211「没杀死一个怪，就提示没有睡袋和食物」：战斗中增益数据读不到（加密值），一读就全成「缺」，
    --   出战斗又读到 → 每打一只怪报一次「没了」。战斗中不查不画，提醒条保持进战斗前的样子
    if InCombatLockdown and InCombatLockdown() then return end
    local ok, res, done = pcall(XC.Check)
    if not ok then return end
    XC.last = res
    if done then if win then win:Hide() end; return end
    XC.Alerts(res)
    XC.Draw(res)
end

-- 聊天框一行汇总
function XC.Summary()
    local res, done = XC.Check()
    if done then ns.Print(L("经验加成：已满级，不用查了", "XP bonuses: max level")); return end
    local parts = {}
    for _, r in ipairs(res) do
        -- 11-09 用户截图：✓ ✗ 聊天字体里没有，显示成方框 → 用游戏自带的就绪检查图标（绿勾 / 红叉 / 问号）
        local mark = (r.st == "ok" and "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t") or (r.st == "warn" and "|TInterface\\RaidFrame\\ReadyCheck-Waiting:14|t")
            or (r.st == "miss" and "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t") or "|cff999999·|r"
        parts[#parts + 1] = mark .. r.text
    end
    if #parts == 0 then return end
    ns.Print(L("经验加成：", "XP bonuses: ") .. table.concat(parts, "  "))
end

-- ---------- 事件 ----------
local ev = CreateFrame("Frame")
XC._ev = ev
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED", "PLAYER_UPDATE_RESTING", "ZONE_CHANGED_NEW_AREA" }) do
    local valid = not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e)
    if valid then pcall(ev.RegisterEvent, ev, e) end
end
if ev.RegisterUnitEvent then pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player") else pcall(ev.RegisterEvent, ev, "UNIT_AURA") end
local lastAura, wasInst = 0, nil
ev:SetScript("OnEvent", function(_, e, a1)
    if not ns.db or not XC.Enabled() then return end
    if e == "UNIT_AURA" then
        if a1 ~= "player" or now() - lastAura < 1 then return end
        lastAura = now()
    elseif e == "PLAYER_REGEN_ENABLED" then
        XC.Flush()
    elseif e == "PLAYER_ENTERING_WORLD" or e == "PLAYER_LEVEL_UP" or e == "ZONE_CHANGED_NEW_AREA" then
        local inst = inInstance()
        local leftInst = (wasInst == true and not inst)
        if e ~= "ZONE_CHANGED_NEW_AREA" or leftInst then
            if C_Timer and C_Timer.After then C_Timer.After(3, function() pcall(XC.Summary) end) end
        end
        wasInst = inst
    end
    XC.Update()
end)
table.insert(ns.modules, function()
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(5, function() pcall(XC.Update) end) end
end)

-- ---------- 主面板页签「经验加成」（11-09 用户「/gi xp 无效」「然后能做图形界面吗」）----------
-- 五张卡：图标 + 状态 + 剩余时间条 + 怎么补；顶部总开关 / 小窗 / 提醒，开着时每 2 秒刷新。小窗还在，管「缺了 / 快到期自己弹」
XC.FULL = { tent = 1800, bag = 7200 }   -- 时间条满格：帐篷 30 分钟、睡袋 2 小时；其他按本次登录见过的最长剩余
local maxSeen = {}
local CARD_H, CARD_GAP = 70, 6
local STATE_TXT = { ok = { "生效中", "Active" }, warn = { "快到期", "Ending" }, miss = { "缺", "Missing" }, info = { "等待", "Waiting" } }

local function card(parent, i)
    local c = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    c:SetHeight(CARD_H)
    c:SetPoint("TOPLEFT", 0, -(i - 1) * (CARD_H + CARD_GAP)); c:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
    if c.SetBackdrop then
        pcall(c.SetBackdrop, c, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    end
    local hl = c:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.06)
    c.ic = c:CreateTexture(nil, "ARTWORK"); c.ic:SetSize(40, 40); c.ic:SetPoint("TOPLEFT", 10, -12)
    c.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.title = c:CreateFontString(nil, "OVERLAY", "GameFontNormal"); c.title:SetPoint("TOPLEFT", c.ic, "TOPRIGHT", 10, 0)
    c.badge = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); c.badge:SetPoint("LEFT", c.title, "RIGHT", 8, 0)
    c.time = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); c.time:SetPoint("TOPRIGHT", -12, -10); c.time:SetJustifyH("RIGHT")
    c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); c.text:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -4)
    c.text:SetPoint("RIGHT", c, "RIGHT", -110, 0); c.text:SetJustifyH("LEFT"); c.text:SetWordWrap(false)
    c.how = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); c.how:SetPoint("TOPLEFT", c.text, "BOTTOMLEFT", 0, -4)
    c.how:SetPoint("RIGHT", c, "RIGHT", -12, 0); c.how:SetJustifyH("LEFT"); c.how:SetWordWrap(false); c.how:SetTextColor(0.72, 0.72, 0.72)
    c.barBg = c:CreateTexture(nil, "ARTWORK"); c.barBg:SetColorTexture(1, 1, 1, 0.08)
    c.barBg:SetPoint("TOPRIGHT", -12, -34); c.barBg:SetSize(90, 6)
    c.bar = c:CreateTexture(nil, "OVERLAY"); c.bar:SetPoint("TOPLEFT", c.barBg, "TOPLEFT"); c.bar:SetHeight(6)
    c:SetScript("OnEnter", function(self)
        local it = self.it
        if not it or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(T(it.key), 1, 0.82, 0)
        GameTooltip:AddLine(it.text, 1, 1, 1, true)
        for _, h in ipairs(it.how or {}) do GameTooltip:AddLine("· " .. h, 0.8, 0.8, 0.8, true) end
        if it.action then GameTooltip:AddLine(L("点击打开", "Click to open"), 0.25, 0.9, 0.35) end
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    c:SetScript("OnClick", function(self) local it = self.it; if it and it.action then pcall(it.action) end end)
    return c
end

local function paintCard(c, key, it, why)
    c.it = it
    c.ic:SetTexture((it and it.icon) or XC.ICON[key])
    c.title:SetText(T(key))
    local st = it and it.st or "off"
    local col = COLOR[st] or { 0.5, 0.5, 0.5 }
    if c.SetBackdropColor then
        c:SetBackdropColor(col[1] * 0.12, col[2] * 0.12, col[3] * 0.12, 0.85)
        c:SetBackdropBorderColor(col[1], col[2], col[3], it and 0.55 or 0.2)
    end
    c.ic:SetDesaturated(not it or st == "miss" or st == "info")
    c.badge:SetText(it and L(STATE_TXT[st][1], STATE_TXT[st][2]) or "")
    c.badge:SetTextColor(col[1], col[2], col[3])
    if not it then
        c.text:SetText(why or ""); c.text:SetTextColor(0.5, 0.5, 0.5)
        c.how:SetText(""); c.time:SetText(""); c.barBg:Hide(); c.bar:Hide()
        return
    end
    c.text:SetText(it.text); c.text:SetTextColor(1, 1, 1)
    local how = it.how and it.how[1] or ""
    if it.how and it.how[2] then how = how .. "  ·  " .. it.how[2] end
    c.how:SetText(how ~= "" and ("→ " .. how) or "")
    if it.left then
        maxSeen[key] = math.max(maxSeen[key] or 0, it.left)
        local full = math.max((st ~= "info" and XC.FULL[key]) or 0, maxSeen[key])
        local frac = full > 0 and math.min(1, it.left / full) or 0
        c.time:SetText(fmt(it.left)); c.time:SetTextColor(col[1], col[2], col[3])
        c.barBg:Show(); c.bar:Show()
        c.bar:SetWidth(math.max(1, 90 * frac)); c.bar:SetColorTexture(col[1], col[2], col[3], 0.9)
    else
        c.time:SetText(""); c.barBg:Hide(); c.bar:Hide()
    end
end

function XC.RefreshPage()
    local p = XC.page
    if not (p and p:IsShown()) then return end
    local on = XC.Enabled()
    p.onBtn:SetText(on and L("已开启", "On") or L("已关闭", "Off"))
    p.winBtn:SetText(opt("always", false) and L("提醒条：一直半透明", "Bar: always") or (opt("win", true) and L("提醒条：快没了才出", "Bar: when ending") or L("提醒条：不显示", "Bar: off")))
    p.warnBtn:SetText(opt("warn", true) and L("到期提醒：开", "Alerts: on") or L("到期提醒：关", "Alerts: off"))
    local res, done = {}, false
    if on then
        local ok, r, d = pcall(XC.Check)
        if ok then res, done = r, d else p.note:SetText("|cffff5040" .. L("检查出错：", "Error: ") .. tostring(r) .. "|r"); return end
    end
    local by = {}
    for _, r in ipairs(res) do by[r.key] = r end
    local nOk, nMiss = 0, 0
    for i, k in ipairs(XC.KEYS) do
        local why
        if not on then why = L("检查已关闭（点上面「已关闭」打开）", "Check is off")
        elseif done then why = L("已满级，不用查", "Max level")
        elseif not XC.ItemOn(k) then why = L("这一项已在设置里关掉", "Turned off in settings")
        else why = inInstance() and L("副本里不查这一项", "Not checked in instances") or L("现在不用管（等级不够或不适用）", "Not relevant right now") end
        local it = by[k]
        if it and (it.st == "ok") then nOk = nOk + 1 elseif it and (it.st == "miss" or it.st == "warn") then nMiss = nMiss + 1 end
        paintCard(p.cards[i], k, it, why)
    end
    if not on then p.note:SetText(L("经验加成检查已关闭", "XP check is off"))
    elseif done then p.note:SetText(L("已满级", "Max level"))
    else p.note:SetText(string.format(L("|cff40e060%d 项生效|r  ·  |cffff5040%d 项可以补|r  ·  点卡片看怎么补", "|cff40e060%d active|r  ·  |cffff5040%d to fix|r"), nOk, nMiss)) end
end

local function buildPage(p)
    XC.page = p
    local y = ns.PageHeader(p, L("经验加成", "XP bonuses"), L("帐篷 / 营火 / 睡袋 / 经验食物 / 休息经验：有没有、还剩多久、缺了怎么补", "Tent / campfire / bag / food / rested"))
    p.onBtn = ns.Button(p, "", 90, 22, function() XC.Set("on", not XC.Enabled()); XC.hidden = false; XC.RefreshPage() end)
    p.onBtn:SetPoint("TOPLEFT", 12, y)
    p.winBtn = ns.Button(p, "", 150, 22, function()   -- 快没了才出 → 一直半透明 → 不显示 → 快没了才出
        if not opt("win", true) then XC.DB().win = true; XC.DB().always = false
        elseif opt("always", false) then XC.DB().win = false; XC.DB().always = false
        else XC.DB().always = true end
        XC.hidden = false; XC.Update(); XC.RefreshPage()
    end)
    p.winBtn:SetPoint("LEFT", p.onBtn, "RIGHT", 8, 0)
    p.warnBtn = ns.Button(p, "", 110, 22, function() XC.Set("warn", not opt("warn", true)); XC.RefreshPage() end)
    p.warnBtn:SetPoint("LEFT", p.winBtn, "RIGHT", 8, 0)
    -- 11-12 界面重构第 2 期：原来跳到设置页再找 → 改成就地展开本页设置（每项开关 / 音效 / 移动提醒条 / 帐篷蹭露营都在里面）
    local more = ns.Button(p, L("每项开关 / 音效", "More settings"), 120, 22, function()
        if ns.TogglePageSettings and ns.TogglePageSettings("xp", true) then return end
        ns.ToggleMain("data")
    end)
    more:SetPoint("LEFT", p.warnBtn, "RIGHT", 8, 0)
    p.note = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.note:SetPoint("TOPLEFT", 14, y - 30); p.note:SetPoint("RIGHT", -12, 0); p.note:SetJustifyH("LEFT")
    local box = CreateFrame("Frame", nil, p)
    box:SetPoint("TOPLEFT", 8, y - 50); box:SetPoint("BOTTOMRIGHT", -8, 0)
    p.cards = {}
    for i = 1, #XC.KEYS do p.cards[i] = card(box, i) end
    local acc = 0
    p:SetScript("OnUpdate", function(_, el)
        acc = acc + (el or 0)
        if acc < 2 then return end
        acc = 0
        XC.RefreshPage()
    end)
end
if ns.RegisterPage then
    ns.RegisterPage({ key = "xp", order = 1.87, title = ns.L("经验加成", "XP bonuses"), tabTitle = ns.L("经验加成", "XP"),
        icon = "Interface\\Icons\\INV_Misc_Tent", build = buildPage, refresh = function() XC.RefreshPage() end })
end
function XC.OpenPage()
    if ns.ToggleMain then
        local f = XC.page and XC.page:GetParent()
        if f and f:IsShown() and XC.page:IsShown() then XC.RefreshPage(); return end
        ns.ToggleMain("xp")
    end
end

-- ---------- 命令 ----------
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.xp = function(rest)
    rest = (rest or ""):lower()
    if rest == "off" then XC.Set("on", false); ns.Print(L("经验加成检查：已关", "XP check: off"))
    elseif rest == "on" then XC.Set("on", true); XC.hidden = false; ns.Print(L("经验加成检查：已开", "XP check: on"))
    elseif rest == "move" then XC.SetMoving(not XC.moving)
    elseif rest == "reset" then XC.ResetPos()
    elseif rest == "probe" then
        ns.ShowBox(L("经验加成探针", "XP probe"), L("Ctrl+C 复制发给开发者", "Ctrl+C to copy"), table.concat(XC.DB().probe or {}, "\n"))
    else
        -- 11-09 用户「/gi xp 无效」：汇总出错要说出来（原来报错被吞 / 全齐时小窗不出 → 看着像没反应），然后直接打开图形页
        XC.hidden = false
        if not XC.Enabled() then ns.Print(L("经验加成检查是关着的：/gi xp on 打开，或在页里点「已关闭」", "XP check is off: /gi xp on")) end
        local ok, err = pcall(XC.Summary)
        if not ok then ns.Print(L("经验加成检查出错（请截图发我们）：", "XP check error (please screenshot): ") .. tostring(err)) end
        pcall(XC.Update)
        XC.OpenPage()
    end
end
ns.ExtraSlash["经验"] = ns.ExtraSlash.xp

-- 11-12 重构第 1 期：提醒条登记进设置页「窗口与提醒」
ns.RegisterWindow({ key = "xpBar", order = 30, title = function() return L("经验提醒条", "XP reminder bar") end,
    state = function()
        if not XC.Enabled() then return L("经验加成检查已关", "XP check is off") end
        local d = XC.DB()
        if d.win == false then return L("不显示", "Off") end
        if d.always == true then return L("一直显示（半透明）", "Always shown") end
        return L("加成快没了才出", "Shown when a bonus is ending")
    end,
    actions = function()
        local on = XC.Enabled() and XC.DB().win ~= false
        return {
            { text = on and L("关闭", "Hide") or L("打开", "Show"), fn = function()
                if on then XC.Set("win", false)
                else XC.DB().on = true; XC.hidden = false; XC.Set("win", true) end
            end },
            { text = XC.moving and L("锁定位置", "Lock position") or L("移动", "Move"), fn = function() XC.SetMoving(not XC.moving) end },
            { text = L("重置位置", "Reset position"), fn = function() XC.ResetPos() end },
        }
    end })
