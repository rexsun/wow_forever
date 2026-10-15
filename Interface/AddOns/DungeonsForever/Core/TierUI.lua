-- =============================================================================
-- 无限副本手册 · 职业指南页（界面层）
-- 职业排行与专精指南的渲染层，数据来自 Data_ClassTier / Data_ClassGuide；只对无限服 / 正式服加载。
-- =============================================================================

local _, ns = ...

if not ns.LoadForeverPages then return end

local format = string.format
local L = ns.L

local Host = ns.ProfHost
if not Host then return end

local DG = Host.DG
local MakeFS = Host.MakeFS
local NewButton, MakeOutline = Host.NewButton, Host.MakeOutline
local SetOutline, Unpack = Host.SetOutline, Host.Unpack
local C_GOLD = Host.C_GOLD
local C_GREY, C_DIM, C_WHITE, C_TEXT = Host.C_GREY, Host.C_DIM, Host.C_WHITE, Host.C_TEXT
local PAGE_INSET, CONTENT_W = Host.PAGE_INSET, Host.CONTENT_W
local ROW_CLASS = Host.ROW_CLASS
local FALLBACK_ICON = Host.FALLBACK_ICON

local T = ns.ClassTier
if not T or type(T.pages) ~= "table" or #T.pages == 0 then return end

local TT = {}
ns.TierModule = TT

-- ★ 双大卡两列布局（2026-10-10 定案，模板=探索页 navCard/listCard）：左列（指南 /
--   专精指南）与右列（子页签 + hero + 板块页签 + 内容区）各包进一块 L1 大容器卡，
--   卡坐窗：左右底 = 窗沿 20；★ 顶 = CARD_TOP 8（二十八轮对齐全局标准：大卡顶 =
--   主窗页签轨道底 + 8，专业页 17:29 同款修正，原窗沿 20 比其他页低 12 UI）；
--   卡↔卡 8，卡内四周内衬 8（右列内容统一内收 INSET）。
TT.EDGE = PAGE_INSET
TT.CARD_TOP = 8
TT.NAV_X, TT.NAV_PAD = TT.EDGE, 8
TT.NAV_TOP = TT.CARD_TOP + 8
TT.NAV_W = ((type(GetLocale) == "function") and GetLocale() == "enUS") and 184 or 148
TT.NAV_ITEM_H, TT.NAV_ICON, TT.NAV_FS = 26, 20, 16
-- 左列条目步进 = 条目高 + 条目间距（用户定 4px 呼吸；进大卡后属卡内内衬，豁免 8）。
TT.NAV_ITEM_GAP = 4
TT.NAV_ITEM_STEP = TT.NAV_ITEM_H + TT.NAV_ITEM_GAP
-- 左列纵向节奏（y 自 NAV_TOP 下数）：分组标题 → 「职业排行」按钮 → 分组标题 → 9 职业条目。
TT.NAV_HEAD_Y  = TT.NAV_TOP + 2
TT.NAV_RANK_Y  = TT.NAV_TOP + 22
TT.NAV_GROUP_Y = TT.NAV_TOP + 58
TT.NAV_FIRST_Y = TT.NAV_TOP + 84
-- 左列两个分组标题（指南 / 专精指南）的字号：与条目文字同档 16（用户要求）。
TT.NAV_HEAD_FS = 16
-- 页签字号（右上子页签 + 板块页签）：与卡片正文同档 14（用户：页签文字太小）。
TT.TAB_FS = 14
TT.CLASS_ICON_DIR = "Interface\\AddOns\\DungeonsForever\\Media\\icon\\CLASS\\"
-- 内容列：大卡左缘 = X0，卡内衬 INSET 后才是内容缘（页签 / hero / 滚动区同一条线）。
TT.X0 = TT.NAV_X + TT.NAV_PAD + TT.NAV_W + TT.NAV_PAD + 8
TT.INSET = 8
TT.RIGHT_X = TT.X0 + TT.INSET
TT.RIGHT_W = CONTENT_W - TT.RIGHT_X - TT.EDGE - TT.INSET
TT.SUB_Y, TT.SUB_H, TT.SUB_W, TT.SUB_STEP = TT.CARD_TOP + TT.INSET, 22, 70, 78
TT.BODY_TOP = TT.SUB_Y + TT.SUB_H + 8
-- ★ 专精页顶卡（卡中卡）：spec 页签行 / hero / 板块页签行整体装进一张固定 L2 边框
--   内卡（与滚动区底板 specPlate 同材同色 ⇒ 大卡内上下两张内卡同调）；内件 8 内衬，
--   视口顶 = 顶卡底 + 8。rank 模式不建顶卡，仍走 SUB_Y/BODY_TOP 老栅格。
TT.SPEC_TAB_Y   = TT.SUB_Y + 8
TT.SPEC_HERO_TOP = TT.SPEC_TAB_Y + TT.SUB_H + 8
TT.LIST_PAD = 5
TT.CARD_W = TT.RIGHT_W

TT.GRID_COLS = 8
TT.GRID_ROWS = 1
TT.ICON = 28
TT.CELL_H = 40
TT.CELL_GAP = 8
TT.EMPTY_H = 26
TT.BADGE_W = 44
TT.CARD_GAP = 8

TT.OUTER_PAD = 0
TT.COL_GAP = 8
TT.FULL_W = TT.CARD_W
TT.COL_W = (TT.FULL_W - TT.COL_GAP) / 2
TT.CARD_PAD = 10
TT.HDR_H = 26
TT.SPEC_GAP = 8
TT.HERO_H = 56
TT.SPEC_ICON = 44
TT.INNER_W = TT.COL_W - 2 * TT.CARD_PAD
TT.INNER_FULL_W = TT.FULL_W - 2 * TT.CARD_PAD
TT.SPEC_TOP = TT.SPEC_HERO_TOP + TT.HERO_H

TT.SEC_TAB_H    = 24
TT.SEC_TAB_GAP  = 8
TT.SEC_TAB_STEP = 8
TT.SEC_TAB_PAD  = 24
TT.SEC_TAB_MAX  = 9
TT.SEC_TAB_Y    = TT.SPEC_TOP + TT.SEC_TAB_GAP
TT.SEC_DROP     = 16   -- 顶卡底衬 8 + 卡↔视口 8（两内卡之间卡↔卡 8）
TT.SEC_TOP      = TT.SEC_TAB_Y + TT.SEC_TAB_H + TT.SEC_DROP
TT.SEC_TEXT_W   = TT.FULL_W - 2 * TT.CARD_PAD
TT.SEC_ORDER = { "changes", "viability", "sw", "beginner", "systems", "rotation", "stats", "races", "prof" }

TT.CARD_RADIUS = 6
TT.PAIR_GAP = 12
TT.CHIP_H = 20
TT.CHIP_GAP = 5
TT.ROW_MAX = 120
TT.CARD_MAX = 14
TT.CHIP_MAX = 10
TT.SPAN_FULL = 2
TT.GOOD = { 0.37, 0.66, 0.37 }
TT.BAD = { 0.76, 0.39, 0.36 }
TT.HELP_ROW = 4
TT.HELP_HEAD = 6

TT.COLOR = {
    S = { 1.00, 0.50, 0.00 },
    A = { 0.64, 0.21, 0.93 },
    B = { 0.00, 0.44, 0.87 },
    C = { 0.12, 0.60, 0.00 },
    D = { 0.62, 0.62, 0.62 },
}
TT.BADGE_TEXT = { 0.08, 0.08, 0.08 }
TT.BADGE_R = 6

TT.PAGE_NAME = {
    dps = L["输出"],
    tank = L["坦克"],
    healer = L["治疗"],
}

local SPEC_INDEX = {}
for cls, list in pairs(T.specs or {}) do
    SPEC_INDEX[cls] = SPEC_INDEX[cls] or {}
    for _, sp in ipairs(list) do SPEC_INDEX[cls][sp.key] = sp end
end

local function DB()
    DungeonsForeverDB = DungeonsForeverDB or {}
    local s = DungeonsForeverDB.tier
    if not s then
        s = {}
        DungeonsForeverDB.tier = s
    end
    if not s.tab then s.tab = T.pages[1].key end
    if s.nav ~= "spec" then s.nav = "rank" end
    return s
end

local function PageFor(key)
    for _, p in ipairs(T.pages) do
        if p.key == key then return p end
    end
    return T.pages[1]
end

local function SpecRec(cls, key)
    local m = SPEC_INDEX[cls]
    return m and m[key]
end

local function ClassName(cls)
    local n = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]
    return n or cls
end

local function ClassColor(cls)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function SpecGrade(cls, spec)
    local pages = T.pages
    if type(pages) ~= "table" then return nil end
    for _, p in ipairs(pages) do
        for _, tr in ipairs(p.tiers or {}) do
            for _, e in ipairs(tr.specs or {}) do
                if e.class == cls and e.spec == spec then
                    return tr.key, p.key
                end
            end
        end
    end
    return nil
end

local FONT_BASE
local function Fnt(size)
    FONT_BASE = FONT_BASE or ns.FONT or "Fonts\\FRIZQT__.TTF"
    local flags = "OUTLINE"
    if ns.hui and ns.hui.FontFlags then flags = ns.hui.FontFlags("OUTLINE") end
    return FONT_BASE, size, flags
end

local function SetFont(fs, size)
    local a, b, c = Fnt(size)
    if a and fs.SetFont then fs:SetFont(a, b, c) end
end

local function SetIcon(tex, path)
    if type(path) == "string" and path ~= "" then
        tex:SetTexture(path)
    else
        tex:SetTexture(FALLBACK_ICON)
    end
end

-- 职业枚举名 → 自备材质图标文件名（WARRIOR → ClassIcon_Warrior）。
-- 文件名按「首字母大写 + 其余小写」生成，9 个职业都是单字词，不需要额外映射表。
local function ClassIconPath(cls)
    return TT.CLASS_ICON_DIR .. "ClassIcon_" .. cls:sub(1, 1) .. cls:sub(2):lower()
end

-- 圆角图标瓦片：图标纹理 + 圆角裁剪，返回 (独立帧, 纹理)。
-- ★ 单独套一层帧：2026-09-30 之前 ns.hui.RoundIcon 把蒙版挂在「父帧」上
--   （mask:SetAllPoints(父帧)），父帧比图标大就对不上角；现在蒙版改按**贴图**尺寸裁
--   （mask:SetAllPoints(tex)），这层帧已非必需，保留只为「帧尺寸 = 图标尺寸」同源好读。
-- ★ 蒙版走库里的 HUIRoundRectMask（ns.hui.RoundIcon 自带 __huiRounded 幂等记忆，
--   同一条纹理会重复调用也只挂一次蒙版）。本页所有「按钮内图标」都经这里。
local function MakeIconTile(parent, size)
    local fr = CreateFrame("Frame", nil, parent)
    fr:SetSize(size, size)
    local tex = fr:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(tex) end
    return fr, tex
end

local function FSHeight(fs)
    local h = fs.GetStringHeight and fs:GetStringHeight()
    return tonumber(h) or 16
end

local function TextChars(s)
    local n, i, len = 0, 1, #s
    while i <= len do
        local c = string.byte(s, i)
        local step = 1
        if c >= 240 then step = 4
        elseif c >= 224 then step = 3
        elseif c >= 192 then step = 2 end
        i = i + step
        n = n + 1
    end
    return n
end

local function MobileCls()
    local _, cls = UnitClass("player")
    return cls
end

local function PatchBadge(frame)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
end

local G
local function EnsureCG()
    if not G then
        local cg = ns.EnsureClassGuide and ns.EnsureClassGuide() or nil
        G = (cg and type(cg.specs) == "table") and cg or nil
    end
    return G
end

TT.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

TT.SEC_TITLE = {
    changes = L["改动速览"],
    viability = L["定位评估"],
    sw = L["优缺点"],
    beginner = L["新手上手"],
    systems = L["职业系统"],
    rotation = L["输出循环"],
    stats = L["属性优先级"],
    races = L["种族推荐"],
    prof = L["专业推荐"],
}

TT.RACE_SIDE = {
    alliance = L["联盟"],
    horde = L["部落"],
    both = L["新增"],
}
TT.RACE_ORDER = { "alliance", "horde", "both" }

local function SpellName(id)
    if not id then return nil end
    local nm
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        nm = info and info.name
    end
    if (type(nm) ~= "string" or nm == "") and type(GetSpellInfo) == "function" then
        nm = GetSpellInfo(id)
    end
    if type(nm) == "string" and nm ~= "" then return nm end
    return format(L["法术 #%d"], id)
end

local function Spellify(text)
    if type(text) ~= "string" or text == "" then return text or "" end
    if not string.find(text, "|s", 1, true) then return text end
    return string.gsub(text, "|s(%d+)|", function(id)
        local nm = SpellName(tonumber(id))
        return format("|cff71d5ff|Hspell:%s|h[%s]|h|r", id, nm)
    end)
end

local function Prep(text)
    if type(text) ~= "string" then return tostring(text or "") end
    local s = string.gsub(text, "|l|", "\n")
    return Spellify(s)
end

local function HyperTip(frame, link)
    if not link or not GameTooltip then return end
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
    if not ok or (GameTooltip.NumLines and (GameTooltip:NumLines() or 0) == 0) then
        GameTooltip:AddLine(link, 0.8, 0.8, 0.8, true)
    end
    GameTooltip:Show()
end

-- 排行 tier 卡：二十三轮重排后坐在排行大卡（L1 容器）上 ⇒ 内卡 L2 + 白 10% 细边
-- （SkinPopup 对 L 阶色原生支持）；非 hui 保留旧白 α 方形回落。
local function Cardify(frame, alpha)
    if ns.hui and ns.hui.SkinPopup then
        ns.hui.SkinPopup(frame, 6, nil, ns.hui.layer.L2)
    elseif frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        frame:SetBackdropColor(1, 1, 1, alpha or 0.03)
    end
end

-- 种族/标签芯片：坐在 L2 内容卡内 ⇒ 再嵌套件提亮到 L3（r6 与页签同参）。
local function SkinChip(frame)
    if ns.hui and ns.hui.SkinPopup then
        ns.hui.SkinPopup(frame, 6, nil, ns.hui.layer.L3)
    elseif frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        frame:SetBackdropColor(1, 1, 1, 0.06)
    end
end

-- 左列职业按钮的选中/悬停底：hui 走胶囊贴片（L2 常亮底 + L4 悬停），
-- fallback 走旧白 α 方形贴片（cb.bg）。两路共用下面的开关。
local function SetClassBase(cb, on)
    if cb.__base then
        for _, t in ipairs(cb.__base) do t:SetShown(on) end
    elseif cb.bg then
        cb.bg:SetShown(on)
    end
end

local function SetClassHover(cb, on)
    if cb.__hovc then
        for _, t in ipairs(cb.__hovc) do t:SetShown(on) end
    end
end

-- 格子双态（hui）：own 常亮 = L3 胶囊、hover = L4 胶囊（hover 优先、盖过 own，
-- OnLeave 只撤 hover 片）；fallback 保留旧白 α 单纹理两态共用。
local function PaintCell(cell, own, hover)
    if cell.__own or cell.__hov then
        local hv = hover == true
        if cell.__hov then
            for _, t in ipairs(cell.__hov) do t:SetShown(hv) end
        end
        if cell.__own then
            for _, t in ipairs(cell.__own) do t:SetShown(own == true and not hv) end
        end
    elseif cell.bg then
        cell.bg:SetShown(own == true or hover == true)
    end
end

local function CellTip(cell)
    local rec, cls = cell.rec, cell.cls
    if not rec then return end
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local tc = TT.COLOR[cell.tierKey] or TT.COLOR.D
    GameTooltip:AddLine(format(L["%s 档"], cell.tierKey), tc[1], tc[2], tc[3])
    local cr, cg, cb = ClassColor(cls)
    GameTooltip:AddLine(ClassName(cls) .. " · " .. rec.name, cr, cg, cb)
    if rec.nameEn and rec.nameEn ~= "" then
        GameTooltip:AddLine(rec.nameEn, 0.6, 0.6, 0.6)
    end
    if cls == cell.own then
        GameTooltip:AddLine(L["你的职业"], 0.47, 0.75, 0.45)
    end
    GameTooltip:Show()
end

local function BuildNav(page)
    TT.nav = {}
    local label = MakeFS(page, TT.NAV_HEAD_FS, C_GREY, "LEFT")
    label:SetPoint("TOPLEFT", page, "TOPLEFT", TT.NAV_X + TT.NAV_PAD + 2, -TT.NAV_HEAD_Y)
    label:SetText(L["指南"])
    TT.navLabel = label

    -- 「职业排行」：与子页签同款按钮皮 + 书本图标（圆角裁剪）。
    local bt = NewButton(page, L["职业排行"], TT.NAV_W, TT.NAV_ITEM_H, TT.NAV_FS)
    bt:SetPoint("TOPLEFT", page, "TOPLEFT", TT.NAV_X + TT.NAV_PAD, -TT.NAV_RANK_Y)
    MakeOutline(bt, 1, 0.82, 0)
    SetOutline(bt, true, 1, 0.82, 0)
    bt.__huiKeepTextColor = true
    bt.__name = L["职业排行"]
    local fs = bt:GetFontString()
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", bt, "LEFT", 5 + TT.NAV_ICON + 5, 0)
    fs:SetJustifyH("LEFT")
    local btile, bicon = MakeIconTile(bt, TT.NAV_ICON)
    btile:SetPoint("LEFT", bt, "LEFT", 5, 0)
    SetIcon(bicon, "Interface\\Icons\\inv_misc_book_11")
    bt.__tile = btile
    bt.__icon = bicon
    bt:SetScript("OnClick", function()
        DB().nav = "rank"
        TT.Render()
        ns.PlaySound(1)
    end)
    TT.navBtn = bt

    G = EnsureCG()
    if not G then return end
    local glabel = MakeFS(page, TT.NAV_HEAD_FS, C_GREY, "LEFT")
    glabel:SetPoint("TOPLEFT", page, "TOPLEFT", TT.NAV_X + TT.NAV_PAD + 2, -TT.NAV_GROUP_Y)
    glabel:SetText(L["专精指南"])
    TT.navGroup = glabel

    TT.classBtns = {}
    local y = TT.NAV_FIRST_Y
    for _, cls in ipairs(TT.CLASS_ORDER) do
        if G.specs[cls] then
            -- 与「职业排行」同构：同一套按钮皮（SkinButton 的 1px 圆角描边 + 悬停强调边），
            -- 选中再由金色描边 + 白字表达。
            local cb = NewButton(page, ClassName(cls), TT.NAV_W, TT.NAV_ITEM_H, TT.NAV_FS)
            -- 按钮皮自带白 α 高亮只在 fallback 分支挂：hui 走 L4 悬停胶囊，避免双效叠加。
            if not (ns.hui and ns.hui.BuildCapsule) then
                cb:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
                local hl = cb:GetHighlightTexture()
                if hl then hl:SetAlpha(0.08) end
            end
            MakeOutline(cb, 1, 0.82, 0)
            SetOutline(cb, false, 1, 0.82, 0)
            cb.__huiKeepTextColor = true
            local cfs = cb:GetFontString()
            cfs:ClearAllPoints()
            cfs:SetPoint("LEFT", cb, "LEFT", 5 + TT.NAV_ICON + 5, 0)
            cfs:SetJustifyH("LEFT")
            -- 选中/悬停底：外层大卡 L1 ⇒ 按钮内件 L2 常亮底，悬停胶囊再 +2 档到 L4
            -- （BACKGROUND 子层 +2：盖过按钮皮 backdrop、又不压文字）。
            if ns.hui and ns.hui.BuildCapsule then
                cb.__base = ns.hui.BuildCapsule(cb, 8, ns.hui.layer.L2, 1, 2)
                cb.__hovc = ns.hui.BuildCapsule(cb, 8, ns.hui.layer.L4, 1, 2)
                for _, t in ipairs(cb.__base) do t:Hide() end
                for _, t in ipairs(cb.__hovc) do t:Hide() end
            else
                cb.bg = cb:CreateTexture(nil, "BACKGROUND", nil, 2)
                cb.bg:SetAllPoints()
                cb.bg:SetColorTexture(1, 1, 1, 0.04)
                cb.bg:Hide()
            end
            local tile, ic = MakeIconTile(cb, TT.NAV_ICON)
            tile:SetPoint("LEFT", cb, "LEFT", 5, 0)
            SetIcon(ic, ClassIconPath(cls))
            cb:SetScript("OnClick", function()
                TT.OpenSpec(cls)
            end)
            cb:SetScript("OnEnter", function(self)
                SetClassHover(self, true)
                if not self.__hovc and self.bg then self.bg:Show() end
            end)
            cb:SetScript("OnLeave", function(self)
                SetClassHover(self, false)
                if not self.__hovc and self.bg then self.bg:Hide() end
            end)
            cb.__cls = cls
            cb.__txt = cfs
            cb.__icon = ic
            cb.__tile = tile
            TT.classBtns[cls] = cb
            cb:SetPoint("TOPLEFT", page, "TOPLEFT", TT.NAV_X + TT.NAV_PAD, -y)
            y = y + TT.NAV_ITEM_STEP
        end
    end
end

local function BuildSubTabs(page)
    TT.subBtns = {}
    local x = 0
    for _, p in ipairs(T.pages) do
        local bt = NewButton(page, TT.PAGE_NAME[p.key] or p.key, TT.SUB_W, TT.SUB_H, TT.TAB_FS)
        MakeOutline(bt, 1, 0.82, 0)
        bt.__huiKeepTextColor = true
        bt:SetPoint("TOPLEFT", page, "TOPLEFT", TT.RIGHT_X + x, -TT.SUB_Y)
        bt:SetScript("OnClick", function()
            DB().tab = p.key
            DB().nav = "rank"
            TT.Render()
            ns.PlaySound(1)
        end)
        TT.subBtns[p.key] = bt
        x = x + TT.SUB_STEP
    end

    G = EnsureCG()
    if not G then return end
    TT.specTabs = {}
    for i = 1, 3 do
        local bt = NewButton(page, "", TT.SUB_W, TT.SUB_H, TT.TAB_FS)
        MakeOutline(bt, 1, 0.82, 0)
        bt.__huiKeepTextColor = true
        bt:SetPoint("TOPLEFT", page, "TOPLEFT", TT.RIGHT_X + 8 + (i - 1) * TT.SUB_STEP, -TT.SPEC_TAB_Y)
        bt:Hide()
        bt:SetScript("OnClick", function()
            local db = DB()
            if bt.__specKey then
                db.spec = bt.__specKey
                TT.Render()
                ns.PlaySound(1)
            end
        end)
        TT.specTabs[i] = bt
        x = x + TT.SUB_STEP
    end
end

local RenderSpec

local function BuildSecTabs(page)
    G = EnsureCG()
    if not G then return end
    TT.secTabs = {}
    for i = 1, TT.SEC_TAB_MAX do
        local bt = NewButton(page, "", 60, TT.SEC_TAB_H, TT.TAB_FS)
        MakeOutline(bt, 1, 0.82, 0)
        bt.__huiKeepTextColor = true
        bt:SetPoint("TOPLEFT", page, "TOPLEFT", TT.RIGHT_X + 8, -TT.SEC_TAB_Y)
        bt:SetScript("OnClick", function(self)
            if self.__secKey then
                DB().sec = self.__secKey
                RenderSpec()
                ns.PlaySound(1)
            end
        end)
        bt:Hide()
        TT.secTabs[i] = bt
    end
end

local function BuildCards(parent)
    TT.cards = {}
    local maxSpecs = 0
    for _, p in ipairs(T.pages) do
        for _, t in ipairs(p.tiers or {}) do
            local n = #(t.specs or {})
            if n > maxSpecs then maxSpecs = n end
        end
    end
    TT.GRID_ROWS = math.max(1, math.ceil(maxSpecs / TT.GRID_COLS))
    local gridW = TT.CARD_W - 2 * TT.LIST_PAD - TT.BADGE_W - 16
    local cellW = gridW / TT.GRID_COLS
    for i = 1, 5 do
        local card = CreateFrame("Frame", nil, parent)
        card:SetWidth(TT.CARD_W)
        Cardify(card, 0.03)
        local badge = CreateFrame("Frame", nil, card, "BackdropTemplate")
        badge:SetSize(TT.BADGE_W, TT.EMPTY_H)
        local badgeColor = { 1, 1, 1, 1 }
        local badgeRepaint
        if ns.hui and ns.hui.SkinPopup and ns.huiTheme == "hui" then
            ns.hui.SkinPopup(badge, 6, nil, badgeColor)
            local reps = badge.__huiRepaints
            if reps and #reps > 0 then
                badgeRepaint = function()
                    for _, fn in ipairs(reps) do pcall(fn) end
                end
            end
        else
            PatchBadge(badge)
        end
        local letter = MakeFS(badge, 16, TT.BADGE_TEXT, "CENTER")
        letter:SetAllPoints()
        local empty = MakeFS(card, 14, C_GREY, "LEFT")
        empty:SetText(L["本档为空"])
        local cells = {}
        for c = 1, TT.GRID_COLS * TT.GRID_ROWS do
            local cell = CreateFrame("Button", nil, card)
            cell:SetSize(cellW, TT.CELL_H)
            -- 格子底（hui 双态）：坐 L2 tier 卡内 ⇒ own 常亮提亮 L3、悬停再 +2 档到 L4
            -- （BACKGROUND 子层 2：盖卡底、不压图标/文字）；fallback 保留旧白 α 贴片。
            if ns.hui and ns.hui.BuildCapsule then
                cell.__own = ns.hui.BuildCapsule(cell, 4, ns.hui.layer.L3, 0, 2)
                cell.__hov = ns.hui.BuildCapsule(cell, 4, ns.hui.layer.L4, 0, 2)
                for _, t in ipairs(cell.__own) do t:Hide() end
                for _, t in ipairs(cell.__hov) do t:Hide() end
            else
                cell.bg = cell:CreateTexture(nil, "BACKGROUND")
                cell.bg:SetAllPoints()
                cell.bg:SetColorTexture(1, 1, 1, 0.05)
                cell.bg:Hide()
            end
            local ic = CreateFrame("Frame", nil, cell)
            ic:SetSize(TT.ICON, TT.ICON)
            ic:SetPoint("TOP", cell, "TOP", 0, 0)
            cell.icon = ic:CreateTexture(nil, "ARTWORK")
            cell.icon:SetAllPoints()
            cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(cell.icon) end
            cell.name = MakeFS(cell, 14, C_TEXT, "CENTER")
            cell.name:SetPoint("TOP", ic, "BOTTOM", 0, 0)
            cell.name:SetWordWrap(false)
            cell:RegisterForClicks("LeftButtonUp")
            cell:SetScript("OnEnter", function(self)
                PaintCell(self, self.own, true)
                CellTip(self)
            end)
            cell:SetScript("OnLeave", function(self)
                PaintCell(self, self.own, false)
                GameTooltip:Hide()
            end)
            cell:SetScript("OnClick", function(self)
                local cg = EnsureCG()
                if self.cls and self.spec and cg and cg.specs[self.cls] and cg.specs[self.cls][self.spec] then
                    TT.OpenSpec(self.cls, self.spec)
                end
            end)
            cells[c] = cell
        end
        TT.cards[i] = { frame = card, badge = badge, letter = letter, empty = empty, cells = cells, cellW = cellW, badgeColor = badgeColor, badgeRepaint = badgeRepaint }
    end
end

local function BuildNotes(parent)
    TT.factorTitle = MakeFS(parent, 14, C_WHITE, "LEFT")
    TT.factorTitle:SetText(L["排名依据"])
    TT.factorRows = {}
    for i = 1, 6 do
        local row = MakeFS(parent, 14, C_DIM, "LEFT")
        TT.factorRows[i] = row
    end
    TT.noteRows = {}
    for i = 1, 10 do
        local row = MakeFS(parent, 14, C_DIM, "LEFT")
        TT.noteRows[i] = row
    end
end

local function BuildSpecHero(page)
    G = EnsureCG()
    if not G then return end
    -- ★ 顶卡（卡中卡，2026-10-10 用户定案）：spec 页签行 + hero + 板块页签行整体装进
    --   一张固定 L2 边框内卡（与 specPlate 同材同色 ⇒ 大卡内上下两张内卡）；不随滚动
    --   （滚动只作用于下方内容），纯卡中卡外观（上缘剔除已严格化，遮罩职责退役）。
    local topCard = CreateFrame("Frame", nil, page, "BackdropTemplate")
    if ns.hui and ns.hui.SkinPopup then
        ns.hui.SkinPopup(topCard, 6, nil, ns.hui.layer.L2)
    else
        topCard:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        topCard:SetBackdropColor(0.086, 0.102, 0.133, 1)
        topCard:SetBackdropBorderColor(1, 1, 1, 0.1)
    end
    topCard:SetPoint("TOPLEFT", page, "TOPLEFT", TT.RIGHT_X, -(TT.CARD_TOP + 8))
    topCard:SetPoint("BOTTOMRIGHT", page, "TOPRIGHT",
                     -(TT.EDGE + TT.INSET), -(TT.SEC_TOP - 8))
    topCard:Hide()
    TT.specTopCard = topCard

    local hero = CreateFrame("Frame", nil, page)
    hero:SetPoint("TOPLEFT", page, "TOPLEFT", TT.RIGHT_X + 8, -TT.SPEC_HERO_TOP)
    hero:SetSize(TT.RIGHT_W - 16, TT.HERO_H)
    hero:Hide()
    TT.hero = hero

    local iconFrame = CreateFrame("Frame", nil, hero)
    iconFrame:SetSize(TT.SPEC_ICON, TT.SPEC_ICON)
    iconFrame:SetPoint("TOPLEFT", hero, "TOPLEFT", 0, -(TT.HERO_H - TT.SPEC_ICON) / 2)
    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(icon) end
    TT.heroIcon = icon

    local tx = TT.SPEC_ICON + 10
    local title = MakeFS(hero, 16, C_WHITE, "LEFT")
    title:SetPoint("TOPLEFT", hero, "TOPLEFT", tx, -8)
    TT.specTitle = title

    -- 元信息行挂页面最右、与右上子页签（输出 / 坦克 / 治疗，专精模式下为专精名）同一行
    -- 高度（2026-09-30 用户：不再压在标题下面）。挂在 page 上而非 hero（hero 顶在
    -- BODY_TOP，够不着页签行），显隐由 RenderSpec / HideSpec 接管。
    -- ★ 相对点必须是 TOPRIGHT（右上角）：写 "RIGHT" 会相对 page 右边条的垂直中点，
    --   整行掉到页面中部（2026-09-30 实机实锤）。自身锚点 "RIGHT" = 取文字垂直居中，
    --   对齐页签行中心，与字号无关。
    local meta = MakeFS(page, 14, C_GREY, "LEFT")
    meta:SetPoint("RIGHT", page, "TOPRIGHT", -(TT.EDGE + TT.INSET + 8), -(TT.SPEC_TAB_Y + TT.SUB_H / 2))
    TT.specMeta = meta

    local grade = MakeFS(hero, 14, C_GREY, "RIGHT")
    grade:SetPoint("TOPRIGHT", hero, "TOPRIGHT", 0, -12)
    TT.heroGrade = grade
    -- 底部职业色横线已按定案删除（强调条类）；hero 与下方板块页签由 SEC_TAB_GAP=8 分隔。
end

local function BuildSpecPool(parent)
    G = EnsureCG()
    if not G then return end
    local child = TT.child

    TT.scCards = {}
    for i = 1, TT.CARD_MAX do
        local fr = CreateFrame("Frame", nil, child)
        fr:SetWidth(TT.FULL_W)
        fr:Hide()
        -- ★ 专精内容卡不带背景（2026-10-10 用户定案：卡固定、内容滚动）：实底背景由
        --   page 上固定的 specPlate 承担（视口矩形），滚动 child 里只留承载布局的
        --   无背景帧 —— 无裁剪引擎上「卡固定、内容滚动」的唯一正解，卡体不再滚出视口。
        local title = MakeFS(fr, 14, C_WHITE, "LEFT")
        title:SetPoint("TOPLEFT", fr, "TOPLEFT", TT.CARD_PAD, -TT.CARD_PAD)
        local divider = fr:CreateTexture(nil, "ARTWORK")
        divider:SetWidth(1)
        divider:SetColorTexture(1, 1, 1, 0.1)
        divider:Hide()
        TT.scCards[i] = { frame = fr, title = title, divider = divider, n = 0, H = 0 }
    end

    TT.rowPool = {}
    for i = 1, TT.ROW_MAX do
        local fs = MakeFS(TT.rowHost, 14, C_TEXT, "LEFT")
        fs:SetWordWrap(true)
        fs:Hide()
        if fs.EnableHyperlinks then
            fs:EnableHyperlinks()
        elseif fs.SetHyperlinksEnabled then
            fs:SetHyperlinksEnabled(true)
        end
        TT.rowPool[i] = fs
    end

    TT.chipPool = {}
    for i = 1, TT.CHIP_MAX do
        local cf = CreateFrame("Frame", nil, child)
        cf:SetHeight(TT.CHIP_H)
        cf:Hide()
        SkinChip(cf)
        local cfs = MakeFS(cf, 14, C_TEXT, "CENTER")
        cfs:SetPoint("CENTER", cf, "CENTER", 0, 0)
        TT.chipPool[i] = { frame = cf, fs = cfs }
    end

    -- ★ 行文字宿主层级收口：scCards 是后建的实底卡帧、层级天然高于 rowHost，
    --   不显式抬高 = 行文字仍被盖（Titan 客户端同层顺序还随机，纪律上必须显式）。
    local topLvl = 0
    for i = 1, TT.CARD_MAX do
        local lv = TT.scCards[i] and TT.scCards[i].frame:GetFrameLevel() or 0
        if lv > topLvl then topLvl = lv end
    end
    TT.rowHost:SetFrameLevel(topLvl + 1)

    local fr = child
    fr:EnableMouse(true)
    if fr.SetHyperlinksEnabled then
        fr:SetHyperlinksEnabled(true)
    end
    fr:SetScript("OnHyperlinkEnter", HyperTip)
    fr:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
    fr:SetScript("OnMouseWheel", function(_, delta)
        -- ★ child 盖在视口上会先吃到滚轮事件：与 scroll 上的脚本同走自管滚动
        --   （旧 DG.WheelScroll 走 SetVerticalScroll，本引擎已证实不可信）。
        TierWheel(delta)
    end)
end

local function TakeSpecCard()
    TT.__cards = (TT.__cards or 0) + 1
    return TT.scCards[TT.__cards]
end

local function Elide()
    local card = TT.__cur
    if not card or not card.lastFS or card.elided then return end
    card.elided = true
    local fs = card.lastFS
    local txt = fs.GetText and fs:GetText()
    if type(txt) ~= "string" then txt = "" end
    if string.sub(txt, -3) ~= "…" then
        fs:SetText(txt .. "…")
    end
    local nh = FSHeight(fs)
    local d = nh - (card.lastH or 0)
    if d > 0.01 then
        card.elideDelta = (card.elideDelta or 0) + d
    end
    card.lastH = nh
end

local function TakeRowFS()
    TT.__rows = (TT.__rows or 0) + 1
    local fs = TT.rowPool[TT.__rows]
    if not fs then
        TT.__overflow = (TT.__overflow or 0) + 1
        Elide()
        return nil
    end
    return fs
end

local function TakeSpecChip()
    TT.__chips = (TT.__chips or 0) + 1
    return TT.chipPool[TT.__chips]
end

local function PutRow(text, size, color, x, y, w)
    local card = TT.__cur
    local fs = TakeRowFS()
    if not fs then return nil end
    card.n = card.n + 1
    SetFont(fs, size)
    fs:SetWidth(w)
    fs:SetText(Prep(text))
    fs:SetTextColor(color[1], color[2], color[3])
    fs:Show()
    local h = FSHeight(fs)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", card.frame, "TOPLEFT", x, y)
    -- ★ 自算剔除登记（十一轮+：引擎布局读数不可信）：__cy = child 坐标顶（距 child 顶
    --   向下），__ch = 行高。卡顶 = child 顶（scCard 锚 child (0,0)），故 child-y = -y。
    fs.__cy, fs.__ch = -y, h
    fs.__cgen = TT.__renderGen
    card.lastFS = fs
    card.lastH = h
    return h
end

local function AddRow(text, size, color, indent, gap, w)
    local w2 = w or (TT.__innerW - (indent or 0))
    local h = PutRow(text, size, color, TT.CARD_PAD + (indent or 0), TT.__cy, w2)
    if not h then return false end
    TT.__cy = TT.__cy - h - (gap or TT.HELP_ROW)
    return true
end

local function AddPair(goods, bads, innerW)
    local card = TT.__cur
    local gap = TT.PAIR_GAP
    local colW = math.floor((innerW - (gap * 2 + 1)) / 2)
    local leftX = TT.CARD_PAD
    local lineX = TT.CARD_PAD + colW + gap
    local rightX = lineX + 1 + gap
    local startY = TT.__cy
    local ly, ry = startY, startY
    for _, item in ipairs(goods) do
        local h = PutRow(item, 14, TT.GOOD, leftX, ly, colW)
        if not h then break end
        ly = ly - h - TT.HELP_ROW
    end
    for _, item in ipairs(bads) do
        local h = PutRow(item, 14, TT.BAD, rightX, ry, colW)
        if not h then break end
        ry = ry - h - TT.HELP_ROW
    end
    local bot = math.max(ly, ry)
    card.pairLineX = lineX
    card.pairBot = bot
    card.divider:ClearAllPoints()
    card.divider:SetPoint("TOPLEFT", card.frame, "TOPLEFT", lineX, startY - 1)
    card.divider:SetPoint("BOTTOMLEFT", card.frame, "TOPLEFT", lineX, bot + 5)
    card.divider:Show()
    -- ★ 自算剔除登记：divider 跨 [bot+5, startY-1]（card 坐标负值 → child 取负）。
    card.divider.__cy = -(bot + 5)
    card.divider.__ch = (bot - startY) + 6
    card.divider.__cgen = TT.__renderGen
    TT.__cy = bot - TT.SPEC_GAP
end

local function AddRaces(items, innerW)
    local card = TT.__cur
    local groups = {}
    local seen = {}
    local order = {}
    for _, r in ipairs(items) do
        local name = r.race or r.name or ""
        local side = r.side or "both"
        if not groups[side] then
            groups[side] = {}
            seen[side] = true
            order[#order + 1] = side
        end
        groups[side][#groups[side] + 1] = { name = name, mark = r.mark }
    end
    local seq = {}
    for _, s in ipairs(TT.RACE_ORDER) do
        if groups[s] then seq[#seq + 1] = s end
    end
    for _, s in ipairs(order) do
        if not (s == "alliance" or s == "horde" or s == "both") then seq[#seq + 1] = s end
    end
    for _, side in ipairs(seq) do
        local label = TT.RACE_SIDE[side] or side
        local rowY = TT.__cy
        local lfs = TakeRowFS()
        if not lfs then break end
        card.n = card.n + 1
        SetFont(lfs, 14)
        lfs:SetWidth(innerW)
        lfs:SetText(label)
        lfs:SetTextColor(C_DIM[1], C_DIM[2], C_DIM[3])
        local lw = tonumber(lfs:GetStringWidth()) or 30
        lfs:ClearAllPoints()
        lfs:SetPoint("TOPLEFT", card.frame, "TOPLEFT", TT.CARD_PAD, rowY)
        lfs:Show()
        card.lastFS = lfs
        card.lastH = FSHeight(lfs)
        -- ★ 自算剔除登记（同 PutRow）。
        lfs.__cy, lfs.__ch = -rowY, card.lastH
        lfs.__cgen = TT.__renderGen
        local cx = TT.CARD_PAD + lw + TT.CHIP_GAP
        local cy2 = rowY
        for _, item in ipairs(groups[side]) do
            local chip = TakeSpecChip()
            if not chip then break end
            local text = ((item.mark == "star") and "★" or "") .. item.name
            local cfs = chip.fs
            cfs:SetText(text)
            chip.frame:Show()
            local tw = tonumber(cfs:GetStringWidth()) or 30
            local cw = math.max(24, tw + 12)
            if cx + cw > TT.CARD_PAD + innerW then
                cx = TT.CARD_PAD
                cy2 = cy2 - TT.CHIP_H - TT.HELP_ROW
            end
            chip.frame:SetWidth(cw)
            chip.frame:ClearAllPoints()
            chip.frame:SetPoint("TOPLEFT", card.frame, "TOPLEFT", cx, cy2)
            -- ★ 自算剔除登记（同 PutRow）。
            chip.frame.__cy, chip.frame.__ch = -cy2, TT.CHIP_H
            chip.frame.__cgen = TT.__renderGen
            cx = cx + cw + TT.CHIP_GAP
        end
        TT.__cy = cy2 - TT.CHIP_H - TT.HELP_HEAD
    end
end

local function SectionSpan(sec)
    local hasGood, hasBad = false, false
    for _, e in ipairs(sec.flow or {}) do
        if e.t == "good" and e.v and #e.v > 0 then hasGood = true end
        if e.t == "bad" and e.v and #e.v > 0 then hasBad = true end
    end
    if hasGood and hasBad then return TT.SPAN_FULL end
    for _, e in ipairs(sec.flow or {}) do
        if e.t == "tb" or e.t == "races" then return TT.SPAN_FULL end
    end
    return 1
end

local function SectionHas(sec)
    for _, e in ipairs(sec.flow or {}) do
        local t = e.t
        if t == "p" or t == "h4" then
            if type(e.v) == "string" and e.v ~= "" then return true end
        elseif e.v and #e.v > 0 then
            return true
        end
    end
    return false
end

local function SpecSectionKeys(data)
    local have = {}
    for _, sec in ipairs(data.sections or {}) do
        local k = sec.key
        if k and TT.SEC_TITLE[k] and SectionHas(sec) then have[k] = true end
    end
    local keys = {}
    for _, k in ipairs(TT.SEC_ORDER) do
        if have[k] then keys[#keys + 1] = k end
    end
    return keys
end

local function SecTabWidth(bt, text)
    bt:SetWidth(TT.RIGHT_W)
    bt:SetText(text)
    local fs = bt.GetFontString and bt:GetFontString()
    local n
    if fs and fs.GetStringWidth then n = tonumber(fs:GetStringWidth()) end
    if not n or n <= 0 then n = TextChars(text) * TT.TAB_FS end
    return n
end

local function PaintSecTabs(data)
    local db = DB()
    local keys = SpecSectionKeys(data)
    local tabs = TT.secTabs
    if not tabs then return keys end
    local n = #keys
    if n > 0 then
        local found = false
        for _, k in ipairs(keys) do
            if k == db.sec then found = true break end
        end
        if not found then db.sec = keys[1] end
    end
    local sel = n > 0 and db.sec or nil
    local maxW = n > 0 and math.floor((TT.RIGHT_W - (n - 1) * TT.SEC_TAB_STEP) / n) or 48
    local x = 0
    for i = 1, TT.SEC_TAB_MAX do
        local bt = tabs[i]
        if bt and i <= n then
            local key = keys[i]
            local w = SecTabWidth(bt, TT.SEC_TITLE[key] or key)
            w = math.max(48, math.min(w + TT.SEC_TAB_PAD, maxW))
            bt:SetWidth(w)
            bt:ClearAllPoints()
            bt:SetPoint("TOPLEFT", TT.page, "TOPLEFT", TT.RIGHT_X + 8 + x, -TT.SEC_TAB_Y)
            x = x + w + TT.SEC_TAB_STEP
            bt.__secKey = key
            local on = (key == sel)
            SetOutline(bt, on, 1, 0.82, 0)
            bt:GetFontString():SetTextColor(Unpack(on and C_WHITE or C_DIM))
            -- ★ 页签不做底部强调条（用户 2026-09-30 明确不要）：选中态只由金色描边 + 白色
            --   文字表达。这里只留一个纯数据位，供离线探针判定「恰一个选中」。
            bt.__sel = on and true or false
            bt:Show()
        elseif bt then
            bt.__sel = false
            bt:Hide()
        end
    end
    return keys
end

local function BuildSpecCard(sec)
    local card = TakeSpecCard()
    if not card then return nil end
    local span = TT.SPAN_FULL
    local w = TT.FULL_W
    local innerW = TT.INNER_FULL_W
    card.frame:SetWidth(w)
    card.frame:Show()
    card.divider:Hide()
    card.title:Hide()
    card.n = 0
    card.lastFS = nil
    card.lastH = 0
    card.elided = false
    card.elideDelta = 0
    card.pairLineX = nil
    card.pairBot = nil

    TT.__cur = card
    TT.__innerW = innerW
    TT.__cy = -TT.CARD_PAD

    local goods, bads = {}, {}
    for _, e in ipairs(sec.flow or {}) do
        if e.t == "good" then
            for _, item in ipairs(e.v or {}) do goods[#goods + 1] = item end
        elseif e.t == "bad" then
            for _, item in ipairs(e.v or {}) do bads[#bads + 1] = item end
        end
    end
    local pair = (#goods > 0) and (#bads > 0)
    local pairDone = false

    for _, e in ipairs(sec.flow or {}) do
        local t = e.t
        if t == "good" or t == "bad" then
            if not pairDone then
                pairDone = true
                if pair then
                    AddPair(goods, bads, innerW)
                else
                    local items = (#goods > 0) and goods or bads
                    for _, item in ipairs(items) do
                        if not AddRow(item, 14, C_TEXT, 0, TT.CHIP_GAP, TT.SEC_TEXT_W) then break end
                    end
                end
            end
        elseif t == "tb" then
            for _, cells in ipairs(e.v or {}) do
                if type(cells) == "table" then
                    local label = tostring(cells[1] or "")
                    local rest = {}
                    for i = 2, #cells do
                        local cc = cells[i]
                        if cc ~= nil and cc ~= "" then rest[#rest + 1] = tostring(cc) end
                    end
                    local body = table.concat(rest, "　")
                    if label ~= "" then
                        if not AddRow(label, 14, C_GOLD, 0, body ~= "" and 3 or 9) then break end
                    end
                    if body ~= "" then
                        if not AddRow(body, 14, C_TEXT, 0, 9) then break end
                    end
                end
            end
        elseif t == "ul" then
            for _, it in ipairs(e.v or {}) do
                local term, txt = it.term or "", it.text or ""
                if txt ~= "" then
                    if term ~= "" then
                        if not AddRow(term, 14, C_GOLD, 0, 3, TT.SEC_TEXT_W) then break end
                    end
                    if not AddRow(txt, 14, C_TEXT, 0, 6, TT.SEC_TEXT_W) then break end
                elseif term ~= "" then
                    if not AddRow(term, 14, C_GOLD, 0, 6, TT.SEC_TEXT_W) then break end
                end
            end
        elseif t == "races" then
            AddRaces(e.v or {}, innerW)
        elseif t == "h4" then
            TT.__cy = TT.__cy - TT.HELP_HEAD
            if not AddRow(e.v, 14, C_WHITE, 0, 8, TT.SEC_TEXT_W) then break end
        else
            if type(e.v) == "string" and e.v ~= "" then
                if not AddRow(e.v, 14, C_TEXT, 0, 6, TT.SEC_TEXT_W) then break end
            end
        end
    end

    if (card.elideDelta or 0) > 0.01 then
        TT.__cy = TT.__cy - card.elideDelta
        if card.pairLineX and card.pairBot and card.divider:IsShown() then
            card.divider:SetPoint("BOTTOMLEFT", card.frame, "TOPLEFT",
                card.pairLineX, card.pairBot - card.elideDelta + 5)
        end
    end
    card.H = -TT.__cy + TT.CARD_PAD
    card.frame:SetHeight(card.H)
    return { card = card, span = span }
end

-- 前置声明（RenderSpec / BuildScroll 的闭包都引用，函数体在 BuildScroll 之后赋值）
local UpdateScrollUI, CullScrollContent, TierWheel

RenderSpec = function()
    -- ★ 十九轮：渲染代在此自增（不能只靠 TT.Render）——板块页签/专精切换走的是
    --   直调 RenderSpec()，若代数不增，上一板块的未使用行/分隔线仍带「当前代」
    --   标记，会被 CullScrollContent 按旧坐标重新 Show = 幽灵文本残留。
    TT.__renderGen = (TT.__renderGen or 0) + 1
    -- ★ 顶卡接管 spec 模式：显示顶卡（纯卡中卡外观）；rank 模式顶卡由
    --   HideSpec 隐藏（其视口上缘改为严格剔除，无遮罩板）。
    if TT.specTopCard then TT.specTopCard:Show() end
    G = EnsureCG()
    if not G then return end
    local db = DB()
    local cls = db.cls or TT.CLASS_ORDER[1]
    local rec = G.specs[cls]
    if not rec then
        for _, c in ipairs(TT.CLASS_ORDER) do
            if G.specs[c] then cls = c rec = G.specs[c] break end
        end
        if not rec then return end
    end
    local spec = db.spec
    if not spec or not rec[spec] then
        local list = T.specs and T.specs[cls]
        if list then
            for _, sp in ipairs(list) do
                if rec[sp.key] then spec = sp.key break end
            end
        end
        if not spec or not rec[spec] then
            spec = next(rec)
        end
    end
    db.cls, db.spec = cls, spec
    local data = rec[spec]
    local spRec = SpecRec(cls, spec)

    local cr, cg, cb = ClassColor(cls)
    TT.specTitle:SetText(ClassName(cls) .. " · " .. (spRec and spRec.name or spec))
    TT.specTitle:SetTextColor(cr, cg, cb)
    local meta = G.meta or {}
    TT.specMeta:SetText(format(L["补丁 %s · 等级上限 %d · 已更新 %s"],
        tostring(meta.patch or ""), tonumber(meta.level) or 0, tostring(data.updated or "")))
    TT.specMeta:Show()
    SetIcon(TT.heroIcon, spRec and spRec.icon)
    local gk, pk = SpecGrade(cls, spec)
    if gk then
        local gc = TT.COLOR[gk] or TT.COLOR.D
        TT.heroGrade:SetText(format(L["★ %s级 · %s"], gk, TT.PAGE_NAME[pk] or ""))
        TT.heroGrade:SetTextColor(gc[1], gc[2], gc[3])
        TT.heroGrade:Show()
    else
        TT.heroGrade:Hide()
    end
    TT.hero:Show()

    TT.__rows = 0
    TT.__cards = 0
    TT.__chips = 0
    TT.__overflow = 0

    local keys = PaintSecTabs(data)

    if #keys == 0 then
        TT.curSec = nil
        for i = 1, TT.CARD_MAX do
            TT.scCards[i].frame:Hide()
            TT.scCards[i].divider:Hide()
        end
        for i = 1, TT.ROW_MAX do TT.rowPool[i]:Hide() end
        for i = 1, TT.CHIP_MAX do TT.chipPool[i].frame:Hide() end
        TT.child:SetHeight(TT.SPEC_GAP)
        TT.scroll:SetVerticalScroll(0)
        TT.overflowed = false
        return
    end

    local plan
    for _, sec in ipairs(data.sections or {}) do
        if sec.key == db.sec and TT.SEC_TITLE[sec.key] and SectionHas(sec) then
            plan = BuildSpecCard(sec)
            break
        end
    end

    for i = (TT.__cards or 0) + 1, TT.CARD_MAX do
        TT.scCards[i].frame:Hide()
        TT.scCards[i].divider:Hide()
    end
    for i = (TT.__rows or 0) + 1, TT.ROW_MAX do TT.rowPool[i]:Hide() end
    for i = (TT.__chips or 0) + 1, TT.CHIP_MAX do TT.chipPool[i].frame:Hide() end

    TT.curSec = db.sec
    if plan then
        local card = plan.card
        card.frame:ClearAllPoints()
        card.frame:SetPoint("TOPLEFT", TT.child, "TOPLEFT", TT.OUTER_PAD, 0)
        TT.child:SetHeight(card.H + TT.SPEC_GAP)
    else
        TT.child:SetHeight(TT.SPEC_GAP)
    end
    -- ★ child 高度变化后重注册（自管滚动：归零 __v 并把 child 平移回顶）；剔除延后一帧。
    TT.__v = 0
    TT.child:SetPoint("TOPLEFT", TT.scroll, "TOPLEFT", 0, 0)
    CullScrollContent()
    TT.overflowed = (TT.__overflow or 0) > 0
end

local function BuildScroll(page)
    -- ★ 六轮定案（2026-10-10 探针驱动）：视口底 y 符号修正（BOTTOMRIGHT 的 y 为正向上收）
    --   + 固定底板（specPlate）+ 行级剔除（CullScrollContent）三件套落地后，滚动内容全是
    --   矮元素、不再依赖引擎裁剪 ⇒ 回退裸 ScrollFrame（无模板自带滚动条）。
    --   滚动条自绘藏品样式（2026-10-10 用户定案）：track L2 胶囊 + thumb L4 可拖拽，
    --   内容不足一屏整条隐藏。
    local scroll = CreateFrame("ScrollFrame", nil, page)
    scroll:EnableMouseWheel(true)
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", TT.RIGHT_X, -TT.BODY_TOP)
    -- ★ BOTTOMRIGHT 的 y 必须为正（向上收）：视口底 = page 底上方 EDGE+INSET（卡底内衬 8）。
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT",
                    -(TT.EDGE + TT.INSET), TT.EDGE + TT.INSET)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        TierWheel(delta)
    end)
    scroll:SetScript("OnVerticalScroll", function()
        CullScrollContent()
    end)
    -- ── 自绘滚动条（藏品页同款：轨道 L2 胶囊 + 滑块 L4 胶囊可拖拽）──
    local track = CreateFrame("Frame", nil, scroll, "BackdropTemplate")
    if ns.hui and ns.hui.BuildCapsule then
        ns.hui.BuildCapsule(track, 3, ns.hui.layer.L2)
    else
        track:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        track:SetBackdropColor(0, 0, 0, 0.25)
        track:SetBackdropBorderColor(1, 1, 1, 0.08)
    end
    track:SetWidth(6)
    -- ★ 滚动条放卡片外（2026-10-10 用户定案）：右缘越过 scroll 内容缘 +7，落进内容
    --   右缘（932）与 contentCard 卡缘（940）之间的 8px 沟槽，不再遮挡内容。
    --   ★ 二十六轮：上下缘与视口/底板齐平（原 ±1 内缩）——轨道与文字底板是同参照
    --   兄弟件，齐平后轨道底距 contentCard 卡底恰 8（间距标准），顶底不再差 1px。
    track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 7, 0)
    track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 7, 0)
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(4)
    thumb:EnableMouse(true)
    if ns.hui and ns.hui.BuildCapsule then
        ns.hui.BuildCapsule(thumb, 2, ns.hui.layer.L4)
    else
        local tx = thumb:CreateTexture(nil, "OVERLAY")
        tx:SetAllPoints()
        tx:SetColorTexture(1, 1, 1, 0.30)
    end
    thumb:SetPoint("TOP", track, "TOP", 0, -1)
    thumb:Hide()
    -- 滑块拖拽：光标位移按比例映射到滚动值（藏品页同款；自记账 clamp 同滚轮）
    thumb:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        local scale = UIParent and UIParent:GetEffectiveScale() or 1
        local cy0 = select(2, GetCursorPosition()) / scale
        local sc0 = TT.__v or 0
        self:SetScript("OnUpdate", function()
            local cy = select(2, GetCursorPosition()) / scale
            local trackH = track:GetHeight() - 2
            local span = trackH - thumb:GetHeight()
            if span <= 0 then return end
            local maxScroll = TT.child:GetHeight() - TT.scroll:GetHeight()
            TT.__v = math.min(maxScroll, math.max(0, sc0 + (cy0 - cy) / span * maxScroll))
            TT.child:SetPoint("TOPLEFT", TT.scroll, "TOPLEFT", 0, TT.__v)
            -- ★ 十五轮补全：拖拽路径此前漏剔除与滑块同步（拖到一半行不隐藏/滑块不回弹）。
            CullScrollContent()
            UpdateScrollUI()
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    thumb:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    TT.sbarTrack, TT.sbarThumb = track, thumb
    -- ★ child 挂 page 而非 scroll（九轮+）：彻底摆脱 ScrollFrame 的 C 层干预——
    --   本引擎 ScrollFrame 对子帧/滚动状态的管理不可信（滚动状态与布局脱节、
    --   未注册 SetScrollChild 时 SetVerticalScroll 直接失效）。child 成为普通帧，
    --   滚动 = TierWheel 里 SetPoint 平移；超界部分由行级剔除 Hide。
    local child = CreateFrame("Frame", nil, page)
    child:SetSize(TT.FULL_W + 2 * TT.OUTER_PAD, 10)
    child:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    TT.scroll, TT.child = scroll, child
    -- ★ 固定内容底板（2026-10-10 用户定案：卡固定、内容滚动）：挂 page、不进滚动；
    --   渲染时与 scroll 同矩形（SetAllPoints），L2 实底 r6；spec/rank 两模式共用。
    --   层级在 Build 尾收口块之后压到 cardLvl+1（低于 scroll 内容、高于 contentCard）。
    do
        local plate = CreateFrame("Frame", nil, page, "BackdropTemplate")
        if ns.hui and ns.hui.SkinPopup then
            ns.hui.SkinPopup(plate, 6, nil, ns.hui.layer.L2)
        else
            plate:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            plate:SetBackdropColor(0.086, 0.102, 0.133, 1)  -- L2 161A22
        end
        plate:Hide()
        TT.specPlate = plate
    end
    -- ★ 十六轮伪裁剪（引擎无裁剪 ⇒ 骑视口上缘的元素上半截画进 hero/页签区）：
    --   历史上用 GlassPlate 玻璃同材遮罩（纯色板叠玻璃卡面必然显形黑块，十七轮
    --   教训）。二十三/二十四轮后遮罩全部退役：spec/rank 一律上缘严格剔除——顶卡
    --   与视口间的 8px 沟槽挡不住溢出（见 CullScrollContent），顶卡只剩卡中卡外观。
end

-- ★ 自算剔除（十二轮终稿）：渲染锚定时每个视觉元素登记 __cy/__ch（child 坐标，
--   距 child 顶向下），剔除 = 纯数字区间比较 [__v, __v+viewH] —— 完全不碰引擎布局
--   读数（GetTop/GetBottom 已证实与渲染脱节，同帧/下一帧都不可信）。
CullScrollContent = function()
    local scroll = TT.scroll
    if not scroll then return end
    local viewH = scroll.GetHeight and scroll:GetHeight()
    if type(viewH) ~= "number" then return end
    local vTop, vBot = (TT.__v or 0), (TT.__v or 0) + viewH
    -- ★ 十五轮破案（探针 v3 取证）：旧判据 `not el:IsShown() then return` 是单向门——
    --   元素被剔除 Hide 后，回滚再进视口时因 IsShown=false 被直接跳过，永远无法重新
    --   Show（下滚再上滚顶部内容消失、滚到底下方空白的真凶）。改为「渲染代」门控：
    --   只处理本轮渲染(TT.__renderGen)登记的元素，无论当前显隐一律参与区间判定，
    --   被隐藏的行回滚进视口后能重新 Show；上一轮的残留登记（旧代）一律跳过，
    --   不会把别的模式/上轮布局的幽灵行误显示出来。
    local gen = TT.__renderGen
    local function cull(el)
        if not el or el.__cgen ~= gen then return end
        local cy, ch = el.__cy, el.__ch
        if type(cy) ~= "number" or type(ch) ~= "number" then return end
        -- 与视口相交才显示：底在视口顶之下 且 顶在视口底之上。
        -- ★ 用 Show/Hide 而非 SetShown（后者同为 8.0+ API，本引擎无）。
        -- ★ 下缘「底缘全入才显示」——骑底元素的无裁剪溢出会画出卡外甚至窗外；
        --   超高元素（≥视口高，理论不存在）退回骑底判定防永不显示。
        -- ★ 二十三轮 rank 上缘严格 → 二十四轮 spec 同样严格（统一）：spec 视口上方的
        --   顶卡只盖条带主体（EDGE+8 ~ SEC_TOP-8），与视口顶之间有 8px 沟槽 + 窗沿
        --   8px（间距标准），骑缘元素的溢出上半截会从沟槽漏出（实机复现）⇒ 两模式
        --   一律「顶入视口才显示」结构性杜绝，遮罩方案彻底退役。
        local show = false
        if (cy + ch) > vTop then
            if ch < viewH then
                show = (cy >= vTop) and ((cy + ch) <= vBot)
            else
                show = cy < vBot
            end
        end
        if show then
            el:Show()
        else
            el:Hide()
        end
    end
    for i = 1, TT.CARD_MAX do
        local c = TT.cards and TT.cards[i]
        if c then cull(c.frame) end
    end
    cull(TT.factorTitle)
    cull(TT.intro)
    if TT.factorRows then for i = 1, #TT.factorRows do cull(TT.factorRows[i]) end end
    if TT.noteRows then for i = 1, #TT.noteRows do cull(TT.noteRows[i]) end end
    if TT.rowPool then for i = 1, #TT.rowPool do cull(TT.rowPool[i]) end end
    if TT.chipPool then
        for i = 1, #TT.chipPool do
            local chip = TT.chipPool[i]
            if chip then cull(chip.frame) end
        end
    end
    -- ★ 十五轮补全：spec 分隔线此前漏剔除（滚出视口仍绘制，溢出帮凶）。
    if TT.scCards then
        for i = 1, TT.CARD_MAX do
            local c = TT.scCards[i]
            if c then cull(c.divider) end
        end
    end
end

-- 滚动条联动：内容不足一屏整条隐藏；滑块高/位置按视口占比刷新（藏品页同款）。
UpdateScrollUI = function()
    local scroll, child = TT.scroll, TT.child
    if not (scroll and child and TT.sbarTrack) then return end
    local viewH, contentH = scroll.GetHeight and scroll:GetHeight(), child.GetHeight and child:GetHeight()
    if type(viewH) ~= "number" or type(contentH) ~= "number" then return end
    if contentH <= viewH + 2 then
        TT.sbarTrack:Hide()
        return
    end
    TT.sbarTrack:Show()
    local trackH = TT.sbarTrack:GetHeight() - 2
    local maxScroll = contentH - viewH
    local frac = math.min(1, math.max(0, (TT.__v or 0) / maxScroll))
    local th = math.max(24, trackH * viewH / contentH)
    local thumb = TT.sbarThumb
    thumb:SetHeight(th)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", TT.sbarTrack, "TOP", 0, -1 - frac * (trackH - th))
end

-- ★ 自管滚动（九轮+十轮定案）：__v 唯一真源，严格钳 [0, childH - viewH]；
--   child 用 SetPoint 平移。scroll 与 child 两处 OnMouseWheel 都挂本函数
--   （child 盖在视口上会先吃到滚轮事件，两处挂同一逻辑防漏）。
TierWheel = function(delta)
    local maxScroll = math.max(0, (TT.child.GetHeight and TT.child:GetHeight() or 0)
                                  - (TT.scroll.GetHeight and TT.scroll:GetHeight() or 0))
    if type(maxScroll) ~= "number" then return end
    TT.__v = math.max(0, math.min(maxScroll, (TT.__v or 0) - delta * 48))
    TT.child:SetPoint("TOPLEFT", TT.scroll, "TOPLEFT", 0, TT.__v)
    CullScrollContent()
    UpdateScrollUI()
end

function TT.PlaceScroll(top)
    local scroll = TT.scroll
    if not scroll or not TT.page then return end
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", TT.page, "TOPLEFT", TT.RIGHT_X, -(top or TT.BODY_TOP))
    -- ★ 同 BuildScroll：BOTTOMRIGHT 的 y 为正（向上收），视口底 = 卡底内衬 8。
    scroll:SetPoint("BOTTOMRIGHT", TT.page, "BOTTOMRIGHT",
                    -(TT.EDGE + TT.INSET), TT.EDGE + TT.INSET)
    -- ★ BOTTOMRIGHT 的 y 为正（向上收）：视口底 = 卡底内衬 8。视口顶由 Render
    --   分支经本函数传入（spec=SEC_TOP / rank=__rankTop）。
end

function TT.Build(page)
    if TT.built or TT.building then return end
    ns.OpenPerf.Begin("职业指南")
    TT.building = true
    ns.PhasedStart(15, coroutine.create(function()
    TT.page = page

    -- ★ 双大卡最先建（模板=探索页 navCard/listCard）：后续兄弟帧（按钮/滚动区/hero）
    --   天然浮在实底卡上；page 直挂 FontString 由 Build 尾部的文字宿主层承接。
    do
        local navCard = CreateFrame("Frame", nil, page, "BackdropTemplate")
        local contentCard = CreateFrame("Frame", nil, page, "BackdropTemplate")
        -- ★ 锚定（2026-10-10 补）：漏 SetPoint = 零尺寸帧不可见。几何与间距标准对齐：
        --   两卡坐窗沿 20；卡↔卡缝 8（navCard 右缘 = X0-8，contentCard 左缘 = X0）；
        --   内容线 RIGHT_X/SUB_Y/BODY_TOP/滚动区底 -28 全部恰好卡内衬 8。
        navCard:SetPoint("TOPLEFT", page, "TOPLEFT", TT.EDGE, -TT.CARD_TOP)
        navCard:SetPoint("BOTTOMRIGHT", page, "BOTTOMLEFT", TT.X0 - TT.INSET, TT.EDGE)
        contentCard:SetPoint("TOPLEFT", page, "TOPLEFT", TT.X0, -TT.CARD_TOP)
        contentCard:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -TT.EDGE, TT.EDGE)
        if ns.hui and ns.hui.SkinPopup then
            ns.hui.SkinPopup(navCard, 6)
            ns.hui.SkinPopup(contentCard, 6)
        else
            for _, f in ipairs({ navCard, contentCard }) do
                f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
                                edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
                f:SetBackdropColor(1, 1, 1, 0.03)
                f:SetBackdropBorderColor(1, 1, 1, 0.05)
            end
        end
        TT.navCard, TT.contentCard = navCard, contentCard
    end
    coroutine.yield()

    BuildNav(page)
    BuildSubTabs(page)
    coroutine.yield()
    BuildScroll(page)
    coroutine.yield()

    local child = TT.child
    -- ★ 行文字宿主层（探索页 labelHost 同款）：内容卡是 L2 实底帧，child 直挂
    --   FontString 是 region、永远画在同父子帧之下 → 行/简介/依据/注释全被实底卡
    --   盖住（专精指南空壳卡实锤）。行文字统一搬进抬高的宿主帧。
    local rowHost = CreateFrame("Frame", nil, child)
    rowHost:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    TT.rowHost = rowHost
    TT.meta = MakeFS(page, 14, C_GREY, "LEFT")
    -- 同 specMeta：相对点 TOPRIGHT（右上角），自身 "RIGHT" 取垂直居中对齐页签行中心。
    TT.meta:SetPoint("RIGHT", page, "TOPRIGHT", -(TT.EDGE + TT.INSET), -(TT.SUB_Y + TT.SUB_H / 2))
    TT.intro = MakeFS(TT.rowHost, 14, C_DIM, "LEFT")
    TT.intro:SetWidth(TT.CARD_W - 100)
    coroutine.yield()

    BuildCards(child)
    coroutine.yield()
    BuildNotes(TT.rowHost)
    coroutine.yield()
    BuildSpecHero(page)
    BuildSecTabs(page)
    BuildSpecPool(child)
    coroutine.yield()

    TT.built = true
    TT.building = false
    ns.OpenPerf.Mark("就绪")

    -- ★ 层级收口（实底卡时代的静默杀手，探索页同款）：两块大卡之上的兄弟帧显式抬高；
    --   page 直挂 FontString（组标题 / 元信息行）是 region，永远画在子帧之下、
    --   SetFrameLevel 管不到 → 搬进抬高的专用文字宿主层。
    do
        local cardLvl = TT.navCard:GetFrameLevel()
        TT.contentCard:SetFrameLevel(cardLvl)
        local tl = CreateFrame("Frame", nil, page)
        tl:SetFrameLevel(cardLvl + 2)
        for _, rg in ipairs({ page:GetRegions() }) do
            rg:SetParent(tl)
        end
        TT.textLayer = tl
        for _, fr in ipairs({ page:GetChildren() }) do
            if fr ~= TT.navCard and fr ~= TT.contentCard and fr ~= tl then
                fr:SetFrameLevel(math.max(fr:GetFrameLevel(), cardLvl + 2))
            end
        end
        -- ★ specPlate 是专精固定底板（背景）：压到 scroll 内容（cardLvl+2）之下、
        --   contentCard 容器卡（cardLvl）之上 —— 内容行滚过它、它垫住视口矩形。
        if TT.specPlate then
            TT.specPlate:SetFrameLevel(cardLvl + 1)
        end
        -- ★ 十六轮：伪裁剪遮罩（卡外段 +3、卡内段 +4 同色段压住接缝）高于滚动内容
        --   （cardLvl+2）；固定件（hero / 各级页签 / 元信息文字层）抬到 +6，
        --   保证页签与标题画在遮罩之上不被盖住。
        -- ★ 十六轮：伪裁剪遮罩层级。先「压平」内容——scCard 去背景后行文字不再需要
        --   高于卡帧，全部统一 cardLvl+2（rowHost 曾按 scCards+1 抬层，会造出「后代
        --   层级高于/低于祖先」的未定义序，本引擎同层序本就随机，必须消灭）；
        --   遮罩 = 卡外段 +3 / 卡内段 +4，固定件 +7。
        if TT.rowHost then TT.rowHost:SetFrameLevel(cardLvl + 2) end
        for i = 1, TT.CARD_MAX do
            if TT.scCards[i] then TT.scCards[i].frame:SetFrameLevel(cardLvl + 2) end
        end
        if TT.chipPool then
            for i = 1, #TT.chipPool do
                if TT.chipPool[i] then TT.chipPool[i].frame:SetFrameLevel(cardLvl + 2) end
            end
        end
        -- ★ 顶卡（纯卡中卡外观，上缘剔除已严格化、遮罩职责退役）：压到底板档
        --   （与 specPlate 同层；二者上下相邻不叠，同层无冲突），不遮任何内容。
        if TT.specTopCard then TT.specTopCard:SetFrameLevel(cardLvl + 1) end
        local fixLvl = cardLvl + 7
        if TT.hero then TT.hero:SetFrameLevel(fixLvl) end
        if TT.textLayer then TT.textLayer:SetFrameLevel(fixLvl) end
        for _, bt in pairs(TT.specTabs or {}) do bt:SetFrameLevel(fixLvl) end
        for _, bt in pairs(TT.secTabs or {}) do bt:SetFrameLevel(fixLvl) end
        for _, bt in pairs(TT.subBtns or {}) do bt:SetFrameLevel(fixLvl) end
    end
    coroutine.yield()

    TT.Render()
    end))
end

function TT.PaintNav()
    local db = DB()
    local specMode = (db.nav == "spec") and (EnsureCG() ~= nil) or false
    local rankSel = not specMode
    SetOutline(TT.navBtn, rankSel, 1, 0.82, 0)
    TT.navBtn:GetFontString():SetTextColor(Unpack(rankSel and C_WHITE or C_DIM))
    if TT.classBtns then
        for cls, cb in pairs(TT.classBtns) do
            local sel = specMode and (cls == db.cls)
            SetClassBase(cb, sel)
            -- 文字取职业色（与团本页 9 枚职业芯片同一口径）；选中只靠金色描边 + 不透明度区分。
            local cr, cg, cbc = ClassColor(cls)
            cb.__txt:SetTextColor(cr, cg, cbc)
            cb.__txt:SetAlpha(sel and 1 or 0.82)
            SetOutline(cb, sel, 1, 0.82, 0)
        end
    end
    for _, bt in pairs(TT.subBtns) do
        bt:SetShown(rankSel)
    end
    if TT.specTabs then
        for _, bt in pairs(TT.specTabs) do
            bt:Hide()
        end
        if specMode then
            local list = T.specs and T.specs[db.cls]
            local i = 0
            for _, sp in ipairs(list or {}) do
                if G.specs[db.cls] and G.specs[db.cls][sp.key] then
                    i = i + 1
                    local bt = TT.specTabs[i]
                    if bt then
                        bt.__specKey = sp.key
                        bt:SetText(sp.name)
                        bt:Show()
                        local sel = (sp.key == db.spec)
                        SetOutline(bt, sel, 1, 0.82, 0)
                        bt:GetFontString():SetTextColor(Unpack(sel and C_WHITE or C_DIM))
                    end
                end
            end
        end
    end
    if TT.secTabs and not specMode then
        for i = 1, TT.SEC_TAB_MAX do
            if TT.secTabs[i] then TT.secTabs[i]:Hide() end
        end
    end
    return specMode
end

function TT.OpenSpec(cls, spec)
    G = EnsureCG()
    if not G then return end
    local db = DB()
    db.nav = "spec"
    db.cls = cls
    if spec then db.spec = spec end
    TT.Render()
    ns.PlaySound(1)
end

function TT.HideRank()
    TT.meta:Hide()
    TT.intro:Hide()
    for i = 1, 5 do
        TT.cards[i].frame:Hide()
    end
    TT.factorTitle:Hide()
    for i = 1, 6 do TT.factorRows[i]:Hide() end
    for i = 1, 10 do TT.noteRows[i]:Hide() end
end

function TT.HideSpec()
    if not TT.specTitle then return end
    if TT.specTopCard then TT.specTopCard:Hide() end
    if TT.hero then TT.hero:Hide() end
    if TT.heroGrade then TT.heroGrade:Hide() end
    if TT.specMeta then TT.specMeta:Hide() end
    if TT.secTabs then
        for i = 1, TT.SEC_TAB_MAX do
            if TT.secTabs[i] then TT.secTabs[i]:Hide() end
        end
    end
    for i = 1, TT.CARD_MAX do
        if TT.scCards[i] then
            TT.scCards[i].frame:Hide()
            TT.scCards[i].divider:Hide()
        end
    end
    for i = 1, TT.ROW_MAX do
        if TT.rowPool[i] then TT.rowPool[i]:Hide() end
    end
    for i = 1, TT.CHIP_MAX do
        if TT.chipPool[i] then TT.chipPool[i].frame:Hide() end
    end
end

local function PY()
    if coroutine.running and coroutine.running() then coroutine.yield() end
end

function TT.Render()
    if not TT.built then return end
    -- ★ 十五轮：渲染代自增——本轮渲染登记的元素才参与滚动剔除（见 CullScrollContent）。
    TT.__renderGen = (TT.__renderGen or 0) + 1
    local specMode = TT.PaintNav()
    TT.__mode = specMode and "spec" or "rank"
    PY()
    if specMode then
        TT.PlaceScroll(TT.SEC_TOP)
        TT.HideRank()
        RenderSpec()
        -- ★ 固定内容底板：与滚动视口同矩形（专精卡固定、内容滚动的背景板）。
        if TT.specPlate then
            TT.specPlate:ClearAllPoints()
            TT.specPlate:SetAllPoints(TT.scroll)
            TT.specPlate:Show()
        end
    else
        TT.HideSpec()
        TT.RenderRank()
        -- ★ 二十三轮重排：视口顶 = tier 卡区底（RenderRank 捕获的 __rankTop），
        --   故 PlaceScroll 必须排在渲染之后；滚动只作用于下方文字卡（排名依据 +
        --   注意事项），tier 卡区固定不滚。
        TT.PlaceScroll(TT.__rankTop or TT.BODY_TOP)
        -- ★ 文字底板：与（重排后的）滚动视口同矩形，只衬文字区。
        if TT.specPlate then
            TT.specPlate:ClearAllPoints()
            TT.specPlate:SetAllPoints(TT.scroll)
            TT.specPlate:Show()
        end
        -- ★ 同 RenderSpec：自管滚动归零（child 平移回顶）+ 剔除 + 滑块回顶。
        --   必须在 PlaceScroll 改完视口矩形之后执行。
        TT.__v = 0
        TT.child:SetPoint("TOPLEFT", TT.scroll, "TOPLEFT", 0, 0)
        CullScrollContent()
        UpdateScrollUI()
    end
end

function TT.RenderRank()
    -- ★ 十九轮：同 RenderSpec——登记入口自带代数自增（对称防御）。
    TT.__renderGen = (TT.__renderGen or 0) + 1
    if not TT.built then return end
    local p = PageFor(DB().tab)
    local own = MobileCls()

    for k, bt in pairs(TT.subBtns) do
        local sel = (k == p.key)
        SetOutline(bt, sel, 1, 0.82, 0)
        bt:GetFontString():SetTextColor(Unpack(sel and C_WHITE or C_DIM))
    end

    local meta = T.meta or {}
    TT.meta:SetText(format(L["补丁 %s · 等级上限 %d · 已更新 %s"],
        tostring(meta.patch or ""), tonumber(meta.level) or 0, tostring(meta.updated or "")))
    TT.intro:SetText(p.intro or "")
    local leadW = 100
    if TT.factorTitle and TT.factorTitle.GetStringWidth then
        local w = TT.factorTitle:GetStringWidth()
        if tonumber(w) then leadW = w + 20 end
    end
    TT.intro:SetWidth(math.max(160, TT.CARD_W - leadW))

    -- ★ 二十七轮（UI_RULES §3 链式推导）：页签胶囊行底 = SUB_Y+SUB_H = BODY_TOP-8，
    --   首张 tier 卡顶必须 = 胶囊底 + 8 = BODY_TOP —— 故 tier 区从 y=0 起排（原 y=8
    --   多垫一道 8，首卡顶变胶囊底+16）。文字区起排的 y=8 在底板内，属卡内内衬豁免。
    local y = 0

    local tiers = p.tiers or {}
    for i = 1, 5 do
        local ui = TT.cards[i]
        local tier = tiers[i]
        ui.frame:Hide()
        if i % 2 == 0 then PY() end
        if tier then
            local key = tier.key
            local specs = tier.specs or {}
            local col = TT.COLOR[key] or TT.COLOR.D
            local bc = ui.badgeColor
            bc[1], bc[2], bc[3], bc[4] = col[1], col[2], col[3], 1
            if ui.badgeRepaint then
                ui.badgeRepaint()
            elseif ui.badge.SetBackdropColor then
                ui.badge:SetBackdropColor(col[1], col[2], col[3], 1)
            end
            ui.letter:SetText(key)
            ui.letter:SetTextColor(TT.BADGE_TEXT[1], TT.BADGE_TEXT[2], TT.BADGE_TEXT[3])
            local rows = math.ceil(#specs / TT.GRID_COLS)
            local h = math.max(TT.EMPTY_H, rows * TT.CELL_H + 2 * TT.LIST_PAD)
            ui.frame:SetHeight(h)
            ui.frame:ClearAllPoints()
            -- ★ 二十二轮重排：tier 卡改为固定定位（挂 page，不随滚动）——滚动只属于
            --   下方文字卡（排名依据 + 注意事项）。页 y = BODY_TOP + 累计 y。
            ui.frame:SetPoint("TOPLEFT", TT.page, "TOPLEFT", TT.RIGHT_X, -(TT.BODY_TOP + y))
            ui.badge:SetHeight(h - 2 * TT.LIST_PAD)
            ui.badge:ClearAllPoints()
            ui.badge:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", TT.LIST_PAD, -TT.LIST_PAD)
            if #specs == 0 then
                ui.empty:ClearAllPoints()
                ui.empty:SetPoint("LEFT", ui.badge, "RIGHT", 16, 0)
                ui.empty:Show()
            else
                ui.empty:Hide()
            end
            for c = 1, TT.GRID_COLS * TT.GRID_ROWS do
                local cell = ui.cells[c]
                local e = specs[c]
                if e then
                    local rec = SpecRec(e.class, e.spec)
                    cell.cls = e.class
                    cell.spec = e.spec
                    cell.rec = rec
                    cell.tierKey = key
                    cell.own = (e.class == own) and true or false
                    local gridCol = (c - 1) % TT.GRID_COLS
                    local gridRow = math.floor((c - 1) / TT.GRID_COLS)
                    cell:ClearAllPoints()
                    cell:SetPoint("TOPLEFT", ui.frame, "TOPLEFT",
                        TT.LIST_PAD + TT.BADGE_W + 16 + gridCol * ui.cellW,
                        -TT.LIST_PAD - gridRow * TT.CELL_H)
                    SetIcon(cell.icon, rec and rec.icon)
                    cell.name:SetText(rec and rec.name or "?")
                    local cr2, cg2, cb2 = ClassColor(e.class)
                    cell.name:SetTextColor(cr2, cg2, cb2)
                    cell:Show()
                    PaintCell(cell, cell.own, false)
                else
                    cell.cls, cell.spec, cell.rec, cell.tierKey = nil, nil, nil, nil
                    cell.own = false
                    cell:Hide()
                end
            end
            ui.frame:Show()
            y = y + h + TT.CARD_GAP
        end
    end

    -- ★ 二十三轮重排：tier 卡区已固定（挂 page，见上）。滚动视口从文字区开始，
    --   视口顶 = tier 卡排完的页 y（此刻 y 已含最后一张卡后的 CARD_GAP）。文字区
    --   改从 child 顶起排（child 只承载文字卡内容），剔除坐标口径不变。
    TT.__rankTop = TT.BODY_TOP + y
    y = 8
    TT.factorTitle:ClearAllPoints()
    TT.factorTitle:SetPoint("TOPLEFT", TT.child, "TOPLEFT", 0, -y)
    -- ★ 自算剔除登记。
    TT.factorTitle.__cy, TT.factorTitle.__ch = y, FSHeight(TT.factorTitle)
    TT.factorTitle.__cgen = TT.__renderGen
    TT.intro:ClearAllPoints()
    TT.intro:SetPoint("LEFT", TT.factorTitle, "RIGHT", 16, 0)
    TT.intro.__cy, TT.intro.__ch = TT.factorTitle.__cy, FSHeight(TT.intro)
    TT.intro.__cgen = TT.__renderGen
    y = y + math.max(FSHeight(TT.factorTitle), FSHeight(TT.intro)) + 8

    local factors = p.factors or {}
    for i = 1, 6 do
        local row = TT.factorRows[i]
        local f = factors[i]
        if f then
            row:SetWidth(TT.CARD_W)
            row:SetText(format("|cffffd100%s|r  %s", f[1] or "", f[2] or ""))
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", TT.child, "TOPLEFT", 0, -y)
            row:Show()
            local rh = FSHeight(row)
            row.__cy, row.__ch = y, rh
            row.__cgen = TT.__renderGen
            y = y + rh + 5
        else
            row:Hide()
        end
    end

    y = y + 8
    local notes = p.notes or {}
    for i = 1, 10 do
        local row = TT.noteRows[i]
        local n = notes[i]
        if n then
            row:SetWidth(TT.CARD_W)
            row:SetText(n)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", TT.child, "TOPLEFT", 0, -y)
            row:Show()
            local rh = FSHeight(row)
            row.__cy, row.__ch = y, rh
            row.__cgen = TT.__renderGen
            y = y + rh + 7
        else
            row:Hide()
        end
    end

    TT.child:SetHeight(y + 10)
    -- ★ 二十三轮：归零/剔除上移到 TT.Render rank 分支——必须在 PlaceScroll 重排
    --   视口顶（__rankTop）之后执行，此处只剩内容高度落定。
end

function TT.Refresh()
    if not TT.built then return end
    TT.Render()
end

function TT.OnThemeChange()
    if not TT.built then return end
    TT.Render()
end
