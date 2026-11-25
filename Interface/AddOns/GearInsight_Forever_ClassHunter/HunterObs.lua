-- 猎人宠物众包加强（11-20 用户「加强猎人宠物BB技能的众包」，HOLD：游戏内验收完才进发行包）
-- 只在猎人角色加载（猎人专属子插件 GearInsight_Forever_ClassHunter，主插件 ClassStub.lua 登录时 LoadAddOn）。
-- 走 Obs 同一条通道（ns.Obs.Add → 导出串 ob 字段 → 更新器上传），服务端 ≥2 个玩家一致才采信（scripts/gi_forever_pet_crowd.py）：
--   bc 野兽施法  野外野兽（有家族、不是玩家控制的）放技能：键 npcID → 值 法术ID
--                ⛔ 《无限》是 12.0 引擎：插件注册 COMBAT_LOG_EVENT_UNFILTERED = ADDON_ACTION_FORBIDDEN（整个插件被禁用，Stats.lua 10-07），
--                  战斗记录不能用 → 改听单位施法事件 UNIT_SPELLCAST_SUCCEEDED（目标 / 焦点 / 鼠标指向 / 姓名板单位都会发）。
--                  只看得到「放出来的技能」（瞬发 / 读条都算），看不到普通攻击；保密值（战斗中可能）一律跳过。
--                性能：先查单位令牌（查表，不分配）→ 法术 ID 有效 → 每秒最多 BUDGET 次进一步查 → GUID 缓存「是不是野兽」→ 同一只怪同一个技能本次登录只记一次，
--                  每只怪最多 PER_NPC 个技能，bc 总共最多 BC_TOTAL 条（超了删最旧的 bc）
--   bt 训练野兽  打开「训练野兽」（经典是 CRAFT 框体：GetNumCrafts / GetCraftInfo，第 6 / 7 个返回值 = 训练点消耗 / 要求宠物等级）：
--                键「s法术ID」（读不到 ID 用「n名字:等级」）→ 值「训练点|要求宠物等级」= 补「训练点数值」缺口
--                《无限》要是改成训练师样式的窗口（TRAINER_SHOW 但没有 NPC）：同样记，键「t名字|等级」→ 值「花费|要求等级」
--   bp 训练点    宠物出来 / 打开训练野兽时：键「L宠物等级:忠诚度等级」→ 值 总训练点（GetPetTrainingPoints 第 1 个）
--   tm 补强      HunterTame.lua 的挂钩：① 驯服引导被打断 / 失败、或之后放了「召唤宠物 / 复活宠物」→ 这一下不算（防兽栏老宠物）；
--                ② 本机见过的宠物 GUID 不算新驯服；③ 值末尾加「|攻速|宠物等级」（攻速 = UnitAttackSpeed("pet")，家族 / 野兽决定）
--   宠物训练师（低吼 / 耐力 / 护甲 / 抗性的学习等级 + 价格 + 训练师坐标）：主插件 Obs.lua 的 pt / pn 早就在记（任何训练师窗口），这里不重复
-- ⛔ 只记游戏数据（NPC ID / 法术 ID / 等级 / 坐标 / 训练点），不记角色名 / 服务器名 / 宠物名；不发任何聊天。
-- 探针：/gi petobs（主插件命令，猎人多打几行：施法 / 训练野兽 / 训练点 / 最近驯服）
local _, ns = ...; ns = _G.GearInsightForever or ns
if not ns or select(2, UnitClass("player")) ~= "HUNTER" or not ns.HunterTame then return end

local T = ns.HunterTame
local clean, call, add, now = T.clean, T.call, T.add, T.now
local O = {}
ns.HunterObs = O

O.BC_TOTAL = 200
O.PER_NPC = 6
O.BUDGET = 20          -- 每秒最多进一步查几次（姓名板多的时候施法事件很密）
O.BT_TOTAL = 80
O.BP_TOTAL = 40
O.CALL_PET = { [883] = true, [982] = true }   -- 召唤宠物 / 复活宠物
O.BEAST_TRAINING = 5149
O.seen = {}            -- [npc] = { [法术ID] = true, n = 几个 }
O.recent = {}          -- 最近几条 bc（探针看）：{ npc, name, spell }

local UNITS = { target = true, focus = true, mouseover = true, softenemy = true }
for i = 1, 40 do UNITS["nameplate" .. i] = true end
O.UNITS = UNITS

local gc, gcN = {}, 0   -- GUID → npcID（野兽）/ false（不是野兽）；满 300 清空
local budget, budgetAt = 0, -1

-- ---------- bc 野兽施法 ----------
function O.Cast(unit, _, spellID)
    if not UNITS[unit] then return false end
    if type(spellID) ~= "number" or (ns.Secret and ns.Secret(spellID)) or spellID <= 0 then return false end
    local t = now()
    if t - budgetAt >= 1 then budgetAt, budget = t, 0 end
    budget = budget + 1
    if budget > O.BUDGET then return false end
    local guid = clean(call(UnitGUID, unit))
    if type(guid) ~= "string" then return false end
    local npc = gc[guid]
    if npc == nil then
        npc = false
        if not call(UnitIsPlayer, unit) and not call(UnitPlayerControlled, unit) then
            local fam = clean(call(UnitCreatureFamily, unit))
            if fam and fam ~= "" then npc = T.NpcOfGuid(guid) or false end
        end
        if gcN >= 300 then gc, gcN = {}, 0 end
        gc[guid], gcN = npc, gcN + 1
    end
    if not npc then return false end
    local s = O.seen[npc]
    if not s then s = { n = 0 }; O.seen[npc] = s end
    if s[spellID] or s.n >= O.PER_NPC then return false end
    s[spellID], s.n = true, s.n + 1
    local r = O.recent
    if #r >= 8 then table.remove(r, 1) end
    r[#r + 1] = { npc = npc, name = clean(call(UnitName, unit)), spell = spellID }
    local okAdd = add("bc", tostring(npc), tostring(spellID))
    T.Trim("bc", O.BC_TOTAL)
    return okAdd
end

-- ---------- bp 训练点（宠物等级 × 忠诚度 → 总训练点）----------
local function loyaltyLevel()
    local s = clean(call(GetPetLoyalty))
    if type(s) == "number" then return s end
    return type(s) == "string" and tonumber(s:match("(%d+)")) or 0
end
function O.PetPoints()
    if not GetPetTrainingPoints or not call(UnitExists, "pet") then return false end
    local total = tonumber(clean(call(GetPetTrainingPoints)))
    local lv = tonumber(clean(call(UnitLevel, "pet"))) or 0
    if not total or lv <= 0 then return false end
    local okAdd = add("bp", "L" .. lv .. ":" .. loyaltyLevel(), tostring(total))
    T.Trim("bp", O.BP_TOTAL)
    return okAdd
end

-- ---------- bt 训练野兽 ----------
local btName
local function isBeastTraining()
    if btName == nil then
        btName = clean(call(GetSpellInfo, O.BEAST_TRAINING)) or (C_Spell and clean(call(C_Spell.GetSpellName, O.BEAST_TRAINING))) or false
    end
    local n = clean(call(GetCraftDisplaySkillLine)) or clean(call(GetCraftName))
    return btName and n and n == btName
end
local function linkId(link)
    link = clean(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("[Hh]?spell:(%d+)") or link:match("enchant:(%d+)"))
end
local function num(v)
    v = tonumber(clean(v))
    return v and tostring(v) or ""
end

function O.Craft()
    if not (GetNumCrafts and GetCraftInfo) then return 0 end
    local n = tonumber(clean(call(GetNumCrafts))) or 0
    if n <= 0 then return 0 end
    local rows, anyTP = {}, false
    for i = 1, math.min(n, 60) do
        local name, sub, typ, _, _, tp, req = call(GetCraftInfo, i)
        name, sub, tp = clean(name), clean(sub), tonumber(clean(tp))
        if type(name) == "string" and name ~= "" and typ ~= "header" then
            rows[#rows + 1] = { i = i, name = name, sub = sub, tp = tp, req = req }
            if tp and tp > 0 then anyTP = true end
        end
    end
    if not (anyTP or isBeastTraining()) then return 0 end   -- 猎人兼附魔：附魔也是 CRAFT 框体，不记
    local added = 0
    for _, r in ipairs(rows) do
        local id = linkId(call(GetCraftItemLink, r.i)) or linkId(call(GetCraftRecipeLink, r.i))
        local key = id and ("s" .. id) or ("n" .. r.name:sub(1, 24) .. ":" .. ((type(r.sub) == "string" and r.sub:match("(%d+)")) or ""))
        if add("bt", key, (r.tp and tostring(r.tp) or "") .. "|" .. num(r.req)) then added = added + 1 end
    end
    T.Trim("bt", O.BT_TOTAL)
    pcall(O.PetPoints)
    return added
end

-- 《无限》要是把训练野兽做成训练师样式（没有 NPC 的训练师窗口）：照样记
function O.TrainerNoNpc()
    if call(UnitExists, "npc") or not (GetNumTrainerServices and GetTrainerServiceInfo) then return 0 end
    local n = tonumber(clean(call(GetNumTrainerServices))) or 0
    local added = 0
    for i = 1, math.min(n, 60) do
        local name, sub, cat = call(GetTrainerServiceInfo, i)
        name, sub = clean(name), clean(sub)
        if type(name) == "string" and name ~= "" and cat ~= "header" then
            local key = "t" .. name:sub(1, 24) .. "|" .. ((type(sub) == "string" and sub:match("(%d+)")) or "")
            if add("bt", key, num(call(GetTrainerServiceCost, i)) .. "|" .. num(call(GetTrainerServiceLevelReq, i))) then added = added + 1 end
        end
    end
    T.Trim("bt", O.BT_TOTAL)
    return added
end

-- ---------- tm 补强（HunterTame.lua 的挂钩）----------
local function petDb()
    if not ns.db then return {} end
    ns.db.hunterPets = ns.db.hunterPets or {}   -- 本机见过的宠物 GUID（只在本机，不上传）
    return ns.db.hunterPets
end
function O.RememberPet()
    local g = clean(call(UnitGUID, "pet"))
    if type(g) ~= "string" then return end
    local D, n = petDb(), 0
    if D[g] then return end
    for _ in pairs(D) do n = n + 1 end
    if n >= 50 then for k in pairs(D) do D[k] = nil end end
    D[g] = true
end
T.veto[#T.veto + 1] = function(pd)
    if pd.bad then return true end
    local g = clean(call(UnitGUID, "pet"))
    return type(g) == "string" and petDb()[g] == true
end
T.extra = function()
    local sp = tonumber(clean(call(UnitAttackSpeed, "pet")))
    return "|" .. (sp and string.format("%.2f", sp) or "") .. "|" .. (tonumber(clean(call(UnitLevel, "pet"))) or "")
end
-- 只认「这一下」的施法 GUID：引导中再按一次驯服报的「另一个动作正在进行」不算打断
local function tameBroken(unit, castGUID, spellID)
    local pd = T.pending
    if unit ~= "player" or not pd or not T.IsTame(spellID) then return end
    castGUID = clean(castGUID)
    if pd.cast and castGUID and castGUID ~= pd.cast then return end
    pd.bad = true
end

-- ---------- 探针 ----------
local function count(k)
    local n = 0
    for _, r in pairs((ns.db and ns.db.obs) or {}) do if r.k == k then n = n + 1 end end
    return n
end
local function spellName(id)
    return clean(call(GetSpellInfo, id)) or (C_Spell and clean(call(C_Spell.GetSpellName, id))) or ("#" .. id)
end
function ns.HunterProbe()
    ns.Print(string.format(ns.L("猎人众包：野兽施法 %d 条 · 训练野兽 %d 条 · 训练点 %d 条", "Hunter crowdsourcing: %d beast casts · %d Beast Training rows · %d training-point rows"),
        count("bc"), count("bt"), count("bp")))
    for _, r in ipairs(O.recent) do
        ns.Print(string.format("  #%d %s → %s (%d)", r.npc, tostring(r.name or "?"), tostring(spellName(r.spell)), r.spell))
    end
    local l = T.last
    if l then
        ns.Print(string.format(ns.L("最近驯服：#%d（%s）读到 %d 个宠物技能", "Last tame: #%d (%s), %d pet abilities"), l.npc, tostring(l.fam), l.n))
    end
end

-- ---------- 事件 ----------
T.Listen("UNIT_SPELLCAST_SUCCEEDED", function(unit, castGUID, spellID)
    if unit == "player" then
        if T.pending and O.CALL_PET[tonumber(spellID) or 0] then T.pending.bad = true end
        return
    end
    O.Cast(unit, castGUID, spellID)
end)
T.Listen("UNIT_SPELLCAST_INTERRUPTED", tameBroken)
T.Listen("UNIT_SPELLCAST_FAILED", tameBroken)
T.Listen("CRAFT_SHOW", O.Craft)
T.Listen("CRAFT_UPDATE", O.Craft)
T.Listen("TRAINER_SHOW", O.TrainerNoNpc)
-- 宠物出现：先等 HunterTame 判完是不是新驯服（同一个事件里它先跑），再把这只记成「见过」；训练点过 2 秒再读
T.Listen("UNIT_PET", function(unit)
    if unit ~= nil and unit ~= "player" then return end
    if not T.pending then O.RememberPet() end
    if C_Timer and C_Timer.After then C_Timer.After(2, function() pcall(O.PetPoints) end) end
end)
if not T.pending then pcall(O.RememberPet) end   -- 登录时已经带着的宠物
