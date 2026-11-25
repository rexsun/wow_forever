-- 专业路线求解器（11-12，docs/forever-profession-assistant-design.md 第 10 / 12 节）
--   ns.ProfAssist.Solve(专业, 起始技能, 目标技能, 价格函数, opts) => 路线（步骤 / 期望次数 / 材料合计 / 总价）
-- ⛔ 和 scripts/gi_forever_prof_solver.py（= bis_wow tools/forever_prof_solver.py）是同一个算法，运算顺序都一样：
--    默认估算价下求出来的路线必须和随包路线（ProfData.route = prof_route.json）逐步相等，有测试
--    （scripts/gi_forever_profession_test.py）。改这里任何一步，Python 那边必须同步改。
-- 数据：ProfCandData.lua（紧凑字符串，用到哪个专业才解码哪个）。只依赖 ns.ProfCandData / ns.Prices，不碰内核和界面，
--       以后和专业页一起整体搬进按需加载的子插件。
local _, ns = ...; ns = _G.GearInsightForever or ns

local S = {}
ns.ProfSolve = S

local EPS = 1e-9
local function CD() return ns.ProfCandData end

S.CAND_V = 1      -- 认得的候选集编码版本
S.ALGO = 2        -- 算法版本（要和候选集的 algo 一样，不一样说明数据和代码不配套）

function S.Ready()
    local d = CD()
    return d ~= nil and d.v == S.CAND_V and d.algo == S.ALGO
end

-- ---------- 解码 ----------
local decoded, bundle = {}, nil

-- 随包估算价：{ [物品] = { 价, 来源码 } }
function S.Bundle()
    if bundle then return bundle end
    bundle = {}
    local d = CD()
    if d and d.price then
        for it, p, src in string.gmatch(d.price, "(%d+):([%d%.]+):(%a)") do
            bundle[tonumber(it)] = { tonumber(p), src }
        end
    end
    return bundle
end

-- 只用随包估算价的价格函数（= 生成器的口径）
function S.DefaultPrice(item)
    local e = S.Bundle()[item]
    if e then return e[1], e[2] end
    return nil
end

-- 一个专业的候选集：{ recs = { 配方… 按法术号排好 }, legacy = { {f, t, 法术} }, cost = 随包路线估算总价 }
--   配方 = { spell, learn, y, grey, n, item（没有成品 = nil）, rt, src, rx, mats = { {物品, 数量} } }
function S.Prof(key)
    if decoded[key] ~= nil then return decoded[key] or nil end
    local d = CD()
    local raw = d and d.profs and d.profs[key]
    if not raw or not S.Ready() then
        decoded[key] = false
        return nil
    end
    local recs = {}
    for chunk in string.gmatch(raw.recs or "", "[^|]+") do
        local head = string.match(chunk, "^[^;]+")
        local sp, learn, y, grey, n, item, flag = string.match(head, "^(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%w+)$")
        if sp then
            local r = { spell = tonumber(sp), learn = tonumber(learn), y = tonumber(y), grey = tonumber(grey), n = tonumber(n),
                rt = tonumber(string.sub(flag, 1, 1)), src = string.sub(flag, 2, 2), rx = string.sub(flag, 3), mats = {} }
            local it = tonumber(item)
            if it and it > 0 then r.item = it end
            for a, b in string.gmatch(chunk, ";(%d+)%*(%d+)") do
                r.mats[#r.mats + 1] = { tonumber(a), tonumber(b) }
            end
            recs[#recs + 1] = r
        end
    end
    table.sort(recs, function(a, b) return a.spell < b.spell end)
    local legacy = {}
    for f, t, sp in string.gmatch(raw.legacy or "", "(%d+),(%d+),(%d+)") do
        legacy[#legacy + 1] = { tonumber(f), tonumber(t), tonumber(sp) }
    end
    local by = {}
    for _, r in ipairs(recs) do by[r.spell] = r end
    decoded[key] = { key = key, recs = recs, legacy = legacy, cost = raw.cost, by = by }
    return decoded[key]
end

-- 丢掉解码结果（省内存；下次用再解）
function S.Release()
    decoded, bundle = {}, nil
end

-- ---------- 算法（和 Python 逐行对应）----------
function S.Prob(y, grey, s)
    if s < y then return 1 end
    if s >= grey then return 0 end
    return (grey - s) / (grey - y)
end

local function ceilq(x) return math.ceil(x - EPS) end
S.CeilQ = ceilq

-- 能进路线的配方。allow = 放宽哪些约束（原因码，比如 "sm"）
function S.Eligible(prof, allow)
    allow = allow or ""
    local out = {}
    for _, r in ipairs(prof.recs) do
        local ok = r.rt and r.rt > 0
        if not ok and r.rx ~= "" and not string.find(r.rx, "u", 1, true) then
            ok = true
            for i = 1, #r.rx do
                if not string.find(allow, string.sub(r.rx, i, i), 1, true) then ok = false break end
            end
        end
        if ok then out[#out + 1] = r end
    end
    return out
end

-- 返回 val(物品) => 单价、mode[物品] = "make" / "buy"、makers[物品] = 做它的配方
function S.MakeValues(recs, price)
    local d = CD()
    local fallback = d and d.fallback or 20
    local makers = {}
    for _, r in ipairs(recs) do
        local it = r.item
        if it and not makers[it] then
            local self = false
            for _, mt in ipairs(r.mats) do if mt[1] == it then self = true break end end
            if not self then makers[it] = r end
        end
    end
    local memo, mode, busy, nbusy = {}, {}, {}, 0
    local val
    val = function(it)
        local m = memo[it]
        if m ~= nil then return m end
        local pv, ps = price(it)
        local mk = makers[it]
        local c = nil
        if mk ~= nil and not busy[it] then
            busy[it] = true; nbusy = nbusy + 1
            c = 0
            for _, mt in ipairs(mk.mats) do
                c = c + val(mt[1]) * mt[2]
            end
            c = c / (mk.n or 1)
            busy[it] = nil; nbusy = nbusy - 1
        end
        local v, md
        if pv == nil or (ps == "c" and c ~= nil) then
            if c ~= nil then v, md = c, "make" else v, md = fallback, "buy" end
        elseif c ~= nil and c < pv then
            v, md = c, "make"
        else
            v, md = pv, "buy"
        end
        if nbusy == 0 then
            memo[it], mode[it] = v, md
        elseif mode[it] == nil then
            mode[it] = md
        end
        return v
    end
    return val, mode, makers
end

local function sortedKeys(t)
    local ks = {}
    for k in pairs(t) do ks[#ks + 1] = k end
    table.sort(ks)
    return ks
end

-- 路线真实花费与材料合计。steps = { { rec =, x = 期望次数 } }
function S.Account(steps, val, mode, makers, have)
    local depthMax = (CD() and CD().depth) or 4
    local supply = {}
    for k, v in pairs(have or {}) do
        if v and v > 0 then supply[k] = v end
    end
    local used = {}
    for _, st in ipairs(steps) do
        for _, mt in ipairs(st.rec.mats) do used[mt[1]] = true end
    end
    for _, st in ipairs(steps) do
        local it = st.rec.item
        if it and used[it] then
            supply[it] = (supply[it] or 0) + (st.rec.n or 1) * st.x
        end
    end
    local buy, extra = {}, {}
    local need
    need = function(it, qty, depth)
        local got = supply[it] or 0
        if got > 0 then
            local use = got < qty and got or qty
            supply[it] = got - use
            qty = qty - use
        end
        if qty <= EPS then return end
        local mk = makers[it]
        if mk ~= nil and mode[it] == nil then val(it) end      -- 还没问过价的半成品先问一次，mode 才有值
        if mode[it] == "make" and mk ~= nil and depth < depthMax then
            local n = qty / (mk.n or 1)
            extra[it] = (extra[it] or 0) + n
            for _, mt in ipairs(mk.mats) do
                need(mt[1], mt[2] * n, depth + 1)
            end
        else
            buy[it] = (buy[it] or 0) + qty
        end
    end
    for _, st in ipairs(steps) do
        for _, mt in ipairs(st.rec.mats) do
            need(mt[1], mt[2] * st.x, 0)
        end
    end
    local cost = 0
    for _, it in ipairs(sortedKeys(buy)) do
        cost = cost + buy[it] * val(it)
    end
    local left = {}
    for k, v in pairs(supply) do
        if v > EPS and makers[k] then left[k] = v end
    end
    return { cost = cost, buy = buy, make = extra, left = left }
end

local function walk(recs, s0, s1, ucost, val, legacyAt, budget, breaks, tol)
    local steps, cur, seg = {}, nil, nil
    local left = nil
    if budget then
        left = {}
        for k, v in pairs(budget) do left[k] = v end
    end
    for s = s0, s1 - 1 do
        local best, bestEff, effs = nil, 0, {}
        for _, r in ipairs(recs) do
            if not (r.learn > s or s >= r.grey) then
                local p = S.Prob(r.y, r.grey, s)
                local c = ucost[r.spell]
                if left ~= nil then
                    local it = r.item
                    local b = it and left[it] or 0
                    if b > EPS then
                        local n = r.n or 1
                        c = c - val(it) * (n < b and n or b)
                        if c < 0 then c = 0 end
                    end
                end
                local e = c / p
                effs[r.spell] = { e, r, p }
                if best == nil or e < bestEff - 1e-12 or (math.abs(e - bestEff) <= 1e-12 and
                    (r.learn < best.learn or (r.learn == best.learn and r.spell < best.spell))) then
                    best, bestEff = r, e
                end
            end
        end
        if best == nil then
            steps[#steps + 1] = { gap = true, f = s }
            break
        end
        local lim = bestEff * (1 + tol) + EPS
        local pick = best
        if cur ~= nil and effs[cur.spell] and effs[cur.spell][1] <= lim then
            pick = cur
        else
            local lg = legacyAt[s]
            if lg ~= nil and effs[lg] and effs[lg][1] <= lim then
                pick = effs[lg][2]
            end
        end
        local p = effs[pick.spell][3]
        if seg == nil or seg.rec ~= pick or breaks[s] then
            seg = { f = s, t = s + 1, rec = pick, x = 0 }
            steps[#steps + 1] = seg
        end
        seg.t = s + 1
        seg.x = seg.x + 1 / p
        if left ~= nil and pick.item then
            local it = pick.item
            if (left[it] or 0) > 0 then
                left[it] = left[it] - (pick.n or 1) / p
            end
        end
        cur = pick
    end
    return steps
end

local function sameTable(a, b)
    if a == nil or b == nil then return false end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function listOf(t, round)
    local out = {}
    for _, k in ipairs(sortedKeys(t)) do
        local n = round(t[k])
        if n then out[#out + 1] = { k, n } end
    end
    return out
end

local function totalOf(acc)
    return {
        cost = math.floor(acc.cost + 0.5),
        buy = listOf(acc.buy, ceilq),
        make = listOf(acc.make, ceilq),
        left = listOf(acc.left, function(v)
            local n = math.floor(v + EPS)
            return n >= 1 and n or nil
        end),
    }
end

local function unitCosts(recs, val)
    local ucost = {}
    for _, r in ipairs(recs) do
        local c = 0
        for _, mt in ipairs(r.mats) do
            c = c + val(mt[1]) * mt[2]
        end
        ucost[r.spell] = c
    end
    return ucost
end

-- 求解。prof = 专业 key（"tailoring"）或 S.Prof 解出来的表；price(物品) => 价格（铜）, 来源码（"c" = 只是按制作估出来的）
-- opts：have = { [物品] = 数量 }（背包 / 银行已有，合计里先抵）；legacy = false 不看旧路线；
--       breaks = { 75, 150, 225 } 必须分段的技能点（默认用候选集里的）；allow = 放宽的约束原因码
-- 返回 { steps = { { f, t, sp, c = 次数, x = 期望次数, m = { {物品, 数量} }, cost } }, gap = 断在哪一点, total = { cost, buy, make, left }, round }
--      数据没准备好返回 nil
function S.Solve(prof, s0, s1, price, opts)
    if type(prof) == "string" then prof = S.Prof(prof) end
    if not prof then return nil end
    opts = opts or {}
    price = price or S.DefaultPrice
    local d = CD()
    local tol, rounds = d.tol or 0.02, d.rounds or 3
    local recs = S.Eligible(prof, opts.allow)
    local val, mode, makers = S.MakeValues(recs, price)
    local ucost = unitCosts(recs, val)
    local legacyAt = {}
    if opts.legacy ~= false then
        for _, lg in ipairs(prof.legacy) do
            for s = lg[1], lg[2] - 1 do legacyAt[s] = lg[3] end
        end
    end
    local breaks = {}
    for _, b in ipairs(opts.breaks or d.breaks or {}) do breaks[b] = true end
    local best, budget = nil, nil
    for rnd = 0, rounds - 1 do
        local steps = walk(recs, s0, s1, ucost, val, legacyAt, budget, breaks, tol)
        local real = {}
        for _, st in ipairs(steps) do if st.rec then real[#real + 1] = st end end
        local acc = S.Account(real, val, mode, makers, opts.have)
        if best == nil or acc.cost < best[2].cost - EPS then
            best = { steps, acc, rnd }
        end
        local nb, any = {}, false
        for _, st in ipairs(real) do
            for _, mt in ipairs(st.rec.mats) do
                local a = mt[1]
                if mode[a] == "make" and makers[a] then
                    nb[a] = (nb[a] or 0) + mt[2] * st.x
                    any = true
                end
            end
        end
        if not any or sameTable(nb, budget) then break end
        budget = nb
    end
    local out, gap = {}, nil
    for _, st in ipairs(best[1]) do
        if st.gap then
            gap = st.f
        else
            local r, x = st.rec, st.x
            local m = {}
            for i, mt in ipairs(r.mats) do m[i] = { mt[1], ceilq(mt[2] * x) } end
            out[#out + 1] = { f = st.f, t = st.t, sp = r.spell, c = ceilq(x), x = x, m = m, cost = ucost[r.spell] * x, rec = r }
        end
    end
    return { steps = out, gap = gap, total = totalOf(best[2]), round = best[3], acc = best[2] }
end

-- 给一条现成路线按同一口径算账。segs = { { f, t, 法术 } }；from = 从哪一点起算（已经练过的部分不算）
-- 返回 total（同 Solve）和每一段的 { f, t, sp, x }
function S.RouteCost(prof, segs, price, opts)
    if type(prof) == "string" then prof = S.Prof(prof) end
    if not prof then return nil end
    opts = opts or {}
    price = price or S.DefaultPrice
    local recs = S.Eligible(prof, opts.allow)
    local val, mode, makers = S.MakeValues(recs, price)
    local from = opts.from
    local steps = {}
    for _, sg in ipairs(segs) do
        local r = prof.by[sg[3]]
        local f = sg[1]
        if from and from > f then f = from end
        if r and f < sg[2] then
            local x = 0
            for s = f, sg[2] - 1 do
                local p = S.Prob(r.y, r.grey, s)
                if p <= 0 then x = nil break end
                x = x + 1 / p
            end
            if x then steps[#steps + 1] = { f = f, t = sg[2], sp = sg[3], rec = r, x = x } end
        end
    end
    local acc = S.Account(steps, val, mode, makers, opts.have)
    return totalOf(acc), steps, acc
end

-- 挂到专业助手上（设计里对外的名字）
if ns.ProfAssist then
    ns.ProfAssist.Solve = S.Solve
    ns.ProfAssist.RouteCost = S.RouteCost
end

-- 随包估算价接进价格层（优先级排在扫描价 / 手填之后）
if ns.Prices and ns.Prices.RegisterProvider then
    ns.Prices.RegisterProvider("bundle", ns.Prices.ORDER.bundle, function(item)
        local e = S.Bundle()[item]
        if e then return e[1], e[2], nil, nil end
        return nil
    end)
end
