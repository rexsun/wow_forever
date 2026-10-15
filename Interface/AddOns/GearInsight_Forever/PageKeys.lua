-- 键位页（10-10 立项；10-12 照正式服 10-12「阶段 3」拆页：键位 / 手法 两个独立页签，手法在 PageRot.lua）
--   照正式服 GearInsight_Layout/ui/LayoutPage.lua「替换」视图：
--   顶部 当前天赋系 + 待处理行 + 右上「虚拟键盘」→ 中部 按组分行（前 5 行 = 手法助手 5 轨：主循环 / 短冷却 / 大招 / 生存 / 控制，
--   其余收进「其他」默认折叠；每组行头「设键」「模板」）→ 底部 一键全铺 / 还原 / 高级 ▸
--   格子：左键 = 给这一格改键（同虚拟键盘点键帽）；不在条上的点「—」放上去。
--   《无限》差异：正式服面板是「计划键」，点「将插件建议实现到动作条」才绑；这里一直是实况（保留你的键位），改键立刻生效。
-- ⛔ 不碰宏。⛔ HOLD（_hold.txt），测完才进包。
local _, ns = ...
local K = ns.Keys

local page
local GAP = 5

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
    local hl = c:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
    c:SetScript("OnClick", function(self)
        local p = self.p
        if not p then return end
        if p.slot then
            if ns.KeysKb then ns.KeysKb.BeginKeyCapture(p.slot) end
        elseif p.placeable then K.PlaceMissing(p) end
    end)
    c:SetScript("OnEnter", function(self)   -- 小格子显示不全 → 悬停看全（用户硬规定）
        local p = self.p
        if not p then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(p.name or "?", 1, 0.82, 0)
        local rn = K.ROLE_NAME[p.role]
        GameTooltip:AddLine(ns.L(rn and rn[1] or "", rn and rn[2] or ""), 0.7, 0.7, 0.7)
        if p.slot then
            GameTooltip:AddLine(p.key and (ns.L("按键：", "Key: ") .. p.key) or ns.L("在动作条上，但这格没绑键", "On your bars but that slot has no key"), 1, 1, 1)
            GameTooltip:AddLine(string.format(ns.L("动作条第 %d 格", "Action slot %d"), p.slot), 0.6, 0.6, 0.6)
            GameTooltip:AddLine(ns.L("点击 = 给这一格改键（按下新键立刻生效）", "Click = rebind this slot (applies right away)"), 0.5, 0.75, 1, true)
        elseif p.placeable then
            GameTooltip:AddLine(ns.L("不在动作条上 · 点一下自动放到一个有键的空格", "Not on your bars - click to place it in a free slot with a key"), 0.2, 1, 0.6, true)
        else
            GameTooltip:AddLine(ns.L("这类技能默认不铺（可自己拖上去）", "Not placed by default (drag it yourself)"), 0.6, 0.6, 0.6, true)
        end
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
    h.set:SetPoint("RIGHT", -60, 0)
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
                    .. ((#skipped > 0) and ("  |cffff5555" .. ns.L("移动 / 聊天键不顶替：", "kept (movement / chat): ") .. table.concat(skipped, " ") .. "|r") or ""))
                if page.refresh then page.refresh() end
            end }
        end
        ns.KeysKb.Menu(self, string.format(ns.L("「%s」套用键位模板", "\"%s\" key preset"), x._label or ""), items)
    end)
    h.tpl:SetPoint("RIGHT", -2, 0)
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
    local rows, missing = K.Status()
    local size, cols = cellSize()
    local miscOpen = ns.db.keysMiscOpen
    local y, n, nh = 0, 0, 0
    local miscN = 0
    for _, grp in ipairs(K.Grouped(rows)) do if grp.g.fold then miscN = miscN + #grp.items end end
    for _, grp in ipairs(K.Grouped(rows)) do
        local g = grp.g
        if g.fold and miscN > 0 then
            local mb = page.miscBtn
            mb:ClearAllPoints(); mb:SetPoint("TOPLEFT", 0, y); mb:SetPoint("RIGHT", page.child, "RIGHT", -4, 0); mb:Show()
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
            h.t:SetText(string.format("|cff%s%s|r  |cff777777%d%s · %s|r", hex, ns.L(g.n[1], g.n[2]), #grp.items, ns.L(" 个", ""), ns.L(g.d[1], g.d[2])))
            h.set:SetEnabled(#slots > 0); h.tpl:SetEnabled(#slots > 0)
            h:Show()
            y = y - 22
            local col = 0
            for _, p in ipairs(grp.items) do
                if col >= cols then col = 0; y = y - size - GAP end
                n = n + 1
                local c = getCell(n)
                c.p = p
                c:SetSize(size, size)
                c:ClearAllPoints(); c:SetPoint("TOPLEFT", col * (size + GAP), y)
                c.ic:SetTexture("Interface\\Icons\\" .. ((p.e.i or "") ~= "" and p.e.i or "INV_Misc_QuestionMark"))
                local on = p.slot ~= nil
                c.ic:SetDesaturated(not on); c.ic:SetAlpha(on and 1 or (p.placeable and 0.55 or 0.3))
                if c.SetBackdropBorderColor then c:SetBackdropBorderColor(g.c[1], g.c[2], g.c[3], on and 0.95 or 0.35) end
                c.key:SetText(on and (shortKey(p.key) or "|cffff5555?|r") or "")
                c.keyBg:SetShown(on)
                c.num:SetText(on and tostring(p.slot) or "")
                c.dash:SetShown(not on and p.placeable)
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
    page.miss:SetText(missing > 0 and string.format(ns.L("|cffffd100%d|r 个技能不在条上 · 点「—」一键放上去 · 点格子改键", "|cffffd100%d|r spells not on your bars - click a dash to place it - click a slot to rebind"), missing)
        or ns.L("|cff33ff99该上条的技能都在条上了|r · 点格子改键", "|cff33ff99Everything is on your bars|r - click a slot to rebind"))
    local tree, pts = K.MainTree()
    page.spec:SetText(ns.EnSafe(ns.L("当前：", "Now: ") .. (tree and ns.L("第 " .. tree .. " 系 · " .. pts .. " 点", "tree " .. tree .. " - " .. pts .. " pts") or ns.L("天赋未满 10 点，按职业通用", "under 10 talent points - class default"))))
    page.kbBtn:SetText(ns.KeysKb and ns.KeysKb.Shown() and ns.L("收起键盘", "Hide keyboard") or ns.L("虚拟键盘", "Keyboard"))
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
    p.cells, p.hdrs = {}, {}
    p.refresh = refresh
    ns.PageHeader(p, ns.L("键位", "Keys"),
        ns.L("保留你的键位：缺的点「—」放上去 · 点格子 / 键帽改键 · 或一键全铺（自动备份，能还原）", "Keep your keys: click a dash to place a missing spell - click a slot to rebind - or lay out everything (backed up)"))
    p.spec = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); p.spec:SetPoint("TOPLEFT", 12, -44); p.spec:SetPoint("RIGHT", -130, 0); p.spec:SetJustifyH("LEFT")
    p.miss = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); p.miss:SetPoint("TOPLEFT", 12, -60); p.miss:SetPoint("RIGHT", -130, 0); p.miss:SetJustifyH("LEFT"); p.miss:SetWordWrap(false)
    -- 右上「虚拟键盘」（正式服：替换页右上 96×20）
    p.kbBtn = ns.Button(p, ns.L("虚拟键盘", "Keyboard"), 110, 22, function() if ns.KeysKb then ns.KeysKb.Toggle(); refresh() end end)
    p.kbBtn:SetPoint("TOPRIGHT", -14, -42)
    p.kbBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.L("虚拟键盘", "Virtual keyboard"), 1, 0.82, 0)
        GameTooltip:AddLine(ns.L("打开 / 关闭虚拟键盘：每个键上显示它现在绑的技能图标；看哪些键空着、哪些绑在空格上、W A S D Q E 是不是留给了移动；点键帽直接改键。",
            "Shows the spell icon on every key; see which keys are free or wasted and that W A S D Q E stay on movement; click a cap to rebind."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    p.kbBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local sf, c = ns.Scroll(p, 6, -80, 616, 474 - 80 - 46)
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
    -- 底部：一键全铺 / 还原 / 高级
    local all = ns.Button(p, ns.L("一键全铺", "Lay out all"), 110, 24, function() K.ApplyAll(true) end)
    all:SetPoint("BOTTOMLEFT", 12, 12)
    all:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.L("一键全铺", "Lay out all"), 1, 0.82, 0)
        GameTooltip:AddLine(ns.L("先自动备份，再按职能从主条开始铺满；已有的键不动，没键的格从顺手的键里分", "Backs up first, then fills your bars by role; existing keys are kept, empty slots get comfortable keys"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    all:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.restore = ns.Button(p, ns.L("还原上次", "Undo"), 90, 24, function() K.Restore((ns.db.keysBackups or {})[1]) end)
    p.restore:SetPoint("LEFT", all, "RIGHT", 6, 0)
    local advBtn = ns.Button(p, ns.L("高级 ▸", "Advanced"), 80, 24, function() p.adv:SetShown(not p.adv:IsShown()); refresh() end)
    advBtn:SetPoint("BOTTOMRIGHT", -12, 12)
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
    local re = ns.Button(adv, ns.L("全部重新分键", "Reassign all keys"), 130, 22, function() K.ApplyAll(false) end)
    re:SetPoint("TOPLEFT", 10, -10)
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
    -- 第一次打开：说一句保留还是全铺（记住不再说）
    if not ns.db.keysMode then
        ns.db.keysMode = "keep"
        ns.Print(ns.L("键位：默认保留你现在的键位，只补缺的技能（点「—」）；想按职能全部重铺点「一键全铺」，会先自动备份。",
            "Keys: your keys are kept by default - click a dash to add a missing spell; 'Lay out all' backs up first."))
    end
end

-- 刷新：动作条 / 绑定 / 学会新技能（节流 0.3 秒）
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS", "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "UPDATE_BONUS_ACTIONBAR" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local queued
ev:SetScript("OnEvent", function()
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
            ns.Print(string.format(ns.L("学会新技能了：%d 个该上条的技能不在条上 · /gif keys 一键放上去", "New spell learned: %d spells not on your bars - /gif keys"), miss))
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
