-- 套装页：T1（海加尔峰）各职业 / 定位的套装效果（数据 = 小程序 / 网站「T1 套装」同一份 tier1）
-- Beta 客户端里套装件属性是隐藏的，只有套装效果；上线前可能改
-- 10-07 用户：每个专精一张卡（左边专精图标），每条套装效果前加技能图标；职业按钮加图标，本职业高亮
local _, ns = ...

local page, cur
local CARD_W = 600

local function icon(name, size)
    if not name or name == "" then return "" end
    return "|TInterface\\Icons\\" .. name .. ":" .. (size or 16) .. ":" .. (size or 16) .. ":0:0:64:64:5:59:5:59|t"
end

local function getCard(i)
    local c = page.cards[i]
    if c then return c end
    c = CreateFrame("Frame", nil, page.child)
    c:SetWidth(CARD_W)
    local bg = c:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.04)
    c.ic = c:CreateTexture(nil, "ARTWORK"); c.ic:SetSize(40, 40); c.ic:SetPoint("TOPLEFT", 8, -8)
    c.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.name = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    c.name:SetPoint("TOPLEFT", 56, -8); c.name:SetPoint("RIGHT", -8, 0); c.name:SetJustifyH("LEFT")
    c.sub = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    c.sub:SetPoint("TOPLEFT", 56, -26); c.sub:SetPoint("RIGHT", -8, 0); c.sub:SetJustifyH("LEFT")
    c.body = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.body:SetPoint("TOPLEFT", 56, -46); c.body:SetWidth(CARD_W - 66)
    c.body:SetJustifyH("LEFT"); c.body:SetSpacing(4)
    page.cards[i] = c
    return c
end

local function refresh()
    if not page then return end
    for _, b in ipairs(page.classBtns) do b.sel:SetShown(b.cls == cur) end
    for _, c in ipairs(page.cards) do c:Hide() end
    local y, n = -4, 0
    for _, s in ipairs(ns.Data.tier.sets or {}) do
        if s.cls == cur then
            n = n + 1
            local c = getCard(n)
            c:ClearAllPoints(); c:SetPoint("TOPLEFT", 4, y)
            c.ic:SetTexture("Interface\\Icons\\" .. (s.si or "inv_misc_questionmark"))
            c.name:SetText("|cffffd100" .. ns.L(s.n, s.nEn) .. "|r")
            c.sub:SetText(ns.EnSafe(ns.L(s.role, s.roleEn) .. " · " .. ns.L(s.spec, s.specEn)))   -- 10-07 用户截图「这有英文」：中文界面不再附英文套装名
            local lines = {}
            for _, b in ipairs(s.b) do
                lines[#lines + 1] = icon(b.i, 16) .. " |cff33ff99" .. b.p .. ns.L(" 件", "-pc") .. "|r  " .. ns.EnSafe(ns.L(b.cn, b.en))
            end
            c.body:SetText(table.concat(lines, "\n"))
            local h = 54 + c.body:GetStringHeight()
            c:SetHeight(h)
            c:Show()
            y = y - h - 8
        end
    end
    if n == 0 then
        local c = getCard(1)
        c:ClearAllPoints(); c:SetPoint("TOPLEFT", 4, -4)
        c.ic:SetTexture("Interface\\Icons\\inv_misc_questionmark")
        c.name:SetText(ns.L("这个职业还没有 T1 数据", "No Tier 1 data for this class yet"))
        c.sub:SetText(""); c.body:SetText(""); c:SetHeight(56); c:Show()
        y = -64
    end
    page.child:SetHeight(-y + 4)
end

local function build(p)
    page = p
    p.cards = {}
    local raid = (ns.Data.tier and ns.Data.tier.raid) or ""
    ns.PageHeader(p, ns.L("T1 套装", "Tier 1 sets"),
        ns.L(raid .. " · 12 月开放 · Beta 里套装件属性隐藏，效果上线前可能改",
            "Mount Hyjal (20) · opens in December · item stats hidden in Beta, bonuses may change"))
    p.classBtns = ns.ClassBar(p, -38, function(cls) cur = cls; refresh() end)
    local _, c = ns.Scroll(p, 6, -70, 616, 474 - 70 - 12)
    p.child = c
    cur = ns.MyClass()
end

ns.RegisterPage({ key = "tier", order = 3, title = ns.L("T1 套装", "Tier 1"), build = build, refresh = refresh })
