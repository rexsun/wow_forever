-- HOLD：右侧「公会」拆成两个子页签 —— 本公会 / 公会招募（10-18 用户截图「公会拆两个，一个本公会，一个公会招募，
--   本公会展示公会内专业情况（帮我看看是否需要安装插件）」）。
-- 专业数据两路，页面上写明每条来自哪：
--   ① 游戏自带「公会专业」（GetNumGuildTradeSkill / GetGuildTradeSkillInfo）—— 不用装插件、全员可见。
--      ⛔ 10-18 查《无限》Wow.exe：这组接口名都在，但经典服务器不一定下发数据（经典怀旧服就是空的）→ 读到 0 行就当不可用
--   ② 插件互相同步：装了 GI 的会员登录 / 专业变化时在公会插件频道发自己的专业（PREFIX GIFgh），别人点开本公会时问一次。
--      存档按公会名分开，离线的人也能看到上次同步的。
-- ⛔ 共享的 GIWidgets.lua 不改；招募抽屉（GuildTab.lua）的点击逻辑一行不改：只在「公会」页签上挂 PreClick / OnClick 钩子切换。
local _, ns = ...; ns = _G.GearInsightForever or ns  -- 10-18 拆成按需加载的子插件：用主插件的命名空间（_G.GearInsightForever），子插件自己的 ... 是张新表
local L = ns.L

local GH = {}
ns.GuildHome = GH

local PREFIX = "GIFgh"
local DW = 430
local SUB_W, SUB_H, SUB_GAP = 86, 24, 4
local ICON = {
    herbalism = "Trade_Herbalism", mining = "Trade_Mining", skinning = "INV_Misc_Pelt_Wolf_01", alchemy = "Trade_Alchemy",
    blacksmithing = "Trade_BlackSmithing", enchanting = "Trade_Engraving", engineering = "Trade_Engineering",
    leatherworking = "INV_Misc_ArmorKit_17", tailoring = "Trade_Tailoring", cooking = "INV_Misc_Food_15",
    firstaid = "Spell_Holy_SealOfSacrifice", fishing = "Trade_Fishing",
}
local CODE = { herbalism = "he", mining = "mi", skinning = "sk", alchemy = "al", blacksmithing = "bs", enchanting = "en",
    engineering = "eg", leatherworking = "lw", tailoring = "ta", cooking = "co", firstaid = "fa", fishing = "fi" }
local KEY = {}
for k, c in pairs(CODE) do KEY[c] = k end

local function now() return GetTime and GetTime() or 0 end
local function secret(v) return ns.Secret and ns.Secret(v) end
local function short(n) return type(n) == "string" and (n:match("^([^%-]+)") or n) or nil end
local function inGuild() return IsInGuild and IsInGuild() and true or false end
local function guildName()
    if not GetGuildInfo then return nil end
    local ok, g = pcall(GetGuildInfo, "player")
    if ok and type(g) == "string" and not secret(g) and g ~= "" then return g end
end
local function store()
    ns.db.guildProfs = ns.db.guildProfs or {}
    local g = guildName()
    if not g then return nil end
    ns.db.guildProfs[g] = ns.db.guildProfs[g] or {}
    return ns.db.guildProfs[g]
end
GH.Store = store

-- ---------- 我的专业 → 编码 ----------
function GH.MySkills()
    if not (ns.Prof and ns.Prof.Skills) then return {} end
    local ok, s = pcall(ns.Prof.Skills)
    return ok and type(s) == "table" and s or {}
end
function GH.Encode(skills)
    local parts = {}
    for _, k in ipairs((ns.Prof and ns.Prof.ORDER) or {}) do
        local s = skills[k]
        if s and CODE[k] then parts[#parts + 1] = CODE[k] .. ":" .. (s.r or 0) .. ":" .. (s.m or 0) end
    end
    local lv = UnitLevel and UnitLevel("player") or 0
    local cls = UnitClass and select(2, UnitClass("player")) or ""
    return "P|1|" .. lv .. "|" .. (type(cls) == "string" and cls or "") .. "|" .. table.concat(parts, ",")
end
function GH.Decode(msg)
    local lv, cls, body = msg:match("^P|%d+|(%d+)|([%u]*)|(.*)$")
    if not lv then return nil end
    local p = {}
    for c, r, m in body:gmatch("(%l%l):(%d+):(%d+)") do
        if KEY[c] then p[KEY[c]] = { r = tonumber(r), m = tonumber(m) } end
    end
    return { lv = tonumber(lv), cls = cls ~= "" and cls or nil, p = p }
end

-- ---------- 发送 / 接收（公会插件频道）----------
local lastSent, lastReq, lastReply = -999, -999, -999
local function sendGuild(msg)
    if not inGuild() then return false end
    local f = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not f then return false end
    return pcall(f, PREFIX, msg, "GUILD")
end
function GH.Announce(force)
    if not force and now() - lastSent < 60 then return end
    local s = GH.MySkills()
    if not next(s) then return end
    lastSent = now()
    sendGuild(GH.Encode(s))
    -- 自己也记一份（自己发的回声有的客户端收不到）
    -- ⛔ 10-18 用户截图：《无限》角色名带姓，UnitName 只回「Clark」，公会消息的发送者是全名「Clark Insight」→ 同一个人记成两个。
    --   收到过自己的回声后记下全名（GH.SelfName），以后都记在全名下，旧的短名那条删掉
    local st, me = store(), UnitName and UnitName("player")
    if st and me and not secret(me) then
        local lv = UnitLevel and UnitLevel("player") or 0
        local key = GH.SelfName(st) or me
        if key ~= me then st[me] = nil end
        st[key] = { t = time and time() or 0, lv = lv, cls = select(2, UnitClass("player")), p = s }
    end
end

-- 自己在公会消息 / 名单里的全名（《无限》名字带姓）：存档里记过就用记过的
function GH.SelfName(st)
    local me = UnitName and UnitName("player")
    if not me or secret(me) then return nil end
    -- 10-18 探针：GetUnitName("player", true) 回全名「Clark Insight」（UnitFullName 回名 / 姓两段）
    if GetUnitName then
        local ok, full = pcall(GetUnitName, "player", true)
        if ok and type(full) == "string" and not secret(full) and full ~= "" then
            full = short(full)
            if full and full ~= me and full:sub(1, #me + 1) == me .. " " then return full end
        end
    end
    local db = ns.db and ns.db.guildSelf
    return db and db[me] or nil
end
-- 这条消息是不是自己发的：发送者 = 我的名字，或「我的名字 + 空格 + 姓」且等级 / 职业对得上
local function isSelf(who, d)
    local me = UnitName and UnitName("player")
    if not me or secret(me) or not who then return false end
    if who == me then return true end
    if who:sub(1, #me + 1) ~= me .. " " then return false end
    local lv = UnitLevel and UnitLevel("player") or 0
    local _, cls = UnitClass("player")
    return d and d.lv == lv and d.cls == cls or false
end
function GH.Request()
    if now() - lastReq < 60 then return end
    lastReq = now()
    sendGuild("R|1")
end
function GH.Handle(sender, msg)
    if type(sender) ~= "string" or type(msg) ~= "string" or secret(sender) or secret(msg) then return end
    local who = short(sender)
    if msg:sub(1, 2) == "R|" then
        -- 有人点开了本公会：随机 1-6 秒后回一次（60 秒内只回一次，别一群人同时刷屏）
        if now() - lastReply >= 60 then
            lastReply = now()
            if C_Timer and C_Timer.After then C_Timer.After(1 + math.random() * 5, function() GH.Announce(true) end) else GH.Announce(true) end
        end
        return
    end
    local d = GH.Decode(msg)
    local st = store()
    if not (d and st and who) then return end
    if isSelf(who, d) then
        local me = UnitName("player")
        if who ~= me then
            ns.db.guildSelf = ns.db.guildSelf or {}
            ns.db.guildSelf[me] = who      -- 记下全名
            st[me] = nil                   -- 短名那条是同一个人
        end
    end
    st[who] = { t = time and time() or 0, lv = d.lv, cls = d.cls, p = d.p }
    GH.dirty = true
    GH.QueueRender()   -- 有人点刷新时全公会的 GI 用户 1-6 秒内陆续回话：合并成一次重画
end

-- ---------- 游戏自带公会专业 ----------
-- 返回 { [key] = { {name, skill, online, cls}, … } }, 行数；接口不在 / 0 行 → nil
function GH.ReadOfficial()
    if not (GetNumGuildTradeSkill and GetGuildTradeSkillInfo) then return nil, 0 end
    local ok, n = pcall(GetNumGuildTradeSkill)
    n = ok and tonumber(n) or 0
    if n <= 0 then return nil, 0 end
    -- 折叠的专业先展开（展开后行数会变，重读一次）
    local expanded = false
    for i = 1, n do
        local ok2, skillID, collapsed, _, header = pcall(GetGuildTradeSkillInfo, i)
        if ok2 and header and collapsed and ExpandGuildTradeSkillHeader then pcall(ExpandGuildTradeSkillHeader, skillID); expanded = true end
    end
    if expanded then ok, n = pcall(GetNumGuildTradeSkill); n = ok and tonumber(n) or 0 end
    -- ⛔ 10-18 /gi guildprobe 实测：《无限》这个接口第 13 列（技能）对所有人都回 1 —— 只说明「学了」，不是技能点；
    --   专业标题行第 5 / 7 列 = 在线 / 总人数（列表默认只列在线的人，不能拿行数当人数）
    local out, cur, rows, counts, maxSkill = {}, nil, 0, {}, 0
    for i = 1, n do
        local ok2, skillID, _, _, header, numOnline, _, numPlayers, name, _, _, online, _, skill, cls = pcall(GetGuildTradeSkillInfo, i)
        if ok2 then
            if header then
                cur = ns.Prof and ns.Prof.KeyOf and (ns.Prof.KeyOf(skillID) or ns.Prof.KeyOf(header)) or nil
                if cur then counts[cur] = { total = tonumber(numPlayers), online = tonumber(numOnline) } end
            elseif cur and type(name) == "string" and not secret(name) then
                out[cur] = out[cur] or {}
                local sk = tonumber(skill) or 0
                if sk > maxSkill then maxSkill = sk end
                table.insert(out[cur], { name = short(name), skill = sk, online = online and true or false, cls = cls })
                rows = rows + 1
            end
        end
    end
    if rows == 0 then return nil, 0, counts end
    -- 所有人都 ≤ 1：这一路没有真实技能点 → 不写数字（显示「已学」）
    if maxSkill <= 1 then
        for _, list in pairs(out) do for _, m in ipairs(list) do m.skill = nil end end
    end
    return out, rows, counts
end

-- 合并两路：{ { key, members = { {name, r, m, src, cls, online}, … } } }，按人数多→少；同一人两路都有 → 取技能高的
function GH.Collect()
    local by = {}
    local off, _, counts = GH.ReadOfficial()
    if off then
        for k, list in pairs(off) do
            by[k] = by[k] or {}
            for _, m in ipairs(list) do by[k][m.name] = { name = m.name, r = m.skill, src = "game", cls = m.cls, online = m.online } end
        end
    end
    local st = store() or {}
    local nSync = 0
    for who, e in pairs(st) do
        nSync = nSync + 1
        for k, s in pairs(e.p or {}) do
            by[k] = by[k] or {}
            local old = by[k][who]
            if not old or (s.r or 0) > (old.r or 0) then by[k][who] = { name = who, r = s.r, m = s.m, src = "addon", cls = e.cls, t = e.t } end
        end
    end
    local out = {}
    for k, set in pairs(by) do
        local list = {}
        for _, m in pairs(set) do list[#list + 1] = m end
        -- 有真实技能的（插件同步）在前按技能高到低；只知道「学了」的按在线在前
        table.sort(list, function(a, b)
            if (a.r or -1) ~= (b.r or -1) then return (a.r or -1) > (b.r or -1) end
            if (a.online and 1 or 0) ~= (b.online and 1 or 0) then return a.online and true or false end
            return a.name < b.name
        end)
        local c = counts and counts[k]
        out[#out + 1] = { key = k, members = list, total = c and c.total, onlineN = c and c.online }
    end
    table.sort(out, function(a, b)
        local na, nb = math.max(a.total or 0, #a.members), math.max(b.total or 0, #b.members)
        if na ~= nb then return na > nb end
        return a.key < b.key
    end)
    return out, off ~= nil, nSync
end

-- ---------- 抽屉 ----------
local function classHex(cls)
    local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
    if c and c.colorStr then return c.colorStr:sub(3) end
    if c and c.r then return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
    return "ffffff"
end

local function build(host)
    local W = ns.W
    local d = CreateFrame("Frame", nil, host, BackdropTemplateMixin and "BackdropTemplate" or nil)
    d:SetSize(DW, 540)
    if W and W.SkinPanel then W.SkinPanel(d) elseif d.SetBackdrop then
        d:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        d:SetBackdropColor(0.04, 0.05, 0.07, 0.96)
    end
    d:SetFrameStrata("HIGH"); d:EnableMouse(true)
    d.title = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); d.title:SetPoint("TOPLEFT", 14, -14)
    d.title:SetPoint("RIGHT", -40, 0); d.title:SetJustifyH("LEFT"); d.title:SetWordWrap(false)
    local close = W and W.CloseButton and W.CloseButton(d) or nil
    if close then close:SetPoint("TOPRIGHT", -8, -8); close:SetScript("OnClick", function() GH.Hide() end) end
    -- 11-12 界面重构第 2 期：「公会设置」齿轮（聊天里显示等级 / 升级播报 / 邀请入会 / 野外 PvP 通报；描述在主插件 Settings.lua，代码在内核）
    if ns.SettingsGearButton then
        d.gear = ns.SettingsGearButton(d, "guild")
        d.gear:SetPoint("TOPRIGHT", -40, -10)
        d.title:SetPoint("RIGHT", -122, 0)
    end
    d.sub = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); d.sub:SetPoint("TOPLEFT", 14, -40); d.sub:SetPoint("RIGHT", -14, 0)
    d.sub:SetJustifyH("LEFT"); d.sub:SetWordWrap(true); d.sub:SetTextColor(0.7, 0.7, 0.7)
    local sf, c = ns.Scroll(d, 6, -76, DW - 12, 540 - 76 - 52)
    d.sf, d.child, d.rows = sf, c, {}
    d.note = d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); d.note:SetPoint("BOTTOMLEFT", 14, 12); d.note:SetPoint("RIGHT", -110, 0)
    d.note:SetJustifyH("LEFT"); d.note:SetWordWrap(true)
    d.refresh = ns.Button(d, L("刷新", "Refresh"), 84, 22, function()
        lastReq = -999; GH.Request(); GH.Announce(true)
        if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
        GH.Render()
    end)
    d.refresh:SetPoint("BOTTOMRIGHT", -12, 10)
    d.open = {}
    d:Hide()
    return d
end

local function row(d, i)
    local r = d.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, d.child)
    r:SetHeight(26)
    if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.ic = r:CreateTexture(nil, "ARTWORK"); r.ic:SetSize(20, 20); r.ic:SetPoint("LEFT", 6, 0); r.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.t = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.t:SetPoint("LEFT", 32, 0); r.t:SetWidth(150); r.t:SetJustifyH("LEFT"); r.t:SetWordWrap(false)
    r.s = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.s:SetPoint("LEFT", 186, 0); r.s:SetPoint("RIGHT", -8, 0)
    r.s:SetJustifyH("LEFT"); r.s:SetWordWrap(false)
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.rows[i] = r
    return r
end

-- 11-07 用户截图「增加功能，可以右键发悄悄话，右键，菜单弹出，点击私聊」：会员行右键 → 小菜单 → 私聊
-- ⛔ 《无限》名字带姓（「Joker Dc」）：拼「/w 名字」会被聊天框当成只密「Joker」→ 先走 ChatFrame_SendTell（直接设密语对象），
--   再退到直接给输入框设 chatType / tellTarget；名字没空格时最后才拼 /w
function GH.Whisper(name)
    if type(name) ~= "string" or secret(name) or name == "" then return false end
    for _, f in ipairs({ ChatFrame_SendTell or false, ChatFrameUtil and ChatFrameUtil.SendTell or false }) do
        if type(f) == "function" and pcall(f, name) then return true end
    end
    local open = ChatFrame_OpenChat or (ChatFrameUtil and ChatFrameUtil.OpenChat)
    if type(open) ~= "function" then return false end
    if not name:find(" ") then return (pcall(open, "/w " .. name .. " ")) end
    if not pcall(open, "") then return false end
    local getAct = ChatEdit_GetActiveWindow or (ChatFrameUtil and ChatFrameUtil.GetActiveWindow)
    local eb = (type(getAct) == "function" and getAct()) or _G.ChatFrame1EditBox
    if not (eb and eb.SetAttribute) then return false end
    eb:SetAttribute("chatType", "WHISPER"); eb:SetAttribute("tellTarget", name)
    local upd = ChatEdit_UpdateHeader or (ChatFrameUtil and ChatFrameUtil.UpdateHeader)
    if type(upd) == "function" then pcall(upd, eb) end
    return true
end

function GH.MemberMenu(anchor, name)
    local function tell()
        if not GH.Whisper(name) then ns.Print(L("打不开私聊框：手动输入 /w ", "Couldn't open chat: type /w ") .. name) end
    end
    -- 11-13 第 4 期：键位页（KeysKb.lua）搬进按需加载的 _Class，小菜单实现留在主插件 ns.PopMenu（ClassStub.lua）
    local menu = (ns.KeysKb and ns.KeysKb.Menu) or ns.PopMenu
    if not menu then return tell() end   -- 菜单不在就直接私聊
    menu(anchor, "|cffffd100" .. name .. "|r", { { text = L("私聊", "Whisper"), fn = tell } })
end

function GH.Render()
    local d = GH.drawer
    if not d then return end
    for _, r in ipairs(d.rows) do r:Hide() end
    local g = guildName()
    if not inGuild() or not g then
        d.title:SetText(L("本公会", "My guild"))
        d.sub:SetText(L("你还没有公会。加入公会后，这里会列出会员的专业和等级；想找公会点左边「公会招募」。",
            "You're not in a guild. Once you join, members' professions show up here; see Guild recruitment on the left."))
        d.note:SetText("")
        return
    end
    d.title:SetText(L("本公会", "My guild") .. "  |cffffd100" .. g .. "|r")
    local list, official, nSync = GH.Collect()
    d.sub:SetText(L("各专业有谁、多少级；点专业展开全部会员", "Who has which profession and at what skill; click a profession to see everyone"))
    if official then
        d.note:SetText("|cff33ff99" .. L("游戏公会专业数据：全员可见，不用装插件", "Game guild-profession data: everyone, no addon needed") .. "|r"
            .. "  " .. string.format(L("· 另有 %d 人插件同步", "- plus %d synced via addon"), nSync))
    else
        d.note:SetText("|cffff9966" .. L("服务器没给公会专业数据 → 只显示装了 GI 的会员", "No guild-profession data from the server - showing GI users only") .. "|r"
            .. "  " .. string.format(L("（%d 人）", "(%d)"), nSync))
    end
    local y, i = 0, 0
    if #list == 0 then
        i = 1
        local r = row(d, i)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, 0); r:SetPoint("RIGHT", d.child, "RIGHT", 0, 0)
        r.bg:SetColorTexture(1, 1, 1, 0.03); r.ic:SetTexture(nil)
        r.t:SetText(L("还没有专业数据", "No profession data yet"))
        r.s:SetText(L("装了 GI 的会员上线后会自动同步；点「刷新」问一次", "GI users sync when they log in; click Refresh to ask"))
        r:SetScript("OnClick", nil); r:SetScript("OnEnter", nil)
        r:Show()
        return
    end
    for _, grp in ipairs(list) do
        i = i + 1
        local r = row(d, i)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", d.child, "RIGHT", 0, 0); r:SetHeight(26)
        r.bg:SetColorTexture(1, 0.82, 0, 0.07)
        r.ic:SetTexture("Interface\\Icons\\" .. (ICON[grp.key] or "INV_Misc_QuestionMark"))
        local name = ns.Prof and ns.Prof.Name and ns.Prof.Name(grp.key) or grp.key
        local open = d.open[grp.key]
        local cnt = (grp.total and grp.total >= #grp.members)
            and string.format(L("%d 人（在线 %d）", "%d (%d online)"), grp.total, grp.onlineN or 0) or (#grp.members .. L(" 人", ""))
        r.t:SetText((open and "- " or "+ ") .. name .. "  |cff999999" .. cnt .. "|r")
        local top = {}
        for j = 1, math.min(3, #grp.members) do
            local m = grp.members[j]
            top[#top + 1] = "|cff" .. classHex(m.cls) .. m.name .. "|r " .. (m.r or ("|cff888888" .. L("已学", "learned") .. "|r"))
        end
        r.s:SetText(table.concat(top, "  "))
        r:SetScript("OnClick", function() d.open[grp.key] = not d.open[grp.key]; GH.Render() end)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(name, 1, 0.82, 0)
            for j = 1, math.min(20, #grp.members) do
                local m = grp.members[j]
                GameTooltip:AddDoubleLine("|cff" .. classHex(m.cls) .. m.name .. "|r", m.r and (m.r .. (m.m and m.m > 0 and ("/" .. m.m) or "")) or L("已学", "learned"), 1, 1, 1, 1, 1, 1)
            end
            if #grp.members > 20 then GameTooltip:AddLine(string.format(L("…… 共 %d 人，点开看全部", "... %d total, click to see all"), #grp.members), 0.6, 0.6, 0.6) end
            GameTooltip:Show()
        end)
        r:Show()
        y = y + 28
        if open then
            for _, m in ipairs(grp.members) do
                i = i + 1
                local mr = row(d, i)
                mr:ClearAllPoints(); mr:SetPoint("TOPLEFT", 0, -y); mr:SetPoint("RIGHT", d.child, "RIGHT", 0, 0); mr:SetHeight(22)
                mr.bg:SetColorTexture(1, 1, 1, 0.02); mr.ic:SetTexture(nil)
                mr.t:SetText("   |cff" .. classHex(m.cls) .. m.name .. "|r")
                local src = m.src == "game" and (m.online and ("|cff33ff99" .. L("在线", "online") .. "|r") or ("|cff888888" .. L("离线", "offline") .. "|r"))
                    or ("|cff888888" .. L("插件同步", "addon sync") .. "|r")
                mr.s:SetText((m.r and (m.r .. (m.m and m.m > 0 and ("|cff888888/" .. m.m .. "|r") or "")) or ("|cff888888" .. L("已学（游戏只给是否学会）", "learned (the game gives no skill value)") .. "|r")) .. "   " .. src)
                local who = m.name
                mr:SetScript("OnClick", function(self, btn) if btn == "RightButton" then GH.MemberMenu(self, who) end end)
                mr:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(who, 1, 1, 1)
                    GameTooltip:AddLine(L("右键：私聊", "Right-click: whisper"), 0.6, 0.6, 0.6)
                    GameTooltip:Show()
                end)
                mr:Show()
                y = y + 24
            end
        end
    end
    d.child:SetHeight(math.max(10, y))
end

-- ---------- 右侧页签：子页签 + 切换 ----------
local function guildTab() local h = _G.GearInsightForeverMain; return h and rawget(h, "_giGuildTab") end
local function mode() return (ns.db.ui and ns.db.ui.guildSub) or "home" end
local function setMode(m) ns.db.ui = ns.db.ui or {}; ns.db.ui.guildSub = m end
GH.Mode = mode

local function place(d, host, tab)
    if d:GetParent() ~= host and d.SetParent then d:SetParent(host) end
    local hh = host.GetHeight and host:GetHeight()
    d:SetHeight(math.max(540, type(hh) == "number" and hh or 540))
    local ht, tt = host.GetTop and host:GetTop(), tab.GetTop and tab:GetTop()
    local dy = (type(ht) == "number" and type(tt) == "number") and (ht - tt) or 0
    -- 11-10 用户录屏：放不下先把主面板左移（W.RoomRight），左边也没地方才翻到页签左边盖住主面板
    local room = not (ns.W and ns.W.RoomRight) or ns.W.RoomRight(host, tab, DW)
    d:ClearAllPoints()
    if not room then d:SetPoint("TOPRIGHT", tab, "TOPLEFT", -4, dy)
    else d:SetPoint("TOPLEFT", tab, "TOPRIGHT", 4, dy) end
end

function GH.Hide()
    if GH.drawer then GH.drawer:Hide() end
    local tab = guildTab()
    local rd = tab and rawget(tab, "_drawer")
    if tab and ns.W and ns.W.SelectTab and not (rd and rd:IsShown()) then ns.W.SelectTab(tab, false) end
    GH.SyncSubTabs()
end

function GH.ShowHome()
    local host, tab = _G.GearInsightForeverMain, guildTab()
    if not (host and tab) then return end
    local rd = rawget(tab, "_drawer")
    if rd and rd:IsShown() then rd:Hide() end
    local qm = ns.QM
    if qm and qm.drawer and qm.drawer:IsShown() and not (ns.db.qm and ns.db.qm.pinned) then
        qm.drawer:Hide()
        local qt = rawget(host, "_giQmTab"); if qt and ns.W then ns.W.SelectTab(qt, false) end
        if qm.SyncSubTabs then pcall(qm.SyncSubTabs) end
    end
    GH.drawer = GH.drawer or build(host)
    place(GH.drawer, host, tab)
    GH.drawer:Show()
    if ns.W and ns.W.SelectTab then ns.W.SelectTab(tab, true) end
    GH.Request()
    GH.Announce()
    GH.Render()
    GH.SyncSubTabs()
end

-- 子页签：「公会」下面 [本公会][公会招募]，任一抽屉开着就展开
function GH.SyncSubTabs()
    local host, tab = _G.GearInsightForeverMain, guildTab()
    if not (host and tab) then return end
    local subs = rawget(tab, "_giSubs")
    if not subs then return end
    local rd = rawget(tab, "_drawer")
    local open = host:IsShown() and ((GH.drawer and GH.drawer:IsShown()) or (rd and rd:IsShown())) and true or false
    for i, b in ipairs(subs) do
        b:ClearAllPoints(); b:SetPoint("TOPRIGHT", i == 1 and tab or subs[i - 1], "BOTTOMRIGHT", 0, -SUB_GAP)
        b:SetShown(open and true or false)
    end
    local m = (GH.drawer and GH.drawer:IsShown()) and "home" or ((rd and rd:IsShown()) and "recruit" or mode())
    for k, b in pairs(rawget(tab, "_giSubByMode") or {}) do
        if rawget(b, "_seg") and ns.SegSelect then ns.SegSelect(b, k == m) end
    end
    if ns.LayoutSideTabs then ns.LayoutSideTabs(host) end
end

local function wire()
    local host, tab = _G.GearInsightForeverMain, guildTab()
    if not (host and tab) or rawget(tab, "_giHomeWired") or not tab.HookScript then return end
    if not rawget(tab, "_giLoadWired") then return end   -- 等 GuildTab.lua 先把招募点击接好
    tab._giHomeWired = true
    tab._giSubs, tab._giSubByMode = {}, {}
    for _, m in ipairs({ { "home", L("本公会", "My guild"), L("公会会员的专业和等级", "Members' professions and skill") },
        { "recruit", L("公会招募", "Recruitment"), L("正在招人的公会", "Guilds that are recruiting") } }) do
        local b = (ns.SegButton or ns.Button)(host, m[2], SUB_W, SUB_H, function()
            setMode(m[1])
            if m[1] == "home" then GH.ShowHome()
            else
                if GH.drawer then GH.drawer:Hide() end
                local rd = rawget(tab, "_drawer")
                if not (rd and rd:IsShown()) then local f = tab:GetScript("OnClick"); if f then GH._inner = true; pcall(f, tab); GH._inner = false end end
                GH.SyncSubTabs()
            end
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(m[2], 1, 0.82, 0)
            GameTooltip:AddLine(m[3], 1, 1, 1, true); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        tab._giSubs[#tab._giSubs + 1] = b
        tab._giSubByMode[m[1]] = b
    end
    -- 点「公会」大页签：打开上次看的那个子页（默认本公会）；再点一下 = 全收起
    local wasOpen = false
    tab:HookScript("PreClick", function()
        local rd = rawget(tab, "_drawer")
        wasOpen = (GH.drawer and GH.drawer:IsShown()) or false
        GH._recruitWas = rd and rd:IsShown() or false
    end)
    tab:HookScript("OnClick", function()
        local qm = ns.QM   -- 组队抽屉在同一个位置：收起（钉住的不管）
        if qm and qm.drawer and qm.drawer:IsShown() and not (ns.db.qm and ns.db.qm.pinned) then
            qm.drawer:Hide()
            local qt = rawget(host, "_giQmTab"); if qt and ns.W then ns.W.SelectTab(qt, false) end
            if qm.SyncSubTabs then pcall(qm.SyncSubTabs) end
        end
        if GH._inner then return end
        local rd = rawget(tab, "_drawer")
        if wasOpen then   -- 本公会开着时点大页签 = 收起（招募抽屉被原逻辑打开了，也一起关）
            if rd and rd:IsShown() then rd:Hide() end
            GH.Hide()
            return
        end
        if mode() == "home" and not GH._recruitWas then
            if rd and rd:IsShown() then rd:Hide() end
            GH.ShowHome()
            return
        end
        GH.SyncSubTabs()
    end)
    -- 「组队」页签点开 → 本公会收起：在 QuestMates.lua 组队页签自己的点击里收（和收招募抽屉同一处），这里不另挂钩子
    if host.HookScript then
        host:HookScript("OnHide", function() if GH.drawer then GH.drawer:Hide() end; GH.SyncSubTabs() end)
        host:HookScript("OnShow", function() GH.SyncSubTabs() end)
    end
end
GH.Wire = wire

if hooksecurefunc and type(ns.ToggleMain) == "function" then
    hooksecurefunc(ns, "ToggleMain", function() pcall(wire) end)
end

-- ---------- 事件 ----------
-- ⛔ 10-18 用户反馈掉帧：GUILD_TRADESKILL_UPDATE 在大公会里很密（有人上下线就来一次），
--   每次都整表重读（上千行 GetGuildTradeSkillInfo）+ 排序 + 重排行 → 抽屉开着时一阵一阵卡。
--   合并成 2 秒最多一次
local renderQueued = false
function GH.QueueRender()
    if renderQueued or not (GH.drawer and GH.drawer:IsShown()) then return end
    if not (C_Timer and C_Timer.After) then pcall(GH.Render); return end
    renderQueued = true
    C_Timer.After(2, function()
        renderQueued = false
        if GH.drawer and GH.drawer:IsShown() then pcall(GH.Render) end
    end)
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
elseif RegisterAddonMessagePrefix then pcall(RegisterAddonMessagePrefix, PREFIX) end
local ev = CreateFrame("Frame")
for _, e in ipairs({ "CHAT_MSG_ADDON", "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "GUILD_TRADESKILL_UPDATE" }) do
    local valid = not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e)
    if valid then pcall(ev.RegisterEvent, ev, e) end
end
ev:SetScript("OnEvent", function(_, e, a1, a2, a3, a4)
    if e == "CHAT_MSG_ADDON" then
        if a1 == PREFIX and a3 == "GUILD" then pcall(GH.Handle, a4, a2) end
    elseif e == "PLAYER_ENTERING_WORLD" then
        if C_Timer and C_Timer.After then C_Timer.After(15, function() pcall(GH.Announce) end) end
    elseif e == "SKILL_LINES_CHANGED" then
        pcall(GH.Announce)   -- 60 秒节流
    elseif e == "GUILD_TRADESKILL_UPDATE" then
        GH.QueueRender()
    end
end)
GH._event = ev:GetScript("OnEvent")   -- 测试用
GH._ev = ev                           -- /gi perf 按事件计时用

-- 10-18 按需加载：登录早就过了，补跑一次「进入游戏」那段初始化
if IsLoggedIn and IsLoggedIn() then pcall(ev:GetScript("OnEvent"), ev, "PLAYER_ENTERING_WORLD") end

-- ---------- 10-18 探针：/gi guildprobe ----------
-- 用户截图「是不是搞错了」：本公会里除了自己几乎所有人技能都是 1。正式服接口第 13 列是技能值，《无限》客户端可能不一样 →
--   把 GetGuildTradeSkillInfo 前几行的每一列原样记下来（存档 ns.db.guildProbe + 聊天框），再记自己名字几种接口的返回
local function cell(v)
    if v == nil then return "nil" end
    if secret(v) then return "<secret>" end
    return tostring(v)
end
function GH.Probe()
    local out = {}
    local function add(s) out[#out + 1] = s end
    add("me UnitName=" .. cell(UnitName and UnitName("player")) .. " GetUnitName=" .. cell(GetUnitName and GetUnitName("player", true))
        .. " UnitFullName=" .. cell(UnitFullName and select(1, UnitFullName("player"))) .. "/" .. cell(UnitFullName and select(2, UnitFullName("player"))))
    if GetNumGuildTradeSkill and GetGuildTradeSkillInfo then
        local ok, n = pcall(GetNumGuildTradeSkill)
        add("rows=" .. cell(ok and n or "err"))
        local heads, members = 0, 0
        for i = 1, (ok and tonumber(n) or 0) do
            local r = { pcall(GetGuildTradeSkillInfo, i) }
            if r[1] then
                local isHead = r[5] and true or false
                if (isHead and heads < 3) or (not isHead and members < 8) then
                    local cols = {}
                    for c = 2, math.min(#r, 20) do cols[#cols + 1] = (c - 1) .. "=" .. cell(r[c]) end
                    add("#" .. i .. " " .. table.concat(cols, " | "))
                    if isHead then heads = heads + 1 else members = members + 1 end
                end
            end
        end
    else
        add("GetGuildTradeSkillInfo 不存在")
    end
    if GetNumGuildMembers and GetGuildRosterInfo then
        local me = UnitName and UnitName("player") or ""
        local ok, n = pcall(GetNumGuildMembers)
        for i = 1, (ok and tonumber(n) or 0) do
            local ok2, name, _, _, lv = pcall(GetGuildRosterInfo, i)
            if ok2 and type(name) == "string" and not secret(name) and name:sub(1, #me) == me then
                add("roster#" .. i .. " name=" .. name .. " lv=" .. cell(lv))
            end
        end
    end
    ns.db.guildProbe = out
    for _, s in ipairs(out) do ns.Print("|cff888888GIGUILD1|r " .. s) end
    ns.Print(ns.L("公会专业探针已记下（共 ", "Guild profession probe saved (") .. #out .. ns.L(" 行），输 /reload 写进存档后告诉我", " lines); /reload to save it"))
end
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.guildprobe = function() GH.Probe() end
