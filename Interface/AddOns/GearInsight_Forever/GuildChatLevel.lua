-- HOLD：公会频道显示等级（10-18 用户截图「增加个能力，设置里可以开，默认打开，就是工会频道显示当前等级」）
--   公会 / 官员频道名字前加「[26]」：[公会] [26][玛尔 卖啤]: …。等级取游戏自带公会名单（含没装插件的人），自己的用 UnitLevel。
--   ⛔ 不改 author 参数、不钩 GetColoredName（会弄坏名字链接 / 右键菜单），只在聊天框显示前往整行里插字。
--   名单在 GUILD_ROSTER_UPDATE 时只记「脏了」，有人说话时才重建（最多 5 秒一次）；没人说话 = 零开销。
--   开关 ns.db.ui.guildChatLevel（nil = 默认开），设置页「公会」一栏。
local _, ns = ...; ns = _G.GearInsightForever or ns  -- 10-19 用户「拿到主插件，不要放子插件了」：搬回主插件，登录就跑（不用先点公会页签）；这行在主插件里也成立
local L = ns.L

local GL = {}
ns.GuildChatLevel = GL

local levels, dirty, builtAt, askedAt = {}, true, -999, -999
local function now() return GetTime and GetTime() or 0 end
local function secret(v) return ns.Secret and ns.Secret(v) end
local function short(n) return n:match("^([^%-]+)") or n end

function GL.Enabled()
    return not (ns.db and ns.db.ui and ns.db.ui.guildChatLevel == false)
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
    local t = {}
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        local ok, total = pcall(GetNumGuildMembers)
        total = ok and tonumber(total) or 0
        for i = 1, total do
            local ok2, name, _, _, level = pcall(GetGuildRosterInfo, i)
            level = ok2 and tonumber(level) or nil
            if type(name) == "string" and level and not secret(name) and not secret(level) then t[short(name)] = level end
        end
    end
    levels = t
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
function GL.Tag(lv) return "|cffc8b27a[" .. lv .. "]|r" end

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
GL.Paused = true
function GL.HookFrame() end   -- 兼容旧调用：什么也不做

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
