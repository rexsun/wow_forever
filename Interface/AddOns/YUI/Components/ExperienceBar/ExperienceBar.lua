local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI or not (YUI.IsForever or YUI.IsRetail) or not YUI.Components or not YUI.GUI2 then return end
local Components, GUI2, Model = YUI.Components, YUI.GUI2, YUI.ExperienceBarModel
local L = YUI.Locale:Get("ExperienceBar")
local PRODUCT = YUI:GetAddonProductId(ADDON_NAME, "suite") or "suite"
local KEY, LAYOUT, MODULE = "ExperienceBar", "yui.component.experiencebar", "component.experiencebar"
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local Native = YUI.API and YUI.API.BlizzardUI
local defaults = {
    layout = "left", ring = "fineSilver", width = 400, diameter = 48, height = 20,
    font = "默认", outline = "OUTLINE", shadow = true,
    textStyle = "outlineShadow", detailFont = "默认", detailTextStyle = "none",
    levelSize = 20, barSize = 14, detailSize = 14, barTextOffsetY = 16,
    levelTextOffsetX = 0, levelTextOffsetY = 0,
    levelColor = { 1, 0.85, 0.52, 1 }, barColor = { 1, 1, 1, 1 }, detailColor = { 239/255, 239/255, 239/255, 1 },
    texture = " |cFFFF00FFY|r|cFFFF6666U|r|cFFFF9900I|r |CFFBA55D3Solid|r", gradient = false, vertical = false,
    startColor = { 167/255, 76/255, 235/255, 1 }, endColor = { 167/255, 76/255, 235/255, 1 },
    backgroundColor = { 0.055, 0.047, 0.067, 1 },
    borderColor = { 0.32, 0.34, 0.38, 1 },
    hideMax = true, hideNative = true, showPercent = true, showETA = true,
    hoverEnabled = true, pinEnabled = true, showCompleted = true,
    showRested = true, restedColor = { 44/255, 146/255, 235/255, 1 }, questColor = { 244/255, 139/255, 52/255, 1 },
    restedGradient = false, restedVertical = false, restedEndColor = { 44/255, 146/255, 235/255, 1 },
    questGradient = false, questVertical = false, questEndColor = { 244/255, 139/255, 52/255, 1 },
    details = { xp = true, remaining = true, rate = true, rested = true,
        completed = true, incomplete = true, projected = true,
        levelTime = true, sessionTime = true, gained = true },
}
-- Client-native regions: FDID, UV bounds, aspect ratio and interior radius.
local rings = {
    thin = { 4417031, 1440/2048, 1723/2048, 0/2048, 283/2048, 283/283, 0.46 },
    services = { 1146909, 259/1024, 333/1024, 868.5/1024, 942.5/1024, 74/74.0, 0.43 },
    portrait = { 1729779, 5/256, 183/256, 5.5/256, 183.5/256, 178/178.0, 0.45 },
    faceted = { 4417031, 271/2048, 398/2048, 529/2048, 658/2048, 127/129, 0.35 },
    medal = { 1114519, 623/1024, 740/1024, 574/1024, 686/1024, 117/112, 0.4 },
    stable = { 5551744, 1468/2048, 1604/2048, 24/2048, 160/2048, 136/136, 0.43 },
    journeys = { 7486942, 54/2048, 167/2048, 216/2048, 329/2048, 113/113, 0.4 },
    fineSilver = { 4417031, 405/2048, 475/2048, 528/2048, 601/2048, 70/73, 0.45 },
    islandRing = { 2053904, 130/2048, 188/2048, 393/512, 455/512, 58/62, 0.4 },
    challengeRing = { 1061072, 0/1024, 64/1024, 434/512, 500/512, 64/66, 0.44 },
    braid = { 1114519, 265/1024, 344/1024, 885/1024, 964/1024, 79/79, 0.36 },
    laurel = { 1114519, 0/1024, 95/1024, 812/1024, 909/1024, 95/97, 0.29 },
    runic = { 1114519, 508/1024, 622/1024, 320/1024, 435/1024, 114/115, 0.29 },
    arcane = { 1114519, 248/1024, 371/1024, 75/1024, 195/1024, 123/120, 0.28 },
    gear = { 1114519, 745/1024, 864/1024, 691/1024, 807/1024, 119/116, 0.28 },
    cross = { 1114519, 0/1024, 122/1024, 687/1024, 812/1024, 122/125, 0.29 },
    frost = { 1114519, 0/1024, 121/1024, 572/1024, 691/1024, 121/119, 0.27 },
}
local ringOrder = { "thin", "services", "portrait", "faceted", "medal", "stable", "journeys", "fineSilver", "islandRing", "challengeRing", "braid", "laurel", "runic", "arcane", "gear", "cross", "frost" }

local layouts = { left = true, right = true, center = true, plain = true }
local detailKeys = { "xp", "remaining", "rate", "rested", "completed", "incomplete", "projected", "levelTime", "sessionTime", "gained" }
local owner, state = {}, {}
local active, preview, pinned, hovering = false, false, false, false
local frame, track, fill, badge, ring, levelText, percentText, etaText, panel, hint
local prediction
local secondFill, secondPrediction
local restedOverlay, secondRestedOverlay
local colorPreview = false
local previewStats = { xp = 210000, maximum = 600000, gained = 36000, started = 0, levelSeconds = 2400, levelTimeAt = 720 }
local dragging, suppressClick = false, false
local well, backing, secondTrack, secondWell
local rows = {}
local detailGroups = { { "xp", "remaining", "rested" }, { "completed", "incomplete", "projected" }, { "rate", "gained", "sessionTime", "levelTime" } }
local separators = {}
local joins = {}
local db, pending, leaveTimer, timeTimer
local enteredWorld = false
local etaRefreshNeeded = false
local questsDirty, completed, incomplete = true, nil, nil
local refreshCount, eventCount, listeners = 0, 0, 0
local Render, ApplyAppearance, SyncTimeRefresh

local function Now() return GetTime() end
local function Config()
    local config = Components:EnsureConfig("ExperienceBar_Config", defaults, PRODUCT)
    config.layout = layouts[config.layout] and config.layout or defaults.layout
    config.ring = rings[config.ring] and config.ring or defaults.ring
    config.levelSize = math.max(12, math.min(36, tonumber(config.levelSize) or defaults.levelSize))
    config.levelTextOffsetX = math.max(-40, math.min(40, tonumber(config.levelTextOffsetX) or defaults.levelTextOffsetX))
    config.levelTextOffsetY = math.max(-40, math.min(40, tonumber(config.levelTextOffsetY) or defaults.levelTextOffsetY))
    config.barSize = math.max(9, math.min(22, tonumber(config.barSize) or defaults.barSize))
    config.barTextOffsetY = math.max(-20, math.min(20, tonumber(config.barTextOffsetY) or defaults.barTextOffsetY))
    config.detailSize = math.max(9, math.min(20, tonumber(config.detailSize) or defaults.detailSize))
    if config.outline ~= "" and config.outline ~= "OUTLINE" and config.outline ~= "THICKOUTLINE" then config.outline = "OUTLINE" end
    config.width = math.max(300, math.min(700, tonumber(config.width) or defaults.width))
    config.diameter = math.max(36, math.min(80, tonumber(config.diameter) or defaults.diameter))
    config.height = math.max(4, math.min(64, tonumber(config.height) or defaults.height))
    for _, key in ipairs({ "startColor", "endColor", "backgroundColor", "borderColor", "levelColor", "barColor", "detailColor", "restedColor", "questColor", "restedEndColor", "questEndColor" }) do
        if type(config[key]) ~= "table" then config[key] = {} end
        for i = 1, 4 do config[key][i] = math.max(0, math.min(1, tonumber(config[key][i]) or defaults[key][i])) end
    end
    if not config.textStyle then
        config.textStyle = config.outline == "THICKOUTLINE" and "thick"
            or config.outline == "OUTLINE" and (config.shadow and "outlineShadow" or "outline")
            or (config.shadow and "shadow" or "none")
    end
    config.detailFont = config.detailFont or config.font
    config.detailTextStyle = config.detailTextStyle or config.textStyle
    if type(config.details) ~= "table" then config.details = {} end
    return config
end

local function CancelTimers()
    if pending then pending:Cancel(); pending = nil end
    if leaveTimer then leaveTimer:Cancel(); leaveTimer = nil end
    if timeTimer then timeTimer:Cancel(); timeTimer = nil end
end

local function Text(region, value)
    if region:GetText() ~= value then region:SetText(value) end
end

local function Number(value)
    if not value then return "—" end
    local text = string.format("%.0f", math.floor(value + 0.5))
    return (text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function Tint(text, color, brightness)
    brightness = brightness or 1
    return string.format("|cff%02x%02x%02x%s|r", math.floor(color[1] * brightness * 255 + 0.5),
        math.floor(color[2] * brightness * 255 + 0.5), math.floor(color[3] * brightness * 255 + 0.5), text)
end

local function Percent(value, plus, maximum)
    maximum = maximum or state.maximum
    if not value or not maximum or maximum <= 0 then return "" end
    return string.format(plus and "+%.1f%%" or "%.1f%%", value / maximum * 100)
end

local function WithPercent(value, plus, maximum, color, prefix)
    local percent = Percent(value, plus, maximum)
    return (prefix or Number(value)) .. (percent ~= "" and Tint("（" .. percent .. "）", color or db.detailColor) or "")
end

local function Duration(seconds, roundUp)
    if not seconds then return "—" end
    local minutes = math.max(0, roundUp and math.ceil(seconds / 60) or math.floor(seconds / 60))
    if minutes < 60 then return string.format(L["time.minutes"], minutes) end
    return string.format(L["time.hoursMinutes"], math.floor(minutes / 60), minutes % 60)
end

local function ScanQuests()
    questsDirty = false
    completed, incomplete = nil, nil
    if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries or not C_QuestLog.GetInfo
        or not C_QuestLog.IsComplete or not GetQuestLogRewardXP then return end
    local count = Model.ReadNumber(C_QuestLog.GetNumQuestLogEntries)
    if not count then return end
    local done, todo = 0, 0
    for index = 1, math.min(count, 200) do
        local info = C_QuestLog.GetInfo(index)
        if info and not info.isHeader and info.questID then
            local reward = Model.ReadNumber(GetQuestLogRewardXP, info.questID)
            if not reward then return end
            local isComplete = C_QuestLog.IsComplete(info.questID)
            if issecretvalue and issecretvalue(isComplete) then return end
            if isComplete then done = done + reward else todo = todo + reward end
        end
    end
    completed, incomplete = done, todo
end

local function SetDetails(show)
    if panel then panel:SetShown((show or colorPreview) and frame:IsShown()) end
    if SyncTimeRefresh then SyncTimeRefresh() end
end

local function OnTimeRefresh()
    timeTimer = nil
    if active then Render() end
end

SyncTimeRefresh = function()
    local detailTime = panel and panel:IsShown() and (db.details.rate or db.details.levelTime or db.details.sessionTime)
    local needed = active and frame and frame:IsShown() and not preview and not colorPreview
        and ((db.showETA and etaRefreshNeeded) or detailTime)
    if needed and not timeTimer then timeTimer = C_Timer.NewTimer(60, OnTimeRefresh)
    elseif not needed and timeTimer then timeTimer:Cancel(); timeTimer = nil end
end

local function SessionStore()
    local database = YUI.DB and YUI.DB:GetAceDB(PRODUCT)
    return database and database.char
end

local function FinishLeave()
    leaveTimer = nil
    if not hovering and not pinned then SetDetails(false) end
end

local function Enter()
    hovering = true
    if leaveTimer then leaveTimer:Cancel(); leaveTimer = nil end
    if (active or preview) and (db.hoverEnabled or pinned) then Render(); SetDetails(true) end
end

local function Leave()
    hovering = false
    if leaveTimer then leaveTimer:Cancel() end
    leaveTimer = C_Timer.NewTimer(0.2, FinishLeave)
end

local function OpenSettings()
    if YUI.Settings and YUI.Settings.OpenComponentFeature then YUI.Settings:OpenComponentFeature(KEY) end
end

local function Click(_, button)
    if suppressClick then suppressClick = false; return end
    if button == "RightButton" then OpenSettings(); return end
    if not db.pinEnabled and not pinned then return end
    pinned = not pinned
    Render()
    SetDetails(pinned or (hovering and db.hoverEnabled))
end

local function StopPreviewDrag(cancel)
    if not dragging then return end
    dragging = false
    if YUI.Layout then YUI.Layout:EndDirectDrag(cancel) end
end

local function StartPreviewDrag()
    local layout = YUI.Layout
    if not colorPreview or not layout or not layout.BeginDirectDrag
        or not layout:IsPlacementReady(LAYOUT) then return end
    dragging = layout:BeginDirectDrag(LAYOUT, { snap = false }) == true
    if dragging then suppressClick = true end
end

local function DefaultPlacement()
    return { version = 1, anchor = { point = "TOPLEFT", relative = "UIParent", relativePoint = "TOPLEFT" }, offset = { x = 2, y = -40 } }
end

local function EnsureFrame()
    if frame then return end
    if not state.started then Model.Reset(state, Now()) end
    frame = GUI2:CreateFrame(UIParent, { type = "Button", name = "YUIExperienceBar", strata = "MEDIUM" })
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 2, -40)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", StartPreviewDrag)
    frame:SetScript("OnDragStop", function() StopPreviewDrag(false) end)
    frame:SetScript("OnHide", function() StopPreviewDrag(true) end)
    frame:SetScript("OnEnter", Enter)
    frame:SetScript("OnLeave", Leave)
    frame:SetScript("OnClick", Click)
    track = GUI2:CreateFrame(frame, { template = "BackdropTemplate" })
    GUI2:CreateBorder(track, "color.border.default")
    track.gui2Borders.widthPixels = 1
    track:UpdateGUI2PixelScale()
    well = GUI2:CreateTexture(track, { layer = "BACKGROUND" })
    well:SetPoint("CENTER", track, "CENTER")
    secondTrack = GUI2:CreateFrame(frame, { template = "BackdropTemplate" })
    GUI2:CreateBorder(secondTrack, "color.border.default")
    secondTrack.gui2Borders.widthPixels = 1
    secondTrack:UpdateGUI2PixelScale()
    secondWell = GUI2:CreateTexture(secondTrack, { layer = "BACKGROUND" })
    secondWell:SetPoint("CENTER", secondTrack, "CENTER")
    fill = CreateFrame("StatusBar", nil, track)
    fill:SetMinMaxValues(0, 1)
    restedOverlay = GUI2:CreateTexture(fill, { layer = "OVERLAY", subLevel = 1 })
    restedOverlay:Hide()
    prediction = GUI2:CreateTexture(fill, { layer = "OVERLAY" })
    prediction:SetColorTexture(0.92, 0.72, 0.30, 0.40)
    prediction:Hide()
    secondFill = CreateFrame("StatusBar", nil, secondTrack)
    secondFill:SetMinMaxValues(0, 1)
    secondRestedOverlay = GUI2:CreateTexture(secondFill, { layer = "OVERLAY", subLevel = 1 })
    secondRestedOverlay:Hide()
    secondPrediction = GUI2:CreateTexture(secondFill, { layer = "OVERLAY" })
    secondPrediction:SetColorTexture(0.92, 0.72, 0.30, 0.40)
    secondPrediction:Hide()
    for index, bar in ipairs({ fill, secondFill }) do
        local join = {}
        joins[index] = join
        for layer = 1, 3 do
            join[layer] = GUI2:CreateTexture(bar, { layer = "ARTWORK", subLevel = layer - 1 })
            GUI2:ApplyTexturePixelPolicy(join[layer])
        end
    end
    badge = GUI2:CreateFrame(frame, { level = fill:GetFrameLevel() + 2 })
    backing = GUI2:CreateTexture(badge, { layer = "BACKGROUND" })
    backing:SetColorTexture(0.055, 0.047, 0.067, 1)
    -- Only the interior is backed; ornamental silhouettes retain their alpha.
    backing:SetPoint("CENTER", badge, "CENTER")
    local mask = badge:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(backing)
    backing:AddMaskTexture(mask)
    ring = GUI2:CreateTexture(badge, { layer = "ARTWORK" })
    ring:SetPoint("CENTER", badge, "CENTER")
    levelText = GUI2:CreateText(badge, "", 22)
    levelText:SetPoint("CENTER")
    levelText:SetTextColor(1, 0.85, 0.52)
    percentText = GUI2:CreateText(fill, "", 12)
    etaText = GUI2:CreateText(fill, "", 12)
    panel = GUI2:CreateFrame(frame, { type = "Button", template = "BackdropTemplate", strata = "TOOLTIP" })
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    panel:SetBackdropColor(0.045, 0.04, 0.065, 0.97)
    panel:SetBackdropBorderColor(0.55, 0.46, 0.31, 1)
    panel:SetWidth(300)
    panel:EnableMouse(true)
    panel:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    panel:SetScript("OnEnter", Enter)
    panel:SetScript("OnLeave", Leave)
    panel:SetScript("OnClick", Click)
    for _, key in ipairs(detailKeys) do
        local label = GUI2:CreateText(panel, L["detail." .. key], 12)
        local value = GUI2:CreateText(panel, "", 12)
        rows[key] = { label = label, value = value }
    end
    for index = 1, 2 do
        separators[index] = GUI2:CreateTexture(panel, { layer = "ARTWORK" })
    end
    local help = GUI2:CreateFrame(panel, {})
    help:SetPoint("TOPLEFT", rows.levelTime.label, "TOPLEFT")
    help:SetPoint("BOTTOMRIGHT", rows.levelTime.label, "BOTTOMRIGHT")
    help:EnableMouse(true)
    help:SetScript("OnEnter", function()
        Enter()
        if GameTooltip then
            GameTooltip:SetOwner(help, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["detail.levelTime.help"], 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    help:SetScript("OnLeave", function()
        if GameTooltip and GameTooltip:IsOwned(help) then YUI.HideGameTooltip() end
        Leave()
    end)
    help:SetScript("OnHide", function()
        if GameTooltip and GameTooltip:IsOwned(help) then YUI.HideGameTooltip() end
    end)
    rows.levelTime.help = help
    hint = GUI2:CreateText(panel, "", 11)
    hint:SetPoint("BOTTOM", 0, 10)
    panel:Hide()
    if YUI.Layout then
        YUI.Layout:RegisterFrame(LAYOUT, {
            frame = frame, title = L["name"], category = "component",
            defaultPlacement = DefaultPlacement, movable = true, snap = true, anchorTargets = { "UIParent" },
            isEnabled = function() return active or preview or colorPreview end,
            onEnterEditMode = function() preview = true; Render() end,
            onExitEditMode = function() preview = false; Render() end,
            openPluginSettings = OpenSettings,
        })
    end
end

local forecastColors = {}

local function PaintTexture(texture, a, b, first, last, vertical)
    texture:SetVertexColor(1, 1, 1, 1)
    if texture.SetGradient and CreateColor then
        if vertical then first, last = 0, 1 end
        texture:SetGradient(vertical and "VERTICAL" or "HORIZONTAL",
            CreateColor(a[1]+(b[1]-a[1])*first, a[2]+(b[2]-a[2])*first, a[3]+(b[3]-a[3])*first, a[4]+(b[4]-a[4])*first),
            CreateColor(a[1]+(b[1]-a[1])*last, a[2]+(b[2]-a[2])*last, a[3]+(b[3]-a[3])*last, a[4]+(b[4]-a[4])*last))
    else
        texture:SetVertexColor(a[1], a[2], a[3], a[4])
    end
end

local function PaintFill(bar, first, last)
    PaintTexture(bar:GetStatusBarTexture(), db.startColor, db.gradient and db.endColor or db.startColor, first, last, db.vertical)
end

local function StyleText(region, size, color, detail)
    local fallback = GUI2.GetFont and GUI2:GetFont("font.family.body") or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local fontKey = detail and db.detailFont or db.font
    local font = fontKey ~= "default" and LSM and LSM:Fetch("font", fontKey, true) or fallback
    if fontKey == "chat" then font = ChatFontNormal and select(1, ChatFontNormal:GetFont()) or fallback end
    if fontKey == "damage" then font = DAMAGE_TEXT_FONT or fallback end
    local style = detail and db.detailTextStyle or db.textStyle
    local flags = style == "thick" and "THICKOUTLINE" or (style == "outline" or style == "outlineShadow") and "OUTLINE" or ""
    local shadow = style == "shadow" or style == "outlineShadow"
    if region:SetFont(font, size, flags) == false then region:SetFont(fallback, size, flags) end
    -- This component owns configured colors; theme refresh must not overwrite them.
    region.gui2ColorKey = nil
    region:SetTextColor(color[1], color[2], color[3], color[4])
    region:SetShadowColor(0, 0, 0, shadow and 1 or 0)
    region:SetShadowOffset(shadow and 1 or 0, shadow and -1 or 0)
end

ApplyAppearance = function()
    db = Config()
    forecastColors.rested = { db.restedColor, db.restedGradient and db.restedEndColor or db.restedColor, db.restedVertical }
    forecastColors.quest = { db.questColor, db.questGradient and db.questEndColor or db.questColor, db.questVertical }
    EnsureFrame()
    local plain = db.layout == "plain"
    local asset = rings[db.ring]
    local pixel = GUI2:GetPixelSize(track, 1, 1)
    local diameter, center, start, width, secondStart = Model.JoinGeometry(db.layout, db.width, db.diameter, db.height, asset[7], pixel)
    frame:SetSize(db.width, plain and db.height or math.max(db.height, diameter))
    local split = db.layout == "center"
    track:ClearAllPoints()
    track:SetPoint("LEFT", frame, "LEFT", start, 0)
    track:SetSize(width, db.height)
    well:SetSize(width - 2 * pixel, db.height - 2 * pixel)
    secondTrack:ClearAllPoints()
    secondTrack:SetPoint("LEFT", frame, "LEFT", secondStart, 0)
    secondTrack:SetSize(width, db.height)
    secondTrack:SetShown(split)
    secondWell:SetSize(width - 2 * pixel, db.height - 2 * pixel)
    local bg = db.backgroundColor
    well:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
    secondWell:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
    local border = db.borderColor
    GUI2:SetBorderColor(track, border[1], border[2], border[3], border[4])
    GUI2:SetBorderColor(secondTrack, border[1], border[2], border[3], border[4])
    badge:ClearAllPoints()
    badge:SetPoint("CENTER", frame, "LEFT", center, 0)
    badge:SetSize(diameter, diameter)
    badge:SetShown(not plain)
    local ratio = asset[6]
    ring:SetSize(diameter * math.min(1, ratio), diameter / math.max(1, ratio))
    backing:SetSize(diameter * asset[7] * 2, diameter * asset[7] * 2)
    ring:SetTexture(asset[1])
    ring:SetTexCoord(asset[2], asset[3], asset[4], asset[5])
    local path = LSM and LSM:Fetch("statusbar", db.texture, true)
    fill:SetStatusBarTexture(path or "Interface\\TargetingFrame\\UI-StatusBar")
    secondFill:SetStatusBarTexture(path or "Interface\\TargetingFrame\\UI-StatusBar")
    GUI2:ApplyTexturePixelPolicy(fill:GetStatusBarTexture())
    GUI2:ApplyTexturePixelPolicy(secondFill:GetStatusBarTexture())
    for _, overlay in ipairs({ prediction, secondPrediction, restedOverlay, secondRestedOverlay }) do
        overlay:SetTexture(path or "Interface\\TargetingFrame\\UI-StatusBar")
        GUI2:ApplyTexturePixelPolicy(overlay)
    end
    fill:ClearAllPoints()
    secondFill:ClearAllPoints()
    -- The background overlaps the badge, but progress uses only unobscured pixels.
    local extent = diameter * math.min(1, ratio) / 2 + pixel
    local leftInset = db.layout == "left" and math.max(0, center + extent - start - pixel) or 0
    local rightInset = (db.layout == "right" or split) and math.max(0, start + width - pixel - center + extent) or 0
    local secondInset = split and math.max(0, center + extent - secondStart - pixel) or 0
    fill:SetPoint("TOPLEFT", well, "TOPLEFT", leftInset, 0)
    fill:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -rightInset, 0)
    secondFill:SetPoint("TOPLEFT", secondWell, "TOPLEFT", secondInset, 0)
    secondFill:SetPoint("BOTTOMRIGHT", secondWell, "BOTTOMRIGHT", 0, 0)
    secondFill:SetShown(split)
    -- Extend the edge sample under the badge without counting occluded pixels as XP.
    for index, join in ipairs(joins) do
        local bar, background = index == 1 and fill or secondFill, index == 1 and well or secondWell
        local atLeft = index == 2 or db.layout == "left"
        join.enabled = not plain and (index == 1 or split)
        join.atLeft = atLeft
        join.edge = atLeft and (index == 2 and 0.5 or 0) or (split and 0.5 or 1)
        for layer, texture in ipairs(join) do
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", atLeft and background or bar, atLeft and "TOPLEFT" or "TOPRIGHT")
            texture:SetPoint("BOTTOMRIGHT", atLeft and bar or background, atLeft and "BOTTOMLEFT" or "BOTTOMRIGHT")
            texture:SetTexture(path or "Interface\\TargetingFrame\\UI-StatusBar")
            local u = atLeft and 0 or 1
            texture:SetTexCoord(u, u, 0, 1)
            if layer == 1 then
                PaintFill({ GetStatusBarTexture = function() return texture end }, join.edge, join.edge)
            else
                local colors = layer == 2 and forecastColors.quest or forecastColors.rested
                PaintTexture(texture, colors[1], colors[2], join.edge, join.edge, colors[3])
            end
        end
    end
    percentText:ClearAllPoints()
    etaText:ClearAllPoints()
    local radius = diameter / 2
    if db.layout == "center" then
        percentText:SetPoint("CENTER", frame, "LEFT", (db.width / 2 - radius) / 2, db.barTextOffsetY)
        etaText:SetPoint("CENTER", frame, "RIGHT", -(db.width / 2 - radius) / 2, db.barTextOffsetY)
    else
        percentText:SetPoint("LEFT", fill, "LEFT", 8, db.barTextOffsetY)
        etaText:SetPoint("RIGHT", fill, "RIGHT", -8, db.barTextOffsetY)
    end
    StyleText(levelText, db.levelSize, db.levelColor)
    levelText:ClearAllPoints()
    levelText:SetPoint("CENTER", badge, "CENTER", db.levelTextOffsetX, db.levelTextOffsetY)
    StyleText(percentText, db.barSize, db.barColor)
    StyleText(etaText, db.barSize, db.barColor)
    for _, row in pairs(rows) do
        StyleText(row.label, db.detailSize, db.detailColor, true)
        StyleText(row.value, db.detailSize, db.detailColor, true)
    end
    StyleText(hint, math.max(9, db.detailSize - 1), db.detailColor, true)
    PaintFill(fill, 0, split and 0.5 or 1)
    PaintFill(secondFill, 0.5, 1)
    if YUI.Layout then YUI.Layout:RefreshFrame(LAYOUT) end
end

local function FillDetails(now, rate, eta, rested)
    local state = colorPreview and previewStats or state
    local y = -14
    local contentWidth = 272
    local wantsQuests = db.details.completed or db.details.incomplete or db.details.projected
    if wantsQuests and questsDirty and not colorPreview then ScanQuests() end
    local completed, incomplete = completed, incomplete
    if colorPreview then now, rate, rested, completed, incomplete = 720, 180000, 120000, 240000, 90000 end
    local groupsShown = 0
    for _, separator in ipairs(separators) do separator:Hide() end
    for _, group in ipairs(detailGroups) do
        local groupShown = false
        for _, key in ipairs(group) do
            local row = rows[key]
            local show = colorPreview or db.details[key] == true
            row.label:SetShown(show); row.value:SetShown(show)
            if row.help then row.help:SetShown(show) end
            if show then
                if not groupShown then
                    if groupsShown > 0 then
                        local separator = separators[groupsShown]
                        separator:ClearAllPoints()
                        separator:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y - 2)
                        separator:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, y - 2)
                        separator:SetHeight(GUI2:GetPixelSize(panel, 1, 1))
                        separator:SetColorTexture(db.detailColor[1], db.detailColor[2], db.detailColor[3], 0.16)
                        separator:Show()
                        y = y - 12
                    end
                    groupsShown, groupShown = groupsShown + 1, true
                end
                local value
                if key == "xp" then value = WithPercent(state.xp, false, state.maximum, db.startColor,
                    Number(state.xp) .. " / " .. Number(state.maximum))
                elseif key == "remaining" then value = WithPercent(state.xp and state.maximum - state.xp, false, state.maximum)
                elseif key == "rate" then
                    value = rate and string.format(L["perHour"], Number(rate)) or L["sampling"]
                    if rate and now - state.started < 300 then value = value .. Tint(" · " .. L["sampling"], db.detailColor) end
                elseif key == "rested" then value = WithPercent(rested, false, state.maximum, db.restedColor)
                elseif key == "completed" then value = WithPercent(completed, true, state.maximum, db.questColor)
                elseif key == "incomplete" then value = WithPercent(incomplete, true, state.maximum)
                elseif key == "projected" then value = state.xp and completed
                    and Percent(state.xp, false, state.maximum) .. " → " .. Tint(Percent(state.xp + completed, false, state.maximum), db.questColor) or "—"
                elseif key == "levelTime" then value = state.levelSeconds and Duration(state.levelSeconds + now - state.levelTimeAt) or L["detail.unavailable"]
                elseif key == "sessionTime" then value = Duration(now - state.started)
                elseif key == "gained" then value = Number(state.gained) end
                local color = db.detailColor
                row.value:SetTextColor(color[1], color[2], color[3], 1)
                row.label:ClearAllPoints(); row.value:ClearAllPoints()
                row.label:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)
                row.value:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, y)
                Text(row.value, value)
                contentWidth = math.max(contentWidth, row.label:GetStringWidth() + row.value:GetStringWidth() + 24)
                y = y - db.detailSize - 8
            end
        end
    end
    Text(hint, (colorPreview and L["preview.short"] or pinned and L["unpin"] or L["pin"]) .. "\n" .. L["rightClick"])
    contentWidth = math.max(contentWidth, hint:GetStringWidth())
    panel:SetHeight(-y + 18 + 2 * math.max(9, db.detailSize - 1))
    panel:SetWidth(contentWidth + 28)
    panel:ClearAllPoints()
    local below = not frame:GetBottom() or frame:GetBottom() > panel:GetHeight() + 12
    local anchor = db.layout == "right" and "RIGHT" or db.layout == "center" and "" or "LEFT"
    panel:SetPoint((below and "TOP" or "BOTTOM") .. anchor, frame, (below and "BOTTOM" or "TOP") .. anchor, 0, below and -4 or 4)
end

local function ShowSegment(bar, overlay, fraction, predicted, index, split)
    local _, value = Model.SegmentRange(0, fraction, index, split)
    local width = bar:GetWidth()
    -- Keep tiny nonzero XP visible without changing its reported numeric value.
    if value > 0 and width > 0 then value = math.min(1, math.max(value, GUI2:GetPixelSize(bar, 1, 1) / width)) end
    if bar:GetValue() ~= value then bar:SetValue(value) end
    -- A zero-valued bar may retain a full texture after material/layout changes.
    -- Hide only the actual fill, keeping independent forecast regions available.
    local texture = bar:GetStatusBarTexture()
    texture:SetTexCoord(0, value, 0, 1)
    if texture:IsShown() ~= (value > 0) then texture:SetShown(value > 0) end
    local first, last = Model.SegmentRange(fraction, math.min(1, fraction + predicted), index, split)
    first = math.max(first, value)
    overlay:SetShown(last > first and width > 0)
    if last > first and width > 0 then
        overlay:ClearAllPoints()
        local edge = value > 0 and texture or bar
        local top, bottom = value > 0 and "TOPRIGHT" or "TOPLEFT", value > 0 and "BOTTOMRIGHT" or "BOTTOMLEFT"
        overlay:SetPoint("TOPLEFT", edge, top, 0, 0)
        overlay:SetPoint("BOTTOMLEFT", edge, bottom, 0, 0)
        overlay:SetWidth(width * (last - first))
        overlay:SetTexCoord(first, last, 0, 1)
        local colors = (overlay == restedOverlay or overlay == secondRestedOverlay) and forecastColors.rested or forecastColors.quest
        local offset, scale = split and (index - 1) * 0.5 or 0, split and 0.5 or 1
        PaintTexture(overlay, colors[1], colors[2], offset + first * scale, offset + last * scale, colors[3])
    end
end

Render = function()
    if not frame then return end
    if not active and not preview and not colorPreview then frame:Hide(); panel:Hide(); return end
    local now = Now()
    local level = Model.ReadNumber(UnitLevel, "player")
    local xp = Model.ReadNumber(UnitXP, "player")
    local maximum = Model.ReadNumber(UnitXPMax, "player")
    local valid = Model.Sample(state, now, level, xp, maximum)
    local maxLevel = Model.ReadNumber(GameRulesUtil and GameRulesUtil.GetEffectiveMaxLevelForPlayer) or Model.ReadNumber(GetMaxPlayerLevel)
    local atMax = level and maxLevel and level >= maxLevel
    local locked = IsXPUserDisabled and IsXPUserDisabled()
    if issecretvalue and issecretvalue(locked) then locked = false end
    etaRefreshNeeded = valid and not locked and not atMax
    local shown = preview or colorPreview or not (db.hideMax and atMax)
    frame:SetShown(shown)
    if not shown then panel:Hide(); pinned = false; hovering = false; SyncTimeRefresh(); return end
    local rate, eta = Model.Estimate(state, now, locked)
    local fraction = valid and state.xp / state.maximum or 0
    if preview and (not valid or atMax) then fraction = 0.482 end
    if colorPreview then fraction = 0.35 end
    Text(levelText, Number(colorPreview and (level or 88) or level))
    local rested = Model.ReadNumber(GetXPExhaustion) or 0
    local percent = (colorPreview or valid or preview) and string.format("%.1f%%", fraction * 100) or "—"
    if colorPreview or (db.showRested and valid and rested > 0) then
        local r = db.restedColor
        percent = percent .. string.format(" |cff%02x%02x%02x(+%.1f%%)|r",
            math.floor(r[1] * 255 + 0.5), math.floor(r[2] * 255 + 0.5), math.floor(r[3] * 255 + 0.5),
            colorPreview and 20 or rested / maximum * 100)
    end
    if not db.showPercent and not colorPreview then percent = "" end
    if db.layout == "plain" then percent = string.format(L["level"], Number(level)) .. "  ·  " .. percent end
    Text(percentText, percent)
    local estimate = eta and Duration(eta, true)
    if eta and now - state.started < 300 then
        estimate = eta >= 3600 and string.format(L["time.hours"], math.floor(eta / 3600 + 0.5)) or estimate
        estimate = string.format(L["eta.early"], estimate)
    elseif eta then estimate = string.format(L["eta"], estimate) end
    if colorPreview then estimate = string.format(L["eta"], Duration(7800, true)) end
    Text(etaText, estimate or "")
    etaText:SetShown(colorPreview or (db.showETA and eta ~= nil and not atMax))
    if db.showCompleted and questsDirty then ScanQuests() end
    local predicted = db.showCompleted and valid and completed and math.min(1 - fraction, completed / maximum) or 0
    local restedFraction = db.showRested and valid and math.min(1 - fraction, rested / maximum) or 0
    if colorPreview then predicted, restedFraction = 0.40, 0.20 end
    for _, join in ipairs(joins) do
        local edge = join.edge
        local normal = fraction > 0 and (fraction > edge or not join.atLeft and fraction == edge)
        join[1]:SetShown(join.enabled and normal)
        join[2]:SetShown(join.enabled and not normal and predicted > 0 and fraction <= edge
            and (fraction + predicted > edge or not join.atLeft and fraction + predicted == edge))
        join[3]:SetShown(join.enabled and not normal and restedFraction > 0 and fraction <= edge
            and (fraction + restedFraction > edge or not join.atLeft and fraction + restedFraction == edge))
    end
    ShowSegment(fill, restedOverlay, fraction, restedFraction, 1, db.layout == "center")
    if db.layout == "center" then ShowSegment(secondFill, secondRestedOverlay, fraction, restedFraction, 2, true) end
    ShowSegment(fill, prediction, fraction, predicted, 1, db.layout == "center")
    if db.layout == "center" then ShowSegment(secondFill, secondPrediction, fraction, predicted, 2, true) end
    if colorPreview or pinned or (hovering and db.hoverEnabled) then
        FillDetails(now, rate, eta, rested)
        SetDetails(true)
    end
    refreshCount = refreshCount + 1
    SyncTimeRefresh()
end

local function Flush()
    pending = nil
    if active then Render() end
end

local function QueueRefresh()
    if not active or pending then return end
    pending = C_Timer.NewTimer(0.05, Flush)
end

local function OnEvent(event, arg1, arg2)
    eventCount = eventCount + 1
    if event == "PLAYER_LOGOUT" then
        local store = SessionStore()
        if store then store.experienceBarSession = Model.Save(state, Now()) end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" and not enteredWorld then
        enteredWorld = true
        local store = SessionStore()
        if arg2 == true and store then Model.Restore(state, store.experienceBarSession, Now()) end
        if store then store.experienceBarSession = nil end
    end
    if event == "TIME_PLAYED_MSG" then
        local seconds = Model.Number(arg2)
        if seconds then state.levelSeconds, state.levelTimeAt = seconds, Now() end
    end
    if event == "QUEST_LOG_UPDATE" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_ENTERING_WORLD" then questsDirty = true end
    if Native and db.hideNative and (event == "PLAYER_ENTERING_WORLD" or event == "ADDON_LOADED") then Native:Refresh() end
    QueueRefresh()
end

local events = { "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "QUEST_LOG_UPDATE", "TIME_PLAYED_MSG", "ENABLE_XP_GAIN", "DISABLE_XP_GAIN", "ADDON_LOADED", "PLAYER_LOGOUT" }

local function ApplyNative()
    if not Native then return end
    if active and db.hideNative then Native:Acquire(owner, "experienceBar") else Native:ReleaseOwner(owner) end
end

local function Toggle(enabled)
    StopPreviewDrag(true)
    YUI.Event:OffOwner(owner)
    CancelTimers()
    listeners = 0
    local wasActive = active
    active, preview, pinned, hovering = enabled == true, false, false, false
    colorPreview = false
    db = Config()
    if active then
        if not wasActive then Model.Reset(state, Now()) end
        questsDirty = true
        ApplyAppearance()
        for _, event in ipairs(events) do YUI.Event:On(event, OnEvent, owner); listeners = listeners + 1 end
        Render()
    else
        local store = SessionStore()
        if store then store.experienceBarSession = nil end
        if frame then frame:Hide(); panel:Hide() end
    end
    ApplyNative()
end

local function Change()
    StopPreviewDrag(true)
    CancelTimers()
    ApplyAppearance()
    ApplyNative()
    Render()
    SetDetails(pinned or (hovering and db.hoverEnabled))
end

local Feature = {
    id = KEY, name = L["name"], description = L["description"], default = true,
    settingsMode = "inline", product = PRODUCT, storageKey = KEY, toolboxManaged = true,
    sourceRoot = "Components\\ExperienceBar", versions = { "forever", "mainline" },
    assetFolders = { "Components\\ExperienceBar\\Media" },
    modSwitchImage = "modswitch\\experiencebar-bg.png", modSwitchImageCrop = false,
    callback = function(enabled)
        if enabled then YUI.Module:Enable(MODULE) else YUI.Module:Disable(MODULE) end
    end,
}

function Feature:GetSettingsTitleAction()
    return {
        getText = function() return L[colorPreview and "preview.stop" or "preview.start"] end,
        onClick = function()
            StopPreviewDrag(true)
            colorPreview = not colorPreview
            Change()
        end,
    }
end

function Feature:GetOptions()
    db = Config()
    local function Field(kind, key, extra)
        local field = extra or {}
        field.type, field.label = kind, L["setting." .. key]
        field.get = function() return Config()[key] end
        field.set = function(value) Config()[key] = value; Change() end
        if key == "layout" or key == "gradient" or key == "restedGradient" or key == "questGradient" then
            field.onChange = function() if Feature.RefreshCurrentModule then Feature.RefreshCurrentModule() end end
        end
        return field
    end
    local function Choices(prefix, keys)
        local result = {}
        for _, key in ipairs(keys) do result[#result + 1] = { text = L[prefix .. key], value = key } end
        return result
    end
    local function Row(left, right)
        local children = { left }
        if right then children[2] = right end
        for _, field in ipairs(children) do
            field.width = 320
            if field.type == "slider" then field.inline, field.inputWidth = true, 48 end
            if field.type ~= "checkbox" and field.type ~= "button" then
                field.inlineLabel, field.labelWidth, field.controlWidth, field.gap = true, 140, 180, 0
            end
        end
        return { type = "row", gap = 18, children = children }
    end
    local function Section(key)
        return { type = "divider", label = L["section." .. key], alignLeft = true, width = 658 }
    end
    local function Font(key)
        return Field("font", key, { prependOptions = {
            { text = L["font.chat"], value = "chat", fontPath = ChatFontNormal and select(1, ChatFontNormal:GetFont()) },
            { text = L["font.damage"], value = "damage", fontPath = DAMAGE_TEXT_FONT },
        } })
    end
    local options = {
        Section("layout"),
        Row(Field("dropdown", "layout", { options = Choices("layout.", { "left", "right", "center", "plain" }) }),
            Field("dropdown", "ring", { options = Choices("ring.", ringOrder), disabled = db.layout == "plain" })),
        Row(Field("slider", "width", { min = 300, max = 700, step = 1 }), Field("slider", "height", { min = 4, max = 64, step = 1 })),
        Row(Field("slider", "diameter", { min = 36, max = 80, step = 1, tooltip = L["setting.diameter.tooltip"], disabled = db.layout == "plain" })),
        Section("track"),
        Row(Field("color", "backgroundColor", { hasAlpha = true }), Field("color", "borderColor", { hasAlpha = true })),
        Section("fill"),
        Row(Field("texture", "texture")),
        Row(Field("checkbox", "gradient"), Field("checkbox", "vertical", { disabled = not db.gradient })),
        Row(Field("color", "startColor", { hasAlpha = true }), Field("color", "endColor", { hasAlpha = true, disabled = not db.gradient })),
        Section("restedFill"),
        Row(Field("checkbox", "showRested")),
        Row(Field("checkbox", "restedGradient"), Field("checkbox", "restedVertical", { disabled = not db.restedGradient })),
        Row(Field("color", "restedColor", { hasAlpha = true }), Field("color", "restedEndColor", { hasAlpha = true, disabled = not db.restedGradient })),
        Section("questFill"),
        Row(Field("checkbox", "showCompleted")),
        Row(Field("checkbox", "questGradient"), Field("checkbox", "questVertical", { disabled = not db.questGradient })),
        Row(Field("color", "questColor", { hasAlpha = true }), Field("color", "questEndColor", { hasAlpha = true, disabled = not db.questGradient })),
        Section("barText"),
        Row(Font("font"), Field("dropdown", "textStyle", { options = GUI2.Form:BuildFontOutlineOptions() })),
        Row(Field("slider", "levelSize", { min = 12, max = 36, step = 1 }), Field("color", "levelColor", { hasAlpha = true })),
        Row(Field("slider", "levelTextOffsetX", { min = -40, max = 40, step = 1 }), Field("slider", "levelTextOffsetY", { min = -40, max = 40, step = 1 })),
        Row(Field("slider", "barSize", { min = 9, max = 22, step = 1 }), Field("color", "barColor", { hasAlpha = true })),
        Row(Field("slider", "barTextOffsetY", { min = -20, max = 20, step = 1 })),
        Row(Field("checkbox", "showPercent"), Field("checkbox", "showETA")),
        Section("detailText"),
        Row(Font("detailFont"), Field("dropdown", "detailTextStyle", { options = GUI2.Form:BuildFontOutlineOptions() })),
        Row(Field("slider", "detailSize", { min = 9, max = 20, step = 1 }), Field("color", "detailColor", { hasAlpha = true })),
        Section("details"),
    }
    local function DetailField(key)
        return { type = "checkbox", label = L["detail." .. key],
            get = function() return Config().details[key] == true end,
            set = function(value) Config().details[key] = value == true; Change() end }
    end
    for index = 1, #detailKeys, 2 do
        options[#options + 1] = Row(DetailField(detailKeys[index]), detailKeys[index + 1] and DetailField(detailKeys[index + 1]))
    end
    options[#options + 1] = Section("behavior")
    options[#options + 1] = Row(Field("checkbox", "hoverEnabled"), Field("checkbox", "pinEnabled"))
    options[#options + 1] = Row(Field("checkbox", "hideMax"), Field("checkbox", "hideNative"))
    options[#options + 1] = { type = "button", label = L["setting.reset"], onClick = function()
        local config = Config()
        for key, value in pairs(defaults) do
            if type(value) == "table" then
                config[key] = {}
                for k, v in pairs(value) do config[key][k] = v end
            else config[key] = value end
        end
        Change()
        if Feature.RefreshCurrentModule then Feature.RefreshCurrentModule() end
    end }
    return options
end

function Feature:OnSettingsLeave()
    StopPreviewDrag(true)
    if leaveTimer then leaveTimer:Cancel(); leaveTimer = nil end
    hovering = false
    if colorPreview then colorPreview = false; Render() end
    if not pinned then SetDetails(false) end
end

function Feature:GetStats()
    return { active = active, listeners = listeners, pending = pending ~= nil,
        timers = (pending and 1 or 0) + (leaveTimer and 1 or 0) + (timeTimer and 1 or 0), events = eventCount,
        timeRefresh = timeTimer ~= nil,
        refreshes = refreshCount, rows = #detailKeys, idleTickers = 0 }
end

YUI.Module:Register({
    id = MODULE, owner = owner, product = PRODUCT,
    dependencies = { "core.db", "core.event", "core.locale", "core.api" },
    getEnabled = function() return Components:IsEnabled(KEY) end,
    OnEnable = function() Toggle(true) end,
    OnDisable = function() Toggle(false) end,
    OnProfileChanged = function()
        Model.Reset(state, Now())
        Toggle(Components:IsEnabled(KEY))
    end,
})
Components:RegisterFeature(KEY, Feature)
