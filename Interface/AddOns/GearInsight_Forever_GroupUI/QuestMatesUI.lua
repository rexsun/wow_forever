-- 组队 · 任务组队的抽屉界面（11-13 界面重构第 5 期从 QuestMates.lua 拆出来，代码原样搬）。
--   本文件在按需加载的子插件 GearInsight_Forever_GroupUI 里：点右侧「组队」页签 / /gi qm / /gi 组队 / 小地图「组队」时才加载
--   （GearInsight_Forever_Group/QuestMates.lua 的 QM.EnsureUI）。
--   信标（收发 GIFQM1、心跳、进城暂停、身边玩家扫描、道谢）留在登录就加载的 GearInsight_Forever_Group：
--   界面没加载时收到的进度照样记在 QM.peers，这里一打开就画出来。
--   ⛔ 这里不发任何插件消息：要发的一律调信标的 QM.Request / QM.Broadcast / QM.SetSharing（发送节流和格式都在信标）
local _, ns = ...; ns = _G.GearInsightForever or ns
local QM = ns.QM
if not QM or not QM._b then return end   -- 信标没加载（GearInsight_Forever_Group 被关了）：什么都不做
local B = QM._b
local L, now, dbq, safe, myPos, yards = B.L, B.now, B.dbq, B.safe, B.myPos, B.yards
local shortName, wallNow, friendCVar, friendPlatesOn = B.shortName, B.wallNow, B.friendCVar, B.friendPlatesOn
local BEAT, SHOUT_GAP = B.BEAT, B.SHOUT_GAP
local peers = QM.peers
local MAX_PEERS, MAX_ROWS = QM.MAX_PEERS, QM.MAX_ROWS
local failKind = QM.FailKind
local modeList = QM.ModeList

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

local GUILD_TAG = "|cff40ff40<" .. L("公会", "Guild") .. ">|r "

function QM.Rows(selQid)
    local mine = QM.MyQuests()
    local byId = {}
    for _, q in ipairs(mine) do byId[q.id] = q end
    local map, x, y = myPos()
    local cfg = dbq()
    local rows = {}
    for key, e in pairs(peers) do
        local shared, behind, ahead, open = {}, 0, 0, 0
        for qid, h in pairs(e.quests or {}) do
            local q = byId[qid]
            if q and (not selQid or selQid == qid) then
                shared[#shared + 1] = { q = q, his = h }
                if h[1] < q.p then behind = behind + 1 elseif h[1] > q.p then ahead = ahead + 1 end
                if h[1] < 100 then open = open + 1 end
            end
        end
        local same = (map and e.map == map) and true or false
        local dist, approx
        if same then dist, approx = yards(map, x, y, e.x, e.y) end
        local short = key:match("^([^%-]+)") or key
        if QM.near[short] then dist, approx = math.min(dist or 40, QM.near[short].yd), false end   -- 姓名板看得到 = 就在身边
        local rg = cfg.range or 100
        local inRange = (rg < 0) or (rg == 0 and same) or (rg > 0 and dist ~= nil and dist <= rg)
        -- 11-11 用户截图「任务组队怎么很多人扫描不进来了」：原来只留进度比我低的，我 3/20 时几乎人人都比我快 → 64 人全被筛掉。
        --   杀怪任务只要他还没做完，组上就一起算 → 这个开关改成「只看没做完」（做完的才筛掉），进度比我低的照旧排前面
        local keep = #shared > 0 and inRange and (open > 0 or not cfg.onlyBehind) and not QM.IsDeclined(key) and not QM.IsBusy(key)
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
                if q then nShared = nShared + 1; if h[1] < 100 then behind = behind + 1 end end
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
            elseif behind == 0 and cfg.onlyBehind then why = L("他已经做完了", "already finished")
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

function QM.Invite(name, quiet)
    local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if not fn then return false end
    local ok = pcall(fn, name)
    if ok then
        QM.invited[shortName(name)] = now()
        QM.toolInviteAt = now()   -- 11-06 自动自由拾取：只管组队工具邀请来的队
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
            -- 11-07 玩家「这个怎么关？」：原来所有拒绝 / 已有队伍的系统消息都接，自己手动邀请被拒也刷屏、还被记进隐藏名单
            --   → 只认组队工具 10 分钟内发出的邀请；提示可 /gi qm quiet 关（只关提示，照样记下、照样跳过）
            local at = QM.invited[sn]
            if not at or now() - at > 600 then return end
            local quiet = dbq().quietResult
            QM.invited[sn] = nil
            QM.dirty = true
            pcall(QM.SetResult, sn, sp[2])
            if sp[2] == "declined" then
                QM.Declined()[sn] = wallNow()
                if not quiet then
                    local h = ns.SlashHint or "/gif"
                    ns.Print(string.format(L("组队：%s 拒绝了邀请，以后不再列出（%s qm clear 清空，%s qm quiet 关掉这条提示）",
                        "Group up: %s declined - hidden from now on (%s qm clear to reset, %s qm quiet to mute this)"), sn, h, h))
                end
            else
                QM.Busy()[sn] = wallNow()
                if not quiet then ns.Print(string.format(L("组队：%s 已经有队伍了，挪到列表下面「已有队伍」，可以私聊请他拉你",
                    "Group up: %s is already in a group - moved to \"In a group\"; whisper to ask for an invite"), sn)) end
            end
            return
        end
    end
end

-- 显示用：身边、等级差 ≤ 4、不在插件列表 / 队伍里；近的在前，等级近的在前
-- 11-11 用户「身边有很多人我没发组」：等级差 4 级外的原来一声不吭就不列 → 数出来；点提示行可切「等级不限」（cfg.nearAnyLv）
QM.nearSkipLv = 0
function QM.NearRows()
    local anyLv = dbq().nearAnyLv == true
    local skipLv = 0
    local known = {}
    for k in pairs(peers) do known[k:match("^([^%-]+)") or k] = true end
    local myLv = UnitLevel and UnitLevel("player") or 0
    local out = {}
    for short, w in pairs(QM.near) do
        if not known[short] and not (QM.IsMe and QM.IsMe(w.name or short, short)) and not (UnitInParty and UnitInParty(short)) and not QM.IsDeclined(short) and not QM.IsBusy(short)
            then
            if anyLv or w.lvl == 0 or math.abs(w.lvl - myLv) <= 4 then
                out[#out + 1] = { name = w.name, lvl = w.lvl, cls = w.cls, file = w.file, yd = w.yd, how = w.how, guild = QM.IsGuildmate(w.name or short) }
            else
                skipLv = skipLv + 1
            end
        end
    end
    QM.nearSkipLv = skipLv
    table.sort(out, function(a, b)
        if a.guild ~= b.guild then return a.guild end   -- 同公会置顶（10-18）
        if a.yd ~= b.yd then return a.yd < b.yd end
        local da, db = math.abs(a.lvl - myLv), math.abs(b.lvl - myLv)
        if da ~= db then return da < db end
        return a.name < b.name
    end)
    return out
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
-- ---------- 一键私聊（10-12 用户「增加一个一键私聊，老哥，我在做 xxx 任务（必须范围内），要不要一起，你有队伍，xxx」「你来定」）----------
-- 话术：没队伍「老哥，我在做「XX」，要不要一起组个队？」；有队伍「老哥，看你有队伍了，我也在做「XX」，组我一下吗？」（11-10 用户「说组我」）
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
-- 10-17 用户「加上[Gearinsight插件]」：中文客户端前缀改成 [Gearinsight插件]（私聊 / 喊人 / 解散道谢都走这里）
local TAG = L("[Gearinsight插件] ", "[Gearinsight] ")
QM.TAG = TAG
function QM.Tagged(msg)
    if dbq().noTag or type(msg) ~= "string" or msg:sub(1, #TAG) == TAG then return msg end
    return TAG .. msg
end
-- 11-10 用户「求组私聊也去掉插件标识」：一对一私聊不加 [Gearinsight插件]（喊人照旧走 QM.Tagged）
function QM.WhisperText(q, busy)
    return QM.WhisperBody(q, busy)
end
function QM.WhisperBody(q, busy)
    local t = q and q.title
    local members = tonumber(GetNumGroupMembers and GetNumGroupMembers()) or 0
    -- 11-09 GI-210：设置页「自动私信内容」填了组任务邀请就用自己的
    local mine = ns.MyWhisper and ns.MyWhisper("qm", { ["任务"] = t, ["人数"] = members > 1 and members or nil })
    if mine then return mine end
    if members > 1 then
        local intro = t and string.format(L("你好，我们在做「%s」，目前队伍有 %d 人。", "Hi, we're working on \"%s\" and currently have %d people in our group. "), t, members)
            or string.format(L("你好，我们正在附近做任务，目前队伍有 %d 人。", "Hi, we're questing nearby and currently have %d people in our group. "), members)
        return intro .. (busy and L("看你也有队伍，方便的话要不要一起做任务？", "I see you have a group too. Would you like to quest together?")
            or L("方便的话，要不要一起做任务？", "Would you like to join us and quest together?"))
    end
    if busy then
        return t and string.format(L("老哥，看你有队伍了，我也在做「%s」，组我一下吗？", "Hey, saw you're in a group - I'm on \"%s\" too, mind inviting me?"), t)
            or L("老哥，看你有队伍了，组我一下一起做任务吗？", "Hey, saw you're in a group - mind inviting me to quest together?")
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
-- QM.lastShout（上次喊人的时刻）在信标里初始化：每秒那轮 OnUpdate 界面没加载时也读它
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
    -- 11-10 用户截图「加个UI缩放和透明度」：标题栏「外观」按钮 → 小面板 [缩放 - 100% +] [背景 - 100% +]，存档记住。
    --   透明度只调背景（字和按钮照常清楚），钉在屏幕上练级时能透出后面的画面
    d.look = (W and W.Button) and W.Button(d, nil) or ns.Button(d, "", 52, 22)
    d.look:SetSize(52, 22); d.look:SetPoint("RIGHT", d.pin, "LEFT", -4, 0)
    d.look:SetText(L("外观", "Look"))
    local lp = CreateFrame("Frame", nil, d, BackdropTemplateMixin and "BackdropTemplate" or nil)
    lp:SetSize(200, 64); lp:SetPoint("TOPRIGHT", d.look, "BOTTOMRIGHT", 0, -4)
    if lp.SetBackdrop then
        lp:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        lp:SetBackdropColor(0.03, 0.035, 0.05, 0.97); lp:SetBackdropBorderColor(0.85, 0.68, 0.25, 0.9)
    end
    lp:SetFrameLevel((d:GetFrameLevel() or 1) + 20)
    lp:EnableMouse(true)
    lp:Hide()
    d.lookPanel = lp
    local function row(y, label, key, lo, hi)
        local fs = lp:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", 10, y - 4); fs:SetText(label)
        local val = lp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        val:SetPoint("TOPLEFT", 118, y - 4); val:SetWidth(44); val:SetJustifyH("CENTER")
        local function step(dv)
            local cur = tonumber(dbq()[key]) or 1
            cur = math.floor((cur + dv) * 20 + 0.5) / 20
            dbq()[key] = math.max(lo, math.min(hi, cur))
            QM.ApplyLook()
        end
        local minus = ns.Button(lp, "-", 24, 20, function() step(-0.05) end)
        minus:SetPoint("TOPLEFT", 92, y)
        local plus = ns.Button(lp, "+", 24, 20, function() step(0.05) end)
        plus:SetPoint("TOPLEFT", 164, y)
        return val
    end
    lp.scaleVal = row(-8, L("缩放", "Scale"), "scale", QM.SCALE_MIN, QM.SCALE_MAX)
    lp.alphaVal = row(-34, L("背景不透明", "Background"), "bgAlpha", QM.ALPHA_MIN, 1)
    d.look:SetScript("OnClick", function() lp:SetShown(not lp:IsShown()); QM.ApplyLook() end)
    d.look:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(L("缩放 / 透明度", "Scale / opacity"), 1, 0.82, 0)
        GameTooltip:AddLine(L("调这个窗口的大小和背景透明度，重新登录还记得", "Adjust this window's size and background opacity (saved)"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    d.look:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- 11-12 界面重构第 2 期：组队设置的齿轮（原设置页「组队」那栏 + 对应的自动私信内容；描述在主插件 Settings.lua）
    if ns.SettingsGearButton then
        d.gear = ns.SettingsGearButton(d, "group", true)
        d.gear:SetPoint("RIGHT", d.look, "LEFT", -4, 0)
    end
    -- 10-16 用户「左右两个组队太乱了」→ 拍板「只留右边，副本组队并进抽屉」：顶上 [附近任务] [副本组队] 切换。
    --   副本组队（PageGroup.lua，HOLD）没装就不出这两个按钮，抽屉和以前一模一样
    QM.BuildModeBtns(d)
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
    -- 第二行：四个等宽按钮  只看没做完（11-11 原「只看比我慢」）· 只看本区域 · 共享 · 刷新
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
    d.fBehind:SetText(cfg.onlyBehind and L("只看没做完", "Not done yet") or L("全部进度", "Any progress"))
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
        .. string.format(L("%d 人 · 40 码内 · ", "%d - 40 yd - "), #wr)
        .. (cfg.nearAnyLv and L("等级不限", "any level") or L("等级差 4 级内", "level +/-4"))
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
    local skipLv, secretN = QM.nearSkipLv or 0, (QM.plateStat and QM.plateStat.secret) or 0
    if #wr == 0 or plates ~= true or skipLv > 0 or cfg.nearAnyLv or secretN > 0 then
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
        local secretTxt = secretN > 0 and string.format(L("  · 另有 %d 人游戏不给读名字（选中他一下就能加进来）", "  - %d more hide their names (target them to add)"), secretN) or ""
        if plates == true and (skipLv > 0 or cfg.nearAnyLv) then
            h.t:SetText("|cffffd200" .. (cfg.nearAnyLv and L("已列出所有等级 · 点这里只看等级差 4 级内的", "Showing all levels - click for +/-4 only")
                or string.format(L("身边还有 %d 人等级差超过 4 级没列 · 点这里也列出来", "%d more nearby are 5+ levels away - click to list them"), skipLv)) .. "|r" .. DIM .. secretTxt .. "|r")
            h:SetScript("OnClick", function() local c = dbq(); c.nearAnyLv = not c.nearAnyLv or nil; QM.Render() end)
        elseif plates == true then
            h.t:SetText(DIM .. (#wr == 0 and L("身边 40 码内没有等级相近的玩家", "Nobody at your level within 40 yd") or "") .. secretTxt .. "|r")
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
    local canAll, cantWhy = QM.CanInvite("")
    local nInv = canAll and #QM.InviteCandidates(names) or 0
    -- 11-11 用户截图「我身边有很多人我没发组」：按钮灰着不说为啥（在别人队里不是队长 / 队伍满了）→ 原因写在按钮上
    d.invAll:SetText(nInv > 0 and string.format(L("组人 · %d 人", "Invite %d"), nInv)
        or (canAll and L("组人 · 暂无", "Invite - none") or (L("组人 · ", "Invite - ") .. (cantWhy or ""))))
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

-- 抽屉贴着页签放（照公会抽屉 placeDrawer：顶边和主面板齐；右边放不下就放到页签左边）
local function placeAtTab(d, host, tab)
    local W = ns.W
    if d:GetParent() ~= host and d.SetParent then d:SetParent(host) end
    if d.SetFrameStrata then d:SetFrameStrata("HIGH") end
    local hh = host.GetHeight and host:GetHeight()
    d:SetHeight(math.max(540, type(hh) == "number" and hh or 540))
    local ht, tt = host.GetTop and host:GetTop(), tab.GetTop and tab:GetTop()
    local dy = (type(ht) == "number" and type(tt) == "number") and (ht - tt) or 0
    -- 11-10 用户录屏：放不下先把主面板左移（W.RoomRight），左边也没地方才翻到页签左边盖住主面板
    local room = not (W and W.RoomRight) or W.RoomRight(host, tab, DW)
    d:ClearAllPoints()
    if not room then d:SetPoint("TOPRIGHT", tab, "TOPLEFT", -4, dy)
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

QM.SCALE_MIN, QM.SCALE_MAX, QM.ALPHA_MIN = 0.6, 1.5, 0.2
function QM.ApplyLook()
    local d = QM.drawer
    if not d then return end
    local cfg = dbq()
    local sc = math.max(QM.SCALE_MIN, math.min(QM.SCALE_MAX, tonumber(cfg.scale) or 1))
    local al = math.max(QM.ALPHA_MIN, math.min(1, tonumber(cfg.bgAlpha) or 1))
    if d.SetScale then d:SetScale(sc) end
    if d.SetBackdropColor then d:SetBackdropColor(0.035, 0.04, 0.055, al) end
    if d.SetBackdropBorderColor then d:SetBackdropBorderColor(0.85, 0.68, 0.25, math.max(0.4, al)) end
    local lp = d.lookPanel
    if lp then
        lp.scaleVal:SetText(math.floor(sc * 100 + 0.5) .. "%")
        lp.alphaVal:SetText(math.floor(al * 100 + 0.5) .. "%")
    end
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
    QM.drawer = QM.drawer or build(nil); pcall(QM.ApplyLook)
    placePinned(QM.drawer)
    QM.drawer:Show()
    QM.Request()
    QM.Render()
    -- 11-10 用户「reload 后保持是副本组队，不要切任务组队」：恢复上次的模式。这时 DungeonChat.lua 可能还没载入 → 下一帧再切
    if cfg.mode == "dungeon" then
        local function go() pcall(QM.SetMode, "dungeon") end
        if C_Timer and C_Timer.After then C_Timer.After(0, go) else go() end
    end
end

-- 副本组队盖在任务内容上面（实底、挡鼠标），切回附近任务就藏起来
-- 11-10 用户「点了没反应，也没红字」：/run 实测 d.lfg = nil —— 组队窗口上次开着，登录时 QuestMates.lua 一载入就建了抽屉，
--   那时 DungeonChat.lua（toc 排在后面）还没载入 → 没建盖板，之后点副本组队直接 return。→ 盖板改成用到时再补建
function QM.EnsureLfg(d)
    if not d or rawget(d, "lfg") then return d and rawget(d, "lfg") end
    if not (ns.BuildDungeonPanel or ns.BuildGroupPanel) then return nil end
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
    return o
end

-- 11-12 界面重构第 2 期（§6 拍板 4）：第三个子页签「法师吃喝」= MageWater.lua 的设置面板挂在这层上（盖在任务 / 副本内容上面）
function QM.EnsureMw(d)
    if not d or rawget(d, "mwPane") then return d and rawget(d, "mwPane") end
    if not (ns.MageWater and ns.MageWater.EmbedSettings) then return nil end
    local o = CreateFrame("Frame", nil, d, BackdropTemplateMixin and "BackdropTemplate" or nil)
    o:SetPoint("TOPLEFT", 4, -38); o:SetPoint("BOTTOMRIGHT", -4, 4)
    if o.SetBackdrop then
        o:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        o:SetBackdropColor(0.035, 0.04, 0.055, 1)
    end
    local lvl = d.GetFrameLevel and d:GetFrameLevel()
    -- 11-12 用户截图：副本组队盖板（lvl+30）的按钮 / 滑条是它的子框，层级 +31~+35，压在 +32 的这层上面 → 抬高，切到这页时也把盖板收起
    if lvl and o.SetFrameLevel then o:SetFrameLevel(lvl + 60) end
    o:EnableMouse(true)
    o:Hide()
    d.mwPane = o
    return o
end

-- 10-16 抽屉模式：quest = 附近任务（原来的），dungeon = 副本组队；11-12 第 2 期 mage = 法师吃喝设置（不记进存档：下次开抽屉还是任务 / 副本）
function QM.SetMode(m)
    local d = QM.drawer
    if d then QM.EnsureLfg(d) end
    if m == "mage" then
        if not (ns.MageWater and ns.MageWater.EmbedSettings) and ns.GroupLoadMage then ns.GroupLoadMage(true) end   -- 11-13 第 5 期：法师吃喝按需加载
        local pane = d and QM.EnsureMw(d)
        if not pane then return end
        d.mwOn = true
        if rawget(d, "lfg") then d.lfg:Hide() end
        pane:Show()
        pcall(ns.MageWater.EmbedSettings, pane)
        QM.MarkMode("mage")
        QM.SyncSubTabs()
        return
    end
    if d then
        d.mwOn = nil
        if rawget(d, "mwPane") then d.mwPane:Hide() end
    end
    if not d or not d.lfg then
        if m == "dungeon" then ns.Print(L("副本组队没建起来：组队窗口是在副本组队装上之前打开的，/reload 一下再点", "Dungeon group not ready: /reload and try again")) end
        return
    end
    dbq().mode = m
    if m == "dungeon" then
        -- 11-10 用户「点了没反应」：建面板出错时整段停在这，玩家只看到没反应 → 报错打到聊天框，好截图
        if not rawget(d, "lfgBuilt") then
            local ok, res = pcall(ns.BuildDungeonPanel or ns.BuildGroupPanel, d.lfg, DW - 8, 540 - 42)
            if not ok then ns.Print("|cffff6060" .. L("副本组队出错（截图发给开发者）：", "Dungeon group error: ") .. tostring(res) .. "|r") end
            d.lfgBuilt = ok and res
        end
        d.lfg:Show()
        local rf = ns.BuildDungeonPanel and ns.RefreshDungeonPanel or ns.RefreshGroupPage
        if rf then rf() end
    else
        d.lfg:Hide()
    end
    QM.MarkMode(m)
    QM.SyncSubTabs()
end
function QM.MarkMode(m)
    local d = QM.drawer
    local tab = QM.Tab()
    for _, set in ipairs({ d and rawget(d, "modeBtns") or {}, tab and rawget(tab, "_giSubByMode") or {} }) do
        for k, b in pairs(set) do
            if rawget(b, "_seg") and ns.SegSelect then ns.SegSelect(b, k == m)
            elseif ns.MarkSelected then ns.MarkSelected(b, k == m) end
        end
    end
end

-- 11-11 用户截图「文字不对」：钉住的窗口登录时先建好，那会儿副本组队（DungeonChat.lua）还没载入 →
--   没出 [任务组队][副本组队] 按钮、标题停在「同任务的人」。抽成函数，EnsureLfg 补建盖板时再补一次
function QM.BuildModeBtns(d)
    if not d or rawget(d, "modeBtns") or not (ns.BuildDungeonPanel or ns.BuildGroupPanel) then return end
    d.title:SetText(L("组队", "Group up"))
    d.modeBtns = {}
    local list = modeList()
    -- 11-12 第 2 期多了「法师吃喝」：三个按钮收窄，别压到标题栏右边的「组队设置 / 外观 / 钉住」
    local bw = (#list >= 3) and 58 or 92
    local mx = PAD + ((#list >= 3) and 40 or 52)
    for _, m in ipairs(list) do
        local b = (ns.SegButton or ns.Button)(d, m[2], bw, 22, function() QM.SetMode(m[1]) end)   -- 10-17 分段按钮（扁平深底，选中金边金线）
        b:SetPoint("TOPLEFT", mx, -9); mx = mx + bw + 2 + ((#list >= 3) and 0 or 2)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(m[2], 1, 0.82, 0)
            GameTooltip:AddLine(m[3], 1, 1, 1, true); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        d.modeBtns[m[1]] = b
    end
    if QM.EnsureLfg then QM.EnsureLfg(d) end
end

-- 点右侧「组队」页签（信标里的页签 OnClick 转过来；原来写在 attach 里，原样搬）
function QM.TabClick(tab)
    local host = _G.GearInsightForeverMain
    local W = ns.W or _G.GIWidgets
    tab = tab or QM.Tab()
    if not (host and tab and W) then return end
    if ns.PerfGuard and ns.PerfGuard.UserOpened then pcall(ns.PerfGuard.UserOpened) end   -- 10-22 自动卡顿检测暂停 / 关掉过组队：玩家自己点开 = 恢复，以后不再替他关
    QM.drawer = QM.drawer or build(host); pcall(QM.ApplyLook)
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
    if QM.EnsureLfg(d) then QM.SetMode(cfg.mode or "quest") end
    QM.SyncSubTabs()
    pcall(QM.AskGuildRoster)
    QM.Request()
    QM.ScanNear()
    QM.Render()
end

-- /gi 组队：打开主面板 + 右侧「组队」抽屉，并切到指定模式（ns.OpenGroupDrawer 在信标，转到这里）
function QM.OpenDrawer(mode)
    local host = _G.GearInsightForeverMain
    if not (host and host:IsShown()) and ns.ToggleMain then ns.ToggleMain() end
    pcall(QM.Attach)
    local tab = QM.Tab and QM.Tab()
    if not (QM.drawer and QM.drawer:IsShown()) and tab then
        local click = tab:GetScript("OnClick")
        if click then click(tab) end
    end
    if mode then QM.SetMode(mode) end
end

-- /gi qm 里要动抽屉的子命令（信标的 /gi qm 转过来）
function QM.SlashUI(rest, rawRest)
    rest = rest or ""
    if rest == "say" or rest == "yell" or rest == "local" then
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
    elseif rest == "pin" then
        QM.drawer = QM.drawer or build(nil); pcall(QM.ApplyLook)
        QM.SetPinned(not dbq().pinned)
    else
        local host = _G.GearInsightForeverMain
        if not (host and host:IsShown()) then ns.ToggleMain() end
        host = _G.GearInsightForeverMain
        local tab = host and rawget(host, "_giQmTab")
        if tab and not (QM.drawer and QM.drawer:IsShown()) then tab:GetScript("OnClick")(tab) end
    end
end

-- 只有界面在才用得上的事件：邀请结果（系统消息）/ 进队记结果 + 重画 / 公会名单变了（同公会标注）——挂到信标的事件框上，处理函数还是信标那一个
if QM._ev then
    for _, e in ipairs({ "CHAT_MSG_SYSTEM", "GROUP_ROSTER_UPDATE", "GUILD_ROSTER_UPDATE" }) do
        local valid = not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e)
        if valid then pcall(QM._ev.RegisterEvent, QM._ev, e) end
    end
end
QM.uiLoaded = true
pcall(QM.EnsureSubTabs)   -- 页签先挂好、界面后加载：子页签现在补上
