-- 队里有术士就提醒绑灵魂石（11-21 用户截图（队伍框两个「死亡」）「对里有SS就提醒帮石头」）
--   11-21 用户「都按推荐」：放在信标里登录内存超预算（+38 KB）→ 搬进按需加载的 GearInsight_Forever_GroupMage（法师吃喝子插件）后解除 HOLD。
--     登录加载的组队信标 BuffAsk.lua 只留几行：副本里 · 组队 · 我不是术士 · 开关开着 → ns.LoadModule("mage") 加载本文件，再把那次进本 / 队伍变动转给 SA._event；
--     「/gi buff 石头 …」和窗口与提醒「灵魂石提醒（队友）」（ssAsk）的占位也在 BuffAsk.lua（没加载时先加载再转过来；术士角色只改开关）。
--     ⛔ 术士角色：本文件开头就返回（非法师默认登录就会加载 _GroupMage 的野外要水 / 道谢，术士也一样 —— 这里什么都不建）
--   术士自己那一头（小条 / 倒计时 / 安全按钮）是 _Class 的 Soulstone.lua（11-18，HOLD）；本文件管「我不是术士、队里有术士」这一头
--   ① 什么时候问：在副本（5 人本 / 团本）的队伍里 · 我不是术士 · 队里有在线、附近（BA.Near）的术士 · 全队（含我）身上都读得到、都没有「灵魂石复活」
--      → 进本 5 秒后 / 队伍变动 2 秒后查一次；每次进本只问一次（出副本 / 换副本才清）；战斗中不查（脱战后补一次）
--      ⛔ 光环读到秘密值 = 不知道有没有 → 不问（宁可漏问也不喊错）
--   ② 怎么问：借要 BUFF（BuffAsk.lua）同一个小框 ——「队里有术士 XX，还没人绑灵魂石（倒了能原地起来），一般绑给治疗 YY」
--      [队伍里说] [密他] [以后别问]；⛔ 点了才发，话不带插件名（11-13 网易DD）；同一个人 10 分钟内和要 BUFF 合起来只密一次（BA.RecentlyAsked）
--      绑给谁：职责标了治疗的 → 按职业猜 牧师 > 萨满 > 德鲁伊 > 圣骑士（同 Soulstone.lua 的 SS.HEAL_ORDER）；我就是治疗 = 「给我绑一个」；没有治疗 = 不点名
--   ③ 开关：ns.db.buffAsk.ss（nil = 开，false = 关）；要 BUFF 总开关关了也不问。/gi buff 石头 开 | 关 | 测试；「以后别问」后从 窗口与提醒「灵魂石提醒（队友）」找回
--   buff「灵魂石复活」法术 id 20707 / 20762 / 20763 / 20764 / 20765 = 经典值（同 Soulstone.lua，需核对），运行时再读物品上的法术名 / id 补；名字或 id 任一对上就算
local _, ns = ...; ns = _G.GearInsightForever or ns
local L = function(cn, en) return ns.L(cn, en) end
local CL = function(cn, en) return ns.ChatL(cn, en) end
local BA = ns.BuffAsk
local DC = ns.DungeonChat
if not (BA and DC) or select(3, pcall(UnitClass, "player")) == "WARLOCK" then return end

local SA = { done = {} }
ns.SoulstoneAsk = SA
SA.ENTER_DELAY, SA.ROSTER_DELAY = 5, 2
SA.ITEMS = { 16896, 16895, 16893, 16892, 5232 }   -- 特效 / 强效 / 灵魂石 / 次级 / 初级（同 Soulstone.lua SS.ITEMS）
SA.BUFF_IDS = { [20707] = true, [20762] = true, [20763] = true, [20764] = true, [20765] = true }
SA.BUFF_NAMES = { ["灵魂石复活"] = true, ["Soulstone Resurrection"] = true }
SA.HEAL_ORDER = { PRIEST = 1, SHAMAN = 2, DRUID = 3, PALADIN = 4 }

local function clean(v)
    if v == nil or (ns.Secret and ns.Secret(v)) then return nil end
    return v
end
local function sec(v) return v ~= nil and ns.Secret ~= nil and ns.Secret(v) and true or false end
local function pass(ok, ...) if ok then return ... end return nil end
local function call(f, ...) if type(f) ~= "function" then return nil end return pass(pcall(f, ...)) end
local function combat() return InCombatLockdown and InCombatLockdown() and true or false end
local function wall() return (time and time()) or 0 end
local function unitClass(u) local _, c = call(UnitClass, u); return clean(c) end
local short = DC.Short

function SA.On()
    local d = ns.db and BA.DB()
    return d ~= nil and BA.Opt("on") and d.ss ~= false
end
function SA.SetOn(v)
    if v then BA.DB().ss = nil else BA.DB().ss = false end   -- 11-21 修：原 `(not v) and false or nil` 恒为 nil，「关」从来关不上
    if v and not BA.Opt("on") then BA.SetOpt("on", true) end
    SA.Sync()
end

-- 运行时补 buff 名字 / id（物品信息没缓存好时拿不到 → 下次再读）
function SA.Learn()
    if SA.learned then return end
    local gis = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    local got = false
    for _, id in ipairs(SA.ITEMS) do
        local n, sid = call(gis, id)
        n, sid = clean(n), tonumber(clean(sid))
        if type(n) == "string" and n ~= "" then SA.BUFF_NAMES[n] = true; got = true end
        if sid then SA.BUFF_IDS[sid] = true end
    end
    for id in pairs(SA.BUFF_IDS) do
        local n = BA.SpellName and BA.SpellName(id)
        if n then SA.BUFF_NAMES[n] = true; got = true end
    end
    SA.learned = got
end

-- 这个人身上有没有灵魂石：true / false / nil（读不到 = 不知道）
local function auraAt(u, i)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local a = call(C_UnitAuras.GetAuraDataByIndex, u, i, "HELPFUL")
        if a == nil then return nil end
        if sec(a) or type(a) ~= "table" or sec(a.name) or sec(a.spellId) then return false end
        return true, a.name, tonumber(a.spellId)
    end
    if not UnitBuff then return nil end
    local r = { pcall(UnitBuff, u, i) }
    if not r[1] or r[2] == nil then return nil end
    if sec(r[2]) or sec(r[11]) then return false end
    return true, r[2], tonumber(r[11])
end
function SA.HasStone(u)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) and not UnitBuff then return nil end
    for i = 1, 40 do
        local okA, name, id = auraAt(u, i)
        if okA == nil then return false end
        if okA == false then return nil end
        if (id and SA.BUFF_IDS[id]) or (name and SA.BUFF_NAMES[name]) then return true end
    end
    return false
end

local function members()
    local out = { "player" }
    if clean(call(IsInRaid)) then
        for i = 1, 40 do local u = "raid" .. i; if clean(call(UnitExists, u)) and not clean(call(UnitIsUnit, u, "player")) then out[#out + 1] = u end end
    else
        for i = 1, 4 do local u = "party" .. i; if clean(call(UnitExists, u)) then out[#out + 1] = u end end
    end
    return out
end
local function fullName(u)
    local n = clean(call(GetUnitName, u, true))
    return type(n) == "string" and n ~= "" and n or nil
end
-- 该绑给谁：{ unit, who, me }；没有治疗 = nil
function SA.Healer(list)
    local best, bestP
    for _, u in ipairs(list) do
        local role = clean(call(UnitGroupRolesAssigned, u))
        local cls = unitClass(u)
        local p = (role == "HEALER" and 0) or (role ~= "TANK" and role ~= "DAMAGER" and SA.HEAL_ORDER[cls or ""]) or nil
        if p and not clean(call(UnitIsDeadOrGhost, u)) and (not bestP or p < bestP) then best, bestP = u, p end
    end
    if not best then return nil end
    return { unit = best, who = fullName(best), me = best == "player" }
end

-- 查一次：返回 true = 弹了；false, 原因（测试 / 诊断用）
function SA.Check()
    if not SA.On() then return false, "off" end
    if combat() then SA.pending = true; return false, "combat" end
    local inInst, inst = BA.InDungeon()
    if not (inInst and clean(call(IsInGroup))) then return false, "nodungeon" end
    if unitClass("player") == "WARLOCK" then return false, "iamwarlock" end
    if SA.done[inst] then return false, "done" end
    local list = members()
    local lock
    for _, u in ipairs(list) do
        if u ~= "player" and unitClass(u) == "WARLOCK" and BA.Near(u) and not clean(call(UnitIsDeadOrGhost, u)) then
            local lv = tonumber(clean(call(UnitLevel, u)))
            if not lv or lv <= 0 or lv >= 18 then lock = u; break end   -- 18 级才学会制造灵魂石
        end
    end
    if not lock then return false, "nolock" end
    local who = fullName(lock)
    if not who then return false, "noname" end
    SA.Learn()
    for _, u in ipairs(list) do
        local has = SA.HasStone(u)
        if has == nil then return false, "unknown" end
        if has then SA.done[inst] = true; return false, "has" end
    end
    if BA.frame and BA.frame:IsShown() and BA.cur and not BA.cur.ss then return false, "busy" end
    SA.done[inst] = true
    SA.Show({ who = who, heal = SA.Healer(list) })
    return true
end

function SA.ChatText(o)
    local h = o.heal
    local cw = (ns.CallWord and ns.CallWord()) or CL("义父", "hey")
    if h and h.me then return string.format(CL("%s，方便给我绑个灵魂石吗？谢谢~", "%s, could you put a Soulstone on me? Thanks!"), cw) end
    if h and h.who then return string.format(CL("%s，方便给 %s 绑个灵魂石吗？谢谢~", "%s, could you Soulstone %s? Thanks!"), cw, short(h.who) or h.who) end
    return string.format(CL("%s，方便给队里绑个灵魂石吗？谢谢~", "%s, could you Soulstone someone? Thanks!"), cw)
end
function SA.PartyText(o)
    return (short(o.who) or o.who) .. CL("，", ", ") .. SA.ChatText(o)
end
function SA.Text(o)
    local h = o.heal
    local tgt = (h and h.me and L("你是治疗，可以让他绑给你", "you're the healer - ask for it"))
        or (h and h.who and string.format(L("一般绑给治疗 %s", "usually on the healer, %s"), short(h.who) or h.who))
        or L("一般绑给治疗", "usually on the healer")
    return string.format(L("队里有术士 %s，还没人身上有灵魂石（倒了能原地起来，团灭不用跑尸），%s", "Your group has a Warlock (%s) but nobody has a Soulstone (lets one player resurrect in place); %s"),
        short(o.who) or o.who, tgt) .. "\n|cff999999" .. L("队伍里会说：", "Party message: ") .. SA.PartyText(o) .. "|r"
end

-- 按钮悬停说明：要 BUFF 的说明按 BA.cur.dungeon 分流，灵魂石框换成自己的（包一层 OnEnter，第一次弹时装）
SA.TIPS = {
    ask = function(o) return L("点了才发，在队伍频道说：\n", "Sends this to party chat (only when you click):\n") .. SA.PartyText(o) end,
    no = function(o) return L("点了才发，私聊术士：\n", "Whispers the Warlock (only when you click):\n") .. SA.ChatText(o) end,
    mute = function() return L("队里有术士不再提醒绑灵魂石（/gi buff 石头 开 重新打开）", "Stop Soulstone prompts (/gi buff soulstone on to re-enable)") end,
}
local function hookTips(f)
    if f._ssTips then return end
    f._ssTips = true
    for k, tipf in pairs(SA.TIPS) do
        local b = f[k]
        local orig = b and b.GetScript and b:GetScript("OnEnter")
        if b then
            b:SetScript("OnEnter", function(self, ...)
                local o = BA.cur
                if not (o and o.ss) then if orig then return orig(self, ...) end return end
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:AddLine(self.label, 1, 0.82, 0)
                GameTooltip:AddLine(tipf(o), 1, 1, 1, true)
                GameTooltip:Show()
            end)
        end
    end
end
function SA.Show(o)
    local f = BA.Build()
    hookTips(f)
    BA.cur = { ss = true, who = o.who, heal = o.heal, sample = o.sample }
    f.title:SetText(L("灵魂石 · 队里有术士", "Soulstone - your group has a Warlock"))
    f.ask:SetText(L("队伍里说", "Ask party")); f.ask.label = L("队伍里说", "Ask party")
    f.no:SetText(L("密他", "Whisper")); f.no.label = L("密他", "Whisper")
    f.mute:SetText(L("以后别问", "Don't ask again")); f.mute.label = L("以后别问", "Don't ask again")
    f.never:Hide()
    for _, b in ipairs(f.picks or {}) do b:Hide() end
    if f.pickLbl then f.pickLbl:Hide() end
    BA.PaintExtras(f, false)
    f.text:SetText(SA.Text(o))
    local h = f.text.GetStringHeight and tonumber(f.text:GetStringHeight())
    if h then f:SetHeight(math.max(112, 72 + h)) end
    f.age = 0
    f:Show()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
    return f
end
local function sendOK()
    if BA.CanChat() then return true end
    ns.Print(L("现在发不了（战斗中 / 聊天受限），过一会儿再点", "Can't send right now (combat / chat locked) - try again in a moment"))
    return false
end
function SA.Party()
    local o = BA.cur
    if not (o and o.ss) or o.sample then BA.HideField(); return false end
    if not sendOK() then return false end
    if not BA.Send(SA.PartyText(o), clean(call(IsInRaid)) and "RAID" or "PARTY") then return false end
    BA.MarkAsked(o.who, wall())
    BA.HideField()
    return true
end
function SA.Whisper()
    local o = BA.cur
    if not (o and o.ss) or o.sample then BA.HideField(); return false end
    if not sendOK() then return false end
    local t = wall()
    if BA.RecentlyAsked(o.who, t) then
        ns.Print(string.format(L("10 分钟内密过 %s 了，这次不再密", "Already whispered %s in the last 10 min"), short(o.who) or o.who))
        BA.HideField()
        return false
    end
    if not BA.Send(SA.ChatText(o), "WHISPER", o.who) then return false end
    BA.MarkAsked(o.who, t)
    BA.HideField()
    return true
end
function SA.Never()
    BA.HideField()
    BA.DB().ss = false
    SA.Sync()
    if ns.CloseHint then
        ns.CloseHint("ssAsk", L("队里有术士不再提醒绑灵魂石。找回：GI 菜单 → 设置 → 窗口与提醒「灵魂石提醒（队友）」点「打开」，或 /gi buff 石头 开",
            "Soulstone prompt turned off. Bring it back: GI menu > Settings > Windows & alerts > Soulstone prompt, or /gi buff soulstone on"))
    end
end

-- 三个按钮：要 BUFF 的框按 BA.cur 分流，灵魂石框先截下来（包一层，不改 BuffAsk.lua）
for k, fn in pairs({ BtnA = SA.Party, BtnB = SA.Whisper, BtnC = SA.Never }) do
    local orig = BA[k]
    BA[k] = function(...) if BA.cur and BA.cur.ss then return fn() end return orig(...) end
end

-- ---------- 事件（只在开着时注册）----------
local ev = CreateFrame("Frame")
local function soon(delay)
    if not (C_Timer and C_Timer.After) then return pcall(SA.Check) end
    C_Timer.After(delay, function() pcall(SA.Check) end)
end
ev:SetScript("OnEvent", function(_, e)
    if e == "PLAYER_ENTERING_WORLD" or e == "ZONE_CHANGED_NEW_AREA" then
        local inInst, inst = BA.InDungeon()
        if not inInst then SA.done = {} elseif SA.lastInst ~= inst then SA.done = {} end
        SA.lastInst = inInst and inst or nil
        if not inInst and BA.cur and BA.cur.ss then BA.HideField() end
        if inInst then soon(SA.ENTER_DELAY) end
    elseif e == "GROUP_ROSTER_UPDATE" then
        if BA.InDungeon() then soon(SA.ROSTER_DELAY) end
    elseif e == "PLAYER_REGEN_ENABLED" then
        if SA.pending then SA.pending = nil; soon(2) end
    end
end)
SA._event = ev:GetScript("OnEvent")   -- 测试用
function SA.Sync()
    local on = SA.On() and unitClass("player") ~= "WARLOCK"
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED" }) do
        if on then pcall(ev.RegisterEvent, ev, e) else pcall(ev.UnregisterEvent, ev, e) end
    end
end
local _groupSync = ns.GroupSync
if type(_groupSync) == "function" and not SA.wrapped then
    SA.wrapped = true
    ns.GroupSync = function(...)
        local r = { _groupSync(...) }
        if ns.db then pcall(SA.Sync) end
        return unpack(r)
    end
end
if ns.db then pcall(SA.Sync) end

-- /gi buff 石头 开 | 关 | 测试（其余照旧交给要 BUFF）
ns.ExtraSlash = ns.ExtraSlash or {}
local _slash = ns.ExtraSlash.buff
local function slash(rest)
    local arg = (rest or ""):match("^石头%s*(.*)$") or (rest or ""):match("^灵魂石%s*(.*)$") or (rest or ""):match("^soulstone%s*(.*)$") or (rest or ""):match("^ss%s*(.*)$")
    if not arg then if _slash then return _slash(rest) end return end
    if arg == "开" or arg == "on" then SA.SetOn(true)
    elseif arg == "关" or arg == "off" then SA.SetOn(false)
    elseif arg == "测试" or arg == "test" then
        SA.Show({ who = L("示例术士", "Sample Warlock"), heal = { who = L("示例牧师", "Sample Priest") }, sample = true })
        return
    end
    ns.Print(L("队里有术士提醒绑灵魂石：", "Soulstone prompt: ") .. (SA.On() and L("开", "on") or L("关", "off")) .. L("（/gi buff 石头 开 | 关 | 测试）", " (/gi buff soulstone on | off | test)"))
end
for _, c in ipairs({ "buff", "要buff", "要BUFF" }) do ns.ExtraSlash[c] = slash end

-- 窗口与提醒「灵魂石提醒（队友）」（ssAsk）登记在登录加载的 BuffAsk.lua（本文件没加载时也能关 / 找回），按钮走上面的 /gi buff 石头
