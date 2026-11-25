-- 价格层（11-12，docs/forever-profession-assistant-design.md 第 11 节）：给「专业路线按什么价算」一个统一的问价口
--   ns.Prices.Get(物品) => 价格（铜）, 来源, 时间戳, 样本数      没有任何来源知道这个物品 => nil
--   来源按优先级问，可插拔（RegisterProvider）：
--     10 scan    拍卖行扫描价   来源码 "a"   现在还没有扫描器，只有存档结构和写入口 SetScan
--     20 manual  玩家手填       来源码 "m"   SetManual
--     30 bundle  随包估算价     来源码 "v" 商人买价 / "l" 限量商人货 / "c" 按制作折算 / "e" 卖店价估算（ProfSolve.lua 解码候选集后注册）
--   存档 GearInsightForeverDB.prices（账号级），按「服务器-阵营」分桶：
--     { v = 1, realms = { ["服务器-阵营"] = { scan = { [物品] = { 价, 样本数, 时间 } }, manual = { [物品] = { 价, 时间 } }, scanAt = 最近一次扫描 } } }
--   过期：扫描价超过 SCAN_TTL 不再采用（退回下一个来源），超过 SCAN_PURGE 登录时清掉；手填不过期。
-- 只读存档、不建框体、不注册事件，内核和任何模块都能直接用；没有数据时 Get 就是几次查表。
local _, ns = ...

local M = {}
ns.Prices = M

M.VERSION = 1
M.SCAN_TTL = 7 * 86400        -- 扫描价 7 天内算新
M.SCAN_PURGE = 30 * 86400     -- 30 天以上的扫描价清掉
M.ORDER = { scan = 10, manual = 20, bundle = 30 }

local providers = {}          -- { name, order, fn }，按 order 从小到大
local listeners = {}
local batch, dirty = 0, false

local function now() return (time and time()) or 0 end

-- 现在这个角色的桶名。取不到服务器名（登录太早）时返回 nil，读写都跳过
function M.Bucket()
    local realm = GetRealmName and GetRealmName() or nil
    if not realm or realm == "" then return nil end
    local fac = UnitFactionGroup and UnitFactionGroup("player") or nil
    return realm .. "-" .. (fac or "Neutral")
end

-- 旧版本存档升到当前版本。现在只有 v1；以后改结构在这里按版本一步步升
function M.Migrate(db)
    if type(db) ~= "table" then return { v = M.VERSION, realms = {} } end
    local v = tonumber(db.v) or 0
    if v < 1 then
        -- v0（没有版本号的草稿结构：直接 { [桶] = { scan, manual } }）=> v1
        local realms = type(db.realms) == "table" and db.realms or {}
        for k, b in pairs(db) do
            if k ~= "v" and k ~= "realms" and type(b) == "table" and (b.scan or b.manual) then
                realms[k] = realms[k] or b
                db[k] = nil
            end
        end
        db.realms = realms
        db.v = 1
    end
    if type(db.realms) ~= "table" then db.realms = {} end
    if db.v > M.VERSION then
        -- 存档比插件新（回退了插件版本）：不认识的结构不动它，只保证读写不报错
        db.realms = type(db.realms) == "table" and db.realms or {}
    end
    return db
end

-- 存档根。create = false 时没有就返回 nil（只读路径不往存档里塞空表）
local function root(create)
    local db = rawget(_G, "GearInsightForeverDB")
    if type(db) ~= "table" then return nil end
    local p = db.prices
    if type(p) ~= "table" then
        if not create then return nil end
        p = { v = M.VERSION, realms = {} }
        db.prices = p
    elseif p.v ~= M.VERSION or type(p.realms) ~= "table" then
        p = M.Migrate(p)
        db.prices = p
    end
    return p
end

local function bucket(create, key)
    key = key or M.Bucket()
    if not key then return nil end
    local p = root(create)
    if not p then return nil end
    local b = p.realms[key]
    if type(b) ~= "table" then
        if not create then return nil end
        b = { scan = {}, manual = {} }
        p.realms[key] = b
    end
    if type(b.scan) ~= "table" then b.scan = {} end
    if type(b.manual) ~= "table" then b.manual = {} end
    return b
end

-- ---------- 来源 ----------
-- fn(物品) => 价格, 来源码, 时间戳, 样本数；不知道返回 nil。同名再注册 = 替换
function M.RegisterProvider(name, order, fn)
    for i = #providers, 1, -1 do
        if providers[i].name == name then table.remove(providers, i) end
    end
    if fn then
        providers[#providers + 1] = { name = name, order = order or 100, fn = fn }
        table.sort(providers, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return a.name < b.name
        end)
    end
end

function M.Providers()
    local out = {}
    for i, p in ipairs(providers) do out[i] = p.name end
    return out
end

M.RegisterProvider("scan", M.ORDER.scan, function(item)
    local b = bucket(false)
    local e = b and b.scan[item]
    if type(e) ~= "table" or not e[1] or e[1] <= 0 then return nil end
    if now() - (e[3] or 0) > M.SCAN_TTL then return nil end
    return e[1], "a", e[3], e[2]
end)

M.RegisterProvider("manual", M.ORDER.manual, function(item)
    local b = bucket(false)
    local e = b and b.manual[item]
    if type(e) ~= "table" or not e[1] or e[1] <= 0 then return nil end
    return e[1], "m", e[2], nil
end)

-- 问价。only = 只问某一个来源（"scan" / "manual" / "bundle"）
function M.Get(item, only)
    if not item then return nil end
    for _, p in ipairs(providers) do
        if not only or p.name == only then
            local price, src, ts, n = p.fn(item)
            if price then return price, src, ts, n end
        end
    end
    return nil
end

-- 给求解器用的价格函数：返回 价格, 来源码（没有价格返回 nil）
function M.Fn()
    return function(item)
        local price, src = M.Get(item)
        return price, src
    end
end

-- ---------- 回调 ----------
-- fn(物品, 价格, 来源码)；批量写完只通知一次（物品 = nil）
function M.OnChange(fn)
    if type(fn) == "function" then listeners[#listeners + 1] = fn end
end

local function fire(item, price, src)
    if batch > 0 then dirty = true return end
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, item, price, src)
        if not ok and ns.Debug then ns.Debug("Prices listener: " .. tostring(err)) end
    end
end

function M.BeginBatch() batch = batch + 1 end
function M.EndBatch()
    if batch > 0 then batch = batch - 1 end
    if batch == 0 and dirty then
        dirty = false
        fire(nil, nil, nil)
    end
end

-- ---------- 写入 ----------
-- 扫描价写入口（给以后的拍卖行扫描器 / 众包下发用）。price = 铜（单件），n = 样本数，ts = 扫描时间（默认现在）
-- price = nil 或 0 => 删掉这条。返回是否写进去了
function M.SetScan(item, price, n, ts)
    item, price = tonumber(item), tonumber(price)
    if not item then return false end
    local b = bucket(true)
    if not b then return false end
    if not price or price <= 0 then
        if b.scan[item] == nil then return false end
        b.scan[item] = nil
        fire(item, nil, "a")
        return true
    end
    ts = tonumber(ts) or now()
    b.scan[item] = { price, tonumber(n) or 1, ts }
    if ts > (b.scanAt or 0) then b.scanAt = ts end
    fire(item, price, "a")
    return true
end

-- 玩家手填。price = nil 或 0 => 清掉
function M.SetManual(item, price)
    item, price = tonumber(item), tonumber(price)
    if not item then return false end
    local b = bucket(true)
    if not b then return false end
    if not price or price <= 0 then
        if b.manual[item] == nil then return false end
        b.manual[item] = nil
        fire(item, nil, "m")
        return true
    end
    b.manual[item] = { price, now() }
    fire(item, price, "m")
    return true
end

-- 这个桶里有没有「不是随包估算」的价格（有 = 路线可以按真实价格重算）。返回 "a" / "m" / nil
function M.CustomKind()
    local b = bucket(false)
    if not b then return nil end
    local t = now()
    for _, e in pairs(b.scan) do
        if type(e) == "table" and t - (e[3] or 0) <= M.SCAN_TTL then return "a" end
    end
    if next(b.manual) ~= nil then return "m" end
    return nil
end

-- 最近一次扫描时间、扫描价条数（还新的）
function M.ScanInfo()
    local b = bucket(false)
    if not b then return nil, 0 end
    local t, n = now(), 0
    for _, e in pairs(b.scan) do
        if type(e) == "table" and t - (e[3] or 0) <= M.SCAN_TTL then n = n + 1 end
    end
    return b.scanAt, n
end

-- 清过期扫描价（所有桶）。登录后调一次就够；返回清了几条
function M.Purge()
    local p = root(false)
    if not p then return 0 end
    local t, n = now(), 0
    for _, b in pairs(p.realms) do
        if type(b) == "table" and type(b.scan) == "table" then
            for item, e in pairs(b.scan) do
                if type(e) ~= "table" or t - (e[3] or 0) > M.SCAN_PURGE then
                    b.scan[item] = nil
                    n = n + 1
                end
            end
        end
    end
    return n
end

-- 来源码 => 给人看的说法
function M.SourceText(src)
    if src == "a" then return ns.L("拍卖行扫描价", "auction scan") end
    if src == "m" then return ns.L("你填的价格", "your price") end
    if src == "v" then return ns.L("商人买价", "vendor price") end
    if src == "l" then return ns.L("限量商人货的买价", "limited vendor price") end
    if src == "c" then return ns.L("按制作材料折算", "from crafting cost") end
    return ns.L("按卖店价估算", "estimated from sell price")
end

-- 铜 => 「12金 34银 56铜」
function M.Money(c)
    c = math.floor((tonumber(c) or 0) + 0.5)
    local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    if g > 0 then
        return g .. ns.L("金", "g") .. (s > 0 and (" " .. s .. ns.L("银", "s")) or "")
    end
    if s > 0 then
        return s .. ns.L("银", "s") .. (k > 0 and (" " .. k .. ns.L("铜", "c")) or "")
    end
    return k .. ns.L("铜", "c")
end
