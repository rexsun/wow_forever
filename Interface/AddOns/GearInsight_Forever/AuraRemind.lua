-- HOLD：圣骑士「光环没开就提醒」（11-15 用户「骑士加个光环提醒，没开就提醒」），游戏内实测前不进发行包
--
-- ① 放在哪：职业子插件 GearInsight_Forever_Class（和一键祝福 PallyBless.lua 同一处，单独一个文件好按文件 HOLD）
--   · 里面有安全按钮（点一下施放光环），_Class 战斗中一律不加载（ModStub.lua noCombat）→ 按钮只在脱战时建、属性只在脱战时设
--   · 拆分包：圣骑士登录（学会了光环、提醒开着）时 ClassStub.lua 条件加载 _Class；合并包（默认发版形态）登录就在
-- ② 光环数据（⛔ 名字 / id 以开服客户端技能书 services/dashboard/static/data/forever/spellbook.json 为准，DataClass.lua 的 Paladin keys 同一批）：
--   虔诚 / 惩罚 / 专注 / 暗影抗性 / 冰霜抗性 / 火焰抗性光环，逐级 id + 学习等级；无限技能书 / 天赋树里没有新增光环（圣洁光环天赋也没有）
-- ③ 「开没开」：经典里圣骑士光环在姿态条上 —— GetNumShapeshiftForms / GetShapeshiftFormInfo(i) 的 active / GetShapeshiftForm()==0 = 没开；
--   再读自己身上的光环 buff 兜底（来源是我 / 读不到来源都算开着；别的圣骑士的同名光环不算）。
--   ⛔ 读到 secret 值（副本里受保护）= 不知道 → 不提醒；死亡 / 骑马 / 飞行点 / 载具不提醒；进世界 / 复活后先等 3 秒（光环还没读到）
-- ④ 没开：屏幕上一个小条「没开光环」+ 安全按钮「开 XX光环」（type = spell，spell = 那条光环自己学会的最高级 id）；
--   默认用上一次开过的光环（姿态条 / 身上光环 / 施法成功都记），没记录用虔诚光环，学会的才用；开了自动收起。
--   ⛔ 战斗中不改按钮属性、不显示 / 隐藏 / 挪动小条（里面有安全按钮）：进战斗前显示着就一直显示着（按钮照样能点），
--   战斗中光环掉了等脱战再弹；战斗中只改小条上的字。× = 10 分钟内先别提醒。
-- ⑤ 开关：ns.db.auraRemind.on（nil = 默认开，false = 关），Settings.lua「职业 → 一键祝福」组里一项；
--   命令 /gi 光环（/gi aura）：检查一次 · 开 · 关 · 重置（小条位置）。⛔ 不发任何聊天消息（只有自己敲命令时在本地聊天框回一句）
local _, ns = ...; ns = _G.GearInsightForever or ns

local AR = {}
ns.AuraRemind = AR
local function L(cn, en) return ns.L(cn, en) end

AR.BTN = "GearInsightForeverAuraRemindBtn"
AR.GRACE = 3        -- 进世界 / 复活后这么多秒内不提醒（光环 / 姿态条还没刷出来）
AR.SNOOZE = 600     -- 点 × 后这么久不提醒
AR.DEFAULT = "devotion"

-- ---------- 数据（来源见文件头 ②）：ranks = { 法术 id, 学习等级 }，按等级升序 ----------
AR.LINES = {
    { key = "devotion", cn = "虔诚光环", en = "Devotion Aura", icon = "Interface\\Icons\\Spell_Holy_DevotionAura",
      ranks = { { 465, 1 }, { 10290, 10 }, { 643, 20 }, { 10291, 30 }, { 1032, 40 }, { 10292, 50 }, { 10293, 60 } } },
    { key = "retribution", cn = "惩罚光环", en = "Retribution Aura", icon = "Interface\\Icons\\Spell_Holy_AuraOfLight",
      ranks = { { 7294, 16 }, { 10298, 26 }, { 10299, 36 }, { 10300, 46 }, { 10301, 56 } } },
    { key = "concentration", cn = "专注光环", en = "Concentration Aura", icon = "Interface\\Icons\\Spell_Holy_MindSooth",
      ranks = { { 19746, 22 } } },
    { key = "shadow", cn = "暗影抗性光环", en = "Shadow Resistance Aura", icon = "Interface\\Icons\\Spell_Shadow_SealOfKings",
      ranks = { { 19876, 28 }, { 19895, 40 }, { 19896, 52 } } },
    { key = "frost", cn = "冰霜抗性光环", en = "Frost Resistance Aura", icon = "Interface\\Icons\\Spell_Frost_WizardMark",
      ranks = { { 19888, 32 }, { 19897, 44 }, { 19898, 56 } } },
    { key = "fire", cn = "火焰抗性光环", en = "Fire Resistance Aura", icon = "Interface\\Icons\\Spell_Fire_SealOfFire",
      ranks = { { 19891, 36 }, { 19899, 48 }, { 19900, 60 } } },
}
AR.LINE, AR.BY_ID, AR.BY_NAME = {}, {}, {}
for _, d in ipairs(AR.LINES) do
    AR.LINE[d.key] = d
    for _, r in ipairs(d.ranks) do AR.BY_ID[r[1]] = d end
    AR.BY_NAME[d.cn], AR.BY_NAME[d.en] = d, d
end

-- ---------- 小工具 ----------
local function now() return GetTime and GetTime() or 0 end
local function combat() return InCombatLockdown and InCombatLockdown() and true or false end
-- secret 值（副本里受保护）：不能拿来判真假 / 比较 → 一律当「不知道」
local function sec(v) return issecretvalue ~= nil and issecretvalue(v) and true or false end
AR.IsSecret = sec
-- 调游戏接口 → 第一个返回值, 是不是 secret（接口不存在 / 出错 = nil, false）
local function ask(f, ...)
    if type(f) ~= "function" then return nil, false end
    local ok, v = pcall(f, ...)
    if not ok then return nil, false end
    if sec(v) then return nil, true end
    return v, false
end
function AR.IsPaladin()
    if not UnitClass then return false end
    local ok, _, c = pcall(UnitClass, "player")
    if not ok or sec(c) then return false end
    return c == "PALADIN"
end

-- ---------- 设置（ns.db.auraRemind；nil = 默认）----------
function AR.DB()
    if not ns.db then return {} end
    if type(ns.db.auraRemind) ~= "table" then ns.db.auraRemind = {} end
    return ns.db.auraRemind
end
function AR.On() return not (ns.db and type(ns.db.auraRemind) == "table" and ns.db.auraRemind.on == false) end
-- ⛔ 别写成 (not v) and false or nil（恒为 nil）
function AR.SetOn(v)
    if v then AR.DB().on = nil; AR.snoozeUntil = 0 else AR.DB().on = false end
    AR.Refresh()
end
function AR.Remember(key)
    if key and AR.LINE[key] and ns.db then AR.DB().last = key end
end

-- ---------- 会哪些 ----------
local function known(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown and ask(C_SpellBook.IsSpellKnown, id) then return true end
    if IsPlayerSpell and ask(IsPlayerSpell, id) then return true end
    if IsSpellKnown and ask(IsSpellKnown, id) then return true end
    return false
end
-- 这条光环自己学会的最高一级 id（没学 = nil）
function AR.BestRank(line)
    if type(line) == "string" then line = AR.LINE[line] end
    if not line then return nil end
    for i = #line.ranks, 1, -1 do
        if known(line.ranks[i][1]) then return line.ranks[i][1] end
    end
    return nil
end
-- 按钮用哪条：上一次开过的 → 虔诚光环 → 学会的第一条
function AR.Pick()
    for _, k in ipairs({ AR.DB().last, AR.DEFAULT }) do
        local line = k and AR.LINE[k]
        local id = line and AR.BestRank(line)
        if id then return line, id end
    end
    for _, line in ipairs(AR.LINES) do
        local id = AR.BestRank(line)
        if id then return line, id end
    end
    return nil
end

-- ---------- 开没开 ----------
-- 姿态条第 i 格 → active, spellID, 有没有 secret（新接口 icon, active, castable, spellID；老接口 texture, name, active, castable）
local function formInfo(i)
    if not GetShapeshiftFormInfo then return nil, nil, false end
    local ok, a, b, c, d = pcall(GetShapeshiftFormInfo, i)
    if not ok then return nil, nil, false end
    if sec(a) or sec(b) or sec(c) or sec(d) then return nil, nil, true end
    local active, sid
    if type(b) == "string" then active = c else active, sid = b, d end
    return (active == true or active == 1), tonumber(sid), false
end
-- → "on", spellID | "off" | "secret" | "none"（姿态条上没东西 / 没这个接口：看不出来）
function AR.StanceState()
    local n, s = ask(GetNumShapeshiftForms)
    if s then return "secret" end
    n = tonumber(n) or 0
    if n <= 0 then return "none" end
    local cur, s2 = ask(GetShapeshiftForm)
    if s2 then return "secret" end
    local anySecret = false
    for i = 1, n do
        local active, sid, si = formInfo(i)
        if si then anySecret = true elseif active then return "on", sid end
    end
    cur = tonumber(cur)
    if cur and cur > 0 then
        local _, sid = formInfo(cur)
        return "on", sid
    end
    if anySecret then return "secret" end
    return "off"
end
-- 自己身上第 i 个增益 → name, src, spellID, 有没有 secret；没有了 → nil
local function buffAt(i)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or a == nil then return nil end
        if sec(a) or type(a) ~= "table" then return false, nil, nil, true end
        local name, src, sid = a.name, a.sourceUnit, a.spellId
        if sec(name) and sec(sid) then return false, nil, nil, true end
        if sec(name) then name = nil end
        if sec(sid) then sid = nil end
        if sec(src) then src = nil end
        return name or false, src, tonumber(sid), false
    end
    local f = UnitAura or UnitBuff
    if not f then return nil end
    local ok, name, _, _, _, _, _, src, _, _, sid = pcall(f, "player", i, UnitAura and "HELPFUL" or nil)
    if not ok then return nil end
    if sec(name) then return false, nil, nil, true end
    if name == nil then return nil end
    if sec(sid) then sid = nil end
    if sec(src) then src = nil end
    return name, src, tonumber(sid), false
end
local function isMe(u)
    if u == nil or u == "player" then return true end   -- 读不到来源：当成我的（不知道时不提醒）
    local v, s = ask(UnitIsUnit, u, "player")
    if s then return true end
    return v and true or false
end
-- → "on", 光环 key | "off" | "secret"
function AR.BuffState()
    local anySecret = false
    for i = 1, 40 do
        local name, src, sid, si = buffAt(i)
        if name == nil then break end
        if si then
            anySecret = true
        else
            local line = (sid and AR.BY_ID[sid]) or (name and AR.BY_NAME[name])
            if line and isMe(src) then return "on", line.key end
        end
    end
    if anySecret then return "secret" end
    return "off"
end
-- → "on", key | "off" | nil（不知道）
function AR.Status()
    local st, sid = AR.StanceState()
    local key = sid and AR.BY_ID[sid] and AR.BY_ID[sid].key or nil
    if st == "on" then
        if not key then local _, bk = AR.BuffState(); key = bk end
        return "on", key
    end
    local bst, bkey = AR.BuffState()
    if bst == "on" then return "on", bkey end
    if st == "secret" or bst == "secret" then return nil end
    return "off"
end

-- 现在不该提醒的状态：死亡 / 飞行点 / 骑马 / 载具；读到 secret → "unknown"
function AR.Blocked()
    local checks = {
        { UnitIsDeadOrGhost, "dead", "player" },
        { UnitOnTaxi, "taxi", "player" },
        { IsMounted, "mount" },
        { UnitInVehicle, "vehicle", "player" },
        { UnitHasVehicleUI, "vehicle", "player" },
    }
    for _, c in ipairs(checks) do
        local v, s = ask(c[1], c[3])
        if s then return "unknown" end
        if v then return c[2] end
    end
    return nil
end

AR.graceUntil, AR.snoozeUntil = 0, 0
-- → 要不要提醒, 原因, 光环, 法术 id
function AR.Check()
    if not ns.db then return false, "nodb" end
    if not AR.IsPaladin() then return false, "class" end
    if not AR.On() then return false, "off" end
    local line, id = AR.Pick()
    if not line then return false, "unlearned" end
    local st, key = AR.Status()
    if st == "on" then AR.Remember(key); return false, "on" end
    if st == nil then return false, "unknown" end
    local b = AR.Blocked()
    if b then return false, b end
    if now() < (AR.graceUntil or 0) then return false, "grace" end
    if now() < (AR.snoozeUntil or 0) then return false, "snooze" end
    line, id = AR.Pick()   -- Status 里可能刚记下「上一次开过的」
    return true, "show", line, id
end

-- ---------- 安全按钮 ----------
AR.attrWrites = 0
local function setAttrs(b, typ, spell)
    if combat() then return false end   -- ⛔ 战斗中不改属性
    local cur = rawget(b, "_arAttr")
    if cur and cur.type == typ and cur.spell == spell then return true end
    b:SetAttribute("type", typ)
    b:SetAttribute("spell", spell)
    rawset(b, "_arAttr", { type = typ, spell = spell })
    AR.attrWrites = AR.attrWrites + 1
    return true
end
AR.SetAttrs = setAttrs

-- ---------- 小条 ----------
local function savePos()
    local f = AR.frame
    if not f then return end
    local p, _, _, x, y = f:GetPoint()
    AR.DB().pos = { p or "CENTER", x or 0, y or 0 }
end
local function place(f)
    f:ClearAllPoints()
    local pos = AR.DB().pos
    if type(pos) == "table" and pos[1] then f:SetPoint(pos[1], UIParent, pos[1], tonumber(pos[2]) or 0, tonumber(pos[3]) or 0)
    else f:SetPoint("CENTER", UIParent, "CENTER", -260, -40) end   -- 默认在一键祝福悬浮框（CENTER -260,-120）正上方
end
function AR.Build()
    if AR.frame then return AR.frame end
    if combat() then return nil end
    local f = CreateFrame("Frame", "GearInsightForeverAuraRemind", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(200, 56); f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(true)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.07, 0.05, 0.03, 0.88)
        if f.SetBackdropBorderColor then f:SetBackdropBorderColor(1, 0.6, 0.15, 0.9) end
    end
    place(f)
    f:SetMovable(true); f:EnableMouse(true)
    if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
    f:SetScript("OnDragStart", function(self) if not combat() then self:StartMoving() end end)   -- 里面有安全按钮：战斗中不能挪
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos() end)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(16, 16); f.icon:SetPoint("TOPLEFT", 8, -6)
    f.line = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.line:SetPoint("LEFT", f.icon, "RIGHT", 5, 0); f.line:SetPoint("RIGHT", f, "RIGHT", -22, 0); f.line:SetJustifyH("LEFT")
    local x = CreateFrame("Button", nil, f)
    x:SetSize(14, 14); x:SetPoint("TOPRIGHT", -5, -5)
    x:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    x:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    -- 11-17 用户「这些弹出的功能都确保能永久关闭」：左键 = 10 分钟内先别提醒，右键 = 永久关闭（存档 auraRemind.on = false）
    if x.RegisterForClicks then x:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    x:SetScript("OnClick", function(_, mb) if mb == "RightButton" then AR.Never() else AR.Snooze() end end)
    x:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L("10 分钟内先别提醒", "Not now (10 min)"), 1, 0.82, 0)
        GameTooltip:AddLine(L("也能 /gi 光环 关，或「职业 → 一键祝福」页右上角本页设置", "Also /gi aura off, or the Blessings page settings"), 1, 1, 1, true)
        GameTooltip:AddLine(L("左键 10 分钟内先别提醒  ·  右键永久关闭", "Left: not now (10 min)  ·  Right: close for good"), 0.25, 0.9, 0.35, true)
        GameTooltip:Show()
    end)
    x:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.close = x
    local b = CreateFrame("Button", AR.BTN, f, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    b:SetSize(184, 24); b:SetPoint("BOTTOM", f, "BOTTOM", 0, 7)
    if b.RegisterForClicks then b:RegisterForClicks("AnyDown") end
    if ns.SkinButton then ns.SkinButton(b) end
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L("点一下开光环", "Click to turn on your aura"), 1, 0.82, 0)
        GameTooltip:AddLine(L("默认用你上一次开过的光环；拖动小条可以换位置（战斗中不能拖）", "Uses the aura you had on last; drag the bar to move it (not in combat)"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.btn = b
    f:Hide()
    AR.frame = f
    return f
end
function AR.Snooze()
    if combat() then return false end   -- 战斗中不能收起（里面有安全按钮）
    AR.snoozeUntil = now() + AR.SNOOZE
    if AR.frame then AR.frame:Hide() end
    return true
end
-- 右键 ×：永久关闭（⛔ 战斗中小条里有安全按钮收不起来 → 只提示）
function AR.Never()
    if combat() then ns.Print(L("战斗中收不起这个提醒条，脱战后再右键", "Can't hide it in combat - right-click again after")); return false end
    AR.SetOn(false)
    if AR.frame then AR.frame:Hide() end
    if ns.CloseHint then
        ns.CloseHint("auraRemind", L("光环没开提醒已永久关闭。找回：GI 菜单 → 设置 → 窗口与提醒「光环没开提醒」点「打开」，或 /gi 光环 开",
            "Aura reminder closed for good. Bring it back: GI menu > Settings > Windows & alerts > Aura reminder, or /gi aura on"))
    end
    return true
end
function AR.ResetPos()
    if combat() then return false end
    AR.DB().pos = nil
    if AR.frame then place(AR.frame) end
    return true
end

-- ---------- 刷新 ----------
local function lineText(want)
    if want then return L("|cffff9933没开光环|r", "|cffff9933No aura on|r") end
    return L("|cff7fbf7f光环已开|r |cff9a9a9a（脱战后收起）|r", "|cff7fbf7fAura on|r |cff9a9a9a(hides after combat)|r")
end
function AR.Refresh()
    local want, why, line, id = AR.Check()
    AR.why = why
    local f = AR.frame
    if combat() then
        -- ⛔ 战斗中：不显示 / 不隐藏 / 不改属性，只改字；没显示着的等脱战（PLAYER_REGEN_ENABLED）再弹
        if f and f:IsShown() then f.line:SetText(lineText(want)) end
        AR.pending = want or nil
        return want, why
    end
    AR.pending = nil
    if want then
        f = f or AR.Build()
        if not f then return want, why end
        setAttrs(f.btn, "spell", id)
        f.btn:SetText(string.format(L("开 %s", "Cast %s"), L(line.cn, line.en)))
        if f.icon.SetTexture then f.icon:SetTexture(line.icon) end
        f.line:SetText(lineText(true))
        f:Show()
    elseif f and f:IsShown() then
        f:Hide()
    end
    return want, why
end

local WHY = {
    show = { "没开光环：屏幕上出了提醒小条，点按钮开", "No aura on: click the button on screen" },
    on = { "光环开着", "Aura is on" },
    off = { "光环提醒已关（/gi 光环 开）", "Aura reminder is off (/gi aura on)" },
    unlearned = { "还没学会光环", "No aura learned yet" },
    class = { "光环提醒只给圣骑士用", "Aura reminder is for paladins" },
    dead = { "死亡中不提醒", "Not while dead" },
    taxi = { "飞行中不提醒", "Not while on a flight path" },
    mount = { "骑马时不提醒", "Not while mounted" },
    vehicle = { "载具上不提醒", "Not in a vehicle" },
    unknown = { "读不到光环状态（副本里受保护），这次不提醒", "Can't read aura state here (protected), skipped" },
    grace = { "刚进世界 / 复活，过几秒再看", "Just loaded / revived, checking in a few seconds" },
    snooze = { "10 分钟内先不提醒", "Snoozed for 10 minutes" },
    nodb = { "存档还没读好", "Settings not loaded yet" },
}
function AR.WhyText(why)
    local w = WHY[why or ""] or { tostring(why), tostring(why) }
    return L(w[1], w[2])
end

-- ---------- 事件 ----------
local ev = CreateFrame("Frame")
AR.ev = ev
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_DEAD",
    "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS", "UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
    "PLAYER_MOUNT_DISPLAY_CHANGED", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local dirty, acc = true, 0
function AR.Dirty() dirty = true end
function AR.Active() return ns.db ~= nil and AR.On() and AR.IsPaladin() end
-- 有事件 0.3 秒内刷新；平时每 2 秒看一眼（下马 / 落地没有可靠的事件）
function AR.OnUpdate(el)
    acc = acc + (el or 0)
    if acc < (dirty and 0.3 or 2) then return end
    acc = 0
    local d = dirty
    dirty = false
    if not AR.Active() then
        if d and AR.frame and AR.frame:IsShown() and not combat() then AR.frame:Hide() end
        return
    end
    pcall(AR.Refresh)
end
ev:SetScript("OnUpdate", function(_, el) AR.OnUpdate(el) end)
function AR.OnEvent(e, a1, a2, a3)
    if sec(a1) then return end
    if e == "UNIT_AURA" or e == "UNIT_SPELLCAST_SUCCEEDED" or e == "UNIT_ENTERED_VEHICLE" or e == "UNIT_EXITED_VEHICLE" then
        if a1 ~= "player" then return end
    end
    if not AR.IsPaladin() then return end
    if e == "PLAYER_LOGIN" or e == "PLAYER_ENTERING_WORLD" or e == "PLAYER_ALIVE" or e == "PLAYER_UNGHOST" then
        AR.graceUntil = now() + AR.GRACE
    elseif e == "UNIT_SPELLCAST_SUCCEEDED" then
        local id = (not sec(a3)) and tonumber(a3) or nil
        if not id and not sec(a2) then id = tonumber(a2) end
        local line = id and AR.BY_ID[id]
        if line then AR.Remember(line.key) end
    elseif e == "PLAYER_REGEN_ENABLED" or e == "PLAYER_REGEN_DISABLED" then
        pcall(AR.Refresh)
        return
    end
    dirty = true
end
ev:SetScript("OnEvent", function(_, e, ...) pcall(AR.OnEvent, e, ...) end)
-- 拆分包里 _Class 晚于进世界才加载 → 补一次（同样先等几秒）
ns.AddInit(function()
    if IsLoggedIn and IsLoggedIn() then AR.graceUntil = now() + AR.GRACE; dirty = true end
end)

-- ---------- 命令 ----------
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash["光环"] = function(rest)
    rest = (rest or ""):gsub("^[ \t]+", ""):gsub("[ \t]+$", "")
    if not AR.IsPaladin() then ns.Print(AR.WhyText("class")); return end
    if rest == "开" or rest == "on" then
        AR.SetOn(true)
        ns.Print(L("光环没开时提醒：开", "Aura reminder: on"))
    elseif rest == "关" or rest == "off" then
        AR.SetOn(false)
        ns.Print(L("光环没开时提醒：关", "Aura reminder: off"))
    elseif rest == "重置" or rest == "reset" then
        if AR.ResetPos() then ns.Print(L("光环提醒小条：位置已重置", "Aura bar position reset"))
        else ns.Print(L("战斗中不能挪，脱战后再试", "Can't move it in combat")) end
    else
        AR.snoozeUntil, AR.graceUntil = 0, 0
        local _, why = AR.Refresh()
        ns.Print(AR.WhyText(why) .. L("　|cff9a9a9a/gi 光环 开 | 关 | 重置|r", "   |cff9a9a9a/gi aura on | off | reset|r"))
    end
end
ns.ExtraSlash.aura = ns.ExtraSlash["光环"]

-- 「窗口与提醒」（11-17）：右键关掉的光环提醒从这里找回（⛔ 关掉后 _Class 不再为它登录加载 → 主插件 ClassStub.lua 要有同 key 占位）
if ns.RegisterWindow then
    ns.RegisterWindow({ key = "auraRemind", order = 56, title = function() return L("光环没开提醒（圣骑士）", "Aura reminder (Paladin)") end,
        avail = function() return AR.IsPaladin() end,
        state = function() return AR.On() and L("没开光环时出", "Shows when no aura is on") or L("已关闭", "Closed") end,
        actions = function()
            local on = AR.On()
            return {
                { text = on and L("关闭", "Turn off") or L("打开", "Turn on"), fn = function() if on then AR.Never() else AR.SetOn(true) end end },
                { text = L("重置位置", "Reset position"), fn = function() AR.ResetPos() end },
            }
        end })
end
