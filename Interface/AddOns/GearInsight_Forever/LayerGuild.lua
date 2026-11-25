-- A · 公会位面（10-28，HOLD；设计稿 docs/forever-layering-addon-design-1028.md 第四节）
-- 场景：开服当晚主城集合签公会登记表 —— 不在同一层就看不见会长、签不了名。
-- 关键判断：集合不靠「换到同一层」，靠「先进会长的团」—— 暴雪明说组队会把你传到队长那一层（10-01 起建队 / 改队时队长不动）。
--   插件只让这件事更快更不乱：谁到了、谁不在会长这一层、会员一键「请会长拉我」、会长一下一个点邀请、会长 / 官员邀请自动接受。
-- 通道：建会后 = 公会插件消息；建会前 = 集合口令频道（会长 /gi layer lead 口令，会员 /gi layer join 口令）。
-- ⛔ 邀请只在按钮点击里调，一下一个（不批量、收到请求也不自动邀请）；⛔ 不自动退队 / 解散（离队可能弹回原层）。
local _, ns = ...
local LY = ns.Layer
if not LY then return end
local L = function(cn, en) return ns.L(cn, en) end

local LG = {}
ns.LayerGuild = LG
LG.NEED = 9               -- 签名人数（经典规则 9 个；装了 GuildInsight 建会助手就用它读到的）
LG.REQ_GAP = 60           -- 秒：同一个人「请会长拉我」最短间隔
LG.requests = {}          -- 会长侧：[短名] = 时间
LG.lastReq = -1e9

local function now() return (GetTime and GetTime()) or 0 end
local function me() return UnitName and UnitName("player") or "?" end

-- ---------- 会阶 ----------
LG.ranks = {}             -- [短名] = 会阶序号（公会名单）
function LG.ReadRoster()
    LG.ranks = {}
    if not (GetNumGuildMembers and GetGuildRosterInfo) then return end
    local n = GetNumGuildMembers() or 0
    for i = 1, math.min(n, 1000) do
        local ok, name, _, rankIndex = pcall(GetGuildRosterInfo, i)
        if ok and type(name) == "string" and not ns.Secret(name) then LG.ranks[LY.Short(name)] = tonumber(rankIndex) end
    end
end
function LG.MyRank()
    if not (IsInGuild and IsInGuild() and GetGuildInfo) then return nil end
    local ok, _, _, idx = pcall(GetGuildInfo, "player")
    return ok and tonumber(idx) or nil
end
function LG.IsOfficerRank(r) return r ~= nil and r <= (LY.DB().officerMax or 1) end
-- 我是不是「会长侧」（会长 / 官员 / 集合频道发起人）
function LG.AmLeader()
    if LY.gather and LY.gatherLead then return true end
    return LG.IsOfficerRank(LG.MyRank())
end

-- 会长（集合基准）：公会 = 在线的会长（会阶 0），没有就在线官员里会阶最小的；集合频道 = 发起人；我自己是会长就是我
function LG.Leader()
    if LY.gather then
        if LY.gatherLead then return { name = me(), self = true } end
        for _, p in ipairs(LY.Peers("gather")) do if p.ld then return p end end
    end
    local my = LG.MyRank()
    if my == 0 then return { name = me(), self = true } end
    local best
    for _, p in ipairs(LY.Peers("guild")) do
        local r = LG.ranks[p.name] or p.r
        if LG.IsOfficerRank(r) and (not best or r < (LG.ranks[best.name] or best.r or 9)) then best = p end
    end
    if not best and LG.IsOfficerRank(my) then return { name = me(), self = true } end
    return best
end

-- 心跳带会阶 / 集合发起人
LY.AddFields(function(t, scope)
    if scope == "guild" then t.r = LG.MyRank() end
    if scope == "gather" and LY.gatherLead then t.ld = 1 end
end)

-- 自动接受：会长 / 官员（看公会名单，不信心跳里自报的会阶）、集合频道发起人
-- 11-13：第二个返回值 "officer" = 受 autoAccept 管；autoAccept 还是 nil（没问过）时照样认出来，由 LY.AcceptReason 改成「先问一次」
LY.AddAcceptRule(function(s)
    if LY.DB().autoAccept == false then return nil end
    if LG.IsOfficerRank(LG.ranks[s]) then return L("会长 / 官员", "guild officer"), "officer" end
    local ld = LY.gather and not LY.gatherLead and LG.Leader()
    if ld and ld.name == s then return L("集合发起人", "gather leader"), "officer" end
    return nil
end)

-- ---------- 分组 ----------
-- 以会长的层为准（我是会长就以我为准）：same 同层 / other 同图别层 / unknown 还没读到层 / away 别的图
function LG.Classify(p, ref)
    if not ref or not ref.m then return "unknown" end
    if p.inst then return "away" end
    if not p.m then return "unknown" end
    if p.m ~= ref.m then return "away" end
    if not p.z or (p.c or 0) < 2 or not ref.z then return "unknown" end
    return (p.z == ref.z) and "same" or "other"
end

function LG.RefLayer()
    local ld = LG.Leader()
    if not ld then return nil, nil end
    if ld.self then
        local m, z, c = LY.Mine()
        return { name = ld.name, m = m, z = (c or 0) >= 2 and z or nil, c = c, self = true }, ld
    end
    return ld, ld
end

-- 会长视图的名单：返回 { groups = { same = {…}, other = {…}, unknown = {…}, away = {…} }, queue = {…}, sameN }
function LG.Board()
    local ref = LG.RefLayer()
    local via = LY.gather and "gather" or "guild"
    local g = { same = {}, other = {}, unknown = {}, away = {} }
    for _, p in ipairs(LY.Peers(via)) do
        if not (ref and p.name == ref.name) then   -- 会长自己不进名单（同层人数里单独加 1）
            local k = LG.Classify(p, ref)
            table.insert(g[k], p)
        end
    end
    -- 邀请队列：求拉的在前（按请求时间），再是同图别层的；跳过 60 秒内刚邀请过的、已在队伍里的
    local q, seen = {}, {}
    local function inGroup(n) return (UnitInParty and UnitInParty(n)) or (UnitInRaid and UnitInRaid(n)) end
    local reqs = {}
    for n, t in pairs(LG.requests) do
        if now() - t > 600 then LG.requests[n] = nil else reqs[#reqs + 1] = { n = n, t = t } end
    end
    table.sort(reqs, function(a, b) return a.t < b.t end)
    for _, r in ipairs(reqs) do
        if not seen[r.n] and not inGroup(r.n) then seen[r.n] = true; q[#q + 1] = { name = r.n, asked = r.t, p = LY.peers[r.n] } end
    end
    for _, p in ipairs(g.other) do
        if not seen[p.name] and not inGroup(p.name) then seen[p.name] = true; q[#q + 1] = { name = p.name, p = p } end
    end
    local sameN = #g.same + ((ref and ref.z) and 1 or 0)
    return { groups = g, queue = q, sameN = sameN, ref = ref }
end

function LG.Need()
    local gi = _G.GuildInsight
    local F = gi and gi.Found
    if F and F.Need then local ok, n = pcall(F.Need); if ok and tonumber(n) then return tonumber(n) end end
    return LG.NEED
end

-- ---------- 会员：请会长拉我 ----------
-- 返回 nil / "nolead" / "same" / "wait" / "sent"
function LG.MyStatus()
    local ref = LG.RefLayer()
    if not ref then return "nolead" end
    if ref.self then return "lead" end
    local m, z, c = LY.Mine()
    local k = LG.Classify({ m = m, z = (c or 0) >= 2 and z or nil, c = c, inst = LY.InInstance() }, ref)
    return k, ref
end
function LG.RequestPull()
    local ref = LG.RefLayer()
    if not ref or ref.self then return "nolead" end
    if now() - LG.lastReq < LG.REQ_GAP then return "wait" end
    LG.lastReq = now()
    local m, z = LY.Mine()
    local msg = LY.Encode("Q", { to = ref.name, m = m, z = z })
    if LY.gather then LY.Queue("GATHER", msg) else LY.Queue("GUILD", msg) end
    return "sent"
end
LY.handlers.Q = function(t, s, via)
    if via ~= "guild" and via ~= "gather" then return end
    if not LG.AmLeader() then return end
    -- 发给会长的，官员也收（会长不在线时官员接手）
    LG.requests[s] = now()
    LY.dirty = true
    if LG.page and LG.page:IsShown() then return end
    ns.Print(L(s .. " 请你拉他进团（/gi layer 打开位面面板，点「邀请」）", s .. " asks to be pulled to your layer (/gi layer)"))
end

-- 会长：邀请（⛔ 只在按钮点击里调）
function LG.InviteOne(name)
    if not name then return false end
    local ok = LY.Invite(name)
    if ok then LG.requests[name] = nil; LY.dirty = true end
    return ok
end
function LG.NextInQueue()
    local b = LG.Board()
    for _, r in ipairs(b.queue) do
        local t = LY.invited[r.name]
        if not t or now() - t > 60 then return r.name end
    end
    return nil
end
function LG.ConvertToRaid()
    if IsInRaid and IsInRaid() then return "already" end
    local f = (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid
    if not f then return "noapi" end
    if not (UnitIsGroupLeader and UnitIsGroupLeader("player")) then return "notlead" end
    local ok = pcall(f)
    return ok and "ok" or "fail"
end


LY.OnEvent("GUILD_ROSTER_UPDATE", function() LG.ReadRoster() end)
LY.OnEvent("PLAYER_ENTERING_WORLD", function()
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
    LG.ReadRoster()
end)

-- ---------- 会员提示条：你和会长不在同一层 ----------
local bar
function LG.Bar()
    if bar then return bar end
    bar = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    bar:SetSize(420, 30)
    bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 30, 260)
    bar:SetFrameStrata("MEDIUM")
    bar:SetMovable(true); bar:EnableMouse(true); bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", bar.StartMoving); bar:SetScript("OnDragStop", bar.StopMovingOrSizing)
    if bar.SetBackdrop then
        bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        bar:SetBackdropColor(0.1, 0.05, 0.02, 0.9); bar:SetBackdropBorderColor(1, 0.6, 0.1, 0.9)
    end
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("LEFT", 8, 0); bar.text:SetJustifyH("LEFT")
    bar.close = ns.Button(bar, "×", 24, 20, function() LG.barHideUntil = now() + 600; bar:Hide() end)
    bar.close:SetPoint("RIGHT", -4, 0)
    -- 11-17 用户「这些弹出的功能都确保能永久关闭」：× 照旧只收 10 分钟；右键提示条 = 永久不出（存档 layer.leadBar = false，位面页设置同一个键）
    bar:SetScript("OnMouseUp", function(_, mb) if mb == "RightButton" then LG.CloseBarForGood() end end)
    bar:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L("× 收起 10 分钟  ·  右键永久关闭  ·  拖拽移动", "×: hide 10 min  ·  Right-click: close for good  ·  Drag: move"), 0.25, 0.9, 0.35, true)
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    bar.btn = ns.Button(bar, L("请会长拉我", "Ask to be pulled"), 100, 20, function()
        local r = LG.RequestPull()
        ns.Print(r == "sent" and L("已告诉会长，等他邀请（会长 / 官员的邀请会自动接受）", "Sent - wait for the invite")
            or r == "wait" and L("刚请求过，等一下", "Just asked - please wait") or L("会长不在线", "Leader not online"))
    end)
    bar.btn:SetPoint("RIGHT", bar.close, "LEFT", -4, 0)
    bar:Hide()
    return bar
end
LG.barHideUntil = -1e9
function LG.BarOn() return not (ns.db and type(ns.db.layer) == "table" and ns.db.layer.leadBar == false) end
function LG.SetBarOn(v)
    if v then LY.DB().leadBar = nil else LY.DB().leadBar = false end
    if not v and bar then bar:Hide() end
end
function LG.CloseBarForGood()
    if GameTooltip then GameTooltip:Hide() end
    LG.SetBarOn(false)
    if ns.CloseHint then
        ns.CloseHint("layerLeadBar", L("「你和会长不在同一层」提示条已永久关闭。找回：GI 菜单 → 窗口与提醒 → 会长不同层提示条，或位面页设置",
            "Leader-layer bar closed for good. Bring it back: GI menu > Windows & alerts > Leader layer bar, or the Layers tab"))
    end
end
function LG.UpdateBar()
    -- 11-18 卡顿 / 内存：这条每秒跑一次，原来不管提示条能不能显示都先算「会长在哪层」（建全部在线 peer 的名单再排序）。
    --   提示条只在开服集合口令频道开着时显示 → 没开集合频道时只做原来算的时候顺带的事：会阶不是 0 时清一遍过期 peer
    --   （原来 LG.Leader 走 LY.Peers("guild") 会清；会阶 0 = 我就是会长，原来也不走那里），然后照旧收起提示条
    if not LY.gather then
        if LG.MyRank() ~= 0 then LY.Prune() end
        if not LG.BarOn() then if bar then bar:Hide() end; return end
        LG.Bar():Hide()
        return
    end
    local k, ref = LG.MyStatus()
    if not LG.BarOn() then if bar then bar:Hide() end; return end
    local b = LG.Bar()
    -- 11-06 公会早建好了，练级时会长在哪层无所谓：「你和会长不在同一层」只在开服集合口令频道开着时提示
    if LY.gather and k == "other" and ref and now() >= LG.barHideUntil then
        local m, z = LY.Mine()
        b.text:SetText(ns.EnSafe(string.format(L("|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:14|t 你和会长不在同一层（%s 在 %s · 你在 %s）", "You're on a different layer from %s (%s vs you %s)"),
            ref.name, LY.Label(ref.m, ref.z), LY.Label(m, z))))
        b:Show()
    else
        b:Hide()
    end
end
LY.OnTick(function() if LY.DB().on then LG.UpdateBar() end end)

-- 11-17「这些弹出的功能都确保能永久关闭」：右键关掉的提示条从设置页「窗口与提醒」找回（位面识别开着才有）
if ns.RegisterWindow then ns.RegisterWindow({ key = "layerLeadBar", order = 76, title = function() return L("会长不同层提示条", "Leader layer bar") end,
    avail = function() return LY.DB().on ~= false end,
    state = function()
        if not LG.BarOn() then return L("已关闭", "Closed") end
        return L("开服集合时你和会长不在同一层才出", "Shows during guild gathering when you're not on the leader's layer")
    end,
    actions = function()
        local on = LG.BarOn()
        return { { text = on and L("关闭", "Turn off") or L("打开", "Turn on"), fn = function() LG.SetBarOn(not on) end } }
    end }) end
