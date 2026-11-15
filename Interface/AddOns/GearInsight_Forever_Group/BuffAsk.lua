-- 要 BUFF（11-15 用户「搞一个组件，可以自动要BUFF，最好是操作了才要，不要自动发，探测附近有啥，然后如果副本的话，自动检测，缺了自动（进入副本开始，看队伍配置）」）
--   HOLD：游戏内实测前不进发行包（登记在本目录 _hold.txt）。思路照法师吃喝 MageWater.lua 的「野外弹框 / 副本自动要」，泛化成 BUFF；不改 MageWater。
--   ① 野外 / 主城（不在任何副本 / 战场）：目标 / 鼠标指向 / 友方姓名板 / 队友名单来了一个单位查一个（不轮询）——
--      同阵营在线玩家，职业能给我身上还没有、而且对我有用的 BUFF → 弹小框「附近有牧师 XX，你没有耐力，要不要密他要？」
--      ⛔ 只弹框：玩家点「密他要」才发私聊；不点不发。同一个人 10 分钟内只问一次（不管点没点）；任意两次弹框至少隔 2 分钟；
--      「这次不再提示」= 本次登录不再弹（/reload 或重登恢复）；弹框 60 秒没人理自己收起；进战斗 / 进副本收起
--   ② 副本（IsInInstance = party / raid）：进本 5 秒后 + 队伍变动 2 秒后看队伍配置：队里哪些职业能给哪些 BUFF、我身上缺哪个 →
--      缺了且队里有人能给 → 自动发一句（默认队伍频道，团队里发团队频道；设置里可改成私聊那个人）。
--      每次进本每种 BUFF 只要一次（出副本 / 换副本才清）；战斗中不发（脱战后补查一次）；任意两次自动发至少隔 COOLDOWN 秒；
--      同一个人 10 分钟内野外弹框 / 副本自动要合起来只密一次（BA.RecentlyAsked）
--   BUFF：耐力（牧师）/ 智力（法师）/ 野性印记（德鲁伊）/ 圣骑士祝福（近战要力量、其余要智慧；身上已经有任何一种祝福 = 不缺）
--      对我有用：战士 / 盗贼不要智力和智慧祝福；自己职业能给的不要（自己加）
--      法术 ID：开服客户端技能书 services/dashboard/static/data/forever/spellbook.json（1.60.1.70862，wago.tools DB2）逐级列全，
--      单体王者祝福 20217 = PallyBless.lua（训练师 20 级学，无限技能书里没有这条单列）。读光环按 spellId，读不到 ID 再按客户端法术名
--   ⛔ 发的话不带插件名（11-13 网易DD：自动发言别带插件名）→ 不走 DC.Tagged，直接发正文；战斗中 / 聊天锁定不发；秘密值（issecretvalue）一律当读不到
--   开关（ns.db.buffAsk；nil = 默认）：总开关 on（开）· 野外弹框 field（开）· 副本自动要 auto（开，用户「缺了自动」）· 副本里改私聊 whisper（关 = 发队伍频道）
--   设置：本文件登记 ns.RegisterSettings（组队抽屉齿轮「组队设置」+ 全部设置索引，key = buffask）；命令 /gi buff（/gi 要buff）
local _, ns = ...; ns = _G.GearInsightForever or ns
local L = function(cn, en) return ns.L(cn, en) end
local DC = ns.DungeonChat
if not DC then return end

local BA = { runAsked = {}, peek = {} }
ns.BuffAsk = BA
BA.ASK_CD = 600        -- 同一个人 10 分钟内只问一次（野外弹框 + 副本自动要合起来）
BA.FIELD_GAP = 120     -- 任意两次野外弹框
BA.FIELD_TTL = 60      -- 弹框自己收起
BA.PEEK = 30           -- 看过但不弹的人（不缺 / 等级不够），这么久内不再算
BA.COOLDOWN = 20       -- 副本里任意两次自动发
BA.ENTER_DELAY = 5     -- 进副本后等几秒（过完读条、队友单位就绪、BUFF 读得到）

-- ---------- 数据（来源见文件头）----------
--   k = 键；cls = 谁能给；lv = 最低几级能给（第一级的学习等级）；ids = 这一类的所有法术（各等级 + 团队版 / 强效版：任何一个在身上都算有）
--   fam = 同一家（圣骑士祝福：力量 / 智慧 / 王者任何一种在身上都算有了祝福）
BA.TYPES = {
    { k = "fort", cls = "PRIEST", lv = 1, cn = "耐力", en = "Fortitude",
      ids = { 1243, 1244, 1245, 2791, 10937, 10938,   -- 真言术：韧 1-6 级
              21562, 21564 } },                       -- 坚韧祷言 1-2 级
    { k = "int", cls = "MAGE", lv = 1, cn = "智力", en = "Intellect", mana = true,
      ids = { 1459, 1460, 1461, 10156, 10157,         -- 奥术智慧 1-5 级
              23028 } },                              -- 奥术光辉
    { k = "motw", cls = "DRUID", lv = 1, cn = "野性印记", en = "Mark of the Wild",
      ids = { 1126, 5232, 6756, 5234, 8907, 9884, 9885,   -- 野性印记 1-7 级
              21849, 21850 } },                           -- 野性赐福 1-2 级
    { k = "might", cls = "PALADIN", lv = 4, fam = "bless", melee = true, cn = "力量祝福", en = "Blessing of Might",
      ids = { 19740, 19834, 19835, 19836, 19837, 19838, 25291,   -- 力量祝福 1-7 级
              25782, 25916 } },                                  -- 强效力量祝福 1-2 级
    { k = "wis", cls = "PALADIN", lv = 14, fam = "bless", mana = true, cn = "智慧祝福", en = "Blessing of Wisdom",
      ids = { 19742, 19850, 19852, 19853, 19854, 25290,          -- 智慧祝福 1-6 级
              25894, 25918 } },                                  -- 强效智慧祝福 1-2 级
    { k = "kings", cls = "PALADIN", lv = 20, fam = "bless", noAsk = true, cn = "王者祝福", en = "Blessing of Kings",
      ids = { 20217, 25898 } },                                  -- 王者祝福 / 强效王者祝福：只用来认「身上有祝福了」，不主动要
}
BA.BY_K = {}
for _, t in ipairs(BA.TYPES) do BA.BY_K[t.k] = t end
BA.CLS_CN = { PRIEST = { "牧师", "Priest" }, MAGE = { "法师", "Mage" }, DRUID = { "德鲁伊", "Druid" }, PALADIN = { "圣骑士", "Paladin" } }
-- 没蓝的职业（智力 / 智慧祝福没用）；只吃力量祝福的近战
BA.NO_MANA = { WARRIOR = true, ROGUE = true, DEATHKNIGHT = true }
BA.MELEE = { WARRIOR = true, ROGUE = true, DEATHKNIGHT = true }

-- ---------- 小工具 ----------
local function now() return (GetTime and GetTime()) or 0 end
local function wall() return (time and time()) or 0 end
local function clean(v)
    if v == nil or (ns.Secret and ns.Secret(v)) then return nil end
    return v
end
local function pass(ok, ...) if ok then return ... end return nil end
local function call(f, ...)
    if type(f) ~= "function" then return nil end
    return pass(pcall(f, ...))
end
local short = DC.Short
local function combat() return InCombatLockdown and InCombatLockdown() and true or false end
local function unitClass(u) local _, c = call(UnitClass, u); return clean(c) end
local function myClass() return unitClass("player") end
local function exists(u) return clean(call(UnitExists, u)) and true or false end
local function isMe(u) return clean(call(UnitIsUnit, u, "player")) and true or false end
local function bool(v) return clean(v) and true or false end
-- 单位等级：-1（骷髅，高我 10 级以上）当 60；读不到 = nil
local function unitLevel(u)
    local v = tonumber(clean(call(UnitLevel, u)))
    if not v then return nil end
    if v < 0 then return 60 end
    if v == 0 then return nil end
    return v
end
local function clsName(cls)
    local c = BA.CLS_CN[cls]
    return c and L(c[1], c[2]) or (cls or "")
end
local function buffName(t) return L(t.cn, t.en) end

-- ---------- 设置（ns.db.buffAsk；nil = 默认值）----------
BA.DEFAULTS = { on = true, field = true, auto = true, whisper = false }
function BA.DB()
    ns.db.buffAsk = ns.db.buffAsk or {}
    local d = ns.db.buffAsk
    d.asked = d.asked or {}
    return d
end
function BA.Opt(k)
    if not ns.db then return BA.DEFAULTS[k] end
    local v = BA.DB()[k]
    if v == nil then return BA.DEFAULTS[k] end
    return v and true or false
end
function BA.SetOpt(k, v)
    v = v and true or false
    if v == BA.DEFAULTS[k] then BA.DB()[k] = nil else BA.DB()[k] = v end
    if not BA.FieldOn() and BA.frame and BA.frame:IsShown() then BA.HideField() end
    if BA.SyncEvents then pcall(BA.SyncEvents) end
end
function BA.FieldOn() return BA.Opt("on") and BA.Opt("field") end
function BA.AutoOn() return BA.Opt("on") and BA.Opt("auto") end

-- ---------- 对我有用的 BUFF ----------
-- 这一类对 cls 职业有没有用（noAsk 的王者不主动要；自己职业给得了的不要）
function BA.Useful(t, cls)
    if t.noAsk then return false end
    if cls and t.cls == cls then return false end
    if t.mana and cls and BA.NO_MANA[cls] then return false end
    if t.melee and not (cls and BA.MELEE[cls]) then return false end
    return true
end

-- ---------- 读我身上的 BUFF ----------
--   返回 { [spellId] = true }, { [名字] = true }；读不到（秘密值 / 接口不在）返回 nil —— 读不到就当「不知道」，不要
local function auraAt(i)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local a = call(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if a == nil then return nil end
        if type(a) ~= "table" then return false end
        return true, a.name, a.spellId
    end
    if UnitBuff then
        local r = { pcall(UnitBuff, "player", i) }
        if not r[1] or r[2] == nil then return nil end
        return true, r[2], r[11]
    end
    return nil
end
function BA.MyAuras()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) and not UnitBuff then return nil end
    local ids, names = {}, {}
    for i = 1, 40 do
        local okA, name, id = auraAt(i)
        if okA == nil then break end
        if okA == false then return nil end
        if (name ~= nil and clean(name) == nil) or (id ~= nil and clean(id) == nil) then return nil end   -- 秘密值：整张表不可信
        id = tonumber(id)
        if id then ids[id] = true end
        if type(name) == "string" and name ~= "" then names[name] = true end
    end
    return ids, names
end
-- 法术名（客户端；缓存）
local NAME = {}
local function spellName(id)
    if NAME[id] ~= nil then return NAME[id] or nil end
    local n
    if C_Spell and C_Spell.GetSpellName then n = call(C_Spell.GetSpellName, id) end
    if (type(n) ~= "string" or n == "") and GetSpellInfo then n = call(GetSpellInfo, id) end
    n = clean(n)
    NAME[id] = (type(n) == "string" and n ~= "") and n or false
    return NAME[id] or nil
end
BA.SpellName = spellName
local function hasType(t, ids, names)
    for _, id in ipairs(t.ids) do
        if ids[id] then return true end
        local n = spellName(id)
        if n and names[n] then return true end
    end
    return false
end
-- 我缺的（对我有用、身上没有）：{ [k] = true }；读不到光环 = nil
function BA.Missing()
    local ids, names = BA.MyAuras()
    if not ids then return nil end
    local cls = myClass()
    local fam = {}
    for _, t in ipairs(BA.TYPES) do
        if t.fam and hasType(t, ids, names) then fam[t.fam] = true end
    end
    local out = {}
    for _, t in ipairs(BA.TYPES) do
        if BA.Useful(t, cls) and not (t.fam and fam[t.fam]) and not hasType(t, ids, names) then out[t.k] = true end
    end
    return out
end
-- giverCls 职业、giverLv 级的人能给我的、我缺的：{ t, … }（按 TYPES 顺序）
function BA.CanGive(giverCls, giverLv, missing)
    local out = {}
    if not missing then return out end
    for _, t in ipairs(BA.TYPES) do
        if t.cls == giverCls and missing[t.k] and (not giverLv or giverLv >= t.lv) then out[#out + 1] = t end
    end
    return out
end

-- ---------- 话术（⛔ 不带插件名；简短礼貌）----------
local function joinNames(list)
    local n = {}
    for _, t in ipairs(list) do n[#n + 1] = buffName(t) end
    return table.concat(n, L("和", " and "))
end
-- 对一个职业要：「牧师老板，求个耐力，谢谢~」
function BA.AskText(giverCls, list)
    if not list or #list == 0 then return nil end
    return clsName(giverCls) .. L("老板，求个", ", could I get ") .. joinNames(list) .. L("，谢谢~", " please? Thanks!")
end
-- 队伍频道一句话要几样：一个职业 = 同上；几个职业 = 「各位老板，求个耐力、智力，谢谢~」
function BA.PartyText(plan)
    if #plan == 0 then return nil end
    if #plan == 1 then return BA.AskText(plan[1].cls, plan[1].list) end
    local n = {}
    for _, p in ipairs(plan) do for _, t in ipairs(p.list) do n[#n + 1] = buffName(t) end end
    return L("各位老板，求个", "Could I get ") .. table.concat(n, L("、", ", ")) .. L("，谢谢~", " please? Thanks!")
end

-- ---------- 发话 ----------
function BA.CanChat()
    if combat() then return false end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and call(C_ChatInfo.InChatMessagingLockdown) then return false end
    return true
end
function BA.Send(text, chan, to)
    if not text or not BA.CanChat() then return false end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    return (pcall(send, DC.CutBytes(text, DC.MAX_BYTES), chan, nil, to))
end
-- 同一个人 10 分钟内问过没有（存档里存 time() 秒：/reload、重登也接得上）
function BA.RecentlyAsked(who, t)
    t = t or wall()
    local last = who and BA.DB().asked[who]
    return (type(last) == "number" and last <= t and t - last < BA.ASK_CD) and true or false
end
local function mark(tbl, who, t)
    for k, v in pairs(tbl) do if type(v) ~= "number" or v > t or t - v > 3600 then tbl[k] = nil end end
    tbl[who] = t
end
function BA.MarkAsked(who, t) mark(BA.DB().asked, who, t) end
-- 野外弹框弹过的人（不管点没点）：10 分钟内不再为他弹
function BA.SeenRecently(who, t)
    t = t or wall()
    local d = BA.DB()
    local last = type(d.seen) == "table" and d.seen[who]
    return (type(last) == "number" and last <= t and t - last < BA.ASK_CD) and true or false
end
function BA.MarkSeen(who, t)
    local d = BA.DB()
    d.seen = type(d.seen) == "table" and d.seen or {}
    mark(d.seen, who, t)
end

local function inAnyInstance()
    if not IsInInstance then return false end
    local r = { pcall(IsInInstance) }
    return (r[1] and clean(r[2])) and true or false
end
-- 在不在副本（party / raid）：返回 true/false, 副本名
local function inDungeon()
    if not IsInInstance then return false end
    local r = { pcall(IsInInstance) }
    if not (r[1] and clean(r[2])) then return false end
    local kind = clean(r[3])
    if not (kind == nil or kind == "party" or kind == "raid") then return false end
    return true, clean(call(GetInstanceInfo)) or "inst"
end
BA.InDungeon = inDungeon
local function groupUnits()
    local out = {}
    if clean(IsInRaid and call(IsInRaid)) then
        for i = 1, 40 do out[#out + 1] = "raid" .. i end
    else
        for i = 1, 4 do out[#out + 1] = "party" .. i end
    end
    return out
end
local function online(u)
    local on = UnitIsConnected and call(UnitIsConnected, u)
    return not (on ~= nil and clean(on) == false)
end

-- ================= ② 副本：看队伍配置，缺了自动要 =================
-- 队里能给我缺的那些 BUFF 的人：{ { cls, who, list = { t… } }, … }（每个职业挑第一个在线的；已经要过的类不算）
function BA.PartyPlan(missing)
    local plan, seen = {}, {}
    if not missing then return plan end
    local left = {}
    for k in pairs(missing) do if not BA.runAsked[k] then left[k] = true end end
    for _, u in ipairs(groupUnits()) do
        if exists(u) and not isMe(u) and online(u) then
            local cls = unitClass(u)
            if cls and BA.CLS_CN[cls] and not seen[cls] then
                local list = BA.CanGive(cls, unitLevel(u), left)
                local who = (#list > 0) and DC.FullName(u) or nil
                if who and who ~= "" then
                    seen[cls] = true
                    for _, t in ipairs(list) do left[t.k] = nil end
                    plan[#plan + 1] = { cls = cls, who = who, list = list }
                end
            end
        end
    end
    return plan
end
function BA.AutoCheck(reason)
    if not ns.db or not BA.AutoOn() then return false, "off" end
    local inInst, inst = inDungeon()
    if not inInst then return false, "notinst" end
    if not (IsInGroup and clean(call(IsInGroup))) then return false, "solo" end
    if bool(call(UnitIsDeadOrGhost, "player")) then return false, "dead" end
    if combat() then BA.pendingAuto = reason or true; if BA.SyncEvents then pcall(BA.SyncEvents) end; return false, "combat" end
    if BA.runInst ~= inst then BA.runInst, BA.runAsked = inst, {} end
    local t = now()
    if BA.lastAuto and BA.lastAuto <= t and t - BA.lastAuto < BA.COOLDOWN then
        BA.pendingAuto = reason or true
        if not BA.cdTimer and C_Timer and C_Timer.After then
            BA.cdTimer = true   -- 只挂一个；回调跑完再清（回调里再撞冷却不会再挂一个）
            C_Timer.After(BA.COOLDOWN - (t - BA.lastAuto) + 0.5, function()
                local r = BA.pendingAuto; BA.pendingAuto = nil
                if r then pcall(BA.AutoCheck, r) end
                BA.cdTimer = nil
            end)
        end
        return false, "cooldown"
    end
    local missing = BA.Missing()
    if not missing then return false, "noaura" end
    if not next(missing) then return false, "full" end
    local plan = BA.PartyPlan(missing)
    if #plan == 0 then return false, "nogiver" end
    local wall0, sentAny = wall(), false
    if BA.Opt("whisper") then
        for _, p in ipairs(plan) do
            local done = BA.RecentlyAsked(p.who, wall0)   -- 10 分钟内问过他的也算这次要过了（别刚在门口密完、进本又密一遍）
            if not done and BA.Send(BA.AskText(p.cls, p.list), "WHISPER", p.who) then
                BA.MarkAsked(p.who, wall0)
                sentAny, done = true, true
            end
            if done then for _, x in ipairs(p.list) do BA.runAsked[x.k] = true end end
        end
    else
        local chan = clean(IsInRaid and call(IsInRaid)) and "RAID" or "PARTY"
        if not BA.Send(BA.PartyText(plan), chan) then return false, "send" end
        sentAny = true
        for _, p in ipairs(plan) do
            BA.MarkAsked(p.who, wall0)
            for _, x in ipairs(p.list) do BA.runAsked[x.k] = true end
        end
    end
    if not sentAny then return false, "asked" end
    BA.lastAuto = t
    BA.pendingAuto = nil
    return true, plan
end
local function autoSoon(reason, delay)
    if not BA.AutoOn() then return end
    if C_Timer and C_Timer.After then C_Timer.After(delay or 2, function() pcall(BA.AutoCheck, reason) end) else pcall(BA.AutoCheck, reason) end
end

-- ================= ① 野外：探测附近，弹框问（点了才发）=================
function BA.FieldGate()
    if not ns.db or not BA.FieldOn() then return false, "off" end
    if BA.muted then return false, "muted" end
    if BA.frame and BA.frame:IsShown() then return false, "showing" end
    local d, t = BA.DB(), wall()
    if d.fieldLast and d.fieldLast <= t and t - d.fieldLast < BA.FIELD_GAP then return false, "gap" end
    if combat() then return false, "combat" end
    if inAnyInstance() then return false, "instance" end
    return true
end
function BA.FieldCheck(u)
    local ok, why = BA.FieldGate()
    if not ok then return false, why end
    if not u or not exists(u) then return false, "nounit" end
    if not bool(call(UnitIsPlayer, u)) or isMe(u) then return false, "notplayer" end
    local cls = unitClass(u)
    if not (cls and BA.CLS_CN[cls]) then return false, "notgiver" end
    if UnitIsFriend and not bool(call(UnitIsFriend, "player", u)) then return false, "enemy" end
    local mf, pf = clean(call(UnitFactionGroup, u)), clean(call(UnitFactionGroup, "player"))
    if mf and pf and mf ~= pf then return false, "faction" end
    if not online(u) then return false, "offline" end
    if bool(call(UnitIsDeadOrGhost, u)) then return false, "dead" end
    local who = DC.FullName(u)
    if not who or who == "" then return false, "noname" end
    if BA.RecentlyAsked(who) then return false, "asked" end
    if BA.SeenRecently(who) then return false, "seen" end
    local gt = now()
    local pk = BA.peek[who]
    if pk and pk <= gt and gt - pk < BA.PEEK then return false, "peek" end
    -- 11-15 用户看内存：主城姓名板一刷几百人，peek 只增不减 → 超过 200 人就清掉过期的
    BA.peekN = (BA.peekN or 0) + (pk and 0 or 1)
    if BA.peekN > 200 then
        local n = 0
        for k, v in pairs(BA.peek) do
            if type(v) ~= "number" or v > gt or gt - v >= BA.PEEK then BA.peek[k] = nil else n = n + 1 end
        end
        BA.peekN = n + 1
    end
    BA.peek[who] = gt
    local list = BA.CanGive(cls, unitLevel(u), BA.Missing())
    if #list == 0 then return false, "nothing" end
    BA.peek[who] = nil
    BA.ShowField({ who = who, cls = cls, lv = unitLevel(u), list = list })
    return true, who
end
function BA.FieldText(o)
    local lvTxt = o.lv and string.format(L("（%d 级）", " (Lv%d)"), o.lv) or ""
    return string.format(L("附近有%s %s%s，你没有%s，要不要密他要？", "%s %s%s is nearby and you're missing %s - whisper them?"),
        clsName(o.cls), short(o.who) or o.who, lvTxt, joinNames(o.list))
        .. "\n|cff999999" .. L("会密他：", "Will whisper: ") .. (BA.AskText(o.cls, o.list) or "") .. "|r"
end
-- 弹框里点「密他要」：点了才发
function BA.FieldSend()
    local o = BA.cur
    if not o then return false end
    if BA.RecentlyAsked(o.who) then BA.HideField(); return false end
    if not BA.CanChat() then
        ns.Print(L("现在发不了私聊（战斗中 / 聊天受限），过一会儿再点", "Can't whisper right now (combat / chat locked) - try again in a moment"))
        return false
    end
    if not BA.Send(BA.AskText(o.cls, o.list), "WHISPER", o.who) then return false end
    BA.MarkAsked(o.who, wall())
    ns.Print(L("已密 ", "Whispered ") .. (short(o.who) or o.who) .. L(" 要 ", " for ") .. joinNames(o.list))
    BA.HideField()
    return true
end
function BA.HideField()
    BA.cur = nil
    if BA.frame then BA.frame:Hide() end
end
function BA.Mute()
    BA.muted = true
    BA.HideField()
    ns.Print(L("这次登录不再提示附近能给 BUFF 的人（/reload 或重登恢复；彻底关：组队设置 →「要 BUFF」）", "Buff prompts muted for this session (back after /reload; turn off in Group settings > Buffs)"))
end
function BA.Build()
    if BA.frame then return BA.frame end
    local f = CreateFrame("Frame", "GearInsightForeverBuffAsk", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(330, 112)
    f:SetFrameStrata("DIALOG")
    if f.SetBackdrop then
        pcall(f.SetBackdrop, f, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.05, 0.06, 0.08, 0.95); f:SetBackdropBorderColor(1, 0.82, 0, 0.8)
    end
    local pos = BA.DB().pos
    if type(pos) == "table" and pos[1] then f:SetPoint(pos[1], UIParent, pos[1], pos[2] or 0, pos[3] or 0) else f:SetPoint("TOP", UIParent, "TOP", 0, -240) end
    f:SetMovable(true); f:EnableMouse(true)
    if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint()
        if p then BA.DB().pos = { p, x, y } end
    end)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("TOPLEFT", 10, -8)
    title:SetText(L("要 BUFF · 附近有人能给", "Buffs - someone nearby can buff you"))
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetSize(22, 22); close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() BA.HideField() end)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); f.text:SetPoint("TOPLEFT", 10, -28); f.text:SetWidth(310); f.text:SetJustifyH("LEFT")
    local function btn(label, w, x, onClick, tip)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        if ns.SkinButton then ns.SkinButton(b) end
        b:SetSize(w, 22); b:SetPoint("BOTTOMLEFT", x, 8); b:SetText(label)
        b.label = label
        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(self.label, 1, 0.82, 0)
            GameTooltip:AddLine(type(tip) == "function" and tip() or tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    f.ask = btn(L("密他要", "Whisper"), 96, 10, function() BA.FieldSend() end, function()
        local o = BA.cur
        return L("点了才发，私聊他这句：\n", "Sends this whisper (only when you click):\n") .. ((o and BA.AskText(o.cls, o.list)) or "")
    end)
    f.no = btn(L("不用", "No thanks"), 80, 112, function() BA.HideField() end, L("关掉这个框；这个人 10 分钟内不再提示", "Close; this player won't be suggested again for 10 min"))
    f.mute = btn(L("这次不再提示", "Not this session"), 120, 198, function() BA.Mute() end,
        L("这次登录不再弹；/reload 或重登恢复。彻底关：组队设置 →「要 BUFF」", "Muted until /reload; turn off for good in Group settings > Buffs"))
    f:SetScript("OnUpdate", function(self, el)
        self.age = (self.age or 0) + (el or 0)
        if self.age >= BA.FIELD_TTL then BA.HideField() end
    end)
    f:Hide()
    BA.frame = f
    return f
end
function BA.ShowField(o)
    local f = BA.Build()
    BA.cur = o
    if not o.sample then
        local d, t = BA.DB(), wall()
        d.fieldLast = t
        BA.MarkSeen(o.who, t)   -- 弹过就算问过：同一个人 10 分钟内只弹一次（不管点没点）
    end
    f.text:SetText(BA.FieldText(o))
    if f.text.GetStringHeight then
        local h = tonumber(f.text:GetStringHeight())
        if h then f:SetHeight(math.max(112, 72 + h)) end
    end
    f.age = 0
    f:Show()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
    if BA.SyncEvents then pcall(BA.SyncEvents) end
    return f
end
function BA.FieldRoster()
    if not BA.FieldGate() then return end
    for _, u in ipairs(groupUnits()) do
        if exists(u) and BA.FieldCheck(u) then return end
    end
end

-- ================= 事件（按开关只注册用得上的）=================
BA.EVENTS = {
    field = { "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "PLAYER_REGEN_DISABLED", "GROUP_ROSTER_UPDATE",
        "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" },
    auto = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED" },
}
BA.ALL_EVENTS = { "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "PLAYER_REGEN_DISABLED", "GROUP_ROSTER_UPDATE",
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED" }
function BA.WantedEvents()
    local want = {}
    if not ns.db then return want end
    local function add(list) for _, e in ipairs(list) do want[e] = true end end
    if BA.FieldOn() or (BA.frame and BA.frame:IsShown()) then add(BA.EVENTS.field) end
    if BA.AutoOn() then add(BA.EVENTS.auto) end
    return want
end
local ev = CreateFrame("Frame")
BA.ev = ev
function BA.SyncEvents()
    local want = BA.WantedEvents()
    for _, e in ipairs(BA.ALL_EVENTS) do
        if want[e] then pcall(ev.RegisterEvent, ev, e) else pcall(ev.UnregisterEvent, ev, e) end
    end
    BA.wanted = want
    return want
end
local function onUnit(u) if BA.FieldOn() then pcall(BA.FieldCheck, u) end end
ev:SetScript("OnEvent", function(_, e, a1)
    if e == "PLAYER_TARGET_CHANGED" then onUnit("target")
    elseif e == "UPDATE_MOUSEOVER_UNIT" then onUnit("mouseover")
    elseif e == "NAME_PLATE_UNIT_ADDED" then if type(a1) == "string" then onUnit(a1) end
    elseif e == "PLAYER_REGEN_DISABLED" then if BA.frame and BA.frame:IsShown() then BA.HideField() end
    elseif e == "PLAYER_ENTERING_WORLD" or e == "ZONE_CHANGED_NEW_AREA" then
        local inInst, inst = inDungeon()
        if not inInst then BA.runInst, BA.runAsked = nil, {}         -- 出了副本：下次进本重新要
        elseif BA.runInst ~= inst then BA.runInst, BA.runAsked = inst, {} end
        if inAnyInstance() and BA.frame and BA.frame:IsShown() then BA.HideField() end
        if inInst then autoSoon("enter", BA.ENTER_DELAY) end
    elseif e == "GROUP_ROSTER_UPDATE" then
        if inDungeon() then autoSoon("roster", 2) end
        if BA.FieldOn() then pcall(BA.FieldRoster) end
    elseif e == "PLAYER_REGEN_ENABLED" then
        if BA.pendingAuto then local r = BA.pendingAuto; BA.pendingAuto = nil; autoSoon(r, 2) end
    end
end)
BA._event = ev:GetScript("OnEvent")   -- 测试用

-- ---------- 设置页（组队抽屉齿轮「组队设置」+ 全部设置索引）----------
if ns.RegisterSettings then
    ns.RegisterSettings({ key = "buffask", order = 96, drawer = "group", avail = function() return ns.BuffAsk ~= nil end,
        title = function() return L("要 BUFF", "Ask for buffs") end, short = function() return L("要BUFF", "Buffs") end,
        items = {
            { type = "check", id = "buffask.on", text = function() return L("总开关：要 BUFF（耐力 / 智力 / 野性印记 / 圣骑士祝福）", "Master switch: ask for buffs (Fortitude / Intellect / Mark of the Wild / Blessings)") end,
              get = function() return BA.Opt("on") end, set = function(v) BA.SetOpt("on", v) end },
            { type = "check", id = "buffask.field", indent = 18, text = function() return L("野外 / 主城碰到能给我缺的 BUFF 的人时弹框问（点了才密，同一个人 10 分钟一次）", "Pop a prompt when someone nearby can give a buff you lack (only whispers if you click)") end,
              get = function() return BA.Opt("field") end, set = function(v) BA.SetOpt("field", v) end },
            { type = "check", id = "buffask.auto", indent = 18, text = function() return L("副本里看队伍配置，缺了自动要（进本 / 队伍变动时；每次进本每种只要一次，战斗中不发）", "In dungeons, ask automatically for missing buffs your group can give (once per run each, never in combat)") end,
              get = function() return BA.Opt("auto") end, set = function(v) BA.SetOpt("auto", v) end },
            { type = "check", id = "buffask.whisper", indent = 36, text = function() return L("副本里改成私聊那个人（默认发队伍频道）", "Whisper the player instead of party chat") end,
              get = function() return BA.Opt("whisper") end, set = function(v) BA.SetOpt("whisper", v) end },
            { type = "note", indent = 18, text = function() return L("战士 / 盗贼不要智力和智慧祝福；身上已有任何一种圣骑士祝福就不再要；自己职业能加的不要。发的话不带插件名，例如「牧师老板，求个耐力，谢谢~」",
                  "Warriors / Rogues skip Intellect and Wisdom; any Paladin blessing counts; your own class's buff is skipped. Messages carry no addon name.") end },
        } })
end

-- /gi buff · /gi 要buff：打开组队设置；/gi buff test = 弹一个示例框（不发任何话）
ns.ExtraSlash = ns.ExtraSlash or {}
local function slash(rest)
    if rest == "test" or rest == "测试" then
        BA.ShowField({ who = L("示例牧师", "Sample Priest"), cls = "PRIEST", lv = 40, list = { BA.BY_K.fort }, sample = true })
        BA.cur = nil   -- 示例框：点「密他要」不发（FieldSend 没有 cur 直接回）
        return
    end
    if ns.JumpToSetting and ns.JumpToSetting("buffask.on") then return end
    ns.Print(string.format(L("要 BUFF：总开关%s · 野外弹框%s · 副本自动要%s（%s）", "Buffs: %s / field %s / dungeon %s (%s)"),
        BA.Opt("on") and L("开", "on") or L("关", "off"), BA.Opt("field") and L("开", "on") or L("关", "off"),
        BA.Opt("auto") and L("开", "on") or L("关", "off"), BA.Opt("whisper") and L("私聊", "whisper") or L("队伍频道", "party chat")))
end
for _, c in ipairs({ "buff", "要buff", "要BUFF" }) do ns.ExtraSlash[c] = slash end

-- 加载时（组队信标登录加载）：存档好了就按开关注册事件；没好由 GroupParts.lua 的 ns.GroupSync（本插件 ADDON_LOADED 时调）补
--   ns.GroupSync 是插件自己的函数（不是暴雪全局），包一层：先跑原来的，再按开关重注册本文件的事件
local _groupSync = ns.GroupSync
if type(_groupSync) == "function" and not BA.wrapped then
    BA.wrapped = true
    ns.GroupSync = function(...)
        local r = { _groupSync(...) }
        if ns.db then pcall(BA.SyncEvents) end
        return unpack(r)
    end
end
if ns.db then pcall(BA.SyncEvents) end
