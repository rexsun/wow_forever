-- =============================================================================
-- DungeonsForever · 团本页（界面层）
-- 时间线 / 列表两个子页，渲染本文件内联的团本排期静态表；全端可见。
-- =============================================================================

local _, ns = ...

local format = string.format
local floor = math.floor
local L = ns.L

local Host = ns.ProfHost
if not Host then return end

local MakeFS = Host.MakeFS
local NewButton = Host.NewButton
local MakeOutline, SetOutline = Host.MakeOutline, Host.SetOutline
local Unpack = Host.Unpack
local C_GOLD, C_GREY = Host.C_GOLD, Host.C_GREY
local C_DIM, C_WHITE, C_TEXT = Host.C_DIM, Host.C_WHITE, Host.C_TEXT
local PAGE_INSET = Host.PAGE_INSET
local CONTENT_W = Host.CONTENT_W

local RU = {}
ns.RaidModule = RU

RU.X = PAGE_INSET
RU.W = CONTENT_W - 2 * PAGE_INSET
RU.CARD_TOP = 8
RU.LIST_Y = 16
RU.CARD_BOTTOM = PAGE_INSET

RU.GRID_PAD = 8
RU.GRID_X = 0
RU.LS_LABEL_H = 26
RU.LS_COLS = 2
RU.LS_COL_H = 145
RU.LS_GAP = 8
RU.LS_COL_W = math.floor((RU.W - 2 * RU.GRID_PAD - (RU.LS_COLS - 1) * RU.LS_GAP) / RU.LS_COLS)

RU.CN_SHIFT = 1

RU.DATA = {
    updated = "2026-09-24",
    unlockAt = 1796850000,
    firstOpen = { y = 2026, m = 12, d = 9 },
    raids = {
        { name = "深穴", size = 10, first = true },
        { name = "海加尔峰", size = 20, zone = "海加尔山", first = true },
        { name = "奥妮克希亚的巢穴", size = 40, zone = "尘泥沼泽", first = true, entry = true },
        { size = 10, date = "2027 春季" },
        { size = 20, date = "2027 春季" },
        { name = "经典团本重制", date = "2027 夏季" },
        { date = "2027 夏季" },
    },
    rules = {
        { "单一难度", "团本不分普通 / 英雄 / 史诗，只有一档" },
        { "固定人数", "10 / 20 / 40 人三档，没有弹性人数" },
        { "无随机团本", "需自行组队，再跑本到团本门口" },
        { "等级上限 60", "后续团本横向铺开，不抬等级上限" },
        { "套装跨团本", "新职业套装件分散在不同团本里" },
        { "禁止 GDKP", "官方明确不支持金币分配团" },
    },
}

RU.DETAILS = {
    ["奥妮克希亚的巢穴"] = {
        id = "onyxias_lair",
        nameEn = "Onyxia's Lair",
        levelMin = 60,
        levelMax = 60,
        zone = "尘泥沼泽",
        bosses = { "奥妮克希亚" },
    },
}

local function DB()
    local db = ns.DB()
    db.raid = db.raid or {}
    return db.raid
end

local function SizeColor(n)
    if n == 10 then return 0.42, 0.66, 0.86 end
    if n == 20 then return 0.52, 0.77, 0.55 end
    if n == 40 then return 0.91, 0.65, 0.29 end
    return 0.40, 0.40, 0.40
end

local function SizeText(n)
    if type(n) == "number" then return format("%d%s", n, L["人"]) end
    return L["未公布"]
end

local function IsCnClient()
    return type(GetLocale) == "function" and GetLocale() == "zhCN"
end

function RU.DayShift(cn)
    if cn == nil then cn = IsCnClient() end
    return cn and RU.CN_SHIFT or 0
end

function RU.UnlockAt(shift)
    return RU.DATA.unlockAt + RU.DayShift(shift) * 86400
end

function RU.FirstOpenText(shift)
    local f = RU.DATA.firstOpen
    return format(L["%d 年 %d 月 %d 日"], f.y, f.m, f.d + RU.DayShift(shift))
end

local function RecDateText(rec)
    if rec.date then return rec.date end
    if rec.first then return RU.FirstOpenText() end
    return L["未公布"]
end

function RU.PickClock(env)
    if type(env) ~= "table" then return nil end
    if type(env.time) == "function" then return env.time end
    if type(env.serverTime) == "function" then return env.serverTime end
    if type(env.os) == "table" and type(env.os.time) == "function" then
        return env.os.time
    end
    return nil
end

local Clock = RU.PickClock({ time = _G.time,
                             serverTime = _G.GetServerTime,
                             os = _G.os })

function RU.NowSec()
    if Clock then return Clock() end
    return nil
end

function RU.CountdownText(nowSec, shift)
    local now = nowSec or RU.NowSec()
    local target = RU.UnlockAt(shift)
    if type(now) ~= "number" or type(target) ~= "number" then return "" end
    local remain = target - now
    if remain <= 0 then return L["已开启"] end
    local d = floor(remain / 86400)
    local h = floor(remain % 86400 / 3600)
    local m = floor(remain % 3600 / 60)
    return format(L["距首批开放还有 %d 天 %d 小时 %d 分"], d, h, m)
end

local function BuildTiers()
    local big, small = {}, {}
    for _, rec in ipairs(RU.DATA.raids) do
        if rec.first then big[#big + 1] = rec else small[#small + 1] = rec end
    end
    return big, small
end

local function CardEdge(c, r, g, b, a)
    a = a or 1
    if c.__rborder then
        for _, t in ipairs(c.__rborder) do
            t:SetVertexColor(r, g, b)
            t:SetAlpha(a)
        end
    else
        c:SetBackdropBorderColor(r, g, b, a)
    end
end

function RU.LayoutCards(list, w, h, y0)
    local perRow = math.max(1, floor((RU.W + RU.LS_GAP) / (w + RU.LS_GAP)))
    local out, col, row = {}, 0, 0
    for i = 1, #list do
        if col >= perRow then
            col, row = 0, row + 1
        end
        out[i] = {
            x = RU.GRID_X + col * (w + RU.LS_GAP),
            y = -(y0 + row * (h + RU.LS_GAP)),
        }
        col = col + 1
    end
    out.rows = row + 1
    out.bottom = y0 + row * (h + RU.LS_GAP) + h
    return out
end

function RU.NewCard(page)
    local c = CreateFrame("Button", nil, page, "BackdropTemplate")
    c:EnableMouse(true)
    c:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    c:SetBackdropColor(0, 0, 0, 0)
    c:SetBackdropBorderColor(1, 1, 1, 0.10)
    local rounded = false
    local layer = ns.hui and ns.hui.layer
    if ns.hui and ns.hui.BuildRoundedBG and layer then
        ns.hui.BuildRoundedBG(c, 6, layer.L2, "both", false)
        c:SetBackdropBorderColor(0, 0, 0, 0)
        if ns.hui.BuildRoundBorder then
            c.__rborder = ns.hui.BuildRoundBorder(c, 6, ns.hui.CARD_BORDER, c, "OVERLAY", "both", 1)
        end
        rounded = true
    end
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints(c)
    c.bg:SetColorTexture(0, 0, 0, 0.35)
    c.bg:SetShown(not rounded)
    c.art = c:CreateTexture(nil, "BACKGROUND", nil, 2)
    c.art:SetAllPoints(c)
    c.art:Hide()
    if rounded and ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(c.art) end
    c.dim = c:CreateTexture(nil, "ARTWORK")
    c.dim:SetAllPoints(c)
    c.dim:SetColorTexture(0, 0, 0, 0.38)
    c.dim:Hide()
    c.name = MakeFS(c, 16, C_WHITE, "LEFT")
    c.name:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -22)
    c.size = MakeFS(c, 14, C_GREY, "RIGHT")
    c.size:SetPoint("TOPRIGHT", c, "TOPRIGHT", -20, -24)
    c.zone = MakeFS(c, 14, C_DIM, "LEFT")
    c.zone:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -58)
    c.date = MakeFS(c, 14, C_GOLD, "LEFT")
    c.date:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -86)
    c.__hovOn = false
    c:SetScript("OnEnter", function(self)
        self.__hovOn = true
        CardEdge(self, 1, 1, 1, 0.9)
        if self.rec and RU.DETAILS[self.rec.name] then
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:ClearLines()
            GameTooltip:SetText(L["点击查看详情"])
            GameTooltip:Show()
        end
    end)
    c:SetScript("OnLeave", function(self)
        self.__hovOn = false
        local e = self.__edge
        if e then CardEdge(self, e[1], e[2], e[3], e[4]) end
        GameTooltip:Hide()
    end)
    c:SetScript("OnClick", function(self)
        if self.rec and RU.DETAILS[self.rec.name] then RU.OpenDetail(self.rec.name) end
    end)
    return c
end

function RU.PaintCard(c, rec, ec, ea)
    c.rec = rec
    local det = RU.DETAILS[rec.name]
    c.name:SetText(rec.name or L["未定名团本"])
    c.name:SetTextColor(Unpack(rec.first and C_WHITE or C_DIM))
    c.size:SetText(SizeText(rec.size))
    local cr, cg, cb = SizeColor(rec.size)
    c.size:SetTextColor(cr, cg, cb)
    local where = rec.zone and L[rec.zone] or L["地点未公布"]
    if det and det.levelMin then
        where = where .. " · " .. format(L["等级 %d"], det.levelMin)
    end
    c.zone:SetText(where)
    c.zone:SetTextColor(Unpack(rec.first and C_DIM or C_GREY))
    c.date:SetText(RecDateText(rec))
    c.date:SetTextColor(Unpack(rec.first and C_GOLD or C_DIM))
    c.__edge = { ec[1], ec[2], ec[3], ea or 0.7 }
    if c.IsMouseOver and c:IsMouseOver() then
        c.__hovOn = true
        CardEdge(c, 1, 1, 1, 0.9)
    else
        c.__hovOn = false
        CardEdge(c, ec[1], ec[2], ec[3], ea or 0.7)
    end
    local art, coord
    if det and ns.DungeonUI and ns.DungeonUI.CardArtFor then
        art, coord = ns.DungeonUI.CardArtFor({ id = det.id })
    end
    if art then
        c.art:SetTexture(art)
        if coord then c.art:SetTexCoord(coord[1], coord[2], coord[3], coord[4])
        else c.art:SetTexCoord(0, 1, 0, 1) end
        c.art:SetShown(true)
        c.dim:SetShown(true)
        c.bg:SetAlpha(0)
    else
        c.art:SetShown(false)
        c.dim:SetShown(false)
        c.bg:SetAlpha(1)
    end
    c:SetShown(true)
end

-- =============================================================================
-- 第三子页签：套装（数据 Core/Data/Data_RaidSets.lua 的 ns.RaidSetData）
--
-- ★ 与另两子页共用同一个三行头（标题 / 说明 / 二级页签）：第三枚页签占
--   x = 178…254。正文顶仍是 RU.BODY_Y（时间线 / 列表两页共用）。
-- ★ 卡片**不显示部位行**（用户 2026-09-30 拍板删除）：一套恒 6 件，件数并入
--   副行末尾，腾出的高度给效果区。数据层因此不存 slots。
-- ★ 筛选默认锁当前登录职业（用户 2026-09-30 拍板）；再点已选中的职业退回「全部」。
-- ★ 版式（用户 2026-09-30 二次定稿）：
--   ① 卡内文本一律 14 号（原 11）；芯片尺度比照三枚二级页签 —— 高 24、字号 14、
--      文字取**职业色**（「全部」非职业，用中性色），选中态只靠金色描边区分；
--   ② 卡片底色走 HUI 色阶 **L2**（比面板亮一档），悬停再提亮到 **L3**；
--   ③ 卡片四角倒圆角（ns.hui.BuildRoundedBG 原语：弧盘 + 1px 描边）；
--   ④ 左侧竖向强调条**已整条删除**（用户 2026-09-30 三次定稿追加：卡内只留徽记 +
--      名称行 + 效果区，不再贴职业色竖条）。建帧与着色两处都撤，帧名一并不再占用。
-- ★ 版式（用户 2026-09-30 三次定稿）：
--   ⑤ 副行（职业 · 专精 · 护甲 · N 件套）不再独占一行，**并到名称右手边同排**
--      —— 头部只剩一行，正文顶随之上提到 SET_BODY_Y（60 → 46）；
--   ⑥ **不再渲染「技能状态标注」行**（原「改动 / 原样 + 天赋树位置 + 补充说明」）：
--      用户 2026-09-30 明确不需要 ⇒ 标注帧、状态配音/配色的两张表、条数上限常量与
--      整条渲染路径一并撤掉。数据层的标注字段仅作研究数据留存（见 Data_RaidSets.lua
--      头注），界面一概不读。
--      ⚠️ 静态断言钉的是「RaidUI 里不许再出现标注相关标识符」⇒ **本注释里也绝不能写出
--         那些标识符字面量**，否则会被自家注释误红（2026-09-30 踩过一次，见日志）。
-- ★★ 版式五稿（2026-10-07 用户定 · 批次平铺 + 职业下拉 + 分区 + 占位卡）：
--   ⑦ **批次成为一级筛选**（数据 batch 字段）：卡墙上方右侧排一列批次芯片
--      （全部 / 海加尔峰 T1 / Forever 专属），点选切换批次；行池条数 = 批次总数 + 1。
--   ⑧ **职业筛选从 10 枚芯片改为下拉**：原先 10 枚等宽芯片吃满页签行右侧 678，
--      腾不出批次芯片的位置 ⇒ 收成一枚常驻按钮（文本 = 「职业：」+ 当前职业，
--      2026-10-07 用户：光一个职业名看不出按钮是干嘛的）。
--      ★ 展开菜单走 **Hui ShowMenu**（BOSS / 类型下拉同款）
--        —— 首版手搓展开面板在实机「点开是空的」，无法离线复现，整条退役；
--        点外关闭由 ShowMenu 自带 GLOBAL_MOUSE_DOWN 兜底。
--   ⑨ **卡墙按 revealed 分两段**，段前各一条分节标签（18 套已公开 / 9 套未揭示）。
--      revealed = false 的套装渲染**占位卡**：只有徽记（兜底问号）+ 名称 + 副行 +
--      「效果未揭示」+ 部件编号，不渲染效果区（这类套装数据里没有 bonuses）。
--   ⑩ 正文顶由 RU.BODY_Y(96) 下移到 RU.SET_TOP(124)：让出页签行下方的批次行。
-- ★★ 版式六稿（2026-10-07 用户定 · 主从布局）：
--   ⑪ 卡墙 2 列平铺退役（占位卡塞部件编号串后整卡爆宽，用户实机反馈「点开看
--      都不能看」）。改为主从布局：左侧滚动列表（行池按 revealed 分两段，
--      金描边 = 选中态，行 = 图标 + 名称 + 右端件数），右侧固定详情帧
--      （头部 + 效果区 + 「部件编号」+ 部件物品卡 2 列网格，名称走 DG.ItemName）。
--   ⑫ 选中态 = 内存态（不落库）；筛选 / 切批次后选中不在列表时回落第一行显示。
--      列表空（该批次 × 该职业没有套装）时详情区显示「没有匹配的套装」。
-- ★★ 版式七稿（2026-10-08 用户定 · 物品卡对齐五人本）：
--   ⑬ 详情物品卡规格对齐五人本掉落行：44 高 / 图标 32 / 名称 14 品质色
--      （DG.QColor）/ 槽位·类型副行 11（DG.ItemMeta；RaidUI 字号纪律 11/14/16）/
--      FitText 按「字」截断。
--   ⑭ 悬停 = 浮白 + 物品提示框（DG.ShowItemTip）；Shift+点击 = 链接进聊天框
--      （DG.ItemShiftClick）。名字没缓存时 RequestItem 预热，到货由
--      RefreshItemCards → RU.OnItemData 重涂（物品卡名称不再停留「物品 #N」）。
-- ★ 帧数纪律同另两子页：卡片池 / 批次芯片 / 下拉行池 / 滚动区一律 Build 期建好，
--   RenderSets 只改文本、颜色、显隐与坐标，渲染期不新建帧。
-- =============================================================================
RU.SET_PAD      = 14
RU.SET_ICON     = 24
RU.SET_HEAD_Y   = 14
-- 副行并入名称行（同排右侧）后头部只剩一行 ⇒ 正文顶从 60 提到 46
-- （图标顶 14 + 高 24 = 底 38，再留 8 的呼吸）。
RU.SET_BODY_Y   = 46
RU.SET_SUB_GAP  = 12                                           -- 名称右缘 → 副行左缘
RU.SET_LABEL_W  = 34
RU.SET_TEXT_X   = 16 + RU.SET_LABEL_W + 8                      -- 58
RU.SET_BADGE_W, RU.SET_BADGE_H = 46, 20
-- ★ 芯片比照三枚二级页签（高 24 / 字号 14）。
RU.SET_CHIP_H   = RU.TAB_H                                     -- 24，与二级页签同高
RU.SET_CHIP_W   = RU.TAB_W                                     -- 76，单枚宽上限
RU.SET_CHIP_GAP = 6
RU.SET_CHIP_FS  = 14                                           -- 与二级页签同字号
RU.SET_RADIUS   = 6                                            -- 卡片倒圆角半径
-- ★★ 五稿新增（2026-10-07）
-- 批次行：页签行（RU.TAB_Y = 58，高 24 → 底 82）下方留 8 呼吸 ⇒ 顶 90。
RU.SET_BATCH_Y  = 90
-- 正文顶：批次行底（90 + 24 = 114）+ 10 呼吸 ⇒ 124。时间线 / 列表两页仍用 RU.BODY_Y。
RU.SET_TOP      = 124
-- 分节头行高（左列表内每段的标签占位）
RU.SET_SEC_H    = 26
-- 职业下拉：按钮宽 128（容纳最宽的「职业：全部职业」），菜单走 Hui ShowMenu
RU.SET_DD_W     = 128
RU.SET_DD_H     = RU.TAB_H                                     -- 24，与页签同高
RU.SET_LINE_H   = 18                                           -- 14 号字一行高的兜底（真机走 GetStringHeight）
-- ★★ 六稿新增（2026-10-07 主从布局）：左列表 252 + 呼吸 12 ⇒ 右详情 672（RU.W = 936）。
RU.SET_LIST_W   = 252                                          -- 左列表宽（滚动区内容宽）
RU.SET_LIST_GAP = 12                                           -- 列表 → 详情 呼吸
RU.SET_DETAIL_W = RU.W - RU.SET_LIST_W - RU.SET_LIST_GAP       -- 672
RU.SET_ROW_H    = 30                                           -- 左列表行高
RU.SET_ROW_ICON = 20                                           -- 左列表行图标
RU.SET_TEXT_W   = RU.SET_DETAIL_W - RU.SET_TEXT_X - 16         -- 598（详情口径效果文本宽）
-- 效果行池（★★ 七稿 D）：祝福板甲有 2..6 共 5 档效果 ⇒ 池 6（阈值 2..7）兜住，
--   渲染时按 bonuses 实有档位显隐。
RU.SET_BONUS_ROWS = 6
-- 物品卡网格（详情正文）：2 列，池上限 9 > 最大件数 8。
-- ★★ 七稿（2026-10-08 用户：物品卡要和五人本那样显示 + 鼠标提示框）：规格对齐
--   五人本掉落行（DG.LOOT_CARD_H=44 / DG.LOOT_ICON=32 同尺寸）。
RU.SET_PIECE_H    = 44
RU.SET_PIECE_ICON = 32
RU.SET_PIECE_TX   = 6 + RU.SET_PIECE_ICON + 5                 -- 43：文本列左缘（内边距+图标+间距）
RU.SET_PIECE_NAME_R = 7                                       -- 文本右缘 → 卡右缘
RU.SET_PIECE_COLS = 2
RU.SET_PIECE_GAP  = 8
RU.SET_PIECE_W    = floor((RU.SET_DETAIL_W - 32 - RU.SET_PIECE_GAP) / RU.SET_PIECE_COLS)  -- 316
RU.SET_PIECE_MAX  = 9

local SET_ICON_DIR = "Interface\\AddOns\\DungeonsForever\\Media\\icon\\CLASS\\ClassIcon_"
local SET_ICON_FILE = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
local SET_CHIPS = { "ALL", "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
                    "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
-- 角色标签在**加载期**就解析成当前语言文案（Locales 先于 Core 加载），
-- 用字面 L["…"] 才能被本地化生成器扫到（表驱动的 L[变量] 扫不到）。
local SET_ROLE_LABEL = { dps = L["输出"], tank = L["坦克"], heal = L["治疗"] }
local SET_ROLE_COLOR = { dps = { 0.95, 0.45, 0.40 },
                         tank = { 0.45, 0.65, 1.00 },
                         heal = { 0.45, 0.95, 0.60 } }
-- ★★ 五稿新增（2026-10-07）
-- 批次键序：全部 → 数据表 batches 的顺序（"ALL" 是伪键）。
-- 批次芯片行池条数 = 批次总数 + 1（全部）；这里的 count 上限在 Build 期按数据实况夹住。
local SET_BATCH_ALL = "ALL"
-- Forever 专属批：该批套装 class 为空（无职业限制）⇒「职业筛选」按钮整颗隐藏
local SET_BATCH_EXCL = "exclusive"
-- 未揭示套装的副行文案与部件编号前缀（字面 L 键才能被生成器扫到）
local SET_WAIT_LABEL = L["效果未揭示"]
local SET_IDS_LABEL  = L["部件编号"]
-- 分节标签文案
local SET_SEC_OPEN   = L["效果已公开"]
local SET_SEC_HIDDEN = L["效果未揭示"]

local function Utf8Len(s)
    local n = 0
    for i = 1, #s do
        local b = s:byte(i)
        if b and (b < 0x80 or b >= 0xC0) then n = n + 1 end
    end
    return n
end

-- 文本实测宽：优先真实量（客户端）；插桩环境 GetStringWidth 回假对象时按字符数估算。
-- ⚠️ 不能用 `#s` —— 那是 UTF-8 字节数，中文会被算成 3 倍宽；芯片行总宽虚高后
-- 右对齐的起点会算成负数，整行画到面板外且零报错。
local function TextW(fs, text)
    local w = fs and fs.GetStringWidth and fs:GetStringWidth()
    if type(w) == "number" and w > 0 then return w end
    return Utf8Len(text) * 11
end

local function ClassNameOf(cls)
    local n = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]
    return n or cls
end

local function ClassColorOf(cls)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
    if c then return c.r, c.g, c.b end
    return 0.70, 0.70, 0.70
end

local function MyClass()
    if type(UnitClass) == "function" then
        local _, cls = UnitClass("player")
        if cls and SET_ICON_FILE[cls] then return cls end
    end
    return "ALL"
end

local function SetsData()
    return ns.RaidSetData
end

-- ★★ 五稿（2026-10-07）：批次列表 —— 优先取数据表的 batches 元信息（含 count / revealed），
--   数据表若没写 batches（老数据 / 覆盖层缺项）则从 sets 的 batch 字段现推一份，
--   保证界面在任何数据形态下都不空转。返回 { { key, label, count, revealed }, … }。
local function BatchList(data)
    data = data or SetsData()
    if not data then return {} end
    if data.batches and #data.batches > 0 then return data.batches end
    local order, seen = {}, {}
    for _, rec in ipairs(data.sets or {}) do
        local b = rec.batch or "t1"
        if not seen[b] then
            seen[b] = { key = b, label = b, count = 0, revealed = true }
            order[#order + 1] = seen[b]
        end
        seen[b].count = seen[b].count + 1
    end
    return order
end

local function CurBatch()
    local b = DB().setBatch
    if type(b) ~= "string" then b = SET_BATCH_ALL end
    if b ~= SET_BATCH_ALL then
        local ok = false
        for _, bt in ipairs(BatchList()) do
            if bt.key == b then ok = true break end
        end
        if not ok then b = SET_BATCH_ALL end
    end
    return b
end

local function CurFilter()
    local f = DB().setFilter
    if type(f) ~= "string" then
        f = MyClass()
        DB().setFilter = f
    end
    if f ~= "ALL" and not SET_ICON_FILE[f] then f = "ALL" end
    return f
end

local function FSHeight(fs, fallback)
    local h = fs and fs.GetStringHeight and fs:GetStringHeight()
    if type(h) ~= "number" or h <= 0 then return fallback or 14 end
    return h
end

local function SetsClassCount(data)
    local seen, n = {}, 0
    for _, rec in ipairs((data and data.sets) or {}) do
        if rec.class and not seen[rec.class] then
            seen[rec.class] = true
            n = n + 1
        end
    end
    return n
end

-- ★★ 六稿（2026-10-07 主从布局）：左列表行 —— NewButton 作点击载体（点 = 选中该套），
--   金描边选中态由 RenderSets 统一 SetOutline；行内 = 图标 20 + 名称 14
--   （复用按钮字体串，左对齐锚图标右缘）+ 右端件数 11。
function RU.NewSetRow(parent)
    local bt = NewButton(parent, "", RU.SET_LIST_W, RU.SET_ROW_H, 14)
    MakeOutline(bt, 1, 0.82, 0)
    bt.__huiKeepTextColor = true
    local it = bt:CreateTexture(nil, "ARTWORK")
    it:SetSize(RU.SET_ROW_ICON, RU.SET_ROW_ICON)
    it:SetPoint("LEFT", bt, "LEFT", 6, 0)
    it:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(it) end
    local fs = bt:GetFontString()
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", it, "RIGHT", 6, 0)
    fs:SetJustifyH("LEFT")
    local count = MakeFS(bt, 14, C_GREY, "RIGHT")
    count:SetPoint("RIGHT", bt, "RIGHT", -8, 0)
    bt.iconTex = it
    bt.countFs = count
    bt:SetScript("OnClick", function(self)
        if self.rec then RU.SelectSet(self.rec.name) end
    end)
    return bt
end

-- ★★ 七稿：详情正文网格单元（物品卡）——对齐五人本掉落行（DG.LOOT_* 同款口径）：
--   皮 L3 圆角 4 / 图标 32 / 名称 14 品质色 + 槽位·类型副行 11（DG.ItemMeta）/
--   悬停浮白 + 物品提示框（DG.ShowItemTip：SetItemByID→SetHyperlink→请求装载链，
--   自带 tooltip 重入守卫）/ Shift+点击链接进聊天框（DG.ItemShiftClick）。
function RU.NewPieceCard(parent)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(RU.SET_PIECE_W, RU.SET_PIECE_H)
    local layer = ns.hui and ns.hui.layer
    if ns.hui and ns.hui.BuildRoundedBG and layer then
        ns.hui.BuildRoundedBG(f, 4, layer.L3, "both", true, 1)
    else
        f.edge = f:CreateTexture(nil, "BACKGROUND")
        f.edge:SetAllPoints(f)
        f.edge:SetColorTexture(1, 1, 1, 0.10)
        f.bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        f.bg:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        f.bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        f.bg:SetColorTexture(0x16 / 255, 0x1A / 255, 0x22 / 255, 1)
    end
    local it = f:CreateTexture(nil, "ARTWORK")
    it:SetSize(RU.SET_PIECE_ICON, RU.SET_PIECE_ICON)
    it:SetPoint("LEFT", f, "LEFT", 6, 0)
    it:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(it) end
    f.iconTex = it
    f.name = MakeFS(f, 14, C_TEXT, "LEFT")
    f.name:SetPoint("TOPLEFT", f, "TOPLEFT", RU.SET_PIECE_TX, -4)
    f.name:SetWidth(RU.SET_PIECE_W - RU.SET_PIECE_TX - RU.SET_PIECE_NAME_R)
    f.name:SetWordWrap(false)
    f.meta = MakeFS(f, 14, C_GREY, "LEFT")
    f.meta:SetPoint("TOPLEFT", f, "TOPLEFT", RU.SET_PIECE_TX, -23)
    f.meta:SetWordWrap(false)
    -- 悬停浮白：五人本卡内行同款极淡高亮（OVERLAY 一层白，Build 期建好）
    f.hover = f:CreateTexture(nil, "OVERLAY")
    f.hover:SetAllPoints(f)
    f.hover:SetColorTexture(1, 1, 1, 0.06)
    f.hover:Hide()
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        self.hover:Show()
        if self.__id and Host.DG and Host.DG.ShowItemTip then
            Host.DG.ShowItemTip(self, { self.__id })
        end
    end)
    f:SetScript("OnLeave", function(self)
        self.hover:Hide()
        GameTooltip:Hide()
    end)
    f:SetScript("OnClick", function(self, button)
        if Host.DG and Host.DG.ItemShiftClick then Host.DG.ItemShiftClick(self, button) end
    end)
    return f
end

-- ★★ 六稿：右详情固定帧（不滚动）。皮 L2 圆角（无悬停层——详情不参与 hover）；
--   头部 = 徽记 24 + 名称 16 + 徽章 + 副行；正文 = 效果 4 行（占位态全隐）+
--   「部件编号」分节 + 物品卡 2 列网格（池 9）。建帧期全部建好，渲染期零新建。
function RU.NewSetDetail(parent)
    local d = CreateFrame("Frame", nil, parent)
    local layer = ns.hui and ns.hui.layer
    if ns.hui and ns.hui.BuildRoundedBG and layer then
        ns.hui.BuildRoundedBG(d, RU.SET_RADIUS, layer.L2, "both", true, 1)
    else
        d.edge = d:CreateTexture(nil, "BACKGROUND")
        d.edge:SetAllPoints(d)
        d.edge:SetColorTexture(1, 1, 1, 0.10)
        d.bg = d:CreateTexture(nil, "BACKGROUND", nil, 1)
        d.bg:SetPoint("TOPLEFT", d, "TOPLEFT", 1, -1)
        d.bg:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -1, 1)
        d.bg:SetColorTexture(0x16 / 255, 0x1A / 255, 0x22 / 255, 1)
    end

    -- 职业徽记：蒙版由 RoundIcon 按**贴图**尺寸裁（mask:SetAllPoints(tex)）；帧与图标等大即可
    local ih = CreateFrame("Frame", nil, d)
    ih:SetSize(RU.SET_ICON, RU.SET_ICON)
    ih:SetPoint("TOPLEFT", d, "TOPLEFT", 16, -RU.SET_HEAD_Y)
    local it = ih:CreateTexture(nil, "ARTWORK")
    it:SetAllPoints(ih)
    it:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(it) end
    d.iconTex = it

    d.name = MakeFS(d, 16, C_WHITE, "LEFT")
    d.name:SetPoint("TOPLEFT", d, "TOPLEFT", 48, -(RU.SET_HEAD_Y + 1))
    d.badgeBG = d:CreateTexture(nil, "ARTWORK")
    d.badgeBG:SetSize(RU.SET_BADGE_W, RU.SET_BADGE_H)
    d.badgeBG:SetPoint("TOPRIGHT", d, "TOPRIGHT", -16, -(RU.SET_HEAD_Y + 3))
    d.badge = MakeFS(d, 14, C_TEXT, "CENTER")
    d.badge:SetPoint("CENTER", d.badgeBG, "CENTER", 0, 0)

    -- 副行并入名称行：锚在名称**右缘**（名称是自适应宽，锚点随文本实时重算）。
    d.sub = MakeFS(d, 14, C_GREY, "LEFT")
    d.sub:SetPoint("LEFT", d.name, "RIGHT", RU.SET_SUB_GAP, 0)

    d.labels, d.texts = {}, {}
    for i = 1, RU.SET_BONUS_ROWS do
        d.labels[i] = MakeFS(d, 14, C_GOLD, "LEFT")
        d.texts[i] = MakeFS(d, 14, C_TEXT, "LEFT")
        d.texts[i]:SetWidth(RU.SET_TEXT_W)
        d.texts[i]:SetWordWrap(true)
    end

    d.idsLabel = MakeFS(d, 14, C_GOLD, "LEFT")
    d.idsLabel:Hide()
    d.pieces = {}
    for i = 1, RU.SET_PIECE_MAX do
        d.pieces[i] = RU.NewPieceCard(d)
        d.pieces[i]:Hide()
    end
    return d
end

-- ★★ 七稿 C（2026-10-08 用户）：行 / 详情头图标 = 职业徽记优先；无职业（专属批）
--   不再贴兜底问号，改用**套装第一件物品**的图标（DG.ItemIcon，内部兜底 FALLBACK_ICON，
--   客户端没缓存时先是问号、数据到货后 RefreshItemCards → PaintSetRow 会补上）。
local function SetIconForRec(tex, rec)
    local file = SET_ICON_FILE[rec.class]
    if file then
        tex:SetTexture(SET_ICON_DIR .. file)
    else
        local ids = rec.ids or {}
        local t = Host.FALLBACK_ICON
        if ids[1] and Host.DG and Host.DG.ItemIcon then t = Host.DG.ItemIcon(ids[1]) end
        tex:SetTexture(t)
    end
    tex:SetAlpha(1)
end

-- ★★ 六稿：左列表行两态 —— 已公开 = 职业徽记 + 正文色名称；未揭示（无职业）=
--   第一件物品图标 + 暗色名称（七稿 C 起不再半透问号）。件数一律显示 ids 实长
--   （27 套全量入库，都有部件）。选中描边不在本函数管（RenderSets 统一 SetOutline）。
function RU.PaintSetRow(row, rec)
    local revealed = (rec.revealed ~= false)
    SetIconForRec(row.iconTex, rec)
    local fs = row:GetFontString()
    fs:SetText(rec.name or "")
    fs:SetTextColor(Unpack(revealed and C_TEXT or C_DIM))
    row.countFs:SetText(format("%d", #(rec.ids or {})))
end

-- ★★ 七稿：物品卡单格渲染 —— 名称走 DG.ItemName 实名（品质色 QColor / FitText 按
--   「字」截断补「…」；客户端给不出回退「物品 #N」灰字并 RequestItem 预热），
--   副行走 DG.ItemMeta（槽位 · 类型），图标走 DG.ItemIcon（内部兜底 FALLBACK_ICON）。
function RU.PaintPieceCard(f, id)
    f.__id = id                                           -- 悬停提示框 / Shift 链接都要用
    local nm, ok
    if Host.DG and Host.DG.ItemName then nm, ok = Host.DG.ItemName(id) end
    local txt = (ok and nm) or format(L["物品 #%d"], id or 0)
    if Host.DG and Host.DG.FitText then
        txt = Host.DG.FitText(txt, 14,
            RU.SET_PIECE_W - RU.SET_PIECE_TX - RU.SET_PIECE_NAME_R)
    end
    f.name:SetText(txt)
    f.meta:SetText("")
    if ok then
        if Host.DG.QColor and Host.DG.QualOf then
            local qr, qg, qb = Host.DG.QColor(Host.DG.QualOf(id))
            if qr then f.name:SetTextColor(qr, qg, qb) end
        end
        if Host.DG and Host.DG.ItemMeta then
            local meta = Host.DG.ItemMeta(id)
            if type(meta) == "string" and meta ~= "" then f.meta:SetText(meta) end
        end
    else
        f.name:SetTextColor(Unpack(C_GREY))
        -- 客户端还没缓存 ⇒ 请求装载；到货后（RefreshItemCards → RU.OnItemData）重涂
        if Host.DG and Host.DG.RequestItem then Host.DG.RequestItem(id) end
    end
    local tex = Host.FALLBACK_ICON
    if Host.DG and Host.DG.ItemIcon then tex = Host.DG.ItemIcon(id) end
    f.iconTex:SetTexture(tex)
end

-- ★★ 七稿：物品数据到货回调（DungeonUI.RefreshItemCards 末尾钩进来）——
--   只重涂当前详情里挂这件物品的卡（实名 / 品质色 / 副行一并补齐）。
function RU.OnItemData(itemID)
    local d = RU.setDetail
    if not (d and d:IsShown()) then return end
    for i = 1, RU.SET_PIECE_MAX do
        local f = d.pieces[i]
        if f and f.__id == itemID and f:IsShown() then RU.PaintPieceCard(f, itemID) end
    end
end

-- ★★ 六稿：右详情两态渲染 —— revealed（头部 + 效果 4 行 + 部件网格）与
--   未揭示（头部占位徽章 / 副行 + 效果 4 行全隐 + 部件网格），两态共用同一批
--   帧，靠 Show/Hide 切换，渲染期不新建帧。
function RU.PaintSetDetail(rec)
    local d = RU.setDetail
    if not d then return end
    if not rec then d:Hide() return end
    d:Show()
    local revealed = (rec.revealed ~= false)
    d.__rec = rec
    d.__placeholder = not revealed                         -- 供离线断言辨识两态

    -- 徽记：已揭示走职业徽记；无职业（专属批）走第一件物品图标（七稿 C 同列表行）
    SetIconForRec(d.iconTex, rec)

    d.name:SetText(rec.name or "")

    -- 角色徽章：有职业的已揭示套装走角色徽章（坦克 / 治疗 / 输出）；
    --   无职业（专属批，★★ 七稿 D：含已揭示的 5 套）一律「专属」灰金小标。
    local hasClass = (rec.class ~= nil and rec.class ~= "")
    if revealed and hasClass then
        local role = rec.role or "dps"
        local rc = SET_ROLE_COLOR[role] or SET_ROLE_COLOR.dps
        d.badgeBG:SetColorTexture(rc[1], rc[2], rc[3], 0.18)
        d.badge:SetText(SET_ROLE_LABEL[role] or L["输出"])
        d.badge:SetTextColor(rc[1], rc[2], rc[3])
    else
        d.badgeBG:SetColorTexture(0.55, 0.52, 0.42, 0.20)
        d.badge:SetText(L["专属"])
        d.badge:SetTextColor(0.82, 0.76, 0.55)
    end

    -- 副行：有职业已揭示 = 职业 · 专精 · 护甲 · N 件套；无职业已揭示 = N 件套（件数
    --   按 ids 实长——专属套装件数不等）；未揭示 = 效果未揭示 · 部件编号 N
    if revealed and hasClass then
        d.sub:SetText(format("%s · %s · %s · %d%s",
            ClassNameOf(rec.class), rec.spec or "", rec.armor or "",
            (SetsData() and SetsData().pieces) or 6, L[" 件套"]))
        d.sub:SetTextColor(Host.C_GREY[1], Host.C_GREY[2], Host.C_GREY[3])
    elseif revealed then
        d.sub:SetText(format("%d%s", #(rec.ids or {}), L[" 件套"]))
        d.sub:SetTextColor(Host.C_GREY[1], Host.C_GREY[2], Host.C_GREY[3])
    else
        d.sub:SetText(format("%s · %s %d",
            SET_WAIT_LABEL, SET_IDS_LABEL, #(rec.ids or {})))
        d.sub:SetTextColor(Host.C_DIM[1], Host.C_DIM[2], Host.C_DIM[3])
    end

    local y = RU.SET_BODY_Y
    if not revealed then
        -- 占位详情：效果区全部行隐（这类套装数据里没有 bonuses）
        for i = 1, RU.SET_BONUS_ROWS do
            d.labels[i]:Hide()
            d.texts[i]:Hide()
        end
    else
        for i = 1, RU.SET_BONUS_ROWS do
            local n = i + 1                                   -- 2 / 3 / … 件档
            local txt = rec.bonuses and rec.bonuses[n]
            local lb, fs = d.labels[i], d.texts[i]
            if txt then
                lb:SetText(format("%d%s", n, L["件"]))
                lb:SetTextColor(Host.C_GOLD[1], Host.C_GOLD[2], Host.C_GOLD[3])
                lb:SetPoint("TOPLEFT", d, "TOPLEFT", 16, -y)
                lb:Show()
                fs:SetText(txt)
                fs:SetTextColor(0.86, 0.87, 0.88)
                fs:SetPoint("TOPLEFT", d, "TOPLEFT", RU.SET_TEXT_X, -y)
                fs:Show()
                y = y + FSHeight(fs, RU.SET_LINE_H) + 5
            else
                lb:Hide()
                fs:Hide()
            end
            y = y + 4
        end
    end

    -- 「部件编号」分节 + 物品卡网格（2 列；池 9 > 最大件数 8，不会溢池）
    d.idsLabel:SetPoint("TOPLEFT", d, "TOPLEFT", 16, -y)
    d.idsLabel:Show()
    y = y + FSHeight(d.idsLabel, RU.SET_LINE_H) + 6
    local ids = rec.ids or {}
    local col, rowY = 0, y
    for i = 1, RU.SET_PIECE_MAX do
        local f = d.pieces[i]
        local id = ids[i]
        if id and id > 0 then
            RU.PaintPieceCard(f, id)
            f:SetPoint("TOPLEFT", d, "TOPLEFT",
                16 + col * (RU.SET_PIECE_W + RU.SET_PIECE_GAP), -rowY)
            f:Show()
            col = col + 1
            if col >= RU.SET_PIECE_COLS then
                col = 0
                rowY = rowY + RU.SET_PIECE_H + RU.SET_PIECE_GAP
            end
        else
            f:Hide()
        end
    end
end

-- ★★ 六稿：选中一套（左列表点行 / L 键路径共用）。内存态不落库——切页签回来自由。
function RU.SelectSet(name)
    if RU.setSelName == name then return end
    RU.setSelName = name
    RU.RenderSets()
    if ns.PlaySound then ns.PlaySound(1) end
end

-- ★★ 五稿（2026-10-07）：职业筛选改下拉 —— 常驻按钮显示当前职业，
--   点开是 10 行行池（全部职业 + 9 职业）；再点已选中的职业退回「全部」。
function RU.SetFilter(key)
    if key == CurFilter() and key ~= "ALL" then key = "ALL" end
    DB().setFilter = key
    RU.RenderSets()
    if ns.PlaySound then ns.PlaySound(1) end
end

-- 批次筛选：点已选中的批次退回「全部」
function RU.SetBatch(key)
    if type(key) ~= "string" then key = SET_BATCH_ALL end
    if key ~= SET_BATCH_ALL then
        -- 非法批次不落库（离线断言 / 实机手改 DB 都可能塞进脏值）
        local ok = false
        for _, bt in ipairs(BatchList()) do
            if bt.key == key then ok = true break end
        end
        if not ok then key = SET_BATCH_ALL end
    end
    if key == CurBatch() and key ~= SET_BATCH_ALL then key = SET_BATCH_ALL end
    DB().setBatch = key
    -- ★★ 七稿 B（2026-10-08 用户）：进专属批「职业筛选」整颗隐藏 ⇒ 隐藏期间筛不动，
    --   残留的职业筛选会把专属套装全藏掉（它们的 class 为空，恒不过职业筛选）
    --   ⇒ 一律复位「全部」；切回其他批用户可再选。
    if key == SET_BATCH_EXCL then DB().setFilter = "ALL" end
    RU.RenderSets()
    if ns.PlaySound then ns.PlaySound(1) end
end

-- 批次芯片（全部 + N 个批次）：选中态靠金色描边，未选中降不透明度
function RU.PaintBatchChips()
    local cur = CurBatch()
    for i = 1, #(RU.batchChips or {}) do
        local item = RU.batchChips[i]
        if item and item.bt then
            local sel = (item.key == cur)
            SetOutline(item.bt, sel, 1, 0.82, 0)
            local fs = item.bt:GetFontString()
            fs:SetTextColor(Unpack(sel and C_GOLD or C_TEXT))
            fs:SetAlpha(sel and 1 or 0.82)
        end
    end
end

-- 职业下拉按钮的文字 = 「职业：」前缀 + 当前筛选（全部职业 / 职业名 + 职业色）。
-- 前缀口径随副本页「BOSS：」「类型：」两枚下拉（2026-10-07 用户：光一个职业名
-- 看不出按钮是干嘛的）。选中态 = 职业色字 + 金描边（同 BOSS 下拉）。
function RU.PaintDropButton()
    if not RU.ddBtn then return end
    -- ★★ 七稿 B（2026-10-08 用户）：Forever 专属批无职业限制 ⇒ 「职业筛选」直接隐藏
    RU.ddBtn:SetShown(CurBatch() ~= SET_BATCH_EXCL)
    local cur = CurFilter()
    local fs = RU.ddBtn:GetFontString()
    if cur == "ALL" then
        fs:SetText(L["职业："] .. L["全部职业"])
        fs:SetTextColor(Unpack(C_GREY))
    else
        fs:SetText(L["职业："] .. ClassNameOf(cur))
        fs:SetTextColor(ClassColorOf(cur))
    end
    MakeOutline(RU.ddBtn, 1, 0.82, 0)
    SetOutline(RU.ddBtn, cur ~= "ALL", 1, 0.82, 0)
end

function RU.OpenClassMenu(owner)
    local batch = CurBatch()
    local counts = {}
    for _, rec in ipairs((SetsData() and SetsData().sets) or {}) do
        if batch == SET_BATCH_ALL or rec.batch == batch then
            counts[rec.class or ""] = (counts[rec.class or ""] or 0) + 1
        end
    end
    local items = {}
    for _, key in ipairs(SET_CHIPS) do
        local n = (key == "ALL") and 0 or (counts[key] or 0)
        local name = (key == "ALL") and L["全部职业"] or ClassNameOf(key)
        local color
        if key ~= "ALL" then
            local rc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[key]
            if rc then
                color = format("|cFF%02X%02X%02X",
                    floor(rc.r * 255 + 0.5), floor(rc.g * 255 + 0.5), floor(rc.b * 255 + 0.5))
            end
        end
        items[#items + 1] = {
            text = (key ~= "ALL" and n > 0) and format("%s · %d", name, n) or name,
            color = color,
            func = function() RU.SetFilter(key) end,
        }
    end
    ns.hui.ShowMenu(items, { owner = owner })
end

-- 渲染入口：批次芯片 + 职业下拉按钮态
function RU.PaintChips()
    RU.PaintBatchChips()
    RU.PaintDropButton()
end

-- ★★ 六稿：渲染入口（主从布局）。左列表 = 分段铺行（已公开 / 未揭示，段前分节头），
--   右详情 = PaintSetDetail（选中套）；选中态内存恢复、回落第一行。
function RU.RenderSets()
    if not RU.setRows then return end
    RU.PaintChips()
    local data = SetsData()
    local filter = CurFilter()
    local batch = CurBatch()
    local shown = {}
    for _, rec in ipairs((data and data.sets) or {}) do
        local okB = (batch == SET_BATCH_ALL) or (rec.batch == batch)
        local okC = (filter == "ALL") or (rec.class == filter)
        if okB and okC then shown[#shown + 1] = rec end
    end

    -- 选中恢复：内存选中仍在 shown 用它；不在回落第一行（不写回——切回「全部」
    -- 时用户原选中还在）。
    local sel
    for _, rec in ipairs(shown) do
        if rec.name == RU.setSelName then sel = rec break end
    end
    if not sel then
        -- ★★ 七稿 D：回落「渲染序首行」= 已揭示段在前（专属批里即首套已揭示；
        --   曾经回落 shown[1]，专属批混合揭示态后它会指到第 6 行的未揭示套）
        for _, rec in ipairs(shown) do
            if rec.revealed ~= false then sel = rec break end
        end
        sel = sel or shown[1]
    end

    -- 左列表：按 revealed 分两段铺行，段前各一条分节头；只显示「有内容」的段。
    local segs = { { revealed = true, label = SET_SEC_OPEN },
                   { revealed = false, label = SET_SEC_HIDDEN } }

    local idx, y = 0, 0
    local secI = 0
    for _, seg in ipairs(segs) do
        local list = {}
        for _, rec in ipairs(shown) do
            local rv = (rec.revealed ~= false)
            if rv == seg.revealed then list[#list + 1] = rec end
        end
        if #list > 0 then
            secI = secI + 1
            local lb = RU.secLabels and RU.secLabels[secI]
            if lb then
                lb:SetText(format("%s · %d", seg.label, #list))
                lb:SetTextColor(Unpack(seg.revealed and C_GOLD or C_TEXT))
                lb:SetPoint("TOPLEFT", RU.setChild, "TOPLEFT", 2, -y)
                lb:Show()
            end
            y = y + RU.SET_SEC_H
            for _, rec in ipairs(list) do
                idx = idx + 1
                local row = RU.setRows[idx]
                if row then
                    RU.PaintSetRow(row, rec)
                    row.rec = rec
                    row:SetWidth(RU.SET_LIST_W)
                    row:SetPoint("TOPLEFT", RU.setChild, "TOPLEFT", 0, -y)
                    SetOutline(row, sel ~= nil and rec == sel, 1, 0.82, 0)
                    row:Show()
                end
                y = y + RU.SET_ROW_H + 2
            end
        end
    end
    for j = secI + 1, #(RU.secLabels or {}) do RU.secLabels[j]:Hide() end
    for j = idx + 1, #RU.setRows do RU.setRows[j]:Hide() end
    RU.setChild:SetHeight(math.max(10, y))

    -- 空态（该批次 × 该职业没有套装）：详情区显示「没有匹配的套装」
    if RU.setEmpty then
        if #shown == 0 then RU.setEmpty:Show() else RU.setEmpty:Hide() end
    end

    RU.PaintSetDetail(sel)
end

function RU.BuildSets(page)
    local sets = CreateFrame("Frame", nil, page)
    sets:SetAllPoints(page)
    RU.sets = sets

    -- ★★ 六稿：左列表滚动区 —— 顶仍 RU.SET_TOP（让出批次行），宽收到 SET_LIST_W，
    --   右侧让位给固定详情帧。左列表自身可滚（27 行 + 分节头超出视口高）。
    local scroll = CreateFrame("ScrollFrame", nil, sets)
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", RU.X, -RU.SET_TOP)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT",
        -(RU.X + RU.SET_DETAIL_W + RU.SET_LIST_GAP), RU.X)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        if Host.DG and Host.DG.WheelScroll then
            Host.DG.WheelScroll(RU.setScroll, RU.setChild, delta)
        end
    end)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(RU.SET_LIST_W, 10)
    scroll:SetScrollChild(child)
    RU.setScroll, RU.setChild = scroll, child

    local data = SetsData()
    local pool = #((data and data.sets) or {})
    if pool < 1 then pool = 1 end
    -- 左列表行池：条数 = 套装总数（筛选只影响显隐与坐标，不重建）
    RU.setRows = {}
    for i = 1, pool do
        local row = RU.NewSetRow(child)
        row:Hide()
        RU.setRows[i] = row
    end
    -- 分节头池：最多 2 段（已公开 / 未揭示）
    RU.secLabels = {}
    for i = 1, 2 do
        local lb = MakeFS(child, 14, C_GOLD, "LEFT")
        lb:Hide()
        RU.secLabels[i] = lb
    end

    -- ★★ 六稿：右详情固定帧（不滚动），纵向锚满滚动区；空态提示挂在详情位。
    local d = RU.NewSetDetail(sets)
    d:SetPoint("TOPLEFT", page, "TOPLEFT", RU.X + RU.SET_LIST_W + RU.SET_LIST_GAP, -RU.SET_TOP)
    d:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -RU.X, RU.X)
    RU.setDetail = d
    RU.setEmpty = MakeFS(sets, 14, C_GREY, "LEFT")
    RU.setEmpty:SetPoint("TOPLEFT", sets, "TOPLEFT",
        RU.X + RU.SET_LIST_W + RU.SET_LIST_GAP + 16, -(RU.SET_TOP + 40))
    RU.setEmpty:SetText(L["没有匹配的套装"])
    RU.setEmpty:Hide()

    -- ★★ 五稿：批次芯片（全部 + N 个批次），排在页签行下方的 RU.SET_BATCH_Y。
    --   行池条数 = 批次总数 + 1；宽度按可用宽等分（上限页签宽 76），起排自左。
    local batches = BatchList(data)
    local nb = #batches + 1                                   -- 含「全部」
    RU.batchChips = {}
    local texts = {}
    for i = 1, nb do
        local key = (i == 1) and SET_BATCH_ALL or batches[i - 1].key
        local label = (key == SET_BATCH_ALL) and L["全部"] or (L[batches[i - 1].label] or batches[i - 1].label)
        local bt = NewButton(sets, label, RU.SET_CHIP_W, RU.SET_CHIP_H, RU.SET_CHIP_FS)
        MakeOutline(bt, 1, 0.82, 0)
        bt.__huiKeepTextColor = true
        bt:SetScript("OnClick", function() RU.SetBatch(key) end)
        texts[i] = TextW(bt:GetFontString(), label)
        RU.batchChips[i] = { key = key, bt = bt }
    end

    -- ★ 批次行可用宽：左起 RU.X + 2，右到职业下拉左缘（下拉右对齐页面右端）
    local ddRight = RU.X + RU.W - 2
    local ddX = ddRight - RU.SET_DD_W
    local left = RU.X + 2
    local room = ddX - 8 - left
    local gap = RU.SET_CHIP_GAP
    local widest = 0
    for i = 1, nb do
        if texts[i] > widest then widest = texts[i] end
    end
    local w = floor((room - gap * (nb - 1)) / nb)
    if w > RU.SET_CHIP_W then w = RU.SET_CHIP_W end
    if w < widest + 10 then w = widest + 10 end               -- 不截字优先
    local x = left
    for i = 1, nb do
        local item = RU.batchChips[i]
        item.w = w
        item.bt:SetWidth(w)
        item.bt:SetPoint("TOPLEFT", page, "TOPLEFT", x, -RU.SET_BATCH_Y)
        x = x + w + gap
    end

    -- ★★ 五稿：职业下拉 —— 常驻按钮（右对齐批次行右端），展开走 Hui ShowMenu
    --   （OpenClassMenu；手搓展开面板实机「点开是空的」已整条退役）。按钮文本由
    --   PaintDropButton 上「职业：」前缀，Build 期先垫一份防竞态空壳。
    local dd = NewButton(sets, L["职业："] .. L["全部职业"], RU.SET_DD_W, RU.SET_DD_H, RU.SET_CHIP_FS)
    MakeOutline(dd, 1, 0.82, 0)
    dd.__huiKeepTextColor = true
    dd:SetPoint("TOPRIGHT", page, "TOPRIGHT", -(RU.X + 2), -RU.SET_BATCH_Y)
    dd:SetScript("OnClick", function() RU.OpenClassMenu(dd) end)
    RU.ddBtn = dd
end

function RU.CullCards()
    local sc = RU.listScroll
    if not (sc and RU.listChild) then return end
    local top = 0
    if sc.GetVerticalScroll then top = sc:GetVerticalScroll() end
    if type(top) ~= "number" then top = 0 end
    local vh = 0
    if sc.GetHeight then vh = sc:GetHeight() end
    if type(vh) ~= "number" then vh = 0 end
    if vh <= 0 then return end
    local bot = top + vh
    for _, e in ipairs(RU.cullables or {}) do
        local ok = e.yTop >= top and e.yBot <= bot
        if e.card then
            e.f:SetShown(ok and e.card.__shown)
        else
            e.f:SetShown(ok)
        end
    end
end

local function CullAdd(f, yTop, yBot, card)
    RU.cullables[#RU.cullables + 1] = { f = f, yTop = yTop, yBot = yBot, card = card }
end

function RU.DungeonRec(name)
    local d = name and RU.DETAILS[name]
    if not d then return nil end
    return {
        id = d.id,
        name = name,
        nameEn = d.nameEn,
        levelMin = d.levelMin,
        levelMax = d.levelMax or d.levelMin,
        zone = d.zone,
        bossCount = d.bosses and #d.bosses or nil,
        raid = true,
    }
end

function RU.OpenDetail(name)
    local rec = RU.DungeonRec(name)
    local MJ = ns.DungeonUI
    if not (rec and MJ and MJ.SwitchSub and MJ.ShowDungeonDetail) then return end
    MJ:SwitchSub("Dungeons")
    if MJ.SetDungeonTab then MJ:SetDungeonTab("loot") end
    MJ:SetDungeonView("list")
    MJ:ShowDungeonDetail(rec)
    if MJ.SetSubCapsule then MJ:SetSubCapsule("Raids") end
    if ns.PlaySound then ns.PlaySound(1) end
end

function RU.RenderList()
    local ci = 0
    for gi, g in ipairs(RU.groups) do
        local lb = RU.wallLabels[(gi - 1) * 2 + 1]
        local nt = RU.wallLabels[(gi - 1) * 2 + 2]
        lb:SetText(g.title)
        nt:SetText(g.note)
        for i, rec in ipairs(g.list) do
            ci = ci + 1
            RU.PaintCard(RU.cards[ci], rec, g.edge, g.ea)
            RU.cards[ci].__shown = true
        end
    end
    for j = ci + 1, #RU.cards do
        RU.cards[j].__shown = false
        RU.cards[j]:Hide()
    end
    RU.CullCards()
end

function RU.Render()
    if not RU.built then return end
    RU.RenderList()
end

function RU.Build(page)
    if RU.built then return end
    RU.page = page
    RU.tiers = { BuildTiers() }
    RU.cards, RU.wallLabels, RU.groups, RU.cullables = {}, {}, {}, {}

    local layer = ns.hui and ns.hui.layer
    local card = CreateFrame("Frame", nil, page)
    card:SetPoint("TOPLEFT", page, "TOPLEFT", RU.X, -RU.CARD_TOP)
    card:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -RU.X, RU.CARD_BOTTOM)
    if ns.hui and ns.hui.BuildRoundedBG and layer then
        ns.hui.BuildRoundedBG(card, 6, layer.L1, "both", true, 1)
    end
    local baseLv = page:GetFrameLevel() or 0
    card:SetFrameLevel(baseLv + 1)
    RU.listCard = card

    local scroll = CreateFrame("ScrollFrame", nil, page)
    if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end
    scroll:SetFrameLevel(baseLv + 2)
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", RU.X + RU.GRID_PAD, -RU.LIST_Y)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -(RU.X + RU.GRID_PAD), RU.CARD_BOTTOM)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local ch = RU.listChild
        if not ch then return end
        local maxScroll = math.max(0, ch:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 48)))
        RU.CullCards()
    end)
    scroll:HookScript("OnShow", function() RU.CullCards() end)
    RU.listScroll = scroll

    if ns.hui and ns.hui.layer and ns.hui.layer.L0 then
        local L0 = ns.hui.layer.L0
        local mask = CreateFrame("Frame", nil, page)
        mask:SetFrameLevel(baseLv + 3)
        mask:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -1)
        mask:SetPoint("TOPRIGHT", card, "BOTTOMRIGHT", 0, -1)
        mask:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
        mask:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
        local tex = mask:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        tex:SetTexture("Interface\\Buttons\\WHITE8x8")
        tex:SetVertexColor(L0[1], L0[2], L0[3], L0[4] or 1)
        mask:Hide()
        RU.listFades = { mask }
    end

    local child = CreateFrame("Frame", nil, scroll)
    RU.listChild = child
    child:SetSize(RU.W - 2 * RU.GRID_PAD, 10)
    scroll:SetScrollChild(child)

    for i = 1, 4 do
        if i % 2 == 1 then
            RU.wallLabels[i] = MakeFS(child, 14, C_GOLD, "LEFT")
        else
            RU.wallLabels[i] = MakeFS(child, 14, C_GREY, "RIGHT")
        end
    end
    for _ = 1, #RU.DATA.raids do
        RU.cards[#RU.cards + 1] = RU.NewCard(child)
    end

    local y = RU.GRID_PAD
    local groups = {
        { list = RU.tiers[1],
          title = L["首批开启"], note = RU.FirstOpenText() .. " · " .. L["同日开启"],
          edge = C_GOLD, ea = 0.70 },
        { list = RU.tiers[2],
          title = L["后续预告"], note = L["官方只给了窗口，名称与地点均未公布"],
          edge = { 0.60, 0.63, 0.68 }, ea = 0.30 },
    }
    local ci = 0
    for gi, g in ipairs(groups) do
        local lb = RU.wallLabels[(gi - 1) * 2 + 1]
        local nt = RU.wallLabels[(gi - 1) * 2 + 2]
        lb:SetPoint("TOPLEFT", child, "TOPLEFT", RU.GRID_X, -y)
        nt:SetPoint("TOPRIGHT", child, "TOPRIGHT", -RU.GRID_X, -y)
        CullAdd(lb, y, y + RU.LS_LABEL_H)
        CullAdd(nt, y, y + RU.LS_LABEL_H)
        y = y + RU.LS_LABEL_H
        local pos = RU.LayoutCards(g.list, RU.LS_COL_W, RU.LS_COL_H, y)
        for i, rec in ipairs(g.list) do
            ci = ci + 1
            local c = RU.cards[ci]
            c:SetSize(RU.LS_COL_W, RU.LS_COL_H)
            c:SetPoint("TOPLEFT", child, "TOPLEFT", pos[i].x, pos[i].y)
            CullAdd(c, -pos[i].y, -pos[i].y + RU.LS_COL_H, c)
        end
        g.pos = pos
        y = pos.bottom + RU.LS_LABEL_H
        RU.groups[gi] = g
    end

    local rulesTop = y + 4
    local ruleRule = child:CreateTexture(nil, "ARTWORK")
    if layer and layer.DIV then
        ruleRule:SetColorTexture(layer.DIV[1], layer.DIV[2], layer.DIV[3], 1)
    else
        ruleRule:SetColorTexture(1, 1, 1, 0.10)
    end
    ruleRule:SetPoint("TOPLEFT", child, "TOPLEFT", RU.GRID_X, -rulesTop)
    ruleRule:SetSize(RU.W - 2 * RU.GRID_PAD, 1)
    CullAdd(ruleRule, rulesTop, rulesTop + 1)
    local rtitle = MakeFS(child, 16, C_WHITE, "LEFT")
    rtitle:SetPoint("TOPLEFT", child, "TOPLEFT", RU.GRID_X, -(rulesTop + 14))
    rtitle:SetText(L["团本规则"])
    CullAdd(rtitle, rulesTop + 14, rulesTop + 34)
    local ruleRowH, ruleCol2, ruleDescX = 26, 478, 96
    local gdkpDesc
    for i, rule in ipairs(RU.DATA.rules) do
        local rx = RU.GRID_X + ((i - 1) % 2) * ruleCol2
        local ry = rulesTop + 32 + floor((i - 1) / 2) * ruleRowH
        local rn = MakeFS(child, 14, C_TEXT, "LEFT")
        rn:SetPoint("TOPLEFT", child, "TOPLEFT", rx, -ry)
        rn:SetText(L[rule[1]])
        local rd = MakeFS(child, 14, C_DIM, "LEFT")
        rd:SetPoint("TOPLEFT", child, "TOPLEFT", rx + ruleDescX, -ry)
        rd:SetText(L[rule[2]])
        CullAdd(rn, ry, ry + ruleRowH)
        CullAdd(rd, ry, ry + ruleRowH)
        if rule[1] == "禁止 GDKP" then gdkpDesc = rd end
    end
    if gdkpDesc then
        RU.cnNote = MakeFS(child, 14, C_GREY, "LEFT")
        RU.cnNote:SetPoint("LEFT", gdkpDesc, "RIGHT", 14, 0)
        RU.cnNote:SetText(L["国服待确定"])
    end
    child:SetHeight(rulesTop + 32 + floor((#RU.DATA.rules + 1) / 2) * ruleRowH + 16)

    RU.built = true
    RU.Render()
end
