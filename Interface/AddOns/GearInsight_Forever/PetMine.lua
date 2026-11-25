-- 11-20 用户「怎么能在插件看到抓了的宝宝，技能学习进度」→「做吧，加个『我的宠物』视图」+「多一些图片，按钮，少一些文字设计」：
--   猎人宠物页第 1 个视图「我的宠物」，三块，全是图标 / 按钮，字只留名字和数字：
--   ① 宠物卡：当前宠物（实时头像）+ 兽栏里的；等级角标、快乐表情、训练点条 / 经验条，细节放鼠标提示
--   ② 技能格：22 个宠物技能一个图标一格；右下角「已学/共几级」；没学 = 灰；你现在就能去抓野兽学下一级 = 绿框 + 绿「+」；
--      当前宠物带着的 = 金色小角标；顶上「只看当前宠物能学的」开关 + 学习进度条 +「训练野兽」同步按钮（只提示，不碰安全接口）
--   ③ 点一个技能 → 下面一排等级按钮（绿 = 学会了 / 金框 = 现在能学 / 灰 = 还早）→ 点等级 → 会教这一级的野兽按钮，点 = 地图标点
-- 数据：主插件 PetSnap.lua 记的存档（训练野兽窗口 / 兽栏开过一次才有）+ 宠物在身边时实时读；野兽 = PetTame.lua（M.Teachers / M.ShowBeast）
-- ⛔ 在 HOLD 里：游戏内验收前不进发行包；PagePet.lua 没有 ns.PetMine 时没有这个视图。
local _, ns = ...; ns = _G.GearInsightForever or ns
-- 1.4.6 内存预算：宠物页只给猎人看 → 不是猎人整个文件当场返回；职业读不到（nil）照常往下
do
    local ok, _, c = pcall(UnitClass, "player")
    if ok and type(c) == "string" and c ~= "HUNTER" then return end
end

local M = {}
ns.PetMine = M

local GREEN, GOLD, GREY = "|cff33ff66", "|cffffd100", "|cff888888"
M.COLS = 9
M.TILE = 66
M.TEACH_SHOW = 6

local function T() return ns.PetTame end
local function snap() return ns.PetSnap and ns.PetSnap.Mine and ns.PetSnap.Mine() or nil end
local function myLevel() local ok, v = pcall(UnitLevel, "player"); return (ok and type(v) == "number") and v or 1 end

local function famByName(name)
    if type(name) ~= "string" then return nil end
    for _, f in ipairs((ns.PetData and ns.PetData.families) or {}) do
        if name == f.cn or name == f.en or (ns.TD and name == ns.TD(f.cn)) then return f end
    end
end
local function skillIcon(id)
    local t
    if C_Spell and C_Spell.GetSpellTexture then local ok, v = pcall(C_Spell.GetSpellTexture, id); if ok then t = v end end
    if not t and GetSpellTexture then local ok, v = pcall(GetSpellTexture, id); if ok then t = v end end
    return t or "Interface\\Icons\\INV_Misc_QuestionMark"
end
local function skName(s) return ns.SpellNm and ns.SpellNm(s.id, s.cn, s.en) or ns.L(s.cn, s.en) end
local function beastName(b)
    if ns.zh then return ns.TD and ns.TD(b.cn or b.en) or (b.cn or b.en) end
    return b.en or b.cn
end
local function ago(t)
    if not t then return nil end
    local d = time() - t
    if d < 3600 then return ns.L("刚刚", "just now") end
    if d < 86400 then return ns.L(math.floor(d / 3600) .. " 小时前", math.floor(d / 3600) .. "h ago") end
    return ns.L(math.floor(d / 86400) .. " 天前", math.floor(d / 86400) .. "d ago")
end

-- 已学：训练野兽窗口记下的（名字 → 技能）∪ 当前宠物技能书里的（法术 ID → 技能 + 等级）
function M.Learned(sn, cur)
    local byName, learned, petHas = {}, {}, {}
    for _, s in ipairs((ns.PetData and ns.PetData.skills) or {}) do
        byName[skName(s)] = s; byName[s.cn] = s; byName[s.en] = s
        if ns.TD then byName[ns.TD(s.cn)] = s end
    end
    for _, c in ipairs((sn and sn.crafts) or {}) do
        local s = byName[c.n]
        if s then learned[s.en] = math.max(learned[s.en] or 0, c.r or 1) end
    end
    local SI = T() and T().SpellInfo
    for _, id in ipairs((cur and cur.spells) or {}) do
        local en, rk = nil, nil
        if SI then en, rk = SI(id) end
        if not en and GetSpellInfo then
            local ok, nm = pcall(GetSpellInfo, id)
            local s = ok and byName[nm]
            if s then en, rk = s.en, 1 end
        end
        if en then
            petHas[en] = math.max(petHas[en] or 0, rk or 1)
            learned[en] = math.max(learned[en] or 0, rk or 1)
        end
    end
    return learned, petHas
end

-- 下一级现在能不能去学：有会教这一级的野兽、等级不超过我
function M.CanLearn(en, rank)
    local Tm = T()
    if not (Tm and Tm.Teachers) then return false end
    local lv = myLevel()
    for _, b in ipairs(Tm.Teachers(en, rank)) do
        if (b.lo or 99) <= lv then return true end
    end
    return false
end

-- 野兽 ID → 家族（画野兽按钮的家族图标；第一次用时建表）
local beastFam
function M.BeastFam(id)
    if not beastFam then
        beastFam = {}
        local Tm = T()
        for _, f in ipairs((ns.PetData and ns.PetData.families) or {}) do
            for _, b in ipairs((Tm and Tm.Beasts) and Tm.Beasts(f.id) or {}) do beastFam[b.id] = f end
        end
    end
    return beastFam[id]
end

local function famHas(fam, s)
    if not fam then return true end
    for _, id in ipairs(s.fams or {}) do if id == fam.id then return true end end
    return false
end

-- 快乐表情：暴雪宠物面板那张图（开心 / 一般 / 不开心）
local HAP = { [3] = { 0, 0.1875 }, [2] = { 0.1875, 0.375 }, [1] = { 0.375, 0.5625 } }

local function bar(parent, x, y, w, v, max, r, g, b)
    local bg = parent:CreateTexture(nil, "ARTWORK")
    bg:SetPoint("TOPLEFT", x, y); bg:SetSize(w, 5); bg:SetColorTexture(0.15, 0.15, 0.17, 1)
    local fg = parent:CreateTexture(nil, "OVERLAY")
    fg:SetPoint("TOPLEFT", x, y)
    local frac = (max and max > 0 and v) and math.max(0, math.min(1, v / max)) or 0
    fg:SetSize(math.max(1, w * frac), 5); fg:SetColorTexture(r, g, b, 1)
    if frac == 0 then fg:Hide() end
end

-- ① 宠物卡
local function petCard(ctx, x, y, d, live, isCur)
    local W, H = 150, 92
    local b = ctx.box(x, y, W, H, isCur)
    local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(48, 48); ic:SetPoint("TOPLEFT", 8, -8)
    local fam = famByName(d and d.fam)
    if live and SetPortraitTexture then pcall(SetPortraitTexture, ic, "pet")
    else
        ic:SetTexture((d and d.icon) or (fam and fam.icon and fam.icon > 0 and fam.icon) or (d and "Interface\\Icons\\Ability_Hunter_BeastTaming") or "Interface\\Icons\\INV_Box_PetCarrier_01")
        ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if not d then ic:SetDesaturated(true); ic:SetAlpha(0.5) end
    end
    if d and d.lv then
        local lv = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        lv:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", 2, -1); lv:SetText(d.lv)
    end
    if d and fam then
        local fi = b:CreateTexture(nil, "OVERLAY"); fi:SetSize(16, 16); fi:SetPoint("TOPLEFT", ic, "TOPLEFT", -3, 3)
        fi:SetTexture(fam.icon and fam.icon > 0 and fam.icon or "Interface\\Icons\\Ability_Hunter_BeastTaming"); fi:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if live then fi:Show() else fi:Hide() end   -- 兽栏卡的大图标本来就是宠物图标，家族小角标只给实时头像
    end
    if d and d.hap and HAP[d.hap] then
        local h = b:CreateTexture(nil, "OVERLAY"); h:SetSize(20, 20); h:SetPoint("TOPRIGHT", -6, -6)
        h:SetTexture("Interface\\PetPaperDollFrame\\UI-PetHappiness"); h:SetTexCoord(HAP[d.hap][1], HAP[d.hap][2], 0, 0.359375)
    end
    local nm = ctx.text(b, d and "GameFontNormal" or "GameFontDisableSmall", 62, -10, W - 70 - ((d and d.hap) and 20 or 0),
        d and d.n or ns.L("兽栏未同步", "Stable not synced"))
    nm:SetWordWrap(false)
    if d then
        local fs = ctx.text(b, "GameFontDisableSmall", 62, -28, W - 70, fam and ns.L(fam.cn, fam.en) or (d.fam or ""))
        fs:SetWordWrap(false)
    end
    if d and d.tp then
        local free = (d.tp or 0) - (d.spent or 0)
        ctx.text(b, "GameFontHighlightSmall", 62, -44, W - 70, "|cffffcc66TP|r " .. free)
        bar(b, 8, -66, W - 16, d.spent, d.tp, 1, 0.8, 0.2)
    end
    if d and d.xpMax and d.xpMax > 0 then bar(b, 8, -76, W - 16, d.xp, d.xpMax, 0.6, 0.3, 1) end
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not d then
            GameTooltip:AddLine(ns.L("兽栏", "Stable"), 1, 0.82, 0)
            GameTooltip:AddLine(ns.L("去兽栏管理员那打开一次兽栏，这里就会显示", "Open the stable once at a Stable Master to show it here"), 1, 1, 1, true)
        else
            GameTooltip:AddLine(d.n, 1, 0.82, 0)
            if fam then GameTooltip:AddLine(ns.L(fam.cn, fam.en), 0.7, 0.7, 0.7) end
            if d.lv then GameTooltip:AddDoubleLine(ns.L("等级", "Level"), d.lv, 0.7, 0.7, 0.7, 1, 1, 1) end
            if d.loy then GameTooltip:AddDoubleLine(ns.L("忠诚", "Loyalty"), tostring(d.loy), 0.7, 0.7, 0.7, 1, 1, 1) end
            if d.tp then GameTooltip:AddDoubleLine(ns.L("训练点（剩 / 共）", "Training pts (free / total)"), ((d.tp or 0) - (d.spent or 0)) .. " / " .. d.tp, 0.7, 0.7, 0.7, 1, 0.8, 0.2) end
            if d.xpMax and d.xpMax > 0 then GameTooltip:AddDoubleLine(ns.L("经验", "XP"), (d.xp or 0) .. " / " .. d.xpMax, 0.7, 0.7, 0.7, 0.7, 0.5, 1) end
            if fam then
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine(ns.L("伤害 / 护甲 / 生命", "Dmg / Armor / HP"), fam.dmg .. "% / " .. fam.arm .. "% / " .. fam.hp .. "%", 0.7, 0.7, 0.7, 1, 1, 1)
            end
            if not live and d.at then GameTooltip:AddLine(ns.L("记录于 ", "Recorded ") .. ago(d.at), 0.5, 0.5, 0.5) end
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- 小方按钮（图标 / 字），统一边框
local function sqButton(parent, x, y, w, h)
    local bt = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    bt:SetPoint("TOPLEFT", x, y); bt:SetSize(w, h)
    if bt.SetBackdrop then
        bt:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        bt:SetBackdropColor(0.10, 0.11, 0.13, 0.95); bt:SetBackdropBorderColor(0.3, 0.3, 0.32, 1)
    end
    local hl = bt:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
    return bt
end
local function border(bt, r, g, b) if bt.SetBackdropBorderColor then bt:SetBackdropBorderColor(r, g, b, 1) end end

function M.View(ctx)
    local p, c = ctx.p, ctx.c
    local D = ns.PetData
    local sn = snap() or {}
    local live = ns.PetSnap and ns.PetSnap.ReadCur and ns.PetSnap.ReadCur() or nil
    local cur = live or sn.cur
    local curFam = famByName(cur and cur.fam)
    local learned, petHas = M.Learned(sn, cur)
    ns.db.ui = ns.db.ui or {}
    local UI = ns.db.ui
    local y = 0

    -- ① 宠物卡：当前 + 兽栏（兽栏没同步过 = 两张「兽栏未同步」占位卡）
    petCard(ctx, 0, y, cur, live ~= nil, true)
    local st = sn.stable
    local n = st and #st or 0
    local slots = st and math.max(sn.stableSlots or 0, n) or 2
    for i = 1, math.min(math.max(slots, 1), 3) do
        petCard(ctx, i * 156, y, st and st[i] or nil, false, false)
    end
    y = y - 92 - 10

    -- ② 顶条：同步按钮 + 学习进度条 + 只看当前宠物能学的
    local bar0 = ctx.box(0, y, 618, 34, false)
    local sync = sqButton(bar0, 4, -4, 120, 26)
    local si = sync:CreateTexture(nil, "ARTWORK"); si:SetSize(20, 20); si:SetPoint("LEFT", 3, 0)
    si:SetTexture(skillIcon(ns.PetSnap and ns.PetSnap.BEAST_TRAINING or 5149)); si:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local st1 = sync:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); st1:SetPoint("LEFT", 27, 0)
    st1:SetText(ns.L("训练野兽", "Beast Training"))
    if not sn.crafts then border(sync, 1, 0.82, 0) end
    sync:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine(ns.L("同步已学技能", "Sync learned abilities"), 1, 0.82, 0)
        GameTooltip:AddLine(ns.L("技能书里点「训练野兽」打开一次就同步", "Open Beast Training from your spellbook once to sync"), 1, 1, 1, true)
        GameTooltip:AddLine(sn.craftAt and (ns.L("上次同步：", "Last sync: ") .. ago(sn.craftAt)) or (GREY .. ns.L("还没同步过", "Never synced") .. "|r"), 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    sync:SetScript("OnLeave", function() GameTooltip:Hide() end)
    sync:SetScript("OnClick", function() ns.Print(ns.L("按 P 打开技能书 → 点「训练野兽」，打开一次就同步", "Press P, then click Beast Training once to sync")) end)

    local tot, got = 0, 0
    for _, s in ipairs(D.skills) do
        if not UI.petMineFam or famHas(curFam, s) then
            tot = tot + (s.ranks or 1); got = got + math.min(learned[s.en] or 0, s.ranks or 1)
        end
    end
    local pt = ctx.text(bar0, "GameFontHighlightSmall", 134, -6, 120, GOLD .. got .. "|r / " .. tot)
    pt:SetWordWrap(false)
    bar(bar0, 134, -22, 250, got, tot, 0.2, 0.9, 0.4)

    local flt = sqButton(bar0, 618 - 4 - 196, -4, 196, 26)
    local fi = flt:CreateTexture(nil, "ARTWORK"); fi:SetSize(20, 20); fi:SetPoint("LEFT", 3, 0)
    fi:SetTexture(curFam and curFam.icon and curFam.icon > 0 and curFam.icon or "Interface\\Icons\\Ability_Hunter_BeastTaming"); fi:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local ft = flt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); ft:SetPoint("LEFT", 27, 0)
    ft:SetText((UI.petMineFam and GREEN or "") .. ns.L("只看当前宠物能学的", "Current pet only") .. (UI.petMineFam and "|r" or ""))   -- 开着 = 绿字 + 绿框（字体没有 ✓）
    if UI.petMineFam then border(flt, 0.2, 0.9, 0.4) end
    if not curFam then flt:Disable(); flt:SetAlpha(0.4) end
    flt:SetScript("OnClick", function() UI.petMineFam = not UI.petMineFam or nil; ctx.refresh(true) end)
    y = y - 34 - 8

    -- ③ 技能格
    local list = {}
    for _, s in ipairs(D.skills) do
        if not UI.petMineFam or famHas(curFam, s) then list[#list + 1] = s end
    end
    M.sel = M.sel or UI.petMineSel
    local selS
    for _, s in ipairs(list) do if s.en == M.sel then selS = s end end
    selS = selS or list[1]
    local TS = M.TILE
    for i, s in ipairs(list) do
        local col, row = (i - 1) % M.COLS, math.floor((i - 1) / M.COLS)
        local lr, mx = learned[s.en] or 0, s.ranks or 1
        local nextOk = lr < mx and M.CanLearn(s.en, lr + 1)
        local bt = sqButton(c, col * (TS + 3), y - row * (TS + 3), TS, TS)
        p.items[#p.items + 1] = bt
        local ic = bt:CreateTexture(nil, "ARTWORK"); ic:SetSize(40, 40); ic:SetPoint("TOP", 0, -5)
        ic:SetTexture(skillIcon(s.id)); ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if lr == 0 then ic:SetDesaturated(true); ic:SetAlpha(0.55) end
        local rk = bt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); rk:SetPoint("BOTTOM", 0, 5)
        rk:SetText((lr >= mx and GREEN or (lr > 0 and "|cffffffff" or GREY)) .. lr .. "|r" .. GREY .. "/" .. mx .. "|r")
        if petHas[s.en] then
            local pw = bt:CreateTexture(nil, "OVERLAY"); pw:SetSize(14, 14); pw:SetPoint("TOPLEFT", ic, "TOPLEFT", -4, 4)
            pw:SetTexture(curFam and curFam.icon and curFam.icon > 0 and curFam.icon or "Interface\\Icons\\Ability_Hunter_BeastTaming"); pw:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
        if nextOk then
            border(bt, 0.2, 0.9, 0.4)
            local pl = bt:CreateFontString(nil, "OVERLAY", "GameFontGreenLarge"); pl:SetPoint("TOPRIGHT", -3, -1); pl:SetText("+")
        end
        if selS == s then border(bt, 1, 0.82, 0) end
        bt:SetScript("OnClick", function()
            if IsShiftKeyDown and IsShiftKeyDown() and ns.PetSpellClick then pcall(ns.PetSpellClick, s); return end
            M.sel, M.selRank = s.en, nil; UI.petMineSel = s.en; ctx.refresh(true)
        end)
        bt:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, s.id)
            if not ok or (GameTooltip:NumLines() or 0) == 0 then GameTooltip:ClearLines(); GameTooltip:AddLine(skName(s), 1, 0.82, 0) end
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine(ns.L("已学", "Learned"), lr .. " / " .. mx, 0.7, 0.7, 0.7, 1, 1, 1)
            if petHas[s.en] then GameTooltip:AddDoubleLine(ns.L("当前宠物", "Current pet"), ns.L("等级 ", "Rank ") .. petHas[s.en], 0.7, 0.7, 0.7, 1, 0.82, 0) end
            if nextOk then GameTooltip:AddLine(GREEN .. ns.L("现在就能去学下一级", "Next rank learnable now") .. "|r") end
            if curFam and not famHas(curFam, s) then GameTooltip:AddLine(GREY .. ns.L("当前宠物家族学不了", "Your pet's family can't learn this") .. "|r") end
            GameTooltip:Show()
        end)
        bt:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    y = y - math.ceil(#list / M.COLS) * (TS + 3) - 8

    -- ④ 选中技能：等级按钮 → 会教这一级的野兽按钮
    if selS then
        local lr, mx = learned[selS.en] or 0, selS.ranks or 1
        local Tm = T()
        local ranks = (Tm and Tm.Ranks) and Tm.Ranks(selS.en) or {}
        local tameable = {}
        for _, r in ipairs(ranks) do tameable[r] = true end
        local rank = M.selRank
        if not rank or rank > mx then
            rank = nil
            for r = lr + 1, mx do if tameable[r] then rank = r; break end end
            rank = rank or (tameable[mx] and mx) or ranks[#ranks]
        end
        local panel = ctx.box(0, y, 618, 10, false)
        local ic = panel:CreateTexture(nil, "ARTWORK"); ic:SetSize(36, 36); ic:SetPoint("TOPLEFT", 8, -8)
        ic:SetTexture(skillIcon(selS.id)); ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        ctx.text(panel, "GameFontNormal", 52, -10, 200, skName(selS)):SetWordWrap(false)
        ctx.text(panel, "GameFontDisableSmall", 52, -28, 200, lr .. " / " .. mx)
        for r = 1, mx do
            local rb = sqButton(panel, 260 + (r - 1) * 32, -12, 28, 28)
            local t = rb:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); t:SetPoint("CENTER"); t:SetText(r)
            if r <= lr then rb:SetBackdropColor(0.10, 0.35, 0.15, 0.95); t:SetTextColor(0.6, 1, 0.6)
            elseif not tameable[r] then t:SetTextColor(0.45, 0.45, 0.45) end
            if r > lr and M.CanLearn(selS.en, r) then border(rb, 0.2, 0.9, 0.4) end
            if r == rank then border(rb, 1, 0.82, 0) end
            rb:SetScript("OnClick", function() M.selRank = r; ctx.refresh(true) end)
            rb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(skName(selS) .. " " .. ns.L("等级 ", "Rank ") .. r, 1, 0.82, 0)
                GameTooltip:AddLine(r <= lr and (GREEN .. ns.L("已学会", "Learned") .. "|r")
                    or (tameable[r] and ns.L("点了看哪只野兽会教", "Click to see which beasts teach it") or (GREY .. ns.L("没有野兽教（驯服即会 / 等级到了自动会）", "No beast teaches this rank") .. "|r")), 1, 1, 1, true)
                GameTooltip:Show()
            end)
            rb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        local yy = -52
        local teach = (rank and Tm and Tm.Teachers) and Tm.Teachers(selS.en, rank) or {}
        local lv = myLevel()
        table.sort(teach, function(a, b)
            local oa, ob = (a.lo or 99) <= lv, (b.lo or 99) <= lv
            if oa ~= ob then return oa end
            if oa then return (a.lo or 0) > (b.lo or 0) end   -- 能抓的：离我等级最近的先
            return (a.lo or 0) < (b.lo or 0)
        end)
        for j = 1, math.min(#teach, M.TEACH_SHOW) do
            local b = teach[j]
            local col, row = (j - 1) % 3, math.floor((j - 1) / 3)
            local bt = sqButton(panel, 8 + col * 202, yy - row * 32, 198, 28)
            local bf = M.BeastFam(b.id)
            local bi = bt:CreateTexture(nil, "ARTWORK"); bi:SetSize(22, 22); bi:SetPoint("LEFT", 3, 0)
            bi:SetTexture(bf and bf.icon and bf.icon > 0 and bf.icon or "Interface\\Icons\\Ability_Hunter_BeastTaming"); bi:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            if (b.lo or 99) > lv then bi:SetDesaturated(true) end
            local pin = bt:CreateTexture(nil, "ARTWORK"); pin:SetSize(16, 16); pin:SetPoint("RIGHT", -4, 0)
            pin:SetTexture("Interface\\Icons\\INV_Misc_Map_01"); pin:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local t = bt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); t:SetPoint("LEFT", 29, 0); t:SetWidth(198 - 29 - 24)
            t:SetJustifyH("LEFT"); t:SetWordWrap(false)
            local okLv = (b.lo or 99) <= lv
            t:SetText((okLv and "|cffffffff" or GREY) .. beastName(b) .. "|r " .. (okLv and GREEN or "|cffff5555") .. (b.lo or "?") .. "|r")
            bt:SetScript("OnClick", function() if Tm.ShowBeast then Tm.ShowBeast(b) end end)
            bt:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(beastName(b), 1, 0.82, 0)
                GameTooltip:AddDoubleLine(ns.L("等级", "Level"), (b.lo or "?") .. ((b.hi and b.hi ~= b.lo) and ("-" .. b.hi) or ""), 0.7, 0.7, 0.7, 1, 1, 1)
                if Tm.ZoneName then GameTooltip:AddDoubleLine(ns.L("地区", "Zone"), Tm.ZoneName(b.ui), 0.7, 0.7, 0.7, 1, 1, 1) end
                if b.x then GameTooltip:AddDoubleLine(ns.L("坐标", "Coords"), string.format("%.1f, %.1f", b.x, b.y or 0), 0.7, 0.7, 0.7, 1, 1, 1) end
                if Tm.Verified and Tm.Verified(b, selS.en, rank) then GameTooltip:AddLine(GREEN .. ns.L("《无限》驯服实测过", "Verified in Forever") .. "|r") end
                GameTooltip:AddLine(ns.L("点：地图标点", "Click: show on map"), 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end)
            bt:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        local rows = math.ceil(math.min(#teach, M.TEACH_SHOW) / 3)
        if #teach == 0 then
            ctx.text(panel, "GameFontDisableSmall", 8, yy - 4, 600, GREY .. ns.L("这一级没有野兽教", "No beast teaches this rank") .. "|r")
            rows = 1
        end
        local h = -yy + rows * 32 + 6
        panel:SetHeight(h)
        y = y - h - 4
    end
    c:SetHeight(-y + 4)
end
