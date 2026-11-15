-- HOLD：圣骑士「一键加祝福」（11-14 用户「圣骑士一键加祝福功能设计一下做进去」），游戏内实测前不进发行包
--
-- ① 放在哪：职业子插件 GearInsight_Forever_Class（按需加载），不放主插件。理由：
--   · 里面有安全按钮（SecureActionButton 施法 + 绑键 SetBindingClick），_Class 走 ModStub.lua 的 noCombat：战斗中一律不加载，
--     保证安全按钮只在脱战时建、属性只在脱战时设（主插件 /reload 时可能正在战斗）
--   · 只有圣骑士用得上：放主插件 = 九个职业每次登录都要读这份代码；放 _Class 非圣骑士零成本（页 / 命令 / 设置都只给圣骑士）
--   · 圣骑士进队时（GROUP_ROSTER_UPDATE / 登录时已在队里、悬浮按钮开着）ClassStub.lua 才条件加载 _Class，单刷不加载
--   · 和猎人弹药提醒（AmmoRemind.lua）同一套：主插件 ClassStub.lua 放占位页 / 命令占位，Settings.lua 放设置描述（读存档不加载）
--
-- ② 祝福数据（⛔ 名字 / id 以游戏数据为准，别凭记忆）：
--   · 力量 / 智慧 / 强效力量 / 强效智慧 / 强效王者：开服客户端 DB2 技能书 services/dashboard/static/data/forever/spellbook.json
--     （逐级 id + 学习等级；TrainNowData.lua 里能对上的几级 id 一致：19740 / 19834 / 19742 / 25782 / 25894 / 25898 …）
--   · 单体王者祝福：无限改成训练师 20 级学（不是天赋了，class_hub/Paladin.json、abilities.json「王者祝福与奉献 两者均可通过训练学习」），
--     训练师实测 obs_confirmed.json「王者祝福 20 级 3100 铜」62 台设备；id 20217（插件宏库 macros.json「祝福一键」宏同一个 id）
--   · 拯救祝福 / 光明祝福（含强效）：11-05 客户端 70790 已经删掉（raid_buffs.json 的 src 注释），这里不做；
--     「拯救别给坦克」的问题也就不存在了。庇护祝福无限天赋树里没有
--   · 强效祝福要「王者印记」（物品 21177，db_items.json）：背包里没有就改用单体（无限有没有改掉没实测，先按经典处理）
--
-- ③ 分配（默认，玩家可改；存 ns.db.pally）：
--   · 战士 / 盗贼 → 力量；法师 / 术士 / 牧师 → 智慧；猎人 → 智慧（力量祝福只加「近战」攻击强度，猎人吃不到）
--   · 德鲁伊 / 圣骑士 / 萨满（有蓝的混合职业）→ 智慧；熊猫德 / 增强萨 / 惩戒骑想要力量：页上点职业格换，或右键名字单独指定这个人
--   · 学会王者祝福后可勾「全给王者」：所有人改给王者（职业格单独设了「不加」的照旧不加）
--   · 每个职业「有用的祝福」：纯近战 = 力量 / 王者；纯法系 + 猎人 = 智慧 / 王者；混合职业三种都行 —— 冲突时只在这里面挑替补
--   · 多个圣骑士（各自一套，不冲突就行）：插件频道 GIFPB 互发自己的分配；名字排序靠前的先挑，靠后的遇到同职业同祝福就换替补
--     （首选 → 王者 → 另一种有用的），都被占了这个职业就不加。名字靠前的分配不看靠后的人 → 不会来回改
--   · 没装插件的圣骑士：读队友身上的光环，同类祝福已经是别人加的（来源不是我）→ 这个人换替补；替补都被占 = 跳过（不覆盖别人的）
--   · 用自己已学的最高级；经典里高等级祝福给低等级目标有限制（目标等级 ≥ 法术学习等级 − 10），按目标等级降级；
--     游戏报「目标等级太低」时把这个人这一级记下来，下次再降一级（规则没在无限实测，以报错自动校正）
--   · 52 级起强效祝福：在队伍里、同职业 ≥ 2 个都要同一种祝福、而且这个职业每个人分到的都是这种（没有单独指定成别的）、
--     背包有王者印记、强效那一级对这个职业最低等级的人也能上 → 点一下用强效（一次给整个职业）；设置里可关
--
-- ④ 一键流程：
--   · 一个 SecureActionButton（type = spell / spell = 法术 id / unit = 队友），每点一下（硬件事件）给「下一个」施放分给他的祝福
--     —— 暴雪规定每次施法都要一次按键，所以是连点逐个加，不能一键全加
--   · 下一个 = 先挑没有我这份祝福的（队伍顺序），都有了再挑我加的快到期的（剩余 < 1 分钟，可改，剩得最少的先）
--   · 跳过：死亡 / 离线 / 不在视野或施法距离外 / 等级太低没有能上的一级 / 别人已经加了同类而替补都被占 / 刚施放还没生效（1.5 秒）/
--     刚报过「视线受阻 / 距离太远」（8 秒内不再点他，先给下一个）
--   · 属性只在脱战时改：PreClick（脱战时）现算一次下一个再设属性；施法成功 / UNIT_AURA / 每秒刷新时脱战就更新到下一个
--   · 战斗中：状态驱动（RegisterStateDriver [combat]）进战斗瞬间清掉 type 并隐藏按钮（受保护代码里做，插件代码战斗中不碰属性），
--     脱战后插件再设属性、显示；悬浮框战斗中显示「战斗中暂停」，不能拖
--   · 页上一个按钮 + 可拖动小悬浮框（组队时出，显示「下一个：名字 · 祝福」和还缺几个）；绑键 = 页上「设置快捷键」按一个键
--     （SetBindingClick 到悬浮框里的按钮，只绑这一个键；用户规定键位只许逐个设置，不许一键铺 / 一键绑。无限版插件里没有 CoreKeyCheck）
--   · 只认 AnyDown（同 MageWater.lua 的安全按钮）
--
-- ⑤ 开关（Settings.lua 的 ns.RegisterSettings「pally」组）：页（db.pally.page）、悬浮按钮（float）、全给王者（allKings）、
--   强效祝福（greater）、恢复默认分配；命令 /gi 祝福（/gi pb）：开页 · 悬浮 开|关 · 王者 开|关 · 强效 开|关 · 提前 秒数 · 默认
local _, ns = ...; ns = _G.GearInsightForever or ns

local PB = {}
ns.PallyBless = PB
local function L(cn, en) return ns.L(cn, en) end

PB.PREFIX = "GIFPB"
PB.SOON = 60          -- 我加的祝福剩余少于这么多秒 = 快到期，要补
PB.INFLIGHT = 1.5     -- 刚点完：这么久内不再挑同一个人（光环还没到）
PB.BLOCK = 8          -- 报「视线受阻 / 距离太远」后这么久不挑他
PB.LOWLV = 10         -- 目标等级 ≥ 法术学习等级 − 10 才能上（经典规则；无限没实测，报错自动校正）
PB.GREATER_MIN = 2    -- 同职业几个人起用强效
PB.SYMBOL = 21177     -- 王者印记（强效祝福的材料）
PB.BTN = "GearInsightForeverPallyBlessBtn"   -- 绑键目标（悬浮框里的安全按钮）

-- ---------- 数据（来源见文件头 ②）----------
--   ranks / greater：{ 法术 id, 学习等级 }，按等级升序
PB.TYPES = {
    M = { cn = "力量祝福", en = "Blessing of Might", gcn = "强效力量祝福", gen = "Greater Blessing of Might", short = "力量", shortEn = "Might",
          icon = "Interface\\Icons\\Spell_Holy_FistOfJustice",
          ranks = { { 19740, 4 }, { 19834, 12 }, { 19835, 22 }, { 19836, 32 }, { 19837, 42 }, { 19838, 52 }, { 25291, 60 } },
          greater = { { 25782, 52 }, { 25916, 60 } } },
    W = { cn = "智慧祝福", en = "Blessing of Wisdom", gcn = "强效智慧祝福", gen = "Greater Blessing of Wisdom", short = "智慧", shortEn = "Wisdom",
          icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom",
          ranks = { { 19742, 14 }, { 19850, 24 }, { 19852, 34 }, { 19853, 44 }, { 19854, 54 }, { 25290, 60 } },
          greater = { { 25894, 54 }, { 25918, 60 } } },
    K = { cn = "王者祝福", en = "Blessing of Kings", gcn = "强效王者祝福", gen = "Greater Blessing of Kings", short = "王者", shortEn = "Kings",
          icon = "Interface\\Icons\\Spell_Magic_MageArmor",
          ranks = { { 20217, 20 } },
          greater = { { 25898, 60 } } },
}
PB.ORDER = { "M", "W", "K" }
-- 法术 id / 名字 → 祝福类型（读光环用；强效和单体同类，不叠加）
PB.BY_ID, PB.BY_NAME = {}, {}
for t, d in pairs(PB.TYPES) do
    for _, r in ipairs(d.ranks) do PB.BY_ID[r[1]] = { t = t, lv = r[2] } end
    for _, r in ipairs(d.greater) do PB.BY_ID[r[1]] = { t = t, lv = r[2], greater = true } end
    PB.BY_NAME[d.cn], PB.BY_NAME[d.en], PB.BY_NAME[d.gcn], PB.BY_NAME[d.gen] = t, t, t, t
end

PB.CLASSES = { "WARRIOR", "ROGUE", "HUNTER", "DRUID", "PALADIN", "SHAMAN", "MAGE", "WARLOCK", "PRIEST" }
PB.CLASS_CN = { WARRIOR = "战士", ROGUE = "盗贼", HUNTER = "猎人", DRUID = "德鲁伊", PALADIN = "圣骑士", SHAMAN = "萨满",
    MAGE = "法师", WARLOCK = "术士", PRIEST = "牧师" }
PB.CLASS_EN = { WARRIOR = "Warrior", ROGUE = "Rogue", HUNTER = "Hunter", DRUID = "Druid", PALADIN = "Paladin", SHAMAN = "Shaman",
    MAGE = "Mage", WARLOCK = "Warlock", PRIEST = "Priest" }
PB.DEFAULT = { WARRIOR = "M", ROGUE = "M", HUNTER = "W", DRUID = "W", PALADIN = "W", SHAMAN = "W", MAGE = "W", WARLOCK = "W", PRIEST = "W" }
-- 这个职业用得上的祝福（冲突换替补只在这里面挑）
local MELEE, CASTER, HYBRID = { M = true, K = true }, { W = true, K = true }, { M = true, W = true, K = true }
PB.USEFUL = { WARRIOR = MELEE, ROGUE = MELEE, HUNTER = CASTER, MAGE = CASTER, WARLOCK = CASTER, PRIEST = CASTER,
    DRUID = HYBRID, PALADIN = HYBRID, SHAMAN = HYBRID }

-- ---------- 小工具 ----------
local function now() return GetTime and GetTime() or 0 end
local function combat() return InCombatLockdown and InCombatLockdown() and true or false end
local function call(f, ...) if not f then return nil end local ok, a, b, c = pcall(f, ...); if ok then return a, b, c end end
local function short(name) return type(name) == "string" and (name:match("^([^%-]+)") or name) or nil end
local function exists(u)
    if UnitExists then return call(UnitExists, u) and true or false end
    return UnitGUID ~= nil and call(UnitGUID, u) ~= nil
end
local function isMe(u)
    if u == "player" then return true end
    return UnitIsUnit ~= nil and call(UnitIsUnit, u, "player") and true or false
end
local function classOf(u) local _, c = call(UnitClass, u); return c end
function PB.IsPaladin() return classOf("player") == "PALADIN" end
local function inGroup() return IsInGroup ~= nil and call(IsInGroup) and true or false end
local function inRaid() return IsInRaid ~= nil and call(IsInRaid) and true or false end
function PB.TypeName(t, greater)
    local d = t and PB.TYPES[t]
    if not d then return L("不加", "None") end
    if greater then return L(d.gcn, d.gen) end
    return L(d.cn, d.en)
end
function PB.ClassName(c) return L(PB.CLASS_CN[c] or c or "?", PB.CLASS_EN[c] or c or "?") end

-- ---------- 设置（ns.db.pally；nil = 默认）----------
function PB.DB()
    if not ns.db then return {} end
    if type(ns.db.pally) ~= "table" then ns.db.pally = {} end
    return ns.db.pally
end
function PB.FloatOn() return not (ns.db and type(ns.db.pally) == "table" and ns.db.pally.float == false) end
function PB.GreaterOn() return not (ns.db and type(ns.db.pally) == "table" and ns.db.pally.greater == false) end
function PB.AllKings() return ns.db ~= nil and type(ns.db.pally) == "table" and ns.db.pally.allKings == true end
function PB.Soon() return tonumber(PB.DB().soon) or PB.SOON end
-- ⛔ 别写成 (not v) and false or nil（恒为 nil）
function PB.SetFloat(v) if v then PB.DB().float = nil else PB.DB().float = false end; PB.Refresh() end
function PB.SetGreater(v) if v then PB.DB().greater = nil else PB.DB().greater = false end; PB.Refresh() end
function PB.SetPage(v) if v then PB.DB().page = nil else PB.DB().page = false end end
function PB.SetAllKings(v) PB.DB().allKings = v and true or nil; PB.Refresh(); PB.Broadcast(true) end
function PB.SetSoon(sec)
    sec = tonumber(sec)
    if not sec then return end
    PB.DB().soon = math.max(10, math.min(1800, math.floor(sec)))
    PB.Refresh()
end
-- 职业的首选：玩家设过的（"M" / "W" / "K" / "0" = 不加）> 全给王者 > 默认
function PB.ClassPref(c)
    local by = PB.DB().by
    local v = type(by) == "table" and by[c] or nil
    if v == "0" then return nil end
    if v and PB.TYPES[v] then return v end
    if PB.AllKings() and PB.Knows("K") then return "K" end
    return PB.DEFAULT[c]
end
function PB.SetClassPref(c, v)   -- v = nil 恢复默认
    local db = PB.DB()
    db.by = type(db.by) == "table" and db.by or {}
    db.by[c] = v
    PB.Refresh(); PB.Broadcast(true)
end
-- 单独指定某个人（按名字记；"0" = 不给他加）
function PB.WhoPref(name)
    local w = PB.DB().who
    return type(w) == "table" and name and w[name] or nil
end
function PB.SetWhoPref(name, v)
    if not name then return end
    local db = PB.DB()
    db.who = type(db.who) == "table" and db.who or {}
    db.who[name] = v
    PB.Refresh()
end
function PB.ResetAssign()
    local db = PB.DB()
    db.by, db.who, db.allKings = nil, nil, nil
    PB.Refresh(); PB.Broadcast(true)
end

-- ---------- 会哪些 ----------
local function known(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown and call(C_SpellBook.IsSpellKnown, id) then return true end
    if IsPlayerSpell and call(IsPlayerSpell, id) then return true end
    if IsSpellKnown and call(IsSpellKnown, id) then return true end
    return false
end
PB.Known = known
function PB.Knows(t)
    local d = PB.TYPES[t]
    if not d then return false end
    for _, r in ipairs(d.ranks) do if known(r[1]) then return true end end
    return false
end
-- 给 lv 级的目标能上的最高一级（自己学会的里挑；cap = 这个人报过「等级太低」的那一级，只挑比它低的）
local function pickRank(list, lv, cap)
    for i = #list, 1, -1 do
        local id, need = list[i][1], list[i][2]
        if known(id) and (not lv or lv <= 0 or lv >= need - PB.LOWLV) and (not cap or need < cap) then return id, need end
    end
    return nil
end
function PB.SpellFor(t, lv, cap)
    local d = PB.TYPES[t]
    if not d then return nil end
    return (pickRank(d.ranks, lv, cap))
end
function PB.GreaterFor(t, lv, cap)
    local d = PB.TYPES[t]
    if not d then return nil end
    return (pickRank(d.greater, lv, cap))
end
local function hasSymbol()
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not f then return true end
    local n = call(f, PB.SYMBOL)
    return (tonumber(n) or 0) > 0
end
PB.HasSymbol = hasSymbol

-- ---------- 读光环 ----------
local function auraAt(u, i)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local a = call(C_UnitAuras.GetAuraDataByIndex, u, i, "HELPFUL")
        if type(a) ~= "table" then return nil end
        return a.name or "", a.expirationTime, a.sourceUnit, a.spellId
    end
    local f = UnitAura or UnitBuff
    if not f then return nil end
    local ok, name, _, _, _, _, exp, src, _, _, sid = pcall(f, u, i, UnitAura and "HELPFUL" or nil)
    if not ok or not name then return nil end
    return name, exp, src, sid
end
-- → { [t] = { mine = 剩余秒数或 nil, other = true 或 nil } }
function PB.Auras(u)
    local out = {}
    for i = 1, 40 do
        local name, exp, src, sid = auraAt(u, i)
        if not name then break end
        local info = sid and PB.BY_ID[sid]
        local t = info and info.t or PB.BY_NAME[name]
        if t then
            local o = out[t] or {}
            out[t] = o
            local left = (tonumber(exp) or 0) > 0 and (exp - now()) or 1e9
            if src and isMe(src) then o.mine = math.max(o.mine or 0, left) else o.other = true end
        end
    end
    return out
end

-- ---------- 多个圣骑士：插件消息同步 ----------
PB.peers = {}   -- [短名字] = { at, plan = { [职业] = 类型 } }
local function rosterNames()
    local t = {}
    for _, u in ipairs(PB.Roster()) do local n = short(call(UnitName, u)); if n then t[n] = u end end
    return t
end
-- 名字排在我前面、还在队里、装了插件的圣骑士已经占了的：{ [职业] = { [类型] = 名字 } }
function PB.Taken()
    local me = short(call(UnitName, "player")) or ""
    local here = rosterNames()
    local taken = {}
    for n, p in pairs(PB.peers) do
        if n ~= me and here[n] and n < me and type(p.plan) == "table" then
            for c, t in pairs(p.plan) do
                taken[c] = taken[c] or {}
                taken[c][t] = taken[c][t] or n
            end
        end
    end
    return taken
end
-- 这个职业的候选（首选 → 王者 → 其余有用的），只留自己会的
function PB.Candidates(c)
    local out, seen = {}, {}
    local useful = PB.USEFUL[c] or HYBRID
    local function add(t) if t and not seen[t] and useful[t] and PB.Knows(t) then seen[t] = true; out[#out + 1] = t end end
    local first = PB.ClassPref(c)
    if not first then return out end   -- 玩家设了「不加」
    add(first); add("K")
    for _, t in ipairs(PB.ORDER) do add(t) end
    return out
end
-- 我的分配：{ [职业] = 类型 }（被名字靠前的圣骑士占了就换替补；都被占 = 不在表里）
function PB.Plan(taken)
    taken = taken or PB.Taken()
    local plan = {}
    for _, c in ipairs(PB.CLASSES) do
        for _, t in ipairs(PB.Candidates(c)) do
            if not (taken[c] and taken[c][t]) then plan[c] = t; break end
        end
    end
    return plan
end
local function planText(plan)
    local parts = {}
    for _, c in ipairs(PB.CLASSES) do if plan[c] then parts[#parts + 1] = c .. ":" .. plan[c] end end
    return table.concat(parts, ",")
end
PB.PlanText = planText
function PB.ParsePlan(s)
    local plan = {}
    for c, t in (s or ""):gmatch("([A-Z]+):([MWK])") do plan[c] = t end
    return plan
end
local lastSent, lastText = 0, nil
function PB.Broadcast(force)
    if not (PB.IsPaladin() and inGroup() and C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
    local text = planText(PB.Plan())
    if not force and text == lastText and now() - lastSent < 60 then return false end
    lastSent, lastText = now(), text
    call(C_ChatInfo.SendAddonMessage, PB.PREFIX, "S\t1\t" .. text, inRaid() and "RAID" or "PARTY")
    return true
end
function PB.OnAddonMsg(msg, sender)
    local n = short(sender)
    if not n or n == short(call(UnitName, "player")) then return end
    local kind, rest = (msg or ""):match("^(%u)\t(.*)$")
    if kind == "S" then
        local body = rest:match("^%d+\t(.*)$") or ""
        local before = PB.peers[n] and planText(PB.peers[n].plan) or nil
        PB.peers[n] = { at = now(), plan = PB.ParsePlan(body) }
        if before == nil then PB.Broadcast(true) end                  -- 新来的圣骑士：把我的也告诉他
        if before ~= planText(PB.peers[n].plan) then PB.Refresh(); PB.Broadcast() end
    elseif kind == "Q" then
        PB.Broadcast(true)
    end
end

-- ---------- 队伍 ----------
function PB.Roster()
    local out = {}
    if inRaid() then
        local n = call(GetNumGroupMembers) or 0
        for i = 1, n do out[#out + 1] = "raid" .. i end
    else
        out[1] = "player"
        if inGroup() then for i = 1, 4 do if exists("party" .. i) then out[#out + 1] = "party" .. i end end end
    end
    return out
end
local function inRange(u, id)
    if isMe(u) then return true end
    if UnitIsVisible and not call(UnitIsVisible, u) then return false end
    -- 11-14 用户「点了没反应」（队友就在旁边却显示范围外）：按法术 ID 问距离，ID 和法术书里那一级对不上时可能一直回 false →
    --   改成几种问法任何一种说「在范围内」就算在（判错了顶多施法报「距离太远」，那时 OnError 拉黑 8 秒，不会卡死）
    local said = nil
    if C_Spell and C_Spell.IsSpellInRange then
        local r = call(C_Spell.IsSpellInRange, id, u)
        if r == true or r == 1 then return true end
        if r ~= nil then said = false end
    end
    if IsSpellInRange and GetSpellInfo then
        local n = call(GetSpellInfo, id)
        local r = n and call(IsSpellInRange, n, u)
        if r == 1 or r == true then return true end
        if r ~= nil then said = false end
    end
    if UnitInRange then
        local r, checked = call(UnitInRange, u)
        if checked and r then return true end
        if checked then said = false end
    end
    return said ~= false
end

PB.inflight = nil     -- { guid, cls, id, at, greater }
PB.blocked = {}       -- [guid] = 到这个时间之前不挑他
PB.tooLow = {}        -- [guid] = { lv = 报过「目标等级太低」的那一级的学习等级, at = 当时目标等级 }（目标升级后作废）
local function capFor(guid, lv)
    local x = PB.tooLow[guid]
    if type(x) == "table" and (lv or 0) <= (x.at or 0) then return x.lv end
    return nil
end

-- 每个人现在怎样：{ unit, guid, name, cls, lv, t, id, st, left, alt }
--   st：need 缺 · soon 快到期 · ok 有了 · dead · offline · far 太远/看不见 · lowlv 等级太低 · covered 别人已加 · none 不加 · nocast 不会 · blocked 刚报错 · flying 刚施放
function PB.Eval()
    local list = {}
    local plan, taken = PB.Plan(), PB.Taken()
    local soon, t0 = PB.Soon(), now()
    for _, u in ipairs(PB.Roster()) do
        local guid = call(UnitGUID, u)
        if guid then
            local name = call(UnitName, u)
            local cls = classOf(u)
            local e = { unit = u, guid = guid, name = name, cls = cls, lv = tonumber(call(UnitLevel, u)) or 0 }
            list[#list + 1] = e
            if UnitIsConnected and not call(UnitIsConnected, u) then e.st = "offline"
            elseif UnitIsDeadOrGhost and call(UnitIsDeadOrGhost, u) then e.st = "dead"
            else
                local au = PB.Auras(u)
                local who = PB.WhoPref(short(name))
                local t
                if who == "0" then t = nil
                elseif who and PB.TYPES[who] then t = who
                else t = plan[cls] end
                if t and au[t] and au[t].other and not au[t].mine then
                    -- 没装插件的圣骑士已经加了同类：换替补（单独指定的人不换，跳过）
                    local alt
                    if not who then
                        for _, c in ipairs(PB.Candidates(cls)) do
                            if c ~= t and not (taken[cls] and taken[cls][c]) and not (au[c] and au[c].other and not au[c].mine) then alt = c; break end
                        end
                    end
                    if alt then e.alt = t; t = alt else e.st = "covered"; e.t = t end
                end
                if not e.st then
                    e.t = t
                    if not t then e.st = "none"
                    elseif not PB.Knows(t) then e.st = "nocast"
                    else
                        e.id = PB.SpellFor(t, e.lv, capFor(guid, e.lv))
                        local mine = au[t] and au[t].mine
                        e.left = mine
                        if not e.id then e.st = "lowlv"
                        elseif mine and mine >= soon then e.st = "ok"
                        else
                            e.st = mine and "soon" or "need"
                            local inf = PB.inflight
                            if inf and t0 - inf.at < PB.INFLIGHT and (inf.guid == guid or (inf.greater and inf.cls == cls and inf.t == t)) then e.st = "flying"
                            elseif (PB.blocked[guid] or 0) > t0 then e.st = "blocked"
                            elseif not inRange(u, e.id) then e.st = "far" end
                        end
                    end
                end
            end
        end
    end
    return list
end

-- 强效：这个职业在队里的人 ≥ 2 个都要同一种、每个人分到的都是它、有王者印记、强效那一级对最低等级的也能上
function PB.GreaterPick(e, list)
    if not (PB.GreaterOn() and inGroup() and e and e.t and e.cls) then return nil end
    local want, minLv = 0, e.lv
    for _, x in ipairs(list) do
        if x.cls == e.cls and x.st ~= "offline" and x.st ~= "dead" then
            if x.t ~= e.t then return nil end
            if x.st == "need" or x.st == "soon" or x.st == "far" or x.st == "blocked" then want = want + 1 end
            if x.lv and x.lv > 0 and (not minLv or minLv <= 0 or x.lv < minLv) then minLv = x.lv end
        end
    end
    if want < PB.GREATER_MIN or not hasSymbol() then return nil end
    return PB.GreaterFor(e.t, minLv, capFor(e.guid, e.lv))
end

-- 下一个：先挑缺的（队伍顺序），再挑快到期的（剩得最少的先）→ { e, id, greater, missing = 还缺几个 }，没有 = nil, missing
function PB.Next(list)
    list = list or PB.Eval()
    local first, soonest, missing = nil, nil, 0
    for _, e in ipairs(list) do
        if e.st == "need" or e.st == "soon" or e.st == "far" or e.st == "blocked" or e.st == "flying" then missing = missing + 1 end
        if e.st == "need" and not first then first = e end
        if e.st == "soon" and (not soonest or (e.left or 0) < (soonest.left or 0)) then soonest = e end
    end
    local e = first or soonest
    if not e then return nil, missing end
    local g = PB.GreaterPick(e, list)
    return { e = e, id = g or e.id, greater = g ~= nil, missing = missing }, missing
end

-- ---------- 安全按钮 ----------
PB.buttons = {}
PB.attrWrites = 0
local function setAttrs(b, typ, spell, unit)
    if combat() then return false end   -- ⛔ 战斗中不改属性（进战斗时状态驱动已清掉 type 并隐藏）
    local cur = rawget(b, "_pbAttr")
    if cur and cur.type == typ and cur.spell == spell and cur.unit == unit then return true end
    b:SetAttribute("type", typ)
    b:SetAttribute("spell", spell)
    b:SetAttribute("unit", unit)
    rawset(b, "_pbAttr", { type = typ, spell = spell, unit = unit })
    PB.attrWrites = PB.attrWrites + 1
    return true
end
PB.SetAttrs = setAttrs

function PB.Apply(nx)
    if combat() then return false end
    for _, b in ipairs(PB.buttons) do
        if nx then setAttrs(b, "spell", nx.id, nx.e.unit) else setAttrs(b, nil, nil, nil) end
        rawset(b, "_pbNext", nx)
    end
    return true
end

local function secureBtn(name, parent, w, h)
    local b = CreateFrame("Button", name, parent or UIParent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    b:SetSize(w, h)
    if b.RegisterForClicks then b:RegisterForClicks("AnyDown") end
    if RegisterStateDriver and b.SetAttribute then
        -- 进战斗：受保护代码里清掉 type 并隐藏（插件代码战斗中不碰属性）；脱战后插件代码 PB.OnRegen 再设、再显示
        b:SetAttribute("_onstate-gipbcombat", [[ if newstate == "1" then self:SetAttribute("type", nil); self:Hide() end ]])
        RegisterStateDriver(b, "gipbcombat", "[combat] 1; 0")
    end
    if ns.SkinButton then ns.SkinButton(b) end
    b:SetScript("PreClick", function(self)
        if combat() then return end
        PB.Refresh()   -- 脱战时现算一次下一个，属性对准他
    end)
    b:SetScript("PostClick", function(self)
        if combat() then return end   -- 战斗中按键（绑键点到隐藏的按钮）：type 已被状态驱动清空，什么都没放
        local nx = rawget(self, "_pbNext")
        if not nx then
            local why = PB.WhyText()
            if why ~= "" then ns.Print(L("一键祝福：这下没放 —— ", "Blessings: nothing cast - ") .. why)
            else ns.Print(L("一键祝福：队伍里的人都有你的祝福了（或者不需要）", "Blessings: everyone has your blessing")) end
            return
        end
        PB.inflight = { guid = nx.e.guid, cls = nx.e.cls, t = nx.e.t, id = nx.id, lv = nx.e.lv, at = now(), greater = nx.greater }
        if C_Timer and C_Timer.After then C_Timer.After(0.3, PB.Refresh) end
    end)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L("一键祝福", "One-click blessings"), 1, 0.82, 0)
        GameTooltip:AddLine(PB.NextText(), 1, 1, 1, true)
        local why = PB.WhyText()
        if why ~= "" then GameTooltip:AddLine(why, 1, 0.6, 0.4, true) end
        GameTooltip:AddLine(L("每点一下给一个人（暴雪规定每次施法都要按一下）；战斗中暂停", "One player per click (each cast needs a key press); paused in combat"), 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    PB.buttons[#PB.buttons + 1] = b
    return b
end

-- ---------- 文字 ----------
local function clock(sec)
    if not sec or sec >= 1e8 then return "∞" end
    sec = math.max(0, math.floor(sec))
    if sec >= 3600 then return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60) end
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end
PB.Clock = clock
-- 11-14 用户截图「还缺 1 个，都在范围外 / 刚施放」「点了没反应」：缺的人点不了时写清楚是谁、为什么（太远 / 刚施放 / 刚报错）
local WHY = { far = { "太远或看不见", "out of range / not visible" }, flying = { "刚施放，等生效", "just cast" },
    blocked = { "刚报视线 / 距离错误，8 秒后再试", "line of sight / range error, retry in 8s" } }
function PB.WhyText(list)
    list = list or PB.Eval()
    local out = {}
    for _, e in ipairs(list) do
        local w = WHY[e.st]
        if w then out[#out + 1] = (short(e.name) or "?") .. L("（", " (") .. L(w[1], w[2]) .. L("）", ")") end
    end
    return table.concat(out, L("、", ", "))
end
-- 11-14 用户截图「优化」：4 个人的原因全列出来把悬浮框撑爆 → 悬浮框 / 页上只写按原因汇总的一句（1 个人才写名字），明细放鼠标提示
local WHY_SHORT = { far = { "太远", "out of range" }, flying = { "刚施放", "just cast" }, blocked = { "刚报距离 / 视线错误，8 秒后再试", "LoS / range error, retry in 8s" } }
function PB.WhyShort(list)
    list = list or PB.Eval()
    local n, names, order = {}, {}, {}
    for _, e in ipairs(list) do
        if WHY_SHORT[e.st] then
            if not n[e.st] then n[e.st] = 0; names[e.st] = {}; order[#order + 1] = e.st end
            n[e.st] = n[e.st] + 1
            table.insert(names[e.st], short(e.name) or "?")
        end
    end
    local out = {}
    for _, st in ipairs(order) do
        local w = L(WHY_SHORT[st][1], WHY_SHORT[st][2])
        if n[st] == 1 then out[#out + 1] = names[st][1] .. " " .. w
        else out[#out + 1] = string.format(L("%d 人%s", "%d %s"), n[st], w) end
    end
    return table.concat(out, L("；", "; "))
end
function PB.NextText(nx, missing)
    if nx == nil and missing == nil then nx, missing = PB.Next() end
    -- 11-15 用户截图「能看出来给谁加了，为什么加不」：战斗中写清原因 + 脱战后先给谁（战斗前最后算好的那个）
    if combat() then
        local l = PB.last
        local head = L("战斗中暂停（游戏不让插件换目标）","Paused in combat (addons can't retarget in combat)")
        if l and l.e then
            local who = l.greater and (PB.ClassName(l.e.cls) .. L("（整职业）", " (class)")) or (short(l.e.name) or "?")
            return head .. "\n" .. string.format(L("脱战后先给 %s 加%s", "After combat: %s - %s"), who, PB.TypeName(l.e.t, l.greater))
        end
        return head .. "\n" .. L("脱战后继续", "Resumes after combat")
    end
    if not nx then
        if (missing or 0) > 0 then
            local why = PB.WhyShort()
            return string.format(L("还缺 %d 个，现在点不了：", "%d missing, none castable now: "), missing) .. (why ~= "" and why or L("范围外 / 刚施放", "out of range / just cast"))
        end
        return L("都有了", "All blessed")
    end
    local who = nx.greater and (PB.ClassName(nx.e.cls) .. L("（整职业）", " (class)")) or (short(nx.e.name) or "?")
    return string.format(L("下一个：%s · %s　还缺 %d 个", "Next: %s - %s   %d missing"), who, PB.TypeName(nx.e.t, nx.greater), missing or nx.missing or 0)
end
local ST_TEXT = {
    need = { "|cffff5555缺|r", "|cffff5555missing|r" }, soon = { "|cffffd100快到期 %s|r", "|cffffd100expiring %s|r" },
    ok = { "|cff33ff99剩 %s|r", "|cff33ff99%s left|r" }, dead = { "|cff888888死亡，跳过|r", "|cff888888dead|r" },
    offline = { "|cff888888离线，跳过|r", "|cff888888offline|r" }, far = { "|cffaaaaaa太远 / 看不见|r", "|cffaaaaaaout of range|r" },
    lowlv = { "|cffaaaaaa等级太低，没有能上的一级|r", "|cffaaaaaatoo low level|r" },
    covered = { "|cffaaaaaa别的圣骑士已加，替补都被占|r", "|cffaaaaaacovered by another paladin|r" },
    none = { "|cff888888不加|r", "|cff888888none|r" }, nocast = { "|cff888888你还没学|r", "|cff888888not learned|r" },
    blocked = { "|cffaaaaaa刚报视线 / 距离，稍后再试|r", "|cffaaaaaaline of sight / range - retry soon|r" },
    flying = { "|cffaaaaaa施放中…|r", "|cffaaaaaacasting...|r" },
}
function PB.StatusText(e)
    local s = ST_TEXT[e.st] or { e.st or "?", e.st or "?" }
    local txt = L(s[1], s[2])
    if e.st == "soon" or e.st == "ok" then txt = string.format(txt, clock(e.left)) end
    return txt
end

-- ---------- 悬浮框 ----------
local float
local function savePos()
    if not float then return end
    local p, _, _, x, y = float:GetPoint()
    PB.DB().pos = { p or "CENTER", x or 0, y or 0 }
end
-- 11-14 用户截图：「下一个：欧皇萨 · 智慧祝福　还缺 3 个」折成两行压到按钮上 → 框加宽 + 按文字实际行数撑高（框里有安全按钮：只在脱战时改尺寸）
function PB.SetFloatText(text)
    if not (float and float.line) then return end
    float.line:SetText(text)
    if combat() then return end
    local h = tonumber(float.line.GetStringHeight and float.line:GetStringHeight()) or 14
    if h < 12 then h = 14 end
    float:SetHeight(math.floor(7 + h + 6 + 26 + 7 + 0.5))
end
function PB.BuildFloat()
    if float then return float end
    if combat() then return nil end
    local f = CreateFrame("Frame", "GearInsightForeverPallyFloat", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(260, 62); f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(true)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.05, 0.05, 0.07, 0.88)
    end
    local pos = PB.DB().pos
    if type(pos) == "table" then f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else f:SetPoint("CENTER", UIParent, "CENTER", -260, -120) end
    f:SetMovable(true); f:EnableMouse(true)
    if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
    f:SetScript("OnDragStart", function(self) if not combat() then self:StartMoving() end end)   -- 里面有安全按钮：战斗中不能挪
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos() end)
    f.line = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.line:SetPoint("TOPLEFT", 8, -7); f.line:SetPoint("TOPRIGHT", -8, -7); f.line:SetJustifyH("LEFT")
    if f.line.SetWordWrap then f.line:SetWordWrap(true) end
    if f.line.SetMaxLines then f.line:SetMaxLines(2) end   -- 最多两行（战斗中框不能改高度，再长就截断，明细看鼠标提示）
    local b = secureBtn(PB.BTN, f, 244, 26)
    b:SetPoint("BOTTOM", f, "BOTTOM", 0, 7)
    b:SetText(L("加祝福", "Bless"))
    f.btn = b
    f:Hide()
    float = f
    PB.float = f
    return f
end
function PB.FloatWanted() return PB.IsPaladin() and PB.FloatOn() and (inGroup() or PB.floatPreview == true) end
function PB.ResetPos()
    if combat() then return false end
    PB.DB().pos = nil
    if float then float:ClearAllPoints(); float:SetPoint("CENTER", UIParent, "CENTER", -260, -120) end
    return true
end

-- ---------- 页面 ----------
local page
-- 11-14 用户截图「为啥是空的」：页上职业格 / 队伍 / 状态全空。页可能被建过不止一次（合并包里占位页 + 真页），
--   原来只画最后建的那个 page，看得见的那份就是空的 → 记下所有建过的页，画「正显示着」的那份；画的时候出错打一次到聊天框（原来被 pcall 吞掉）
local pages = {}
local function curPage()
    for i = #pages, 1, -1 do
        local q = pages[i]
        if q and q.IsVisible and q:IsVisible() then return q end
    end
    return page
end
PB._curPage = curPage
local ROWS = 10
local function cycle(list, cur)
    for i, v in ipairs(list) do if v == cur then return list[i % #list + 1] end end
    return list[1]
end
local function prefChoices(c)
    local out = { false }   -- false = 默认（自动）
    for _, t in ipairs(PB.ORDER) do if (PB.USEFUL[c] or HYBRID)[t] then out[#out + 1] = t end end
    out[#out + 1] = "0"
    return out
end
function PB.CycleClass(c)
    local by = PB.DB().by
    local cur = type(by) == "table" and by[c] or false
    local nxt = cycle(prefChoices(c), cur or false)
    PB.SetClassPref(c, nxt or nil)
    return nxt
end
function PB.CycleWho(name)
    name = short(name)
    if not name then return end
    local nxt = cycle({ false, "M", "W", "K", "0" }, PB.WhoPref(name) or false)
    PB.SetWhoPref(name, nxt or nil)
    return nxt
end

local function classLabel(c, plan, taken)
    local col = ns.CLASS_COLOR and ns.CLASS_COLOR[PB.CLASS_EN[c]] or "ffffff"
    local by = PB.DB().by
    local set = type(by) == "table" and by[c] or nil
    local t = plan[c]
    local txt = "|cff" .. col .. PB.ClassName(c) .. "|r：" .. (t and PB.TypeName(t) or ("|cff888888" .. L("不加", "none") .. "|r"))
    if not set then txt = txt .. "|cff888888" .. L("（默认）", " (default)") .. "|r" end
    local pref = PB.Candidates(c)[1]
    if pref and t ~= pref and taken[c] and taken[c][pref] then
        txt = txt .. "\n|cffaaaaaa" .. string.format(L("%s 已给%s", "%s gives %s"), taken[c][pref], PB.TypeName(pref)) .. "|r"
    end
    return txt
end

local paintErr
function PB.Paint()
    local p = curPage()
    if not (p and p.IsShown and p:IsShown()) then return end
    local ok, err = pcall(PB.PaintPage, p)
    if not ok and not paintErr then
        paintErr = true
        ns.Print(L("一键祝福页面出错（请截图给开发者）：", "Blessings page error: ") .. tostring(err))
    end
end
function PB.PaintPage(p)
    local list = PB.Eval()
    local nx, missing = PB.Next(list)
    p.status:SetText(PB.NextText(nx, missing))
    local plan, taken = PB.Plan(), PB.Taken()
    for i, c in ipairs(PB.CLASSES) do p.cls[i]:SetText(classLabel(c, plan, taken)) end
    table.sort(list, function(a, b)
        local ra = (a.st == "need" and 1) or (a.st == "soon" and 2) or (a.st == "ok" and 4) or 3
        local rb = (b.st == "need" and 1) or (b.st == "soon" and 2) or (b.st == "ok" and 4) or 3
        if ra ~= rb then return ra < rb end
        return (a.name or "") < (b.name or "")
    end)
    for i = 1, ROWS do
        local r, e = p.rows[i], list[i]
        if e then
            local col = ns.CLASS_COLOR and ns.CLASS_COLOR[PB.CLASS_EN[e.cls or ""] or ""] or "ffffff"
            local who = PB.WhoPref(short(e.name))
            r.name:SetText("|cff" .. col .. (short(e.name) or "?") .. "|r" .. (e.lv > 0 and (" |cff888888" .. e.lv .. "|r") or "")
                .. (who and ("|cffffd100" .. L(" *", " *") .. "|r") or ""))
            r.bless:SetText(e.t and PB.TypeName(e.t) or "")
            r.st:SetText(PB.StatusText(e))
            rawset(r, "pbName", short(e.name))
            r:Show()
        else
            r:Hide()
        end
    end
    p.more:SetText(#list > ROWS and string.format(L("还有 %d 人没列出（都已排在后面：有祝福 / 跳过）", "%d more not shown"), #list - ROWS) or "")
    local peers = {}
    local here = rosterNames()
    for n in pairs(PB.peers) do if here[n] then peers[#peers + 1] = n end end
    table.sort(peers)
    p.peers:SetText(#peers > 0 and (L("同队装了插件的圣骑士：", "Other paladins with this addon: ") .. table.concat(peers, L("、", ", "))
        .. L("（名字靠前的先挑，冲突的职业自动换替补）", " (alphabetical priority, conflicts switch to a backup)"))
        or L("同队没有别的装了插件的圣骑士；没装插件的圣骑士已经加过的同类祝福会自动让开", "No other paladin with this addon; blessings already given by others are left alone"))
    local keys = PB.BindKeys()
    p.bind:SetText(#keys > 0 and string.format(L("快捷键：%s", "Key: %s"), table.concat(keys, " / ")) or L("设置快捷键", "Set a key"))
    if p.floatBtn then p.floatBtn:SetText(PB.FloatOn() and L("悬浮按钮：开", "Floating: on") or L("悬浮按钮：关", "Floating: off")) end
end

-- 绑键：只绑一个键（SetBindingClick 到悬浮框的按钮）
local BIND_CMD = "CLICK " .. PB.BTN .. ":LeftButton"
function PB.BindKeys()
    local out = {}
    if GetBindingKey then
        local k1, k2 = call(GetBindingKey, BIND_CMD)
        if k1 then out[#out + 1] = k1 end
        if k2 then out[#out + 1] = k2 end
    end
    return out
end
-- → true / nil, 原因（combat / api / taken, 原来的功能）
function PB.Bind(key, force)
    if combat() then return nil, "combat" end
    if not (SetBindingClick and SetBinding) then return nil, "api" end
    PB.BuildFloat()
    if key then
        local act = GetBindingAction and call(GetBindingAction, key)
        if act and act ~= "" and act ~= BIND_CMD and not force then return nil, "taken", act end
    end
    for _, k in ipairs(PB.BindKeys()) do call(SetBinding, k) end
    if key then call(SetBindingClick, key, PB.BTN, "LeftButton") end
    if SaveBindings then call(SaveBindings, (GetCurrentBindingSet and call(GetCurrentBindingSet)) or 2) end
    return true
end
local capture, pendingKey
local function withMods(k)
    local m = ""
    if IsAltKeyDown and IsAltKeyDown() then m = m .. "ALT-" end
    if IsControlKeyDown and IsControlKeyDown() then m = m .. "CTRL-" end
    if IsShiftKeyDown and IsShiftKeyDown() then m = m .. "SHIFT-" end
    return m .. k
end
local function finish(key)
    if capture then capture:Hide() end
    if key == nil then pendingKey = nil; return end
    local ok, why, act = PB.Bind(key or nil, key ~= false and pendingKey == key)
    if ok then
        pendingKey = nil
        ns.Print(key and string.format(L("一键祝福快捷键：%s（按一下给下一个人加祝福）", "Blessing key: %s"), key) or L("一键祝福快捷键已清除", "Blessing key cleared"))
    elseif why == "taken" then
        pendingKey = key
        ns.Print(string.format(L("%s 现在是「%s」。要顶替就再点「设置快捷键」按一次同一个键", "%s is bound to %s. Set it again with the same key to replace"), key, _G["BINDING_NAME_" .. tostring(act)] or tostring(act)))
    elseif why == "combat" then
        ns.Print(L("战斗中不能改键位，脱战后再设", "Can't change keys in combat"))
    end
    PB.Paint()
end
function PB.BeginBind(parent)
    if combat() then ns.Print(L("战斗中不能改键位，脱战后再设", "Can't change keys in combat")); return end
    if not capture then
        local c = CreateFrame("Frame", nil, parent or UIParent)
        c:SetAllPoints(); c:EnableKeyboard(true); c:EnableMouse(true)
        pcall(c.SetPropagateKeyboardInput, c, false)
        c:SetFrameStrata("DIALOG")
        local dim = c:CreateTexture(nil, "BACKGROUND"); dim:SetAllPoints(); dim:SetColorTexture(0, 0, 0, 0.7)
        c.t = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); c.t:SetPoint("CENTER", 0, 20)
        c.t:SetText(L("给「一键祝福」按一个键…", "Press a key for One-click blessings..."))
        c.t2 = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); c.t2:SetPoint("TOP", c.t, "BOTTOM", 0, -12)
        c.t2:SetText(L("支持 Shift / Ctrl / Alt 组合、鼠标侧键\nEsc 取消 · Backspace 清除", "Shift / Ctrl / Alt and mouse buttons work\nEsc cancels - Backspace clears"))
        c:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then finish(nil)
            elseif key == "BACKSPACE" or key == "DELETE" then finish(false)
            elseif key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then
            else finish(withMods(key)) end
        end)
        c:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" or button == "RightButton" then return end
            local MOUSE_KEY = { MIDDLEBUTTON = "BUTTON3", BUTTON4 = "BUTTON4", BUTTON5 = "BUTTON5" }
            local kb = string.upper(button or "")
            finish(withMods(MOUSE_KEY[kb] or kb))
        end)
        capture = c
    end
    capture:Show()
end
PB._finishBind = finish   -- 测试用

local function build(p)
    page = p
    pages[#pages + 1] = p
    local y0 = ns.PageHeader(p, L("一键祝福", "Blessings"), L("圣骑士 · 每点一下给下一个缺祝福 / 快到期的队友加上分给他的祝福", "Paladin - each click blesses the next player who needs it"))
    y0 = y0 or -44
    p.slot = CreateFrame("Frame", nil, p)
    p.slot:SetSize(200, 30); p.slot:SetPoint("TOPLEFT", 12, y0)
    p.status = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.status:SetPoint("LEFT", p.slot, "RIGHT", 12, 0); p.status:SetPoint("RIGHT", p, "RIGHT", -12, 0); p.status:SetJustifyH("LEFT")
    p.bind = ns.Button(p, L("设置快捷键", "Set a key"), 150, 22, function() PB.BeginBind(p) end)
    p.bind:SetPoint("TOPLEFT", 12, y0 - 38)
    p.floatBtn = ns.Button(p, "", 130, 22, function() PB.SetFloat(not PB.FloatOn()); if PB.FloatOn() and not inGroup() then PB.floatPreview = true; PB.Refresh() end; PB.Paint() end)
    p.floatBtn:SetPoint("LEFT", p.bind, "RIGHT", 8, 0)
    local reset = ns.Button(p, L("恢复默认分配", "Reset assignments"), 120, 22, function() PB.ResetAssign(); PB.Paint() end)
    reset:SetPoint("LEFT", p.floatBtn, "RIGHT", 8, 0)
    local h1 = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h1:SetPoint("TOPLEFT", 14, y0 - 72)
    h1:SetText(L("按职业分配（点一下换：默认 → 力量 / 智慧 / 王者 → 不加）", "By class (click to cycle)"))
    p.cls = {}
    for i, c in ipairs(PB.CLASSES) do
        local b = CreateFrame("Button", nil, p)
        b:SetSize(210, 30)
        b:SetPoint("TOPLEFT", 12 + ((i - 1) % 3) * 216, y0 - 92 - math.floor((i - 1) / 3) * 32)
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.10)
        local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.04)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", 6, 0); fs:SetPoint("RIGHT", -4, 0); fs:SetJustifyH("LEFT")
        b:SetScript("OnClick", function() PB.CycleClass(c); PB.Paint() end)
        p.cls[i] = fs
    end
    local h2 = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h2:SetPoint("TOPLEFT", 14, y0 - 196)
    h2:SetText(L("队伍（右键名字：单独给这个人指定，带 * 的是单独指定过的）", "Group (right-click a name to set a per-player blessing)"))
    p.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, p)
        r:SetHeight(18)
        r:SetPoint("TOPLEFT", 12, y0 - 214 - (i - 1) * 19); r:SetPoint("RIGHT", p, "RIGHT", -12, 0)
        if r.RegisterForClicks then r:RegisterForClicks("RightButtonUp") end
        local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.08)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.name:SetPoint("LEFT", 4, 0); r.name:SetWidth(170); r.name:SetJustifyH("LEFT")
        r.bless = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.bless:SetPoint("LEFT", 180, 0); r.bless:SetWidth(120); r.bless:SetJustifyH("LEFT")
        r.st = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.st:SetPoint("LEFT", 306, 0); r.st:SetPoint("RIGHT", -4, 0); r.st:SetJustifyH("LEFT")
        r:SetScript("OnClick", function(self)
            local n = rawget(self, "pbName")
            if not n then return end
            local v = PB.CycleWho(n)
            ns.Print(string.format(L("一键祝福：%s → %s", "Blessings: %s -> %s"), n, v == false and L("跟职业走", "follow class") or PB.TypeName(v ~= "0" and v or nil)))
            PB.Paint()
        end)
        r:Hide()
        p.rows[i] = r
    end
    p.more = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); p.more:SetPoint("TOPLEFT", 14, y0 - 214 - ROWS * 19 - 2)
    p.peers = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.peers:SetPoint("TOPLEFT", 14, y0 - 214 - ROWS * 19 - 18); p.peers:SetPoint("RIGHT", p, "RIGHT", -14, 0); p.peers:SetJustifyH("LEFT")
    PB.AttachPageBtn()
    if p.HookScript then p:HookScript("OnShow", function() PB.Refresh() end) end
    PB.Paint()
end

-- 页上的安全按钮：脱战时建好挂到页上（页在战斗中第一次打开 → 脱战后再挂）
function PB.AttachPageBtn()
    page = curPage() or page
    if not page or combat() then return end
    if not PB.pageBtn then
        PB.pageBtn = secureBtn("GearInsightForeverPallyBlessPageBtn", page.slot, 200, 30)
        PB.pageBtn:SetText(L("加下一个祝福", "Bless next"))
    end
    PB.pageBtn:SetParent(page.slot)
    PB.pageBtn:ClearAllPoints(); PB.pageBtn:SetAllPoints(page.slot)
    PB.pageBtn:Show()
end

-- ---------- 刷新（每秒 / 事件）----------
function PB.Refresh()
    if not (ns.db and PB.IsPaladin()) then return nil end
    if combat() then
        -- 战斗中：属性改不了（状态驱动已清空并隐藏按钮），也不必每 0.2 秒扫一遍团队光环 —— 只改一行字，脱战（PLAYER_REGEN_ENABLED）再算
        PB.SetFloatText(PB.NextText(nil, 0))
        local cp = curPage(); if cp and cp.status and cp:IsShown() then cp.status:SetText(PB.NextText(nil, 0)) end
        return nil
    end
    local nx, missing = PB.Next()
    PB.last = nx
    PB.Apply(nx)
    local want = PB.FloatWanted()
    if want and not float and not combat() then PB.BuildFloat() end
    if float then
        if not combat() then
            if want then float:Show() else float:Hide() end
            if want and float.btn then float.btn:Show() end
        end
        PB.SetFloatText(PB.NextText(nx, missing))
    end
    PB.Paint()
    return nx, missing
end
function PB.OnRegen()
    PB.AttachPageBtn()
    PB.Refresh()
end

-- 施法结果：报错的时候刚点过谁
local FAIL_BLOCK = { "SPELL_FAILED_LINE_OF_SIGHT", "SPELL_FAILED_OUT_OF_RANGE", "ERR_SPELL_OUT_OF_RANGE", "SPELL_FAILED_UNIT_NOT_INFRONT" }
-- 11-14 用户截图：4 个人全是「刚报视线 / 距离错误」—— 打怪时自己普攻 / 别的技能报的「距离太远」「不在视野中」也算到了祝福头上。
--   改成：只有游戏同时报了「我的祝福施法失败」（UNIT_SPELLCAST_FAILED，法术是祝福）才认这条错误；两个事件谁先到都行（1 秒内配对）
PB.pendErr, PB.castFailAt = nil, -1e9
function PB.OnCastFailed(spellID)
    local inf = PB.inflight
    if not inf or not PB.BY_ID[tonumber(spellID) or -1] then return nil end
    PB.castFailAt = now()
    local pe = PB.pendErr
    if pe and now() - pe.at <= 1 then PB.pendErr = nil; return PB.ResolveError(pe.msg) end
    return nil
end
function PB.OnError(msg)
    if type(msg) ~= "string" or not PB.inflight then return nil end
    if now() - (PB.castFailAt or -1e9) <= 1 then PB.castFailAt = -1e9; return PB.ResolveError(msg) end
    PB.pendErr = { msg = msg, at = now() }
    return nil
end
function PB.ResolveError(msg)
    local inf = PB.inflight
    if not (inf and type(msg) == "string") or now() - inf.at > 2 then return nil end
    if _G.SPELL_FAILED_LOWLEVEL and msg == _G.SPELL_FAILED_LOWLEVEL then
        local info = PB.BY_ID[inf.id]
        if info then PB.tooLow[inf.guid] = { lv = info.lv, at = inf.lv or 0 } end
        PB.inflight = nil
        PB.Refresh()
        return "lowlv"
    end
    for _, k in ipairs(FAIL_BLOCK) do
        if _G[k] and msg == _G[k] then
            PB.blocked[inf.guid] = now() + PB.BLOCK
            PB.inflight = nil
            PB.Refresh()
            return "blocked"
        end
    end
    PB.inflight = nil   -- 别的错（公共冷却 / 没蓝）：还是这个人
    PB.Refresh()
    return "other"
end

-- ---------- 事件 ----------
local ev = CreateFrame("Frame")
PB.frame = ev
for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "UNIT_AURA", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UNIT_SPELLCAST_SUCCEEDED",
    "UI_ERROR_MESSAGE", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "CHAT_MSG_ADDON", "LEARNED_SPELL_IN_TAB", "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD", "UNIT_LEVEL" }) do
    pcall(ev.RegisterEvent, ev, e)
end
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PB.PREFIX)
elseif RegisterAddonMessagePrefix then pcall(RegisterAddonMessagePrefix, PB.PREFIX) end
local dirty, acc = false, 0
local function soon() dirty = true end
ev:SetScript("OnUpdate", function(_, el)
    acc = acc + (el or 0)
    if acc < (dirty and 0.2 or 1) then return end
    acc = 0
    if not (dirty or (float and float:IsShown()) or (curPage() and curPage():IsShown())) then return end
    dirty = false
    pcall(PB.Refresh)
end)
function PB.OnEvent(e, a1, a2, a3, a4)
    if not (ns.db and PB.IsPaladin()) then return end
    if e == "CHAT_MSG_ADDON" then
        if a1 == PB.PREFIX then PB.OnAddonMsg(a2, a4) end
    elseif e == "UNIT_AURA" then
        if type(a1) == "string" and (a1 == "player" or a1:match("^party%d") or a1:match("^raid%d")) then
            local inf = PB.inflight
            if inf and call(UnitGUID, a1) == inf.guid then PB.inflight = nil end
            soon()
        end
    elseif e == "UNIT_SPELLCAST_SUCCEEDED" then
        if a1 == "player" and PB.BY_ID[a3 or a2] then soon() end
    elseif e == "UI_ERROR_MESSAGE" then
        PB.OnError(type(a2) == "string" and a2 or a1)
    elseif e == "UNIT_SPELLCAST_FAILED" or e == "UNIT_SPELLCAST_FAILED_QUIET" then
        if a1 == "player" then PB.OnCastFailed(a3 or a2) end
    elseif e == "PLAYER_REGEN_ENABLED" then
        PB.OnRegen()
    elseif e == "PLAYER_REGEN_DISABLED" then
        PB.SetFloatText(PB.NextText())
    elseif e == "GROUP_ROSTER_UPDATE" then
        for n in pairs(PB.peers) do if not rosterNames()[n] then PB.peers[n] = nil end end
        if inGroup() and C_ChatInfo and C_ChatInfo.SendAddonMessage and not next(PB.peers) then
            call(C_ChatInfo.SendAddonMessage, PB.PREFIX, "Q\t1", inRaid() and "RAID" or "PARTY")
        end
        PB.Broadcast()
        PB.Refresh()
    else
        soon()
    end
end
ev:SetScript("OnEvent", function(_, e, ...) PB.OnEvent(e, ...) end)
-- _Class 晚于进世界才加载（进队时 ClassStub.lua 条件加载）→ 补跑一次
ns.AddInit(function()
    if IsLoggedIn and IsLoggedIn() then pcall(PB.OnEvent, "GROUP_ROSTER_UPDATE") end
end)

-- ---------- 页 / 命令 ----------
local function pageVisible() return not (ns.db and type(ns.db.pally) == "table" and ns.db.pally.page == false) end
PB.PageVisible = pageVisible
ns.RegisterPage({ key = "pally", order = 1.46, class = "Paladin", visible = pageVisible, title = ns.L("一键祝福", "Blessings"),
    build = build, refresh = function() PB.Refresh() end })

ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash["祝福"] = function(rest)
    rest = (rest or ""):gsub("^[ \t]+", ""):gsub("[ \t]+$", "")
    if not PB.IsPaladin() then ns.Print(L("一键祝福只给圣骑士用", "One-click blessings is for paladins")); return end
    local k, v = rest:match("^([^ \t]+)[ \t]*(.-)$")
    local on   -- ⛔ 别写成 … and false or nil（恒为 nil）
    if v == "开" or v == "on" then on = true elseif v == "关" or v == "off" then on = false end
    if (k == "悬浮" or k == "float") then
        if on == nil then on = not PB.FloatOn() end
        PB.SetFloat(on); PB.floatPreview = on or nil; PB.Refresh()
        ns.Print(on and L("一键祝福悬浮按钮：开（组队时显示）", "Floating button: on") or L("一键祝福悬浮按钮：关", "Floating button: off"))
    elseif (k == "王者" or k == "kings") and on ~= nil then
        PB.SetAllKings(on)
        ns.Print(on and L("全给王者：开（学会王者祝福后生效）", "All Kings: on") or L("全给王者：关", "All Kings: off"))
    elseif (k == "强效" or k == "greater") and on ~= nil then
        PB.SetGreater(on)
        ns.Print(on and L("强效祝福（同职业整组）：开", "Greater blessings: on") or L("强效祝福：关", "Greater blessings: off"))
    elseif (k == "提前" or k == "soon") and tonumber(v) then
        PB.SetSoon(v)
        ns.Print(string.format(L("剩余少于 %d 秒就补", "Rebless under %d s"), PB.Soon()))
    elseif k == "默认" or k == "reset" then
        PB.ResetAssign()
        ns.Print(L("一键祝福：分配恢复默认", "Blessings: assignments reset"))
    else
        if ns.ToggleMain then ns.ToggleMain("pally") end
        ns.Print(PB.NextText() .. L("　|cff9a9a9a/gi 祝福 悬浮 | 王者 开/关 | 强效 开/关 | 提前 60 | 默认|r", "   |cff9a9a9a/gi pb float | kings on/off | greater on/off | soon 60 | reset|r"))
    end
end
ns.ExtraSlash.pb = ns.ExtraSlash["祝福"]
