-- 11-20 用户「怎么能在插件看到抓了的宝宝，技能学习进度」→「做吧，加个『我的宠物』视图」：
--   猎人宠物页「我的宠物」视图（_Class 的 PetMine.lua）要的三份数据，在这里记进存档（_Class 按需加载，事件只能主插件收）：
--   crafts  「训练野兽」窗口里列的 = 猎人已学会的宠物技能（名字 / 等级 / 训练点 / 需要等级）：只有窗口开着时客户端才给 → CRAFT_SHOW / CRAFT_UPDATE 时记
--   stable  兽栏里的宠物（图标 / 名字 / 等级 / 家族 / 忠诚）：只有兽栏开着时才给 → PET_STABLE_SHOW / PET_STABLE_UPDATE 时记
--   cur     当前宠物（名字 / 等级 / 家族 / 技能书法术 ID / 训练点 / 忠诚 / 快乐 / 经验）：宠物在身边时随时读，收回去以后看存档
-- 存档 ns.db.petSnap[角色 GUID]；只猎人注册事件。⛔ 每个 API 都 pcall / 判空。⛔ 在 HOLD 里，游戏内验收完才进发行包。
local _, ns = ...
-- 1.4.6 内核预算：不是猎人整个文件当场返回（函数一个都不建，登录不占内存）；职业读不到（nil）照常往下
do
    local ok, _, c = pcall(UnitClass, "player")
    if ok and type(c) == "string" and c ~= "HUNTER" then return end
end

local S = {}
ns.PetSnap = S
S.BEAST_TRAINING = 5149

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
local function rankOf(sub) return tonumber(type(sub) == "string" and sub:match("(%d+)") or nil) end

function S.Mine()
    if not ns.db then return nil end
    local g = clean(call(UnitGUID, "player"))
    if type(g) ~= "string" then return nil end
    ns.db.petSnap = ns.db.petSnap or {}
    ns.db.petSnap[g] = ns.db.petSnap[g] or {}
    return ns.db.petSnap[g]
end

-- 「训练野兽」窗口：附魔在经典旧世也走同一套 Craft 接口 → 先认技能线名字
function S.IsBeastTraining()
    local line = clean(call(GetCraftDisplaySkillLine))
    if type(line) ~= "string" or line == "" then return false end
    local bt = clean(call(GetSpellInfo, S.BEAST_TRAINING))
    if bt and line == bt then return true end
    return line == "训练野兽" or line == "訓練野獸" or line == "Beast Training"
end
function S.ReadCrafts()
    if not S.IsBeastTraining() then return false end
    local n = tonumber(clean(call(GetNumCrafts))) or 0
    local out = {}
    for i = 1, math.min(n, 120) do
        local name, sub, kind, _, _, tp, lv = call(GetCraftInfo, i)
        name = clean(name)
        if type(name) == "string" and name ~= "" and kind ~= "header" then
            out[#out + 1] = { n = name, r = rankOf(clean(sub)), tp = tonumber(clean(tp)), lv = tonumber(clean(lv)) }
        end
    end
    if #out == 0 then return false end
    local m = S.Mine()
    if not m then return false end
    m.crafts, m.craftAt = out, time()
    return true
end

function S.ReadStable()
    local m = S.Mine()
    if not m then return false end
    local n = tonumber(clean(call(GetNumStableSlots))) or 0
    local out = {}
    for i = 1, math.min(math.max(n, 0), 4) do
        local icon, name, lv, fam, loy = call(GetStablePetInfo, i)
        name = clean(name)
        if type(name) == "string" and name ~= "" then
            out[#out + 1] = { slot = i, icon = clean(icon), n = name, lv = tonumber(clean(lv)), fam = clean(fam), loy = clean(loy) }
        end
    end
    m.stable, m.stableAt, m.stableSlots = out, time(), n
    return true
end

-- 宠物技能书里的法术 ID（ObsPet 同一套读法；指令按钮 ID 不要）
local function petSpellIds()
    local out = {}
    local n = tonumber(clean(call(HasPetSpells))) or 0
    local SB = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
    if n == 0 and SB and SB.HasPetSpells then n = tonumber(clean(call(SB.HasPetSpells))) or 0 end
    for i = 1, math.min(n, 30) do
        local id
        if GetSpellBookItemInfo then
            local kind, sid = call(GetSpellBookItemInfo, i, BOOKTYPE_PET or "pet")
            if kind ~= "FUTURESPELL" then id = tonumber(clean(sid)) end
        elseif SB and SB.GetSpellBookItemInfo and bank then
            local info = call(SB.GetSpellBookItemInfo, i, bank)
            if type(info) == "table" then id = tonumber(clean(info.spellID or info.actionID)) end
        end
        if id and id > 0 and id < 0x1000000 then out[#out + 1] = id end
    end
    return out
end

-- 当前宠物：在身边才读（读到了覆盖存档，收回去也留着上一次的）
function S.ReadCur()
    if not clean(call(UnitExists, "pet")) then return nil end
    local name = clean(call(UnitName, "pet"))
    if type(name) ~= "string" or name == "" then return nil end
    local tp, spent = call(GetPetTrainingPoints)
    local xp, xpMax = call(GetPetExperience)
    local hap = call(GetPetHappiness)
    local c = {
        n = name, lv = tonumber(clean(call(UnitLevel, "pet"))), fam = clean(call(UnitCreatureFamily, "pet")),
        spells = petSpellIds(), tp = tonumber(clean(tp)), spent = tonumber(clean(spent)),
        loy = clean(call(GetPetLoyalty)), hap = tonumber(clean(hap)),
        xp = tonumber(clean(xp)), xpMax = tonumber(clean(xpMax)), at = time(),
    }
    local m = S.Mine()
    if m and (#c.spells > 0 or not m.cur or m.cur.n ~= name) then m.cur = c end
    return c
end

local function changed()
    local P = ns.PetPage
    if P and P.view == "mine" and P.refreshView and P.IsVisible and P:IsVisible() then pcall(P.refreshView, true) end
end

table.insert(ns.modules, function()
    local _, cls = call(UnitClass, "player")
    if cls ~= "HUNTER" then return end
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "CRAFT_SHOW", "CRAFT_UPDATE", "PET_STABLE_SHOW", "PET_STABLE_UPDATE", "UNIT_PET", "PET_BAR_UPDATE", "PLAYER_ENTERING_WORLD" }) do
        pcall(f.RegisterEvent, f, e)
    end
    local pend = false
    f:SetScript("OnEvent", function(_, e, unit)
        if e == "CRAFT_SHOW" or e == "CRAFT_UPDATE" then
            if pcall(S.ReadCrafts) then changed() end
        elseif e == "PET_STABLE_SHOW" or e == "PET_STABLE_UPDATE" then
            pcall(S.ReadStable); changed()
        elseif e ~= "UNIT_PET" or unit == "player" then
            -- 技能书要等一会儿才填好：合并成 1 秒后读一次
            if pend or not (C_Timer and C_Timer.After) then return end
            pend = true
            C_Timer.After(1, function() pend = false; pcall(S.ReadCur); changed() end)
        end
    end)
end)
