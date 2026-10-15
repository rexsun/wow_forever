-- 主界面（v1，10-07）：窗口 + 左外侧竖排图标页签 + 小地图按钮
-- 各页在自己的文件里 ns.RegisterPage{ key, title, order, build(page), refresh(page) }
-- ⛔ 公会 / 组队 / 社交功能不放这里（归 GuildInsight）
local _, ns = ...

local W, H = 690, 564   -- 10-07 页签挪到面板外：内容区仍是 670 × 474
local GOLD = { 1, 0.82, 0 }
local pages, frame, current = {}, nil, nil

function ns.RegisterPage(p)
    pages[#pages + 1] = p
    table.sort(pages, function(a, b) return (a.order or 99) < (b.order or 99) end)
end
ns._Pages = pages   -- 测试用（左侧页签 / 顶部功能列表都按它画）
-- 10-11 录像用：还没发布的页（RegisterPage 时带 hold = true）在 /gif keys off 后不出页签、不进顶部功能列表
local function visiblePages()
    local t = {}
    for _, p in ipairs(pages) do
        if not (p.hold and ns.db and ns.db.hideHold) then t[#t + 1] = p end
    end
    return t
end

-- 公共小工具：页头大字 + 分隔线，返回内容区起始 y
function ns.PageHeader(p, title, sub)
    local hd = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hd:SetPoint("TOPLEFT", 12, -10)
    hd:SetText(title)
    hd:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    if sub then
        local s = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s:SetPoint("LEFT", hd, "RIGHT", 10, -1)
        s:SetPoint("RIGHT", p, "RIGHT", -12, 0)
        s:SetJustifyH("LEFT")
        s:SetText(ns.EnSafe(sub))
        s:SetTextColor(0.7, 0.7, 0.7)
        p._sub = s
    end
    local ln = p:CreateTexture(nil, "ARTWORK")
    ln:SetColorTexture(0.3, 0.3, 0.3, 0.6)
    ln:SetPoint("TOPLEFT", 8, -34); ln:SetPoint("TOPRIGHT", -8, -34)
    ln:SetHeight(1)
    return -42
end

function ns.Button(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 100, h or 22)
    b:SetText(text)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- ---------- 职业：公共常量 + 职业按钮条（10-07 用户：职业加图标、本职业高亮）----------
ns.CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
ns.CLASS_COLOR = { Warrior = "c79c6e", Paladin = "f58cba", Hunter = "abd473", Rogue = "fff569", Priest = "ffffff",
    Shaman = "0070de", Mage = "69ccf0", Warlock = "9482c9", Druid = "ff7d0a" }
ns.CLASS_ICON = { Warrior = "inv_sword_27", Paladin = "spell_holy_holybolt", Hunter = "inv_weapon_bow_07",
    Rogue = "inv_throwingknife_04", Priest = "inv_staff_30", Shaman = "spell_nature_bloodlust",
    Mage = "inv_staff_13", Warlock = "spell_nature_drowsy", Druid = "ability_druid_maul" }

function ns.MyClass()
    local _, token = UnitClass("player")
    token = token or "Warrior"
    return token:sub(1, 1) .. token:sub(2):lower()
end

-- 本职业：金色描边（四条边）；返回描边容器，调用方不用管
function ns.MarkMine(b)
    local c = { 1, 0.82, 0, 0.95 }
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
        { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(c[1], c[2], c[3], c[4])
        t:SetPoint(side[1]); t:SetPoint(side[2])
        if side[3] then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
    end
end

-- 一排 9 个职业按钮（图标 + 职业色名字；本职业金框）；返回按钮表，每个有 .cls / .sel
local SHORT_CN = { Paladin = "圣骑", Shaman = "萨满", Druid = "德鲁伊" }
function ns.ClassBar(p, y, onClick)
    local btns, mine = {}, ns.MyClass()
    local x = 8
    for k, cls in ipairs(ns.CLASSES) do
        local b = CreateFrame("Button", nil, p)
        -- 10-07 用户「优化UI」：9 × 73 超出页面、长名字被截成「圣骑…」→ 短名
        -- 10-08 用户截图「最边上的德鲁伊展示全」：等宽 68 放不下三个字 → 按名字长短给宽度（两字 64 / 三字 78，合计 622 < 646）
        local label = ns.L(SHORT_CN[cls] or ns.Data.classCn[cls] or cls, cls)
        local zh = ns.zh
        local w = zh and ((#label > 6) and 78 or 64) or 68   -- UTF-8 中文一字 3 字节：>6 = 三个字；英文统一 68
        b:SetSize(w, 24)
        b:SetPoint("TOPLEFT", x, y); x = x + w + 4
        local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.04)
        local sel = b:CreateTexture(nil, "BACKGROUND", nil, 1); sel:SetAllPoints(); sel:SetColorTexture(0.2, 0.8, 0.6, 0.3); sel:Hide()
        -- 选中：底下一条职业色粗线（比整块染色清楚，也不和本职业金框打架）
        local r, g, bb = tonumber(ns.CLASS_COLOR[cls]:sub(1, 2), 16) / 255, tonumber(ns.CLASS_COLOR[cls]:sub(3, 4), 16) / 255, tonumber(ns.CLASS_COLOR[cls]:sub(5, 6), 16) / 255
        local line = b:CreateTexture(nil, "ARTWORK", nil, 2); line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(3)
        line:SetColorTexture(r, g, bb, 1)
        sel:SetColorTexture(r, g, bb, 0.22)
        line:Hide()
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.1)
        local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(18, 18); ic:SetPoint("LEFT", 3, 0)
        ic:SetTexture("Interface\\Icons\\" .. ns.CLASS_ICON[cls]); ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", ic, "RIGHT", 3, 0); fs:SetPoint("RIGHT", -2, 0); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        fs:SetText("|cff" .. ns.CLASS_COLOR[cls] .. label .. "|r")
        if cls == mine then ns.MarkMine(b) end
        -- .sel 是个小代理：底色和底线一起开关（页面里只调 b.sel:SetShown）
        b.sel = { SetShown = function(_, v) sel:SetShown(v); line:SetShown(v) end, IsShown = function() return sel:IsShown() end }
        b.cls = cls
        b:SetScript("OnClick", function() onClick(cls) end)
        b:SetScript("OnEnter", function(self)   -- 名字万一被截也能看全（用户硬规定：显示不全一律挂 tooltip）
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("|cff" .. ns.CLASS_COLOR[cls] .. ns.L(ns.Data.classCn[cls] or cls, cls) .. "|r")
            if cls == mine then GameTooltip:AddLine(ns.L("你的职业", "Your class"), 1, 0.82, 0) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btns[k] = b
    end
    return btns
end

-- 可滚动内容：返回 scroll, child（child 宽度跟随）
function ns.Scroll(parent, x, y, w, h)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", x, y)
    sf:SetSize(w, h)
    local c = CreateFrame("Frame", nil, sf)
    c:SetSize(w, 10)
    sf:SetScrollChild(c)
    return sf, c
end

-- 10-07 用户「板式也变成这种页签的」（GuildInsight 改版那张图）：标题栏 logo 色带 + 挂在面板左外侧的竖排大图标页签，
--   选中 = 金边；页面内容区宽高不变（页签挪出去后面板窄 118px，标题栏多出来 44px）
-- ⛔ 图标只用 60 级经典就有的游戏图标（无限客户端里一定存在）
local TAB_ICON = {
    talent = "Interface\\Icons\\INV_Misc_Book_11",
    macro = "Interface\\Icons\\INV_Scroll_05",
    loot = "Interface\\Icons\\INV_Misc_Bag_10",
    tier = "Interface\\Icons\\INV_Chest_Plate03",
    news = "Interface\\Icons\\INV_Letter_15",
    data = "Interface\\Icons\\INV_Misc_Note_01",
}
local LOGO = "Interface\\AddOns\\GearInsight_Forever\\media\\logo"
local HEAD = 80    -- 标题栏高度（内容区从这里往下）

local function setTabSel(b, on)
    if b.SetBackdropColor then
        if on then b:SetBackdropColor(0.13, 0.12, 0.07, 0.98); b:SetBackdropBorderColor(1, 0.82, 0, 0.9)
        else b:SetBackdropColor(0.05, 0.06, 0.08, 0.92); b:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.8) end
    end
    if on then b.label:SetTextColor(1, 0.82, 0) else b.label:SetTextColor(0.82, 0.82, 0.82) end
end

local function showPage(key)
    local vis = visiblePages()
    local okKey = false
    for _, p in ipairs(vis) do if p.key == key then okKey = true end end
    if not okKey and vis[1] then key = vis[1].key end   -- 记住的页被隐藏了 → 退回第一页
    for _, p in ipairs(pages) do
        if p.frame then p.frame:Hide() end
        if p.tab then setTabSel(p.tab, false) end
    end
    for _, p in ipairs(pages) do
        if p.key == key then
            if not p.frame then
                local f = CreateFrame("Frame", nil, frame)
                f:SetPoint("TOPLEFT", 10, -HEAD)
                f:SetPoint("BOTTOMRIGHT", -10, 10)
                local ok, err = pcall(p.build, f)
                if not ok then ns.Print("页面出错 " .. p.key .. ": " .. tostring(err)) end
                p.frame = f
            end
            p.frame:Show()
            if p.tab then setTabSel(p.tab, true) end
            if p.refresh then pcall(p.refresh, p.frame) end
            current = key
            ns.db.ui = ns.db.ui or {}
            ns.db.ui.page = key
        end
    end
end
ns.ShowPage = showPage

local function build()
    local f = CreateFrame("Frame", "GearInsightForeverMain", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(W, H)
    f:SetPoint("CENTER", 50, 0)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        f:SetBackdropColor(0.04, 0.05, 0.07, 0.96); f:SetBackdropBorderColor(0.85, 0.68, 0.25, 1)
    end

    -- 标题栏：logo + 名字 + 版本；下一行 = 角色 / 开服提示
    local band = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    band:SetPoint("TOPLEFT", 5, -5); band:SetPoint("TOPRIGHT", -5, -5); band:SetHeight(68)
    band:SetColorTexture(0.10, 0.20, 0.16, 0.55)
    local logo = f:CreateTexture(nil, "ARTWORK"); logo:SetSize(58, 58); logo:SetPoint("TOPLEFT", 12, -10); logo:SetTexture(LOGO)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -6)
    local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("GearInsight_Forever", "Version"))
        or (GetAddOnMetadata and GetAddOnMetadata("GearInsight_Forever", "Version")) or ""
    title:SetText("|cff33ff99Gear|r|cffffd200Insight|r " .. ns.L("无限版", "Forever") .. "  |cff888888" .. ver .. "|r")
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    -- Keep long localized page lists inside the header, including added pages.
    f.sub:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    f.sub:SetHeight(28)
    f.sub:SetJustifyH("LEFT"); f.sub:SetJustifyV("TOP")
    f.sub:SetWordWrap(true)
    if f.sub.SetMaxLines then f.sub:SetMaxLines(2) end
    local subHit = CreateFrame("Frame", nil, f)
    subHit:SetAllPoints(f.sub); subHit:EnableMouse(true)
    subHit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(f.sub:GetText() or "", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    subHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local cmd = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); cmd:SetPoint("TOPRIGHT", -40, -22)
    cmd:SetText(ns.SlashHint or "/gif")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -4, -4)
    local line = f:CreateTexture(nil, "ARTWORK"); line:SetPoint("TOPLEFT", 6, -73); line:SetPoint("TOPRIGHT", -6, -73); line:SetHeight(1)
    line:SetColorTexture(0.85, 0.68, 0.25, 0.45)
    f:SetScript("OnShow", function(self)
        local lv = UnitLevel and UnitLevel("player") or 0
        local cls = ns.MyClass()
        -- 页签名现查 pages 表拼，⛔别手写死list：新加页会漏（10-07 升级规划/资讯两页上线时就漏过一次）
        local names = {}
        for _, p in ipairs(visiblePages()) do names[#names + 1] = p.tabTitle or p.title end
        self.sub:SetText("|cff" .. (ns.CLASS_COLOR[cls] or "ffffff") .. ns.L(ns.Data.classCn[cls] or cls, cls) .. "|r  "
            .. ns.L("等级 ", "level ") .. lv .. "   |cff888888" .. table.concat(names, " · ") .. "|r")
    end)

    -- 页签：挂在面板左外侧的竖排大标签（图标 + 名字），点标签换整页
    local prev
    local tabPages = visiblePages()
    for _, p in ipairs(tabPages) do
        local b = CreateFrame("Button", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
        -- 10-10 第 8 个页签（成就）：48 高 + 6 间距 × 8 = 432 + 起点 80 超出面板 474 → 多于 7 个时压成 44 + 4
        --   10-10 第 9 个（键位手法）：9 × 44 + 8 × 4 也超 → 多于 8 个时 40 + 3（9 个 = 384 + 80 = 464）
        --   10-12 键位 / 手法拆成两个页签（照正式服阶段 3）= 第 10 个：10 × 36 + 9 × 3 = 387 + 80 = 467
        local np = #tabPages
        local th, tg = 48, 6
        if np > 9 then th, tg = 36, 3 elseif np > 8 then th, tg = 40, 3 elseif np > 7 then th, tg = 44, 4 end
        b:SetSize(100, th)
        if prev then b:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -tg) else b:SetPoint("TOPRIGHT", f, "TOPLEFT", 3, -80) end
        if b.SetBackdrop then
            b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        end
        local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(24, 24); ic:SetPoint("LEFT", 9, 0)
        ic:SetTexture(p.icon or TAB_ICON[p.key] or "Interface\\Icons\\INV_Misc_QuestionMark"); ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal"); b.label:SetPoint("LEFT", ic, "RIGHT", 7, 0)
        b.label:SetPoint("RIGHT", -4, 0); b.label:SetJustifyH("LEFT"); b.label:SetWordWrap(false)
        b.label:SetText(p.tabTitle or p.title)
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.10)
        b:SetScript("OnClick", function() showPage(p.key) end)
        setTabSel(b, false)
        p.tab = b
        prev = b
    end

    if UISpecialFrames then table.insert(UISpecialFrames, "GearInsightForeverMain") end
    f:Hide()
    return f
end

function ns.ToggleMain(key)
    frame = frame or build()
    if frame:IsShown() and (not key or key == current) then frame:Hide(); return end
    frame:Show()
    showPage(key or (ns.db.ui and ns.db.ui.page) or (pages[1] and pages[1].key))
end

-- ---------- 小地图按钮 ----------
local function placeButton(b)
    local a = math.rad(ns.db.minimap.angle or 210)
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
end

local function buildMinimap()
    if not Minimap then return end
    ns.db.minimap = ns.db.minimap or { angle = 210 }
    local b = CreateFrame("Button", "GearInsightForeverMinimap", Minimap)
    b:SetSize(32, 32); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\inv_misc_map_01")
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54); border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then ns.ToggleMain("data") else ns.ToggleMain() end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            ns.db.minimap.angle = math.deg(math.atan2(py / s - my, px / s - mx))
            placeButton(self)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff33ff99GearInsight|r " .. ns.L("无限版", "Forever"))
        GameTooltip:AddLine(ns.L("左键：打开主界面", "Left-click: open"), 1, 1, 1)
        GameTooltip:AddLine(ns.L("右键：公测数据", "Right-click: beta data"), 1, 1, 1)
        GameTooltip:AddLine(ns.L("拖动：移动按钮", "Drag: move"), 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    placeButton(b)
    if ns.db.minimap.hide then b:Hide() end
    ns.MinimapButton = b
end

function ns.SetMinimapShown(on)
    ns.db.minimap = ns.db.minimap or {}
    ns.db.minimap.hide = not on
    if ns.MinimapButton then ns.MinimapButton:SetShown(on) end
end

table.insert(ns.modules, function() pcall(buildMinimap) end)
