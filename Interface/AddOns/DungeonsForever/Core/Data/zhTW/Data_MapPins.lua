-- ============================================================================
-- 繁體資料副本 · 生成物（_temp/gen_zhtw_data.py 產出，禁手改）
-- 僅 zhTW 客戶端加載：覆蓋同名 ns 表；zhCN 客戶端在此秒退。
-- 轉換管線與 Locales/zhTW.lua 同源（TW 術語詞表 + opencc s2t），
-- 保證資料值與代碼 L 鍵的對查兩側一致。
-- ============================================================================

local gl = (type(GetLocale) == 'function') and GetLocale() or 'zhCN'
if gl ~= 'zhTW' then return end

local _, ns = ...

ns.MapPins = {
    ["hall_of_thanes"] = {
        entrance = { { 50.9, 93.4 } },
        quest = { { 40, 63.8, 96395 }, { 54.6, 16.9, 98423 } },
    },
    ["ragefire_chasm"] = {
        entrance = { { 61, 8.6 } },
    },
    ["ruins_of_lordaeron"] = {
        entrance = { { 61, 21.6 } },
        quest = { { 62.4, 28.5, 95250 } },
    },
    ["shadowfang_keep"] = {
        object = { { 37.3, 53.8, 6895 }, { 47.2, 79.3, 6283, 6 } },
    },
    ["the_deadmines"] = {
        entrance = { { 30.8, 15.7 } },
    },
    ["wailing_caverns"] = {
        entrance = { { 47.1, 60.3 } },
    },
}
