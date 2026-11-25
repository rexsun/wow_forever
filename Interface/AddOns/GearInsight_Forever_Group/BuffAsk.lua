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
--   BUFF：耐力（牧师）/ 智力（法师）/ 野性印记（德鲁伊）/ 圣骑士祝福（近战 + 猎人要力量、有蓝的要智慧，都要王者；每种祝福单独判断有没有）
--      11-19 用户「猎人的力量祝福也得要把」：猎人也要力量（BA.MELEE 加 HUNTER），猎人 = 力量 / 智慧 / 王者三种都要
--      11-18 用户截图「祝福分多钟」「祝福要齐全」：原来「身上有任何一种祝福 = 不缺」+ 王者只认不要 → 改成力量 / 智慧 / 王者逐种判断、逐种去要。
--      无限服实际有的只有这三种（拯救 / 光明 11-05 客户端删了，庇护天赋树里没有，见 PallyBless.lua 文件头）。
--      经典规则：一个圣骑士只能给你挂一种祝福（他再加别的会顶掉自己那一种）→ 一次只找一个圣骑士要一种；已经给我加了祝福的圣骑士不找他要另一种；
--      几种都缺时先要还没向别的圣骑士要过的那种（BA.blessAsk）；副本里队里几个圣骑士各要一种
--      对我有用：战士 / 盗贼不要智力和智慧祝福；自己职业能给的不要（自己加）
--      法术 ID：开服客户端技能书 services/dashboard/static/data/forever/spellbook.json（1.60.1.70862，wago.tools DB2）逐级列全，
--      单体王者祝福 20217 = PallyBless.lua（训练师 20 级学，无限技能书里没有这条单列）。读光环按 spellId，读不到 ID 再按客户端法术名
--   ⛔ 发的话不带插件名（11-13 网易DD：自动发言别带插件名）→ 不走 DC.Tagged，直接发正文；战斗中 / 聊天锁定不发；秘密值（issecretvalue）一律当读不到
--   开关（ns.db.buffAsk；nil = 默认）：总开关 on（开）· 野外弹框 field（开）· 副本里缺 BUFF dmode（off 不管 / ask 弹框问我 / auto 自动要；默认 ask）· 自动要时改私聊 whisper（关 = 发队伍频道）
--   ⛔ 11-16 用户「这个进本就自动喊要BUFF的咋关」→「设计下」→「开工」：副本默认从「自动发」改成「弹框问我」（自动发言默认关，见网易DD 11-13）：
--      缺了且队里有人能给 → 弹小框「队里有牧师 XX 能给耐力，你身上没有」[队伍里要] [密他要] [以后别问]；点了才发；每次进本每种只问一次；进战斗收起；30 秒自己收起
--      老存档 auto = false（关过）→ off；其余（从没动过 = 原来默认自动）→ ask，第一次进世界聊天框说一次怎么改回自动（d.dmodeNote）
--      选「自动要」的：每次自动发完聊天框自己可见一行「刚在队伍里要了…（/gi buff 可改成弹框或关闭）」
--      /gi buff 开 | 关（总开关）· /gi buff 自动 | 弹框 | 不管（副本里缺 BUFF 怎么办）
--   设置：本文件登记 ns.RegisterSettings（组队抽屉齿轮「组队设置」+ 全部设置索引，key = buffask）；命令 /gi buff（/gi 要buff）
--   11-20 GI-319 玩家（战士）「找骑士要BUFF 可以提供选择要王者还是力量」：圣骑士祝福偏好 + 弹框里直接选
--      存档 ns.db.buffAsk.blessPref：nil = 自动（原顺序 力量 / 智慧 / 王者）· kings / might / wis = 几种都缺时先要这一种（职业用不上的偏好当自动）
--      存档 ns.db.buffAsk.blessNo：{ might = true, … } = 这种祝福不要（不弹、不自动要、右键菜单 / 清单都不算缺）；nil = 都要 —— 老存档行为不变
--      CanGive 按偏好顺序挑（多个圣骑士仍各要一种，偏好那种先给第一个）；BA.BlessChoices = 这个圣骑士能给我的全部祝福（偏好在前）
--      野外 / 副本弹框里同一个圣骑士能给不止一种 → 框里多一行 [要王者] [要力量] …（默认那种高亮），点哪个就密他要哪个；⛔ 点了才发，走 CL、不带插件名
--      命令：/gi buff 王者 | 力量 | 智慧 · /gi buff 祝福 自动（「/gi buff 自动」原来就是副本自动要，不改）· /gi buff 不要力量 | 要力量
local _, ns = ...; ns = _G.GearInsightForever or ns
local L = function(cn, en) return ns.L(cn, en) end
local CL = function(cn, en) return ns.ChatL(cn, en) end   -- 11-19 发出去的要 BUFF 话走对外说话语言
local DC = ns.DungeonChat
if not DC then return end

local BA = { runAsked = {}, peek = {} }
ns.BuffAsk = BA
BA.ASK_CD = 600        -- 同一个人 10 分钟内只问一次（野外弹框 + 副本自动要合起来）
BA.FIELD_GAP = 120     -- 任意两次野外弹框
-- 11-23 用户「M语要BUFF的，除了我本地，改回每30S只能M一个」：野外弹框「密他要」30 秒一个（框照旧换成下一个，30 秒内点了不发、说还要等几秒）；
--   ns.DEV_LOCAL = 用户本机才有的 DevLocal.lua（_hold.txt，⛔ 永不进包）→ 不限。⛔ 内核没余量：不另开定时器
BA.WHISPER_GAP = 30
BA.FIELD_TTL = 60      -- 弹框自己收起
BA.PEEK = 30           -- 看过但不弹的人（不缺 / 等级不够），这么久内不再算
BA.COOLDOWN = 20       -- 副本里任意两次自动发
BA.ENTER_DELAY = 5     -- 进副本后等几秒（过完读条、队友单位就绪、BUFF 读得到）

-- ---------- 数据（来源见文件头）----------
--   k = 键；cls = 谁能给；lv = 最低几级能给（第一级的学习等级）；ids = 这一类的所有法术（各等级 + 团队版 / 强效版：任何一个在身上都算有）
--   fam = 同一家（圣骑士祝福 bless：一个圣骑士只能给你挂一种 → 找同一个圣骑士一次只要一种；11-18 起有没有按种类各算各的）
--   ranks = 各等级的学习等级（经典训练师表）：判断对方等级太低、只放得出低几级的 buff（11-17 用户「为啥碰到等级差很多的还要buff呢」）
BA.TYPES = {
    { k = "fort", ranks = { 1, 12, 24, 36, 48, 60 }, cls = "PRIEST", lv = 1, cn = "耐力", en = "Fortitude",
      ids = { 1243, 1244, 1245, 2791, 10937, 10938,   -- 真言术：韧 1-6 级
              21562, 21564 } },                       -- 坚韧祷言 1-2 级
    { k = "int", ranks = { 1, 14, 28, 42, 56 }, cls = "MAGE", lv = 1, cn = "智力", en = "Intellect", mana = true,
      ids = { 1459, 1460, 1461, 10156, 10157,         -- 奥术智慧 1-5 级
              23028 } },                              -- 奥术光辉
    { k = "motw", ranks = { 1, 10, 20, 30, 40, 50, 60 }, cls = "DRUID", lv = 1, cn = "野性印记", en = "Mark of the Wild",
      ids = { 1126, 5232, 6756, 5234, 8907, 9884, 9885,   -- 野性印记 1-7 级
              21849, 21850 } },                           -- 野性赐福 1-2 级
    { k = "might", ranks = { 4, 12, 22, 32, 42, 52, 60 }, cls = "PALADIN", lv = 4, fam = "bless", melee = true, cn = "力量祝福", en = "Blessing of Might",
      ids = { 19740, 19834, 19835, 19836, 19837, 19838, 25291,   -- 力量祝福 1-7 级
              25782, 25916 } },                                  -- 强效力量祝福 1-2 级
    { k = "wis", ranks = { 14, 24, 34, 44, 54, 60 }, cls = "PALADIN", lv = 14, fam = "bless", mana = true, cn = "智慧祝福", en = "Blessing of Wisdom",
      ids = { 19742, 19850, 19852, 19853, 19854, 25290,          -- 智慧祝福 1-6 级
              25894, 25918 } },                                  -- 强效智慧祝福 1-2 级
    { k = "kings", ranks = { 20 }, cls = "PALADIN", lv = 20, fam = "bless", cn = "王者祝福", en = "Blessing of Kings",
      ids = { 20217, 25898 } },                                  -- 王者祝福 / 强效王者祝福（11-18 起也要：「祝福要齐全」）
}
BA.BY_K = {}
for _, t in ipairs(BA.TYPES) do BA.BY_K[t.k] = t end
BA.CLS_CN = { PRIEST = { "牧师", "Priest" }, MAGE = { "法师", "Mage" }, DRUID = { "德鲁伊", "Druid" }, PALADIN = { "圣骑士", "Paladin" } }
-- 没蓝的职业（智力 / 智慧祝福没用）；要力量祝福的职业（近战 + 猎人，11-19）
BA.NO_MANA = { WARRIOR = true, ROGUE = true, DEATHKNIGHT = true }
BA.MELEE = { WARRIOR = true, ROGUE = true, DEATHKNIGHT = true, HUNTER = true }

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
local function buffName(t, chat) if chat then return ns.ChatName(t.cn, t.en) end return L(t.cn, t.en) end

-- ---------- 设置（ns.db.buffAsk；nil = 默认值）----------
BA.DEFAULTS = { on = true, field = true, auto = true, whisper = false }
BA.DUNGEON_TTL = 30    -- 副本弹框自己收起
BA.DMODES = { off = true, ask = true, auto = true }
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
-- 副本里缺 BUFF 怎么办：off / ask / auto（存档没写 = 老存档 auto 关过 → off，否则 ask）
function BA.DModeRaw()
    if not ns.db then return "ask" end
    local d = BA.DB()
    if BA.DMODES[d.dmode] then return d.dmode end
    if d.auto == false then return "off" end
    return "ask"
end
function BA.DMode()
    if not BA.Opt("on") then return "off" end
    return BA.DModeRaw()
end
function BA.SetDMode(m)
    if not BA.DMODES[m] then return end
    BA.DB().dmode = m
    if m == "off" and BA.cur and BA.cur.dungeon then BA.HideField() end
    if BA.SyncEvents then pcall(BA.SyncEvents) end
end
BA.DMODE_TXT = { off = { "不管", "do nothing" }, ask = { "弹框问我", "ask me" }, auto = { "自动要", "ask automatically" } }
function BA.DModeText(m) local t = BA.DMODE_TXT[m or BA.DMode()]; return t and L(t[1], t[2]) or tostring(m) end
-- 副本这一路要不要跑（弹框问 / 自动要都算）
function BA.AutoOn() return BA.DMode() ~= "off" end
-- 老用户第一次进世界：副本自动要改成了弹框问，说一次怎么改回来
function BA.MigrateNote()
    if not ns.db then return false end
    local d = BA.DB()
    if d.dmodeNote or d.dmode ~= nil or d.auto == false or not BA.Opt("on") then d.dmodeNote = true; return false end
    d.dmodeNote = true
    ns.Print(L("要 BUFF：副本里缺 BUFF 改成先弹框问你，点了才发；想恢复自动要：/gi buff 自动（不想管：/gi buff 不管）",
        "Buffs: in dungeons you now get a prompt instead of an automatic party message; /gi buff auto to restore, /gi buff none to turn off"))
    return true
end

-- ---------- 对我有用的 BUFF ----------
-- 这一类对 cls 职业有没有用（不看玩家勾的「不要」）
local function fitCls(t, cls)
    if t.noAsk then return false end
    if cls and t.cls == cls then return false end
    if t.mana and cls and BA.NO_MANA[cls] then return false end
    if t.melee and not (cls and BA.MELEE[cls]) then return false end
    return true
end
-- 这一类对 cls 职业有没有用（noAsk 的王者不主动要；自己职业给得了的不要；11-20 玩家勾了「不要」的祝福不要）
function BA.Useful(t, cls)
    if not fitCls(t, cls) then return false end
    if t.fam == "bless" and BA.BlessNo(t.k) then return false end
    return true
end

-- ---------- 11-20 GI-319 圣骑士祝福偏好（见文件头）----------
--   ⛔ 组队信标登录就加载（内存预算闸 gi_forever_mem_budget_test）：这一段和下面选择行都写得很省
BA.BLESS_SHORT = { might = { "力量", "Might" }, wis = { "智慧", "Wisdom" }, kings = { "王者", "Kings" } }
BA.BLESS_KEYS = { "kings", "might", "wis" }
local function bdb() return ns.db and BA.DB() or {} end
function BA.BlessNo(k) local n = bdb().blessNo; return type(n) == "table" and n[k] == true end
function BA.BlessPrefRaw() local p = bdb().blessPref; return BA.BLESS_SHORT[p or ""] and p or "auto" end
-- 实际生效的偏好：职业用不上 / 勾了不要 = 自动（nil）
function BA.BlessPref(cls)
    local p = BA.BlessPrefRaw()
    if p ~= "auto" and fitCls(BA.BY_K[p], cls or myClass()) and not BA.BlessNo(p) then return p end
end
local function setNo(d, k, v)
    local n = type(d.blessNo) == "table" and d.blessNo or {}
    n[k] = v and true or nil
    d.blessNo = next(n) and n or nil   -- 全不勾 = nil（存档不留痕）
end
-- k = kings / might / wis；别的（auto / nil）= 自动。选了先要它 = 不再「不要」它
function BA.SetBlessPref(k)
    local d = BA.DB()
    k = BA.BLESS_SHORT[k or ""] and k or nil
    d.blessPref = k
    if k then setNo(d, k, false) end
end
-- 勾「不要」：偏好正好是它 → 偏好回自动
function BA.SetBlessNo(k, v)
    if not BA.BLESS_SHORT[k or ""] then return end
    local d = BA.DB()
    setNo(d, k, v)
    if v and d.blessPref == k then d.blessPref = nil end
end
function BA.BlessShort(k) local s = BA.BLESS_SHORT[k]; return s and L(s[1], s[2]) or tostring(k) end
-- 圣骑士祝福按偏好排：偏好那种在前，其余照 TYPES 顺序
function BA.BlessOrder(cls)
    local p, out = BA.BlessPref(cls), {}
    if p then out[1] = BA.BY_K[p] end
    for _, t in ipairs(BA.TYPES) do if t.fam == "bless" and t.k ~= p then out[#out + 1] = t end end
    return out
end
-- 「先要王者 · 不要力量」（诊断 / 命令回显）
function BA.BlessNoText()
    local p, s = BA.BlessPrefRaw(), {}
    s[1] = p == "auto" and L("自动", "auto") or L("先要", "prefer ") .. BA.BlessShort(p)
    for _, k in ipairs(BA.BLESS_KEYS) do if BA.BlessNo(k) then s[#s + 1] = L("不要", "skip ") .. BA.BlessShort(k) end end
    return table.concat(s, " · ")
end

-- ---------- 读我身上的 BUFF ----------
--   返回 { [spellId] = true }, { [名字] = true }；读不到（秘密值 / 接口不在）返回 nil —— 读不到就当「不知道」，不要
local function auraAt(i)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local a = call(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if a == nil then return nil end
        if type(a) ~= "table" then return false end
        return true, a.name, a.spellId, a.duration, a.expirationTime, a.sourceUnit
    end
    if UnitBuff then
        local r = { pcall(UnitBuff, "player", i) }
        if not r[1] or r[2] == nil then return nil end
        return true, r[2], r[11], r[6], r[7], r[8]
    end
    return nil
end
-- 11-18 用户截图「时间低于3分之一就可以要了」：剩下不到总时长三分之一的 BUFF 当作没有（快到期了，碰到能给的人就问）；
--   读不到时长 / 永久 / 秘密值 = 按有算
BA.LOW_FRAC = 1 / 3
local function nearlyGone(dur, exp)
    dur, exp = tonumber(clean(dur)), tonumber(clean(exp))
    if not (dur and exp and dur > 0 and exp > 0) then return false end
    local t = GetTime and GetTime() or 0
    return (exp - t) < dur * BA.LOW_FRAC
end
function BA.MyAuras()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) and not UnitBuff then return nil end
    local ids, names = {}, {}
    for i = 1, 40 do
        local okA, name, id, dur, exp = auraAt(i)
        if okA == nil then break end
        if okA == false then return nil end
        if (name ~= nil and clean(name) == nil) or (id ~= nil and clean(id) == nil) then return nil end   -- 秘密值：整张表不可信
        if not nearlyGone(dur, exp) then   -- 快到期的不记（= 缺，见 BA.LOW_FRAC）
            id = tonumber(id)
            if id then ids[id] = true end
            if type(name) == "string" and name ~= "" then names[name] = true end
        end
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
--   11-18「祝福要齐全」：圣骑士祝福也按种类各算各的（原来身上有任何一种祝福 = 整家都不缺）
function BA.Missing()
    local ids, names = BA.MyAuras()
    if not ids then return nil end
    local cls = myClass()
    local out = {}
    for _, t in ipairs(BA.TYPES) do
        if BA.Useful(t, cls) and not hasType(t, ids, names) then out[t.k] = true end
    end
    return out
end
-- 身上的圣骑士祝福是谁加的：{ [全名] = k }（施法者读不到 / 秘密值 / 是我自己 = 不记；快到期的也记 —— 他还占着「给我挂一种」的名额）
--   用处：已经给我加了力量的圣骑士，不找他要王者（他一加就把力量顶掉了）；同一种快到期了照样找他续
function BA.BlessFrom()
    local out = {}
    if not (DC.FullName and (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex or UnitBuff)) then return out end
    for i = 1, 40 do
        local okA, name, id, _, _, src = auraAt(i)
        if okA == nil then break end
        if okA == true then
            name, id, src = clean(name), tonumber(clean(id)), clean(src)
            if type(src) == "string" and src ~= "" and not isMe(src) then
                for _, t in ipairs(BA.TYPES) do
                    if t.fam == "bless" and hasType(t, id and { [id] = true } or {}, type(name) == "string" and { [name] = true } or {}) then
                        local who = clean(DC.FullName(src))
                        if type(who) == "string" and who ~= "" then out[who] = t.k end
                        break
                    end
                end
            end
        end
    end
    return out
end
-- 几种祝福都缺时，向别的圣骑士要过的那种（10 分钟内）先让给他：{ [k] = { who, t } }（本次登录）
BA.blessAsk = {}
function BA.NoteBless(who, list, t)
    t = t or wall()
    for _, x in ipairs(list or {}) do if x.fam == "bless" then BA.blessAsk[x.k] = { who = who, t = t } end end
end
function BA.BlessTaken(k, who, t)
    t = t or wall()
    local b = BA.blessAsk[k]
    return (b and b.who ~= who and b.t <= t and t - b.t < BA.ASK_CD) and true or false
end
-- 11-18 用户「或者不判断时间，直接可以要（不判断是否有这个buff」：右键菜单「找他要BUFF」用这份 —— 对我有用的全部（不看身上有没有）
function BA.Wantable()
    local cls, out = myClass(), {}
    for _, t in ipairs(BA.TYPES) do if BA.Useful(t, cls) then out[t.k] = true end end
    return out
end
-- giverCls 职业、giverLv 级的人能给我的、我缺的：{ t, … }（按 TYPES 顺序）
-- 11-17 用户「为啥碰到等级差很多的还要buff呢」（同一天「40 级碰到 26 级的就不应该问水」）：
--   对方比我低 LV_DIFF 级以上、而且他能放的最高一级比「跟我同级的这个职业」能放的低 → 太低，不问（野外弹框 / 组队自动要 / 补给清单同一口径）。
--   例：我 40 级，26 级法师只有 2 级奥术智慧（28 级才有 3 级）→ 不问；36 级牧师和 40 级牧师都是 4 级真言术：韧 → 照问。不知道他等级（骷髅 = 比我高 10 级以上）= 不挡
BA.LV_DIFF = 5
local function rankAt(t, lv)
    local n = 0
    for i, need in ipairs(t.ranks or {}) do if lv >= need then n = i end end
    return n
end
function BA.GiverTooLow(t, giverLv, myLv)
    giverLv, myLv = tonumber(giverLv), tonumber(myLv)
    if not (t and t.ranks and giverLv and giverLv > 0 and myLv) then return false end
    if giverLv >= myLv - BA.LV_DIFF then return false end
    return rankAt(t, giverLv) < rankAt(t, myLv)
end
-- who = 对方全名（可不传）：圣骑士一次只要一种祝福（11-18）—— 已经给我加了别的祝福的不找他要；几种都缺先要没向别人要过的那种
-- from（可选）：调用方已经读好的 BA.BlessFrom()（11-19 主城卡顿闸：Givers / 出发前清单一轮只读一次身上的祝福，别每个圣骑士读一遍）
local function giveOK(t, giverCls, giverLv, missing, myLv)
    return t.cls == giverCls and missing[t.k] and (not giverLv or giverLv >= t.lv) and not BA.GiverTooLow(t, giverLv, myLv)
end
-- 11-20 这个圣骑士能给我的祝福（按偏好排；向别的圣骑士要过的那种挪到最后）：{ t, … }；第一个 = CanGive 挑的那种
function BA.BlessChoices(giverCls, giverLv, missing, who, from, myLv)
    local out, taken = {}, {}
    if giverCls ~= "PALADIN" or not missing then return out end
    myLv = myLv or unitLevel("player")
    for _, t in ipairs(BA.BlessOrder()) do
        if giveOK(t, giverCls, giverLv, missing, myLv) then
            if from == nil then from = (who and BA.BlessFrom()) or false end
            local his = from and from[who]
            if not (his and his ~= t.k) then   -- 他给我挂的是别的祝福 → 这种不找他（一加就顶掉）；同一种 = 找他续
                if BA.BlessTaken(t.k, who) then taken[#taken + 1] = t else out[#out + 1] = t end
            end
        end
    end
    for _, t in ipairs(taken) do out[#out + 1] = t end
    return out
end
function BA.CanGive(giverCls, giverLv, missing, who, from)
    local out = {}
    if not missing then return out end
    local myLv = unitLevel("player")
    for _, t in ipairs(BA.TYPES) do
        if t.fam ~= "bless" and giveOK(t, giverCls, giverLv, missing, myLv) then out[#out + 1] = t end
    end
    local bless = BA.BlessChoices(giverCls, giverLv, missing, who, from, myLv)[1]   -- 一个圣骑士一次只要一种：偏好那种先
    if bless then out[#out + 1] = bless end
    return out
end
-- 弹框用：能给的祝福不止一种才返回列表（给 [要王者] [要力量] 按钮），否则 nil
function BA.ChoiceList(c, lv, miss, who) local ch = BA.BlessChoices(c, lv, miss, who); return ch[2] and ch or nil end

-- ---------- 话术（⛔ 不带插件名；简短礼貌）----------
local function joinNames(list, chat)   -- chat = 发出去的话（按对外说话语言）
    local n = {}
    for _, t in ipairs(list) do n[#n + 1] = buffName(t, chat) end
    return table.concat(n, (chat and CL or L)("和", " and "))
end
-- 对一个职业要：「义父，求个耐力，谢谢~」——11-17 起称呼 × 请求 × 结尾随机组合（DC.AskPhrase：「好心的牧师，能给个耐力吗？多谢！」…），
--   who = 发给谁（预览和实发同一句；对同一个人优先换说法）；设置里「固定一种说法」= 老说法
function BA.AskText(giverCls, list, who)
    if not list or #list == 0 then return nil end
    return DC.AskPhrase(who or giverCls, clsName(giverCls), "buff", joinNames(list, true))
end
-- 队伍频道一句话要几样：一个职业 = 同上；几个职业 = 「各位老板，求个耐力、智力，谢谢~」（同样随机组合）
function BA.PartyText(plan)
    if #plan == 0 then return nil end
    if #plan == 1 then return BA.AskText(plan[1].cls, plan[1].list, "PARTY") end
    local n = {}
    for _, p in ipairs(plan) do for _, t in ipairs(p.list) do n[#n + 1] = buffName(t, true) end end
    return DC.AskPhrase("PARTY", nil, "buff", table.concat(n, CL("、", ", ")))
end

-- ---------- 发话 ----------
function BA.CanChat()
    if combat() then return false end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and call(C_ChatInfo.InChatMessagingLockdown) then return false end
    return true
end
-- 11-20 用户截图（密德鲁伊要野性印记）「要BUFF也加坐标」：私聊句尾带「我在<地区> x,y [地图标记]」，对方不用回问在哪
--   读不到位置（副本里 / 秘密值）= 不加；加上超 255 字节先丢地图标记、还超就不加（别把超链接截一半）
-- 11-23 用户截图「坐标别加了」「地图标记位置可以加」：只带 [地图标记位置] 链接，不写「我在<地区> x,y」
function BA.Here()
    local PS = ns.PvPShout
    if not (PS and PS.Pos and PS.PinLink) then return nil end
    local ok, m, x, y = pcall(PS.Pos)
    if not ok or not m then return nil end
    local ok2, link = pcall(PS.PinLink, m, x, y)
    return ok2 and type(link) == "string" and link ~= "" and link or nil
end
-- 11-24 用户截图「地图标记搞个开关」：rec.askPin = false 关（nil = 默认带）
function BA.PinOn() return not (ns.db and DC.DB().rec.askPin == false) end
function BA.WithHere(text)
    local w = BA.PinOn() and BA.Here()
    local s = w and (text .. " " .. w)
    return s and #s <= DC.MAX_BYTES and s or text
end
-- 11-23 用户「收到BUFF还是有的时候不弹感谢窗」：回谢框（_Xp 的 XpSupply.lua）原来只认出发前清单的「喊」，
--   这里密人要 / 队伍里要都没算 → 发出去以后也挂上回谢（XC.ThankArmAsk；_Xp 没加载就加载上）
function BA.ArmThank(who, list)
    local XC = ns.XpCheck
    if not (ns.db and XC and XC.DB) or XC.DB().thank == false then return end
    if not XC.ThankArmAsk and ns.XpLoad then pcall(ns.XpLoad) end
    if XC.ThankArmAsk then pcall(XC.ThankArmAsk, who, list) end
end
function BA.Send(text, chan, to)
    if not text or not BA.CanChat() then return false end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    local ok, err = pcall(send, DC.CutBytes(chan == "WHISPER" and BA.WithHere(text) or text, DC.MAX_BYTES), chan, nil, to)
    BA.lastSendErr = (not ok) and tostring(err) or nil   -- 11-18 右键「找他要BUFF」没反应：报错原文留给调用方打印
    if ok and DC.AskSent then DC.AskSent(text, to) end   -- 11-17 话术变体：发出去了才换下一句
    return ok
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
-- 11-20 用户「进组以后立刻弹要水要BUFF，但是隔着很远，这个没必要」：能给的那个人在附近才弹 / 才发（野外弹框 · 副本弹框 / 自动要；法师吃喝 MageWater 借这一个）
--   true = 附近；false = 远 / 离线 / 看不见 / 读不到。依次：UnitIsVisible 假 = 远 → UnitInRange（约 40 码）→ UnitDistanceSquared → CheckInteractDistance 4（28 码，战斗外）
--   → 同一张地图坐标换算成码（不同地图 = 远）→ 都读不到（秘密值）：UnitIsVisible 真才算；它也读不到 = 副本里算近（地图已核对过）、野外不算；客户端没有 UnitIsVisible = 不挡（老行为）
BA.NEAR = 40
local function wpos(m, u)
    local _, w = call(C_Map.GetWorldPosFromMapPos, m, clean(call(C_Map.GetPlayerMapPosition, m, u)))
    w = clean(w)
    if w and w.GetXY then local x, y = w:GetXY(); return tonumber(clean(x)), tonumber(clean(y)) end
end
function BA.Near(u)
    if not exists(u) or not online(u) then return false end
    local vis = UnitIsVisible and clean(call(UnitIsVisible, u))
    if vis == false then return false end
    local r, c = call(UnitInRange, u)
    r, c = clean(r), clean(c)
    if c and r ~= nil then return r and true or false end
    local d, c2 = call(UnitDistanceSquared, u)
    d = tonumber(clean(d))
    if clean(c2) and d then return d <= BA.NEAR * BA.NEAR end
    if not (InCombatLockdown and InCombatLockdown()) and clean(call(CheckInteractDistance, u, 4)) then return true end
    local M = C_Map or {}
    local m = clean(call(M.GetBestMapForUnit, "player"))
    local um = m and clean(call(M.GetBestMapForUnit, u))
    if um and um ~= m then return false end
    if um and M.GetWorldPosFromMapPos then
        local x1, y1 = wpos(m, "player")
        local x2, y2 = wpos(m, u)
        if x1 and x2 then return (x1 - x2) ^ 2 + (y1 - y2) ^ 2 <= BA.NEAR * BA.NEAR end
    end
    if vis ~= nil then return vis and true or false end
    return UnitIsVisible == nil or inAnyInstance()
end
-- 远的先挂着：每 WAIT 秒复查一次（野外 FieldRoster / 副本 AutoCheck），靠近了照原规则弹 / 发；挂满 WAIT_MAX 秒或离队就放弃
BA.WAIT, BA.WAIT_MAX = 5, 600
function BA.Wait(k)
    local w, t = BA.wait, now()
    if not w or t - w.t0 > BA.WAIT_MAX then w = { t0 = t }; BA.wait = w end
    w[k] = true
    if not w.armed and C_Timer and C_Timer.After then w.armed = true; C_Timer.After(BA.WAIT, BA.WaitTick) end
end
function BA.WaitTick()
    local w = BA.wait
    if not w then return end
    local f, d = w.f, w.d
    w.armed, w.f, w.d = nil, nil, nil
    if not (IsInGroup and clean(call(IsInGroup))) or now() - w.t0 > BA.WAIT_MAX then BA.wait = nil; return end
    if f then
        local ok, why = BA.FieldGate()
        if ok then pcall(BA.FieldRoster) elseif why == "showing" or why == "gap" or why == "combat" then w.f = true end
    end
    if d then pcall(BA.AutoCheck, "near") end
    if w.f or w.d then BA.Wait(w.f and "f" or "d") elseif BA.wait == w then BA.wait = nil end
end

-- ================= ② 副本：看队伍配置，缺了自动要 =================
-- 队里能给我缺的那些 BUFF 的人：{ { cls, who, list = { t… } }, … }（每个职业挑第一个在线的；圣骑士每人一种祝福、几个圣骑士各要各的；已经要过的类不算）
function BA.PartyPlan(missing)
    local plan, seen = {}, {}
    if not missing then return plan end
    local left = {}
    for k in pairs(missing) do if not BA.runAsked[k] then left[k] = true end end
    for _, u in ipairs(groupUnits()) do
        if exists(u) and not isMe(u) and online(u) then
            local cls = unitClass(u)
            if cls and BA.CLS_CN[cls] and not seen[cls] then
                local full, lv = DC.FullName(u), unitLevel(u)
                local list = BA.CanGive(cls, lv, left, full)
                local who = (#list > 0) and full or nil
                if who and not BA.Near(u) then plan.far, who = true, nil end   -- 11-20 能给但离得远：先不算（同职业的下一个近的顶上），AutoCheck 挂起等他走近
                if who and who ~= "" then
                    if cls ~= "PALADIN" then seen[cls] = true end   -- 11-18 圣骑士一人只给一种祝福：队里几个圣骑士各要一种
                    local ch = BA.ChoiceList(cls, lv, left, full)   -- 11-20 弹框里给他选（拿走之前算：能给的全部）
                    for _, t in ipairs(list) do left[t.k] = nil end
                    plan[#plan + 1] = { cls = cls, who = who, list = list, choices = ch }
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
    if plan.far then BA.Wait("d") end
    if #plan == 0 then return false, plan.far and "far" or "nogiver" end
    -- 11-16 默认「弹框问我」：只弹框，点了才发；弹过的这几样这次进本不再问（不管点没点）
    if BA.DMode() == "ask" then
        if BA.frame and BA.frame:IsShown() and BA.cur and not BA.cur.dungeon then BA.HideField() end
        if BA.frame and BA.frame:IsShown() then BA.pendingAuto = reason or true; return false, "showing" end
        for _, p in ipairs(plan) do for _, x in ipairs(p.list) do BA.runAsked[x.k] = true end end
        BA.ShowDungeon(plan)
        BA.lastAuto = t
        BA.pendingAuto = nil
        return true, plan
    end
    local wall0, sentAny = wall(), false
    if BA.Opt("whisper") then
        for _, p in ipairs(plan) do
            local done = BA.RecentlyAsked(p.who, wall0)   -- 10 分钟内问过他的也算这次要过了（别刚在门口密完、进本又密一遍）
            if not done and BA.Send(BA.AskText(p.cls, p.list, p.who), "WHISPER", p.who) then
                BA.MarkAsked(p.who, wall0); BA.NoteBless(p.who, p.list, wall0); BA.ArmThank(p.who, p.list)
                sentAny, done = true, true
            end
            if done then for _, x in ipairs(p.list) do BA.runAsked[x.k] = true end end
        end
    else
        local chan = clean(IsInRaid and call(IsInRaid)) and "RAID" or "PARTY"
        if not BA.Send(BA.PartyText(plan), chan) then return false, "send" end
        sentAny = true
        for _, p in ipairs(plan) do BA.ArmThank(p.who, p.list) end
        for _, p in ipairs(plan) do
            BA.MarkAsked(p.who, wall0); BA.NoteBless(p.who, p.list, wall0)
            for _, x in ipairs(p.list) do BA.runAsked[x.k] = true end
        end
    end
    if not sentAny then return false, "asked" end
    BA.lastAuto = t
    BA.pendingAuto = nil
    -- 自动发的：聊天框自己可见一行，知道是插件发的、怎么改
    local got = {}
    for _, p in ipairs(plan) do for _, x in ipairs(p.list) do got[#got + 1] = buffName(x) end end
    local where = BA.Opt("whisper") and L("在私聊里", "by whisper") or L("在队伍里", "in party chat")
    ns.Print(string.format(L("刚%s要了%s（/gi buff 弹框 = 先问你再发；/gi buff 不管 = 关掉）", "Just asked %s for %s (/gi buff ask = prompt first; /gi buff none = off)"),
        where, table.concat(got, L("、", ", "))))
    return true, plan
end
-- 11-15 用户截图「BUFF不全为撒谎不提醒」：记下最近一次副本自动要的结果，/gi buff 诊断 时说清楚为什么没要
do
    local raw = BA.AutoCheck
    BA.AutoCheck = function(reason)
        local ok, why = raw(reason)
        BA.lastAuto2 = { ok = ok, why = ok and "sent" or why, t = now(), reason = reason }
        return ok, why
    end
end
-- 11-21 /gi buff 诊断（BA.WHY / BA.WhyText / BA.Diag）搬进按需加载的 _GroupMage 的 BuffAskDiag.lua（给灵魂石提醒的登录触发腾内存）；
--   这里只把它要用的几个小工具挂出去，命令里先 ns.LoadModule("mage") 再调
BA.ClsName, BA.JoinNames, BA.BuffName = clsName, joinNames, buffName

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
    -- 11-17 用户截图「飞机上不弹」：坐飞行点（UnitOnTaxi）跟战斗中一样不弹
    if combat() or bool(call(UnitOnTaxi, "player")) then return false, "combat" end
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
    local miss, lv = BA.Missing(), unitLevel(u)
    local list = BA.CanGive(cls, lv, miss, who)
    if #list == 0 then return false, "nothing" end
    BA.peek[who] = nil
    if not BA.Near(u) then   -- 11-20 离得远（典型：刚进组队友在别处）不弹；是队友就挂起，走近了再弹
        if u:find("^party") or u:find("^raid") then BA.Wait("f") end
        return false, "far"
    end
    BA.ShowField({ who = who, cls = cls, lv = lv, list = list, want = BA.WantOf(list), choices = BA.ChoiceList(cls, lv, miss, who) })
    return true, who
end
function BA.FieldText(o)
    local lvTxt = o.lv and string.format(L("（%d 级）", " (Lv%d)"), o.lv) or ""
    -- 11-20 能给不止一种祝福：让玩家选（下面一行按钮）；「会密他」= 默认那种
    return string.format(o.choices and L("附近有%s %s%s，你缺%s（他只能给你挂一种），选一种密他要：", "%s %s%s is nearby; you lack %s (one sticks) - pick one:")
        or L("附近有%s %s%s，你没有%s，要不要密他要？", "%s %s%s is nearby and you're missing %s - whisper them?"),
        clsName(o.cls), short(o.who) or o.who, lvTxt, joinNames(o.choices or o.list))
        .. "\n|cff999999" .. L("会密他：", "Will whisper: ") .. (BA.AskText(o.cls, o.list, o.who) or "") .. "|r"
        .. BA.AltText(o)
end
-- 11-18 用户「附近有别人点第二次就切换人啊」：小框里写附近还有几个能给（点「换人」或再点清单图标 = 换下一个）
function BA.AltText(o)
    local n = (o and not o.sample and o.want) and #BA.Alts(o) or 0
    if n <= 0 then return "" end
    return "\n|cff80c0ff" .. string.format(L("附近还有 %d 个能给：密完自动换下一个，也可以点「换人」", "%d more nearby can give it - next one comes up after you whisper, or click Next"), n) .. "|r"
end
local rotOf   -- 下面「换人」那段定义（密完自动换下一个也用）
-- 弹框里点「密他要」：点了才发
function BA.FieldSend()
    local o = BA.cur
    if not o then return false end
    if BA.RecentlyAsked(o.who) then BA.HideField(); return false end
    if not BA.CanChat() then
        ns.Print(L("现在发不了私聊（战斗中 / 聊天受限），过一会儿再点", "Can't whisper right now (combat / chat locked) - try again in a moment"))
        return false
    end
    local left = not ns.DEV_LOCAL and BA.lastField and BA.WHISPER_GAP - (now() - BA.lastField)
    if left and left > 0 then
        ns.Print(string.format(L("30 秒只能密一个，%d 秒后再点", "One whisper per 30 s - try again in %d s"), math.ceil(left)))
        return false
    end
    if not BA.Send(BA.AskText(o.cls, o.list, o.who), "WHISPER", o.who) then return false end
    BA.lastField = now()
    BA.MarkAsked(o.who, wall()); BA.NoteBless(o.who, o.list); BA.ArmThank(o.who, o.list)
    ns.Print(L("已密 ", "Whispered ") .. (short(o.who) or o.who) .. L(" 要 ", " for ") .. joinNames(o.list))
    -- 11-22 用户「如果还有可以点的，就一直点密到都密过了，再收起弹窗」：附近还有没密过的能给的人 → 框换成下一个，都密过了才收
    local g = not o.sample and o.want and BA.Givers(o.want)[1]
    if g then
        local r = rotOf(o.want)
        r.tried[o.who], r.tried[g.who], r.t = true, true, now()
        BA.ShowField({ who = g.who, cls = g.cls, lv = g.lv, list = g.list, want = o.want, choices = BA.ChoiceList(g.cls, g.lv, o.want, g.who) })
        return true
    end
    BA.HideField()
    return true
end
-- 11-20 GI-319 弹框里的 [要王者] [要力量] …：点哪个就密他要哪个（⛔ 点了才发，走 FieldSend：CL 话术、不带插件名）
--   选择行属于谁：野外 = 框里这个圣骑士；副本 = 计划里唯一的圣骑士（几个圣骑士已经各排一种 = 不给选，免得要成同一种）
-- 字宽（读不到 = nil）
local function strW(fs) return fs and fs.GetStringWidth and tonumber(fs:GetStringWidth()) or nil end
local function pickOwner(o)
    if not o then return nil end
    if not o.dungeon then return o.choices and o end
    local hit
    for _, p in ipairs(o.plan) do if p.cls == "PALADIN" then if hit then return nil end hit = p end end
    return hit and hit.choices and hit
end
BA.PickOwner = pickOwner
-- 副本：密完那个圣骑士，框里别的人照旧可点
function BA.PickBless(i)
    local o = BA.cur
    local p = o and not o.sample and pickOwner(o)   -- 示例框不发
    local t = p and p.choices[i]
    if not t then return false end
    if not o.dungeon then o.list = { t }; return BA.FieldSend() end
    local rest = {}
    for _, q in ipairs(o.plan) do if q ~= p then rest[#rest + 1] = q end end
    BA.cur = { who = p.who, cls = p.cls, list = { t } }
    if not BA.FieldSend() then
        if BA.frame:IsShown() then BA.cur = o end   -- 发不了（战斗 / 聊天受限）：框留着
        return false
    end
    if rest[1] then BA.ShowDungeon(rest) end
    return true
end
-- 画选择行：返回多占的高度（没有选择 = 0）；按钮宽按字量（中英文都放得下），默认那种高亮
function BA.PaintChoices(f, o)
    local p = pickOwner(o)
    local ch = p and p.choices
    if not ch then
        f.pickLbl:Hide()
        for _, b in ipairs(f.picks) do b:Hide() end
        return 0
    end
    f.pickLbl:SetText(L("选一种：", "Pick one:")); f.pickLbl:Show()
    local x = 10 + math.max(48, strW(f.pickLbl) or 60) + 6
    for i, b in ipairs(f.picks) do
        local t = ch[i]
        if t then
            local on, label = t == p.list[1], L("要", "Ask ") .. BA.BlessShort(t.k)
            b.label, b.bt, b.who, b.cls = label, t, p.who, p.cls
            b:SetText(on and ("|cff33ff99" .. label .. "|r") or label)
            local w = math.min(math.max(78, (strW(b.GetFontString and b:GetFontString()) or 0) + 24), 420 - x)
            b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", x, 36); b:SetWidth(w); b.px, b.pw = x, w
            x = x + w + 6
            if b.LockHighlight then if on then b:LockHighlight() else b:UnlockHighlight() end end
            b:Show()
        else
            b:Hide()
        end
    end
    return 28
end
function BA.HideField()
    BA.cur = nil
    if BA.frame then BA.frame:Hide() end
end
-- ---------- 副本弹框（11-16）：和野外同一个框，按钮换成 [队伍里要] [密他要] [以后别问] ----------
function BA.DungeonText(plan)
    local parts = {}
    for _, p in ipairs(plan) do
        parts[#parts + 1] = clsName(p.cls) .. " " .. (short(p.who) or p.who) .. L(" 能给", " can give ") .. joinNames(p.list)
    end
    local pick = pickOwner({ dungeon = true, plan = plan }) and L("\n圣骑士能给几种祝福（只能挂一种）：点下面「要…」直接密他", "\nThe Paladin can give several (one sticks): pick one below to whisper") or ""   -- 11-20
    return L("队里有", "In your group: ") .. table.concat(parts, L("；", "; ")) .. L("，你身上没有", " - you're missing it") .. pick
        .. "\n|cff999999" .. L("队伍里会说：", "Party message: ") .. (BA.PartyText(plan) or "") .. "|r"
end
function BA.ShowDungeon(plan, sample)
    local f = BA.Build()
    BA.cur = { dungeon = true, plan = plan, sample = sample }
    f.title:SetText(L("要 BUFF · 队里有人能给", "Buffs - your group can buff you"))
    f.ask:SetText(L("队伍里要", "Ask party")); f.ask.label = L("队伍里要", "Ask party")
    f.no:SetText(L("密他要", "Whisper")); f.no.label = L("密他要", "Whisper")
    f.mute:SetText(L("以后别问", "Don't ask again")); f.mute.label = L("以后别问", "Don't ask again")
    f.never:Hide()   -- 副本框的「以后别问」本身就是永久的
    BA.PaintExtras(f, false)
    local extra = BA.PaintChoices(f, BA.cur)
    f.text:SetText(BA.DungeonText(plan))
    if f.text.GetStringHeight then
        local h = tonumber(f.text:GetStringHeight())
        if h then f:SetHeight(math.max(112 + extra, 72 + h + extra)) end
    end
    f.age = 0
    f:Show()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
    if BA.SyncEvents then pcall(BA.SyncEvents) end
    return f
end
-- [队伍里要]：队伍 / 团队频道一句
function BA.DungeonParty()
    local o = BA.cur
    if not (o and o.dungeon) or o.sample then BA.HideField(); return false end
    if not BA.CanChat() then
        ns.Print(L("现在发不了（战斗中 / 聊天受限），过一会儿再点", "Can't send right now (combat / chat locked) - try again in a moment"))
        return false
    end
    local chan = clean(IsInRaid and call(IsInRaid)) and "RAID" or "PARTY"
    if not BA.Send(BA.PartyText(o.plan), chan) then return false end
    for _, p in ipairs(o.plan) do BA.ArmThank(p.who, p.list) end
    local t = wall()
    for _, p in ipairs(o.plan) do BA.MarkAsked(p.who, t); BA.NoteBless(p.who, p.list, t) end
    BA.HideField()
    return true
end
-- [密他要]：每个能给的人各密一句（10 分钟内密过的跳过）
function BA.DungeonWhisper()
    local o = BA.cur
    if not (o and o.dungeon) or o.sample then BA.HideField(); return false end
    if not BA.CanChat() then
        ns.Print(L("现在发不了私聊（战斗中 / 聊天受限），过一会儿再点", "Can't whisper right now (combat / chat locked) - try again in a moment"))
        return false
    end
    local t, n = wall(), 0
    for _, p in ipairs(o.plan) do
        if not BA.RecentlyAsked(p.who, t) and BA.Send(BA.AskText(p.cls, p.list, p.who), "WHISPER", p.who) then
            BA.MarkAsked(p.who, t); BA.NoteBless(p.who, p.list, t); BA.ArmThank(p.who, p.list); n = n + 1
        end
    end
    BA.HideField()
    return n > 0
end
-- [以后别问]：副本里改成「不管」
function BA.DungeonNever()
    BA.HideField()
    BA.SetDMode("off")
    ns.Print(L("副本里缺 BUFF 不再问你（/gi buff 弹框 重新打开；/gi buff 自动 = 缺了自动要）", "Won't ask about missing buffs in dungeons (/gi buff ask to turn back on)"))
    if ns.CloseHint then
        ns.CloseHint("buffAskDungeon", L("找回副本里的要 BUFF 弹框：GI 菜单 → 设置 → 窗口与提醒「要 BUFF 副本弹框」点「打开」",
            "Bring the dungeon buff prompt back: GI menu > Settings > Windows & alerts > Dungeon buff prompt"))
    end
end
-- 11-17 用户「这些弹出的功能都确保能永久关闭」：野外弹框上的 [不再弹框] = 关掉「野外弹框」那一项（存档 ns.db.buffAsk.field = false，重载 / 换角色都不弹）
function BA.Never()
    BA.muted = nil
    BA.HideField()
    BA.SetOpt("field", false)
    if ns.CloseHint then
        ns.CloseHint("buffAskField", L("要 BUFF 野外弹框已永久关闭（副本里的照旧）。找回：GI 菜单 → 设置 → 窗口与提醒「要 BUFF 野外弹框」点「打开」，或组队设置 →「要 BUFF」勾回来",
            "Field buff prompt closed for good (dungeons unchanged). Bring it back: GI menu > Settings > Windows & alerts > Field buff prompt, or Group settings > Buffs"))
    end
end
-- 三个按钮按框的种类分流
function BA.BtnA() if BA.cur and BA.cur.dungeon then return BA.DungeonParty() end return BA.FieldSend() end
function BA.BtnB() if BA.cur and BA.cur.dungeon then return BA.DungeonWhisper() end BA.HideField() end
function BA.BtnC() if BA.cur and BA.cur.dungeon then return BA.DungeonNever() end return BA.Mute() end
function BA.Mute()
    BA.muted = true
    BA.HideField()
    ns.Print(L("这次登录不再提示附近能给 BUFF 的人（/reload 或重登恢复；彻底关：组队设置 →「要 BUFF」）", "Buff prompts muted for this session (back after /reload; turn off in Group settings > Buffs)"))
end
function BA.Build()
    if BA.frame then return BA.frame end
    local f = CreateFrame("Frame", "GearInsightForeverBuffAsk", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(430, 112)   -- 11-17 多了「不再弹框」：330 → 372；11-18 多了「换人」：372 → 430
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
    f.title = title
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetSize(22, 22); close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() BA.HideField() end)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); f.text:SetPoint("TOPLEFT", 10, -28); f.text:SetWidth(410); f.text:SetJustifyH("LEFT")
    -- 11-18 用户「自定义 义父替代在哪里，要做到UI的」「要不用户找不到」：标题右边直接写现在的称呼，点了改（预设 / 自己填 / 去设置）
    local cb = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    if ns.SkinButton then ns.SkinButton(cb) end
    cb:SetSize(118, 18); cb:SetPoint("TOPRIGHT", -26, -4)
    cb:SetScript("OnClick", function(self) BA.CallClick(self) end)
    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L("求人 / 道谢的称呼", "Form of address"), 1, 0.82, 0)
        GameTooltip:AddLine(string.format(L("现在叫「%s」。点了换：义父 / 老哥 / 大佬 / 兄弟 / 老板，或者自己填", "Now \"%s\". Click to pick a preset or type your own"), ns.CallWord and ns.CallWord() or "义父"), 1, 1, 1, true)
        GameTooltip:AddLine(L("也在 设置 → 通用 →「求人 / 道谢的称呼」", "Also in Settings > General"), 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.call = cb
    local function btn(label, w, x, onClick, tip)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        if ns.SkinButton then ns.SkinButton(b) end
        b:SetSize(w, 22); b:SetPoint("BOTTOMLEFT", x, 8); b:SetText(label)
        b.label = label
        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(self.label, 1, 0.82, 0)
            GameTooltip:AddLine(type(tip) == "function" and tip(self) or tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    f.ask = btn(L("密他要", "Whisper"), 86, 10, function() BA.BtnA() end, function()
        local o = BA.cur
        if o and o.dungeon then return L("点了才发，在队伍频道说：\n", "Sends this to party chat (only when you click):\n") .. (BA.PartyText(o.plan) or "") end
        return L("点了才发，私聊他这句：\n", "Sends this whisper (only when you click):\n") .. ((o and BA.AskText(o.cls, o.list, o.who)) or "")
    end)
    -- 11-18 「换人」：附近还有别的能给的人时可点（没有 = 灰着）；副本框隐藏
    f.swap = btn(L("换人", "Next"), 56, 100, function() BA.SwapGiver() end, function()
        local o = BA.cur
        local alts = BA.Alts(o)
        if not alts[1] then return L("附近没有别的能给的人（10 分钟内密过的不算）", "Nobody else nearby can give it") end
        return string.format(L("换成附近下一个能给的人（还有 %d 个，轮着来）；只换框里的人，点「密他要」才发", "Switch to the next player nearby (%d more); nothing is sent until you click Whisper"), #alts)
    end)
    f.no = btn(L("不用", "No thanks"), 70, 160, function() BA.BtnB() end, function()
        local o = BA.cur
        if o and o.dungeon then return L("点了才发，私聊能给的人一句（10 分钟内密过的不再密）", "Whispers each player who can give it (skips anyone asked in the last 10 min)") end
        return L("关掉这个框；这个人 10 分钟内不再提示", "Close; this player won't be suggested again for 10 min")
    end)
    f.mute = btn(L("这次不再提示", "Not this session"), 98, 234, function() BA.BtnC() end, function()
        local o = BA.cur
        if o and o.dungeon then return L("副本里缺 BUFF 不再问；/gi buff 弹框 重新打开", "Stop asking in dungeons; /gi buff ask turns it back on") end
        return L("这次登录不再弹；/reload 或重登恢复。永久关掉点右边「不再弹框」", "Muted until /reload; use \"Never\" to turn it off for good")
    end)
    -- 11-17「确保能永久关闭」：野外框多一个永久的（副本框隐藏，「以后别问」已经是永久的）
    f.never = btn(L("不再弹框", "Never"), 84, 336, function() BA.Never() end, function()
        return L("永久不再弹这个框（记进存档，重载 / 换角色都不弹；副本里的照旧）。找回：设置 → 窗口与提醒「要 BUFF 野外弹框」",
            "Never show this prompt again (saved; dungeons unchanged). Bring it back in Settings > Windows & alerts")
    end)
    -- 11-20 GI-319 选祝福那一行（[要王者] [要力量] [要智慧]），平时藏着；BA.PaintChoices 排位置、量宽度
    f.pickLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); f.pickLbl:SetPoint("BOTTOMLEFT", 10, 41); f.pickLbl:Hide()
    f.picks = {}
    for i = 1, 3 do
        f.picks[i] = btn("", 90, 10, function() BA.PickBless(i) end, function(self)
            return L("点了才发，私聊他：\n", "Sends this whisper (only when you click):\n") .. (BA.AskText(self.cls, { self.bt }, self.who) or "")
        end)
        f.picks[i]:Hide()
    end
    f:SetScript("OnUpdate", function(self, el)
        self.age = (self.age or 0) + (el or 0)
        if self.age >= ((BA.cur and BA.cur.dungeon) and BA.DUNGEON_TTL or BA.FIELD_TTL) then BA.HideField() end
    end)
    f:Hide()
    BA.frame = f
    return f
end
-- 11-18 框上的「称呼：义父」按钮 + 「换人」按钮（field = 野外框；副本框没有换人）
function BA.PaintExtras(f, field)
    if f.call then f.call:SetText(L("称呼：", "Call: ") .. ((ns.CallWord and ns.CallWord()) or "义父")) end
    if not f.swap then return end
    if not field then f.swap:Hide(); return end
    f.swap:Show()
    local o = BA.cur
    local can = (o and not o.sample and o.want and BA.Alts(o)[1]) and true or false
    if f.swap.SetEnabled then f.swap:SetEnabled(can) elseif can and f.swap.Enable then f.swap:Enable() elseif f.swap.Disable then f.swap:Disable() end
end
-- 点「称呼：义父」：小菜单（主插件 Settings.lua 的 ns.CallMenu）；改完重画框里的话（预览句子跟着换）
function BA.CallClick(anchor)
    local function redraw()
        local f, o = BA.frame, BA.cur
        if not (f and f:IsShown()) then return end
        BA.PaintExtras(f, not (o and o.dungeon))
        if o and o.dungeon then f.text:SetText(BA.DungeonText(o.plan))
        elseif o then f.text:SetText(BA.FieldText(o)) end
    end
    if ns.CallMenu then return ns.CallMenu(anchor, redraw) end
    if ns.JumpToSetting then return ns.JumpToSetting("callword.custom") end
end
function BA.ShowField(o)
    local f = BA.Build()
    BA.cur = o
    if not o.sample then
        local d, t = BA.DB(), wall()
        d.fieldLast = t
        BA.MarkSeen(o.who, t)   -- 弹过就算问过：同一个人 10 分钟内只弹一次（不管点没点）
    end
    f.title:SetText(L("要 BUFF · 附近有人能给", "Buffs - someone nearby can buff you"))
    f.ask:SetText(L("密他要", "Whisper")); f.ask.label = L("密他要", "Whisper")
    f.no:SetText(L("不用", "No thanks")); f.no.label = L("不用", "No thanks")
    f.mute:SetText(L("这次不再提示", "Not this session")); f.mute.label = L("这次不再提示", "Not this session")
    f.never:Show()
    BA.PaintExtras(f, true)
    local extra = BA.PaintChoices(f, o)
    f.text:SetText(BA.FieldText(o))
    if f.text.GetStringHeight then
        local h = tonumber(f.text:GetStringHeight())
        if h then f:SetHeight(math.max(112 + extra, 72 + h + extra)) end
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

-- 11-21 灵魂石提醒（队友）SoulstoneAsk.lua 在按需加载的 _GroupMage（信标登录内存没余量）：这里只留触发 / 命令 / 窗口与提醒占位
--   e = 进本 / 队伍变动：副本里 · 组队 · 不在战斗 · 我不是术士 · 开关开着才静默加载，再把这次事件转给它（之后它自己注册事件）；
--   e = nil（命令 / 窗口与提醒按钮，玩家自己点的）：不是术士就加载。⛔ 术士永不加载
local function ssWant() return ns.db and BA.Opt("on") and BA.DB().ss ~= false and myClass() ~= "WARLOCK" end
local function ssLoad(e)
    local sa = ns.SoulstoneAsk
    if sa or myClass() == "WARLOCK" or e and (not ssWant() or combat() or not bool(call(IsInGroup))) then return sa end
    pcall(ns.LoadModule, "mage", e and true)
    sa = ns.SoulstoneAsk
    if sa and e then pcall(sa._event, nil, e) end
    return sa
end

-- ================= 事件（按开关只注册用得上的）=================
BA.EVENTS = {
    field = { "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "PLAYER_REGEN_DISABLED", "GROUP_ROSTER_UPDATE",
        "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" },
    auto = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" },
}
BA.ALL_EVENTS = { "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "PLAYER_REGEN_DISABLED", "GROUP_ROSTER_UPDATE",
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED" }
function BA.WantedEvents()
    local want = {}
    if not ns.db then return want end
    local function add(list) for _, e in ipairs(list) do want[e] = true end end
    if BA.FieldOn() or (BA.frame and BA.frame:IsShown()) then add(BA.EVENTS.field) end
    if BA.AutoOn() or (not ns.SoulstoneAsk and ssWant()) then add(BA.EVENTS.auto) end
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
-- 11-17 经验加成「练级 BUFF 补全器」：「buff和来源要可视化对应」「路上碰到还可以刷新」→ 记下附近见过的、能给 BUFF 的同阵营玩家
--   （2 分钟内、最多 30 人），给经验加成页 / 出发前清单画「增益 ← 牧师 XX」；点了走上面同一个弹框（点「密他要」才发，10 分钟一次），不另外发言
BA.Short = short
BA.near, BA.NEAR_TTL = {}, 120
function BA.Note(u)
    if not u or not exists(u) or isMe(u) or not bool(call(UnitIsPlayer, u)) then return end
    local cls = unitClass(u)
    if not (cls and BA.CLS_CN[cls]) then return end
    local mf, pf = clean(call(UnitFactionGroup, u)), clean(call(UnitFactionGroup, "player"))
    if (mf and pf and mf ~= pf) or bool(call(UnitIsDeadOrGhost, u)) then return end
    local who = DC.FullName(u)
    if not who or who == "" then return end
    local n, t = 0, now()
    for k, v in pairs(BA.near) do if t - v.t > BA.NEAR_TTL or v.t > t then BA.near[k] = nil else n = n + 1 end end
    if n >= 30 and not BA.near[who] then return end
    BA.near[who] = { who = who, cls = cls, lv = unitLevel(u), t = t }
end
-- ---------- 11-18 换人（用户「附近有别人点第二次就切换人啊」）----------
--   附近能给的人不止一个：小框「换人」/ 出发前清单同一个 BUFF 图标再点一次 → 换下一个（轮着来：都换过一遍再从头）。
--   跳过：10 分钟内密过的（BA.RecentlyAsked，野外弹框 / 副本 / 右键菜单共用）；点过「不用」/ 弹过框的（BA.SeenRecently）排到后面；
--   等级太低 / 已经给我挂了别的祝福的圣骑士 = CanGive 不出（同上面的规则）。只是换框里的人，⛔ 不发话（点「密他要」才发）
function BA.WantOf(list)
    local w = {}
    for _, t in ipairs(list or {}) do w[t.k] = true end
    return w
end
local function wantKey(want)
    local ks = {}
    for k in pairs(want or {}) do ks[#ks + 1] = k end
    table.sort(ks)
    return table.concat(ks, ",")
end
BA.WantKey = wantKey
-- 附近能给 want 里任一样的人：{ { who, cls, lv, list, t, seen }, … }；没弹过框的在前，再按最近见到的
-- 11-19 主城卡顿闸（gi_forever_mem_churn_test）：出发前清单每次刷新按每种 BUFF 各查一遍附近的人，主城几百人 × 5 种都走 CanGive 建表
--   → 先按职业筛掉给不了的人（CanGive 对他们本来就返回空），结果不变、不再为路人建表
local function wantsCls(want, cls)
    for _, ty in ipairs(BA.TYPES) do if ty.cls == cls and want[ty.k] then return true end end
    return false
end
function BA.Givers(want, from)
    local out, t = {}, now()
    if type(want) ~= "table" or not next(want) then return out end
    if from == nil then
        for _, ty in ipairs(BA.TYPES) do
            if ty.fam == "bless" and want[ty.k] then from = BA.BlessFrom() or false; break end
        end
    end
    for who, v in pairs(BA.near) do
        if t - v.t <= BA.NEAR_TTL and v.t <= t and wantsCls(want, v.cls) and not BA.RecentlyAsked(who) then
            local list = BA.CanGive(v.cls, v.lv, want, who, from)
            if #list > 0 then out[#out + 1] = { who = who, cls = v.cls, lv = v.lv, list = list, t = v.t, seen = BA.SeenRecently(who) } end
        end
    end
    table.sort(out, function(a, b)
        if a.seen ~= b.seen then return not a.seen end
        if a.t ~= b.t then return a.t > b.t end
        return a.who < b.who
    end)
    return out
end
-- 这一轮换过的人（按要的东西分开记；2 分钟没再点就重新开始）
BA.rot = {}
rotOf = function(want)
    local key, t = wantKey(want), now()
    local r = BA.rot[key]
    if not r or t - r.t > BA.NEAR_TTL or r.t > t then r = { tried = {}, t = t }; BA.rot[key] = r end
    return r
end
-- 除了框里现在这个人，附近还能给的
function BA.Alts(o)
    local out = {}
    if not (o and o.want) then return out end
    for _, g in ipairs(BA.Givers(o.want)) do if g.who ~= o.who then out[#out + 1] = g end end
    return out
end
-- 下一个该问谁（不改状态，给清单图标显示用）：没换过的在前；avoid = 这一轮别的图标已经占了的人（圣骑士一人一种）；cur = 框里现在这个
function BA.PeekGiver(want, avoid, cur, from)
    local list = BA.Givers(want, from)
    local r = rotOf(want)
    local function pick(skipTried, skipAvoid)
        for _, g in ipairs(list) do
            if g.who ~= cur and not (skipTried and r.tried[g.who]) and not (skipAvoid and avoid and avoid[g.who]) then return g end
        end
    end
    return pick(true, true) or pick(false, true), list   -- avoid 是硬的：同一个圣骑士不排给两种祝福
end
-- 弹框问下一个（清单图标点击 / 小框「换人」）：返回 true = 弹了；false, 原因
function BA.AskNext(want, avoid)
    local cur = BA.frame and BA.frame:IsShown() and BA.cur
    local curWho = (cur and not cur.dungeon and not cur.sample and cur.want and wantKey(cur.want) == wantKey(want)) and cur.who or nil
    local g, list = BA.PeekGiver(want, avoid, curWho)
    if not g then
        if curWho then ns.Print(L("附近没有别的能给的人了（10 分钟内密过的不算）", "Nobody else nearby can give it (players asked in the last 10 min are skipped)")) end
        return false, curWho and "noalt" or "none"
    end
    local r = rotOf(want)
    -- 附近就他一个、这一轮已经问过他（弹过框 / 点过「不用」）：不再弹第二次（原来「同一个人 10 分钟一次」的口径）
    if #list == 1 and (r.tried[g.who] or g.seen) then
        ns.Print(string.format(L("附近能给的只有 %s，刚问过了（10 分钟内不再弹）", "Only %s nearby can give it and was just asked"), short(g.who) or g.who))
        return false, "asked"
    end
    if curWho then r.tried[curWho] = true end
    r.tried[g.who], r.t = true, now()
    BA.ShowField({ who = g.who, cls = g.cls, lv = g.lv, list = g.list, want = want, choices = BA.ChoiceList(g.cls, g.lv, want, g.who) })
    return true, g.who
end
function BA.SwapGiver()
    local o = BA.cur
    if not o or o.dungeon or o.sample or not o.want then return false, "none" end
    return BA.AskNext(o.want)
end
-- 附近能给谁 / 点了怎么要（BA.Nearby / BA.AskNear）在按需加载的 GearInsight_Forever_Xp（XpSupply.lua）里，省主插件登录内存
local function onUnit(u)
    if BA.FieldOn() then pcall(BA.Note, u); pcall(BA.FieldCheck, u) end
end
ev:SetScript("OnEvent", function(_, e, a1)
    if e == "PLAYER_TARGET_CHANGED" then onUnit("target")
    elseif e == "UPDATE_MOUSEOVER_UNIT" then onUnit("mouseover")
    elseif e == "NAME_PLATE_UNIT_ADDED" then if type(a1) == "string" then onUnit(a1) end
    elseif e == "PLAYER_REGEN_DISABLED" then if BA.frame and BA.frame:IsShown() then BA.HideField() end
    elseif e == "PLAYER_ENTERING_WORLD" or e == "ZONE_CHANGED_NEW_AREA" then
        local inInst, inst = inDungeon()
        if not inInst then BA.runInst, BA.runAsked = nil, {}         -- 出了副本：下次进本重新要
        elseif BA.runInst ~= inst then BA.runInst, BA.runAsked = inst, {} end
        if inAnyInstance() and BA.frame and BA.frame:IsShown() and not (BA.cur and BA.cur.dungeon) then BA.HideField() end
        if not inInst and BA.cur and BA.cur.dungeon then BA.HideField() end
        if e == "PLAYER_ENTERING_WORLD" then pcall(BA.MigrateNote) end
        if inInst then autoSoon("enter", BA.ENTER_DELAY); ssLoad(e) end
    elseif e == "GROUP_ROSTER_UPDATE" then
        if inDungeon() then autoSoon("roster", 2); ssLoad(e) end
        if BA.FieldOn() then pcall(BA.FieldRoster) end
    elseif e == "PLAYER_REGEN_ENABLED" then
        if BA.pendingAuto then local r = BA.pendingAuto; BA.pendingAuto = nil; autoSoon(r, 2) end
    end
end)
BA._event = ev:GetScript("OnEvent")   -- 测试用

-- ---------- 设置页（组队抽屉齿轮「组队设置」+ 全部设置索引）----------
-- 11-20 GI-319「找骑士要BUFF 可以提供选择要王者还是力量」：几种祝福都缺时先要哪种 + 哪种不要，插在说明后面
--   圣骑士自己不显示；职业用不上的那种不显示（读不到职业 = 全显示）
local function blessAvail(k)
    local cls = myClass()
    return cls ~= "PALADIN" and (k == "auto" or not cls or fitCls(BA.BY_K[k], cls))
end
-- ⛔ 一整块画成一个 custom 项（两行勾选框只在打开设置页时才建）：每多一个设置项登录就多占约 1 KB（内存预算闸）
BA.blessCtl = setmetatable({}, { __mode = "k" })
local function blessSync() for c in pairs(BA.blessCtl) do c:SetChecked(c.get() and true or false) end end
if ns.OnSettingsRefresh then ns.OnSettingsRefresh(blessSync) end
function BA.BlessRow(row, x)
    local lines = { { L("圣骑士祝福先要：", "Blessing:") }, { L("这几种不要：", "Skip:") } }
    for _, k in ipairs({ "auto", "kings", "might", "wis" }) do
        if blessAvail(k) then
            local nm = k == "auto" and L("自动", "Auto") or BA.BlessShort(k)
            table.insert(lines[1], { nm, function() return BA.BlessPrefRaw() == k end, function() BA.SetBlessPref(k) end })
            if k ~= "auto" then table.insert(lines[2], { L("不要", "") .. nm, function() return BA.BlessNo(k) end, function(v) BA.SetBlessNo(k, v) end }) end
        end
    end
    local lw = 0
    for i, ln in ipairs(lines) do
        ln.fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        ln.fs:SetPoint("TOPLEFT", x + 4, 23 - i * 28); ln.fs:SetText(ln[1])
        lw = math.max(lw, strW(ln.fs) or 100)
    end
    local first, right = nil, 0
    for i, ln in ipairs(lines) do
        local cx = x + lw + 14
        for j = 2, #ln do
            local o = ln[j]
            local c = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            c:SetSize(24, 24); c:SetPoint("TOPLEFT", cx, 28 - i * 28)
            local t = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            t:SetPoint("LEFT", c, "RIGHT", 2, 0); t:SetText(o[1])
            c.get, c.label = o[2], t
            c:SetScript("OnClick", function(self) o[3](self:GetChecked() and true or false); ns.RefreshSettings(); blessSync() end)
            BA.blessCtl[c] = true
            first = first or c
            cx = cx + 28 + math.max(28, strW(t) or 40) + 12
        end
        right = math.max(right, cx)
    end
    blessSync()
    BA.blessRight = right   -- 测试用：两行最右到哪
    return first, 0
end
-- 插在「称呼」按钮前面（说明之后）
local function withBless(items)
    local at = #items + 1
    for i, it in ipairs(items) do if it.id == "buffask.call" then at = i; break end end
    table.insert(items, at, { type = "custom", id = "buffask.bless", indent = 18, h = 58, avail = function() return blessAvail("auto") end,
        text = function() return L("圣骑士祝福先要哪种 / 哪种不要", "Paladin blessing preference") end, build = BA.BlessRow })
    table.insert(items, at + 1, { type = "note", indent = 36, avail = items[at].avail, text = function() return L("圣骑士能给几种时弹框里直接选（偏好那种高亮）；/gi buff 王者 | 力量 | 智慧 · 祝福 自动 · 不要力量",
        "Pick in the prompt when a Paladin can give several; /gi buff kings | might | wisdom, bless auto, no might") end })
    return items
end
if ns.RegisterSettings then
    ns.RegisterSettings({ key = "buffask", order = 96, drawer = "group", avail = function() return ns.BuffAsk ~= nil end,
        title = function() return L("要 BUFF", "Ask for buffs") end, short = function() return L("要BUFF", "Buffs") end,
        items = withBless({
            { type = "check", id = "buffask.on", text = function() return L("总开关：要 BUFF（耐力 / 智力 / 野性印记 / 圣骑士祝福）", "Master switch: ask for buffs (Fortitude / Intellect / Mark of the Wild / Blessings)") end,
              get = function() return BA.Opt("on") end, set = function(v) BA.SetOpt("on", v) end },
            { type = "check", id = "buffask.field", indent = 18, text = function() return L("野外 / 主城碰到能给我缺的 BUFF 的人时弹框问（点了才密，同一个人 10 分钟一次）", "Pop a prompt when someone nearby can give a buff you lack (only whispers if you click)") end,
              get = function() return BA.Opt("field") end, set = function(v) BA.SetOpt("field", v) end },
            { type = "label", id = "buffask.dmodeLabel", indent = 18, w = 150, text = function() return L("副本里缺了、队里有人能给：", "In dungeons, if missing:") end },
            { type = "check", radio = true, inline = true, id = "buffask.dmode.ask", step = 96, text = function() return L("弹框问我", "Ask me") end,
              get = function() return BA.DModeRaw() == "ask" end, set = function() BA.SetDMode("ask") end },
            { type = "check", radio = true, inline = true, id = "buffask.dmode.auto", step = 86, text = function() return L("自动要", "Auto") end,
              get = function() return BA.DModeRaw() == "auto" end, set = function() BA.SetDMode("auto") end },
            { type = "check", radio = true, inline = true, id = "buffask.dmode.off", step = 70, text = function() return L("不管", "Off") end,
              get = function() return BA.DModeRaw() == "off" end, set = function() BA.SetDMode("off") end },
            { type = "note", indent = 36, text = function() return L("弹框问我：点「队伍里要 / 密他要」才发；自动要：进本 / 队伍变动时直接发。都是每次进本每种只要一次，战斗中不发", "Ask me: sends only when you click; Auto: sends on entering / group change. Once per run each, never in combat") end },
            { type = "check", id = "buffask.whisper", indent = 36, text = function() return L("自动要时改成私聊那个人（默认发队伍频道）", "Auto: whisper the player instead of party chat") end,
              get = function() return BA.Opt("whisper") end, set = function(v) BA.SetOpt("whisper", v) end },
            { type = "note", indent = 18, text = function() return L("战士 / 盗贼不要智力和智慧祝福；圣骑士祝福（力量 / 智慧 / 王者）每种单独算、单独要 —— 一个圣骑士只能给你挂一种，不同的祝福要找不同的圣骑士；自己职业能加的不要。发的话不带插件名，例如「义父，求个耐力，谢谢~」",
                  "Warriors / Rogues skip Intellect and Wisdom; each Paladin blessing (Might / Wisdom / Kings) is checked and asked separately - one Paladin can only keep one blessing on you, so different blessings come from different Paladins; your own class's buff is skipped. Messages carry no addon name.") end },
            -- 11-18 用户「自定义 义父替代在哪里，要做到UI的」：要 BUFF 设置里直接放称呼入口
            { type = "button", id = "buffask.call", indent = 18, w = 200, dyn = true, text = function() return L("称呼：", "Form of address: ") .. ((ns.CallWord and ns.CallWord()) or "义父") .. L("（点了改）", " (change)") end,
              click = function(self) if ns.CallMenu then ns.CallMenu(self) elseif ns.JumpToSetting then ns.JumpToSetting("callword.custom") end end },
            -- 11-17 用户「话术变化增多」：默认每次换个说法（称呼 × 请求 × 结尾 216 种）；勾上 = 回到固定老说法。要吃喝（找法师要水）也按这个
            { type = "check", id = "buffask.fixed", indent = 18, text = function() return L("固定一种说法（不勾 = 每次换个说法，像真人说话；要水也按这个）", "Use one fixed phrase (unchecked = vary the wording each time; also for water)") end,
              get = function() return DC.AskFixed() end, set = function(v) DC.DB().rec.askFixed = v and true or nil end },
            { type = "check", id = "buffask.pin", indent = 18, text = function() return L("私聊要 BUFF 时句尾带 [地图标记位置]（对方点了看到你在哪）", "Add a [map pin] link when whispering for buffs") end,
              get = function() return BA.PinOn() end, set = function(v) if v then DC.DB().rec.askPin = nil else DC.DB().rec.askPin = false end end },
        }) })
end

-- /gi buff · /gi 要buff：打开组队设置；/gi buff test = 弹一个示例框（不发任何话）
ns.ExtraSlash = ns.ExtraSlash or {}
BA.BLESS_WORD = { ["王者"] = "kings", kings = "kings", ["力量"] = "might", might = "might", ["智慧"] = "wis", wisdom = "wis", ["自动"] = "auto", auto = "auto" }
-- 11-20 返回 true = 认得这条（已处理）：王者 | 力量 | 智慧 · 祝福 [自动|王者…] · 不要X / 要X（「自动」单独一个词 = 副本自动要，不归这里）
function BA.BlessSlash(rest)
    local W = BA.BLESS_WORD
    local arg = rest:match("^祝福%s*(.*)$") or rest:match("^bless%s*(.*)$")
    local no, yes = rest:match("^不要%s*(.+)$") or rest:match("^no%s+(.+)$"), rest:match("^要%s*(.+)$")
    local k = W[arg or (W[rest] ~= "auto" and rest) or ""] or W[no or yes or ""]
    if not k and arg ~= "" then return false end
    if (no or yes) and k == "auto" then return false end
    if k and k ~= "auto" and not fitCls(BA.BY_K[k], myClass()) then
        ns.Print(string.format(L("你的职业用不上%s，没改", "Your class has no use for %s - unchanged"), buffName(BA.BY_K[k])))
    elseif no or yes then BA.SetBlessNo(k, no and true)
    elseif k then BA.SetBlessPref(k) end
    ns.Print(L("要 BUFF · 圣骑士祝福：", "Buffs - blessings: ") .. BA.BlessNoText())
    return true
end
local function slash(rest)
    if rest == "why" or rest == "诊断" or rest == "check" then pcall(ns.LoadModule, "mage"); return BA.Diag and BA.Diag() end
    -- 11-21 /gi buff 石头 …：灵魂石提醒没加载时先加载再转过去（它加载后自己接管这条命令）
    if rest and (rest:match("^石头") or rest:match("^灵魂石") or rest:match("^soulstone") or rest:match("^ss")) and ssLoad() and ns.ExtraSlash.buff ~= slash then return ns.ExtraSlash.buff(rest) end
    -- 11-16：不用进设置页就能切
    if rest == "开" or rest == "on" then BA.SetOpt("on", true); ns.Print(L("要 BUFF：已打开", "Buffs: on")); return end
    if rest == "关" or rest == "off" then BA.SetOpt("on", false); ns.Print(L("要 BUFF：已关闭（野外弹框和副本都不再管；/gi buff 开 重新打开）", "Buffs: off (/gi buff on to re-enable)")); return end
    -- 11-20 GI-319 圣骑士祝福偏好：/gi buff 王者 | 力量 | 智慧 · /gi buff 祝福 自动 · /gi buff 不要力量 | 要力量（「/gi buff 自动」是副本自动要，不动）
    if BA.BlessSlash(rest or "") then return end
    local dm = ({ ["自动"] = "auto", auto = "auto", ["弹框"] = "ask", ["问"] = "ask", ask = "ask", ["不管"] = "off", none = "off" })[rest or ""]
    if dm then
        BA.SetDMode(dm)
        if dm ~= "off" and not BA.Opt("on") then BA.SetOpt("on", true) end
        ns.Print(L("要 BUFF：副本里缺了 → ", "Buffs: in dungeons -> ") .. BA.DModeText(dm))
        return
    end
    -- 示例框 /gi buff test | test2 | test3（不发任何话）：11-23 搬进按需加载的 _GroupMage BuffAskDiag.lua（BA.Test），给内核腾内存
    if rest and (rest:match("^test") or rest:match("^测试")) then pcall(ns.LoadModule, "mage"); return BA.Test and BA.Test(rest) end
    if ns.JumpToSetting and ns.JumpToSetting("buffask.on") then return end
    ns.Print(string.format(L("要 BUFF：总开关%s · 野外弹框%s · 副本里缺了：%s · 圣骑士祝福：%s（/gi buff 开 | 关 | 自动 | 弹框 | 不管 · 王者 | 力量 | 智慧 | 祝福 自动）",
        "Buffs: %s / field %s / dungeon: %s / blessings: %s (/gi buff on | off | auto | ask | none | kings | might | wisdom | bless auto)"),
        BA.Opt("on") and L("开", "on") or L("关", "off"), BA.Opt("field") and L("开", "on") or L("关", "off"), BA.DModeText(), BA.BlessNoText()))
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

-- ---------- 「窗口与提醒」（11-17 用户「这些弹出的功能都确保能永久关闭」：弹框上永久关掉的从这里找回）----------
--   组队信标登录就加载（_Group），这两行一直在
if ns.RegisterWindow then
    ns.RegisterWindow({ key = "buffAskField", order = 62, title = function() return L("要 BUFF 野外弹框", "Field buff prompt") end,
        state = function()
            if not BA.Opt("on") then return L("要 BUFF 总开关关着", "Buffs master switch is off") end
            if not BA.Opt("field") then return L("已关闭", "Closed") end
            if BA.muted then return L("这次登录静音（重载恢复）", "Muted this session") end
            return L("碰到能给你缺的 BUFF 的人时弹出", "Pops up when someone nearby can buff you")
        end,
        actions = function()
            local on = BA.FieldOn() and not BA.muted
            return {
                { text = on and L("关闭", "Turn off") or L("打开", "Turn on"), fn = function()
                    if on then BA.Never() else BA.muted = nil; BA.SetOpt("on", true); BA.SetOpt("field", true) end
                end },
                { text = L("示例", "Preview"), fn = function() pcall(ns.LoadModule, "mage"); return BA.Test and BA.Test("test") end },
            }
        end })
    ns.RegisterWindow({ key = "buffAskDungeon", order = 63, title = function() return L("要 BUFF 副本弹框", "Dungeon buff prompt") end,
        state = function()
            local m = BA.DMode()
            if m == "off" then return L("已关闭", "Closed") end
            if m == "auto" then return L("改成了自动要（不弹框）", "Set to ask automatically (no prompt)") end
            return L("副本里缺 BUFF、队里有人能给时弹出", "Pops up in dungeons when a groupmate can buff you")
        end,
        actions = function()
            local on = BA.DMode() ~= "off"
            return {
                { text = on and L("关闭", "Turn off") or L("打开", "Turn on"), fn = function()
                    if on then BA.SetDMode("off") else BA.SetOpt("on", true); BA.SetDMode("ask") end
                end },
            }
        end })
    -- 11-21 灵魂石提醒（队友）：SoulstoneAsk.lua 按需加载，登记留在这里（没加载也能关 / 找回）；按钮走 /gi buff 石头（会先加载）。术士不出这一条
    if myClass() ~= "WARLOCK" then ns.RegisterWindow({ key = "ssAsk", order = 64, title = function() return L("灵魂石提醒（队友）", "Soulstone prompt") end,
        state = function() return ssWant() and L("副本里队里有术士、没人绑灵魂石时弹出", "Pops up in dungeons when a Warlock is grouped and nobody has a Soulstone") or L("已关闭", "Closed") end,
        actions = function()
            local a = ssWant() and "关" or "开"
            return { { text = a == "关" and L("关闭", "Turn off") or L("打开", "Turn on"), fn = function() slash("石头 " .. a) end }, { text = L("示例", "Preview"), fn = function() slash("石头 测试") end } }
        end }) end
end
