-- =============================================================================
-- DungeonsForever · 专业页（界面层 · 手写骨架件）
--
-- ★ 本文件**不是生成物**，可以直接改（同 Core/Hui.lua 的定位）。
--   数据来自 Core/Data/Data_Prof*.lua（由 _temp/fc_gen.py 生成，勿手改）；
--   本文件只负责把那些表画出来，一个数据字段都不写死。
--
-- ★★ 只对无限服（1.60.x）加载：营地系统 / 传承特权 / 1→300 路线都是无限服 1.60.1
--    的规则，泰坦 3.80.2 端没有这些物品与专业 —— 加载了只会画出一堆查不到的空名字。
--    判定用 ns.IsForever（Core.lua）。泰坦端本文件整体 return，U.profPage 恒为 nil，
--    顶栏也不加「专业」胶囊（见 _temp/port_dungeonsforever.py 的 PROFESSION_PATCHES）。
--
-- ★ 为什么单独一个文件而不是塞进 Core/DungeonUI.lua：
--   DungeonUI.lua 由 _temp/port_dungeonsforever.py 从上游按**硬编码行号**抽取生成，
--   在里面写业务代码会让每次迭代都去动生成链；那里只留 4 处小补丁当挂钩
--   （ns.ProfHost 基建交接 / 顶栏胶囊 defs / SwitchSub 分流 / Build 建页）。
--
-- ★★ 帧数纪律（与副本页同款，harness 有对应断言）：
--   · 页骨架（左导航 / 子页签 / 工具条 / 滚动容器 / 行池 / 材料芯片池 / 详情条）
--     一律在 PD.Build() 里**一次建好** —— 切到本页、切专业、切子页签都**不得新建帧**；
--     PD.Build 由 U:Build() 调用（首屏），故「切专业零新建帧」成立。
--   · 行池按需生长（沿副本页做法），但设 PD.ROW_CAP 封顶，并在封顶处明说「还有 N 条」——
--     宁可提示用分类缩小范围，也不让一次「全部」把帧数顶到几千（最大 512 条）。
--   · 一切「显示/隐藏」都走 SetShown，绝不 SetParent(nil)、绝不重建 scroll child
--     （ScrollFrame 内部持有旧 child 指针，卸载会 ACCESS_VIOLATION，副本页踩过）。
--
-- ★ 物品名 / 图标 / 品质**只从客户端取**（数据表只存 ID，中文名由客户端给）。
--   客户端还没懒加载到时显示占位，并挂几次重扫（PD.ScheduleSweep）自动补上。
--
-- ★ 表字段序的唯一说明在 Core/Data/Data_Prof*.lua 的头注释里（由 fc_gen.py 写）。
--   本文件按位置取值（如 r[12] = 材料），改字段序必须同步改这里。
-- =============================================================================

local _, ns = ...

if not ns.LoadForeverPages then return end

local L = ns.L

local Host = ns.ProfHost
if not Host then return end

local DG = Host.DG
local MakeFS, NewButton = Host.MakeFS, Host.NewButton
local MakeOutline = Host.MakeOutline
local SetOutline, Unpack = Host.SetOutline, Host.Unpack
local C_GOLD, C_GREY = Host.C_GOLD, Host.C_GREY
local C_DIM, C_WHITE, C_TEXT = Host.C_DIM, Host.C_WHITE, Host.C_TEXT
local CONTENT_W = Host.CONTENT_W
local PAGE_INSET, ROW_CLASS = Host.PAGE_INSET, Host.ROW_CLASS
local FALLBACK_ICON = Host.FALLBACK_ICON

local D  = ns.ProfData
local R  = ns.ProfRecipes
local LV = ns.ProfLeveling
local GA = ns.ProfGathering

local PD = {}
ns.ProfModule = PD

PD.NAV_X, PD.NAV_TOP = PAGE_INSET, ROW_CLASS
PD.NAV_W = ((type(GetLocale) == "function") and GetLocale() == "enUS") and 184 or 148
PD.NAV_FS, PD.NAV_ICON = 16, 20
PD.NAV_ITEM_H, PD.NAV_GROUP_H, PD.NAV_GAP = 26, 22, 3
PD.NAV_LV_FS = 14
PD.RIGHT_X = PD.NAV_X + PD.NAV_W + 10
PD.RIGHT_W = CONTENT_W - PD.RIGHT_X - PAGE_INSET
PD.SUB_Y, PD.SUB_H, PD.SUB_W, PD.SUB_STEP = ROW_CLASS, 22, 70, 74
PD.BODY_TOP = PD.SUB_Y + PD.SUB_H + 10
PD.BODY_BOT = PAGE_INSET + 26
PD.TOOL_H, PD.TOOL_GAP, PD.TOOL_W = 22, 4, 72
PD.TOOL_BODY_GAP = 8
PD.ROW_H, PD.ROW_H1, PD.TEXT_H = 34, 24, 20

PD.SETTING_DEF = { greyPassed = true, hlCurrent = true }
PD.SETTING_TOG_MAX = 4
local function ProfDB()
    DungeonsForeverDB = DungeonsForeverDB or {}
    DungeonsForeverDB.prof = DungeonsForeverDB.prof or {}
    return DungeonsForeverDB.prof
end
function PD.Setting(k)
    local v = ProfDB()[k]
    if v == nil then return PD.SETTING_DEF[k] and true or false end
    return v and true or false
end

PD.LIST_PAD = 5
PD.COL_GAP = 12
local LV_SPLIT = ((type(GetLocale) == "function") and GetLocale() == "enUS") and 0.75 or 0.80
PD.COL_LW = math.floor((PD.RIGHT_W - 2 * PD.LIST_PAD - PD.COL_GAP) * LV_SPLIT)
PD.COL_RW = PD.RIGHT_W - 2 * PD.LIST_PAD - PD.COL_GAP - PD.COL_LW

PD.OV_SPLIT = 0.62
PD.SEC_CARD_MAX = 8
PD.SEC_PAD = 4
PD.SEC_GAP = 8
PD.OV_GUT = PD.SEC_GAP + 2 * PD.SEC_PAD

PD.GRID_LW = math.floor((PD.RIGHT_W - 2 * PD.LIST_PAD - PD.COL_GAP) / 2)
PD.GRID_RW = PD.RIGHT_W - 2 * PD.LIST_PAD - PD.COL_GAP - PD.GRID_LW

PD.IX_COLS = 3
PD.IX_GAP = 8
PD.IX_COLW = math.floor((PD.RIGHT_W - 2 * PD.LIST_PAD - (PD.IX_COLS - 1) * PD.IX_GAP) / PD.IX_COLS)
PD.IX_CARD_H = 38
PD.IX_ICON = 24
PD.IX_HEAD_H = 18
PD.IX_ROWW_GAP = 6
PD.IX_GROUP_GAP = 10

PD.MAT_FS = 13
PD.MAT_ICON_PX = 16
PD.MAT_ROW_W = PD.RIGHT_W - 2 * PD.LIST_PAD
PD.MAT_RIGHT_RESERVE = 132
PD.MAT_X = math.floor(PD.MAT_ROW_W * 0.40)
PD.MAT_W = PD.MAT_ROW_W - PD.MAT_RIGHT_RESERVE - PD.MAT_X - 8

PD.LV_FS = 13
PD.TBL_ICON = 24
PD.TBL_H = 42
PD.TBL_RNG_GAP = 12
PD.TBL_NAME_GAP = 8
PD.TBL_MAT_CNT_FS = 14
PD.TBL_BLK_GAP = 8
PD.TBL_MAT_RPAD = 6
PD.TBL_CNT_GAP = 8
PD.TBL_MARK_W = 16
PD.TBL_NAME_MIN, PD.TBL_NAME_MAX = 88, 150
PD.TBL_BLK_MAX = 5
PD.TBL_NAME_DY, PD.TBL_SRC_DY = 7, -8
PD.TBL_MAT_CNT_DY = -8
PD.ZEBRA_A = 0.045
PD.LV_ICON_X = 6 + 71 + PD.TBL_RNG_GAP
PD.LV_NAME_X = PD.LV_ICON_X + PD.TBL_ICON + PD.TBL_NAME_GAP
PD.LV_CNT_W = 78
PD.LV_CNT_R = PD.TBL_MAT_RPAD + 240 + PD.TBL_CNT_GAP
PD.LV_NAME_W = PD.TBL_NAME_MIN
PD.LV_MAT_W = 240

PD.ROW_CAP = 300
PD.TOOL_MAX = 20

PD.TEXT_W = PD.RIGHT_W - 46

DG.PROF_SUBTABS = {
    { key = "overview", text = L["总览"] },
    { key = "camp",     text = L["营地"] },
    { key = "recipe",   text = L["配方"] },
    { key = "gather",   text = L["采集"] },
    { key = "leveling", text = L["升级"] },
    { key = "legacy",   text = L["传承"] },
    { key = "notes",    text = L["说明"] },
}

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

DG.ZoneName = function(id)
    if type(id) ~= "number" then return L["无数据"] end
    local m = C_Map
    local fn = m and m.GetAreaInfo
    if type(fn) == "function" then
        local ok, nm = pcall(fn, id)
        if ok and type(nm) == "string" and nm ~= "" then return nm end
    end
    return format(L["区域 #%d"], id)
end

local qname = {}
function PD.QuestName(id)
    if not id then return L["任务 #?"] end
    local c = qname[id]
    if c ~= nil then return c end
    local nm
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, t = pcall(C_QuestLog.GetTitleForQuestID, id)
        if ok and type(t) == "string" and t ~= "" then nm = t end
    end
    if type(nm) ~= "string" or nm == "" then nm = format(L["任务 #%d"], id) end
    qname[id] = nm
    return nm
end

-- ★ UTF-8 估宽 / 按「字」截断已上移 Hui.lua（ns.hui，双端通用，2026-10-03）——
--   副本掉落页的名称截断在泰坦端也要用，而本文件只对无限端加载。
--   这里留委托 + CharStep 别名（下面的 PD.Wrap 还在用）。
local CharStep = ns.hui.CharStep

PD.TextW = function(text, fs) return ns.hui.TextW(text, fs) end

PD.Fit = function(text, fs, width) return ns.hui.Fit(text, fs, width) end

PD.Wrap = function(text, fs, width)
    local out = {}
    if type(text) ~= "string" or text == "" or not width then return out end
    local i, n = 1, #text
    local line, w = "", 0
    while i <= n do
        local ch, step, k = CharStep(text, i)
        local cw = k * fs
        if w + cw > width and line ~= "" then
            out[#out + 1] = line
            line, w = "", 0
        end
        line = line .. ch
        w = w + cw
        i = i + step
    end
    if line ~= "" then out[#out + 1] = line end
    return out
end

PD.TIER_HEX = { "|cffffd100", "|cff40d940", "|cff8c8c8c" }
PD.TierText = function(a, b, c)
    return format("%s%s|r/%s%s|r/%s%s|r",
                  PD.TIER_HEX[1], tostring(a),
                  PD.TIER_HEX[2], tostring(b),
                  PD.TIER_HEX[3], tostring(c))
end

local function ColTextW(col)
    if col == 2 then
        if PD.gridSplit then return PD.GRID_RW end
        if PD.lvSplit then return PD.splitRW or PD.COL_RW end
        return PD.COL_RW
    end
    if col == 1 then
        if PD.gridSplit then return PD.GRID_LW end
        if PD.lvSplit then return PD.splitLW or PD.COL_LW end
        return PD.COL_LW
    end
    return PD.TEXT_W
end

local function PushText(rows, text, fs, color, col)
    for _, ln in ipairs(PD.Wrap(text, fs or 12, ColTextW(col))) do
        rows[#rows + 1] = { kind = "text", text = ln, fs = fs or 12, color = color, col = col }
    end
end

local function PushHead(rows, text, col, fs)
    rows[#rows + 1] = { kind = "head", text = text, col = col, fs = fs }
end

local function PushGap(rows, h, col)
    rows[#rows + 1] = { kind = "gap", h = h or 8, col = col }
end

PD.cur = nil
PD.tab = "overview"
PD.campView = "a"
PD.toolKey = nil
PD.perkOpen = {}
PD.rows, PD.toolBtns = {}, {}
PD.specs = nil

function PD.SetRowHover(r, on)
    on = on and true or false
    r.__hlOn = on
    if on then
        r:SetBackdropColor(1, 1, 1, DG.LOOT_CARD_BG_HOVER)
        r:SetBackdropBorderColor(1, 1, 1, DG.LOOT_CARD_EDGE_HOVER)
    elseif r.__z then
        r:SetBackdropColor(1, 1, 1, PD.ZEBRA_A)
        r:SetBackdropBorderColor(1, 1, 1, 0)
    else
        r:SetBackdropColor(1, 1, 1, 0)
        r:SetBackdropBorderColor(1, 1, 1, 0)
    end
end

function PD.SyncHover()
    for i = 1, #PD.rows do
        local r = PD.rows[i]
        local over = (r.IsMouseOver and r:IsMouseOver()) and true or false
        if over ~= r.__hlOn then PD.SetRowHover(r, over) end
    end
    if PD.ixRoot and PD.ixRoot:IsVisible() then
        for i = 1, #(PD.ixCards or {}) do
            local c = PD.ixCards[i]
            local over = (c.IsMouseOver and c:IsMouseOver()) and true or false
            if over ~= c.__hlOn then PD.SetCardHover(c, over) end
        end
    end
end

function PD.Row(i)
    local r = PD.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, PD.child, "BackdropTemplate")
    r:SetWidth(PD.RIGHT_W)
    r:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    r.__hlOn = false
    PD.SetRowHover(r, false)
    r:EnableMouse(true)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(r.icon) end
    r.blk = {}
    r.a = MakeFS(r, 13, C_TEXT, "LEFT")
    r.b = MakeFS(r, 11, C_GREY, "LEFT")
    r.c = MakeFS(r, 12, C_GOLD, "RIGHT")
    r.d = MakeFS(r, 11, C_GREY, "RIGHT")
    r.e = MakeFS(r, 13, C_GOLD, "LEFT")
    r.f = MakeFS(r, PD.MAT_FS, C_TEXT, "LEFT")
    for _, f in ipairs({ r.a, r.b, r.c, r.d, r.e, r.f }) do f:SetWordWrap(false) end
    r.mark = r:CreateTexture(nil, "OVERLAY")
    r.mark:SetWidth(2)
    r.mark:SetColorTexture(0.42, 0.94, 0.62, 1)
    r.sep = r:CreateTexture(nil, "BACKGROUND")
    r.sep:SetHeight(1)
    r.sep:SetColorTexture(1, 1, 1, 0.055)
    r.bT = r:CreateTexture(nil, "BORDER")
    r.bT:SetHeight(1)
    r.bT:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.bT:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
    r.bB = r:CreateTexture(nil, "BORDER")
    r.bB:SetHeight(1)
    r.bB:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    r.bB:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    r.bL = r:CreateTexture(nil, "BORDER")
    r.bL:SetWidth(1)
    r.bL:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.bL:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    r.bR = r:CreateTexture(nil, "BORDER")
    r.bR:SetWidth(1)
    r.bR:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
    r.bR:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    r:SetScript("OnEnter", function(self)
        PD.SetRowHover(self, true)
        if self.__lines and (self.__linesFirst or not self.__it) then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            for _, ln in ipairs(self.__lines) do
                if ln[1] and ln[1] ~= "" then
                    GameTooltip:AddLine(ln[1], ln[2] or 1, ln[3] or 1, ln[4] or 1, true)
                end
            end
            GameTooltip:Show()
        elseif self.__it then
            DG.ShowItemTip(self, self.__it)
        end
    end)
    r:SetScript("OnLeave", function(self)
        PD.SetRowHover(self, false)
        GameTooltip:Hide()
    end)
    r:SetScript("OnClick", function(self, button)
        if button == "LeftButton" and self.__it
           and type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
            DG.ItemShiftClick(self, button)
            return
        end
        if self.__act then self.__act(self, button) end
        ns.PlaySound(1)
    end)
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", function(self, delta)
        DG.WheelScroll(PD.scroll, PD.child, delta)
    end)
    PD.rows[i] = r
    return r
end

function PD.RowHeight(spec)
    if spec.h then return spec.h end
    if spec.kind == "gap" then return 6 end
    if spec.kind == "text" or spec.kind == "head" then return PD.TEXT_H end
    return PD.ROW_H
end

function PD.PaintRows(rows)
    local y = { 0, 0 }
    local bb = {}
    local zc = { 0, 0 }
    local n = #rows
    local truncated = 0
    if n > PD.ROW_CAP then truncated = n - PD.ROW_CAP; n = PD.ROW_CAP end
    local grid = PD.gridSplit and true or false
    local ROW_W = PD.RIGHT_W - 2 * PD.LIST_PAD
    for i = 1, n do
        local spec = rows[i]
        local h = PD.RowHeight(spec)
        local r = PD.Row(i)
        if spec.sec then
            local nxt
            for j = i + 1, n do
                local s2 = rows[j]
                if s2.kind ~= "gap" then nxt = s2 break end
            end
            spec._lastInSec = not (nxt and nxt.sec == spec.sec)
        end
        local span = (grid and spec.kind ~= "row") or spec.span == true
        if spec.kind == "gap" then
            r:Hide()
            if span then
                local ny = math.max(y[1], y[2]) + h
                y[1], y[2] = ny, ny
            else
                local col = (spec.col == 2) and 2 or 1
                y[col] = y[col] + h
            end
        else
            local col, x, w, top
            if span then
                top = math.max(y[1], y[2])
                x, w = PD.LIST_PAD, ROW_W
            else
                if spec.col == 2 then
                    col = 2
                elseif grid then
                    col = (y[2] < y[1]) and 2 or 1
                else
                    col = 1
                end
                top = y[col]
                if PD.lvSplit then
                    local lw = PD.splitLW or PD.COL_LW
                    local rw = PD.splitRW or PD.COL_RW
                    x = (col == 2) and (PD.LIST_PAD + lw + PD.OV_GUT) or PD.LIST_PAD
                    w = (col == 2) and rw or lw
                elseif grid then
                    x = (col == 2) and (PD.LIST_PAD + PD.GRID_LW + PD.COL_GAP) or PD.LIST_PAD
                    w = (col == 2) and PD.GRID_RW or PD.GRID_LW
                else
                    x, w = PD.LIST_PAD, ROW_W
                end
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", PD.child, "TOPLEFT", x, -top)
            r:SetSize(w, h)
            r:Show()
            if spec.kind == "row" and col and not spec.sec then
                zc[col] = zc[col] + 1
                spec.z = (zc[col] % 2 == 0)
            else
                spec.z = nil
            end
            PD.BindRow(r, spec, h)
            if spec.sec then
                local b = bb[spec.sec]
                if not b then
                    bb[spec.sec] = { x0 = x, y0 = top, x1 = x + w, y1 = top + h }
                else
                    b.x0 = math.min(b.x0, x)
                    b.y0 = math.min(b.y0, top)
                    b.x1 = math.max(b.x1, x + w)
                    b.y1 = math.max(b.y1, top + h)
                end
            end
            if span then
                y[1], y[2] = top + h + 2, top + h + 2
            else
                y[col] = top + h + 2
            end
        end
    end
    for i = n + 1, #PD.rows do PD.rows[i]:Hide() end
    if PD.hasSecs and PD.secCards then
        local ci = 0
        for s = 1, (PD.secCount or 0) do
            local b = bb[s]
            if b then
                ci = ci + 1
                local c = PD.secCards[ci]
                if c then
                    c:ClearAllPoints()
                    c:SetPoint("TOPLEFT", PD.child, "TOPLEFT",
                               b.x0 - PD.SEC_PAD, -(b.y0 - PD.SEC_PAD))
                    c:SetSize((b.x1 - b.x0) + 2 * PD.SEC_PAD,
                              (b.y1 - b.y0) + 2 * PD.SEC_PAD)
                    c:Show()
                end
            end
        end
        for i = ci + 1, #PD.secCards do PD.secCards[i]:Hide() end
    elseif PD.secCards then
        for i = 1, #PD.secCards do PD.secCards[i]:Hide() end
    end
    local h1 = y[1]
    if PD.wantIndexGrid and PD.ixRoot then
        PD.placeIndexGrid(h1)
        h1 = h1 + (PD.ixGridH or 0) + 8
    elseif PD.ixRoot then
        PD.ixRoot:Hide()
    end
    if PD.wantBonusTable and PD.bonusTable then
        PD.placeBonusTable(h1)
        if PD.bonusTitleNote then
            PD.bonusTitleNote:ClearAllPoints()
            PD.bonusTitleNote:SetPoint("TOPRIGHT", PD.child, "TOPRIGHT",
                                       -PD.LIST_PAD, -(h1 - 19))
            PD.bonusTitleNote:Show()
        end
        h1 = h1 + (PD.bonusTableH or 0) + 8
    elseif PD.bonusTable then
        if PD.bonusTitleNote then PD.bonusTitleNote:Hide() end
        PD.bonusTable:Hide()
    end
    PD.child:SetHeight(math.max(h1, y[2]) + 10)
    return truncated
end

function PD.RowBorder(r, on)
    local show = on and true or false
    r.bT:SetShown(show)
    r.bB:SetShown(show)
    r.bL:SetShown(show)
    r.bR:SetShown(show)
    if not show then return end
    local cr, cg, cb = PD.NavAccent()
    r.bT:SetColorTexture(cr, cg, cb, 0.95)
    r.bB:SetColorTexture(cr, cg, cb, 0.95)
    r.bL:SetColorTexture(cr, cg, cb, 0.95)
    r.bR:SetColorTexture(cr, cg, cb, 0.95)
end

function PD.BindRow(r, spec, h)
    r.__z = spec.z and true or false
    PD.SetRowHover(r, r.IsMouseOver and r:IsMouseOver())
    r.__it = spec.it
    r.__lines = spec.lines
    r.__linesFirst = spec.linesFirst
    r.__act = spec.act
    r.__named = false
    do
        local wantFs = spec.fs or 13
        local _, curFs = r.a:GetFont()
        if curFs ~= wantFs then
            r.a:SetFont(ns.FONT, wantFs,
                        ns.hui and ns.hui.FontFlags and ns.hui.FontFlags("OUTLINE") or "OUTLINE")
        end
    end
    PD.ClearMats(r)
    PD.RowBorder(r, spec.cur)

    local iconName = spec.icon
    local itemID = spec.it and spec.it[1]
    local showIcon = (spec.kind == "row") and (itemID or iconName) and true or false
    r.icon:SetShown(showIcon)
    if showIcon then
        r.icon:SetSize(20, 20)
        r.icon:ClearAllPoints()
        r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 6, -5)
        SetIcon(r.icon, iconName or DG.ItemIcon(itemID))
    end
    r.mark:SetShown(spec.is_new and true or false)
    if spec.is_new then
        r.mark:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -2)
        r.mark:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 2)
    end

    if spec.kind == "head" then
        r.a:SetTextColor(Unpack(C_WHITE))
        r.a:SetText(spec.text or "")
        r.a:ClearAllPoints()
        r.a:SetPoint("LEFT", r, "LEFT", 6, 0)
        r.b:SetText(""); r.c:SetText(""); r.d:SetText(""); r.e:SetText(""); r.f:SetText("")
        r.sep:Hide()
        return
    end
    if spec.kind == "text" then
        r.a:SetTextColor(Unpack(spec.color or C_TEXT))
        r.a:SetText(spec.text or "")
        r.a:ClearAllPoints()
        r.a:SetPoint("LEFT", r, "LEFT", 6, 0)
        r.b:SetText(""); r.c:SetText(""); r.d:SetText(""); r.e:SetText(""); r.f:SetText("")
        r.sep:Hide()
        return
    end
    r.sep:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    r.sep:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    if spec._lastInSec then r.sep:Hide() else r.sep:Show() end

    if spec.lvstep then
        if spec.passed then
            r.a:SetTextColor(Unpack(C_DIM))
            r.e:SetTextColor(Unpack(C_DIM))
            r.b:SetTextColor(Unpack(C_DIM))
            r.c:SetTextColor(Unpack(C_DIM))
        else
            r.a:SetTextColor(Unpack(C_TEXT))
            r.e:SetTextColor(Unpack(C_GOLD))
            r.b:SetTextColor(Unpack(C_GREY))
            r.c:SetTextColor(Unpack(C_GOLD))
        end
        r.a:SetText(spec.rng or "")
        r.e:SetText(spec.text or "")
        r.b:SetText(spec.src or "")
        r.c:SetText(spec.cnt or "")
        r.d:SetText("")
        r.f:SetText("")
        r.a:ClearAllPoints()
        r.a:SetPoint("LEFT", r, "LEFT", 6, 0)
        r.e:ClearAllPoints()
        r.e:SetPoint("LEFT", r, "LEFT", PD.LV_NAME_X, PD.TBL_NAME_DY)
        r.b:ClearAllPoints()
        r.b:SetPoint("LEFT", r, "LEFT", PD.LV_NAME_X, PD.TBL_SRC_DY)
        r.c:ClearAllPoints()
        r.c:SetPoint("RIGHT", r, "RIGHT", -PD.LV_CNT_R, 0)
        r.icon:SetSize(PD.TBL_ICON, PD.TBL_ICON)
        r.icon:ClearAllPoints()
        r.icon:SetPoint("LEFT", r, "LEFT", PD.LV_ICON_X, 0)
        r.icon:SetDesaturated(spec.passed and true or false)
        PD.PaintMats(r, spec.blocks, spec.matCut, spec.passed)
        return
    end

    local padL = showIcon and ((iconName and not itemID) and 28 or 32) or 6
    r.a:SetTextColor(Unpack(spec.nameColor or C_TEXT))
    r.a:SetText((spec.text or "") .. (spec.is_new and L[" |cff40d940新|r"] or ""))
    r.b:SetText(spec.sub or "")
    r.c:SetText(spec.right or "")
    r.c:SetTextColor(Unpack(spec.rightColor or C_GOLD))
    r.d:SetText(spec.right2 or "")
    r.e:SetText("")
    r.f:SetTextColor(Unpack(spec.matColor or C_TEXT))
    r.f:SetText(spec.mats or "")
    r.a:ClearAllPoints()
    r.c:ClearAllPoints()
    r.f:ClearAllPoints()
    if h <= PD.ROW_H1 then
        r.a:SetPoint("LEFT", r, "LEFT", padL, 0)
        r.b:SetText("")
        r.c:SetPoint("RIGHT", r, "RIGHT", -6, 0)
        r.d:SetText("")
        r.f:SetText("")
    else
        r.a:SetPoint("TOPLEFT", r, "TOPLEFT", padL, -4)
        r.b:ClearAllPoints()
        r.b:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", padL, 4)
        r.c:SetPoint("TOPRIGHT", r, "TOPRIGHT", -6, -4)
        r.d:ClearAllPoints()
        r.d:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -6, 4)
        r.f:SetPoint("LEFT", r, "LEFT", PD.MAT_X, 0)
    end
end

PD.BT_COL1 = 88
PD.BT_W_LAST = 236
PD.BT_H_HEAD = 28
PD.BT_LINE_H = 19
PD.BT_ROW_MIN = 34

function PD.BuildBonusTable(parent)
    local root = CreateFrame("Frame", nil, parent)
    PD.bonusTable = root
    root:SetSize(PD.RIGHT_W - 2 * PD.LIST_PAD, 10)
    local W = PD.RIGHT_W - 2 * PD.LIST_PAD
    PD.BT_COLW = math.floor((W - PD.BT_COL1 - PD.BT_W_LAST) / 3)

    local heads = { L["专业"], format(L["技能 %d"], 20), format(L["技能 %d"], 140),
                    format(L["技能 %d"], 300), L["职业版对照 / 其他功能"] }
    for j, txt in ipairs(heads) do
        local fs = MakeFS(root, 14, C_GOLD, "LEFT")
        local x = (j == 1) and 0 or (PD.BT_COL1 + (j - 2) * PD.BT_COLW)
        fs:SetPoint("TOPLEFT", root, "TOPLEFT", x, -5)
        fs:SetText(txt)
    end
    local tipBtn = CreateFrame("Button", nil, root)
    tipBtn:EnableMouse(true)
    tipBtn:SetSize(PD.BT_W_LAST - 6, PD.BT_H_HEAD - 2)
    tipBtn:SetPoint("TOPLEFT", root, "TOPLEFT", PD.BT_COL1 + 3 * PD.BT_COLW, -2)
    tipBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["职业版对照 / 其他功能"], 1, 0.82, 0)
        GameTooltip:AddLine(L["数值以 60 级为基准、随等级成长 —— 游戏内低等级看到的数字更小属正常缩放。"],
                            1, 1, 1, true)
        GameTooltip:Show()
    end)
    tipBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local rule = root:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetColorTexture(1, 0.75, 0.35, 0.35)
    rule:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -PD.BT_H_HEAD + 3)
    rule:SetPoint("RIGHT", root, "RIGHT", 0, 0)

    root.__rows = {}
    for k = 1, #(D.order or {}) do
        local r = CreateFrame("Button", nil, root)
        r:EnableMouse(true)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(r.icon) end
        r.icon:SetSize(15, 15)
        r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
        r.name = MakeFS(r, 14, C_TEXT, "LEFT")
        r.name:SetWordWrap(false)
        r.name:SetPoint("LEFT", r, "LEFT", 21, 0)
        r.cells = {}
        for j = 1, 3 do
            local fs = MakeFS(r, 14, C_TEXT, "LEFT")
            fs:SetWordWrap(true)
            fs:SetWidth(PD.BT_COLW - 6)
            fs:SetPoint("TOPLEFT", r, "TOPLEFT", PD.BT_COL1 + (j - 1) * PD.BT_COLW, -7)
            r.cells[j] = fs
        end
        local cx = PD.BT_COL1 + 3 * PD.BT_COLW
        r.cmp1 = MakeFS(r, 14, C_GREY, "LEFT")
        r.cmp1:SetWordWrap(true)
        r.cmp1:SetWidth(PD.BT_W_LAST - 10)
        r.cmp1:SetPoint("TOPLEFT", r, "TOPLEFT", cx, -7)
        r.cmp2 = MakeFS(r, 14, C_TEXT, "LEFT")
        r.cmp2:SetWordWrap(true)
        r.cmp2:SetWidth(PD.BT_W_LAST - 10)
        r.cmp2:SetPoint("TOPLEFT", r, "TOPLEFT", cx, -26)
        r.sep = r:CreateTexture(nil, "OVERLAY")
        r.sep:SetHeight(1)
        r.sep:SetColorTexture(1, 1, 1, 0.08)
        r.sep:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
        r.sep:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 1, 1, 0.04)
        r.hl:Hide()
        r:SetScript("OnEnter", function(self)
            self.hl:Show()
            if self.__lines and #self.__lines > 0 then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                for _, ln in ipairs(self.__lines) do
                    if ln[1] and ln[1] ~= "" then
                        GameTooltip:AddLine(ln[1], ln[2] or 1, ln[3] or 1, ln[4] or 1, true)
                    end
                end
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", function(self)
            self.hl:Hide()
            GameTooltip:Hide()
        end)
        root.__rows[k] = r
    end
    root:Hide()
end

local function btLines(fs, est)
    if fs.GetNumLines then
        local n = fs:GetNumLines()
        if type(n) == "number" and n > 0 then return n end
    end
    return est
end

function PD.FillBonusTable()
    local root = PD.bonusTable
    if not root then
        return
    end
    local used = 0
    local yCur = -PD.BT_H_HEAD
    local lastUsed = nil
    for _, slug in ipairs(D.order or {}) do
        local p = D.pro[slug]
        local camp = (p and p.camp) or {}
        local r = root.__rows[used + 1]
        if r and #camp > 0 then
            local t1, t2, t3, caps = {}, {}, {}, {}
            local buffTxt, cmpName = "", ""
            for _, c in ipairs(camp) do
                local lv = c[4] or 0
                local bucket, tag
                if lv == 20 then
                    bucket = t1
                elseif lv == 140 then
                    bucket = t2
                elseif lv == 300 then
                    bucket = t3
                elseif lv < 140 then
                    bucket, tag = t1, format("(%d)", lv)
                else
                    bucket, tag = t3, format("(%d)", lv)
                end
                bucket[#bucket + 1] = (c[2] or "?") .. (tag or "")
                if c[6] and c[6] ~= "" and buffTxt == "" then
                    buffTxt = c[6]
                    cmpName = c[9] or ""
                end
                if c[10] and c[10] ~= "" then caps[#caps + 1] = c[10] end
            end
            SetIcon(r.icon, p.icon)
            r.name:SetText(p.name or slug)
            r.cells[1]:SetText(table.concat(t1, "、"))
            r.cells[2]:SetText(table.concat(t2, "、"))
            r.cells[3]:SetText(table.concat(t3, "、"))
            if buffTxt ~= "" then
                r.cmp1:SetText(cmpName ~= "" and cmpName or L["营地增益"])
                r.cmp1:SetTextColor(Unpack(C_GREY))
                r.cmp2:SetText(format("|cff7fdc7f%s|r", buffTxt))
            elseif #caps > 0 then
                r.cmp1:SetText(L["功能"])
                r.cmp2:SetText(format("|cff7fdc7f%s|r", format(L["营火容量 %s"], table.concat(caps, "/"))))
            else
                r.cmp1:SetText(L["功能"])
                r.cmp2:SetText(format("|cff9a958a%s|r", camp[1][5] or ""))
            end
            local lines = {}
            for _, c in ipairs(camp) do
                lines[#lines + 1] = { c[2] or "?", 1, 0.82, 0 }
                if c[5] and c[5] ~= "" then
                    lines[#lines + 1] = { c[5], 0.88, 0.88, 0.88 }
                end
                if c[6] and c[6] ~= "" then
                    lines[#lines + 1] = { format(L["增益：%s"], c[6]), 0.5, 0.9, 0.5 }
                end
                if c[11] and #c[11] > 0 then
                    lines[#lines + 1] = { format(L["材料：%s"], PD.MatText(c[11])), 0.7, 0.7, 0.7 }
                end
                if c[12] and c[12][1] then
                    lines[#lines + 1] = { format(L["图纸：%s"], DG.ItemName(c[12][1])) }
                end
            end
            r.__lines = lines
            local plain = (r.cmp2:GetText():gsub("|cff%x%x%x%x%x%x", ""))
            plain = (plain:gsub("|r", ""))
            local need = btLines(r.cmp1, 1) + btLines(r.cmp2, #PD.Wrap(plain, 14, PD.BT_W_LAST - 10))
            for j = 1, 3 do
                local n = btLines(r.cells[j], #PD.Wrap(r.cells[j]:GetText(), 14, PD.BT_COLW - 6))
                if n > need then need = n end
            end
            local rowH = math.max(PD.BT_ROW_MIN, need * PD.BT_LINE_H + 10)
            r:SetPoint("TOPLEFT", root, "TOPLEFT", 0, yCur)
            r:SetSize(PD.RIGHT_W - 2 * PD.LIST_PAD, rowH)
            r.sep:Show()
            r:Show()
            yCur = yCur - rowH
            lastUsed = r
            used = used + 1
        elseif r then
            r:Hide()
        end
    end
    if lastUsed then lastUsed.sep:Hide() end
    PD.bonusTableH = -yCur
    root:SetHeight(PD.bonusTableH)
end

function PD.placeBonusTable(y)
    PD.FillBonusTable()
    PD.bonusTable:ClearAllPoints()
    PD.bonusTable:SetPoint("TOPLEFT", PD.child, "TOPLEFT", PD.LIST_PAD, -y)
    PD.bonusTable:Show()
end

local function ixCardSub(slug, p)
    if slug == "camping" then
        local n = 0
        for _, q in ipairs(D.order or {}) do
            local q2 = D.pro[q]
            if q2 and q2.camp then n = n + #q2.camp end
        end
        return format(L["物件 %d · 职业加成"], n)
    end
    if p.section == "gathering" then
        local g = GA and GA[slug]
        if slug == "skinning" then
            return format(L["档次 %d"], g and #g or 0)
        end
        return format(L["节点 %d"], g and #g or 0)
    end
    if slug == "fishing" then
        local g = GA and GA.fishing
        return format(L["区域 %d"], g and #g or 0)
    end
    return format(L["配方 %d 条"], p.recipes or 0)
end

local function ixGroupOf(p)
    if p.section == "crafting" then return 1 end
    if p.section == "gathering" then return 2 end
    if p.section == "camping" then return 4 end
    return 3
end

local IX_GROUP_LABELS

function PD.SetCardHover(c, on)
    on = on and true or false
    c.__hlOn = on
    if on then
        c:SetBackdropColor(1, 1, 1, DG.LOOT_CARD_BG_HOVER)
        c:SetBackdropBorderColor(1, 1, 1, DG.LOOT_CARD_EDGE_HOVER)
    else
        c:SetBackdropColor(1, 1, 1, DG.LOOT_CARD_BG)
        c:SetBackdropBorderColor(1, 1, 1, DG.LOOT_CARD_EDGE)
    end
end

function PD.BuildIndexGrid(parent)
    IX_GROUP_LABELS = {
        L["制造专业 —— 每个角色选两个主要专业"],
        L["采集专业 —— 为制造专业提供材料"],
        L["次要专业 —— 每个角色三个都能学"],
        L["营地系统"],
    }
    local w = PD.RIGHT_W - 2 * PD.LIST_PAD
    local root = CreateFrame("Frame", nil, parent)
    root:SetSize(w, 10)
    PD.ixRoot = root

    PD.ixHeads = {}
    for gi = 1, 4 do
        local fs = MakeFS(root, 12, C_GOLD, "LEFT")
        fs:SetText(IX_GROUP_LABELS[gi])
        PD.ixHeads[gi] = fs
    end

    PD.ixCards = {}
    local byGroup = { {}, {}, {}, {} }
    for _, slug in ipairs(D.order or {}) do
        local p = D.pro[slug]
        if p then
            local gi = ixGroupOf(p)
            local c = CreateFrame("Button", nil, root, "BackdropTemplate")
            c:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            PD.SetCardHover(c, false)
            c:EnableMouse(true)            c.icon = c:CreateTexture(nil, "ARTWORK")
            c.icon:SetSize(PD.IX_ICON, PD.IX_ICON)
            c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(c.icon) end
            c.icon:SetPoint("LEFT", c, "LEFT", 7, 0)
            SetIcon(c.icon, p.icon)
            c.name = MakeFS(c, 12, C_TEXT, "LEFT")
            c.name:SetWordWrap(false)
            c.name:SetPoint("TOPLEFT", c, "TOPLEFT", PD.IX_ICON + 13, -5)
            c.name:SetText(p.name or slug)
            c.sub = MakeFS(c, 10, C_GREY, "LEFT")
            c.sub:SetWordWrap(false)
            c.sub:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", PD.IX_ICON + 13, 4)
            c.sub:SetText(ixCardSub(slug, p))
            c:SetScript("OnEnter", function(self) PD.SetCardHover(self, true) end)
            c:SetScript("OnLeave", function(self) PD.SetCardHover(self, false) end)
            c:SetScript("OnClick", function(self)
                ns.PlaySound(1)
                if slug == "camping" then
                    PD.Show("camping")
                    PD.campView = "bonus"
                    PD.SetTab("camp")
                else
                    PD.Show(slug)
                end
            end)
            c:SetScript("OnMouseWheel", function(_, delta)
                DG.WheelScroll(PD.scroll, PD.child, delta)
            end)
            byGroup[gi][#byGroup[gi] + 1] = c
            PD.ixCards[#PD.ixCards + 1] = c
        end
    end

    PD.ixNote = MakeFS(root, 10, C_GREY, "CENTER")
    PD.ixNote:SetText(L["营地档位对照表 →「营地系统 → 职业加成」"])

    local y = 0
    for gi = 1, 4 do
        local head = PD.ixHeads[gi]
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        y = y + PD.IX_HEAD_H
        local cards = byGroup[gi]
        local rows = math.ceil(#cards / PD.IX_COLS)
        for k, c in ipairs(cards) do
            local row = math.floor((k - 1) / PD.IX_COLS)
            local col = (k - 1) % PD.IX_COLS
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", root, "TOPLEFT",
                       col * (PD.IX_COLW + PD.IX_GAP), -(y + row * (PD.IX_CARD_H + PD.IX_ROWW_GAP)))
            c:SetSize(PD.IX_COLW, PD.IX_CARD_H)
        end
        if gi == 4 then
            PD.ixNote:ClearAllPoints()
            PD.ixNote:SetPoint("LEFT", root, "LEFT",
                               PD.IX_COLW + PD.IX_GAP + 8, -(y + math.floor(PD.IX_CARD_H / 2)))
        end
        y = y + rows * PD.IX_CARD_H + (rows - 1) * PD.IX_ROWW_GAP + PD.IX_GROUP_GAP
    end
    PD.ixGridH = y
    root:SetHeight(y)
    root:Hide()
end

function PD.placeIndexGrid(y)
    PD.ixRoot:ClearAllPoints()
    PD.ixRoot:SetPoint("TOPLEFT", PD.child, "TOPLEFT", PD.LIST_PAD, -y)
    PD.ixRoot:SetHeight(PD.ixGridH or 10)
    PD.ixRoot:Show()
end

function PD.Build(page)
    if PD.built then return end
    PD.built = true
    PD.page = page
    PD.navKey = {}

    PD.nav = {}
    local navY = 0
    local function navEntry(key, text, icon)
        local bt = NewButton(page, text, PD.NAV_W, PD.NAV_ITEM_H, PD.NAV_FS)
        bt:SetPoint("TOPLEFT", page, "TOPLEFT", PD.NAV_X, -(PD.NAV_TOP + navY))
        local fs = bt:GetFontString()
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", bt, "LEFT", 5 + PD.NAV_ICON + 5, 0)
        fs:SetJustifyH("LEFT")
        MakeOutline(bt, 1, 0.82, 0)
        SetOutline(bt, false, 1, 0.82, 0)
        bt.__huiKeepTextColor = true
        bt.__name = text
        bt.__icon = bt:CreateTexture(nil, "ARTWORK")
        bt.__icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(bt.__icon) end
        bt.__icon:SetSize(PD.NAV_ICON, PD.NAV_ICON)
        bt.__icon:SetPoint("LEFT", bt, "LEFT", 5, 0)
        SetIcon(bt.__icon, icon)
        bt.__lv = MakeFS(bt, PD.NAV_LV_FS, C_GREY, "RIGHT")
        bt.__lv:SetPoint("RIGHT", bt, "RIGHT", -6, 0)
        bt.__lv:Hide()
        bt:SetScript("OnClick", function() PD.Show(key) end)
        PD.nav[#PD.nav + 1] = bt
        PD.navKey[key] = bt
        navY = navY + PD.NAV_ITEM_H + PD.NAV_GAP
        return bt
    end

    navEntry("__index", L["全部专业"], "inv_misc_book_11")
    PD.navOrder = {}
    for _, g in ipairs({ { kind = "primary", label = L["主专业"] },
                         { kind = "secondary", label = L["次专业"] },
                         { kind = "system", label = L["营地系统"] } }) do
        local list = {}
        for _, slug in ipairs(D.order or {}) do
            local p = D.pro[slug]
            if p and p.kind == g.kind then list[#list + 1] = slug end
        end
        if #list > 0 then
            navY = navY + 4
            local lab = MakeFS(page, 11, C_GREY, "LEFT")
            lab:SetPoint("TOPLEFT", page, "TOPLEFT", PD.NAV_X + 5,
                         -(PD.NAV_TOP + navY + 6))
            lab:SetText(g.label)
            navY = navY + PD.NAV_GROUP_H
            for _, slug in ipairs(list) do
                local p = D.pro[slug]
                navEntry(slug, p.name or slug, p.icon)
                PD.navOrder[#PD.navOrder + 1] = slug
            end
        end
    end

    ns.hui.OnThemeChange(function() if PD.built then pcall(PD.PickNav) end end)

    PD.subBtns = {}
    for _, def in ipairs(DG.PROF_SUBTABS) do
        local bt = NewButton(page, def.text, PD.SUB_W, PD.SUB_H, 13)
        MakeOutline(bt, 1, 0.82, 0)
        bt.__huiKeepTextColor = true
        bt:Hide()
        bt:SetScript("OnClick", function() PD.SetTab(def.key) end)
        PD.subBtns[def.key] = bt
    end

    local gear = NewButton(page, "", PD.SUB_H, PD.SUB_H, 13)
    MakeOutline(gear, 1, 0.82, 0)
    gear.__huiKeepTextColor = true
    gear.__icon = gear:CreateTexture(nil, "ARTWORK")
    gear.__icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(gear.__icon) end
    gear.__icon:SetSize(14, 14)
    gear.__icon:SetPoint("CENTER", gear, "CENTER", 0, 0)
    SetIcon(gear.__icon, ns.SET_ICON)
    gear:SetPoint("TOPRIGHT", page, "TOPLEFT", PD.RIGHT_X + PD.RIGHT_W, -PD.SUB_Y)
    gear:SetScript("OnClick", function()
        PD.setOpen = not PD.setOpen
        PD.Render()
        ns.PlaySound(1)
    end)
    PD.setGear = gear

    PD.setToggles = {}

    for i = 1, PD.TOOL_MAX do
        local bt = NewButton(page, "", PD.TOOL_W, PD.TOOL_H, 12)
        MakeOutline(bt, 1, 0.82, 0)
        bt.__huiKeepTextColor = true
        bt:Hide()
        bt:SetScript("OnClick", function(self)
            if self.__key and PD.onTool then PD.onTool(self.__key) end
            ns.PlaySound(1)
        end)
        PD.toolBtns[i] = bt
    end

    local listCard = CreateFrame("Frame", nil, page, "BackdropTemplate")
    listCard:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    listCard:SetBackdropColor(1, 1, 1, DG.LOOT_CARD_BG)
    listCard:SetBackdropBorderColor(1, 1, 1, DG.LOOT_CARD_EDGE)
    PD.listCard = listCard

    local divider = page:CreateTexture(nil, "BORDER")
    divider:SetColorTexture(1, 1, 1, 0.12)
    divider:SetWidth(1)
    divider:Hide()
    PD.divider = divider

    local scroll = CreateFrame("ScrollFrame", nil, page)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        DG.WheelScroll(PD.scroll, PD.child, delta)
    end)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(PD.RIGHT_W, 10)
    scroll:SetScrollChild(child)
    PD.scroll, PD.child = scroll, child

    local hlAcc = 0
    child:SetScript("OnUpdate", function(_, el)
        hlAcc = hlAcc + el
        if hlAcc < 0.1 then return end
        hlAcc = 0
        PD.SyncHover()
    end)

    PD.BuildBonusTable(child)

    for i = 1, PD.SETTING_TOG_MAX do
        local tg = CreateFrame("CheckButton", nil, child)
        tg:SetSize(36, 20)
        tg:EnableMouse(true)
        ns.hui.ReskinToggle(tg)
        tg:SetScript("OnClick", function(self)
            if self.__key then
                ProfDB()[self.__key] = not PD.Setting(self.__key)
                self:SetChecked(PD.Setting(self.__key))
            end
            PD.Render()
            ns.PlaySound(1)
        end)
        PD.setToggles[i] = tg
    end

    PD.bonusTitleNote = MakeFS(child, 11, C_GREY, "RIGHT")
    PD.bonusTitleNote:SetText(
        L["营地增益不与同类职业增益叠加、效果略低于职业版（如王者祝福 10% → 营地 8%）。"])
    PD.bonusTitleNote:Hide()

    PD.BuildIndexGrid(child)

    PD.secCards = {}
    for i = 1, PD.SEC_CARD_MAX do
        local c = CreateFrame("Frame", nil, child)
        ns.hui.BuildRoundedBG(c, 6, { 1, 1, 1, DG.LOOT_CARD_BG }, "both", true, 1)
        c:Hide()
        PD.secCards[i] = c
    end

    PD.ver = MakeFS(page, 11, C_GREY, "LEFT")
    PD.ver:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 10, 4)
    PD.ver:SetText(format(L["专业数据 build %s · %s"],
                          tostring(D.build or "?"), tostring(D.updated or "?")))
end

local NAV_SKILL_SLUG = {
    [171] = "alchemy",     [164] = "blacksmithing", [333] = "enchanting",
    [202] = "engineering", [165] = "leatherworking", [197] = "tailoring",
    [186] = "mining",      [182] = "herbalism",     [393] = "skinning",
    [185] = "cooking",     [356] = "fishing",       [129] = "first-aid",
}

function PD.ProfLearned()
    local out = {}
    if type(GetProfessions) ~= "function" then return out end
    local ok, a, b, c, d, e, f = pcall(GetProfessions)
    if not ok then return out end
    local slots = { a, b, c, d, e, f }
    for i = 1, 6 do
        local idx = slots[i]
        if idx then
            local oki, _, _, cur, mx, _, _, sid = pcall(GetProfessionInfo, idx)
            local slug = NAV_SKILL_SLUG[sid]
            if oki and slug and cur and mx then
                out[slug] = { cur = tonumber(cur) or 0, max = tonumber(mx) or 0 }
            end
        end
    end
    return out
end

local function NavAccent()
    local a = ns.hui and ns.hui.ACCENT
    if a then return a[1], a[2], a[3] end
    return 0x46 / 255, 0xbf / 255, 0x72 / 255
end
PD.NavAccent = NavAccent

function PD.PickNav()
    local learned = PD.ProfLearned()
    local function paint(bt, sel, lv)
        SetOutline(bt, sel, 1, 0.82, 0)
        if lv then
            if sel then
                bt:GetFontString():SetTextColor(Unpack(C_GOLD))
            else
                bt:GetFontString():SetTextColor(NavAccent())
            end
            bt.__lv:SetText(format("%d/%d", lv.cur, lv.max))
            bt.__lv:SetTextColor(NavAccent())
            bt.__lv:Show()
        else
            bt.__lv:Hide()
            bt:GetFontString():SetTextColor(Unpack(sel and C_GOLD or C_DIM))
        end
        bt.__icon:SetDesaturated(not sel and not lv)
    end
    for _, slug in ipairs(PD.navOrder or {}) do
        local bt = PD.navKey[slug]
        if bt then paint(bt, slug == PD.cur, learned[slug]) end
    end
    local ib = PD.navKey["__index"]
    if ib then paint(ib, PD.cur == "__index", nil) end
end

function PD.TabsFor(slug)
    if slug == "__index" then return { "overview" } end
    local p = D.pro[slug]
    local out = { "overview" }
    if not p then return out end
    if slug == "camping" then out[#out + 1] = "camp" end
    if p.camp and #p.camp > 0 then out[#out + 1] = "camp" end
    local r = R[slug]
    if r and ((r.rows and #r.rows > 0) or (r.enchants and #r.enchants > 0)
              or (r.crafted and #r.crafted > 0)) then
        out[#out + 1] = "recipe"
    end
    if GA and (GA[slug] or (slug == "fishing" and GA.fishing)) then out[#out + 1] = "gather" end
    if LV and LV[slug] then out[#out + 1] = "leveling" end
    if p.perks and #p.perks > 0 then out[#out + 1] = "legacy" end
    out[#out + 1] = "notes"
    return out
end

function PD.PickTabs()
    local tabs = PD.TabsFor(PD.cur)
    PD.avail = {}
    for _, t in ipairs(tabs) do PD.avail[t] = true end
    if not PD.avail[PD.tab] then PD.tab = "overview" end
    local shown = 0
    for _, def in ipairs(DG.PROF_SUBTABS) do
        local bt = PD.subBtns[def.key]
        local on = PD.avail[def.key] and true or false
        bt:SetShown(on)
        if on then
            bt:ClearAllPoints()
            bt:SetPoint("TOPLEFT", PD.page, "TOPLEFT",
                        PD.RIGHT_X + shown * PD.SUB_STEP, -PD.SUB_Y)
            shown = shown + 1
            if def.key == "camp" and PD.cur == "camping" then
                bt:SetText(L["职业加成"])
            else
                bt:SetText(def.text)
            end
            local sel = (not PD.setOpen) and (def.key == PD.tab)
            SetOutline(bt, sel, 1, 0.82, 0)
            bt:GetFontString():SetTextColor(Unpack(sel and C_GOLD or C_GREY))
        end
    end
    if PD.setGear then
        SetOutline(PD.setGear, PD.setOpen and true or false, 1, 0.82, 0)
        local gc = PD.setOpen and ns.SET_ICON_ON or ns.SET_ICON_IDLE
        PD.setGear.__icon:SetVertexColor(gc[1], gc[2], gc[3])
    end
end

PD.TOOL_MIN_W, PD.TOOL_MAX_W = 56, 200
PD.TOOL_PADX = 18

function PD.ToolSize(text)
    local need = PD.TextW(text, 12) + PD.TOOL_PADX
    local w = math.ceil(math.max(PD.TOOL_MIN_W, math.min(PD.TOOL_MAX_W, need)))
    local shown = text
    if need > PD.TOOL_MAX_W then shown = PD.Fit(text, 12, PD.TOOL_MAX_W - PD.TOOL_PADX) end
    return w, shown
end

function PD.PaintTool(list, handler)
    PD.onTool = handler
    list = list or {}
    local n = math.min(#list, PD.TOOL_MAX)
    local x, row = 0, 0
    for i = 1, PD.TOOL_MAX do
        local bt = PD.toolBtns[i]
        local def = (i <= n) and list[i] or nil
        if def then
            local w, text = PD.ToolSize(def.text)
            if x > 0 and x + w > PD.RIGHT_W then row = row + 1; x = 0 end
            bt:SetSize(w, PD.TOOL_H)
            bt:ClearAllPoints()
            bt:SetPoint("TOPLEFT", PD.page, "TOPLEFT", PD.RIGHT_X + x,
                        -(PD.BODY_TOP + row * (PD.TOOL_H + PD.TOOL_GAP)))
            bt:SetText(text)
            bt.__key = def.key
            SetOutline(bt, def.on and true or false, 1, 0.82, 0)
            bt:GetFontString():SetTextColor(Unpack(def.on and C_GOLD or C_GREY))
            bt:Show()
            x = x + w + PD.TOOL_GAP
        else
            bt:Hide()
            bt.__key = nil
        end
    end
    local rows = (n > 0) and (row + 1) or 0
    PD.toolRows = rows
    return (rows > 0) and (rows * (PD.TOOL_H + PD.TOOL_GAP) + PD.TOOL_BODY_GAP) or 0
end

function PD.Layout(toolH)
    local top = PD.BODY_TOP + (toolH or 0)
    local bot = PD.BODY_BOT
    PD.scroll:ClearAllPoints()
    PD.scroll:SetPoint("TOPLEFT", PD.page, "TOPLEFT", PD.RIGHT_X, -top)
    PD.scroll:SetPoint("BOTTOMRIGHT", PD.page, "BOTTOMRIGHT", -PAGE_INSET, bot)
    PD.listCard:ClearAllPoints()
    PD.listCard:SetPoint("TOPLEFT", PD.page, "TOPLEFT",
                         PD.RIGHT_X - PD.LIST_PAD, -(top - PD.LIST_PAD))
    PD.listCard:SetPoint("BOTTOMRIGHT", PD.page, "BOTTOMRIGHT",
                         -(PAGE_INSET - PD.LIST_PAD), bot - PD.LIST_PAD)
    PD.listCard:Show()
    local splitW
    if PD.lvSplit then splitW = PD.splitLW or PD.COL_LW
    elseif PD.gridSplit then splitW = PD.GRID_LW end
    if splitW and not PD.hideDivider then
        local gut = PD.lvSplit and PD.OV_GUT or PD.COL_GAP
        local mx = PD.RIGHT_X + PD.LIST_PAD + splitW + gut / 2
        PD.divider:ClearAllPoints()
        PD.divider:SetPoint("TOPLEFT", PD.page, "TOPLEFT", mx, -top)
        PD.divider:SetPoint("BOTTOMLEFT", PD.page, "BOTTOMLEFT", mx, bot)
        PD.divider:Show()
    else
        PD.divider:Hide()
    end
end

PD.SWEEP_AT = { 0.5, 1.5, 4, 9 }

function PD.SweepNames()
    if PD.sweeping or not PD.notReady then return end
    PD.sweeping = true
    local got = false
    for _, id in ipairs(PD.notReady) do
        local _, ok = DG.ItemName(id)
        if ok then got = true; break end
    end
    PD.notReady = nil
    if got then PD.Render() end
    PD.sweeping = false
end

function PD.ScheduleSweep()
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
    for _, t in ipairs(PD.SWEEP_AT) do
        C_Timer.After(t, function() PD.SweepNames() end)
    end
end

function PD.RowsOverview(rows)
    if PD.cur == "__index" then
        local new, camps, perks, pts = 0, 0, 0, 0
        for _, slug in ipairs(D.order or {}) do
            local p = D.pro[slug]
            local r = R[slug]
            if r and r.rows then
                for _, it in ipairs(r.rows) do if it[11] then new = new + 1 end end
            end
            if p and p.camp then camps = camps + #p.camp end
            if p and p.perks then perks = perks + #p.perks end
            if p and p.miles then
                for _, m in ipairs(p.miles) do pts = pts + (m[3] or 0) end
            end
        end
        PushHead(rows, L["这份手册里有什么"])
        PushText(rows, format(
            L["%d 个专业 · 新增配方 %d 条 · 营地物件 %d 个 · 传承里程碑 %d 点 · 特权 %d 个"],
            #(D.order or {}), new, camps, pts, perks), 12)
        PushGap(rows)
        return
    end

    local p = D.pro[PD.cur]
    if not p then return end
    PushGap(rows, 6, 1)
    PushGap(rows, 6, 2)

    PushHead(rows, L["简介"], 1)
    local lede = (type(p.lede) == "string" and p.lede ~= "") and p.lede or p.summary
    PushText(rows, lede, 12, nil, 1)
    PushGap(rows, PD.OV_GUT, 1)
    if p.cert or p.title then
        PushHead(rows, L["认证与称号"], 1)
        if p.cert then
            rows[#rows + 1] = {
                kind = "row", h = PD.ROW_H, col = 1, it = { p.cert[1] },
                text = p.cert[2] or "?",
                sub = format(L["解锁称号：%s"], p.cert[5] or "?"),
                right = format(L["技能 %d"], p.cert[4] or 0),
                lines = { { p.cert[2] or "?" },
                          { format(L["解锁称号：%s"], p.cert[5] or "?"), 1, 0.82, 0 } },
            }
        end
        if p.title then PushText(rows, p.title, 12, C_GOLD, 1) end
        PushGap(rows, PD.OV_GUT, 1)
    end
    if p.bonuses and #p.bonuses > 0 then
        PushHead(rows, L["共同变化"], 1)
        for _, b in ipairs(p.bonuses) do
            PushText(rows, format("%s：%s", b[1] or "?", b[4] or ""), 12, nil, 1)
        end
        PushGap(rows, PD.OV_GUT, 1)
    end
    if p.camp and #p.camp > 0 then
        PushHead(rows, L["营地三档"], 1)
        for _, c in ipairs(p.camp) do
            rows[#rows + 1] = {
                kind = "row", h = PD.ROW_H1, col = 1, icon = c[3],
                text = format(L["技能 %d · %s"], c[4] or 0, c[2] or "?"),
                right = c[6] or c[7] or "",
            }
        end
    end

    local miles = p.miles or {}
    local mpts = 0
    for _, m in ipairs(miles) do mpts = mpts + (m[3] or 0) end
    local function stat(label, value)
        rows[#rows + 1] = {
            kind = "row", h = PD.ROW_H1, col = 2,
            nameColor = C_GREY, text = label, right = value,
        }
    end
    PushHead(rows, L["数字速览"], 2)
    if p.cert then stat(L["认证技能"], format(L["技能 %d"], p.cert[4] or 0)) end
    if p.recipes or p.sub then
        stat(L["配方规模"], format(L["%d 条 · %d 个分类"], p.recipes or 0, p.sub or 0))
    end
    if #miles > 0 then stat(L["里程碑"], format(L["%d 点"], mpts)) end
    if p.camp and #p.camp > 0 then stat(L["营地"], format(L["%d 档"], #p.camp)) end
    if p.perks and #p.perks > 0 then stat(L["传承特权"], format(L["%d 个"], #p.perks)) end
    PushGap(rows, PD.OV_GUT, 2)
    if #miles > 0 then
        PushHead(rows, L["里程碑与传承点数"], 2)
        for _, m in ipairs(miles) do
            rows[#rows + 1] = {
                kind = "row", h = PD.ROW_H1, col = 2, text = m[1] or "?",
                right = format(L["技能 %d · %d 点"], m[2] or 0, m[3] or 0),
            }
        end
    end

    local secN = 0
    for _, sp in ipairs(rows) do
        if sp.kind == "head" then
            secN = secN + 1
            sp.sec = secN
        elseif sp.kind ~= "gap" then
            sp.sec = secN
        end
    end
    PD.secCount = secN
end

-- ★★ areaID → uiMapID：与探索页共用同一张静态表（Core/Data/Data_AreaMap.lua，生成物）。
--   无限服客户端没有 C_Map.GetMapInfoFromAreaID ⇒ 表里漏键 = 点军需官不落图。
local CAMP_AREA_MAP = ns.AreaMap or {}

local function MapIDAlive(mapID)
    if not mapID then return false end
    if not (C_Map and C_Map.GetMapInfo) then return true end
    local ok, mi = pcall(C_Map.GetMapInfo, mapID)
    return ok and mi ~= nil
end

function PD.MarkCampPoint(areaID, x, y)
    local mapID = areaID and CAMP_AREA_MAP[areaID] or nil
    if not MapIDAlive(mapID) then
        mapID = nil
        if areaID and C_Map and C_Map.GetMapInfoFromAreaID then
            local ok, mi = pcall(C_Map.GetMapInfoFromAreaID, areaID)
            mapID = ok and mi and mi.mapID or nil
        end
        if not MapIDAlive(mapID) then mapID = nil end
    end
    if not mapID then
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, L["未收录该位置的地图"], 1, 0.4, 0.4)
        end
        return
    end
    if UiMapPoint and UiMapPoint.CreateFromCoordinates and C_Map and C_Map.SetUserWaypoint then
        local pok, pt = pcall(UiMapPoint.CreateFromCoordinates, mapID, (x or 0) / 100, (y or 0) / 100)
        if pok and pt then
            pcall(C_Map.SetUserWaypoint, pt)
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, false)
            end
        end
    end
    if C_Map and C_Map.OpenWorldMap then
        pcall(C_Map.OpenWorldMap, mapID)
    elseif OpenWorldMap then
        pcall(OpenWorldMap, mapID)
    end
end

function PD.CampZoneName(areaID, fallback)
    local f = C_Map and C_Map.GetMapInfoFromAreaID
    if f and areaID then
        local ok, mi = pcall(f, areaID)
        if ok and mi and mi.name and mi.name ~= "" then return mi.name end
    end
    local g = C_Map and C_Map.GetAreaInfo
    if g and areaID then
        local ok, name = pcall(g, areaID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return fallback
end

function PD.RowsCamp(rows, side)
    local p = D.pro[PD.cur]
    if not (p and p.camp) then return end
    PushGap(rows, 6)
    PushHead(rows, L["三档营地物件（技能 20 / 140 / 300）"])
    for _, c in ipairs(p.camp) do
        local lines = {}
        local function Add(label, v)
            if v and v ~= "" then lines[#lines + 1] = { label .. "：" .. v } end
        end
        Add(L["角色"], c[7])
        Add(L["增益"], c[6])
        Add(L["取代"], c[8])
        Add(L["互斥"], c[9])
        Add(L["容量"], c[10])
        if c[11] and #c[11] > 0 then
            lines[#lines + 1] = { format(L["材料：%s"], PD.MatText(c[11])), 0.7, 0.7, 0.7 }
        end
        if c[12] and c[12][1] then
            lines[#lines + 1] = { format(L["图纸：%s"], DG.ItemName(c[12][1])) }
        end
        rows[#rows + 1] = {
            kind = "row", icon = c[3],
            text = c[2] or "?",
            sub = c[5] or "",
            right = format(L["技能 %d"], c[4] or 0),
            lines = lines,
        }
    end
    local lv = LV[PD.cur]
    if lv and (lv.camps or lv.vendor) then
        PushGap(rows, PD.OV_GUT)
        PushHead(rows, L["营地与军需官坐标（按阵营）"])
        local camp = lv.camps and lv.camps[side]
        if camp then
            rows[#rows + 1] = {
                kind = "row", text = format(L["营地 · %s"], camp[3] or "?"),
                sub = format("%s · %s", PD.CampZoneName(camp[6], tostring(camp[2] or "")), tostring(camp[1] or "")),
                right = format("%.1f, %.1f", camp[4] or 0, camp[5] or 0),
                lines = {
                    { L["点击：在地图上标记此位置"], 1, 0.82, 0 },
                    { format("%s %.1f, %.1f", tostring(camp[2] or ""), camp[4] or 0, camp[5] or 0), 0.75, 0.75, 0.75 },
                },
                act = function() PD.MarkCampPoint(camp[6], camp[4], camp[5]) end,
            }
        end
        local vd = lv.vendor and lv.vendor[side]
        if vd then
            rows[#rows + 1] = {
                kind = "row", icon = vd[4], text = format(L["军需官 · %s"], tostring(vd[1])),
                sub = tostring(vd[3] or ""),
                right = format("%.1f, %.1f", vd[5] or 0, vd[6] or 0),
                lines = {
                    { L["点击：在地图上标记该 NPC"], 1, 0.82, 0 },
                    { format("%.1f, %.1f", vd[5] or 0, vd[6] or 0), 0.75, 0.75, 0.75 },
                },
                act = function() PD.MarkCampPoint(vd[7], vd[5], vd[6]) end,
            }
        end
    end

    local secN = 0
    for _, sp in ipairs(rows) do
        if sp.kind == "head" then
            secN = secN + 1
            sp.sec = secN
        elseif sp.kind ~= "gap" then
            sp.sec = secN
        end
    end
    PD.secCount = secN
end

function PD.MatIconTex(id, px)
    px = px or 14
    local ic = DG.ItemIcon(id)
    if type(ic) == "number" then
        return format("|T%d:%d:%d|t", ic, px, px)
    end
    return format("|TInterface\\Icons\\%s:%d:%d|t", tostring(ic or FALLBACK_ICON), px, px)
end

function PD.MatCol(list, fs, budget)
    if not list or #list == 0 then return "", 0, 0 end
    local gap, px = 10, PD.MAT_ICON_PX
    local out, w, n = {}, 0, 0
    for i = 1, #list do
        local m = list[i]
        local cnt = format("%d×", m[2] or 1)
        local name = DG.ItemName(m[1])
        local cw = PD.TextW(cnt, fs) + px + PD.TextW(name, fs)
        if n > 0 and w + gap + cw > budget then
            out[#out + 1] = "…"
            break
        end
        if n == 0 and cw > budget then
            name = PD.Fit(name, fs, budget - PD.TextW(cnt, fs) - px)
            cw = PD.TextW(cnt, fs) + px + PD.TextW(name, fs)
        end
        out[#out + 1] = cnt .. PD.MatIconTex(m[1], px) .. name
        w = w + (n > 0 and gap or 0) + cw
        n = n + 1
    end
    return table.concat(out, "  "), w, n
end

function PD.MatText(list, maxN)
    if not list or #list == 0 then return "" end
    local t = {}
    for i, m in ipairs(list) do
        if maxN and i > maxN then t[#t + 1] = "…"; break end
        t[#t + 1] = format("%d×%s%s", m[2] or 1, PD.MatIconTex(m[1]), DG.ItemName(m[1]))
    end
    return table.concat(t, "  ")
end

function PD.RowBlk(r, j)
    local b = r.blk[j]
    if b then return b end
    b = {}
    b.ic = r:CreateTexture(nil, "ARTWORK")
    b.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(b.ic) end
    b.ic:SetSize(PD.TBL_ICON, PD.TBL_ICON)
    b.nm = MakeFS(r, 12, C_TEXT, "LEFT")
    b.ct = MakeFS(r, PD.TBL_MAT_CNT_FS, C_GOLD, "LEFT")
    b.ct:SetFont(ns.FONT, PD.TBL_MAT_CNT_FS, "THICKOUTLINE")
    b.ct:SetShadowColor(0, 0, 0, 1)
    b.ct:SetShadowOffset(1, -1)
    b.nm:SetWordWrap(false)
    b.ct:SetWordWrap(false)
    r.blk[j] = b
    return b
end

function PD.ClearMats(r)
    for j = 1, #r.blk do
        local b = r.blk[j]
        b.ic:Hide()
        b.nm:Hide()
        b.ct:Hide()
    end
end

function PD.PackMats(list, budget)
    local out, total, n = {}, 0, 0
    if not list or #list == 0 or not budget or budget <= 0 then return out, 0, false end
    for i = 1, #list do
        if n >= PD.TBL_BLK_MAX then break end
        local cnt = list[i][2] or 1
        local w = math.max(PD.TBL_ICON, PD.TextW(format("%d", cnt), PD.TBL_MAT_CNT_FS))
        local step = w + ((n > 0) and PD.TBL_BLK_GAP or 0)
        if total + step + PD.TBL_MARK_W > budget then
            return out, total, true
        end
        total = total + step
        out[#out + 1] = { id = list[i][1], cnt = cnt, w = w }
        n = n + 1
    end
    return out, total, n < #list
end

function PD.PaintMats(r, blocks, cut, grey)
    local n = blocks and #blocks or 0
    local right = PD.COL_LW - PD.TBL_MAT_RPAD
    if cut then
        local b = PD.RowBlk(r, n + 1)
        b.ic:Hide()
        b.ct:SetText("")
        b.ct:Hide()
        b.nm:SetTextColor(Unpack(grey and C_DIM or C_TEXT))
        b.nm:SetText("…")
        b.nm:ClearAllPoints()
        b.nm:SetPoint("RIGHT", r, "RIGHT", -(PD.COL_LW - right), PD.TBL_NAME_DY)
        b.nm:Show()
        right = right - PD.TBL_MARK_W - PD.TBL_BLK_GAP
    end
    for k = n, 1, -1 do
        local blk = blocks[k]
        local b = PD.RowBlk(r, k)
        SetIcon(b.ic, DG.ItemIcon(blk.id))
        b.ic:SetDesaturated(grey and true or false)
        b.ic:ClearAllPoints()
        b.ic:SetPoint("RIGHT", r, "RIGHT", -(PD.COL_LW - right), 0)
        b.nm:Hide()
        b.ct:SetTextColor(Unpack(grey and C_DIM or C_GOLD))
        b.ct:SetText(format("%d", blk.cnt))
        b.ct:ClearAllPoints()
        b.ct:SetPoint("RIGHT", r, "RIGHT", -(PD.COL_LW - right), PD.TBL_MAT_CNT_DY)
        b.ic:Show(); b.ct:Show()
        right = right - blk.w - PD.TBL_BLK_GAP
    end
    for k = n + (cut and 1 or 0) + 1, #r.blk do
        local b = r.blk[k]
        b.ic:Hide(); b.nm:Hide(); b.ct:Hide()
    end
end

function PD.LevelSrc(rec)
    if not rec then return nil, nil end
    local src = rec[14]
    local fid = rec[13] and rec[13][1]
    if not fid then return L["向训练师学习"], nil end
    local detail
    if src and src.drops and #src.drops > 0 then
        detail = format(L["图纸：%s · 掉落 %d 处"], DG.ItemName(fid), #src.drops)
    end
    return L["需图纸 · 商人出售"], detail
end

function PD.SourceText(s)
    if not s then return nil end
    local t = {}
    if s.skill then t[#t + 1] = format(L["技能 %s"], tostring(s.skill)) end
    if s.drops and #s.drops > 0 then t[#t + 1] = format(L["掉落 %d 处"], #s.drops) end
    if s.vendors and #s.vendors > 0 then
        local v = s.vendors[1]
        t[#t + 1] = format(L["商人：%s"], (v and v.name) or "?")
    end
    if #t == 0 then return nil end
    return table.concat(t, " · ")
end

function PD.EnchantSpec(en)
    local spec
    if en[13] and #en[13] > 0 then
        local t = {}
        for _, b in ipairs(en[13]) do t[#t + 1] = b[3] or "" end
        spec = table.concat(t, " / ")
    end
    local lines = { { en[1] or "" } }
    if en[4] and en[4] ~= "" then lines[#lines + 1] = { en[4] } end
    if en[10] then lines[#lines + 1] = { PD.SourceText(en[10]) or "", 0.7, 0.7, 0.7 } end
    if en[9] and #en[9] > 0 then
        lines[#lines + 1] = { format(L["材料：%s"], PD.MatText(en[9])), 0.7, 0.7, 0.7 }
    end
    if spec then lines[#lines + 1] = { format(L["适用：%s"], spec), 0.6, 0.9, 0.6 } end
    return {
        kind = "row", is_new = en[11], _mats = en[9],
        text = en[2] or en[1] or "?",
        sub = table.concat({ tostring(en[3] or ""), tostring(en[4] or ""),
                             spec or "" }, " · "),
        mats = PD.MatCol(en[9], PD.MAT_FS, PD.MAT_W),
        right = format("%s · %s", format(L["学 %s"], tostring(en[5])),
                       PD.TierText(en[6], en[7], en[8])),
        right2 = en[12] and L["Season of Discovery"] or format(L["%d 种材料"], #(en[9] or {})),
        lines = lines,
    }
end

function PD.RecipeSpec(r)
    local mats = PD.MatText(r[12], 4)
    local lines = {}
    if r[6] and r[6] ~= "" then lines[#lines + 1] = { r[6] } end
    lines[#lines + 1] = { format(L["材料：%s"], mats ~= "" and mats or L["无"]) }
    lines[#lines + 1] = { format(L["技能：学 %s · %s"], tostring(r[7]),
                                 PD.TierText(r[8], r[9], r[10])) }
    if r[15] and #r[15] > 0 then
        lines[#lines + 1] = { format(L["改版前材料：%s"], PD.MatText(r[15])), 0.9, 0.7, 0.4 }
    end
    if r[16] and r[16] ~= "" then
        lines[#lines + 1] = { format(L["套装：%s"], r[16]), 0.64, 0.21, 0.93 }
    end
    if r[17] and r[17] ~= "" then
        lines[#lines + 1] = { format(L["护甲类型：%s"], r[17]), 0.7, 0.7, 0.7 }
    end
    return {
        kind = "row", is_new = r[11], it = { r[2] }, row = r, _mats = r[12],
        text = DG.ItemName(r[2]),
        sub = tostring(r[5] or ""),
        mats = PD.MatCol(r[12], PD.MAT_FS, PD.MAT_W),
        right = format("%s · %s", format(L["学 %s"], tostring(r[7])),
                       PD.TierText(r[8], r[9], r[10])),
        right2 = PD.SourceText(r[14]) or (r[13] and L["需要图纸"] or ""),
        lines = lines,
    }
end

function PD.CraftedSpec(c)
    local mats = PD.MatText(c[8], 4)
    return {
        kind = "row", is_new = c[10], it = { c[2] }, _mats = c[8], craft = c,
        text = DG.ItemName(c[2]),
        sub = "",
        mats = PD.MatCol(c[8], PD.MAT_FS, PD.MAT_W),
        right = format("%s · %s", format(L["学 %s"], tostring(c[4])),
                       PD.TierText(c[5], c[6], c[7])),
        right2 = (c[9] and c[9] ~= "") and format(L["师傅 NPC #%s"], tostring(c[9])) or "",
        lines = { { format(L["材料：%s"], mats ~= "" and mats or L["无"]) } },
    }
end

function PD.FavorSpec(f)
    local out = f[5] and DG.ItemName(f[5])
    return {
        kind = "row", it = { f[1] }, _mats = nil,
        text = DG.ItemName(f[1]),
        sub = (f[4] and f[4] ~= "" and format(L["换得：%s"], f[4]))
              or (out and format(L["换得：%s"], out)) or "",
        right = format(L["技能 %s"], tostring(f[2])),
        right2 = format(L["商人青睐 %s"], tostring(f[3])),
        lines = { { format(L["交出：%s"], DG.ItemName(f[1])) },
                  { (f[4] and f[4] ~= "") and format(L["换得配方：%s"], f[4])
                    or format(L["换得：%s"], tostring(out)), 1, 0.82, 0 },
                  { format(L["所需：技能 %s · 商人青睐 %s"], tostring(f[2]), tostring(f[3])),
                    0.7, 0.7, 0.7 } },
    }
end

function PD.RecipeTool(d)
    if not d then return {}, nil end
    local tool = {}
    local function on(k) return PD.toolKey == k end
    if d.rows and #d.rows > 0 then
        tool[#tool + 1] = { key = "all", text = format(L["全部 %d"], #d.rows), on = on("all") }
        for _, g in ipairs(d.groups or {}) do
            tool[#tool + 1] = { key = g[1], text = format("%s %d", g[2] or g[1], g[4] or 0),
                                on = on(g[1]) }
        end
    end
    if d.enchants and #d.enchants > 0 then
        tool[#tool + 1] = { key = "__enchant", text = format(L["附魔 %d"], #d.enchants),
                            on = on("__enchant") }
    end
    if d.crafted and #d.crafted > 0 then
        tool[#tool + 1] = { key = "__crafted", text = format(L["可制造 %d"], #d.crafted),
                            on = on("__crafted") }
    end
    if d.favor and #d.favor > 0 then
        tool[#tool + 1] = { key = "__favor", text = format(L["商人兑换 %d"], #d.favor),
                            on = on("__favor") }
    end
    if #tool > PD.TOOL_MAX then
        local keep = PD.TOOL_MAX - 1
        local rest = 0
        for i = keep + 1, #tool do rest = rest + 1 end
        for i = #tool, keep + 1, -1 do table.remove(tool, i) end
        tool[#tool + 1] = { key = "__rest", text = format(L["其他 %d"], rest), on = on("__rest") }
    end
    local valid = false
    for _, t in ipairs(tool) do if t.on then valid = true end end
    if not valid then
        PD.toolKey = tool[1] and tool[1].key or "all"
        if tool[1] then tool[1].on = true end
    end
    return tool, function(k) PD.toolKey = k; PD.Render() end
end

function PD.RecipeList()
    local d = R[PD.cur]
    local out = {}
    if not d then return out end
    local key = PD.toolKey
    if key == "__enchant" then
        for _, e in ipairs(d.enchants or {}) do out[#out + 1] = PD.EnchantSpec(e) end
        return out
    end
    if key == "__crafted" then
        for _, c in ipairs(d.crafted or {}) do out[#out + 1] = PD.CraftedSpec(c) end
        return out
    end
    if key == "__favor" then
        for _, f in ipairs(d.favor or {}) do out[#out + 1] = PD.FavorSpec(f) end
        return out
    end
    local any = false
    for _, r in ipairs(d.rows or {}) do
        if (not key or key == "all" or r[4] == key) then
            out[#out + 1] = PD.RecipeSpec(r)
            any = true
        end
    end
    if not any then
        for _, r in ipairs(d.rows or {}) do out[#out + 1] = PD.RecipeSpec(r) end
    end
    return out
end

function PD.RowsRecipe(rows)
    local d = R[PD.cur]
    if not d then return end
    local list = PD.RecipeList()
    local total = (d.counts and d.counts.total) or #list
    local unread = (d.counts and d.counts.unreadable) or 0
    PushHead(rows, format(L["当前分类 %d 条（标注总计 %d 条，其中 %d 条来源不可读）"],
                          #list, total, unread))
    local trunc = 0
    if #list > PD.ROW_CAP then trunc = #list - PD.ROW_CAP end
    for i = 1, math.min(#list, PD.ROW_CAP) do rows[#rows + 1] = list[i] end
    if trunc > 0 then
        PushGap(rows)
        PushText(rows, format(
            L["列表只画前 %d 条，还有 %d 条没显示 —— 用上方分类缩小范围。"],
            PD.ROW_CAP, trunc), 12, C_GOLD)
    end
end

function PD.ZoneText(list, maxN)
    if not list or #list == 0 then return L["无数据"] end
    local t = {}
    for i, z in ipairs(list) do
        if maxN and i > maxN then t[#t + 1] = "…"; break end
        t[#t + 1] = format("%s(%d)", DG.ZoneName(z[1]), z[2] or 0)
    end
    return table.concat(t, "  ")
end

DG.FISH_FIELD_LABEL = {
    L["所需技能"], L["技能加成"], L["持续（分钟）"], L["等级"],
    L["学会后解锁"], L["标注新增"], L["可作为钓具"], L["需求"],
}
DG.FISH_GROUPS = {
    { key = "spells", text = L["钓鱼法术"] },
    { key = "lures",  text = L["鱼饵"] },
    { key = "food",   text = L["钓鱼食物"] },
    { key = "items",  text = L["钓鱼物品"] },
    { key = "titles", text = L["钓鱼称号"] },
}

function PD.RowsFishing(rows)
    local p = D.pro.fishing
    local zones = GA and GA.fishing
    if zones and #zones > 0 then
        PushHead(rows, format(L["可钓区域（%d 处）"], #zones))
        for _, z in ipairs(zones) do
            rows[#rows + 1] = {
                kind = "row", h = PD.ROW_H1, text = DG.ZoneName(z[1]),
                right = format(L["技能 %s"], tostring(z[2])),
            }
        end
        PushGap(rows)
    end

    if p and p.ranks and #p.ranks > 0 then
        PushHead(rows, L["技能等级（怎么把上限提上去）"])
        for _, rk in ipairs(p.ranks) do
            local note = rk[3] or ""
            local book = rk[4]
            if book then note = note:gsub("{book}", (DG.ItemName(book))) end
            rows[#rows + 1] = {
                kind = "row", h = PD.ROW_H1,
                it = book and { book } or nil,
                text = rk[1] or "?", right = format(L["技能 %s"], tostring(rk[2])),
                lines = { { rk[1] or "" }, { note } },
            }
            if note ~= "" then PushText(rows, "· " .. note, 11, C_GREY) end
        end
        PushGap(rows)
    end

    if not (p and p.fishing) then return end
    for _, grp in ipairs(DG.FISH_GROUPS) do
        local list = p.fishing[grp.key]
        if list and #list > 0 then
            PushHead(rows, format(L["%s（%d 条）"], grp.text, #list))
            local isSpell = (grp.key == "spells")
            local isTitle = (grp.key == "titles")
            for _, e in ipairs(list) do
                local id, icon, sub = e[1], e[3], e[5]
                local nm
                if isSpell then
                    nm = SpellName(id)
                elseif not isTitle then
                    nm = DG.ItemName(id)
                end
                if type(nm) ~= "string" or nm == "" then nm = e[2] end
                local lines = {}
                if e[4] and e[4] ~= "" then lines[#lines + 1] = { e[4] } end
                if sub and sub ~= "" then lines[#lines + 1] = { sub, 0.7, 0.7, 0.7 } end
                for i = 6, 13 do
                    local v = e[i]
                    if v ~= nil and v ~= false and v ~= 0 and v ~= "" then
                        if type(v) == "table" then
                            local t = {}
                            for _, x in ipairs(v) do t[#t + 1] = tostring(x) end
                            v = table.concat(t, " / ")
                        end
                        if v ~= "" then
                            lines[#lines + 1] = { format("%s：%s",
                                DG.FISH_FIELD_LABEL[i - 5], tostring(v)), 0.6, 0.9, 0.6 }
                        end
                    end
                end
                rows[#rows + 1] = {
                    kind = "row", is_new = e[11],
                    it = (id and not isSpell and not isTitle) and { id } or nil,
                    icon = (icon ~= "" and icon) or nil,
                    text = nm or (id and format(L["法术 #%d"], id)) or "?",
                    sub = sub or "", right = (e[6] and format(L["技能 %s"], tostring(e[6]))) or "",
                    right2 = e[9] and format(L["等级 %s"], tostring(e[9])) or "",
                    lines = lines,
                }
            end
            PushGap(rows)
        end
    end
end

function PD.RowsGather(rows)
    if PD.cur == "fishing" then
        PD.RowsFishing(rows)
        return
    end
    local g = GA and GA[PD.cur]
    if not g then return end
    if PD.cur == "skinning" then
        PushHead(rows, L["剥皮档次（等级区间 → 产出 → 分布）"])
        for _, t in ipairs(g) do
            local items = {}
            for _, id in ipairs(t[2] or {}) do items[#items + 1] = DG.ItemName(id) end
            rows[#rows + 1] = {
                kind = "row",
                text = format(L["等级 %s - %s"], tostring(t[1][1]), tostring(t[1][2])),
                sub = table.concat(items, "  "),
                right2 = PD.ZoneText(t[3], 3),
                lines = { { format(L["产出：%s"], table.concat(items, "  ")) },
                          { format(L["分布：%s"], PD.ZoneText(t[3])) } },
            }
        end
        return
    end
    PushHead(rows, L["节点表（所需技能 → 产出 → 分布）"])
    for _, n in ipairs(g) do
        local head = n[1] and n[1][1]
        local items = {}
        for _, id in ipairs(n[1] or {}) do items[#items + 1] = DG.ItemName(id) end
        local nm, got = DG.ItemName(head)
        if not got then nm = head and format(L["物品 #%d"], head) or "?" end
        rows[#rows + 1] = {
            kind = "row", it = head and { head } or nil, text = nm,
            sub = table.concat(items, "  "),
            right = format(L["技能 %d"], n[2] or 0),
            right2 = PD.ZoneText(n[3], 3),
            lines = { { format(L["产出：%s"], table.concat(items, "  ")) },
                      { format(L["分布：%s"], PD.ZoneText(n[3])) } },
        }
    end
end

function PD.RowsLeveling(rows)
    local lv = LV[PD.cur]
    if not lv then return end

    local _learned = PD.ProfLearned()
    local curLv = _learned and _learned[PD.cur] and _learned[PD.cur].cur or nil
    local greyOn = PD.Setting("greyPassed")

    local recOf = {}
    local rr = R[PD.cur]
    if rr and rr.rows then
        for _, r in ipairs(rr.rows) do recOf[r[1]] = r end
    end

    local rngW, nameW, cntW, matNeed = 0, 0, 0, 0
    for _, st in ipairs(lv.steps or {}) do
        local w = PD.TextW(format(L["%s – %s"], tostring(st[1]), tostring(st[2])), PD.LV_FS)
        if w > rngW then rngW = w end
        local nw = PD.TextW(SpellName(st[3]), PD.LV_FS)
        if nw > nameW then nameW = nw end
        local cw = PD.TextW(format(L["~%s 次制作"], tostring(st[4])), PD.LV_FS)
        if cw > cntW then cntW = cw end
        local rec = recOf[st[3]]
        local _, mw = PD.PackMats((rec and rec[12]) or {}, 1e9)
        if mw + PD.TBL_MARK_W > matNeed then matNeed = mw + PD.TBL_MARK_W end
    end
    PD.LV_ICON_X = 6 + math.ceil(rngW) + PD.TBL_RNG_GAP
    PD.LV_NAME_X = PD.LV_ICON_X + PD.TBL_ICON + PD.TBL_NAME_GAP
    PD.LV_CNT_W = math.max(40, math.ceil(cntW))
    local avail = PD.COL_LW - PD.TBL_MAT_RPAD - PD.LV_NAME_X - PD.TBL_NAME_GAP
                  - PD.LV_CNT_W - PD.TBL_CNT_GAP
    PD.LV_NAME_W = math.min(PD.TBL_NAME_MAX, math.max(PD.TBL_NAME_MIN, math.ceil(nameW)))
    if avail - PD.LV_NAME_W < matNeed then
        PD.LV_NAME_W = math.max(PD.TBL_NAME_MIN, avail - matNeed)
    end
    PD.LV_MAT_W = avail - PD.LV_NAME_W
    PD.LV_CNT_R = PD.TBL_MAT_RPAD + PD.LV_MAT_W + PD.TBL_CNT_GAP

    local function FitName(s)
        return PD.Fit(s, PD.LV_FS, PD.LV_NAME_W)
    end
    local function FitL(s)
        return PD.Fit(s, PD.LV_FS, PD.COL_LW - 120)
    end
    local function FitR(s) return PD.Fit(s, 13, PD.COL_RW - 66) end

    if lv.steps and #lv.steps > 0 then
        PushHead(rows, L["1 → 300 分段路线"], 1)
        for _, st in ipairs(lv.steps) do
            local rec = recOf[st[3]]
            local mats = (rec and rec[12]) or {}
            local nm = SpellName(st[3])
            local src, detail = PD.LevelSrc(rec)
            local blocks, _, cut = PD.PackMats(mats, PD.LV_MAT_W)
            local tip = { { nm, 1, 0.82, 0 },
                          { src or L["来源未收录"], 0.7, 0.7, 0.7 },
                          { format(L["材料：%s"],
                                   (#mats > 0 and PD.MatText(mats) or L["无"])), 0.7, 0.7, 0.7 } }
            if detail then tip[#tip + 1] = { detail, 0.6, 0.9, 0.6 } end
            local segHi = tonumber(st[2])
            local over = (curLv ~= nil and segHi ~= nil and segHi < curLv) or nil
            local passed = (greyOn and over) or nil
            rows[#rows + 1] = {
                kind = "row", h = PD.TBL_H, col = 1, lvstep = true,
                passed = passed, over = over,
                it = (rec and rec[2]) and { rec[2] } or nil,
                linesFirst = true,
                rng = format(L["%s – %s"], tostring(st[1]), tostring(st[2])),
                text = FitName(nm),
                src = src,
                cnt = format(L["~%s 次制作"], tostring(st[4])),
                blocks = blocks, matCut = cut,
                _mats = mats,
                lines = tip,
            }
        end
    end
    if PD.Setting("hlCurrent") and curLv ~= nil then
        for _, spec in ipairs(rows) do
            if spec.lvstep and spec.over == nil then
                spec.cur = true
                break
            end
        end
    end
    if lv.rods and #lv.rods > 0 then
        PushGap(rows, 8, 1)
        PushHead(rows, L["附魔魔棒（所需技能 → 魔棒）"], 1)
        for _, rd in ipairs(lv.rods) do
            rows[#rows + 1] = {
                kind = "row", h = PD.ROW_H1, col = 1, it = { rd[2] },
                text = FitL(DG.ItemName(rd[2])),
                right = format(L["技能 %s"], tostring(rd[1])),
            }
        end
    end
    if lv.quest and #lv.quest > 0 then
        PushGap(rows, 8, 1)
        PushHead(rows, format(L["关联任务（%d 个）"], #lv.quest), 1)
        for _, id in ipairs(lv.quest) do
            rows[#rows + 1] = {
                kind = "row", h = PD.ROW_H1, col = 1,
                text = FitL(PD.QuestName(id)),
                right = format("#%d", id),
            }
        end
    end

    if lv.shopping and #lv.shopping > 0 then
        local total = 0
        for _, s in ipairs(lv.shopping) do total = total + (s[2] or 0) end
        PushHead(rows, L["要准备的材料"], 2)
        for _, s in ipairs(lv.shopping) do
            rows[#rows + 1] = {
                kind = "row", h = PD.ROW_H1, col = 2, it = { s[1] },
                text = FitR(DG.ItemName(s[1])), right = format("×%d", s[2] or 0),
            }
        end
        rows[#rows + 1] = { kind = "row", h = PD.ROW_H1, col = 2,
                            text = L["合计"], right = format(L["%d 件"], total) }
    end
    if lv.parts and #lv.parts > 0 then
        PushGap(rows, 8, 2)
        PushHead(rows, format(L["半成品（%d 种）"], #lv.parts), 2)
        for _, id in ipairs(lv.parts) do
            rows[#rows + 1] = { kind = "row", h = PD.ROW_H1, col = 2, it = { id },
                                text = FitR(DG.ItemName(id)) }
        end
    end
    if lv.sold and #lv.sold > 0 then
        PushGap(rows, 8, 2)
        PushHead(rows, L["商人直卖（无需自采）"], 2)
        for _, id in ipairs(lv.sold) do
            rows[#rows + 1] = { kind = "row", h = PD.ROW_H1, col = 2, it = { id },
                                text = FitR(DG.ItemName(id)) }
        end
    end
end

function PD.RowsLegacy(rows)
    local p = D.pro[PD.cur]
    if not (p and p.perks) then return end
    PushHead(rows, L["传承特权（13 个专业共用同一批，按 id 引用）"])
    for _, pid in ipairs(p.perks) do
        local pk = D.perks[pid]
        if pk then
            local open = PD.perkOpen[pid]
            local lines = { { pk[6] or "" } }
            if pk[8] then
                for _, u in ipairs(pk[8]) do lines[#lines + 1] = { u, 0.9, 0.7, 0.4 } end
            end
            rows[#rows + 1] = {
                kind = "row", icon = pk[2], text = pk[1] or "?",
                sub = (pk[6] or ""):sub(1, 90),
                right = format(L["满级 %s"], tostring(pk[4])),
                right2 = open and L["收起逐级文本"]
                                  or format(L["展开 %d 级文本"], #(pk[5] or {})),
                lines = lines,
                act = function()
                    PD.perkOpen[pid] = not PD.perkOpen[pid]
                    PD.Render()
                end,
            }
            if open and pk[5] then
                for i, t in ipairs(pk[5]) do
                    rows[#rows + 1] = { kind = "text", text = format("%d. %s", i, t),
                                        color = C_TEXT }
                end
            end
        end
    end
end

function PD.RowsNotes(rows)
    if PD.cur == "__index" then
        PushHead(rows, L["怎么读这份手册"])
        PushText(rows, L["左侧选专业、右侧切子页。子页按数据是否存在自动启用：采集类没有配方与升级路线（但有节点表），营地系统只有营地和说明。物品名与图标全部由客户端提供，客户端还没加载到的会先显示占位、随后自动补上。"], 12)
        PushGap(rows)
        PushHead(rows, L["数据版本"])
        PushText(rows, format(L["build %s · 更新于 %s"],
                              tostring(D.build or "?"), tostring(D.updated or "?")), 12)
        PushGap(rows)
        PushHead(rows, L["状态标签说明"])
        local seen, list = {}, {}
        for _, slug in ipairs(D.order or {}) do
            local p = D.pro[slug]
            if p and p.status and not seen[p.status] then
                seen[p.status] = true
                list[#list + 1] = p.status
            end
        end
        for _, st in ipairs(list) do
            rows[#rows + 1] = { kind = "text", text = "· " .. st, color = C_GREY }
        end
        return
    end
    local p = D.pro[PD.cur]
    if not p then return end
    PushHead(rows, L["状态"])
    rows[#rows + 1] = {
        kind = "row", h = PD.ROW_H1, text = p.status or L["未标注"],
        right = p.kind or "",
    }
    local function Block(title, list, color)
        if not (list and #list > 0) then return end
        PushGap(rows)
        PushHead(rows, title)
        for _, t in ipairs(list) do PushText(rows, "· " .. t, 12, color) end
    end
    Block(L["要点"], p.tips)
    Block(L["待核实"], p.verify, { 0.95, 0.78, 0.35 })
    Block(L["未收录"], p.unknowns, C_GREY)
    if p.steps and #p.steps > 0 then
        PushGap(rows)
        PushHead(rows, p.steps_title or L["怎么开始"])
        if p.steps_note then PushText(rows, p.steps_note, 12, C_GREY) end
        for i, st in ipairs(p.steps) do
            rows[#rows + 1] = {
                kind = "row", text = format("%d. %s", i, st[1] or ""), sub = st[2] or "",
                lines = { { st[1] or "" }, { st[2] or "", 0.85, 0.85, 0.85 } },
            }
        end
    end
    if p.racials and #p.racials > 0 then
        PushGap(rows)
        PushHead(rows, L["种族相关"])
        for _, rc in ipairs(p.racials) do PushText(rows, "· " .. (rc[3] or ""), 12) end
    end
end

function PD.RowsSettings(rows)
    PushHead(rows, L["升级页设置"])
    PushGap(rows, 2)
    PushText(rows, L["这里的开关只作用于「升级」页签里的制作路线（升级路线表），不影响其他页签。"], 11, C_GREY)
    PushGap(rows, 4)
    local defs = {
        { k = "greyPassed", name = L["已过段落灰显"],
          desc = L["上限低于当前技能的段落（如 42 级时的 1~15）整行灰显"],
          d1 = L["开启后：段名、出处、数量文字变暗，配方与材料图标去饱和，不再作为下一个要关注的制作目标；"],
          d2 = L["关闭后：所有段落恢复常规配色，不做灰显处理。"] },
        { k = "hlCurrent", name = L["当前段落高亮"],
          desc = L["上下限跨着当前技能的段落（如下一个要练的 15~58）加一圈主题色外框"],
          d1 = L["开启后：下一个要练的段落四周显示一圈主题绿描边，一眼定位当前制作路线；外框只是描边，不影响行内容与点击。"],
          d2 = L["关闭后：不显示外框，该段落样式与其他行一致。"] },
    }
    for _, d in ipairs(defs) do
        rows[#rows + 1] = {
            kind = "row", h = 40, col = 1,
            text = d.name,
            sub = d.desc,
            togKey = d.k,
            lines = { { d.name }, { d.desc, 0.7, 0.7, 0.7 }, { d.d1, 0.7, 0.7, 0.7 }, { d.d2, 0.7, 0.7, 0.7 } },
        }
        PushText(rows, d.d1, 11, C_GREY)
        PushText(rows, d.d2, 11, C_GREY)
        PushGap(rows, 6)
    end
end

function PD.PlaceSettingsToggles(rows)
    local n = math.min(#(rows or {}), PD.ROW_CAP)
    local ti = 0
    for i = 1, n do
        local spec = rows[i]
        if PD.setOpen and spec.togKey then
            ti = ti + 1
            local tg = PD.setToggles[ti]
            tg:ClearAllPoints()
            tg:SetPoint("RIGHT", PD.rows[i], "RIGHT", -8, 0)
            tg:SetFrameLevel((PD.rows[i]:GetFrameLevel() or 0) + 10)
            tg:SetChecked(PD.Setting(spec.togKey))
            tg.__key = spec.togKey
            tg:Show()
        end
    end
    for j = ti + 1, #PD.setToggles do PD.setToggles[j]:Hide() end
end

function PD.Render()
    if not (PD.built and PD.page) or not PD.cur then return end
    PD.PickNav()
    PD.PickTabs()

    local rows = {}
    local tool, handler = {}, nil
    PD.lvSplit = false
    PD.gridSplit = false
    PD.wantIndexGrid = false
    PD.wantBonusTable = false
    PD.hasSecs = false
    PD.splitLW, PD.splitRW = nil, nil
    PD.hideDivider = false
    PD.secCount = 0

    if PD.setOpen then
        PD.RowsSettings(rows)
    elseif PD.tab == "overview" then
        PD.lvSplit = (PD.cur ~= "__index")
        PD.wantIndexGrid = (PD.cur == "__index")
        PD.splitLW = math.floor((PD.RIGHT_W - 2 * PD.LIST_PAD - PD.OV_GUT) * PD.OV_SPLIT)
        PD.splitRW = PD.RIGHT_W - 2 * PD.LIST_PAD - PD.OV_GUT - PD.splitLW
        PD.hasSecs = true
        PD.hideDivider = true
        PD.RowsOverview(rows)
    elseif PD.tab == "camp" then
        local hasCamp = (D.pro[PD.cur] and D.pro[PD.cur].camp) and true or false
        if not hasCamp then PD.campView = "bonus" end
        tool = {}
        if hasCamp then
            tool[#tool + 1] = { key = "a", text = L["联盟"], on = PD.campView == "a" }
            tool[#tool + 1] = { key = "h", text = L["部落"], on = PD.campView == "h" }
            handler = function(k) PD.campView = k; PD.Render() end
        end
        if PD.campView == "bonus" then
            PD.hasSecs = false
            PushGap(rows, 6)
            PushHead(rows, L["全部专业的营地物件档位对照"], nil, 16)
            PD.wantBonusTable = true
        else
            PD.hasSecs = true
            PD.RowsCamp(rows, PD.campView)
        end
    elseif PD.tab == "recipe" then
        tool, handler = PD.RecipeTool(R[PD.cur])
        PD.RowsRecipe(rows)
    elseif PD.tab == "gather" then
        PD.gridSplit = (PD.cur == "fishing")
        PD.RowsGather(rows)
    elseif PD.tab == "leveling" then
        PD.lvSplit = true
        PD.RowsLeveling(rows)
    elseif PD.tab == "legacy" then
        PD.RowsLegacy(rows)
    else
        PD.RowsNotes(rows)
    end

    local toolH = PD.PaintTool(tool, handler)
    PD.Layout(toolH)

    PD.specs = rows
    PD.truncated = PD.PaintRows(rows)
    PD.PlaceSettingsToggles(rows)
    PD.scroll:SetVerticalScroll(0)
    PD.scroll:Show()
    PD.RequestRows(rows)
end

function PD.RequestRows(rows)
    if not DG.RequestItem then return end
    local wait = {}
    local function want(id)
        if not id then return end
        DG.RequestItem(id)
        if not select(2, DG.ItemName(id)) then wait[#wait + 1] = id end
    end
    local n = math.min(#rows, PD.ROW_CAP)
    for i = 1, n do
        local spec = rows[i]
        if spec.it then want(spec.it[1]) end
        for _, m in ipairs(spec._mats or {}) do want(m[1]) end
    end
    PD.notReady = (#wait > 0) and wait or nil
    if PD.notReady and not PD.sweeping then PD.ScheduleSweep() end
end

function PD.Show(slug)
    if slug ~= PD.cur then
        PD.cur = slug
        PD.toolKey = nil
        PD.campView = "a"
        PD.tab = "overview"
        PD.setOpen = false
    end
    PD.Render()
end

function PD.SetTab(key)
    PD.setOpen = false
    if not (PD.avail and PD.avail[key]) then return end
    PD.tab = key
    PD.Render()
end

function PD.Open()
    if not PD.built then return end
    if not PD.cur then PD.cur = "__index" end
    PD.Render()
end

function PD.Refresh()
    if not PD.built then return end
    if not PD.cur then PD.cur = "__index" end
    PD.Render()
end
