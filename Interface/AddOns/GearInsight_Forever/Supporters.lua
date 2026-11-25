-- 自动生成（services/wow-agent/build_supporters_lua.py），⛔ 别手改：下次打包会覆盖。
-- 数据源 gearinsight.app/api/wow/supporters；费用只带百分比不带金额。
local _, ns = ...; ns = _G.GearInsightForever or ns
ns.SUPPORTERS = {
    updatedAt = "2026-11-17 22:56",
    pct = 52.5, serverPct = 37.5, llmPct = 15.1,
    people = 379, monthCount = 29, count = 404,
    -- { 名字, 区服, 占全部支持的百分比, 留言, 笔数, 大区(cn/us/eu/tw/kr), "PCT", 职业(大写英文), 时间 }
    top = {
        { "糯米团丶丶", "安苏", 26.17, "", 1, "cn", "PCT", "MAGE", "2026-09-25 12:28" },
        { "GearInsight 会员", "", 24.50, "", 12, "cn", "PCT", "", "2026-11-13 14:08" },
        { "陈一", "丽丽（四川）", 14.74, "加油", 1, "cn", "PCT", "WARRIOR", "2026-09-24 14:17" },
        { "枫萧吟", "熊猫酒仙", 14.74, "祝我的亲朋[红手熊-暗影之月]早日拿到坐骑贝洛朗", 1, "cn", "PCT", "WARRIOR", "2026-09-20 18:35" },
        { "Fecs", "Illidan", 14.74, "第一次这么支持一个人，加油哥们。来自美服伊利丹20年老玩家", 1, "us", "PCT", "DRUID", "2026-09-19 14:24" },
        { "维密收割机", "", 8.49, "为众人拾柴抱薪者加油", 1, "cn", "PCT", "", "2026-11-10 10:10" },
        { "冯灬宝宝", "", 7.84, "支持", 1, "cn", "PCT", "", "2026-10-02 06:44" },
        { "毛豆", "", 6.87, "加油", 1, "cn", "PCT", "SHAMAN", "2026-09-21 23:43" },
        { "虚空精灵女王", "燃烧之刃", 5.89, "加油", 1, "cn", "PCT", "WARLOCK", "2026-11-12 09:32" },
        { "几两春秋梦丶", "霜之哀伤", 5.89, "", 1, "cn", "PCT", "PRIEST", "2026-09-28 15:04" },
    },
    recent = {
        { "张老六七八九", "无尽之海", 2.95, "", 1, "cn", "PCT", "MAGE", "2026-11-17 21:48" },
        { "一条大河", "", 0.59, "好好做", 1, "cn", "PCT", "DEATHKNIGHT", "2026-11-17 21:30" },
        { "鞭子配碘伏", "CAMWOW CN1 Realm 11 PvP", 0.59, "", 1, "cn", "PCT", "", "2026-11-17 21:18" },
        { "五花肉归来", "冰风岗", 0.59, "", 1, "cn", "PCT", "DEMONHUNTER", "2026-11-17 16:12" },
        { "洛嫣", "凤凰之神", 0.59, "", 1, "cn", "PCT", "PALADIN", "2026-11-17 13:18" },
        { "福福吃不饱", "", 0.59, "", 1, "cn", "PCT", "", "2026-11-16 22:42" },
        { "北逸", "CN1 Realm 7 PvE", 0.29, "", 1, "cn", "PCT", "", "2026-11-16 20:07" },
        { "小麦果", "泰兰德", 0.59, "", 1, "cn", "PCT", "SHAMAN", "2026-11-16 19:02" },
        { "阿尔特弥斯", "CN5 Realm 1 PvP", 0.59, "", 1, "cn", "PCT", "", "2026-11-16 17:41" },
        { "Asen", "CAMWOW CN1 Realm 12 PvP", 0.59, "", 1, "cn", "PCT", "", "2026-11-16 09:51" },
        { "Ei", "CN5 Realm 4 PvP", 0.59, "", 1, "cn", "PCT", "", "2026-11-16 09:16" },
        { "菜", "CN1 Realm 3 PvE", 0.59, "", 1, "cn", "PCT", "", "2026-11-15 23:54" },
        { "神行 太保", "", 0.59, "", 1, "cn", "PCT", "", "2026-11-15 23:26" },
        { "代代木", "CN5 Realm 6 PvP", 0.59, "幸苦了", 1, "cn", "PCT", "", "2026-11-15 21:06" },
        { "軒軒騎", "", 0.59, "", 1, "cn", "PCT", "", "2026-11-15 04:17" },
    },
}

-- 名字 / 区服 / 留言跟随界面语言：{ 英文, 繁体, 简体 }，缺译显示原文。
local TR = {
    name = {
        ["GearInsight 会员"] = { "GearInsightHuiyuan", "GearInsight 會員", "GearInsight 会员" },
        ["一条大河"] = { "Yitiaodahe", "一條大河", "一条大河" },
        ["五花肉归来"] = { "Wuhuarouguilai", "五花肉歸來", "五花肉归来" },
        ["代代木"] = { "Daidaimu", "代代木", "代代木" },
        ["冯灬宝宝"] = { "Fengbaobao", "馮灬寶寶", "冯灬宝宝" },
        ["几两春秋梦丶"] = { "Jiliangchunqiumeng", "幾兩春秋夢丶", "几两春秋梦丶" },
        ["北逸"] = { "Beiyi", "北逸", "北逸" },
        ["小麦果"] = { "Xiaomaiguo", "小麥果", "小麦果" },
        ["张老六七八九"] = { "Zhanglaoliuqibajiu", "張老六七八九", "张老六七八九" },
        ["枫萧吟"] = { "Fengxiaoyin", "楓蕭吟", "枫萧吟" },
        ["毛豆"] = { "Maodou", "毛豆", "毛豆" },
        ["洛嫣"] = { "Luoyan", "洛嫣", "洛嫣" },
        ["神行 太保"] = { "Shenxingtaibao", "神行 太保", "神行 太保" },
        ["福福吃不饱"] = { "Fufuchibubao", "福福吃不飽", "福福吃不饱" },
        ["糯米团丶丶"] = { "Nuomituan", "糯米糰丶丶", "糯米团丶丶" },
        ["维密收割机"] = { "Weimishougeji", "維密收割機", "维密收割机" },
        ["菜"] = { "Cai", "菜", "菜" },
        ["虚空精灵女王"] = { "Xukongjinglingnvwang", "虛空精靈女王", "虚空精灵女王" },
        ["軒軒騎"] = { "Xuanxuanqi", "軒軒騎", "軒軒騎" },
        ["阿尔特弥斯"] = { "Aertemisi", "阿爾特彌斯", "阿尔特弥斯" },
        ["陈一"] = { "Chenyi", "陳一", "陈一" },
        ["鞭子配碘伏"] = { "Bianzipeidianfu", "鞭子配碘伏", "鞭子配碘伏" },
    },
    realm = {
        ["丽丽（四川）"] = { "Lili (Sichuan)", "麗麗（四川）", "" },
        ["冰风岗"] = { "Chillwind Point", "冰風崗", "" },
        ["凤凰之神"] = { "Al'ar", "鳳凰之神", "" },
        ["安苏"] = { "Anzu", "安蘇", "" },
        ["无尽之海"] = { "The Great Sea", "無盡之海", "" },
        ["泰兰德"] = { "Tyrande", "泰蘭德", "" },
        ["熊猫酒仙"] = { "Pandaren", "熊貓酒仙", "" },
        ["燃烧之刃"] = { "Burning Blade", "燃燒之刃", "" },
        ["霜之哀伤"] = { "Frostmourne", "霜之哀傷", "" },
    },
    msg = {
        ["为众人拾柴抱薪者加油"] = { "To the one who gathers firewood for all of us — keep it up!", "為眾人拾柴抱薪者加油", "为众人拾柴抱薪者加油" },
        ["加油"] = { "Keep it up!", "加油", "加油" },
        ["好好做"] = { "Keep up the good work!", "好好做", "好好做" },
        ["幸苦了"] = { "Thanks for all your hard work!", "辛苦了！", "幸苦了" },
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
