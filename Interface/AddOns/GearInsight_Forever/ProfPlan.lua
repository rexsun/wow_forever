-- 专业 v2「时刻表」引擎（10-18，docs/forever-profession-v2-design.md 第三节）：把专业要做的事钉在升级路线的每张图 / 每次进城上。
--   R1 采集门槛：离开这张图前，技能要够下一张图的主力资源
--   R2 能学就学：路过能教下一档的训练师就学；下一个训练师很远、又快到上限 → 「这次必须学」
--   R3 进城清单：学 / 熔炼 / 买材料 / 要铁砧熔炉的配方，一条做完
--   R4 制造顺路冲：冲级路线这一步 + 背包里有多少材料 + 在哪做（随时 / 营火边 / 进城）
-- ⛔ 只用确定的数据（采集点需求、档位要求、路线顺序、训练师 / 熔炉 / 商人位置），不估算刷多快。
-- ⛔ 在 HOLD（_hold.txt）：没在游戏里测完不进发行包。
local _, ns = ...; ns = _G.GearInsightForever or ns
local P = ns.Prof
if not P then return end

local function D() return ns.ProfData end
local function L(a, b) return ns.L(a, b) end

-- 离上限还差不到 MUST_GAP 点，而路线上下一个能学的训练师在 MUST_LEVELS 级以后：这次必须学
P.MUST_GAP = 15
P.MUST_LEVELS = 5

-- ---------- 路线 ----------
-- 按等级排好的地图段；同一张图连着的段合并
function P.Legs(fac, race)
    local out = {}
    for _, s in ipairs(ns.RouteLegs and ns.RouteLegs(fac, race) or {}) do
        local m = s.main and s.main.m
        if m and m ~= 0 then
            local last = out[#out]
            if last and last.m == m then
                last.hi = math.max(last.hi, s.hi)
            else
                out[#out + 1] = { lo = s.lo, hi = s.hi, m = m, zh = s.main.zh, en = s.main.en }
            end
        end
    end
    return out
end

-- 等级 lv 正在走的那一段（最后一个 lo ≤ lv 的）
function P.LegAt(legs, lv)
    local idx
    for i, l in ipairs(legs) do if l.lo <= lv then idx = i end end
    return idx
end

-- 段和段的等级会重叠（西部荒野 13-15 / 黑海岸 14-19）：优先取「这一级升级路线说的当前地图」那一段
-- 10-18 用户截图：14 级取成黑海岸，西部荒野的采集行就没了「离开前」
function P.LegFor(legs, lv, m)
    if m then
        for i, l in ipairs(legs) do
            if l.m == m and l.lo <= lv and lv <= l.hi then return i end
        end
    end
    return P.LegAt(legs, lv)
end
function P.CurLeg(legs, fac, race, lv)
    local cz = ns.RouteZones and ns.RouteZones(fac, race, lv)
    local main = cz and cz.current and cz.current[1] and cz.current[1].zone
    return P.LegFor(legs, lv, main and main.m)
end

function P.NodeName(n) return L(n[1], n[4] or n[1]) end

-- ---------- R1 采集门槛 ----------
-- 一张图的主力需求：草药 / 矿取数量最多的两种里**要求低的**（到了至少有一种主力能采，边采边涨）；
-- 剥皮取这张图大多数野兽等级的下沿
function P.ZoneGate(m, key)
    local z = D().zones[m]
    if not z then return nil end
    if key == "skinning" then
        if not z.sk then return nil end
        return { need = z.sk[3], what = string.format(L("%d-%d 级野兽", "Lv %d-%d beasts"), z.sk[1], z.sk[2]) }
    end
    local list = (key == "herbalism" and z.h) or (key == "mining" and z.o) or nil
    if not list or not list[1] then return nil end
    local need, names = nil, {}
    for i = 1, math.min(2, #list) do
        need = math.min(need or 999, list[i][2])
        names[#names + 1] = P.NodeName(list[i])
    end
    return { need = need, what = table.concat(names, L("、", ", ")) }
end

-- 这张图的点最多能把技能练到多少（最高需求 + 100 变灰）；剥皮按怪物等级上沿
function P.ZoneReach(m, key)
    local z = D().zones[m]
    if not z then return nil end
    if key == "skinning" then return z.sk and (z.sk[4] + 100) or nil end
    local list = (key == "herbalism" and z.h) or (key == "mining" and z.o) or nil
    local top
    for _, n in ipairs(list or {}) do top = math.max(top or 0, n[2] + 100) end
    return top
end

-- 第 i 段之后、下一张有采集资料的图要多少技能：{ key, need, what, next = 段, ok, reach, short }
-- 中间夹着《无限》新区域（没资料）就跳过它往后找，不编数
function P.Gate(legs, i, key, rank)
    for j = i + 1, #legs do
        if legs[j].m ~= legs[i].m and D().zones[legs[j].m] then
            local g = P.ZoneGate(legs[j].m, key)
            if not g then return nil end
            g.key, g.next = key, legs[j]
            g.ok = rank ~= nil and rank >= g.need
            g.reach = P.ZoneReach(legs[i].m, key)
            g.short = g.reach and g.reach < g.need or false   -- 这张图练不到门槛
            return g
        end
    end
    return nil
end

-- ---------- 阵营 ----------
-- 站点带阵营 A / H / N：⛔ 只用中立和自己阵营的（不然联盟会被指去塔伦米尔的部落训练师）
function P.SideOK(sd)
    if sd == nil or sd == "N" then return true end
    local fac = UnitFactionGroup and UnitFactionGroup("player")
    return (fac == "Alliance" and sd == "A") or (fac == "Horde" and sd == "H")
end

-- 铁砧 / 熔炉列表里第一个自己阵营能用的 {x, y, 阵营}
function P.FirstSpot(list)
    for _, p in ipairs(list or {}) do
        if P.SideOK(p[3]) then return p end
    end
    return nil
end

-- ---------- R2 训练 ----------
-- 这张图有没有能教到第 idx 档（1..4）的训练师
function P.TrainerIn(m, key, idx)
    local st = D().stations and D().stations[m]
    for _, t in ipairs(st and st.t or {}) do
        -- 10-22 GI-14：第 7 位 "g" = 攻略站的《无限》新训练师（新手区初级训练师 / 泽风岛），名字后标「攻略值」，众包确认后构建器会去掉
        if t[1] == key and t[2] + 1 >= idx and P.SideOK(t[6]) then
            return { name = t[3] .. (t[7] == "g" and L("（攻略值）", " (guide)") or ""), x = t[4], y = t[5], guide = t[7] == "g" or nil }
        end
    end
    return nil
end

-- 全地图找（路线和主城都没有时）：给「要专门跑一趟」的提醒用
function P.AnyTrainer(key, idx)
    for m, st in pairs(D().stations or {}) do
        local t = P.TrainerIn(m, key, idx)
        if t then t.m, t.zh, t.en = m, st.zh, st.en; return t end
    end
    return nil
end

function P.NextTrainerLeg(legs, i, key, idx)
    for j = i + 1, #legs do
        local t = P.TrainerIn(legs[j].m, key, idx)
        if t then return legs[j], t end
    end
    return nil
end

-- 下一档要找训练师学（书 / 任务档不算）；s.plan = 选了还没学 → 学初级
local function trainTier(key, s)
    if s.plan then
        local p = D().profs[key]
        return p and { tier = p.tiers[1], idx = 1, ready = true, lvOk = true } or nil
    end
    local nt = P.NextTier(key, s, 60)
    if nt and not nt.tier.via and nt.tier.sk then return nt end
    return nil
end

-- ---------- 背包 ----------
-- P.BagCount 11-13 挪进主插件 Prof.lua 小核（经验加成检查登录就用）

-- ---------- R3 进城清单 ----------
-- 第 i 段这张图能顺手办的专业事。isNow = 现在就在这一段（按当前技能 / 背包算）；否则只给「下一次能学」的预告
-- opts.city = 主城（不在路线上，回城学职业技能时顺路办）：不标「必须」；opts.skip = 已经排在别处的专业
function P.Hub(legs, i, skills, cur, isNow, opts)
    opts = opts or {}
    local leg = legs[i]
    local st = D().stations and D().stations[leg.m]
    if not st then return nil end
    local h = { leg = leg, learn = {}, smelt = {}, buy = {}, make = {}, pts = {}, city = opts.city }
    local function pt(x, y, label)
        if x and #h.pts < 5 then h.pts[#h.pts + 1] = { x, y, label } end
    end
    for key, s in pairs(skills) do
        local nt = not (opts.skip and opts.skip[key]) and trainTier(key, s) or nil
        local t = nt and P.TrainerIn(leg.m, key, nt.idx)
        if t then
            local ready = s.r >= nt.tier.sk
            if isNow then
                if ready then
                    local nl = not opts.city and P.NextTrainerLeg(legs, i, key, nt.idx) or nil
                    local must = not opts.city and not s.plan and (nt.tier.cap - 75) - s.r <= P.MUST_GAP and (not nl or nl.lo - cur >= P.MUST_LEVELS)
                    h.learn[#h.learn + 1] = { key = key, nt = nt, t = t, must = must, nextLeg = nl }
                    pt(t.x, t.y, t.name)
                end
            else
                h.learn[#h.learn + 1] = { key = key, nt = nt, t = t, cond = not ready }
                pt(t.x, t.y, t.name)
            end
        end
    end
    if not isNow then return #h.learn > 0 and h or nil end
    -- 熔炼：有熔炉、学会了、背包里有矿
    local mi = skills.mining
    local forge = P.FirstSpot(st.f)
    if mi and forge then
        for _, sm in ipairs(D().profs.mining and D().profs.mining.smelt or {}) do
            if sm.learn <= mi.r then
                local have = P.BagCount(sm.m[1][1])
                if have and have >= sm.m[1][2] then
                    h.smelt[#h.smelt + 1] = { sm = sm, n = math.floor(have / sm.m[1][2]) }
                end
            end
        end
        if #h.smelt > 0 then pt(forge[1], forge[2], L("熔炉", "Forge")) end
    end
    -- 制造：冲级路线这一步要的商人材料（扣掉背包里的）+ 要铁砧 / 熔炉的配方
    for key, s in pairs(skills) do
        local step = P.CRAFT[key] and P.RouteStep(key, s.r)
        if step then
            for _, v in ipairs(st.v or {}) do
                for _, it in ipairs(P.SideOK(v[5]) and v[2] or {}) do
                    for _, mt in ipairs(step.m) do
                        if mt[1] == it then
                            local miss = mt[2] - (P.BagCount(it) or 0)
                            if miss > 0 then
                                h.buy[#h.buy + 1] = { item = it, n = miss, vendor = v[1], x = v[3], y = v[4], key = key }
                                pt(v[3], v[4], v[1])
                            end
                        end
                    end
                end
            end
            local spot = (step.fo == 1 and P.FirstSpot(st.a)) or (step.fo == 3 and P.FirstSpot(st.f)) or nil
            if spot and not P.CampHas(key, step.fo, skills) then
                h.make[#h.make + 1] = { key = key, step = step, x = spot[1], y = spot[2] }
                pt(spot[1], spot[2], step.fo == 1 and L("铁砧", "Anvil") or L("熔炉", "Forge"))
            end
        end
    end
    if #h.learn + #h.smelt + #h.buy + #h.make == 0 then return nil end
    return h
end

-- 主城：路线不经过，但每两级回城学职业技能时都会去 —— 路线这一段学不了、技能已经够了的，排到「回主城时」
P.CAPITAL = { Human = 1453, Dwarf = 1455, Gnome = 1455, NightElf = 1457, Orc = 1454, Troll = 1454, Tauren = 1456, Scourge = 1458, Undead = 1458 }
P.CAPITALS = { Alliance = { 1453, 1455, 1457 }, Horde = { 1454, 1456, 1458 } }
function P.CityHub(fac, race, skills, cur, skip)
    local order, seen = {}, {}
    local home = P.CAPITAL[race or ""]
    if home then order[1] = home; seen[home] = true end
    for _, m in ipairs(P.CAPITALS[fac or ""] or {}) do
        if not seen[m] then order[#order + 1] = m end
    end
    -- 先本族主城，学不全的再看同阵营别的主城；返回列表
    local out, done = {}, {}
    for k in pairs(skip or {}) do done[k] = true end
    for _, m in ipairs(order) do
        local st = D().stations and D().stations[m]
        if st then
            local h = P.Hub({ { lo = cur, hi = cur, m = m, zh = st.zh, en = st.en } }, 1, skills, cur, true, { city = true, skip = done })
            -- 主城只为「学」专门去；熔炼 / 买材料是顺手的，没有要学的就不单独出一行
            if h and #h.learn > 0 then
                h.smelt, h.buy, h.make = {}, {}, {}   -- 买 / 熔炼 / 铁砧已经排在路线这一段的「进城」里，主城行只管学
                h.pts = {}
                for _, e in ipairs(h.learn) do h.pts[#h.pts + 1] = { e.t.x, e.t.y, e.t.name } end
                out[#out + 1] = h
                for _, e in ipairs(h.learn) do done[e.key] = true end
            end
        end
    end
    return out
end

-- 路线上没有训练师的那一档去哪学：{ kind = "city" | "far" | "none", t = 训练师（带 zh / en / m） }
function P.TrainWhere(fac, race, key, idx)
    local home = P.CAPITAL[race or ""]
    local order = { home }
    for _, m in ipairs(P.CAPITALS[fac or ""] or {}) do if m ~= home then order[#order + 1] = m end end
    for _, m in ipairs(order) do
        local t = m and P.TrainerIn(m, key, idx)
        if t then
            local st = D().stations[m]
            t.m, t.zh, t.en = m, st.zh, st.en
            return { kind = "city", t = t }
        end
    end
    local t = P.AnyTrainer(key, idx)
    if t then return { kind = "far", t = t } end
    return { kind = "none" }
end

-- ---------- 选专业（v2 P2，10-18 拍板：只有「升级最快」一个目标） ----------
P.PRIMARY = { herbalism = true, mining = true, skinning = true, alchemy = true, blacksmithing = true, enchanting = true,
    engineering = true, leatherworking = true, tailoring = true }
-- 每个职业一套：主专业两个 + 三个副专业都学。数据在 ProfData.pick（scripts/forever_prof_pick.py，网站 / 小程序同一份）
--   理由来自营地 / 食物数据（ProfData.camp / xpPct），这里只有职业补的那一句
P.PICK = (D() and D().pick and D().pick.profs) or { "skinning", "leatherworking", "cooking", "fishing", "firstaid" }
P.PICK_NOTE = (D() and D().pick and D().pick.notes) or {}

local function planStore()
    ns.db.prof = ns.db.prof or {}
    ns.db.prof.planned = ns.db.prof.planned or {}
    return ns.db.prof.planned
end
local function charKey() return (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?") end

-- 这个角色选好要学的专业（列表），没选返回 nil
function P.Planned() return planStore()[charKey()] end
function P.SetPlanned(list)
    planStore()[charKey()] = list
    if ns.RefreshPlanPage then ns.RefreshPlanPage() end
end

-- 规划用的专业：已学的 + 选了还没学的（主专业最多两个，满了就不加）
function P.PlanSkills(skills)
    local out, prim = {}, 0
    for k, s in pairs(skills) do
        out[k] = s
        if P.PRIMARY[k] then prim = prim + 1 end
    end
    for _, k in ipairs(P.Planned() or {}) do
        if not out[k] and D().profs[k] and not (P.PRIMARY[k] and prim >= 2) then
            out[k] = { r = 0, m = 0, plan = true }
            if P.PRIMARY[k] then prim = prim + 1 end
        end
    end
    return out
end

-- ---------- 我的时刻表（v2 P2）：一个专业沿路线的节点 ----------
-- 节点 { lv, kind = "train" | "gate", text, done }；按等级排
function P.Timeline(key, s, fac, race, cur)
    local legs = P.Legs(fac, race)
    local ci = P.CurLeg(legs, fac, race, cur) or 1
    local nodes = {}
    if P.GATHER[key] then
        for i = ci, #legs do
            local g = P.Gate(legs, i, key, s.r)
            if g then
                nodes[#nodes + 1] = { lv = legs[i].hi, kind = "gate", need = g.need, done = g.ok,
                    text = string.format(L("%d 级离开%s前到 %d（下一张图 %s）", "Lv %d, before leaving %s: %d (next: %s)"),
                        legs[i].hi, L(legs[i].zh, legs[i].en), g.need, L(g.next.zh, g.next.en)) }
            end
        end
    end
    local p = D().profs[key]
    local nt = trainTier(key, s)
    local from = ci
    local lastLv = cur
    for idx = nt and nt.idx or 99, #(p and p.tiers or {}) do
        local t = p.tiers[idx]
        if t.via then break end
        local found
        for j = from, #legs do
            local tr = P.TrainerIn(legs[j].m, key, idx)
            if tr then found = { j = j, tr = tr }; break end
        end
        local name = L(t.zh, t.en)
        -- 技能已经够了、路线这一段又学不了：和规划里「回主城时」一致，排在现在（⛔ 游戏是 Lua 5.1，没有 goto）
        local city
        if idx == (nt and nt.idx) and (s.r or 0) >= (t.sk or 0) and not (found and found.j == ci) then
            local w = P.TrainWhere(fac, race, key, idx)
            if w.kind == "city" then city = w end
        end
        if city then
            nodes[#nodes + 1] = { lv = cur, kind = "train",
                text = L(string.format("现在：回主城时在%s学%s", city.t.zh, t.zh), string.format("Now: train %s in %s on your next capital visit", t.en, city.t.en)) }
            lastLv = cur
        elseif found then
            local lv = found.j == ci and cur or legs[found.j].lo
            local lg = legs[found.j]
            nodes[#nodes + 1] = { lv = lv, kind = "train",
                text = L(string.format("%d 级在%s学%s（技能到 %d）", lv, lg.zh, t.zh, t.sk or 0),
                    string.format("Lv %d: train %s in %s (at %d skill)", lv, t.en, lg.en, t.sk or 0)) }
            from, lastLv = found.j + 1, lv
        else
            local w = P.TrainWhere(fac, race, key, idx)
            local where = w.t and L(w.t.zh, w.t.en) or L("待实测", "unknown")
            nodes[#nodes + 1] = { lv = lastLv, kind = "train", far = w.kind ~= "city",
                text = string.format(L("学%s（技能到 %d）：路线上没有，去%s", "Train %s (at %d skill): not on the route, go to %s"), name, t.sk or 0, where) }
        end
    end
    table.sort(nodes, function(a, b) if a.lv ~= b.lv then return a.lv < b.lv end return a.kind > b.kind end)
    return nodes
end

-- 营地设施能不能代替城里的铁砧 / 熔炉：锻造 140 铁砧；锻造 300 大师级熔炉 / 采矿 300 熔火铸造厂
function P.CampHas(key, focus, skills)
    local bs, mi = skills.blacksmithing, skills.mining
    if focus == 1 then return bs and bs.r >= 140 or false end
    if focus == 3 then return (bs and bs.r >= 300) or (mi and mi.r >= 300) or false end
    return false
end

-- ---------- R4 制造顺路冲 ----------
-- 冲级路线这一步：背包里有多少材料、在哪做
function P.CraftNow(key, s, skills)
    local step = P.RouteStep(key, s.r)
    if not step then return nil end
    local mats, any = {}, false
    for _, mt in ipairs(step.m) do
        local have = P.BagCount(mt[1])
        if have and have > 0 then any = true end
        mats[#mats + 1] = { item = mt[1], need = mt[2], have = have }
    end
    local where
    if step.fo == 1 then
        where = P.CampHas(key, 1, skills) and "camp" or "anvil"
    elseif step.fo == 3 then
        where = P.CampHas(key, 3, skills) and "camp" or "forge"
    elseif key == "cooking" then
        where = "fire"
    else
        where = "any"
    end
    return { step = step, mats = mats, any = any, where = where }
end

P.WHERE = {
    any = { "随时能做（营火边歇着时做）", "Craft anytime (e.g. while resting at camp)" },
    fire = { "营火边做", "Cook at a campfire" },
    camp = { "营地设施就能做，不用进城", "Your camp object covers it; no town trip" },
    anvil = { "要铁砧：排到下次进城", "Needs an anvil: do it on your next town stop" },
    forge = { "要熔炉：排到下次进城", "Needs a forge: do it on your next town stop" },
}
