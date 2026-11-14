-- 《无限》天赋读法（11-07）：开服客户端没有经典 GetNumTalents / GetTalentInfo / UnitCharacterPoints（/gi talentprobe 实测全是 nil，
--   C_ClassTalents.GetActiveConfigID 有值）→ 插件「读我的天赋」、按主系自动选默认加点、升级规划进度、tp 众包观测全部读到空。
-- 这里统一用 C_Traits 读本职业天赋节点，对到 Data.lua 的天赋格（ns.Data.talents[职业][系].t[i] 的 r / col）：
--   1. 按坐标：和 scripts/gi_forever_talents_trait.py 同一套换算（X 三段 1020 / 5020 / 9080 起、列距 600；Y 2130 起每 600 一行；
--      客户端个别坐标多一个 0 → 大于 20000 先除以 10）
--   2. 坐标对不上的按法术名（中文 / 英文）兜底
-- 全部 pcall 护住；接口不存在 = 返回 nil，调用方照旧走经典读法。
local _, ns = ...

local function num(v) return tonumber(v) or 0 end
local function classKey()
    local _, token = UnitClass("player")
    token = token or ""
    return token:sub(1, 1) .. token:sub(2):lower()
end

-- 11-13 重构第 4 期：整份天赋树（带说明文字 / 图标，DataClass.lua）随职业子插件 GearInsight_Forever_Class 按需加载；
--   内核里只有 TalentIndexData.lua 的「骨架」（行 / 列 / 满点 / 中英文名，顺序和整份一样）。登录就要的配点码读法都走这里：
--   _Class 加载了 → 用整份；没加载 → 把骨架展开成同样字段名的表（r / col / m / c / n；系的 n / c），按职业缓存。
--   ⛔ rawget：别为了读骨架去碰 ns.Data.talents（那个字段没加载时一读就会去加载 _Class）
local expanded = {}
function ns.TalentTrees(cls)
    local full = type(ns.Data) == "table" and rawget(ns.Data, "talents")
    if full then return full[cls] end
    local e = expanded[cls]
    if e ~= nil then return e or nil end
    local src = ns.TalentIdx and ns.TalentIdx[cls]
    if not src then expanded[cls] = false; return nil end
    e = {}
    for ti, tr in ipairs(src) do
        local t = {}
        for i, c in ipairs(tr[3]) do t[i] = { r = c[1], col = c[2], m = c[3], c = c[4], n = c[5] } end
        e[ti] = { n = tr[1], c = tr[2], t = t }
    end
    expanded[cls] = e
    return e
end

local function activeConfig()
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo) then return nil end
    local ok, cfg = pcall(C_ClassTalents.GetActiveConfigID)
    return ok and cfg or nil
end

local function configTrees(cfg)
    local ok, info = pcall(C_Traits.GetConfigInfo, cfg)
    if not ok or type(info) ~= "table" or type(info.treeIDs) ~= "table" then return {} end
    return info.treeIDs
end

local function spellName(sid)
    if not sid or sid == 0 then return nil end
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, sid)
        if ok then return n end
    end
    if GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, sid)
        if ok then return n end
    end
end

local function nodeSpell(cfg, ni)
    local eid = (type(ni.activeEntry) == "table" and ni.activeEntry.entryID) or (type(ni.entryIDs) == "table" and ni.entryIDs[1]) or nil
    if not (eid and C_Traits.GetEntryInfo and C_Traits.GetDefinitionInfo) then return nil end
    local ok, ei = pcall(C_Traits.GetEntryInfo, cfg, eid)
    if not ok or type(ei) ~= "table" or not ei.definitionID then return nil end
    local ok2, di = pcall(C_Traits.GetDefinitionInfo, ei.definitionID)
    return ok2 and type(di) == "table" and tonumber(di.spellID) or nil
end

local BASE = { 1020, 5020, 9080 }
local function fixc(v) return v > 20000 and v / 10 or v end
-- 坐标 → 系 / 行 / 列（和生成器一致）
function ns.TraitCellOf(x, y)
    x, y = fixc(num(x)), fixc(num(y))
    local t = x < 4000 and 1 or (x < 8500 and 2 or 3)
    local col = math.floor((x - BASE[t]) / 600 + 0.5) + 1
    local row = math.floor((y - 2130) / 600 + 0.5) + 1
    return t, row, col
end

-- 本职业天赋格实况：cells[系]["行:列"] = { rank, max, name, node }；读不到 = nil
function ns.TraitCells()
    local cfg = activeConfig()
    if not cfg or not C_Traits.GetTreeNodes or not C_Traits.GetNodeInfo then return nil end
    local trees = ns.TalentTrees(classKey())
    if not trees then return nil end
    local byName = {}
    for ti, tr in ipairs(trees) do
        for _, t in ipairs(tr.t or {}) do
            if t.c then byName[t.c] = byName[t.c] or { ti, t.r, t.col } end
            if t.n then byName[t.n] = byName[t.n] or { ti, t.r, t.col } end
        end
    end
    local function hasCell(ti, r, c)
        for _, t in ipairs((trees[ti] or {}).t or {}) do
            if t.r == r and t.col == c then return true end
        end
    end
    local cells, seen = { {}, {}, {} }, 0
    for _, tree in ipairs(configTrees(cfg)) do
        local ok, nodes = pcall(C_Traits.GetTreeNodes, tree)
        for _, nid in ipairs((ok and type(nodes) == "table") and nodes or {}) do
            local ok2, ni = pcall(C_Traits.GetNodeInfo, cfg, nid)
            if ok2 and type(ni) == "table" and num(ni.ID) ~= 0 and num(ni.maxRanks) > 0 then
                local rank = num(ni.activeRank)
                if rank == 0 then rank = num(ni.ranksPurchased) end
                local ti, r, c = ns.TraitCellOf(ni.posX, ni.posY)
                local name
                if not hasCell(ti, r, c) then
                    name = spellName(nodeSpell(cfg, ni))
                    local p = name and byName[name]
                    if p then ti, r, c = p[1], p[2], p[3] else ti = nil end
                end
                if ti then
                    local key = r .. ":" .. c
                    local old = cells[ti][key]
                    -- 客户端有坏坐标的重复孤儿节点：同一格取点数多的那个
                    if not old or rank > old.rank then
                        cells[ti][key] = { rank = rank, max = num(ni.maxRanks), name = name, node = nid }
                    end
                    seen = seen + 1
                end
            end
        end
    end
    if seen == 0 then return nil end
    return cells
end

-- 当前配点 → GIF2 码 + 总点数（和 ParseTalentCode / 小程序 / 网站同一格式）；读不到 = nil
function ns.TraitTalentCode()
    local cells = ns.TraitCells()
    if not cells then return nil end
    local cls = classKey()
    local trees = ns.TalentTrees(cls)
    if not trees then return nil end
    local parts, total = {}, 0
    for ti, tr in ipairs(trees) do
        local s = {}
        for i, t in ipairs(tr.t) do
            local cell = cells[ti][t.r .. ":" .. t.col]
            local r = cell and math.min(cell.rank, t.m, 9) or 0
            s[i] = tostring(r)
            total = total + r
        end
        parts[ti] = table.concat(s)
    end
    return "GIF2." .. cls .. "." .. table.concat(parts, "-"), total
end

-- 还没分的天赋点：经典 UnitCharacterPoints 有就用；否则 C_Traits 本职业树货币余额；再不行按「等级 - 9 - 已点」估
function ns.UnspentTalentPoints()
    if UnitCharacterPoints then
        local ok, p = pcall(UnitCharacterPoints, "player")
        if ok and type(p) == "number" then return p end
    end
    local cfg = activeConfig()
    if cfg and C_Traits.GetTreeCurrencyInfo then
        local n, got = 0, false
        for _, tree in ipairs(configTrees(cfg)) do
            local ok, list = pcall(C_Traits.GetTreeCurrencyInfo, cfg, tree, false)
            if ok and type(list) == "table" and type(list[1]) == "table" then
                n = n + num(list[1].quantity); got = true
            end
        end
        if got then return n end
    end
    local _, total = ns.TraitTalentCode()
    if not total then return 0 end
    local lv = UnitLevel and UnitLevel("player") or 0
    return math.max(0, math.min(51, lv - 9) - total)
end

-- 解析配点码 → { cls=, pts={ {..}, {..}, {..} } } 或 nil, 原因（11-13 第 4 期从 Talents.lua 挪来：只要天赋树骨架）
function ns.ParseTalentCode(code)
    code = tostring(code or ""):gsub("%s+", "")
    if code:match("^GIF1%.") then
        return nil, ns.L("这是开服前的配点码，天赋树已经改了，请到小程序或网站重新生成（GIF2 开头）",
            "This is a pre-launch build code and the talent trees have changed; make a new one (starts with GIF2)")
    end
    local cls, body = code:match("^GIF2%.(%a+)%.(.+)$")
    if not cls then return nil, ns.L("不是配点码（应以 GIF2. 开头）", "Not a build code (should start with GIF2.)") end
    local trees = ns.TalentTrees(cls)
    if not trees then return nil, ns.L("不认识的职业：", "Unknown class: ") .. cls end
    local parts = {}
    for p in (body .. "-"):gmatch("([^%-|]*)[%-|]") do parts[#parts + 1] = p end
    local pts, total = {}, 0
    for ti, tr in ipairs(trees) do
        local s = parts[ti] or ""
        pts[ti] = {}
        for i, t in ipairs(tr.t) do
            local v = tonumber(s:sub(i, i)) or 0
            if v > t.m then v = t.m end
            pts[ti][i] = v
            total = total + v
        end
    end
    if total > 51 then return nil, ns.L("点数超过 51", "More than 51 points") end
    return { cls = cls, pts = pts, total = total, v = 2 }
end

-- 当前角色投点最多的系（自己职业才读得到；没点 → nil）。11-13 第 4 期从 DefaultBuilds.lua 挪来：
--   推荐装备按天赋（_Plan 的 SpecGear.lua）、攻略页默认专精要用，不该为了它加载 _Class
local function myClass()
    if not UnitClass then return "" end   -- 网站导出（lupa）里没有游戏 API
    local _, token = UnitClass("player")
    token = token or ""
    return token:sub(1, 1) .. token:sub(2):lower()
end
function ns.MyMainTree()
    if not (ns.CurrentTalentCode and ns.ParseTalentCode) then return nil end
    local ok, code = pcall(ns.CurrentTalentCode)
    local plan = ok and code and ns.ParseTalentCode(code)
    if not plan or (plan.total or 0) == 0 then return nil end
    if plan.cls and plan.cls ~= myClass() then return nil end   -- 不是本职业的码（读错 / 测试）不算
    local best, bp = nil, 0
    for ti, row in ipairs(plan.pts) do
        local s = 0
        for _, v in ipairs(row) do s = s + v end
        if s > bp then best, bp = ti, s end
    end
    return best
end

-- 天赋变化事件：经典 CHARACTER_POINTS_CHANGED 在《无限》不发 → 各模块注册这一组
ns.TALENT_EVENTS = { "CHARACTER_POINTS_CHANGED", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE" }
function ns.IsTalentEvent(e)
    return e == "CHARACTER_POINTS_CHANGED" or e == "TRAIT_CONFIG_UPDATED" or e == "PLAYER_TALENT_UPDATE"
end
