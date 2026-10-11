-- ============================================================================
-- 繁體資料副本 · 生成物（_temp/gen_zhtw_data.py 產出，禁手改）
-- 僅 zhTW 客戶端加載：覆蓋同名 ns 表；zhCN 客戶端在此秒退。
-- 轉換管線與 Locales/zhTW.lua 同源（TW 術語詞表 + opencc s2t），
-- 保證資料值與代碼 L 鍵的對查兩側一致。
-- ============================================================================

local gl = (type(GetLocale) == 'function') and GetLocale() or 'zhCN'
if gl ~= 'zhTW' then return end

local _, ns = ...

if (type(GetLocale) == "function") and GetLocale() ~= "zhCN" then return end

ns.NameOverrides = {
    spell = {
        [1279399] = "召喚軍馬",
        [1296534] = "召喚被遺忘者戰馬",
    },
}
