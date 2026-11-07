-- 公会频道显示等级（10-18 用户截图「增加个能力，设置里可以开，默认打开，就是工会频道显示当前等级」）
--   公会 / 官员频道名字前加「[26]」：[公会] [26][玛尔 卖啤]: …。等级取游戏自带公会名单（含没装插件的人），自己的用 UnitLevel。
--   ⛔ 不改 author 参数、不钩 GetColoredName（会弄坏名字链接 / 右键菜单），只在聊天框显示前往整行里插字。
--   名单在 GUILD_ROSTER_UPDATE 时只记「脏了」，有人说话时才重建（最多 5 秒一次）；没人说话 = 零开销。
--   开关 ns.db.ui.guildChatLevel（nil = 默认开），设置页「公会」一栏。
local _, ns = ...; ns = _G.GearInsightForever or ns  -- 10-19 用户「拿到主插件，不要放子插件了」：搬回主插件，登录就跑（不用先点公会页签）；这行在主插件里也成立
local L = ns.L

local GL = {}
ns.GuildChatLevel = GL

-- 11-06 用户截图「这里可以加上地区吗」：名单里本来就有每人所在地区（GetGuildRosterInfo 第 6 个返回值）→ 「[24·贫瘠之地]」
--   地区会变：显示地区时每条消息顺手要一次名单（ask 自己 60 秒限流），名单事件回来 5 秒内重建 → 最多落后一两分钟
--   开关 ns.db.ui.guildChatZone（nil = 默认开），设置页「公会」栏，挂在等级开关下面（等级关了地区也不出）
local levels, zones, dirty, builtAt, askedAt = {}, {}, true, -999, -999
local function now() return GetTime and GetTime() or 0 end
local function secret(v) return ns.Secret and ns.Secret(v) end
local function short(n) return n:match("^([^%-]+)") or n end

function GL.Enabled()
    return not (ns.db and ns.db.ui and ns.db.ui.guildChatLevel == false)
end

function GL.ZoneEnabled()
    return not (ns.db and ns.db.ui and ns.db.ui.guildChatZone == false)
end

function GL.SetZoneEnabled(on)
    if not ns.db then return end
    ns.db.ui = ns.db.ui or {}
    ns.db.ui.guildChatZone = on and true or false
end

function GL.SetEnabled(on)
    if not ns.db then return end
    ns.db.ui = ns.db.ui or {}
    ns.db.ui.guildChatLevel = on and true or false
end

-- 向服务器要一次公会名单（服务器自己也限流；这里 60 秒内不重复要）
local function ask()
    if not (IsInGuild and IsInGuild()) or now() - askedAt < 60 then return end
    askedAt = now()
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
end
GL.Ask = ask

function GL.Rebuild(force)
    if not force and (not dirty or now() - builtAt < 5) then return end
    dirty, builtAt = false, now()
    local t, z = {}, {}
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        local ok, total = pcall(GetNumGuildMembers)
        total = ok and tonumber(total) or 0
        for i = 1, total do
            local ok2, name, _, _, level, _, zone = pcall(GetGuildRosterInfo, i)
            level = ok2 and tonumber(level) or nil
            if type(name) == "string" and level and not secret(name) and not secret(level) then
                t[short(name)] = level
                if type(zone) == "string" and zone ~= "" and not secret(zone) then z[short(name)] = zone end
            end
        end
    end
    levels, zones = t, z
end

local function isMe(author)
    local me = UnitName and UnitName("player")
    return me and not secret(me) and short(author) == me
end

-- 发言人 → 所在地区；查不到 nil（自己用当前地区）
function GL.Zone(author)
    if type(author) ~= "string" or secret(author) or author == "" then return nil end
    if isMe(author) then
        local z = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText())
        if type(z) == "string" and z ~= "" and not secret(z) then return z end
        return nil
    end
    GL.Rebuild()
    ask()   -- 地区会变：60 秒内最多要一次
    return zones[short(author)]
end

-- 发言人（可能带「-服务器」）→ 等级；查不到 nil
function GL.Level(author)
    if type(author) ~= "string" or secret(author) or author == "" then return nil end
    local s = short(author)
    local me = UnitName and UnitName("player")
    if me and not secret(me) and s == me then
        local lv = UnitLevel and UnitLevel("player")
        if type(lv) == "number" and not secret(lv) and lv > 0 then return lv end
    end
    GL.Rebuild()
    local lv = levels[s]
    if not lv then ask() end   -- 新人刚进会 / 名单还没拿到：要一次，下一条消息就有了
    return lv
end

-- 10-18 第二版（用户截图「[公会][26][玛尔 卖啤]: …」）：等级放在名字前面，不放正文里。
--   拼好的整行在聊天框 AddMessage 时才看得到名字链接 → 换掉每个聊天框的 AddMessage，在 |Hplayer: 链接前插「[26]」。
--   只认公会 / 官员频道那一行（|Hchannel:GUILD / OFFICER）；整行是保密值（12.x 副本里）就原样放过，名字链接本身不改
function GL.Tag(lv, zone)
    if type(zone) == "string" and zone ~= "" then return "|cffc8b27a[" .. lv .. "·" .. zone .. "]|r" end
    return "|cffc8b27a[" .. lv .. "]|r"
end

function GL.Decorate(text)
    if type(text) ~= "string" or secret(text) or not GL.Enabled() then return text end
    if not (text:find("|Hchannel:GUILD", 1, true) or text:find("|Hchannel:OFFICER", 1, true)
        or text:find("|Hchannel:Guild", 1, true) or text:find("|Hchannel:Officer", 1, true)) then return text end
    local s, name = text:match("()|Hplayer:([^:|]+)")
    if not s then return text end
    local lv = GL.Level(name)
    if not lv then return text end
    return text:sub(1, s - 1) .. GL.Tag(lv) .. text:sub(s)
end

-- ⛔⛔ 10-25 停用（0.5.5）：原来在这里把每个聊天框的 AddMessage 换成插件函数（cf.AddMessage = function …）。
--   用户截图 BugGrabber「attempted to iterate a table that cannot be accessed while tainted
--   (execution tainted by 'GearInsight_Forever')」Count 1004、栈为空：无限客户端是 12.x 引擎，暴雪聊天框处理每一条消息
--   （所有频道 / 系统 / 拾取 / 经验）都会调 self:AddMessage → 走进插件函数 → 这条执行链从此被污染 → 暴雪随后遍历
--   只许安全代码访问的表时炸。插件里只有这一处替换暴雪框体方法；gi_forever_forbidden_check 早就把 _G["ChatFrame"..i] 标红，
--   但发版脚本没跑这道闸。
--   现在：不碰任何聊天框，公会频道等级显示暂停（设置页不再出这个开关）。Decorate / Level 留着给以后的安全实现。
--   ⛔ 别再 cf.AddMessage = … / hooksecurefunc 以外的方式改暴雪聊天框；ChatFrame_AddMessageEventFilter 在 12.x 是否安全
--   没有真机证据，要恢复这个功能先进 HOLD 真机测。
function GL.HookFrame() end   -- 兼容旧调用：什么也不做

-- ✅ 11-05 恢复（用户截图公会频道：「增加功能，聊天框前面加等级数字」）：只走官方的 ChatFrame_AddMessageEventFilter
--   （LevelMute.lua 同一个口子，0.5.6 起随包、真机没报污染），⛔ 仍然不碰任何聊天框方法。
--   过滤器只能改「正文」，改说话人参数会弄坏名字链接 / 右键 / 密语 → 等级放在正文最前面：[公会] [枫叶 洞察]: [26] 不太对
--   正文 / 说话人是保密值（12.x 副本里）原样放行；查不到等级原样放行；全部 pcall。
--   ⛔ 要排在 LevelMute 后面注册（toc 里本文件在 LevelMute.lua 之后）：它按正文开头认播报，先加了等级它就认不出了
GL.Paused = false
local function filter(_, _, msg, author, ...)
    if not GL.Enabled() or type(msg) ~= "string" or secret(msg) or secret(author) then return false end
    local ok, lv = pcall(GL.Level, author)
    if not ok or not lv then return false end
    local zone
    if GL.ZoneEnabled() then
        local okz, z = pcall(GL.Zone, author)
        if okz then zone = z end
    end
    return false, GL.Tag(lv, zone) .. " " .. msg, author, ...
end
GL._filter = filter   -- 离线测试用
if ChatFrame_AddMessageEventFilter then
    for _, e in ipairs({ "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER" }) do pcall(ChatFrame_AddMessageEventFilter, e, filter) end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "PLAYER_ENTERING_WORLD" }) do
    local valid = not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e)
    if valid then pcall(ev.RegisterEvent, ev, e) end
end
ev:SetScript("OnEvent", function(_, e)
    dirty = true
    if e == "PLAYER_ENTERING_WORLD" and not GL.Paused then ask() end
end)

-- 已登录（晚加载）才补跑一次「进入游戏」那段初始化；主插件正常加载时这里不跑，等事件
if IsLoggedIn and IsLoggedIn() then pcall(ev:GetScript("OnEvent"), ev, "PLAYER_ENTERING_WORLD") end

-- 11-06 用户直播中「招人加上通报当前公会统计，在线人数，实时的感觉」→「用第 1 种，公会频道定时通报」：
--   开了以后每 N 分钟（默认 10）往公会频道发一条「[Gearinsight插件] 公会 X 共 N 人 · 在线 M 人 · 全职业招募，密我进会」；
--   同时打开游戏的聊天记录（LoggingChat，等于 /chatlog），直播侧栏（_live_overlay.py /guild）从 Logs/WoWChatLog.txt 读这条 + 上下线提示。
--   ⛔ 默认关（每个会员都开 = 公会频道刷屏），只给会长 / 主播自己开：设置页「公会」栏或 /gi 通报
GL.REPORT_MIN = 10
function GL.ReportOn() return ns.db and ns.db.ui and ns.db.ui.guildReport == true end
function GL.Counts()
    if not (IsInGuild and IsInGuild()) then return nil end
    local ok, total, _, online = pcall(GetNumGuildMembers)
    if not ok or type(total) ~= "number" or total <= 0 or secret(total) then return nil end
    if type(online) ~= "number" or secret(online) then online = nil end
    local okn, gname = pcall(GetGuildInfo, "player")
    if not okn or type(gname) ~= "string" or secret(gname) then gname = nil end
    -- 11-06 用户截图 GuildInsight「共 271 人 · 在线 98 · 满级 0 · 平均 18 级」：通报带上平均等级（名册读得到几个算几个）
    local sum, n = 0, 0
    if GetGuildRosterInfo then
        for i = 1, total do
            local okr, _, _, _, lv = pcall(GetGuildRosterInfo, i)
            if okr and type(lv) == "number" and not secret(lv) and lv > 0 then sum, n = sum + lv, n + 1 end
        end
    end
    return total, online, gname, (n > 0) and math.floor(sum / n + 0.5) or nil
end
function GL.ReportText()
    local total, online, gname, avg = GL.Counts()
    if not total then return nil end
    local s = ns.L("[Gearinsight插件] 公会", "[Gearinsight] Guild") .. (gname and (" " .. gname) or "") .. string.format(ns.L(" 共 %d 人", " %d members"), total)
    if online then s = s .. string.format(ns.L(" · 在线 %d 人", " · %d online"), online) end
    if avg then s = s .. string.format(ns.L(" · 平均 %d 级", " · avg level %d"), avg) end
    return s .. ns.L(" · 全职业招募，密我进会", " · recruiting all classes, whisper me to join")
end
function GL.Report()
    local msg = GL.ReportText()
    if not (msg and SendChatMessage) then return false end
    if LoggingChat then pcall(LoggingChat, true) end
    return pcall(SendChatMessage, msg, "GUILD")
end
local ticker
function GL.SetReport(on)
    if not ns.db then return end
    ns.db.ui = ns.db.ui or {}
    ns.db.ui.guildReport = on and true or false
    if ticker then ticker:Cancel(); ticker = nil end
    if not on then return end
    if LoggingChat then pcall(LoggingChat, true) end
    -- 先刷新名册（在线人数才准），2 秒后发第一条
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
    if C_Timer and C_Timer.After then C_Timer.After(2, function() if GL.ReportOn() then GL.Report() end end) end
    if C_Timer and C_Timer.NewTicker then
        ticker = C_Timer.NewTicker(GL.REPORT_MIN * 60, function()
            if not GL.ReportOn() then return end
            if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
            C_Timer.After(2, function() if GL.ReportOn() then GL.Report() end end)
        end)
    end
end
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash["通报"] = function()
    GL.SetReport(not GL.ReportOn())
    if ns.Print then ns.Print(GL.ReportOn() and string.format(ns.L("公会统计通报：已开（每 %d 分钟发一次公会频道，聊天记录已打开）", "Guild stats report on (every %d min)"), GL.REPORT_MIN)
        or ns.L("公会统计通报：已关", "Guild stats report off")) end
end
ns.ExtraSlash.report = ns.ExtraSlash["通报"]
-- 上线后接着通报（开关存在存档里）
local rev = CreateFrame("Frame")
pcall(rev.RegisterEvent, rev, "PLAYER_ENTERING_WORLD")
rev:SetScript("OnEvent", function(self) self:UnregisterAllEvents(); if GL.ReportOn() and not ticker then C_Timer.After(10, function() if GL.ReportOn() and not ticker then GL.SetReport(true) end end) end end)
