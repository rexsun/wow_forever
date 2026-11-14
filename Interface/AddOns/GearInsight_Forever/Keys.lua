-- 键位手法 · 底座（10-10，docs/forever-keybind-rotation-design.md §1/§6，从正式服 GearInsight_Layout 移植精简）
-- 读键（游戏绑定 + Bartender / ElvUI / Dominos）、技能在不在条上、路 A 左键拿起 / 右键选格放、
-- 备份 / 还原、战斗中排队到脱战。⛔ 不碰宏（无限版宏库在宏库页）。⛔ HOLD（_hold.txt），测完才进包。
local _, ns = ...; ns = _G.GearInsightForever or ns

local K = {}
ns.Keys = K

-- ---------- 动作条：格号 ↔ 绑定命令 ----------
-- 经典布局：1–12 主条；61–72 左下；49–60 右下；25–36 右侧；37–48 右侧 2；145–180 条 5–7（客户端有才算，P0 实测）；
--   73–120 姿态 / 形态 / 潜行页，用主条同位的 ACTIONBUTTON 键
K.BARS = {
    { from = 1, to = 12, cmd = "ACTIONBUTTON" },
    { from = 61, to = 72, cmd = "MULTIACTIONBAR1BUTTON" },
    { from = 49, to = 60, cmd = "MULTIACTIONBAR2BUTTON" },
    { from = 25, to = 36, cmd = "MULTIACTIONBAR3BUTTON" },
    { from = 37, to = 48, cmd = "MULTIACTIONBAR4BUTTON" },
    { from = 145, to = 156, cmd = "MULTIACTIONBAR5BUTTON" },
    { from = 157, to = 168, cmd = "MULTIACTIONBAR6BUTTON" },
    { from = 169, to = 180, cmd = "MULTIACTIONBAR7BUTTON" },
}
local FORM_PAGES = { { 73, 84 }, { 85, 96 }, { 97, 108 }, { 109, 120 } }

-- 调用时再取全局（不在加载时缓存）：测试替换模拟函数也能生效
local function getBindingKeys(cmd)
    local f = GetBindingKey
    if type(cmd) ~= "string" or cmd == "" or not f then return nil end   -- 正式服 09-27 BugSack：命令为空直接传会报 Usage
    local ok, k1, k2 = pcall(f, cmd)
    if not ok then return nil end
    return k1, k2
end
local function bindingKey(cmd) return (getBindingKeys(cmd)) end

function K.SlotCommand(slot)
    for _, b in ipairs(K.BARS) do
        if slot >= b.from and slot <= b.to then return b.cmd .. (slot - b.from + 1) end
    end
    for _, p in ipairs(FORM_PAGES) do
        if slot >= p[1] and slot <= p[2] then return "ACTIONBUTTON" .. (slot - p[1] + 1) end
    end
end

-- 条插件按钮框体 → 格号 → 键（只读；正式服 addonBarKeys 同法）
function K.AddonBarKeys()
    local m = {}
    local function take(btn, name)
        if not btn or not btn.GetAttribute then return end
        local ok, action = pcall(btn.GetAttribute, btn, "action")
        action = (ok and action) or btn._state_action or btn.action
        if type(action) ~= "number" or m[action] then return end
        for _, cmd in ipairs({ btn.keyBoundTarget or false, "CLICK " .. name .. ":Keybind", "CLICK " .. name .. ":LeftButton", "CLICK " .. name .. ":HOTKEY" }) do
            if cmd then
                local k = bindingKey(cmd)
                if k then m[action] = k; return end
            end
        end
    end
    for i = 1, 180 do
        take(_G["BT4Button" .. i], "BT4Button" .. i)
        take(_G["DominosActionButton" .. i], "DominosActionButton" .. i)
    end
    for b = 1, 15 do for i = 1, 12 do local n = "ElvUI_Bar" .. b .. "Button" .. i; take(_G[n], n) end end
    return m
end

function K.SlotKey(slot, abk)
    abk = abk or K.AddonBarKeys()
    return abk[slot] or bindingKey(K.SlotCommand(slot))
end

-- ---------- 技能 ----------
local function spellName(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellName then local ok, n = pcall(C_Spell.GetSpellName, id); if ok and n then return n end end
    if GetSpellInfo then local ok, n = pcall(GetSpellInfo, id); if ok then return n end end
end
K.SpellName = spellName
-- 条目 → 当前客户端能用的法术编号（最高等级）；没学会返回 nil
--   有编号的：先确认学会了（IsPlayerSpell / IsSpellKnown 认第一级编号），再按名字取最高等级；
--   天赋技能没有编号：按客户端语言的名字查（学会了才查得到）
function K.Resolve(e)
    local name = (e.id and spellName(e.id)) or ns.L(e.n, e.nEn or e.n)
    if not name then return nil end
    if e.id then
        local known = (IsPlayerSpell and IsPlayerSpell(e.id)) or (IsSpellKnown and IsSpellKnown(e.id))
        if not known then
            -- 第一级没学（少见）也可能学了高等级：按名字兜底
            local ok, _, _, _, _, _, _, sid = pcall(GetSpellInfo, name)
            if not (ok and sid) then return nil end
            return sid, name
        end
    end
    local ok, _, _, _, _, _, _, sid = pcall(GetSpellInfo, name)
    if ok and sid then return sid, name end
    return e.id, name
end

local function slotInfo(slot)
    if not GetActionInfo then return nil end
    local ok, t, id = pcall(GetActionInfo, slot)
    if not ok or not t then return nil end
    local r = { t = t, id = id }
    if t == "spell" then r.name = spellName(id)
    elseif t == "macro" and GetActionText then r.name = GetActionText(slot) end
    return r
end
K.SlotInfo = slotInfo

-- 10-16 /gi keys diag：形态视图「为啥还是没技能」诊断 —— 本职业数据里每个技能：编号 / 解析到的编号 / 学没学会 / 当前视图能不能用；
--   再列法术书里实际学会、但数据里没有的技能（数据漏了就看这一段）
function K.DiagView()
    local view = K.ActiveView and K.ActiveView()
    local out = { "GIKEYS1", "view=" .. tostring(view and view.key), "cls=" .. tostring(ns.MyClass()), "lv=" .. tostring(UnitLevel and UnitLevel("player")) }
    local seen = {}
    for _, e in ipairs((ns.Data.keys or {})[ns.MyClass()] or {}) do
        local sid, name = K.Resolve(e)
        local kp = e.id and IsPlayerSpell and select(2, pcall(IsPlayerSpell, e.id))
        local ks = e.id and IsSpellKnown and select(2, pcall(IsSpellKnown, e.id))
        local inf = K.InForm(e, view)
        seen[e.n] = true
        if sid or kp or ks then
            out[#out + 1] = string.format("%s#%s>%s:%s%s%s", e.n, tostring(e.id), tostring(sid), kp and "P" or "-", ks and "K" or "-", inf and "F" or "x")
        end
    end
    -- 法术书里学会了、数据里没有的
    local extra = {}
    local SB = C_SpellBook
    if SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo then
        local okn, n = pcall(SB.GetNumSpellBookSkillLines)
        for li = 1, (okn and n or 0) do
            local ok, info = pcall(SB.GetSpellBookSkillLineInfo, li)
            if ok and info then
                for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local ok2, it = pcall(SB.GetSpellBookItemInfo, i, Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0)
                    if ok2 and it and it.name and not seen[it.name] and not it.isPassive then extra[#extra + 1] = it.name .. "#" .. tostring(it.spellID or it.actionID) end
                end
            end
        end
    elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
        for t = 1, GetNumSpellTabs() do
            local _, _, off, num = GetSpellTabInfo(t)
            for i = off + 1, off + num do
                local nm = GetSpellBookItemName(i, BOOKTYPE_SPELL or "spell")
                if nm and not seen[nm] then extra[#extra + 1] = nm end
            end
        end
    end
    out[#out + 1] = "extra=" .. table.concat(extra, "/")
    ns.ShowBox(ns.L("键位诊断", "Keys diag"), ns.L("Ctrl+C 复制发给开发者", "Ctrl+C to copy"), table.concat(out, ";"))
end

-- /gi keys macros：列出条上每个宏格 —— 格号 / 宏名 / GetActionInfo 的 id / 认出的宏序号 / 认出的技能（「宏没识别」时贴这个）
function K.DebugMacros()
    local n = 0
    for _, b in ipairs(K.BARS) do
        for sl = b.from, b.to do
            local info = slotInfo(sl)
            if info and info.t == "macro" then
                n = n + 1
                local names, idx, text = K.SlotMacroSpells(sl, info.id)
                ns.Print(string.format("宏格 %d · 「%s」 · id=%s · 宏序号=%s · 技能：%s", sl, tostring(text), tostring(info.id), tostring(idx),
                    #names > 0 and table.concat(names, "、") or "（没认出来）"))
            end
        end
    end
    if n == 0 then ns.Print("条上没有宏格（GetActionInfo 一个 macro 都没返回）") end
end

-- 宏里放的是哪些技能（10-12 用户截图「宏在上面没识别」：治疗之触鼠标指向宏在条上，键位页还说「不在动作条上」）
--   ① GetMacroSpell：宏此刻会放的技能（按条件算出来的那个）
--   ② 宏正文里所有 /cast /施放 /castsequence /施放序列 的技能名：去掉 [条件]、reset=、!、（等级 N）/(Rank N)，按 ; , 拆开
--   名字和计划里一样按「技能名」对，等级不同也算同一个
local CAST_CMDS = { ["/cast"] = true, ["/施放"] = true, ["/castsequence"] = true, ["/施放序列"] = true, ["/castrandom"] = true, ["/随机施放"] = true }
function K.MacroSpellNames(macroIndex)
    local out, seen = {}, {}
    local function add(n)
        if type(n) ~= "string" or ns.Secret(n) then return end
        -- ⛔ 全角括号别放进 [字符类]：Lua 按字节匹配，会连带吃掉中文字的字节 → 半角 / 全角各 gsub 一次
        n = n:gsub("%b()", ""):gsub("（.-）", ""):gsub("^[ 	]+", ""):gsub("[ 	]+$", ""):gsub("^!", "")
        if n ~= "" and not seen[n] then seen[n] = true; out[#out + 1] = n end
    end
    if GetMacroSpell then
        local ok, a = pcall(GetMacroSpell, macroIndex)
        if ok and a then
            if type(a) == "number" then add(spellName(a)) else add(a) end
        end
    end
    if GetMacroBody then
        local ok, body = pcall(GetMacroBody, macroIndex)
        if ok and type(body) == "string" and not ns.Secret(body) then
            for line in (body .. "\n"):gmatch("([^\n]*)\n") do
                local cmd, args = line:match("^%s*(/%S+)%s*(.*)$")
                if cmd and CAST_CMDS[cmd:lower()] then
                    args = args:gsub("%[[^%]]*%]", ""):gsub("reset=%S+", "")
                    for part in (args .. ";"):gmatch("([^;,]*)[;,]") do add(part) end
                end
            end
        end
    end
    return out
end

-- 宏格 → 宏里的技能名（10-12 第二次截图「宏还是没识别」：12.x 引擎里宏格 GetActionInfo 的 id 不一定是宏序号，
--   可能是宏此刻要放的技能 ID）→ 三路都试：① 格子上的宏名（GetActionText）→ GetMacroIndexByName → 正文
--   ② id 当宏序号（宏名对得上才算）③ id 当技能 ID（spellName 拿得到名字就算）
function K.SlotMacroSpells(slot, id)
    local out, seen = {}, {}
    local function addAll(list) for _, n in ipairs(list) do if not seen[n] then seen[n] = true; out[#out + 1] = n end end end
    local text = GetActionText and GetActionText(slot)
    if type(text) == "string" and ns.Secret(text) then text = nil end
    local idx
    if text and text ~= "" and GetMacroIndexByName then
        local ok, i = pcall(GetMacroIndexByName, text)
        if ok and tonumber(i) and i > 0 then idx = i end
    end
    if not idx and tonumber(id) and GetMacroInfo then
        local ok, mname = pcall(GetMacroInfo, id)
        if ok and mname and (not text or mname == text) then idx = id end
    end
    if idx then addAll(K.MacroSpellNames(idx)) end
    if tonumber(id) and (not idx or idx ~= id) then
        local n = spellName(id)
        if n then addAll({ n }) end
    end
    return out, idx, text
end

-- ---------- 形态视图（10-16 用户「尤其是形态的情况下，上方有切形态的按钮」；数据 KeysFormData.lua，没装 = 老样子）----------
-- 视图 = 键位页选的那个形态（只是看，不改游戏里的形态）：{ key, page, zh, en, d }；page = 主条在该形态下换成的形态页号，nil = 主条本身
-- 10-16 用户「没学的形态先不要放」「注意其他职业也要考虑」：没学会的形态 / 姿态不出按钮。
--   形态技能：熊 5487 / 巨熊 9634、豹 768；防御姿态 71、狂暴姿态 2458（战斗姿态 2457 一级就有）；潜行 1784。
--   先看姿态条（GetShapeshiftFormInfo 第 4 个返回值 = 技能编号），再看 IsPlayerSpell / IsSpellKnown；这几个接口都没有就当学会了
K.FORM_SPELLS = { bear = { 5487, 9634 }, cat = { 768 }, battle = { 2457 }, defensive = { 71 }, berserker = { 2458 }, stealth = { 1784 } }
function K.FormKnown(f)
    local ids = f and K.FORM_SPELLS[f.key]
    if not ids then return true end
    local asked = false
    if GetNumShapeshiftForms and GetShapeshiftFormInfo then
        asked = true
        local okn, n = pcall(GetNumShapeshiftForms)
        for i = 1, (okn and tonumber(n) or 0) do
            local ok, _, _, _, sid = pcall(GetShapeshiftFormInfo, i)
            if ok then for _, id in ipairs(ids) do if sid == id then return true end end end
        end
    end
    for _, fn in ipairs({ IsPlayerSpell or false, IsSpellKnown or false }) do
        if fn then
            asked = true
            for _, id in ipairs(ids) do
                local ok, v = pcall(fn, id)
                if ok and v then return true end
            end
        end
    end
    return not asked
end
-- 只返回学会了的形态；学会的不到 2 个（比如 10 级前的德鲁伊）= 没得切，当没形态处理（页面照老样子）
function K.Forms(cls)
    local d = ns.KeysForms and ns.KeysForms[cls or ns.MyClass()]
    if not d then return nil end
    local out = {}
    for _, f in ipairs(d.forms) do if K.FormKnown(f) then out[#out + 1] = f end end
    if #out < 2 then return nil, d end
    return out, d
end
function K.FormByKey(key, cls)
    for _, f in ipairs((K.Forms(cls)) or {}) do if f.key == key then return f end end
end
-- 现在实际在哪个形态：按 GetBonusBarOffset 对形态页号（没变身 = 0 = 页为 nil 的那个）
function K.CurrentFormKey(cls)
    local fs = K.Forms(cls)
    if not fs then return nil end
    local off = 0
    if GetBonusBarOffset then local ok, v = pcall(GetBonusBarOffset); if ok and type(v) == "number" then off = v end end
    for _, f in ipairs(fs) do if (f.page or 0) == off then return f.key end end
    return fs[1].key
end
K.viewKey = nil   -- 键位页手动选的形态；nil = 跟着实际形态
function K.ActiveView(cls)
    local fs, d = K.Forms(cls)
    if not fs then return nil end
    local f = K.FormByKey(K.viewKey or K.CurrentFormKey(cls), cls) or fs[1]
    return { key = f.key, page = f.page, zh = f.zh, en = f.en, d = d }
end
-- 这个技能在这个形态下能不能用（数据里没列的按职业默认：德鲁伊人形态 / 战士三姿态 / 盗贼普通 + 潜行）
function K.InForm(e, view)
    if not view then return true end
    if e and e.racial then return true end   -- 种族 / 通用技能：各形态都能放
    local sp = view.d.spells or {}
    local list = (e.id and sp[e.id]) or (e.nEn and sp[e.nEn]) or view.d.def or {}
    for _, k in ipairs(list) do if k == view.key then return true end end
    return false
end
K.FORM_PAGES = FORM_PAGES

-- 条上每个技能（按名字，等级不同也算同一个）→ { 格号, 键 }；有键的那格优先；宏里放的技能也算（10-12）
--   view（形态视图）：主条 1–12 只在没变身那个形态算；变身形态只算它自己那一页；别的条（左下 / 右下…）都算 —— 和游戏里该形态下按得到的一致
function K.LiveMap(view)
    local abk = K.AddonBarKeys()
    local m = {}
    local function scan(from, to)
        for sl = from, to do
            local info = slotInfo(sl)
            if info and info.t == "spell" and info.name then
                local k = K.SlotKey(sl, abk)
                local cur = m[info.name]
                if not cur or (not cur.key and k) or (cur.macro and (k or not cur.key)) then m[info.name] = { slot = sl, key = k } end
            elseif info and info.t == "macro" then
                local k = K.SlotKey(sl, abk)
                for _, n in ipairs((K.SlotMacroSpells(sl, info.id))) do
                    local cur = m[n]
                    -- 同一个技能：条上本体优先，宏其次；都在时有键的那格优先
                    if not cur or (cur.macro and not cur.key and k) then m[n] = { slot = sl, key = k, macro = true } end
                end
            end
        end
    end
    if view then
        for _, b in ipairs(K.BARS) do if b.from ~= 1 or not view.page then scan(b.from, b.to) end end
        local pg = view.page and FORM_PAGES[view.page]
        if pg then scan(pg[1], pg[2]) end
        return m, abk
    end
    for _, b in ipairs(K.BARS) do scan(b.from, b.to) end
    for _, p in ipairs(FORM_PAGES) do scan(p[1], p[2]) end
    return m, abk
end

-- ---------- 职业 / 天赋系 ----------
function K.MainTree()
    if not GetTalentTabInfo then return nil, 0 end
    local best, bp = nil, -1
    for i = 1, 3 do
        local ok, a, b, c, d, e = pcall(GetTalentTabInfo, i)
        if ok then
            local pts = 0
            for _, v in ipairs({ a, b, c, d, e }) do   -- 不同客户端返回位置不同：取第一个看着像投点数的整数
                if type(v) == "number" and v >= 0 and v <= 61 and v == math.floor(v) and v ~= i then pts = v; break end
            end
            if pts > bp then best, bp = i, pts end
        end
    end
    return (bp >= 10) and best or nil, bp
end

-- 本职业要上条的技能（按职能行排好；默认不铺：功能 util / 姿态 stance —— 姿态有暴雪姿态条）
K.PLACE_ROLES = { racial = true, main = true, burst = true, interrupt = true, taunt = true, cc = true, defense = true, heal = true, move = true, buff = true }
K.ROLE_NAME = {
    main = { "主循环", "Rotation" }, burst = { "爆发", "Burst" }, interrupt = { "打断", "Interrupt" }, taunt = { "嘲讽", "Taunt" },
    cc = { "控制", "Control" }, defense = { "保命", "Defensive" }, heal = { "治疗", "Healing" }, move = { "位移", "Movement" },
    stance = { "姿态", "Stance" }, racial = { "种族 / 通用", "Racial / General" }, buff = { "增益", "Buffs" }, util = { "其他", "Utility" },
}
-- 10-17 用户「种族天赋技能也放待设置技能里」：种族主动技能 + 法术书「通用」页的主动技能（攻击、《无限》新种族的踏空而行…）
--   来源：①Data.notes 里 k="racial" 的种族天赋名（旧种族）②法术书第一页（通用）里学会的、非被动、不在职业数据里的技能
local function spellIdByName(name)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if ok and type(info) == "table" and info.spellID then return info.spellID, info.name end
    end
    if GetSpellInfo then
        local ok, n, _, _, _, _, _, sid = pcall(GetSpellInfo, name)
        if ok and sid then return sid, n end
    end
end
local function isPassive(sid)
    if C_Spell and C_Spell.IsSpellPassive then local ok, v = pcall(C_Spell.IsSpellPassive, sid); if ok then return v end end
    if IsPassiveSpell then local ok, v = pcall(IsPassiveSpell, sid); if ok then return v end end
    return false
end
local function known(sid) return (IsPlayerSpell and IsPlayerSpell(sid)) or (IsSpellKnown and IsSpellKnown(sid)) end
function K.RacialEntries(classNames)
    local out, seen = {}, {}
    local function add(sid, name)
        if not sid or seen[sid] or (classNames and classNames[name]) then return end
        if not known(sid) or isPassive(sid) then return end
        seen[sid] = true
        out[#out + 1] = { e = { id = sid, n = name, r = "racial", racial = true }, id = sid, name = name, role = "racial" }
    end
    for key, nt in pairs((ns.Data and ns.Data.notes) or {}) do
        if type(nt) == "table" and nt.k == "racial" then
            local sid, name = spellIdByName(key)
            add(sid, name)
        end
    end
    local SB = C_SpellBook
    if SB and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo then
        local ok, info = pcall(SB.GetSpellBookSkillLineInfo, 1)
        if ok and info and info.numSpellBookItems then
            local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
            for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local ok2, it = pcall(SB.GetSpellBookItemInfo, i, bank)
                if ok2 and it and it.spellID and not it.isPassive then add(it.spellID, it.name) end
            end
        end
    elseif GetSpellTabInfo and GetSpellBookItemName and GetSpellBookItemInfo then
        local _, _, off, num = GetSpellTabInfo(1)
        for i = (off or 0) + 1, (off or 0) + (num or 0) do
            local nm = GetSpellBookItemName(i, BOOKTYPE_SPELL or "spell")
            local _, sid = GetSpellBookItemInfo(i, BOOKTYPE_SPELL or "spell")
            if nm and sid then add(sid, nm) end
        end
    end
    return out
end

function K.Plan(cls)
    cls = cls or ns.MyClass()
    local out, names = {}, {}
    for _, e in ipairs((ns.Data.keys or {})[cls] or {}) do
        local sid, name = K.Resolve(e)
        if sid then out[#out + 1] = { e = e, id = sid, name = name, role = e.r }; names[name] = true end
    end
    if cls == ns.MyClass() then
        local ok, extra = pcall(K.RacialEntries, names)
        for _, p in ipairs(ok and extra or {}) do out[#out + 1] = p end
    end
    return out
end

-- 计划里的技能：在不在条上、什么键
function K.Status(cls, view)
    local live = K.LiveMap(view)
    local rows, missing = {}, 0
    for _, p in ipairs(K.Plan(cls)) do
        if K.InForm(p.e, view) then
        local l = live[p.name]
        p.slot, p.key = l and l.slot, l and l.key
        p.placeable = K.PLACE_ROLES[p.role] or false
        if not p.slot and p.placeable then missing = missing + 1 end
        rows[#rows + 1] = p
        end
    end
    return rows, missing
end

-- ---------- 键池（正式服同一套：左手手感从好到差；裸 W A S D Q E 不参与） ----------
local KEY_POOL = {}
do
    for _, k in ipairs({ "1", "2", "3", "4", "5", "R", "F", "T", "G", "Z", "X", "C", "V", "B" }) do KEY_POOL[#KEY_POOL + 1] = k end
    for _, m in ipairs({ "SHIFT-", "ALT-", "CTRL-" }) do
        for _, k in ipairs({ "1", "2", "3", "4", "5", "Q", "E", "R", "F", "T", "G", "Z", "X", "C", "V", "A", "D", "S", "W" }) do KEY_POOL[#KEY_POOL + 1] = m .. k end
    end
    for i = 1, 4 do KEY_POOL[#KEY_POOL + 1] = "F" .. i end
    for _, k in ipairs({ "6", "SHIFT-6", "ALT-6", "CTRL-6", "`", "SHIFT-`" }) do KEY_POOL[#KEY_POOL + 1] = k end
    for i = 5, 12 do KEY_POOL[#KEY_POOL + 1] = "F" .. i end
    for _, k in ipairs({ "7", "8", "9", "0", "-", "=" }) do KEY_POOL[#KEY_POOL + 1] = k end
end
K.KEY_POOL = KEY_POOL
local function isOurCmd(cmd) return cmd and (cmd:match("^ACTIONBUTTON%d+$") or cmd:match("^MULTIACTIONBAR%dBUTTON%d+$")) end
-- ⛔ 10-16 用户截图（主条键成了 1 3 4 ` 5…）：「第一动作条的数字都不准设置变动，是技能随动作条放，否则多姿态容易乱」
--   主动作条 ACTIONBUTTON1–12 的键（1–9 0 - =）锁死：插件不改它们的键、也不把它们的键挪给别的格；技能往主条格子里放就行。
--   姿态 / 形态页共用主条的键，主条键一乱，每个姿态都跟着乱。
local function isMainCmd(cmd) return type(cmd) == "string" and cmd:match("^ACTIONBUTTON%d+$") ~= nil end
K.IsMainCmd = isMainCmd
K.MAIN_DEFAULT = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=" }
-- 键能不能给动作条用：没绑 / 绑在动作条格上 = 可以；绑在移动 / 界面等别的功能上 = 不碰
function K.KeyFree(k)
    if not GetBindingAction then return false end
    local ok, cmd = pcall(GetBindingAction, k)
    cmd = ok and cmd or nil
    return not cmd or cmd == "" or (isOurCmd(cmd) and not isMainCmd(cmd))
end

-- ---------- 战斗中排队 ----------
local pending
local qf = CreateFrame("Frame")
qf:RegisterEvent("PLAYER_REGEN_ENABLED")
qf:SetScript("OnEvent", function()
    if pending then local f = pending; pending = nil; pcall(f) end
end)
local function outOfCombat(fn, what)
    if InCombatLockdown and InCombatLockdown() then
        pending = fn
        ns.Print(ns.L("战斗中不能改动作条，脱战后自动" .. what, "Can't change action bars in combat - will " .. what .. " after combat"))
        return false
    end
    fn()
    return true
end

local function saveBindings()
    if SaveBindings then pcall(SaveBindings, (GetCurrentBindingSet and GetCurrentBindingSet()) or 2) end
end

-- ---------- 备份 / 还原（操作前自动存；留 10 份；只管动作条格和动作条绑定） ----------
local function allSlots()
    local t = {}
    for _, b in ipairs(K.BARS) do for s = b.from, b.to do t[#t + 1] = s end end
    for _, p in ipairs(FORM_PAGES) do for s = p[1], p[2] do t[#t + 1] = s end end
    return t
end
local function allCmds()
    local t = {}
    for _, b in ipairs(K.BARS) do for i = 1, 12 do t[#t + 1] = b.cmd .. i end end
    return t
end
function K.Backup(reason)
    ns.db.keysBackups = ns.db.keysBackups or {}
    local snap = { at = time(), cls = ns.MyClass(), name = UnitName("player"), why = reason or "", slots = {}, binds = {} }
    for _, s in ipairs(allSlots()) do
        local info = slotInfo(s)
        if info then snap.slots[s] = { t = info.t, id = info.id, n = info.name } end
    end
    for _, c in ipairs(allCmds()) do
        local k1, k2 = getBindingKeys(c)
        if k1 or k2 then snap.binds[c] = { k1, k2 } end
    end
    table.insert(ns.db.keysBackups, 1, snap)
    while #ns.db.keysBackups > 10 do table.remove(ns.db.keysBackups) end
    return snap
end

local function placeSpell(id, slot)
    if not (PickupSpell and PlaceAction) then return false end
    if ClearCursor then ClearCursor() end
    local ok = pcall(PickupSpell, id)
    if not ok then return false end
    pcall(PlaceAction, slot)
    if ClearCursor then ClearCursor() end
    return true
end
local function clearSlot(slot)
    if not (PickupAction and HasAction) then return end
    if HasAction(slot) then pcall(PickupAction, slot); if ClearCursor then ClearCursor() end end
end

function K.Restore(snap)
    if not snap then return false end
    if snap.cls ~= ns.MyClass() then
        ns.Print(ns.L("这份备份是别的职业的，不还原", "That backup is for another class - not restored"))
        return false
    end
    return outOfCombat(function()
        for _, s in ipairs(allSlots()) do
            local want = snap.slots[s]
            local have = slotInfo(s)
            local same = want and have and want.t == have.t and want.id == have.id
            if not same then
                clearSlot(s)
                if want then
                    if want.t == "spell" then placeSpell(want.id, s)
                    elseif want.t == "macro" and want.n and PickupMacro then if ClearCursor then ClearCursor() end; pcall(PickupMacro, want.n); pcall(PlaceAction, s); if ClearCursor then ClearCursor() end
                    elseif want.t == "item" and PickupItem then if ClearCursor then ClearCursor() end; pcall(PickupItem, want.id); pcall(PlaceAction, s); if ClearCursor then ClearCursor() end end
                end
            end
        end
        if SetBinding then
            for _, c in ipairs(allCmds()) do
                local k1, k2 = getBindingKeys(c)
                for _, k in ipairs({ k1, k2 }) do if k then pcall(SetBinding, k) end end
            end
            for c, ks in pairs(snap.binds) do for _, k in ipairs(ks) do if k then pcall(SetBinding, k, c) end end end
            saveBindings()
        end
        ns.Print(ns.L("已还原到备份：", "Restored backup: ") .. date("%m-%d %H:%M", snap.at))
    end, ns.L("还原", "restore"))
end

-- ---------- 放格 ----------
-- 路 A 的目标格：已经有键的空格优先（主条 → 左下 → 右下 → 右侧 → 右侧 2）；都没键就第一个空格，回头再分键
local PLACE_ORDER = { 1, 2, 3, 4, 5 }   -- K.BARS 下标
local function firstEmpty(withKey, abk)
    for _, bi in ipairs(PLACE_ORDER) do
        local b = K.BARS[bi]
        for s = b.from, b.to do
            if not (HasAction and HasAction(s)) and (not withKey or K.SlotKey(s, abk)) then return s end
        end
    end
end

-- 给没键的格分一个池子里的空键；used = 本次已分出去的
local function assignKey(slot, used)
    if not SetBinding then return nil end
    local cmd = K.SlotCommand(slot)
    if not cmd or slot > 72 and slot < 145 then return nil end   -- 姿态页跟主条共用键，不单独绑
    if isMainCmd(cmd) then return nil end                         -- 主条键锁死，不分键
    for _, k in ipairs(KEY_POOL) do
        if not used[k] and K.KeyFree(k) then
            local holder = GetBindingAction and GetBindingAction(k)
            if not holder or holder == "" then
                used[k] = true
                pcall(SetBinding, k, cmd)
                return k
            end
        end
    end
end

-- 路 A：点「—」= 把这个技能拿到鼠标上，玩家自己点动作条格子放下（10-16 用户截图「点一下应该是拿到鼠标上」：
--   原来自动找空格放 + 分键，熊形态下放到了人形态的格子上，点一次放一次，聊天框刷了一排「已放上 槌击」）。
--   ⛔ 不自动放、不自动绑键（同 feedback：键位只许逐个设置）
function K.PlaceMissing(p)
    return outOfCombat(function()
        if not (p and p.id) then return end
        if ClearCursor then ClearCursor() end
        local pick = (C_Spell and C_Spell.PickupSpell) or PickupSpell
        local ok = pick and pcall(pick, p.id)
        if not ok then
            ns.Print(string.format(ns.L("拿不起「%s」：去技能书里拖到动作条上", "Can't pick up %s - drag it from your spellbook"), p.name or "?"))
            return
        end
        -- 10-16 截图：点一下刷 4 行 → 同一技能 2 秒内只说一次；想放进某个形态的页：右键选格
        local now = (GetTime and GetTime()) or 0
        K._pickSay = K._pickSay or {}
        if not K._pickSay[p.name or "?"] or now - K._pickSay[p.name or "?"] > 2 then
            K._pickSay[p.name or "?"] = now
            ns.Print(string.format(ns.L("「%s」已在鼠标上：点动作条上的格子放下（想放进某个形态的那一页：右键这个技能选格）", "%s is on your cursor: click an action slot (right-click the spell to choose a form slot)"), p.name or "?"))
        end
    end, ns.L("拿到鼠标上", "pick it up"))
end

-- ---------- 10-16 指定格放技能（键位页「放到哪一格」面板 / 形态问询 / 录键时按了主条键）----------
-- 用户：「切换状态，所有这个状态能用的技能都要能设置才对」「设置 123456 的时候，多弹出一个对话框问是设置给哪个形态的」
--   主条键（1–9 0 - =）锁死不改；「放到第 n 个位置」= 放进所选形态那一页的第 n 格（人形态 / 普通 / 没形态 = 主条本身）。
function K.ViewOf(formKey, cls)
    local fs, d = K.Forms(cls)
    if not fs then return nil end
    local f = K.FormByKey(formKey, cls)
    if not f then return nil end
    return { key = f.key, page = f.page, zh = f.zh, en = f.en, d = d }
end
-- 10-16 用户「各形态公用技能要列出来」：这个技能在哪些学会的形态能用（2 个以上 = 公用）
function K.SharedForms(p, cls)
    local fs = K.Forms(cls)
    if not (fs and p and p.e) then return nil end
    local out = {}
    for _, f in ipairs(fs) do
        if K.InForm(p.e, K.ViewOf(f.key, cls)) then out[#out + 1] = f end
    end
    return out
end
-- 主条第 n 个位置（键 = 主条第 n 格的键）在某形态下实际是哪一格
function K.MainPosSlot(n, view)
    local pg = view and view.page and FORM_PAGES[view.page]
    return pg and (pg[1] + n - 1) or n
end
-- 主条第几个位置用的是这个键（不是主条的键返回 nil）
function K.MainPosOfKey(key)
    if not key then return nil end
    for i = 1, 12 do
        local k1, k2 = getBindingKeys("ACTIONBUTTON" .. i)
        if k1 == key or k2 == key then return i end
    end
    return nil
end
-- 学会的形态，以及这个技能在各形态能不能用（形态问询框用）；没形态 / 只学会一个 → nil
function K.FormChoices(p, cls)
    local fs = K.Forms(cls)
    if not fs or #fs < 2 then return nil end
    local out = {}
    for _, f in ipairs(fs) do
        local v = K.ViewOf(f.key, cls)
        out[#out + 1] = { view = v, usable = (not (p and p.e)) or K.InForm(p.e, v) }
    end
    return out
end
-- 技能放进第 slot 格（脱战才放；战斗中排到脱战）。同一技能 2 秒内只打印一次（10-16 截图：点一下刷 4 行）
local lastSay = {}
function K.PlaceSpellAt(p, slot, where)
    return outOfCombat(function()
        if not (p and p.id and slot and PlaceAction) then return end
        local before = slotInfo(slot)
        if ClearCursor then ClearCursor() end
        local pick = (C_Spell and C_Spell.PickupSpell) or PickupSpell
        local ok = pick and pcall(pick, p.id)
        if not ok then
            ns.Print(string.format(ns.L("拿不起「%s」：去技能书里拖到动作条上", "Can't pick up %s - drag it from your spellbook"), p.name or "?"))
            return
        end
        pcall(PlaceAction, slot)
        if ClearCursor then ClearCursor() end
        -- 10-17「把这个技能移动过去」：p.moveFrom = 原来那格 → 放好新格后把原格清掉（原格还是这个技能才清）
        local moved = ""
        local from = p.moveFrom
        if from and from ~= slot then
            local old = slotInfo(from)
            if old and old.name == p.name and PickupAction then
                pcall(PickupAction, from)
                if ClearCursor then ClearCursor() end
                moved = string.format(ns.L("（从第 %d 格移过来）", " (moved from slot %d)"), from)
            end
        end
        local now = (GetTime and GetTime()) or 0
        local key = (p.name or "?") .. ":" .. slot
        if not lastSay[key] or now - lastSay[key] > 2 then
            lastSay[key] = now
            local rep = (before and before.name and before.name ~= p.name) and string.format(ns.L("（替换了「%s」）", " (replaced %s)"), before.name) or ""
            ns.Print(string.format(ns.L("「%s」已放到%s%s", "%s placed: %s%s"), p.name or "?", where or string.format(ns.L("第 %d 格", "slot %d"), slot), rep .. moved))
        end
        if K.OnChanged then K.OnChanged() end
    end, ns.L("放上去", "place it"))
end

-- 10-16 用户「删掉，不要这个按钮了」：路 B 一键全铺 / 全部重新分键 去掉（键位只许逐个设置）

-- ---------- 键位页分组（10-12 照正式服 LayoutPage 10-10 重构：前 5 行 = 手法助手 5 轨，其余折叠成「其他」）----------
--   正式服：主循环 / 短冷却(<60s) / 大招(≥60s) / 生存 / 控制(打断 → 控制 → 嘲讽)；位移 / 姿态 / 团队 / 功能 … 收进「其他」。
--   《无限》差异：治疗职业的治疗技能就是主力 → 「治疗」单独一行常显（正式服那边治疗在 WCL 主循环里，这里没有 WCL 数据）。
K.GROUPS = {
    { key = "core", n = { "主循环", "Rotation" }, d = { "手法里要一直按的；对应手法页的主推", "Pressed all the time; matches the rotation page" }, c = { 0.886, 0.722, 0.361 } },
    { key = "short", n = { "短冷却", "Short CDs" }, d = { "冷却不到 60 秒的爆发技能", "Burst spells with a cooldown under 60s" }, c = { 0.541, 0.706, 1 } },
    { key = "major", n = { "大招", "Major CDs" }, d = { "冷却 60 秒以上的爆发技能", "Burst spells with a 60s+ cooldown" }, c = { 0.835, 0.549, 1 } },
    { key = "def", n = { "生存", "Defensive" }, d = { "减伤、保命、自疗", "Damage reduction and self-heals" }, c = { 0.247, 0.780, 0.627 } },
    { key = "ctrl", n = { "控制", "Control" }, d = { "打断 > 控制 > 嘲讽", "Interrupt -> control -> taunt" }, c = { 1, 0.42, 0.36 } },
    { key = "heal", n = { "治疗", "Healing" }, d = { "治疗法术", "Heals" }, c = { 0.2, 0.9, 0.4 } },
    { key = "racial", n = { "种族 / 通用", "Racial / General" }, d = { "种族天赋和攻击这类通用技能，各形态都能放", "Racial and general abilities, usable in every form" }, c = { 0.95, 0.75, 0.45 } },
    { key = "misc", n = { "其他", "Other" }, d = { "位移 / 增益 / 姿态 / 功能", "Movement / buffs / stances / utility" }, c = { 0.64, 0.66, 0.71 }, fold = true },
}
local CTRL_SUB = { interrupt = 1, cc = 2, taunt = 3 }
function K.GroupOf(p)
    local r = p and (p.role or (p.e and p.e.r))
    if r == "main" then return "core" end
    if r == "burst" then return (((p.e and p.e.cd) or 0) >= 60) and "major" or "short" end
    if r == "defense" then return "def" end
    if r == "heal" then return "heal" end
    if r == "racial" then return "racial" end
    if CTRL_SUB[r] then return "ctrl" end
    return "misc"
end
-- K.Status 的行 → 按 K.GROUPS 分好组：{ {g=组定义, items={...}}, ... }（空组也返回，调用方自己跳过）
function K.Grouped(rows)
    local out, by = {}, {}
    for _, g in ipairs(K.GROUPS) do local x = { g = g, items = {} }; out[#out + 1] = x; by[g.key] = x end
    for i, p in ipairs(rows or {}) do p._i = i; local x = by[K.GroupOf(p)]; x.items[#x.items + 1] = p end
    local ctrl = by.ctrl.items
    table.sort(ctrl, function(a, b)
        local sa, sb = CTRL_SUB[a.role] or 9, CTRL_SUB[b.role] or 9
        if sa ~= sb then return sa < sb end
        return a._i < b._i
    end)
    return out
end

-- ---------- 改键（10-12 照正式服 AssignSlotKey 规则：新键直接拿走，原格置空，不交换、不补第三个键）----------
--   正式服是「计划键」（点「将插件建议实现到动作条」才绑）；《无限》版键位页一直是实况（保留你的键位），这里直接 SetBinding。
--   10-12 用户截图「Z 现在是取出/收起武器，不抢」→「这个不能直接设置顶替吗」：
--   键被别的功能占着 → 直接顶替（那个功能变成没键，返回第 2 个值 = 被顶掉的命令，界面打印出来，记进 K.Stolen 可还原）；
--   ⛔ 只有移动 / 跳跃 / 聊天 / 菜单这类「顶了人就动不了、打不了字」的键不顶（返回 "taken"），免得一套模板把 W 改没了。
local PROTECT = { MOVEFORWARD = true, MOVEBACKWARD = true, TURNLEFT = true, TURNRIGHT = true, STRAFELEFT = true, STRAFERIGHT = true,
    -- 10-12 用户截图「R 是回复对话，不顶替」→「是没权限吗」：回复密语（REPLY / REPLY2）很少用，R 是技能常用键 → 不再保护
    JUMP = true, TOGGLEAUTORUN = true, MOVEANDSTEER = true, OPENCHAT = true, OPENCHATSLASH = true, TOGGLEGAMEMENU = true,
    SCREENSHOT = true }
K.PROTECT = PROTECT
-- 被顶掉的原功能：{ [键] = 原命令 }，K.RestoreStolen() 一键放回（账号存档，按角色分开）
function K.StolenTable()
    if not ns.db then return {} end
    ns.db.keysStolen = ns.db.keysStolen or {}
    local ck = (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
    ns.db.keysStolen[ck] = ns.db.keysStolen[ck] or {}
    return ns.db.keysStolen[ck]
end
function K.RestoreStolen()
    if InCombatLockdown and InCombatLockdown() then return nil, "combat" end
    local t, n = K.StolenTable(), 0
    for key, cmd in pairs(t) do
        local ok, cur = pcall(GetBindingAction or function() end, key)
        cur = ok and cur or nil
        -- 这个键现在还在动作条上（是我们顶的）或者空着 → 放回原功能；用户后来自己改别的了就不动
        if not cur or cur == "" or isOurCmd(cur) then pcall(SetBinding, key, cmd); n = n + 1 end
        t[key] = nil
    end
    if n > 0 then saveBindings(); if K.OnChanged then K.OnChanged() end end
    return n
end
--   key = false：解掉这一格的键（Backspace）。返回 ok, holderCmd 或 nil, 原因, 占用命令
function K.AssignSlotKey(slot, key)
    if InCombatLockdown and InCombatLockdown() then return nil, "combat" end
    if not SetBinding then return nil, "api" end
    local cmd = slot and K.SlotCommand(slot)
    if not cmd then return nil, "nocmd" end
    if isMainCmd(cmd) then return nil, "mainlocked" end
    local holder, stolen
    if key then
        local ok, act = pcall(GetBindingAction or function() end, key)
        act = ok and act or nil
        if isMainCmd(act) then return nil, "mainkey", act end
        if act and act ~= "" and act ~= cmd then
            if not isOurCmd(act) then
                if PROTECT[act] then return nil, "taken", act end
                stolen = act
                local t = K.StolenTable()
                if t[key] == nil then t[key] = act end   -- 只记第一次顶掉的原功能（顶来顶去也能还原到最初）
            end
            holder = act
            pcall(SetBinding, key)
        end
    end
    local k1, k2 = getBindingKeys(cmd)
    if k1 and k1 ~= key then pcall(SetBinding, k1) end
    if k2 and k2 ~= key then pcall(SetBinding, k2) end
    if key then
        local ok, r = pcall(SetBinding, key, cmd)
        if not ok or r == false then
            if holder then pcall(SetBinding, key, holder) end
            return nil, "bad"
        end
    end
    saveBindings()
    if K.OnChanged then K.OnChanged() end
    return true, holder, stolen and "stolen" or nil
end

-- ---------- 10-16 虚拟键盘「左键设置，右键清除」用 ----------
-- 这个键现在绑着什么、是不是移动 / 聊天这类保护功能
function K.KeyAction(key)
    if not (key and GetBindingAction) then return nil, false end
    local ok, act = pcall(GetBindingAction, key)
    act = ok and act or nil
    if act == "" then act = nil end
    return act, (act and PROTECT[act]) and true or false
end
-- 清掉第 slot 格的动作（先备份）；where = 聊天框里怎么称呼这一格
function K.ClearSlot(slot, where)
    return outOfCombat(function()
        if not (slot and PickupAction) then return end
        local before = slotInfo(slot)
        if not before then
            ns.Print(string.format(ns.L("%s本来就是空的", "%s is already empty"), where or string.format(ns.L("第 %d 格", "slot %d"), slot)))
            return
        end
        K.Backup(ns.L("清除 ", "clear ") .. (before.name or ""))
        if ClearCursor then ClearCursor() end
        pcall(PickupAction, slot)
        if ClearCursor then ClearCursor() end
        ns.Print(string.format(ns.L("已清除%s：%s", "Cleared %s: %s"), where or string.format(ns.L("第 %d 格", "slot %d"), slot), before.name or "?"))
        if K.OnChanged then K.OnChanged() end
    end, ns.L("清除", "clear it"))
end
-- 解开一个键（⛔ 主条键 / 移动聊天键不解）
function K.UnbindKey(key)
    if InCombatLockdown and InCombatLockdown() then return nil, "combat" end
    local act, prot = K.KeyAction(key)
    if not act then return nil, "free" end
    if isMainCmd(act) then return nil, "mainkey", act end
    if prot then return nil, "taken", act end
    pcall(SetBinding, key)
    saveBindings()
    if K.OnChanged then K.OnChanged() end
    return true, act
end
-- 10-16 用户「右键清除技能的所有快捷键设置并放回法术书」：
-- 这个键现在放的是哪个技能（1 至 = 按所看形态那一页的同位格，那格空就看主条本格；别的键看它绑的那格）
function K.SpellOfKey(key, view)
    if not key then return nil end
    local n = K.MainPosOfKey(key)
    local sl
    if n then
        sl = K.MainPosSlot(n, view)
        if not slotInfo(sl) then sl = n end
    else
        local byKey = K.KeyMap(view)
        sl = byKey and byKey[key]
    end
    local info = sl and slotInfo(sl)
    if info and info.t == "spell" and info.name then return info, sl end
    return nil, sl
end
-- 把这个技能从所有格子（1–120、145–180，含各形态页）清掉，解开指向这些格的非主条键（主条键 1 至 = 锁死不动）；先备份
--   技能本身就只剩法术书里（= 放回法术书）
function K.ClearSpellEverywhere(name)
    return outOfCombat(function()
        if not (name and PickupAction) then return end
        local slots = {}
        for _, rg in ipairs({ { 1, 120 }, { 145, 180 } }) do
            for sl = rg[1], rg[2] do
                local info = slotInfo(sl)
                if info and info.t == "spell" and info.name == name then slots[#slots + 1] = sl end
            end
        end
        if #slots == 0 then
            ns.Print(string.format(ns.L("「%s」不在任何格子上", "%s isn't on any slot"), name))
            return
        end
        K.Backup(ns.L("清除 ", "clear ") .. name)
        local keys = {}
        for _, sl in ipairs(slots) do
            if ClearCursor then ClearCursor() end
            pcall(PickupAction, sl)
            if ClearCursor then ClearCursor() end
            local cmd = K.SlotCommand(sl)
            if cmd and not isMainCmd(cmd) then
                local k1, k2 = getBindingKeys(cmd)
                for _, k in ipairs({ k1, k2 }) do
                    if k then pcall(SetBinding, k); keys[#keys + 1] = k end
                end
            end
        end
        saveBindings()
        ns.Print(string.format(ns.L("已把「%s」从 %d 个格子清掉%s（主动作条的键 1 至 = 不动）；还原上次可以恢复",
            "Cleared %s from %d slots%s (main bar keys 1 to = untouched); Undo restores it"), name, #slots,
            #keys > 0 and string.format(ns.L("，解开了键 %s", ", unbound %s"), table.concat(keys, " ")) or ""))
        if K.OnChanged then K.OnChanged() end
    end, ns.L("清除", "clear it"))
end
-- 左右下条第一个空格（键盘「设置」给空闲键找地方用）
function K.FirstFreeSideSlot()
    for _, rg in ipairs({ { 61, 72 }, { 49, 60 } }) do
        for s = rg[1], rg[2] do
            if not (HasAction and HasAction(s)) and not K.SlotKey(s) then return s end
        end
    end
end

-- 主动作条恢复默认键 1–9 0 - =：只在玩家点按钮时调；那个键被别的动作条格占着就先解开（是动作条格才动），
--   被移动 / 聊天等别的功能占着的跳过不抢。返回 改了几个, 跳过的键表
function K.ResetMainBar()
    if InCombatLockdown and InCombatLockdown() then return nil, "combat" end
    if not (SetBinding and GetBindingAction) then return nil, "api" end
    K.Backup(ns.L("主动作条恢复默认键", "reset main bar keys"))
    local n, skipped = 0, {}
    for i, k in ipairs(K.MAIN_DEFAULT) do
        local cmd = "ACTIONBUTTON" .. i
        local ok, act = pcall(GetBindingAction, k)
        act = ok and act or ""
        if act == cmd then
            -- 已经对
        elseif act == "" or isOurCmd(act) then
            local k1, k2 = getBindingKeys(cmd)
            if k1 and k1 ~= k then pcall(SetBinding, k1) end
            if k2 and k2 ~= k then pcall(SetBinding, k2) end
            if act ~= "" then pcall(SetBinding, k) end
            pcall(SetBinding, k, cmd)
            n = n + 1
        else
            skipped[#skipped + 1] = k
        end
    end
    saveBindings()
    if K.OnChanged then K.OnChanged() end
    return n, skipped
end

-- 键位模板（正式服 GearInsight.KEY_TEMPLATES 同一套）：一组从左到右套一套键
K.KEY_TEMPLATES = {
    { key = "num", label = "1 2 3 4 5 6", keys = { "1", "2", "3", "4", "5", "6" } },
    { key = "qer", label = "Q E R F T G", keys = { "Q", "E", "R", "F", "T", "G" } },
    { key = "zxc", label = "Z X C V B", keys = { "Z", "X", "C", "V", "B" } },
    { key = "shift", label = "Shift + 1-6", keys = { "SHIFT-1", "SHIFT-2", "SHIFT-3", "SHIFT-4", "SHIFT-5", "SHIFT-6" } },
    { key = "alt", label = "Alt + 1-6", keys = { "ALT-1", "ALT-2", "ALT-3", "ALT-4", "ALT-5", "ALT-6" } },
    { key = "ctrl", label = "Ctrl + 1-6", keys = { "CTRL-1", "CTRL-2", "CTRL-3", "CTRL-4", "CTRL-5", "CTRL-6" } },
    { key = "shiftq", label = "Shift + Q E R F T G", keys = { "SHIFT-Q", "SHIFT-E", "SHIFT-R", "SHIFT-F", "SHIFT-T", "SHIFT-G" } },
    { key = "fkeys", label = "F1 - F6", keys = { "F1", "F2", "F3", "F4", "F5", "F6" } },
    { key = "mouse", label = { "鼠标侧键 / 中键 / 滚轮", "Mouse buttons / wheel" }, keys = { "BUTTON4", "BUTTON5", "BUTTON3", "MOUSEWHEELUP", "MOUSEWHEELDOWN", "SHIFT-BUTTON4", "SHIFT-BUTTON5" } },
}
-- 返回 套上的格数, 被移动 / 聊天这类保护键占着跳过的键表, 顶替了别的功能的键表
function K.ApplyKeyTemplate(slots, tpl)
    local n, skipped, stolen = 0, {}, {}
    for i, sl in ipairs(slots or {}) do
        local k = tpl and tpl.keys[i]
        if not k then break end
        local ok, why, st = K.AssignSlotKey(sl, k)
        if ok then
            n = n + 1
            if st == "stolen" then stolen[#stolen + 1] = k end
        elseif why == "taken" or why == "mainkey" or why == "mainlocked" then skipped[#skipped + 1] = k elseif why == "combat" then break end
    end
    return n, skipped, stolen
end

-- 键 → 格（虚拟键盘用）：条插件按钮的键优先，其次游戏绑定（每个命令两个键都算）
--   主条 1–12 在变身 / 姿态时显示的是形态页那一格（GetBonusBarOffset）
--   view（形态视图）：按那个形态算（不看实际形态）；第二个返回值 = 主条 1–12 的键（随形态变的键）
function K.KeyMap(view)
    local abk = K.AddonBarKeys()
    local m = {}
    for s, k in pairs(abk) do if not m[k] then m[k] = s end end
    for _, b in ipairs(K.BARS) do
        for i = 1, 12 do
            local k1, k2 = getBindingKeys(b.cmd .. i)
            if k1 and not m[k1] then m[k1] = b.from + i - 1 end
            if k2 and not m[k2] then m[k2] = b.from + i - 1 end
        end
    end
    local off = 0
    if view then off = view.page or 0
    elseif GetBonusBarOffset then local ok, v = pcall(GetBonusBarOffset); if ok and type(v) == "number" then off = v end end
    local formKeys = {}
    for k, s in pairs(m) do if s >= 1 and s <= 12 then formKeys[k] = true end end
    if off > 0 and off <= #FORM_PAGES then
        for k, s in pairs(m) do if s >= 1 and s <= 12 then m[k] = FORM_PAGES[off][1] + s - 1 end end
    end
    return m, formKeys
end
K.IsOurCmd = isOurCmd

-- 测试用
K._firstEmpty = firstEmpty
K._assignKey = assignKey
