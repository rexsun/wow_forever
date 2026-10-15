-- 副本任务（10-10 用户「主要是副本任务」）：某个副本该提前接哪些任务 —— 谁给 / 在哪 / 前置 / 目标 / 奖励 / 经验 / 《无限》改了什么，
-- 以及「做过没 / 接了没 / 等级够不够」。数据 = DungeonQuestData.lua（scripts/gi_forever_dungeon_quests.py 生成）。
-- 入口：掉落页副本横幅「副本任务」按钮、升级规划刷本清单副本卡片右侧「任务」按钮。点一行 = 在地图上标接任务的位置。
-- 名字：任务名优先游戏现读（C_QuestLog.GetTitleForQuestID，国服客户端给官方中文，《无限》新任务也有），读不到用数据里的中文 / 英文；
--   物品名用 GetItemInfo 现读（新装备也是官方中文）。
-- ⛔ 状态符号一律用游戏贴图（√ ● → 这类字符在游戏字体里会变方框）
local _, ns = ...

local byLoot = {}       -- 掉落数据英文名 → 副本任务的副本
local function index()
    if next(byLoot) or not ns.DQ then return end
    for _, d in ipairs(ns.DQ.dungeons) do
        for _, en in ipairs(d.loot or {}) do byLoot[en] = d end
    end
end

-- 掉落页 / 规划页按副本中文名或英文名找
function ns.DQForDungeon(name, nameEn)
    index()
    if nameEn and byLoot[nameEn] then return byLoot[nameEn] end
    for _, d in ipairs((ns.Data.loot or {}).dungeons or {}) do
        if d.n == name or d.nEn == name then return byLoot[d.nEn] end
    end
end

local CLASS_ID = { Warrior = 1, Paladin = 2, Hunter = 3, Rogue = 4, Priest = 5, Shaman = 7, Mage = 8, Warlock = 9, Druid = 11 }
local function mySide()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return f == "Alliance" and "A" or f == "Horde" and "H" or nil
end

-- 这个任务对当前角色：是否可接（阵营 / 职业）
function ns.DQFits(q)
    local side = mySide()
    if side and (q.side == "A" or q.side == "H") and q.side ~= side then return false end
    if q.cls and #q.cls > 0 then
        local my = CLASS_ID[ns.MyClass()]
        local ok = false
        for _, c in ipairs(q.cls) do if tonumber(c) == my then ok = true end end
        if not ok then return false end
    end
    return true
end

local function questDone(id)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(id) end
    if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(id) end
    return false
end
local function inLog(id)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local i = C_QuestLog.GetLogIndexForQuestID(id)
        return i and i > 0
    end
    return false
end

-- 状态：done 做过 / log 已接 / ok 现在能接 / pre 前置没做 / low 等级不够
function ns.DQState(id)
    local q = ns.DQ.quests[id]
    if not q then return "ok" end
    if questDone(id) then return "done" end
    if inLog(id) then return "log" end
    local lv = UnitLevel and UnitLevel("player") or 1
    if (q.req or 0) > lv then return "low" end
    for _, p in ipairs(q.pre or {}) do
        if not questDone(p) and not inLog(p) then return "pre" end
    end
    return "ok"
end

local STATE_TEX = {
    done = "Interface\\RaidFrame\\ReadyCheck-Ready",
    log = "Interface\\GossipFrame\\ActiveQuestIcon",
    ok = "Interface\\GossipFrame\\AvailableQuestIcon",
    pre = "Interface\\GossipFrame\\AvailableQuestIcon",
    low = "Interface\\GossipFrame\\AvailableQuestIcon",
}
local STATE_TXT = {
    done = { "已完成", "Done" }, log = { "已接", "In log" }, ok = { "可以接", "Available" },
    pre = { "先做前置", "Needs prerequisite" }, low = { "等级不够", "Level too low" },
}
local ORDER = { ok = 1, log = 2, pre = 3, low = 4, done = 5 }

-- 任务名：游戏现读 > 数据中文 > 英文；读不到的请求一次，QUEST_DATA_LOAD_RESULT 回来再刷
local asked = {}
function ns.DQTitle(id)
    local t
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then t = C_QuestLog.GetTitleForQuestID(id) end
    if t and t ~= "" then return t end
    if not asked[id] and C_QuestLog and C_QuestLog.RequestLoadQuestByID then
        asked[id] = true
        pcall(C_QuestLog.RequestLoadQuestByID, id)
    end
    local q = ns.DQ.quests[id]
    if not q then return "#" .. id end
    return ns.L((q.c ~= "" and q.c) or q.n, q.n)
end

local function itemText(id)
    local name, _, quality = nil, nil, nil
    if GetItemInfo then name, _, quality = GetItemInfo(id) end
    if not name then
        -- 10-10 截图奖励全是「#279897」：《无限》新物品客户端没缓存，GetItemInfo 第一次拿不到 → 主动向服务器要，
        --   GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT 回来后弹框自动刷新成官方中文名
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        local zh = (ns.DQ.items or {})[id]
        return "|cffcccccc" .. ((zh and ns.L(zh, "")) ~= "" and zh or ns.L("读取中…", "loading...")) .. "|r"
    end
    local col = (ITEM_QUALITY_COLORS and quality and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].hex) or "|cffffffff"
    return col .. name .. "|r"
end

-- 10-11 用户截图「副本内，副本外，哪个地图，在这里展示下」：位置前加醒目标签
--   副本内（橙）+ 副本名 · 副本外（蓝）+ 地区 (x, y) · 物品（紫）= 打怪掉的物品右键开始 · 位置未知（灰）
local TAG_IN, TAG_OUT, TAG_ITEM, TAG_UNK = "|cffff9966", "|cff66ccff", "|cffc69bff", "|cff8a8a8a"
local function whoText(w, extra)
    if not w then return nil end
    local n = ns.L((w.c ~= "" and w.c) or w.n, w.n)
    local z = ns.L((w.zc ~= "" and w.zc) or w.ze, w.ze)
    local sep = ns.L(" · ", " - ")
    if w.k == "item" then
        return TAG_ITEM .. ns.L("物品", "Item") .. "|r " .. n .. ((extra and extra ~= "") and (sep .. extra) or ns.L("（打怪掉落，右键开始）", " (drops - right-click to start)"))
    end
    if w.i then return n .. sep .. TAG_IN .. ns.L("副本内", "Inside") .. "|r " .. z end
    if z ~= "" then
        local at = (w.x and w.x > 0) and string.format(" (%.0f, %.0f)", w.x, w.y) or ""
        return n .. sep .. TAG_OUT .. ns.L("副本外", "Outside") .. "|r " .. z .. at
    end
    return n .. sep .. TAG_UNK .. ns.L("位置未知", "location unknown") .. "|r" .. ((extra and extra ~= "") and (" " .. extra) or "")
end

local function money(c)
    if not c or c <= 0 then return "" end
    local g, s = math.floor(c / 10000), math.floor((c % 10000) / 100)
    return (g > 0 and (g .. ns.L("金", "g")) or "") .. (s > 0 and (s .. ns.L("银", "s")) or "")
end

-- 在地图上标接任务的人（暴雪自带地图标记 + 超级追踪）
function ns.DQWaypoint(q)
    local w = q and q.st
    if not w or not w.ui or w.ui == 0 or not w.x or w.x <= 0 then
        ns.Print(ns.L("这个任务没有可以标在地图上的位置（可能在副本里接，或者是掉落开始的任务）", "No map position for this quest's start"))
        return
    end
    -- 10-11：打标同时打开世界地图切到那个地区（ns.ShowOnMap，装了 TomTom 也打 TomTom 点）
    local ok = ns.ShowOnMap(w.ui, { { w.x, w.y } }, ns.L(w.c or w.n or "", w.n or w.c or ""))
    ns.Print((ok and ns.L("已在地图上标出：", "Map pin set: ") or "") .. (whoText(w) or ""))
end

-- ---------- 弹框 ----------
local pop
local function build(parent)
    local f = CreateFrame("Frame", "GearInsightForeverDQPop", parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -40)
    f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    f:SetFrameLevel((parent:GetFrameLevel() or 1) + 30)
    f:EnableMouse(true)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.04, 0.04, 0.07, 0.97)
    end
    -- 10-10 截图：提示框底图半透明，底下页面的字透上来 → 再铺一层实色底
    local solid = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    solid:SetPoint("TOPLEFT", 4, -4); solid:SetPoint("BOTTOMRIGHT", -4, 4); solid:SetColorTexture(0.05, 0.05, 0.08, 1)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 14, -12); f.title:SetPoint("RIGHT", -230, 0); f.title:SetJustifyH("LEFT"); f.title:SetWordWrap(false)
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4); f.sub:SetPoint("RIGHT", -34, 0); f.sub:SetJustifyH("LEFT"); f.sub:SetWordWrap(false)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    f.all = ns.Button(f, "", 112, 22, function()
        ns.db.ui = ns.db.ui or {}
        ns.db.ui.dqAll = not ns.db.ui.dqAll
        if f.cur then ns.ShowDungeonQuests(f.cur) end
    end)
    f.all:SetPoint("TOPRIGHT", -34, -10)
    f.all:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(ns.L("默认只列你这个角色能接的（阵营 / 职业）；点一下看全部", "By default only quests your character can take are listed"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.all:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local sf, c = ns.Scroll(f, 10, -54, 610, 360)
    f.sf, f.child, f.rows = sf, c, {}
    f.foot = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.foot:SetPoint("BOTTOMLEFT", 14, 8); f.foot:SetPoint("RIGHT", -14, 0); f.foot:SetJustifyH("LEFT"); f.foot:SetWordWrap(false)
    f.foot:SetText(ns.L("点一行：在地图上标出接任务的人 · 数据：Dungeon Assistant（Wowhead《无限》1.60.1）+ Dungeon Quests Forever", "Click a row to pin the quest giver on the map - Data: Dungeon Assistant (Wowhead Forever 1.60.1) + Dungeon Quests Forever"))
    f:Hide()
    return f
end

local function rowTooltip(r)
    local q, id = r.q, r.id
    if not q then return end
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.DQTitle(id), 1, 0.82, 0)
    local st = STATE_TXT[ns.DQState(id)]
    GameTooltip:AddLine(ns.L(st[1], st[2]) .. ns.L("　任务等级 ", "  quest level ") .. (q.lv or 0) .. ns.L("　", "  ") .. (q.req or 0) .. ns.L(" 级可接", "+ to accept"), 0.8, 0.8, 0.8)
    if q.st then GameTooltip:AddLine(ns.L("接：", "Start: ") .. whoText(q.st, (q.stText ~= "") and ns.L(q.stTextC ~= "" and q.stTextC or q.stText, q.stText) or nil), 1, 1, 1, true)
    elseif q.stText ~= "" then GameTooltip:AddLine(ns.L("接：", "Start: ") .. ns.L(q.stTextC ~= "" and q.stTextC or q.stText, q.stText), 1, 1, 1, true) end
    if q.fi and (not q.st or q.fi.id ~= q.st.id) then GameTooltip:AddLine(ns.L("交：", "Turn in: ") .. whoText(q.fi), 1, 1, 1, true) end
    local o = ns.L((q.oc ~= "" and q.oc) or q.o, q.o)
    if o ~= "" then GameTooltip:AddLine(" "); GameTooltip:AddLine(o, 0.85, 0.85, 0.85, true) end
    if #(q.goals or {}) > 0 then
        for _, g in ipairs(q.goals) do
            GameTooltip:AddLine("  " .. ns.L((g.c ~= "" and g.c) or g.n, g.n) .. " x" .. (g.cnt or 1), 0.7, 0.9, 1)
        end
    end
    local chain = q.chain or {}
    if #chain > 1 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ns.L("任务链（按顺序）", "Quest chain (in order)"), 1, 0.82, 0)
        for i, cid in ipairs(chain) do
            local s = ns.DQState(cid)
            local col = (s == "done") and "|cff40c040" or (cid == id) and "|cffffd100" or "|cffcccccc"
            GameTooltip:AddLine(col .. i .. ". " .. ns.DQTitle(cid) .. (s == "done" and ns.L("（已完成）", " (done)") or s == "log" and ns.L("（已接）", " (in log)") or "") .. "|r", 1, 1, 1, true)
        end
    elseif #(q.pre or {}) > 0 then
        local t = {}
        for _, p in ipairs(q.pre) do t[#t + 1] = ns.DQTitle(p) .. (questDone(p) and ns.L("（已完成）", " (done)") or "") end
        GameTooltip:AddLine(ns.L("前置：", "Requires: ") .. table.concat(t, ns.L("、", ", ")), 1, 0.6, 0.4, true)
    end
    local rw = {}
    for _, i in ipairs(q.r or {}) do rw[#rw + 1] = itemText(i) end
    if #rw > 0 then GameTooltip:AddLine(ns.L("奖励：", "Rewards: ") .. table.concat(rw, ns.L("、", ", ")), 1, 1, 1, true) end
    local ch = {}
    for _, i in ipairs(q.ch or {}) do ch[#ch + 1] = itemText(i) end
    if #ch > 0 then GameTooltip:AddLine(ns.L("任选其一：", "Choose one: ") .. table.concat(ch, ns.L("、", ", ")), 1, 1, 1, true) end
    local tail = {}
    if (q.xp or 0) > 0 then tail[#tail + 1] = ns.L("经验 ", "XP ") .. q.xp end
    if (q.money or 0) > 0 then tail[#tail + 1] = money(q.money) end
    for _, rp in ipairs(q.rep or {}) do tail[#tail + 1] = rp[1] .. ns.L(" 声望 +", " rep +") .. rp[2] end
    if #tail > 0 then GameTooltip:AddLine(table.concat(tail, ns.L("　", "  ")), 0.7, 0.7, 0.7, true) end
    if (q.changed or "") ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ns.L("《无限》改动：", "Changed in Forever: ") .. ns.L(q.changedc ~= "" and q.changedc or q.changed, q.changed), 0.2, 1, 0.6, true)
    end
    if q.share then GameTooltip:AddLine(ns.L("可以共享给队友", "Shareable with your party"), 0.6, 0.6, 0.6) end
    if q.beta then
        GameTooltip:AddLine(ns.L("这条来自 Beta 实测整理（Dungeon Quests Forever）：任务等级是按副本等级估的，NPC 位置可能还要核对",
            "From beta play-testing notes (Dungeon Quests Forever): level estimated from the dungeon, NPC positions may need checking"), 0.7, 0.7, 0.7, true)
    end
    GameTooltip:AddLine(ns.L("点击：在地图上标出接任务的人", "Click: pin the quest giver on the map"), 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function getRow(i)
    local r = pop.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, pop.child)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 1, 1, 0.03)
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.07)
    r.ic = r:CreateTexture(nil, "ARTWORK"); r.ic:SetSize(18, 18); r.ic:SetPoint("TOPLEFT", 6, -6)
    r.t = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.t:SetPoint("TOPLEFT", 30, -6); r.t:SetPoint("RIGHT", -150, 0); r.t:SetJustifyH("LEFT"); r.t:SetWordWrap(false)
    r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.tag:SetPoint("TOPRIGHT", -8, -8); r.tag:SetWidth(140); r.tag:SetJustifyH("RIGHT"); r.tag:SetWordWrap(false)
    r.a = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.a:SetPoint("TOPLEFT", 30, -25); r.a:SetPoint("RIGHT", -8, 0); r.a:SetJustifyH("LEFT"); r.a:SetWordWrap(false)
    r.b = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.b:SetPoint("TOPLEFT", 30, -41); r.b:SetPoint("RIGHT", -8, 0); r.b:SetJustifyH("LEFT"); r.b:SetWordWrap(false)
    r:SetScript("OnEnter", rowTooltip)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self) ns.DQWaypoint(self.q) end)
    pop.rows[i] = r
    return r
end

-- 列表（给测试 / 规划页用）：这个副本对当前角色的任务，按「能接 > 已接 > 先做前置 > 等级不够 > 已完成」再按等级排
function ns.DQList(d, all)
    local list = {}
    for _, id in ipairs(d.q or {}) do
        local q = ns.DQ.quests[id]
        if q and (all or ns.DQFits(q)) then list[#list + 1] = { id = id, q = q, s = ns.DQState(id) } end
    end
    table.sort(list, function(a, b)
        if ORDER[a.s] ~= ORDER[b.s] then return ORDER[a.s] < ORDER[b.s] end
        if a.q.lv ~= b.q.lv then return a.q.lv < b.q.lv end
        return a.id < b.id
    end)
    return list
end

function ns._DQPop() return pop end   -- 测试用
function ns.ShowDungeonQuests(d, parent)
    if type(d) == "string" then d = ns.DQForDungeon(d) end
    if not d then return end
    parent = parent or (ns.ActivePage and ns.ActivePage()) or ns.LootPage
    if not parent then return end
    if not pop or pop:GetParent() ~= parent then
        if pop then pop:Hide() end
        pop = build(parent)
    end
    pop.cur = d
    local all = ns.db.ui and ns.db.ui.dqAll
    local list = ns.DQList(d, all)
    local nOk, nDone = 0, 0
    for _, e in ipairs(list) do
        if e.s == "ok" or e.s == "log" then nOk = nOk + 1 elseif e.s == "done" then nDone = nDone + 1 end
    end
    local dn = d.n
    for _, ld in ipairs((ns.Data.loot or {}).dungeons or {}) do
        if ld.nEn == (d.loot or {})[1] then dn = ns.L((ld.n or ""):gsub("：.*$", ""), d.n) break end
    end
    pop.title:SetText("|cffffd100" .. dn .. "|r " .. ns.L("副本任务", "dungeon quests") .. "  |cff888888" .. #list .. "|r")
    pop.sub:SetText(ns.EnSafe(string.format(ns.L("等级 %d-%d · 现在能接 %d 个 · 已完成 %d 个", "Level %d-%d - %d available - %d done"), d.min, d.max, nOk, nDone)))
    pop.all:SetText(all and ns.L("只看我能接的", "Mine only") or ns.L("显示全部", "Show all"))
    for _, r in ipairs(pop.rows) do r:Hide() end
    local y = -2
    if #list == 0 then
        local r = getRow(1)
        r.q, r.id = nil, nil
        r.ic:Hide(); r.tag:SetText(""); r.a:SetText(""); r.b:SetText("")
        local others = #ns.DQList(d, true)
        local msg
        if others == 0 then
            msg = d.new and ns.L("《无限》新副本：任务还没公开（Beta 等级上限还没开到这里）", "New Forever dungeon: quests not public yet")
                or ns.L("这个副本没有任务数据", "No quest data for this dungeon")
        else
            local fac = (d.side == "H") and ns.L("部落", "Horde") or (d.side == "A") and ns.L("联盟", "Alliance") or nil
            msg = (fac and string.format(ns.L("这是%s副本，%d 个任务都是%s的", "A %s dungeon: all %d quests are %s"), fac, others, fac)
                or string.format(ns.L("%d 个任务都是另一阵营或别的职业的", "All %d quests are for the other faction or other classes"), others))
                .. ns.L("，点右上「显示全部」看", " - click Show all")
        end
        r.t:SetText("|cff999999" .. msg .. "|r")
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, y); r:SetPoint("RIGHT", pop.child, "RIGHT", -4, 0); r:SetHeight(30); r:Show()
        y = y - 32
    end
    for i, e in ipairs(list) do
        local q, r = e.q, getRow(i)
        r.q, r.id = q, e.id
        r.ic:SetTexture(STATE_TEX[e.s]); r.ic:Show()
        r.ic:SetDesaturated(e.s == "low" or e.s == "pre")
        local tc = (e.s == "done") and "|cff7f7f7f" or (e.s == "low") and "|cff9a9a9a" or "|cffffd100"
        r.t:SetText(tc .. ns.DQTitle(e.id) .. "|r  |cff888888Lv." .. (q.lv or 0) .. "|r")
        local tags = {}
        local st = STATE_TXT[e.s]
        tags[#tags + 1] = (e.s == "ok" and "|cff40ff40" or e.s == "log" and "|cffffd100" or "|cff9a9a9a") .. ns.L(st[1], st[2]) .. "|r"
        if q.new then tags[#tags + 1] = "|cff33ff99" .. ns.L("新", "New") .. "|r" end
        if (q.changed or "") ~= "" then tags[#tags + 1] = "|cff33ff99" .. ns.L("有改动", "Changed") .. "|r" end
        if q.beta then tags[#tags + 1] = "|cffaaaaaaBeta|r" end
        r.tag:SetText(table.concat(tags, " "))
        local stx = (q.stText ~= "") and ns.L(q.stTextC ~= "" and q.stTextC or q.stText, q.stText) or ""
        local where = q.st and whoText(q.st, stx) or (stx ~= "" and (TAG_OUT .. ns.L("副本外", "Outside") .. "|r " .. stx)) or "?"
        local pre = ""
        if #(q.pre or {}) > 0 and e.s == "pre" then pre = "　|cffff9966" .. ns.L("前置：", "Needs: ") .. ns.DQTitle(q.pre[1]) .. (#q.pre > 1 and ns.L(" 等", " ...") or "") .. "|r" end
        r.a:SetText("|cffaaaaaa" .. ns.L("接：", "Start: ") .. "|r" .. where .. pre)
        local rw = {}
        for _, it in ipairs(q.r or {}) do rw[#rw + 1] = itemText(it) end
        if #(q.ch or {}) > 0 then
            local ch = {}
            for _, it in ipairs(q.ch) do ch[#ch + 1] = itemText(it) end
            rw[#rw + 1] = ns.L("任选：", "choose: ") .. table.concat(ch, ns.L(" / ", " / "))
        end
        if (q.xp or 0) > 0 then rw[#rw + 1] = "|cffaaaaaa" .. ns.L("经验 ", "XP ") .. q.xp .. "|r" end
        r.b:SetText(#rw > 0 and (ns.L("奖励：", "Rewards: ") .. table.concat(rw, ns.L("、", ", "))) or ("|cff777777" .. ns.L("没有物品奖励", "No item reward") .. "|r"))
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, y); r:SetPoint("RIGHT", pop.child, "RIGHT", -4, 0); r:SetHeight(58)
        r:Show()
        y = y - 60
    end
    pop.child:SetHeight(-y + 4)
    pop:Show()
end

-- 物品 / 任务名异步回来后刷新开着的弹框（只在弹框显示时刷，节流 0.3 秒）
local ev = CreateFrame("Frame")
local pending = false
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
pcall(ev.RegisterEvent, ev, "ITEM_DATA_LOAD_RESULT")
pcall(ev.RegisterEvent, ev, "QUEST_DATA_LOAD_RESULT")      -- 《无限》客户端没有的事件别让整个插件报错
pcall(ev.RegisterEvent, ev, "QUEST_TURNED_IN")
pcall(ev.RegisterEvent, ev, "QUEST_ACCEPTED")
ev:SetScript("OnEvent", function()
    if not pop or not pop:IsShown() or pending then return end
    pending = true
    C_Timer.After(0.3, function()
        pending = false
        if pop and pop:IsShown() and pop.cur then ns.ShowDungeonQuests(pop.cur, pop:GetParent()) end
    end)
end)
