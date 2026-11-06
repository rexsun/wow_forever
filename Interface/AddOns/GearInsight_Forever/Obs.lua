-- 10-22 GI-14「专业冲级 × 升级路线：实测校准」→ 通用游戏内观测（众包）
-- 用户：「咱们的优势就是有更新器的众包能力，帮我充分利用」。客户端数据里没有、只能在游戏里看到的东西，在这里记下来，
-- 随掉落导出串（GIFD1 的 ob 字段）由更新器上传；服务端按 (类型, 键, 值) 数不同设备，≥2 个一致才进数据（forever_beta.py）。
--   pt 训练师  打开任意训练师窗口：每一项要几点技能 / 几级 / 多少钱（专业 + 职业训练师都记）   pn = 训练师在哪
--   pg 采集    采草 / 挖矿 / 剥皮 成功（记当时技能，= 需求上限）或失败（记提示里的需求点数）
--   pl 学档位  专业上限变高的那一刻：角色几级、技能多少（档位到底看不看角色等级）
--   pc 营地    放营火 / 设施成功或失败（失败记提示原文）；pr = 不在旅店时休息经验变多了多少（帐篷）
--   lg 传承    系统消息里出现传承：记当时各专业技能（150 / 225 / 300 给点的说法核对）
--   tl 天赋树  本职业每一格的名字 / 最高等级（不依赖第三方）；tp = 每升一级时的配点码（真实玩家怎么点）
--   gn 点位    11-05 用户「矿点等各种点位上插件，要众包的」：采草 / 挖矿成功、或从地上的物体拿东西（宝箱、箱子、可拾取物）时，
--              记精确到 0.1% 的坐标。键「种类:物体ID:地图」（物体 ID 从拾取来源 GUID 取，不分语言；拿不到 ID 时用名字「种类:n名字:地图」），
--              值「x:y」（百分比一位小数）。种类 = herb 草药 / ore 矿 / go 其他地上物体。服务端把相距很近的报告聚成一个点，≥2 台设备才采信
-- ⛔ 不记角色名 / 服务器名；系统消息里带自己名字的不记。⛔ 存档最多 MAX 条，按 (k, key, val) 去重。
-- ⛔ 记录关了（/gif data off）照记本机，但不进导出串（Stats.lua WriteAutoExport 管）。
local _, ns = ...

local MAX = 800
local O = {}
ns.Obs = O

local function db()
    ns.db.obs = ns.db.obs or {}
    return ns.db.obs
end

local function clean(v)
    if v == nil or (ns.Secret and ns.Secret(v)) then return nil end
    return v
end

-- 键值都转成短字符串；同一条再见一次只加次数、更新时间
function O.Add(k, key, val)
    key, val = clean(key), clean(val)
    if not key then return false end
    key, val = tostring(key):sub(1, 120), tostring(val or ""):sub(1, 160)
    local D = db()
    local id = k .. "\1" .. key .. "\1" .. val
    local old = D[id]
    local now = time()
    if old then
        old.c, old.t = (old.c or 1) + 1, now
        return false
    end
    local n, oldestK, oldestT = 0, nil, math.huge
    for kk, v in pairs(D) do
        n = n + 1
        if (v.t or 0) < oldestT then oldestK, oldestT = kk, v.t or 0 end
    end
    if n >= MAX and oldestK then D[oldestK] = nil end
    D[id] = { k = k, key = key, v = val, c = 1, t = now }
    return true
end

function O.Export()
    local D = ns.db and ns.db.obs
    if not D then return nil end
    local out = {}
    for _, r in pairs(D) do out[#out + 1] = { k = r.k, key = r.key, v = r.v, c = r.c, t = r.t } end
    if #out == 0 then return nil end
    table.sort(out, function(a, b) return (a.t or 0) < (b.t or 0) end)
    return out
end

local function where()
    local m = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not m then return 0, 0, 0 end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
    if not ok or not pos then return m, 0, 0 end
    local x, y = pos:GetXY()
    return m, math.floor((x or 0) * 100 + 0.5), math.floor((y or 0) * 100 + 0.5)
end

local function unitNpc(unit)
    local guid = UnitGUID and clean(UnitGUID(unit))
    if not guid then return 0 end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return 0 end
    return tonumber(id) or 0
end

local function lv() return (UnitLevel and UnitLevel("player")) or 0 end

-- 各专业当前技能：Prof.lua 的读取（读不到就空）
local function skills()
    local P = ns.Prof
    if not (P and P.Skills) then return {} end
    local ok, s = pcall(P.Skills)
    return ok and type(s) == "table" and s or {}
end
local function skillOf(key)
    local s = skills()[key]
    return s and s.r or nil
end
local function skillLine()
    local s, out = skills(), {}
    for _, k in ipairs((ns.Prof and ns.Prof.ORDER) or {}) do
        if s[k] then out[#out + 1] = k .. "=" .. s[k].r .. "/" .. (s[k].m or 0) end
    end
    return table.concat(out, ",")
end

-- ---------- pt / pn 训练师 ----------
function O.Trainer()
    if not (GetNumTrainerServices and GetTrainerServiceInfo) then return 0 end
    local ok, n = pcall(GetNumTrainerServices)
    n = ok and tonumber(n) or 0
    local npc = unitNpc("npc")
    if n == 0 or npc == 0 then return 0 end
    local m, x, y = where()
    O.Add("pn", npc, m .. ":" .. x .. ":" .. y .. ":" .. (clean(UnitName and UnitName("npc")) or ""))
    local added = 0
    for i = 1, n do
        local ok2, name, sub, cat = pcall(GetTrainerServiceInfo, i)
        if ok2 and clean(name) and cat ~= "header" then
            local sname, srank
            if GetTrainerServiceSkillReq then
                local ok3, a, b = pcall(GetTrainerServiceSkillReq, i)
                if ok3 then sname, srank = clean(a), clean(b) end
            end
            local lvq = GetTrainerServiceLevelReq and select(2, pcall(GetTrainerServiceLevelReq, i))
            local cost = GetTrainerServiceCost and select(2, pcall(GetTrainerServiceCost, i))
            local key = npc .. "|" .. name .. ((sub and sub ~= "") and ("|" .. tostring(sub)) or "")
            if O.Add("pt", key, tostring(sname or "") .. ":" .. tostring(srank or "") .. ":" .. tostring(clean(lvq) or "") .. ":" .. tostring(clean(cost) or "")) then
                added = added + 1
            end
        end
    end
    return added
end

-- ---------- pg 采集（采草 / 挖矿 / 剥皮）----------
local GATHER = {}   -- 法术名（客户端语言）→ 专业键
local function spellName(id)
    if not id then return nil end
    if GetSpellInfo then return clean((GetSpellInfo(id))) end
    if C_Spell and C_Spell.GetSpellName then return clean(C_Spell.GetSpellName(id)) end
end
local function gatherKey(spellID)
    if not next(GATHER) then
        -- 10-29：客户端 70532 采草的法术叫「采集草药」（1235236 Herb Gathering），老的 2366 改名「草药学」；
        --   原来写的「草药采集」对不上 → 线上草药 pg 一条都没有（采矿 / 剥皮正常）。几个名字都认。
        for _, p in ipairs({ { "herbalism", "采集草药", "Herb Gathering" }, { "herbalism", "草药采集", "Herbalism" }, { "herbalism", "草药学", "Herbalism" },
                             { "mining", "采矿", "Mining" }, { "skinning", "剥皮", "Skinning" } }) do
            GATHER[p[2]] = p[1]; GATHER[p[3]] = p[1]
        end
    end
    local name = spellName(spellID)
    return name and GATHER[name]
end

local pending   -- 正在采的那一下：{ key, target, npc, mlv, map, t }
local lastGather  -- 刚采成功的那一下（等拾取窗口拿物体 ID）：{ kind, name, map, x, y, t }

-- ---------- gn 精确点位 ----------
O.GN_TOTAL = 400   -- 点位最多留这么多条（Obs 存档 800 条各类共用），超了删最旧的点位
local function wherePrecise()
    local m = C_Map and C_Map.GetBestMapForUnit and clean(C_Map.GetBestMapForUnit("player"))
    if not m then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
    if not ok or not pos then return nil end
    local x, y = pos:GetXY()
    x, y = clean(x), clean(y)
    if not (x and y) or x <= 0 or y <= 0 or x >= 1 or y >= 1 then return nil end
    return m, string.format("%.1f", x * 100), string.format("%.1f", y * 100)
end
O.WherePrecise = wherePrecise
local function objectIdOf(guid)
    guid = clean(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "GameObject" then return nil end
    return tonumber(id)
end
O.ObjectIdOf = objectIdOf
function O.AddPoint(kind, idOrName, m, x, y)
    if not (kind and idOrName and m and x and y) then return false end
    local D = db()
    local list = {}
    for kk, v in pairs(D) do if v.k == "gn" then list[#list + 1] = { kk, v.t or 0 } end end
    if #list >= O.GN_TOTAL then
        table.sort(list, function(a, b) return a[2] < b[2] end)
        for i = 1, #list - O.GN_TOTAL + 1 do D[list[i][1]] = nil end   -- 删到留出一个空位
    end
    return O.Add("gn", kind .. ":" .. tostring(idOrName) .. ":" .. m, x .. ":" .. y)
end
local GN_KIND = { herbalism = "herb", mining = "ore" }
-- 拾取窗口打开：来源是地上的物体 → 记点位。刚采过草 / 矿（8 秒内）就归到草药 / 矿，否则算其他物体（宝箱等）
function O.LootOpened()
    if not GetLootSourceInfo then return false end
    local ok, guid = pcall(GetLootSourceInfo, 1)
    local id = ok and objectIdOf(guid)
    local g = lastGather
    lastGather = nil
    -- 拾取窗口比「施法成功」先到的客户端：还在采的那一下也算
    if not g and pending and GN_KIND[pending.key] and GetTime() - pending.t < 10 then
        local m, x, y = wherePrecise()
        if m then g = { kind = GN_KIND[pending.key], name = pending.target, map = m, x = x, y = y, t = GetTime() } end
        pending.gnDone = true   -- 这一下已经记过点位：随后到的「施法成功」别再留一份给下一次拾取
    end
    if g and GetTime() - g.t <= 8 then
        return O.AddPoint(g.kind, id or ("n" .. g.name), g.map, g.x, g.y)
    end
    if not id then return false end
    local m, x, y = wherePrecise()
    if not m then return false end
    return O.AddPoint("go", id, m, x, y)
end
local campPending

local function campNames()
    local out = {}
    local C = ns.ProfData and ns.ProfData.camp
    if not C then return out end
    for _, f in ipairs(C.fires or {}) do out[f.zh] = "fire"; out[f.en] = "fire" end
    for key, list in pairs(C.profs or {}) do
        for _, o in ipairs(list) do out[o.zh] = key; out[o.en] = key end
    end
    return out
end
local CAMP

function O.CastSent(unit, target, _, spellID)
    if unit ~= "player" then return end
    pending, campPending = nil, nil   -- 新的一下顶掉上一下：免得上一下的失败提示 / 成功记到这一下头上
    local key = gatherKey(spellID)
    if key then
        local npc, mlv = 0, 0
        if key == "skinning" then
            npc = unitNpc("target")
            mlv = (UnitLevel and clean(UnitLevel("target"))) or 0
        end
        local m, px, py = where()
        pending = { key = key, target = clean(target) or "?", npc = npc, mlv = mlv, map = m, px = px, py = py, t = GetTime() }
        return
    end
    CAMP = CAMP or campNames()
    local name = spellName(spellID)
    if name and CAMP[name] then campPending = { name = name, prof = CAMP[name], t = GetTime() } end
end

local function gatherId(p)
    -- 剥皮按怪 ID + 等级；草 / 矿按名字（客户端语言，服务端按语言分开汇总）+ 地图
    if p.key == "skinning" and p.npc > 0 then return "skin:" .. p.npc .. ":" .. p.mlv end
    return p.key .. ":" .. p.target .. ":" .. (GetLocale and GetLocale() or "") .. ":" .. p.map
end

function O.CastDone(unit, _, spellID)
    if unit ~= "player" then return end
    if pending and gatherKey(spellID) == pending.key then
        local s = skillOf(pending.key)
        if s and GetTime() - pending.t < 10 then
            O.Add("pg", gatherId(pending), "ok:" .. s)
            -- 10-29 采集点分布：草 / 矿成功时记一个 5% 网格坐标（at:x:y，同格只记一次；服务端 ≥2 台设备同格才采信）
            if pending.key ~= "skinning" and (pending.px or 0) > 0 and (pending.py or 0) > 0 then
                O.Add("pg", gatherId(pending), "at:" .. (math.floor(pending.px / 5) * 5) .. ":" .. (math.floor(pending.py / 5) * 5))
            end
        end
        -- 11-05 精确点位：等拾取窗口拿物体 ID（LootOpened）；不看技能读没读到；采完没开拾取窗口（背包满等）就不记
        if GetTime() - pending.t < 10 and GN_KIND[pending.key] and not pending.gnDone then
            local m, x, y = wherePrecise()
            if m then lastGather = { kind = GN_KIND[pending.key], name = pending.target, map = m, x = x, y = y, t = GetTime() } end
        end
        pending = nil   -- 超时的也清掉
        return
    end
    if campPending and GetTime() - campPending.t < 10 then
        local cook = skillOf("cooking") or ""
        local own = campPending.prof ~= "fire" and (skillOf(campPending.prof) or "") or cook
        O.Add("pc", campPending.name, "ok:" .. cook .. ":" .. own .. ":" .. lv())
        campPending = nil
    end
end

-- 失败提示里第一个数字 = 需求点数（「需要草药学 150」之类，具体措辞各语言不同，只取数字）
function O.UIError(_, msg)
    msg = clean(msg)
    if type(msg) ~= "string" then return end
    if pending and GetTime() - pending.t < 3 then
        local need = tonumber(msg:match("(%d+)"))
        if need then O.Add("pg", gatherId(pending), "need:" .. need .. ":" .. (skillOf(pending.key) or "")) end
        pending = nil
        return
    end
    if campPending and GetTime() - campPending.t < 3 then
        local me = UnitName and clean(UnitName("player"))
        if not (me and msg:find(me, 1, true)) then
            O.Add("pc", campPending.name, "err:" .. msg:sub(1, 80) .. ":" .. (skillOf("cooking") or "") .. ":" .. lv())
        end
        campPending = nil
    end
end

-- ---------- pl 学档位 ----------
function O.SkillsChanged()
    local s = skills()
    local D = ns.db
    D.obsMax = D.obsMax or {}
    local ck = (UnitGUID and clean(UnitGUID("player"))) or "?"   -- 只当本机键，不上传
    local mine = D.obsMax[ck] or {}
    for key, v in pairs(s) do
        local m = v.m or 0
        if mine[key] and m > mine[key] then
            O.Add("pl", key .. ":" .. m, lv() .. ":" .. (v.r or 0))
        end
        mine[key] = m
    end
    D.obsMax[ck] = mine
end

-- ---------- pr 休息经验（帐篷）----------
local lastRest
function O.Exhaustion()
    local r = GetXPExhaustion and clean(GetXPExhaustion()) or 0
    local maxXP = UnitXPMax and clean(UnitXPMax("player")) or 0
    if lastRest and r > lastRest and maxXP > 0 and not (IsResting and IsResting()) then
        O.Add("pr", "lv" .. lv(), string.format("%.1f", (r - lastRest) / maxXP * 100))
    end
    lastRest = r
end

-- ---------- lg 传承 ----------
function O.System(_, msg)
    msg = clean(msg)
    if type(msg) ~= "string" then return end
    if not (msg:find("传承", 1, true) or msg:find("Legacy", 1, true)) then return end
    local me = UnitName and clean(UnitName("player"))
    if me and msg:find(me, 1, true) then return end
    O.Add("lg", msg:sub(1, 100), skillLine() .. ";lv=" .. lv())
end

-- ---------- tl / tp 天赋 ----------
local function classToken() return select(2, UnitClass("player")) or "?" end
function O.TalentTree()
    if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return end
    local cls = classToken()
    local ok, tabs = pcall(GetNumTalentTabs)
    for ti = 1, (ok and tonumber(tabs) or 0) do
        local ok2, n = pcall(GetNumTalents, ti)
        for i = 1, (ok2 and tonumber(n) or 0) do
            local ok3, name, _, tier, col, _, maxRank = pcall(GetTalentInfo, ti, i)
            if ok3 and clean(name) and tier then
                O.Add("tl", cls .. ":" .. ti .. ":" .. tier .. ":" .. col, name .. ":" .. tostring(maxRank or ""))
            end
        end
    end
end
function O.TalentPicks()
    if not ns.CurrentTalentCode then return end
    local ok, code, total = pcall(ns.CurrentTalentCode)
    if ok and code and (total or 0) > 0 then O.Add("tp", classToken() .. ":" .. lv(), code) end
end

table.insert(ns.modules, function()
    local f = CreateFrame("Frame")
    -- ⛔ 事件一律容错注册：《无限》客户端没有的事件名会报错
    for _, e in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UI_ERROR_MESSAGE",
        "SKILL_LINES_CHANGED", "UPDATE_EXHAUSTION", "CHAT_MSG_SYSTEM", "PLAYER_ENTERING_WORLD", "CHARACTER_POINTS_CHANGED", "LOOT_OPENED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    local treeDone
    ns._obsEvent = function(_, e, ...)
        if e == "TRAINER_SHOW" or e == "TRAINER_UPDATE" then pcall(O.Trainer)
        elseif e == "UNIT_SPELLCAST_SENT" then pcall(O.CastSent, ...)
        elseif e == "UNIT_SPELLCAST_SUCCEEDED" then pcall(O.CastDone, ...)
        elseif e == "UI_ERROR_MESSAGE" then pcall(O.UIError, ...)
        elseif e == "SKILL_LINES_CHANGED" then pcall(O.SkillsChanged)
        elseif e == "UPDATE_EXHAUSTION" then pcall(O.Exhaustion)
        elseif e == "CHAT_MSG_SYSTEM" then pcall(O.System, nil, ...)
        elseif e == "PLAYER_ENTERING_WORLD" then
            pcall(O.SkillsChanged); pcall(O.Exhaustion)
            if not treeDone then treeDone = true; pcall(O.TalentTree) end
        -- 只在分配天赋点时记：升级那一刻点还没分，记了会把上一级的配点算到新等级头上
        elseif e == "CHARACTER_POINTS_CHANGED" then pcall(O.TalentPicks)
        elseif e == "LOOT_OPENED" then pcall(O.LootOpened)
        end
    end
    f:SetScript("OnEvent", ns._obsEvent)
end)
