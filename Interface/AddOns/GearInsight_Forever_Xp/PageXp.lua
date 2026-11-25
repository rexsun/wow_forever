-- 经验加成页 + 出发前清单（11-17 起在按需加载的 GearInsight_Forever_Xp；检查 / 合计 / 到期提醒 / 提醒条留在主插件 XpCheck.lua）
--   用户 11-17「buff和来源要可视化对应」：每一行 = 左边「增益 / 物资」图标 + 名字 + 状态（生效 / 快到期 / 缺）← 右边「从哪来」：
--     物品来源 = 物品图标 + 包里几个；商人 / 拍卖行 = 金币图标 + 价格 + 本城商人；玩家 = 职业圆图标 + 名字（点了走要 BUFF / 要水的弹框）；
--     帐篷 / 营火 = 对应图标 +「附近」。多个来源并排：能用的亮、用不上的灰，能用的排第一。包里有没用的再给一个「用」安全按钮（战斗中不碰）
--   「出发前清单」：进主城 / 旅店自动弹（主插件 XpCheck.PrepCheck 按需加载本子插件后调 XC.Prep.Show），离开休息区收起，回来再弹
--   11-17 用户「可以放大缩小，然后这样太占空间了，弄得便携一点」「文字展示不全也好好优化」：
--     出发前清单改成紧凑小窗（默认宽 300）：每项一行 22 高 = 色条 + 小图标 + 短文字（「吃的 0/20」）+ 来源小图标（全文在悬停）；
--     够用的折叠成一行「睡袋 · 修理 · 背包空格」、可选的折叠成「可选：…」（点开 / 收起，记住）；右下角拖改宽度，Ctrl+滚轮 / 右键标题整体缩放；
--     所有文字按实际字宽挑放得下的那一档（长 → 短 → 只剩数字），不出现「…」截断；来源放得下才带短名，放不下整排只剩图标
local _, ns = ...; ns = _G.GearInsightForever or ns
local L = function(cn, en) return ns.L(cn, en) end
local XC = ns.XpCheck
if not XC then return end

local COLOR = { ok = { 0.25, 0.9, 0.35 }, warn = { 1, 0.82, 0.1 }, miss = { 1, 0.35, 0.3 }, info = { 0.7, 0.7, 0.7 }, off = { 0.5, 0.5, 0.5 } }
local STATE_TXT = { ok = { "生效中", "Active" }, warn = { "快到期", "Ending" }, miss = { "缺", "Missing" }, info = { "可选", "Optional" } }
local SUP_STATE = { ok = { "够用", "OK" }, warn = { "快不够", "Low" }, miss = { "没有", "Out" }, info = { "可选", "Optional" } }
local ROW_H, LEFT_W, CHIPS = 42, 292, 3
XC.ROW = { h = ROW_H, left = LEFT_W, chips = CHIPS }
local MINI_H, MINI_CHIPS = 22, 6   -- 11-18 祝福逐种列（耐力 / 智力 / 野性印记 / 力量或智慧 / 王者 = 5 个）：4 → 6
XC.MINI = { h = MINI_H, chip = 16, chips = MINI_CHIPS }
local READY, WAITING = "Interface\\RaidFrame\\ReadyCheck-Ready", "Interface\\RaidFrame\\ReadyCheck-Waiting"
local function inCombat() return InCombatLockdown and InCombatLockdown() and true or false end
local function opt(k, def) local v = XC.DB()[k]; if v == nil then return def end return v end
local function num(v) if v == nil or (ns.Secret and ns.Secret(v)) then return nil end return tonumber(v) end

-- ---------- 字宽：按实际宽度挑放得下的一档（不靠「…」截断）----------
local function sw(fs)
    local f = fs and (fs.GetUnboundedStringWidth or fs.GetStringWidth)
    if not f then return 0 end
    local ok, w = pcall(f, fs)
    return (ok and type(w) == "number") and w or 0
end
XC.StrW = sw
-- cands 从长到短；返回选中的文字。都放不下用最后一档（调用方保证最后一档够短）
local function fit(fs, w, cands)
    local pick
    for _, t in ipairs(cands) do
        if type(t) == "string" and t ~= "" then
            pick = t
            fs:SetText(t)
            if sw(fs) <= w then fs:SetWidth(w); return t, true end
        end
    end
    fs:SetText(pick or "")
    fs:SetWidth(w)
    return pick, false
end
XC.Fit = fit
local function fmtS(sec)
    sec = math.floor(sec or 0)
    if sec >= 3600 then return string.format("%d:%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
    if sec >= 60 then return string.format(L("%d分", "%dm"), math.floor(sec / 60 + 0.5)) end
    return string.format(L("%d秒", "%ds"), sec)
end
XC.FmtS = fmtS
local SHORT = { tent = { "帐篷", "Tent" }, fire = { "营火", "Fire" }, bag = { "睡袋", "Bag" }, food = { "经验食物", "XP food" }, boost = { "经验药剂", "XP potion" },
    kit = { "药剂/油", "Elixir/oil" }, rest = { "休息经验", "Rested" }, cbuff = { "职业BUFF", "Class buffs" }, eat = { "吃的", "Food" }, drink = { "喝的", "Drink" },
    ammo = { "弹药", "Ammo" }, reagent = { "施法材料", "Reagents" }, potion = { "绷带/药水", "Bandage/potion" }, repair = { "修理", "Repair" }, space = { "背包空格", "Bag space" } }
local STW = { ok = { "有", "OK" }, warn = { "快到期", "Ending" }, miss = { "缺", "Missing" }, info = { "可选", "Optional" } }
local function stitle(x) local t = SHORT[x.key]; return t and L(t[1], t[2]) or x.title or "" end
XC.ShortTitle = stitle
-- 一行的几档文字：{ 长（宽窗口）, 短（「吃的 0/20」「经验食物 剩1分」）, 最短（只剩数字 / 状态）}
function XC.RowTexts(x)
    local it = x.it
    if not it then return { x.why or "", x.whyS or stitle(x) } end
    if it.short then return { it.text, it.short, it.tiny or it.short } end
    local s
    if x.key == "rest" and it.pct then s = string.format("%d%%", it.pct)
    elseif x.key == "cbuff" and it.nMiss and it.nMiss > 0 then s = string.format(L("缺%d", "-%d"), it.nMiss)
    elseif it.left and it.st == "info" then s = L("冷却", "CD ") .. fmtS(it.left)
    elseif it.left and (it.st == "ok" or it.st == "warn") then s = L("剩", "") .. fmtS(it.left)
    else local w = STW[it.st]; s = w and L(w[1], w[2]) or "" end
    return { it.text, stitle(x) .. " " .. s, s }
end

-- ---------- 来源小图标 ----------
local function hideTip() if GameTooltip then GameTooltip:Hide() end end
local function chipTip(self)
    local s = self.s
    if not (s and GameTooltip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(s.text, 1, 1, 1, true)
    if s.tip then GameTooltip:AddLine(s.tip, 0.8, 0.8, 0.8, true) end
    GameTooltip:AddLine(s.ok and L("现在用得上", "Available now") or L("现在用不上（灰）", "Not available right now"), s.ok and 0.25 or 0.6, s.ok and 0.9 or 0.6, s.ok and 0.35 or 0.6)
    if s.fn then GameTooltip:AddLine(s.clickTip or (L("点击：", "Click: ") .. L("去补", "get it")), 0.5, 0.75, 1, true) end
    if s.callMenu and ns.CallMenu then GameTooltip:AddLine(L("右键：喊 BUFF 频道（说 / 大喊）、改求人的称呼", "Right-click: ask channel (Say / Yell), form of address"), 0.5, 0.75, 1, true) end
    GameTooltip:Show()
end
local function chipClick(self, button)
    local s = self.s
    -- 11-18 用户「自定义 义父替代在哪里，要做到UI的」：职业 BUFF 图标右键 = 改称呼（小菜单：预设 / 自己填 / 去设置）
    if button == "RightButton" then
        if s and s.callMenu and ns.CallMenu then hideTip(); XC.ShoutMenu(self, function() if XC.Prep and XC.Prep.Refresh then XC.Prep.Refresh() end end) end
        return
    end
    if not (s and s.fn) then return end
    pcall(s.fn)
    if XC.RefreshPage then XC.RefreshPage() end
    if XC.Prep and XC.Prep.Refresh then XC.Prep.Refresh() end
end
local function newChip(parent, sz)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(sz, sz)
    c.sz, c.s = sz, false
    c.ic = c:CreateTexture(nil, "ARTWORK"); c.ic:SetSize(sz, sz); c.ic:SetPoint("LEFT", 0, 0)
    c.t = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); c.t:SetPoint("LEFT", c.ic, "RIGHT", 3, 0)
    c.t:SetJustifyH("LEFT"); c.t:SetWordWrap(false)
    if c.RegisterForClicks then c:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    c:SetScript("OnEnter", chipTip); c:SetScript("OnLeave", hideTip); c:SetScript("OnClick", chipClick)
    return c
end
-- 排一行来源：iconW = 只放图标时可用的宽（决定放几个）；nameW = 带短名时可用的宽（全部放得下才带名字，否则整排只图标）
--   x0 = 左起点；nil = 靠右（right = 右边留白）。返回 占的宽, 放了几个
local function layChips(row, sl, iconW, nameW, x0, right)
    local chips, gap = row.chips, 2
    local sz = chips[1] and chips[1].sz or 16
    local n = math.min(#sl, #chips, math.max(0, math.floor((iconW + gap) / (sz + gap))))
    local ws, names = {}, false
    if nameW and n > 0 then
        local tot = 0
        for i = 1, n do
            local s, c = sl[i], chips[i]
            local tw = 0
            if s.short and s.short ~= "" then c.t:SetText(s.short); tw = math.ceil(sw(c.t)) + 1 end
            ws[i] = tw
            tot = tot + sz + (tw > 0 and (tw + 3) or 0) + (i > 1 and 6 or 0)
        end
        names = tot <= nameW
    end
    local total = 0
    for i = 1, n do
        local w = sz + ((names and ws[i] > 0) and (ws[i] + 3) or 0)
        total = total + w + (i > 1 and (names and 6 or gap) or 0)
    end
    local x = x0 or (row.w - (right or 0) - total)
    for i, c in ipairs(chips) do
        local s = i <= n and sl[i] or nil
        c.s = s or false
        if s then
            local tw = names and ws[i] or 0
            c:ClearAllPoints(); c:SetPoint("LEFT", row, "LEFT", x, 0)
            c:SetSize(sz + (tw > 0 and (tw + 3) or 0), sz)
            c.ic:SetTexture(s.icon)
            if s.tc then c.ic:SetTexCoord(s.tc[1], s.tc[2], s.tc[3], s.tc[4]) else c.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
            -- 11-17：dim = 已经有了（BUFF 在身上 / 包里有）→ 变暗；lit = 缺的 BUFF → 附近没人给也保持亮
            local dark = s.dim or (not s.ok and not s.lit)
            c.dark = dark and true or false
            if c.ic.SetDesaturated then c.ic:SetDesaturated(dark) end
            if tw > 0 then
                c.t:SetText(s.short); c.t:SetWidth(tw); c.t:Show()
                if not dark then c.t:SetTextColor(1, 1, 1) else c.t:SetTextColor(0.5, 0.5, 0.5) end
            else c.t:SetText(""); c.t:Hide() end
            c:SetAlpha(s.dim and 0.45 or (dark and 0.6 or 1))
            c:Show()
            x = x + sz + (tw > 0 and (tw + 3) or 0) + (names and 6 or gap)
        else c:Hide() end
    end
    return total, n
end
XC.LayChips = layChips

-- ---------- 页里的一行（大卡片）：增益 ← 来源 ----------
local function rowTip(self)
    local r = rawget(self, "row")
    local x = r and rawget(r, "x")
    if not (x and GameTooltip) then return end
    local it = x.it
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(x.title or stitle(x), 1, 0.82, 0)
    GameTooltip:AddLine(it and it.text or x.why or "", 1, 1, 1, true)
    for _, h in ipairs(it and it.how or {}) do GameTooltip:AddLine("· " .. h, 0.8, 0.8, 0.8, true) end
    local sl = rawget(r, "src")
    if type(sl) == "table" and sl[1] then
        GameTooltip:AddLine(L("从哪来（亮的现在就能补）：", "Where to get it (lit = available now):"), 0.5, 0.75, 1)
        for _, s in ipairs(sl) do GameTooltip:AddLine("· " .. s.text, s.ok and 1 or 0.6, s.ok and 1 or 0.6, s.ok and 1 or 0.6, true) end
    end
    -- 11-18 职业 BUFF 行：写现在的称呼、怎么改（用户「要不用户找不到」）
    if x.key == "cbuff" and ns.CallTip then
        GameTooltip:AddLine(string.format(L("喊 BUFF 频道：%s（右键改）", "Ask channel: %s (right-click)"), XC.ShoutChanText()), 0.5, 0.75, 1, true)
        GameTooltip:AddLine(ns.CallTip(), 0.5, 0.75, 1, true)
    end
    GameTooltip:Show()
end
function XC.RowWidget(parent, w)
    local r = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    r:SetSize(w, ROW_H)
    r.w, r.compact, r.x, r.src = w, false, false, false
    if r.SetBackdrop then pcall(r.SetBackdrop, r, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }) end
    r.ic = r:CreateTexture(nil, "ARTWORK"); r.ic:SetSize(30, 30); r.ic:SetPoint("LEFT", 6, 0); r.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.title:SetPoint("TOPLEFT", 44, -5); r.title:SetWordWrap(false); r.title:SetJustifyH("LEFT")
    r.badge = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); r.badge:SetPoint("LEFT", r.title, "RIGHT", 6, 0); r.badge:SetWordWrap(false); r.badge:SetJustifyH("LEFT")
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.text:SetPoint("TOPLEFT", 44, -22)
    r.text:SetWidth(LEFT_W - 50); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
    r.arrow = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); r.arrow:SetPoint("LEFT", LEFT_W - 4, 0); r.arrow:SetText("<"); r.arrow:SetWidth(14)
    r.hit = CreateFrame("Frame", nil, r); r.hit:SetPoint("TOPLEFT"); r.hit:SetSize(LEFT_W - 8, ROW_H); r.hit.row = r
    if r.hit.EnableMouse then r.hit:EnableMouse(true) end
    r.hit:SetScript("OnEnter", rowTip); r.hit:SetScript("OnLeave", hideTip)
    r.chips = {}
    for i = 1, CHIPS do r.chips[i] = newChip(r, 18) end
    r.more = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); r.more:SetPoint("RIGHT", -66, -12); r.more:SetWidth(30); r.more:SetJustifyH("RIGHT")
    return r
end

-- 「用」安全按钮（宏 /use item:ID；武器油再 /use 16 点主手）：只在脱战时建 / 改属性 / 显隐；进战斗由状态驱动自己藏
local USE = setmetatable({}, { __mode = "k" })   -- 行 → 它的「用」按钮
XC._useBtns = USE   -- 测试用
local function useBtn(row)
    if USE[row] or inCombat() then return USE[row] end
    local mini = rawget(row, "compact") == true
    -- 11-22 用户截图「战斗中为啥无法关闭」：同 11-15 圣骑士祝福（PallyBless PB.AttachPageBtn）—— 安全按钮原来是行的子框体
    --   → 整个主面板被带成受保护框体，战斗中 × / ESC 关不掉。改挂 UIParent（不进主面板父子链），脱战时贴到行上（XC.AttachUse），
    --   行藏了 / 进战斗前（PLAYER_REGEN_DISABLED 里还能动）摘下来藏好
    local b = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    b:SetSize(mini and 30 or 56, mini and 18 or 20)
    b.row, b.mini = row, mini
    if b.RegisterForClicks then b:RegisterForClicks("AnyDown") end
    if ns.SkinButton then ns.SkinButton(b) end
    if RegisterStateDriver and b.SetAttribute then
        b:SetAttribute("_onstate-gixpuse", [[ if newstate == "1" then self:Hide() end ]])
        RegisterStateDriver(b, "gixpuse", "[combat] 1; 0")
    end
    b:SetScript("OnEnter", function(self)
        local u = self.u
        if not (u and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(u.name, 1, 0.82, 0)
        if u.fx then GameTooltip:AddLine(u.fx, 1, 1, 1, true) end
        GameTooltip:AddLine(u.weapon and L("点一下：涂到主手武器上（读条几秒，别动）", "Click: apply to your main-hand weapon (short cast)")
            or (u.trinket and L("点一下：使用（要戴在脖子上）", "Click: use it (must be equipped)")) or L("点一下：喝一瓶", "Click: drink one"), 0.25, 0.9, 0.35, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", hideTip)
    b:Hide()
    USE[row] = b
    if row.HookScript then
        row:HookScript("OnHide", function() XC.DetachUse(b) end)
        row:HookScript("OnShow", function() XC.AttachUse(b) end)
    end
    return b
end
-- 贴到行的右侧（只在脱战时；行看不见就不显示）
function XC.AttachUse(b)
    local row = b and rawget(b, "row")
    if not row or inCombat() then return end
    if not rawget(b, "u") then b:Hide(); return end
    b:ClearAllPoints(); b:SetPoint("RIGHT", row, "RIGHT", b.mini and -2 or -6, 0)
    if row.GetFrameStrata then b:SetFrameStrata(row:GetFrameStrata()) end
    b:SetFrameLevel((row:GetFrameLevel() or 1) + 3)
    if row.IsVisible and row:IsVisible() then b:Show() else b:Hide() end
end
-- 摘下来：藏好、不再挂在行上（战斗中动不了就算了，状态驱动已经把它藏了）
function XC.DetachUse(b)
    if not b or inCombat() then return end
    b:Hide(); b:ClearAllPoints()
end
do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED"); ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, e)
        for _, b in pairs(USE) do
            if e == "PLAYER_REGEN_DISABLED" then b:Hide(); b:ClearAllPoints() else XC.AttachUse(b) end   -- 进战斗前最后一刻摘下；脱战贴回
        end
    end)
    XC._useEv = ev   -- 测试用
end
function XC.PaintUse(row, u)
    if inCombat() then return end
    local b = u and useBtn(row) or USE[row]
    if not b then return end
    if u and b.SetAttribute then
        b.u = u
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", "/use item:" .. u.item .. (u.weapon and "\n/use 16" or ""))
        b:SetText(L("用", "Use"))
        XC.AttachUse(b)
    else
        b.u = nil
        b:Hide()
    end
end

-- title：行名；it：检查结果（nil = 这一项现在不查，why 写原因）；sup：物资行（状态字不同）；whyS = 原因的短说法
function XC.PaintRow(row, key, title, it, why, sup, whyS)
    local x = { key = key, title = title, it = it, why = why, whyS = whyS }
    row.it = it or false   -- false 不是 nil：没查的行也把旧数据清掉
    row.key, row.x = key, x
    local st = it and it.st or "off"
    local col = COLOR[st] or COLOR.off
    row.ic:SetTexture((it and it.icon) or XC.ICON[key] or "Interface\\Icons\\INV_Misc_QuestionMark")
    if row.ic.SetDesaturated then row.ic:SetDesaturated(not it or st == "miss" or st == "info") end
    if row.SetBackdropColor then
        row:SetBackdropColor(col[1] * 0.1, col[2] * 0.1, col[3] * 0.1, 0.85)
        row:SetBackdropBorderColor(col[1], col[2], col[3], it and 0.5 or 0.15)
    end
    -- 第一行：名字 + 状态（名字按实际宽，状态放不下就去掉剩余时间）
    local lw = LEFT_W - 50 - 12
    row.title:SetText(title)
    local tw = math.ceil(sw(row.title)) + 1
    if tw <= 1 or tw > lw then tw = math.floor(lw * 0.6) end
    row.title:SetWidth(tw)
    local stt = it and (sup and SUP_STATE or STATE_TXT)[st]
    local b1 = stt and L(stt[1], stt[2]) or ""
    fit(row.badge, math.max(1, lw - tw - 6), { (stt and it.left) and (b1 .. "  " .. fmtS(it.left)) or b1, b1 })
    row.badge:SetTextColor(col[1], col[2], col[3])
    fit(row.text, LEFT_W - 50, XC.RowTexts(x))
    if it then row.text:SetTextColor(1, 1, 1) else row.text:SetTextColor(0.5, 0.5, 0.5) end
    local sl = it and XC.Sources(it) or {}
    row.src = sl
    row.arrow:SetShown(sl[1] ~= nil)
    local avail = row.w - (LEFT_W + 14) - 64 - 34
    local _, n = layChips(row, sl, avail, avail, LEFT_W + 14)
    row.more:SetText(#sl > n and ("+" .. (#sl - n)) or "")
    XC.PaintUse(row, it and (st == "miss" or st == "info") and it.use or nil)
    row:Show()
end

-- ---------- 一组行：检查器各项 + 职业 BUFF + 物资 ----------
local SUP_TITLE = { eat = { "吃的", "Food" }, drink = { "喝的", "Drink" }, ammo = { "弹药", "Ammo" }, reagent = { "施法材料", "Reagents" },
    potion = { "绷带 / 药水", "Bandages / potions" }, repair = { "修理", "Repair" }, space = { "背包空格", "Bag space" } }
XC.SUP_TITLE = SUP_TITLE
-- 返回 { { key, title, it, why, whyS, sup } … }；prep = 出发前清单（只要出发前能准备的，缺的排前面）
function XC.Rows(prep)
    local out, by = {}, {}
    local on = XC.Enabled()
    local res, done = {}, false
    if on then
        local ok, r, d = pcall(XC.Check)
        if ok then res, done = r, d else out.err = r end
    end
    for _, r in ipairs(res) do by[r.key] = r end
    local cb = (on and not done) and XC.ClassBuffs and XC.ClassBuffs() or nil
    local keys = {}
    for _, k in ipairs(XC.KEYS) do
        keys[#keys + 1] = k
        if k == "boost" then keys[#keys + 1] = "cbuff" end
    end
    local PREP = { bag = true, food = true, boost = true, kit = true, cbuff = true }
    for _, k in ipairs(keys) do
        local it = (k == "cbuff") and cb or by[k]
        if not prep or (it and PREP[k]) then
            local why, whyS
            if not on then why, whyS = L("检查已关闭（点上面「已关闭」打开）", "Check is off - click Off above"), L("检查已关闭", "Check is off")
            elseif done then why = L("已满级，不用查", "Max level")
            elseif not XC.ItemOn(k) then why, whyS = L("这一项已在设置里关掉", "Turned off in settings"), L("设置里关了", "Off")
            elseif k == "boost" then why, whyS = L("没有经验药剂 / 活动加成（身上有、包里有或坠饰能用时才显示）", "No XP potion / event bonus (shown when you have one)"), L("没有（有了才显示）", "None")
            elseif k == "cbuff" then why, whyS = L("要 BUFF 模块没加载（组队子插件）", "Buff module not loaded"), L("BUFF 模块没加载", "Not loaded")
            else why, whyS = L("现在不用管（等级不够、副本里或不适用）", "Not relevant right now"), L("现在不用管", "N/A") end
            local t = k == "cbuff" and { L("职业 BUFF", "Class buffs") } or { L(XC.TITLE[k][1], XC.TITLE[k][2]) }
            out[#out + 1] = { key = k, title = t[1], it = it, why = why, whyS = whyS }
        end
    end
    if on and not done and XC.Supplies then
        local ok, sup = pcall(XC.Supplies)
        if ok then
            for _, r in ipairs(sup) do
                local t = SUP_TITLE[r.key]
                out[#out + 1] = { key = r.key, title = (r.key == "reagent" and r.title) or (t and L(t[1], t[2])) or r.key, it = r, sup = true }
            end
        end
    end
    -- 11-17 ③ 包里有（没用上）的：不再强提醒 —— 不标红、不算「没备好」，排在缺的后面
    for _, x in ipairs(out) do
        if x.it and x.it.st == "miss" and XC.InBag and XC.InBag(x.it) then x.have = true end
    end
    if prep then
        local RANK = { miss = 1, warn = 2, info = 3, ok = 4 }
        for i, x in ipairs(out) do x.i = i end
        table.sort(out, function(a, b)
            local ra, rb = a.have and 3 or RANK[a.it and a.it.st or "ok"] or 5, b.have and 3 or RANK[b.it and b.it.st or "ok"] or 5
            if ra ~= rb then return ra < rb end
            return a.i < b.i
        end)
    end
    return out, res
end

local function paintList(list, rows, parent, w, newRow)
    for i, x in ipairs(list) do
        local row = rows[i]
        if not row then row = newRow(parent, w); rows[i] = row end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + 3))
        XC.PaintRow(row, x.key, x.title, x.it, x.why, x.sup, x.whyS)
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
end

-- ---------- 主面板页 ----------
local Page = {}
XC.Page = Page
local HELP = { "右边小图标 = 从哪来：亮的现在就能补，灰的现在用不上；悬停看全文，点了去补", "Right side = where to get it: lit = available now; hover for details, click to get it" }
function Page.Refresh()
    local p = XC.page
    if not (p and p:IsShown()) then return end
    local on = XC.Enabled()
    p.onBtn:SetText(on and L("已开启", "On") or L("已关闭", "Off"))
    p.winBtn:SetText(opt("always", false) and L("提醒条：一直半透明", "Bar: always") or (opt("win", true) and L("提醒条：快没了才出", "Bar: when ending") or L("提醒条：不显示", "Bar: off")))
    p.warnBtn:SetText(opt("warn", true) and L("到期提醒：开", "Alerts: on") or L("到期提醒：关", "Alerts: off"))
    local list = XC.Rows(false)
    if list.err then fit(p.note, p.w, { "|cffff5040" .. L("检查出错：", "Error: ") .. tostring(list.err) .. "|r", "|cffff5040" .. L("检查出错（悬停看）", "Error (hover)") .. "|r" }); p.err = list.err; return end
    p.err = false
    local nOk, nMiss = 0, 0
    for _, x in ipairs(list) do
        if x.it and x.it.st == "ok" then nOk = nOk + 1 elseif x.it and not x.have and (x.it.st == "miss" or x.it.st == "warn") then nMiss = nMiss + 1 end
    end
    paintList(list, p.rows, p.child, p.w, XC.RowWidget)
    if p.child.SetHeight then p.child:SetHeight(#list * (ROW_H + 3) + 4) end
    p.list = list
    if not on then fit(p.note, p.w, { L("经验加成检查已关闭", "XP check is off") })
    else
        local tt = opt("total", true) and XC.TotalText()
        local cnt = string.format(L("|cff40e060%d 项够了|r  ·  |cffff5040%d 项可以补|r", "|cff40e060%d ok|r  ·  |cffff5040%d to fix|r"), nOk, nMiss)
        local short = XC.TotalShort and XC.TotalShort()
        fit(p.note, p.w, { tt and ("|cff40e060" .. tt .. "|r  ·  " .. cnt), short and ("|cff40e060" .. short .. "|r  ·  " .. cnt), cnt })
    end
end

local function buildPage(p)
    XC.page = p
    local y = ns.PageHeader(p, L("经验加成", "XP bonuses"), L("增益 / 物资 ← 从哪来", "Bonuses & supplies <- where to get them"))
    p.onBtn = ns.Button(p, "", 90, 22, function() XC.Set("on", not XC.Enabled()); XC.hidden = false; Page.Refresh() end)
    p.onBtn:SetPoint("TOPLEFT", 12, y)
    p.winBtn = ns.Button(p, "", 150, 22, function()   -- 快没了才出 → 一直半透明 → 不显示 → 快没了才出
        local d = XC.DB()
        if not opt("win", true) then d.win = true; d.always = false
        elseif opt("always", false) then d.win = false; d.always = false
        else d.always = true end
        XC.hidden = false; XC.Update(); Page.Refresh()
    end)
    p.winBtn:SetPoint("LEFT", p.onBtn, "RIGHT", 8, 0)
    p.warnBtn = ns.Button(p, "", 110, 22, function() XC.Set("warn", not opt("warn", true)); Page.Refresh() end)
    p.warnBtn:SetPoint("LEFT", p.winBtn, "RIGHT", 8, 0)
    local prep = ns.Button(p, L("出发前清单", "Checklist"), 90, 22, function() if XC.Prep then XC.Prep.Show(false) end end)
    prep:SetPoint("LEFT", p.warnBtn, "RIGHT", 8, 0)
    local more = ns.Button(p, L("每项开关", "Settings"), 80, 22, function()
        if ns.TogglePageSettings and ns.TogglePageSettings("xp", true) then return end
        ns.ToggleMain("data")
    end)
    more:SetPoint("LEFT", prep, "RIGHT", 8, 0)
    p.w = 640
    p.err = false
    p.note = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.note:SetPoint("TOPLEFT", 14, y - 30); p.note:SetJustifyH("LEFT"); p.note:SetWordWrap(false); p.note:SetWidth(p.w)
    -- 合计的逐项明细 + 怎么看：悬停这一行
    local hit = CreateFrame("Frame", nil, p)
    hit:SetPoint("TOPLEFT", p.note, "TOPLEFT"); hit:SetPoint("BOTTOMRIGHT", p.note, "BOTTOMRIGHT")
    if hit.EnableMouse then hit:EnableMouse(true) end
    hit:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if rawget(p, "err") then GameTooltip:AddLine(tostring(p.err), 1, 0.35, 0.3, true) end
        if opt("total", true) and XC.TotalText() then
            GameTooltip:AddLine(XC.TotalText(), 0.25, 0.9, 0.35, true)
            for _, h in ipairs(XC.TotalLines()) do GameTooltip:AddLine("· " .. h, 0.8, 0.8, 0.8, true) end
        end
        GameTooltip:AddLine(L(HELP[1], HELP[2]), 0.5, 0.75, 1, true)
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", hideTip)
    p.scroll, p.child = ns.Scroll(p, 8, y - 48, p.w + 4, 474 + y - 54)   -- 内容区 474 高
    p.rows = {}
    local acc = 0
    p:SetScript("OnUpdate", function(_, el)   -- 11-18 卡顿：2 秒 → 5 秒（页面开着时才跑）
        acc = acc + (el or 0)
        if acc < 5 then return end
        acc = 0
        -- 11-18：定时刷新时背包没动就用上一轮扫的（XpSupply.lua XC.BagScan）
        XC.scanReuse = true
        local ok, err = pcall(Page.Refresh)
        XC.scanReuse = nil
        if not ok then error(err, 0) end
    end)
end
if ns.RegisterPage then
    local d = {}
    for k, v in pairs(XC.PAGE) do d[k] = v end
    d.build = buildPage
    d.refresh = function() Page.Refresh() end
    ns.RegisterPage(d)
end

-- 合计的短说法「经验 约 +8%」（细分在悬停）
function XC.TotalShort()
    local t = XC.total
    if not t then return nil end
    if t.kill > 0 or t.quest > 0 then return L("经验 ", "XP ") .. (t.approx and L("约 ", "~") or "") .. "+" .. math.max(t.kill, t.quest) .. "%" end
    if t.undead > 0 then return string.format(L("杀亡灵 +%d%%", "Undead +%d%%"), t.undead) end
    return nil
end

-- ---------- 出发前清单（主城 / 旅店）：紧凑小窗 ----------
local Prep = {}
XC.Prep = Prep
Prep.DEF_W, Prep.MIN_W, Prep.MAX_W = 300, 200, 640
Prep.WIDE, Prep.NAMES = 380, 340          -- 宽于 WIDE：主行先试长文字；宽于 NAMES：来源试带短名
Prep.SCALE_MIN, Prep.SCALE_MAX, Prep.SCALES = 0.6, 1.6, { 0.8, 1, 1.2 }
Prep.TOP, Prep.BOTTOM = 42, 14             -- 标题 + 汇总一行；底下给缩放角留 14
local GRIP = { "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up", "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down", "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight" }
local function D() return XC.DB() end
local function clampW(w) w = tonumber(w) or Prep.DEF_W; return math.floor(math.max(Prep.MIN_W, math.min(Prep.MAX_W, w)) + 0.5) end
function Prep.Width()
    local f = Prep.f
    local lw = f and rawget(f, "liveW")
    if lw then return lw end
    return clampW(D().prepW)
end
function Prep.Scale()
    local s = tonumber(D().prepScale) or 1
    return math.max(Prep.SCALE_MIN, math.min(Prep.SCALE_MAX, s))
end
-- 折叠：ok = 够用的、info = 可选的（默认都折叠；玩家点开记住）
function Prep.Folded(g)
    local t = D().prepFold
    if type(t) == "table" and t[g] ~= nil then return t[g] == true end
    return true
end
function Prep.Toggle(g)
    local d = D()
    if type(d.prepFold) ~= "table" then d.prepFold = {} end
    d.prepFold[g] = not Prep.Folded(g)
    Prep.Refresh()
end
local function savePos(f)
    local pt, _, rel, x, y = f:GetPoint()
    if pt then D().prepPos = { pt, x or 0, y or 0, rel or pt } end
end
local function place(f)
    f:ClearAllPoints()
    local pos = D().prepPos
    if type(pos) == "table" and pos[1] then f:SetPoint(pos[1], UIParent, pos[4] or pos[1], tonumber(pos[2]) or 0, tonumber(pos[3]) or 0)
    else f:SetPoint("TOP", UIParent, "TOP", 0, -120) end
end
-- 整体缩放：屏幕上左上角不动（换算成新缩放下的坐标）
function Prep.SetScale(s)
    s = math.floor((tonumber(s) or 1) * 20 + 0.5) / 20
    s = math.max(Prep.SCALE_MIN, math.min(Prep.SCALE_MAX, s))
    local f = Prep.f
    local old = Prep.Scale()
    D().prepScale = s
    if not f then return s end
    local l, t = num(f.GetLeft and f:GetLeft()), num(f.GetTop and f:GetTop())
    f:SetScale(s)
    if l and t and s > 0 then
        f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * old / s, t * old / s)
        D().prepPos = { "TOPLEFT", l * old / s, t * old / s, "BOTTOMLEFT" }
    end
    Prep.Refresh()
    return s
end
function Prep.SetLock(on)
    if on then D().prepLock = true else D().prepLock = nil end
    Prep.Refresh()
end
function Prep.Reset(quiet)
    local d = D()
    d.prepW, d.prepScale, d.prepPos, d.prepFold, d.prepLock = nil, nil, nil, nil, nil
    local f = Prep.f
    if f then
        f.liveW, f.sizing, f.drag = false, false, false
        f:SetScale(1); place(f); Prep.Refresh()
    end
    if not quiet then ns.Print(L("出发前清单：已恢复默认大小、缩放、位置和折叠", "Checklist: size, scale, position and folding reset")) end
end
function Prep.SetAuto(on)
    D().prep = on and true or false
    if on then ns.Print(L("出发前清单：进主城 / 旅店会自动弹", "Checklist will open in towns / inns"))
    else ns.Print(L("出发前清单：进主城不再自动弹（经验加成页「出发前清单」按钮还能打开；设置里可改回）", "Checklist won't auto-open (use the button on the XP page)")) end
end
-- 右键标题 / 齿轮的菜单
function Prep.MenuItems()
    local d, sc, items = D(), Prep.Scale(), {}
    for _, s in ipairs(Prep.SCALES) do
        items[#items + 1] = { text = string.format(L("缩放 %d%%", "Scale %d%%"), s * 100) .. (math.abs(sc - s) < 0.01 and L("（当前）", " (now)") or ""), fn = function() Prep.SetScale(s) end }
    end
    items[#items + 1] = { text = d.prepLock and L("解锁位置（可拖动）", "Unlock position") or L("锁定位置", "Lock position"), fn = function() Prep.SetLock(not d.prepLock) end }
    items[#items + 1] = { text = (d.prep ~= false) and L("进城不再自动弹", "Don't auto-open in town") or L("进城自动弹", "Auto-open in town"),
        fn = function() local on = d.prep == false; Prep.SetAuto(on); if not on then Prep.Hide() end end }
    items[#items + 1] = { text = L("恢复默认大小和位置", "Reset size and position"), fn = function() Prep.Reset() end }
    -- 11-18 用户「自定义 义父替代在哪里，要做到UI的」：齿轮菜单里也放称呼
    if ns.CallMenu and ns.CallWord then
        items[#items + 1] = { text = string.format(L("求人称呼：%s（点了改）", "Form of address: %s (change)"), ns.CallWord()),
            fn = function() ns.CallMenu(Prep.f, function() Prep.Refresh() end) end }
        items[#items + 1] = { text = string.format(L("喊 BUFF 频道：%s（点了换）", "Ask channel: %s (switch)"), XC.ShoutChanText()),
            fn = function() XC.ShoutMenu(Prep.f, function() Prep.Refresh() end) end }
    end
    return items
end
-- 右键 ×：进城不再自动弹（存档），聊天框说一次怎么找回
function Prep.Never()
    Prep.SetAuto(false)
    Prep.Hide()
    if ns.CloseHint then
        ns.CloseHint("xpPrep", L("找回出发前清单：GI 菜单 → 设置 → 窗口与提醒「出发前清单」点「打开」，或经验加成页「出发前清单」按钮",
            "Bring the checklist back: GI menu > Settings > Windows & alerts > Checklist, or the button on the XP page"))
    end
end
function Prep.Menu(anchor)
    if not ns.PopMenu then return end
    return ns.PopMenu(anchor or Prep.f, L("出发前清单", "Checklist") .. string.format("  %d%%", Prep.Scale() * 100 + 0.5), Prep.MenuItems())
end

-- 一行（紧凑）：色条 + 小图标 + 短文字 …… 来源小图标（+「用」）
local function miniTip(self)
    local r = rawget(self, "row")
    if not (r and GameTooltip) then return end
    local g = rawget(r, "group")
    if g then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(g == "ok" and L("这些都够了", "These are fine") or L("可选（不备也行）", "Optional"), 1, 0.82, 0)
        for _, x in ipairs(rawget(r, "glist") or {}) do GameTooltip:AddLine("· " .. stitle(x) .. L("：", ": ") .. (x.it and x.it.text or ""), 0.9, 0.9, 0.9, true) end
        GameTooltip:AddLine(Prep.Folded(g) and L("点一下展开", "Click to expand") or L("点一下收起", "Click to collapse"), 0.5, 0.75, 1)
        GameTooltip:Show()
        return
    end
    rowTip(self)
    if XC.RowNav(rawget(r, "src")) and GameTooltip.AddLine then
        GameTooltip:AddLine(L("点这一行：插旗导航到最近的商人", "Click this row: waypoint to the nearest vendor"), 0.5, 0.75, 1, true)
        GameTooltip:Show()
    end
end
-- 11-17 ② 这一行能导航的来源（商人）：点整行 = 点它
function XC.RowNav(sl)
    for _, s in ipairs(type(sl) == "table" and sl or {}) do if s.nav and s.fn then return s end end
end
-- 11-17 ④ 「职业BUFF 缺N」行的「喊」按钮（普通按钮：点击本身就是硬件事件，/说 要这个）
local function shoutBtn(row)
    local b = rawget(row, "shout")
    if b then return b end
    b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    b:SetSize(30, 18); b:SetPoint("RIGHT", -2, 0)
    b:SetFrameLevel((row:GetFrameLevel() or 1) + 3)
    if ns.SkinButton then ns.SkinButton(b) end
    b:SetText(L("喊", "Ask"))
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then   -- 11-18 右键「喊」= 改称呼；11-19 同一个菜单里选频道（说 / 大喊）
            if ns.CallMenu then hideTip(); XC.ShoutMenu(self) end
            return
        end
        local ks = self.ks
        if ks then XC.Shout(ks) end
    end)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L("喊 BUFF", "Ask for buffs"), 1, 0.82, 0)
        GameTooltip:AddLine(string.format(L("点了在「%s」频道说一句（副本里发队伍），带你的位置：", "Sends this in %s (party chat in dungeons), with your location:"), XC.ShoutChanText()), 1, 1, 1, true)
        GameTooltip:AddLine(XC.ShoutText(self.ks or {}) or "", 0.6, 0.85, 1, true)
        GameTooltip:AddLine(L("同一句 10 秒一次；有人加了会弹框问你要不要回谢", "Once per 10 s; offers a thank-you when someone buffs you"), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(string.format(L("频道：%s（右键选「说（白字）/ 大喊」）", "Channel: %s (right-click: Say / Yell)"), XC.ShoutChanText()), 0.5, 0.75, 1, true)
        if ns.CallTip then GameTooltip:AddLine(ns.CallTip(), 0.5, 0.75, 1, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", hideTip)
    row.shout = b
    return b
end
function XC.PaintShout(row, ks)
    local b = ks and shoutBtn(row) or rawget(row, "shout")
    if not b then return end
    b.ks = ks
    if ks then b:Show() else b:Hide() end
end
function XC.MiniRow(parent, w)
    local r = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    r:SetSize(w, MINI_H)
    r.w, r.compact, r.x, r.src, r.group, r.glist, r.shout = w, true, false, false, false, false, false
    if r.SetBackdrop then pcall(r.SetBackdrop, r, { bgFile = "Interface\\Buttons\\WHITE8x8" }) end
    r.bar = r:CreateTexture(nil, "ARTWORK"); r.bar:SetSize(3, MINI_H - 4); r.bar:SetPoint("LEFT", 1, 0)
    r.ic = r:CreateTexture(nil, "ARTWORK"); r.ic:SetSize(18, 18); r.ic:SetPoint("LEFT", 6, 0)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.text:SetPoint("LEFT", 28, 0)
    r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
    r.tog = r:CreateTexture(nil, "OVERLAY"); r.tog:SetSize(12, 12); r.tog:SetPoint("RIGHT", -6, 0); r.tog:Hide()
    r.hit = CreateFrame("Button", nil, r); r.hit:SetPoint("TOPLEFT"); r.hit:SetSize(w, MINI_H); r.hit.row = r
    r.hit:SetScript("OnEnter", miniTip); r.hit:SetScript("OnLeave", hideTip)
    if r.hit.RegisterForClicks then r.hit:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    r.hit:SetScript("OnClick", function(self, button)
        if button == "RightButton" then   -- 11-18 职业 BUFF 行右键 = 改称呼（别的行右键照旧不做事）
            if rawget(r, "key") == "cbuff" and not rawget(r, "group") and ns.CallMenu then hideTip(); XC.ShoutMenu(self, function() Prep.Refresh() end) end
            return
        end
        local g = rawget(r, "group")
        if g then Prep.Toggle(g); return end
        local s = XC.RowNav(rawget(r, "src"))
        if s then pcall(s.fn) end
    end)
    r.chips = {}
    local lv = num(r.GetFrameLevel and r:GetFrameLevel()) or 1
    for i = 1, MINI_CHIPS do
        local c = newChip(r, 16)
        if c.SetFrameLevel then c:SetFrameLevel(lv + 2) end
        r.chips[i] = c
    end
    return r
end
local function tint(row, col, a)
    row.bar:SetColorTexture(col[1], col[2], col[3], 1)
    if row.SetBackdropColor then row:SetBackdropColor(col[1] * 0.12, col[2] * 0.12, col[3] * 0.12, a or 0.8) end
end
local function paintMini(row, x, w, wide)
    row.w = w; row:SetWidth(w)
    row.group, row.glist, row.x, row.it, row.key = false, false, x, x.it or false, x.key
    local it = x.it
    local st = it and it.st or "off"
    local col = (x.have and COLOR.info) or COLOR[st] or COLOR.off
    tint(row, col)
    row.ic:SetTexture((it and it.icon) or XC.ICON[x.key] or "Interface\\Icons\\INV_Misc_QuestionMark"); row.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if row.ic.SetDesaturated then row.ic:SetDesaturated(st == "info" or x.have == true) end
    if row.ic.SetAlpha then row.ic:SetAlpha(x.have and 0.55 or 1) end
    row.tog:Hide()
    local sl = it and XC.Sources(it) or {}
    row.src = sl
    local use = it and (st == "miss" or st == "info") and it.use or nil
    local ks = (x.key == "cbuff" and it and type(it.missK) == "table" and it.missK[1] and XC.Opt2 and XC.Opt2("shoutBtn")) and it.missK or nil
    local lead, right = 28, (use and 34) or (ks and 34) or 4
    local cands = XC.RowTexts(x)
    if not wide and #cands > 2 then table.remove(cands, 1) end   -- 窄：不试长文字
    row.text:SetText(cands[#cands] or ""); local wTiny = math.ceil(sw(row.text))
    row.text:SetText(cands[math.max(1, #cands - 1)] or ""); local wShort = math.ceil(sw(row.text))
    local room = w - lead - right - 6
    local cw = layChips(row, sl, room - wTiny, (w >= Prep.NAMES) and (room - wShort) or nil, nil, right)
    local tw = math.max(1, room - cw)
    fit(row.text, tw, cands)
    if x.have then row.text:SetTextColor(0.75, 0.75, 0.75) elseif st == "miss" then row.text:SetTextColor(1, 0.55, 0.5) elseif st == "warn" then row.text:SetTextColor(1, 0.85, 0.3) elseif st == "info" then row.text:SetTextColor(0.7, 0.7, 0.7) else row.text:SetTextColor(1, 1, 1) end
    row.hit:SetSize(lead + tw, MINI_H)
    XC.PaintUse(row, use)
    XC.PaintShout(row, ks)
    row:Show()
end
local function paintGroup(row, g, items, w)
    row.w = w; row:SetWidth(w)
    row.group, row.glist, row.x, row.it, row.key, row.src = g, items, false, false, "grp_" .. g, false
    XC.PaintUse(row, nil)
    XC.PaintShout(row, nil)
    for _, c in ipairs(row.chips) do c.s = false; c:Hide() end
    tint(row, g == "ok" and COLOR.ok or COLOR.info, 0.5)
    row.ic:SetTexture(g == "ok" and READY or WAITING); row.ic:SetTexCoord(0, 1, 0, 1)
    if row.ic.SetDesaturated then row.ic:SetDesaturated(false) end
    row.tog:SetTexture(Prep.Folded(g) and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up"); row.tog:Show()
    local names = {}
    for _, x in ipairs(items) do names[#names + 1] = stitle(x) end
    local joined = table.concat(names, " · ")
    if g == "ok" then fit(row.text, w - 28 - 22, { joined, string.format(L("够用 %d 项", "%d OK"), #items) })
    else fit(row.text, w - 28 - 22, { L("可选：", "Optional: ") .. joined, string.format(L("可选 %d 项", "%d optional"), #items) }) end
    row.text:SetTextColor(g == "ok" and 0.6 or 0.7, g == "ok" and 0.95 or 0.7, g == "ok" and 0.6 or 0.7)
    row.hit:SetSize(w, MINI_H)
    row:Show()
end

-- 缩放角：按住拖改宽度（高度跟内容走）；右键恢复默认
function Prep.SizeStart(f)
    if rawget(f, "sizing") or D().prepLock then return end
    local l, t = num(f.GetLeft and f:GetLeft()), num(f.GetTop and f:GetTop())
    local cx = GetCursorPosition and num((GetCursorPosition()))
    if not (l and t and cx) then return end
    f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    D().prepPos = { "TOPLEFT", l, t, "BOTTOMLEFT" }
    local es = num(f.GetEffectiveScale and f:GetEffectiveScale()) or 1
    if es <= 0 then es = 1 end
    f.drag = { cx = cx, es = es, w = Prep.Width() }
    f.liveW = Prep.Width()
    f.sizing = true
    f.grip:SetScript("OnUpdate", function() Prep.SizeTick(f) end)
end
function Prep.SizeTick(f)
    local dr = rawget(f, "drag")
    if not dr then return end
    local cx = GetCursorPosition and num((GetCursorPosition()))
    if not cx then return end
    local w = clampW(dr.w + (cx - dr.cx) / dr.es)
    if w == rawget(f, "liveW") then return end
    f.liveW = w
    Prep.Refresh()
end
function Prep.SizeStop(f)
    f.grip:SetScript("OnUpdate", nil)
    if not rawget(f, "sizing") then return end
    local w = rawget(f, "liveW")
    if w then D().prepW = clampW(w) end
    f.sizing, f.drag, f.liveW = false, false, false
    Prep.Refresh()
end
local function buildGrip(f)
    local g = CreateFrame("Button", nil, f)
    g:SetSize(14, 14); g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    if g.SetNormalTexture then g:SetNormalTexture(GRIP[1]) end
    if g.SetPushedTexture then g:SetPushedTexture(GRIP[2]) end
    if g.SetHighlightTexture then g:SetHighlightTexture(GRIP[3]) end
    local lv = num(f.GetFrameLevel and f:GetFrameLevel())
    if lv and g.SetFrameLevel then g:SetFrameLevel(lv + 10) end
    g:SetScript("OnMouseDown", function(_, b) if b == nil or b == "LeftButton" then Prep.SizeStart(f) end end)
    g:SetScript("OnMouseUp", function(_, b) if b == "RightButton" then Prep.Reset(); return end Prep.SizeStop(f) end)
    g:SetScript("OnHide", function() if rawget(f, "sizing") then Prep.SizeStop(f) end end)
    g:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L("调整大小", "Resize"), 1, 0.82, 0)
        GameTooltip:AddLine(L("按住左键拖：改宽度（高度跟内容走；宽了会显示更多文字和来源名）", "Drag: change the width (wider shows more text)"), 1, 1, 1, true)
        GameTooltip:AddLine(L("Ctrl+滚轮 / 右键标题：整体缩放", "Ctrl+wheel / right-click the title: scale"), 0.6, 0.85, 1, true)
        GameTooltip:AddLine(L("右键：恢复默认", "Right-click: reset"), 0.6, 0.85, 1, true)
        GameTooltip:Show()
    end)
    g:SetScript("OnLeave", hideTip)
    f.grip = g
end

local function buildPrep()
    local f = CreateFrame("Frame", "GearInsightForeverXpPrep", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(Prep.DEF_W, 120); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true); f:SetMovable(true)
    f.liveW, f.sizing, f.drag = false, false, false
    if f.EnableMouse then f:EnableMouse(true) end
    if f.SetResizable then pcall(f.SetResizable, f, true) end
    local sh = num(UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 1080
    if f.SetResizeBounds then pcall(f.SetResizeBounds, f, Prep.MIN_W, 60, Prep.MAX_W, sh)
    else   -- 旧客户端
        if f.SetMinResize then pcall(f.SetMinResize, f, Prep.MIN_W, 60) end
        if f.SetMaxResize then pcall(f.SetMaxResize, f, Prep.MAX_W, sh) end
    end
    if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
    f:SetScript("OnDragStart", function(self) if not D().prepLock then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos(self) end)
    f:SetScript("OnMouseUp", function(self, b) if b == "RightButton" then Prep.Menu(self) end end)
    if f.EnableMouseWheel then f:EnableMouseWheel(true) end
    f:SetScript("OnMouseWheel", function(_, delta)
        if IsControlKeyDown and IsControlKeyDown() then Prep.SetScale(Prep.Scale() + ((delta or 0) > 0 and 0.1 or -0.1)) end
    end)
    f:SetScale(Prep.Scale())
    place(f)
    if f.SetBackdrop then
        pcall(f.SetBackdrop, f, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.04, 0.04, 0.05, 0.92); f:SetBackdropBorderColor(0.25, 0.9, 0.35, 0.5)
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.title:SetPoint("TOPLEFT", 8, -6)
    f.title:SetJustifyH("LEFT"); f.title:SetWordWrap(false)
    f.sum = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.sum:SetPoint("TOPLEFT", 8, -24)
    f.sum:SetJustifyH("LEFT"); f.sum:SetWordWrap(false)
    local sumHit = CreateFrame("Frame", nil, f)
    sumHit:SetPoint("TOPLEFT", 6, -22); sumHit:SetSize(Prep.DEF_W - 12, 16)
    if sumHit.EnableMouse then sumHit:EnableMouse(true) end
    sumHit:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        local tt = opt("total", true) and XC.TotalText()
        if tt then
            GameTooltip:AddLine(tt, 0.25, 0.9, 0.35, true)
            for _, h in ipairs(XC.TotalLines()) do GameTooltip:AddLine("· " .. h, 0.8, 0.8, 0.8, true) end
        end
        GameTooltip:AddLine(L(HELP[1], HELP[2]), 0.5, 0.75, 1, true)
        GameTooltip:AddLine(L("离开主城自动收起；右键标题 / 齿轮：缩放、锁定、进城不再自动弹", "Closes when you leave town; right-click the title for options"), 0.5, 0.75, 1, true)
        GameTooltip:Show()
    end)
    sumHit:SetScript("OnLeave", hideTip)
    f.sumHit = sumHit
    -- 11-17 用户「这些弹出的功能都确保能永久关闭」：左键 = 这次进城不再弹，右键 = 以后进城都不自动弹（存档 xpcheck.prep = false）
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetSize(20, 20); close:SetPoint("TOPRIGHT", 1, 1)
    close:SetScript("OnClick", function(_, mb)
        if mb == "RightButton" then Prep.Never(); return end
        Prep.Hide()
        if ns.CloseHint then
            ns.CloseHint("xpPrepX", L("出发前清单这次进城不再弹；以后都不想自动弹：右键 × 或齿轮菜单「进城不再自动弹」",
                "Checklist closed for this visit; to stop it auto-opening, right-click × or use the gear menu"))
        end
    end)
    close:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L("左键这次进城不再弹  ·  右键永久关闭（进城不再自动弹）", "Left: close for this visit  ·  Right: close for good"), 0.25, 0.9, 0.35, true)
        GameTooltip:Show()
    end)
    close:SetScript("OnLeave", hideTip)
    if close.RegisterForClicks then close:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    f.closeBtn = close
    local gear = CreateFrame("Button", nil, f); gear:SetSize(14, 14); gear:SetPoint("TOPRIGHT", -22, -4)
    if gear.SetNormalTexture then gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton") end
    if gear.SetHighlightTexture then gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight") end
    gear:SetScript("OnClick", function(self) Prep.Menu(self) end)
    gear:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L("缩放 / 锁定 / 进城不再自动弹 / 恢复默认", "Scale / lock / auto-open / reset"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", hideTip)
    f.gear = gear
    f.child = CreateFrame("Frame", nil, f); f.child:SetPoint("TOPLEFT", 6, -Prep.TOP); f.child:SetSize(Prep.DEF_W - 12, 10)
    f.rows = {}
    buildGrip(f)
    -- 11-18 用户「重载了还是巨卡」：原来每 2 秒整个清单重算一遍（扫背包 + 几十行）→ 10 秒兜底；背包 / 光环变化由下面的事件框立刻刷新
    local acc = 0
    f:SetScript("OnUpdate", function(self, el)
        acc = acc + (el or 0)
        if acc < 10 and not (rawget(self, "dirty") and acc >= 2) then return end   -- 有变化也至多 2 秒刷一次（主城光环变得勤）
        acc = 0
        rawset(self, "dirty", nil)
        -- 11-18：定时刷新时背包没动就用上一轮扫的（XpSupply.lua XC.BagScan；背包事件会作废这份缓存）
        XC.scanReuse = true
        local ok, err = pcall(Prep.Refresh)
        XC.scanReuse = nil
        if not ok then error(err, 0) end
    end)
    local ev = CreateFrame("Frame", nil, f)
    for _, e in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "UPDATE_INVENTORY_DURABILITY" }) do pcall(ev.RegisterEvent, ev, e) end
    if ev.RegisterUnitEvent then pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player") end
    ev:SetScript("OnEvent", function() rawset(f, "dirty", true) end)   -- 只标脏，下一帧统一刷新一次（同一帧多个事件不重复算）
    return f
end
function Prep.Refresh()
    local f = Prep.f
    if not (f and f:IsShown()) or inCombat() then return end   -- 战斗中不动布局（行里有安全按钮）
    local W = Prep.Width()
    f:SetWidth(W)
    local list = XC.Rows(true)
    local main, info, okl = {}, {}, {}
    for _, x in ipairs(list) do
        local st = x.it and x.it.st
        if st == "ok" then okl[#okl + 1] = x elseif st == "info" then info[#info + 1] = x else main[#main + 1] = x end
    end
    local items = {}
    for _, x in ipairs(main) do items[#items + 1] = { x = x } end
    for _, grp in ipairs({ { "info", info }, { "ok", okl } }) do
        if grp[2][1] then
            items[#items + 1] = { group = grp[1], list = grp[2] }
            if not Prep.Folded(grp[1]) then for _, x in ipairs(grp[2]) do items[#items + 1] = { x = x } end end
        end
    end
    local rw = W - 12
    for i, e in ipairs(items) do
        local row = f.rows[i]
        if not row then row = XC.MiniRow(f.child, rw); f.rows[i] = row end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(i - 1) * (MINI_H + 2))
        if e.group then paintGroup(row, e.group, e.list, rw) else paintMini(row, e.x, rw, W >= Prep.WIDE) end
    end
    for i = #items + 1, #f.rows do XC.PaintUse(f.rows[i], nil); XC.PaintShout(f.rows[i], nil); f.rows[i]:Hide() end
    f.child:SetSize(rw, math.max(1, #items * (MINI_H + 2)))
    f:SetHeight(Prep.TOP + #items * (MINI_H + 2) + Prep.BOTTOM)
    fit(f.title, W - 54, { L("出发前清单 · 主城备好再走", "Checklist - stock up in town"), L("出发前清单", "Checklist"), L("清单", "List") })
    local n = 0
    for _, x in ipairs(main) do if not x.have then n = n + 1 end end
    local short = opt("total", true) and XC.TotalShort() or nil
    local head = n > 0 and string.format(L("%d 项没备好", "%d to prepare"), n) or L("都备好了，出发！", "All set - go!")
    fit(f.sum, W - 16, { short and (head .. " · " .. short) or head, head, n > 0 and string.format(L("缺 %d", "-%d"), n) or L("齐了", "OK") })
    if n > 0 then f.sum:SetTextColor(1, 0.4, 0.35) else f.sum:SetTextColor(0.25, 0.9, 0.35) end
    if f.sumHit.SetSize then f.sumHit:SetSize(W - 12, 16) end
    if D().prepLock then f.grip:Hide() else f.grip:Show() end
    f.list, f.entries = list, items
end
-- auto = 进城自动弹（本次进城点过关闭就不再弹，离开再回来才弹）
function Prep.Show(auto)
    if inCombat() then return false end
    if auto and Prep.closed then return false end
    Prep.f = Prep.f or buildPrep()
    XC.prepFrame = Prep.f
    Prep.f:Show()
    Prep.Refresh()
    return true
end
function Prep.Hide(leaving)
    if Prep.f then Prep.f:Hide() end
end
-- 城里点 × = 这次进城不再自己弹；主插件 PrepCheck 离开休息区时也调 Hide（那时不在休息区）→ 清掉「关过」，回城再弹
local hide0 = Prep.Hide
Prep.Hide = function()
    Prep.closed = (IsResting and IsResting()) and true or nil
    hide0()
end

-- 「窗口与提醒」（11-17）：进主城自己弹的出发前清单（⛔ 本子插件按需加载，关掉自动弹后登录可能不加载 → 主插件要有同 key 占位，见回报）
if ns.RegisterWindow then
    ns.RegisterWindow({ key = "xpPrep", order = 31, title = function() return L("出发前清单（进主城自动弹）", "Departure checklist (auto in towns)") end,
        state = function()
            if Prep.f and Prep.f:IsShown() then return L("显示中", "Shown") end
            return D().prep ~= false and L("进主城 / 旅店时弹出", "Opens in towns / inns") or L("已关闭（进城不自动弹）", "Closed (no auto-open)")
        end,
        actions = function()
            local auto = D().prep ~= false
            return {
                { text = auto and L("关闭", "Turn off") or L("打开", "Turn on"), fn = function()
                    if auto then Prep.Never() else Prep.SetAuto(true); Prep.Show(false) end
                end },
                { text = L("重置位置", "Reset position"), fn = function() Prep.Reset() end },
            }
        end })
end
