-- =============================================================================
-- DungeonsForever · 团本页（界面层 · 手写骨架件）
--
-- ★ 本文件**不是生成物**，可以直接改（与 Core/ExploreUI.lua / Core/BisUI.lua 同定位）。
--   团本清单是**本文件内联的静态表**（RU.DATA.raids），没有单独的数据文件 ——
--   与探索页「战斗法师」子页同款做法。
--
-- ★ 团本页分两个二级子页（用户 2026-09-29 定），页签在标题下方、与 5人本页的
--   【掉落】【任务】同层：
--     · 时间线 —— 纵向时间轴，按「同一开放窗口」聚成节点，节点下列当批团本；
--     · 列表   —— 团本卡墙，首批 3 张大卡 + 后续 4 张小卡，下方带「团本规则」两列块。
--   两个子页共用同一份 RU.DATA.raids（按 date 聚成时间轴节点，按 first 聚成卡墙两档），
--   改排期只动那张表，两页一起变。
--
-- ★ 全端可见：本页**不挂** ns.LoadForeverPages 闸（用户 2026-09-29 定），
--   无限服 / 泰坦 / 正式服三端画同一份内容。表是静态排期，不读客户端。
--
-- ★ 倒计时只到「分」（用户 2026-09-29 定）：官方开放时刻本身是按惯例推算的，
--   给到秒是假精度；RU.CountdownText(nowSec, shift) 是纯函数（默认取 RU.NowSec()），
--   Build 里挂 1 秒 OnUpdate 重算，只在文本变化时才 SetText。
--
-- ★★ 时钟一律走 RU.NowSec()，**不许直接写 os 的 time**（2026-09-29 实机事故）：
--   WoW 的 Lua **没有 os 库**（暴雪用全局 time() / date() / difftime() 顶替），
--   所以 `os.time()` 在客户端会抛 `attempt to index a nil value`，
--   把整页 Build 打断（实测：团本页直接开不出来）。
--   ★ 离线 harness 跑的是 lupa 真 Lua：标准库齐全（有 os.time）、反而没有全局 time
--   → 「写了 os.* 的代码」在离线恒绿、实机必崩（harness 盲区，非偶然）。
--   故 harness 现已抹掉 os、补上全局 time()，与客户端同形。
--   RU.PickClock(env) 是纯函数（环境可注入，便于离线断言），解析顺序：
--   time() → GetServerTime() → env.os.time()（仅离线桩用，且 type() 守卫）。
--   一个时钟都拿不到时倒计时返回空串（不显示、也不报错），绝不阻断 Build。
--   RU.DATA.unlockAt = 2026-12-09 13:00 PST 的 epoch（首批三座同日开启）。
--
-- ★★ 国服比外服晚 1 天（用户 2026-09-29 定）：排期基准是**外服口径**
--   （RU.DATA.firstOpen = 2026-12-09），zhCN 客户端（国服）整体后移一天 ——
--   页面显示「2026 年 12 月 10 日」，倒计时锚点同步 +86400。
--   判定收在 RU.DayShift(cn)：显式传 true / false 可覆盖，不传则按
--   GetLocale() == "zhCN" 自动判；改天数只动 RU.CN_SHIFT（台服 zhTW / enUS
--   都按外服口径走）。首批三座的 date 由 RU.FirstOpenText(shift) 算出来，
--   表里不再写死日期；时间线节点标签与卡片日期共用 RecDateText()，两页不会各显示一个日期。
--
-- ★★ 时间轴轴线两端都必须锚页面的 TOPLEFT：尾端若写成
--   `SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", x, -(y))`，BOTTOMLEFT 的 y 是自下缘
--   向上量，负值等于往页面**下方**画 —— 轴线会穿过底部注记、一路戳出窗口
--   （2026-09-29 实机截图实锤）。
--
-- ★ 「国服待确定」注记挂在「团本规则」里 禁止 GDKP 那行的描述右侧（用户 2026-09-29 定）。
--
-- ★ 帧数纪律（与专业页 / 探索页 / BiS 页同款）：页骨架（二级页签 / 时间轴节点 /
--   时间线行池 / 卡片池 / 规则行）一律在 RU.Build() 里**一次建好**；
--   RU.Render() 只改文本、颜色与显隐，渲染期不得新建帧。
--   行池 = 7、卡片池 = 7，与 RU.DATA.raids 的条数对齐；改条数要同步这两个池。
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
RU.TITLE_Y = 19
RU.NOTE_Y = 42
RU.TAB_Y, RU.TAB_W, RU.TAB_H, RU.TAB_STEP = 58, 76, 24, 82
RU.BODY_Y = 96

RU.TL_AXIS = 14
RU.TL_NODE_H = 30
RU.TL_ROW_H = 40
RU.TL_NODE_GAP = 16
RU.TL_TEXT_X = 34
RU.TL_NOTE_Y = 540

RU.LS_LABEL_H = 26
RU.LS_GAP = 10
RU.LS_BIG_W, RU.LS_BIG_H = 304, 108
RU.LS_SMALL_W, RU.LS_SMALL_H = 226, 96
RU.RULES_RULE_Y = 430
RU.RULES_TITLE_Y = 452
RU.RULES_TOP, RU.RULES_ROW_H = 466, 26
RU.RULES_COL2 = 478
RU.RULES_DESC_X = 96

RU.CN_SHIFT = 1

RU.DATA = {
    updated = "2026-09-24",
    unlockAt = 1796850000,
    firstOpen = { y = 2026, m = 12, d = 9 },
    raids = {
        { name = "深穴", size = 10, first = true },
        { name = "海加尔峰", size = 20, zone = "海加尔山", first = true },
        { name = "奥妮克希亚的巢穴", size = 40, zone = "尘泥沼泽", first = true },
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

local function DB()
    local db = ns.DB()
    db.raid = db.raid or {}
    return db.raid
end

local function CurTab()
    local t = DB().tab
    if t == "list" or t == "sets" then return t end
    return "timeline"
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

local function UpdateCD()
    if not RU.cd then return end
    local txt = RU.CountdownText()
    if RU.cdTxt ~= txt then
        RU.cdTxt = txt
        RU.cd:SetText(txt)
    end
end

local function BuildNodes()
    local out = {}
    for _, rec in ipairs(RU.DATA.raids) do
        local label = RecDateText(rec)
        local last = out[#out]
        if last and last.date == label then
            last.rows[#last.rows + 1] = rec
        else
            out[#out + 1] = { date = label, first = rec.first == true, rows = { rec } }
        end
    end
    return out
end

local function BuildTiers()
    local big, small = {}, {}
    for _, rec in ipairs(RU.DATA.raids) do
        if rec.first then big[#big + 1] = rec else small[#small + 1] = rec end
    end
    return big, small
end

local function SetHover(card, on)
    card.edge:SetColorTexture(1, 1, 1, on and 0.22 or 0.10)
end

function RU.LayoutCards(list, w, h, y0)
    local perRow = math.max(1, floor((RU.W + RU.LS_GAP) / (w + RU.LS_GAP)))
    local out, col, row = {}, 0, 0
    for i = 1, #list do
        if col >= perRow then
            col, row = 0, row + 1
        end
        out[i] = {
            x = RU.X + col * (w + RU.LS_GAP),
            y = -(y0 + row * (h + RU.LS_GAP)),
        }
        col = col + 1
    end
    out.rows = row + 1
    out.bottom = y0 + row * (h + RU.LS_GAP) + h
    return out
end

function RU.NewRow(page)
    local r = CreateFrame("Frame", nil, page)
    r:SetSize(RU.W - RU.TL_TEXT_X, RU.TL_ROW_H)
    r:EnableMouse(true)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints(r)
    r.bg:SetColorTexture(1, 1, 1, 0.05)
    r.bg:Hide()
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetSize(3, RU.TL_ROW_H - 12)
    r.bar:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.name = MakeFS(r, 14, C_TEXT, "LEFT")
    r.name:SetPoint("LEFT", r, "LEFT", 14, 0)
    r.meta = MakeFS(r, 14, C_GREY, "RIGHT")
    r.meta:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r:SetScript("OnEnter", function(self) self.bg:Show() end)
    r:SetScript("OnLeave", function(self) self.bg:Hide() end)
    return r
end

function RU.PaintRow(r, rec)
    local cr, cg, cb = SizeColor(rec.size)
    r.bar:SetColorTexture(cr, cg, cb, rec.first and 0.95 or 0.35)
    r.name:SetText(rec.name or L["未定名团本"])
    r.name:SetTextColor(Unpack(rec.first and C_WHITE or C_DIM))
    local where = rec.zone and L[rec.zone] or L["地点未公布"]
    r.meta:SetText(SizeText(rec.size) .. " · " .. where)
    r.meta:SetTextColor(cr, cg, cb)
    r:SetShown(true)
end

function RU.NewCard(page)
    local c = CreateFrame("Frame", nil, page)
    c:EnableMouse(true)
    c.edge = c:CreateTexture(nil, "BACKGROUND")
    c.edge:SetAllPoints(c)
    c.edge:SetColorTexture(1, 1, 1, 0.10)
    c.bg = c:CreateTexture(nil, "BACKGROUND", nil, 1)
    c.bg:SetPoint("TOPLEFT", c, "TOPLEFT", 1, -1)
    c.bg:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -1, 1)
    c.bg:SetColorTexture(0, 0, 0, 0.35)
    c.bar = c:CreateTexture(nil, "ARTWORK")
    c.bar:SetPoint("TOPLEFT", c, "TOPLEFT", 1, -1)
    c.bar:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 1, 1)
    c.bar:SetWidth(3)
    c.name = MakeFS(c, 16, C_WHITE, "LEFT")
    c.name:SetPoint("TOPLEFT", c, "TOPLEFT", 16, -18)
    c.size = MakeFS(c, 14, C_GREY, "RIGHT")
    c.size:SetPoint("TOPRIGHT", c, "TOPRIGHT", -16, -20)
    c.zone = MakeFS(c, 14, C_DIM, "LEFT")
    c.zone:SetPoint("TOPLEFT", c, "TOPLEFT", 16, -48)
    c.date = MakeFS(c, 14, C_GOLD, "LEFT")
    c.date:SetPoint("TOPLEFT", c, "TOPLEFT", 16, -72)
    c:SetScript("OnEnter", function(self) SetHover(self, true) end)
    c:SetScript("OnLeave", function(self) SetHover(self, false) end)
    return c
end

function RU.PaintCard(c, rec)
    local cr, cg, cb = SizeColor(rec.size)
    c.bar:SetColorTexture(cr, cg, cb, rec.first and 0.95 or 0.35)
    c.name:SetText(rec.name or L["未定名团本"])
    c.name:SetTextColor(Unpack(rec.first and C_WHITE or C_DIM))
    c.size:SetText(SizeText(rec.size))
    c.size:SetTextColor(cr, cg, cb)
    c.zone:SetText(rec.zone and L[rec.zone] or L["地点未公布"])
    c.zone:SetTextColor(Unpack(rec.first and C_DIM or C_GREY))
    c.date:SetText(RecDateText(rec))
    c.date:SetTextColor(Unpack(rec.first and C_GOLD or C_DIM))
    c:SetShown(true)
end

-- =============================================================================
-- 第三子页签：套装（数据 Core/Data/Data_RaidSets.lua 的 ns.RaidSetData）
--
-- ★ 与另两子页共用同一个三行头（标题 / 说明 / 二级页签）：第三枚页签占
--   x = 178…254，职业筛选芯片右对齐到页签行右端，正文顶仍是 RU.BODY_Y。
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
-- ★ 帧数纪律同另两子页：卡片池 / 芯片 / 滚动区一律 Build 期建好，
--   RenderSets 只改文本、颜色、显隐与坐标，渲染期不新建帧。
-- =============================================================================
RU.SET_COLS     = 2
RU.SET_GAP      = 12
RU.SET_CARD_W   = floor((RU.W - RU.SET_GAP) / RU.SET_COLS)     -- 462
RU.SET_PAD      = 14
RU.SET_ICON     = 24
RU.SET_HEAD_Y   = 14
-- 副行并入名称行（同排右侧）后头部只剩一行 ⇒ 正文顶从 60 提到 46
-- （图标顶 14 + 高 24 = 底 38，再留 8 的呼吸）。
RU.SET_BODY_Y   = 46
RU.SET_SUB_GAP  = 12                                           -- 名称右缘 → 副行左缘
RU.SET_LABEL_W  = 34
RU.SET_TEXT_X   = 16 + RU.SET_LABEL_W + 8                      -- 58
RU.SET_TEXT_W   = RU.SET_CARD_W - RU.SET_TEXT_X - 16           -- 388
RU.SET_BADGE_W, RU.SET_BADGE_H = 46, 20
-- ★ 芯片比照三枚二级页签（高 24 / 字号 14）。10 枚 × 页签宽 76 ＝ 760，
--   而页签行右侧只剩 678（right 946 − minX 268）⇒ 塞不下，**按可用宽等分**成
--   等宽芯片（本页实得 62），仍然右对齐、等高同字号。「大小一致」于是落在
--   「等宽 + 高 24 + 字号 14」上，而不是逐枚 76。
RU.SET_CHIP_H   = RU.TAB_H                                     -- 24，与二级页签同高
RU.SET_CHIP_W   = RU.TAB_W                                     -- 76，单枚宽上限
RU.SET_CHIP_GAP = 6
RU.SET_CHIP_FS  = 14                                           -- 与二级页签同字号
RU.SET_RADIUS   = 6                                            -- 卡片倒圆角半径
RU.SET_LINE_H   = 18                                           -- 14 号字一行高的兜底（真机走 GetStringHeight）

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

function RU.NewSetCard(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(RU.SET_CARD_W, 120)
    c:EnableMouse(true)
    -- ★ 底色 / 圆角（用户 2026-09-30 定）：常态 = HUI 色阶 L2（比面板亮一档），
    --   悬停提亮到 L3；四角倒圆角走 ns.hui.BuildRoundedBG 原语（弧盘 + 1px 描边）。
    --   ⚠️ 悬停层用 noRepaint 建（不注册重绘回调 / 不登主窗 alpha），建完立即 Hide。
    local layer = ns.hui and ns.hui.layer
    if ns.hui and ns.hui.BuildRoundedBG and layer then
        ns.hui.BuildRoundedBG(c, RU.SET_RADIUS, layer.L2, "both", true, 1)
        c.hover = ns.hui.BuildRoundedBG(c, RU.SET_RADIUS, layer.L3, "both", false, nil, true) or {}
        for _, t in ipairs(c.hover) do t:Hide() end
    else
        -- 非 HUI 皮兜底：1px 亮边 + 直角深底（与列表页卡片同形）
        c.edge = c:CreateTexture(nil, "BACKGROUND")
        c.edge:SetAllPoints(c)
        c.edge:SetColorTexture(1, 1, 1, 0.10)
        c.bg = c:CreateTexture(nil, "BACKGROUND", nil, 1)
        c.bg:SetPoint("TOPLEFT", c, "TOPLEFT", 1, -1)
        c.bg:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -1, 1)
        c.bg:SetColorTexture(0x36 / 255, 0x36 / 255, 0x36 / 255, 1)
    end

    -- 职业徽记：蒙版由 RoundIcon 按**贴图**尺寸裁（mask:SetAllPoints(tex)）；帧与图标等大即可
    local ih = CreateFrame("Frame", nil, c)
    ih:SetSize(RU.SET_ICON, RU.SET_ICON)
    ih:SetPoint("TOPLEFT", c, "TOPLEFT", 16, -RU.SET_HEAD_Y)
    local it = ih:CreateTexture(nil, "ARTWORK")
    it:SetAllPoints(ih)
    it:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(it) end
    c.iconTex = it

    c.name = MakeFS(c, 14, C_WHITE, "LEFT")
    c.name:SetPoint("TOPLEFT", c, "TOPLEFT", 48, -(RU.SET_HEAD_Y + 1))
    c.badgeBG = c:CreateTexture(nil, "ARTWORK")
    c.badgeBG:SetSize(RU.SET_BADGE_W, RU.SET_BADGE_H)
    c.badgeBG:SetPoint("TOPRIGHT", c, "TOPRIGHT", -16, -(RU.SET_HEAD_Y + 3))
    c.badge = MakeFS(c, 14, C_TEXT, "CENTER")
    c.badge:SetPoint("CENTER", c.badgeBG, "CENTER", 0, 0)

    -- 副行并入名称行：锚在名称**右缘**（名称是自适应宽，锚点随文本实时重算）。
    -- 只给一个 LEFT 锚 ⇒ 副行自适应宽度、垂直居中于名称那一行。
    c.sub = MakeFS(c, 14, C_GREY, "LEFT")
    c.sub:SetPoint("LEFT", c.name, "RIGHT", RU.SET_SUB_GAP, 0)

    c.labels, c.texts = {}, {}
    for i = 1, 4 do
        c.labels[i] = MakeFS(c, 14, C_GOLD, "LEFT")
        c.texts[i] = MakeFS(c, 14, C_TEXT, "LEFT")
        c.texts[i]:SetWidth(RU.SET_TEXT_W)
        c.texts[i]:SetWordWrap(true)
    end

    -- 悬停 = 提亮到 L3（正式皮走 c.hover 圆角层；非 HUI 皮退化成抬高边框亮度）
    c:SetScript("OnEnter", function(self)
        if self.hover and self.hover[1] then
            for _, t in ipairs(self.hover) do t:Show() end
        elseif self.edge then
            SetHover(self, true)
        end
    end)
    c:SetScript("OnLeave", function(self)
        if self.hover and self.hover[1] then
            for _, t in ipairs(self.hover) do t:Hide() end
        elseif self.edge then
            SetHover(self, false)
        end
    end)
    return c
end

-- 返回卡片实高（行内取最大值后再统一 SetHeight）
function RU.PaintSetCard(c, rec)
    local file = SET_ICON_FILE[rec.class]
    c.iconTex:SetTexture(file and (SET_ICON_DIR .. file) or Host.FALLBACK_ICON)

    c.name:SetText(rec.name or "")
    c.name:SetTextColor(1, 1, 1)

    local role = rec.role or "dps"
    local rc = SET_ROLE_COLOR[role] or SET_ROLE_COLOR.dps
    c.badgeBG:SetColorTexture(rc[1], rc[2], rc[3], 0.18)
    c.badge:SetText(SET_ROLE_LABEL[role] or L["输出"])
    c.badge:SetTextColor(rc[1], rc[2], rc[3])

    local data = SetsData()
    c.sub:SetText(format("%s · %s · %s · %d%s",
        ClassNameOf(rec.class), rec.spec or "", rec.armor or "",
        (data and data.pieces) or 6, L[" 件套"]))

    local y = RU.SET_BODY_Y
    for i = 1, 4 do
        local n = i + 1                                   -- 2 / 3 / 4 / 5 件
        local txt = rec.bonuses and rec.bonuses[n]
        local lb, fs = c.labels[i], c.texts[i]
        if txt then
            lb:SetText(format("%d%s", n, L["件"]))
            lb:SetPoint("TOPLEFT", c, "TOPLEFT", 16, -y)
            lb:Show()
            fs:SetText(txt)
            fs:SetTextColor(0.86, 0.87, 0.88)
            fs:SetPoint("TOPLEFT", c, "TOPLEFT", RU.SET_TEXT_X, -y)
            fs:Show()
            y = y + FSHeight(fs, RU.SET_LINE_H) + 5
        else
            lb:Hide()
            fs:Hide()
        end
        y = y + 4
    end

    local h = y + RU.SET_PAD - 4
    c:SetHeight(h)
    return h
end

function RU.SetFilter(key)
    if key == CurFilter() and key ~= "ALL" then key = "ALL" end
    DB().setFilter = key
    RU.RenderSets()
    if ns.PlaySound then ns.PlaySound(1) end
end

function RU.PaintChips()
    local cur = CurFilter()
    for i = 1, #RU.chips do
        local item = RU.chips[i]
        local sel = (item.key == cur)
        -- 选中态只靠金色描边区分（用户 2026-09-30 定：字色一律取职业色）。
        SetOutline(item.bt, sel, 1, 0.82, 0)
        local fs = item.bt:GetFontString()
        local cr, cg, cb
        if item.key == "ALL" then
            cr, cg, cb = Unpack(C_TEXT)          -- 「全部」不是职业，走中性色
        else
            cr, cg, cb = ClassColorOf(item.key)  -- 9 枚职业芯片 = 职业色
        end
        fs:SetTextColor(cr, cg, cb)
        fs:SetAlpha(sel and 1 or 0.82)           -- 未选中稍降不透明度，仍保留描边区分
    end
end

function RU.RenderSets()
    if not RU.setCards then return end
    RU.PaintChips()
    local data = SetsData()
    local filter = CurFilter()
    local shown = {}
    for _, rec in ipairs((data and data.sets) or {}) do
        if filter == "ALL" or rec.class == filter then shown[#shown + 1] = rec end
    end
    local idx, y = 0, 0
    while idx < #shown do
        local row, rowH = {}, 0
        for k = 1, RU.SET_COLS do
            idx = idx + 1
            local rec = shown[idx]
            if rec then
                local c = RU.setCards[idx]
                if c then
                    local h = RU.PaintSetCard(c, rec)
                    row[k] = c
                    if h > rowH then rowH = h end
                end
            end
        end
        for k = 1, RU.SET_COLS do
            local c = row[k]
            if c then
                c:SetWidth(RU.SET_CARD_W)
                c:SetHeight(rowH)
                c:SetPoint("TOPLEFT", RU.setChild, "TOPLEFT",
                    (k - 1) * (RU.SET_CARD_W + RU.SET_GAP), -y)
                c:Show()
            end
        end
        y = y + rowH + RU.SET_GAP
    end
    for j = #shown + 1, #RU.setCards do RU.setCards[j]:Hide() end
    RU.setChild:SetHeight(math.max(10, y))
end

function RU.SyncHeader(tab)
    local data = SetsData()
    local onSets = (tab == "sets") and data ~= nil
    if RU.note then
        if onSets then
            RU.note:SetText(format(L["%s T1 · %d 套 / %d 职业 · 每套 %d 件 %d 项效果"],
                L[data.raid or ""], data.total or 0, SetsClassCount(data),
                data.pieces or 6, 4))
        else
            RU.note:SetText(L["首发即开放 10 / 20 / 40 人团本，2027 年的后续梯队已在排期"])
        end
    end
    if RU.count then
        if onSets then
            RU.count:SetText(format(L["共 %d 套 · 更新于 %s"],
                data.total or 0, data.updated or ""))
        else
            RU.count:SetText(format(L["共 %d 座 · 更新于 %s"],
                #RU.DATA.raids, RU.DATA.updated))
        end
    end
end

function RU.BuildSets(page)
    local sets = CreateFrame("Frame", nil, page)
    sets:SetAllPoints(page)
    RU.sets = sets

    local scroll = CreateFrame("ScrollFrame", nil, sets)
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", RU.X, -RU.BODY_Y)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -RU.X, RU.X)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        if Host.DG and Host.DG.WheelScroll then
            Host.DG.WheelScroll(RU.setScroll, RU.setChild, delta)
        end
    end)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(RU.W, 10)
    scroll:SetScrollChild(child)
    RU.setScroll, RU.setChild = scroll, child

    local data = SetsData()
    local pool = #((data and data.sets) or {})
    if pool < 1 then pool = 1 end
    RU.setCards = {}
    for i = 1, pool do
        local c = RU.NewSetCard(child)
        c:Hide()
        RU.setCards[i] = c
    end

    -- 芯片 10 枚（全部 + 9 职业）：尺度比照三枚二级页签（高 24 / 字号 14），
    -- 与页签同一条 y（RU.TAB_Y），仍右对齐到页签行右端。
    -- ★ 宽度**等宽**：10 枚 × 页签宽 76 ＝ 760 > 可用宽（right 946 − minX 268 ＝ 678）
    --   ⇒ 逐枚 76 会顶出面板；故按可用宽等分（本页实得 62），
    --   再以「最宽那枚的字宽 + 10」兜底防截字，最后把起点夹在页签行右侧。
    RU.chips = {}
    local texts = {}
    for i, key in ipairs(SET_CHIPS) do
        local label = (key == "ALL") and L["全部"] or ClassNameOf(key)
        local bt = NewButton(sets, label, RU.SET_CHIP_W, RU.SET_CHIP_H, RU.SET_CHIP_FS)
        MakeOutline(bt, 1, 0.82, 0)
        bt.__huiKeepTextColor = true
        bt:SetScript("OnClick", function() RU.SetFilter(key) end)
        texts[i] = TextW(bt:GetFontString(), label)
        RU.chips[i] = { key = key, bt = bt }
    end

    local right = RU.X + RU.W - 2
    local minX = RU.X + 2 + 3 * RU.TAB_STEP + 8
    local n, gap = #texts, RU.SET_CHIP_GAP
    local widest = 0
    for i = 1, n do
        if texts[i] > widest then widest = texts[i] end
    end
    local w = floor((right - minX - gap * (n - 1)) / n)
    if w > RU.SET_CHIP_W then w = RU.SET_CHIP_W end
    if w < widest + 10 then w = widest + 10 end           -- 不截字优先
    local total = w * n + gap * (n - 1)
    local x = right - total
    if x < minX then x = minX end
    for i = 1, n do
        local item = RU.chips[i]
        item.w = w
        item.bt:SetWidth(w)
        item.bt:SetPoint("TOPLEFT", page, "TOPLEFT", x, -RU.TAB_Y)
        x = x + w + gap
    end
end

function RU.RenderTimeline()
    local nodes = RU.nodes
    local y = RU.BODY_Y
    local ri = 0
    for ni, nd in ipairs(nodes) do
        local mk = RU.nodeMarks[ni]
        mk:SetPoint("TOPLEFT", RU.page, "TOPLEFT", RU.X + RU.TL_AXIS - 5, -(y + 4))
        mk:SetColorTexture(1, 0.82, 0, nd.first and 0.95 or 0.35)
        mk:Show()
        local dl = RU.nodeLabels[ni]
        dl:SetPoint("TOPLEFT", RU.page, "TOPLEFT", RU.X + RU.TL_TEXT_X, -y)
        dl:SetText(nd.date)
        dl:SetTextColor(Unpack(nd.first and C_GOLD or C_DIM))
        dl:Show()
        y = y + RU.TL_NODE_H
        for _, rec in ipairs(nd.rows) do
            ri = ri + 1
            local r = RU.rows[ri]
            r:SetPoint("TOPLEFT", RU.page, "TOPLEFT", RU.X + RU.TL_TEXT_X, -y)
            RU.PaintRow(r, rec)
            y = y + RU.TL_ROW_H
        end
        y = y + RU.TL_NODE_GAP
    end
    for j = ri + 1, #RU.rows do RU.rows[j]:Hide() end
    for j = #nodes + 1, #RU.nodeLabels do
        RU.nodeLabels[j]:Hide()
        RU.nodeMarks[j]:Hide()
    end
    RU.axis:SetPoint("BOTTOMLEFT", RU.page, "TOPLEFT", RU.X + RU.TL_AXIS, -(y - RU.TL_NODE_GAP))
end

function RU.RenderList()
    local tiers = RU.tiers
    local groups = {
        { list = tiers[1], w = RU.LS_BIG_W, h = RU.LS_BIG_H,
          title = L["首批开启"], note = RU.FirstOpenText() .. " · " .. L["同日开启"] },
        { list = tiers[2], w = RU.LS_SMALL_W, h = RU.LS_SMALL_H,
          title = L["后续预告"], note = L["官方只给了窗口，名称与地点均未公布"] },
    }
    local y = RU.BODY_Y
    local ci = 0
    for gi, g in ipairs(groups) do
        local lb = RU.wallLabels[(gi - 1) * 2 + 1]
        local nt = RU.wallLabels[(gi - 1) * 2 + 2]
        lb:SetPoint("TOPLEFT", RU.page, "TOPLEFT", RU.X + 2, -y)
        lb:SetText(g.title)
        nt:SetPoint("TOPRIGHT", RU.page, "TOPRIGHT", -(RU.X + 2), -y)
        nt:SetText(g.note)
        y = y + RU.LS_LABEL_H
        local pos = RU.LayoutCards(g.list, g.w, g.h, y)
        for i, rec in ipairs(g.list) do
            ci = ci + 1
            local c = RU.cards[ci]
            c:SetSize(g.w, g.h)
            c:SetPoint("TOPLEFT", RU.page, "TOPLEFT", pos[i].x, pos[i].y)
            RU.PaintCard(c, rec)
        end
        y = pos.bottom + RU.LS_LABEL_H
    end
    for j = ci + 1, #RU.cards do RU.cards[j]:Hide() end
end

function RU.Render()
    if not RU.built then return end
    local tab = CurTab()
    for key, bt in pairs(RU.tabs) do
        local sel = (key == tab)
        SetOutline(bt, sel, 1, 0.82, 0)
        bt:GetFontString():SetTextColor(Unpack(sel and C_GOLD or C_DIM))
    end
    RU.timeline:SetShown(tab == "timeline")
    RU.list:SetShown(tab == "list")
    if RU.sets then RU.sets:SetShown(tab == "sets") end
    RU.SyncHeader(tab)
    UpdateCD()
    if tab == "timeline" then
        RU.RenderTimeline()
    elseif tab == "list" then
        RU.RenderList()
    else
        RU.RenderSets()
    end
end

function RU.SetTab(key)
    DB().tab = key
    RU.Render()
    if ns.PlaySound then ns.PlaySound(1) end
end

function RU.Build(page)
    if RU.built then return end
    RU.built = true
    RU.page = page
    RU.nodes = BuildNodes()
    RU.tiers = { BuildTiers() }
    RU.rows, RU.cards, RU.nodeMarks, RU.nodeLabels, RU.wallLabels = {}, {}, {}, {}, {}
    RU.tabs = {}

    local title = MakeFS(page, 16, C_WHITE, "LEFT")
    title:SetPoint("TOPLEFT", page, "TOPLEFT", RU.X + 2, -RU.TITLE_Y)
    title:SetText(L["团本"])
    local count = MakeFS(page, 14, C_GREY, "RIGHT")
    count:SetPoint("TOPRIGHT", page, "TOPRIGHT", -(RU.X + 2), -RU.TITLE_Y)
    count:SetText(format(L["共 %d 座 · 更新于 %s"], #RU.DATA.raids, RU.DATA.updated))
    local note = MakeFS(page, 14, C_DIM, "LEFT")
    note:SetPoint("TOPLEFT", page, "TOPLEFT", RU.X + 2, -RU.NOTE_Y)
    note:SetText(L["首发即开放 10 / 20 / 40 人团本，2027 年的后续梯队已在排期"])
    RU.count, RU.note = count, note

    RU.cd = MakeFS(page, 14, C_GOLD, "RIGHT")
    RU.cd:SetPoint("TOPRIGHT", page, "TOPRIGHT", -(RU.X + 2), -RU.NOTE_Y)

    local tick = CreateFrame("Frame", nil, page)
    tick:SetScript("OnUpdate", function(_, elapsed)
        RU.cdAcc = (RU.cdAcc or 0) + elapsed
        if RU.cdAcc >= 1 then
            RU.cdAcc = 0
            UpdateCD()
        end
    end)

    local defs = { { key = "timeline", text = L["时间线"] }, { key = "list", text = L["列表"] },
                   { key = "sets", text = L["套装"] } }
    for i, def in ipairs(defs) do
        local bt = NewButton(page, def.text, RU.TAB_W, RU.TAB_H, 14)
        bt:SetPoint("TOPLEFT", page, "TOPLEFT", RU.X + 2 + (i - 1) * RU.TAB_STEP, -RU.TAB_Y)
        MakeOutline(bt, 1, 0.82, 0)
        bt.__huiKeepTextColor = true
        bt:SetScript("OnClick", function() RU.SetTab(def.key) end)
        RU.tabs[def.key] = bt
    end

    local tl = CreateFrame("Frame", nil, page)
    tl:SetAllPoints(page)
    RU.timeline = tl
    local axis = tl:CreateTexture(nil, "BACKGROUND")
    axis:SetColorTexture(1, 1, 1, 0.12)
    axis:SetWidth(1)
    axis:SetPoint("TOPLEFT", page, "TOPLEFT", RU.X + RU.TL_AXIS, -RU.BODY_Y)
    RU.axis = axis
    for i = 1, #RU.nodes do
        local mk = tl:CreateTexture(nil, "ARTWORK")
        mk:SetSize(10, 10)
        mk:SetColorTexture(1, 0.82, 0, 0.9)
        RU.nodeMarks[i] = mk
        RU.nodeLabels[i] = MakeFS(tl, 16, C_GOLD, "LEFT")
    end
    for _ = 1, #RU.DATA.raids do
        RU.rows[#RU.rows + 1] = RU.NewRow(tl)
    end
    local tlNote = MakeFS(tl, 14, C_GREY, "LEFT")
    tlNote:SetPoint("TOPLEFT", page, "TOPLEFT", RU.X + 2, -RU.TL_NOTE_Y)
    tlNote:SetText(L["排期窗口以官方公布为准，未定名的条目仍会变动"])

    local ls = CreateFrame("Frame", nil, page)
    ls:SetAllPoints(page)
    RU.list = ls
    for i = 1, 4 do
        if i % 2 == 1 then
            RU.wallLabels[i] = MakeFS(ls, 14, C_GOLD, "LEFT")
        else
            RU.wallLabels[i] = MakeFS(ls, 11, C_GREY, "RIGHT")
        end
    end
    for _ = 1, #RU.DATA.raids do
        RU.cards[#RU.cards + 1] = RU.NewCard(ls)
    end
    local ruleRule = ls:CreateTexture(nil, "ARTWORK")
    ruleRule:SetColorTexture(1, 1, 1, 0.10)
    ruleRule:SetPoint("TOPLEFT", page, "TOPLEFT", RU.X, -RU.RULES_RULE_Y)
    ruleRule:SetSize(RU.W, 1)
    local rtitle = MakeFS(ls, 16, C_WHITE, "LEFT")
    rtitle:SetPoint("TOPLEFT", page, "TOPLEFT", RU.X + 2, -RU.RULES_TITLE_Y)
    rtitle:SetText(L["团本规则"])
    local gdkpDesc
    for i, rule in ipairs(RU.DATA.rules) do
        local rx = RU.X + 2 + ((i - 1) % 2) * RU.RULES_COL2
        local ry = RU.RULES_TOP + floor((i - 1) / 2) * RU.RULES_ROW_H
        local rn = MakeFS(ls, 14, C_TEXT, "LEFT")
        rn:SetPoint("TOPLEFT", page, "TOPLEFT", rx, -ry)
        rn:SetText(L[rule[1]])
        local rd = MakeFS(ls, 14, C_DIM, "LEFT")
        rd:SetPoint("TOPLEFT", page, "TOPLEFT", rx + RU.RULES_DESC_X, -ry)
        rd:SetText(L[rule[2]])
        if rule[1] == "禁止 GDKP" then gdkpDesc = rd end
    end
    if gdkpDesc then
        RU.cnNote = MakeFS(ls, 14, C_GREY, "LEFT")
        RU.cnNote:SetPoint("LEFT", gdkpDesc, "RIGHT", 14, 0)
        RU.cnNote:SetText(L["国服待确定"])
    end

    RU.BuildSets(page)

    RU.Render()
end
