-- 11-05 猎人宠物「在哪抓」方案 c：开源数据（PetTameData.lua，经典旧世 1.12）打底 + 这里的游戏内众包校正。
-- 走 Obs 同一条通道（ns.Obs.Add → 掉落导出串 GIFD1 的 ob 字段 → 更新器上传，更新器不用发版），服务端 ≥2 台设备一致才采信：
--   bf 野兽目击  鼠标指向 / 选中一只有家族的野兽（UnitCreatureFamily 有值、不是玩家控制的）：
--                键 npcID → 值「家族名|等级|地图|x|y|稀有度|名字」（坐标 = 自己当时的位置，百分比一位小数；
--                家族名 / 名字 = 客户端语言的怪物名，不是玩家；稀有度 n 普通 / e 精英 / r 稀有 / R 稀有精英 / b 首领）
--                → 补《无限》新地区、新家族狐狸、等级 / 坐标改动、中文名。同一只怪本次登录只记一次。
--   tm 驯服结果  ⛔ 11-20 搬进猎人专属子插件 GearInsight_Forever_ClassHunter/HunterTame.lua（只有猎人加载），格式不变：
--                键 npcID → 值「家族名|驯服时目标等级|地图|x|y|宠物技能」，宠物技能 = 法术ID 逗号连（读不到 ID 用「名字:等级」）
--                → 新抓的宠物会的技能等级 = 这只野兽会教的，校正「哪只野兽教哪一级」。
--   rs 稀有目击  11-10 看板 GI-214「未标注泽风岛稀有怪」：网站稀有怪是经典旧世库，《无限》新地区（泽风岛等）一只没有 →
--                鼠标指向 / 选中稀有 / 稀有精英（任何生物类型，不只野兽）：键 npcID → 值「等级|地图|x|y|稀有度|名字|生物类型」
--                → scripts/gi_forever_rare_obs_build.py ≥2 台一致才进 rares_obs.json（网站野外稀有页「玩家实测」）。同一只本次登录只记一次。
-- ⛔ 不记角色名 / 服务器名 / 宠物自起名；保密值（ns.Secret）不记；bf 最多 BF_TOTAL 条，超了删最旧的。
-- ⛔ 每个 API 都 pcall / 判空（经典旧世引擎 1.60 客户端，接口可能缺）。⛔ 在 HOLD 里，游戏内验收完才进发行包。
-- 探针：/gi petobs（看记了多少条 + 最近一次驯服）
local _, ns = ...
-- 11-17 界面重构第 6a 期：功能开关「obs」—— 正文包成函数，读完存档关着就不跑（见 Features.lua 的 ns.FeatureDefer；正文没缩进是为了不动原有行）
local function body()

local P = {}
ns.ObsPet = P

P.BF_TOTAL = 300
P.RS_TOTAL = 200
P.seen = {}            -- 本次登录已记过的 npc（bf）
P.seenRare = {}        -- 本次登录已记过的稀有（rs）

local function clean(v)
    if v == nil or (ns.Secret and ns.Secret(v)) then return nil end
    return v
end
local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local r = { pcall(f, ...) }
    if not r[1] then return nil end
    return unpack(r, 2, table.maxn(r))
end
local function add(k, key, val)
    return ns.Obs and ns.Obs.Add and ns.Obs.Add(k, key, val) or false
end

-- GUID 里的生物 ID：野外怪是 Creature-…，宠物是 Pet-…（同样第 6 段是生物 ID）
local function npcOfGuid(guid)
    guid = clean(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Pet" and kind ~= "Vehicle" then return nil end
    id = tonumber(id)
    return id and id > 0 and id or nil
end
P.NpcOfGuid = npcOfGuid   -- 猎人专属子插件共用

local function pos()
    local W = ns.Obs and ns.Obs.WherePrecise
    if W then
        local ok, m, x, y = pcall(W)
        if ok and m then return m, x, y end
    end
    return 0, "", ""
end

local CLS = { elite = "e", rare = "r", rareelite = "R", worldboss = "b" }
local function clsOf(unit)
    local c = clean(call(UnitClassification, unit))
    return CLS[c or ""] or "n"
end

-- 只删某一类最旧的，别把训练师 / 采集 / 标价挤掉
function P.Trim(k, cap)
    local D = ns.db and ns.db.obs
    if not D then return 0 end
    local list = {}
    for id, r in pairs(D) do
        if r.k == k then list[#list + 1] = { id = id, t = r.t or 0 } end
    end
    if #list <= cap then return 0 end
    table.sort(list, function(a, b) return a.t < b.t end)
    local n = #list - cap
    for i = 1, n do D[list[i].id] = nil end
    return n
end

-- ---------- rs 稀有目击（任何生物类型）----------
function P.Rare(unit)
    local c = clsOf(unit)
    if c ~= "r" and c ~= "R" then return false end
    local npc = npcOfGuid(call(UnitGUID, unit))
    if not npc or P.seenRare[npc] then return false end
    P.seenRare[npc] = true
    local m, x, y = pos()
    local lv = tonumber(clean(call(UnitLevel, unit))) or 0
    local name = clean(call(UnitName, unit)) or ""
    local ct = clean(call(UnitCreatureType, unit)) or ""
    local okAdd = add("rs", tostring(npc), table.concat({ lv, m, x, y, c, tostring(name):sub(1, 40), tostring(ct):sub(1, 16) }, "|"))
    P.Trim("rs", P.RS_TOTAL)
    return okAdd
end

-- ---------- bf 野兽目击 ----------
function P.Sight(unit)
    if not unit or not call(UnitExists, unit) then return false end
    if call(UnitIsPlayer, unit) or call(UnitPlayerControlled, unit) then return false end
    P.Rare(unit)
    local fam = clean(call(UnitCreatureFamily, unit))
    if not fam or fam == "" then return false end
    local npc = npcOfGuid(call(UnitGUID, unit))
    if not npc or P.seen[npc] then return false end
    P.seen[npc] = true
    local m, x, y = pos()
    local lv = tonumber(clean(call(UnitLevel, unit))) or 0
    local name = clean(call(UnitName, unit)) or ""
    local okAdd = add("bf", tostring(npc), table.concat({ tostring(fam):sub(1, 20), lv, m, x, y, clsOf(unit), tostring(name):sub(1, 40) }, "|"))
    P.Trim("bf", P.BF_TOTAL)
    return okAdd
end

-- ---------- tm 驯服结果 ----------
-- 11-20 用户硬规「职业专属的只有这个职业才加载」：tm（猎人驯服结果）搬进猎人专属子插件 GearInsight_Forever_ClassHunter（HunterTame.lua），
--   只有猎人角色登录才加载（ClassStub.lua）；内核这里只留所有职业都能记的 bf 野兽目击 / rs 稀有目击。

local function count(k)
    local n = 0
    for _, r in pairs((ns.db and ns.db.obs) or {}) do
        if r.k == k then n = n + 1 end
    end
    return n
end

function P.Probe(rest)
    ns.Print(string.format(ns.L("宠物众包：野兽目击 %d 条 · 驯服结果 %d 条", "Pet crowdsourcing: %d beast sightings · %d tames"), count("bf"), count("tm")))
    if ns.HunterProbe then pcall(ns.HunterProbe, rest) end   -- 猎人专属子插件（只有猎人加载）：驯服 / 施法 / 训练野兽
end

ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.petobs = function(rest) pcall(P.Probe, rest) end

table.insert(ns.modules, function()
    local f = CreateFrame("Frame")
    -- ⛔ 容错注册：客户端没有的事件名会报错
    for _, e in ipairs({ "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    ns._obsPetEvent = function(_, e, ...)
        if e == "UPDATE_MOUSEOVER_UNIT" then pcall(P.Sight, "mouseover")
        elseif e == "PLAYER_TARGET_CHANGED" then pcall(P.Sight, "target")
        end
    end
    f:SetScript("OnEvent", ns._obsPetEvent)
end)
end
if ns.FeatureDefer then ns.FeatureDefer("obs", body) else body() end
