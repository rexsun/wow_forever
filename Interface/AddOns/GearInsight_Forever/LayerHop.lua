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
LH.COOLDOWN = 15          -- 秒：发起换层请求的冷却（11-07 用户「3分钟是不是时间太长了？」：180 → 60；11-19 用户「这个锁定多久，时间简短」「剪短」：60 → 15；帮手那边有 10 分钟 5 次 / 弹框 3 次 / 同人 2 分钟的保护）
LH.AFTER_INST = 600       -- 秒：出副本后多久内不推荐
LH.FRESH = 300            -- 秒：报告多新算满分
LH.RATIO = 1.5
LH.HELP_MAX, LH.HELP_WIN = 5, 600
LH.ACCEPT_WIN = 30        -- 秒：发起后多久内接受帮手的邀请
LH.POP_DELAY = 3          -- 秒：要弹框问的帮手晚这么久再弹（11-14 自动帮忙的人 0~1.5 秒就认领，弹框的这边别闪一下就没）
LH.CLAIMED_LINGER = 4     -- 秒：框弹着时被别人认领，「XX 已经在拉他了」留多久再收
LH.POP_LIVE = 90          -- 秒：帮手这边「XX 想换到你这层」框留多久（11-14 用户「让我组的窗口太短暂了」：30 → 90；对方到了别处 / 被别人认领就提前收）
LH.CHAIN_MAX = 3          -- 11-10 用户「这里如果一个人没接，会自动换一个人？」「自动换人要做啊」：点名请人 30 秒没邀请 → 自动换下一位，一轮最多请几个人
-- 11-23 用户「连续切换不成功，看看是不是有BUG」，存档日志三次「成功」全是误判：
--   08:00 / 08:32 进队 11 秒 / 2 秒读到 1 只怪的层码既不是原层也不是队长报的层（隔壁图 / 刚刷的怪；进退队 90 秒放宽期 1 只就换）→ 判成功、4 秒后退队 = 服务器还没传就走了；
--   10:41 进队 16 秒没读到怪 → 按队长报的层「推断」成功、扣额度、给他 +1、180 秒不再请他（同图唯一帮手）→ 退队后读到 5201974（≠ 队长层），4 次群发全把他排除、白等 3 分钟。
--   现在：① 只有亲眼读到的层 = 队长那层才算换成（他心跳是我进队前读的 = 可能旧了 → 新层要 2 只不同的怪都给出才认）；不再按队长推断；
--   ② 进队后留在队里等，最多 CONFIRM 秒；读到原层要「进队 ≥ SAME_AFTER 秒且最近 SAME_FRESH 秒内还读到原层」才判没换成（传层要几秒到几十秒，早退 = 白拉）；
--   ③ 没换成 / 确认不了 / 换成后读回原层（回弹）：不算请过他（见 undo）
LH.SAME_AFTER = 60        -- 秒：进队这么久后还在原层才判「没换成」（45 → 60：传层常要 10~30 秒，战斗中更久）
LH.SAME_FRESH = 15        -- 秒：判「没换成」时最近一次亲眼读到原层要在这么久内（只读到过一次旧怪不算）
LH.CONFIRM = 90           -- 秒：进队后最多等这么久亲眼认层（原来 15 秒就推断；90 = 60 秒判没换成 + 30 秒给读不到怪的人去指一下）
LH.JOIN_WIN = 300         -- 秒：进队后这么久内亲眼读到队长那层都算到了（确认不了之后才指到怪也照样出结果）
LH.PROBE_AT = { 2, 4, 6, 9, 12, 16, 20, 25, 30, 40, 50, 61, 75 }   -- 进队后这些秒主动把目标 / 焦点 / 软目标 / 队友目标 / 姓名板读一遍，读完顺带判一次
LH.RECENT_WIN = 180       -- 秒：拉过我的人（和他那层）这么久内「我想换一层」不再找（11-19 用户「剪短」：600 → 180）；没换成的那次不算（undo）
LH.VERIFY_WIN = 180       -- 秒：换成之后这么久内亲眼读回原来那层 = 回弹（600 → 180：回弹都在退队后一两分钟内，太长会把之后正常的换层当回弹）
-- 11-19 用户截图：小辛恶魔刚把我拉到第 10 层（0029），列表里他却在第 8 层（0020）、我那层「没有别的公会会员」——
--   拉人那一刻他一定在我现在这层（进队就到队长那层），他心跳里的层码是旧的。这么久内：他还没「换层以后重新读到的」心跳 →
--   放进我这层标「待确认」（他收到回执 D 会马上重读、补发心跳）；他重新读到的还是别的层码 → 留在他报的层、标「层码对不上」
LH.HOP_TRUST = 300         -- LH.GuildByLayer / GuildElsewhere（只有位面页用）11-19 搬到 _LayerUI 的 LayerPub.lua，省主插件登录内存
LH.recent = {}            -- [帮手名] = { t, m, z, from, ok }
LH.lastHop = nil          -- { ok, who, leader, m, z, from, fm 起始图, t }
LH.lastReq = -1e9
LH.pending = nil          -- { m, z, n, t, helper }
LH.helped = {}            -- 帮过的时间
LH.popups = {}            -- [nonce] = { from, z, q, t }
LH.askedAt = {}           -- 11-06 用户「前 6 个人一直被骚扰，可以平均一下吗」：[名字] = 我上次请他的时间（本机）
LH.popped = {}            -- 我没开帮忙、被点名弹框的时间（10 分钟最多 3 次）
LH.askedBy = {}           -- [请求人] = 他上次点名我的时间（REASK 内重复点名我 → 忽略）
LH.POP_MAX, LH.POP_WIN, LH.REASK = 3, 600, 7200   -- 11-23 用户「原则上一个人，在2小时内，只请求一个人邀请一次」：120 秒 → 2 小时（跨 /reload 记忆在 _LayerUI LayerCredit.lua）
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
    -- 11-22 点过「不再弹」/「这次上线别弹」（又没开会员求助自动拉）的人求他也不会弹框 → 不报可帮忙，别被优先点名白等 30 秒
    local d = LY.DB()
    if d.helper and (LH.PopOn() and not LH.muteUntil or d.autoHelp == true or LH.autoAll) then t.hp = 1 end
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
-- LH.Score / LH.Current（只有位面页「建议换到」用）11-19 搬到 _LayerUI 的 LayerPub.lua，省主插件登录内存

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
-- 11-19 用户「锁定期间要让人看得到还剩多久」：这个人还要几秒才能再请（0 = 现在就能请）：
--   我刚点名请过他（他那边 REASK 内会忽略）/ 他刚拉过我（RECENT_WIN 内不再找）。按钮上的倒计时在 _LayerUI 的 LayerPub.lua
function LH.AskLeft(name)
    local r, t = LH.RecentHelper(name), now()
    return math.max(0, math.ceil(math.max(LH.REASK - (t - (LH.askedAt[name] or -1e9)), r and (LH.RECENT_WIN - (t - (r.t or 0))) or 0)))
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

-- 11-22 一轮求助的上下文 LH.ctx = { t, m, from 起始层, a = {[点名 / 认领的帮手] = 请他的时间}, n = {[请求号] = 时间}, joinedAt, leader, res 结果 }
--   不随 30 秒 pending 清掉：点名 / 认领过的帮手 POP_LIVE 内的邀请照样自动接；JOIN_WIN 内进过帮手的队、层真变了也算换成（照样自动退队）
--   发起新求助（Request / AskChain）= 换一个新的，旧的放宽窗口作废
local function newCtx() local m, z = LY.Mine(); LH.ctx = { t = now(), m = m, from = z, a = {}, n = {} } end
-- 结果只记一次：t 没人邀请 < b 回弹 < f 没换成 < u 确认不了 < o 换成；后来出了更好的结果 → 改记（旧的减回去）
local function res(k, c)
    c = c or LH.ctx
    if not c or c.res and ("tbfuo"):find(c.res) >= ("tbfuo"):find(k) then return false end
    if c.res then LY.Stat(c.res, -1) end
    c.res = k; LY.Stat(k)
    return true
end
-- 11-06 兼容 0.7.0 的帮手：点名只写「名」（0.7.0 拿 UnitName 比，无限 UnitName 只给名）
local function toName(n) return (tostring(n or ""):gsub("%-.*$", ""):match("^(%S+)")) or n end

-- 11-08 用户「点了以后毫无反馈？」「我到底切换了没」：30 秒没人邀请 → 请求作废时屏幕中间提示 + 页面状态行写结果（以前静默作废）
LH.last = nil             -- { ok = bool, text, t }（显示用的 LH.LastText 11-19 搬到 _LayerUI 的 LayerPub.lua）
function LH.SetResult(ok, text, m, z, tpl)
    LH.last = { ok = ok, text = text, t = now(), m = m, z = z, tpl = tpl }
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
        if who and p.chain and LH.ChainNext and LH.ChainNext(p.chain, who) then return end
        -- 11-22 群发 30 秒没人认领 → 自动挨个点名（密语，比公共频道稳）；群发那轮的邀请 90 秒内照样接（ctx.bp）
        if p == (LH.ctx and LH.ctx.bp) and not who and LH.AutoChain and LH.AutoChain(p) then return end
        -- 11-22 超时文字（各种原因）搬到 _LayerUI 的 LayerPub.lua LH.MissText，省主插件登录内存
        local text = LH.MissText and LH.MissText(p, who) or L("没换成：没有人邀请你", "No move: nobody invited you")
        res("t")
        LH.SetResult(false, text)
    end)
end
LH.Watch = watch

-- 返回 false, why[, 给玩家看的整句]
function LH.Request(z)
    local st, txt = LH.AlreadyMoved(z, z ~= nil)
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
    LH.pending = { m = m, z = z, n = n, t = now(), from = myZ, hop = true, free = LH.FreeHelpers and LH.FreeHelpers(z), xset = xset, g = LH.gOnly }
    newCtx(); LY.Stat("r"); LH.ctx.bp = LH.pending
    watch(LH.pending)
    LH.Track(n)
    local msg = LY.Encode("R", { m = m, z = z, f = myZ, q = firstQuest(), n = n, x = (#xn > 0) and table.concat(xn, ",") or nil, xz = xz })
    LY.Log("我求换层 z=" .. tostring(z or "任意") .. " from=" .. tostring(myZ))
    if IsInGuild and IsInGuild() then LY.Queue("GUILD", msg) end
    if not LH.gOnly then LY.Queue("PUB", msg) end   -- 11-21 gOnly = 只找公会（公会外额度用完，_LayerUI 的 LayerCredit.lua 设）
    return true
end
-- 11-22 内存：RequestFrom / RequestAny 合成一个（any = 别的图的会员：只发给他，他那边不比地图 / 层）
local function reqTo(name, any)
    local why = LH.Blocked()
    if why then return false, why end
    local peer = name and LY.peers[name]
    local m, myZ = LY.Mine()
    if not peer or not any and (peer.m ~= m or not peer.z or peer.z == myZ) then return false, "same" end
    -- 11-06 用户「没开帮忙的话，可以有个按钮请求」：没开帮忙也能请，他那边弹框问，点了才拉（不自动）
    local n = nonce()
    LH.lastReq = now()
    LH.pending = { m = m, z = not any and peer.z or nil, n = n, t = now(), from = myZ, helper = name, hop = true, any = any }
    watch(LH.pending)
    LH.askedAt[name] = now()
    LH.Track(n, peer.full or name)
    LY.Queue("WHISPER:" .. (peer.full or name), LY.Encode("R", { any = any and 1, m = peer.m, z = peer.z, f = myZ, q = not any and firstQuest() or nil, n = n, to = toName(name) }))
    LY.Log((any and "我请别图的 " or "我请 ") .. tostring(name) .. " 拉我 z=" .. tostring(peer.z))
    return true
end
function LH.RequestFrom(name) return reqTo(name) end
-- 11-06 用户「位面不分地图吧」「为啥他们我就无法让他们邀请我呢」：位面是整块大陆共用的，层码却按地图编号（同一层在不同地图的
--   GUID 段不一样）→ 别的图的会员看不出和我是不是同层，但他拉我进队照样把我带到他那层。
--   请别的图的会员拉我：只发给他（密语 R，any=1），他那边不比地图 / 层；我进队后看层变没变：变了 = 到了（照旧自动退队），
--   25 秒没变 = 他本来就和我同层 → 提示一下并按开关退队
function LH.RequestAny(name) return reqTo(name, true) end

-- 11-10 用户「这里如果一个人没接，会自动换一个人？」「自动换人要做啊」：
--   页面「过去」/「请他们拉我」走这里：先请 list 里最近帮得最少的一位（RequestFrom = 同图点名层；far = 别的图，RequestAny）；
--   30 秒没邀请（watch 超时）→ ChainNext 自动请下一位：本轮问过的跳过、自动续请不受冷却限制，一轮最多 CHAIN_MAX 人；
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
            ch.asked = ch.asked or {}; ch.asked[who] = true   -- 11-14：真问过的（tried 里还混着「刚拉过我、直接跳过」的）
            if LH.pending then LH.pending.chain = ch end
            return who
        end
        if why ~= "same" then return nil, why end
    end
    return nil
end
LH._chainAsk = chainAsk   -- 11-22 _LayerUI 的 LH.AutoChain 用
function LH.AskChain(list, far, z)
    local st, txt = LH.AlreadyMoved(z, true)
    if st then return nil, st, txt end
    local why = LH.Blocked()
    if why then return nil, why end
    local ch = { list = list or {}, far = far or {}, tried = {}, n = 0 }
    -- 11-12：刚拉过我的人不再请（本轮当成问过）
    local skipped
    for _, lst in ipairs({ ch.list, ch.far }) do
        for _, pe in ipairs(lst) do
            -- 11-19：我 REASK 内刚点名过的人他那边会忽略 → 也跳过（原来白等 30 秒）
            if pe.name and LH.AskLeft(pe.name) > 0 then ch.tried[pe.name] = true; skipped = skipped or pe.name end
        end
    end
    local old = LH.ctx
    newCtx()
    local who, why2 = chainAsk(ch)
    if not who then
        LH.ctx = old
        if skipped and not why2 then
            return nil, "dup", string.format(L("只剩刚请过 / 刚拉过你的 %s，%d 分钟后可再请；或换别的层", "Only %s (just asked) - again in %dm, or try another layer"),
                (tostring(skipped):gsub("%-.*$", "")), math.ceil(LH.AskLeft(skipped) / 60))
        end
        return nil, why2 or "nobody"
    end
    LY.Stat("r")
    return who
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
    local p, c = LH.pending, LH.ctx
    -- 11-14：帮手框留到 90 秒 → 本轮自动换人前面问过、当时没点的，晚点了邀请也接（他点的就是我这一轮的求助）
    -- 11-22：这一轮点名过 / 认领过的帮手，各自 POP_LIVE（90 秒）内都接（不管 pending 30 秒清没清）；群发没点名的照旧 30 秒
    if c and c.res ~= "o" then
        for nm, at in pairs(c.a) do
            if now() - at <= LH.POP_LIVE and sameName(nm, s) then return L("换层帮手", "layer helper") end
        end
    end
    -- 11-22 用户「老是过30秒没人组」：群发求助原来要他在名单里 + 开了帮忙 + 层码读到了 + 30 秒内才接，邀请常比他的心跳 / 认领先到 → 没接。
    --   现在群发那轮 POP_LIVE（90 秒，和帮手的框一样长）内：插件用户（名单里有他）邀请就接，只有「明确和我同层 / 不是我点的那层 / 刚拉过我」才不接
    local bp = c and c.res ~= "o" and c.bp
    if bp and now() - bp.t <= LH.POP_LIVE then
        if bp.helper then return sameName(bp.helper, s) and L("换层帮手", "layer helper") or nil end   -- 已有人认领：只认他（11-19 别被第二个人拉走）
        local peer = LH.PeerByName(s)
        if not peer then LY.noWhy = "不在插件名单"; return nil end
        -- 11-12：随便换一层时，刚拉过我的人 / 他们那层的人邀请也不自动接（他们是没认出 x / xz 的旧版本）
        if LH.RecentHelper(peer.name or s) or (bp.xset and peer.z and bp.xset[peer.z]) then LY.noWhy = "刚拉过我"; return nil end
        if peer.z and peer.m == bp.m and (bp.z and peer.z ~= bp.z or not bp.z and peer.z == bp.from) then LY.noWhy = "和我同层"; return nil end
        return L("换层帮手", "layer helper")
    end
    if not p or now() - p.t > LH.ACCEPT_WIN then LY.noWhy = LY.noWhy or "不在求助窗口"; return nil end
    if p.helper then return sameName(p.helper, s) and L("换层帮手", "layer helper") or nil end
end)
-- 11-22 邀请先到、他的认领 C / 心跳后到（Layer.lua 记 LY.missInv）：暴雪邀请框还挂着就再判一次，这回认出来就接
function LY.Recheck(s)
    local v = LY.missInv
    if not (v and sameName(s, v.who)) then return end
    if now() - v.t > 60 or IsInGroup and IsInGroup() or StaticPopup_Visible and not StaticPopup_Visible("PARTY_INVITE") then LY.missInv = nil; return end
    if LY.AcceptReason(v.who) then LY.OnInvite(v.who) end
end

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
-- 11-19 d 秒后再退（还在队里才退）：见 LH.LEAVE_DELAY
local function doLeave(d)
    local f = (C_PartyInfo and C_PartyInfo.LeaveParty) or LeaveParty
    if not f then return end
    if d and C_Timer and C_Timer.After then C_Timer.After(d, function() if IsInGroup and IsInGroup() then doLeave() end end); return end
    local ok, e = pcall(f)
    if not ok then LY.Log("自动退队失败：" .. tostring(e)) end   -- 11-22 失败记进 /gi layer log
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
    if a == true then doLeave(LH.LEAVE_DELAY); return true end
    if a == nil and arrived then LH.AskLeave() end
    return false
end
-- 11-23 用户「同意」：帮手拉了却没换成（f 没换成 / u 确认不了 / b 回弹）不算「2 小时内请过这个人」——
--   不计 REASK（我这边 askedAt 删掉；回执 D ok=0 带 h=他，他那边删 askedBy[我]）、不计 RECENT_WIN、不扣额度（_LayerUI LH.OnUndo 退回）、不给帮手 +1（只有 ok=1 才 +1）
local function undo(c, bounce)
    local who = c.leader or c.helper
    if type(who) ~= "string" then return end
    local _, k = LH.RecentHelper(who)
    if k then LH.recent[k] = nil end
    for n in pairs(LH.askedAt) do if sameName(n, who) then LH.askedAt[n] = nil end end
    if bounce then local pe = LH.PeerByName(who); LY.Queue("WHISPER:" .. (pe and pe.full or who), LY.Encode("D", { n = "0", ok = 0, h = who }), true) end
    if LH.OnUndo then pcall(LH.OnUndo, who, bounce) end
end
-- 11-22 进队 CONFIRM 秒还没亲眼认出层：记 u（不算换成、不扣、不算请过）；开着自动退队、还在帮手队里 → 退
local function giveUp(c)
    if not res("u", c) then return end
    undo(c)
    LH.Finish(false, c.leader)
    local left = LY.DB().autoLeave == true and LY.InMyGroup(c.leader)
    if left then doLeave() end
    LH.SetResult(false, string.format(L("进了 %s 的队，%d 秒没亲眼读到新层：不算换成（不扣额度，可马上再请他）%s", "Joined %s's group but no layer read in %ds - not counted%s"), helperOf(c), LH.CONFIRM,
        left and L("；已自动退队", "; left group") or L("；指一下附近 NPC / 怪能看出换没换", "")))
end
-- 11-09 帮手关了公共频道也要收到「到了」→ 频道 + 公会 + 密语帮手；11-19 改成整轮一起发（LH.Finish）
local function receipt(p, ok)
    local r = LH.round
    if not (r and not r.done and r.ns[#r.ns] == p.n) then LH.round = nil; LH.Track(p.n, p.helper and LY.peers[p.helper] and LY.peers[p.helper].full) end
    -- h 用「名 姓」全名：队长名在《无限》可能只有「名」，同名不同姓的帮手会误以为是自己拉的 → 优先用认领 / 点名时记下的全名
    local w = p.leader or p.helper
    if p.helper and sameName(p.helper, w) then w = p.helper else local pe = LH.PeerByName(w); w = pe and pe.name or w end
    LH.Finish(ok, w)
end

-- 11-19 用户「换完位面了，还有人邀请我」。日志：07:34:41 求换层 → :43 文文大怪兽邀请、自动接、到了、自动退队 → :44 Awesome Noob 又邀请（没接）。
--   开了自动帮忙的人随机晚 0~1.5 秒邀请，先邀请的发 C 认领 —— C 还在路上时第二个人已经邀请了；我又马上退了队，他的邀请就弹到我这。
--   还有：点名链里先请过的人 / 30 秒后又点了一次，回执 D 原来只带最后一次的请求号、只密语最后一个人（旧版帮手只认请求号，框不收）。
--   ① 一轮求助（群发 + 点名过的每个人）记下全部请求号，换好了：频道 + 公会发一条（n = 最后一次，ns = 其余的，h = 谁拉的），
--      旧版只认 n → 其余群发的请求号各补一条，点名过的人各密语一条他自己那个请求号
--   ② 自动退队晚 LH.LEAVE_DELAY 秒：抢答慢一步的邀请这时会被服务器直接挡掉（对方看到「已在队伍中」），不弹到我这
--   ③ 换好 LH.DONE_WIN 秒内，这轮的帮手（心跳里开了帮忙的插件用户 / 点名过的人，拉我的那位除外）再邀请：不自动接（会长官员那条也压住），
--      聊天框说一句「已经换好了，可以拒绝」。⛔ 不替玩家点拒绝（DeclineGroup 无限客户端没实测过），也不撤回 / 不踢（UninviteUnit 对已进队的人就是踢人）
LH.DONE_WIN, LH.LEAVE_DELAY = 120, 4
function LH.Track(n, to)
    local r = LH.round
    if not r or r.done or now() - r.t > LH.POP_LIVE + 10 then r = { ns = {}, to = {}, bc = {} }; LH.round = r end
    local m, z = LY.Mine()
    r.t, r.m, r.from = now(), r.m or m, r.from or z
    r.ns[#r.ns + 1] = n
    if to then r.to[to] = n else r.bc[#r.bc + 1] = n end
    local c = LH.ctx
    if c then c.n[n] = now(); if to then c.a[to] = now() end end
end
function LH.Finish(ok, who)
    local r = LH.round
    if not r or r.done then return end
    r.done, r.ok, r.who = now(), ok, who
    local last, guild = r.ns[#r.ns], IsInGuild and IsInGuild()
    local function send(dist, n, rest) LY.Queue(dist, LY.Encode("D", { n = n, ok = ok and 1 or 0, h = who, ns = rest }), true) end
    local function both(n, rest) send("PUB", n, rest); if guild then send("GUILD", n, rest) end end
    for _, n in ipairs(r.bc) do if n ~= last then both(n) end end
    for to, n in pairs(r.to) do send("WHISPER:" .. to, n) end
    both(last, #r.ns > 1 and table.concat(r.ns, ",", 1, #r.ns - 1) or nil)
end
table.insert(LY.acceptRules, 1, function(s)
    local r = LH.round
    if LH.pending or not (r and r.ok and now() - r.done <= LH.DONE_WIN) or sameName(r.who, s) then return nil end
    local pe, hit = LH.PeerByName(s), nil
    hit = pe and pe.hp
    for to in pairs(r.to) do hit = hit or sameName(to, s) end
    if not hit then return nil end
    r.said = r.said or {}
    if not r.said[s] then
        r.said[s] = true
        ns.Print(string.format(L("%s 邀请你组队：你已经换好层了（%s 拉的），这个邀请可以拒绝", "%s invited you: you've already moved layer (via %s) - you can decline"), s, tostring(r.who or "?"):gsub("%-.*$", "")))
    end
    return true, "no"
end)

-- 11-23 换没换成只看亲眼读到的层（见 SAME_AFTER 上面的注释）：c = pending 或 ctx（m / from / leader / joinedAt）
--   新层 = 队长那层 → 换成；队长心跳是我进队以后读的、还是别的层 → 还没到；他的心跳是进队以前的（可能旧了）→ 新层要 2 只不同的怪都给出才认
local function hit(c, map, new)
    local f0 = LY.XOnMap(c.m, c.from, map)
    if not (f0 and new) or new == f0 then return false end
    local pe = LH.PeerByName(c.leader or c.helper)
    local lz = pe and LY.XOnMap(pe.m, pe.z, map)
    if lz == new then return true end
    if lz and (pe.zAt or 0) > (c.joinedAt or 1e12) then return false end
    local cu, n = LY.cur, 0
    if cu.map == map and cu.z == new then for _ in pairs(cu.npcs or {}) do n = n + 1 end end
    return n >= 2
end
LH._hit = hit
local function arrive(p, map, new)
    LH.pending = nil
    res("o")
    receipt(p, true)
    local who = helperOf(p)
    local where = LY.LayerName(map, new)
    -- 11-12：记下谁拉过我、到了哪层（再点「我想换一层」直接说已经换过来了，也不再请他 / 他那层）
    local r = LH.RecentHelper(p.leader or p.helper)
    if not r then LH.MarkRecent(p); r = LH.RecentHelper(p.leader or p.helper) end   -- 进队事件先于读到新层
    if r then r.ok, r.z, r.m = true, new, map end
    LH.lastHop = { ok = true, who = who, leader = p.leader or p.helper, m = map, z = new, from = p.from, fm = p.m, t = now() }
    local left = leaveIfAuto(true)
    local tail = left and L("，已自动退队", ", left group") or ""
    ns.Print(string.format(L("%s 把你拉到了 %s", "%s pulled you to %s"), who, where) .. (left and (tail .. LY.OffHint()) or ""))
    local tpl = string.format(L("换层成功：%s 把你拉到了 ", "Moved: %s pulled you to "), tostring(who):gsub("%%", "%%%%")) .. "%s" .. tail
    LH.SetResult(true, string.format(L("换层成功：%s 把你拉到了 %s", "Moved: %s pulled you to %s"), who, where) .. tail, map, new, tpl)
    -- 11-19：两边层码记进 /gi layer log，下次对不上有据可查
    local pe = LH.PeerByName(p.leader or p.helper)
    LY.Log("核对：拉我的 " .. tostring(pe and pe.name or who) .. " 报 z=" .. tostring(pe and pe.z) .. " / 我读到 z=" .. tostring(new))
end

LY.OnChange(function(_, new, map)
    local p = LH.pending
    if not (p and new) then return end
    -- 11-23 没进队之前只认「指定的那层」（随便换一层时层码变了多半是读到隔壁图的怪，不是被拉过去）
    if p.joinedAt and hit(p, map, new) or not p.joinedAt and map == p.m and p.z and new == p.z then arrive(p, map, new) end
end)

-- 11-22 迟到的邀请（30 秒后手动接的）/ 确认不了之后才指到怪：这一轮 JOIN_WIN 内进过帮手的队、亲眼读到队长那层 → 也算换成，照样按开关退队
LY.OnChange(function(_, new, map)
    local c, r = LH.ctx, LH.round
    if LH.pending then return end
    -- 11-19 求助 30 秒过了（pending 已清）才手动接了某个帮手的邀请、换了层 → 也算这轮换好了，发回执让别人收框（11-23 同样要亲眼认：hit）
    if r and not r.done and now() - r.t < LH.POP_LIVE + 10 and IsInGroup and IsInGroup() and hit({ m = r.m, from = r.from, leader = leaderName() }, map, new) then LH.Finish(true, leaderName()) end
    if not (c and c.joinedAt and now() - c.joinedAt < LH.JOIN_WIN) or not hit(c, map, new) or not res("o") then return end
    LH.Finish(true, c.leader)
    LH.lastHop = { ok = true, who = helperOf(c), leader = c.leader, m = map, z = new, from = c.from, fm = c.m, t = now() }
    local left = leaveIfAuto(true)
    LH.SetResult(true, string.format(L("换层成功：%s 把你拉到了 %s", "Moved: %s pulled you to %s"), helperOf(c), LY.LayerName(map, new))
        .. (left and L("，已自动退队", ", left group") or ""))
end)

-- 11-23 换成之后 VERIFY_WIN 内亲眼读回原来那层（回弹 / 服务器其实没传）→ 改判没换成：o 减回、记 b；退额度、解除对他的封锁（undo），可马上再请
LY.OnChange(function(_, new, map)
    local h = LH.lastHop
    if not (h and h.ok and new) or LH.pending or now() - h.t > LH.VERIFY_WIN or new ~= LY.XOnMap(h.fm, h.from, map) then return end
    h.ok = false
    LY.Stat("o", -1); LY.Stat("b")
    local c = LH.ctx
    if c and c.res == "o" then c.res = "b" end
    undo(h, true)
    LH.SetResult(false, string.format(L("没换成：读到附近的怪，你又回到了原来那层（%s）。不算请过 %s（不扣额度），可马上再请", "Bounced back to %s - not counted, ask %s again"), LY.LayerName(map, new), tostring(h.who)))
end)

function LH.CheckJoined(p, final)
    if LH.pending ~= p or not p.joinedAt then return end
    local m, z = LY.Mine()
    if hit(p, m, z) then return arrive(p, m, z) end
    local ls = LY.lastSeen
    local f0 = LY.XOnMap(p.m, p.from, m)   -- 11-22 换了图也换算起始层再比
    if f0 and z == f0 and ls and ls.m == m and ls.z == f0 and now() - (ls.at or 0) <= LH.SAME_FRESH and now() - p.joinedAt >= LH.SAME_AFTER then
        LH.pending = nil
        res("f")
        receipt(p, false)
        undo(p)
        LH.lastHop = nil
        local left = leaveIfAuto(false)
        LH.SetResult(false, string.format(L("没换成：在 %s 的队里等了 %d 秒，你还在原来那层（%s）——他可能和你同层，或服务器没传你。不算请过他（不扣额度）%s", "No move: in %s's group %ds, still on %s - not counted%s"),
            helperOf(p), math.floor(now() - p.joinedAt), LY.LayerName(m, z), left and L("，已自动退队，可马上再试", ", left group") or L("，可退队再试", "")))
        return
    end
    if final then
        LH.pending = nil
        giveUp(LH.ctx or p)
    end
end

-- 进队后还没读到过怪（层没法判断）→ 提示站着别动、去指一下；读到过了（不管换没换）就不唠叨
function LH.NudgeRead(p)
    if LH.pending ~= p or not p.joinedAt then return false end
    local ls = LY.lastSeen
    if ls and ls.m == p.m and (ls.at or 0) > p.joinedAt + 3 then return false end
    local text = string.format(L("已进 %s 的队：先别退队，鼠标指一下附近任意 NPC / 怪，插件亲眼读到新层才算换成", "Joined %s's group - stay, and mouse over any NPC so the addon can read your layer"), helperOf(p))
    LY.Flash(text, 1, 0.82, 0.2)
    ns.Print(text)
    if PlaySound then pcall(PlaySound, 8959) end
    p.nudged = (p.nudged or 0) + 1
    return true
end

-- 11-12 进队后按 PROBE_AT 主动把目标 / 焦点 / 软目标 / 目标的目标 / 队友的目标 / 姓名板读一遍（LY.ReadAll），读完判一次（CheckJoined）
--   11-23 删掉「15 秒没读到怪就按队长报的层算到了」（10:41 那次误判的来源）
function LH.Probe(p)
    if LH.pending ~= p or not p.joinedAt then return false end
    pcall(LY.ReadAll)
    if LH.pending == p then pcall(LH.CheckJoined, p) end
    return LH.pending ~= p
end
-- 第 2 只新层的怪是鼠标 / 姓名板读到的（同层不触发 OnChange）→ 每秒判一次，别等下一轮 PROBE_AT
LY.OnTick(function() local p = LH.pending; if p and p.joinedAt then LH.CheckJoined(p) end end)

-- 11-12「再点一次『我想换一层』还是选中同一个人」：已经被某人拉过 / 正在他的队里 / 已在他那层 → 先说清楚，不再发求助
--   返回 nil（可以发起）或 why, 给玩家看的整句
-- 11-20 用户截图「还想换为啥不行」：被拉到 0011 后点别的层「过去」，一直红字「已经换过来了…第 2 层（层码 0011）」——
--   1.4.4 公会那块同样（「叁 劈 已把你拉到 第 1 层 / 第 2 层（层码 0012）」）。原来不看点的是哪层，只要 120 秒内换成功过、我还在那层就拦。
--   现在换层成功的状态不拦任何后续请求：pick（点了某层 / 某些人）且 tz = 我自己这层 → 「你已经在这层」；其余照常发求助
--   （「我想换一层」会带上刚拉过我的人和他那层做排除 x / xz，不会又请到他）。还在他队里 → 下面那条 / Blocked 的「先退队」
function LH.AlreadyMoved(tz, pick)
    local p = LH.pending
    if p and p.joinedAt and now() - p.joinedAt < LH.JOIN_WIN then
        LH.Probe(p)
        if LH.pending == p then
            return "confirming", string.format(L("已在 %s 的队里，正在确认换没换层（插件在读目标 / 姓名板 / 队友的目标），别重复求助；鼠标指一下附近任意 NPC / 怪能马上出结果",
                "Already in %s's group - confirming your layer; mouse over any NPC for an instant result"), helperOf(p))
        end
    end
    local m, z = LY.Mine()
    local where = z and string.format(L("你现在在 %s（层码 %s）", "you're on %s (%s)"), LY.LayerName(m, z), LY.Tail(z))
    if pick then
        if tz and tz == z then return "here", L("你已经在这层：", "Already on this layer: ") .. where end
        return nil
    end
    if z and IsInGroup and IsInGroup() then
        for name, r in pairs(LH.recent) do
            if now() - (r.t or 0) <= LH.RECENT_WIN and LY.InMyGroup and LY.InMyGroup(name) then
                local pe = LH.PeerByName(name)
                local lz = pe and pe.m and pe.z and ((pe.m == m) and pe.z or LY.XOnMap(pe.m, pe.z, m))
                -- 11-20：以我自己读到的层码为准 —— 我的层离开了他拉我时的那层，才算换过来（他心跳里的层码可能是旧的）
                if (lz and lz == z and z ~= r.from) or (r.ok and r.m == m and r.z == z) then
                    return "already", string.format(L("已经换过来了：你在 %s 的队里，%s", "Already moved: in %s's group, %s"),
                        (tostring(name):gsub("%-.*$", "")), where)
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
    local p, c = LH.pending, LH.ctx
    local inG = IsInGroup and IsInGroup()
    -- 11-22 进了帮手的队（记 i）：pending 已清（30 秒后手动接的 / 点名帮手 90 秒内的邀请）也记进这一轮，300 秒还认不出层 → giveUp
    if inG and c and not c.joinedAt and now() - c.t < LH.JOIN_WIN then
        local ld, hit = leaderName(), p
        -- pending 已清：队长得是这一轮点名 / 认领过的帮手（别把会员顺手组的副本队当成换层队，换了层就退）
        if not hit then for nm in pairs(c.a) do hit = hit or sameName(nm, ld) end end
        if hit then
            c.joinedAt, c.leader = now(), ld or p.helper
            LY.Stat("i")
            if not p then C_Timer.After(LH.CONFIRM, function() if LH.ctx == c and not LH.pending then giveUp(c) end end) end
        end
    end
    if not p then return end
    if p.joinedAt then
        -- 11-12：还没确认就自己退了队（层会留下）→ 马上读一遍 / 推断一次，别让页面一直挂着「正在确认」
        if not inG and not p.leftAt then p.leftAt = now(); LH.Probe(p, true); LY.dirty = true end
        return
    end
    if not inG then return end
    p.joinedAt = now()
    local ld = leaderName()   -- 11-23 队长名《无限》可能只有「名」，同名不同姓会认错人 → 和认领 / 点名的帮手是同一人就用他的全名
    p.leader = (p.helper and sameName(p.helper, ld)) and p.helper or ld or p.helper
    LH.MarkRecent(p)
    LY.dirty = true
    if C_Timer and C_Timer.After then
        for _, d in ipairs(LH.PROBE_AT) do C_Timer.After(d, function() LH.Probe(p) end) end
        -- 11-09 用户「但是如果不提示用户不回去指吧？」：插件自己重读过了还没读到怪 → 10 / 40 / 70 秒各主动提示一次（屏幕中间 + 聊天框）
        for _, d in ipairs({ 10, 40, 70 }) do C_Timer.After(d, function() LH.NudgeRead(p) end) end
        C_Timer.After(LH.CONFIRM, function() LH.CheckJoined(p, true) end)
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
    if IsInGroup and IsInGroup() then return false end
    if LH.autoAll then return true end   -- 11-22 弹框里点了「这次登录全自动」：没组队时谁求都直接拉（含非本公会），重登恢复
    local ah = LY.DB().autoHelp
    if ah == false then return false end
    -- 11-22 用户「点了自动帮助别人切位面，为啥半天都没有帮」：原来只自动拉公会会员，路人求助晚 3 秒弹框、早被别人抢走 →
    --   开了自动帮助 = 单人没组队时公会会员和同图插件用户都直接拉（组队 / 战斗 / 副本照旧不自动）
    if ah == true then return true end
    if via == "guild" then return true end
    local LG = ns.LayerGuild
    return (LG and LG.ranks and LG.ranks[s] ~= nil) and true or false
end
function LH.AutoInvite(n)
    local p = LH.popups[n]
    if not p or not LH.CanHelp(p.any) then return false end
    if LY.InCombat() or LY.InInstance() then return LH.ShowPopup(n) end
    if now() - (p.t or 0) > LY.ASK_FRESH then LH.popups[n] = nil; return false end   -- 问一次的框搁太久才点：求助早过期了
    if LY.DB().autoHelp ~= true and not LH.autoAll then return LH.AskHelp(n) end
    local ok = LH.HelpInvite(n)   -- 无限客户端允许插件消息回调里邀请（Guild Master Forever 真机做法）
    if ok then LY.Stat("a"); ns.Print(string.format(L("%s 想换到你这层，已自动邀请（右侧『位面』页签可关）", "%s asked to join your layer - invited (turn off in the Layers tab)"), p.from)) end
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
    -- 11-06「前 6 个人一直被骚扰」：同一个人 REASK（2 小时）内重复点名我 → 忽略
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
    -- 11-20 路人（非本公会，公共频道认识的）：弹框写「非本公会」，一律弹框不自动拉（autoHelp 只管公会会员）；我没开帮忙就不理他的点名
    local LG = ns.LayerGuild
    local ng = via ~= "guild" and not (LG and LG.ranks and LG.ranks[s] ~= nil) or nil
    -- 点名请我的（t.to = 我）：我没开帮忙也弹框问一下（不自动拉）；位面识别关着 / 副本 / 战斗里照旧不理
    local asked = t.to ~= nil and LY.DB().on and not LY.InInstance() and not LY.InCombat() and not ng
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
    local fn = (can and (not ng or LH.autoAll or LY.DB().autoHelp == true) and LH.AutoHelpOK(s, via)) and LH.AutoInvite or LH.ShowPopup
    -- 11-14 群友「请求位面切换的那个弹窗怎么每次才停留一两秒」：公会里开了自动帮忙的人 0~1.5 秒就认领（C 回执）→ 弹框的人这边刚弹出来就被收掉。
    --   要弹框问的晚 LH.POP_DELAY 秒再弹：这期间已经有人认领 = 根本不弹（不闪一下）；弹出来以后再被认领见下面 C 的处理
    if fn == LH.ShowPopup then delay = LH.POP_DELAY + delay end
    LH.popups[t.n] = { from = s, full = sender, q = tonumber(t.q), t = now() + delay, any = any, ng = ng, hn = tonumber(t.hn) }   -- 11-21 hn = 他自报帮过别人几次
    if C_Timer and C_Timer.After then C_Timer.After(delay, function() fn(t.n) end) else fn(t.n) end
end
LY.handlers.C = function(t, s, via)
    if (via ~= "pub" and via ~= "guild" and via ~= "whisper") or not t.n then return end
    if LH.popups[t.n] and t.h ~= me() then
        LH.popups[t.n] = nil
        -- 11-14：框已经弹出来了才被别人认领 → 不一下子消失（看着像「只停一两秒」），改成写明谁在拉、停几秒再收
        if not LH.ClaimedPopup(t.n, s or t.h) then LH.HidePopup(t.n) end
    end
    if LH.pending and LH.pending.n == t.n and not LH.pending.helper then LH.pending.helper = s or t.h end   -- 11-09：s 带姓，t.h 可能只有名
    local c = LH.ctx   -- 11-22 认领了我这一轮请求的帮手：他的邀请按那次请求的时间放宽到 POP_LIVE
    if c and c.n[t.n] and (s or t.h) then c.a[s or t.h] = c.n[t.n] end
end
LY.handlers.D = function(t, s)
    -- 11-19 ns = 这一轮他别的请求号（点名链前面问过的 / 30 秒后又点的）：和 n 一起收框、取消还没发出的自动邀请（AutoInvite / 弹框都先查 popups）
    local who
    for k in ((t.n or "") .. "," .. (t.ns or "")):gmatch("[^,]+") do
        if LH.popups[k] then LH.popups[k] = nil; LH.HidePopup(k) end
        if LH.myInvites and LH.myInvites[k] then who = LH.myInvites[k]; LH.myInvites[k] = nil end
    end
    -- 11-14 框留 90 秒后：他换了一个人求（新的 n）、被那人拉到了 → 我这边旧的框也收掉，别留着让我白邀请
    if s then
        for k, q in pairs(LH.popups) do
            if q.from and sameName(q.from, s) then LH.popups[k] = nil; LH.HidePopup(k) end
        end
    end
    -- 11-23 用户「同意」：我拉了他却没换成（ok=0、h=我）→ 不算他请过我，删掉 askedBy，他马上能再点名我
    if t.ok ~= "1" and s and t.h and (LY.IsMe(t.h) or sameName(t.h, me())) then LH.askedBy[s] = nil end
    if not who then return end
    -- 11-19 h = 谁拉的（老版本不带）：不是我 → 我的邀请慢了一步，说一句，别写「已换到你这层」
    if t.h and not LY.IsMe(t.h) and not sameName(t.h, me()) then
        return ns.Print(string.format(L("%s 已经被 %s 拉过去了，你的邀请不用管（对方会拒绝）", "%s was already pulled by %s - ignore your invite"), who, (t.h:gsub("%-.*$", ""))))
    end
    -- 11-21 互助额度：帮人换成一次 +1（存档 layer.cr：b 攒下的 / n 累计帮过；上限、每日赠送、扣法和显示都在 _LayerUI 的 LayerCredit.lua）
    local ok1 = t.ok == "1"
    if ok1 then local d = LY.DB(); local c = type(d.cr) == "table" and d.cr or {}; d.cr = c; c.b, c.n = (c.b or 0) + 1, (c.n or 0) + 1; LY.Stat("k") end
    LY.Flash(string.format(L("%s 已换到你这层", "%s is now on your layer"), who) .. (ok1 and L("（互助额度 +1）", " (+1 help credit)") or ""))
    -- 11-19：他拿我的层当成他的新层 → 我这边马上重读一遍、补发心跳，别让他页面上看到我还在几分钟前那层
    local ok, changed = pcall(LY.ReadAll)
    if not (ok and changed) then LY.Beat(true) end
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
    -- 11-22 认领先密语给他（直接发，不排队）再邀请：他那边先认出是我，邀请一到就自动接（原来认领排在队列后面，常比邀请晚到）
    local to = "WHISPER:" .. (p.full or p.from)
    local cm = LY.Encode("C", { n = n, h = me() })
    if not LY._rawSend(to, cm) then LY.Queue(to, cm, true) end
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
function LH.PopOn() return not (ns.db and type(ns.db.layer) == "table" and ns.db.layer.hopPop == false) end
function LH.SetPop(v)
    if v then LY.DB().hopPop = nil else LY.DB().hopPop = false end
    if not v and pop then pop:Hide() end
end
function LH.Never()
    if pop and pop.n then LH.popups[pop.n] = nil end
    LH.SetPop(false)
    if ns.CloseHint then
        ns.CloseHint("layerHopPop", L("换层求助弹框已永久关闭（公会会员求助自动拉不受影响）。找回：GI 菜单 → 窗口与提醒 → 换层求助弹框，或位面页设置",
            "Layer help prompt closed for good (auto-invite for guildmates unchanged). Bring it back: GI menu > Windows & alerts > Layer help prompt, or the Layers tab"))
    end
end
function LH.ShowPopup(n)
    local p = LH.popups[n]
    -- 11-09 review：原来这里又查 CanHelp()，没开帮忙的被点名时（R 里特意放行的「弹框问一下」）永远弹不出来
    if not p or not LY.DB().on or LY.InInstance() or LY.InCombat() then return end
    if not LH.PopOn() then LH.popups[n] = nil; return end   -- 11-17 点过「不再弹」（永久，存档 layer.hopPop = false）
    if LH.muteUntil and now() < LH.muteUntil then LH.popups[n] = nil; return end
    -- 11-21 互助额度：正弹着的那位帮过别人更多（hn）→ 不被后来的顶掉（帮得多的人求助优先被看到；被挡下的那位 30 秒后会自动换人）
    local cur = pop and pop:IsShown() and pop.n and pop.n ~= n and LH.popups[pop.n]
    if cur and (cur.hn or 0) > (p.hn or 0) then return end
    if not pop then
        pop = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        pop:SetSize(530, 34); pop:SetPoint("TOP", UIParent, "TOP", 0, -120); pop:SetFrameStrata("HIGH")
        if pop.SetBackdrop then
            pop:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            pop:SetBackdropColor(0.04, 0.06, 0.1, 0.92); pop:SetBackdropBorderColor(0.4, 0.7, 1, 0.9)
        end
        pop.text = pop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pop.text:SetPoint("LEFT", 8, 0); pop.text:SetJustifyH("LEFT")
        -- 11-09 review：原来写「今天别提示」实际是永久关掉帮忙开关 → 改成这次上线不再弹（重登恢复），开关不动
        pop.mute = ns.Button(pop, L("这次上线别弹", "Mute session"), 96, 22, function() LH.muteUntil = now() + 86400; if pop.n then LH.popups[pop.n] = nil end; pop:Hide() end)
        pop.mute:SetPoint("RIGHT", -4, 0)
        -- 11-17 用户「这些弹出的功能都确保能永久关闭」：「这次上线别弹」只管本次登录（保留），再加「不再弹」= 永久（存档 layer.hopPop = false，
        --   位面页设置里「别人求我拉他换层时弹框问」同一个键；会员求助自动拉不受影响）；框整体加宽 70 放下这个按钮
        pop.never = ns.Button(pop, L("不再弹", "Never"), 60, 22, function() LH.Never() end)
        pop.never:SetPoint("RIGHT", -4, 0)
        pop.mute:ClearAllPoints(); pop.mute:SetPoint("RIGHT", pop.never, "LEFT", -4, 0)
        pop.no = ns.Button(pop, L("忽略", "Ignore"), 50, 22, function() if pop.n then LH.popups[pop.n] = nil end; pop:Hide() end)
        pop.no:SetPoint("RIGHT", pop.mute, "LEFT", -4, 0)
        pop.yes = ns.Button(pop, L("邀请", "Invite"), 56, 22, function() if pop.n and LH.HelpInvite(pop.n) then LY.Stat("c") end end)
        pop.yes:SetPoint("RIGHT", pop.no, "LEFT", -4, 0)
        -- 11-22 用户「换位面弹窗增加一个，这次登录全部自动同意按钮（单人没组队情况）」：点了 = 这个也拉 + 这次登录里没组队时谁求都直接拉（重登恢复）
        pop.all = ns.Button(pop, L("这次登录全自动", "Auto this session"), 104, 22, function() LH.autoAll = true; ns.Print(L("这次登录没组队时自动拉人（重登恢复）", "Auto-invite while solo this session")); if pop.n and LH.HelpInvite(pop.n) then LY.Stat("c") end; pop:Hide() end)
        pop.all:SetPoint("RIGHT", pop.yes, "LEFT", -4, 0)
    end
    pop.n = n
    pop.yes:Show(); pop.no:Show(); pop.mute:Show(); pop.never:Show(); pop.all:Show()   -- 上一个框被认领时收起过
    local qn = p.q and C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(p.q)
    local base = ns.EnSafe(string.format(L("%s 想换到你这层%s", "%s wants to switch to your layer%s"), p.from .. (p.ng and L("（非本公会）", " (not in your guild)") or ""),
        (type(qn) == "string" and not ns.Secret(qn)) and ("（在做【" .. qn .. "】）") or ""))
        .. (p.hn and ("|cff88ccff" .. string.format(L(" · 他帮过别人 %d 次", " - helped others %d"), math.min(999, p.hn)) .. "|r") or "")
    -- 11-14 用户「切位面的（询问我）太短暂了，几秒钟就消失了」：原来 10 秒就关 → 30 秒；同日又说「让我组的窗口太短暂了」→ LH.POP_LIVE = 90 秒
    --   （对方 30 秒后会自动换人，但会长 / 官员 / 本轮问过的人晚点的邀请新版照样自动接；他到了别处 = D 回执把框收掉）。原注释：留到对方还肯接邀请的时候（LH.ACCEPT_WIN = 30 秒，
    --   过了他那边会自动换下一个人，再拉也白拉），行尾倒计时「还剩 N 秒」
    local untilT = now() + LH.POP_LIVE
    local function paint()
        local left = math.max(0, math.ceil(untilT - now()))
        pop.text:SetText(base .. "  |cff888888" .. string.format(L("（还剩 %d 秒）", "(%ds left)"), left) .. "|r")
    end
    paint()
    pop:SetWidth(math.max(640, (tonumber(pop.text:GetStringWidth()) or 0) + 410))   -- 11-21 字多了（帮过几次）框跟着加宽，别压到按钮
    pop.untilT, pop.tick = untilT, 0
    pop:SetScript("OnUpdate", function(self, el)
        self.tick = (self.tick or 0) + (el or 0)
        if self.tick < 1 then return end
        self.tick = 0
        if pop.n ~= n then return end
        paint()
    end)
    pop:Show()
    LY.Stat("p")
    local my = n
    if C_Timer and C_Timer.After then C_Timer.After(LH.POP_LIVE, function() if pop.n == my then pop:Hide(); LH.popups[my] = nil end end) end
end
function LH.HidePopup(n)
    if pop and (not n or pop.n == n) then pop:Hide() end
end
-- 正显示着 n 的框被别人认领：文字改「XX 已经在拉他了」，按钮收起，LH.CLAIMED_LINGER 秒后关。返回 true = 处理了
function LH.ClaimedPopup(n, by)
    if not (pop and pop:IsShown() and pop.n == n) then return false end
    local who = tostring(by or "?"):gsub("%-.*$", "")
    pop:SetScript("OnUpdate", nil)
    pop.yes:Hide(); pop.no:Hide(); pop.mute:Hide(); pop.never:Hide(); pop.all:Hide()
    pop.text:SetText("|cff88ff88" .. string.format(L("%s 已经在拉他了，不用你邀请", "%s is already pulling them - nothing to do"), ns.EnSafe(who)) .. "|r")
    pop.n = nil
    if C_Timer and C_Timer.After then C_Timer.After(LH.CLAIMED_LINGER, function() if pop.n == nil then pop:Hide() end end) end
    return true
end
LH._pop = function() return pop end

-- 11-17「这些弹出的功能都确保能永久关闭」：换层求助弹框 / 位面切换的屏幕提示，从设置页「窗口与提醒」找回（位面识别开着才有）
if ns.RegisterWindow then ns.RegisterWindow({ key = "layerHopPop", order = 75, title = function() return L("换层求助弹框（位面）", "Layer help prompt") end,
    avail = function() return LY.DB().on ~= false end,
    state = function()
        if not LH.PopOn() then return L("已关闭", "Closed") end
        return L("有人求你拉他换到你这层时弹出", "Pops up when someone asks to join your layer")
    end,
    actions = function()
        local on = LH.PopOn()
        return { { text = on and L("关闭", "Turn off") or L("打开", "Turn on"), fn = function() LH.SetPop(not on) end } }
    end }) end
if ns.RegisterWindow then ns.RegisterWindow({ key = "layerFlash", order = 77, title = function() return L("位面切换屏幕提示", "Layer change on-screen text") end,
    avail = function() return LY.DB().on ~= false end,
    state = function()
        if LY.DB().flash == false then return L("已关闭", "Off") end
        return L("换层时屏幕上方出一行字", "A line of text at the top when your layer changes")
    end,
    actions = function()
        local on = LY.DB().flash ~= false
        return { { text = on and L("关闭", "Turn off") or L("打开", "Turn on"), fn = function()
            if on then LY.DB().flash = false else LY.DB().flash = nil end
        end } }
    end }) end
