-- HOLD（11-15）：副本组队「招人」把集合石（游戏原生「寻求组队」，C_LFGList，按 I 那个）里单人挂单求组的散人读进「来密我的人」。
-- 用户（招人页截图：死亡矿井 19~27 级，已勾「集合石 · 已挂」，下面「来密我的人」）：「集合石求组的 散人，能读取进来吗」
-- 证据（10-16 Beta 70374 /gi lfgprobe 存档 GearInsightForeverDB.lfgprobe）：
--   · Search(2) 可用（Search(2, 活动表) 报「bad argument #2」）；按钮里搜、计时器里搜都没被拦（search_click / search_timer = ok，结果 38 / 43 条）
--   · GetSearchResultInfo 读得到 leaderName / numMembers / age / activityIDs / isDelisted / hasSelf；name / comment 是空串
--     （存档前三条都是 numMembers = 1 = 经典端单人挂单：经典版集合石里散人自己挂一条「找队」，人数就是 1）
--   · 有 GetSearchResultPlayerInfo / GetSearchResultLeaderInfo / GetSearchResultMemberCounts；没有 GetSearchResultMemberInfo
--   · 11-14 用户 BugGrabber（求组页集合石扫描 LfgListScan）：正式服 activityIDs 可能整张是保密表 → 一律先过 clean
--   ⛔ 1.60.1（70790）正式服没跑过完整探针：所有接口 pcall；名字 / 人数读不到（保密 / 没有）这条就不列，职业 / 等级 / 职责读不到就空着，不编
-- 做法：
--   · 招人页开着时每 45 秒 Search(地下城 2) 一次（打开招人页 / 点「刷新」= 玩家点击里搜；计时器里搜被游戏拦了 → 以后只在点「刷新」时搜）；
--     暴雪自己的集合石窗口开着不抢它的搜索，只读它的结果；求组页的集合石扫描（LfgListScan，另一分支 HOLD）刚搜过也不重复搜，结果共用
--   · 只取「单人挂单」（人数 = 1；numMembers 读不到时用各职责人数加起来）、挂的活动里有当前招人副本的；跳过自己 / 下架 / 自己挂的
--   · 按招人设置筛：等级在最低 / 最高之间（关了「喊等级」不筛；读不到等级不筛）、需要的职责（读得到他的职责才筛；纯输出职业按输出算）、
--     职业点了「不要」的不列；点了「要」的排前面
--   · 显示：并进「来密我的人」同一张表，「说的话」开头灰色「[集合石]」；同一个人既密过我又挂了集合石 → 合成一行（密我那行补上集合石读到的等级 / 职业 / 职责）
--   · 「邀请」= 现有 DC.Invite（C_PartyInfo.InviteUnit，只在按钮点击里调）；「私聊」= 第一次点发招呼（这个副本的招人话术，没写「M我」又读不到等级 / 职责就补反问，
--     带「带标识」前缀规则）；15 分钟内再点 = 打开对他的私聊输入框。招呼过的人回话即使不在喊话 15 分钟窗口里也收进「来密我的人」
--   · 行尾「×」/ 表头「清空」：集合石的人本次登录不再列（不动存档）
-- 开关：DC.DB().rec.lfgSolo（nil = 开，false = 关）=「复制到聊天群」那排最右「集合石散人」+「刷新」。
-- 读不到（没有接口 / 受限 / 保密）：静默不列、不报错，记进 GearInsightForeverDB.lfgprobe.solo；/gi lfgsolo 打一行状态
local _, ns = ...; ns = _G.GearInsightForever or ns
local L = function(cn, en) return ns.L(cn, en) end

local DC = ns.DungeonChat
if not DC then return end
local clean, short = DC._clean or function(v) return v end, DC.Short
local isMe = DC._isMe or function() return false end
local function now() return (GetTime and GetTime()) or 0 end

local S = { all = {}, hidden = {}, greeted = {}, why = {} }
ns.LfgSolo = S

S.CAT = 2            -- 集合石「地下城」分类
S.INTERVAL = 45      -- 招人页开着时多久自动搜一次（秒）
S.CLICK_GAP = 3      -- 手动刷新最短间隔
S.KEEP = 180         -- 结果多久没刷新就不再列
S.MAX_ROWS = 20      -- 集合石散人最多列几个（密过我的那些不算）
S.GREET_WIN = 900    -- 招呼过的人多久内回话算「来密我的人」
S.GRAY = "|cff9a9a9a"

-- GI 副本名 → 集合石活动编号（GroupFinderActivity 1.60.1.70790；和 LfgListAuto.ACTS 同一份。LfgListAuto 也在 HOLD，这里各带一份，缺了它也能用）
S.ACTS = {
    ["怒焰裂谷"] = { 798 }, ["领主大厅"] = { 1984 }, ["洛丹伦废墟"] = { 1982 }, ["哀嚎洞穴"] = { 796 }, ["死亡矿井"] = { 799 },
    ["影牙城堡"] = { 800 }, ["黑暗深渊"] = { 801 }, ["暴风城监狱"] = { 802 }, ["挖掘场"] = { 1981 },
    ["血色修道院"] = { 805, 829, 827, 828 }, ["达拉然城"] = { 1983 }, ["诺莫瑞根"] = { 803 }, ["剃刀沼泽"] = { 804 },
    ["剃刀高地"] = { 806 }, ["奥达曼"] = { 807 }, ["祖尔法拉克"] = { 808 }, ["玛拉顿"] = { 809 }, ["沉没的神庙"] = { 810 },
    ["黑石深渊"] = { 811 }, ["厄运之槌"] = { 813, 814, 815 }, ["黑石塔下层"] = { 812 }, ["黑石塔上层"] = { 837 },
    ["通灵学院"] = { 797 }, ["斯坦索姆"] = { 816, 1603 },
}
local ACT2DG = {}
for n, ids in pairs(S.ACTS) do for _, id in ipairs(ids) do ACT2DG[id] = n end end

local function api() return type(C_LFGList) == "table" and C_LFGList or nil end
local function fn(name)
    local t = api()
    local f = t and t[name]
    return type(f) == "function" and f or nil
end
-- 调一个返回表的接口；不是表（或整张是保密表）= nil
local function tcall(name, ...)
    local f = fn(name)
    if not f then return nil end
    local ok, r = pcall(f, ...)
    r = ok and clean(r) or nil
    if type(r) == "table" then return r end
    return nil
end
local function num(v) return tonumber(clean(v)) end
local function str(v)
    v = clean(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end
local function truthy(v) v = clean(v); return v == true or v == 1 end
local function say(msg) if msg and ns.Print then ns.Print(msg) end end

-- 探针：读不到 / 被拦都记进存档（不弹错），/gi lfgsolo 和 /gi lfgprobe ⑧ 带出来
local function probe(k, v)
    if not ns.db then return end
    ns.db.lfgprobe = ns.db.lfgprobe or {}
    local p = ns.db.lfgprobe
    p.solo = p.solo or {}
    p.solo[k] = v
end
S._probe = probe

function S.On() return DC.DB().rec.lfgSolo ~= false end
function S.Toggle()
    local r = DC.DB().rec
    if r.lfgSolo == false then r.lfgSolo = nil else r.lfgSolo = false end
    if not S.On() then S.all, S.readAt, S.stale = {}, nil, nil end
end

-- ---------- 一个人：职业 / 等级 / 职责 ----------
local ROLE_OK = { TANK = true, HEALER = true, DAMAGER = true }
local PURE_DPS = { MAGE = true, WARLOCK = true, ROGUE = true, HUNTER = true }
local SOLO_KEYS = { soloRoleTank = "TANK", soloRoleHealer = "HEALER", soloRoleDPS = "DAMAGER" }
-- 正式服写法：GetSearchResultPlayerInfo(编号, 1) 回一张表（classFilename / className / level / assignedRole / lfgRoles{tank,healer,dps} / areaName）；
-- 经典写法：GetSearchResultMemberInfo(编号, 1) = 名字, 职责, 职业, 职业名, 等级, 所在地, 单人坦, 单人奶, 单人输出（老正式服 = 职责, 职业, 职业名, 专精）；
-- 都没有再试队长信息 GetSearchResultLeaderInfo。读不到的字段 = nil
function S.Member(id)
    local out = { roles = {} }
    local t = tcall("GetSearchResultPlayerInfo", id, 1) or tcall("GetSearchResultLeaderInfo", id)
    if t then
        out.via = "player"
        out.name = str(t.name) or str(t.leaderName)
        out.cls = str(t.classFilename) or str(t.classFileName)
        out.clsName = str(t.className) or str(t.localizedClass)
        out.lv = num(t.level)
        out.area = str(t.areaName)
        local lr = clean(t.lfgRoles)
        if type(lr) == "table" then
            if truthy(lr.tank) then out.roles.TANK = true end
            if truthy(lr.healer) then out.roles.HEALER = true end
            if truthy(lr.dps) or truthy(lr.damager) then out.roles.DAMAGER = true end
        end
        for k, role in pairs(SOLO_KEYS) do if truthy(t[k]) then out.roles[role] = true end end
        local ar = str(t.assignedRole)
        if not next(out.roles) and ar and ROLE_OK[ar] then out.roles[ar] = true end
    else
        local f = fn("GetSearchResultMemberInfo")
        if f then
            local ok, a, b, c, d, e5, e6, e7, e8, e9 = pcall(f, id, 1)
            if ok then
                out.via = "member"
                a = clean(a)
                if a == "NONE" or (type(a) == "string" and ROLE_OK[a]) then
                    out.cls, out.clsName = str(b), str(c)
                    if ROLE_OK[a] then out.roles[a] = true end
                else
                    out.name, out.cls, out.clsName, out.lv, out.area = str(a), str(c), str(d), num(e5), str(e6)
                    if truthy(e7) then out.roles.TANK = true end
                    if truthy(e8) then out.roles.HEALER = true end
                    if truthy(e9) then out.roles.DAMAGER = true end
                    local role = str(b)
                    if not next(out.roles) and role and ROLE_OK[role] then out.roles[role] = true end
                end
            end
        end
    end
    if out.cls and not (DC.CLS_TC and DC.CLS_TC[out.cls]) then out.cls = nil end
    if out.lv and (out.lv < 1 or out.lv > 80) then out.lv = nil end
    return out
end

-- ---------- 一条结果 → 一个散人（不是单人 / 不是地下城 / 读不到名字 = nil + 原因；第三个返回值 = 这条是不是地下城）----------
function S.Parse(id, t)
    local r = tcall("GetSearchResultInfo", id)
    if not r then return nil, "noinfo" end
    local ids, one = clean(r.activityIDs), clean(r.activityID)
    local acts = ids or (one and { one }) or {}
    if type(acts) ~= "table" then acts = { acts } end
    local dgs, any = {}, false
    for _, x in ipairs(acts) do
        x = num(x)
        local n = x and ACT2DG[x]
        if n then dgs[n], any = true, true end
    end
    if not any then return nil, "notdg" end
    if clean(r.isDelisted) or clean(r.hasSelf) then return nil, "self", true end
    local n = num(r.numMembers)
    if n == nil then
        local mc = tcall("GetSearchResultMemberCounts", id)
        if mc then
            local s, got = 0, false
            for _, k in ipairs({ "TANK", "HEALER", "DAMAGER", "NOROLE" }) do
                local v = num(mc[k])
                if v then s, got = s + v, true end
            end
            if got then n = s end
        end
    end
    if n == nil then return nil, "nonum", true end
    if n ~= 1 then return nil, "group", true end
    local m = S.Member(id)
    local raw = r.leaderName
    local name = str(raw) or m.name
    if not name then return nil, (raw ~= nil and ns.Secret and ns.Secret(raw)) and "secretname" or "noname", true end
    if isMe(name) then return nil, "me", true end
    local e = {
        id = num(r.searchResultID) or id, author = name, short = short(name), dgs = dgs,
        t = (t or now()) - (num(r.age) or 0), cls = m.cls, clsName = m.clsName, lv = m.lv, roles = m.roles, area = m.area, via = m.via,
    }
    -- 留言：保密值只留着给界面显示（不拼接、不比较、不解析）；普通字符串照常
    local cm = r.comment
    if cm ~= nil and ns.Secret and ns.Secret(cm) then e.commentSecret = cm
    else e.comment = str(cm) end
    local title = str(r.name)
    if title and title ~= e.comment then e.title = title end
    return e, nil, true
end

-- 读当前搜索结果。force = 我自己搜的结果回来了（结果里没有地下城也换）
function S.Read(force)
    local g = fn("GetSearchResults")
    if not g then probe("api", "noGetSearchResults"); return false end
    local ok, a, b = pcall(g)
    a, b = ok and clean(a) or nil, ok and clean(b) or nil
    local ids = (type(a) == "table" and a) or (type(b) == "table" and b) or nil
    if not ids then probe("api", ok and "resultsNotTable" or ("resultsErr " .. tostring(a):sub(1, 80))); return false end
    local out, t, dg, why, seen = {}, now(), 0, {}, {}
    local okL, errL = pcall(function()
        for _, id in ipairs(ids) do
            local okP, e, w, isDg = pcall(S.Parse, id, t)
            if not okP then
                why.err = (why.err or 0) + 1
                probe("parseErr", tostring(e):sub(1, 120))
            else
                if isDg then dg = dg + 1 end
                if e and not seen[e.short] then seen[e.short] = true; out[#out + 1] = e
                elseif w then why[w] = (why[w] or 0) + 1 end
            end
        end
    end)
    if not okL then probe("api", "loopErr " .. tostring(errL):sub(1, 80)); return false end
    -- 暴雪集合石窗口里在搜别的分类（任务 / 自定义）：结果里一个地下城都没有，别把上一轮清空
    if not force and dg == 0 and #ids > 0 then S.stale = nil; return false end
    S.all, S.readAt, S.stale, S.total, S.dg, S.why = out, t, nil, #ids, dg, why
    probe("last", S.ProbeLine())
    DC.dirty = true
    return true
end

-- ---------- 按招人设置筛 ----------
local function rolesOf(e)
    if next(e.roles or {}) then return e.roles, true end
    if e.cls and PURE_DPS[e.cls] then return { DAMAGER = true }, true end
    return {}, false
end
-- d = 招人副本；返回 能列, 不列的原因
function S.Pass(e, d)
    if not (d and e.dgs[d.n]) then return false, "dg" end
    if S.hidden[e.short] then return false, "hidden" end
    local r = DC.DB().rec
    if not r.noLv and e.lv then
        local lo, hi = DC.RecRange()
        if e.lv < lo or e.lv > hi then return false, "lv" end
    end
    if e.cls and DC.ClsPick(e.cls) == "no" then return false, "cls" end
    local need = r.roles or {}
    if next(need) then
        local rs, known = rolesOf(e)
        if known then
            local hit = false
            for role in pairs(rs) do if need[role] then hit = true end end
            if not hit then return false, "role" end
        end
    end
    return true
end

-- 当前招人副本能列的散人（筛过、排好：点了「要」的职业在前，其余新挂的在前）
function S.Entries(d)
    if not S.On() then return {} end
    if S.stale and now() - (S.staleAt or 0) >= 1 then S.Read(false) end
    if not S.readAt or now() - S.readAt > S.KEEP then return {} end
    d = d or DC.RecDungeon()
    local out, cut = {}, {}
    for _, e in ipairs(S.all) do
        local okP, why = S.Pass(e, d)
        if okP then out[#out + 1] = e elseif why ~= "dg" then cut[why] = (cut[why] or 0) + 1 end
    end
    table.sort(out, function(x, y)
        local wx, wy = x.cls and DC.ClsPick(x.cls) == "want" or false, y.cls and DC.ClsPick(y.cls) == "want" or false
        if wx ~= wy then return wx end
        return x.t > y.t
    end)
    while #out > S.MAX_ROWS do table.remove(out) end
    S.cut = cut
    return out
end

-- ---------- 并进「来密我的人」 ----------
-- 密过我的那一行补上集合石读到的（他自己没说的才补）；不改存档里那张表，复制一份给界面
function S.Merge(p, e)
    local c = {}
    for k, v in pairs(p) do c[k] = v end
    c.lfg = e
    if rawget(p, "lv") == nil and e.lv then c.lv = e.lv end
    c.cls, c.clsName = p.cls or e.cls, p.clsName or e.clsName
    if not next(p.roles or {}) and next(e.roles or {}) then
        c.roles = {}
        for k, v in pairs(e.roles) do c.roles[k] = v end
    end
    return c
end
function S.Text(e)
    if e.comment then return e.comment end
    if e.title then return e.title end
    return L("在集合石单人求组", "Solo in Group Finder") .. (e.area and (L(" · 在", " - in ") .. e.area) or "")
end
-- 只挂了集合石的散人 → 「来密我的人」一行的样子（ch = 不从「说的话」里认等级）
function S.View(e)
    return { author = e.author, short = e.short, text = S.Text(e), t = e.t, roles = e.roles or {}, cls = e.cls, clsName = e.clsName,
        lv = e.lv, ch = L("集合石", "Group Finder"), lfg = e, lfgOnly = true }
end
-- DungeonChat 招人页调：密我的人（DC.PruneReplies）→ 合并后的整张表（密过我的在前，集合石散人接在后面）
function S.Rows(list)
    if not S.On() then return list end
    local d = DC.RecDungeon()
    local extra = S.Entries(d)
    if not S.readAt or now() - S.readAt > S.KEEP then return list end
    local by = {}
    for _, e in ipairs(S.all) do
        if d and e.dgs[d.n] and not S.hidden[e.short] and not by[e.short] then by[e.short] = e end
    end
    local out, used = {}, {}
    for _, p in ipairs(list) do
        local e = p.short and by[p.short]
        if e then out[#out + 1] = S.Merge(p, e) else out[#out + 1] = p end
        if p.short then used[p.short] = true end
    end
    for _, e in ipairs(extra) do
        if not used[e.short] then used[e.short] = true; out[#out + 1] = S.View(e) end
    end
    return out
end

-- 灰色小标签（「说的话」开头）
function S.Tag() return S.GRAY .. "[" .. L("集合石", "LFG") .. "]|r" end
-- 一行的单元格（DungeonChat.ReplyCells 之后调）
function S.Cells(p, cells)
    if not p.lfg then return cells end
    if p.lfgOnly and p.lfg.commentSecret then
        cells.txt = S.Tag() .. " " .. S.GRAY .. L("留言受保护（点行展开看）", "comment protected (click to expand)") .. "|r"
    else
        cells.txt = S.Tag() .. " " .. tostring(cells.txt or "")
    end
    return cells
end

local function agoText(t)
    local s = math.max(0, math.floor(now() - (t or now())))
    if s < 60 then return string.format(L("挂了 %d 秒", "listed %ds ago"), s) end
    if s < 3600 then return string.format(L("挂了 %d 分钟", "listed %dm ago"), math.floor(s / 60)) end
    return string.format(L("挂了 %d 小时", "listed %dh ago"), math.floor(s / 3600))
end

-- 「私聊」：第一次 = 发招呼（招人话术 + 必要时反问，带前缀规则）；招呼过 = 打开对他的私聊输入框
function S.GreetText(p)
    local base = DC.RecText and DC.RecText() or ""
    local ask = DC.AskText and DC.AskText(p)
    if ask and not DC.IsAutoText(base) then base = base .. " " .. ask end   -- 招人话术里已有「M我…」/ 11-19 英文 whisper me your…（话术本身走对外说话语言）
    return base
end
function S.Greeted(name)
    local t = S.greeted[short(name) or ""]
    return t and now() - t <= S.GREET_WIN or false
end
function S.Greet(p)
    if not (p and p.author) then return false end
    if S.Greeted(p.author) then return DC.Tell(p.author) end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return DC.Tell(p.author) end
    local text = (DC.Whisper or DC.Tagged)(S.GreetText(p), DC.MAX_BYTES)   -- 11-19 私聊不带标识
    local ok = pcall(send, text, "WHISPER", nil, p.author)
    if ok then
        S.greeted[p.short] = now()
        say(string.format(L("已密 %s：%s（他回话会进「来密我的人」）", "Whispered %s: %s (replies show in the list)"), p.short, text))
    end
    return ok
end

-- 每一行画完后调（所有行都调：复用的行先恢复成普通「来密」行的样子）
function S.Decorate(row, p)
    if not p.lfg then return end
    local e = p.lfg
    local tip = row.tip or {}
    local base = #tip
    local last = base > 0 and tip[base] or nil   -- 最后一行是「点一下展开 / 收起」，挪到最后
    if last then tip[base] = nil end
    tip[#tip + 1] = S.GRAY .. (p.lfgOnly and L("来源：集合石（按 I 的寻求组队）里单人挂单求组", "From Group Finder (I): solo listing")
        or L("他也在集合石（按 I 的寻求组队）里单人挂单求组", "Also listed solo in Group Finder (I)")) .. "|r"
    tip[#tip + 1] = S.GRAY .. agoText(e.t) .. (e.area and (L(" · 在", " - in ") .. e.area) or "") .. "|r"
    if e.comment and p.lfgOnly then
        -- 「说的话」那列已经是留言了
    elseif e.comment then
        tip[#tip + 1] = S.GRAY .. L("集合石留言：", "Listing note: ") .. e.comment .. "|r"
    elseif e.commentSecret then
        tip[#tip + 1] = S.GRAY .. L("集合石留言受保护：点行展开看原文", "Listing note is protected: click the row to see it") .. "|r"
    end
    if p.lfgOnly then
        tip[#tip + 1] = S.GRAY .. (S.Greeted(p.author) and L("「私聊」= 打开对他的私聊输入框（已招呼过）", "Whisper opens a whisper to them (already greeted)")
            or L("「私聊」= 密他一句招人话术（带标识规则同喊话）；之后再点打开私聊输入框", "Whisper sends your recruit line once; later clicks open a whisper")) .. "|r"
        row.w:SetScript("OnClick", function() S.Greet(p); DC.Render() end)
    end
    if last then tip[#tip + 1] = last end
    row.tip = tip
    -- 保密的留言：展开时单独塞进那个文字框（只显示，不拼接、不解析）
    if e.commentSecret and rawget(row, "open") and row.full then
        pcall(row.full.SetText, row.full, e.commentSecret)
    end
end

-- 行尾「×」/ 表头「清空」：本次登录不再列（集合石的人不进存档）
function S.Hide(s) if s then S.hidden[s] = true end end
function S.HideAll()
    for _, e in ipairs(S.all) do S.hidden[e.short] = true end
end

-- ---------- 搜索 ----------
local BLIZZ = { "LFGParentFrame", "LFGBrowseFrame", "LFGListFrame", "PVEFrame" }
function S.BlizzOpen()
    for _, n in ipairs(BLIZZ) do
        local f = rawget(_G, n)
        if type(f) == "table" and f.IsVisible then
            local ok, v = pcall(f.IsVisible, f)
            if ok and v == true then return true end
        end
    end
    return false
end
local function inCombat()
    if not InCombatLockdown then return false end
    local ok, v = pcall(InCombatLockdown)
    return ok and clean(v) and true or false
end
-- click = 玩家点击里调（打开招人页 / 刷新 / 打开开关）
function S.Search(click)
    if not S.On() then return false, "off" end
    local f = fn("Search")
    if not f then
        S.last = L("这个客户端没有集合石接口", "This client has no Group Finder API")
        probe("api", "noSearch")
        return false, "noapi"
    end
    if S.BlizzOpen() then return false, "blizz" end   -- 暴雪集合石窗口开着：不抢它的搜索，读它的结果
    if not click and inCombat() then return false, "combat" end
    local t = now()
    -- 求组页的集合石扫描（LfgListScan，HOLD）刚搜过：结果共用，不重复搜
    local LS = ns.LfgListScan
    local other = type(LS) == "table" and tonumber(rawget(LS, "searchAt")) or nil
    if not click and other and t - other < S.INTERVAL then
        S.searchAt = math.max(S.searchAt or other, other)
        return false, "shared"
    end
    if click and S.searchAt and t - S.searchAt < S.CLICK_GAP then return false, "gap" end
    S.tryAt, S.pending, S.byClick = t, true, click and true or false
    local ok, err = pcall(f, S.CAT)
    S.searchAt = t
    S.searches = (S.searches or 0) + 1
    if not ok then
        S.pending = nil
        S.last = L("集合石搜索失败：", "Group Finder search failed: ") .. tostring(err):sub(1, 80)
        probe("searchErr", tostring(err):sub(1, 120))
        return false, "err"
    end
    if click then S.needClick = nil end
    return true
end

local function visible(f)
    if not f then return false end
    local v = f.IsVisible and f:IsVisible()
    if v == nil then v = f.IsShown and f:IsShown() end
    return v and true or false
end
-- 招人页每次重画时调（开着时每 5 秒重画一次）：页面真看得见、到点了才自动搜
function S.Tick()
    if not S.On() or S.needClick then return false end
    local P = DC.panel
    if not (P and DC.view == "recruit" and visible(P) and visible(P.rec)) then return false end
    if S.searchAt and now() - S.searchAt < S.INTERVAL then return false end
    return S.Search(false)
end

-- ---------- 事件 ----------
local ev = CreateFrame("Frame")
S._ev = ev
local function mineAddon(a1) return tostring(a1 or ""):find("GearInsight_Forever", 1, true) ~= nil end
local function refresh()
    if DC.panel and DC.panel.IsShown and DC.panel:IsShown() and DC.view == "recruit" then DC.dirty = false; pcall(DC.Render) end
end
-- 招呼过的人回话：不在喊话 15 分钟窗口里也收进「来密我的人」（在窗口里 DungeonChat 自己会收，这里不管）
function S.OnWhisper(msg, author, guid)
    author = clean(author)
    if not author or not S.Greeted(author) or not DC.OnWhisper then return false end
    if DC.InReplyWin and DC.InReplyWin() then return false end
    local saved = rawget(DC, "lastShout")
    rawset(DC, "lastShout", now())
    local ok, r = pcall(DC.OnWhisper, msg, author, guid)
    rawset(DC, "lastShout", saved)
    if ok and r then refresh() end
    return ok and r or false
end
ev:SetScript("OnEvent", function(_, e, a1, a2, ...)
    if e == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        local mine = S.pending
        S.pending = nil
        if S.On() and S.Read(mine) then refresh() end
    elseif e == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        -- 一次搜索会连着来几十个：只记脏，下次重画时重读
        if not S.stale then S.stale, S.staleAt = true, now() end
    elseif e == "LFG_LIST_SEARCH_FAILED" then
        if S.pending then
            S.pending = nil
            S.last = L("集合石搜索失败：", "Group Finder search failed: ") .. tostring(clean(a1) or "?")
            probe("searchFailed", tostring(clean(a1) or "?"))
        end
    elseif e == "CHAT_MSG_WHISPER" then
        pcall(S.OnWhisper, a1, a2, select(10, ...))   -- 第 12 个参数 = GUID
    elseif e == "ADDON_ACTION_BLOCKED" or e == "ADDON_ACTION_FORBIDDEN" then
        if not mineAddon(a1) then return end
        if S.tryAt and now() - S.tryAt < 3 and not S.byClick then
            S.needClick = true          -- 计时器里搜被拦：以后只在点「刷新」时搜
            S.pending = nil
            S.last = L("集合石自动刷新被游戏拦下了，点「刷新」手动刷", "Auto refresh was blocked; click Refresh")
            probe("timerBlocked", tostring(clean(a2) or "?"))
        end
    end
end)
for _, e in ipairs({ "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_RESULT_UPDATED", "LFG_LIST_SEARCH_FAILED",
    "CHAT_MSG_WHISPER", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do pcall(ev.RegisterEvent, ev, e) end
S._event = ev:GetScript("OnEvent")   -- 测试用

-- ---------- 状态 / 探针 ----------
-- 一行状态：SOLO=api:有没有接口 / 搜了几次 / 被拦没 / 结果总数 / 地下城几条 / 散人几个 / 跳过原因
function S.ProbeLine()
    local why = {}
    for k, v in pairs(S.why or {}) do why[#why + 1] = k .. v end
    table.sort(why)
    local vias = {}
    for _, e in ipairs(S.all or {}) do if e.via then vias[e.via] = true end end
    local vl = {}
    for k in pairs(vias) do vl[#vl + 1] = k end
    table.sort(vl)
    return "SOLO=api:" .. (fn("Search") and "ok" or "none") .. "/on:" .. tostring(S.On()) .. "/search:" .. tostring(S.searches or 0)
        .. "/needClick:" .. tostring(S.needClick and true or false) .. "/res:" .. tostring(S.total or "-") .. "/dg:" .. tostring(S.dg or "-")
        .. "/solo:" .. tostring(#(S.all or {})) .. "/why:" .. table.concat(why, ".") .. "/via:" .. table.concat(vl, ".")
end
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.lfgsolo = function() say(S.ProbeLine()) end

-- 「集合石散人」按钮的鼠标提示后半句（状态）
function S.Note()
    if not S.On() then return L("关着：不搜、不列", "Off") end
    if S.last and (S.needClick or not S.readAt) then return S.last end
    if not fn("Search") then return L("这个客户端没有集合石接口", "No Group Finder API") end
    if S.BlizzOpen() then return L("暴雪集合石窗口开着，读它的结果", "Reading the open Group Finder window") end
    if not S.readAt then return L("还没搜到结果", "No results yet") end
    local d = DC.RecDungeon()
    local n = #S.Entries(d)
    local s = string.format(L("上次 %d 秒前：集合石 %d 条，%s 单人 %d 个合你的设置", "%ds ago: %d listings; %s: %d solo fit"),
        math.floor(now() - S.readAt), S.total or 0, d and d.n or "?", n)
    local cut = 0
    for _, v in pairs(S.cut or {}) do cut = cut + v end
    if cut > 0 then s = s .. string.format(L("（筛掉 %d 个：等级 / 职责 / 职业不合）", " (%d filtered by level / role / class)"), cut) end
    return s
end

-- ---------- 招人页上的开关（DungeonChat renderRecruit 调；R = 招人页）----------
local function sel(b, on) if ns.SegSelect and rawget(b, "_segFs") then ns.SegSelect(b, on) end end
local EMPTY_HINT = { "；集合石里单人求组、合你设置的散人也会列在这里，开头标灰色「[集合石]」", "; solo Group Finder listings that fit show here too, tagged [LFG]" }
function S.EmptyHint() return S.On() and L(EMPTY_HINT[1], EMPTY_HINT[2]) or "" end
function S.Place(R)
    local LR = rawget(R, "lower") or R
    local tg = rawget(R, "lfgSoloBtn")
    if not tg then
        tg = (ns.SegButton or ns.Button)(LR, L("集合石散人", "LFG solos"), 72, 22, function()
            S.Toggle()
            if S.On() then S.Search(true) end
            DC.Render()
        end)
        tg:SetPoint("TOPRIGHT", -40, -24)
        tg:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L("读取集合石散人", "Read Group Finder solos"), 1, 0.82, 0)
            GameTooltip:AddLine(L("开着时，招人页每 45 秒搜一次集合石（按 I 的寻求组队），把单人挂单求组、挂了这个副本的人列进下面「来密我的人」，开头标灰色「[集合石]」；按上面的等级范围、需要的职责、职业「不要」筛。同一个人密过你又挂了集合石，合成一行。",
                "When on, searches Group Finder every 45s and lists solo players listed for this dungeon below, tagged [LFG], filtered by your level range, needed roles and unwanted classes."), 1, 1, 1, true)
            GameTooltip:AddLine(S.Note(), 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        tg:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rawset(R, "lfgSoloBtn", tg)
        local rf = ns.Button(LR, L("刷新", "Refresh"), 36, 22, function() S.Search(true); DC.Render() end)
        rf:SetPoint("LEFT", tg, "RIGHT", 4, 0)
        rf:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L("马上搜一次集合石", "Search Group Finder now"), 1, 0.82, 0)
            GameTooltip:AddLine(S.Note(), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        rf:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rawset(R, "lfgSoloRefresh", rf)
    end
    sel(tg, S.On())
    local rf = rawget(R, "lfgSoloRefresh")
    if rf then rf:SetShown(S.On()) end
    -- 空态那句「集合石散人也会列在这里」改由 DungeonChat.lua 渲染时接上（S.EmptyHint），这里再改会被筛选那段的空态覆盖 / 重复拼
    S.Tick()
end
