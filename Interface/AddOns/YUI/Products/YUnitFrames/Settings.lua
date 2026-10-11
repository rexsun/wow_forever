local YUI = _G.YUI
local UF = YUI and YUI.YUnitFrames
if not UF then return end
local S, GUI = YUI.Settings, YUI.GUI2
local LC = YUI.Locale:Get("Core")
local page, preview, selection, properties, rows, propertyScroll, propertyTitle, previewStage, listScroll
local propertyHeading, propertySubtitle, visibilityHost, sampleText
local selectedID = "name"
local propertyTab, showRoot = "content", false
local previewOwner = {}
local retired, propertyGeneration = nil, 0
local showColors, colorKind, colorToken, insertTag, propertyTabs = false, "class", "MAGE", "name", nil
local Render, RenderProperties, PaintPreview
local previewMenuOpen
local listDrag
local showCopy, copyTargets, sampleOptions = false, {}, false
local function CancelListDrag()
    if not listDrag then return end
    local drag = listDrag; listDrag = nil; UF.dragIndex = nil
    local ghost = drag.ghost
    ghost:SetScript("OnUpdate", nil)
    ghost:StopMovingOrSizing(); drag.ghost:Hide(); drag.line:Hide()
    drag.row:SetAlpha(drag.enabled and 1 or 0.38)
end
-- Product-scoped editor surfaces follow the active theme, without changing other pages.
GUI:RegisterTokenProvider("yunitframes.editor", function(tokens)
    local base = tokens["color.surface.raised"].value
    local light = tokens["color.text.secondary"].value
    local tint = tokens["color.control.active"].value
    for key, amount in pairs({ canvas = 0.035, panel = 0.045, header = 0.085, button = 0.08 }) do
        tokens["color.yunitframes." .. key] = GUI:CreateSolidPaint(
            base[1] * 0.65 + tint[1] * 0.35 + (light[1] - base[1]) * amount,
            base[2] * 0.65 + tint[2] * 0.35 + (light[2] - base[2]) * amount,
            base[3] * 0.65 + tint[3] * 0.35 + (light[3] - base[3]) * amount, 1)
    end
    local panel = tokens["color.yunitframes.panel"].value
    tokens["color.yunitframes.list"] = GUI:CreateSolidPaint(panel[1], panel[2], panel[3], 0.55)
    tokens["color.yunitframes.clear"] = GUI:CreateSolidPaint(0, 0, 0, 0)
end)
local function T(key) return UF:T(key) end
local function Config() return UF:GetDB().units[UF.selectedUnit or "player"] end
local function Selected()
    for _, element in ipairs(Config().elements) do if element.id == selectedID then return element end end
    local element = Config().elements[1]
    selectedID = element and element.id
    return element
end
local function Label(parent, text, x, y, width, color, size)
    local font = GUI:CreateText(parent, text, size or "font.size.md", color or "color.text.primary")
    font:SetPoint("TOPLEFT", x, y); font:SetWidth(width); font:SetJustifyH("LEFT")
    return font
end
local function ElementName(element)
    if element.kind == "text" then
        if element.id == "name" or element.id == "healthText" then return T("element." .. element.id) end
        return T("kind.text")
    end
    if element.kind == "texture" and element.id == "background" then return T("element.background") end
    if element.kind == "auras" then return T("filter." .. element.filter) end
    if element.kind == "indicator" then return T("option." .. element.indicator) end
    return T("kind." .. element.kind)
end
local function Button(parent, text, x, y, width, click, disabled, align, icon, height)
    local button = GUI.Form:CreateButton(parent, { text = text, width = width, height = height or 28, onClick = click, disabled = disabled,
        tone = "default", justifyH = align or "CENTER", microIcon = icon, iconSize = 16, iconGap = 6,
        fontSizeKey = width <= 56 and "font.size.sm" or "font.size.md", textLeftPadding = 10, textRightPadding = 6 })
    button:SetPoint("TOPLEFT", x, y)
    button.gui2SurfaceToken = "color.yunitframes.button"
    button.gui2BorderToken = "color.border.default"
    button.gui2HoverSurfaceToken = "color.interaction.fill"
    button:SetState(disabled and "disabled" or "normal")
    return button
end
local function Primary(button)
    button.gui2SurfaceToken = "color.interaction.primary"
    button.gui2BorderToken = "color.border.accent"
    button.gui2HoverSurfaceToken = "color.interaction.primaryHover"
    button.gui2PressedSurfaceToken = "color.interaction.primaryPressed"
    GUI.Form:SetButtonRelief(button, "hairline")
    button.gui2TextColorKey = "color.interaction.text"
    button.gui2HoverTextColorKey = "color.interaction.text"
    button:SetState(button.gui2Disabled and "disabled" or "normal")
    return button
end
local function Tabs(parent, opts)
    opts.height, opts.gap = opts.height or 30, opts.gap or 16
    opts.itemPaddingX, opts.minItemWidth = 8, 40
    opts.overflow = "scroll"
    opts.indicatorColorKey = "color.interaction.primary"
    opts.hoverColorKey = "color.text.primary"
    return GUI.Form:CreateUnderlineTabs(parent, opts)
end
local function Quiet(button)
    button.gui2SurfaceToken, button.gui2BorderToken = "color.yunitframes.clear", "color.yunitframes.clear"
    button.gui2HoverBorderToken = "color.border.subtle"
    button.gui2HoverTextColorKey = "color.text.primary"
    button:SetState(button.gui2Disabled and "disabled" or "normal")
    return button
end
local function Rule(parent, x, y, width)
    local line = GUI:CreateTexture(parent, { layer = "ARTWORK" })
    GUI:SetTexturePaintKey(line, "color.border.default")
    line:SetPoint("TOPLEFT", x, y); line:SetSize(width, GUI:GetPixelSize(parent, 1))
end
local castText = { castname = true, casttarget = true, casttime = true }
local function KindIcon(kind)
    if kind == "text" or castText[kind] then return "text-initial" end
    if kind == "portrait" or kind == "texture" then return "image" end
    if kind == "absorbs" or kind == "healabsorbs" then return "shield" end
    if kind == "indicator" then return "circle" end
    if kind == "auras" then return "panels-top-left" end
    if kind == "border" then return "square" end
    return "chart-bar-big"
end
local function SelectRow(row, selected)
    row:SetState(selected and "selected" or "normal")
    if row.marker then row.marker:SetShown(selected) end
end
-- Retired controls keep a hidden ancestor even if theme/scroll refresh shows them.
-- Do not orphan old controls with SetParent(nil): their callbacks still exist.
local function ClearEditor(parent)
    CancelListDrag()
    if not retired then retired = GUI:CreateFrame(UIParent); retired:Hide() end
    for _, child in ipairs({ parent:GetChildren() }) do
        child:Hide(); child:SetParent(retired); child:ClearAllPoints()
    end
    for _, region in ipairs({ parent:GetRegions() }) do
        region:Hide(); region:SetParent(retired); region:ClearAllPoints()
    end
end
local function Rerender(resetList)
    if not page or not page:IsShown() then return end
    local offset = not resetList and listScroll and listScroll:GetVerticalScroll() or 0
    Render(page)
    if listScroll then listScroll:SetVerticalScroll(offset); GUI:FitScrollContent(listScroll) end
end
function UF:RefreshSettings() Rerender() end
local function Changed()
    UF:ApplySettings(UF.selectedUnit or "player")
    PaintPreview()
    local element = Selected()
    if sampleText and element and element.kind == "text" then
        UF.Tags:Paint(sampleText, UF.Tags:Compile(element.text), UF.selectedUnit or "player", true)
    end
    local row = element and rows and rows[element.id]
    if row then
        row:SetText(ElementName(element))
        row:SetAlpha(element.enabled and 1 or 0.38)
        if row.visibilityButton then
            GUI:ApplyMicroIcon(row.visibilityButton.icon, element.enabled and "eye" or "eye-off", 16)
            row.visibilityButton:SetBareMicroIconColorKey(element.enabled and "color.text.secondary" or "color.text.disabled")
        end
    end
end
local function Set(element, field, value)
    if UF:InCombat() then return end
    element[field] = value
    Changed()
end
local function Slider(element, field, low, high, step)
    return { type = "slider", label = T("field." .. field), min = low, max = high, step = step or 1,
        get = function() return element[field] end, set = function(value) Set(element, field, value) end }
end
local function Check(element, field)
    return { type = "checkbox", label = T("field." .. field), get = function() return element[field] end,
        set = function(value) Set(element, field, value == true) end }
end
local function Options(values, prefix)
    local result = {}
    for _, value in ipairs(values) do result[#result + 1] = { value = value, text = T((prefix or "option.") .. value) } end
    return result
end
local function Dropdown(element, field, options)
    return { type = "dropdown", label = T("field." .. field), options = options,
        get = function() return element[field] end, set = function(value) Set(element, field, value) end }
end

local function SelectElement(id)
    local fullPage = showColors or showRoot or showCopy
    selectedID, showColors, showRoot, showCopy = id, false, false, false
    if fullPage then Rerender(); return end
    for key, row in pairs(rows or {}) do SelectRow(row, key == id) end
    if propertyScroll then propertyScroll:SetVerticalScroll(0) end
    PaintPreview(); RenderProperties()
end

local function PreviewBounds(item)
    local x, y, width, height = UF:ElementBounds(item, Config(), preview.content)
    if item.widthMode ~= "fixed" and (item.kind == "text" or castText[item.kind]) then
        for _, visual in ipairs(preview.elements) do
            if visual.config == item and visual.text then
                -- The canvas contains public sample text only; runtime never measures unit text.
                local measured = visual.text:GetStringWidth()
                if not YUI.API.Security.IsSecretValue(measured) then
                    if item.align == "LEFT" then x = x + (measured - width) / 2
                    elseif item.align == "RIGHT" then x = x - (measured - width) / 2 end
                    width = measured
                end
                break
            end
        end
    end
    return x, y, width, height
end

local function PickPreviewElement(anchor)
    if not preview or UF:InCombat() then return end
    local x, y = GetCursorPosition()
    local scale = preview.content:GetEffectiveScale()
    local cx, cy = preview.content:GetCenter()
    if not cx or not cy then return end
    x, y = x / scale - cx, y / scale - cy
    local options = {}
    for layer, item in ipairs(Config().elements) do
        local ix, iy, iw, ih = PreviewBounds(item)
        if item.enabled and math.abs(x - ix) <= iw / 2 and math.abs(y - iy) <= ih / 2 then
            options[#options + 1] = { value = item.id, text = ElementName(item),
                description = T("layer") .. " " .. layer .. " · " .. T("kind." .. item.kind) }
        end
    end
    if #options == 1 then SelectElement(options[1].value)
    elseif #options > 1 then
        local current = preview
        previewMenuOpen = true
        GUI:OpenDropdown(anchor, options, function(value)
            previewMenuOpen = nil
            if preview == current and page and page:IsShown() then SelectElement(value) end
        end, selectedID, 240)
    end
end

PaintPreview = function()
    if not preview then return end
    UF.View:Configure(preview, Config())
    local config = Config()
    local element = Selected()
    local left, right, bottom, top = -config.width / 2, config.width / 2, -config.height / 2, config.height / 2
    for _, item in ipairs(config.elements) do
        if item.enabled or item == element then
            local x, y, width, height = PreviewBounds(item)
            if item.kind == "auras" then
                local count = math.min(item.count, UF.PreviewData.auraCount)
                for i = 1, count do
                    local ax, ay = UF:AuraOffset(item, i)
                    local rightCorner = item.startCorner == "TOPRIGHT" or item.startCorner == "BOTTOMRIGHT"
                    local bottomCorner = item.startCorner == "BOTTOMLEFT" or item.startCorner == "BOTTOMRIGHT"
                    local cx = x + (rightCorner and width / 2 - item.iconSize / 2 or -width / 2 + item.iconSize / 2) + ax
                    local cy = y + (bottomCorner and -height / 2 + item.iconSize / 2 or height / 2 - item.iconSize / 2) + ay
                    left, right = math.min(left, cx - item.iconSize / 2 - 12), math.max(right, cx + item.iconSize / 2 + 12)
                    bottom, top = math.min(bottom, cy - item.iconSize / 2 - 12), math.max(top, cy + item.iconSize / 2 + 12)
                end
            end
            left = math.min(left, x - width / 2 - (item.kind == "cast" and item.iconPosition == "LEFT" and item.height + item.iconGap or 0))
            right = math.max(right, x + width / 2 + (item.kind == "cast" and item.iconPosition == "RIGHT" and item.height + item.iconGap or 0))
            bottom = math.min(bottom, y - height / 2)
            top = math.max(top, y + height / 2)
        end
    end
    local scale = math.min(1, (previewStage:GetWidth() - 28) / ((right - left) * config.scale), (previewStage:GetHeight() - 64) / ((top - bottom) * config.scale))
    preview.frame:SetScale(scale)
    previewStage.origin:ClearAllPoints()
    previewStage.origin:SetPoint("CENTER", previewStage, "CENTER", -(left + right) / 2 * scale * config.scale, -(bottom + top) / 2 * scale * config.scale + 12)
    UF.View:Configure(preview, config)
    if not element then selection:Hide(); return end
    local visual
    for _, item in ipairs(preview.elements) do if item.config.id == element.id then visual = item.frame; break end end
    selection:ClearAllPoints()
    local x, y, width, height = PreviewBounds(element)
    selection:SetPoint("CENTER", preview.content, "CENTER", x, y)
    selection.visual = visual
    selection:SetSize(math.max(16, width), math.max(16, height))
    selection:SetFrameLevel(preview.frame:GetFrameLevel() + 150)
    selection:Show()
end

local function ClearPreview()
    if previewMenuOpen then GUI:CloseDropdown(false); previewMenuOpen = nil end
    if preview then UF.View:Park(preview) end
    if selection then selection:StopMovingOrSizing(); selection:Hide() end
    preview, selection, previewStage = nil, nil, nil
end

local function BuildPreview(parent, width, height)
    height = math.min(height, 240)
    local stage = GUI:CreatePanel(parent, { width = width, height = height, surface = "color.yunitframes.canvas", border = false })
    previewStage = stage
    stage:SetClipsChildren(true)
    stage:SetPoint("TOPLEFT", 0, 0)
    Label(stage, T("preview.hint"), 12, -height + 32, width - 24, "color.text.secondary", "font.size.sm")
    stage.origin = GUI:CreateFrame(stage, { width = 1, height = 1 })
    preview = UF.View:New(stage.origin, UF.selectedUnit or "player", true)
    preview.frame:SetPoint("CENTER", stage.origin, "CENTER", 0, 0)
    selection = GUI:CreateButtonFrame(preview.content, { template = "BackdropTemplate" })
    GUI:CreateBorder(selection, "color.interaction.primary")
    selection:EnableMouse(true); selection:SetMovable(true); selection:RegisterForDrag("LeftButton")
    local hitArea = GUI:CreateButtonFrame(preview.content)
    hitArea:SetAllPoints(stage); hitArea:EnableMouse(true)
    hitArea:SetFrameLevel(preview.frame:GetFrameLevel() + 149)
    hitArea:SetScript("OnMouseUp", function(frame) PickPreviewElement(frame) end)
    local dragged = false
    selection:SetScript("OnMouseDown", function() dragged = false end)
    selection:SetScript("OnMouseUp", function(frame) if not dragged then PickPreviewElement(frame) end end)
    local dragX, dragY, originalX, originalY, dragElement
    selection:SetScript("OnDragStart", function(frame)
        if UF:InCombat() then return end
        dragElement = Selected()
        if not dragElement then return end
        if dragElement.absorbMode == "overlay" or dragElement.powerMode == "attached" then dragElement = nil; return end
        dragged = true
        dragX, dragY = GetCursorPosition(); originalX, originalY = dragElement.x, dragElement.y
        local visual = frame.visual or frame
        visual:SetMovable(true); visual:StartMoving()
    end)
    selection:SetScript("OnDragStop", function(frame)
        (frame.visual or frame):StopMovingOrSizing()
        if not dragElement then return end
        if not UF:InCombat() then
            local x, yPos = GetCursorPosition()
            local scale = preview.content:GetEffectiveScale()
            dragElement.x = math.floor(UF.Number(originalX + (x - dragX) / scale, -1000, 1000, originalX) + 0.5)
            dragElement.y = math.floor(UF.Number(originalY + (yPos - dragY) / scale, -1000, 1000, originalY) + 0.5)
            Changed(); RenderProperties()
        end
        dragElement = nil; PaintPreview()
    end)
    selection:SetScript("OnHide", function(frame) (frame.visual or frame):StopMovingOrSizing(); dragElement = nil end)
    local sampleButton = Quiet(Button(stage, T("preview.options"), width - 98, -4, 90, function()
        sampleOptions = not sampleOptions; Rerender()
    end))
    sampleButton:SetFrameLevel(preview.frame:GetFrameLevel() + 170)
    if sampleOptions then
        local host = GUI:CreateFrame(parent, { width = width, height = 250 })
        host:SetPoint("TOPLEFT", 0, -height)
        local y = 10
        local function SampleField(kind, key, low, high)
            local options = { min = low, max = high, step = 1, width = width - 24, inputWidth = 42, inline = true,
                get = function() return UF.PreviewData[key] end,
                set = function(value)
                    if previewStage == stage and page and page:IsShown() and not UF:InCombat() then
                        UF.PreviewData[key] = value; Changed()
                    end
                end }
            local widget
            if kind == "checkbox" then
                options.label = T("preview." .. key)
                widget = GUI.Form:CreateCheckbox(host, options)
            else
                Label(host, T("preview." .. key), 12, -y, width - 24, "color.text.secondary", "font.size.sm")
                y = y + 20
                widget = GUI.Form:CreateSlider(host, options)
            end
            widget:SetPoint("TOPLEFT", 12, -y)
            y = y + widget:GetHeight() + 8
        end
        SampleField("slider", "health", 0, 100)
        SampleField("checkbox", "absorbs")
        SampleField("slider", "absorbAmount", 0, 150)
        SampleField("checkbox", "healabsorbs")
        SampleField("slider", "healAbsorbAmount", 0, 150)
        SampleField("slider", "auraCount", 0, 16)
        host:SetHeight(y)
    end
    PaintPreview()
end

RenderProperties = function()
    if not properties then return end
    propertyGeneration = propertyGeneration + 1
    local generation = propertyGeneration
    -- Retire the entire generation before building another form. Focus-loss and
    -- theme callbacks must never revive controls under the active scroll child.
    local host = propertyScroll.child
    ClearEditor(host)
    properties = GUI:CreateFrame(host, { width = host:GetWidth(), height = 1 })
    properties:SetPoint("TOPLEFT", 0, 0)
    ClearEditor(visibilityHost)
    sampleText = nil
    local element = Selected()
    propertyTitle:SetText(showCopy and T("copy.title") or showColors and T("colors.title") or showRoot and T("frameOptions") or (element and ElementName(element) or T("elements")))
    propertySubtitle:SetText((showColors or showRoot or showCopy) and "" or T("unit." .. (UF.selectedUnit or "player")) .. " / " .. (element and T("kind." .. element.kind) or ""))
    if element and not showColors and not showRoot and not showCopy then
        local current = element
        local toggle = GUI.Form:CreateCheckbox(visibilityHost, { width = 72, height = 28, label = T("field.enabled"),
            get = function() return current.enabled end,
            set = function(value)
                if generation == propertyGeneration and page and page:IsShown() and Selected() == current then Set(current, "enabled", value == true) end
            end })
        toggle:SetPoint("TOPLEFT", 0, 0)
    end
    if propertyTabs then propertyTabs:SetShown(not showColors and not showRoot and not showCopy) end
    local fields = {}
    local function Add(value) fields[#fields + 1] = value end
    local defaultElement = element and UF:NewElement(element.kind, element.id)
    local function DefaultColor(object, key)
        if object == element then return defaultElement and defaultElement[key] end
        for name, child in pairs(element or {}) do
            if child == object then return defaultElement[name] and defaultElement[name][key] end
        end
    end
    local function Color(object, key)
        Add({ type = "color", label = T("field." .. key), hasAlpha = true, default = DefaultColor(object, key), get = function() return object[key] end,
            set = function(value) Set(object, key, UF.Copy(value)) end })
    end
    local function TextStyle(style)
        local mode = Dropdown(style, "widthMode", Options({ "auto", "fixed" }))
        mode.get = function() return style.widthMode or "auto" end
        mode.set = function(value) Set(style, "widthMode", value); RenderProperties() end
        Add(mode)
        if style.widthMode == "fixed" then
            local width = Slider(style, "width", 4, 600)
            width.get = function() return style.width or 40 end
            Add(width)
        end
        Add(Slider(style, "fontSize", 8, 32))
        Add({ type = "font", label = T("field.font"), prependOptions = {
            { value = "default", text = LC["font.builtin.default"] }, { value = "chat", text = LC["font.builtin.chat"] }, { value = "damage", text = LC["font.builtin.damage"] } },
            get = function() return style.font == "" and "default" or style.font end, set = function(value) Set(style, "font", value) end })
        local outline = Dropdown(style, "outline", GUI.Form:BuildFontOutlineOptions())
        outline.get = function() return UF:OutlineMode(style.outline) end
        Add(outline); Color(style, "color")
        Add(Dropdown(style, "point", Options({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" })))
        Add(Slider(style, "x", -80, 80)); Add(Slider(style, "y", -80, 80))
    end
    if showCopy then
        Add({ type = "text", label = T("copy.hint") .. " · " .. T("copy." .. UF.settingsClipboard.group) })
        local function SelectTargets(invert)
            if UF:InCombat() then return end
            for _, unit in ipairs(UF.UnitOrder) do
                for _, target in ipairs(UF:GetDB().units[unit].elements) do
                    if UF:CanPasteSettings(target) and target ~= element then
                        copyTargets[target] = not invert or not copyTargets[target]
                    end
                end
            end
            RenderProperties()
        end
        Add({ type = "button", label = T("copy.all"), onClick = function() SelectTargets(false) end })
        Add({ type = "button", label = T("copy.invert"), onClick = function() SelectTargets(true) end })
        for _, unit in ipairs(UF.UnitOrder) do
            for _, target in ipairs(UF:GetDB().units[unit].elements) do
                if UF:CanPasteSettings(target) and target ~= element then
                    Add({ type = "checkbox", copyUnit = unit, label = ElementName(target), get = function() return copyTargets[target] == true end,
                        set = function(value) copyTargets[target] = value == true end })
                end
            end
        end
        Add({ type = "button", label = T("copy.apply"), onClick = function()
            if UF:InCombat() then return end
            for _, unit in ipairs(UF.UnitOrder) do
                for _, target in ipairs(UF:GetDB().units[unit].elements) do
                    if copyTargets[target] then UF:PasteSettings(target) end
                end
            end
            showCopy = false; copyTargets = {}; UF:ApplySettings(); Rerender()
        end })
    elseif showColors then
        local tokens, options = UF:ColorKeys(colorKind), {}
        local found
        for _, token in ipairs(tokens) do
            if token == colorToken then found = true end
            local label
            if colorKind == "class" then label = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]
            else
                label = T("power." .. token)
                if label == "power." .. token then label = type(_G[token]) == "string" and _G[token] or token end
            end
            options[#options + 1] = { value = token, text = label or token }
        end
        if not found then colorToken = tokens[1] end
        local kind, token = colorKind, colorToken
        local function RefreshColors() UF:ApplySettings(); PaintPreview() end
        Add({ type = "text", label = T("colors.hint"), colorKey = "color.text.muted" })
        Add({ type = "dropdown", label = T("colors.kind"), options = Options({ "class", "power" }), get = function() return kind end,
            set = function(value) colorKind = value; RenderProperties() end })
        Add({ type = "dropdown", label = T("colors.token"), options = options, get = function() return token end,
            set = function(value) colorToken = value; RenderProperties() end })
        if token then
            Add({ type = "color", label = T("field.color"), get = function() return { UF:GetColor(kind, token) } end,
                set = function(value) if UF:SetColor(kind, token, value) then RefreshColors() end end })
            Add({ type = "button", label = T("colors.resetOne"), onClick = function()
                if UF:ResetColors(kind, token) then RefreshColors(); RenderProperties() end
            end })
        end
        Add({ type = "button", label = T("colors.resetAll"), onClick = function()
            if UF:ResetColors() then RefreshColors(); RenderProperties() end
        end })
    elseif showRoot then
        local root = Config()
        Add(Slider(root, "scale", 0.5, 2, 0.05))
        local rootWidth, rootHeight = Slider(root, "width", 40, 800), Slider(root, "height", 20, 300)
        rootWidth.label, rootHeight.label = T("root.width"), T("root.height")
        Add(rootWidth); Add(rootHeight)
        if UF.selectedUnit == "boss" then Add(Slider(root, "spacing", 35, 300)) end
        Add({ type = "button", label = T("defaults.restore"), onClick = function()
            if UF:InCombat() then return end
            previewMenuOpen = true
            GUI:OpenDropdown(propertyTitle:GetParent(), {
                { value = "restore", text = T("defaults.confirm"), description = T("defaults.hint") },
                { value = "cancel", text = LC["common.cancel"] },
            }, function(value)
                previewMenuOpen = nil
                if value ~= "restore" or generation ~= propertyGeneration or UF:InCombat() then return end
                local defaults = UF:DefaultUnit(UF.selectedUnit or "player")
                root.elements = defaults.elements; root.nextID = 1
                selectedID = "name"; showRoot = false; Changed(); Rerender(true)
            end, nil, 300)
        end })
    elseif not element then
        Add({ type = "text", label = T("empty") })
    elseif propertyTab == "position" then
        if element.kind == "power" then
            local mode = Dropdown(element, "powerMode", Options({ "attached", "independent" }))
            mode.set = function(value) Set(element, "powerMode", value); RenderProperties() end
            Add(mode)
        end
        if element.powerMode == "attached" then
            local healthOptions = { { value = "", text = T("power.autoHealth") } }
            for _, item in ipairs(Config().elements) do
                if item.kind == "health" then healthOptions[#healthOptions + 1] = { value = item.id, text = ElementName(item) .. " · " .. item.id } end
            end
            if #healthOptions > 2 or element.healthID ~= "" then Add(Dropdown(element, "healthID", healthOptions)) end
            Add(Dropdown(element, "attachSide", Options({ "TOP", "BOTTOM", "LEFT", "RIGHT" })))
            Add(Slider(element, "attachThickness", 2, 80)); Add(Slider(element, "attachGap", 0, 40))
        elseif element.absorbMode == "overlay" then
            Add({ type = "text", label = T("absorb.positionHint"), colorKey = "color.text.muted" })
        else
            local placement = Dropdown(element, "placement", Options(UF.Placements, "placement."))
            placement.set = function(value)
                if UF:InCombat() then return end
                element.placement, element.x, element.y = value, 0, 0
                Changed(); RenderProperties()
            end
            Add(placement)
            Add(Slider(element, "x", -500, 500)); Add(Slider(element, "y", -300, 300))
            if element.kind == "text" or castText[element.kind] then
                local mode = Dropdown(element, "widthMode", Options({ "auto", "fixed" }))
                mode.set = function(value) Set(element, "widthMode", value); RenderProperties() end
                Add(mode)
            end
            if (element.kind ~= "text" and not castText[element.kind]) or element.widthMode == "fixed" then Add(Slider(element, "width", 4, 600)) end
            Add(Slider(element, "height", 2, 160))
        end
        if element.kind == "auras" then
            Add(Slider(element, "iconSize", 12, 64)); Add(Slider(element, "perLine", 0, 16))
            Add(Slider(element, "spacing", 0, 20)); Add(Slider(element, "spacingY", 0, 20))
            Add(Dropdown(element, "startCorner", Options({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" })))
            local growth = Dropdown(element, "growth", Options({ "RIGHT", "DOWN" }, "aura.flow."))
            growth.get = function() return (element.growth == "LEFT" or element.growth == "RIGHT") and "RIGHT" or "DOWN" end
            Add(growth)
        end
        Add(Slider(element, "alpha", 0, 1, 0.05))
    elseif propertyTab == "content" then
        if element.kind == "text" then
            Add({ type = "text", label = T("field.text") })
            Add({ type = "editbox", label = T("field.text"), get = function() return element.text end,
                set = function(value) Set(element, "text", value:sub(1, 512)) end })
            local tagOptions = {}
            for _, id in ipairs(UF.Tags.order) do
                local label = T("tag." .. id)
                if label == "tag." .. id then label = id end
                tagOptions[#tagOptions + 1] = { text = label, description = "[" .. id .. "]", selectionText = label .. " · [" .. id .. "]", value = id }
            end
            Add({ type = "dropdown", label = T("insertTag"), menuWidth = 440, options = tagOptions, get = function() return insertTag end,
                set = function(value)
                    if UF:InCombat() then return end
                    insertTag = value
                    element.text = (element.text .. "[" .. value .. "]"):sub(1, 512); Changed(); RenderProperties()
                end })
            Add({ type = "text", label = T("tags.hint"), colorKey = "color.text.muted" })
            local compiled = UF.Tags:Compile(element.text)
            if #compiled.errors > 0 then Add({ type = "text", label = T("tags.unknown") .. table.concat(compiled.errors, ", "), colorKey = "color.state.warning" }) end
        elseif element.kind == "auras" then
            Add(Dropdown(element, "filter", Options({ "HELPFUL", "HARMFUL", "HELPFUL|PLAYER", "HARMFUL|PLAYER", "HARMFUL|RAID" }, "filter.")))
            Add(Slider(element, "count", 1, 16))
            Add(Check(element, "duration")); Add(Check(element, "stacks")); Add(Check(element, "hideSingle")); Add(Check(element, "cooldown"))
        elseif element.kind == "portrait" then Add(Dropdown(element, "mode", Options({ "2d", "3d" })))
        elseif element.kind == "cast" then
            local mode = Dropdown(element, "widthMode", Options({ "auto", "fixed" }))
            Add(mode)
            if UF.selectedUnit ~= "castbar" then Add(Check(element, "showName")); Add(Check(element, "showTime")) end
            Add(Check(element, "showTicks")); Add(Slider(element, "tickCount", 0, 32))
            Add(Check(element, "reverse"))
        elseif element.kind == "absorbs" or element.kind == "healabsorbs" then
            local mode = Dropdown(element, "absorbMode", Options({ "overlay", "independent" }))
            mode.set = function(value) Set(element, "absorbMode", value); RenderProperties() end
            Add(mode); Add(Check(element, "reverse"))
            if element.absorbMode == "overlay" then Add(Check(element, "overflow"))
            else Add(Check(element, "vertical")) end
        elseif element.kind == "indicator" then Add(Dropdown(element, "indicator", Options({ "raid", "leader", "combat" })))
        elseif castText[element.kind] or element.kind == "casticon" then
            Add({ type = "text", label = T("castPart.hint"), colorKey = "color.text.secondary" })
        elseif element.kind ~= "texture" and element.kind ~= "border" then
            Add(Check(element, "reverse"))
            if element.powerMode ~= "attached" then Add(Check(element, "vertical")) end
        end
    else
        if element.kind == "text" or element.kind == "cast" or castText[element.kind] then
            Add(Slider(element, "fontSize", 8, 32))
            Add({ type = "font", label = T("field.font"), prependOptions = {
                { value = "default", text = LC["font.builtin.default"] }, { value = "chat", text = LC["font.builtin.chat"] }, { value = "damage", text = LC["font.builtin.damage"] } },
                get = function() return element.font == "" and "default" or element.font end, set = function(value) Set(element, "font", value) end })
            local outline = Dropdown(element, "outline", GUI.Form:BuildFontOutlineOptions())
            outline.get = function() return UF:OutlineMode(element.outline) end
            Add(outline)
            if element.kind == "text" or castText[element.kind] then Add(Dropdown(element, "align", Options({ "LEFT", "CENTER", "RIGHT" }))) end
            if element.kind == "text" or castText[element.kind] then
                local mode = Dropdown(element, "colorMode", Options({ "custom", "class" }))
                mode.set = function(value) Set(element, "colorMode", value); RenderProperties() end
                Add(mode)
            end
            if element.kind == "cast" and UF.selectedUnit ~= "castbar" then
                Add(Dropdown(element, "iconPosition", Options({ "LEFT", "RIGHT", "NONE" })))
                Add(Slider(element, "iconGap", 0, 20))
            end
        elseif element.kind == "portrait" then
            if element.mode == "2d" then Add(Dropdown(element, "shape", Options({ "square", "rounded", "circle" })))
            else Add({ type = "text", label = T("portrait.modelHint"), colorKey = "color.text.muted" }) end
            Add(Dropdown(element, "portraitBorder", Options({ "none", "thin", "thick" })))
            Add({ type = "color", label = T("field.borderColor"), hasAlpha = true, default = defaultElement.borderColor, get = function() return element.borderColor end,
                set = function(value) Set(element, "borderColor", UF.Copy(value)) end })
        elseif element.kind == "auras" then
            Add(Slider(element, "auraBorder", 0, 8)); Color(element, "auraBorderColor")
            Add({ type = "text", label = T("field.duration") }); TextStyle(element.durationStyle)
            Add({ type = "text", label = T("field.stacks") }); TextStyle(element.stackStyle)
        elseif element.kind == "border" then
            Add(Dropdown(element, "borderStyle", Options({ "solid", "double" })))
            Add(Slider(element, "borderSize", 1, 8))
        end
        if element.kind ~= "auras" and element.kind ~= "portrait" and element.kind ~= "indicator" then
            if element.kind == "texture" or element.kind == "border" or element.colorMode == "custom" then
                Add({ type = "color", label = T("field.color"), hasAlpha = true, default = defaultElement.color, get = function() return element.color end,
                    set = function(value) Set(element, "color", UF.Copy(value)) end })
            else Add({ type = "text", label = T("colors.sourceHint"), colorKey = "color.text.muted" }) end
            if element.kind ~= "text" and element.kind ~= "border" and not castText[element.kind] and element.kind ~= "casticon" then
                Add({ type = "texture", label = T("field.texture"), get = function() return element.texture end, set = function(value) Set(element, "texture", value) end })
                if element.kind ~= "texture" then
                    local mode = Dropdown(element, "colorMode", Options({ "custom", "class", "power" }))
                    mode.set = function(value) Set(element, "colorMode", value); RenderProperties() end
                    Add(mode)
                end
            end
        end
        if UF.BarKinds[element.kind] then
            if element.absorbMode ~= "overlay" then
                Add(Check(element, "backgroundEnabled")); Color(element, "backgroundColor")
            end
            Add({ type = "text", label = T("border.hint"), colorKey = "color.text.muted" })
            local style = Dropdown(element, "borderStyle", Options({ "none", "solid", "double" }))
            style.set = function(value) Set(element, "borderStyle", value); RenderProperties() end
            Add(style)
            if element.borderStyle ~= "none" then
                Add(Slider(element, "borderSize", 1, 8))
                Add({ type = "color", label = T("field.borderColor"), hasAlpha = true, default = defaultElement.borderColor,
                    get = function() return element.borderColor end,
                    set = function(value) Set(element, "borderColor", UF.Copy(value)) end })
            end
        end
        if #fields == 0 then Add({ type = "text", label = T("appearance.empty"), colorKey = "color.text.muted" }) end
    end
    if element and (element.kind == "absorbs" or element.kind == "healabsorbs") and not showCopy and not showColors and not showRoot then
        local key = element.kind
        table.insert(fields, 1, { type = "checkbox", label = T("preview." .. key),
            get = function() return UF.PreviewData[key] end,
            set = function(value)
                if UF:InCombat() then return end
                UF.PreviewData[key] = value == true; Changed()
            end })
        table.insert(fields, 2, { type = "text", label = T("preview.absorbHint"), colorKey = "color.text.secondary" })
    end
    local width = properties:GetWidth() - 40
    for _, field in ipairs(fields) do
        for _, callbackKey in ipairs({ "set", "onClick" }) do
            local callback = field[callbackKey]
            if callback then
                field[callbackKey] = function(...)
                    if generation == propertyGeneration and page and page:IsShown() and Selected() == element then return callback(...) end
                end
            end
        end
        field.labelWidth, field.rowWidth, field.rowGap = 88, width, 6
        field.controlWidth = math.max(60, width - 98 - (field.type == "slider" and 62 or 0))
        field.valueWidth, field.gap = 54, 8
        -- Every input shares one label/control lane; long menu entries remain two-line.
        if field.type == "text" then
            field.width, field.justify = width, "LEFT"
            if field.colorKey == "color.text.muted" then field.colorKey = "color.text.secondary" end
        end
        if element and element.kind == "text" and propertyTab == "content" and not showColors and not showRoot and not showCopy
            and (field.type == "editbox" or field.type == "dropdown") then
            field.layout, field.width, field.labelWidth = "legacy", width, width
            field.controlWidth, field.rowGap = width, 14
        end
        if field.type == "button" then field.width, field.tone = math.min(width, 200), "default" end
    end
    local textEditor = element and element.kind == "text" and propertyTab == "content" and not showColors and not showRoot and not showCopy
    S:RenderConfig(properties, (textEditor or showCopy) and {} or fields)
    if showCopy then
        local buttonX, y, lastUnit, index = 20, 82, nil, 0
        local columns = math.max(1, math.min(3, math.floor((width - 100) / 150)))
        local cellWidth = (width - 100) / columns
        for _, field in ipairs(fields) do
            if field.type == "button" then
                local apply = field.label == T("copy.apply")
                local button = Button(properties, field.label, apply and width - 160 or buttonX, -8, apply and 180 or 100, field.onClick)
                if apply then Primary(button) else buttonX = buttonX + 108 end
            elseif field.type == "text" then Label(properties, field.label, 20, -48, width, "color.text.secondary", "font.size.sm")
            else
                if field.copyUnit ~= lastUnit then
                    if lastUnit then y = y + math.ceil(index / columns) * 30 + 12 end
                    Rule(properties, 20, -y + 6, width)
                    Label(properties, T("unit." .. field.copyUnit), 20, -y - 5, 94)
                    index, lastUnit = 0, field.copyUnit
                end
                field.width, field.inline, field.height = cellWidth - 8, true, 24
                local widget = GUI.Form:CreateCheckbox(properties, field)
                widget:SetPoint("TOPLEFT", 120 + (index % columns) * cellWidth, -y - math.floor(index / columns) * 30)
                index = index + 1
            end
        end
        properties:SetHeight(y + math.ceil(index / columns) * 30 + 12)
    elseif textEditor then
        local y = 12
        for _, field in ipairs(fields) do
            if field.type == "editbox" or field.type == "dropdown" then
                Label(properties, field.label, 20, -y, width)
                y = y + 24
                local widget = field.type == "editbox" and GUI.Form:CreateEditBox(properties, field)
                    or GUI.Form:CreateDropdown(properties, field)
                widget:SetPoint("TOPLEFT", 20, -y)
                y = y + widget:GetHeight() + 18
            elseif field.type == "text" and field.label ~= T("field.text") then
                local help = Label(properties, field.label, 20, -y, width, field.colorKey or "color.text.secondary", "font.size.sm")
                help:SetWordWrap(true)
                y = y + math.max(20, help:GetStringHeight()) + 12
            end
        end
        Rule(properties, 20, -y, width)
        Label(properties, T("text.sample"), 20, -y - 14, width, "color.text.secondary", "font.size.sm")
        sampleText = Label(properties, "", 20, -y - 36, width, "color.text.primary", "font.size.lg")
        UF.Tags:Paint(sampleText, UF.Tags:Compile(element.text), UF.selectedUnit or "player", true)
        properties:SetHeight(y + 70)
    end
    propertyScroll.child:SetHeight(properties:GetHeight())
    propertyScroll:UpdateScrollChildRect()
    GUI:FitScrollContent(propertyScroll)
end

local function BuildList(parent, width, y, height)
    local rowHeight = 24
    local listWidth = math.max(206, math.min(280, math.floor(width * 0.36)))
    local inspectorWidth = width - listWidth - 14
    local actionWidth = (listWidth - 22) / 4
    local list = GUI:CreatePanel(parent, { width = listWidth, height = height, surface = "color.yunitframes.list", border = false })
    list:SetPoint("TOPLEFT", 20, y)
    Label(list, T("elements"), 12, -16, 54, "color.text.primary")
    Label(list, tostring(#Config().elements), 58, -17, 24, "color.text.secondary", "font.size.sm")
    Button(list, T("up"), 8, -height + 36, actionWidth, function()
        if not UF:InCombat() and selectedID then UF:MoveElement(UF.selectedUnit or "player", selectedID, -1); Changed(); Rerender() end
    end)
    Button(list, T("down"), 10 + actionWidth, -height + 36, actionWidth, function()
        if not UF:InCombat() and selectedID then UF:MoveElement(UF.selectedUnit or "player", selectedID, 1); Changed(); Rerender() end
    end)
    local addButton
    addButton = Button(list, T("add"), listWidth - 120, -10, 110, function()
        if UF:InCombat() then return end
        local unit, generation = UF.selectedUnit, propertyGeneration
        local options = Options(UF.KindOrder, "kind.")
        for _, option in ipairs(options) do
            local kind = option.value
            local family = (kind == "text" or castText[kind]) and "text" or (kind == "health" or kind == "power" or kind == "cast" or kind == "absorbs" or kind == "healabsorbs") and "bar" or "visual"
            option.description = T("family." .. family)
        end
        previewMenuOpen = true
        GUI:OpenDropdown(addButton, options, function(kind)
            previewMenuOpen = nil
            if generation ~= propertyGeneration or not page or not page:IsShown() or UF:InCombat() then return end
            local element = UF:AddElement(unit, kind)
            if element then selectedID = element.id; propertyTab = kind == "border" and "appearance" or "content"; showColors = false; Changed(); Rerender(true) end
        end, nil, 240)
    end, #Config().elements >= UF.MAX_ELEMENTS)
    Primary(addButton)
    local scroll = GUI:CreateScrollFrame(list, { width = listWidth - 32, height = height - 92, childWidth = listWidth - 32, childHeight = math.max(1, #Config().elements * rowHeight), autoHide = true })
    listScroll = scroll
    scroll:SetPoint("TOPLEFT", 10, -50)
    local content = scroll.child
    rows = {}
    local dragGhost, dropLine
    local function UpdateDropPosition()
        local drag = listDrag
        if not drag then return end
        if UF:InCombat() or not scroll:IsVisible() then CancelListDrag(); return end
        local x, y = GetCursorPosition()
        local scale = scroll:GetEffectiveScale()
        x, y = x / scale, y / scale
        local left, right, top, bottom = scroll:GetLeft(), scroll:GetRight(), scroll:GetTop(), scroll:GetBottom()
        drag.valid = left and right and top and bottom and x >= left and x <= right and y >= bottom and y <= top
        if not drag.valid then drag.line:Hide(); return end
        local contentY = y * scale / content:GetEffectiveScale()
        drag.slot = math.max(1, math.min(#Config().elements + 1, math.floor((content:GetTop() - contentY) / rowHeight + 0.5) + 1))
        drag.line:ClearAllPoints()
        drag.line:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(drag.slot - 1) * rowHeight)
        drag.line:Show()
    end
    list:HookScript("OnHide", CancelListDrag)
    for i, element in ipairs(Config().elements) do
        local row = Button(content, ElementName(element), 0, -(i - 1) * rowHeight, listWidth - 64, function()
            if not content:IsVisible() or listDrag then return end
            showColors = false
            selectedID = element.id
            for id, button in pairs(rows) do SelectRow(button, id == selectedID) end
            propertyScroll:SetVerticalScroll(0); PaintPreview(); RenderProperties()
        end, false, "LEFT", KindIcon(element.kind), rowHeight)
        rows[element.id] = row
        row.gui2SelectedSurfaceToken = "color.control.active"
        row.gui2SelectedBorderToken = "color.control.active"
        row.gui2SelectedTextColorKey = "color.text.primary"
        row.gui2SurfaceToken, row.gui2BorderToken = "color.yunitframes.clear", "color.yunitframes.clear"
        row.marker = GUI:CreateTexture(row, { layer = "OVERLAY", subLevel = 7 })
        GUI:SetTexturePaintKey(row.marker, "color.interaction.primary")
        row.marker:SetPoint("TOPLEFT", 0, 0); row.marker:SetSize(3, rowHeight)
        SelectRow(row, element.id == selectedID)
        row:SetAlpha(element.enabled and 1 or 0.38)
        local function KeepDragRestingState()
            if listDrag then SelectRow(row, element.id == selectedID) end
        end
        row:HookScript("OnEnter", KeepDragRestingState)
        row:HookScript("OnMouseDown", KeepDragRestingState)
        row:HookScript("OnMouseUp", KeepDragRestingState)
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", function()
            if UF:InCombat() or not content:IsVisible() then return end
            CancelListDrag()
            local ghost = dragGhost or GUI:CreatePanel(list, { width = listWidth - 44, height = rowHeight,
                surface = "color.control.active", border = "color.border.accent" })
            ghost:SetFrameStrata("TOOLTIP"); ghost:EnableMouse(false); ghost:SetMovable(true)
            dragGhost = ghost
            ghost.caption = ghost.caption or Label(ghost, "", 10, -4, listWidth - 64)
            ghost.caption:SetText(ElementName(element)); ghost:Show()
            local x, cursorY = GetCursorPosition(); local scale = ghost:GetEffectiveScale()
            ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, cursorY / scale)
            local marker = scroll.yunitframesDropMarker
            if not marker then
                marker = GUI:CreateFrame(scroll, { width = listWidth - 32, height = 1 })
                marker:SetAllPoints(scroll)
                marker:SetFrameLevel(content:GetFrameLevel() + 200); marker:EnableMouse(false)
                scroll.yunitframesDropMarker = marker
            end
            local line = dropLine or GUI:CreateTexture(marker, { layer = "OVERLAY", subLevel = 7 })
            dropLine = line; line:Show(); line:ClearAllPoints()
            GUI:SetTexturePaintKey(line, "color.interaction.primary")
            line:SetSize(listWidth - 32, GUI:GetPixelSize(content, 2))
            line:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
            listDrag = { ghost = ghost, line = line, row = row, source = i, slot = i, enabled = element.enabled }
            for id, button in pairs(rows) do SelectRow(button, id == selectedID) end
            UF.dragIndex = i; row:SetAlpha(0.2); ghost:StartMoving()
            ghost:SetScript("OnUpdate", function() UpdateDropPosition() end)
            UpdateDropPosition()
        end)
        row:SetScript("OnDragStop", function()
            local drag = listDrag
            if not drag then return end
            UpdateDropPosition()
            if listDrag ~= drag then return end
            local slot = drag.slot
            local target = slot > i and slot - 1 or slot
            local valid = drag.valid
            CancelListDrag()
            if valid and target ~= i then UF:MoveElement(UF.selectedUnit or "player", element.id, target - i); Changed(); Rerender() end
        end)
        row.visibilityButton = GUI:CreateBareMicroIconButton(content, {
            size = rowHeight, iconName = element.enabled and "eye" or "eye-off",
            colorKey = element.enabled and "color.text.secondary" or "color.text.disabled",
            tooltip = function() return T(element.enabled and "action.hide" or "action.show") .. " · " .. ElementName(element) end,
            onClick = function()
                if UF:InCombat() then return end
                element.enabled = not element.enabled; Changed(); Rerender()
            end,
        })
        row.visibilityButton:SetPoint("TOPLEFT", listWidth - 60, -(i - 1) * rowHeight)
    end
    Button(list, T("duplicate"), 12 + actionWidth * 2, -height + 36, actionWidth, function()
        if UF:InCombat() then return end
        local selected = Selected()
        if not selected then return end
        local item = UF:AddElement(UF.selectedUnit or "player", selected.kind)
        if item then
            local id = item.id
            for key, value in pairs(selected) do item[key] = UF.Copy(value) end
            item.id, item.y, selectedID = id, selected.y + 10, id
            Changed(); Rerender()
        end
    end)
    Button(list, T("remove"), 14 + actionWidth * 3, -height + 36, actionWidth, function()
        if UF:InCombat() then return end
        for i, element in ipairs(Config().elements) do
            if element.id == selectedID then table.remove(Config().elements, i); break end
        end
        Selected(); Changed(); Rerender()
    end)
    Rule(list, 10, -height + 42, listWidth - 20)
    scroll:UpdateScrollChildRect()
    GUI:FitScrollContent(scroll)
    local divider = GUI:CreateTexture(parent, { layer = "ARTWORK" })
    GUI:SetTexturePaintKey(divider, "color.border.default")
    divider:SetPoint("TOPLEFT", 27 + listWidth, y)
    divider:SetSize(GUI:GetPixelSize(parent, 1), height)
    local inspector = GUI:CreatePanel(parent, { width = inspectorWidth, height = height, surface = "color.yunitframes.clear", border = false })
    inspector:SetPoint("TOPLEFT", 34 + listWidth, y)
    propertyHeading = GUI:CreatePanel(inspector, { width = inspectorWidth, height = 50, surface = "color.yunitframes.clear", border = false })
    propertyHeading:SetPoint("TOPLEFT", 0, 0)
    propertyTitle = Label(propertyHeading, "", 18, -9, inspectorWidth - 118, "color.text.primary", "font.size.lg")
    propertySubtitle = Label(propertyHeading, "", 18, -31, inspectorWidth - 118, "color.text.secondary", "font.size.sm")
    visibilityHost = GUI:CreateFrame(propertyHeading, { width = 72, height = 28 })
    visibilityHost:SetPoint("TOPRIGHT", -12, -12)
    local tabs = Tabs(inspector, { width = math.min(250, inspectorWidth - 144), value = propertyTab,
        items = { { value = "content", text = T("tab.content") }, { value = "position", text = T("tab.position") }, { value = "appearance", text = T("tab.appearance") } },
        onChange = function(_, value) propertyTab = value; propertyScroll:SetVerticalScroll(0); RenderProperties() end })
    Rule(inspector, 18, -49, inspectorWidth - 36)
    Rule(inspector, 18, -84, inspectorWidth - 36)
    local copyButton
    copyButton = Quiet(Button(inspector, T("copy.title"), inspectorWidth - 106, -52, 90, function()
        local current, generation = Selected(), propertyGeneration
        if not current or UF:InCombat() then return end
        local options = {}
        for _, group in ipairs(UF.CopyGroups) do
            if UF:CanCopySettings(current, group) then
                options[#options + 1] = { value = group, text = T("copy." .. group) }
            end
        end
        if UF:CanPasteSettings(current) then options[#options + 1] = { value = "paste", text = T("copy.paste") } end
        previewMenuOpen = true
        GUI:OpenDropdown(copyButton, options, function(value)
            previewMenuOpen = nil
            if generation ~= propertyGeneration or not page or not page:IsShown() then return end
            if value == "paste" then UF:PasteSettings(current); Changed(); RenderProperties()
            elseif UF:CopySettings(current, value) then showCopy = true; copyTargets = {}; Rerender() end
        end, nil, 200)
    end))
    propertyTabs = tabs
    tabs:SetPoint("TOPLEFT", 18, -52)
    propertyScroll = GUI:CreateScrollFrame(inspector, { width = inspectorWidth - 18, height = height - 96,
        childWidth = inspectorWidth - 18, childHeight = 1, autoHide = true })
    propertyScroll:SetPoint("TOPLEFT", 0, -88)
    properties = propertyScroll.child
    RenderProperties()
end

local function BuildSettingsPage(parent, width, y, height)
    rows, listScroll, propertyTabs = nil, nil, nil
    local heading = GUI:CreateFrame(parent, { width = width, height = 40 })
    heading:SetPoint("TOPLEFT", 20, y)
    propertyTitle = Label(heading, "", 0, -9, width - 110, "color.text.primary", "font.size.lg")
    propertySubtitle = Label(heading, "", 0, -30, width - 110)
    visibilityHost = GUI:CreateFrame(heading)
    visibilityHost:Hide()
    Quiet(Button(heading, LC["common.back"], width - 90, -4, 90, function()
        showRoot, showColors, showCopy = false, false, false; Rerender()
    end))
    Rule(heading, 0, -38, width)
    propertyScroll = GUI:CreateScrollFrame(parent, { width = width, height = height - 46,
        childWidth = width, childHeight = 1, autoHide = true })
    propertyScroll:SetPoint("TOPLEFT", 20, y - 46)
    properties = propertyScroll.child
    RenderProperties()
end

function UF:OnSettingsLeave()
    CancelListDrag()
    self:SetSettingsPreview(nil)
    showCopy, copyTargets = false, {}
    propertyGeneration = propertyGeneration + 1
    propertyTabs, propertyHeading, propertySubtitle, visibilityHost, sampleText = nil, nil, nil, nil, nil
    S:ClearRightPreview(previewOwner)
    ClearPreview()
    page, properties, rows, propertyScroll, propertyTitle, listScroll, self.dragIndex = nil, nil, nil, nil, nil, nil, nil
end

Render = function(host)
    propertyGeneration = propertyGeneration + 1
    ClearEditor(host)
    page = host
    rows, listScroll, propertyTabs = nil, nil, nil
    local parent = GUI:CreateFrame(host, { width = host:GetWidth(), height = 1 })
    parent:SetPoint("TOPLEFT", 0, 0)
    UF.selectedUnit = UF.selectedUnit or "player"
    UF:SetSettingsPreview(UF.selectedUnit)
    Selected()
    local width = math.max(560, parent:GetWidth() - 40)
    local unit = UF.selectedUnit
    local function IsCurrent() return parent:IsVisible() and UF.selectedUnit == unit end
    local function ChooseUnit(value)
        if not IsCurrent() or not UF:GetDB().units[value] then return end
        UF.selectedUnit = value; selectedID = "name"; showColors, showRoot, showCopy = false, false, false; Rerender(true)
    end
    Label(parent, T("title"), 20, -(S.ModulePageLayout and S.ModulePageLayout.titleTop or 20), width - 130, "color.text.heading", "font.size.title")
    local colorsButton = Quiet(Button(parent, T("colors.title"), width - 80, -16, 100, function()
        if not IsCurrent() then return end
        showColors, showRoot, showCopy = not showColors, false, false; Rerender()
    end, false, "LEFT", "paintbrush"))
    colorsButton:SetState(showColors and "selected" or "normal")
    local controlsTop = 56
    local selectorWidth = math.max(160, math.min(230, width - 376))
    local selector = GUI.Form:CreateDropdown(parent, { width = selectorWidth, height = 28, menuWidth = 280,
        get = function() return UF.selectedUnit end,
        options = function()
            local options = {}
            for _, value in ipairs(UF.UnitOrder) do
                local label = T("unit." .. value)
                options[#options + 1] = { value = value,
                    text = label, selectionText = label,
                    render = function(button)
                        local enabled = UF:GetDB().units[value].enabled
                        local status = button.yunitframesStatus
                        if not status then
                            status = GUI:CreateText(button, "", "font.size.sm", "color.text.secondary")
                            button.yunitframesStatus = status
                            button:HookScript("OnHide", function() status:Hide() end)
                        end
                        status:SetText(T(enabled and "unitState.enabled" or "unitState.disabled"))
                        GUI:SetTextColorKey(status, enabled and "color.state.success" or "color.text.disabled")
                        status:Show()
                        status:SetPoint("RIGHT", -12, 0); status:SetWidth(76); status:SetJustifyH("RIGHT")
                        button.text:SetWidth(160); button.text:ClearAllPoints(); button.text:SetPoint("LEFT", 20, 0)
                    end }
            end
            return options
        end,
        set = ChooseUnit })
    selector:SetPoint("TOPLEFT", 20, -controlsTop)
    local enabled = GUI.Form:CreateCheckbox(parent, { width = 80, height = 28, label = LC["common.enable"],
        get = function() return Config().enabled end,
        set = function(value)
            if IsCurrent() and not UF:InCombat() then
                Config().enabled = value; if value then Config().hideNative = true end
                Changed(); Rerender()
            end
        end })
    enabled:SetPoint("TOPLEFT", 34 + selectorWidth, -controlsTop)
    local native = GUI.Form:CreateCheckbox(parent, { width = 150, height = 28, label = T("hideNative"),
        get = function() return Config().hideNative end,
        set = function(value)
            if IsCurrent() and not UF:InCombat() then
                Config().hideNative, Config().enabled = value, value
                UF:ApplySettings(); Rerender()
            end
        end })
    native:SetPoint("TOPLEFT", 120 + selectorWidth, -controlsTop)
    local rootButton = Quiet(Button(parent, T("frameOptions"), width - 80, -controlsTop, 100, function()
        if not IsCurrent() then return end
        showRoot, showColors, showCopy = not showRoot, false, false; Rerender()
    end, false, "LEFT", "settings"))
    rootButton:SetState(showRoot and "selected" or "normal")
    local toolbarTop = controlsTop + 38
    if UF:InCombat() then
        Label(parent, T("combatLock"), 20, -toolbarTop, width, "color.state.warning", "font.size.sm")
        toolbarTop = toolbarTop + 26
    end
    Rule(parent, 20, -toolbarTop + 2, width)
    local top = toolbarTop + 8
    local viewport = S.Elements and S.Elements.scrollFrame
    local height = math.max(260, (viewport and viewport:GetHeight() or 620) - top - 12)
    if showColors or showRoot or showCopy then BuildSettingsPage(parent, width, -top, height)
    else BuildList(parent, width, -top, height) end
    local previewWidth = 280
    local window = S.Elements and S.Elements.frame
    if window and window.GetRight and UIParent.GetRight then
        local available = (UIParent:GetRight() * UIParent:GetEffectiveScale() - window:GetRight() * window:GetEffectiveScale()) / window:GetEffectiveScale() - 12
        previewWidth = math.max(220, math.min(320, available))
    end
    S:ShowRightPreview(previewOwner, { width = previewWidth, height = sampleOptions and 600 or 240,
        title = T("preview.title") .. " · " .. T("unit." .. UF.selectedUnit), onClear = ClearPreview,
        render = function(content, context) BuildPreview(content, context.width, context.height) end })
    if not host.yunitframesHideHook then
        host.yunitframesHideHook = true
        host:HookScript("OnHide", function() if page == host then UF:OnSettingsLeave() end end)
        host:HookScript("OnShow", function()
            if page ~= host then Render(host) end
        end)
    end
    parent:SetHeight(top + height + 10)
    host:SetHeight(parent:GetHeight())
    if viewport then viewport:UpdateScrollChildRect() end
    if S.RefreshCurrentModuleScroll then S:RefreshCurrentModuleScroll(false) end
end

S:RegisterModule("YUnitFrames", 132089, Render, {
    id = UF.SETTINGS_ENTRY, product = UF.PRODUCT_ID, scope = UF.PRODUCT_ID,
    titleKey = "title", titleNamespace = "YUnitFrames", navTitleKey = "title", navTitleNamespace = "YUnitFrames",
    navToggle = { moduleId = UF.PRODUCT_ID,
        get = function() return UF:IsEnabled() end,
        set = function(_, enabled) return UF:SetEnabled(enabled) end,
    },
})
