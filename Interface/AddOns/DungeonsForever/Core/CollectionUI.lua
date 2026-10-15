-- =============================================================================
-- DungeonsForever · 藏品页（坐骑 / 宠物）
-- 读取藏品数据表并渲染列表与详情（含 3D 模型展示、NPC 点击定位）；只对无限服加载。
-- =============================================================================

local _, ns = ...

if not ns.LoadForeverPages then return end

local format = string.format
local L = ns.L

local Host = ns.ProfHost
if not Host then return end

local DG = Host.DG
local MakeFS = Host.MakeFS
local NewButton = Host.NewButton
local MakeOutline = Host.MakeOutline
local SetOutline, Unpack = Host.SetOutline, Host.Unpack
local C_GOLD, C_GREY = Host.C_GOLD, Host.C_GREY
local C_DIM, C_WHITE, C_TEXT = Host.C_DIM, Host.C_WHITE, Host.C_TEXT
local C_GREEN = Host.C_GREEN
local FALLBACK_ICON = Host.FALLBACK_ICON
local PAGE_INSET = Host.PAGE_INSET

local MOUNTS = ns.CollectionMounts
if type(MOUNTS) ~= "table" or #MOUNTS == 0 then return end

local CG = {}
ns.CollectionModule = CG

local BT = BackdropTemplateMixin and "BackdropTemplate" or nil

local C_LINK = { 0.55, 0.78, 1.0 }
local C_ACCENT = { 0.27, 0.75, 0.45 }   -- 主题绿（与 46bf72 同系）

-- ── 子页（坐骑 / 宠物）───────────────────────────────────────────────────────
--
-- ★ 宠物列表 = **两张表合并**：探索页小动物（ns.ExplorePets，Data_ExplorePets.lua）
--   ∪ 藏品独有（ns.CollectionPets，Data_CollectionPets.lua，wowhead 宠物指南商城 4 只）。
--   ★★ 但**不许在文件顶层捕获**——两张表都可能晚于本文件赋值（懒构建顺序），
--      一律走 CG.Pets() 运行期取（内含按 item id 去重合并，探索页优先）。
--   字段（沿用探索页口径，顺序即索引）：
--     1 item  宠物物品 id（名字 / 图标按它问客户端）
--     2 slug  wowhead 图标名（仅兜底）
--     3 fac   "A" 联盟限定 / "H" 部落限定 / nil 双阵营
--     4 diff  "party" 组队 / "solo" 单人 / "easy" 简单 / "store" 商城（藏品独有）
--     5 area  AreaTable id（商城条目 false）；6/7 x/y 地图百分比（false = wowhead 没标）
--     8 src   来源短语；9 steps 步骤链；10 srcMarks（来源行可点击段，可选）
local SUB_MOUNT, SUB_PET = "mount", "pet"

local SUB_TABS = {
    { id = SUB_MOUNT, label = L["坐骑"] },
    { id = SUB_PET,   label = L["宠物"] },
}

function CG.Pets()
    -- 藏品页宠物 = 探索页小动物 ∪ 藏品独有（Data_CollectionPets）。
    -- 两张表都只能运行期取（懒构建顺序）；合并按 item id 去重，探索页优先。
    local seen, out = {}, {}
    local function add(t)
        if type(t) ~= "table" then return end
        for _, rec in ipairs(t) do
            local id = rec[1]
            if id and not seen[id] then
                seen[id] = true
                out[#out + 1] = rec
            end
        end
    end
    add(ns.ExplorePets)
    add(ns.CollectionPets)
    return out
end

-- 阵营 / 难度 文案与配色：与探索页共用（PET_FAC_* / PET_DIFF_*），
-- 两处必须一致，否则同一只宠物在两个页面显示不同颜色。
local PET_FAC_TXT = { A = L["联盟限定"], H = L["部落限定"] }
local PET_FAC_COL = { A = { 0.45, 0.68, 0.98 }, H = { 0.95, 0.5, 0.45 } }
local PET_FAC_DUAL = L["双阵营"]
local PET_FAC_DUAL_COL = { 0.66, 0.70, 0.78 }
local PET_DIFF_TXT = {
    party = L["难度·组队"], solo = L["难度·单人"], easy = L["难度·简单"],
    store = L["商城"],       -- 藏品独有（Data_CollectionPets）：不是难度，是来源
    unknown = L["待补充"],   -- 分类页批量收录、来源还没研究的条目
    vendor = L["商人"],      -- 商人出售（步骤里的 NPC 名可点击 → 世界地图定位）
    drop = L["掉落"],        -- 怪物掉落
    quest = L["任务"],       -- 任务奖励
    craft = L["制造"],       -- 专业制造（工程学等）
    pick = L["扒窃"],        -- 潜行者扒窃获取
}
local PET_DIFF_COL = {
    party = { 0.88, 0.42, 0.42 },
    solo  = { 0.38, 0.80, 0.50 },
    easy  = { 0.38, 0.80, 0.50 },
    store = { 0.95, 0.72, 0.35 },   -- 金色 = 商城（同 GROUP_COL.store）
    unknown = { 0.60, 0.63, 0.68 }, -- 灰 = 待补充（同 GROUP_COL.unknown）
    vendor = { 0.35, 0.78, 0.55 },  -- 绿 = 商人出售（同 GROUP_COL.rep）
    drop   = { 0.88, 0.42, 0.42 },  -- 红 = 怪物掉落（同 party）
    quest  = { 0.62, 0.55, 0.90 },  -- 紫 = 任务奖励（同 GROUP_COL.job）
    craft  = { 0.38, 0.80, 0.75 },  -- 青 = 专业制造
    pick   = { 0.80, 0.62, 0.40 },  -- 棕 = 扒窃获取
}

-- ── 分组 / 筛选 ──────────────────────────────────────────────────────────────

local GROUP_TXT = {
    job     = L["职业任务"],
    store   = L["商城"],
    legacy  = L["传承轨迹"],
    rep     = L["声望商人"],
    drop    = L["掉落"],
    unknown = L["待补充"],
}
local GROUP_COL = {
    job     = { 0.62, 0.55, 0.90 },
    store   = { 0.95, 0.72, 0.35 },
    legacy  = { 0.85, 0.62, 0.40 },
    rep     = { 0.35, 0.78, 0.55 },
    drop    = { 0.88, 0.42, 0.42 },
    unknown = { 0.60, 0.63, 0.68 },
}
local GROUP_ORDER = { "job", "store", "legacy", "rep", "drop", "unknown" }

local FILTERS = {
    { id = "all",   label = L["全部"] },
    { id = "job",   label = L["任务"] },
    { id = "rep",   label = L["声望"] },
    { id = "store", label = L["商城"] },
    { id = "drop",  label = L["掉落"] },
    { id = "other", label = L["其他"] },
}
local FILTER_MATCH = {
    all   = nil,
    job   = { job = true },
    rep   = { rep = true },
    store = { store = true },
    drop  = { drop = true },
    other = { legacy = true, unknown = true },
}

local LIST_W   = 330
local ROW_H    = 42
local SEC_H    = 24
local PAD      = 8
local MODEL_H  = 480   -- 2026-10-07 用户反馈：模型框加大加高（292 → 480，吃掉下方空白）

-- ── 数据取值 ─────────────────────────────────────────────────────────────────

local OVR = ns.NameOverrides

local function MountName(rec)
    if rec[2] == "spell" then
        local ok, nm = pcall(GetSpellInfo, rec[1])
        if ok and type(nm) == "string" and nm ~= "" then return nm, true end
        -- 无限服自定义法术客户端查不到 → 专用映射文件兜底（Data_NameOverrides）
        local o = OVR and OVR.spell and OVR.spell[rec[1]]
        if o then return o, true end
        return format(L["法术 #%d"], rec[1]), false
    end
    local nm, got = DG.ItemName(rec[1])
    if got then return nm, true end
    local o = OVR and OVR.item and OVR.item[rec[1]]
    if o then return o, true end
    return nm, false
end

local function MountIcon(rec)
    if rec[2] == "spell" then
        local ok, _, _, icon = pcall(GetSpellInfo, rec[1])
        if ok and (type(icon) == "string" or type(icon) == "number") then return icon end
    else
        local tex = DG.ItemIcon(rec[1])
        if type(tex) == "string" and tex ~= "" and tex ~= FALLBACK_ICON then return tex end
        if type(tex) == "number" then return tex end
    end
    if type(rec[3]) == "string" and rec[3] ~= "" then
        return "Interface\\Icons\\" .. rec[3]
    end
    return FALLBACK_ICON
end

-- ★ 坐骑与宠物是**两套字段结构**（见各数据文件表头），这里统一抽成同一组取值函数，
--   UI 侧不再到处判 CG.sub。宠物模型 displayId 已落盘（Data_ExplorePets /
--   Data_CollectionPets 的 __display，wowhead 各物品页「3D查看」的
--   data-mv-display-id，2026-10-07 真浏览器抓取）
--   ⇒ 详情走 3D 模型；个别未落盘的条目自动退化大图标，UI 无需改动。

local function RecName(rec, isPet)
    if isPet then
        local nm, got = DG.ItemName(rec[1])
        if got then return nm, true end
        local o = OVR and OVR.item and OVR.item[rec[1]]
        if o then return o, true end
        return nm, false
    end
    return MountName(rec)
end

local function RecIcon(rec, isPet)
    if isPet then
        local tex = DG.ItemIcon(rec[1])
        if type(tex) == "string" and tex ~= "" and tex ~= FALLBACK_ICON then return tex end
        if type(tex) == "number" then return tex end
        if type(rec[2]) == "string" and rec[2] ~= "" then
            return "Interface\\Icons\\" .. rec[2]
        end
        return FALLBACK_ICON
    end
    return MountIcon(rec)
end

-- 展示模型用的 displayId（宠物走 __display；未落盘的条目 nil ⇒ 大图标兜底）
local function RecDisplay(rec, isPet)
    if isPet then return tonumber(rec.__display or rec[11]) end
    return tonumber(rec[6])
end

-- 相机距离倍数（宠物数据暂无这一位，取 1）
local function RecCam(rec, isPet)
    if isPet then return tonumber(rec.__cam or rec[12]) or 1 end
    return tonumber(rec[7]) or 1
end

-- 当前子页的可见条目（宠物直接读探索页表；筛选/搜索都作用在这里）
local function CurrentList()
    if CG.sub == SUB_PET then
        local pets = CG.Pets() or {}
        local out = {}
        for _, rec in ipairs(pets) do out[#out + 1] = rec end
        return out
    end
    return MOUNTS
end

-- 列表标题已撤（页签已标明子页，数量由右侧「当前 N」承担）

-- 当前子页筛选芯片定义（坐骑看来源，宠物看阵营）
local function CurrentFilters()
    if CG.sub == SUB_PET then
        return {
            { id = "all", label = L["全部"] },
            { id = "A",   label = L["联盟"] },
            { id = "H",   label = L["部落"] },
            { id = "dual", label = L["双阵营"] },
        }
    end
    return FILTERS
end

local function AllNamesKnown()
    local isPet = CG.sub == SUB_PET
    for _, rec in ipairs(CurrentList()) do
        local _, got = RecName(rec, isPet)
        if not got then return false end
    end
    return true
end

local function ProbeNames()
    local isPet = CG.sub == SUB_PET
    local ok = true
    for _, rec in ipairs(CurrentList()) do
        local _, got = RecName(rec, isPet)
        if not got then
            ok = false
            if rec[2] ~= "spell" and DG.RequestItem then DG.RequestItem(rec[1]) end
        end
    end
    return ok
end

-- 当前子页的筛选 / 搜索都作用在这里（分组渲染见 Paint）
local function VisibleList()
    local match = FILTER_MATCH[CG.filter or "all"]
    local q = CG.search or ""
    local isPet = CG.sub == SUB_PET
    local out = {}
    for _, rec in ipairs(CurrentList()) do
        local pass = true
        if isPet then
            -- 宠物筛选口径：全部 / 联盟 / 部落 / 双阵营（fac 为 nil 即双阵营）
            if CG.filter == "A" then pass = (rec[3] == "A")
            elseif CG.filter == "H" then pass = (rec[3] == "H")
            elseif CG.filter == "dual" then pass = (rec[3] == nil)
            end
        else
            pass = (match == nil) or (match[rec[4]] == true)
        end
        if pass and q ~= "" then
            local nm = RecName(rec, isPet)
            local hay = string.lower(tostring(nm)) .. " " .. tostring(rec[1])
            pass = hay:find(q, 1, true) ~= nil
        end
        if pass then out[#out + 1] = rec end
    end
    return out
end

-- ── 骨架件 ───────────────────────────────────────────────────────────────────

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

local function TipOff()
    if GameTooltip then GameTooltip:Hide() end
end

-- ── 模型取景（本客户端唯一可用 API：SetCamDistanceScale，先例 MapUI.BossModelPose）──

-- 相机距离倍数：>1 拉远 = 模型变小。方法不存在（离线桩）就当无操作。
local function ApplyCam(m)
    if m and m.SetCamDistanceScale then
        pcall(m.SetCamDistanceScale, m, m.__cam or 1)
    end
end

-- 模型是否真加载出来（GetDisplayInfo 非 0）；桩上 pcall 兜底按未加载算。
local function ProbeLoaded(m)
    local ok, v = pcall(m.GetDisplayInfo, m)
    return (ok and type(v) == "number" and v ~= 0) or false
end

-- 提示行回显当前取景倍数（滚轮校准用：直观看到 x几，好据此定档）
function CG.SyncHint()
    local d = CG.detail
    if not d or not d.hintTxt then return end
    local cam = 1
    if d.model then cam = d.model.__cam or 1 end
    d.hintTxt:SetText(L["自动旋转 · 拖动旋转 · 滚轮缩放"] .. format(" · x%.1f", cam))
end

-- ★ 区域名 / 落图直接借探索页那套（EG.ZoneName / EG.MarkPoint）——
--   同一份 AREA_MAP 静态表、同一条「没坐标就只开地图」纪律，**不另起一份**，
--   否则两个页面会出现同一个区域显示不同名字 / 一个能落点一个不能。
function CG.ZoneName(areaID)
    local EG = ns.ExploreModule
    if EG and EG.ZoneName then
        return EG.ZoneName(areaID, format(L["区域 #%d"], areaID or 0))
    end
    return format(L["区域 #%d"], areaID or 0)
end

function CG.MarkPoint(areaID, x, y)
    local EG = ns.ExploreModule
    if EG and EG.MarkPoint then EG.MarkPoint(areaID, x, y) end
end

-- 宠物详情说明区：把 steps 链拼成带序号的整段文字。
--   ★ 只做「读」——步骤的可点击子串（m）留给探索页那张卡去处理，
--     藏品页这边提供跳转链接直达「获取详情」，不重复实现一套点击热点。
function CG.PetStepsText(rec)
    local steps = rec[9]
    local parts = {}
    if type(steps) == "table" then
        for si, st in ipairs(steps) do
            local t = (type(st) == "table" and st.t) or st
            if t and t ~= "" then
                parts[#parts + 1] = format("%d. %s", si, tostring(t))
            end
        end
    end
    if #parts == 0 then
        return tostring(rec[8] or "")
    end
    return table.concat(parts, "\n")
end

-- ── 宠物详情步骤：可点击段（NPC 定位）────────────────────────────────────
--   探索页小动物卡同款机制（PetSplit / PetSeg / PetFlow）：
--   步骤整句里 m 命中的子串渲染成可点击段 —— 点 NPC 名字直接把该 NPC 的
--   区域 + 坐标落到世界地图（复用 CG.MarkPoint → EG.MarkPoint）。
--   数据侧格式与探索页一致：steps[i] = { t = 整句, m = { { 子串, area, x, y }, … } }。
local C_STEP_LINK = { 0.55, 0.78, 1.0 }
local C_STEP_LINK_HI = { 1, 0.82, 0 }
local STEP_H = 18   -- 步骤行高（与 desc 字号 13 匹配）

local function StepTip(owner, on, label, area, x, y)
    if not GameTooltip then return end
    if not on then
        if GameTooltip.Hide then pcall(GameTooltip.Hide, GameTooltip) end
        return
    end
    -- 无坐标（x/y 非数字）= 只开区域地图 ⇒ 提示语同步，别让玩家以为会落点
    local has = type(x) == "number" and type(y) == "number"
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if GameTooltip.ClearLines then GameTooltip:ClearLines() end
    GameTooltip:AddLine(label or "", 1, 1, 1, false)
    local zone = CG.ZoneName(area, area or "?")
    GameTooltip:AddLine(has and format("%s %.1f, %.1f", zone, x, y) or zone, 0.7, 0.75, 0.82, false)
    GameTooltip:AddLine(has and L["点击在世界地图标记"] or L["点击打开该区域地图"], 0.55, 0.78, 1, false)
    if GameTooltip.Show then GameTooltip:Show() end
end

local function StepSplit(t, marks)
    local segs, pos = {}, 1
    for _, mk in ipairs(marks or {}) do
        local s = t:find(mk[1], pos, true)
        if s then
            if s > pos then segs[#segs + 1] = { t:sub(pos, s - 1) } end
            segs[#segs + 1] = { t:sub(s, s + #mk[1] - 1), mk }
            pos = s + #mk[1]
        end
    end
    if pos <= #t then segs[#segs + 1] = { t:sub(pos) } end
    return segs
end

local function StepSeg(d, k)
    local sg = d.segs[k]
    if sg then return sg end
    sg = CreateFrame("Button", nil, d.panel)
    sg:SetHeight(STEP_H)
    local fs = MakeFS(sg, 13, C_TEXT, "LEFT")
    sg:SetFontString(fs)
    sg.tx = fs
    sg:SetScript("OnEnter", function(self)
        local m = self.__mark
        if not m then return end
        self.tx:SetTextColor(Unpack(C_STEP_LINK_HI))
        StepTip(self, true, m[1], m[2], m[3], m[4])
    end)
    sg:SetScript("OnLeave", function(self)
        if self.__mark then self.tx:SetTextColor(Unpack(C_STEP_LINK)) end
        StepTip(self, false)
    end)
    sg:SetScript("OnClick", function(self)
        local m = self.__mark
        if m and type(m[2]) == "number" then CG.MarkPoint(m[2], m[3], m[4]) end
    end)
    sg:Hide()
    d.segs[k] = sg
    return sg
end

-- 流式排版步骤段（探索页 PetFlow 同款折行策略，简化版）
--   topY 为面板内 TOPLEFT 纵向偏移（负数），maxW 为可用宽度
local function PaintSteps(d, rec, topY, maxW)
    for _, sg in pairs(d.segs) do sg:Hide() end
    d.desc:Hide()
    local steps = rec[9]
    if type(steps) ~= "table" or #steps == 0 then
        -- 无步骤链：退回纯文本（沿用 rec[8] 来源短语）
        d.desc:Show()
        d.desc:SetText(tostring(rec[8] or ""))
        return
    end
    local k, x, y = 0, 0, topY
    for si, st in ipairs(steps) do
        local t = (type(st) == "table" and st.t) or st
        if t and t ~= "" then
            local marks = (type(st) == "table" and type(st.m) == "table") and st.m or nil
            local segs = StepSplit(format("%d. %s", si, tostring(t)), marks)
            for _, s in ipairs(segs) do
                k = k + 1
                local sg = StepSeg(d, k)
                local txt, m = s[1], s[2]
                sg.__mark = m
                sg.tx:SetWordWrap(false)
                sg.tx:SetText(txt)
                local w = sg.tx:GetStringWidth()
                if type(w) ~= "number" or w <= 0 then w = 7 * #txt end
                local rows = 1
                if w > maxW then
                    -- 长段折行：另起一行占满全宽，行数按实际宽度算
                    if x > 0 then x, y = 0, y - STEP_H end
                    w, rows = maxW, math.ceil(w / maxW)
                    sg.tx:SetWidth(w)
                    sg.tx:SetWordWrap(true)
                end
                sg:SetWidth(w + 1)
                sg:SetHeight(STEP_H * rows)
                sg.tx:ClearAllPoints()
                sg.tx:SetPoint("LEFT", sg, "LEFT", 0, 0)
                if x > 0 and x + w > maxW then x, y = 0, y - STEP_H end
                sg:ClearAllPoints()
                sg:SetPoint("TOPLEFT", d.panel, "TOPLEFT", PAD + x, y)
                if m then
                    sg:EnableMouse(true)
                    sg.tx:SetTextColor(Unpack(C_STEP_LINK))
                else
                    sg:EnableMouse(false)
                    sg.tx:SetTextColor(Unpack(C_TEXT))
                end
                sg:Show()
                x = x + w
                if rows > 1 then x, y = 0, y - STEP_H * (rows - 1) end
            end
        end
    end
end

-- ── 列表 ─────────────────────────────────────────────────────────────────────

local function PaintRow(r, rec)
    if not r then return end
    if rec then
        r:Show()
        r.__rec = rec
        r.__pet = (CG.sub == SUB_PET) or nil
        r.icon:SetTexture(RecIcon(rec, r.__pet))
        local nm = RecName(rec, r.__pet)
        r.name:SetText(nm)
        if r.__pet then
            -- 宠物行：副行 = 阵营 · 难度（沿用探索页文案与配色）
            local fac, diff = rec[3], rec[4]
            local ftxt = fac and PET_FAC_TXT[fac] or PET_FAC_DUAL
            local fcol = (fac and PET_FAC_COL[fac]) or PET_FAC_DUAL_COL
            local dk = PET_DIFF_TXT[diff] and diff or "easy"   -- store 等新键直过，未知回 easy
            r.src:SetText(format("%s · %s", ftxt, PET_DIFF_TXT[dk]))
            r.src:SetTextColor(Unpack(fcol))
        else
            local g = rec[4]
            r.src:SetText(GROUP_TXT[g] or g)
            r.src:SetTextColor(Unpack(GROUP_COL[g] or C_GREY))
        end
        SetOutline(r, CG.sel == rec, Unpack(C_ACCENT))
    else
        r.__rec = nil
        r.__pet = nil
        r:Hide()
    end
end

    -- 收起坐骑说明可点击段（宠物分支 / 空态 / 无数据条目共用）
    local function HideSrcRow(d)
        for _, sg in ipairs(d.srcSegs or {}) do sg:Hide() end
    end

    -- 坐骑说明可点击段排版（PaintSteps 同款流式折行；段池复用 srcSegs）
    --   segs = StepSplit 产物：s[1] = 文本，s[2] = { 名字, npcID }（纯文本段无 s[2]）
    local function PaintMountSegs(d, segs, topY)
        local maxW = d.panel:GetWidth() - 2 * PAD
        local x, y = 0, topY
        for k, s in ipairs(segs) do
            local sg = d.srcSegs[k]
            if not sg then break end
            -- s[2] 是 mark 表 { 名字, npcID }；__npcID 只要数字 id（纯文本段为 nil）
            sg.__npcID = s[2] and s[2][2] or nil
            local t = s[1]
            sg.tx:SetText(t)
            local w = sg.tx:GetStringWidth()
            if type(w) ~= "number" or w <= 0 then w = 7 * #t end
            if x > 0 and x + w > maxW then x, y = 0, y - STEP_H end
            sg:SetWidth(w + 2)
            sg:ClearAllPoints()
            sg:SetPoint("TOPLEFT", d.panel, "TOPLEFT", PAD + x, y)
            sg.tx:SetTextColor(Unpack(sg.__npcID and C_STEP_LINK or C_TEXT))
            sg:EnableMouse(sg.__npcID ~= nil)
            sg:Show()
            x = x + w
        end
        for k = #segs + 1, #d.srcSegs do d.srcSegs[k]:Hide() end
    end

local function PaintDetail()
    local rec = CG.sel
    local d = CG.detail
    if not d then return end
    if not rec then
        d.empty:SetShown(true)
        d.model:Hide()
        d.modelIcon:Hide()
        d.name:SetText("")
        d.pill:Hide()
        d.desc:SetText("")
        HideSrcRow(d)
        for _, sg in pairs(d.segs) do sg:Hide() end   -- 宠物步骤段残留同样要收
        return
    end
    d.empty:SetShown(false)

    -- 模型视口：display 有效且 API 可用 → PlayerModel；否则大图标占位
    local isPetSub = CG.sub == SUB_PET
    local disp = RecDisplay(rec, isPetSub)
    local useModel = disp ~= nil and disp > 0
        and type(d.model.SetDisplayInfo) == "function"
    d.modelIcon:SetShown(not useModel)
    if useModel then
        local m = d.model
        m.__auto = true
        m.__rot = m.__rot or 0
        m.__cam = RecCam(rec, isPetSub)        -- 相机距离倍数（>1 拉远 = 变小）
        m.__loaded = false
        m.__token = (m.__token or 0) + 1       -- 选中令牌：错帧补设时校验，别落到新选中上
        local tok = m.__token
        -- ★ Show 先行、Set 在后（MapUI 2026-10-06 实机：从未 Show 过的帧上首次 Set 可能不生效）
        m:SetAlpha(0)                          -- 加载期不可见（避免闪一帧巨大模型）
        m:Show()
        pcall(m.SetDisplayInfo, m, disp)
        ApplyCam(m)
        if C_Timer and C_Timer.After then
            -- ★ 错帧补设：加载完成会重置取景（MapUI 同源教训），每次补设 + 探测显形
            for _, t in ipairs({ 0.2, 0.5, 1.0, 2.0 }) do
                C_Timer.After(t, function()
                    if m.__token ~= tok or not m:IsShown() then return end
                    ApplyCam(m)
                    if not m.__loaded and ProbeLoaded(m) then
                        m.__loaded = true
                        m:SetAlpha(1)
                    end
                end)
            end
            C_Timer.After(2.6, function()          -- 兜底：探不出来也别一直隐形
                if m.__token == tok and m:IsShown() then m:SetAlpha(1) end
            end)
        else
            m:SetAlpha(1)
        end
    else
        d.model:Hide()
        d.modelIcon:SetTexture(RecIcon(rec, CG.sub == SUB_PET))
    end

    local isPet = CG.sub == SUB_PET
    if isPet then
        -- 宠物详情：名称 + 阵营/难度双胶囊 + 区域坐标芯片 + 步骤链 + 跳转链接
        local fac, diff = rec[3], rec[4]
        local ftxt = fac and PET_FAC_TXT[fac] or PET_FAC_DUAL
        local fcol = (fac and PET_FAC_COL[fac]) or PET_FAC_DUAL_COL
        d.name:SetText(RecName(rec, true))
        d.pillTxt:SetText(ftxt)
        d.pillTxt:SetTextColor(Unpack(fcol))
        d.pill:Show()
        -- 第二个胶囊：难度（复用同一个 pill 帧的兄弟，见 BuildDetailPanel）
        local dk = PET_DIFF_TXT[diff] and diff or "easy"   -- store/vendor 等新键直过，未知回 easy
        if d.pill2 then
            d.pill2Txt:SetText(PET_DIFF_TXT[dk])
            d.pill2Txt:SetTextColor(Unpack(PET_DIFF_COL[dk]))
            d.pill2:Show()
        end
        -- 区域 + 坐标芯片（有真实坐标才显示芯片；false = wowhead 没标）
        local area, px, py = rec[5], rec[6], rec[7]
        local zone = CG.ZoneName(area)
        local hasMain = type(px) == "number" and type(py) == "number"
        if d.locChip then
            d.locChip:SetShown(hasMain)
            d.locChipTx:SetText(hasMain and format("%.1f, %.1f", px, py) or "")
            d.locChip.__area, d.locChip.__x, d.locChip.__y = area, px, py
            d.locChip.__label = zone
        end
        if d.zoneTx then
            -- ★ 商城等藏品独有条目 area=false：区域行整行隐藏（原来恒显示，空文案还留着点击区）
            local hasArea = type(area) == "number"
            d.zoneTx:SetShown(hasArea)
            if hasArea then
                d.zoneTx:SetText(zone)
                d.zoneTx.__area, d.zoneTx.__x, d.zoneTx.__y = area, px, py
                d.zoneTx.__label = zone
            end
        end
        if d.zoneHit then d.zoneHit:SetShown(type(area) == "number") end
        -- 宠物说明下移一行（+66）：给「查看获取详情 | 区域名 | 坐标」链接行让位
        d.desc:ClearAllPoints()
        d.desc:SetPoint("TOPLEFT", d.panel, "TOPLEFT", PAD, -(8 + MODEL_H + 70))
        d.desc:SetPoint("TOPRIGHT", d.panel, "TOPRIGHT", -PAD, -(8 + MODEL_H + 70))
        -- ★ 步骤走可点击段渲染（m 命中的 NPC 名字 → 点击在世界地图落航点）；
        --   无步骤链时自动退回纯文本（rec[8] 来源短语），见 PaintSteps
        PaintSteps(d, rec, -(8 + MODEL_H + 70), d.panel:GetWidth() - 2 * PAD)
        -- 跳转链接只对探索页小动物显示：藏品独有宠物（商城等）在探索页没有详情卡
        local inExplore = false
        if type(ns.ExplorePets) == "table" then
            for _, p in ipairs(ns.ExplorePets) do
                if p[1] == rec[1] then inExplore = true break end
            end
        end
        if d.gotoBtn then d.gotoBtn:SetShown(inExplore) end
        HideSrcRow(d)   -- 坐骑来源 NPC 行是坐骑分支专属，切到宠物必须藏
    else
        d.name:SetText(MountName(rec))
        local g = rec[4]
        local c = GROUP_COL[g] or C_GREY
        d.pillTxt:SetText(GROUP_TXT[g] or g)
        d.pillTxt:SetTextColor(Unpack(c))
        d.pill:Show()
        if d.pill2 then d.pill2:Hide() end
        if d.locChip then d.locChip:Hide() end
        if d.zoneTx then d.zoneTx:Hide() end
        if d.zoneHit then d.zoneHit:Hide() end
        for _, sg in pairs(d.segs) do sg:Hide() end   -- 宠物分支的步骤段帧不收会叠在说明上
        -- ★ 说明文本里的 NPC 名字直接可点击（2026-10-08 用户反馈：删「来源：」独立行，
        --   与「商人：…」重复）。有 npcs 且名字出现在文本里 → 说明走可点击段排版，
        --   名字段点击 → DG.MarkNPC 落图；否则纯文本 desc。
        local txt = tostring(rec[5] or "")
        local segs = nil
        local npcs = type(rec.npcs) == "table" and rec.npcs or nil
        if npcs and #npcs > 0 and txt ~= "" then
            local marks = {}
            for _, np in ipairs(npcs) do
                local nm = tostring(np[2] or "")
                if nm ~= "" then
                    local p1 = txt:find(nm, 1, true)
                    if p1 then marks[#marks + 1] = { p1, nm, np[1] } end
                end
            end
            table.sort(marks, function(a, b) return a[1] < b[1] end)   -- 按出现序，StepSplit 要求顺序匹配
            for i, mk in ipairs(marks) do marks[i] = { mk[2], mk[3] } end
            if #marks > 0 then
                segs = StepSplit(txt, marks)
                if #segs > #d.srcSegs then segs = nil end   -- 段池不够 → 退纯文本
            end
        end
        d.desc:ClearAllPoints()
        d.desc:SetPoint("TOPLEFT", d.panel, "TOPLEFT", PAD, -(8 + MODEL_H + 42))
        d.desc:SetPoint("TOPRIGHT", d.panel, "TOPRIGHT", -PAD, -(8 + MODEL_H + 42))
        if segs then
            d.desc:Hide()
            PaintMountSegs(d, segs, -(8 + MODEL_H + 42))
        else
            HideSrcRow(d)
            d.desc:Show()
            d.desc:SetText(txt)
        end
        if d.gotoBtn then d.gotoBtn:Hide() end
    end
    CG.SyncHint()
end

local function PY()
    if coroutine.running and coroutine.running() then coroutine.yield() end
end

local function Paint()
    if not CG.built then return end
    local list = VisibleList()

    -- 无有效选中 → 落到列表第一个（筛选后仍保证右侧有内容）
    local selOK = false
    for _, rec in ipairs(list) do
        if rec == CG.sel then selOK = true break end
    end
    if not selOK then CG.sel = list[1] end

    -- 分组：坐骑按获取方式，宠物按阵营（A / H / nil=双阵营）
    local isPet = CG.sub == SUB_PET
    local byG, order = {}, {}
    if isPet then
        for _, rec in ipairs(list) do
            local g = rec[3] or "dual"
            if not byG[g] then byG[g] = {}; order[#order + 1] = g end
            byG[g][#byG[g] + 1] = rec
        end
    else
        for _, rec in ipairs(list) do
            local g = rec[4]
            byG[g] = byG[g] or {}
            byG[g][#byG[g] + 1] = rec
        end
        order = GROUP_ORDER
    end

    local function SecLabel(g, n)
        if isPet then
            local t = (g == "A" and L["联盟限定"]) or (g == "H" and L["部落限定"]) or L["双阵营"]
            return format("%s · %d", t, n)
        end
        return format("%s · %d", GROUP_TXT[g] or g, n)
    end

    local y = 0
    local ri, si = 0, 0
    for _, g in ipairs(order) do
        local arr = byG[g]
        if arr then
            si = si + 1
            if si > 1 then y = y - 8 end   -- 组↔组间距 8（首组贴顶不加）
            local hd = CG.secs[si]
            if hd then
                hd:ClearAllPoints()
                hd:SetPoint("TOPLEFT", CG.listChild, "TOPLEFT", 0, y)
                hd.txt:SetText(SecLabel(g, #arr))
                hd:Show()
            end
            y = y - SEC_H
            for _, rec in ipairs(arr) do
                ri = ri + 1
                local r = CG.rows[ri]
                PaintRow(r, rec)
                if r then
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", CG.listChild, "TOPLEFT", 0, y)
                    r:SetPoint("RIGHT", CG.listChild, "RIGHT", 0, 0)   -- 双锚点撑宽（BisUI 同款）
                end
                y = y - (ROW_H + 8)   -- 行卡↔行卡缝 8
                if ri % 8 == 0 then PY() end
            end
        end
    end
    for i = si + 1, #CG.secs do CG.secs[i]:Hide() end
    for i = ri + 1, #CG.rows do
        local r = CG.rows[i]
        if r.__rec ~= nil then r.__rec = nil r:Hide() end
    end
    CG.listChild:SetHeight(-y)

    -- ★ 滚动位置治理（2026-10-08 用户反馈：坐骑滚到底切宠物，短列表露大片空白）
    --   子页切换 → 回顶；同页内容变短（筛选/搜索）→ 收敛到新范围。
    if CG.lastListSub ~= CG.sub then
        CG.lastListSub = CG.sub
        CG.listScroll:SetVerticalScroll(0)
    else
        local maxS = math.max(0, CG.listChild:GetHeight() - CG.listScroll:GetHeight())
        if CG.listScroll:GetVerticalScroll() > maxS then
            CG.listScroll:SetVerticalScroll(maxS)
        end
    end
    if CG.UpdateListScroll then CG.UpdateListScroll() end

    -- 子页签选中态（每次 Paint 刷，点切后立即更新描边）
    if CG.subBtns then
        for id, bt in pairs(CG.subBtns) do
            SetOutline(bt, id == CG.sub, Unpack(C_ACCENT))
        end
    end
    if CG.count then
        if CG.sub == SUB_PET then
            CG.count:SetText(format(L["当前 %d 只"], #list))
        else
            CG.count:SetText(format(L["当前 %d 匹"], #list))
        end
    end
    PaintDetail()
end

local function SweepNames()
    if not (C_Timer and C_Timer.After) then return end
    for _, d in ipairs({ 0.5, 2, 5 }) do
        C_Timer.After(d, function()
            if CG.built and CG.needNames and CG.page and CG.page:IsShown() then
                CG.needNames = not ProbeNames()
                CG.Render()
            end
        end)
    end
end

function CG.OnItemData(itemID)
    if not (CG.built and CG.needNames and CG.page and CG.page:IsShown()) then return end
    if not itemID or CG._itemRepaint then return end
    CG._itemRepaint = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, function()
            CG._itemRepaint = false
            if CG.built and CG.needNames and CG.page and CG.page:IsShown() then
                CG.needNames = not ProbeNames()
                CG.Render()
            end
        end)
    else
        CG._itemRepaint = false
    end
end

-- ── 构建 ─────────────────────────────────────────────────────────────────────

local function BuildListPanel(page)
    local p = CreateFrame("Frame", nil, page, BT)
    if ns.hui and ns.hui.BuildRoundedBG then
        ns.hui.BuildRoundedBG(p, 8, ns.hui.layer.L1, "both", true, 1)   -- 容器卡=L1（主窗 L0 之上一层）
    else
        Cardify(p, 0.05, 0.12)
    end
    -- ★ 顶边 -8（窗沿 20 = PAGE_INSET 12 + GUTTER 8：页级卡片距页缘一律 8，四边对齐）
    p:SetPoint("TOPLEFT", page, "TOPLEFT", PAGE_INSET, -8)
    -- ★ 底边必须锚 page 的 BOTTOMLEFT（此前误锚 TOPLEFT ⇒ 面板只剩 33px 高，
    --   ScrollFrame 高度算成负值把整个列表裁没了 —— 2026-10-07 实机截图定位）
    p:SetPoint("BOTTOMRIGHT", page, "BOTTOMLEFT", PAGE_INSET + LIST_W, PAGE_INSET)   -- ★ BOTTOM 系锚点 y 正值才是往上（负值会伸出页外）

    CG.count = MakeFS(p, 12, C_DIM, "RIGHT")
    CG.count:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, -8)

    -- ★ 子页签（坐骑 | 宠物）钉在**列表面板标题行**：用户 2026-10-07 实机指定位置
    --   （那个红框就在标题「坐骑」右边）。右侧详情面板不加任何页签。
    CG.subBtns = {}
    local sx = PAD
    for _, t in ipairs(SUB_TABS) do
        local bt = NewButton(p, t.label, 52, 20, 12)
        bt:SetPoint("TOPLEFT", p, "TOPLEFT", sx, -8)   -- 顶与标题同高对齐
        bt.lbl = bt:GetFontString()
        MakeOutline(bt, Unpack(C_ACCENT))
        bt:SetScript("OnClick", function()
            if CG.sub ~= t.id then
                CG.sub = t.id
                CG.filter = "all"
                CG.search = ""
                if CG.searchBox then CG.searchBox:SetText("") end
                CG.PaintFilters()
                CG.Render()
                CG.needNames = not ProbeNames()
                SweepNames()
                ns.PlaySound(1)
            end
        end)
        SetOutline(bt, t.id == "mount", Unpack(C_ACCENT))
        CG.subBtns[t.id] = bt
        sx = sx + 60   -- 宽 52 + 缝 8
    end

    -- 搜索框
    local sb = CreateFrame("Frame", nil, p, "BackdropTemplate")
    -- ③ 搜索框：L2 圆角 + DIV 细描边（替代旧黑 25% 直角；列表面板已定 L1 ⇒ 内件提亮一档）
    if ns.hui and ns.hui.BuildRoundedBG then
        ns.hui.BuildRoundedBG(sb, 5, ns.hui.layer.L2, "both", true, 1)
    else
        sb:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        sb:SetBackdropColor(0, 0, 0, 0.25)
        sb:SetBackdropBorderColor(1, 1, 1, 0.08)
    end
    -- ★ 顶 -36：页签行底 28 + 缝 8；筛选/滚动区依次随动，各保持缝 8
    sb:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -36)
    sb:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, -36)
    sb:SetHeight(22)
    local eb = CreateFrame("EditBox", nil, sb)
    eb:SetAllPoints()
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(30)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local ph = MakeFS(sb, 12, C_DIM, "LEFT")
    ph:SetPoint("LEFT", sb, "LEFT", 8, 0)
    eb:SetScript("OnTextChanged", function(self)
        CG.search = string.lower(self:GetText() or "")
        ph:SetShown(self:GetText() == "")
        CG.Render()
    end)
    CG.searchBox, CG.searchPH = eb, ph

    -- 筛选芯片（一次建满：坐骑 6 枚 / 宠物 4 枚，取多者；按当前子页显隐 + 改文案）
    --   58→50 / 62→54：2026-10-08 坐骑侧加「掉落」芯片后 6 枚才放得下（面板 330）
    --   宽 50→45 / 步距 54→53：缝 4→8（6×45+5×8=310 ≤ 内容宽 314，仍放得下 6 枚）
    CG.filterBtns = {}
    for i = 1, #FILTERS do
        local bt = NewButton(p, "", 45, 22, 12)
        bt:SetPoint("TOPLEFT", p, "TOPLEFT", PAD + (i - 1) * 53, -66)
        bt.lbl = bt:GetFontString()
        MakeOutline(bt, Unpack(C_ACCENT))
        bt:SetScript("OnClick", function()
            CG.filter = bt.__id
            CG.Render()
            ns.PlaySound(1)
        end)
        CG.filterBtns[i] = bt
    end
    coroutine.yield()

    -- 按子页刷新芯片文案与显隐 / 搜索占位符
    function CG.PaintFilters()
        local list = CurrentFilters()
        for i, bt in ipairs(CG.filterBtns) do
            local f = list[i]
            if f then
                bt.__id = f.id
                bt:SetText(f.label)
                bt:Show()
            else
                bt.__id = nil
                bt:Hide()
            end
        end
        if CG.searchPH then
            CG.searchPH:SetText(CG.sub == SUB_PET and L["搜索宠物…"] or L["搜索坐骑…"])
            CG.searchPH:SetShown((CG.searchBox and CG.searchBox:GetText() or "") == "")
        end
    end

    -- 滚动列表 + 行池
    local scroll = CreateFrame("ScrollFrame", nil, p)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(LIST_W - 2 * PAD, 10)
    scroll:SetScrollChild(child)
    scroll:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -96)   -- 筛选行底 88 + 缝 8
    scroll:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -PAD, PAD)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        DG.WheelScroll(scroll, child, delta)
    end)
    CG.listScroll, CG.listChild = scroll, child

    -- ── 滚动条（2026-10-08 用户反馈：红框位置要滚动条）──
    --   轨道贴列表右缘 PAD 沟槽内，滑块可拖拽；内容不足一屏时整条隐藏。
    local track = CreateFrame("Frame", nil, p, "BackdropTemplate")
    -- ④ 滚动条轨道：L2 圆角胶囊（替代旧黑 25% 直角；列表面板已定 L1 ⇒ 内件提亮一档）
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
    track:SetPoint("TOPRIGHT", p, "TOPRIGHT", -1, -96)
    track:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -1, PAD)
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(4)
    thumb:EnableMouse(true)
    -- ④ 滑块：L4 圆角胶囊，悬停提亮到 L5（替代旧白 30%/45% 直角块）
    local tp = nil
    local tx = nil
    if ns.hui and ns.hui.BuildCapsule then
        tp = ns.hui.BuildCapsule(thumb, 2, ns.hui.layer.L4)
    else
        tx = thumb:CreateTexture(nil, "OVERLAY")
        tx:SetAllPoints()
        tx:SetColorTexture(1, 1, 1, 0.30)
    end
    thumb:SetScript("OnEnter", function()
        if tp then
            local L5 = ns.hui.layer.L5
            for _, t in ipairs(tp) do t:SetVertexColor(L5[1], L5[2], L5[3]) end
        elseif tx then
            tx:SetColorTexture(1, 1, 1, 0.45)
        end
    end)
    thumb:SetScript("OnLeave", function()
        if tp then
            local L4 = ns.hui.layer.L4
            for _, t in ipairs(tp) do t:SetVertexColor(L4[1], L4[2], L4[3]) end
        elseif tx then
            tx:SetColorTexture(1, 1, 1, 0.30)
        end
    end)
    thumb:SetPoint("TOP", track, "TOP", 0, -1)

    -- 依滚动状态刷新滑块位置 / 高度（OnVerticalScroll 与 Paint 都会调）
    function CG.UpdateListScroll()
        local viewH = scroll:GetHeight()
        local contentH = child:GetHeight()
        if contentH <= viewH + 2 then track:Hide() return end
        track:Show()
        local trackH = track:GetHeight() - 2
        local maxScroll = contentH - viewH
        local frac = math.min(1, math.max(0, scroll:GetVerticalScroll() / maxScroll))
        local th = math.max(24, trackH * viewH / contentH)
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -1 - frac * (trackH - th))
    end
    scroll:SetScript("OnVerticalScroll", function() CG.UpdateListScroll() end)

    -- 滑块拖拽：光标位移按比例映射到滚动值
    thumb:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        local scale = UIParent and UIParent:GetEffectiveScale() or 1
        local cy0 = select(2, GetCursorPosition()) / scale
        local sc0 = scroll:GetVerticalScroll()
        self:SetScript("OnUpdate", function(self)
            local cy = select(2, GetCursorPosition()) / scale
            local trackH = track:GetHeight() - 2
            local span = trackH - thumb:GetHeight()
            if span <= 0 then return end
            local maxScroll = child:GetHeight() - scroll:GetHeight()
            scroll:SetVerticalScroll(math.min(maxScroll, math.max(0, sc0 + (cy0 - cy) / span * maxScroll)))
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    thumb:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    coroutine.yield()

    CG.secs = {}
    for i = 1, #GROUP_ORDER do
        local hd = CreateFrame("Frame", nil, child)
        hd:SetHeight(SEC_H)
        hd:SetWidth(LIST_W - 2 * PAD)
        hd.txt = MakeFS(hd, 12, C_DIM, "LEFT")
        hd.txt:SetPoint("LEFT", hd, "LEFT", 2, 0)
        hd:Hide()
        CG.secs[i] = hd
    end
    coroutine.yield()

    CG.rows = {}
    -- ★ 行池按**两个子页里条目多的那个**建满（坐骑 N vs 宠物 M 取大者）：
    --   切子页只改显隐与内容，绝不新建帧（页骨架一次建好的纪律）。
    local maxRows = #MOUNTS
    do
        local pets = CG.Pets()
        if type(pets) == "table" and #pets > maxRows then maxRows = #pets end
    end
    for i = 1, maxRows do
        local r = CreateFrame("Button", nil, child, BT)
        r:SetHeight(ROW_H)
        r:SetWidth(LIST_W - 2 * PAD)   -- 行宽必须显式给（BisUI/探索页同口径）
        -- ① 行卡：L2 圆角 r6 + 细描边（替代旧白 3.5% 直角 Cardify；列表面板 L1 ⇒ 内卡提亮一档）
        if ns.hui and ns.hui.BuildRoundedBG then
            ns.hui.BuildRoundedBG(r, 6, ns.hui.layer.L2, "both", true, 1)
        else
            Cardify(r)
        end
        -- ② 悬停高亮：L4 圆角胶囊（底色 +2 档）、内缩 1px 露出行卡描边（替代旧白 6% 直角 highlight）
        --   胶囊片建在行卡之后、图标/文字之前 ⇒ 绘制序天然「盖底不盖字」
        r.__hover = nil
        if ns.hui and ns.hui.BuildCapsule then
            local hp = ns.hui.BuildCapsule(r, 12, ns.hui.layer.L4, 1, 2)
            for _, t in ipairs(hp) do t:Hide() end
            r.__hover = hp
        else
            r:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
            local hl = r:GetHighlightTexture()
            hl:SetColorTexture(1, 1, 1, 0.06)
        end
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(30, 30)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(r.icon) end
        r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
        r.name = MakeFS(r, 14, C_TEXT, "LEFT")
        r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 44, -4)
        r.name:SetWidth(LIST_W - 2 * PAD - 44 - 4)
        r.name:SetWordWrap(false)
        r.src = MakeFS(r, 11, C_GREY, "LEFT")
        r.src:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 44, 5)
        r.src:SetWordWrap(false)
        MakeOutline(r, Unpack(C_ACCENT))
        r:SetScript("OnEnter", function(self)
            if self.__hover then
                for _, t in ipairs(self.__hover) do t:Show() end
            end
            -- 悬停物品 tooltip：坐骑/宠物条目的第 1 位都是物品 id
            local rec = self.__rec
            if rec then DG.ShowItemTip(self, { rec[1] }) end
        end)
        r:SetScript("OnLeave", function()
            if r.__hover then
                for _, t in ipairs(r.__hover) do t:Hide() end
            end
            TipOff()
        end)
        r:SetScript("OnClick", function(self)
            if self.__rec then
                CG.sel = self.__rec
                CG.Render()
                ns.PlaySound(1)
            end
        end)
        r:Hide()
        CG.rows[i] = r
        if i % 14 == 0 then coroutine.yield() end
    end
end

local function BuildDetailPanel(page)
    local p = CreateFrame("Frame", nil, page, BT)
    if ns.hui and ns.hui.BuildRoundedBG then
        ns.hui.BuildRoundedBG(p, 8, ns.hui.layer.L1, "both", true, 1)   -- 容器卡=L1（主窗 L0 之上一层）
    else
        Cardify(p, 0.05, 0.12)
    end
    p:SetPoint("TOPLEFT", page, "TOPLEFT", PAGE_INSET + LIST_W + 8, -8)
    p:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -PAGE_INSET, PAGE_INSET)

    -- 模型视口
    local vp = CreateFrame("Frame", nil, p, "BackdropTemplate")
    -- ⑤ L0 下沉圆角 + DIV 细边（替代旧黑 30% 直角）
    if ns.hui and ns.hui.BuildRoundedBG then
        ns.hui.BuildRoundedBG(vp, 6, ns.hui.layer.L0, "both", true, 1)
    else
        vp:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        vp:SetBackdropColor(0, 0, 0, 0.30)
        vp:SetBackdropBorderColor(1, 1, 1, 0.10)
    end
    vp:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -8)
    vp:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, -8)
    vp:SetHeight(MODEL_H)

    -- 操作提示 + 取景读数（读数用于校准「多大才是合适」；模型是 vp+2 层，
    --   提示要压过它 ⇒ 单开一层帧托管，否则被模型盖住看不见）
    local hintBox = CreateFrame("Frame", nil, vp)
    hintBox:SetSize(1, 1)
    hintBox:SetPoint("BOTTOM", vp, "BOTTOM", 0, 6)
    hintBox:SetFrameLevel(vp:GetFrameLevel() + 4)
    local hint = MakeFS(hintBox, 11, C_DIM, "CENTER")
    hint:SetPoint("BOTTOM", hintBox, "BOTTOM", 0, 0)
    hint:SetText(L["自动旋转 · 拖动旋转 · 滚轮缩放"])

    -- 大图标兜底（display 无效 / API 缺失时显示）
    local modelIcon = vp:CreateTexture(nil, "ARTWORK")
    modelIcon:SetSize(120, 120)
    modelIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(modelIcon) end
    modelIcon:SetPoint("CENTER", vp, "CENTER", 0, 14)
    modelIcon:Hide()

    -- 3D 模型
    --   自动旋转（展示台）+ 左键拖动旋转 + 滚轮缩放，全部收敛进一个 OnUpdate：
    --   零常驻新帧；模型隐藏时 OnUpdate 不跑（WoW 引擎语义），无空转成本。
    local model = CreateFrame("PlayerModel", nil, vp)
    model:SetAllPoints(vp)
    model:SetFrameLevel(vp:GetFrameLevel() + 2)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    model:RegisterForDrag("LeftButton")
    model:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then self.__auto = false end   -- 手动接管，暂停自转
    end)
    model:SetScript("OnDragStart", function(self)
        self.__drag = true
        self.__dragX = nil
    end)
    model:SetScript("OnDragStop", function(self)
        self.__drag = nil
        self.__dragX = nil
    end)
    model:SetScript("OnHide", function(self)
        self.__drag = nil
        self.__dragX = nil
    end)
    model:SetScript("OnMouseWheel", function(self, delta)
        -- 滚轮上 = 拉近（模型变大）= 相机倍数变小；范围放宽到 0.2~40，
        -- 给「无相机巨模型」留足拉远空间（校准读数在底部提示行回显）
        self.__cam = self.__cam or 1
        self.__cam = self.__cam * (delta > 0 and (1 / 1.3) or 1.3)
        if self.__cam < 0.2 then self.__cam = 0.2 end
        if self.__cam > 40 then self.__cam = 40 end
        ApplyCam(self)
        CG.SyncHint()
    end)
    model:SetScript("OnUpdate", function(self, dt)
        local uiScale = UIParent and UIParent:GetEffectiveScale() or 1
        local rotating = false
        if self.__drag then
            local mx = select(1, GetCursorPosition())
            if mx then mx = mx / uiScale end
            if self.__dragX and mx then
                local dx = mx - self.__dragX
                if dx ~= 0 then
                    self.__rot = (self.__rot or 0) + dx * 0.02
                end
            end
            if mx then self.__dragX = mx end
            rotating = true
        elseif self.__auto then
            self.__rot = (self.__rot or 0) + dt * 0.7
            rotating = true
        end
        -- ★ 取景系数必须每帧钉住：SetDisplayInfo 异步落地，加载完成时引擎按默认
        --   取景重算 ⇒ 一次性设置会被冲掉（2026-10-07 实机：配了系数毫无变化）。
        ApplyCam(self)
        -- ★ 加载探测：探到真加载才显形（加载期 Alpha=0，用户看不到中间态）
        if not self.__loaded and ProbeLoaded(self) then
            self.__loaded = true
            self:SetAlpha(1)
        end
        if not rotating then return end
        local rot = self.__rot
        if self.SetFacing then
            pcall(self.SetFacing, self, rot)
        elseif self.SetRotation then
            pcall(self.SetRotation, self, rot)
        end
        ApplyCam(self)   -- 姿态之后再补一次，保证本帧最终取景不被引擎重算覆盖
    end)

    -- 名称 + 分组胶囊 + （宠物）难度胶囊 + 区域行 + 说明 / 步骤
    local name = MakeFS(p, 18, C_WHITE, "LEFT")
    name:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -(8 + MODEL_H + 12))
    name:SetPoint("TOPRIGHT", p, "TOPRIGHT", -200, -(8 + MODEL_H + 12))
    name:SetWordWrap(false)

    local pill = CreateFrame("Frame", nil, p, "BackdropTemplate")
    -- ⑥ 分组胶囊：L3 圆角胶囊（替代旧黑 25% 直角）
    if ns.hui and ns.hui.BuildCapsule then
        ns.hui.BuildCapsule(pill, 11, ns.hui.layer.L3)
    else
        pill:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        pill:SetBackdropColor(0, 0, 0, 0.25)
    end
    pill:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, -(8 + MODEL_H + 12))
    pill:SetSize(74, 22)
    local pillTxt = MakeFS(pill, 12, C_WHITE, "CENTER")
    pillTxt:SetPoint("CENTER", pill, "CENTER", 0, 0)

    -- 第二个胶囊（难度），只在宠物子页显示，拼在阵营胶囊左边
    local pill2 = CreateFrame("Frame", nil, p, "BackdropTemplate")
    -- ⑥ 难度胶囊：同分组胶囊（L3 圆角）
    if ns.hui and ns.hui.BuildCapsule then
        ns.hui.BuildCapsule(pill2, 11, ns.hui.layer.L3)
    else
        pill2:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        pill2:SetBackdropColor(0, 0, 0, 0.25)
    end
    pill2:SetPoint("TOPRIGHT", pill, "TOPLEFT", -8, 0)   -- 胶囊↔胶囊缝 8
    pill2:SetSize(74, 22)
    local pill2Txt = MakeFS(pill2, 12, C_WHITE, "CENTER")
    pill2Txt:SetPoint("CENTER", pill2, "CENTER", 0, 0)
    pill2:Hide()

    -- 区域行 + 坐标芯片（宠物专用；有真实坐标才出芯片）
    --   ★ 底部行版式（用户 2026-10-07 定稿）：
    --     名称行(+12，胶囊顶对齐) → 链接行(+42：查看获取详情 | 区域名 | 坐标芯片；距胶囊底 8) → 说明(+70)
    --     坐骑子页没有链接/区域行，说明保持 +42（与胶囊底 34 缝 8）。
    local zoneTx = MakeFS(p, 13, C_GREY, "LEFT")
    zoneTx:SetPoint("TOPLEFT", p, "TOPLEFT", PAD + 120, -(8 + MODEL_H + 42))
    zoneTx:SetPoint("TOPRIGHT", p, "TOPRIGHT", -110, -(8 + MODEL_H + 42))
    zoneTx:SetWordWrap(false)
    zoneTx:Hide()
    -- 区域行可点：走同一套落图（无坐标则只开该区域地图）
    local zoneHit = CreateFrame("Button", nil, p)
    zoneHit:SetPoint("TOPLEFT", zoneTx, "TOPLEFT", 0, 2)
    zoneHit:SetPoint("BOTTOMRIGHT", zoneTx, "BOTTOMRIGHT", 0, -2)
    zoneHit:SetScript("OnClick", function()
        if zoneTx.__area then CG.MarkPoint(zoneTx.__area, zoneTx.__x, zoneTx.__y) end
    end)
    zoneHit:SetScript("OnEnter", function(self) zoneTx:SetTextColor(Unpack(C_LINK)) end)
    zoneHit:SetScript("OnLeave", function(self) zoneTx:SetTextColor(Unpack(C_GREY)) end)
    zoneHit:Hide()
    local locChip = CreateFrame("Button", nil, p, "BackdropTemplate")
    -- ⑦ 坐标芯片：L2 圆角 + 链接青描边（替代旧黑 25% 直角淡蓝边；详情面板已定 L1 ⇒ 内件提亮一档）
    if ns.hui and ns.hui.BuildRoundedBG then
        ns.hui.BuildRoundedBG(locChip, 6, ns.hui.layer.L2, "both", false)
        if ns.hui.BuildRoundBorder then
            ns.hui.BuildRoundBorder(locChip, 6, { 0.55, 0.78, 1, 0.55 }, locChip, "BORDER", "both", 1)
        end
    else
        locChip:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        locChip:SetBackdropColor(0, 0, 0, 0.25)
        locChip:SetBackdropBorderColor(0.55, 0.78, 1, 0.35)
    end
    locChip:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, -(8 + MODEL_H + 42))
    locChip:SetSize(84, 20)
    local locChipTx = MakeFS(locChip, 11, C_LINK, "CENTER")
    locChipTx:SetPoint("CENTER", locChip, "CENTER", 0, 0)
    locChip:Hide()
    locChip:SetScript("OnClick", function(self)
        if self.__area then CG.MarkPoint(self.__area, self.__x, self.__y) end
    end)

    local desc = MakeFS(p, 13, C_TEXT, "LEFT")
    desc:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -(8 + MODEL_H + 42))
    desc:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, -(8 + MODEL_H + 42))
    desc:SetJustifyV("TOP")

    -- ★ 跳转探索页「获取详情」链接（用户 2026-10-07 指定）：
    --   走 ns.OpenPage("Explore") + ExploreModule.ShowSub("pets")（快速按钮栏同款链路），
    --   再 FocusPet(itemID) 滚到对应那张卡。宠物子页且**条目在探索页**时才显示
    --   （藏品独有宠物没有探索页详情卡，跳转隐藏，见 PaintDetail）。
    local gotoBtn = CreateFrame("Button", nil, p)
    gotoBtn:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -(8 + MODEL_H + 42))
    gotoBtn:SetHeight(18)
    local gotoText = MakeFS(gotoBtn, 13, C_LINK, "LEFT")
    gotoText:SetPoint("TOPLEFT", gotoBtn, "TOPLEFT", 0, 0)
    gotoText:SetText(L["查看获取详情 →"])
    gotoBtn:SetWidth(gotoText:GetStringWidth() + 8)
    gotoBtn:SetScript("OnEnter", function(self) gotoText:SetTextColor(1, 1, 1) end)
    gotoBtn:SetScript("OnLeave", function(self) gotoText:SetTextColor(Unpack(C_LINK)) end)
    gotoBtn:SetScript("OnClick", function()
        local rec = CG.sel
        ns.OpenPage("Explore")
        local EG = ns.ExploreModule
        if EG and EG.ShowSub then
            EG.ShowSub("pets")
            if rec and EG.FocusPet then EG.FocusPet(rec[1]) end
        end
    end)
    gotoBtn:Hide()

    -- ★ 坐骑说明 NPC 点击段帧池：商人/掉落来源的 NPC 名字在说明文本里直接可点击
    --   （与任务页 NPC 名同链路：坐标查 ns.NPCLoc，未收录时 MarkNPC 明说）。
    --   数据：条目命名键 npcs = { { npcID, "名字" }, … }（Data_CollectionMounts.lua）。
    --   段帧池一次建好复用（页骨架纪律）；池宽 8 格，段数超池退纯文本。
    local srcSegs = {}
    for k = 1, 8 do
        local sg = CreateFrame("Button", nil, p)
        sg:SetHeight(STEP_H)
        local fs = MakeFS(sg, 13, C_STEP_LINK, "LEFT")
        sg:SetFontString(fs)
        sg.tx = fs
        sg:SetScript("OnEnter", function(self)
            if not self.__npcID then return end
            self.tx:SetTextColor(Unpack(C_STEP_LINK_HI))
            DG.ShowNpcTip(self, self.__npcID)
        end)
        sg:SetScript("OnLeave", function(self)
            self.tx:SetTextColor(Unpack(self.__npcID and C_STEP_LINK or C_TEXT))
            TipOff()
        end)
        sg:SetScript("OnClick", function(self)
            if self.__npcID then
                DG.MarkNPC(self.__npcID)
                ns.PlaySound(1)
            end
        end)
        sg:Hide()
        srcSegs[k] = sg
    end

    -- 空态（列表为空，例如搜索无结果）
    local empty = MakeFS(p, 14, C_DIM, "CENTER")
    empty:SetPoint("CENTER", vp, "CENTER", 0, 0)
    empty:SetText(L["没有匹配的条目"])
    empty:Hide()

    CG.detail = {
        panel = p, vp = vp, model = model, modelIcon = modelIcon,
        name = name, pill = pill, pillTxt = pillTxt,
        pill2 = pill2, pill2Txt = pill2Txt,
        zoneTx = zoneTx, zoneHit = zoneHit,
        locChip = locChip, locChipTx = locChipTx,
        gotoBtn = gotoBtn,
        desc = desc, empty = empty, hintTxt = hint,
        segs = {},   -- 宠物步骤可点击段帧池（PaintSteps / StepSeg，一次建好复用）
        srcSegs = srcSegs,   -- 坐骑说明 NPC 点击段帧池（BuildDetailPanel 一次建好）
    }
end

function CG.Build(page)
    if CG.built or CG.building then return end
    CG.building = true
    ns.PhasedStart(34, coroutine.create(function()
    CG.page = page
    CG.sub = SUB_MOUNT
    CG.filter = "all"
    CG.search = ""
    BuildListPanel(page)
    coroutine.yield()
    BuildDetailPanel(page)
    coroutine.yield()
    CG.built = true
    if CG.PaintFilters then CG.PaintFilters() end
    CG.Render()
    end))
end

function CG.Open()
    if not CG.built then return end
    CG.Render()
    CG.needNames = not ProbeNames()
    SweepNames()
end

-- 供外部跳转：打开藏品页并直接落到某个子页（目前只给座骑/宠物两格）
function CG.ShowSub(key)
    if not CG.built then return end
    if key ~= SUB_MOUNT and key ~= SUB_PET then key = SUB_MOUNT end
    if CG.sub ~= key then
        CG.sub = key
        CG.filter = "all"
        CG.search = ""
        if CG.searchBox then CG.searchBox:SetText("") end
        if CG.PaintFilters then CG.PaintFilters() end
    end
    CG.sel = nil
    CG.Render()
    CG.needNames = not ProbeNames()
    SweepNames()
end

function CG.Refresh()
    if not CG.built then return end
    CG.Render()
end

CG.Render = Paint

return
