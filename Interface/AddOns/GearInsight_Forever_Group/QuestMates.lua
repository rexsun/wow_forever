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
        if q then shared = true; if h[1] < q.p then behind = true end end
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

local function snapshot()
    local map, x, y = myPos()
    local _, cls = nil, nil
    if UnitClass then cls = select(2, UnitClass("player")) end
    local lvl = UnitLevel and UnitLevel("player") or 0
    return QM.EncodeAll(QM.MyQuests(), gen, lvl, cls, map, x, y)
end

function QM.Broadcast()
    if not dbq().share then return end
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
    if not dbq().share or type(sender) ~= "string" then return end
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
        if QM.drawer and QM.drawer:IsShown() then
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

-- ---------- 列表数据：按当前选的任务 / 全部共同任务 ----------
-- 返回 rows = { { key, e, shared = {{q, mine, his}}, behind, dist, sameZone }, … } 已排序
QM._rank = {}   -- 上一次显示的先后（Render 写），排序同档时照旧
local function distBucket(d)
    if not d then return 1e6 end
    return math.floor(d / 100)
end
-- 显示用距离：100 码内取 5 码整，往外取 10 码整（数字不跟着每一步跳）
function QM.RoundYd(d)
    if not d then return nil end
    if d < 100 then return math.floor(d / 5 + 0.5) * 5 end
    return math.floor(d / 10 + 0.5) * 10
end
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
local GUILD_TAG = "|cff40ff40<" .. L("公会", "Guild") .. ">|r "

function QM.Rows(selQid)
    local mine = QM.MyQuests()
    local byId = {}
    for _, q in ipairs(mine) do byId[q.id] = q end
    local map, x, y = myPos()
    local cfg = dbq()
    local rows = {}
    for key, e in pairs(peers) do
        local shared, behind, ahead = {}, 0, 0
        for qid, h in pairs(e.quests or {}) do
            local q = byId[qid]
            if q and (not selQid or selQid == qid) then
                shared[#shared + 1] = { q = q, his = h }
                if h[1] < q.p then behind = behind + 1 elseif h[1] > q.p then ahead = ahead + 1 end
            end
        end
        local same = (map and e.map == map) and true or false
        local dist, approx
        if same then dist, approx = yards(map, x, y, e.x, e.y) end
        local short = key:match("^([^%-]+)") or key
        if QM.near[short] then dist, approx = math.min(dist or 40, QM.near[short].yd), false end   -- 姓名板看得到 = 就在身边
        local rg = cfg.range or 100
        local inRange = (rg < 0) or (rg == 0 and same) or (rg > 0 and dist ~= nil and dist <= rg)
        local keep = #shared > 0 and inRange and (behind > 0 or not cfg.onlyBehind) and not QM.IsDeclined(key) and not QM.IsBusy(key)
        if keep then
            table.sort(shared, function(a, b) return a.q.id < b.q.id end)
            rows[#rows + 1] = { key = key, e = e, shared = shared, behind = behind, ahead = ahead, same = same, dist = dist, approx = approx,
                guild = QM.IsGuildmate(e.name or key) }
        end
    end
    -- 同公会的置顶（10-18）→ 进度比我低的在前（用户「优先筛选完成进度低于自己的」）→ 比我低的任务多的在前 → 共同任务多 → 近的在前
    table.sort(rows, function(a, b)
        if a.guild ~= b.guild then return a.guild end
        if (a.behind > 0) ~= (b.behind > 0) then return a.behind > 0 end
        if a.behind ~= b.behind then return a.behind > b.behind end
        if #a.shared ~= #b.shared then return #a.shared > #b.shared end
        if a.same ~= b.same then return a.same end   -- 同区域的在别的区域前（没有世界坐标时距离都是空的）
        -- 10-17 用户「频繁刷新闪烁…可以稳定点不」：距离按 100 码一档比，同档保持上一次的先后（走两步不换位置）
        local da, db = distBucket(a.dist), distBucket(b.dist)
        if da ~= db then return da < db end
        local ra, rb = QM._rank[a.key] or 1e6, QM._rank[b.key] or 1e6
        if ra ~= rb then return ra < rb end
        return a.key < b.key
    end)
    return rows, mine
end

-- 收到了进度、但没进列表的人（10-12 用户截图「收到 1 位玩家的进度，范围内没有符合的」→「这个玩家是谁能看到吗」）
-- 返回 { {key, e, why, dist, approx, nShared}, … }，按距离排
function QM.FilteredPeers(shownKeys, selQid)
    local byId = {}
    for _, q in ipairs(QM.MyQuests()) do if not selQid or q.id == selQid then byId[q.id] = q end end
    local map, x, y = myPos()
    local cfg = dbq()
    local out = {}
    for key, e in pairs(peers) do
        if not (shownKeys and shownKeys[key]) and not QM.IsBusy(key) then
            local nShared, behind = 0, 0
            for qid, h in pairs(e.quests or {}) do
                local q = byId[qid]
                if q then nShared = nShared + 1; if h[1] < q.p then behind = behind + 1 end end
            end
            local same = (map and e.map == map) and true or false
            local dist, approx
            if same then dist, approx = yards(map, x, y, e.x, e.y) end
            local short = key:match("^([^%-]+)") or key
            if QM.near[short] then dist, approx = math.min(dist or 40, QM.near[short].yd), false end
            local rg = cfg.range or 100
            local why
            local hw = QM.HiddenWhy and QM.HiddenWhy(key)
            if hw == "declined" then why = L("拒绝过邀请", "declined before")
            elseif hw == "busy" then why = L("在别的队伍里", "in another group")
            elseif e.questReceived == false then why = L("任务数据待接收", "waiting for quest data")
            elseif nShared == 0 then why = selQid and L("未收到所选任务", "selected quest not received") or L("未收到共同任务", "no shared quest received")
            elseif not same and rg >= 0 then why = L("在别的区域", "other zone")
            elseif rg > 0 and dist == nil then why = L("距离未知", "distance unknown")
            elseif rg > 0 and dist > rg then why = string.format(L("超出 %d 码", "beyond %d yd"), rg)
            elseif behind == 0 and cfg.onlyBehind then why = L("进度未落后", "not behind you")
            else why = L("不符合筛选", "filtered") end
            out[#out + 1] = { key = key, e = e, why = why, dist = dist, approx = approx, same = same, nShared = nShared }
        end
    end
    table.sort(out, function(a, b)
        local da, db = a.dist or 1e9, b.dist or 1e9
        if da ~= db then return da < db end
        return a.key < b.key
    end)
    return out
end

-- ---------- 邀请 ----------
function QM.CanInvite(name)
    if UnitInParty and UnitInParty(name) then return false, L("已在队伍里", "In your group") end
    if UnitInRaid and UnitInRaid(name) then return false, L("已在团队里", "In your raid") end
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    local raid = IsInRaid and IsInRaid()
    if not raid and n >= 5 then return false, L("队伍满了", "Group is full") end
    if n > 0 and UnitIsGroupLeader and not UnitIsGroupLeader("player") and not (UnitIsGroupAssistant and UnitIsGroupAssistant("player")) then
        return false, L("你不是队长", "You are not the leader")
    end
    return true
end

QM.invited = {}    -- [短名] = 邀请时刻；一键组人 2 分钟内不重复邀请同一个人

-- ---------- 邀请记录（10-12 用户「邀请过的也记录下，可以存下他们的任务进度快照」）----------
-- 存档按角色，最新在前，最多 200 条：{ n 名字, t 时间(time()), r 结果 invited/joined/declined/busy, lvl, cls, map,
--   quests = { [任务ID] = { 他的百分比, 已完成, 需要, 任务名, 我当时的百分比 } } }（只有装了插件的人有任务快照）
local HIST_MAX = 200
function QM.History()
    local q = dbq()
    local ck = (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
    q.history = q.history or {}
    q.history[ck] = q.history[ck] or {}
    return q.history[ck]
end
local function histNow() return (time and time()) or 0 end
function QM.RecordInvite(name)
    local sn = (name or ""):match("^([^%-]+)") or name
    local e
    for k, v in pairs(peers) do if (k:match("^([^%-]+)") or k) == sn then e = v; break end end
    local w = QM.near and QM.near[sn]
    local rec = { n = name, t = histNow(), r = "invited", lvl = (e and e.lvl) or (w and w.lvl) or 0,
        cls = (e and e.cls) or (w and w.file) or nil, map = e and e.map or nil, quests = {} }
    if e and e.quests then
        local mine = {}
        for _, q in ipairs(QM.MyQuests()) do mine[q.id] = q end
        for qid, h in pairs(e.quests) do
            local mq = mine[qid]
            rec.quests[qid] = { h[1], h[2], h[3], mq and mq.title or nil, mq and mq.p or nil }
        end
    end
    local H = QM.History()
    table.insert(H, 1, rec)
    while #H > HIST_MAX do table.remove(H) end
    return rec
end
-- 最近一条这个人的记录（结果回写用）
function QM.LastRecord(name)
    local sn = (name or ""):match("^([^%-]+)") or name
    for _, rec in ipairs(QM.History()) do
        if ((rec.n or ""):match("^([^%-]+)") or rec.n) == sn then return rec end
    end
end
function QM.SetResult(name, r)
    local rec = QM.LastRecord(name)
    if rec and histNow() - (rec.t or 0) <= 600 then rec.r = r; rec.rt = histNow() end
end
local RESULT_TXT = { invited = { "已邀请", "invited" }, joined = { "进队了", "joined" }, declined = { "拒绝了", "declined" }, busy = { "已有队伍", "in a group" } }
function QM.ResultText(r) local t = RESULT_TXT[r or ""]; return t and L(t[1], t[2]) or (r or "") end
local function ago(t)
    local m = math.floor((histNow() - (t or 0)) / 60)
    if m < 1 then return L("刚刚", "just now") elseif m < 60 then return m .. L(" 分钟前", " min ago")
    elseif m < 1440 then return math.floor(m / 60) .. L(" 小时前", " h ago") end
    return math.floor(m / 1440) .. L(" 天前", " d ago")
end
QM.Ago = ago
-- 悬停里加一行「上次邀请：N 分钟前 · 结果」
function QM.TipLastInvite(name)
    local rec = QM.LastRecord(name)
    if rec and GameTooltip then
        GameTooltip:AddLine(string.format(L("上次邀请：%s · %s", "Last invite: %s - %s"), ago(rec.t), QM.ResultText(rec.r)), 0.9, 0.75, 0.4)
    end
end
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
function QM.Invite(name, quiet)
    local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if not fn then return false end
    local ok = pcall(fn, name)
    if ok then
        QM.invited[shortName(name)] = now()
        pcall(QM.RecordInvite, name)
        if not quiet then ns.Print(L("已邀请 ", "Invited ") .. name) end
    end
    return ok
end

-- 一键组人（10-12 用户「来个一键组人功能，直接能邀请附近的玩家」）：
--   按列表顺序（装了插件、范围内、比我慢的在前 → 身边没装插件的）邀请，邀请人数 = 队伍空位；
--   邀请顺序 = 距离从近到远（装没装插件混排）；跳过：已在队伍里 / 2 分钟内邀请过 / 拒绝过（存档）。不是队长、队伍满了 → 不发。
function QM.OpenSlots()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if IsInRaid and IsInRaid() then return math.max(0, 40 - n) end
    return math.max(0, 5 - math.max(n, 1))
end
function QM.InviteCandidates(names)
    local out, seen = {}, {}
    local slots = QM.OpenSlots()
    for _, name in ipairs(names or {}) do
        local sn = shortName(name)
        if #out >= slots then break end
        if not seen[sn] and not (UnitInParty and UnitInParty(sn)) and not (UnitInRaid and UnitInRaid(sn))
            and now() - (QM.invited[sn] or -999) > 120 and not QM.IsDeclined(sn) and not QM.IsBusy(sn) then
            seen[sn] = true
            out[#out + 1] = name
        end
    end
    return out
end
function QM.InviteAll(names)
    local can, why = QM.CanInvite("")
    if not can then ns.Print("|cffff6060" .. L("一键组人：", "Group up: ") .. why .. "|r"); return 0 end
    local list = QM.InviteCandidates(names)
    for _, name in ipairs(list) do QM.Invite(name, true) end
    if #list > 0 then
        ns.Print(string.format(L("一键组人：已邀请 %d 人 —— %s", "Group up: invited %d - %s"), #list, table.concat(list, "、")))
    else
        ns.Print(L("一键组人：列表里没有可邀请的人（都邀请过 / 拒绝过 / 已在队里）", "Group up: nobody left to invite"))
    end
    QM.dirty = true
    return #list
end

-- 拒绝邀请：系统消息「%s 拒绝了你的组队邀请」→ 10 分钟内一键组人跳过他
-- 系统消息 → 状态：拒绝了组队邀请（一直藏）/ 已经在别的队伍里（藏 30 分钟）。格式串取客户端自己的全局文字，中英文客户端都认。
local sysPats
local function toPattern(fmt)
    if type(fmt) ~= "string" or not fmt:find("%%s") then return nil end
    -- 先转义正则特殊字符，再把格式里的「%s」换成捕获组（⛔ 匹配 %s 本身的模式是 "%%s"，不是 "%%%%s"）
    local pat = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    pat = pat:gsub("%%s", "(.+)")
    return "^" .. pat .. "$"
end
function QM.OnSystemMsg(msg)
    if type(msg) ~= "string" or ns.Secret(msg) then return end
    if not sysPats then
        sysPats = {}
        local d = toPattern(_G.ERR_DECLINE_GROUP_S)
        if d then sysPats[#sysPats + 1] = { d, "declined" } end
        local g = toPattern(_G.ERR_ALREADY_IN_GROUP_S)
        if g then sysPats[#sysPats + 1] = { g, "busy" } end
    end
    for _, sp in ipairs(sysPats) do
        local who = msg:match(sp[1])
        if who then
            local sn = shortName(who)
            QM.invited[sn] = nil
            QM.dirty = true
            pcall(QM.SetResult, sn, sp[2])
            if sp[2] == "declined" then
                QM.Declined()[sn] = wallNow()
                ns.Print(string.format(L("组队：%s 拒绝了邀请，已记下，以后不再列出、一键组人也跳过（%s qm clear 清空）",
                    "Group up: %s declined - hidden from now on (%s qm clear to reset)"), sn, ns.SlashHint or "/gif"))
            else
                QM.Busy()[sn] = wallNow()
                ns.Print(string.format(L("组队：%s 已经有队伍了，挪到列表下面「已有队伍」，可以私聊请他拉你",
                    "Group up: %s is already in a group - moved to \"In a group\"; whisper to ask for an invite"), sn))
            end
            return
        end
    end
end

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
                if CheckInteractDistance then
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

-- 显示用：身边、等级差 ≤ 4、不在插件列表 / 队伍里；近的在前，等级近的在前
function QM.NearRows()
    local known = {}
    for k in pairs(peers) do known[k:match("^([^%-]+)") or k] = true end
    local myLv = UnitLevel and UnitLevel("player") or 0
    local out = {}
    for short, w in pairs(QM.near) do
        if not known[short] and not (QM.IsMe and QM.IsMe(w.name or short, short)) and not (UnitInParty and UnitInParty(short)) and not QM.IsDeclined(short) and not QM.IsBusy(short)
            and (w.lvl == 0 or math.abs(w.lvl - myLv) <= 4) then
            out[#out + 1] = { name = w.name, lvl = w.lvl, cls = w.cls, file = w.file, yd = w.yd, how = w.how, guild = QM.IsGuildmate(w.name or short) }
        end
    end
    table.sort(out, function(a, b)
        if a.guild ~= b.guild then return a.guild end   -- 同公会置顶（10-18）
        if a.yd ~= b.yd then return a.yd < b.yd end
        local da, db = math.abs(a.lvl - myLv), math.abs(b.lvl - myLv)
        if da ~= db then return da < db end
        return a.name < b.name
    end)
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
    if k and v ~= "1" and SetCVar and pcall(SetCVar, k, "1") then
        dbq().platesWeOpened = k
        QM.dirty = true
    end
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

-- ---------- 界面：右侧「组队」页签 + 抽屉 ----------
local DW, PAD, ROW_H = 430, 12, 30
-- 列：{ 左边距, 宽 }  玩家 · 距离 · 共同任务 / 他的进度 · 比我慢 / 我的；最右是 54 宽的「邀请」
local COLS = { { 8, 138 }, { 150, 74 }, { 228, 58 }, { 288, 40 } }
local GOLD, DIM, TXT = "|cffffd200", "|cff8a93a6", "|cffe6e0c8"
local CLASS_HEX = { DRUID = "FF7C0A", HUNTER = "AAD372", MAGE = "3FC7EB", PALADIN = "F48CBA", PRIEST = "FFFFFF", ROGUE = "FFF468",
    SHAMAN = "0070DD", WARLOCK = "8788EE", WARRIOR = "C79C6E" }
local function classHex(cls)
    local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
    if c and c.GenerateHexColor then return c:GenerateHexColor():sub(3) end
    return (cls and CLASS_HEX[cls]) or "e6e0c8"
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

-- ---------- 一键私聊（10-12 用户「增加一个一键私聊，老哥，我在做 xxx 任务（必须范围内），要不要一起，你有队伍，xxx」「你来定」）----------
-- 话术：没队伍「老哥，我在做「XX」，要不要一起组个队？」；有队伍「老哥，看你有队伍了，我也在做「XX」，方便拉我一下吗？」
-- XX 取：装了插件的 → 和他的共同任务（没做完的）；否则 → 列表里选中的任务 → 游戏里追踪的任务 → 任务日志第一个没做完的
-- 只私聊范围内 / 身边的人；一次最多 5 人；同一个人 10 分钟内不重复私聊（防骚扰 / 防被举报刷屏）
QM.whispered = {}
local WHISPER_MAX, WHISPER_GAP = 5, 600
function QM.FocusQuest(peerE)
    local mine = QM.MyQuests()
    if peerE and peerE.quests then
        for _, q in ipairs(mine) do if not q.done and peerE.quests[q.id] then return q end end
    end
    local sq = QM.SelectedQuest(mine)
    if sq then return sq end
    for _, q in ipairs(mine) do if not q.done then return q end end
    return nil
end
-- 10-17 用户「加上[GearInsight插件]」：中文客户端前缀改成 [GearInsight插件]（私聊 / 喊人 / 解散道谢都走这里）
local TAG = L("[GearInsight插件] ", "[GearInsight] ")
QM.TAG = TAG
function QM.Tagged(msg)
    if dbq().noTag or type(msg) ~= "string" or msg:sub(1, #TAG) == TAG then return msg end
    return TAG .. msg
end
function QM.WhisperText(q, busy)
    return QM.Tagged(QM.WhisperBody(q, busy))
end
function QM.WhisperBody(q, busy)
    local t = q and q.title
    local members = tonumber(GetNumGroupMembers and GetNumGroupMembers()) or 0
    if members > 1 then
        local intro = t and string.format(L("你好，我们在做「%s」，目前队伍有 %d 人。", "Hi, we're working on \"%s\" and currently have %d people in our group. "), t, members)
            or string.format(L("你好，我们正在附近做任务，目前队伍有 %d 人。", "Hi, we're questing nearby and currently have %d people in our group. "), members)
        return intro .. (busy and L("看你也有队伍，方便的话要不要一起做任务？", "I see you have a group too. Would you like to quest together?")
            or L("方便的话，要不要一起做任务？", "Would you like to join us and quest together?"))
    end
    if busy then
        return t and string.format(L("老哥，看你有队伍了，我也在做「%s」，方便拉我一下吗？", "Hey, saw you're in a group - I'm on \"%s\" too, mind inviting me?"), t)
            or L("老哥，看你有队伍了，方便拉我一下一起做任务吗？", "Hey, saw you're in a group - mind inviting me to quest together?")
    end
    return t and string.format(L("老哥，我在做「%s」，要不要一起组个队？", "Hey, I'm on \"%s\" - want to group up?"), t)
        or L("老哥，附近一起做任务吗？组个队？", "Hey, want to group up and quest together?")
end
function QM.Whisper(name, busy, peerE, quiet)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send or not name or name == "" then return false end
    local msg = QM.WhisperText(QM.FocusQuest(peerE), busy)
    local ok = pcall(send, msg, "WHISPER", nil, name)
    if ok then
        QM.whispered[(name:match("^([^%-]+)") or name)] = now()
        if not quiet then ns.Print(L("已私聊 ", "Whispered ") .. name) end
    end
    return ok
end
-- cands = { {name, busy, peer}, … }（已按距离排好，只放范围内 / 身边的）
function QM.WhisperCandidates(cands)
    local out, seen = {}, {}
    for _, c in ipairs(cands or {}) do
        if #out >= WHISPER_MAX then break end
        local sn = c.name:match("^([^%-]+)") or c.name
        if not seen[sn] and not QM.IsDeclined(sn) and not (UnitInParty and UnitInParty(sn))
            and now() - (QM.whispered[sn] or -9999) > WHISPER_GAP then
            seen[sn] = true
            out[#out + 1] = c
        end
    end
    return out
end
-- ---------- 喊人（10-12 用户「可以一键在附近说话或者本地频道说话（可配置，可选，默认是在附近说话，可以选大喊）」）----------
-- 频道：say 附近说话（默认）/ yell 大喊 / local 本地频道（区域的「综合」频道）；右键按钮切换，存档
-- 话术：「求组：我在做「XX」（7/10），同任务的老哥一起？密我直接进组」；/gi qm text 自定义（{任务} {进度}），空 = 恢复默认
-- ⛔ 说话 / 大喊 / 公共频道发言要硬件事件（点击）才能发 → 只在点按钮时发；30 秒一次防刷屏
QM.lastShout = -999
local SHOUT_CH = { "say", "yell", "local" }
local SHOUT_NAME = { say = { "附近说话", "Say" }, yell = { "大喊", "Yell" }, ["local"] = { "本地频道", "Local channel" } }
function QM.ShoutChannelName(ch) local t = SHOUT_NAME[ch or "say"]; return t and L(t[1], t[2]) or ch end
function QM.ShoutChannel() return dbq().shoutCh or "say" end
function QM.CycleShoutChannel()
    local cur = QM.ShoutChannel()
    local nxt = "say"
    for i, c in ipairs(SHOUT_CH) do if c == cur then nxt = SHOUT_CH[i % #SHOUT_CH + 1] end end
    dbq().shoutCh = nxt
    QM.dirty = true
    return nxt
end
-- 本地频道 = 区域「综合」频道（中文客户端叫「综合」，英文 General）：按名字在已加入的频道里找编号
function QM.LocalChannelIndex()
    if not GetChannelList then return nil end
    local list = { GetChannelList() }
    for i = 1, #list, 3 do
        local id, name = list[i], list[i + 1]
        if type(name) == "string" and not ns.Secret(name) and (name:find("综合", 1, true) or name:lower():find("general", 1, true)) then
            return tonumber(id)
        end
    end
    return nil
end
function QM.ShoutText()
    return QM.Tagged(QM.ShoutBody())
end
function QM.ShoutBody()
    local q = QM.FocusQuest(nil)
    local tpl = dbq().shoutText
    local prog = q and ((q.r and q.r > 0) and (q.f .. "/" .. q.r) or (q.p .. "%")) or ""
    if type(tpl) == "string" and tpl ~= "" then
        return (tpl:gsub("{任务}", q and q.title or L("任务", "quests")):gsub("{进度}", prog))
    end
    if q then
        return string.format(L("求组：我在做「%s」（%s），同任务的老哥一起？密我直接进组", "LFG: on \"%s\" (%s) - same quest? whisper me for an invite"), q.title, prog)
    end
    return L("求组：附近一起做任务的老哥？密我直接进组", "LFG: anyone questing nearby? whisper me for an invite")
end
function QM.Shout()
    if now() - QM.lastShout < SHOUT_GAP then
        ns.Print(string.format(L("喊人：%d 秒内只能喊一次，稍等", "Wait %ds between calls"), SHOUT_GAP))
        return false, "cd"
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false, "api" end
    local ch, msg = QM.ShoutChannel(), QM.ShoutText()
    local ok
    if ch == "local" then
        local idx = QM.LocalChannelIndex()
        if not idx then
            ns.Print(L("喊人：没找到本地「综合」频道（可能没加入），右键按钮换成附近说话 / 大喊", "No local General channel found; right-click to switch to Say / Yell"))
            return false, "nochan"
        end
        ok = pcall(send, msg, "CHANNEL", nil, idx)
    else
        ok = pcall(send, msg, ch == "yell" and "YELL" or "SAY")
    end
    if ok then QM.lastShout = now(); QM.dirty = true end
    return ok
end

function QM.WhisperAll(cands)
    local list = QM.WhisperCandidates(cands)
    local names = {}
    for _, c in ipairs(list) do
        if QM.Whisper(c.name, c.busy, c.peer, true) then names[#names + 1] = c.name end
    end
    if #names > 0 then ns.Print(string.format(L("一键私聊：已私聊 %d 人 —— %s", "Whispered %d - %s"), #names, table.concat(names, "、")))
    else ns.Print(L("一键私聊：范围内没有可私聊的人（10 分钟内私聊过的不重复）", "Nobody in range to whisper (no repeats within 10 min)")) end
    QM.dirty = true
    return #names
end

-- 已有队伍的人（范围内 / 身边）：装了插件的按坐标距离，身边的按姓名板
function QM.BusyRows()
    local map, x, y = myPos()
    local rg = dbq().range or 100
    local out, seen = {}, {}
    for key, e in pairs(peers) do
        if QM.IsBusy(key) then
            local sn = key:match("^([^%-]+)") or key
            local dist, approx
            if map and e.map == map then dist, approx = yards(map, x, y, e.x, e.y) end
            if QM.near[sn] then dist, approx = math.min(dist or 40, QM.near[sn].yd), false end
            if rg < 0 or (rg == 0 and map and e.map == map) or (dist and dist <= math.max(rg, 40)) then
                seen[sn] = true
                out[#out + 1] = { name = e.name, cls = e.cls, file = e.cls, lvl = e.lvl or 0, dist = dist, approx = approx, peer = e }
            end
        end
    end
    for sn, w in pairs(QM.near) do
        if not seen[sn] and QM.IsBusy(sn) then
            out[#out + 1] = { name = w.name, cls = w.cls, file = w.file, lvl = w.lvl or 0, dist = w.yd }
        end
    end
    table.sort(out, function(a, b) if (a.dist or 1e9) ~= (b.dist or 1e9) then return (a.dist or 1e9) < (b.dist or 1e9) end return a.name < b.name end)
    return out
end

local function pctTxt(p, f, r)
    local col = (p >= 100) and "|cff33ff99" or (p >= 50 and "|cffffd200" or "|cffff9966")
    return col .. ((r and r > 0) and (f .. "/" .. r) or (p .. "%")) .. "|r"
end

local function build(host)
    local W = ns.W
    local d = CreateFrame("Frame", "GearInsightForeverGroupUp", host or UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    d:SetSize(DW, 540)
    -- 不透明底（10-12 截图：Tooltip 底图半透明，后面的任务追踪透出来）——和公会抽屉同一套 WHITE8x8 实底 + 金边
    if d.SetBackdrop then
        d:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        d:SetBackdropColor(0.035, 0.04, 0.055, 1)
        d:SetBackdropBorderColor(0.85, 0.68, 0.25, 1)
    end
    if d.SetFrameStrata then d:SetFrameStrata("HIGH") end
    d:EnableMouse(true)
    d.title = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    d.title:SetPoint("TOPLEFT", PAD, -PAD - 2)
    d.title:SetText(L("组队", "Group up") .. "  " .. DIM .. L("同任务的人 · 附近 · 实时", "players on your quests - nearby - live") .. "|r")
    local close = W and W.CloseButton and W.CloseButton(d, function()
        d:Hide(); dbq().open = false
        local t = QM.Tab()
        if t and W.SelectTab then W.SelectTab(t, false) end
    end)
    if close then close:SetPoint("TOPRIGHT", -8, -8) end
    -- 钉在屏幕上（10-12 用户「保留钉在屏幕的能力和选项」）：钉住后不跟主面板走，关主面板也留着，能拖，重登 / reload 还在
    d.pin = (W and W.Button) and W.Button(d, nil) or ns.Button(d, "", 72, 22)
    d.pin:SetSize(72, 22); d.pin:SetPoint("TOPRIGHT", -40, -9)
    d.pin:SetScript("OnClick", function() QM.SetPinned(not dbq().pinned) end)
    d.pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(L("钉在屏幕上", "Pin to screen"), 1, 0.82, 0)
        GameTooltip:AddLine(L("钉住后：关掉主面板它也留在屏幕上，按住标题栏拖到哪就在哪，重新登录还在；再点一下取消。",
            "Pinned: stays on screen when the main window closes, drag it by the title, survives relogs. Click again to unpin."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    d.pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- 10-16 用户「左右两个组队太乱了」→ 拍板「只留右边，副本组队并进抽屉」：顶上 [附近任务] [副本组队] 切换。
    --   副本组队（PageGroup.lua，HOLD）没装就不出这两个按钮，抽屉和以前一模一样
    if ns.BuildGroupPanel then
        d.title:SetText(L("组队", "Group up"))
        d.modeBtns = {}
        local mx = PAD + 52
        for _, m in ipairs({ { "quest", L("附近任务", "Nearby quests"), L("同任务的人 · 附近 · 实时", "players on your quests - nearby - live") },
            { "dungeon", L("副本·测试", "Dungeons (test)"), L("测试版（10-19 用户「暂时标记为测试状态，不对外放出」）：只在开发安装里有，不随发行包发布。游戏自带的寻求组队（按 I 那个），全服都看得到", "Test build, not in public releases. The game's own group finder, server-wide") } }) do
            local b = (ns.SegButton or ns.Button)(d, m[2], 92, 22, function() QM.SetMode(m[1]) end)   -- 10-17 分段按钮（扁平深底，选中金边金线）
            b:SetPoint("TOPLEFT", mx, -9); mx = mx + 96
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(m[2], 1, 0.82, 0)
                GameTooltip:AddLine(m[3], 1, 1, 1, true); GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            d.modeBtns[m[1]] = b
        end
        -- 副本组队盖在任务内容上面（实底、挡鼠标），切回附近任务就藏起来
        local o = CreateFrame("Frame", nil, d, BackdropTemplateMixin and "BackdropTemplate" or nil)
        o:SetPoint("TOPLEFT", 4, -38); o:SetPoint("BOTTOMRIGHT", -4, 4)
        if o.SetBackdrop then
            o:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            o:SetBackdropColor(0.035, 0.04, 0.055, 1)
        end
        local lvl = d.GetFrameLevel and d:GetFrameLevel()
        if lvl and o.SetFrameLevel then o:SetFrameLevel(lvl + 30) end
        o:EnableMouse(true)
        o:Hide()
        d.lfg = o
    end
    if d.SetMovable then d:SetMovable(true) end
    if d.SetClampedToScreen then d:SetClampedToScreen(true) end
    if d.RegisterForDrag then d:RegisterForDrag("LeftButton") end
    d:SetScript("OnDragStart", function(self) if dbq().pinned and self.StartMoving then self:StartMoving() end end)
    d:SetScript("OnDragStop", function(self)
        if self.StopMovingOrSizing then self:StopMovingOrSizing() end
        if dbq().pinned then QM.SavePinPos() end
    end)
    -- 10-12 用户截图「UI 优化下」：滚动条压在表头上 / 按钮宽窄不一 / 空态挤在底部和说明叠字 / 中间大片空白
    --   → 任务选择条加底色；四个按钮等宽一排；表头和列表右侧给滚动条留槽；空态放到列表正中；底部状态 + 说明各一行不换行
    local INNER = DW - PAD * 2
    local GUT = 22                                  -- 滚动条槽
    local LW = INNER - GUT                          -- 表头 / 列表宽
    local y = -44
    local function btn(text, w, onClick, kind)
        local b = (W and W.Button) and W.Button(d, nil, kind) or ns.Button(d, text, w, 22)
        b:SetSize(w, 22); b:SetText(text); b:SetScript("OnClick", onClick)
        return b
    end
    -- 第一行：当前任务下拉（10-12：原来是 < > 翻页）—— 整条是个按钮，点开列出 自动 / 全部 / 每个任务
    d.qsel = CreateFrame("Button", nil, d, BackdropTemplateMixin and "BackdropTemplate" or nil)
    d.qsel:SetPoint("TOPLEFT", PAD, y + 2); d.qsel:SetSize(INNER, 26)
    if d.qsel.SetBackdrop then
        d.qsel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        d.qsel:SetBackdropColor(0.08, 0.08, 0.1, 1); d.qsel:SetBackdropBorderColor(0.85, 0.68, 0.25, 0.8)
    end
    local qhl = d.qsel:CreateTexture(nil, "HIGHLIGHT"); qhl:SetAllPoints(); qhl:SetColorTexture(1, 0.82, 0, 0.08)
    d.quest = d.qsel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    d.quest:SetPoint("LEFT", 10, 0); d.quest:SetPoint("RIGHT", -26, 0); d.quest:SetJustifyH("LEFT"); d.quest:SetWordWrap(false)
    d.qarrow = d.qsel:CreateTexture(nil, "OVERLAY"); d.qarrow:SetSize(16, 16); d.qarrow:SetPoint("RIGHT", -6, 0)
    d.qarrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")   -- 经典客户端就有的向下箭头
    d.qsel:SetScript("OnClick", function() QM.ToggleQuestMenu() end)
    -- 第二行：四个等宽按钮  只看比我慢 · 只看本区域 · 共享 · 刷新
    y = y - 34
    local GAP = 6
    local BW = math.floor((INNER - GAP * 3) / 4)
    d.fBehind = btn("", BW, function() local c = dbq(); c.onlyBehind = not c.onlyBehind; QM.Request(); QM.Render() end)
    -- 范围：40 → 100 → 300 码 → 本区域 → 回到 40
    d.fZone = btn("", BW, function()
        local c = dbq()
        local nxt = { [40] = 100, [100] = 300, [300] = 0, [0] = 40 }
        c.range = nxt[c.range or 100] or 40
        QM.Request(); QM.Render()
    end)
    d.fZone:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(L("距离范围", "Range"), 1, 0.82, 0)
        GameTooltip:AddLine(L("点一下换：40 码 / 100 码 / 300 码 / 本区域。\n装了插件的人按坐标算距离；没装插件的人只能看到姓名板范围内（约 40 码）的。",
            "Click to cycle 40 / 100 / 300 yd / this zone.\nAddon users: by position. Others: only within nameplate range (~40 yd)."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    d.fZone:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.share = btn("", BW, function() QM.SetSharing(not dbq().share); QM.Render() end)
    d.refresh = btn(L("刷新", "Refresh"), BW, function()
        QM.Request(); QM.ScanNear(); QM.Render()
    end, "primary")
    for i, b in ipairs({ d.fBehind, d.fZone, d.share, d.refresh }) do b:SetPoint("TOPLEFT", PAD + (i - 1) * (BW + GAP), y) end
    -- 表头（右侧留滚动条槽，别让滚动条压在表头上）
    y = y - 34
    d.head = CreateFrame("Frame", nil, d)
    d.head:SetPoint("TOPLEFT", PAD, y); d.head:SetSize(LW, 20)
    local hb = d.head:CreateTexture(nil, "BACKGROUND"); hb:SetAllPoints(); hb:SetColorTexture(1, 0.82, 0, 0.12)
    local hl = d.head:CreateTexture(nil, "BORDER"); hl:SetPoint("BOTTOMLEFT"); hl:SetPoint("BOTTOMRIGHT"); hl:SetHeight(1)
    hl:SetColorTexture(1, 0.82, 0, 0.5)
    d.cols = {}
    for i, c in ipairs(COLS) do
        local fs = d.head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", c[1], 0); fs:SetWidth(c[2]); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        d.cols[i] = fs
    end
    -- 列表：表头下面一直到底部状态栏上面
    local sf, c = ns.Scroll(d, PAD, y - 22, LW, 300)
    sf:ClearAllPoints(); sf:SetPoint("TOPLEFT", PAD, y - 22); sf:SetPoint("BOTTOMRIGHT", -PAD - GUT, 86)
    -- 一键组人：整行金色主按钮，在列表和底部状态栏之间
    d.invAll = (W and W.Button) and W.Button(d, nil, "primary") or ns.Button(d, "", INNER, 28)
    local HB = math.floor((INNER - 12) / 3)   -- 10-12 加了「喊人」：三个按钮一排
    d.invAll:SetSize(HB, 28); d.invAll:SetPoint("BOTTOMLEFT", PAD, 52)
    d.whAll = (W and W.Button) and W.Button(d, nil) or ns.Button(d, "", HB, 28)
    d.whAll:SetSize(HB, 28); d.whAll:SetPoint("BOTTOMLEFT", PAD + HB + 6, 52)
    -- 喊人：左键发，右键换频道（附近说话 → 大喊 → 本地频道）
    d.shout = (W and W.Button) and W.Button(d, nil) or ns.Button(d, "", HB, 28)
    d.shout:SetSize(HB, 28); d.shout:SetPoint("BOTTOMRIGHT", -PAD, 52)
    if d.shout.RegisterForClicks then d.shout:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    d.shout:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then
            local ch = QM.CycleShoutChannel()
            ns.Print(L("喊人频道：", "Call channel: ") .. QM.ShoutChannelName(ch))
        else
            QM.Shout()
        end
        QM.Render()
        if self:IsMouseOver() and self:GetScript("OnEnter") then self:GetScript("OnEnter")(self) end
    end)
    d.shout:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L("喊人", "Call for group"), 1, 0.82, 0)
        GameTooltip:AddLine(L("频道：", "Channel: ") .. QM.ShoutChannelName(QM.ShoutChannel()), 1, 1, 1)
        GameTooltip:AddLine(QM.ShoutText(), 0.7, 0.85, 1, true)
        GameTooltip:AddLine(string.format(L("左键发一次（%d 秒一次）· 右键换频道：附近说话 / 大喊 / 本地频道\n%s qm text 自定义内容（{任务} {进度}）",
            "Left-click to send (once per %ds) - right-click: Say / Yell / Local\n%s qm text to customise ({任务} {进度})"), SHOUT_GAP, ns.SlashHint or "/gif"), 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    d.shout:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.whAll:SetScript("OnClick", function() QM.WhisperAll(d._whCands); QM.Render() end)
    d.whAll:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L("一键私聊", "Whisper all"), 1, 0.82, 0)
        local list = QM.WhisperCandidates(d._whCands)
        if #list == 0 then GameTooltip:AddLine(L("范围内没有可私聊的人", "Nobody in range"), 0.8, 0.8, 0.8)
        else
            for _, c in ipairs(list) do
                GameTooltip:AddLine(c.name, 1, 1, 1)
                GameTooltip:AddLine("  " .. QM.WhisperText(QM.FocusQuest(c.peer), c.busy), 0.7, 0.85, 1, true)
            end
        end
        GameTooltip:AddLine(string.format(L("只私聊范围内 / 身边的人，从近到远，一次最多 %d 人；同一个人 10 分钟内不重复。右键单独一行 = 只私聊他。",
            "Only players in range, nearest first, max %d; no repeats within 10 min. Right-click a row to whisper just them."), WHISPER_MAX), 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    d.whAll:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.invAll:SetScript("OnClick", function() QM.InviteAll(d._invNames); QM.Render() end)
    d.invAll:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L("一键组人", "Group up"), 1, 0.82, 0)
        local can, why = QM.CanInvite("")
        if not can then GameTooltip:AddLine(why, 1, 0.4, 0.4)
        else
            local list = QM.InviteCandidates(d._invNames)
            if #list == 0 then GameTooltip:AddLine(L("没有可邀请的人", "Nobody to invite"), 0.8, 0.8, 0.8)
            else
                GameTooltip:AddLine(string.format(L("从近到远邀请 %d 人（队伍空位 %d）：", "Invites %d, nearest first (%d open slots):"), #list, QM.OpenSlots()), 1, 1, 1)
                for _, n in ipairs(list) do GameTooltip:AddLine("  " .. n, 0.9, 0.9, 0.9) end
            end
        end
        GameTooltip:AddLine(L("从近到远邀请；跳过已在队里的、2 分钟内邀请过的；拒绝过的记下来，以后不再列出。", "Nearest first; skips group members and recent invites; anyone who declined is hidden for good."), 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    d.invAll:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c:SetWidth(LW)
    d.sf, d.child, d.rows = sf, c, {}
    -- 空态：放在列表正中（图标 + 一句话 + 怎么办）
    d.empty = CreateFrame("Frame", nil, d)
    d.empty:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, -40); d.empty:SetPoint("RIGHT", sf, "RIGHT", 0, 0); d.empty:SetHeight(150)
    d.empty.ic = d.empty:CreateTexture(nil, "ARTWORK"); d.empty.ic:SetSize(40, 40); d.empty.ic:SetPoint("TOP", 0, 0)
    d.empty.ic:SetTexture("Interface\\Icons\\INV_Misc_GroupNeedMore"); d.empty.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93); d.empty.ic:SetAlpha(0.6)
    d.empty.t = d.empty:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    d.empty.t:SetPoint("TOP", d.empty.ic, "BOTTOM", 0, -10); d.empty.t:SetWidth(LW - 40); d.empty.t:SetJustifyH("CENTER")
    d.empty.s = d.empty:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.empty.s:SetPoint("TOP", d.empty.t, "BOTTOM", 0, -8); d.empty.s:SetWidth(LW - 40); d.empty.s:SetJustifyH("CENTER")
    d.empty.s:SetTextColor(0.65, 0.65, 0.65)
    d.empty:Hide()
    -- 底部：分隔线 + 状态一行 + 说明一行（都不换行，免得两行叠字）
    local bl = d:CreateTexture(nil, "ARTWORK"); bl:SetPoint("BOTTOMLEFT", PAD, 46); bl:SetPoint("BOTTOMRIGHT", -PAD, 46); bl:SetHeight(1)
    bl:SetColorTexture(0.85, 0.68, 0.25, 0.35)
    d.status = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.status:SetPoint("BOTTOMLEFT", PAD, 28); d.status:SetPoint("RIGHT", -PAD, 0); d.status:SetJustifyH("LEFT"); d.status:SetWordWrap(false)
    d.foot = d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    d.foot:SetPoint("BOTTOMLEFT", PAD, 10); d.foot:SetPoint("RIGHT", -PAD, 0); d.foot:SetJustifyH("LEFT"); d.foot:SetWordWrap(false)
    d.foot:SetText(L("任务进度只来自装了 GearInsight 无限版、开着共享的玩家", "Quest progress only comes from players running the addon with sharing on"))
    d:SetScript("OnShow", function() pcall(QM.PlatesOnOpen) end)
    d:SetScript("OnHide", function() pcall(QM.PlatesOnClose) end)
    d:Hide()
    return d
end

local function row(d, i)
    local r = d.rows[i]
    if r then
        for k, c in ipairs(COLS) do r.c[k]:SetWidth(c[2]) end   -- 行会被别的段复用：列宽 / 按钮文字 / 右键先还原
        r.inv:SetText(L("邀请", "Invite")); r:SetScript("OnClick", nil)
        return r
    end
    r = CreateFrame("Button", nil, d.child)
    if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.acc = r:CreateTexture(nil, "BORDER"); r.acc:SetWidth(3); r.acc:SetPoint("TOPLEFT"); r.acc:SetPoint("BOTTOMLEFT")
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.08)
    r.c = {}
    for k, c in ipairs(COLS) do
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", c[1], 0); fs:SetWidth(c[2]); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        r.c[k] = fs
    end
    local W = ns.W
    r.inv = (W and W.Button) and W.Button(r, nil, "primary") or ns.Button(r, "", 58, 22)
    r.inv:SetSize(54, 22); r.inv:SetPoint("RIGHT", -2, 0); r.inv:SetText(L("邀请", "Invite"))
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.rows[i] = r
    return r
end

-- 任务下拉菜单：自绘（不用 UIDropDownMenu，免得污染暴雪菜单）；点外面 / 再点一次 / Esc 关
function QM.FillQuestMenu()
    local m = QM.menu
    local d = QM.drawer
    if not (m and d) then return end
    local mine = QM.MyQuests()
    local dist = QM.QuestDistances()
    local cur = dbq().questSel or "auto"
    local items = {
        { key = "auto", text = "|cff33ff99" .. L("自动", "Auto") .. "|r  " .. L("离我最近的任务（跟着走）", "nearest quest (follows you)") },
        { key = "all", text = L("全部共同任务", "All shared quests") .. DIM .. "  (" .. #mine .. ")|r" },
    }
    table.sort(mine, function(a, b)
        local da, db = dist[a.id] or 1e9, dist[b.id] or 1e9
        if da ~= db then return da < db end
        return a.id < b.id
    end)
    for _, q in ipairs(mine) do
        items[#items + 1] = { key = q.id, text = (q.done and DIM or GOLD) .. q.title .. "|r  " .. pctTxt(q.p, q.f, q.r)
            .. (dist[q.id] and (DIM .. L("  约 ", "  ~") .. dist[q.id] .. L(" 码", " yd") .. "|r") or "") }
    end
    if type(rawget(m, "rows")) ~= "table" then m.rows = {} end   -- ⛔ rawget：框体的元表会把没有的键转去方法表
    for _, r in ipairs(m.rows) do r:Hide() end
    for i, it in ipairs(items) do
        local r = m.rows[i]
        if not r then
            r = CreateFrame("Button", nil, m)
            r:SetHeight(22)
            r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
            local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.12)
            r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.t:SetPoint("LEFT", 10, 0); r.t:SetPoint("RIGHT", -8, 0)
            r.t:SetJustifyH("LEFT"); r.t:SetWordWrap(false)
            m.rows[i] = r
        end
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 22); r:SetPoint("RIGHT", m, "RIGHT", -4, 0)
        local on = (it.key == cur)
        r.bg:SetColorTexture(1, 0.82, 0, on and 0.16 or 0)
        r.t:SetText((on and "|cffffd200>|r " or "  ") .. it.text)
        r:SetScript("OnClick", function()
            dbq().questSel = it.key
            QM.Request()
            m:Hide()
            QM.Render()
        end)
        r:Show()
    end
    m:SetHeight(8 + #items * 22)
end
function QM.ToggleQuestMenu()
    local d = QM.drawer
    if not d then return end
    if not QM.menu then
        local m = CreateFrame("Frame", "GearInsightForeverQuestMenu", d, BackdropTemplateMixin and "BackdropTemplate" or nil)
        if m.SetBackdrop then
            m:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            m:SetBackdropColor(0.04, 0.045, 0.06, 1); m:SetBackdropBorderColor(0.85, 0.68, 0.25, 1)
        end
        m:SetFrameStrata("DIALOG"); m:EnableMouse(true)
        m:SetPoint("TOPLEFT", d.qsel, "BOTTOMLEFT", 0, -2); m:SetPoint("TOPRIGHT", d.qsel, "BOTTOMRIGHT", 0, -2)
        if UISpecialFrames then table.insert(UISpecialFrames, "GearInsightForeverQuestMenu") end
        -- 点菜单外面就关
        m:SetScript("OnUpdate", function(self)
            if IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
                and not self:IsMouseOver() and not d.qsel:IsMouseOver() then self:Hide() end
        end)
        m:Hide()
        QM.menu = m
    end
    if QM.menu:IsShown() then QM.menu:Hide() else QM.FillQuestMenu(); QM.menu:Show() end
end

function QM.Render()
    local d = QM.drawer
    if not d then return end
    local cfg = dbq()
    local mineAll = QM.MyQuests()
    local nq = #mineAll
    local selQ, mode, autoYd = QM.SelectedQuest(mineAll)
    local modeTxt = (mode == "auto") and ("|cff33ff99" .. L("自动", "Auto") .. "|r  ") or ""
    d.quest:SetText(modeTxt .. (selQ and (GOLD .. selQ.title .. "|r  " .. DIM .. L("我的进度 ", "My progress ") .. "|r" .. pctTxt(selQ.p, selQ.f, selQ.r)
            .. (autoYd and (DIM .. L("  · 约 ", "  - ~") .. autoYd .. L(" 码", " yd") .. "|r") or ""))
        or (TXT .. L("全部共同任务", "All shared quests") .. "|r  " .. DIM .. "(" .. nq .. L(" 个任务)", " quests)") .. "|r")))
    if QM.menu and QM.menu:IsShown() then QM.FillQuestMenu() end
    d.fBehind:SetText(cfg.onlyBehind and L("只看比我慢", "Behind me") or L("全部进度", "Any progress"))
    local rg = cfg.range or 100
    d.fZone:SetText(rg > 0 and string.format(L("%d 码内", "Within %d yd"), rg) or L("本区域", "This zone"))
    d.share:SetText(cfg.share and L("共享 开", "Share on") or L("共享 关", "Share off"))
    d.pin:SetText(cfg.pinned and L("已钉住", "Pinned") or L("钉住", "Pin"))
    if cfg.pinned then d.pin:LockHighlight() else d.pin:UnlockHighlight() end
    for _, b in ipairs({ d.fBehind, d.fZone, d.share }) do if ns.W and ns.W.PaintButton then ns.W.PaintButton(b) end end
    if cfg.onlyBehind then d.fBehind:LockHighlight() else d.fBehind:UnlockHighlight() end
    d.fZone:LockHighlight()   -- 范围永远是生效状态
    if cfg.share then d.share:LockHighlight() else d.share:UnlockHighlight() end
    d.cols[1]:SetText(L("玩家", "Player")); d.cols[2]:SetText(L("距离", "Distance"))
    d.cols[3]:SetText(selQ and L("他的进度", "Theirs") or L("共同任务", "Shared"))
    -- 10-18 用户截图「显示0是啥情况」：原来这列只数「比我慢」的任务个数，0 看不出是一样还是比我快 → 改成「进度」：慢 N / 快 N / 同
    d.cols[4]:SetText(selQ and L("我的", "Mine") or L("进度", "Pace"))

    local allRows = QM.Rows(selQ and selQ.id or nil)
    local rows = {}
    for i = 1, math.min(MAX_ROWS, #allRows) do rows[i] = allRows[i] end
    QM._rank = {}
    for i, it in ipairs(allRows) do QM._rank[it.key] = i end
    for _, r in ipairs(d.rows) do r:Hide() end   -- 同一帧里藏了再显示，画面上不会闪
    local y = 0
    for i, it in ipairs(rows) do
        local r = row(d, i)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", d.child, "RIGHT", 0, 0); r:SetHeight(ROW_H)
        local e = it.e
        local short = e.name:match("^([^%-]+)") or e.name
        local behind = it.behind > 0
        if it.guild then r.bg:SetColorTexture(0.25, 1, 0.25, (i % 2 == 0) and 0.07 or 0.10)   -- 同公会：淡绿底 + <公会> 标
        else r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0.06) end
        r.acc:SetColorTexture(0.2, 1, 0.6, behind and 0.9 or 0); r.acc:SetShown(behind)
        r.c[1]:SetText((it.guild and GUILD_TAG or "") .. "|cff" .. classHex(e.cls) .. short .. "|r " .. DIM .. (e.lvl or "?") .. "|r")
        r.c[2]:SetText(it.dist and ((it.approx and L("约 ", "~") or "") .. QM.RoundYd(it.dist) .. L(" 码", " yd")) or (it.same and L("同区域", "same zone") or DIM .. L("别的区域", "other zone") .. "|r"))
        if selQ then
            local h = it.shared[1].his
            r.c[3]:SetText(pctTxt(h[1], h[2], h[3])); r.c[4]:SetText(pctTxt(selQ.p, selQ.f, selQ.r))
        else
            r.c[3]:SetText(TXT .. #it.shared .. "|r")
            r.c[4]:SetText(behind and ("|cff33ff99" .. L("慢 ", "-") .. it.behind .. "|r")
                or ((it.ahead or 0) > 0 and ("|cffff9966" .. L("快 ", "+") .. it.ahead .. "|r")) or (DIM .. L("同", "same") .. "|r"))
        end
        local can, why = QM.CanInvite(e.name)
        r.inv:SetEnabled(can)
        r.inv:SetScript("OnClick", function() QM.Invite(e.name) end)
        r:SetScript("OnClick", function(_, btn) if btn == "RightButton" then QM.Whisper(e.name, false, e) end end)
        r.inv:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(can and L("邀请组队", "Invite to group") or why, 1, 0.82, 0); GameTooltip:Show()
        end)
        r.inv:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("|cff" .. classHex(e.cls) .. e.name .. "|r  " .. L("等级 ", "level ") .. (e.lvl or "?"))
            if it.guild then GameTooltip:AddLine(L("同公会 · 排在最前面", "Guildmate - listed first"), 0.25, 1, 0.25) end
            for _, s in ipairs(it.shared) do
                GameTooltip:AddDoubleLine(s.q.title, pctTxt(s.his[1], s.his[2], s.his[3]) .. DIM .. L("  我 ", "  me ") .. "|r" .. pctTxt(s.q.p, s.q.f, s.q.r), 1, 1, 1)
            end
            QM.TipLastInvite(e.name)
            GameTooltip:AddLine(L("进度：慢 N = 有 N 个共同任务他比你慢（带他一起做）· 快 N = 他比你快 · 同 = 进度一样 · 右键私聊",
                "Pace: -N = behind you on N shared quests (bring them along) - +N = ahead - same = even - right-click to whisper"), 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        r:Show()
        y = y + ROW_H + 2
    end
    local np = 0
    for _ in pairs(peers) do np = np + 1 end
    if #rows == 0 then
        if not rawget(d, "peerHint") then
            local h = CreateFrame("Frame", nil, d.child)
            h:SetHeight(40)
            h.t = h:CreateFontString(nil, "OVERLAY", "GameFontNormal"); h.t:SetPoint("TOPLEFT", 8, -4); h.t:SetPoint("RIGHT", -8, 0)
            h.t:SetJustifyH("LEFT"); h.t:SetWordWrap(false)
            h.s = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); h.s:SetPoint("TOPLEFT", 8, -22); h.s:SetPoint("RIGHT", -8, 0)
            h.s:SetJustifyH("LEFT"); h.s:SetWordWrap(false); h.s:SetTextColor(0.65, 0.65, 0.65)
            d.peerHint = h
        end
        local h = d.peerHint
        h:ClearAllPoints(); h:SetPoint("TOPLEFT", 0, -y); h:SetPoint("RIGHT", d.child, "RIGHT", 0, 0)
        if np == 0 then
            h.t:SetText(L("范围内还没有装插件、同任务的玩家", "No addon users on your quests in range yet"))
            h.s:SetText(L("装了 GearInsight 无限版的人会带着任务进度出现在这里", "Players with the addon show up here with their progress"))
        else
            h.t:SetText(L("当前任务、距离和进度条件下暂无匹配玩家", "No players match the current quest, range and progress filters"))
            h.s:SetText(L("可调整筛选；展开下方查看其他玩家及排除原因", "Adjust filters, or expand below to see other players and why they were excluded"))
        end
        h:Show()
        y = y + 44
    elseif rawget(d, "peerHint") then
        d.peerHint:Hide()
    end
    -- Received but excluded peers are opt-in diagnostics, never match results.
    local shownKeys = {}
    for _, it in ipairs(allRows) do shownKeys[it.key] = true end
    local fp = QM.FilteredPeers(shownKeys, selQ and selQ.id or nil)
    local filterKey = tostring(selQ and selQ.id or "all") .. ":" .. tostring(rg) .. ":" .. tostring(cfg.onlyBehind)
    if rawget(d, "filterKey") ~= filterKey then d.filterKey = filterKey; d.showFiltered = false end
    if not rawget(d, "fpHdr") then
        local h = CreateFrame("Button", nil, d.child)
        h:SetHeight(22)
        h:SetScript("OnClick", function() d.showFiltered = not d.showFiltered; QM.Render() end)
        local bg = h:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.06)
        h.t = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); h.t:SetPoint("LEFT", 8, 0); h.t:SetPoint("RIGHT", -8, 0)
        h.t:SetJustifyH("LEFT"); h.t:SetWordWrap(false)
        d.fpHdr = h
    end
    local nFp = 0
    if #fp > 0 then
        d.fpHdr:ClearAllPoints(); d.fpHdr:SetPoint("TOPLEFT", 0, -y); d.fpHdr:SetPoint("RIGHT", d.child, "RIGHT", 0, 0)
        d.fpHdr.t:SetText(DIM .. string.format(L("其他已收到数据的玩家 · %d 人", "Other players heard from - %d"), #fp)
            .. (d.showFiltered and L(" · 收起", " - collapse") or L(" · 展开", " - expand")) .. "|r")
        d.fpHdr:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L("这些玩家不符合当前筛选，不是任务匹配结果。", "These players do not match your filters; they are not quest matches."), 1, 1, 1, true)
            GameTooltip:AddLine(string.format(L("共 %d 人，展开最多显示前 5 人。", "%d players; expands to show up to 5."), #fp), 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        d.fpHdr:SetScript("OnLeave", function() GameTooltip:Hide() end)
        d.fpHdr:Show()
        y = y + 24
        for j, it in ipairs(fp) do
            if not d.showFiltered or j > 5 then break end
            nFp = j
            local e = it.e
            local r = row(d, #rows + j)
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", d.child, "RIGHT", 0, 0); r:SetHeight(ROW_H)
            r.bg:SetColorTexture(1, 1, 1, 0.02); r.acc:Hide()
            local short = e.name:match("^([^%-]+)") or e.name
            r.c[1]:SetText("|cff" .. classHex(e.cls) .. short .. "|r " .. DIM .. (e.lvl or "?") .. "|r")
            r.c[2]:SetText(DIM .. (it.dist and ((it.approx and L("约 ", "~") or "") .. QM.RoundYd(it.dist) .. L(" 码", " yd")) or (it.same and L("同区域", "same zone") or L("别的区域", "other zone"))) .. "|r")
            -- 原因写在第 3 列，一直占到邀请按钮左边（共同任务数放悬停里）
            r.c[3]:SetWidth(100); r.c[3]:SetText("|cffff9966" .. it.why .. "|r")
            r.c[4]:SetText("")
            r.inv:SetEnabled(false)
            r.inv:SetScript("OnClick", nil)
            r:SetScript("OnClick", nil)
            r.inv:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(L("不符合当前筛选，请先调整筛选条件", "Does not match; adjust your filters first"), 1, 0.82, 0); GameTooltip:Show()
            end)
            r.inv:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("|cff" .. classHex(e.cls) .. e.name .. "|r  " .. L("等级 ", "level ") .. (e.lvl or "?"))
                GameTooltip:AddLine(L("没列出来的原因：", "Not listed because: ") .. it.why, 1, 0.6, 0.4, true)
                GameTooltip:AddLine(string.format(L("当前筛选共同任务 %d 个", "%d shared quests in this selection"), it.nShared), 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end)
            r:Show()
            y = y + ROW_H + 2
        end
        y = y + 4
    else
        d.fpHdr:Hide()
    end
    -- 身边其他玩家（未装插件，姓名板 ≈ 40 码内）：单独一段
    local wr = QM.NearRows()
    while #wr > 10 do table.remove(wr) end
    if not rawget(d, "whoHdr") then
        local h = CreateFrame("Frame", nil, d.child)
        h:SetHeight(22)
        local bg = h:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.43, 0.65, 0.97, 0.14)
        -- 10-18 右边「自动开姓名板」勾：觉得卡的玩家能直接在这里关，不用去翻命令 / 删插件
        local cb = CreateFrame("CheckButton", nil, h, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cb.label:SetPoint("RIGHT", h, "RIGHT", -6, 0); cb.label:SetText(L("自动开姓名板", "Auto nameplates"))
        cb:SetPoint("RIGHT", cb.label, "LEFT", -1, 0)
        cb:SetScript("OnClick", function(self) QM.SetAutoPlates(self:GetChecked() and true or false) end)
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L("自动开友方姓名板", "Auto friendly nameplates"), 1, 0.82, 0)
            GameTooltip:AddLine(L("打开组队窗口时自动打开友方姓名板，用来认出身边没装插件的人；关掉窗口时还原。",
                "Turns on friendly nameplates while this window is open so nearby players without the addon show up; restored when closed."), 1, 1, 1, true)
            GameTooltip:AddLine(L("觉得卡可以先关掉试试：只影响「身边玩家」这一栏，其他功能照常。设置页「性能」里还能一键自查卡顿。",
                "Feel laggy? Try turning it off: only this section is affected. Settings > Performance has a one-click lag check."), 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        h.auto = cb
        h.t = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); h.t:SetPoint("LEFT", 8, 0); h.t:SetPoint("RIGHT", cb, "LEFT", -6, 0); h.t:SetJustifyH("LEFT")
        h.t:SetWordWrap(false)
        d.whoHdr = h
    end
    local wh = d.whoHdr
    y = y + 6
    wh:ClearAllPoints(); wh:SetPoint("TOPLEFT", 0, -y); wh:SetPoint("RIGHT", d.child, "RIGHT", 0, 0)
    local plates = friendPlatesOn()   -- true / false / nil（找不到设置）
    if rawget(wh, "auto") then wh.auto:SetChecked(QM.AutoPlatesOn()) end
    wh.t:SetText("|cff6ea6f7" .. L("身边玩家 · 未装插件", "Players around you - no addon") .. "|r  " .. DIM
        .. string.format(L("%d 人 · 40 码内 · 等级差 4 级内", "%d - 40 yd - level +/-4"), #wr)
        .. ((plates == true) and "" or ("  |cffff9966" .. L("友方姓名板关着", "friendly nameplates off") .. "|r")) .. "|r")
    wh:Show()
    y = y + 24
    for j, w in ipairs(wr) do
        local r = row(d, #rows + nFp + j)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", d.child, "RIGHT", 0, 0); r:SetHeight(ROW_H)
        if w.guild then r.bg:SetColorTexture(0.25, 1, 0.25, (j % 2 == 0) and 0.07 or 0.10)
        else r.bg:SetColorTexture(1, 1, 1, (j % 2 == 0) and 0.02 or 0.04) end
        r.acc:Hide()
        local short = w.name:match("^([^%-]+)") or w.name
        r.c[1]:SetText((w.guild and GUILD_TAG or "") .. "|cff" .. classHex(w.file) .. short .. "|r " .. DIM .. (w.lvl > 0 and w.lvl or "?") .. "|r")
        r.c[2]:SetText(w.how and (DIM .. L("刚说过话", "spoke nearby") .. "|r") or (w.yd <= 28 and L("28 码内", "<28 yd") or L("40 码内", "<40 yd")))
        r.c[3]:SetText(TXT .. (w.cls or "?") .. "|r"); r.c[4]:SetText(DIM .. "-|r")
        local can, why = QM.CanInvite(w.name)
        r.inv:SetEnabled(can)
        r.inv:SetScript("OnClick", function() QM.Invite(w.name) end)
        r:SetScript("OnClick", function(_, btn) if btn == "RightButton" then QM.Whisper(w.name, false) end end)
        r.inv:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(can and L("邀请组队", "Invite to group") or why, 1, 0.82, 0); GameTooltip:Show()
        end)
        r.inv:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("|cff" .. classHex(w.file) .. w.name .. "|r  " .. L("等级 ", "level ") .. w.lvl .. "  " .. (w.cls or ""))
            GameTooltip:AddLine(L("没装 GearInsight 无限版：游戏不给别人的任务信息，看不到他的任务和进度。", "No addon: the game doesn't share their quests."), 0.8, 0.8, 0.8, true)
            QM.TipLastInvite(w.name)
            GameTooltip:AddLine(L("右键私聊", "Right-click to whisper"), 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        r:Show()
        y = y + ROW_H + 2
    end
    -- 10-18 姓名板关着时不管列表空不空都给这一行（说过话的人不靠姓名板，列表可能不空）
    if #wr == 0 or plates ~= true then
        if not rawget(d, "nearHint") then
            local h = CreateFrame("Button", nil, d.child)
            h:SetHeight(22)
            h.t = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); h.t:SetPoint("LEFT", 8, 0); h.t:SetPoint("RIGHT", -8, 0)
            h.t:SetJustifyH("LEFT"); h.t:SetWordWrap(false)
            local hl = h:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.08)
            d.nearHint = h
        end
        local h = d.nearHint
        h:ClearAllPoints(); h:SetPoint("TOPLEFT", 0, -y); h:SetPoint("RIGHT", d.child, "RIGHT", 0, 0)
        if plates == true then
            h.t:SetText(DIM .. L("身边 40 码内没有等级相近的玩家", "Nobody at your level within 40 yd") .. "|r")
            h:SetScript("OnClick", nil)
        elseif plates == nil then
            -- 找不到设置名：插件改不了，只能请玩家按游戏自带的快捷键
            h.t:SetText("|cffffd200" .. L("按 Shift+V 打开友方姓名板，身边的人才会出现在这里", "Press Shift+V to show friendly nameplates so nearby players appear here") .. "|r")
            h:SetScript("OnClick", nil)
        else
            -- 友方姓名板关着就看不到身边的人：点这一行打开（只改这一个设置；战斗中不改）
            h.t:SetText("|cffffd200" .. L("点这里打开友方姓名板，看身边没装插件的人（Shift+V 也行）", "Click to turn on friendly nameplates (or Shift+V) to see players around you") .. "|r")
            h:SetScript("OnClick", function()
                if InCombatLockdown and InCombatLockdown() then return end
                local k = friendCVar()
                if k and SetCVar then pcall(SetCVar, k, "1") end
                QM.ScanNear(); QM.Render()
            end)
        end
        h:Show()
        y = y + 24
    elseif rawget(d, "nearHint") then
        d.nearHint:Hide()
    end
    -- 已有队伍（10-12「也别弄掉，打个标记，放到下面的区域吧」）：最下面一段，按钮 = 私聊请他拉你
    local br = QM.BusyRows()
    while #br > 10 do table.remove(br) end
    if not rawget(d, "busyHdr") then
        local h = CreateFrame("Frame", nil, d.child)
        h:SetHeight(22)
        local bg = h:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 0.6, 0.4, 0.12)
        h.t = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); h.t:SetPoint("LEFT", 8, 0); h.t:SetPoint("RIGHT", -8, 0)
        h.t:SetJustifyH("LEFT"); h.t:SetWordWrap(false)
        d.busyHdr = h
    end
    local nBase = #rows + nFp + #wr
    if #br > 0 then
        y = y + 6
        d.busyHdr:ClearAllPoints(); d.busyHdr:SetPoint("TOPLEFT", 0, -y); d.busyHdr:SetPoint("RIGHT", d.child, "RIGHT", 0, 0)
        d.busyHdr.t:SetText("|cffff9966" .. L("已有队伍", "Already in a group") .. "|r  " .. DIM
            .. string.format(L("%d 人 · 私聊请他拉你", "%d - whisper to ask for an invite"), #br) .. "|r")
        d.busyHdr:Show()
        y = y + 24
        for j, b in ipairs(br) do
            local r = row(d, nBase + j)
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", d.child, "RIGHT", 0, 0); r:SetHeight(ROW_H)
            r.bg:SetColorTexture(1, 0.6, 0.4, (j % 2 == 0) and 0.03 or 0.05); r.acc:Hide()
            local short = b.name:match("^([^%-]+)") or b.name
            r.c[1]:SetText("|cff" .. classHex(b.file) .. short .. "|r " .. DIM .. (b.lvl > 0 and b.lvl or "?") .. "|r")
            r.c[2]:SetText(b.dist and ((b.approx and L("约 ", "~") or "") .. b.dist .. L(" 码", " yd")) or L("身边", "nearby"))
            r.c[3]:SetWidth(100); r.c[3]:SetText("|cffff9966" .. L("已有队伍", "in a group") .. "|r"); r.c[4]:SetText("")
            r.inv:SetText(L("私聊", "Whisper")); r.inv:SetEnabled(true)
            r.inv:SetScript("OnClick", function() QM.Whisper(b.name, true, b.peer) end)
            r.inv:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(L("私聊请他拉你", "Whisper to ask for an invite"), 1, 0.82, 0)
                GameTooltip:AddLine(QM.WhisperText(QM.FocusQuest(b.peer), true), 0.7, 0.85, 1, true); GameTooltip:Show()
            end)
            r.inv:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnClick", function(_, btn) if btn == "RightButton" then QM.Whisper(b.name, true, b.peer) end end)
            r:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("|cff" .. classHex(b.file) .. b.name .. "|r", 1, 1, 1)
                GameTooltip:AddLine(L("已经有队伍了（邀请时系统提示的，30 分钟后自动当他退队了）", "Already in a group (from the invite reply; cleared after 30 min)"), 1, 0.6, 0.4, true)
                GameTooltip:Show()
            end)
            r:Show()
            y = y + ROW_H + 2
        end
    else
        d.busyHdr:Hide()
    end
    d.child:SetHeight(math.max(y, 10))
    -- 一键私聊：范围内装了插件的 + 身边的 + 已有队伍的，按距离
    local wc = {}
    for _, it in ipairs(rows) do wc[#wc + 1] = { name = it.e.name, peer = it.e, d = it.dist or 9999 } end
    for _, w in ipairs(wr) do wc[#wc + 1] = { name = w.name, d = w.yd or 9999 } end
    for _, b in ipairs(br) do wc[#wc + 1] = { name = b.name, busy = true, peer = b.peer, d = b.dist or 9999 } end
    table.sort(wc, function(a, b) return a.d < b.d end)
    d._whCands = wc
    local nWh = #QM.WhisperCandidates(wc)
    d.whAll:SetText(nWh > 0 and string.format(L("私聊 · %d 人", "Whisper %d"), nWh) or L("私聊 · 暂无", "Whisper - none"))
    d.whAll:SetEnabled(nWh > 0)
    local ch = QM.ShoutChannel()
    local cd = SHOUT_GAP - (now() - QM.lastShout)
    d.shout:SetText(L("喊人 · ", "Call - ") .. ({ say = L("附近", "Say"), yell = L("大喊", "Yell"), ["local"] = L("本地", "Local") })[ch]
        .. (cd > 0 and (" " .. math.ceil(cd) .. "s") or ""))
    -- The action itself enforces cooldown; keep right-click channel selection alive.
    d.shout:SetEnabled(true)
    -- 一键组人：距离从近到远（10-12 用户「距离从近到远顺序」）；装了插件的按坐标码数，身边的 28 / 40 码，说过话的 60，不知道的放最后
    local cand = {}
    for i, it in ipairs(rows) do cand[#cand + 1] = { name = it.e.name, d = it.dist or 9999, o = i } end
    for i, w in ipairs(wr) do cand[#cand + 1] = { name = w.name, d = w.yd or 9999, o = 1000 + i } end
    table.sort(cand, function(a, b) if a.d ~= b.d then return a.d < b.d end return a.o < b.o end)
    local names = {}
    for _, c in ipairs(cand) do names[#names + 1] = c.name end
    d._invNames = names
    local canAll = QM.CanInvite("")
    local nInv = canAll and #QM.InviteCandidates(names) or 0
    d.invAll:SetText(nInv > 0 and string.format(L("组人 · %d 人", "Invite %d"), nInv)
        or (canAll and L("组人 · 暂无", "Invite - none") or L("组人", "Invite")))
    d.invAll:SetEnabled(nInv > 0)
    local chan = ""   -- 11-05 起不进频道（公会 + 密语），没有「频道未连上」这回事
    local why = ""
    if QM.sendError then
        local k = failKind(QM.lastName)
        local txt = (k == "throttle") and L("被限流", "throttled")
            or (k == "lock") and L("客户端暂禁插件通信", "addon comms locked") or tostring(QM.lastName or "?")
        why = "|cffff6060" .. L("共享失败·", "Share failed - ") .. txt .. (QM.lastCode and ("(" .. QM.lastCode .. ")") or "") .. "|r  "
    end
    d.empty:Hide()   -- 10-12 改成列表最上面一行提示（peerHint），身边段总在下面
    d.status:SetText(why .. DIM .. string.format(L("符合 %d 人 · 收到 %d 人数据 · 身边未装插件 %d 人 · %d 秒刷新", "%d match - heard from %d - %d around, no addon - %ds"),
        #allRows, np, #wr, BEAT) .. "|r" .. chan)
    if #allRows > MAX_ROWS or np >= MAX_PEERS then
        d.status:SetText(why .. DIM .. string.format(L("匹配 %d 人 · 显示前 %d 人 · 缓存 %d/%d 人", "%d matches - showing %d - cached %d/%d"), #allRows, #rows, np, MAX_PEERS) .. "|r" .. chan)
    end
    -- FontStrings do not support scripts: expose bounds on the existing refresh button.
    d.refresh:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(string.format(L("匹配 %d 人，当前显示前 %d 人；缓存上限 %d 人。", "%d matches, showing the first %d; cache limit %d."), #allRows, #rows, MAX_PEERS), 1, 1, 1, true)
        GameTooltip:AddLine(L("最多保留 200 人，优先当前任务、范围与进度匹配者；另有最多 20 人临时接收区，10 秒无更新清理。名单可能不完整，不代表全服或区域内所有玩家。", "Retains 200 peers, preferring current quest, range and progress matches; up to 20 candidates stage packets and expire after 10s without updates. Results may be incomplete."), 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    d.refresh:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function QM.Tab()
    local host = _G.GearInsightForeverMain
    return host and rawget(host, "_giQmTab") or nil
end

-- 抽屉贴着页签放（照公会抽屉 placeDrawer：顶边和主面板齐；右边放不下就放到页签左边）
local function placeAtTab(d, host, tab)
    local W = ns.W
    if d:GetParent() ~= host and d.SetParent then d:SetParent(host) end
    if d.SetFrameStrata then d:SetFrameStrata("HIGH") end
    local hh = host.GetHeight and host:GetHeight()
    d:SetHeight(math.max(540, type(hh) == "number" and hh or 540))
    local ht, tt = host.GetTop and host:GetTop(), tab.GetTop and tab:GetTop()
    local dy = (type(ht) == "number" and type(tt) == "number") and (ht - tt) or 0
    local tr, sr = tab.GetRight and tab:GetRight(), W and W.ScreenRight and W.ScreenRight(tab)
    d:ClearAllPoints()
    if type(tr) == "number" and sr and tr + 4 + DW > sr then d:SetPoint("TOPRIGHT", tab, "TOPLEFT", -4, dy)
    else d:SetPoint("TOPLEFT", tab, "TOPRIGHT", 4, dy) end
end

function QM.SavePinPos()
    local d = QM.drawer
    if not d then return end
    local l, t = d.GetLeft and d:GetLeft(), d.GetTop and d:GetTop()
    if type(l) == "number" and type(t) == "number" then dbq().pinPos = { l, t } end
end

local function placePinned(d)
    if d:GetParent() ~= UIParent and d.SetParent then d:SetParent(UIParent) end
    -- 10-12 两次截图：MEDIUM 默认层级被伤害统计（同层）盖住；改 HIGH 又盖住了世界地图（地图也是 HIGH）。
    --   → MEDIUM 层 + 层内级别拉到 120：压过同层的伤害统计等小窗，又低于世界地图 / 主面板（HIGH）
    if d.SetFrameStrata then d:SetFrameStrata("MEDIUM") end
    if d.SetFrameLevel then d:SetFrameLevel(120) end
    local pos = dbq().pinPos
    d:ClearAllPoints()
    if type(pos) == "table" and pos[1] then d:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2])
    else d:SetPoint("CENTER", UIParent, "CENTER", 300, 0) end
end

function QM.SetPinned(on)
    local cfg = dbq()
    local d = QM.drawer
    if on and d and d:IsShown() then QM.SavePinPos() end   -- 在哪钉住就留在哪
    cfg.pinned = on and true or false
    local host = _G.GearInsightForeverMain
    local tab = QM.Tab()
    if d then
        if on then
            placePinned(d); d:Show(); cfg.open = true
        elseif host and tab and host:IsShown() then
            placeAtTab(d, host, tab)
        else
            d:Hide(); cfg.open = false
        end
        if tab and ns.W and ns.W.SelectTab then ns.W.SelectTab(tab, d:IsShown()) end
        QM.Render()
    end
    QM.SyncSubTabs()
    ns.Print(on and L("组队列表已钉在屏幕上：关主面板也留着，拖标题栏挪位置", "Group up pinned: stays on screen, drag the title to move")
        or L("组队列表取消钉住：跟着主面板走", "Group up unpinned"))
end

-- 登录 / reload：上次钉着并开着 → 原位置打开
function QM.RestorePinned()
    local cfg = dbq()
    if not (cfg.pinned and cfg.open) then return end
    QM.drawer = QM.drawer or build(nil)
    placePinned(QM.drawer)
    QM.drawer:Show()
    QM.Request()
    QM.Render()
end

-- 10-16 抽屉模式：quest = 附近任务（原来的），dungeon = 副本组队
function QM.SetMode(m)
    local d = QM.drawer
    if not d or not d.lfg then return end
    dbq().mode = m
    if m == "dungeon" then
        if not d.lfgBuilt then d.lfgBuilt = ns.BuildGroupPanel(d.lfg, DW - 8, 540 - 42) end
        d.lfg:Show()
        if ns.RefreshGroupPage then ns.RefreshGroupPage() end
    else
        d.lfg:Hide()
    end
    local tab = QM.Tab()
    for _, set in ipairs({ d.modeBtns or {}, tab and rawget(tab, "_giSubByMode") or {} }) do
        for k, b in pairs(set) do
            if rawget(b, "_seg") and ns.SegSelect then ns.SegSelect(b, k == m)
            elseif ns.MarkSelected then ns.MarkSelected(b, k == m) end
        end
    end
    QM.SyncSubTabs()
end

-- 10-18 用户截图「任务组队，副本组队做两个折叠子TAB在组队下面」：照左栏大类（UI.lua GROUPS），
--   [附近任务][副本组队] 挂在右侧「组队」页签正下方，抽屉开着才展开、关了收起，下面别的右侧页签跟着让位。
--   10-18 用户截图（钉住状态下顶上还是两个按钮）「任务组队和副本组队拆成两个小TAB」：钉没钉住都一样，主面板开着就用子页签；
--   只有钉住 + 主面板关了（子页签跟着主面板藏起来）时，抽屉顶上才出那两个切换按钮兜底
local SUB_W, SUB_H, SUB_GAP = 86, 24, 4
function QM.SyncSubTabs()
    local host, tab, d = _G.GearInsightForeverMain, QM.Tab(), QM.drawer
    local hostShown = host and host:IsShown() and true or false
    local subs = tab and rawget(tab, "_giSubs")
    local useSubs = subs and hostShown and true or false
    if d and d.modeBtns then
        for _, b in pairs(d.modeBtns) do b:SetShown(not useSubs) end
        local m = dbq().mode == "dungeon" and L("副本组队 · 测试", "Dungeons (test)") or L("附近任务", "Nearby quests")
        d.title:SetText(useSubs and (L("组队", "Group up") .. "  " .. DIM .. m .. "|r") or L("组队", "Group up"))
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
    -- 折叠子页签（副本组队 HOLD 没装 = 只有附近任务一个，不出子页签，和以前一样）
    if ns.BuildGroupPanel and (ns.SegButton or ns.Button) then
        tab._giSubs, tab._giSubByMode = {}, {}
        for _, m in ipairs({ { "quest", L("附近任务", "Nearby quests"), L("同任务的人 · 附近 · 实时", "players on your quests - nearby - live") },
            { "dungeon", L("副本·测试", "Dungeons (test)"), L("测试版（10-19 用户「暂时标记为测试状态，不对外放出」）：只在开发安装里有，不随发行包发布。游戏自带的寻求组队（按 I 那个），全服都看得到", "Test build, not in public releases. The game's own group finder, server-wide") } }) do
            local b = (ns.SegButton or ns.Button)(host, m[2], SUB_W, SUB_H, function() QM.SetMode(m[1]) end)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(m[2], 1, 0.82, 0)
                GameTooltip:AddLine(m[3], 1, 1, 1, true); GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:Hide()
            tab._giSubs[#tab._giSubs + 1] = b
            tab._giSubByMode[m[1]] = b
        end
    end
    tab:SetScript("OnClick", function()
        if ns.PerfGuard and ns.PerfGuard.UserOpened then pcall(ns.PerfGuard.UserOpened) end   -- 10-22 自动卡顿检测暂停 / 关掉过组队：玩家自己点开 = 恢复，以后不再替他关
        QM.drawer = QM.drawer or build(host)
        local d = QM.drawer
        local cfg = dbq()
        if d:IsShown() then d:Hide(); cfg.open = false; W.SelectTab(tab, false); QM.SyncSubTabs(); return end
        if cfg.pinned then
            placePinned(d)
        else
            -- 和公会抽屉同一个位置：开这个就把那个关掉
            local gt = rawget(host, "_giGuildTab")
            if gt and rawget(gt, "_drawer") then gt._drawer:Hide(); W.SelectTab(gt, false) end
            local gh = ns.GuildHome   -- 10-18 本公会抽屉也在同一个位置
            if gh and gh.drawer and gh.drawer:IsShown() then gh.drawer:Hide(); if gt then W.SelectTab(gt, false) end end
            if gh and gh.SyncSubTabs then pcall(gh.SyncSubTabs) end
            placeAtTab(d, host, tab)
        end
        d:Show(); cfg.open = true; W.SelectTab(tab, true)
        if d.lfg then QM.SetMode(cfg.mode or "quest") end
        QM.SyncSubTabs()
        pcall(QM.AskGuildRoster)
        QM.Request()
        QM.ScanNear()
        QM.Render()
    end)
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
    if W.KeepSideTabsOnScreen then W.KeepSideTabsOnScreen(host) end
end

ns.QMAttach = attach   -- 10-18 按需加载：主插件 UI.lua ns.OpenModule 调

-- /gi 组队：打开主面板 + 右侧「组队」抽屉，并切到指定模式
function ns.OpenGroupDrawer(mode)
    local host = _G.GearInsightForeverMain
    if not (host and host:IsShown()) and ns.ToggleMain then ns.ToggleMain() end
    pcall(attach)
    local tab = QM.Tab and QM.Tab()
    if not (QM.drawer and QM.drawer:IsShown()) and tab then
        local click = tab:GetScript("OnClick")
        if click then click(tab) end
    end
    if mode then QM.SetMode(mode) end
end
if hooksecurefunc and type(ns.ToggleMain) == "function" then
    hooksecurefunc(ns, "ToggleMain", function() pcall(attach) end)
end

-- ---------- 事件 ----------
local ev = CreateFrame("Frame")
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
elseif RegisterAddonMessagePrefix then pcall(RegisterAddonMessagePrefix, PREFIX) end
for _, e in ipairs({ "CHAT_MSG_ADDON", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP",
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_SYSTEM", "GROUP_ROSTER_UPDATE", "GUILD_ROSTER_UPDATE" }) do
    local valid = not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e)
    if valid then pcall(ev.RegisterEvent, ev, e) end
end
ev:SetScript("OnEvent", function(_, e, a1, a2, _, a4, ...)
    if e == "CHAT_MSG_ADDON" then
        if a1 == PREFIX then pcall(QM.Handle, a4, a2, a3) end
    elseif e == "CHAT_MSG_SYSTEM" then
        pcall(QM.OnSystemMsg, a1)
    elseif e == "GUILD_ROSTER_UPDATE" then
        QM.guildDirty = true   -- 只记一笔，抽屉开着时由每秒那轮 RebuildGuild 处理（10 秒最多一次）
    elseif e == "GROUP_ROSTER_UPDATE" then
        QM.dirty = true   -- 有人进队 / 退队：列表和一键组人的人数跟着变
        -- 10 分钟内邀请过、现在在队里的 → 记录结果「进队了」
        for sn, t in pairs(QM.invited) do
            if now() - t <= 600 and UnitInParty and UnitInParty(sn) then pcall(QM.SetResult, sn, "joined") end
        end
    elseif e == "CHAT_MSG_SAY" or e == "CHAT_MSG_YELL" or e == "CHAT_MSG_EMOTE" or e == "CHAT_MSG_TEXT_EMOTE" then
        pcall(QM.Heard, a2, e, (select(8, ...)))   -- 聊天事件第 12 个参数 = 说话人 GUID
    elseif e == "PLAYER_ENTERING_WORLD" then
        if C_Timer and C_Timer.After then C_Timer.After(6, function() dirtyAt = now() end) end
        if not QM._restored then
            QM._restored = true
            pcall(QM.RestorePinned)
            if not (QM.drawer and QM.drawer:IsShown()) or not dbq().autoPlates then pcall(QM.PlatesOnClose) end
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
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.qm = function(rest, rawRest)
    if rest == "tag on" or rest == "tag off" then
        dbq().noTag = (rest == "tag off") or nil
        ns.Print(rest == "tag on" and L("组队：私聊 / 喊人 / 道谢最前面加 [GearInsight插件]", "Group up: messages prefixed with [GearInsight]")
            or L("组队：私聊 / 喊人 / 道谢不再加 [GearInsight插件]", "Group up: no [GearInsight] prefix"))
    elseif rest == "say" or rest == "yell" or rest == "local" then
        dbq().shoutCh = rest
        ns.Print(L("喊人频道：", "Call channel: ") .. QM.ShoutChannelName(rest))
        QM.dirty = true
    elseif rest == "text" or rest:sub(1, 5) == "text " then
        local t = ((rawRest or rest):match("^[^ 	]*[ 	]*(.-)$") or ""):gsub("^[ 	]+", "")   -- 用原样的文字（不转小写）
        dbq().shoutText = (t ~= "") and t or nil
        ns.Print(t ~= "" and (L("喊人内容已改：", "Call text set: ") .. QM.ShoutText()) or L("喊人内容恢复默认", "Call text reset"))
    elseif rest == "log" then
        local H = QM.History()
        if #H == 0 then ns.Print(L("组队：还没有邀请记录", "Group up: no invite history yet")) return end
        ns.Print(string.format(L("组队 · 最近邀请（共 %d 条，最多存 %d 条）", "Group up - recent invites (%d stored, max %d)"), #H, HIST_MAX))
        for i, rec in ipairs(H) do
            if i > 10 then break end
            local qs = {}
            for _, v in pairs(rec.quests or {}) do
                if v[4] then qs[#qs + 1] = v[4] .. " " .. (v[3] and v[3] > 0 and (v[2] .. "/" .. v[3]) or (v[1] .. "%")) end
            end
            ns.Print(string.format("  %s  %s Lv%s  %s%s", ago(rec.t), rec.n or "?", tostring(rec.lvl or "?"), QM.ResultText(rec.r),
                #qs > 0 and ("  · " .. table.concat(qs, "；")) or ""))
        end
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
    elseif rest == "pin" then
        QM.drawer = QM.drawer or build(nil)
        QM.SetPinned(not dbq().pinned)
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
        local cv = function(k) if not GetCVar then return "?" end local ok, v = pcall(GetCVar, k); return ok and tostring(v) or "err" end
        local nNear = 0
        for _ in pairs(QM.near) do nNear = nNear + 1 end
        ns.Print("QM probe 姓名板: 看到 " .. (ps.plates or 0) .. " 个 · 友方玩家 " .. (ps.players or 0) .. " · 名字保密 " .. (ps.secret or 0)
            .. " · 友方开关 " .. tostring((friendCVar())) .. "=" .. tostring(select(2, friendCVar()))
            .. " · 身边列表 " .. nNear .. " 人 · GetNamePlates " .. has(C_NamePlate and C_NamePlate.GetNamePlates))
        local pc, okList = QM.PlateCVars()
        ns.Print("QM probe 姓名板相关设置: " .. (okList and (#pc > 0 and table.concat(pc, " · ") or "（没有匹配的）") or "（客户端没有 C_Console.GetAllCommands）"))
    else
        local host = _G.GearInsightForeverMain
        if not (host and host:IsShown()) then ns.ToggleMain() end
        host = _G.GearInsightForeverMain
        local tab = host and rawget(host, "_giQmTab")
        if tab and not (QM.drawer and QM.drawer:IsShown()) then tab:GetScript("OnClick")(tab) end
    end
end

-- ---------- 10-16 队伍解散后道谢（用户「当组队解散的时候提示用户（可开关）是否感谢一路陪伴，话术你来定」）----------
-- 记队友：GROUP_ROSTER_UPDATE 时按完整名（名-服务器）记进队时间，离队时累计；一起待满 5 分钟才算「一路陪伴」。
-- 触发：从「有队友」变成「不在队伍里」（解散 / 自己退 / 被踢）；同一支队伍只问一次；战斗中不弹，脱战再弹；20 秒没点自动收起。
-- 发送：只在玩家点「发送感谢」后，每位队友一条私聊、间隔 1 秒。开关 ns.db.qm.thanks（默认开），/gi 感谢 开 | 关
local TH = { mates = {}, inGroup = false, asked = false }
QM.Thanks = TH
TH.MIN = 300
-- 10-17 用户「感谢的带一下感谢你，德鲁伊~祝你快乐游戏…搞 5 个随机选项」：%s = 队友职业名（拿不到职业时用「朋友」）
TH.LINES = {
    { "感谢你，%s~ 这一路多亏有你，祝你快乐游戏，天天出好装备！", "Thank you, %s~ Couldn't have done it without you. Have fun and may the loot be with you!" },
    { "辛苦啦，%s！和你组队很开心，祝你练级顺利，有缘再一起冒险~", "Thanks for the hard work, %s! Great grouping with you - happy leveling, see you out there~" },
    { "谢谢你的陪伴，%s~ 祝你欧气满满，打怪必掉好东西！", "Thanks for the company, %s~ Wishing you all the luck and great drops!" },
    { "多谢%s一路照应！祝你一路顺风、早日满级，下次见还一起~", "Thanks for watching my back, %s! Safe travels, ding 60 soon, and let's team up again~" },
    { "感谢同行，%s~ 合作愉快，祝你在艾泽拉斯玩得开心！", "Thanks for tagging along, %s~ Great teamwork - have fun in Azeroth!" },
}
-- 记得一起做的任务时，第 5 条换成带任务名的（仍是 5 选 1）
TH.QUEST_LINE = { "感谢同行，%s~ 一起做「%s」很愉快，祝你练级顺利、玩得开心！", "Thanks, %s~ Doing \"%s\" together was fun - happy leveling!" }

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

function TH.Roster()
    local t = now()
    local present, n = members()
    for fn, cls in pairs(present) do
        local m = TH.mates[fn]
        if not m then m = { total = 0 }; TH.mates[fn] = m end
        if not m.since then m.since = t end
        if type(cls) == "string" then m.cls = cls end
    end
    for fn, m in pairs(TH.mates) do
        if not present[fn] and m.since then m.total = m.total + (t - m.since); m.since = nil end
    end
    if next(present) then
        if not TH.inGroup then TH.asked = false; TH.doneAt = nil; TH.doneQuest = nil end   -- 新的一支队伍
        TH.inGroup = true
        local ok, q = pcall(QM.SelectedQuest)
        if ok and q and q.title then TH.quest = q.title end
    elseif TH.inGroup and n <= 1 then
        TH.inGroup = false
        TH.Ended()
    end
end

function TH.Ended()
    local list = {}
    TH.cls = {}
    local done = TH.RecentDone()
    for fn, m in pairs(TH.mates) do
        if (m.total or 0) >= TH.MIN or (done and m.doneAt == TH.doneAt) then list[#list + 1] = fn; TH.cls[fn] = m.cls end
    end
    table.sort(list)
    TH.mates = {}
    local quest = done and TH.doneQuest or TH.quest
    TH.quest = nil
    if #list == 0 or TH.asked or not TH.On() then return end
    -- 自己点的退队：不问（10-17）；⛔ 例外（10-18 用户「刚刚完成任务的情况下，退出队伍也要弹出感谢提示框」）：刚一起交了任务
    if not done and TH.SelfLeft and TH.SelfLeft() then return end
    TH.asked = true
    TH.lastDone = done
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        TH.pending = { list = list, quest = quest }   -- 脱战再弹
        return
    end
    TH.Show(list, quest)
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
    local pool = {}
    for _, l in ipairs(TH.LINES) do pool[#pool + 1] = string.format(L(l[1], l[2]), who) end
    if quest and quest ~= "" then pool[#pool] = string.format(L(TH.QUEST_LINE[1], TH.QUEST_LINE[2]), who, quest) end
    return QM.Tagged(pool[math.random(#pool)])
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

function TH.Show(list, quest)
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
        f.body:SetPoint("TOPLEFT", 14, -32); f.body:SetPoint("RIGHT", -14, 0); f.body:SetJustifyH("CENTER"); f.body:SetSpacing(3)
        f.send = ns.Button(f, L("发送感谢", "Say thanks"), 100, 22, function()
            f:Hide(); pcall(TH.Send, f.list or {}, f.quest)
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
    f.t:SetText(TH.lastDone and quest and quest ~= "" and string.format(L("刚一起完成了「%s」", "Just finished \"%s\" together"), quest)
        or L("队伍解散了", "Group disbanded"))
    local names = {}
    for i, fn in ipairs(list) do
        if i > 4 then break end
        names[#names + 1] = fn:match("^([^%-]+)") or fn
    end
    f.body:SetText(L("要不要和刚才的队友说声谢谢？", "Say thanks to your teammates?") .. "\n|cffffd100" .. table.concat(names, L("、", ", "))
        .. (#list > 4 and string.format(L(" 等 %d 人", " and %d more"), #list - 4) or "") .. "|r")
    TH.shownAt = now()
    f:Show()
    TH.token = (TH.token or 0) + 1
    local my = TH.token
    if C_Timer and C_Timer.After then
        C_Timer.After(20, function() if TH.token == my and f:IsShown() then f:Hide() end end)
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
            TH.MarkSelfLeft()
            if not TH.lastDone then   -- 刚一起交了任务：自己退队也照样问（10-18）
                TH.pending = nil
                if TH.frame and TH.frame:IsShown() and TH.shownAt and now() - TH.shownAt <= 3 then TH.frame:Hide() end
            end
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
        if p and TH.On() then pcall(TH.Show, p.list, p.quest) end
    else
        pcall(TH.Roster)
    end
end)
QM._thanksEvent = thEv:GetScript("OnEvent")   -- 测试用
QM._thEv = thEv

ns.ExtraSlash["感谢"] = function(rest)
    if rest == "开" or rest == "on" then TH.Set(true)
    elseif rest == "关" or rest == "off" then TH.Set(false)
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
