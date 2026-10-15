-- 每个职业的推荐升级加点（10-07 用户「每个职业先去网上找一套升级点的路线」「作为默认」）：
--   没导入配点码、或导入的码不是本职业时，升级规划页就按这套逐点排，不再显示「还没有天赋计划」。
-- 10-11 玩家「我是熊 D，天赋页推荐的是野德（猫），怎么换？」→ 每职业可以有多套（DefaultBuildsData[cls].builds，第 1 套 = 默认）：
--   选哪套：本角色手动选过的（按角色记，ns.db.buildPick）> 按当前投点最多的系自动挑主系一样的那套 > 第 1 套。
--   猫 / 熊都是野性系 → 点了野性默认仍是猫，玩家切到熊后记住。
-- 数据 = DefaultBuildsData.lua 生成的 { key, role, tree, spec, specCn, src, url, order = { { "树英文名", "天赋英文名" }, … } }
--   order 是攻略里的逐点顺序（第 1 条 = 10 级那一点），天赋按英文名在运行时对到《无限》的树上（ns.Data.talents）；
--   对不上的（《无限》删 / 改名了）跳过并记进 missing，测试会报出来。
local _, ns = ...

local cache = {}
local session = {}   -- 看别的职业时临时选的（不存档）

-- 按英文名找格子：先在同名树里找，找不到再全职业三棵树里找（攻略树名偶尔写别名）
local function locate(trees, treeName, talentName)
    local function inTree(ti)
        for i, t in ipairs(trees[ti].t) do
            if t.n == talentName then return ti, i end
        end
    end
    for ti, tr in ipairs(trees) do
        if tr.n == treeName then local a, b = inTree(ti); if a then return a, b end end
    end
    for ti in ipairs(trees) do local a, b = inTree(ti); if a then return a, b end end
end

local function myClass()
    if not UnitClass then return "" end   -- 网站导出（lupa）里没有游戏 API
    local _, token = UnitClass("player")
    token = token or ""
    return token:sub(1, 1) .. token:sub(2):lower()
end
local function charKey()
    return (UnitName and UnitName("player") or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "")
end

-- 本职业全部推荐方案（老数据只有一套：顶层字段当唯一一套）
function ns.DefaultBuilds(cls)
    local d = ns.DefaultBuildsData and ns.DefaultBuildsData[cls]
    if not d then return {} end
    if d.builds and #d.builds > 0 then return d.builds end
    return { d }
end

-- 当前角色投点最多的系（自己职业才读得到；没点 → nil）
local function myMainTree()
    if not (ns.CurrentTalentCode and ns.ParseTalentCode) then return nil end
    local ok, code = pcall(ns.CurrentTalentCode)
    local plan = ok and code and ns.ParseTalentCode(code)
    if not plan or (plan.total or 0) == 0 then return nil end
    local best, bp = nil, 0
    for ti, row in ipairs(plan.pts) do
        local s = 0
        for _, v in ipairs(row) do s = s + v end
        if s > bp then best, bp = ti, s end
    end
    return best
end

-- 选哪套 → key
function ns.DefaultBuildKey(cls)
    local L = ns.DefaultBuilds(cls)
    if #L == 0 then return nil end
    local function has(k) for _, b in ipairs(L) do if b.key == k then return true end end end
    if cls == myClass() then
        local p = ns.db and ns.db.buildPick and ns.db.buildPick[charKey()]
        if p and p[cls] and has(p[cls]) then return p[cls] end
        local mt = myMainTree()
        if mt then for _, b in ipairs(L) do if b.tree == mt then return b.key end end end
    elseif session[cls] and has(session[cls]) then
        return session[cls]
    end
    return L[1].key
end

-- 手动切换：自己职业按角色存档，别的职业只记这次
function ns.SetDefaultBuild(cls, key)
    if cls == myClass() then
        ns.db.buildPick = ns.db.buildPick or {}
        local ck = charKey()
        ns.db.buildPick[ck] = ns.db.buildPick[ck] or {}
        ns.db.buildPick[ck][cls] = key
    else
        session[cls] = key
    end
end

-- → plan { cls, key, role, pts, total, order = { {ti, i}, … }, default = true, spec, specCn, src, url, missing = { … } } 或 nil
--   key 不传 = 按 ns.DefaultBuildKey 选
function ns.DefaultPlan(cls, key)
    key = key or ns.DefaultBuildKey(cls)
    local ck = cls .. ":" .. tostring(key)
    if cache[ck] ~= nil then return cache[ck] or nil end
    local d
    for _, b in ipairs(ns.DefaultBuilds(cls)) do if b.key == key or (key == nil) then d = b; break end end
    d = d or ns.DefaultBuilds(cls)[1]
    local trees = ns.Data and ns.Data.talents and ns.Data.talents[cls]
    if not d or not trees then cache[ck] = false; return nil end
    local pts, order, missing, total = {}, {}, {}, 0
    for ti, tr in ipairs(trees) do pts[ti] = {}; for i in ipairs(tr.t) do pts[ti][i] = 0 end end
    for _, o in ipairs(d.order or {}) do
        local ti, i = locate(trees, o[1], o[2])
        if ti and pts[ti][i] < trees[ti].t[i].m and total < 51 then
            pts[ti][i] = pts[ti][i] + 1
            order[#order + 1] = { ti, i }
            total = total + 1
        else
            missing[#missing + 1] = o[2]
        end
    end
    if total == 0 then cache[ck] = false; return nil end
    local plan = { cls = cls, key = d.key, role = d.role, pts = pts, total = total, order = order, default = true,
        spec = d.spec, specCn = d.specCn, src = d.src, url = d.url, missing = missing, adjusted = d.adjusted or 0,
        nBuilds = #ns.DefaultBuilds(cls) }
    cache[ck] = plan
    return plan
end

ns.ROLE_NAME = { dps = { "输出", "DPS" }, tank = { "坦克", "Tank" }, healer = { "治疗", "Healer" } }
