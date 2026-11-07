-- HOLD：右键菜单「邀请入会」（11-05 用户「右键这个功能转移到 gearinsight 上」：原来在 GuildInsight 的 WelcomeUI.lua，
--   大部分玩家只装 GearInsight → 搬进主插件，菜单小标题写「GearInsight」）
-- 聊天框右键名字 / 头像右键 → 「GearInsight」小标题下多一项「邀请入会」
--   走暴雪新菜单 Menu.ModifyMenu（官方给插件加菜单项的口子，不污染）；没这个接口的客户端什么都不做
--   只在：在公会里、有邀请权限、对方不是自己、对方不在本公会 时出现
-- ⛔ 11-05 GuildInsight 真机两次实锤：插件调 GuildInvite = ADDON_ACTION_FORBIDDEN；安全按钮 macrotext=/ginvite 也被禁；
--   只有玩家亲手在聊天框输入 /ginvite 名 姓 可以 → 这里只弹复制框，不调任何邀请接口
-- 名字：无限角色名是「名 姓」两段，菜单 ctx.name 只给「名」→ 按 ① 聊天行完整发送者 ② UnitFullName ③ GUID ④ 最近聊天见过的发送者 拼全名
-- 装了 GuildInsight 的：它看到 GearInsightForever.inviteMenu 就不再加自己那一项（避免两项）
local _, ns = ...

local IM = {}
ns.InviteMenu = IM
IM.MENU_TAGS = { "MENU_UNIT_FRIEND", "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS" }

local function secret(v) return issecretvalue and issecretvalue(v) end
local function short(n) return (tostring(n or ""):gsub("%-.*$", "")) end
local function myRealm() return GetNormalizedRealmName and GetNormalizedRealmName() or nil end

-- 名 + 第二段 → 全名：第二段 = 本服规范服务器名 → 只是服务器；否则是姓 →「名 姓」；带空格 / 「-」的视为已经是全名
local function joinName(a, b)
    if type(a) ~= "string" or a == "" or secret(a) then return nil end
    if a:find("-", 1, true) or a:find(" ", 1, true) then return a end
    if type(b) == "string" and b ~= "" and not secret(b) and b ~= myRealm() then return a .. " " .. b end
    return a
end
IM.joinName = joinName

-- 聊天发送者缓存：首段名 → 全名（去掉「-服务器」）；同一个首段对应多个全名 = 不确定，不用
IM.seen = {}
local function noteSender(full)
    if type(full) ~= "string" or full == "" or secret(full) then return end
    full = full:gsub("%-[^%-]*$", "")
    local first = full:match("^([^ ]+) ")
    if not first then return end
    local cur = IM.seen[first]
    if cur == nil then IM.seen[first] = full elseif cur ~= full then IM.seen[first] = false end
end
IM.noteSender = noteSender
do
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_CHANNEL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
                         "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_EMOTE" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, _, _, sender) pcall(noteSender, sender) end)
end

function IM.Target(ctx)
    if type(ctx) ~= "table" then return nil end
    local name, server = ctx.name, ctx.server
    if (not name or name == "") and ctx.unit and UnitName then name, server = UnitName(ctx.unit) end
    if type(name) ~= "string" or name == "" or secret(name) then return nil end
    -- ① 聊天行的完整发送者
    local full = type(ctx.chatTarget) == "string" and ctx.chatTarget ~= "" and not secret(ctx.chatTarget) and ctx.chatTarget or nil
    if full and (full:find(" ", 1, true) or full:find("-", 1, true)) then return (full:gsub("%-" .. (myRealm() or "\0") .. "$", "")) end
    -- ② 单位
    if ctx.unit and UnitFullName then
        local ok, a, b = pcall(UnitFullName, ctx.unit)
        local n = ok and joinName(a, b) or nil
        if n and n ~= name then return n end
    end
    -- ③ GUID
    local guid = ctx.guid or (ctx.playerLocation and ctx.playerLocation.GetGUID and ctx.playerLocation:GetGUID())
    if guid and GetPlayerInfoByGUID and not secret(guid) then
        local ok, _, _, _, _, _, gn, gr = pcall(GetPlayerInfoByGUID, guid)
        local n = ok and joinName(gn, gr) or nil
        if n and n ~= name then return n end
    end
    -- 菜单自己给的第二段
    local n = joinName(name, server)
    if n and n ~= name then return n end
    -- ④ 最近见过的发送者
    if IM.seen[name] then return IM.seen[name] end
    return name
end

-- 本公会名单里有没有这个人（按首段名比，名单里是「名 姓-服务器」）
local function inMyGuild(name)
    if not (GetNumGuildMembers and GetGuildRosterInfo) then return false end
    local want = short(name)
    local ok, total = pcall(GetNumGuildMembers)
    for i = 1, (ok and tonumber(total) or 0) do
        local ok2, n = pcall(GetGuildRosterInfo, i)
        if ok2 and type(n) == "string" and not secret(n) and short(n) == want then return true end
    end
    return false
end

function IM.CanInvite(ctx)
    if not (IsInGuild and IsInGuild()) then return false end
    if CanGuildInvite then
        local ok, v = pcall(CanGuildInvite)
        if ok and not v then return false end
    end
    local name = IM.Target(ctx)
    if not name then return false end
    local me = UnitName and UnitName("player")
    if me and not secret(me) and short(name) == short(me) then return false end
    if ctx.unit and UnitIsInMyGuild then
        local ok, v = pcall(UnitIsInMyGuild, ctx.unit)
        if ok and v and not secret(v) then return false end
    end
    if inMyGuild(name) then return false end
    return true
end

-- 复制框：「/ginvite 名 姓」已选中，Ctrl+C → 回车 → Ctrl+V → 回车
local box
local function mkBox()
    if box then return box end
    local f = CreateFrame("Frame", "GearInsightForeverInviteCopy", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(440, 132)
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    f:SetFrameStrata("DIALOG")
    if f.SetBackdrop then
        pcall(f.SetBackdrop, f, { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    end
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -14)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.hint:SetPoint("TOP", f.title, "BOTTOM", 0, -6); f.hint:SetWidth(410)
    f.box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.box:SetSize(360, 26); f.box:SetPoint("TOP", f.hint, "BOTTOM", 0, -10); f.box:SetAutoFocus(false)
    f.box:SetScript("OnTextChanged", function(self, user) if user then self:SetText(f.text or ""); self:HighlightText() end end)   -- 只读
    f.box:SetScript("OnEscapePressed", function() f:Hide() end)
    f.box:SetScript("OnEnterPressed", function() f:Hide() end)
    f.box:SetScript("OnKeyDown", function(_, key)
        -- Ctrl+C 复制完就收起，省得挡住聊天框
        if key == "C" and IsControlKeyDown and IsControlKeyDown() and C_Timer and C_Timer.After then C_Timer.After(0.1, function() f:Hide() end) end
    end)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetScript("OnClick", function() f:Hide() end)   -- 原生红叉走 HideUIPanel，战斗中被拦 → 直接 Hide
    close:SetPoint("TOPRIGHT", -2, -2)
    f:Hide()
    box = f
    return f
end

function IM.Invite(name)
    if type(name) ~= "string" or name == "" then return false end
    local f = mkBox()
    f.text = "/ginvite " .. name
    f.title:SetText(string.format(ns.L("邀请「%s」入会", "Invite %s"), name))
    f.hint:SetText(ns.L("游戏只允许你亲手发公会邀请：Ctrl+C 复制 → 回车打开聊天框 → Ctrl+V → 回车", "Ctrl+C, then Enter, Ctrl+V, Enter in chat"))
    f.box:SetText(f.text)
    f:Show(); f.box:SetFocus(); f.box:HighlightText()
    IM.last = name
    for _, p in ipairs(IM.pending) do if not p.done and p.name == name then p.at = 0; return true end end
    IM.pending[#IM.pending + 1] = { name = name, at = 0, done = false }
    return true
end

-- ---------- 回执（11-05 用户「邀请失败时直接提示原因」；翻译表与公会插件会话 GuildInviteMenu.lua / GuildInsight InviteDiag 同一套）----------
-- 玩家亲手发 /ginvite 后听系统消息：成功 / 找不到 / 已在公会 / 已被邀请 / 拒绝 / 自动拒绝 / 不同阵营 / 没权限 → 聊天框说人话
-- 复制框模式：玩家可能没发，2 分钟没动静就安静丢掉，不报「没回执」
local function toPattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local p = fmt:gsub("%%%d?%$?s", "")
    p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    p = p:gsub("", "(.-)")
    return "^" .. p .. "$"
end
local FAIL = {
    { "ERR_GUILD_PLAYER_NOT_FOUND_S", "找不到这个玩家：名字不对或对方不在线（无限的角色名是「名 姓」，要写全）", "Player not found (wrong name or offline)" },
    { "ERR_CHAT_PLAYER_NOT_FOUND_S", "找不到这个玩家：名字不对或对方不在线", "Player not found" },
    { "ERR_ALREADY_IN_GUILD_S", "对方已经在一个公会里了", "Already in a guild" },
    { "ERR_ALREADY_INVITED_TO_GUILD_S", "对方已经收到别的公会邀请，等他先处理", "Already invited to a guild" },
    { "ERR_GUILD_DECLINE_S", "对方拒绝了邀请", "Declined" },
    { "ERR_GUILD_DECLINE_AUTO_S", "对方设置了自动拒绝公会邀请", "Auto-declined" },
    { "ERR_GUILD_NOT_ALLIED", "对方和你不是同一阵营", "Not the same faction" },
    { "ERR_GUILD_PERMISSIONS", "你没有邀请权限（会长 / 有邀请权限的官员才能邀请）", "No invite permission" },
    { "ERR_GUILD_INTERNAL", "服务器内部错误，稍后再试", "Internal error, try again later" },
}
local OK_KEYS = { "ERR_GUILD_INVITE_S", "ERR_GUILD_INVITE_SS" }
function IM.Match(msg)
    if type(msg) ~= "string" or secret(msg) then return nil end
    for _, f in ipairs(FAIL) do
        local pat = toPattern(_G[f[1]])
        if pat and msg:match(pat) then return "fail", ns.L(f[2], f[3]) end
    end
    for _, k in ipairs(OK_KEYS) do
        local pat = toPattern(_G[k])
        if pat and msg:match(pat) then return "ok" end
    end
end
IM.WAIT = 120
IM.pending = {}
local function report(p, kind, text)
    p.done = true
    if not ns.Print then return end
    if kind == "ok" then ns.Print(string.format("|cff66dd88" .. ns.L("已向 %s 发出公会邀请", "Invite sent to %s") .. "|r" .. ns.L("，等对方点「接受」", " - waiting for accept"), p.name))
    else ns.Print(string.format("|cffff6060" .. ns.L("邀请 %s 没成功", "Invite to %s failed") .. "：|r%s", p.name, text or "")) end
end
function IM.OnSystem(msg)
    if #IM.pending == 0 then return end
    local kind, text = IM.Match(msg)
    if not kind then return end
    local hit
    for _, p in ipairs(IM.pending) do
        if not p.done then
            if hit == nil then hit = p end
            local first = p.name:match("^([^ %-]+)") or p.name
            if msg:find(first, 1, true) then hit = p; break end
        end
    end
    if hit then report(hit, kind, text) end
end
do
    local rv = CreateFrame("Frame")
    IM._rv = rv
    for _, e in ipairs({ "CHAT_MSG_SYSTEM", "UI_ERROR_MESSAGE" }) do pcall(rv.RegisterEvent, rv, e) end
    rv:SetScript("OnEvent", function(_, e, a1, a2)
        if #IM.pending == 0 then return end
        local msg = (e == "UI_ERROR_MESSAGE" and type(a1) ~= "string") and a2 or a1   -- UI 提示：新版 (id, msg)，旧版 (msg)
        pcall(IM.OnSystem, msg)
    end)
    rv:SetScript("OnUpdate", function(_, el)
        if #IM.pending == 0 then return end
        for i = #IM.pending, 1, -1 do
            local p = IM.pending[i]
            p.at = p.at + (el or 0)
            if p.done or p.at >= IM.WAIT then table.remove(IM.pending, i) end
        end
    end)
end

-- /gi ginvite 名 姓：同样弹复制框（宏 / 手动用）
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.ginvite = function(rest, rawRest)
    local n = tostring(rawRest or rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if n ~= "" then IM.Invite(n) end
end

IM.hooked = false
-- 11-06 用户「这些都是设置，有设置，默认打开」：开关 ns.db.ui.inviteMenu（nil = 默认开），设置页「公会」栏
function IM.Enabled()
    return not (ns.db and ns.db.ui and ns.db.ui.inviteMenu == false)
end
function IM.SetEnabled(on)
    if not ns.db then return end
    ns.db.ui = ns.db.ui or {}
    ns.db.ui.inviteMenu = on and true or false
end

function IM.Hook()
    if IM.hooked or not (Menu and Menu.ModifyMenu) then return false end
    for _, tag in ipairs(IM.MENU_TAGS) do
        Menu.ModifyMenu(tag, function(_, root, ctx)
            if not IM.Enabled() then return end
            local ok, can = pcall(IM.CanInvite, ctx)
            if not ok or not can then return end
            local name = IM.Target(ctx)
            if root.CreateDivider then root:CreateDivider() end
            if root.CreateTitle then root:CreateTitle("GearInsight") end
            root:CreateButton(ns.L("邀请入会", "Invite to guild"), function() IM.Invite(name) end)
        end)
    end
    IM.hooked = true
    if _G.GearInsightForever then _G.GearInsightForever.inviteMenu = true end
    return true
end
pcall(IM.Hook)
