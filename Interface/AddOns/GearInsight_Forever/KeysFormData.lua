-- 自动生成（scripts/gi_forever_keys_forms.py ← 《无限》DB2 SpellShapeshift / SpellShapeshiftForm），⛔别手改。
-- 键位页形态切换：每职业的形态（页 = 主条在该形态下换成的形态页号，nil = 主条本身）+ 每个技能能在哪些形态用。
-- spells 键：技能编号（Data.keys 的 id）或英文名（天赋技能）；没列的技能按 def。
local _, ns = ...; ns = _G.GearInsightForever or ns
ns.KeysForms = {
    Druid = {
        forms = {
            { key = "caster", zh = "人形态", en = "Caster", page = nil },
            { key = "bear", zh = "熊形态", en = "Bear", page = 3 },
            { key = "cat", zh = "豹形态", en = "Cat", page = 1 },
        },
        def = { "caster" },
        spells = {
            [99] = { "bear" },   -- 挫志咆哮
            [6807] = { "bear" },   -- 槌击
            [779] = { "bear" },   -- 挥击
            [1079] = { "cat" },   -- 撕扯
            [1082] = { "cat" },   -- 爪击
            [5221] = { "cat" },   -- 撕碎
            [1822] = { "cat" },   -- 扫击
            [5217] = { "caster", "bear", "cat" },   -- 猛虎之怒（各形态通用）
            ["Primal Bite"] = { "bear" },   -- 原始撕咬
            [8998] = { "cat" },   -- 畏缩
            [22568] = { "cat" },   -- 凶猛撕咬
            [6785] = { "cat" },   -- 毁灭
            [414644] = { "bear" },   -- 割伤
            [1850] = { "cat" },   -- 急奔
            [6795] = { "bear" },   -- 低吼
            [5209] = { "bear" },   -- 挑战咆哮
            [5211] = { "bear" },   -- 重击
            [16810] = { "caster", "bear", "cat" },   -- 自然之握（各形态通用）
            ["Shifting Power"] = { "cat" },   -- 变换之力
            [9005] = { "cat" },   -- 突袭
            ["Berserk"] = { "cat" },   -- 狂暴
            [22812] = { "caster", "bear", "cat" },   -- 树皮术（各形态通用）
            [1238122] = { "bear", "cat" },   -- 野性冲锋
            [5215] = { "cat" },   -- 潜行
            [5229] = { "bear" },   -- 狂怒
            [770] = { "caster", "bear", "cat" },   -- 精灵之火
            [5225] = { "cat" },   -- 追踪人型生物
            [22842] = { "bear" },   -- 狂暴回复
        },
    },
    Warrior = {
        forms = {
            { key = "battle", zh = "战斗姿态", en = "Battle", page = 1 },
            { key = "defensive", zh = "防御姿态", en = "Defensive", page = 2 },
            { key = "berserker", zh = "狂暴姿态", en = "Berserker", page = 3 },
        },
        def = { "battle", "defensive", "berserker" },
        spells = {
            [7384] = { "battle" },   -- 压制
            [6572] = { "defensive" },   -- 复仇
            [5308] = { "battle", "berserker" },   -- 斩杀
            [1680] = { "berserker" },   -- 旋风斩
            [772] = { "battle", "defensive" },   -- 撕裂
            [6343] = { "battle", "defensive" },   -- 雷霆一击
            [1310222] = { "battle" },   -- 穿刺打击
            [1715] = { "battle", "berserker" },   -- 断筋
            ["Sweeping Strikes"] = { "battle" },   -- 横扫攻击
            [1719] = { "berserker" },   -- 鲁莽
            [72] = { "battle", "defensive" },   -- 盾击
            [6552] = { "berserker" },   -- 拳击
            [355] = { "defensive" },   -- 嘲讽
            [694] = { "battle" },   -- 惩戒痛击
            [2565] = { "defensive" },   -- 盾牌格挡
            [20230] = { "battle" },   -- 反击风暴
            [871] = { "defensive" },   -- 盾墙
            [18499] = { "berserker" },   -- 狂暴之怒
            [100] = { "battle" },   -- 冲锋
            [20252] = { "berserker" },   -- 拦截
            [676] = { "defensive" },   -- 缴械
        },
    },
    Rogue = {
        forms = {
            { key = "normal", zh = "普通", en = "Normal", page = nil },
            { key = "stealth", zh = "潜行", en = "Stealth", page = 1 },
        },
        def = { "normal", "stealth" },
        spells = {
            [8676] = { "stealth" },   -- 伏击
            [1833] = { "stealth" },   -- 偷袭
            [703] = { "stealth" },   -- 绞喉
            ["Preparation"] = { "normal", "stealth" },   -- 伺机待发（各形态通用）
            ["Blade Flurry"] = { "normal", "stealth" },   -- 剑刃乱舞（各形态通用）
            [6770] = { "stealth" },   -- 闷棍
            [438040] = { "normal", "stealth" },   -- 转嫁（各形态通用）
            [921] = { "stealth" },   -- 搜索
            [1725] = { "normal", "stealth" },   -- 扰乱（各形态通用）
        },
    },
}
