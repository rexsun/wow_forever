-- 手法页（10-12，照正式服 10-12「阶段 3」把键位 / 手法拆成两个独立页签：GearInsight_Rotation/ui/RotationPage.lua BuildRotationPage）
--   正式服结构：顶部「控制台」卡（左 = 现在该按：大图标 + 键 + 名字 + 为什么；右 = 开关一列）→ 循环来源单选（每行 名字 + 依据 + 「正在用」）
--     → 整套循环技能（每格下面印你条上的键）→ 教练解读。
--   《无限》差异：没有暴雪官方循环助手（C_AssistedCombat）和 WCL 数据 → 「现在该按」只走 GI 基础手法引擎（KeysRot.lua）；
--     没有冷却管理器键帽开关，换成「决策 HUD」开关；教练解读 = 手写规则表逐条讲（KeysRotData.lua 的 why / when）；
--     起手序列（正式服 WCL 顶尖玩家开怪）没有数据，不做、不放空壳。
--   能力探针 / 公测众包施法频率（原键位手法页「高级」里的）挪到这页底部：两个都是给手法用的。
-- ⛔ HOLD（_hold.txt），测完才进包。⛔ 只读：IsSpellUsable / 冷却 / 绑定，不改动作条。
local _, ns = ...
local K = ns.Keys
local GOLD = { 1, 0.82, 0 }

local page

-- 循环来源（设计稿 §5.1）：按「职业 · 天赋系」记住选择；没数据的灰着写「制作中」
local SOURCES = {
    { key = "hand", n = { "GI 基础手法", "GI basic" }, d = { "按经典成熟打法 + 《无限》技能改动手写的优先级", "Hand-written priority from classic play + Forever changes" } },
    { key = "beta", n = { "GI 顶尖手法 · 公测版", "GI top · beta" }, d = { "从公测玩家的真实按法里学（数据收集中：页面底部勾「贡献我的施法频率」）", "Learned from beta players' casts (collecting data - tick 'Share my cast frequency' below)" }, off = true },
    { key = "wcl", n = { "GI 顶尖手法 · 地下城 / 团本", "GI top · dungeon / raid" }, d = { "WarcraftLogs 收录《无限》后，从排名前列的日志里学", "From top WarcraftLogs logs once Forever is supported" }, off = true },
}
local function srcKey()
    local tree = K.MainTree()
    return ns.MyClass() .. ":" .. (tree or 0)
end
function ns.KeysSource()
    ns.db.keysSrc = ns.db.keysSrc or {}
    return ns.db.keysSrc[srcKey()] or "hand"
end

-- 规则条件 → 人话（教练解读用）
local function condText(w)
    local cond, arg = w:match("^(%a+)([<>=:].*)$")
    cond = cond or w
    local n = arg and arg:match("[%d.]+")
    if w == "ready" then return ns.L("转好就按", "on cooldown") end
    if w == "proc" then return ns.L("触发后才能按", "only after it procs") end
    if cond == "res" then return string.format(ns.L("怒气 / 能量 >= %s", "rage / energy >= %s"), n or "?") end
    if cond == "mana" then return string.format(ns.L("法力 < %s%%", "mana < %s%%"), n or "?") end
    if cond == "cp" then return string.format(ns.L("连击点 >= %s", "combo points >= %s"), n or "?") end
    if cond == "dot" then return string.format(ns.L("目标身上剩 < %s 秒", "< %ss left on target"), n or "?") end
    if cond == "buff" then return string.format(ns.L("增益剩 < %s 秒", "buff < %ss left"), n or "?") end
    if cond == "stack" then return string.format(ns.L("层数 < %s", "stacks < %s"), n or "?") end
    if cond == "targets" then return string.format(ns.L("%s 个以上目标", "%s+ targets"), n or "?") end
    if cond == "known" then return string.format(ns.L("学会了%s", "knows %s"), arg:sub(2)) end
    return w
end

-- 规则里的技能名 → 铺条数据条目 + 当前客户端编号 / 名字
local function ruleSpell(cls, cast)
    for _, e in ipairs((ns.Data.keys or {})[cls] or {}) do
        if e.n == cast then
            local id, nm = K.Resolve(e)
            return e, id, nm
        end
    end
end

local function lbl(parent, font, x, y, w)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", x or 0, y or 0)
    if w then fs:SetWidth(w) end
    fs:SetJustifyH("LEFT")
    return fs
end
-- 段标题下的金线（正式服 ruled）
local function ruled(p, fs)
    local r = p:CreateTexture(nil, "ARTWORK"); r:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25); r:SetHeight(1)
    r:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3); r:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    fs._rule = r
    return fs
end

-- ---------- 现在该按（0.2 秒刷一次，页面不显示就停 —— 正式服 tickNext 同规则）----------
local function tickNext()
    if not (page and page:IsShown()) then return end
    local R = ns.KeysRot
    local s = R and R.Next and R.Next()
    local c = page.card
    if s then
        c.icon:SetTexture((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(s.id)) or (GetSpellTexture and GetSpellTexture(s.id)) or "Interface\\Icons\\INV_Misc_QuestionMark")
        c.icon:SetDesaturated(false)
        c.key:SetText(s.key and ns.KeysShortKey(s.key) or (s.onBar and "|cffff5555?|r" or ""))
        c.name:SetText(s.name .. (s.onBar and "" or ns.L("  |cffff5555不在条上|r", "  |cffff5555not on bars|r")))
        c.why:SetText(ns.L(s.why[1], s.why[2]))
        local basis = {}
        for _, w in ipairs((s.rule and s.rule.when) or {}) do basis[#basis + 1] = condText(w) end
        c.basis:SetText(ns.L("依据：", "Because: ") .. table.concat(basis, " · ") .. (s.est and ns.L("  |cff888888（部分按施法推算）|r", "  |cff888888(partly estimated)|r") or ""))
    else
        c.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark"); c.icon:SetDesaturated(true)
        c.key:SetText("")
        local T = R and R.Current and R.Current()
        c.name:SetText(T and ns.L("（无目标 / 现在没有该按的）", "(no target / nothing to press)") or ns.L("这个职业的手法还没做", "No rotation for this class yet"))
        c.why:SetText(T and "" or ns.L("首批：战士 / 盗贼 / 术士", "First batch: Warrior / Rogue / Warlock"))
        c.basis:SetText("")
    end
end
ns._RotTick = tickNext   -- 测试用

local function getSrcRow(i)
    local r = page.srcRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, page.child, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if r.SetBackdrop then r:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }) end
    -- 正式服 10-09：小绿点换成游戏自带单选圆钮；选中行深金底 + 亮金边 + 右侧「正在用」；没选中的行悬停边框变亮
    r.radio = CreateFrame("CheckButton", nil, r, "UIRadioButtonTemplate"); r.radio:SetSize(20, 20); r.radio:SetPoint("LEFT", 8, 0)
    r.radio:SetScript("OnClick", function(rb) local p = rb:GetParent(); rb:SetChecked(p._on); if p:GetScript("OnClick") then p:GetScript("OnClick")(p) end end)
    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.title:SetPoint("TOPLEFT", 36, -6); r.title:SetJustifyH("LEFT")
    r.desc = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.desc:SetPoint("TOPLEFT", 36, -24); r.desc:SetPoint("RIGHT", -96, 0)
    r.desc:SetJustifyH("LEFT"); r.desc:SetWordWrap(true)
    r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.tag:SetPoint("TOPRIGHT", -12, -6)
    r:SetScript("OnEnter", function(x) if not x._on and not x._soon and x.SetBackdropBorderColor then x:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.75) end end)
    r:SetScript("OnLeave", function(x) if not x._on and x.SetBackdropBorderColor then x:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], x._soon and 0.12 or 0.3) end end)
    page.srcRows[i] = r
    return r
end

local function getRotCell(i)
    local c = page.rotCells[i]
    if c then return c end
    c = CreateFrame("Button", nil, page.child)
    c:SetSize(34, 34)
    c.icon = c:CreateTexture(nil, "ARTWORK"); c.icon:SetAllPoints(); c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.num = c:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall"); c.num:SetPoint("TOPLEFT", 2, -2)
    c.key = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); c.key:SetPoint("TOP", c, "BOTTOM", 0, -2); c.key:SetWidth(40); c.key:SetWordWrap(false)
    local hl = c:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
    c:SetScript("OnEnter", function(self)
        local r = self.r
        if not r then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(string.format("%d. %s", self.i or 0, self.nm or r.cast), 1, 0.82, 0)
        GameTooltip:AddLine(ns.L(r.why[1], r.why[2]), 1, 1, 1, true)
        local cs = {}
        for _, w in ipairs(r.when or {}) do cs[#cs + 1] = condText(w) end
        if #cs > 0 then GameTooltip:AddLine(table.concat(cs, " · "), 0.7, 0.7, 0.7, true) end
        if not self.id then GameTooltip:AddLine(ns.L("还没学会", "Not learned yet"), 0.6, 0.6, 0.6)
        elseif not self.onBar then GameTooltip:AddLine(ns.L("不在动作条上 · 去「键位」页点「—」放上去", "Not on your bars - place it on the Keys page"), 1, 0.4, 0.4, true) end
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c:SetScript("OnClick", function(self) if not self.onBar and self.id then ns.ShowPage("keys") end end)
    page.rotCells[i] = c
    return c
end

local function refresh()
    if not page or not page:IsShown() then return end
    local vt = page.child
    local R = ns.KeysRot
    local T, cls, tree = nil, ns.MyClass(), nil
    if R and R.Current then T, cls, tree = R.Current() end
    page.boardCb:SetChecked(ns.db.keysBoard and true or false)
    page.hudCb:SetChecked(ns.db.keysHud and true or false)
    tickNext()
    -- ① 循环来源（单选，按职业 · 天赋系记）
    local y = -122
    page.srcHd:ClearAllPoints(); page.srcHd:SetPoint("TOPLEFT", 10, y)
    page.srcHd:SetText(ns.L("循环来源 · 选一个（记住你的选择，按职业 · 天赋系分开记）", "Rotation source - pick one (remembered per class and tree)"))
    y = y - 22
    local cur = ns.KeysSource()
    for i, s in ipairs(SOURCES) do
        local r = getSrcRow(i)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", vt, "TOPLEFT", 6, y); r:SetPoint("RIGHT", vt, "RIGHT", -12, 0)
        local on, soon = (s.key == cur), s.off
        r._on, r._soon = on, soon
        r.radio:SetChecked(on); r.radio:SetEnabled(not soon)
        r.title:SetText((soon and "|cff777777" or (on and "|cffffd100" or "|cffeeeeee")) .. ns.L(s.n[1], s.n[2]) .. "|r"
            .. (soon and ("  |cff777777" .. ns.L("制作中", "coming") .. "|r") or ""))
        r.tag:SetText(on and ("|TInterface\\RaidFrame\\ReadyCheck-Ready:16|t |cff40e060" .. ns.L("正在用", "in use") .. "|r") or "")
        local stat
        if s.key == "hand" then
            stat = T and string.format(ns.L("本系：%s · %d 条规则", "This tree: %s - %d rules"), ns.L(T.name[1], T.name[2]), #T.rules)
                or ns.L("这个职业还没做（首批：战士 / 盗贼 / 术士）", "Not done for this class yet (first: Warrior / Rogue / Warlock)")
        end
        r.desc:SetText((soon and "|cff666666" or (on and "|cffdddddd" or "|cffaaaaaa")) .. ns.L(s.d[1], s.d[2]) .. "|r"
            .. (stat and ("\n" .. (on and "|cffffe9a0" or "|cff999999") .. stat .. "|r") or ""))
        local sh = r.desc.GetStringHeight and r.desc:GetStringHeight()
        local h = 32 + math.min(30, math.max(14, (type(sh) == "number" and sh) or 14))
        r:SetHeight(h)
        if r.SetBackdropColor then
            if on then r:SetBackdropColor(0.42, 0.31, 0.04, 0.55); r:SetBackdropBorderColor(1, 0.82, 0.1, 1)
            else r:SetBackdropColor(0.06, 0.06, 0.09, soon and 0.4 or 0.75); r:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], soon and 0.12 or 0.3) end
        end
        r:SetScript("OnClick", (not soon and not on) and function()
            ns.db.keysSrc = ns.db.keysSrc or {}
            ns.db.keysSrc[srcKey()] = s.key
            if ns.KeysRotChanged then ns.KeysRotChanged() end
            refresh()
        end or nil)
        r:Show()
        y = y - h - 4
    end
    y = y - 10
    -- ② 整套循环技能（优先级从左到右，每格下面印你条上的键）
    page.rotHd:ClearAllPoints(); page.rotHd:SetPoint("TOPLEFT", 10, y)
    page.rotHd:SetText(T and string.format(ns.L("循环技能 · %s（%s）· 优先级从左到右，格子下面 = 你条上的键", "Rotation - %s (%s) - priority left to right, your key under each"),
        ns.L(T.name[1], T.name[2]), tree and string.format(ns.L("第 %d 系", "tree %d"), tree) or ns.L("升级期", "levelling"))
        or ns.L("循环技能", "Rotation"))
    y = y - 24
    for _, c in ipairs(page.rotCells) do c:Hide() end
    local live = K.LiveMap()
    local seen, n = {}, 0
    local rules = T and T.rules or {}
    for _, r in ipairs(rules) do
        if not seen[r.cast] then
            seen[r.cast] = true
            n = n + 1
            local e, id, nm = ruleSpell(cls, r.cast)
            local c = getRotCell(n)
            c.r, c.i, c.id, c.nm = r, n, id, nm
            local l = nm and live[nm]
            c.onBar = l ~= nil
            c:ClearAllPoints(); c:SetPoint("TOPLEFT", 12 + ((n - 1) % 14) * 42, y - math.floor((n - 1) / 14) * 54)
            c.icon:SetTexture("Interface\\Icons\\" .. ((e and (e.i or "") ~= "" and e.i) or "INV_Misc_QuestionMark"))
            c.icon:SetDesaturated(not id); c.icon:SetAlpha(id and 1 or 0.4)
            c.num:SetText(tostring(n))
            c.key:SetText((not id) and "|cff666666x|r" or (l and l.key and ns.KeysShortKey(l.key)) or (l and "|cffff5555?|r") or ns.L("|cffff5555未上条|r", "|cffff5555off bar|r"))
            c:Show()
        end
    end
    if n > 0 then y = y - math.ceil(n / 14) * 54 - 6 else
        page.rotEmpty:ClearAllPoints(); page.rotEmpty:SetPoint("TOPLEFT", 14, y); page.rotEmpty:Show(); y = y - 20
    end
    if n > 0 then page.rotEmpty:Hide() end
    -- ③ 教练解读：规则表逐条讲
    page.coachHd:ClearAllPoints(); page.coachHd:SetPoint("TOPLEFT", 10, y)
    page.coachHd:SetText(ns.L("教练解读 · 本系（从上往下，第一条满足的就是现在该按的）", "Coach notes - this tree (top to bottom; the first that applies is what to press)"))
    y = y - 22
    local lines = {}
    for i, r in ipairs(rules) do
        local cs = {}
        for _, w in ipairs(r.when or {}) do cs[#cs + 1] = condText(w) end
        local _, _, nm = ruleSpell(cls, r.cast)
        lines[#lines + 1] = string.format("|cffffd100%d.|r %s  |cffdddddd%s|r  |cff888888%s|r", i, nm or r.cast, ns.L(r.why[1], r.why[2]), table.concat(cs, " · "))
    end
    page.coach:ClearAllPoints(); page.coach:SetPoint("TOPLEFT", 14, y); page.coach:SetPoint("RIGHT", vt, "RIGHT", -16, 0)
    page.coach:SetText(#lines > 0 and table.concat(lines, "\n")
        or ns.L("|cff888888这个职业的 GI 基础手法还没做；先在「键位」页把技能铺好，手法做好后这里会讲每一步为什么。|r", "|cff888888No GI rotation for this class yet.|r"))
    local ch = page.coach.GetStringHeight and page.coach:GetStringHeight()
    y = y - ((type(ch) == "number" and ch) or (#lines * 16)) - 16
    vt:SetHeight(-y + 8)
end
ns._RotRefresh = refresh

local function build(p)
    page = p
    ns.RotPage = p   -- 测试用
    p.srcRows, p.rotCells = {}, {}
    ns.PageHeader(p, ns.L("手法", "Rotation"),
        ns.L("现在该按什么 · 钉到屏幕的循环助手 · 决策 HUD", "What to press now - on-screen rotation helper - decision HUD"))
    local sf, vt = ns.Scroll(p, 6, -40, 616, 474 - 40 - 44)
    p.scroll, p.child = sf, vt
    -- 顶部「控制台」卡（正式服 rt.card）：左 = 现在该按；右 = 两个开关一列
    local card = CreateFrame("Frame", nil, vt, BackdropTemplateMixin and "BackdropTemplate" or nil)
    card:SetPoint("TOPLEFT", 4, -2); card:SetPoint("RIGHT", vt, "RIGHT", -12, 0); card:SetHeight(110)
    if card.SetBackdrop then
        card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        card:SetBackdropColor(0.05, 0.05, 0.08, 0.7); card:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.35)
    end
    p.card = card
    card.hd = lbl(card, "GameFontNormal", 10, -7, 300); card.hd:SetText(ns.L("现在该按 · GI 手法（按你当前天赋系）", "Press now - GI rotation (your current tree)"))
    card.icon = card:CreateTexture(nil, "ARTWORK"); card.icon:SetSize(50, 50); card.icon:SetPoint("TOPLEFT", 12, -28); card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local fr = CreateFrame("Frame", nil, card, BackdropTemplateMixin and "BackdropTemplate" or nil)
    fr:SetPoint("TOPLEFT", card.icon, -1, 1); fr:SetPoint("BOTTOMRIGHT", card.icon, 1, -1)
    if fr.SetBackdrop then fr:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }); fr:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.8) end
    -- 键只留在图标角标上（正式服 10-10「大字 = 技能名、下一行 = 为什么、再下一行 = 依据」）
    card.key = fr:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge"); card.key:SetPoint("BOTTOMRIGHT", card.icon, "BOTTOMRIGHT", -1, 2)
    card.name = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge"); card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 12, 0); card.name:SetWidth(250); card.name:SetJustifyH("LEFT"); card.name:SetWordWrap(false)
    card.why = card:CreateFontString(nil, "OVERLAY", "GameFontNormal"); card.why:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 12, -22); card.why:SetWidth(250); card.why:SetJustifyH("LEFT"); card.why:SetWordWrap(false)
    card.basis = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); card.basis:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 12, -40); card.basis:SetWidth(250); card.basis:SetJustifyH("LEFT"); card.basis:SetWordWrap(false)
    card.note = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); card.note:SetPoint("BOTTOMLEFT", 10, 8); card.note:SetPoint("RIGHT", card, "RIGHT", -300, 0); card.note:SetJustifyH("LEFT"); card.note:SetWordWrap(false)
    card.note:SetText(ns.L("随目标 / 战斗实时变 · 红字 = 技能不在条上  |cff888888[?]|r", "Updates with target / combat - red = not on bars  |cff888888[?]|r"))
    -- 被截的字悬停看全（用户硬规定）
    local hit = CreateFrame("Frame", nil, card); hit:SetPoint("TOPLEFT", card.icon, "TOPLEFT"); hit:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -300, 0)
    hit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(card.name:GetText() or "", 1, 0.82, 0)
        GameTooltip:AddLine(card.why:GetText() or "", 1, 1, 1, true)
        GameTooltip:AddLine(card.basis:GetText() or "", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(ns.L("选中目标 / 进战斗后这里跟着变；键 = 你条上绑的（红问号 = 在条上但没键）；部分条件客户端读不到，按你的施法推算。",
            "Follows target / combat; key = what's bound on your bars (red ? = on bars, no key); some conditions are estimated from your casts."), 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- 右列：开关（文字在框右边、不出卡）
    local function switch(y, text, tip, onClick)
        local cb = CreateFrame("CheckButton", nil, card, "UICheckButtonTemplate"); cb:SetSize(24, 24); cb:SetPoint("TOPLEFT", card, "TOPRIGHT", -290, y)
        cb.t = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); cb.t:SetPoint("LEFT", cb, "RIGHT", 2, 0); cb.t:SetWidth(258); cb.t:SetJustifyH("LEFT"); cb.t:SetWordWrap(false)
        cb.t:SetText(text)
        cb:SetScript("OnClick", function(b) onClick(b:GetChecked() and true or false); refresh() end)
        cb:SetScript("OnEnter", function(b) GameTooltip:SetOwner(b, "ANCHOR_TOP"); GameTooltip:AddLine(text, 1, 0.82, 0); GameTooltip:AddLine(tip, 1, 1, 1, true); GameTooltip:Show() end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return cb
    end
    p.boardCb = switch(-26, ns.L("屏幕上显示 GI 循环助手（钉板）", "Show the GI rotation helper on screen"),
        ns.L("屏幕上一个小框：现在该按哪个技能、按哪个键、为什么；按完告诉你跟手法一不一致。拖动可移动；关掉会记住，登录不会自己冒出来。",
            "A small frame: what to press now, which key and why; tells you if you matched. Drag to move; stays off once turned off."),
        function(on) if ns.KeysRot then ns.KeysRot.Toggle(on) end; if not on and ns.KeysHud and ns.db.keysHud then ns.KeysHud.Toggle(false) end end)
    p.hudCb = switch(-52, ns.L("钉板下挂决策 HUD（训练模式）", "Decision HUD under the helper (training)"),
        ns.L("挂在钉板下面的分轨面板：资源 / 连击点、目标身上你的持续伤害剩余、技能冷却、触发技亮没亮。开它会顺带打开钉板。",
            "A panel under the helper: resource / combo points, your DoTs on the target, cooldowns and procs. Turns the helper on too."),
        function(on) if ns.KeysHud then ns.KeysHud.Toggle(on) end end)
    -- 段标题（金线）
    p.srcHd = ruled(vt, lbl(vt, "GameFontNormal", 10, -122, 600))
    p.rotHd = ruled(vt, lbl(vt, "GameFontNormal", 10, -260, 600))
    p.rotEmpty = lbl(vt, "GameFontDisableSmall", 14, -284, 560); p.rotEmpty:SetText(ns.L("这个职业的手法还没做（首批：战士 / 盗贼 / 术士）", "No rotation for this class yet (first: Warrior / Rogue / Warlock)")); p.rotEmpty:Hide()
    p.coachHd = ruled(vt, lbl(vt, "GameFontNormal", 10, -340, 600))
    p.coach = vt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); p.coach:SetPoint("TOPLEFT", 14, -362); p.coach:SetJustifyH("LEFT")
    if p.coach.SetSpacing then p.coach:SetSpacing(3) end
    -- 底部：公测众包施法记录（P5，默认关）+ 能力探针
    local cc = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    cc:SetSize(22, 22); cc:SetPoint("BOTTOMLEFT", 10, 12)
    cc.t = cc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); cc.t:SetPoint("LEFT", cc, "RIGHT", 2, 0); cc.t:SetWidth(330); cc.t:SetJustifyH("LEFT")
    cc.t:SetText(ns.L("贡献我的施法频率（匿名，用来做「顶尖手法 · 公测版」）", "Share my cast frequency (anonymous, builds the beta rotation)"))
    cc:SetScript("OnShow", function(self) self:SetChecked(ns.KeysCast and ns.KeysCast.On() or false) end)
    cc:SetScript("OnClick", function(self) if ns.KeysCast then ns.KeysCast.Set(self:GetChecked() and true or false) end end)
    cc:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.L("贡献施法频率", "Share cast frequency"), 1, 0.82, 0)
        GameTooltip:AddLine(ns.L("战斗中记每个技能按了几次、按完哪个接哪个，用来生成「GI 顶尖手法 · 公测版」。只记技能和次数，不记角色名、服务器、目标；随 /gif data 导出、由你自己上传。",
            "Records how often you press each spell in combat and what follows what, to build the beta rotation. Spells and counts only - no names, realm or targets; uploads with /gif data."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    cc:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.castCb = cc
    local pr = ns.Button(p, ns.L("能力探针", "Probe"), 90, 22, function() if ns.KeysProbe then ns.KeysProbe.Toggle() end end)
    pr:SetPoint("BOTTOMRIGHT", -12, 12)
    pr:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.L("能力探针", "Capability probe"), 1, 0.82, 0)
        GameTooltip:AddLine(ns.L("测这个客户端读不读得到资源 / 冷却 / 增益 / 法术等级（打木桩或野怪时开着），结果发给我们用来校正手法引擎。/gif probe keys 同。",
            "Checks what this client exposes (resources / cooldowns / buffs); send us the result to tune the engine. Same as /gif probe keys."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    pr:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- 「现在该按」0.2 秒刷新：挂在页面子框上，页面藏起来 OnUpdate 自然停
    local tk = CreateFrame("Frame", nil, p)
    local acc = 0
    tk:SetScript("OnUpdate", function(_, el)
        acc = acc + (el or 0)
        if acc < 0.2 then return end
        acc = 0
        pcall(tickNext)
    end)
end

-- 刷新：天赋 / 动作条 / 绑定变了（节流 0.3 秒）
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS", "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local queued
ev:SetScript("OnEvent", function()
    if queued or not page then return end
    queued = true
    C_Timer.After(0.3, function() queued = false; pcall(refresh) end)
end)

ns.RegisterPage({ key = "rot", order = 1.65, title = ns.L("手法", "Rotation"), tabTitle = ns.L("手法", "Rotation"),
    icon = "Interface\\Icons\\Ability_Warrior_BattleShout", build = build, refresh = refresh })
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.rot = function()   -- /gif rot：打开手法页
    local f = _G.GearInsightForeverMain
    if f and f:IsShown() then ns.ShowPage("rot") else ns.ToggleMain("rot") end
end
ns.ExtraSlash["手法"] = ns.ExtraSlash.rot
