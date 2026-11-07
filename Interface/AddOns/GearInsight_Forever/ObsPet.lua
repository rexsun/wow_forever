-- 11-05 猎人宠物「在哪抓」方案 c：开源数据（PetTameData.lua，经典旧世 1.12）打底 + 这里的游戏内众包校正。
-- 走 Obs 同一条通道（ns.Obs.Add → 掉落导出串 GIFD1 的 ob 字段 → 更新器上传，更新器不用发版），服务端 ≥2 台设备一致才采信：
--   bf 野兽目击  鼠标指向 / 选中一只有家族的野兽（UnitCreatureFamily 有值、不是玩家控制的）：
--                键 npcID → 值「家族名|等级|地图|x|y|稀有度|名字」（坐标 = 自己当时的位置，百分比一位小数；
--                家族名 / 名字 = 客户端语言的怪物名，不是玩家；稀有度 n 普通 / e 精英 / r 稀有 / R 稀有精英 / b 首领）
--                → 补《无限》新地区、新家族狐狸、等级 / 坐标改动、中文名。同一只怪本次登录只记一次。
--   tm 驯服结果  猎人「驯服野兽」（1515）放出去时记下目标；新宠物出现（UNIT_PET）后：
--                键 npcID → 值「家族名|驯服时目标等级|地图|x|y|宠物技能」，宠物技能 = 法术ID 逗号连（读不到 ID 用「名字:等级」）
--                → 新抓的宠物会的技能等级 = 这只野兽会教的，校正「哪只野兽教哪一级」。
-- ⛔ 不记角色名 / 服务器名 / 宠物自起名；保密值（ns.Secret）不记；bf 最多 BF_TOTAL 条、tm 最多 TM_TOTAL 条，超了删最旧的。
-- ⛔ 每个 API 都 pcall / 判空（经典旧世引擎 1.60 客户端，接口可能缺）。⛔ 在 HOLD 里，游戏内验收完才进发行包。
-- 探针：/gi petobs（看记了多少条 + 最近一次驯服）
local _, ns = ...

local P = {}
ns.ObsPet = P

P.TAME = 1515          -- 驯服野兽
P.BF_TOTAL = 300
P.TM_TOTAL = 60
P.TAME_WINDOW = 45     -- 放出驯服后多少秒内出现的新宠物算这一下（引导 20 秒 + 余量）
P.seen = {}            -- 本次登录已记过的 npc（bf）
P.pending = nil        -- { npc, lv, fam, map, x, y, t }
P.last = nil           -- 最近一次 tm：{ npc, fam, n }

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
local function now() return (GetTime and GetTime()) or 0 end

-- GUID 里的生物 ID：野外怪是 Creature-…，刚驯服的宠物是 Pet-…（同样第 6 段是生物 ID）
local function npcOfGuid(guid)
    guid = clean(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Pet" and kind ~= "Vehicle" then return nil end
    id = tonumber(id)
    return id and id > 0 and id or nil
end
P.NpcOfGuid = npcOfGuid

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

-- ---------- bf 野兽目击 ----------
function P.Sight(unit)
    if not unit or not call(UnitExists, unit) then return false end
    if call(UnitIsPlayer, unit) or call(UnitPlayerControlled, unit) then return false end
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
local tameName
local function isTame(spellID)
    if tonumber(spellID) == P.TAME then return true end
    if tameName == nil then
        tameName = clean(call(GetSpellInfo, P.TAME)) or (C_Spell and clean(call(C_Spell.GetSpellName, P.TAME))) or false
    end
    if not tameName or not spellID then return false end
    local n = clean(call(GetSpellInfo, spellID)) or (C_Spell and clean(call(C_Spell.GetSpellName, spellID)))
    return n ~= nil and n == tameName
end
P.IsTame = isTame

function P.CastSent(unit, _, _, spellID)
    if unit ~= "player" or not isTame(spellID) then return end
    local npc = npcOfGuid(call(UnitGUID, "target"))
    local m, x, y = pos()
    P.pending = { npc = npc, lv = tonumber(clean(call(UnitLevel, "target"))) or 0, fam = clean(call(UnitCreatureFamily, "target")),
                  map = m, x = x, y = y, t = now() }
end

-- 11-07 玩家「上面写的有（狂狼之嚎），我抓了十几只都没有」→ 查服务端 tm：120 条记的全是 100663296 / 117440512 这类
--   打包 ID（0x06000000 / 0x07000000 = 宠物指令：攻击 / 跟随 / 停留 / 被动…），一条真技能都没有。
--   高 8 位非 0 的先取低 24 位当法术 ID；低 24 位是 0（纯指令）或高位是 6 / 7 的不记
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
P.RealSpell = realSpell

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
P.PetSpells = petSpells

-- 新宠物出现：在驯服窗口内 → 记 tm；技能书还没填好（0 个）就过一会儿再读（最多 3 次）
function P.PetChanged(tries)
    local pd = P.pending
    if not pd or now() - pd.t > P.TAME_WINDOW then return false end
    if not call(UnitExists, "pet") then return false end
    local npc = npcOfGuid(call(UnitGUID, "pet")) or pd.npc
    if not npc then return false end
    local spells = petSpells()
    tries = tries or 0
    if #spells == 0 and tries < 3 and C_Timer and C_Timer.After then
        C_Timer.After(1.5, function() pcall(P.PetChanged, tries + 1) end)
        return false
    end
    local fam = clean(call(UnitCreatureFamily, "pet")) or pd.fam or ""
    local sp = table.concat(spells, ","):sub(1, 100)
    local okAdd = add("tm", tostring(npc), table.concat({ tostring(fam):sub(1, 20), pd.lv or 0, pd.map, pd.x, pd.y, sp }, "|"))
    P.pending = nil
    P.last = { npc = npc, fam = fam, n = #spells }
    P.Trim("tm", P.TM_TOTAL)
    return okAdd
end

local function count(k)
    local n = 0
    for _, r in pairs((ns.db and ns.db.obs) or {}) do
        if r.k == k then n = n + 1 end
    end
    return n
end

function P.Probe()
    ns.Print(string.format(ns.L("宠物众包：野兽目击 %d 条 · 驯服结果 %d 条", "Pet crowdsourcing: %d beast sightings · %d tames"), count("bf"), count("tm")))
    local l = P.last
    if l then
        ns.Print(string.format(ns.L("最近驯服：#%d（%s）读到 %d 个宠物技能", "Last tame: #%d (%s), %d pet abilities"), l.npc, tostring(l.fam), l.n))
    end
end

ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.petobs = function() pcall(P.Probe) end

table.insert(ns.modules, function()
    local f = CreateFrame("Frame")
    -- ⛔ 容错注册：客户端没有的事件名会报错
    for _, e in ipairs({ "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED", "UNIT_SPELLCAST_SENT", "UNIT_PET" }) do
        pcall(f.RegisterEvent, f, e)
    end
    ns._obsPetEvent = function(_, e, ...)
        if e == "UPDATE_MOUSEOVER_UNIT" then pcall(P.Sight, "mouseover")
        elseif e == "PLAYER_TARGET_CHANGED" then pcall(P.Sight, "target")
        elseif e == "UNIT_SPELLCAST_SENT" then pcall(P.CastSent, ...)
        elseif e == "UNIT_PET" then
            local unit = ...
            if unit == nil or unit == "player" then pcall(P.PetChanged, 0) end
        end
    end
    f:SetScript("OnEvent", ns._obsPetEvent)
end)
