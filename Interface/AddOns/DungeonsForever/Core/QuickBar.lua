-- =============================================================================
-- DungeonsForever · 主窗口右侧「快捷按钮栏」
--
--   贴主窗右缘的常驻窄栏（与「设置」/「装备过滤」槽位并存、互不挤占）：
--     · 推荐五人本 —— 按玩家等级实时算（沿用副本页 DG.GroupOf 的 rec 桶），
--                     点条目直接进该副本详情
--     · 专业       —— 列表口径由设置决定：只看已学 / 全部
--     · 探索       —— 显示哪几个子页由设置里的多选决定
--   总开关与各分组开关存 DungeonsForeverDB.ui.quick（读写都走 Core.lua 的 ns.QuickCfg）。
--
--   ★ 吸附（两档槽位，随「设置」/「装备过滤」弹窗显隐**实时**切换，不用关掉主窗重开）：
--     · 两个弹窗都关着 → 左靠、贴住主窗右缘（槽位 8），和主窗连成一体；
--     · 任一弹窗打开   → 让位到第二槽（槽位 236 = 第一槽 220 + 8 + 8），两栏不叠。
--     切换走弹窗自己的 OnShow / OnHide 钩子（QB:HookSettings）；面板的开关处再显式锚一次
--     （弹窗可能是**建好之后**才第一次打开，钩子那一刻还没挂上）。
--
--   ★ 启动即建（QB:Boot）：面板是主窗的**子帧**，登录时就建好 ⇒ 主窗一显示它就跟着显示。
--     这样彻底摆脱「钩子没跑到 / 钩子跑得太早」这类时序问题（实机症状：要关掉主窗再开才出来）。
--
--   约束：字号仅 11 / 14 / 16；面板宽 120（左右内边距 8 → 内容宽 104）；
--         标题「5人本专业探索」与**分组头**（推荐五人本 / 专业 / 探索）同为 14
--         （分组头原为 11，2026-09-30 用户定：与按钮文字同号 —— QB.FS_GRP）；
--         ★「全部副本」摆在「推荐五人本」**分组头上方**（它是整页入口，先给；2026-09-30 用户定）；
--         父级 = 主窗口（随窗显隐、继承缩放）；
--         **条目恒单行**：等级 / 熟练度只进悬停提示，不占副行；
--         条目名超宽按「字」截断并补「…」（绝不截半个汉字；完整名在悬停提示里）；
--         ★ 专业条目内嵌 **16px 圆角图标**（图标名取 Data_Professions 的 p.icon →
--           Interface\Icons\*）；图标**单独套一层与图标等大的帧**再挂蒙版 ——
--           ns.hui.RoundIcon 把圆角蒙版挂在贴图的父帧上，父帧比图标大就裁错角（同 TierUI）；
--           ★ 贴图 UV 四边各内缩 7%（0.07 ~ 0.93）**裁掉素材自带的那圈边**
--             —— 与全仓（ProfessionUI / TierUI / BisUI / ExploreUI / LootFilterUI / RaidUI）
--             同口径，不裁的话圆角蒙版里会留一圈素材边框色（2026-09-30 用户点出）；
--           其余条目无图标，文本回到左缩进 4（带图标时 23）。
--         条目 = **圆角**按钮：底与边都走 HUI 的圆角拼装原语
--           · 底色 ns.hui.BuildRoundedBG（圆角盘 + 四条补边，noRepaint 免被主题重绘冲掉悬停态）
--           · 描边 ns.hui.BuildRoundBorder（1px 圆角弧 + 上下左右补条，thickness 默认 1）
--           常态中性灰蓝描边、悬停转金、划走复位；悬停只改**已建贴图**的颜色 / alpha，不重建
--           （重建会持续累积贴图 = 泄漏）。
--         本文件只挂 QB.* 与 ns.*，不定义裸全局函数。
--
--   ★ 本文件不是生成物，是手写件，直接改本文件即可。
-- =============================================================================

local _, ns = ...

if not ns.IsTitan then return end

local L = ns.L

local QB = {}
ns.QuickBar = QB

-- 几何 -----------------------------------------------------------------------
QB.W = 120                     -- 面板宽（标题 14px 的「5人本专业探索」≈92px，100 装不下）
QB.SLOT1 = 8                   -- 贴主窗右缘（设置 / 装备过滤 弹窗都关着时用这一档）
QB.SLOT2 = 236                 -- 第二槽左缘 = 第一槽 220 + 间距 8 + 再留 8（有弹窗占第一槽时让位）
QB.PAD = 8                     -- 左右内边距
QB.CW = QB.W - QB.PAD * 2      -- 内容宽 104
QB.TEXT_PAD = 4                -- 无图标条目的文本左缩进
QB.FS_HEAD, QB.FS_NAME, QB.FS_AUX = 14, 14, 11
QB.FS_GRP = 14                 -- 分组头字号（推荐五人本 / 专业 / 探索；2026-09-30 用户定：与条目同号）
QB.ICON = 16                   -- 专业条目内的图标边长（行高 22，上下各留 3px）
QB.ICON_X = 3                  -- 图标左缩进
QB.NAME_ICON_X = QB.ICON_X + QB.ICON + 4   -- 带图标条目的文本左缩进 = 23
QB.HEAD_Y, QB.BODY_Y = -10, -36
QB.GRP_H, QB.GAP = 20, 3
QB.ROW_H = 22                  -- 条目恒单行 → 固定行高
QB.RADIUS = 6                  -- 条目圆角半径（与 hui.SkinButton / SkinPopup 同规格）

local C_WHITE = { 1, 1, 1 }
local C_TEXT  = { 0.88, 0.88, 0.88 }
local C_DIM   = { 0.62, 0.62, 0.62 }
local C_GOLD  = { 1, 0.82, 0 }
local C_EDGE  = { 0.40, 0.43, 0.50 }   -- 条目常态描边色（悬停换 C_GOLD）
QB.EDGE, QB.EDGE_HOT = C_EDGE, C_GOLD
QB.FILL, QB.FILL_HOT = 0.04, 0.12      -- 条目常态 / 悬停底色 alpha

local strbyte, strsub, format = string.byte, string.sub, format or string.format

-- 探索子页：键与 Core/ExploreUI.lua 的 CurSub 口径一致；栏内用短标签。
local EXPLORE_DEFS = {
    { key = "books",   text = L["40本书"] },
    { key = "rewards", text = L["奖励总览"] },
    { key = "bag",     text = L["睡袋"] },
    { key = "bm",      text = L["战斗法师"] },
}

local function Accent()
    local a = ns.hui and ns.hui.ACCENT
    if a then return a[1], a[2], a[3] end
    return 0x46 / 255, 0xbf / 255, 0x72 / 255
end

local function Fs(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(ns.FONT, size, "")
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
    return fs
end

local function Outline(bt, on)
    local H = ns.ProfHost
    if not (H and H.SetOutline) then return end
    H.SetOutline(bt, on, 1, 0.82, 0)
end

-- 图标 -------------------------------------------------------------------
local FALLBACK_ICON = (ns.ProfHost and ns.ProfHost.FALLBACK_ICON)
    or "Interface\\Icons\\INV_Misc_QuestionMark"

-- 专业图标名（Data_Professions 的 p.icon，如 "trade_alchemy"）→ 纹理；带反斜杠的当整路径。
local function SetIcon(tex, name)
    if type(name) == "number" then
        tex:SetTexture(name)
    elseif type(name) == "string" and name ~= "" then
        if name:find("\\", 1, true) then
            tex:SetTexture(name)
        else
            tex:SetTexture("Interface\\Icons\\" .. name)
        end
    else
        tex:SetTexture(FALLBACK_ICON)
    end
end

-- 圆角按钮的底与边 -------------------------------------------------------------
-- 描边：1px 圆角弧 + 上下左右补条（条用 SetColorTexture、角用 SetVertexColor 着色 —— 与
-- hui.SkinPopup 的 borderPieces 同一套写法）。
local function PaintEdge(r, c)
    r.edgeColor = c
    for _, t in ipairs(r.edgePieces or {}) do
        if t.__huiBorderStrip then
            t:SetColorTexture(c[1], c[2], c[3], 1)
        else
            t:SetVertexColor(c[1], c[2], c[3])
        end
        t:SetAlpha(1)
    end
end

-- 底色：圆角盘 + 补边，只调 alpha（色恒白，悬停靠底色变亮）。
local function PaintFill(r, a)
    for _, t in ipairs(r.fillPieces or {}) do t:SetAlpha(a) end
end

-- 单行截断 ---------------------------------------------------------------
-- UTF-8 按「字」切 —— 按字节切会切出半个汉字。
local function Chars(s)
    local out, i, n = {}, 1, #s
    while i <= n do
        local b = strbyte(s, i) or 0
        local len = 1
        if b >= 0xF0 then len = 4
        elseif b >= 0xE0 then len = 3
        elseif b >= 0xC0 then len = 2 end
        out[#out + 1] = strsub(s, i, i + len - 1)
        i = i + len
    end
    return out
end

-- 单字估宽：CJK ≈ 字号、其余 ≈ 0.55 字号。只用来决定截到第几个字，不追像素级。
local function CharW(ch, size)
    local b = strbyte(ch, 1) or 0
    if b >= 0xE0 then return size end
    if b >= 0xC0 then return size * 0.9 end
    return size * 0.55
end

local function EstW(text, size)
    local w = 0
    for _, ch in ipairs(Chars(text)) do w = w + CharW(ch, size) end
    return w
end

-- 单行装不下 → 按字截断补「…」（极窄时至少留 1 个字 + 省略号）。
local function Fit(text, maxw, size)
    if EstW(text, size) <= maxw then return text end
    local out, w = {}, 0
    local budget = maxw - size          -- 「…」按一个全角字宽预留
    for _, ch in ipairs(Chars(text)) do
        local cw = CharW(ch, size)
        if w + cw > budget then break end
        out[#out + 1] = ch
        w = w + cw
    end
    if #out == 0 and budget > 0 then
        out[1] = Chars(text)[1]
    end
    return table.concat(out) .. "…"
end

local NAME_W = QB.CW - QB.TEXT_PAD * 2
local NAME_W_ICON = QB.CW - QB.NAME_ICON_X - QB.TEXT_PAD

-- 条目名的可用宽：带图标的行要右移，别压到图标上。
local function NameW(hasIcon)
    if hasIcon then return NAME_W_ICON end
    return NAME_W
end

local function PlayerLevel()
    if type(UnitLevel) ~= "function" then return 0 end
    return UnitLevel("player") or 0
end

-- 条目：等级只进悬停提示（列表恒单行，用户 2026-09-30 定）
local function DungeonRow(d)
    return {
        text = d.name,
        tip = d.name .. "  " .. (d.nameEn or "") .. "\n"
            .. format(L["等级 %d-%d"], d.levelMin or 0, d.levelMax or 0)
            .. " · " .. (d.zone or L["位置未知"]),
        act = "dungeon",
        id = d.id,
    }
end

-- 条目清单：三个分组按「分组头 + 条目」铺平；关掉的分组整段不产出。
function QB:Collect()
    local cfg = ns.QuickCfg()
    local DG = ns.ProfHost and ns.ProfHost.DG
    local out = {}
    local n = { dungeon = 0, prof = 0, explore = 0 }

    -- 「全部副本」是整页入口：摆在「推荐五人本」分组头**上方**（2026-09-30 用户定）；
    -- 它跟着副本分组开关一起显隐（组关掉 → 整段撤下）。
    if cfg.groups.dungeon then
        out[#out + 1] = { text = L["全部副本"], act = "page", key = "Dungeons", gold = true }
        out[#out + 1] = { grp = L["推荐五人本"] }
        local lv = PlayerLevel()
        for _, d in ipairs((ns.DungeonData and ns.DungeonData.dungeons) or {}) do
            if DG and d.levelMin and DG.GroupOf(d, lv) == "rec" then
                out[#out + 1] = DungeonRow(d)
                n.dungeon = n.dungeon + 1
            end
        end
        if n.dungeon == 0 then
            out[#out + 1] = { text = L["当前等级暂无推荐副本"], dead = true }
        end
    end

    if cfg.groups.prof and ns.LoadForeverPages then
        out[#out + 1] = { grp = L["专业"] }
        local D = ns.ProfData
        local PD = ns.ProfModule
        local learned = (PD and PD.ProfLearned) and PD.ProfLearned() or {}
        for _, slug in ipairs((D and D.order) or {}) do
            local p = D.pro and D.pro[slug]
            local known = learned[slug]
            if p and (cfg.profMode == "all" or known) then
                local tip = p.name or slug
                if known then
                    tip = tip .. "\n" .. format(L["熟练度 %d/%d"], known.cur or 0, known.max or 0)
                else
                    tip = tip .. "\n" .. L["未学习"]
                end
                out[#out + 1] = {
                    text = p.name or slug,
                    icon = p.icon,
                    tip = tip,
                    act = "prof",
                    slug = slug,
                    known = known and true or false,
                }
                n.prof = n.prof + 1
            end
        end
        if n.prof == 0 then out[#out + 1] = { text = L["未学任何专业"], dead = true } end
    end

    if cfg.groups.explore and ns.LoadForeverPages then
        out[#out + 1] = { grp = L["探索"] }
        for _, e in ipairs(EXPLORE_DEFS) do
            if cfg.expl[e.key] then
                out[#out + 1] = { text = e.text, act = "explore", key = e.key }
                n.explore = n.explore + 1
            end
        end
        if n.explore == 0 then out[#out + 1] = { text = L["未选任何探索子页"], dead = true } end
    end

    self.counts = n
    return out
end

function QB:Scroll(delta)
    local sc = self.scroll
    if not sc then return end
    local maxS = math.max(0, (self.content:GetHeight() or 0) - (sc:GetHeight() or 0))
    local cur = sc:GetVerticalScroll() or 0
    sc:SetVerticalScroll(math.max(0, math.min(maxS, cur - (delta or 0) * 40)))
end

function QB:RowAt(i)
    local r = self.pool[i]
    if r then return r end
    r = CreateFrame("Button", nil, self.content)
    r:SetSize(self.CW, self.ROW_H)
    r:RegisterForClicks("LeftButtonUp")
    -- 圆角按钮：圆角底 + 1px 圆角描边（用户 2026-09-30：方角边框要倒圆角）
    r.fillPieces = ns.hui.BuildRoundedBG(r, self.RADIUS, { 1, 1, 1, self.FILL }, "both", false, nil, true)
    r.edgePieces = ns.hui.BuildRoundBorder(r, self.RADIUS, C_EDGE)
    PaintFill(r, self.FILL)
    PaintEdge(r, C_EDGE)

    -- 专业图标：单独一层帧，便于随条目一起 SetShown（wantIcon 分支）。
    -- ★ 2026-09-30 起 RoundIcon 的圆角蒙版改成按**贴图**尺寸裁（锚点从父帧挪到贴图），
    --   这层「等大帧」已不是必需 —— 保留只为和 TierUI 的 MakeIconTile 同构。
    r.iconTile = CreateFrame("Frame", nil, r)
    r.iconTile:SetSize(self.ICON, self.ICON)
    r.iconTile:SetPoint("LEFT", r, "LEFT", self.ICON_X, 0)
    r.icon = r.iconTile:CreateTexture(nil, "ARTWORK")
    r.icon:SetPoint("TOPLEFT", r.iconTile, "TOPLEFT", 0, 0)
    r.icon:SetPoint("BOTTOMRIGHT", r.iconTile, "BOTTOMRIGHT", 0, 0)
    -- 裁图：四边各内缩 7% 去掉素材自带的那圈边（全仓统一口径，与法术书图标同款）。
    -- ★ 必须在蒙版之前设好 UV —— 蒙版裁的是显示区域、UV 决定「显示哪一块」，两者互不干扰，
    --   但先定 UV 再挂蒙版可以避免中途一帧的「满幅图 + 圆角裁」闪烁。
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(r.icon) end
    r.iconTile:Hide()

    r.name = Fs(r, self.FS_NAME, C_TEXT)
    r.name:SetPoint("LEFT", r, "LEFT", self.TEXT_PAD, 0)
    r.name:SetWidth(NAME_W)
    r.name:SetHeight(self.FS_NAME)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)          -- 恒单行（超宽交给 Fit 截断）

    r:SetScript("OnEnter", function(self)
        PaintEdge(self, C_GOLD)
        PaintFill(self, QB.FILL_HOT)
        if self.spec and self.spec.tip then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(self.spec.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function(self)
        PaintEdge(self, C_EDGE)
        PaintFill(self, QB.FILL)
        GameTooltip:Hide()
    end)
    r:SetScript("OnClick", function(self) QB:Click(self.spec) end)
    -- 条目是 Button：不显式接滚轮，鼠标停在条目上就滚不动（实机典型症状）。
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", function(_, delta) QB:Scroll(delta) end)

    self.pool[i] = r
    return r
end

-- 吸附 -------------------------------------------------------------------
local function PopShown(pop)
    return (pop and pop.IsShown and pop:IsShown()) and true or false
end

-- 当前该落哪一档：占第一槽的弹窗（设置 / 装备过滤 / 地图设置）任一开着 → 让位；都关着 → 贴主窗右缘。
function QB:SlotX()
    if PopShown(ns.SettingsPopup) then return self.SLOT2 end
    local LF = ns.LootFilterUI
    if LF and LF.ConfigPopup and PopShown(LF:ConfigPopup()) then return self.SLOT2 end
    if ns.ExploreMapConfigPopup and PopShown(ns.ExploreMapConfigPopup()) then return self.SLOT2 end
    return self.SLOT1
end

-- 同一档重复调用是空操作（不动锚点、不累计 reskin）。
function QB:Reanchor(force)
    local f, host = self.frame, ns.MainFrame
    if not (f and host) then return end
    local x = self:SlotX()
    if not force and self.slotX == x then return end
    self.slotX = x
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", host, "TOPRIGHT", x, 0)
    f:SetPoint("BOTTOMLEFT", host, "BOTTOMRIGHT", x, 0)
end

-- 占第一槽的弹窗显隐 → 立刻挪位（不再需要关掉主窗重开）。
function QB:HookSettings()
    self.hookedPops = self.hookedPops or {}
    local function hook(pop)
        if not (pop and pop.HookScript) or self.hookedPops[pop] then return end
        self.hookedPops[pop] = true
        pop:HookScript("OnShow", function() if QB.built then QB:Reanchor() end end)
        pop:HookScript("OnHide", function() if QB.built then QB:Reanchor() end end)
    end
    hook(ns.SettingsPopup)
    local LF = ns.LootFilterUI
    if LF and LF.ConfigPopup then hook(LF:ConfigPopup()) end
    -- 地图设置面板懒建：建好时（已存在则直接钩）补挂显隐钩
    if ns.ExploreMapConfigPopup then hook(ns.ExploreMapConfigPopup()) end
end

function QB:Ensure()
    if self.built then return self end
    local host = ns.MainFrame
    if not host then return nil end

    local f = CreateFrame("Frame", "DungeonsForever_QuickBar", host, "BackdropTemplate")
    f:SetWidth(self.W)
    f:SetFrameLevel(512)
    f:EnableMouse(true)
    f:SetScript("OnMouseWheel", function() end)
    if ns.hui and ns.hui.SkinPopup then ns.hui.SkinPopup(f, 8) end
    self.frame = f

    local head = Fs(f, self.FS_HEAD, C_WHITE)
    head:SetText(L["5人本专业探索"])
    head:SetPoint("TOPLEFT", f, "TOPLEFT", self.PAD, self.HEAD_Y)

    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetPoint("TOPLEFT", f, "TOPLEFT", self.PAD, self.BODY_Y + 6)
    line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -self.PAD, self.BODY_Y + 6)
    line:SetHeight(1)

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", self.PAD, self.BODY_Y)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -self.PAD, 10)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) QB:Scroll(delta) end)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(self.CW)
    content:SetHeight(10)
    scroll:SetScrollChild(content)
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", function(_, delta) QB:Scroll(delta) end)

    -- 主窗显示 → 重算一次（面板是主窗子帧，显示本身不用我们管；这里只管内容新鲜度）。
    if host.HookScript then
        host:HookScript("OnShow", function() if QB.built then QB:Apply() end end)
    end

    self.scroll, self.content = scroll, content
    self.pool, self.grpPool = {}, {}
    self.built = true
    self:HookSettings()
    self:Reanchor(true)
    return self
end

function QB:Render()
    if not self.built then return end
    self:HookSettings()
    self:Reanchor()
    local specs = self:Collect()
    self.specs = specs

    local y, nRow, nGrp = -2, 0, 0
    for _, sp in ipairs(specs) do
        if sp.grp then
            nGrp = nGrp + 1
            local fs = self.grpPool[nGrp]
            if not fs then
                fs = Fs(self.content, self.FS_GRP, C_DIM)
                fs:SetJustifyH("LEFT")
                self.grpPool[nGrp] = fs
            end
            fs:SetText(sp.grp)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", self.content, "TOPLEFT", self.TEXT_PAD, y - 4)
            fs:Show()
            y = y - self.GRP_H
        else
            nRow = nRow + 1
            local r = self:RowAt(nRow)
            local wantIcon = sp.icon and true or false
            r.spec = sp
            -- 图标位只对有图标的行开；开关切换时才动锚点（同档重复调用是空操作）。
            if r.hasIcon ~= wantIcon then
                r.hasIcon = wantIcon
                r.iconTile:SetShown(wantIcon)
                r.name:ClearAllPoints()
                r.name:SetPoint("LEFT", r, "LEFT",
                    wantIcon and self.NAME_ICON_X or self.TEXT_PAD, 0)
            end
            if wantIcon then SetIcon(r.icon, sp.icon) end
            r.name:SetText(Fit(sp.text, NameW(wantIcon), self.FS_NAME))
            if sp.dead then
                r.name:SetTextColor(C_DIM[1], C_DIM[2], C_DIM[3])
            elseif sp.gold then
                r.name:SetTextColor(C_GOLD[1], C_GOLD[2], C_GOLD[3])
            elseif sp.known then
                r.name:SetTextColor(Accent())
            else
                r.name:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3])
            end
            r:SetHeight(self.ROW_H)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, y)
            r:Show()
            y = y - self.ROW_H - self.GAP
        end
    end
    for i = nRow + 1, #self.pool do self.pool[i]:Hide() end
    for i = nGrp + 1, #self.grpPool do self.grpPool[i]:Hide() end
    self.content:SetHeight(math.max(10, -y + 6))
    self.rows, self.groups = nRow, nGrp
end

function QB:Click(spec)
    if type(spec) ~= "table" or spec.dead then return end
    ns.PlaySound(1)
    if spec.act == "dungeon" then
        if ns.ShowDungeonDetail then ns.ShowDungeonDetail(spec.id) end
    elseif spec.act == "prof" then
        ns.OpenPage("Professions")
        if ns.ProfModule and ns.ProfModule.Show then ns.ProfModule.Show(spec.slug) end
    elseif spec.act == "explore" then
        ns.OpenPage("Explore")
        if ns.ExploreModule and ns.ExploreModule.ShowSub then
            ns.ExploreModule.ShowSub(spec.key)
        end
    elseif spec.act == "page" then
        ns.OpenPage(spec.key)
    end
end

-- 显隐与刷新 ---------------------------------------------------------------
function QB:Apply()
    local cfg = ns.QuickCfg()
    if not cfg.on then
        if self.frame then self.frame:Hide() end
        return
    end
    if not self.built and not self:Ensure() then return end
    self:HookSettings()
    self:Reanchor()
    self:Render()
    self.frame:Show()
end

-- 启动即建：登录时就把面板建好（子帧随主窗显隐），不等主窗第一次 OnShow。
function QB:Boot()
    if not ns.QuickCfg().on then return end
    if not self:Ensure() then return end
    self.frame:Show()
    local host = ns.MainFrame
    if host and host.IsShown and host:IsShown() then self:Render() end
end

function QB:OnMainShow()
    self:Apply()
end

-- 设置面板分组（挂主窗的「设置」弹窗，不另开窗口） --------------------------
local SET_PAD, SET_ROW_H, SET_HDR_H = 14, 24, 22

local function Toggle(parent)
    local tg = CreateFrame("CheckButton", nil, parent)
    tg:SetSize(36, 20)
    tg:EnableMouse(true)
    if ns.hui and ns.hui.ReskinToggle then ns.hui.ReskinToggle(tg) end
    tg.label = Fs(parent, 14, C_TEXT)
    tg.label:SetJustifyH("RIGHT")
    tg.label:SetPoint("RIGHT", tg, "LEFT", -6, 0)
    return tg
end

local function Chip(parent, text, w, h)
    local bt = CreateFrame("Button", nil, parent, "BackdropTemplate")
    bt:SetSize(w, h)
    local H = ns.ProfHost
    if H and H.MakeOutline then H.MakeOutline(bt, 1, 0.82, 0) end
    bt.label = Fs(bt, 14, C_TEXT)
    bt.label:SetText(text)
    bt.label:SetPoint("CENTER", bt, "CENTER", 0, 0)
    return bt
end

local function PaintChip(bt, on)
    Outline(bt, on)
    local c = on and C_GOLD or C_DIM
    bt.label:SetTextColor(c[1], c[2], c[3])
end

function QB:EnsureSettings()
    if self.setBuilt then return true end
    local pop = ns.SettingsPopup
    if not pop then return false end

    local set = { group = {}, expl = {} }
    local y = -44

    local function Header(text)
        local fs = Fs(pop, self.FS_AUX, C_DIM)
        fs:SetPoint("TOPLEFT", pop, "TOPLEFT", SET_PAD, y)
        fs:SetText(text)
        y = y - SET_HDR_H
    end

    local function ToggleRow(label, isOn, setOn)
        local tg = Toggle(pop)
        tg:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -SET_PAD, y)
        tg.label:SetText(label)
        tg:SetChecked(isOn() and true or false)
        tg:SetScript("OnClick", function(self)
            ns.PlaySound(1)
            setOn(not isOn())
            self:SetChecked(isOn() and true or false)
            QB:SyncSettings()
            QB:Apply()
        end)
        y = y - SET_ROW_H
        return tg
    end

    Header(L["快捷按钮栏"])
    set.on = ToggleRow(L["显示快捷按钮栏"],
        function() return ns.QuickCfg().on end,
        function(v) ns.QuickCfg().on = v end)

    Header(L["显示分组"])
    for _, def in ipairs({
        { key = "dungeon", label = L["推荐五人本"] },
        { key = "prof",    label = L["专业"] },
        { key = "explore", label = L["探索"] },
    }) do
        if ns.LoadForeverPages or def.key == "dungeon" then
            local key = def.key
            set.group[key] = ToggleRow(def.label,
                function() return ns.QuickCfg().groups[key] end,
                function(v) ns.QuickCfg().groups[key] = v end)
        end
    end

    Header(L["专业列表"])
    do
        local learned = Chip(pop, L["只看已学"], 68, 22)
        local all = Chip(pop, L["全部"], 68, 22)
        learned:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -SET_PAD, y)
        all:SetPoint("RIGHT", learned, "LEFT", -6, 0)
        set.chipLearned, set.chipAll = learned, all
        learned:SetScript("OnClick", function()
            ns.PlaySound(1)
            ns.QuickCfg().profMode = "learned"
            QB:SyncSettings()
            QB:Apply()
        end)
        all:SetScript("OnClick", function()
            ns.PlaySound(1)
            ns.QuickCfg().profMode = "all"
            QB:SyncSettings()
            QB:Apply()
        end)
        y = y - SET_ROW_H
    end

    Header(L["探索子页"])
    for _, def in ipairs(EXPLORE_DEFS) do
        local key = def.key
        set.expl[key] = ToggleRow(def.text,
            function() return ns.QuickCfg().expl[key] end,
            function(v) ns.QuickCfg().expl[key] = v end)
    end

    self.set, self.setBuilt = set, true
    return true
end

function QB:SyncSettings()
    if not self:EnsureSettings() then return end
    local cfg = ns.QuickCfg()
    local set = self.set

    local function Gate(tg)
        if cfg.on then tg:Enable() else tg:Disable() end
    end

    set.on:SetChecked(cfg.on and true or false)
    for k, tg in pairs(set.group) do
        tg:SetChecked(cfg.groups[k] and true or false)
        Gate(tg)
    end
    for k, tg in pairs(set.expl) do
        tg:SetChecked(cfg.expl[k] and true or false)
        Gate(tg)
    end
    PaintChip(set.chipLearned, cfg.profMode ~= "all")
    PaintChip(set.chipAll, cfg.profMode == "all")
end

ns.Init(function()
    -- ① 登录就把面板建出来（子帧随主窗自动显隐，不再依赖钩子时序）
    QB:Boot()

    -- ② 等级 / 专业变动 → 重算推荐列表
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LEVEL_UP")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("SKILL_LINES_CHANGED")
    ev:SetScript("OnEvent", function()
        if QB.built then QB:Render() end
        -- 兜底：主窗已经开着但面板还没建（或钩子没跑到）→ 在这里补建一次，
        -- 免得「打开主窗看不到快捷栏、关掉重开才出来」。
        local mf = ns.MainFrame
        if mf and mf.IsShown and mf:IsShown() and not QB.built then QB:Boot() end
    end)
    QB.events = ev
end)
