-- 法师「阈限传送」（GI-280 第一期 11-16 / 第二期 11-20；用户实测后随无限 1.4.4 发布，只有法师角色加载）
--
-- 玩家吐槽：手里有「阈限通行卷轴」（传送到一个小队成员处，你和目标都必须正在旅店或城市中休息），
--   但要自己 /who 一个区一个区地找「正在目的地休息的人」，再密语、组队、用卷轴、退队，太麻烦。
-- 第二期（共建看板 GI-280「法师旅店传送，检索目标地点旅店或附近玩家」）：
--   · 目的地从「六座主城 + 四个地精小镇」扩到「所有有旅店的地区」（LiminalInnData.lua，45 个旅店老板），
--     选了地区 → 列出那里的旅店（旅店老板名 + 坐标 + 「地图」插旗），玩家知道卷轴能落到哪家旅店
--   · 「附近玩家」：点「找人」时先看公会 / 好友名单里谁正在那个地区（不用 /who、不限流），排在 /who 结果前面、标「公会」「好友」
--
-- ① 放在哪（11-20 用户新规「职业专属的只有这个职业才加载」）：法师专属子插件 GearInsight_Forever_ClassMage（按需加载、战斗中不加载）
--   · 主插件 ClassStub.lua 只在法师角色上放占位页 / 命令，非法师连占位都没有、这个子插件一个文件都不加载
--   · 文件头再挡一次（万一被别的插件 / 手动 LoadAddOn）：不是法师就直接 return，不建表不建框
--   · 里面有安全按钮（SecureActionButton type = item 用卷轴）→ noCombat：只在脱战时加载、建按钮
--   · 整个文件夹没进发行脚本的子插件清单（gi_forever_tocfiles.MODULES）= 发行包里没有它（HOLD）；_hold.txt 照规矩也登记了
--
-- ② 数据（⛔ 以游戏数据为准，别凭记忆）：
--   · 卷轴：物品 213548「阈限通行卷轴 / Scroll of Liminal Passage」，法术 434752「阈限通行」（客户端 1.60.1 Spell.db2：
--     「传送到一个小队成员处。你和目标都必须正在旅店或城市中休息。」）；法师专属、1 秒施法、一格叠 5 张、可交易
--   · 旅店：LiminalInnData.lua（scripts/gi_forever_liminal_inns.py：vmangos 旅店老板 + Questie 坐标，过 gi_forever_remap_coords 换算），经典旧世口径
--   · /who 的区域过滤认客户端本地化的区域名 → 先用 C_Map.GetMapInfo(uiMapID).name，拿不到再用数据里的中 / 英文名
--   · /who 结果里的区域是「大区」：野外旅店只能搜到整个地区，搜到的人不一定在旅店 —— 页上明说，让玩家密语时问一句
--
-- ③ 流程（每一步都要玩家自己点，插件不自动发任何东西）：
--   · 选目的地 →「找人」：先扫公会 / 好友名单（同区的列出来），再 C_FriendList.SendWho('z-"区域名"')（只在点击里发，硬件事件）；
--     搜的时候摘掉好友面板的 WHO_LIST_UPDATE，SetWhoToUi(true) 让结果走事件不刷聊天框，结果回来恢复
--   · 结果：名字 / 等级 / 职业 / 公会；去掉自己和已经在队里的人；/who 本来就只出同阵营
--   · 每行「请他帮传」：先密语一句客气话（⛔ 不带插件名），再邀请进队；同一个人 10 分钟内只能点一次（存档里记，/reload 也算）
--   · 他进队、我也在休息（IsResting）、背包里有卷轴 → 页上出「用阈限通行卷轴」安全按钮（type = item，脱战时建，进战斗状态驱动隐藏）
--   · 点了按钮 5 秒内施法成功（UNIT_SPELLCAST_SUCCEEDED，法术 id 用 C_Item.GetItemSpell 对；点了没放出去不算），
--     之后 2 分钟内、帮手还在队里时换了区 = 传送成功：密语一句谢谢；只有「这功能组起来的两人队」才自动退队
--   · 背包里没有卷轴：不去打扰别人
--
-- ④ 命令：/gi 阈限（/gi liminal）开页
local _, ns = ...; ns = _G.GearInsightForever or ns
if not ns or select(2, UnitClass("player")) ~= "MAGE" then return end

local LM = {}
ns.Liminal = LM
local function L(cn, en) return ns.L(cn, en) end

LM.ITEM = 213548          -- 阈限通行卷轴
LM.ASK_CD = 600           -- 同一个人多久内只能请一次（秒）
LM.WHO_TIMEOUT = 8        -- /who 结果多久没回来就放开（被限流 / 没发出去）
LM.DONE_WINDOW = 120      -- 用完卷轴多久内换区算传送成功
LM.ROWS = 10
LM.INN_ROWS = 3
LM.BTN = "GearInsightForeverLiminalUseBtn"

-- 主城（uiMapID → 阵营）：主城整座城都算休息区；页上快捷按钮排最前
LM.CITY = { [1453] = "Alliance", [1455] = "Alliance", [1457] = "Alliance", [1454] = "Horde", [1456] = "Horde", [1458] = "Horde" }
-- 快捷按钮：本阵营三座主城 + 四个中立地精小镇所在的地区（第一期的目的地，老玩家熟悉的落脚点）
LM.QUICK = { 1453, 1455, 1457, 1454, 1456, 1458, 1446, 1413, 1434, 1452 }
-- 中立小镇的旅店老板 → 镇名（第一期数据：这四个地区各只有这一位中立旅店老板）
LM.TOWN = { [7733] = { "加基森", "Gadgetzan" }, [6791] = { "棘齿城", "Ratchet" }, [6807] = { "藏宝海湾", "Booty Bay" }, [11118] = { "永望镇", "Everlook" } }
local FAC = { A = "Alliance", H = "Horde" }

-- ---------- 小工具 ----------
local function unsecret(v) if ns.Secret and ns.Secret(v) then return nil end return v end
local function call(f, ...) if not f then return nil end local ok, a, b, c = pcall(f, ...); if ok then return unsecret(a), unsecret(b), unsecret(c) end end
local function now() return GetTime and GetTime() or 0 end
local function wall() return time and time() or 0 end
local function combat() return InCombatLockdown and InCombatLockdown() and true or false end
local function short(name) return type(name) == "string" and (name:match("^([^%-]+)") or name) or nil end
LM.Short = short
local function inGroup() return IsInGroup ~= nil and call(IsInGroup) and true or false end
local function inRaid() return IsInRaid ~= nil and call(IsInRaid) and true or false end
local function members() return tonumber((call(GetNumGroupMembers))) or 0 end

function LM.IsMage() return ns.MyClass and ns.MyClass() == "Mage" end
function LM.Faction() local f = call(UnitFactionGroup, "player"); return f end
function LM.MyName() return short((call(UnitName, "player"))) end
function LM.MyZone() return call(GetRealZoneText) or call(GetZoneText) end
function LM.Resting() return IsResting ~= nil and call(IsResting) and true or false end
function LM.ScrollCount()
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    return tonumber((call(f, LM.ITEM))) or 0
end

function LM.DB()
    ns.db.liminal = type(ns.db.liminal) == "table" and ns.db.liminal or {}
    local d = ns.db.liminal
    if type(d.asked) ~= "table" then d.asked = {} end
    return d
end

-- ---------- 目的地 = 有旅店的地区 ----------
local DATA = ns.LiminalInnData or { inns = {}, zones = {} }
LM.BY_KEY = {}
-- 某阵营看得到的旅店：本阵营 + 中立
local function innOK(inn, fac) return inn[6] == "N" or FAC[inn[6]] == fac end
-- 这个地区里这个阵营能用的旅店 → { { ui, x, y, cn, en, fac, npc }, … }
function LM.Inns(ui, fac)
    fac = fac or LM.Faction()
    local out = {}
    for _, inn in ipairs(DATA.inns) do
        if inn[1] == ui and innOK(inn, fac) then out[#out + 1] = inn end
    end
    return out
end
local function dest(ui)
    local d = LM.BY_KEY[tostring(ui)]
    if d then return d end
    local z = DATA.zones[ui] or {}
    d = { key = tostring(ui), ui = ui, kind = LM.CITY[ui] and "city" or "zone", fac = LM.CITY[ui], cn = z[1] or tostring(ui), en = z[2] or tostring(ui) }
    LM.BY_KEY[d.key] = d
    return d
end
-- 本阵营能去的目的地：有本阵营 / 中立旅店的地区（敌对主城不列）；quick = 只要快捷按钮那几个（按 LM.QUICK 的顺序）
function LM.Dests(fac, quick)
    fac = fac or LM.Faction()
    local out, seen = {}, {}
    local function add(ui)
        if seen[ui] then return end
        if LM.CITY[ui] and LM.CITY[ui] ~= fac then return end
        if #LM.Inns(ui, fac) == 0 then return end
        seen[ui] = true
        out[#out + 1] = dest(ui)
    end
    for _, ui in ipairs(LM.QUICK) do add(ui) end
    if not quick then
        local rest = {}
        for _, inn in ipairs(DATA.inns) do if not seen[inn[1]] and innOK(inn, fac) then rest[inn[1]] = true end end
        local list = {}
        for ui in pairs(rest) do list[#list + 1] = ui end
        table.sort(list)
        for _, ui in ipairs(list) do add(ui) end
    end
    return out
end
function LM.DestName(d) return LM.ZoneName(d) end
-- 区域名：客户端自己的区域名优先（C_Map；/who 也认这个），拿不到再用数据里的中 / 英文
function LM.ZoneName(d)
    if C_Map and C_Map.GetMapInfo and d.ui then
        local ok, info = pcall(C_Map.GetMapInfo, d.ui)
        local n = ok and type(info) == "table" and unsecret(info.name) or nil
        if type(n) == "string" and n ~= "" then return n end
    end
    return L(d.cn, d.en)
end
function LM.WhoQuery(d) return 'z-"' .. LM.ZoneName(d) .. '"' end
-- 一家旅店的显示文字：旅店老板（中立小镇带镇名）+ 坐标
function LM.InnText(inn)
    local town = LM.TOWN[inn[7]]
    local n = L(inn[4], inn[5])
    if town then n = L(town[1], town[2]) .. " · " .. n end
    return string.format("%s  |cff9a9a9a%.1f, %.1f|r", n, inn[2], inn[3])
end
function LM.ShowInn(inn)
    if not (inn and ns.ShowOnMap) then return false end
    local ok = ns.ShowOnMap(inn[1], { { inn[2], inn[3] } }, L(inn[4], inn[5]))
    ns.Print(L("已在地图上插旗：", "Waypoint set: ") .. L(inn[4], inn[5]))
    return ok
end

-- ---------- 队伍 ----------
function LM.PartyNames()
    local t = {}
    for i = 1, 4 do
        local n = short((call(UnitName, "party" .. i)))
        if n then t[n] = true end
    end
    if inRaid() and GetRaidRosterInfo then
        for i = 1, members() do
            local n = short((call(GetRaidRosterInfo, i)))
            if n then t[n] = true end
        end
    end
    return t
end
function LM.InParty(name)
    local n = short(name)
    return n ~= nil and LM.PartyNames()[n] == true
end
-- 队友所在的区（GetRaidRosterInfo 第 7 个返回值；小队里也能用）
function LM.MemberZone(name)
    local n = short(name)
    if not (n and GetRaidRosterInfo) then return nil end
    for i = 1, math.max(members(), 5) do
        local ok, rn, _, _, _, _, _, zone = pcall(GetRaidRosterInfo, i)
        if ok and short(unsecret(rn)) == n then return unsecret(zone) end
    end
    return nil
end

-- ---------- 公会 / 好友里正在目的地的人（不用 /who）----------
-- → { { name, lv, cls, zone, tag = "guild" / "friend" }, … }；同一个人既是公会又是好友只列一次（公会优先）
function LM.Known(zone)
    local out, seen = {}, {}
    if type(zone) ~= "string" or zone == "" then return out end
    local function add(name, lv, cls, z, tag)
        if type(name) == "string" and name ~= "" and z == zone and not seen[short(name)] then
            seen[short(name)] = true
            out[#out + 1] = { name = name, lv = tonumber(lv), cls = cls, zone = z, tag = tag }
        end
    end
    if IsInGuild and call(IsInGuild) and GetGuildRosterInfo then
        for i = 1, tonumber((call(GetNumGuildMembers))) or 0 do
            local ok, name, _, _, lv, cls, z, _, _, online = pcall(GetGuildRosterInfo, i)
            if ok and unsecret(online) then add(unsecret(name), unsecret(lv), unsecret(cls), unsecret(z), "guild") end
        end
    end
    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        for i = 1, tonumber((call(C_FriendList.GetNumFriends))) or 0 do
            local ok, f = pcall(C_FriendList.GetFriendInfoByIndex, i)
            if ok and type(f) == "table" and unsecret(f.connected) then add(unsecret(f.name), unsecret(f.level), unsecret(f.className), unsecret(f.area), "friend") end
        end
    end
    return out
end

-- ---------- /who ----------
local function friendsWho(mute)
    local f = FriendsFrame
    if not (f and f.UnregisterEvent) then return end
    pcall(function()
        if mute then
            LM._friendsHad = not f.IsEventRegistered or f:IsEventRegistered("WHO_LIST_UPDATE") and true or false
            f:UnregisterEvent("WHO_LIST_UPDATE")
        elseif LM._friendsHad then
            f:RegisterEvent("WHO_LIST_UPDATE")
        end
    end)
end
local function whoToUi(on)
    if C_FriendList and C_FriendList.SetWhoToUi then pcall(C_FriendList.SetWhoToUi, on)
    elseif SetWhoToUI then pcall(SetWhoToUI, on and 1 or 0) end
end

-- 第 i 条结果 → 名字, 公会, 等级, 职业, 区域（保密值当没有）
function LM.WhoInfo(i)
    if C_FriendList and C_FriendList.GetWhoInfo then
        local ok, t = pcall(C_FriendList.GetWhoInfo, i)
        if ok and type(t) == "table" then
            return unsecret(t.fullName), unsecret(t.fullGuildName), unsecret(t.level), unsecret(t.classStr), unsecret(t.area)
        end
        return nil
    end
    if GetWhoInfo then
        local ok, name, guild, lv, _, cls, zone = pcall(GetWhoInfo, i)
        if ok then return unsecret(name), unsecret(guild), unsecret(lv), unsecret(cls), unsecret(zone) end
    end
    return nil
end

-- 原始结果 → 能请的人：去掉没名字的、自己、已经在队里的、重复的（公会 / 好友已列过的排前面）
function LM.FilterRows(raw)
    local me, party, out, seen = LM.MyName(), LM.PartyNames(), {}, {}
    for _, r in ipairs(raw) do
        local n = short(r.name)
        if type(r.name) == "string" and r.name ~= "" and n ~= me and not party[n] and not seen[n] then
            seen[n] = true
            out[#out + 1] = r
        end
    end
    return out
end

-- 「找人」：只在点击里调（SendWho 要硬件事件）→ true / false, 原因
function LM.Find(key)
    if not LM.IsMage() then return false, "class" end
    local d = LM.BY_KEY[key or LM.dest or ""]
    if not d then return false, "nodest" end
    if LM.searching and now() - (LM.searchAt or 0) < LM.WHO_TIMEOUT then return false, "busy" end
    LM.dest = d.key
    -- 先把公会 / 好友里正在那儿的人列出来（/who 被限流也有东西看）
    LM.known = LM.Known(LM.ZoneName(d))
    LM.results, LM.resultDest = LM.FilterRows(LM.known), d.key
    local send = (C_FriendList and C_FriendList.SendWho) or SendWho
    if not send then LM.Paint(); return false, "noapi" end
    LM.searching, LM.searchAt, LM.searchDest = true, now(), d.key
    friendsWho(true)
    whoToUi(true)
    local ok = pcall(send, LM.WhoQuery(d))
    if not ok then LM.searching = false; friendsWho(false); whoToUi(false); LM.Paint(); return false, "noapi" end
    LM.Paint()
    return true
end

function LM.OnWho()
    if not LM.searching then return end
    LM.searching = false
    friendsWho(false)
    whoToUi(false)
    local n = tonumber((call((C_FriendList and C_FriendList.GetNumWhoResults) or GetNumWhoResults))) or 0
    local raw = {}
    for _, k in ipairs(LM.known or {}) do raw[#raw + 1] = k end
    for i = 1, n do
        local name, guild, lv, cls, zone = LM.WhoInfo(i)
        if name then raw[#raw + 1] = { name = name, guild = guild, lv = tonumber(lv), cls = cls, zone = zone } end
    end
    LM.results = LM.FilterRows(raw)
    LM.resultDest, LM.resultRaw = LM.searchDest, n
    LM.Paint()
end

-- ---------- 请人帮传 ----------
-- 11-19 密给别人的：走对外说话语言（ns.ChatL）
function LM.AskText()
    return ns.ChatL("打扰下，刚给你发了个组队邀请，能接一下吗？我用法师卷轴传到你身边（要你在旅店或主城里），传完马上退队，谢谢~",
        "Hi, sorry to bother you - I just sent you a group invite. Could you accept? I'll use a mage scroll to teleport to you (you need to be in an inn or a city), then leave right away. Thanks!")
end
function LM.ThanksText() return ns.ChatL("到了，谢谢你帮忙！", "Made it - thank you so much!") end

-- 这个人还要等多少秒才能再请（0 = 现在能请）
function LM.AskWait(name)
    local at = tonumber(LM.DB().asked[name or ""])
    if not at then return 0 end
    local left = LM.ASK_CD - (wall() - at)
    return left > 0 and math.ceil(left) or 0
end
local function pruneAsked()
    local a = LM.DB().asked
    for k, at in pairs(a) do if not tonumber(at) or wall() - at >= LM.ASK_CD then a[k] = nil end end
end

local function whisper(msg, to)
    local f = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not (f and to) then return false end
    return pcall(f, msg, "WHISPER", nil, to) and true or false
end

-- 「请他帮传」：只在点击里调 → true / false, 原因
function LM.Ask(name)
    if not LM.IsMage() then return false, "class" end
    if type(name) ~= "string" or name == "" then return false, "noname" end
    if LM.ScrollCount() <= 0 then
        ns.Print(L("背包里没有阈限通行卷轴，先别打扰人家了（卷轴是法师用理解技能解译未翻译的卷轴得到的）",
            "You have no Scroll of Liminal Passage in your bags - no point asking anyone yet"))
        return false, "noscroll"
    end
    local wait = LM.AskWait(name)
    if wait > 0 then
        ns.Print(string.format(L("刚请过 %s，%d 分钟后才能再请（别刷屏打扰人家）", "You already asked %s - wait %d min before asking again"), name, math.ceil(wait / 60)))
        return false, "cooldown"
    end
    if inRaid() or members() >= 5 then
        ns.Print(L("你在团队 / 满员队伍里，邀请不了别人", "You're in a raid or a full group - can't invite"))
        return false, "full"
    end
    pruneAsked()
    LM.DB().asked[name] = wall()
    local formed = not inGroup()
    whisper(LM.AskText(), name)
    local inv = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if inv then pcall(inv, name) end
    LM.helper = { name = name, at = now(), formed = formed, dest = LM.resultDest or LM.dest }
    LM.used, LM.thanked = nil, nil
    ns.Print(string.format(L("已密语并邀请 %s。他进队后，你站在旅店 / 主城里，页上会出「用阈限通行卷轴」按钮",
        "Whispered and invited %s. Once they join and you're resting in an inn or city, the \"Use scroll\" button appears"), name))
    LM.Paint()
    return true
end

-- ---------- 用卷轴 ----------
-- 能不能用：→ true / false, 原因（nohelper 没请人 / notparty 他还没进队 / notresting 我没在休息 / noscroll 没卷轴 / combat 战斗中）
function LM.CanUse()
    local h = LM.helper
    if not h then return false, "nohelper" end
    if not LM.InParty(h.name) then return false, "notparty" end
    if LM.ScrollCount() <= 0 then return false, "noscroll" end
    if not LM.Resting() then return false, "notresting" end
    if combat() then return false, "combat" end
    return true
end

local WHY = {
    nohelper = { "先选目的地 → 找人 → 请一个人帮传", "Pick a destination, find someone, and ask them" },
    notparty = { "等对方接受组队邀请……", "Waiting for them to accept the invite..." },
    noscroll = { "背包里没有阈限通行卷轴", "No Scroll of Liminal Passage in your bags" },
    notresting = { "你得先在旅店或主城里休息（头像旁有 zzz）才能用卷轴", "You must be resting in an inn or city to use the scroll" },
    combat = { "战斗中不能用", "Can't use in combat" },
}
function LM.WhyText(why) local w = WHY[why or ""]; return w and L(w[1], w[2]) or "" end

-- 卷轴的法术 id（C_Item.GetItemSpell；拿不到 = nil，那就认「点完 5 秒内我施放成功的任一法术」）
function LM.ScrollSpell()
    local f = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    local _, id = call(f, LM.ITEM)
    return tonumber(id)
end
-- 施法成功：点过按钮、5 秒内、法术对得上 → 记下「卷轴真放出去了」
function LM.OnCast(spellID)
    local u = LM.used
    if not u or u.cast or now() - u.at > 5 then return end
    local want = LM.ScrollSpell()
    if want and tonumber(spellID) ~= want then return end
    u.cast = now()
end

-- 传送成功了吗（换区时调）：卷轴放出去了、2 分钟内、帮手还在队里，而且换到了别的区（用卷轴时区名没拿到 = 新区和帮手所在区一样）
function LM.Teleported()
    local u, h = LM.used, LM.helper
    if not (u and u.cast and h) then return false end
    if now() - u.cast > LM.DONE_WINDOW then return false end
    if not LM.InParty(h.name) then return false end
    local z = LM.MyZone()
    if not z then return false end
    if u.zone then return z ~= u.zone end
    local hz = LM.MemberZone(h.name)
    return hz ~= nil and hz == z
end

-- 传完要不要自动退队：只有这功能组起来的队、现在就我和帮手两个人
function LM.ShouldLeave()
    local h = LM.helper
    if not (h and h.formed) then return false end
    if not inGroup() or inRaid() then return false end
    if members() ~= 2 then return false end
    return LM.InParty(h.name)
end

function LM.Finish()
    local h = LM.helper
    if not h then return false end
    if not LM.thanked then
        LM.thanked = true
        whisper(LM.ThanksText(), h.name)
    end
    local left = false
    if LM.ShouldLeave() then
        local f = (C_PartyInfo and C_PartyInfo.LeaveParty) or LeaveParty
        if f then left = pcall(f) and true or false end
    end
    ns.Print(left and string.format(L("阈限传送成功，已谢过 %s 并退队", "Teleported - thanked %s and left the group"), h.name)
        or string.format(L("阈限传送成功，已谢过 %s（队伍不是这里组的 / 不止两个人，没帮你退队）", "Teleported - thanked %s (group kept: not formed here or more than 2 people)"), h.name))
    LM.helper, LM.used = nil, nil
    LM.Paint()
    return true, left
end

function LM.OnZone()
    if LM.Teleported() then LM.Finish() end
end

-- ---------- 安全按钮（脱战时建，挂 UIParent，贴到页上占位格；同 PallyBless.lua）----------
local pages, page = {}, nil
local function curPage()
    for i = #pages, 1, -1 do
        local q = pages[i]
        if q and q.IsVisible and q:IsVisible() then return q end
    end
    return page
end
LM._curPage = curPage

function LM.BuildBtn()
    if LM.btn or combat() then return LM.btn end
    local b = CreateFrame("Button", LM.BTN, UIParent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    b:SetSize(200, 26)
    if b.RegisterForClicks then b:RegisterForClicks("AnyDown") end
    b:SetAttribute("type", "item")
    b:SetAttribute("item", "item:" .. LM.ITEM)
    if RegisterStateDriver and b.SetAttribute then
        -- 进战斗：受保护代码里隐藏（插件代码战斗中不碰安全按钮）；脱战后插件再按条件显示
        b:SetAttribute("_onstate-gilmcombat", [[ if newstate == "1" then self:Hide() end ]])
        RegisterStateDriver(b, "gilmcombat", "[combat] 1; 0")
    end
    if ns.SkinButton then ns.SkinButton(b) end
    b:SetText(L("用阈限通行卷轴", "Use Liminal scroll"))
    b:SetScript("PostClick", function()
        if combat() then return end
        LM.used = { at = now(), zone = LM.MyZone() }
    end)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L("阈限通行卷轴", "Scroll of Liminal Passage"), 1, 0.82, 0)
        GameTooltip:AddLine(L("传送到小队成员处；你和他都要在旅店或主城里休息。传到后插件自动谢谢他，这里组的两人队会自动退队",
            "Teleports you to a party member; both of you must be resting. On arrival: auto thanks, and leaves a 2-person group formed here"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:Hide()
    LM.btn = b
    return b
end

-- 按钮跟着条件显示 / 隐藏（只在脱战时动）
function LM.UpdateBtn()
    if combat() then return end
    local p = curPage()
    local can = LM.CanUse()
    local show = can and p ~= nil and p.slot ~= nil and p.slot.IsVisible ~= nil and p.slot:IsVisible()
    if show and not LM.btn then LM.BuildBtn() end
    local b = LM.btn
    if not b then return end
    if show then
        b:ClearAllPoints(); b:SetAllPoints(p.slot)
        if p.slot.GetFrameStrata then b:SetFrameStrata(p.slot:GetFrameStrata()) end
        if p.slot.GetFrameLevel then b:SetFrameLevel((p.slot:GetFrameLevel() or 0) + 5) end
        b:Show()
    else
        b:Hide()
    end
end
LM.ButtonShown = function() return LM.btn ~= nil and LM.btn:IsShown() and true or false end

-- ---------- 页 ----------
local TAG = { guild = { "|cff40ff40公会|r ", "|cff40ff40Guild|r " }, friend = { "|cff66bbff好友|r ", "|cff66bbffFriend|r " } }
local function rowText(r)
    local lv = r.lv and tostring(r.lv) or "?"
    local g = (type(r.guild) == "string" and r.guild ~= "") and ("<" .. r.guild .. ">") or ""
    local t = TAG[r.tag or ""]
    return string.format("%s%s  |cff9a9a9a%s %s|r  %s", t and L(t[1], t[2]) or "", r.name, lv, r.cls or "", g)
end

function LM.StatusText()
    if not LM.IsMage() then return L("阈限传送只给法师用", "Liminal teleport is for mages") end
    local cnt = LM.ScrollCount()
    local s = cnt > 0 and string.format(L("背包里有 %d 张阈限通行卷轴", "%d Liminal scroll(s) in bags"), cnt)
        or ("|cffff6060" .. L("背包里没有阈限通行卷轴", "No Liminal scroll in bags") .. "|r")
    if LM.searching then return s .. "　" .. L("正在找人……", "Searching...") end
    local h = LM.helper
    if h then
        local ok, why = LM.CanUse()
        if ok then return s .. "　" .. string.format(L("%s 已进队，点「用阈限通行卷轴」", "%s joined - click \"Use Liminal scroll\""), h.name) end
        return s .. "　" .. string.format(L("帮手：%s · %s", "Helper: %s - %s"), h.name, LM.WhyText(why))
    end
    return s
end

-- 「更多旅店」下拉：快捷按钮以外、本阵营能去的地区（每个地区几家旅店）
function LM.MoreItems()
    local items, quick = {}, {}
    for _, d in ipairs(LM.Dests(nil, true)) do quick[d.key] = true end
    for _, d in ipairs(LM.Dests()) do
        if not quick[d.key] then
            local k = d.key
            items[#items + 1] = { text = string.format("%s  |cff9a9a9a%d|r", LM.DestName(d), #LM.Inns(d.ui)), fn = function() LM.dest = k; LM.Paint() end }
        end
    end
    return items
end

function LM.Paint()
    local p = curPage()
    if not (p and p.status) then return end
    p.status:SetText(LM.StatusText())
    local dests = LM.Dests(nil, true)
    for i, b in ipairs(p.dests) do
        local d = dests[i]
        if d then
            b:SetText(LM.DestName(d))
            rawset(b, "lmKey", d.key)
            if ns.SegSelect then ns.SegSelect(b, LM.dest == d.key) end
            b:Show()
        else
            b:Hide()
        end
    end
    local d = LM.BY_KEY[LM.dest or ""]
    local isQuick = false
    for _, q in ipairs(dests) do if d and q.key == d.key then isQuick = true end end
    p.more:SetText((d and not isQuick) and (LM.DestName(d) .. " …") or L("更多旅店 …", "More inns …"))
    if ns.SegSelect then ns.SegSelect(p.more, d ~= nil and not isQuick) end
    p.find:SetText(d and string.format(L("找人：%s", "Find: %s"), LM.DestName(d)) or L("先选目的地", "Pick a destination"))
    -- 这里的旅店
    local inns = d and LM.Inns(d.ui) or {}
    for i, r in ipairs(p.inns) do
        local inn = inns[i]
        if inn then
            r.t:SetText(LM.InnText(inn))
            rawset(r.map, "lmInn", inn)
            r:Show()
        else
            r:Hide()
        end
    end
    if not d then
        p.innHd:SetText(L("选一个目的地：下面会列出那里的旅店（卷轴落到帮手身边，帮手得在旅店或主城里）", "Pick a destination to see its inns"))
    else
        p.innHd:SetText(string.format(L("%s 的旅店（%d 家%s）", "Inns in %s (%d%s)"), LM.DestName(d), #inns,
            #inns > LM.INN_ROWS and string.format(L("，只列前 %d 家", ", first %d shown"), LM.INN_ROWS) or ""))
    end
    local rows = LM.results or {}
    local rd = LM.BY_KEY[LM.resultDest or ""]
    if LM.results == nil then
        p.head:SetText(L("选好目的地点「找人」：先列公会 / 好友里正在那儿的人，再 /who 找同阵营玩家", "Pick a destination and click Find: guild / friends there first, then /who"))
    elseif #rows == 0 then
        p.head:SetText(string.format(L("%s：%s", "%s: %s"), rd and LM.DestName(rd) or "?",
            LM.searching and L("公会 / 好友里没人在那儿，正在 /who……", "no guildmates / friends there, running /who...")
            or L("没找到能请的人（换个目的地，或过一会儿再找）", "nobody to ask (try another place or later)")))
    else
        local kn = 0
        for _, x in ipairs(rows) do if x.tag then kn = kn + 1 end end
        p.head:SetText(string.format(L("%s：找到 %d 人", "%s: %d found"), rd and LM.DestName(rd) or "?", #rows)
            .. (kn > 0 and string.format(L("（公会 / 好友 %d）", " (guild / friends %d)"), kn) or ""))
    end
    for i, r in ipairs(p.rows) do
        local x = rows[i]
        if x then
            r.name:SetText(rowText(x))
            r.zone:SetText(x.zone or "")
            rawset(r.ask, "lmName", x.name)
            local wait = LM.AskWait(x.name)
            if wait > 0 then
                r.ask:SetText(string.format(L("已请过（%d 分）", "Asked (%dm)"), math.ceil(wait / 60)))
                r.ask:Disable()
            else
                r.ask:SetText(L("请他帮传", "Ask"))
                r.ask:Enable()
            end
            r:Show()
        else
            r:Hide()
        end
    end
    p.over:SetText(#rows > LM.ROWS and string.format(L("还有 %d 人没列出", "%d more not shown"), #rows - LM.ROWS) or "")
    local src = L("旅店位置是经典旧世数据，《无限》可能有调整。", "Inn spots are classic-era data and may differ in Forever. ")
    if rd and rd.kind ~= "city" then
        p.note:SetText(src .. string.format(L("/who 按整个%s搜，对方不一定在旅店 —— 密语时问一句；对方也得在旅店里休息卷轴才能用",
            "/who searches all of %s; they may not be at an inn - ask when you whisper"), LM.DestName(rd)))
    else
        p.note:SetText(src .. L("对方也得在旅店或主城里休息，卷轴才能用", "They must also be resting in an inn or city"))
    end
    LM.UpdateBtn()
end

local function build(p)
    page = p
    pages[#pages + 1] = p
    local y0 = ns.PageHeader(p, L("阈限传送", "Liminal teleport"), L("法师 · 找正在目的地旅店休息的人，请他组你，用阈限通行卷轴传过去", "Mage - find someone resting at your destination's inn and teleport to them"))
    y0 = y0 or -44
    p.dests = {}
    for i = 1, 7 do
        local b = ns.Button(p, "", 88, 22, nil)
        b:SetPoint("TOPLEFT", 12 + (i - 1) * 90, y0)
        b:SetScript("OnClick", function(self) LM.dest = rawget(self, "lmKey"); LM.Paint() end)
        p.dests[i] = b
    end
    p.more = ns.Button(p, "", 110, 22, function(self)
        local items = LM.MoreItems()
        if ns.PopMenu and #items > 0 then ns.PopMenu(self, L("其他有旅店的地区", "Other zones with inns"), items) end
    end)
    p.more:SetPoint("TOPLEFT", 12 + 7 * 90, y0)
    p.find = ns.Button(p, "", 180, 24, function() local ok, why = LM.Find(); if not ok and why == "nodest" then ns.Print(L("先点一个目的地", "Pick a destination first")) end end)
    p.find:SetPoint("TOPLEFT", 12, y0 - 30)
    p.slot = CreateFrame("Frame", nil, p)
    p.slot:SetSize(200, 26); p.slot:SetPoint("LEFT", p.find, "RIGHT", 12, 0)
    p.innHd = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.innHd:SetPoint("TOPLEFT", 14, y0 - 60); p.innHd:SetPoint("RIGHT", p, "RIGHT", -12, 0); p.innHd:SetJustifyH("LEFT")
    p.inns = {}
    for i = 1, LM.INN_ROWS do
        local r = CreateFrame("Frame", nil, p)
        r:SetHeight(18)
        r:SetPoint("TOPLEFT", 20, y0 - 76 - (i - 1) * 19); r:SetPoint("RIGHT", p, "RIGHT", -12, 0)
        r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.t:SetPoint("LEFT", 0, 0); r.t:SetWidth(420); r.t:SetJustifyH("LEFT")
        r.map = ns.Button(r, L("地图", "Map"), 60, 18, function(self) LM.ShowInn(rawget(self, "lmInn")) end)
        r.map:SetPoint("LEFT", 426, 0)
        r:Hide()
        p.inns[i] = r
    end
    local y1 = y0 - 76 - LM.INN_ROWS * 19 - 4
    p.status = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.status:SetPoint("TOPLEFT", 14, y1); p.status:SetPoint("RIGHT", p, "RIGHT", -12, 0); p.status:SetJustifyH("LEFT")
    p.head = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.head:SetPoint("TOPLEFT", 14, y1 - 22); p.head:SetPoint("RIGHT", p, "RIGHT", -12, 0); p.head:SetJustifyH("LEFT")
    p.rows = {}
    for i = 1, LM.ROWS do
        local r = CreateFrame("Frame", nil, p)
        r:SetHeight(22)
        r:SetPoint("TOPLEFT", 12, y1 - 42 - (i - 1) * 23); r:SetPoint("RIGHT", p, "RIGHT", -12, 0)
        local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.06)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.name:SetPoint("LEFT", 4, 0); r.name:SetWidth(330); r.name:SetJustifyH("LEFT")
        r.zone = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); r.zone:SetPoint("LEFT", 340, 0); r.zone:SetWidth(120); r.zone:SetJustifyH("LEFT")
        r.ask = ns.Button(r, L("请他帮传", "Ask"), 110, 20, function(self)
            LM.Ask(rawget(self, "lmName"))
            LM.Paint()
        end)
        r.ask:SetPoint("RIGHT", -2, 0)
        r:Hide()
        p.rows[i] = r
    end
    local y2 = y1 - 42 - LM.ROWS * 23
    p.over = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); p.over:SetPoint("TOPLEFT", 14, y2 - 2)
    p.note = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.note:SetPoint("TOPLEFT", 14, y2 - 18); p.note:SetPoint("RIGHT", p, "RIGHT", -14, 0); p.note:SetJustifyH("LEFT")
    if p.slot.HookScript then
        p.slot:HookScript("OnHide", function() if LM.btn and not combat() then LM.btn:Hide() end end)
    end
    if p.HookScript then p:HookScript("OnShow", function() LM.Paint() end) end
    LM.Paint()
end
LM._build = build

-- ---------- 事件 ----------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "WHO_LIST_UPDATE", "GROUP_ROSTER_UPDATE", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_UPDATE_RESTING",
    "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UNIT_SPELLCAST_SUCCEEDED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
function LM.OnEvent(e, a1, a2, a3)
    if not (ns.db and LM.IsMage()) then return end
    if e == "UNIT_SPELLCAST_SUCCEEDED" then
        if a1 == "player" then LM.OnCast(a3 or a2) end
    elseif e == "WHO_LIST_UPDATE" then
        LM.OnWho()
    elseif e == "ZONE_CHANGED_NEW_AREA" or e == "PLAYER_ENTERING_WORLD" then
        LM.OnZone()
        LM.Paint()
    elseif e == "GROUP_ROSTER_UPDATE" then
        local h = LM.helper
        if h then
            if LM.InParty(h.name) then
                if not h.joined then
                    h.joined = true
                    ns.Print(string.format(L("%s 进队了。站在旅店 / 主城里（休息状态），点页上的「用阈限通行卷轴」", "%s joined. Rest in an inn or city, then click \"Use Liminal scroll\""), h.name))
                end
            elseif h.joined then
                LM.helper, LM.used = nil, nil   -- 他进过队又走了：这次作废
            end
        end
        LM.Paint()
    elseif e == "PLAYER_REGEN_DISABLED" then
        -- 进战斗前最后一刻：安全按钮先藏起来（状态驱动也会藏，这里只是让主面板别被它带成受保护）
        if LM.btn then LM.btn:Hide() end
    else
        LM.Paint()
    end
end
ev:SetScript("OnEvent", function(_, e, ...) pcall(LM.OnEvent, e, ...) end)
-- /who 一直没回来（被限流 / 没发出去）：超时放开，恢复好友面板，下次点击可以重搜（公会 / 好友那几个人照样留着）
local acc = 0
ev:SetScript("OnUpdate", function(_, el)
    acc = acc + (el or 0)
    if acc < 1 then return end
    acc = 0
    if LM.searching and now() - (LM.searchAt or 0) > LM.WHO_TIMEOUT then
        LM.searching = false
        friendsWho(false); whoToUi(false)
        LM.results, LM.resultDest = LM.results or {}, LM.searchDest
        pcall(LM.Paint)
    end
end)
LM._ev = ev

-- ---------- 页 / 命令 ----------
ns.RegisterPage({ key = "liminal", order = 1.48, class = "Mage", title = ns.L("阈限传送", "Liminal teleport"),
    build = build, refresh = function() LM.Paint() end })

ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash["阈限"] = function()
    if ns.ToggleMain then ns.ToggleMain("liminal") end
end
ns.ExtraSlash.liminal = ns.ExtraSlash["阈限"]

-- 子插件就绪标记（ClassStub.lua 的 LazyModule key = "cmage"）
ns._modReady = ns._modReady or {}
ns._modReady.cmage = true
