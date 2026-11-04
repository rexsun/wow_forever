-- 推荐装备按天赋（10-18 用户截图「安排下」野德 / 奶德；设计 docs/forever-bis-by-spec-weights.md，用户拍板「可以，先做练级的」）
--   原来「装备」页每格只挑装等最高的一件，跟职业天赋无关 → 奶德、鸟德拿到野德的皮甲。
--   现在：每个职业按天赋一套属性权重（数据 SpecGearData.lua ← scripts/forever_spec_weights.py，三端同一份），
--   每件候选 分数 = Σ 属性 × 权重；命中 / 暴击等「等级」按目标等级换算成 % 再乘权重。
--   天赋：默认按点数最多的那一系自动选（和「默认配点」同一个判断），也能手动切，按角色存 ns.db.ui.gearSpec[角色][职业]。
-- ⛔ 算法和 scripts/forever_spec_weights.py 的 score() 一模一样，gi_forever_spec_gear_test.py 逐件对拍；改一边必须改另一边
local _, ns = ...

local SG = {}
ns.SpecGear = SG

local function D() return ns.SpecGearData end
local function charKey() return (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?") end
local PCT = { hit = true, crit = true, shit = true, scrit = true, dodge = true, parry = true, block = true, haste = true }

function SG.Available() return D() ~= nil end

-- 10-18 服务器上不存在的装备（用户 /gi itemprobe all 实测，ITEM_DATA_LOAD_RESULT 回 false）：推荐里排除，三端同一份名单
function SG.Missing(id)
    return ns.ItemMissing and ns.ItemMissing(id) or false
end

function SG.Specs(cls)
    local d = D()
    return d and d.specs and d.specs[cls] or {}
end

function SG.SpecInfo(cls, key)
    for _, s in ipairs(SG.Specs(cls)) do if s.k == key then return s end end
end

-- 自动：本职业 → 点数最多的系对应哪一套；别的职业 / 没点天赋 → 列表第一套
function SG.AutoSpec(cls)
    local list = SG.Specs(cls)
    if #list == 0 then return nil end
    if cls == (ns.MyClass and ns.MyClass()) and ns.MyMainTree then
        local ok, tree = pcall(ns.MyMainTree)
        if ok and tree then
            for _, s in ipairs(list) do
                for _, t in ipairs(s.trees or {}) do if t == tree then return s.k end end
            end
        end
    end
    return list[1].k
end

-- 手动选的（"auto" / nil = 自动）
function SG.Picked(cls)
    local u = ns.db and ns.db.ui and ns.db.ui.gearSpec
    local p = u and u[charKey()]
    local k = p and p[cls]
    if k and SG.SpecInfo(cls, k) then return k end
    return nil
end

function SG.Current(cls)
    return SG.Picked(cls) or SG.AutoSpec(cls)
end

function SG.Set(cls, key)
    ns.db.ui = ns.db.ui or {}
    ns.db.ui.gearSpec = ns.db.ui.gearSpec or {}
    local ck = charKey()
    ns.db.ui.gearSpec[ck] = ns.db.ui.gearSpec[ck] or {}
    ns.db.ui.gearSpec[ck][cls] = (key and key ~= "auto") and key or nil
end

-- 低于 60 级 1% 需要的等级更少（TBC 公式，60 级 = 1）
function SG.RatingFactor(lv)
    lv = math.max(1, math.min(60, math.floor(tonumber(lv) or 60)))
    return math.max(2, lv - 8) / 52
end

-- 物品分数；没有属性数据 → nil（调用方退回按装等）
function SG.Score(id, slot, cls, key, lv)
    local d = D()
    local st = d and d.st and d.st[id]
    if not st then return nil end
    local sp = SG.SpecInfo(cls, key)
    if not sp then return nil end
    local w, rating, f = sp.w, d.rating, SG.RatingFactor(lv)
    local s = 0
    for k, v in pairs(st) do
        local r = rating[k]
        if r then
            s = s + (w[r[1]] or 0) * v / (r[2] * f)
        elseif k:sub(-1) == "P" and PCT[k:sub(1, -2)] then
            s = s + (w[k:sub(1, -2)] or 0) * v
        elseif k == "dps" then   -- 双持副手那把只打一半伤害（经典旧世规则）
            s = s + (w[slot == "远程" and "dps_r" or "dps_m"] or 0) * v * (slot == "副手" and 0.5 or 1)
        else
            s = s + (w[k] or 0) * v
        end
    end
    return s
end

-- 悬停用：这件对当前天赋最值钱的几项属性（中文名 + 数值）
local STAT_NAME = {
    str = { "力量", "Str" }, agi = { "敏捷", "Agi" }, sta = { "耐力", "Sta" }, int = { "智力", "Int" }, spi = { "精神", "Spi" },
    ap = { "攻强", "AP" }, rap = { "远程攻强", "RAP" }, fap = { "变形攻强", "Feral AP" }, sp = { "法术强度", "Spell power" },
    heal = { "治疗", "Healing" }, spdmg = { "法术伤害", "Spell dmg" }, mp5 = { "回蓝", "MP5" }, armor = { "护甲", "Armor" },
    blockv = { "格挡值", "Block value" }, dps = { "秒伤", "DPS" }, pen = { "法术穿透", "Spell pen" }, def = { "防御", "Defense" },
    hitR = { "命中等级", "Hit rating" }, critR = { "暴击等级", "Crit rating" }, shitR = { "法术命中等级", "Spell hit rating" },
    scritR = { "法术暴击等级", "Spell crit rating" }, defR = { "防御等级", "Defense rating" }, dodgeR = { "躲闪等级", "Dodge rating" },
    parryR = { "招架等级", "Parry rating" }, blockR = { "格挡等级", "Block rating" }, hasteR = { "急速等级", "Haste rating" },
    hitP = { "命中 %", "Hit %" }, critP = { "暴击 %", "Crit %" }, shitP = { "法术命中 %", "Spell hit %" }, scritP = { "法术暴击 %", "Spell crit %" },
    dodgeP = { "躲闪 %", "Dodge %" }, parryP = { "招架 %", "Parry %" }, blockP = { "格挡 %", "Block %" },
    sd_shadow = { "暗影法伤", "Shadow dmg" }, sd_fire = { "火焰法伤", "Fire dmg" }, sd_frost = { "冰霜法伤", "Frost dmg" },
    sd_nature = { "自然法伤", "Nature dmg" }, sd_arcane = { "奥术法伤", "Arcane dmg" }, sd_holy = { "神圣法伤", "Holy dmg" },
}
function SG.TopStats(id, slot, cls, key, lv, n)
    local d = D()
    local st = d and d.st and d.st[id]
    local sp = SG.SpecInfo(cls, key)
    if not (st and sp) then return {} end
    local f = SG.RatingFactor(lv)
    local l = {}
    for k, v in pairs(st) do
        local r = d.rating[k]
        local c
        if r then c = (sp.w[r[1]] or 0) * v / (r[2] * f)
        elseif k:sub(-1) == "P" and PCT[k:sub(1, -2)] then c = (sp.w[k:sub(1, -2)] or 0) * v
        elseif k == "dps" then c = (sp.w[slot == "远程" and "dps_r" or "dps_m"] or 0) * v
        else c = (sp.w[k] or 0) * v end
        if c > 0 then
            local nm = STAT_NAME[k]
            l[#l + 1] = { c = c, t = (nm and ns.L(nm[1], nm[2]) or k) .. " " .. v }
        end
    end
    table.sort(l, function(a, b) if a.c ~= b.c then return a.c > b.c end return a.t < b.t end)
    local out = {}
    for i = 1, math.min(n or 3, #l) do out[i] = l[i].t end
    return out
end

-- 10-29 双手专精：有双手武器就只推双手、副手留空（scripts/forever_spec_weights.py TWO_HAND，网站导出同一条）
function SG.TwoHand(cls, key)
    local d = D()
    return d and d.th and d.th[cls] and d.th[cls][key] and true or false
end

function SG.DualWield(cls, key)
    local d = D()
    return d and d.dw and d.dw[cls] and d.dw[cls][key] and true or false
end
