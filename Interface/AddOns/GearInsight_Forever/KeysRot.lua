-- 键位手法 · 手法引擎 + 钉板（10-10，docs/forever-keybind-rotation-design.md §5）
-- 引擎和职业无关：读规则表（KeysRotData，手写 / 公测 / WCL 同一种格式）→ 记账 → 求「现在该按」+ 依据 → 键帽。
-- 《无限》= 12.0 引擎：战斗日志对插件关闭、部分数值是保密值 → 沿用正式服血 DK 的「事件驱动 + 自己记账」：
--   读得到的直接读（IsSpellUsable、冷却、资源…以 P0 探针结论为准），读不到的按施法事件推算；推算的条件在依据里标「推算」。
-- 只显示第一格（现在该按）：09-21 用户「暴雪只算下一个，再往后只能猜，猜错比不显示更糟」。
-- ⛔ HOLD（_hold.txt），测完才进包。
local _, ns = ...
local K = ns.Keys

local R = {}
ns.KeysRot = R

local S = { last = {}, dots = {}, buffs = {}, stacks = {}, cp = 0, fight = { n = 0, hit = 0 }, streak = 0 }
R.S = S

local function now() return GetTime and GetTime() or 0 end
local function secret(v) return issecretvalue and v ~= nil and issecretvalue(v) end
local function num(v) if v == nil or secret(v) then return nil end; return tonumber(v) end

-- 当前目标的记账键：GUID 读得到就用 GUID（换目标各记各的），保密 / 没有就统一记 "t"
local function tkey()
    local ok, g = pcall(UnitGUID, "target")
    if ok and g and not secret(g) then return g end
    return "t"
end

-- ---------- 规则表 ----------
local spellCache
local function entryByName(cls, name)
    for _, e in ipairs((ns.Data.keys or {})[cls] or {}) do if e.n == name then return e end end
end
local function resolve(cls, name)
    spellCache = spellCache or {}
    local c = spellCache[name]
    if c == nil then
        local e = entryByName(cls, name)
        local id, loc
        if e then id, loc = K.Resolve(e) end
        c = id and { id = id, name = loc, cd = e.cd or 0 } or false
        spellCache[name] = c
    end
    return c or nil
end
function R.ClearCache() spellCache = nil end

function R.Table(cls, tree)
    local T = (ns.KeysRotData or {})[cls]
    if not T then return nil end
    return T[tree or 0] or T[0]
end
function R.Current()
    local cls = ns.MyClass()
    local tree = K.MainTree()
    return R.Table(cls, tree), cls, tree
end

-- ---------- 读 / 推算 ----------
local function usable(id)
    local f = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
    if not f then return nil end
    local ok, u = pcall(f, id)
    if not ok or secret(u) then return nil end
    return u and true or false
end
local function cdReady(sp, nm)
    local f = GetSpellCooldown
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, c = pcall(C_Spell.GetSpellCooldown, sp.id)
        if ok and c and num(c.startTime) and num(c.duration) then
            return c.startTime == 0 or c.duration <= 1.6 or (c.startTime + c.duration - now()) <= 0.1, false
        end
    elseif f then
        local ok, st, du = pcall(f, sp.id)
        if ok and num(st) and num(du) then return st == 0 or du <= 1.6 or (st + du - now()) <= 0.1, false end
    end
    -- 读不到：按上次施放 + 冷却时长推算
    local t = S.last[nm]
    return (not t) or (now() - t) >= (sp.cd or 0) - 0.2, true
end
local function power()
    local ok, v = pcall(UnitPower, "player")
    return ok and num(v) or nil
end
local function manaPct()
    local ok, v = pcall(UnitPower, "player", 0)
    local ok2, m = pcall(UnitPowerMax, "player", 0)
    v, m = ok and num(v), ok2 and num(m)
    if v and m and m > 0 then return v / m * 100 end
end
local FINISHERS = { ["切割"] = true, ["剔骨"] = true, ["割裂"] = true, ["毒针"] = true, ["肾击"] = true, ["刺骨"] = true }
local function combo()
    if GetComboPoints then
        local ok, v = pcall(GetComboPoints, "player", "target")
        if ok and num(v) then return v, false end
    end
    return S.cp, true
end
local function targets()
    local n = 0
    local ok, list = pcall(function() return C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() end)
    for _, np in ipairs((ok and list) or {}) do
        local u = np.namePlateUnitToken
        if u then
            local ok2, atk = pcall(UnitCanAttack, "player", u)
            if ok2 and atk and not secret(atk) then
                local ok3, near = pcall(CheckInteractDistance or function() return true end, u, 3)   -- 3 = 约 10 码
                if not ok3 or near == nil or secret(near) or near then n = n + 1 end
            end
        end
    end
    return n
end
local function remain(t) if not t then return 0 end; return math.max(0, t - now()) end

-- ---------- 求值 ----------
-- 返回 { id, name, key, why, est = 是否用了推算 } 或 nil
function R.Next()
    local T, cls = R.Current()
    if not T then return nil end
    local tk = tkey()
    for _, r in ipairs(T.rules) do
        local sp = resolve(cls, r.cast)
        if sp then
            local ok, est = true, false
            for _, w in ipairs(r.when or {}) do
                local cond, arg = w:match("^(%a+)([<>=:].*)$")
                cond = cond or w
                if w == "ready" then
                    local u = usable(sp.id)
                    if u == false then ok = false else
                        local rdy, e = cdReady(sp, r.cast); est = est or e
                        if not rdy then ok = false end
                    end
                elseif w == "proc" then
                    if usable(sp.id) ~= true then ok = false end
                    local rdy = cdReady(sp, r.cast); if not rdy then ok = false end
                elseif cond == "res" then
                    local p = power(); local n = tonumber(arg:match("%d+"))
                    if p then if p < n then ok = false end else est = true end
                elseif cond == "mana" then
                    local m = manaPct(); local n = tonumber(arg:match("%d+"))
                    if not m or m >= n then ok = false end
                elseif cond == "cp" then
                    local c, e = combo(); est = est or e
                    if c < tonumber(arg:match("%d+")) then ok = false end
                elseif cond == "dot" then
                    local d = S.dots[tk] and S.dots[tk][r.cast]
                    if remain(d) >= tonumber(arg:match("[%d.]+")) then ok = false end
                    est = true
                elseif cond == "buff" then
                    if remain(S.buffs[r.cast]) >= tonumber(arg:match("[%d.]+")) then ok = false end
                    est = true
                elseif cond == "stack" then
                    local s = S.stacks[tk] and S.stacks[tk][r.cast]
                    local n = (s and remain(s.exp) > 0) and s.n or 0
                    if n >= tonumber(arg:match("%d+")) then ok = false end
                    est = true
                elseif cond == "targets" then
                    if targets() < tonumber(arg:match("%d+")) then ok = false end
                elseif cond == "known" then
                    if not resolve(cls, arg:sub(2)) then ok = false end
                end
                if not ok then break end
            end
            if ok then
                local live = R._live or K.LiveMap()
                R._live = live
                local l = live[sp.name]
                return { id = sp.id, name = sp.name, cast = r.cast, key = l and l.key, onBar = l ~= nil, why = r.why, est = est, rule = r }
            end
        end
    end
end

-- ---------- 记账（施法成功事件） ----------
local function onCast(spellID)
    if not spellID or secret(spellID) then return end
    local nm = K.SpellName(spellID)
    if not nm then return end
    local T, cls = R.Current()
    -- 本地名 → 规则里的中文键（规则按数据里的中文名写；英文客户端靠 resolve 缓存反查）
    local key = nm
    if spellCache then for k, c in pairs(spellCache) do if c and c.name == nm then key = k; break end end end
    local t = now()
    S.last[key] = t
    if T then
        for _, r in ipairs(T.rules) do
            if r.cast == key and r.dur then
                local tk = tkey()
                for _, w in ipairs(r.when or {}) do
                    if w:match("^dot") then S.dots[tk] = S.dots[tk] or {}; S.dots[tk][key] = t + r.dur end
                    if w:match("^buff") then S.buffs[key] = t + r.dur end
                    if w:match("^stack") then
                        S.stacks[tk] = S.stacks[tk] or {}
                        local s = S.stacks[tk][key]
                        local n = (s and remain(s.exp) > 0) and s.n or 0
                        S.stacks[tk][key] = { n = math.min(5, n + 1), exp = t + r.dur }
                    end
                end
            end
        end
    end
    if cls == "ROGUE" or ns.MyClass() == "Rogue" then
        if FINISHERS[key] then S.cp = 0 else S.cp = math.min(5, S.cp + 1) end
    end
    -- 跟手法对照：按下的是不是刚才建议的那个
    local sug = R._sug
    if sug and (t - (R._sugAt or 0)) < 3 and UnitAffectingCombat and UnitAffectingCombat("player") then
        S.fight.n = S.fight.n + 1
        if sug.name == nm then S.fight.hit = S.fight.hit + 1; S.streak = S.streak + 1; R._fb = { ok = true, at = t }
        else S.streak = 0; R._fb = { ok = false, at = t, got = nm, want = sug.name, why = sug.why } end
    end
    R._live = nil
end
R._onCast = onCast   -- 测试用

-- ---------- 钉板 ----------
local board
local function buildBoard()
    local f = CreateFrame("Frame", "GearInsightForeverKeysBoard", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(250, 74); f:SetFrameStrata("MEDIUM")
    local pos = ns.db.keysBoardPos
    if pos then f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else f:SetPoint("CENTER", 0, -180) end
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint()
        ns.db.keysBoardPos = { p, x, y }
    end)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0, 0, 0, 0.55)
    end
    f.ic = f:CreateTexture(nil, "ARTWORK"); f.ic:SetSize(44, 44); f.ic:SetPoint("TOPLEFT", 8, -8); f.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.key = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge"); f.key:SetPoint("BOTTOMRIGHT", f.ic, "BOTTOMRIGHT", -1, 2)
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.name:SetPoint("TOPLEFT", f.ic, "TOPRIGHT", 8, 0); f.name:SetPoint("RIGHT", -8, 0)
    f.name:SetJustifyH("LEFT"); f.name:SetWordWrap(false)
    f.why = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.why:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -4); f.why:SetPoint("RIGHT", -8, 0)
    f.why:SetJustifyH("LEFT"); f.why:SetWordWrap(true)
    f.fb = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.fb:SetPoint("BOTTOMLEFT", 8, 6); f.fb:SetPoint("RIGHT", -8, 0); f.fb:SetJustifyH("LEFT")
    f.fbIc = f:CreateTexture(nil, "OVERLAY"); f.fbIc:SetSize(14, 14); f.fbIc:SetPoint("BOTTOMRIGHT", -8, 5)
    f:SetScript("OnEnter", function(self)   -- 依据被截 → 悬停看全
        local s = R._sug
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.L("GI 手法 · 现在该按", "GI rotation - press now"), 1, 0.82, 0)
        if s then
            GameTooltip:AddLine(s.name .. (s.key and ("  [" .. s.key .. "]") or ""), 1, 1, 1)
            GameTooltip:AddLine(ns.L(s.why[1], s.why[2]), 0.8, 0.8, 0.8, true)
            if s.est then GameTooltip:AddLine(ns.L("部分条件是按施法推算的（客户端读不到）", "Some conditions are estimated from your casts"), 0.6, 0.6, 0.6, true) end
        end
        local T = R.Current()
        if T then GameTooltip:AddLine(ns.L("手法来源：", "Source: ") .. ns.L("GI 基础手法 · ", "GI basic - ") .. ns.L(T.name[1], T.name[2]), 0.6, 0.6, 0.6) end
        GameTooltip:AddLine(ns.L("拖动可移动 · /gif keys hud 关闭", "Drag to move - /gif keys hud to hide"), 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local acc = 0
    f:SetScript("OnUpdate", function(self, el)
        acc = acc + el
        if acc < 0.1 then return end
        acc = 0
        R.Render(self)
    end)
    return f
end

function R.Render(f)
    f = f or board
    if not f then return end
    local s = R.Next()
    R._sug, R._sugAt = s, now()
    if s then
        f.ic:SetTexture((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(s.id)) or (GetSpellTexture and GetSpellTexture(s.id)) or "Interface\\Icons\\INV_Misc_QuestionMark")
        f.key:SetText(s.key and ns.KeysShortKey(s.key) or (s.onBar and "|cffff5555?|r" or ""))
        f.name:SetText(s.name .. (s.onBar and "" or ns.L("  |cffff5555不在条上|r", "  |cffff5555not on bars|r")))
        f.why:SetText(ns.L(s.why[1], s.why[2]))
        f.ic:SetDesaturated(false)
    else
        f.ic:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark"); f.ic:SetDesaturated(true)
        f.key:SetText(""); f.name:SetText(ns.L("GI 手法", "GI rotation"))
        f.why:SetText(R.Current() and ns.L("现在没有该按的", "Nothing to press right now") or ns.L("这个职业的手法还没做", "No rotation for this class yet"))
    end
    -- 反馈：2.5 秒内显示刚才那一下对不对；平时显示本场一致率
    local fb = R._fb
    if fb and now() - fb.at < 2.5 then
        f.fbIc:SetTexture(fb.ok and "Interface\\RaidFrame\\ReadyCheck-Ready" or "Interface\\RaidFrame\\ReadyCheck-NotReady"); f.fbIc:Show()
        f.fb:SetText(fb.ok and string.format(ns.L("跟手法一致 · 连对 %d", "Matched - streak %d"), S.streak)
            or string.format(ns.L("你按了 %s，手法这里按 %s", "You pressed %s, rotation says %s"), fb.got or "?", fb.want or "?"))
    else
        f.fbIc:Hide()
        local n = S.fight.n
        f.fb:SetText(n > 0 and string.format(ns.L("本场跟手法一致 %d%%（%d 下）", "This fight: %d%% matched (%d casts)"), math.floor(S.fight.hit / n * 100 + 0.5), n) or "")
    end
end

function R.Toggle(on)
    if on == nil then on = not (board and board:IsShown()) end
    ns.db.keysBoard = on and true or false
    if on then board = board or buildBoard(); board:Show() elseif board then board:Hide() end
    return on
end
R._build = function() board = board or buildBoard(); return board end   -- 测试用

-- ---------- 事件 ----------
local ev = CreateFrame("Frame")
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED", "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS",
    "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "CHARACTER_POINTS_CHANGED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, e, a1, a2, a3)
    if e == "UNIT_SPELLCAST_SUCCEEDED" then pcall(onCast, a3)
    elseif e == "PLAYER_REGEN_DISABLED" then S.fight = { n = 0, hit = 0 }; S.streak = 0
    elseif e == "PLAYER_REGEN_ENABLED" then
        if S.fight.n >= 10 and board and board:IsShown() then
            ns.Print(string.format(ns.L("上一场跟手法一致 %d%%（%d 下）", "Last fight: %d%% matched the rotation (%d casts)"), math.floor(S.fight.hit / S.fight.n * 100 + 0.5), S.fight.n))
        end
        S.cp = 0
    elseif e == "SPELLS_CHANGED" or e == "CHARACTER_POINTS_CHANGED" then R.ClearCache(); R._live = nil
    elseif e == "ACTIONBAR_SLOT_CHANGED" or e == "UPDATE_BINDINGS" then R._live = nil
    elseif e == "PLAYER_ENTERING_WORLD" then
        if ns.db and ns.db.keysBoard then R.Toggle(true) end
    end
end)
ns.KeysRotChanged = function() R.ClearCache(); if ns.KeysHud then ns.KeysHud.ClearCache() end end
