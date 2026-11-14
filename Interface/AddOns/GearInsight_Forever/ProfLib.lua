-- 专业：页面 / 升级规划要用的推导函数（11-13 重构第 4 期从 Prof.lua 拆出来，进按需加载的 GearInsight_Forever_Prof）
--   读角色专业、专业名、事件、探针这些登录就要的留在主插件 Prof.lua（小核）；这里接着往同一个 ns.Prof 上挂函数。
--   内核里漏改的 ns.Prof.<这里的函数> 读取会经 ProfStub.lua 的元表触发加载，不会静默拿到 nil。
local _, ns = ...; ns = _G.GearInsightForever or ns

local P = ns.Prof
local function D() return ns.ProfData end
local function clean(v) if v == nil or ns.Secret(v) then return nil end return tonumber(v) end

-- ---------- 规则 ----------
-- 采集点颜色（经典规则）：技能 < 需求 = 采不了；需求 +25 内橙、+50 内黄、+100 内绿，再高灰
function P.GatherColor(need, rank)
    if not rank then return nil end
    if rank < need then return "red" end
    if rank < need + 25 then return "orange" end
    if rank < need + 50 then return "yellow" end
    if rank < need + 100 then return "green" end
    return "grey"
end
P.HEX = { red = "ff4040", orange = "ff8040", yellow = "ffff00", green = "40c040", grey = "808080" }
P.COLOR_NAME = { red = { "采不了", "too low" }, orange = { "橙", "orange" }, yellow = { "黄", "yellow" }, green = { "绿", "green" }, grey = { "灰", "grey" } }

-- 配方颜色：黄色以前橙；黄到绿之间黄；绿到灰之间绿；之后灰
function P.RecipeColor(step, rank)
    if not rank then return nil end
    if rank >= step.gr then return "grey" end
    if rank >= step.g then return "green" end
    if rank >= step.y then return "yellow" end
    return "orange"
end

-- 当前档位：技能上限对应哪一档（1..4）；上限读不到时按技能推
function P.TierIndex(key, s)
    local p = D().profs[key]
    if not p then return nil end
    local cap = s and (s.m or 0) or 0
    for i, t in ipairs(p.tiers) do if cap > 0 and cap <= t.cap then return i end end
    for i, t in ipairs(p.tiers) do if (s and s.r or 0) < t.cap then return i end end
    return #p.tiers
end

-- 下一档：{ tier, idx, ready=技能够了, lvOk=等级够了 }；已到专家返回 nil
function P.NextTier(key, s, level)
    local p = D().profs[key]
    local i = P.TierIndex(key, s)
    if not p or not i or i >= #p.tiers then return nil end
    local t = p.tiers[i + 1]
    local r = s and s.r or 0
    return { tier = t, idx = i + 1, ready = t.sk ~= nil and r >= t.sk, lvOk = (t.lv or 0) <= (level or 0) }
end

-- 冲级路线里「现在这一步」
function P.RouteStep(key, rank)
    local p = D().profs[key]
    if not p or not p.route then return nil end
    for _, st in ipairs(p.route) do
        if st.f and rank >= st.f and rank < st.t then return st end
    end
    return nil
end

-- 区域地图：子区域（主城 / 小地图）往上找到区域那一级
function P.CurrentZone()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
    m = ok and clean(m) or nil
    for _ = 1, 5 do
        if not m or not C_Map.GetMapInfo then break end
        local ok2, info = pcall(C_Map.GetMapInfo, m)
        if not ok2 or type(info) ~= "table" then break end
        if info.mapType == 3 or (D().zones[m]) then return m end
        m = info.parentMapID
    end
    return m
end

-- 这张图能采 / 能剥什么（只列玩家有的采集专业）；返回 nil = 这张图没有资料
function P.ZoneGather(m, skills)
    local z = D().zones[m]
    if not z then return nil end
    local out = {}
    local function add(key, list)
        if not list or not skills[key] then return end
        local r = skills[key].r
        for _, n in ipairs(list) do out[#out + 1] = { key = key, name = ns.L(n[1], n[4] or n[1]), need = n[2], n = n[3], color = P.GatherColor(n[2], r) } end
    end
    add("herbalism", z.h)
    add("mining", z.o)
    if z.sk and skills.skinning then
        local r = skills.skinning.r
        out[#out + 1] = { key = "skinning", lo = z.sk[1], hi = z.sk[2], need = z.sk[3], needHi = z.sk[4],
            color = P.GatherColor(z.sk[4], r) == "red" and P.GatherColor(z.sk[3], r) or P.GatherColor(z.sk[4], r) }
    end
    return out
end

-- 能做的经验食物：学会了（学习技能 ≤ 烹饪）、还会涨点或不涨点都行、使用等级 ≤ 角色等级；按使用等级从高到低
function P.XpFoods(cookRank, level, m)
    local z = m and D().zones[m]
    local here = {}
    for _, it in ipairs(z and z.ck or {}) do here[it] = true end
    local out = {}
    for _, f in ipairs(D().foods) do
        if f.learn <= (cookRank or 0) and (f.use or 1) <= (level or 60) then
            local local_ = false
            for _, mt in ipairs(f.m) do if here[mt[1]] then local_ = true end end
            out[#out + 1] = { f = f, here = local_ }
        end
    end
    table.sort(out, function(a, b)
        if a.here ~= b.here then return a.here end
        if a.f.use ~= b.f.use then return a.f.use > b.f.use end
        return a.f.learn > b.f.learn
    end)
    return out
end

-- 图纸属于哪个专业：拿蓝图英文名对营地设施英文名
function P.BlueprintProf(bp)
    local nm = (bp.en or ""):gsub("^Blueprint:%s*", "")
    for key, tiers in pairs(D().camp.profs or {}) do
        for _, t in ipairs(tiers) do if t.en == nm then return key end end
    end
    if nm == "Cookie's Feast" then return "cooking" end
    return nil
end

-- 传承里程碑领过没：成就能查就按成就；查不了按本账号记下的角色技能推算（第二个返回值 = "ach" / "guess"）
local function achDone(id)
    if not GetAchievementInfo then return nil end
    local ok, _, _, _, completed = pcall(GetAchievementInfo, id)
    if not ok then return nil end
    return completed and true or false
end
function P.LegacyClaimed(key, at)
    local ids = ((D().legacyAch or {})[key] or {})[at]
    local known = false
    for _, id in ipairs(ids or {}) do
        local d = achDone(id)
        if d then return true, "ach" end
        if d == false then known = true end
    end
    if known then return false, "ach" end
    for _, e in ipairs(P.AccountSkills()) do
        if e.key == key and (e.r or 0) >= at then return true, "guess" end
    end
    return false, "guess"
end

-- 策略：level = 不耽误升级（默认）/ balance = 均衡 / prof = 专业优先
-- 10-18 用户拍板目标只有「升级最快」+ 截图「这三个好像点了没区别」：策略固定 level，界面按钮已去掉；
--   以前存过的 profStrategy（均衡 / 专业优先）一律不再生效
function P.Strategy() return "level" end
function P.SetStrategy() if ns.db.ui then ns.db.ui.profStrategy = nil end end

-- ---------- 升级规划（地图待办）里的专业行 ----------
local GATHER = { herbalism = true, mining = true, skinning = true }
local CRAFT = { alchemy = true, blacksmithing = true, enchanting = true, engineering = true, leatherworking = true, tailoring = true }
P.GATHER, P.CRAFT = GATHER, CRAFT

local function routeDungeonLevel(fac, race, dunZh)
    if not ns.RouteLegs then return nil end
    for _, s in ipairs(ns.RouteLegs(fac, race)) do
        for _, d in ipairs(s.dun or {}) do
            if d.zh == dunZh then return tonumber((d.lv or ""):match("%d+")) end
        end
    end
    return nil
end

function ns.ProfPlanItems(lo, hi, cur)
    if not D() then return {} end
    local skills, src = P.Skills()
    local items = {}
    local function add(t) if t.lv >= lo and t.lv <= hi then items[#items + 1] = t end end
    local fac = UnitFactionGroup and UnitFactionGroup("player")
    local race = ns.RouteRace and ns.RouteRace()
    local have = next(skills) ~= nil
    -- v2 P2：选好还没学的专业也进「进城」清单（去学初级）
    local planSk = P.PlanSkills and P.PlanSkills(skills) or skills
    if not have and not next(planSk) then
        add({ lv = math.max(lo, math.min(cur, hi)), kind = "prof", sub = "none", st = "now", src = src })
        return items
    end
    local legs = P.Legs and P.Legs(fac, race) or {}
    -- 顺路采集：路线换图的那一级（以及当前等级）出一行，按「现在的技能」上色；v2 R1：带「离开前要到多少」
    local hasGather = skills.herbalism or skills.mining or skills.skinning
    if hasGather and ns.RouteZones then
        local prev
        for lv = lo, hi do
            local cz = ns.RouteZones(fac, race, lv).current
            local main = cz[1] and cz[1].zone
            local key = main and tostring(main.m) or ""
            if main and (key ~= prev or lv == cur) then
                local gates = {}
                local li = P.LegFor and P.LegFor(legs, lv, main.m)
                if li and legs[li].m == main.m then
                    for _, gk in ipairs({ "herbalism", "mining", "skinning" }) do
                        local g = skills[gk] and P.Gate(legs, li, gk, skills[gk].r)
                        if g then gates[#gates + 1] = g end
                    end
                end
                add({ lv = lv, kind = "prof", sub = "gather", st = lv <= cur and "now" or "future", zone = main,
                    list = P.ZoneGather(main.m, skills), gates = gates })
            end
            prev = key
        end
    end
    -- v2 R2 / R3：这一段的进城清单（现在）+ 往后每个专业下一档最近的训练师（预告）
    local learned = {}
    local ci = P.CurLeg and P.CurLeg(legs, fac, race, cur)
    if ci then
        local h = P.Hub(legs, ci, planSk, cur, true)
        if h then
            add({ lv = cur, kind = "prof", sub = "hub", hub = h, st = "now" })
            for _, e in ipairs(h.learn) do learned[e.key] = true end
        end
        -- 这一段学不了、技能已经够了的 → 回主城（学职业技能时）顺路学
        for _, ch in ipairs(P.CityHub(fac, race, planSk, cur, learned)) do
            add({ lv = cur, kind = "prof", sub = "hub", hub = ch, st = "now" })
            for _, e in ipairs(ch.learn) do learned[e.key] = true end
        end
        local seen = {}
        for k in pairs(learned) do seen[k] = true end
        for j = ci + 1, #legs do
            local fh = P.Hub(legs, j, planSk, cur, false)
            if fh then
                local keep = {}
                for _, e in ipairs(fh.learn) do
                    if not seen[e.key] then keep[#keep + 1] = e; seen[e.key] = true end
                end
                if #keep > 0 then
                    fh.learn = keep
                    add({ lv = legs[j].lo, kind = "prof", sub = "hub", hub = fh, st = "future" })
                end
            end
        end
        for k in pairs(seen) do learned[k] = true end
    end
    -- 经验食物（当前等级）
    if cur >= lo and cur <= hi then
        if skills.cooking then
            local cz = ns.RouteZones and ns.RouteZones(fac, race, cur).current or {}
            local m = P.CurrentZone() or (cz[1] and cz[1].zone.m)
            local foods = P.XpFoods(skills.cooking.r, cur, m)
            add({ lv = cur, kind = "prof", sub = "food", st = "now", foods = foods, zone = m })
        else
            add({ lv = cur, kind = "prof", sub = "learncook", st = "now" })
        end
        -- 11-12 专业助手：这一级最值得吃的食物（按职业挑属性）。ProfAssist.lua 不在包里（HOLD）就没有这一行
        local PA = ns.ProfAssist
        if PA and PA.Ready() then
            local _, cls = UnitClass("player")
            local best = PA.BestFoods(cur, cls, skills.cooking and skills.cooking.r or nil, 3)
            if #best > 0 then add({ lv = cur, kind = "prof", sub = "bestfood", st = best[1].can and "now" or "future", best = best }) end
        end
    end
    for key, s in pairs(skills) do
        -- 训练档位：技能接近上限才提醒；等级不够的挂到能学的那一级
        local nt = P.NextTier(key, s, cur)
        -- 路线上有训练师的已经排进「进城」行；这里只剩书 / 任务档，和路线上找不到训练师的（回主城学）
        if nt and nt.tier.sk and s.r >= nt.tier.sk - 10 and not learned[key] then
            local lvNeed = math.max(cur, nt.tier.lv or 0)
            add({ lv = lvNeed, kind = "prof", sub = "train", key = key, s = s, nt = nt,
                where = not nt.tier.via and P.TrainWhere and P.TrainWhere(fac, race, key, nt.idx) or nil,
                st = (nt.ready and nt.lvOk) and "now" or "future" })
        end
        -- 营地第一档：技能 20 学
        local camp = P.Camp(key)[1]
        if camp and s.r >= 10 and s.r < 60 and cur >= lo and cur <= hi then
            add({ lv = cur, kind = "prof", sub = "camp", key = key, s = s, camp = camp, st = s.r >= camp.sk and "now" or "future" })
        end
        -- 传承：最近一个没领的制造专业里程碑
        if CRAFT[key] and cur >= lo and cur <= hi then
            for _, at in ipairs({ 150, 225, 300 }) do
                if s.r < at then
                    local claimed, how = P.LegacyClaimed(key, at)
                    -- 不耽误升级：离里程碑 50 点以内才提醒（技能 1 点就说「练到 150」没用，10-18 用户截图）
                    local near = at - s.r <= 50 or P.Strategy() ~= "level"
                    if not claimed and near then add({ lv = cur, kind = "prof", sub = "legacy", key = key, s = s, at = at, how = how, st = "future" }) end
                    break
                end
            end
        end
        -- v2 R4 制造顺路冲：背包里已经有材料就出（不耽误升级也出）；均衡 / 专业优先一直出
        if (CRAFT[key] or key == "cooking" or key == "firstaid") and cur >= lo and cur <= hi then
            local cn = P.CraftNow and P.CraftNow(key, s, skills)
            if cn and (cn.any or P.Strategy() ~= "level") then
                add({ lv = cur, kind = "prof", sub = "craft", key = key, s = s, step = cn.step, cn = cn, st = "now" })
            end
        end
    end
    -- 图纸：路线里的副本掉你专业的营地升级图纸
    for _, bp in ipairs(D().blueprints or {}) do
        local key = P.BlueprintProf(bp)
        if key and skills[key] then
            local lv = routeDungeonLevel(fac, race, bp.dun)
            if lv then add({ lv = lv, kind = "prof", sub = "bp", key = key, bp = bp, st = lv <= cur and "now" or "future" }) end
        end
    end
    return items
end

local ICON = { gather = "Interface\\Icons\\INV_Misc_Flower_02", food = "Interface\\Icons\\INV_Misc_Food_15",
    train = "Interface\\Icons\\INV_Misc_Book_11", camp = "Interface\\Icons\\INV_Misc_Bag_EnchantedRunecloth",
    legacy = "Interface\\Icons\\INV_Misc_Map_01", craft = "Interface\\Icons\\Trade_BlackSmithing", bp = "Interface\\Icons\\INV_Scroll_03",
    hub = "Interface\\Icons\\INV_Misc_Coin_02",
    none = "Interface\\Icons\\INV_Misc_QuestionMark", learncook = "Interface\\Icons\\INV_Misc_Food_15",
    bestfood = "Interface\\Icons\\INV_Misc_Food_15" }
local GATHER_ICON = { herbalism = "Interface\\Icons\\INV_Misc_Flower_02", mining = "Interface\\Icons\\Trade_Mining",
    skinning = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" }
local PURPLE = "|cffe6a0ff"

local function colored(e)
    local c = P.HEX[e.color or "grey"] or "c8c8c8"
    return "|cff" .. c .. e.name .. "|r"
end

local function tipLines(lines)
    return function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for i, ln in ipairs(lines) do
            if i == 1 then GameTooltip:AddLine(ln, 1, 0.82, 0, true) else GameTooltip:AddLine(ln, 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end
end

-- 地图待办里画一行专业（PagePlan 的行：r.ic / r.t / r.s / r.btn）
function ns.ProfRenderRow(r, it, suffix)
    r.ic:SetTexture(ICON[it.sub] or ICON.none)
    local head = PURPLE .. ns.L("专业：", "Profession: ") .. "|r"
    local lines
    local function openPage()
        if ns.ToggleMain then ns.ToggleMain("prof") end
    end
    if it.sub == "none" then
        r.t:SetText(head .. ns.L("还没读到你的专业", "No professions found"))
        r.s:SetText(ns.L("没学专业，或者这个客户端读不到；打开一次专业窗口就能记下", "Not learned yet, or unreadable; open your profession window once"))
        lines = { ns.L("专业", "Professions"), ns.L("练级推荐：烹饪（自制食物击杀经验 +", "For leveling: Cooking (crafted food gives +") .. (D().xpPct or 5)
            .. ns.L("%）+ 急救 + 两个采集专业", "% kill XP) + First Aid + two gathering professions") }
    elseif it.sub == "learncook" then
        r.t:SetText(head .. ns.L("学烹饪：自制食物击杀经验 +", "Learn Cooking: crafted food gives +") .. (D().xpPct or 5) .. "%")
        r.s:SetText(ns.L("几乎所有自制食物都带经验加成，吃饱 15 分钟；去主城找烹饪训练师", "Almost all crafted food has the XP buff (15 min); find a Cooking trainer"))
    elseif it.sub == "gather" then
        local z = it.zone
        if not it.list then
            r.t:SetText(head .. ns.L("顺路采集 · ", "Gather on the way - ") .. ns.L(z.zh, z.en))
            r.s:SetText(ns.L("这张图暂无采集点资料（《无限》新区域）", "No node data for this zone yet (new Forever zone)"))
        else
            -- 10-18 用户截图「看不太懂」：以后的地图不按现在的技能下结论（「没有会涨点的」是错的，其实是太低）；
            --   「离开前」和要求放在同一行（说明只有一行，换行会被截掉）；剥皮不说「主力」
            local isNow = it.st == "now"
            r.t:SetText(head .. ns.L("顺路采集 · ", "Gather on the way - ") .. ns.L(z.zh, z.en))
            -- 10-18 用户截图「图标为啥是采药的？误导」：按这一行第一种采集选图标（草药 / 矿 / 剥皮）
            local first = it.list[1] and it.list[1].key
            if first then r.ic:SetTexture(GATHER_ICON[first] or ICON.gather) end
            local parts, full, minNeed, allGrey = {}, {}, nil, true
            for _, e in ipairs(it.list) do
                local plain
                if e.key == "skinning" then
                    plain = string.format(ns.L("剥皮：%d-%d 级野兽，要 %d-%d 点", "Skinning: Lv %d-%d beasts, needs %d-%d"), e.lo, e.hi, e.need, e.needHi)
                else
                    plain = e.name .. string.format(ns.L("（要 %d）", " (%d)"), e.need)
                end
                local c = P.HEX[e.color or "grey"] or "c8c8c8"
                full[#full + 1] = (isNow and ("|cff" .. c) or "") .. plain .. (isNow and "|r" or "")
                    .. (e.n and string.format(ns.L(" · 约 %d 处", ", ~%d nodes"), e.n) or "")
                if isNow then
                    if e.color ~= "red" and e.color ~= "grey" and #parts < 4 then parts[#parts + 1] = "|cff" .. c .. plain .. "|r" end
                    if e.color ~= "grey" then allGrey = false end
                    if e.color == "red" then minNeed = math.min(minNeed or 999, e.need) end
                elseif #parts < 4 then
                    parts[#parts + 1] = plain
                end
            end
            local sub
            if #parts > 0 then
                sub = table.concat(parts, ns.L("、", ", "))
            elseif allGrey then
                sub = ns.L("这里的点对你已经太低，不涨点了", "Everything here is too low to give points")
            else
                sub = string.format(ns.L("你的技能还不够采这里（最低要 %d）", "Your skill is too low here (needs %d)"), minNeed or 0)
            end
            -- v2 R1：离开前要到多少（同一行）
            local gl = {}
            local now = isNow and P.Skills() or nil
            for _, g in ipairs(it.gates or {}) do
                local mark = ""
                if now then
                    local have = (now[g.key] or {}).r or 0
                    mark = have >= g.need and " |TInterface\\RaidFrame\\ReadyCheck-Ready:0|t" or (" |cffff8040" .. ns.L("还差 ", "short ") .. (g.need - have) .. "|r")
                end
                gl[#gl + 1] = string.format(ns.L("%s到 %d", "%s %d+"), P.Name(g.key), g.need) .. mark
            end
            if #gl > 0 then
                local nx = it.gates[1].next
                sub = sub .. ns.L("；", "; ") .. "|cffffd100" .. ns.L("离开前", "Before leaving: ") .. "|r" .. table.concat(gl, ns.L("、", ", "))
                    .. string.format(ns.L("（下一张图%s）", " (next: %s)"), ns.L(nx.zh, nx.en))
            end
            r.s:SetText(sub)
            lines = { ns.L("顺路采集 · ", "Gather - ") .. ns.L(z.zh, z.en) }
            for _, l in ipairs(full) do lines[#lines + 1] = l end
            for _, g in ipairs(it.gates or {}) do
                local nx = ns.L(g.next.zh, g.next.en)
                if g.key == "skinning" then
                    lines[#lines + 1] = "|cffffd100" .. string.format(ns.L("离开%s前，剥皮最好到 %d：下一张图%s的野兽是 %s，要 %d 点起才剥得动",
                        "Before leaving %s, get Skinning to %d: %s has %s, which need %d+"), ns.L(z.zh, z.en), g.need, nx, g.what, g.need) .. "|r"
                else
                    lines[#lines + 1] = "|cffffd100" .. string.format(ns.L("离开%s前，%s最好到 %d：下一张图%s主要是%s，要 %d 点起才采得动",
                        "Before leaving %s, get %s to %d: %s is mostly %s, which needs %d+"), ns.L(z.zh, z.en), P.Name(g.key), g.need, nx, g.what, g.need) .. "|r"
                end
                if g.short then
                    lines[#lines + 1] = string.format(ns.L("这张图的点最多练到约 %d，剩下的到下一张图先采低级的", "Nodes here stop giving points around %d; finish on the easier nodes in the next zone"), g.reach)
                end
            end
            lines[#lines + 1] = isNow and ns.L("颜色按你现在的技能：橙、黄必涨，绿偶尔涨，灰不涨，红采不了", "Colors use your current skill: orange/yellow always, green sometimes, grey never, red too low")
                or ns.L("这是以后才到的地图：到时你的技能会更高，这里只列要求", "A later zone: your skill will be higher by then, so this only lists requirements")
            lines[#lines + 1] = ns.L("采集点分布是经典旧世基线，《无限》可能改过", "Node data is the Classic baseline")
        end
    elseif it.sub == "food" then
        local f = it.foods[1]
        if f then
            r.t:SetText(head .. ns.L("经验食物：", "XP food: ") .. ns.L(f.f.zh, f.f.en) .. "  |cff33ff99+" .. (D().xpPct or 5) .. ns.L("% 击杀经验", "% kill XP") .. "|r")
            local mats = {}
            for _, mt in ipairs(f.f.m) do mats[#mats + 1] = P.ItemName(mt[1]) .. "×" .. mt[2] end
            r.s:SetText((f.here and ns.L("材料这张图就有：", "Mats drop here: ") or ns.L("材料：", "Mats: ")) .. table.concat(mats, ns.L("、", ", ")))
            lines = { ns.L("能做的经验食物", "XP foods you can cook") }
            for i, e in ipairs(it.foods) do
                if i > 6 then break end
                lines[#lines + 1] = ns.L(e.f.zh, e.f.en) .. string.format(ns.L("（学 %d · 使用 %d 级%s）", " (learn %d, use Lv %d%s)"), e.f.learn, e.f.use,
                    e.here and ns.L(" · 材料本图有", ", mats here") or "")
            end
            lines[#lines + 1] = ns.L("坐下吃满 10 秒，吃饱效果 15 分钟", "Eat seated for 10 sec; Well Fed lasts 15 min")
        else
            r.t:SetText(head .. ns.L("经验食物：烹饪再练几点就有", "XP food: a few more Cooking points"))
            r.s:SetText(ns.L("美味迅猛龙肉块这类食物烹饪 25 左右能学", "Foods like Tasty Raptor Bites unlock around Cooking 25"))
        end
    elseif it.sub == "bestfood" then
        -- 11-12 专业助手：属性 / 数值来自食物法术效果，职业偏好见 ProfAssist.lua A.CLASS_PREF
        local PA = ns.ProfAssist
        local e = it.best[1]
        local function state(x)
            if x.can then return "|cff33ff99" .. ns.L("你能做", "you can cook it") .. "|r" end
            if x.unknown then return ns.L("学习技能数据待补", "skill needed: unknown") end
            if x.nocook then return string.format(ns.L("要烹饪 %d", "Cooking %d"), x.f.learn) end
            return string.format(ns.L("烹饪还差 %d 点", "%d more Cooking"), x.lack)
        end
        local function label(x)
            local kn = PA.KIND_NAME[x.kind]
            return ns.L(x.f.zh, x.f.en) .. ns.L("（", " (") .. ns.L(kn[1], kn[2]) .. " +" .. x.amt .. ns.L("）", ")")
        end
        r.t:SetText(head .. ns.L("这一级最值得吃：", "Best food now: ") .. label(e) .. "  " .. state(e))
        local mats = {}
        for _, mt in ipairs(e.f.m) do mats[#mats + 1] = PA.ItemName(mt[1]) .. "×" .. mt[2] end
        r.s:SetText(string.format(ns.L("使用 %d 级 · 材料：", "Use Lv %d - Mats: "), e.f.use or 1) .. table.concat(mats, ns.L("、", ", "))
            .. ns.L(" · 配方：", " - Recipe: ") .. PA.FoodSource(e.f)
            .. (e.now and (ns.L(" · 现在能做：", " - Now: ") .. ns.L(e.now.f.zh, e.now.f.en) .. " +" .. e.now.amt) or ""))
        lines = { ns.L("这一级最值得吃的食物（按职业挑属性）", "Best food at this level (by class)") }
        for _, x in ipairs(it.best) do
            lines[#lines + 1] = label(x) .. string.format(ns.L(" · 使用 %d 级 · ", ", use Lv %d, "), x.f.use or 1) .. state(x)
            lines[#lines + 1] = "  " .. PA.FoodBuff(x.f)
        end
        lines[#lines + 1] = ns.L("效果取自游戏里的食物法术；完整材料和出处看专业页「专业助手」的烹饪", "Effects come from the in-game food spells; see the Professions page for details")
    elseif it.sub == "train" then
        local t, s = it.nt.tier, it.s
        r.t:SetText(head .. P.Name(it.key) .. " " .. s.r .. "/" .. (s.m or "?") .. ns.L("：去学", ": train ") .. ns.L(t.zh, t.en))
        local need = {}
        if t.sk then need[#need + 1] = string.format(ns.L("技能 %d", "skill %d"), t.sk) end
        if (t.lv or 0) > 0 then need[#need + 1] = string.format(ns.L("角色 %d 级", "level %d"), t.lv) end
        local via = t.via == "book" and ns.L("（买书：", " (book: ") .. (t.name or "") .. ns.L("）", ")")
            or t.via == "quest" and ns.L("（任务：", " (quest: ") .. (t.name or "") .. ns.L("）", ")") or ns.L("（找训练师）", " (trainer)")
        local w = it.where
        if w and w.kind == "city" then
            via = string.format(ns.L("（回主城：%s 的 %s）", " (capital: %s, %s)"), ns.L(w.t.zh, w.t.en), w.t.name)
        elseif w and w.kind == "far" then
            via = string.format(ns.L("（路线和主城都没有，要专门去 %s 找 %s）", " (not on your route or in a capital: go to %s, %s)"), ns.L(w.t.zh, w.t.en), w.t.name)
        elseif w and w.kind == "none" then
            via = ns.L("（路线和主城都没有能教这一档的训练师，《无限》里在哪待实测）", " (no trainer for this rank on your route or in a capital; location in Forever still to be checked)")
        end
        r.s:SetText(ns.L("要求 ", "Needs ") .. table.concat(need, ns.L("、", ", ")) .. via)
        lines = { r.t:GetText(), r.s:GetText(), ns.L("《无限》实测：学高一档只看专业点数，不要求角色等级", "Tested in Forever: only skill points are required, no character level") }
    elseif it.sub == "camp" then
        local c = it.camp
        r.t:SetText(head .. P.Name(it.key) .. " " .. c.sk .. ns.L(" 点学营地设施：", ": camp object ") .. ns.L(c.zh, c.en))
        r.s:SetText(ns.EnSafe(c.fn ~= "" and c.fn or c.tx))
        local fire = (D().camp.fires or {})[1]
        lines = { ns.L(c.zh, c.en), ns.EnSafe(c.tx), ns.L("需要附近有营火；所有营地设施共享 1 小时冷却", "Needs a campfire; all camp objects share a 1 h cooldown"),
            (fire and fire.tool) and (ns.L("点营火要带 ", "A campfire needs ") .. ns.L(fire.tool, fire.toolEn) .. (fire.mat and (" + " .. ns.L(fire.mat, fire.matEn)) or "")) or nil }
    elseif it.sub == "legacy" then
        -- 10-18 用户截图「有点歧义」：「现在 1」像是已有 1 点传承、「可领」像要去哪领 → 写清楚是技能数、怎么给
        r.t:SetText(head .. string.format(ns.L("传承：%s练到 %d 点，账号奖励 1 点传承", "Legacy: %s to %d gives your account 1 Legacy point"), P.Name(it.key), it.at))
        r.s:SetText(string.format(ns.L("你的%s现在 %d 点；整个账号第一个练到 %d 的角色自动获得，之后的角色不再给",
                "Your %s is %d; awarded automatically to the first character on the account to reach %d"), P.Name(it.key), it.s.r, it.at)
            .. (it.how == "guess" and ns.L("（领没领过按装了插件的角色推算）", " (claimed status estimated from your characters)") or ""))
    elseif it.sub == "craft" then
        local st = it.step
        local col = P.HEX[P.RecipeColor(st, it.s.r) or "grey"]
        local mats = {}
        if it.cn then
            for _, mt in ipairs(it.cn.mats) do
                local cnt = mt.have and (" |cff" .. (mt.have >= mt.need and "33ff99" or "c8c8c8") .. mt.have .. "/" .. mt.need .. "|r") or ("×" .. mt.need)
                mats[#mats + 1] = P.ItemName(mt.item) .. cnt
            end
        else
            for _, mt in ipairs(st.m) do mats[#mats + 1] = P.ItemName(mt[1]) .. "×" .. mt[2] end
        end
        r.t:SetText(head .. P.Name(it.key) .. " " .. st.f .. "-" .. st.t .. "：|cff" .. col .. ns.L(st.zh, st.en) .. "|r ×" .. st.c)
        local wh = it.cn and P.WHERE[it.cn.where]
        r.s:SetText(ns.L("材料（背包/需要）：", "Mats (bag/need): ") .. table.concat(mats, ns.L("、", ", ")) .. (wh and ("\n" .. ns.L(wh[1], wh[2])) or ""))
        lines = { r.t:GetText(), r.s:GetText(), ns.L("次数是期望值：黄色以后不是每次都涨点", "Counts are expected values; yellow/green recipes don't always skill up") }
    elseif it.sub == "hub" then
        local h = it.hub
        local zn = ns.L(h.leg.zh, h.leg.en)
        local parts = {}
        lines = { ns.L("进城：", "Town stop: ") .. zn }
        for _, e in ipairs(h.learn) do
            local t = e.nt.tier
            -- 以后的段写「急救中级（技能到 50）」；现在的段写「急救：学中级」
            local txt = it.st == "now" and (P.Name(e.key) .. ns.L("：学", ": train ") .. ns.L(t.zh, t.en))
                or (P.Name(e.key) .. ns.L("", " ") .. ns.L(t.zh, t.en))
            if e.cond then txt = txt .. string.format(ns.L("（技能到 %d）", " (at %d skill)"), t.sk) end
            if e.must then txt = "|cffff4040" .. txt .. ns.L("（这次必须学）", " (do it now)") .. "|r" end
            parts[#parts + 1] = txt
            lines[#lines + 1] = txt .. string.format(" · %s %.1f, %.1f", e.t.name, e.t.x, e.t.y)
            if e.must then
                lines[#lines + 1] = e.nextLeg and string.format(ns.L("下一个能学的训练师在 %d 级的 %s", "Next trainer is at level %d in %s"), e.nextLeg.lo, ns.L(e.nextLeg.zh, e.nextLeg.en))
                    or ns.L("路线后面没有能学这一档的训练师了", "No trainer for this rank later on the route")
            end
        end
        for _, e in ipairs(h.smelt) do
            local txt = ns.L("熔炼 ", "Smelt ") .. P.ItemName(e.sm.item) .. " ×" .. e.n
            parts[#parts + 1] = txt; lines[#lines + 1] = txt
        end
        for _, e in ipairs(h.buy) do
            local txt = ns.L("买 ", "Buy ") .. P.ItemName(e.item) .. " ×" .. e.n
            parts[#parts + 1] = txt
            lines[#lines + 1] = txt .. string.format(" · %s %.1f, %.1f", e.vendor, e.x, e.y)
        end
        for _, e in ipairs(h.make) do
            local txt = ns.L("做 ", "Craft ") .. ns.L(e.step.zh, e.step.en) .. " ×" .. e.step.c
            parts[#parts + 1] = txt
            lines[#lines + 1] = txt .. string.format(" · %s %.1f, %.1f", e.step.fo == 1 and ns.L("铁砧", "anvil") or ns.L("熔炉", "forge"), e.x, e.y)
        end
        -- 10-18 用户截图：「下次能学 · 湿地」看不懂 → 「路过湿地时去学」
        if h.city then
            r.t:SetText(head .. ns.L("回主城时 · ", "Next capital visit - ") .. zn)
        elseif it.st == "now" then
            r.t:SetText(head .. ns.L("进城要做 · ", "Town stop - ") .. zn)
        else
            r.t:SetText(head .. string.format(ns.L("路过%s时去学", "Train when you pass %s"), zn))
        end
        r.s:SetText(table.concat(parts, ns.L("；", "; ")) .. (suffix or ""))
        lines[#lines + 1] = ns.L("训练师 / 商人 / 铁砧熔炉的位置是经典旧世基线，《无限》可能挪过", "Trainer / vendor / anvil locations are the Classic baseline")
        if #h.pts > 0 and ns.ShowOnMap then
            r.btn:SetText(ns.L("地图", "Map")); r.btn:Show(); r.btn:SetEnabled(true)
            r.btn:SetScript("OnClick", function() ns.ShowOnMap(h.leg.m, h.pts, zn) end)
            r:SetScript("OnEnter", tipLines(lines))
            return
        end
        suffix = nil
    elseif it.sub == "bp" then
        local bp = it.bp
        r.t:SetText(head .. ns.L("图纸 · ", "Blueprint - ") .. (bp.dun or "") .. "·" .. (bp.boss or ""))
        r.s:SetText(ns.L(bp.zh or bp.en, bp.en) .. ns.L("（", " (") .. P.Name(it.key) .. ns.L(" 140 档营地设施）", " camp tier 2)"))
        lines = { r.t:GetText(), r.s:GetText(), ns.L("Beta 实测掉落；掉率未知", "Seen in Beta; drop rate unknown") }
    end
    r.s:SetText((r.s:GetText() or "") .. (suffix or ""))
    r.btn:SetText(ns.L("专业页", "Professions")); r.btn:Show(); r.btn:SetEnabled(true)
    r.btn:SetScript("OnClick", openPage)
    if lines then r:SetScript("OnEnter", tipLines(lines)) end
end
