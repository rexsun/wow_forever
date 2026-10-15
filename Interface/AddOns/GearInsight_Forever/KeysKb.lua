-- 键位页 · 虚拟键盘 + 录键（10-12，照正式服 GearInsight_Layout/ui/LayoutPage.lua 的「虚拟键盘」与 capture 1:1 移植）
--   每个键帽 = 这个键（当前修饰层）现在指向什么：金框 + 技能图标 = GI 铺条计划里的技能；黄框 = 动作条上别的东西（宏 / 物品 / 计划外技能）；
--   红角 = 键绑在空格上（白占着）；灰「移动」= WASD / QE / 空格留给移动；暗灰小字 = 被别的功能占着（打开地图之类）；黑 = 空闲。
--   修饰层按钮：无 / Shift / Ctrl / Alt。悬停看详情，点键帽 = 给那一格改键（同点键位页上的格子）。
--   《无限》差异：键位页是实况（不是正式服的计划键），所以录键直接 SetBinding；没有正式服的「系统键」编辑（回复密语 / 焦点…），
--     那些键在键盘上按「被别的功能占着」显示。
-- ⛔ HOLD（_hold.txt），测完才进包。⛔ 战斗中不改绑定（K.AssignSlotKey 自己拦）。
local _, ns = ...
local K = ns.Keys

local KB = {}
ns.KeysKb = KB
local GOLD = { 1, 0.82, 0 }

local function L(zh, en) return ns.L(zh, en) end
local function isDown(fn) if type(fn) ~= "function" then return false end local ok, v = pcall(fn); return ok and v and true or false end
local function bindText(key)
    if GetBindingText then local ok, t = pcall(GetBindingText, key, 1); if ok and t and t ~= "" then return t end end
    return key
end
local function bindName(act)
    if not act or act == "" then return nil end
    return _G["BINDING_NAME_" .. act] or act
end
local function actionTex(slot)
    if not (slot and GetActionTexture) then return nil end
    local ok, t = pcall(GetActionTexture, slot)
    return ok and t or nil
end

local REASON = {
    combat = { "战斗中不能改键位，脱战再来", "Can't change keys in combat" },
    nocmd = { "这一格没有能绑键的命令（条 6-8 请在条插件里设）", "That slot has no bindable command (set it in your bar addon)" },
    bad = { "这个键系统不认、没绑上", "The game rejected that key" },
    api = { "客户端不能改键位", "Key binding not available" },
}
-- 改键结果统一打印（录键 / 模板 / 键盘共用）
function KB.Report(key, ok, why, act)
    -- 成功时：why = "stolen"（顶掉了别的功能）或 nil；act = 原来占着这个键的命令
    if ok then
        if why == "stolen" and act then
            ns.Print("|cffffd100" .. string.format(L("%s 原来是「%s」，已顶替给这一格；那个功能现在没键（%s keys restore 一键放回）。",
                "%s was \"%s\" - replaced; that action has no key now (%s keys restore to put it back)."), bindText(key), bindName(act) or tostring(act), ns.SlashHint or "/gif") .. "|r")
        elseif act then
            ns.Print("|cffffd100" .. string.format(L("%s 原来绑在另一格（%s），已转给这一格；原格现在没键。", "%s moved here from another slot (%s); that slot has no key now."), bindText(key), tostring(act)) .. "|r")
        end
        return
    end
    if why == "taken" then
        ns.Print("|cffff5555" .. string.format(L("%s 是「%s」（移动 / 跳跃 / 聊天这类），不顶替，免得角色动不了；真要用先去游戏按键设置里解开。",
            "%s is \"%s\" (movement / jump / chat) - not replaced; unbind it in Key Bindings first if you really want it."), bindText(key), bindName(act) or "?") .. "|r")
    else
        local r = REASON[why] or REASON.bad
        ns.Print("|cffff5555" .. L(r[1], r[2]) .. (key and ("：" .. bindText(key)) or "") .. "|r")
    end
end

local page, capture, kbf
-- 录键状态放普通表（不挂在框体上）
local CS = {}
KB._cs = CS   -- 测试用
local kbCells, kbModBtns = {}, {}

-- ---------- 录键（正式服 capture 同款：一次进入只结算一次；整组设键 = 队列，Backspace 跳过、Esc 结束）----------
local function slotName(slot)
    local info = K.SlotInfo(slot)
    return info and info.name or (L("格 ", "slot ") .. tostring(slot))
end
local function finishCapture(key)
    if not capture or CS.finished then return end
    CS.finished = true
    local slot = CS.slot; CS.slot = nil; capture:Hide()
    local q = CS.queue
    if slot and key ~= nil and not (q and key == false) then
        local ok, why, act = K.AssignSlotKey(slot, key)
        if ok then KB.Report(key, true, act, why) else KB.Report(key or nil, false, why, act) end
    end
    if q then
        if key == nil or #q == 0 then
            CS.queue, CS.qi, CS.qn = nil, nil, nil
            if key ~= nil then ns.Print(string.format(L("「%s」这一组设完了。", "\"%s\" done."), CS.qlabel or "")) end
        else
            local nxt = table.remove(q, 1)
            CS.qi = (CS.qi or 0) + 1
            C_Timer.After(0.05, function() KB.BeginKeyCapture(nxt, true) end)
        end
    end
    if page and page.refresh then pcall(page.refresh) end
end
KB._finish = finishCapture   -- 测试用
local function withMods(k)
    local m = ""
    if isDown(IsAltKeyDown) then m = m .. "ALT-" end
    if isDown(IsControlKeyDown) then m = m .. "CTRL-" end
    if isDown(IsShiftKeyDown) then m = m .. "SHIFT-" end
    return m .. k
end

local function buildCapture(p)
    local c = CreateFrame("Frame", nil, p)
    c:SetAllPoints(); c:EnableKeyboard(true); c:EnableMouse(true); c:Hide()
    -- SetPropagateKeyboardInput 在战斗中可能进入受保护路径：页面若恰好此时首次创建，脱战再设（正式服同注释）
    if not (InCombatLockdown and InCombatLockdown()) then pcall(c.SetPropagateKeyboardInput, c, false)
    else
        local safe = CreateFrame("Frame"); safe:RegisterEvent("PLAYER_REGEN_ENABLED")
        safe:SetScript("OnEvent", function(self) pcall(c.SetPropagateKeyboardInput, c, false); self:UnregisterAllEvents() end)
    end
    c:SetFrameStrata("DIALOG"); c:SetFrameLevel(150)
    local dim = c:CreateTexture(nil, "BACKGROUND"); dim:SetAllPoints(); dim:SetColorTexture(0, 0, 0, 0.6)
    local box = CreateFrame("Frame", nil, c, BackdropTemplateMixin and "BackdropTemplate" or nil)
    box:SetFrameStrata("DIALOG"); box:SetFrameLevel(200)
    box:SetPoint("CENTER", c, "CENTER", 0, 40); box:SetSize(460, 150)
    if box.SetBackdrop then
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        box:SetBackdropColor(0.06, 0.06, 0.08, 1); box:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
    end
    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge"); hint:SetPoint("TOP", 0, -22); hint:SetWidth(430); hint:SetWordWrap(false)
    local hint2 = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); hint2:SetPoint("TOP", hint, "BOTTOM", 0, -14); hint2:SetWidth(420); hint2:SetJustifyH("CENTER")
    c.hint, c.hint2 = hint, hint2
    c:HookScript("OnShow", function()
        if CS.queue and CS.qn then
            hint:SetText(string.format(L("「%s」第 %d / %d 格：%s", "\"%s\" %d / %d: %s"), CS.qlabel or "", CS.qi or 1, CS.qn, slotName(CS.slot)))
            hint2:SetText(L("按下这一格的新键，自动跳到下一格\nBackspace 跳过这一格 · Esc 结束", "Press the new key - moves on to the next slot\nBackspace skips - Esc stops"))
        else
            hint:SetText(string.format(L("按下新的键位...（%s）", "Press a new key... (%s)"), slotName(CS.slot)))
            hint2:SetText(L("支持 Shift / Ctrl / Alt 组合、鼠标侧键、滚轮\nEsc 取消 · Backspace 不绑", "Shift / Ctrl / Alt combos, mouse buttons and wheel work\nEsc cancels - Backspace unbinds"))
        end
    end)
    c:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then finishCapture(nil)
        elseif key == "BACKSPACE" or key == "DELETE" then finishCapture(false)
        elseif key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then
        else finishCapture(withMods(key)) end
    end)
    -- ⛔ 正式服 09-19：OnMouseDown 给的是 "MiddleButton"，绑定系统认 "BUTTON3"，直接大写去 SetBinding 会静默失败
    c:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" or button == "RightButton" then return end
        local MOUSE_KEY = { MIDDLEBUTTON = "BUTTON3", BUTTON4 = "BUTTON4", BUTTON5 = "BUTTON5" }
        local kb = string.upper(button or "")
        finishCapture(withMods(MOUSE_KEY[kb] or kb))
    end)
    c:SetScript("OnMouseWheel", function(_, d) finishCapture(withMods(d > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")) end)
    return c
end

function KB.BeginKeyCapture(slot, keepQueue)
    if not capture then return end
    if InCombatLockdown and InCombatLockdown() then KB.Report(nil, false, "combat"); CS.queue = nil; return end
    if not keepQueue then CS.queue, CS.qi, CS.qn = nil, nil, nil end
    if slot then CS.finished = nil; CS.slot = slot; capture:Show() end
end
-- 整组设键：slots 按格子在行里的顺序；label = 组名
function KB.BeginGroupKeyCapture(slots, label)
    if not capture then return end
    if InCombatLockdown and InCombatLockdown() then KB.Report(nil, false, "combat"); return end
    local q = {}
    for _, sl in ipairs(slots or {}) do q[#q + 1] = sl end
    if #q == 0 then ns.Print(L("这一组还没有上条的技能，先点「—」放上去", "Nothing of this group is on your bars yet")); return end
    local first = table.remove(q, 1)
    CS.queue, CS.qi, CS.qn, CS.qlabel = q, 1, #q + 1, label
    CS.finished = nil; CS.slot = first; capture:Show()
end
function KB.Capturing() return capture and capture:IsShown() and CS.slot or nil end

-- ---------- 小下拉菜单（键位模板用；不依赖 MenuUtil / EasyMenu，《无限》客户端没验过它们）----------
local menu
function KB.Menu(anchor, title, items)
    if not menu then
        menu = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        menu:SetFrameStrata("FULLSCREEN_DIALOG"); menu:SetClampedToScreen(true); menu:EnableMouse(true)
        if menu.SetBackdrop then
            menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            menu:SetBackdropColor(0.05, 0.05, 0.07, 0.98)
        end
        menu.t = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); menu.t:SetPoint("TOPLEFT", 10, -8)
        menu.rows = {}
        local cl = CreateFrame("Button", nil, menu, "UIPanelCloseButton"); cl:SetSize(20, 20); cl:SetPoint("TOPRIGHT", 0, 0)
    end
    menu.t:SetText(title or "")
    for _, r in ipairs(menu.rows) do r:Hide() end
    for i, it in ipairs(items) do
        local r = menu.rows[i]
        if not r then
            r = CreateFrame("Button", nil, menu)
            r:SetSize(200, 18)
            r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.t:SetPoint("LEFT", 6, 0); r.t:SetJustifyH("LEFT")
            local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.12)
            menu.rows[i] = r
        end
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 6, -24 - (i - 1) * 18)
        r.t:SetText(it.text)
        r:SetScript("OnClick", function() menu:Hide(); pcall(it.fn) end)
        r:Show()
    end
    menu:SetSize(214, 32 + #items * 18)
    menu:ClearAllPoints(); menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    menu:Show()
    return menu
end

-- ---------- 虚拟键盘 ----------
local KB_ROWS = {
    { "`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=" },
    { "TAB", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]" },
    { "CAPSLOCK", "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'" },
    { "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", "SPACE" },
    { "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12" },
    { "BUTTON3", "BUTTON4", "BUTTON5", "MOUSEWHEELUP", "MOUSEWHEELDOWN", "NUMPAD0", "NUMPAD1", "NUMPAD2", "NUMPAD3" },
}
KB.ROWS = KB_ROWS
local KB_LABEL = {
    TAB = { "Tab", "Tab" }, CAPSLOCK = { "Caps", "Caps" }, SPACE = { "Space", "Space" },
    BUTTON3 = { "鼠中", "M3" }, BUTTON4 = { "鼠4", "M4" }, BUTTON5 = { "鼠5", "M5" },
    MOUSEWHEELUP = { "滚上", "WhUp" }, MOUSEWHEELDOWN = { "滚下", "WhDn" },
    NUMPAD0 = { "小0", "Num0" }, NUMPAD1 = { "小1", "Num1" }, NUMPAD2 = { "小2", "Num2" }, NUMPAD3 = { "小3", "Num3" },
}
local MOVE_KEYS = { W = true, S = true, A = true, D = true, Q = true, E = true, SPACE = true }
local WIDE = { TAB = 1.5, CAPSLOCK = 1.75, SPACE = 2.5 }
local ROW_OFF = { 0, 0, 0, 0.9, 0, 0 }

local function kbMod() return (ns.db and ns.db.kbMod) or "" end
local function kbKey(base) local m = kbMod(); return (m ~= "" and (m .. "-") or "") .. base end

local function kbCell()
    local c = CreateFrame("Button", nil, kbf, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if c.SetBackdrop then c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }) end
    c.icon = c:CreateTexture(nil, "ARTWORK"); c.icon:SetPoint("TOPLEFT", 2, -2); c.icon:SetPoint("BOTTOMRIGHT", -2, 2); c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.hi = c:CreateTexture(nil, "OVERLAY"); c.hi:SetPoint("TOPLEFT", 1, -1); c.hi:SetPoint("TOPRIGHT", -1, -1); c.hi:SetHeight(2); c.hi:SetColorTexture(1, 1, 1, 0.14)
    c.cap = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); c.cap:SetPoint("TOPLEFT", 3, -2)
    c.sub = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); c.sub:SetPoint("BOTTOM", 0, 2); c.sub:SetWidth(40); c.sub:SetWordWrap(false)
    c.mark = c:CreateTexture(nil, "OVERLAY"); c.mark:SetSize(8, 8); c.mark:SetPoint("TOPRIGHT", -1, -1); c.mark:SetColorTexture(1, 0.25, 0.25, 1); c.mark:Hide()
    c:SetScript("OnEnter", function(x)
        GameTooltip:SetOwner(x, "ANCHOR_RIGHT")
        GameTooltip:AddLine(bindText(x._key or ""), 1, 0.82, 0)
        if x._slot then
            local info = K.SlotInfo(x._slot)
            if info then
                local kind = (info.t == "macro" and L("宏", "macro")) or (info.t == "item" and L("物品", "item")) or nil
                GameTooltip:AddLine(L("动作条：", "Bar: ") .. (info.name or "?") .. (kind and ("（" .. kind .. "）") or "") .. string.format(L("  (格 %d)", "  (slot %d)"), x._slot), 1, 1, 1)
                if x._plan then GameTooltip:AddLine(L("GI 铺条计划里的技能", "In the GI layout plan"), 1, 0.82, 0) end
            else
                GameTooltip:AddLine(string.format(L("键绑在空格上（格 %d）：键白占着", "Bound to an empty slot (%d)"), x._slot), 1, 0.4, 0.4)
            end
            GameTooltip:AddLine(L("点击 = 给这一格改键", "Click = rebind this slot"), 0.5, 0.75, 1)
        else
            local act = x._act
            if act and act ~= "" then GameTooltip:AddLine(L("现在：", "Now: ") .. (bindName(act) or act), 0.7, 0.7, 0.7)
            else GameTooltip:AddLine(L("现在：空闲", "Now: free"), 0.5, 0.5, 0.5) end
            if x._move then GameTooltip:AddLine(L("留给移动（W A S D Q E 空格）", "Kept for movement"), 0.6, 0.6, 0.6) end
        end
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c:SetScript("OnClick", function(x) if x._slot then KB.BeginKeyCapture(x._slot) end end)
    return c
end

local function layoutKb()
    if not (kbf and kbf:IsShown()) then return end
    local X0, y = 10, -10
    kbf.hd:ClearAllPoints(); kbf.hd:SetPoint("TOPLEFT", X0, y); kbf.hd:SetPoint("RIGHT", kbf, "RIGHT", -30, 0); kbf.hd:SetJustifyH("LEFT"); kbf.hd:SetWordWrap(false)
    kbf.hd:SetText(L("虚拟键盘 · 这一层的键都指向什么", "Virtual keyboard - what each key does on this layer"))
    local mods = { { "", L("无修饰", "None") }, { "SHIFT", "Shift" }, { "CTRL", "Ctrl" }, { "ALT", "Alt" } }
    local x = 0
    for i, m in ipairs(mods) do
        local b = kbModBtns[i]
        if not b then
            b = CreateFrame("Button", nil, kbf, "UIPanelButtonTemplate"); b:SetSize(70, 18); b:SetText(m[2])
            b:SetScript("OnClick", function() ns.db.kbMod = m[1]; KB.Refresh() end)
            kbModBtns[i] = b
        end
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", X0 + x, y - 20); b:SetEnabled(kbMod() ~= m[1]); x = x + 74
    end
    y = y - 44
    kbf.note:ClearAllPoints(); kbf.note:SetPoint("LEFT", kbModBtns[4], "RIGHT", 10, 0); kbf.note:SetPoint("RIGHT", kbf, "RIGHT", -10, 0); kbf.note:SetWordWrap(false); kbf.note:SetJustifyH("LEFT")
    kbf.note:SetText("|cff888888" .. L("金框 = 计划里的技能 · 红角 = 绑在空格上 · 灰 = 留给移动 · 暗字 = 被别的功能占着", "Gold = planned spell - red corner = empty slot - grey = movement - dim = other function") .. "|r")
    local size, gap = 40, 3
    local idx, maxW = 0, 0
    for r, row in ipairs(KB_ROWS) do
        local rx = math.floor(size * (ROW_OFF[r] or 0))
        for _, k in ipairs(row) do
            idx = idx + 1
            local c = kbCells[idx] or kbCell(); kbCells[idx] = c
            c._base = k
            local cw = math.floor(size * (WIDE[k] or 1) + gap * ((WIDE[k] or 1) - 1))
            c:SetSize(cw, size); c:ClearAllPoints(); c:SetPoint("TOPLEFT", X0 + rx, y)
            c:Show()
            rx = rx + cw + gap
        end
        if rx > maxW then maxW = rx end
        y = y - size - gap
    end
    for j = idx + 1, #kbCells do kbCells[j]:Hide() end
    kbf.foot:ClearAllPoints(); kbf.foot:SetPoint("TOPLEFT", X0, y - 2); kbf.foot:SetPoint("RIGHT", kbf, "RIGHT", -10, 0)
    kbf.foot:SetText(L("点键帽 = 给那格改键；Shift / Ctrl / Alt 层切上面按钮看。裸 W A S D Q E / 空格留给移动。",
        "Click a cap to rebind that slot; switch layers above. Bare W A S D Q E / Space stay on movement."))
    kbf:SetSize(X0 * 2 + maxW, -y + 44)
end

local function refreshKb()
    if not (kbf and kbf:IsShown()) then return end
    layoutKb()
    local byKey = K.KeyMap()
    local planned = {}
    for _, p in ipairs(K.Plan()) do if p.name then planned[p.name] = true end end
    local mod = kbMod()
    for _, c in ipairs(kbCells) do
        if c:IsShown() then
            local key = kbKey(c._base)
            c._key = key
            local slot = byKey[key]
            local act
            if GetBindingAction then local ok, a = pcall(GetBindingAction, key); act = ok and a or nil end
            c._slot, c._act, c._plan, c._move = slot or false, act or false, false, false
            local lb = KB_LABEL[c._base]
            c.cap:SetText(lb and L(lb[1], lb[2]) or c._base); c.cap:SetTextColor(1, 1, 1)
            c.icon:SetTexture(nil); c.sub:SetText(""); c.mark:Hide(); c:SetAlpha(1)
            local info = slot and K.SlotInfo(slot)
            if slot and info then
                c.icon:SetTexture(actionTex(slot))
                if info.t == "spell" and planned[info.name] then
                    c._plan = true
                    if c.SetBackdropColor then c:SetBackdropColor(0.1, 0.1, 0.12, 1); c:SetBackdropBorderColor(1, 0.82, 0, 1) end
                else
                    if c.SetBackdropColor then c:SetBackdropColor(0.1, 0.1, 0.12, 1); c:SetBackdropBorderColor(0.7, 0.6, 0.2, 1) end
                    if info.t == "macro" then c.cap:SetTextColor(0.45, 0.8, 1); c.sub:SetText(info.name or "") end
                end
            elseif slot then
                -- 键绑在动作条格上，但那格是空的
                if c.SetBackdropColor then c:SetBackdropColor(0.06, 0.06, 0.08, 1); c:SetBackdropBorderColor(0.45, 0.3, 0.3, 1) end
                c.mark:Show(); c.sub:SetText(L("空格", "empty"))
            elseif mod == "" and MOVE_KEYS[c._base] then
                c._move = true
                if c.SetBackdropColor then c:SetBackdropColor(0.16, 0.16, 0.18, 1); c:SetBackdropBorderColor(0.35, 0.35, 0.38, 1) end
                c.sub:SetText(L("移动", "move")); c:SetAlpha(0.85)
            elseif act and act ~= "" then
                if c.SetBackdropColor then c:SetBackdropColor(0.08, 0.08, 0.1, 1); c:SetBackdropBorderColor(0.3, 0.3, 0.32, 1) end
                c.sub:SetText("|cff777777" .. tostring(bindName(act)):sub(1, 6) .. "|r")
            else
                if c.SetBackdropColor then c:SetBackdropColor(0.04, 0.04, 0.06, 1); c:SetBackdropBorderColor(0.2, 0.2, 0.22, 1) end
                c:SetAlpha(0.8)
            end
        end
    end
end
KB.Refresh = refreshKb
KB._cells = kbCells   -- 测试用

local function buildKb(p)
    local f = CreateFrame("Frame", "GearInsightForeverVirtualKeyboard", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(600, 320); f:SetFrameStrata("DIALOG")
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.05, 0.05, 0.08, 0.97); f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.6)
    end
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(x)
        x:StopMovingOrSizing()
        local pt, _, rp, px, py = x:GetPoint()
        ns.db.kbPos = { pt, rp, px, py }
    end)
    local pos = ns.db.kbPos
    if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        -- 默认贴主面板右边；右外侧挂着公会页签时让开它
        local main = _G.GearInsightForeverMain
        local gt = main and rawget(main, "_giGuildTab")
        local dx = 6
        if type(gt) == "table" and gt.GetWidth then local ok, w = pcall(gt.GetWidth, gt); if ok and type(w) == "number" then dx = dx + w end end
        f:SetPoint("TOPLEFT", main or p, "TOPRIGHT", dx, 0)
    end
    local x = CreateFrame("Button", nil, f, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT", 2, 2)
    x:SetScript("OnClick", function() f:Hide(); ns.db.kbOpen = nil end)
    f.hd = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.note:SetJustifyH("LEFT")
    f.foot = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.foot:SetJustifyH("LEFT"); f.foot:SetWordWrap(true)
    f:Hide()
    f:SetScript("OnShow", function() refreshKb() end)
    return f
end

function KB.Toggle(on)
    if not kbf then return end
    if on == nil then on = not kbf:IsShown() end
    if on then ns.db.kbOpen = true; kbf:Show() else ns.db.kbOpen = nil; kbf:Hide() end
    return on
end
function KB.Shown() return kbf and kbf:IsShown() or false end

-- 键位页 build 时接上：录键框盖住键位页；键盘只跟键位页走（切到别的页藏掉，切回来按开关状态带回 —— 正式服 09-19 同规则）
function KB.Attach(p)
    page = p
    capture = buildCapture(p)
    kbf = buildKb(p)
    KB._capture, KB._kbf = capture, kbf   -- 测试用
    p:HookScript("OnHide", function() if kbf then kbf:Hide() end; if capture and capture:IsShown() then finishCapture(nil) end end)
    p:HookScript("OnShow", function()
        -- ⛔ IsVisible 不是 IsShown（正式服 09-25：IsShown 只看自己的标记，主面板没开也是真 → 一进游戏键盘就弹）
        C_Timer.After(0, function() if ns.db.kbOpen and p:IsVisible() and kbf and not kbf:IsShown() then kbf:Show() end end)
    end)
    if ns.db.kbOpen then C_Timer.After(0, function() if p:IsVisible() and kbf then kbf:Show() end end) end
end
