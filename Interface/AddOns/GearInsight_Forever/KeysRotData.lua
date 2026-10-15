-- 键位手法 · 手法规则表（10-10，docs/forever-keybind-rotation-design.md §5.2）
-- 来源 src = "hand"：按经典旧世成熟打法 + 《无限》技能改动手写（《无限》猛击有 15 秒冷却、术士诅咒改「灾祸」）。
-- 以后「公测版 / WCL 版」导出同一种格式（src = "beta" / "wcl"，可带 tree 决策树和 conf 考试成绩），引擎 KeysRot.lua 不用改。
--
-- 条件 when（全部满足才按；引擎读不到的条件按「满足」处理，并在依据里写「推算」）：
--   "ready"         这个技能能按：IsSpellUsable 为真 + 冷却好了（冷却读不到就按上次施放 + 冷却时长推算）
--   "proc"          只在触发后可用的技能（压制 / 复仇 / 还击 / 斩杀）：IsSpellUsable 为真就算
--                   ⛔ 吸取灵魂 / 暗影灼烧任何时候都能放（不是触发技），「目标快死才用」要读目标血量 → 等 P0 确认读得到再加
--   "res>=N"        主资源（怒气 / 能量）≥ N；读不到就不判断（IsSpellUsable 已经保证够按）
--   "mana<N"        法力百分比 < N
--   "cp>=N"         连击点 ≥ N（读不到就按「攒点技能 +1、终结技清零」记账）
--   "dot<N"         这个技能在当前目标身上的持续伤害剩余 < N 秒（自己记账：施放时间 + dur）
--   "buff<N"        这个技能给自己的增益剩余 < N 秒（同上，记账）
--   "stack<N"       这个技能在目标身上叠的层数 < N（破甲攻击；记账）
--   "targets>=N"    8 码内可攻击的敌人（姓名板）≥ N
--   "known:名字"    学会了另一个技能才按（例：学会了致死打击才不打猛击当主力）
-- dur = 持续时间（秒，记账用；Beta 改了以 P0 实测为准）
local _, ns = ...

ns.KeysRotData = {
    Warrior = {
        [1] = { v = 1, src = "hand", name = { "武器", "Arms" }, rules = {
            { cast = "斩杀", when = { "proc" }, why = { "目标进斩杀线，斩杀优先", "Execute range - Execute first" } },
            { cast = "致死打击", when = { "ready" }, why = { "致死打击转好就打", "Mortal Strike on cooldown" } },
            { cast = "压制", when = { "proc" }, why = { "压制亮了（目标刚躲闪）", "Overpower is up (target dodged)" } },
            { cast = "旋风斩", when = { "ready", "targets>=2" }, why = { "两个以上目标，旋风斩", "2+ targets - Whirlwind" } },
            { cast = "撕裂", when = { "ready", "dot<1.5" }, dur = 15, why = { "撕裂快没了补上", "Rend about to fall off" } },
            { cast = "猛击", when = { "ready" }, why = { "猛击转好（《无限》猛击有冷却）", "Slam is ready (on cooldown in Forever)" } },
            { cast = "顺劈斩", when = { "ready", "targets>=2", "res>=40" }, why = { "怒气多、两个目标：顺劈斩泄怒", "Rage to spare and 2 targets - Cleave" } },
            { cast = "英勇打击", when = { "ready", "res>=50" }, why = { "怒气快溢出：英勇打击泄掉", "Rage capping - dump into Heroic Strike" } },
        } },
        [2] = { v = 1, src = "hand", name = { "狂怒", "Fury" }, rules = {
            { cast = "斩杀", when = { "proc" }, why = { "目标进斩杀线，斩杀优先", "Execute range - Execute first" } },
            { cast = "嗜血", when = { "ready" }, why = { "嗜血转好就打", "Bloodthirst on cooldown" } },
            { cast = "旋风斩", when = { "ready" }, why = { "旋风斩转好就打", "Whirlwind on cooldown" } },
            { cast = "压制", when = { "proc" }, why = { "压制亮了（目标刚躲闪）", "Overpower is up" } },
            { cast = "猛击", when = { "ready" }, why = { "猛击转好", "Slam is ready" } },
            { cast = "顺劈斩", when = { "ready", "targets>=2", "res>=40" }, why = { "怒气多、两个目标：顺劈斩", "2 targets - Cleave" } },
            { cast = "英勇打击", when = { "ready", "res>=50" }, why = { "怒气快溢出：英勇打击泄掉", "Rage capping - Heroic Strike" } },
        } },
        [3] = { v = 1, src = "hand", name = { "防护", "Protection" }, rules = {
            { cast = "盾牌猛击", when = { "ready" }, why = { "盾牌猛击转好就打（仇恨最高）", "Shield Slam on cooldown (most threat)" } },
            { cast = "复仇", when = { "proc" }, why = { "复仇亮了（刚格挡 / 躲闪 / 招架）", "Revenge is up" } },
            { cast = "破甲攻击", when = { "ready", "stack<5" }, dur = 30, why = { "破甲还没叠满 5 层", "Sunder Armor below 5 stacks" } },
            { cast = "雷霆一击", when = { "ready", "targets>=3" }, why = { "三个以上怪：雷霆一击拉仇恨", "3+ mobs - Thunder Clap" } },
            { cast = "顺劈斩", when = { "ready", "targets>=2", "res>=40" }, why = { "多目标：顺劈斩", "Multiple targets - Cleave" } },
            { cast = "英勇打击", when = { "ready", "res>=40" }, why = { "怒气够：英勇打击加仇恨", "Spare rage - Heroic Strike for threat" } },
            { cast = "破甲攻击", when = { "ready" }, dur = 30, why = { "没别的可按：破甲刷新", "Nothing else - refresh Sunder" } },
        } },
        [0] = { v = 1, src = "hand", name = { "升级期", "Leveling" }, rules = {
            { cast = "斩杀", when = { "proc" }, why = { "目标进斩杀线，斩杀", "Execute range" } },
            { cast = "压制", when = { "proc" }, why = { "压制亮了", "Overpower is up" } },
            { cast = "撕裂", when = { "ready", "dot<1.5" }, dur = 15, why = { "撕裂没挂上", "Rend not on target" } },
            { cast = "猛击", when = { "ready" }, why = { "猛击转好", "Slam is ready" } },
            { cast = "英勇打击", when = { "ready", "res>=30" }, why = { "怒气够：英勇打击", "Rage up - Heroic Strike" } },
        } },
    },
    Rogue = {
        [1] = { v = 1, src = "hand", name = { "刺杀", "Assassination" }, rules = {
            { cast = "切割", when = { "ready", "cp>=1", "buff<2" }, dur = 21, why = { "切割快断了先补", "Slice and Dice about to drop" } },
            { cast = "割裂", when = { "ready", "cp>=5", "dot<1.5" }, dur = 16, why = { "5 星：割裂没挂就挂", "5 points - apply Rupture" } },
            { cast = "毒针", when = { "ready", "cp>=5" }, why = { "5 星：毒针", "5 points - Venom" } },
            { cast = "刺骨", when = { "ready", "cp>=5" }, why = { "5 星：刺骨", "5 points - Eviscerate" } },
            { cast = "毁伤", when = { "ready" }, why = { "攒连击点：毁伤", "Build points - Mutilate" } },
            { cast = "邪恶攻击", when = { "ready" }, why = { "攒连击点：邪恶攻击", "Build points - Sinister Strike" } },
        } },
        [2] = { v = 1, src = "hand", name = { "战斗", "Combat" }, rules = {
            { cast = "切割", when = { "ready", "cp>=1", "buff<2" }, dur = 21, why = { "切割快断了先补（战斗贼最重要的增益）", "Slice and Dice about to drop" } },
            { cast = "还击", when = { "proc" }, why = { "还击亮了（刚招架）", "Riposte is up (you parried)" } },
            { cast = "刺骨", when = { "ready", "cp>=5" }, why = { "5 星：刺骨", "5 points - Eviscerate" } },
            { cast = "邪恶攻击", when = { "ready" }, why = { "攒连击点：邪恶攻击", "Build points - Sinister Strike" } },
        } },
        [3] = { v = 1, src = "hand", name = { "敏锐", "Subtlety" }, rules = {
            { cast = "切割", when = { "ready", "cp>=1", "buff<2" }, dur = 21, why = { "切割快断了先补", "Slice and Dice about to drop" } },
            { cast = "刺骨", when = { "ready", "cp>=5" }, why = { "5 星：刺骨", "5 points - Eviscerate" } },
            { cast = "鬼魅攻击", when = { "ready" }, why = { "鬼魅攻击转好", "Ghostly Strike ready" } },
            { cast = "出血", when = { "ready" }, why = { "攒连击点：出血", "Build points - Hemorrhage" } },
            { cast = "邪恶攻击", when = { "ready" }, why = { "攒连击点：邪恶攻击", "Build points - Sinister Strike" } },
        } },
        [0] = { v = 1, src = "hand", name = { "升级期", "Leveling" }, rules = {
            { cast = "切割", when = { "ready", "cp>=2", "buff<1" }, dur = 15, why = { "切割没开就开", "Open Slice and Dice" } },
            { cast = "刺骨", when = { "ready", "cp>=4" }, why = { "4 星以上：刺骨", "4+ points - Eviscerate" } },
            { cast = "邪恶攻击", when = { "ready" }, why = { "攒连击点：邪恶攻击", "Build points - Sinister Strike" } },
        } },
    },
    Warlock = {
        [1] = { v = 1, src = "hand", name = { "痛苦", "Affliction" }, rules = {
            { cast = "腐蚀术", when = { "ready", "dot<1.5" }, dur = 18, why = { "腐蚀术快没了补上", "Corruption about to fall off" } },
            { cast = "痛苦灾祸", when = { "ready", "dot<1.5" }, dur = 24, why = { "痛苦灾祸快没了补上", "Bane of Agony about to fall off" } },
            { cast = "生命虹吸", when = { "ready", "dot<1.5" }, dur = 30, why = { "生命虹吸快没了补上", "Siphon Life about to fall off" } },
            { cast = "生命分流", when = { "ready", "mana<20" }, why = { "法力不到 20%：生命分流", "Mana under 20% - Life Tap" } },
            { cast = "暗影箭", when = { "ready" }, why = { "DoT 都挂着：暗影箭填充", "DoTs up - Shadow Bolt filler" } },
        } },
        [2] = { v = 1, src = "hand", name = { "恶魔学识", "Demonology" }, rules = {
            { cast = "腐蚀术", when = { "ready", "dot<1.5" }, dur = 18, why = { "腐蚀术快没了补上", "Corruption about to fall off" } },
            { cast = "痛苦灾祸", when = { "ready", "dot<1.5" }, dur = 24, why = { "痛苦灾祸快没了补上", "Bane of Agony about to fall off" } },
            { cast = "生命分流", when = { "ready", "mana<20" }, why = { "法力不到 20%：生命分流", "Mana under 20% - Life Tap" } },
            { cast = "暗影箭", when = { "ready" }, why = { "暗影箭填充", "Shadow Bolt filler" } },
        } },
        [3] = { v = 1, src = "hand", name = { "毁灭", "Destruction" }, rules = {
            { cast = "献祭", when = { "ready", "dot<1.5" }, dur = 15, why = { "献祭快没了补上（燃烧要它）", "Immolate about to fall off (Conflagrate needs it)" } },
            { cast = "燃烧", when = { "ready" }, why = { "燃烧转好就打", "Conflagrate on cooldown" } },
            { cast = "腐蚀术", when = { "ready", "dot<1.5" }, dur = 18, why = { "腐蚀术快没了补上", "Corruption about to fall off" } },
            { cast = "生命分流", when = { "ready", "mana<20" }, why = { "法力不到 20%：生命分流", "Mana under 20% - Life Tap" } },
            { cast = "烧尽", when = { "ready" }, why = { "烧尽填充", "Incinerate filler" } },
            { cast = "暗影箭", when = { "ready" }, why = { "暗影箭填充", "Shadow Bolt filler" } },
        } },
        [0] = { v = 1, src = "hand", name = { "升级期", "Leveling" }, rules = {
            { cast = "腐蚀术", when = { "ready", "dot<1.5" }, dur = 18, why = { "腐蚀术没挂上", "Corruption not on target" } },
            { cast = "痛苦灾祸", when = { "ready", "dot<1.5" }, dur = 24, why = { "痛苦灾祸没挂上", "Bane of Agony not on target" } },
            { cast = "献祭", when = { "ready", "dot<1.5" }, dur = 15, why = { "献祭没挂上", "Immolate not on target" } },
            { cast = "生命分流", when = { "ready", "mana<20" }, why = { "法力不到 20%：生命分流", "Mana under 20% - Life Tap" } },
            { cast = "暗影箭", when = { "ready" }, why = { "暗影箭填充", "Shadow Bolt filler" } },
        } },
    },
}
