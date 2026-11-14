-- 猎人宠物页（10-18 用户转抖音「猎人宠物攻略」：「整合进插件」→「资讯分类下面有猎人宠物攻略」）
--   三个视图：家族（18 个家族的伤害 / 护甲 / 生命加成 + 会的技能）· 技能（22 个技能：适用家族、集中值、冷却、学会等级、说明）· 怎么选
--   11-05 第 4 个视图「在哪抓」+ 技能下面「会教的野兽」：代码在 PetTame.lua（HOLD），没加载时这里照旧三个视图
-- 数据：PetData.lua（scripts/gi_forever_pets.py 从《无限》客户端 DB2 生成；⛔不搬攻略图）
-- 所有职业都能看（资讯类攻略），猎人自己的当前宠物家族高亮
local _, ns = ...; ns = _G.GearInsightForever or ns

local GREEN, RED, GREY = "|cff33ff66", "|cffff5555", "|cff888888"

local function pct(v)
    if not v or v == 0 then return GREY .. "—|r" end
    return (v > 0 and GREEN .. "+" or RED) .. v .. "%|r"
end

-- 技能链接（客户端给的优先；没有就自己拼，聊天 / 弹框都认 |Hspell:id|h）
local function spellLink(s)
    local l
    if C_Spell and C_Spell.GetSpellLink then local ok, v = pcall(C_Spell.GetSpellLink, s.id); if ok then l = v end end
    if not l and GetSpellLink then local ok, v = pcall(GetSpellLink, s.id); if ok then l = v end end
    return l or ("|cff71d5ff|Hspell:" .. s.id .. "|h[" .. ns.L(s.cn, s.en) .. "]|h|r")
end
-- 点技能：Shift = 链接插进聊天输入框；否则弹出游戏自带的技能说明框（和点聊天里的技能链接一样，可拖可关）
function ns.PetSpellClick(s)
    local link = spellLink(s)
    if IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
        if ChatEdit_InsertLink(link) then return end
    end
    if SetItemRef then SetItemRef("spell:" .. s.id, link, "LeftButton")
    elseif ItemRefTooltip and ItemRefTooltip.SetHyperlink then
        ShowUIPanel(ItemRefTooltip); ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE"); ItemRefTooltip:SetHyperlink("spell:" .. s.id)
    end
end

local function skillIcon(id)
    local t
    if C_Spell and C_Spell.GetSpellTexture then t = C_Spell.GetSpellTexture(id) end
    if not t and GetSpellTexture then t = GetSpellTexture(id) end
    return t or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function famById()
    local t = {}
    for _, f in ipairs(ns.PetData.families) do t[f.id] = f end
    return t
end

local function skillByEn()
    local t = {}
    for _, s in ipairs(ns.PetData.skills) do t[s.en] = s end
    return t
end

-- 猎人当前宠物的家族（中文客户端 UnitCreatureFamily 返回中文名）
local function myPetFamily()
    if not UnitExists or not UnitExists("pet") or not UnitCreatureFamily then return nil end
    return UnitCreatureFamily("pet")
end

local function skillTag(s)
    if s.new then return " |cffff9933" .. ns.L("无限新增", "New") .. "|r" end
    if s.renamed then return " |cff66aaff" .. ns.L("改名", "Renamed") .. "|r" end
    return ""
end

local function lvText(s)
    if (s.lv or 0) > 0 then
        return ns.L(s.lv .. " 级学", "Lv " .. s.lv) .. (s.maxlv > s.lv and ns.L("·" .. s.maxlv .. " 级满", "-" .. s.maxlv) or "")
    end
    return ns.L("驯服即会", "Innate")
end

local function famNames(ids)
    local fb, out = famById(), {}
    for _, id in ipairs(ids) do
        local f = fb[id]
        if f then out[#out + 1] = ns.L(f.cn, f.en) end
    end
    return out
end

local function views()
    if ns.PetTame and ns.PetTameData then return { "fam", "skill", "pick", "tame" } end
    return { "fam", "skill", "pick" }
end

local function build(p)
    local D = ns.PetData
    local y0 = ns.PageHeader(p, ns.L("猎人宠物", "Hunter pets"),
        ns.L(#D.families .. " 个家族 · " .. #D.skills .. " 个技能 · 数据取自《无限》客户端 " .. D.build,
            #D.families .. " families · " .. #D.skills .. " abilities · from client " .. D.build))
    p.seg = {}
    local labels = { fam = ns.L("家族属性", "Families"), skill = ns.L("宠物技能", "Abilities"), pick = ns.L("怎么选", "Which pet"), tame = ns.L("在哪抓", "Where to tame") }
    local VIEWS = views()
    for i, v in ipairs(VIEWS) do
        local b = ns.SegButton(p, labels[v], 96, 22, function() p.view = v; ns.db.ui = ns.db.ui or {}; ns.db.ui.petView = v; p.refreshView() end)
        b:SetPoint("TOPLEFT", 12 + (i - 1) * 100, y0 - 2)
        p.seg[v] = b
    end
    local sf, c = ns.Scroll(p, 8, y0 - 32, 626, 474 - 42 - 36)
    p.sf, p.c = sf, c
    p.items = {}

    local function clear()
        GameTooltip:Hide()
        for _, it in ipairs(p.items) do it:Hide() end
        p.items = {}
    end
    local function text(parent, tpl, x, y, w, s)
        local fs = parent:CreateFontString(nil, "OVERLAY", tpl)
        fs:SetPoint("TOPLEFT", x, y); if w then fs:SetWidth(w) end
        fs:SetJustifyH("LEFT"); fs:SetText(s)
        return fs
    end
    local function box(x, y, w, h, hi)
        local f = CreateFrame("Frame", nil, c, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetPoint("TOPLEFT", x, y); f:SetSize(w, h)
        if f.SetBackdrop then
            f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            f:SetBackdropColor(0.07, 0.08, 0.10, 0.9)
            if hi then f:SetBackdropBorderColor(1, 0.82, 0, 0.95) else f:SetBackdropBorderColor(0.28, 0.28, 0.30, 0.9) end
        end
        p.items[#p.items + 1] = f
        return f
    end

    -- 家族：3 列卡片（图标 + 名字 + 三项加成 + 专属技能）；悬停看全部技能
    local function viewFam()
        local sb, mine = skillByEn(), myPetFamily()
        local W, H, GAP = 204, 112, 6
        for i, f in ipairs(D.families) do
            local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
            local isMine = mine and (mine == f.cn or mine == f.en)
            local b = box(col * (W + GAP), -row * (H + GAP), W, H, isMine)
            local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(36, 36); ic:SetPoint("TOPLEFT", 6, -6)
            ic:SetTexture(f.icon and f.icon > 0 and f.icon or "Interface\\Icons\\Ability_Hunter_BeastTaming")
            ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local title = text(b, "GameFontNormal", 48, -7, W - 56, ns.L(f.cn, f.en))
            title:SetWordWrap(false); title:SetMaxLines(1)
            local badge = isMine and ns.L("当前宠物", "Current pet") or (f.new and ns.L("无限新家族", "New family") or ns.L("宠物家族", "Pet family"))
            text(b, "GameFontDisableSmall", 48, -25, W - 56, badge):SetWordWrap(false)
            -- Each stat has its own column: labels and values never share a wrapping line.
            local stats = { { ns.L("伤害", "Damage"), f.dmg }, { ns.L("护甲", "Armor"), f.arm }, { ns.L("生命", "Health"), f.hp } }
            for j, stat in ipairs(stats) do
                local x = 8 + (j - 1) * 64
                local label = text(b, "GameFontDisableSmall", x, -47, 60, stat[1])
                label:SetWordWrap(false); label:SetJustifyH("CENTER")
                local value = text(b, "GameFontHighlight", x, -63, 60, pct(stat[2]))
                value:SetWordWrap(false); value:SetJustifyH("CENTER")
            end
            -- 专属 = 只有 1~4 个家族会的（撕咬 / 突进 / 爪击 这种大家都有的不列）
            local own = {}
            for _, en in ipairs(f.skills) do
                local s = sb[en]
                if s and #s.fams <= 4 then own[#own + 1] = ns.L(s.cn, s.en) end
            end
            local o = text(b, "GameFontDisableSmall", 8, -87, W - 16, ns.L("专属：", "Own: ") .. (#own > 0 and table.concat(own, "、") or "—"))
            o:SetWordWrap(false); o:SetMaxLines(1)
            b:EnableMouse(true)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, col == 2 and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
                GameTooltip:AddLine(ns.L(f.cn, f.en), 1, 0.82, 0)
                if ns.zh then GameTooltip:AddLine(f.en, 0.6, 0.6, 0.6) end
                GameTooltip:AddLine(" ")
                for _, en in ipairs(f.skills) do
                    local s = sb[en]
                    if s then GameTooltip:AddDoubleLine(ns.L(s.cn, s.en) .. skillTag(s), lvText(s), 1, 1, 1, 0.7, 0.7, 0.7) end
                end
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        c:SetHeight(math.ceil(#D.families / 3) * (H + GAP))
        local note = box(0, -math.ceil(#D.families / 3) * (H + GAP), 626, 22)
        note:SetBackdropColor(0, 0, 0, 0); note:SetBackdropBorderColor(0, 0, 0, 0)
        text(note, "GameFontDisableSmall", 2, -4, 620, ns.L("伤害 = 宠物输出加成 · 护甲 = 减伤 · 生命 = 血量；负数 = 这项被削弱；金框 = 你现在的宠物",
            "Dmg / Armor / HP modifiers; negative = penalty; gold frame = your current pet"))
        c:SetHeight(math.ceil(#D.families / 3) * (H + GAP) + 24)
    end

    -- 技能：一行一个，按「会的家族多 → 少」排
    local function viewSkill()
        local y = 0
        for _, s in ipairs(D.skills) do
            local fams = famNames(s.fams)
            local desc = ns.L(s.dcn, s.den)
            local b = box(0, y, 610, 10, false)
            local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(32, 32); ic:SetPoint("TOPLEFT", 6, -6)
            ic:SetTexture(skillIcon(s.id)); ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            text(b, "GameFontNormal", 46, -5, 300, ns.L(s.cn, s.en) .. (ns.zh and (" " .. GREY .. s.en .. "|r") or "") .. skillTag(s))
            local meta = (s.cost > 0 and (s.cost .. ns.L(" 集中", " focus")) or "") .. "  "
                .. (s.cd > 0 and (s.cd .. ns.L(" 秒冷却", "s CD")) or ns.L("无冷却", "no CD")) .. "  " .. lvText(s)
            local m = text(b, "GameFontHighlightSmall", 300, -6, 304, "|cffffcc66" .. meta .. "|r"); m:SetJustifyH("RIGHT")
            local fl = text(b, "GameFontDisableSmall", 46, -22, 556,
                (#s.fams >= 10 and ns.L(#s.fams .. " 个家族都会", #s.fams .. " families") .. "：" or ns.L("适用：", "Families: ")) .. table.concat(fams, "、"))
            fl:SetWordWrap(true)
            local d = text(b, "GameFontHighlightSmall", 46, -22 - fl:GetStringHeight() - 3, 556, desc)
            d:SetWordWrap(true)
            local h = math.max(44, 22 + fl:GetStringHeight() + 3 + d:GetStringHeight() + 8)
            -- 11-05 会教的野兽（PetTame.lua，HOLD；没加载 = 不画）
            if ns.PetTame and ns.PetTame.SkillTeachers then
                local ok, extra = pcall(ns.PetTame.SkillTeachers, b, s, -(22 + fl:GetStringHeight() + 3 + d:GetStringHeight() + 6))
                if ok and (extra or 0) > 0 then h = math.max(h, 22 + fl:GetStringHeight() + 3 + d:GetStringHeight() + 6 + extra + 4) end
            end
            b:SetHeight(h)
            -- 10-18 用户「技能能索引到游戏内的可以点击的弹出技能说明」：悬停 = 游戏自带技能提示；点 = 弹出可固定的技能说明框；Shift+点 = 发链接到聊天
            b:EnableMouse(true)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, s.id)
                if not ok or (GameTooltip:NumLines() or 0) == 0 then   -- 客户端查不到这个法术：用我们自己的说明
                    GameTooltip:ClearLines(); GameTooltip:AddLine(ns.L(s.cn, s.en), 1, 0.82, 0); GameTooltip:AddLine(desc, 1, 1, 1, true)
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(ns.L("点击：弹出技能说明 · Shift+点击：发到聊天", "Click: pop out the spell · Shift-click: link in chat"), 0.6, 0.6, 0.6, true)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:SetScript("OnMouseUp", function() pcall(ns.PetSpellClick, s) end)
            y = y - h - 4
        end
        c:SetHeight(-y)
    end

    -- 怎么选：两组按数据现算（伤害 / 生存），两组按技能挑（团队增益 / 控制抢怪）
    local function viewPick()
        local fams = {}
        for _, f in ipairs(D.families) do fams[#fams + 1] = f end
        local function top(key, n)
            local t = {}
            for _, f in ipairs(fams) do t[#t + 1] = f end
            table.sort(t, function(a, b) local va, vb = key(a), key(b); if va ~= vb then return va > vb end return a.id < b.id end)
            local out = {}
            for i = 1, n do
                if t[i] and key(t[i]) > 0 then out[#out + 1] = ns.L(t[i].cn, t[i].en) end
            end
            return table.concat(out, "、")
        end
        local sb = skillByEn()
        local function bySkills(list)
            local out = {}
            for _, row in ipairs(list) do
                local s = sb[row[1]]
                if s then
                    local fn = famNames(s.fams)[1] or "?"
                    out[#out + 1] = fn .. "「" .. ns.L(s.cn, s.en) .. "」" .. row[2]
                end
            end
            return table.concat(out, "\n")
        end
        local cards = {
            { ns.L("练级 · 伤害优先", "Leveling · damage"),
              ns.L("伤害加成最高：", "Highest damage: ") .. top(function(f) return f.dmg end, 6)
                .. ns.L("\n配撕咬 / 爪击输出，任务怪快进快出", "\nUse Bite / Claw") },
            { ns.L("扛怪 · 生存优先", "Tanking · survival"),
              ns.L("护甲 + 生命加成最高：", "Most armor + HP: ") .. top(function(f) return f.arm + f.hp end, 6)
                .. ns.L("\n拉多只怪、打精英更稳", "\nSafer on packs and elites") },
            { ns.L("团队增益", "Group buffs"),
              bySkills({ { "Furious Howl", ns.L("队友近战攻强", " party melee AP") }, { "Trickster's Dance", ns.L("躲闪 + 攻速", " dodge + haste") },
                         { "Demoralizing Screech", ns.L("削怪攻强", " lowers enemy AP") }, { "Dust Cloud", ns.L("降护甲", " armor reduction") } }) },
            { ns.L("控制 · 抢怪 / PvP", "Control · tagging / PvP"),
              bySkills({ { "Pinch", ns.L("减速", " slow") }, { "Web", ns.L("定身", " root") }, { "Tendon Rip", ns.L("减速", " slow") },
                         { "Charge", ns.L("定身", " root") }, { "Sonic Blast", ns.L("施法变慢", " slower casts") }, { "Mine!", ns.L("缴械", " disarm") } }) },
        }
        local W, GAP = 305, 8
        local yy = 0
        for i, cd in ipairs(cards) do
            local col = (i - 1) % 2
            local b = box(col * (W + GAP), yy, W, 150, false)
            text(b, "GameFontNormal", 10, -8, W - 20, cd[1])
            local t = text(b, "GameFontHighlightSmall", 10, -28, W - 20, cd[2]); t:SetWordWrap(true); t:SetSpacing(3)
            if col == 1 then yy = yy - 150 - GAP end
        end
        local note = box(0, yy, 618, 40)
        note:SetBackdropColor(0, 0, 0, 0); note:SetBackdropBorderColor(0, 0, 0, 0)
        text(note, "GameFontDisableSmall", 2, -4, 614, ns.L("突进和俯冲同样是移速 +80%，按家族二选一。数值来自客户端数据，以游戏内鼠标提示为准。",
            "Dash and Dive are both +80% speed. Numbers come from client data; in-game tooltips win."))
        c:SetHeight(-yy + 44)
    end

    p.refreshView = function()
        clear()
        for v, b in pairs(p.seg) do ns.SegSelect(b, v == p.view) end
        if p.view == "tame" and ns.PetTame and ns.PetTameData then
            ns.PetTame.View({ p = p, c = c, box = box, text = text, mine = myPetFamily(), refresh = p.refreshView })
        elseif p.view == "skill" then viewSkill() elseif p.view == "pick" then viewPick() else viewFam() end
        if sf.SetVerticalScroll then sf:SetVerticalScroll(0) end
    end
    p.view = (ns.db.ui and ns.db.ui.petView) or "fam"
    if p.view == "tame" and not p.seg.tame then p.view = "fam" end   -- 上次看的「在哪抓」被 HOLD 剔掉了
    ns.PetPage = p
end

local function refresh(p)
    if p.refreshView then p.refreshView() end
end

ns.RegisterPage({ key = "pet", order = 3.6, class = "Hunter",   -- 11-10 挪进职业百宝箱，只给猎人看
 title = ns.L("猎人宠物", "Hunter pets"), tabTitle = ns.L("猎人宠物", "Hunter pets"),
    icon = "Interface\\Icons\\Ability_Hunter_BeastTaming", hold = true, build = build, refresh = refresh })
