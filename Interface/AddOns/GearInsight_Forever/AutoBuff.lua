-- HOLD：GI-303「一键给路人上BUFF」（法师玩家原话：「现在能自动密附近玩家求buff，有没有办法实现自动给路人上buff的，我是法师，用手选玩家再去点，人都走远了」），游戏内实测前不进发行包
--
-- ⛔ 暴雪规则：插件不能自动施法 —— 每次施法都要玩家按一下（硬件事件）；安全按钮（SecureActionButton）的 unit / spell 属性战斗中插件代码改不了。
--   ⛔ 本文件不发任何聊天（只往自己聊天框 ns.Print 说原因），也不做任何没按键的施法（代码里没有 CastSpell*，测试核对）。
--   所以做成「插件挑人、玩家按键」：
--   · 一个可拖动的小悬浮框，里面一个安全按钮（type = spell / spell = 法术 id / unit = 挑中的人），按钮上：BUFF 图标 + 附近缺的人数 + 下一个是谁；没蓝时图标变灰
--   · 战斗外插件挑「下一个」：目标 / 鼠标指向 / 焦点 / 队友 / 友方姓名板 nameplate1..40 里 —— 是玩家、不是自己、可协助（UnitCanAssist）、不是敌对 / 异阵营、
--     在线、活着、身上没有这类 BUFF（任何人加的、同类团队版都算有）、在施法距离内（C_Spell.IsSpellInRange / IsSpellInRange）、按他的等级挑得出能上的一级
--     → 挑谁：目标 / 鼠标指向（玩家自己指着的人）先；其余按距离近的先（UnitDistanceSquared 队友有数；路人用 CheckInteractDistance 分档 10 / 11 / 28 码；
--       读不到距离的排在读得到的后面、彼此按候选顺序）
--   · 属性只在脱战时改：PreClick（脱战时）现挑一次再设属性（按下那一刻对准的就是现在最该上的人）；1 秒 / 事件 0.25 秒节流刷新框上的字（不每帧扫）
--   · 没有合适的人：type 清空（这一下什么都不放），聊天框说一句原因（「附近没有缺智力的玩家」/「友方姓名板没开，看不到附近玩家」+ 怎么打开），3 秒内同一句不重复
--   · 战斗中：插件代码一个属性都不改；进战斗那一刻属性改成「按当前目标放」（unit = target、spell = 不带等级的法术名），按钮上写「战斗中：给当前目标」
--     两道保险：① PLAYER_REGEN_DISABLED 里（这时还能改）插件自己改；② 安全状态驱动 [combat] 在受保护环境里再改一次（万一事件晚了 / 被别的插件拖慢，
--     战斗前挑的姓名板编号也不会留到战斗里指到别人身上）
--   · 跳过：刚上过（施法成功后 30 秒内不再挑他，光环读不到时也不会来回点同一个人）/ 刚点还没生效（1.5 秒）/
--     刚报「视线受阻 / 距离太远」（8 秒内先给下一个）/ 光环读不到（秘密值）的人
--
-- 法术等级（11-20 查清楚的经典规则，写在这里备查）：
--   · 经典客户端：从动作条放「不带等级」的 BUFF 给等级太低的人，客户端会自动降到他能吃的最高一级（warcraft.wiki.gg「Downranking」）；
--     但指定了等级（宏写「(等级 3)」/ 按 spellId 施放 = 锁死在那一级）就不降，直接报「目标等级太低」（官方论坛多帖实测：宏 / 指定等级报错，动作条正常）。
--   · 本按钮战斗外按 spellId 施放（SecureActionButton type=spell 数字 → CastSpellByID，锁定那一级）——是故意的：插件已经按目标等级自己挑好了那一级
--     （目标等级 ≥ 学习等级 − 10，同 PallyBless.lua 的 PB.LOWLV），不依赖客户端自动降级；万一规则在无限不一样，报「目标等级太低」时记下这个人这一级、下次再降一级。
--   · 战斗中按当前目标放，插件不知道目标是谁 → 用不带等级的法术名（spell = "奥术智慧"），让客户端按目标等级自动降级（同动作条行为）。无限上没实测，见交付说明。
--
-- 数据（11-20 共建看板要求「别复制一份」）：BUFF 类型 / 各级法术 id / 学习等级 / 团队版 / 没蓝职业全读组队信标 _Group 的 BuffAsk.lua（ns.BuffAsk.TYPES / NO_MANA），
--   那边的 id 来自开服客户端技能书 services/dashboard/static/data/forever/spellbook.json（测试逐条核对）；ids 前 #ranks 个 = 各级（和 ranks 一一对应），后面的 = 团队版。
--   组队信标没加载（设置里改成点了才加载）→ 脱战时 ns.LoadModule("group") 拉起来。⛔ 所以本文件和 BuffAsk.lua 绑在一起：发版时 BuffAsk.lua 要一起解除 HOLD。
--   读别人身上的光环：BuffAsk.lua 只暴露了读自己（BA.MyAuras），没有读别的单位的接口 → 这里留一个按单位读的小函数（不改 BuffAsk.lua，避免和 GI-319 撞）。
-- 圣骑士不在这里：已有 PallyBless.lua 的一键祝福（职业 → 一键祝福页 / 悬浮框），设置说明里指过去。牧师暗影防护 / 神圣之灵（选做）这期没做。
--
-- ① 放在哪：职业子插件 GearInsight_Forever_Class（含安全按钮，⛔ 战斗中不加载，同 PallyBless.lua）；
--   主插件 ClassStub.lua：开关开着（默认关）的法师 / 牧师 / 德鲁伊登录后条件加载 _Class；「窗口与提醒」放同 key 占位；组队抽屉「组队设置」里的设置组 buffgive
-- ② 开关（存档 ns.db.autoBuff）：on（true = 开；nil / false = 关，新功能默认关）· pos 悬浮框位置；快捷键存在游戏键位里（SetBindingClick，只绑一个键）
--   组队抽屉齿轮「组队设置」→「一键给路人上 BUFF（按钮 + 快捷键）」+「设置快捷键」· 功能中心「一键给路人上BUFF」· 悬浮框齿轮（左键：设置快捷键 / 重置位置 / 永久关闭；右键：永久关闭）
--   · 窗口与提醒「一键上BUFF悬浮框」找回 · /gi buff give on|off|key（= /gi 上buff 开|关|键）
local _, ns = ...; ns = _G.GearInsightForever or ns

local AB = {}
ns.AutoBuff = AB
local function L(cn, en) return ns.L(cn, en) end

AB.BTN = "GearInsightForeverAutoBuffBtn"   -- 绑键目标（悬浮框里的安全按钮）
AB.INFLIGHT = 1.5     -- 刚点完：这么久内不再挑同一个人（光环还没到）
AB.DONE = 30          -- 施法成功后这么久内不再挑他
AB.BLOCK = 8          -- 报「视线受阻 / 距离太远」后这么久不挑他
AB.LOWLV = 10         -- 目标等级 ≥ 法术学习等级 − 10 才能上（经典规则，同 PallyBless.lua）
AB.PLATES = 40        -- 友方姓名板最多看几个
AB.IDLE, AB.DIRTY = 1, 0.25   -- 刷新节流：平时每秒一次，有事件时 0.25 秒内合并一次
AB.SAY_GAP = 3        -- 同一句原因 3 秒内不重复说

-- 哪个职业放哪个（只有显示用的法术名；id / 等级 / 团队版读 BuffAsk.lua，见文件头）
AB.SPELL = { MAGE = { "奥术智慧", "Arcane Intellect" }, PRIEST = { "真言术：韧", "Power Word: Fortitude" }, DRUID = { "野性印记", "Mark of the Wild" } }

-- ---------- 小工具（secret 值一律当「不知道」，同 PallyBless.lua）----------
local function now() return GetTime and GetTime() or 0 end
local function combat() return InCombatLockdown and InCombatLockdown() and true or false end
local function unsecret(v) if issecretvalue and issecretvalue(v) then return nil end return v end
local function call(f, ...) if not f then return nil end local ok, a, b, c = pcall(f, ...); if ok then return unsecret(a), unsecret(b), unsecret(c) end end
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
local function inGroup() return IsInGroup ~= nil and call(IsInGroup) and true or false end
local function inRaid() return IsInRaid ~= nil and call(IsInRaid) and true or false end
-- 单位等级：-1（骷髅）当 60；读不到 = nil
local function unitLevel(u)
    local v = tonumber(call(UnitLevel, u))
    if not v or v == 0 then return nil end
    if v < 0 then return 60 end
    return v
end
local function fullName(u)
    local n, realm = call(UnitName, u)
    if type(n) ~= "string" or n == "" then return nil end
    if type(realm) == "string" and realm ~= "" then return n .. "-" .. realm end
    return n
end
local NAMES = {}
local function spellName(id)
    if not id then return nil end
    if NAMES[id] ~= nil then return NAMES[id] or nil end
    local n
    if C_Spell and C_Spell.GetSpellName then n = call(C_Spell.GetSpellName, id) end
    if (type(n) ~= "string" or n == "") and GetSpellInfo then n = call(GetSpellInfo, id) end
    NAMES[id] = (type(n) == "string" and n ~= "") and n or false
    return NAMES[id] or nil
end

function AB.MyClass() return classOf("player") end
-- 这个职业用得上吗（不看组队信标在不在）
function AB.ForMe() return AB.SPELL[AB.MyClass() or ""] ~= nil end

-- ---------- BUFF 类型：从 BuffAsk.lua 的 BA.TYPES 拼出来（不复制数据）----------
--   → { k, cls, cn, en（法术名）, scn, sen（BUFF 简称：智力 / 耐力 / 野性印记）, ranks = { { id, 学习等级 }, … }（低到高）, ids = { [id] = true }（含团队版）, mana, noMana }
function AB.TypeFor(cls, BA)
    BA = BA or ns.BuffAsk
    local sp = AB.SPELL[cls or ""]
    if not (sp and BA and type(BA.TYPES) == "table") then return nil end
    for _, x in ipairs(BA.TYPES) do
        if x.cls == cls and not x.fam and type(x.ids) == "table" and type(x.ranks) == "table" then
            local t = { k = x.k, cls = cls, cn = sp[1], en = sp[2], scn = x.cn, sen = x.en, mana = x.mana, noMana = BA.NO_MANA or {}, ranks = {}, ids = {} }
            for i, id in ipairs(x.ids) do
                t.ids[id] = true
                if x.ranks[i] then t.ranks[#t.ranks + 1] = { id, x.ranks[i] } end
            end
            return t
        end
    end
    return nil
end
local cache = {}
function AB.MyType()
    local cls = AB.MyClass()
    if not AB.SPELL[cls or ""] then return nil end
    local BA = ns.BuffAsk
    if not BA and not combat() and not AB.grpTried and ns.LoadModule then   -- 组队信标没加载（点了才加载）：脱战时拉一次
        AB.grpTried = true
        pcall(ns.LoadModule, "group", true)
        BA = ns.BuffAsk
    end
    if not BA then return nil end
    if cache.types ~= BA.TYPES or cache.cls ~= cls then cache = { types = BA.TYPES, cls = cls, t = AB.TypeFor(cls, BA) } end
    return cache.t
end
function AB.BuffName(t) t = t or AB.MyType(); return t and (spellName(t.ranks[1] and t.ranks[1][1]) or L(t.cn, t.en)) or "" end
function AB.ShortName(t) t = t or AB.MyType(); return t and L(t.scn, t.sen) or L("BUFF", "buff") end

-- ---------- 开关（ns.db.autoBuff；新功能默认关：on == true 才开）----------
function AB.DB()
    if type(ns.db.autoBuff) ~= "table" then ns.db.autoBuff = {} end
    return ns.db.autoBuff
end
function AB.On() return ns.db ~= nil and type(ns.db.autoBuff) == "table" and ns.db.autoBuff.on == true end
function AB.SetOn(v)
    if not ns.db then return end
    AB.DB().on = v and true or false
    AB.Refresh()
end

-- ---------- 法术等级 ----------
local function known(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown and call(C_SpellBook.IsSpellKnown, id) then return true end
    if IsPlayerSpell and call(IsPlayerSpell, id) then return true end
    if IsSpellKnown and call(IsSpellKnown, id) then return true end
    return false
end
AB.Known = known
function AB.TopKnown(t)
    t = t or AB.MyType()
    if not t then return nil end
    for i = #t.ranks, 1, -1 do if known(t.ranks[i][1]) then return t.ranks[i][1] end end
    return nil
end
function AB.Knows(t) return AB.TopKnown(t) ~= nil end
-- 给 lv 级的目标能上的最高一级（自己学会的里挑；cap = 这个人报过「等级太低」的那一级的学习等级，只挑比它低的）→ id, 学习等级, 第几级
function AB.SpellFor(lv, cap, t)
    t = t or AB.MyType()
    if not t then return nil end
    for i = #t.ranks, 1, -1 do
        local id, need = t.ranks[i][1], t.ranks[i][2]
        if known(id) and (not lv or lv <= 0 or lv >= need - AB.LOWLV) and (not cap or need < cap) then return id, need, i end
    end
    return nil
end
-- 战斗中按当前目标放的法术：不带等级的法术名（客户端按目标等级自动降级，见文件头）；名字读不到才退回最高一级的 id
function AB.CombatSpell(t)
    local top = AB.TopKnown(t)
    return spellName(top) or top
end

-- ---------- 读光环：他身上有没有这类 BUFF（任何人加的都算）→ true / false；读不到（秘密值）= nil ----------
local function auraAt(u, i)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, u, i, "HELPFUL")
        if not ok or a == nil then return nil end
        if type(a) ~= "table" then return false end
        if (a.name ~= nil and unsecret(a.name) == nil) or (a.spellId ~= nil and unsecret(a.spellId) == nil) then return false end
        return true, a.name, a.spellId
    end
    local f = UnitAura or UnitBuff
    if not f then return nil end
    local r = { pcall(f, u, i, UnitAura and "HELPFUL" or nil) }
    if not r[1] or r[2] == nil then return nil end
    if unsecret(r[2]) == nil or (r[11] ~= nil and unsecret(r[11]) == nil) then return false end
    return true, r[2], r[11]
end
function AB.HasBuff(u, t)
    t = t or AB.MyType()
    if not t then return nil end
    local names = t.names
    if not names then
        names = {}
        for id in pairs(t.ids) do local n = spellName(id); if n then names[n] = true end end
        t.names = names
    end
    for i = 1, 40 do
        local okA, name, id = auraAt(u, i)
        if okA == nil then break end
        if okA == false then return nil end
        if (id and t.ids[tonumber(id) or -1]) or (name and names[name]) then return true end
    end
    return false
end

-- 施法距离：几种问法任何一种说「在」就算在；都说不在 = 不在；都问不到 = 当在（判错了顶多报「距离太远」，那时拉黑 8 秒）
local function inRange(u, id)
    if UnitIsVisible and call(UnitIsVisible, u) == false then return false end
    local said = nil
    if C_Spell and C_Spell.IsSpellInRange then
        local r = call(C_Spell.IsSpellInRange, id, u)
        if r == true or r == 1 then return true end
        if r ~= nil then said = false end
    end
    if IsSpellInRange then
        local n = spellName(id)
        local r = n and call(IsSpellInRange, n, u)
        if r == 1 or r == true then return true end
        if r ~= nil then said = false end
    end
    return said ~= false
end
AB.InRange = inRange

-- 距离（码）：队友 UnitDistanceSquared 有准数；路人只能分档（CheckInteractDistance 3 = 决斗 ~10 码 / 2 = 交易 ~11 码 / 4 = 跟随 ~28 码，战斗外才问）；读不到 = nil
local function interact(u, k)
    if not CheckInteractDistance or (InCombatLockdown and InCombatLockdown()) then return nil end   -- 战斗中受保护
    local ok, r = pcall(CheckInteractDistance, u, k)
    if not ok then return nil end
    r = unsecret(r)
    if r == nil then return nil end
    return r and true or false
end
function AB.Dist(u)
    if UnitDistanceSquared then
        local d, checked = call(UnitDistanceSquared, u)
        d = tonumber(d)
        if checked and d and d >= 0 then return math.sqrt(d) end
    end
    if combat() then return nil end
    local r3 = interact(u, 3)
    if r3 == nil then return nil end
    if r3 then return 10 end
    if interact(u, 2) then return 11 end
    if interact(u, 4) then return 28 end
    return 30   -- 施法距离内（30 码）但 28 码外
end

-- ---------- 挑人 ----------
AB.inflight = nil     -- { guid, id, at, lv, need }
AB.done = {}          -- [guid] = 到这个时间之前不挑他（刚上过）
AB.blocked = {}       -- [guid] = 到这个时间之前不挑他（刚报视线 / 距离）
AB.tooLow = {}        -- [guid] = { lv = 报过「目标等级太低」那一级的学习等级, at = 当时他的等级 }（他升级后作废）
local function capFor(guid, lv)
    local x = AB.tooLow[guid]
    if type(x) == "table" and (lv or 0) <= (x.at or 0) then return x.lv end
    return nil
end
-- 候选单位（这个顺序 = 距离读不到时的先后）
function AB.Units()
    local out = { "target", "mouseover", "focus" }
    if inRaid() then
        local n = tonumber(call(GetNumGroupMembers)) or 0
        for i = 1, math.min(n, 40) do out[#out + 1] = "raid" .. i end
    elseif inGroup() then
        for i = 1, 4 do out[#out + 1] = "party" .. i end
    end
    for i = 1, AB.PLATES do out[#out + 1] = "nameplate" .. i end
    return out
end
-- 一个单位现在怎样：{ unit, guid, name, cls, lv, st, id, need }
--   st：need 要上 · has 有了 · skip 不给（没蓝）· far 太远 / 看不见 · lowlv 等级太低没有能上的一级 · flying 刚点 · done 刚上过 · blocked 刚报错 · unknown 光环读不到
--   不是玩家 / 自己 / 不可协助 / 敌对 / 异阵营 / 离线 / 死了 → nil（不列）
function AB.Check(u, t, mf)
    t = t or AB.MyType()
    if not (t and exists(u)) then return nil end
    if not call(UnitIsPlayer, u) or isMe(u) then return nil end
    if UnitIsFriend and not call(UnitIsFriend, "player", u) then return nil end
    if UnitCanAssist and not call(UnitCanAssist, "player", u) then return nil end
    mf = mf or call(UnitFactionGroup, "player")
    local f = call(UnitFactionGroup, u)
    if mf and f and f ~= mf then return nil end
    if UnitIsConnected and call(UnitIsConnected, u) == false then return nil end
    if UnitIsDeadOrGhost and call(UnitIsDeadOrGhost, u) then return nil end
    local guid = call(UnitGUID, u) or fullName(u)
    if not guid then return nil end
    local e = { unit = u, guid = guid, name = fullName(u), cls = classOf(u), lv = unitLevel(u) }
    if t.mana and e.cls and t.noMana[e.cls] then e.st = "skip"; return e end
    local has = AB.HasBuff(u, t)
    if has == nil then e.st = "unknown"; return e end
    if has then e.st = "has"; return e end
    local id, need = AB.SpellFor(e.lv, capFor(guid, e.lv), t)
    if not id then e.st = "lowlv"; return e end
    e.id, e.need = id, need
    local tm = now()
    local inf = AB.inflight
    if inf and inf.guid == guid and tm - inf.at < AB.INFLIGHT then e.st = "flying"; return e end
    if (AB.done[guid] or 0) > tm then e.st = "done"; return e end
    if (AB.blocked[guid] or 0) > tm then e.st = "blocked"; return e end
    if not inRange(u, id) then e.st = "far"; return e end
    e.st = "need"
    return e
end
function AB.Eval()
    local t = AB.MyType()
    local list, seen = {}, {}
    if not t then return list end
    local mf = call(UnitFactionGroup, "player")
    for _, u in ipairs(AB.Units()) do
        local e = AB.Check(u, t, mf)
        if e and not seen[e.guid] then
            seen[e.guid] = true
            list[#list + 1] = e
        end
    end
    return list
end
-- → 下一个（nil = 没人要上）, 附近缺的人数（在施法距离内、这一下能上的，含这一个）
--   目标 / 鼠标指向（玩家自己指着的人）先；其余距离近的先；读不到距离的排后面、按候选顺序
local PICKED = { target = true, mouseover = true }
function AB.Next(list)
    list = list or AB.Eval()
    local need = {}
    for i, e in ipairs(list) do
        if e.st == "need" then
            e.ord = i
            if PICKED[e.unit] then e.dist = -1 else e.dist = AB.Dist(e.unit) end
            need[#need + 1] = e
        end
    end
    table.sort(need, function(a, b)
        local da, db = a.dist or 1e9, b.dist or 1e9
        if da ~= db then return da < db end
        return a.ord < b.ord
    end)
    return need[1], #need
end

-- ---------- 安全按钮 ----------
AB.attrWrites = 0
local btn, float, guard
local function setAttrs(b, typ, spell, unit)
    if not b or combat() then return false end   -- ⛔ 战斗中不改属性
    local cur = rawget(b, "_abAttr")
    if cur and cur.type == typ and cur.spell == spell and cur.unit == unit then return true end
    b:SetAttribute("type", typ)
    b:SetAttribute("spell", spell)
    b:SetAttribute("unit", unit)
    rawset(b, "_abAttr", { type = typ, spell = spell, unit = unit })
    AB.attrWrites = AB.attrWrites + 1
    return true
end
AB.SetAttrs = setAttrs
function AB.Apply(nx)
    if combat() or not btn then return false end
    if nx then setAttrs(btn, "spell", nx.id, nx.unit) else setAttrs(btn, nil, nil, nil) end
    rawset(btn, "_abNext", nx)
    -- 战斗保险（安全状态驱动）用的法术名：脱战时随时备好
    if guard then guard:SetAttribute("abspell", AB.Wanted() and AB.CombatSpell() or nil) end   -- 关着时战斗中按了也不放
    return true
end
-- 进战斗：按当前目标放（unit = target、不带等级的法术名）
function AB.ApplyCombat()
    if not btn then return false end
    local sp = AB.CombatSpell()
    local ok = setAttrs(btn, sp and "spell" or nil, sp, sp and "target" or nil)
    rawset(btn, "_abNext", nil)
    return ok
end

-- ---------- 文字 ----------
local function rankTxt(e)
    local t = AB.MyType()
    if not (t and e and e.id) then return "" end
    for i, r in ipairs(t.ranks) do
        if r[1] == e.id then return i < #t.ranks and string.format(L("（%d 级）", " (rank %d)"), i) or "" end
    end
    return ""
end
function AB.NextText(nx, n)
    if combat() or AB.inCombat then return L("战斗中：按一下给当前目标上（插件战斗中不能换人，脱战继续挑）", "In combat: press to buff your current target (resumes picking after combat)") end
    if not AB.MyType() then return L("要用组队模块（要 BUFF）的数据，组队模块没加载上", "Needs the Group module (buff data) - not loaded") end
    if not nx then
        if not AB.Knows() then return string.format(L("还没学会%s", "You haven't learned %s"), AB.BuffName()) end
        return string.format(L("附近没有缺%s的玩家", "Nobody nearby needs %s"), AB.ShortName())
    end
    local s = string.format(L("下一个：%s · %s%s", "Next: %s · %s%s"), short(nx.name) or "?", AB.BuffName(), rankTxt(nx))
    if (n or 0) > 1 then s = s .. string.format(L("　还有 %d 个", "  (%d more)"), n - 1) end
    return s
end
function AB.BtnText(nx)
    if combat() or AB.inCombat then return L("战斗中：给当前目标", "Combat: current target") end
    if not nx then return L("没人缺", "Nobody") end
    return string.format(L("上%s → %s", "%s > %s"), AB.ShortName(), short(nx.name) or "?")
end
function AB.WhyText(list)
    local cnt = {}
    for _, e in ipairs(list or AB.Eval()) do cnt[e.st] = (cnt[e.st] or 0) + 1 end
    local parts = {}
    local W = { { "far", "%d 个太远", "%d too far" }, { "lowlv", "%d 个等级太低", "%d too low" }, { "blocked", "%d 个刚报视线 / 距离", "%d blocked" },
        { "unknown", "%d 个读不到光环", "%d unreadable" } }
    for _, w in ipairs(W) do if cnt[w[1]] then parts[#parts + 1] = string.format(L(w[2], w[3]), cnt[w[1]]) end end
    return table.concat(parts, L("，", ", "))
end
-- 友方姓名板开没开：true / false；读不到 = nil
function AB.FriendPlates()
    local v
    if C_CVar and C_CVar.GetCVar then v = call(C_CVar.GetCVar, "nameplateShowFriends") end
    if v == nil and GetCVar then v = call(GetCVar, "nameplateShowFriends") end
    if v == nil then return nil end
    return tostring(v) == "1"
end
AB.PLATE_HOW = { "按 Shift+V 打开友方姓名板（或 Esc → 选项 → 界面 → 姓名板 → 勾「友方玩家」）",
    "press Shift+V for friendly nameplates (or Esc > Options > Interface > Nameplates > Friendly players)" }
-- 这一下没放的原因（聊天框说）
function AB.EmptyReason(list)
    local t = AB.MyType()
    if not t then return AB.NextText(nil) end
    if not AB.Knows(t) then return AB.NextText(nil) end
    list = list or AB.Eval()
    local plates = AB.FriendPlates()
    local s
    if plates == false then
        s = L("友方姓名板没开，看不到附近玩家（现在只看得到目标 / 鼠标指向 / 队友）：", "Friendly nameplates are off, so nearby players can't be seen (only target / mouseover / party): ") .. L(AB.PLATE_HOW[1], AB.PLATE_HOW[2])
        if ns.CityPlates and ns.CityPlates.Enabled and ns.CityPlates.InCity and call(ns.CityPlates.Enabled) and call(ns.CityPlates.InCity) then
            s = s .. L("。插件「进主城关友方姓名板」在主城会关掉它，要在主城上 BUFF 可在 GI 设置里关掉这项", ". GearInsight's \"hide friendly nameplates in cities\" turns them off here - disable it in GI settings to buff in cities")
        end
    else
        s = string.format(L("附近没有缺%s的玩家", "Nobody nearby needs %s"), AB.ShortName(t))
        local why = AB.WhyText(list)
        if why ~= "" then s = s .. L("（", " (") .. why .. L("）", ")") end
    end
    return s
end
AB.saidAt, AB.saidMsg = -1e9, nil
function AB.SayEmpty()
    local msg = AB.EmptyReason()
    if msg == AB.saidMsg and now() - AB.saidAt < AB.SAY_GAP then return false end
    AB.saidAt, AB.saidMsg = now(), msg
    ns.Print(L("一键上BUFF：这下没放 —— ", "One-key buff: nothing cast - ") .. msg)
    return true
end

-- ---------- 按钮外观：图标 / 人数 / 没蓝变灰 ----------
local function iconOf(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellTexture then local tx = call(C_Spell.GetSpellTexture, id); if tx then return tx end end
    if GetSpellTexture then local tx = call(GetSpellTexture, id); if tx then return tx end end
    if GetSpellInfo then local _, _, tx = call(GetSpellInfo, id); return tx end
    return nil
end
-- 这个法术现在蓝够不够：false = 不够；true / nil（读不到）= 当够
function AB.ManaOk(id)
    if not id then return nil end
    local f = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
    if not f then return nil end
    local _, noMana = call(f, id)
    if noMana == true then return false end
    return true
end
function AB.Paint(nx, n)
    if not (btn and btn.icon) then return end
    local id = (nx and nx.id) or AB.TopKnown()
    local tx = iconOf(id)
    if tx then btn.icon:SetTexture(tx) end
    local poor = AB.ManaOk(id) == false
    btn.icon:SetDesaturated(poor)
    if poor then btn.icon:SetVertexColor(0.5, 0.5, 1) else btn.icon:SetVertexColor(1, 1, 1) end
    rawset(btn, "_abPoor", poor)
    if btn.count then
        if combat() then btn.count:SetText("")
        else btn.count:SetText((n or 0) > 0 and tostring(n) or "") end
    end
    if poor and not combat() then btn:SetText(L("法力不足", "Not enough mana")) end
end

-- ---------- 悬浮框 ----------
local function savePos()
    if not float then return end
    local p, _, _, x, y = float:GetPoint()
    AB.DB().pos = { p or "CENTER", x or 0, y or 0 }
end
local function secureBtn(parent)
    local b = CreateFrame("Button", AB.BTN, parent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    b:SetSize(224, 30)
    if b.RegisterForClicks then b:RegisterForClicks("AnyDown") end
    if ns.SkinButton then ns.SkinButton(b) end
    -- 左边 BUFF 图标 + 右下角人数；文字挪到图标右边
    local ic = b:CreateTexture(nil, "ARTWORK")
    ic:SetSize(24, 24); ic:SetPoint("LEFT", b, "LEFT", 3, 0)
    if ic.SetTexCoord then ic:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    b.icon = ic
    local ct = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    ct:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", 2, -1)
    b.count = ct
    local fs = b.GetFontString and b:GetFontString()
    if fs then fs:ClearAllPoints(); fs:SetPoint("LEFT", b, "LEFT", 32, 0); fs:SetPoint("RIGHT", b, "RIGHT", -6, 0) end
    b:SetScript("PreClick", function()
        if combat() then return end
        AB.Refresh()   -- 脱战时现挑一次，属性对准现在最该上的人
    end)
    b:SetScript("PostClick", function(self)
        if combat() then return end   -- 战斗中按的是「当前目标」：放没放客户端自己会报
        local nx = rawget(self, "_abNext")
        local a = rawget(self, "_abAttr")
        if not (nx and a and a.type) then AB.SayEmpty(); return end
        AB.inflight = { guid = nx.guid, id = nx.id, at = now(), lv = nx.lv, need = nx.need }
        if C_Timer and C_Timer.After then C_Timer.After(0.3, AB.Refresh) end
    end)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L("一键给路人上BUFF", "One-key buffing"), 1, 0.82, 0)
        GameTooltip:AddLine(AB.NextText(AB.last, AB.lastN), 1, 1, 1, true)
        if not combat() then
            local why = AB.WhyText()
            if why ~= "" then GameTooltip:AddLine(why, 1, 0.6, 0.4, true) end
        end
        if rawget(self, "_abPoor") then GameTooltip:AddLine(L("法力不足", "Not enough mana"), 0.5, 0.5, 1) end
        local keys = AB.BindKeys()
        GameTooltip:AddLine(keys[1] and string.format(L("快捷键：%s", "Key: %s"), keys[1]) or L("没设快捷键：右上角齿轮 →「设置快捷键」", "No key yet: gear > Set key"), 0.25, 0.9, 0.35, true)
        GameTooltip:AddLine(L("每按一下给一个人（暴雪规定每次施法都要按一下）；图标上的数字 = 附近缺的人数；战斗中只能给当前目标", "One player per press (each cast needs a key press); number = players nearby missing it; in combat: current target only"), 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end
-- 战斗保险：安全状态驱动 [combat] —— 进战斗时在受保护环境里把按钮改成「当前目标 + 不带等级的法术名」
local GUARD_SNIP = [[
if newstate == "1" then
    local b = self:GetFrameRef("btn")
    local s = self:GetAttribute("abspell")
    if b and s then b:SetAttribute("type", "spell"); b:SetAttribute("spell", s); b:SetAttribute("unit", "target") end
    if b and not s then b:SetAttribute("type", nil) end
end
]]
local function buildGuard(parent)
    local ok, h = pcall(CreateFrame, "Frame", nil, parent, "SecureHandlerStateTemplate")
    if not (ok and h) then return nil end
    if SecureHandlerSetFrameRef then pcall(SecureHandlerSetFrameRef, h, "btn", btn) elseif h.SetFrameRef then pcall(h.SetFrameRef, h, "btn", btn) end
    h:SetAttribute("_onstate-abcombat", GUARD_SNIP)
    h:SetAttribute("abspell", AB.CombatSpell())
    if RegisterStateDriver then pcall(RegisterStateDriver, h, "abcombat", "[combat] 1; 0") end
    return h
end
AB.GUARD_SNIP = GUARD_SNIP
function AB.BuildFloat()
    if float then return float end
    if combat() then return nil end
    local f = CreateFrame("Frame", "GearInsightForeverAutoBuffFloat", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(240, 66); f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(true)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.05, 0.05, 0.07, 0.88)
    end
    local pos = AB.DB().pos
    if type(pos) == "table" then f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else f:SetPoint("CENTER", UIParent, "CENTER", 260, -120) end
    f:SetMovable(true); f:EnableMouse(true)
    if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
    f:SetScript("OnDragStart", function(self) if not combat() then self:StartMoving() end end)   -- 里面有安全按钮：战斗中不能挪
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos() end)
    f.line = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.line:SetPoint("TOPLEFT", 8, -7); f.line:SetPoint("TOPRIGHT", -26, -7); f.line:SetJustifyH("LEFT")
    if f.line.SetWordWrap then f.line:SetWordWrap(true) end
    if f.line.SetMaxLines then f.line:SetMaxLines(2) end
    -- 右上角齿轮：左键小菜单（设置快捷键 / 重置位置 / 永久关闭）· 右键永久关闭（11-17 用户「这些弹出的功能都确保能永久关闭」）
    local gear = CreateFrame("Button", nil, f)
    gear:SetSize(16, 16); gear:SetPoint("TOPRIGHT", -6, -6)
    gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    if gear.RegisterForClicks then gear:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    gear:SetScript("OnClick", function(self, mb) if mb == "RightButton" then AB.Never() else AB.GearMenu(self) end end)
    gear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L("一键上BUFF设置", "One-key buff settings"), 1, 0.82, 0)
        GameTooltip:AddLine(L("左键：设置快捷键 / 重置位置 / 永久关闭  ·  右键：永久关闭  ·  拖拽移动", "Left: key / reset / close  ·  Right: close for good  ·  Drag: move"), 0.25, 0.9, 0.35, true)
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.gear = gear
    btn = secureBtn(f)
    btn:SetPoint("BOTTOM", f, "BOTTOM", 0, 7)
    btn:SetText(AB.BtnText(nil))
    f.btn = btn
    guard = buildGuard(f)
    f.guard = guard
    f:Hide()
    float = f
    AB.float = f
    return f
end
function AB.GearMenu(anchor)
    if not ns.PopMenu then return end
    local keys = AB.BindKeys()
    ns.PopMenu(anchor, L("一键上BUFF", "One-key buff"), {
        { text = keys[1] and string.format(L("设置快捷键（现在：%s）", "Set key (now: %s)"), keys[1]) or L("设置快捷键", "Set key"), fn = function() AB.BeginBind() end },
        { text = L("重置位置", "Reset position"), fn = function() AB.ResetPos() end },
        { text = L("永久关闭悬浮框", "Close for good"), fn = function() AB.Never() end },
    })
end
-- 永久关闭（⛔ 框里有安全按钮，战斗中收不起来 → 只提示）
function AB.Never()
    if combat() then ns.Print(L("战斗中收不起悬浮框，脱战后再右键", "Can't hide it in combat - right-click again after")); return false end
    AB.SetOn(false)
    if float then float:Hide() end
    if ns.CloseHint then
        ns.CloseHint("autoBuff", L("一键上BUFF悬浮框已永久关闭。找回：组队抽屉齿轮「组队设置」→「一键给路人上 BUFF」，或 GI 菜单 → 设置 → 窗口与提醒「一键上BUFF悬浮框」，或 /gi buff give on",
            "One-key buff button closed for good. Bring it back: Group drawer gear > Group settings, GI menu > Settings > Windows & alerts, or /gi buff give on"))
    end
    return true
end
function AB.ResetPos()
    if combat() then return false end
    if ns.db then AB.DB().pos = nil end
    if float then float:ClearAllPoints(); float:SetPoint("CENTER", UIParent, "CENTER", 260, -120) end
    return true
end
function AB.Wanted() return AB.ForMe() and AB.On() end

-- ---------- 绑键：只绑一个键（SetBindingClick 到悬浮框的按钮；用户规定键位只许逐个设置，不许一键铺 / 一键绑）----------
local BIND_CMD = "CLICK " .. AB.BTN .. ":LeftButton"
AB.BIND_CMD = BIND_CMD
function AB.BindKeys()
    local out = {}
    if GetBindingKey then
        local k1, k2 = call(GetBindingKey, BIND_CMD)
        if k1 then out[#out + 1] = k1 end
        if k2 then out[#out + 1] = k2 end
    end
    return out
end
-- → true / nil, 原因（combat / api / taken, 原来的功能）
function AB.Bind(key, force)
    if combat() then return nil, "combat" end
    if not (SetBindingClick and SetBinding) then return nil, "api" end
    AB.BuildFloat()
    if key then
        local act = GetBindingAction and call(GetBindingAction, key)
        if act and act ~= "" and act ~= BIND_CMD and not force then return nil, "taken", act end
    end
    for _, k in ipairs(AB.BindKeys()) do call(SetBinding, k) end
    if key then call(SetBindingClick, key, AB.BTN, "LeftButton") end
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
    local ok, why, act = AB.Bind(key or nil, key ~= false and pendingKey == key)
    if ok then
        pendingKey = nil
        ns.Print(key and string.format(L("一键上BUFF快捷键：%s（按一下给下一个人上BUFF）", "One-key buff key: %s"), key) or L("一键上BUFF快捷键已清除", "One-key buff key cleared"))
    elseif why == "taken" then
        pendingKey = key
        ns.Print(string.format(L("%s 现在是「%s」。要顶替就再设一次、按同一个键", "%s is bound to %s. Set it again with the same key to replace"), key, _G["BINDING_NAME_" .. tostring(act)] or tostring(act)))
    elseif why == "combat" then
        ns.Print(L("战斗中不能改键位，脱战后再设", "Can't change keys in combat"))
    end
end
AB._finishBind = finish   -- 测试用
function AB.BeginBind()
    if combat() then ns.Print(L("战斗中不能改键位，脱战后再设", "Can't change keys in combat")); return end
    if not capture then
        local c = CreateFrame("Frame", nil, UIParent)
        c:SetAllPoints(); c:EnableKeyboard(true); c:EnableMouse(true)
        pcall(c.SetPropagateKeyboardInput, c, false)
        c:SetFrameStrata("DIALOG")
        local dim = c:CreateTexture(nil, "BACKGROUND"); dim:SetAllPoints(); dim:SetColorTexture(0, 0, 0, 0.7)
        c.t = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); c.t:SetPoint("CENTER", 0, 20)
        c.t:SetText(L("给「一键上BUFF」按一个键…", "Press a key for One-key buff..."))
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

-- ---------- 刷新 ----------
function AB.Refresh()
    if not ns.db then return nil end
    if combat() then
        if float and float.line then float.line:SetText(AB.NextText(nil)) end   -- 战斗中：属性 / 尺寸 / 显示都不碰，只改字和图标颜色
        AB.Paint(nil, 0)
        return nil
    end
    if not AB.Wanted() then
        AB.Apply(nil)
        AB.last, AB.lastN = nil, 0
        if float then float:Hide() end
        return nil
    end
    if not float then AB.BuildFloat() end
    local nx, n = AB.Next()
    AB.last, AB.lastN = nx, n
    AB.Apply(nx)
    if float then
        float:Show()
        float.line:SetText(AB.NextText(nx, n))
        btn:SetText(AB.BtnText(nx))
        AB.Paint(nx, n)
    end
    return nx, n
end
-- 进战斗那一刻（PLAYER_REGEN_DISABLED 里还能改属性）：改成按当前目标放（战斗前挑的姓名板 / 鼠标指向编号战斗中会指到别人身上）
function AB.OnCombatStart()
    AB.inCombat = true   -- PLAYER_REGEN_DISABLED 时 InCombatLockdown 还是假：文字按战斗写
    AB.ApplyCombat()
    AB.last, AB.lastN = nil, 0
    if float and float.line then float.line:SetText(AB.NextText(nil)) end
    if btn then btn:SetText(AB.BtnText(nil)) end
    AB.Paint(nil, 0)
end
function AB.OnCombatEnd()
    AB.inCombat = nil
    if btn then rawset(btn, "_abAttr", nil) end   -- 状态驱动在受保护环境里改过属性：缓存作废，下一次刷新整组重写
    AB.Refresh()
end

-- ---------- 施法结果（同 PallyBless.lua：错误和「我的 BUFF 施法失败」1 秒内配上才算到这个人头上）----------
local function mine(spellID)
    local t = AB.MyType()
    return t ~= nil and t.ids[tonumber(spellID) or -1] == true
end
local FAIL_BLOCK = { "SPELL_FAILED_LINE_OF_SIGHT", "SPELL_FAILED_OUT_OF_RANGE", "ERR_SPELL_OUT_OF_RANGE", "SPELL_FAILED_UNIT_NOT_INFRONT" }
AB.pendErr, AB.castFailAt = nil, -1e9
function AB.ResolveError(msg)
    local inf = AB.inflight
    if not (inf and type(msg) == "string") or now() - inf.at > 2 then return nil end
    if _G.SPELL_FAILED_LOWLEVEL and msg == _G.SPELL_FAILED_LOWLEVEL then
        AB.tooLow[inf.guid] = { lv = inf.need, at = inf.lv or 0 }
        AB.inflight = nil
        AB.Refresh()
        return "lowlv"
    end
    for _, k in ipairs(FAIL_BLOCK) do
        if _G[k] and msg == _G[k] then
            AB.blocked[inf.guid] = now() + AB.BLOCK
            AB.inflight = nil
            AB.Refresh()
            return "blocked"
        end
    end
    AB.inflight = nil   -- 别的错（公共冷却 / 没蓝）：还是这个人
    AB.Refresh()
    return "other"
end
function AB.OnCastFailed(spellID)
    if not AB.inflight or not mine(spellID) then return nil end
    AB.castFailAt = now()
    local pe = AB.pendErr
    if pe and now() - pe.at <= 1 then AB.pendErr = nil; return AB.ResolveError(pe.msg) end
    return nil
end
function AB.OnError(msg)
    if type(msg) ~= "string" or not AB.inflight then return nil end
    if now() - (AB.castFailAt or -1e9) <= 1 then AB.castFailAt = -1e9; return AB.ResolveError(msg) end
    AB.pendErr = { msg = msg, at = now() }
    return nil
end
function AB.OnCastOk(spellID)
    local inf = AB.inflight
    if not (inf and mine(spellID)) then return nil end
    AB.done[inf.guid] = now() + AB.DONE
    AB.inflight = nil
    -- 记录别越攒越多（主城一刷几百人）：过期的清掉
    local tm = now()
    for k, v in pairs(AB.done) do if v <= tm then AB.done[k] = nil end end
    for k, v in pairs(AB.blocked) do if v <= tm then AB.blocked[k] = nil end end
    return true
end

-- ---------- 事件 ----------
local ev = CreateFrame("Frame")
AB.frame = ev
for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "GROUP_ROSTER_UPDATE",
    "UNIT_AURA", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UNIT_SPELLCAST_SUCCEEDED", "UI_ERROR_MESSAGE", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_FAILED_QUIET", "LEARNED_SPELL_IN_TAB", "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local dirty, acc = false, 0
ev:SetScript("OnUpdate", function(_, el)
    acc = acc + (el or 0)
    if acc < (dirty and AB.DIRTY or AB.IDLE) then return end
    acc = 0
    if not (float and float:IsShown()) then return end
    if combat() then pcall(AB.Paint, nil, 0); return end   -- 战斗中只看蓝够不够（图标变灰），不扫人
    dirty = false
    pcall(AB.Refresh)
end)
function AB.OnEvent(e, a1, a2, a3)
    if not (ns.db and AB.ForMe()) then return end
    if e == "PLAYER_REGEN_DISABLED" then
        if AB.On() then AB.OnCombatStart() end
    elseif e == "PLAYER_REGEN_ENABLED" then
        AB.OnCombatEnd()
    elseif e == "UNIT_SPELLCAST_SUCCEEDED" then
        if a1 == "player" and AB.OnCastOk(a3 or a2) then dirty = true end
    elseif e == "UI_ERROR_MESSAGE" then
        AB.OnError(type(a2) == "string" and a2 or a1)
    elseif e == "UNIT_SPELLCAST_FAILED" or e == "UNIT_SPELLCAST_FAILED_QUIET" then
        if a1 == "player" then AB.OnCastFailed(a3 or a2) end
    elseif e == "PLAYER_ENTERING_WORLD" or e == "LEARNED_SPELL_IN_TAB" or e == "SPELLS_CHANGED" or e == "PLAYER_LEVEL_UP" then
        AB.Refresh()
    else
        if AB.On() then dirty = true end
    end
end
ev:SetScript("OnEvent", function(_, e, ...) AB.OnEvent(e, ...) end)
-- _Class 晚于进世界才加载（开关开着时 ClassStub.lua 登录后条件加载）→ 补跑一次
ns.AddInit(function()
    if IsLoggedIn and IsLoggedIn() then pcall(AB.Refresh) end
end)

-- ---------- 命令：/gi buff give on|off|key（Core.lua 转过来）= /gi 上buff 开|关|键 ----------
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash["上buff"] = function(rest)
    rest = (rest or ""):gsub("^[ \t]+", ""):gsub("[ \t]+$", "")
    if not AB.ForMe() then ns.Print(L("一键上BUFF只给法师 / 牧师 / 德鲁伊用（圣骑士用「职业 → 一键祝福」）", "One-key buff is for mages, priests and druids (Paladins: Class > Blessings)")); return end
    if rest == "键" or rest == "bind" or rest == "key" then AB.BeginBind(); return end
    local on
    if rest == "开" or rest == "on" then on = true elseif rest == "关" or rest == "off" then on = false end
    if on == nil then on = not AB.On() end
    AB.SetOn(on)
    if on then
        local keys = AB.BindKeys()
        ns.Print(L("一键上BUFF：开 —— ", "One-key buff: on - ") .. AB.NextText(AB.last, AB.lastN)
            .. (keys[1] and string.format(L("　快捷键 %s", "   key %s"), keys[1]) or L("　|cff9a9a9a没设快捷键：/gi buff give key 或悬浮框齿轮|r", "   |cff9a9a9ano key: /gi buff give key or the gear|r")))
    else
        ns.Print(L("一键上BUFF：关", "One-key buff: off"))
    end
end
ns.ExtraSlash.autobuff = ns.ExtraSlash["上buff"]

-- 「窗口与提醒」：右键关掉的悬浮框从这里找回（⛔ 关掉后 _Class 不再为它登录加载 → 主插件 ClassStub.lua 要有同 key 占位）
if ns.RegisterWindow then
    ns.RegisterWindow({ key = "autoBuff", order = 57.5, title = function() return L("一键上BUFF悬浮框（法师 / 牧师 / 德鲁伊）", "One-key buff button (Mage / Priest / Druid)") end,
        avail = function() return AB.ForMe() end,
        state = function() return AB.On() and L("开着", "On") or L("已关闭", "Closed") end,
        actions = function()
            local on = AB.On()
            return {
                { text = on and L("关闭", "Turn off") or L("打开", "Turn on"), fn = function() if on then AB.Never() else AB.SetOn(true) end end },
                { text = L("重置位置", "Reset position"), fn = function() AB.ResetPos() end },
            }
        end })
end
