-- 副本组队 · 登录就要的那一小块（11-13 界面重构第 5 期从 DungeonChat.lua 拆出来，代码原样搬）。
--   在登录加载的 GearInsight_Forever_Group 里；副本组队的面板 / 读频道 / 来密我的人 / 自动反问在按需加载的
--   GearInsight_Forever_GroupUI/DungeonChat.lua（打开「副本组队」子页签才加载）。
--   这里只留：
--     · ns.DungeonChat 表本身 + 存档 DC.DB + 发话前缀 [GI组队助手]（DC.Tagged）+ 名字 / 人数小工具 —— 法师吃喝（GearInsight_Forever_GroupMage）也要用
--     · 满员自动通知（rec.fullSay / rec.fullTell，默认关）：开着才注册 GROUP_ROSTER_UPDATE
--     · 副本里跟法师开交易自动要吃喝（TRADE_SHOW）：法师吃喝加载了交给它（MW.OnTradeShow）；没装法师吃喝时走 1.0.0 老逻辑（rec.mageAsk）
--       开着要用才注册 TRADE_SHOW（DC.SyncCore）
--     · 「要水 / 要面包」私聊识别（原 MageWater.ParseAsk）：副本组队「来密我的人」要用它跳过要水的私聊，法师吃喝没加载时也得在
local _, ns = ...; ns = _G.GearInsightForever or ns
local L = function(cn, en) return ns.L(cn, en) end

local DC = { posts = {}, applied = {}, lastShout = -1e9, view = "seek" }
ns.DungeonChat = DC
-- 11-13 用户截图（招人页刚喊完、列表空着）「记录在这里不要老清除」：「来密我的人」存进存档 ns.db.dchat.replies，
--   DC.replies 读写都落到那张表（下面 DC.Replies）；别处照旧写 DC.replies / DC.replies = {}，不用改
setmetatable(DC, {
    __index = function(_, k) if k == "replies" then return DC.Replies() end end,
    __newindex = function(t, k, v)
        if k ~= "replies" then rawset(t, k, v); return end
        if ns.db then DC.DB().replies = v else rawset(t, "_repTmp", v) end
    end,
})
DC.TTL = 600            -- 组队消息留多久（秒）
DC.MAX_POSTS = 60
DC.APPLY_WIN = 600      -- 申请后多久内自动接受这个队长的邀请
DC.SHOUT_CD = 30        -- 招人喊话冷却
DC.REPLY_WIN = 900      -- 喊完多久内密我的算「来密我的人」（只管「记不记进来」；记进来之后一直留着）
DC.REC_MAX = 50         -- 「来密我的人」最多留几个人（超出丢最旧的）
DC.REC_AGE = 86400      -- 「来密我的人」最后一次密我超过 24 小时的丢掉（防存档无限涨）

local function now() return (GetTime and GetTime()) or 0 end
DC._now = now
local function clean(v)
    if v == nil or (ns.Secret and ns.Secret(v)) then return nil end
    return v
end
DC._clean = clean
local function short(n) return type(n) == "string" and (n:match("^[^-]+") or n) or nil end
DC.Short = short
-- 只把 A-Z 变小写：string.lower 跟着 C 运行库的区域设置走，碰到中文字节可能改坏（测试环境里就坏了），只动 ASCII 最稳
local function lowerAscii(s) return (s:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end)) end
DC.LowerAscii = lowerAscii


function DC.DB()
    ns.db.dchat = ns.db.dchat or {}
    local d = ns.db.dchat
    d.rec = d.rec or {}
    d.rec.roles = d.rec.roles or { TANK = true, HEALER = true }
    d.rec.chans = d.rec.chans or {}
    d.replies = d.replies or {}
    return d
end

-- ---------- 插件标识前缀 ----------
-- 11-12 用户截图（招人面板）「这个默认加上[GI插件]都，包括回复」→ 随后改名「[GI组队助手]」：
--   副本组队里插件发出去的话（招人喊话 / 申请私聊 / 自动反问 / 复制到聊天群）开头都带这个前缀；默认开，招人页「带标识」可关（rec.noTag = true）
--   ⛔ 前缀只在这里定义一处；聊天一条最多 255 字节 → 超长先裁正文、不裁前缀
DC.TAG = "[GI组队助手]"
DC.MAX_BYTES = 255
function DC.TagOn() return DC.DB().rec.noTag ~= true end
-- 按 UTF-8 字符边界裁到 n 字节以内（别把中文切成半个字）
local function cutBytes(s, n)
    if #s <= n then return s end
    if n <= 0 then return "" end
    local i = n
    while i > 0 do
        local b = s:byte(i + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end   -- 下一个字节不是续字节 = 这里是字符边界
        i = i - 1
    end
    return s:sub(1, i)
end
DC.CutBytes = cutBytes
-- 去掉文字里的前缀（别人的插件发来的 / 编辑框里带着的）
function DC.StripTag(s)
    if type(s) ~= "string" then return s end
    local t = DC.TAG
    local a, b = s:find(t, 1, true)
    while a do
        s = s:sub(1, a - 1) .. s:sub(b + 1)
        a, b = s:find(t, 1, true)
    end
    return (s:gsub("^%s+", ""))
end
function DC.HasTag(s) return type(s) == "string" and s:find(DC.TAG, 1, true) ~= nil end
-- 最终要发的文字：前缀 + 正文；limit = 字节上限（发聊天传 DC.MAX_BYTES；复制框不限传 nil）
function DC.Tagged(text, limit)
    text = DC.StripTag(tostring(text or ""))
    local pre = DC.TagOn() and DC.TAG or ""
    if limit then text = cutBytes(text, limit - #pre) end
    return pre .. text
end

local function me() return clean(UnitName and UnitName("player")) end
-- 11-10 用户「复制的文案带上姓啊」：《无限》角色名是「名 姓」，UnitName 只回「名」→ GetUnitName(unit, true) 回全名（去掉 -服务器）
local function fullName(u)
    if GetUnitName then
        local ok, n = pcall(GetUnitName, u, true)
        n = ok and short(clean(n))
        if n and n ~= "" then return n end
    end
    return clean(UnitName and UnitName(u))
end
DC.FullName = fullName
local function isMe(author)
    local s = short(author)
    return s ~= nil and (s == me() or s == fullName("player"))
end
DC._me = me
DC._isMe = isMe

DC.CNT_MIN = 3
-- 11-11 用户截图「怎么不喊4=1」：GetNumGroupMembers 读不到（加密值 / nil）时退回 1 → 不带人数；
--   再数一遍 party1-4 谁在，两个取大的
function DC.PartyCount()
    local n = 1
    if GetNumGroupMembers then
        local ok, v = pcall(GetNumGroupMembers)
        v = ok and tonumber(clean(v)) or nil
        if v and v > n then n = v end
    end
    if UnitExists then
        local c = 1
        for i = 1, 4 do
            local ok, e = pcall(UnitExists, "party" .. i)
            if ok and clean(e) then c = c + 1 end
        end
        if c > n then n = c end
    end
    return n
end
-- 11-11 用户截图「会发：…」「这个可编辑可保存」：每个副本可以存一句自己的话术（rec.custom[副本名]）；
--   存的时候把当时的人数「4=1」换成 {人数}，之后照样跟着队伍人数变；「默认」按钮清掉回插件生成的

-- 11-12 用户「组满人自动在队伍里发：人员已满，立刻发车；分别私聊一下另外四个人也。这俩都是可选，默认关闭」
--   rec.fullSay = 队伍频道说一句；rec.fullTell = 逐个私聊四个队友。只在「从不满变成满 5 人」那一下发一次，
--   掉到 5 人以下再满才会再发；刚上线 / 重载时本来就满的不发；自己不是队长不发（免得五个人都开了一起刷）
DC.FULL_N = 5
function DC.FullText() return L("人员已满，立刻发车", "Group is full - heading out now") end
function DC.CheckFull()
    local n = DC.PartyCount()
    local prev = DC.fullPrev
    DC.fullPrev = n
    if n < DC.FULL_N then DC.fullDone = nil; return false end
    if prev == nil or prev >= DC.FULL_N or DC.fullDone then return false end
    local r = DC.DB().rec
    if not (r.fullSay or r.fullTell) then return false end
    if IsInRaid then local ok, v = pcall(IsInRaid); if ok and clean(v) then return false end end
    if UnitIsGroupLeader then local ok, v = pcall(UnitIsGroupLeader, "player"); if ok and not clean(v) then return false end end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    DC.fullDone = true
    local text = DC.Tagged(DC.FullText(), DC.MAX_BYTES)
    if r.fullSay then pcall(send, text, "PARTY") end
    if r.fullTell then
        for i = 1, 4 do
            local ok, e = pcall(UnitExists or function() end, "party" .. i)
            local who = ok and clean(e) and fullName("party" .. i) or nil
            if who and who ~= "" then pcall(send, text, "WHISPER", nil, who) end
        end
    end
    return true
end

-- 11-12 用户「副本内检测交易法师，自动密语功能」「要吃喝」：在副本里跟法师一开交易窗，自动密他一句要吃喝，
--   省得每次手打。rec.mageAsk 开关，默认关；同一个法师 MAGE_CD 秒内只密一次；自己是法师不发。
--   有蓝的职业要「水和面包」，没蓝的（战士 / 盗贼）只要「面包」。交易对象的单位名是 "NPC"。
DC.MAGE_CD = 180
function DC.MageAskText()
    local mana = true
    if UnitPowerType then
        local ok, t = pcall(UnitPowerType, "player")
        t = ok and clean(t)
        if t ~= nil and t ~= 0 then mana = false end
    end
    if mana then return L("法师老板，求水和面包，谢谢~", "Could I get some water and food please? Thanks!") end
    return L("法师老板，求面包，谢谢~", "Could I get some food please? Thanks!")
end
function DC.OnTradeShow()
    -- 11-12 自动要水 / 自动发水（MageWater.lua，HOLD）：在就交给它（按背包缺多少、按等级要；法师那边出「一键放入」）；不在 = 下面 1.0.0 老逻辑
    if ns.MageWater and ns.MageWater.OnTradeShow then return ns.MageWater.OnTradeShow() end
    if not DC.DB().rec.mageAsk then return false end
    if not IsInInstance then return false end
    local okI, inInst, kind = pcall(IsInInstance)
    if not (okI and clean(inInst)) then return false end
    kind = clean(kind)
    if kind ~= nil and kind ~= "party" and kind ~= "raid" then return false end
    if not UnitClass then return false end
    local okC, _, cls = pcall(UnitClass, "NPC")
    if not (okC and clean(cls) == "MAGE") then return false end
    local okM, _, mine = pcall(UnitClass, "player")
    if okM and clean(mine) == "MAGE" then return false end
    local who = fullName("NPC")
    if not who or who == "" then return false end
    DC.mageAsked = DC.mageAsked or {}
    local t = now()
    if DC.mageAsked[who] and t - DC.mageAsked[who] < DC.MAGE_CD then return false end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    DC.mageAsked[who] = t
    pcall(send, DC.Tagged(DC.MageAskText(), DC.MAX_BYTES), "WHISPER", nil, who)
    return true
end

-- ---------- 认「要吃喝」的话（11-13 第 5 期从 MageWater.lua 搬来，原样；MW.ParseAsk / MW.SkipWhisper 指向这里）----------
local NOT_WATER = { "水平", "水晶", "下水道", "水下", "水元素", "水果", "水母", "水手", "水桶", "水泥", "水怪", "水域", "水路", "口水", "灌水", "风水", "水友", "薪水", "水货", "水深", "水草" }
local WATER_W = { "水", "喝的", "喝点", "饮料" }
local FOOD_W = { "面包", "吃的", "吃点", "食物", "粮", "馒头", "饼" }
local BOTH_W = { "吃喝", "吃的喝的", "水和面包", "水跟面包", "水面包" }
local INTENT_W = { "求", "要", "给", "来", "麻烦", "能", "有", "发", "整", "搞", "弄", "谢", "法师", "老板", "大佬", "拜托", "一组", "点", "些", "plz", "pls", "please", "need", "?", "？" }
local NEG_W = { "不用", "不要", "不需要", "够了", "有了", "我有", "不缺", "别给", "不渴", "no need" }
-- 英文按整词认（⛔ 用 a-z 字节范围，别用 %a：跟区域设置走，中文字节可能被当成字母）
local EN_WATER = { "%f[a-z]water%f[^a-z]", "%f[a-z]drinks?%f[^a-z]" }
local EN_FOOD = { "%f[a-z]food%f[^a-z]", "%f[a-z]bread%f[^a-z]" }
local function hasAny(s, words)
    for _, w in ipairs(words) do if s:find(w, 1, true) then return true end end
    return false
end
local function hasPat(s, pats)
    for _, p in ipairs(pats) do if s:find(p) then return true end end
    return false
end
local function stripText(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    return s
end
function DC.MageParseAsk(msg)
    if type(msg) ~= "string" or msg == "" then return false, false end
    local tagged = DC.HasTag(msg)
    local s = DC.LowerAscii(stripText(DC.StripTag(msg)))
    -- 法师那边插件回的话（「好的，来交易就给你」「吃喝放好了」）不是要
    if tagged and (s:find("交易", 1, true) or s:find("trade", 1, true) or s:find("稍等", 1, true)) then return false, false end
    if hasAny(s, NEG_W) then return false, false end
    local w = s
    for _, x in ipairs(NOT_WATER) do w = w:gsub(x, "") end
    local both = hasAny(s, BOTH_W)
    local water = both or hasAny(w, WATER_W) or hasPat(s, EN_WATER)
    local food = both or hasAny(s, FOOD_W) or hasPat(s, EN_FOOD)
    if not (water or food) then return false, false end
    -- 很短的一句（「水」「求水」「面包」）直接算；长句要有「求 / 要 / 给 / 麻烦 / ?」这类词；对方插件发来的「法师老板，求…」直接算
    if not (tagged or #s <= 15 or hasAny(s, INTENT_W)) then return false, false end
    return water, food
end
-- 组队招人那边「来密我的人」别把要水的私聊当报名（DungeonChat.OnWhisper 调；MageWater.lua 里 MW.SkipWhisper 是同一个函数）
function DC.MageSkipWhisper(msg)
    local w, f = DC.MageParseAsk(msg)
    if w or f then return true end
    return DC.HasTag(msg) and type(msg) == "string" and (msg:find("交易", 1, true) or msg:find("稍等", 1, true)) and true or false
end

-- ---------- 来密我的人（11-13 从 DungeonChat.lua 搬来：面板没加载也要收；/reload、换区、重登都还在）----------
--   判定不变：喊完 REPLY_WIN（15 分钟）内私聊我的才记进来（要水 / 法师回话除外）；记进来之后一直留着，
--   只有玩家点「清空」/ 行尾 ×、或者超出 REC_MAX 人 / 超过 REC_AGE 没再密才丢（最旧的先丢）。
--   每条：author / short / text / hist（最近 6 句）/ roles / lv / cls / clsName / asked / gi / at（最后一次密我，time() 秒）/ firstAt / t（GetTime，本次登录内用）
--   喊话时刻另存 ns.db.dchat.lastShoutAt（time() 秒）：喊完马上 /reload，剩下的窗口照样收
DC.ROLE_WORDS = {
    ["TANK"] = { "坦克", "坦", "mt", "tank", "%f[a-z]t%f[^a-z]", "%f[a-z]tn%f[^a-z]" },
    ["HEALER"] = { "治疗", "奶", "heal", "%f[a-z]n%f[^a-z]", "%f[a-z]tn%f[^a-z]", "牧师", "萨满" },
    ["DAMAGER"] = { "输出", "dps", "%f[a-z]dd%f[^a-z]", "法师", "术士", "猎人", "盗贼", "近战", "远程",
        "%f[a-z]ss%f[^a-z]", "%f[a-z]fs%f[^a-z]", "%f[a-z]lr%f[^a-z]", "%f[a-z]dz%f[^a-z]" },
}
function DC.StripCodes(msg)
    msg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "")
    return msg
end
function DC.HasWord(lower, words)
    for _, w in ipairs(words) do
        if w:find("%%f") then
            if lower:find(w) then return true end
        elseif lower:find(w, 1, true) then return true end
    end
    return false
end
-- 11-10 用户截图「人的等级职业列出来」：职业从聊天事件带的 GUID 读（GetPlayerInfoByGUID，陌生人也有）
function DC.WhoOf(guid)
    guid = clean(guid)
    if not guid or not GetPlayerInfoByGUID then return nil end
    local ok, locCls, cls = pcall(GetPlayerInfoByGUID, guid)
    if not ok then return nil end
    return clean(cls), clean(locCls)
end
function DC.TextLevel(text)
    if type(text) ~= "string" then return nil end
    -- 11-12 喊话改成「M我带职责等级」后常见回「24奶」「28 T」「lv25 dps」→ 开头的数字后面跟着字就算（光回「1」「111」= 我来，不是等级）
    local x = text:match("^%s*(%d%d?)%s*[^%d%s]") or text:match("(%d%d?)%s*级") or text:match("[Ll][Vv]%s*(%d%d?)")
        or text:match("[^%d%s]%s*(%d%d?)%s*$")   -- 「求组SS 25」：前面有字、结尾的数字
    x = tonumber(x)
    if x and x >= 1 and x <= 60 then return x end
end

local function epoch() return (time and time()) or (os and os.time and os.time()) or 0 end
DC._epoch = epoch
function DC.Replies()
    if not ns.db then
        local t = rawget(DC, "_repTmp")
        if not t then t = {}; rawset(DC, "_repTmp", t) end
        return t
    end
    return DC.DB().replies
end
-- 超出上限丢最旧的：最后一次密我超过 REC_AGE 的、排在 REC_MAX 之后的（列表最新在前）
function DC.PruneReplies()
    local list, cut = DC.Replies(), epoch() - DC.REC_AGE
    for i = #list, 1, -1 do
        local at = type(list[i]) == "table" and tonumber(list[i].at)
        if type(list[i]) ~= "table" or (at and at < cut) then table.remove(list, i) end
    end
    while #list > DC.REC_MAX do table.remove(list) end
    return list
end
function DC.ClearReplies()
    local list = DC.Replies()
    for i = #list, 1, -1 do list[i] = nil end
    DC.dirty = true
end
function DC.RemoveReply(s)
    local list, n = DC.Replies(), 0
    for i = #list, 1, -1 do if list[i].short == s then table.remove(list, i); n = n + 1 end end
    DC.dirty = true
    return n > 0
end
-- 喊话（DC.Shout 发出去了）：记时刻；⛔ 不再清空「来密我的人」
function DC.MarkShout()
    DC.lastShout = now()
    rawset(DC, "_shoutRestored", true)
    if ns.db then DC.DB().lastShoutAt = epoch() end
end
-- 刚登录 / 重载：存档里的喊话时刻还在窗口里 → 换算回本次登录的 GetTime（只在本次登录还没喊过时做一次）
function DC.RestoreShout()
    if rawget(DC, "_shoutRestored") or not ns.db then return end
    rawset(DC, "_shoutRestored", true)
    local at = tonumber(DC.DB().lastShoutAt)
    if not at or DC.lastShout > -1e8 then return end
    local age = epoch() - at
    if age >= 0 and age <= DC.REPLY_WIN then DC.lastShout = now() - age end
end
function DC.InReplyWin()
    DC.RestoreShout()
    return now() - DC.lastShout <= DC.REPLY_WIN
end

function DC.OnWhisper(msg, author, guid)
    author, msg = clean(author), clean(msg)
    if not author or not msg or not DC.InReplyWin() then return false end
    -- 11-12 要水 / 法师回话的私聊不是来报名的，别进「来密我的人」、别自动反问
    if DC.MageSkipWhisper(msg) then return false end
    local list = DC.Replies()
    local s = short(author)
    local prev
    for i = #list, 1, -1 do if list[i].short == s then prev = table.remove(list, i) end end
    -- 对方也装了插件：前缀去掉再认等级 / 职责（「[GI组队助手]20 LR求组」开头不是数字就认不出 20），记 gi 标记
    local raw = DC.StripCodes(msg)
    local t = epoch()
    local p = { author = author, short = s, text = DC.StripTag(raw), t = now(), at = t, firstAt = t, roles = {}, reply = true, gi = DC.HasTag(raw) or nil }
    p.cls, p.clsName = DC.WhoOf(guid)
    local lower = lowerAscii(p.text)
    for role, words in pairs(DC.ROLE_WORDS) do if DC.HasWord(lower, words) then p.roles[role] = true end end
    -- 11-12 用户「如果没有等级和职责，直接自动反问」「然后汇总到表格」：同一个人后面补的（先回「N」再回「25」）合进同一行
    if prev then
        for r in pairs(prev.roles or {}) do p.roles[r] = true end
        -- 问过他之后光回一个数（「25」）就是等级；没问过的「1」「11」还是当「我来」
        local bare = prev.asked and tonumber(p.text:match("^%s*(%d%d?)%s*$"))
        if bare and (bare < 1 or bare > 60) then bare = nil end
        p.lv = rawget(p, "lv") or DC.TextLevel(p.text) or bare or rawget(prev, "lv")
        p.cls, p.clsName = p.cls or prev.cls, p.clsName or prev.clsName
        p.asked, p.first = prev.asked, prev.first or prev.t
        p.firstAt = prev.firstAt or prev.at or t
        p.hist = prev.hist or { prev.text }
        p.hist[#p.hist + 1] = p.text
        while #p.hist > 6 do table.remove(p.hist, 1) end
    end
    table.insert(list, 1, p)
    DC.PruneReplies()
    DC.dirty = true
    if DC.MaybeAsk then DC.MaybeAsk(p) end   -- 自动反问在面板那边（DungeonChat.lua）；面板没加载就只记下来
    return true
end

-- ---------- 事件（登录就在的这一半；11-13 第 5 期：用得上才注册）----------
--   TRADE_SHOW：法师吃喝加载了 → 问它要不要（MW.WantTrade：道谢 / 自动要 / 一键放入有一个开着）；没加载 → 1.0.0 老逻辑开关 rec.mageAsk
--   GROUP_ROSTER_UPDATE：满员喊话 / 满员私聊开着才注册（面板加载后 DungeonChat.lua 自己的事件框也会跟人数，那时这边管满员、那边只管重画）
local cev = CreateFrame("Frame")
DC.coreEv = cev
local function wantTrade()
    local MW = ns.MageWater
    if MW and MW.WantTrade then return MW.WantTrade() and true or false end
    return DC.DB().rec.mageAsk and true or false
end
function DC.SyncCore()
    if not ns.db then return end
    local r = DC.DB().rec
    local trade, full = wantTrade(), (r.fullSay or r.fullTell) and true or false
    if trade then pcall(cev.RegisterEvent, cev, "TRADE_SHOW") else pcall(cev.UnregisterEvent, cev, "TRADE_SHOW") end
    if full then pcall(cev.RegisterEvent, cev, "GROUP_ROSTER_UPDATE") else pcall(cev.UnregisterEvent, cev, "GROUP_ROSTER_UPDATE") end
    DC.SyncWhisper()
    DC.coreTrade, DC.coreFull = trade, full
    return trade, full
end
-- 11-13 CHAT_MSG_WHISPER：面板（DungeonChat.lua）没加载、且还在喊话窗口里（喊完 /reload / 重登）才由这里收；
--   面板加载了它自己的事件框收（别记两遍）；窗口过了，下一条私聊进来时顺手注销
function DC.SyncWhisper()
    local want = rawget(DC, "ev") == nil and ns.db ~= nil and DC.InReplyWin()
    if want then pcall(cev.RegisterEvent, cev, "CHAT_MSG_WHISPER") else pcall(cev.UnregisterEvent, cev, "CHAT_MSG_WHISPER") end
    DC.coreWhisper = want and true or false
    return DC.coreWhisper
end
cev:SetScript("OnEvent", function(_, e, a1, a2, ...)
    if e == "TRADE_SHOW" then pcall(DC.OnTradeShow)
    elseif e == "GROUP_ROSTER_UPDATE" then pcall(DC.CheckFull)
    elseif e == "CHAT_MSG_WHISPER" then
        if rawget(DC, "ev") == nil then pcall(DC.OnWhisper, a1, a2, select(10, ...)) end   -- a12 = GUID
        if rawget(DC, "ev") ~= nil or not DC.InReplyWin() then DC.SyncWhisper() end
    end
end)
DC._coreEvent = cev:GetScript("OnEvent")   -- 测试用
