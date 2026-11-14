-- 组队 · 同任务的人（10-12 用户「这个叫组队功能」；原需求：用户「根据当前的任务，查看附近的人，实时展示在列表，最好能读取到共同任务的进度列在表格里，
--   然后可以一键邀请，优先筛选完成进度低于自己的」「做在右侧公会下方页签内」）
--
-- ⛔ 游戏不开放读取别人的任务进度（只有自己的任务日志）→ 唯一办法是插件之间互相广播：
--   装了本插件的玩家，每隔一会儿把「在哪个区域 + 任务日志里每个任务的进度」发出去（11-05 起：公会频道 + 静默插件密语，见下），
--   谁打开这个页签就能看到附近（同一区域）和自己有共同任务的人。没装插件的人看不到进度，也不会出现在列表里。
--   共享默认开，页签里一键关（/gi qm off）；只发区域 + 坐标（百分之一精度）+ 等级职业 + 任务 ID 与进度，不发别的。
--
-- 协议（前缀 GIFQM1，每条 ≤ 250 字节，客户端上限 255）：
--   H|gen|等级|职业|地图ID|x千分|y千分        心跳 / 位置
--   Q|gen|任务ID:百分比:已完成:需要,…        任务进度（任务多时分几条发，同一个 gen 合并）
--   R                                          请求：收到的人 1–4 秒内回一次（每人 15 秒最多回一次）
-- 收发都走 OnUpdate 队列（每 0.4 秒最多发 1 条），别撞客户端的插件消息限流。
-- ⛔ 11-05 改道（用户「直接改成公会加密语吧」）：《无限》客户端插件消息走自建频道恒返回 7 InvalidChannel
--   （玩家探针 CHANNEL 7 / GUILD 0 / WHISPER 0 / SAY 4 / YELL 4，GIForeverQM 根本进不去），不再进任何频道：
--   ① 公会频道：每轮发一次，公会里装了插件的人都收得到
--   ② 静默插件密语：身边看得到名字的玩家（页签开着时扫姓名板 / 说话的人）+ 已经互相认识的非公会玩家，每轮最多 WHISPER_FANOUT 人；
--      对方装了插件 → 收到后用密语回一份自己的进度（每人 60 秒最多回一次）→ 两边互相出现在列表里；
--      对方没装插件 → 插件密语不进聊天框，对方什么也看不到
--   密语给已下线的人游戏会回「没有找到玩家」：只密 2 分钟内见过的人，并把我们刚密过的人的这条系统提示过滤掉
-- ⛔ HOLD 中（_hold.txt），游戏里实测通过、用户点头后再移出。
local _, ns = ...; ns = _G.GearInsightForever or ns  -- 10-18 拆成按需加载的子插件：用主插件的命名空间（_G.GearInsightForever），子插件自己的 ... 是张新表
-- ⛔ 11-13 界面重构第 5 期：本文件只留「信标」—— 登录就加载（组队子插件 GearInsight_Forever_Group）：
--   收发 GIFQM1 消息、30 秒心跳、进城暂停、身边玩家扫描（姓名板 / 说话的人）、回别人的进度、解散道谢、组队工具自动自由拾取、右侧「组队」页签本身。
--   抽屉界面（列表 / 子页签内容 / 外观 / 钉住 / 一键组人 / 私聊 / 喊人 / 邀请记录）搬到按需加载的
--   GearInsight_Forever_GroupUI/QuestMatesUI.lua：点组队页签 / /gi qm / 小地图入口时才 LoadAddOn（QM.EnsureUI）。
--   界面没加载时收到的进度照样记进 QM.peers，界面一开就看得到。
--   ⛔ 协议、消息格式、节流、发送频率一个字节都没改（多人互通，新旧版本要互相看得到）：发送相关代码是从拆分前原样搬的，
--      scripts/gi_forever_group_beacon_test.py 拿拆分前的 QuestMates.lua 在同样输入下录 SendAddonMessage 序列逐条比对

local QM = {}
ns.QM = QM
local PREFIX = "GIFQM1"
local CHAN = "GIForeverQM"   -- 11-05 起不再加入（保留名字给 /gi qm probe 显示）
QM.WHISPER_FANOUT = 6       -- 每轮最多密几个非公会的人（插件消息限流：每个前缀大约每秒 1 条）
QM.REPLY_GAP = 60           -- 秒：收到别人的密语进度，同一个人多久内只回一次
local EXPIRE = 150         -- 秒：这么久没收到心跳就从列表里去掉
local MAX_PEERS, MAX_QUESTS, MAX_ROWS = 200, 60, 20
QM.MAX_PEERS, QM.MAX_QUESTS, QM.MAX_ROWS = MAX_PEERS, MAX_QUESTS, MAX_ROWS
local receiveTokens, receiveAt = 200, 0
QM.dropped = 0
QM.SEND_GAP = 1.0       -- 秒：插件频道消息最短发送间隔（11-04 从 0.4 放慢到 1.0：频道限流比队伍 / 公会严）
local SHOUT_GAP = 30       -- 秒：喊人（说话 / 大喊 / 本地频道）最短间隔；定时刷新也要用，放最前面
local BEAT = 30            -- 秒：心跳间隔（10-12 加了距离筛选：位置要新一点，45 → 30）
local peers = {}           -- [发送者] = { name, lvl, cls, map, x, y, seen, gen, quests = { [qid] = {p, f, r} } }
QM.peers = peers
local queue, gen = {}, 0
local lastSend, lastReply, dirtyAt = 0, -999, nil
local retryAt, retries = 0, 0
local L = function(cn, en) return ns.L(cn, en) end

local function now() return (GetTime and GetTime()) or 0 end
local function dbq()
    ns.db.qm = ns.db.qm or {}
    local q = ns.db.qm
    if q.share == nil then q.share = true end
    if q.onlyBehind == nil then q.onlyBehind = true end
    -- 10-12 用户「不在一定范围内没用啊」：只看本区域 → 距离范围（码）；0 = 本区域（不限距离）
    if q.range == nil then q.range = (q.onlyZone == false) and 0 or 100 end
    -- 10-12 用户「一定要打开姓名版」：组队列表开着时自动打开友方姓名板，关列表时还原（只还原自己打开的）
    -- 10-18 曾短暂改成默认不开（五轮粗测像是姓名板拖帧），随后 /gi perf plates 交替两轮对照推翻：
    --   友方姓名板开 / 关 95% 帧时间一样（10.4ms，20 多个姓名板），真正拖帧的是第三方姓名板插件（Ellesmere +3~4ms/帧，与友方开关无关）
    --   → 恢复默认自动开。platesV3：把 V2 那次替玩家改成的 false 还原一次；之后玩家 /gi qm plates off 的选择照常保留
    if not q.platesV3 then q.platesV3 = 1; q.platesV2 = nil; q.autoPlates = true end
    if q.autoPlates == nil then q.autoPlates = true end
    return q
end
local function safe(v) if v == nil or ns.Secret(v) then return nil end return v end

-- ---------- 自己的任务日志 ----------
-- 返回 { {id, title, lvl, f, r, p, done}, … }；新旧两套 API 都试，拿不到就空表
local function objectives(qid, logIndex)
    local f, r = 0, 0
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objs = pcall(C_QuestLog.GetQuestObjectives, qid)
        if ok and type(objs) == "table" and #objs > 0 then
            for _, o in ipairs(objs) do
                local nf, nr = tonumber(safe(o.numFulfilled)), tonumber(safe(o.numRequired))
                if nr and nr > 0 then f = f + math.min(nf or 0, nr); r = r + nr
                else r = r + 1; if safe(o.finished) then f = f + 1 end end
            end
            return f, r
        end
    end
    if GetNumQuestLeaderBoards and GetQuestLogLeaderBoard and logIndex then
        local okn, n = pcall(GetNumQuestLeaderBoards, logIndex)
        for j = 1, (okn and tonumber(n)) or 0 do
            local ok, text, _, done = pcall(GetQuestLogLeaderBoard, j, logIndex)
            text = ok and safe(text)
            local a, b
            if type(text) == "string" then a, b = text:match("(%d+)%s*/%s*(%d+)") end
            if a then f = f + math.min(tonumber(a), tonumber(b)); r = r + tonumber(b)
            else r = r + 1; if ok and done then f = f + 1 end end
        end
    end
    return f, r
end

function QM.MyQuests()
    local out = {}
    local n = 0
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then n = select(1, C_QuestLog.GetNumQuestLogEntries()) or 0
    elseif GetNumQuestLogEntries then n = select(1, GetNumQuestLogEntries()) or 0 end
    for i = 1, tonumber(n) or 0 do
        local title, lvl, isHeader, isComplete, qid
        if C_QuestLog and C_QuestLog.GetInfo then
            local ok, info = pcall(C_QuestLog.GetInfo, i)
            if ok and type(info) == "table" then
                title, lvl, isHeader, qid = safe(info.title), safe(info.level), info.isHeader, safe(info.questID)
                if qid and C_QuestLog.IsComplete then local okc, c = pcall(C_QuestLog.IsComplete, qid); isComplete = okc and c end
            end
        elseif GetQuestLogTitle then
            local ok, t1, t2, _, t4, _, t6, _, t8 = pcall(GetQuestLogTitle, i)   -- 经典：title, level, group, isHeader, collapsed, isComplete, freq, questID
            if ok then title, lvl, isHeader, isComplete, qid = safe(t1), safe(t2), t4, (t6 == 1 or t6 == true), safe(t8) end
        end
        qid = tonumber(qid)
        if qid and qid > 0 and not isHeader then
            local f, r = objectives(qid, i)
            local done = isComplete and true or (r > 0 and f >= r)
            local p = done and 100 or (r > 0 and math.floor(f / r * 100) or 0)
            out[#out + 1] = { id = qid, title = title or ("#" .. qid), lvl = tonumber(lvl) or 0, f = f, r = r, p = p, done = done }
        end
    end
    return out
end

-- ---------- 位置 ----------
local function myPos()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
    map = ok and safe(map)
    if not map then return nil end
    local x, y
    if C_Map.GetPlayerMapPosition then
        local okp, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
        if okp and pos and pos.GetXY then x, y = pos:GetXY(); x, y = safe(x), safe(y) end
    end
    return map, x, y
end
QM.MyPos = myPos

-- 同一张地图上的两点 → 码（地图有世界坐标就换算；没有就返回 nil，界面只写「同区域」）
-- 10-18 卡帧自测（scripts/gi_forever_perf_test.py）：200 人缓存时每次刷新列表要换算 400 次世界坐标（每次两个 C 调用 + 一个
--   CreateVector2D 表），收到新人的每条插件消息还要把 200 人全换算一遍 → 帧尖峰 + 大量垃圾。对方坐标是 0.001 精度发来的，
--   同一点反复出现 → 按「地图 + 万分之一坐标」缓存换算结果（数字键，不产生垃圾），满 4000 条整表清掉重来
local wpCache, wpCount = {}, 0
local function worldPos(map, x, y)
    local k = (map * 10001 + math.floor(x * 10000 + 0.5)) * 10001 + math.floor(y * 10000 + 0.5)
    local c = wpCache[k]
    if c == nil then
        c = false
        local ok, cont, w = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
        if ok and w and w.GetXY then
            local wx, wy = w:GetXY()
            if wx and wy then c = { cont, wx, wy } end
        end
        if wpCount >= 4000 then wpCache, wpCount = {}, 0 end
        wpCache[k] = c; wpCount = wpCount + 1
    end
    return c
end
QM._wpCache = function() return wpCache, wpCount end   -- 测试用
local function yards(map, x1, y1, x2, y2)
    if not (map and x1 and y1 and x2 and y2) then return nil end
    if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local a, b = worldPos(map, x1, y1), worldPos(map, x2, y2)
        if a and b and a[1] == b[1] then
            return math.floor(math.sqrt((a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2) + 0.5)
        end
    end
    -- 客户端换算不了：按地图百分比估（经典野外地图约 3000–4000 码宽，1% ≈ 35 码），界面写「约」
    return math.floor(math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) * 3500 + 0.5), true
end
QM.Yards = yards

-- ---------- 编码 ----------
-- 本次登录的随机编号：消息里带着它，收到带自己编号的 = 自己的回声（10-12 用户截图「为啥我自己都在里面」：
--   天裔名字带空格 / 服务器名后缀格式和 GetNormalizedRealmName 对不上 → 按名字比没认出自己）
local function newId()
    local t = {}
    for i = 1, 8 do t[i] = string.format("%x", math.random(0, 15)) end
    return table.concat(t)
end
QM.myId = newId()
local selfSenders = {}   -- 认出来是自己的发送者名（之后这个名字发来的一律不收）
QM._selfSenders = selfSenders

function QM.EncodeAll(quests, g, lvl, cls, map, x, y)
    local msgs = { table.concat({ "H", g, lvl or 0, cls or "", map or 0, x and math.floor(x * 1000) or -1, y and math.floor(y * 1000) or -1, QM.myId }, "|") }
    local cur = "Q|" .. g .. "|"
    local base = #cur
    for _, q in ipairs(quests) do
        local item = q.id .. ":" .. q.p .. ":" .. q.f .. ":" .. q.r
        if #cur + #item + 1 > 250 then msgs[#msgs + 1] = cur; cur = "Q|" .. g .. "|" end
        cur = cur .. ((#cur > base) and "," or "") .. item
    end
    if #cur > base or #quests == 0 then msgs[#msgs + 1] = cur end
    return msgs
end

-- At most 200 peers are retained; up to 20 short-lived candidates may be
-- assembling packets. Both pools retain at most MAX_QUESTS per sender.
local pending = {}
QM.pending = pending
local rankContext, rankAt, rankKey
local rankGen = 0   -- 打分上下文换一次 +1；同一代里每个人的分数记在 e 上，新人来一条消息不用把 200 人重算一遍（10-18 卡帧自测）
local function cacheRank(e)
    local at, cfg = now(), dbq()
    local key = tostring(cfg.questSel) .. ":" .. tostring(cfg.range) .. ":" .. tostring(cfg.onlyBehind)
    if rankContext and at - rankAt < 1 and key == rankKey and e._rkGen == rankGen and e._rkSeen == e.seen then
        return e._rkScore, e._rkDist
    end
    if not rankContext or at - rankAt >= 1 or key ~= rankKey then
        rankGen = rankGen + 1
        local mine = QM.MyQuests()
        local selected = QM.SelectedQuest and QM.SelectedQuest(mine)
        local byId = {}
        for _, q in ipairs(mine) do
            if not selected or selected.id == q.id then byId[q.id] = q end
        end
        local map, x, y = myPos()
        rankContext = { quests = byId, map = map, x = x, y = y }
        rankAt, rankKey = at, key
    end
    if at - (e.seen or 0) > EXPIRE then return -1, math.huge end
    local c = rankContext
    local same = c.map and e.map == c.map
    local distance = same and yards(c.map, c.x, c.y, e.x, e.y) or nil
    local near = QM.near and QM.near[(e.name or ""):match("^([^%-]+)") or e.name]
    if near then distance = math.min(distance or 40, near.yd) end
    local range = cfg.range or 100
    local inRange = range < 0 or (range == 0 and same) or (range > 0 and distance and distance <= range)
    local shared, behind = false, false
    for id, h in pairs(e.quests or {}) do
        local q = c.quests[id]
        if q then shared = true; if h[1] < 100 then behind = true end end
    end
    local eligible = shared and inRange and (not cfg.onlyBehind or behind)
        and not (QM.IsDeclined and QM.IsDeclined(e.name)) and not (QM.IsBusy and QM.IsBusy(e.name))
    local score = eligible and 4 or (shared and 3 or (inRange and 2 or (same and 1 or 0)))
    e._rkGen, e._rkSeen, e._rkScore, e._rkDist = rankGen, e.seen, score, distance or 1e9
    return score, distance or 1e9
end

function QM.Handle(sender, text, via)
    if type(sender) ~= "string" or type(text) ~= "string" or ns.Secret(sender) or ns.Secret(text) then return end
    if #sender > 128 or #text > 250 then return end
    local at = now()
    receiveTokens = math.min(200, receiveTokens + math.max(0, at - receiveAt) * 100)
    receiveAt = at
    if receiveTokens < 1 then QM.dropped = QM.dropped + 1; return end
    receiveTokens = receiveTokens - 1
    -- 自己发的回声：同服时 sender 不带服务器名，跨服带「-服务器」
    local me = UnitName and UnitName("player")
    local short, realm = sender:match("^([^%-]+)%-?(.*)$")
    if me and short == me then
        local myRealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
        if realm == "" or realm == myRealm then return end
    end
    if selfSenders[sender] then return end
    local kind = text:sub(1, 1)
    if #text > 250 or (kind ~= "H" and kind ~= "Q" and kind ~= "R") then return end
    local parts = {}
    for p in (text .. "|"):gmatch("(.-)|") do parts[#parts + 1] = p end
    -- 带自己编号的：心跳 H 第 8 段 / 请求 R 第 2 段 → 记下这个发送者名，把已经收进来的自己删掉
    if (kind == "H" and parts[8] == QM.myId) or (kind == "R" and parts[2] == QM.myId) then
        selfSenders[sender] = true
        pending[sender] = nil
        if peers[sender] then peers[sender] = nil; QM.dirty = true end
        return
    end
    if kind == "R" then
        if via == "WHISPER" then QM.ReplyTo(sender); return end   -- 密语来的请求：只回他一个人
        if now() - lastReply >= 15 then lastReply = now(); dirtyAt = now() + 1 + math.random() * 3 end
        return
    end
    local g = tonumber(parts[2])
    if not g or g < 1 or g > 9999 or g ~= math.floor(g) then return end
    local e = peers[sender] or pending[sender] or { name = sender, quests = {} }
    -- A new login can restart the counter. Remember retired sessions so delayed
    -- heartbeats cannot revive them; legacy Q packets still use modular ordering.
    if kind == "H" and parts[8] and parts[8] ~= "" then
        e.retired = e.retired or {}
        if e.retired[parts[8]] then return end
        if e.session and e.session ~= parts[8] then
            e.retired[e.session] = true; e.gen = nil; e.quests = {}
            e.retiredOrder = e.retiredOrder or {}
            e.retiredOrder[#e.retiredOrder + 1] = e.session
            if #e.retiredOrder > 8 then e.retired[table.remove(e.retiredOrder, 1)] = nil end
        end
        e.session = parts[8]
    end
    if e.gen and g ~= e.gen and (g - e.gen) % 9999 > 4999 then return end
    e.seen = now()
    if g ~= e.gen then e.gen = g; e.quests = {}; e.questReceived = false end   -- 新一轮：清掉旧进度（任务交了 / 放弃了的不会残留）
    if kind == "H" then
        e.lvl, e.cls, e.map = tonumber(parts[3]) or 0, parts[4] ~= "" and parts[4] or nil, tonumber(parts[5])
        local x, y = tonumber(parts[6]), tonumber(parts[7])
        e.x, e.y = (x and x >= 0) and x / 1000 or nil, (y and y >= 0) and y / 1000 or nil
    elseif kind == "Q" then
        e.questReceived = true
        local count = 0
        for _ in pairs(e.quests) do count = count + 1 end
        for item in (parts[3] or ""):gmatch("[^,]+") do
            local id, p, f, r = item:match("^(%d+):(%d+):(%d+):(%d+)$")
            if id then
                id = tonumber(id)
                if e.quests[id] or count < MAX_QUESTS then
                    if not e.quests[id] then count = count + 1 end
                    e.quests[id] = { tonumber(p), tonumber(f), tonumber(r) }
                end
            end
        end
    end
    e._rkGen = nil   -- 这条消息改了他的任务 / 位置：打分缓存作废
    e.via = via or e.via
    if kind == "H" and via == "WHISPER" then QM.ReplyTo(sender) end   -- 陌生人密来进度：回他一份，两边互相看得到
    if not peers[sender] then
        local count, victim, worst, worstDistance = 0, nil, nil, nil
        local priority, distance = cacheRank(e)
        for key, peer in pairs(peers) do
            count = count + 1
            local score, dist = cacheRank(peer)
            if not worst or score < worst or (score == worst and dist > worstDistance) then
                victim, worst, worstDistance = key, score, dist
            end
        end
        if count < MAX_PEERS or priority > worst or (priority == worst and distance < worstDistance) then
            if count >= MAX_PEERS then peers[victim] = nil end
            peers[sender] = e; pending[sender] = nil
        else
            -- A rejected heartbeat is not evidence that its later quest packets
            -- are irrelevant. Keep a small bounded staging area for assembly.
            local n, oldest, oldestAt = 0, nil, math.huge
            for key, peer in pairs(pending) do
                n = n + 1
                if (peer.seen or 0) < oldestAt then oldest, oldestAt = key, peer.seen or 0 end
            end
            if not pending[sender] and n >= 20 then pending[oldest] = nil end
            pending[sender] = e
            QM.dropped = QM.dropped + 1
        end
    end
    QM.dirty = true
end

-- ---------- 发送 ----------
local function chanIndex()
    if not GetChannelName then return nil end
    local id = GetChannelName(CHAN)
    id = tonumber(id)
    return (id and id > 0) and id or nil
end

-- 11-05 起不再加入 GIForeverQM（《无限》里插件消息走自建频道恒返回 7）；chanIndex 只给 /gi qm probe 看还在不在

-- 发送结果码 → 名字（Enum.SendAddonMessageResult 反查；没有这个枚举就只有数字）
local function codeName(code)
    if type(code) ~= "number" then return nil end
    local E = Enum and Enum.SendAddonMessageResult
    if type(E) == "table" then
        for k, v in pairs(E) do if v == code then return k end end
    end
    return nil
end
-- 失败原因分类：throttle 限流（放慢重试，不丢队列）/ lock 客户端暂时禁止插件通信 / chan 频道不可用（退出重进）/ other
local function failKind(name)
    if not name then return "other" end
    if name:find("Throttle") then return "throttle" end
    if name:find("Lockdown") then return "lock" end
    if name == "InvalidChannel" then return "chan" end
    return "other"
end
QM.CodeName, QM.FailKind = codeName, failKind

-- 一条出队消息 = { t = 正文, c = "GUILD" | "WHISPER", to = 密语对象 }
QM.whisperedAt = {}   -- [对方全名] = 上次密他的时间（过滤「没有找到玩家」用）
local function send(m)
    local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not fn then QM.lastCode, QM.lastName = nil, "NoApi"; return false end
    if m.c == "GUILD" and not (IsInGuild and IsInGuild()) then return true end   -- 退会了：这条直接丢掉
    local ok, result = pcall(fn, PREFIX, m.t, m.c, m.to)
    if m.c == "WHISPER" then QM.whisperedAt[m.to] = now() end
    QM.lastVia = m.c
    local idx = m.to
    local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0
    local good = ok and (result == nil or result == true or result == success)
    QM.lastIdx = idx
    if not ok then
        QM.lastCode, QM.lastName = nil, "Error"
    elseif result == nil or result == true then
        QM.lastCode, QM.lastName = success, "Success"
    else
        QM.lastCode, QM.lastName = tonumber(result), codeName(tonumber(result)) or tostring(result)
    end
    if good then QM.lastOkAt = now() end
    return good
end


function QM.SetSharing(enabled)
    dbq().share = enabled and true or false
    queue = {}; retries = 0; retryAt = 0; dirtyAt = nil
    if enabled then QM.Broadcast() end
    QM.dirty = true
end

local function short(n) return (type(n) == "string" and (n:match("^([^%-]+)") or n)) or "" end
-- 这一轮密谁：身边看得到名字的（近的在前）+ 已经认识的非公会玩家（最近收到的在前），去重、不含自己 / 公会的人，最多 WHISPER_FANOUT 个
function QM.WhisperTargets()
    local out, seen = {}, {}
    local me = UnitName and UnitName("player")
    local function add(full)
        if type(full) ~= "string" or full == "" or ns.Secret(full) or #out >= QM.WHISPER_FANOUT then return end
        local k = short(full)
        if seen[k] or k == me or selfSenders[full] or QM.IsGuildmate(full) then return end
        seen[k] = true
        out[#out + 1] = full
    end
    local near = {}
    for _, w in pairs(QM.near or {}) do if now() - (w.seen or 0) <= 120 then near[#near + 1] = w end end
    table.sort(near, function(a, b) if a.yd ~= b.yd then return a.yd < b.yd end return (a.name or "") < (b.name or "") end)
    local known = {}
    for k, e in pairs(peers) do if now() - (e.seen or 0) <= 120 then known[#known + 1] = { k, e.seen or 0 } end end
    table.sort(known, function(a, b) return a[2] > b[2] end)
    -- 已认识的先占一半名额（别让新面孔挤掉正在一起做任务的人），剩下的给身边的新面孔
    local half = math.ceil(QM.WHISPER_FANOUT / 2)
    for i = 1, math.min(half, #known) do add(known[i][1]) end
    for _, w in ipairs(near) do add(w.name) end
    for i = half + 1, #known do add(known[i][1]) end
    return out
end

-- 一份快照（H + Q…）→ 出队消息：公会一份 + 每个密语对象一份
local function fanout(msgs, only)
    if only then
        for _, t in ipairs(msgs) do queue[#queue + 1] = { t = t, c = "WHISPER", to = only } end
        return
    end
    if IsInGuild and IsInGuild() then
        for _, t in ipairs(msgs) do queue[#queue + 1] = { t = t, c = "GUILD" } end
    end
    for _, to in ipairs(QM.WhisperTargets()) do
        for _, t in ipairs(msgs) do queue[#queue + 1] = { t = t, c = "WHISPER", to = to } end
    end
end
QM._fanout = fanout

-- 11-12 用户「到主城关闭任务组队功能 / 停止扫描」：六大主城里人多、又没人在城里做任务 →
--   暂停 定时广播任务进度 / 回别人的进度 / 每秒扫身边玩家 / 记身边说话的人；出城自动恢复并补发一轮。
--   副本组队（找队伍 / 招人）、法师吃喝不受影响。设置页可关（qm.cityPause，nil = 开）。主城判断复用 CityPlates.InCity，2 秒缓存一次
QM.CITY_CHECK_GAP = 2
function QM.CityPauseOn() return dbq().cityPause ~= false end
function QM.SetCityPause(v) if v then dbq().cityPause = nil else dbq().cityPause = false end; QM.cityAt = nil; QM.dirty = true end
function QM.CityPaused()
    if not QM.CityPauseOn() then QM.cityIn = false; return false end
    local t = now()
    if QM.cityAt and t >= QM.cityAt and t - QM.cityAt < QM.CITY_CHECK_GAP then return QM.cityIn end
    local CP = ns.CityPlates
    local ok, inCity = pcall(function() return CP and CP.InCity and CP.InCity() end)
    local was = QM.cityIn
    QM.cityAt, QM.cityIn = t, (ok and inCity) and true or false
    if QM.cityIn and not was then
        queue = {}; retries = 0; retryAt = 0
        if not QM.cityNoted then
            QM.cityNoted = true
            ns.Print(L("进主城：任务组队已暂停扫描和共享（城里人多会卡），出城自动恢复。设置页「组队」栏可关这个功能",
                "In a capital: quest-mate scanning and sharing paused to save FPS, resumes when you leave (Settings to turn off)"))
        end
    elseif was and not QM.cityIn then
        dirtyAt = now()   -- 出城：补发一轮
    end
    QM.dirty = true
    return QM.cityIn
end

local function snapshot()
    local map, x, y = myPos()
    local _, cls = nil, nil
    if UnitClass then cls = select(2, UnitClass("player")) end
    local lvl = UnitLevel and UnitLevel("player") or 0
    return QM.EncodeAll(QM.MyQuests(), gen, lvl, cls, map, x, y)
end

function QM.Broadcast()
    if not dbq().share or QM.CityPaused() then return end
    -- 旧快照作废，只留还没发的「请求」
    local keep = {}
    for _, m in ipairs(queue) do if m.t:sub(1, 1) == "R" then keep[#keep + 1] = m end end
    queue = keep; retries = 0; retryAt = 0
    gen = (gen % 9999) + 1
    fanout(snapshot())
    lastSend = now()
end

-- 收到别人密过来的进度：回他一份自己的（60 秒内同一个人只回一次）
QM.repliedAt = {}
function QM.ReplyTo(sender)
    if not dbq().share or type(sender) ~= "string" or QM.CityPaused() then return end
    if now() - (QM.repliedAt[sender] or -999) < QM.REPLY_GAP then return end
    QM.repliedAt[sender] = now()
    if gen == 0 then gen = 1 end
    fanout(snapshot(), sender)
end

function QM.Request()
    for _, m in ipairs(queue) do if m.t:sub(1, 1) == "R" then return end end
    fanout({ "R|" .. QM.myId })
    QM.Broadcast()
end

QM.AUTO_RENDER_GAP = 3
local pumpAcc, beatAcc, uiAcc = 0, 0, 0
-- 10-18 /gi perf 实测（铁炉堡、公会 956 人）：每秒那轮把 扫身边 + 扫公会名单 + 重画列表 挤在同一帧，单帧 >5ms 累计 897 次（一卡一卡）
--   → 拆到相邻三帧：第 1 帧过期清理 + 扫身边，第 2 帧公会名单，第 3 帧重画
local uiStage = 0
local function onUpdate(_, el)
    el = el or 0
    pumpAcc, beatAcc, uiAcc = pumpAcc + el, beatAcc + el, uiAcc + el
    if #queue > 0 and not dbq().share then queue = {} end   -- 共享关了：没发完的也不发了
    if pumpAcc >= QM.SEND_GAP and #queue > 0 and now() >= retryAt and now() >= (ns.GroupSendAt or 0) then
        pumpAcc = 0
        do   -- 11-05 起不进频道：公会 / 密语直接发
            ns.GroupSendAt = now() + QM.SEND_GAP
            if send(queue[1]) then
                table.remove(queue, 1); retries = 0; retryAt = 0; QM.sendError = nil; QM.chanRebuilds = 0
            else
                QM.sendError = true
                local kind = failKind(QM.lastName)
                -- 11-04 探针：每种失败原因每次登录只在聊天框说一次（玩家不用敲命令，截图就能看到原因）
                if QM.printedFail ~= QM.lastName then
                    QM.printedFail = QM.lastName
                    ns.Print(L("组队共享发送失败：", "Group share send failed: ") .. tostring(QM.lastName) .. (QM.lastCode and ("(" .. QM.lastCode .. ")") or "")
                        .. "  " .. tostring(QM.lastVia) .. L("（/gi qm probe 看详情）", " (/gi qm probe for details)"))
                end
                if kind == "throttle" then
                    retryAt = now() + 6                       -- 被限流：等一会儿再发，队列留着
                elseif kind == "lock" then
                    retryAt = now() + 20                      -- 客户端暂时禁止插件通信（战斗 / 副本等）：等一会儿，队列留着
                elseif queue[1] and queue[1].c == "WHISPER" then
                    table.remove(queue, 1)   -- 密语对象不对（下线 / 改名）：只丢这一条，别卡住后面的
                else
                    retries = retries + 1; retryAt = now() + math.min(8, 2 ^ retries)
                    if retries >= 3 then queue = {}; retries = 0 end
                end
            end
            QM.dirty = true
        end
    end
    if dirtyAt and now() >= dirtyAt and now() - lastSend >= 10 then dirtyAt = nil; QM.Broadcast() end
    if beatAcc >= BEAT then beatAcc = 0; QM.Broadcast() end
    if uiAcc >= 1 then
        uiAcc = 0
        for k, e in pairs(pending) do if now() - (e.seen or 0) > 10 then pending[k] = nil end end
        for k, e in pairs(peers) do if now() - (e.seen or 0) > EXPIRE then peers[k] = nil; QM.dirty = true end end
        if QM.drawer and QM.drawer:IsShown() and not QM.CityPaused() then
            pcall(QM.ScanNear)
            if now() - QM.lastShout <= SHOUT_GAP + 1 then QM.dirty = true end   -- 喊人按钮倒计时
            if (dbq().questSel or "auto") == "auto" then QM.dirty = true end      -- 自动选最近的任务：边走边换
        end
        uiStage = 1
    elseif uiStage == 1 then
        uiStage = 2
        if QM.drawer and QM.drawer:IsShown() then pcall(QM.RebuildGuild) end   -- 同公会标注：只在抽屉开着时
    elseif uiStage == 2 then
        uiStage = 0
        -- 10-17「频繁刷新闪烁」：自动刷新最多 3 秒一次（喊人倒计时那几十秒照旧每秒）；点按钮的刷新不受限
        local gap = (now() - QM.lastShout <= SHOUT_GAP + 1) and 1 or QM.AUTO_RENDER_GAP
        if QM.dirty and QM.drawer and QM.drawer:IsShown() and now() - (QM.lastAutoRender or -999) >= gap then
            QM.dirty = false; QM.lastAutoRender = now(); QM.Render()
        end
    end
end

-- 「没有找到玩家」：我们 10 秒内密过的人下线了，游戏会在聊天框回一句 → 只过滤这一种、只过滤这些人（官方过滤器口子，不碰聊天框）
local function notFoundPat()
    local f = _G.ERR_CHAT_PLAYER_NOT_FOUND_S
    if type(f) ~= "string" then return nil end
    local pat = f:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", ".+")
    return "^" .. pat .. "$"
end
function QM.SysFilter(_, _, msg)
    if type(msg) ~= "string" or ns.Secret(msg) then return false end
    local pat = notFoundPat()
    if not (pat and msg:match(pat)) then return false end
    for name, t in pairs(QM.whisperedAt) do   -- 引号样式各客户端不同：直接看这句里有没有我们刚密过的名字
        if now() - t <= 10 and msg:find(short(name), 1, true) then return true end
    end
    return false
end
if ChatFrame_AddMessageEventFilter then pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_SYSTEM", QM.SysFilter) end

-- 10-18 用户截图「同工会的优先标注并置顶」：用游戏自带公会名单（短名）认人，不靠对方插件发公会名。
--   名单在 GUILD_ROSTER_UPDATE 时重建（事件很密 → 最多 10 秒一次），抽屉打开时向服务器要一次名单（60 秒内不重复要）
QM.guild = {}
local guildBuiltAt, guildAskedAt = -999, -999
function QM.RebuildGuild(force)
    -- 10-18 掉帧排查：大公会名单上千人，原来抽屉开着就每 10 秒整表扫一遍 → 只在名单真变了（GUILD_ROSTER_UPDATE）时 10 秒一次，否则 120 秒兜底
    if not force and now() - guildBuiltAt < (QM.guildDirty and 10 or 120) then return end
    guildBuiltAt = now(); QM.guildDirty = false
    local set = {}
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        local ok, total = pcall(GetNumGuildMembers)
        total = ok and tonumber(total) or 0
        for i = 1, total do
            local ok2, name = pcall(GetGuildRosterInfo, i)
            if ok2 and type(name) == "string" and not (ns.Secret and ns.Secret(name)) then set[name:match("^([^%-]+)") or name] = true end
        end
    end
    local changed = false
    for k in pairs(set) do if not QM.guild[k] then changed = true; break end end
    if not changed then for k in pairs(QM.guild) do if not set[k] then changed = true; break end end end
    QM.guild = set
    if changed then QM.dirty = true end
end
function QM.AskGuildRoster()
    if not (IsInGuild and IsInGuild()) or now() - guildAskedAt < 60 then return end
    guildAskedAt = now()
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
    QM.RebuildGuild(true)
end
function QM.IsGuildmate(name)
    if type(name) ~= "string" then return false end
    return QM.guild[name:match("^([^%-]+)") or name] == true
end

QM.invited = {}    -- [短名] = 邀请时刻；一键组人 2 分钟内不重复邀请同一个人

-- 拒绝过的人（10-12 用户「如果拒绝了，记录下缓存，然后下次点就跳过这个人，也从列表删掉」）：
--   存进存档（按角色，下线 / reload 还在），一键组人跳过、列表里也不再出现；/gi qm clear 清空
local function shortName(n) return (n or ""):match("^([^%-]+)") or n end
function QM.Declined()
    local q = dbq()
    local ck = (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
    q.declined = q.declined or {}
    q.declined[ck] = q.declined[ck] or {}
    return q.declined[ck]
end
-- 已经在别的队伍里（10-12 用户截图「心之钢已经加入了别的队伍」→「这种也缓存一下状态」→「也别弄掉，打个标记，放到下面的区域吧」）：
--   记进存档 30 分钟（他退队了还可能再组）；不藏，挪到列表最下面「已有队伍」一段，按钮换成「私聊」（请他拉你）。
--   拒绝过的一直藏，直到 /gi qm clear
local BUSY_SEC = 1800
function QM.Busy()
    local q = dbq()
    local ck = (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
    q.busy = q.busy or {}
    q.busy[ck] = q.busy[ck] or {}
    return q.busy[ck]
end
local function wallNow() return (time and time()) or 0 end
-- 这个人为什么被藏起来：拒绝过 / 在别的队伍（30 分钟内）/ nil
function QM.HiddenWhy(name)
    local sn = shortName(name)
    if QM.Declined()[sn] ~= nil then return "declined" end
    local b = QM.Busy()[sn]
    if b then
        if wallNow() - b <= BUSY_SEC then return "busy" end
        QM.Busy()[sn] = nil
    end
    return nil
end
function QM.IsDeclined(name) return QM.HiddenWhy(name) == "declined" end
function QM.IsBusy(name) return QM.HiddenWhy(name) == "busy" end

-- 11-06 用户「组队工具组队的时候自动自由拾取（副本不算）」：
--   我是队长 + 10 分钟内用组队工具邀请过人 + 有人进队 + 不在副本里 → 拾取方式改成自由拾取（一支队伍只改一次，改过就不再动，玩家手动改回去也不覆盖）。
--   副本里（IsInInstance）不改；开关 ns.db.qm.autoFFA（默认开），/gi 拾取 开 | 关
QM.FFA_WINDOW = 600
function QM.AutoFFAOn()
    local q = dbq()
    if q.autoFFA == nil then q.autoFFA = true end
    return q.autoFFA
end
function QM.SetAutoFFA(on) dbq().autoFFA = on and true or false end   -- 11-06 设置页开关
function QM.TryAutoFFA()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if n <= 1 then QM.ffaDone = nil; return false end
    if QM.ffaDone or not QM.AutoFFAOn() then return false end
    if not (QM.toolInviteAt and now() - QM.toolInviteAt <= QM.FFA_WINDOW) then return false end
    if not (UnitIsGroupLeader and UnitIsGroupLeader("player")) then return false end
    if IsInInstance then
        local inside, kind = IsInInstance()
        if inside or kind == "party" or kind == "raid" then return false end   -- 副本不算
    end
    QM.ffaDone = true
    local get = (C_PartyInfo and C_PartyInfo.GetLootMethod) or GetLootMethod
    local cur = get and select(2, pcall(get))
    if cur == "freeforall" or cur == 0 then return false end
    local set = (C_PartyInfo and C_PartyInfo.SetLootMethod) or SetLootMethod
    if not set or not pcall(set, "freeforall") then return false end
    ns.Print(L("组队工具组的队：拾取方式已改成自由拾取（副本里不改；/gi 拾取 关 可以关掉）",
        "Group from Group up: loot set to free-for-all (not in dungeons; /gi ffa off to disable)"))
    return true
end
do
    local f = CreateFrame("Frame")
    pcall(f.RegisterEvent, f, "GROUP_ROSTER_UPDATE")
    f:SetScript("OnEvent", function() pcall(QM.TryAutoFFA) end)
end
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash["拾取"] = function(rest, rawRest)
    rest = rest or ""
    local raw = rawRest or rest   -- 11-13 第 5 期：中文「开 / 关」看原样的参数（rest 转过小写）
    local q = dbq()
    if raw:find("关") or rest:find("off") then q.autoFFA = false
    elseif raw:find("开") or rest:find("on") then q.autoFFA = true end
    ns.Print(QM.AutoFFAOn() and L("组队工具组队自动自由拾取：开（/gi 拾取 关）", "Auto free-for-all for Group up: on (/gi ffa off)")
        or L("组队工具组队自动自由拾取：关（/gi 拾取 开）", "Auto free-for-all for Group up: off (/gi ffa on)"))
end
ns.ExtraSlash.ffa = ns.ExtraSlash["拾取"]

-- ---------- 身边没装插件的人（10-12 用户「加」→「能展示距离范围内的吗」→「不在一定范围内没用，不是一个任务」）----------
-- ⛔ 原来用 /who 查整个区域：几十个人，不知道远近、不知道做不做同一个任务，用户说没用 → 去掉。
-- 现在只认「看得见的」：友方姓名板（约 40 码）+ 目标 / 鼠标指向 / 焦点；CheckInteractDistance 4 = 28 码内。
-- 只列和我等级差 ≤ 4 的。⛔ 10-12 试过「站在任务目标区域 → 标可能同任务」，用户「可能做啥感觉没意义」→ 删了，没装插件的只写名字等级职业距离。
QM.near = {}
-- 10-12 用户「必须点中其他玩家才能出现在窗口？」—— 姓名板那一路在用户客户端里只有目标进得来，原因待 /gi qm probe 定：
--   ① 友方姓名板实际没显示  ② 姓名板单位的名字是保密值（safe() 丢掉了）。
-- ⛔ 不能用战斗记录补：12.0 引擎起插件注册 COMBAT_LOG_EVENT_UNFILTERED = ADDON_ACTION_FORBIDDEN，整个插件被禁用（Stats.lua 10-07）。
-- 补一路不靠姓名板的：身边 /说 /喊 /表情 的人（说话范围就是身边；GuildInsight 在同一客户端注册这些事件没问题）。
QM.heard = {}   -- [短名] = { name, seen, how }
QM.plateStat = { plates = 0, players = 0, secret = 0 }
local NEAR_UNITS = { "target", "mouseover", "focus" }
for i = 1, 40 do NEAR_UNITS[#NEAR_UNITS + 1] = "nameplate" .. i end
function QM.ScanNear()
    local out = {}
    local me = UnitName and UnitName("player")
    local st = { plates = 0, players = 0, secret = 0 }
    for _, u in ipairs(NEAR_UNITS) do
        local plate = u:sub(1, 9) == "nameplate"
        if plate and UnitExists and UnitExists(u) then st.plates = st.plates + 1 end
        if UnitExists and UnitExists(u) and UnitIsPlayer and UnitIsPlayer(u) and not (UnitIsUnit and UnitIsUnit(u, "player"))
            and (not UnitIsFriend or UnitIsFriend("player", u)) then
            local raw = GetUnitName and GetUnitName(u, true) or (UnitName and UnitName(u))
            if plate then st.players = st.players + 1; if raw ~= nil and ns.Secret(raw) then st.secret = st.secret + 1 end end
            local name = safe(raw)
            if type(name) == "string" and name ~= "" and name ~= me then
                local short = name:match("^([^%-]+)") or name
                local lvl = tonumber(safe(UnitLevel and UnitLevel(u))) or 0
                local cls, file
                if UnitClass then cls, file = UnitClass(u); cls, file = safe(cls), safe(file) end
                local yd = 40
                -- 11-12 用户「包满了捡东西不停弹框然后掉线」：BugGrabber 记了 33 次 ADDON_ACTION_BLOCKED 指向这里 ——
                --   CheckInteractDistance 在 12.x 引擎战斗中是受保护函数，pcall 挡不住「插件被禁止」，身边玩家列表每秒扫一次就弹一次
                --   → 战斗中一律不调（距离先按 40 码算，脱战再细分）
                if CheckInteractDistance and not (InCombatLockdown and InCombatLockdown()) then
                    local ok, c = pcall(CheckInteractDistance, u, 4)
                    if ok and c then yd = 28 end
                end
                if not out[short] or yd < out[short].yd then
                    out[short] = { name = name, lvl = lvl, cls = cls, file = file, yd = yd, seen = now() }
                end
            end
        end
    end
    QM.plateStat = st
    -- 60 秒内在身边说过话 / 喊过 / 做过表情的人（没有等级职业，等级显示 ?）
    for k, h in pairs(QM.heard) do
        if now() - (h.seen or 0) > 60 then QM.heard[k] = nil
        elseif not out[k] then out[k] = { name = h.name, lvl = 0, yd = 60, seen = h.seen, how = h.how } end
    end
    -- 刚离开视野的人留 8 秒，免得列表一闪一闪
    for k, v in pairs(QM.near) do if not out[k] and now() - (v.seen or 0) <= 8 then out[k] = v end end
    local changed = false
    for k in pairs(out) do if not QM.near[k] then changed = true end end
    for k in pairs(QM.near) do if not out[k] then changed = true end end
    QM.near = out
    if changed then QM.dirty = true end
    return out
end

-- 友方玩家姓名板的开关：10-12 用户 probe「nameplateShowFriends=nil」—— 《无限》客户端（12.0 引擎）没有这个设置名。
--   按顺序找第一个存在的；都不存在 = 不知道（返回 nil），界面提示按 Shift+V（游戏自带「显示友方姓名板」快捷键），不再当成「开着」。
local FRIEND_CVARS = { "nameplateShowFriendlyPlayers", "nameplateShowFriendlyPlayerUnits", "nameplateShowFriends" }
local function friendCVar()
    if not GetCVar then return nil end
    for _, k in ipairs(FRIEND_CVARS) do
        local ok, v = pcall(GetCVar, k)
        if ok and v ~= nil then return k, v end
    end
    return nil
end
-- true = 开着；false = 关着；nil = 不知道（客户端里找不到这个设置）
local function friendPlatesOn()
    local k, v = friendCVar()
    if not k then return nil end
    return v == "1"
end
QM.FriendPlatesOn = friendPlatesOn
QM.FriendCVar = friendCVar
-- 10-18 用户「如果用户怀疑卡是不是有个地方可以关，不要因为这个功能影响插件使用率」：
--   原来只有 /gi qm plates off 能关 → 设置页「组队」+ 组队抽屉「身边玩家」标题右边各放一个看得见的勾
function QM.AutoPlatesOn() return dbq().autoPlates and true or false end
function QM.SetAutoPlates(v)
    dbq().autoPlates = v and true or false
    if not v then pcall(QM.PlatesOnClose)                         -- 只还原我们替他开的那次
    elseif QM.drawer and QM.drawer:IsShown() then pcall(QM.PlatesOnOpen) end
    QM.dirty = true
    if QM.drawer and QM.drawer:IsShown() then pcall(QM.Render) end
end

-- 列表打开：友方姓名板关着 → 打开，记下是我们开的；列表关掉 → 只还原我们开的那次（玩家自己开着的不动）
-- ⛔ 战斗中不改设置（姓名板设置战斗中受保护）；找不到设置名就只提示 Shift+V
function QM.PlatesOnOpen()
    if not dbq().autoPlates then QM.PlatesOnClose(); return end   -- 关了自动开：以前我们替他开的那次顺手还原（只还原我们开的）
    if InCombatLockdown and InCombatLockdown() then return end
    local k, v = friendCVar()
    if QM.CityPlatesHolding(k) then return end   -- 11-13 第 5 期（§2.6）/ GI-244：主城里「进城关友方姓名板」正关着这一项 → 尊重它，不打开
    if k and v ~= "1" and SetCVar and pcall(SetCVar, k, "1") then
        dbq().platesWeOpened = k
        QM.dirty = true
    end
end
-- 11-13 第 5 期（§2.6）+ GI-244 合并后统一：姓名板在主城里归 CityPlates（主插件「进城关友方姓名板」）管，组队尊重它。约定：
--   · ns.db.qm.platesWeOpened = 组队替玩家打开的那一项设置名（组队写；组队关窗口时清；CityPlates 认出「原值是玩家开着的」时也会清 = 作废这笔）
--   · CityPlates 的账在 ns.db.cityPlates.off[设置名]（插件关的）/ .qm[设置名]（关的时候那份「开着」是组队的）—— 只由 CityPlates 读写，组队不碰
--   · 城里 CityPlates 正关着这一项、组队「进主城暂停」开着 → 组队不打开（打开了 CityPlates 也会关回去）；玩家关了「城里暂停」→ 让给组队
--   · 出城时谁的原值还原谁的由 CityPlates.Restore 按 .qm + platesWeOpened 判断，组队关窗口只管清自己的 platesWeOpened
function QM.CityPlatesHolding(k)
    local CP = ns.CityPlates
    if not (CP and CP.Enabled and CP.Off and CP.Enabled()) then return false end
    if not QM.CityPauseOn() then return false end
    k = k or friendCVar()
    return (k ~= nil and CP.Off(k)) and true or false
end
function QM.PlatesOnClose()
    local k = dbq().platesWeOpened
    if not k or (InCombatLockdown and InCombatLockdown()) then return end
    if SetCVar then pcall(SetCVar, k, "0") end
    dbq().platesWeOpened = nil
end

-- 列出客户端里所有和「姓名板 / 友方」有关的设置（probe 用：找真正的开关名）
function QM.PlateCVars()
    local out = {}
    local list
    if C_Console and C_Console.GetAllCommands then local ok, l = pcall(C_Console.GetAllCommands); list = ok and l or nil end
    for _, c in ipairs(list or {}) do
        local name = type(c) == "table" and c.command or nil
        if type(name) == "string" then
            local low = name:lower()
            if low:find("nameplate", 1, true) and (low:find("friend", 1, true) or low:find("player", 1, true)) then
                local ok, v = pcall(GetCVar, name)
                out[#out + 1] = name .. "=" .. tostring(ok and v or "?")
            end
        end
    end
    table.sort(out)
    return out, list ~= nil
end

-- 当前任务（10-12 用户「改成下拉菜单是不是更好，选择当前任务，最好可以自动选最接近的」）：
--   存档 qm.questSel = "auto"（默认：离我最近的没做完的任务）/ "all"（全部共同任务）/ 任务 ID
--   最近 = C_QuestLog.GetQuestsOnMap 给的任务地图点里离我最近的；客户端没这个接口 / 当前地图没点 → 游戏追踪的任务 → 全部
function QM.QuestDistances()
    local out = {}
    local map, x, y = myPos()
    if not (map and x and C_QuestLog and C_QuestLog.GetQuestsOnMap) then return out end
    local ok, list = pcall(C_QuestLog.GetQuestsOnMap, map)
    if not ok or type(list) ~= "table" then return out end
    for _, q in ipairs(list) do
        local qid, qx, qy = tonumber(safe(q.questID)), safe(q.x), safe(q.y)
        if qid and qx and qy then
            local yd = yards(map, x, y, qx, qy)
            if yd and (not out[qid] or yd < out[qid]) then out[qid] = yd end
        end
    end
    return out
end
function QM.TrackedQuestID()
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        local ok, id = pcall(C_SuperTrack.GetSuperTrackedQuestID)
        id = ok and tonumber(safe(id)) or nil
        if id and id > 0 then return id end
    end
    return nil
end
-- 返回 选中的任务（nil = 全部共同任务）, 模式 "auto" / "all" / "pick", 自动选时的距离
function QM.SelectedQuest(mine)
    mine = mine or QM.MyQuests()
    local mode = dbq().questSel or "auto"
    if mode == "all" then return nil, "all" end
    if mode ~= "auto" then
        for _, q in ipairs(mine) do if q.id == mode then return q, "pick" end end
        dbq().questSel = "auto"   -- 选的任务交掉 / 放弃了 → 回到自动
    end
    local dist = QM.QuestDistances()
    local best, bd
    for _, q in ipairs(mine) do
        local yd = dist[q.id]
        if yd and not q.done and (not bd or yd < bd) then best, bd = q, yd end
    end
    if best then return best, "auto", bd end
    local tid = QM.TrackedQuestID()
    if tid then for _, q in ipairs(mine) do if q.id == tid then return q, "auto" end end end
    return nil, "auto"
end

-- ---------- 11-13 第 5 期：信标 ↔ 抽屉界面 ----------
-- 喊人冷却：界面里点「喊人」才改；每秒那轮 OnUpdate 一直在读（界面没加载时也要有值，不然算术报错）
QM.lastShout = -999
-- 界面文件（QuestMatesUI.lua）要用的信标内部小工具：同一份函数 / 常量，不另抄一份
QM._b = { L = L, now = now, dbq = dbq, safe = safe, myPos = myPos, yards = yards, shortName = shortName, wallNow = wallNow,
    BEAT = BEAT, SHOUT_GAP = SHOUT_GAP, EXPIRE = EXPIRE, friendCVar = friendCVar, friendPlatesOn = friendPlatesOn }
-- 抽屉界面子插件装了没（装了才出子页签；已经加载了当然算）
function QM.UIAvailable()
    if QM.uiLoaded or ns.BuildDungeonPanel or ns.BuildGroupPanel then return true end
    return (ns.ModuleAvailable and ns.ModuleAvailable("groupui")) and true or false
end
-- 要用抽屉了：没加载就 LoadAddOn（主插件 UI.lua 的 ns.LoadModule，失败会在聊天框说一次）。返回界面是不是已经在了
function QM.EnsureUI()
    if QM.uiLoaded then return true end
    if not ns.LoadModule then return false end
    -- 11-13 用户截图「副本组队没建起来…/reload 一下再点」：组队窗口上次钉着开着 → 本文件末尾补发的 PLAYER_ENTERING_WORLD
    --   在本子插件还没载完时（DungeonChatCore / GroupParts 还没跑）就把界面子插件加载了 → DungeonChat.lua 找不到 ns.DungeonChat 整个跳过，
    --   之后怎么点副本组队都建不起来。→ 本子插件没载完（最后一个文件 GroupParts 才置 ns.GroupSync）先不加载界面
    if not (ns.DungeonChat and ns.GroupSync) then return false end
    local ok, loaded = pcall(ns.LoadModule, "groupui")
    return (ok and loaded and QM.uiLoaded) and true or false
end
-- 界面函数的占位：界面没加载时调到 → 先加载界面，再转给界面里的真函数（界面加载后用真函数把占位盖掉）
local function lazy(name)
    local stub
    stub = function(...)
        if QM.EnsureUI() and QM[name] ~= stub then return QM[name](...) end
    end
    QM[name] = stub
end
for _, n in ipairs({ "SetMode", "SetPinned", "TabClick", "OpenDrawer", "SlashUI" }) do lazy(n) end

function QM.Tab()
    local host = _G.GearInsightForeverMain
    return host and rawget(host, "_giQmTab") or nil
end

-- 子页签 / 顶上切换按钮的清单：法师吃喝（MageWater.lua）在才有第三个
-- 11-13 第 5 期：法师吃喝搬进按需加载的 GearInsight_Forever_GroupMage —— 没加载但装了也出这个子页签（点了再加载）
local function mageThere()
    if ns.MageWater and ns.MageWater.EmbedSettings then return true end
    return (ns.ModuleAvailable and ns.ModuleAvailable("mage")) and true or false
end
local function modeList()
    local t = { { "quest", L("任务组队", "Quest group"), L("同任务的人 · 附近 · 实时", "players on your quests - nearby - live") },
        { "dungeon", L("副本组队", "Dungeon group"), L("读你加入的所有聊天频道里的组队消息，一键申请（自动私聊）；也能一键发招人消息到频道", "Reads group posts from your chat channels; one-click apply, one-click recruit") } }
    if mageThere() then
        t[#t + 1] = { "mage", L("法师吃喝", "Mage food"), L("找法师要水 / 法师发水的全部开关（/gi 吃喝 也能开）", "All options for asking mages for water / handing it out (/gi water)") }
    end
    return t
end
QM.ModeList = modeList

-- 10-18 用户截图「任务组队，副本组队做两个折叠子TAB在组队下面」：照左栏大类（UI.lua GROUPS），
--   [附近任务][副本组队] 挂在右侧「组队」页签正下方，抽屉开着才展开、关了收起，下面别的右侧页签跟着让位。
--   10-18 用户截图（钉住状态下顶上还是两个按钮）「任务组队和副本组队拆成两个小TAB」：钉没钉住都一样，主面板开着就用子页签；
--   只有钉住 + 主面板关了（子页签跟着主面板藏起来）时，抽屉顶上才出那两个切换按钮兜底
local SUB_W, SUB_H, SUB_GAP = 86, 24, 4
-- 折叠子页签（副本组队 / 抽屉界面子插件没装 = 只有附近任务一个，不出子页签，和以前一样）
--   11-13 第 5 期：页签挂上时抽屉界面可能还没加载 → 按「装了没」建；界面后来才装上 / 法师吃喝后来才加载 → 再调一次补上缺的
function QM.EnsureSubTabs()
    local host, tab = _G.GearInsightForeverMain, QM.Tab()
    if not (host and tab) or not QM.UIAvailable() or not (ns.SegButton or ns.Button) then return end
    if type(rawget(tab, "_giSubs")) ~= "table" then tab._giSubs, tab._giSubByMode = {}, {} end
    local added = false
    for _, m in ipairs(modeList()) do
        if not tab._giSubByMode[m[1]] then
            local b = (ns.SegButton or ns.Button)(host, m[2], SUB_W, SUB_H, function() QM.SetMode(m[1]) end)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(m[2], 1, 0.82, 0)
                GameTooltip:AddLine(m[3], 1, 1, 1, true); GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:Hide()
            tab._giSubs[#tab._giSubs + 1] = b
            tab._giSubByMode[m[1]] = b
            added = true
        end
    end
    if added and QM.drawer then QM.SyncSubTabs() end
end
function QM.SyncSubTabs()
    local host, tab, d = _G.GearInsightForeverMain, QM.Tab(), QM.drawer
    local hostShown = host and host:IsShown() and true or false
    local subs = tab and rawget(tab, "_giSubs")
    local useSubs = subs and hostShown and true or false
    if d and not rawget(d, "modeBtns") and QM.BuildModeBtns then QM.BuildModeBtns(d) end   -- 抽屉只在界面加载后才有
    if d and rawget(d, "modeBtns") then
        for _, b in pairs(d.modeBtns) do b:SetShown(not useSubs) end
    end
    -- 11-10 用户截图：副本组队页标题还写「同任务的人 · 附近 · 实时」（抽屉先于副本组队建好时没换标题）→ 有子页签就按当前模式写
    if d and rawget(d, "title") then
        local DIM = "|cff8a93a6"
        local dungeon = dbq().mode == "dungeon"
        local btns = rawget(d, "modeBtns") and not useSubs
        local m = rawget(d, "mwOn") and L("法师吃喝", "Mage food") or dungeon and L("副本组队", "Dungeon group") or (subs and L("任务组队", "Quest group") or L("同任务的人 · 附近 · 实时", "players on your quests - nearby - live"))
        d.title:SetText(btns and L("组队", "Group up") or (L("组队", "Group up") .. "  " .. DIM .. m .. "|r"))
    end
    if not (host and tab and subs) then return end
    local open = d and d:IsShown() and hostShown and true or false
    for i, b in ipairs(subs) do
        b:ClearAllPoints(); b:SetPoint("TOPRIGHT", i == 1 and tab or subs[i - 1], "BOTTOMRIGHT", 0, -SUB_GAP)
        b:SetShown(open)
    end
    if ns.LayoutSideTabs then ns.LayoutSideTabs(host) end   -- 下面的页签让位（UI.lua 统一排，公会那组也展开时叠加）
end

local function attach()
    local host = _G.GearInsightForeverMain
    local W = ns.W or _G.GIWidgets
    if not host or not W or not W.SideTab or rawget(host, "_giQmTab") then return end
    -- 排在「公会」页签下面：公会页签（或 10-18 起没加载公会模块时的占位页签）先挂
    if not (rawget(host, "_giGuildTab") or rawget(host, "_giGuildStub")) then return end
    -- 10-12 用户「这个叫组队功能」：页签 / 标题都叫「组队」
    local tab = W.SideTab(host, L("组队", "Group up"), "Interface\\Icons\\INV_Misc_GroupNeedMore")
    host._giQmTab = tab
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(L("组队", "Group up"), 1, 0.82, 0)
        GameTooltip:AddLine(L("附近和你有共同任务的人（装了本插件的），实时进度，比你慢的在前，一键邀请", "Nearby players on your quests, live progress, one-click invite"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    QM.EnsureSubTabs()
    -- 11-13 第 5 期：点页签 = 加载抽屉界面（第一次）再开抽屉；开抽屉的代码原样在 QuestMatesUI.lua 的 QM.TabClick
    tab:SetScript("OnClick", function() QM.TabClick(tab) end)
    -- 公会页签被点开 → 收起这个抽屉
    local gt = rawget(host, "_giGuildTab")
    if gt and gt.HookScript then
        gt:HookScript("OnClick", function()
            if QM.drawer and QM.drawer:IsShown() and not dbq().pinned then QM.drawer:Hide(); W.SelectTab(tab, false) end
            QM.SyncSubTabs()
        end)
    end
    if host.HookScript then host:HookScript("OnShow", function() QM.SyncSubTabs() end) end   -- 钉住的抽屉还开着：主面板一开子页签就出来
    -- 主面板关掉：没钉住的抽屉跟着关；钉住的留在屏幕上
    if host.HookScript then host:HookScript("OnHide", function()
        if QM.drawer and not dbq().pinned then QM.drawer:Hide() end
        W.SelectTab(tab, false)
        QM.SyncSubTabs()
    end) end
    -- 钉着的抽屉是登录时独立建的（那时还没有页签），现在页签有了 → 页签亮起
    if QM.drawer and QM.drawer:IsShown() then W.SelectTab(tab, true) end
    if ns.LayoutSideTabs then ns.LayoutSideTabs(host) end   -- 11-12 第 2 期：右侧页签按固定顺序重排（组队登录就加载时它比位面后挂）
    if W.KeepSideTabsOnScreen then W.KeepSideTabsOnScreen(host) end
end

ns.QMAttach = attach   -- 10-18 按需加载：主插件 UI.lua ns.OpenModule 调
QM.Attach = attach

-- /gi 组队：打开主面板 + 右侧「组队」抽屉，并切到指定模式（真身在 QuestMatesUI.lua 的 QM.OpenDrawer：先加载界面）
function ns.OpenGroupDrawer(mode) return QM.OpenDrawer(mode) end
if hooksecurefunc and type(ns.ToggleMain) == "function" then
    hooksecurefunc(ns, "ToggleMain", function() pcall(attach) end)
end

-- ---------- 事件 ----------
local ev = CreateFrame("Frame")
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
elseif RegisterAddonMessagePrefix then pcall(RegisterAddonMessagePrefix, PREFIX) end
-- 11-13 第 5 期：CHAT_MSG_SYSTEM（邀请结果）/ GROUP_ROSTER_UPDATE（进队记结果、重画）/ GUILD_ROSTER_UPDATE（同公会标注）只有抽屉界面用得上，
--   界面加载时（QuestMatesUI.lua 末尾）再挂到这个框上；处理函数还是下面这一个。共享 / 回包 / 身边说话的人照旧登录就注册
for _, e in ipairs({ "CHAT_MSG_ADDON", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP",
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" }) do
    local valid = not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e)
    if valid then pcall(ev.RegisterEvent, ev, e) end
end
ev:SetScript("OnEvent", function(_, e, a1, a2, _, a4, ...)
    if e == "CHAT_MSG_ADDON" then
        -- ⛔ 第三个参数（消息来路 GUILD / WHISPER）一直是 nil：原来写的 a3 不在参数表里（恒为 nil）。11-13 第 5 期查过：
        --   传真值会激活 QM.Handle 里「密语来的 H → 回他一份完整进度 / 密语来的 R → 只回他一个人」两条路径，改变对外发送的消息（多发 / 少发），
        --   新旧版本插件之间的网络行为就不一样了 → 协议冻结期不修，利弊见第 5 期汇报，由用户拍板。保持 nil = 和所有已发版本行为一致
        if a1 == PREFIX then pcall(QM.Handle, a4, a2, nil) end
    elseif e == "CHAT_MSG_SYSTEM" then
        if QM.OnSystemMsg then pcall(QM.OnSystemMsg, a1) end   -- 邀请结果：界面里才有（只认组队工具 10 分钟内发的邀请）
    elseif e == "GUILD_ROSTER_UPDATE" then
        QM.guildDirty = true   -- 只记一笔，抽屉开着时由每秒那轮 RebuildGuild 处理（10 秒最多一次）
    elseif e == "GROUP_ROSTER_UPDATE" then
        QM.dirty = true   -- 有人进队 / 退队：列表和一键组人的人数跟着变
        -- 10 分钟内邀请过、现在在队里的 → 记录结果「进队了」
        for sn, t in pairs(QM.invited) do
            if now() - t <= 600 and UnitInParty and UnitInParty(sn) and QM.SetResult then pcall(QM.SetResult, sn, "joined") end
        end
    elseif e == "CHAT_MSG_SAY" or e == "CHAT_MSG_YELL" or e == "CHAT_MSG_EMOTE" or e == "CHAT_MSG_TEXT_EMOTE" then
        if not QM.CityPaused() then pcall(QM.Heard, a2, e, (select(8, ...))) end   -- 聊天事件第 12 个参数 = 说话人 GUID
    elseif e == "PLAYER_ENTERING_WORLD" then
        if C_Timer and C_Timer.After then C_Timer.After(6, function() dirtyAt = now() end) end
        if not QM._restored then
            QM._restored = true
            -- 上次钉着并开着 → 加载抽屉界面原位打开（11-13 第 5 期：没钉着就不加载界面）
            local q = dbq()
            -- 本子插件还没载完（登录时这里是本文件末尾直接调的）→ 下一帧再恢复钉住的抽屉
            local function restore()
                if q.pinned and q.open and QM.EnsureUI() then pcall(QM.RestorePinned) end
                if not (QM.drawer and QM.drawer:IsShown()) or not dbq().autoPlates then pcall(QM.PlatesOnClose) end
            end
            if (ns.DungeonChat and ns.GroupSync) or not (C_Timer and C_Timer.After) then restore() else C_Timer.After(0, restore) end
        end
    else
        dirtyAt = dirtyAt or (now() + 3)   -- 任务进度 / 区域 / 等级变了：3 秒后（且距上次 ≥10 秒）发一轮
        QM.dirty = true
    end
end)
ev:SetScript("OnUpdate", onUpdate)
QM._onUpdate = onUpdate   -- 测试用
QM._ev = ev               -- /gi perf 按事件计时用

-- 身边说话的人 → 记进 QM.heard（喊话范围大，也算：至少在同一片区域）
-- 10-17 用户截图「本人不要识别」：自己说话 / 做表情会把自己记进「身边玩家」。
--   旧判断只比 UnitName("player")：名字带服务器后缀、或名字是受保护值时比不上 → 加 GUID 和全名两道
local function isMe(sender, short, guid)
    if type(guid) == "string" and not ns.Secret(guid) and UnitGUID then
        local my = UnitGUID("player")
        if my and not ns.Secret(my) and guid == my then return true end
    end
    local my = UnitName and UnitName("player")
    if my and not ns.Secret(my) and (short == my or sender == my) then return true end
    local full = GetUnitName and GetUnitName("player", true)
    if full and not ns.Secret(full) and sender == full then return true end
    return false
end
QM.IsMe = isMe   -- 测试用

function QM.Heard(sender, ev, guid)
    if type(sender) ~= "string" or ns.Secret(sender) or sender == "" then return end
    local short = sender:match("^([^%-]+)") or sender
    if isMe(sender, short, guid) then return end
    QM.heard[short] = { name = sender, seen = now(), how = ev }
    QM.dirty = true
end

-- ---------- 斜杠：/gi qm [on|off|probe] ----------
-- 11-13 第 5 期：只改存档 / 看信标状态的子命令在这里直接办；要动抽屉的（say / yell / local / text / log / pin / 打开）先加载界面再转给 QM.SlashUI
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.qm = function(rest, rawRest)
    rest = rest or ""
    if rest == "tag on" or rest == "tag off" then
        dbq().noTag = (rest == "tag off") or nil
        ns.Print(rest == "tag on" and L("组队：私聊 / 喊人 / 道谢最前面加 [Gearinsight插件]", "Group up: messages prefixed with [GearInsight]")
            or L("组队：私聊 / 喊人 / 道谢不再加 [Gearinsight插件]", "Group up: no [GearInsight] prefix"))
    elseif rest == "quiet" or rest == "quiet on" or rest == "quiet off" then
        local on = rest ~= "quiet off" and not (rest == "quiet" and dbq().quietResult)
        dbq().quietResult = on or nil
        ns.Print(on and L("组队：不再提示「拒绝了邀请 / 已有队伍」（照样记下、一键组人照样跳过；qm quiet 再开）", "Group up: decline / busy notices muted")
            or L("组队：恢复提示「拒绝了邀请 / 已有队伍」", "Group up: decline / busy notices on"))
    elseif rest == "clear" then
        local t = QM.Declined()
        local n = 0
        for k in pairs(t) do t[k] = nil; n = n + 1 end
        local b = QM.Busy()
        for k in pairs(b) do b[k] = nil; n = n + 1 end
        QM.dirty = true
        ns.Print(string.format(L("组队：清空了 %d 个拒绝过邀请的人", "Group up: cleared %d declined players"), n))
    elseif rest == "plates off" or rest == "plates on" then
        QM.SetAutoPlates(rest == "plates on")
        ns.Print(rest == "plates on" and L("组队：列表开着时自动打开友方姓名板（关列表还原）", "Group up: auto friendly nameplates on")
            or L("组队：不再自动打开友方姓名板", "Group up: auto friendly nameplates off"))
    elseif rest == "off" or rest == "on" then
        QM.SetSharing(rest == "on")
        ns.Print(rest == "on" and L("组队：已开始共享你的任务进度", "Group up: sharing on") or L("组队：已停止发送；别人已收到的进度最多保留 150 秒", "Sharing stopped; received data expires within 150 seconds"))
    elseif rest == "probe" then
        local selected = QM.SelectedQuest(QM.MyQuests())
        local received, waiting, shared = 0, 0, 0
        for _, peer in pairs(peers) do
            if peer.questReceived then received = received + 1 else waiting = waiting + 1 end
            if selected and peer.quests[selected.id] then shared = shared + 1 end
        end
        ns.Print("QM tasks: selected=" .. tostring(selected and selected.id or "all")
            .. " received=" .. received .. " waiting=" .. waiting .. " selectedPeers=" .. shared
            .. " dropped=" .. QM.dropped)
        local has = function(v) return v and "|cff33ff99OK|r" or "|cffff6060--|r" end
        ns.Print("QM probe: C_QuestLog.GetInfo " .. has(C_QuestLog and C_QuestLog.GetInfo) .. " · GetQuestLogTitle " .. has(GetQuestLogTitle)
            .. " · GetQuestObjectives " .. has(C_QuestLog and C_QuestLog.GetQuestObjectives) .. " · SendAddonMessage " .. has((C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage)
            .. " · JoinTemporaryChannel " .. has(JoinTemporaryChannel) .. " · channel " .. tostring(chanIndex())
            .. " · map " .. tostring((myPos())) .. " · quests " .. #QM.MyQuests() .. " · peers " .. (function() local n = 0; for _ in pairs(peers) do n = n + 1 end; return n end)()
            .. " · InviteUnit " .. has((C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit))
        ns.Print("QM probe 发送: 最近结果 " .. tostring(QM.lastName or "（还没发过）") .. (QM.lastCode and ("(" .. QM.lastCode .. ")") or "")
            .. " · 方式 " .. tostring(QM.lastVia or "-") .. " · 公会 " .. tostring(IsInGuild and IsInGuild() and "在" or "不在")
            .. " · 本轮密语 " .. #QM.WhisperTargets() .. " 人 · 上次成功 " .. (QM.lastOkAt and string.format("%d 秒前", now() - QM.lastOkAt) or "从没成功")
            .. " · 队列 " .. #queue .. " · 间隔 " .. QM.SEND_GAP .. "s")
        -- 10-12「必须点中其他玩家才能出现」：姓名板能看到几个、几个是玩家、几个名字是保密值；友方姓名板设置
        QM.ScanNear()
        local ps = QM.plateStat or {}
        local nNear = 0
        for _ in pairs(QM.near) do nNear = nNear + 1 end
        ns.Print("QM probe 姓名板: 看到 " .. (ps.plates or 0) .. " 个 · 友方玩家 " .. (ps.players or 0) .. " · 名字保密 " .. (ps.secret or 0)
            .. " · 友方开关 " .. tostring((friendCVar())) .. "=" .. tostring(select(2, friendCVar()))
            .. " · 身边列表 " .. nNear .. " 人 · GetNamePlates " .. has(C_NamePlate and C_NamePlate.GetNamePlates))
        local pc, okList = QM.PlateCVars()
        ns.Print("QM probe 姓名板相关设置: " .. (okList and (#pc > 0 and table.concat(pc, " · ") or "（没有匹配的）") or "（客户端没有 C_Console.GetAllCommands）"))
    else
        QM.SlashUI(rest, rawRest)
    end
end

-- ---------- 10-16 队伍解散后道谢（用户「当组队解散的时候提示用户（可开关）是否感谢一路陪伴，话术你来定」）----------
-- 记队友：GROUP_ROSTER_UPDATE 时按完整名（名-服务器）记进队时间，离队时累计；一起待满 5 分钟才算「一路陪伴」。
-- 触发：从「有队友」变成「不在队伍里」（解散 / 自己退 / 被踢）；同一支队伍只问一次；战斗中不弹，脱战再弹；20 秒没点自动收起。
-- 发送：只在玩家点「发送感谢」后，每位队友一条私聊、间隔 1 秒。开关 ns.db.qm.thanks（默认开），/gi 感谢 开 | 关
-- 11-13 GI-247「有个猎人全需被踢了…发感谢的时候还是发给了这个人」：弹框里每人一个勾选框，只发勾上的；
--   默认勾 = 队伍结束时还在队里的（上一次非空名单 TH.last；结束前 END_GAP 秒内陆续走的 / 一起交完任务后才走的也算）；
--   中途离队 / 被踢的默认不勾。鼠标在框上时不自动收起。
local TH = { mates = {}, inGroup = false, asked = false, last = {} }
QM.Thanks = TH
TH.MIN = 300
-- 10-17 用户「感谢的带一下感谢你，德鲁伊~祝你快乐游戏…搞 5 个随机选项」：%s = 队友职业名（拿不到职业时用「朋友」）
-- 11-10 用户截图「改的更接地气」「去掉插件标识」：话术换成玩家之间的大白话，道谢不再带 [Gearinsight插件] 前缀
TH.LINES = {
    { "谢啦%s，这趟多亏你了，下回有任务还喊你！", "Thanks %s, couldn't have done it without you - I'll ping you next time!" },
    { "%s辛苦啦，跟你组队真舒服，下次接着组~", "Cheers %s, that was a smooth group - let's do it again~" },
    { "谢了%s，带飞了！祝你次次出货~", "Thanks %s, you carried! May every kill drop loot~" },
    { "多谢%s，配合太顺了，祝你早日60、天天出紫！", "Thanks %s, great teamwork - ding 60 soon and enjoy the purples!" },
    { "谢啦%s，组得开心！练级不卡怪，出门就出货~", "Thanks %s, good times! Smooth leveling and good drops~" },
}
-- 记得一起做的任务时，第 5 条换成带任务名的（仍是 5 选 1）
TH.QUEST_LINE = { "谢啦%s，「%s」一起搞定了！下次再组~", "Thanks %s, we got \"%s\" done! Group up again sometime~" }

function TH.On()
    local q = dbq()
    if q.thanks == nil then q.thanks = true end
    return q.thanks
end
function TH.Set(on)
    dbq().thanks = on and true or false
    ns.Print(on and L("队伍解散后会问你要不要向队友道谢（/gi 感谢 关 可以关掉）", "Will offer to thank teammates when a group ends (/gi thanks off to disable)")
        or L("已关闭解散道谢提示（/gi 感谢 开 可以打开）", "Thank-you prompt off (/gi thanks on to re-enable)"))
end

local function fullName(unit)
    local n, r = UnitName(unit)
    if not n or ns.Secret(n) or n == "" then return nil end
    if r and r ~= "" and not ns.Secret(r) then return n .. "-" .. r end
    return n
end
local function members()
    local present, n = {}, (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if n <= 0 then return present, n end
    local raid = IsInRaid and IsInRaid()
    local prefix, cnt = raid and "raid" or "party", raid and n or (n - 1)
    for i = 1, cnt do
        local u = prefix .. i
        if (not UnitExists or UnitExists(u)) and not (UnitIsUnit and UnitIsUnit(u, "player")) then
            local fn = fullName(u)
            if fn and fn ~= (UnitName("player")) then
                local file = UnitClass and select(2, UnitClass(u))
                present[fn] = (type(file) == "string" and not ns.Secret(file)) and file or true   -- 职业（道谢话术里叫「德鲁伊~」）
            end
        end
    end
    return present, n
end

-- 11-06 用户「目前主动退没弹」：/reload（装新文件）后 TH.mates 清零，同队时长从 reload 那一刻重算 → 不满 5 分钟就不问。
--   队友进队时间存进存档（GetTime 是开机时长，reload / 小退都不归零），reload 后接着算；超过 6 小时或时间倒退（重启过电脑）的作废
function TH.Restore()
    local saved = dbq().thMates
    if type(saved) ~= "table" or next(TH.mates) then return end
    local t = now()
    for fn, m in pairs(saved) do
        if type(m) == "table" and (not m.since or (m.since <= t and t - m.since <= 6 * 3600)) then m.restored = true; TH.mates[fn] = m end
    end
end
function TH.Save() dbq().thMates = TH.mates end

function TH.Roster()
    TH.Restore()
    local t = now()
    local present, n = members()
    for fn, cls in pairs(present) do
        local m = TH.mates[fn]
        if not m then m = { total = 0 }; TH.mates[fn] = m end
        if not m.since then m.since = t end
        m.restored = nil
        m.leftAt = nil
        if type(cls) == "string" then m.cls = cls end
    end
    for fn, m in pairs(TH.mates) do
        if not present[fn] and m.restored then TH.mates[fn] = nil   -- 存档里有、reload 后已不在队里的：不知道几时走的，不算
        elseif not present[fn] and m.since then m.total = m.total + (t - m.since); m.since = nil; m.leftAt = t end
    end
    if next(present) then
        if not TH.inGroup then TH.asked = false; TH.doneAt = nil; TH.doneQuest = nil end   -- 新的一支队伍
        -- GI-247 上一次非空名单：解散 / 自己退 / 被踢时先收到空名单，那一刻还在队里的人看这张
        TH.last = {}
        for fn in pairs(present) do TH.last[fn] = true end
        TH.inGroup = true
        local ok, q = pcall(QM.SelectedQuest)
        if ok and q and q.title then TH.quest = q.title end
    elseif TH.inGroup and n <= 1 then
        TH.inGroup = false
        TH.Ended()
    end
    TH.Save()
end

-- GI-247 结束前这么多秒内走的也算「打到最后」（打完副本大家一个个退，最后一个人走才算队伍结束）；更早走的 = 中途离队 / 被踢
TH.END_GAP = 90
function TH.Ended()
    local list, pick = {}, {}
    TH.cls, TH.info = {}, {}
    local t = now()
    local done = TH.RecentDone()
    local last = TH.last or {}
    for fn, m in pairs(TH.mates) do
        if (m.total or 0) >= TH.MIN or (done and m.doneAt == TH.doneAt) then
            list[#list + 1] = fn; TH.cls[fn] = m.cls
            local stay = last[fn] or (m.leftAt and (t - m.leftAt <= TH.END_GAP or (done and m.leftAt >= TH.doneAt)))
            pick[fn] = stay and true or false
            TH.info[fn] = { total = m.total or 0, left = not pick[fn] }
        end
    end
    -- 打到最后的排前面，再按名字
    table.sort(list, function(a, b) if pick[a] ~= pick[b] then return pick[a] end return a < b end)
    TH.mates = {}
    TH.last = {}
    local quest = done and TH.doneQuest or TH.quest
    TH.quest = nil
    if #list == 0 or TH.asked or not TH.On() then return end
    -- 自己点的退队：10-17 起不问，10-18 刚一起交了任务时例外；11-06 用户「主动退队，也要弹出感谢框」→ 不再区分，一律问
    TH.asked = true
    TH.lastDone = done
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        TH.pending = { list = list, quest = quest, pick = pick }   -- 脱战再弹
        return
    end
    TH.Show(list, quest, pick)
end

-- 职业代号（DRUID）→ 「德鲁伊」/「Druid」；拿不到 → 「朋友」/「friend」
function TH.ClassName(file)
    if type(file) == "string" and file ~= "" then
        local cls = file:sub(1, 1):upper() .. file:sub(2):lower()
        local cn = ns.Data and ns.Data.classCn and ns.Data.classCn[cls]
        if cn then return L(cn, cls) end
    end
    return L("朋友", "friend")
end

function TH.Message(quest, file)
    local who = TH.ClassName(file)
    -- 11-09 GI-210：设置页「自动私信内容」填了退队感谢就用自己的
    local mine = ns.MyWhisper and ns.MyWhisper("thanks", { ["职业"] = who, ["任务"] = quest })
    if mine then return mine end
    -- 11-10 用户「不要说德鲁伊，说老哥」：默认话术一律叫「老哥」（设置页自填的 {职业} 占位照旧给职业名）
    who = L("老哥", "mate")
    local pool = {}
    for _, l in ipairs(TH.LINES) do pool[#pool + 1] = string.format(L(l[1], l[2]), who) end
    if quest and quest ~= "" then pool[#pool] = string.format(L(TH.QUEST_LINE[1], TH.QUEST_LINE[2]), who, quest) end
    return pool[math.random(#pool)]
end

function TH.Send(list, quest)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return 0 end
    for i, name in ipairs(list) do
        local msg = TH.Message(quest, TH.cls and TH.cls[name])
        local fn = function() pcall(send, msg, "WHISPER", nil, name) end
        if i == 1 or not (C_Timer and C_Timer.After) then fn() else C_Timer.After(i - 1, fn) end
    end
    ns.Print(string.format(L("已向 %d 位队友道谢", "Thanked %d teammate(s)"), #list))
    return #list
end

-- ---- GI-247 弹框里的勾选名单 ----
TH.ROW_H = 20
TH.ROWS_MAX = 8          -- 最多同时显示 8 行（团队人多时滚轮翻）
TH.HOVER_RECHECK = 3     -- 20 秒到了鼠标还在框上：每 3 秒再看一次，移开才收起

function TH.Together(sec)
    local m = math.floor((sec or 0) / 60)
    if m < 1 then return L("一起不到 1 分钟", "<1 min together") end
    if m < 60 then return string.format(L("一起 %d 分钟", "%d min together"), m) end
    return string.format(L("一起 %d 小时 %d 分", "%dh %dm together"), math.floor(m / 60), m % 60)
end

local function thColored(fn, cls)
    local short = fn:match("^([^%-]+)") or fn
    local c = type(cls) == "string" and type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[cls]
    if type(c) == "table" and c.r then
        return string.format("|cff%02x%02x%02x%s|r", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), short)
    end
    return short
end

function TH.Picked(f)
    f = f or TH.frame
    local out = {}
    if not f or not f.pick then return out end
    for _, fn in ipairs(f.list or {}) do
        if f.pick[fn] then out[#out + 1] = fn end
    end
    return out
end

function TH.Refresh(f)
    f = f or TH.frame
    if not f then return end
    local on = #TH.Picked(f) > 0
    f.send.on = on
    if on then f.send:Enable() else f.send:Disable() end   -- 一个都没勾：按钮置灰
    for _, row in ipairs(f.rows) do
        if row.fn then row.cb:SetChecked(f.pick[row.fn] and true or false) end
    end
end

function TH.Toggle(fn)
    local f = TH.frame
    if not f or not f.pick or not fn then return end
    f.pick[fn] = not f.pick[fn]
    TH.Refresh(f)
end

local function thRow(f, i)
    local row = f.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, f.listc)
    row:SetSize(312, TH.ROW_H); row:SetPoint("TOPLEFT", 0, -(i - 1) * TH.ROW_H)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
    row.cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.cb:SetSize(20, 20); row.cb:SetPoint("LEFT", 0, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", 24, 0); row.name:SetJustifyH("LEFT")
    row.dur = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.dur:SetPoint("RIGHT", -2, 0); row.dur:SetJustifyH("RIGHT")
    row:SetScript("OnClick", function(self) TH.Toggle(self.fn) end)   -- 点整行也能勾
    row.cb:SetScript("OnClick", function() TH.Toggle(row.fn) end)
    f.rows[i] = row
    return row
end

function TH.Show(list, quest, pick)
    local f = TH.frame
    if not f then
        f = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(340, 128); f:SetFrameStrata("DIALOG"); f:SetPoint("CENTER", 0, 160)
        if f.SetBackdrop then
            f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            f:SetBackdropColor(0, 0, 0, 0.92)
        end
        f.t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.t:SetPoint("TOP", 0, -10)
        f.t:SetText(L("队伍解散了", "Group disbanded"))
        f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.body:SetPoint("TOPLEFT", 14, -30); f.body:SetPoint("RIGHT", -14, 0); f.body:SetJustifyH("CENTER"); f.body:SetSpacing(3)
        -- GI-247 勾选名单：超过 ROWS_MAX 行时滚轮翻
        f.scroll = CreateFrame("ScrollFrame", nil, f)
        f.scroll:SetPoint("TOPLEFT", 14, -50)
        f.listc = CreateFrame("Frame", nil, f.scroll)
        f.listc:SetSize(312, TH.ROW_H)
        if f.scroll.SetScrollChild then f.scroll:SetScrollChild(f.listc) end
        if f.scroll.EnableMouseWheel then f.scroll:EnableMouseWheel(true) end
        f.scroll:SetScript("OnMouseWheel", function(_, delta)
            local maxOff = math.max(0, (#(f.list or {}) - TH.ROWS_MAX) * TH.ROW_H)
            f.off = math.min(maxOff, math.max(0, (f.off or 0) - (delta or 0) * TH.ROW_H))
            if f.scroll.SetVerticalScroll then f.scroll:SetVerticalScroll(f.off) end
        end)
        f.more = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        f.more:SetPoint("TOP", f.scroll, "BOTTOM", 0, -2)
        f.rows = {}
        f.send = ns.Button(f, L("发送感谢", "Say thanks"), 100, 22, function()
            local picked = TH.Picked(f)
            if #picked == 0 then return end   -- 一个都没勾
            f:Hide(); pcall(TH.Send, picked, f.quest)
        end)
        f.send:SetPoint("BOTTOMLEFT", 12, 10)
        f.no = ns.Button(f, L("不用了", "No thanks"), 100, 22, function() f:Hide() end)
        f.no:SetPoint("BOTTOM", 0, 10)
        f.never = ns.Button(f, L("以后别问", "Don't ask again"), 100, 22, function() f:Hide(); TH.Set(false) end)
        f.never:SetPoint("BOTTOMRIGHT", -12, 10)
        f:Hide()
        TH.frame = f
    end
    f.list, f.quest = list, quest
    f.pick = {}
    for _, fn in ipairs(list) do
        if type(pick) == "table" then f.pick[fn] = pick[fn] and true or false else f.pick[fn] = true end
    end
    f.t:SetText(TH.lastDone and quest and quest ~= "" and string.format(L("刚一起完成了「%s」", "Just finished \"%s\" together"), quest)
        or L("队伍解散了", "Group disbanded"))
    f.body:SetText(L("要不要和刚才的队友说声谢谢？只发给勾上的", "Say thanks to your teammates? Only ticked ones get it"))
    -- 名单：职业色名字 + 一起待了多久；中途离队的标出来（默认不勾）
    local info = TH.info or {}
    for i, fn in ipairs(list) do
        local row = thRow(f, i)
        row.fn = fn
        row.name:SetText(thColored(fn, TH.cls and TH.cls[fn]))
        local inf = info[fn]
        local dur = inf and TH.Together(inf.total) or ""
        if inf and inf.left then dur = L("中途离队，", "left early, ") .. dur end
        row.dur:SetText(dur)
        row:Show()
    end
    for i = #list + 1, #f.rows do f.rows[i].fn = nil; f.rows[i]:Hide() end
    local vis = math.min(#list, TH.ROWS_MAX)
    f.off = 0
    f.scroll:SetSize(312, math.max(1, vis) * TH.ROW_H)
    f.listc:SetHeight(math.max(1, #list) * TH.ROW_H)
    if f.scroll.SetVerticalScroll then f.scroll:SetVerticalScroll(0) end
    local extra = #list - vis
    if extra > 0 then
        f.more:SetText(string.format(L("滚轮查看其余 %d 人", "Scroll for %d more"), extra)); f.more:Show()
    else
        f.more:SetText(""); f.more:Hide()
    end
    f:SetHeight(50 + vis * TH.ROW_H + (extra > 0 and 16 or 0) + 44)   -- 高度随人数变
    TH.Refresh(f)
    TH.shownAt = now()
    f:Show()
    TH.token = (TH.token or 0) + 1
    local my = TH.token
    if C_Timer and C_Timer.After then
        -- 20 秒没点自动收起；鼠标在框上（正在勾选）就先不收，移开后再收
        local function autoHide()
            if TH.token ~= my or not f:IsShown() then return end
            if f.IsMouseOver and f:IsMouseOver() then C_Timer.After(TH.HOVER_RECHECK, autoHide); return end
            f:Hide()
        end
        C_Timer.After(20, autoHide)
    end
end

-- 10-17 用户「我主动退队也弹出来」：自己退队不问。
--   ① 钩 LeaveParty / C_PartyInfo.LeaveParty（右键头像「离开队伍」、/leave 都走它们）记下时间；
--   ② 系统消息「你离开了队伍」兜底（钩子没挂上的客户端）：弹框 3 秒内收到就收起、撤回待弹
TH.SELF_GAP = 5
function TH.MarkSelfLeft() TH.leftAt = now() end
function TH.SelfLeft() return TH.leftAt and (now() - TH.leftAt) <= TH.SELF_GAP end
if hooksecurefunc then
    if type(LeaveParty) == "function" then pcall(hooksecurefunc, "LeaveParty", TH.MarkSelfLeft) end
    if C_PartyInfo and type(C_PartyInfo.LeaveParty) == "function" then pcall(hooksecurefunc, C_PartyInfo, "LeaveParty", TH.MarkSelfLeft) end
end
local function isSelfLeaveMsg(msg)
    if type(msg) ~= "string" or ns.Secret(msg) then return false end
    for _, k in ipairs({ "ERR_LEFT_GROUP_YOU", "ERR_RAID_YOU_LEFT" }) do
        local s = _G[k]
        if type(s) == "string" and s ~= "" and msg == s then return true end
    end
    return false
end

-- 10-18 刚一起交任务：QUEST_TURNED_IN（无限客户端没有就靠系统消息「××完成。」）记时间 + 当时在队里的人；
--   DONE_GAP 秒内退队 / 解散 → 这些人不受「一起满 5 分钟」限制，自己退队也问，标题和话术带任务名
TH.DONE_GAP = 180
function TH.QuestDone(title)
    if not TH.inGroup then return end
    local t = now()
    local same = TH.doneAt and t - TH.doneAt < 2   -- 事件 + 系统消息是同一次交任务：有名字就补上，别拿空的覆盖
    TH.doneAt = t
    if title and title ~= "" then TH.doneQuest = title elseif not same then TH.doneQuest = nil end
    local present = members()
    for fn, cls in pairs(present) do
        local m = TH.mates[fn]
        if not m then m = { total = 0, since = t }; TH.mates[fn] = m end
        if type(cls) == "string" then m.cls = cls end
        m.doneAt = t
    end
end
function TH.RecentDone() return TH.doneAt and (now() - TH.doneAt) <= TH.DONE_GAP or false end
-- 系统消息「××完成。」（ERR_QUEST_COMPLETE_S = "%s完成。"）→ 任务名；按 %s 前后两段原样比，不拼模式串
local function questDoneTitle(msg)
    local fmt = _G.ERR_QUEST_COMPLETE_S
    if type(msg) ~= "string" or ns.Secret(msg) or type(fmt) ~= "string" then return nil end
    local pre, post = fmt:match("^(.-)%%s(.*)$")
    if not pre or #msg <= #pre + #post then return nil end
    if msg:sub(1, #pre) ~= pre or (post ~= "" and msg:sub(-#post) ~= post) then return nil end
    return msg:sub(#pre + 1, #msg - #post)
end

local thEv = CreateFrame("Frame")
for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "CHAT_MSG_SYSTEM", "QUEST_TURNED_IN" }) do
    local valid = not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e)
    if valid then pcall(thEv.RegisterEvent, thEv, e) end
end
thEv:SetScript("OnEvent", function(_, e, msg)
    if e == "CHAT_MSG_SYSTEM" then
        if isSelfLeaveMsg(msg) then
            TH.MarkSelfLeft()   -- 11-06 主动退队也弹：收到「你离开了队伍」不再收起 / 取消待弹
        else
            local qt = questDoneTitle(msg)
            if qt then TH.QuestDone(qt) end
        end
    elseif e == "QUEST_TURNED_IN" then
        local id = tonumber(msg)
        local title = id and C_QuestLog and C_QuestLog.GetTitleForQuestID and select(2, pcall(C_QuestLog.GetTitleForQuestID, id))
        TH.QuestDone((type(title) == "string" and not ns.Secret(title)) and title or nil)
    elseif e == "PLAYER_REGEN_ENABLED" then
        local p = TH.pending
        TH.pending = nil
        if p and TH.On() then pcall(TH.Show, p.list, p.quest, p.pick) end
    else
        pcall(TH.Roster)
    end
end)
QM._thanksEvent = thEv:GetScript("OnEvent")   -- 测试用
QM._thEv = thEv

ns.ExtraSlash["感谢"] = function(rest, rawRest)
    -- 11-13 第 5 期：中文参数用原样的 rawRest 比（rest 是整体转过小写的，个别环境会把中文字节改坏）
    local raw = rawRest or rest
    if raw == "开" or rest == "on" then TH.Set(true)
    elseif raw == "关" or rest == "off" then TH.Set(false)
    else
        ns.Print((TH.On() and L("解散道谢提示：开", "Thank-you prompt: on") or L("解散道谢提示：关", "Thank-you prompt: off"))
            .. L("（/gi 感谢 开 | /gi 感谢 关）", " (/gi thanks on | off)"))
    end
end
ns.ExtraSlash.thanks = ns.ExtraSlash["感谢"]


-- 10-18 按需加载：登录早就过了，补跑一次「进入游戏」那段初始化
if IsLoggedIn and IsLoggedIn() then pcall(ev:GetScript("OnEvent"), ev, "PLAYER_ENTERING_WORLD") end

-- 10-18 按需加载：登录早就过了，补跑一次「进入游戏」那段初始化
if IsLoggedIn and IsLoggedIn() then pcall(thEv:GetScript("OnEvent"), thEv, "PLAYER_ENTERING_WORLD") end
