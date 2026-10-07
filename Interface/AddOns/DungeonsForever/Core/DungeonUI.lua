-- =============================================================================
-- 无限副本手册 · 界面层
-- 唯一内容页 = 副本手册（列表 / 详情 / 掉落 / 任务）。
-- ⚠️ 几何值一律原值：改一个像素整页位移。
-- =============================================================================

local _, ns = ...

local L = ns.L

if not ns.IsTitan then return end

local U = {}
ns.DungeonUI = U

local FONT_BASE
local CONTENT_W = 960
local PAGE_INSET = 12
local HDR_H = 142
local CARD_H = 484
local CREDIT_H = 22
local CONTENT_H = HDR_H + CARD_H + CREDIT_H

local ROW_SUB = 0
local ROW_CLASS = 30

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local C_GOLD = { 1, 0.82, 0.0 }
local C_GREEN = { 0.25, 0.85, 0.35 }
local C_RED = { 0.9, 0.35, 0.35 }
local C_GREY = { 0.55, 0.55, 0.55 }
local C_DIM = { 0.63, 0.63, 0.63 }
local C_DARKGREY = { 0.30, 0.30, 0.30 }
local C_WHITE = { 1, 1, 1 }
local C_TEXT = { 0.88, 0.88, 0.88 }

local function DB()
    DungeonsForeverDB = DungeonsForeverDB or {}
    local s = DungeonsForeverDB.dungeon
    if not s then
        s = {}
        DungeonsForeverDB.dungeon = s
    end
    return s
end

local function IsHui()
    return ns.huiTheme == "hui"
end

local function Fnt(size)
    return FONT_BASE, size, ns.hui.FontFlags("OUTLINE")
end

local function Unpack(c)
    return c[1], c[2], c[3]
end

local function MakeFS(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(Fnt(size))
    if color then fs:SetTextColor(Unpack(color)) end
    if justify then fs:SetJustifyH(justify) end
    return fs
end

local function NewButton(parent, text, w, h, size)
    local bt = ns.CreateButton(parent)
    bt:SetSize(w, h)
    if text then bt:SetText(text) end
    bt:GetFontString():SetFont(Fnt(size or 13))
    return bt
end

local function MakeOutline(bt, r, g, b)
    if IsHui() and ns.hui and ns.hui.BuildRoundBorder then
        local f = CreateFrame("Frame", nil, bt)
        f:SetAllPoints()
        f:SetFrameLevel((bt:GetFrameLevel() or 0) + 5)
        local pieces = ns.hui.BuildRoundBorder(f, 6, { r or 1, g or 1, b or 1, 1 }, f, "OVERLAY", "both", 1) or {}
        for _, tex in ipairs(pieces) do tex:SetShown(true) end
        f:Hide()
        bt.__outlineFrame = f
        bt.__bars = pieces
        return
    end
    bt.__outlineFrame = false
    local bars = {}
    local function mk(w, h, pt1, ox1, oy1, pt2, ox2, oy2)
        local tex = bt:CreateTexture(nil, "OVERLAY")
        tex:SetTexture("Interface\\Buttons\\WHITE8x8")
        tex:SetPoint(pt1, bt, pt1, ox1, oy1)
        tex:SetPoint(pt2, bt, pt2, ox2, oy2)
        if w then tex:SetWidth(w) end
        if h then tex:SetHeight(h) end
        tex:Hide()
        bars[#bars + 1] = tex
    end
    mk(nil, 2, "TOPLEFT", -2, 2, "TOPRIGHT", 2, 2)
    mk(nil, 2, "BOTTOMLEFT", -2, -2, "BOTTOMRIGHT", 2, -2)
    mk(2, nil, "TOPLEFT", -2, 0, "BOTTOMLEFT", -2, 0)
    mk(2, nil, "TOPRIGHT", 2, 0, "BOTTOMRIGHT", 2, 0)
    bt.__bars = bars
    return bars
end

local function SetOutline(bt, on, r, g, b)
    if bt.__outlineFrame then
        bt.__outlineFrame:SetShown(on and true or false)
        return
    end
    for _, tex in ipairs(bt.__bars or {}) do
        if on then
            tex:SetColorTexture(r or 1, g or 1, b or 1, 1)
            tex:Show()
        else
            tex:Hide()
        end
    end
end

local function SetTip(frame, tip)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function EnsureContent()
    if U.panel then return U.panel end
    local host = ns.TalentSimFrame
    local panel = CreateFrame("Frame", nil, host, "BackdropTemplate")
    panel:SetSize(CONTENT_W, CONTENT_H)
    panel:SetPoint("TOP", host, "TOP", 0, -(IsHui() and 44 or 76))
    if IsHui() and ns.hui and ns.hui.SkinPopup then
        ns.hui.SkinPopup(panel, 8)
    end
    U.panel = panel
    return panel
end
local SOURCE_POPUP = "DungeonsForever_SourceURL"
local pendingSourceURL = "https://www.wowhead.com/forever"

local function ShowSourceURL(url)
    pendingSourceURL = url
    if not StaticPopupDialogs[SOURCE_POPUP] then
        StaticPopupDialogs[SOURCE_POPUP] = {
            text = L["复制网址"],
            button1 = L["关闭"],
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            hasEditBox = true,
            editBoxWidth = 260,
            OnShow = function(self)
                local edit = self.EditBox or self.editBox
                edit:SetText(pendingSourceURL)
                edit:HighlightText()
                edit:SetFocus()
            end,
            EditBoxOnEnterPressed = function(self)
                self:GetParent():Hide()
            end,
            EditBoxOnEscapePressed = function(self)
                self:GetParent():Hide()
            end,
        }
    end
    StaticPopup_Show(SOURCE_POPUP)
end

local function MakeSourceCredit(panel, label, url, prev)
    local fs = MakeFS(panel, 11, C_GREY, "RIGHT")
    if prev then
        fs:SetPoint("RIGHT", prev, "LEFT", -18, 0)
    else
        fs:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, -4)
    end
    fs:SetText(label)
    local btn = CreateFrame("Button", nil, panel)
    btn:SetPoint("TOPLEFT", fs, "TOPLEFT", -4, 4)
    btn:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 4, -4)
    btn:SetHitRectInsets(0, 0, 0, 0)
    btn:SetScript("OnEnter", function(self)
        fs:SetTextColor(0.9, 0.9, 0.9)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["点击复制数据来源网址"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        fs:SetTextColor(Unpack(C_GREY))
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function() ShowSourceURL(url) end)
    U.sourceCredits[#U.sourceCredits + 1] = { fs = fs, btn = btn, url = url, label = label }
    return fs
end

local DG = {}
ns.DungeonModule = DG

function DG.RowPaint(f)
    if IsHui() then
        local l2 = ns.hui.layer.L2
        f:SetBackdropColor(l2[1], l2[2], l2[3], 0.95)
        f:SetBackdropBorderColor(1, 1, 1, 0.10)
    else
        f:SetBackdropColor(0, 0, 0, 0.35)
        f:SetBackdropBorderColor(0.30, 0.30, 0.30, 1)
    end
end

DG.AX0, DG.AX1, DG.LO, DG.HI = 78, 838, 13, 60
DG.BARMAX, DG.MINW, DG.GAPX = 924, 100, 4
DG.LANE_H, DG.BAR_H = 35, 31
DG.CUR_H, DG.TICK_H, DG.BOT_PAD = 16, 20, 10
DG.TICKS = { 13, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60 }
DG.NEW_EDGE = { 0.19, 0.62, 0.47 }
DG.OLD_EDGE = { 0.30, 0.35, 0.50 }
DG.NOART_COLOR = { 0.26, 0.28, 0.32 }

DG.HERO_H = 120
DG.HERO_PLATE_H = 40
DG.HERO_TITLE_Y, DG.HERO_META_Y = 84, 104
DG.FILTER_Y = DG.HERO_H + 8
DG.SCROLL_Y = DG.FILTER_Y + 34
DG.GUIDE_TOP_Y = DG.HERO_H + 8
DG.HERO_TEX_OFFICIAL = { 0.02, 0.98, 0.422, 0.668 }
DG.HERO_TEX_CAMELOT = { 0.00, 1.00, 0.372, 0.628 }
DG.WIDE_TEX_OFFICIAL = { 0.115, 0.885, 0.295, 0.805 }
DG.WIDE_TEX_CAMELOT  = { 0.000, 1.000, 0.169, 0.831 }
DG.HERO_FDID = {
    ragefire_chasm = 131862, wailing_caverns = 131882, the_deadmines = 131833,
    shadowfang_keep = 131869, blackfathom_deeps = 131823, the_stockade = 131870,
    gnomeregan = 131841, razorfen_kraul = 131865, razorfen_downs = 131864,
    sm_graveyard = 131852, sm_library = 131852, sm_armory = 131852, sm_cathedral = 131852,
    uldaman = 131876, zul_farrak = 131885, maraudon = 131850, sunken_temple = 131872,
    blackrock_depths = 131824, dire_maul_east = 131835, dire_maul_north = 131835,
    dire_maul_west = 131835, lower_blackrock_spire = 131825, upper_blackrock_spire = 131825,
    scholomance = 131868, stratholme_main = 131871, stratholme_service = 131859,
}
DG.HERO_CAMELOT = {
    city_of_dalaran = 7963775,
    excavation_wetlands = 7963777,
    ruins_of_lordaeron = 7963782,
    hall_of_thanes = 7963781,
}

function DG.ArtOf(d, kind)
    local wide = (kind == "wide")
    if ns.IsForever then
        local cam = DG.HERO_CAMELOT[d.id]
        if cam then return cam, (wide and DG.WIDE_TEX_CAMELOT or DG.HERO_TEX_CAMELOT) end
    end
    local fd = DG.HERO_FDID[d.id]
    if fd then return fd, (wide and DG.WIDE_TEX_OFFICIAL or DG.HERO_TEX_OFFICIAL) end
    return nil
end

function DG.PaintArt(tex, d, kind)
    local art, coord = DG.ArtOf(d, kind)
    if art then
        tex:SetTexture(art)
        if coord then tex:SetTexCoord(coord[1], coord[2], coord[3], coord[4])
        else tex:SetTexCoord(0, 1, 0, 1) end
        return true
    end
    tex:SetColorTexture(DG.NOART_COLOR[1], DG.NOART_COLOR[2], DG.NOART_COLOR[3], 1)
    return false
end

function DG.X(level)
    return DG.AX0 + (level - DG.LO) / (DG.HI - DG.LO) * (DG.AX1 - DG.AX0)
end

function DG.Pack(list)
    local sorted = {}
    for _, d in ipairs(list) do sorted[#sorted + 1] = d end
    table.sort(sorted, function(a, b)
        if a.levelMin ~= b.levelMin then return a.levelMin < b.levelMin end
        return a.levelMax < b.levelMax
    end)
    local right, out = {}, {}
    for _, d in ipairs(sorted) do
        local x1 = DG.X(d.levelMin)
        local x2 = math.max(DG.X(d.levelMax), x1 + DG.MINW)
        if x2 > DG.BARMAX then x2 = DG.BARMAX end
        local lane
        for i = 1, #right do
            if right[i] + DG.GAPX <= x1 then
                lane = i
                break
            end
        end
        if not lane then
            right[#right + 1] = 0
            lane = #right
        end
        right[lane] = x2
        out[#out + 1] = { d = d, lane = lane, x1 = x1, x2 = x2 }
    end
    return out, #right
end

DG.CARD_COLS, DG.CARD_H, DG.CARD_GAP = 5, 58, 8
DG.CHILD_W = CONTENT_W - PAGE_INSET * 2 - 28
DG.CARD_W = math.floor((DG.CHILD_W - (DG.CARD_COLS - 1) * DG.CARD_GAP) / DG.CARD_COLS)

function DG.WheelScroll(scroll, child, delta)
    if not (scroll and child) then return end
    local maxScroll = math.max(0, child:GetHeight() - scroll:GetHeight())
    scroll:SetVerticalScroll(math.max(0, math.min(maxScroll, scroll:GetVerticalScroll() - delta * 48)))
end

function DG.NewCard(parent)
    local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
    card:SetSize(DG.CARD_W, DG.CARD_H)
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    card:SetBackdropColor(0, 0, 0, 0)
    card.art = card:CreateTexture(nil, "BACKGROUND")
    card.art:SetAllPoints()
    card.dim = card:CreateTexture(nil, "ARTWORK")
    card.dim:SetAllPoints()
    card.stripe = card:CreateTexture(nil, "OVERLAY")
    card.stripe:SetWidth(3)
    card.stripe:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
    card.stripe:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 1, 1)
    card.stripe:SetColorTexture(DG.NEW_EDGE[1], DG.NEW_EDGE[2], DG.NEW_EDGE[3], 1)
    card.plate = card:CreateTexture(nil, "ARTWORK")
    card.plate:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 1, 1)
    card.plate:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -1, 1)
    card.plate:SetHeight(20)
    card.plate:SetColorTexture(0, 0, 0, 0.55)
    card.name = MakeFS(card, 16, C_WHITE, "LEFT")
    card.name:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -5)
    card.name:SetWordWrap(false)
    card.meta = MakeFS(card, 14, C_GREY, "LEFT")
    card.meta:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 8, 3)
    card.meta:SetShadowColor(0, 0, 0, 1)
    card.meta:SetShadowOffset(1, -1)
    card.badge = MakeFS(card, 11, { 0.42, 0.94, 0.62 }, "RIGHT")
    card.badge:SetPoint("TOPRIGHT", card, "TOPRIGHT", -7, -4)
    card.badge:SetText(L["新"])
    card:SetScript("OnEnter", function(self)
        if not self.__tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(self.__tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function() GameTooltip:Hide() end)
    card:EnableMouseWheel(true)
    card:SetScript("OnMouseWheel", function(self, delta)
        DG.WheelScroll(U.dungeonListScroll, U.dungeonListChild, delta)
    end)
    card:SetScript("OnClick", function(self)
        if self.__d then U:ShowDungeonDetail(self.__d) end
        ns.PlaySound(1)
    end)
    return card
end

function DG.GroupOf(d, lv)
    if d.levelMin > lv then return "up" end
    if d.levelMax and lv <= d.levelMax then return "rec" end
    return "now"
end

function DG.BuildList()
    local data = ns.DungeonData
    local scroll, child, pool = U.dungeonListScroll, U.dungeonListChild, U.dungeonListPool
    if not (data and data.dungeons and scroll and child and pool) then return end

    local lv = UnitLevel("player") or 0
    U.dungeonListLevel = lv

    local cols, gx = DG.CARD_COLS, DG.CARD_GAP
    local cardW = DG.CARD_W
    local nCard, nHdr = 0, 0

    local collapsed = U.dungeonListCollapsed
    if type(collapsed) ~= "table" then collapsed = {} end
    U.dungeonListCollapsed = collapsed

    local groups = {
        { key = "rec", label = L["推荐"],         hint = L["等级正合适，优先前往"], color = C_GOLD },
        { key = "now", label = L["现在可以进入"], hint = L["等级已超出，仍可前往"], color = { 0.74, 0.80, 0.90 } },
        { key = "up",  label = L["还需升级"],     hint = L["等级达到下限后开放"],   color = { 0.74, 0.72, 0.68 } },
    }
    local buckets = { now = {}, rec = {}, up = {} }
    for _, d in ipairs(data.dungeons) do
        local b = buckets[DG.GroupOf(d, lv)]
        b[#b + 1] = d
    end

    local y = -4
    for _, g in ipairs(groups) do
        local list = buckets[g.key]
        table.sort(list, function(a, b)
            if a.levelMin ~= b.levelMin then return a.levelMin < b.levelMin end
            return a.levelMax < b.levelMax
        end)

        nHdr = nHdr + 1
        local ui = pool.hdr[nHdr]
        if not ui then
            ui = {
                txt = MakeFS(child, 16, C_GOLD, "LEFT"),
                hint = MakeFS(child, 14, C_DIM, "RIGHT"),
                div = child:CreateTexture(nil, "ARTWORK"),
            }
            ui.div:SetHeight(1)
            ui.arrD = child:CreateTexture(nil, "ARTWORK")
            ui.arrD:SetSize(10, 10)
            ui.arrD:SetTexture("Interface/AddOns/DungeonsForever/Media/textures/arrow.tga")
            ui.arrD:SetRotation(math.pi)
            ui.arrU = child:CreateTexture(nil, "ARTWORK")
            ui.arrU:SetSize(10, 10)
            ui.arrU:SetTexture("Interface/AddOns/DungeonsForever/Media/textures/arrow.tga")
            ui.hit = CreateFrame("Button", nil, child)
            ui.hit:SetHeight(26)
            ui.hit:RegisterForClicks("LeftButtonUp")
            ui.hit:SetScript("OnClick", function(self)
                local key = self.__key
                if not key then return end
                collapsed[key] = not collapsed[key] or nil
                ns.PlaySound(1)
                DG.BuildList()
            end)
            ui.hit:SetScript("OnEnter", function(self)
                if not self.__key then return end
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(L["点击折叠 / 展开该组"], 1, 1, 1, true)
                GameTooltip:Show()
            end)
            ui.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
            ui.hit:EnableMouseWheel(true)
            ui.hit:SetScript("OnMouseWheel", function(self, delta)
                DG.WheelScroll(U.dungeonListScroll, U.dungeonListChild, delta)
            end)
            pool.hdr[nHdr] = ui
        end
        local isClosed = collapsed[g.key] == true
        ui.txt:SetTextColor(Unpack(g.color))
        ui.txt:SetText(g.label .. " · " .. #list .. L[" 个"])
        ui.txt:ClearAllPoints()
        ui.txt:SetPoint("TOPLEFT", child, "TOPLEFT", 14, y)
        for _, at in ipairs({ ui.arrD, ui.arrU }) do
            at:SetVertexColor(g.color[1], g.color[2], g.color[3])
            at:ClearAllPoints()
            at:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y - 2)
        end
        ui.arrD:SetShown(not isClosed)
        ui.arrU:SetShown(isClosed)
        ui.hint:SetText(g.hint)
        ui.hint:ClearAllPoints()
        ui.hint:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, y - 1)
        ui.div:SetColorTexture(g.color[1], g.color[2], g.color[3], 0.30)
        ui.div:ClearAllPoints()
        ui.div:SetPoint("TOPLEFT", ui.txt, "BOTTOMLEFT", -14, -6)
        ui.div:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        ui.div:Show()
        ui.hit:ClearAllPoints()
        ui.hit:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
        ui.hit:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        ui.hit.__key = g.key
        ui.hit:Show()
        y = y - 28

        if isClosed then
            y = y - 2
        else
            for i, d in ipairs(list) do
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            nCard = nCard + 1
            local card = pool.card[nCard]
            if not card then
                card = DG.NewCard(child)
                pool.card[nCard] = card
            end
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", child, "TOPLEFT", col * (cardW + gx), y - row * (DG.CARD_H + gx))
            card:SetBackdropBorderColor(g.color[1], g.color[2], g.color[3], g.key == "up" and 0.30 or 0.70)
            DG.PaintArt(card.art, d, "wide")
            card.dim:SetColorTexture(0, 0, 0,
                (g.key == "rec") and 0.38 or ((g.key == "now") and 0.52 or 0.66))
            card.stripe:SetShown(d.isNew and true or false)
            card.name:SetTextColor(Unpack((g.key == "up") and C_DIM or C_WHITE))
            card.name:SetText(d.name)
            card.name:ClearAllPoints()
            card.name:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -5)
            card.name:SetPoint("RIGHT", card, "RIGHT", d.isNew and -20 or -8, 0)
            card.meta:SetText(d.levelMin .. "–" .. d.levelMax ..
                (d.bossCount and (" · BOSS " .. d.bossCount) or ""))
            card.badge:SetShown(d.isNew and true or false)
            card.__tip = d.name .. "  " .. d.nameEn .. "\n" ..
                format(L["等级 %d–%d · %s"], d.levelMin, d.levelMax, d.zone or L["位置未知"])
            card.__d = d
            card:Show()
        end

            local rows = math.ceil(#list / cols)
            y = y - rows * (DG.CARD_H + gx) - 12
        end
    end

    for i = nCard + 1, #pool.card do pool.card[i]:Hide() end
    for i = nHdr + 1, #pool.hdr do
        pool.hdr[i].txt:Hide()
        pool.hdr[i].hint:Hide()
        pool.hdr[i].div:Hide()
        pool.hdr[i].arrD:Hide()
        pool.hdr[i].arrU:Hide()
        pool.hdr[i].hit:Hide()
    end
    child:SetHeight(math.max(10, -y + 10))
end

function DG.BuildDungeons()
    if U.dungeonBuilt then return end
    local data = ns.DungeonData
    if not (data and data.dungeons and #data.dungeons > 0) then return end
    U.dungeonBuilt = true
    local page = U.dungeonPage

    local SUBTAB_Y = ROW_CLASS
    local BODY_Y = SUBTAB_Y + 36
    local listW = CONTENT_W - PAGE_INSET * 2

    U.dungeonSum = MakeFS(page, 14, C_GREY, "RIGHT")
    U.dungeonSum:SetPoint("TOPRIGHT", page, "TOPRIGHT", -6, -(SUBTAB_Y + 5))

    local SW, SGAP = 86, 6
    local views = {
        { key = "list",     text = L["列表"], tip = L["场景图卡片墙：按能否进入分三组，点卡片看详情"] },
        { key = "overview", text = L["总览"], tip = L["按等级排布，一眼看清全部副本分布"] },
    }
    U.dungeonViewBtns = {}
    for i, def in ipairs(views) do
        local bt = NewButton(page, def.text, SW, 24, 14)
        bt:SetPoint("TOPLEFT", page, "TOPLEFT", 6 + (i - 1) * (SW + SGAP), -SUBTAB_Y)
        MakeOutline(bt, 1, 0.82, 0)
        bt.__huiKeepTextColor = true
        U.dungeonViewBtns[def.key] = bt
        bt:SetScript("OnClick", function()
            U:SetDungeonView(def.key)
            ns.PlaySound(1)
        end)
        SetTip(bt, def.tip)
    end

    local listScroll = CreateFrame("ScrollFrame", nil, page)
    listScroll:SetPoint("TOPLEFT", page, "TOPLEFT", PAGE_INSET, -BODY_Y)
    listScroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -PAGE_INSET, PAGE_INSET)
    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(DG.CHILD_W, 10)
    listScroll:SetScrollChild(listChild)
    listScroll:EnableMouseWheel(true)
    listScroll:SetScript("OnMouseWheel", function(self, delta)
        local ch = U.dungeonListChild
        if not ch then return end
        local maxScroll = math.max(0, ch:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 48)))
    end)
    U.dungeonListScroll = listScroll
    U.dungeonListChild = listChild
    U.dungeonListPool = { card = {}, hdr = {} }

    local detail = CreateFrame("Frame", nil, page)
    detail:SetPoint("TOPLEFT", page, "TOPLEFT", PAGE_INSET, -BODY_Y)
    detail:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -PAGE_INSET, PAGE_INSET)
    detail:Hide()
    U.dungeonDetail = detail


    local oscroll = CreateFrame("ScrollFrame", nil, page)
    oscroll:SetPoint("TOPLEFT", page, "TOPLEFT", PAGE_INSET, -BODY_Y)
    oscroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -PAGE_INSET, PAGE_INSET)
    local ochild = CreateFrame("Frame", nil, oscroll)
    ochild:SetSize(listW - 20, 10)
    oscroll:SetScrollChild(ochild)
    oscroll:EnableMouseWheel(true)
    oscroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, ochild:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 48)))
    end)
    U.dungeonOverviewScroll = oscroll
    U.dungeonOverviewChild = ochild
    oscroll:Hide()
    -- ★ 懒建：总览内容见 DG.EnsureOverviewBuilt()，首屏不再整包建 35 条

    DG.BuildList()
end

-- ══════════════════════════════════════════════════════════════════════════
-- ★★ 分帧器：把一串「建帧块」摊到随后的空闲帧里逐块执行。
--   ★ 同步兜底：C_Timer 不可用（离线 harness / 极端环境）时**递归同步跑完**，
--     调用方返回时一切就绪 —— 断言因此看到的仍是「全都建好了」，无需感知分帧。
--   ★ 幂等由各子块自己的 built 闸保证：若分帧还没轮到就被「按需同步」抢先建过，
--     轮到执行时会直接 return，不重复建。
-- ══════════════════════════════════════════════════════════════════════════
-- ══════════════════════════════════════════════════════════════════════════
-- ★★★ 第五刀 · 统一分帧调度器 DG.Loader（2026-10-03「有些用户电脑很差」）
--   ──────────────────────────────────────────────────────────────────────
--   前四刀解决的是「哪一帧付哪笔钱」，但**单帧里到底建多少**一直没有上限：
--   黑石深渊点副本那一帧要建 249 个对象（详情外壳 + 168 个掉落行帧）—— 好机器
--   只是打个顿，差电脑主线程一次阻塞上百毫秒 ⇒ Windows 判定无响应、整窗涂灰。
--
--   DG.Loader 给每一帧加两道闸，任一触发就立刻停手、剩下的排到下一帧：
--     · 时间闸 debugprofilestop：**真机自适应** —— 好机器一帧多跑几个、差机器
--       一帧少跑几个。这正是「有些用户电脑很差」的正解：不必猜用户配置，也不必
--       让所有人陪跑最慢的节奏。
--     · 数量闸 DG.LOOT_ROW_FRAME_CAP / DG.CARD_POOL_CAP：计时口不可用 / 计时异常
--       时的兜底，防一帧失控（离线桩就走这条）。
--
--   ★★ 单位必须是**毫秒，不是个数**：一个空 frame 约 0.05ms，而一次首次贴图
--      加载能到 2ms —— 差 20 倍以上。按「个数」分帧，碰上重对象照样卡死。
--   ★★ 同步兜底不破：C_Timer 不可用（离线 harness / 极端环境）时 pump 一路跑到底，
--      「调用方返回时一切就绪」这条契约不变 ⇒ 全部离线断言不受影响。
-- ══════════════════════════════════════════════════════════════════════════
DG.Loader = {
    budgetMs = 4,       -- 单块内的时间预算（ms）：块内循环据此停手，剩下的排到下一帧
    preset   = "normal",
}
DG.LOADER_PRESETS = { eco = 2, normal = 4, turbo = 8 }
DG.LOADER_LABEL = { eco = L["省电"], normal = L["标准"], turbo = L["激进"] }

function DG.Loader.SetBudget(k)
    local v = DG.LOADER_PRESETS[k]
    if type(v) ~= "number" then return false end
    DG.Loader.budgetMs = v
    DG.Loader.preset = k
    DB().loadBudget = (k ~= "normal") and k or nil
    return true
end

-- 读档（幂等；U:Build 里调一次）
function DG.Loader.Init()
    local k = DB().loadBudget
    if DG.LOADER_PRESETS[k] then
        DG.Loader.budgetMs = DG.LOADER_PRESETS[k]
        DG.Loader.preset = k
    else
        DG.Loader.preset = "normal"
        DG.Loader.budgetMs = DG.LOADER_PRESETS.normal
    end
end

-- 计时口：真机 debugprofilestop 返毫秒；离线 / 极端环境没有它 ⇒ 只靠数量闸。
function DG.__nowMs()
    local f = debugprofilestop
    if type(f) == "function" then
        local ok, v = pcall(f)
        if ok and type(v) == "number" then return v end
    end
    return nil
end

-- ══ 载入进度条 ═══════════════════════════════════════════════════════════
--   ★ 用户 2026-10-03 拍板「顶部细条（像浏览器加载）」：**不遮内容** ——
--     骨架和已经建好的部分都能看见。所以这里没有遮罩，只有两样东西：
--       · 内容区上缘 3px 的细进度条；满进度即时消失。
--       · 内容区右下角一枚状态胶囊（「正在载入… NN%」+「跳过」）。
--     胶囊落右下角而不是右上：顶部那两排挤着页签 / 筛选 / 视图按钮，浮在那里
--     会压住可点控件（本插件版式最密的区域）。
--   ★ 跳过 = **只撤进度条，剩下的继续在后台分帧建** —— 不走「一次啃完」那条路
--     （那就等于把卡死还回来），也不丢数据（列表随后自己补齐）。
-- ══════════════════════════════════════════════════════════════════════════
DG.Gate = { on = false, total = 0, done = 0, minSteps = 24, skipped = false, w = CONTENT_W }

function DG.Gate.Ensure()
    if DG.Gate.bar then return true end
    local panel = U.panel or (U.dungeonPage and U.dungeonPage:GetParent())
    if not panel then return false end
    -- ★★ 贴主窗口最上边框（2026-10-04 用户选方案 A）：锚 host（窗体 1000 宽）而不是
    --   内容面板 —— 面板首行内容紧贴面板顶，3px 条压内容；窗沿这条与内容零重叠。
    --   左右各缩进 8px 躲开 hui 窗皮的圆角；填充宽度按「窗宽 - 16」现算
    --   （桩环境测量 API 返回表值 ⇒ type 守卫 + 常量兜底，见 2026-10-03 探索页教训）。
    local host = panel:GetParent() or panel
    local bar = CreateFrame("Frame", nil, host)
    bar:SetFrameLevel(host:GetFrameLevel() + 20)
    bar:SetPoint("TOPLEFT", host, "TOPLEFT", 8, 0)
    bar:SetPoint("TOPRIGHT", host, "TOPRIGHT", -8, 0)
    bar:SetHeight(3)
    do
        local gw = 1000
        local mw = host.GetWidth and host:GetWidth()
        if type(mw) == "number" and mw > 0 then gw = mw end
        DG.Gate.w = gw - 16
    end
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0, 0, 0, 0.45)
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    bar.fill:SetWidth(1)
    bar.fill:SetColorTexture(Unpack(C_GOLD))
    bar:Hide()
    DG.Gate.bar = bar

    local pill = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    pill:SetFrameLevel(panel:GetFrameLevel() + 21)
    pill:SetSize(186, 26)
    pill:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 10)
    pill:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    pill:SetBackdropColor(0, 0, 0, 0.72)
    pill:SetBackdropBorderColor(1, 0.82, 0, 0.45)
    -- ★ 圆角 8 ≥ 本插件铁律下限；非 hui 主题下上面那套纯色底 + 1px 描边就是兜底外观。
    if IsHui() and ns.hui and ns.hui.SkinPopup then
        ns.hui.SkinPopup(pill, 8)
    end
    pill.text = MakeFS(pill, 12, C_TEXT, "LEFT")
    pill.text:SetPoint("LEFT", pill, "LEFT", 10, 0)
    do
        local sk = CreateFrame("Button", nil, pill)
        sk:SetSize(48, 18)
        sk:SetPoint("RIGHT", pill, "RIGHT", -5, 0)
        local sl = MakeFS(sk, 12, C_GOLD, "CENTER")
        sl:SetPoint("CENTER", sk, "CENTER", 0, 0)
        sl:SetText(L["跳过"])
        sk:SetScript("OnClick", function() DG.Gate.Skip() end)
        pill.skip = sk
    end
    pill:Hide()
    DG.Gate.pill = pill
    return true
end

function DG.Gate.Paint()
    local bar, pill = DG.Gate.bar, DG.Gate.pill
    local total = DG.Gate.total
    local pct = 0
    if total > 0 then pct = math.floor(DG.Gate.done / total * 100 + 0.5) end
    if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
    if bar then
        bar.fill:SetWidth(math.max(1, math.floor(DG.Gate.w * pct / 100)))
    end
    if pill and pill.text then
        pill.text:SetText(L["正在载入…"] .. " " .. pct .. "%")
    end
end

function DG.Gate.HideUI()
    if DG.Gate.bar then DG.Gate.bar:Hide() end
    if DG.Gate.pill then DG.Gate.pill:Hide() end
end

-- 进度分母**入队时就算好**、只增不减；量太小则走快速通道（不闪进度条）。
function DG.Gate.Begin(n)
    DG.Gate.total = n or 0
    DG.Gate.done = 0
    DG.Gate.skipped = false
    if DG.Gate.total < DG.Gate.minSteps then return end
    DG.Gate.on = true
    if DG.Gate.Ensure() then
        DG.Gate.bar:Show()
        DG.Gate.pill:Show()
    end
    DG.Gate.Paint()
end

function DG.Gate.Advance(k)
    DG.Gate.done = DG.Gate.done + (k or 1)
    if DG.Gate.on then DG.Gate.Paint() end
end

function DG.Gate.Skip()
    DG.Gate.skipped = true
    DG.Gate.on = false
    DG.Gate.HideUI()
    if DG.DEMO_SAVE then DG.Loader.EndDemo() end
end

function DG.Gate.Finish()
    DG.Gate.done = DG.Gate.total
    DG.Gate.on = false
    DG.Gate.HideUI()
    -- ★ 演示模式（/dfgate demo）收工：把临时放宽的三道闸门还原回正式值。
    if DG.DEMO_SAVE then DG.Loader.EndDemo() end
end

-- 载入速度档位：省电 2ms / 标准 4ms / 激进 8ms（默认标准）。
-- ★ 三档的单帧耗时都远低于卡顿阈值（Windows 约 200ms 才判无响应）——
--   档位只决定「总时长」，不决定「会不会卡」。
if type(SlashCmdList) == "table" then
    SLASH_DUNGEONSFOREVERSPEED1 = "/dfspeed"
    SlashCmdList["DUNGEONSFOREVERSPEED"] = function(msg)
        local k = tostring(msg or ""):lower():gsub("%s+", "")
        if DG.LOADER_PRESETS[k] then
            DG.Loader.SetBudget(k)
            print("|cff46bf72[无限副本手册]|r " .. L["载入速度"] .. " = "
                  .. (DG.LOADER_LABEL[k] or k) .. "（" .. DG.LOADER_PRESETS[k] .. "ms/帧）")
            return
        end
        print("|cff46bf72[无限副本手册]|r " .. L["载入速度"] .. "："
              .. L["省电"] .. " / " .. L["标准"] .. " / " .. L["激进"]
              .. "（" .. L["当前"] .. " = " .. (DG.LOADER_LABEL[DG.Loader.preset] or "standard") .. "）")
    end
end

-- ★ 行池「待建表」：渲染时算好版式、把还没建的行帧记在这里，随后按每帧预算逐批建。
--   ★ 每轮渲染开头**整体重置** —— 上一轮排下但还没建的行（比如玩家已经点到别的副本）
--     必须丢掉，否则它们会在新页面上冒出来。
DG.__pendRows = {}

-- ★★★ 第五刀：待建行帧的落地与调度 -------------------------------------------
DG.GATE_MIN_SHOW = 24     -- 少于这么多行不闪进度条（闪一下反而比不闪更难受）
DG.ROW_SYNC_MAX = 20      -- 少于这么多行直接同步建完（一帧十几个对象无所谓）

-- 单个待建行：建帧 + 塞进池 + 上数据。**帧已经在池里就跳过**（幂等）。
function DG.RealizePendingRow(e)
    local rows = U.dungeonDetailPool and U.dungeonDetailPool.item
    if not (rows and e) or rows[e.idx] then return end
    local ok, r = pcall(e.make)
    if ok and r then
        rows[e.idx] = r
        if e.paint then pcall(e.paint, r) end
    end
end

-- 逐批建（每帧受 DG.Loader 的时间预算 + DG.LOOT_ROW_FRAME_CAP 夹住）。
function DG.BuildPendRows()
    local list = DG.__pendRows
    local rows = U.dungeonDetailPool and U.dungeonDetailPool.item
    if not (list and rows) then
        DG.__pendRows = {}
        DG.Gate.Finish()
        return
    end
    local t0 = DG.__nowMs()
    local left = DG.LOOT_ROW_FRAME_CAP
    while #list > 0 and left > 0 do
        DG.RealizePendingRow(table.remove(list, 1))
        DG.Gate.Advance(1)
        left = left - 1
        local t1 = t0 and DG.__nowMs()
        if t1 and (t1 - t0) >= DG.Loader.budgetMs then break end
    end
    if #list > 0 then
        DG.PushStep(DG.BuildPendRows)
    else
        DG.Gate.Finish()
    end
end

-- 渲染收尾入口：量小同步建完（快速通道，不闪进度条）；量大交分帧器 + 进度条。
function DG.FlushPendingRows()
    local n = #DG.__pendRows
    if n == 0 then
        DG.Gate.Finish()
        return
    end
    if n < DG.ROW_SYNC_MAX then
        for k = 1, n do DG.RealizePendingRow(DG.__pendRows[k]) end
        DG.__pendRows = {}
        DG.Gate.Finish()
        return
    end
    DG.Gate.Begin(n)
    DG.PushStep(DG.BuildPendRows)
    DG.RunSteps()
end

DG.LOOT_ROW_FRAME_CAP = 16      -- 单块最多建这么多行帧（无计时口时的数量兜底闸）

-- ══ 载入闸门自检 / 演示（/dfgate） ═════════════════════════════════════
--   ★ 为什么需要这个命令：进度条**只在真的有活干的时候才亮**。掉落行帧池是全局共享、
--     只增不减的（惟灵学院 292 行是最大的一本）——整局游戏里
--     通常只有「第一本把池子撑大的副本」会亮一次，之后每本都是复用
--     已经建好的行帧（真·瞬时，本就不该有进度条）。
--     好电脑上几乎看不到它 ⇒ 留一条能随时复现的入口，方便自测与远程帮用户看。
--
--   ★ 演示做法：把三道闸门**临时**放宽到「必定触发」（多小都亮 / 一律分帧 / 每帧只建
--     2 行），再清空掉落行池重新渲染一次 ⇒ 任何副本都能把进度条走完一遍。
--     收工由 DG.Gate.Finish 统一还原（队列抽干是唯一可靠的「活干完了」信号）。
DG.DEMO_SAVE = nil

function DG.Loader.StartDemo()
    if DG.DEMO_SAVE then DG.Loader.EndDemo() end
    DG.DEMO_SAVE = {
        minSteps = DG.Gate.minSteps,
        syncMax  = DG.ROW_SYNC_MAX,
        rowCap   = DG.LOOT_ROW_FRAME_CAP,
        cardCap  = DG.CARD_POOL_CAP,
    }
    DG.Gate.minSteps      = 0     -- 多小都亮（正式值 24）
    DG.ROW_SYNC_MAX       = 0     -- 不走近路，一律走分帧（正式值 20）
    DG.LOOT_ROW_FRAME_CAP = 2     -- 每帧只建 2 行 ⇒ 才看得清（正式值 16）
    DG.CARD_POOL_CAP      = 1     -- 每帧只建 1 张卡 ⇒ 卡片视图那条条也看得清（正式值 6）
    -- 清空掉落行池：行帧池只增不减，不清的话「复用已有行帧」会让待建表为空 ⇒ 进度条照旧不亮
    local it = U.dungeonDetailPool and U.dungeonDetailPool.item
    if it then
        for i = #it, 1, -1 do it[i]:Hide() end
        U.dungeonDetailPool.item = {}
    end
    -- ★ 正停在「卡片」视图时把 boss 卡池也清掉重来 ⇒ 卡片那条进度条同样能复现。
    --   清之前先 Hide 旧卡帧：卡池表一清，旧帧还挂在 child 上 ⇒ 两份卡叠着。
    if (U.lootView or "list") == "card" and U.dungeonDetailPool then
        local cs = U.dungeonDetailPool.card
        if cs then
            for i = #cs, 1, -1 do cs[i]:Hide() end
        end
        U.cardPoolBuilt = nil
        DG.__cardPoolI = 0
    end
    if U.dungeonDetailCur then U:SetDungeonTab("loot") end
end

function DG.Loader.EndDemo()
    local s = DG.DEMO_SAVE
    DG.DEMO_SAVE = nil
    if not s then return end
    DG.Gate.minSteps      = s.minSteps
    DG.ROW_SYNC_MAX       = s.syncMax
    DG.LOOT_ROW_FRAME_CAP = s.rowCap
    DG.CARD_POOL_CAP      = s.cardCap or 6
end

if type(SlashCmdList) == "table" then
    SLASH_DUNGEONSFOREVERGATE1 = "/dfgate"
    SlashCmdList["DUNGEONSFOREVERGATE"] = function(msg)
        local a = tostring(msg or ""):lower():gsub("%s+", "")
        if a == "demo" then
            if not U.dungeonDetailCur then
                print("|cff46bf72[无限副本手册]|r " .. L["先点开一个副本的掉落页，再运行这个命令。"])
                return
            end
            DG.Loader.StartDemo()
            print("|cff46bf72[无限副本手册]|r " .. L["演示：每帧只建 2 行，进度条会走完一遍。"])
            return
        end
        if a == "off" then
            DG.Loader.EndDemo()
            print("|cff46bf72[无限副本手册]|r " .. L["已还原。"])
            return
        end
        -- 不带参数 = 看状态：闸门为什么没亮，看「行池已建行数」就知道了
        local pool = U.dungeonDetailPool
        local n = (pool and pool.item) and #pool.item or 0
        print("|cff46bf72[无限副本手册]|r " .. L["载入速度"] .. " = "
              .. (DG.LOADER_LABEL[DG.Loader.preset] or DG.Loader.preset) .. "（" .. DG.Loader.budgetMs .. "ms/帧）")
        print("  " .. L["进度条"] .. " " .. DG.Gate.done .. "/" .. DG.Gate.total
              .. " · " .. L["待建行"] .. " " .. #DG.__pendRows
              .. " · " .. L["行池"] .. " " .. n)
        print("  /dfgate demo — " .. L["演示：每帧只建 2 行，进度条会走完一遍。"])
    end
end

DG.pendingSteps = {}
DG.stepping = false
function DG.PushStep(fn)
    DG.pendingSteps[#DG.pendingSteps + 1] = fn
end
function DG.RunSteps()
    if DG.stepping then return end
    DG.stepping = true
    local function pump()
        -- ★★★ 第五刀的分工：**pump 一帧只跑一个块** —— 块本身已经是「一帧的量」
        --   （预热一撮 / 一批行帧 / 一批 boss 卡 / 地图页的一段），一帧连跑多块就等于
        --   把已经拆开的尖峰又合并回去。
        --   块**内部**的密度才由 DG.Loader.budgetMs（真机 debugprofilestop 计时）+
        --   各块自己的数量兜底闸自适应 —— 好机器一帧多建几个、差机器少建几个。
        local fn = table.remove(DG.pendingSteps, 1)
        if not fn then
            DG.stepping = false
            return
        end
        local ok, err = pcall(fn)
        if not ok then
            print("|cffff5040[无限副本手册] 分帧构建出错（已跳过该块）：|r" .. tostring(err))
        end
        if #DG.pendingSteps > 0 then
            if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
                C_Timer.After(0, pump)
            else
                pump()
            end
        else
            DG.stepping = false
            DG.Gate.Finish()      -- ★ 队列抽干 = 这一批活干完了（进度条到此收工）
        end
    end
    -- ★★★ 2026-10-03「点副本就卡死」第四刀：**首块也不抢当前帧**。
    --   此前这里是裸的 `pump()` —— 「点开副本」那一帧会同步吃掉队列第一块
    --   （实测正是 MapUI 整页 138 帧 / 945 纹理那一坨，砸在玩家点下去的那一下）。
    --   现在统一排到下一帧；只有 C_Timer 不可用（离线桩 / 极端环境）才同步兜底，
    --   保证「调用方返回时一切就绪」这条离线契约不破。
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(0, pump)
    else
        pump()
    end
end

-- ══ 详情页四个「重池」（幂等；分帧 + 按需同步双入口）══════════════════════
-- ★★★ 第五刀：单张 boss 卡的建帧整段（原样搬出来，**原缩进一字未动** ——
--   里面那几处 SetPoint 是变异锚点，重排缩进会把它们打散；缩进在这里只是观感）。
function DG.NewBossCard(dchild, arrow)
            local c = CreateFrame("Frame", nil, dchild)
            c:EnableMouse(false)
            if ns.hui and ns.hui.BuildRoundedBG then
                ns.hui.BuildRoundedBG(c, 6, { 1, 1, 1, DG.LOOT_CARD_BG }, "both", true, 1)
            end
            c.hit = CreateFrame("Button", nil, c)
            c.hit:RegisterForClicks("LeftButtonUp")
            c.hit:SetHeight(DG.LOOT_CARD_MIN_H)
            c.arrD = c:CreateTexture(nil, "ARTWORK")
            c.arrD:SetSize(DG.LOOT_CARD_ARROW, DG.LOOT_CARD_ARROW)
            c.arrD:SetTexture(arrow)
            c.arrD:SetRotation(math.pi)
            c.arrU = c:CreateTexture(nil, "ARTWORK")
            c.arrU:SetSize(DG.LOOT_CARD_ARROW, DG.LOOT_CARD_ARROW)
            c.arrU:SetTexture(arrow)
            -- ★★ 卡头元素必须钉在「卡头顶部条带」内（相对 HDR_H 居中），不能相对整卡
            --    竖直居中（LEFT/RIGHT 锚 = 整卡中线）——卡一高标题就沉到卡中间（实机截图实锤）。
            for _, at in ipairs({ c.arrD, c.arrU }) do
                at:SetVertexColor(Unpack(C_GOLD))
                at:SetPoint("TOPRIGHT", c, "TOPRIGHT", -DG.LOOT_CARD_PAD,
                            -(DG.LOOT_CARD_HDR_H - DG.LOOT_CARD_ARROW) / 2)
            end
            c.name = MakeFS(c, DG.LOOT_FS_HDR, C_TEXT, "LEFT")
            c.name:SetWordWrap(false)
            -- 标题锚「卡顶**往下** HDR_H/2」（LEFT 点 + TOPLEFT 基准 = 标题中线落在卡头正中）。
            -- ★★★ y 必须取**负值**：WoW 的 SetPoint y 正方向 = 向上，写正号会把标题放到卡顶**外侧**。
            --   实机事故（2026-10-03 用户截图两张）：这里曾是 +HDR_H/2 ⇒
            --     ① 第一排卡（cy = 0）的标题落到滚动内容区之上，被滚动容器裁掉 —— 看着「卡片没有标题」；
            --     ② 第二排往后标题浮在上一张卡与下一张卡的缝里 —— 看着「标题位置偏了」。
            --   ★ 病灶指纹：同一卡头里箭头写的是 -(HDR_H-ARROW)/2（负、卡内），标题却是正 —— 一正一负。
            c.name:SetPoint("LEFT", c, "TOPLEFT", DG.LOOT_CARD_PAD, -DG.LOOT_CARD_HDR_H / 2)
            c.cnt = MakeFS(c, DG.LOOT_FS_META, C_GREY, "RIGHT")
            c.cnt:SetPoint("RIGHT", c.arrD, "LEFT", -6, 0)
            c.hit:SetScript("OnClick", function(self)
                local key = self.__key
                if not key then return end
                DG.LootFoldToggle(key)
            end)
            c.hit:SetScript("OnEnter", function(self)
                local g = self.__g or {}
                local n = g.gi and #(g.items or {}) or 0
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(g.srcName or "", 1, 1, 1, true)
                if g.enName and g.enName ~= "" then
                    GameTooltip:AddLine(g.enName, 0.55, 0.55, 0.55, true)
                end
                GameTooltip:AddLine(format(L["%d 件"], n), 1, 0.82, 0, true)
                GameTooltip:AddLine(L["点击折叠 / 展开该组"], 0.55, 0.55, 0.55, true)
                GameTooltip:Show()
                self.__hi:Show()
            end)
            c.hit:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
                self.__hi:Hide()
            end)
            -- 热区是 EnableMouse 的按钮（压在滚动容器里）⇒ 显式把滚轮转发给详情滚动条，
            -- 否则鼠标停在卡头上时整页滚不动（项目铁律：子控件一律显式转发滚轮）。
            c.hit:EnableMouseWheel(true)
            c.hit:SetScript("OnMouseWheel", function(self, delta)
                DG.WheelScroll(U.dungeonDetailScroll, U.dungeonDetailChild, delta)
            end)
            c.hit.__hi = c.hit:CreateTexture(nil, "OVERLAY")
            c.hit.__hi:SetAllPoints()
            c.hit.__hi:SetColorTexture(1, 1, 1, 0.06)
            c.hit.__hi:Hide()
            c:Hide()
    return c
end

-- boss 卡池分帧：一次最多建 DG.CARD_POOL_CAP 张，剩下的排到下一帧（时间闸同时生效）。
DG.CARD_POOL_CAP = 6
-- 卡池是否已经建满（渲染路径据此决定「先别画，等池子好」）。
function DG.CardPoolReady()
    return (DG.__cardPoolI or 0) >= (DG.LOOT_CARD_MAX or 0)
end

function DG.BuildCardPool()
    local dchild = U.dungeonDetailChild
    local pool = U.dungeonDetailPool
    if not (dchild and pool and pool.card) then return end
    local n = DG.LOOT_CARD_MAX or 0
    local i = DG.__cardPoolI or 0
    -- ★★★ 第六刀（续）：卡池也进载入闸门 —— 进度分母 = 这一本要建的总卡数。
    --   ★ Begin 放**首块**而**不是** DG.EnsureCardPool：切「卡片」视图那一帧
    --     必须零新建帧（harness 有 `FRAMES == _fPre` 钉着），连进度条都不该
    --     在那一帧建出来 —— 那一帧是玩家手指底下的那一帧。
    if not DG.__cardPoolBegun then
        DG.__cardPoolBegun = true
        DG.Gate.Begin(n)
    end
    local t0 = DG.__nowMs()
    local left = DG.CARD_POOL_CAP
    local arrow = "Interface\\AddOns\\DungeonsForever\\Media\\textures\\arrow.tga"
    while i < n and left > 0 do
        i = i + 1
        pool.card[i] = DG.NewBossCard(dchild, arrow)
        DG.Gate.Advance(1)
        left = left - 1
        local t1 = t0 and DG.__nowMs()
        if t1 and (t1 - t0) >= DG.Loader.budgetMs then break end
    end
    DG.__cardPoolI = i
    if i < n then
        DG.PushStep(DG.BuildCardPool)
    elseif (U.lootView or "list") == "card" and U.dungeonDetailCur then
        -- ★ 收尾补渲染：卡池建好时若正停在「卡片」视图，得把内容画出来 ——
        --   分帧窗口里 RenderDungeonLootCards 见不到还没建的卡，只能提前收工。
        DG.PushStep(function() U:RenderDungeonLoot() end)
    end
end

-- boss 卡池（卡片视图专用）
function DG.EnsureCardPool()
    if U.cardPoolBuilt then return end
    local dchild, pool = U.dungeonDetailChild, U.dungeonDetailPool
    if not (dchild and pool) then return end
    U.cardPoolBuilt = true
    -- ★★ boss 卡池（卡片视图专用，2026-10-01）--------------------------------------------
    --   一个来源一张卡，池上限 = 扫一遍全库取「单副本来源数最大值」（当前 29 = 黑石深渊）。
    --   卡片是 child 的普通子帧（不带 BackdropTemplate —— 圆角底走 HUI 原语 BuildRoundedBG，
    --   与地图页三张分组卡 / 团本页卡墙同一套）；EnableMouse(false) ⇒ 卡内空白处滚轮穿透。
    --   卡头热区（c.hit）才是可点控件：折叠键必须挂在**它**身上（挂卡帧 ⇒ self.__key 恒 nil）。
    --   ★★★ 第五刀：池子改为**逐批建**（见 DG.BuildCardPool）—— 29 张卡 ≈ 290 个纹理，
    --     原来一帧建全 = 切到「卡片」视图那一下卡一下；现在按每帧预算摊开。
    pool.card = {}
    local maxG = 0
    for _, srcs in pairs(ns.DungeonLoot or {}) do
        local n = #srcs
        if n > maxG then maxG = n end
    end
    DG.LOOT_CARD_MAX = math.max(maxG, 6)
    DG.__cardPoolI = 0
    DG.__cardPoolBegun = nil
    DG.PushStep(DG.BuildCardPool)
    DG.RunSteps()
end


-- 任务两栏 + 任务页底板
function DG.EnsureQuestLane()
    if U.questLaneBuilt then return end
    local detail = U.dungeonDetail
    if not detail then return end
    U.questLaneBuilt = true
    local qscroll = CreateFrame("ScrollFrame", nil, detail)
    qscroll:SetFrameLevel(U.dungeonDetailHero:GetFrameLevel() + 1)
    qscroll:SetPoint("TOPLEFT", detail, "TOPLEFT", 0, -DG.SCROLL_Y)
    qscroll:SetPoint("BOTTOMRIGHT", detail, "BOTTOMLEFT", DG.Q_LIST_W, 0)
    local qchild = CreateFrame("Frame", nil, qscroll)
    qchild:SetSize(DG.Q_LIST_W, 10)
    qscroll:SetScrollChild(qchild)
    qscroll:EnableMouseWheel(true)
    qscroll:SetScript("OnMouseWheel", function(self, delta)
        DG.WheelScroll(self, U.dungeonQuestChild, delta)
    end)
    qscroll:Hide()
    U.dungeonQuestScroll = qscroll
    U.dungeonQuestChild = qchild
    U.dungeonQuestPool = { hdr = {}, row = {} }
    U.dungeonQuestSum = MakeFS(qchild, 14, C_GOLD, "LEFT")
    U.dungeonQuestNote = MakeFS(qchild, 14, C_GREY, "LEFT")

    local qdet = CreateFrame("ScrollFrame", nil, detail)
    qdet:SetFrameLevel(U.dungeonDetailHero:GetFrameLevel() + 1)
    qdet:SetPoint("TOPLEFT", detail, "TOPLEFT", DG.Q_LIST_W + DG.Q_DET_GAP, -DG.SCROLL_Y)
    qdet:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", 0, 0)
    local qdchild = CreateFrame("Frame", nil, qdet)
    qdchild:SetSize(DG.CHILD_W - DG.Q_LIST_W - DG.Q_DET_GAP, 10)
    qdet:SetScrollChild(qdchild)
    qdet:EnableMouseWheel(true)
    qdet:SetScript("OnMouseWheel", function(self, delta)
        DG.WheelScroll(self, U.dungeonQDetChild, delta)
    end)
    qdet:Hide()
    U.dungeonQDet = qdet
    U.dungeonQDetChild = qdchild
    U.dungeonQDetPool = { lab = {}, kv = {}, txt = {}, node = {}, chip = {}, npc = {} }
    U.dungeonQDetName = MakeFS(qdchild, 16, C_GOLD, "LEFT")
    U.dungeonQDetName:SetWordWrap(false)
    U.dungeonQDetName:SetWidth(DG.CHILD_W - DG.Q_LIST_W - DG.Q_DET_GAP - 8)
    U.dungeonQDetSt = MakeFS(qdchild, 14, C_GREY, "LEFT")

    local function questPlate()
        local p = CreateFrame("Frame", nil, detail, "BackdropTemplate")
        p:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        p:SetBackdropColor(1, 1, 1, DG.LOOT_CARD_BG)
        p:SetBackdropBorderColor(1, 1, 1, DG.LOOT_CARD_EDGE)
        p:Hide()
        return p
    end
    local plateL = questPlate()
    plateL:SetPoint("TOPLEFT", detail, "TOPLEFT", -8, -(DG.SCROLL_Y - 8))
    plateL:SetPoint("BOTTOMRIGHT", detail, "BOTTOMLEFT", DG.Q_LIST_W + 2, 0)
    plateL:SetFrameLevel(qscroll:GetFrameLevel() - 1)
    local plateR = questPlate()
    plateR:SetPoint("TOPLEFT", detail, "TOPLEFT", DG.Q_LIST_W + DG.Q_DET_GAP - 2, -(DG.SCROLL_Y - 8))
    plateR:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", 8, 0)
    plateR:SetFrameLevel(qdet:GetFrameLevel() - 1)
    U.dungeonQPlateL = plateL
    U.dungeonQPlateR = plateR
end

-- 攻略栏
function DG.EnsureGuideLane()
    if U.guideLaneBuilt then return end
    local detail = U.dungeonDetail
    if not detail then return end
    U.guideLaneBuilt = true
    local gscroll = CreateFrame("ScrollFrame", nil, detail)
    gscroll:SetFrameLevel(U.dungeonDetailHero:GetFrameLevel() + 1)
    gscroll:SetPoint("TOPLEFT", detail, "TOPLEFT", 0, -DG.GUIDE_TOP_Y)
    gscroll:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", 0, 0)
    local gchild = CreateFrame("Frame", nil, gscroll)
    gchild:SetSize(DG.CHILD_W, 10)
    gscroll:SetScrollChild(gchild)
    gscroll:EnableMouseWheel(true)
    gscroll:SetScript("OnMouseWheel", function(self, delta)
        DG.WheelScroll(self, U.dungeonGuideChild, delta)
    end)
    gscroll:Hide()
    U.dungeonGuideScroll = gscroll
    U.dungeonGuideChild = gchild
    U.dungeonGuidePool = { card = {} }

end

-- 地图页
function DG.EnsureMapPage()
    if U.mapPageBuilt then return end
    local detail, hero = U.dungeonDetail, U.dungeonDetailHero
    if not (detail and hero) then return end
    U.mapPageBuilt = true
    if ns.MapModule then
        U.dungeonMapFrame = ns.MapModule.Build(detail, hero)
    end

end

-- ══════════════════════════════════════════════════════════════════════════
-- ★★★ 懒建：详情页 / 总览页（2026-10-03「打开就卡死」第二刀）
--   实测：DG.BuildDungeons() 原本在**首屏**就把详情页整套一次建全
--   （boss 卡池 29 张 + 任务两栏 + 攻略栏 + 地图页 + 圆角/遮罩纹理，约 400+ 纹理），
--   而 detail 容器是 Hide 的 —— 打开界面时完全不可见，纯属白建；
--   总览页同理（35 条等级条，oscroll:Hide()）。
--   现在：首屏只建两个空壳容器；内容首次进入时才建（各只付一次）。
--   ★ 触发点：详情页 = U:ShowDungeonDetail 开头；总览页 = U:UpdateDungeons 的 overview 分支。
-- ══════════════════════════════════════════════════════════════════════════
function DG.EnsureDetailBuilt()
    if U.detailBuilt then return end
    local detail = U.dungeonDetail
    local listScroll = U.dungeonListScroll
    if not (detail and listScroll) then return end
    U.detailBuilt = true
    local hero = CreateFrame("Frame", nil, detail)
    hero:SetPoint("TOPLEFT", detail, "TOPLEFT", 0, 0)
    hero:SetPoint("TOPRIGHT", detail, "TOPRIGHT", 0, 0)
    hero:SetHeight(DG.HERO_H)
    hero.art = hero:CreateTexture(nil, "BACKGROUND")
    hero.art:SetAllPoints()
    local heroSheen = hero:CreateTexture(nil, "ARTWORK")
    heroSheen:SetAllPoints()
    heroSheen:SetColorTexture(0, 0, 0, 0.20)
    local heroPlate = hero:CreateTexture(nil, "ARTWORK")
    heroPlate:SetPoint("BOTTOMLEFT", hero, "BOTTOMLEFT", 0, 0)
    heroPlate:SetPoint("BOTTOMRIGHT", hero, "BOTTOMRIGHT", 0, 0)
    heroPlate:SetHeight(DG.HERO_PLATE_H)
    heroPlate:SetColorTexture(0, 0, 0, 0.66)
    U.dungeonDetailHero = hero

    local back = NewButton(detail, L["‹ 副本"], 70, 24, 14)
    back:SetFrameLevel(hero:GetFrameLevel() + 1)
    back:SetPoint("TOPLEFT", detail, "TOPLEFT", 8, -8)
    back:SetScript("OnClick", function()
        detail:Hide()
        listScroll:Show()
        ns.PlaySound(1)
    end)
    U.dungeonBack = back
    U.dungeonDetailTitle = MakeFS(hero, 16, C_WHITE, "LEFT")
    U.dungeonDetailTitle:SetShadowColor(0, 0, 0, 1)
    U.dungeonDetailTitle:SetShadowOffset(1, -1)
    U.dungeonDetailTitle:SetPoint("TOPLEFT", hero, "TOPLEFT", 12, -DG.HERO_TITLE_Y)
    U.dungeonDetailTitle:EnableMouse(true)
    U.dungeonDetailTitle:SetScript("OnMouseUp", function()
        local dd = U.dungeonDetailCur
        if dd then DG.MarkEntrance(dd.id) end
    end)
    U.dungeonDetailTitle:SetScript("OnEnter", function(self) DG.ShowEntranceTip(self) end)
    U.dungeonDetailTitle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    U.dungeonEntChips = {}
    U.dungeonDetailMeta = MakeFS(hero, 14, C_GREY, "LEFT")
    U.dungeonDetailMeta:SetShadowColor(0, 0, 0, 1)
    U.dungeonDetailMeta:SetShadowOffset(1, -1)
    U.dungeonDetailMeta:SetPoint("TOPLEFT", hero, "TOPLEFT", 12, -DG.HERO_META_Y)
    U.dungeonDetailTipZone = CreateFrame("Frame", nil, detail)
    U.dungeonDetailTipZone:SetPoint("TOPLEFT", detail, "TOPLEFT", 10, -DG.HERO_TITLE_Y + 4)
    U.dungeonDetailTipZone:SetPoint("TOPRIGHT", detail, "TOPRIGHT", 0, -DG.HERO_TITLE_Y + 4)
    U.dungeonDetailTipZone:SetHeight(36)
    U.dungeonDetailTipZone:EnableMouse(true)

    local dscroll = CreateFrame("ScrollFrame", nil, detail)
    dscroll:SetFrameLevel(hero:GetFrameLevel() + 1)
    dscroll:SetPoint("TOPLEFT", detail, "TOPLEFT", 0, -DG.SCROLL_Y)
    dscroll:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", 0, 0)
    local dchild = CreateFrame("Frame", nil, dscroll)
    dchild:SetSize(DG.CHILD_W, 10)
    dscroll:SetScrollChild(dchild)
    dscroll:EnableMouseWheel(true)
    dscroll:SetScript("OnMouseWheel", function(self, delta)
        DG.WheelScroll(self, U.dungeonDetailChild, delta)
    end)
    U.dungeonDetailScroll = dscroll
    U.dungeonDetailChild = dchild
    U.dungeonDetailPool = { hdr = {}, item = {} }
    U.dungeonDetailNote = MakeFS(dchild, 14, C_GREY, "LEFT")

    -- ★ 分帧：重池摊到随后的空闲帧里建（首屏只付壳体）。
    --   每块都幂等；切页/切视图时若还没轮到，会由对应的 Ensure* 同步补建。
    --
    -- ★★★ 2026-10-03「点副本就卡死」第四刀：**不再预建 boss 卡池与地图页**。
    --   实测这两块是首开成本的大头，且都属于「用到才需要」：
    --     · boss 卡池（58 帧 / 580 纹理）只有掉落页切到「卡片」视图才用 ——
    --       RenderDungeonLootCards / U:SetLootView 自己会补建（DG.EnsureCardPool）；
    --     · 地图页（138 帧 / 1153 纹理）只有切到「地图」页签才用 ——
    --       U:RenderDungeonTab 的 map 分支自己会补建（DG.EnsureMapPage）。
    --   ★ 任务两栏 / 攻略栏仍预建：各只是两个滚动容器 + 几行文字，很轻，且是常用页签。
    --
    -- ★★★ 第六刀 · 详情外壳分片（2026-10-03「点开瞬间只出框架 + 进度条」）：
    --   探针实测（_temp/_probe_shell.py）外壳 60 帧 / 336 纹理里，**15 颗按钮吃掉
    --   59 帧 / 333 纹理**（ns.CreateButton 约 3 帧/颗；BuildRoundBorder 描边 0 帧
    --   但把纹理额度占满），非按钮部分只占 1 帧。⇒ 页签 / 入口 chip / 筛选行 /
    --   视图按钮 四组各排一块到分帧管线里，点副本那一帧只剩「hero + 返回键 +
    --   标题 + 备注 + 提示区 + 滚动容器」。
    --   ★ 四张控件表在这里先立成**空表**：首次渲染时那几行循环全是 nil 安全
    --     （`#(U.xxx or {})` / `if U.xxx then`），内容照常画，只是按钮晚几帧出现；
    --     每块建完立刻补刷一次文字与选中态（DG.ApplyDetailChrome 等）把顺序追平
    --     —— 顺序仍是「先建壳、后切显隐」，不踩那条空白老坑。
    U.dungeonTabBtns = {}
    U.dungeonFilterBtns = {}
    U.dungeonLootViewBtns = {}
    DG.PushStep(DG.BuildDetailTabs)
    DG.PushStep(DG.BuildDetailChips)
    DG.PushStep(DG.BuildDetailFilterRow)
    DG.PushStep(DG.BuildDetailLootView)
    DG.PushStep(DG.EnsureQuestLane)
    DG.PushStep(DG.EnsureGuideLane)
    DG.RunSteps()
end

-- ══ 详情外壳的四组控件（分帧建；每块一组，建完立刻补刷外壳文字/选中态）══════
--   ★ 循环体是**逐字搬过来**的（缩进一字未动）—— 里面那些 SetPoint / SetScript
--     既是版式常量又是变异锚点，重排一次就会打散。
--   ★ 幂等闸：对应表里已经有东西就直接 return（分帧块万一被重排也不重复建）。
--   ★ 四张空表由 DG.EnsureDetailBuilt 先立好，所以渲染路径任何时刻看到的都是表不是 nil。
--   ★ 时间序：这四块排在详情渲染**之后**、行帧分片**之前**（RenderDungeonLoot 尾部
--     才会 PushStep(DG.BuildPendRows)），所以它们各自独占一帧、互不叠加。

-- 入口 chip 的「上字 + 显隐」：首帧渲染时 chip 还没建，只能等这一块建完补一次。
function DG.PaintEntChips(d)
    local chips = U.dungeonEntChips
    if not (d and chips) then return end
    local pts = DG.EntrancePoints(d.id)
    local n = pts and #pts or 0
    for ci = 1, #chips do
        local chip = chips[ci]
        if ci <= n then
            local p = pts[ci]
            chip:SetText(p.label or L["入口"])
            if ci == 1 then
                chip:SetPoint("LEFT", U.dungeonDetailTitle, "RIGHT", 10, 0)
            else
                chip:SetPoint("LEFT", chips[ci - 1], "RIGHT", 6, 0)
            end
            chip:Show()
        else
            chip:Hide()
        end
    end
end

-- 筛选行的「上字」按当前页签分派：
--   · 掉落页 → U:RenderDungeonLoot 里那一段；· 任务页 → U:RenderDungeonQuests 里那一段。
--   两者都靠 DG.__chromeOnly 只跑「筛选行上字」就收工 —— **绝不能重排待建行**
--   （那会把已经排好、还没建的行帧整体丢掉 = 真丢行）。
--   · 攻略 / 地图页本来就不显示筛选行，直接隐藏。
function DG.RefreshFilterRow()
    local cur = U.dungeonTab or "loot"
    if cur == "guide" or cur == "map" then
        for i = 1, #(U.dungeonFilterBtns or {}) do U.dungeonFilterBtns[i]:Hide() end
        return
    end
    if cur == "quest" then DG.EnsureQuestLane() end
    DG.__chromeOnly = true
    local ok, err = pcall(function()
        if cur == "quest" then U:RenderDungeonQuests() else U:RenderDungeonLoot() end
    end)
    DG.__chromeOnly = nil
    if not ok then
        print("|cffff5040[无限副本手册] 外壳补刷出错（已跳过）：|r" .. tostring(err))
    end
end

-- 详情页外壳的「显隐 / 选中态 / 页签高亮」统一入口。
--   渲染路径（U:RenderDungeonTab 末尾）与外壳分片补建都调它 ⇒
--   「先建壳、后补壳」两种时序下最终状态完全一致。
-- 详情页外壳的「按钮组」补刷：掉落视图按钮显隐 / 筛选行在攻略·地图下全隐 /
--   页签与视图按钮的选中态描边。
--   ★ 只管**按钮壳** —— 页签容器互斥（谁渲染谁显）与掉落筛选栏（LFUI:EnsureBar）
--     都是**渲染分派**的职责，留在 U:RenderDungeonTab 尾部。第六刀最初的版本把
--     它们一起搬进来，结果分片补刷在「渲染已跑、管线还在排」的窗口里又跑了一遍：
--     分帧期间切页签时它会去 SetShown **别的**容器，把地图页/任务页藏掉
--     （harness 实锤：地图容器被藏 ⇒ MapUI ⑤收尾的 frame:IsShown() 不成立 ⇒
--      右栏永远不亮）；掉落筛选栏也被提前到分片帧建，帧数账全乱。
--   ⇒ 渲染路径（U:RenderDungeonTab 末尾）与外壳分片**共用这一个按钮补刷口**。
function DG.ApplyDetailChrome(cur)
    cur = cur or U.dungeonTab or "loot"
    local isQuest = (cur == "quest")
    local isGuide = (cur == "guide")
    local isMap   = (cur == "map")
    -- ★ 显示方式切换只在「掉落」页签出现（其余页签这一行是别的语义，按钮位置也不同）
    if #(U.dungeonLootViewBtns or {}) > 0 then
        if cur == "loot" then U:RefreshLootViewBtns() end
        for i = 1, #U.dungeonLootViewBtns do
            U.dungeonLootViewBtns[i]:SetShown(cur == "loot")
        end
    end
    if U.dungeonLootBossDd then
        U.dungeonLootBossDd:SetShown(cur == "loot")
    end
    if isGuide or isMap then
        for i = 1, #(U.dungeonFilterBtns or {}) do
            U.dungeonFilterBtns[i]:Hide()
        end
    end
    for i = 1, #(U.dungeonFilterBtns or {}) do
        local bt = U.dungeonFilterBtns[i]
        if bt and bt.__em then
            if isQuest and (i == 2 or i == 3) then
                local tex = DG.FactionTex(i == 2 and "A" or "H")
                if tex then
                    bt.__em:SetTexture(tex)
                    bt.__em:Show()
                else
                    bt.__em:Hide()
                end
            else
                bt.__em:Hide()
            end
        end
    end
    for key, bt in pairs(U.dungeonTabBtns or {}) do
        local sel = (key == cur)
        SetOutline(bt, sel, 1, 0.82, 0)
        local fs = bt:GetFontString()
        if fs then fs:SetTextColor(Unpack(sel and C_GOLD or C_GREY)) end
    end
end

function DG.BuildDetailTabs()
    local detail, hero = U.dungeonDetail, U.dungeonDetailHero
    if not (detail and hero) then return end
    if next(U.dungeonTabBtns or {}) then return end
    local tabs = { { key = "loot", text = L["掉落"] }, { key = "quest", text = L["任务"] }, { key = "guide", text = L["攻略"] }, { key = "map", text = L["地图"] } }
    for i, def in ipairs(tabs) do
        local bt = NewButton(detail, def.text, 70, 24, 14)
        bt:SetFrameLevel(hero:GetFrameLevel() + 1)
        bt:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -8 - (i - 1) * 76, -(DG.HERO_META_Y - 12))
        MakeOutline(bt, 1, 0.82, 0)
        bt.__huiKeepTextColor = true
        bt:SetScript("OnClick", function()
            U:SetDungeonTab(def.key)
        end)
        U.dungeonTabBtns[def.key] = bt
    end
    DG.ApplyDetailChrome(U.dungeonTab or "loot")
end

function DG.BuildDetailChips()
    local detail, hero = U.dungeonDetail, U.dungeonDetailHero
    if not (detail and hero) then return end
    if next(U.dungeonEntChips or {}) then return end
    for i = 1, 3 do
        local chip = NewButton(detail, "", 70, 20, 12)
        chip:SetFrameLevel(hero:GetFrameLevel() + 1)
        chip.__entIdx = i
        chip:SetScript("OnClick", function(self)
            local dd = U.dungeonDetailCur
            if dd then DG.MarkEntranceAt(dd.id, self.__entIdx) end
        end)
        chip:SetScript("OnEnter", function(self) DG.ShowEntrancePointTip(self, self.__entIdx) end)
        chip:SetScript("OnLeave", function() GameTooltip:Hide() end)
        chip:Hide()
        U.dungeonEntChips[i] = chip
    end
    DG.PaintEntChips(U.dungeonDetailCur)
end

function DG.BuildDetailFilterRow()
    local detail, hero = U.dungeonDetail, U.dungeonDetailHero
    if not (detail and hero) then return end
    if next(U.dungeonFilterBtns or {}) then return end
    for i = 1, DG.FILTER_MAX do
        local bt = NewButton(detail, "", 92, 24, 14)
        bt:SetPoint("TOPLEFT", detail, "TOPLEFT", (i - 1) * 96, -DG.FILTER_Y)
        MakeOutline(bt, 1, 0.82, 0)
        bt.__huiKeepTextColor = true
        bt.__mode, bt.__key = "loot", "all"
        local em = bt:CreateTexture(nil, "OVERLAY")
        em:SetSize(12, 12)
        em:SetPoint("LEFT", bt, "LEFT", 4, 0)
        em:Hide()
        bt.__em = em
        bt:SetScript("OnClick", function()
            if bt.__mode == "loot" and bt.__key == "__typeMenu" then
                DG.OpenLootTypeMenu()
            elseif bt.__mode == "quest" then
                if bt.__key == "A" or bt.__key == "H" then
                    U:SetQuestSide(bt.__key)
                elseif bt.__key == "qall" then
                    U:SetQuestSide("all")
                else
                    U:SetQuestFilter(bt.__key)
                end
            else
                U:SetDungeonFilter(bt.__key)
            end
            ns.PlaySound(1)
        end)
        U.dungeonFilterBtns[i] = bt
    end
    DG.RefreshFilterRow()
    DG.ApplyDetailChrome(U.dungeonTab or "loot")
end

function DG.BuildDetailLootView()
    local detail = U.dungeonDetail
    if not detail then return end
    if next(U.dungeonLootViewBtns or {}) then return end
    -- ★★ 掉落页显示方式切换（2026-10-01 用户：一行 4 件 + 可选「卡片」视图）------------------
    --   落在筛选行右端（5 颗筛选按钮 4×96 + 92 = 476 收尾，这里从 DG.LOOT_VIEW_X = 492 起），
    --   两段式按钮组，选中态沿用筛选行那套 SetOutline + 金/灰字。**不放进 U.dungeonFilterBtns**
    --   （那张表是筛选语义，混进去会把「筛选按钮共 5 个」之类的不变量搅乱）。

    for vi = 1, 2 do
        local vk = (vi == 1) and "list" or "card"
        local bt = NewButton(detail, (vk == "list") and L["列表"] or L["卡片"],
                             DG.LOOT_VIEW_W, 24, 14)
        bt:SetPoint("TOPLEFT", detail, "TOPLEFT",
                    DG.LOOT_VIEW_X + (vi - 1) * (DG.LOOT_VIEW_W + DG.LOOT_VIEW_GAP), -DG.FILTER_Y)
        MakeOutline(bt, 1, 0.82, 0)
        bt.__huiKeepTextColor = true
        bt.__lootView = vk
        bt.__mode = "lootview"
        bt:SetScript("OnClick", function() U:SetLootView(vk) end)
        U.dungeonLootViewBtns[vi] = bt
    end
    -- ★★ BOSS 下拉（2026-10-04 方案 A）：默认「全部」，选中后列表 / 卡片两路都只渲染该 boss。
    --   独立新帧，不进 U.dungeonFilterBtns（那张表「5 格」的口径不能动）；显隐归 ApplyDetailChrome。
    if not U.dungeonLootBossDd then
        local dd = NewButton(detail, "", DG.LOOT_BOSS_W, 24, 14)
        dd:SetPoint("TOPLEFT", detail, "TOPLEFT", DG.LOOT_BOSS_X, -DG.FILTER_Y)
        MakeOutline(dd, 1, 0.82, 0)
        dd.__huiKeepTextColor = true
        dd:SetScript("OnClick", function() DG.OpenLootBossMenu(dd) end)
        U.dungeonLootBossDd = dd
    end
    -- ★ 分片时序兜底：本帧可能建在 RenderDungeonLoot 的 chrome 补刷**之后**（那时
    --   `if bossDd then` 跳过 ⇒ 字没上），这里显式补一遍，杜绝「空壳下拉」。
    DG.ApplyLootDropdownChrome()
    DG.ApplyDetailChrome(U.dungeonTab or "loot")
end

function DG.EnsureOverviewBuilt()
    if U.overviewBuilt then return end
    if not U.dungeonOverviewChild then return end
    U.overviewBuilt = true
    DG.BuildDungeonOverview()
end

function DG.PaintCurrentLevel()
    local ov, line, tag = U.dungeonCurOverlay, U.dungeonCurLine, U.dungeonCurTag
    if not (ov and line and tag) then return end
    local lv = UnitLevel("player") or 0
    if lv < DG.LO or lv > DG.HI then
        ov:Hide()
        return
    end
    ov:Show()
    local mx = DG.X(lv)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", ov, "TOPLEFT", mx, -(U.dungeonGridTop or 0))
    tag:ClearAllPoints()
    tag:SetPoint("CENTER", ov, "TOPLEFT", mx, -(DG.CUR_H / 2))
    tag:SetText(format(L["当前等级 %d"], lv))
end

function DG.BuildDungeonOverview()
    local data = ns.DungeonData
    local child = U.dungeonOverviewChild
    if not (child and data and data.dungeons) then return end

    local places, lanes = DG.Pack(data.dungeons)

    local yRow = DG.CUR_H + DG.TICK_H + 4
    local totalH = yRow + lanes * DG.LANE_H + DG.BOT_PAD
    child:SetHeight(totalH)

    local gridTop = DG.CUR_H + DG.TICK_H - 4
    U.dungeonGridTop = gridTop
    for _, lv in ipairs(DG.TICKS) do
        local gx = DG.X(lv)
        local ln = child:CreateTexture(nil, "BACKGROUND")
        ln:SetWidth(1)
        ln:SetHeight(totalH - gridTop)
        ln:SetPoint("TOPLEFT", child, "TOPLEFT", gx, -gridTop)
        ln:SetColorTexture(1, 1, 1, 0.06)
        local fs = MakeFS(child, 11, C_GREY, "CENTER")
        fs:SetPoint("CENTER", child, "TOPLEFT", gx, -(DG.CUR_H + DG.TICK_H / 2))
        fs:SetText(tostring(lv))
    end

    local function drawBar(p)
        local d = p.d
        local bar = CreateFrame("Button", nil, child, "BackdropTemplate")
        bar:SetSize(p.x2 - p.x1, DG.BAR_H)
        bar:SetPoint("TOPLEFT", child, "TOPLEFT", p.x1, -(yRow + (p.lane - 1) * DG.LANE_H))
        bar:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        bar:SetBackdropColor(0, 0, 0, 0)
        local edge = d.isNew and DG.NEW_EDGE or DG.OLD_EDGE
        bar:SetBackdropBorderColor(edge[1], edge[2], edge[3], 0.90)

        local art = bar:CreateTexture(nil, "BACKGROUND")
        art:SetAllPoints()
        DG.PaintArt(art, d, "wide")
        local dim = bar:CreateTexture(nil, "ARTWORK")
        dim:SetAllPoints()
        dim:SetColorTexture(0, 0, 0, d.isNew and 0.42 or 0.52)
        if d.isNew then
            local stripe = bar:CreateTexture(nil, "OVERLAY")
            stripe:SetWidth(3)
            stripe:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
            stripe:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)
            stripe:SetColorTexture(DG.NEW_EDGE[1], DG.NEW_EDGE[2], DG.NEW_EDGE[3], 1)
        end

        local nm = MakeFS(bar, 12, C_WHITE, "LEFT")
        nm:SetPoint("TOPLEFT", bar, "TOPLEFT", 7, -4)
        nm:SetWordWrap(false)
        nm:SetText(d.name)
        local barW = p.x2 - p.x1
        local nameW = nm:GetStringWidth()
        if type(nameW) ~= "number" or nameW <= 0 then nameW = (#d.name / 3) * 12 end
        if not d.isNew then
            nm:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        else
            local badge = MakeFS(bar, 11, { 0.42, 0.94, 0.62 }, "LEFT")
            badge:SetText(L["新"])
            if nameW + 14 <= barW - 14 then
                badge:SetPoint("LEFT", nm, "RIGHT", 4, 0)
            else
                nm:SetPoint("RIGHT", bar, "RIGHT", -18, 0)
                badge:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
            end
        end
        local lv = MakeFS(bar, 11, C_GREY, "LEFT")
        lv:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 7, 4)
        lv:SetText(d.levelMin .. "–" .. d.levelMax .. (d.bossCount and (" · BOSS " .. d.bossCount) or ""))

        SetTip(bar, d.name .. "  " .. d.nameEn .. "\n" ..
            format(L["等级 %d–%d · %s"], d.levelMin, d.levelMax, d.zone or L["位置未知"]))
        bar:SetScript("OnClick", function()
            U:SetDungeonView("list")
            U:ShowDungeonDetail(d)
            ns.PlaySound(1)
        end)
    end

    for _, p in ipairs(places) do drawBar(p) end

    local ov = CreateFrame("Frame", nil, child)
    ov:SetAllPoints(child)
    ov:EnableMouse(false)
    ov:SetFrameLevel((child:GetFrameLevel() or 1) + 30)
    U.dungeonCurOverlay = ov
    U.dungeonCurLine = ov:CreateTexture(nil, "ARTWORK")
    U.dungeonCurLine:SetWidth(1)
    U.dungeonCurLine:SetHeight(totalH - gridTop)
    U.dungeonCurLine:SetColorTexture(C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.60)
    U.dungeonCurTag = MakeFS(ov, 11, C_GOLD, "CENTER")
    DG.PaintCurrentLevel()
end

function U:SetDungeonView(view)
    local v = (view == "overview") and "overview" or "list"
    local changed = (v ~= U.dungeonView)
    U.dungeonView = v
    DB().dungeonView = v
    if changed and U.dungeonDetail then U.dungeonDetail:Hide() end
    U:UpdateDungeons()
end

function U:UpdateDungeons()
    if not U.dungeonBuilt then return end
    local data = ns.DungeonData
    local total = data and #data.dungeons or 0
    local view = (U.dungeonView == "overview") and "overview" or "list"
    local lv = UnitLevel("player") or 0
    local can, rec = 0, 0
    for _, d in ipairs((data and data.dungeons) or {}) do
        if d.levelMin and d.levelMin <= lv then
            can = can + 1
            if DG.GroupOf(d, lv) == "rec" then rec = rec + 1 end
        end
    end
    U.dungeonSum:SetText(format(L["共 %d 个副本 · 你（%d 级）可进入 %d 个，其中推荐 %d 个"], total, lv, can, rec))
    for key, bt in pairs(U.dungeonViewBtns or {}) do
        local sel = (key == view)
        SetOutline(bt, sel, 1, 0.82, 0)
        bt:GetFontString():SetTextColor(Unpack(sel and C_GOLD or C_GREY))
    end
    local isOverview = (view == "overview")
    if isOverview then DG.EnsureOverviewBuilt() end   -- ★ 懒建：首次切总览才建 35 条
    if U.dungeonOverviewScroll then U.dungeonOverviewScroll:SetShown(isOverview) end
    if isOverview then
        DG.PaintCurrentLevel()
        if U.dungeonListScroll then U.dungeonListScroll:Hide() end
        if U.dungeonDetail then U.dungeonDetail:Hide() end
    else
        local detailOpen = U.dungeonDetail and U.dungeonDetail:IsShown()
        if U.dungeonListScroll then
            U.dungeonListScroll:SetShown(not detailOpen)
            if (U.dungeonListLevel or -1) ~= lv then
                DG.BuildList()
            end
            U.dungeonListScroll:SetVerticalScroll(0)
        end
    end
end

DG.LOOT_COLS = 4                 -- ★ 2026-10-01 用户：一行 3 件 → 4 件（卡宽 297 → 221）
DG.LOOT_GAP_X = 8
DG.LOOT_GAP_Y = 6
DG.LOOT_CARD_H = 44
-- ★ 卡内水平几何（2026-10-01 用户：「掉落里面的物品图标改大到 32，五人本掉落页面也一样」）
--   图标变大后右侧余量必须重算：名称列宽 = 卡宽 − (左内边距 + 图标 + 图标间距) − 右内边距。
--   ★★ 4 列后名称列只剩 221 − 43 − 7 = 171px（≈12 个汉字），全库最长物品名 16 字放不下 ⇒
--      一律走 DG.FitText 按「字」截断补「…」（完整名留给悬停提示框），**绝不按字节切**。
DG.LOOT_PAD_X = 6                -- 卡左内边距（= 图标左缘）
DG.LOOT_ICON = 32                -- 物品图标边长（★ 与副本地图页 MapUI 的 M.CARD_ICON 同尺寸）
DG.LOOT_ICON_GAP = 5             -- 图标右缘 → 名称左缘
DG.LOOT_TEXT_R = 7               -- 名称 / 百分比右缘 → 卡右缘
DG.LOOT_TAG_W = 28               -- 带「新」徽标时预留的右侧宽（右内边距 + 徽标 + 间距）
DG.LOOT_FS_NAME = 14
DG.LOOT_FS_META = 12
DG.LOOT_FS_TAG = 11
DG.LOOT_FS_HDR = 14
DG.LOOT_HDR_H = 24
DG.LOOT_GRP_GAP = 12
DG.LOOT_CARD_BG, DG.LOOT_CARD_EDGE = 0.03, 0.05
DG.LOOT_CARD_BG_HOVER, DG.LOOT_CARD_EDGE_HOVER = 0.09, 0.18
DG.LOOT_ROW_HOVER = 0.06         -- 卡片视图里卡内行的悬停底（扁平行：只浮一层极淡的底、无边框）
DG.LOOT_CARD_W = math.floor((DG.CHILD_W - (DG.LOOT_COLS - 1) * DG.LOOT_GAP_X) / DG.LOOT_COLS)

-- ★★ 掉落页「显示方式」（2026-10-01 用户：「可以选择显示方式：1 目前这样 / 2 卡片的形式，
--   参考地图界面 一个 boss 一张卡片」）----------------------------------------------------
--   同一份分组数据两条渲染路径 —— 列表（网格）与卡片（boss 卡墙 · 4 列）。
--   视图二选一存 DB().lootView（"list" 缺省 / "card"），切换按钮落在筛选行右端。
--   两视图的卡宽 / 列距 / 行高**共用上面那套**（DG.LOOT_CARD_W / LOOT_GAP_X / LOOT_CARD_H）。
DG.LOOT_VIEW_X = 492             -- 切换按钮左缘（筛选 5 颗 = 4×96 + 92 = 476，留 16px 净距）
DG.LOOT_VIEW_W = 60              -- 单段宽（两段 + 4px 间隔 = 124 ⇒ 右缘 616）
DG.LOOT_VIEW_GAP = 4             -- 两段之间的间隔
--   右侧净空核对：装备过滤条最左一枚图标的最坏落点 ≈ 682（6 个方案时），616 < 682 ⇒ 永不重叠。
-- ★★ 方案 A 收纳式工具行（2026-10-04 用户拍板）：掉落页 1 号筛选按钮重设为「类型」下拉、
--   2–5 号隐藏（任务页照旧全用）；BOSS 下拉是独立新帧 U.dungeonLootBossDd
--   （BuildDetailLootView 里建）。两处选择都写 DB() 跨会话记住。
--   ★ 2026-10-04 用户：两个下拉**宽度一致** ⇒ 类型下拉（1 号）掉落页 SetWidth 到
--     LOOT_BOSS_W（任务页在 RenderDungeonQuests 里回设 92），BOSS 左缘随之从 100 → 158。
DG.LOOT_BOSS_X = 158             -- BOSS 下拉左缘（类型下拉 = 1 号按钮原位 0，同宽 150 收尾 150）
DG.LOOT_BOSS_W = 150             -- 两个下拉统一宽（BOSS 右缘 308，距视图按钮 492 净空 184）
DG.LOOT_DD_TEXT_W = 140          -- 类型下拉文字 FitText 上限（150 宽按钮内留边距）
DG.LOOT_CARD_PAD = 6             -- boss 卡内左右内边距
DG.LOOT_CARD_ARROW = 10          -- 卡头折叠箭头边长（与地图页卡头同尺寸）
DG.LOOT_CARD_ROW_GAP = 4         -- 卡内掉落行间距
DG.LOOT_CARD_NAME_R = 52         -- 卡头右侧预留（「N 件」+ 箭头 + 内边距）
DG.LOOT_CARD_HDR_H = DG.LOOT_HDR_H   -- 卡头高（与列表视图的分组标题行等高）
DG.LOOT_CARD_MIN_H = DG.LOOT_CARD_HDR_H + DG.LOOT_CARD_PAD   -- 空态 / 收起态卡高

DG.GUIDE_COLS, DG.GUIDE_GAP_X, DG.GUIDE_GAP_Y = 2, 8, 8
DG.GUIDE_PAD, DG.GUIDE_HDR_H, DG.GUIDE_STRIPE = 10, 26, 3
DG.GUIDE_SIDE = 8
DG.GUIDE_GRID_W = CONTENT_W - PAGE_INSET * 2 - DG.GUIDE_SIDE * 2
DG.GUIDE_CARD_W = math.floor((DG.GUIDE_GRID_W - (DG.GUIDE_COLS - 1) * DG.GUIDE_GAP_X) / DG.GUIDE_COLS)
DG.GUIDE_ACCENT = {
    { 0.42, 0.72, 0.94 },
    { 0.19, 0.62, 0.47 },
    { 0.85, 0.65, 0.13 },
    { 0.78, 0.45, 0.42 },
}
DG.FILTERS = { "all", "weapon", "armor", "quest", "new" }
DG.FILTER_LABEL = {
    all = L["全部"], weapon = L["武器"], armor = L["护甲"],
    quest = L["任务物品"], new = L["仅新增"],
}
DG.FILTER_MAX = 5

DG.QUALTAB = {
    { 0.62, 0.62, 0.62 },
    { 1.00, 1.00, 1.00 },
    { 0.12, 1.00, 0.00 },
    { 0.00, 0.44, 0.87 },
    { 0.64, 0.21, 0.93 },
    { 1.00, 0.50, 0.00 },
}
function DG.QColor(q)
    local t = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
    if t and t.r then return t.r, t.g, t.b end
    local d = DG.QUALTAB[(q or 1) + 1] or DG.QUALTAB[1]
    return d[1], d[2], d[3]
end
function DG.ItemInfo(id)
    if id == nil then return nil end
    local fn = GetItemInfo or (C_Item and C_Item.GetItemInfo)
    if type(fn) ~= "function" then return nil end
    return fn(id)
end
function DG.ItemInfoInstant(id)
    if id == nil then return nil end
    local fn = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
    if type(fn) ~= "function" then return nil end
    return fn(id)
end
function DG.ItemApiName()
    if type(GetItemInfo) == "function" then return "GetItemInfo（全局）" end
    if C_Item and type(C_Item.GetItemInfo) == "function" then return "C_Item.GetItemInfo（命名空间）" end
    return nil
end

function DG.QualOf(id)
    if id then
        local _, _, q = DG.ItemInfo(id)
        if type(q) == "number" then return q end
        q = DG.NsCall("GetItemQualityByID", id)
        if type(q) == "number" then return q end
    end
    return nil
end

function DG.NsCall(name, id)
    if id == nil then return nil end
    local fn = C_Item and C_Item[name]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, id)
    if ok then return v end
    return nil
end

function DG.ContinueOnItemLoad(id, cb)
    local mk = _G.Item and _G.Item.CreateFromItemID
    if id == nil or type(mk) ~= "function" then return false end
    local ok, item = pcall(mk, _G.Item, id)
    if not ok or not item then return false end
    local ok2 = pcall(item.ContinueOnItemLoad, item, cb)
    return ok2 and true or false
end

function DG.HarvestTipName(id)
    local tip = DG.__warmTip
    if not tip or not id then return nil end
    if not pcall(tip.SetOwner, tip, UIParent, "ANCHOR_NONE") then return nil end
    local ok = pcall(tip.SetItemByID, tip, id)
    if not ok then ok = pcall(tip.SetHyperlink, tip, "item:" .. tostring(id)) end
    if not ok then return nil end
    pcall(tip.Show, tip)
    local nm
    if tip.NumLines and tip:NumLines() > 0 then
        local fs = _G["TFItemWarmTipTextLeft1"]
        if fs and fs.GetText then
            local t = fs:GetText()
            if type(t) == "string" and #t >= 2 then nm = t end
        end
        if nm and fs.GetTextColor then
            local r, g, b2 = fs:GetTextColor()
            if type(r) == "number" then DG.__tipColor = { r, g, b2 } end
        end
    end
    pcall(tip.Hide, tip)
    return nm
end

function DG.RefreshItemCards(itemID)
    local pool = U.dungeonDetailPool and U.dungeonDetailPool.item
    if not pool then return end
    local LF = ns.LootFilter
    -- ★★ 第七刀（整合包悬停卡死）：整合包里其他插件会把客户端物品缓存挤掉
    --   （ItemMixin:IsDataEvictable 恒 true）⇒ 悬停 → SetItemByID（未缓存即同步装载）→ 到货 → 这里。
    --   旧尾巴是「整池 LF.ApplyAll」= 对每张卡做隐藏 tooltip 扫描（LF.ScanTip），
    --   未缓存条目真机同步装载 ⇒ 悬停一次 = 一帧几百次 SetItemByID = 卡死。
    --   过滤规则没变时其他卡的判定结果不变 ⇒ 只失效这一件、只重判匹配卡（O(命中)）。
    if LF then LF.Invalidate(itemID) end
    for i = 1, #pool do
        local c = pool[i]
        local it = c and c.__it
        if it and it[1] == itemID then
            if c.name then
                local nm, hasName = DG.ItemName(itemID)
                c.name:SetText(nm)
                if hasName then
                    c.name:SetTextColor(DG.QColor(DG.QualOf(itemID)))
                else
                    c.name:SetTextColor(Unpack(C_GREY))
                end
                c.__named = hasName
            end
            if c.icon and c.icon.SetTexture then
                c.icon:SetTexture(DG.ItemIcon(itemID))
            end
            if c.tp then c.tp:SetText(DG.ItemMeta(itemID)) end
            if LF then LF.Apply(c) end
        end
    end
    local qpool = U.dungeonQDetPool and U.dungeonQDetPool.chip
    if qpool then
        for i = 1, #qpool do
            local c = qpool[i]
            local it = c and c.__it
            if it and it[1] == itemID and c.name then
                local nm, hasName = DG.ItemName(itemID)
                c.name:SetText(nm)
                if hasName then
                    local qr, qg, qb = DG.QColor(DG.QualOf(itemID))
                    if qr then
                        c.name:SetTextColor(qr, qg, qb)
                    else
                        c.name:SetTextColor(Unpack(C_TEXT))
                    end
                else
                    c.name:SetTextColor(Unpack(C_GREY))
                end
                c.__named = hasName
            end
        end
    end
end

-- ★★ 单卡刷新（2026-10-03「点副本就卡死」第四刀）：DG.RefreshItemCards 是「按 itemID
--   **全池扫**」的入口（事件 / 官方异步回调只拿得到 itemID），而且每次调用末尾还要
--   LF.Invalidate + LF.ApplyAll 走一遍掉落过滤。名字收割里卡片本来就是手里这张，
--   逐卡走那条链 = 每帧 292 次全池扫 + 292 次整池 ApplyAll（实测是分片之后剩下最大的一坨）。
--   这里给「已知是哪张卡」的场景一个 O(1) 的纯绘制口。
--   ⚠️ 绘制口径必须与 DG.RefreshItemCards 里那两段保持一致（那边留给「只有 itemID」的入口）。
function DG.PaintItemRow(c, itemID)
    if not (c and itemID) then return end
    if c.name then
        local nm, hasName = DG.ItemName(itemID)
        c.name:SetText(nm)
        if hasName then
            c.name:SetTextColor(DG.QColor(DG.QualOf(itemID)))
        else
            c.name:SetTextColor(Unpack(C_GREY))
        end
        c.__named = hasName
    end
    if c.icon and c.icon.SetTexture then c.icon:SetTexture(DG.ItemIcon(itemID)) end
    if c.tp then c.tp:SetText(DG.ItemMeta(itemID)) end
end

function DG.PaintItemChip(c, itemID)
    if not (c and c.name and itemID) then return end
    local nm, hasName = DG.ItemName(itemID)
    c.name:SetText(nm)
    if hasName then
        local qr, qg, qb = DG.QColor(DG.QualOf(itemID))
        if qr then
            c.name:SetTextColor(qr, qg, qb)
        else
            c.name:SetTextColor(Unpack(C_TEXT))
        end
    else
        c.name:SetTextColor(Unpack(C_GREY))
    end
    c.__named = hasName
end

function DG.ItemName(id)
    if id then
        local nm = DG.ItemInfo(id)
        if type(nm) == "string" and nm ~= "" then return nm, true end
        nm = DG.NsCall("GetItemNameByID", id)
        if type(nm) == "string" and nm ~= "" then return nm, true end
    end
    return L["暂时没有客户端数据"], false
end

function DG.Pct(v)
    if type(v) ~= "number" then return nil end
    if v >= 10 then return format("%d%%", math.floor(v + 0.5)) end
    return tostring(v) .. "%"
end

function DG.ItemLink(id)
    if id == nil then return nil end
    local fn = GetItemInfo or (C_Item and C_Item.GetItemInfo)
    if type(fn) == "function" then
        local ok, _, link = pcall(fn, id)
        if ok and type(link) == "string" and link ~= "" then return link end
    end
    return "item:" .. tostring(id) .. ":0:0:0:0:0:0:0"
end

function DG.InsertItemLink(id)
    local link = DG.ItemLink(id)
    if link == nil then return false end
    if type(ChatEdit_GetActiveWindow) == "function"
       and type(ChatEdit_InsertLink) == "function"
       and ChatEdit_GetActiveWindow() then
        ChatEdit_InsertLink(link)
        return true
    end
    if type(ChatFrame_OpenChat) == "function" then
        ChatFrame_OpenChat(link)
        return true
    end
    return false
end

function DG.ItemShiftClick(row, button)
    if button ~= "LeftButton" then return false end
    if type(IsShiftKeyDown) ~= "function" or not IsShiftKeyDown() then return false end
    local it = row and row.__it
    if it == nil then return false end
    return DG.InsertItemLink(it[1])
end

function DG.Hex(c)
    return format("|cff%02x%02x%02x",
        math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

DG.CAT_BY_CLASS = { [2] = "weapon", [6] = "weapon", [4] = "armor", [12] = "quest" }
function DG.CatOf(id)
    local _, _, _, _, _, classID = DG.ItemInfoInstant(id)
    return DG.CAT_BY_CLASS[classID] or "other"
end

function DG.ItemIcon(id)
    local tex = select(10, DG.ItemInfo(id))
    if type(tex) ~= "string" or tex == "" then
        local ic = select(5, DG.ItemInfoInstant(id))
        if type(ic) == "string" or type(ic) == "number" then tex = ic end
    end
    if type(tex) == "string" and tex ~= "" then return tex end
    if type(tex) == "number" then return tex end
    return FALLBACK_ICON
end

function DG.ItemMeta(id)
    local _, _, subType, loc, _, _, subID = DG.ItemInfoInstant(id)
    local a
    if type(loc) == "string" then
        a = _G[loc]
        if type(a) ~= "string" and loc:sub(1, 8) ~= "INVTYPE_" then a = loc end
    end
    if type(a) ~= "string" or a == "" then return "" end
    if type(subID) == "number" and subID ~= 0
        and type(subType) == "string" and subType ~= "" then
        return a .. " · " .. subType
    end
    return a
end

DG.__asked = {}
function DG.RequestItem(id, force)
    if not id or (DG.__asked[id] and not force) then return end
    DG.__asked[id] = true
    DG.EnsureItemListener()
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, id)
    end
    local fn = GetItemInfo or (C_Item and C_Item.GetItemInfo)
    if type(fn) == "function" then pcall(fn, id) end
    if not DG.__warmTip and not DG.__warmTried then
        DG.__warmTried = true
        local ok, tip = pcall(CreateFrame, "GameTooltip", "TFItemWarmTip", UIParent, "GameTooltipTemplate")
        if ok then DG.__warmTip = tip end
        if DG.__warmTip then pcall(DG.__warmTip.SetAlpha, DG.__warmTip, 0) end
    end
    if DG.__warmTip then
        pcall(DG.__warmTip.SetOwner, DG.__warmTip, UIParent, "ANCHOR_NONE")
        if not pcall(DG.__warmTip.SetItemByID, DG.__warmTip, id) then
            pcall(DG.__warmTip.SetHyperlink, DG.__warmTip, "item:" .. tostring(id))
        end
        pcall(DG.__warmTip.Hide, DG.__warmTip)
    end
    DG.ContinueOnItemLoad(id, function() DG.RefreshItemCards(id) end)
end

function DG.EnsureItemListener()
    if DG.__itemEvt then return end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    pcall(ev.RegisterEvent, ev, "ITEM_DATA_LOAD_RESULT")
    ev:SetScript("OnEvent", function(_, _, itemID, success)
        if success == false then return end
        -- ★★ 第七刀（整合包悬停卡死）：GET_ITEM_INFO_RECEIVED 对**任何插件**请求的物品都会触发
        --   —— 整合包里成百上千条陌生 itemID 事件，每条都走「全池扫 + 整池 ApplyAll」会把弱机按死。
        --   这里 O(1) 查「是否本插件请过的物品」（DG.RequestItem 会记 DG.__asked），陌生的直接忽略。
        if not (itemID and DG.__asked[itemID]) then return end
        local r = U.dungeonDetailHover
        if r and r.__it and r.__it[1] == itemID and r:IsMouseOver() then
            DG.ShowItemTip(r, r.__it)
        end
        DG.RefreshItemCards(itemID)
    end)
    DG.__itemEvt = ev
end

function DG.PrewarmLoot(d)
    if not d then return end
    local loot = (ns.DungeonLoot or {})[d.id]
    if not loot then return end
    DG.EnsureItemListener()
    -- ★★★ 分帧（2026-10-03「点副本就卡死」第三刀）：整本的物品不再在「打开详情」这一帧
    --   里一口气催完（见 DG.ITEM_WARM_CHUNK）。现在每帧只催一小撮，催完自己在队尾续
    --   一段；C_Timer 不可用（离线 harness / 极端环境）时 DG.RunSteps 递归同步跑完 ——
    --   调用方返回时整本已经催过，断言因此看到的仍是「全都做了」，无需感知分帧。
    local list, n = {}, 0
    for _, s in ipairs(loot) do
        local its = s[5]
        for k = 1, #(its or {}) do
            n = n + 1
            list[n] = its[k]
        end
    end
    local i = 1
    local function warmChunk()
        local stop = i + DG.ITEM_WARM_CHUNK - 1
        if stop > n then stop = n end
        for k = i, stop do
            local it = list[k]
            -- 名字还拿不到就**强制**重请一次：客户端物品缓存会被驱逐
            -- （ItemMixin:IsDataEvictable 恒 true），去过重的话驱逐之后再进这个副本
            -- 就永远停在占位文案上了。
            local _, hasName = DG.ItemName(it[1])
            DG.RequestItem(it[1], not hasName)
        end
        i = stop + 1
        if i <= n then DG.PushStep(warmChunk) end   -- 本帧催完这一撮，下一帧接着来
    end
    if n > 0 then
        DG.PushStep(warmChunk)
        DG.RunSteps()
    end
    DG.ScheduleNameSweep()
end

-- ★★★ 物品数据「催到货」的分帧片大小（2026-10-03「点副本就卡死」第三刀）——
--   一本副本的掉落一次最多催这么多件，剩下的由分帧器摊到随后的空闲帧里。
--   实机根因：通灵学院一本 292 件、黑石深渊 180 件，原来在「打开详情」的那一帧里
--   **一口气**全催一遍；每一件都走 DG.RequestItem 的隐藏 tooltip（真机上 tooltip
--   渲染物品必须先有数据 ⇒ 同步装载），几百次堆在同一帧 = 主线程卡死数秒 ⇒ Windows
--   判定无响应、整窗涂灰。分片之后每帧只付一小撮的成本，界面全程可交互。
DG.ITEM_WARM_CHUNK = 6

DG.SWEEP_AT = { 0.5, 1.5, 4, 9 }

function DG.SweepMissingNames()
    -- ★★★ 分帧（2026-10-03「点副本就卡死」第三刀）：重扫原来是**一次 for 扫完整池** ——
    --   通灵学院一本 292 张卡，每张都走 DG.HarvestTipName，而那是「把隐藏 tooltip 渲染
    --   一遍物品」的重活（真机上 tooltip 渲染物品必须先有数据 ⇒ 同步装载），几百次堆在
    --   同一帧 = 主线程卡死数秒 ⇒ Windows 判定无响应、整窗涂灰。
    --   现在一次最多收割 DG.ITEM_WARM_CHUNK × 2 张，没割完的排到后续空闲帧继续（more）。
    local LF = ns.LootFilter
    local left = DG.ITEM_WARM_CHUNK * 2
    local more = false
    local pool = U.dungeonDetailPool and U.dungeonDetailPool.item
    if pool then
        for i = 1, #pool do
            local c = pool[i]
            local it = c and c.__it
            if it and not c.__named then
                -- ★ O(1) 画这张卡；失效只针对这一件（末尾统一 ApplyAll 一次）
                DG.PaintItemRow(c, it[1])
                if LF then LF.Invalidate(it[1]) end
                if not c.__named and DG.HarvestTipName then
                    if left <= 0 then
                        more = true
                    else
                        left = left - 1
                        local nm = DG.HarvestTipName(it[1])
                        if nm and c.name then
                            c.name:SetText(nm)
                            local col = DG.__tipColor
                            if col then
                                c.name:SetTextColor(col[1] or 1, col[2] or 1, col[3] or 1)
                                DG.__tipColor = nil
                            else
                                c.name:SetTextColor(Unpack(C_GREY))
                            end
                            c.__named = true
                        end
                    end
                end
            end
        end
    end
    local qpool = U.dungeonQDetPool and U.dungeonQDetPool.chip
    local needQRender = false
    if qpool then
        for i = 1, #qpool do
            local c = qpool[i]
            local it = c and c.__it
            if it and not c.__named then
                DG.PaintItemChip(c, it[1])
                if LF then LF.Invalidate(it[1]) end
                if not c.__named and DG.HarvestTipName then
                    if left <= 0 then
                        more = true
                    else
                        left = left - 1
                        local nm = DG.HarvestTipName(it[1])
                        if nm and c.name then
                            c.name:SetText(nm)
                            local col = DG.__tipColor
                            if col then
                                c.name:SetTextColor(col[1] or 1, col[2] or 1, col[3] or 1)
                                DG.__tipColor = nil
                            else
                                c.name:SetTextColor(Unpack(C_GREY))
                            end
                            c.__named = true
                            DG.ApplyChipBadge(c)
                            if c.__q then needQRender = true end
                        end
                    end
                end
            end
        end
    end
    -- ★ 分帧：这一帧没割完就排到下一帧（别把剩下的几百张也啃在这一帧里）。
    if more then
        DG.PushStep(DG.SweepMissingNames)
        DG.RunSteps()
        return
    end
    if needQRender and U.RenderQuestDetail and U.dungeonQDet
       and U.dungeonQDet.IsShown and U.dungeonQDet:IsShown() then
        U:RenderQuestDetail()
    end
    if LF then LF.ApplyAll() end
end

function DG.ScheduleNameSweep()
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
    for _, t in ipairs(DG.SWEEP_AT) do
        C_Timer.After(t, function() DG.SweepMissingNames() end)
    end
end

function DG.ShowItemTip(owner, it)
    -- ★★ 第九刀（Auctionator 共存炸栈，2026-10-03 用户实机 287x C stack overflow）：
    --   实机堆栈：ShowItemTip → GameTooltip:SetItemByID →（Auctionator 挂在 GameTooltip
    --   上的钩子 → ShowTipWithPricing → DBKeyFromLink → ContinueOnItemLoad：物品数据
    --   已就绪时 AsyncCallbackSystem **同步**派发回调）→ 我们的到货处理（行还悬着）
    --   再调 ShowItemTip → 再 SetItemByID ⇒ 无限同步递归直到 C stack overflow。
    --   对策：重入即忽略 —— 正在显示的这一遍，数据刚就绪 SetItemByID 必然成功，
    --   再入的那遍是纯冗余。pcall 包住本体保证 flag 无论成败都复位（错误原样上抛）。
    if DG.__tipBusy then return end
    DG.__tipBusy = true
    local ok, err = pcall(DG.ShowItemTipBody, owner, it)
    DG.__tipBusy = nil
    if not ok then error(err, 0) end
end

function DG.ShowItemTipBody(owner, it)
    local id = it[1]
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()

    local native = false
    if id and GameTooltip.SetItemByID then
        local ok = pcall(GameTooltip.SetItemByID, GameTooltip, id)
        if ok then
            GameTooltip:Show()
            local n = GameTooltip.NumLines and GameTooltip:NumLines() or 0
            native = (type(n) == "number" and n > 1)
        end
    end
    if not native and id and GameTooltip.SetHyperlink then
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. tostring(id))
        if ns.hui and ns.hui.MarkTipItem then ns.hui.MarkTipItem(GameTooltip, true) end
        if ok then
            GameTooltip:Show()
            local n = GameTooltip.NumLines and GameTooltip:NumLines() or 0
            native = (type(n) == "number" and n > 1)
        end
    end
    if not native and id then DG.RequestItem(id, true) end

    if native then
        -- ★★ TinyInspect 兼容（2026-10-03 用户实机）：它给物品提示框插「装备等级」行时，
        --   是下一帧 ClearLines 整段重加行再 Show —— 那次重建会清掉客户端的物品内容态，
        --   我们的 OnShow 皮肤判定（ttItemMark + GetItem）双双落空 ⇒ 装备提示框被错套主题。
        --   这里显式打物品标记（标记是本插件的表，重建清不掉）⇒ 装备提示框始终不套主题。
        if ns.hui and ns.hui.MarkTipItem then ns.hui.MarkTipItem(GameTooltip, true) end
        GameTooltip:Show()
        return
    end

    GameTooltip:ClearLines()
    local nm, hasName = DG.ItemName(id)
    if hasName then
        local r, g, b = DG.QColor(DG.QualOf(id))
        GameTooltip:AddLine(nm, r, g, b, true)
    else
        local meta = id and DG.ItemMeta(id) or ""
        if meta ~= "" then
            GameTooltip:AddLine(meta, 0.85, 0.85, 0.85)
        else
            GameTooltip:AddLine(format(L["物品 #%d"], id or 0), 0.6, 0.6, 0.6)
        end
    end
    if id and DG.ItemInfoInstant(id) then
        GameTooltip:AddLine(L["客户端详细数据加载中，稍后自动刷新"], 0.5, 0.5, 0.5, true)
    else
        GameTooltip:AddLine(L["客户端未收录此物品"], 0.5, 0.5, 0.5, true)
    end
    GameTooltip:Show()
end

-- ★★ 名称按「字」截断（2026-10-01 用户：一行 4 件 / boss 卡内 221px 宽）------------------
--   4 列后名称列只剩 171px（≈12 个汉字），全库最长物品名 16 字 / 最长来源名 12 字都放不下 ⇒
--   一律走这里按「字」截断补「…」，完整名留给悬停提示框（DG.ShowItemTip）。
--   ★ 复用 UTF-8 按「字」切 + 全角估宽（ns.hui.Fit，双端通用——原 ns.ProfModule.Fit
--     只在无限端存在，泰坦端会退回原串溢出，2026-10-03 上移）——**绝不按字节切**：
--     按字节切会切出半个汉字，lupa 桩回传时直接 UnicodeDecodeError 崩掉整个 harness。
--   两处都不可用（理论上不会）时退回原串：宁可溢出也不崩。
function DG.FitText(s, fs, maxw)
    if type(s) ~= "string" then return "" end
    local H = ns.hui
    if H and H.Fit and type(maxw) == "number" and maxw > 0 then
        return H.Fit(s, fs, maxw)
    end
    local PD = ns.ProfModule
    if PD and PD.Fit then return PD.Fit(s, fs, maxw) end
    return s
end

function U:SetDungeonFilter(key)
    U.dungeonFilter = key
    DB().dungeonFilter = key
    U:RenderDungeonLoot()
end

-- ★★ 方案 A 收纳式（2026-10-04）：类型 / BOSS 两个下拉 --------------------------------
--   菜单宿主与 LootFilterUI 同款：懒建挂 UIParent 的 UIDropDownMenu。
--   ★ 2026-10-04 用户反馈后改为**各用各的宿主**：共用一个时 lib 的 toggle 语义是
--     「列表开着 && OPEN_MENU==宿主 ⇒ 收」——A 菜单开着去点 B 按钮，会被当成
--     「同一个下拉再点一次」直接收掉，B 永远打不开。分宿主后切换 / 再点关闭都正常。
function DG.MenuHost(which)
    local key = which or "main"
    local cache = DG.__menuHosts or {}
    if cache[key] then return cache[key] end
    if not (ns.LibBG and ns.LibBG.Create_UIDropDownMenu) then return nil end
    cache[key] = ns.LibBG:Create_UIDropDownMenu(nil, UIParent)
    DG.__menuHosts = cache
    return cache[key]
end

-- 当前副本的 boss 名单（出现序去重）。判定口径：附加说明含「敌人 / 物件」的是
--   小怪 / 宝箱类特殊来源（UI 恒置底那批），不算 boss；其余（含无限新副本那批
--   没有 NPC id 的首领、稀有、任务召唤）都算 —— 不能拿 NPC id 判，新副本首领
--   s[4] 是空串（实测塞恩大厅名单被清零后改口径）。
function DG.LootBossNames(loot)
    local seen, out = {}, {}
    for _, s in ipairs(loot or {}) do
        local nm = s[2]
        local note = s[3] or ""
        local special = note:find("敌人", 1, true) or note:find("物件", 1, true)
        if not special and type(nm) == "string" and nm ~= "" and not seen[nm] then
            seen[nm] = true
            out[#out + 1] = nm
        end
    end
    return out
end

function U:SetLootBoss(name)
    if name == "" then name = nil end
    U.dungeonLootBoss = name
    DB().dungeonLootBoss = name
    U:RenderDungeonLoot()
    ns.PlaySound(1)
end

-- 「类型」下拉：五个筛选档（件数取渲染时存下的 DG.__filterCounts，按当前 boss 收窄）。
function DG.OpenLootTypeMenu()
    local host = DG.MenuHost("type")
    if not (host and ns.LibBG and ns.LibBG.EasyMenu) then return end
    local menu = {}
    for _, key in ipairs(DG.FILTERS) do
        menu[#menu + 1] = {
            text = (DG.FILTER_LABEL[key] or key) .. " " .. tostring(DG.__filterCounts and DG.__filterCounts[key] or 0),
            notCheckable = true,
            func = function() U:SetDungeonFilter(key) end,
        }
    end
    ns.LibBG:EasyMenu(menu, host, "cursor", 0, 0, "MENU")
end

-- 「BOSS」下拉：全部 + 当前副本 boss 名单（每次点开现算，不缓存）。
function DG.OpenLootBossMenu()
    local d = U.dungeonDetailCur
    local host = DG.MenuHost("boss")
    if not (d and host and ns.LibBG and ns.LibBG.EasyMenu) then return end
    local menu = { { text = L["全部"], notCheckable = true, func = function() U:SetLootBoss(nil) end } }
    for _, nm in ipairs(DG.LootBossNames((ns.DungeonLoot or {})[d.id])) do
        menu[#menu + 1] = { text = nm, notCheckable = true, func = function() U:SetLootBoss(nm) end }
    end
    ns.LibBG:EasyMenu(menu, host, "cursor", 0, 0, "MENU")
end

-- ★★ 两个下拉的「上字 + 选中态」统一出口（2026-10-04 用户：偶尔显示为空）----------
--   根因：外壳分片补建时 BuildDetailLootView 可能在 RenderDungeonLoot 的 chrome 补刷
--   **之后**才建出 BOSS 下拉（那时 chrome 里 `if bossDd then` 跳过 ⇒ 字没上，
--   ApplyDetailChrome 只 SetShown ⇒ 新按钮空壳示人）。把上字收成一个出口，
--   渲染主体与 BuildDetailLootView 共用 ⇒ 谁后建帧谁补字，杜绝空下拉。
function DG.ApplyLootDropdownChrome()
    -- BOSS 下拉
    local bossDd = U.dungeonLootBossDd
    if bossDd then
        local bossSel = U.dungeonLootBoss
        bossDd:SetShown((U.dungeonTab or "loot") == "loot")
        bossDd:SetText(L["BOSS："] .. DG.FitText(bossSel or L["全部"], 14, 112))
        SetOutline(bossDd, bossSel ~= nil, 1, 0.82, 0)
        local bfs = bossDd:GetFontString()
        if bfs then bfs:SetTextColor(Unpack(bossSel and C_GOLD or C_GREY)) end
    end
    -- 类型下拉（= 1 号筛选按钮；只在其处于掉落语义时上字，任务页别碰）
    local bt1 = U.dungeonFilterBtns and U.dungeonFilterBtns[1]
    if bt1 and bt1.__mode == "loot" and bt1.__key == "__typeMenu" then
        local filter = U.dungeonFilter or "all"
        local lab = DG.FILTER_LABEL[filter] or filter
        if filter ~= "all" then
            lab = lab .. " " .. tostring(DG.__filterCounts and DG.__filterCounts[filter] or 0)
        end
        bt1:SetWidth(DG.LOOT_BOSS_W)   -- ★ 用户：两个下拉宽度一致
        bt1:SetText(DG.FitText(L["类型："] .. lab, 14, DG.LOOT_DD_TEXT_W))
        SetOutline(bt1, filter ~= "all", 1, 0.82, 0)
        local fs = bt1:GetFontString()
        if fs then fs:SetTextColor(Unpack((filter ~= "all") and C_GOLD or C_GREY)) end
    end
end

-- ★★ 下拉「点外面就关」（2026-10-04 用户）----------------------------------------
--   根因：BiaoGe 版 LibUIDropDownMenu 只在 retail 挂 GLOBAL_MOUSE_DOWN 关闭钩
--   （lib 行 ~1953 `if lib and WoWRetail`），MoP 端 wowversion 5.x 落在 lib 的
--   「n/a」分支 ⇒ 钩子没上 ⇒ 菜单开着点别处不关（只能选中一项或再点一次按钮）。
--   这里补一个事件帧（隐藏帧照收事件）：任一 L_DropDownList 开着 + 鼠标不在菜单
--   列表上 ⇒ 全部收掉。点我们的两个触发按钮时放行——lib 的 toggle 语义是
--   「开着再点就收」，若我们先收，按钮 OnClick（抬键）又把它开回来 = 永远关不掉。
local function OutsideMenuMouseDown()
    local open, overList = false, false
    for i = 1, 3 do
        local lf = _G["L_DropDownList" .. i]
        if lf and lf:IsShown() then
            open = true
            if lf:IsMouseOver() then overList = true end
        end
    end
    if not open or overList then return end
    local om = _G.L_UIDROPDOWNMENU_OPEN_MENU
    if om and om.Button and om.Button:IsVisible() and om.Button:IsMouseOver() then return end
    local t1 = U.dungeonFilterBtns and U.dungeonFilterBtns[1]
    if t1 and t1:IsVisible() and t1:IsMouseOver() then return end
    if U.dungeonLootBossDd and U.dungeonLootBossDd:IsVisible() and U.dungeonLootBossDd:IsMouseOver() then return end
    -- 探索地图设置面板的下拉触发按钮（2026-10-05）：同款放行，理由同上
    if ns.ExploreMapMenuGuard and ns.ExploreMapMenuGuard() then return end
    -- LootFilterUI 的方案菜单同库同列表，一并受益；对普通 UI 的点击照常透传（不吞）。
    ns.LibBG:CloseDropDownMenus()
end
local OUT_EV = CreateFrame("Frame", nil, UIParent)
OUT_EV:RegisterEvent("GLOBAL_MOUSE_DOWN")
OUT_EV:Hide()   -- 隐藏帧照收事件
OUT_EV:SetScript("OnEvent", OutsideMenuMouseDown)

function U:SetQuestFilter(key)
    local cur = U.dungeonQFilter or "all"
    U.dungeonQFilter = (key == cur) and "all" or key
    DB().dungeonQuestFilter = (U.dungeonQFilter ~= "all") and U.dungeonQFilter or nil
    U:RenderDungeonQuests()
end

function U:SetQuestSide(key)
    local k = (key == "A" or key == "H") and key or "all"
    U.dungeonQSide = k
    DB().dungeonQSide = (k ~= "all") and k or nil
    U:RenderDungeonQuests()
    ns.PlaySound(1)
end

function U:ShowDungeonDetail(d)
    if not U.dungeonBuilt then return end
    DG.EnsureDetailBuilt()          -- ★ 懒建：首次打开详情页时才建那整套
    local detail = U.dungeonDetail
    local child, pool = U.dungeonDetailChild, U.dungeonDetailPool
    if not (detail and U.dungeonDetailScroll and child and pool) then return end
    U.dungeonListScroll:Hide()
    detail:Show()
    local hero = U.dungeonDetailHero
    if hero then DG.PaintArt(hero.art, d, "hero") end
    U.dungeonDetailCur = d
    DG.PrewarmLoot(d)

    U.dungeonDetailTitle:SetText(d.name .. "  " .. d.nameEn)
    DG.PaintEntChips(d)
    SetTip(U.dungeonDetailTipZone, d.isNew and L["新副本的 boss 名单来自 beta 客户端，标「新」的是无限版新增的物品；没有掉落数据的 boss 只列名字。"]
        or L["谁掉什么、掉率多少是经典旧世的数据。标「新」的是无限版新增的掉落；其余物品无限版的属性可能有改动，以正式版为准。"])
    local meta = format(L["等级 %d–%d · %s"], d.levelMin, d.levelMax, d.zone or L["位置未知"])
    if d.bossCount then meta = meta .. format(L[" · BOSS %d"], d.bossCount) end
    if d.dropCount then meta = meta .. format(L[" · 掉落 %d"], d.dropCount) end
    U.dungeonDetailMeta:SetText(meta)

    U:RenderDungeonTab()
end

function U:RenderDungeonLoot()
    local LF = ns.LootFilter
    local d = U.dungeonDetailCur
    local child, pool = U.dungeonDetailChild, U.dungeonDetailPool
    if not (d and child and pool) then return end
    local loot = (ns.DungeonLoot or {})[d.id] or {}
    -- ★★★ 第五刀：上一轮排下、还没建的行帧必须整体丢掉 —— 否则玩家已经点到别的副本，
    --   它们随后建出来就会在新页面上冒出来（版式属于上一本）。
    -- ★★★ 第六刀：外壳分片补建时只借下面「筛选行上字」那一段，别动待建表
    --   （那些行还在队列里等着建 —— 丢了就是真丢行）。
    if not DG.__chromeOnly then DG.__pendRows = {} end

    -- ★★ BOSS 聚焦（2026-10-04 方案 A）：先按 BOSS 下拉把来源表收窄，类型计数与
    --   分组渲染全部吃收窄后的来源 ⇒ 选中 boss 后计数就是「这一 boss 里」各类型的件数。
    --   存档里记的 boss 在当前副本不存在（换副本 / 数据更新）就回落「全部」，不弹提示。
    local bossSel = U.dungeonLootBoss or DB().dungeonLootBoss
    if bossSel then
        local seen = {}
        for _, nm in ipairs(DG.LootBossNames(loot)) do seen[nm] = true end
        if not seen[bossSel] then
            bossSel = nil
        end
    end
    U.dungeonLootBoss = bossSel
    DB().dungeonLootBoss = bossSel

    local srcs = loot
    if bossSel then
        srcs = {}
        for _, s in ipairs(loot) do
            if s[2] == bossSel then srcs[#srcs + 1] = s end
        end
    end

    local counts = { all = 0, weapon = 0, armor = 0, quest = 0, new = 0 }
    for _, s in ipairs(srcs) do
        for _, it in ipairs(s[5]) do
            counts.all = counts.all + 1
            local cat = DG.CatOf(it[1])
            if counts[cat] then counts[cat] = counts[cat] + 1 end
            if it[3] then counts.new = counts.new + 1 end
        end
    end

    local filter = U.dungeonFilter or "all"
    if filter ~= "all" and (not counts[filter] or counts[filter] == 0) then
        filter = "all"
        U.dungeonFilter = "all"
        DB().dungeonFilter = "all"
    end
    -- ★★ 类型下拉（1 号按钮重设语义，2026-10-04 方案 A）：掉落页 1 号 = 「类型」下拉
    --   （金框 = 有筛选生效），2–5 号隐藏 —— 它们在任务页照旧全用（RenderDungeonQuests）。
    DG.__filterCounts = counts
    for i, key in ipairs(DG.FILTERS) do
        local bt = U.dungeonFilterBtns and U.dungeonFilterBtns[i]
        if bt then
            bt.__mode = "loot"
            local sel
            if i == 1 then
                bt.__key = "__typeMenu"
                bt:SetShown(true)
                sel = (filter ~= "all")
            else
                bt.__key = key
                bt:SetShown(false)
                sel = false
            end
            SetOutline(bt, sel, 1, 0.82, 0)
            local fs = bt:GetFontString()
            if fs then fs:SetTextColor(Unpack(sel and C_GOLD or C_GREY)) end
        end
    end
    for i = #DG.FILTERS + 1, #(U.dungeonFilterBtns or {}) do
        U.dungeonFilterBtns[i]:Hide()
    end
    -- 两个下拉上字统一走 DG.ApplyLootDropdownChrome（外壳补刷这遍也要刷 —— 它们是工具行的一部分）。
    DG.ApplyLootDropdownChrome()
    -- ★★★ 第六刀：外壳分片补建时，借完「筛选行上字」就收工（不重排待建行）。
    if DG.__chromeOnly then return end

    local named, special = {}, {}
    for _, s in ipairs(srcs) do
        local items = {}
        for _, it in ipairs(s[5]) do
            local cat = DG.CatOf(it[1])
            if filter == "all" or cat == filter or (filter == "new" and it[3]) then
                items[#items + 1] = it
            end
        end
        local g = { src = s, items = items }
        if s[4] ~= "" then named[#named + 1] = g else special[#special + 1] = g end
    end
    local groups = {}
    for _, g in ipairs(named) do groups[#groups + 1] = g end
    for _, g in ipairs(special) do groups[#groups + 1] = g end

    local hdr, rows = pool.hdr, pool.item
    local nH, nI, y = 0, 0, 0
    local cols = DG.LOOT_COLS
    local cw = DG.LOOT_CARD_W
    local stepX, stepY = cw + DG.LOOT_GAP_X, DG.LOOT_CARD_H + DG.LOOT_GAP_Y
    local tx = DG.LOOT_PAD_X + DG.LOOT_ICON + DG.LOOT_ICON_GAP

    local function makeRow()
        r = CreateFrame("Button", nil, child, "BackdropTemplate")
        r:SetSize(cw, DG.LOOT_CARD_H)
        r:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        r:EnableMouse(true)
        r:EnableMouseWheel(true)
        r:SetScript("OnMouseWheel", function(self, delta)
            DG.WheelScroll(U.dungeonDetailScroll, U.dungeonDetailChild, delta)
        end)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(DG.LOOT_ICON, DG.LOOT_ICON)
        r.icon:SetPoint("LEFT", r, "LEFT", DG.LOOT_PAD_X, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(r.icon) end
        r.name = MakeFS(r, DG.LOOT_FS_NAME, C_TEXT, "LEFT")
        r.name:SetPoint("TOPLEFT", r, "TOPLEFT", tx, -4)
        r.name:SetWidth(cw - tx - DG.LOOT_TEXT_R)
        r.name:SetWordWrap(false)
        r.tag = MakeFS(r, DG.LOOT_FS_TAG, { 0.42, 0.94, 0.62 }, "RIGHT")
        r.tag:SetText(L["新"])
        r.tag:SetPoint("TOPRIGHT", r, "TOPRIGHT", -DG.LOOT_TEXT_R, -6)
        r.tp = MakeFS(r, DG.LOOT_FS_META, C_GREY, "LEFT")
        r.tp:SetPoint("TOPLEFT", r, "TOPLEFT", tx, -23)
        r.ch = MakeFS(r, DG.LOOT_FS_META, C_GREY, "RIGHT")
        r.ch:SetPoint("TOPRIGHT", r, "TOPRIGHT", -DG.LOOT_TEXT_R, -23)
        r.note = MakeFS(r, DG.LOOT_FS_META, C_GREY, "LEFT")
        r.note:SetPoint("LEFT", r, "LEFT", 8, 0)
        r:SetScript("OnEnter", function(self)
            U.dungeonDetailHover = self
            -- ★ 行控件两种视图共用 ⇒ 悬停态按当前视图给：列表视图是「卡片提亮」，
            --   卡片视图里行是扁平的（卡内不再套小卡）⇒ 只浮一层极淡的底、不要边框。
            if (U.lootView or "list") == "card" then
                self:SetBackdropColor(1, 1, 1, DG.LOOT_ROW_HOVER)
                self:SetBackdropBorderColor(1, 1, 1, 0)
            else
                self:SetBackdropColor(1, 1, 1, DG.LOOT_CARD_BG_HOVER)
                self:SetBackdropBorderColor(1, 1, 1, DG.LOOT_CARD_EDGE_HOVER)
            end
            if self.__it then DG.ShowItemTip(self, self.__it) end
        end)
        r:SetScript("OnLeave", function(self)
            if U.dungeonDetailHover == self then U.dungeonDetailHover = nil end
            if (U.lootView or "list") == "card" then
                self:SetBackdropColor(1, 1, 1, 0)
                self:SetBackdropBorderColor(1, 1, 1, 0)
            else
                self:SetBackdropColor(1, 1, 1, DG.LOOT_CARD_BG)
                self:SetBackdropBorderColor(1, 1, 1, DG.LOOT_CARD_EDGE)
            end
            GameTooltip:Hide()
        end)
        r:SetScript("OnClick", function(self, button) DG.ItemShiftClick(self, button) end)
        return r
    end

    -- ★★★ 第五刀：「行帧还没建」不再当场建，而是记进待建表（DG.__pendRows）。
    --   一本大副本（黑石深渊 168 件 / 通灵学院 292 件）原来在**渲染这一帧**里同步
    --   CreateFrame 出全部行帧 —— 一帧 250+ 个对象，差电脑上主线程一次阻塞上百毫秒
    --   ⇒ Windows 判定无响应、整窗涂灰。
    --   现在渲染只算版式：位置由调用方按原公式算好、连同上数据一起进待建表，随后由
    --   DG.BuildPendRows 按每帧预算逐批建出来。
    --   ★★ 版式一字未改：待建行落点用的仍是同一组坐标 ⇒ 分批建出来的位置与「同步建」
    --      完全一致，离线几何断言比的就是这些坐标。
    --   ★ make(r) 只建帧；paint(r) 摆位 + 上数据（每轮渲染都要跑一次，行帧会被复用）。
    local function takeRow(make, paint)
        nI = nI + 1
        local idx = nI
        local r = rows[idx]
        if r then
            paint(r)
            return
        end
        DG.__pendRows[#DG.__pendRows + 1] = { idx = idx, make = make, paint = paint }
    end

    -- ★★ 显示方式分派（2026-10-01 用户：「可以选择显示方式：1 目前这样 / 2 卡片的形式」）------
    --   卡片视图走独立的一路（独立 boss 卡池 + 独立布局），列表这一路一字不动；
    --   两条路径共用上面这个行池工厂 takeCard（切视图不新建帧、不重建 scroll child）。
    --   ★ 分派点必须在 takeCard 之后 —— 卡片路径要靠这个闭包取行。
    if (U.lootView or "list") == "card" then
        U:RenderDungeonLootCards(groups, filter, takeRow, makeRow)
        return
    end

    for _, g in ipairs(groups) do
        local items = g.items
        if filter == "all" or #items > 0 then
            local s = g.src
            nH = nH + 1
            local hd = hdr[nH]
            if not hd then
                hd = { name = MakeFS(child, DG.LOOT_FS_HDR, C_TEXT, "LEFT"),
                       cnt = MakeFS(child, DG.LOOT_FS_META, C_GREY, "RIGHT") }
                hdr[nH] = hd
            end
            local en = s[1] or ""
            local sub = s[3] or ""
            if sub ~= "" then en = (en ~= "" and (en .. " · " .. sub) or sub) end
            hd.name:SetText(s[2] .. (en ~= "" and ("  " .. DG.Hex(C_GREY) .. en .. "|r") or ""))
            hd.name:ClearAllPoints()
            hd.name:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
            hd.name:Show()
            hd.cnt:SetText(format(L["%d 件"], #items))
            hd.cnt:ClearAllPoints()
            hd.cnt:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, y - 1)
            hd.cnt:Show()
            y = y - DG.LOOT_HDR_H

            if #items == 0 then
                local baseY = y
                takeRow(makeRow, function(r)
                    r:SetSize(cw, DG.LOOT_CARD_H)
                    r.icon:Hide(); r.name:Hide(); r.tag:Hide(); r.tp:Hide(); r.ch:Hide()
                    r.__it = nil
                    r:SetAlpha(1)
                    r.note:SetText(L["暂无掉落数据"])
                    r.note:Show()
                    r:SetBackdropColor(1, 1, 1, DG.LOOT_CARD_BG)
                    r:SetBackdropBorderColor(1, 1, 1, DG.LOOT_CARD_EDGE)
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, baseY)
                    r:Show()
                end)
                y = y - stepY
            else
                local baseY = y
                -- ★ 单行摆位 + 上数据（原样搬进来，只把「取行」换成 takeRow）
                local function paintRow(r, it, rx, ry)
                    -- ★ 行池两路共用：列表路把行宽拨回列表卡全宽（卡片路会收窄到卡内宽）
                    r:SetSize(cw, DG.LOOT_CARD_H)
                    r.note:Hide()
                    r.icon:SetTexture(DG.ItemIcon(it[1]))
                    r.icon:Show()
                    local nm, hasName = DG.ItemName(it[1])
                    -- ★ 4 列后名称列只剩 171px（≈12 个汉字）——超过就按「字」截断补「…」，
                    --   完整名仍由悬停提示框给（DG.ShowItemTip）。绝不按字节切。
                    local nbudget = it[3] and (cw - tx - DG.LOOT_TAG_W) or (cw - tx - DG.LOOT_TEXT_R)
                    r.name:SetText(DG.FitText(nm, DG.LOOT_FS_NAME, nbudget))
                    if hasName then
                        r.name:SetTextColor(DG.QColor(DG.QualOf(it[1])))
                    else
                        r.name:SetTextColor(Unpack(C_GREY))
                    end
                    r.__named = hasName
                    r.name:Show()
                    if it[3] then
                        r.name:SetWidth(cw - tx - DG.LOOT_TAG_W)
                        r.tag:Show()
                    else
                        r.name:SetWidth(cw - tx - DG.LOOT_TEXT_R)
                        r.tag:Hide()
                    end
                    r.tp:SetText(DG.ItemMeta(it[1]))
                    r.tp:Show()
                    r.ch:SetText(DG.Pct(it[2]) or "")
                    r.ch:Show()
                    r.__it = it
                    if LF and LF.Apply then LF.Apply(r) end
                    r:SetBackdropColor(1, 1, 1, DG.LOOT_CARD_BG)
                    r:SetBackdropBorderColor(1, 1, 1, DG.LOOT_CARD_EDGE)
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", child, "TOPLEFT", rx, ry)
                    r:Show()
                end
                for i, it in ipairs(items) do
                    local rx = ((i - 1) % cols) * stepX
                    local ry = baseY - math.floor((i - 1) / cols) * stepY
                    takeRow(makeRow, function(r) paintRow(r, it, rx, ry) end)
                end
                y = y - math.ceil(#items / cols) * stepY
            end
            y = y - DG.LOOT_GRP_GAP
        end
    end

    for i = nH + 1, #hdr do hdr[i].name:Hide(); hdr[i].cnt:Hide() end
    for i = nI + 1, #rows do rows[i]:Hide() end
    DG.FlushPendingRows()          -- ★ 这一轮排下的待建行：量小同步、量大分帧

    local note = U.dungeonDetailNote
    if nH == 0 then
        note:ClearAllPoints()
        note:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
        if #loot == 0 then
            note:SetText(L["尚未收录这个副本的 boss 名单，数据补上后会自动出现。"])
        else
            note:SetText(L["该分类下暂无掉落。"])
        end
        note:Show()
        y = y - 26
    else
        note:Hide()
    end

    -- ★ 对称收池（2026-10-01）：列表这条路上 boss 卡一张都不出 —— 不显式收，
    --   从卡片视图切回来时上一轮的 boss 卡会整面留在屏上（残影，离线断言实锤）。
    for i = 1, #(pool.card or {}) do pool.card[i]:Hide() end

    child:SetHeight(math.max(10, -y + 12))
    U.dungeonDetailScroll:SetVerticalScroll(0)
end

-- ★★ 掉落「卡片」视图（2026-10-01 用户：「卡片的形式，参考地图界面 一个 boss 一张卡片」）------
--   一个来源一张 boss 卡：4 列、列内自上而下堆（列底参差、互不牵连 —— 瀑布流不做等高对齐，
--   因为 boss 有先后顺序，按列轮转才能保住「左→右、上→下」的阅读序）。
--   卡头 = 来源名 + 「N 件」+ 折叠箭头（点卡头折叠，状态存 DB().dungeonLootFold[key]，key = 副本 id + "#" + 组序号）。
--   ★ 掉落行**复用列表视图那套扁平行池**：行帧一个不新建、scroll child 不重建，
--     切视图只是重新 SetPoint（卡内一行 1 件、双行文本，与列表卡同款，只是窄 12px）。
--   ★ 卡内行是扁平的（卡片内不再套小卡）⇒ 常态底色全透明、悬停只浮一层极淡的底。
function U:RenderDungeonLootCards(groups, filter, takeRow, makeRow)
    DG.EnsureCardPool()               -- ★ 卡片视图需要 boss 卡池；没轮到就同步补建
    local d = U.dungeonDetailCur
    local child, pool = U.dungeonDetailChild, U.dungeonDetailPool
    if not (d and child and pool and takeRow and makeRow) then return end
    local cards, rows = pool.card, pool.item
    if not (cards and rows) then return end
    -- ★ 卡池还在分帧建 ⇒ 先别画：这时候 cards[nC] 是 nil，走到下面会把行池整池收干净
    --   （列表视图的行全被 Hide = 闪一下空白）。等池子建满后由 DG.BuildCardPool 收尾补渲染。
    if not DG.CardPoolReady() then return end
    local loot = (ns.DungeonLoot or {})[d.id] or {}
    DG.__pendRows = {}             -- ★ 同列表路：清掉上一轮排下、还没建的行

    local cols = DG.LOOT_COLS
    local cw = DG.LOOT_CARD_W
    local stepX = cw + DG.LOOT_GAP_X
    local rowW = cw - DG.LOOT_CARD_PAD * 2
    local ix = DG.LOOT_CARD_PAD + DG.LOOT_ICON + DG.LOOT_ICON_GAP
    local nameW = cw - DG.LOOT_CARD_PAD - DG.LOOT_CARD_NAME_R

    local fold = DB().dungeonLootFold
    if type(fold) ~= "table" then
        fold = {}
        DB().dungeonLootFold = fold
    end

    local colY = {}
    for c = 1, cols do colY[c] = 0 end

    local nC, nR = 0, 0
    for gi = 1, #groups do
        local g = groups[gi]
        local items = g.items
        if filter == "all" or #items > 0 then
            nC = nC + 1
            local card = cards[nC]
            if not card then break end
            local s = g.src
            local key = d.id .. "#" .. gi
            local closed = fold[key] and true or false
            local n = closed and 0 or #items
            local h = DG.LOOT_CARD_HDR_H + DG.LOOT_CARD_PAD
            if n > 0 then h = h + n * DG.LOOT_CARD_H + (n - 1) * DG.LOOT_CARD_ROW_GAP end
            local col = ((nC - 1) % cols) + 1
            local cx, cy = (col - 1) * stepX, colY[col]
            colY[col] = cy - (h + DG.LOOT_GAP_Y)

            local en = s[1] or ""
            local sub = s[3] or ""
            if sub ~= "" then en = (en ~= "" and (en .. " · " .. sub) or sub) end
            card.__gid = key
            card.hit.__key = key
            card.hit.__g = { gi = gi, items = items, srcName = s[2] or "", enName = en }
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", child, "TOPLEFT", cx, cy)
            card:SetSize(cw, h)
            card.hit:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
            card.hit:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
            card.arrD:SetShown(not closed)
            card.arrU:SetShown(closed)
            card.name:SetText(DG.FitText(s[2] or "", DG.LOOT_FS_HDR, nameW))
            card.name:SetWidth(nameW)
            card.cnt:SetText(format(L["%d 件"], #items))
            card:Show()
            -- ★ 卡头热区高（收起时整张卡就剩这一条）—— 展开时也只盖卡头那一横条，
            --   绝不挡下面的掉落行（与地图页那三张分组卡同一套定式）。
            card.hit:SetHeight(DG.LOOT_CARD_MIN_H)

            for ii = 1, n do
                nR = nR + 1
                local it = items[ii]
                local rx = cx + DG.LOOT_CARD_PAD
                local ry = cy - DG.LOOT_CARD_HDR_H - (ii - 1) * (DG.LOOT_CARD_H + DG.LOOT_CARD_ROW_GAP)
                takeRow(makeRow, function(r)
                    -- ★ 行宽按卡片路收窄（卡宽 − 2×内边距）：行池是两路共用的，
                    --   不显式拨回去就会顶着列表卡的全宽 221 戳出卡右缘 6px（「新」徽标出界实锤）。
                    r:SetSize(rowW, DG.LOOT_CARD_H)
                    r.note:Hide()
                    r.icon:SetTexture(DG.ItemIcon(it[1]))
                    r.icon:Show()
                    local nm, hasName = DG.ItemName(it[1])
                    local nbudget = it[3] and (rowW - ix - DG.LOOT_TAG_W) or (rowW - ix - DG.LOOT_TEXT_R)
                    r.name:SetText(DG.FitText(nm, DG.LOOT_FS_NAME, nbudget))
                    if hasName then
                        r.name:SetTextColor(DG.QColor(DG.QualOf(it[1])))
                    else
                        r.name:SetTextColor(Unpack(C_GREY))
                    end
                    r.__named = hasName
                    r.name:Show()
                    if it[3] then
                        r.name:SetWidth(rowW - ix - DG.LOOT_TAG_W)
                        r.tag:Show()
                    else
                        r.name:SetWidth(rowW - ix - DG.LOOT_TEXT_R)
                        r.tag:Hide()
                    end
                    r.tp:SetText(DG.ItemMeta(it[1]))
                    r.tp:Show()
                    r.ch:SetText(DG.Pct(it[2]) or "")
                    r.ch:Show()
                    r.__it = it
                    local LF = ns.LootFilter
                    if LF and LF.Apply then LF.Apply(r) end
                    -- 卡内行扁平化：常态不留底、悬停只浮一层极淡高亮（悬停态在行自己的 OnEnter 里给）
                    r:SetBackdropColor(1, 1, 1, 0)
                    r:SetBackdropBorderColor(1, 1, 1, 0)
                    r:ClearAllPoints()
                    -- ★ 行 1 紧贴卡头下缘起排：偏移 = 卡头高 + (序号−1)×(行高+行距)。
                    --   曾经写成 ii*(行高+行距)（第 1 行整行下坠）⇒ 末行被推出卡底（实机截图实锤）。
                    r:SetPoint("TOPLEFT", child, "TOPLEFT", rx, ry)
                end)
            end
        end
    end

    for i = nC + 1, #cards do cards[i]:Hide() end
    for i = nR + 1, #rows do rows[i]:Hide() end
    DG.FlushPendingRows()          -- ★ 同上：待建行按预算落地
    -- 列表视图的分组标题行（pool.hdr）在卡片视图里一条都不出 —— 但**要显式收回池**，
    -- 否则从列表切过来时上一轮的标题会留在屏上（残影）。
    for i = 1, #(pool.hdr or {}) do
        pool.hdr[i].name:Hide()
        pool.hdr[i].cnt:Hide()
    end

    local note = U.dungeonDetailNote
    if nC == 0 then
        note:ClearAllPoints()
        note:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
        if #loot == 0 then
            note:SetText(L["尚未收录这个副本的 boss 名单，数据补上后会自动出现。"])
        else
            note:SetText(L["该分类下暂无掉落。"])
        end
        note:Show()
    else
        note:Hide()
    end

    local bottom = 0
    for c = 1, cols do
        if colY[c] < bottom then bottom = colY[c] end
    end
    child:SetHeight(math.max(10, -bottom + DG.LOOT_GAP_Y))
end

-- 卡片视图 · 折叠 / 展开一张 boss 卡（状态存 DB().dungeonLootFold，跨会话记住）。
-- ★ 收起写 true、展开写 nil（存档里不留 false，与地图页详情页那三张卡片同一套口径）。
-- ★ 折叠后**保住滚动位置** —— 整页跳回顶部是最讨嫌的行为。
function DG.LootFoldToggle(key)
    local s = DB()
    local f = s.dungeonLootFold
    if type(f) ~= "table" then
        f = {}
        s.dungeonLootFold = f
    end
    f[key] = (not f[key]) or nil
    local sc = ns.DungeonUI and ns.DungeonUI.dungeonDetailScroll
    local keep = sc and sc:GetVerticalScroll() or 0
    ns.DungeonUI:RenderDungeonLoot()
    if sc then sc:SetVerticalScroll(keep) end
    ns.PlaySound(1)
end

-- 掉落页显示方式切换（列表 / 卡片）：只切渲染路径，不动数据、不重建任何帧。
function U:SetLootView(v)
    local nv = (v == "card") and "card" or "list"
    U.lootView = nv
    DB().lootView = nv
    if nv == "card" then DG.EnsureCardPool() end   -- ★ 首次切卡片视图才建 boss 卡池
    U:RefreshLootViewBtns()
    U:RenderDungeonLoot()
    if U.dungeonDetailScroll then U.dungeonDetailScroll:SetVerticalScroll(0) end
    ns.PlaySound(1)
end

function U:RefreshLootViewBtns()
    local cur = U.lootView or "list"
    for i = 1, #(U.dungeonLootViewBtns or {}) do
        local bt = U.dungeonLootViewBtns[i]
        if bt then
            local sel = (bt.__lootView == cur)
            SetOutline(bt, sel, 1, 0.82, 0)
            local fs = bt:GetFontString()
            if fs then fs:SetTextColor(Unpack(sel and C_GOLD or C_GREY)) end
        end
    end
end

function DG.QLFn(name)
    local fn = C_QuestLog and C_QuestLog[name]
    if type(fn) == "function" then return fn end
    return nil
end

function DG.QLCall(name, id)
    if id == nil then return nil end
    local fn = DG.QLFn(name)
    if not fn then return nil end
    local ok, v = pcall(fn, id)
    if ok then return v end
    return nil
end

DG.questDoneCache = {}
function DG.QuestSnapReset()
    DG.questDoneSet = nil
    DG.questDoneCache = {}
end
function DG.BuildQuestSnap()
    DG.QuestSnapReset()
    local fn = DG.QLFn("GetAllCompletedQuestIDs")
    if not fn then return false end
    local ok, list = pcall(fn)
    if not ok or type(list) ~= "table" then return false end
    local set = {}
    for i = 1, #list do
        local q = list[i]
        if q then set[q] = true end
    end
    DG.questDoneSet = set
    return true
end

function DG.QuestDone(id)
    if not id then return false end
    local set = DG.questDoneSet
    if set then return set[id] == true end
    local c = DG.questDoneCache[id]
    if c ~= nil then return c end
    local v = (DG.QLCall("IsQuestFlaggedCompleted", id) == true)
    DG.questDoneCache[id] = v
    return v
end
function DG.QuestActive(id)
    if not id then return false end
    return DG.QLCall("IsOnQuest", id) == true
end
function DG.QuestName(id)
    if not id then return nil, false end
    local n = DG.QLCall("GetTitleForQuestID", id)
    if type(n) == "string" and n ~= "" then return n, true end
    return format(L["任务 #%d"], id), false
end
function DG.QuestLevel(id)
    local n = DG.QLCall("GetQuestDifficultyLevel", id)
    if type(n) == "number" and n > 0 then return n end
    return nil
end
function DG.QuestLink(id, lvl)
    if not id or type(GetQuestLink) ~= "function" then return nil end
    local ok, s = pcall(GetQuestLink, id)
    if ok and type(s) == "string" and s ~= "" then return s end
    local title = DG.QLCall("GetTitleForQuestID", id)
    if type(title) ~= "string" or title == "" then title = "?" end
    return format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", id, lvl or 1, title)
end

DG.__qDataAsked = DG.__qDataAsked or {}
function DG.PrefetchQuestData(list)
    local req = DG.QLFn("RequestLoadQuestByID")
    if not req then return end
    for i = 1, #(list or {}) do
        local id = type(list[i]) == "table" and list[i][1] or nil
        if id and not DG.__qDataAsked[id] then
            DG.__qDataAsked[id] = true
            pcall(req, id)
        end
    end
end

function DG.AskQuestData(id)
    if id == nil or DG.__qDataAsked[id] then return end
    DG.__qDataAsked[id] = true
    local req = DG.QLFn("RequestLoadQuestByID")
    if req then pcall(req, id) end
end

function DG.DifficultyColor(level)
    if type(level) ~= "number" or type(GetQuestDifficultyColor) ~= "function" then return nil end
    local ok, c1, c2, c3 = pcall(GetQuestDifficultyColor, level)
    if not ok then return nil end
    if type(c1) == "table" and type(c1.r) == "number" then
        return { c1.r, c1.g, c1.b }
    end
    if type(c1) == "number" and type(c2) == "number" and type(c3) == "number" then
        return { c1, c2, c3 }
    end
    return nil
end

function DG.QuestDescription(id)
    if id == nil then return nil end
    DG.AskQuestData(id)
    local d = DG.QLCall("GetQuestDescription", id)
    if type(d) == "string" and d ~= "" then return d end
    local link = DG.QuestLink(id)
    if not link then return nil end
    local title = DG.QLCall("GetTitleForQuestID", id)
    local function take(txt, parts)
        if txt == "" or txt:find("^%s*$") or txt:find("^　*$")
           or txt:find("^任务等级") or txt:find("^Level ") or txt:find("^等级")
           or txt:find("你已经在做") or txt:find("你已经完成")
           or txt:find("^You are already") or txt:find("^You have already") then
            return parts
        end
        parts = parts or {}
        parts[#parts + 1] = txt
        return parts
    end
    local parts
    if type(C_TooltipInfo) == "table" and type(C_TooltipInfo.GetHyperlink) == "function" then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
        if ok and type(data) == "table" and type(data.lines) == "table" then
            local start = 0
            for i = 1, #data.lines do
                local ln = data.lines[i]
                local txt = (type(ln) == "table" and type(ln.leftText) == "string") and ln.leftText or nil
                if txt and title and txt ~= "" and txt:find(title, 1, true) then
                    start = i
                    break
                end
            end
            for i = start + 1, #data.lines do
                local ln = data.lines[i]
                local txt = (type(ln) == "table" and type(ln.leftText) == "string") and ln.leftText or nil
                if txt and (txt:find("^要求") or txt:find("^Requirements")
                   or txt:find("^任务 ID") or txt:find("^Quest ID")) then
                    break
                end
                if txt then parts = take(txt, parts) end
            end
        end
    end
    if not parts or #parts == 0 then return nil end
    return table.concat(parts, "\n")
end

DG.GAINS_FALLBACK = false

function DG.Thousand(n)
    local s = tostring(n)
    local k = #s % 3
    local out = (k > 0 and s:sub(1, k)) or ""
    for i = k + 1, #s, 3 do
        out = out .. (out ~= "" and "," or "") .. s:sub(i, i + 2)
    end
    return out
end

function DG.QuestRewardXP(id)
    if id == nil or type(GetQuestLogRewardXP) ~= "function" then return nil end
    local ok, v = pcall(GetQuestLogRewardXP, id)
    if ok and type(v) == "number" and v > 0 then return v end
    return nil
end

function DG.QuestRewardMoney(id)
    if id == nil or type(GetQuestLogRewardMoney) ~= "function" then return nil end
    local ok, v = pcall(GetQuestLogRewardMoney, id)
    if ok and type(v) == "number" and v > 0 then return v end
    return nil
end

function DG.QuestObjectiveList(id)
    if id == nil then return nil end
    local fn = DG.QLFn("GetQuestObjectives")
    if not fn then return nil end
    local ok, list = pcall(fn, id)
    if not ok or type(list) ~= "table" then return nil end
    local out = {}
    for _, o in ipairs(list) do
        if type(o) == "table" and type(o.text) == "string" and o.text ~= "" then
            out[#out + 1] = { o.text, tonumber(o.numFilled) or 0, tonumber(o.numRequired) or 0 }
        end
    end
    if #out == 0 then return nil end
    return out
end

function DG.QuestObjectives(id)
    local list = DG.QuestObjectiveList(id)
    if not list then return nil end
    local parts = {}
    for _, ob in ipairs(list) do
        local need = ob[3]
        if need > 0 and not ob[1]:find("%d+/%d+") then
            parts[#parts + 1] = format("%s（%d/%d）", ob[1], ob[2], need)
        else
            parts[#parts + 1] = ob[1]
        end
    end
    return table.concat(parts, "\n")
end

function DG.ItemObjectiveProgress(questID, itemID)
    if questID == nil or itemID == nil then return nil end
    local nm, ok = DG.ItemName(itemID)
    if not ok then return nil end
    local list = DG.QuestObjectiveList(questID)
    if not list then return nil end
    for _, ob in ipairs(list) do
        if ob[3] > 0 and ob[1]:find(nm, 1, true) then
            return ob[2], ob[3]
        end
    end
    return nil
end

function DG.ApplyChipBadge(c)
    if not (c and c.badge) then return end
    if not c.__q then c.badge:Hide() return end
    local have, need = DG.ItemObjectiveProgress(c.__q, c.__it and c.__it[1])
    if have then
        c.badge:SetText(format("%d/%d", have, need))
        if have >= need then
            c.badge:SetTextColor(Unpack(C_GREEN))
        else
            c.badge:SetTextColor(Unpack(C_GREY))
        end
        c.badge:Show()
    else
        c.badge:Hide()
    end
end

function DG.NeedObjectivesText(questID, items)
    local list = DG.QuestObjectiveList(questID)
    if not list then return nil end
    local names = {}
    if items then
        for _, iid in ipairs(items) do
            local nm, ok = DG.ItemName(iid)
            if ok then names[#names + 1] = nm end
        end
    end
    local parts = {}
    for _, ob in ipairs(list) do
        local taken = false
        if ob[3] > 0 then
            for _, nm in ipairs(names) do
                if ob[1]:find(nm, 1, true) then taken = true break end
            end
        end
        if not taken then
            if ob[3] > 0 and not ob[1]:find("%d+/%d+") then
                parts[#parts + 1] = format("%s（%d/%d）", ob[1], ob[2], ob[3])
            else
                parts[#parts + 1] = ob[1]
            end
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "\n")
end

function DG.QuestDataSig(id)
    local objLen, prog = 0, 0
    local list = DG.QuestObjectiveList(id)
    if list then
        for _, ob in ipairs(list) do
            objLen = objLen + #ob[1]
            prog = prog + ob[2] * 100 + ob[3]
        end
    end
    local desc = DG.QuestDescription(id)
    return format("%d:%d:%d:%d:%d", DG.QuestRewardXP(id) or 0, DG.QuestRewardMoney(id) or 0,
        objLen, prog, desc and #desc or 0)
end

function DG.GainsSegs(q)
    if not q or q[1] == nil then return nil end
    local g = q[18]
    local seg = {}
    local apiXp = DG.QuestRewardXP(q[1])
    local apiMoney = DG.QuestRewardMoney(q[1])
    local xp = apiXp or (DG.GAINS_FALLBACK and g and g.xp or nil)
    if xp then seg[#seg + 1] = DG.Thousand(xp) .. L[" 经验"] end
    local money = apiMoney or (DG.GAINS_FALLBACK and g and g.money or nil)
    if money then
        local go, si, co = math.floor(money / 10000), math.floor((money % 10000) / 100), money % 100
        local ms = ""
        if go > 0 then ms = ms .. go .. L["金"] end
        if si > 0 then ms = ms .. si .. L["银"] end
        if co > 0 or ms == "" then ms = ms .. co .. L["铜"] end
        seg[#seg + 1] = ms
    end
    if g and g.rep and #g.rep > 0 then
        local rs = {}
        for _, rr in ipairs(g.rep) do
            rs[#rs + 1] = rr[3] .. " +" .. rr[2]
        end
        seg[#seg + 1] = table.concat(rs, "、")
    end
    return seg
end

function DG.RewardsArrived(id)
    local sig = DG.QuestDataSig(id)
    local g = U.dungeonQDetGains
    if g and g.questID == id and sig ~= g.sig then
        g.sig = sig
        if U.RenderQuestDetail and U.dungeonQDet
           and U.dungeonQDet.IsShown and U.dungeonQDet:IsShown() then
            U:RenderQuestDetail()
        end
    end
    local w = DG.__bagGains
    if w and w.questID == id and sig ~= w.sig then
        w.sig = sig
        if w.apply then pcall(w.apply) end
    end
end

DG.__rewAsked = {}
function DG.RequestQuestRewardData(id)
    if not id or DG.__rewAsked[id] then return end
    DG.__rewAsked[id] = true
    DG.EnsureQuestRewardListener()
    local req = DG.QLFn("RequestLoadQuestByID")
    if req then pcall(req, id) end
    local pre = C_TaskQuest and type(C_TaskQuest.RequestPreloadRewardData) == "function"
        and C_TaskQuest.RequestPreloadRewardData or nil
    if pre then
        local hv = type(HaveQuestRewardData) == "function" and HaveQuestRewardData or nil
        local ok, ready
        if hv then ok, ready = pcall(hv, id) end
        if not ok or not ready then pcall(pre, id) end
    end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        local step = 0
        local function tick()
            if not DG.__rewAsked[id] then return end
            step = step + 1
            if step < 3 and type(HaveQuestRewardData) == "function"
               and C_TaskQuest and type(C_TaskQuest.RequestPreloadRewardData) == "function" then
                local ok, ready = pcall(HaveQuestRewardData, id)
                if ok and not ready then pcall(C_TaskQuest.RequestPreloadRewardData, id) end
            end
            DG.RewardsArrived(id)
            if step < 3 then C_Timer.After(step * 1.2, tick) end
        end
        C_Timer.After(1.2, tick)
    end
end

function DG.EnsureQuestRewardListener()
    if DG.__rewEvt then return DG.__rewEvt end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("QUEST_LOG_UPDATE")
    pcall(ev.RegisterEvent, ev, "QUEST_DATA_LOAD_RESULT")
    pcall(ev.RegisterEvent, ev, "TOOLTIP_DATA_UPDATE")
    ev:SetScript("OnEvent", function(_, event, arg1)
        if event == "QUEST_DATA_LOAD_RESULT" then
            if arg1 then DG.RewardsArrived(arg1) end
        else
            local g = U.dungeonQDetGains
            if g then DG.RewardsArrived(g.questID) end
        end
    end)
    DG.__rewEvt = ev
    return ev
end

function DG.EnsureQuestListener()
    if DG.__questEvt then return DG.__questEvt end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("QUEST_TURNED_IN")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:RegisterEvent("QUEST_LOG_UPDATE")
    ev:SetScript("OnEvent", function(_, event, arg1)
        if event == "QUEST_TURNED_IN" then
            if arg1 then
                if DG.questDoneSet then DG.questDoneSet[arg1] = true end
                DG.questDoneCache[arg1] = true
            end
        elseif event == "QUEST_LOG_UPDATE" then
        else
            DG.BuildQuestSnap()
        end
        if U.RefreshQuestRows then U.RefreshQuestRows() end
    end)
    DG.__questEvt = ev
    return ev
end

function DG.ShowQuestTip(owner, q)
    if not q then return end
    DG.AskQuestData(q[1])
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local link = DG.QuestLink(q[1], q[3])
    local native = false
    if link and GameTooltip.SetHyperlink then
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        if ok then
            GameTooltip:Show()
            local n = GameTooltip.NumLines and GameTooltip:NumLines() or 0
            native = (type(n) == "number" and n > 1)
        end
    end
    if native then return end

    GameTooltip:ClearLines()
    local nm, hasName = DG.QuestName(q[1])
    GameTooltip:AddLine(nm, 1, 1, 1, true)
    local st = DG.QuestState(q[1])
    if st == "done" then
        GameTooltip:AddLine(L["已完成"], 0.25, 0.85, 0.35)
    elseif st == "active" then
        GameTooltip:AddLine(L["进行中"], 1, 0.82, 0)
    else
        GameTooltip:AddLine(L["未完成"], 0.6, 0.6, 0.6)
    end
    if q[3] then GameTooltip:AddLine(format(L["%d 级可接"], q[3]), 0.75, 0.75, 0.75) end
    local where = (q[17] and q[17] ~= "" and q[17]) or q[5] or ""
    if q[17] and q[17] ~= "" and q[16] then where = where .. " #" .. q[16] end
    if q[6] then where = (where ~= "" and (where .. " · " .. q[6]) or q[6]) end
    if where ~= "" then GameTooltip:AddLine(L["起始："] .. where, 0.75, 0.75, 0.75, true) end
    if q[9] and #q[9] > 0 then
        local parts = {}
        for _, seg in ipairs(q[9]) do
            if type(seg) == "number" then
                local pnm, pok = DG.QuestName(seg)
                if pok then
                    parts[#parts + 1] = pnm .. " #" .. seg
                elseif q[7] then
                    parts[#parts + 1] = q[7]
                else
                    parts[#parts + 1] = pnm
                end
            else
                parts[#parts + 1] = tostring(seg)
            end
        end
        if #parts > 0 then
            GameTooltip:AddLine(L["前置："] .. table.concat(parts, "、"), 0.75, 0.75, 0.75, true)
        end
    elseif q[7] then
        GameTooltip:AddLine(L["前置："] .. q[7], 0.75, 0.75, 0.75, true)
    end
    if not hasName then
        GameTooltip:AddLine(L["客户端未收录此任务，暂时没有客户端数据"], 0.5, 0.5, 0.5, true)
    end
    GameTooltip:Show()
end

DG.Q_LIST_W = 520
DG.Q_DET_GAP = 8
DG.Q_ROW_H = 34
DG.Q_GAP_Y = 4
DG.Q_X_NAME = 30
DG.Q_X_LOC = 200
DG.Q_X_LV = 348
DG.Q_X_PRE = 416
DG.Q_W_NAME = 164
DG.Q_W_LOC = 144
DG.Q_FS_DET = 14
DG.Q_DET_ICON = 20
DG.C_FAC_A = { 0.45, 0.65, 1 }
DG.C_FAC_H = { 1, 0.40, 0.40 }
DG.Q_BAR_W = 3
DG.Q_FS_NAME = 14
DG.Q_FS_META = 14
DG.Q_FS_HDR = 16
DG.Q_HDR_H = 26
DG.Q_GRP_GAP = 10
DG.Q_SUM_H = 28
DG.Q_STATUS_TAG = { done = L["已完成"], active = L["进行中"], todo = L["未完成"] }
DG.QFILTERS = { "all", "todo", "done" }
DG.QFILTER_LABEL = { all = L["全部"], todo = L["未完成"], done = L["已完成"] }
DG.QSIDE_LABEL = { all = L["全部"], A = L["联盟"], H = L["部落"] }
DG.Q_DIFF_COLOR = {
    [1] = { 1, 0.12, 0.12 }, [2] = { 1, 0.5, 0.25 }, [3] = { 1, 0.82, 0 },
    [4] = { 0.12, 1, 0 }, [5] = { 0.6, 0.6, 0.6 },
}
DG.QCLASS_TOKEN = {
    [ns.DL("战士")] = "WARRIOR", [ns.DL("圣骑士")] = "PALADIN", [ns.DL("猎人")] = "HUNTER", [ns.DL("盗贼")] = "ROGUE",
    [ns.DL("牧师")] = "PRIEST", [ns.DL("萨满")] = "SHAMAN", [ns.DL("法师")] = "MAGE", [ns.DL("术士")] = "WARLOCK", [ns.DL("德鲁伊")] = "DRUID",
}
DG.QCLASS_CHAR = {
    [ns.DL("战士")] = L["战"], [ns.DL("圣骑士")] = L["骑"], [ns.DL("猎人")] = L["猎"], [ns.DL("盗贼")] = L["盗"], [ns.DL("牧师")] = L["牧"],
    [ns.DL("萨满")] = L["萨"], [ns.DL("法师")] = L["法"], [ns.DL("术士")] = L["术"], [ns.DL("德鲁伊")] = L["德"],
}
function DG.QClassColor(cls)
    local t = RAID_CLASS_COLORS and RAID_CLASS_COLORS[DG.QCLASS_TOKEN[cls] or ""]
    if t and t.r then return { t.r, t.g, t.b } end
    return C_GOLD
end
function DG.QClassChar(cls)
    local first = string.match(cls or "", "^([^/]+)")
    return DG.QCLASS_CHAR[first]
end

function DG.QuestState(id)
    if DG.QuestDone(id) then return "done" end
    if DG.QuestActive(id) then return "active" end
    return "todo"
end

function DG.PlayerSide()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    if f == "Alliance" then return "A" end
    if f == "Horde" then return "H" end
    return nil
end

function DG.QuestRows(d)
    local all = (ns.DungeonQuests or {})[d.id] or {}
    local n = #all
    local ps = DG.PlayerSide()
    if not ps or n == 0 then return all, n, nil end
    local keep, m, other = {}, 0, false
    for i = 1, n do
        local s = all[i][2]
        if not s or s == "" or s == ps then
            m = m + 1
            keep[m] = all[i]
        else
            other = true
        end
    end
    if m == 0 then return all, n, (other and "fallback" or nil) end
    return keep, m, (other and "filtered" or nil)
end

function DG.QuestList(d)
    return (ns.DungeonQuests or {})[d.id] or {}
end

DG.__rowByID = nil
function DG.QuestRowByID(id)
    if not DG.__rowByID then
        local map = {}
        for _, rows in pairs(ns.DungeonQuests or {}) do
            for _, q in ipairs(rows) do map[q[1]] = q end
        end
        DG.__rowByID = map
    end
    return DG.__rowByID[id]
end

DG.__followers = nil
function DG.QuestFollowers(id)
    if not DG.__followers then
        local map = {}
        for _, rows in pairs(ns.DungeonQuests or {}) do
            for _, q in ipairs(rows) do
                local pre = q[9]
                if pre then
                    for _, seg in ipairs(pre) do
                        if type(seg) == "number" then
                            map[seg] = map[seg] or {}
                            local t = map[seg]
                            t[#t + 1] = q
                        end
                    end
                end
            end
        end
        DG.__followers = map
    end
    return DG.__followers[id] or {}
end

DG.__facTex = {}
function DG.FactionTex(side)
    if side ~= "A" and side ~= "H" then return nil end
    if DG.__facTex[side] == nil then
        local p = "Interface\\PVPFrame\\PVP-Capture" .. (side == "A" and "Alliance" or "Horde")
        local ok = false
        if type(GetFileIDFromPath) == "function" then
            local ok2, fid = pcall(GetFileIDFromPath, p)
            ok = (ok2 and type(fid) == "number" and fid > 0) or false
        end
        DG.__facTex[side] = ok and p or false
    end
    return DG.__facTex[side] or nil
end
function DG.FactionLetter(side)
    if side == "A" then return L["盟"] end
    if side == "H" then return L["部"] end
    return nil
end

function U:RenderDungeonQuests()
    local d = U.dungeonDetailCur
    local child, pool = U.dungeonQuestChild, U.dungeonQuestPool
    if not (d and child and pool) then return end
    DG.EnsureQuestListener()

    local list = DG.QuestList(d)
    DG.PrefetchQuestData(list)
    local nAll = #list

    local cnt = { all = nAll, A = 0, H = 0, todo = 0, done = 0 }
    local doneN = 0
    for i = 1, nAll do
        local s = list[i][2]
        if s == "A" or not s then cnt.A = cnt.A + 1 end
        if s == "H" or not s then cnt.H = cnt.H + 1 end
        if DG.QuestDone(list[i][1]) then doneN = doneN + 1 end
    end
    cnt.done = doneN
    cnt.todo = nAll - doneN

    local side = U.dungeonQSide or DB().dungeonQSide
    if not side then
        local ps = DG.PlayerSide()
        side = (ps and cnt[ps] > 0) and ps or "all"
    end
    U.dungeonQSide = side
    local status = U.dungeonQFilter or "all"

    for i = 1, #(U.dungeonFilterBtns or {}) do
        local bt = U.dungeonFilterBtns[i]
        if bt then
            local key, label, n
            if i == 1 then key, label, n = "qall", DG.QSIDE_LABEL.all, cnt.all
            elseif i == 2 then key, label, n = "A", DG.QSIDE_LABEL.A, cnt.A
            elseif i == 3 then key, label, n = "H", DG.QSIDE_LABEL.H, cnt.H
            elseif i == 4 then key, label, n = "todo", DG.QFILTER_LABEL.todo, cnt.todo
            else key, label, n = "done", DG.QFILTER_LABEL.done, cnt.done end
            bt.__mode, bt.__key = "quest", key
            bt:SetWidth(92)   -- 掉落页把 1 号拉宽到 LOOT_BOSS_W（同宽下拉），回任务页先还原
            local tex = (i == 2 or i == 3) and DG.FactionTex(i == 2 and "A" or "H") or nil
            bt:SetText((tex and "  " or "") .. label .. " " .. n)
            bt:SetShown(true)
            local sel = (i <= 3 and side == key) or (i == 4 and status == "todo") or (i == 5 and status == "done")
            SetOutline(bt, sel, 1, 0.82, 0)
            bt:GetFontString():SetTextColor(Unpack(sel and C_GOLD or C_GREY))
        end
    end

    -- ★★★ 第六刀：外壳分片补建时，借完「筛选行上字」就收工。
    if DG.__chromeOnly then return end

    local nVis, doneVis = 0, 0
    for i = 1, nAll do
        local q = list[i]
        if side == "all" or q[2] == side or not q[2] then
            nVis = nVis + 1
            if DG.QuestDone(q[1]) then doneVis = doneVis + 1 end
        end
    end
    local seg = ""
    if side ~= "all" then
        if side == DG.PlayerSide() then
            seg = L["（已按你的阵营筛选）"]
        else
            seg = format(L["（只看%s阵营任务）"], DG.QSIDE_LABEL[side] or side)
        end
    else
        local ps = DG.PlayerSide()
        if ps and nAll > 0 and cnt[ps] == 0 then
            seg = L["（含对方阵营的任务）"]
        end
    end
    U.dungeonQuestSum:ClearAllPoints()
    U.dungeonQuestSum:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 2)
    U.dungeonQuestSum:SetText(format(L["已完成 %d / %d"], doneVis, nVis) .. seg)
    U.dungeonQuestSum:Show()

    local groups = { { inside = false, rows = {} }, { inside = true, rows = {} } }
    for i = 1, nAll do
        local q = list[i]
        if side == "all" or q[2] == side or not q[2] then
            local key = q[8] and 2 or 1
            local st = DG.QuestState(q[1])
            local hit = true
            if status == "done" then hit = (st == "done")
            elseif status == "todo" then hit = (st ~= "done") end
            if hit then
                local g = groups[key]
                g.rows[#g.rows + 1] = q
            end
        end
    end

    local selOk = false
    for gi = 1, 2 do
        for _, q in ipairs(groups[gi].rows) do
            if q[1] == U.dungeonQuestSel then selOk = true break end
        end
        if selOk then break end
    end
    if not selOk then
        local first = groups[1].rows[1] or groups[2].rows[1]
        U.dungeonQuestSel = first and first[1] or nil
    end

    local hdr, rows = pool.hdr, pool.row
    local nH, nR, y = 0, 0, -DG.Q_SUM_H

    local function takeRow()
        nR = nR + 1
        local r = rows[nR]
        if not r then
            r = CreateFrame("Button", nil, child, "BackdropTemplate")
            r:SetSize(DG.Q_LIST_W, DG.Q_ROW_H)
            r:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            r:EnableMouse(true)
            r:EnableMouseWheel(true)
            r:SetScript("OnMouseWheel", function(_, delta)
                DG.WheelScroll(U.dungeonQuestScroll, U.dungeonQuestChild, delta)
            end)
            r:SetScript("OnClick", function()
                if r.__q then
                    U.dungeonQuestSel = r.__q[1]
                    U:RenderDungeonQuests()
                end
            end)
            r.bar = r:CreateTexture(nil, "ARTWORK")
            r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
            r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
            r.bar:SetWidth(DG.Q_BAR_W)
            r.em = r:CreateTexture(nil, "ARTWORK")
            r.em:SetSize(12, 12)
            r.em:SetPoint("TOPLEFT", r, "TOPLEFT", 12, -(DG.Q_ROW_H - 12) / 2)
            r.emL = MakeFS(r, 14, C_GREY, "LEFT")
            r.emL:SetPoint("TOPLEFT", r, "TOPLEFT", 13, -(DG.Q_ROW_H - 14) / 2 - 1)
            r.cls = MakeFS(r, 14, C_GREY, "LEFT")
            r.cls:SetPoint("TOPLEFT", r, "TOPLEFT", 30, -(DG.Q_ROW_H - 14) / 2 - 1)
            r.name = MakeFS(r, DG.Q_FS_NAME, C_TEXT, "LEFT")
            r.name:SetPoint("TOPLEFT", r, "TOPLEFT", DG.Q_X_NAME, -(DG.Q_ROW_H - DG.Q_FS_NAME) / 2 - 1)
            r.name:SetWidth(DG.Q_W_NAME)
            r.name:SetWordWrap(false)
            r.sub = MakeFS(r, DG.Q_FS_META, C_GREY, "LEFT")
            r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", DG.Q_X_LOC, -(DG.Q_ROW_H - DG.Q_FS_META) / 2 - 1)
            r.sub:SetWidth(DG.Q_W_LOC)
            r.sub:SetWordWrap(false)
            r.lv = MakeFS(r, DG.Q_FS_META, C_GREY, "LEFT")
            r.lv:SetPoint("TOPLEFT", r, "TOPLEFT", DG.Q_X_LV, -(DG.Q_ROW_H - DG.Q_FS_META) / 2 - 1)
            r.pre = MakeFS(r, 14, C_GREY, "LEFT")
            r.pre:SetPoint("TOPLEFT", r, "TOPLEFT", DG.Q_X_PRE, -(DG.Q_ROW_H - 14) / 2 - 1)
            r.pre:SetText(L["前置"])
            r.meta = MakeFS(r, DG.Q_FS_META, C_GREY, "RIGHT")
            r.meta:SetPoint("TOPRIGHT", r, "TOPRIGHT", -6, -(DG.Q_ROW_H - DG.Q_FS_META) / 2 - 1)
            r.selMark = r:CreateTexture(nil, "OVERLAY")
            r.selMark:SetColorTexture(1, 0.82, 0, 0.95)
            r.selMark:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
            r.selMark:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
            r.selMark:SetWidth(3)
            r.selMark:Hide()
            r:SetScript("OnEnter", function(self)
                U.dungeonQuestHover = self
                self:SetBackdropColor(1, 1, 1, DG.LOOT_CARD_BG_HOVER)
                self:SetBackdropBorderColor(1, 1, 1, DG.LOOT_CARD_EDGE_HOVER)
                if self.__q then DG.ShowQuestTip(self, self.__q) end
            end)
            r:SetScript("OnLeave", function(self)
                if U.dungeonQuestHover == self then U.dungeonQuestHover = nil end
                if self.__q and self.__q[1] == U.dungeonQuestSel then
                    self:SetBackdropColor(1, 1, 1, DG.LOOT_CARD_BG_HOVER)
                    self:SetBackdropBorderColor(1, 0.82, 0, 0.9)
                else
                    self:SetBackdropColor(1, 1, 1, DG.LOOT_CARD_BG)
                    self:SetBackdropBorderColor(1, 1, 1, DG.LOOT_CARD_EDGE)
                end
                GameTooltip:Hide()
            end)
            rows[nR] = r
        end
        return r
    end

    for gi = 1, 2 do
        local g = groups[gi]
        if #g.rows > 0 then
            nH = nH + 1
            local hd = hdr[nH]
            if not hd then
                hd = { name = MakeFS(child, DG.Q_FS_HDR, C_TEXT, "LEFT"),
                       cnt = MakeFS(child, DG.Q_FS_META, C_GREY, "RIGHT") }
                hdr[nH] = hd
            end
            hd.name:SetText(g.inside and L["副本内领取 / 交付"] or L["进本前先去接"])
            hd.name:ClearAllPoints()
            hd.name:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
            hd.name:Show()
            hd.cnt:SetText(format(L["%d 个"], #g.rows))
            hd.cnt:ClearAllPoints()
            hd.cnt:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, y - 1)
            hd.cnt:Show()
            y = y - DG.Q_HDR_H

            for i = 1, #g.rows do
                local q = g.rows[i]
                local r = takeRow()
                local st = DG.QuestState(q[1])
                local col = (st == "done" and C_GREEN) or (st == "active" and C_GOLD) or C_GREY
                local nm, hasName = DG.QuestName(q[1])
                r.bar:SetColorTexture(col[1], col[2], col[3], 1)
                r.bar:Show()
                local ftex = q[2] and DG.FactionTex(q[2]) or nil
                if ftex then
                    r.em:SetTexture(ftex)
                    r.em:Show()
                    r.emL:Hide()
                else
                    r.em:Hide()
                    local lt = q[2] and DG.FactionLetter(q[2]) or nil
                    if lt then
                        r.emL:SetText(lt)
                        r.emL:SetTextColor(Unpack(q[2] == "A" and DG.C_FAC_A or DG.C_FAC_H))
                        r.emL:Show()
                    else
                        r.emL:Hide()
                    end
                end
                local clsChar = q[15] and DG.QClassChar(q[15]) or nil
                if clsChar then
                    r.cls:SetText(clsChar)
                    r.cls:SetTextColor(Unpack(DG.QClassColor(q[15])))
                    r.cls:Show()
                    r.name:ClearAllPoints()
                    r.name:SetPoint("TOPLEFT", r, "TOPLEFT", DG.Q_X_NAME + 14, -(DG.Q_ROW_H - DG.Q_FS_NAME) / 2 - 1)
                    r.name:SetWidth(DG.Q_W_NAME - 14)
                else
                    r.cls:Hide()
                    r.name:ClearAllPoints()
                    r.name:SetPoint("TOPLEFT", r, "TOPLEFT", DG.Q_X_NAME, -(DG.Q_ROW_H - DG.Q_FS_NAME) / 2 - 1)
                    r.name:SetWidth(DG.Q_W_NAME)
                end
                r.name:SetText(nm)
                if not hasName then
                    r.name:SetTextColor(Unpack(C_GREY))
                elseif st == "done" then
                    r.name:SetTextColor(Unpack(C_GREEN))
                elseif st == "active" then
                    r.name:SetTextColor(Unpack(C_GOLD))
                else
                    r.name:SetTextColor(Unpack(C_TEXT))
                end
                r.name:Show()
                local loc = q[6] or ""
                if loc == "" and q[8] then loc = L["副本内"] end
                r.sub:SetText(loc)
                r.sub:Show()
                if hasName and q[3] then
                    r.lv:SetText(format(L["%d 级可接"], q[3]))
                    r.lv:SetTextColor(Unpack(C_GOLD))
                    r.lv:Show()
                else
                    r.lv:Hide()
                end
                if (q[7] or q[9]) and hasName then
                    r.pre:Show()
                else
                    r.pre:Hide()
                end
                r.meta:SetText(hasName and (DG.Q_STATUS_TAG[st] or "") or L["暂时没有客户端数据"])
                r.meta:SetTextColor(Unpack(hasName and col or C_DARKGREY))
                r.meta:Show()
                r.__q = q
                local isSel = (q[1] == U.dungeonQuestSel)
                if isSel then
                    r:SetBackdropColor(1, 1, 1, DG.LOOT_CARD_BG_HOVER)
                    r:SetBackdropBorderColor(1, 0.82, 0, 0.9)
                    r.selMark:Show()
                else
                    r:SetBackdropColor(1, 1, 1, DG.LOOT_CARD_BG)
                    r:SetBackdropBorderColor(1, 1, 1, DG.LOOT_CARD_EDGE)
                    r.selMark:Hide()
                end
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y - (i - 1) * (DG.Q_ROW_H + DG.Q_GAP_Y))
                r:Show()
            end
            y = y - #g.rows * (DG.Q_ROW_H + DG.Q_GAP_Y) - DG.Q_GRP_GAP
        end
    end

    for i = nH + 1, #hdr do hdr[i].name:Hide(); hdr[i].cnt:Hide() end
    for i = nR + 1, #rows do rows[i]:Hide() end

    local note = U.dungeonQuestNote
    if nH == 0 then
        note:ClearAllPoints()
        note:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
        if nAll == 0 then
            note:SetText(L["本站资料里这个副本还没有任务清单，数据补上后会自动出现。"])
        else
            note:SetText(L["该分类下暂无任务。"])
        end
        note:Show()
        y = y - 26
    else
        note:Hide()
    end

    child:SetHeight(math.max(10, -y + 12))
    U.dungeonQuestScroll:SetVerticalScroll(0)
    U:RenderQuestDetail()
end

function U:RefreshQuestRows()
    if not U.dungeonBuilt then return end
    if (U.dungeonTab or "loot") ~= "quest" then return end
    if not (U.dungeonDetail and U.dungeonDetail:IsShown()) then return end
    U:RenderDungeonQuests()
end

function DG.MarkNPC(npcID)
    local ver = select(4, GetBuildInfo()) or 0
    if ver < 16000 or ver > 16999 then
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, L["地图标记仅无限客户端支持"], 1, 0.6, 0.2)
        end
        return
    end
    local loc = ns.NPCLoc and ns.NPCLoc[npcID]
    if not loc then
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, format(L["NPC #%d 未收录地图位置"], npcID), 1, 0.4, 0.4)
        end
        return
    end
    local mapID = loc[1]
    if UiMapPoint and UiMapPoint.CreateFromCoordinates and C_Map and C_Map.SetUserWaypoint
        and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(mapID)) then
        local ok, pt = pcall(UiMapPoint.CreateFromCoordinates, mapID, loc[2] / 100, loc[3] / 100)
        if ok and pt then
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

function DG.ShowNpcTip(owner, npcID)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["点击：在地图上标记该 NPC"], 1, 0.82, 0)
    local loc = ns.NPCLoc and ns.NPCLoc[npcID]
    if loc then
        GameTooltip:AddLine(format("%s %.1f, %.1f", tostring(loc[4] or ""), loc[2], loc[3]), 0.75, 0.75, 0.75)
    else
        GameTooltip:AddLine(L["未收录该 NPC 的地图位置"], 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

function DG.MarkEntrance(dungeonID)
    local ver = select(4, GetBuildInfo()) or 0
    if ver < 16000 or ver > 16999 then
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, L["地图标记仅无限客户端支持"], 1, 0.6, 0.2)
        end
        return
    end
    local loc = dungeonID and ns.DungeonEntry and ns.DungeonEntry[dungeonID]
    if not loc then
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, L["未收录该副本的入口位置"], 1, 0.4, 0.4)
        end
        return
    end
    local mapID = loc[1]
    if UiMapPoint and UiMapPoint.CreateFromCoordinates and C_Map and C_Map.SetUserWaypoint
        and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(mapID)) then
        local ok, pt = pcall(UiMapPoint.CreateFromCoordinates, mapID, loc[2] / 100, loc[3] / 100)
        if ok and pt then pcall(C_Map.SetUserWaypoint, pt) end
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, false)
        end
    end
    if C_Map and C_Map.OpenWorldMap then
        pcall(C_Map.OpenWorldMap, mapID)
    elseif OpenWorldMap then
        pcall(OpenWorldMap, mapID)
    end
end

function DG.ShowEntranceTip(owner)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["点击：在地图上标记副本入口"], 1, 0.82, 0)
    local d = U.dungeonDetailCur
    local loc = d and ns.DungeonEntry and ns.DungeonEntry[d.id]
    if loc then
        local route = d and ns.DungeonEntryRoute and ns.DungeonEntryRoute[d.id]
        GameTooltip:AddLine((route and (L["副本入口"] .. " ") or "") ..
            format("%s %.1f, %.1f", tostring(loc[4] or ""), loc[2], loc[3]), 0.75, 0.75, 0.75)
        if route then
            for i = 1, #route do
                local p = route[i]
                GameTooltip:AddLine(tostring(p[4] or "") .. " " .. tostring(p[5] or "") .. " " ..
                    format("%.1f, %.1f", p[2], p[3]), 0.6, 0.6, 0.6)
            end
        end
    else
        GameTooltip:AddLine(L["未收录该副本的入口位置"], 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

function DG.EntrancePoints(dungeonID)
    local loc = dungeonID and ns.DungeonEntry and ns.DungeonEntry[dungeonID]
    if not loc then return nil end
    local pts = { { mapID = loc[1], x = loc[2], y = loc[3], label = nil, mapName = loc[4] } }
    local route = dungeonID and ns.DungeonEntryRoute and ns.DungeonEntryRoute[dungeonID]
    if route then
        for i = 1, #route do
            local p = route[i]
            pts[#pts + 1] = { mapID = p[1], x = p[2], y = p[3], label = p[4], mapName = p[5] }
        end
    end
    return pts
end

function DG.MarkEntranceAt(dungeonID, idx)
    local ver = select(4, GetBuildInfo()) or 0
    if ver < 16000 or ver > 16999 then
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, L["地图标记仅无限客户端支持"], 1, 0.6, 0.2)
        end
        return
    end
    local pts = DG.EntrancePoints(dungeonID)
    local p = pts and pts[idx or 1]
    if not p then
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, L["未收录该副本的入口位置"], 1, 0.4, 0.4)
        end
        return
    end
    if UiMapPoint and UiMapPoint.CreateFromCoordinates and C_Map and C_Map.SetUserWaypoint
        and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(p.mapID)) then
        local ok, wp = pcall(UiMapPoint.CreateFromCoordinates, p.mapID, p.x / 100, p.y / 100)
        if ok and wp then pcall(C_Map.SetUserWaypoint, wp) end
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, false)
        end
    end
    if C_Map and C_Map.OpenWorldMap then
        pcall(C_Map.OpenWorldMap, p.mapID)
    elseif OpenWorldMap then
        pcall(OpenWorldMap, p.mapID)
    end
end

function DG.ShowEntrancePointTip(owner, idx)
    if not GameTooltip then return end
    local d = U.dungeonDetailCur
    local pts = d and DG.EntrancePoints(d.id)
    local p = pts and pts[idx or 1]
    if not p then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["点击：在地图上标记此点"], 1, 0.82, 0)
    GameTooltip:AddLine(tostring(p.label or L["副本入口"]) .. " " .. tostring(p.mapName or "") .. " " ..
        format("%.1f, %.1f", p.x, p.y), 0.75, 0.75, 0.75)
    GameTooltip:Show()
end

function U:RenderQuestDetail()
    local d = U.dungeonDetailCur
    local child, pool = U.dungeonQDetChild, U.dungeonQDetPool
    if not (d and child and pool) then return end
    local detW = DG.CHILD_W - DG.Q_LIST_W - DG.Q_DET_GAP

    local q
    for _, row in ipairs(DG.QuestList(d)) do
        if row[1] == U.dungeonQuestSel then q = row end
    end

    pool.nLab, pool.nKv, pool.nTxt, pool.nNode, pool.nChip, pool.nNpc = 0, 0, 0, 0, 0, 0
    local y = -2

    local function takeLab()
        pool.nLab = pool.nLab + 1
        local i = pool.nLab
        local f = pool.lab[i]
        if not f then
            f = MakeFS(child, 14, C_GREY, "LEFT")
            pool.lab[i] = f
        end
        return f
    end
    local function takeKv()
        pool.nKv = pool.nKv + 1
        local i = pool.nKv
        local f = pool.kv[i]
        if not f then
            f = MakeFS(child, DG.Q_FS_DET, C_TEXT, "LEFT")
            f:SetWidth(detW - 8)
            f:SetWordWrap(false)
            pool.kv[i] = f
        end
        return f
    end
    local function takeNpc()
        pool.nNpc = pool.nNpc + 1
        local i = pool.nNpc
        local f = pool.npc[i]
        if not f then
            f = CreateFrame("Button", nil, child)
            f:SetSize(detW, 24)
            f:EnableMouse(true)
            f:EnableMouseWheel(true)
            f:SetScript("OnMouseWheel", function(_, delta)
                DG.WheelScroll(U.dungeonQDet, U.dungeonQDetChild, delta)
            end)
            f:SetScript("OnClick", function(self)
                if self.__npc then DG.MarkNPC(self.__npc) end
            end)
            f:SetScript("OnEnter", function(self)
                if self.__npc then DG.ShowNpcTip(self, self.__npc) end
            end)
            f:SetScript("OnLeave", function() GameTooltip:Hide() end)
            f.fs = MakeFS(f, DG.Q_FS_DET, C_TEXT, "LEFT")
            f.fs:SetWidth(detW - 8)
            f.fs:SetWordWrap(false)
            f.fs:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
            pool.npc[i] = f
        end
        return f
    end
    local function takeTxt()
        pool.nTxt = pool.nTxt + 1
        local i = pool.nTxt
        local f = pool.txt[i]
        if not f then
            f = MakeFS(child, DG.Q_FS_DET, C_TEXT, "LEFT")
            f:SetWidth(detW - 8)
            pool.txt[i] = f
        end
        return f
    end
    local function takeNode()
        pool.nNode = pool.nNode + 1
        local i = pool.nNode
        local r = pool.node[i]
        if not r then
            r = CreateFrame("Button", nil, child, "BackdropTemplate")
            r:SetSize(detW, 38)
            r:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            r:EnableMouse(true)
            r:EnableMouseWheel(true)
            r:SetScript("OnMouseWheel", function(_, delta)
                DG.WheelScroll(U.dungeonQDet, U.dungeonQDetChild, delta)
            end)
            r:SetScript("OnEnter", function(self)
                self:SetBackdropColor(1, 1, 1, DG.LOOT_CARD_BG_HOVER)
                self:SetBackdropBorderColor(1, 1, 1, DG.LOOT_CARD_EDGE_HOVER)
                if self.__q then DG.ShowQuestTip(self, self.__q) end
            end)
            r:SetScript("OnLeave", function(self)
                self:SetBackdropColor(1, 1, 1, DG.LOOT_CARD_BG)
                self:SetBackdropBorderColor(1, 1, 1, DG.LOOT_CARD_EDGE)
                GameTooltip:Hide()
            end)
            r:SetScript("OnClick", function(self)
                if self.__npc then DG.MarkNPC(self.__npc) end
            end)
            r.bar = r:CreateTexture(nil, "ARTWORK")
            r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
            r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
            r.bar:SetWidth(3)
            r.name = MakeFS(r, 14, C_TEXT, "LEFT")
            r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 10, -3)
            r.name:SetWidth(detW - 100)
            r.name:SetWordWrap(false)
            r.st = MakeFS(r, 14, C_GREY, "RIGHT")
            r.st:SetPoint("TOPRIGHT", r, "TOPRIGHT", -8, -3)
            r.sub = MakeFS(r, 14, C_GREY, "LEFT")
            r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", 10, -21)
            r.sub:SetWidth(detW - 18)
            r.sub:SetWordWrap(false)
            pool.node[i] = r
        end
        r:SetBackdropColor(1, 1, 1, DG.LOOT_CARD_BG)
        r:SetBackdropBorderColor(1, 1, 1, DG.LOOT_CARD_EDGE)
        return r
    end
    local function takeChip()
        pool.nChip = pool.nChip + 1
        local i = pool.nChip
        local r = pool.chip[i]
        if not r then
            r = CreateFrame("Button", nil, child)
            r:SetSize(detW, DG.Q_DET_ICON + 6)
            r:EnableMouse(true)
            r:EnableMouseWheel(true)
            r:SetScript("OnMouseWheel", function(_, delta)
                DG.WheelScroll(U.dungeonQDet, U.dungeonQDetChild, delta)
            end)
            r:SetScript("OnEnter", function(self)
                if self.__it then DG.ShowItemTip(self, self.__it) end
            end)
            r:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
            r:SetScript("OnClick", function(self, button) DG.ItemShiftClick(self, button) end)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(r.icon) end
            r.icon:SetSize(DG.Q_DET_ICON, DG.Q_DET_ICON)
            r.icon:SetPoint("LEFT", r, "LEFT", 2, 0)
            r.name = MakeFS(r, DG.Q_FS_DET, C_TEXT, "LEFT")
            r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
            r.name:SetWidth(detW - DG.Q_DET_ICON - 16)
            r.name:SetWordWrap(false)
            r.badge = MakeFS(r, DG.Q_FS_DET, C_GREY, "RIGHT")
            r.badge:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            r.badge:SetWidth(46)
            r.badge:SetWordWrap(false)
            pool.chip[i] = r
        end
        return r
    end

    local function put(f, h)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
        f:Show()
        y = y - h
    end

    local name = U.dungeonQDetName
    local stf = U.dungeonQDetSt
    if not q then
        U.dungeonQDetGains = nil
        name:ClearAllPoints()
        name:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -2)
        name:SetText(L["点左侧任务查看详情"])
        name:SetTextColor(Unpack(C_GREY))
        name:Show()
        stf:Hide()
        child:SetHeight(30)
        return
    end

    U.dungeonQDetGains = { questID = q[1], sig = DG.QuestDataSig(q[1]) }
    DG.RequestQuestRewardData(q[1])

    local nm, hasName = DG.QuestName(q[1])
    local st = DG.QuestState(q[1])
    local col = (st == "done" and C_GREEN) or (st == "active" and C_GOLD) or C_GREY
    if hasName then nm = nm .. format(" |cff9a9a9a#%d|r", q[1]) end
    name:SetText(nm)
    name:SetTextColor(Unpack(hasName and C_GOLD or C_GREY))
    name:ClearAllPoints()
    name:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -2)
    name:Show()
    y = -28
    stf:SetText(hasName and (L["状态："] .. (DG.Q_STATUS_TAG[st] or "")) or L["暂时没有客户端数据"])
    stf:SetTextColor(Unpack(hasName and col or C_DARKGREY))
    put(stf, 22)

    local lvClient = DG.QuestLevel(q[1])
    local attain = q[3] and format(L["%d 级可接"], q[3]) or nil
    local lvCol = lvClient and DG.DifficultyColor(lvClient) or nil
    local lvTxt = ""
    if attain then
        lvTxt = DG.Hex(C_GOLD) .. attain .. "|r"
        if lvClient or q[4] then
            local lvSeg = format(L[" · 任务等级 Lv%s"], tostring(lvClient or q[4]))
            lvTxt = lvTxt .. (lvCol and DG.Hex(lvCol) .. lvSeg .. "|r" or lvSeg)
        end
    elseif lvClient or q[4] then
        local lvSeg = format(L["任务等级 Lv%s"], tostring(lvClient or q[4]))
        lvTxt = lvCol and DG.Hex(lvCol) .. lvSeg .. "|r" or lvSeg
    end
    local shareSeg
    do
        local push = DG.QLCall("IsPushableQuest", q[1])
        if push ~= nil then
            shareSeg = DG.Hex(C_GREY) .. L["共享"] .. "：|r"
                .. (push and DG.Hex(C_GREEN) .. L["可分享"] .. "|r"
                        or DG.Hex(C_RED) .. L["不可共享"] .. "|r")
        end
    end
    if lvTxt ~= "" then
        local f = takeKv()
        f:SetText(DG.Hex(C_GREY) .. L["可接等级"] .. "：|r" .. lvTxt
            .. (shareSeg and " · " .. shareSeg or ""))
        put(f, 24)
    elseif shareSeg then
        local f = takeKv()
        f:SetText(shareSeg)
        put(f, 24)
    end
    if q[13] and #q[13] > 0 then
        local parts = {}
        for _, d in ipairs(q[13]) do
            local dc = DG.Q_DIFF_COLOR[d[2]] or C_GREY
            parts[#parts + 1] = DG.Hex(dc) .. tostring(d[1]) .. "|r"
        end
        local f = takeKv()
        f:SetText(DG.Hex(C_GREY) .. L["任务难度"] .. "：|r" .. table.concat(parts, "  "))
        put(f, 24)
    end
    local where = q[5] or ""
    if q[6] then where = (where ~= "" and (where .. " · " .. q[6]) or q[6]) end
    if q[16] then
        local nm = (q[17] and q[17] ~= "" and q[17]) or q[5] or ""
        where = "|cffffd100" .. nm .. "|r" .. format(" |cff9a9a9a#%d|r", q[16])
        if q[6] then where = where .. " · " .. q[6] end
    end
    if where ~= "" then
        local f
        if q[16] then
            f = takeNpc()
            f.fs:SetText(DG.Hex(C_GREY) .. L["起始："] .. "|r" .. where)
            f.__npc = q[16]
        else
            f = takeKv()
            f:SetText(DG.Hex(C_GREY) .. L["起始："] .. "|r" .. where)
        end
        put(f, 24)
    end
    do
        local f = takeKv()
        local fac, facCol
        if q[2] == "A" then
            fac, facCol = L["联盟专属"], DG.C_FAC_A
        elseif q[2] == "H" then
            fac, facCol = L["部落专属"], DG.C_FAC_H
        else
            fac = L["双阵营共有"]
        end
        f:SetText(DG.Hex(C_GREY) .. L["阵营"] .. "：|r"
            .. (facCol and DG.Hex(facCol) .. fac .. "|r" or fac))
        put(f, 24)
    end
    if q[15] then
        local f = takeKv()
        f:SetText(DG.Hex(C_GREY) .. L["职业"] .. "：|r"
            .. DG.Hex(DG.QClassColor(q[15])) .. format(L["%s专属"], q[15]) .. "|r")
        put(f, 24)
    end
    y = y - 4

    do
        local nodes, seen = {}, { [q[1]] = true }
        local function collect(row, depth)
            if not row or depth > 30 or #nodes >= 30 then return end
            local pre = row[9]
            if not pre then return end
            for k = #pre, 1, -1 do
                local seg = pre[k]
                if type(seg) == "number" and not seen[seg] then
                    seen[seg] = true
                    local prow = DG.QuestRowByID(seg)
                    if not prow and ns.DungeonQuestPreExtra then
                        local ex = ns.DungeonQuestPreExtra[seg]
                        if ex then prow = { [1] = seg, [9] = ex } end
                    end
                    collect(prow, depth + 1)
                    nodes[#nodes + 1] = seg
                elseif type(seg) == "string" then
                    nodes[#nodes + 1] = seg
                end
            end
        end
        collect(q, 1)
        local pnote = ns.DungeonQuestPreNote and ns.DungeonQuestPreNote[q[1]]
        if #nodes > 0 or pnote then
            local f = takeLab()
            f:SetText(L["前导任务"])
            put(f, 20)
            local frontier = true
            for _, seg in ipairs(nodes) do
                local r = takeNode()
                if type(seg) == "number" then
                    local pnm, pok = DG.QuestName(seg)
                    local pst = DG.QuestState(seg)
                    local pcol = (pst == "done" and C_GREEN) or (pst == "active" and C_GOLD) or C_GREY
                    r.bar:SetColorTexture(pcol[1], pcol[2], pcol[3], 1)
                    r.name:SetText(pok and (pnm .. format(" |cff9a9a9a#%d|r", seg)) or pnm)
                    r.name:SetTextColor(Unpack(pok and pcol or C_GREY))
                    local stag = (pok and DG.Q_STATUS_TAG[pst]) or ""
                    local shex = format("%02x%02x%02x", pcol[1] * 255 + 0.5, pcol[2] * 255 + 0.5, pcol[3] * 255 + 0.5)
                    if frontier and pok and pst ~= "done" then
                        stag = "|cffffd100" .. L["下一步"] .. "|r" .. (stag ~= "" and (" · |cff" .. shex .. stag .. "|r") or "")
                        frontier = false
                    end
                    r.st:SetText(stag)
                    r.st:Show()
                    local prow = DG.QuestRowByID(seg)
                    local sub = ""
                    if prow then
                        sub = prow[5] or ""
                        if prow[6] then sub = (sub ~= "" and (sub .. " · " .. prow[6]) or prow[6]) end
                        if prow[3] then sub = sub .. " · " .. format(L["%d 级可接"], prow[3]) end
                    elseif ns.DungeonQuestPreExtra and ns.DungeonQuestPreExtra[seg] then
                        local ex = ns.DungeonQuestPreExtra[seg]
                        if ex.src and ex.src ~= "" then
                            sub = ex.src
                            if ex.lv then sub = sub .. " · " .. format(L["%d 级可接"], ex.lv) end
                        elseif ex.npc and ex.npc ~= "" then
                            sub = ex.npc
                            if ex.lv then sub = sub .. " · " .. format(L["%d 级可接"], ex.lv) end
                        end
                    end
                    if sub == "" then sub = L["本表未收录起始信息"] end
                    r.sub:SetText(sub)
                    r.__q = prow
                    r.__preID = seg
                    local nid = prow and prow[16] or nil
                    if not nid and ns.QuestPreNpcID then nid = ns.QuestPreNpcID[seg] end
                    r.__npc = nid
                else
                    r.bar:SetColorTexture(0.43, 0.4, 0.32, 1)
                    r.name:SetText(seg)
                    r.name:SetTextColor(Unpack(C_GREY))
                    r.st:Hide()
                    r.sub:SetText(L["前置 ID 未收录，查不了状态"])
                    r.__q = nil
                    r.__preID = nil
                    r.__npc = nil
                end
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
                r:Show()
                y = y - 38
            end
        end
        if pnote then
            local t = takeTxt()
            t:SetText(pnote)
            t:SetTextColor(Unpack(C_GREY))
            local h = t:GetStringHeight()
            put(t, (type(h) == "number" and h or 18) + 2)
        end
        y = y - 4
    end

    do
        local fol = DG.QuestFollowers(q[1])
        if #fol > 0 then
            local f = takeLab()
            f:SetText(L["后续任务"])
            put(f, 20)
            for _, fq in ipairs(fol) do
                local r = takeNode()
                local fnm, fok = DG.QuestName(fq[1])
                local fst = DG.QuestState(fq[1])
                local fcol = (fst == "done" and C_GREEN) or (fst == "active" and C_GOLD) or C_GREY
                r.bar:SetColorTexture(fcol[1], fcol[2], fcol[3], 1)
                r.name:SetText(fok and (fnm .. format(" |cff9a9a9a#%d|r", fq[1])) or fnm)
                r.name:SetTextColor(Unpack(fok and fcol or C_GREY))
                r.st:SetText(fok and (DG.Q_STATUS_TAG[fst] or "") or "")
                r.st:Show()
                local sub = fq[5] or ""
                if fq[6] then sub = (sub ~= "" and (sub .. " · " .. fq[6]) or fq[6]) end
                if sub == "" then sub = L["本表未收录起始信息"] end
                r.sub:SetText(sub)
                r.__q = fq
                r.__npc = fq[16]
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
                r:Show()
                y = y - 38
            end
        end
        y = y - 4
    end

    do
        local desc = DG.QuestDescription(q[1])
        if desc then
            local f = takeLab()
            f:SetText(L["任务说明"])
            put(f, 20)
            local t = takeTxt()
            t:SetText(desc)
            t:SetTextColor(Unpack(C_TEXT))
            local h = t:GetStringHeight()
            put(t, (type(h) == "number" and h or 18) + 4)
            y = y - 2
        end
    end

    do
        local note = q[12]
        if note then
            local f = takeLab()
            f:SetText(L["任务注释"])
            put(f, 20)
            local t = takeTxt()
            t:SetText(note)
            t:SetTextColor(Unpack(C_TEXT))
            local h = t:GetStringHeight()
            put(t, (type(h) == "number" and h or 18) + 4)
            y = y - 2
        end
    end

    local function renderChips(items, ncol, questID)
        local colW = math.floor((detW - 8) / ncol)
        for idx, iid in ipairs(items) do
            local r = takeChip()
            r:SetSize(colW, DG.Q_DET_ICON + 6)
            if questID then
                r.__q = questID
                r.name:SetWidth(colW - DG.Q_DET_ICON - 16 - 46)
            else
                r.__q = nil
                r.name:SetWidth(colW - DG.Q_DET_ICON - 16)
            end
            r.icon:SetTexture(DG.ItemIcon(iid))
            local inm, iok = DG.ItemName(iid)
            r.name:SetText(inm)
            if iok then
                local qr, qg, qb = DG.QColor(DG.QualOf(iid))
                if qr then
                    r.name:SetTextColor(qr, qg, qb)
                else
                    r.name:SetTextColor(Unpack(C_TEXT))
                end
            else
                r.name:SetTextColor(Unpack(C_GREY))
            end
            r.__named = iok
            r.__it = { iid }
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", child, "TOPLEFT",
                (idx - 1) % ncol * (colW + 8), y - math.floor((idx - 1) / ncol) * (DG.Q_DET_ICON + 8))
            r:Show()
            DG.ApplyChipBadge(r)
        end
        for _, iid in ipairs(items) do
            local _, iok = DG.ItemName(iid)
            DG.RequestItem(iid, not iok)
        end
        return math.ceil(#items / ncol)
    end
    do
        local objTxt = DG.NeedObjectivesText(q[1], q[14])
        if not objTxt and not DG.QuestObjectiveList(q[1]) and (DG.GAINS_FALLBACK or not q[11]) then
            objTxt = q[11]
        end
        local hasChips = q[14] and #q[14] > 0
        if hasChips or objTxt then
            local f = takeLab()
            f:SetText(L["任务需求"])
            put(f, 20)
            if hasChips then
                y = y - renderChips(q[14], 2, q[1]) * (DG.Q_DET_ICON + 8) - 2
            end
            if objTxt then
                local t = takeTxt()
                t:SetText(objTxt)
                t:SetTextColor(Unpack(C_TEXT))
                local h = t:GetStringHeight()
                put(t, (type(h) == "number" and h or 18) + 4)
                y = y - 2
            end
        end
    end
    local rew = q[10]
    if rew and #rew > 0 then
        local f = takeLab()
        f:SetText(L["任务奖励"])
        put(f, 20)
        y = y - renderChips(rew, 2) * (DG.Q_DET_ICON + 8) - 2
    end
    do
        local seg = DG.GainsSegs(q)
        if seg and #seg > 0 then
            local f = takeLab()
            f:SetText(L["收获"])
            put(f, 20)
            local txt = table.concat(seg, " · ")
            local t = takeTxt()
            t:SetText(txt)
            t:SetTextColor(Unpack(C_TEXT))
            local h = t:GetStringHeight()
            put(t, (type(h) == "number" and h or 18) + 4)
            y = y - 2
        end
    end

    do
        local t = takeTxt()
        t:SetText(L["状态来自你自己的任务日志，交完任务这里会自动变。"])
        t:SetTextColor(Unpack(C_DARKGREY))
        put(t, 22)
    end

    for i = pool.nLab + 1, #pool.lab do pool.lab[i]:Hide() end
    for i = pool.nKv + 1, #pool.kv do pool.kv[i]:Hide() end
    for i = pool.nTxt + 1, #pool.txt do pool.txt[i]:Hide() end
    for i = pool.nNode + 1, #pool.node do pool.node[i]:Hide() end
    for i = pool.nChip + 1, #pool.chip do pool.chip[i]:Hide() end
    for i = pool.nNpc + 1, #pool.npc do pool.npc[i]:Hide() end

    child:SetHeight(math.max(10, -y + 12))
    U.dungeonQDet:SetVerticalScroll(0)
end

function DG.GuideBossName(dungeonID, en)
    local loot = (ns.DungeonLoot or {})[dungeonID]
    if loot then
        for i = 1, #loot do
            if loot[i][1] == en then return loot[i][2] or en end
        end
    end
    return en
end

function U:RenderDungeonGuide()
    local d = U.dungeonDetailCur
    local child, pool = U.dungeonGuideChild, U.dungeonGuidePool
    if not (d and child and pool) then return end
    local g = (ns.DungeonGuide or {})[d.id]
    local cards = pool.card
    local nC = 0

    local function takeCard()
        nC = nC + 1
        local c = cards[nC]
        if not c then
            c = CreateFrame("Frame", nil, child, "BackdropTemplate")
            c:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            c:SetBackdropColor(1, 1, 1, DG.LOOT_CARD_BG)
            c:SetBackdropBorderColor(1, 1, 1, DG.LOOT_CARD_EDGE)
            c.stripe = c:CreateTexture(nil, "OVERLAY")
            c.stripe:SetWidth(DG.GUIDE_STRIPE)
            c.stripe:SetPoint("TOPLEFT", c, "TOPLEFT", 1, -1)
            c.stripe:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 1, 1)
            c.title = MakeFS(c, 16, C_GOLD, "LEFT")
            c.title:SetPoint("TOPLEFT", c, "TOPLEFT", DG.GUIDE_PAD + DG.GUIDE_STRIPE, -DG.GUIDE_PAD)
            c.rows = {}
            cards[nC] = c
        end
        c:Show()
        return c
    end

    local function takeT(c, w)
        local n = (c.n or 0) + 1
        c.n = n
        local f = c.rows[n]
        if not f then
            f = MakeFS(c, 14, C_TEXT, "LEFT")
            f:SetWordWrap(true)
            c.rows[n] = f
        end
        f:SetWidth(w)
        f:Show()
        return f
    end

    local function fillCard(c, def)
        c.n = 0
        c.title:SetText(def.label)
        c.stripe:SetColorTexture(def.accent[1], def.accent[2], def.accent[3], 1)
        local cy = -(DG.GUIDE_PAD + DG.GUIDE_HDR_H)
        local rows, last = def.rows, #def.rows
        for i = 1, last do
            local r = rows[i]
            local f = takeT(c, DG.GUIDE_CARD_W - DG.GUIDE_PAD * 2 - (r.x or 0))
            f:SetTextColor(Unpack(r.c or C_TEXT))
            f:SetText(r.t)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", c, "TOPLEFT", DG.GUIDE_PAD + (r.x or 0), cy)
            local sh = f:GetStringHeight()
            cy = cy - (type(sh) == "number" and sh or 18) - (i == last and 0 or (r.gap or 4))
        end
        for i = c.n + 1, #c.rows do c.rows[i]:Hide() end
        return -cy + DG.GUIDE_PAD
    end

    local defs = {}
    if g then
        if g.tagline or (g.tips and #g.tips > 0) then
            local rows = {}
            if g.tagline then
                rows[#rows + 1] = { t = "· " .. g.tagline, c = C_TEXT, x = 0, gap = 5 }
            end
            if g.tips then
                for i = 1, #g.tips do
                    rows[#rows + 1] = { t = "· " .. g.tips[i], c = C_TEXT, x = 0, gap = 5 }
                end
            end
            defs[#defs + 1] = { label = L["副本须知"], accent = DG.GUIDE_ACCENT[1], rows = rows }
        end
        if g.entrance and (g.entrance.H or (g.entrance.A and #g.entrance.A > 0)) then
            local rows = {}
            if g.entrance.H then
                rows[#rows + 1] = { t = L["部落："] .. g.entrance.H, c = C_TEXT, x = 0, gap = 6 }
            end
            if g.entrance.A and #g.entrance.A > 0 then
                rows[#rows + 1] = { t = L["联盟："], c = C_TEXT, x = 0, gap = 2 }
                for i = 1, #g.entrance.A do
                    rows[#rows + 1] = { t = i .. ". " .. g.entrance.A[i], c = C_TEXT, x = 12, gap = 4 }
                end
            end
            defs[#defs + 1] = { label = L["怎么进本"], accent = DG.GUIDE_ACCENT[2], rows = rows }
        end
        if g.bosses and #g.bosses > 0 then
            local rows = {}
            for i = 1, #g.bosses do
                local b = g.bosses[i]
                local cn = DG.GuideBossName(d.id, b.en)
                rows[#rows + 1] = { t = (cn ~= b.en) and (cn .. "（" .. b.en .. "）") or b.en,
                                    c = C_GOLD, x = 0, gap = 3 }
                rows[#rows + 1] = { t = b.text, c = C_TEXT, x = 0, gap = 9 }
            end
            defs[#defs + 1] = { label = L["BOSS 打法"], accent = DG.GUIDE_ACCENT[3], rows = rows }
        end
        if g.trash and #g.trash > 0 then
            local rows = {}
            for i = 1, #g.trash do
                rows[#rows + 1] = { t = g.trash[i].title, c = C_GOLD, x = 0, gap = 3 }
                rows[#rows + 1] = { t = g.trash[i].text, c = C_TEXT, x = 0, gap = 9 }
            end
            defs[#defs + 1] = { label = L["小怪应对"], accent = DG.GUIDE_ACCENT[4], rows = rows }
        end
    end

    if #defs == 0 then
        if not pool.note then
            pool.note = MakeFS(child, 14, C_GREY, "LEFT")
            pool.note:SetWordWrap(true)
        end
        local f = pool.note
        f:SetWidth(DG.CHILD_W)
        f:SetText(L["这个副本还没有攻略，数据补上后会自动出现。"])
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
        f:Show()
        for i = 1, #cards do cards[i]:Hide() end
        child:SetHeight(30)
        U.dungeonGuideScroll:SetVerticalScroll(0)
        return
    end
    if pool.note then pool.note:Hide() end

    local list = {}
    for k = 1, #defs do
        local c = takeCard()
        list[k] = { frame = c, h = fillCard(c, defs[k]) }
    end

    local top, i = 0, 1
    while i <= #list do
        local a, b = list[i], list[i + 1]
        local rh = a.h
        if b and b.h > rh then rh = b.h end
        a.frame:ClearAllPoints()
        a.frame:SetPoint("TOPLEFT", child, "TOPLEFT", DG.GUIDE_SIDE, top)
        a.frame:SetSize(DG.GUIDE_CARD_W, rh)
        if b then
            b.frame:ClearAllPoints()
            b.frame:SetPoint("TOPLEFT", child, "TOPLEFT", DG.GUIDE_SIDE + DG.GUIDE_CARD_W + DG.GUIDE_GAP_X, top)
            b.frame:SetSize(DG.GUIDE_CARD_W, rh)
        end
        top = top - rh - DG.GUIDE_GAP_Y
        i = i + 2
    end

    for i = nC + 1, #cards do cards[i]:Hide() end
    child:SetHeight(math.max(10, -top - DG.GUIDE_GAP_Y + DG.GUIDE_PAD))
    U.dungeonGuideScroll:SetVerticalScroll(0)
end

function U:SetDungeonTab(tab)
    local t = "loot"
    if tab == "quest" then t = "quest" elseif tab == "guide" then t = "guide" elseif tab == "map" then t = "map" end
    U.dungeonTab = t
    DB().dungeonTab = t
    U:RenderDungeonTab()
    ns.PlaySound(1)
end

function U:RenderDungeonTab()
    local cur = U.dungeonTab or "loot"
    local isQuest = (cur == "quest")
    local isGuide = (cur == "guide")
    local isMap = (cur == "map")

    -- ★★★ 顺序：**先补建、再切显隐**（2026-10-03 实机回归：/reload 后恢复上次「地图」页签 → 整页空白）
    --   下面的可见性块全是 `if U.xxx then U.xxx:SetShown(isX) end` ——「引用存在才切」。
    --   而懒建之后，本页签的容器完全可能**到这一刻才第一次被建出来**（详情页刚懒建完、
    --   分帧还没轮到）。于是那几行 SetShown 拿到 nil 直接跳过，容器以**隐藏态**诞生
    --   （EnsureQuestLane / EnsureGuideLane 主动 Hide；地图页 M.Build 也 Hide）⇒
    --   内容全画进了看不见的帧里 = 页签一片空白，要等下一次 RenderDungeonTab
    --   （切走再切回）才恢复。
    --   ★ 实机指纹：关闭时停在「地图」页 → /reload → 打开副本详情直接恢复地图页
    --   → 空地图；切到掉落再切回地图就好了。
    --   ✅ 因此把「渲染分派」整体提到可见性块**之前**：Ensure* 先把容器建出来并渲染内容，
    --      后面的 SetShown 才切得动。与 U:UpdateDungeons 的总览分支同一顺序（Ensure 在前）。
    if isQuest then
        DG.EnsureQuestLane()
        U:RenderDungeonQuests()
    elseif isGuide then
        DG.EnsureGuideLane()
        U:RenderDungeonGuide()
    elseif isMap then
        DG.EnsureMapPage()
        if ns.MapModule then ns.MapModule.Paint(U.dungeonDetailCur) end
    else
        U:RenderDungeonLoot()
    end
    if U.dungeonDetailScroll then U.dungeonDetailScroll:SetShown(not isQuest and not isGuide and not isMap) end
    if U.dungeonGuideScroll then U.dungeonGuideScroll:SetShown(isGuide) end
    if U.dungeonMapFrame then U.dungeonMapFrame:SetShown(isMap) end
    if U.dungeonQuestScroll then U.dungeonQuestScroll:SetShown(isQuest) end
    if U.dungeonQDet then U.dungeonQDet:SetShown(isQuest) end
    if U.dungeonQPlateL then U.dungeonQPlateL:SetShown(isQuest) end
    if U.dungeonQPlateR then U.dungeonQPlateR:SetShown(isQuest) end
    do
        local LFUI = ns.LootFilterUI
        if cur == "loot" then
            if LFUI then LFUI:EnsureBar(); LFUI:RefreshBar() end
            if U.lootFilterBar then U.lootFilterBar:Show() end
        else
            if U.lootFilterBar then U.lootFilterBar:Hide() end
        end
    end
    DG.ApplyDetailChrome(cur)
end
DG.CAPSULE_LIFT = 10
DG.CAPSULE_W = 82
local function BuildSubTabs()
    local defs = {
        { key = "Dungeons", text = L["5人本"], width = DG.CAPSULE_W },
        { key = "Raids",    text = L["团本"],  width = DG.CAPSULE_W },
    }
    if ns.LoadForeverPages then
        defs[#defs + 1] = { key = "Professions", text = L["专业"], width = DG.CAPSULE_W }
        defs[#defs + 1] = { key = "Explore", text = L["探索"], width = DG.CAPSULE_W }
        defs[#defs + 1] = { key = "Bis", text = L["BIS配装"], width = DG.CAPSULE_W }
        defs[#defs + 1] = { key = "Tier", text = L["职业指南"], width = DG.CAPSULE_W }
    end
    local BTN_H = IsHui() and 20 or 26
    local GAP = IsHui() and 0 or 6
    local totalW = 0
    for i, t in ipairs(defs) do
        totalW = totalW + t.width
        if i > 1 then totalW = totalW + GAP end
    end
    local host = CreateFrame("Frame", nil, U.panel)
    host:SetSize(totalW, BTN_H)
    host:SetPoint("TOP", U.panel, "TOP", 0, DG.CAPSULE_LIFT - ROW_SUB)

    local ctrl
    if IsHui() and ns.hui and ns.hui.CreateSegmentedControl then
        ctrl = ns.hui.CreateSegmentedControl(host)
    end

    local btns, prev = {}, nil
    for _, tab in ipairs(defs) do
        local bt
        if ctrl then
            bt = CreateFrame("Button", nil, host)
            bt:SetSize(tab.width, BTN_H)
            if prev then
                bt:SetPoint("LEFT", prev, "RIGHT", 0, 0)
            else
                bt:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            end
            local t = bt:CreateFontString()
            t:SetAllPoints()
            t:SetFont(Fnt(14))
            t:SetText(tab.text)
            t:SetWordWrap(false)
            t:SetTextColor(Unpack(C_DIM))
            bt:SetFontString(t)
        else
            bt = NewButton(host, tab.text, tab.width, BTN_H, 14)
            if prev then
                bt:SetPoint("LEFT", prev, "RIGHT", GAP, 0)
            else
                bt:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            end
        end
        prev = bt
        btns[#btns + 1] = bt
        tab.button = bt
        bt:SetScript("OnClick", function()
            U:SwitchSub(tab.key)
            ns.PlaySound(1)
        end)
    end
    if ctrl then ctrl:AttachButtons(btns) end
    U.subTabs = defs
    U.subCtrl = ctrl
end

-- ══════════════════════════════════════════════════════════════════════
-- ★★ 懒构建 + 分帧预热（2026-10-03，实机「打开界面整窗变灰」）
--   实测：首屏 U:Build() 原本无条件同步构建全部 6 个页面共 1673 帧
--   （不含纹理/字体串）→ 阻塞主线程。
--   现在：U:Build() 只建「当前子页」；其余页由 U:EnsureBuilt 在首次切到时同步建，
--         并由 U:SchedulePrebuild 在随后空闲帧里逐页补建 → 切页依然零等待。
--   幂等：各模块自带 built 闸；U.subBuilt 记录已触发过的页。
-- ══════════════════════════════════════════════════════════════════════
function U:EnsureBuilt(k)
    if k == "Dungeons" then
        DG.BuildDungeons()          -- 副本页原本就懒建（U.dungeonBuilt 幂等）
        return
    end
    if not U.subBuilt then U.subBuilt = {} end
    if U.subBuilt[k] then return end
    if k == "Raids" and ns.RaidModule and U.raidPage then
        U.subBuilt[k] = true
        ns.RaidModule.Build(U.raidPage)
    elseif k == "Professions" and ns.ProfModule and U.profPage then
        U.subBuilt[k] = true
        ns.ProfModule.Build(U.profPage)
    elseif k == "Explore" and ns.ExploreModule and U.explorePage then
        U.subBuilt[k] = true
        ns.ExploreModule.Build(U.explorePage)
    elseif k == "Bis" and ns.BisModule and U.bisPage then
        U.subBuilt[k] = true
        ns.BisModule.Build(U.bisPage)
    elseif k == "Tier" and ns.TierModule and U.tierPage then
        U.subBuilt[k] = true
        ns.TierModule.Build(U.tierPage)
    end
end

-- ★ 分帧预热：首屏只需付「当前子页」的建帧成本；其余页在随后的空闲帧里逐页补建。
--   切页因此仍是「零等待」，而打开动作不再被 6 页的建帧量一次性阻塞。
--   C_Timer 不可用时直接返回，退化为「首次切到时同步建」（U:EnsureBuilt 兜底）。
function U:SchedulePrebuild()
    if U.prebuildOn then return end
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
    U.prebuildOn = true
    local order = { "Raids" }
    if ns.LoadForeverPages then
        order[#order + 1] = "Professions"
        order[#order + 1] = "Explore"
        order[#order + 1] = "Bis"
        order[#order + 1] = "Tier"
    end
    local left = 0
    for _, k2 in ipairs(order) do
        if not (U.subBuilt and U.subBuilt[k2]) then left = left + 1 end
    end
    if left == 0 then return end     -- 全部建齐：不再排程（每次开窗都排会白跑一轮）
    local i = 0
    local function step()
        local frame = ns.TalentSimFrame
        if not frame or not frame:IsShown() then
            U.prebuildOn = false            -- 界面已关：停止预热，下次开窗重启排程
            return
        end
        i = i + 1
        local k = order[i]
        if not k then U.prebuildOn = false return end
        if k ~= U.curSub then U:EnsureBuilt(k) end
        if order[i + 1] then
            C_Timer.After(0.2, step)     -- 0.2s：给主线程留喘息，切页前基本已建好
        else
            U.prebuildOn = false
        end
    end
    C_Timer.After(0.6, step)
end

function U:SwitchSub(key)
    local k = "Dungeons"
    if key == "Raids" then
        k = "Raids"
    elseif key == "Professions" and ns.LoadForeverPages then
        k = "Professions"
    elseif key == "Explore" and ns.LoadForeverPages then
        k = "Explore"
    elseif key == "Bis" and ns.LoadForeverPages then
        k = "Bis"
    elseif key == "Tier" and ns.LoadForeverPages then
        k = "Tier"
    end
    U.curSub = k
    DB().subTab = k
    local isDun, isRaid, isProf, isExpl, isBis, isTier = (k == "Dungeons"), (k == "Raids"), (k == "Professions"), (k == "Explore"), (k == "Bis"), (k == "Tier")
    if U.dungeonPage then U.dungeonPage:SetShown(isDun) end
    if U.raidPage then U.raidPage:SetShown(isRaid) end
    if U.profPage then U.profPage:SetShown(isProf) end
    if U.explorePage then U.explorePage:SetShown(isExpl) end
    if U.bisPage then U.bisPage:SetShown(isBis) end
    if U.tierPage then U.tierPage:SetShown(isTier) end
    if isRaid then
        U:EnsureBuilt("Raids")
    elseif isDun then
        DG.BuildDungeons()
        U:UpdateDungeons()
    elseif isProf and ns.ProfModule then
        U:EnsureBuilt("Professions")
        ns.ProfModule.Open()
    elseif isExpl and ns.ExploreModule then
        U:EnsureBuilt("Explore")
        ns.ExploreModule.Open()
    elseif isBis and ns.BisModule then
        U:EnsureBuilt("Bis")
        ns.BisModule.Open()
    elseif isTier and ns.TierModule then
        U:EnsureBuilt("Tier")
        ns.TierModule.Refresh()
    end
    for _, tab in ipairs(U.subTabs or {}) do
        local selected = (tab.key == k)
        if U.subCtrl and selected then U.subCtrl:SetSelected(tab.button, true) end
        tab.button:GetFontString():SetTextColor(Unpack(selected and C_WHITE or C_DIM))
    end
end

function U:UpdateActiveSub()
    if self.curSub == "Raids" then return end
    if self.curSub == "Professions" then
        if ns.ProfModule then ns.ProfModule.Refresh() end
        return
    end
    if self.curSub == "Explore" then
        if ns.ExploreModule then ns.ExploreModule.Refresh() end
        return
    end
    if self.curSub == "Bis" then
        if ns.BisModule then ns.BisModule.Refresh() end
        return
    end
    if self.curSub == "Tier" then
        if ns.TierModule then ns.TierModule.Refresh() end
        return
    end
    self:UpdateDungeons()
end

function U:Build()
    if U.built or U.building then return end
    FONT_BASE = FONT_BASE or ns.FONT
    if not FONT_BASE then return end
    U.building = true
    DG.Loader.Init()          -- ★ 载入速度档位（/dfspeed），默认标准 4ms

    local saved = DB().subTab
    if saved == "Raids" then
        U.curSub = "Raids"
    elseif saved == "Professions" and ns.LoadForeverPages then
        U.curSub = "Professions"
    elseif saved == "Explore" and ns.LoadForeverPages then
        U.curSub = "Explore"
    elseif saved == "Bis" and ns.LoadForeverPages then
        U.curSub = "Bis"
    elseif saved == "Tier" and ns.LoadForeverPages then
        U.curSub = "Tier"
    else
        U.curSub = "Dungeons"
    end

    local panel = EnsureContent()
    U.dungeonPage = CreateFrame("Frame", nil, panel)
    U.dungeonPage:SetAllPoints(panel)
    U.dungeonPage:Hide()

    U.raidPage = CreateFrame("Frame", nil, panel)
    U.raidPage:SetAllPoints(panel)
    U.raidPage:Hide()
    -- ★ 懒构建：团本页内容见 U:EnsureBuilt("Raids")，首屏不再整包建帧

    if ns.LoadForeverPages then
        U.profPage = CreateFrame("Frame", nil, panel)
        U.profPage:SetAllPoints(panel)
        U.profPage:Hide()
        -- ★ 懒构建：专业页内容见 U:EnsureBuilt("Professions")
        U.explorePage = CreateFrame("Frame", nil, panel)
        U.explorePage:SetAllPoints(panel)
        U.explorePage:Hide()
        -- ★ 懒构建：探索页内容见 U:EnsureBuilt("Explore")
        U.bisPage = CreateFrame("Frame", nil, panel)
        U.bisPage:SetAllPoints(panel)
        U.bisPage:Hide()
        -- ★ 懒构建：BIS 配装页内容见 U:EnsureBuilt("Bis")
        U.tierPage = CreateFrame("Frame", nil, panel)
        U.tierPage:SetAllPoints(panel)
        U.tierPage:Hide()
        -- ★ 懒构建：职业指南页内容见 U:EnsureBuilt("Tier")
    end

    U.dungeonBuilt = false
    DG.__chromeOnly = nil
    U.detailBuilt = nil
    U.overviewBuilt = nil
    U.cardPoolBuilt = nil
    U.questLaneBuilt = nil
    U.guideLaneBuilt = nil
    U.mapPageBuilt = nil
    U.dungeonListChild = nil
    U.dungeonListPool = nil
    U.dungeonListLevel = nil
    U.dungeonDetailChild = nil
    U.dungeonDetailHero = nil
    U.dungeonDetailPool = nil
    U.dungeonDetailNote = nil
    U.dungeonDetailCur = nil
    U.dungeonFilterBtns = nil
    U.dungeonLootViewBtns = nil
    U.dungeonDetailTipZone = nil
    U.dungeonDetailHover = nil
    U.dungeonQuestScroll = nil
    U.dungeonQuestChild = nil
    U.dungeonQuestPool = nil
    U.dungeonQuestSum = nil
    U.dungeonQuestNote = nil
    U.dungeonQuestHover = nil
    U.dungeonGuideScroll = nil
    U.dungeonGuideChild = nil
    U.dungeonGuidePool = nil
    U.dungeonMapFrame = nil
    U.dungeonTabBtns = nil
    U.dungeonQDet = nil
    U.dungeonQDetChild = nil
    U.dungeonQDetPool = nil
    U.dungeonQDetName = nil
    U.dungeonQDetSt = nil
    U.dungeonQuestSel = nil
    U.dungeonQSide = nil
    U.dungeonView = (DB().dungeonView == "overview") and "overview" or "list"
    U.dungeonFilter = DB().dungeonFilter or "all"
    U.dungeonLootBoss = DB().dungeonLootBoss
    U.dungeonQFilter = DB().dungeonQuestFilter or "all"
    -- ★ 掉落页显示方式（"list" / "card"）：缺省列表，选中卡片视图跨会话记住
    U.lootView = (DB().lootView == "card") and "card" or "list"
    do
        local dt = DB().dungeonTab
        U.dungeonTab = (dt == "quest" or dt == "guide" or dt == "map") and dt or "loot"
    end
    U.sourceCredits = {}
    -- ★ 懒构建账本：记录已被触发建过的子页（见 U:EnsureBuilt）
    U.subBuilt = {}

    BuildSubTabs()

    MakeSourceCredit(panel, L["数据来源：wowhead"], "https://www.wowhead.com/forever")

    U:SwitchSub(U.curSub)
    U.building = false
    U.built = true
end

function U:Refresh()
    if not U.built then return end
    self:UpdateDungeons()
end

ns.Init(function()
    local frame = ns.TalentSimFrame
    if not frame then return end
    frame:SetScript("OnShow", function()
        FONT_BASE = FONT_BASE or ns.FONT
        if not U.built then
            U.building = false
            local ok, err = xpcall(U.Build, function(e)
                return tostring(e) .. "\n" .. debugstack(2, 40)
            end, U)
            if not ok then
                U.building = false
                U.built = false
                print("|cff46bf72[无限副本手册] 界面构建出错：|r" .. tostring(err))
                return
            end
        end
        U:UpdateActiveSub()
        -- ★ 懒构建：其余子页在随后空闲帧里逐页补建（首屏只建了当前页）
        U:SchedulePrebuild()
    end)
    frame:SetScript("OnHide", function()
        GameTooltip:Hide()
        U.dungeonDetailHover, U.dungeonQuestHover = nil, nil
        U.dungeonMapHover = nil
    end)
end)

ns.ProfHost = {
    U = U, DG = DG,
    MakeFS = MakeFS, NewButton = NewButton, MakeOutline = MakeOutline,
    SetOutline = SetOutline, SetTip = SetTip, Unpack = Unpack,
    C_GOLD = C_GOLD, C_GREEN = C_GREEN, C_GREY = C_GREY,
    C_DIM = C_DIM, C_WHITE = C_WHITE, C_TEXT = C_TEXT,
    CONTENT_W = CONTENT_W, CONTENT_H = CONTENT_H,
    PAGE_INSET = PAGE_INSET, ROW_CLASS = ROW_CLASS,
    FALLBACK_ICON = FALLBACK_ICON,
}

function ns.OpenPage(key)
    local frame = ns.TalentSimFrame
    if not frame then return end
    if not frame:IsShown() then frame:Show() end
    frame:Raise()
    if U.built then U:SwitchSub(key) end
end

-- 供「快捷按钮栏」调用：切到副本页并直接打开该副本的详情（id 不存在则不动）。
function ns.ShowDungeonDetail(id)
    local d
    for _, x in ipairs((ns.DungeonData and ns.DungeonData.dungeons) or {}) do
        if x.id == id then d = x break end
    end
    if not d then return end
    ns.OpenPage("Dungeons")
    if U.built and U.dungeonBuilt then
        U:SetDungeonView("list")
        U:ShowDungeonDetail(d)
    end
end
