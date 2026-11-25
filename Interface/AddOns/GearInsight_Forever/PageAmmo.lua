-- HOLD：职业百宝箱 · 猎人「弹药商」（11-10 用户「游戏里弄个职业百宝箱页签…现在猎人，做一个功能就是定位最近的弓箭和子弹商」）
--   数据：AmmoVendorData.lua（scripts/gi_forever_ammo_vendors.py：vmangos 商人表 + Questie 坐标）+ 本地补记（打开卖弹药的商人窗口就记下）
--   找最近 / 插旗 / 开地图跟训练师一套（Trainers.lua 导出的 PlayerPos / World / ZoneName + ns.ShowOnMap）
--   远程武器是弓 / 弩 → 默认找箭，是枪 → 默认找子弹；两个按钮都在，手动切也行
local _, ns = ...; ns = _G.GearInsightForever or ns

local A = {}
ns.Ammo = A
local ARROW, BULLET = 1, 2
local ROWS = 6
local function has(mask, k) return math.floor((mask or 0) / k) % 2 == 1 end

local function T() return ns.Trainers or {} end
local function seenDB()
    ns.db.ammoSeen = ns.db.ammoSeen or {}
    return ns.db.ammoSeen
end
local function myFac()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return f == "Alliance" and "A" or f == "Horde" and "H" or "N"
end

-- 11-11 实测「装着弓却显示没装」：《无限》客户端没有全局 GetItemInfoInstant，要走 C_Item（同 ObsVendor.lua）
local function instant(link)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not (f and link) then return nil end
    local ok, _, _, _, _, _, classID, subID = pcall(f, link)
    if ok then return classID, subID end
end

local function slotLink(name, fallback)
    if not GetInventoryItemLink then return nil end
    local slot = fallback
    if GetInventorySlotInfo then
        local ok, s = pcall(GetInventorySlotInfo, name)
        if ok and s then slot = s end
    end
    return GetInventoryItemLink("player", slot)
end

-- 远程武器要什么弹药：弓(2) / 弩(18) → 箭，枪(3) → 子弹；远程格看不出来再看主手（新客户端弓枪可能在主手）、
-- 再看弹药格里装的是箭还是子弹；都没有 → nil
function A.WantKind()
    for _, s in ipairs({ { "RangedSlot", 18 }, { "MainHandSlot", 16 } }) do
        local classID, subID = instant(slotLink(s[1], s[2]))
        if classID == 2 then
            if subID == 2 or subID == 18 then return ARROW end
            if subID == 3 then return BULLET end
        end
    end
    local classID, subID = instant(slotLink("AmmoSlot", 0))
    if classID == 6 then
        if subID == 2 then return ARROW end
        if subID == 3 then return BULLET end
    end
    return nil
end

-- 身上的弹药（弹药栏那组的数量）
function A.AmmoCount()
    if not (GetInventorySlotInfo and GetInventoryItemCount) then return nil end
    local ok, slot = pcall(GetInventorySlotInfo, "AmmoSlot")
    if not ok or not slot then return nil end
    return GetInventoryItemCount("player", slot)
end

-- 11-17 用户截图「锯齿箭 · 40 以后要买这个了」「现在提示不对」：商人常卖的四档弹药（vmangos item_template + locales_item）
--   { 需求等级, 物品 ID, 中文名, 英文名, 每秒伤害+ }；51 / 52 级的冰线 / 瑟银只有奥山 / 声望商人卖，不算常卖档
A.TIERS = {
    [ARROW] = { { 1, 2512, "劣质箭", "Rough Arrow", 1 }, { 10, 2515, "锋利的箭", "Sharp Arrow", 3 },
        { 25, 3030, "锐锋箭", "Razor Arrow", 7 }, { 40, 11285, "锯齿箭", "Jagged Arrow", 13 } },
    [BULLET] = { { 1, 2516, "轻弹丸", "Light Shot", 1 }, { 10, 2519, "重弹丸", "Heavy Shot", 3 },
        { 25, 3033, "实心子弹", "Solid Shot", 7 }, { 40, 11284, "精准弹丸", "Accurate Slugs", 13 } },
}
-- 这个等级能买的最好那档：{ lv, id, zh, en, dps }
function A.Tier(kind, lv)
    lv = lv or (UnitLevel and UnitLevel("player")) or 1
    local best
    for _, t in ipairs(A.TIERS[kind] or {}) do if t[1] <= lv then best = t end end
    return best
end
function A.TierName(t) return t and ns.L(t[3], t[4]) or "" end
-- 某种弹药的需求等级：四档表里有就直接用，没有问客户端；读不出 → nil
function A.ReqOf(id)
    if not id then return nil end
    for _, list in pairs(A.TIERS) do
        for _, t in ipairs(list) do if t[2] == id then return t[1] end end
    end
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if f then
        local ok, _, _, _, _, minLv = pcall(f, id)
        if ok and tonumber(minLv) then return tonumber(minLv) end
    end
end

-- minLv：只要卖到这一档的商人（vendor 表第 8 列 = 这位卖的弹药最高需求等级）；一个都没有就退回全部
local function candidates(kind, minLv)
    local list, fac = {}, myFac()
    for _, v in ipairs(ns.AmmoVendorData or {}) do
        if (v[6] == fac or v[6] == "N") and has(v[7], kind) then
            list[#list + 1] = { ui = v[1], x = v[2], y = v[3], name = ns.L(v[4], v[5]), lv = v[8], kind = v[7], fac = v[6] }
        end
    end
    for name, s in pairs(seenDB()) do
        if s.ui and has(s.kind, kind) then
            list[#list + 1] = { ui = s.ui, x = s.x, y = s.y, name = name, seen = true, kind = s.kind, lv = s.lv }
        end
    end
    if minLv and minLv > 1 then
        local keep = {}
        for _, t in ipairs(list) do if (tonumber(t.lv) or 0) >= minLv then keep[#keep + 1] = t end end
        if #keep > 0 then return keep, true end
    end
    return list, false
end

-- 最近的几个：{ {t, 距离码 or nil}, ... }, 候选总数, 是否按 minLv 筛过
function A.Nearest(kind, max, minLv)
    local list, filtered = candidates(kind or ARROW, minLv)
    local pui, px, py
    if T().PlayerPos then pui, px, py = T().PlayerPos() end
    local world = T().World
    local pw = pui and world and world(pui, px, py)
    local scored = {}
    for _, t in ipairs(list) do
        local d
        local tw = pw and world(t.ui, t.x, t.y)
        if pw and tw and tw[1] == pw[1] then
            d = math.sqrt((tw[2] - pw[2]) ^ 2 + (tw[3] - pw[3]) ^ 2)
        elseif pui and t.ui == pui then
            d = math.sqrt((t.x - px) ^ 2 + (t.y - py) ^ 2) * 10
        end
        scored[#scored + 1] = { t = t, d = d }
    end
    table.sort(scored, function(a, b)
        if a.d and b.d then return a.d < b.d end
        if a.d or b.d then return a.d ~= nil end
        if (a.t.seen and 0 or 1) ~= (b.t.seen and 0 or 1) then return a.t.seen == true end
        return (a.t.name or "") < (b.t.name or "")
    end)
    local out = {}
    for i = 1, math.min(max or 3, #scored) do out[i] = scored[i] end
    return out, #list, filtered
end

local function zone(ui) return T().ZoneName and T().ZoneName(ui) or tostring(ui) end

function A.Go(kind)
    kind = kind or A.WantKind() or ARROW
    local tier = A.Tier(kind)
    local res, _, filtered = A.Nearest(kind, 3, tier and tier[1])
    local first = res[1]
    if not first then
        ns.Print(ns.L("没有找到你这个阵营的弹药商资料；打开一次卖弹药的商人窗口，插件会记下来", "No ammo vendors known for your faction; open an ammo vendor once and it will be remembered"))
        return
    end
    if not first.d then
        ns.Print(ns.L("这片大陆上没有已知的弹药商，先列出资料里的：", "No known ammo vendor on this continent; listing what we have:"))
    end
    ns.ShowOnMap(first.t.ui, { { first.t.x, first.t.y } }, first.t.name)
    for i, r in ipairs(res) do
        ns.Print(string.format("%d. %s  |cffaaaaaa%s %.1f, %.1f|r%s", i, r.t.name, zone(r.t.ui), r.t.x, r.t.y,
            r.d and string.format(ns.L("  约 %d 码", "  ~%d yd"), r.d) or ""))
    end
    if filtered then
        ns.Print(string.format(ns.L("（只列卖「%s」的商人：你这个等级该用它了）", "(Only vendors selling %s, the best for your level)"), A.TierName(tier)))
    end
    ns.Print(ns.L("已在地图上插旗（小地图边上有箭头指路）", "Waypoint set (follow the arrow on your minimap)"))
end

-- 打开商人窗口：货架上有箭 / 子弹就记下这位商人和你站的位置
function A.OnMerchantShow()
    if not (GetMerchantNumItems and GetMerchantItemLink) then return end
    local kind, top = 0, 0
    for i = 1, GetMerchantNumItems() do
        local link = GetMerchantItemLink(i)
        if link then
            local classID, subID = instant(link)
            if classID == 6 and subID == 2 and not has(kind, ARROW) then kind = kind + ARROW end
            if classID == 6 and subID == 3 and not has(kind, BULLET) then kind = kind + BULLET end
            if classID == 6 and (subID == 2 or subID == 3) then
                top = math.max(top, A.ReqOf(tonumber(link:match("item:(%d+)"))) or 0)
            end
        end
    end
    if kind == 0 then return end
    local name = UnitName and UnitName("npc")
    local ui, x, y
    if T().PlayerPos then ui, x, y = T().PlayerPos() end
    if not name or not ui then return end
    seenDB()[name] = { kind = kind, lv = top, ui = ui, x = math.floor(x * 10 + 0.5) / 10, y = math.floor(y * 10 + 0.5) / 10, t = time and time() or 0 }
end
local ev = CreateFrame("Frame")
ev:RegisterEvent("MERCHANT_SHOW")
ev:SetScript("OnEvent", function() pcall(A.OnMerchantShow) end)

-- ---------- 页面 ----------
-- 11-11 用户截图「展示优化」：每行左边弹药图标、卖什么 / 中立做成小标签、最近那位金条 + 「最近」、右边距离放大 + 「点击插旗」
local ICON_ARROW, ICON_BULLET = "Interface\\Icons\\INV_Ammo_Arrow_02", "Interface\\Icons\\INV_Ammo_Bullet_02"
local function tag(text, hex) return "|cff" .. hex .. "[" .. text .. "]|r" end

local function weaponLine()
    local want, cnt = A.WantKind(), A.AmmoCount()
    local ic = GetInventoryItemTexture and (GetInventoryItemTexture("player", 18) or GetInventoryItemTexture("player", 16))
    local w = want == ARROW and ns.L("远程武器用 |cffffd100箭|r", "Ranged weapon uses |cffffd100arrows|r")
        or want == BULLET and ns.L("远程武器用 |cffffd100子弹|r", "Ranged weapon uses |cffffd100bullets|r")
        or ns.L("没认出远程武器（弓 / 弩 / 枪）", "No bow, crossbow or gun found")
    if ic and want then w = "|T" .. ic .. ":18:18:0:0|t " .. w end
    if cnt then
        -- 11-11 和补充提醒（AmmoRemind.lua）同一套线
        local AR = ns.AmmoRemind
        local urgent, warn = AR and AR.Get("urgent") or 150, AR and AR.Get("warn") or 400
        local hex = cnt < urgent and "ff4040" or cnt < warn and "ffd100" or "ffffff"
        w = w .. string.format(ns.L("　·　身上弹药 |cff%s%d|r 发", "  -  ammo on you: |cff%s%d|r"), hex, cnt)
        if cnt < urgent then w = w .. ns.L("  |cffff4040快用完了|r", "  |cffff4040running low|r") end
    end
    return w
end

local function paint(p)
    local kind = rawget(p, "ammoKind") or A.WantKind() or ARROW
    rawset(p, "ammoKind", kind)
    if ns.SegSelect then
        ns.SegSelect(p.segA, kind == ARROW)
        ns.SegSelect(p.segB, kind == BULLET)
    end
    p.info:SetText(weaponLine())
    local res, total = A.Nearest(kind, ROWS)
    for i = 1, ROWS do
        local row, r = p.rows[i], res[i]
        if r then
            local t = r.t
            row.r = r
            local both = has(t.kind, ARROW) and has(t.kind, BULLET)
            row.icon:SetTexture(both and (kind == ARROW and ICON_ARROW or ICON_BULLET) or (has(t.kind, BULLET) and ICON_BULLET or ICON_ARROW))
            local tags = {}
            if i == 1 and r.d then tags[#tags + 1] = tag(ns.L("最近", "nearest"), "ffd100") end
            if both then tags[#tags + 1] = tag(ns.L("箭和子弹都卖", "arrows + bullets"), "8fd3ff") end
            if t.fac == "N" then tags[#tags + 1] = tag(ns.L("中立", "neutral"), "c0c0c0") end
            if t.seen then tags[#tags + 1] = tag(ns.L("你去过", "visited"), "33ff99") end
            row.name:SetText(t.name .. (#tags > 0 and ("  " .. table.concat(tags, " ")) or ""))
            row.where:SetText(string.format("%s  |cff888888%.1f, %.1f|r", zone(t.ui), t.x, t.y))
            if r.d then
                row.dist:SetText(r.d < 15 and ns.L("|cff33ff99就在身边|r", "|cff33ff99right here|r") or string.format(ns.L("约 %d 码", "~%d yd"), r.d))
            else
                row.dist:SetText(ns.L("|cff888888别的大陆|r", "|cff888888other continent|r"))
            end
            row.bar:SetShown(i == 1 and r.d ~= nil)
            row:Show()
        else
            row:Hide()
        end
    end
    p.empty:SetShown(#res == 0)
    p.foot:SetText(string.format(ns.L("资料里有你这个阵营可去的 %d 位%s商人；《无限》新地区的商人，打开一次他的窗口就会记下", "%d %s vendors for your faction; vendors in new Forever zones are learned when you open them"),
        total, kind == ARROW and ns.L("弓箭", "arrow") or ns.L("子弹", "bullet")))
end

local function build(p)
    local y0 = ns.PageHeader(p, ns.L("弹药商", "Ammo vendors"), ns.L("猎人 · 找最近卖箭 / 子弹的商人，点一下在地图上插旗", "Hunter - nearest arrow / bullet vendor, click to set a waypoint"))
    y0 = y0 or -44
    p.segA = ns.SegButton(p, ns.L("弓箭商", "Arrows"), 100, 24, function() rawset(p, "ammoKind", ARROW); paint(p) end)
    p.segA:SetPoint("TOPLEFT", 12, y0)
    p.segB = ns.SegButton(p, ns.L("子弹商", "Bullets"), 100, 24, function() rawset(p, "ammoKind", BULLET); paint(p) end)
    p.segB:SetPoint("LEFT", p.segA, "RIGHT", 6, 0)
    local go = ns.Button(p, ns.L("带我去最近的", "Take me to the nearest"), 150, 24, function() A.Go(rawget(p, "ammoKind")) end)
    go:SetPoint("LEFT", p.segB, "RIGHT", 16, 0)
    p.info = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.info:SetPoint("TOPLEFT", 14, y0 - 38)
    p.rows = {}
    local RH, STEP = 44, 48
    for i = 1, ROWS do
        local b = CreateFrame("Button", nil, p)
        b:SetHeight(RH)
        b:SetPoint("TOPLEFT", 12, y0 - 64 - (i - 1) * STEP)
        b:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, y0 - 64 - (i - 1) * STEP)
        local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.04)
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.10)
        b.bar = b:CreateTexture(nil, "ARTWORK"); b.bar:SetColorTexture(1, 0.82, 0, 0.9)
        b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetWidth(3)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(30, 30); b.icon:SetPoint("LEFT", 10, 0)
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal"); b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 10, 1)
        b.where = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.where:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 10, 0)
        b.where:SetTextColor(0.75, 0.75, 0.75)
        b.dist = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge"); b.dist:SetPoint("TOPRIGHT", -14, -6)
        b.hint = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); b.hint:SetPoint("BOTTOMRIGHT", -14, 6)
        b.hint:SetText(ns.L("点击插旗 ›", "click to set waypoint ›"))
        b:SetScript("OnClick", function(self)
            if self.r then ns.ShowOnMap(self.r.t.ui, { { self.r.t.x, self.r.t.y } }, self.r.t.name) end
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local t = self.r and self.r.t
            if t then
                GameTooltip:AddLine(t.name, 1, 1, 1)
                GameTooltip:AddLine(string.format("%s  %.1f, %.1f", zone(t.ui), t.x, t.y), 0.75, 0.75, 0.75)
                if t.lv and t.lv > 0 then
                    GameTooltip:AddLine(string.format(ns.L("货架上最好的弹药要 %d 级", "Best ammo on sale needs level %d"), t.lv), 0.75, 0.75, 0.75)
                end
            end
            GameTooltip:AddLine(ns.L("点一下：在地图上插旗", "Click: set a waypoint"), 1, 0.82, 0)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p.rows[i] = b
    end
    p.empty = p:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    p.empty:SetPoint("TOPLEFT", 14, y0 - 74)
    p.empty:SetText(ns.L("还没有你这个阵营的弹药商资料", "No ammo vendors known for your faction yet"))
    p.foot = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.foot:SetPoint("TOPLEFT", 14, y0 - 64 - ROWS * STEP - 6); p.foot:SetPoint("RIGHT", p, "RIGHT", -14, 0); p.foot:SetJustifyH("LEFT")
    paint(p)
end

ns.RegisterPage({ key = "ammo", order = 1.45, class = "Hunter", title = ns.L("弹药商", "Ammo vendors"), build = build, refresh = paint })

ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.ammo = function() A.Go() end
ns.ExtraSlash["弹药"] = ns.ExtraSlash.ammo
