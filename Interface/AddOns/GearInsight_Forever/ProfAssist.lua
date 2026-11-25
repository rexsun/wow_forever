-- 专业助手（11-12，docs/forever-profession-assistant-design.md）：在「专业」页的冲级路线上做系统化
--   · 12 个专业都有：制造 8 个 = 分段路线 + 从当前技能起算的次数 / 材料 / 还缺；采集 3 个 = 分段推荐地图；钓鱼 = 水域分组
--   · 烹饪：按角色等级 + 职业偏好推荐「现在最值得吃的食物」
-- 数据：ProfAssistData.lua（scripts/gi_forever_prof_assist.py 生成）+ ProfData.lua 的路线 / 档位。这里只做推导，不画界面。
-- ⛔ 路线步骤以 ProfData.route 为准（和网站 / 小程序同一份 prof_route.json）。
--    第二期（11-12）：材料合计走求解器的算账（ProfSolve.lua，自产半成品折成原料不重复算）；
--    有了真实价格（拍卖行扫描 / 手填，ns.Prices）以后可以用 A.Reroute 按真实价格重算一条，随包路线仍是默认显示。
local _, ns = ...; ns = _G.GearInsightForever or ns

local A = {}
ns.ProfAssist = A

local function AD() return ns.ProfAssistData end
local function D() return ns.ProfData end
local function P() return ns.Prof end

A.CRAFT = { "firstaid", "cooking", "alchemy", "blacksmithing", "enchanting", "engineering", "leatherworking", "tailoring" }
A.GATHER = { "skinning", "herbalism", "mining", "fishing" }
A.KIND = { firstaid = "craft", cooking = "craft", alchemy = "craft", blacksmithing = "craft", enchanting = "craft", engineering = "craft",
    leatherworking = "craft", tailoring = "craft", skinning = "gather", herbalism = "gather", mining = "gather", fishing = "fish" }

function A.Ready() return AD() ~= nil and D() ~= nil and P() ~= nil end

-- 物品名：先用专业数据里的官方名，再用助手数据补的，最后问客户端
function A.ItemName(id)
    local it = D() and D().items and D().items[id]
    if not it then it = AD() and AD().items and AD().items[id] end
    if it then return ns.L(it[1] ~= "" and it[1] or it[2], it[2] ~= "" and it[2] or it[1]) end
    if GetItemInfo then
        local ok, nm = pcall(GetItemInfo, id)
        if ok and type(nm) == "string" then return nm end
    end
    return tostring(id)
end

-- ---------- 口径 ----------
-- 涨点几率：没到黄 = 1；到灰 = 0；中间 (灰 - 当前) / (灰 - 黄)
function A.Prob(y, gr, s)
    if s < y then return 1 end
    if s >= gr then return 0 end
    return (gr - s) / (gr - y)
end

-- 从 f 练到 t 的期望制作次数（不取整）；中途变灰返回 nil
function A.Expect(y, gr, f, t)
    local sum = 0
    for s = f, t - 1 do
        local p = A.Prob(y, gr, s)
        if p <= 0 then return nil end
        sum = sum + 1 / p
    end
    return sum
end

-- 第几段（1-75 / 75-150 / 150-225 / 225-300）；300 算最后一段
function A.SegIndex(rank)
    local segs = AD().segs
    for i, sg in ipairs(segs) do
        if rank < sg[2] then return i end
    end
    return #segs
end

local function bag(item)
    local f = P().BagCount
    return f and f(item) or nil
end

-- 合计材料：list = { {item, n}, ... } 累加进 acc（acc.order 记先后）
local function addMats(acc, list)
    for _, mt in ipairs(list) do
        if not acc.n[mt[1]] then acc.order[#acc.order + 1] = mt[1] end
        acc.n[mt[1]] = (acc.n[mt[1]] or 0) + mt[2]
    end
end
local function newAcc() return { n = {}, order = {} } end
local function finishAcc(acc)
    local out = {}
    for _, it in ipairs(acc.order) do
        local need, have = acc.n[it], bag(it)
        out[#out + 1] = { item = it, need = need, have = have, lack = have and math.max(0, need - have) or nil }
    end
    return out
end
A._NewAcc, A._AddMats, A._FinishAcc = newAcc, addMats, finishAcc

-- ---------- 价格 / 算账（第二期）----------
local function SV() local s = ns.ProfSolve; return s and s.Ready() and s or nil end

-- 现在路线按什么价格算：nil = 随包估算价（商人价 / 卖店价估算）；"a" = 有拍卖行扫描价；"m" = 有手填价
function A.PriceKind()
    return ns.Prices and ns.Prices.CustomKind and ns.Prices.CustomKind() or nil
end

function A.PriceLabel()
    local k = A.PriceKind()
    if k == "a" then return ns.L("按拍卖行价", "auction prices") end
    if k == "m" then return ns.L("含你填的价格", "with your prices") end
    return ns.L("按商人价估算", "vendor-price estimate")
end

-- 给求解器的价格函数：有价格层走价格层（扫描 > 手填 > 随包），没有就用随包估算
function A.PriceFn()
    if ns.Prices and ns.Prices.Fn then return ns.Prices.Fn() end
    local s = SV()
    return s and s.DefaultPrice or nil
end

-- 一组「配方 × 期望次数」的材料合计：自己做的半成品先抵、不够的折成原料。parts = { { 法术, 期望次数 } }
--   返回 rows（同 finishAcc：item / need / have / lack）, 估算总价（铜）, 要额外做的半成品 { {物品, 次数} }；求解器不在返回 nil
function A.Account(key, parts)
    local s = SV()
    local prof = s and s.Prof(key)
    if not prof or #parts == 0 then return nil end
    local recs = s.Eligible(prof)
    local val, mode, makers = s.MakeValues(recs, A.PriceFn())
    local steps = {}
    for _, pt in ipairs(parts) do
        local r = prof.by[pt[1]]
        if not r then return nil end
        steps[#steps + 1] = { rec = r, x = pt[2] }
    end
    -- 背包里已经做好的半成品（布卷、火药…）先抵掉，不再折成原料
    local have = nil
    for it in pairs(makers) do
        local n = bag(it)
        if n and n > 0 then have = have or {}; have[it] = n end
    end
    local acc = s.Account(steps, val, mode, makers, have)
    local ids = {}
    for it in pairs(acc.buy) do ids[#ids + 1] = it end
    table.sort(ids)
    local rows = {}
    for _, it in ipairs(ids) do
        local need = s.CeilQ(acc.buy[it])
        local have = bag(it)
        rows[#rows + 1] = { item = it, need = need, have = have, lack = have and math.max(0, need - have) or nil }
    end
    local make = {}
    for it, n in pairs(acc.make) do make[#make + 1] = { it, s.CeilQ(n) } end
    table.sort(make, function(a, b) return a[1] < b[1] end)
    return rows, math.floor(acc.cost + 0.5), make
end

-- 按现在的价格（价格层）从当前技能重算一条路线。只有价格层里有真实价格时才有意义（没有时结果 = 随包路线）
--   返回 ns.ProfSolve.Solve 的结果，外加 base = 随包路线按同样价格算的总价（好比较省了多少）
function A.Reroute(key, rank)
    local s = SV()
    if not s then return nil end
    local price = A.PriceFn()
    local from = math.max(1, rank or 1)
    if from >= 300 then return nil end
    local res = s.Solve(key, from, 300, price)
    if not res then return nil end
    local prof = s.Prof(key)
    local segs = {}
    for _, st in ipairs(D().profs[key].route) do
        if st.f then segs[#segs + 1] = { st.f, st.t, st.sp } end
    end
    local base = s.RouteCost(prof, segs, price, { from = from })
    res.base = base and base.cost or nil
    return res
end

-- 一步从当前技能起还要做几次、要多少材料。rank = nil 或还没到这一步：用路线上的整步数字（和网站一致）
--   返回 { c = 次数, mats = { {item, n} }, part = 是不是只算了后半截 }；这一步已经过了返回 nil
function A.StepRemain(key, st, rank)
    if rank and rank >= st.t then return nil end
    if not rank or rank <= st.f then return { c = st.c, mats = st.m, part = false, x = A.Expect(st.y, st.gr, st.f, st.t) } end
    local e = A.Expect(st.y, st.gr, rank, st.t)
    local info = AD().steps[key] and AD().steps[key][st.f]
    if not e or not info then return { c = st.c, mats = st.m, part = false, x = A.Expect(st.y, st.gr, st.f, st.t) } end
    local c = math.ceil(e - 1e-9)
    local mats = {}
    for _, mt in ipairs(info.pm) do mats[#mats + 1] = { mt[1], math.ceil(mt[2] * e - 1e-9) } end
    return { c = c, mats = mats, part = true, x = e }
end

function A.StepInfo(key, st)
    return AD().steps[key] and AD().steps[key][st.f] or nil
end

-- 档位：第 i 段对应第 i 档（初级 / 中级 / 高级 / 大师级）
function A.Tier(key, i)
    local p = D().profs[key]
    return p and p.tiers and p.tiers[i] or nil
end

-- 制造专业的整套计划。rank = 当前技能（没学 = nil）
--   segs[i] = { f, t, state = "done" / "here" / "todo", tier = 这一段要先学的档位, steps = { { st, rem, here } }, total = 合计材料 }
--   total = 从现在到 300 的合计材料；left = 还要做的步数
function A.CraftPlan(key, rank)
    local p = D().profs[key]
    if not p or not p.route or #p.route == 0 then return nil end
    local plan = { key = key, rank = rank, segs = {}, left = 0 }
    local all = newAcc()
    local allParts, partsOk = {}, SV() ~= nil
    if ns.Prices and ns.Prices.Purge and not A._purged then
        A._purged = true
        ns.Prices.Purge()
    end
    for i, sg in ipairs(AD().segs) do
        local seg = { f = sg[1], t = sg[2], idx = i, tier = A.Tier(key, i), steps = {} }
        if not rank then seg.state = "todo"
        elseif rank >= sg[2] and i < #AD().segs then seg.state = "done"
        elseif rank >= 300 then seg.state = "done"
        elseif rank >= sg[1] or i == 1 then seg.state = "here"
        else seg.state = "todo" end
        local acc = newAcc()
        local parts = {}
        for _, st in ipairs(p.route) do
            if st.f and st.f >= sg[1] and st.f < sg[2] then
                local rem = A.StepRemain(key, st, rank)
                seg.steps[#seg.steps + 1] = { st = st, rem = rem, here = rank ~= nil and rank >= st.f and rank < st.t }
                if rem then
                    addMats(acc, rem.mats); addMats(all, rem.mats)
                    plan.left = plan.left + 1
                    if rem.x then
                        parts[#parts + 1] = { st.sp, rem.x }
                        allParts[#allParts + 1] = { st.sp, rem.x }
                    else
                        partsOk = false
                    end
                end
            end
        end
        -- 合计：求解器在就按「半成品折成原料」算（deducted = true），不在就退回逐步相加
        local rows, cost = nil, nil
        if partsOk then rows, cost = A.Account(key, parts) end
        seg.total, seg.cost, seg.deducted = rows or finishAcc(acc), cost, rows ~= nil
        plan.segs[i] = seg
    end
    local rows, cost, make = nil, nil, nil
    if partsOk then rows, cost, make = A.Account(key, allParts) end
    plan.total, plan.cost, plan.make, plan.deducted = rows or finishAcc(all), cost, make, rows ~= nil
    plan.priceKind, plan.priceLabel = A.PriceKind(), A.PriceLabel()
    return plan
end

-- 下一档去哪学：{ tier, idx, ready = 技能够了, lvOk = 等级够了, needSkill, needLevel }
function A.NextTier(key, s, level)
    if not s then
        local t = A.Tier(key, 1)
        return t and { tier = t, idx = 1, ready = true, lvOk = (t.lv or 0) <= (level or 0), needSkill = 0, needLevel = t.lv or 0 } or nil
    end
    local nt = P().NextTier(key, s, level)
    if not nt then return nil end
    nt.needSkill, nt.needLevel = nt.tier.sk, nt.tier.lv or 0
    return nt
end

-- ---------- 采集 ----------
-- 草药 / 采矿 / 剥皮的分段推荐地图；state 同上
function A.GatherSegs(key, rank)
    local g = AD().gather and AD().gather[key]
    if not g then return nil end
    local out = {}
    for i, sg in ipairs(g) do
        local state = "todo"
        if rank then
            if rank >= sg.t and i < #g then state = "done"
            elseif rank >= 300 then state = "done"
            elseif rank >= sg.f or i == 1 then state = "here" end
        end
        out[i] = { f = sg.f, t = sg.t, idx = i, state = state, maps = sg.maps, tier = A.Tier(key, i) }
    end
    return out
end

-- 钓鱼：按水域基础技能分组。state：safe = 不跑鱼；ok = 能钓但会跑鱼；low = 技能不够
--   best = 现在最该去的那一组（能不跑鱼的里面最高的；一个都没有就取能钓的里面最低的）
function A.FishGroups(rank)
    local f = AD().fish
    if not f or not f.groups then return nil end
    local out, best = {}, nil
    for i, g in ipairs(f.groups) do
        local state = nil
        if rank then
            state = rank >= g.safe and "safe" or rank >= g.cast and "ok" or "low"
        end
        out[i] = { base = g.base, cast = g.cast, safe = g.safe, maps = g.maps, state = state }
        if state == "safe" then best = i end
    end
    if rank and not best then
        for i, g in ipairs(out) do if g.state == "ok" then best = i break end end
    end
    if best then out[best].best = true end
    return out, best
end

-- ---------- 烹饪：现在最值得吃的食物 ----------
-- 职业偏好（先后顺序 = 优先级）。这是口径不是数据，写在设计文档第 5 节；食物给什么属性、多少点来自法术效果
A.CLASS_PREF = {
    WARRIOR = { "str", "ap", "sta", "agi" },
    ROGUE = { "agi", "ap", "str", "sta" },
    HUNTER = { "agi", "ap", "sta", "int" },
    PALADIN = { "str", "ap", "sta", "int", "heal" },
    SHAMAN = { "str", "agi", "ap", "int", "sp", "sta" },
    DRUID = { "str", "agi", "ap", "int", "sp", "sta" },
    MAGE = { "sp", "int", "spi", "sta" },
    WARLOCK = { "sp", "int", "sta", "spi" },
    PRIEST = { "sp", "spi", "int", "heal", "sta" },
}
A.KIND_NAME = { str = { "力量", "Strength" }, agi = { "敏捷", "Agility" }, sta = { "耐力", "Stamina" }, int = { "智力", "Intellect" },
    spi = { "精神", "Spirit" }, ap = { "攻击强度", "Attack Power" }, sp = { "法术伤害", "Spell Damage" }, heal = { "治疗", "Healing" } }

local function kindAmt(f, kind)
    for _, k in ipairs(f.k or {}) do
        if k[1] == kind then return k[2] end
    end
    return nil
end

local function canCook(f, cookRank)
    return f.learn ~= nil and cookRank ~= nil and cookRank >= f.learn
end

-- 某一种属性里，使用等级 ≤ level 的最好的一个。onlyCan = 只在现在做得出来的里面挑
function A.BestOfKind(kind, level, cookRank, onlyCan, skip)
    local best, bestAmt
    for _, f in ipairs(AD().foods or {}) do
        local amt = kindAmt(f, kind)
        if amt and not f.zone and (f.use or 1) <= level and not (skip and skip[f.item])
            and (not onlyCan or canCook(f, cookRank)) then
            local better = false
            if not best or amt > bestAmt then better = true
            elseif amt == bestAmt then
                local a, b = canCook(f, cookRank), canCook(best, cookRank)
                if a ~= b then better = a
                elseif (f.xp and true or false) ~= (best.xp and true or false) then better = f.xp and true or false
                elseif (f.learn or 999) ~= (best.learn or 999) then better = (f.learn or 999) < (best.learn or 999)
                else better = f.item < best.item end
            end
            if better then best, bestAmt = f, amt end
        end
    end
    return best, bestAmt
end

-- 推荐列表（最多 n 个，每种属性一个）：
--   { f = 食物, kind, amt, can = 现在做得出来, lack = 还差几点烹饪, unknown = 学习技能没数据, nocook = 没学烹饪,
--     now = 做不出来时「现在能做的同类最好的」{ f, amt } }
function A.BestFoods(level, class, cookRank, n)
    if not AD() or not AD().foods then return {} end
    level = level or 1
    local prefs = A.CLASS_PREF[class or ""] or { "sta" }
    local out, used = {}, {}
    for _, kind in ipairs(prefs) do
        if #out >= (n or 3) then break end
        local f, amt = A.BestOfKind(kind, level, cookRank, false, used)
        if f then
            used[f.item] = true
            local e = { f = f, kind = kind, amt = amt, can = canCook(f, cookRank), nocook = cookRank == nil, unknown = f.learn == nil }
            if not e.can and f.learn and cookRank then e.lack = f.learn - cookRank end
            if not e.can and cookRank then
                local nf, namt = A.BestOfKind(kind, level, cookRank, true, nil)
                if nf then e.now = { f = nf, amt = namt } end
            end
            out[#out + 1] = e
        end
    end
    return out
end

-- 食物增益的官方说明
function A.FoodBuff(f) return ns.L(f.bz or f.be or "", f.be or f.bz or "") end

-- 配方出处短句：训练师 / 商人 / 掉落…（细节在配方库，这里只给一句）
local SRC = { auto = { "学烹饪就会", "known from the start" }, trainer = { "训练师", "trainer" }, vendor = { "商人卖配方", "recipe vendor" },
    drop = { "掉落配方", "recipe drop" }, rep = { "声望", "reputation" }, quest = { "任务", "quest" }, unknown = { "出处未记录", "source unknown" } }
function A.FoodSource(f)
    local s = SRC[f.src or "unknown"] or SRC.unknown
    return ns.L(s[1], s[2])
end

-- ---------- 覆盖情况（设计文档 / 测试 / 页面顶上的说明都用它）----------
-- full = 数据齐；base = 只有经典基线、《无限》没实测；none = 数据待补
function A.Coverage(key)
    local kind = A.KIND[key]
    if kind == "craft" then
        local p = D().profs[key]
        local v = AD().verify and AD().verify[key]
        if not p or not p.route or #p.route == 0 then return "none" end
        if v and v.ok == v.n then return "full" end
        return "base"
    elseif kind == "gather" then
        local g = AD().gather and AD().gather[key]
        return (g and #g > 0) and "base" or "none"
    elseif kind == "fish" then
        local f = AD().fish
        return (f and f.groups and #f.groups > 0) and "base" or "none"
    end
    return "none"
end
