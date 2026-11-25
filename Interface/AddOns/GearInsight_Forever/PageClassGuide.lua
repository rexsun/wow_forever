-- 「职业 → 攻略」页（11-15 用户「插件内职业内加一个攻略选项，弄一个文章LIST页面，点了可以进去看这个」）
--   列表：顶上一排 9 个职业（默认自己的）→「XX 专属」在前、「通用攻略」在后；每条 = 标题 + 一行摘要，整条可点。
--   阅读：返回按钮 + 标题 + 正文（小标题 / 段落 / 列表 / 提示框，滚动，长文不截断）；
--     末尾有视频版链接的篇出「视频版（抖音）：」+ 只读输入框（点一下全选，Ctrl+C 复制；游戏里点不开网址）。
--   数据：ClassGuideData.lua（ns.ClassGuides）+ ClassGuideLinks.lua（ns.ClassGuideLinks）← scripts/gi_forever_guides_build.py 从攻略稿生成。
--     ⛔ ClassGuideLinks.lua 不进网易DD 包（gi_forever_pack.DD_DROP）→ DD 版没有视频版那一行。
--   ⛔ 在 HOLD 里（GearInsight_Forever_Class/_hold.txt），游戏内验收完才进发行包。
--   ⛔ 别用 ①② / ■ / ✓ 这类字符：游戏字体没字形会显示成方框（生成脚本已替换）。
local _, ns = ...; ns = _G.GearInsightForever or ns
-- 11-15 发版前繁体扫描闸：攻略数据里的中文不走 ns.L → 繁体模式下显示前转繁（简体端原样）
local function TD(x) if type(x) == "string" and ns.TD then return ns.TD(x) end return x end

local GOLD = { 1, 0.82, 0 }
local CW = 616          -- 正文宽（滚动区 646 − 右侧留白）
local S = { cls = nil, open = nil }
local page

local function str(v) return type(v) == "string" and v or "" end
local function list(t) return type(t) == "table" and t or {} end
local function guides() return list(ns.ClassGuides and ns.ClassGuides.list) end
local function classCn(cls) return (ns.Data and ns.Data.classCn and ns.Data.classCn[cls]) or cls end
local function classColor(cls) return (ns.CLASS_COLOR and ns.CLASS_COLOR[cls]) or "ffffff" end
local function videoLink(id) local t = rawget(ns, "ClassGuideLinks"); return type(t) == "table" and str(t[id]) or "" end

-- 本职业的 + 通用的（各自保持数据里的顺序）
function ns.ClassGuideList(cls)
    local mine, common = {}, {}
    for _, g in ipairs(guides()) do
        if g.cls == nil then common[#common + 1] = g
        elseif g.cls == cls then mine[#mine + 1] = g end
    end
    return mine, common
end
local function byId(id)
    for _, g in ipairs(guides()) do if g.id == id then return g end end
    return nil
end

local function tip(fr, title, body, hint)
    fr:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(TD(title), GOLD[1], GOLD[2], GOLD[3], 1, true)
        if body and body ~= "" then GameTooltip:AddLine(TD(body), 0.9, 0.9, 0.9, true) end
        if hint then GameTooltip:AddLine(TD(hint), 0.5, 0.8, 1, true) end
        GameTooltip:Show()
    end)
    fr:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function build(p)
    page = p
    ns.ClassGuidePage = p   -- 测试用
    local sub = ns.L("无限服玩法攻略：本职业专属在前，通用攻略在后，点一篇直接在插件里看。", "WoW: Forever guides (Chinese only): class guides first, then general ones.")
    local y0 = ns.PageHeader(p, ns.L("攻略", "Guides"), sub)
    S.cls = S.cls or ns.MyClass()

    -- 第一排：职业（列表时显示）；阅读时同一位置换成「返回」+ 本篇所属
    p.classBtns = ns.ClassBar(p, y0, function(cls) S.cls = cls; S.open = nil; p.render() end)
    local back = ns.Button(p, ns.L("< 返回列表", "< Back"), 104, 22, function() S.open = nil; p.render() end)
    back:SetPoint("TOPLEFT", 8, y0 - 1)
    back:Hide()
    p.backBtn = back
    local where = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    where:SetPoint("LEFT", back, "RIGHT", 10, 0); where:SetPoint("RIGHT", p, "RIGHT", -12, 0)
    where:SetJustifyH("LEFT"); where:SetWordWrap(false); where:SetTextColor(0.65, 0.65, 0.65)
    p.whereFs = where

    local top = y0 - 30
    local sf = ns.Scroll(p, 4, top, 646, 474 + top - 6)
    p.sf = sf
    local c, y

    local function newChild()
        local old = c
        c = CreateFrame("Frame", nil, sf); c:SetSize(646, 10)
        sf:SetScrollChild(c)
        if old then old:Hide() end
        p.c = c
        p.fs, p.rows, p.linkBox = {}, {}, nil
        y = 4
        if sf.SetVerticalScroll then sf:SetVerticalScroll(0) end
    end
    local function text(parent, font, s, x, w, r, g, b, yy)
        local fs = parent:CreateFontString(nil, "OVERLAY", font)
        p.fs[#p.fs + 1] = fs
        fs:SetPoint("TOPLEFT", x, -(yy or y)); fs:SetWidth(w)
        fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP"); fs:SetWordWrap(true)
        if fs.SetSpacing then fs:SetSpacing(2) end
        fs:SetText(TD(s))
        if r then fs:SetTextColor(r, g, b) end
        return fs, math.max(12, math.ceil(tonumber(fs:GetStringHeight()) or 12))
    end
    -- 板块标题：淡金底 + 左侧金条 + 右侧篇数
    local function section(title, n)
        y = y + 6
        local hr = CreateFrame("Frame", nil, c)
        hr:SetPoint("TOPLEFT", 0, -y); hr:SetSize(CW + 10, 24)
        local bg = hr:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.14)
        local bar = hr:CreateTexture(nil, "BORDER"); bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.95)
        bar:SetPoint("TOPLEFT"); bar:SetPoint("BOTTOMLEFT"); bar:SetWidth(4)
        local t = hr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("LEFT", 12, 0); t:SetText(TD(title)); t:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        local r = hr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r:SetPoint("RIGHT", -10, 0); r:SetTextColor(0.75, 0.75, 0.75)
        r:SetText(string.format(ns.L("%d 篇", "%d"), n))
        p.fs[#p.fs + 1] = t
        y = y + 24 + 6
    end
    local function empty(s)
        local _, h = text(c, "GameFontDisable", s, 12, CW - 12)
        y = y + h + 8
    end
    -- 一条：第一行 [标签] 标题；第二行 摘要（一行，放不下截断，悬停看全）
    local function row(g)
        local r = CreateFrame("Button", nil, c)
        r:SetPoint("TOPLEFT", 0, -y); r:SetWidth(CW + 10)
        local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.04)
        local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.08)
        local tags = ""
        if g.cls then tags = tags .. "|cff" .. classColor(g.cls) .. "[" .. ns.L(classCn(g.cls), g.cls) .. "]|r " end
        if str(g.tag) ~= "" then
            local col = (g.tag == "联盟" and "4a9eff") or (g.tag == "部落" and "ff5a4a") or "c0c0c0"
            tags = tags .. "|cff" .. col .. "[" .. g.tag .. "]|r "
        end
        local t1 = text(r, "GameFontHighlight", tags .. str(g.title), 10, CW - 10, nil, nil, nil, 6)
        t1:SetWordWrap(false); t1:SetHeight(16)
        local t2 = text(r, "GameFontHighlightSmall", str(g.summary), 10, CW - 10, 0.62, 0.62, 0.62, 25)
        t2:SetWordWrap(false); t2:SetHeight(14)
        r:SetHeight(45)
        r.title, r.sub, r.g = t1, t2, g
        tip(r, str(g.title), str(g.summary), ns.L("点击：在插件里阅读全文", "Click to read"))
        r:SetScript("OnClick", function() S.open = g.id; p.render() end)
        p.rows[#p.rows + 1] = r
        y = y + 45 + 4
    end

    local function renderList()
        local cls = S.cls
        for _, b in ipairs(p.classBtns) do b:Show(); b.sel:SetShown(b.cls == cls) end
        back:Hide(); where:SetText("")
        local mine, common = ns.ClassGuideList(cls)
        section("|cff" .. classColor(cls) .. ns.L(classCn(cls), cls) .. "|r" .. ns.L(" 专属攻略", " guides"), #mine)
        if #mine == 0 then
            empty(ns.L("这个职业的专属攻略还在整理，先看下面的通用攻略。", "No class guides yet - see the general guides below."))
        end
        for _, g in ipairs(mine) do row(g) end
        section(ns.L("通用攻略（所有职业）", "General guides"), #common)
        if #common == 0 then empty(ns.L("还没有通用攻略。", "No general guides yet.")) end
        for _, g in ipairs(common) do row(g) end
    end

    local function renderArticle(g)
        for _, b in ipairs(p.classBtns) do b:Hide() end
        back:Show()
        local parts = {}
        parts[#parts + 1] = g.cls and ("|cff" .. classColor(g.cls) .. ns.L(classCn(g.cls), g.cls) .. "|r" .. ns.L("专属", "")) or ns.L("通用攻略", "General")
        if str(g.tag) ~= "" then parts[#parts + 1] = g.tag end
        if str(g.date) ~= "" then parts[#parts + 1] = g.date end
        where:SetText(TD(table.concat(parts, "  ·  ")))
        local _, ht = text(c, "GameFontNormalLarge", str(g.title), 6, CW - 6, GOLD[1], GOLD[2], GOLD[3])
        y = y + ht + 6
        if str(g.summary) ~= "" then
            local _, hs = text(c, "GameFontHighlightSmall", str(g.summary), 6, CW - 6, 0.65, 0.65, 0.65)
            y = y + hs + 8
        end
        local ln = c:CreateTexture(nil, "ARTWORK"); ln:SetColorTexture(0.3, 0.3, 0.3, 0.6)
        ln:SetPoint("TOPLEFT", 4, -y); ln:SetSize(CW, 1)
        y = y + 8
        for _, b in ipairs(list(g.body)) do
            local s = str(b.s)
            if b.t == "h" then
                y = y + 8
                local _, h = text(c, "GameFontNormal", s, 6, CW - 6, GOLD[1], GOLD[2], GOLD[3])
                y = y + h + 6
            elseif b.t == "li" then
                local dot = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                dot:SetPoint("TOPLEFT", 10, -y); dot:SetText("·"); dot:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
                p.fs[#p.fs + 1] = dot
                local _, h = text(c, "GameFontHighlight", s, 22, CW - 22)
                y = y + h + 5
            elseif b.t == "q" then
                -- 提示框：深底 + 左侧金条，文字内缩
                local box = CreateFrame("Frame", nil, c)
                box:SetPoint("TOPLEFT", 4, -y); box:SetWidth(CW - 4)
                local bg = box:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.08)
                local bar = box:CreateTexture(nil, "BORDER"); bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.8)
                bar:SetPoint("TOPLEFT"); bar:SetPoint("BOTTOMLEFT"); bar:SetWidth(3)
                local _, h = text(box, "GameFontHighlight", s, 14, CW - 30, 0.95, 0.92, 0.82, 7)
                box:SetHeight(h + 14)
                y = y + h + 14 + 8
            else
                local _, h = text(c, "GameFontHighlight", s, 6, CW - 6)
                y = y + h + 8
            end
        end
        -- 末尾：视频版链接（网址在游戏里点不开 → 只读输入框，点一下全选，Ctrl+C 复制）
        local url = videoLink(g.id)
        if url ~= "" then
            y = y + 10
            local ln2 = c:CreateTexture(nil, "ARTWORK"); ln2:SetColorTexture(0.3, 0.3, 0.3, 0.6)
            ln2:SetPoint("TOPLEFT", 4, -y); ln2:SetSize(CW, 1)
            y = y + 10
            local _, hl = text(c, "GameFontNormal", ns.L("视频版（抖音）：", "Video version (Douyin):"), 6, CW - 6)
            y = y + hl + 4
            local eb = CreateFrame("EditBox", nil, c, "InputBoxTemplate")
            eb:SetSize(340, 22); eb:SetPoint("TOPLEFT", 12, -y)
            eb:SetAutoFocus(false); eb:SetFontObject("GameFontHighlight")
            eb:SetText(url); eb:SetCursorPosition(0)
            eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
            eb:SetScript("OnMouseUp", function(self) self:SetFocus(); self:HighlightText() end)
            eb:SetScript("OnTextChanged", function(self, user) if user then self:SetText(url); self:HighlightText() end end)
            eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            local hint = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            hint:SetPoint("LEFT", eb, "RIGHT", 10, 0); hint:SetTextColor(0.6, 0.6, 0.6)
            hint:SetText(ns.L("点一下全选，Ctrl+C 复制", "Click to select, Ctrl+C to copy"))
            p.fs[#p.fs + 1] = hint
            p.linkBox = eb
            y = y + 22 + 8
        end
    end

    function p.render()
        newChild()
        local g = S.open and byId(S.open)
        if g then renderArticle(g) else S.open = nil; renderList() end
        c:SetHeight(y + 12)
    end
    p.render()
end

local function refresh(p)
    if p and p.render then p.render() end
end

-- 测试 / 别的页跳转用：打开某一篇（不在主窗口时先打开这页）
function ns.ClassGuideOpen(id)
    if not byId(id) then return false end
    S.open = id
    if ns.CurrentPage and ns.CurrentPage() == "cguide" and page and page.render then page.render()
    elseif ns.ToggleMain then ns.ToggleMain("cguide") end
    return true
end
function ns.ClassGuideState() return S end   -- 测试用

-- ⛔ 页名 / 顺序 / 图标要和 ClassStub.lua 里的占位页一模一样
ns.RegisterPage({ key = "cguide", order = 1.02, title = ns.L("攻略", "Guides"), tabTitle = ns.L("攻略", "Guides"),
    icon = "Interface\\Icons\\INV_Scroll_03", build = build, refresh = refresh })
