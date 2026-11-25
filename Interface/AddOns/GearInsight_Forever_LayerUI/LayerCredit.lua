-- 位面「互助额度」（11-21 用户「增加位面切换概率，是不是帮助别人才能获得 额度」「然后gearinsight工会的，可以不受这个限制」，HOLD）
--   规则（数值依据见下面常量注释）：
--   · 向「公会外」（同图公共频道）的人求换层要额度；本公会内互相拉不要、不扣；GearInsight 公会成员不要、不扣（LY.InGIGuild，同 1.3.0「Gearinsight 公会位面三项默认开」）
--   · 每人每天送 FREE 次（11-21 用户「不送」→ 0；11-22「每天」送 1）；帮别人拉成一次（对方回执「到了」）+1，攒下的最多 MAX 次，IDLE（3 天）没动就清空
--   · 只在真被「公会外的人」拉过去时才扣 1（先扣当天赠送的，再扣攒下的）；没人拉 / 被公会会员拉 = 不扣
--   · 额度用完：「我想换一层」自动改成只找公会会员（不在公会 = 不发，说清楚怎么攒）；公会外玩家那块的「过去」灰掉写原因
--   · 「增加切换概率」：求助消息带上自己累计帮过几次（hn），帮手弹框写「他帮过别人 N 次」、正弹着的帮得多的不被后来的顶掉（主插件 LayerHop.lua）；
--     自己帮得多，一轮自动换人最多请的人数从 3 位加到 4 / 5 位（LH.CHAIN_MAX）
--   ⛔ 隐私：只存自己的计数（存档 layer.cr = { d 日期, u 今天用了几次赠送, b 攒下的, n 累计帮过 }），不存别人的档、不收集额外数据；hn 是客户端自报，不做反作弊
--   ⛔ 主插件只留最小钩子：LayerHop.lua 的 LH.gOnly（只发公会）、D 回执里 +1、R 里读 hn、弹框显示 / 优先；PageLayer.lua 的 okMsg / askWho 两处。
--     这个文件 HOLD 剔掉时：没人设 gOnly、R 不带 hn → 钩子全不生效，只剩存档里一个帮人计数在涨（攒着，上线这功能时直接能用）
local _, ns = ...; ns = _G.GearInsightForever or ns
local LY, LH = ns.Layer, ns.LayerHop
if not (LY and LH) then return end
local LC = {}
ns.LayerCredit = LC
local function L(cn, en) return ns.L(cn, en) end
local function now() return (GetTime and GetTime()) or 0 end

LC.FREE = 3       -- 每天送几次：11-21 用户「不送」→ 0；11-22「每天」送 1；11-23 用户「默认次数没有，也就没有帮忙的机会」「每天给3次默认」→ 3（当天不用不攒，先扣赠送再扣攒下的）
-- 11-23 用户「但是强提醒，只有帮了才能积累额度」：卡片第二行橙字写在最前；每用掉一次屏幕中间橙字提醒 + 聊天框一句
LC.MAX = 5        -- 攒下的上限：11-21 用户「最多攒5次，3天不用清空」（原定 10）
LC.IDLE = 3 * 86400   -- 攒下的额度 3 天没动（没帮人也没用掉）就清空
LC.BASE_CHAIN = 3 -- 和 LayerHop.lua LH.CHAIN_MAX 原值一样
LC.CHAIN = { { 20, 5 }, { 5, 4 } }   -- 累计帮过 ≥20 次：一轮最多请 5 位；≥5 次：4 位（每多一位最多多等 30 秒，也多打扰一个人 → 用帮人换）

local function today() return (date and date("%Y-%m-%d")) or "?" end
-- 自己的计数（跨天清零当天用掉的赠送；攒下的夹到上限）
function LC.State()
    local d = LY.DB()
    local c = type(d.cr) == "table" and d.cr or {}
    d.cr = c
    local td = today()
    if c.d ~= td then c.d, c.u = td, 0 end
    c.u = tonumber(c.u) or 0
    c.b = math.max(0, math.min(LC.MAX, tonumber(c.b) or 0))
    c.n = math.max(0, tonumber(c.n) or 0)
    -- 3 天不用清空：攒下的 / 累计帮过 有变化（帮人 +1 在主插件 LayerHop.lua 里加，这里看到变化才记时间，只会算得更宽）就重新计时
    local t = (time and time()) or 0
    if c.lb ~= c.b or c.ln ~= c.n or not c.t then c.t, c.lb, c.ln = t, c.b, c.n end
    if c.b > 0 and t - c.t >= LC.IDLE then c.b, c.lb, c.t = 0, 0, t end
    return c
end
-- 还剩几次（赠送剩余 + 攒下的）, 赠送剩余, 攒下的, 累计帮过
function LC.Left()
    local c = LC.State()
    local free = math.max(0, LC.FREE - c.u)
    return free + c.b, free, c.b, c.n
end
-- GearInsight 公会成员：不扣、不限（公会名还没读到 = 先按普通人算）
-- 11-21 用户「我想测试下别的工会的互助次数」：/run GearInsightForever.db.layer.asOther=true 假装不在 Gearinsight 公会（=nil 恢复）
function LC.Unlimited()
    if ns.db and ns.db.layer and ns.db.layer.asOther then return false end
    return LY.InGIGuild and LY.InGIGuild() == true or false
end
-- 公会外的额度用完了（GearInsight 公会成员永远 false）
function LC.Blocked() return not LC.Unlimited() and LC.Left() <= 0 end
function LC.ChainMax()
    local n = LC.State().n
    for _, r in ipairs(LC.CHAIN) do if n >= r[1] then return r[2] end end
    return LC.BASE_CHAIN
end
local function syncChain() LH.CHAIN_MAX = LC.ChainMax() end

-- 拉我的人是不是本公会的（公会名单会阶 / 公会心跳还新鲜）
function LC.IsGuildmate(who)
    if type(who) ~= "string" or (ns.Secret and ns.Secret(who)) or who == "" then return false end
    local s = LY.Short(who)
    local LG = ns.LayerGuild
    if LG and type(LG.ranks) == "table" then
        if LG.ranks[s] ~= nil then return true end
        for k in pairs(LG.ranks) do if LH.SameName(k, s) then return true end end
    end
    local pe = LH.PeerByName(s)
    local g = pe and pe.via and pe.via.guild
    return (g and now() - g <= LY.EXPIRE) and true or false
end

-- 扣 1：先扣当天赠送的，再扣攒下的
function LC.Spend()
    if LC.Unlimited() then return false end
    local c = LC.State()
    if c.u < LC.FREE then c.u = c.u + 1; return "u" end   -- 11-23 返回扣的是哪种（赠送 u / 攒下的 b），回弹时原样退
    if c.b > 0 then c.b = c.b - 1; return "b" end
    return false
end
-- 11-23 用户「同意」：帮手拉了却没换成（回弹）不扣额度 → 主插件 LayerHop.lua undo 调：这一轮扣过就原样退回（扣的赠送退赠送、扣的攒下的退攒下的）
LH.OnUndo = function(who)
    local l = LC.last
    if not (l and l.k and LH.SameName(l.who, who) and now() - l.t < 900) then return end
    local c = LC.State()
    if l.k == "u" then c.u = math.max(0, c.u - 1) else c.b = math.min(LC.MAX, c.b + 1) end
    LC.last = nil
    ns.Print(L("刚才没换成：退回 1 次公会外额度", "Move didn't stick - credit refunded"))
end

function LC.Text(kind)
    local left, free, bank = LC.Left()
    if kind == "gonly" then
        return L("没有公会外换层额度：这次只向公会会员求助（公会内互拉不扣额度）。想找公会外的人：先帮别人拉一次 +1",
            "No out-of-guild layer credits: asked guildmates only this time. Help someone move first (+1) to ask outside your guild")
    elseif kind == "none" then
        return L("没有公会外换层额度，你又没在公会里，这次没发求助。办法：① 去帮别人：位面页勾着「我愿意帮…换层」，别人求你时点「邀请」，拉成一次 +1；② 加入公会，公会内互拉不限",
            "No out-of-guild layer credits and you're not in a guild - nothing sent. Help someone move (+1) or join a guild (guildmates are free)")
    elseif kind == "card" then
        return L("没有公会外换层额度：这块是公会外的玩家，要额度才能请。帮别人拉一次 +1（别人求你时点「邀请」）；上面公会会员那块不扣额度",
            "No out-of-guild credits: these players aren't in your guild. Help someone move (+1); guildmates above are free")
    elseif kind == "spent" then
        return string.format(L("用掉 1 次公会外额度，还剩 %d 次；只有帮别人才能攒（帮拉成一次 +1）", "Used 1 credit (%d left) - only helping others earns more"), left)
    end
    return ""
end

-- ---------- 包住 LayerHop 的几个入口（只包我们自己的函数表字段，不碰暴雪全局）----------
-- 「我想换一层」/「换过去」：同时发公会 + 同图公共频道。公共频道关着 = 本来就只找公会，不要额度
-- 原样返回（返回值个数不变）；成功就把这一轮记成「发过公会外」，要是被公会外的人拉过去，收尾时扣 1（LH.Finish）
local function tag(ok, ...)
    if ok and LH.round then LH.round.cr = true end
    return ok, ...
end
LH._crReq0 = LH._crReq0 or LH.Request
LH.Request = function(z)
    syncChain()
    local d = LY.DB()
    if not (d.pub and d.on) or LC.Unlimited() then return LH._crReq0(z) end
    if LC.Left() > 0 then return tag(LH._crReq0(z)) end
    if IsInGuild and IsInGuild() then
        LH.gOnly = true
        local ok, why, txt = LH._crReq0(z)
        LH.gOnly = nil
        if ok then return true, nil, LC.Text("gonly") end
        return ok, why, txt
    end
    return false, "nocredit", LC.Text("none")
end
-- 「过去」：公会外玩家那块（LayerPub.lua，名单带 byRecent 标记）要额度；公会会员那块 / 别的图的公会会员不要
LH._crAsk0 = LH._crAsk0 or LH.AskChain
LH.AskChain = function(list, far, z)
    syncChain()
    local pub = (type(list) == "table" and rawget(list, "byRecent")) or (type(far) == "table" and rawget(far, "byRecent"))
    if not pub or LC.Unlimited() then return LH._crAsk0(list, far, z) end
    if LC.Left() <= 0 then return nil, "nocredit", LC.Text("card") end
    return tag(LH._crAsk0(list, far, z))
end
-- 一轮换好了（主插件 receipt / 手动接了邀请都走这里，一轮只一次）：这轮发过公会外、拉我的人不是本公会的 → 扣 1
LH._crFin0 = LH._crFin0 or LH.Finish
LH.Finish = function(ok, who)
    local r = LH.round
    local k = ok and r and not r.done and r.cr and not LC.IsGuildmate(who) and LC.Spend()
    if k then
        local text = LC.Text("spent")
        ns.Print(text)
        if UIErrorsFrame and UIErrorsFrame.AddMessage then pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, text, 1, 0.6, 0.2) end   -- 11-23 强提醒
        LC.last = { t = now(), who = who, k = k }
    end
    return LH._crFin0(ok, who)
end
-- 求助消息 R 带上自己累计帮过几次（hn，帮手弹框显示 / 优先；老版本帮手不认这个字段，忽略）
LY._crEnc0 = LY._crEnc0 or LY.Encode
LY.Encode = function(kind, t)
    if kind == "R" and type(t) == "table" and t.hn == nil then t.hn = math.min(999, LC.State().n) end
    return LY._crEnc0(kind, t)
end

-- ---------- 11-22 换层成功率统计（计数在主插件 Layer.lua 的 LY.Stat，存档 layer.st[日期]，只留 14 天）----------
--   求助方 r 发出求助 / i 有人拉（进了帮手的队）/ o 换成 / f 没换成 / t 没人邀请 / u 进队后确认不了 / b 换成后读回原层（11-23 回弹）；帮手 p 弹框 / a 自动拉 / c 手动拉 / k 对方回执到了
local SK = "riofutbpack"
-- 近 days 天（含今天）各键合计；days = nil → 存档里留着的全部（最多 14 天）
function LC.Sum(days)
    local st, s = LY.DB().st, {}
    local cut = days and date("%Y-%m-%d", time() - (days - 1) * 86400) or ""
    for c in SK:gmatch(".") do s[c] = 0 end
    for d, b in pairs(type(st) == "table" and st or {}) do
        if type(b) == "table" and d >= cut then for c in SK:gmatch(".") do s[c] = s[c] + (tonumber(b[c]) or 0) end end
    end
    return s
end
-- 「近 7 天换层：求助 N 次 · 有人拉 M 次 · 换成 K 次（成功率 X%）」；成功率 = 换成 / 求助，没求助过不写百分比
function LC.StatLine(s, head)
    return string.format(L("%s换层：求助 %d 次 · 有人拉 %d 次 · 换成 %d 次", "%s layer moves: asked %d - pulled %d - moved %d"), head or L("近 7 天", "Last 7 days"), s.r, s.i, s.o)
        .. (s.r > 0 and string.format(L("（成功率 %d%%）", " (%d%% success)"), math.floor(s.o * 100 / s.r + 0.5)) or "")
end
function LC.StatTip(s, head)
    return LC.StatLine(s, head) .. "\n"
        .. string.format(L("没换成的：没人邀请 %d · 进队了没换成 %d · 确认不了 %d · 回弹 %d", "Failed: no invite %d - same layer %d - unconfirmed %d - bounced %d"), s.t, s.f, s.u, s.b) .. "\n"
        .. string.format(L("我帮别人：弹框 %d 次 · 拉人 %d 次（自动 %d · 手动 %d）· 对方确认到了 %d 次", "Helping: prompts %d - invites %d (auto %d/manual %d) - arrived %d"), s.p, s.a + s.c, s.a, s.c, s.k)
end
-- /gi layer stat：近 7 天 + 存档里全部（最多 14 天）
function ns.LayerStatText()
    return LC.StatTip(LC.Sum(7)) .. "\n" .. LC.StatTip(LC.Sum(), L("近 14 天（存档只留 14 天）", "Last 14 days"))
end
-- /gi layer 帮助（11-22 从主插件 Layer.lua 搬来省登录内存）+ /gi layer stat
function ns.LayerSlash(sub)
    if sub == "stat" then return ns.Print(ns.LayerStatText()) end
    if sub == "pub" then local a, b = LC.Pub(); return ns.Print(a .. "\n" .. b) end
    -- 文字里写死 /gi，打印时换成实际的命令前缀（少一串拼接；繁体表也能按整句查到）
    local C = (ns.SlashHint or "/gi"):gsub("%%", "%%%%")
    for _, t in ipairs({
        L("位面：/gi layer 打开面板 · /gi layer lead 口令（会长：开服当晚还没公会时建集合频道）· /gi layer join 口令（会员加入）· /gi layer leave · /gi layer helper on|off 帮别人换层 · /gi layer pub on|off 按地图的公共频道 · /gi layer stat 换层成功率 · /gi layerprobe 开服探针",
            "Layers: /gi layer panel · /gi layer lead CODE · /gi layer join CODE · /gi layer leave · /gi layer helper on|off · /gi layer pub on|off · /gi layer stat · /gi layerprobe"),
        -- 11-13 玩家「哪里关😳」：三个自动行为单独一行列清楚（右侧「位面」页签 → 设置 里也能勾）
        L("位面自动行为（第一次碰到时会问你一次）：/gi layer autohelp on|off 会员求助自动拉 · /gi layer accept on|off 会长 / 官员邀请自动接受 · /gi layer autoleave on|off 换过去后自动退队 · /gi layer auto on|off 三个一起；右侧『位面』页签 → 设置里也能改",
            "Layer automation (asked once the first time): /gi layer autohelp on|off · /gi layer accept on|off · /gi layer autoleave on|off · /gi layer auto on|off (all three); also in the Layers tab -> Settings"),
    }) do ns.Print((t:gsub("/gi", C))) end
end

-- 11-23 用户截图冬泉谷「同图其他玩家 0 人」：/gi layer pub（不带 on/off）打印公共频道诊断；位面页 0 人时那行也带第一句（LayerPub.lua LP.EmptyText）
--   备用名换的时间在 LY.pubAlt[-地图]、收到的公共频道心跳条数在 LY.pubAlt.rx（主插件 Layer.lua，不给 LY 加字段）
-- 返回 第一行（频道名 + 已加入几号 / 未加入的原因）, 第二行（备用名 · 收到几条心跳 · 本图几人）
function LC.Pub()
    local w, a, m, t, n = LY.PubChannel(), LY.pubAlt, LY.Mine(), now(), 0
    for _, pe in pairs(LY.peers) do if pe.via.pub and t - pe.via.pub <= LY.EXPIRE and pe.m == m then n = n + 1 end end
    local id, r, i = w and LY.ChanIndex(w), (not LY.DB().pub and 1) or (not LY.ChanReady() and 2) or (not LY.ChanRoom() and 3) or 4, 0
    for x in L("开关关着|刚上线 30 秒内|聊天频道满了|等服务器回话 / 换图 5 秒后再加", "off|just logged in|channels full|waiting"):gmatch("[^|]+") do i = i + 1; if i == r then r = x end end
    return string.format(L("频道 %s：%s", "Channel %s: %s"), tostring(w), id and string.format(L("已加入（%d 号）", "joined (#%d)"), id) or (L("未加入 · ", "not joined - ") .. r)),
        string.format(L("备用名 x%d · 本次登录收到公共频道心跳 %d 条 · 本图近期 %d 人", "alt x%d - %d heartbeats - %d players here"), m and a[m] or 0, a.rx or 0, n)
end

-- ---------- 位面页：「我想换一层」下面一行额度说明（鼠标悬停看完整规则）----------
-- 11-21 用户「UI，更明显点」：原来两行小字没底色、第二行折行压到下面标题 → 改成带边框的卡片 + 右侧大号剩余次数，块高按三行留足
-- 11-22 卡片里第二块再加一行「近 7 天换层」成功率（细分在鼠标提示里），卡片高 58 → 72、块高 66 → 80
-- 11-22 用户截图「优化UI」：加了成功率一行后左边 4 行字（72 高）压出下边框、压到右下「公会外还能换」→ 加高到 88，
--   右侧改成独立一栏（竖线隔开）：大号次数 + 下面一行小字，都按卡片竖直居中；左边字宽让出这一栏
-- 11-22 用户又截图「UI优化」：「怎么攒」一行太长自动折成两行，成功率那行又压出下边框 → 关掉自动折行（只按 \n 分行），
--   左边固定 1 + 3 行，每行文字缩短到一行装得下
-- 11-22 用户再截图「字多，还错位，不用都展示」：关了折行后 \n 也不换行，后两行被吞、框里空一大块 → 卡片只留两行
--   （剩几次 / 怎么攒），成功率和帮过几次只放鼠标提示；卡片 88 → 56 高
local CARD_W, BOX_H, BOX_IN, COL_W = 596, 64, 56, 118
local BD = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }
function LC.Tip()
    local _, free, bank, n = LC.Left()
    return table.concat({
        L("互助额度：帮别人换层攒，向公会外的人求换层用", "Help credits: earn by helping, spend outside your guild"),
        string.format(L("· 帮别人拉成一次 +1（别人求你时点「邀请」，或公会会员求助自动拉），最多攒 %d 次，现在 %d；3 天没帮人也没用就清空", "- +1 per pull (max %d, now %d); cleared after 3 idle days"), LC.MAX, bank),
        L("· 只在真被公会外的人拉过去时扣 1；没人拉、被公会会员拉都不扣", "- Charged only when a non-guildie moves you"),
        L("· 本公会内互相拉：不限、不扣", "- Guildmates: unlimited, free"),
        string.format(L("· 你累计帮过别人 %d 次：求助时对方会看到；帮过 5 次一轮自动换人最多请 4 位，20 次 5 位（现在 %d 位）", "- You've helped %d times (shown to helpers); 5+ = up to 4 asks per round, 20+ = 5 (now %d)"), n, LC.ChainMax()),
        L("· 没有额度时：「我想换一层」只找公会会员", "- Out of credits: \"Switch layer\" asks guildmates only"),
        "", LC.StatTip(LC.Sum(7)),   -- 11-22 换层成功率细分（卡片上不再写，只在这里）
    }, "\n")
end
-- 插一行到「我想换一层」和「XX 的位面」标题之间：标题和公会卡片整体下移 BOX_H（PageLayer.lua 每次刷新从 p.cardsY 往下排）
function LC.Mount(p)
    if not p or rawget(p, "crBox") or not (p.body and p.gHd and p.cardsY) then return end
    local y = p.cardsY + 20   -- PageLayer.lua：gHd 在 y，cardsY = y - 20
    local f = CreateFrame("Frame", nil, p.body, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(CARD_W, BOX_IN)
    f:SetPoint("TOPLEFT", p.body, "TOPLEFT", 12, y + 2)
    if f.SetBackdrop then pcall(f.SetBackdrop, f, BD) end
    f.bar = f:CreateTexture(nil, "ARTWORK"); f.bar:SetPoint("TOPLEFT", 1, -1); f.bar:SetPoint("BOTTOMLEFT", 1, 1); f.bar:SetWidth(4)
    local tw = CARD_W - COL_W - 24
    f.a = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); f.a:SetPoint("TOPLEFT", 14, -9); f.a:SetWidth(tw); f.a:SetJustifyH("LEFT")
    f.a:SetWordWrap(false)
    f.b = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.b:SetPoint("TOPLEFT", 14, -32); f.b:SetWidth(tw); f.b:SetJustifyH("LEFT")
    f.b:SetWordWrap(false)
    f.sep = f:CreateTexture(nil, "ARTWORK"); f.sep:SetWidth(1); f.sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -COL_W, -10); f.sep:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -COL_W, 10)
    local cx = -COL_W / 2   -- 右栏中线（相对卡片右边）
    f.n = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge"); f.n:SetPoint("CENTER", f, "RIGHT", cx - 8, 7); f.n:SetJustifyH("CENTER")
    f.u = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.u:SetPoint("BOTTOMLEFT", f.n, "BOTTOMRIGHT", 3, 2)
    f.h = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.h:SetPoint("TOP", f, "RIGHT", cx, -5); f.h:SetWidth(COL_W - 8); f.h:SetJustifyH("CENTER")
    if f.EnableMouse then f:EnableMouse(true) end
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(LC.Tip(), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.crBox = f
    p.gHd:ClearAllPoints(); p.gHd:SetPoint("TOPLEFT", p.body, "TOPLEFT", 12, y - BOX_H)
    p.cardsY = p.cardsY - BOX_H
end
-- 三行字（各一行、不折行）：今天还剩几次 / 怎么攒 / 帮过几次（LayerPub.lua 的 LP.Refresh 每次刷新调）
function LC.Lines()
    if LC.Unlimited() then
        return "|cff33ff66" .. L("互助额度：你在 Gearinsight 公会，换层不限次数、不扣额度", "Help credits: Gearinsight guild member - unlimited") .. "|r",
            string.format(L("你累计帮过别人 %d 次（求助时对方会看到）· 帮别人拉一次照样记一笔", "You've helped others %d times (shown when you ask)"), LC.State().n)
    end
    local left, free, bank, n = LC.Left()
    local a
    if left > 0 then
        a = string.format(L("公会外换层额度：还剩 |cffffd100%d|r 次（每天送 %d 次 · 最多攒 %d 次）", "Out-of-guild layer credits: |cffffd100%d|r left (%d free daily - max %d)"), left, LC.FREE, LC.MAX)
    else
        a = "|cffff7766" .. string.format(L("公会外换层额度用完了：只找公会会员，明天再送 %d 次", "No credits: guild only, %d more tomorrow"), LC.FREE) .. "|r"
    end
    return a, L("|cffffaa33只有帮别人才能攒额度：帮拉成一次 +1|r · 每天送的当天不攒 · 指这里看规则", "|cffffaa33Only helping earns credits: +1 per pull|r - hover for rules")
end
function LC.Paint(p)
    if not p then return end
    LC.Mount(p)
    local f = rawget(p, "crBox")
    if not f then return end
    syncChain()
    local d = LY.DB()
    if not d.on then f:Hide(); return end
    local a, b = LC.Lines()
    f.a:SetText(ns.EnSafe and ns.EnSafe(a) or a)
    f.b:SetText(ns.EnSafe and ns.EnSafe(b) or b)
    -- 右侧大号：剩几次（不限 = 绿，用完 = 红，其余金色）；左边竖条 / 边框同色
    local col, num, unit
    if LC.Unlimited() then col, num, unit = { 0.2, 1, 0.4 }, L("不限", "∞"), ""
    else
        local left = LC.Left()
        col = left > 0 and { 1, 0.82, 0 } or { 1, 0.4, 0.35 }
        num, unit = tostring(left), L("次", "left")
    end
    f.n:SetText(num); f.n:SetTextColor(col[1], col[2], col[3]); f.u:SetText(unit)
    f.h:SetText(L("公会外还能换", "outside guild"))
    f.bar:SetColorTexture(col[1], col[2], col[3], 1)
    f.sep:SetColorTexture(col[1], col[2], col[3], 0.35)
    if f.SetBackdropColor then
        f:SetBackdropColor(col[1] * 0.14, col[2] * 0.14, col[3] * 0.14, 0.92); f:SetBackdropBorderColor(col[1], col[2], col[3], 0.75)
    end
    f:Show()
end

-- 11-23 用户「原则上一个人，在2小时内，只请求一个人邀请一次」：LayerHop 的 askedAt（我请过谁）/ askedBy（谁点名过我）只在内存里，
--   /reload 就清零 → 存进存档 layer.ask = { a = {名字 = 墙钟秒}, b = {…} }，加载时还原、退出 / reload 时写回；过了 REASK 的丢掉
function LC.AskRestore()
    local d = LY.DB(); local s = d.ask
    if type(s) ~= "table" then return end
    local tw, tn = time(), now()
    for k, tb in pairs({ a = LH.askedAt, b = LH.askedBy }) do
        for name, w in pairs(type(s[k]) == "table" and s[k] or {}) do
            local ago = tw - w
            if ago >= 0 and ago < LH.REASK and (tb[name] or -1e9) < tn - ago then tb[name] = tn - ago end
        end
    end
end
function LC.AskSave()
    local d = LY.DB(); local tw, tn = time(), now()
    local s = { a = {}, b = {} }
    for k, tb in pairs({ a = LH.askedAt, b = LH.askedBy }) do
        for name, t in pairs(tb) do if tn - t < LH.REASK then s[k][name] = math.floor(tw - (tn - t)) end end
    end
    d.ask = (next(s.a) or next(s.b)) and s or nil
end
pcall(LC.AskRestore)
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGOUT")
    f:SetScript("OnEvent", function() pcall(LC.AskSave) end)
end

-- 子插件是位面页第一次刷新时才加载的（PageLayer.lua refreshView 开头）：这时页面已建好、公会卡片还没排 → 现在就插行，这一次刷新就排对
do
    local LG = ns.LayerGuild
    if LG and LG.page then pcall(LC.Mount, LG.page) end
end
