-- 专业助手的界面（11-12）：接管「专业」页的冲级路线子页（PageProf.lua 的 renderRoute 先问这里）。
--   行 / 标题 / 图标都用 PageProf 导出的那套（ns._ProfUI），不另起一套控件。
--   这个文件不在包里时（HOLD）PageProf 照旧画原来的冲级路线，所以这里不能被别处硬依赖。
local _, ns = ...; ns = _G.GearInsightForever or ns

local A = ns.ProfAssist
if not A then return end

local showAll = false       -- 「显示已练完的」
local function UI() return ns._ProfUI end
local function P() return ns.Prof end
local function AD() return ns.ProfAssistData end

local GREEN, RED, GREY, GOLD, BLUE = "|cff33ff99", "|cffff6060", "|cff888888", "|cffffd100", "|cff66ccff"
local SEP = function() return ns.L("、", ", ") end

local function matText(item, need, have)
    local s = A.ItemName(item)
    if have and have > 0 then
        s = s .. " " .. GREEN .. have .. "|r/" .. need
    else
        s = s .. "×" .. need
    end
    if have and have < need then s = s .. RED .. ns.L(" 缺", " need ") .. (need - have) .. "|r" end
    return s
end

local function matList(mats)
    local out = {}
    for _, mt in ipairs(mats) do
        local have = P().BagCount and P().BagCount(mt[1])
        out[#out + 1] = matText(mt[1], mt[2], have)
    end
    return out
end

-- 合计材料：一行放不下，每行 6 种（上 3 下 3），悬停看全部
local function totalRows(title, total, note)
    local ui = UI()
    if #total == 0 then return end
    local all, lack = {}, 0
    for _, e in ipairs(total) do
        all[#all + 1] = matText(e.item, e.need, e.have)
        if e.lack and e.lack > 0 then lack = lack + 1 end
    end
    local tip = { title }
    for _, s in ipairs(all) do tip[#tip + 1] = s end
    if note then tip[#tip + 1] = note end
    -- 11-15「点击就能买材料」：合计行也能点（开着商人买 / 开着拍卖行搜）
    local mlink = { mats = {} }
    for _, e in ipairs(total) do mlink.mats[#mlink.mats + 1] = { e.item, e.need } end
    local i, first = 1, true
    while i <= #all do
        local a, b = {}, {}
        for j = i, math.min(i + 2, #all) do a[#a + 1] = all[j] end
        for j = i + 3, math.min(i + 5, #all) do b[#b + 1] = all[j] end
        local t = table.concat(a, SEP())
        if first then
            t = GOLD .. title .. "|r" .. (lack > 0 and (RED .. string.format(ns.L("（%d 种不够）", " (%d short)"), lack) .. "|r")
                or (total[1].have and (GREEN .. ns.L("（背包里都够）", " (all in bags)") .. "|r") or "")) .. "  " .. t
        end
        ui.item(first and "Interface\\Icons\\INV_Misc_Bag_08" or nil, t, table.concat(b, SEP()), tip, mlink)
        i, first = i + 6, false
    end
end

-- 11-15 用户「烹饪还有急救各个学习的书的东西在哪里买也标记，能AH的标记，点击可以直接搜」：
--   教材物品 ID（经典 ID，《无限》客户端 ItemSparse 核过名字）；出处（商人 / 坐标）在 ns.ProfBooks（ProfBookData.lua，没有就只给按钮）
-- 教材在哪买（经典库 vmangos npc_vendor 口径；物品 ID / 名字 / 绑定对过《无限》客户端 ItemSparse 70938：三本都不绑定，客户端买价 1 金）
ns.ProfBooks = ns.ProfBooks or {
    ["中级烹饪教材"] = { item = 16072, vendors = { { n = "珊蒂瑞亚", ne = "Shandrina", z = "灰谷", ze = "Ashenvale", um = 1440, x = 49.5, y = 67.1, side = "A" }, { n = "乌兰", ne = "Wulan", z = "凄凉之地", ze = "Desolace", um = 1443, x = 26.2, y = 69.6, side = "H" } } },
    ["中级急救教材 - 绷带缚体"] = { item = 16084, vendors = { { n = "德尼布·沃克", ne = "Deneb Walker", z = "阿拉希高地", ze = "Arathi Highlands", um = 1417, x = 27.0, y = 58.8, side = "A" }, { n = "巴莱·洛克维", ne = "Balai Lok'Wein", z = "尘泥沼泽", ze = "Dustwallow Marsh", um = 1445, x = 36.5, y = 30.4, side = "H" } } },
    ["中级钓鱼教材 - 鲈鱼与你"] = { item = 16083, vendors = { { n = "老人海明威", ne = "Old Man Heming", z = "荆棘谷", ze = "Stranglethorn Vale", um = 1434, x = 27.4, y = 77.2, side = "N" } } },
}
A.BOOK_ITEM = A.BOOK_ITEM or { ["中级烹饪教材"] = 16072, ["中级急救教材 - 绷带缚体"] = 16084, ["中级钓鱼教材 - 鲈鱼与你"] = 16083 }
local function bookOf(t)
    if not (t and t.via == "book" and t.name) then return nil end
    local bd = ns.ProfBooks and ns.ProfBooks[t.name]
    local id = (bd and bd.item) or A.BOOK_ITEM[t.name]
    if not id then return nil end
    return { item = id, mats = { { id, 1 } }, book = t.name, vendors = bd and bd.vendors or nil }
end
A.BookOf = bookOf
local function bookTag(t)
    local b = bookOf(t)
    if not b then return "" end
    local S = ns.ProfShop
    local tag = S and S.AHTag and S.AHTag(b.item) or ""
    -- 本阵营的商人排前面（中立也算）
    local side = UnitFactionGroup and UnitFactionGroup("player")
    side = side == "Alliance" and "A" or side == "Horde" and "H" or nil
    local v
    for _, x in ipairs(b.vendors or {}) do if not side or x.side == side or x.side == "N" then v = x; break end end
    v = v or (b.vendors and b.vendors[1])
    local where = v and (GREY .. ns.L("  商人 ", "  vendor ") .. ns.L(v.n, v.ne or v.n) .. "·" .. ns.L(v.z or "", v.ze or v.z or "")
        .. ((#b.vendors > 1) and string.format(ns.L(" 等%d处", " +%d"), #b.vendors) or "") .. "|r") or ""
    return (tag ~= "" and ("  " .. tag) or "") .. where
end
-- 11-18 用户截图（烹饪「先学 大师级 · 任务：蚌肉大餐」）「这个在哪里学」：任务档只写了任务名，没说去哪接 →
--   按阵营补上接任务的 NPC 和位置。来源 = 烹饪攻略（GuideData，视频 + 经典数据一致；训练师位置《无限》实测 ≥8 台）
--   行只有一行高：行里写「去哪接」（short），完整流程放悬停提示（full）
local QUEST_WHERE = {
    ["蚌肉大餐"] = {
        Horde = { short = { "奥格瑞玛 扎姆沙 (57, 54) 接", "from Zamja, Orgrimmar (57, 54)" },
                  full = { "奥格瑞玛烹饪训练师 扎姆沙 (57, 54) 接「加基森之旅！」，再去塔纳利斯加基森交材料完成「蚌肉大餐」",
                           "Take To Gadgetzan You Go! from Zamja, Orgrimmar cooking trainer (57, 54), then turn in the materials at Gadgetzan, Tanaris for Clamlette Surprise" } },
        Alliance = { short = { "铁炉堡 达瑞尔·瑞克努索 (60, 36) 接", "from Daryl Riknussun, Ironforge (60, 36)" },
                     full = { "铁炉堡烹饪训练师 达瑞尔·瑞克努索 (60, 36) 接「我认识一个家伙…」，再去塔纳利斯加基森交材料完成「蚌肉大餐」",
                              "Take I Know A Guy... from Daryl Riknussun, Ironforge cooking trainer (60, 36), then turn in the materials at Gadgetzan, Tanaris for Clamlette Surprise" } },
    },
}
A.QUEST_WHERE = QUEST_WHERE
-- 返回本阵营那一份（读不到阵营 → nil，调用方两边都给）
local function questSide(t)
    local w = t and QUEST_WHERE[t.name or ""]
    if not w then return nil, nil end
    local side = UnitFactionGroup and UnitFactionGroup("player")
    if ns.Secret and ns.Secret(side) then side = nil end
    return w, w[side or ""]
end
function A.QuestWhereShort(t)
    local w, s = questSide(t)
    if not w then return "" end
    if s then return ns.L("（", " (") .. ns.L(s.short[1], s.short[2]) .. ns.L("）", ")") end
    return ns.L("（主城烹饪训练师接，悬停看详情）", " (from your capital's cooking trainer; hover for details)")
end
-- 悬停提示：nil = 用默认 { 标题, 副标题 }
function A.QuestWhereTip(t, title, sub)
    local w, s = questSide(t)
    if not w then return nil end
    local tip = { title or "", sub or "" }
    if s then tip[#tip + 1] = ns.L(s.full[1], s.full[2])
    else
        tip[#tip + 1] = ns.L("部落：", "Horde: ") .. ns.L(w.Horde.full[1], w.Horde.full[2])
        tip[#tip + 1] = ns.L("联盟：", "Alliance: ") .. ns.L(w.Alliance.full[1], w.Alliance.full[2])
    end
    tip[#tip + 1] = "|cffff8040" .. ns.L(string.format("任务要技能 %s%s 才会出现：不够时训练师头上没有感叹号，对话里也不给", tostring(t.sk or "?"), (t.lv or 0) > 0 and ("、角色 " .. t.lv .. " 级") or ""),
        string.format("The quest only appears at skill %s%s: below that the trainer shows no ! and offers nothing", tostring(t.sk or "?"), (t.lv or 0) > 0 and (" and level " .. t.lv) or "")) .. "|r"
    tip[#tip + 1] = "|cffaaaaaa" .. ns.L("主城这条只是引路任务，也可以直接去塔纳利斯加基森交「蚌肉大餐」（《无限》改没改待众包确认）",
        "The capital quest is only a breadcrumb; you can also go straight to Gadgetzan, Tanaris (unconfirmed on Forever)") .. "|r"
    tip[#tip + 1] = "|cff999999" .. ns.L("点一下：任务已接 = 追踪任务并打开任务地图；没接 = 地图上标出接任务的人并开始导航",
        "Click: quest in log = track it and open the quest map; otherwise pin the quest giver and navigate") .. "|r"
    return tip
end

-- 11-18 用户「点击打开任务追踪视图」「然后可以定位」：任务档那行点一下 →
--   任务日志里有这条链上的任务 → 加追踪 + 超级追踪 + 打开任务地图；还没接 → 本阵营接任务的人打地图标记（ns.ShowOnMap：游戏标记 + 超级追踪 + TomTom + 开地图）
--   坐标 / 地图 ID 同 GuideData 烹饪攻略（奥格瑞玛 1454 / 铁炉堡 1455）；任务 ID 同 ObsProf.QUESTS（6610 蚌肉大餐，6611 / 6612 两条前置）
local QUEST_PIN = {
    ["蚌肉大餐"] = { quests = { 6611, 6612, 6610 },
        Horde = { n = "扎姆沙", ne = "Zamja", um = 1454, x = 57.4, y = 54.0 },
        Alliance = { n = "达瑞尔·瑞克努索", ne = "Daryl Riknussun", um = 1455, x = 60.1, y = 36.4 } },
}
A.QUEST_PIN = QUEST_PIN
function A.QuestLink(t)
    if not (t and t.via == "quest" and QUEST_PIN[t.name or ""]) then return nil end
    return { quest = t.name }
end
local function inLog(qid)
    if not (C_QuestLog and C_QuestLog.GetLogIndexForQuestID) then return false end
    local ok, idx = pcall(C_QuestLog.GetLogIndexForQuestID, qid)
    return ok and type(idx) == "number" and idx > 0 and not (ns.Secret and ns.Secret(idx))
end
function ns.ProfPinQuest(link)
    local p = link and QUEST_PIN[link.quest or ""]
    if not p then return false end
    for _, qid in ipairs(p.quests) do
        if inLog(qid) then
            if C_QuestLog.AddQuestWatch then pcall(C_QuestLog.AddQuestWatch, qid) end
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then pcall(C_SuperTrack.SetSuperTrackedQuestID, qid) end
            local inCombat = InCombatLockdown and InCombatLockdown()
            if not inCombat then
                if QuestMapFrame_OpenToQuestDetails then pcall(QuestMapFrame_OpenToQuestDetails, qid)
                elseif OpenWorldMap then pcall(OpenWorldMap) end
            end
            ns.Print(ns.L("「", "") .. link.quest .. ns.L("」这条任务已在任务日志里：已追踪", " is in your quest log: now tracked"))
            return true, "track"
        end
    end
    local side = UnitFactionGroup and UnitFactionGroup("player")
    if ns.Secret and ns.Secret(side) then side = nil end
    local list = side and p[side] and { p[side] } or { p.Horde, p.Alliance }
    for _, v in ipairs(list) do
        ns.Print(ns.L("「", "") .. link.quest .. ns.L("」去这里接：", " - start here: ") .. ns.L(v.n, v.ne)
            .. string.format(" %.1f, %.1f", v.x, v.y))
    end
    local v = list[1]
    local pinned = ns.ShowOnMap and ns.ShowOnMap(v.um, { { v.x, v.y } }, ns.L(v.n, v.ne)) or false
    return pinned and true or false, "pin"
end

-- 11-18 用户「按照坐标过来，没任务啊」（技能还没到 225）→「这个提示加到插件里」：任务档技能 / 等级不够时行里直接写
function A.QuestGate(t, rank)
    if not (t and t.via == "quest") then return "" end
    local lv = UnitLevel and UnitLevel("player")
    if ns.Secret and ns.Secret(lv) then lv = nil end
    local need = {}
    if rank and t.sk and rank < t.sk then need[#need + 1] = string.format(ns.L("技能到 %d（现在 %d）", "skill %d (now %d)"), t.sk, rank) end
    if lv and (t.lv or 0) > 0 and lv < t.lv then need[#need + 1] = string.format(ns.L("角色 %d 级（现在 %d）", "level %d (now %d)"), t.lv, lv) end
    if #need == 0 then return "" end
    return RED .. ns.L("  · 要", "  - needs ") .. table.concat(need, ns.L("、", ", ")) .. ns.L("才有任务", " before the quest shows") .. "|r"
end

local function tierVia(t)
    if t.via == "book" then return ns.L("买书：", "Book: ") .. ns.L(t.name or "", rawget(t, "nameEn") or t.name or "") .. bookTag(t) end
    if t.via == "quest" then return ns.L("任务：", "Quest: ") .. ns.L(t.name or "", rawget(t, "nameEn") or t.name or "") .. A.QuestWhereShort(t) end
    return ns.L("找训练师", "Trainer")
end

local function tierNeed(t)
    local s = ns.L("技能 ", "skill ") .. (t.sk or "?")
    if (t.lv or 0) > 0 then s = s .. ns.L("、角色 ", ", Lv ") .. t.lv .. ns.L(" 级", "") end
    return s
end

local function myLevel() return UnitLevel and UnitLevel("player") or 1 end
local function myClass()
    if not UnitClass then return nil end
    local _, c = UnitClass("player")
    return c
end

-- 顶上一行：下一档去学什么
local function nextTierRow(key, s)
    local ui = UI()
    local nt = A.NextTier(key, s, myLevel())
    if not nt then return end
    local t = nt.tier
    local state
    if not s then
        state = ns.L("还没学这个专业：先去学", "Not learned yet: train ") .. ns.L(t.zh, t.en)
    elseif nt.ready and nt.lvOk then
        state = GREEN .. ns.L("现在就能学 ", "You can train ") .. ns.L(t.zh, t.en) .. "|r"
    elseif not nt.ready and t.sk then
        state = ns.L("下一档 ", "Next: ") .. ns.L(t.zh, t.en) .. RED .. string.format(ns.L("（技能还差 %d 点）", " (%d more skill)"), t.sk - s.r) .. "|r"
    else
        state = ns.L("下一档 ", "Next: ") .. ns.L(t.zh, t.en) .. RED .. string.format(ns.L("（要角色 %d 级）", " (needs Lv %d)"), t.lv or 0) .. "|r"
    end
    local sub = (s and (tierNeed(t) .. ns.L(" 可学 · ", " to train - ")) or "") .. tierVia(t) .. ns.L(" · 上限 ", " - cap ") .. (t.cap or "?")
    ui.item("Interface\\Icons\\INV_Misc_Book_11", BLUE .. state .. "|r", sub, A.QuestWhereTip(t, BLUE .. state .. "|r", sub), bookOf(t) or A.QuestLink(t))
end

local function segTitle(seg)
    local t = seg.tier
    local s = seg.f .. "-" .. seg.t .. (t and ("  " .. ns.L(t.zh, t.en)) or "")
    if seg.state == "here" then s = "> " .. s .. ns.L("  你在这一段", "  you are here") end
    return s
end

-- 这一段要先学的档位（第一段 = 学专业本身）
local function segTierRow(seg, rank)
    local t = seg.tier
    if not t or seg.idx == 1 then return end
    local title = BLUE .. ns.L("先学 ", "Train ") .. ns.L(t.zh, t.en) .. "|r  " .. tierNeed(t) .. A.QuestGate(t, rank)
    local sub = tierVia(t) .. ns.L(" · 学了上限到 ", " - raises the cap to ") .. (t.cap or seg.t)
    UI().item("Interface\\Icons\\INV_Misc_Book_11", title, sub, A.QuestWhereTip(t, title, sub), bookOf(t) or A.QuestLink(t))
end

local function doneRow(seg)
    UI().item(nil, GREY .. seg.f .. "-" .. seg.t .. (seg.tier and ("  " .. ns.L(seg.tier.zh, seg.tier.en)) or "")
        .. ns.L("  已练完", "  done") .. "|r", GREY .. ns.L("点右上「显示已练完的」展开", "Use \"Show finished\" to expand") .. "|r")
end

local function coverageRow(key)
    local c = A.Coverage(key)
    if c == "full" then return end
    local ui = UI()
    if c == "none" then
        ui.item("Interface\\Icons\\INV_Misc_QuestionMark", RED .. ns.L("数据待补", "Data pending") .. "|r",
            ns.L("这个专业还没有可靠的游戏数据，先不给路线", "No reliable game data for this profession yet"))
    elseif A.KIND[key] == "fish" then
        ui.item("Interface\\Icons\\INV_Misc_QuestionMark", GOLD .. ns.L("经典旧世基线，《无限》还没实测", "Classic baseline, not verified in Forever") .. "|r",
            ns.L("水域要求来自经典数据；钓多少次涨一点没有数据（待补），以游戏里为准", "Water skill from Classic data; skill-up rate unknown"),
            { ns.L("钓鱼数据说明", "About fishing data"),
              ns.L("水域基础技能取自经典旧世数据库（vmangos skill_fishing_base_level）。", "Water base skill comes from the Classic database."),
              ns.L("经典规则：技能达到「基础 + 95」不再跑鱼。《无限》有没有改过还没实测。", "Classic rule: no getaways at base + 95. Not yet verified in Forever."),
              ns.L("涨点次数规律客户端数据里没有，这里不写数字。", "Skill-up rate is not in client data, so no numbers here.") })
    else
        ui.item("Interface\\Icons\\INV_Misc_QuestionMark", GOLD .. ns.L("采集点分布是经典旧世基线", "Node spawns are the Classic baseline") .. "|r",
            ns.L("需求技能来自《无限》客户端；每张图有多少点来自经典数据库，《无限》可能挪过", "Skill needed is from the Forever client; spawn counts are from Classic data"))
    end
end

-- ---------- 烹饪：现在最值得吃的 ----------
local function foodRows(cookRank)
    local ui = UI()
    local lv, cls = myLevel(), myClass()
    local list = A.BestFoods(lv, cls, cookRank, 3)
    if #list == 0 then return end
    ui.head(string.format(ns.L("%d 级现在最值得吃的（按职业挑属性）", "Best food at level %d (by class)"), lv))
    for _, e in ipairs(list) do
        local f = e.f
        local kn = A.KIND_NAME[e.kind]
        local state
        if e.can then state = GREEN .. ns.L("你能做", "You can cook it") .. "|r"
        elseif e.unknown then state = GREY .. ns.L("学习技能数据待补", "skill needed: unknown") .. "|r"
        elseif e.nocook then state = RED .. string.format(ns.L("要烹饪 %d（你还没学烹饪）", "Cooking %d (not learned)"), f.learn) .. "|r"
        else state = RED .. string.format(ns.L("烹饪还差 %d 点（要 %d）", "%d more Cooking (needs %d)"), e.lack, f.learn) .. "|r" end
        local mats = matList(f.m)
        local sub = string.format(ns.L("使用 %d 级 · ", "Use Lv %d - "), f.use or 1)
        if e.now then
            sub = sub .. ns.L("现在能做：", "Now: ") .. ns.L(e.now.f.zh, e.now.f.en) .. " +" .. e.now.amt .. ns.L(" · ", " - ")
        end
        sub = sub .. ns.L("材料：", "Mats: ") .. table.concat(mats, SEP()) .. ns.L(" · 配方：", " - Recipe: ") .. A.FoodSource(f)
        local tip = { ns.L(f.zh, f.en), A.FoodBuff(f) }
        if f.xp then tip[#tip + 1] = ns.L("自制食物：击杀经验 +", "Crafted food: kill XP +") .. ((ns.ProfData and ns.ProfData.xpPct) or 5) .. "%" end
        tip[#tip + 1] = string.format(ns.L("使用等级 %d · 学习要烹饪 %s · 黄 %d · 灰 %d", "Use Lv %d, learn at Cooking %s, yellow %d, grey %d"),
            f.use or 1, f.learn and tostring(f.learn) or "?", f.y, f.gr)
        tip[#tip + 1] = ns.L("材料：", "Mats: ") .. table.concat(mats, SEP())
        tip[#tip + 1] = ns.L("配方：", "Recipe: ") .. A.FoodSource(f) .. ((f.fz or f.fe) and (ns.L(" · ", " - ") .. ns.L(f.fz or f.fe, f.fe or f.fz)) or "")
        if e.now then
            tip[#tip + 1] = ns.L("现在能做的同类：", "What you can cook now: ") .. ns.L(e.now.f.zh, e.now.f.en) .. " · " .. A.FoodBuff(e.now.f)
        end
        local rr = ns.ProfRecipeBySpell and ns.ProfRecipeBySpell(f.sp)
        ui.item(ui.icon("cooking"), GOLD .. ns.L(kn[1], kn[2]) .. " +" .. e.amt .. "|r  " .. ns.L(f.zh, f.en) .. "  " .. state, sub, tip,
            { item = f.item, spell = f.sp, mats = f.m, recipe = rr and rr[14] ~= 1 and rr or nil })
    end
end

-- ---------- 制造 ----------
local function stepRow(key, e)
    local ui = UI()
    local st, rem = e.st, e.rem
    local rank = e.rank
    local col = rank and P().HEX[P().RecipeColor(st, rank)] or "ffffff"
    local mats = matList(rem and rem.mats or st.m)
    local rr = ns.ProfRecipeBySpell and ns.ProfRecipeBySpell(st.sp)
    local src
    if rr and rr[14] ~= 1 and (rr[16] or 0) > 0 and ui.shortSource then
        src = ui.shortSource(rr)
    elseif st.src == "vendor" then
        src = ns.L("配方商人卖", "recipe from a vendor")
    elseif st.src == "auto" then
        src = ns.L("学专业就会", "known from the start")
    else
        src = ns.L("训练师", "trainer") .. ((rr and rr[4]) and string.format(ns.L("（技能 %d 可学）", " (at %d)"), rr[4]) or "")
    end
    local where = st.fo == 1 and ns.L("  要铁砧", "  needs anvil") or st.fo == 3 and ns.L("  要熔炉", "  needs forge") or ""
    local tip = { ns.L(st.zh, st.en), string.format(ns.L("黄 %d · 绿 %d · 灰 %d", "Yellow %d, green %d, grey %d"), st.y, st.g, st.gr),
        ns.L("材料：", "Mats: ") .. table.concat(mats, SEP()), ns.L("配方：", "Recipe: ") .. src }
    local info = A.StepInfo(key, st)
    for _, al in ipairs(info and info.alt or {}) do
        local am = {}
        for _, mt in ipairs(al.m) do am[#am + 1] = A.ItemName(mt[1]) .. "×" .. mt[2] end
        tip[#tip + 1] = string.format(ns.L("备选：%s ×%d（每次 %s）", "Alt: %s x%d (each: %s)"), ns.L(al.zh, al.en), al.c, table.concat(am, SEP()))
            .. (al.x and string.format(ns.L(" · 材料价值约 %.1f 倍", ", ~%.1fx mat value"), al.x) or "")
    end
    tip[#tip + 1] = ns.L("次数是期望值；材料价值按商人价估算，不是拍卖行价格。路线已经按这个估算挑了最省的，备选是手头正好有材料时可以换着做的", "Counts are expected values; mat value uses vendor prices, not the auction house. The route already picks the cheapest by this estimate; alts are for when you happen to have the mats")
    if rr and rr[14] ~= 1 and ns.ProfSourceTip then ns.ProfSourceTip(tip, rr) end
    local title
    if not rem then
        title = GREY .. st.f .. "-" .. st.t .. "  " .. ns.L(st.zh, st.en) .. ns.L("  已过", "  done") .. "|r"
    else
        title = (e.here and (GREEN .. "> |r") or "") .. GOLD .. ((rem.part and rank) or st.f) .. "-" .. st.t .. "|r  |cff" .. col
            .. ns.L(st.zh, st.en) .. "|r ×" .. rem.c .. (rem.part and (GREEN .. ns.L("（从你现在算）", " (from now)") .. "|r") or "")
            .. GREY .. where .. "|r"
    end
    ui.item(nil, title, ns.L("材料：", "Mats: ") .. table.concat(mats, SEP()) .. GREY .. ns.L("  配方：", "  Recipe: ") .. src .. "|r", tip,
        { spell = st.sp, mats = rem and rem.mats or st.m, recipe = rr and rr[14] ~= 1 and rr or nil })
end

local function DEDUCT_NOTE()
    return ns.L("自己做的半成品（布卷、火药、磨刀石这类）已经折成原料，不重复算", "Intermediates you craft yourself are folded into raw mats, not counted twice")
end

-- 估算花费一行：写明按什么价格算。有了真实价格（拍卖行扫描 / 手填）才多出「按现在的价格重算」那一行
--   ⛔ 现在还没有拍卖行扫描，也没有手填价格的界面，所以重算那一行平时不出现（入口先留在这里）
local function costRow(key, plan)
    local ui = UI()
    if not plan.cost or not ns.Prices then return end
    local M = ns.Prices
    ui.item("Interface\\Icons\\INV_Misc_Coin_01", GOLD .. ns.L("材料估价 ", "Mat cost ") .. "|r" .. M.Money(plan.cost)
        .. GREY .. ns.L("（", " (") .. plan.priceLabel .. ns.L("）", ")") .. "|r",
        plan.priceKind and "" or ns.L("没有拍卖行价格：商人卖的按商人价，其余按卖店价估算，只用来比较哪个配方更省", "No auction prices: vendor items at vendor price, the rest estimated from sell price - only for comparing recipes"),
        { ns.L("材料估价", "Mat cost"), plan.priceLabel,
          ns.L("这不是你真要花的钱，只是挑配方用的同一把尺子", "Not what you will really pay - just one yardstick for picking recipes") })
    if not plan.priceKind then return end
    local res = A.Reroute(key, plan.rank)
    if not res or not res.base or res.total.cost >= res.base then return end
    local tip = { ns.L("按现在的价格重算的路线", "Route re-solved with current prices") }
    for _, st in ipairs(res.steps) do
        local nm = ns.SpellNameRaw(st.sp)   -- 11-15 GI-266：C_Spell.GetSpellName 优先（《无限》新客户端没有全局 GetSpellInfo）
        nm = nm and ns.FromClient(nm)
        tip[#tip + 1] = st.f .. "-" .. st.t .. "  " .. (type(nm) == "string" and nm or tostring(st.sp)) .. " ×" .. st.c
    end
    ui.item("Interface\\Icons\\INV_Misc_Coin_02", GREEN .. ns.L("按现在的价格重算能再省 ", "Re-solving with current prices saves ") .. "|r"
        .. M.Money(res.base - res.total.cost), ns.L("悬停看重算后的步骤", "Hover for the re-solved steps"), tip)
end

local function renderCraft(key, s)
    local ui = UI()
    local rank = s and s.r
    local plan = A.CraftPlan(key, rank)
    ui.head(P().Name(key) .. ns.L(" 专业助手 · 1 至 300 省材料路线", " assistant - 1 to 300, low-mat route")
        .. (plan and (GREY .. ns.L("（", " (") .. plan.priceLabel .. ns.L("）", ")") .. "|r") or "")
        .. (rank and ("   " .. GREEN .. ns.L("你现在 ", "you: ") .. rank .. (s.m and ("/" .. s.m) or "") .. "|r")
            or ("   " .. GREY .. ns.L("还没学，先看看", "not learned - browsing") .. "|r")))
    coverageRow(key)
    if not plan then return end
    nextTierRow(key, s)
    if key == "cooking" then foodRows(rank) end
    for _, seg in ipairs(plan.segs) do
        if seg.state == "done" and not showAll then
            doneRow(seg)
        else
            ui.head(segTitle(seg))
            if seg.state ~= "done" then segTierRow(seg, rank) end
            for _, e in ipairs(seg.steps) do
                e.rank = rank
                if e.rem or showAll then stepRow(key, e) end
            end
            if #seg.steps == 0 then
                ui.item(nil, GREY .. ns.L("这一段路线上没有步骤", "No steps in this bracket") .. "|r", "")
            end
            totalRows(rank and seg.state == "here" and ns.L("这一段还要的材料", "Mats left for this bracket") or ns.L("这一段材料合计", "Mats for this bracket"),
                seg.total, seg.deducted and DEDUCT_NOTE() or nil)
        end
    end
    if #plan.total > 0 then
        ui.head(rank and ns.L("从现在练到 300 一共还要", "Everything left to reach 300") or ns.L("1 练到 300 一共要", "Everything from 1 to 300"))
        totalRows(ns.L("材料合计", "All mats"), plan.total,
            plan.deducted and DEDUCT_NOTE() or ns.L("没有扣掉前面步骤做出来又被后面用掉的半成品", "Intermediates crafted in earlier steps are not deducted"))
        costRow(key, plan)
    elseif rank and rank >= 300 then
        ui.item(nil, GREEN .. ns.L("已经 300 了", "Already at 300") .. "|r", "")
    end
end

-- ---------- 采集 ----------
local function lvText(lv)
    if type(lv) ~= "table" or not lv[1] then return "" end
    return string.format(ns.L("（%d-%d 级）", " (Lv %d-%d)"), lv[1], lv[2] or lv[1])
end

local function mapName(mp)
    return ns.L(mp.zh or "", mp.en or mp.zh or "")
end

local function renderGather(key, s)
    local ui = UI()
    local rank = s and s.r
    local G = P().GatherColor
    ui.head(P().Name(key) .. ns.L(" 专业助手 · 每一段去哪张图", " assistant - where to go in each bracket")
        .. (rank and ("   " .. GREEN .. ns.L("你现在 ", "you: ") .. rank .. (s.m and ("/" .. s.m) or "") .. "|r")
            or ("   " .. GREY .. ns.L("还没学，先看看", "not learned - browsing") .. "|r")))
    coverageRow(key)
    nextTierRow(key, s)
    for _, seg in ipairs(A.GatherSegs(key, rank) or {}) do
        if seg.state == "done" and not showAll then
            doneRow(seg)
        else
            ui.head(segTitle(seg))
            if seg.state ~= "done" then segTierRow(seg, rank) end
            for i, mp in ipairs(seg.maps) do
                local sub, tip
                if key == "skinning" then
                    local sk = mp.sk
                    sub = string.format(ns.L("%d-%d 级野兽 · 要剥皮 %d-%d · 练到 %d 不再涨", "Lv %d-%d beasts, needs %d-%d, grey at %d"),
                        sk[1], sk[2], sk[3], sk[4], sk[4] + 100)
                else
                    local parts = {}
                    for _, nd in ipairs(mp.nodes or {}) do
                        local c = rank and G and G(nd[3], rank)
                        local hex = c and P().HEX[c] or "ffffff"
                        parts[#parts + 1] = "|cff" .. hex .. ns.L(nd[1], nd[2]) .. "|r" .. string.format(ns.L("（要 %d · 约 %d 处）", " (%d, ~%d)"), nd[3], nd[4])
                    end
                    sub = table.concat(parts, SEP())
                end
                tip = { mapName(mp) .. lvText(mp.lv), sub,
                    ns.L("颜色按你现在的技能：红 = 采不了，橙 / 黄 / 绿 = 会涨，灰 = 不涨", "Colors use your skill: red = can't, orange/yellow/green = skill-ups, grey = none") }
                ui.item(i == 1 and ui.icon(key) or nil, GOLD .. i .. ".|r " .. mapName(mp) .. GREY .. lvText(mp.lv) .. "|r", sub, tip)
            end
            if #seg.maps == 0 then
                ui.item(nil, RED .. ns.L("数据待补", "Data pending") .. "|r", ns.L("这一段没有合适地图的资料", "No zone data for this bracket"))
            end
        end
    end
    -- 明细：原来的「技能多少去哪张图」总表
    if ui.renderGather then ui.renderGather(key, rank) end
end

-- ---------- 钓鱼 ----------
local FISH_HEX = { safe = "33ff99", ok = "ffd100", low = "ff6060" }
local function renderFish(s)
    local ui = UI()
    local rank = s and s.r
    ui.head(P().Name("fishing") .. ns.L(" 专业助手 · 技能多少去哪钓", " assistant - where to fish at each skill")
        .. (rank and ("   " .. GREEN .. ns.L("你现在 ", "you: ") .. rank .. (s.m and ("/" .. s.m) or "") .. "|r")
            or ("   " .. GREY .. ns.L("还没学，先看看", "not learned - browsing") .. "|r")))
    coverageRow("fishing")
    nextTierRow("fishing", s)
    local p = ns.ProfData.profs.fishing
    if p and p.tiers then
        ui.head(ns.L("档位", "Ranks"))
        for i, t in ipairs(p.tiers) do
            if i > 1 then
                ui.item("Interface\\Icons\\INV_Misc_Book_11", BLUE .. ns.L(t.zh, t.en) .. "|r  " .. tierNeed(t), tierVia(t) .. ns.L(" · 上限 ", " - cap ") .. (t.cap or "?"))
            end
        end
    end
    local groups = A.FishGroups(rank)
    if not groups then return end
    ui.head(ns.L("水域（从低到高）", "Waters (low to high)"))
    for _, g in ipairs(groups) do
        local names = {}
        for _, mp in ipairs(g.maps) do names[#names + 1] = mapName(mp) end
        local hex = g.state and FISH_HEX[g.state] or "ffffff"
        local st = g.state == "safe" and ns.L("不跑鱼", "no getaways") or g.state == "ok" and ns.L("能钓，会跑鱼", "fishable, some getaways")
            or g.state == "low" and ns.L("技能不够", "skill too low") or ""
        local title = (g.best and (GREEN .. "> |r") or "") .. "|cff" .. hex
            .. string.format(ns.L("技能 %d 起能钓 · %d 起不跑鱼", "Fish from %d, no getaways from %d"), g.cast, math.max(1, g.safe)) .. "|r"
            .. (st ~= "" and ("  " .. GREY .. st .. "|r") or "") .. (g.best and (GREEN .. ns.L("  现在去这里", "  go here now") .. "|r") or "")
        local sub = table.concat(names, SEP())
        ui.item(g.best and ui.icon("fishing") or nil, title, sub,
            { title, sub, ns.L("经典旧世水域基础技能 ", "Classic water base skill ") .. g.base .. ns.L("；《无限》未实测", "; not verified in Forever") })
    end
end

-- PageProf 的冲级路线先问这里；返回 true = 已经画了
function ns.ProfAssistRender(key, skills)
    if not (A.Ready() and UI()) then return false end
    local kind = A.KIND[key]
    local s = skills and skills[key]
    if kind == "craft" then renderCraft(key, s)
    elseif kind == "gather" then renderGather(key, s)
    elseif kind == "fish" then renderFish(s)
    else return false end
    return true
end

-- 页面上多一个「显示已练完的」开关（只在冲级路线子页出现）
function ns.ProfAssistBuild(page, refresh)
    local b = ns.Button(page, ns.L("显示已练完的", "Show finished"), 110, 20, function()
        showAll = not showAll
        refresh()
    end)
    b:SetPoint("TOPRIGHT", -12, -96)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.L("默认只列接下来要做的；点一下把已经练完的段和步骤也列出来", "By default only what's left is listed; click to show finished brackets too"), 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.assistBtn = b
end

function ns.ProfAssistRefresh(page, tab)
    local b = rawget(page, "assistBtn")
    if not b then return end
    b:SetShown(tab == "route")
    b:SetText(showAll and ns.L("只看接下来的", "Only what's left") or ns.L("显示已练完的", "Show finished"))
end

ns._ProfAssistShowAll = function(v) if v ~= nil then showAll = v end return showAll end   -- 测试用
