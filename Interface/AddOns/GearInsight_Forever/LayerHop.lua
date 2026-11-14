-- B · 多位面切换：做任务时换到「同图里怪多、抢的人少」的层（10-28，HOLD；设计稿第五节）
-- 11-06 用户「给练级过程中的会员用的，互相互助切位面」：改成以会员互助为主（我想换一层 / 请他拉我过去 / 会员求助自动拉 / 到了自动退队）。
--   参考了两个 MIT 开源插件的做法（只学思路，没有照抄代码）：
--     · LayerHopper（Copyright (c) 2020 psynct，MIT）：公会消息求换层，别层会员直接邀请；GUID 第 5 段 zoneUID 认层
--     · Guild Master Forever（Copyright (c) Olympus addon contributors / SwiftyPigeon512，MIT，《无限》16001 专用）：
--       无限客户端里 InviteUnit 可以在插件消息回调里调、AcceptGroup 在 PARTY_INVITE_REQUEST 里调、看到换层后 LeaveParty 自动退队，
--       「离队后层会留下」；公会成员互相求助默认自动拉，陌生人才弹框
--   ⛔ 仍然：副本 / 战斗里不发起不邀请；我在别人的队伍里时不自动拉（弹框）；不循环换层；不踢人
-- 唯一手段：找那一层装了本插件、打开了「帮别人换层」的玩家，由他点一下邀请你进队 —— 进队就到队长那一层（暴雪公开机制）。
-- 打分只用插件网络里看得到的数据（公共频道 GIForeverLY 的心跳）：
--   T(z) 该层插件用户最近报告看到的「我的任务目标怪」数量（多人报告取最大，不叠加）
--   C(z) 该层正在做同一个任务（任务 ID 相同）的插件用户数      P(z) 该层插件用户数
--   F(z) 新鲜度：最近一次报告 ≤ 5 分钟 = 1，之后 5 分钟内线性降到 0
--   S(z) = F × (T + 1) / (C + 0.3·P + 1)；最佳层 ≥ 1.5 × 当前层、且那层有在线帮手，才提示「建议换过去」
-- ⛔ 10-28 用户拍板 + 设计稿红线：只做任务怪（不做采集物 / 稀有精英 / 世界首领）；副本里不工作、出副本 10 分钟内不推荐；
--    战斗中不能发起；每人 3 分钟最多发起 1 次；帮手每 10 分钟最多帮 5 次；邀请只在帮手的按钮点击里调；不循环换层；不自动退队。
local _, ns = ...
local LY = ns.Layer
if not LY then return end
local L = function(cn, en) return ns.L(cn, en) end

local LH = {}
ns.LayerHop = LH
LH.COOLDOWN = 60          -- 秒：发起换层请求的冷却（11-07 用户「3分钟是不是时间太长了？」：180 → 60；帮手那边有 10 分钟 5 次 / 弹框 3 次 / 同人 5 分钟的保护）
LH.AFTER_INST = 600       -- 秒：出副本后多久内不推荐
LH.FRESH = 300            -- 秒：报告多新算满分
LH.RATIO = 1.5
LH.HELP_MAX, LH.HELP_WIN = 5, 600
LH.ACCEPT_WIN = 30        -- 秒：发起后多久内接受帮手的邀请
LH.CHAIN_MAX = 3          -- 11-10 用户「这里如果一个人没接，会自动换一个人？」「自动换人要做啊」：点名请人 30 秒没邀请 → 自动换下一位，一轮最多请几个人
LH.SAME_AFTER = 45        -- 秒：进队这么久后亲眼读到的还是原来那层 → 判「没换成」
LH.JOIN_WIN = 300         -- 秒：进队后这么久内层码变了都算到了（中途读不到怪就一直等，指一下怪就出结果）
-- 11-12 用户截图：进了 Closing Time 的队、人已经到了他那层，页面还写「正在确认换没换层」、自己仍是旧层；再点「我想换一层」又请到他。
LH.INFER_AFTER = 15       -- 秒：进队这么久一只怪都没读到 → 按队长心跳里报的层认我的层（进队就到队长那层，暴雪机制）
LH.PROBE_AT = { 2, 4, 6, 9, 12, 16, 20, 25, 30, 40, 60, 90, 120, 180, 240 }   -- 进队后这些秒主动把目标 / 焦点 / 软目标 / 队友目标 / 姓名板读一遍
LH.RECENT_WIN = 600       -- 秒：拉过我的人（和他那层）这么久内「我想换一层」不再找
LH.ALREADY_WIN = 120      -- 秒：刚换成功这么久内再点「我想换一层」→ 直接说已经换过来了
LH.recent = {}            -- [帮手名] = { t, m, z, from, ok }
LH.lastHop = nil          -- { ok, who, m, z, from, t, inferred }
LH.lastReq = -1e9
LH.pending = nil          -- { m, z, n, t, helper }
LH.helped = {}            -- 帮过的时间
LH.popups = {}            -- [nonce] = { from, z, q, t }
LH.askedAt = {}           -- 11-06 用户「前 6 个人一直被骚扰，可以平均一下吗」：[名字] = 我上次请他的时间（本机）
LH.popped = {}            -- 我没开帮忙、被点名弹框的时间（10 分钟最多 3 次）
LH.askedBy = {}           -- [请求人] = 他上次点名我的时间（5 分钟内重复点名我 → 忽略）
LH.POP_MAX, LH.POP_WIN, LH.REASK = 3, 600, 300
LH.seenReq = {}           -- [nonce] = 时间：同一请求公会 + 频道各来一份，只处理一次

local function now() return (GetTime and GetTime()) or 0 end
local function me() return UnitName and UnitName("player") or "?" end
-- 11-09 review：帮手回执 C 里的名字是 UnitName（《无限》可能只有「名」），等待的帮手名是心跳里的「名 姓」→ 原来用 == 比对不上，
--   回执先于邀请到达时自动接受就失效（用户截图：进组得自己点）。同名 / 一个是另一个的「名 + 空格」开头都算同一人
local function sameName(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    a, b = (a:gsub("%-.*$", "")), (b:gsub("%-.*$", ""))
    if a == "" or b == "" then return false end
    if a == b then return true end
    return a:sub(1, #b + 1) == b .. " " or b:sub(1, #a + 1) == a .. " "
end
LH.SameName = sameName
local function leaderName()
    if not UnitIsGroupLeader then return nil end
    for _, u in ipairs({ "party1", "party2", "party3", "party4" }) do
        local ok, isL = pcall(UnitIsGroupLeader, u)
        if ok and isL then
            local n
            if GetUnitName then local ok2, v = pcall(GetUnitName, u, false); if ok2 then n = v end end
            if type(n) ~= "string" or ns.Secret(n) then local ok3, v = pcall(UnitName, u); n = ok3 and v or nil end
            if type(n) == "string" and not ns.Secret(n) then return n end
        end
    end
    return nil
end
LH.LeaderName = leaderName
-- 名字 → 心跳里的 peer（「名」和「名 姓」都认）
function LH.PeerByName(name)
    if type(name) ~= "string" or ns.Secret(name) then return nil end
    local s = name:gsub("%-.*$", "")
    if LY.peers[s] then return LY.peers[s] end
    for k, pe in pairs(LY.peers) do if sameName(k, s) then return pe end end
    return nil
end
-- 11-12：最近拉过我的人（RECENT_WIN 内）→ 记录, 名字
function LH.RecentHelper(name)
    if type(name) ~= "string" or ns.Secret(name) then return nil end
    local t = now()
    for n, r in pairs(LH.recent) do
        if t - (r.t or 0) <= LH.RECENT_WIN and sameName(n, name) then return r, n end
    end
    return nil
end
-- 「我想换一层」要避开的：最近拉过我的人（名字列表）+ 他们那层（同图的层码列表 / 集合）
function LH.Exclusions(m)
    local names, zs, zset = {}, {}, {}
    local t = now()
    for n, r in pairs(LH.recent) do
        if t - (r.t or 0) > LH.RECENT_WIN then LH.recent[n] = nil
        else
            names[#names + 1] = n
            if r.m == m and r.z and not zset[r.z] then zset[r.z] = true; zs[#zs + 1] = r.z end
        end
    end
    table.sort(names); table.sort(zs)
    return names, zs, zset
end
function LH.IsExcluded(peer, m)
    if type(peer) ~= "table" then return false end
    if LH.RecentHelper(peer.name) then return true end
    local _, _, zset = LH.Exclusions(m)
    return (peer.m == m and peer.z and zset[peer.z]) and true or false
end
LH.helpLog = {}          -- 11-06 用户「最近帮助过别人的次数能看到吗，找少的」：我帮人拉层的时间（留 30 分钟），心跳里报 hc
LH.HC_WIN = 1800
function LH.HelpCount()
    local t, n = now(), 0
    for i = #LH.helpLog, 1, -1 do if t - LH.helpLog[i] > LH.HC_WIN then table.remove(LH.helpLog, i) else n = n + 1 end end
    return n
end

-- ---------- 我的任务目标 ----------
-- 任务目标文字「XX slain: 3/10」→ 怪名（按客户端自己的格式串 QUEST_MONSTERS_KILLED 去掉前后缀）
function LH.ObjectiveName(text)
    if type(text) ~= "string" or ns.Secret(text) then return nil end
    -- ⛔ Lua 按字节匹配：全角「：」是 3 个字节，别塞进 [] 字符集（会拆字节，切出半个汉字）→ 半角 / 全角分开写
    local s = text:gsub("%s*:%s*%d+%s*/%s*%d+%s*$", ""):gsub("%s*：%s*%d+%s*/%s*%d+%s*$", "")
    local fmt = _G.QUEST_MONSTERS_KILLED
    if type(fmt) == "string" then
        local head = fmt:match("^(.-)%s*:") or fmt:match("^(.-)%s*：") or fmt
        local pre, post = head:match("^(.-)%%s(.*)$")
        if pre and pre ~= "" and s:sub(1, #pre) == pre then s = s:sub(#pre + 1) end
        if post and post ~= "" and s:sub(-#post) == post then s = s:sub(1, -#post - 1) end
    end
    s = s:gsub("%s+[Ss]lain$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return s ~= "" and s or nil
end

-- 返回 { [questID] = { names = { [怪名] = true }, left = 还差几只 } }（只要「杀怪」类、还没完成的）
function LH.MyQuests()
    local out = {}
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return out end
    local ids = {}
    if C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local n = C_QuestLog.GetNumQuestLogEntries() or 0
        for i = 1, n do
            local ok, info = pcall(C_QuestLog.GetInfo, i)
            if ok and type(info) == "table" and not info.isHeader and info.questID then ids[#ids + 1] = info.questID end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        local n = GetNumQuestLogEntries() or 0
        for i = 1, n do
            local ok, _, _, _, isHeader, _, _, _, qid = pcall(GetQuestLogTitle, i)
            if ok and not isHeader and qid then ids[#ids + 1] = qid end
        end
    end
    for _, qid in ipairs(ids) do
        local ok, objs = pcall(C_QuestLog.GetQuestObjectives, qid)
        if ok and type(objs) == "table" then
            for _, o in ipairs(objs) do
                if o.type == "monster" and not o.finished then
                    local nm = LH.ObjectiveName(o.text)
                    if nm then
                        out[qid] = out[qid] or { names = {}, left = 0 }
                        out[qid].names[nm] = true
                        out[qid].left = out[qid].left + math.max(0, (o.numRequired or 0) - (o.numFulfilled or 0))
                    end
                end
            end
        end
    end
    return out
end

-- 我的任务目标对应的 NPC ID（本机看到过名字对得上的）
function LH.TargetNpcs(quests)
    local names = {}
    for _, q in pairs(quests or LH.MyQuests()) do for nm in pairs(q.names) do names[nm] = true end end
    local ids = {}
    for npc, nm in pairs(LY.names) do if names[nm] then ids[npc] = true end end
    return ids
end

-- 心跳（公共频道）：任务 ID（最多 6 个）+ 看到的怪（最多 8 种，任务目标优先，再按数量）+ 帮手标记
LY.AddFields(function(t, scope)
    -- 11-06 用户截图「（没开帮忙）」：帮手标记原来只在公共频道心跳里带，公会心跳没带 → 会员个个显示没开帮忙。现在所有心跳都带
    if LY.DB().helper then t.hp = 1 end
    t.hc = LH.HelpCount()   -- 最近 30 分钟帮过几次（大家都去找帮得少的；带 0 也带，好和 0.7.0 区分）
    if scope ~= "pub" then return end
    local qs = LH.MyQuests()
    local qids = {}
    for qid in pairs(qs) do qids[#qids + 1] = qid end
    table.sort(qids)
    while #qids > 6 do table.remove(qids) end
    t.q = table.concat(qids, ",")
    local tg = LH.TargetNpcs(qs)
    local list = {}
    for npc in pairs(LY.seen) do
        local n = LY.SeenCount(npc)
        if n > 0 then list[#list + 1] = { npc = npc, n = n, tg = tg[npc] and 1 or 0 } end
    end
    table.sort(list, function(a, b) if a.tg ~= b.tg then return a.tg > b.tg end; if a.n ~= b.n then return a.n > b.n end; return a.npc < b.npc end)
    local parts = {}
    for i = 1, math.min(8, #list) do parts[i] = list[i].npc .. ":" .. math.min(99, list[i].n) end
    t.t = table.concat(parts, ",")
end)

-- ---------- 打分 ----------
-- 返回 rows = { { z, label, T, C, P, F, S, helpers = {名字…}, age, mine } }（按 S 从高到低）, best, curRow
function LH.Score(peers, myM, myZ, quests, localT)
    quests = quests or {}
    local tg = {}
    if localT then for npc in pairs(localT) do tg[npc] = true end end
    local layers = {}
    local function row(z)
        layers[z] = layers[z] or { z = z, T = 0, C = 0, P = 0, age = 1e9, helpers = {} }
        return layers[z]
    end
    if myZ then local r = row(myZ); r.mine = true; r.age = 0; r.T = localT and localT._mine or 0 end
    local t = now()
    for _, p in ipairs(peers) do
        if p.m == myM and p.z and (p.c or 0) >= 2 and not p.inst then
            local r = row(p.z)
            r.P = r.P + 1
            local age = t - (p.seen or 0)
            if age < r.age then r.age = age end
            local seenT = 0
            for npc, n in pairs(p.t or {}) do if tg[npc] then seenT = seenT + n end end
            if seenT > r.T then r.T = seenT end
            for qid in pairs(p.q or {}) do if quests[qid] then r.C = r.C + 1; break end end
            if p.hp and age <= LY.EXPIRE then r.helpers[#r.helpers + 1] = p.name end
        end
    end
    local rows, cur = {}, nil
    for _, r in pairs(layers) do
        r.F = (r.age <= LH.FRESH) and 1 or math.max(0, 1 - (r.age - LH.FRESH) / LH.FRESH)
        r.S = r.F * (r.T + 1) / (r.C + 0.3 * r.P + 1)
        r.label = LY.Label(myM, r.z)
        rows[#rows + 1] = r
        if r.mine then cur = r end
    end
    table.sort(rows, function(a, b) if a.S ~= b.S then return a.S > b.S end; return a.z < b.z end)
    local best
    for _, r in ipairs(rows) do
        if not r.mine and #r.helpers > 0 and r.F > 0 then best = r; break end
    end
    if best and cur and best.S < LH.RATIO * cur.S then best = nil end
    if best and not cur then best = nil end
    return rows, best, cur
end

-- 为什么现在不能发起（nil = 可以）
function LH.Blocked()
    if not LY.DB().on then return "off" end
    if LY.InInstance() then return "instance" end
    -- 11-12：进了帮手的队、还在确认换没换层（哪怕自己先退了队）→ 不许再发一次求助（原来 30 秒后就放行，又请到同一个人）
    if LH.pending and LH.pending.joinedAt and now() - LH.pending.joinedAt < LH.JOIN_WIN then return "confirming" end
    if IsInGroup and IsInGroup() then return "ingroup" end   -- 在队伍里接不了别人的邀请（11-06）
    if now() - (LY.leftInstanceAt or -1e9) < LH.AFTER_INST then return "afterinst" end
    if LY.InCombat() then return "combat" end
    if not LY.Confirmed() then return "nolayer" end
    if now() - LH.lastReq < LH.COOLDOWN then return "cooldown" end
    if LH.pending and now() - LH.pending.t < LH.ACCEPT_WIN then return "pending" end
    return nil
end
function LH.CooldownLeft() return math.max(0, math.ceil(LH.COOLDOWN - (now() - LH.lastReq))) end

-- 当前的推荐（给页面 / 任务提示用）
function LH.Current()
    local m, z = LY.Mine()
    if not m or not z or not LY.Confirmed() then return {}, nil, nil end
    local qs = LH.MyQuests()
    local tg = LH.TargetNpcs(qs)
    local mineT = 0
    for npc in pairs(tg) do mineT = mineT + LY.SeenCount(npc) end
    tg._mine = mineT
    local rows, best, cur = LH.Score(LY.Peers("pub"), m, z, qs, tg)
    if LH.Blocked() == "instance" or LH.Blocked() == "afterinst" then best = nil end
    return rows, best, cur
end

-- ---------- 发起：求邀请 ----------
-- 11-06 用户「给练级过程中的会员用的，互相互助切位面」：
--   LH.Request(z)      z = 指定层（B 推荐的那层）；z = nil = 「我想换一层」：同图别的层谁都行
--   LH.RequestFrom(名) 「请他拉我过去」：只发给这一个会员（插件密语），也只自动接受他的邀请
--   都同时发公会 + 公共频道（RequestFrom 只发密语）；帮手那边弹框，点「邀请」才邀
local function nonce() return string.format("%x%04x", math.floor(now() * 10) % 65536, math.random(0, 65535)) end
local function firstQuest()
    local q
    for qid in pairs(LH.MyQuests()) do q = q and math.min(q, qid) or qid end
    return q
end
-- 11-06 用户「这个会不会前6个人一直被骚扰，可以平均一下吗」：从这一层 / 这张图的全部会员里挑，不只是显示出来的几个
function LH.PickHelper(list, skip)
    if type(list) ~= "table" or #list == 0 then return nil end
    local tiers = { {}, {}, {} }
    for _, peer in ipairs(list) do
        if skip and skip[peer.name] then
            -- 11-10 自动换人：本轮问过的不再问
        elseif peer.hp and not peer.ig then table.insert(tiers[1], peer)
        elseif peer.hp then table.insert(tiers[2], peer)
        else table.insert(tiers[3], peer) end
    end
    local cand = (#tiers[1] > 0 and tiers[1]) or (#tiers[2] > 0 and tiers[2]) or tiers[3]
    -- 11-06 用户「不是我一直请，主要是最近帮助过别人的次数能看到吗，找少的」：按大家心跳里报的 hc（最近 30 分钟帮过几次）从少到多
    local function key(peer) return (peer.hc == nil) and 1 or 0, peer.hc or 0, LH.askedAt[peer.name] or -1e12 end
    local function less(a1, a2, a3, b1, b2, b3)
        if a1 ~= b1 then return a1 < b1 end
        if a2 ~= b2 then return a2 < b2 end
        return a3 < b3
    end
    local best, ties = nil, {}
    local k1, k2, k3
    for _, peer in ipairs(cand) do
        local c1, c2, c3 = key(peer)
        if not best or less(c1, c2, c3, k1, k2, k3) then best, ties, k1, k2, k3 = peer, { peer }, c1, c2, c3
        elseif c1 == k1 and c2 == k2 and c3 == k3 then ties[#ties + 1] = peer end
    end
    if #ties > 1 then best = ties[math.random(1, #ties)] end
    return best and best.name or nil, best
end

-- 11-06 兼容 0.7.0 的帮手：点名只写「名」（0.7.0 拿 UnitName 比，无限 UnitName 只给名）
local function toName(n) return (tostring(n or ""):gsub("%-.*$", ""):match("^(%S+)")) or n end

-- 11-08 用户「点了以后毫无反馈？」「我到底切换了没」：30 秒没人邀请 → 请求作废时屏幕中间提示 + 页面状态行写结果（以前静默作废）
LH.last = nil             -- { ok = bool, text, t }
function LH.SetResult(ok, text)
    LH.last = { ok = ok, text = text, t = now() }
    LY.Flash(text, ok and 0.2 or 1, ok and 1 or 0.45, ok and 0.6 or 0.35)
    LY.dirty = true
end
local function watch(p)
    LH.last = nil
    if not (C_Timer and C_Timer.After) then return end
    C_Timer.After(LH.ACCEPT_WIN + 1, function()
        if LH.pending ~= p or p.joinedAt then return end   -- 到了 / 已进队在等层变化：别处收尾（11-09 原来只有「别的图」求助记进队）
        LH.pending = nil
        local who = p.helper and tostring(p.helper):gsub("%-.*$", "")
        if who and p.chain and LH.ChainNext(p.chain, who) then return end
        local text
        if who and p.chain and p.chain.n > 1 then
            text = string.format(L("没换成：连请了 %d 位公会会员都没在 30 秒内邀请你（可能在队伍里、走开了、弹框没点），过会儿再试", "No move: %d guildmates in a row didn't invite you - try again later"), p.chain.n)
        elseif who then
            text = string.format(L("没换成：%s 30 秒内没邀请你（他可能在队伍里、走开了、弹框没点），这层没有别人可请了", "No move: %s didn't invite you within 30 sec - nobody else to ask"), who)
        elseif p.free == 0 then
            text = L("没换成：别的层的公会会员都在队伍里 / 没开帮忙（在队伍里的不会被群发打扰）。可以点某一层的「过去」单独请一个人，或等他们出队",
                "No move: guildmates on other layers are grouped or not helping - use \"Go\" on a layer to ask one person")
        else
            text = L("没换成：30 秒内没有公会会员邀请你（可能走开了）。可以点某一层的「过去」单独请一个人", "No move: nobody invited you within 30 sec - use \"Go\" on a layer to ask one person")
        end
        LH.SetResult(false, text)
    end)
end
LH.Watch = watch

-- 11-10 用户截图「点了也没人邀请我」：别的层能帮的公会会员（开了帮忙、没在队伍里、不在副本）有几个；0 个时超时提示说清楚原因
function LH.FreeHelpers(z)
    local m, myZ = LY.Mine()
    local n = 0
    for _, p in ipairs(LY.Peers("guild")) do
        if p.m == m and p.z and p.z ~= myZ and (not z or p.z == z) and p.hp and not p.ig and not p.inst
            and not (LY.IsMe and LY.IsMe(p.full or p.name)) and (z or not LH.IsExcluded(p, m)) then n = n + 1 end
    end
    return n
end
-- 返回 false, why[, 给玩家看的整句]
function LH.Request(z)
    local st, txt = LH.AlreadyMoved()
    if st then return false, st, txt end
    local why = LH.Blocked()
    if why then return false, why end
    local m, myZ = LY.Mine()
    if z and z == myZ then return false, "same" end
    local n = nonce()
    LH.lastReq = now()
    -- 11-12「再点一次还是选中同一个人」：随便换一层时，带上最近拉过我的人（x，最多 3 个）和他们那层（xz），帮手那边自己让开，我这边也不接
    local xn, xz, xset = {}, nil, nil
    if not z then
        local names, zs, zset = LH.Exclusions(m)
        for i = 1, math.min(3, #names) do xn[i] = toName(names[i]) end
        if #zs > 0 then xz = table.concat(zs, ","); xset = zset end
    end
    LH.pending = { m = m, z = z, n = n, t = now(), from = myZ, hop = true, free = LH.FreeHelpers(z), xset = xset }
    watch(LH.pending)
    local msg = LY.Encode("R", { m = m, z = z, f = myZ, q = firstQuest(), n = n, x = (#xn > 0) and table.concat(xn, ",") or nil, xz = xz })
    LY.Log("我求换层 z=" .. tostring(z or "任意") .. " from=" .. tostring(myZ))
    if IsInGuild and IsInGuild() then LY.Queue("GUILD", msg) end
    LY.Queue("PUB", msg)
    return true
end
function LH.RequestFrom(name)
    local why = LH.Blocked()
    if why then return false, why end
    local peer = name and LY.peers[name]
    local m, myZ = LY.Mine()
    if not peer or peer.m ~= m or not peer.z or peer.z == myZ then return false, "same" end
    -- 11-06 用户「没开帮忙的话，可以有个按钮请求」：没开帮忙也能请，他那边弹框问，点了才拉（不自动）
    local n = nonce()
    LH.lastReq = now()
    LH.pending = { m = m, z = peer.z, n = n, t = now(), from = myZ, helper = name, hop = true }
    watch(LH.pending)
    LH.askedAt[name] = now()
    LY.Queue("WHISPER:" .. (peer.full or name), LY.Encode("R", { m = m, z = peer.z, f = myZ, q = firstQuest(), n = n, to = toName(name) }))
    LY.Log("我请 " .. tostring(name) .. " 拉我 z=" .. tostring(peer.z))
    return true
end

-- 11-06 用户「位面不分地图吧」「为啥他们我就无法让他们邀请我呢」：位面是整块大陆共用的，层码却按地图编号（同一层在不同地图的
--   GUID 段不一样）→ 别的图的会员看不出和我是不是同层，但他拉我进队照样把我带到他那层。
--   请别的图的会员拉我：只发给他（密语 R，any=1），他那边不比地图 / 层；我进队后看层变没变：变了 = 到了（照旧自动退队），
--   25 秒没变 = 他本来就和我同层 → 提示一下并按开关退队
function LH.RequestAny(name)
    local why = LH.Blocked()
    if why then return false, why end
    local peer = name and LY.peers[name]
    if not peer then return false, "same" end
    local m, myZ = LY.Mine()
    local n = nonce()
    LH.lastReq = now()
    LH.pending = { m = m, n = n, t = now(), from = myZ, helper = name, hop = true, any = true }
    watch(LH.pending)
    LH.askedAt[name] = now()
    LY.Queue("WHISPER:" .. (peer.full or name), LY.Encode("R", { any = 1, m = peer.m, z = peer.z, f = myZ, n = n, to = toName(name) }))
    LY.Log("我请别图的 " .. tostring(name) .. " 拉我")
    return true
end

-- 11-10 用户「这里如果一个人没接，会自动换一个人？」「自动换人要做啊」：
--   页面「过去」/「请他们拉我」走这里：先请 list 里最近帮得最少的一位（RequestFrom = 同图点名层；far = 别的图，RequestAny）；
--   30 秒没邀请（watch 超时）→ ChainNext 自动请下一位：本轮问过的跳过、自动续请不受 60 秒冷却限制，一轮最多 CHAIN_MAX 人；
--   名单上的人换了层 / 不在了（RequestFrom 回 same）就跳过再挑。迟到的邀请照样接（AcceptReason 认公会会员，不认点名）
local function chainAsk(ch)
    while ch.n < LH.CHAIN_MAX do
        local who, pe, any = LH.PickHelper(ch.list, ch.tried), nil, false
        if not who then who = LH.PickHelper(ch.far, ch.tried); any = true end
        if not who then return nil end
        ch.tried[who] = true
        local ok, why
        if any then ok, why = LH.RequestAny(who) else ok, why = LH.RequestFrom(who) end
        if ok then
            ch.n = ch.n + 1
            if LH.pending then LH.pending.chain = ch end
            return who
        end
        if why ~= "same" then return nil, why end
    end
    return nil
end
function LH.AskChain(list, far)
    local st, txt = LH.AlreadyMoved()
    if st then return nil, st, txt end
    local why = LH.Blocked()
    if why then return nil, why end
    local ch = { list = list or {}, far = far or {}, tried = {}, n = 0 }
    -- 11-12：刚拉过我的人不再请（本轮当成问过）
    local skipped
    for _, lst in ipairs({ ch.list, ch.far }) do
        for _, pe in ipairs(lst) do
            if pe.name and LH.RecentHelper(pe.name) then ch.tried[pe.name] = true; skipped = skipped or pe.name end
        end
    end
    local who, why2 = chainAsk(ch)
    if not who then
        if skipped and not why2 then
            return nil, "dup", string.format(L("这里只有刚拉过你的 %s 能请（再请也是同一个人）：换别的层或等别人上线再试", "Only %s (who just pulled you) is here - try another layer"),
                (tostring(skipped):gsub("%-.*$", "")))
        end
        return nil, why2 or "nobody"
    end
    return who
end
function LH.ChainNext(ch, last)
    if ch.n >= LH.CHAIN_MAX then return false end
    local saved = LH.lastReq
    LH.lastReq = -1e9          -- 自动续请：不吃冷却（其他拦截照旧：进队 / 战斗 / 副本 / 关了）
    local who = chainAsk(ch)
    if not who then LH.lastReq = saved; return false end
    LY.Log("自动换人：" .. tostring(last) .. " 没邀请 → 请 " .. tostring(who))
    LH.SetResult(true, string.format(L("%s 30 秒没邀请你，自动换 %s 试试（第 %d / %d 位）", "%s didn't invite - asking %s (%d/%d)"),
        tostring(last), tostring(who):gsub("%-.*$", ""), ch.n, LH.CHAIN_MAX))
    return true
end

-- 别的图的会员（页面「别的图的会员」）：{ peer… }，按名字排
function LH.GuildElsewhere()
    local m = LY.Mine()
    local out = {}
    for _, p in ipairs(LY.Peers("guild")) do
        if p.m and p.m ~= m and not p.inst and not (LY.IsMe and LY.IsMe(p.full or p.name)) then out[#out + 1] = p end
    end
    return out
end

-- 同图的会员按层分组（页面「同图的会员在哪层」）：groups = { { z, no, name, mine, members = { peer… } } }，unknown = 没读到层的
function LH.GuildByLayer()
    local m, myZ = LY.Mine()
    local byZ, unknown = {}, {}
    if not m then return m, myZ, {}, unknown end
    -- 11-06 用户截图「第 1 层 2 人：我 枫叶 洞察」：公会消息会把自己的心跳也送回来 → 名单里跳过自己（比短名，去掉服务器后缀）
    for _, p in ipairs(LY.Peers("guild")) do
        if p.m == m and not p.inst and not (LY.IsMe and LY.IsMe(p.full or p.name)) then
            -- 11-09 用户截图「为啥我没切过去一起」：同队的人进队 20 秒后一定在同一层（暴雪机制），他心跳里的旧层不算 → 放进我这层，标「同队」
            -- 11-12：按进队时刻（groupAt）算 20 秒；rosterAt 在队里会被名单小变动反复刷新，原来队友一直显示在他旧的那层
            local party = myZ and LY.Confirmed() and LY.InMyGroup and LY.InMyGroup(p.full or p.name) and now() - (LY.groupAt or LY.rosterAt or 0) > 20
                and not (LH.pending and LH.pending.joinedAt)   -- 换层还没确认时我的层是旧的，别把队长挪进我的旧层
            p.party = party or nil
            if party then
                byZ[myZ] = byZ[myZ] or { z = myZ, members = {} }
                table.insert(byZ[myZ].members, p)
            elseif p.z and (p.c or 0) >= 2 then
                byZ[p.z] = byZ[p.z] or { z = p.z, members = {} }
                table.insert(byZ[p.z].members, p)
            else
                unknown[#unknown + 1] = p
            end
        end
    end
    if myZ and LY.Confirmed() then byZ[myZ] = byZ[myZ] or { z = myZ, members = {} }; byZ[myZ].mine = true end
    -- 11-06 用户「这里没有展示多个位面」：这张图我到过的层也列出来（没有会员也显示，标「你来过」）
    local known = LY.DB().order and LY.DB().order[tostring(m)] or {}
    for _, z in ipairs(known) do
        if not byZ[z] then byZ[z] = { z = z, members = {}, known = true } end
    end
    local groups = {}
    for z, g in pairs(byZ) do
        g.no = LY.LayerNo(m, z) or 99
        g.name = LY.LayerName(m, z)
        groups[#groups + 1] = g
    end
    table.sort(groups, function(a, b) if a.mine ~= b.mine then return a.mine and true or false end; return a.no < b.no end)
    return m, myZ, groups, unknown
end

-- 求助换层时，目标层见到 1 只怪就认（Layer.lua LY.Feed）
LY.ExpectZ = function(map)
    local p = LH.pending
    if p and p.m == map and p.z then return p.z end
    return nil
end

-- 自动接受：只认自己刚发起的那次请求的帮手（指定了人 / 认领了就只认他），30 秒内
--   指定层：那层上开了帮忙的；「随便换一层」：同图、和我原来不同层、开了帮忙的
LY.AddAcceptRule(function(s)
    local p = LH.pending
    if not p or now() - p.t > LH.ACCEPT_WIN then return nil end
    if p.helper then return sameName(p.helper, s) and L("换层帮手", "layer helper") or nil end
    local peer = LY.peers[s]
    if not (peer and peer.m == p.m and peer.hp and peer.z) then return nil end
    if p.z then return (peer.z == p.z) and L("换层帮手", "layer helper") or nil end
    -- 11-12：随便换一层时，刚拉过我的人 / 他们那层的人邀请也不自动接（他们是没认出 x / xz 的旧版本）
    if LH.RecentHelper(peer.name or s) or (p.xset and p.xset[peer.z]) then return nil end
    return (peer.z ~= p.from) and L("换层帮手", "layer helper") or nil
end)

-- 到了 / 收尾
-- 11-09 用户截图「进组了，说没邀请」「怎么判断是不是换成功了」「切换完也没有自动退队」：
--   原来只认「层码 == 帮手心跳里报的层」，可帮手报的层可能是旧的（心跳 60 秒一跳，还得他指过怪才更新）
--   → 用户从 0029 换到 0031、帮手报 0009，被当成没换成，也就没退队，30 秒后还报「没邀请你」。
--   现在：进了队（自动 / 手动接受都算）就不再报「没邀请」；进队后层码离开原来那层 = 到了（照旧发回执 + 按开关退队）；
--   进队 45 秒后亲眼读到的还是原来那层 = 没换成（按开关退队）；一直读不到怪 → 提示指一下 NPC / 怪确认，5 分钟内指到了照样出结果。
local function helperOf(p)
    local who = p.leader or p.helper
    return who and tostring(who):gsub("%-.*$", "") or L("公会会员", "A guildmate")
end
local function doLeave()
    local f = (C_PartyInfo and C_PartyInfo.LeaveParty) or LeaveParty
    if f then pcall(f) end
end
-- 11-13：autoLeave 三态 —— true 自动退；false 不退；nil（没问过）这次不退，换层成功（arrived）时弹「问一次」
function LH.AskLeave()
    local at = now()
    return LY.AskOnce("autoLeave", {
        text = L("已经换到新的一层。以后换过去后要自动退队吗？", "You're on the new layer. Leave the group automatically after future moves?"),
        yes = L("以后都自动退", "Always leave"), no = L("不自动退", "Don't leave"),
        onYes = function()
            -- 这次也退：还在队里、没过 60 秒才退（层会留下）
            if now() - at > LY.ASK_FRESH or not (IsInGroup and IsInGroup()) then return end
            doLeave()
            ns.Print(L("已退队（换过去的层会留下）", "Left the group (you stay on the new layer)") .. LY.OffHint())
        end,
    })
end
local function leaveIfAuto(arrived)
    if not (IsInGroup and IsInGroup()) then return false end
    local a = LY.DB().autoLeave
    if a == true then doLeave(); return true end
    if a == nil and arrived then LH.AskLeave() end
    return false
end
local function receipt(p, ok)
    local d = LY.Encode("D", { n = p.n, ok = ok and 1 or 0 })
    LY.Queue("PUB", d)
    if IsInGuild and IsInGuild() then LY.Queue("GUILD", d) end   -- 11-09 帮手关了公共频道也要收到「到了」
    local pe = p.helper and LY.peers[p.helper]
    if pe and pe.full then LY.Queue("WHISPER:" .. pe.full, d) end
end

LY.OnChange(function(_, new, map)
    local p = LH.pending
    if not (p and map == p.m and new) then return end
    local arrived
    if p.joinedAt then arrived = new ~= p.from
    else arrived = (p.z and new == p.z) or (not p.z and p.from and new ~= p.from) end
    if not arrived then return end
    LH.pending = nil
    receipt(p, true)
    local who = helperOf(p)
    local where = LY.LayerName(map, new)
    local inferred = LY.cur and LY.cur.map == map and LY.cur.z == new and LY.cur.inferred
    local note = (p.z and new ~= p.z) and L("（和他心跳里报的层不一样：他那边的层信息旧了，以你现在读到的为准）", " (differs from what he reported - his info was stale)") or ""
    if inferred then note = L("（附近没读到怪，按他报的层算；鼠标指一下 NPC 可以再核实）", " (no NPC read nearby - based on his reported layer)") end
    -- 11-12：记下谁拉过我、到了哪层（再点「我想换一层」直接说已经换过来了，也不再请他 / 他那层）
    local r = LH.RecentHelper(p.leader or p.helper)
    if not r and LH.MarkRecent then LH.MarkRecent(p); r = LH.RecentHelper(p.leader or p.helper) end   -- 进队事件先于读到新层
    if r then r.ok, r.z, r.m = true, new, map end
    LH.lastHop = { ok = true, who = who, m = map, z = new, from = p.from, t = now(), inferred = inferred and true or nil }
    local left = leaveIfAuto(true)
    ns.Print(string.format(L("%s 把你拉到了 %s%s", "%s pulled you to %s%s"), who, where,
        left and L("，已自动退队（右侧『位面』页签可关）", "; left the group automatically (turn off in the Layers tab)") or "") .. note)
    LH.SetResult(true, string.format(L("换层成功：%s 把你拉到了 %s", "Moved: %s pulled you to %s"), who, where) .. (left and L("，已自动退队", ", left group") or "")
        .. (inferred and L("（按他报的层算）", " (per his report)") or ""))
end)

-- 11-12 按队长推断的「到了」之后又亲眼读到怪：回到原来那层 = 其实没换成；到了别的层 = 以亲眼的为准
LY.OnChange(function(old, new, map)
    local h = LH.lastHop
    if not (h and h.ok and h.inferred and map == h.m and old == h.z and new) or now() - h.t > LH.RECENT_WIN then return end
    h.inferred = nil
    if new == h.from then
        h.ok = false
        local r = LH.RecentHelper(h.who)
        if r then r.ok = false end
        LH.SetResult(false, string.format(L("核实：读到附近的怪，你其实还在原来那层（%s），刚才没换成；换个人或别的层再试", "Checked: you are still on %s - the move didn't happen"), LY.LayerName(map, new)))
    else
        h.z = new
        LH.SetResult(true, string.format(L("核实：你现在在 %s（%s 心跳里的层旧了，以亲眼读到的为准）", "Checked: you are on %s (%s's info was stale)"), LY.LayerName(map, new), tostring(h.who)))
    end
end)

function LH.CheckJoined(p, final)
    if LH.pending ~= p or not p.joinedAt then return end
    local m, z = LY.Mine()
    local ls = LY.lastSeen
    local fresh = ls and ls.m == p.m and (ls.at or 0) > p.joinedAt + 3
    if fresh and z == p.from and now() - p.joinedAt >= LH.SAME_AFTER then
        LH.pending = nil
        receipt(p, false)
        local r = LH.RecentHelper(p.leader or p.helper)
        if r then r.ok = false end
        LH.lastHop = { ok = false, who = helperOf(p), m = p.m, z = z, from = p.from, t = now() }
        local left = leaveIfAuto(false)
        LH.SetResult(false, string.format(L("没换成：进了 %s 的队，但你还在原来那层（%s），他可能和你本来就同层%s", "No move: joined %s's group but still on %s%s"),
            helperOf(p), LY.LayerName(m, z), left and L("；已自动退队，换个人再试（右侧『位面』页签可关）", "; left the group (turn off in the Layers tab)") or L("；可以退队换个人再试", "")))
        return
    end
    if final then
        LH.pending = nil
        LH.SetResult(false, string.format(L("进了 %s 的队，但一直没认出新层：鼠标指一下附近任意 NPC / 怪就能看出换没换（没自动退队）", "Joined %s's group but couldn't read the layer - mouse over an NPC"), helperOf(p)))
    end
end

-- 进队后还没读到过怪（层没法判断）→ 提示去指一下；读到过了（不管换没换）就不唠叨
function LH.NudgeRead(p)
    if LH.pending ~= p or not p.joinedAt then return false end
    local ls = LY.lastSeen
    if ls and ls.m == p.m and (ls.at or 0) > p.joinedAt + 3 then return false end
    local text = string.format(L("已进 %s 的队：鼠标指一下附近任意 NPC / 怪，插件才能看出你换没换层", "Joined %s's group - mouse over any NPC so the addon can read your layer"), helperOf(p))
    LY.Flash(text, 1, 0.82, 0.2)
    ns.Print(text)
    if PlaySound then pcall(PlaySound, 8959) end
    p.nudged = (p.nudged or 0) + 1
    return true
end

-- 11-12 用户截图「已进 Closing Time 的队，正在确认换没换层」一直不出结果（人其实已经到了第 11 层）：
--   ① 进队后按 PROBE_AT 主动把目标 / 焦点 / 软目标 / 目标的目标 / 队友的目标 / 姓名板读一遍（LY.ReadAll），读到新层立刻算到了；
--   ② 进队 INFER_AFTER 秒一只怪都没读到 → 按队长心跳里报的层认我的层（进队就到队长那层，暴雪机制），标「按他报的层算」，
--      之后亲眼读到别的层照常改过来（读回原来那层 = 其实没换成，会提示）；
--   ③ 进队后亲眼读到的还是原来那层 → 不推断，交给 CheckJoined 45 秒判「没换成」
function LH.TryInfer(p, left)
    if LH.pending ~= p or not p.joinedAt then return false end
    if now() - p.joinedAt < LH.INFER_AFTER then return false end
    if left and (p.leftAt or now()) - p.joinedAt < 5 then return false end   -- 进队几秒就退了：层可能还没传过去
    local ls = LY.lastSeen
    if ls and ls.m == p.m and (ls.at or 0) > p.joinedAt + 3 then return false end   -- 进队后亲眼读到过：以亲眼的为准
    local who = p.leader or p.helper
    if not who then return false end
    if not left and not (LY.InMyGroup and LY.InMyGroup(who)) then return false end
    local pe = LH.PeerByName(who)
    if not pe or pe.inst or not pe.m or not pe.z or (pe.c or 0) < 2 then return false end
    local m = LY.cur.map or (LY.MyMap and LY.MyMap())
    if not m or m ~= p.m then return false end
    local lz = (pe.m == m) and pe.z or LY.XOnMap(pe.m, pe.z, m)
    if not lz or lz == p.from then return false end
    LY.Log("进队 " .. math.floor(now() - p.joinedAt) .. " 秒没读到怪：按队长 " .. tostring(who) .. " 报的层认 z=" .. tostring(lz))
    return LY.Adopt(m, lz, "leader")
end
function LH.Probe(p, left)
    if LH.pending ~= p or not p.joinedAt then return false end
    left = left or p.leftAt ~= nil
    pcall(LY.ReadAll)
    if LH.pending ~= p then return true end   -- 读到新层：OnChange 已收尾
    local ok, r = pcall(LH.TryInfer, p, left)
    return ok and r or false
end

-- 11-12「再点一次『我想换一层』还是选中同一个人」：已经被某人拉过 / 正在他的队里 / 已在他那层 → 先说清楚，不再发求助
--   返回 nil（可以发起）或 why, 给玩家看的整句
function LH.AlreadyMoved()
    local p = LH.pending
    if p and p.joinedAt and now() - p.joinedAt < LH.JOIN_WIN then
        LH.Probe(p)
        if LH.pending == p then
            return "confirming", string.format(L("已在 %s 的队里，正在确认换没换层（插件在读目标 / 姓名板 / 队友的目标），别重复求助；鼠标指一下附近任意 NPC / 怪能马上出结果",
                "Already in %s's group - confirming your layer; mouse over any NPC for an instant result"), helperOf(p))
        end
    end
    local m, z = LY.Mine()
    local h = LH.lastHop
    if h and h.ok and z and now() - h.t < LH.ALREADY_WIN and m == h.m and z == h.z then
        return "already", string.format(L("已经换过来了：%s 已把你拉到 %s（层码 %s），不用再换", "Already moved: %s pulled you to %s (%s)"), tostring(h.who), LY.LayerName(m, z), LY.Tail(z))
    end
    if z and IsInGroup and IsInGroup() then
        for name, r in pairs(LH.recent) do
            if now() - (r.t or 0) <= LH.RECENT_WIN and LY.InMyGroup and LY.InMyGroup(name) then
                local pe = LH.PeerByName(name)
                local lz = pe and pe.m and pe.z and ((pe.m == m) and pe.z or LY.XOnMap(pe.m, pe.z, m))
                if (lz and lz == z) or (r.ok and r.m == m and r.z == z) then
                    return "already", string.format(L("已经换过来了：你在 %s 的队里，和他同在 %s（层码 %s），不用再换", "Already moved: you're in %s's group on %s (%s)"),
                        (tostring(name):gsub("%-.*$", "")), LY.LayerName(m, z), LY.Tail(z))
                end
            end
        end
    end
    return nil
end

function LH.MarkRecent(p)
    local who = p.leader or p.helper
    if type(who) ~= "string" or ns.Secret(who) then return end
    local s = who:gsub("%-.*$", "")
    local r, key = LH.RecentHelper(s)
    local pe = LH.PeerByName(s)
    local z = pe and pe.m == p.m and pe.z or p.z
    if r then LH.recent[key] = nil end
    LH.recent[s] = { t = now(), m = p.m, z = z, from = p.from }
end

LY.OnEvent("GROUP_ROSTER_UPDATE", function()
    local p = LH.pending
    if not p then return end
    local inG = IsInGroup and IsInGroup()
    if p.joinedAt then
        -- 11-12：还没确认就自己退了队（层会留下）→ 马上读一遍 / 推断一次，别让页面一直挂着「正在确认」
        if not inG and not p.leftAt then p.leftAt = now(); LH.Probe(p, true); LY.dirty = true end
        return
    end
    if not inG then return end
    p.joinedAt = now()
    p.leader = leaderName() or p.helper
    LH.MarkRecent(p)
    LY.dirty = true
    if C_Timer and C_Timer.After then
        for _, d in ipairs(LH.PROBE_AT) do C_Timer.After(d, function() LH.Probe(p) end) end
        -- 11-09 用户「但是如果不提示用户不回去指吧？」：进队后 3 / 8 秒插件自己重读过了还没读到怪 → 10 秒、40 秒各主动提示一次（屏幕中间 + 聊天框）
        for _, d in ipairs({ 10, 40 }) do C_Timer.After(d, function() LH.NudgeRead(p) end) end
        for _, d in ipairs({ 20, LH.SAME_AFTER + 1, 90, 180 }) do C_Timer.After(d, function() LH.CheckJoined(p, false) end) end
        C_Timer.After(LH.JOIN_WIN, function() LH.CheckJoined(p, true) end)
    end
end)

-- ---------- 帮手侧 ----------
function LH.CanHelp(any)
    if not LY.DB().on or not LY.DB().helper or LY.InInstance() or LY.InCombat() then return false end
    if not any and not LY.Confirmed() then return false end   -- 别的图来的求助（any）不用先认出我的层
    local t, n = now(), 0
    for i = #LH.helped, 1, -1 do
        if t - LH.helped[i] > LH.HELP_WIN then table.remove(LH.helped, i) else n = n + 1 end
    end
    return n < LH.HELP_MAX
end

-- 会员求助能不能直接拉（不弹框）：开关开着、求助的是公会会员、我不在队伍里（在自己队里就弹框，别打扰队友）
--   11-13：autoHelp 三态 —— false 弹框；true 直接拉；nil（没问过）也走 AutoInvite，在那里先「问一次」
function LH.AutoHelpOK(s, via)
    if LY.DB().autoHelp == false then return false end
    if IsInGroup and IsInGroup() then return false end
    if via == "guild" then return true end
    local LG = ns.LayerGuild
    return (LG and LG.ranks and LG.ranks[s] ~= nil) and true or false
end
function LH.AutoInvite(n)
    local p = LH.popups[n]
    if not p or not LH.CanHelp(p.any) then return false end
    if LY.InCombat() or LY.InInstance() then return LH.ShowPopup(n) end
    if now() - (p.t or 0) > LY.ASK_FRESH then LH.popups[n] = nil; return false end   -- 问一次的框搁太久才点：求助早过期了
    if LY.DB().autoHelp ~= true then return LH.AskHelp(n) end
    local ok = LH.HelpInvite(n)   -- 无限客户端允许插件消息回调里邀请（Guild Master Forever 真机做法）
    if ok then ns.Print(string.format(L("公会会员 %s 想换到你这层，已自动邀请（右侧『位面』页签可关）", "Guildmate %s asked to join your layer - invited (turn off in the Layers tab)"), p.from)) end
    return ok
end
-- 11-13 玩家「或者初次的时候确认一次」：autoHelp 还是 nil → 先问「以后会员求助要直接拉吗？」
--   「以后都直接拉」= 存 true，这次也拉；「每次问我」= 存 false，这次照原样弹「邀请 / 忽略」框；× / 战斗中 / 框在问别的 = 这次照原样弹框
function LH.AskHelp(n)
    local p = LH.popups[n]
    if not p then return false end
    local function fallback()
        local q = LH.popups[n]
        if q and now() - (q.t or 0) <= LY.ASK_FRESH then LH.ShowPopup(n) end
    end
    if LH.muteUntil and now() < LH.muteUntil then return LH.ShowPopup(n) end   -- 「这次上线别弹」照旧管用
    local r = LY.AskOnce("autoHelp", {
        text = string.format(L("公会会员 %s 想换到你这层。以后会员求助要直接拉吗？", "Guildmate %s wants to switch to your layer. Invite guildmates automatically from now on?"), tostring(p.from)),
        yes = L("以后都直接拉", "Always invite"), no = L("每次问我", "Ask me each time"),
        onYes = function() LH.AutoInvite(n) end,
        onNo = fallback, onClose = fallback,
    })
    if r ~= "shown" then fallback() end
    return false
end

LY.handlers.R = function(t, s, via, sender)
    if via ~= "pub" and via ~= "guild" and via ~= "whisper" then return end
    if t.to and not (LY.IsMe and LY.IsMe(t.to)) and t.to ~= me() then return end
    local any = t.any == "1" and t.to ~= nil
    local m, z = LY.Mine()
    if any then
        if not t.n then return end
    elseif tonumber(t.m) ~= m or not t.n or not z then return
    elseif t.z then
        if tonumber(t.z) ~= z then return end
    elseif not t.f or tonumber(t.f) == z then
        return   -- 「随便换一层」：他本来就在我这层就不用我
    end
    -- 11-12「再点一次还是选中同一个人」：群发求助里带了「刚拉过他的人」（x）和「那几层」（xz）→ 是我 / 我在那层就让给别人
    if t.to == nil then
        local my = me()
        if type(t.x) == "string" then
            for nm in t.x:gmatch("[^,]+") do
                if (LY.IsMe and LY.IsMe(nm)) or (type(my) == "string" and not ns.Secret(my) and sameName(my, nm)) then
                    LY.Log("收到群发求助 from=" .. tostring(s) .. "：我刚拉过他，这次让给别人")
                    return
                end
            end
        end
        if type(t.xz) == "string" and z then
            for zz in t.xz:gmatch("%d+") do
                if tonumber(zz) == z then LY.Log("收到群发求助 from=" .. tostring(s) .. "：他刚从我这层的人那里换过，这次让给别的层"); return end
            end
        end
    end
    if LH.seenReq[t.n] then return end  -- 公会 + 频道各来一份：只处理一次
    LH.seenReq[t.n] = now()
    for k, at in pairs(LH.seenReq) do if now() - at > 600 then LH.seenReq[k] = nil end end
    -- 11-06「前 6 个人一直被骚扰」：同一个人 5 分钟内重复点名我 → 忽略
    if t.to ~= nil then
        if now() - (LH.askedBy[s] or -1e9) < LH.REASK then return end
        LH.askedBy[s] = now()
    end
    -- 11-10 用户截图公会频道「老大，我在FB队伍里」：「我想换一层」是群发的，在队伍里的会员也弹框 → 他邀请了只会把人拉进自己的副本队，
    --   帮不上还被打扰。群发的求助：我在队伍里就不理（点名请我的照旧弹框问，由我自己决定）
    if t.to == nil and IsInGroup and IsInGroup() then
        LY.Log("收到群发求助 from=" .. tostring(s) .. "：我在队伍里，不打扰")
        return
    end
    local can = LH.CanHelp(any)
    -- 点名请我的（t.to = 我）：我没开帮忙也弹框问一下（不自动拉）；位面识别关着 / 副本 / 战斗里照旧不理
    local asked = t.to ~= nil and LY.DB().on and not LY.InInstance() and not LY.InCombat()
    if not can and not asked then return end
    if not can then
        -- 没开帮忙、只弹框的：10 分钟最多弹 3 次，多的直接忽略
        local tn, nPop = now(), 0
        for i = #LH.popped, 1, -1 do if tn - LH.popped[i] > LH.POP_WIN then table.remove(LH.popped, i) else nPop = nPop + 1 end end
        if nPop >= LH.POP_MAX then return end
        LH.popped[#LH.popped + 1] = tn
    end
    LY.Log("收到求助 from=" .. tostring(s) .. " via=" .. tostring(via) .. (t.to and " 点名我" or "") .. (any and " 别图" or "") .. " 能帮=" .. tostring(can))
    local delay = math.random() * 1.5   -- 抢答：多个帮手随机错开，先邀请的人认领，其他人的自动取消
    LH.popups[t.n] = { from = s, full = sender, q = tonumber(t.q), t = now() + delay, any = any }
    local fn = (can and LH.AutoHelpOK(s, via)) and LH.AutoInvite or LH.ShowPopup
    if C_Timer and C_Timer.After then C_Timer.After(delay, function() fn(t.n) end) else fn(t.n) end
end
LY.handlers.C = function(t, s, via)
    if (via ~= "pub" and via ~= "guild" and via ~= "whisper") or not t.n then return end
    if LH.popups[t.n] and t.h ~= me() then LH.popups[t.n] = nil; LH.HidePopup(t.n) end
    if LH.pending and LH.pending.n == t.n and not LH.pending.helper then LH.pending.helper = s or t.h end   -- 11-09：s 带姓，t.h 可能只有名
end
LY.handlers.D = function(t)
    if t.n and LH.popups[t.n] then LH.popups[t.n] = nil; LH.HidePopup(t.n) end
    local who = t.n and LH.myInvites and LH.myInvites[t.n]
    if who then
        LH.myInvites[t.n] = nil
        LY.Flash(string.format(L("%s 已换到你这层", "%s is now on your layer"), who))
    end
end

-- 帮手点「邀请」（⛔ 只在按钮点击里调）
function LH.HelpInvite(n)
    local p = LH.popups[n]
    if not p then return false end
    LH.popups[n] = nil
    -- 11-10 用户「有人点了换位面……是她组我」：我自己正等着被拉（刚发了求换层）时绝不去邀请别人 —— 我一邀请就成了队长，换层方向反了
    if LH.pending and LH.pending.hop and now() - LH.pending.t < LH.JOIN_WIN and not LH.pending.joinedAt then
        LY.Log("跳过邀请 " .. tostring(p.from) .. "：我自己正在等别人拉")
        LH.HidePopup(n)
        return false
    end
    local ok = LY.Invite(p.full or p.from)
    if ok then
        LH.helped[#LH.helped + 1] = now()
        LH.helpLog[#LH.helpLog + 1] = now()   -- 没开帮忙、弹框里点了邀请的也算一次
        -- 11-06 帮手这边也提示：正在拉谁；对方到了（D 回执）再提示一次
        local who = tostring(p.from or "?"):gsub("%-.*$", "")
        LH.myInvites = LH.myInvites or {}
        LH.myInvites[n] = who
        LY.Flash(string.format(L("正在把 %s 拉到你这层…", "Pulling %s to your layer..."), who))
        local c = LY.Encode("C", { n = n, h = me() })
        if IsInGuild and IsInGuild() then LY.Queue("GUILD", c) end
        LY.Queue("PUB", c)
    end
    LH.HidePopup(n)
    return ok
end

local pop
function LH.ShowPopup(n)
    local p = LH.popups[n]
    -- 11-09 review：原来这里又查 CanHelp()，没开帮忙的被点名时（R 里特意放行的「弹框问一下」）永远弹不出来
    if not p or not LY.DB().on or LY.InInstance() or LY.InCombat() then return end
    if LH.muteUntil and now() < LH.muteUntil then LH.popups[n] = nil; return end
    if not pop then
        pop = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        pop:SetSize(460, 34); pop:SetPoint("TOP", UIParent, "TOP", 0, -120); pop:SetFrameStrata("HIGH")
        if pop.SetBackdrop then
            pop:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            pop:SetBackdropColor(0.04, 0.06, 0.1, 0.92); pop:SetBackdropBorderColor(0.4, 0.7, 1, 0.9)
        end
        pop.text = pop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pop.text:SetPoint("LEFT", 8, 0); pop.text:SetJustifyH("LEFT")
        -- 11-09 review：原来写「今天别提示」实际是永久关掉帮忙开关 → 改成这次上线不再弹（重登恢复），开关不动
        pop.mute = ns.Button(pop, L("这次上线别弹", "Mute session"), 96, 22, function() LH.muteUntil = now() + 86400; if pop.n then LH.popups[pop.n] = nil end; pop:Hide() end)
        pop.mute:SetPoint("RIGHT", -4, 0)
        pop.no = ns.Button(pop, L("忽略", "Ignore"), 50, 22, function() if pop.n then LH.popups[pop.n] = nil end; pop:Hide() end)
        pop.no:SetPoint("RIGHT", pop.mute, "LEFT", -4, 0)
        pop.yes = ns.Button(pop, L("邀请", "Invite"), 56, 22, function() if pop.n then LH.HelpInvite(pop.n) end end)
        pop.yes:SetPoint("RIGHT", pop.no, "LEFT", -4, 0)
    end
    pop.n = n
    local qn = p.q and C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(p.q)
    pop.text:SetText(ns.EnSafe(string.format(L("%s 想换到你这层%s", "%s wants to switch to your layer%s"), p.from,
        (type(qn) == "string" and not ns.Secret(qn)) and ("（在做【" .. qn .. "】）") or "")))
    pop:Show()
    local my = n
    if C_Timer and C_Timer.After then C_Timer.After(10, function() if pop.n == my then pop:Hide(); LH.popups[my] = nil end end) end
end
function LH.HidePopup(n)
    if pop and (not n or pop.n == n) then pop:Hide() end
end
LH._pop = function() return pop end
