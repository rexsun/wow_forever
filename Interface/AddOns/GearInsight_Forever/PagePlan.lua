-- 升级规划页（10-07 用户「天赋都引入升级规划…升到多少级，对当前已有的天赋点、技能、宏，以及装备实现最优配置。
--   详细展示任务链或者来源，点了弹出…装备最好是类似用户 C 键的用户栏那种展示」）：
-- 「要做的事」页签（原名「时间轴」，10-07 用户看不懂改名）：按等级顺序列出这期间要做的事——天赋怎么加点、去训练师学什么新技能、该导入哪些宏、
--   哪些技能是打任务解锁的（点开看完整任务链：谁给、在哪、目标是什么）。
-- 「装备」页签：仿 C 键纸娃娃布局，每个部位按目标等级推荐一件装等最高的候选（地下城掉落 + 职业任务链套装）。
--   ⛔ 装备来源 = 地下城掉落（经典 25 本 + 无限新本）+ 职业任务链套装，野外任务奖励还没收——
--   查不到候选的部位显示「待补」，不装样子说全；天赋「对练级最优」复用热门配点数据，不是专门算的练级权重。
local _, ns = ...

local page
local ICON = { quest = "Interface\\Icons\\INV_Misc_Book_09", spell = "Interface\\Icons\\INV_Misc_Note_01",
    talent = "Interface\\Icons\\Spell_Nature_InnerSerenity", macro = "Interface\\Icons\\INV_Scroll_05" }
local QCOLOR = { q1 = "ffffff", q2 = "1eff00", q3 = "0070dd", q4 = "a335ee", q5 = "ff8000" }
local viewMode = "timeline"   -- "timeline" | "gear"（10-07 用户「装备最好是类似 C 键用户栏那种展示」）
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
local ORDER = { zone = 0, quest = 1, talent = 2, spell = 3, macro = 4, dquest = 5 }
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
    for _, s in ipairs((ns.Data.spells or {})[cls] or {}) do
        if s.lv >= lo and s.lv <= hi then
            if s.quest then
                items[#items + 1] = { lv = s.lv, kind = "quest", n = s.n, st = s.lv < cur and "done" or (s.lv == cur and "now" or "future") }
            else
                local known = spellKnown(s.id)
                -- 天赋系技能（s.tal）没学会多半是没点那个天赋，不算「漏学」
                local st = known and "done" or (s.tal and known == false and s.lv <= cur and "tal")
                    or (s.lv < cur and known == false and "missed") or (s.lv <= cur and "now") or "future"
                local rk, rkMax, nextLv = rankOf(ranks, s.n, s.lv)
                items[#items + 1] = { lv = s.lv, kind = "spell", n = s.n, i = s.i, auto = s.auto, d = s.d, st = st, tal = s.tal,
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
    -- 10-07 用户「加个筛选，完成的可以过滤掉」：隐藏已学会的技能 / 已过的任务（分组跟着没了）
    local hidden = 0
    if ns.db.ui.planHideDone then
        local keep = {}
        for _, it in ipairs(items) do
            if it.st == "done" then hidden = hidden + 1 else keep[#keep + 1] = it end
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

-- 每个格子按目标等级能拿到的装等最高的候选（地下城掉落 + 职业任务链套装）；
-- ⛔ 来源不全（地下城 + 任务链套装，野外任务奖励没收），查不到的格子返回 nil，悬停说明「待补」
local function bestGearBySlot(targetLv, cls)
    cls = cls or myClass()
    local pool = {}
    for _, it in ipairs((ns.Data.gear or {})[cls] or {}) do
        local req = (it.req and it.req > 0) and it.req or (it.min or 0)
        if req <= targetLv then
            pool[it.slot] = pool[it.slot] or {}
            table.insert(pool[it.slot], it)
        end
    end
    -- ⛔ 10-08：装等相同时按物品 ID 定死先后（Lua 排序不稳定，平手会随机挑；网站 / 小程序读的导出结果要和这里逐件一致）
    for _, lst in pairs(pool) do table.sort(lst, function(a, b)
        if (a.ilvl or 0) ~= (b.ilvl or 0) then return (a.ilvl or 0) > (b.ilvl or 0) end
        if (a.id or 0) ~= (b.id or 0) then return (a.id or 0) < (b.id or 0) end
        return (a.srcName or "") < (b.srcName or "")   -- 同一件多个首领都掉：按来源名定死
    end) end
    local function pick(slotCn, skipId)
        for _, it in ipairs(pool[slotCn] or {}) do if it.id ~= skipId then return it end end
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
    out.main = pick("武器")
    out.off = not (out.main and out.main.two) and pick("副手") or nil
    out.ranged = pick("远程")
    return out
end
-- 测试 / 导出对拍用：某职业某一级每格选哪件（槽位键 → 物品 ID）。网站 / 小程序读 gear.json 里同一份结果（gi_forever_web_export.py）
ns.PlanBestGear = function(lv, cls)
    local r = {}
    for k, it in pairs(bestGearBySlot(lv, cls)) do if type(it) == "table" then r[k] = it.id end end
    return r
end

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

local STATE_TXT = {
    done = { "|cff808080", ns.L("已学 / 已过", "done") },
    missed = { "|cffff4040", ns.L("漏学", "missed") },
    now = { "|cff33ff99", ns.L("现在就能做", "do it now") },
}

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
        r.btn:Hide(); r.lvTag:SetText("")
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
        if it.kind ~= "zone" then perLv[it.lv] = (perLv[it.lv] or 0) + 1 end
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
            r.s:SetText(e.lo .. "-" .. e.hi .. ns.L(" 级参考 · 按任务和位置选择，无需每张都去", " suggested levels; choose by quests and location"))
            r.btn:SetText(ns.L("打开地图", "Open map")); r.btn:Show()
            local function open() if ns.OpenRouteMap then ns.OpenRouteMap(z.m) end end
            r.btn:SetScript("OnClick", open); r:SetScript("OnClick", open)
            r:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(ns.L(z.zh, z.en), 1, 0.82, 0)
                GameTooltip:AddLine(r.s:GetText(), 1, 1, 1, true)
                if e.primary then GameTooltip:AddLine(ns.L(e.stage.zh, e.stage.en), 1, 1, 1, true) end
                GameTooltip:AddLine(ns.L(e.stage.src == "fv" and "公开路线建议；非地图准入限制。" or "经典基线参考，Beta 可能调整；非准入限制。",
                    e.stage.src == "fv" and "Published route suggestion, not an entry restriction." or "Classic baseline; beta may change. Not an entry restriction."), 0.7, 0.7, 0.7, true)
                GameTooltip:Show()
            end)
        elseif it.kind == "quest" then
            r.ic:SetTexture(ICON.quest)
            r.t:SetText("|cff33ff99" .. ns.L("任务解锁：", "Quest-unlocked: ") .. "|r" .. it.n)
            r.s:SetText(ns.L("点击看完整任务链（谁给 / 在哪 / 目标）", "Click for the full chain (giver / location / objective)") .. suffix)
            r:SetScript("OnClick", function() showQuestPop(it.n) end)
            r:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(it.n, 1, 0.82, 0)
                GameTooltip:AddLine(ns.L("打任务解锁的技能，没有训练师条目", "Unlocked by a quest chain, no trainer entry"), 1, 1, 1, true)
                GameTooltip:Show()
            end)
        elseif it.kind == "spell" then
            r.ic:SetTexture((it.i and it.i ~= "") and ("Interface\\Icons\\" .. it.i) or ICON.spell)
            local rankTxt = it.rank and ("  |cff9d9d9d" .. ns.L("等级 ", "Rank ") .. it.rank .. "|r") or ""
            r.t:SetText((state == "done" and "|cff808080" or "") .. it.n .. (state == "done" and "|r" or "") .. rankTxt)
            r.s:SetText((it.tal and ns.L("天赋技能：要先点对应天赋", "Talent ability: needs the talent first")
                or it.auto and ns.L("自动学会", "Learned automatically") or ns.L("去职业训练师那里学", "Learn from your class trainer")) .. suffix)
            r.ic:SetDesaturated(state == "done")
            r:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(it.n, 1, 0.82, 0)
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
            r.t:SetText("|cff66ccff" .. ns.L("天赋：", "Talent: ") .. "|r" .. st.name)
            r.s:SetText(st.tree .. (st.avail and ("　|cff33ff99" .. ns.L("现在就能点", "available now") .. "|r") or ""))
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
    local ilvl = GetItemInfo and select(4, GetItemInfo(link))
    return { id = id, ilvl = ilvl }
end

local function getSlotBtn(key)
    local b = page.gearBtns[key]
    if b then return b end
    b = CreateFrame("Button", nil, page.gearFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
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
    b.name = page.gearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.sub = page.gearFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    for _, fs in ipairs({ b.name, b.sub }) do
        fs:SetWordWrap(false)
        if fs.SetShadowOffset then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1) end   -- 压在副本背景图上也看得清
    end
    -- 第二行小一号：10-08 截图里「装等 37 · 需要 32 级 · …」来源被截掉了
    if b.sub.SetFont then pcall(b.sub.SetFont, b.sub, SUB_FONT, 10, "") end
    -- 文字区也能悬停 / 点击（字可能被截断 → 悬停看全文，用户硬规定）
    b.hit = CreateFrame("Button", nil, page.gearFrame)
    b.hit:SetScript("OnEnter", function() local f = b:GetScript("OnEnter"); if f then f(b) end end)
    b.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b.hit:SetScript("OnClick", function() local f = b:GetScript("OnClick"); if f then f(b) end end)
    page.gearBtns[key] = b
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
        local eq = equipped(invName)
        b.cmp = nil
        if eq and eq.id == it.id then
            b.cmp = "worn"; b.badge:SetTexture(CHECK_ICON); b.badge:Show()
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
            b.name:SetText("|cff" .. (QCOLOR[it.q] or "ffffff") .. (it.n or "?") .. "|r")
            local src = (it.src == "quest") and ns.L("任务", "Quest") or (it.dn or "")
            local sub = "|cffd8c79a" .. ns.L("装等 ", "ilvl ") .. (it.ilvl or 0) .. "|r|cff999999" .. ns.L(" · ", " · req ") .. req .. ns.L(" 级", "")
            if src ~= "" then sub = sub .. " · " .. src end
            sub = sub .. "|r"
            if b.cmp == "worn" then sub = "|cff66ff66" .. ns.L("已穿 · ", "worn · ") .. "|r" .. sub
            elseif b.cmp == "up" then sub = "|cff66ff66" .. ns.L("可升级 · ", "upgrade · ") .. "|r" .. sub end
            b.sub:SetText(sub)
        elseif g[1] == "off" and mainTwo then
            b.name:SetText("|cff777777" .. ns.L("副手", "Off hand") .. "|r"); b.sub:SetText(ns.L("主手是双手武器", "Two-handed main hand"))
        elseif not g[2] then
            b.name:SetText("|cff777777" .. (g[1] == "shirt" and ns.L("衬衣", "Shirt") or ns.L("战袍", "Tabard")) .. "|r"); b.sub:SetText(ns.L("外观，不推荐", "Cosmetic"))
        else
            b.name:SetText("|cff777777" .. g[2] .. "|r"); b.sub:SetText(ns.L("暂无推荐", "No pick yet"))
        end
    end
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
                    GameTooltip:AddLine("|cff" .. (QCOLOR[it.q] or "ffffff") .. it.n .. "|r")
                    GameTooltip:AddLine((it.slot or "") .. ((it.type and it.type ~= "") and (" · " .. it.type) or "") .. ns.L("　装等 ", "  ilvl ") .. (it.ilvl or 0), 0.8, 0.8, 0.8)
                end
            end
            GameTooltip:AddLine(" ")
            local req = (it.req and it.req > 0) and it.req or (it.min or 0)
            -- 10-07 用户截图：「GI 掉落：哀嚎洞穴 · 斯卡姆」和「GearInsight 需要 17 级 · 掉落 · 哀嚎洞穴 · 斯卡姆」重复 →
            --   掉落来源交给全局物品提示那一行（PageLoot），这里只补任务来源
            if it.src == "quest" then
                GameTooltip:AddLine("|cff33ff99GI|r " .. ns.L("需要 ", "Req ") .. req .. ns.L(" 级 · 任务：", " · Quest: ") .. (it.srcName or ""), 1, 0.82, 0.4, true)
            elseif rawget(GameTooltip, "__gifItem") ~= it.id then   -- 全局那行没加上（物品没缓存、走了简版）才补
                GameTooltip:AddLine("|cff33ff99GI|r " .. ns.L("需要 ", "Req ") .. req .. ns.L(" 级 · 掉落：", " · Drops: ") .. (it.srcName or ""), 1, 0.82, 0.4, true)
            end
            if self.cmp == "worn" then GameTooltip:AddLine(ns.L("你已经穿着这件", "You're wearing this"), 0.4, 1, 0.4)
            elseif self.cmp == "up" then GameTooltip:AddLine(ns.L("比你身上这格好（装等更高）", "Upgrade over what you wear (higher ilvl)"), 0.4, 1, 0.4)
            elseif self.cmp == "down" then GameTooltip:AddLine(ns.L("不如你身上这格", "Worse than what you wear"), 0.6, 0.6, 0.6) end
            if it.src ~= "quest" then GameTooltip:AddLine(ns.L("点击：去掉落页看这个副本", "Click: open this dungeon on the Loot page"), 0.6, 0.6, 0.6) end
        elseif g[1] == "off" and mainTwo then
            GameTooltip:AddLine(ns.L("副手", "Off hand"), 1, 0.82, 0)
            GameTooltip:AddLine(ns.L("推荐的主手是双手武器，副手用不上", "The main-hand pick is two-handed, so no off hand"), 0.8, 0.8, 0.8, true)
        elseif not g[2] then
            GameTooltip:AddLine(ns.L("衬衣 / 战袍只是外观，不推荐", "Shirt / tabard are cosmetic, no recommendation"), 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine(g[2], 1, 0.82, 0)
            GameTooltip:AddLine(ns.L("这个部位目前查不到候选——装备来源是地下城掉落 + 职业任务链套装，野外任务奖励还没收",
                "No candidate for this slot yet — sources are dungeon drops plus class quest-chain sets; open-world quest rewards are not included yet"), 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnClick", function()
        if it and it.src ~= "quest" and it.dn and ns.LootShowDungeon then ns.LootShowDungeon(it.dn) end
    end)
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
    local m = page.model
    if not m then return end
    pcall(m.SetUnit, m, "player")
    if m.TryOn then
        if m.Dress then pcall(m.Dress, m) end
        for _, it in pairs(bySlot) do pcall(m.TryOn, m, "item:" .. it.id) end
    end
end

local function refreshGear(tgt)
    local bySlot = bestGearBySlot(tgt)
    local W = page.gearFrame:GetWidth() or 646
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
    if page.model then
        page.model:ClearAllPoints()
        page.model:SetPoint("TOPLEFT", cx - MODEL_HALF, 0)
        page.model:SetPoint("BOTTOMRIGHT", page.gearFrame, "TOPLEFT", cx + MODEL_HALF, by + 6)
        dressModel(bySlot)
    end
    -- 底部汇总：几个格子有推荐 · 副本几件（按副本数）· 任务几件；悬停看明细
    local n, nd, nq, byD, total = 0, 0, 0, {}, 0
    for _, grp in ipairs({ GEAR_LEFT, GEAR_RIGHT, GEAR_BOTTOM }) do
        for _, g in ipairs(grp) do
            if g[2] then total = total + 1 end
            local it = bySlot[g[1]]
            if it then
                n = n + 1
                if it.src == "quest" then nq = nq + 1 else nd = nd + 1; local dn = it.dn or "?"; byD[dn] = (byD[dn] or 0) + 1 end
            end
        end
    end
    -- 10-08 用户「加上副本背景图」：用这套里推荐件数最多的那个副本的场景图铺底（按比例裁，不拉伸），压一层暗色保证字看得清
    local topD, topN = nil, 0
    for dn, c in pairs(byD) do if c > topN or (c == topN and topD and dn < topD) then topD, topN = dn, c end end
    local art = topD and ns.DungeonArt and lootDungeonByName(topD) and ns.DungeonArt(lootDungeonByName(topD))
    local H = page.gearFrame:GetHeight() or 366
    if not tonumber(H) or H < 200 then H = 366 end
    page.gearArtDn = (art and art.big) and topD or nil
    if art and art.big then
        page.gearBg:SetTexture(art.big); page.gearBg:SetTexCoord(ns.ArtCoord({ region = art.bigRegion }, W, H)); page.gearBg:Show(); page.gearShade:Show()
        page.gearBgCap:SetText(topD .. " · " .. topN .. ns.L(" 件", ""))
        page.gearBgFull = ns.L("背景是「", "Backdrop: ") .. topD .. ns.L("」：这套推荐里有 ", " — ") .. topN .. ns.L(" 件出自这个副本，是最多的", " pieces of this set drop here (the most)")
        page.gearBgCap:Show()
    else
        page.gearBg:Hide(); page.gearShade:Hide(); page.gearBgCap:Hide()
    end
    page.gearNote:SetText(ns.L("推荐 ", "") .. n .. "/" .. total .. ns.L(" 格 · 副本 ", " slots · dungeons ") .. nd
        .. ns.L(" 件 · 任务 ", " · quests ") .. nq .. ns.L(" 件（悬停看明细）", " (hover for details)"))
    page.gearNoteHit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(ns.L("装备来源", "Gear sources"), 1, 0.82, 0)
        local names = {}
        for dn in pairs(byD) do names[#names + 1] = dn end
        table.sort(names, function(a, b) return byD[a] > byD[b] end)
        for _, dn in ipairs(names) do GameTooltip:AddDoubleLine(dn, byD[dn] .. ns.L(" 件", ""), 1, 1, 1, 1, 1, 1) end
        if nq > 0 then GameTooltip:AddDoubleLine(ns.L("职业任务链", "Class quest chains"), nq .. ns.L(" 件", ""), 1, 1, 1, 1, 1, 1) end
        GameTooltip:AddLine(ns.L("野外任务奖励还没收进来", "Open-world quest rewards aren't included yet"), 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
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
            if it.src == "quest" then
                local key = it.srcName or "?"
                if not qmap[key] then qmap[key] = { name = key, items = {}, req = 999 }; qlist[#qlist + 1] = qmap[key] end
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
        r.t:SetText("|c" .. (QCOL[it.q] or "ffffffff") .. (it.n or "?") .. "|r")
        local span = (it.useFrom and it.useTo and it.useTo < tgt) and string.format(ns.L("　用到 %d 级", "  until %d"), it.useTo) or ""
        r.s:SetText("|cffaaaaaa" .. (it.slot or "") .. ((it.type or "") ~= "" and (" · " .. it.type) or "") .. ns.L("　需要 ", "  req ") .. (it.req or 0) .. ns.L(" 级", "") .. span .. "|r")
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok = pcall(GameTooltip.SetItemByID, GameTooltip, it.id)
            local first = (GameTooltip:NumLines() or 0) > 0 and _G.GameTooltipTextLeft1 and _G.GameTooltipTextLeft1:GetText()
            if not ok or not first or first == "" or first == RETRIEVING_ITEM_INFO then
                if ns.ItemFallbackTip then ns.ItemFallbackTip(it) else GameTooltip:AddLine(it.n or "?") end
            end
            GameTooltip:Show()
        end)
        if dn then r:SetScript("OnClick", function() if ns.LootShowDungeon then ns.LootShowDungeon(dn) end end) end
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
        card(k .. ". " .. d.name, string.format(ns.L("需要 %d 级起 · %d 个首领 · 推荐 %d 件", "From level %d · %d bosses · %d items"), d.req, #d.blist, d.n), art,
            function() if ns.LootShowDungeon then ns.LootShowDungeon(d.name) end end, d.name)
        for _, b in ipairs(d.blist) do
            local r = row(20); r.ic:Hide(); r.t:ClearAllPoints(); r.t:SetPoint("LEFT", 12, 0); r.t:SetPoint("RIGHT", -10, 0)
            r.t:SetText("|cffffd100" .. b.name .. "|r"); r.s:SetText("")
            for _, it in ipairs(b.items) do itemRow(it, d.name) end
        end
    end
    if #qlist > 0 then
        card(ns.L("职业任务链", "Class quest chains"), string.format(ns.L("%d 条任务线 · 奖励装备", "%d chains with gear rewards"), #qlist),
            { icon = "Interface\\Icons\\INV_Misc_Book_09", iconCoord = { 0.07, 0.93, 0.07, 0.93 } }, nil)
        for _, q in ipairs(qlist) do
            local r = row(20); r.ic:Hide(); r.t:ClearAllPoints(); r.t:SetPoint("LEFT", 12, 0); r.t:SetPoint("RIGHT", -10, 0)
            r.t:SetText("|cff33ff99" .. ns.L("任务：", "Quest: ") .. q.name .. "|r"); r.s:SetText("")
            for _, it in ipairs(q.items) do itemRow(it, nil) end
        end
    end
    c:SetHeight(-y + 8)
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
        page.sf:Hide(); page.gearFrame:Hide()
        ns.RefreshRouteView(page, lo, hi)
        return
    end
    if ns.HideRouteView then ns.HideRouteView(page) end
    if viewMode == "gear" then
        page.sf:Hide(); page.gearFrame:Show()
        refreshGear(hi)   -- 装备按范围上限（「到那一级能拿到的最好」）
    elseif viewMode == "farm" then
        page.gearFrame:Hide(); page.sf:Show()
        refreshFarm(lo, hi)
    else
        page.gearFrame:Hide(); page.sf:Show()
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
        gear = ns.L("像 C 键角色栏那样，按部位摆出到目标等级能拿到的最好装备（地下城掉落 + 职业任务链）。",
            "A character-sheet view of the best gear per slot you can get by the target level (dungeon drops + class quest chains)."),
        farm = ns.L("等级范围内一路升级的刷本路线：每一级能拿到的最好装备都列出来（从几级用到几级），按副本从低到高排：先刷哪个本、打哪个首领、拿哪件；任务线单独列。",
            "The recommended gear as a farming route: which dungeon, which boss, which item; quest chains listed separately."),
    }
    local views = { { "timeline", ns.L("地图待办", "Plan") }, { "gear", ns.L("装备", "Gear") }, { "farm", ns.L("刷本清单", "Farm list") } }
    VIEW_TIP.timeline = ns.L("地图与待办合在一条等级时间线：先看去哪练级，再看天赋、技能、宏和副本任务。地图按当前角色阵营种族推荐，切换等级范围一起更新。",
        "Zones and to-dos share a level timeline. Recommendations use your character's faction and race; changing the range updates both.")
    if ns.RefreshRouteView then
        views[#views + 1] = { "route", ns.L("路线总览", "Routes") }
        VIEW_TIP.route = ns.L("按当前等级查看可选练级区域和下一段；可手动查 1-60 级、切阵营种族、查看完整路线，点击区域打开地图。",
            "Find zones for your level and the next stage. Look up levels 1-60, switch faction/race, or view the full route. Click a zone to open its map.")
    end
    for _, v in ipairs(views) do
        local b = ns.Button(p, v[2], 72, 22, function()
            viewMode = v[1]; page.needScroll = true
            if viewMode == "route" and ns.RouteSetMode then ns.RouteSetMode("all") else refresh() end
        end)
        b:SetPoint("TOPLEFT", vx, -40); vx = vx + 76
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
    -- 装备页：纸娃娃，和时间轴共用同一块内容区，切页签时互相 Show/Hide
    page.gearFrame = CreateFrame("Frame", nil, p)
    page.gearFrame:SetPoint("TOPLEFT", sf, "TOPLEFT"); page.gearFrame:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT")
    page.gearFrame:Hide()
    page.gearBtns = {}
    -- 副本背景图（refreshGear 里按推荐件数最多的副本换）+ 两层暗色：整体压暗，左右两列再压一点给文字
    page.gearBg = page.gearFrame:CreateTexture(nil, "BACKGROUND", nil, -8); page.gearBg:SetAllPoints(); page.gearBg:SetAlpha(0.85); page.gearBg:Hide()
    page.gearShade = page.gearFrame:CreateTexture(nil, "BACKGROUND", nil, -7); page.gearShade:SetAllPoints()
    page.gearShade:SetColorTexture(0, 0, 0, 0.45); page.gearShade:Hide()
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local s = page.gearFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
        s:SetPoint("TOP" .. side); s:SetPoint("BOTTOM" .. side); s:SetWidth(230)
        s:SetColorTexture(1, 1, 1, 1)
        local dark, clear = CreateColor and CreateColor(0, 0, 0, 0.55), CreateColor and CreateColor(0, 0, 0, 0)
        if s.SetGradient and dark then
            pcall(s.SetGradient, s, "HORIZONTAL", side == "LEFT" and dark or clear, side == "LEFT" and clear or dark)
        else s:SetColorTexture(0, 0, 0, 0.3) end
    end
    -- 细金边框住整块（和掉落页副本横幅同一个金色）
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
        local l = page.gearFrame:CreateTexture(nil, "BORDER"); l:SetPoint(e[1]); l:SetPoint(e[2]); l:SetColorTexture(1, 0.82, 0, 0.35)
        if e[3] then l:SetWidth(e[3]) else l:SetHeight(e[4]) end
    end
    page.gearBgCap = page.gearFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    page.gearBgCap:SetPoint("TOP", 0, -2); page.gearBgCap:SetWordWrap(false); page.gearBgCap:Hide()
    if page.gearBgCap.SetFont then pcall(page.gearBgCap.SetFont, page.gearBgCap, SUB_FONT, 10, "") end
    page.gearBgHit = CreateFrame("Button", nil, page.gearFrame)
    page.gearBgHit:SetAllPoints(page.gearBgCap)
    page.gearBgHit:SetScript("OnEnter", function(self)
        if not page.gearArtDn then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine(page.gearBgFull or "", 1, 0.82, 0, true)
        GameTooltip:AddLine(ns.L("点击：去掉落页看这个副本", "Click: open this dungeon on the Loot page"), 0.6, 0.6, 0.6); GameTooltip:Show()
    end)
    page.gearBgHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.gearBgHit:SetScript("OnClick", function() if page.gearArtDn and ns.LootShowDungeon then ns.LootShowDungeon(page.gearArtDn) end end)
    page.model = buildModel(page.gearFrame)
    page.gearNote = page.gearFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    page.gearNote:SetPoint("BOTTOMLEFT", 10, 4); page.gearNote:SetPoint("RIGHT", -10, 0); page.gearNote:SetJustifyH("CENTER")
    page.gearNote:SetWordWrap(false)   -- 文字太长就裁掉，⛔不许自动换行把自己顶到图标格子上去
    page.gearNoteHit = CreateFrame("Frame", nil, page.gearFrame)
    page.gearNoteHit:SetPoint("TOPLEFT", page.gearNote, "TOPLEFT"); page.gearNoteHit:SetPoint("BOTTOMRIGHT", page.gearNote, "BOTTOMRIGHT")
    page.gearNoteHit:EnableMouse(true)
    page.gearNoteHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
