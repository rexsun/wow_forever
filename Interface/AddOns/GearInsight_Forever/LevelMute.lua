-- HOLD：屏蔽别人的升级播报（10-26 玩家群反馈：「能不能加个屏蔽别人的升级播报啥的，公会里全是各家插件各种升级提醒，
--   已经严重影响正常交流了」「这种播报很必要吗，为什么每家都在做」）
-- ① 公会 / 官员 / 小队 / 团队 / 副本 / 说 / 喊 / 数字频道里，别人发的「升级播报」不显示（各家插件 + 我们自己的 [GearInsight插件]）
--    判据要「插件味」：「从 4 级升到 5 级」直接算；「升到 20 级」这类得再带用时 / 方括号前缀 / 恭喜 / Ding 才算 ——
--    玩家正常说「我刚升到 20 级，XX 怎么走」不会被吞
-- ② 自己发的不屏蔽（看得到自己的播报发出去了）；悄悄话不管
-- ③ 默认关（11-07 起；原来默认开）；/gi 屏蔽升级 开|关；设置页「公会」栏有开关；本次登录第一次屏蔽时提示一句怎么关
-- ⛔ 只用 ChatFrame_AddMessageEventFilter，绝不替换聊天框方法（0.5.5 GuildChatLevel 换 AddMessage 污染暴雪聊天的教训）；
--    消息 / 说话人是保密值就原样放行；全部 pcall
local _, ns = ...; ns = _G.GearInsightForever or ns

local LM = {}
ns.LevelMute = LM

local EVENTS = {
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL",
}

local hidden, lastLine, lastHit, told = 0, nil, false, false

function LM.Enabled() return ns.db.lvlMute == true end   -- 11-07 用户「默认不打开这个屏蔽哈」：默认关，自己去设置页打开
function LM.Hidden() return hidden end

-- ⛔ Lua 模式按字节：「了?」只让「了」的最后一个字节可选，中文可选字一律拆成两条写
-- 一眼就是播报的句式（本身带「从 X 级到 Y 级」或英文固定说法）
local STRONG = {
    "从%s*%d+%s*级%s*升到%s*%d+%s*级", "从%s*%d+%s*级%s*升到了%s*%d+%s*级", "从%s*%d+%s*级%s*升至%s*%d+%s*级", "从%s*%d+%s*级%s*到%s*%d+%s*级",
    "^%W*ding%f[%W]", "%f[%w]dinged%f[%W]", "reached level %d+", "leveled up to %d+", "levelled up to %d+",
    "is now level %d+", "hit level %d+", "from level %d+ to %d+",
}
-- 普通人也会说的「升到 20 级」：得再带一个插件信号才算
local LEVEL = {
    "升到%s*%d+%s*级", "升到了%s*%d+%s*级", "升至%s*%d+%s*级", "升级到%s*%d+%s*级", "达到%s*%d+%s*级", "达到了%s*%d+%s*级", "到达%s*%d+%s*级",
    "等级提升", "满级了", "%f[%w]level up%f[%W]", "%f[%w]level %d+",
}
local SIGNAL = {
    "^%s*%[", "^%s*【", "^%s*<", "^%s*{",                              -- 插件前缀 [XX插件] 【XX】 <XX>
    "%d+%s*小时", "%d+%s*分", "%d+%s*秒", "用时", "耗时", "游戏时长", "played", "%d+%s*min", "%d+%s*sec", "%d+h",
    "恭喜", "ding", "gz", "grats",
}

local function anyMatch(s, list)
    for i = 1, #list do if s:find(list[i]) then return true end end
    return false
end

-- 11-07 用户截图「[GuildInsight插件]热烈欢迎新会 XX 加入！第348位兄弟…」「这个也加上屏蔽功能覆盖的范围」：
--   各家插件的入会欢迎播报也算：开头是插件前缀（[XX插件] / 【XX】）+ 欢迎 / 加入 / 入会 / 第 N 位 之类。
--   ⛔ 必须带插件前缀：玩家自己打「欢迎新人」不吞
local PREFIX = { "^%s*%[[^%]]-插件%]", "^%s*%[[^%]]-addon%]", "^%s*【.-】", "^%s*%[gearinsight%]", "^%s*%[guildinsight%]" }
local WELCOME = { "欢迎", "加入", "入会", "第%s*%d+%s*位", "welcome", "joined the guild", "has joined" }
function LM.IsWelcome(s)
    return anyMatch(s, PREFIX) and anyMatch(s, WELCOME)
end

function LM.IsShout(msg)
    if type(msg) ~= "string" or msg == "" or #msg > 400 then return false end
    local s = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):lower()
    if anyMatch(s, STRONG) then return true end
    if LM.IsWelcome(s) or LM.IsWelcome((msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) then return true end   -- 中文按原串再比一次（有的环境 lower() 会动多字节）
    return anyMatch(s, LEVEL) and anyMatch(s, SIGNAL)
end

local function isMe(author)
    if type(author) ~= "string" or author == "" then return false end
    local me = UnitName and UnitName("player")
    if not me or ns.Secret(me) then return false end
    local base = author:match("^([^%-]+)") or author
    return author == me or base == me or base:match("^(%S+)") == me   -- 11-07 无限「名 姓」：发送人带姓，UnitName 只给名
end

local function filter(_, _, msg, author, ...)
    if not LM.Enabled() then return false end
    if ns.Secret(msg) or ns.Secret(author) then return false end
    local lineID = select(9, ...)   -- arg11：同一条消息每个聊天框各调一次，按 lineID 只算一次
    if lineID ~= nil and ns.Secret(lineID) then lineID = nil end
    if lineID ~= nil and lineID == lastLine then return lastHit end
    local ok, hit = pcall(function() return (not isMe(author)) and LM.IsShout(msg) end)
    hit = ok and hit or false
    lastLine, lastHit = lineID, hit
    if hit then
        hidden = hidden + 1
        if not told then
            told = true
            ns.Print(ns.L("已屏蔽别人的升级播报（本次登录只提示这一次）。想看：/gi 屏蔽升级 关",
                "Hiding other players' level-up shouts (shown once per login). To see them: /gi lvlmute off"))
        end
    end
    return hit
end

LM._filter, LM._events = filter, EVENTS   -- 离线测试用
if ChatFrame_AddMessageEventFilter then
    for _, e in ipairs(EVENTS) do pcall(ChatFrame_AddMessageEventFilter, e, filter) end
end

function LM.SetEnabled(v)
    ns.db.lvlMute = v and true or false
    ns.Print(ns.L("屏蔽别人的升级播报：", "Hide others' level-up shouts: ") .. (v and ns.L("开", "on") or ns.L("关", "off"))
        .. ns.L("（/gi 屏蔽升级 开 | 关）", " (/gi lvlmute on|off)"))
end

local ARG = { ["开"] = true, on = true, ["关"] = false, off = false }
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash["屏蔽升级"] = function(rest)
    rest = (rest or ""):gsub("%s+", "")
    if ARG[rest] ~= nil then LM.SetEnabled(ARG[rest]); return end
    ns.Print(ns.L("屏蔽别人的升级播报现在：", "Hide others' level-up shouts: ") .. (LM.Enabled() and ns.L("开", "on") or ns.L("关", "off"))
        .. string.format(ns.L("，本次登录已屏蔽 %d 条。/gi 屏蔽升级 开 | 关", ", %d hidden this session. /gi lvlmute on|off"), hidden))
end
ns.ExtraSlash.lvlmute = ns.ExtraSlash["屏蔽升级"]
