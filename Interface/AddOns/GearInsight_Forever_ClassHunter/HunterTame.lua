-- 猎人宠物众包 tm 驯服结果（11-05 随 ObsPet.lua 上线；11-20 从主插件搬进猎人专属子插件 GearInsight_Forever_ClassHunter）
--   用户硬规「职业专属的只有这个职业才加载」：只有猎人角色登录才加载（主插件 ClassStub.lua），非猎人不占内存。
--   逻辑 / 格式和 1.4.4 主插件版完全一样（服务端 gi_forever_pet_crowd.py 照旧认）：
--   猎人「驯服野兽」（1515）放出去时记下目标；新宠物出现（UNIT_PET）后：
--     键 npcID → 值「家族名|驯服时目标等级|地图|x|y|宠物技能」，宠物技能 = 法术ID 逗号连（读不到 ID 用「名字:等级」）
--   11-20 键记驯服目标的 npcID（《无限》宠物 GUID 里的生物 ID 一律是通用的 165189）。
--   挂钩（HOLD 的 HunterObs.lua 用；没有它时行为和 1.4.4 一样）：
--     T.veto[i](pd) 返回真 = 这一下不算（兽栏召出的老宠物等）· T.extra(pd) 返回的串接在值末尾（「|攻速|宠物等级」）
-- ⛔ 不记角色名 / 服务器名 / 宠物自起名；保密值不记；tm 最多 TM_TOTAL 条，超了删最旧的。⛔ 每个 API 都 pcall / 判空。
local _, ns = ...; ns = _G.GearInsightForever or ns
if not ns or select(2, UnitClass("player")) ~= "HUNTER" or not ns.ObsPet or (ns.FeatureOff and ns.FeatureOff("obs")) then return end

local T = {}
ns.HunterTame = T

T.TAME = 1515          -- 驯服野兽
T.TM_TOTAL = 60
T.TAME_WINDOW = 45     -- 放出驯服后多少秒内出现的新宠物算这一下（引导 20 秒 + 余量）
T.pending = nil        -- { npc, lv, fam, name, cast, map, x, y, t }
T.last = nil           -- 最近一次 tm：{ npc, fam, n, v }
T.veto = {}

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
T.clean, T.call = clean, call
local function now() return (GetTime and GetTime()) or 0 end
T.now = now

local P = ns.ObsPet   -- 主插件（同一个功能开关「众包观测」）：GUID 里的生物 ID / 只删某一类最旧的 共用它的
local function npcOfGuid(guid) return P and P.NpcOfGuid and P.NpcOfGuid(guid) or nil end
T.NpcOfGuid = npcOfGuid

local function pos()
    local W = ns.Obs and ns.Obs.WherePrecise
    if W then
        local ok, m, x, y = pcall(W)
        if ok and m then return m, x, y end
    end
    return 0, "", ""
end
T.pos = pos

local function add(k, key, val)
    return ns.Obs and ns.Obs.Add and ns.Obs.Add(k, key, val) or false
end
T.add = add

function T.Trim(k, cap) return P and P.Trim and P.Trim(k, cap) or 0 end

local tameName
local function isTame(spellID)
    if tonumber(spellID) == T.TAME then return true end
    if tameName == nil then
        tameName = clean(call(GetSpellInfo, T.TAME)) or (C_Spell and clean(call(C_Spell.GetSpellName, T.TAME))) or false
    end
    if not tameName or not spellID then return false end
    local n = clean(call(GetSpellInfo, spellID)) or (C_Spell and clean(call(C_Spell.GetSpellName, spellID)))
    return n ~= nil and n == tameName
end
T.IsTame = isTame

function T.CastSent(unit, _, castGUID, spellID)
    if unit ~= "player" or not isTame(spellID) then return end
    local npc = npcOfGuid(call(UnitGUID, "target"))
    local m, x, y = pos()
    T.pending = { npc = npc, lv = tonumber(clean(call(UnitLevel, "target"))) or 0, fam = clean(call(UnitCreatureFamily, "target")),
                  name = clean(call(UnitName, "target")), cast = clean(castGUID), map = m, x = x, y = y, t = now() }
end

-- 11-07：宠物指令打包 ID（0x06000000 / 0x07000000 = 攻击 / 跟随 / 停留 / 被动…）不是技能；高 8 位非 0 的取低 24 位
local function realSpell(id)
    id = tonumber(id)
    if not id or id <= 0 then return nil end
    if id >= 0x1000000 then
        local hi, lo = math.floor(id / 0x1000000), id % 0x1000000
        if hi == 6 or hi == 7 or lo == 0 then return nil end
        id = lo
    end
    return id
end
T.RealSpell = realSpell

-- 宠物技能书：老接口 GetSpellBookItemName(i, BOOKTYPE_PET) / GetSpellBookItemInfo；新接口 C_SpellBook.*
local function petSpells()
    local out, n = {}, 0
    local book = BOOKTYPE_PET or "pet"
    local SB = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
    if HasPetSpells then n = tonumber(clean(call(HasPetSpells))) or 0 end
    if n == 0 and SB and SB.HasPetSpells then n = tonumber(clean(call(SB.HasPetSpells))) or 0 end
    for i = 1, math.min(n, 30) do
        local id, name, sub
        if GetSpellBookItemInfo then
            local kind, sid = call(GetSpellBookItemInfo, i, book)
            if kind ~= "FUTURESPELL" then id = tonumber(clean(sid)) end
        elseif SB and SB.GetSpellBookItemInfo and bank then
            local info = call(SB.GetSpellBookItemInfo, i, bank)
            if type(info) == "table" then id = tonumber(clean(info.spellID or info.actionID)) end
        end
        if GetSpellBookItemName then
            name, sub = call(GetSpellBookItemName, i, book)
        elseif SB and SB.GetSpellBookItemName and bank then
            name, sub = call(SB.GetSpellBookItemName, i, bank)
        end
        name, sub = clean(name), clean(sub)
        local raw = id
        id = realSpell(id)
        if raw and not id then name = nil end   -- 指令按钮：名字也不要
        if id and id > 0 then out[#out + 1] = tostring(id)
        elseif type(name) == "string" and name ~= "" then
            out[#out + 1] = name:sub(1, 16) .. ((type(sub) == "string" and sub ~= "") and (":" .. (sub:match("(%d+)") or sub:sub(1, 8))) or "")
        end
    end
    -- 技能书读不到：退到宠物动作条（只有名字 / 是不是技能）
    if #out == 0 and GetPetActionInfo then
        for i = 1, (NUM_PET_ACTION_SLOTS or 10) do
            local name, _, _, isToken, _, _, _, sid = call(GetPetActionInfo, i)
            sid = realSpell(clean(sid))
            name = clean(name)
            if sid and sid > 0 then out[#out + 1] = tostring(sid)
            elseif type(name) == "string" and name ~= "" and not isToken then out[#out + 1] = name:sub(1, 16) end
        end
    end
    table.sort(out)
    return out
end
T.PetSpells = petSpells

-- 新宠物出现：在驯服窗口内 → 记 tm；技能书还没填好（0 个）就过一会儿再读（最多 3 次）
function T.PetChanged(tries)
    local pd = T.pending
    if not pd or now() - pd.t > T.TAME_WINDOW then return false end
    if not call(UnitExists, "pet") then return false end
    for _, f in ipairs(T.veto) do
        local ok, no = pcall(f, pd)
        if ok and no then T.pending = nil; return false end
    end
    local npc = pd.npc or npcOfGuid(call(UnitGUID, "pet"))
    if not npc then return false end
    local spells = petSpells()
    tries = tries or 0
    if #spells == 0 and tries < 3 and C_Timer and C_Timer.After then
        C_Timer.After(1.5, function() pcall(T.PetChanged, tries + 1) end)
        return false
    end
    local fam = clean(call(UnitCreatureFamily, "pet")) or pd.fam or ""
    local sp = table.concat(spells, ","):sub(1, 100)
    local v = table.concat({ tostring(fam):sub(1, 20), pd.lv or 0, pd.map, pd.x, pd.y, sp }, "|")
    if T.extra then
        local ok, e = pcall(T.extra, pd)
        if ok and type(e) == "string" and e ~= "" then v = v .. e end
    end
    local okAdd = add("tm", tostring(npc), v)
    T.pending = nil
    T.last = { npc = npc, fam = fam, n = #spells, v = v }
    T.Trim("tm", T.TM_TOTAL)
    return okAdd
end

-- 事件（HunterObs.lua 往 T.on 里挂自己的处理，共用一个框体）
T.on = {}
local f = CreateFrame("Frame")
T.frame = f
function T.Listen(e, fn)
    if not T.on[e] then
        T.on[e] = {}
        pcall(f.RegisterEvent, f, e)   -- ⛔ 容错注册：客户端没有的事件名会报错
    end
    local l = T.on[e]
    l[#l + 1] = fn
end
f:SetScript("OnEvent", function(_, e, ...)
    for _, fn in ipairs(T.on[e] or {}) do pcall(fn, ...) end
end)
ns._hunterEvent = function(_, e, ...)   -- 测试用
    for _, fn in ipairs(T.on[e] or {}) do pcall(fn, ...) end
end
T.Listen("UNIT_SPELLCAST_SENT", T.CastSent)
T.Listen("UNIT_PET", function(unit) if unit == nil or unit == "player" then T.PetChanged(0) end end)
