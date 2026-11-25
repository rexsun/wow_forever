-- 帐篷蹭露营 · 弹窗 / 求组 / 离队感谢 / /gi camp（11-24 从主插件 Camp.lua 原样搬来，内核减肥：登录不占内存）。
--   主插件 Camp.lua 留：读提示框认帐篷、判断弹不弹（CanOffer）和不弹的原因提示、别人申请进我队（帐篷主人那侧）、事件、存档、设置项。
--   要弹窗了（CP.Offer）/ 敲 /gi camp 时才加载这个子插件（ns.ModLoad("gate")）；这里定义 CP.Show / CP.Request / CP.OnWho / CP.OnRoster / /gi camp 真处理函数。
--   CP.whispered 有人 = 一定点过「密他求组」= 这个文件早已加载：离队感谢（OnRoster）、/who 回包（OnWho）都只在那之后才有事做。
--   ⛔ 这里的文件都晚于主插件加载：文件头一律 ns = _G.GearInsightForever or ns
local _, ns = ...; ns = _G.GearInsightForever or ns
local CP = ns.Camp
if not CP then return end
local L = ns.L
local function now() return GetTime and GetTime() or 0 end
local function str(v) return type(v) == "string" and not ns.Secret(v) and v ~= "" and v or nil end
local function short(n) n = str(n); return n and (n:match("^([^%-]+)") or n) or nil end
local function on(k) return CP.DB()[k] ~= false end


-- ---------- 弹窗 ----------
local pop
local function buildPop()
    local f = CreateFrame("Frame", "GearInsightForeverCampPop", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(360, 74); f:SetPoint("TOP", 0, -150); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
    if f.SetBackdrop then
        pcall(f.SetBackdrop, f, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.03, 0.035, 0.05, 0.9); f:SetBackdropBorderColor(0.85, 0.68, 0.25, 0.85)
    end
    f.t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.t:SetPoint("TOPLEFT", 10, -10); f.t:SetPoint("TOPRIGHT", -10, -10); f.t:SetJustifyH("LEFT"); f.t:SetWordWrap(true)
    f.yes = ns.Button(f, L("密他求组", "Whisper"), 120, 22, function() f:Hide(); CP.Request(f.owner) end)
    f.yes:SetPoint("BOTTOMLEFT", 10, 8)
    f.no = ns.Button(f, L("不用", "No thanks"), 80, 22, function() f:Hide() end)
    f.no:SetPoint("LEFT", f.yes, "RIGHT", 8, 0)
    -- 11-08 玩家「鼠标路过别人帐篷 组队的 哪里关啊」：弹窗上直接给「不再提示」，设置页也有开关
    f.off = ns.Button(f, L("不再提示", "Don't ask again"), 90, 22, function()
        f:Hide(); CP.SetOn(false)
        -- 11-17「永久关闭」：存档 camp.on = false（功能中心「帐篷蹭露营」同一个键）；找回提示同一句最多说 3 次（ns.CloseHint）
        local msg = string.format(L("帐篷蹭露营提示已永久关闭。找回 / 重新打开：GI 菜单 → 窗口与提醒 → 帐篷蹭露营弹窗，或 %s camp on", "Tent prompts off for good - bring them back: GI menu > Windows & alerts > Tent prompt, or %s camp on"), ns.SlashHint or "/gi")
        if ns.CloseHint then ns.CloseHint("campPop", msg) else ns.Print(msg) end
    end)
    f.off:SetPoint("BOTTOMRIGHT", -10, 8)
    f:Hide()
    return f
end

-- 弹窗本体（内核 Camp.lua 的 CP.Offer 判断过要弹、记了「问过」才调这里）
function CP.Show(who)
    pop = pop or buildPop()
    CP.pop = pop
    pop.owner = who
    local text = string.format(L("附近有 |cffffd100%s|r 放的帐篷，密他求组蹭露营？（他拉你才进队）", "|cffffd100%s|r placed a tent nearby. Whisper them for an invite?"), who)
    if CP.soon then
        text = text .. "\n" .. string.format(L("你身上的「%s」还剩 %d 秒，等你进队坐下时就结束了", "Your \"%s\" ends in %ds - it'll be gone by the time you sit down"), CP.soon.name, CP.soon.left)
    end
    if CP.nonxp then
        text = text .. "\n" .. string.format(L("你身上的「%s」没有经验加成：进他队伍后在帐篷旁坐满 60 秒才有", "Your \"%s\" gives no XP: join their group and sit by the tent for 60 seconds"), CP.nonxp)
    end
    pop.t:SetText(text)
    -- 11-08 用户截图：主人名字长（「看我脸色行事 大天使泰瑞尔」）时第三行被截掉 → 按文字实际高度撑开
    local th = tonumber(pop.t.GetStringHeight and pop.t:GetStringHeight()) or 28
    pop:SetHeight(math.max(74, th + 50))
    pop:Show()
    pop.at = now()
    if C_Timer and C_Timer.After then
        local at = pop.at
        C_Timer.After(30, function() if pop and pop.at == at then pop:Hide() end end)
    end
    return true
end

local function send(msg, who)
    local f = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not (f and msg and who) then return false end
    return (pcall(f, msg, "WHISPER", nil, who))
end

-- 11-09 用户「措辞委婉点，比如说老哥，求xxx」→「多弄几个变体，可以随机出，不至于被认出来」：
--   求组 / 感谢各一池随机挑，和上一句不重样；/gi camp msg、/gi camp thanks 自定义了就只用自定义的
-- 11-17 用户「改成义父」「都改」：求组 / 感谢里的称呼（老哥 / 大佬 / 兄弟 / 老板）都换成「义父」
CP.ASK = {
    { "义父，求拉一下蹭个帐篷~ 坐一分钟就走，谢谢啦！", "Hey friend, mind inviting me to share your tent? Just a minute, thanks a lot!" },
    { "义父，能拉我进队蹭下帐篷不？蹭完就退，感谢感谢~", "Hi! Could you invite me to rest at your tent? I'll leave right after, thanks!" },
    { "义父，路过看到你的帐篷，求带一下~ 坐会儿就走", "Hey, saw your tent - mind inviting me for a minute?" },
    { "义父好，求组一下蹭个帐篷经验，一分钟就退，谢啦！", "Hello! Could I join for a minute to use your tent? Thanks!" },
    { "义父你好~ 帐篷能借我坐一下不？拉我进队就行，蹭完马上走", "Hi there - could I borrow a spot at your tent? Just invite me, I'll head off soon after." },
    { "打扰啦，求拉进队蹭个帐篷，坐满一分钟就退，谢谢义父！", "Sorry to bother - could you invite me to share the tent? Only a minute, thank you!" },
    { "好心人求拉一下~ 想在你帐篷边坐会儿，马上就走", "Kind stranger, could you invite me to sit by your tent for a bit?" },
}
CP.THANK = {
    { "谢谢义父的帐篷，祝你玩得开心！", "Thanks for the tent, have fun!" },
    { "蹭完啦，谢谢义父~ 祝出好装备！", "All done - thank you! Good luck with your loot!" },
    { "谢谢义父，帐篷很舒服，一路顺风~", "Thanks a lot, the tent was great. Safe travels!" },
    { "感谢义父的帐篷！祝升级飞快~", "Thanks for the tent! Happy leveling!" },
    { "谢谢好心人~ 有缘再见！", "Thank you, kind stranger - see you around!" },
}
local lastPick = {}
function CP.Pick(pool)
    local n = #pool
    local i = math.random(1, n)
    if n > 1 and i == lastPick[pool] then i = i % n + 1 end
    lastPick[pool] = i
    return ns.ApplyCall(ns.ChatL(pool[i][1], pool[i][2]))   -- 11-18 GI-307 称呼可改（默认义父）；11-19 密给帐篷主人：走对外说话语言
end

-- 11-10 用户「无限露营主动发私聊就行，申请加入功能放到设置，默认关闭」：点了只密一句（对方愿意就拉你）；
--   系统入队申请（RequestInviteFromUnit）改成设置项 camp.reqJoin，默认关
function CP.ReqJoinOn() return CP.DB().reqJoin == true end
-- 求组：密一句说明来意（+ 设置里开了才发系统入队申请）；不自动接受任何邀请
-- ---------- GI-282 帐篷主人在不在这张地图（11-16 玩家「帐篷主人和你不在同块地图的时候，不会触发 20% 经验加成」）----------
--   点「密他求组」时先看主人在不在身边（目标 / 鼠标指向 / 姓名板里有他 = 同一张地图，直接发）；
--   不在身边 → /who n-"主人"（点击里发，硬件事件）查他在哪个区：和我同区才发；不同区 = 不发，聊天框说明；查不到（下线 / 改名）= 不发；
--   WHO_TIMEOUT 秒没结果（/who 被限流）= 照常发（宁可多发一句也别卡住）。搜的时候摘掉好友面板的 WHO_LIST_UPDATE（同 Liminal.lua）
--   进队后再看一次：主人和我不在同一张地图 → 提示「20% 经验加成不会生效（专业制作的效果照常）」
--   设置 camp.zoneCheck（nil = 开）；/gi camp zone on|off
CP.WHO_TIMEOUT = 6
function CP.ZoneCheckOn() return CP.DB().zoneCheck ~= false end
local function sameShort(a, b)
    a, b = short(a), short(b)
    return a ~= nil and a == b
end
-- 主人就在身边（读得到他的单位）→ 单位名；否则 nil
function CP.OwnerUnit(who)
    local units = { "target", "mouseover", "focus" }
    for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
    for _, u in ipairs(units) do
        local ok, n = pcall(UnitName, u)
        if ok and str(n) and sameShort(n, who) then return u end
    end
    return nil
end
local function myZone()
    local z = GetRealZoneText and str((select(2, pcall(GetRealZoneText))))
    return z or (GetZoneText and str((select(2, pcall(GetZoneText)))))
end
CP.MyZone = myZone
local function friendsWho(mute)
    local f = FriendsFrame
    if not (f and f.UnregisterEvent) then return end
    pcall(function()
        if mute then
            CP._friendsHad = not f.IsEventRegistered or f:IsEventRegistered("WHO_LIST_UPDATE") and true or false
            f:UnregisterEvent("WHO_LIST_UPDATE")
        elseif CP._friendsHad then
            f:RegisterEvent("WHO_LIST_UPDATE")
        end
    end)
end
local function whoToUi(on2)
    if C_FriendList and C_FriendList.SetWhoToUi then pcall(C_FriendList.SetWhoToUi, on2)
    elseif SetWhoToUI then pcall(SetWhoToUI, on2 and 1 or 0) end
end
local function whoEnd()
    CP.pendingWho = nil
    friendsWho(false)
    whoToUi(false)
end
-- /who 第 i 条 → 名字, 区域
function CP.WhoInfo(i)
    if C_FriendList and C_FriendList.GetWhoInfo then
        local ok, t = pcall(C_FriendList.GetWhoInfo, i)
        if ok and type(t) == "table" then return str(t.fullName), str(t.area) end
        return nil
    end
    if GetWhoInfo then
        local ok, name, _, _, _, _, zone = pcall(GetWhoInfo, i)
        if ok then return str(name), str(zone) end
    end
    return nil
end
-- 点「密他求组」：先判断主人在不在这张地图
function CP.Request(who)
    if not who then return false end
    if not CP.ZoneCheckOn() or CP.OwnerUnit(who) then return CP.DoRequest(who) end
    local send = (C_FriendList and C_FriendList.SendWho) or SendWho
    if not send then return CP.DoRequest(who) end
    friendsWho(true)
    whoToUi(true)
    local q = 'n-"' .. (short(who) or who) .. '"'
    if not pcall(send, q) then whoEnd(); return CP.DoRequest(who) end
    local p = { who = who, at = now() }
    CP.pendingWho = p
    ns.Print(string.format(L("先查一下 %s 在不在这张地图（不在的话组进去也拿不到 20%% 经验加成）…", "Checking whether %s is in this zone (no 20%% XP bonus otherwise)..."), short(who) or who))
    if C_Timer and C_Timer.After then
        C_Timer.After(CP.WHO_TIMEOUT, function()
            if CP.pendingWho == p then
                whoEnd()
                ns.Print(string.format(L("没查到 %s 在哪（/who 没回），照常密他", "Couldn't look up %s's zone - whispering anyway"), short(who) or who))
                CP.DoRequest(who)
            end
        end)
    end
    return true
end
function CP.OnWho()
    local p = CP.pendingWho
    if not p then return end
    whoEnd()
    local n = tonumber((select(2, pcall((C_FriendList and C_FriendList.GetNumWhoResults) or GetNumWhoResults or function() return 0 end)))) or 0
    local zone
    for i = 1, n do
        local name, area = CP.WhoInfo(i)
        if name and sameShort(name, p.who) then zone = area or ""; break end
    end
    local mine = myZone()
    local who = short(p.who) or p.who
    if zone == nil then
        ns.Print(string.format(L("/who 查不到 %s（可能下线了），没发密语", "%s not found with /who (offline?) - no whisper sent"), who))
        return false, "notfound"
    end
    if zone == "" or not mine or zone == mine then return CP.DoRequest(p.who) end
    ns.Print(string.format(L("%s 现在在「%s」，不在这张地图（%s）：组进去也拿不到 20%% 经验加成，没发密语", "%s is in %s, not here (%s): no 20%% XP bonus even if invited - no whisper sent"),
        who, zone, mine))
    return false, "otherzone"
end
-- 进队后：主人和我是不是同一张地图（看他的单位所在地图）
function CP.OwnerMapDiffers(who)
    if not (C_Map and C_Map.GetBestMapForUnit) then return false end
    local mine = select(2, pcall(C_Map.GetBestMapForUnit, "player"))
    for i = 1, 4 do
        local u = "party" .. i
        local ok, n = pcall(UnitName, u)
        if ok and str(n) and sameShort(n, who) then
            local m = select(2, pcall(C_Map.GetBestMapForUnit, u))
            if type(m) == "number" and type(mine) == "number" and m ~= mine then return true end
            return false
        end
    end
    return false
end
-- 真正发：密一句（+ 设置里开了才发系统入队申请）
function CP.DoRequest(who)
    if not who then return false end
    local req = false
    if CP.ReqJoinOn() and C_PartyInfo and C_PartyInfo.RequestInviteFromUnit then
        req = (pcall(C_PartyInfo.RequestInviteFromUnit, who))
    end
    local msg = CP.DB().msg or CP.Pick(CP.ASK)
    local sent = send(msg, who)
    -- 11-09 用户「只主动拒绝露营申请的人」：再发一个插件暗号，对方插件靠它认出这是来蹭露营的（自定义话术里没「帐篷」也认得出）
    local am = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if am then pcall(am, CP.PREFIX, "ask", "WHISPER", who) end
    if not (req or sent) then return false end
    CP.whispered[who] = now()
    ns.Print(string.format(req and L("已密 %s 并发了入队申请，等对方同意", "Whispered %s and sent a join request - waiting for them to accept")
        or L("已密 %s 求组，等对方拉你", "Whispered %s - waiting for an invite"), who))
    return true
end
CP.Whisper = CP.Request

-- 进队 / 离队：同过队的帐篷主人，离队时密一句谢谢
function CP.OnRoster()
    if CP.joined then
        if not CP.InGroupWith(CP.joined.who) then
            local who = CP.joined.who
            CP.joined = nil
            if on("thank") and not CP.thanked[who] then
                local msg = CP.DB().thankMsg or CP.Pick(CP.THANK)
                if send(msg, who) then CP.thanked[who] = true end
            end
        end
        return
    end
    for who, t in pairs(CP.whispered) do
        if now() - t < 7200 and CP.InGroupWith(who) then
            CP.joined = { who = who, at = now() }
            ns.Print(L("已进队：在帐篷旁坐下（按 X）满 60 秒才拿到奖励经验", "Joined: sit (X) next to the tent for 60 sec to get the rested XP"))
            if CP.ZoneCheckOn() and CP.OwnerMapDiffers(who) then   -- GI-282
                ns.Print(string.format(L("注意：帐篷主人 %s 现在不在这张地图，20%% 经验加成不会生效（专业制作的效果照常）", "Note: tent owner %s is not in this zone - the 20%% XP bonus won't apply (crafting buffs still do)"), short(who) or who))
            end
            return
        end
    end
end

-- ---------- /gi camp ----------
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.camp = function(rest, rawRest)
    local sub, arg = (rest or ""):match("^(%S*)%s*(.-)$")
    local rawArg = (rawRest or ""):match("^%S*%s*(.-)$") or arg
    local d = CP.DB()
    local C = (ns.SlashHint or "/gif") .. " camp"
    if sub == "on" or sub == "off" then d.on = sub == "on"
    elseif sub == "thank" and (arg == "on" or arg == "off") then d[sub] = arg == "on"
    elseif sub == "zone" and (arg == "on" or arg == "off") then if arg == "on" then d.zoneCheck = nil else d.zoneCheck = false end
    elseif sub == "accept" and (arg == "on" or arg == "off") then d.reqAcceptSolo = arg == "on" or nil
    elseif sub == "decline" and (arg == "on" or arg == "off") then d.reqDecline = arg == "on" or nil
    elseif sub == "msg" then d.msg = rawArg ~= "" and rawArg or nil
    elseif sub == "thanks" then d.thankMsg = rawArg ~= "" and rawArg or nil
    elseif sub == "probe" then
        ns.ShowBox(L("帐篷探针", "Tent probe"), L("复制全部发给开发者", "Copy all and send to the developer"), table.concat(d.probe or {}, "\n"))
        return
    end
    local function st(k) return on(k) and L("开", "on") or L("关", "off") end
    local function st2(v) return v and L("开", "on") or L("关", "off") end
    ns.Print(string.format(L("帐篷蹭露营：%s · 离队自动感谢：%s · 入队申请单人自动同意：%s · 自动拒绝蹭露营的：%s", "Tent: %s - thank on leave: %s - auto-accept solo: %s - decline tent requests: %s"),
        st("on"), st("thank"), st2(d.reqAcceptSolo), st2(d.reqDecline))
        .. "\n" .. L(C .. " on|off · " .. C .. " thank on|off · " .. C .. " accept on|off 单人自动同意 · " .. C .. " decline on|off 拒绝蹭露营的 · " .. C .. " msg 求组话术 · " .. C .. " thanks 感谢话术 · " .. C .. " probe 探针",
            C .. " on|off · thank on|off · accept on|off · decline on|off · msg <text> · thanks <text> · probe"))
end
