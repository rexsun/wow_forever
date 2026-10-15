-- 键位手法 P4 · 决策 HUD（训练模式 = 分轨面板，挂在钉板下面；10-10，docs/forever-keybind-rotation-design.md §5.3）
-- 轨道都从手法引擎的记账里取（KeysRot.S），读不到的不画：
--   资源轨（怒气 / 能量 / 法力 + 盗贼连击点）· DoT 轨（当前目标身上自己的持续伤害，剩余秒数）·
--   冷却轨（规则里有冷却的技能，剩余秒数）· 触发轨（压制 / 复仇 / 还击 / 斩杀：能按就亮）
-- ⛔ 游戏字体没有 ● ✓ → 等符号：格子用贴图。⛔ HOLD（_hold.txt），测完才进包。
local _, ns = ...
local R = ns.KeysRot

local H = {}
ns.KeysHud = H
local ICON = 22

local function now() return GetTime and GetTime() or 0 end
local function secret(v) return issecretvalue and v ~= nil and issecretvalue(v) end

local function iconOf(id)
    return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or (GetSpellTexture and GetSpellTexture(id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- 当前规则表里各类技能（按轨道分好），引擎缓存清了就重算
local tracksCache
function H.Tracks()
    if tracksCache then return tracksCache end
    local T, cls = R.Current()
    local t = { dot = {}, cd = {}, proc = {} }
    if not T then tracksCache = t; return t end
    local seen = {}
    for _, r in ipairs(T.rules) do
        local e
        for _, x in ipairs((ns.Data.keys or {})[cls] or {}) do if x.n == r.cast then e = x; break end end
        local id, name
        if e then id, name = ns.Keys.Resolve(e) end   -- ⛔ 别写成 e and Resolve(e)：and 只留第一个返回值，名字会丢
        if id and not seen[r.cast] then
            seen[r.cast] = true
            local w = table.concat(r.when or {}, " ")
            local it = { cast = r.cast, id = id, name = name, cd = e.cd or 0, dur = r.dur }
            if w:find("dot<") then t.dot[#t.dot + 1] = it end
            if w:find("proc") then t.proc[#t.proc + 1] = it
            elseif (e.cd or 0) >= 4 then t.cd[#t.cd + 1] = it end
        end
    end
    tracksCache = t
    return t
end
function H.ClearCache() tracksCache = nil end

-- 冷却剩余：API 读得到就用，读不到按施法记账
local function cdLeft(it)
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, c = pcall(C_Spell.GetSpellCooldown, it.id)
        if ok and c and not secret(c.startTime) and not secret(c.duration) and c.startTime and c.duration then
            if c.startTime == 0 or c.duration <= 1.6 then return 0 end
            return math.max(0, c.startTime + c.duration - now())
        end
    end
    local t = R.S.last[it.cast]
    if not t then return 0 end
    return math.max(0, t + it.cd - now())
end

local function getCell(f, track, i)
    f.cells[track] = f.cells[track] or {}
    local c = f.cells[track][i]
    if c then return c end
    c = CreateFrame("Frame", nil, f)
    c:SetSize(ICON, ICON)
    c.ic = c:CreateTexture(nil, "ARTWORK"); c.ic:SetAllPoints(); c.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.t = c:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall"); c.t:SetPoint("CENTER", 0, 0)
    c:EnableMouse(true)
    c:SetScript("OnEnter", function(self)   -- 小图标显示不全 → 悬停看全
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(self.tip, 1, 1, 1); GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.cells[track][i] = c
    return c
end

local TRACK_NAME = { res = { "资源", "Resource" }, dot = { "持续伤害", "DoTs" }, cd = { "冷却", "Cooldowns" }, proc = { "触发", "Procs" } }

local function build(anchor)
    local f = CreateFrame("Frame", "GearInsightForeverKeysHud", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(250, 120)
    f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0, 0, 0, 0.45)
    end
    f.cells, f.labels = {}, {}
    for i, k in ipairs({ "res", "dot", "cd", "proc" }) do
        local l = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        l:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 27); l:SetWidth(52); l:SetJustifyH("LEFT")
        l:SetText(ns.L(TRACK_NAME[k][1], TRACK_NAME[k][2]))
        f.labels[k] = l
    end
    -- 资源条
    f.bar = CreateFrame("StatusBar", nil, f)
    f.bar:SetSize(170, 12); f.bar:SetPoint("TOPLEFT", 64, -8)
    f.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar"); f.bar:SetMinMaxValues(0, 100)
    f.bar.bg = f.bar:CreateTexture(nil, "BACKGROUND"); f.bar.bg:SetAllPoints(); f.bar.bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
    f.bar.t = f.bar:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall"); f.bar.t:SetPoint("CENTER")
    f.pips = {}
    for i = 1, 5 do
        local p = f:CreateTexture(nil, "ARTWORK"); p:SetSize(14, 6); p:SetPoint("TOPLEFT", 64 + (i - 1) * 17, -22)
        p:SetTexture("Interface\\Buttons\\WHITE8x8")
        f.pips[i] = p
    end
    local acc = 0
    f:SetScript("OnUpdate", function(self, el)
        acc = acc + el
        if acc < 0.15 then return end
        acc = 0
        H.Render(self)
    end)
    return f
end

local function rowCells(f, track, items, y, fill)
    for _, c in ipairs(f.cells[track] or {}) do c:Hide() end
    for i, it in ipairs(items) do
        if i > 7 then break end
        local c = getCell(f, track, i)
        c:ClearAllPoints(); c:SetPoint("TOPLEFT", 64 + (i - 1) * (ICON + 3), y)
        c.ic:SetTexture(iconOf(it.id))
        fill(c, it)
        c:Show()
    end
end

function H.Render(f)
    f = f or H.frame
    if not f then return end
    local S = R.S
    -- 资源
    local ok, v = pcall(UnitPower, "player")
    local ok2, m = pcall(UnitPowerMax, "player")
    if ok and ok2 and v and m and not secret(v) and not secret(m) and m > 0 then
        f.bar:SetMinMaxValues(0, m); f.bar:SetValue(v); f.bar.t:SetText(v .. " / " .. m)
    elseif ok and v ~= nil then
        pcall(f.bar.SetValue, f.bar, v); f.bar.t:SetText("")   -- 保密值只能交给 StatusBar 显示，不能判断（正式服同法）
    end
    local isRogue = ns.MyClass() == "Rogue"
    local cp = isRogue and select(1, (function()
        if GetComboPoints then local okc, c = pcall(GetComboPoints, "player", "target"); if okc and c and not secret(c) then return c end end
        return S.cp
    end)()) or 0
    for i, p in ipairs(f.pips) do
        p:SetShown(isRogue)
        if i <= cp then p:SetVertexColor(1, 0.82, 0, 1) else p:SetVertexColor(0.25, 0.25, 0.25, 1) end
    end
    local tr = H.Tracks()
    -- DoT：当前目标（记账）
    local okg, g = pcall(UnitGUID, "target")
    local tk = (okg and g and not secret(g)) and g or "t"
    rowCells(f, "dot", tr.dot, -8 - 27 - 2, function(c, it)
        local exp = S.dots[tk] and S.dots[tk][it.cast]
        local left = exp and math.max(0, exp - now()) or 0
        c.t:SetText(left > 0 and string.format("%d", math.ceil(left)) or "")
        c.ic:SetDesaturated(left <= 0)
        c.ic:SetAlpha(left > 0 and (left < 3 and 0.6 or 1) or 0.4)
        c.tip = it.name .. (left > 0 and string.format(ns.L("：还剩 %d 秒（推算）", ": %ds left (estimated)"), math.ceil(left)) or ns.L("：目标身上没有", ": not on target"))
    end)
    rowCells(f, "cd", tr.cd, -8 - 54 - 2, function(c, it)
        local left = cdLeft(it)
        c.t:SetText(left > 0 and string.format("%d", math.ceil(left)) or "")
        c.ic:SetDesaturated(left > 0)
        c.tip = it.name .. (left > 0 and string.format(ns.L("：%d 秒后转好", ": ready in %ds"), math.ceil(left)) or ns.L("：转好了", ": ready"))
    end)
    rowCells(f, "proc", tr.proc, -8 - 81 - 2, function(c, it)
        local f2 = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
        local oku, u = pcall(f2 or function() end, it.id)
        local lit = oku and u == true
        c.t:SetText("")
        c.ic:SetDesaturated(not lit); c.ic:SetAlpha(lit and 1 or 0.35)
        c.tip = it.name .. (lit and ns.L("：亮了，能按", ": up - press it") or ns.L("：没触发", ": not up"))
    end)
end

function H.Toggle(on)
    if on == nil then on = not (H.frame and H.frame:IsShown()) end
    ns.db.keysHud = on and true or false
    if on then
        local board = _G.GearInsightForeverKeysBoard
        if not board then R.Toggle(true); board = _G.GearInsightForeverKeysBoard end
        H.frame = H.frame or build(board)
        H.frame:Show()
    elseif H.frame then H.frame:Hide() end
    return on
end
H._build = function(anchor) H.frame = H.frame or build(anchor); return H.frame end   -- 测试用

local ev = CreateFrame("Frame")
for _, e in ipairs({ "SPELLS_CHANGED", "CHARACTER_POINTS_CHANGED", "PLAYER_ENTERING_WORLD" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, e)
    H.ClearCache()
    if e == "PLAYER_ENTERING_WORLD" and ns.db and ns.db.keysHud then H.Toggle(true) end
end)
