local YUI = _G.YUI
local UF = YUI and YUI.YUnitFrames
if not UF then return end
local GUI = YUI.GUI2
local secret = YUI.API.Security.IsSecretValue
local unpack = unpack or table.unpack
local View = {}
UF.View = View
local bars = { health = true, power = true, absorbs = true, healabsorbs = true, cast = true }
local castParts = { casticon = true, castname = true, casttarget = true, casttime = true }
local domains = { casticon = "cast", castname = "cast", casttarget = "cast", casttime = "cast", health = "health", power = "power", absorbs = "absorb", healabsorbs = "absorb", cast = "cast", portrait = "identity", indicator = "identity" }
local previewIcons = { 136116, 135940, 136048, 135953, 135932, 136085, 136078, 135817 }

local function Font(fontString, config)
    GUI:ApplyFontAppearance(fontString, { font = config.font == "" and "default" or config.font,
        size = config.fontSize, outline = UF:OutlineMode(config.outline) })
    fontString.gui2ColorKey = nil -- User color is independent of the settings theme.
    fontString:SetTextColor(unpack(config.color))
    fontString:SetJustifyH(config.align)
    fontString:SetWordWrap(false)
end

local function TextLayout(font, parent, config)
    font:ClearAllPoints()
    font:SetWidth(0); font:SetHeight(0)
    if config.widthMode == "fixed" then font:SetAllPoints(parent)
    else font:SetPoint(config.align, parent, config.align, 0, 0) end
end

local function PaintTextColor(element, record)
    local data = element.config
    local r, g, b = data.color[1], data.color[2], data.color[3]
    if data.colorMode == "class" then
        if record.preview then r, g, b = UF:GetColor("class", "MAGE")
        else r, g, b = UF.Backend:UnitColor(record.unit) end
    end
    element.text:SetTextColor(r, g, b, data.color[4])
end

function View:Texture(id)
    if UF.Materials[id] then return UF.Materials[id] end
    if id == "flat" then return "Interface\\Buttons\\WHITE8X8" end
    return GUI:GetStatusBarTexture(id)
end

local function PaintColor(element, unit, preview)
    local config = element.config
    local r, g, b = config.color[1], config.color[2], config.color[3]
    if config.colorMode == "class" then
        if preview then r, g, b = UF:GetColor("class", "MAGE")
        else
            r, g, b = UF.Backend:UnitColor(unit)
        end
    elseif config.colorMode == "power" then
        if preview then r, g, b = UF:GetColor("power", "MANA")
        else
            local _, token = UnitPowerType(unit)
            if not secret(token) then
                if token then r, g, b = UF:GetColor("power", token) end
            end
        end
    end
    element.bar:SetStatusBarColor(r, g, b, config.color[4])
end

local function CreateElement(record, kind)
    local element = { kind = kind, frame = GUI:CreateFrame(record.content), record = record }
    element.frame:EnableMouse(false)
    if bars[kind] then
        element.bar = CreateFrame("StatusBar", nil, element.frame)
        element.bar:SetAllPoints()
        element.background = GUI:CreateTexture(element.frame, nil, "BACKGROUND")
        element.background:SetAllPoints()
        if kind == "cast" then
            element.label = GUI:CreateText(element.bar, "", 11)
            element.label:SetPoint("LEFT", 4, 0); element.label:SetPoint("RIGHT", -38, 0)
            element.time = GUI:CreateText(element.bar, "", 10)
            element.time:SetPoint("RIGHT", -3, 0)
            element.icon = GUI:CreateTexture(element.frame, nil, "ARTWORK")
            element.icon:SetPoint("RIGHT", element.frame, "LEFT", -3, 0)
            element.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            if not record.canvas then element.binding = UF.Backend:CreateCastBinding(element.time) end
        end
    elseif kind == "text" or (castParts[kind] and kind ~= "casticon") then
        element.text = GUI:CreateText(element.frame, "", 13)
        element.text:SetAllPoints()
        if kind == "casttime" and not record.canvas then element.binding = UF.Backend:CreateCastBinding(element.text) end
    elseif kind == "portrait" then
        element.portraitSlot = GUI:CreateFrame(element.frame)
        element.portraitSlot:SetPoint("CENTER", element.frame, "CENTER", 0, 0)
        element.texture = GUI:CreateTexture(element.portraitSlot, nil, "ARTWORK")
        element.portraitSlot.icon = element.texture
        element.texture:SetAllPoints()
        if not record.canvas then
            element.model = CreateFrame("PlayerModel", nil, element.portraitSlot)
            element.model:SetAllPoints(element.texture); element.model:Hide()
        end
    elseif kind == "auras" then
        element.auraRegions = {}
        if record.preview then
            element.icons = {}
            for i = 1, 16 do
                local icon = GUI:CreateTexture(element.frame, nil, "ARTWORK")
                icon:SetTexture(previewIcons[(i - 1) % #previewIcons + 1]); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                element.icons[i] = icon
            end
        end
    elseif kind == "border" then
        element.edges = {}
        for i = 1, 8 do element.edges[i] = GUI:CreateTexture(element.frame, nil, "OVERLAY") end
    else
        element.texture = GUI:CreateTexture(element.frame, nil, "ARTWORK")
        element.texture:SetAllPoints()
    end
    return element
end

local function ConfigureCast(element)
    local data = element.config
    element.ticks = GUI:CreateCastMarkers(element.bar, math.max(8, (data.tickCount or 0) - 1), element.ticks)
    element.icon:ClearAllPoints()
    local right = data.iconPosition == "RIGHT"
    element.icon:SetPoint(right and "LEFT" or "RIGHT", element.frame, right and "RIGHT" or "LEFT", right and data.iconGap or -data.iconGap, 0)
    element.icon:SetSize(data.height, data.height)
    element.icon:SetShown(data.iconPosition ~= "NONE")
    element.label:SetShown(data.showName)
    element.time:SetShown(data.showTime)
    element.label:ClearAllPoints()
    element.label:SetWidth(0); element.label:SetHeight(0)
    element.label:SetWordWrap(false); element.time:SetWordWrap(false)
    element.label:SetPoint("LEFT", 4, 0)
    if data.widthMode == "fixed" then element.label:SetPoint("RIGHT", data.showTime and -38 or -4, 0) end
    element.time:SetWidth(data.widthMode == "fixed" and 34 or 0)
    GUI:ApplyFontAppearance(element.label, { font = data.font, size = data.fontSize, outline = UF:OutlineMode(data.outline) })
    GUI:ApplyFontAppearance(element.time, { font = data.font, size = data.fontSize, outline = UF:OutlineMode(data.outline) })
end

local function AttachAbsorbs(record)
    local health
    for _, element in ipairs(record.elements) do if element.kind == "health" then health = element; break end end
    for _, element in ipairs(record.elements) do
        if element.kind == "absorbs" or element.kind == "healabsorbs" then
            local attached = element.config.absorbMode == "overlay"
            element.missingHealth = attached and not health
            if element.absorbClip then element.absorbClip:Hide() end
            element.background:SetShown(not attached and element.config.backgroundEnabled)
            if attached and health then
                local cfg = health.config
                if not element.absorbClip then element.absorbClip = GUI:CreateFrame(record.content) end
                local clip = element.absorbClip
                clip:SetAllPoints(health.frame); clip:SetClipsChildren(not element.config.overflow); clip:Show()
                local negative = cfg.reverse ~= element.config.reverse
                local edge = cfg.vertical and (cfg.reverse and "BOTTOM" or "TOP") or (cfg.reverse and "LEFT" or "RIGHT")
                local start = cfg.vertical and (negative and "TOP" or "BOTTOM") or (negative and "RIGHT" or "LEFT")
                element.frame:SetParent(clip); element.frame:ClearAllPoints()
                element.frame:SetPoint(start, health.bar:GetStatusBarTexture(), edge, 0, 0)
                element.frame:SetSize(health.frame:GetWidth(), health.frame:GetHeight())
                element.frame:SetFrameLevel(math.max(health.frame:GetFrameLevel() + 2, element.frame:GetFrameLevel()))
                element.bar:SetOrientation(cfg.vertical and "VERTICAL" or "HORIZONTAL")
                element.bar:SetReverseFill(negative)
            elseif attached then element.frame:Hide() end
        end
    end
end

local function ConfigureBorder(element, attached)
    local config = element.config
    if attached and config.borderStyle == "none" then
        if element.borderFrame then element.borderFrame:Hide() end
        return
    end
    if attached and not element.borderFrame then
        element.borderFrame = GUI:CreateFrame(element.bar)
        element.borderFrame:SetPoint("CENTER", element.frame, "CENTER", 0, 0)
        element.borderFrame:EnableMouse(false)
        element.borderEdges = {}
        for i = 1, 8 do element.borderEdges[i] = GUI:CreateTexture(element.borderFrame, nil, "OVERLAY") end
    end
    local frame = attached and element.borderFrame or element.frame
    local edges = attached and element.borderEdges or element.edges
    local pixel = GUI:GetPixelSize(frame, 1, 1)
    local thickness = GUI:GetPixelSize(frame, config.borderSize, 1)
    local width, height = element.frame:GetWidth(), element.frame:GetHeight()
    if attached then
        -- Draw outside the bar so thin power bars keep their full fill area.
        local outset = config.borderStyle == "double" and (thickness * 2 + pixel) or thickness
        width, height = width + outset * 2, height + outset * 2
        frame:SetSize(width, height)
        frame:ClearAllPoints()
        local dx, dy = 0, 0
        if element.sharedEdge == "TOP" then height = height - outset; dy = -outset / 2
        elseif element.sharedEdge == "BOTTOM" then height = height - outset; dy = outset / 2
        elseif element.sharedEdge == "LEFT" then width = width - outset; dx = outset / 2
        elseif element.sharedEdge == "RIGHT" then width = width - outset; dx = -outset / 2 end
        frame:SetSize(width, height)
        frame:SetPoint("CENTER", element.frame, "CENTER", dx, dy)
        frame:SetFrameLevel(element.bar:GetFrameLevel() + 1)
        frame:Show()
    else thickness = math.min(thickness, width / 6, height / 6) end
    for i, edge in ipairs(edges) do
        local inner = i > 4
        local inset = inner and (thickness + pixel) or 0
        local side = (i - 1) % 4 + 1
        edge:ClearAllPoints()
        if side == 1 or side == 2 then
            local point = side == 1 and "TOPLEFT" or "BOTTOMLEFT"
            local leftInset = element.sharedEdge == "LEFT" and 0 or inset
            local rightInset = element.sharedEdge == "RIGHT" and 0 or inset
            edge:SetPoint(point, frame, point, leftInset, side == 1 and -inset or inset)
            edge:SetSize(math.max(0, width - leftInset - rightInset), thickness)
        else
            local point = side == 3 and "TOPLEFT" or "TOPRIGHT"
            local topTrim = element.sharedEdge == "TOP" and 0 or inset + thickness
            local bottomTrim = element.sharedEdge == "BOTTOM" and 0 or inset + thickness
            edge:SetPoint(point, frame, point, side == 3 and inset or -inset, -topTrim)
            edge:SetSize(thickness, math.max(0, height - topTrim - bottomTrim))
        end
        edge:SetColorTexture(unpack(attached and config.borderColor or config.color))
        edge:SetShown((not inner or config.borderStyle == "double") and element.sharedEdge ~= ({ "TOP", "BOTTOM", "LEFT", "RIGHT" })[side])
    end
end

function View:New(parent, unit, preview, key)
    local record = { unit = unit, preview = preview == true, canvas = preview == true, pool = {}, elements = {}, active = false }
    if preview then record.frame = GUI:CreateFrame(parent)
    else
        record.frame = CreateFrame("Button", "YUI_UnitFrame_" .. (key or unit), parent, "SecureUnitButtonTemplate")
        record.frame:RegisterForClicks("AnyUp")
        record.frame:SetAttribute("unit", unit)
        record.frame:SetAttribute("type1", "target")
        record.frame:SetAttribute("type2", "togglemenu")
        record.frame:SetScript("OnEnter", function(frame)
            GameTooltip:SetOwner(frame, "ANCHOR_RIGHT"); GameTooltip:SetUnit(record.unit)
        end)
        record.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if ClickCastFrames and key ~= "castbar" then ClickCastFrames[record.frame] = true end
    end
    record.frame:SetSize(224, 54)
    -- Layout and its mover use UIParent units. Scale only the visual content.
    record.content = GUI:CreateFrame(record.frame)
    record.content:SetPoint("CENTER", record.frame, "CENTER", 0, 0)
    record.content:EnableMouse(false)
    UF.Stats.frames = UF.Stats.frames + 1
    return record
end

function View:Park(record)
    record.active = false
    for _, element in ipairs(record.elements) do
        if element.container then UF.Backend:ParkAura(element) end
        if element.binding then element.binding:SetEnabled(false) end
        if element.model then element.model:ClearModel() end
        element.frame:Hide()
    end
end

function View:StyleAuraRegions(regions, config, scale)
    scale = scale or 1
    for _, pair in ipairs({ { regions.count, config.stackStyle, config.stacks }, { regions.duration, config.durationStyle, config.duration } }) do
        local font, style = pair[1], pair[2]
        GUI:ApplyFontAppearance(font, { font = style.font, size = style.fontSize,
            outline = UF:OutlineMode(style.outline), fontScale = scale })
        font.gui2ColorKey = nil
        font:ClearAllPoints(); font:SetPoint(style.point, regions.owner, style.point, style.x / scale, style.y / scale)
        font:SetWordWrap(false); font:SetHeight(0)
        font:SetWidth(style.widthMode == "fixed" and (style.width or 40) / scale or 0)
        font:SetTextColor(unpack(style.color)); font:SetAlpha(pair[3] and 1 or 0)
    end
    regions.cooldown:SetAlpha(config.cooldown and 1 or 0)
    local size = GUI:GetPixelSize(regions.owner, config.auraBorder, 0)
    for i, edge in ipairs(regions.edges) do
        edge:ClearAllPoints()
        if i <= 2 then
            edge:SetPoint(i == 1 and "TOPLEFT" or "BOTTOMLEFT", regions.owner, i == 1 and "TOPLEFT" or "BOTTOMLEFT", 0, 0)
            edge:SetSize(regions.size, size)
        else
            edge:SetPoint(i == 3 and "TOPLEFT" or "TOPRIGHT", regions.owner, i == 3 and "TOPLEFT" or "TOPRIGHT", 0, -size)
            edge:SetSize(size, math.max(0, regions.size - 2 * size))
        end
        edge:SetColorTexture(unpack(config.auraBorderColor)); edge:SetShown(config.auraBorder > 0)
    end
end
local function ConfigureAura(element, record)
    local config = element.config
    if not record.canvas then UF.Backend:ConfigureAura(element, record) end
    if record.preview then
        element.samples = element.samples or {}
        element.icons = element.icons or {}
        for i = 1, 16 do
            local sample = element.samples[i]
            if not sample then
                local owner = GUI:CreateFrame(element.frame)
                local icon = element.icons[i] or GUI:CreateTexture(owner, nil, "ARTWORK")
                icon:SetParent(owner); icon:ClearAllPoints(); icon:SetAllPoints(owner)
                icon:SetTexture(previewIcons[(i - 1) % #previewIcons + 1]); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                sample = { owner = owner, count = GUI:CreateText(owner, "", 11), duration = GUI:CreateText(owner, "", 10),
                    cooldown = GUI:CreateTexture(owner, nil, "OVERLAY"), edges = {} }
                sample.cooldown:SetColorTexture(0, 0, 0, 0.35)
                for n = 1, 4 do sample.edges[n] = GUI:CreateTexture(owner, nil, "OVERLAY") end
                element.samples[i], element.icons[i] = sample, icon
            end
            sample.size = config.iconSize
            sample.owner:SetSize(config.iconSize, config.iconSize); sample.owner:ClearAllPoints()
            local x, y = UF:AuraOffset(config, i)
            sample.owner:SetPoint(config.startCorner, element.frame, config.startCorner, x, y)
            sample.cooldown:ClearAllPoints(); sample.cooldown:SetPoint("BOTTOMLEFT", sample.owner, "BOTTOMLEFT", 0, 0)
            sample.cooldown:SetSize(config.iconSize, config.iconSize * (i % 4 + 1) / 5)
            View:StyleAuraRegions(sample, config)
            local count = (i - 1) % 4 + 1
            sample.count:SetText(config.hideSingle and count == 1 and "" or tostring(count))
            sample.duration:SetText(i % 3 == 0 and "2m" or tostring(i * 7))
            sample.owner:SetShown(i <= math.min(config.count, UF.PreviewData.auraCount))
            element.icons[i]:SetShown(i <= math.min(config.count, UF.PreviewData.auraCount))
        end
    end
end

function View:Configure(record, config)
    self:Park(record)
    record.elements, record.config, record.hasCast = {}, config, false
    record.frame:SetSize(config.width * config.scale, config.height * config.scale)
    record.content:SetSize(config.width, config.height)
    record.content:SetScale(config.scale)
    record.content:ClearAllPoints(); record.content:SetPoint("CENTER", record.frame, "CENTER", 0, 0)
    local dx, dy = GUI:GetPixelOriginCorrection(record.content)
    -- Element boundaries are measured from the center, rather than the host's lower-left corner.
    dx = dx + GUI:SnapLayoutBoundary(record.content, config.width / 2) - config.width / 2
    dy = dy + GUI:SnapLayoutBoundary(record.content, config.height / 2) - config.height / 2
    record.content:SetPoint("CENTER", record.frame, "CENTER", dx, dy)
    local counts = {}
    for order, data in ipairs(config.elements) do
        if data.enabled then
            local kind = data.kind
            if kind == "cast" or castParts[kind] then record.hasCast = true end
            counts[kind] = (counts[kind] or 0) + 1
            local pool = record.pool[kind]
            if not pool then pool = {}; record.pool[kind] = pool end
            local element = pool[counts[kind]]
            if not element then element = CreateElement(record, kind); pool[counts[kind]] = element end
            element.config = data
            element.previewVisible = nil
            element.missingHealth = kind == "power" and data.powerMode == "attached" and not UF:HealthTarget(data, config)
            record.elements[#record.elements + 1] = element
            element.frame:SetParent(record.content)
            element.frame:ClearAllPoints()
            local x, y, width, height, vertical, sharedEdge = UF:ElementBounds(data, config, record.content)
            element.sharedEdge = sharedEdge
            element.frame:SetPoint("CENTER", record.content, "CENTER", x, y)
            element.frame:SetSize(width, height)
            element.frame:SetFrameLevel(record.frame:GetFrameLevel() + (#config.elements - order + 1) * 4)
            element.frame:SetAlpha(data.alpha)
            element.frame:Show()
            if element.bar then
                element.bar:SetStatusBarTexture(self:Texture(data.texture))
                element.bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
                element.bar:SetReverseFill(data.reverse)
                PaintColor(element, record.unit, record.preview)
                element.background:SetColorTexture(unpack(data.backgroundColor))
                element.background:SetShown(data.backgroundEnabled)
                ConfigureBorder(element, true)
                if kind == "cast" then ConfigureCast(element) end
            elseif element.text then
                Font(element.text, data); TextLayout(element.text, element.frame, data)
                if kind == "text" then element.compiled = UF.Tags:Compile(data.text) end
            elseif kind == "casticon" then element.texture:SetVertexColor(unpack(data.color))
            elseif kind == "border" then ConfigureBorder(element)
            elseif kind == "texture" then
                element.texture:SetTexture(self:Texture(data.texture)); element.texture:SetVertexColor(unpack(data.color))
            elseif kind == "portrait" then
                element.portraitSlot.gui2IconBorderColorOverride = data.borderColor
                GUI:ApplyIconAppearance(element.portraitSlot, { shape = data.mode == "3d" and "square" or data.shape,
                    border = data.portraitBorder, size = math.min(data.width, data.height), zoom = 0.08 })
                element.texture:SetShown(record.preview or data.mode ~= "3d")
                if element.model then
                    local inset = GUI:GetIconBorderThickness(data.portraitBorder)
                    element.model:ClearAllPoints()
                    element.model:SetPoint("TOPLEFT", element.portraitSlot, "TOPLEFT", inset, -inset)
                    element.model:SetPoint("BOTTOMRIGHT", element.portraitSlot, "BOTTOMRIGHT", -inset, inset)
                    element.model:SetShown(data.mode == "3d" and not record.preview)
                end
            elseif kind == "auras" then ConfigureAura(element, record) end
        end
    end
    AttachAbsorbs(record)
    record.active = true
    self:Paint(record)
end

local function PaintBar(element, record)
    local kind, unit, bar = element.kind, record.unit, element.bar
    if element.missingHealth then element.frame:Hide(); return end
    if record.preview then
        local samples = UF.PreviewData
        if (kind == "absorbs" and not samples.absorbs) or (kind == "healabsorbs" and not samples.healabsorbs) then element.frame:Hide(); return end
        element.frame:Show()
        if element.binding then element.binding:SetEnabled(false) end
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(kind == "health" and samples.health or kind == "power" and 70 or kind == "cast" and 58 or kind == "absorbs" and samples.absorbAmount or samples.healAbsorbAmount)
        if kind == "cast" then element.label:SetText(UF:T("preview.cast")); element.time:SetText("1.4"); element.icon:SetTexture(135846); UF.Backend:PaintTicks(element, nil, true) end
    elseif not UF.Backend:PaintBar(element, unit) then return end
    UF.Stats.valueWrites = UF.Stats.valueWrites + 1
end

local function PaintIndicator(element, record)
    local indicator, unit, texture = element.config.indicator, record.unit, element.texture
    if indicator == "raid" then
        local index = record.preview and 8 or GetRaidTargetIndex(unit)
        texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        if secret(index) then
            texture:SetSpriteSheetCell(index, 4, 4, 64, 64); texture:Show()
        elseif index and index > 0 then
            SetRaidTargetIconTexture(texture, index); texture:Show()
        else texture:Hide() end
    else
        texture:SetTexCoord(0, 1, 0, 1)
        local value
        if indicator == "leader" then value = UnitIsGroupLeader(unit); texture:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
        else value = UnitAffectingCombat(unit); texture:SetTexture("Interface\\CharacterFrame\\UI-StateIcon"); texture:SetTexCoord(0.5, 1, 0, 0.5) end
        if record.preview then texture:Show()
        elseif secret(value) then texture:Hide()
        else texture:SetShown(value == true) end
    end
end

function View:Paint(record, domain)
    if not record.active then return end
    if record.hasCast and not record.preview and (not domain or domain == "cast" or domain == "identity") then
        record.castInfo = YUI.API.Unit.GetCastInfo(record.unit)
        record.castDisplay = record.castDisplay or { castStages = {} }
        record.castDuration, record.castIsChannel = YUI.API.Unit.ReadCastDisplay(record.castInfo, record.castDisplay)
    end
    for _, element in ipairs(record.elements) do
        local kind = element.kind
        if element.text and (not domain or domain == "identity") then PaintTextColor(element, record) end
        if kind == "text" then UF.Tags:Paint(element.text, element.compiled, record.unit, record.preview, domain)
        elseif castParts[kind] and (not domain or domain == "cast") then
            UF.Backend:PaintCastPart(element, record)
        elseif kind == "auras" then
            if element.previewVisible ~= record.preview then
                if element.container then element.container:SetAlpha(record.preview and 0 or 1) end
                if element.icons then
                    for i, icon in ipairs(element.icons) do icon:SetShown(record.preview and i <= math.min(element.config.count, UF.PreviewData.auraCount)) end
                end
                if element.samples then
                    for i, sample in ipairs(element.samples) do sample.owner:SetShown(record.preview and i <= math.min(element.config.count, UF.PreviewData.auraCount)) end
                end
                element.previewVisible = record.preview
            end
        elseif not domain or domains[kind] == domain or (domain == "identity" and element.bar) then
            if element.bar then
                PaintBar(element, record)
                if not domain or domain == "identity" or kind == "power" then PaintColor(element, record.unit, record.preview) end
            elseif kind == "portrait" then
                element.texture:SetShown(record.preview or element.config.mode ~= "3d")
                if element.model then element.model:SetShown(not record.preview and element.config.mode == "3d") end
                if record.preview then UF.Backend:PaintPortrait(element.texture, "player")
                elseif element.config.mode == "3d" then element.model:SetUnit(record.unit)
                else UF.Backend:PaintPortrait(element.texture, record.unit) end
            elseif kind == "indicator" then PaintIndicator(element, record) end
        end
    end
    if record.healthDisplay then
        record.healthDisplay.valueRaw, record.healthDisplay.maxValueRaw, record.healthDisplay.percentRaw = nil, nil, nil
        record.healthDisplay.rawValuesAvailable = false
    end
    record.healthRead = nil
    record.castInfo, record.castDuration = nil, nil
end
