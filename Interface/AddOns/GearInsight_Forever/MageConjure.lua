-- 法师「造水」（11-14 用户「然后职业里给法师增加一个快速帮助对应等级的人做对应的水的功能」「有人密语要水，弹窗，自动一键做」）
--   两块，都只对法师生效（别的职业：页不出、事件不注册）：
--   ① 「职业」大类里的「造水」页（key = conj，class = Mage）：
--        左边列当前目标 + 队伍 / 团队成员：名字、等级、他能用的最高档水 / 面包（物品使用等级 ≤ 他的等级，且不高于我学会的档位），每行一键施法；
--        右边一排按档位的快捷按钮（「水 · 适用 25 级以上」…），没学会的档灰着
--   ② 有人密我要水 / 面包 → 弹窗：谁、几级、要什么，按钮「造 魔法泉水（适用 25 级）」，点一下施法、再点继续造；跟他交易时接「法师吃喝」的「一键放入」
--        独立开关（存 ns.db.mageConj.pop，nil = 开）：法师默认开，不受「法师吃喝」总开关（rec.mageAsk）管，设置页「造水」那组可关
--        默认不自动发话（ns.db.mageConj.reply，默认关）；开了才回一句「稍等，在造」，带 [Gearinsight插件] 前缀（同组队那边 DC.Tagged）
--   要水的识别：复用组队信标 DungeonChatCore.lua 的 DC.MageParseAsk（法师吃喝同一个函数）；组队子插件没加载时退回本文件的简版
--   对方等级：在队里 / 是目标 / 鼠标指向 → UnitLevel；公会名单 / 好友名单里有 → 名单等级；他话里报了（「我29级」「lv29」）→ 用它；都没有 → 弹窗里让玩家选
--   ⛔ 施法 = 受保护：只走安全按钮。⛔ 安全按钮不挂在 / 不锚到 GI 窗口和弹窗（会把它们带成受保护、战斗中关不掉，同 Talents.lua「去点」）：
--      只有一个顶层安全按钮 GearInsightForeverConjCast（父 = UIParent），鼠标移到页上 / 弹窗里的普通按钮上时，脱战按屏幕坐标盖过去、
--      改 type=spell / spell=法术 ID（脱战才改属性）；移开就藏；进战斗由安全状态驱动 [combat] 藏起来；只认按下（AnyDown，《无限》实测）
--   法术用 ID（SecureActionButton 的 spell 属性是数字时走 CastSpellByID，按 ID 施放的就是那一级，不用拼「造水术(等级 3)」）；
--      ID / 学习等级和 TrainNowData.lua（无限客户端 DB2 × 训练师实测）、MageWater.lua 的 MW.WATER / MW.FOOD 一致（测试逐条核）
--   本文件在主插件 HOLD 里：不加载时没有「造水」页、没有弹窗，UI.lua 职业大类成员里的 "conj" 没有对应页 → 不出，其余照旧
local _, ns = ...
local L = function(cn, en) return ns.L(cn, en) end

local MC = { orders = {}, replied = {} }
ns.MageConjure = MC
MC.ORDER_TTL = 300      -- 弹窗里的「有人要」留 5 分钟
MC.REPLY_CD = 180       -- 自动回话（开了的话）同一个人 3 分钟一次
MC.MAX_ROWS = 12        -- 页上最多列几个人（团队 40 人列不下：其余用右边按档位造）
MC.MAX_LV = 60
MC.TAG = "[Gearinsight插件]"   -- 组队信标没加载时的兜底前缀（⛔ 和 DungeonChatCore.lua 的 DC.TAG 一致）

-- ---------- 数据（⛔ 和 MageWater.lua 的 MW.WATER / MW.FOOD 逐条一致；gi_forever_mage_conjure_test.py 核）----------
--   req = 物品使用等级；spell = 造它的那一级法术；learn = 法师学会这一级的等级；山泉水 231778（造水术 8 级）只在真学会时才用
MC.WATER = {
    { id = 5350, req = 1, spell = 5504, learn = 4, n = "魔法水", en = "Conjured Water" },
    { id = 2288, req = 5, spell = 5505, learn = 10, n = "魔法淡水", en = "Conjured Fresh Water" },
    { id = 2136, req = 15, spell = 5506, learn = 20, n = "魔法纯净水", en = "Conjured Purified Water" },
    { id = 3772, req = 25, spell = 6127, learn = 30, n = "魔法泉水", en = "Conjured Spring Water" },
    { id = 8077, req = 35, spell = 10138, learn = 40, n = "魔法矿泉水", en = "Conjured Mineral Water" },
    { id = 8078, req = 45, spell = 10139, learn = 50, n = "魔法苏打水", en = "Conjured Sparkling Water" },
    { id = 8079, req = 55, spell = 10140, learn = 60, n = "魔法晶水", en = "Conjured Crystal Water" },
    { id = 231778, req = 55, spell = 468766, learn = 60, n = "山泉水", noAsk = true },
}
MC.FOOD = {
    { id = 5349, req = 1, spell = 587, learn = 6, n = "魔法松饼", en = "Conjured Muffin" },
    { id = 1113, req = 5, spell = 597, learn = 12, n = "魔法面包", en = "Conjured Bread" },
    { id = 1114, req = 15, spell = 990, learn = 22, n = "魔法黑面包", en = "Conjured Rye" },
    { id = 1487, req = 25, spell = 6129, learn = 32, n = "魔法粗面包", en = "Conjured Pumpernickel" },
    { id = 8075, req = 35, spell = 10144, learn = 42, n = "魔法酵母", en = "Conjured Sourdough" },
    { id = 8076, req = 45, spell = 10145, learn = 52, n = "魔法甜面包", en = "Conjured Sweet Roll" },
    { id = 22895, req = 55, spell = 28612, learn = 60, n = "魔法肉桂面包", en = "Conjured Cinnamon Roll" },
}
MC.REQS = { 1, 5, 15, 25, 35, 45, 55 }   -- 档位（物品使用等级）
MC.NO_MANA = { WARRIOR = true, ROGUE = true, DEATHKNIGHT = true }   -- 没蓝职业只要面包（同 MW.NO_MANA）

-- ---------- 小工具 ----------
local function now() return (GetTime and GetTime()) or 0 end
local function clean(v)
    if v == nil or (ns.Secret and ns.Secret(v)) then return nil end
    return v
end
local function pass(ok, ...) if ok then return ... end return nil end
local function call(f, ...)
    if type(f) ~= "function" then return nil end
    return pass(pcall(f, ...))
end
local function combat() return InCombatLockdown and InCombatLockdown() and true or false end
MC.Combat = combat
local function bool(v) return clean(v) and true or false end
local function short(n) return type(n) == "string" and (n:match("^[^-]+") or n) or nil end
MC.Short = short
local function exists(u) return UnitExists and bool(call(UnitExists, u)) or false end
local function isMe(u) return bool(call(UnitIsUnit, u, "player")) end
local function unitClass(u) local _, c = call(UnitClass, u); return clean(c) end
local function unitClassName(u) local n = call(UnitClass, u); return clean(n) end
local function unitLevel(u)
    local v = tonumber(clean(call(UnitLevel, u)))
    if v == -1 then return MC.MAX_LV end   -- 骷髅（高我 10 级以上）= 什么都能吃
    if v and v > 0 then return v end
    return nil
end
local function fullName(u)
    local n, realm = call(UnitName, u)
    n, realm = clean(n), clean(realm)
    if type(n) ~= "string" or n == "" then return nil end
    if type(realm) == "string" and realm ~= "" then return n .. "-" .. realm end
    return n
end
local function myLevel() return unitLevel("player") end
function MC.IsMage() return unitClass("player") == "MAGE" end
function MC.WantsWater(cls) return not (cls and MC.NO_MANA[cls]) end
-- 自定义字段一律 rawget（框体元表可能给没设过的键返回方法）
local function rg(t, k) return type(t) == "table" and rawget(t, k) or nil end

-- ---------- 设置（ns.db.mageConj；nil = 默认值）----------
MC.DEFAULTS = { pop = true, reply = false }
function MC.DB()
    ns.db.mageConj = ns.db.mageConj or {}
    return ns.db.mageConj
end
function MC.Opt(k)
    if not ns.db then return MC.DEFAULTS[k] end
    local v = MC.DB()[k]
    if v == nil then return MC.DEFAULTS[k] end
    return v
end
function MC.SetOpt(k, v)
    v = v and true or false
    if v == MC.DEFAULTS[k] then MC.DB()[k] = nil else MC.DB()[k] = v end
    if k == "pop" and not v then MC.HideAsk() end
    if MC.Sync then pcall(MC.Sync) end
end
function MC.PopOn() return MC.Opt("pop") and true or false end

-- ---------- 档位 ----------
local function hasSpellApi()
    return (C_SpellBook and C_SpellBook.IsSpellKnown) or IsPlayerSpell or IsSpellKnown or nil
end
function MC.Known(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown and bool(call(C_SpellBook.IsSpellKnown, id)) then return true end
    if IsPlayerSpell and bool(call(IsPlayerSpell, id)) then return true end
    if IsSpellKnown and bool(call(IsSpellKnown, id)) then return true end
    return false
end
-- 我学会的档位（从低到高；同一个使用等级只留最好的那个：学会山泉水就用它顶替魔法晶水）
--   客户端没有查法术的接口时退回「学习等级 ≤ 我的等级」（不含山泉水）
function MC.Learned(list)
    local out, api, my = {}, hasSpellApi(), myLevel() or 0
    for _, e in ipairs(list) do
        local ok
        if api then ok = MC.Known(e.spell) else ok = (not e.noAsk) and e.learn <= my end
        if ok then
            if #out > 0 and out[#out].req == e.req then out[#out] = e else out[#out + 1] = e end
        end
    end
    return out
end
function MC.MaxLearned(list) local t = MC.Learned(list); return t[#t] end
-- lv 级的人能用的最高档（不高于我学会的）；lv 不知道 / 一档都没学 → nil
function MC.TierFor(list, lv)
    lv = tonumber(lv)
    if not lv then return nil end
    local best
    for _, e in ipairs(MC.Learned(list)) do if e.req <= lv then best = e end end
    return best
end
-- 档位按钮用：这个使用等级我学会的那个（没学 = nil）
function MC.LearnedAt(list, req)
    for _, e in ipairs(MC.Learned(list)) do if e.req == req then return e end end
    return nil
end
function MC.IsWater(e)
    for _, w in ipairs(MC.WATER) do if w == e then return true end end
    return false
end
function MC.ItemName(e)
    if not e then return "" end
    local n
    if C_Item and C_Item.GetItemNameByID then n = clean(call(C_Item.GetItemNameByID, e.id)) end
    if (type(n) ~= "string" or n == "") and GetItemInfo then n = clean(call(GetItemInfo, e.id)) end
    if type(n) == "string" and n ~= "" then return n end
    return L(e.n, e.en or e.n)
end

-- ---------- 名单 ----------
local function groupUnits()
    local out = {}
    if bool(IsInRaid and call(IsInRaid)) then
        for i = 1, 40 do out[#out + 1] = "raid" .. i end
    else
        for i = 1, 4 do out[#out + 1] = "party" .. i end
    end
    return out
end
-- 页上列的人：目标在最前，其余按等级从低到高
function MC.Roster()
    local out, seen = {}, {}
    local function add(u, isTarget)
        if not exists(u) or isMe(u) then return end
        if UnitIsPlayer and not bool(call(UnitIsPlayer, u)) then return end
        if UnitIsFriend and not bool(call(UnitIsFriend, "player", u)) then return end
        local who = fullName(u)
        if not who or seen[who] then return end
        seen[who] = true
        out[#out + 1] = { unit = u, who = who, lv = unitLevel(u), cls = unitClass(u), clsName = unitClassName(u), target = isTarget or nil }
    end
    add("target", true)
    for _, u in ipairs(groupUnits()) do add(u) end
    table.sort(out, function(a, b)
        if (a.target and true or false) ~= (b.target and true or false) then return a.target and true or false end
        local la, lb = a.lv or 999, b.lv or 999
        if la ~= lb then return la < lb end
        return a.who < b.who
    end)
    return out
end

-- 聊天作者 → 单位（队友 / 目标 / 鼠标指向 / 焦点）
function MC.UnitOf(author)
    local s = short(clean(author))
    if not s or s == "" then return nil end
    local list = groupUnits()
    for _, u in ipairs({ "target", "mouseover", "focus" }) do list[#list + 1] = u end
    for _, u in ipairs(list) do
        if exists(u) then
            local n = short(fullName(u))
            if n == s then return u end
        end
    end
    return nil
end
-- 对方等级 → lv, 来源（group / unit / guild / friend / said）；拿不到 = nil
function MC.LevelInText(msg)
    if type(msg) ~= "string" then return nil end
    local s = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local n = s:match("(%d+)[ \t]*级") or s:match("[Ll][Vv][Ll]?%.?[ \t]*(%d+)") or s:match("[Ll]evel[ \t]*(%d+)")
    n = tonumber(n)
    if n and n >= 1 and n <= MC.MAX_LV then return n end
    return nil
end
local function guildLevel(s)
    if not (GetNumGuildMembers and GetGuildRosterInfo) then return nil end
    if IsInGuild and not bool(call(IsInGuild)) then return nil end
    local n = tonumber(clean(call(GetNumGuildMembers))) or 0
    for i = 1, math.min(n, 1000) do
        local name, _, _, lv = call(GetGuildRosterInfo, i)
        if short(clean(name)) == s then lv = tonumber(clean(lv)); if lv and lv > 0 then return lv end end
    end
    return nil
end
local function friendLevel(s)
    local F = C_FriendList
    if not (F and F.GetNumFriends and F.GetFriendInfoByIndex) then return nil end
    local n = tonumber(clean(call(F.GetNumFriends))) or 0
    for i = 1, math.min(n, 200) do
        local t = call(F.GetFriendInfoByIndex, i)
        if type(t) == "table" and short(clean(t.name)) == s then
            local lv = tonumber(clean(t.level)); if lv and lv > 0 then return lv end
        end
    end
    return nil
end
function MC.LevelOf(author, msg)
    local s = short(clean(author))
    local u = MC.UnitOf(author)
    if u then
        local lv = unitLevel(u)
        if lv then return lv, (u:find("^party") or u:find("^raid")) and "group" or "unit", u end
    end
    if s then
        local lv = guildLevel(s)
        if lv then return lv, "guild" end
        lv = friendLevel(s)
        if lv then return lv, "friend" end
    end
    local lv = MC.LevelInText(msg)
    if lv then return lv, "said" end
    return nil
end
local SRC_TEXT = { group = { "队伍", "group" }, unit = { "目标", "target" }, guild = { "公会名单", "guild roster" },
    friend = { "好友名单", "friends list" }, said = { "他自己说的", "their message" }, pick = { "你选的", "your pick" } }

-- ---------- 要水识别 ----------
--   优先用组队信标的 DC.MageParseAsk（法师吃喝同一个函数）；信标没加载 → 简版：短句或带「求 / 要 / 给…」的、提到水 / 面包的
local FB_WATER = { "水", "喝的" }
local FB_NOT_WATER = { "水晶", "水果", "水下", "水元素", "潜水", "风水", "水平", "口水", "水手" }
local FB_FOOD = { "面包", "吃的", "食物" }
local FB_BOTH = { "吃喝", "吃的喝的" }
local FB_INTENT = { "求", "要", "给", "麻烦", "来点", "能不能", "可以", "?", "？", "plz", "pls", "please" }
local function hasAny(s, words) for _, w in ipairs(words) do if s:find(w, 1, true) then return true end end return false end
function MC.ParseFallback(msg)
    if type(msg) ~= "string" or msg == "" then return false, false end
    local s = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end)   -- ⛔ 只动 ASCII（lower() 会切坏中文）
    if s:find(MC.TAG, 1, true) or s:find("[gi", 1, true) then
        if s:find("交易", 1, true) or s:find("稍等", 1, true) or s:find("trade", 1, true) then return false, false end
    end
    local w = s
    for _, x in ipairs(FB_NOT_WATER) do w = w:gsub(x, "") end
    local both = hasAny(s, FB_BOTH)
    local water = both or hasAny(w, FB_WATER) or s:find("%f[a-z]water%f[^a-z]") ~= nil or s:find("%f[a-z]drinks?%f[^a-z]") ~= nil
    local food = both or hasAny(s, FB_FOOD) or s:find("%f[a-z]food%f[^a-z]") ~= nil or s:find("%f[a-z]bread%f[^a-z]") ~= nil
    if not (water or food) then return false, false end
    if not (#s <= 15 or hasAny(s, FB_INTENT)) then return false, false end
    return water and true or false, food and true or false
end
function MC.ParseAsk(msg)
    local DC = ns.DungeonChat
    if DC and DC.MageParseAsk then
        local ok, w, f = pcall(DC.MageParseAsk, msg)
        if ok then return w and true or false, f and true or false end
    end
    return MC.ParseFallback(msg)
end

-- ---------- 发话（默认关；开了才回一句）----------
local function tagged(text)
    local DC = ns.DungeonChat
    if DC and DC.Tagged then return DC.Tagged(text, DC.MAX_BYTES or 255) end
    return MC.TAG .. text
end
MC.Tagged = tagged
function MC.CanChat()
    if combat() then return false end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and bool(call(C_ChatInfo.InChatMessagingLockdown)) then return false end
    return true
end
function MC.ReplyText(o)
    local names = {}
    local we = o.water and MC.TierFor(MC.WATER, o.lv)
    local fe = o.food and MC.TierFor(MC.FOOD, o.lv)
    if we then names[#names + 1] = MC.ItemName(we) end
    if fe then names[#names + 1] = MC.ItemName(fe) end
    if #names == 0 then return L("好的，稍等，我先造一下~", "Sure, give me a sec to conjure some~") end
    return L("好的，稍等，给你造", "Sure, conjuring ") .. table.concat(names, " + ") .. L("，好了叫你来交易~", " - I'll ping you to trade~")
end
function MC.MaybeReply(o)
    if not MC.Opt("reply") or not o or rg(o, "preview") then return false end
    if not MC.CanChat() then return false end
    local t = now()
    local last = MC.replied[o.short]
    if last and last <= t and t - last < MC.REPLY_CD then return false end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    if not pcall(send, tagged(MC.ReplyText(o)), "WHISPER", nil, o.who) then return false end
    MC.replied[o.short] = t
    return true
end

-- ---------- 安全施法按钮（唯一一个，顶层；盖到普通按钮上）----------
local hoverBtn   -- 鼠标正停在哪个普通按钮上（脱战后补盖用）
function MC.BuildCast()
    if MC.cast then return MC.cast end
    if combat() then return nil end
    local b = CreateFrame("Button", "GearInsightForeverConjCast", UIParent, "SecureActionButtonTemplate")
    b:SetFrameStrata("FULLSCREEN_DIALOG")
    if b.SetHighlightTexture then b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD") end
    if b.RegisterForClicks then b:RegisterForClicks("AnyDown") end
    if RegisterStateDriver and b.SetAttribute then
        b:SetAttribute("_onstate-giconj", [[ if newstate == "1" then self:Hide() end ]])
        RegisterStateDriver(b, "giconj", "[combat] 1; 0")
    end
    b:SetScript("OnEnter", function(self) local a = rg(self, "anchor"); if a then MC.Tip(a, self) end end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("PostClick", function(self) pcall(MC.Casted, rg(self, "anchor")) end)
    b:SetScript("OnUpdate", function(self)
        if combat() then return end
        local a = rg(self, "anchor")
        if not a or not a:IsVisible() or not (self:IsMouseOver() or a:IsMouseOver()) then
            self:Hide(); self.anchor = nil
        end
    end)
    b:Hide()
    MC.cast = b
    return b
end
-- 盖到 anchor（普通按钮，身上有 spell）上：脱战才改属性；返回 true = 盖上了
function MC.Hover(anchor)
    if combat() then return false, "combat" end
    local spell = rg(anchor, "spell")
    if not spell then return false, "nospell" end
    local b = MC.BuildCast()
    if not b then return false, "combat" end
    local l, btm = anchor:GetLeft(), anchor:GetBottom()
    if not (l and btm) then return false, "nopos" end
    local es, us = anchor:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if es and us and us > 0 then b:SetScale(es / us) end
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, btm)
    b:SetSize(anchor:GetWidth() or 100, anchor:GetHeight() or 22)
    b:SetAttribute("type", "spell")
    b:SetAttribute("spell", spell)
    b.anchor = anchor
    b:Show()
    return true
end
-- 盖不上时（战斗中 / 位置拿不到）点到的是普通按钮本身
function MC.FallbackClick(btn)
    if combat() then
        ns.Print(L("战斗中不能施法（暴雪限制），脱战后鼠标移到按钮上再点", "Can't conjure in combat - hover the button again after combat"))
    elseif rg(btn, "spell") then
        ns.Print(L("按钮还没就位：鼠标移开再移回来点一下", "Button not ready - move the mouse off and back, then click"))
    end
end
-- 点完一下：弹窗里记「点了几次」（施法成不成功插件不知道，只记点击）
function MC.Casted(anchor)
    local o = rg(anchor, "order")
    if o then o.casts = (o.casts or 0) + 1; if MC.askFrame and MC.askFrame:IsShown() then pcall(MC.RefreshAsk) end end
end

-- 普通按钮（页上 / 弹窗里）：鼠标移上去 = 提示 + 盖安全按钮
local function plainBtn(parent, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    if ns.SkinButton then ns.SkinButton(b) end
    b:SetScript("OnEnter", function(self) hoverBtn = self; MC.Tip(self, self); MC.Hover(self) end)
    b:SetScript("OnLeave", function(self) if hoverBtn == self then hoverBtn = nil end; GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self) MC.FallbackClick(self) end)
    return b
end
MC.PlainBtn = plainBtn
-- 设按钮：e = 档位（nil = 不可点），text = 显示文字
local function setBtn(b, e, text, order)
    b.entry, b.spell, b.order = e, e and e.spell or nil, order
    b:SetText(text or "")
    if b.SetEnabled then b:SetEnabled(e ~= nil) end
    -- 鼠标正停在它上面、档位变了：安全按钮跟着改（脱战）/ 收起
    if MC.cast and rg(MC.cast, "anchor") == b and not combat() then
        if e then MC.Hover(b) else MC.cast:Hide(); MC.cast.anchor = nil end
    end
end
MC.SetBtn = setBtn
function MC.Tip(btn, owner)
    local e = rg(btn, "entry")
    local tip = rg(btn, "tip")
    GameTooltip:SetOwner(owner or btn, "ANCHOR_TOP")
    if e then
        local isW = MC.IsWater(e)
        GameTooltip:AddLine((isW and L("造水术", "Conjure Water") or L("造食术", "Conjure Food")) .. " → " .. MC.ItemName(e), 1, 0.82, 0)
        GameTooltip:AddLine(string.format(L("适用 %d 级以上；点一下施放，再点继续造", "Usable at level %d+; click to cast, click again for more"), e.req), 1, 1, 1, true)
        if combat() then GameTooltip:AddLine(L("战斗中不能施法（暴雪限制）", "Can't cast in combat"), 1, 0.3, 0.3, true) end
    elseif tip then
        GameTooltip:AddLine(tip, 1, 1, 1, true)
    else
        GameTooltip:AddLine(L("这一档还没学会", "Not learned yet"), 1, 0.3, 0.3, true)
    end
    GameTooltip:Show()
end

-- ================= ① 「造水」页 =================
local ROW_H = 26
local CLS_ZH = { WARRIOR = "战士", PALADIN = "圣骑士", HUNTER = "猎人", ROGUE = "盗贼", PRIEST = "牧师", SHAMAN = "萨满", MAGE = "法师", WARLOCK = "术士", DRUID = "德鲁伊" }
local CLS_COLOR = { WARRIOR = "c79c6e", PALADIN = "f58cba", HUNTER = "abd473", ROGUE = "fff569", PRIEST = "ffffff", SHAMAN = "0070de", MAGE = "69ccf0", WARLOCK = "9482c9", DRUID = "ff7d0a" }
local function colorName(who, cls)
    local c = cls and CLS_COLOR[cls]
    local s = short(who) or who or ""
    return c and ("|cff" .. c .. s .. "|r") or s
end
function MC.MineText()
    local we, fe = MC.MaxLearned(MC.WATER), MC.MaxLearned(MC.FOOD)
    local function one(e, none)
        if not e then return "|cffff6060" .. none .. "|r" end
        return MC.ItemName(e) .. string.format(L("（适用 %d 级）", " (Lv%d+)"), e.req)
    end
    return L("我学会的最高档：水 ", "My best: water ") .. one(we, L("还没学会造水术", "Conjure Water not learned"))
        .. L(" · 面包 ", " · food ") .. one(fe, L("还没学会造食术", "Conjure Food not learned"))
end
local function fs(p, font, x, y, w)
    local t = p:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    t:SetPoint("TOPLEFT", x, y)
    if w then t:SetWidth(w) end
    t:SetJustifyH("LEFT")
    return t
end
function MC.BuildPage(p)
    MC.page = p
    local y = ns.PageHeader(p, L("造水", "Conjure"), L("按对方等级造他能用的最高档水 / 面包", "Conjure the best water / food each player can use"))
    p.mine = fs(p, "GameFontHighlight", 12, y, 640)
    y = y - 22
    p.lhead = fs(p, "GameFontNormal", 12, y, 450)
    p.rhead = fs(p, "GameFontNormal", 486, y, 170)
    p.rhead:SetText(L("按档位造", "By tier"))
    y = y - 20
    p.rows = {}
    for i = 1, MC.MAX_ROWS do
        local ry = y - (i - 1) * ROW_H
        local r = {}
        r.name = fs(p, "GameFontHighlight", 12, ry - 5, 122); if r.name.SetWordWrap then r.name:SetWordWrap(false) end
        r.lv = fs(p, "GameFontHighlightSmall", 136, ry - 6, 44)
        r.w = plainBtn(p, 140, 22); r.w:SetPoint("TOPLEFT", 182, ry)
        r.f = plainBtn(p, 140, 22); r.f:SetPoint("TOPLEFT", 326, ry)
        p.rows[i] = r
    end
    p.empty = fs(p, "GameFontDisable", 12, y - 6, 450)
    p.more = fs(p, "GameFontDisableSmall", 12, y - MC.MAX_ROWS * ROW_H - 2, 450)
    -- 右边：按档位（水 7 档、面包 7 档）
    p.tw, p.tf = {}, {}
    for i, req in ipairs(MC.REQS) do
        local b = plainBtn(p, 170, 22); b:SetPoint("TOPLEFT", 486, y - (i - 1) * 24); b.req = req
        p.tw[i] = b
    end
    local fy = y - #MC.REQS * 24 - 8
    for i, req in ipairs(MC.REQS) do
        local b = plainBtn(p, 170, 22); b:SetPoint("TOPLEFT", 486, fy - (i - 1) * 24); b.req = req
        p.tf[i] = b
    end
    p.note = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.note:SetPoint("BOTTOMLEFT", 12, 4); p.note:SetWidth(640); p.note:SetJustifyH("LEFT")
    p.note:SetText(L("施法要你自己点（暴雪规定），战斗中不能用；造好后让他来交易 —— 有人密你要水时会弹窗（本页设置可关）",
        "Casting needs your click (Blizzard rule) and is unavailable in combat; then trade them. Whisper requests pop a prompt (toggle in page settings)"))
    MC.RefreshPage(p)
end
function MC.RefreshPage(p)
    p = p or MC.page
    if not p or not rg(p, "rows") then return end
    p.mine:SetText(MC.MineText())
    local roster = MC.Roster()
    p.lhead:SetText(string.format(L("目标 / 队伍（%d 人）", "Target / group (%d)"), #roster))
    for i, r in ipairs(p.rows) do
        local m = roster[i]
        local on = m ~= nil
        for _, x in ipairs({ r.name, r.lv, r.w, r.f }) do if on then x:Show() else x:Hide() end end
        if m then
            local tag = m.target and L("|cffffd100[目标]|r ", "|cffffd100[T]|r ") or ""
            r.name:SetText(tag .. colorName(m.who, m.cls))
            r.lv:SetText(m.lv and string.format(L("%d 级", "Lv%d"), m.lv) or "??")
            local lv = m.lv or MC.MAX_LV
            if MC.WantsWater(m.cls) then
                local e = MC.TierFor(MC.WATER, lv)
                setBtn(r.w, e, e and MC.ItemName(e) or L("没学会造水术", "No Conjure Water"))
            else
                setBtn(r.w, nil, L("不用水", "No mana"))
            end
            local e = MC.TierFor(MC.FOOD, lv)
            setBtn(r.f, e, e and MC.ItemName(e) or L("没学会造食术", "No Conjure Food"))
        else
            setBtn(r.w, nil, ""); setBtn(r.f, nil, "")
        end
    end
    if #roster == 0 then
        p.empty:SetText(L("没组队也没选中玩家：选中对方或组队后这里会列出他；也可以用右边按档位造", "No target or group: target someone or group up, or use the tier buttons on the right"))
        p.empty:Show()
    else p.empty:Hide() end
    local extra = #roster - MC.MAX_ROWS
    p.more:SetText(extra > 0 and string.format(L("还有 %d 人没列出：用右边按档位造", "%d more not listed - use the tier buttons"), extra) or "")
    for i, req in ipairs(MC.REQS) do
        local e = MC.LearnedAt(MC.WATER, req)
        setBtn(p.tw[i], e, string.format(L("水 · 适用 %d 级以上", "Water · Lv%d+"), req))
        e = MC.LearnedAt(MC.FOOD, req)
        setBtn(p.tf[i], e, string.format(L("面包 · 适用 %d 级以上", "Food · Lv%d+"), req))
    end
end
function MC.PageShown() return MC.page ~= nil and MC.page:IsVisible() and true or false end
function MC.Open()
    if ns.ToggleMain then
        local f = _G.GearInsightForeverMain
        if f and f:IsShown() and MC.PageShown() then return end
        ns.ToggleMain("conj")
    end
end

-- ================= ② 密语要水弹窗 =================
function MC.Orders()
    local out, t = {}, now()
    for k, o in pairs(MC.orders) do
        if not rg(o, "preview") and t - o.t > MC.ORDER_TTL then MC.orders[k] = nil else out[#out + 1] = o end
    end
    table.sort(out, function(a, b) return a.t < b.t end)
    return out
end
local function classOfAuthor(author, guid)
    local u = MC.UnitOf(author)
    if u then local c = unitClass(u); if c then return c end end
    if guid and GetPlayerInfoByGUID then
        local _, c = call(GetPlayerInfoByGUID, guid)
        c = clean(c)
        if type(c) == "string" and c ~= "" then return c end
    end
    return nil
end
-- 收到私聊：是要水 → 记下来、弹窗。返回 true / false, 原因
function MC.OnWhisper(msg, author, guid)
    if not ns.db then return false, "nodb" end
    if not MC.IsMage() then return false, "notmage" end
    if not MC.PopOn() then return false, "off" end
    msg, author = clean(msg), clean(author)
    if type(author) ~= "string" or author == "" then return false, "noauthor" end
    local s = short(author)
    if s == short(fullName("player")) then return false, "me" end
    local water, food = MC.ParseAsk(msg)
    if not (water or food) then return false, "notask" end
    -- 11-14 去重：「法师吃喝」总开关 + 提醒条都开着、他又在队里 → 那边的提醒条会接这一单，这里不再弹第二个窗
    local MW = ns.MageWater
    if MW and MW.On and MW.Opt and MW.UnitOf and MW.On() and MW.Opt("bar") and MW.UnitOf(author) then return false, "mwbar" end
    local cls = classOfAuthor(author, clean(guid))
    if cls == "MAGE" then return false, "mage" end
    if not MC.WantsWater(cls) then water, food = false, true end
    local lv, src = MC.LevelOf(author, msg)
    local old = MC.orders[s]
    if not lv and old and old.lv then lv, src = old.lv, old.src end   -- 之前选过 / 读到过 → 接着用
    local o = { who = author, short = s, lv = lv, src = src, water = water, food = food, cls = cls, msg = msg, t = now(), casts = old and old.casts or 0 }
    MC.orders[s] = o
    MC.cur = s
    pcall(MC.MaybeReply, o)
    MC.ShowAsk()
    return true, lv
end
-- 示例窗（设置页「弹一个示例窗」：摆位置 / 看样子）
function MC.Preview()
    local s = L("示例玩家", "Example")
    MC.orders[s] = { who = s, short = s, lv = 27, src = "said", water = true, food = true, msg = L("法师老板，求点水，谢谢~（我27级）", "Could I get some water please? (Lv27)"), t = now(), casts = 0, preview = true }
    MC.cur = s
    return MC.ShowAsk()
end

local function utf8Cut(s, maxBytes)
    if #s <= maxBytes then return s end
    local i = maxBytes
    while i > 0 do
        local c = s:byte(i + 1)
        if not c or c < 0x80 or c >= 0xC0 then break end   -- 下一个字节不是续字节 → 在这里切
        i = i - 1
    end
    return s:sub(1, i) .. "…"
end
MC.Utf8Cut = utf8Cut
function MC.AskText(o)
    local want = {}
    if o.water then want[#want + 1] = L("水", "water") end
    if o.food then want[#want + 1] = L("面包", "food") end
    local lvTxt = o.lv and string.format(L("%d 级", "Lv%d"), o.lv) or ("|cffff9933" .. L("等级不明（下面选他的等级）", "level unknown (pick below)") .. "|r")
    local line1 = colorName(o.who, o.cls) .. " · " .. lvTxt .. " · " .. L("要", "wants ") .. table.concat(want, L("和", " and "))
    local said = tostring(o.msg or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|", "")
    local out = line1 .. "\n|cff999999" .. L("他说：", "Said: ") .. utf8Cut(said, 90)
    if o.lv and o.src and SRC_TEXT[o.src] then out = out .. L("　（等级来自", "  (level from ") .. L(SRC_TEXT[o.src][1], SRC_TEXT[o.src][2]) .. L("）", ")") end
    if (o.casts or 0) > 0 then out = out .. "\n|cff33ff99" .. string.format(L("已点了 %d 次", "Clicked %d times"), o.casts) .. "|r" end
    return out .. "|r"
end
-- 弹窗按钮上的字：「造 魔法泉水（适用 25 级）」
function MC.CastLabel(list, o)
    local e = MC.TierFor(list, o.lv)
    if e then return e, string.format(L("造 %s（适用 %d 级）", "Conjure %s (Lv%d+)"), MC.ItemName(e), e.req) end
    if not o.lv then return nil, L("先在下面选他的等级", "Pick their level below") end
    return nil, (list == MC.WATER) and L("还没学会造水术", "Conjure Water not learned") or L("还没学会造食术", "Conjure Food not learned")
end
function MC.BuildAsk()
    if MC.askFrame then return MC.askFrame end
    local f = CreateFrame("Frame", "GearInsightForeverConjAsk", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(350, 172)
    f:SetFrameStrata("DIALOG")
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    if f.SetBackdrop then
        pcall(f.SetBackdrop, f, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.05, 0.06, 0.08, 0.95); f:SetBackdropBorderColor(0.41, 0.8, 0.94, 0.9)
    end
    local pos = ns.db and MC.DB().pos
    if type(pos) == "table" and pos[1] then f:SetPoint(pos[1], UIParent, pos[1], pos[2] or 0, pos[3] or 0) else f:SetPoint("TOP", UIParent, "TOP", 0, -180) end
    f:SetMovable(true); f:EnableMouse(true)
    if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint()
        if p and ns.db then MC.DB().pos = { p, x, y } end
    end)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("TOPLEFT", 10, -8)
    title:SetText(L("造水 · 有人密你要吃喝", "Conjure - someone whispered for food / water"))
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetSize(22, 22); close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() MC.HideAsk() end)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); f.text:SetPoint("TOPLEFT", 10, -28); f.text:SetWidth(330); f.text:SetJustifyH("LEFT")
    -- 造水 / 造食（普通按钮，鼠标移上去盖安全按钮）
    f.cw = plainBtn(f, 160, 24); f.cf = plainBtn(f, 160, 24)
    -- 他的等级（等级不明 / 想改时选；按档位的使用等级）
    f.lvLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); f.lvLabel:SetPoint("BOTTOMLEFT", 10, 40)
    f.lvLabel:SetText(L("他的等级：", "Their level:"))
    f.picks = {}
    for i, req in ipairs(MC.REQS) do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        if ns.SkinButton then ns.SkinButton(b) end
        b:SetSize(36, 18); b:SetPoint("BOTTOMLEFT", 70 + (i - 1) * 39, 36)
        b:SetText(req .. "+"); b.req = req
        b:SetScript("OnClick", function(self) MC.PickLevel(rg(self, "req")) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(string.format(L("按 %d 级造（这一档物品要 %d 级才能用）", "Conjure for level %d"), rg(self, "req"), rg(self, "req")), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.picks[i] = b
    end
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.hint:SetPoint("BOTTOMLEFT", 10, 12); f.hint:SetWidth(200); f.hint:SetJustifyH("LEFT")
    f.hint:SetText(L("造好后让他来交易，「交易」要你自己点", "Then trade them - you click Trade yourself"))
    f.no = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); if ns.SkinButton then ns.SkinButton(f.no) end
    f.no:SetSize(56, 20); f.no:SetPoint("BOTTOMRIGHT", -8, 8); f.no:SetText(L("不用", "Dismiss"))
    f.no:SetScript("OnClick", function() MC.Done(MC.cur) end)
    f.next = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); if ns.SkinButton then ns.SkinButton(f.next) end
    f.next:SetSize(76, 20); f.next:SetPoint("RIGHT", f.no, "LEFT", -4, 0)
    f.next:SetScript("OnClick", function() MC.Next() end)
    f:Hide()
    MC.askFrame = f
    return f
end
-- 当前那一单（过期了就换下一单）
function MC.Current()
    local o = MC.cur and MC.orders[MC.cur]
    if o and (rg(o, "preview") or now() - o.t <= MC.ORDER_TTL) then return o end
    local list = MC.Orders()
    o = list[#list]
    MC.cur = o and o.short or nil
    return o
end
function MC.RefreshAsk()
    local f = MC.askFrame
    if not f then return false end
    local o = MC.Current()
    if not o then MC.HideAsk(); return false end
    f.text:SetText(MC.AskText(o))
    local we, wl = MC.CastLabel(MC.WATER, o)
    local fe, fl = MC.CastLabel(MC.FOOD, o)
    f.cw:ClearAllPoints(); f.cf:ClearAllPoints()
    if o.water and o.food then
        f.cw:SetSize(162, 24); f.cf:SetSize(162, 24)
        f.cw:SetPoint("BOTTOMLEFT", 10, 62); f.cf:SetPoint("BOTTOMLEFT", 178, 62)
        f.cw:Show(); f.cf:Show()
    else
        local b = o.water and f.cw or f.cf
        b:SetSize(330, 24); b:SetPoint("BOTTOMLEFT", 10, 62); b:Show()
        local other = o.water and f.cf or f.cw
        other:Hide()
    end
    setBtn(f.cw, o.water and we or nil, wl, o)
    setBtn(f.cf, o.food and fe or nil, fl, o)
    -- 等级选择：高亮当前那档；没学会的档灰掉
    local cur = MC.TierFor(MC.WATER, o.lv) or MC.TierFor(MC.FOOD, o.lv)
    local curReq
    if o.lv then for _, req in ipairs(MC.REQS) do if req <= o.lv then curReq = req end end end
    for _, b in ipairs(f.picks) do
        local req = rg(b, "req")
        local learned = MC.LearnedAt(MC.WATER, req) or MC.LearnedAt(MC.FOOD, req)
        if b.SetEnabled then b:SetEnabled(learned ~= nil) end
        if req == curReq then b:SetText("|cff33ff99" .. req .. "+|r"); if b.LockHighlight then b:LockHighlight() end
        else b:SetText(req .. "+"); if b.UnlockHighlight then b:UnlockHighlight() end end
    end
    local n = #MC.Orders() - 1
    if n > 0 then f.next:SetText(string.format(L("下一位(%d)", "Next (%d)"), n)); f.next:Show() else f.next:Hide() end
    if f.text.GetStringHeight then
        local h = tonumber(f.text:GetStringHeight())
        if h then f:SetHeight(math.max(172, 128 + h)) end
    end
    return cur ~= nil or o.lv == nil
end
function MC.ShowAsk()
    local f = MC.BuildAsk()
    if not MC.Current() then return nil end
    MC.RefreshAsk()
    if not f:IsShown() then
        f:Show()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
    end
    return f
end
function MC.HideAsk()
    if MC.cast and MC.askFrame and not combat() then
        local a = rg(MC.cast, "anchor")
        if a == MC.askFrame.cw or a == MC.askFrame.cf then MC.cast:Hide(); MC.cast.anchor = nil end
    end
    if MC.askFrame then MC.askFrame:Hide() end
    for k, o in pairs(MC.orders) do if rg(o, "preview") then MC.orders[k] = nil end end
end
function MC.PickLevel(req)
    local o = MC.Current()
    if not (o and tonumber(req)) then return false end
    o.lv, o.src = tonumber(req), "pick"
    MC.RefreshAsk()
    return true
end
-- 这一单不用了（「不用」）：有下一位就换，没有就收起
function MC.Done(s)
    if s then MC.orders[s] = nil end
    MC.cur = nil
    if MC.Current() then MC.RefreshAsk() else MC.HideAsk() end
end
function MC.Next()
    local list = MC.Orders()
    if #list < 2 then return end
    local idx = 1
    for i, o in ipairs(list) do if o.short == MC.cur then idx = i end end
    local o = list[idx % #list + 1]
    MC.cur = o.short
    MC.RefreshAsk()
end

-- ---------- 交易：接「法师吃喝」的「一键放入」----------
--   开交易的对象是弹窗里要过水的人（5 分钟内）→ 加载法师吃喝子插件（按需；它的总开关关着 = 不注册任何自动行为），
--   只把交易窗下的「一键放入」按钮摆出来；tradeReplied 置上 → 点了按钮也不自动密话（默认不发话）
--   法师吃喝总开关开着时它自己会出按钮（DungeonChatCore 的 TRADE_SHOW 转给它），这里不插手
local function tradeName()
    local who = fullName("NPC")
    if (not who or who == "") and _G.TradeFrameRecipientNameText and TradeFrameRecipientNameText.GetText then
        who = clean(call(TradeFrameRecipientNameText.GetText, TradeFrameRecipientNameText))
    end
    return who
end
function MC.OnTradeShow()
    if not (MC.IsMage() and MC.PopOn()) or combat() then return false, "off" end
    local who = tradeName()
    local o = who and MC.orders[short(who)]
    if not o or rg(o, "preview") or now() - o.t > MC.ORDER_TTL then return false, "noorder" end
    local MW = ns.MageWater
    if MW and MW.On and MW.On() then return false, "mw" end
    if not MW and ns.GroupLoadMage then pcall(ns.GroupLoadMage, true); MW = ns.MageWater end
    if not (MW and MW.ShowGive) then return false, "nomw" end
    if MW.On and MW.On() then return false, "mw" end
    MW.tradeOpen, MW.tradeWith, MW.tradeReplied = true, who, true
    if MW.orders then MW.orders[who] = { who = who, cls = o.cls, lv = o.lv, water = o.water, food = o.food, t = now() } end
    local ok = MW.ShowGive()
    if MW.SyncEvents then pcall(MW.SyncEvents) end   -- 交易开着 → 它会注册 TRADE_CLOSED，关窗时自己收按钮
    return ok and true or false
end

-- ---------- 事件 ----------
local PAGE_EV = { "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED", "UNIT_LEVEL", "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED" }
local POP_EV = { "CHAT_MSG_WHISPER", "TRADE_SHOW" }
local ev = CreateFrame("Frame")
MC.ev = ev
function MC.Sync()
    local mage = ns.db ~= nil and MC.IsMage()
    local pop = mage and MC.PopOn()
    for _, e in ipairs(PAGE_EV) do if mage then pcall(ev.RegisterEvent, ev, e) else pcall(ev.UnregisterEvent, ev, e) end end
    for _, e in ipairs(POP_EV) do if pop then pcall(ev.RegisterEvent, ev, e) else pcall(ev.UnregisterEvent, ev, e) end end
    MC.synced = { mage = mage and true or false, pop = pop and true or false }
    return MC.synced
end
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, e, a1, a2, ...)
    if e == "PLAYER_LOGIN" then pcall(MC.Sync); return end
    if e == "CHAT_MSG_WHISPER" then pcall(MC.OnWhisper, a1, a2, (select(10, ...))); return end
    if e == "TRADE_SHOW" then pcall(MC.OnTradeShow); return end
    if not (ns.db and MC.IsMage()) then return end
    if e == "PLAYER_REGEN_ENABLED" then
        -- 脱战：鼠标还停在某个按钮上 → 把安全按钮补盖上去
        if hoverBtn and hoverBtn.IsMouseOver and hoverBtn:IsMouseOver() and hoverBtn:IsVisible() then pcall(MC.Hover, hoverBtn) end
    end
    if MC.PageShown() then pcall(MC.RefreshPage) end
    if MC.askFrame and MC.askFrame:IsShown() then
        -- 队伍 / 等级变了：弹窗那一单的等级按队伍重读（玩家手选的不动）
        local o = MC.Current()
        if o and o.src ~= "pick" then
            local lv, src = MC.LevelOf(o.who, o.msg)
            if lv then o.lv, o.src = lv, src end
        end
        pcall(MC.RefreshAsk)
    end
end)
MC._event = ev:GetScript("OnEvent")   -- 测试用
table.insert(ns.modules, function() pcall(MC.Sync) end)

-- ---------- 页 / 设置 / 命令 ----------
ns.RegisterPage({ key = "conj", order = 1.47, class = "Mage", title = L("造水", "Conjure"), tabTitle = L("造水", "Conjure"),
    icon = "Interface\\Icons\\INV_Drink_18",
    build = function(p) MC.BuildPage(p) end,
    refresh = function(p) MC.RefreshPage(p) end })

if ns.RegisterSettings then
    ns.RegisterSettings({ key = "conj", order = 59, page = "conj", avail = function() return ns.MageConjure ~= nil and MC.IsMage() end,
        title = function() return L("造水（法师）", "Conjure (mage)") end, short = function() return L("造水", "Conjure") end,
        items = {
            { type = "check", id = "conj.pop", text = function() return L("有人密我要水 / 面包时弹窗（按他的等级一键造对应的档）", "Pop a prompt when someone whispers for water / food (one click conjures the right tier)") end,
              get = function() return MC.PopOn() end, set = function(v) MC.SetOpt("pop", v) end },
            { type = "check", id = "conj.reply", indent = 18, text = function() return L("弹窗时自动私聊回他一句「稍等，给你造…」（带前缀，默认关）", "Also whisper back \"conjuring, one sec\" (prefixed; off by default)") end,
              get = function() return MC.Opt("reply") and true or false end, set = function(v) MC.SetOpt("reply", v) end },
            { type = "button", id = "conj.preview", w = 140, text = function() return L("弹一个示例窗", "Show a sample") end, click = function() MC.Preview() end },
            { type = "button", id = "conj.resetpos", w = 140, inline = true, x = 160, text = function() return L("弹窗位置重置", "Reset position") end,
              click = function()
                  MC.DB().pos = nil
                  if MC.askFrame then MC.askFrame:ClearAllPoints(); MC.askFrame:SetPoint("TOP", UIParent, "TOP", 0, -180) end
              end },
            { type = "note", text = function() return L("和组队页「法师吃喝」总开关无关：那个管队友自动回话 / 提醒条；这里只管密语弹窗和本页按钮，默认不发任何话",
                "Separate from the Group tab's Mage food switch (auto-replies / request bar); this only pops the whisper prompt, and sends nothing by default") end },
        } })
end

ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash["造水"] = function(rest)
    if rest == "测试" or rest == "test" then MC.Preview() else MC.Open() end
end
ns.ExtraSlash.conj = ns.ExtraSlash["造水"]
