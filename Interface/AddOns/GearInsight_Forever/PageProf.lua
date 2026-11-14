-- 「专业」页（v2，10-18，docs/forever-profession-v2-design.md 第四节）：选专业 / 我的时刻表 / 冲级路线 / 配方库 / 营地与传承
--   选专业只有一个目标：升级最快（10-18 用户拍板）；选好的专业写进 ns.db.prof.planned，升级规划按它出「去学初级」。
--   10-18 用户「这三个好像点了没区别」：去掉「不耽误升级 / 均衡 / 专业优先」三个策略按钮，目标只有升级最快（P.Strategy 固定 level）
--   我的时刻表：每个专业一条 1-60 级的轴，节点 = 路线上的训练和采集门槛（ProfPlan.lua P.Timeline），点节点跳到升级规划那一级。
--   配方库：ProfRecipes.lua（全部配方），按技能段 / 部位 / 《无限》新增 / 我能穿 / 搜索筛。
--   数据 ProfData.lua / ProfRecipes.lua；推导函数在 Prof.lua / ProfPlan.lua。⛔ 在 HOLD 里，没实测完不进发行包。
local _, ns = ...; ns = _G.GearInsightForever or ns

local page
local tab                   -- pick / time / route / recipes / camp；第一次打开：有专业 = 时刻表，没有 = 选专业
local routeKey              -- 冲级路线 / 配方库选中的专业
local flt = { range = 0, slot = 1, new = false, mine = false, q = "", src = 1 }   -- 配方库筛选（src = SRC_FILTERS 下标）
local shortSource   -- 配方出处短句（定义在配方库那段，冲级路线也用）
local ROW_H = 36
local TIME_H = 58
local MAX_RECIPES = 120

local function D() return ns.ProfData end
local P = function() return ns.Prof end

local function getRow(i)
    local r = page.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, page.child)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 1, 1, 0.03)
    r.ic = r:CreateTexture(nil, "ARTWORK"); r.ic:SetSize(24, 24); r.ic:SetPoint("TOPLEFT", 4, -5); r.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.t:SetPoint("TOPLEFT", 34, -3); r.t:SetPoint("RIGHT", -8, 0); r.t:SetJustifyH("LEFT"); r.t:SetWordWrap(false)
    r.s = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.s:SetPoint("TOPLEFT", 34, -20); r.s:SetPoint("RIGHT", -8, 0); r.s:SetJustifyH("LEFT"); r.s:SetWordWrap(false)
    r.s:SetTextColor(0.7, 0.7, 0.7)
    r.head = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.head:SetPoint("LEFT", 6, 0)
    r.head:SetPoint("RIGHT", -8, 0); r.head:SetJustifyH("LEFT")
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.05)
    -- 显示不全一律能悬停看全文（用户硬规定）；配方行先出游戏自己的物品 / 法术说明
    r:SetScript("OnEnter", function(self)
        local link = rawget(self, "link")
        if not rawget(self, "tip") and not link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local shown = false
        if link then
            if link.item and link.item > 0 and GameTooltip.SetItemByID then
                shown = pcall(GameTooltip.SetItemByID, GameTooltip, link.item)
            elseif link.spell and GameTooltip.SetSpellByID then
                shown = pcall(GameTooltip.SetSpellByID, GameTooltip, link.spell)
            end
        end
        for i, ln in ipairs(self.tip or {}) do
            if i == 1 and not shown then GameTooltip:AddLine(ln, 1, 0.82, 0, true) else GameTooltip:AddLine(ln, 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- 配方库：点一下 = 出处打地图标记 + 聊天框列全部出处（10-20 GI-22）
    r:SetScript("OnClick", function(self)
        local link = rawget(self, "link")
        if link and link.recipe and ns.ProfPinRecipeSource then ns.ProfPinRecipeSource(link.recipe) end
    end)
    page.rows[i] = r
    return r
end

-- 时刻表那条轴（第一次用时才建）
local function getBar(r)
    local have = rawget(r, "bar")
    if have then return have end
    local b = CreateFrame("Frame", nil, r)
    b:SetPoint("TOPLEFT", 34, -24); b:SetPoint("RIGHT", -12, 0); b:SetHeight(8)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(1, 1, 1, 0.10)
    b.fill = b:CreateTexture(nil, "ARTWORK"); b.fill:SetPoint("TOPLEFT"); b.fill:SetPoint("BOTTOMLEFT"); b.fill:SetColorTexture(0.2, 0.8, 0.4, 0.55)
    b.ticks = {}
    r.bar = b
    return b
end

local function getTick(bar, i)
    local t = bar.ticks[i]
    if t then return t end
    t = CreateFrame("Button", nil, bar)
    t:SetSize(9, 16)
    t.tx = t:CreateTexture(nil, "OVERLAY"); t.tx:SetPoint("CENTER"); t.tx:SetSize(4, 14)
    t:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        for j, ln in ipairs(self.lines or {}) do
            if j == 1 then GameTooltip:AddLine(ln, 1, 0.82, 0, true) else GameTooltip:AddLine(ln, 1, 1, 1, true) end
        end
        GameTooltip:AddLine(ns.L("点一下：在升级规划里看这一级", "Click: open the leveling plan at this level"), 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    t:SetScript("OnClick", function(self) if ns.PlanShowLevel then ns.PlanShowLevel(self.lv) end end)
    bar.ticks[i] = t
    return t
end

-- 写行的小工具：head 标题行 / item 普通行 / timeRow 带轴的行
local y, n
local function reset(r, h)
    r.tip, r.link = nil, nil
    local bar = rawget(r, "bar")
    if bar then bar:Hide() end
    r.s:ClearAllPoints(); r.s:SetPoint("TOPLEFT", 34, -20); r.s:SetPoint("RIGHT", -8, 0)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, y); r:SetPoint("RIGHT", page.child, "RIGHT", 0, 0); r:SetHeight(h); r:Show()
end
local function head(text)
    n = n + 1
    local r = getRow(n)
    reset(r, 22)
    r.ic:Hide(); r.t:SetText(""); r.s:SetText(""); r.bg:Hide()
    r.head:SetText("|cffffd100" .. text .. "|r")
    y = y - 24
end
local function item(icon, title, sub, tip, link)
    n = n + 1
    local r = getRow(n)
    reset(r, ROW_H)
    r.head:SetText(""); r.bg:Show()
    if icon then r.ic:SetTexture(icon); r.ic:Show() else r.ic:Hide() end
    r.t:SetText(title or ""); r.s:SetText(sub or "")
    r.tip = tip or { title or "", sub or "" }
    r.link = link
    y = y - ROW_H - 2
    return r
end

local PICON = { alchemy = "trade_alchemy", blacksmithing = "trade_blacksmithing", enchanting = "trade_engraving",
    engineering = "trade_engineering", leatherworking = "inv_misc_armorkit_17", tailoring = "trade_tailoring",
    herbalism = "spell_nature_naturetouchgrow", mining = "trade_mining", skinning = "inv_misc_pelt_wolf_01",
    cooking = "inv_misc_food_15", firstaid = "spell_holy_sealofsacrifice", fishing = "trade_fishing" }
local function icon(key) return "Interface\\Icons\\" .. (PICON[key] or "inv_misc_questionmark") end

local function myClass()
    local _, c = UnitClass and UnitClass("player")
    return c
end
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS_ZH = { WARRIOR = "战士", PALADIN = "圣骑士", HUNTER = "猎人", ROGUE = "潜行者", PRIEST = "牧师", SHAMAN = "萨满祭司",
    MAGE = "法师", WARLOCK = "术士", DRUID = "德鲁伊" }
local function className(c)
    local loc = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c]
    return loc or ns.L(CLASS_ZH[c] or c, c:sub(1, 1) .. c:sub(2):lower())
end

-- ---------- 选专业（升级最快） ----------
local function campLine(key)
    local c = P().Camp(key)[1]
    if not c then return "" end
    -- 游戏里的说明带数值（2% / 8% / 56 点）优先；没有（帐篷）再用我们的一句话
    return ns.L(c.zh, c.en) .. "：" .. ns.EnSafe((c.tx and c.tx ~= "") and c.tx or c.fn)
end

local function renderPick()
    local skills = P().Skills()
    local cls = myClass()
    local note = P().PICK_NOTE[cls or ""]
    head(ns.L("升级最快的专业", "Fastest-leveling professions") .. (cls and ("  |cffc8c8c8" .. className(cls) .. "|r") or ""))
    item(icon("leatherworking"), "|cff33ff99" .. ns.L("主专业：剥皮 + 制皮", "Primary: Skinning + Leatherworking") .. "|r",
        note and ns.L(note[1], note[2]) or ns.L("两个都先冲到 20：营地第一档设施就是练级最值的两件", "Get both to 20 first: their first camp objects help leveling most"),
        { ns.L("剥皮 + 制皮", "Skinning + Leatherworking"), ns.L("两个都先冲到 20：营地第一档设施就是练级最值的两件", "Get both to 20 first: their first camp objects are the best for leveling"),
          note and ns.L(note[1], note[2]) or nil })
    item(icon("leatherworking"), ns.L("制皮 20 · ", "Leatherworking 20 - ") .. campLine("leatherworking"), ns.L("每小时一次的休息经验，不占团队增益位", "Rested XP once an hour; takes no buff slot"))
    item(icon("skinning"), ns.L("剥皮 20 · ", "Skinning 20 - ") .. campLine("skinning"), ns.L("全队就座的人都吃", "Everyone seated gets it"))
    head(ns.L("副专业：三个都学（不占主专业栏位）", "Secondary: learn all three (no profession slot)"))
    item(icon("cooking"), ns.L("烹饪：自制食物击杀经验 +", "Cooking: crafted food gives +") .. (D().xpPct or 5) .. ns.L("%", "% kill XP"),
        ns.L("吃饱 15 分钟；营火也是摆营地设施的前提", "Well Fed for 15 min; the campfire is what every camp object needs"))
    item(icon("fishing"), ns.L("钓鱼到 20 · ", "Fishing to 20 - ") .. campLine("fishing"), ns.L("20 点就能学，门槛最低的一件营地设施", "Only 20 skill: the cheapest camp object"))
    item(icon("firstaid"), ns.L("急救 · ", "First Aid - ") .. campLine("firstaid"), ns.L("绷带回血，少坐下吃喝", "Bandages mean less time sitting to eat"))
    -- 你现在
    head(ns.L("你现在", "You now"))
    local have = {}
    for _, key in ipairs(P().ORDER) do
        if skills[key] then have[#have + 1] = P().Name(key) .. " " .. skills[key].r end
    end
    local planned = P().Planned()
    item(nil, #have > 0 and table.concat(have, ns.L("、", ", ")) or ns.L("还没学专业", "No professions yet"),
        planned and (ns.L("已按这套规划：", "Planned: ") .. (function()
            local t = {}
            for _, k in ipairs(planned) do t[#t + 1] = P().Name(k) end
            return table.concat(t, ns.L("、", ", "))
        end)()) or ns.L("点上面「按这套规划」，升级规划会在路过的城里提醒你去学", "Press 'Plan these' above; the leveling plan will remind you where to learn them"),
        { ns.L("你现在", "You now"), ns.L("已经学了别的也没关系：规划照样按你学的专业出", "Already learned others? The plan follows whatever you have"),
          ns.L("主专业只能学两个：两个都满了，选的主专业不会再加进规划", "Only two primary professions: if both slots are used, planned primaries are skipped") })
    head(ns.L("各职业一览", "All classes"))
    for _, c in ipairs(CLASSES) do
        local nt = P().PICK_NOTE[c]
        item(nil, (c == cls and "|cff33ff99" or "") .. className(c) .. (c == cls and "|r" or "") .. ns.L("：剥皮 + 制皮", ": Skinning + Leatherworking"),
            nt and ns.L(nt[1], nt[2]) or "")
    end
end

-- ---------- 我的时刻表 ----------
local KCOL = { train = { 0.4, 0.8, 1 }, gate = { 1, 0.82, 0 }, done = { 0.2, 0.9, 0.4 }, far = { 1, 0.4, 0.3 } }
local function timeRow(key, s, nodes, cur)
    n = n + 1
    local r = getRow(n)
    reset(r, TIME_H)
    r.head:SetText(""); r.bg:Show()
    r.ic:SetTexture(icon(key)); r.ic:Show()
    local cap = s.plan and ns.L("选了还没学", "planned, not learned") or (s.r .. "/" .. (s.m or "?"))
    r.t:SetText(P().Name(key) .. "  |cffffd100" .. cap .. "|r")
    local bar = getBar(r)
    bar:Show()
    local w = (page.child:GetWidth() or 600) - 46
    local function xOf(lv) return math.max(0, math.min(1, ((lv or 1) - 1) / 59)) * w end
    bar.fill:SetWidth(math.max(1, xOf(cur)))
    for _, t in ipairs(bar.ticks) do t:Hide() end
    local upcoming = {}
    for i, nd in ipairs(nodes) do
        local t = getTick(bar, i)
        local col = nd.done and KCOL.done or nd.far and KCOL.far or KCOL[nd.kind] or KCOL.gate
        t.tx:SetColorTexture(col[1], col[2], col[3], 1)
        t:ClearAllPoints(); t:SetPoint("CENTER", bar, "LEFT", xOf(nd.lv), 0)
        t.lv = nd.lv
        t.lines = { P().Name(key), nd.text }
        t:Show()
        if not nd.done and #upcoming < 2 then upcoming[#upcoming + 1] = nd.text end
    end
    r.s:ClearAllPoints(); r.s:SetPoint("TOPLEFT", 34, -38); r.s:SetPoint("RIGHT", -8, 0)
    r.s:SetText(#upcoming > 0 and (ns.L("接下来：", "Next: ") .. table.concat(upcoming, ns.L("；", "; "))) or ns.L("路线上没有要办的了", "Nothing left on the route"))
    local tip = { P().Name(key) .. "  " .. cap }
    for _, nd in ipairs(nodes) do tip[#tip + 1] = (nd.done and "|cff33ff99" or "") .. nd.text .. (nd.done and "|r" or "") end
    local camp = P().Camp(key)
    for _, c in ipairs(camp) do
        tip[#tip + 1] = "|cffc8c8c8" .. ns.L("营地 ", "Camp ") .. c.sk .. ns.L(" 点：", ": ") .. ns.L(c.zh, c.en) .. "|r"
    end
    r.tip = tip
    y = y - TIME_H - 2
end

local function renderTime()
    local skills = P().Skills()
    local plan = P().PlanSkills(skills)
    local cur = UnitLevel and UnitLevel("player") or 1
    local fac = UnitFactionGroup and UnitFactionGroup("player")
    local race = ns.RouteRace and ns.RouteRace()
    head(ns.L("我的时刻表（1-60 级；蓝 = 训练，黄 = 离开前采集门槛，绿 = 已达成）", "My timeline (1-60; blue = training, yellow = gather target, green = done)"))
    local any = false
    for _, key in ipairs(P().ORDER) do
        local s = plan[key]
        if s then
            any = true
            timeRow(key, s, P().Timeline(key, s, fac, race, cur), cur)
        end
    end
    if not any then
        item(nil, ns.L("还没有专业", "No professions yet"),
            ns.L("去「选专业」选一套，或者学了以后打开一次专业窗口", "Pick a set in 'Choose', or open your profession window once after learning"))
    end
    item(nil, "|cff888888" .. ns.L("节点按升级路线和训练师位置排（经典基线）；点节点跳到升级规划那一级", "Nodes follow your leveling route and trainer locations (Classic baseline); click one to jump to that level") .. "|r", "")
end

-- ---------- 冲级路线 ----------
-- 10-16 用户截图「选中的状态不明显，优化」：选中的保持可点，加金色粗边框 + 金色底光 + 白字
local SEL = setmetatable({}, { __mode = "k" })
local function markSel(b, on)
    local box = SEL[b]
    if not box then
        box = {}
        SEL[b] = box
        local glowTex = b:CreateTexture(nil, "OVERLAY")
        glowTex:SetPoint("TOPLEFT", 3, -3); glowTex:SetPoint("BOTTOMRIGHT", -3, 3)
        glowTex:SetColorTexture(1, 0.82, 0, 0.28); glowTex:SetBlendMode("ADD")
        box[1] = glowTex
        for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
            { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
            local t = b:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(1, 0.85, 0.1, 1)
            t:SetPoint(side[1]); t:SetPoint(side[2])
            if side[3] then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
            box[#box + 1] = t
        end
    end
    b:SetEnabled(true)
    for _, t in ipairs(box) do t:SetShown(on) end
    if b.SetNormalFontObject then b:SetNormalFontObject(on and "GameFontHighlight" or "GameFontNormal") end
end

local ROUTE_KEYS = { "firstaid", "cooking", "alchemy", "blacksmithing", "enchanting", "engineering", "leatherworking", "tailoring" }
-- 11-09 GI-204「比如剥皮，多少技能点可以剥什么地方的皮」：冲级路线第二排放三个采集专业，点了出「技能多少去哪张图」总表
local GATHER_KEYS = { "skinning", "herbalism", "mining" }
local IS_GATHER = { skinning = true, herbalism = true, mining = true }
-- 11-12 专业助手（ProfAssist.lua，HOLD 时不在包里）：在的话第二排多一个钓鱼，冲级路线子页改叫「专业助手」
if ns.ProfAssist then GATHER_KEYS[#GATHER_KEYS + 1] = "fishing"; IS_GATHER.fishing = true end
local function pickRouteKey(skills)
    if routeKey then return end
    for _, k in ipairs(ROUTE_KEYS) do if skills[k] and P().CRAFT[k] then routeKey = k break end end
    routeKey = routeKey or "firstaid"
end

-- 地图名：猎宠数据里有中英文名；没有的几张补上；再没有就问客户端
local ZONE_EXTRA = { [1449] = { "安戈洛环形山", "Un'Goro Crater" }, [1450] = { "月光林地", "Moonglade" }, [1459] = { "奥特兰克山谷", "Alterac Valley" } }
local function zoneName(m)
    local t = (ns.PetTameData and ns.PetTameData.zones and ns.PetTameData.zones[m]) or ZONE_EXTRA[m]
    if t and t[1] then return ns.L(t[1], t[2] or t[1]) end
    if C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, m)
        if ok and type(info) == "table" and info.name then return info.name end
    end
    return tostring(m)
end
ns._ProfZoneName = zoneName   -- 测试用

local function renderGather(key, rank)
    local G = P().GatherColor
    local function col(need) local c = rank and G(need, rank); return c and P().HEX[c] or "ffffff" end
    local zones = D().zones or {}
    local ms = {}
    for m in pairs(zones) do ms[#ms + 1] = m end
    head(P().Name(key) .. ns.L("：技能多少去哪张图", ": where to go at each skill")
        .. (rank and ("   |cff33ff99" .. ns.L("你现在 ", "you: ") .. rank .. "|r") or ""))
    if key == "skinning" then
        item(icon("skinning"), ns.L("剥皮要求 = 野兽等级：10 级及以下 1 点；11-20 级 =（等级 - 10）× 10；20 级以上 = 等级 × 5",
            "Skill needed by beast level: up to 10 = 1; 11-20 = (level - 10) x 10; above 20 = level x 5"),
            ns.L("比要求高 100 点就不再涨点（变灰）。颜色按你现在的技能：红 = 剥不了，橙 / 黄 / 绿 = 会涨，灰 = 不涨",
                "No more skill-ups 100 points above. Colors use your skill: red = can't, orange/yellow/green = skill-ups, grey = none"))
        local list = {}
        for _, m in ipairs(ms) do if zones[m].sk then list[#list + 1] = m end end
        table.sort(list, function(a, b)
            local x, z = zones[a].sk, zones[b].sk
            if x[3] ~= z[3] then return x[3] < z[3] end
            if x[4] ~= z[4] then return x[4] < z[4] end
            return a < b
        end)
        for _, m in ipairs(list) do
            local sk = zones[m].sk
            local need = sk[3] == sk[4] and tostring(sk[3]) or (sk[3] .. "-" .. sk[4])
            item(nil, "|cff" .. col(sk[3]) .. need .. "|r  " .. zoneName(m),
                string.format(ns.L("%d-%d 级野兽 · 技能 %d 起能剥这里的全部 · 练到 %d 不再涨", "Lv %d-%d beasts - all skinnable from %d - grey at %d"),
                    sk[1], sk[2], sk[4], sk[4] + 100))
        end
        return
    end
    -- 草药 / 矿：按种类列，每种写要求 + 最多的几张图
    local field = key == "herbalism" and "h" or "o"
    local by, order = {}, {}
    for _, m in ipairs(ms) do
        for _, nd in ipairs(zones[m][field] or {}) do
            local nm = nd[4] or nd[1]
            local e = by[nm]
            if not e then e = { zh = nd[1], en = nd[4] or nd[1], need = nd[2], at = {} }; by[nm] = e; order[#order + 1] = e end
            e.at[#e.at + 1] = { m = m, n = nd[3] or 0 }
        end
    end
    table.sort(order, function(a, b) if a.need ~= b.need then return a.need < b.need end return a.en < b.en end)
    item(icon(key), ns.L("每种按要求从低到高；后面是这种点最多的地图（数据库刷新点数）", "Sorted by skill needed; zones with the most spawns follow"),
        ns.L("颜色按你现在的技能：红 = 采不了，橙 / 黄 / 绿 = 会涨，灰 = 不涨", "Colors use your skill: red = can't, orange/yellow/green = skill-ups, grey = none"))
    for _, e in ipairs(order) do
        table.sort(e.at, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.m < b.m end)
        local names = {}
        for i = 1, math.min(5, #e.at) do names[#names + 1] = zoneName(e.at[i].m) end
        item(nil, "|cff" .. col(e.need) .. e.need .. "|r  " .. ns.L(e.zh, e.en),
            table.concat(names, ns.L("、", ", ")) .. (#e.at > 5 and ns.L(" 等 ", " +") .. #e.at .. ns.L(" 张图", " zones") or ""))
    end
end

-- 专业助手用同一套行 / 标题（PageProfAssist.lua）
ns._ProfUI = { head = head, item = item, icon = icon, zoneName = zoneName, renderGather = renderGather,
    shortSource = function(r) return shortSource(r) end }

local function renderRoute()
    local skills = P().Skills()
    pickRouteKey(skills)
    -- 11-12 专业助手在包里就交给它画（分段 / 只列接下来的 / 合计材料 / 钓鱼 / 烹饪推荐）；不在就还是下面原来的路线
    if ns.ProfAssistRender and ns.ProfAssistRender(routeKey, skills) then return end
    if IS_GATHER[routeKey] then
        return renderGather(routeKey, skills[routeKey] and skills[routeKey].r)
    end
    local p = D().profs[routeKey]
    local rank = skills[routeKey] and skills[routeKey].r
    head(P().Name(routeKey) .. ns.L(" 1 至 300（最省材料）", " 1 to 300 (cheapest mats)")
        .. (rank and ("   |cff33ff99" .. ns.L("你现在 ", "you: ") .. rank .. "|r") or ""))
    for _, st in ipairs(p.route or {}) do
        if st.train then
            local t = p.tiers[st.train + 1]
            local via = t.via == "book" and (ns.L("买书：", "Book: ") .. (t.name or "")) or t.via == "quest" and (ns.L("任务：", "Quest: ") .. (t.name or ""))
                or ns.L("找训练师", "Trainer")
            item("Interface\\Icons\\INV_Misc_Book_11", "|cff66ccff" .. ns.L("学 ", "Train ") .. ns.L(t.zh, t.en) .. "|r"
                .. ns.L("  技能 ", "  skill ") .. (st.at or "?") .. (((st.lv or 0) > 0) and (ns.L("、角色 ", ", Lv ") .. st.lv .. ns.L(" 级", "")) or ""), via)
        else
            local here = rank and rank >= st.f and rank < st.t
            local col = rank and P().HEX[P().RecipeColor(st, rank)] or "ffffff"
            local mats = {}
            for _, mt in ipairs(st.m) do
                -- v2：背包里有多少（拿不到背包就只写需要）
                local have = P().BagCount and P().BagCount(mt[1])
                mats[#mats + 1] = P().ItemName(mt[1]) .. ((have and have > 0) and (" |cff33ff99" .. have .. "|r/" .. mt[2]) or ("×" .. mt[2]))
            end
            -- 10-20 GI-22：不是训练师教的配方，写上去哪儿弄（本阵营第一个出处的短句）
            local rr = ns.ProfRecipeBySpell and ns.ProfRecipeBySpell(st.sp)
            local srcTxt = ""
            if rr and rr[14] ~= 1 and (rr[16] or 0) > 0 then
                srcTxt = "  " .. shortSource(rr)
            elseif st.src == "vendor" then
                srcTxt = ns.L("（配方商人卖）", " (recipe from a vendor)")
            end
            local where = st.fo == 1 and ns.L("  要铁砧", "  needs anvil") or st.fo == 3 and ns.L("  要熔炉", "  needs forge") or ""
            local tip = { ns.L(st.zh, st.en), string.format(ns.L("黄 %d · 绿 %d · 灰 %d", "Yellow %d, green %d, grey %d"), st.y, st.g, st.gr),
                ns.L("材料：", "Mats: ") .. table.concat(mats, ns.L("、", ", ")),
                ns.L("次数是期望值；材料价值按商人价估算，不是拍卖行价格", "Counts are expected values; mat value uses vendor prices, not the auction house") }
            if rr and rr[14] ~= 1 then ns.ProfSourceTip(tip, rr) end
            item(nil, (here and "|cff33ff99> |r" or "") .. "|cffffd100" .. st.f .. "-" .. st.t .. "|r  |cff" .. col .. ns.L(st.zh, st.en) .. "|r ×" .. st.c .. "|cff888888" .. where .. "|r",
                (srcTxt ~= "" and (srcTxt:gsub("^%s+", "") .. "  ") or "") .. ns.L("材料：", "Mats: ") .. table.concat(mats, ns.L("、", ", ")),
                tip, { spell = st.sp, recipe = rr and rr[14] ~= 1 and rr or nil })
        end
    end
    if not p.route or #p.route == 0 then
        item(nil, ns.L("这个专业没有制作路线", "No crafting route"), ns.L("采集 / 钓鱼按地图练，看升级规划里的「顺路采集」", "Gather along your leveling route"))
    end
end

-- ---------- 配方库 ----------
local RANGES = ns.LateL({ { 0, 300, ns.L("全部", "All") }, { 1, 75, "1-75" }, { 76, 150, "76-150" }, { 151, 225, "151-225" }, { 226, 300, "226-300" } })   -- 11-09 GI-202：ns.LateL = 手动切语言后跟着换
-- 部位：InventoryType → 分组
local SLOTS = ns.LateL({
    { ns.L("全部部位", "All slots") },
    { ns.L("头", "Head"), { [1] = true } }, { ns.L("肩", "Shoulder"), { [3] = true } },
    { ns.L("胸", "Chest"), { [5] = true, [20] = true } }, { ns.L("手腕", "Wrist"), { [9] = true } },
    { ns.L("手", "Hands"), { [10] = true } }, { ns.L("腰", "Waist"), { [6] = true } },
    { ns.L("腿", "Legs"), { [7] = true } }, { ns.L("脚", "Feet"), { [8] = true } },
    { ns.L("背", "Back"), { [16] = true } },
    { ns.L("武器盾", "Weapons"), { [13] = true, [14] = true, [15] = true, [17] = true, [21] = true, [22] = true, [23] = true, [25] = true, [26] = true } },
    { ns.L("饰品戒指", "Trinket/ring"), { [2] = true, [11] = true, [12] = true } },
    { ns.L("背包", "Bags"), { [18] = true } },
    { ns.L("消耗品材料", "Non-gear"), { [0] = true } },
})
-- 能穿什么材质（5 锁 6 板 7 布 8 皮）；非护甲谁都能用
local ARMOR = { WARRIOR = { [5] = 1, [6] = 1, [7] = 1, [8] = 1 }, PALADIN = { [5] = 1, [6] = 1, [7] = 1, [8] = 1 },
    HUNTER = { [5] = 1, [7] = 1, [8] = 1 }, SHAMAN = { [5] = 1, [7] = 1, [8] = 1 }, ROGUE = { [7] = 1, [8] = 1 },
    DRUID = { [7] = 1, [8] = 1 }, MAGE = { [7] = 1 }, PRIEST = { [7] = 1 }, WARLOCK = { [7] = 1 } }
local ARM_NAME = { [5] = { "锁甲", "Mail" }, [6] = { "板甲", "Plate" }, [7] = { "布甲", "Cloth" }, [8] = { "皮甲", "Leather" } }
local QHEX = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }
local SRC_NAME = { [1] = { "训练师", "trainer" }, [2] = { "商人卖配方", "vendor" }, [3] = { "掉落配方", "drop" }, [4] = { "声望", "reputation" },
    [5] = { "任务奖励", "quest" }, [6] = { "商人青睐兑换", "Merchant's Favor" } }
local SRC_TAG = { [1] = "c8c8c8", [2] = "33ff99", [3] = "ff8040", [4] = "c080ff", [5] = "ffd100", [6] = "66ccff" }

-- 10-20 共建 GI-22「补全图纸出处（哪个商人出售）」：每条配方挂 r[16] 出处位 + r[17] 出处（ProfRecipes.src 池下标）
-- 筛选位：1 训练师 2 商人 4 掉落 8 声望 16 任务 32 商人青睐 64 箱子；-1 = 出处未记录
local SRC_FILTERS = ns.LateL({
    { ns.L("全部出处", "Any source"), 0 }, { ns.L("商人", "Vendor"), 2 }, { ns.L("商人青睐", "Favor"), 32 },
    { ns.L("掉落", "Drop"), 4 + 64 }, { ns.L("任务", "Quest"), 16 }, { ns.L("声望", "Reputation"), 8 },
    { ns.L("训练师", "Trainer"), 1 }, { ns.L("出处未记录", "Unknown"), -1 },
})
local function hasBit(m, b)   -- 不依赖 bit 库：b 可以是几个位的和
    m = m or 0
    local p = 1
    while p <= b do
        if b % (p * 2) >= p and m % (p * 2) >= p then return true end
        p = p * 2
    end
    return false
end
local function mySide()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return f == "Alliance" and "A" or f == "Horde" and "H" or nil
end
-- 一条配方的出处，本阵营 / 中立在前、对面阵营在后（other = true，显示成灰色）
function ns.ProfRecipeSources(r)
    local R = ns.ProfRecipes
    local out = {}
    if not R or not R.src or type(r[17]) ~= "table" then return out end
    local side = mySide()
    for pass = 1, 2 do
        for _, ix in ipairs(r[17]) do
            local e = R.src[ix]
            local other = e and side and (e[8] == "A" or e[8] == "H") and e[8] ~= side or false
            if e and (pass == 1) ~= other then out[#out + 1] = { e = e, other = other } end
        end
    end
    return out
end
-- 法术 → 配方（冲级路线那一步要找它的出处）
local bySpell
function ns.ProfRecipeBySpell(spell)
    if not ns.ProfRecipes then return nil end
    if not bySpell then
        bySpell = {}
        for _, lst in pairs(ns.ProfRecipes.profs) do
            for _, r in ipairs(lst) do bySpell[r[1]] = r end
        end
    end
    return bySpell[spell]
end
-- 出处里第一个有坐标的（本阵营优先）→ 地图打标 + 聊天框给全部出处
function ns.ProfPinRecipeSource(r)
    local list = ns.ProfRecipeSources(r)
    local name = ns.L(r[2], r[3])
    ns.Print(ns.L("「", "") .. name .. ns.L("」出处：", " - where to get it:"))
    if #list == 0 then ns.Print(ns.L("  出处未记录", "  no source recorded")) return false end
    for _, s in ipairs(list) do ns.Print("  " .. (s.other and "|cff808080" or "") .. ns.EnSafe(ns.L(s.e[1], s.e[2])) .. (s.other and "|r" or "")) end
    for _, s in ipairs(list) do
        local e = s.e
        if not s.other and (e[5] or 0) > 0 and (e[6] or 0) > 0 then
            local ok = ns.ShowOnMap(e[5], { { e[6], e[7] } }, name)
            ns.Print(string.format("/way #%d %.1f %.1f %s", e[5], e[6], e[7], name))
            return ok
        end
    end
    return false
end
-- 配方行副标题用的短出处（本阵营第一条；只有训练师就写训练师）
-- 鼠标提示里的「出处」段：全部出处（对方阵营灰色）+ 能打标时提示点一下
function ns.ProfSourceTip(tip, r)
    local list, pin = ns.ProfRecipeSources(r), false
    tip[#tip + 1] = "|cffffd100" .. ns.L("出处", "Where to get it") .. "|r"
    if #list == 0 then
        tip[#tip + 1] = "|cff808080" .. ns.L("出处未记录：foreverchanges 和经典数据库都没有这张图纸的来源", "No source recorded yet") .. "|r"
    end
    for _, s in ipairs(list) do
        tip[#tip + 1] = (s.other and "|cff808080" or "") .. ns.EnSafe(ns.L(s.e[1], s.e[2])) .. (s.other and (ns.L("（对方阵营）", " (other faction)") .. "|r") or "")
        if not s.other and (s.e[5] or 0) > 0 then pin = true end
    end
    -- 游戏内自己见过的（ProfSeen.lua：开商人窗口 / 拾取时记下）
    if ns.ProfSeenFor then
        for _, v in ipairs(ns.ProfSeenFor(r)) do tip[#tip + 1] = "|cff33ff99" .. ns.EnSafe(ns.ProfSeenLine(v)) .. "|r" end
    end
    if pin then tip[#tip + 1] = "|cff999999" .. ns.L("点一下：在地图上标出最近的出处，聊天框列出全部", "Click: pin the source on the map and list all in chat") .. "|r" end
    return tip
end
shortSource = function(r)
    local list = ns.ProfRecipeSources(r)
    local s = list[1]
    if not s then
        local seen = ns.ProfSeenFor and ns.ProfSeenFor(r)[1]
        if seen then return "|cff33ff99" .. ns.EnSafe(ns.ProfSeenLine(seen)) .. "|r" end
        return "|cff808080" .. ns.L("出处未记录", "source unknown") .. "|r"
    end
    local more = #list > 1 and ns.L(" 等" .. #list .. "处", " +" .. (#list - 1)) or ""
    return "|cff" .. (SRC_TAG[r[14]] or "c8c8c8") .. ns.EnSafe(ns.L(s.e[3], s.e[4])) .. more .. "|r"
end

function ns.ProfRecipeFilter(key, f, cls)
    local R = ns.ProfRecipes
    if not R or not R.profs[key] then return {}, 0 end
    local rg = RANGES[(f.range or 0) + 1] or RANGES[1]
    local slot = SLOTS[f.slot or 1] or SLOTS[1]
    local allow = ARMOR[cls or ""]
    local q = (f.q or ""):lower()
    local out, total = {}, 0
    for _, r in ipairs(R.profs[key]) do
        local sk = r[4] or r[5]
        local ok = sk >= rg[1] and sk <= rg[2]
        if ok and slot[2] then ok = slot[2][r[9]] or false end
        if ok and f.new then ok = r[13] end
        if ok and f.mine and r[10] > 0 then ok = allow == nil or allow[r[10]] ~= nil end
        local sb = SRC_FILTERS[f.src or 1] and SRC_FILTERS[f.src or 1][2] or 0
        if ok and sb ~= 0 then
            if sb == -1 then ok = (r[16] or 0) == 0 else ok = hasBit(r[16], sb) end
        end
        if ok and q ~= "" then
            ok = (r[2]:lower():find(q, 1, true) or r[3]:lower():find(q, 1, true)) and true or false
            if not ok then
                for _, mt in ipairs(r[15]) do
                    local nm = R.items[mt[1]]
                    if nm and ((nm[1] or ""):lower():find(q, 1, true) or (nm[2] or ""):lower():find(q, 1, true)) then ok = true; break end
                end
            end
            -- 出处也能搜：商人名 / 地区名（「暴风城」「塔纳利斯」→ 在那儿能买 / 能打到的图纸）
            if not ok and R.src and type(r[17]) == "table" then
                for _, ix in ipairs(r[17]) do
                    local e = R.src[ix]
                    if e and ((e[1] or ""):lower():find(q, 1, true) or (e[2] or ""):lower():find(q, 1, true)) then ok = true; break end
                end
            end
        end
        if ok then
            total = total + 1
            if #out < MAX_RECIPES then out[#out + 1] = r end
        end
    end
    return out, total
end

local function matName(id)
    local nm = ns.ProfRecipes.items[id]
    return nm and ns.L(nm[1] ~= "" and nm[1] or nm[2], nm[2] ~= "" and nm[2] or nm[1]) or tostring(id)
end

local function renderRecipes()
    local skills = P().Skills()
    pickRouteKey(skills)
    if not ns.ProfRecipes then
        item(nil, ns.L("配方库数据没加载", "Recipe data not loaded"), "")
        return
    end
    local cls = myClass()
    local lv = UnitLevel and UnitLevel("player") or 1
    local rank = skills[routeKey] and skills[routeKey].r
    local list, total = ns.ProfRecipeFilter(routeKey, flt, cls)
    local all = #(ns.ProfRecipes.profs[routeKey] or {})
    local nNew = 0
    for _, r in ipairs(ns.ProfRecipes.profs[routeKey] or {}) do if r[13] then nNew = nNew + 1 end end
    head(string.format(ns.L("%s：%d 个配方，其中《无限》新增 %d 个 · 符合筛选 %d 个", "%s: %d recipes, %d new in Forever - %d match"),
        P().Name(routeKey), all, nNew, total))
    for _, r in ipairs(list) do
        local name = ns.L(r[2], r[3])
        local col = QHEX[r[12]] or "ffffff"
        local tags = {}
        if r[13] then tags[#tags + 1] = "|cff66ccff" .. ns.L("新增", "New") .. "|r" end
        if r[11] > 0 then tags[#tags + 1] = "|cffffd100" .. ns.L("套装", "Set") .. "|r" end
        if r[10] > 0 then
            local an = ARM_NAME[r[10]]
            local wear = not ARMOR[cls or ""] or ARMOR[cls][r[10]]
            tags[#tags + 1] = (wear and "|cffc8c8c8" or "|cff808080") .. ns.L(an[1], an[2]) .. (wear and "" or ns.L("·穿不了", " (can't wear)")) .. "|r"
        end
        local learn = r[4] and string.format(ns.L("学 %d", "learn %d"), r[4]) or ns.L("学习技能未知", "learn ?")
        local here = rank and (rank >= r[6] and "808080" or rank >= r[5] and "ffff00" or rank >= (r[4] or r[5]) and "ff8040" or "c8c8c8") or "c8c8c8"
        local mats = {}
        for _, mt in ipairs(r[15]) do mats[#mats + 1] = matName(mt[1]) .. "×" .. mt[2] end
        local use = r[8] > 0 and ((r[8] <= lv and "|cff33ff99" or "|cffc8c8c8") .. string.format(ns.L("使用 %d 级", "use Lv %d"), r[8]) .. "|r") or ""
        local src = SRC_NAME[r[14]]
        if src and r[14] ~= 1 then tags[#tags + 1] = "|cff" .. (SRC_TAG[r[14]] or "c8c8c8") .. ns.L(src[1], src[2]) .. "|r" end
        local title = "|cff" .. here .. "[" .. learn .. "]|r |cff" .. col .. name .. "|r  " .. table.concat(tags, " ")
        local matTxt = ns.L("材料：", "Mats: ") .. table.concat(mats, ns.L("、", ", "))
        local colors = string.format(ns.L("黄 %d · 灰 %d", "yellow %d, grey %d"), r[5], r[6]) .. (use ~= "" and ("  " .. use) or "")
        -- 10-20 GI-22：副标题先写出处（玩家最想知道去哪儿弄图纸），材料放后面，全文在鼠标提示里
        local sub = shortSource(r) .. "  " .. matTxt
        local tip = { name, learn .. (src and ("（" .. ns.L(src[1], src[2]) .. "）") or ""), colors, matTxt,
            r[13] and ns.L("《无限》新增：经典旧世没有这个配方", "New in Forever: not in Classic") or nil }
        ns.ProfSourceTip(tip, r)
        -- 11-10 GI-218：每种材料写一句从哪来（ReagentSrc.lua，HOLD 期间没有就跳过）
        if ns.ReagentSrcTip and ns.ReagentSrcTip.Enabled() then
            local head
            for _, mt in ipairs(r[15]) do
                local s = ns.ReagentSrcTip.Short(mt[1])
                if s then
                    if not head then tip[#tip + 1] = ns.L("材料从哪来（经典旧世参考）：", "Where to get mats (Classic reference):"); head = true end
                    tip[#tip + 1] = "  " .. matName(mt[1]) .. ns.L("：", ": ") .. s
                end
            end
        end
        local ic
        if r[7] > 0 and C_Item and C_Item.GetItemIconByID then
            local ok, v = pcall(C_Item.GetItemIconByID, r[7])
            if ok then ic = v end
        end
        item(ic or icon(routeKey), title, sub, tip, { item = r[7], spell = r[1], recipe = r })
    end
    if total > #list then
        item(nil, string.format(ns.L("还有 %d 个没列出来：用上面的技能段 / 部位 / 搜索缩小范围", "%d more: narrow down with the filters above"), total - #list), "")
    end
    if total == 0 then item(nil, ns.L("没有符合的配方", "No matching recipes"), ns.L("换个筛选或搜索词", "Try other filters")) end
end

-- ---------- 营地与传承 ----------
local function renderCamp()
    local skills = P().Skills()
    local C = D().camp
    head(ns.L("营火（烹饪）", "Campfires (Cooking)"))
    for _, f in ipairs(C.fires or {}) do
        -- 10-16 实测：基础营火学初级烹饪就会，要带「燧石和火绒」+ 普通木柴；中级 / 高级营火的要求还没实测
        local need = f.tool and (ns.L("要带 ", "needs ") .. ns.L(f.tool, f.toolEn) .. (f.mat and (ns.L(" + ", " + ") .. ns.L(f.mat, f.matEn)) or "")) or ""
        -- 10-22 GI-14：中级 / 高级营火 学会 95 / 205、放下要 140 / 220（客户端 70532 物品技能要求），两个都写
        local skTx = f.use and string.format(ns.L("  烹饪 %d 学 · %d 放", "  Cooking %d learn · %d place"), f.sk, f.use) or (ns.L("  烹饪 ", "  Cooking ") .. f.sk)
        local tip = { ns.L(f.zh, f.en), string.format(ns.L("可摆 %d 件设施", "Holds %d objects"), f.cap) .. (need ~= "" and ("；" .. need) or "") }
        if f.use then tip[#tip + 1] = string.format(ns.L("烹饪 %d 点能学会，%d 点才能放下", "Learnable at Cooking %d, placeable at %d"), f.sk, f.use) end
        tip[#tip + 1] = f.ok and ns.L("已在游戏里核对过", "Verified in game") or ns.L("数值来自客户端数据，还没在游戏里核对", "From client data, not yet checked in game")
        item(icon("cooking"), ns.L(f.zh, f.en) .. skTx,
            string.format(ns.L("可摆 %d 件设施", "holds %d objects"), f.cap) .. (need ~= "" and ("　" .. need) or ""), tip)
    end
    head(ns.L("各专业的营地设施（20 / 140 / 300）", "Camp objects by profession"))
    for _, key in ipairs(P().ORDER) do
        local tiers = P().Camp(key)
        if #tiers > 0 then
            local parts = {}
            local s = skills[key]
            for _, c in ipairs(tiers) do
                parts[#parts + 1] = ((s and s.r >= c.sk) and "|cff33ff99" or "|cffc8c8c8") .. ns.L(c.zh, c.en) .. "(" .. c.sk .. ")|r"
            end
            local tip = { P().Name(key) }
            for _, c in ipairs(tiers) do tip[#tip + 1] = ns.L(c.zh, c.en) .. " " .. c.sk .. ": " .. ns.EnSafe(c.tx) end
            item(icon(key), P().Name(key) .. (s and ("  |cff888888" .. s.r .. "|r") or ""), table.concat(parts, "  "), tip)
        end
    end
    head(ns.L("营地升级图纸（Beta 实测掉落）", "Camp blueprints (seen in Beta)"))
    for _, bp in ipairs(D().blueprints or {}) do
        local key = P().BlueprintProf(bp)
        local mine = key and skills[key]
        item("Interface\\Icons\\INV_Scroll_03", (mine and "|cff33ff99" or "") .. ns.L(bp.zh or bp.en, bp.en) .. (mine and "|r" or ""),
            (bp.dun or "") .. " · " .. (bp.boss or "") .. (key and (ns.L("  （", "  (") .. P().Name(key) .. ns.L("）", ")")) or ""))
    end
    -- 传承
    head(ns.L("传承 · 制造专业里程碑：每档账号首次 1 点", "Legacy - crafting milestones: 1 point each, once per account"))
    local got, how = 0, "ach"
    for _, key in ipairs(P().ORDER) do
        if P().CRAFT[key] then
            local parts = {}
            for _, at in ipairs({ 150, 225, 300 }) do
                local ok, h = P().LegacyClaimed(key, at)
                if h == "guess" then how = "guess" end
                if ok then got = got + 1 end
                parts[#parts + 1] = (ok and "|cff33ff99" or "|cff808080") .. at .. (ok and ns.L(" 已领", " done") or ns.L(" 未领", " open")) .. "|r"
            end
            local s = skills[key]
            item(icon(key), P().Name(key) .. (s and ("  |cffffd100" .. s.r .. "|r") or ""), table.concat(parts, "   "))
        end
    end
    item(nil, string.format(ns.L("已领 %d / 18", "%d of 18 claimed"), got),
        how == "guess" and ns.L("查不到成就时按本账号装了插件的角色技能推算", "Estimated from characters with this addon when achievements are unavailable")
        or ns.L("按成就完成状态", "From achievement status"))
    head(ns.L("传承 · 专业树（括号里是满级效果）", "Legacy - Professions tree (max rank shown)"))
    for _, pk in ipairs(D().legacy or {}) do
        item("Interface\\Icons\\INV_Misc_Book_09", ns.L(pk.zh, pk.en) .. "  |cff888888" .. ns.L("共 ", "") .. (pk.max or "?") .. ns.L(" 级", " ranks") .. "|r",
            ns.EnSafe(ns.L(pk.d or "", pk.dEn or pk.d or "")))
    end
end

-- ---------- 页面 ----------
local TOP = { pick = -98, time = -74, route = -124, recipes = -124, camp = -74 }   -- 11-09 GI-204 冲级路线多一排采集按钮
local function refresh()
    if not page or not D() then return end
    -- ⛔ P().Skills() 返回两个值，直接塞进 next() 会把第二个当成 key 报错（10-18 整页空白、按钮全叠在一起）
    if not tab then
        local sk = P().Skills()
        tab = next(P().PlanSkills(sk)) and "time" or "pick"
    end
    for k, b in pairs(page.tabBtns) do markSel(b, k == tab) end
    page.pickBtn:SetShown(tab == "pick"); page.unpickBtn:SetShown(tab == "pick" and P().Planned() ~= nil)
    local rk = tab == "route" or tab == "recipes"
    if rk then pickRouteKey(P().Skills()) end
    for k, b in pairs(page.routeBtns) do b:SetShown(rk and not (IS_GATHER[k] and tab ~= "route")); markSel(b, k == routeKey) end
    if tab == "recipes" and IS_GATHER[routeKey] then routeKey = nil; pickRouteKey(P().Skills()); for k, b in pairs(page.routeBtns) do markSel(b, k == routeKey) end end
    for i, b in ipairs(page.rangeBtns) do b:SetShown(tab == "recipes"); markSel(b, i - 1 == flt.range) end
    page.slotBtn:SetShown(tab == "recipes"); page.slotBtn:SetText(SLOTS[flt.slot][1])
    page.newBtn:SetShown(tab == "recipes"); markSel(page.newBtn, flt.new)
    page.mineBtn:SetShown(tab == "recipes"); markSel(page.mineBtn, flt.mine)
    page.srcBtn:SetShown(tab == "recipes"); page.srcBtn:SetText(SRC_FILTERS[flt.src or 1][1]); markSel(page.srcBtn, (flt.src or 1) ~= 1)
    page.search:SetShown(tab == "recipes")
    if ns.ProfAssistRefresh then ns.ProfAssistRefresh(page, tab) end
    local top = TOP[tab] or -98
    -- 11-12 GI-238「滚动到下面 每隔一秒就会自动重置回到顶部」：Prof.lua 的 SKILL_LINES_CHANGED / TRADE_SKILL_LIST_UPDATE
    --   一来就整页重画，以前每次都把滚动条拉回 0。现在只有换了子页 / 专业 / 筛选才回顶部，同一视图重画保住位置（夹在新内容高度内）
    local vk = table.concat({ tostring(tab), tostring(routeKey), tostring(flt.range), tostring(flt.slot), tostring(flt.new),
        tostring(flt.mine), tostring(flt.q or ""), tostring(flt.src or 1) }, "\1")
    local keep = 0
    if vk == page.viewKey and page.sf.GetVerticalScroll then keep = tonumber(page.sf:GetVerticalScroll()) or 0 end
    page.viewKey = vk
    local sfH = 474 + top - 12
    page.sf:ClearAllPoints()
    page.sf:SetPoint("TOPLEFT", 6, top)
    page.sf:SetSize(616, sfH)
    for _, r in ipairs(page.rows) do r:Hide() end
    y, n = -2, 0
    if tab == "pick" then renderPick() elseif tab == "time" then renderTime() elseif tab == "route" then renderRoute()
    elseif tab == "recipes" then renderRecipes() else renderCamp() end
    page.child:SetHeight(-y + 4)
    if page.sf.UpdateScrollChildRect then page.sf:UpdateScrollChildRect() end
    if page.sf.SetVerticalScroll then page.sf:SetVerticalScroll(math.max(0, math.min(keep, (-y + 4) - sfH))) end
end
ns.RefreshProfPage = refresh

local function build(p)
    page = p
    ns.ProfPage = p   -- 测试用
    p.rows = {}
    ns.PageHeader(p, ns.L("专业", "Professions"),
        ns.L("边练级边练专业：选专业、路线上的训练和采集门槛、配方库", "Level your professions while you level: picks, route timeline, recipes"))
    p.tabBtns = {}
    local x = 12
    for _, t in ipairs({ { "pick", ns.L("选专业", "Choose") }, { "time", ns.L("我的时刻表", "Timeline") }, { "route", ns.ProfAssist and ns.L("专业助手", "Assistant") or ns.L("冲级路线", "Route") },
        { "recipes", ns.L("配方库", "Recipes") }, { "camp", ns.L("营地与传承", "Camp & Legacy") } }) do
        local b = ns.Button(p, t[2], 112, 22, function() tab = t[1]; refresh() end)
        b:SetPoint("TOPLEFT", x, -42); x = x + 116
        p.tabBtns[t[1]] = b
    end
    -- 选专业：按这套规划 / 取消
    p.pickBtn = ns.Button(p, ns.L("按这套规划", "Plan these"), 120, 22, function()
        local list = {}
        for _, k in ipairs(P().PICK) do list[#list + 1] = k end
        P().SetPlanned(list); refresh()
    end)
    p.pickBtn:SetPoint("TOPLEFT", 12, -70)
    p.unpickBtn = ns.Button(p, ns.L("取消规划", "Clear plan"), 100, 22, function() P().SetPlanned(nil); refresh() end)
    p.unpickBtn:SetPoint("LEFT", p.pickBtn, "RIGHT", 6, 0)
    -- 冲级路线 / 配方库：专业
    p.routeBtns = {}
    x = 12
    for _, k in ipairs(ROUTE_KEYS) do
        local b = ns.Button(p, P().Name(k), 74, 20, function() routeKey = k; refresh() end)
        b:SetPoint("TOPLEFT", x, -70); x = x + 76
        p.routeBtns[k] = b
    end
    x = 12
    for _, k in ipairs(GATHER_KEYS) do
        local b = ns.Button(p, P().Name(k), 74, 20, function() routeKey = k; refresh() end)
        b:SetPoint("TOPLEFT", x, -96); x = x + 76
        p.routeBtns[k] = b
    end
    -- 配方库筛选：技能段 / 部位 / 只看新增 / 我能穿 / 搜索
    p.rangeBtns = {}
    x = 12
    for i, rg in ipairs(RANGES) do
        local b = ns.Button(p, rg[3], i == 1 and 40 or 54, 20, function() flt.range = i - 1; refresh() end)
        b:SetPoint("TOPLEFT", x, -96); x = x + (i == 1 and 42 or 56)
        p.rangeBtns[i] = b
    end
    p.slotBtn = ns.Button(p, SLOTS[1][1], 70, 20, function() flt.slot = flt.slot % #SLOTS + 1; refresh() end)
    p.slotBtn:SetPoint("TOPLEFT", x + 2, -96); x = x + 74
    p.slotBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(ns.L("部位：点一下换下一个", "Slot: click to cycle"), 1, 0.82, 0); GameTooltip:Show()
    end)
    p.slotBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.newBtn = ns.Button(p, ns.L("新增", "New"), 46, 20, function() flt.new = not flt.new; refresh() end)
    p.newBtn:SetPoint("TOPLEFT", x, -96); x = x + 48
    p.newBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(ns.L("只看《无限》新增的配方", "Only recipes new in Forever"), 1, 0.82, 0); GameTooltip:Show()
    end)
    p.newBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.mineBtn = ns.Button(p, ns.L("我能穿", "Wearable"), 56, 20, function() flt.mine = not flt.mine; refresh() end)
    p.mineBtn:SetPoint("TOPLEFT", x, -96); x = x + 58
    -- 10-20 GI-22：按出处筛（商人 / 商人青睐 / 掉落 / 任务 / 声望 / 训练师 / 未记录），点一下换下一个，右键回到全部
    p.srcBtn = ns.Button(p, SRC_FILTERS[1][1], 76, 20, function() flt.src = (flt.src or 1) % #SRC_FILTERS + 1; refresh() end)
    p.srcBtn:SetPoint("TOPLEFT", x, -96); x = x + 78
    if p.srcBtn.RegisterForClicks then p.srcBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    local leftClick = p.srcBtn:GetScript("OnClick")
    p.srcBtn:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then flt.src = 1; refresh() elseif leftClick then leftClick(self, btn) end
    end)
    p.srcBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.L("出处：点一下换下一个，右键回到全部", "Source: click to cycle, right-click to reset"), 1, 0.82, 0)
        GameTooltip:AddLine(ns.L("搜索框也能搜商人名 / 地区名", "The search box also matches vendor and zone names"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    p.srcBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.search = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    p.search:SetSize(612 - x, 20); p.search:SetPoint("TOPLEFT", x + 6, -96); p.search:SetAutoFocus(false)
    p.search:SetScript("OnTextChanged", function(self, user)
        if user == false then return end
        flt.q = self:GetText() or ""
        refresh()
    end)
    p.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    p.search:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(ns.L("搜配方名、材料名、商人名或地区", "Search recipe, material, vendor or zone"), 1, 0.82, 0); GameTooltip:Show()
    end)
    p.search:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if ns.ProfAssistBuild then ns.ProfAssistBuild(p, refresh) end
    local sf, c = ns.Scroll(p, 6, -98, 616, 474 - 98 - 12)
    p.sf, p.child = sf, c
end

-- 外面跳进来：/gi prof 选专业 等
function ns.ProfOpenTab(t)
    tab = t
    if page and page.IsVisible and page:IsVisible() then refresh(); return end
    if ns.ToggleMain then ns.ToggleMain("prof") end
    refresh()
end

ns.RegisterPage({ key = "prof", order = 1.85, title = ns.L("专业", "Professions"), tabTitle = ns.L("专业", "Profs"),
    icon = "Interface\\Icons\\Trade_BlackSmithing", hold = true, build = build, refresh = refresh })
