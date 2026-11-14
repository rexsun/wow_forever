-- 自动生成（services/wow-agent/build_supporters_lua.py），⛔ 别手改：下次打包会覆盖。
-- 数据源 gearinsight.app/api/wow/supporters；费用只带百分比不带金额。
local _, ns = ...; ns = _G.GearInsightForever or ns
ns.SUPPORTERS = {
    updatedAt = "2026-11-07 16:56",
    pct = 12.7, serverPct = 12.7, llmPct = 0.0,
    people = 328, monthCount = 11, count = 349,
    -- { 名字, 区服, 占全部支持的百分比, 留言, 笔数, 大区(cn/us/eu/tw/kr), "PCT", 职业(大写英文), 时间 }
    top = {
        { "糯米团丶丶", "安苏", 28.15, "", 1, "cn", "PCT", "MAGE", "2026-09-25 12:28" },
        { "陈一", "丽丽（四川）", 15.85, "加油", 1, "cn", "PCT", "WARRIOR", "2026-09-24 14:17" },
        { "枫萧吟", "熊猫酒仙", 15.85, "祝我的亲朋[红手熊-暗影之月]早日拿到坐骑贝洛朗", 1, "cn", "PCT", "WARRIOR", "2026-09-20 18:35" },
        { "Fecs", "Illidan", 15.85, "第一次这么支持一个人，加油哥们。来自美服伊利丹20年老玩家", 1, "us", "PCT", "DRUID", "2026-09-19 14:24" },
        { "GearInsight 会员", "", 14.44, "", 8, "cn", "PCT", "", "2026-11-01 11:04" },
        { "冯灬宝宝", "", 8.43, "支持", 1, "cn", "PCT", "", "2026-10-02 06:44" },
        { "毛豆", "", 7.39, "加油", 1, "cn", "PCT", "SHAMAN", "2026-09-21 23:43" },
        { "几两春秋梦丶", "霜之哀伤", 6.34, "", 1, "cn", "PCT", "PRIEST", "2026-09-28 15:04" },
        { "罐儿", "夏维安", 6.34, "作者加油！", 1, "cn", "PCT", "MAGE", "2026-09-24 00:35" },
        { "指上弹冰", "", 6.34, "", 1, "cn", "PCT", "", "2026-09-23 16:11" },
    },
    recent = {
        { "苹果流星", "", 0.63, "支持动力", 1, "cn", "PCT", "HUNTER", "2026-11-07 16:04" },
        { "风织旋律", "死亡之翼", 0.79, "", 1, "cn", "PCT", "HUNTER", "2026-11-07 13:12" },
        { "水木相生", "罗宁", 0.63, "", 1, "cn", "PCT", "SHAMAN", "2026-11-07 10:54" },
        { "软炸豆芽", "安苏", 0.63, "", 1, "cn", "PCT", "", "2026-11-07 06:20" },
        { "软炸豆芽", "", 1.59, "", 1, "cn", "PCT", "MAGE", "2026-11-07 06:15" },
        { "软炸豆芽", "", 0.63, "", 1, "cn", "PCT", "MAGE", "2026-11-07 06:11" },
        { "遥远理想乡", "影之哀伤", 0.63, "", 1, "cn", "PCT", "ROGUE", "2026-11-06 03:34" },
        { "布插图腾", "主宰之剑", 0.63, "", 1, "cn", "PCT", "SHAMAN", "2026-11-05 14:23" },
        { "南蠻小孟獲", "暗影之月", 0.63, "", 1, "kr", "PCT", "", "2026-11-05 11:10" },
        { "雪海熊喵", "暗影裂口", 0.63, "", 1, "cn", "PCT", "MONK", "2026-11-05 08:31" },
        { "沖田杏梨", "加基森", 0.63, "", 1, "cn", "PCT", "DEMONHUNTER", "2026-11-05 00:38" },
    },
}

-- 名字 / 区服 / 留言跟随界面语言：{ 英文, 繁体, 简体 }，缺译显示原文。
local TR = {
    name = {
        ["GearInsight 会员"] = { "GearInsightHuiyuan", "GearInsight 會員", "GearInsight 会员" },
        ["冯灬宝宝"] = { "Fengbaobao", "馮灬寶寶", "冯灬宝宝" },
        ["几两春秋梦丶"] = { "Jiliangchunqiumeng", "幾兩春秋夢丶", "几两春秋梦丶" },
        ["南蠻小孟獲"] = { "Nanmanxiaomenghuo", "南蠻小孟獲", "南蠻小孟獲" },
        ["布插图腾"] = { "Buchatuteng", "布插圖騰", "布插图腾" },
        ["指上弹冰"] = { "Zhishangdanbing", "指上彈冰", "指上弹冰" },
        ["枫萧吟"] = { "Fengxiaoyin", "楓蕭吟", "枫萧吟" },
        ["毛豆"] = { "Maodou", "毛豆", "毛豆" },
        ["水木相生"] = { "Shuimuxiangsheng", "水木相生", "水木相生" },
        ["沖田杏梨"] = { "Chongtianxingli", "沖田杏梨", "沖田杏梨" },
        ["糯米团丶丶"] = { "Nuomituan", "糯米糰丶丶", "糯米团丶丶" },
        ["罐儿"] = { "Guaner", "罐兒", "罐儿" },
        ["软炸豆芽"] = { "Ruanzhadouya", "軟炸豆芽", "软炸豆芽" },
        ["遥远理想乡"] = { "Yaoyuanlixiangxiang", "遙遠理想鄉", "遥远理想乡" },
        ["陈一"] = { "Chenyi", "陳一", "陈一" },
        ["雪海熊喵"] = { "Xuehaixiongmiao", "雪海熊喵", "雪海熊喵" },
        ["风织旋律"] = { "Fengzhixuanlv", "風織旋律", "风织旋律" },
    },
    realm = {
        ["主宰之剑"] = { "The Master's Glaive", "主宰之劍", "" },
        ["丽丽（四川）"] = { "Lili (Sichuan)", "麗麗（四川）", "" },
        ["加基森"] = { "Gadgetzan", "加基森", "" },
        ["夏维安"] = { "Xavian", "夏維安", "" },
        ["安苏"] = { "Anzu", "安蘇", "" },
        ["影之哀伤"] = { "Shadowmourne", "影之哀傷", "" },
        ["暗影之月"] = { "Shadowmoon", "暗影之月", "" },
        ["暗影裂口"] = { "Cleft Of Shadow", "暗影裂口", "" },
        ["死亡之翼"] = { "Deathwing", "死亡之翼", "" },
        ["熊猫酒仙"] = { "Pandaren", "熊貓酒仙", "" },
        ["罗宁"] = { "Rhonin", "羅寧", "" },
        ["霜之哀伤"] = { "Frostmourne", "霜之哀傷", "" },
    },
    msg = {
        ["作者加油！"] = { "Keep it up, dev!", "作者加油！", "作者加油！" },
        ["加油"] = { "Keep it up!", "加油", "加油" },
        ["支持"] = { "Support!", "支持", "支持" },
        ["祝我的亲朋[红手熊-暗影之月]早日拿到坐骑贝洛朗"] = { "Wishing my buddy [Hongshouxiong-Shadowmoon] gets the Belo'ren mount soon!", "祝我的親朋[紅手熊-暗影之月]早日拿到坐騎貝洛朗", "祝我的亲朋[红手熊-暗影之月]早日拿到坐骑贝洛朗" },
        ["第一次这么支持一个人，加油哥们。来自美服伊利丹20年老玩家"] = { "First time I've ever backed someone like this. Keep it up, bro. — a 20-year veteran from Illidan (US)", "第一次這麼支持一個人，加油兄弟。來自美服伊利丹 20 年老玩家", "第一次这么支持一个人，加油哥们。来自美服伊利丹20年老玩家" },
    },
}
local S = ns.SUPPORTERS
local LOC = GetLocale and GetLocale() or "enUS"
local col = (LOC == "zhCN" and 3) or (LOC == "zhTW" and 2) or 1
local function tr(t, s)
    local m = s and t[s]
    local v = m and m[col]
    return (v and v ~= "") and v or s
end
for _, list in ipairs({ S.top or {}, S.recent or {} }) do
    for _, rw in ipairs(list) do
        if not rw[10] then
            rw[10] = rw[1]
            rw[1], rw[2], rw[4] = tr(TR.name, rw[1]), tr(TR.realm, rw[2]), tr(TR.msg, rw[4])
        end
    end
end
