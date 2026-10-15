-- =============================================================================
-- DungeonsForever · BIS配装页（界面层）
-- 读取 Data_BIS 的配装数据并渲染配装与方案管理；只对无限服加载。
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
local C_GOLD, C_GREY = Host.C_GOLD, Host.C_GREY
local C_DIM, C_WHITE, C_TEXT = Host.C_DIM, Host.C_WHITE, Host.C_TEXT
local C_GREEN = Host.C_GREEN
local PAGE_INSET = Host.PAGE_INSET
local CONTENT_W = Host.CONTENT_W
local FALLBACK_ICON = Host.FALLBACK_ICON

local BIS, VOLS, N_PRESET
-- ★ 分卷（20级 / 30级）：数据源每个职业/专精只维护一份清单，等级上限一涨就整页换掉，
--   所以两卷分别冻结/抓取后一起进包，由「预设方案」行切换（见 PaintPlans）。
--   BIS.classes 是 default 卷的运行期别名；levels 缺失（旧结构数据）时退化成单卷。
-- 三类型定义提到卷常量前：N_PRESET 按「类型 × 卷」展平计数需要它。
local SPEC_DEFS = { { id = "pve", label = L["副本"] }, { id = "pvp", label = L["战场"] },
                    { id = "tank", label = L["坦克"] } }
local function EnsureBIS()
    if VOLS then return BIS end
    VOLS = {}
    local d = ns.EnsureBISData and ns.EnsureBISData() or nil
    BIS = (d and type(d.classes) == "table") and d or nil
    if BIS then
        if type(BIS.levels) == "table" then
            for lv, v in pairs(BIS.levels) do
                if type(v) == "table" and type(v.classes) == "table" then
                    VOLS[#VOLS + 1] = { lv = tonumber(lv) or 0, classes = v.classes }
                end
            end
            table.sort(VOLS, function(a, b) return a.lv < b.lv end)
        end
        if #VOLS == 0 then
            VOLS = { { lv = tonumber(BIS.default) or 0, classes = BIS.classes } }
        end
    end
    N_PRESET = #VOLS * #SPEC_DEFS
    return BIS
end
local N_USER = 7            -- 用户方案行数

local BG = {}
ns.BisModule = BG

local function DefaultVol()
    EnsureBIS()
    local d = BIS and tonumber(BIS.default) or nil
    if d then
        for i, v in ipairs(VOLS) do
            if v.lv == d then return i end
        end
    end
    return #VOLS
end

local function CurVol() EnsureBIS() return VOLS[BG.vol] or VOLS[#VOLS] end

local CLASS_FILE = {
    warrior = "WARRIOR", paladin = "PALADIN", hunter = "HUNTER",
    rogue = "ROGUE", priest = "PRIEST", mage = "MAGE",
    warlock = "WARLOCK", druid = "DRUID", shaman = "SHAMAN",
}

-- 职业图标（Media/icon/CLASS 自制全套，TierUI 同款命名：ClassIcon_<Slug>.blp）。
local function ClassIconPath(slug)
    return "Interface\\AddOns\\DungeonsForever\\Media\\icon\\CLASS\\ClassIcon_"
        .. slug:sub(1, 1) .. slug:sub(2):lower()
end

local SLOTS_LEFT  = { "head", "neck", "shoulder", "back", "chest",
                      "shirt", "tabard", "wrist" }
local SLOTS_RIGHT = { "hands", "waist", "legs", "feet", "finger", "finger2",
                      "trinket", "trinket2" }
local SLOT_NAMES = {
    head = L["头部"], neck = L["颈部"], shoulder = L["肩部"], back = L["背部"], chest = L["胸部"],
    wrist = L["手腕"], hands = L["手部"], waist = L["腰部"], legs = L["腿部"], feet = L["脚"],
    finger = L["戒指"], finger2 = L["戒指"], trinket = L["饰品"], trinket2 = L["饰品"],
    shirt = L["衬衣"], tabard = L["公会徽章"],
    ["two-hand"] = L["双手武器"], ["main-hand"] = L["主手"], ["off-hand"] = L["副手"],
    ranged = L["远程"],
}

local function RowsKey(slotKey)
    if slotKey == "finger2" then return "finger" end
    if slotKey == "trinket2" then return "trinket" end
    if slotKey == "main" then return "main-hand" end
    if slotKey == "off" then return "off-hand" end
    return slotKey
end

local FILTERS = {
    { id = "all", label = L["全部"] }, { id = "craft", label = L["制造"] },
    { id = "quest", label = L["任务"] }, { id = "boss", label = L["副本"] },
    { id = "rare", label = L["稀有"] }, { id = "other", label = L["其他"] },
}

local STAT_ROWS = {
    { "ITEM_MOD_STRENGTH_SHORT",     L["力量"] },
    { "ITEM_MOD_AGILITY_SHORT",      L["敏捷"] },
    { "ITEM_MOD_STAMINA_SHORT",      L["耐力"] },
    { "ITEM_MOD_INTELLECT_SHORT",    L["智力"] },
    { "ITEM_MOD_SPIRIT_SHORT",       L["精神"] },
    { "ITEM_MOD_ATTACK_POWER_SHORT", L["攻击强度"] },
    { "ITEM_MOD_SPELL_POWER_SHORT",  L["法术强度"] },
    { "ITEM_MOD_CRIT_RATING_SHORT",  L["暴击等级"] },
    { "ITEM_MOD_HASTE_RATING_SHORT", L["急速等级"] },
}

local QUALITY_COLORS = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 },
    [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0.2 },
}

local ROW_H = 46
local PLAN_H = 28
local LIST_PAD = 8

local BT = BackdropTemplateMixin and "BackdropTemplate" or nil
local function Cardify(f, bgA, edA)
    if not f.SetBackdrop then return end
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(1, 1, 1, bgA or 0.035)
    f:SetBackdropBorderColor(1, 1, 1, edA or 0.09)
end

local function BuildPanels(page)
    BG.panels = {}
    for i = 1, 4 do
        local p = CreateFrame("Frame", nil, page, BT)
        if ns.hui and ns.hui.BuildRoundedBG then
            ns.hui.BuildRoundedBG(p, 8, ns.hui.layer.L2, "both", true, 1)
        else
            Cardify(p, 0.05, 0.12)
        end
        BG.panels[i] = p
    end
end

local function DB()
    DungeonsForeverDB = DungeonsForeverDB or {}
    local s = DungeonsForeverDB.bis
    if not s then
        s = { plans = {} }
        DungeonsForeverDB.bis = s
    end
    if not s.plans then s.plans = {} end
    return s
end

local function PlansFor(slug)
    local s = DB()
    if not s.plans[slug] then s.plans[slug] = {} end
    return s.plans[slug]
end

-- ★ 一次性存档迁移（两卷并行前的老方案没有等级字段）：
--   统一归到最早的一卷（20级），并按用户口径给名字加「N级 · 」前缀。
--   幂等：跑过就打 migVol 闸；名字已有该前缀的也不会被叠加。
local function MigratePlans()
    local s = DB()
    if s.migVol then return end
    s.migVol = true
    local lv = VOLS[1] and VOLS[1].lv or 20
    local pre = format(L["%d级 · "], lv)
    for _, list in pairs(s.plans) do
        for _, p in ipairs(list) do
            if type(p) == "table" and p.vol == nil then
                p.vol = lv
                local nm = tostring(p.name or "")
                if string.sub(nm, 1, #pre) ~= pre then
                    p.name = pre .. nm
                end
            end
        end
    end
end

BG.cls = "warrior"
BG.spec = "pve"
BG.side = "a"
BG.vol = nil               -- 当前预设卷（下标进 VOLS）
BG.cur = {}
BG.ench = {}
BG.usingPlan = nil
BG.filter = "all"
BG.search = ""
BG.sel = nil

local function ClassRec()
    for _, c in ipairs(CurVol().classes) do
        if c.slug == BG.cls then return c end
    end
end

local function SpecRec()
    local c = ClassRec()
    if not c then return nil end
    for _, sp in ipairs(c.specs) do
        if sp.id == BG.spec then return sp end
    end
    return c.specs[1]
end

local function SpecLabel()
    for _, def in ipairs(SPEC_DEFS) do
        if def.id == BG.spec then return def.label end
    end
    return string.upper(BG.spec)
end

local function RecItem(sp, slotKey)
    if not sp then return nil end
    local sides = sp.slots[slotKey]
    if type(sides) ~= "table" then return nil end
    local s = sides[BG.side == "a" and 1 or 2]
    if type(s) ~= "table" then return nil end
    return s[1], s[2], s[3]
end

local function MainKey(sp)
    return sp and sp.slots["two-hand"] and "two-hand" or "main-hand"
end

local function DataKey(sp, slotKey)
    if slotKey == "main" then return MainKey(sp) end
    if slotKey == "off" then return "off-hand" end
    if slotKey == "ranged" then return "ranged" end
    return slotKey
end

local function CurItem(sp, slotKey)
    local dk = DataKey(sp, slotKey)
    local id = BG.cur[dk]
    if id then return id end
    local pl = BG.usingPlan
    if pl and pl.items and pl.items[dk] then return pl.items[dk] end
    return RecItem(sp, dk)
end

local ENCH_SLOTS = {
    [ns.DL("颈部")] = { "neck" }, [ns.DL("背部")] = { "back" }, [ns.DL("胸部")] = { "chest" },
    [ns.DL("手腕")] = { "wrist" }, [ns.DL("手部")] = { "hands" }, [ns.DL("腿部")] = { "legs" },
    [ns.DL("脚")] = { "feet" }, [ns.DL("肩部")] = { "shoulder" }, [ns.DL("双手武器")] = { "two-hand" },
    [ns.DL("主手")] = { "main-hand" }, [ns.DL("副手")] = { "off-hand" },
    [ns.DL("副手：盾牌")] = { "off-hand" }, [ns.DL("远程")] = { "ranged" },
    [ns.DL("手部、腿部")] = { "hands", "legs" }, [ns.DL("主手、副手")] = { "main-hand", "off-hand" },
}

local function EnchRowsFor(sp, dk)
    local out = {}
    if not (sp and sp.enchs and dk) then return out end
    for _, e in ipairs(sp.enchs) do
        for _, k in ipairs(ENCH_SLOTS[e.slot] or {}) do
            if k == dk then out[#out + 1] = e break end
        end
    end
    return out
end

local function EnchToken(e)
    return e.item or e.eff
end

local function EnchName(e)
    if e.item then
        local nm = DG.ItemName(e.item) or ""
        for _, p in ipairs({ L["公式："], L["公式: "], L["公式:"] }) do
            if string.sub(nm, 1, #p) == p then
                return string.sub(nm, #p + 1)
            end
        end
        return nm
    end
    return e.name or e.eff or ""
end

local function EnchText(sp, tok)
    if tok == nil then return "" end
    if type(tok) == "string" then return tok end
    if sp and sp.enchs then
        for _, e in ipairs(sp.enchs) do
            if e.item == tok and e.eff then return e.eff end
        end
    end
    return DG.ItemName(tok)
end

local function CurEnch(sp, dk)
    local id = BG.ench and BG.ench[dk]
    if id then return id end
    local pl = BG.usingPlan
    if pl and pl.enchs and pl.enchs[dk] then return pl.enchs[dk] end
    local rec = EnchRowsFor(sp, dk)[1]
    if rec then return EnchToken(rec) end
    return nil
end

local CLASS_CN = {
    warrior = L["战士"], paladin = L["圣骑士"], hunter = L["猎人"], rogue = L["潜行者"],
    priest = L["牧师"], mage = L["法师"], warlock = L["术士"], druid = L["德鲁伊"],
    shaman = L["萨满祭司"],
}
local function ClassName(slug)
    local file = CLASS_FILE[slug]
    local T = type(LOCALIZED_CLASS_NAMES) == "table" and LOCALIZED_CLASS_NAMES
    local loc = T and file and T[file]
    return loc or CLASS_CN[slug] or file or slug
end

local function SideLabel()
    return BG.side == "a" and L["联盟"] or L["部落"]
end

local function QColor(q)
    if type(q) == "number" then return QUALITY_COLORS[q] or C_TEXT end
    return C_TEXT
end

local function ItemQuality(sp, itemID, siteQ)
    local _, _, cq = DG.ItemInfo(itemID)
    if type(cq) == "number" then return cq end
    if sp and type(siteQ) == "number" then return siteQ end
    return nil
end

local function ItemIcon(itemID)
    if itemID == nil then return FALLBACK_ICON end
    if C_Item and type(C_Item.GetItemIconByID) == "function" then
        local ok, ic = pcall(C_Item.GetItemIconByID, itemID)
        if ok and type(ic) == "number" and ic ~= 0 then return ic end
    end
    if type(GetItemIcon) == "function" then
        local ok, ic = pcall(GetItemIcon, itemID)
        if ok and type(ic) == "number" and ic ~= 0 then return ic end
    end
    local info = { DG.ItemInfo(itemID) }
    if type(info[10]) == "number" and info[10] ~= 0 then return info[10] end
    local ins = { DG.ItemInfoInstant(itemID) }
    if type(ins[10]) == "number" and ins[10] ~= 0 then return ins[10] end
    return FALLBACK_ICON
end

local function ItemTip(owner, itemID, extra)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local link = DG.ItemLink(itemID)
    local ok = false
    if link then
        ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
            and type(GameTooltip.NumLines) == "function"
            and (GameTooltip:NumLines() or 0) > 0
    end
    if not ok then
        GameTooltip:AddLine(DG.ItemName(itemID), 0.8, 0.8, 0.8, true)
    end
    if extra then
        for _, ln in ipairs(extra) do
            GameTooltip:AddLine(ln, 0.55, 0.75, 0.55, true)
        end
    end
    GameTooltip:Show()
end

local function TipOff()
    if GameTooltip then pcall(GameTooltip.Hide, GameTooltip) end
end

local function LinkToChat(itemID)
    local _, link = DG.ItemInfo(itemID)
    if link and ChatFrame_InsertLink then
        ChatFrame_InsertLink(link)
    end
end

local PROF_NAMES = {
    blacksmithing = L["锻造"], leatherworking = L["制皮"], tailoring = L["裁缝"],
    alchemy = L["炼金"], engineering = L["工程学"], enchanting = L["附魔"],
    cooking = L["烹饪"], firstaid = L["急救"], fishing = L["钓鱼"],
}

local function QuestTitle(qid)
    if not (C_QuestLog and C_QuestLog.GetTitleForQuestID) then return nil end
    local ok, t = pcall(C_QuestLog.GetTitleForQuestID, qid)
    if ok and type(t) == "string" and t ~= "" then return t end
    return nil
end

local function SrcText(src)
    if type(src) ~= "table" then return "" end
    local t = src.t
    if t == "quest" then
        local qid = src.q and tonumber(src.q) or nil
        local qn = qid and QuestTitle(qid) or nil
        local head = L["任务："] .. (qn or (qid and ("#" .. qid) or "?"))
        if not src.note or src.note == "" then return head end
        local note = src.note:gsub("(%d+)%s*级起", "%1级可接")
        note = note:gsub("(%d+)%s*級起", "%1級可接")
        note = note:gsub("[、，]", " · ")
        return head .. " · " .. note
    elseif t == "boss" then
        local who = src.boss and (src.boss .. " · ") or ""
        return who .. (src.dung or L["副本"]) .. (src.rate and (" · " .. src.rate) or "")
    elseif t == "craft" then
        local pn = PROF_NAMES[src.prof] or src.prof or L["制造"]
        return pn .. (src.lvl and format("（%d）", src.lvl) or "")
            .. (src.note and (" · " .. src.note) or "")
    elseif t == "rare" then
        return L["稀有 · "] .. (src.note or "")
    elseif t == "books" then
        return src.note or L["图书馆之友"]
    end
    return src.note or ""
end

local function SrcKind(src)
    local t = type(src) == "table" and src.t or nil
    if t == "quest" then return "quest" end
    if t == "craft" then return "craft" end
    if t == "boss" then return "boss" end
    if t == "rare" then return "rare" end
    return "other"
end

local ALL_SLOT_KEYS = {}
for _, k in ipairs(SLOTS_LEFT) do ALL_SLOT_KEYS[#ALL_SLOT_KEYS + 1] = k end
for _, k in ipairs(SLOTS_RIGHT) do ALL_SLOT_KEYS[#ALL_SLOT_KEYS + 1] = k end
ALL_SLOT_KEYS[#ALL_SLOT_KEYS + 1] = "two-hand"
ALL_SLOT_KEYS[#ALL_SLOT_KEYS + 1] = "main-hand"
ALL_SLOT_KEYS[#ALL_SLOT_KEYS + 1] = "off-hand"
ALL_SLOT_KEYS[#ALL_SLOT_KEYS + 1] = "ranged"

local function SumStats()
    local sp = SpecRec()
    local acc = {}
    if not sp then return acc end
    local seen = {}
    for _, key in ipairs(ALL_SLOT_KEYS) do
        local id = BG.cur[key] or RecItem(sp, key)
        if id and not seen[id] then
            seen[id] = true
            local fn = GetItemStats or (C_Item and C_Item.GetItemStats)
            if type(fn) == "function" then
                local ok, stats = pcall(fn, DG.ItemLink(id))
                if ok and type(stats) == "table" then
                    for k, v in pairs(stats) do
                        if type(v) == "number" then acc[k] = (acc[k] or 0) + v end
                    end
                end
            end
        end
    end
    return acc
end

-- 顶栏涂装（2026-10-10 重排定案）：职业按钮排与三类型标签整体退役（职业走下拉、
--   类型并入预设方案行），本函数只剩阵营钮态 + 标题 + 下拉按钮文案同步。
local function PaintTopbar()
    for id, btn in pairs(BG.sideBtns) do
        local on = BG.side == id
        SetOutline(btn, on, Unpack(C_GOLD))
        btn.lbl:SetTextColor(Unpack(on and C_GOLD or C_TEXT))
    end
    if BG.ddBtn then
        BG.ddBtn:SetText(ClassName(BG.cls))
        -- ★ 切职业后同步：文字保持职业色 + 图标换图（用户定案 2026-10-11）。
        local rc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[CLASS_FILE[BG.cls] or ""]
        if rc and rc.r then BG.ddBtn.lbl:SetTextColor(rc.r, rc.g, rc.b) end
        if BG.ddBtn.__icon then BG.ddBtn.__icon:SetTexture(ClassIconPath(BG.cls)) end
    end
    BG.head:SetText(format("%s · %s · %s", ClassName(BG.cls), SpecLabel(), SideLabel()))
end

local function PaintDoll()
    local sp = SpecRec()
    if not sp then return end
    local mk = MainKey(sp)
    for key, cell in pairs(BG.dollCells) do
        local dkey = key
        if key == "main" then dkey = mk end
        if key == "off" then dkey = "off-hand" end
        if key == "ranged" then dkey = "ranged" end
        cell.__dkey = dkey
        local id, q, ench = CurItem(sp, key)
        local empty = not id
        if key == "off" and mk == "two-hand" then empty = true end
        if empty then
            cell.icon:SetTexture("")
            cell.name:SetText(key == "off" and mk == "two-hand"
                and L["被双手武器占用"] or "—")
            cell.name:SetTextColor(Unpack(C_DIM))
        else
            cell.icon:SetTexture(ItemIcon(id))
            cell.name:SetText(DG.ItemName(id))
            cell.name:SetTextColor(Unpack(QColor(ItemQuality(sp, id, q))))
        end
        cell.ench:SetText(EnchText(sp, CurEnch(sp, dkey)))
        local sel = BG.sel ~= nil and BG.sel == key
        SetOutline(cell, sel == true, Unpack(C_GOLD))
        cell.dot:SetShown(BG.cur[dkey] ~= nil)
    end
end

local function PaintStats()
    local acc = SumStats()
    -- ★ 动态高度（用户定案 2026-10-11）：无值属性行隐藏、可见行紧凑重排（原全量
    --   绝对定位，空值行也占位）；汇总卡高 = 内容实高（BG.LayoutMid），剩余高度全部
    --   让给下方方案卡。
    local n = 0
    for _, row in ipairs(BG.statRows) do
        local v = acc[row[1]]
        if v then
            local ry = 30 + n * 24
            row.lab:ClearAllPoints()
            row.lab:SetPoint("TOPLEFT", BG.statParent, "TOPLEFT", 12, -ry)
            row.val:ClearAllPoints()
            row.val:SetPoint("TOPRIGHT", BG.statParent, "TOPRIGHT", -12, -ry)
            row.val:SetText(tostring(v))
            row.val:SetTextColor(Unpack(C_GREEN))
            row.lab:Show()
            row.val:Show()
            n = n + 1
        else
            row.lab:Hide()
            row.val:Hide()
        end
    end
    BG.LayoutMid(n)
end

-- ★ 布局换向修正（用户截图纠偏 2026-10-11）：中列两卡是「方案（panel2）在上、
--   属性汇总（panel3）在下且底边钉页底窗沿」。属性汇总卡高随内容向上长（顶边 =
--   页底窗沿 + 内容实高，TOPLEFT 锚 page BOTTOMLEFT，y 正=上）；方案卡顶钉页顶
--   窗沿（Build 初值），底边 = 属性汇总顶 - 8 ⇒ 剩余高度全部归方案滚动区（其底边
--   锚面板底，见 BuildMid）。由 PaintStats 每次渲染调用（可见行数随职业/专精变化）。
function BG.LayoutMid(n)
    if not (BG.page and BG.py and BG.panels and BG.panels[2] and BG.panels[3]) then return end
    local statH = 30 + n * 24 + 8
    -- ★ ★ 全量重锚纪律（接缝贴死实锤 2026-10-11）：本引擎 SetPoint 对「同点位、
    --   不同参照系」的旧锚不保证替换（Build 初锚与动态锚共存拉扯）——必须先
    --   ClearAllPoints 再四边一次锚齐。
    local p3 = BG.panels[3]
    p3:ClearAllPoints()
    p3:SetPoint("TOPLEFT", BG.page, "BOTTOMLEFT", 320, PAGE_INSET + statH)
    p3:SetPoint("BOTTOMRIGHT", BG.page, "BOTTOMLEFT", 544, PAGE_INSET)
    local p2 = BG.panels[2]
    p2:ClearAllPoints()
    p2:SetPoint("TOPLEFT", BG.page, "TOPLEFT", 320, -BG.py)
    -- ★ 底部锚 y 正=上（项目铁律）：方案卡底边要在属性汇总顶边「上方 8」⇒ +8。
    --   （此前写 -8 = 向下伸进属性汇总顶下 8 UI，被上层盖住 ⇒ 可见间距 0。）
    p2:SetPoint("BOTTOMRIGHT", p3, "TOPLEFT", 224, 8)
end

-- 当前职业可用的预设条目（类型 × 卷，按 SPEC_DEFS 顺序展平）：
--   缺该类型的职业（如牧师无战场/坦克）自然少几行，列表场景直接不渲染，不灰置。
local function PresetList()
    local c = ClassRec()
    local out = {}
    if not c then return out end
    for _, def in ipairs(SPEC_DEFS) do
        local has = false
        for _, sp in ipairs(c.specs) do
            if sp.id == def.id then has = true break end
        end
        if has then
            for i = 1, #VOLS do
                out[#out + 1] = { vol = i, spec = def.id, label = def.label }
            end
        end
    end
    return out
end

local function PaintPlans()
    local plans = PlansFor(BG.cls)
    local rows = BG.planRows
    local y = 0
    -- ① 预设方案：类型 × 卷 展平（「20级推荐 · 副本」「20级推荐 · 战场」…），
    --    点中即切卷+切类型；active = 三元全中（无覆盖方案 + 卷 + 类型）。
    local presets = PresetList()
    for i = 1, N_PRESET do
        local r = rows[i]
        local pe = presets[i]
        if pe then
            r:Show()
            local active = (BG.usingPlan == nil and BG.vol == pe.vol and BG.spec == pe.spec)
            r.title:SetText(format(L["%d级推荐 · %s"], VOLS[pe.vol].lv, pe.label))
            r.dot:SetShown(active)
            r.__plan = nil
            r.__vol = pe.vol
            r.__spec = pe.spec
            SetOutline(r, active, Unpack(C_GOLD))
            r.title:SetTextColor(Unpack(active and C_GOLD or C_TEXT))
            r:SetPoint("TOPLEFT", BG.planChild, "TOPLEFT", 0, -y)
            r:SetPoint("RIGHT", BG.planChild, "RIGHT", 0, 0)
            y = y + PLAN_H + 4
        else
            r:Hide()
        end
    end
    -- ② 用户方案（自带等级，载入时把卷一起还原）
    for i = 1, N_USER do
        local r = rows[N_PRESET + i]
        local p = plans[i]
        if p then
            r:Show()
            r.title:SetText(p.name)
            local active = p == BG.usingPlan
            r.dot:SetShown(false)
            SetOutline(r, active, Unpack(C_GOLD))
            r.title:SetTextColor(Unpack(active and C_GOLD or C_TEXT))
            r.__plan = p
            r.__vol = nil
            r:SetPoint("TOPLEFT", BG.planChild, "TOPLEFT", 0, -y)
            r:SetPoint("RIGHT", BG.planChild, "RIGHT", 0, 0)
            y = y + PLAN_H + 4
        else
            r:Hide()
        end
    end
    local has = BG.usingPlan ~= nil
    BG.renameBtn:SetEnabled(has)
    BG.deleteBtn:SetEnabled(has)
    BG.renameBtn.lbl:SetTextColor(Unpack(has and C_TEXT or C_DIM))
    BG.deleteBtn.lbl:SetTextColor(Unpack(has and C_TEXT or C_DIM))
    BG.planChild:SetHeight(y + 6)
end

local function ScanOwned()
    local t = {}
    for slot = 1, 19 do
        local id = GetInventoryItemID and GetInventoryItemID("player", slot)
        if id and id > 0 then t[id] = true end
    end
    for bag = 0, 11 do
        for s = 1, 32 do
            local iid
            if C_Container and C_Container.GetContainerItemInfo then
                local ok, ci = pcall(C_Container.GetContainerItemInfo, bag, s)
                if ok and type(ci) == "table" then iid = ci.itemID end
            elseif GetContainerItemInfo then
                local ok, id = pcall(GetContainerItemInfo, bag, s)
                if ok and type(id) == "number" then iid = id end
            end
            if iid and iid > 0 then t[iid] = true end
        end
    end
    return t
end

local function PaintBrowser()
    local sp = SpecRec()
    if not sp then return end
    local rkey = BG.sel and RowsKey(BG.sel) or nil
    if rkey == "main-hand" then rkey = MainKey(sp) end
    if BG.sel then
        BG.bwTitle:SetText(format(L["%s · 备选"], SLOT_NAMES[BG.sel] or BG.sel))
        local cur = CurItem(sp, BG.sel)
        BG.bwCount:SetText(SideLabel() .. L[" · 当前："] .. (cur and DG.ItemName(cur) or "—"))
    else
        BG.bwTitle:SetText(L["点左侧部位查看备选"])
        BG.bwCount:SetText(SideLabel() .. " · " .. ClassName(BG.cls))
    end
    for _, f in ipairs(FILTERS) do
        local btn = BG.filterBtns[f.id]
        local on = BG.filter == f.id
        SetOutline(btn, on, Unpack(C_GOLD))
        btn.lbl:SetTextColor(Unpack(on and C_GOLD or C_TEXT))
    end
    local list = {}
    if BG.sel and rkey then
        for _, row in ipairs(sp.rows[rkey] or {}) do
            local pass = (BG.filter == "all" or BG.filter == SrcKind(row.src))
            if pass and row.side and row.side ~= BG.side then pass = false end
            if pass and BG.search ~= "" then
                local nm = string.lower(DG.ItemName(row.item))
                if not string.find(nm, BG.search, 1, true) then pass = false end
            end
            if pass then list[#list + 1] = row end
        end
    end
    BG.pool = list
    BG.owned = ScanOwned()
    local rows = BG.bwRows
    for i = 1, #rows do rows[i]:Hide() end
    local equipped = BG.sel and BG.cur[DataKey(sp, BG.sel)] or nil
    local y = 0
    for i, row in ipairs(list) do
        if i > #rows then break end
        local r = rows[i]
        r:Show()
        r.__row = row
        r.icon:SetTexture(ItemIcon(row.item))
        r.name:SetText(DG.ItemName(row.item))
        r.name:SetTextColor(Unpack(QColor(ItemQuality(sp, row.item, row.q))))
        local st = SrcText(row.src)
        r.src:SetText(st)
        r.src:SetTextColor(Unpack(C_GREY))
        if row.src and row.src.t == "quest" and row.src.q then
            local qid = tonumber(row.src.q)
            if qid and not QuestTitle(qid) then BG.needNames = true end
        end
        r.eqTag:SetShown(equipped == row.item)
        r.ownTag:SetShown(BG.owned ~= nil and BG.owned[row.item] ~= nil)
        r.sideTag:SetShown(row.side ~= nil)
        if row.side then r.sideTag:SetText(row.side == "a" and L["联盟"] or L["部落"]) end
        r:SetPoint("TOPLEFT", BG.bwChild, "TOPLEFT", 0, -y)
        r:SetPoint("RIGHT", BG.bwChild, "RIGHT", 0, 0)
        y = y + ROW_H + 2
    end
    if BG.sel and #list == 0 and rows[1] then
        local r = rows[1]
        r:Show()
        r.__row = nil
        r.icon:SetTexture("")
        r.name:SetText(L["这个筛选下没有条目"])
        r.name:SetTextColor(Unpack(C_DIM))
        r.src:SetText("")
        r.eqTag:SetShown(false)
        r.ownTag:SetShown(false)
        r.sideTag:SetShown(false)
        r:SetPoint("TOPLEFT", BG.bwChild, "TOPLEFT", 0, -y)
        r:SetPoint("RIGHT", BG.bwChild, "RIGHT", 0, 0)
        y = y + ROW_H
    end
    BG.bwChild:SetHeight(y + LIST_PAD)
    if BG.needNames then BG.ScheduleSweep() end
end

local function PaintEnchs()
    local sp = SpecRec()
    local rows = BG.enchRows
    for i = 1, #rows do rows[i]:Hide() end
    local dk = BG.sel and DataKey(sp, BG.sel) or nil
    local list = EnchRowsFor(sp, dk)
    local y = 0
    for i, e in ipairs(list) do
        if i > #rows then break end
        local r = rows[i]
        r:Show()
        r.__ench = e
        r.name:SetText(EnchName(e))
        r.lvl:SetText(e.lvl and format(L["附魔 %d"], e.lvl) or "")
        r.note:SetText(e.eff or "")
        r.note:SetTextColor(Unpack(C_TEXT))
        local sel = CurEnch(sp, dk) == EnchToken(e)
        SetOutline(r, sel, Unpack(C_GOLD))
        r.name:SetTextColor(Unpack(sel and C_GOLD or C_TEXT))
        r:SetPoint("TOPLEFT", BG.enchChild, "TOPLEFT", 0, -y)
        r:SetPoint("RIGHT", BG.enchChild, "RIGHT", 0, 0)
        y = y + 38
    end
    if #list == 0 and rows[1] then
        local r = rows[1]
        r:Show()
        r.__ench = nil
        r.name:SetText(BG.sel and L["该部位没有附魔推荐"] or L["点左侧部位查看该部位的附魔"])
        r.name:SetTextColor(Unpack(C_DIM))
        r.lvl:SetText("")
        r.note:SetText("")
        SetOutline(r, false)
        r:SetPoint("TOPLEFT", BG.enchChild, "TOPLEFT", 0, 0)
        r:SetPoint("RIGHT", BG.enchChild, "RIGHT", 0, 0)
        y = 38
    end
    BG.enchChild:SetHeight(y + 4)
    if BG.needNames then BG.ScheduleSweep() end
end

local function PY()
    if coroutine.running and coroutine.running() then coroutine.yield() end
end

function BG.Render()
    if not BG.built then return end
    EnsureBIS()
    if not BG.vol then BG.vol = DefaultVol() end
    PaintTopbar()
    PY()
    PaintDoll()
    PY()
    PaintStats()
    PaintPlans()
    PY()
    PaintBrowser()
    PaintEnchs()
end

function BG.Open()
    if not BG.built then return end
    BG.Render()
end

function BG.Refresh()
    if not BG.built then return end
    BG.Render()
end

function BG.SetSlot(slotKey, itemID)
    if not slotKey then return end
    local dk = DataKey(SpecRec(), slotKey)
    if itemID == nil then BG.cur[dk] = nil else BG.cur[dk] = itemID end
    BG.Render()
end

function BG.SelectSlot(slotKey)
    BG.sel = slotKey
    BG.Render()
end

function BG.SelectClass(slug)
    BG.cls = slug
    BG.cur = {}
    BG.ench = {}
    BG.usingPlan = nil
    BG.sel = nil
    BG.Render()
end

function BG.SelectSpec(id)
    BG.spec = id
    BG.cur = {}
    BG.ench = {}
    BG.usingPlan = nil
    BG.Render()
end

function BG.SelectSide(side)
    BG.side = side
    BG.Render()
end

function BG.SavePlan()
    local sp = SpecRec()
    if not sp then return end
    local plans = PlansFor(BG.cls)
    local items = {}
    for _, dk in ipairs(ALL_SLOT_KEYS) do
        local id = BG.cur[dk]
        if not id and BG.usingPlan and BG.usingPlan.items then
            id = BG.usingPlan.items[dk]
        end
        if not id then id = RecItem(sp, dk) end
        if id then items[dk] = id end
    end
    local enchs = {}
    for _, dk in ipairs(ALL_SLOT_KEYS) do
        local eid = CurEnch(sp, dk)
        if eid then enchs[dk] = eid end
    end
    local p = { name = format(L["%d级 · %s · 我的方案 %d"], CurVol().lv, SpecLabel(), #plans + 1),
                items = items, enchs = enchs, side = BG.side, spec = BG.spec,
                vol = CurVol().lv }   -- 存「等级号」(20/30)，与 UsePlan 的 v.lv 比对口径一致
    plans[#plans + 1] = p
    BG.cur = {}
    BG.ench = {}
    BG.usingPlan = p
    BG.Render()
end

function BG.UsePlan(plan)
    BG.cur = {}
    BG.ench = {}
    BG.usingPlan = plan
    if plan then
        if plan.side then BG.side = plan.side end
        if plan.vol then
            for i, v in ipairs(VOLS) do
                if v.lv == plan.vol then BG.vol = i break end
            end
        end
        if plan.spec then
            local c = ClassRec()
            if c then
                for _, sp in ipairs(c.specs) do
                    if sp.id == plan.spec then BG.spec = plan.spec end
                end
            end
        end
    end
    BG.Render()
end

-- 预设方案行被点：切到该等级卷 + 该类型（specId 由方案行携带），同时清掉本会话
--   覆盖，回到该卷该类型的推荐
function BG.UsePreset(idx, specId)
    if not VOLS[idx] then return end
    BG.vol = idx
    if specId then BG.spec = specId end
    BG.cur = {}
    BG.ench = {}
    BG.usingPlan = nil
    BG.Render()
end

function BG.ResetToRec()
    BG.cur = {}
    BG.ench = {}
    BG.usingPlan = nil
    BG.Render()
end

function BG.SweepNames()
    if not BG.built or not BG.needNames then BG._sweepQueued = false return end
    BG.needNames = false
    local sp = SpecRec()
    if sp then
        for _, key in ipairs(ALL_SLOT_KEYS) do
            local id = CurItem(sp, key)
            if id then
                local _, ok = DG.ItemName(id)
                if not ok then BG.needNames = true end
            end
            local eid = CurEnch(sp, key)
            if eid then
                local _, ok = DG.ItemName(eid)
                if not ok then BG.needNames = true end
            end
        end
        for _, row in ipairs(BG.pool or {}) do
            local _, ok = DG.ItemName(row.item)
            if not ok then BG.needNames = true end
            if row.src and row.src.t == "quest" and row.src.q then
                local qid = tonumber(row.src.q)
                if qid and not QuestTitle(qid) then BG.needNames = true end
            end
        end
        for _, r in ipairs(BG.enchRows or {}) do
            if r.__ench and r.__ench.item then
                local _, ok = DG.ItemName(r.__ench.item)
                if not ok then BG.needNames = true end
            end
        end
    end
    BG.Render()
    if BG.needNames then BG.ScheduleSweep() end
end

function BG.ScheduleSweep()
    if BG._sweepQueued then return end
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
    BG._sweepQueued = true
    C_Timer.After(1.0, function()
        BG._sweepQueued = false
        BG.SweepNames()
    end)
end

local function MakeCell(parent, w, slotLabel, mirror)
    local c = CreateFrame("Button", nil, parent, BT)
    c:SetSize(w, 44)
    if ns.hui and ns.hui.BuildRoundedBG then
        ns.hui.BuildRoundedBG(c, 6, ns.hui.layer.L2, "both", true, 1)
    else
        Cardify(c)
    end
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(26, 26)
    c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(c.icon) end
    c.slot = MakeFS(c, 11, C_GREY, "LEFT")
    c.slot:SetWordWrap(false)
    c.slot:SetText(slotLabel)
    c.name = MakeFS(c, 14, C_TEXT, "LEFT")
    c.name:SetWidth(w - 42)
    c.name:SetWordWrap(false)
    c.ench = MakeFS(c, 11, C_GREEN, "LEFT")
    c.ench:SetWordWrap(false)
    c.dot = c:CreateTexture(nil, "OVERLAY")
    c.dot:SetSize(5, 5)
    c.dot:SetColorTexture(0.94, 0.71, 0.24, 1)
    c.dot:SetShown(false)
    c:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
    local hl = c:GetHighlightTexture()
    hl:SetColorTexture(1, 1, 1, 0.06)
    if not mirror then
        c.slot:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -3)
        c.ench:SetPoint("TOPRIGHT", c, "TOPRIGHT", -6, -3)
        c.icon:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -16)
        c.name:SetPoint("LEFT", c.icon, "RIGHT", 6, 0)
    else
        c.slot:SetPoint("TOPRIGHT", c, "TOPRIGHT", -6, -3)
        c.slot:SetJustifyH("RIGHT")
        c.ench:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -3)
        c.icon:SetPoint("TOPRIGHT", c, "TOPRIGHT", -6, -16)
        c.name:SetPoint("RIGHT", c.icon, "LEFT", -6, 0)
        c.name:SetJustifyH("RIGHT")
    end
    c:SetScript("OnEnter", function(self)
        local sp = SpecRec()
        local id = CurItem(sp, self.__key)
        if id and not (self.__key == "off" and MainKey(sp) == "two-hand") then
            ItemTip(self, id)
        end
    end)
    c:SetScript("OnLeave", TipOff)
    MakeOutline(c, Unpack(C_GOLD))
    return c
end

local function ClickSlot(key, dkey)
    return function(self)
        if IsShiftKeyDown() then
            local sp = SpecRec()
            local id = CurItem(sp, key)
            if id then
                LinkToChat(id)
                return
            end
        end
        BG.SelectSlot(dkey or key)
        ns.PlaySound(1)
    end
end

function BG.OpenClassMenu(owner)
    local items = {}
    for _, c in ipairs(BIS.classes or {}) do
        local color
        local rc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[CLASS_FILE[c.slug] or ""]
        if rc and rc.r then
            color = format("|cFF%02X%02X%02X",
                math.floor(rc.r * 255 + 0.5), math.floor(rc.g * 255 + 0.5),
                math.floor(rc.b * 255 + 0.5))
        end
        items[#items + 1] = {
            text = (c.slug == BG.cls and "● " or "") .. ClassName(c.slug),
            color = color,
            func = function() BG.SelectClass(c.slug) end,
        }
    end
    ns.hui.ShowMenu(items, { owner = owner })
end

-- 顶行（2026-10-10 重排定案）：三类型标签退场 ⇒ 原位放职业下拉；阵营两钮同行右移；
--   标题行 y=yt+30。占高不变（返回 yt+48）⇒ 人偶/浏览器/中部面板全部下游连锁零改动。
local function BuildSpecRow(parent, yt)
    local x, y = 6, yt
    local dd = NewButton(parent, ClassName(BG.cls), 140, 24, 14)
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    dd.lbl = dd:GetFontString()
    -- ★ 职业图标（用户定案：职业名左侧 16px，文字右移让位）+ 按钮文字 = 职业色
    --   （不吃按钮皮白字；__huiKeepTextColor 防悬停重涂，TierUI 职业钮同款验证路径）。
    dd.lbl:ClearAllPoints()
    dd.lbl:SetPoint("LEFT", dd, "LEFT", 27, 0)
    local rc0 = RAID_CLASS_COLORS and RAID_CLASS_COLORS[CLASS_FILE[BG.cls] or ""]
    if rc0 and rc0.r then dd.lbl:SetTextColor(rc0.r, rc0.g, rc0.b) end
    local ic = dd:CreateTexture(nil, "ARTWORK")
    ic:SetSize(16, 16)
    ic:SetPoint("LEFT", dd, "LEFT", 6, 0)
    ic:SetTexture(ClassIconPath(BG.cls))
    dd.__icon = ic
    MakeOutline(dd, Unpack(C_GOLD))
    dd.__huiKeepTextColor = true
    dd:SetScript("OnClick", function() BG.OpenClassMenu(dd) end)
    BG.ddBtn = dd
    x = x + 150
    BG.sideBtns = {}
    for _, sd in ipairs({ { id = "a", label = L["联盟"] }, { id = "h", label = L["部落"] } }) do
        local bt = NewButton(parent, sd.label, 52, 24, 12)
        bt:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
        bt.lbl = bt:GetFontString()
        MakeOutline(bt, Unpack(C_GOLD))
        bt:SetScript("OnClick", function() BG.SelectSide(sd.id) end)
        BG.sideBtns[sd.id] = bt
        x = x + 56
    end
    BG.head = MakeFS(parent, 16, C_WHITE, "LEFT")
    BG.head:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -(yt + 30))
    return yt + 48
end

local function BuildDoll(parent, lt)
    BG.dollCells = {}
    local w, lh = 140, 52
    for i, key in ipairs(SLOTS_LEFT) do
        local c = MakeCell(parent, w, SLOT_NAMES[key] or key, false)
        c.__key = key
        c:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -(lt + (i - 1) * lh))
        c:SetScript("OnClick", ClickSlot(key))
        BG.dollCells[key] = c
    end
    local rx = 6 + w + 8
    for i, key in ipairs(SLOTS_RIGHT) do
        local c = MakeCell(parent, w, SLOT_NAMES[key] or key, true)
        c.__key = key
        c:SetPoint("TOPLEFT", parent, "TOPLEFT", rx, -(lt + (i - 1) * lh))
        c:SetScript("OnClick", ClickSlot(key))
        BG.dollCells[key] = c
    end
    local wy = lt + #SLOTS_RIGHT * lh
    for i, wk in ipairs({ { "main", L["主手"], false }, { "ranged", L["远程"], true } }) do
        local c = MakeCell(parent, w, wk[2], wk[3])
        c.__key = wk[1]
        c:SetPoint("TOPLEFT", parent, "TOPLEFT",
                   i == 1 and 6 or rx, -wy)
        c:SetScript("OnClick", ClickSlot(wk[1], wk[1] == "main" and "main" or nil))
        BG.dollCells[wk[1]] = c
    end
    local off = MakeCell(parent, w, L["副手"], false)
    off.__key = "off"
    off:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -(wy + 44 + 8))
    off:SetScript("OnClick", ClickSlot("off"))
    BG.dollCells["off"] = off
    return wy + 44 + 8 + 44
end

local function MakePlanRow(parent)
    local r = CreateFrame("Button", nil, parent, BT)
    r:SetHeight(PLAN_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    Cardify(r)
    r:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
    local hl = r:GetHighlightTexture()
    hl:SetColorTexture(1, 1, 1, 0.06)
    r.title = MakeFS(r, 14, C_TEXT, "LEFT")
    r.title:SetPoint("TOPLEFT", r, "TOPLEFT", 8, -2)
    r.title:SetWordWrap(false)
    r.title:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    r.meta = MakeFS(r, 11, C_GREY, "LEFT")
    r.meta:SetShown(false)
    r.dot = r:CreateTexture(nil, "OVERLAY")
    r.dot:SetSize(5, 5)
    r.dot:SetColorTexture(0.94, 0.71, 0.24, 1)
    r.dot:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    r.dot:SetShown(false)
    MakeOutline(r, Unpack(C_GOLD))
    r.edit = CreateFrame("EditBox", nil, r, BT)
    r.edit:SetAllPoints()
    if r.edit.SetBackdrop then
        r.edit:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        r.edit:SetBackdropColor(0, 0, 0, 0.35)
        r.edit:SetBackdropBorderColor(0.94, 0.71, 0.24, 0.6)
    end
    r.edit:SetFontObject("GameFontHighlightSmall")
    r.edit:SetTextInsets(8, 8, 0, 0)
    r.edit:SetAutoFocus(false)
    r.edit:SetMaxLetters(16)
    r.edit:Hide()
    r.edit:SetScript("OnEnterPressed", function(self)
        local p = r.__plan
        local txt = self:GetText()
        if p and txt ~= "" then p.name = txt end
        self:ClearFocus()
        self:Hide()
        BG.Render()
    end)
    r.edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:Hide()
    end)
    r.edit:SetScript("OnEditFocusLost", function(self) self:Hide() end)
    r:SetScript("OnClick", function(self, button)
        if button == "RightButton" and self.__plan then
            if IsShiftKeyDown() then
                local plans = PlansFor(BG.cls)
                for i, p in ipairs(plans) do
                    if p == self.__plan then table.remove(plans, i) break end
                end
                if BG.usingPlan == self.__plan then BG.usingPlan = nil end
                BG.Render()
                return
            end
            self.edit:SetText(self.__plan.name or "")
            self.edit:Show()
            self.edit:SetFocus()
            return
        end
        if self.__plan then
            BG.UsePlan(self.__plan)
        elseif self.__vol then
            BG.UsePreset(self.__vol, self.__spec)
        else
            BG.ResetToRec()
        end
        ns.PlaySound(1)
    end)
    return r
end

local function BuildMid(m1, m2)
    local x, w = 8, 208
    BG.planHead = MakeFS(m1, 16, C_WHITE, "LEFT")
    BG.planHead:SetPoint("TOPLEFT", m1, "TOPLEFT", x, -6)
    BG.planHead:SetText(L["方案"])
    BG.renameBtn = NewButton(m1, L["改名"], 44, 22, 12)
    BG.renameBtn.lbl = BG.renameBtn:GetFontString()
    BG.renameBtn:SetPoint("LEFT", BG.planHead, "RIGHT", 8, 0)
    BG.renameBtn:SetScript("OnClick", function()
        local p = BG.usingPlan
        if not p then return end
        for _, r in ipairs(BG.planRows) do
            if r.__plan == p then
                r.edit:SetText(p.name or "")
                r.edit:Show()
                r.edit:SetFocus()
                return
            end
        end
    end)
    BG.deleteBtn = NewButton(m1, L["删除"], 44, 22, 12)
    BG.deleteBtn.lbl = BG.deleteBtn:GetFontString()
    BG.deleteBtn:SetPoint("LEFT", BG.renameBtn, "RIGHT", 4, 0)
    BG.deleteBtn:SetScript("OnClick", function()
        local p = BG.usingPlan
        if not p then return end
        local plans = PlansFor(BG.cls)
        for i, q in ipairs(plans) do
            if q == p then table.remove(plans, i) break end
        end
        BG.usingPlan = nil
        BG.Render()
        ns.PlaySound(1)
    end)

    local save = NewButton(m1, L["另存当前"], (w - 6) / 2, 24, 12)
    save:SetPoint("TOPLEFT", m1, "TOPLEFT", x, -30)
    save:SetScript("OnClick", function() BG.SavePlan() end)
    local reset = NewButton(m1, L["恢复推荐"], (w - 6) / 2, 24, 12)
    reset:SetPoint("TOPLEFT", m1, "TOPLEFT", x + (w - 6) / 2 + 6, -30)
    reset:SetScript("OnClick", function() BG.ResetToRec() end)

    local pool = CreateFrame("ScrollFrame", nil, m1)
    pool:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, pool)
    child:SetSize(w - 8, 10)
    pool:SetScrollChild(child)
    pool:SetPoint("TOPLEFT", m1, "TOPLEFT", x, -60)
    -- ★ 方案滚动区吃剩余高度（用户定案 2026-10-11）：底边锚面板底（面板本身钉页底
    --   窗沿、顶随属性汇总卡动态下移，见 BG.LayoutMid），不再写死 160。
    pool:SetPoint("BOTTOMRIGHT", m1, "BOTTOMRIGHT", -8, -8)
    pool:SetScript("OnMouseWheel", function(_, delta)
        DG.WheelScroll(pool, child, delta)
    end)
    BG.planScroll, BG.planChild = pool, child
    BG.planRows = {}
    for i = 1, N_PRESET + N_USER do
        local r = MakePlanRow(child)
        BG.planRows[i] = r
    end

    BG.statHead = MakeFS(m2, 16, C_WHITE, "LEFT")
    BG.statHead:SetPoint("TOPLEFT", m2, "TOPLEFT", x, -6)
    BG.statHead:SetText(L["属性汇总"])
    BG.statRows = {}
    for i, sr in ipairs(STAT_ROWS) do
        local ry = 30 + (i - 1) * 24
        local lab = MakeFS(m2, 14, C_GREY, "LEFT")
        lab:SetPoint("TOPLEFT", m2, "TOPLEFT", x + 4, -ry)
        lab:SetWordWrap(false)
        lab:SetText(sr[2])
        local val = MakeFS(m2, 14, C_GREEN, "RIGHT")
        val:SetPoint("TOPRIGHT", m2, "TOPRIGHT", -(x + 4), -ry)
        val:SetWordWrap(false)
    BG.statRows[i] = { sr[1], lab = lab, val = val }
end
BG.statParent = m2
end

local function BuildBrowser(parent, bottomLocal)
    local x, w = 8, 388
    BG.bwTitle = MakeFS(parent, 16, C_WHITE, "LEFT")
    BG.bwTitle:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -6)
    BG.bwTitle:SetWidth(w - 170)
    BG.bwTitle:SetWordWrap(false)
    BG.bwCount = MakeFS(parent, 14, C_GREY, "LEFT")
    BG.bwCount:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -28)
    BG.bwCount:SetWordWrap(false)
    BG.bwCount:SetWidth(w - 16)

    local sb = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    sb:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    sb:SetBackdropColor(0, 0, 0, 0.25)
    sb:SetBackdropBorderColor(1, 1, 1, 0.08)
    sb:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -6)
    sb:SetSize(150, 22)
    local eb = CreateFrame("EditBox", nil, sb)
    eb:SetAllPoints()
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(30)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local ph = MakeFS(sb, 12, C_DIM, "LEFT")
    ph:SetPoint("LEFT", sb, "LEFT", 8, 0)
    ph:SetText(L["搜索物品…"])
    eb:SetScript("OnTextChanged", function(self)
        BG.search = string.lower(self:GetText() or "")
        ph:SetShown(self:GetText() == "")
        BG.Render()
    end)

    BG.filterBtns = {}
    local fx = x
    for _, f in ipairs(FILTERS) do
        local bt = NewButton(parent, f.label, 52, 22, 12)
        bt:SetPoint("TOPLEFT", parent, "TOPLEFT", fx, -52)
        bt.lbl = bt:GetFontString()
        MakeOutline(bt, Unpack(C_GOLD))
        bt:SetScript("OnClick", function()
            BG.filter = f.id
            BG.Render()
        end)
        BG.filterBtns[f.id] = bt
        fx = fx + 56
    end

    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(w - 16 - 2 * LIST_PAD, 10)
    scroll:SetScrollChild(child)
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -82)
    scroll:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", -x, -(bottomLocal - 186))
    scroll:SetScript("OnMouseWheel", function(_, delta)
        DG.WheelScroll(scroll, child, delta)
    end)
    BG.bwScroll, BG.bwChild = scroll, child

    local ey = bottomLocal - 186
    BG.enchHead = MakeFS(parent, 16, C_WHITE, "LEFT")
    BG.enchHead:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -ey)
    BG.enchHead:SetText(L["附魔"])
    local escroll = CreateFrame("ScrollFrame", nil, parent)
    escroll:EnableMouseWheel(true)
    local echild = CreateFrame("Frame", nil, escroll)
    echild:SetSize(w - 16, 10)
    escroll:SetScrollChild(echild)
    escroll:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(ey + 26))
    escroll:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", -x, -(bottomLocal - 4))
    escroll:SetScript("OnMouseWheel", function(_, delta)
        DG.WheelScroll(escroll, echild, delta)
    end)
    BG.enchScroll, BG.enchChild = escroll, echild
    BG.enchRows = {}
    for i = 1, 6 do
        local r = CreateFrame("Button", nil, echild, BT)
        r:SetHeight(36)
        r:RegisterForClicks("LeftButtonUp")
        Cardify(r)
        r:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
        local hl = r:GetHighlightTexture()
        hl:SetColorTexture(1, 1, 1, 0.06)
        r.name = MakeFS(r, 14, C_TEXT, "LEFT")
        r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 8, -3)
        r.name:SetWordWrap(false)
        r.lvl = MakeFS(r, 11, C_GREY, "RIGHT")
        r.lvl:SetPoint("TOPRIGHT", r, "TOPRIGHT", -8, -4)
        r.lvl:SetWordWrap(false)
        r.note = MakeFS(r, 11, C_GREY, "LEFT")
        r.note:SetPoint("TOPLEFT", r, "TOPLEFT", 8, -19)
        r.note:SetWidth(360)
        r.note:SetWordWrap(false)
        MakeOutline(r, Unpack(C_GOLD))
        r:SetScript("OnEnter", function(self)
            if self.__ench and self.__ench.item then ItemTip(self, self.__ench.item) end
        end)
        r:SetScript("OnLeave", TipOff)
        r:SetScript("OnClick", function(self)
            local e = self.__ench
            if not e or not BG.sel then return end
            local dk = DataKey(SpecRec(), BG.sel)
            local tok = EnchToken(e)
            if CurEnch(SpecRec(), dk) == tok then
                BG.ench[dk] = nil
            else
                BG.ench[dk] = tok
            end
            BG.Render()
            ns.PlaySound(1)
        end)
        BG.enchRows[i] = r
    end

    BG.bwRows = {}
    for i = 1, 50 do
        local r = CreateFrame("Button", nil, child, BT)
        r:SetHeight(ROW_H)
        Cardify(r)
        r:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
        local hl = r:GetHighlightTexture()
        hl:SetColorTexture(1, 1, 1, 0.06)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(30, 30)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(r.icon) end
        r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
        r.name = MakeFS(r, 14, C_TEXT, "LEFT")
        r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 44, -5)
        r.name:SetWordWrap(false)
        r.src = MakeFS(r, 11, C_GREY, "LEFT")
        r.src:SetPoint("TOPLEFT", r, "TOPLEFT", 44, -22)
        r.src:SetWordWrap(false)
        r.eqTag = MakeFS(r, 11, C_GOLD, "LEFT")
        r.eqTag:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
        r.eqTag:SetWordWrap(false)
        r.eqTag:SetText(L["已装备"])
        r.eqTag:SetShown(false)
        r.ownTag = MakeFS(r, 11, C_GREEN, "LEFT")
        r.ownTag:SetPoint("LEFT", r.eqTag, "RIGHT", 6, 0)
        r.ownTag:SetWordWrap(false)
        r.ownTag:SetText(L["已收藏"])
        r.ownTag:SetShown(false)
        r.sideTag = MakeFS(r, 11, C_GREY, "RIGHT")
        r.sideTag:SetPoint("TOPRIGHT", r, "TOPRIGHT", -8, -22)
        r.sideTag:SetWordWrap(false)
        r:SetScript("OnEnter", function(self)
            local row = self.__row
            if not row then return end
            local st = SrcText(row.src)
            ItemTip(self, row.item, st ~= "" and { st } or nil)
        end)
        r:SetScript("OnLeave", TipOff)
        r:SetScript("OnClick", function(self)
            local row = self.__row
            if not row then return end
            if IsShiftKeyDown() then
                LinkToChat(row.item)
                return
            end
            BG.SetSlot(BG.sel, row.item)
            ns.PlaySound(1)
        end)
        r:EnableMouseWheel(true)
        r:SetScript("OnMouseWheel", function(_, delta)
            DG.WheelScroll(scroll, child, delta)
        end)
        BG.bwRows[i] = r
    end
end

function BG.Build(page)
    if BG.built or BG.building then return end
    BG.building = true
    ns.OpenPerf.Begin("BIS")
    ns.PhasedStart(8, coroutine.create(function()
    EnsureBIS()
    if not BG.vol then BG.vol = DefaultVol() end
    MigratePlans()
    coroutine.yield()
    -- ★ 页顶收窗沿 20（2026-10-10：顶部职业按钮排退役，原 y=13 顶栏 + py=45 让位）
    local py = 8
    BG.py = py
    BG.page = page
    coroutine.yield()
    BuildPanels(page)
    coroutine.yield()
    local dollTop = BuildSpecRow(BG.panels[1], 4)
    local dollBotLocal = BuildDoll(BG.panels[1], dollTop)
    -- ★ 底窗沿（用户定案 2026-10-11）：面板底边不再内容驱动（旧 = py+dollBotLocal+6，
    --   页底留一大截空）——一律钉在页底上方窗沿 20，与页顶 py=20 镜像，页高恒定。
    local pb = PAGE_INSET
    coroutine.yield()
    BuildMid(BG.panels[2], BG.panels[3])
    coroutine.yield()
    BuildBrowser(BG.panels[4], dollBotLocal + 6 - 8)
    coroutine.yield()

    BG.panels[1]:SetPoint("TOPLEFT", page, "TOPLEFT", PAGE_INSET, -py)
    BG.panels[1]:SetPoint("BOTTOMRIGHT", page, "BOTTOMLEFT", 312, pb)
    BG.panels[2]:SetPoint("TOPLEFT", page, "TOPLEFT", 320, -py)
    BG.panels[2]:SetPoint("BOTTOMRIGHT", page, "TOPLEFT", 544, -(py + 228))
    BG.panels[3]:SetPoint("TOPLEFT", page, "TOPLEFT", 320, -(py + 236))
    BG.panels[3]:SetPoint("BOTTOMRIGHT", page, "BOTTOMLEFT", 544, pb)
    BG.panels[4]:SetPoint("TOPLEFT", page, "TOPLEFT", 552, -py)
    BG.panels[4]:SetPoint("BOTTOMRIGHT", page, "BOTTOMLEFT", 948, pb)

    BG.built = true
    BG.building = false
    BG.needNames = true
    BG.ScheduleSweep()
    BG.Render()
    ns.OpenPerf.Mark("首绘")
    end))
end
