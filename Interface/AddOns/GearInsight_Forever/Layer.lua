-- 《无限》位面（layer）底座：识别当前层 + 插件互助网络 + 自动接受 + 众包 ly（10-28，HOLD）
-- 用户 10-28：「帮我调研并设计 公会位面插件，还有多位面自由切换插件」→「按你建议的，开始做A」→「都做到GEARINSIGHT」「B也做」
-- 设计稿 docs/forever-layering-addon-design-1028.md；A = LayerGuild.lua（公会位面），B = LayerHop.lua（换到最优层），探针 = LayerProbe.lua
--
-- 读层：NPC / 载具 GUID「Creature-0-服务器-实例-zoneUID-NPCID-刷新UID」的 zoneUID 段；同一张图不同层这一段不同。
--   层键 = 地图ID + zoneUID，只比同一张图的；连续 2 只不同 NPC 给出同一个 zoneUID 才算「确认」（conf = 2）。
--   战斗中 / 副本里不读（GUID 可能是保密值；副本没有分层）。
-- 网络（前缀 GIFLY1，每条 ≤ 250 字节）：
--   公会插件消息（A，建会后）· 集合口令频道 GIFL<口令>（A，开服当晚还没公会时）· 公共频道 GIForeverLY（B）
--   H|k=v|…   心跳：m 地图 / z 层 / c 置信 / r 会阶(0 会长 1 官员 2 会员) / ld 集合发起人 / lv 等级 / hp 愿意帮人换层 / q 任务 / t 看到的怪
--   Q|to=名字           A：请会长拉我                R|m=|z=|q=|n=   B：求邀请到 z 层
--   C|n=|h=名字          B：帮手认领                  D|n=|ok=1       B：到了
-- ⛔ 红线（设计稿 4.7 / 5.8）：邀请只在按钮点击里调（不批量、不自动邀请任何人）；不自动退队 / 解散；
--    副本内不工作；不循环换层；全部免费。⛔ HOLD：开服第一小时 /gi layerprobe 9 项探针通过、用户点头才出 HOLD。
-- ⛔ UI.lua 顶上写着「公会 / 组队 / 社交功能不放这里（归 GuildInsight）」——10-28 用户明确改口「都做到GEARINSIGHT」，本模块例外。
local _, ns = ...

local LY = {}
ns.Layer = LY
local PREFIX = "GIFLY1"
local PUB = "GIForeverLY"
LY.PREFIX, LY.PUB = PREFIX, PUB
LY.EXPIRE = 150           -- 秒：这么久没心跳 = 离线
LY.BEAT = 60              -- 秒：心跳间隔
LY.MIN_GAP = 5            -- 秒：层变了立即补发，但最少隔这么久
LY.SEEN_WINDOW = 180      -- 秒：「看到的怪」只算最近这么久
LY.MAX_PEERS = 300
LY.HOLD = 6               -- 秒：原来那层多久没见到才认新层（照 Guild Master Forever Layers.HOLD）
local L = function(cn, en) return ns.L(cn, en) end

local function now() return (GetTime and GetTime()) or 0 end
local function wall() return (time and time()) or 0 end
local function secret(v) return ns.Secret and ns.Secret(v) end
local function short(n) return type(n) == "string" and (n:match("^([^%-]+)") or n) or nil end
LY.Short = short

-- 11-13 玩家「哪里关😳」「或者初次的时候确认一次，后续要改的话去设置里找」：三个自动行为（会员求助自动拉 / 会长官员邀请自动接受 /
--   换过去后自动退队）存档改三态 true / false / nil(=还没问过)。nil 时不自动做，第一次真碰到时弹小框问一次（LY.AskOnce），选了就存，之后不再问
LY.ASK_KEYS = { "autoHelp", "autoAccept", "autoLeave" }
LY.ASK_FRESH = 60         -- 秒：问一次的框里点「以后都…」时，这件事（求助 / 邀请 / 换层）还在这么久以内才顺手照做
function LY.DB()
    ns.db.layer = ns.db.layer or {}
    local d = ns.db.layer
    if d.on == nil then d.on = true end                -- 读层 + 公会 / 集合频道心跳
    -- autoAccept（会长 / 官员的邀请自动接受）：10-28 起默认 true 写进存档；11-13 起不再给默认值（nil = 第一次碰到时问）
    if d.officerMax == nil then d.officerMax = 1 end    -- 会阶序号 ≤ 这个算「官员」（0 = 会长）
    if d.pub == nil then d.pub = true end              -- B：在公共频道报层（只报地图 / 层 / 任务 ID / 怪的数量）
    if d.helper == nil then d.helper = true end        -- B：愿意帮别人换到我这层（收到请求弹提示，点了才邀）
    -- 11-06 用户「我的目的是给练级过程中的会员用的，互相互助切位面」+「设置都可以关闭，默认打开」：
    --   帮手默认开；旧存档里自动写进去的 false 一次性改成 true（helperV=2 记已迁，之后玩家自己关的不再动）
    if d.helperV ~= 2 then d.helper = true; d.helperV = 2 end
    -- 11-06 照 Guild Master Forever（无限外服公会插件，MIT）的真机做法：会员求助自动拉、到了新层自动退队（都能关，默认开）
    --   autoHelp（公会会员求助：我没在队伍里就直接邀请，不弹框；路人求助照旧弹框）/ autoLeave（求助换层：进队、看到层变了就自动退队）同上，不给默认值
    -- 11-13 老存档迁移（askV=1 记已迁，只跑一次）：1.1.1 及以前 DB() 一打开就把默认值 true 写进存档，没有「玩家改过」的记号，
    --   存档里的 true 分不出是吃默认还是自己开的 → 一律当「还没问过」清成 nil（自己开过的人也只是被问一次，点「以后都…」就回到原样）；
    --   false 只可能是玩家自己关的（这三项默认从来都是 true）→ 原样保留，不再问
    if d.askV ~= 1 then
        for _, k in ipairs(LY.ASK_KEYS) do
            if d[k] == true then d[k] = nil end
        end
        d.askV = 1
    end
    d.order = type(d.order) == "table" and d.order or {}   -- [地图] = { zoneUID, … }：本地 L1/L2 编号（按首次看到的先后）
    d.xmap = type(d.xmap) == "table" and d.xmap or {}      -- 11-06 跨地图对照表：["m:z_m:z"] = { s = { [来源] = 时间 }, t = 最近时间 }
    return d
end

-- ---------- 读层 ----------
-- 返回 { kind, server, inst, zuid, npc, spawn }；只认 Creature / Vehicle（宠物、召唤物、玩家不算）
function LY.ParseGUID(guid)
    if type(guid) ~= "string" or secret(guid) then return nil end
    local kind, _, server, inst, zuid, npc, spawn = guid:match("^(%a+)%-(%d+)%-(%d+)%-(%d+)%-(%d+)%-(%d+)%-(%x+)$")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return { kind = kind, server = tonumber(server), inst = tonumber(inst), zuid = tonumber(zuid), npc = tonumber(npc), spawn = spawn }
end

LY.cur = { map = nil, z = nil, conf = 0, npcs = {} }   -- 当前层
LY.pend = nil                                            -- 待确认的新层 { z, npcs }
LY.changes = {}                                          -- 换层日志 { t, wall, map, from, to }（探针 P6 / P7 用）
LY.listeners = {}
LY.seen = {}                                             -- [npcID] = { [spawn] = 时间 }（B：附近有几只）
LY.names = {}                                            -- [npcID] = 名字（B：和任务目标名字对上）

function LY.OnChange(fn) LY.listeners[#LY.listeners + 1] = fn end
-- 11-06 用户「切位面给点提示，给邀请人和被邀请人，就弹出一个快速消失的文字」：屏幕中上方一行字，几秒淡出（暴雪红字提示那一行）
function LY.Flash(text, r, g, b)
    if type(text) ~= "string" or text == "" then return end
    local f = _G.UIErrorsFrame
    if f and f.AddMessage then pcall(f.AddMessage, f, text, r or 0.2, g or 1, b or 0.6) end
end

local function fire(old, new, map)
    if old and new and old ~= new and LY.LayerName then
        LY.Flash(string.format(ns.L("位面已切换：%s → %s", "Layer changed: %s -> %s"), LY.LayerName(map, old), LY.LayerName(map, new)))
    end
    local c = LY.changes
    c[#c + 1] = { t = now(), wall = wall(), map = map, from = old, to = new }
    while #c > 50 do table.remove(c, 1) end
    for _, fn in ipairs(LY.listeners) do pcall(fn, old, new, map) end
end

local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

-- 喂一条 GUID（map = 玩家所在地图）。返回 true = 当前层刚确认 / 换了
function LY.Feed(guid, map, name)
    local g = LY.ParseGUID(guid)
    if not g or not map then return false end
    local cur = LY.cur
    if cur.map ~= map then
        LY.cur = { map = map, z = nil, conf = 0, npcs = {} }; LY.pend = nil; cur = LY.cur
    end
    local seen = LY.seen[g.npc] or {}
    LY.seen[g.npc] = seen
    seen[g.spawn] = now()
    if type(name) == "string" and not secret(name) and name ~= "" then LY.names[g.npc] = name end
    -- 11-06 用户实测「没成功」：暴风城满街「暴风城卫兵」是同一种 NPC，旧门槛（2 种不同 NPC 才确认）永远确认不了。
    --   改照 Guild Master Forever（无限真机在用，MIT）Layers.lua 的门槛：
    --   · 这张图第一只怪 → 直接当我的层；
    --   · 别的 zoneUID：要 2 只不同的怪（按 GUID 算，同一种 NPC 的两只也算）都给出它，且原来那层已经 6 秒没见到，才换；
    --   · 换层求助的目标层（LY.ExpectZ）见到 1 只就换。
    local key = g.npc .. ":" .. tostring(g.spawn)
    if cur.z == nil then
        cur.z, cur.npcs, cur.conf, cur.seenAt = g.zuid, { [key] = true }, 2, now()
        LY.pend = nil
        pcall(LY.XFromWalk, map, g.zuid)
        LY.lastSeen = { m = map, z = g.zuid, at = now() }
        LY.Remember(map, cur.z); fire(nil, cur.z, map)
        return true
    end
    if g.zuid == cur.z then
        cur.npcs[key] = true
        cur.seenAt = now()
        cur.inferred = nil   -- 11-12：按队长推断的层被亲眼读到的怪证实了
        LY.pend = nil
        LY.lastSeen = { m = map, z = cur.z, at = now() }
        return false
    end
    local expect = LY.ExpectZ and LY.ExpectZ(map)
    local p = LY.pend
    if not p or p.z ~= g.zuid then p = { z = g.zuid, npcs = {} }; LY.pend = p end
    p.npcs[key] = true
    -- 11-06 用户「切过来，看到位面换了，但是这里没有展示」：进 / 退队后层随时会被传走，这 90 秒里见到 1 只新层的怪就换（LY.fastUntil）
    local fast = LY.fastUntil and now() < LY.fastUntil
    if expect == g.zuid or fast or (count(p.npcs) >= 2 and now() - (cur.seenAt or 0) >= LY.HOLD) then
        local old = cur.z
        LY.cur = { map = map, z = p.z, conf = 2, npcs = p.npcs, seenAt = now() }
        LY.pend = nil
        LY.lastSeen = { m = map, z = p.z, at = now() }
        LY.Remember(map, p.z)
        fire(old, p.z, map)
        return true
    end
    return false
end

function LY.Reset()
    LY.cur = { map = nil, z = nil, conf = 0, npcs = {} }; LY.pend = nil
end

-- 我现在的层：map, z, conf（副本里 / 没读到 = nil）
function LY.Mine()
    local c = LY.cur
    if not c.map or not c.z then return c.map, nil, 0 end
    return c.map, c.z, c.conf
end
function LY.Confirmed() return LY.cur.z ~= nil and LY.cur.conf >= 2 end

-- 本地编号：同一张图按首次看到的先后 L1 / L2 …（⛔ zoneUID 本身没有序号，不编造「第几层」；只代表本插件网络所见）
function LY.Remember(map, z)
    if not map or not z then return end
    local o = LY.DB().order
    local k = tostring(map)
    o[k] = o[k] or {}
    for _, v in ipairs(o[k]) do if v == z then return end end
    if #o[k] >= 12 then table.remove(o[k], 1) end
    o[k][#o[k] + 1] = z
end
function LY.Label(map, z)
    if not z then return "?" end
    LY.Remember(map, z)
    local o = LY.DB().order[tostring(map)] or {}
    for i, v in ipairs(o) do if v == z then return "L" .. i end end
    return "L?"
end
function LY.Tail(z) return z and string.format("%04d", z % 10000) or "----" end
-- 11-06 页面给玩家看的叫法：「第 N 层」（N = 本地编号，同 L1 / L2；⛔ 不是官方层号）
function LY.LayerNo(map, z)
    local l = LY.Label(map, z)
    return tonumber(l:match("^L(%d+)$"))
end
function LY.LayerName(map, z)
    local n = LY.LayerNo(map, z)
    return n and string.format(L("第 %d 层", "layer %d"), n) or L("某一层", "a layer")
end
-- 地图中文名（读不到给编号）
function LY.MapName(map)
    if not map then return "?" end
    if C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, map)
        local nm = ok and type(info) == "table" and info.name
        if type(nm) == "string" and not secret(nm) and nm ~= "" then return nm end
    end
    return tostring(map)
end

-- 最近 SEEN_WINDOW 秒内看到的某 NPC 有几只（按刷新 UID 去重）
function LY.SeenCount(npc)
    local s = LY.seen[npc]
    if not s then return 0 end
    local n, t = 0, now()
    for k, at in pairs(s) do
        if t - at <= LY.SEEN_WINDOW then n = n + 1 else s[k] = nil end
    end
    return n
end

local function inInstance()
    if not IsInInstance then return false end
    local ok, inside = pcall(IsInInstance)
    return ok and inside and true or false
end
LY.InInstance = inInstance
local function inCombat()
    if InCombatLockdown and InCombatLockdown() then return true end
    if UnitAffectingCombat and UnitAffectingCombat("player") then return true end
    return false
end
LY.InCombat = inCombat
-- 11-07 用户截图「我现在：东部王国 · 第 6 层」+ 1～5 层：有的地方游戏给不出地区图，GetBestMapForUnit 返回整块大陆，
--   各地区的层码（按地区编号）全记到大陆名下 → 冒出一堆假层。大陆 / 世界级的图（UIMapType ≤ Continent）不认，当没认出地图
local function myMap()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or type(m) ~= "number" or secret(m) then return nil end
    if C_Map.GetMapInfo then
        local ok2, info = pcall(C_Map.GetMapInfo, m)
        local t = ok2 and type(info) == "table" and tonumber(info.mapType)
        local cont = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
        if t and t <= cont then
            -- 11-07 用户截图「指上去了，还是认不出」（迪菲亚那一带）：直接扔掉大陆图 = 整片地方认不出。
            --   改成按我在大陆图上的位置，问这个点落在哪个地区（GetMapInfoAtPosition），拿到地区图就用它
            if C_Map.GetPlayerMapPosition and C_Map.GetMapInfoAtPosition then
                local okp, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
                local okx, x, y
                if okp and pos then okx, x, y = pcall(pos.GetXY, pos) end
                if okx and type(x) == "number" and type(y) == "number" and not secret(x) and not secret(y) then
                    local oki, zi = pcall(C_Map.GetMapInfoAtPosition, m, x, y)
                    local zt = oki and type(zi) == "table" and tonumber(zi.mapType)
                    if zt and zt > cont and tonumber(zi.mapID) then return tonumber(zi.mapID) end
                end
            end
            return nil
        end
    end
    return m
end
LY.MyMap = myMap

LY.leftInstanceAt = -1e9
-- ---------- 11-06 跨地图对照表（用户「位面不分地图吧」「能跨地图确认对方在第几层吗」「继续推」）----------
-- 位面整块大陆共用，层码（GUID 第 5 段）却按地图编号：同一层在暴风城是 13、在艾尔文森林是 27。插件自己学对应：
--   ① 我走过地图边界（同一块大陆、5 分钟内、中间没传送 / 进出副本 / 队伍名单变动）：旧图的层 ≡ 新图的层
--   ② 同队队友在别的图（我在队里 > 30 秒、他的心跳是名单变动 20 秒后发的、我的层已确认）：他的层 ≡ 我的层
--   ③ 会员心跳里带他自己学到的 3 条，合进来，来源记成他
-- 一对至少 2 个来源（不同的机器）都说过才采信（照众包「≥2 台一致」）；12 小时没再见到就过期（服务器重启层码会变）。
-- 采信的对应连成图，同一个连通块 = 同一个大陆层；查别的图的会员在我这张图上对应哪个层码 → 第 N 层 / 和你同层
LY.XWIN, LY.XTTL, LY.XMIN, LY.XPARTY = 300, 12 * 3600, 2, 30
LY._cont = {}
function LY.Continent(map)
    if type(map) ~= "number" then return nil end
    local c = LY._cont[map]
    if c ~= nil then return c or nil end
    local res = false
    local CT = Enum and Enum.UIMapType and Enum.UIMapType.Continent
    if C_Map and C_Map.GetMapInfo and CT then
        local id, n = map, 0
        while type(id) == "number" and id > 0 and n < 10 do
            local ok, info = pcall(C_Map.GetMapInfo, id)
            if not ok or type(info) ~= "table" then break end
            if info.mapType == CT then res = id; break end
            id, n = info.parentMapID, n + 1
        end
    end
    LY._cont[map] = res
    return res or nil
end
local function xnode(m, z) return tostring(m) .. ":" .. tostring(z) end
local function xpair(a, b) if a < b then return a .. "_" .. b end return b .. "_" .. a end
local function xcount(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end

function LY.XLearn(m1, z1, m2, z2, src)
    if not (m1 and z1 and m2 and z2 and src) or m1 == m2 then return false end
    local d = LY.DB()
    local k = xpair(xnode(m1, z1), xnode(m2, z2))
    local e = d.xmap[k]
    if not e then e = { s = {} }; d.xmap[k] = e end
    e.s[src] = wall(); e.t = wall()
    if src == "self" then
        LY.xMine = LY.xMine or {}
        for i = #LY.xMine, 1, -1 do if LY.xMine[i] == k then table.remove(LY.xMine, i) end end
        table.insert(LY.xMine, 1, k)
        while #LY.xMine > 6 do table.remove(LY.xMine) end
    end
    LY._xg = nil; LY.dirty = true
    return true
end

function LY.XPrune()
    local d, t = LY.DB(), wall()
    for k, e in pairs(d.xmap) do
        for src, at in pairs(e.s or {}) do if t - (at or 0) > LY.XTTL then e.s[src] = nil end end
        if xcount(e.s) == 0 then d.xmap[k] = nil end
    end
    LY._xg = nil
end

local function xgraph()
    -- 过期条目每 5 分钟清一次（12 小时没再见到的）
    if not LY._xgAt or now() - LY._xgAt > 300 then LY.XPrune(); LY._xgAt = now() end
    if LY._xg then return LY._xg end
    local adj = {}
    for k, e in pairs(LY.DB().xmap) do
        if xcount(e.s) >= LY.XMIN then
            local a, b = k:match("^(%d+:%d+)_(%d+:%d+)$")
            if a then
                adj[a] = adj[a] or {}; adj[b] = adj[b] or {}
                adj[a][b] = true; adj[b][a] = true
            end
        end
    end
    LY._xg = adj
    return adj
end

-- (m, z) 在 target 这张图上对应哪个层码；查不到 / 数据打架（同一块里 target 图有两个层码）→ nil
function LY.XOnMap(m, z, target)
    if not (m and z and target) then return nil end
    if m == target then return z end
    local adj, start = xgraph(), xnode(m, z)
    if not adj[start] then return nil end
    local seen, queue, found = { [start] = true }, { start }, nil
    local i = 1
    while queue[i] do
        local cur = queue[i]; i = i + 1
        local cm, cz = cur:match("^(%d+):(%d+)$")
        if tonumber(cm) == target then
            if found and found ~= tonumber(cz) then return nil end
            found = tonumber(cz)
        end
        for nb in pairs(adj[cur] or {}) do
            if not seen[nb] then seen[nb] = true; queue[#queue + 1] = nb end
        end
    end
    return found
end

-- ① 走过地图边界：新图第一只怪时调（Feed）
function LY.XFromWalk(map, z)
    local pv = LY.lastSeen
    if not (pv and pv.m and pv.z and pv.m ~= map) then return false end
    if now() - (pv.at or -1e9) > LY.XWIN then return false end
    if (LY.pewAt or -1e9) >= pv.at or (LY.rosterAt or -1e9) >= pv.at then return false end
    if inCombat() or inInstance() then return false end
    local c1 = LY.Continent(pv.m)
    if not c1 or c1 ~= LY.Continent(map) then return false end
    return LY.XLearn(pv.m, pv.z, map, z, "self")
end

-- 名字是不是我队伍里的人（名 / 名 姓都认）
local function inMyGroup(name)
    if not (IsInGroup and IsInGroup()) or type(name) ~= "string" then return false end
    local s = name:gsub("%-.*$", "")
    local first = s:match("^(%S+)")
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    local raid = IsInRaid and IsInRaid()
    for i = 1, math.max(n, 4) do
        local u = raid and ("raid" .. i) or ("party" .. i)
        local ok, un = pcall(UnitName, u)
        if ok and type(un) == "string" and not secret(un) then
            local us = un:gsub("%-.*$", "")
            if us == s or us == first or (us:match("^(%S+)") == first) then return true end
        end
    end
    return false
end
LY.InMyGroup = inMyGroup

-- ② 同队队友在别的图：收到他的心跳时调（Handle）
function LY.XFromParty(p)
    if not (p and p.m and p.z and (p.c or 0) >= 2) or p.inst then return false end
    local m, z = LY.Mine()
    if not (m and z and LY.Confirmed()) or p.m == m then return false end
    if inCombat() or inInstance() then return false end
    local ra = LY.rosterAt or -1e9
    if now() - ra < LY.XPARTY or (p.seen or 0) < ra + 20 then return false end
    if not inMyGroup(p.full or p.name) then return false end
    local c1 = LY.Continent(m)
    if not c1 or c1 ~= LY.Continent(p.m) then return false end
    return LY.XLearn(m, z, p.m, p.z, "self")
end

function LY.ReadUnit(unit)
    if not LY.DB().on or inCombat() or inInstance() then return false end
    if not UnitGUID then return false end
    -- 11-12 12.x：UnitIsPlayer 的返回值可能是保密值，不能直接拿来 if → pcall + 先判保密
    if UnitIsPlayer then
        local okp, isP = pcall(UnitIsPlayer, unit)
        if okp and not secret(isP) and isP then return false end
    end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok then return false end
    local name
    if UnitName then local ok2, n = pcall(UnitName, unit); if ok2 then name = n end end
    return LY.Feed(guid, myMap(), name)
end

-- 11-12 用户截图「已进 Closing Time 的队，正在确认换没换层」一直不出结果：原来进队后只重读 target / mouseover / 姓名板，
--   城里友方姓名板默认不显示、玩家也没去指怪 → 一只 NPC 都读不到，层码永远停在旧层。
--   现在把能读到 GUID 的单位全读一遍：目标 / 鼠标 / 焦点 / 软目标（12.x 的 softenemy / softfriend / softinteract）/
--   目标的目标 / 队友的目标（队长指着的怪也在他那层）+ 姓名板。读不到的单位 UnitGUID 给 nil，ParseGUID 直接丢掉
LY.PROBE_UNITS = { "target", "mouseover", "focus", "softenemy", "softfriend", "softinteract", "targettarget",
    "party1target", "party2target", "party3target", "party4target" }
function LY.ReadAll()
    if not LY.DB().on or inCombat() or inInstance() then return false end
    local changed = false
    for _, u in ipairs(LY.PROBE_UNITS) do
        local ok, r = pcall(LY.ReadUnit, u)
        if ok and r then changed = true end
    end
    pcall(LY.ScanPlates)
    return changed
end

-- 11-12 读不到任何怪时，按队长（进队就到他那层，暴雪机制）心跳里报的层认我的层：标 inferred，之后亲眼读到别的层照常改过来
function LY.Adopt(map, z, why)
    if not map or not z or secret(z) then return false end
    local old = (LY.cur.map == map) and LY.cur.z or nil
    if old == z then return false end
    LY.cur = { map = map, z = z, conf = 2, npcs = {}, seenAt = now(), inferred = why or true }
    LY.pend = nil
    LY.Remember(map, z)
    fire(old, z, map)
    return true
end

function LY.ScanPlates()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return 0 end
    if not LY.DB().on or inCombat() or inInstance() then return 0 end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return 0 end
    local n = 0
    for _, p in ipairs(plates) do
        local u = p and (p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit))
        if u then n = n + 1; LY.ReadUnit(u) end
    end
    return n
end

-- ---------- 网络 ----------
LY.peers = {}            -- [短名] = { m, z, c, r, ld, lv, hp, q = {}, t = {}, seen, via = { guild, gather, pub } }
LY.gather = nil          -- 集合口令（开服当晚还没公会时；会长 /gi layer lead 口令，会员 /gi layer join 口令）
local queue = {}
local lastBeat, lastSend = -1e9, -1e9

local function chanIndex(name)
    if not GetChannelName or not name then return nil end
    local id = tonumber((GetChannelName(name)))
    return (id and id > 0) and id or nil
end
-- GI-215「加入聊天频道导致原有频道顺序错乱……能否往后加」：刚上线时系统频道（综合 / 交易 / 本地防务 / 寻求组队）还在一个个加，
--   插件这时加频道会占掉前面的编号，系统频道被挤到后面、颜色跟着乱 → 真正上线（不是 /reload）后等 CHAN_WAIT 秒再加；
--   /reload 时系统频道早就在了，不用等
LY.CHAN_WAIT = 30
function LY.ChanReady()
    if not LY.loginAt then return true end
    return now() - LY.loginAt >= LY.CHAN_WAIT
end
local function joinChannel(name)
    if not name then return false end
    if chanIndex(name) then return true end
    if not LY.ChanReady() then return false end
    if JoinTemporaryChannel then pcall(JoinTemporaryChannel, name)
    elseif JoinChannelByName then pcall(JoinChannelByName, name) end
    -- ⛔ 别碰暴雪聊天框（gi_forever_forbidden_check）：插件消息不进聊天框，加入频道只多一个编号
    return chanIndex(name) ~= nil
end
-- GI-201「自动添加GIForeverLY频道能不能加个开关」：默认加入，位面页设置 / /gi layer pub off 可关；关了立刻退频道，只和公会会员互通
-- 11-10 用户「频道是不是被封了」「暴雪不让加入了」→「按地图分频道吧」：全服挤一个 GIForeverLY（人满 / 被封一锅端）→
--   每张图一个频道 GIFM<地图编号>：心跳里的层 / 任务 / 怪本来就只对同图的人有用；换图时退旧的、加新的（停稳 5 秒再换，路过不折腾）。
--   旧的 GIForeverLY 还在就顺手退掉。副本里不加（副本没有层）
LY.pubJoined = nil
function LY.PubChannel()
    local m = myMap()
    if type(m) ~= "number" then return nil end
    return "GIFM" .. m
end
local function leave(name)
    if name and LeaveChannelByName and chanIndex(name) then pcall(LeaveChannelByName, name) end
end
-- 让「我在的公共频道」= 这张图的频道。返回 true = 现在已经在这张图的频道里
function LY.SyncPub()
    leave(PUB)   -- 旧的全服频道
    local want = (LY.DB().pub and not inInstance()) and LY.PubChannel() or nil
    if LY.pubJoined and LY.pubJoined ~= want then leave(LY.pubJoined); LY.pubJoined = nil end
    if not want then return false end
    if joinChannel(want) then LY.pubJoined = want; return true end
    return false
end
function LY.SetPub(v)
    LY.DB().pub = v and true or false
    LY.SyncPub()
    if v then LY.Beat(true) end
    LY.dirty = true
end
LY.PUB = PUB
function LY.GatherChannel() return LY.gather and ("GIFL" .. LY.gather) or nil end

-- 11-10 用户「这个能不能用户看不到感知不到」「但是功能照常实现？」：插件频道照常加、插件消息照常收发（本来就不进聊天框），
--   只把玩家能看到的两样藏掉：加入 / 离开频道的系统提示（「已加入频道：5. GIForeverLY」）、有人在这个频道里打字。
--   只用官方 ChatFrame_AddMessageEventFilter（同 GuildChatLevel / LevelMute），⛔ 不碰聊天框本身
function LY.IsOurChannel(name)
    if type(name) ~= "string" or secret(name) then return false end
    local base = name:gsub("^%d+%.%s*", "")
    return base == PUB or base:sub(1, 4) == "GIFL" or base:sub(1, 4) == "GIFM"
end
local function hideOurChannel(_, _, _, _, _, chanStr, _, _, _, _, chanName)
    if LY.IsOurChannel(chanName) or LY.IsOurChannel(chanStr) then return true end
    return false
end
LY._hideOurChannel = hideOurChannel
if ChatFrame_AddMessageEventFilter then
    for _, e in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE", "CHAT_MSG_CHANNEL" }) do
        pcall(ChatFrame_AddMessageEventFilter, e, hideOurChannel)
    end
end
LY.ChanIndex, LY.JoinChannel = chanIndex, joinChannel

-- dist = "GUILD" / "GATHER" / "PUB" / "WHISPER:名字"
function LY.Queue(dist, msg)
    if #msg > 250 then msg = msg:sub(1, 250) end
    if #queue > 40 then table.remove(queue, 1) end
    queue[#queue + 1] = { dist, msg }
end
LY._queue = queue

local function rawSend(dist, msg)
    local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not fn then return false end
    local ok, res
    if dist == "GUILD" then
        if not (IsInGuild and IsInGuild()) then return true end   -- 没公会：丢掉，不重试
        ok, res = pcall(fn, PREFIX, msg, "GUILD")
    elseif dist == "GATHER" or dist == "PUB" then
        if dist == "PUB" and not LY.DB().pub then return true end   -- GI-201：公共频道关了 → 丢掉，不加频道
        local name = (dist == "PUB") and LY.PubChannel() or LY.GatherChannel()
        if not name then return true end
        if dist == "PUB" and inInstance() then return true end
        if not chanIndex(name) and not LY.ChanReady() then return true end   -- GI-215：上线头 30 秒先不加频道，这条心跳丢掉（每分钟还会再发）
        if dist == "PUB" then
            if not LY.SyncPub() then return false end
        elseif not joinChannel(name) then return false end
        ok, res = pcall(fn, PREFIX, msg, "CHANNEL", chanIndex(name))
    elseif dist:sub(1, 8) == "WHISPER:" then
        ok, res = pcall(fn, PREFIX, msg, "WHISPER", dist:sub(9))
    else
        return true
    end
    local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0
    return ok and (res == nil or res == true or res == success)
end

LY._rawSend = rawSend   -- 测试用

-- 心跳内容：基础字段 + 各模块（A 加会阶 / B 加任务和怪）挂的字段
LY.fieldHooks = {}
function LY.AddFields(fn) LY.fieldHooks[#LY.fieldHooks + 1] = fn end
function LY.Encode(kind, t)
    local parts = { kind }
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = t[k]
        if v ~= nil and v ~= "" then parts[#parts + 1] = k .. "=" .. tostring(v) end
    end
    return table.concat(parts, "|")
end
function LY.Decode(msg)
    if type(msg) ~= "string" then return nil end
    local kind = msg:match("^(%a)|") or msg:match("^(%a)$")
    if not kind then return nil end
    local t = { kind = kind }
    for k, v in msg:gmatch("|(%w+)=([^|]*)") do t[k] = v end
    return t
end

function LY.Heartbeat(scope)
    local d = LY.DB()
    if not d.on then return end
    local m, z, c = LY.Mine()
    local base = { m = m, z = z, c = c, lv = UnitLevel and UnitLevel("player") or nil }
    if UnitClass then   -- 11-06 位面页会员名字用职业色
        local ok, _, cf = pcall(UnitClass, "player")
        if ok and type(cf) == "string" and not secret(cf) then base.cl = cf end
    end
    if inInstance() then base.m, base.z, base.c, base.i = nil, nil, 0, 1 end
    if IsInGroup and IsInGroup() then base.g = 1 end   -- 11-06 在队伍里：别人挑帮手时排后面（在队里接不了邀请拉人也要弹框）
    for _, fn in ipairs(LY.fieldHooks) do pcall(fn, base, scope) end
    -- 11-06 跨地图对照：带最近自己亲眼学到的 3 条（0.7.0 收到不认识的字段直接忽略）；整条心跳超过 240 字节就少带
    local mine = {}
    for _, k in ipairs(LY.xMine or {}) do if #mine < 3 and d.xmap[k] and d.xmap[k].s.self then mine[#mine + 1] = k end end
    while #mine > 0 do
        base.x = table.concat(mine, ",")
        if #LY.Encode("H", base) <= 240 then break end
        table.remove(mine); base.x = nil
    end
    return base
end

function LY.Beat(force)
    local t = now()
    if not force and t - lastBeat < LY.MIN_GAP then return end
    lastBeat = t
    local d = LY.DB()
    if not d.on then return end
    if IsInGuild and IsInGuild() then LY.Queue("GUILD", LY.Encode("H", LY.Heartbeat("guild"))) end
    if LY.gather then LY.Queue("GATHER", LY.Encode("H", LY.Heartbeat("gather"))) end
    if d.pub then LY.Queue("PUB", LY.Encode("H", LY.Heartbeat("pub"))) end
end

LY.handlers = {}         -- [kind] = function(t, sender, via)
-- 11-06 用户截图「第 1 层 2 人：我 枫叶 洞察」：《无限》角色名是「名 姓」，UnitName("player") 可能只给「枫叶」，
--   插件消息的发送人却是「枫叶 洞察(-服务器)」→ 原来的 s == me 认不出自己。名字相同、或发送人以「我的名字 + 空格」开头、
--   或我的全名（GetUnitName 带姓）相同，都算自己
function LY.IsMe(name)
    if type(name) ~= "string" or secret(name) then return false end
    local s = name:gsub("%-.*$", "")
    local me = UnitName and UnitName("player")
    if type(me) ~= "string" or secret(me) or me == "" then return false end
    if s == me then return true end
    -- 拿得到带姓的全名就只认全名（别把同名不同姓的「枫叶 某某」当成自己）；拿不到才按「名 + 空格」开头认
    local full = GetUnitName and select(2, pcall(GetUnitName, "player", false))
    if type(full) == "string" and not secret(full) and full:find(" ", 1, true) then return full:gsub("%-.*$", "") == s end
    return s:sub(1, #me + 1) == me .. " "
end

function LY.Handle(msg, sender, via)
    local s = short(sender)
    if not s or secret(s) then return end
    if LY.IsMe(s) then return end
    local t = LY.Decode(msg)
    if not t then return end
    if t.kind == "H" then
        local p = LY.peers[s]
        if not p then
            if count(LY.peers) >= LY.MAX_PEERS then return end
            p = { via = {} }; LY.peers[s] = p
        end
        p.name, p.full = s, sender
        p.m, p.z, p.c = tonumber(t.m), tonumber(t.z), tonumber(t.c) or 0
        p.r, p.ld, p.lv, p.hp, p.inst = tonumber(t.r), t.ld == "1", tonumber(t.lv), t.hp == "1", t.i == "1"
        p.cl = (type(t.cl) == "string" and t.cl:match("^%u+$")) and t.cl or nil
        p.ig = t.g == "1"
        p.hc = tonumber(t.hc)   -- 11-06 最近 30 分钟帮过几次（0.7.0 没这个字段 = nil）
        if type(t.x) == "string" then
            for a1, b1, a2, b2 in t.x:gmatch("(%d+):(%d+)_(%d+):(%d+)") do
                pcall(LY.XLearn, tonumber(a1), tonumber(b1), tonumber(a2), tonumber(b2), s)
            end
        end
        p.q, p.t = {}, {}
        for q in (t.q or ""):gmatch("(%d+)") do p.q[tonumber(q)] = true end
        for npc, n in (t.t or ""):gmatch("(%d+):(%d+)") do p.t[tonumber(npc)] = tonumber(n) end
        p.seen = now()
        p.via[via] = now()
        if p.m and p.z then LY.Remember(p.m, p.z) end
        pcall(LY.XFromParty, p)
        LY.dirty = true
    end
    local h = LY.handlers[t.kind]
    if h then pcall(h, t, s, via, sender) end
end

-- 只看某个来源（guild / gather / pub）的在线 peer
function LY.Peers(via)
    local out, t = {}, now()
    for name, p in pairs(LY.peers) do
        if t - (p.seen or 0) > LY.EXPIRE then LY.peers[name] = nil
        elseif not via or (p.via[via] and t - p.via[via] <= LY.EXPIRE) then out[#out + 1] = p end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- ---------- 自动接受 ----------
-- 各模块挂规则：fn(inviterShort) → 理由字符串 / nil。A = 会长 / 官员 / 集合发起人；B = 自己刚求的那一层的帮手（30 秒内）
LY.acceptRules = {}
function LY.AddAcceptRule(fn) LY.acceptRules[#LY.acceptRules + 1] = fn end
-- 规则可多返回一个 kind：「officer」= 会长 / 官员 / 集合发起人那条，受 autoAccept 管 —— 开关还是 nil（没问过）时不算数，
--   记成第三个返回值 ask（OnInvite 拿去弹「问一次」），接着看别的规则（自己求的换层帮手那条不受影响）
function LY.AcceptReason(inviter)
    local s = short(inviter)
    if not s or secret(s) then return nil end
    local ask
    for _, fn in ipairs(LY.acceptRules) do
        local ok, why, kind = pcall(fn, s)
        if ok and why then
            if kind == "officer" and LY.DB().autoAccept == nil then ask = ask or why
            elseif kind then return why, kind
            else return why end
        end
    end
    if ask then return nil, nil, ask end
    return nil
end
-- 11-10 用户「有人点了换位面，然后是她组我……她的位面没动」：换层收发全记一笔（存档留 40 条），/gi layer log 弹框复制，下次出事看得到谁邀请了谁
function LY.Log(line)
    local d = LY.DB()
    d.log = d.log or {}
    local ts = (date and date("%m-%d %H:%M:%S")) or tostring(now())
    if #d.log >= 40 then table.remove(d.log, 1) end
    d.log[#d.log + 1] = ts .. " " .. tostring(line)
end
-- ---------- 11-13 问一次（自动拉 / 自动接受 / 自动退队：开关还是 nil 时，第一次真碰到才问）----------
-- LY.AskOnce(key, opts)：opts = { text, yes, no, onYes, onNo, onClose }
--   点 yes「以后都…」→ 存 true，调 onYes（这次也照做）；点 no「每次问我 / 不自动退」→ 存 false，调 onNo；右上 × = 这次先不定（还是 nil，下次碰到再问），调 onClose
--   ⛔ 插件自己的框，不用 StaticPopup（不往暴雪弹框表里塞东西）；⛔ 战斗中不弹：返回 "later"，调用方这次按「不自动」处理，脱战后再问（文字前加「刚才：」）
--   框正在问别的事 → 排队，返回 "queued"；正在问同一件事 → "busy"；弹出来了 → "shown"；这项已经定过（不是 nil）→ nil
LY.askQ = {}
local askFrame
function LY.OffHint() return L("（右侧『位面』页签可关）", " (turn off in the Layers tab)") end
local function askShow(key, opts, later)
    if not askFrame then
        local f = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(460, 100); f:SetPoint("TOP", UIParent, "TOP", 0, -170); f:SetFrameStrata("DIALOG")
        if f.SetBackdrop then
            f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            f:SetBackdropColor(0.04, 0.06, 0.1, 0.95); f:SetBackdropBorderColor(1, 0.82, 0.2, 0.9)
        end
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.text:SetPoint("TOPLEFT", 12, -12); f.text:SetWidth(410); f.text:SetJustifyH("LEFT")
        f.yes = ns.Button(f, "", 130, 22, function() LY.AskPick(true) end)
        f.yes:SetPoint("BOTTOMLEFT", 12, 28)
        f.no = ns.Button(f, "", 100, 22, function() LY.AskPick(false) end)
        f.no:SetPoint("LEFT", f.yes, "RIGHT", 8, 0)
        f.close = ns.Button(f, "×", 22, 20, function() LY.AskPick(nil) end)
        f.close:SetPoint("TOPRIGHT", -4, -4)
        f.foot = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        f.foot:SetPoint("BOTTOMLEFT", 12, 9); f.foot:SetJustifyH("LEFT")
        f.foot:SetText(L("以后可以在右侧『位面』页签 → 设置里改", "You can change this later in the Layers tab (right side) -> Settings"))
        askFrame = f
    end
    local t = opts.text or ""
    if later then t = L("刚才：", "Earlier: ") .. t end
    askFrame.key, askFrame.opts = key, opts
    askFrame.text:SetText(ns.EnSafe and ns.EnSafe(t) or t)
    askFrame.yes:SetText(opts.yes or L("以后都这样", "Always"))
    askFrame.no:SetText(opts.no or L("每次问我", "Ask me each time"))
    askFrame:Show()
    LY.Log("问一次 " .. key .. (later and "（脱战 / 排队后补问）" or ""))
end
local function askBusy() return askFrame ~= nil and askFrame.key ~= nil and askFrame:IsShown() end
local function askPush(key, opts)
    for i = #LY.askQ, 1, -1 do if LY.askQ[i].key == key then table.remove(LY.askQ, i) end end
    LY.askQ[#LY.askQ + 1] = { key = key, opts = opts }
end
function LY.AskNext()
    if askBusy() or inCombat() then return false end
    while #LY.askQ > 0 do
        local it = table.remove(LY.askQ, 1)
        if LY.DB()[it.key] == nil then askShow(it.key, it.opts, true); return true end
    end
    return false
end
function LY.AskOnce(key, opts)
    if LY.DB()[key] ~= nil then return nil end
    if askBusy() then
        if askFrame.key == key then return "busy" end
        askPush(key, opts)
        return "queued"
    end
    if inCombat() then askPush(key, opts); return "later" end
    askShow(key, opts, false)
    return "shown"
end
-- v = true「以后都…」/ false「每次问我」/ nil 右上 ×（这次先不定）
function LY.AskPick(v)
    local f = askFrame
    if not (f and f.key) then return end
    local key, opts = f.key, f.opts or {}
    f.key, f.opts = nil, nil
    f:Hide()
    local cb = opts.onClose
    if v == true then cb = opts.onYes elseif v == false then cb = opts.onNo end
    if v ~= nil then
        LY.DB()[key] = v
        local label = (v == true) and opts.yes or opts.no
        ns.Print(string.format(L("已记住：%s（以后可以在右侧『位面』页签 → 设置里改）", "Saved: %s (change it in the Layers tab -> Settings)"), tostring(label or "")))
    end
    LY.Log("问一次 " .. key .. " 选=" .. tostring(v))
    if cb then pcall(cb) end
    if ns.RefreshSettings then pcall(ns.RefreshSettings) end
    LY.dirty = true
    LY.AskNext()
end
LY._ask = function() return askFrame end

LY.lastAccept = nil
-- 11-13：会长 / 官员（集合发起人）的邀请，autoAccept 还是 nil → 不自动接，弹「问一次」；暴雪自己的邀请框照常在，这次由玩家自己点
function LY.AskAccept(inviter, why)
    local s = short(inviter)
    if not s or secret(s) then return nil end
    local LG = ns.LayerGuild
    local r = LG and LG.ranks and LG.ranks[s]
    local role = why
    if r == 0 then role = L("会长", "Guild leader")
    elseif r ~= nil and LG.IsOfficerRank and LG.IsOfficerRank(r) then role = L("官员", "Officer") end
    local at = now()
    return LY.AskOnce("autoAccept", {
        text = string.format(L("%s %s 邀请你组队（换层）。以后会长 / 官员的邀请要自动接受吗？", "%s %s invited you (layer hop). Auto-accept leader / officer invites from now on?"), tostring(role), s),
        yes = L("以后都自动接受", "Always accept"), no = L("每次问我", "Ask me each time"),
        onYes = function()
            -- 这次也接：邀请还挂着才接（已经进队 / 暴雪邀请框没了 / 过了 60 秒 = 只记住设置）
            if now() - at > LY.ASK_FRESH then return end
            if IsInGroup and IsInGroup() then return end
            if StaticPopup_Visible and not StaticPopup_Visible("PARTY_INVITE") then return end
            LY.OnInvite(inviter)
        end,
    })
end
function LY.OnInvite(inviter)
    local why, kind, ask = LY.AcceptReason(inviter)
    LY.Log("收到邀请 from=" .. tostring(short(inviter)) .. " 自动接受=" .. tostring(why or (ask and "先问一次") or "否"))
    if not why then
        if ask then LY.AskAccept(inviter, ask) end
        return false
    end
    if not AcceptGroup then return false end
    local ok = pcall(AcceptGroup)
    if ok and StaticPopup_Hide then pcall(StaticPopup_Hide, "PARTY_INVITE") end
    LY.lastAccept = { who = short(inviter), why = why, ok = ok, t = now() }
    -- 11-13「哪里关」：会长 / 官员这条（受 autoAccept 管）行末带「（右侧『位面』页签可关）」；自己发起的换层帮手那条不受开关管，不带
    if ok then ns.Print(L("已自动接受 ", "Auto-accepted invite from ") .. tostring(short(inviter)) .. L("（" .. why .. "）", " (" .. why .. ")") .. (kind == "officer" and LY.OffHint() or "")) end
    return ok
end

-- 邀请：⛔ 只许在按钮 OnClick 里调（硬件事件）；一下一个
LY.invited = {}
function LY.Invite(name)
    local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if not fn or not name then return false end
    local ok = pcall(fn, name)
    if ok then LY.invited[short(name)] = now() end
    LY.Log("发出邀请 to=" .. tostring(short(name)) .. " ok=" .. tostring(ok))
    return ok
end

-- ---------- 众包 ly（经更新器，非实时）：每张图每个北京小时见过几层 ----------
-- key = 地图:北京小时，val = zoneUID 的哈希（⛔ 不传原值、不传角色名 / 服务器名）；服务端按设备数数不同 val = 这个时段有几层
function LY.Hash(z)
    if not z then return nil end
    return string.format("%08x", (z * 2654435761) % 4294967296)
end
function LY.ObsLayer(map, z)
    if not (ns.Obs and ns.Obs.Add) or not map or not z then return false end
    local h = tonumber(date and date("!%H") or "0") or 0
    h = (h + 8) % 24
    return ns.Obs.Add("ly", tostring(map) .. ":" .. h, LY.Hash(z))
end
LY.OnChange(function(_, new, map) LY.ObsLayer(map, new); LY.Beat(true) end)

-- ---------- 事件 ----------
local ev = CreateFrame("Frame")
LY._ev = ev
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
elseif RegisterAddonMessagePrefix then pcall(RegisterAddonMessagePrefix, PREFIX) end
for _, e in ipairs({ "CHAT_MSG_ADDON", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "NAME_PLATE_UNIT_ADDED", "UPDATE_MOUSEOVER_UNIT",
    "PLAYER_TARGET_CHANGED", "PARTY_INVITE_REQUEST", "PLAYER_REGEN_ENABLED", "GUILD_ROSTER_UPDATE", "GROUP_ROSTER_UPDATE" }) do
    local valid = not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e)
    if valid then pcall(ev.RegisterEvent, ev, e) end
end

-- CHAT_MSG_ADDON 的来源：GUILD / 集合频道 / 公共频道（按频道名或编号对）
function LY.ViaOf(dist, chanName, chanIdx)
    if dist == "GUILD" then return "guild" end
    if dist == "WHISPER" then return "whisper" end
    if dist == "CHANNEL" then
        local nm = type(chanName) == "string" and chanName:lower() or nil
        local g = LY.GatherChannel()
        if g and ((nm and nm:find(g:lower(), 1, true)) or (chanIdx and chanIdx == chanIndex(g))) then return "gather" end
        if (nm and (nm:find("gifm", 1, true) or nm:find(PUB:lower(), 1, true))) or (chanIdx and LY.pubJoined and chanIdx == chanIndex(LY.pubJoined)) then return "pub" end
    end
    return nil
end

ev:SetScript("OnEvent", function(_, e, a1, a2, a3, a4, a5, a6, a7, a8)
    if e == "CHAT_MSG_ADDON" then
        if a1 ~= PREFIX then return end
        local via = LY.ViaOf(a3, a8, tonumber(a7))
        if via then pcall(LY.Handle, a2, a4, via) end
    elseif e == "NAME_PLATE_UNIT_ADDED" then pcall(LY.ReadUnit, a1)
    elseif e == "UPDATE_MOUSEOVER_UNIT" then pcall(LY.ReadUnit, "mouseover")
    elseif e == "PLAYER_TARGET_CHANGED" then pcall(LY.ReadUnit, "target")
    elseif e == "PARTY_INVITE_REQUEST" then pcall(LY.OnInvite, a1)
    elseif e == "PLAYER_REGEN_ENABLED" then
        LY.scanAt = now() + 1
        -- 11-13：战斗中碰到的「问一次」脱战后再问（等 2 秒，别一脱战就糊脸）
        if #LY.askQ > 0 then
            if C_Timer and C_Timer.After then C_Timer.After(2, function() pcall(LY.AskNext) end) else pcall(LY.AskNext) end
        end
    elseif e == "GROUP_ROSTER_UPDATE" then
        LY.rosterAt = now()   -- 11-06 跨地图对照：名单一动，之前那段「走过地图边界」和队友的旧层都不能拿来学
        -- 进队 / 退队：接下来 90 秒放宽换层门槛，并在 3 / 8 / 15 秒后重读目标和姓名板（传层要几秒）
        local inG = IsInGroup and IsInGroup() and true or false
        if inG ~= LY._wasInGroup then
            LY._wasInGroup = inG
            LY.groupAt = inG and now() or nil   -- 11-12：进队时刻（rosterAt 在队里会被名单小变动反复刷新，不能拿来算「进队多久」）
            LY.fastUntil = now() + 90
            if C_Timer and C_Timer.After then
                for _, d in ipairs({ 3, 8, 15 }) do
                    C_Timer.After(d, function()
                        pcall(LY.ReadAll)
                        if d == 15 then pcall(LY.Beat, true) end   -- 11-09 同队的人在页面上显示成不同层：进退队后补一次心跳，别等 60 秒
                    end)
                end
            end
        end
    elseif e == "PLAYER_ENTERING_WORLD" or e == "ZONE_CHANGED_NEW_AREA" then
        if e == "PLAYER_ENTERING_WORLD" then LY.pewAt = now() end   -- 传送 / 进出副本 / 读条进图：之前的层不能和之后的对上
        local wasInst = LY._inInst
        LY._inInst = inInstance()
        if wasInst and not LY._inInst then LY.leftInstanceAt = now() end
        LY.Reset()
        LY.scanAt = now() + 2
        if e == "PLAYER_ENTERING_WORLD" and C_Timer and C_Timer.After then
            -- GI-215：真正上线（isInitialLogin）记时间，等系统频道加完（CHAN_WAIT 秒后）再加公共频道；/reload、进出副本照旧 8 秒
            if a1 == true then LY.loginAt = now() end
            local wait = LY.ChanReady() and 8 or (LY.CHAN_WAIT - (now() - LY.loginAt) + 1)
            C_Timer.After(wait, function() pcall(LY.SyncPub); LY.Beat(true) end)
        else
            -- 换图：停稳 5 秒再换频道（一路跑过好几张图不跟着进进出出）
            LY._pubTok = (LY._pubTok or 0) + 1
            local tok = LY._pubTok
            if C_Timer and C_Timer.After then C_Timer.After(5, function() if LY._pubTok == tok and LY.ChanReady() then pcall(LY.SyncPub) end end) end
            LY.Beat(true)
        end
    end
    if LY.eventHooks[e] then for _, fn in ipairs(LY.eventHooks[e]) do pcall(fn, a1, a2, a3, a4) end end
    LY.dirty = true
end)
LY.eventHooks = {}
function LY.OnEvent(e, fn)
    LY.eventHooks[e] = LY.eventHooks[e] or {}
    table.insert(LY.eventHooks[e], fn)
end

local pumpAcc, scanAcc, uiAcc = 0, 0, 0
LY.tickHooks = {}
function LY.OnTick(fn) LY.tickHooks[#LY.tickHooks + 1] = fn end
local function onUpdate(_, el)
    el = el or 0
    pumpAcc, scanAcc, uiAcc = pumpAcc + el, scanAcc + el, uiAcc + el
    if pumpAcc >= 0.4 and #queue > 0 and now() >= (ns.GroupSendAt or 0) then
        pumpAcc = 0
        local item = queue[1]
        ns.GroupSendAt = now() + 0.4   -- 和组队插件共用发包节奏，别撞客户端限流
        if rawSend(item[1], item[2]) then table.remove(queue, 1); LY.sendError = nil
        else
            item.tries = (item.tries or 0) + 1
            LY.sendError = item[1]
            if item.tries >= 3 then table.remove(queue, 1) end
        end
    end
    if scanAcc >= 5 or (LY.scanAt and now() >= LY.scanAt) then
        scanAcc = 0; LY.scanAt = nil
        pcall(LY.ScanPlates)
    end
    if now() - lastBeat >= LY.BEAT then LY.Beat(true) end
    if uiAcc >= 1 then
        uiAcc = 0
        for _, fn in ipairs(LY.tickHooks) do pcall(fn) end
    end
end
ev:SetScript("OnUpdate", onUpdate)
LY._onUpdate = onUpdate

-- ---------- 斜杠命令 /gi layer … ----------
local function help()
    local C = ns.SlashHint or "/gi"
    ns.Print(L("位面：" .. C .. " layer 打开面板 · " .. C .. " layer lead 口令（会长：开服当晚还没公会时建集合频道）· "
        .. C .. " layer join 口令（会员加入）· " .. C .. " layer leave · " .. C .. " layer helper on|off 帮别人换层 · "
        .. C .. " layer pub on|off 按地图的公共频道 · " .. C .. " layerprobe 开服探针",
        "Layers: " .. C .. " layer panel · " .. C .. " layer lead CODE · " .. C .. " layer join CODE · " .. C .. " layer leave · "
        .. C .. " layer helper on|off · " .. C .. " layer pub on|off · " .. C .. " layerprobe"))
    -- 11-13 玩家「哪里关😳」：三个自动行为单独一行列清楚（右侧「位面」页签 → 设置 里也能勾）
    ns.Print(L("位面自动行为（第一次碰到时会问你一次）：" .. C .. " layer autohelp on|off 会员求助自动拉 · " .. C .. " layer accept on|off 会长 / 官员邀请自动接受 · "
        .. C .. " layer autoleave on|off 换过去后自动退队 · " .. C .. " layer auto on|off 三个一起；右侧『位面』页签 → 设置里也能改",
        "Layer automation (asked once the first time): " .. C .. " layer autohelp on|off · " .. C .. " layer accept on|off · "
        .. C .. " layer autoleave on|off · " .. C .. " layer auto on|off (all three); also in the Layers tab -> Settings"))
end
LY.Help = help

-- 11-13：三个自动行为的命令开关（存 true / false，之后不再问）
local AUTO_TEXT = {
    autoHelp = function(on) return on and L("公会会员求助：自动拉（不弹框）", "Guildmate requests: auto-invite") or L("公会会员求助：每次弹框问我", "Guildmate requests: ask each time") end,
    autoAccept = function(on) return on and L("会长 / 官员的组队邀请：自动接受", "Leader/officer invites: auto-accept") or L("会长 / 官员的组队邀请：不再自动接受", "Leader/officer invites: manual") end,
    autoLeave = function(on) return on and L("换过去后：自动退队", "After the move: leave the group") or L("换过去后：不自动退队", "After the move: stay in the group") end,
}
function LY.SetAuto(key, on)
    if not AUTO_TEXT[key] then return false end
    LY.DB()[key] = on and true or false
    if askFrame and askFrame.key == key then askFrame.key, askFrame.opts = nil, nil; askFrame:Hide(); LY.AskNext() end
    for i = #LY.askQ, 1, -1 do if LY.askQ[i].key == key then table.remove(LY.askQ, i) end end
    if ns.RefreshSettings then pcall(ns.RefreshSettings) end
    LY.dirty = true
    ns.Print(AUTO_TEXT[key](on) .. L("（右侧『位面』页签 → 设置里也能改）", " (also in the Layers tab -> Settings)"))
    return true
end

function LY.SetGather(code, lead)
    if code then
        code = tostring(code):gsub("[^%w]", ""):sub(1, 12)
        if code == "" then code = nil end
    end
    local old = LY.GatherChannel()
    if old and LeaveChannelByName then pcall(LeaveChannelByName, old) end
    LY.gather = code
    LY.gatherLead = (code and lead) and true or false
    LY.DB().gather, LY.DB().gatherLead = code, LY.gatherLead
    if code then joinChannel(LY.GatherChannel()); LY.Beat(true) end
    LY.dirty = true
end

ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.layer = function(rest, rawRest)
    local sub, arg = (rest or ""):match("^(%S*)%s*(.-)$")
    local rawArg = (rawRest or ""):match("^%S*%s*(.-)$") or arg
    local d = LY.DB()
    if sub == "" then ns.ToggleMain("layer")
    elseif sub == "lead" or sub == "join" then
        if rawArg == "" then help(); return end
        LY.SetGather(rawArg, sub == "lead")
        ns.Print(sub == "lead" and L("集合频道已建，口令「" .. rawArg .. "」发到群里让会员 /gi layer join " .. rawArg, "Gather channel up; members: /gi layer join " .. rawArg)
            or L("已加入集合频道「" .. rawArg .. "」", "Joined gather channel " .. rawArg))
    elseif sub == "leave" then LY.SetGather(nil); ns.Print(L("已退出集合频道", "Left gather channel"))
    elseif sub == "accept" and (arg == "on" or arg == "off") then LY.SetAuto("autoAccept", arg == "on")
    elseif sub == "autohelp" and (arg == "on" or arg == "off") then LY.SetAuto("autoHelp", arg == "on")
    elseif sub == "autoleave" and (arg == "on" or arg == "off") then LY.SetAuto("autoLeave", arg == "on")
    elseif sub == "auto" and (arg == "on" or arg == "off") then
        for _, k in ipairs(LY.ASK_KEYS) do LY.SetAuto(k, arg == "on") end
    elseif sub == "helper" and (arg == "on" or arg == "off") then
        d.helper = (arg == "on"); LY.Beat(true)
        ns.Print(d.helper and L("已打开「帮别人换到我这层」：收到请求会弹提示，点了才邀请", "Helping others hop: on (you click to invite)") or L("已关闭「帮别人换层」", "Helping others hop: off"))
    elseif sub == "pub" and (arg == "on" or arg == "off") then
        LY.SetPub(arg == "on")
        ns.Print(d.pub and L("已打开公共频道（每张图一个）：同图其他公会的插件用户也能互相看到层、互相拉", "Public channel on (one per map)")
            or L("已退出公共频道：位面只和公会会员互通（" .. (ns.SlashHint or "/gi") .. " layer pub on 重新加入）", "Public channel off (guild only)"))
    elseif sub == "probe" and ns.LayerProbe then ns.LayerProbe.Toggle()
    elseif sub == "log" then
        ns.ShowBox(L("换层记录", "Layer log"), L("复制全部发给开发者", "Copy all and send to the developer"), table.concat(d.log or {}, "\n"))
    elseif sub == "off" or sub == "on" then
        d.on = (sub == "on"); ns.Print(d.on and L("位面识别已打开", "Layer detection on") or L("位面识别已关闭", "Layer detection off"))
    else help() end
end
ns.ExtraSlash["位面"] = ns.ExtraSlash.layer

ns.modules[#ns.modules + 1] = function()
    local d = LY.DB()
    if d.gather then LY.gather = d.gather; LY.gatherLead = d.gatherLead and true or false end
end
