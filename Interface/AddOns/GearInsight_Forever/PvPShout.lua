-- 野外荣誉击杀 / 被玩家击杀 → 发到公会频道（11-06 用户「荣誉击杀发生就在工会报一下，也默认打开，然后默认5分钟只能报一次，
--   被杀也是，分开计算，5分钟只能报一次」「野外，战场不算」）
--   · 只报野外：IsInInstance() 为真（战场 / 竞技场 / 副本）一律不报
--   · 被杀写成「我在<地区>被 部落 32级 亡灵 盗贼 黑手 杀了，附近的会员注意！」
--   · 击杀和被杀各自 5 分钟最多一次（时间戳存 ns.db.pvpShoutAt，/reload 不清零）；冷却里的直接丢，不攒
--   · 开关 ns.db.ui.pvpShout.kill / .death（nil = 默认开），设置页「公会」栏
--   ⛔ 12.0 引擎起插件注册 COMBAT_LOG_EVENT_UNFILTERED = ADDON_ACTION_FORBIDDEN（Stats.lua 10-07），不能用战斗记录：
--     击杀 = CHAT_MSG_COMBAT_HONOR_GAIN（「某某死亡，荣誉击杀…」，按客户端自己的 COMBATLOG_HONORGAIN 格式取名字）；
--       没有这条消息的客户端退回 PLAYER_PVP_KILLS_CHANGED（荣誉击杀数涨了，不带名字）
--     被杀 = PLAYER_DEAD：先看死亡回放最后一击是不是玩家（DeathRecap_GetEvents，客户端有才用）；
--       没有就看当前目标是不是能打的敌对玩家；都认不出 = 不报（宁可漏报，不把怪物击杀报成被玩家杀）
--   全部 pcall；名字 / 消息是保密值（12.x）原样放过不报
local _, ns = ...; ns = _G.GearInsightForever or ns
local L = ns.L

local PS = {}
ns.PvPShout = PS
PS.CD = 300   -- 默认 5 分钟
-- 11-06 用户「这些设置和开关也做下」：间隔可选（击杀 / 被杀各自设），存 ns.db.ui.pvpShoutCD[kind]（秒）
PS.CD_CHOICES = { 60, 300, 600, 1800 }
function PS.GetCD(kind)
    local c = ns.db and ns.db.ui and ns.db.ui.pvpShoutCD
    local v = c and tonumber(c[kind])
    return v or PS.CD
end
function PS.SetCD(kind, sec)
    if not ns.db then return end
    ns.db.ui = ns.db.ui or {}
    ns.db.ui.pvpShoutCD = ns.db.ui.pvpShoutCD or {}
    ns.db.ui.pvpShoutCD[kind] = tonumber(sec) or PS.CD
end

local function secret(v) return ns.Secret and ns.Secret(v) end
local function short(n) return (tostring(n or ""):gsub("%-.*$", "")) end
local function now() return time and time() or 0 end

function PS.On(kind)
    local c = ns.db and ns.db.ui and ns.db.ui.pvpShout
    return not (c and c[kind] == false)
end

function PS.Set(kind, on)
    if not ns.db then return end
    ns.db.ui = ns.db.ui or {}
    ns.db.ui.pvpShout = ns.db.ui.pvpShout or {}
    ns.db.ui.pvpShout[kind] = on and true or false
end

-- 野外 = 不在任何副本里（战场 pvp / 竞技场 arena / 地下城 party / 团本 raid 都算副本）
function PS.InWorld()
    if not IsInInstance then return true end
    local ok, inside, kind = pcall(IsInInstance)
    if not ok then return false end
    return not inside and (kind == nil or kind == "none")
end

local function zone()
    local z = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    if type(z) ~= "string" or secret(z) then return "" end
    return z
end

-- 11-06 用户截图「位置那里加上 <贫瘠之地> 角色名[名 姓]这样，然后加上坐标，坐标可以发出那种点击就标记的格式吗」：
--   位置 = 「<贫瘠之地> 45.6,32.1」+ 游戏自己的地图标记链接（会员点一下就在地图上打标）
--   ⛔ 链接只用 C_Map.GetUserWaypointHyperlink() 生成（自己拼的格式服务器可能整条吞掉）：先记下玩家原来的标记，
--      借用一下生成链接，再放回去（原来没有就清掉）。拿不到位置 / 没有这套接口 → 只写地区名
function PS.Pos()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or type(m) ~= "number" or secret(m) then return nil end
    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
    if not ok2 or not pos then return nil end
    local ok3, x, y = pcall(pos.GetXY, pos)
    if not ok3 or type(x) ~= "number" or type(y) ~= "number" or secret(x) or secret(y) or (x == 0 and y == 0) then return nil end
    return m, x, y
end

function PS.PinLink(m, x, y)
    if not (C_Map and C_Map.SetUserWaypoint and C_Map.GetUserWaypointHyperlink and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return nil end
    if C_Map.CanSetUserWaypointOnMap then
        local ok, can = pcall(C_Map.CanSetUserWaypointOnMap, m)
        if not ok or not can then return nil end
    end
    local old = C_Map.GetUserWaypoint and select(2, pcall(C_Map.GetUserWaypoint)) or nil
    local tracked = C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint and select(2, pcall(C_SuperTrack.IsSuperTrackingUserWaypoint))
    local link
    if pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(m, x, y)) then
        local ok, l = pcall(C_Map.GetUserWaypointHyperlink)
        if ok and type(l) == "string" and l ~= "" and not secret(l) then link = l end
    end
    if type(old) == "table" then
        pcall(C_Map.SetUserWaypoint, old)
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, tracked and true or false) end
    elseif C_Map.ClearUserWaypoint then
        pcall(C_Map.ClearUserWaypoint)
    end
    return link
end

function PS.Where()
    local z = zone()
    local s = "<" .. (z ~= "" and z or L("野外", "the world")) .. ">"
    local m, x, y = PS.Pos()
    if m then
        s = s .. string.format(" %.1f,%.1f", x * 100, y * 100)
        local link = PS.PinLink(m, x, y)
        if link then s = s .. " " .. link end
    end
    return s
end

-- 拼出要发的那句话；kind = "kill" / "death"；返回 nil = 这种情况不报
function PS.Format(kind, name, desc)
    if type(name) == "string" and (secret(name) or name == "") then name = nil end
    local tpl
    if kind == "kill" then
        -- 11-06 用户「击杀的部落角色信息跟被杀一致」：「荣誉击杀了 部落 24级 亡灵 潜行者 [夫赖]！」
        tpl = name and L("我在{z} 荣誉击杀了 {d}！", "I got an honorable kill on {d} at {z}!") or L("我在{z} 拿到一个荣誉击杀！", "I got an honorable kill at {z}!")
    else
        if not name then return nil end
        -- 「我在<贫瘠之地> 45.6,32.1 [地图标记] 被 部落 24级 亡灵 潜行者 [夫赖] 杀了，附近的会员注意！」
        tpl = L("我在{z} 被 {d} 杀了，附近的会员注意！", "Killed by {d} at {z}, guildies nearby watch out!")
    end
    -- 11-06 用户「名字也加上」→ 截图后「角色名[名 姓]这样」：名字放方括号（描述拿不到就只写名字）
    if name then
        local n = "[" .. short(name) .. "]"
        desc = (type(desc) == "string" and desc ~= "") and (desc .. " " .. n) or n
    end
    local where = PS.Where()
    -- 11-06 用户截图（公会频道带标记那句已能点）「加上[Gearinsight]」：句首挂品牌
    tpl = L("[Gearinsight插件] ", "[Gearinsight] ") .. tpl   -- 11-06 用户「[Gearinsight插件]xxx」
    -- 用 {z} / {n} / {d} 占位（Lua 5.1 的 string.format 不支持 %2$s，中英文语序又不同）
    return (tpl:gsub("{z}", function() return where end):gsub("{n}", function() return short(name) end)
        :gsub("{d}", function() return desc or "" end))
end

-- 返回 true = 发出去了
function PS.Shout(kind, name, desc)
    if not PS.On(kind) or not PS.InWorld() then return false end
    if not (IsInGuild and IsInGuild()) then return false end
    ns.db.pvpShoutAt = ns.db.pvpShoutAt or {}
    local last = tonumber(ns.db.pvpShoutAt[kind]) or 0
    local t = now()
    if t - last < PS.GetCD(kind) then return false end
    local msg = PS.Format(kind, name, desc)
    if not msg then return false end
    if not (PS.chatSend and PS.chatSend(msg, "GUILD")) then return false end   -- 11-07 统一走 C_ChatInfo + 255 字节截断
    ns.db.pvpShoutAt[kind] = t
    return true
end

-- 11-06 用户截图「还是弹出个对话框来问是否需要工会频道发信息求助吧，默认工会频道，有菜单可以选择小队还是团队」「只有野外，战场不需要」：
--   被玩家杀了不再自动发，弹求助框：预览那句话 + [公会][小队][团队]（默认公会；没加入的灰掉）+ [发送][不用了]
--   野外才弹（PS.InWorld）；冷却里不弹；点「发送」才记冷却；2 分钟没点自动收起。荣誉击杀照旧自动发公会
PS.CHANNELS = { { "GUILD", "公会", "Guild" }, { "PARTY", "小队", "Party" }, { "RAID", "团队", "Raid" } }
function PS.ChannelOk(ch)
    local ok, v
    if ch == "GUILD" then ok, v = pcall(function() return IsInGuild and IsInGuild() end)
    elseif ch == "PARTY" then ok, v = pcall(function() return IsInGroup and IsInGroup() end)
    elseif ch == "RAID" then ok, v = pcall(function() return IsInRaid and IsInRaid() end) end
    return ok and v and not secret(v) and true or false
end

local pop
local function mkPop()
    if pop then return pop end
    local f = CreateFrame("Frame", "GearInsightForeverPvPHelp", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(460, 168)
    f:SetPoint("TOP", UIParent, "TOP", 0, -160)
    f:SetFrameStrata("DIALOG")
    if f.SetBackdrop then
        pcall(f.SetBackdrop, f, { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    end
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -14)
    f.preview = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.preview:SetPoint("TOP", f.title, "BOTTOM", 0, -8); f.preview:SetWidth(424); f.preview:SetJustifyH("LEFT")
    f.chs = {}
    local mk = ns.SegButton or ns.Button
    for i, c in ipairs(PS.CHANNELS) do
        local b = mk(f, L(c[2], c[3]), 80, 22, function() PS.PickChannel(c[1]) end)
        b:SetPoint("BOTTOMLEFT", 20 + (i - 1) * 86, 46)
        b.ch = c[1]
        f.chs[#f.chs + 1] = b
    end
    f.send = ns.Button(f, L("发送", "Send"), 96, 24, function() PS.SendHelp() end)
    f.send:SetPoint("BOTTOMRIGHT", -122, 16)
    f.no = ns.Button(f, L("不用了", "No thanks"), 96, 24, function() f:Hide() end)
    f.no:SetPoint("BOTTOMRIGHT", -20, 16)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetScript("OnClick", function() f:Hide() end)   -- 原生红叉走 HideUIPanel，战斗中被拦 → 直接 Hide
    close:SetPoint("TOPRIGHT", -2, -2)
    f:Hide()
    pop = f
    PS._pop = f   -- 离线测试用
    return f
end

function PS.PickChannel(ch)
    local f = mkPop()
    if not PS.ChannelOk(ch) then return false end
    f.ch = ch
    for _, b in ipairs(f.chs) do
        local on = b.ch == ch
        if ns.SegSelect and b._segFs then ns.SegSelect(b, on) elseif b.LockHighlight then if on then b:LockHighlight() else b:UnlockHighlight() end end
        if b.SetEnabled then b:SetEnabled(PS.ChannelOk(b.ch)) end
        if b.SetAlpha then b:SetAlpha(PS.ChannelOk(b.ch) and 1 or 0.4) end
    end
    return true
end

-- 11-06 用户截图「这个也弹框，炫耀一下」：荣誉击杀也走同一个框（标题不同），冷却各算各的
PS.TITLES = {
    death = { "被玩家击杀了，发消息求助吗？", "Killed by a player - ask for help?" },
    kill = { "拿到荣誉击杀，炫耀一下？", "Honorable kill - show it off?" },
    level = { "升级了！要通报吗？", "Level up! Announce it?" },   -- 11-06 LevelShare 每级弹框
}
local function setTitle(f, kind)
    local t = PS.TITLES[kind] or PS.TITLES.death
    f.title:SetText(L(t[1], t[2]))
end

-- 返回 true = 弹出来了
function PS.Offer(kind, name, desc)
    if not PS.On(kind) or not PS.InWorld() then return false end
    ns.db.pvpShoutAt = ns.db.pvpShoutAt or {}
    local last = tonumber(ns.db.pvpShoutAt[kind]) or 0
    if now() - last < PS.GetCD(kind) then return false end
    local first
    for _, c in ipairs(PS.CHANNELS) do if PS.ChannelOk(c[1]) then first = c[1]; break end end
    if not first then return false end   -- 没公会也没队伍：没处可发
    local msg = PS.Format(kind, name, desc)
    if not msg then return false end
    local f = mkPop()
    f.msg, f.test, f.kind, f.onSent = msg, false, kind, false
    setTitle(f, kind)
    f.preview:SetText(msg)
    PS.PickChannel(first)   -- 默认公会；没公会退到小队 / 团队
    f:Show()
    local token = {}
    f.token = token
    if C_Timer and C_Timer.After then C_Timer.After(120, function() if f.token == token then f:Hide() end end) end
    return true
end

-- 通用：弹框发一句现成的话（LevelShare 升级播报用）；不看野外 / 冷却，onSent = 发出去后回调
function PS.OfferMsg(kind, msg, onSent)
    if type(msg) ~= "string" or msg == "" then return false end
    local first
    for _, c in ipairs(PS.CHANNELS) do if PS.ChannelOk(c[1]) then first = c[1]; break end end
    if not first then return false end
    local f = mkPop()
    f.msg, f.test, f.kind, f.onSent = msg, false, kind, onSent or false
    setTitle(f, kind)
    f.preview:SetText(msg)
    PS.PickChannel(first)
    f:Show()
    local token = {}
    f.token = token
    if C_Timer and C_Timer.After then C_Timer.After(120, function() if f.token == token then f:Hide() end end) end
    return true
end

-- 11-07 用户「升级弹窗，我点发送到工会，没有发」：① 聊天一条最多 255 字节（中文 3 字节一个），升级那句带排名 + 用时 + 战绩容易超 →
--   按 UTF-8 字符边界截到 255；② 先用 C_ChatInfo.SendChatMessage（升级自动发走的就是它），没有再用全局 SendChatMessage；
--   ③ 还是失败就在聊天框说一声，别让人以为发出去了
function PS.Clip(msg, max)
    max = max or 255
    if type(msg) ~= "string" or #msg <= max then return msg end
    local cut = max
    while cut > 0 do
        local b = msg:byte(cut + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end   -- 下一个字节不是续字节 = 这里是字符边界
        cut = cut - 1
    end
    local s = msg:sub(1, cut)
    -- 别把 |c…|r 颜色 / 链接截成半截
    local lastBar = s:match(".*()|")
    if lastBar and not s:sub(lastBar):find("|r", 1, true) and s:sub(lastBar, lastBar + 1) ~= "|r" then s = s:sub(1, lastBar - 1) end
    return s
end
local function chatSend(msg, ch)
    local f = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not f then return false, "api" end
    local ok, err = pcall(f, PS.Clip(msg), ch)
    return ok, err
end
PS.chatSend = chatSend

function PS.SendHelp()
    local f = pop
    if not (f and type(f.msg) == "string" and type(f.ch) == "string" and PS.ChannelOk(f.ch)) then
        if ns.Print then ns.Print(L("没发出去：你现在不在这个频道（没公会 / 没组队）", "Not sent: you're not in that channel")) end
        return false
    end
    local ok, err = chatSend(f.msg, f.ch)
    f:Hide()
    if not ok then
        if ns.Print then ns.Print(L("没发出去：", "Not sent: ") .. tostring(err)) end
        return false
    end
    if f.test == true then return true end
    if type(f.onSent) == "function" then pcall(f.onSent) end
    if f.kind ~= "kill" and f.kind ~= "death" then return true end   -- 升级播报不占击杀 / 被杀的冷却
    ns.db.pvpShoutAt = ns.db.pvpShoutAt or {}
    ns.db.pvpShoutAt[f.kind] = now()
    return true
end

-- /gi pvp：用示例凶手弹一次求助框（不看开关 / 野外 / 冷却，发了也不记冷却），试界面和地图标记
function PS.Test()
    local msg = PS.Format("death", L("测试凶手", "TestKiller"), L("部落 24级 亡灵 潜行者", "Horde level 24 Undead Rogue"))
    if not msg then return false end
    local f = mkPop()
    f.msg, f.test, f.kind, f.onSent = msg, true, "death", false
    setTitle(f, "death")
    f.preview:SetText(msg)
    local first
    for _, c in ipairs(PS.CHANNELS) do if PS.ChannelOk(c[1]) then first = c[1]; break end end
    if first then PS.PickChannel(first) else f.ch = nil end
    f:Show()
    return true
end
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.pvp = PS.Test

-- 「%s死亡，荣誉击杀军衔：%s（预计荣誉点数：%d）」→ Lua 模式，第一个 %s 是名字
local function toPattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local p = fmt:gsub("%%%d*%$?s", "\001"):gsub("%%%d*%$?d", "\002")
    p = p:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
    p = p:gsub("\001", "(.-)"):gsub("\002", "%%d+")
    return "^" .. p .. "$"
end
PS.toPattern = toPattern

-- 11-06 用户截图「荣誉击杀了 部落 26级 亡灵 潜行者 [致死]」「没带姓」：《无限》角色名是「名 姓」，UnitName 只给名。
--   照右键「邀请入会」（InviteMenu.lua IM.Target）的办法拼全名：① UnitFullName 第二段 ② GetPlayerInfoByGUID 名 + 第二段；
--   第二段是本服服务器名就不算姓（IM.joinName 判断）；都拿不到就用原来的名
local function fullOf(unit, guid, name)
    local join = ns.InviteMenu and ns.InviteMenu.joinName
    if type(name) == "string" and name:find(" ", 1, true) then return name end
    if join and unit and UnitFullName then
        local ok, a, b = pcall(UnitFullName, unit)
        local n = ok and join(a, b) or nil
        if type(n) == "string" and n:find(" ", 1, true) then return n end
    end
    if join and guid and GetPlayerInfoByGUID and not secret(guid) then
        local ok, _, _, _, _, _, gn, gr = pcall(GetPlayerInfoByGUID, guid)
        local n = ok and join(gn, gr) or nil
        if type(n) == "string" and n:find(" ", 1, true) then return n end
    end
    return name
end
PS.fullOf = fullOf
local function first(n) return (tostring(n or ""):gsub("%-.*$", ""):match("^(%S+)")) end

function PS.VictimFromHonorMsg(msg)
    if type(msg) ~= "string" or secret(msg) then return nil end
    for _, g in ipairs({ "COMBATLOG_HONORGAIN", "COMBATLOG_HONORGAIN_NO_RANK" }) do
        local p = toPattern(_G[g])
        local n = p and msg:match(p)
        if n and n ~= "" then return n end
    end
    return nil
end

-- 被杀：死亡回放最后一击是玩家 → 名字, GUID；否则当前目标是能打的敌对玩家 → 名字, GUID, "target"；都不是 nil
-- 11-06 用户截图「我被部落杀了，为啥没有报告」：原来取 evs[#evs] 当最后一击，可暴雪的回放 events[1] 才是最后一击，
--   evs[#evs] 是最早那条（截图里是陆行鸟）→ 判成「被怪杀」不报。现在不靠顺序：回放里时间最晚的那条玩家伤害就是凶手；
--   最后一击是宠物 / 怪、但玩家也在打我，同样算被玩家杀（附近有敌对玩家就该提醒）。回放里一条玩家都没有 = 不报
local function recapEvents()
    local tries = {}
    if DeathRecap_GetEvents then tries[#tries + 1] = DeathRecap_GetEvents end
    if C_DeathRecap and C_DeathRecap.GetRecapEvents then tries[#tries + 1] = C_DeathRecap.GetRecapEvents end
    for _, fn in ipairs(tries) do
        local ok, evs = pcall(fn)
        if ok and type(evs) == "table" and #evs > 0 then return evs end
    end
    return nil
end

-- 11-07 用户截图「被 部落 人类 术士 [银色闪光猫 宅且冷脸萌] 杀了」= 他自己：术士生命分流 / 地狱烈焰会伤自己，
--   死亡回放里自己也是「玩家」伤害来源 → 被当成凶手（阵营又按「和我相反」补成了部落）。
--   凶手只认敌对玩家：跳过自己、队友 / 团员；种族能看出阵营的，和我同阵营的也跳过
local ALLIANCE_RACE = { Human = true, Dwarf = true, NightElf = true, Gnome = true, Draenei = true, Worgen = true }
local HORDE_RACE = { Orc = true, Scourge = true, Undead = true, Tauren = true, Troll = true, BloodElf = true, Goblin = true }
local function myFaction()
    local ok, f = pcall(UnitFactionGroup, "player")
    return ok and (f == "Alliance" or f == "Horde") and f or nil
end
function PS.IsFriendlyGUID(guid)
    if type(guid) ~= "string" or secret(guid) then return false end
    local me = UnitGUID and UnitGUID("player")
    if me and not secret(me) and me == guid then return true end
    if IsInGroup and IsInGroup() then
        local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        local pre = (IsInRaid and IsInRaid()) and "raid" or "party"
        for i = 1, n do
            local ok, g = pcall(UnitGUID, pre .. i)
            if ok and g and not secret(g) and g == guid then return true end
        end
    end
    local mf = myFaction()
    if mf and GetPlayerInfoByGUID then
        local ok, _, _, _, race = pcall(GetPlayerInfoByGUID, guid)
        if ok and type(race) == "string" and not secret(race) then
            if (mf == "Alliance" and ALLIANCE_RACE[race]) or (mf == "Horde" and HORDE_RACE[race]) then return true end
        end
    end
    return false
end

function PS.Killer()
    local evs = recapEvents()
    if evs then
        local best, bestT, bestI
        for i, e in ipairs(evs) do
            local guid, nm = type(e) == "table" and e.sourceGUID, type(e) == "table" and e.sourceName
            if type(guid) == "string" and not secret(guid) and guid:find("^Player%-") and not PS.IsFriendlyGUID(guid)
                and type(nm) == "string" and not secret(nm) and nm ~= "" then
                local t = tonumber(not secret(e.timestamp) and e.timestamp) or 0
                -- 时间一样（或没有时间）按「下标小 = 更晚」：暴雪回放 events[1] 是最后一击
                if not best or t > bestT or (t == bestT and i < bestI) then best, bestT, bestI = e, t, i end
            end
        end
        if not best then return nil end   -- 回放里全是怪 / 掉落 = 不是被玩家杀
        local tg = UnitGUID and UnitGUID("target")
        local u = (tg and not secret(tg) and tg == best.sourceGUID) and "target" or nil
        return fullOf(u, best.sourceGUID, best.sourceName), best.sourceGUID, u
    end
    local ok, isP = pcall(function() return UnitExists("target") and UnitIsPlayer("target") and UnitCanAttack("player", "target") end)
    if ok and isP and not secret(isP) then
        local n = UnitName("target")
        local g = UnitGUID and UnitGUID("target")
        if type(g) ~= "string" or secret(g) then g = nil end
        if g and PS.IsFriendlyGUID(g) then return nil end
        if type(n) == "string" and not secret(n) then return fullOf("target", g, n), g, "target" end
    end
    return nil
end

-- 11-06 用户「写出 被 部落 XX级 种族 职业 杀了，附近的会员注意！」→ 凶手描述「部落 32级 亡灵 盗贼」
--   有单位（当前目标 / 姓名板上找到同一 GUID）就读阵营 / 等级 / 种族 / 职业；只有 GUID 用 GetPlayerInfoByGUID 取种族 / 职业，
--   阵营按「和我相反」（野外能打死我的玩家只会是敌对阵营），等级读不到就不写。哪一项是保密值 / 拿不到就跳过那一项
local function ok1(v) return v ~= nil and not secret(v) and v ~= "" end
local function unitForGUID(guid, unit)
    if unit then return unit end
    if not (guid and UnitGUID) then return nil end
    for i = 1, 40 do
        local u = "nameplate" .. i
        local ok, g = pcall(UnitGUID, u)
        if ok and g and not secret(g) and g == guid then return u end
    end
    return nil
end

function PS.Describe(guid, unit)
    unit = unitForGUID(guid, unit)
    local fac, lv, race, cls
    if unit then
        pcall(function()
            local _, f = UnitFactionGroup(unit); fac = f
            lv = UnitLevel(unit)
            race = UnitRace(unit)
            cls = UnitClass(unit)
        end)
    end
    if guid and (not ok1(race) or not ok1(cls)) and GetPlayerInfoByGUID then
        local ok, c, _, r = pcall(GetPlayerInfoByGUID, guid)
        if ok then
            if not ok1(cls) then cls = c end
            if not ok1(race) then race = r end
        end
    end
    if not ok1(fac) and UnitFactionGroup then
        local ok, mine = pcall(UnitFactionGroup, "player")
        if ok and mine == "Alliance" then fac = FACTION_HORDE or L("部落", "Horde")
        elseif ok and mine == "Horde" then fac = FACTION_ALLIANCE or L("联盟", "Alliance") end
    end
    local parts = {}
    if ok1(fac) then parts[#parts + 1] = fac end
    if type(lv) == "number" and not secret(lv) then
        parts[#parts + 1] = lv > 0 and L(lv .. "级", "level " .. lv) or L("??级", "level ??")
    end
    if ok1(race) then parts[#parts + 1] = race end
    if ok1(cls) then parts[#parts + 1] = cls end
    return table.concat(parts, " ")
end

-- 11-06「击杀的部落角色信息跟被杀一致」：被我杀的人死了以后姓名板就没了，所以活着时就记下来——
--   选中 / 鼠标指过的敌对玩家（名字、阵营 / 等级 / 种族 / 职业），留 60 秒；击杀时荣誉消息给了名字就按名字找，
--   没给名字就先看当前目标（还选着那具尸体），再取 15 秒内最近的一个。都没有 = 只报「拿到一个荣誉击杀」
local function gt() return GetTime and GetTime() or 0 end
local recent = {}
PS._recent = recent   -- 离线测试用
local function isEnemyPlayer(u)
    local ok, v = pcall(function() return UnitExists(u) and UnitIsPlayer(u) and (UnitIsEnemy and UnitIsEnemy("player", u) or UnitCanAttack("player", u)) end)
    return ok and v and not secret(v) and true or false
end
function PS.Remember(u)
    if not isEnemyPlayer(u) then return end
    local ok, n = pcall(UnitName, u)
    if not ok or type(n) ~= "string" or secret(n) or n == "" then return end
    local g = UnitGUID and select(2, pcall(UnitGUID, u))
    if type(g) ~= "string" or secret(g) then g = nil end
    local okd, d = pcall(PS.Describe, g, u)
    local t = gt()
    local full = short(fullOf(u, g, n))
    for i = #recent, 1, -1 do if first(recent[i].n) == first(full) or t - recent[i].t > 120 then table.remove(recent, i) end end
    recent[#recent + 1] = { n = full, d = okd and d or nil, t = t }
    if #recent > 20 then table.remove(recent, 1) end
end
function PS.Victim(name)
    local t = gt()
    if name then
        for i = #recent, 1, -1 do
            local r = recent[i]
            if (r.n == short(name) or first(r.n) == first(name)) and t - r.t <= 60 then return r.n, r.d end   -- 荣誉消息可能只给名：按首段名对，用记下的全名
        end
        return short(name), nil
    end
    if isEnemyPlayer("target") then
        PS.Remember("target")
        local r = recent[#recent]
        if r then return r.n, r.d end
    end
    local r = recent[#recent]
    if r and t - r.t <= 15 then return r.n, r.d end
    return nil
end

-- 11-09 用户截图「被 部落 亡灵 圣骑士 [糕糕 爱吃年糕] 杀了」+「加上等级」：死后凶手多半已经不在目标 / 姓名板上，读不到等级 →
--   活着时姓名板出现、选中、鼠标指过的敌对玩家都记下（PS.Remember，含等级），死亡时按名字从这里取描述
function PS.KillerDesc(name, guid, unit)
    local okd, d = pcall(PS.Describe, guid, unit)
    d = okd and d or nil
    if name and not (d and (d:find("%d") or d:find("??", 1, true))) then
        local t = gt()
        for i = #recent, 1, -1 do
            local r = recent[i]
            if (r.n == short(name) or first(r.n) == first(name)) and t - r.t <= 120 and r.d then return r.d end
        end
    end
    return d
end

local honorMsgSeen, honorAt = false, -999
local f = CreateFrame("Frame")
for _, e in ipairs({ "CHAT_MSG_COMBAT_HONOR_GAIN", "PLAYER_PVP_KILLS_CHANGED", "PLAYER_DEAD", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED" }) do
    local valid = not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e)
    if valid then pcall(f.RegisterEvent, f, e) end
end
f:SetScript("OnEvent", function(_, e, msg)
    if e == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        local ok, n = pcall(PS.VictimFromHonorMsg, msg)
        if ok and n then
            honorMsgSeen, honorAt = true, gt()
            local vn, vd = PS.Victim(n)
            pcall(PS.Offer, "kill", vn or n, vd)
        end
    elseif e == "PLAYER_PVP_KILLS_CHANGED" then
        -- 两个事件谁先到不一定：等 1 秒，期间没来荣誉消息（这个客户端没有 / 没认出名字）才报不带名字的
        local at = gt()
        local function later()
            if honorMsgSeen and honorAt >= at - 1 then return end
            local vn, vd = PS.Victim(nil)   -- 没有荣誉消息：按当前目标 / 刚打过的敌对玩家认
            pcall(PS.Offer, "kill", vn, vd)
        end
        if C_Timer and C_Timer.After then C_Timer.After(1, later) else later() end
    elseif e == "PLAYER_TARGET_CHANGED" or e == "UPDATE_MOUSEOVER_UNIT" then
        PS.Remember(e == "PLAYER_TARGET_CHANGED" and "target" or "mouseover")
    elseif e == "NAME_PLATE_UNIT_ADDED" then
        if type(msg) == "string" and not secret(msg) then pcall(PS.Remember, msg) end
    elseif e == "PLAYER_DEAD" then
        -- 死亡回放是死后才整理好的：等 1 秒再读
        local function later()
            local ok, n, guid, unit = pcall(PS.Killer)
            if ok and n then
                local okd, d = pcall(PS.KillerDesc, n, guid, unit)
                pcall(PS.Offer, "death", n, okd and d or nil)   -- 11-06 改成弹求助框，不自动发
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(1, later) else later() end
    end
end)
PS._frame = f   -- 离线测试用
