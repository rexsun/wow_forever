-- 商人助手面板的外框（11-17 用户截图「重合了，优化一下，是不是应该整合到一个」）：标题栏 / × / 「不再弹」/ 页签 / 排版 / 位置
--   登记和开关状态的小核在主插件 MerchantDock.lua（ns.MerchantDock）；这里给它补上画框的函数。放在清背包子插件里是为了省主插件登录内存
--   （卖垃圾默认第一次开商人就加载这个子插件；材料那块要弹时主插件 D.UI() 也会加载它）。说明见 MerchantDock.lua 文件头
--   ⛔ 这个文件晚于主插件加载：文件头 ns = _G.GearInsightForever or ns
local _, ns = ...; ns = _G.GearInsightForever or ns
local L = function(cn, en) return ns.L(cn, en) end
local D = ns.MerchantDock
if not D then return end

local function now() return (GetTime and GetTime()) or 0 end
local function after(sec, fn)
    if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end
end
local function num(v) return type(v) == "number" and v or nil end
local function mcall(o, m, ...)
    if type(o) ~= "table" or type(o[m]) ~= "function" then return nil end
    local ok, v = pcall(o[m], o, ...)
    if ok then return v end
    return nil
end
function D.Shown() return D.frame ~= nil and D.frame:IsShown() and true or false end

-- ---------- 外框 ----------
local function fs(p, font)
    local t = p:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    t:SetJustifyH("LEFT")
    if t.SetWordWrap then t:SetWordWrap(false) end
    return t
end
function D.Build()
    if D.frame then return D.frame end
    local f = CreateFrame("Frame", "GearInsightForeverMerchantDock", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    D.frame = f
    f:Hide()
    f:SetSize(D.W, 120)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    if f.SetBackdrop then
        pcall(f.SetBackdrop, f, { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.04, 0.05, 0.07, 0.96); f:SetBackdropBorderColor(0.85, 0.68, 0.25, 1)
    end
    -- 标题栏：拖动 / 右键复位
    local head = CreateFrame("Button", nil, f)
    head:SetPoint("TOPLEFT", 4, -3); head:SetPoint("TOPRIGHT", -90, -3); head:SetHeight(D.HEAD - 2)
    head:RegisterForDrag("LeftButton")
    head:RegisterForClicks("RightButtonUp")
    head:SetScript("OnDragStart", function() D.dragging = true; f:StartMoving() end)
    head:SetScript("OnDragStop", function() f:StopMovingOrSizing(); D.dragging = false; D.SavePos() end)
    head:SetScript("OnClick", function(_, btn) if btn == "RightButton" then D.ResetPos() end end)
    head:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("GearInsight " .. L("商人助手", "Merchant helper"), 1, 0.82, 0)
        GameTooltip:AddLine(L("拖标题栏移动 · 右键回到商人窗口旁", "Drag to move · right-click to snap back beside the merchant"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    head:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f.head = head
    f.title = fs(f, "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -8); f.title:SetWidth(D.W - 110)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(22, 22); close:SetPoint("TOPRIGHT", -1, -1)
    close:SetScript("OnClick", function() D.Close() end)   -- 直接 Hide（原生红叉走 HideUIPanel，战斗中被拦）
    f.close = close
    f.never = ns.Button(f, L("不再弹", "Never"), 56, 16, function() D.Never() end)
    f.never:SetPoint("RIGHT", close, "LEFT", -2, 0)
    if f.never.HookScript then
        f.never:HookScript("OnEnter", function(self)
            local def = D.secs[D.cur or ""]
            if not (GameTooltip and def) then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(string.format(L("「%s」以后不自动弹", "Stop auto-showing \"%s\""), def.tab()), 1, 0.82, 0)
            GameTooltip:AddLine(L("只关这一块，另一块照常弹", "Only this part - the other one still shows"), 1, 1, 1, true)
            if def.neverTip then GameTooltip:AddLine(def.neverTip(), 0.7, 0.7, 0.7, true) end
            GameTooltip:Show()
        end)
        f.never:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    f.tabs = {}
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetSize(D.W - 2 * D.PAD, 10)
    D.HookMerchant()
    return f
end
-- 一块内容的容器（宽 = D.W - 2 × PAD；高由那一块 D.SetHeight 报上来）
function D.Body(key)
    local f = D.Build()
    D.bodies = D.bodies or {}
    local b = D.bodies[key]
    if b then return b end
    b = CreateFrame("Frame", nil, f.body)
    b:SetSize(D.W - 2 * D.PAD, 10)
    b:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, 0)
    b:Hide()
    D.bodies[key] = b
    return b
end
function D.SetHeight(key, h)
    D.heights = D.heights or {}
    D.heights[key] = tonumber(h) or 0
    if D.on[key] then D.Layout() end
end
local function tab(i)
    local f = D.frame
    local t = f.tabs[i]
    if t then return t end
    t = ns.Button(f, "", 120, D.TABH - 2, nil)
    t:SetScript("OnClick", function(self) D.Pick(rawget(self, "key")) end)
    f.tabs[i] = t
    return t
end
function D.TabText(key)
    local def = D.secs[key]
    if not def then return "" end
    local n = def.count and tonumber(def.count())
    return def.tab() .. ((n and n > 0) and ("  |cffffffff" .. n .. "|r") or "")
end

-- ---------- 排版 ----------
function D.Layout()
    local f = D.frame
    if not f then return end
    local act = D.Active()
    if #act == 0 then
        D.cur, D.picked, D.held, D.holdUntil = nil, nil, nil, nil
        f:Hide()
        for _, b in pairs(D.bodies or {}) do b:Hide() end
        return
    end
    -- 刚开商人：专业材料那块 0.3 秒后才算好 → 先等一下再弹，免得先出卖垃圾页、再跳到材料页
    if D.holdUntil and not D.on.shop and now() < D.holdUntil and not f:IsShown() then return end
    if not (D.cur and D.on[D.cur]) or not D.picked then D.cur = act[1] end
    local cur = D.cur
    local multi = #act >= 2
    local top = D.HEAD + D.GAP
    for i, t in ipairs(multi and act or {}) do
        local b = tab(i)
        b.key = t
        b:SetText(D.TabText(t))
        b:ClearAllPoints()
        local w = (D.W - 2 * D.PAD - (#act - 1) * 4) / #act
        b:SetSize(w, D.TABH - 2)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", D.PAD + (i - 1) * (w + 4), -D.HEAD)
        if ns.SegSelect then ns.SegSelect(b, t == cur) end
        b:Show()
    end
    for i = (multi and #act or 0) + 1, #f.tabs do f.tabs[i]:Hide() end
    if multi then top = D.HEAD + D.TABH + D.GAP end
    local def = D.secs[cur]
    f.title:SetText("GearInsight " .. L("商人助手", "Merchant helper") .. ((not multi and def) and ("|cffaaaaaa · " .. def.tab() .. "|r") or ""))
    f.body:ClearAllPoints()
    f.body:SetPoint("TOPLEFT", f, "TOPLEFT", D.PAD, -top)
    for k, b in pairs(D.bodies or {}) do
        if k == cur then b:Show() else b:Hide() end
    end
    local h = (D.heights and D.heights[cur]) or 100
    f.body:SetHeight(h)
    f:SetHeight(top + h + D.PAD)
    D.layout = { multi = multi, cur = cur, top = top, act = act }
    if not D.dragging then D.Place() end
    f:Show()
end
D.Update = D.Layout

-- ---------- 一块的开 / 关 ----------
-- opts.focus = 玩家点的（/gi 卖、背包上的「卖垃圾」按钮）→ 切到这一页；opts.auto = 开商人自动弹（可能先等材料那块）
function D.Show(key, opts)
    if not D.secs[key] then return false end
    D.Build()
    D.on[key] = true
    if opts and opts.focus then D.cur, D.picked = key, true end
    if opts and opts.auto and key ~= "shop" and not D.frame:IsShown() and not D.held then
        D.held = true
        local wanted = ns.ProfQuickWanted
        if type(wanted) == "function" and wanted() then
            D.holdUntil = now() + D.HOLD_SEC
            after(D.HOLD_SEC, function() D.holdUntil = nil; D.Layout() end)
        end
    end
    D.Layout()
    return true
end
function D.Hide(key)
    if not D.on[key] then return end
    D.on[key] = nil
    if D.cur == key then D.cur, D.picked = nil, nil end
    D.Layout()
end
function D.Pick(key)
    if not (key and D.on[key]) then return end
    D.cur, D.picked = key, true
    D.Layout()
end
-- ×：这次开商人两块都收起
function D.Close()
    for _, k in ipairs(D.Active()) do
        local def = D.secs[k]
        if def.onClose then pcall(def.onClose) end
    end
    D.on, D.cur, D.picked = {}, nil, nil
    D.Layout()
end
-- 「不再弹」：只关当前页那一块
function D.Never()
    local k = D.cur
    local def = k and D.secs[k]
    if not def then return end
    if def.never then pcall(def.never) end
    D.Hide(k)
end
-- 商人关了：状态清零（各块自己也会收到关商人，收起自己）
function D.Reset()
    D.on, D.cur, D.picked, D.held, D.holdUntil = {}, nil, nil, nil, nil
    if D.frame then D.Layout() end
end

-- ---------- 位置 ----------
function D.SavePos()
    local f = D.frame
    if not (f and ns.db) then return end
    local x, y = num(mcall(f, "GetLeft")), num(mcall(f, "GetTop"))
    if not (x and y) then return end
    ns.db.merchantDock = { x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
    D.Place()
end
function D.ResetPos()
    if ns.db then ns.db.merchantDock = nil end
    D.Place()
end
-- 商人窗口在 UIParent 坐标里的 左 / 右 / 下 / 上（缩放不同要换算）
local function rect(fr)
    local l, r, b, t = num(mcall(fr, "GetLeft")), num(mcall(fr, "GetRight")), num(mcall(fr, "GetBottom")), num(mcall(fr, "GetTop"))
    if not (l and r and b and t) then return nil end
    local s1, s0 = num(mcall(fr, "GetEffectiveScale")), num(mcall(UIParent, "GetEffectiveScale"))
    local k = (s1 and s0 and s0 > 0) and (s1 / s0) or 1
    return l * k, r * k, b * k, t * k
end
-- 返回放在哪：saved / right / below / left / center
function D.Place()
    local f = D.frame
    if not f then return nil end
    f:ClearAllPoints()
    local p = ns.db and ns.db.merchantDock
    if type(p) == "table" and num(p.x) and num(p.y) then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
        D.where = "saved"
        return D.where
    end
    local mf = rawget(_G, "MerchantFrame")
    if type(mf) ~= "table" then
        f:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
        D.where = "center"
        return D.where
    end
    local where = "right"
    local l, r, b = rect(mf)
    local sw = num(mcall(UIParent, "GetRight")) or num(mcall(UIParent, "GetWidth"))
    local h = num(mcall(f, "GetHeight")) or 300
    if l and sw and r + D.GAP + D.W > sw then
        if b - 30 - h >= 0 then where = "below"
        elseif l - D.GAP - D.W >= 0 then where = "left" end
    end
    if where == "below" then f:SetPoint("TOPLEFT", mf, "BOTTOMLEFT", 0, -30)       -- 让开商人窗口下沿右边的「GearInsight 冲专业」按钮（22 高）
    elseif where == "left" then f:SetPoint("TOPRIGHT", mf, "TOPLEFT", -D.GAP, -2)
    else f:SetPoint("TOPLEFT", mf, "TOPRIGHT", D.GAP, -2) end
    D.where = where
    return where
end

-- ---------- 商人关：清状态（不另建事件框；MERCHANT_CLOSED 时两块各自 D.Hide，最后一块收起时也清）----------
function D.HookMerchant()
    if D.hooked then return end
    local mf = rawget(_G, "MerchantFrame")
    if type(mf) == "table" and type(mf.HookScript) == "function" then
        D.hooked = true
        pcall(mf.HookScript, mf, "OnHide", function() D.Reset() end)   -- 关商人（两块自己也会收到 MERCHANT_CLOSED 各自收起）
    end
end
