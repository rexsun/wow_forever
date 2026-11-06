-- HOLD：升级播报（10-16 用户截图别家插件在公会频道发「我刚刚从 4 级升到了 5 级，在 18 分钟 52 秒内」：
--   「这个做一下，默认打开，然后我们可以记录更多的一些信息……目的是传播作用」）
-- ① 升级后在公会频道发一句（插件发公会频道不需要点击）：前缀「[GearInsight插件]」+ 本级用时 + 一个让人想问的数据点
--    10-17 定稿：「升到 N 级，用时 X（扣挂机），」+ 一句战绩（死亡+凶手 / 杀怪+最常杀的怪 / 零死亡）；⛔不和公测玩家比（用户：数据不准、不需要）
--    10 / 20 / 30 / 40 / 50 级换里程碑句（1 到 N 级游戏时长），60 级「满级了」。1-5 级不发（新手村刷屏）；同一级只发一次
--    频率：every 每级 / five 每 5 级 / milestone 只在 10·20·…·60（10-26 起默认）/ off；/gi 升级播报 开|关|每5级|里程碑
-- ② 每级多记一点（只记自己的，不记任何人名字）：用时、地图、死亡 / 交任务 / 杀怪数、组队时长占比、有没有休息经验、在不在休息区、累计游戏时长
--    存 GearInsightForeverDB.lvlx[cid][等级]；导出时进 /gi data 的 GIFS1 文档 lx 字段（Stats.lua 里 ns.LevelShareExportDoc，向后兼容）
-- ⛔ 不在公会不发；关了不发；全部 pcall；只靠事件计数，不加 OnUpdate
local _, ns = ...; ns = _G.GearInsightForever or ns  -- 10-19 用户「拿到主插件，不要放子插件了」：搬回主插件，登录就跑（不用先点公会页签）；这行在主插件里也成立

local LS = {}
ns.LevelShare = LS

local MODES = { every = true, five = true, milestone = true, off = true }
local MIN_LEVEL = 6          -- 1-5 级不发
local WAIT_PLAYED = 6        -- 秒：等 TIME_PLAYED_MSG 回来，再晚就不带用时发
local MAX_PER_CHAR = 70

local function db()
    local d = ns.db
    -- 10-26 玩家「公会里全是各家插件升级提醒」，用户「改成默认只在里程碑发」：默认 every → milestone。
    --   旧存档里的 "every" 是当初自动写进去的默认值，分不出是不是玩家自己选的 → 一次性迁到 milestone（lvlShareV=2 记已迁）
    if d.lvlShare == nil then d.lvlShare = "milestone" end
    if d.lvlShareV == nil then
        if d.lvlShare == "every" then d.lvlShare = "milestone" end
        d.lvlShareV = 2
    end
    d.lvlx = d.lvlx or {}
    d.lvlCur = d.lvlCur or {}
    return d
end

local function now() return (GetTime and GetTime()) or 0 end

local function cid()
    local c = ns.CurrentChar and ns.CurrentChar()
    return c and c.cid
end

-- 本级计数器（按角色）
local function cur()
    local id = cid()
    if not id then return nil end
    local d = db()
    local c = d.lvlCur[id]
    local lvl = (UnitLevel and UnitLevel("player")) or 0
    if not c or c.lvl ~= lvl then
        c = { lvl = lvl, dead = 0, quests = 0, kills = 0, grp = 0, afk = 0, mobs = {} }
        d.lvlCur[id] = c
    end
    return c, id
end

-- ---------- 组队时长（本次登录内，按事件记时间点）----------
local grpSince = nil
local function inGroup() return ((GetNumGroupMembers and GetNumGroupMembers()) or 0) > 1 end
local function grpTick()
    local c = cur()
    if not c then return end
    if grpSince then c.grp = (c.grp or 0) + (now() - grpSince); grpSince = nil end
    if inGroup() then grpSince = now() end
end

-- ---------- 话术 ----------
local function fmtDur(sec)
    sec = math.floor(sec or 0)
    local d, h, m, s = math.floor(sec / 86400), math.floor(sec % 86400 / 3600), math.floor(sec % 3600 / 60), sec % 60
    if d > 0 then return string.format(ns.L("%d 天 %d 小时 %d 分", "%dd %dh %dm"), d, h, m) end
    if h > 0 then return string.format(ns.L("%d 小时 %d 分", "%dh %dm"), h, m) end
    return string.format(ns.L("%d 分 %d 秒", "%dm %ds"), m, s)
end
local function thousands(n)
    local s = tostring(math.floor(n + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end
LS.FmtDur = fmtDur

-- 播报里的用时：短（「38 分」「1 小时 2 分」），不带秒
local function fmtShort(sec)
    sec = math.floor(sec or 0)
    if sec < 60 then return string.format(ns.L("%d 秒", "%ds"), sec) end
    local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
    if h > 0 then return string.format(ns.L("%d 小时 %d 分", "%dh %dm"), h, m) end
    return string.format(ns.L("%d 分", "%dm"), m)
end
LS.FmtShort = fmtShort

-- 挂机：/afk 标记期间 + 自动挂机前那 5 分钟不算（游戏没动 5 分钟才自动挂 AFK）
local AFK_LEAD = 300
local afkSince = nil
local function afkTick()
    local c = cur()
    local isAfk = UnitIsAFK and UnitIsAFK("player")
    if isAfk and not afkSince then
        afkSince = now()
    elseif not isAfk and afkSince then
        if c then c.afk = (c.afk or 0) + (now() - afkSince) + AFK_LEAD end
        afkSince = nil
    end
end

-- 杀怪经验那句里取怪名：「迪菲亚劳工死亡，你获得了 45 点经验」/「Defias Laborer dies, you gain 45 experience」
function LS.MobFromXP(s)
    if type(s) ~= "string" or (ns.Secret and ns.Secret(s)) then return nil end
    local n = s:match("^(.-)死亡") or s:match("^(.-)死去") or s:match("^(.-) dies")
    if n and n ~= "" and #n <= 60 then return n end
    return nil
end

-- 这一级的凶手：Stats.lua 的死亡记录里同角色、同等级的（列表导出后会被清，只是尽力而为）
local function killersOf(id, lvl)
    local out, n = {}, 0
    for _, r in ipairs((ns.db and ns.db.deaths) or {}) do
        if r.cid == id and r.lvl == lvl and r.kk == "npc" and type(r.kn) == "string" and r.kn ~= "" then
            out[r.kn] = (out[r.kn] or 0) + 1; n = n + 1
        end
    end
    return out, n
end

-- 一句战绩（用户 10-17 选：死亡 / 零死亡 + 凶手；杀怪 + 最常杀的怪）
--   死过 → 死亡句；没死 → 杀怪句（「砍了 86 只怪，31 只是迪菲亚劳工」/「砍了 86 只怪，零死亡」轮着出）
function LS.StatLine(rec, rot)
    local dead, kills = rec.dead or 0, rec.kills or 0
    if dead > 0 then
        local top, topN = nil, 0
        local total = 0
        for k, v in pairs(rec.killers or {}) do total = total + v; if v > topN then top, topN = k, v end end
        if top and topN == dead then
            if dead == 1 then return string.format(ns.L("死了 1 次，栽在%s手里", "died once, to %s"), top) end
            return string.format(ns.L("死了 %d 次，都栽在%s手里", "died %d times, all to %s"), dead, top)
        end
        return string.format(ns.L("死了 %d 次", "died %d times"), dead)
    end
    if kills >= 5 then
        local top, topN = nil, 0
        for k, v in pairs(rec.mobs or {}) do if v > topN then top, topN = k, v end end
        if top and topN >= 3 and ((rot or 0) % 2 == 0) then
            return string.format(ns.L("砍了 %d 只怪，%d 只是%s", "%d kills, %d of them %s"), kills, topN, top)
        end
        return string.format(ns.L("砍了 %d 只怪，零死亡", "%d kills, no deaths"), kills)
    end
    return ns.L("零死亡", "no deaths")
end

-- 这一级要不要发
function LS.ShouldShare(lvl, mode)
    mode = mode or db().lvlShare
    if mode == "off" or not lvl or lvl < MIN_LEVEL then return false end
    if mode == "five" then return lvl % 5 == 0 end
    if mode == "milestone" then return lvl % 10 == 0 end
    return true
end

-- 公会等级排名（10-17 用户「算一下当前公会等级排名，到了满级就说第几个到满级的」）
--   用游戏自带的公会名单（含离线成员、小号），不靠插件互相同步；自己不算在内，按刚升到的等级比。
--   返回 { rank = 比我高的人数 + 1, tie = 同级的人数, atMax = 已经满级的人数, n = 名单人数 }；名单没拿到 / 只有自己 → nil
function LS.GuildRank(lvl)
    if not (IsInGuild and IsInGuild()) or not GetNumGuildMembers or not GetGuildRosterInfo then return nil end
    local ok, total = pcall(GetNumGuildMembers)
    total = ok and tonumber(total) or 0
    if total < 2 then return nil end
    local me = UnitName and UnitName("player")
    if me and ns.Secret and ns.Secret(me) then me = nil end
    local higher, tie, atMax, n, skippedMe = 0, 0, 0, 0, false
    -- 本职业排名（11-04 用户「增加法师排名第 x，各职业」）：同职业的人里比我高的 + 1；名单没给职业就不报
    local myName, myFile = nil, nil
    if UnitClass then
        local okc, cn, cf = pcall(UnitClass, "player")
        if okc and type(cf) == "string" and not (ns.Secret and ns.Secret(cf)) then myName, myFile = cn, cf end
    end
    local cHigher, cTie, cN = 0, 0, 0
    for i = 1, total do
        local ok2, name, _, _, level, _, _, _, _, _, _, classFile = pcall(GetGuildRosterInfo, i)
        level = ok2 and tonumber(level) or nil
        if level and not (ns.Secret and ns.Secret(level)) then
            local short = (type(name) == "string" and not (ns.Secret and ns.Secret(name))) and (name:match("^([^%-]+)") or name) or nil
            if not skippedMe and me and short == me then
                skippedMe = true
            else
                n = n + 1
                if level > lvl then higher = higher + 1 elseif level == lvl then tie = tie + 1 end
                if myFile and classFile == myFile then
                    cN = cN + 1
                    if level > lvl then cHigher = cHigher + 1 elseif level == lvl then cTie = cTie + 1 end
                end
                if level >= LS.MAX_LEVEL then atMax = atMax + 1 end
            end
        end
    end
    if n < 1 then return nil end
    local r = { rank = higher + 1, tie = tie, atMax = atMax, n = n }
    if myFile and cN >= 1 then r.cls, r.crank, r.ctie, r.cn = myName or myFile, cHigher + 1, cTie, cN end
    return r
end
LS.MAX_LEVEL = 60

-- 「公会里排第 8」/「公会里并列第 8」
local function rankTxt(g)
    if not g then return "" end
    local t
    if g.tie > 0 then t = string.format(ns.L("，公会里并列第 %d", ", tied #%d in the guild"), g.rank)
    else t = string.format(ns.L("，公会里排第 %d", ", #%d in the guild"), g.rank) end
    -- 职业排名：「，法师里并列第 1」/「，法师里排第 3」（公会里没有同职业的人就不带）
    if g.cls and g.crank then
        if g.ctie and g.ctie > 0 then t = t .. string.format(ns.L("，%s里并列第 %d", ", %s: tied #%d"), g.cls, g.crank)
        else t = t .. string.format(ns.L("，%s里排第 %d", ", %s: #%d"), g.cls, g.crank) end
    end
    return t
end

-- rec = { lvl, sec(本级用时，可 nil), played(累计，可 nil), xpMax(上一级经验条，可 nil), quests, guild = LS.GuildRank 结果（可 nil）}
function LS.Message(rec)
    local P = "[GearInsight插件] "   -- 10-22 用户「这里改成[GearInsight插件]」（原「[GearInsight 无限版]」）
    local lvl = rec.lvl
    local g = rec.guild
    if lvl >= LS.MAX_LEVEL then
        -- 第几个到满级 = 公会里已经满级的人数 + 1（名单里的人才算；退了会的不算）
        local nth = g and string.format(ns.L("公会里第 %d 个到 %d 级的，", "#%d in the guild to hit %d. "), g.atMax + 1, LS.MAX_LEVEL) or ""
        if rec.played and rec.played > 0 then
            return P .. string.format(ns.L("满级了！%s1 到 %d 级游戏时长 %s", "Max level! %s1 to %d in %s played"), nth, LS.MAX_LEVEL, fmtDur(rec.played))
        end
        return P .. ns.L("满级了！", "Max level! ") .. (nth ~= "" and nth:gsub("，$", "") or ns.L("一路走来", ""))
    end
    if lvl % 10 == 0 and rec.played and rec.played > 0 then
        return P .. string.format(ns.L("到 %d 级了%s！1 到 %d 级游戏时长 %s", "Level %d%s! 1 to %d in %s played"), lvl, rankTxt(g), lvl, fmtDur(rec.played))
    end
    -- ⛔ 别用「→」：游戏字体会变方框
    local head = P .. string.format(ns.L("升到 %d 级", "reached level %d"), lvl) .. rankTxt(g)
    local stat = LS.StatLine(rec, rec.rot)
    local sec = rec.act or rec.sec
    if not sec or sec <= 0 then return head .. ns.L("，", ", ") .. stat end
    -- 10-17 用户「不需要这样比」：不再和公测玩家比快慢，固定 = 活跃用时 + 一句战绩
    return head .. string.format(ns.L("，用时 %s，", ", %s, "), fmtShort(sec)) .. stat
end

local function send(msg)
    if not (IsInGuild and IsInGuild()) then return false, "noguild" end
    local f = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not f then return false, "api" end
    local ok = pcall(f, msg, "GUILD")
    return ok
end

-- ---------- 升级：记录 + 播报 ----------
local pending = nil      -- { lvl, xpMax, c(上一级计数快照), id, sent }
local lastXPMax = nil

local function prevPlayed(id, lvl)
    local d = db()
    local t = d.lvlx[id]
    local p = t and t[lvl - 1]
    if p and p.played and p.played > 0 then return p.played end
    -- Stats.lua 的升级记录（同一角色上一级的累计时长）
    for i = #(d.lvls or {}), 1, -1 do
        local r = d.lvls[i]
        if r.cid == id and r.lvl == lvl - 1 and (r.played or 0) > 0 then return r.played end
    end
    return nil
end

local function finish(played)
    local p = pending
    if not p or p.done then return end
    p.done = true
    pending = nil
    local d = db()
    local sec
    if played and played > 0 then
        local pp = prevPlayed(p.id, p.lvl)
        if pp and played > pp then sec = played - pp end
    end
    if not sec and p.levelSec and p.levelSec > 0 then sec = p.levelSec end   -- 上一级里拿到过 /played：本级已用 + 之后的时间
    local m, zn = 0, (GetZoneText and GetZoneText()) or ""
    if C_Map and C_Map.GetBestMapForUnit then local ok, v = pcall(C_Map.GetBestMapForUnit, "player"); if ok and v then m = v end end
    local c = p.c or {}
    local afk = math.floor(c.afk or 0)
    local act = sec and math.max(math.min(sec, 60), sec - afk) or nil
    local rec = { lvl = p.lvl, t = time and time() or 0, sec = sec and math.floor(sec) or nil, played = played and math.floor(played) or nil,
        act = act and math.floor(act) or nil, afk = afk,
        map = m, zn = zn, dead = c.dead or 0, quests = c.quests or 0, kills = c.kills or 0,
        grpPct = (sec and sec > 0) and math.min(100, math.floor((c.grp or 0) / sec * 100 + 0.5)) or nil,
        rested = p.rested and 1 or 0, resting = p.resting and 1 or 0, xpMax = p.xpMax }
    d.lvlx[p.id] = d.lvlx[p.id] or {}
    local t = d.lvlx[p.id]
    t[p.lvl] = rec
    local n, minK = 0, nil
    for k in pairs(t) do n = n + 1; if not minK or k < minK then minK = k end end
    if n > MAX_PER_CHAR and minK then t[minK] = nil end
    -- 播报（同一级只发一次）
    d.lvlShared = d.lvlShared or {}
    local key = p.id .. ":" .. p.lvl
    if LS.ShouldShare(p.lvl) and not d.lvlShared[key] then
        -- 只给播报用的（不存）：怪名 / 凶手名
        d.lvlShareRot = (d.lvlShareRot or 0) + 1
        local okG, gr = pcall(LS.GuildRank, p.lvl)
        local msgRec = setmetatable({ mobs = c.mobs, killers = killersOf(p.id, p.lvl - 1), rot = d.lvlShareRot, guild = okG and gr or nil },
            { __index = rec })
        local ok = send(LS.Message(msgRec))
        if ok then d.lvlShared[key] = true end
    end
end

function LS.OnLevelUp(newLvl)
    -- ⛔ 事件触发时 UnitLevel 可能已经是新等级：不能走 cur()（会按新等级把计数清零），直接拿存着的那份
    local id = cid()
    if not id then return end
    local d0 = db()
    if grpSince then
        local c0 = d0.lvlCur[id]
        if c0 then c0.grp = (c0.grp or 0) + (now() - grpSince) end
        grpSince = nil
    end
    local c = d0.lvlCur[id] or { dead = 0, quests = 0, kills = 0, grp = 0 }
    if afkSince then c.afk = (c.afk or 0) + (now() - afkSince) + AFK_LEAD; afkSince = now() end   -- 升级时还挂着：算到上一级，新一级从现在接着算
    -- 上一级的计数快照（cur() 下次会按新等级重开）
    local snap = { dead = c.dead, quests = c.quests, kills = c.kills, grp = c.grp, afk = c.afk, mobs = c.mobs }
    local levelSec
    local pl = ns._played
    if pl and pl.lvl == (newLvl - 1) then levelSec = pl.level + (now() - pl.at) end
    pending = { lvl = newLvl, id = id, c = snap, xpMax = lastXPMax, levelSec = levelSec,
        rested = (GetXPExhaustion and (GetXPExhaustion() or 0) > 0) or false, resting = (IsResting and IsResting()) or false }
    db().lvlCur[id] = { lvl = newLvl, dead = 0, quests = 0, kills = 0, grp = 0, afk = 0, mobs = {} }
    if inGroup() then grpSince = now() end
    -- Stats.lua 开着记录时它会要 /played；关着就自己要（升级时系统本来也会提示一行时长）
    if not (ns.db.collect ~= false) and RequestTimePlayed then pcall(RequestTimePlayed) end
    -- 公会名单刷一下（排名用；等 /played 那几秒里就回来了）
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
    if C_Timer and C_Timer.After then
        local mine = pending
        C_Timer.After(WAIT_PLAYED, function() if pending == mine then finish(nil) end end)
    end
end

-- 存档就绪后补默认值（默认开）
if ns.db then pcall(db) else table.insert(ns.modules, function() pcall(db) end) end   -- 主插件里加载时存档还没就绪 → 排进 ns.modules（以后若再改成按需加载，存档已在就直接补）

-- ---------- 事件 ----------
local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LEVEL_UP", "TIME_PLAYED_MSG", "PLAYER_DEAD", "QUEST_TURNED_IN", "CHAT_MSG_COMBAT_XP_GAIN",
    "GROUP_ROSTER_UPDATE", "PLAYER_XP_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_FLAGS_CHANGED" }) do pcall(f.RegisterEvent, f, e) end
local function onEvent(_, e, a1, a2)
    if not ns.db then return end
    local ok, err = pcall(function()
        if e == "PLAYER_LEVEL_UP" then
            LS.OnLevelUp(tonumber(a1) or ((UnitLevel and UnitLevel("player")) or 0))
        elseif e == "TIME_PLAYED_MSG" then
            if pending then finish(tonumber(a1)) end
        elseif e == "PLAYER_XP_UPDATE" or e == "PLAYER_ENTERING_WORLD" then
            if UnitXPMax then local v = UnitXPMax("player"); if v and v > 0 then lastXPMax = v end end
            if e == "PLAYER_ENTERING_WORLD" then grpSince = inGroup() and now() or nil end
        elseif e == "GROUP_ROSTER_UPDATE" then
            grpTick()
        elseif e == "PLAYER_FLAGS_CHANGED" then
            if a1 == "player" or a1 == nil then afkTick() end
        else
            local c = cur()
            if not c then return end
            if e == "PLAYER_DEAD" then c.dead = c.dead + 1
            elseif e == "QUEST_TURNED_IN" then c.quests = c.quests + 1
            elseif e == "CHAT_MSG_COMBAT_XP_GAIN" then
                -- 杀怪经验那条带「死亡」/ dies（任务经验不走这个事件；休息奖励写在同一句里）
                local s = tostring(a1 or "")
                if s:find("死亡", 1, true) or s:find("dies", 1, true) or s:find("死去", 1, true) then
                    c.kills = c.kills + 1
                    local mob = LS.MobFromXP(a1)
                    if mob then
                        c.mobs = c.mobs or {}
                        local n = 0
                        for _ in pairs(c.mobs) do n = n + 1 end
                        if c.mobs[mob] or n < 40 then c.mobs[mob] = (c.mobs[mob] or 0) + 1 end   -- 最多记 40 种怪
                    end
                end
            end
        end
    end)
    if not ok and ns.Debug then ns.Debug("LevelShare " .. tostring(err)) end
end
f:SetScript("OnEvent", onEvent)
LS._onEvent = onEvent   -- 测试用
LS._finish = finish

-- ---------- 导出（Stats.lua 的 GIFS1 文档加 lx 字段）----------
function ns.LevelShareExportDoc()
    local d = db()
    local out = {}
    for id, t in pairs(d.lvlx) do
        for lvl, r in pairs(t) do
            out[#out + 1] = { cid = id, lvl = lvl, t = r.t, sec = r.sec or 0, played = r.played or 0, map = r.map or 0,
                dead = r.dead or 0, q = r.quests or 0, k = r.kills or 0, grp = r.grpPct or -1, rs = r.rested or 0, inn = r.resting or 0, act = r.act or 0, afk = r.afk or 0 }
        end
    end
    if #out == 0 then return nil end
    table.sort(out, function(a, b) if a.cid ~= b.cid then return a.cid < b.cid end return a.lvl < b.lvl end)
    return out
end

-- ---------- 开关 ----------
local MODE_TXT = { every = { "每级", "every level" }, five = { "每 5 级", "every 5 levels" }, milestone = { "只在 10·20·30·40·50·60 级", "milestones only" }, off = { "关", "off" } }
function LS.ModeText(m) local t = MODE_TXT[m or db().lvlShare]; return t and ns.L(t[1], t[2]) or tostring(m) end
function LS.SetMode(m)
    if not MODES[m] then return false end
    db().lvlShare = m
    ns.Print(ns.L("升级播报：", "Level-up shout: ") .. LS.ModeText(m)
        .. ns.L("（发到公会频道，6 级起；改：/gi 升级播报 开 | 关 | 每5级 | 里程碑）", " (guild chat, from level 6; /gi lvlshare on|off|five|milestone)"))
    return true
end
local ARG = { ["开"] = "every", on = "every", ["每级"] = "every", ["关"] = "off", off = "off", ["每5级"] = "five", five = "five", ["5"] = "five",
    ["里程碑"] = "milestone", milestone = "milestone" }
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash["升级播报"] = function(rest)
    rest = (rest or ""):gsub("%s+", "")
    if ARG[rest] then LS.SetMode(ARG[rest]); return end
    ns.Print(ns.L("升级播报现在：", "Level-up shout: ") .. LS.ModeText()
        .. ns.L("。/gi 升级播报 开 | 关 | 每5级 | 里程碑", ". /gi lvlshare on|off|five|milestone"))
end
ns.ExtraSlash.lvlshare = ns.ExtraSlash["升级播报"]

-- 已登录（晚加载）才补跑一次「进入游戏」那段初始化；主插件正常加载时这里不跑，等事件
if IsLoggedIn and IsLoggedIn() then pcall(onEvent, f, "PLAYER_ENTERING_WORLD") end
