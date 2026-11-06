-- 键位页（10-10 立项；10-12 照正式服 10-12「阶段 3」拆页：键位 / 手法 两个独立页签，手法在 PageRot.lua）
--   照正式服 GearInsight_Layout/ui/LayoutPage.lua「替换」视图：
--   顶部 当前天赋系 + 待处理行 + 右上「虚拟键盘」→ 中部 按组分行（前 5 行 = 手法助手 5 轨：主循环 / 短冷却 / 大招 / 生存 / 控制，
--   其余收进「其他」默认折叠；每组行头「设键」「模板」）→ 底部 还原上次 / 高级（10-16 用户「删掉，不要这个按钮了」：一键全铺去掉）
--   格子：左键 = 给这一格改键（同虚拟键盘点键帽）；不在条上的点「—」放上去。
--   《无限》差异：正式服面板是「计划键」，点「将插件建议实现到动作条」才绑；这里一直是实况（保留你的键位），改键立刻生效。
-- ⛔ 不碰宏。⛔ HOLD（_hold.txt），测完才进包。
local _, ns = ...
local K = ns.Keys

local page
local GAP = 5
-- 10-16 用户「UI 优化」：版面按固定网格排（页 670 × 474）
--   页头 0–34 · 状态区 42–86（左两行提示，右：上虚拟键盘、下形态分段按钮）· 间距 8 · 滚动区 94 起 · 间距 8 · 底栏（高 24，距底 10）
local L_PAGE_H = 474
local L_SCROLL_Y = 94            -- 滚动区顶（状态区底 86 + 8）
local L_SCROLL_W = 610           -- 右边给滚动条留 ~26px，滚动条不压组头按钮
local L_BAR_H, L_BAR_B = 24, 10  -- 底栏按钮高 / 距底
local L_FORM_W, L_FORM_GAP = 64, 2
local L_KB_W = 96

local function shortKey(k)
    if not k then return nil end
    return (k:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A"):gsub("BUTTON", "M"):gsub("MOUSEWHEELUP", "WU"):gsub("MOUSEWHEELDOWN", "WD"))
end
ns.KeysShortKey = shortKey

-- 正式服 cellSize：每格 ≥ 44px，列数 4~8 按当前宽度算，格子最大 72px（窄分辨率 / 大缩放不裁格）
local function cellSize()
    local w = page.scroll and page.scroll.GetWidth and page.scroll:GetWidth()
    if type(w) ~= "number" or w < 100 then w = 616 end
    local cols = math.max(4, math.min(8, math.floor((w - 4 + GAP) / (44 + GAP))))
    return math.max(40, math.min(72, math.floor((w - 4 - (cols - 1) * GAP) / cols))), cols
end

-- 选中样式：金色粗边框 + 金色底光 + 白字（同 PageProf.lua；⛔别用禁用变灰表示选中）
local SEL = setmetatable({}, { __mode = "k" })
local function markSel(b, on)
    local box = SEL[b]
    if not box then
        box = {}
        SEL[b] = box
        local glowTex = b:CreateTexture(nil, "OVERLAY")
        glowTex:SetPoint("TOPLEFT", 3, -3); glowTex:SetPoint("BOTTOMRIGHT", -3, 3)
        glowTex:SetColorTexture(1, 0.82, 0, 0.28); glowTex:SetBlendMode("ADD")
        box[1] = glowTex
        for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
            { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
            local t = b:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(1, 0.85, 0.1, 1)
            t:SetPoint(side[1]); t:SetPoint(side[2])
            if side[3] then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
            box[#box + 1] = t
        end
    end
    b:SetEnabled(true)
    for _, t in ipairs(box) do t:SetShown(on) end
    if b.SetNormalFontObject then b:SetNormalFontObject(on and "GameFontHighlight" or "GameFontNormal") end
end

-- 这一格的键随不随形态变：主条 1–12 / 形态页（换形态 / 姿态后同一个键按出来的是另一页）
local function formSlot(slot)
    if not slot then return false end
    if slot >= 1 and slot <= 12 then return true end
    for _, pg in ipairs(K.FORM_PAGES or {}) do if slot >= pg[1] and slot <= pg[2] then return true end end
    return false
end


-- ---------- 10-16 「放到哪一格」面板 + 形态问询 ----------
-- 用户：「切换状态，所有这个状态能用的技能都要能设置才对」「设置 123456 的时候，多弹出一个对话框问是设置给哪个形态的」「右键设置，左键拿起」
--   左键技能格 = 拿到鼠标上；右键 = 这个面板：主条 12 个位置（按键 1 至 =，主条键锁死）+ 左下 / 右下条。
--   点主条位置：学会 2 个以上形态就先问放进哪个形态的那一页（不能用这个技能的形态灰掉）；只有一个形态 / 没形态直接放。
local CELL_TIP = { "左键：拿到鼠标上 · 右键：设置快捷键（按 1 至 = 先选形态、把技能移过去；按其他键，技能要先在动作条上）",
    "Left-click: pick it up · Right-click: set a key (1 to =: pick the form, the spell moves there; other keys need the spell on a bar)" }
ns.KeysCellTip = CELL_TIP   -- 测试用
local function slotTex(sl)
    local t = GetActionTexture and GetActionTexture(sl)
    return t or "Interface\\Buttons\\UI-Quickslot2"
end
local function soleView()
    local d = ns.KeysForms and ns.KeysForms[ns.MyClass()]
    if not d then return nil end
    local only
    for _, f in ipairs(d.forms or {}) do
        if K.FormKnown(f) then
            if only then return nil end
            only = f
        end
    end
    return only and { key = only.key, page = only.page, zh = only.zh, en = only.en, d = d } or nil
end
local function mainKeyText(n)
    return K.SlotKey(n) or K.MAIN_DEFAULT[n] or tostring(n)
end
local function dlgFrame(name, w, h)
    local f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(w, h); f:SetPoint("CENTER", 0, 60); f:SetFrameStrata("DIALOG")
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.05, 0.05, 0.07, 0.97)
    end
    f:EnableMouse(true)
    f.t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.t:SetPoint("TOPLEFT", 12, -10); f.t:SetPoint("RIGHT", -12, 0); f.t:SetJustifyH("LEFT")
    f:Hide()
    return f
end

-- 形态问询（通用）：choices = K.FormChoices(...)；pre = 默认选中的形态 key；onPick(view)
local formDlg
function ns.KeysChooseForm(title, choices, pre, onPick, usableTip)
    if not formDlg then
        formDlg = dlgFrame("GearInsightForeverKeysFormAsk", 360, 112)
        formDlg.btns = {}
        formDlg.cancel = ns.Button(formDlg, ns.L("取消", "Cancel"), 70, 20, function() formDlg:Hide() end)
        formDlg.cancel:SetPoint("BOTTOMRIGHT", -10, 8)
        ns.KeysFormDlg = formDlg   -- 测试用
    end
    local d = formDlg
    d.t:SetText(ns.EnSafe(title))
    for _, b in ipairs(d.btns) do b:Hide() end
    if not pre then for _, c in ipairs(choices) do if c.usable then pre = c.view.key; break end end end
    d.pre = pre
    local bw = math.floor((340 - (#choices - 1) * 6) / #choices)
    for i, c in ipairs(choices) do
        local b = d.btns[i]
        if not b then b = ns.Button(d, "", bw, 26); d.btns[i] = b end
        b:SetSize(bw, 26); b:ClearAllPoints(); b:SetPoint("TOPLEFT", 10 + (i - 1) * (bw + 6), -42)
        b:SetText(ns.L(c.view.zh, c.view.en))
        b.view, b.usable = c.view, c.usable
        b:SetScript("OnClick", function() d:Hide(); onPick(c.view) end)
        markSel(b, c.view.key == pre)
        b:SetEnabled(c.usable)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(ns.L(c.view.zh, c.view.en), 1, 0.82, 0)
            GameTooltip:AddLine(c.usable and (usableTip or "") or ns.L("这个技能在这个形态下用不了", "This spell can't be used in this form"), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Show()
    end
    d:Show()
end
local function preForm(choices)
    local cur = K.ActiveView and K.ActiveView()
    for _, c in ipairs(choices) do if c.usable and cur and c.view.key == cur.key then return c.view.key end end
end
local function formWhere(v, n)
    if v and v.page then
        return string.format(ns.L("%s动作条第 %d 个位置（按键 %s）", "%s bar position %d (key %s)"), ns.L(v.zh, v.en), n, mainKeyText(n))
    elseif v then
        return string.format(ns.L("%s：主动作条第 %d 格（按键 %s）", "%s: main bar slot %d (key %s)"), ns.L(v.zh, v.en), n, mainKeyText(n))
    end
    return string.format(ns.L("主动作条第 %d 格（按键 %s）", "main bar slot %d (key %s)"), n, mainKeyText(n))
end
ns.KeysFormWhere = formWhere

-- 第 n 个主条位置（键 1 至 =）放技能：学会 2 个以上形态先问形态
function ns.KeysAskForm(p, n)
    local choices = K.FormChoices(p)
    if not choices then
        local v = soleView()
        return K.PlaceSpellAt(p, K.MainPosSlot(n, v), formWhere(v, n))
    end
    ns.KeysChooseForm(string.format(ns.L("「%s」放到哪个形态的第 %d 个位置（按键 %s）？", "Put %s into which form's position %d (key %s)?"), p.name or "?", n, mainKeyText(n)),
        choices, preForm(choices), function(v) K.PlaceSpellAt(p, K.MainPosSlot(n, v), formWhere(v, n)) end,
        string.format(ns.L("放进这个形态那一页的第 %d 格；在这个形态下按 %s 放它", "Goes to position %d of this form's page; press %s in this form"), n, mainKeyText(n)))
end
-- 第 n 个主条位置清掉：学会 2 个以上形态先问清哪个形态的
function ns.KeysAskClear(n)
    local choices = K.FormChoices(nil)
    if not choices then
        local v = soleView()
        return K.ClearSlot(K.MainPosSlot(n, v), formWhere(v, n))
    end
    ns.KeysChooseForm(string.format(ns.L("清除哪个形态的第 %d 个位置（按键 %s）？键本身不动", "Clear position %d (key %s) of which form? The key stays"), n, mainKeyText(n)),
        choices, preForm(choices), function(v) K.ClearSlot(K.MainPosSlot(n, v), formWhere(v, n)) end,
        ns.L("清掉这个形态那一页这一格的技能", "Clears that slot on this form's page"))
end

-- 放到哪一格
local picker
local PICK_ROWS = {
    { key = "main", n = { "主动作条位置（按键 1 至 =，键固定；选了会先问哪个形态）", "Main bar positions (keys 1 to =, fixed; you pick the form)" } },
    { key = "bl", from = 61, n = { "左下动作条", "Bottom-left bar" } },
    { key = "br", from = 49, n = { "右下动作条", "Bottom-right bar" } },
}
-- 给技能所在的格设键：不在条上 → 提示先右键放进去；在主条 / 形态页 → 键固定（1 至 =），换位置用右键
function ns.KeysSetKeyFor(p)
    local sl = p and p.slot
    if not sl then
        ns.Print(ns.L("这个技能还没放上动作条：先右键选一格放进去，再设键", "Not on your bars yet - right-click to place it first")); return
    end
    local cmd = K.SlotCommand(sl)
    if (sl >= 1 and sl <= 12) or (sl >= 73 and sl <= 120) or (K.IsMainCmd and K.IsMainCmd(cmd)) then
        ns.Print(ns.L("这一格在主动作条 / 形态页，键固定是 1 至 =；想换键就右键把技能放到左下 / 右下动作条", "Main bar / form page keys are fixed (1 to =) - right-click to move it to another bar")); return
    end
    if ns.KeysKb and ns.KeysKb.BeginKeyCapture then ns.KeysKb.BeginKeyCapture(sl) end
end

function ns.KeysOpenPicker(p)
    if not (p and p.id) then return end
    if not picker then
        picker = dlgFrame("GearInsightForeverKeysPicker", 452, 262)
        picker.rows = {}
        local y = -32
        for ri, r in ipairs(PICK_ROWS) do
            local lb = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lb:SetPoint("TOPLEFT", 12, y); lb:SetText(ns.L(r.n[1], r.n[2]))
            y = y - 16
            local row = {}
            for i = 1, 12 do
                local b = CreateFrame("Button", nil, picker)
                b:SetSize(32, 32); b:SetPoint("TOPLEFT", 12 + (i - 1) * 35, y)
                b.ic = b:CreateTexture(nil, "ARTWORK"); b.ic:SetAllPoints()
                b.k = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.k:SetPoint("TOPLEFT", 1, -1)
                local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.2)
                row[i] = b
            end
            picker.rows[ri] = row
            y = y - 40
        end
        picker.pick = ns.Button(picker, ns.L("拿到鼠标上自己放", "Pick it up instead"), 140, 20, function() picker:Hide(); K.PlaceMissing(picker.p) end)
        picker.pick:SetPoint("BOTTOMLEFT", 10, 8)
        picker.cancel = ns.Button(picker, ns.L("取消", "Cancel"), 70, 20, function() picker:Hide() end)
        picker.cancel:SetPoint("BOTTOMRIGHT", -10, 8)
        -- 10-16 用户「右键清除技能的所有快捷键设置并放回法术书」：同一个动作也放在这里
        picker.clearAll = ns.Button(picker, ns.L("清除这个技能的所有位置", "Remove from all slots"), 160, 20, function() picker:Hide(); K.ClearSpellEverywhere(picker.p.name) end)
        picker.clearAll:SetPoint("LEFT", picker.pick, "RIGHT", 8, 0)
        -- 10-16「点击没办法设置快捷键了」：这个技能已经在某一格（左下 / 右下条等）→ 直接给那一格设键
        picker.setKey = ns.Button(picker, "", 220, 20, function() picker:Hide(); ns.KeysSetKeyFor(picker.p) end)
        picker.setKey:SetPoint("BOTTOMLEFT", 10, 32)
        ns.KeysPicker = picker   -- 测试用
    end
    picker.p = p
    picker.setKey:SetText(p.slot and string.format(ns.L("给它现在那一格（第 %d 格）设键", "Set a key for its slot (%d)"), p.slot) or ns.L("先放上动作条才能设键", "Place it first to set a key"))
    picker.setKey:SetEnabled(p.slot ~= nil)
    picker.t:SetText(ns.EnSafe(string.format(ns.L("把「%s」放到哪一格？", "Where should %s go?"), p.name or "?")))
    local cur = (K.ActiveView and K.ActiveView()) or soleView()
    for ri, r in ipairs(PICK_ROWS) do
        for i, b in ipairs(picker.rows[ri]) do
            local sl = r.key == "main" and K.MainPosSlot(i, cur) or (r.from + i - 1)
            b.slot = sl
            b.ic:SetTexture(slotTex(sl))
            b.k:SetText(shortKey(r.key == "main" and mainKeyText(i) or K.SlotKey(sl)) or "")
            b:SetScript("OnClick", function()
                picker:Hide()
                if r.key == "main" then ns.KeysAskForm(p, i)
                else
                    local where = string.format(ns.L("%s第 %d 格（按键 %s）", "%s slot %d (key %s)"), ns.L(r.n[1], r.n[2]), i, K.SlotKey(sl) or ns.L("没绑键", "unbound"))
                    K.PlaceSpellAt(p, sl, where)
                end
            end)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                local info = K.SlotInfo(sl)
                GameTooltip:AddLine((info and info.name) or ns.L("空格", "Empty"), 1, 0.82, 0)
                GameTooltip:AddLine(string.format(ns.L("动作条第 %d 格", "Action slot %d"), sl), 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end
    picker:Show()
end

local function getCell(i)
    local c = page.cells[i]
    if c then return c end
    c = CreateFrame("Button", nil, page.child, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if c.SetBackdrop then
        c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
        c:SetBackdropColor(0, 0, 0, 0.6)
    end
    c.ic = c:CreateTexture(nil, "ARTWORK"); c.ic:SetPoint("TOPLEFT", 2, -2); c.ic:SetPoint("BOTTOMRIGHT", -2, 2); c.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.keyBg = c:CreateTexture(nil, "OVERLAY"); c.keyBg:SetPoint("TOPLEFT", 2, -2); c.keyBg:SetPoint("TOPRIGHT", -2, -2); c.keyBg:SetHeight(15); c.keyBg:SetColorTexture(0, 0, 0, 0.75)
    c.key = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); c.key:SetPoint("TOPLEFT", 3, -1); c.key:SetPoint("RIGHT", -2, 0); c.key:SetJustifyH("LEFT"); c.key:SetWordWrap(false)
    c.num = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); c.num:SetPoint("BOTTOMRIGHT", -2, 1); c.num:SetTextColor(0.65, 0.65, 0.65)
    c.dash = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); c.dash:SetPoint("CENTER", 0, -4); c.dash:SetText("|cffffd100—|r")
    -- 10-16 用户「各形态公用技能要列出来」：几个形态都能用的技能左下角标「通用」
    c.shared = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); c.shared:SetPoint("BOTTOMLEFT", 2, 1); c.shared:Hide()
    local hl = c:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
    -- 10-16 用户「右键设置，左键拿起」：左键 = 拿到鼠标上；右键 = 选一格放进去。改键走虚拟键盘 / 设键 / 模板
    if c.RegisterForClicks then c:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    c:SetScript("OnClick", function(self, button)
        local p = self.p
        if not p then return end
        -- 10-16 用户「现在点击怎么没办法设置快捷键了」：Shift+左键 = 给这个技能所在的那一格设键（主条 / 形态页的键锁死，提示去右键换位置）
        if button == "RightButton" then
            if ns.KeysKb and ns.KeysKb.BeginSpellKeyCapture then ns.KeysKb.BeginSpellKeyCapture(p) end
        else K.PlaceMissing(p) end
    end)
    c:SetScript("OnEnter", function(self)   -- 小格子显示不全 → 悬停看全（用户硬规定）
        local p = self.p
        if not p then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(p.name or "?", 1, 0.82, 0)
        local rn = K.ROLE_NAME[p.role]
        GameTooltip:AddLine(ns.L(rn and rn[1] or "", rn and rn[2] or ""), 0.7, 0.7, 0.7)
        if self._sharedNames then
            GameTooltip:AddLine(ns.L("这些形态都能用：", "Usable in: ") .. self._sharedNames, 1, 0.85, 0.3, true)
        end
        if p.slot then
            GameTooltip:AddLine(p.key and (ns.L("按键：", "Key: ") .. p.key) or ns.L("在动作条上，但这格没绑键", "On your bars but that slot has no key"), 1, 1, 1)
            GameTooltip:AddLine(string.format(ns.L("动作条第 %d 格", "Action slot %d"), p.slot), 0.6, 0.6, 0.6)
            local v = K.ActiveView and K.ActiveView()
            if v and formSlot(p.slot) then
                GameTooltip:AddLine(string.format(ns.L("主条的键：在「%s」下按这个键放的是这一格；换形态 / 姿态后同一个键会变成别的技能", "Main-bar key: in %s this key casts this slot; it changes with your form / stance"),
                    ns.L(v.zh, v.en)), 1, 0.85, 0.3, true)
            end
        else
            GameTooltip:AddLine(ns.L("不在动作条上", "Not on your bars"), 0.2, 1, 0.6, true)
        end
        GameTooltip:AddLine(ns.L(CELL_TIP[1], CELL_TIP[2]), 0.5, 0.75, 1, true)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.cells[i] = c
    return c
end

-- 组行头：名字 + 个数 + 说明，右边「设键」「模板」
local function getHdr(i)
    local h = page.hdrs[i]
    if h then return h end
    h = CreateFrame("Frame", nil, page.child)
    h:SetHeight(20)
    h.t = h:CreateFontString(nil, "OVERLAY", "GameFontNormal"); h.t:SetPoint("LEFT", 2, 0); h.t:SetPoint("RIGHT", -110, 0); h.t:SetJustifyH("LEFT"); h.t:SetWordWrap(false)
    h.set = ns.Button(h, ns.L("设键", "Set keys"), 44, 18, function(self)
        local x = self:GetParent()
        if x._slots and ns.KeysKb then ns.KeysKb.BeginGroupKeyCapture(x._slots, x._label) end
    end)
    h.set:SetPoint("RIGHT", -66, 0)
    h.set:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.L("设键", "Set keys"), 1, 0.82, 0)
        GameTooltip:AddLine(ns.L("这一组上了条的格子从左到右依次录键：按一个键 = 绑这一格并跳到下一格；Backspace 跳过；Esc 结束。立刻生效。",
            "Record keys for this group left to right: press a key to bind it and move on; Backspace skips; Esc stops. Applies right away."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    h.set:SetScript("OnLeave", function() GameTooltip:Hide() end)
    h.tpl = ns.Button(h, ns.L("模板", "Preset"), 56, 18, function(self)
        local x = self:GetParent()
        if not (x._slots and ns.KeysKb) then return end
        local items = {}
        for _, t in ipairs(K.KEY_TEMPLATES) do
            local lb = type(t.label) == "table" and ns.L(t.label[1], t.label[2]) or t.label
            items[#items + 1] = { text = lb, fn = function()
                local n, skipped, stolen = K.ApplyKeyTemplate(x._slots, t)
                ns.Print(string.format(ns.L("「%s」前 %d 格套用 %s", "\"%s\": %d slots set to %s"), x._label or "", n, lb)
                    .. ((stolen and #stolen > 0) and ("  |cffffd100" .. ns.L("顶替了原功能：", "replaced: ") .. table.concat(stolen, " ")
                        .. ns.L("（" .. (ns.SlashHint or "/gif") .. " keys restore 放回）", " (" .. (ns.SlashHint or "/gif") .. " keys restore)") .. "|r") or "")
                    .. ((#skipped > 0) and ("  |cffff5555" .. ns.L("跳过（主动作条的格 / 键锁死，移动 / 聊天键不顶替）：", "skipped (main bar is fixed; movement / chat keys kept): ") .. table.concat(skipped, " ") .. "|r") or ""))
                if page.refresh then page.refresh() end
            end }
        end
        ns.KeysKb.Menu(self, string.format(ns.L("「%s」套用键位模板", "\"%s\" key preset"), x._label or ""), items)
    end)
    h.tpl:SetPoint("RIGHT", -6, 0)
    h.tpl:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.L("模板", "Preset"), 1, 0.82, 0)
        GameTooltip:AddLine(ns.L("给这一组从左到右套一套键（1-6、QERFTG、ZXCVB、Shift / Alt / Ctrl 组合、F 键、鼠标侧键）；格子比模板多的不改。撞键时键从原来那格拿过来；被移动 / 界面占着的键不抢。",
            "Give this group a key set left to right; extra slots unchanged. A key taken by another slot moves here; keys used by movement / UI are kept."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    h.tpl:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.hdrs[i] = h
    return h
end

local function refresh()
    if not page or not page:IsShown() then return end
    for _, c in ipairs(page.cells) do c:Hide() end
    for _, h in ipairs(page.hdrs) do h:Hide() end
    page.miscBtn:Hide(); page.empty:Hide()
    -- 10-16 形态切换：按选中的形态算（没有形态数据 / 没形态的职业 = nil = 老样子）
    local view = K.ActiveView and K.ActiveView() or nil
    local rows, missing = K.Status(nil, view)
    local forms = view and K.Forms() or nil
    for k, b in pairs(page.formBtns) do
        local f = forms and K.FormByKey(k)
        b:SetShown(f ~= nil)
        if f then markSel(b, view.key == k) end
    end
    -- 学会的形态从右往左排成一行分段按钮（没学的不占位），在「虚拟键盘」正下方右对齐
    local fx = -12
    for i = #(forms or {}), 1, -1 do
        local b = page.formBtns[forms[i].key]
        if b then b:ClearAllPoints(); b:SetPoint("TOPRIGHT", fx, -66); fx = fx - (L_FORM_W + L_FORM_GAP) end
    end
    -- 第二行提示的右边界 = 形态按钮左边再空 12；没形态就只让开页边
    page.miss:SetPoint("RIGHT", forms and (fx - 12 + L_FORM_GAP) or -12, 0)
    local size, cols = cellSize()
    local miscOpen = ns.db.keysMiscOpen
    if miscOpen == nil and view then miscOpen = true end   -- 形态视图：这个形态能用的技能全列出来（10-16「很多熊的技能没识别」）
    local y, n, nh = 0, 0, 0
    local miscN = 0
    for _, grp in ipairs(K.Grouped(rows)) do if grp.g.fold then miscN = miscN + #grp.items end end
    for _, grp in ipairs(K.Grouped(rows)) do
        local g = grp.g
        -- 11-05 用户截图「这里展示优化下」：展开时「其他 6 个 · 点击收起」和下面组行头「其他 6 个 · 位移 / 增益…」重复两行
        --   → 展开时不再单画一行，「点击收起」并进组行头（行头左边文字区就是收起按钮）；收起时照旧一行「…点击展开」
        local foldHere = g.fold and miscN > 0
        if foldHere and not miscOpen then
            local mb = page.miscBtn
            mb:ClearAllPoints(); mb:SetPoint("TOPLEFT", 0, y); mb:SetPoint("RIGHT", page.child, "RIGHT", -4, 0); mb:SetHeight(18); mb:Show()
            mb.t:SetText(string.format("|cffa3a9b5%s|r  |cff777777%d%s · %s|r", ns.L(g.n[1], g.n[2]), miscN, ns.L(" 个", ""),
                miscOpen and ns.L("点击收起", "click to collapse") or ns.L("位移 / 增益 / 姿态 / 功能 ... 点击展开", "movement / buffs / stances ... click to expand")))
            y = y - 22
        end
        if #grp.items > 0 and (not g.fold or miscOpen) then
            nh = nh + 1
            local h = getHdr(nh)
            local slots = {}
            for _, p in ipairs(grp.items) do if p.slot then slots[#slots + 1] = p.slot end end
            h._slots, h._label = slots, ns.L(g.n[1], g.n[2])
            h:ClearAllPoints(); h:SetPoint("TOPLEFT", 0, y); h:SetPoint("RIGHT", page.child, "RIGHT", -4, 0)
            local hex = string.format("%02x%02x%02x", math.floor(g.c[1] * 255), math.floor(g.c[2] * 255), math.floor(g.c[3] * 255))
            h.t:SetText(string.format("|cff%s%s|r  |cff777777%d%s · %s|r", hex, ns.L(g.n[1], g.n[2]), #grp.items, ns.L(" 个", ""), ns.L(g.d[1], g.d[2]))
                .. (foldHere and ("  |cffa3a9b5" .. ns.L("点击收起", "click to collapse") .. "|r") or ""))
            h.set:SetEnabled(#slots > 0); h.tpl:SetEnabled(#slots > 0)
            h:Show()
            if foldHere then   -- 收起按钮盖在行头文字区上（不盖「设键」「模板」），自己不写字
                local mb = page.miscBtn
                mb.t:SetText("")
                mb:ClearAllPoints(); mb:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0); mb:SetPoint("BOTTOMRIGHT", h.set, "BOTTOMLEFT", -6, 0)
                if mb.SetFrameLevel and h.GetFrameLevel then mb:SetFrameLevel((h:GetFrameLevel() or 0) + 2) end
                mb:Show()
            end
            y = y - 22
            local col = 0
            -- 形态视图：这个形态专用的排前面，几个形态公用的排后面（同类里保持原顺序）
            local items = grp.items
            if view then
                local only, shared = {}, {}
                for _, p in ipairs(grp.items) do
                    local sf = K.SharedForms(p)
                    p._shared = (sf and #sf > 1) and sf or nil
                    if p._shared then shared[#shared + 1] = p else only[#only + 1] = p end
                end
                items = only
                for _, p in ipairs(shared) do items[#items + 1] = p end
            end
            for _, p in ipairs(items) do
                if col >= cols then col = 0; y = y - size - GAP end
                n = n + 1
                local c = getCell(n)
                c.p = p
                c:SetSize(size, size)
                c:ClearAllPoints(); c:SetPoint("TOPLEFT", col * (size + GAP), y)
                -- 10-17 种族 / 通用技能数据里没有图标名（截图一排问号）→ 用游戏自己的技能图标
                local tex = ((p.e.i or "") ~= "") and ("Interface\\Icons\\" .. p.e.i) or nil
                if not tex and p.id then
                    if C_Spell and C_Spell.GetSpellTexture then local ok, t = pcall(C_Spell.GetSpellTexture, p.id); if ok then tex = t end end
                    if not tex and GetSpellTexture then local ok, t = pcall(GetSpellTexture, p.id); if ok then tex = t end end
                end
                c.ic:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
                local on = p.slot ~= nil
                c.ic:SetDesaturated(not on); c.ic:SetAlpha(on and 1 or (p.placeable and 0.55 or 0.3))
                if c.SetBackdropBorderColor then c:SetBackdropBorderColor(g.c[1], g.c[2], g.c[3], on and 0.95 or 0.35) end
                c.key:SetText(on and (shortKey(p.key) or "|cffff5555?|r") or "")
                c.keyBg:SetShown(on)
                c.num:SetText(on and tostring(p.slot) or "")
                c.dash:SetShown(not on and (p.placeable or view ~= nil))
                local sf = view and p._shared
                c.shared:SetText(sf and ("|cffffd100" .. ns.L("通用", "All") .. "|r") or "")
                c.shared:SetShown(sf and true or false)
                if sf then
                    local nm = {}
                    for _, f in ipairs(sf) do nm[#nm + 1] = ns.L(f.zh, f.en) end
                    c._sharedNames = table.concat(nm, ns.L("、", ", "))
                else
                    c._sharedNames = nil
                end
                c:Show()
                col = col + 1
            end
            y = y - size - GAP - 6
        end
    end
    if n == 0 then
        page.empty:ClearAllPoints(); page.empty:SetPoint("TOPLEFT", 0, -10); page.empty:Show()
    end
    page.child:SetHeight(-y + 8)
    page.miss:SetText((view and ("|cffffd100" .. ns.L(view.zh, view.en) .. "|r" .. ns.L("：", ": ")) or "") .. (missing > 0 and string.format(ns.L("|cffffd100%d|r 个技能不在条上 · 左键拿起放上动作条 · 右键设置快捷键", "|cffffd100%d|r spells not on your bars - left-click to pick up - right-click to set a key"), missing)
        or ns.L("|cff33ff99该上条的技能都在条上了|r · 左键拿起 · 右键设置快捷键", "|cff33ff99Everything is on your bars|r - left-click to pick up - right-click to set a key")))
    local tree, pts = K.MainTree()
    page.spec:SetText(ns.EnSafe(ns.L("当前：", "Now: ") .. (tree and ns.L("第 " .. tree .. " 系 · " .. pts .. " 点", "tree " .. tree .. " - " .. pts .. " pts") or ns.L("天赋未满 10 点，按职业通用", "under 10 talent points - class default"))))
    page.kbBtn:SetText(ns.KeysKb and ns.KeysKb.Shown() and ns.L("收起键盘", "Hide keyboard") or ns.L("虚拟键盘", "Keyboard"))
    page.advBtn:SetText(page.adv:IsShown() and ns.L("收起高级", "Hide advanced") or ns.L("高级", "Advanced"))
    if page.cdmBtn and ns.KeysCdm then
        local has = ns.KeysCdm.Available()
        page.cdmBtn:SetText(not has and ns.L("这个客户端没有冷却管理器", "No cooldown manager here")
            or (ns.KeysCdm.Enabled() and ns.L("冷却管理器显示快捷键：开", "Keys on cooldowns: on") or ns.L("冷却管理器显示快捷键：关", "Keys on cooldowns: off")))
        page.cdmBtn:SetEnabled(has)
    end
    -- 备份列表（高级区）
    local B = ns.db.keysBackups or {}
    page.restore:SetEnabled(#B > 0)
    if page.adv:IsShown() then
        for i, r in ipairs(page.bkRows) do
            local s = B[i]
            r:SetShown(s ~= nil)
            if s then r.t:SetText(date("%m-%d %H:%M", s.at) .. "  " .. (s.why or "")); r.snap = s end
        end
    end
    if ns.KeysKb then ns.KeysKb.Refresh() end
end

local function build(p)
    page = p
    ns.KeysPageBuilt = true
    ns.KeysPage = p   -- 测试用（同 ns.LootPage）
    p.layout = { pageH = L_PAGE_H, scrollY = L_SCROLL_Y, scrollW = L_SCROLL_W, barH = L_BAR_H, barB = L_BAR_B, formW = L_FORM_W, kbW = L_KB_W }
    p.cells, p.hdrs = {}, {}
    p.refresh = refresh
    ns.PageHeader(p, ns.L("键位", "Keys"),
        ns.L("保留你的键位：左键拿起技能自己放 · 右键设置快捷键（按 1 至 = 先选形态、技能移过去；其他键要先放上动作条）· 也可用虚拟键盘 / 设键 / 模板",
            "Keep your keys: left-click to pick a spell up - right-click to choose a slot (for 1 to = pick the form) - rebind with the keyboard / Set keys / Preset"))
    -- 状态区（42–86）：左两行提示；右上虚拟键盘，右下形态分段按钮
    p.spec = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); p.spec:SetPoint("TOPLEFT", 12, -46); p.spec:SetPoint("RIGHT", -(L_KB_W + 24), 0); p.spec:SetJustifyH("LEFT"); p.spec:SetWordWrap(false)
    p.miss = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); p.miss:SetPoint("TOPLEFT", 12, -68); p.miss:SetPoint("RIGHT", -12, 0); p.miss:SetJustifyH("LEFT"); p.miss:SetWordWrap(false)
    -- 右上「虚拟键盘」（正式服：替换页右上 96×20）
    p.kbBtn = ns.Button(p, ns.L("虚拟键盘", "Keyboard"), L_KB_W, 20, function() if ns.KeysKb then ns.KeysKb.Toggle(); refresh() end end)
    p.kbBtn:SetPoint("TOPRIGHT", -12, -42)
    p.kbBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.L("虚拟键盘", "Virtual keyboard"), 1, 0.82, 0)
        GameTooltip:AddLine(ns.L("打开 / 关闭虚拟键盘：每个键上显示它现在绑的技能图标；看哪些键空着、哪些绑在空格上、W A S D Q E 是不是留给了移动；点键帽直接改键。",
            "Shows the spell icon on every key; see which keys are free or wasted and that W A S D Q E stay on movement; click a cap to rebind."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    p.kbBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- 10-16 形态 / 姿态切换（德鲁伊人 / 熊 / 豹，战士三姿态，盗贼普通 / 潜行）：只是切换看哪个形态下的技能和键，不改游戏里的形态。
    --   在「虚拟键盘」下面一行右对齐；没形态的职业不出
    p.formBtns = {}
    local fx = -12
    for _, cls in ipairs({ ns.MyClass() }) do
        -- 按数据里全部形态建按钮（中途学会新形态不用重载）；学没学会、摆在哪由 refresh 决定
        local fs = ns.KeysForms and ns.KeysForms[cls] and ns.KeysForms[cls].forms
        for i = #(fs or {}), 1, -1 do
            local f = fs[i]
            local b = ns.Button(p, ns.L(f.zh, f.en), L_FORM_W, 20, function() K.viewKey = f.key; refresh() end)
            b:SetPoint("TOPRIGHT", fx, -66); fx = fx - (L_FORM_W + L_FORM_GAP)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(ns.L(f.zh, f.en), 1, 0.82, 0)
                GameTooltip:AddLine(ns.L("看这个形态下要用的技能、它们在哪格、按什么键（主条的键换形态后会变）。只是看，不会让你变身。",
                    "Show the spells for this form, their slots and keys (main-bar keys change with form). View only - does not shift you."), 1, 1, 1, true)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            p.formBtns[f.key] = b
        end
    end
    -- 滚动区：状态区下 8px 起，到底栏上 8px 止
    local sf, c = ns.Scroll(p, 6, -L_SCROLL_Y, L_SCROLL_W, L_PAGE_H - L_SCROLL_Y - (L_BAR_B + L_BAR_H + 8))
    p.scroll, p.child = sf, c
    p.empty = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); p.empty:SetWidth(500); p.empty:SetJustifyH("LEFT")
    p.empty:SetText(ns.L("这个职业的铺条数据还没有", "No layout data for this class yet"))
    -- 「其他」折叠行（正式服 layoutMiscOpen）
    local mb = CreateFrame("Button", nil, c)
    mb:SetHeight(18)
    mb.t = mb:CreateFontString(nil, "OVERLAY", "GameFontNormal"); mb.t:SetPoint("LEFT", 2, 0); mb.t:SetJustifyH("LEFT")
    mb:SetScript("OnClick", function() ns.db.keysMiscOpen = not ns.db.keysMiscOpen; refresh() end)
    mb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.L("位移、增益、姿态、功能这些手法里没有的行；只影响显示，照常铺、照常分键", "Rows the rotation doesn't use; display only - still laid out and bound"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    mb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mb:Hide()
    p.miscBtn = mb
    -- 底部：还原上次 / 高级（10-16 用户「删掉，不要这个按钮了」：一键全铺去掉，键位只许逐个设置）
    p.restore = ns.Button(p, ns.L("还原上次", "Undo"), 90, 24, function() K.Restore((ns.db.keysBackups or {})[1]) end)
    p.restore:SetPoint("BOTTOMLEFT", 12, L_BAR_B)
    local advBtn = ns.Button(p, ns.L("高级", "Advanced"), 96, 24, function() p.adv:SetShown(not p.adv:IsShown()); refresh() end)   -- 10-16 「高级 ▸」的 ▸ 在游戏字体里是方框 → 纯文字
    p.advBtn = advBtn
    advBtn:SetPoint("BOTTOMRIGHT", -12, L_BAR_B)
    -- 10-17 用户「官方冷却器上印快捷键」：冷却管理器图标上显示快捷键（KeysCdm.lua，默认开）；放在底栏「高级」左边
    if ns.KeysCdm then
        p.cdmBtn = ns.Button(p, "", 210, 24, function()
            ns.KeysCdm.SetEnabled(not ns.KeysCdm.Enabled()); refresh()
        end)
        p.cdmBtn:SetPoint("RIGHT", advBtn, "LEFT", -8, 0)
        p.cdmBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(ns.L("冷却管理器上显示快捷键", "Show keys on the cooldown manager"), 1, 0.82, 0)
            GameTooltip:AddLine(ns.KeysCdm.Available() and ns.L("在暴雪冷却管理器每个技能图标右上角印上它在动作条上的键（按你现在的形态算）",
                "Prints each spell's action bar key on the Blizzard cooldown manager icons (for your current form)")
                or ns.L("这个客户端没有冷却管理器", "This client has no cooldown manager"), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        p.cdmBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    -- 高级区（默认收起）：重新分主条键 / 备份列表
    local adv = CreateFrame("Frame", nil, p, BackdropTemplateMixin and "BackdropTemplate" or nil)
    adv:SetSize(300, 222); adv:SetPoint("BOTTOMRIGHT", advBtn, "TOPRIGHT", 0, 4); adv:SetFrameLevel(((p.GetFrameLevel and p:GetFrameLevel()) or 1) + 20)
    if adv.SetBackdrop then
        adv:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        adv:SetBackdropColor(0.05, 0.05, 0.06, 0.96)
    end
    adv:Hide()
    p.adv = adv
    -- 10-16 主动作条键锁死后：之前被改乱的（比如 1 3 4 ` 5…）一键恢复成 1–9 0 - =（先自动备份）
    local rm = ns.Button(adv, ns.L("主动作条恢复 1 至 =", "Reset main bar keys"), 146, 22, function()
        local n, sk = K.ResetMainBar()
        if not n then ns.Print(ns.L("战斗中不能改键位，脱战再来", "Can't change keys in combat")); return end
        ns.Print(string.format(ns.L("主动作条恢复默认键：改了 %d 个（已自动备份）", "Main bar keys reset: %d changed (backup saved)"), n)
            .. ((sk and #sk > 0) and ("  |cffff5555" .. ns.L("这几个键被移动 / 聊天等占着，没抢：", "kept (used by movement / chat): ") .. table.concat(sk, " ") .. "|r") or ""))
    end)
    rm:SetPoint("TOPLEFT", 10, -10)
    local bt = adv:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); bt:SetPoint("TOPLEFT", 12, -40); bt:SetText(ns.L("备份（最近 10 份）", "Backups (last 10)"))
    p.bkRows = {}
    for i = 1, 7 do
        local r = CreateFrame("Frame", nil, adv)
        r:SetSize(280, 20); r:SetPoint("TOPLEFT", 10, -56 - (i - 1) * 22)
        r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.t:SetPoint("LEFT", 2, 0); r.t:SetPoint("RIGHT", -64, 0)
        r.t:SetJustifyH("LEFT"); r.t:SetWordWrap(false)
        local b = ns.Button(r, ns.L("还原", "Restore"), 58, 18, function() K.Restore(r.snap) end)
        b:SetPoint("RIGHT", 0, 0)
        p.bkRows[i] = r
    end
    if ns.KeysKb then ns.KeysKb.Attach(p) end
    K.OnChanged = function() refresh(); if ns._RotRefresh then pcall(ns._RotRefresh) end end
    -- 第一次打开：说一句怎么用（记住不再说）
    if not ns.db.keysMode then
        ns.db.keysMode = "keep"
        ns.Print(ns.L("键位：保留你现在的键位；缺的技能左键拿起自己放，或右键选一格放进去。",
            "Keys: your keys are kept - left-click a spell to pick it up, or right-click to choose a slot."))
    end
end

-- 刷新：动作条 / 绑定 / 学会新技能（节流 0.3 秒）
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS", "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "UPDATE_BONUS_ACTIONBAR" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local queued
ev:SetScript("OnEvent", function(_, e)
    if e == "UPDATE_BONUS_ACTIONBAR" and K then K.viewKey = nil end   -- 真变身 / 换姿态了：形态按钮跟着现在的形态走
    if queued or not page then return end
    queued = true
    C_Timer.After(0.3, function() queued = false; pcall(refresh) end)
end)
-- 升级学会新技能：页面没开时提醒一次（只在用过键位页之后）
local lf = CreateFrame("Frame")
pcall(lf.RegisterEvent, lf, "LEARNED_SPELL_IN_TAB")
lf:SetScript("OnEvent", function()
    if not ns.db or not ns.db.keysMode then return end
    C_Timer.After(1, function()
        local _, miss = K.Status()
        if miss > 0 and not (page and page:IsShown()) then
            ns.Print(string.format(ns.L("学会新技能了：%d 个该上条的技能不在条上 · /gif keys 去放上", "New spell learned: %d spells not on your bars - /gif keys"), miss))
        end
    end)
end)

ns.RegisterPage({ key = "keys", order = 1.6, title = ns.L("键位", "Keys"), tabTitle = ns.L("键位", "Keys"),
    icon = "Interface\\Icons\\INV_Misc_Key_03", build = build, refresh = refresh })
ns._KeysRefresh = refresh   -- 测试用
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.kb = function()   -- /gif kb：打开键位页 + 虚拟键盘
    local f = _G.GearInsightForeverMain
    if f and f:IsShown() then ns.ShowPage("keys") else ns.ToggleMain("keys") end
    if ns.KeysKb and not ns.KeysKb.Shown() then ns.KeysKb.Toggle(true); pcall(refresh) end
end
