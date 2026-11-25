-- 「位面」页 · 同图其他玩家（公共频道）（11-19 用户「加，同图其他玩家也列出来」→「分开列出」）
--   公会那块（PageLayer.lua）下面单独一块：同一张图、通过公共频道 GIFM<地图ID> 报过心跳、不是本公会的插件用户，按层分组。
--   · 「第 N 层」= LY.LayerNo（公会那块同一套编号；公共频道的人报的层码收心跳时已 LY.Remember，算「还在用」）
--   · 每人：名字、等级、帮手标记、多久前、可信度（LY.PeerNote：N 分钟前 · 可能已变 / 按队长推断 / 刚拉你过来 · 待确认）
--   · 公会会员（公会心跳还新鲜的）只在上面那块，这里不重复；人多时默认只列前几层 / 每层前几人，「展开」看全部
--   · 公共频道关着：只显示一行「公共频道已关（点这里打开）」
--   ⛔ 隐私：只用对方自己在公共频道心跳里公开报的字段（名字 / 地图 / 层 / 等级 / 帮手标记 / 读到层码的时间），不额外收集、不存档
--   内存：控件第一次刷新时才建；数据直接读 LY.peers，不另存常驻表（每次刷新的分组表用完即弃）
-- 11-20 用户「如何能和其他同行的通信切？」「我能选吗」：
--   · 每层一个「过去」（和公会那块同名）：只请这层里开了帮忙的人，没在队伍里的先、再按最近活跃的先（LP.Pick）；
--     走 LayerHop 现有的 AskChain → RequestFrom（插件密语 R，⛔ 不发聊天文字、⛔ 不自动邀请谁）；对方是弹框点「邀请」才拉
--     （帮手那边：非本公会的点名一律弹框、写明「非本公会」、他没开帮忙就不弹 —— 见主插件 LayerHop.lua LY.handlers.R）
--   · 这层没人开帮忙：按钮灰着，鼠标提示写原因（灰着也能悬停）
--   · 等对方邀请时再点一次 = 马上改请这层下一位（LP.Next；照 1.4.0「附近有别人点第二次就切换人」）；前面请过的人晚点邀请照样自动接
--   · 「层未知」一张卡：同图（同一个公共频道）、但对方没读到层码（没指过怪 / 老版本不报地图）的人 —— 以前完全不显示（常见的 0 人）。
--     也能请：走 RequestAny（他那边不比地图 / 层），进他的队就到他那层，只是事先不知道是第几层
--   · 0 人时写清楚：对方要装插件、开着公共频道（/gi layer pub on）、在这张图；我自己没进频道时写原因（刚上线 30 秒 / 频道快满）
local _, ns = ...; ns = _G.GearInsightForever or ns
ns._modReady = ns._modReady or {}
local LY, LH = ns.Layer, ns.LayerHop
local LP = {}
ns.LayerPub = LP
local function L(cn, en) return ns.L(cn, en) end
local function now() return (GetTime and GetTime()) or 0 end

LP.FOLD_LAYERS = 3      -- 收起时最多列几层（「层未知」那张另算，总是列出）
LP.FOLD_NAMES = 6       -- 收起时每层最多列几人
LP.OPEN_NAMES = 30      -- 展开后每层最多列几人（再多写「等 N 人」）
LP.MAX_CARDS = 10       -- 展开后最多几张层卡片
local CARD_W = 596
local LAYER_RGB = {
    { 0.30, 0.95, 0.45 }, { 0.35, 0.65, 1.00 }, { 0.75, 0.50, 1.00 },
    { 1.00, 0.62, 0.22 }, { 1.00, 0.45, 0.72 }, { 0.30, 0.90, 0.90 },
}   -- 和 PageLayer.lua 同一套颜色：同一层两块颜色一样
local UNK_RGB = { 0.55, 0.55, 0.58 }
local function layerRGB(no) return LAYER_RGB[((no or 1) - 1) % #LAYER_RGB + 1] end
local function hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end
local BD = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }
local function btn(parent, text, w, h, onClick)
    local W = ns.W or _G.GIWidgets
    local b
    if W and W.Button then b = W.Button(parent, nil, "normal"); b:SetSize(w, h); b:SetText(text)
    else b = ns.Button(parent, text, w, h) end
    b:SetScript("OnClick", onClick)
    return b
end
local function short(n) return (tostring(n or "?"):gsub("%-.*$", "")) end
-- 11-19 用户「这个锁定多久，时间简短」：剩余时间写短（「12 秒」/「2 分钟」）
function LP.LeftText(sec)
    sec = math.max(1, math.ceil(sec or 0))
    if sec < 60 then return string.format(L("%d 秒", "%ds"), sec) end
    local m = math.ceil(sec / 60)
    if m < 60 then return string.format(L("%d 分钟", "%dm"), m) end
    -- 11-23 同一人 2 小时只请一次：「1 小时 25 分」/「2 小时」
    local h, r = math.floor(m / 60), m % 60
    return r == 0 and string.format(L("%d 小时", "%dh"), h) or string.format(L("%d 小时 %d 分", "%dh %dm"), h, r)
end
-- 名单里最早能再请的还要几秒（有人现在就能请 / 名单空 = 0）；单人的在 LayerHop.lua LH.AskLeft（AskChain 也用它跳过锁定中的人）
function LP.ListLeft(list)
    local best
    for _, pe in ipairs(list or {}) do
        local l = LH.AskLeft and LH.AskLeft(pe.name) or 0
        if l <= 0 then return 0 end
        best = best and math.min(best, l) or l
    end
    return best or 0
end
local function lockText(left) return string.format(L("%s后可再请", "again in %s"), LP.LeftText(left)) end
-- 和 PageLayer.lua 的 okMsg 一样：聊天框一行 + 屏幕中间一行
local function msg(ok, why, sent, detail)
    local text = ok and sent or (type(detail) == "string" and detail) or nil
    if not text then
        text = why == "cooldown" and (L("刚求助过", "Just asked") .. string.format(L("，%s后再试", " - again in %s"), LP.LeftText(LH.CooldownLeft())))
            or why == "nobody" and L("这层没有能请的人（都和你同层、刚换走了或没开帮忙）", "Nobody to ask right now")
            or why == "exhausted" and L("这层开了帮忙的人这一轮都请过了，等他们邀请，或换别的层", "Everyone helping on this layer was asked - wait, or try another layer")
            or LP.WHY[why] or tostring(why)
    end
    if LY.Dup and LY.Dup(text) then return end   -- 11-20 连点：同一句 5 秒内聊天框 + 屏幕都只出一次
    ns.Print(text)
    LY.Flash(text, 1, ok and 0.82 or 0.45, ok and 0.2 or 0.35, true)
end
LP.Msg = msg
-- 按钮为什么灰着（鼠标提示用；PageLayer.lua 的 WHY 是它的局部表，这里只写路人那块会碰到的几种）
LP.WHY = ns.LateL and ns.LateL({
    off = L("位面识别关着", "Layer detection is off"),
    instance = L("副本里不能换层", "Not in instances"),
    afterinst = L("刚出副本，10 分钟内先别换层", "Just left an instance - wait 10 min"),
    combat = L("战斗中不能发起", "Not in combat"),
    ingroup = L("你在队伍里：先退队才能被别人拉过去", "You're in a group - leave it first"),
    nolayer = L("还没认出你自己在哪层：鼠标指一下附近任意一只 NPC / 怪（不知道你原来在哪层，就没法确认换没换过去）", "Your layer is unknown - mouse over any nearby NPC first"),
    pending = L("已经在等别人邀请你了", "Already waiting for an invite"),
    confirming = L("已进帮手的队，正在确认换没换层", "In the helper's group - confirming your layer"),
    same = L("他和你在同一层", "Same layer as you"),
    gone = L("这次求助已经结束", "That request is over"),
}) or {}

local function isGuild(pe, t)
    local g = pe.via and pe.via.guild
    return g ~= nil and t - g <= LY.EXPIRE
end
-- 11-20 挑人：只挑开了帮忙的（心跳 hp），没在队伍里的先，再按最近活跃（心跳 / 读到层码的时间，越近越先）
local function active(pe) return math.max(pe.seen or 0, pe.zAt or 0) end
function LP.Pick(list, skip)
    local best
    for _, pe in ipairs(list or {}) do
        if pe.hp and pe.name and not (skip and skip[pe.name]) then
            if not best or (best.ig and not pe.ig) or ((best.ig and true or false) == (pe.ig and true or false) and active(pe) > active(best)) then best = pe end
        end
    end
    return best and best.name or nil, best
end
-- 路人卡片的名单带 byRecent 标记：LayerHop 的 AskChain / 30 秒自动换人（ChainNext）都经 LH.PickHelper 挑人 → 这种名单改按 LP.Pick 挑
--   （公会那块的名单不带标记，照旧「最近帮得最少的先」）。只包一层我们自己的函数表字段，不碰暴雪全局
LH._pick0 = LH._pick0 or LH.PickHelper
LH.PickHelper = function(list, skip)
    if type(list) == "table" and rawget(list, "byRecent") then return LP.Pick(list, skip) end
    return LH._pick0(list, skip)
end
local function helpersOf(list, out)
    out = out or {}
    for _, pe in ipairs(list or {}) do if pe.hp then out[#out + 1] = pe end end
    return out
end

-- 我现在所在的公共频道是什么时候换的：对方心跳没报地图（没读到层 / 老版本）时，只认换频道以后从频道里收到的
--   （频道 = 每张图一个，收到 = 他发的时候和我在同一张图）
LP.chan, LP.chanAt = LY.pubJoined, 0
LY.OnTick(function()
    local c = LY.pubJoined
    if c ~= LP.chan then LP.chan, LP.chanAt = c, now() end
end)

-- 公会那块的按钮（主插件 PageLayer.lua 画的）：锁定中写剩余时间，不静默灰掉
--   「我想换一层」冷却中 →「我想换一层（12 秒）」；某层 / 别的图的人都刚请过 / 刚拉过我 →「1 分钟后可再请」
function LP.Countdown(p, why)
    local tick = false
    if p.hop and p.hop.SetText then
        local cd = why == "cooldown" and LH.CooldownLeft() or 0
        p.hop:SetText(L("我想换一层", "Switch layer") .. (cd > 0 and ("（" .. LP.LeftText(cd) .. "）") or ""))
        tick = cd > 0
    end
    for _, c in ipairs(rawget(p, "cards") or {}) do
        if c:IsShown() and c.go:IsShown() and #(c.farList or {}) == 0 then
            local left = LP.ListLeft(c.list)
            if left > 0 then
                if c.go.SetText then c.go:SetText(lockText(left)) end
                c.go:SetEnabled(false)
                tick = true
            end
        end
    end
    for _, row in ipairs(rawget(p, "oRows") or {}) do
        if row:IsShown() and row.list and not why then
            local left = LP.ListLeft(row.list)
            if left > 0 and not (row.b.GetText and row.b:GetText() == L("和你同层", "Same layer")) then
                if row.b.SetText then row.b:SetText(lockText(left)) end
                row.b:SetEnabled(false)
                tick = true
            end
        end
    end
    return tick
end

-- 同图、公共频道来的、非本公会的插件用户按层分组 → groups（我这层在前，其余按「第几层」，「层未知」最后），总人数，层未知的人数
--   刚把我拉过来的人（HOP_TRUST 秒内）/ 同队 20 秒以上的人：照公会那块的规则放进我这层（他心跳里的层是旧的）
--   11-20：m = nil（我自己还没读到层）时用我所在的地图，照样列人（按钮会灰着说要先认出我的层）；
--     对方没报层码 → 「层未知」组（以前直接不显示）；没报地图（老版本没读到层时心跳里不带地图）→ 换频道以后从这个频道收到的才算同图
function LP.Collect(m)
    local groups, byZ, total, unkG = {}, {}, 0, nil
    m = m or (LY.MyMap and LY.MyMap())
    if not (LY and LH and m) then return groups, 0, 0 end
    local _, myZ = LY.Mine()
    local conf = LY.Confirmed()
    local t = now()
    local h = LH.lastHop
    local hop = h and h.ok and h.m == m and h.z == myZ and t - h.t <= LH.HOP_TRUST
    for _, pe in ipairs(LY.Peers("pub")) do
        local here = pe.m == m or (pe.m == nil and pe.via and (pe.via.pub or 0) >= (LP.chanAt or 0))
        if here and not isGuild(pe, t) and not pe.inst and not (LY.IsMe and LY.IsMe(pe.full or pe.name)) then
            pe.hopPending, pe.hopConflict = nil, nil
            local party = myZ and conf and LY.InMyGroup and LY.InMyGroup(pe.full or pe.name) and t - (LY.groupAt or LY.rosterAt or 0) > 20
                and not (LH.pending and LH.pending.joinedAt)
            pe.party = party or nil
            if not party and hop and pe.z and pe.z ~= myZ and LH.SameName(pe.name, h.who) then
                if pe.zAt and pe.zAt > h.t + 1 then pe.hopConflict = true else pe.hopPending = true; party = true end
            end
            local z = party and myZ or ((pe.m == m and pe.z and (pe.c or 0) >= 2) and pe.z or nil)
            if z then
                local g = byZ[z]
                if not g then g = { z = z, list = { byRecent = true }, mine = (conf and z == myZ) or nil }; byZ[z] = g; groups[#groups + 1] = g end
                g.list[#g.list + 1] = pe
            else
                unkG = unkG or { unk = true, list = { byRecent = true } }
                unkG.list[#unkG.list + 1] = pe
            end
            total = total + 1
        end
    end
    for _, g in ipairs(groups) do g.no = LY.LayerNo(m, g.z) or 99 end
    table.sort(groups, function(a, b)
        if (a.mine or false) ~= (b.mine or false) then return a.mine and true or false end
        if a.no ~= b.no then return a.no < b.no end
        return a.z < b.z
    end)
    if unkG then groups[#groups + 1] = unkG end
    return groups, total, unkG and #unkG.list or 0
end

-- 一个人的一段：名字 等级 · 可帮忙 / 没开帮忙 · 多久前（· 可信度）
function LP.PersonText(pe)
    local s = "|cffe6e6e6" .. tostring(pe.name) .. "|r" .. (pe.lv and ("|cff999999 " .. pe.lv .. "|r") or "")
    s = s .. (pe.hp and ("|cff33ff66 " .. L("可帮忙", "helps") .. "|r") or ("|cff777777 " .. L("没开帮忙", "not helping") .. "|r"))
    if pe.party then s = s .. "|cff66ccff " .. L("同队", "party") .. "|r" end
    if pe.ig and not pe.party then s = s .. "|cff999999 " .. L("在队伍里", "grouped") .. "|r" end
    local at = pe.zAt or pe.seen
    local age = at and (now() - at) or 0
    if age < LY.STALE and not pe.hopPending then   -- 超过 STALE 的由 PeerNote 写「N 分钟前 · 可能已变」
        s = s .. "|cff888888 · " .. (age < 60 and L("刚刚", "just now") or string.format(L("%d 分钟前", "%dm ago"), math.floor(age / 60))) .. "|r"
    end
    return s .. (LY.PeerNote and LY.PeerNote(pe) or "")
end

-- 11-20 这张卡上正在进行的那一轮（我从这张卡点的、还在等邀请）→ ch；否则 nil
function LP.MyChain(key)
    local p = LH.pending
    local ch = rawget(LP, "ch")
    if not (p and ch and p.chain == ch and LP.chKey == key) or p.joinedAt then return nil end
    if now() - (p.t or 0) >= LH.ACCEPT_WIN then return nil end
    return ch
end
-- 11-20「点第二次换下一个人」：等着的时候再点 → 马上改请这层下一位开了帮忙的（本轮请过的跳过；不吃冷却，其他拦截照旧）。
--   前一位那边的框还在，他晚点邀请照样自动接（AcceptRule 认 ch.asked）。返回 who, why, 上一位
function LP.Next(ch, list, far)
    local p0 = LH.pending
    if not (p0 and p0.chain == ch) or p0.joinedAt then return nil, "gone" end
    if list then ch.list = list end
    if far then ch.far = far end
    local last = p0.helper
    for _ = 1, 40 do
        local who, any = LP.Pick(ch.list, ch.tried), false
        if not who then who = LP.Pick(ch.far, ch.tried); any = true end
        if not who then return nil, "exhausted" end
        ch.tried[who] = true
        if LH.AskLeft(who) <= 0 then
            local saved = LH.lastReq
            LH.lastReq, LH.pending = -1e9, nil
            local ok, why
            if any then ok, why = LH.RequestAny(who) else ok, why = LH.RequestFrom(who) end
            if ok then
                ch.n = ch.n + 1
                ch.asked = ch.asked or {}; ch.asked[who] = true
                LH.pending.chain = ch
                LY.Log("换下一个：" .. tostring(last) .. " → 请 " .. tostring(who))
                return who, nil, last
            end
            LH.lastReq, LH.pending = saved, p0
            if why ~= "same" then return nil, why end
        end
    end
    return nil, "exhausted"
end

-- 这张卡按钮的样子：enabled, 按钮字, 鼠标提示, 要不要每秒刷
function LP.CardState(c, why)
    local all = helpersOf(c.far, helpersOf(c.list))
    local unk = c.key == "unk"
    local ch = LP.MyChain(c.key)
    local go = L("过去", "Go")
    if ch then
        local nx = LP.Pick(c.list, ch.tried) or LP.Pick(c.far, ch.tried)
        local wait = string.format(L("正在等 %s 邀请你（还剩 %d 秒）", "Waiting for %s (%ds)"), short(LH.pending.helper),
            math.max(0, math.ceil(LH.ACCEPT_WIN - (now() - LH.pending.t))))
        if nx then
            return true, L("换一个人", "Next"), wait .. "\n" .. string.format(L("再点一次 = 马上改请 %s（前面请过的人晚点邀请也照样接）", "Click again to ask %s instead"), short(nx)), true
        end
        return false, L("等他邀请", "Waiting"), wait .. "\n" .. L("这层开了帮忙的人这一轮都请过了", "Everyone helping here was asked"), true
    end
    if #all == 0 then
        return false, go, string.format(L("这层的 %d 人都没开帮忙，没法请：要对方在位面页勾上「我愿意帮…换层」（看的是他自己在频道里报的标记）",
            "Nobody here is helping - they need to tick \"Help ... switch layers\" on their Layers page"), #(c.list or {}) + #(c.far or {})), false
    end
    -- 11-21 公会外换层额度用完（LayerCredit.lua，HOLD）：灰掉写原因和办法
    local LC = ns.LayerCredit
    if not why and LC and LC.Blocked() then return false, go, LC.Text("card"), false end
    if why then
        local w = LP.WHY[why] or tostring(why)
        if why == "cooldown" then w = L("刚求助过", "Just asked") .. string.format(L("，%s后再试", " - again in %s"), LP.LeftText(LH.CooldownLeft())) end
        return false, go, w, why == "cooldown"
    end
    local left = LP.ListLeft(all)
    if left > 0 then return false, lockText(left), L("这层开了帮忙的人都刚请过 / 刚拉过你（他那边 2 分钟内会忽略同一个人的点名）", "Everyone helping here was just asked"), true end
    local who, pe = LP.Pick(c.list)
    if not who then who, pe = LP.Pick(c.far) end
    local ago = pe and math.max(0, math.floor(now() - active(pe))) or 0
    local tip = string.format(L("会请 %s（%s前活跃；开了帮忙的 %d 人里没在队伍里、最近活跃的先）", "Asks %s (active %s ago; helpers not in a group and most recently active first)"),
        short(who), LP.LeftText(ago), #all)
        .. "\n" .. L("他不是本公会的：他那边弹框写「非本公会」，点了「邀请」才会拉你，不会自动拉；只发插件消息，不在聊天里说话", "Not in your guild: they get a prompt and must click Invite. Addon message only")
        .. "\n" .. L("30 秒没邀请自动换下一位；等的时候再点一次可以马上换人", "Auto-asks the next one after 30 sec; click again to switch now")
    if unk then tip = tip .. "\n" .. L("层未知：进他的队就到他那层，但事先不知道是第几层（他本来和你同层的话，进队后会提示）", "Layer unknown: joining moves you to his layer, whichever it is") end
    return true, go, tip, false
end

local function mkCard(p)
    local c = CreateFrame("Frame", nil, p.body, BackdropTemplateMixin and "BackdropTemplate" or nil)
    c:SetSize(CARD_W, 52)
    if c.SetBackdrop then pcall(c.SetBackdrop, c, BD) end
    c.bar = c:CreateTexture(nil, "ARTWORK"); c.bar:SetPoint("TOPLEFT", 1, -1); c.bar:SetPoint("BOTTOMLEFT", 1, 1); c.bar:SetWidth(4)
    c.title = c:CreateFontString(nil, "OVERLAY", "GameFontNormal"); c.title:SetPoint("TOPLEFT", 14, -8); c.title:SetJustifyH("LEFT")
    c.code = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); c.code:SetPoint("LEFT", c.title, "RIGHT", 8, 0)
    c.tag = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); c.tag:SetPoint("LEFT", c.code, "RIGHT", 10, 0)
    c.names = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); c.names:SetPoint("TOPLEFT", 14, -28)
    c.names:SetWidth(CARD_W - 130); c.names:SetJustifyH("LEFT")
    if c.names.SetWordWrap then c.names:SetWordWrap(true) end
    -- 「过去」：这层里挑开了帮忙、最近活跃的一位点名（AskChain：30 秒没邀请自动换下一位，最多 3 位）；等的时候再点 = 马上换人。⛔ 只发插件密语
    c.go = btn(c, L("过去", "Go"), 96, 24, function()
        local ch = LP.MyChain(c.key)
        if ch then
            local who, why, last = LP.Next(ch, c.list, c.far)
            msg(who ~= nil, why, string.format(L("已改请 %s 拉你（%s 那边的框还在，谁先邀请都接）", "Now asking %s (%s may still invite - either works)"), short(who), short(last)))
        else
            if not (LP.Pick(c.list) or LP.Pick(c.far)) then return end
            local who, why, detail = LH.AskChain(c.list, c.far, tonumber(c.key))
            if who and LH.pending and LH.pending.chain then LP.ch, LP.chKey = LH.pending.chain, c.key end
            msg(who ~= nil, why, string.format(L("已请 %s 拉你（非本公会，他那边点「邀请」才会拉）：他一邀请你就自动进队；30 秒没邀请自动换人，再点一次马上换人", "Asked %s (not in your guild - they must click Invite); auto-asks someone else after 30 sec, click again to switch now"), short(who)), detail)
        end
        if p.refreshNow then p.refreshNow() end
    end)
    c.go:SetPoint("RIGHT", -10, 0)
    if c.go.SetMotionScriptsWhileDisabled then pcall(c.go.SetMotionScriptsWhileDisabled, c.go, true) end   -- 灰着也能悬停看原因
    c.go:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local _, _, tip = LP.CardState(c, LH.Blocked())
        GameTooltip:SetText(tip or "", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    c.go:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c:Hide()
    return c
end

local function build(p)
    local b = p.body
    p.pBuilt = true
    -- 有倒计时就每秒刷一次（到 0 再刷一次，按钮恢复原样）
    LY.OnTick(function()
        if rawget(p, "pTick") and p:IsShown() and p.refreshView and not (LH.pending or LH.CooldownLeft() > 0) then p.refreshView() end   -- 那两种情况 PageLayer.lua 自己每秒刷
    end)
    p.pHd = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.pSub = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); p.pSub:SetWidth(CARD_W); p.pSub:SetJustifyH("LEFT")
    p.pSub:SetText(L("不是本公会、也装了插件的玩家；只显示他们自己在频道里公开报的名字 / 等级 / 层 / 是否帮忙。点「过去」请这层开了帮忙的人拉你，对方点了「邀请」才会拉。列表每 15 秒更新一次",
        "Other addon users here (not your guild) - only what they broadcast themselves. \"Go\" asks a helper on that layer; they must click Invite. Updates every 15s"))
    -- 公共频道关着：一行可点的字
    p.pOff = CreateFrame("Button", nil, b); p.pOff:SetSize(CARD_W, 18)
    p.pOff.t = p.pOff:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); p.pOff.t:SetPoint("LEFT", 2, 0); p.pOff.t:SetJustifyH("LEFT")
    p.pOff.t:SetText("|cffffcc00" .. L("公共频道已关（点这里打开）", "Public channel is off (click to turn on)") .. "|r")
    p.pOff:SetScript("OnClick", function() LY.SetPub(true); if p.refreshNow then p.refreshNow() end end)
    p.pEmpty = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); p.pEmpty:SetWidth(CARD_W); p.pEmpty:SetJustifyH("LEFT")
    if p.pEmpty.SetWordWrap then p.pEmpty:SetWordWrap(true) end
    p.pMore = btn(b, L("展开", "More"), 160, 22, function()
        p.pubOpen = not rawget(p, "pubOpen")
        if p.refreshNow then p.refreshNow() end
    end)
    p.pCards = {}
end

local function place(p, w, y, x) w:ClearAllPoints(); w:SetPoint("TOPLEFT", p.body, "TOPLEFT", x or 12, y); w:Show() end

-- 11-20 0 人时：要别人看得到 / 我看得到别人，各要满足什么；我自己没进这张图的频道时写原因
function LP.EmptyText()
    local s = L("同图暂时没有其他插件用户。要互相看到：对方也装了 GearInsight 无限版、开着公共频道（/gi layer pub on），并且就在这张图上（每张图一个频道，副本里不算）",
        "No other addon users on this map yet. They need the addon, the public channel on (/gi layer pub on), and to be on this map")
    -- 11-23 诊断：频道名 + 已加入几号 / 未加入的原因（LayerCredit.lua LC.Pub，和 /gi layer pub 同一句；原来这里三种原因各一句，合并省 _LayerUI 内存）
    local LC = ns.LayerCredit
    if LC and LC.Pub then s = s .. "\n" .. (LY.pubJoined == (LY.PubChannel and LY.PubChannel()) and "|cff999999" or "|cffffcc00") .. LC.Pub() .. "|r" end
    return s
end

-- PageLayer.lua 刷新时调：从 y 往下画这一块，返回新的 y。why = LH.Blocked()（按钮可不可点）
function LP.Refresh(p, y, m, why)
    if not (LY and LH and p and p.body) then return y end
    if not rawget(p, "pBuilt") then build(p) end
    if not rawget(p, "lpCalm") then pcall(LP.Calm, p) end   -- 11-21 别人的信号最多 15 秒重排一次（下面 LP.Calm）
    if ns.LayerCredit then pcall(ns.LayerCredit.Paint, p) end   -- 11-21 互助额度那一行（LayerCredit.lua，HOLD；没有就不出）
    p.pTick = LP.Countdown(p, why)
    for _, c in ipairs(p.pCards) do c:Hide() end
    p.pOff:Hide(); p.pEmpty:Hide(); p.pMore:Hide(); p.pSub:Hide()
    local d = LY.DB()
    if not d.on then p.pHd:Hide(); return y end   -- 位面识别关着：上面已经写了，这块不出
    y = y - 8
    if not d.pub then
        p.pHd:SetText(L("同图其他玩家（公共频道）", "Other players here (public channel)"))
        place(p, p.pHd, y); y = y - 20
        place(p, p.pOff, y, 12); y = y - 22
        return y
    end
    m = m or (LY.MyMap and LY.MyMap())
    local groups, total = LP.Collect(m)
    p.pHd:SetText(ns.EnSafe(L("同图其他玩家（公共频道）", "Other players here (public channel)") .. string.format("  |cffcccccc%d %s|r", total, L("人", ""))))
    place(p, p.pHd, y); y = y - 18
    place(p, p.pSub, y, 14); y = y - math.max(12, tonumber(p.pSub:GetStringHeight()) or 12) - 6
    if total == 0 then
        p.pEmpty:SetText(LP.EmptyText())
        place(p, p.pEmpty, y, 14); y = y - math.max(14, tonumber(p.pEmpty:GetStringHeight()) or 14) - 6
        return y
    end
    local open = rawget(p, "pubOpen")
    local unkG = groups[#groups] and groups[#groups].unk and groups[#groups] or nil
    local nKnown = #groups - (unkG and 1 or 0)
    local nShow = open and math.min(nKnown, LP.MAX_CARDS) or math.min(nKnown, LP.FOLD_LAYERS)
    local show = {}
    for i = 1, nShow do show[i] = groups[i] end
    if unkG then show[#show + 1] = unkG end   -- 「层未知」那张总是列出（不占收起时的层数）
    local perCard = open and LP.OPEN_NAMES or LP.FOLD_NAMES
    local folded = nKnown > LP.FOLD_LAYERS
    for i, g in ipairs(show) do
        local c = p.pCards[i]
        if not c then c = mkCard(p); p.pCards[i] = c end
        local col = g.unk and UNK_RGB or layerRGB(g.no)
        if g.unk then
            c.title:SetText(string.format("%s%s|r  |cffcccccc%d %s|r", hex(col), L("层未知", "Layer unknown"), #g.list, L("人", "")))
            c.code:SetText("")
            c.tag:SetText("|cff999999" .. L("他们还没读到层码；进他的队就到他那层", "they haven't read a layer code; joining moves you to theirs") .. "|r")
        else
            c.title:SetText(string.format("%s%s|r  |cffcccccc%d %s|r", hex(col), LY.LayerName(m, g.z), #g.list, L("人", "")))
            c.code:SetText(L("层码 ", "code ") .. LY.Tail(g.z))
            c.tag:SetText(g.mine and ("|cff33ff66" .. L("你在这里", "You are here") .. "|r") or "")
        end
        c.bar:SetColorTexture(col[1], col[2], col[3], 1)
        if c.SetBackdropColor then
            if g.mine then c:SetBackdropColor(col[1] * 0.18, col[2] * 0.18, col[3] * 0.18, 0.92); c:SetBackdropBorderColor(col[1], col[2], col[3], 0.9)
            else c:SetBackdropColor(0.06, 0.06, 0.08, 0.88); c:SetBackdropBorderColor(0.28, 0.28, 0.30, 0.9) end
        end
        local parts = {}
        for k = 1, math.min(perCard, #g.list) do parts[k] = LP.PersonText(g.list[k]) end
        if #g.list > perCard then
            folded = true
            parts[#parts + 1] = string.format("|cff999999" .. L("等 %d 人", "+%d more") .. "|r", #g.list - perCard)
        end
        c.names:SetText(ns.EnSafe(table.concat(parts, "   ")))
        -- 已知层：RequestFrom（点名那层）；层未知：RequestAny（他那边不比地图 / 层，进队后看我的层变没变）
        c.key = g.unk and "unk" or g.z
        c.list = (not g.mine and not g.unk) and g.list or { byRecent = true }
        c.far = g.unk and g.list or { byRecent = true }
        local en, label, _, tick = LP.CardState(c, why)
        if c.go.SetText then c.go:SetText(label) end
        if tick then p.pTick = true end
        c.go:SetShown(not g.mine)
        c.go:SetEnabled((not g.mine) and en)
        local h = math.max(52, 36 + (tonumber(c.names:GetStringHeight()) or 14))
        c:SetHeight(h)
        place(p, c, y, 12)
        y = y - h - 6
    end
    if open and nKnown > LP.MAX_CARDS then
        p.pEmpty:SetText(string.format(L("还有 %d 层没列出", "%d more layers not shown"), nKnown - LP.MAX_CARDS))
        place(p, p.pEmpty, y, 14); y = y - 18
    end
    if folded or open then
        if p.pMore.SetText then
            p.pMore:SetText(open and L("收起", "Less") or string.format(L("展开全部（%d 层 %d 人）", "Show all (%d layers, %d)"), nKnown, total))
        end
        place(p, p.pMore, y, 12); y = y - 28
    end
    return y
end

-- ---------- 11-19 从主插件 LayerHop.lua 搬来（只有位面页用；主插件登录内存没余量，腾给换层「已完成」回执那套）----------
-- 11-14 用户截图：页面「换层成功：… 第 11 层」、顶上「已经换过来了：… 第 12 层（层码 0049）」—— 第几层是插件按发现先后编的号，
--   之后又发现新层编号就挪了，页面那句还是当时写死的字。→ 可以带 { m, z, tpl }：显示时按当前编号重算（LH.LastText），再带上层码
function LH.LastText()
    local l = LH.last
    if not l then return nil end
    if l.tpl and l.m and l.z and LY.LayerName then
        local okN, name = pcall(LY.LayerName, l.m, l.z)
        if okN and type(name) == "string" then
            local code = LY.Tail and select(2, pcall(LY.Tail, l.z))
            return string.format(l.tpl, name .. ((type(code) == "string" and code ~= "") and (L("（层码 ", " (") .. code .. L("）", ")")) or ""))
        end
    end
    return l.text
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
    -- 11-19：刚被谁拉过来（HOP_TRUST 秒内、我还在那层）
    local h = LH.lastHop
    local hop = h and h.ok and h.m == m and h.z == myZ and now() - h.t <= LH.HOP_TRUST
    for _, p in ipairs(LY.Peers("guild")) do
        p.hopPending, p.hopConflict = nil, nil
        if p.m == m and not p.inst and not (LY.IsMe and LY.IsMe(p.full or p.name)) then
            -- 11-09 用户截图「为啥我没切过去一起」：同队的人进队 20 秒后一定在同一层（暴雪机制），他心跳里的旧层不算 → 放进我这层，标「同队」
            -- 11-12：按进队时刻（groupAt）算 20 秒；rosterAt 在队里会被名单小变动反复刷新，原来队友一直显示在他旧的那层
            local party = myZ and LY.Confirmed() and LY.InMyGroup and LY.InMyGroup(p.full or p.name) and now() - (LY.groupAt or LY.rosterAt or 0) > 20
                and not (LH.pending and LH.pending.joinedAt)   -- 换层还没确认时我的层是旧的，别把队长挪进我的旧层
            p.party = party or nil
            if not party and hop and p.z and p.z ~= myZ and LH.SameName(p.name, h.who) then
                -- 他换层以后重新读到过层（za 晚于拉人时刻）还是别的层码 → 以他读到的为准，标「层码对不上」；否则先放进我这层「待确认」
                if p.zAt and p.zAt > h.t + 1 then p.hopConflict = true else p.hopPending = true; party = true end
            end
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
        if not byZ[z] and LY.Live(m, z) then byZ[z] = { z = z, members = {}, known = true } end   -- 11-19：早就过期的层码不再列
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

-- 11-21 用户录像「变动太频繁，观感不好，设计下，让用户看的明确，不需要这么频繁的变动」：
--   原来别人的心跳每来一条就 LY.dirty → 整页每秒重排（层号 / 卡片顺序 / 人数一直跳）
--   → 别人的信号先攒着，整页最多每 LP.HOLD 秒重排一次；我自己的地图 / 层变了、点了按钮（refreshNow）、等待中 / 冷却中照常即时刷；
--     攒着的这段时间只更新「过去」按钮的倒计时字，不动排版
LP.HOLD = 15
function LP.Calm(p)
    if not p or rawget(p, "lpCalm") or not rawget(p, "refreshView") then return end
    p.lpCalm = true
    local raw, rawNow = p.refreshView, p.refreshNow
    p.refreshView = function(...)
        local t = now()
        local m, z = LY.Mine()
        local key = tostring(m) .. "|" .. tostring(z)
        local busy = LH.pending or (LH.CooldownLeft and LH.CooldownLeft() > 0)
        local at = rawget(p, "lpAt")
        if rawget(p, "lpForce") or busy or key ~= rawget(p, "lpKey") or not at or t - at >= LP.HOLD then
            p.lpForce = nil; p.lpKey = key; p.lpAt = t
            return raw(...)
        end
        LY.dirty = true   -- 没轮到：留着脏标记，到点那一秒 PageLayer 的每秒检查会再来
        pcall(LP.Countdown, p, nil)
    end
    if rawNow then p.refreshNow = function(...) p.lpForce = true; return rawNow(...) end end
end
do
    local LG = ns.LayerGuild
    if LG and LG.page then pcall(LP.Calm, LG.page) end
end

-- 11-22 用户「老是过30秒没人组」（从主插件 LayerHop.lua 搬来省登录内存；求助都从位面页发，发的时候本子插件已加载）
-- 11-22 群发求助 30 秒没人认领：从名单里挑别的层开了帮忙、没在队伍里的，自动挨个点名（同 ChainNext，一轮最多 CHAIN_MAX 人）
local function cands(g, z, xset)
    local m, myZ = LY.Mine()
    local list = {}
    for _, pe in ipairs(LY.Peers((g or not LY.DB().pub) and "guild" or nil)) do
        if pe.m == m and pe.z and pe.z ~= myZ and pe.hp and not pe.ig and not pe.inst and not LY.IsMe(pe.full or pe.name)
            and (not z or pe.z == z) and not (xset and xset[pe.z]) and not LH.RecentHelper(pe.name) and LH.AskLeft(pe.name) == 0 then list[#list + 1] = pe end
    end
    return list
end
function LH.AutoChain(p)
    local list = cands(p.g, p.z, p.xset)
    if #list == 0 then return false end
    local ch, saved = { list = list, far = {}, tried = {}, n = 0 }, LH.lastReq
    LH.lastReq = -1e9
    local who = LH._chainAsk(ch)
    if not who then LH.lastReq = saved; return false end
    LY.Log("群发 30 秒没人认领 → 点名 " .. tostring(who))
    LH.SetResult(true, string.format(L("30 秒没人接，自动点名请 %s（第 1 / %d 位）", "No taker in 30s - asking %s (1/%d)"), tostring(who):gsub("%-.*$", ""), LH.CHAIN_MAX))
    return true
end

-- 11-23 用户「增加切换效率，成功率」。存档日志 10:41~10:44：同图只有 Paladinyvil 一个帮手，「我想换一层」4 次群发（每次等 30 秒）全没人接 ——
--   他刚「拉过我」被群发排除（那次其实没换成，主插件 LayerHop.lua 现在会解除）。
--   ① 同图能请的帮手（开了帮忙、没在队伍里、不是刚拉过我 / 刚请过的）只有 1~DIRECT 位：直接点名（插件密语，比公共频道稳），不先群发等 30 秒再点名；
--      DIRECT = 2：3 位以上群发谁快谁拉（自动帮忙的人 0~1.5 秒就认领），比挨个点名每人等 30 秒快
--   ② 连着 2 次以上群发没人接、又没有可点名的人：60 → 120 → 240 秒内不再群发，说清楚原因（别每 30 多秒刷一次公会 + 公共频道）；有人邀请过就清零
local DIRECT, bcN, bcAt = 2, 0, 0
local req0 = LH._crReq0 or LH.Request
local function req(z)
    local c = LH.ctx
    if c and (c.joinedAt or c.res == "o") then bcN = 0 end
    if not z then
        local _, _, xset = LH.Exclusions((LY.Mine()))
        local list = cands(LH.gOnly, nil, xset)
        if #list > 0 and #list <= DIRECT then
            local who = (LH._crAsk0 or LH.AskChain)(list)
            if who then return true, nil, string.format(L("同图能帮你的只有 %d 位：直接请 %s 拉你（不群发）", "Only %d helper(s) here - asking %s directly"), #list, short(who)) end
        end
        local w = bcN >= 2 and 30 * 2 ^ math.min(bcN - 1, 3) - (now() - bcAt) or 0
        if w > 0 then return false, "backoff", string.format(L("连续 %d 次求助都没人接：%s后再群发，或点某层「过去」单独请人", "%d asks unanswered - again in %s"), bcN, LP.LeftText(w)) end
    end
    return req0(z)
end
if LH._crReq0 then LH._crReq0 = req else LH.Request = req end

-- 换层这轮里有人邀请了但没自动接：马上提示点接受，超时文字也照实写（原来 30 秒后说「没有人邀请你」）
LY.onMiss = function(who)
    local c = LH.ctx
    if not c or c.res == "o" or now() - c.t > LH.POP_LIVE + 30 then return end
    c.miss = who
    LY.Flash(string.format(L("%s 邀请了你（没自动接上）：要换层就点组队邀请框里的「接受」", "%s invited you - click Accept on the invite to switch"), who), 1, 0.82, 0)
end

-- 11-22 求助作废时给玩家看的那句（主插件 LayerHop.lua watch 调）
function LH.MissText(p, who)
    if not who and p == (LH.ctx and LH.ctx.bp) then bcN, bcAt = bcN + 1, now() end
    local text
    local mi = LH.ctx and LH.ctx.miss
    if mi then
        text = string.format(L("没换成：%s 邀请过你但没自动接上。组队邀请框还在就点「接受」，或马上再试", "No move: %s invited you but it wasn't auto-accepted - click Accept or try again"), mi)
    elseif who and p.chain and p.chain.n > 1 then
        text = string.format(L("没换成：连请 %d 人都没邀请你，%s后可再请他们", "No move: %d players didn't invite you - again in %s"), p.chain.n, LP.LeftText(LH.REASK))
    elseif who then
        text = string.format(L("没换成：%s 30 秒没邀请你，这层没别人可请；%s后可再请他", "No move: %s didn't invite you - again in %s"), who, LP.LeftText(LH.REASK))
    elseif p.free == 0 then
        text = L("没换成：别的层的帮手都在队伍里 / 没开帮忙。可点某层「过去」单独请人", "No move: helpers on other layers are grouped or not helping - use \"Go\" to ask one person")
    else
        -- 11-19：求助也发到了同图公共频道 → 不只是公会会员
        text = string.format(L("没换成：30 秒内没有人邀请你（%s）。可马上再试，或点某层「过去」单独请人", "No move: nobody invited you within 30 sec (%s) - try again, or use \"Go\""),
            (LY.DB().pub and not p.g) and L("公会 + 同图公共频道", "guild + public channel") or L("公会", "guild"))
    end
    return text
end

-- 11-10 用户截图「点了也没人邀请我」：别的层能帮的公会会员（开了帮忙、没在队伍里、不在副本）有几个（11-22 从主插件搬来）；0 个时超时提示说清楚原因
function LH.FreeHelpers(z)
    local m, myZ = LY.Mine()
    local n = 0
    for _, p in ipairs(LY.Peers(not LY.DB().pub and "guild" or nil)) do   -- 11-19：求助也发同图公共频道 → 开着时那边的帮手也算
        if p.m == m and p.z and p.z ~= myZ and (not z or p.z == z) and p.hp and not p.ig and not p.inst
            and not (LY.IsMe and LY.IsMe(p.full or p.name)) and (z or not LH.IsExcluded(p, m)) then n = n + 1 end
    end
    return n
end
-- 11-22 点名链里下一位（主插件 LayerHop.lua watch 超时调；从主插件搬来省登录内存）
function LH.ChainNext(ch, last)
    if ch.n >= LH.CHAIN_MAX then return false end
    local saved = LH.lastReq
    LH.lastReq = -1e9          -- 自动续请：不吃冷却（其他拦截照旧：进队 / 战斗 / 副本 / 关了）
    local who = LH._chainAsk(ch)
    if not who then LH.lastReq = saved; return false end
    LY.Log("自动换人：" .. tostring(last) .. " 没邀请 → 请 " .. tostring(who))
    LH.SetResult(true, string.format(L("%s 30 秒没邀请你，自动换 %s 试试（第 %d / %d 位）", "%s didn't invite - asking %s (%d/%d)"),
        tostring(last), tostring(who):gsub("%-.*$", ""), ch.n, LH.CHAIN_MAX))
    return true
end

ns._modReady.layerui = true
if ns.FlushInits then ns.FlushInits() end
