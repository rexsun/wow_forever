-- 「位面」页（10-28，HOLD；11-06 改成练级会员互助换层为主，见 build 上方注释）
-- 逻辑在 Layer.lua / LayerGuild.lua / LayerHop.lua；这里只画。⛔ 所有「邀请」按钮的 OnClick 里才调 InviteUnit，一下一个。
local _, ns = ...
local LY, LG, LH = ns.Layer, ns.LayerGuild, ns.LayerHop
if not (LY and LG and LH) then return end
local L = function(cn, en) return ns.L(cn, en) end
local GREEN, YEL, RED, GREY = "|cff33ff66", "|cffffcc00", "|cffff6655", "|cff999999"

local WHY = ns.LateL({   -- 11-09 GI-202：手动切语言后跟着换
    off = L("位面识别关着：下面设置里打开", "Layer detection is off (turn it on below)"),
    instance = L("副本里不能换层", "Not in instances"),
    afterinst = L("刚出副本，10 分钟内先别换层", "Just left an instance - wait 10 min"),
    combat = L("战斗中不能发起", "Not in combat"),
    ingroup = L("你在队伍里：先退队才能被别人拉过去", "You're in a group - leave it first"),
    nolayer = L("还没认出你在哪层：鼠标指一下附近任意一只 NPC / 怪", "Layer unknown - mouse over any nearby NPC"),
    cooldown = L("刚求助过，等一下再试", "Just asked - try again shortly"),
    pending = L("已发出求助，等公会会员拉你（他一邀请你就自动进队）", "Asked - waiting for a guildmate's invite"),
    same = L("他和你在同一层", "Same layer as you"),
    nohelp = L("这层的公会会员都没开「帮公会会员换层」", "Nobody on that layer is helping"),
    nobody = L("没有能请的公会会员（都和你同层或刚换走了）", "Nobody to ask right now"),
    confirming = L("已进帮手的队，正在确认换没换层，别重复求助", "In the helper's group - confirming your layer"),
    already = L("已经换过来了，不用再换", "Already moved"),
    dup = L("这里只有刚拉过你的公会会员，换别的层再试", "Only the guildmate who just pulled you is here"),
})
-- 11-12：detail = LayerHop 给的整句（已经换过来了 / 正在确认 / 只剩刚拉过你的人），有就用它
-- 11-21 用户截图「这里可以公会和公会外同时找吗」：「我想换一层」本来就同时发公会 + 同图公共频道，等待那行别只写「公会会员」
local function askWho()
    local g = IsInGuild and IsInGuild() and true or false
    local pub = LY.pubJoined ~= nil and not (LH.pending and LH.pending.g)   -- 11-21 pending.g = 公会外额度用完、这次只找了公会
    if g and pub then return L("公会会员或同图插件用户", "a guildmate or nearby GI user") end
    if pub then return L("同图插件用户", "a nearby GI user") end
    return L("公会会员", "a guildmate")
end
local function okMsg(ok, why, sent, detail)
    local text = type(detail) == "string" and detail or (ok and sent) or WHY[why] or tostring(why)   -- 11-21 成功也可带整句（只找了公会）
    if LY.Dup(text) then return end   -- 11-20 连点：同一句 5 秒内聊天框 + 屏幕都只出一次
    ns.Print(text)
    LY.Flash(text, 1, ok and 0.82 or 0.45, ok and 0.2 or 0.35, true)   -- 11-08「点了以后毫无反馈？」：屏幕中间也出一行
end

-- 11-06 用户「我的目的是给练级过程中的会员用的，互相互助切位面」→ 截图「不美观，学习下…位面如何区分，展示，学习好的案例」：
--   照 Guild Master Forever 的层列表（「> 」标我这层、层名金字 + 灰色 #zoneUID、右边人数，「You are here」）和
--   NovaWorldBuffs 那种玩家都认识的「Layer N」叫法，做成层卡片：
--   · 每层固定颜色 + 「第 N 层」，层码灰色小字；我这层整块描边高亮，写「你在这里」
--   · 别的层：卡片标题 = 层号 + 人数，卡片里会员名（职业色 + 等级），卡片右边一个「过去」按钮（整层一个，不是每人一个）
--   · 金色只给主按钮「我想换一层」，其余低调
--   开服集合建会那一块（A）公会早建好了，页面上不再出现；LayerGuild.lua 照常加载（会长 / 官员邀请自动接受、/gi layer lead|join 口令还能用）
local LAYER_RGB = {
    { 0.30, 0.95, 0.45 }, { 0.35, 0.65, 1.00 }, { 0.75, 0.50, 1.00 },
    { 1.00, 0.62, 0.22 }, { 1.00, 0.45, 0.72 }, { 0.30, 0.90, 0.90 },
}
-- 11-19 用户截图「展示还是有误」：别人报的层码是几分钟前读到的 / 刚把我拉过来还没回报，都写出来，不当确定的事实
local function peerNote(pe)
    if pe.hopPending then return "|cffffcc00 " .. string.format(L("刚拉你过来 · 待确认（他上次报 层码 %s）", "confirming (%s)"), LY.Tail(pe.z)) .. "|r" end
    local at = pe.zAt or pe.seen
    local age = at and ((GetTime and GetTime() or 0) - at) or 0
    return (pe.hopConflict and ("|cffff9966 " .. L("刚拉过你 · 他读到的层码和你不同", "code differs") .. "|r") or "")
        .. ((age >= LY.STALE and ("|cff888888 · " .. string.format(L("%d 分钟前 · 可能已变", "%dm ago"), math.max(1, math.floor(age / 60))) .. "|r"))
            or (pe.zi and ("|cff888888 · " .. L("按队长推断", "inferred") .. "|r")) or "")
end
LY.PeerNote = peerNote   -- 测试用

local function layerRGB(no) return LAYER_RGB[((no or 1) - 1) % #LAYER_RGB + 1] end
local function hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end
local function classHex(cf)
    local cc = cf and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[cf]
    if type(cc) == "table" and cc.r then return string.format("|cff%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255) end
    return "|cffe6e6e6"
end
local BD = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }
local W = ns.W or _G.GIWidgets
local function btn(parent, text, w, h, kind, onClick)
    local b
    if W and W.Button then b = W.Button(parent, nil, kind); b:SetSize(w, h); b:SetText(text)
    else b = ns.Button(parent, text, w, h) end
    b:SetScript("OnClick", onClick)
    return b
end

local function check(parent, x, y, text, get, set)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate"); c:SetSize(22, 22); c:SetPoint("TOPLEFT", x, y)
    c:SetScript("OnClick", function(b) set(b:GetChecked() and true or false) end)
    c.t = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); c.t:SetPoint("LEFT", c, "RIGHT", 2, 0); c.t:SetText(text)
    c.get = get
    return c
end

local CARD_W, MAX_CARDS = 596, 8
-- 「过去」/「请他们拉我」的鼠标提示：会请谁（11-19 内存：两处共用一份）
local function askTip(self, a, b, none)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local who, pe = LH.PickHelper(a)
    if not who and b then who, pe = LH.PickHelper(b) end
    GameTooltip:SetText(who and string.format(L("会请最近帮得最少的一位：%s（帮过 %s 次）", "Asks whoever helped least recently: %s (%s)"),
        who, pe and pe.hc and tostring(pe.hc) or "?") or none, 1, 1, 1, 1, true)   -- 11-10 BugSack：第 5 个参数是透明度，少写一个 1 → true 落到 alpha 报错
    GameTooltip:Show()
end
local function hideTip() GameTooltip:Hide() end
local function mkCard(parent, p)
    local c = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    c:SetSize(CARD_W, 52)
    if c.SetBackdrop then pcall(c.SetBackdrop, c, BD) end
    c.bar = c:CreateTexture(nil, "ARTWORK"); c.bar:SetPoint("TOPLEFT", 1, -1); c.bar:SetPoint("BOTTOMLEFT", 1, 1); c.bar:SetWidth(4)
    c.title = c:CreateFontString(nil, "OVERLAY", "GameFontNormal"); c.title:SetPoint("TOPLEFT", 14, -8); c.title:SetJustifyH("LEFT")
    c.code = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); c.code:SetPoint("LEFT", c.title, "RIGHT", 8, 0)
    c.tag = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); c.tag:SetPoint("LEFT", c.code, "RIGHT", 10, 0)
    c.names = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); c.names:SetPoint("TOPLEFT", 14, -28)
    c.names:SetWidth(CARD_W - 130); c.names:SetJustifyH("LEFT")
    if c.names.SetWordWrap then c.names:SetWordWrap(true) end
    -- 11-06 用户「前 6 个人一直被骚扰，可以平均一下吗」：点的时候才从这层全部会员里挑（开了帮忙、没在队伍里、我最久没请过的优先）
    c.go = btn(c, L("过去", "Go"), 84, 24, "normal", function()
        -- 11-10 用户「一个人没接，会自动换一个人？」→ 30 秒没邀请自动换下一位（LH.AskChain，最多 3 位）
        if not (LH.PickHelper(c.list) or LH.PickHelper(c.farList)) then return end
        local who, why, detail = LH.AskChain(c.list, c.farList, c.z)
        okMsg(who ~= nil, why, string.format(L("已请 %s 拉你过去：他一邀请你就自动进队，换过去后自动退队；30 秒没邀请会自动换人", "Asked %s - you'll auto-join, then leave once moved; auto-asks someone else after 30 sec"), tostring(who)), detail)
        p.refreshNow()
    end)
    c.go:SetPoint("RIGHT", -10, 0)
    c.go:SetScript("OnEnter", function(self) askTip(self, c.list, c.farList, L("这层没有公会会员", "Nobody on this layer")) end)
    c.go:SetScript("OnLeave", hideTip)
    return c
end

-- 11-06 用户截图「选中的标签加个标识框」：位面页开着时右侧「位面」页签金边高亮（W.SelectTab，同公会 / 组队抽屉页签）
local function markTab(on)
    local host = _G.GearInsightForeverMain
    local tab = host and rawget(host, "_giLayerTab")
    local W = ns.W or _G.GIWidgets
    if tab and W and W.SelectTab then pcall(W.SelectTab, tab, on and true or false) end
end

local function build(p)
    p:HookScript("OnShow", function() markTab(true) end)
    p:HookScript("OnHide", function() markTab(false) end)
    markTab(true)   -- 页面第一次建出来时本来就是显示状态，OnShow 不会再触发
    local y0 = ns.PageHeader(p, L("位面", "Layers"), L("练级时公会会员互相拉一下就能换层 · 进队就到队长那层（官方机制）", "Guildmates pull each other across layers"))
    local top = math.min(-46, y0 - 4)
    local _, body = ns.Scroll(p, 0, top, 646 - 24, 474 + top - 6)
    p.body = body
    local y = -4
    p.me = body:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.me:SetPoint("TOPLEFT", 12, y); p.me:SetJustifyH("LEFT")
    p.meCode = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); p.meCode:SetPoint("LEFT", p.me, "RIGHT", 8, -1)
    y = y - 24
    p.meHint = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.meHint:SetPoint("TOPLEFT", 12, y); p.meHint:SetWidth(CARD_W); p.meHint:SetJustifyH("LEFT")
    y = y - 24
    p.hop = btn(body, L("我想换一层", "Switch layer"), 150, 30, "primary", function()
        local ok, why, detail = LH.Request(nil)
        okMsg(ok, why, L("已向公会和同图的插件用户求助：别的层的公会会员一邀请你就自动进队，换过去后自动退队", "Asked guildmates on other layers - you'll auto-join, then leave once moved"), detail)
        p.refreshNow()
    end)
    p.hop:SetPoint("TOPLEFT", 12, y)
    p.hopSt = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.hopSt:SetPoint("LEFT", p.hop, "RIGHT", 12, 0); p.hopSt:SetWidth(CARD_W - 316); p.hopSt:SetJustifyH("LEFT")
    -- 11-24 用户截图「这里增加一个按钮，自动帮助别人（单人没组的情况）」：同下面设置里的「换层求助自动拉（没组队时）」（autoHelp），
    --   放到「我想换一层」这一行最右边，一眼看得到、一下就开关；开 = 顺带打开「我愿意帮」
    p.ahBtn = btn(body, "", 140, 24, nil, function()
        local on = not (LY.DB().autoHelp == true and LY.DB().helper)
        if on then LY.DB().helper = true end
        LY.SetAuto("autoHelp", on); LY.Beat(true); p.refreshNow()
    end)
    p.ahBtn:SetPoint("TOPRIGHT", body, "TOPLEFT", 12 + CARD_W, y - 3)
    p.ahBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine(L("我没组队时，别人求换层直接邀请（不弹框）；队伍 / 战斗 / 副本里不拉", "When solo, invite layer requests without a popup"), 1, 1, 1)
        GameTooltip:Show()
    end)
    p.ahBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.hopSt:SetWordWrap(false)   -- 11-22 用户「看着像错位闪动」：倒计时每秒刷，折成两行就压到下面的额度卡片
    y = y - 36
    p.gHd = body:CreateFontString(nil, "OVERLAY", "GameFontNormal"); p.gHd:SetPoint("TOPLEFT", 12, y)
    y = y - 20
    p.cardsY = y
    p.cards = {}
    for i = 1, MAX_CARDS do p.cards[i] = mkCard(body, p); p.cards[i]:Hide() end
    p.unknown = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); p.unknown:SetWidth(CARD_W); p.unknown:SetJustifyH("LEFT")
    -- 11-06 用户「位面不分地图吧」「为啥他们我就无法让他们邀请我呢」：别的图的会员也能拉你（位面整块大陆共用），一人一行 +「请他拉我」
    p.oHd = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.oHd:SetText(L("别的图的公会会员", "Guildmates on other maps"))
    -- 11-08 用户「下面的为啥在表格外，却能换？」：层码按地图各算各的，别的图的会员看不出在你这张图的第几层（对得上的已经并进上面卡片）；
    --   但进他的队就到他那层，所以照样能换 → 标题下一行写清楚
    p.oSub = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); p.oSub:SetWidth(CARD_W); p.oSub:SetJustifyH("LEFT")
    p.oSub:SetText(L("层码按地图各算各的，看不出他们在你这里的第几层；但进他的队就到他那层，所以一样能拉你换层", "Layer codes differ per map, so their layer here is unknown - but joining their group still moves you to their layer"))
    p.oRows = {}
    for i = 1, 4 do   -- 按地图一行，最多 4 张图（人多的图排前面）
        local r = CreateFrame("Frame", nil, body, BackdropTemplateMixin and "BackdropTemplate" or nil); r:SetSize(CARD_W, 30)
        if r.SetBackdrop then
            pcall(r.SetBackdrop, r, BD)
            r:SetBackdropColor(0.06, 0.06, 0.08, 0.88); r:SetBackdropBorderColor(0.28, 0.28, 0.30, 0.9)
        end
        r.bar = r:CreateTexture(nil, "ARTWORK"); r.bar:SetPoint("TOPLEFT", 1, -1); r.bar:SetPoint("BOTTOMLEFT", 1, 1); r.bar:SetWidth(4)
        r.bar:SetColorTexture(0.55, 0.55, 0.60, 1)
        r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.t:SetPoint("LEFT", 14, 0); r.t:SetWidth(CARD_W - 120); r.t:SetJustifyH("LEFT")
        r.b = btn(r, L("请他们拉我", "Ask to pull"), 96, 22, "normal", function()
            if not LH.PickHelper(r.list) then return end
            local who, why, detail = LH.AskChain(nil, r.list)
            okMsg(who ~= nil, why, string.format(L("已请 %s 拉你：他一邀请你就自动进队；换了层自动退队，25 秒没换说明本来同层；30 秒没邀请会自动换人", "Asked %s to invite you; auto-asks someone else after 30 sec"), tostring(who)), detail)
            p.refreshNow()
        end)
        r.b:SetPoint("RIGHT", -10, 0)
        r.b:SetScript("OnEnter", function(self) askTip(self, r.list, nil, "") end)
        r.b:SetScript("OnLeave", hideTip)
        r:Hide()
        p.oRows[i] = r
    end
    p.empty = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); p.empty:SetWidth(CARD_W); p.empty:SetJustifyH("LEFT")   -- 文字每次刷新时写（11-19 删掉建页时那句从来显示不出来的）

    p.bHd = body:CreateFontString(nil, "OVERLAY", "GameFontNormal"); p.bHd:SetText(L("做任务推荐", "Quest tip"))
    p.bNote = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); p.bNote:SetWidth(CARD_W - 110); p.bNote:SetJustifyH("LEFT")
    p.bGo = btn(body, L("换过去", "Go"), 84, 22, "normal", function()
        if not p.bestZ then return end
        local ok, why, detail = LH.Request(p.bestZ)
        okMsg(ok, why, L("已求助那一层的公会会员 / 插件用户，有人拉你就自动进队", "Asked helpers on that layer"), detail)
        p.refreshNow()
    end)
    p.sHd = body:CreateFontString(nil, "OVERLAY", "GameFontNormal"); p.sHd:SetText(L("设置（都能关）", "Settings"))
    p.checks = {}
    local D = LY.DB
    -- 11-19 内存（主插件登录没余量）：几个开关的读写共用两个小工厂，少几份函数体
    local function own(k) return function(v) D()[k] = v; if type(D().giAuto) == "table" then D().giAuto[k] = nil end end end   -- 11-18 自己改过 = 不再算公会自动开的
    local function offGet(k) return function() return D()[k] ~= false end end   -- false = 关，nil = 开
    local function offSet(k) return function(v) if v then D()[k] = nil else D()[k] = false end end end
    p.checks[1] = check(body, 10, 0, L("我愿意帮公会会员换层", "Help guildmates switch layers"),
        function() return D().helper end, function(v) D().helper = v; LY.Beat(true) end)
    p.checks[2] = check(body, 310, 0, L("换层求助自动拉（没组队时）", "Auto-invite requests when solo"),
        function() return D().autoHelp end, own("autoHelp"))
    -- 11-22 autoLeave 还是 nil（没问过）时显示没勾：说明写清楚「没设过的第一次换成后会问」，不是「不退」（默认值不动）
    p.checks[3] = check(body, 10, 0, L("换过去后自动退队（没设过的：第一次换成后问你）", "Leave the group after the move (unset = asked once)"),
        function() return D().autoLeave end, own("autoLeave"))
    p.checks[4] = check(body, 310, 0, L("会长 / 官员的组队邀请自动接受", "Auto-accept leader / officer invites"),
        function() return D().autoAccept end, own("autoAccept"))
    -- GI-201「自动添加GIForeverLY频道能不能加个开关」：默认开；关了退出频道，位面只和公会会员互通
    p.checks[#p.checks + 1] = check(body, 10, 0, L("加入公共频道（关了只和公会会员互通）", "Join public channel (off = guild only)"),
        function() return D().pub end, function(v) LY.SetPub(v); p.refreshNow() end)
    -- 11-17 用户「这些弹出的功能都确保能永久关闭」：位面自己冒出来的三样（换层求助弹框 / 换层屏幕提示 / 会长不同层提示条）都能在这里关，
    --   存档 layer.hopPop / layer.flash / layer.leadBar（false = 关，nil = 开），弹框上「不再弹」、提示条右键、「窗口与提醒」读写同一份
    p.checks[#p.checks + 1] = check(body, 10, 0, L("别人求我拉他换层时弹框问", "Prompt when someone asks to join my layer"),
        offGet("hopPop"), offSet("hopPop"))
    p.checks[#p.checks + 1] = check(body, 10, 0, L("位面提示也在屏幕上方出一行字（换层 / 求助结果）", "Layer notices as on-screen text (layer change / results)"),
        offGet("flash"), offSet("flash"))
    p.checks[#p.checks + 1] = check(body, 10, 0, L("集合时提示「你和会长不在同一层」", "Bar when I'm not on the leader's layer (gathering)"),
        offGet("leadBar"), function(v) offSet("leadBar")(v); if LG and LG.UpdateBar then pcall(LG.UpdateBar) end end)
    -- 11-06 用户「这个有个默认开关，关了就不扫描和发布了」：总开关排第一个（默认开）；关了不读怪、不发心跳、不帮人
    table.insert(p.checks, 1, check(body, 10, 0, L("开启位面识别（关了就不扫描、不发布）", "Layer detection on (off = no scanning, no broadcasting)"),
        function() return D().on end, function(v) D().on = v and true or false; LY.SyncPub(); if v then LY.Beat(true) end; p.refreshNow() end))

    p.refreshNow = function() LY.dirty = true; if p.refreshView then p.refreshView() end end
    p.refreshView = function()
        local m, z = LY.Mine()
        if m and z then
            local no = LY.LayerNo(m, z)
            p.me:SetText(ns.EnSafe(string.format(L("我现在：%s · %s%s|r", "Me: %s - %s%s|r"), LY.MapName(m), hex(layerRGB(no)), LY.LayerName(m, z))))
            p.meCode:SetText(L("层码 ", "code ") .. LY.Tail(z))
            p.meHint:SetText("|cff999999" .. L("「第几层」按这张图在用的层码从小到大编，公会会员之间一致；不是官方层号", "Numbered by layer code; not official") .. "|r")
        else
            p.me:SetText(ns.EnSafe(string.format(L("我现在：%s · 还没认出在哪层", "Me: %s - layer unknown"), LY.MapName(m))))
            p.meCode:SetText("")
            p.meHint:SetText("|cffffcc00" .. L("鼠标指一下附近任意一只 NPC / 怪就能认出你在哪层", "Mouse over any nearby NPC to read your layer") .. "|r")
        end
        -- 11-19 LH.GuildByLayer / GuildElsewhere / LastText / Current 搬进了按需加载的 _LayerUI → 先加载（原来在下面公共频道那块前才加载）
        if not ns.LayerPub and not rawget(p, "pubTried") then p.pubTried = true; pcall((C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn, "GearInsight_Forever_LayerUI") end
        local why = LH.Blocked()
        local pend, last = LH.pending, LH.last
        local tn = GetTime and GetTime() or 0
        if pend and pend.joinedAt then
            -- 11-09「怎么判断是不是换成功了」：进队后写清楚在确认什么、怎么加快
            local who = (pend.leader or pend.helper) and tostring(pend.leader or pend.helper):gsub("%-.*$", "") or askWho()
            -- 11-23：亲眼读到队长那层才算换成，最多等 CONFIRM 秒（不再按队长报的层推断）→ 写出最多还等几秒、先别退队
            local left = math.max(0, math.ceil(LH.CONFIRM - (tn - pend.joinedAt)))
            p.hopSt:SetText("|cffffcc00" .. string.format(L("已进 %s 的队，先别退队：等插件亲眼读到新层（最多 %d 秒）· 指一下附近 NPC / 怪更快", "Joined %s - stay; confirming layer (up to %ds), mouse over an NPC"), who, left) .. "|r")
        elseif pend and tn - pend.t < LH.ACCEPT_WIN then
            -- 11-08「我到底切换了没」：等待中写清楚在等谁、还剩几秒；结果出来写结果
            local who = pend.helper and tostring(pend.helper):gsub("%-.*$", "") or askWho()
            p.hopSt:SetText("|cffffcc00" .. string.format(L("等 %s 邀请你（还剩 %d 秒）", "Waiting for %s to invite you (%ds)"), who, math.max(0, math.ceil(LH.ACCEPT_WIN - (tn - pend.t)))) .. "|r")
        elseif last and tn - last.t < 120 then
            p.hopSt:SetText((last.ok and "|cff33ff66" or "|cffff7766") .. ((LH.LastText and LH.LastText()) or last.text) .. "|r")   -- 11-14 按当前编号重算
        else
        p.hopSt:SetText(why and ((why == "pending" and "|cffffcc00" or "|cff999999") .. (WHY[why] or why) .. (why == "cooldown" and ("（" .. LH.CooldownLeft() .. " 秒）") or "") .. "|r")
            or ("|cff33ff66" .. L("可以求助：别的层的公会会员会拉你过去", "Ready") .. "|r"))
        end
        -- 11-12：在队里 / 正在确认时也能点：点了告诉你「已经换过来了」或「正在确认，别重复求助」（不会再发求助）
        p.hop:SetEnabled(not why or why == "confirming" or why == "ingroup")
        local ah = LY.DB().autoHelp == true and LY.DB().helper
        p.ahBtn:SetText(ah and L("|cff33ff66自动帮别人：开|r", "|cff33ff66Auto-help: ON|r") or L("|cff999999自动帮别人：关|r", "|cff999999Auto-help: OFF|r"))
        for _, cb in ipairs(p.checks) do cb:SetChecked(cb.get() and true or false) end

        local _, _, groups, unknown = (LH.GuildByLayer or function() return nil, nil, {}, {} end)()
        -- 11-06 跨地图对照表：别的图的会员 → 我这张图上的层码（对不上 = nil）
        local farPeers = LH.GuildElsewhere and LH.GuildElsewhere() or {}
        local farByZ = {}
        for _, peer in ipairs(farPeers) do
            peer._zz = (m and peer.z) and LY.XOnMap(peer.m, peer.z, m) or nil
            if peer._zz then farByZ[peer._zz] = farByZ[peer._zz] or {}; table.insert(farByZ[peer._zz], peer) end
        end
        p.gHd:SetText(ns.EnSafe(string.format(L("%s 的位面（装了插件的公会会员）", "Layers in %s (guildmates with the addon)"), LY.MapName(m))))
        local y = p.cardsY
        local shownG = {}
        for _, g0 in ipairs(groups) do
            if g0.mine or #g0.members > 0 or #(farByZ[g0.z] or {}) > 0 then shownG[#shownG + 1] = g0 end
        end
        for i, c in ipairs(p.cards) do
            local g = shownG[i]
            -- 11-08 用户「0 人的为啥还显示」：没有会员的层不出卡片（我这层照样显示）
            if g then
                local col = layerRGB(g.no)
                local n = #g.members + (g.mine and 1 or 0)
                c.title:SetText(string.format("%s%s|r  |cffcccccc%d %s|r", hex(col), g.name, n, L("人", "")))
                c.code:SetText(L("层码 ", "code ") .. LY.Tail(g.z))
                c.tag:SetText(g.mine and ("|cff33ff66" .. L("你在这里", "You are here") .. "|r")
                    or ((g.known and #g.members == 0) and ("|cff888888" .. L("你来过 · 现在没有公会会员", "visited - no guildmates now") .. "|r") or ""))
                c.bar:SetColorTexture(col[1], col[2], col[3], 1)
                if c.SetBackdropColor then
                    if g.mine then c:SetBackdropColor(col[1] * 0.18, col[2] * 0.18, col[3] * 0.18, 0.92); c:SetBackdropBorderColor(col[1], col[2], col[3], 0.9)
                    else c:SetBackdropColor(0.06, 0.06, 0.08, 0.88); c:SetBackdropBorderColor(0.28, 0.28, 0.30, 0.9) end
                end
                local parts, helper = {}, nil
                if g.mine then parts[1] = "|cff33ff66" .. L("我", "me") .. "|r" end
                local shown = 0
                for _, peer in ipairs(g.members) do
                    if shown < 6 then
                        parts[#parts + 1] = classHex(peer.cl) .. peer.name .. "|r" .. (peer.lv and ("|cff999999 " .. peer.lv .. "|r") or "")
                            .. (peer.party and ("|cff66ccff " .. L("同队", "party") .. "|r") or "") .. peerNote(peer)
                            .. ((peer.hc or 0) > 0 and ("|cff888888 · " .. string.format(L("帮过 %d 次", "helped %d"), peer.hc) .. "|r") or "")
                        shown = shown + 1
                    end
                    if not helper and peer.hp then helper = peer.name end
                end
                if #g.members > shown then parts[#parts + 1] = string.format("|cff999999" .. L("等 %d 人", "+%d more") .. "|r", #g.members - shown) end
                -- 跨地图对照表对上的别的图会员：「别的图也在这层：暴风城 2」
                local fl = farByZ[g.z] or {}
                if #fl > 0 then
                    local cnt, order = {}, {}
                    for _, peer in ipairs(fl) do
                        if not cnt[peer.m] then cnt[peer.m] = 0; order[#order + 1] = peer.m end
                        cnt[peer.m] = cnt[peer.m] + 1
                    end
                    local seg = {}
                    for k = 1, math.min(3, #order) do seg[k] = LY.MapName(order[k]) .. " " .. cnt[order[k]] end
                    parts[#parts + 1] = "|cff888888" .. L("别的图也在这层：", "Also on this layer: ") .. table.concat(seg, "、") .. "|r"
                end
                c.list, c.z = (not g.mine) and g.members or {}, g.z
                c.farList = (not g.mine) and fl or {}
                local anyHp = false
                for _, peer in ipairs(c.list) do if peer.hp then anyHp = true end end
                for _, peer in ipairs(c.farList) do if peer.hp then anyHp = true end end
                if c.go.SetText then c.go:SetText(anyHp and L("过去", "Go") or L("请他帮忙", "Ask")) end
                if g.mine and #parts == 1 then parts[2] = "|cff888888" .. L("这层暂时没有别的公会会员", "no other guildmates on this layer yet") .. "|r" end
                c.names:SetText(ns.EnSafe(table.concat(parts, "   ")))
                c.helper = (not g.mine) and (helper or (g.members[1] and g.members[1].name) or (fl[1] and fl[1].name)) or nil
                local canGo = not g.mine and (#c.list + #c.farList) > 0
                c.go:SetShown(canGo)   -- 「你来过」但现在没会员的层：没人能拉你，不出按钮
                c.go:SetEnabled(canGo and not why)
                local h = math.max(52, 36 + (tonumber(c.names:GetStringHeight()) or 14))
                c:SetHeight(h)
                c:ClearAllPoints(); c:SetPoint("TOPLEFT", p.body, "TOPLEFT", 12, y)
                c:Show()
                y = y - h - 6
            else
                c.helper = nil
                c:Hide()
            end
        end
        if #unknown > 0 then
            local names = {}
            for k = 1, math.min(8, #unknown) do names[k] = unknown[k].name end
            p.unknown:SetText(string.format(L("还没认出层（%d 人）：%s", "Layer unknown (%d): %s"), #unknown, table.concat(names, "、")))
            p.unknown:ClearAllPoints(); p.unknown:SetPoint("TOPLEFT", p.body, "TOPLEFT", 14, y); p.unknown:Show()
            y = y - 20
        else p.unknown:Hide() end
        local others = 0
        for _, g in ipairs(groups) do others = others + #g.members end
        local onlyMe = others == 0   -- 11-06 来过的层也列出来了 → 按「有没有别的会员」判断空状态
        -- 11-06 用户「公会有人已经装了，为啥看不到」：空状态后面写清楚收到了几个会员的位面信号、都在哪张图（同图才进卡片）
        -- 11-22 用户「字多，不用都展示」：不再逐图列人数（下面「别的图的公会会员」已经列了），一个都没收到时才多说一句
        local diag = #LY.Peers("guild") == 0 and L("最近 2 分钟没收到任何公会会员的位面信号：对方要是 0.7.0、并且在线。", "No guildmate layer signals in the last 2 min (they need 0.7.0 and be online).") or ""
        p.empty:SetText(L("同图还没有其他公会会员（公会会员也装了插件、指过一只怪才看得到）。", "No other guildmates on this map yet. ") .. diag)
        p.empty:SetShown(onlyMe and #unknown == 0)
        if p.empty:IsShown() then
            p.empty:ClearAllPoints(); p.empty:SetPoint("TOPLEFT", p.body, "TOPLEFT", 14, y)
            y = y - math.max(14, tonumber(p.empty:GetStringHeight()) or 14) - 10
        end

        local byMap, far = {}, {}
        local myZ = LY.Confirmed() and select(2, LY.Mine()) or nil
        for _, peer in ipairs(farPeers) do
            local st = (peer._zz and myZ and peer._zz == myZ) and "same" or (peer._zz and ("z" .. peer._zz)) or "?"
            local key = tostring(peer.m) .. "|" .. st
            if st ~= "?" then key = nil end
            local e = key and byMap[key]
            if key and not e then e = { m = peer.m, st = st, zz = peer._zz, list = {} }; byMap[key] = e; far[#far + 1] = e end
            if e then e.list[#e.list + 1] = peer end
        end
        -- 别的层的排前面（找他有用），对不上的其次，和我同层的放最后；同档按地图固定排（11-21 不再按人数排，人数一变顺序就跳）
        local rank = function(e) return e.st == "same" and 2 or (e.st == "?" and 1 or 0) end
        table.sort(far, function(a, b)
            if rank(a) ~= rank(b) then return rank(a) < rank(b) end
            return a.m < b.m
        end)
        p.oHd:SetShown(#far > 0); p.oSub:SetShown(#far > 0)
        if #far > 0 then
            y = y - 8
            p.oHd:ClearAllPoints(); p.oHd:SetPoint("TOPLEFT", p.body, "TOPLEFT", 12, y); y = y - 18
            p.oSub:ClearAllPoints(); p.oSub:SetPoint("TOPLEFT", p.body, "TOPLEFT", 14, y)
            y = y - math.max(12, tonumber(p.oSub:GetStringHeight()) or 12) - 6
        end
        for i, r in ipairs(p.oRows) do
            local e = far[i]
            if e then
                r.list = e.list
                r.who = e.list[1].name
                local names = {}
                for k = 1, math.min(4, #e.list) do
                    local pe = e.list[k]
                    names[k] = classHex(pe.cl) .. pe.name .. "|r" .. ((pe.hc or 0) > 0 and ("|cff888888 · " .. string.format(L("帮过 %d 次", "helped %d"), pe.hc) .. "|r") or "")
                end
                local tag = ""
                if e.st == "same" then tag = "|cff888888" .. L("和你同层", "same layer as you") .. "|r  "
                elseif e.zz then local no = LY.LayerNo(m, e.zz); tag = hex(layerRGB(no)) .. LY.LayerName(m, e.zz) .. "|r  " end
                r.t:SetText(ns.EnSafe(string.format("|cffffd100%s|r  %s|cffcccccc%d %s|r  %s%s", LY.MapName(e.m), tag, #e.list, L("人", ""),
                    table.concat(names, "、"), #e.list > 4 and ("|cff999999 " .. string.format(L("等 %d 人", "+%d"), #e.list - 4) .. "|r") or "")))
                if r.b.SetText then r.b:SetText(e.st == "same" and L("和你同层", "Same layer") or L("请他们拉我", "Ask to pull")) end
                r.b:SetEnabled(e.st ~= "same" and not why and true or false)   -- 同层：找他没用；没开帮忙也能请（他那边弹框）
                r:ClearAllPoints(); r:SetPoint("TOPLEFT", p.body, "TOPLEFT", 12, y); r:Show()
                y = y - 34
            else
                r.who = nil; r:Hide()
            end
        end

        -- 11-19 用户「同图其他玩家也列出来」「分开列出」：公共频道那一块 + 按钮上的倒计时都在按需加载的 GearInsight_Forever_LayerUI（LayerPub.lua），
        --   第一次刷新位面页才加载（主插件登录内存没余量）；没装那个文件夹 = 不出这块，其余照旧
        if ns.LayerPub then y = ns.LayerPub.Refresh(p, y, m, why) end

        y = y - 8
        p.bHd:ClearAllPoints(); p.bHd:SetPoint("TOPLEFT", p.body, "TOPLEFT", 12, y)
        local _, best = (LH.Current or function() end)()
        p.bestZ = best and best.z or nil
        if best then
            p.bNote:SetText(ns.EnSafe(string.format(L("建议换到 %s：那层你的任务怪多（%d 只）、抢的人少（同任务 %d 人）", "Try %s: more of your quest mobs (%d), fewer competitors (%d)"),
                LY.LayerName(m, best.z), best.T, best.C)))
        else
            p.bNote:SetText("|cff999999" .. L("现在这层就行（没有明显更好的层）。只看任务怪，不管采集 / 稀有 / 首领。", "Your layer is fine for your quests right now.") .. "|r")
        end
        p.bNote:ClearAllPoints(); p.bNote:SetPoint("TOPLEFT", p.body, "TOPLEFT", 14, y - 20)
        p.bGo:ClearAllPoints(); p.bGo:SetPoint("TOPLEFT", p.body, "TOPLEFT", 12 + CARD_W - 84, y - 16)
        p.bGo:SetShown(best ~= nil and not why)
        y = y - 48
        p.sHd:ClearAllPoints(); p.sHd:SetPoint("TOPLEFT", p.body, "TOPLEFT", 12, y)
        y = y - 20
        for k, cb in ipairs(p.checks) do
            local row = math.floor((k - 1) / 2)
            cb:ClearAllPoints(); cb:SetPoint("TOPLEFT", p.body, "TOPLEFT", (k % 2 == 1) and 10 or 310, y - row * 24)
        end
        y = y - math.ceil(#p.checks / 2) * 24 - 4
        if p.body.SetHeight then p.body:SetHeight(-y + 8) end
        p.contentBottom = y
    end
    LY.OnTick(function()
        if not p:IsShown() then return end
        -- 等待中 / 冷却中每秒刷一次倒计时
        if LY.dirty or LH.pending or (LH.CooldownLeft and LH.CooldownLeft() > 0) then LY.dirty = false; p.refreshView() end
    end)
    LG.page = p
end

local function refresh(p) if p.refreshView then p.refreshView() end end

-- 11-06 用户截图「放到右边」：位面不出左侧页签，改成主面板右外侧和「公会」「组队」一排的页签（hiddenTab：页还在，/gi layer 照样能跳）
ns.RegisterPage({ key = "layer", order = 3.75, title = ns.L("位面", "Layers"), tabTitle = ns.L("位面", "Layers"), hiddenTab = true,
    icon = "Interface\\Icons\\Spell_Arcane_PortalOrgrimmar", hold = true, build = build, refresh = refresh })

local function ensureSideTab()
    local host = _G.GearInsightForeverMain
    local W = ns.W or _G.GIWidgets
    if not (host and W and W.SideTab) or rawget(host, "_giLayerTab") then return end
    local b = W.SideTab(host, ns.L("位面", "Layers"), "Interface\\Icons\\Spell_Arcane_PortalOrgrimmar", -80)
    host._giLayerTab = b
    local lp; for _, pg in ipairs(ns._Pages or {}) do if pg.key == "layer" then lp = pg end end
    markTab(lp and lp.frame and lp.frame:IsShown())
    -- 11-06 用户「位面有BUG，点了直接关了」：ToggleMain(key) 在面板开着且已停在这一页时会关面板 → 已经在位面页就不动
    b:SetScript("OnClick", function()
        local host2 = _G.GearInsightForeverMain
        if host2 and host2:IsShown() and ns.db and ns.db.ui and ns.db.ui.page == "layer" then return end
        if ns.ToggleMain then ns.ToggleMain("layer") end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(ns.L("位面", "Layers"), 1, 0.82, 0)
        GameTooltip:AddLine(ns.L("看自己在第几层、同图公会会员在哪层；公会会员互相拉一下就能换层", "See your layer and guildmates' layers; pull each other across"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if ns.LayoutSideTabs then pcall(ns.LayoutSideTabs, host) end
    if W.KeepSideTabsOnScreen then pcall(W.KeepSideTabsOnScreen, host) end
end
-- 主面板打开时（ToggleMain 里先排公会 / 组队占位页签）之后再挂，排在它们下面
local origToggle = ns.ToggleMain
if type(origToggle) == "function" then
    ns.ToggleMain = function(...)
        origToggle(...)
        pcall(ensureSideTab)
    end
end
