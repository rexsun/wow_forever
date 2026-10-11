-- =============================================================================
-- DungeonsForever · 专业升级自动路线（按拍卖行价格）
-- 输入专业与过滤设置，输出与固定路线同构的分段路线与成本汇总；不持有任何 UI。
-- =============================================================================

local _, ns = ...

if not ns.LoadForeverPages then return end

local RA = {}
ns.ProfRouteAuto = RA

local CALLER = "DungeonsForever"
local CAP = 300                  -- 无限服 1.60.1 专业上限
local MAX_STALE = 2              -- 价格快照年龄上限（天；价格插件 Age API 返回的就是「天」），超过视为无价
local MAX_PER_RECIPE = 3         -- 同一配方最多出现在 3 段里（防呆：逼路线前进）
local CACHE_TTL = 600            -- 结果缓存 10 分钟
-- 期望收益插值端点（调参集中在这里）
-- ★★ 语义 = 「单次制作的升点概率 P（点/次）」，不是收益系数 —— Simulate 里按 1/P 累计次数。
--   端点须与 ProfFollow.expPerPoint（经典 1/P 口径）一致：
--     黄段 P 1.0 → 0.5、绿段 P 0.5 → 0.05（段末深绿只有 5% 涨点率，要做 20 次）。
--   2026-10-09 修：原为 0.7 / 0.25，把绿色段升点率最高高估 5 倍 ⇒ 次数系统性偏小
--   （91 个攻略段标定：现值 3.2% 误差 / 旧值 11.0%；总次数 2548 → 3822）。
local G_YELLOW, G_GREEN = 0.5, 0.05

-- ── 自动路线方案（2026-10-10 用户：设置内可选，默认最省钱）────────────────────
--   cheapest = 材料+图纸价摊到每点（图纸一次性成本计入选型，修「关掉排除图纸反而
--   更贵」的隐形成本问题）；matcost = 旧口径（只看材料价）；crafts = 期望制作次数
--   最少（同分取便宜）；optim = 乐观计数（1 次=1 点保底、变黄前 25 点
--   可学、排除冷却与未公开材料配方、材料按卖店基础价值比价、不依赖价格插件）。
local SCHEME_ORDER = { "cheapest", "matcost", "crafts", "optim" }
-- ★ 本文件加载序在 Locales 之前 ⇒ 不能在加载期取 L；标签存键名、运行时查。
--   方案标签键（供三语扫描器登记，正则只认 L["…"] 字面量）：
--   L["最省钱"] L["材料成本"] L["次数最少"] L["乐观计数"]
local SCHEME_LABEL = {
    cheapest = "最省钱",
    matcost = "材料成本",
    crafts = "次数最少",
    optim = "乐观计数",
}
function RA.SchemeOrder() return SCHEME_ORDER end
function RA.SchemeLabel(s)
    local k = (s and SCHEME_LABEL[s]) and SCHEME_LABEL[s] or "最省钱"
    return type(L) == "table" and L[k] or k
end

-- ── 拍卖行价格插件可用性与价格层 ──────────────────────────────────────────────

function RA.Available()
    return type(Auctionator) == "table"
        and type(Auctionator.API) == "table"
        and type(Auctionator.API.v1) == "table"
        and type(Auctionator.API.v1.GetAuctionPriceByItemID) == "function"
end

local function CallAPI(fn, ...)
    local ok, v = pcall(fn, CALLER, ...)
    if ok then return v end
    return nil
end

local priceCache = {}   -- itemID → number | false（false = 已查无价）

local function AHPrice(id)
    if priceCache[id] ~= nil then
        return priceCache[id] or nil
    end
    local p
    if RA.Available() then
        p = CallAPI(Auctionator.API.v1.GetAuctionPriceByItemID, id)
        if type(p) ~= "number" or p <= 0 then p = nil end
        if p and type(Auctionator.API.v1.GetAuctionAgeByItemID) == "function" then
            local age = CallAPI(Auctionator.API.v1.GetAuctionAgeByItemID, id)
            if type(age) == "number" then
                if age > MAX_STALE then p = nil end
                if age < (priceCache.__minAge or math.huge) then
                    priceCache.__minAge = age
                end
            end
        end
    end
    priceCache[id] = p or false
    if p then priceCache.__any = true end
    return p
end

local function VendorPrice(id)
    -- ① 插件自采商人价（VendorPriceDB，开过商人窗口就有，不依赖价格插件）
    if ns.VendorPriceDB then
        local ok, p = pcall(ns.VendorPriceDB.GetPrice, id)
        if ok and type(p) == "number" and p > 0 then return p end
    end
    -- ② 价格插件兜底（GetVendorPriceByItemID）
    if not RA.Available() then return nil end
    local fn = Auctionator.API.v1.GetVendorPriceByItemID
    if type(fn) ~= "function" then return nil end
    local p = CallAPI(fn, id)
    if type(p) ~= "number" or p <= 0 then return nil end
    return p
end

-- 材料价：商人直卖清单内强制商人价；否则取 min(AH, 商人)；都无 = nil
local function MatPrice(id, soldSet)
    local v = VendorPrice(id)
    if soldSet[id] then return v end
    local a = AHPrice(id)
    if a and v and v < a then return v end
    return a or v
end

-- 物品卖店价（直接卖给 NPC 的收益）：三通道依次尝试。
-- 本客户端全局 GetItemInfo 不可靠，优先 C_Item.GetItemInfo 现代命名空间版
-- （SELL_PRICE = 第 11 个返回值），再兜 C_Item.GetItemSellPrice。
-- ★ 只缓存成功值：物品数据异步到货，未加载时返回 nil；把 nil 钉进缓存会让
--   产物「直接卖给NPC收益」永久停在 0。
local sellCache = {}   -- itemID → number（只缓存成功值）
local function NPCSellPrice(id)
    if sellCache[id] then return sellCache[id] end
    local p
    -- ① C_Item.GetItemInfo（现代命名空间）
    if C_Item and C_Item.GetItemInfo then
        local vals = { pcall(C_Item.GetItemInfo, id) }
        if vals[1] then
            local sell = vals[12]   -- vals[1]=pcall ok，其后依次 GetItemInfo 返回值（第 11 项 = sellPrice）
            if type(sell) == "number" and sell > 0 then p = sell end
        end
    end
    -- ② 全局 GetItemInfo（老通道）
    if not p and type(GetItemInfo) == "function" then
        local vals = { pcall(GetItemInfo, id) }
        if vals[1] then
            local sell = vals[12]
            if type(sell) == "number" and sell > 0 then p = sell end
        end
    end
    -- ③ C_Item.GetItemSellPrice（专用 API，直达）
    if not p and C_Item and C_Item.GetItemSellPrice then
        local ok, sell = pcall(C_Item.GetItemSellPrice, id)
        if ok and type(sell) == "number" and sell > 0 then p = sell end
    end
    if p then sellCache[id] = p end
    return p
end

-- 客户端是否已公开该物品（optim 方案排除「未公开物品」材料的配方）：
--   GetItemInfo 通道查无名字 = 未公开。物品数据异步到货，首开可能误判 ——
--   数据到货后自动路线缓存会失效重算（ProfessionUI 已有该钩子）。
local function ClientKnown(id)
    local dg = ns.ProfHost and ns.ProfHost.DG
    if dg and type(dg.ItemInfo) == "function" then
        return dg.ItemInfo(id) ~= nil
    end
    if C_Item and C_Item.GetItemInfo then
        return (C_Item.GetItemInfo(id)) ~= nil
    end
    return true
end

-- 材料清单成本（2026-10-10 配方页「制作成本」列/提示框「成本」行共用）：
-- mats = {{id, cnt}, ...}；逐项取 MatPrice（商人价优先/拍卖兜底），无价项计 0 并计数。
-- 返回 total, unpriced（unpriced>0 = 部分材料没价，调用方加 ≈ 前缀）
local MATSOLD_EMPTY = {}   -- MatPrice(id, soldSet) 的空表常量（提示框查价无「商人直卖」上下文）
local function MatListCost(mats)
    if type(mats) ~= "table" or #mats == 0 then return nil, 0 end
    local total, unpriced = 0, 0
    for _, m in ipairs(mats) do
        local id, cnt = m[1] or m.id, (m[2] or m.cnt or 1)
        local p = MatPrice(id, MATSOLD_EMPTY)
        if p then total = total + p * cnt else unpriced = unpriced + 1 end
    end
    return total, unpriced
end

-- ── 提示框/配方页只读价格口（2026-10-10）───────────────────────────────────
-- 拍卖行单价（走 AHPrice 会话内缓存，重复查询零开销；无价 nil）
function RA.AHPriceOf(itemID)
    if not itemID then return nil end
    return AHPrice(itemID)
end

-- 卖店价（三通道，见 NPCSellPrice 注释；数据未加载时 nil，下次悬停重试）
function RA.NPCSellPriceOf(itemID)
    if not itemID then return nil end
    return NPCSellPrice(itemID)
end

-- 材料清单成本：返回 total, unpriced（调用方以 unpriced 决定 ≈ 前缀 / — 显示）
function RA.MatListCost(mats)
    return MatListCost(mats)
end

-- 产物 itemID 预热：走插件的物品加载通道，到货后 UI 重渲染即可取到卖店价
local function RequestProduct(id)
    local H = ns.ProfHost
    local dg = H and H.DG
    if dg and dg.RequestItem then pcall(dg.RequestItem, id) end
end

-- 真实价格快照时间（秒级）：价格插件 SavedState 存的是 epoch 时间戳
-- （TimeOfLastGetAllScan / TimeOfLastReplicateScan / TimeOfLastBrowseScan）。
-- 取三者里最新 → time() - ts = 距上次扫描的秒数；取不到返回 nil（调用方回退天级）。
local function SnapshotSec()
    local A = Auctionator
    local st = (type(A) == "table") and A.SavedState
    if type(st) ~= "table" then return nil end
    local best
    for _, k in ipairs({ "TimeOfLastGetAllScan", "TimeOfLastReplicateScan", "TimeOfLastBrowseScan" }) do
        local v = tonumber(st[k])
        if v and v > 0 and (not best or v > best) then best = v end
    end
    if not best then return nil end
    local now = (type(time) == "function") and time() or 0
    local age = now - best
    if age < 0 then return nil end
    return age
end

-- 是否查到过任何价格数据（一条都没有 = 价格插件未扫描，调用方降级）
function RA.HasPriceData()
    return priceCache.__any and true or false
end

-- 距上次拍卖行扫描的秒数（取不到 nil；板条箱页价格快照用）
function RA.SnapshotAge()
    return SnapshotSec()
end

-- ── 金额格式（金/银，铜抹到银）──────────────────────────────────────────────


-- 币种图标（|T|t 尺寸 0 = 跟随所在文本字号；2026-10-10 金/银/铜不用文字用图标）
local ICON_G = "|TInterface\\MoneyFrame\\UI-GoldIcon:0|t"
local ICON_S = "|TInterface\\MoneyFrame\\UI-SilverIcon:0|t"
local ICON_C = "|TInterface\\MoneyFrame\\UI-CopperIcon:0|t"

-- opt = "copper"：最小单位到铜（购物清单 / 花费卡）；默认抹到银（路线段落等保持紧凑）
-- 负值（2026-10-10 用户）：差价/净利为负时如实显示 - 前缀（不再钳成 0）
function RA.MoneyStr(copper, opt)
    copper = tonumber(copper)
    if copper and copper < 0 then
        return "-" .. RA.MoneyStr(-copper, opt)
    end
    if not copper or copper <= 0 then
        return (opt == "copper") and ("0" .. ICON_C) or ("0" .. ICON_S)
    end
    if opt == "copper" then
        local g = math.floor(copper / 10000)
        local s = math.floor(copper / 100) % 100
        local c = copper % 100
        if g > 0 then
            return format("%d%s%02d%s%02d%s", g, ICON_G, s, ICON_S, c, ICON_C)
        end
        return format("%d%s%02d%s", s, ICON_S, c, ICON_C)
    end
    local totalSilver = math.floor(copper / 100 + 0.5)   -- 四舍五入到银
    local g = math.floor(totalSilver / 100)
    local s = totalSilver % 100
    if g > 0 then return format("%d%s%02d%s", g, ICON_G, s, ICON_S) end
    return format("%d%s", s, ICON_S)
end

-- ── 单次制作的升点概率 P（橙→黄→绿线性插值，与 ProfFollow.expPerPoint 同源）──
--   返回「这一次制作涨 1 技能点的概率」；调用方按 1/P 累计制作次数。

local function Gain(skill, c)
    if skill < c.learn or skill >= c.grey then return nil end
    if skill < c.yellow then return 1.0 end
    if skill < c.green then
        local span = c.green - c.yellow
        if span <= 0 then return G_YELLOW end
        local t = (skill - c.yellow) / span
        return 1.0 - t * (1.0 - G_YELLOW)
    end
    local span = c.grey - c.green
    if span <= 0 then return G_GREEN end
    local t = (skill - c.green) / span
    return G_YELLOW - t * (G_YELLOW - G_GREEN)
end

-- ── 候选集构建 ──────────────────────────────────────────────────────────────
-- rec 行字段序（Data_ProfRecipes.lua 头注释）：
--   1 spell / 2 itemID / 3 count / 4 cat / 5 kind / 6 effect / 7 learn /
--   8 yellow / 9 green / 10 grey / 11 is_new / 12 reagents / 13 formula / 14 source

local function LearnKnown(spell)
    if type(IsSpellKnown) == "function" then
        local ok, v = pcall(IsSpellKnown, spell)
        if ok and v then return true end
    end
    if type(IsPlayerSpell) == "function" then
        local ok, v = pcall(IsPlayerSpell, spell)
        if ok and v then return true end
    end
    return false
end

-- opts = { start=起点技能, onlyAH=bool, noFormula=bool, learnedOnly=bool }
local function BuildCandidates(slug, opts)
    local Rg = ns.ProfRecipes and ns.ProfRecipes[slug]
    local LV = ns.ProfLeveling and ns.ProfLeveling[slug]
    if not (Rg and type(Rg.rows) == "table") then return nil end
    local soldSet = {}
    if LV and type(LV.sold) == "table" then
        for _, id in ipairs(LV.sold) do soldSet[id] = true end
    end

    local cands, recOf = {}, {}
    for _, rec in ipairs(Rg.rows) do
        local spell, learn, yellow, green, grey = rec[1], rec[7], rec[8], rec[9], rec[10]
        local reagents = rec[12]
        if type(spell) == "number" and type(learn) == "number"
           and type(grey) == "number" and grey > learn
           and type(reagents) == "table" and #reagents > 0 then
            local ok = true
            -- 设置过滤：图纸配方（formula 非空且商人不可得 = 掉落图纸）
            -- ★ cheapest 忽略本开关（2026-10-11 用户拍板 A）：图纸成本已按覆盖点数
            --   正确摊销进指标，排除后候选全无图纸成本 → cheapest 与 matcost 恒等
            --   （两方案路线一模一样实测实锤）。其余方案维持开关语义。
            local skipFormula = opts.noFormula and opts.scheme ~= "cheapest"
            if ok and skipFormula and rec[13] then
                local src = rec[14]
                if not (type(src) == "table" and type(src.vendors) == "table" and #src.vendors > 0) then
                    ok = false
                end
            end
            -- 设置过滤：仅已学
            if ok and opts.learnedOnly and not LearnKnown(spell) then ok = false end
            -- 材料定价（含生死判定）
            if ok then
                local cost, unpriced = 0, false
                for _, m in ipairs(reagents) do
                    local p = MatPrice(m[1], soldSet)
                    if p then
                        cost = cost + p * (m[2] or 1)
                    else
                        unpriced = true
                    end
                end
                -- 「只用拍卖行可购材料」不再在此处淘汰（2026-10-09 修缺口误报）：
                -- 无价配方保留进候选池并打 unpriced 标记，严格性由 Simulate 按
                -- allowUnpriced 控制 —— 缺口段会自动放宽，用已知材料估价回填。
                if ok then
                    local itemID = rec[2]
                    -- 方案字段（2026-10-10）：fcost=图纸价（已学免费/取不到按 0，仅
                    --   cheapest 计入选型，摊到 grey-learn 覆盖点数）；base=材料卖店基础价值合计（optim 比价/花费）；
                    --   cd=冷却配方（cat=Transmutes）；unknown=材料客户端未公开；
                    --   learnO=提前学习线（变黄前 25 点）
                    local f = rec[13]
                    local fcost = 0
                    if type(f) == "table" and type(f[1]) == "number" and not LearnKnown(spell) then
                        fcost = MatPrice(f[1], soldSet) or 0
                    end
                    local base, unknown = 0, false
                    for _, m in ipairs(reagents) do
                        if not ClientKnown(m[1]) then unknown = true end
                        local sp = NPCSellPrice(m[1])
                        if sp then base = base + sp * (m[2] or 1) end
                    end
                    local cY = (type(yellow) == "number") and yellow or learn
                    cands[#cands + 1] = {
                        spell = spell, item = (type(itemID) == "number") and itemID or nil,
                        learn = learn, yellow = cY,
                        green = (type(green) == "number") and green or yellow or learn,
                        grey = grey, mats = reagents, cost = cost, unpriced = unpriced,
                        fcost = fcost, base = base, cd = (rec[4] == "Transmutes") or nil,
                        unknown = unknown or nil,
                        learnO = math.max(1, math.min(learn, cY - 25)),
                    }
                    recOf[spell] = rec
                end
            end
        end
    end
    -- rinfo（2026-10-08）：路线引用但配方表没有的法术（附魔配方游离在 enchants
    -- 之外、魔棒两头都不在）并入候选池 —— 否则附魔 1→300 自动路线整段缺。
    -- 字段口径与上面 rows 候选一致（rinfo 是生成器落的纯数值兜底表）。
    if LV and type(LV.rinfo) == "table" then
        for spell, ri in pairs(LV.rinfo) do
            if type(spell) == "number" and not recOf[spell]
               and type(ri.learn) == "number" and type(ri.grey) == "number"
               and ri.grey > ri.learn
               and type(ri.mats) == "table" and #ri.mats > 0 then
                local ok = not (opts.learnedOnly and not LearnKnown(spell))
                local cost, unpriced = 0, false
                if ok then
                    for _, m in ipairs(ri.mats) do
                        local p = MatPrice(m[1], soldSet)
                        if p then
                            cost = cost + p * (m[2] or 1)
                        else
                            unpriced = true
                        end
                    end
                end
                if ok then
                    local y = (type(ri.yellow) == "number") and ri.yellow or ri.learn
                    local g = (type(ri.green) == "number") and ri.green or y
                    -- 方案字段（2026-10-10）：rinfo 无图纸/分类 → fcost=0、cd=false
                    local base, unknown = 0, false
                    for _, m in ipairs(ri.mats) do
                        if not ClientKnown(m[1]) then unknown = true end
                        local sp = NPCSellPrice(m[1])
                        if sp then base = base + sp * (m[2] or 1) end
                    end
                    cands[#cands + 1] = {
                        spell = spell, item = (type(ri.makes) == "number") and ri.makes or nil,
                        learn = ri.learn, yellow = y, green = g, grey = ri.grey,
                        mats = ri.mats, cost = cost, unpriced = unpriced,
                        fcost = 0, base = base, unknown = unknown or nil,
                        learnO = math.max(1, math.min(ri.learn, y - 25)),
                    }
                    recOf[spell] = ri
                end
            end
        end
    end
    return cands, recOf, soldSet
end

-- ── 贪心逐技能点模拟 ────────────────────────────────────────────────────────
-- allowUnpriced=false 时无价配方不参与（「只用拍卖行可购材料」的严格口径）；
-- 严格模拟产生的缺口由 FillGaps 放宽回填（2026-10-09 修缺口误报）。

local function Eligible(c, allowUnpriced)
    return allowUnpriced or not c.unpriced
end

-- 方案相关的可用/收益判定（2026-10-10 方案化改造）：
--   optim 用提前学习线 learnO（min(learn, 变黄前 25 点)）、收益恒 1（乐观口径）、
--   排除冷却配方（cat=Transmutes，月布/转化等）与材料未公开的配方；
--   其余方案走原口径（learn 阈值 + 期望概率插值）。
local function CanUse(scheme, c, cur)
    local lo = (scheme == "optim") and (c.learnO or c.learn) or c.learn
    return cur >= lo and cur < c.grey
end
local function Usable(scheme, c, cur, allowUnpriced)
    if (scheme == "optim") and (c.cd or c.unknown) then return false end
    if not Eligible(c, allowUnpriced) then return false end
    return CanUse(scheme, c, cur)
end
local function GainOf(scheme, c, cur)
    if not CanUse(scheme, c, cur) then return nil end
    if scheme == "optim" then return 1 end
    return Gain(cur, c)
end
local function MetricOf(scheme, c, g)
    if scheme == "cheapest" then
        -- ★ 量纲（2026-10-11 修反转）：每点成本 = cost/g（材料，做 1/g 次每次 cost）
        --   + fcost/覆盖点数（图纸只买一次，与制作次数无关！此前除以 g 等于
        --   「每次制作摊一份图纸」，g 小时惩罚被放大 1/g 倍，贪心系统性回避
        --   图纸配方 → 总花费反超纯材料方案（用户实测实锤）。
        local span = math.max(1, (c.grey or 0) - (c.learn or 0))
        return c.cost / g + (c.fcost or 0) / span
    end
    if scheme == "crafts" then return 1 / g end
    if scheme == "optim" then return (c.base or 0) / g end
    return c.cost / g
end

local function Simulate(cands, start, cap, allowUnpriced, scheme)
    local steps, gaps = {}, {}
    local banned, segRun = {}, {}
    local cur = math.max(1, math.min(cap - 1, start or 1))
    local guard = 0

    while cur < cap do
        guard = guard + 1
        if guard > 4000 then break end

        -- 当前技能点上最优的配方
        local best, bestMetric
        for _, c in ipairs(cands) do
            if not banned[c.spell] and Usable(scheme, c, cur, allowUnpriced) then
                local g = GainOf(scheme, c, cur)
                if g then
                    local metric = MetricOf(scheme, c, g)
                    if not best or metric < bestMetric - 1e-9
                       or (metric < bestMetric + 1e-9 and c.grey > best.grey) then
                        best, bestMetric = c, metric
                    end
                end
            end
        end

        if not best then
            -- 缺口：跳到下一个可学配方，或宣告到顶无解
            local nxt
            for _, c in ipairs(cands) do
                if not banned[c.spell] and Usable(scheme, c, cur, allowUnpriced) then
                    local lo = (scheme == "optim") and (c.learnO or c.learn) or c.learn
                    if lo > cur and (not nxt or lo < nxt) then nxt = lo end
                end
            end
            if nxt then
                gaps[#gaps + 1] = { cur, nxt - 1 }
                cur = nxt
            else
                if cur < cap then gaps[#gaps + 1] = { cur, cap - 1 } end
                cur = cap
            end
        else
            -- 以 best 一路做到它变灰 / 出现更优配方
            local from = cur
            local crafts = 0
            while cur < cap do
                local g = Gain(cur, best)
                if not g then break end
                crafts = crafts + 1 / g
                cur = cur + 1
                local stop = false
                for _, c in ipairs(cands) do
                    if c ~= best and not banned[c.spell] and Usable(scheme, c, cur, allowUnpriced) then
                        local g2 = GainOf(scheme, c, cur)
                        if g2 and MetricOf(scheme, c, g2) < bestMetric - 1e-9 then
                            stop = true
                            break
                        end
                    end
                end
                if stop then break end
            end
            local qty = math.max(1, math.ceil(crafts - 1e-9))
            local last = steps[#steps]
            if last and last[3] == best.spell and last[2] + 1 == from then
                last[2] = cur - 1
                last[4] = last[4] + qty
                last.cost = last.cost + best.cost * qty
            else
                steps[#steps + 1] = {
                    from, cur - 1, best.spell, qty,
                    cost = best.cost * qty, item = best.item,
                    unpriced = best.unpriced,
                }
                segRun[best.spell] = (segRun[best.spell] or 0) + 1
                if segRun[best.spell] >= MAX_PER_RECIPE then banned[best.spell] = true end
            end
        end
    end
    return steps, gaps
end

-- 区间模拟（缺口回填用）：在 [a, b] 内放宽条件跑贪心，返回段列表与残余缺口。
local function SimulateRange(cands, a, b, scheme)
    local steps = {}
    local banned, segRun = {}, {}
    local cur = a
    local guard = 0
    while cur <= b do
        guard = guard + 1
        if guard > 1000 then break end
        local best, bestMetric
        for _, c in ipairs(cands) do
            if not banned[c.spell] and CanUse(scheme, c, cur)
               and not ((scheme == "optim") and (c.cd or c.unknown)) then
                local g = GainOf(scheme, c, cur)
                if g then
                    local metric = MetricOf(scheme, c, g)
                    if not best or metric < bestMetric - 1e-9
                       or (metric < bestMetric + 1e-9 and c.grey > best.grey) then
                        best, bestMetric = c, metric
                    end
                end
            end
        end
        if not best then
            local nxt
            for _, c in ipairs(cands) do
                if not banned[c.spell] and not ((scheme == "optim") and (c.cd or c.unknown)) then
                    local lo = (scheme == "optim") and (c.learnO or c.learn) or c.learn
                    if lo > cur and lo <= b and (not nxt or lo < nxt) then nxt = lo end
                end
            end
            if not nxt then break end
            cur = nxt
        else
            local from = cur
            local crafts = 0
            while cur <= b do
                local g = Gain(cur, best)
                if not g then break end
                crafts = crafts + 1 / g
                cur = cur + 1
                local stop = false
                for _, c in ipairs(cands) do
                    if c ~= best and not banned[c.spell] and CanUse(scheme, c, cur)
                       and cur <= b and not ((scheme == "optim") and (c.cd or c.unknown)) then
                        local g2 = GainOf(scheme, c, cur)
                        if g2 and MetricOf(scheme, c, g2) < bestMetric - 1e-9 then
                            stop = true
                            break
                        end
                    end
                end
                if stop then break end
            end
            local qty = math.max(1, math.ceil(crafts - 1e-9))
            local to = math.min(cur - 1, b)
            local last = steps[#steps]
            if last and last[3] == best.spell and last[2] + 1 == from then
                last[2] = to
                last[4] = last[4] + qty
                last.cost = last.cost + best.cost * qty
            else
                steps[#steps + 1] = {
                    from, to, best.spell, qty,
                    cost = best.cost * qty, item = best.item,
                    unpriced = best.unpriced, est = true,
                }
                segRun[best.spell] = (segRun[best.spell] or 0) + 1
                if segRun[best.spell] >= MAX_PER_RECIPE then banned[best.spell] = true end
            end
        end
    end
    -- 残余缺口：区间内没有任何段覆盖到的地方（真无解）
    local coverTo = a - 1
    for _, s in ipairs(steps) do
        if s[1] <= coverTo + 1 then coverTo = math.max(coverTo, s[2]) end
    end
    local resid = (coverTo < b) and { coverTo + 1, b } or nil
    return steps, resid
end

-- 相邻同配方段合并（回填段与主段在缺口边界拼回一条）
local function MergeSteps(steps)
    local out = {}
    for _, s in ipairs(steps) do
        local last = out[#out]
        if last and last[3] == s[3] and last[2] + 1 == s[1] then
            last[2] = s[2]
            last[4] = last[4] + s[4]
            last.cost = (last.cost or 0) + (s.cost or 0)
            if s.unpriced then last.unpriced = true end
            if s.est then last.est = true end
        else
            out[#out + 1] = s
        end
    end
    return out
end

-- 缺口回填：对每段缺口放宽「只用可购材料」跑区间模拟，能填的填、填不动的留缺口。
local function FillGaps(cands, steps, gaps, scheme)
    local out = {}
    local si = 1
    for _, g in ipairs(gaps) do
        while si <= #steps and steps[si][2] < g[1] do
            out[#out + 1] = steps[si]
            si = si + 1
        end
        local fills, resid = SimulateRange(cands, g[1], g[2], scheme)
        for _, s in ipairs(fills) do out[#out + 1] = s end
        if resid then out[#out + 1] = { gap = resid } end
    end
    while si <= #steps do
        out[#out + 1] = steps[si]
        si = si + 1
    end
    local newSteps, newGaps = {}, {}
    for _, it in ipairs(out) do
        if it.gap then
            newGaps[#newGaps + 1] = it.gap
        else
            newSteps[#newSteps + 1] = it
        end
    end
    return MergeSteps(newSteps), newGaps
end

-- ── 汇总：总成本 / 材料聚合 / 制作次数 / 图纸 ─────────────────────────────
-- rec 行字段：13 = { 图纸itemID, … }（配方由图纸教授时非空）
-- 步骤 cost：自动段在 Simulate 里已带；固定路线步骤没有 → 按「材料单价 × 用量 × 次数」现算
--   （含无价材料的段同时打 unpriced 标记 —— 花费为估算下限）

local function SummarizeCore(steps, recOf, soldSet, skipLearnedFormulas)
    local total, crafts = 0, 0
    -- 产物收益（2026-10-09 四轮）：AH 变卖 / NPC 直卖两条口径
    local productAH, productNPC, productPartial = 0, 0, false
    local mats, firstAt, matPrice = {}, {}, {}
    for _, st in ipairs(steps) do
        local rec = recOf[st[3]]
        local ml = rec and (rec[12] or rec.mats) or nil
        if st.cost == nil then
            local sc, unpriced = 0, false
            if ml then
                for _, m in ipairs(ml) do
                    local id = m[1]
                    if matPrice[id] == nil then matPrice[id] = MatPrice(id, soldSet) end
                    local p = matPrice[id]
                    if p then
                        sc = sc + p * (m[2] or 1) * (st[4] or 0)
                    else
                        unpriced = true
                    end
                end
            end
            st.cost = sc
            st.unpriced = unpriced or nil
        end
        total = total + (st.cost or 0)
        crafts = crafts + (st[4] or 0)
        -- 产物收益：产物 itemID（rec[2]）× 一次产量（rec[3]）× 制作次数（st[4]）
        local prod = rec and rec[2]
        if type(prod) == "number" then
            local outN = (st[4] or 0) * (rec[3] or 1)
            RequestProduct(prod)   -- 异步预热产物物品（卖店价要等物品数据到货）
            local ah = AHPrice(prod)
            if ah then
                productAH = productAH + ah * outN
            else
                productPartial = true
            end
            local sp = NPCSellPrice(prod)
            if sp then productNPC = productNPC + sp * outN end
        end
        if ml then
            for _, m in ipairs(ml) do
                local id = m[1]
                mats[id] = (mats[id] or 0) + (m[2] or 1) * (st[4] or 0)
                if not firstAt[id] or st[1] < firstAt[id] then firstAt[id] = st[1] end
                if matPrice[id] == nil then
                    matPrice[id] = MatPrice(id, soldSet)
                end
            end
        end
    end
    local list = {}
    for id, n in pairs(mats) do
        local p = matPrice[id]
        if p == nil then p = MatPrice(id, soldSet) end
        list[#list + 1] = { id, n, cost = (p or 0) * n, unit = p or 0,
                            vendor = soldSet[id] and true or false,
                            unpriced = (p == nil) and true or false }
    end
    table.sort(list, function(a, b)
        local fa, fb = firstAt[a[1]] or math.huge, firstAt[b[1]] or math.huge
        if fa ~= fb then return fa < fb end
        if a[2] ~= b[2] then return a[2] > b[2] end
        return a[1] < b[1]
    end)
    local vendorTotal = 0
    for _, e in ipairs(list) do
        if e.vendor then vendorTotal = vendorTotal + (e.unit or 0) * e[2] end
    end
    -- 图纸（一次性）：与材料分开列，但计入总花费；每种只列一次
    local formulas, formulasTotal = {}, 0
    for _, st in ipairs(steps) do
        local rec = recOf[st[3]]
        local f = rec and rec[13]
        if type(f) == "table" and type(f[1]) == "number"
           and not (skipLearnedFormulas and LearnKnown(st[3])) then
            local dup = false
            for _, x in ipairs(formulas) do
                if x.id == f[1] then dup = true break end
            end
            if not dup then
                local p = MatPrice(f[1], soldSet)
                formulas[#formulas + 1] = {
                    id = f[1], spell = st[3], cost = p or 0,
                    vendor = soldSet[f[1]] and true or false,
                    unpriced = (p == nil) and true or false,
                }
                formulasTotal = formulasTotal + (p or 0)
            end
        end
    end
    return total, crafts, list, firstAt, vendorTotal, formulas, formulasTotal,
           productAH, productNPC, productPartial
end

-- 公开入口：固定路线复用同一套聚合/定价/图纸收集（steps = {起,止,spell,次数}）
function RA.SummarizeSteps(steps, slug, opts)
    opts = opts or {}
    local Rg = ns.ProfRecipes and ns.ProfRecipes[slug]
    local LV = ns.ProfLeveling and ns.ProfLeveling[slug]
    if not (Rg and type(Rg.rows) == "table") then return nil end
    local soldSet = {}
    if LV and type(LV.sold) == "table" then
        for _, id in ipairs(LV.sold) do soldSet[id] = true end
    end
    local recOf = {}
    for _, rec in ipairs(Rg.rows) do recOf[rec[1]] = rec end
    if LV and type(LV.rinfo) == "table" then
        for spell, ri in pairs(LV.rinfo) do
            if not recOf[spell] then recOf[spell] = ri end
        end
    end
    local total, crafts, list, firstAt, vendorTotal, formulas, formulasTotal,
          productAH, productNPC, productPartial =
        SummarizeCore(steps, recOf, soldSet, opts.learnedOnly)
    return {
        steps = steps, mats = list, firstAt = firstAt,
        matTotal = total, formulas = formulas, formulasTotal = formulasTotal,
        total = total + formulasTotal, vendorTotal = vendorTotal,
        ahTotal = total - vendorTotal,   -- 拍卖行购入 = 材料 − 商人直售
        productAH = productAH, productNPC = productNPC, productPartial = productPartial,
        crafts = crafts,
        priced = RA.HasPriceData(),
        snapshotAge = SnapshotSec(),
        snapshotDays = priceCache.__minAge,
        stamp = time and time() or 0,
    }
end

-- ── 对外入口 ────────────────────────────────────────────────────────────────
-- Compute(slug, opts) → result | nil
-- result = { steps, gaps, mats, firstAt, total, matTotal, formulas, formulasTotal,
--            vendorTotal, ahTotal, crafts, start, target, stamp, priced, filled }
-- steps[i] = {起, 止, spellID, 次数, cost=…, item=…, unpriced=…, est=…}
--   est=true = 缺口回填段：配方含无价材料，花费按已估价材料估算（未知按 0）
--   total = 材料 + 图纸；分类合计：ahTotal（拍卖行）/ vendorTotal（商人直售）/ formulasTotal（图纸）
--           三者相加 = total，购物清单金币卡的三行明细直接用。

-- ▸ 止点口径统一（2026-10-09，用户点名「42-59 其实升到 60 那一点也是这个配方做的，
--   所以需要改成 42-60」）：Simulate 内部存的是**最后能做的技能值**（段末 to），
--   而固定路线（Data_ProfLeveling）的段存的是**练到的技能值**（1–36 / 36–45 首尾相接）。
--   同一张表由 ProfessionUI 同时渲染两种路线 ⇒ 口径必须一致，否则固定路线数字相邻、
--   自动路线数字重叠错位。故**对外（专业页 / HUD）一律 +1** 转成「练到的技能值」。
--   段次数 qty 的积分本来就含段末那一点（qty == Σ 1/P over [from, to]），
--   所以止点显示 to+1 与 qty 自洽 —— 这正是用户要的那个 60。
--   ⚠️ 内部判据（MergeSteps / FillGaps 的 `last[2] + 1 == from`、衔接性、coverTo）
--   必须继续吃「最后能做」口径，转换只发生在最后一次浅拷贝上，两者互不影响。
local function ToReached(steps)
    if type(steps) ~= "table" then return steps end
    local out = {}
    for i, st in ipairs(steps) do
        local c = {}
        for k, v in pairs(st) do c[k] = v end
        c[2] = (tonumber(st[2]) or 0) + 1
        out[i] = c
    end
    return out
end

function RA.Compute(slug, opts)
    opts = opts or {}
    local cands, recOf, soldSet = BuildCandidates(slug, opts)
    if not cands then return nil end
    -- 「只用拍卖行可购材料」= 严格模拟（无价配方不参与）；产生的缺口随后放宽回填
    -- 方案（2026-10-10）：未传/非法 = 最省钱（产品默认；调用方不传也拿到新口径）
    local scheme = opts.scheme
    if scheme == nil or not SCHEME_LABEL[scheme] then scheme = "cheapest" end
    -- 目标等级上限（2026-10-09 v2）：opts.target（如 200）→ 模拟与回填都 clamp 在内
    local cap = tonumber(opts.target) or CAP
    cap = math.max(2, math.min(CAP, math.floor(cap)))
    local steps, gaps = Simulate(cands, opts.start, cap, allowUnpriced, scheme)
    local filled = false
    if not allowUnpriced and #gaps > 0 then
        steps, gaps = FillGaps(cands, steps, gaps, scheme)
        for _, st in ipairs(steps) do
            if st.est then filled = true break end
        end
    end
    -- 乐观计数（2026-10-10）：段花费改用材料卖店基础价值合计 —— 市价口径不适用
    --   （参考口径「只用来挑配方，不写价格」；这里给出量级，页面标注估算）
    if scheme == "optim" then
        local bySpell = {}
        for _, c in ipairs(cands) do bySpell[c.spell] = c end
        for _, st in ipairs(steps) do
            local c = bySpell[st[3]]
            if c then st.cost = (c.base or 0) * (st[4] or 0) end
        end
    end
    local total, crafts, mats, firstAt, vendorTotal, formulas, formulasTotal,
          productAH, productNPC, productPartial =
        SummarizeCore(steps, recOf, soldSet, opts.learnedOnly)
    return {
        scheme = scheme,
        steps = ToReached(steps), gaps = gaps, mats = mats, firstAt = firstAt,
        total = total + formulasTotal, matTotal = total,
        formulas = formulas, formulasTotal = formulasTotal,
        vendorTotal = vendorTotal, ahTotal = total - vendorTotal,
        productAH = productAH, productNPC = productNPC, productPartial = productPartial,
        crafts = crafts,
        start = math.max(1, math.min(CAP - 1, opts.start or 1)),
        target = cap,
        priced = RA.HasPriceData(),
        filled = filled,
        snapshotAge = SnapshotSec(),         -- 秒：真实扫描时间戳（TimeOfLast*Scan）
        snapshotDays = priceCache.__minAge,  -- 天：价格插件库内最近数据日差（回退用）
        stamp = time and time() or 0,
    }
end

-- 缓存（失效：RA.Invalidate() / 设置变更 / 手动重算 / 超时）
local cache = {}

function RA.Invalidate()
    for k in pairs(cache) do cache[k] = nil end
    for k in pairs(priceCache) do
        if k ~= "__any" then priceCache[k] = nil end
    end
    priceCache.__any = nil
end

local function Fingerprint(opts)
    return string.format("%s|%s|%s|%s|%s|%s",
        tostring(opts.start), tostring(opts.onlyAH),
        tostring(opts.noFormula), tostring(opts.learnedOnly),
        tostring(opts.target and math.floor(tonumber(opts.target) or CAP)),
        tostring(opts.scheme))
end

-- Get(slug, opts) → result | nil（带缓存）
function RA.Get(slug, opts)
    opts = opts or {}
    local fp = Fingerprint(opts)
    local c = cache[slug]
    local now = (type(time) == "function") and time() or 0
    if c and c.fp == fp and (now - c.stamp) < CACHE_TTL then return c.res end
    local res = RA.Compute(slug, opts)
    cache[slug] = { fp = fp, res = res, stamp = now }
    return res
end
