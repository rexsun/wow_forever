-- =============================================================================
-- DungeonsForever · 主窗口与入口
-- 独立可拖动窗口（HUI 圆角窗皮），承载副本手册页（列表 / 详情 / 掉落 / 任务）。
-- 入口：小地图按钮（左键开关）+ 斜杠命令 /df（见本文件末尾）。
-- =============================================================================

local _, ns = ...

if not ns.IsTitan then return end

local L = ns.L

local W, H = 1000, 708

-- ★ 版本号只写 toc（## Version），界面统一在这里读一次，禁止多处写死
-- ★★ 新引擎（1.15.4+ / 11.0+）把元数据 API 挪进了 C_AddOns，全局 GetAddOnMetadata
--    可能已不存在（Blizzard_Deprecated 也没补别名）⇒ 两边都探一次，谁在就用谁
local DF_VERSION
do
    if type(C_AddOns) == "table" and type(C_AddOns.GetAddOnMetadata) == "function" then
        DF_VERSION = C_AddOns.GetAddOnMetadata("DungeonsForever", "Version")
    end
    if (DF_VERSION == nil or DF_VERSION == "") and type(GetAddOnMetadata) == "function" then
        DF_VERSION = GetAddOnMetadata("DungeonsForever", "Version")
    end
    if type(DF_VERSION) ~= "string" or DF_VERSION == "" then DF_VERSION = nil end
end

local f = CreateFrame("Frame", "DungeonsForever_MainFrame", UIParent, "BackdropTemplate")
tinsert(UISpecialFrames, "DungeonsForever_MainFrame")
f:SetSize(W, H)
f:SetFrameStrata("HIGH")
f:SetToplevel(true)
f:SetMovable(true)
f:SetClampedToScreen(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetPoint("CENTER")
f:Hide()

ns.MainFrame = f
ns.TalentSimFrame = f

do
    if ns.hui and ns.hui.SkinPopup then
        ns.hui.SkinPopup(f, 8)
    else
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0x2b / 255, 0x2b / 255, 0x2b / 255, 0.95)
        f:SetBackdropBorderColor(1, 1, 1, 0.10)
    end
end

local title = f:CreateFontString(nil, "OVERLAY")
title:SetFont(ns.FONT, 15, "")
title:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -14)
title:SetText(L["无限副本手册"])
title:SetTextColor(0.95, 0.96, 0.98)

local subtitle = f:CreateFontString(nil, "OVERLAY")
subtitle:SetFont(ns.FONT, 11, "")
subtitle:SetPoint("LEFT", title, "RIGHT", 10, 0)
subtitle:SetText("DungeonsForever" .. (DF_VERSION and (" v" .. DF_VERSION) or ""))
subtitle:SetTextColor(0.55, 0.62, 0.70)

local close = CreateFrame("Button", nil, f)
close:SetSize(32, 32)
close:SetFrameLevel(510)
close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
close:SetHitRectInsets(-3, -3, -3, -3)
do
    local gray = 0xa0 / 255
    local it = close:CreateTexture(nil, "ARTWORK")
    it:SetTexture("Interface\\AddOns\\DungeonsForever\\Media\\textures\\YY_close")
    it:SetSize(20, 20)
    it:SetPoint("CENTER")
    it:SetVertexColor(gray, gray, gray)
    close:HookScript("OnEnter", function() it:SetVertexColor(1, 1, 1) end)
    close:HookScript("OnLeave", function() it:SetVertexColor(gray, gray, gray) end)
end
close:SetScript("OnClick", function()
    ns.PlaySound(1)
    f:Hide()
end)

local aboutGlyph
local about

local function SyncAboutGlyph()
    if not aboutGlyph then return end
    if about and about:IsShown() then
        aboutGlyph:SetTextColor(1, 1, 1)
    else
        local g = 0xa0 / 255
        aboutGlyph:SetTextColor(g, g, g)
    end
end

local aboutBtn = CreateFrame("Button", nil, f)
aboutBtn:SetSize(32, 32)
aboutBtn:SetFrameLevel(510)
aboutBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -4)
aboutBtn:SetHitRectInsets(-3, -3, -3, -3)
do
    local q = aboutBtn:CreateFontString(nil, "ARTWORK")
    q:SetFont(ns.FONT, 17, "")
    q:SetText("?")
    q:SetPoint("CENTER")
    aboutGlyph = q
end
aboutBtn:SetScript("OnEnter", function(self)
    aboutGlyph:SetTextColor(1, 1, 1)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(L["关于"], 1, 1, 1, true)
    GameTooltip:Show()
end)
aboutBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
    SyncAboutGlyph()
end)
aboutBtn:SetScript("OnClick", function()
    ns.PlaySound(1)
    about:SetShown(not about:IsShown())
    SyncAboutGlyph()
end)

about = CreateFrame("Frame", nil, f, "BackdropTemplate")
about:SetFrameLevel(505)
about:SetAllPoints(f)
about:EnableMouse(true)
about:SetScript("OnMouseWheel", function() end)
about:SetScript("OnMouseUp", function()
    ns.PlaySound(1)
    about:Hide()
    SyncAboutGlyph()
end)
about:Hide()
if ns.hui and ns.hui.SkinPopup then
    ns.hui.SkinPopup(about, 8)
else
    about:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    about:SetBackdropColor(0x2b / 255, 0x2b / 255, 0x2b / 255, 1)
end

do
    local icon = about:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\DungeonsForever\\Media\\DungeonsForever.blp")
    icon:SetSize(56, 56)
    icon:SetPoint("CENTER", about, "CENTER", 0, 148)

    local brand = about:CreateFontString(nil, "OVERLAY")
    brand:SetFont(ns.FONT, 16, "")
    brand:SetText(L["无限副本手册"])
    brand:SetPoint("CENTER", about, "CENTER", 0, 92)
    brand:SetTextColor(0.95, 0.96, 0.98)

    local ver = DF_VERSION
    local sub = about:CreateFontString(nil, "OVERLAY")
    sub:SetFont(ns.FONT, 14, "")
    sub:SetText("DungeonsForever" .. (ver and (" · v" .. ver) or ""))
    sub:SetPoint("CENTER", about, "CENTER", 0, 66)
    sub:SetTextColor(0.55, 0.62, 0.70)

    local studio = about:CreateFontString(nil, "OVERLAY")
    studio:SetFont(ns.FONT, 14, "")
    studio:SetText(L["黑科研研究所"])
    studio:SetPoint("CENTER", about, "CENTER", 0, 42)
    studio:SetTextColor(0.55, 0.62, 0.70)

    local rows = {
        { L["作者"], L["圆圆"] },
        { L["鸣谢"], L["黑科研 · 胡里胡涂"] },
        { L["QQ群"], "728916609" },
        { L["指令"], "|cff46bf72/df|r · |cff46bf72/fbsc|r · /副本手册 — " .. L["开关窗口"] },
        { L["页面"], "|cff46bf72/df fb|r" .. L["副本"] .. " · |cff46bf72tb|r" .. L["团本"]
            .. " · |cff46bf72zy|r" .. L["专业"] .. " · |cff46bf72ts|r" .. L["探索"]
            .. " · |cff46bf72bis|r" .. L["配装"] },
    }
    for i, row in ipairs(rows) do
        local ln = about:CreateFontString(nil, "OVERLAY")
        ln:SetFont(ns.FONT, 14, "")
        ln:SetText("|cff8c9eb3" .. row[1] .. "|r　" .. row[2])
        ln:SetPoint("CENTER", about, "CENTER", 0, 6 - (i - 1) * 28)
        ln:SetTextColor(0.88, 0.90, 0.93)
    end

    local credit = about:CreateFontString(nil, "OVERLAY")
    credit:SetFont(ns.FONT, 14, "")
    credit:SetText(L["数据来源：wowhead"])
    credit:SetPoint("BOTTOM", about, "BOTTOM", 0, 22)
    credit:SetTextColor(0.55, 0.62, 0.70)
end

local settingsGlyph
local settingsPop

local function SyncSettingsGlyph()
    if not settingsGlyph then return end
    local c = (settingsPop and settingsPop:IsShown()) and ns.SET_ICON_ON or ns.SET_ICON_IDLE
    settingsGlyph:SetVertexColor(c[1], c[2], c[3])
end

local settingsBtn = CreateFrame("Button", nil, f)
settingsBtn:SetSize(32, 32)
settingsBtn:SetFrameLevel(510)
settingsBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -76, -4)
settingsBtn:SetHitRectInsets(-3, -3, -3, -3)
do
    local g = settingsBtn:CreateTexture(nil, "ARTWORK")
    g:SetTexture(ns.SET_ICON)
    g:SetSize(14, 14)
    g:SetPoint("CENTER")
    g:SetVertexColor(ns.SET_ICON_IDLE[1], ns.SET_ICON_IDLE[2], ns.SET_ICON_IDLE[3])
    settingsGlyph = g
end
settingsBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(L["设置"], 1, 1, 1, true)
    GameTooltip:Show()
end)
settingsBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
    SyncSettingsGlyph()
end)
settingsBtn:SetScript("OnClick", function()
    ns.PlaySound(1)
    local show = not settingsPop:IsShown()
    if show then
        about:Hide()
        SyncAboutGlyph()
        -- 与掉落页「装备过滤」面板互斥：开设置时收起过滤面板
        if ns.LootFilterUI and ns.LootFilterUI.CloseConfig then ns.LootFilterUI:CloseConfig() end
        -- 与探索页「地图设置」侧挂面板互斥
        if ns.CloseExploreMapSettings then ns.CloseExploreMapSettings() end
    end
    if show and ns.QuickBar then ns.QuickBar:SyncSettings() end
    settingsPop:SetShown(show)
    SyncSettingsGlyph()
end)

settingsPop = CreateFrame("Frame", nil, f, "BackdropTemplate")
settingsPop:SetFrameLevel(512)
settingsPop:SetPoint("TOPLEFT", f, "TOPRIGHT", 8, 0)
settingsPop:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 8, 0)
settingsPop:SetWidth(220)
settingsPop:EnableMouse(true)
settingsPop:SetScript("OnMouseWheel", function() end)
settingsPop:Hide()
if ns.hui and ns.hui.SkinPopup then
    ns.hui.SkinPopup(settingsPop, 8)
else
    settingsPop:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    settingsPop:SetBackdropColor(0x2b / 255, 0x2b / 255, 0x2b / 255, 1)
end

-- 供掉落页「装备过滤」面板互斥调用：打开过滤面板时先收起设置弹窗（含图标态复位）。
ns.CloseSettings = function()
    if settingsPop then settingsPop:Hide() end
    SyncSettingsGlyph()
end

-- 设置面板对外入口：别的模块（快捷按钮栏）把自己的分组挂进这个弹窗。
ns.SettingsPopup = settingsPop

do
    local title = settingsPop:CreateFontString(nil, "OVERLAY")
    title:SetFont(ns.FONT, 16, "")
    title:SetText(L["设置"])
    title:SetPoint("TOPLEFT", settingsPop, "TOPLEFT", 16, -14)
    title:SetTextColor(0.95, 0.96, 0.98)
end

local SCALE_MIN, SCALE_MAX, SCALE_STEP = 60, 140, 5

local scaleTimer
local scaleReady = false
local scaleValue = 100
local scaleGroup
local scaleText

local function ApplyScale()
    f:SetScale(scaleValue / 100)
    ns.DB().ui.scale = scaleValue
end

local function ScheduleScale()
    if scaleTimer and scaleTimer.Cancel then scaleTimer:Cancel() end
    if C_Timer and C_Timer.After then
        scaleTimer = C_Timer.After(0.5, function()
            scaleTimer = nil
            ApplyScale()
        end)
    else
        ApplyScale()
    end
end

local function SetScaleValue(v)
    v = math.floor(math.max(SCALE_MIN, math.min(SCALE_MAX, v)) + 0.5)
    if v == scaleValue then return end
    scaleValue = v
    scaleText.text:SetText(v .. "%")
    if scaleReady then ScheduleScale() end
end

local function ScaleTooltip(self, title)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(title, 1, 1, 1, true)
    GameTooltip:AddLine(L["范围 60%–140%，停手 0.5 秒生效"], 0.7, 0.75, 0.8, true)
    GameTooltip:Show()
end

local C_PILL_BG = {0x26 / 255, 0x29 / 255, 0x2e / 255}
local C_PILL_ED = {0x55 / 255, 0x58 / 255, 0x5e / 255}
local C_GLYPH   = {0.67, 0.70, 0.73}
local C_NUM     = {0.91, 0.93, 0.94}
local PILL_H    = 22

scaleGroup = CreateFrame("Frame", nil, f, "BackdropTemplate")
scaleGroup:SetFrameLevel(510)
scaleGroup:SetSize(94, PILL_H)
scaleGroup:SetPoint("TOPRIGHT", f, "TOPRIGHT", -116, -9)
scaleGroup:SetBackdrop({ bgFile = "Interface/ChatFrame/ChatFrameBackground" })
scaleGroup:SetBackdropColor(C_PILL_BG[1], C_PILL_BG[2], C_PILL_BG[3], 0.6)
do
    local border = CreateFrame("Frame", nil, scaleGroup)
    border:SetAllPoints()
    ns.hui.BuildRoundBorder(border, 8, C_PILL_ED)
    local hover = CreateFrame("Frame", nil, scaleGroup)
    hover:SetAllPoints()
    hover:Hide()
    ns.hui.BuildRoundBorder(hover, 8, ns.hui.ACCENT)
    scaleGroup.hover = hover
end

local function AddDivider(x)
    local d = scaleGroup:CreateTexture(nil, "OVERLAY")
    d:SetColorTexture(C_PILL_ED[1], C_PILL_ED[2], C_PILL_ED[3], 0.7)
    d:SetPoint("TOPLEFT", x, -5)
    d:SetSize(1, PILL_H - 10)
end
AddDivider(24)
AddDivider(69)

local function MakeGlyphButton(width, label, anchor)
    local bt = CreateFrame("Button", nil, scaleGroup)
    bt:SetFrameLevel(511)
    bt:SetSize(width, PILL_H)
    bt:SetPoint(anchor, scaleGroup, anchor, 0, 0)
    local t = bt:CreateFontString(nil, "OVERLAY")
    bt:SetFontString(t)
    t:SetFont(ns.FONT, 13, "")
    t:SetText(label)
    t:SetPoint("CENTER")
    t:SetTextColor(C_GLYPH[1], C_GLYPH[2], C_GLYPH[3])
    return bt
end

local minusBtn = MakeGlyphButton(24, "-", "TOPLEFT")
local plusBtn  = MakeGlyphButton(24, "+", "TOPRIGHT")
scaleText = CreateFrame("Button", nil, scaleGroup)
scaleText:SetFrameLevel(511)
scaleText:SetSize(44, PILL_H)
scaleText:SetPoint("TOPLEFT", minusBtn, "TOPRIGHT")
do
    local t = scaleText:CreateFontString(nil, "OVERLAY")
    t:SetFont(ns.FONT, 12, "")
    t:SetText("100%")
    t:SetPoint("CENTER")
    t:SetTextColor(C_NUM[1], C_NUM[2], C_NUM[3])
    scaleText.text = t
end

local function HoverOn(glyph)
    if scaleGroup.hover then scaleGroup.hover:Show() end
    if glyph then glyph:SetTextColor(ns.hui.ACCENT[1], ns.hui.ACCENT[2], ns.hui.ACCENT[3]) end
end
local function HoverOff(glyph)
    if scaleGroup.hover then scaleGroup.hover:Hide() end
    if glyph then glyph:SetTextColor(C_GLYPH[1], C_GLYPH[2], C_GLYPH[3]) end
end

local function StopRepeat(bt)
    bt.__holding = nil
    if bt.__delay then bt.__delay:Cancel() bt.__delay = nil end
    if bt.__ticker then bt.__ticker:Cancel() bt.__ticker = nil end
end

local function StartRepeat(bt, dir)
    if not (C_Timer and C_Timer.After and C_Timer.NewTicker) then return end
    StopRepeat(bt)
    bt.__holding = true
    bt.__delay = C_Timer.After(0.4, function()
        bt.__delay = nil
        if not bt.__holding then return end
        bt.__ticker = C_Timer.NewTicker(0.12, function()
            if not bt.__holding or not bt:IsMouseOver() then
                StopRepeat(bt)
                return
            end
            SetScaleValue(scaleValue + dir * SCALE_STEP)
        end)
    end)
end

plusBtn:SetScript("OnMouseDown", function()
    SetScaleValue(scaleValue + SCALE_STEP)
    StartRepeat(plusBtn, 1)
end)
plusBtn:SetScript("OnMouseUp", function() StopRepeat(plusBtn) end)
minusBtn:SetScript("OnMouseDown", function()
    SetScaleValue(scaleValue - SCALE_STEP)
    StartRepeat(minusBtn, -1)
end)
minusBtn:SetScript("OnMouseUp", function() StopRepeat(minusBtn) end)

plusBtn:SetScript("OnEnter", function(self) HoverOn(self:GetFontString()) ScaleTooltip(self, L["放大界面"]) end)
plusBtn:SetScript("OnLeave", function(self) HoverOff(self:GetFontString()) GameTooltip:Hide() end)
minusBtn:SetScript("OnEnter", function(self) HoverOn(self:GetFontString()) ScaleTooltip(self, L["缩小界面"]) end)
minusBtn:SetScript("OnLeave", function(self) HoverOff(self:GetFontString()) GameTooltip:Hide() end)

scaleText:SetScript("OnEnter", function(self)
    HoverOn()
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(L["界面大小"], 1, 1, 1, true)
    GameTooltip:AddLine(L["点击复位 100%"], 0.7, 0.75, 0.8, true)
    GameTooltip:Show()
end)
scaleText:SetScript("OnLeave", function(self) HoverOff() GameTooltip:Hide() end)
scaleText:SetScript("OnClick", function()
    ns.PlaySound(1)
    SetScaleValue(100)
end)

f:HookScript("OnShow", function()
    about:Hide()
    SyncAboutGlyph()
    if settingsPop then settingsPop:Hide() end
    SyncSettingsGlyph()
    if ns.LootFilterUI then ns.LootFilterUI:CloseConfig() end
    if ns.QuickBar then ns.QuickBar:OnMainShow() end
end)

local function SavePosition()
    local db = ns.DB().ui
    local point, _, relPoint, x, y = f:GetPoint(1)
    db.window = { point = point, relPoint = relPoint, x = x, y = y }
end

f:SetScript("OnDragStart", function(self) self:StartMoving() end)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
end)

ns.Init(function()
    local pos = ns.DB().ui.window
    if pos and pos.point then
        f:ClearAllPoints()
        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    end
    local sc = ns.DB().ui.scale
    if sc then
        sc = math.max(60, math.min(140, sc))
        f:SetScale(sc / 100)
        scaleValue = sc
        scaleText.text:SetText(sc .. "%")
    end
    scaleReady = true
end)

function ns.Open()
    if not f:IsShown() then f:Show() end
    f:Raise()
end

function ns.Toggle()
    if f:IsShown() then f:Hide() else ns.Open() end
end

ns.OpenDungeon = ns.Open

ns.Init(function()
    local LDB = LibStub("LibDataBroker-1.1", true)
    local LibDBIcon = LibStub("LibDBIcon-1.0", true)
    if not (LDB and LibDBIcon) then return end

    local db = ns.DB().ui
    if not db.minimap then db.minimap = { hide = false, minimapPos = 315 } end
    if db.minimap.minimapPos == nil then db.minimap.minimapPos = 315 end

    local launcher = LDB:NewDataObject("DungeonsForever", {
        type = "launcher",
        icon = "Interface\\AddOns\\DungeonsForever\\Media\\DungeonsForever.blp",
        OnClick = function(_, button)
            if button == "LeftButton" then ns.Toggle() end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("|cff46bf72" .. L["无限副本手册"] .. "|r")
            tt:AddLine(L["左键：打开 / 关闭界面"], 1, 1, 1)
        end,
    })
    LibDBIcon:Register("DungeonsForever", launcher, db.minimap)
end)

SLASH_DUNGEONSFOREVER1 = "/df"
SLASH_DUNGEONSFOREVER2 = L["/副本手册"]
SLASH_DUNGEONSFOREVER3 = "/fbsc"
local PAGE_ALIASES = {
    fb = "Dungeons",    ["副本"] = "Dungeons",
    tb = "Raids",       ["团本"] = "Raids",
    zy = "Professions", ["专业"] = "Professions",
    ts = "Explore",     ["探索"] = "Explore",
    bis = "Bis",        ["配装"] = "Bis",
    zn = "Tier",        ["指南"] = "Tier",
}
SlashCmdList["DUNGEONSFOREVER"] = function(msg)
    local cmd = strtrim(msg or "")
    if cmd == "" then
        ns.Toggle()
        return
    end
    local key = PAGE_ALIASES[cmd:lower()]
    if key then
        if not ns.IsForever and key ~= "Dungeons" and key ~= "Raids" then
            print("|cff46bf72[" .. L["无限副本手册"] .. "]|r " .. L["该页面仅无限服可用，已为你打开副本页。"])
            key = "Dungeons"
        end
        ns.OpenPage(key)
        return
    end
    print("|cff46bf72[" .. L["无限副本手册"] .. "]|r " .. L["用法：/df 或 /fbsc 打开或关闭界面。"])
    print("  /df fb|副本 · tb|团本 · zy|专业 · ts|探索 · bis|配装 · zn|指南 — " .. L["直达对应页"])
    -- ★ 2026-10-03 第五刀：载入闸门的速度档位（省电 2ms / 标准 4ms / 激进 8ms）。
    --   电脑差的用户不必猜命令 —— /df 就把它列出来。
    print("  /dfspeed — " .. L["载入速度"]
          .. "（" .. L["省电"] .. " / " .. L["标准"] .. " / " .. L["激进"] .. "）")
    -- ★ 2026-10-03：进度条自检 / 演示（它只在真的有活时才亮，好电脑上平时看不到）
    print("  /dfgate — " .. L["进度条"] .. "（demo / off）")
end
