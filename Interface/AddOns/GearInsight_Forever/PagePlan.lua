-- 升级规划页（10-07 用户「天赋都引入升级规划…升到多少级，对当前已有的天赋点、技能、宏，以及装备实现最优配置。
--   详细展示任务链或者来源，点了弹出…装备最好是类似用户 C 键的用户栏那种展示」）：
-- 「要做的事」页签（原名「时间轴」，10-07 用户看不懂改名）：按等级顺序列出这期间要做的事——天赋怎么加点、去训练师学什么新技能、该导入哪些宏、
--   哪些技能是打任务解锁的（点开看完整任务链：谁给、在哪、目标是什么）。
-- 「装备」页签（10-18 起独立，在左栏「装备」大类下）：仿 C 键纸娃娃布局，每个部位按目标等级推荐一件装等最高的候选（地下城掉落 + 职业任务链套装 + 11-06 起专业制造 / 商人出售）。
--   ⛔ 装备来源 = 地下城掉落（经典 25 本 + 无限新本）+ 职业任务链套装，野外任务奖励还没收——
--   查不到候选的部位显示「待补」，不装样子说全；天赋「对练级最优」复用热门配点数据，不是专门算的练级权重。
local _, ns = ...; ns = _G.GearInsightForever or ns

local page
local ICON = { quest = "Interface\\Icons\\INV_Misc_Book_09", spell = "Interface\\Icons\\INV_Misc_Note_01",
    talent = "Interface\\Icons\\Spell_Nature_InnerSerenity", macro = "Interface\\Icons\\INV_Scroll_05" }
local QCOLOR = { q1 = "ffffff", q2 = "1eff00", q3 = "0070dd", q4 = "a335ee", q5 = "ff8000" }
local viewMode = "timeline"   -- "timeline" | "farm" | "dq" | "route"（「装备」10-18 起是独立页签）
local gp = {}   -- 「装备」页签（纸娃娃）自己的控件表；和升级规划的 page 分开
-- 纸娃娃：照游戏 C 键角色栏（10-07 用户截图 + 「学习这个格式」，插件-工会会话转达）
--   左列 头 / 颈 / 肩 / 背 / 胸 / 衬衣 / 战袍 / 手腕，右列 手 / 腰 / 腿 / 脚 / 戒指×2 / 饰品×2，底部 主手 / 副手 / 远程；
--   中间放角色模型试穿推荐装备。10-08 起格子旁写装备名 + 装等/等级/来源（照英雄榜纸娃娃），悬停看详情。{ 槽位键, 数据里的部位, 游戏槽位名（拿空槽剪影 / 身上装备） }
local GEAR_LEFT = { { "head", "头部", "HeadSlot" }, { "neck", "颈部", "NeckSlot" }, { "shoulder", "肩部", "ShoulderSlot" },
    { "back", "背部", "BackSlot" }, { "chest", "胸部", "ChestSlot" }, { "shirt", nil, "ShirtSlot" }, { "tabard", nil, "TabardSlot" },
    { "wrist", "手腕", "WristSlot" } }
local GEAR_RIGHT = { { "hands", "手", "HandsSlot" }, { "waist", "腰部", "WaistSlot" }, { "legs", "腿部", "LegsSlot" },
    { "feet", "脚", "FeetSlot" }, { "finger1", "手指", "Finger0Slot" }, { "finger2", "手指", "Finger1Slot" },
    { "trinket1", "饰品", "Trinket0Slot" }, { "trinket2", "饰品", "Trinket1Slot" } }
local GEAR_BOTTOM = { { "main", "武器", "MainHandSlot" }, { "off", "副手", "SecondaryHandSlot" }, { "ranged", "远程", "RangedSlot" } }
local SLOT_FALLBACK_TEX = { HeadSlot = "Head", NeckSlot = "Neck", ShoulderSlot = "Shoulder", BackSlot = "Chest", ChestSlot = "Chest",
    ShirtSlot = "Shirt", TabardSlot = "Tabard", WristSlot = "Wrists", HandsSlot = "Hands", WaistSlot = "Waist", LegsSlot = "Legs",
    FeetSlot = "Feet", Finger0Slot = "Finger", Finger1Slot = "Finger", Trinket0Slot = "Trinket", Trinket1Slot = "Trinket",
    MainHandSlot = "MainHand", SecondaryHandSlot = "SecondaryHand", RangedSlot = "Ranged" }

local function myClass() return ns.MyClass() end

-- ⛔ 10-07 用户「可以做成双向的筛选条，可以筛选最高，也可以最低，筛选中间的」：
--   原来的「目标等级 ±1/±5」→ 一根 1-60 的双拖柄范围条 [lo, hi]，起点不再强制等于当前等级（可以往回看补学漏掉的）。
--   范围按**角色**存（ns.db.ui.planRange[角色]）——存档是账号共用的，存成一份的话开小号会看到大号的范围。
--   老存档的 planBaseLv / planTarget 读到就清掉 / 迁成 hi。
local function curLv() return UnitLevel and UnitLevel("player") or 1 end
local function charKey() return (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?") end
local function clampLv(v) return math.max(1, math.min(60, math.floor((tonumber(v) or 1) + 0.5))) end

local function range()
    ns.db.ui = ns.db.ui or {}
    local ui = ns.db.ui
    if ui.planBaseLv ~= nil then ui.planBaseLv = nil end
    ui.planRange = ui.planRange or {}
    local r = ui.planRange[charKey()]
    local cur = curLv()
    if not r then
        r = { lo = cur, hi = clampLv(ui.planTarget or (cur + 10)) }
        if r.hi < r.lo then r.hi = clampLv(cur + 10) end
        ui.planRange[charKey()] = r
    end
    ui.planTarget = nil
    local lo, hi = clampLv(r.lo), clampLv(r.hi)
    if lo > hi then lo, hi = hi, lo end
    return lo, hi
end

local function setRangeRaw(lo, hi)
    lo, hi = clampLv(lo), clampLv(hi)
    if lo > hi then lo, hi = hi, lo end
    range()
    ns.db.ui.planRange[charKey()] = { lo = lo, hi = hi }
end

-- 合并：任务解锁技能 / 训练技能 / 天赋加点 / 宏，按等级分组，同级内 任务>天赋>技能>宏
-- 状态 st：future = 还没到；now = 这一级 / 已到但还没学；done = 已经学会 / 已过的任务；missed = 等级已过却没学（漏学）
local ORDER = { zone = 0, quest = 1, chain = 1.5, talent = 2, spell = 3, macro = 4, dquest = 5, prof = 6 }
local function spellKnown(id)
    if not id or id == 0 or not IsSpellKnown then return nil end
    local ok, v = pcall(IsSpellKnown, id)
    if ok then return v and true or false end
end
-- 10-07 用户截图「技能等级能显示吗？」：同名技能在数据里每一级各一条（德鲁伊愤怒 1/6/14/22/30/38/46/54 级），
--   按学习等级排好后的序号就是「等级 N」；只有一级的技能不标
local function rankTable(cls)
    local byName = {}
    for _, s in ipairs((ns.Data.spells or {})[cls] or {}) do
        if not s.quest then
            byName[s.n] = byName[s.n] or {}
            table.insert(byName[s.n], s.lv)
        end
    end
    for _, l in pairs(byName) do table.sort(l) end
    return byName
end
local function rankOf(ranks, name, lv)
    local l = ranks[name]
    if not l or #l < 2 then return nil end
    for i, x in ipairs(l) do if x == lv then return i, #l, l[i + 1] end end
end
ns.PlanRankOf = function(cls, name, lv) return rankOf(rankTable(cls), name, lv) end   -- 测试用

local function buildItems(lo, hi, desc)
    local cls, cur = myClass(), curLv()
    local items = {}
    local ranks = rankTable(cls)
    local notTr = ns.TrainNow and ns.TrainNow.NotTrainer
    for _, s in ipairs((ns.Data.spells or {})[cls] or {}) do
        if s.lv >= lo and s.lv <= hi then
            if s.quest then
                items[#items + 1] = { lv = s.lv, kind = "quest", n = s.n, st = s.lv < cur and "done" or (s.lv == cur and "now" or "future") }
            else
                local known = spellKnown(s.id)
                -- 天赋系技能（s.tal）没学会多半是没点那个天赋，不算「漏学」
                -- 11-19 整体更正：技能书 / 任务 / 掉落给的（安其拉书暗影箭 10、熊形态任务给的低吼…，TrainNowData.nt）同样不算漏学、不给找训练师
                local nt = notTr and s.id and notTr(cls, s.id) or nil
                local st = known and "done" or ((s.tal or nt) and known == false and s.lv <= cur and "tal")
                    or (s.lv < cur and known == false and "missed") or (s.lv <= cur and "now") or "future"
                local rk, rkMax, nextLv = rankOf(ranks, s.n, s.lv)
                items[#items + 1] = { lv = s.lv, kind = "spell", n = s.n, i = s.i, auto = s.auto, d = s.d, st = st, tal = s.tal, nt = nt,
                    rank = rk, rankMax = rkMax, nextLv = nextLv }
            end
        end
    end
    local onBars = ns.MacrosOnBars and ns.MacrosOnBars() or {}   -- 动作条扫一次，所有宏共用
    for _, m in ipairs((ns.Macros or {})[cls] or {}) do
        local lv = m.lv or 0
        if lv >= lo and lv <= hi then
            local ms = ns.MacroState and ns.MacroState(m, onBars) or "none"
            items[#items + 1] = { lv = lv, kind = "macro", m = m, ms = ms,
                st = (ms == "onbar") and "done" or (lv <= cur and "now" or "future") }
        end
    end
    -- 10-10 用户截图「任务整合到这里？」：副本任务按「几级能接」并进时间轴 —— 同一级同一副本合成一行，点开是副本任务弹框
    if ns.DQ and ns.DQList then
        for _, d in ipairs(ns.DQ.dungeons) do
            local byLv = {}
            for _, e in ipairs(ns.DQList(d)) do
                local lv = math.max(1, e.q.req or 1)
                if lv >= lo and lv <= hi then
                    local g = byLv[lv]
                    if not g then g = { lv = lv, kind = "dquest", d = d, list = {} }; byLv[lv] = g; items[#items + 1] = g end
                    g.list[#g.list + 1] = e
                end
            end
            for lv, g in pairs(byLv) do
                local nDone, nOpen = 0, 0
                for _, e in ipairs(g.list) do
                    if e.s == "done" then nDone = nDone + 1 elseif e.s == "ok" or e.s == "log" then nOpen = nOpen + 1 end
                end
                g.nDone, g.nOpen = nDone, nOpen
                g.st = (nDone == #g.list) and "done" or (lv <= cur and "now") or "future"
            end
        end
    end
    -- 天赋只能从「现在已点的」往后推（过去的点已经点了，不知道当时怎么点的），所以只出 >= 当前等级的
    local steps, err
    if hi >= cur and ns.PlanTalentSteps then steps, err = ns.PlanTalentSteps(hi, cur) end
    if steps then
        for _, stp in ipairs(steps) do
            if stp.lv >= math.max(lo, cur) and stp.lv <= hi then
                items[#items + 1] = { lv = stp.lv, kind = "talent", st = stp, state = stp.lv <= cur and "now" or "future" }
            end
        end
    end
    -- 11-10 用户「为啥19级没展示天赋点点哪里」：本级那一点已经点了 → 照列，标「已点」（不然本级像没天赋）
    if cur >= 10 and cur >= lo and cur <= hi and ns.PlanSpentStep then
        local has = false
        for _, it in ipairs(items) do if it.kind == "talent" and it.lv == cur then has = true end end
        local ok, stp = pcall(ns.PlanSpentStep, cur - 9)
        if not has and ok and stp then items[#items + 1] = { lv = cur, kind = "talent", st = stp, state = "done" } end
    end
    -- 10-18 特殊任务线（SideChains.lua，HOLD 里没装就没有）：舒适的睡袋等跨地图任务线，推荐等级那一级出一行
    if ns.SideChainItems then
        local ok, list = pcall(ns.SideChainItems, lo, hi, cur)
        for _, it in ipairs(ok and list or {}) do items[#items + 1] = it end
    end
    -- 11-23 门任务（用户「升级规划加入重要的门任务必做的任务，点击可以打开悬浮窗，任务追踪，跟睡袋一样」）：
    --   数据在按需加载的 GearInsight_Forever_Gate（HOLD 没进包时 ModHas 为假 → 不加载、没有这些行）；每条按推荐等级出一行（kind = "chain"，gate = true）
    if not ns.GateChainsData and ns.ModHas and ns.ModHas("gate", "GateChainsData.lua") and ns.ModLoad then pcall(ns.ModLoad, "gate", nil, true) end
    if ns.GateChainItems and ns.GateChainsData then
        local ok, list = pcall(ns.GateChainItems, lo, hi, cur)
        for _, it in ipairs(ok and list or {}) do items[#items + 1] = it end
    end
    -- 10-16 专业接进地图待办（Prof.lua，HOLD 里没装就没有）：顺路采集 / 经验食物 / 训练 / 营地 / 图纸 / 传承
    if ns.ProfPlanItems then
        local ok, list = pcall(ns.ProfPlanItems, lo, hi, cur)
        for _, it in ipairs(ok and list or {}) do items[#items + 1] = it end
    end
    -- 10-07 用户「加个筛选，完成的可以过滤掉」：隐藏已学会的技能 / 已过的任务（分组跟着没了）
    local hidden = 0
    if ns.db.ui.planHideDone then
        local keep = {}
        for _, it in ipairs(items) do
            if it.st == "done" or (it.kind == "talent" and it.state == "done") then hidden = hidden + 1 else keep[#keep + 1] = it end
        end
        items = keep
    end
    page.hiddenDone = hidden
    -- Maps are context, not completable tasks. Add one block per route change,
    -- always including the visible range's first level and the player's level.
    if ns.RouteZones and ns.RouteRace then
        local fac = UnitFactionGroup and UnitFactionGroup("player")
        local previous
        for lv = lo, hi do
            local zones = ns.RouteZones(fac, ns.RouteRace(), lv).current
            local keys = {}
            for _, e in ipairs(zones) do
                keys[#keys + 1] = tostring(e.zone.m or e.zone.en) .. ":" .. e.lo .. ":" .. e.hi
            end
            local key = table.concat(keys, "|")
            if key ~= previous or lv == cur then
                for index, e in ipairs(zones) do
                    items[#items + 1] = { lv = lv, kind = "zone", entry = e, zoneOrder = index }
                end
            end
            previous = key
        end
    end
    table.sort(items, function(a, b)
        if a.lv ~= b.lv then
            if desc then return a.lv > b.lv end
            return a.lv < b.lv
        end
        if a.kind == "zone" and b.kind == "zone" then return a.zoneOrder < b.zoneOrder end
        return ORDER[a.kind] < ORDER[b.kind]
    end)
    return items, err, cur
end

-- 每个格子按目标等级能拿到的最好候选（地下城掉落 + 职业任务链套装 + 11-06 起专业制造 / 商人出售）；
-- ⛔ 来源不全（地下城 + 任务链套装，野外任务奖励没收），查不到的格子返回 nil，悬停说明「待补」
-- 10-18 按天赋：有属性数据（SpecGearData.lua）就按当前天赋的属性权重打分挑（SpecGear.lua），分数相同 / 没属性的再按装等；
--   SpecGear 不在（HOLD 剔掉）→ 和原来一样只按装等
-- 10-18 需求看板 #69（正式服会话转达）：萨满 / 猎人 40 级才会锁甲，战士 / 圣骑 40 级才会板甲 → 目标等级不到 40 不推这一档
--   ⛔ 网站导出 gi_forever_web_export.py best_gear 同一条，改一边必须改另一边
local ARMOR_AT40 = { Shaman = "锁甲", Hunter = "锁甲", Warrior = "板甲", Paladin = "板甲" }

-- ---------- 11-06 商人出售（src="vendor"，进主推荐）+ 专业制造（只当「备选」）----------
-- 用户「把商人和制造装备也加进BiS推荐」→ 11-06 拍板「制造件只当备选」。数据 scripts/gi_forever_gear_extra.py → craft_vendor_gear.json →
--   Data.lua：商人件进 gear[职业]；制造件在共享表 gearCraft（字段见 gi_forever_addon_data.py craft_table）。
-- ⛔ 三端同一条规则（网站导出 gi_forever_web_export.py best_gear / craft_alts 同一条，改一边必须改另一边）：
--   主推荐 = 副本掉落 + 任务奖励 + 商人件（商人件不走「确认掉过」推荐名单，生成时已按规则筛过）；制造件一律不参与主推荐
--   备选（craftAlts）：每格挑一件最佳制造件（按天赋打分，同分装等高、再物品 ID 小），分数 > 主推荐才带出来，给高多少 %
--     bop（拾取绑定 / 装备要求专业）只在「玩家有 it.pf 这个专业」时算；专业技能值不卡（网站 / 小程序拿不到）
--     profs 参数：{ 专业键 = true }；不传 = 看自己职业时读角色专业（Prof.lua，HOLD 里没装 = 当没专业），看别的职业 = 当没专业
local PROF_NAME = { blacksmithing = { "锻造", "Blacksmithing" }, leatherworking = { "制皮", "Leatherworking" }, tailoring = { "裁缝", "Tailoring" },
    engineering = { "工程学", "Engineering" }, enchanting = { "附魔", "Enchanting" }, alchemy = { "炼金术", "Alchemy" } }
local RECIPE_SRC = { trainer = { "训练师可学", "learned from trainer" }, drop = { "图纸靠掉落", "recipe drops" }, vendor = { "图纸商人有卖", "recipe sold by vendor" },
    rep = { "图纸要声望", "recipe needs reputation" }, auto = { "学会专业自带", "auto-learned" } }
local function profName(k)
    local p = PROF_NAME[k]
    return p and ns.L(p[1], p[2]) or (k or "?")
end
local function playerProfs()
    local P = ns.Prof
    local out = {}
    if not (P and P.Skills) then return out end
    local ok, sk = pcall(P.Skills)
    if ok and type(sk) == "table" then for k in pairs(sk) do out[k] = true end end
    return out
end
ns.PlanPlayerProfs = playerProfs
local function money(c)
    c = tonumber(c) or 0
    local g, s, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local t = {}
    if g > 0 then t[#t + 1] = g .. ns.L("金", "g") end
    if s > 0 then t[#t + 1] = s .. ns.L("银", "s") end
    if cu > 0 or #t == 0 then t[#t + 1] = cu .. ns.L("铜", "c") end
    return table.concat(t, " ")
end
-- 商人件：按玩家阵营挑商人（数据里中立的优先；本阵营买不到、另一阵营有 → a* 那个）
local function vendorPoint(it)
    local fac = UnitFactionGroup and UnitFactionGroup("player")
    local me = fac == "Alliance" and "A" or fac == "Horde" and "H" or nil
    if me and it.sd and it.sd ~= "N" and it.sd ~= me and it.anpc and (it.asd == "N" or it.asd == me) then
        return { npc = it.anpc, n = it.ann, z = it.az, ui = it.aum, x = it.ax, y = it.ay, sd = it.asd }
    end
    return { npc = it.npc, n = it.nn, z = it.z, ui = it.um, x = it.x, y = it.y, sd = it.sd }
end
ns.GearVendorPoint = vendorPoint
-- 获取方式一行（装备页 / 角色面板角标 / 聊天框共用）；掉落 / 任务件返回 nil（各自原来的写法）
-- 制造件：gear 行没有（制造只当备选），共享表 gearCraft 的行不带 src（省体积）→ 有专业键 pf 就是制造件
local function isCraft(it) return it.src == "craft" or (it.src == nil and it.pf ~= nil) end
function ns.GearSourceText(it)
    if not it then return nil end
    if isCraft(it) then
        local t = ns.L("制造：", "Crafted: ") .. profName(it.pf) .. " " .. (it.sk or 0)
        if it.eqs then
            t = t .. ns.L("（装备要求", " (requires ") .. profName(it.pf) .. " " .. it.eqs .. ns.L("，只有会这个专业的能用）", " to equip)")
        elseif it.bop then
            t = t .. ns.L("（拾取绑定：只能自己做）", " (BoP: craft it yourself)")
        else
            t = t .. ns.L(" · 可找人做或拍卖行买", " - ask a crafter or buy on the AH")
        end
        local rs = RECIPE_SRC[it.rs or ""]
        if rs then t = t .. ns.L(" · ", " - ") .. ns.L(rs[1], rs[2]) end
        return t
    elseif it.src == "vendor" then
        local v = vendorPoint(it)
        local t = ns.L("商人：", "Vendor: ") .. ns.TD(v.n or "?") .. (v.z and v.z ~= "" and (" @ " .. ns.TD(v.z)) or "")
            .. (((v.x or 0) > 0) and string.format(" (%.0f, %.0f)", v.x, v.y) or "")
        if (it.pr or 0) > 0 then t = t .. ns.L(" · 售价 ", " - ") .. money(it.pr) end
        if it.lim then t = t .. ns.L(" · 限量（卖完要等刷新）", " - limited stock") end
        if it.base then t = t .. ns.L(" · 经典资料，待游戏内确认", " - classic data, unconfirmed in Forever") end
        return t
    end
end
-- 点击指引：商人 → 地图标商人；制造 → 会这个专业就打开「专业」页配方，不会就提示找人做 / 拍卖行。返回做了什么（测试用），掉落 / 任务件返回 nil
function ns.GearGuide(it)
    if not it then return nil end
    if it.src == "vendor" then
        local v = vendorPoint(it)
        ns.Print(ns.GearSourceText(it))
        if v.ui and (v.x or 0) > 0 and ns.ShowOnMap then
            ns.ShowOnMap(v.ui, { { v.x, v.y } }, v.n)
            return "vendormap"
        end
        return "vendortext"
    elseif isCraft(it) then
        ns.Print(ns.ItemNm(it) .. " — " .. ns.GearSourceText(it))
        if playerProfs()[it.pf] and ns.ProfOpenTab then
            ns.ProfOpenTab("recipes")
            return "profpage"
        end
        return "crafttext"
    end
end

-- 备选：每格最佳制造件（分数比主推荐高才出）。out = 主推荐（bestGearBySlot 的结果）；返回 { 槽位键 = { it, s, pct } }
--   格子：头…脚 / 颈 / 背 / 远程 = 同部位；副手 = 副手部位（盾 / 副手物品；主推荐是双手武器时不出）；
--   主手 = 和主推荐同样单 / 双手的武器（没主推荐 = 单双手里分高的，平手取双手）；
--   戒指 / 饰品两格只出一个，挂在主推荐分低的那格（平手 / 都空 = 第二格；只有第一格空 = 第一格）
--   pct = floor((备选分 / 主推荐分 - 1) × 100 + 0.5 + 1e-6)（+1e-6 防两端浮点在 .5 边上取整不同）；主推荐没有或 0 分 → 没有 pct（只要备选分 > 0 就出）
local CRAFT_SINGLE = { head = "头部", neck = "颈部", shoulder = "肩部", back = "背部", chest = "胸部", wrist = "手腕", hands = "手",
    waist = "腰部", legs = "腿部", feet = "脚", ranged = "远程", off = "副手" }
local craftIdx
local function craftAlts(targetLv, cls, spec, profs, out)
    local SG, C = ns.SpecGear, ns.Data.gearCraft
    if not (spec and SG and SG.Available() and C) then return {} end
    if not craftIdx then craftIdx = {}; for i, c in ipairs(C.cls or {}) do craftIdx[c] = tostring(i) end end
    local ck = craftIdx[cls]
    if not ck then return {} end
    local best = {}
    for _, it in ipairs(C.items or {}) do
        local req = (it.req and it.req > 0) and it.req or (it.min or 0)
        if req <= targetLv and string.find(it.cl or "", ck, 1, true) and not (targetLv < 40 and it.type == ARMOR_AT40[cls])
            and not SG.Missing(it.id) and (not it.bop or profs[it.pf]) then
            local s = SG.Score(it.id, it.slot, cls, spec, targetLv)
            if s then
                local key = (it.slot == "武器") and (it.two and "武器2" or "武器1") or it.slot
                local b = best[key]
                local better = not b or s > b.s + 1e-6
                if not better and math.abs(s - b.s) <= 1e-6 then
                    if (it.ilvl or 0) ~= (b.it.ilvl or 0) then better = (it.ilvl or 0) > (b.it.ilvl or 0) else better = it.id < b.it.id end
                end
                if better then best[key] = { it = it, s = s } end
            end
        end
    end
    local alts = {}
    local function mainScore(key)
        local m = out[key]
        if not m then return nil end
        return SG.Score(m.id, key == "off" and "副手" or m.slot, cls, spec, targetLv) or 0
    end
    local function put(key, b)
        if not b then return end
        local sm = mainScore(key)
        if (sm == nil and b.s > 1e-6) or (sm ~= nil and b.s > sm + 1e-6) then
            alts[key] = { it = b.it, s = b.s, pct = (sm and sm > 1e-6) and math.floor((b.s / sm - 1) * 100 + 0.5 + 1e-6) or nil }
        end
    end
    for key, slot in pairs(CRAFT_SINGLE) do
        if not (key == "off" and out.main and out.main.two) then put(key, best[slot]) end
    end
    local m = out.main
    if m then put("main", best[m.two and "武器2" or "武器1"])
    else
        local b1, b2 = best["武器1"], best["武器2"]
        put("main", (b1 and (not b2 or b1.s > b2.s + 1e-6)) and b1 or b2)
    end
    for _, pr in ipairs({ { "finger1", "finger2", "手指" }, { "trinket1", "trinket2", "饰品" } }) do
        local s1, s2 = mainScore(pr[1]), mainScore(pr[2])
        local key = pr[2]
        if (s1 == nil and s2 ~= nil) or (s1 ~= nil and s2 ~= nil and s1 < s2 - 1e-6) then key = pr[1] end
        put(key, best[pr[3]])
    end
    return alts
end
-- 备选那一行（角标提示 / 装备页 / 刷本清单共用）：「也可以：<名>（<专业> <技能> · 找人做 / 拍卖行，+N%）」
function ns.GearAltText(a)
    if not (a and a.it) then return nil end
    local it = a.it
    local how = it.bop and ns.L("自己做", "craft it yourself") or ns.L("找人做 / 拍卖行", "crafter / AH")
    return ns.L("也可以：", "Also: ") .. ns.ItemNm(it) .. ns.L("（", " (") .. profName(it.pf) .. " " .. (it.sk or 0) .. " · " .. how
        .. (a.pct and (ns.L("，+", ", +") .. a.pct .. "%") or "") .. ns.L("）", ")")
end

-- 11-23 用户拍板「按推荐、全球数据」：60 级起按 BisData.lua（scripts/gi_forever_bis_wcl.py）推荐，每格前 5：
--   WCL 实测（这一专精这一格 ≥ 10 人在穿，按人数排）> 11-20 wowtbc.gg 人工清单 > 权重推算；第 1 名 = 推荐件，悬停列前 5（使用率 · 人数 · 来源）。
--   专精：插件天赋键 → WCL 专精（BisData.map；猎人 / 盗贼 / 法师 / 术士「通用」和牧师「治疗」按点数最多的系挑，看别的职业用 d）。
--   前 5 里的物品插件掉落池有就复用池里那条（副本 / 任务 / 商人的点击照旧），制造表里有的当制造件（点击给制作信息），
--   都没有的做一条 src = "bis" 的条目（how = drop / craft / quest / rep / world / vendor，srcName = 来源）。
--   ⛔ 网站导出 gi_forever_web_export.py 读同一个文件、同一条规则（三端一致），改一边必须改另一边
local CUR_KEYS = { head = "head", neck = "neck", shoulder = "shoulder", back = "back", chest = "chest", wrist = "wrist", hands = "hands",
    waist = "waist", legs = "legs", feet = "feet", finger1 = "finger", finger2 = "finger", trinket1 = "trinket", trinket2 = "trinket",
    main = "main", off = "off", ranged = "ranged" }
local BIS_SLOT_CN = { head = "头部", neck = "颈部", shoulder = "肩部", back = "背部", chest = "胸部", wrist = "手腕", hands = "手",
    waist = "腰部", legs = "腿部", feet = "脚", finger = "手指", trinket = "饰品", main = "武器", off = "副手", ranged = "远程" }
local BIS_HOW = { drop = { "副本掉落", "Dungeon drop" }, craft = { "制造", "Crafted" }, quest = { "任务", "Quest" },
    rep = { "声望", "Reputation" }, world = { "野外 / 世界掉落", "World" }, vendor = { "商人", "Vendor" } }
local BIS_SRC = { w = "wcl", c = "curated", k = "calc" }
local BIS_CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }   -- 别的职业池按固定顺序找（网站导出同一条）
ns.BisHowText = function(how) local t = BIS_HOW[how or ""]; return t and ns.L(t[1], t[2]) or "" end
-- 按 \t 拆（空段保留）
local function splitTab(s)
    local out, p = {}, 1
    while true do
        local q = string.find(s, "\t", p, true)
        if not q then out[#out + 1] = s:sub(p); return out end
        out[#out + 1] = s:sub(p, q - 1); p = q + 1
    end
end
local bisSrcC, bisItC, bisSpC = {}, {}, {}
-- BisData.d 是一个长字符串，每行一条记录：按行首前缀明文找到那一行（"I12345\t" / "R7\t" / "S\tRogue/Combat\t"），返回前缀后面的部分
local function bisLine(prefix)
    local d = ns.BisData and ns.BisData.d
    if type(d) ~= "string" then return nil end
    local p = string.find(d, "\n" .. prefix, 1, true)
    if not p then return nil end
    local q = string.find(d, "\n", p + 1, true) or (#d + 1)
    return d:sub(p + 1 + #prefix, q - 1)
end
local function bisSource(i)
    local c = bisSrcC[i]
    if not c then
        local f = splitTab(bisLine("R" .. i .. "\t") or "world\t\t")
        c = { how = f[1], s = f[2] or "", sEn = f[3] or "" }
        bisSrcC[i] = c
    end
    return c
end
-- 某件物品的来源 + 显示信息（池外物品才有名字 / 图标…）
local function bisItem(id)
    local c = bisItC[id]
    if c then return c end
    local raw = id and bisLine("I" .. id .. "\t")
    if not raw then return nil end
    local f = splitTab(raw)
    local s = bisSource(tonumber(f[1]) or 0)
    local fl = f[2] or ""
    c = { id = id, how = s.how, s = s.s, sEn = s.sEn, n = f[3] or "", nEn = f[4] or "", i = f[5] or "", ilvl = tonumber(f[6]) or 0,
        req = tonumber(f[7]) or 0, q = (f[8] and f[8] ~= "") and f[8] or "q3", slot = f[9] or "",
        two = string.find(fl, "2", 1, true) ~= nil, uniq = string.find(fl, "u", 1, true) ~= nil }
    bisItC[id] = c
    return c
end
ns.BisItemInfo = bisItem
-- 一个 WCL 专精（"Rogue/Combat"）→ { n = 样本, zh, full, lv, head = { {id, pct, cnt, src, rank}… }… }，第一次用到才拆；pct = 人数 / 样本（一位小数）
local function bisSpec(full)
    local c = bisSpC[full]
    if c then return c end
    local raw = bisLine("S\t" .. full .. "\t")
    if not raw then return nil end
    local f = splitTab(raw)
    local n = tonumber(f[1]) or 0
    c = { n = n, zh = f[2] or "", full = full, lv = ns.BisData.lv or 60 }
    for k = 3, #f do
        local key, body = string.match(f[k], "^(%a+)=(.*)$")
        if key and BIS_SLOT_CN[key] then
            local lst = {}
            for id, cnt, src in string.gmatch(body, "(%d+),(%d+),(%a)") do
                cnt = tonumber(cnt)
                lst[#lst + 1] = { id = tonumber(id), cnt = cnt, pct = n > 0 and math.floor(cnt * 1000 / n + 0.5) / 10 or 0,
                    src = BIS_SRC[src] or src, rank = #lst + 1 }
            end
            c[key] = lst
        end
    end
    for key in pairs(BIS_SLOT_CN) do c[key] = c[key] or {} end
    bisSpC[full] = c
    return c
end
-- 插件天赋键 → WCL 专精名（"Combat"）
local function bisWclSpec(cls, spec)
    local B = ns.BisData
    local m = B and B.map and B.map[cls]
    if not m then return nil end
    local v = spec and m[spec]
    if v == nil then
        local SG = ns.SpecGear
        local first = SG and SG.Available() and SG.Specs(cls)[1]
        v = first and m[first.k]
    end
    if type(v) == "table" then
        if cls == myClass() and ns.MyMainTree then
            local ok, t = pcall(ns.MyMainTree)
            if ok and t and v[t] then return v[t] end
        end
        return v.d
    end
    return v
end
local function bisFor(cls, spec, lv)
    local B = ns.BisData
    if not B or (lv or 0) < (B.lv or 60) then return nil end
    local w = bisWclSpec(cls, spec)
    return w and bisSpec(cls .. "/" .. w)
end
ns.PlanBisFor = bisFor
-- 11-23 用户「60 bis有排名的展示，专精，WCL排名第几」：任何地方鼠标指装备（背包 / 聊天链接 / 掉落 / 观察…），这件在任一专精的 60 级 BiS 前 5 里
--   → 加一行「GI 60 级 BiS：射击猎 远程 第2 18%，生存猎 远程 第1 25%」：本职业的专精排前面、金色；再按名次、使用率排；最多 3 个，其余写「等 N 个专精」。
--   ⛔ 不另存反查表：BisData.d 里 S 行就是「=id,人数,来源」「;id,人数,来源」，第一次指到某件时明文找一遍（约 0.1 ms），结果按物品缓存成一串字；
--   合并包（发版默认）BisData 登录就在内存里 → 0 额外数据；拆分包只在 _Plan 已加载时显示（不为一行提示 LoadAddOn _Plan，那要 +590 KB）。
--   使用率只给 WCL 实测件（人工清单 / 推算件只写名次）；网站对照：scripts/gi_forever_bis_wcl.py 的 reverse_index（测试逐件比）
do
    local CLS_ZH = { Warrior = "战", Paladin = "骑", Hunter = "猎", Rogue = "贼", Priest = "牧", Shaman = "萨", Mage = "法", Warlock = "术", Druid = "德" }
    local SHORT = { ["野兽控制"] = "兽王", ["恶魔学识"] = "恶魔" }
    local tipC, tipN, rows = {}, 0, nil
    -- 物品 → { { cls, ws, zh, slot, rank, pct }… }（同一专精多格取最好名次）；不在任何前 5 → 空表；没有 BisData → nil
    local function find(id)
        local d = ns.BisData and ns.BisData.d
        id = tonumber(id)
        if type(d) ~= "string" or not id then return nil end
        if not rows or rows.d ~= d then   -- S 行：{ 起, 止, 职业, WCL 专精, 样本, 中文专精 }（28 条，第一次用到才建）
            rows = { d = d }
            for a, cls, ws, n, zh, e in string.gmatch(d, "\n()S\t(%a+)/(%a+)\t(%d+)\t([^\t]*)[^\n]*()") do rows[#rows + 1] = { a, e, cls, ws, tonumber(n), zh } end
        end
        local out, key, p, lastR = {}, id .. ",", 1, nil
        while true do
            local a = string.find(d, key, p, true)
            if not a then break end
            p = a + 1
            local b = string.byte(d, a - 1)
            if b == 61 or b == 59 then   -- 前一个字是「=」或「;」= 物品编号（不是人数里的一截）
                local r
                for _, x in ipairs(rows) do if a > x[1] and a < x[2] then r = x; break end end
                if not r then break end   -- S 行都在 I / R 行前面
                local t, u, rank = r[1], nil, 1
                while true do u = string.find(d, "\t", t, true); if not u or u > a then break end; t = u + 1 end
                u = t
                while true do u = string.find(d, ";", u, true); if not u or u > a then break end; rank = rank + 1; u = u + 1 end
                local slot = string.match(d, "^(%a+)=", t)
                local cnt, src = string.match(d, "^%d+,(%d+),(%a)", a)
                if slot and cnt then
                    local e = { cls = r[3], ws = r[4], zh = r[6], slot = slot, rank = rank, pct = src == "w" and r[5] > 0 and math.floor(cnt * 100 / r[5] + 0.5) or nil }
                    if lastR ~= r then out[#out + 1] = e; lastR = r elseif rank < out[#out].rank then out[#out] = e end
                end
            end
        end
        return out
    end
    ns._BisTipFind = find   -- 测试用
    -- 排序（本职业在前 → 名次 → 使用率，没有使用率的排后）+ 拼一行
    local function build(id)
        local lst = find(id)
        if not lst or #lst == 0 then return nil end
        local me = myClass()
        table.sort(lst, function(x, y)
            if (x.cls == me) ~= (y.cls == me) then return x.cls == me end
            if x.rank ~= y.rank then return x.rank < y.rank end
            if (x.pct or -1) ~= (y.pct or -1) then return (x.pct or -1) > (y.pct or -1) end
            return x.cls .. x.ws < y.cls .. y.ws
        end)
        local parts = {}
        for i = 1, math.min(3, #lst) do
            local e = lst[i]
            parts[i] = (e.cls == me and "|cffffd100" or "|cffc0c0c0") .. ns.L((SHORT[e.zh] or e.zh) .. (CLS_ZH[e.cls] or "") .. " " .. (BIS_SLOT_CN[e.slot] or e.slot) .. " 第",
                e.ws .. " " .. e.cls .. " " .. e.slot .. " #") .. e.rank .. (e.pct and (" " .. e.pct .. "%") or "") .. "|r"
        end
        return "|cff33ff99GI|r " .. ns.L("60 级 BiS：", "Lv60 BiS: ") .. table.concat(parts, ns.L("，", ", "))
            .. (#lst > 3 and ns.L("  等 " .. (#lst - 3) .. " 个专精", "  +" .. (#lst - 3) .. " specs") or "")
    end
    ns._BisTipText = build   -- 测试用
    local function clear(self) self.__gifBis = nil end
    local function add(tt, id)
        if not tt or not id or tt.__gifBis == id or not tt.AddLine then return end
        if ns.db and ns.db.ui and ns.db.ui.bisTip == false then return end   -- 11-24 GI-348 关掉（设置 → 装备 → 推荐装备「物品提示里的 60 级 BiS 排名」）
        if not tt.__gifBisHk and tt.HookScript then tt.__gifBisHk = true; tt:HookScript("OnTooltipCleared", clear) end
        local s = tipC[id]
        if s == nil then
            if tipN >= 400 then tipC, tipN = {}, 0 end   -- 只缓存最近指过的 400 件
            s = build(id) or false
            tipC[id], tipN = s, tipN + 1
        end
        if not s then return end
        tt.__gifBis = id
        tt:AddLine(s, 1, 0.82, 0.4, true)
        tt:Show()
    end
    ns._BisTipAdd = add   -- 测试用
    local function hook()
        if ns._bisTipHooked then return end
        ns._bisTipHooked = true
        local TDP, T = TooltipDataProcessor, Enum and Enum.TooltipDataType
        if TDP and TDP.AddTooltipPostCall and T and T.Item then
            TDP.AddTooltipPostCall(T.Item, function(tt, data)
                local id = data and data.id
                if id and not ns.Secret(id) then pcall(add, tt, id) end
            end)
            return
        end
        for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
            if tt and tt.HookScript and tt:HasScript("OnTooltipSetItem") then
                tt:HookScript("OnTooltipSetItem", function(self)
                    local _, link = self:GetItem()
                    if link and not ns.Secret(link) then pcall(add, self, tonumber(link:match("item:(%d+)"))) end
                end)
            end
        end
    end
    -- 拆分包：_Plan 是登录后才加载的（存档已读好）→ 当场挂；合并包：文件在 ADDON_LOADED 之前执行 → 排进 ns.modules（排在 LootTip 等后面，行序不变）
    if ns.db then pcall(hook) else table.insert(ns.modules, function() pcall(hook) end) end
end
-- 没中文名的（无限新物品）：取客户端名字（GetItemInfo，第一次可能还没缓存 → 先用英文，物品数据到了页面会重画）
local function curName(e)
    local info = bisItem(e.id) or {}
    if info.n and info.n ~= "" then return ns.ItemNmId(e.id, info.n, info.nEn) end
    local a = ns.ItemNameRaw and ns.ItemNameRaw(e.id)
    local nm = a or (GetItemInfo and GetItemInfo(e.id))
    if nm then return nm end
    for _, cl in ipairs(BIS_CLASSES) do
        for _, it in ipairs((ns.Data.gear or {})[cl] or {}) do if it.id == e.id then return ns.ItemNm(it) end end
    end
    return (info.nEn and info.nEn ~= "" and info.nEn) or ("#" .. e.id)
end
ns.BisCuratedName = curName
-- 来源短写（格子第二行）：「声望：塞拉摩远征军 崇拜」→「声望」、「荆棘谷 · 某 NPC」→「荆棘谷」。⛔ 按分隔符明文找，别用 [^…] 字符集（中文多字节会被拆）
local function curShortSrc(s)
    s = s or ""
    local cut = #s + 1
    for _, sep in ipairs({ "：", ": ", " · ", "（", " (" }) do
        local p = string.find(s, sep, 1, true)
        if p and p < cut then cut = p end
    end
    return s:sub(1, cut - 1)
end
local poolById, anyById, curMade = {}, nil, {}
local function curItem(cls, e, key)
    local idx = poolById[cls]
    if not idx then
        idx = {}
        for _, it in ipairs((ns.Data.gear or {})[cls] or {}) do if not idx[it.id] then idx[it.id] = it end end
        poolById[cls] = idx
    end
    if idx[e.id] then return idx[e.id] end
    local c = curMade[e.id]
    if c then
        if not c.n or c.n == "" then c.n = (GetItemInfo and GetItemInfo(e.id)) or nil end
        return c
    end
    if not anyById then   -- 别的职业池里的（项链 / 戒指 / 饰品 / 武器常见）+ 制造表
        anyById = {}
        for _, cl in ipairs(BIS_CLASSES) do
            for _, it in ipairs((ns.Data.gear or {})[cl] or {}) do if not anyById[it.id] then anyById[it.id] = it end end
        end
        local gc = ns.Data.gearCraft
        for _, it in ipairs(gc and gc.items or {}) do if not anyById[it.id] then anyById[it.id] = it end end
    end
    local info = bisItem(e.id) or { how = "world", s = "", sEn = "", n = "", nEn = "", i = "", ilvl = 0, req = 0, q = "q3", slot = "" }
    local a = anyById[e.id]
    if a then
        c = {}
        for k, v in pairs(a) do c[k] = v end
        if a.pf then c.src = "craft" end   -- 制造表那条没有 src
    else
        c = { id = e.id, nEn = info.nEn, i = info.i, ilvl = info.ilvl, req = info.req, q = info.q, slot = (info.slot ~= "" and info.slot) or BIS_SLOT_CN[key] or "",
            type = "", src = "bis", srcName = ns.L(info.s, info.sEn), how = info.how, two = info.two }
        c.n = (info.n ~= "" and info.n) or (GetItemInfo and GetItemInfo(e.id)) or nil
    end
    curMade[e.id] = c
    return c
end
-- 套到 out 上：戒指 / 饰品两格分第 1、2 名；主手是双手就不推副手；副手第 1 名和主手同一件且唯一装备 → 顺延
local function applyCurated(cur, cls, out)
    local function nth(key, n, skipId)
        local k = 0
        for _, e in ipairs(cur[key] or {}) do
            if e.id ~= skipId then k = k + 1; if k == n then return curItem(cls, e, key) end end
        end
    end
    local new = {}
    for slot, key in pairs(CUR_KEYS) do
        if slot ~= "off" then new[slot] = nth(key, (slot == "finger2" or slot == "trinket2") and 2 or 1) or out[slot] end
    end
    local m = new.main
    local mi = m and bisItem(m.id)
    new.off = nth("off", 1, (m and mi and mi.uniq) and m.id or nil) or out.off
    if m and (m.two or (mi and mi.two)) then new.off = nil end
    return new
end
-- 某格的前 5（槽位键 → 条目列表）；没有数据 / 不到 60 级返回 nil
ns.PlanCuratedTop = function(lv, cls, spec, slot)
    local cur = bisFor(cls or myClass(), spec, lv)
    return cur and cur[CUR_KEYS[slot] or slot], cur
end
-- 悬停一行的右半：「使用率 23% · 284 人」；人工清单 / 推算的写「人工清单」「属性推算」（WCL 也有人穿就带上人数）
local function bisStatText(e)
    local info = bisItem(e.id) or {}
    local parts = {}
    if (e.cnt or 0) > 0 then
        local p = e.pct or 0
        parts[#parts + 1] = string.format(ns.L("使用率 %s%% · %d 人", "%s%% used · %d players"), (p == math.floor(p)) and tostring(math.floor(p)) or tostring(p), e.cnt)
    end
    if e.src == "curated" then parts[#parts + 1] = ns.L("人工清单", "curated list")
    elseif e.src == "calc" then parts[#parts + 1] = ns.L("属性推算", "stat weights") end
    if #parts == 0 then parts[1] = ns.BisHowText(info.how) end
    return table.concat(parts, " · ")
end
ns.BisStatText = bisStatText
-- 来源全文：「副本：黑石深渊 · 小怪」「声望：塞拉摩远征军 崇拜」「任务：…」「商人 · …」「野外：荆棘谷 · …」「世界掉落」
local function bisSrcText(how, s, sEn)
    local t = ns.L(s or "", sEn or "")
    if t == "" then return ns.BisHowText(how) end
    if how == "drop" then return ns.L("副本：", "Dungeon: ") .. t end
    if how == "world" then
        for _, pre in ipairs({ "世界", "野外", "来源", "World", "Source" }) do
            if t:sub(1, #pre) == pre then return t end
        end
        return ns.L("野外：", "World: ") .. t
    end
    return t
end
ns.BisSrcText = bisSrcText

local DW_CLASS = { Warrior = true, Rogue = true, Hunter = true }   -- 没天赋数据时按职业：经典旧世只有这三个职业能学双持
local function bestGearBySlot(targetLv, cls, spec, profs)
    cls = cls or myClass()
    if profs == nil then profs = (cls == myClass()) and playerProfs() or {} end
    local SG = ns.SpecGear
    if SG and SG.Available() then spec = spec or SG.Current(cls) else spec = nil end
    local pool = {}
    local score = {}
    for _, it in ipairs((ns.Data.gear or {})[cls] or {}) do
        local req = (it.req and it.req > 0) and it.req or (it.min or 0)
        -- 10-18 用户「推荐只用确认掉过的和服务器有的」：有 ItemRecommendIds（ItemMissingData.lua，HOLD）就只从里面挑
        --   11-06 商人件不走这张名单（生成时已按规则筛过）；制造件不在 gear 里（备选另算，见 craftAlts）
        local allowT = ns.ItemRecommendIds
        if req <= targetLv and not (targetLv < 40 and it.type == ARMOR_AT40[cls]) and not (SG and SG.Missing(it.id))
            and (it.src == "vendor" or not (SG and allowT) or allowT[it.id]) then
            pool[it.slot] = pool[it.slot] or {}
            table.insert(pool[it.slot], it)
            if spec and score[it] == nil then score[it] = SG.Score(it.id, it.slot, cls, spec, targetLv) or false end
        end
    end
    -- ⛔ 10-08：装等相同时按物品 ID 定死先后（Lua 排序不稳定，平手会随机挑；网站 / 小程序读的导出结果要和这里逐件一致）
    --   有分数的排在没分数的前面（没属性数据的只能按装等猜，不该压过算得出分的）
    for _, lst in pairs(pool) do table.sort(lst, function(a, b)
        if spec then
            local sa, sb = score[a], score[b]
            if (sa and true or false) ~= (sb and true or false) then return sa and true or false end
            if sa and sb and math.abs(sa - sb) > 1e-6 then return sa > sb end
        end
        if (a.ilvl or 0) ~= (b.ilvl or 0) then return (a.ilvl or 0) > (b.ilvl or 0) end
        if (a.id or 0) ~= (b.id or 0) then return (a.id or 0) < (b.id or 0) end
        return (a.srcName or "") < (b.srcName or "")   -- 同一件多个首领都掉：按来源名定死
    end) end
    local function pick(slotCn, skipId, filter)
        for _, it in ipairs(pool[slotCn] or {}) do if it.id ~= skipId and (not filter or filter(it)) then return it end end
    end
    local out = {}
    for _, grp in ipairs({ GEAR_LEFT, GEAR_RIGHT }) do
        for _, g in ipairs(grp) do
            if g[2] then
                if g[1] == "finger2" then out.finger2 = pick("手指", out.finger1 and out.finger1.id)
                elseif g[1] == "trinket2" then out.trinket2 = pick("饰品", out.trinket1 and out.trinket1.id)
                else out[g[1]] = pick(g[2]) end
            end
        end
    end
    -- 11-24 GI-308/323/327/331：副手专用武器（部位「副手」、类型拳套 / 匕首 / 剑…）只有能双持的专精装得上；萨满 / 圣骑 / 德鲁伊…只挑盾牌 / 副手物品
    local dw = spec and SG.DualWield(cls, spec) or (not spec and DW_CLASS[cls])
    local function offOk(it) return dw or it.type == nil or it.type == "" or it.type == "盾牌" end
    if spec then
        -- 双手 vs 单手 + 副手：两种组合比总分（双持职业副手 = 第二把单手武器）
        local function sc(it) return it and score[it] or 0 end
        local two = pick("武器", nil, function(it) return it.two end)
        local one = pick("武器", nil, function(it) return not it.two end)
        local off, offS = nil, 0
        if one then
            if SG.DualWield(cls, spec) then
                -- 双持：副手挑第二把单手武器，秒伤按一半算（按「副手」打分）；没分数的不挑
                for _, it in ipairs(pool["武器"] or {}) do
                    if not it.two and it.id ~= one.id then
                        local s = SG.Score(it.id, "副手", cls, spec, targetLv)
                        if s and (not off or s > offS + 1e-6) then off, offS = it, s end
                    end
                end
            end
            local oh = pick("副手", nil, offOk)
            if oh and (not off or sc(oh) > offS + 1e-6) then off, offS = oh, sc(oh) end
        end
        -- 平手（差 ≤ 1e-6，两边求和顺序不同会差在最后一位）算双手：和网站导出同一条
        if two and (SG.TwoHand(cls, spec) or not one or sc(two) >= sc(one) + offS - 1e-6) then out.main, out.off = two, nil
        else out.main, out.off = one, off end
        if not out.main then out.off = pick("副手", nil, offOk) end   -- 一把武器都没有：副手照样推荐
    else
        out.main = pick("武器")
        out.off = not (out.main and out.main.two) and pick("副手", nil, offOk) or nil
    end
    out.ranged = pick("远程")
    local cur = bisFor(cls, spec, targetLv)
    if cur then return applyCurated(cur, cls, out), spec, {}, cur end   -- 前 5 里已经含制造件，不再出「也可以」备选
    return out, spec, craftAlts(targetLv, cls, spec, profs, out)
end
-- 测试 / 导出对拍用：某职业某一级每格选哪件（槽位键 → 物品 ID）。网站 / 小程序读 gear.json 里同一份结果（gi_forever_web_export.py）
--   主推荐不看专业；profs 只影响备选（不传 = 看自己职业读角色专业）
ns.PlanBestGear = function(lv, cls, spec, profs)
    local r = {}
    for k, it in pairs((bestGearBySlot(lv, cls, spec, profs))) do if type(it) == "table" then r[k] = it.id end end
    return r
end
-- 备选对拍用：{ 槽位键 = { id, pct } }（网站 altBySpec / altByProf 同一份）
ns.PlanCraftAlts = function(lv, cls, spec, profs)
    local _, _, alts = bestGearBySlot(lv, cls, spec, profs)
    local r = {}
    for k, a in pairs(alts or {}) do r[k] = { id = a.it.id, pct = a.pct } end
    return r
end
-- 11-06 角色面板 BiS 角标（BisCorner.lua，HOLD）：同一套挑法，返回整条候选（名字 / 图标 / 来源）+ 用的天赋
ns.PlanBestGearItems = function(lv, cls, spec, profs) return bestGearBySlot(lv, cls, spec, profs) end

-- ---------- 任务链弹窗 ----------
local qPop
local function buildQuestPop(parent)
    local f = CreateFrame("Frame", "GearInsightForeverQuestPop", parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -64)
    f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    f:SetFrameLevel(parent:GetFrameLevel() + 20)
    f:EnableMouse(true)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.04, 0.04, 0.07, 0.97)
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 14, -12); f.title:SetPoint("RIGHT", -34, 0); f.title:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)   -- 10-18 战斗中关不掉：原生红叉走 HideUIPanel，战斗中被拦 → 直接 Hide
    local sf, c = ns.Scroll(f, 10, -40, 600, 330)
    f.child = c
    f:Hide()
    return f
end

-- 一个变体（某个出生地起点）的任务链 → 一段纵向文字，编号 1/N
local function variantText(v)
    local lines = { "|cff888888" .. ns.L("出生地：", "Starting area: ") .. (v.zone ~= "" and v.zone or "?") .. "|r" }
    for i, q in ipairs(v.q) do
        local giver = q.g[1]
        lines[#lines + 1] = string.format("|cffffd100%d/%d|r  |cffffffff%s|r  |cff888888Lv.%d%s|r",
            i, #v.q, q.t, q.lv, giver and ("  " .. giver.n .. " @ " .. giver.z) or "")
        if q.o ~= "" then lines[#lines + 1] = "    |cffcccccc" .. ns.EnSafe(q.o) .. "|r" end
    end
    return table.concat(lines, "\n")
end

local function showQuestPop(spellName)
    qPop = qPop or buildQuestPop(page)
    local cls = myClass()
    local info = ((ns.Data.questSeries or {})[cls] or {})[spellName]
    qPop.title:SetText("|cff33ff99" .. ns.L("任务链：", "Quest chain: ") .. "|r" .. spellName)
    if not info or #info.variants == 0 then
        qPop.child:SetHeight(1)
        local t = qPop.child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        t:SetPoint("TOPLEFT", 4, -4); t:SetText(ns.L("没有收到这条任务链的数据", "No quest chain data for this one yet"))
        qPop:Show(); return
    end
    local y = -2
    if not qPop.texts then qPop.texts = {} end
    for _, t in ipairs(qPop.texts) do t:Hide() end
    for vi, v in ipairs(info.variants) do
        local t = qPop.texts[vi]
        if not t then
            t = qPop.child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            t:SetPoint("LEFT", 4, 0); t:SetWidth(580); t:SetJustifyH("LEFT"); t:SetSpacing(3)
            qPop.texts[vi] = t
        end
        local hd = #info.variants > 1 and (ns.L("方案 ", "Path ") .. vi .. "/" .. #info.variants .. "\n") or ""
        t:SetText(ns.EnSafe(hd .. variantText(v)))
        t:ClearAllPoints(); t:SetPoint("TOPLEFT", 4, y); t:SetWidth(580)
        t:Show()
        y = y - t:GetStringHeight() - 14
    end
    qPop.child:SetHeight(-y + 6)
    qPop:Show()
end

-- ---------- 时间轴行 ----------
-- ⛔ 10-07 用户「调到多少级都是空的」：行以前只锚了 TOPLEFT + 高度、没有宽度 → 游戏里宽 0 的框体整行不画，
--   列表从 0.3.0 起在游戏里就一直是空的（离线测试不算布局，测不出来）。行必须同时锚到 page.child 的 RIGHT。
-- 任务线（睡袋）/ 门任务那一行怎么画（11-23 从主插件 SideChains.lua 搬来，内核净减）：左键 = 路线弹框（_Gate 里，点了才加载），右键 = 钉到界面追踪 / 取消
local function chainRow(r, it, suffix)
    local c, SC = it.c, ns.SideChains
    local gate = c.gate
    r.ic:SetTexture("Interface\\Icons\\" .. (c.icon or (gate and "INV_Misc_Key_14" or "INV_Misc_Note_01")))
    r.ic:SetDesaturated(it.st == "done")
    local head = gate and ns.L("门任务：", "Gate quest: ") or ns.L("任务线：", "Quest line: ")
    r.t:SetText((it.st == "done" and "|cff808080" or "|cffff9933") .. head .. ns.L(c.t, c.tEn) .. "|r"
        .. ((c.hint or it.total == 0) and "" or ("  |cff888888" .. string.format("%d/%d", it.n, it.total) .. "|r")))
    local sub = ns.L(c.gist, c.gistEn)
    if gate then
        local fac = SC.Faction()
        local steps = c.steps and c.steps[fac]
        local _, _, _, nextI = SC.Progress(c, fac)
        sub = ns.L("开", "Opens ") .. ns.L(c.door, c.doorEn) .. ((c.optFac and c.optFac[fac]) and ns.L("（可选）", " (optional)") or "")
            .. ((it.st ~= "done" and steps and nextI and steps[nextI]) and (" · " .. ns.L("下一步：", "Next: ") .. ns.L(steps[nextI].obj, steps[nextI].objEn)) or "")
        if ns.GateOpensText and ns.GateOpensText(c) then sub = sub .. " · " .. ns.GateOpensText(c) end
        if SC.KeyMissing and SC.KeyMissing(c, fac) then sub = sub .. " · |cffff7f50" .. ns.L("任务做完了但身上没钥匙", "done, but the key isn't on you") .. "|r" end
    end
    r.s:SetText(ns.EnSafe(sub) .. (suffix or ""))
    if r.RegisterForClicks then pcall(r.RegisterForClicks, r, "LeftButtonUp", "RightButtonUp") end
    r:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" and not c.hint then   -- 11-07 右键 = 钉到界面追踪 / 取消
            local on = SC.TogglePin(c)
            if ns.Print then ns.Print(on and ns.L("已钉到界面上追踪（右键再点取消）", "Tracker pinned") or ns.L("已取消追踪", "Tracker unpinned")) end
            return
        end
        SC.Show(c)
    end)
    r.btn:SetText(ns.L("路线", "Route")); r.btn:Show()
    r.btn:SetScript("OnClick", function() SC.Show(c) end)
    r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.L(c.t, c.tEn), 1, 0.82, 0)
        GameTooltip:AddLine(ns.L(c.gist, c.gistEn), 1, 1, 1, true)
        if not c.hint then
            GameTooltip:AddLine(string.format(ns.L("已做 %d / %d 步 · 点击看逐步路线和坐标", "%d / %d steps done · click for the route"), it.n, it.total), 0.6, 0.6, 0.6, true)
            GameTooltip:AddLine(ns.L("右键：钉到界面上追踪 / 取消", "Right-click: pin / unpin the tracker"), 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
end
ns.SideChainRenderRow = chainRow

local function getRow(p, i)
    local r = p.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, p.child)
    r.lvTag = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.lvTag:SetPoint("TOPLEFT", 2, -2); r.lvTag:SetWidth(48); r.lvTag:SetJustifyH("LEFT")
    r.ic = r:CreateTexture(nil, "ARTWORK"); r.ic:SetSize(26, 26); r.ic:SetPoint("TOPLEFT", 52, 0)
    r.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.t:SetPoint("TOPLEFT", 84, -3); r.t:SetPoint("RIGHT", -92, 0); r.t:SetJustifyH("LEFT"); r.t:SetWordWrap(false)
    r.s = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.s:SetPoint("TOPLEFT", 84, -20); r.s:SetPoint("RIGHT", -92, 0); r.s:SetJustifyH("LEFT"); r.s:SetWordWrap(false)
    r.s:SetTextColor(0.65, 0.65, 0.65)
    r.btn = ns.Button(r, "", 80, 22); r.btn:SetPoint("RIGHT", -2, 0)
    -- 10-16 用户「弄个加号标志，让可点击展开效果更明显」：折叠行图标左边的 + / -
    r.pm = r:CreateTexture(nil, "OVERLAY"); r.pm:SetSize(18, 18); r.pm:SetPoint("RIGHT", r.ic, "LEFT", -6, 0); r.pm:Hide()
    -- 10-12 用户截图「每一级在 UI 不突出」：等级分组标题改成整行色带 —— 底色条 + 左侧粗色边 + 大号等级数字 + 本级几项
    r.band = r:CreateTexture(nil, "BACKGROUND"); r.band:SetPoint("TOPLEFT", 0, -2); r.band:SetPoint("BOTTOMRIGHT", 0, 2)
    r.bandAcc = r:CreateTexture(nil, "BORDER"); r.bandAcc:SetWidth(4)
    r.bandAcc:SetPoint("TOPLEFT", 0, -2); r.bandAcc:SetPoint("BOTTOMLEFT", 0, 2)
    r.bandLine = r:CreateTexture(nil, "BORDER"); r.bandLine:SetHeight(1)
    r.bandLine:SetPoint("BOTTOMLEFT", 0, 2); r.bandLine:SetPoint("BOTTOMRIGHT", 0, 2)
    r.big = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    r.big:SetPoint("LEFT", 12, 0); r.big:SetJustifyH("LEFT")
    r.bandR = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.bandR:SetPoint("RIGHT", -10, 0); r.bandR:SetJustifyH("RIGHT")
    for _, x in ipairs({ r.band, r.bandAcc, r.bandLine, r.big, r.bandR }) do x:Hide() end
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.05)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.rows[i] = r
    return r
end

local function refreshHeader()
    local lo, hi = range()
    local cur = curLv()
    if page.rangeBar then page.rangeBar:SetValues(lo, hi) end
    page.sortBtn:SetText(ns.db.ui.planDesc and ns.L("从高到低", "High to low") or ns.L("从低到高", "Low to high"))
    page.doneBtn:SetText(ns.db.ui.planHideDone and ns.L("显示已完成", "Show done") or ns.L("隐藏已完成", "Hide done"))
    -- ⛔ 不用「–」「→」这类符号：游戏中文字体会显示成方框，用「至」
    page.baseTxt:SetText(ns.L("你 ", "Lv ") .. "|cffffd100" .. cur .. "|r" .. ns.L(" 级 · 看 ", " · ")
        .. "|cffffd100" .. lo .. "|r" .. ns.L(" 至 ", "-") .. "|cffffd100" .. hi .. "|r")
    page.baseFull = ns.L("你现在 ", "You are level ") .. cur .. ns.L(" 级，列表显示 ", "; showing levels ") .. lo .. ns.L(" 至 ", " to ") .. hi
        .. ns.L(" 级", "")
    return lo, hi
end

local STATE_TXT = ns.LateL({   -- 11-09 GI-202：手动切语言后跟着换
    done = { "|cff808080", ns.L("已学 / 已过", "done") },
    missed = { "|cffff4040", ns.L("漏学", "missed") },
    now = { "|cff33ff99", ns.L("现在就能做", "do it now") },
})

local trainOpen = {}   -- 10-16 训练师折叠组：哪几级展开着（只在本次登录内记）
local refresh   -- 前向声明：时间轴里「导入宏」点完要刷新，refresh 定义在下面（10-07 静态检查查出：原来调的是全局 nil）
local function refreshTimeline(lo, hi)
    for _, r in ipairs(page.rows) do r:Hide() end   -- 先隐藏旧行，buildItems 万一中途出错也不留一屏上次的内容
    local items, err, cur = buildItems(lo, hi, ns.db.ui.planDesc)
    if (page.hiddenDone or 0) > 0 then
        page.baseFull = (page.baseFull or "") .. ns.L("，已隐藏 ", "; hidden ") .. page.hiddenDone .. ns.L(" 项已完成", " done")
    end
    local y, n, curY = 0, 0, nil
    -- ⛔ 行要从 1 开始复用：以前用 #page.rows + 1，每刷新一次就新建一整批行，越点越多
    local function nextRow() n = n + 1; return getRow(page, n) end
    local function place(r, h)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, y); r:SetPoint("RIGHT", page.child, "RIGHT", 0, 0); r:SetHeight(h)
        r:SetScript("OnClick", nil); r:SetScript("OnEnter", nil)   -- 这一行可能是别的行复用来的，清掉上一次的脚本
        r.btn:Hide(); r.btn:SetScript("OnEnter", nil); r.btn:SetEnabled(true); r.lvTag:SetText(""); r.pm:Hide()
        for _, x in ipairs({ r.band, r.bandAcc, r.bandLine, r.big, r.bandR }) do x:Hide() end   -- 等级色带只给标题行
    end
    local function warn(text)
        local r = nextRow(); place(r, 30)
        r.ic:Hide(); r.t:SetText("|cffff6060" .. text .. "|r"); r.s:SetText(""); r:Show()
        -- ⛔ 10-07 用户截图：提示太长被截成「…」，没悬停看不全 → 一律挂完整文字
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(text, 1, 0.4, 0.4, true); GameTooltip:Show()
        end)
        y = y - 32
    end
    -- 用的是默认升级加点：顶上一行金字说明来源，告诉怎么换成自己的（10-07 用户「每个职业先去网上找一套升级点的路线…作为默认」）
    local plan = ns.ActivePlan and ns.ActivePlan()
    if plan and plan.default and err ~= "conflict" then
        local r = nextRow(); place(r, 30)
        local txt = ns.L("天赋按默认升级加点：", "Talents follow the default leveling build: ") .. "|cffffd100" .. ns.L(plan.specCn or plan.spec or "", plan.spec or "") .. "|r"
            .. ns.L("（来源 ", " (source: ") .. (plan.src or "?") .. ns.L("）", ")")
        r.ic:Hide(); r.t:SetText(txt); r.s:SetText("|cff888888" .. ns.L("想换自己的：去「天赋」页导入配点码", "Use your own: import a build on the Talents page") .. "|r"); r:Show()
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(ns.L("默认升级加点", "Default leveling build"), 1, 0.82, 0)
            GameTooltip:AddLine(txt, 1, 1, 1, true)
            if plan.url then GameTooltip:AddLine(plan.url, 0.6, 0.8, 1, true) end
            if (plan.adjusted or 0) > 0 then
                GameTooltip:AddLine(string.format(ns.L("攻略写于 9 月，按《无限》Beta 当前天赋树调整了 %d 处（删掉的天赋 / 挪了行的提前补点解锁）",
                    "Written in September; %d adjustments for the current Beta talent trees"), plan.adjusted), 1, 0.82, 0.4, true)
            end
            GameTooltip:AddLine(ns.L("没导入配点码时自动用这套；在「天赋」页导入自己的码后，这里就按你的码排。",
                "Used when you haven't imported a build; import your own on the Talents page to replace it."), 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        y = y - 32
    end
    -- 11-23 门任务汇总条（到了最低门槛等级才出）：「门任务 3/7 已开 · 下一个：熔火之心调和」，点了 = 门任务清单弹框（GateList.lua，HOLD 没进包就没有）
    if ns.GateSummary and ns.GateListShow then
        local ok, txt = pcall(ns.GateSummary, cur)
        if ok and txt then
            local r = nextRow(); place(r, 30)
            r.ic:SetTexture("Interface\\Icons\\INV_Misc_Key_14"); r.ic:SetDesaturated(false); r.ic:Show()
            r.t:SetText("|cffff9933" .. txt .. "|r")
            r.s:SetText("|cff888888" .. ns.L("点击看本阵营全部门任务（进度 / 路线 / 钉追踪）", "Click for every gate quest of your faction") .. "|r"); r:Show()
            r:SetScript("OnClick", function() ns.GateListShow() end)
            r.btn:SetText(ns.L("清单", "List")); r.btn:Show(); r.btn:SetScript("OnClick", function() ns.GateListShow() end)
            page.gateSum = r
            y = y - 32
        end
    end
    -- 11-24 攒任务提醒行（ZoneQuestXp.lua 填内容 / 点开清单；HOLD 没进包就没有）
    page.turnIn = nil
    if ns.TurnInFill then
        local ok, txt = pcall(ns.TurnInSummary, cur)
        if ok and txt then local r = nextRow(); place(r, 30); ns.TurnInFill(r, txt); page.turnIn = r; y = y - 32 end
    end
    if err == "noplan" then
        warn(ns.L("还没有天赋计划：先去「天赋」页配好一套点、点「按这套逐点学」（技能 / 宏不受影响，照样往下看）", "No talent plan yet — import a build on the Talents page (skills and macros below still work)"))
    elseif err == "conflict" and plan and plan.default then
        warn(ns.L("你已点的天赋和默认升级加点不一样，天赋这部分先不显示：去「天赋」页导入你自己的配点码就能接着排（技能 / 宏不受影响）",
            "Your spent points differ from the default leveling build — import your own build on the Talents page (skills / macros unaffected)"))
    elseif err == "conflict" then
        warn(ns.L("当前已点的天赋和「天赋」页的计划对不上，天赋这部分先不显示（技能 / 宏不受影响）", "Your spent points don't match the Talents plan, so talent rows are hidden (skills / macros unaffected)"))
    end
    local lastLv
    local perLv = {}
    for _, it in ipairs(items) do
        if it.kind ~= "zone" and it.kind ~= "prof" then perLv[it.lv] = (perLv[it.lv] or 0) + 1 end   -- 地图 / 专业是提醒，不算待办数
    end
    -- 10-16 用户截图「这种搞一个按钮就行了，多了乱，一级之内的训练师合并一下做个折叠，折叠标题有按钮就行」：
    --   同一级里要去职业训练师那学的技能 ≥2 个 → 合成一行折叠标题（带「找训练师」），点标题展开 / 收起；展开的子行不再带按钮
    local function isTrainer(it) return it.kind == "spell" and not it.tal and not it.nt and not it.auto and not it.inGroup end
    local trN, trMiss = {}, {}
    for _, it in ipairs(items) do
        if isTrainer(it) then
            trN[it.lv] = (trN[it.lv] or 0) + 1
            if it.st == "missed" then trMiss[it.lv] = true end
        end
    end
    -- 有「漏学」的组默认展开（漏学要一眼看到）；手动点过就听手动的
    local function isOpen(lv) if trainOpen[lv] == nil then return trMiss[lv] == true end return trainOpen[lv] end
    do
        local merged, grp = {}, {}
        for _, it in ipairs(items) do
            if isTrainer(it) and trN[it.lv] >= 2 then
                local g = grp[it.lv]
                if not g then
                    g = { lv = it.lv, kind = "trainergrp", list = {} }
                    grp[it.lv] = g
                    merged[#merged + 1] = g
                end
                g.list[#g.list + 1] = it
                if isOpen(it.lv) then it.inGroup = true; merged[#merged + 1] = it end
            else
                merged[#merged + 1] = it
            end
        end
        items = merged
    end
    for _, it in ipairs(items) do
        if it.lv ~= lastLv then
            -- 每一级一个分组标题：整行色带 + 大号「第 N 级」+ 右侧「本级 N 项」；当前等级绿色带「你现在在这」，已过的等级灰一些
            local first = (lastLv == nil)
            lastLv = it.lv
            if not first then y = y - 8 end   -- 和上一级拉开距离
            local h = nextRow(); place(h, 30); h.ic:Hide(); h.s:SetText(""); h.t:SetText("")
            if it.lv == cur then curY = -y end
            local here, past = (it.lv == cur), (it.lv < cur)
            local cr, cg, cb = 1, 0.82, 0
            if here then cr, cg, cb = 0.2, 1, 0.6 elseif past then cr, cg, cb = 0.55, 0.55, 0.55 end
            h.band:SetColorTexture(cr, cg, cb, here and 0.20 or 0.11); h.band:Show()
            h.bandAcc:SetColorTexture(cr, cg, cb, 0.95); h.bandAcc:Show()
            h.bandLine:SetColorTexture(cr, cg, cb, 0.45); h.bandLine:Show()
            local hex = here and "33ff99" or (past and "a0a0a0" or "ffd100")
            h.big:SetText("|cff" .. hex .. ns.L("第 ", "Level ") .. it.lv .. ns.L(" 级", "") .. "|r"
                .. (here and ("  |cff33ff99" .. ns.L("你现在在这", "you are here") .. "|r") or "")
                .. (past and ("  |cff808080" .. ns.L("已过", "past") .. "|r") or ""))
            h.big:Show()
            h.bandR:SetText("|cff" .. (past and "808080" or "c8c8c8") .. ns.L("本级 ", "") .. (perLv[it.lv] or 0) .. ns.L(" 项", " items") .. "|r"); h.bandR:Show()
            h:Show()
            y = y - 34
        end
        local r = nextRow(); place(r, 40)
        r.ic:Show(); r.ic:SetDesaturated(false)
        local state = it.kind == "talent" and it.state or it.st
        local tag = STATE_TXT[state]
        local suffix = tag and ("　" .. tag[1] .. tag[2] .. "|r") or ""
        if it.kind == "zone" then
            local e, z = it.entry, it.entry.zone
            r.ic:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
            r.t:SetText("|cff66ccff" .. ns.L(e.primary and "练级地图：" or "备选地图：", e.primary and "Leveling zone: " or "Alternative: ") .. "|r" .. ns.L(z.zh, z.en))
            local rangeTxt = e.lo .. "-" .. e.hi .. ns.L(" 级参考 · 按任务和位置选择，无需每张都去", " suggested levels; choose by quests and location")
            r.s:SetText(rangeTxt)
            -- 11-24「我58才来，那些够至少3级」：有任务经验数据（ZoneQuestXp.lua，HOLD 没装就没有）→ 副标题换成「建议 N 级来 · 任务经验约够升 X 级」
            local qxTip
            if ns.ZoneQXLine then
                local okq, qt, qtip = pcall(ns.ZoneQXLine, e, cur)
                if okq and qt then r.s:SetText(qt); qxTip = qtip end
            end
            r.btn:SetText(ns.L("打开地图", "Open map")); r.btn:Show()
            local function open() if ns.OpenRouteMap then ns.OpenRouteMap(z.m) end end
            r.btn:SetScript("OnClick", open); r:SetScript("OnClick", open)
            r:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(ns.L(z.zh, z.en), 1, 0.82, 0)
                GameTooltip:AddLine(r.s:GetText(), 1, 1, 1, true)
                if qxTip then
                    for _, line in ipairs(qxTip) do GameTooltip:AddLine(line, 0.6, 1, 0.75, true) end
                    GameTooltip:AddLine(rangeTxt, 0.8, 0.8, 0.8, true)
                end
                if e.primary then GameTooltip:AddLine(ns.L(e.stage.zh, e.stage.en), 1, 1, 1, true) end
                GameTooltip:AddLine(ns.L(e.stage.src == "fv" and "公开路线建议；非地图准入限制。" or "经典基线参考，Beta 可能调整；非准入限制。",
                    e.stage.src == "fv" and "Published route suggestion, not an entry restriction." or "Classic baseline; beta may change. Not an entry restriction."), 0.7, 0.7, 0.7, true)
                GameTooltip:Show()
            end)
        elseif it.kind == "trainergrp" then
            local open = isOpen(it.lv)
            local todo, miss, names = 0, 0, {}
            for _, x in ipairs(it.list) do
                if x.st == "now" or x.st == "missed" then todo = todo + 1 end
                if x.st == "missed" then miss = miss + 1 end
                if #names < 4 then names[#names + 1] = ns.TD(x.n) end   -- GI-253：技能名（数据中文）繁体端也转
            end
            r.ic:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
            r.pm:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up"); r.pm:Show()
            r.t:SetText("|cffffd100" .. ns.L("职业训练师：", "Class trainer: ") .. "|r" .. #it.list .. ns.L(" 个技能", " spells")
                .. (miss > 0 and ("  |cffff4040" .. ns.L("漏学 ", "missed ") .. miss .. "|r")
                    or todo > 0 and ("  |cff33ff99" .. ns.L("现在就能学 ", "learnable now ") .. todo .. "|r") or ""))
            r.s:SetText((open and ns.L("点击收起", "Click to collapse") or ns.L("点击展开：", "Click to expand: "))
                .. (open and "" or table.concat(names, ns.L("、", ", ")) .. (#it.list > #names and ns.L(" 等", " ...") or "")))
            if todo > 0 and ns.Trainers then
                r.btn:SetText(ns.L("找训练师", "Trainer")); r.btn:Show()
                r.btn:SetScript("OnClick", function() ns.Trainers.Go() end)
            end
            r:SetScript("OnClick", function() trainOpen[it.lv] = not open; refresh() end)
        elseif it.kind == "prof" then
            if ns.ProfRenderRow then ns.ProfRenderRow(r, it, suffix) end
        elseif it.kind == "chain" then
            chainRow(r, it, suffix)
        elseif it.kind == "quest" then
            r.ic:SetTexture(ICON.quest)
            r.t:SetText("|cff33ff99" .. ns.L("任务解锁：", "Quest-unlocked: ") .. "|r" .. ns.TD(it.n))
            r.s:SetText(ns.L("点击看完整任务链（谁给 / 在哪 / 目标）", "Click for the full chain (giver / location / objective)") .. suffix)
            r:SetScript("OnClick", function() showQuestPop(it.n) end)
            r:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(ns.TD(it.n), 1, 0.82, 0)
                GameTooltip:AddLine(ns.L("打任务解锁的技能，没有训练师条目", "Unlocked by a quest chain, no trainer entry"), 1, 1, 1, true)
                GameTooltip:Show()
            end)
        elseif it.kind == "spell" then
            r.ic:SetTexture((it.i and it.i ~= "") and ("Interface\\Icons\\" .. it.i) or ICON.spell)
            local rankTxt = it.rank and ("  |cff9d9d9d" .. ns.L("等级 ", "Rank ") .. it.rank .. "|r") or ""
            r.t:SetText((state == "done" and "|cff808080" or "") .. ns.TD(it.n) .. (state == "done" and "|r" or "") .. rankTxt)
            r.s:SetText((it.tal and ns.L("天赋技能：要先点对应天赋", "Talent ability: needs the talent first")
                or it.nt and ns.L("不在训练师那里学：技能书 / 任务 / 掉落", "Not taught by trainers: tome / quest / drop")
                or it.auto and ns.L("自动学会", "Learned automatically") or ns.L("去职业训练师那里学", "Learn from your class trainer")) .. suffix)
            r.ic:SetDesaturated(state == "done")
            -- 10-16 用户「点击找到最近的训练师，并打开小地图」：要去训练师那里学、现在就能学 / 漏学的行给「找训练师」
            if not it.tal and not it.nt and not it.auto and not it.inGroup and (state == "now" or state == "missed") and ns.Trainers then
                r.btn:SetText(ns.L("找训练师", "Trainer")); r.btn:Show()
                r.btn:SetScript("OnClick", function() ns.Trainers.Go() end)
                r:SetScript("OnClick", function() ns.Trainers.Go() end)
            end
            r:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(ns.TD(it.n), 1, 0.82, 0)
                if it.rank then
                    GameTooltip:AddLine(string.format(ns.L("等级 %d / 共 %d 级", "Rank %d of %d"), it.rank, it.rankMax)
                        .. (it.nextLv and string.format(ns.L("　下一级：%d 级可学", "  Next rank at level %d"), it.nextLv) or ns.L("　（最高级）", "  (max rank)")), 0.8, 0.8, 0.8)
                end
                if it.d ~= "" then GameTooltip:AddLine(ns.EnSafe(it.d), 1, 1, 1, true) end
                if state == "missed" then GameTooltip:AddLine(ns.L("等级早就够了，但你还没学——回训练师那里补上", "You're past this level but haven't learned it — visit your trainer"), 1, 0.3, 0.3, true) end
                GameTooltip:Show()
            end)
        elseif it.kind == "dquest" then
            local d = it.d
            local dn = d.n
            for _, ld in ipairs((ns.Data.loot or {}).dungeons or {}) do
                if ld.nEn == (d.loot or {})[1] then dn = ns.L((ld.n or ""):gsub("：.*$", ""), d.n); break end
            end
            r.ic:SetTexture("Interface\\Icons\\INV_Misc_Note_02")
            r.ic:SetDesaturated(state == "done")
            local names = {}
            for i, e in ipairs(it.list) do
                if i > 3 then names[#names + 1] = ns.L("等", "...") break end
                names[#names + 1] = ns.DQTitle(e.id)
            end
            r.t:SetText((state == "done" and "|cff808080" or "|cffff9933") .. ns.L("副本任务 · ", "Dungeon quests - ") .. dn .. "|r  |cff888888"
                .. #it.list .. ns.L(" 个", "") .. "|r")
            r.s:SetText(table.concat(names, ns.L("、", ", ")) .. suffix)
            r:SetScript("OnClick", function() if ns.ShowDungeonQuests then ns.ShowDungeonQuests(d, page) end end)
            r:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(dn .. ns.L(" 的副本任务", " dungeon quests"), 1, 0.82, 0)
                GameTooltip:AddLine(string.format(ns.L("%d 级起能接 %d 个；进本前先接好，经验和装备多拿一截", "From level %d: %d quests; pick them up before you go in"), it.lv, #it.list), 1, 1, 1, true)
                for _, e in ipairs(it.list) do
                    local col = (e.s == "done") and "|cff808080" or (e.s == "ok" or e.s == "log") and "|cff33ff99" or "|cffcccccc"
                    GameTooltip:AddLine(col .. ns.DQTitle(e.id) .. "|r", 1, 1, 1)
                end
                GameTooltip:AddLine(ns.L("点击：看谁给、在哪、前置和奖励", "Click: giver, location, prerequisites and rewards"), 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end)
        elseif it.kind == "talent" then
            local st = it.st
            r.ic:SetTexture((st.icon and st.icon ~= "") and ("Interface\\Icons\\" .. st.icon) or ICON.talent)
            -- 10-16 用户截图「x/x点标注下」：这一点是第几点 / 共几点
            r.t:SetText("|cff66ccff" .. ns.L("天赋：", "Talent: ") .. "|r" .. st.name
                .. ((st.rank and st.rankMax) and ("  |cffffd100" .. st.rank .. "/" .. st.rankMax .. "|r") or ""))
            r.s:SetText(st.tree .. (st.done and ("　|cff808080" .. ns.L("本级这一点已点", "already spent") .. "|r")
                or st.avail and ("　|cff33ff99" .. ns.L("现在就能点", "available now") .. "|r") or ""))
            r.ic:SetDesaturated(st.done and true or false)
            -- 10-16 用户「点击直接加点？打开天赋页然后高亮」：现在能点的行给「去点」—— 打开天赋面板 + 绿框（加点仍要玩家自己点，暴雪不许插件学天赋）
            -- 鼠标移上去时 Talents.lua 把安全按钮盖过来代点菜单栏天赋按钮；盖不了（战斗中 / 没有菜单栏按钮）就走这个按钮自己的兜底
            if st.avail and st.tab and ns.TalentOpenerHover then
                r.btn:SetText(ns.L("去点", "Go")); r.btn:Show()
                r.btn:SetScript("OnEnter", function(self) ns.TalentOpenerHover(self, st) end)
                r.btn:SetScript("OnClick", function() ns.TalentGoFallback(st) end)
                r:SetScript("OnClick", function() ns.TalentGoFallback(st) end)
            end
            if st.d ~= "" then
                r:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(st.name, 1, 0.82, 0)
                    GameTooltip:AddLine(ns.EnSafe(st.d), 1, 1, 1, true); GameTooltip:Show()
                end)
            end
        else -- macro
            local m = it.m
            r.ic:SetTexture((m.spells[1] and ns.SpellIcon(m.spells[1])) or "Interface\\Icons\\INV_Misc_QuestionMark")
            r.t:SetText("|cffc77dff" .. ns.L("宏：", "Macro: ") .. "|r" .. ns.L(m.tc, m.t))
            -- 按动作条状态：没有 → 导入；建了没放 → 放上动作条（拿到鼠标上）；已在动作条 → 灰掉
            local ms = it.ms or "none"
            local msTxt = (ms == "onbar" and ns.L("|cff808080已在动作条|r　", "|cff808080On your bars|r  "))
                or (ms == "created" and ns.L("|cffffd100已建好，还没放到动作条|r　", "|cffffd100Created, not on your bars|r  ")) or ""
            r.s:SetText(msTxt .. ns.EnSafe(ns.L(m.nc, m.n)))
            r.ic:SetDesaturated(ms == "onbar")
            r.btn:Show()
            if ms == "onbar" then
                r.btn:SetText(ns.L("已放好", "Done")); r.btn:SetEnabled(false)
            elseif ms == "created" then
                r.btn:SetText(ns.L("放上动作条", "Place")); r.btn:SetEnabled(not InCombatLockdown())
                r.btn:SetScript("OnClick", function()
                    local _, _, idx = ns.MacroState(m)
                    if idx and PickupMacro then PickupMacro(idx) end
                    ns.Print(ns.L("宏已在鼠标上：点一下动作条格子放下", "Macro is on your cursor: click an action button"))
                end)
            else
                r.btn:SetText(ns.L("导入", "Import")); r.btn:SetEnabled(not InCombatLockdown())
                r.btn:SetScript("OnClick", function()
                    local ok, msg = ns.ImportMacro(m)
                    ns.Print(ok and (ns.L("宏「", "Macro \"") .. msg .. ns.L("」已在鼠标上：点一下动作条格子放下", "\" is on your cursor")) or msg)
                    if ok then refresh() end
                end)
            end
            r:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(ns.L(m.tc, m.t), 1, 0.82, 0)
                for ln in (ns.MacroBody(m) .. "\n"):gmatch("(.-)\n") do GameTooltip:AddLine(ln, 0.6, 0.9, 1) end
                GameTooltip:Show()
            end)
        end
        -- 显示不全一律能悬停看全文（用户硬规定）：这一行没有专门的提示时，挂标题 + 说明的完整文字
        if not r:GetScript("OnEnter") then
            r:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.t:GetText() or "", 1, 0.82, 0, true)
                if (self.s:GetText() or "") ~= "" then GameTooltip:AddLine(self.s:GetText(), 1, 1, 1, true) end
                GameTooltip:Show()
            end)
        end
        r:Show()
        y = y - 44
    end
    if #items == 0 and not err then
        if (page.hiddenDone or 0) > 0 then
            warn(ns.L("这个等级范围里的都完成了（已隐藏 ", "Everything in this range is done (") .. page.hiddenDone .. ns.L(" 项已完成）", " hidden)"))
        else
            warn(ns.L("这个等级范围里没有要学的技能 / 宏（把范围条往外拉一点试试）", "Nothing in this level range — widen the range bar"))
        end
    end
    page.child:SetHeight(-y + 6)
    -- 打开页面 / 换范围 / 换排序时：滚到「你现在在这」那组；当前等级不在范围里就回顶部
    -- （⛔ 10-07 空白事故：短列表留着长列表的滚动位置，内容全在视野上方——所以换范围必须重设滚动）
    if page.needScroll and page.sf then
        page.needScroll = false
        local want = curY or 0
        if page.sf.UpdateScrollChildRect then page.sf:UpdateScrollChildRect() end
        local maxR = tonumber(page.sf.GetVerticalScrollRange and page.sf:GetVerticalScrollRange()) or 0
        page.sf:SetVerticalScroll(math.max(0, math.min(want, maxR)))
    end
end

-- 掉落数据里按名字找副本（拿副本图用；装备页背景和刷本清单卡片共用）
local function lootDungeonByName(name)
    for _, d in ipairs(ns.Data.loot and ns.Data.loot.dungeons or {}) do if d.n == name then return d end end
end

-- ---------- 装备页：纸娃娃 ----------
local SLOT_PX, SLOT_GAP = 34, 37
local SUB_FONT = STANDARD_TEXT_FONT or "Fonts\\ARKai_T.ttf"
local UPGRADE_ICON = "Interface\\Icons\\Spell_ChargePositive"     -- 比身上好：游戏图标（⛔不用箭头字符，中文字体会变方框）
local CHECK_ICON = "Interface\\Buttons\\UI-CheckBox-Check"           -- 已经穿着
local T5_W = 38   -- 11-23 格子旁「前5」按钮宽（名字那行末端，名字让出这么宽 + 4）

local function slotTexture(invName)
    if GetInventorySlotInfo then
        local ok, _, tex = pcall(GetInventorySlotInfo, invName)
        if ok and tex then return tex end
    end
    return "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. (SLOT_FALLBACK_TEX[invName] or "Chest")
end

-- 身上这格：物品 ID + 装等（读不到返回 nil）
local function equipped(invName)
    if not (GetInventorySlotInfo and GetInventoryItemLink) then return nil end
    local ok, slotId = pcall(GetInventorySlotInfo, invName)
    if not ok or not slotId then return nil end
    local link = GetInventoryItemLink("player", slotId)
    if not link then return nil end
    local id = tonumber(link:match("item:(%d+)"))
    local ilvl = select(4, ns.ItemInfo(link))
    return { id = id, ilvl = ilvl }
end

local function getSlotBtn(key)
    local b = gp.gearBtns[key]
    if b then return b end
    b = CreateFrame("Button", nil, gp.gearFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    b:SetSize(SLOT_PX, SLOT_PX)
    if b.SetBackdrop then
        b:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        b:SetBackdropColor(0.06, 0.06, 0.09, 0.9)
    end
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 3, -3); b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.badge = b:CreateTexture(nil, "OVERLAY"); b.badge:SetSize(14, 14); b.badge:SetPoint("TOPRIGHT", 3, 3); b.badge:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- 10-08 用户截图（英雄榜纸娃娃）「这里也改成这样的展示形式」：格子旁写装备名 + 一行小字，名字朝模型那边写
    b.name = gp.gearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.sub = gp.gearFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    for _, fs in ipairs({ b.name, b.sub }) do
        fs:SetWordWrap(false)
        if fs.SetShadowOffset then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1) end   -- 压在副本背景图上也看得清
    end
    -- 第二行小一号：10-08 截图里「装等 37 · 需要 32 级 · …」来源被截掉了
    if b.sub.SetFont then pcall(b.sub.SetFont, b.sub, SUB_FONT, 10, "") end
    -- 文字区也能悬停 / 点击（字可能被截断 → 悬停看全文，用户硬规定）
    b.hit = CreateFrame("Button", nil, gp.gearFrame)
    b.hit:SetScript("OnEnter", function() local f = b:GetScript("OnEnter"); if f then f(b) end end)
    b.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b.hit:SetScript("OnClick", function() local f = b:GetScript("OnClick"); if f then f(b) end end)
    -- 11-23 用户「旁边加个按钮是看前5」：60 级有 BiS 数据的格子，名字那行末端放「前5」（setSlotItem 定位 / 显隐）
    b.t5 = ns.Button(gp.gearFrame, ns.L("前5", "Top 5"), T5_W, 16, function() ns.BisShowTop(b) end)
    b.t5:SetFrameLevel((b.hit:GetFrameLevel() or 0) + 3); b.t5:Hide()
    gp.gearBtns[key] = b
    return b
end

-- 文字放在格子哪一边：side = "R" 写在图标右边（左列 / 副手），"L" 写在图标左边（右列 / 主手 / 远程）
local function placeLabel(b, side, w)
    local GAP = 6
    b.name:ClearAllPoints(); b.sub:ClearAllPoints(); b.hit:ClearAllPoints()
    if side == "R" then
        b.name:SetPoint("TOPLEFT", b, "TOPRIGHT", GAP, -2); b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -3)
        b.name:SetJustifyH("LEFT"); b.sub:SetJustifyH("LEFT")
        b.hit:SetPoint("TOPLEFT", b, "TOPRIGHT", 0, 0); b.hit:SetPoint("BOTTOMLEFT", b, "BOTTOMRIGHT", 0, 0)
    else
        b.name:SetPoint("TOPRIGHT", b, "TOPLEFT", -GAP, -2); b.sub:SetPoint("TOPRIGHT", b.name, "BOTTOMRIGHT", 0, -3)
        b.name:SetJustifyH("RIGHT"); b.sub:SetJustifyH("RIGHT")
        b.hit:SetPoint("TOPRIGHT", b, "TOPLEFT", 0, 0); b.hit:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT", 0, 0)
    end
    b.name:SetWidth(w); b.sub:SetWidth(w); b.hit:SetWidth(w + GAP)
    b.side, b.labW = side, w
    b.name:Show(); b.sub:Show(); b.hit:Show()
end

local function setSlotItem(b, g, it, mainTwo)
    local invName = g[3]
    b.it, b.slotKey = it, g[1]
    b.icon:SetDesaturated(false); b.badge:Hide()
    if it then
        b.icon:SetTexture("Interface\\Icons\\" .. ((it.i and it.i ~= "") and it.i or "inv_misc_questionmark"))
        b.icon:SetVertexColor(1, 1, 1)
        local hex = QCOLOR[it.q] or "ffffff"
        if b.SetBackdropBorderColor then
            b:SetBackdropBorderColor(tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1)
        end
        -- 和身上比：已穿 = 勾；更好 = 升级图标；更差 = 变灰
        --   10-18 两件都有属性数据 → 按当前天赋的分数比（cmpBy = "spec"）；否则照旧比装等
        local eq = equipped(invName)
        b.cmp, b.cmpBy, b.eqRank = nil, nil, nil
        local SG, spec = ns.SpecGear, gp.curSpec
        -- 60 级 BiS 前 5（11-23 起 WCL 实测）：按名次比（身上那件也在前 5 里 = 不提示升级，悬停写第几名；不在 = 升级）
        local top = gp.curTop and gp.curTop[CUR_KEYS[g[1]] or ""]
        if top and eq and eq.id ~= it.id then
            for r, e in ipairs(top) do if e.id == eq.id then b.eqRank = r end end
        end
        local sNew = not top and spec and eq and eq.id ~= it.id and SG.Score(it.id, it.slot, myClass(), spec, gp.curLv) or nil
        local sOld = sNew and SG.Score(eq.id, it.slot, myClass(), spec, gp.curLv) or nil
        if top and eq and eq.id ~= it.id then
            b.cmpBy = "bis"
            if b.eqRank then b.cmp = "inlist" else b.cmp = "up"; b.badge:SetTexture(UPGRADE_ICON); b.badge:Show() end
        elseif eq and eq.id == it.id then
            b.cmp = "worn"; b.badge:SetTexture(CHECK_ICON); b.badge:Show()
        elseif sNew and sOld then
            b.cmpBy = "spec"
            if sNew > sOld + 1e-6 then b.cmp = "up"; b.badge:SetTexture(UPGRADE_ICON); b.badge:Show()
            else b.cmp = "down"; b.icon:SetDesaturated(true) end
        elseif eq and eq.ilvl and (it.ilvl or 0) > eq.ilvl then
            b.cmp = "up"; b.badge:SetTexture(UPGRADE_ICON); b.badge:Show()
        elseif eq and eq.ilvl and (it.ilvl or 0) <= eq.ilvl then
            b.cmp = "down"; b.icon:SetDesaturated(true)
        end
    else
        b.icon:SetTexture(slotTexture(invName)); b.icon:SetVertexColor(0.6, 0.6, 0.6)
        if b.SetBackdropBorderColor then b:SetBackdropBorderColor(0.3, 0.3, 0.3, 1) end
    end
    -- 格子旁的两行字：装备名（品质色）+ 装等 · 需要几级 · 来源；空格子写部位名
    if b.name then
        if it then
            local req = (it.req and it.req > 0) and it.req or (it.min or 0)
            b.name:SetText("|cff" .. (QCOLOR[it.q] or "ffffff") .. ns.ItemNm(it) .. "|r")
            local src = (it.src == "quest") and ns.L("任务", "Quest") or (it.src == "craft") and ns.L("制造", "Crafted")
                or (it.src == "vendor") and ns.L("商人", "Vendor")
                or (it.src == "bis") and ((it.how == "drop" or it.how == "world") and curShortSrc(it.srcName) or ns.BisHowText(it.how))
                or ns.TD(it.dn or "")
            local sub = "|cffd8c79a" .. ns.L("装等 ", "ilvl ") .. (it.ilvl or 0) .. "|r|cff999999" .. ns.L(" · ", " · req ") .. req .. ns.L(" 级", "")
            if src ~= "" then sub = sub .. " · " .. src end
            sub = sub .. "|r"
            local alt = gp.curAlts and gp.curAlts[g[1]]
            if alt then sub = sub .. "|cff66ccff" .. ns.L(" · 也可制造", " · craft alt") .. (alt.pct and (" +" .. alt.pct .. "%") or "") .. "|r" end
            if b.cmp == "worn" then sub = "|cff66ff66" .. ns.L("已穿 · ", "worn · ") .. "|r" .. sub
            elseif b.cmp == "up" then sub = "|cff66ff66" .. ns.L("可升级 · ", "upgrade · ") .. "|r" .. sub
            elseif b.cmp == "inlist" then sub = "|cffffd100" .. string.format(ns.L("身上的排第 %d · ", "yours is #%d · "), b.eqRank or 0) .. "|r" .. sub end
            b.sub:SetText(sub)
        elseif g[1] == "off" and mainTwo then
            b.name:SetText("|cff777777" .. ns.L("副手", "Off hand") .. "|r"); b.sub:SetText(ns.L("主手是双手武器", "Two-handed main hand"))
        elseif not g[2] then
            b.name:SetText("|cff777777" .. (g[1] == "shirt" and ns.L("衬衣", "Shirt") or ns.L("战袍", "Tabard")) .. "|r"); b.sub:SetText(ns.L("外观，不推荐", "Cosmetic"))
        else
            b.name:SetText("|cff777777" .. ns.TD(g[2]) .. "|r"); b.sub:SetText(ns.L("暂无推荐", "No pick yet"))
        end
    end
    local top5 = it and gp.curTop and gp.curTop[CUR_KEYS[g[1]] or ""]
    local t5on = (top5 and #top5 > 0) or false
    b.t5:SetShown(t5on)
    if t5on and b.labW then
        local off = 6 + b.labW - T5_W
        b.t5:ClearAllPoints()
        if b.side == "R" then b.t5:SetPoint("TOPLEFT", b, "TOPRIGHT", off, 1) else b.t5:SetPoint("TOPRIGHT", b, "TOPLEFT", -off, 1) end
        b.name:SetWidth(b.labW - T5_W - 4)
    elseif b.labW then b.name:SetWidth(b.labW) end
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if it then
            -- 物品原生提示（带服务器下发的真实属性）；客户端还没缓存就用我们自己的简版
            local ok = pcall(GameTooltip.SetItemByID, GameTooltip, it.id)
            local first = (GameTooltip:NumLines() or 0) > 0 and _G.GameTooltipTextLeft1 and _G.GameTooltipTextLeft1:GetText()
            if not ok or not first or first == "" or first == RETRIEVING_ITEM_INFO then
                if ns.ItemFallbackTip then ns.ItemFallbackTip(it)   -- 和掉落页同一个简版：带属性 / 经典原版注明 / 读取状态
                else
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine("|cff" .. (QCOLOR[it.q] or "ffffff") .. ns.ItemNm(it) .. "|r")
                    GameTooltip:AddLine(ns.TD(it.slot or "") .. ((it.type and it.type ~= "") and (" · " .. ns.TD(it.type)) or "") .. ns.L("　装等 ", "  ilvl ") .. (it.ilvl or 0), 0.8, 0.8, 0.8)
                end
            end
            GameTooltip:AddLine(" ")
            local req = (it.req and it.req > 0) and it.req or (it.min or 0)
            -- 10-07 用户截图：「GI 掉落：哀嚎洞穴 · 斯卡姆」和「GearInsight 需要 17 级 · 掉落 · 哀嚎洞穴 · 斯卡姆」重复 →
            --   掉落来源交给全局物品提示那一行（PageLoot），这里只补任务来源
            if it.src == "quest" then
                GameTooltip:AddLine("|cff33ff99GI|r " .. ns.L("需要 ", "Req ") .. req .. ns.L(" 级 · 任务：", " · Quest: ") .. ns.TD(it.srcName or ""), 1, 0.82, 0.4, true)
            elseif it.src == "craft" or it.src == "vendor" then
                GameTooltip:AddLine("|cff33ff99GI|r " .. ns.L("需要 ", "Req ") .. req .. ns.L(" 级 · ", " · ") .. ns.GearSourceText(it), 1, 0.82, 0.4, true)
            elseif it.src == "bis" then
                local info = bisItem(it.id) or {}
                GameTooltip:AddLine("|cff33ff99GI|r " .. (req > 0 and (ns.L("需要 ", "Req ") .. req .. ns.L(" 级 · ", " · ")) or "")
                    .. ns.L("来源：", "Source: ") .. bisSrcText(info.how or it.how, info.s, info.sEn), 1, 0.82, 0.4, true)
            elseif rawget(GameTooltip, "__gifItem") ~= it.id then   -- 全局那行没加上（物品没缓存、走了简版）才补
                GameTooltip:AddLine("|cff33ff99GI|r " .. ns.L("需要 ", "Req ") .. req .. ns.L(" 级 · 掉落：", " · Drops: ") .. ns.TD(it.srcName or ""), 1, 0.82, 0.4, true)
            end
            -- 11-06 备选：最佳制造件比主推荐分高 → 「也可以：…」（点击行为照旧按主推荐走）
            local alt = gp.curAlts and gp.curAlts[g[1]]
            if alt then GameTooltip:AddLine("|cff33ff99GI|r " .. ns.GearAltText(alt), 0.4, 0.8, 1, true) end
            -- 10-18 按天赋：写明按哪套挑的、这件最值钱的几项属性
            local SG, spec = ns.SpecGear, gp.curSpec
            local si = spec and SG.SpecInfo(myClass(), spec)
            -- 60 级 BiS（11-23 起 WCL 实测）：只写一行「第 N 名 · 使用率 · 人数」；前 5 走格子旁「前5」按钮（用户：「不要这样列出来」）
            local top = gp.curTop and gp.curTop[CUR_KEYS[g[1]] or ""]
            if top then
                local me
                for _, e in ipairs(top) do if e.id == it.id then me = e end end
                GameTooltip:AddLine("|cff33ff99GI|r " .. string.format(ns.L("%d 级 BiS 第 %d 名", "Lv %d BiS #%d"), gp.curTop.lv or 60, me and me.rank or 0)
                    .. (me and (" · " .. bisStatText(me)) or ""), 1, 0.82, 0)
                si = nil
            end
            if si then
                local top = SG.TopStats(it.id, it.slot, myClass(), spec, gp.curLv, 3)
                GameTooltip:AddLine("|cff33ff99GI|r " .. ns.L("按天赋「", "Picked for ") .. ns.L(si.zh, si.en) .. ns.L("」挑的", "")
                    .. (#top > 0 and ("：" .. table.concat(top, " · ")) or ns.L("（这件没有属性数据，按装等排）", " (no stat data, ranked by ilvl)")), 0.8, 0.8, 0.8, true)
            end
            local why = self.cmpBy == "spec" and ns.L("按这个天赋的属性算", "by this spec's stat weights")
                or self.cmpBy == "bis" and ns.L("身上那件不在前 5 里", "yours isn't in the top 5") or ns.L("装等更高", "higher ilvl")
            if self.cmp == "worn" then GameTooltip:AddLine(ns.L("你已经穿着这件", "You're wearing this"), 0.4, 1, 0.4)
            elseif self.cmp == "inlist" then
                GameTooltip:AddLine(string.format(ns.L("你身上这件在前 5 里排第 %d", "What you wear is #%d in the top 5"), self.eqRank or 0), 1, 0.82, 0)
            elseif self.cmp == "up" then GameTooltip:AddLine(ns.L("比你身上这格好（", "Upgrade over what you wear (") .. why .. ns.L("）", ")"), 0.4, 1, 0.4)
            elseif self.cmp == "down" then GameTooltip:AddLine(ns.L("不如你身上这格", "Worse than what you wear")
                .. (self.cmpBy == "spec" and ns.L("（按这个天赋的属性算）", " (by this spec's stat weights)") or ""), 0.6, 0.6, 0.6) end
            if top then GameTooltip:AddLine(ns.L("点击：打开装备页（掉落首领 / 任务链 / 配方）· 「前5」看这格前 5", "Click: item page (boss loot / quest chain / recipe) - Top 5 button: this slot's top 5"), 0.6, 0.6, 0.6, true)
            elseif it.src == "vendor" then GameTooltip:AddLine(ns.L("点击：在地图上标出商人", "Click: pin the vendor on the map"), 0.6, 0.6, 0.6)
            elseif it.src == "craft" then
                GameTooltip:AddLine(playerProfs()[it.pf] and ns.L("点击：打开「专业」页找这个配方", "Click: open the Professions page")
                    or ns.L("点击：聊天框给出制作信息（找人做 / 拍卖行）", "Click: print crafting info (crafter / AH)"), 0.6, 0.6, 0.6)
            elseif it.src ~= "quest" and it.src ~= "bis" then GameTooltip:AddLine(ns.L("点击：去掉落页看这个副本", "Click: open this dungeon on the Loot page"), 0.6, 0.6, 0.6) end
            GameTooltip:AddLine(ns.L("Shift + 点击：发到聊天框 · Ctrl + 点击：试穿", "Shift-click: link in chat - Ctrl-click: try on"), 0.6, 0.6, 0.6)
        elseif g[1] == "off" and mainTwo then
            GameTooltip:AddLine(ns.L("副手", "Off hand"), 1, 0.82, 0)
            GameTooltip:AddLine(ns.L("推荐的主手是双手武器，副手用不上", "The main-hand pick is two-handed, so no off hand"), 0.8, 0.8, 0.8, true)
        elseif not g[2] then
            GameTooltip:AddLine(ns.L("衬衣 / 战袍只是外观，不推荐", "Shirt / tabard are cosmetic, no recommendation"), 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine(ns.TD(g[2]), 1, 0.82, 0)
            GameTooltip:AddLine(ns.L("这个部位目前查不到候选——装备来源是地下城掉落 + 职业任务链套装 + 专业制造 + 商人出售，野外任务奖励还没收",
                "No candidate for this slot yet — sources are dungeon drops, class quest-chain sets, crafted and vendor gear; open-world quest rewards are not included yet"), 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnClick", function()
        if it and ns.ItemModClick and ns.ItemModClick(it.id, it.n) then return end   -- Shift 发聊天 / Ctrl 试穿
        if it and gp.curTop and gp.curTop[CUR_KEYS[g[1]] or ""] then ns.BisOpenItem(it.id); return end   -- 60 级 BiS：装备页
        if it and (it.src == "craft" or it.src == "vendor") then ns.GearGuide(it); return end
        if it and it.src ~= "quest" and it.src ~= "bis" and it.dn and ns.LootShowDungeon then ns.LootShowDungeon(it.dn) end
    end)
end

-- ---------- 11-23 60 级 BiS「前5」小面板 + 装备页 ----------
-- 用户截图「不要这样列出来，是旁边加个按钮是看前5，然后点击装备可以打开一个装备页，展示当前BOSS和掉落装备视图」：
--   「前5」= 这个小面板（图标 · 品质色名字 / 使用率 · 人数 · 来源；悬停物品提示，Shift 发聊天 / Ctrl 试穿，ESC 关）。
--   点装备 = 装备页：副本 → 掉落页定位到首领并高亮这件（ns.LootShowItem）；任务 → 副本任务链定位到那条任务（ns.DQOpenForItem）；
--   制造 → 专业页配方库定位到配方（ns.ProfOpenRecipe）；找不到 / 声望 / 野外 / 商人 → 这个面板换成「这件 + 来源说明」
--   ⛔ 合并包登录内存预算紧（MERGED_EXTRA_KB）：框体第一次点才建，一个面板两种用法，别再加函数
local bisPop
local function rowEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetItemByID, GameTooltip, self.id)
    GameTooltip:AddLine(ns.L("点击：打开装备页 · Shift + 点击：发到聊天框 · Ctrl + 点击：试穿", "Click: item page - Shift-click: link - Ctrl-click: try on"), 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end
local function rowClick(self) if not (ns.ItemModClick and ns.ItemModClick(self.id, self.nm)) then ns.BisOpenItem(self.id) end end
-- list = 要列的条目（{ id, rank, cnt, pct }…，最多 5 行）；note = 装备页的来源说明（前 5 时 nil）
local function bisShow(title, list, key, note)
    local f = bisPop
    if not f then
        f = CreateFrame("Frame", "GearInsightForeverBisTop", gp.page, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(400, 214); f:SetFrameStrata("DIALOG"); f:EnableMouse(true); f:SetClampedToScreen(true)
        if f.SetBackdrop then
            f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            f:SetBackdropColor(0.04, 0.04, 0.07, 0.97)
        end
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOPLEFT", 12, -10); f.title:SetPoint("RIGHT", -30, 0); f.title:SetJustifyH("LEFT")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, 0); close:SetScript("OnClick", function() f:Hide() end)
        f.note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.note:SetPoint("TOPLEFT", 14, -84); f.note:SetPoint("RIGHT", -14, 0); f.note:SetJustifyH("LEFT")
        f.rows = {}
        for i = 1, 5 do
            local r = CreateFrame("Button", nil, f)
            r:SetPoint("TOPLEFT", 10, -44 - (i - 1) * 32); r:SetPoint("RIGHT", -10, 0); r:SetHeight(30)
            r.ic = r:CreateTexture(nil, "ARTWORK"); r.ic:SetSize(26, 26); r.ic:SetPoint("LEFT"); r.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.t:SetPoint("TOPLEFT", 32, -1)
            r.s = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); r.s:SetPoint("BOTTOMLEFT", 32, 1)
            for _, fs in ipairs({ r.t, r.s }) do fs:SetPoint("RIGHT", 0, 0); fs:SetWordWrap(false); fs:SetJustifyH("LEFT") end
            local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
            r:SetScript("OnEnter", rowEnter); r:SetScript("OnLeave", function() GameTooltip:Hide() end); r:SetScript("OnClick", rowClick)
            f.rows[i] = r
        end
        if UISpecialFrames then table.insert(UISpecialFrames, "GearInsightForeverBisTop") end
        bisPop = f
    end
    f.title:SetText(title)
    for i, r in ipairs(f.rows) do
        local e = list[i]
        r:SetShown(e ~= nil)
        if e then
            local it, info = curItem(myClass(), e, key), bisItem(e.id) or {}
            local ic = (it.i and it.i ~= "") and it.i or info.i
            r.ic:SetTexture((ic and ic ~= "") and ("Interface\\Icons\\" .. ic) or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.id))
                or "Interface\\Icons\\inv_misc_questionmark")
            r.id, r.nm = e.id, curName(e)
            r.t:SetText("|cff" .. (QCOLOR[it.q or info.q] or "ffffff") .. (e.rank and (e.rank .. ". ") or "") .. r.nm .. "|r")
            r.s:SetText((e.cnt and (bisStatText(e) .. " · ") or "") .. bisSrcText(info.how, info.s, info.sEn))
        end
    end
    f.note:SetText(note or ""); f.note:SetShown(note ~= nil)
    f:Show()
    return f
end
-- 格子旁「前5」
function ns.BisShowTop(b)
    local key, ct = CUR_KEYS[b.slotKey or ""], gp.curTop
    local top = key and ct and ct[key]
    if not top or #top == 0 then return nil end
    local f = bisShow(string.format(ns.L("%s · %d 级 BiS 前 %d（WCL 全球 %d 名%s实测）", "%s - Lv %d BiS top %d (WCL, %d %s players worldwide)"),
        ns.L(ns.TD(BIS_SLOT_CN[key]), key), ct.lv or 60, #top, ct.n or 0, ns.L(ct.zh or "", (ct.full or ""):match("/(.+)$") or "")), top, key)
    f:ClearAllPoints()
    if b.side == "L" then f:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, -2) else f:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2) end
    return f
end
-- 装备页：返回去了哪（测试用）loot / quest / recipe / note
function ns.BisOpenItem(id)
    local info = bisItem(id) or {}
    local how, s = info.how, info.s or ""
    local went = (how == "drop" and ns.LootShowItem and ns.LootShowItem(id) and "loot")
        or (how == "quest" and ns.DQOpenForItem and ns.DQOpenForItem(id, (s:gsub("^任务：", ""))) and "quest")
    if not went and how == "craft" and ns.LoadModule then
        pcall(ns.LoadModule, "prof", true)
        went = ns.ProfOpenRecipe and ns.ProfOpenRecipe(id) and "recipe"
    end
    if went then
        if bisPop then bisPop:Hide() end
        return went
    end
    local e, was = { id = id }, bisPop and bisPop:IsShown()
    local f = bisShow(ns.L("装备页 · ", "Item - ") .. curName(e), { e }, nil, ns.L("来源：", "Source: ") .. bisSrcText(how, s, info.sEn))
    if not was then f:ClearAllPoints(); f:SetPoint("CENTER", gp.page, "CENTER", 0, 0) end
    return "note"
end

-- 中间的角色模型：试穿推荐装备。⛔ 无限客户端不确定有 DressUpModel / TryOn → pcall，失败退回 PlayerModel 只显示角色
local function buildModel(parent)
    local ok, m = pcall(CreateFrame, "DressUpModel", nil, parent)
    if not ok or not m then ok, m = pcall(CreateFrame, "PlayerModel", nil, parent) end
    if not ok or not m then return nil end
    m.facing = 0
    m:EnableMouse(true)
    m:SetScript("OnMouseDown", function(self) self.dragX = GetCursorPosition() end)
    m:SetScript("OnMouseUp", function(self) self.dragX = nil end)
    m:SetScript("OnUpdate", function(self)
        if not self.dragX then return end
        local x = GetCursorPosition()
        self.facing = self.facing + (x - self.dragX) * 0.02; self.dragX = x
        pcall(self.SetFacing, self, self.facing)
    end)
    m:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(ns.L("穿上这套的样子", "Wearing this set"), 1, 0.82, 0)
        GameTooltip:AddLine(ns.L("按住拖动可以转身", "Drag to rotate"), 1, 1, 1)
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return m
end

local function dressModel(bySlot)
    local m = gp.model
    if not m then return end
    pcall(m.SetUnit, m, "player")
    if m.TryOn then
        if m.Dress then pcall(m.Dress, m) end
        for _, it in pairs(bySlot) do pcall(m.TryOn, m, "item:" .. it.id) end
    end
end

local function refreshGear(tgt)
    local bySlot, spec, alts, cur = bestGearBySlot(tgt)
    gp.curSpec, gp.curLv, gp.curAlts, gp.curTop = spec, tgt, alts or {}, cur
    local W = gp.gearFrame:GetWidth() or 646
    if not tonumber(W) or W < 300 then W = 646 end
    -- 10-08 照英雄榜纸娃娃：图标贴两边，名字朝中间写，模型夹在中间；底部 主手（字在左）· 副手（字在右）· 远程（右下角，字在左）
    local cx = math.floor(W / 2)
    local MODEL_HALF = 88
    local leftX, rightX = 6, W - 6 - SLOT_PX
    local sideW = cx - MODEL_HALF - (leftX + SLOT_PX) - 10
    local function column(list, x, side)
        for i, g in ipairs(list) do
            local b = getSlotBtn(g[1])
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", x, -(i - 1) * SLOT_GAP)
            placeLabel(b, side, sideW)
            setSlotItem(b, g, bySlot[g[1]]); b:Show()
        end
    end
    column(GEAR_LEFT, leftX, "R")
    column(GEAR_RIGHT, rightX, "L")
    local by = -8 * SLOT_GAP - 4
    local mainTwo = bySlot.main and bySlot.main.two
    local pos = {
        main = { cx - 4 - SLOT_PX, "L", cx - 4 - SLOT_PX - leftX - 10 },
        off = { cx + 4, "R", 0 },
        ranged = { rightX, "L", 0 },
    }
    pos.ranged[3] = math.floor((rightX - (cx + 4 + SLOT_PX)) / 2) - 8
    pos.off[3] = pos.ranged[3]
    for _, g in ipairs(GEAR_BOTTOM) do
        local b = getSlotBtn(g[1])
        local p = pos[g[1]]
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", p[1], by)
        placeLabel(b, p[2], p[3])
        setSlotItem(b, g, bySlot[g[1]], mainTwo); b:Show()
    end
    if gp.model then
        gp.model:ClearAllPoints()
        gp.model:SetPoint("TOPLEFT", cx - MODEL_HALF, 0)
        gp.model:SetPoint("BOTTOMRIGHT", gp.gearFrame, "TOPLEFT", cx + MODEL_HALF, by + 6)
        dressModel(bySlot)
    end
    -- 底部汇总：几个格子有推荐 · 副本几件（按副本数）· 任务几件；悬停看明细
    local n, nd, nq, byD, total = 0, 0, 0, {}, 0
    local nc, nv = 0, 0
    for _, grp in ipairs({ GEAR_LEFT, GEAR_RIGHT, GEAR_BOTTOM }) do
        for _, g in ipairs(grp) do
            if g[2] then total = total + 1 end
            local it = bySlot[g[1]]
            if it then
                n = n + 1
                if it.src == "quest" then nq = nq + 1
                elseif it.src == "craft" then nc = nc + 1
                elseif it.src == "vendor" then nv = nv + 1
                else nd = nd + 1; local dn = it.dn or "?"; byD[dn] = (byD[dn] or 0) + 1 end
            end
        end
    end
    -- 10-08 用户「加上副本背景图」：用这套里推荐件数最多的那个副本的场景图铺底（按比例裁，不拉伸），压一层暗色保证字看得清
    local topD, topN = nil, 0
    for dn, c in pairs(byD) do if c > topN or (c == topN and topD and dn < topD) then topD, topN = dn, c end end
    local art = topD and ns.DungeonArt and lootDungeonByName(topD) and ns.DungeonArt(lootDungeonByName(topD))
    local H = gp.gearFrame:GetHeight() or 366
    if not tonumber(H) or H < 200 then H = 366 end
    gp.gearArtDn = (art and art.big) and topD or nil
    if art and art.big then
        gp.gearBg:SetTexture(art.big); gp.gearBg:SetTexCoord(ns.ArtCoord({ region = art.bigRegion }, W, H)); gp.gearBg:Show(); gp.gearShade:Show()
        gp.gearBgCap:SetText(topD .. " · " .. topN .. ns.L(" 件", ""))
        gp.gearBgFull = ns.L("背景是「", "Backdrop: ") .. topD .. ns.L("」：这套推荐里有 ", " — ") .. topN .. ns.L(" 件出自这个副本，是最多的", " pieces of this set drop here (the most)")
        gp.gearBgCap:Show()
    else
        gp.gearBg:Hide(); gp.gearShade:Hide(); gp.gearBgCap:Hide()
    end
    gp.gearNote:SetText(ns.L("推荐 ", "") .. n .. "/" .. total .. ns.L(" 格 · 副本 ", " slots · dungeons ") .. nd
        .. ns.L(" 件 · 任务 ", " · quests ") .. nq .. ((nc + nv > 0) and (ns.L(" 件 · 制造 ", " · crafted ") .. nc .. ns.L(" 件 · 商人 ", " · vendor ") .. nv) or "")
        .. ns.L(" 件（悬停看明细）", " (hover for details)"))
    gp.gearNoteHit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(ns.L("装备来源", "Gear sources"), 1, 0.82, 0)
        local names = {}
        for dn in pairs(byD) do names[#names + 1] = dn end
        table.sort(names, function(a, b) return byD[a] > byD[b] end)
        for _, dn in ipairs(names) do GameTooltip:AddDoubleLine(dn, byD[dn] .. ns.L(" 件", ""), 1, 1, 1, 1, 1, 1) end
        if nq > 0 then GameTooltip:AddDoubleLine(ns.L("职业任务链", "Class quest chains"), nq .. ns.L(" 件", ""), 1, 1, 1, 1, 1, 1) end
        if nc > 0 then GameTooltip:AddDoubleLine(ns.L("专业制造", "Crafted"), nc .. ns.L(" 件", ""), 1, 1, 1, 1, 1, 1) end
        if nv > 0 then GameTooltip:AddDoubleLine(ns.L("商人出售", "Vendors"), nv .. ns.L(" 件", ""), 1, 1, 1, 1, 1, 1) end
        GameTooltip:AddLine(ns.L("野外任务奖励还没收进来", "Open-world quest rewards aren't included yet"), 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
end



-- 纸娃娃那块内容区（10-18 用户「往外提一个标签页出来」：原是升级规划里的「装备」视图，独立成「装备」大类下的页签）
local function buildGearFrame(p, x, y, w, h)
    gp.gearFrame = CreateFrame("Frame", nil, p)
    gp.gearFrame:SetPoint("TOPLEFT", x, y); gp.gearFrame:SetSize(w, h)
    gp.gearBtns = {}
    -- 副本背景图（refreshGear 里按推荐件数最多的副本换）+ 两层暗色：整体压暗，左右两列再压一点给文字
    gp.gearBg = gp.gearFrame:CreateTexture(nil, "BACKGROUND", nil, -8); gp.gearBg:SetAllPoints(); gp.gearBg:SetAlpha(0.85); gp.gearBg:Hide()
    gp.gearShade = gp.gearFrame:CreateTexture(nil, "BACKGROUND", nil, -7); gp.gearShade:SetAllPoints()
    gp.gearShade:SetColorTexture(0, 0, 0, 0.45); gp.gearShade:Hide()
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local s = gp.gearFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
        s:SetPoint("TOP" .. side); s:SetPoint("BOTTOM" .. side); s:SetWidth(230)
        s:SetColorTexture(1, 1, 1, 1)
        local dark, clear = CreateColor and CreateColor(0, 0, 0, 0.55), CreateColor and CreateColor(0, 0, 0, 0)
        if s.SetGradient and dark then
            pcall(s.SetGradient, s, "HORIZONTAL", side == "LEFT" and dark or clear, side == "LEFT" and clear or dark)
        else s:SetColorTexture(0, 0, 0, 0.3) end
    end
    -- 细金边框住整块（和掉落页副本横幅同一个金色）
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
        local l = gp.gearFrame:CreateTexture(nil, "BORDER"); l:SetPoint(e[1]); l:SetPoint(e[2]); l:SetColorTexture(1, 0.82, 0, 0.35)
        if e[3] then l:SetWidth(e[3]) else l:SetHeight(e[4]) end
    end
    gp.gearBgCap = gp.gearFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    gp.gearBgCap:SetPoint("TOP", 0, -2); gp.gearBgCap:SetWordWrap(false); gp.gearBgCap:Hide()
    if gp.gearBgCap.SetFont then pcall(gp.gearBgCap.SetFont, gp.gearBgCap, SUB_FONT, 10, "") end
    gp.gearBgHit = CreateFrame("Button", nil, gp.gearFrame)
    gp.gearBgHit:SetAllPoints(gp.gearBgCap)
    gp.gearBgHit:SetScript("OnEnter", function(self)
        if not gp.gearArtDn then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine(gp.gearBgFull or "", 1, 0.82, 0, true)
        GameTooltip:AddLine(ns.L("点击：去掉落页看这个副本", "Click: open this dungeon on the Loot page"), 0.6, 0.6, 0.6); GameTooltip:Show()
    end)
    gp.gearBgHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    gp.gearBgHit:SetScript("OnClick", function() if gp.gearArtDn and ns.LootShowDungeon then ns.LootShowDungeon(gp.gearArtDn) end end)
    gp.model = buildModel(gp.gearFrame)
    gp.gearNote = gp.gearFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    gp.gearNote:SetPoint("BOTTOMLEFT", 10, 4); gp.gearNote:SetPoint("RIGHT", -10, 0); gp.gearNote:SetJustifyH("CENTER")
    gp.gearNote:SetWordWrap(false)   -- 文字太长就裁掉，⛔不许自动换行把自己顶到图标格子上去
    gp.gearNoteHit = CreateFrame("Frame", nil, gp.gearFrame)
    gp.gearNoteHit:SetPoint("TOPLEFT", gp.gearNote, "TOPLEFT"); gp.gearNoteHit:SetPoint("BOTTOMRIGHT", gp.gearNote, "BOTTOMRIGHT")
    gp.gearNoteHit:EnableMouse(true)
    gp.gearNoteHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ---------- 刷本清单（10-07 用户截图「整个装备刷本规划，列出刷什么本，哪个 BOSS，或者什么任务线」）----------
-- 和「装备」同一套推荐（bestGearBySlot，到范围上限那一级能拿到的最好），换个角度排：
--   副本按等级从低到高 → 每个副本一张卡（副本图 + 等级段 + 几件）→ 首领 → 这个首领掉的推荐装备（部位 · 需要几级）
--   任务线另起一段：任务链名 → 奖励装备。点副本 / 装备跳掉落页那个本；悬停装备 = 原生物品提示
local QCOL = { q2 = "ff1eff00", q3 = "ff0070dd", q4 = "ffa335ee", q5 = "ffff8000" }
local function farmGroups(bySlot, sortBy)
    local dmap, dlist, qmap, qlist, seen = {}, {}, {}, {}, {}
    for _, it in pairs(bySlot) do
        if type(it) == "table" and it.id and not seen[it.id] then
            seen[it.id] = true
            if it.src == "quest" or it.src == "craft" or it.src == "vendor" or it.src == "bis" then   -- 11-23 60 级 BiS 池外件（声望 / 野外 / 世界掉落…）按来源一组
                -- 11-06 制造按专业一组（「制造 · 锻造」）、商人按商人一组（srcName「商人 · 名字 · 地区」），和任务线排在一起（网站同一条）
                local key = (it.src == "craft") and ("制造 · " .. (PROF_NAME[it.pf] and PROF_NAME[it.pf][1] or it.pf or "?"))
                    or (it.src == "bis") and bisSrcText(it.how, it.srcName, it.srcName) or it.srcName or "?"
                if not qmap[key] then qmap[key] = { name = key, items = {}, req = 999, kind = it.src, how = it.how }; qlist[#qlist + 1] = qmap[key] end
                table.insert(qmap[key].items, it); qmap[key].req = math.min(qmap[key].req, it.req or 0)
            else
                local dn = it.dn or "?"
                local boss = (it.srcName or ""):match(" · (.+)$") or ns.L("小怪 / 其他", "Trash / other")
                local d = dmap[dn]
                if not d then d = { name = dn, bosses = {}, blist = {}, req = 999, n = 0 }; dmap[dn] = d; dlist[#dlist + 1] = d end
                if not d.bosses[boss] then d.bosses[boss] = { name = boss, items = {} }; d.blist[#d.blist + 1] = d.bosses[boss] end
                table.insert(d.bosses[boss].items, it)
                d.req = math.min(d.req, it.req or 0); d.n = d.n + 1
            end
        end
    end
    -- 10-08 用户「排序是越多的副本排序最上面」：sortBy = "count" 件数多的在前（同件数再按等级）；"level" 按等级从低到高
    if sortBy == "count" then
        table.sort(dlist, function(a, b)
            if a.n ~= b.n then return a.n > b.n end
            if a.req ~= b.req then return a.req < b.req end
            return a.name < b.name
        end)
    else
        table.sort(dlist, function(a, b) if a.req ~= b.req then return a.req < b.req end return a.name < b.name end)
    end
    table.sort(qlist, function(a, b) if a.req ~= b.req then return a.req < b.req end return a.name < b.name end)
    -- 首领先后：⛔ 原来是 pairs 哈希序（每次可能不一样）→ 10-08 和小程序对口径：首领下最低需要等级 → 名字，小怪组放最后
    local function isTrash(name) return name == "小怪" or name == ns.L("小怪 / 其他", "Trash / other") end
    for _, d in ipairs(dlist) do
        for _, b in ipairs(d.blist) do
            table.sort(b.items, function(x, y)
                if (x.req or 0) ~= (y.req or 0) then return (x.req or 0) < (y.req or 0) end
                return (x.id or 0) < (y.id or 0)
            end)
            b.req = b.items[1] and (b.items[1].req or 0) or 0
        end
        table.sort(d.blist, function(a, b)
            local ta, tb = isTrash(a.name), isTrash(b.name)
            if ta ~= tb then return tb end
            if a.req ~= b.req then return a.req < b.req end
            return a.name < b.name
        end)
    end
    for _, q in ipairs(qlist) do
        table.sort(q.items, function(x, y)
            if (x.req or 0) ~= (y.req or 0) then return (x.req or 0) < (y.req or 0) end
            return (x.id or 0) < (y.id or 0)
        end)
    end
    return dlist, qlist
end
-- 10-07 用户「4-60 似乎只包括了 60 左右的本」：原来只取范围上限那一级的最好装备 → 只剩满级本。
--   改成升级路线：范围内逐级算「这一级能拿到的最好」，凡是哪一级当过最好的都列出来，并记下从几级用到几级
local function farmItems(lo, hi, cls)
    local acc, order = {}, {}
    for L = math.max(1, lo), math.max(lo, hi) do
        for _, it in pairs(bestGearBySlot(L, cls)) do
            if type(it) == "table" and it.id then
                local e = acc[it.id]
                if not e then
                    e = {}
                    for k, v in pairs(it) do e[k] = v end
                    e.useFrom, e.useTo = L, L
                    acc[it.id] = e; order[#order + 1] = e
                else e.useTo = L end
            end
        end
    end
    return order
end
-- 11-06 刷本清单的备选行：范围里每一级的「也可以」制造件并起来（useFrom / useTo 同上，pct = 最后一次当备选时高多少）
local function farmAlts(lo, hi, cls)
    local acc, order = {}, {}
    for L = math.max(1, lo), math.max(lo, hi) do
        local _, _, alts = bestGearBySlot(L, cls)
        local keys = {}
        for k in pairs(alts or {}) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local a = alts[k]
            local e = acc[a.it.id]
            if not e then
                e = { src = "craft" }
                for f, v in pairs(a.it) do e[f] = v end
                e.useFrom = L
                acc[a.it.id] = e; order[#order + 1] = e
            end
            e.useTo, e.pct = L, a.pct
        end
    end
    table.sort(order, function(x, y) if x.useFrom ~= y.useFrom then return x.useFrom < y.useFrom end return x.id < y.id end)
    return order
end
ns.PlanFarmAlts = function(lo, hi, cls) return farmAlts(lo, hi or lo, cls) end
ns.PlanFarmGroups = function(lo, hi, sortBy, cls) return farmGroups(farmItems(lo, hi or lo, cls), sortBy) end   -- 测试 / 三端对拍用
ns.PlanFarmItems = function(lo, hi, cls) return farmItems(lo, hi or lo, cls) end
-- 刷本清单两组筛选（10-08 用户「这里要有能筛选项，筛选当前等级BIS装备清单，然后排序是越多的副本排序最上面」）
--   范围：route = 整段升级路线（lo..hi 每一级当过最好的都列）；bis = 只看 hi 那一级的毕业装备（和「装备」页同一套）
--   排序：count = 件数多的副本在前（默认）；level = 按等级
local function farmOpts()
    local ui = ns.db and ns.db.ui or {}
    return (ui.farmMode == "bis") and "bis" or "route", (ui.farmSort == "level") and "level" or "count"
end

-- 10-08 用户录像 1:45：筛选栏放在滚动内容里，一滚就没了 → 刷本清单时把它挂在滚动区外面、滚动区整体下移让位
local FARM_BAR_H = 28
local function placeScroll(withBar)
    local sf = page.sf
    if not (sf and page.sfY) then return end
    sf:ClearAllPoints()
    sf:SetPoint("TOPLEFT", page.sfX, page.sfY - (withBar and FARM_BAR_H or 0))
    sf:SetHeight(page.sfH - (withBar and FARM_BAR_H or 0))
end

local function refreshFarm(lo, tgt)
    local c = page.child
    if type(rawget(page, "farm")) ~= "table" then page.farm = { rows = {}, cards = {} } end
    local F = page.farm
    for _, r in ipairs(F.rows) do r:Hide() end
    for _, r in ipairs(F.cards) do r:Hide() end
    for _, r in ipairs(page.rows) do r:Hide() end
    local y, nr, ncard = 0, 0, 0
    local mode, sortBy = farmOpts()
    -- 顶上一行筛选：当前选中的按钮按下（禁用 = 「你在这」，和上面视图页签一个规矩）
    if not F.bar then
        local bar = CreateFrame("Frame", nil, page.sf:GetParent()); bar:SetHeight(26)   -- 挂在页面上，不随列表滚动
        bar.lab1 = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); bar.lab1:SetPoint("LEFT", 6, 0); bar.lab1:SetText(ns.L("清单", "List"))
        local function set(k, v) ns.db.ui[k] = v; page.needScroll = true; refresh() end
        bar.route = ns.Button(bar, "", 128, 22, function() set("farmMode", "route") end)
        bar.route:SetPoint("LEFT", bar.lab1, "RIGHT", 6, 0)
        bar.bis = ns.Button(bar, "", 96, 22, function() set("farmMode", "bis") end)
        bar.bis:SetPoint("LEFT", bar.route, "RIGHT", 4, 0)
        bar.lab2 = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); bar.lab2:SetPoint("LEFT", bar.bis, "RIGHT", 16, 0); bar.lab2:SetText(ns.L("排序", "Sort"))
        bar.count = ns.Button(bar, ns.L("件数多的在前", "Most items first"), 104, 22, function() set("farmSort", "count") end)
        bar.count:SetPoint("LEFT", bar.lab2, "RIGHT", 6, 0)
        bar.level = ns.Button(bar, ns.L("按等级", "By level"), 64, 22, function() set("farmSort", "level") end)
        bar.level:SetPoint("LEFT", bar.count, "RIGHT", 4, 0)
        local tips = {
            { bar.route, ns.L("升级路线", "Leveling route"), ns.L("等级范围里每一级「当时能拿到的最好」都列出来，带「用到几级」——一路升级一路换", "Every piece that's the best at some level in the range, with how long you'll use it") },
            { bar.bis, ns.L("毕业装备（BiS）", "Best in slot"), ns.L("只看等级条右端那一级能拿到的最好装备（和「装备」页同一套）。先点「当前等级」再选这个 = 你现在这一级的 BiS", "Only the best gear for the top of the level range (same set as the Gear view). Click \"Current level\" first for your BiS right now") },
            { bar.count, ns.L("排序", "Sort"), ns.L("推荐件数多的副本排在最上面，一趟拿得多", "Dungeons with the most picks on top") },
            { bar.level, ns.L("排序", "Sort"), ns.L("按副本需要的等级从低到高", "By dungeon level, low to high") },
        }
        for _, t in ipairs(tips) do
            local b, title, body = t[1], t[2], t[3]
            b:HookScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(title, 1, 0.82, 0); GameTooltip:AddLine(body, 1, 1, 1, true); GameTooltip:Show()
            end)
            b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        end
        F.bar = bar
    end
    local bar = F.bar
    bar:ClearAllPoints(); bar:SetPoint("TOPLEFT", page.sf:GetParent(), "TOPLEFT", page.sfX or 4, page.sfY or -100); bar:SetWidth(page.sfW or 646); bar:Show()
    placeScroll(true)
    bar.route:SetText(string.format(ns.L("升级路线 %d-%d 级", "Route %d-%d"), lo, tgt))
    bar.bis:SetText(string.format(ns.L("%d 级 BiS", "Lv %d BiS"), tgt))
    bar.route:SetEnabled(mode ~= "route"); bar.bis:SetEnabled(mode ~= "bis")
    bar.count:SetEnabled(sortBy ~= "count"); bar.level:SetEnabled(sortBy ~= "level")
    local function row(h)
        nr = nr + 1
        local r = F.rows[nr]
        if not r then
            r = CreateFrame("Button", nil, c)
            r.ic = r:CreateTexture(nil, "ARTWORK"); r.ic:SetSize(22, 22); r.ic:SetPoint("LEFT", 24, 0); r.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.t:SetJustifyH("LEFT"); r.t:SetWordWrap(false)
            r.s = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.s:SetJustifyH("RIGHT"); r.s:SetWordWrap(false)
            r.s:SetPoint("RIGHT", -8, 0)
            local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            F.rows[nr] = r
        end
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, y); r:SetPoint("RIGHT", c, "RIGHT", 0, 0); r:SetHeight(h)
        r:SetScript("OnClick", nil); r:SetScript("OnEnter", nil)
        y = y - h - 2
        r:Show()
        return r
    end
    local function card(title, sub, art, onClick, dname)
        ncard = ncard + 1
        local r = F.cards[ncard]
        if not r then
            r = CreateFrame("Button", nil, c)
            -- 10-07 用户截图「这个图片丑了点」：整条铺图又糊又变形 → 深色卡 + 左边 84×42 缩略图（按比例裁）+ 金色细边
            r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(0.13, 0.11, 0.08, 0.95)
            r.frame = r:CreateTexture(nil, "BORDER"); r.frame:SetSize(88, 46); r.frame:SetPoint("LEFT", 2, 0); r.frame:SetColorTexture(1, 0.82, 0, 0.55)
            r.img = r:CreateTexture(nil, "ARTWORK"); r.img:SetSize(84, 42); r.img:SetPoint("CENTER", r.frame, "CENTER")
            r.big = r:CreateTexture(nil, "ARTWORK"); r.big:SetSize(38, 38); r.big:SetPoint("CENTER", r.frame, "CENTER")
            r.edge = r:CreateTexture(nil, "OVERLAY"); r.edge:SetPoint("BOTTOMLEFT"); r.edge:SetPoint("BOTTOMRIGHT"); r.edge:SetHeight(1)
            r.edge:SetColorTexture(1, 0.82, 0, 0.35)
            r.t = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); r.t:SetPoint("TOPLEFT", r.frame, "TOPRIGHT", 12, -4); r.t:SetPoint("RIGHT", -10, 0)
            r.t:SetJustifyH("LEFT"); r.t:SetWordWrap(false)
            r.s = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.s:SetPoint("BOTTOMLEFT", r.frame, "BOTTOMRIGHT", 12, 5); r.s:SetPoint("RIGHT", -10, 0)
            -- 10-10「主要是副本任务」：卡片右侧「任务 N」→ 副本任务弹框
            r.dq = ns.Button(r, "", 74, 22, function(self) if self.d then ns.ShowDungeonQuests(self.d, page) end end)
            r.dq:SetPoint("RIGHT", -8, 0)
            r.dq:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:AddLine(ns.L("这个副本的任务：进本前先接好", "Quests for this dungeon: pick them up first"), 1, 1, 1, true)
                GameTooltip:Show()
            end)
            r.dq:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r.s:SetJustifyH("LEFT"); r.s:SetWordWrap(false)
            local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.08)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            F.cards[ncard] = r
        end
        if art and art.banner then
            r.img:SetTexture(art.banner); r.img:SetTexCoord(ns.ArtCoord(art, 84, 42)); r.img:Show(); r.big:Hide()
            r.frame:SetColorTexture(1, 0.82, 0, 0.55)        -- 有图：金色细边
        elseif art then
            r.img:Hide(); r.big:SetTexture(art.icon); r.big:SetTexCoord(unpack(art.iconCoord)); r.big:Show()
            r.frame:SetColorTexture(0.22, 0.18, 0.10, 1)      -- 只有图标：深色底托着，别变成一整块金
        else r.img:Hide(); r.big:Hide(); r.frame:SetColorTexture(0.22, 0.18, 0.10, 1) end
        r.t:SetText(title); r.s:SetText(sub)
        local dq = dname and ns.DQForDungeon and ns.DQForDungeon(dname)
        local nq = 0
        if dq then for _, e in ipairs(ns.DQList(dq)) do if e.s ~= "done" then nq = nq + 1 end end end
        r.dq.d = dq
        r.dq:SetText(ns.L("任务 ", "Quests ") .. nq)
        r.dq:SetShown(dq ~= nil and nq > 0)
        r.t:SetPoint("RIGHT", (dq and nq > 0) and -90 or -10, 0); r.s:SetPoint("RIGHT", (dq and nq > 0) and -90 or -10, 0)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, y - 4); r:SetPoint("RIGHT", c, "RIGHT", 0, 0); r:SetHeight(50)
        r:SetScript("OnClick", onClick)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(title, 1, 0.82, 0); GameTooltip:AddLine(sub, 1, 1, 1, true)
            if onClick then GameTooltip:AddLine(ns.L("点击：去掉落页看这个副本", "Click: open on the Loot page"), 0.6, 0.6, 0.6) end
            GameTooltip:Show()
        end)
        r:Show()
        y = y - 50 - 8
    end
    local function itemRow(it, dn)
        local r = row(26)
        r.ic:SetTexture("Interface\\Icons\\" .. (it.i or "inv_misc_questionmark")); r.ic:Show()
        r.t:ClearAllPoints(); r.t:SetPoint("LEFT", r.ic, "RIGHT", 8, 0); r.t:SetPoint("RIGHT", -170, 0)
        r.t:SetText("|c" .. (QCOL[it.q] or "ffffffff") .. ns.ItemNm(it) .. "|r")
        local span = (it.useFrom and it.useTo and it.useTo < tgt) and string.format(ns.L("　用到 %d 级", "  until %d"), it.useTo) or ""
        r.s:SetText("|cffaaaaaa" .. ns.TD(it.slot or "") .. ((it.type or "") ~= "" and (" · " .. ns.TD(it.type)) or "") .. ns.L("　需要 ", "  req ") .. (it.req or 0) .. ns.L(" 级", "") .. span .. "|r")
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok = pcall(GameTooltip.SetItemByID, GameTooltip, it.id)
            local first = (GameTooltip:NumLines() or 0) > 0 and _G.GameTooltipTextLeft1 and _G.GameTooltipTextLeft1:GetText()
            if not ok or not first or first == "" or first == RETRIEVING_ITEM_INFO then
                if ns.ItemFallbackTip then ns.ItemFallbackTip(it) else GameTooltip:AddLine(ns.ItemNm(it)) end
            end
            GameTooltip:Show()
        end)
        if dn then r:SetScript("OnClick", function() if ns.LootShowDungeon then ns.LootShowDungeon(dn) end end)
        elseif it.src == "craft" or it.src == "vendor" then r:SetScript("OnClick", function() ns.GearGuide(it) end) end
        return r
    end
    local dlist, qlist
    if mode == "bis" then dlist, qlist = farmGroups(bestGearBySlot(tgt), sortBy)
    else dlist, qlist = farmGroups(farmItems(lo, tgt), sortBy) end
    if #dlist == 0 and #qlist == 0 then
        local r = row(28); r.ic:Hide(); r.t:ClearAllPoints(); r.t:SetPoint("LEFT", 10, 0); r.t:SetPoint("RIGHT", -10, 0)
        r.t:SetText("|cff999999" .. ns.L("这个等级范围里还没有推荐装备（往右拖等级条看更高等级）", "No recommended gear in this range") .. "|r"); r.s:SetText("")
    end
    for k, d in ipairs(dlist) do
        local ld = lootDungeonByName(d.name)
        local art = ld and ns.DungeonArt and ns.DungeonArt(ld)
        card(k .. ". " .. ns.TD(d.name), string.format(ns.L("需要 %d 级起 · %d 个首领 · 推荐 %d 件", "From level %d · %d bosses · %d items"), d.req, #d.blist, d.n), art,
            function() if ns.LootShowDungeon then ns.LootShowDungeon(d.name) end end, d.name)
        for _, b in ipairs(d.blist) do
            local r = row(20); r.ic:Hide(); r.t:ClearAllPoints(); r.t:SetPoint("LEFT", 12, 0); r.t:SetPoint("RIGHT", -10, 0)
            r.t:SetText("|cffffd100" .. ns.TD(b.name) .. "|r"); r.s:SetText("")
            for _, it in ipairs(b.items) do itemRow(it, d.name) end
        end
    end
    if #qlist > 0 then
        -- 11-06 制造 / 商人组也挂在这张卡下（一张卡：任务线 + 制造 + 商人）
        local nq, nx = 0, 0
        local nc = 0   -- 11-23 60 级 BiS 池外件（声望 / 野外 / 世界掉落…）
        for _, q in ipairs(qlist) do if (q.kind or "quest") == "quest" then nq = nq + 1 elseif q.kind == "bis" then nc = nc + 1 else nx = nx + 1 end end
        if nc > 0 then
            card(ns.L("任务线 / 制造 / 商人 / 其他来源", "Quests / crafted / vendors / other"),
                string.format(ns.L("%d 条任务线 · %d 组制造 / 商人 · %d 组其他来源（声望 / 野外 / 世界掉落…）", "%d quest chains · %d crafted / vendor · %d other (rep / world…)"), nq, nx, nc),
                { icon = "Interface\\Icons\\INV_Misc_Book_09", iconCoord = { 0.07, 0.93, 0.07, 0.93 } }, nil)
        else
        card(nx > 0 and ns.L("任务线 / 制造 / 商人", "Quests / crafted / vendors") or ns.L("职业任务链", "Class quest chains"),
            nx > 0 and string.format(ns.L("%d 条任务线 · %d 组制造 / 商人", "%d quest chains · %d crafted / vendor groups"), nq, nx)
                or string.format(ns.L("%d 条任务线 · 奖励装备", "%d chains with gear rewards"), #qlist),
            { icon = "Interface\\Icons\\INV_Misc_Book_09", iconCoord = { 0.07, 0.93, 0.07, 0.93 } }, nil)
        end
        for _, q in ipairs(qlist) do
            local r = row(20); r.ic:Hide(); r.t:ClearAllPoints(); r.t:SetPoint("LEFT", 12, 0); r.t:SetPoint("RIGHT", -10, 0)
            local head = (q.kind or "quest") == "quest" and (ns.L("任务：", "Quest: ") .. ns.TD(q.name)) or ns.TD(q.name)
            r.t:SetText("|cff33ff99" .. head .. "|r"); r.s:SetText("")
            for _, it in ipairs(q.items) do itemRow(it, nil) end
        end
    end
    -- 11-06 备选：比推荐分高的制造件（不算进副本 / 任务分组，单列在最后）
    local alts = farmAlts(mode == "bis" and tgt or lo, tgt)
    if #alts > 0 then
        local r = row(20); r.ic:Hide(); r.t:ClearAllPoints(); r.t:SetPoint("LEFT", 12, 0); r.t:SetPoint("RIGHT", -10, 0)
        r.t:SetText("|cff66ccff" .. ns.L("也可以：制造件（分数比推荐高，找人做 / 拍卖行；拾取绑定的要自己会这个专业）",
            "Also: crafted gear that scores higher (crafter / AH; BoP needs the profession)") .. "|r"); r.s:SetText("")
        for _, it in ipairs(alts) do
            local ar = itemRow(it, nil)
            ar.s:SetText((ar.s:GetText() or "") .. "|cff66ccff · " .. profName(it.pf) .. " " .. (it.sk or 0) .. (it.pct and (" +" .. it.pct .. "%") or "") .. "|r")
        end
    end
    c:SetHeight(-y + 8)
end

-- ---------- 副本任务路线（11-04 官方副本任务指南）：当前等级范围内的副本，按等级从低到高 ----------
-- 数据函数（测试 / 三端对拍用）：只列对当前阵营开放的副本；官方清单里能接的任务按副本外 / 副本内分开数
ns.PlanDQRoute = function(lo, hi, all)
    local out = {}
    if not (ns.DQ and ns.DQList) then return out end
    local fac = UnitFactionGroup and UnitFactionGroup("player")
    local mine = (fac == "Alliance" and "A") or (fac == "Horde" and "H") or nil
    for _, d in ipairs(ns.DQ.dungeons) do
        local fits = all or not mine or d.side == "" or d.side == mine
        local nOff, nIn, nOut = 0, 0, 0
        for _, o in ipairs(d.off or {}) do
            if all or not mine or o.s == "" or o.s == mine then
                nOff = nOff + 1
                if o.w == "in" then nIn = nIn + 1 else nOut = nOut + 1 end
            end
        end
        local mineList = ns.DQList(d, all)
        if fits and (#mineList > 0 or nOff > 0) and d.max >= lo and d.min <= hi then
            local nDone = 0
            for _, e in ipairs(mineList) do if e.s == "done" then nDone = nDone + 1 end end
            out[#out + 1] = { d = d, min = d.min, max = d.max, nLocal = #mineList, nDone = nDone, nOff = nOff, nIn = nIn, nOut = nOut }
        end
    end
    table.sort(out, function(a, b)
        if a.min ~= b.min then return a.min < b.min end
        if a.max ~= b.max then return a.max < b.max end
        return a.d.k < b.d.k
    end)
    return out
end

local function dqRouteRow(i)
    if type(rawget(page, "dq")) ~= "table" then page.dq = { rows = {} } end
    local r = page.dq.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, page.child)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(0.13, 0.11, 0.08, 0.95)
    r.edge = r:CreateTexture(nil, "OVERLAY"); r.edge:SetPoint("BOTTOMLEFT"); r.edge:SetPoint("BOTTOMRIGHT"); r.edge:SetHeight(1); r.edge:SetColorTexture(1, 0.82, 0, 0.35)
    r.lv = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); r.lv:SetPoint("LEFT", 10, 0); r.lv:SetWidth(64); r.lv:SetJustifyH("LEFT")
    r.t = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.t:SetPoint("TOPLEFT", 78, -7); r.t:SetPoint("RIGHT", -120, 0); r.t:SetJustifyH("LEFT"); r.t:SetWordWrap(false)
    r.s = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.s:SetPoint("TOPLEFT", 78, -26); r.s:SetPoint("RIGHT", -10, 0); r.s:SetJustifyH("LEFT"); r.s:SetWordWrap(false)
    r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.tag:SetPoint("TOPRIGHT", -10, -9); r.tag:SetJustifyH("RIGHT")
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.08)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.dq.rows[i] = r
    return r
end

local function refreshDQRoute(lo, hi)
    for _, r in ipairs(page.rows) do r:Hide() end
    if type(rawget(page, "dq")) ~= "table" then page.dq = { rows = {} } end
    for _, r in ipairs(page.dq.rows) do r:Hide() end
    local list = ns.PlanDQRoute(lo, hi, false)
    local y = -2
    if #list == 0 then
        local r = dqRouteRow(1)
        r.lv:SetText(""); r.tag:SetText(""); r.s:SetText("")
        r.t:SetText("|cff999999" .. ns.L("这个等级范围里没有适合你阵营的副本任务（往右拖等级条）", "No dungeon quests for your faction in this range") .. "|r")
        r:SetScript("OnClick", nil); r:SetScript("OnEnter", nil)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, y); r:SetPoint("RIGHT", page.child, "RIGHT", 0, 0); r:SetHeight(34); r:Show()
        y = y - 36
    end
    for i, e in ipairs(list) do
        local d, r = e.d, dqRouteRow(i)
        local dn = d.n
        for _, ld in ipairs((ns.Data.loot or {}).dungeons or {}) do
            if ld.nEn == (d.loot or {})[1] then dn = ns.L((ld.n or ""):gsub("：.*$", ""), d.n); break end
        end
        r.lv:SetText("|cffffd100" .. e.min .. "-" .. e.max .. "|r")
        r.t:SetText(dn .. (d.new and ("  |cff33ff99" .. ns.L("新", "New") .. "|r") or ""))
        local ent = ns.DQEntrance and ns.DQEntrance(d)
        local bits = {}
        if e.nOut > 0 then bits[#bits + 1] = ns.L("副本外先接 ", "Pick up outside: ") .. e.nOut end
        if e.nIn > 0 then bits[#bits + 1] = ns.L("副本内 ", "Inside: ") .. e.nIn end
        if e.nLocal > 0 then bits[#bits + 1] = ns.L("已完成 ", "Done ") .. e.nDone .. "/" .. e.nLocal end
        if ent then bits[#bits + 1] = ns.L("入口 ", "Entrance: ") .. (ent.zc or "") end
        if #bits == 0 then bits[1] = ns.L("暂无任务数据", "No quest data") end
        r.s:SetText("|cffbbbbbb" .. table.concat(bits, ns.L("　", "  ")) .. "|r")
        local _, _, warn = ns.DQEntrance(d)
        r.tag:SetText(warn and ("|cffff9966" .. ns.L("有风险", "Risky") .. "|r") or (e.nLocal > 0 and e.nDone == e.nLocal and ("|cff7f7f7f" .. ns.L("全部完成", "All done") .. "|r")) or "")
        r:SetScript("OnClick", function() if ns.ShowDungeonQuests then ns.ShowDungeonQuests(d, page) end end)
        r:SetScript("OnEnter", function(self)
            local en, route, w = ns.DQEntrance(d)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(dn, 1, 0.82, 0)
            GameTooltip:AddLine(string.format(ns.L("等级 %d-%d · 官方指南任务 %d 个（副本外 %d / 副本内 %d）", "Level %d-%d - %d guide quests (%d outside / %d inside)"), e.min, e.max, e.nOff, e.nOut, e.nIn), 1, 1, 1, true)
            if en then
                GameTooltip:AddLine(ns.L("入口：", "Entrance: ") .. (en.zc or "") .. ((en.x and en.x > 0) and string.format(" (%.0f, %.0f)", en.x, en.y) or "") .. ((en.sp and en.sp ~= "") and ("　" .. en.sp) or ""), 0.8, 0.9, 1, true)
            end
            if route then GameTooltip:AddLine(route, 0.85, 0.85, 0.85, true) end
            if w then GameTooltip:AddLine(w, 1, 0.6, 0.4, true) end
            GameTooltip:AddLine(ns.L("点击：看谁给、在哪、前置和奖励", "Click: giver, location, prerequisites and rewards"), 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, y); r:SetPoint("RIGHT", page.child, "RIGHT", 0, 0); r:SetHeight(46); r:Show()
        y = y - 48
    end
    page.child:SetHeight(-y + 8)
end

function refresh()   -- 赋给上面前向声明的 local
    if not page then return end
    local lo, hi = refreshHeader()
    local zoneView=viewMode=="route"
    local focused=zoneView and ns.RouteIsFocused and ns.RouteIsFocused()
    page.rangeBar:SetShown(not focused)
    page.rangeLbl:SetText(focused and ns.L("在下方查询地图等级", "Choose a map level below") or ns.L("等级范围", "Levels"))
    for _,b in pairs(page.quick or {})do b:SetShown(not focused)end
    for _,w in ipairs({page.sortBtn,page.doneBtn,page.baseTxt,page.baseHit})do w:SetShown(not zoneView)end
    if page._sub then page._sub:SetText(ns.EnSafe(zoneView and ns.L("先看当前等级去哪；可查其他等级，或切换完整路线", "Find zones for your level, look ahead or view the full route") or
        ns.L("同一等级看去哪练级、学什么、做什么；点击地图可定位", "Zones and to-dos together by level; click a zone to open its map")))end
    for mode, b in pairs(page.viewBtns or {}) do b:SetEnabled(mode ~= viewMode) end   -- 禁用当前这个当「你在这」标记
    if viewMode ~= "farm" then
        placeScroll(false)
        if type(rawget(page, "farm")) == "table" and rawget(page.farm, "bar") then page.farm.bar:Hide() end
    end
    -- 10-12 第四个视图「路线」（Route.lua，HOLD 期间不进包 → 没有 ns.RefreshRouteView 时这个按钮根本不建）
    if viewMode == "route" and ns.RefreshRouteView then
        page.sf:Hide()
        ns.RefreshRouteView(page, lo, hi)
        return
    end
    if ns.HideRouteView then ns.HideRouteView(page) end
    if viewMode ~= "dq" and type(rawget(page, "dq")) == "table" then
        for _, r in ipairs(page.dq.rows) do r:Hide() end
    end
    if viewMode == "dq" then
        page.sf:Show()
        if type(rawget(page, "farm")) == "table" then
            for _, r in ipairs(page.farm.rows) do r:Hide() end
            for _, r in ipairs(page.farm.cards) do r:Hide() end
        end
        refreshDQRoute(lo, hi)
    elseif viewMode == "farm" then
        page.sf:Show()
        refreshFarm(lo, hi)
    else
        page.sf:Show()
        if type(rawget(page, "farm")) == "table" then
            for _, r in ipairs(page.farm.rows) do r:Hide() end
            for _, r in ipairs(page.farm.cards) do r:Hide() end
            if rawget(page.farm, "bar") then page.farm.bar:Hide() end
        end
        refreshTimeline(lo, hi)
    end
end
ns.RefreshPlanPage = refresh
-- 切视图（/gif route 直达路线用）
function ns.PlanSetView(m) viewMode = m; if page then refresh() end end
-- 别的页跳过来看某一级（专业页「我的时刻表」点节点）：范围设成这一级起 6 级，再打开升级规划
function ns.PlanShowLevel(lv)
    lv = tonumber(lv)
    if not lv then return end
    setRangeRaw(lv, lv + 5)
    if ns.ToggleMain then ns.ToggleMain("plan") end
    if page then refresh() end
end

local function setRange(lo, hi)
    setRangeRaw(lo, hi)
    if page then page.needScroll = true end
    refresh()
end
ns.SetPlanRange = setRange   -- 测试 / 调试用

-- 双拖柄等级范围条（自己画，不用 Slider 模板：两个 Slider 叠放时上面那个会吃掉下面那个的鼠标，
-- 而且不确定无限客户端带 OptionsSliderTemplate）。按下时离哪个拖柄近就拖哪个，拖动中数字实时变，松手才刷新列表。
local function buildRangeBar(p, x, y, w)
    local bar = CreateFrame("Frame", nil, p)
    bar:SetPoint("TOPLEFT", x, y); bar:SetSize(w, 22); bar:EnableMouse(true)
    local PAD = 8
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", PAD, 0); track:SetPoint("RIGHT", -PAD, 0); track:SetHeight(4); track:SetColorTexture(0.25, 0.25, 0.3, 1)
    local fill = bar:CreateTexture(nil, "BORDER"); fill:SetHeight(4); fill:SetColorTexture(1, 0.82, 0.1, 0.9)
    local function handle()
        local h = bar:CreateTexture(nil, "ARTWORK"); h:SetSize(10, 18); h:SetColorTexture(1, 0.9, 0.5, 1)
        local t = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); t:SetPoint("BOTTOM", h, "TOP", 0, 1)
        return h, t
    end
    bar.hLo, bar.tLo = handle()
    bar.hHi, bar.tHi = handle()
    bar.lo, bar.hi = 1, 60
    local function px(v) return PAD + (v - 1) / 59 * (w - 2 * PAD) end
    function bar:SetValues(lo, hi)
        self.lo, self.hi = lo, hi
        self.hLo:ClearAllPoints(); self.hLo:SetPoint("CENTER", self, "LEFT", px(lo), 0)
        self.hHi:ClearAllPoints(); self.hHi:SetPoint("CENTER", self, "LEFT", px(hi), 0)
        fill:ClearAllPoints(); fill:SetPoint("LEFT", self, "LEFT", px(lo), 0); fill:SetWidth(math.max(1, px(hi) - px(lo)))
        self.tLo:SetText(lo); self.tHi:SetText(lo == hi and "" or hi)
    end
    local function cursorVal()
        local cx = GetCursorPosition() / bar:GetEffectiveScale() - (bar:GetLeft() or 0)
        return clampLv(1 + (cx - PAD) / (w - 2 * PAD) * 59)
    end
    bar:SetScript("OnMouseDown", function(self)
        local v = cursorVal()
        -- 离哪个拖柄近拖哪个；两个重叠时往右点拖右柄、往左点拖左柄
        if math.abs(v - self.lo) < math.abs(v - self.hi) or (self.lo == self.hi and v < self.lo) then self.drag = "lo" else self.drag = "hi" end
        self:SetScript("OnUpdate", function(s2)
            local nv = cursorVal()
            if s2.drag == "lo" then s2:SetValues(math.min(nv, s2.hi), s2.hi) else s2:SetValues(s2.lo, math.max(nv, s2.lo)) end
        end)
    end)
    bar:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil); self.drag = nil
        setRange(self.lo, self.hi)
    end)
    bar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine(ns.L("等级范围", "Level range"), 1, 0.82, 0)
        GameTooltip:AddLine(ns.L("拖左边定最低等级，拖右边定最高等级；两个都拖 = 只看中间一段。比你现在低的等级也能看（补学漏掉的技能）。",
            "Drag the left handle for the lowest level, the right one for the highest; drag both to see a middle band. Levels below yours are shown too (catch up on missed spells)."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return bar
end

local function build(p)
    page = p
    ns.PlanPage = p   -- 测试 / 调试用（照 PageMacro.lua 的 ns.MacroPage 先例）
    ns.PageHeader(p, ns.L("升级规划", "Leveling plan"),
        ns.L("拖等级范围，看这几级要点哪些天赋、学什么技能、导哪些宏——点行看任务链来源", "Drag the level range to see talents, trainer spells and macros for those levels"))
    page.rangeLbl = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    page.rangeLbl:SetPoint("TOPLEFT", 12, -50); page.rangeLbl:SetText(ns.L("等级范围", "Levels"))
    page.rangeBar = buildRangeBar(p, 80, -44, 270)   -- 10-07 加了第三个视图「刷本清单」，等级条缩短给按钮让位
    local x = 350
    -- 时间轴 / 装备 页签（10-07 用户「装备最好是类似 C 键用户栏那种展示」），共用上面这套等级控件
    page.viewBtns = {}
    local vx = x + 14
    -- ⛔ 10-07 用户「时间轴是啥」：名字看不懂 → 「要做的事」，并挂悬浮说明
    local VIEW_TIP = {
        timeline = ns.L("按等级列出从现在到目标等级要做的事：点哪个天赋、找训练师学什么技能、导哪些宏、接哪些解锁技能的任务。",
            "Everything to do from now to the target level, by level: talents to pick, trainer spells, macros to import, quests that unlock abilities."),
        farm = ns.L("等级范围内一路升级的刷本路线：每一级能拿到的最好装备都列出来（从几级用到几级），按副本从低到高排：先刷哪个本、打哪个首领、拿哪件；任务线单独列。",
            "The recommended gear as a farming route: which dungeon, which boss, which item; quest chains listed separately."),
    }
    -- 10-18「装备」视图搬去「装备」大类自己的页签（PagePlan 末尾 key = "gear"），这里只剩地图待办 / 刷本清单 / 路线
    local views = { { "timeline", ns.L("地图待办", "Plan") }, { "farm", ns.L("刷本清单", "Farm list") }, { "dq", ns.L("副本任务", "Dungeon quests") } }
    VIEW_TIP.dq = ns.L("按等级从低到高列出这个等级范围内你阵营能去的副本：哪些任务要在副本外先接、入口在哪怎么走、有没有风险；点一行看任务详情（官方副本任务指南）。",
        "Dungeons for your faction in the level range, low to high: which quests to pick up outside, where the entrance is and how to get there; click for quest details (official guide).")
    VIEW_TIP.timeline = ns.L("地图与待办合在一条等级时间线：先看去哪练级，再看天赋、技能、宏和副本任务。地图按当前角色阵营种族推荐，切换等级范围一起更新。",
        "Zones and to-dos share a level timeline. Recommendations use your character's faction and race; changing the range updates both.")
    if ns.RefreshRouteView then
        views[#views + 1] = { "route", ns.L("路线总览", "Routes") }
        VIEW_TIP.route = ns.L("按当前等级查看可选练级区域和下一段；可手动查 1-60 级、切阵营种族、查看完整路线，点击区域打开地图。",
            "Find zones for your level and the next stage. Look up levels 1-60, switch faction/race, or view the full route. Click a zone to open its map.")
    end
    for _, v in ipairs(views) do
        local b = ns.Button(p, v[2], 68, 22, function()
            viewMode = v[1]; page.needScroll = true
            if viewMode == "route" and ns.RouteSetMode then ns.RouteSetMode("all") else refresh() end
        end)
        b:SetPoint("TOPLEFT", vx, -40); vx = vx + 70
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(v[2], 1, 0.82, 0)
            GameTooltip:AddLine(VIEW_TIP[v[1]], 1, 1, 1, true); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        page.viewBtns[v[1]] = b
    end
    -- 第二行：快捷范围 + 排序 + 你现在几级（10-07 用户：原「调到当前等级」并进「当前等级」）
    local qx = 12
    local function tip(b, title, body)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(title, 1, 0.82, 0)
            GameTooltip:AddLine(body, 1, 1, 1, true); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    page.quick = {}
    for _, q in ipairs({
        { "now", ns.L("当前等级", "My level"), 70, function(c) return c, c end, ns.L("只看你现在这一级要做的事", "Only your current level") },
        { "next10", ns.L("接下来 10 级", "Next 10"), 90, function(c) return c, c + 10 end, ns.L("从现在到往后 10 级", "From now to 10 levels ahead") },
        { "max", ns.L("到满级", "To 60"), 64, function(c) return c, 60 end, ns.L("从现在一直到 60 级", "From now to level 60") },
        { "all", ns.L("全部", "All"), 50, function() return 1, 60 end, ns.L("1 到 60 级全部列出，包括已经过去的等级（看有没有漏学）", "Levels 1 to 60, including past levels (spot missed spells)") },
    }) do
        local b = ns.Button(p, q[2], q[3], 22, function() setRange(q[4](curLv())) end)
        b:SetPoint("TOPLEFT", qx, -70); qx = qx + q[3] + 4
        tip(b, q[2], q[5])
        page.quick[q[1]] = b
    end
    page.sortBtn = ns.Button(p, "", 76, 22, function()
        ns.db.ui.planDesc = not ns.db.ui.planDesc
        page.needScroll = true
        refresh()
    end)
    page.sortBtn:SetPoint("TOPLEFT", qx + 8, -70)
    tip(page.sortBtn, ns.L("排序", "Sort"), ns.L("按等级从低到高 / 从高到低切换", "Toggle level order low-to-high / high-to-low"))
    page.doneBtn = ns.Button(p, "", 84, 22, function()
        ns.db.ui.planHideDone = not ns.db.ui.planHideDone
        page.needScroll = true
        refresh()
    end)
    page.doneBtn:SetPoint("LEFT", page.sortBtn, "RIGHT", 4, 0)
    tip(page.doneBtn, ns.L("筛选", "Filter"), ns.L("隐藏已经学会的技能、已经过去的任务；再点一下全部显示", "Hide spells you already know and past quests; click again to show all"))
    page.baseTxt = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.baseTxt:SetPoint("LEFT", page.doneBtn, "RIGHT", 10, 0)
    page.baseTxt:SetPoint("RIGHT", -12, 0); page.baseTxt:SetJustifyH("LEFT"); page.baseTxt:SetWordWrap(false)
    -- 这一行可能被截断 → 悬停看全文（用户硬规定：显示不全一律挂 tooltip）
    local baseHit = CreateFrame("Frame", nil, p)
    baseHit:SetPoint("TOPLEFT", page.baseTxt, "TOPLEFT", 0, 4); baseHit:SetPoint("BOTTOMRIGHT", page.baseTxt, "BOTTOMRIGHT", 0, -4)
    baseHit:EnableMouse(true)
    baseHit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine(page.baseFull or "", 1, 1, 1, true); GameTooltip:Show()
    end)
    baseHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.baseHit = baseHit
    local sf, c = ns.Scroll(p, 4, -100, 646, 474 - 100 - 8)
    page.sfX, page.sfY, page.sfW, page.sfH = 4, -100, 646, 474 - 100 - 8   -- 刷本清单的固定筛选栏要让位（placeScroll）
    page.child, page.rows, page.sf = c, {}, sf
end

ns.RegisterPage({ key = "plan", order = 1.8, title = ns.L("升级规划", "Leveling plan"), icon = "Interface\\Icons\\Ability_Hunter_Pathfinding",
    build = build, refresh = function() if page then page.needScroll = true end; refresh() end })

-- 宏放上 / 拖下动作条、建 / 删宏：页面开着就刷新一下宏那几行的状态（0.3 秒内合并，拖动时这两个事件很密）
-- ⛔ 注册前先问客户端认不认识这个事件（无限客户端缺事件时 RegisterEvent 直接报错）
do
    local ev, pending = CreateFrame("Frame"), false
    for _, e in ipairs({ "ACTIONBAR_SLOT_CHANGED", "UPDATE_MACROS" }) do
        local valid = not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e)
        if valid then pcall(ev.RegisterEvent, ev, e) end
    end
    ev:SetScript("OnEvent", function()
        if pending or not page or not page:IsShown() then return end
        pending = true
        C_Timer.After(0.3, function() pending = false; if page and page:IsShown() then refresh() end end)
    end)
end

-- ---------- 「装备」页签（10-18 用户截图「这个往外提一个标签页出来」：原升级规划里的「装备」视图）----------
-- 放在左栏「装备」大类第一个（UI.lua GROUPS grp_gear）。没有升级规划的等级范围条了 → 自己一行「目标等级」：
--   默认跟着你当前等级走（db 里不存），点 -/+ 或快捷按钮才记一个固定等级；点「当前等级」恢复跟随。
local function gearTarget()
    local v = ns.db and ns.db.ui and ns.db.ui.gearTgt
    return v and clampLv(v) or clampLv(curLv())
end

local function refreshGearPage()
    if not gp.page then return end
    local t, cur = gearTarget(), clampLv(curLv())
    gp.tgtTxt:SetText(t)
    local hint
    if t == cur then hint = ns.L("= 你现在的等级（升级后自动跟着变）", "= your level (follows as you level)")
    elseif t > cur then hint = string.format(ns.L("比你现在高 %d 级", "%d levels above you"), t - cur)
    else hint = string.format(ns.L("比你现在低 %d 级", "%d levels below you"), cur - t) end
    gp.hint:SetText(ns.EnSafe(hint))
    gp.minus:SetEnabled(t > 1); gp.plus:SetEnabled(t < 60)
    if gp.specBtn then
        local SG, cls = ns.SpecGear, myClass()
        if SG and SG.Available() and #SG.Specs(cls) > 0 then
            local cur = SG.Current(cls)
            local si = SG.SpecInfo(cls, cur)
            -- 10-18 用户截图：全名「野德（猫，输出）（自动）」撑出按钮 → 短名 + 按字宽定按钮宽（全名在悬停里）
            gp.specBtn:SetText(ns.L("天赋：", "Spec: ") .. (si and ns.L(si.s or si.zh, si.sEn or si.en) or "?")
                .. (SG.Picked(cls) and "" or ns.L(" · 自动", " · auto")))
            local fs = gp.specBtn.GetFontString and gp.specBtn:GetFontString()
            local tw = fs and fs.GetStringWidth and fs:GetStringWidth()
            if tw and tw > 0 then gp.specBtn:SetWidth(math.max(96, math.min(170, math.floor(tw + 30)))) end
            gp.specBtn:Show()
        else
            gp.specBtn:Hide()
        end
    end
    refreshGear(t)   -- 到这一级能拿到的最好
end
ns.RefreshGearPage = refreshGearPage

local function setGearTarget(v)
    ns.db.ui.gearTgt = v and clampLv(v) or nil
    if ns.db.ui.gearTgt == clampLv(curLv()) then ns.db.ui.gearTgt = nil end   -- 和当前等级一样 = 跟随
    refreshGearPage()
end
ns.SetGearTarget = setGearTarget

local function buildGearPage(p)
    gp.page = p
    ns.GearPage = gp   -- 测试 / 调试用
    ns.PageHeader(p, ns.L("推荐装备", "Gear picks"),
        ns.L("像 C 键角色栏那样，按部位摆出到目标等级能拿到的最好装备：按你的天赋看属性（地下城掉落 + 职业任务链 + 制造 + 商人）", "Best gear per slot you can get by the target level, weighted for your spec (dungeon drops, class quest chains, crafted, vendors)"))
    local lbl = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", 12, -48); lbl:SetText(ns.L("目标等级", "Target level"))
    gp.minus = ns.Button(p, "-", 24, 22, function() setGearTarget(gearTarget() - 1) end)
    gp.minus:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
    gp.tgtTxt = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    gp.tgtTxt:SetPoint("LEFT", gp.minus, "RIGHT", 4, 0); gp.tgtTxt:SetWidth(30); gp.tgtTxt:SetJustifyH("CENTER")
    gp.plus = ns.Button(p, "+", 24, 22, function() setGearTarget(gearTarget() + 1) end)
    gp.plus:SetPoint("LEFT", gp.tgtTxt, "RIGHT", 4, 0)
    gp.quick = {}
    local prev, first = gp.plus, true
    for _, q in ipairs({
        { "now", ns.L("当前等级", "My level"), 70, function() return nil end, ns.L("看你现在这一级能穿的最好装备；之后升级会自动跟着变", "Best gear for your current level; follows you as you level") },
        { "p5", ns.L("+5 级", "+5"), 52, function() return curLv() + 5 end, ns.L("看 5 级后能拿到的最好装备", "Best gear 5 levels from now") },
        { "p10", ns.L("+10 级", "+10"), 56, function() return curLv() + 10 end, ns.L("看 10 级后能拿到的最好装备", "Best gear 10 levels from now") },
        { "max", ns.L("60 级", "60"), 52, function() return 60 end, ns.L("看满级能拿到的最好装备", "Best gear at level 60") },
    }) do
        local b = ns.Button(p, q[2], q[3], 22, function() setGearTarget(q[4]()) end)
        b:SetPoint("LEFT", prev, "RIGHT", first and 14 or 4, 0); prev, first = b, false
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(q[2], 1, 0.82, 0)
            GameTooltip:AddLine(q[5], 1, 1, 1, true); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        gp.quick[q[1]] = b
    end
    -- 10-18 按天赋挑：点一下换下一套（自动 → 各天赋 → 自动），按角色存
    gp.specBtn = ns.Button(p, ns.L("天赋：自动", "Spec: auto"), 170, 22, function()
        local SG, cls = ns.SpecGear, myClass()
        local keys = { "auto" }
        for _, sp in ipairs(SG.Specs(cls)) do keys[#keys + 1] = sp.k end
        local cur = SG.Picked(cls) or "auto"
        local nxt = keys[1]
        for i, k in ipairs(keys) do if k == cur then nxt = keys[i % #keys + 1] end end
        SG.Set(cls, nxt)
        refreshGearPage()
    end)
    gp.specBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, -46)
    gp.specBtn:SetScript("OnEnter", function(self)
        local SG, cls = ns.SpecGear, myClass()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine(ns.L("按天赋挑装备", "Gear by spec"), 1, 0.82, 0)
        GameTooltip:AddLine(ns.L("每个天赋看重的属性不同（野德要敏捷力量，奶德要治疗智力）。默认按你点数最多的那一系自动选，点这里可以手动换。",
            "Each spec values different stats. By default the spec follows your most-invested talent tree; click to switch."), 1, 1, 1, true)
        local auto = SG.AutoSpec(cls)
        for _, sp in ipairs(SG.Specs(cls)) do
            local mark = (sp.k == SG.Current(cls)) and "|cff33ff99> |r" or "   "
            GameTooltip:AddLine(mark .. ns.L(sp.zh, sp.en) .. (sp.k == auto and ns.L("  |cff888888自动识别|r", "  |cff888888auto|r") or ""), 0.9, 0.9, 0.9)
        end
        GameTooltip:Show()
    end)
    gp.specBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    gp.hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    gp.hint:SetPoint("LEFT", prev, "RIGHT", 10, 0)
    gp.hint:SetPoint("RIGHT", gp.specBtn, "LEFT", -8, 0); gp.hint:SetJustifyH("LEFT"); gp.hint:SetWordWrap(false)
    buildGearFrame(p, 4, -76, 646, 474 - 76 - 8)
end

ns.RegisterPage({ key = "gear", order = 1.95, title = ns.L("推荐装备", "Gear picks"), tabTitle = ns.L("推荐装备", "Gear picks"),
    icon = "Interface\\Icons\\INV_Chest_Plate03", build = buildGearPage, refresh = refreshGearPage })

-- 换装备 / 升级：纸娃娃上「已穿 / 可升级」角标和跟随等级要跟着变
do
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP" }) do
        local valid = not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e)
        if valid then pcall(ev.RegisterEvent, ev, e) end
    end
    ev:SetScript("OnEvent", function()
        if gp.page and gp.page:IsShown() then C_Timer.After(0.3, function() if gp.page:IsShown() then refreshGearPage() end end) end
    end)
end
