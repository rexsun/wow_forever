-- 键位手法 P0 · 能力探针（10-10，docs/forever-keybind-rotation-design.md §2）
-- 目的：实测《无限》客户端里，键位模块和手法引擎要用的每个能力「能不能用 / 是普通值还是保密值 / 读不到」。
-- 用法：/gif probe keys 开始（再输一次停止并弹出结果）；开始后去打木桩或小怪，脱战自动记一轮。
--      结果同时存 GearInsightForeverDB.keysProbe，弹出的框里 Ctrl+C 复制整串发回来。
-- ⛔ 只读：不改动作条、不绑键。⛔ 在 HOLD（_hold.txt）里，不进发行包。
local _, ns = ...

local P = {}
ns.KeysProbe = P

local function kind(v)
    if v == nil then return "nil" end
    if issecretvalue and issecretvalue(v) then return "secret" end
    if v == false then return "false" end
    return "ok"
end

-- 三个首批职业的代表技能（经典旧世编号；《无限》新编号由探针一并记下实际读到的）
local SP = {
    WARRIOR = { main = 12294, cd = 12292, proc = 7384, debuff = 772, buff = 6673 },        -- 致死打击 / 死亡之愿 / 压制 / 撕裂 / 战斗怒吼
    ROGUE   = { main = 1752,  cd = 13750, proc = 14251, debuff = 1943, buff = 5171 },      -- 邪恶攻击 / 冲动 / 还击 / 割裂 / 切割
    WARLOCK = { main = 686,   cd = 18288, proc = 17941, debuff = 172, buff = 687 },        -- 暗影箭 / 恶毒诅咒 / 暗影冥思 / 腐蚀术 / 恶魔皮肤
}
local function cls() local _, c = UnitClass("player"); return c end
local function sp(k) local t = SP[cls()] or SP.WARRIOR; return t[k] end

local function auraOf(unit, id, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName and C_Spell and C_Spell.GetSpellName then
        local nm = C_Spell.GetSpellName(id)
        local a = nm and C_UnitAuras.GetAuraDataBySpellName(unit, nm, filter)
        if a then return a end
    end
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and unit == "player" then return C_UnitAuras.GetPlayerAuraBySpellID(id) end
    if UnitAura then
        for i = 1, 40 do
            local name, _, count, _, _, exp, _, _, _, sid = UnitAura(unit, i, filter)
            if not name then return nil end
            if sid == id then return { applications = count, expirationTime = exp, spellId = sid } end
        end
    end
    return nil
end
local function cd(id)
    if C_Spell and C_Spell.GetSpellCooldown then local c = C_Spell.GetSpellCooldown(id); return c and c.startTime end
    if GetSpellCooldown then return (GetSpellCooldown(id)) end
end
local function usable(id)
    if C_Spell and C_Spell.IsSpellUsable then return C_Spell.IsSpellUsable(id) end
    if IsUsableSpell then return IsUsableSpell(id) end
end

-- 战斗中 / 脱战各采样的动态项
local CHECKS = {
    { "资源 UnitPower(主)", function() return UnitPower("player") end },
    { "资源上限 UnitPowerMax", function() return UnitPowerMax("player") end },
    { "连击点 GetComboPoints", function() return GetComboPoints and GetComboPoints("player", "target") end },
    { "连击点 UnitPower(4)", function() return UnitPower("player", 4) end },
    { "主技能冷却", function() return cd(sp("main")) end },
    { "大招冷却", function() return cd(sp("cd")) end },
    { "可用 IsSpellUsable 主技能", function() return usable(sp("main")) end },
    { "可用 IsSpellUsable 触发技(压制/还击)", function() return usable(sp("proc")) end },
    { "自身 buff 层数/剩余", function() local a = auraOf("player", sp("buff"), "HELPFUL"); return a and (a.expirationTime or a.applications) end },
    { "目标 debuff 剩余(撕裂/割裂/腐蚀)", function() local a = UnitExists("target") and auraOf("target", sp("debuff"), "HARMFUL|PLAYER"); return a and a.expirationTime end },
    { "buff 遍历第 1 个 spellId", function()
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL"); return a and a.spellId end
        if UnitAura then return select(10, UnitAura("player", 1, "HELPFUL")) end
    end },
    { "自身血量", function() return UnitHealth("player") end },
    { "目标血量", function() return UnitExists("target") and UnitHealth("target") or false end },
    { "姓名板数量", function() return C_NamePlate and C_NamePlate.GetNamePlates and #(C_NamePlate.GetNamePlates() or {}) end },
    { "姓名板 可攻击", function()
        for _, np in ipairs((C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates()) or {}) do
            local u = np.namePlateUnitToken
            if u then return UnitCanAttack("player", u) end
        end
        return false
    end },
    { "暴雪助手 下一个", function() return C_AssistedCombat and C_AssistedCombat.GetNextCastSpell and C_AssistedCombat.GetNextCastSpell(false) or false end },
    { "动作条 1 号格 GetActionInfo", function() return GetActionInfo and select(2, GetActionInfo(1)) end },
    { "动作条 1 号格 冷却", function() return GetActionCooldown and (GetActionCooldown(1)) end },
    { "动作条 1 号格 可用", function() return IsUsableAction and IsUsableAction(1) end },
}

-- 只测一次的静态能力（键位底座要用）
local function statics()
    local out = {}
    local function add(k, v) out[#out + 1] = k .. "=" .. tostring(v) end
    local _, build, _, iface = GetBuildInfo()
    add("build", build); add("interface", iface); add("class", cls())
    for _, n in ipairs({ "C_AssistedCombat", "C_ActionBar", "C_NamePlate", "C_UnitAuras", "C_Spell", "C_SpellBook", "C_Map", "issecretvalue" }) do
        add("has." .. n, _G[n] ~= nil)
    end
    for _, n in ipairs({ "PickupSpell", "PlaceAction", "PickupAction", "ClearCursor", "SetBinding", "SaveBindings", "GetBindingKey",
        "GetBindingAction", "GetActionInfo", "HasAction", "GetBonusBarOffset", "GetShapeshiftForm", "GetNumShapeshiftForms",
        "GetActionBarPage", "FindSpellBookSlotBySpellID", "GetSpellSubtext", "IsPlayerSpell", "IsSpellKnown", "GetComboPoints",
        "UnitAura", "GetSpellCooldown", "IsUsableSpell", "IsUsableAction" }) do
        add("fn." .. n, type(_G[n]) == "function")
    end
    -- 动作条：有多少格有东西、最高格号（判断 120 还是 180）
    local used, maxSlot = 0, 0
    for i = 1, 200 do
        local ok, has = pcall(HasAction, i)
        if ok and has then used = used + 1; maxSlot = i end
    end
    add("slots.used", used); add("slots.max", maxSlot)
    add("NUM_ACTIONBAR_BUTTONS", NUM_ACTIONBAR_BUTTONS)
    local ok, off = pcall(GetBonusBarOffset); add("bonusBarOffset", ok and off or "err")
    ok, off = pcall(GetNumShapeshiftForms); add("shapeshiftForms", ok and off or "err")
    ok, off = pcall(GetShapeshiftForm); add("shapeshiftNow", ok and off or "err")
    -- 法术等级：1-12 格里是法术的，记「编号:等级字」；看拖上去的是哪一级
    local ranks = {}
    for i = 1, 12 do
        local okA, t, id = pcall(GetActionInfo, i)
        if okA and t == "spell" and id then
            local sub = GetSpellSubtext and GetSpellSubtext(id) or (C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id))
            ranks[#ranks + 1] = id .. ":" .. tostring(sub)
        end
    end
    add("slot1-12.ranks", table.concat(ranks, ","))
    -- 绑定：1 号格的命令和键
    ok, off = pcall(GetBindingKey, "ACTIONBUTTON1"); add("bind.ACTIONBUTTON1", ok and tostring(off) or "err")
    -- 条插件
    for _, a in ipairs({ "Bartender4", "ElvUI", "Dominos" }) do
        local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(a) or (IsAddOnLoaded and IsAddOnLoaded(a))
        add("addon." .. a, loaded and true or false)
    end
    return out
end

local glow = { show = 0, secret = 0, ids = {} }
local run, stat, casts, combats, ticker = false, {}, { ok = 0, secret = 0, ids = {} }, 0, nil

local function sample(inCombat)
    local bucket = inCombat and "C" or "O"
    for _, c in ipairs(CHECKS) do
        local ok, v = pcall(c[2])
        local k = ok and kind(v) or "err"
        local s = stat[c[1]] or {}; stat[c[1]] = s
        s[bucket] = s[bucket] or {}
        s[bucket][k] = (s[bucket][k] or 0) + 1
    end
end

local function summary()
    local out = { "GIFK1", table.concat(statics(), ";") }
    for _, c in ipairs(CHECKS) do
        local s = stat[c[1]] or {}
        local function fmt(b) local t = s[b] or {}; local p = {} for k, n in pairs(t) do p[#p + 1] = k .. "x" .. n end; return table.concat(p, " ") end
        out[#out + 1] = string.format("%s | 战斗:%s | 脱战:%s", c[1], fmt("C"), fmt("O"))
    end
    local ids = {}
    for id, n in pairs(casts.ids) do ids[#ids + 1] = id .. "x" .. n end
    out[#out + 1] = string.format("施法事件 ok%d secret%d ids:%s", casts.ok, casts.secret, table.concat(ids, " "))
    local gids = {}
    for id, n in pairs(glow.ids) do gids[#gids + 1] = id .. "x" .. n end
    out[#out + 1] = string.format("技能发光 收到%d 保密%d ids:%s", glow.show, glow.secret, table.concat(gids, " "))
    out[#out + 1] = "战斗场数 " .. combats
    return out
end

local function save()
    local lines = summary()
    ns.db.keysProbe = { at = time(), lines = lines }
    return lines
end

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(_, ev, unit, _, spellID)
    if not run then return end
    if ev == "UNIT_SPELLCAST_SUCCEEDED" then
        if issecretvalue and issecretvalue(spellID) then casts.secret = casts.secret + 1
        else casts.ok = casts.ok + 1; if spellID then casts.ids[spellID] = (casts.ids[spellID] or 0) + 1 end end
    elseif ev == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        glow.show = glow.show + 1
        if issecretvalue and issecretvalue(unit) then glow.secret = glow.secret + 1
        elseif unit then glow.ids[unit] = (glow.ids[unit] or 0) + 1 end
    elseif ev == "PLAYER_REGEN_DISABLED" then
        combats = combats + 1
    elseif ev == "PLAYER_REGEN_ENABLED" then
        save()
        ns.Print(ns.L("键位探针：第 " .. combats .. " 场战斗已记录（/gif probe keys 停止并看结果）",
            "Keys probe: fight " .. combats .. " recorded (/gif probe keys to stop and view)"))
    end
end)
pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_SUCCEEDED", "player")
pcall(f.RegisterEvent, f, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")   -- 客户端没有这个事件时别报错
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")

function P.Toggle()
    run = not run
    if run then
        stat, casts, combats = {}, { ok = 0, secret = 0, ids = {} }, 0
        glow.show, glow.secret, glow.ids = 0, 0, {}
        sample(false)
        ticker = C_Timer.NewTicker(0.5, function() sample(InCombatLockdown() or UnitAffectingCombat("player")) end)
        ns.Print(ns.L("键位探针已开始：去打木桩或小怪（最好放几次技能、等触发），脱战自动记录；再输 /gif probe keys 停止并看结果",
            "Keys probe started: fight a dummy or mobs, then /gif probe keys again to stop"))
    else
        if ticker then ticker:Cancel() end
        local lines = save()
        ns.ShowBox(ns.L("键位探针结果", "Keys probe result"),
            ns.L("Ctrl+C 复制整行发给开发者（只有能力检测结果，不含角色名）", "Ctrl+C to copy and send to the developer (no character name)"),
            table.concat(lines, " || "))
    end
    return run
end
P._summary = summary   -- 测试用
P._sample = sample
