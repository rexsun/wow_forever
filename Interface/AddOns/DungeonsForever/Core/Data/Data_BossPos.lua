-- =============================================================================
-- 无限副本手册 · 首领在副本地图上的位置（钉点）
--
-- ★ 本文件由 _temp/gen_boss_pos.py 生成，请勿手改 ★
--   数据更新后重跑：python _temp/_df_pin_refetch.py && python _temp/_df_pin_floors2.py
--   && python _temp/gen_boss_pos.py
--
-- -- 结构：ns.BossPos[副本 id] = { [首领英文名] = { {left%, top%[, 层号]}, … } }
--   · 第 3 位 = **客户端层号**（客户端层图文件名的数字后缀，如 ShadowfangKeep7_ 的 7、
--     Gnomeregan10_ 的 10）；缺省 = 第 1 层。界面按 ART 前缀尾数字把层号映射成显示序号。
--   · 键 = 首领**英文名**，与 ns.DungeonLoot 的来源名 / ns.DungeonGuide 的
--     bosses[].en 同一个口径 —— 名字是这里唯一的跨表连接键。
--   · 坐标 = 相对客户端原图 1002×668 的百分比，左上为原点（fc 站地图同口径）；
--   · 一个首领有多个坐标 = 它有多个刷新点，界面上画成多个钉点。
--   · 稀有怪（fc faceKind=rare）与首领同表收录（掉落表里本就是来源行）。
--   · fc faceKind=object 的物件点不进本表（物品钉归 ns.MapPins，_temp/fc_pins.py）。
--   · 挖掘场湿地不在 fc 改版页：用户在游戏地图页手工标注（_bosspos_manual.json）。
--   · 只收录采到坐标的副本；没收录的副本地图页没有钉点，靠首领选择条选。
-- =============================================================================
-- 2026-10-05 全量重采（fc 改版页 floors.pins 回铺，前 8 本低级副本 + 2 自制）：
--   剃刀沼泽首次收录 9 钉（含盲眼猎手/唤地者哈穆加 2 稀有）；监狱 +德克斯伦·沃德
--   3 刷点；洛丹伦废墟 +洛丹伦卫兵。★ fc 对影牙/领主大厅/洛丹伦废墟旧点的
--   坐标「校准」不收（用户拍板），生成器 REVERT 层回退旧值。
-- =============================================================================

local _, ns = ...

ns.BossPos = {
    ["ragefire_chasm"] = {
        ["Bazzalan"] = { { 41.5, 86.2 } },
        ["Jergosh the Invoker"] = { { 33, 84.5 } },
        ["Oggleflint"] = { { 56.1, 38 } },
        ["Taragaman the Hungerer"] = { { 41, 57.7 } },
    },
    ["wailing_caverns"] = {
        ["Kresh"] = { { 25.8, 44.6 } },
        ["Lady Anacondra"] = { { 30.5, 43.2 }, { 28.1, 31.8 }, { 47, 45.6 }, { 40.3, 27.4 } },
        ["Lord Cobrahn"] = { { 15.6, 58.5 } },
        ["Lord Serpentis"] = { { 62.5, 53.3 } },
        ["Mutanus the Devourer"] = { { 34.2, 15.8 } },
        ["Verdan the Everliving"] = { { 56.4, 47.4 } },
    },
    ["the_deadmines"] = {
        ["Captain Greenskin"] = { { 61.7, 35.9, 2 } },
        ["Cookie"] = { { 69.7, 42, 2 } },
        ["Edwin VanCleef"] = { { 60.6, 45.9, 2 } },
        ["Gilnid"] = { { 11.9, 73.1, 2 } },
        ["Miner Johnson"] = { { 52.7, 50.5 } },
        ["Mr. Smite"] = { { 56.1, 26.5, 2 } },
        ["Rhahk'Zor"] = { { 38.6, 60.9 } },
        ["Sneed"] = { { 45, 88.9 } },
        ["Sneed's Shredder"] = { { 48.5, 92.4 } },
    },
    ["shadowfang_keep"] = {
        ["Archmage Arugal"] = { { 63.9, 20, 6 } },
        ["Baron Silverlaine"] = { { 29.5, 80.3, 2 } },
        ["Commander Springvale"] = { { 27.9, 59.3 } },
        ["Deathsworn Captain"] = { { 63, 52.5, 7 } },
        ["Fel Steed / Shadow Charger"] = { { 36, 62.9 } },
        ["Fenrus the Devourer"] = { { 55.7, 64.5, 6 } },
        ["Odo the Blindwatcher"] = { { 55.1, 77.1, 7 } },
        ["Razorclaw the Butcher"] = { { 48, 29, 2 } },
        ["Rethilgore"] = { { 66.1, 71.1 } },
        ["Wolf Master Nandos"] = { { 59, 53.3, 6 } },
    },
    ["blackfathom_deeps"] = {
        ["Aku'mai"] = { { 85.6, 86.6, 2 } },
        ["Baron Aquanis"] = { { 41.5, 75.4, 2 } },
        ["Gelihast"] = { { 52.3, 55.1 } },
        ["Ghamoo-ra"] = { { 32.9, 60.2 } },
        ["Lady Sarevess"] = { { 10.1, 36 } },
        ["Lorgus Jett"] = { { 38.8, 20, 2 }, { 44.1, 23.4, 2 }, { 35.4, 48.3, 2 }, { 33.8, 72.3, 2 } },
        ["Old Serra'kis"] = { { 60.6, 31.2, 3 } },
        ["Twilight Lord Kelris"] = { { 51.9, 81.6, 2 } },
    },
    ["the_stockade"] = {
        ["Bazil Thredd"] = { { 85.7, 51 } },
        ["Bruegal Ironknuckle"] = { { 38.1, 24 }, { 29.5, 44.7 }, { 61.6, 48.3 }, { 61.5, 25.1 } },
        ["Dextren Ward"] = { { 14.6, 21.4 }, { 25, 16.5 }, { 17.5, 41.7 } },
        ["Hamhock"] = { { 78.2, 45.7 } },
        ["Kam Deepfury"] = { { 69.2, 30.9 } },
        ["Targorr the Dread"] = { { 49.9, 24.2 }, { 42.4, 46.4 }, { 57.8, 55.2 }, { 33.3, 37.5 } },
    },
    ["gnomeregan"] = {
        ["Crowd Pummeler 9-60"] = { { 43.8, 86.5, 3 } },
        ["Dark Iron Ambassador"] = { { 29.5, 54, 4 } },
        ["Electrocutioner 6000"] = { { 24.8, 67.9, 2 } },
        ["Grubbis"] = { { 81.9, 65.1 } },
        ["Mekgineer Thermaplugg"] = { { 31.3, 30, 4 } },
        ["Viscous Fallout"] = { { 57.6, 56.6 } },
    },
    ["razorfen_kraul"] = {
        ["Agathelos the Raging"] = { { 11.2, 72.4 } },
        ["Aggem Thorncurse"] = { { 80.8, 54.5 } },
        ["Blind Hunter"] = { { 11, 30.3 } },
        ["Charlga Razorflank"] = { { 26.4, 32.4 } },
        ["Death Speaker Jargba"] = { { 87.9, 41.4 } },
        ["Earthcaller Halmgar"] = { { 49.4, 47.1 } },
        ["Overlord Ramtusk"] = { { 56.9, 29.8 } },
        ["Razorfen Spearhide"] = { { 53.4, 35.5 } },
        ["Roogug"] = { { 64.8, 42.1 } },
    },
    ["hall_of_thanes"] = {
        ["Durgen Dirgehammer"] = { { 50.5, 23.1 } },
        ["Faldrim Anvilmar"] = { { 50.4, 63.6 } },
        ["Magmatus"] = { { 62, 50.1 } },
        ["Plunder"] = { { 50.5, 50.6 } },
    },
    ["ruins_of_lordaeron"] = {
        ["Bjork"] = { { 34.7, 42.5 } },
        ["Lordaeron Captain"] = { { 38.5, 25 } },
        ["Rath'mael"] = { { 41.3, 62.7 } },
        ["The Abandoned"] = { { 36.5, 53.3 } },
        ["The Baron"] = { { 58.8, 69.8 } },
        ["Viktor the Vile"] = { { 33.2, 64.8 } },
        ["Witherfang"] = { { 66.8, 39.2 } },
    },
    ["excavation_wetlands"] = {
        ["Highland Horror"] = { { 26.3, 56.2 } },
        ["Relic Guardian"] = { { 46.6, 74.1 } },
        ["Saltspine"] = { { 62, 47.1 } },
        ["Shadetooth"] = { { 40.6, 53.6 } },
    },
}
