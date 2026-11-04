local YUI = _G.YUI
local GUI = YUI and YUI.GUI2
local Skins = GUI and GUI.IconSkins
if not (Skins and GUI.Form) then return end
local preview, previewOwner, popup, activeOwner
local function L(key, fallback) return Skins:Label(key, fallback) end
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Copy(item) end
    return result
end
local function Style(owner)
    return Skins:NormalizeSettings(Copy(owner.binding.getStyle() or {}), owner.binding.product)
end
local function CloseMenuOwnedBy(owner)
    local menu = GUI.DropdownFrame
    local anchor = menu and menu.anchor
    while anchor do
        if anchor == owner then GUI:CloseDropdown(false); return end
        anchor = anchor.GetParent and anchor:GetParent()
    end
end
-- 所有坐标统一到弹窗缩放；选择有空间的一侧，再约束纵向位置。
local function PlaceBeside(panel, anchor, verticalAnchor)
    verticalAnchor = verticalAnchor or anchor
    local scale = panel:GetEffectiveScale()
    local rootScale = UIParent:GetEffectiveScale()
    local screenWidth, screenHeight = UIParent:GetWidth() * rootScale / scale, UIParent:GetHeight() * rootScale / scale
    local width, height = panel:GetWidth(), panel:GetHeight()
    local factor = math.min(1, (screenWidth - 16) / width, (screenHeight - 16) / height)
    if factor < 1 then
        panel:SetScale(panel:GetScale() * factor)
        scale = panel:GetEffectiveScale()
        screenWidth, screenHeight = UIParent:GetWidth() * rootScale / scale, UIParent:GetHeight() * rootScale / scale
    end
    local anchorScale = anchor:GetEffectiveScale() / scale
    local left, right = anchor:GetLeft(), anchor:GetRight()
    local top = verticalAnchor:GetTop()
    panel:ClearAllPoints()
    if not left or not right or not top then
        panel:SetPoint("TOPRIGHT", verticalAnchor, "BOTTOMRIGHT", 0, -6)
        return
    end
    left, right = left * anchorScale, right * anchorScale
    top = top * verticalAnchor:GetEffectiveScale() / scale
    local fitsLeft, fitsRight = left - 10 - width >= 8, right + 10 + width <= screenWidth - 8
    local x
    if fitsLeft and (not fitsRight or (left + right) / 2 > screenWidth / 2) then x = left - width - 10
    elseif fitsRight then x = right + 10
    else
        x = math.max(8, math.min(screenWidth - width - 8, right - width))
        local bottom = verticalAnchor:GetBottom()
        bottom = bottom and bottom * verticalAnchor:GetEffectiveScale() / scale or top
        top = bottom - height - 8 >= 8 and bottom - 8 or top + height + 8
    end
    top = math.max(height + 8, math.min(screenHeight - 8, top))
    panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, top)
end
local function ClosePreview(owner)
    if not previewOwner or (owner and owner ~= previewOwner) then return end
    previewOwner = nil
    for _, sample in pairs({ preview.sample, preview.empty }) do
        if Skins.claims[sample] then GUI:ReleaseIconSkin(sample) end
        GUI:HideShapeShadow(sample.previewShadow)
        sample:Hide()
    end
    preview:Hide()
    preview:ClearAllPoints()
end
local function CreateSample(parent)
    local sample = GUI.Application:CreateCooldownIcon(parent, {
        size = 48, icon = 135807, shape = "square", border = "thin", variant = "bare" })
    sample:EnableMouse(false)
    sample.background = sample.background or GUI:CreateTexture(sample, { layer = "BACKGROUND", subLevel = -7 })
    sample.background:SetAllPoints(sample)
    sample.skinPreviewMask = sample:CreateMaskTexture()
    sample.skinPreviewMask:SetAllPoints(sample)
    sample.skinPreviewMask:SetTexture("Interface\\Buttons\\WHITE8X8")
    sample.background:AddMaskTexture(sample.skinPreviewMask)
    sample.previewState = { backgroundMask = sample.skinPreviewMask }
    sample.previewTarget = { icon = sample.icon, background = sample.background, mask = sample.skinPreviewMask }
    sample.previewShadow = GUI:CreateShapeShadow(sample)
    sample.caption = GUI:CreateText(sample, "", "font.size.sm", "color.text.secondary")
    sample.caption:SetPoint("TOP", sample, "BOTTOM", 0, -4)
    return sample
end
local function EnsurePreview()
    if preview then return preview end
    preview = GUI:CreatePanel(UIParent, { width = 164, height = 112,
        surface = "color.surface.popup", border = "color.popup.border", shadow = true })
    preview:Hide()
    preview:SetFrameStrata("TOOLTIP")
    preview:SetClampedToScreen(true)
    preview:EnableMouse(false)
    preview.title = GUI:CreateText(preview, "", "font.size.md", "color.text.heading")
    preview.title:SetPoint("TOPLEFT", 10, -10)
    preview.title:SetPoint("TOPRIGHT", -10, -10)
    preview.title:SetJustifyH("CENTER")
    preview.note = GUI:CreateText(preview, "", "font.size.sm", "color.text.secondary")
    preview.note:SetPoint("BOTTOMLEFT", 8, 8)
    preview.note:SetPoint("BOTTOMRIGHT", -8, 8)
    preview.note:SetJustifyH("CENTER")
    preview.note:SetWordWrap(true)
    preview.sample = CreateSample(preview)
    return preview
end
local function SkinTitle(id)
    return id == "masque" and "Masque" or L(id, Skins.definitions[id] and Skins.definitions[id].label or L("unavailable", "皮肤不可用"))
end
local function PaintSample(sample, display, parent, x, y, empty)
    sample:SetParent(parent)
    sample:SetFrameLevel(parent:GetFrameLevel() + 1)
    sample:ClearAllPoints()
    sample:SetPoint("CENTER", parent, "CENTER", x, y)
    local snapshot = GUI:CompileIconStyle(display, sample.previewSnapshot)
    sample.previewSnapshot = snapshot
    sample:SetIconAppearance({ size = 48, shape = snapshot.shape, border = snapshot.border, zoom = snapshot.zoom })
    sample:SetIconBorderColor(snapshot.borderColor)
    sample.icon:SetShown(not empty)
    sample.background:Show()
    GUI:ApplyIconChrome(sample.previewTarget, snapshot, sample.previewState)
    local width, height = GUI:GetIconAppearanceSize(48, snapshot.shape)
    GUI:ApplyShapeShadow(sample.previewShadow, { enabled = display.iconShadow == true, shape = snapshot.shape,
        color = display.iconShadowColor }, { anchor = sample, width = width, height = height, allowLayout = true })
    sample:Show()
end
local function ShowPreview(owner, id, anchor, override, embedded)
    if not owner or not owner:IsVisible() then return end
    ClosePreview()
    local panel = EnsurePreview()
    local style = override or Style(owner)
    if id and id ~= style.skinId then
        local selection = Skins:WithSelection(style, owner.binding.product, id)
        if selection then style.skinId, style.skinOptions = selection.skinId, selection.skinOptions end
    end
    local display = Skins:ApplyRecipe(Copy(style), owner.binding.product)
    if owner.binding.product == "Flare" then
        display = { iconShape = display.skin, iconBorder = display.border, iconZoom = display.iconZoom,
            iconBorderColor = display.borderColor, iconBackground = display.background,
            iconBackgroundColor = display.background == "transparent" and {0,0,0,0} or display.backgroundColor,
            iconShadow = display.shadow, iconShadowColor = display.shadowColor }
    end
    local showEmpty = owner.binding.product == "Flare" and style.skinId ~= "masque" and style.skinId ~= "native"
    local parent = embedded and popup.previewArea or panel
    local sample = panel.sample
    PaintSample(sample, display, parent, showEmpty and -42 or 0, embedded and 8 or -6, false)
    sample.caption:SetText(L("preview.icon", "图标"))
    sample.caption:SetShown(showEmpty)
    if showEmpty then
        panel.empty = panel.empty or CreateSample(panel)
        PaintSample(panel.empty, display, parent, 42, embedded and 8 or -6, true)
        panel.empty.caption:SetText(L("preview.empty", "空槽"))
        panel.empty.caption:Show()
    end
    panel.note:SetText("")
    if style.skinId == "masque" then
        local context = owner.binding.getContext and owner.binding.getContext() or {}
        local applied = false
        if not (InCombatLockdown and InCombatLockdown()) and context.groupId then
            applied = GUI:ApplyIconSkin(sample, { id = "masque", product = owner.binding.product,
                groupId = context.groupId, groupLabel = context.groupLabel, preview = true,
                buttonType = owner.binding.product == "Halo" and "Aura" or "Action",
                width = 48, height = 48, regions = { Icon = sample.icon },
                hideBuiltin = function()
                    sample:SetIconBorderColor({ 0, 0, 0, 0 })
                    sample.background:Hide()
                    GUI:HideShapeShadow(sample.previewShadow)
                end })
        end
        if not applied then
            sample:Hide()
            panel.note:SetText(L("preview.masque", "选择 Masque 并配置分组皮肤后可预览；战斗中暂停预览。"))
        end
    elseif style.skinId == "native" then
        sample:Hide()
        panel.note:SetText(L("preview.native", "原生外观由游戏按钮模板提供。"))
    end
    previewOwner = owner
    if not embedded then
        panel:SetSize(showEmpty and 188 or 164, style.skinId == "masque" and 138 or (showEmpty and 124 or 112))
        panel.title:SetText(SkinTitle(style.skinId))
        panel:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
        PlaceBeside(panel, anchor or owner)
        panel:Show()
    end
end
local function ClosePopup(owner)
    if not activeOwner or (owner and owner ~= activeOwner) then return end
    local previous = activeOwner
    activeOwner = nil
    CloseMenuOwnedBy(popup)
    ClosePreview(previous)
    popup:Hide()
    popup:ClearAllPoints()
end
local RefreshPopup
local function CommitParameter(key, value)
    local owner = activeOwner
    if not owner then return end
    local style = Style(owner)
    local options = Skins:WithParameter(style, owner.binding.product, key, value)
    if not options then return end
    owner.binding.set({ skinId = style.skinId, skinOptions = options })
    owner:Refresh()
end
local function PreviewParameter(key, value)
    local owner = activeOwner
    if not owner then return end
    local style = Style(owner)
    local options = Skins:WithParameter(style, owner.binding.product, key, value)
    if options then style.skinOptions = options; ShowPreview(owner, style.skinId, nil, style, true) end
end
local function EnsurePopup()
    if popup then return popup end
    popup = GUI:CreatePanel(UIParent, { width = 320, height = 284,
        surface = "color.surface.popup", border = "color.popup.border", shadow = true })
    popup:Hide()
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(720)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:EnableKeyboard(true)
    popup:SetPropagateKeyboardInput(true)
    popup:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then ClosePopup() end
    end)
    popup:SetScript("OnHide", function() ClosePopup() end)
    local dismiss = GUI:CreateButtonFrame(popup)
    dismiss:SetFrameLevel(719)
    dismiss:SetAllPoints(UIParent)
    dismiss:SetScript("OnClick", function() ClosePopup() end)
    popup.title = GUI:CreateText(popup, L("adjust", "皮肤调整"), "font.size.md", "color.text.heading")
    popup.title:SetPoint("TOPLEFT", 14, -14)
    popup.title:SetPoint("TOPRIGHT", -42, -14)
    popup.title:SetJustifyH("LEFT")
    popup.previewArea = GUI:CreateFrame(popup, { width = 292, height = 80 })
    popup.previewArea:SetPoint("TOPLEFT", 14, -40)
    local close = GUI.Form:CreateIconButton(popup, { size = 24, icon = GUI:GetSettingsIcon("x"), onClick = function() ClosePopup() end })
    close:SetPoint("TOPRIGHT", -8, -8)
    local reset = GUI.Form:CreateButton(popup, { width = 110, height = 26, text = L("reset", "恢复默认"),
        onClick = function()
            if not activeOwner then return end
            local owner, style = activeOwner, Style(activeOwner)
            local values = style.skinOptions[style.skinId] or {}
            for _, spec in ipairs(Skins:GetParameters(style.skinId, owner.binding.product) or {}) do values[spec.key] = nil end
            style.skinOptions[style.skinId] = values
            owner.binding.set({ skinId = style.skinId, skinOptions = style.skinOptions })
            owner:Refresh()
        end })
    reset:SetPoint("BOTTOMRIGHT", -14, 12)
    popup.rows = {}
    return popup
end
local function AddColorChecker(control)
    local chip, parent = control.chip, control.chipBg
    if not chip or not parent then return end
    for _, corners in ipairs({ { "TOPLEFT", "CENTER" }, { "TOP", "RIGHT" }, { "LEFT", "BOTTOM" }, { "CENTER", "BOTTOMRIGHT" } }) do
        local cell = GUI:CreateTexture(parent, { layer = "BACKGROUND", subLevel = 1 })
        cell:SetPoint("TOPLEFT", chip, corners[1], 0, 0)
        cell:SetPoint("BOTTOMRIGHT", chip, corners[2], 0, 0)
        GUI:SetTexturePaintKey(cell, (corners[1] == "TOPLEFT" or corners[1] == "CENTER") and "color.control.bg" or "color.border.default")
    end
end
local function EnsureRow(spec, id)
    local key = id .. ":" .. spec.type .. ":" .. spec.key
    local row = popup.rows[key]
    if row then return row end
    row = { spec = spec, label = GUI:CreateText(popup, L("parameter." .. spec.key, spec.key), "font.size.md", "color.text.primary") }
    row.label:SetWidth(96)
    row.label:SetWordWrap(false)
    local opts = { width = 184, height = 26, set = function(value) CommitParameter(spec.key, value) end }
    if spec.type == "select" then
        opts.options = function()
            local result = {}
            for _, value in ipairs(spec.choices) do result[#result + 1] = { value = value, text = L("value." .. value, value) } end
            return result
        end
        row.control = GUI.Form:CreateDropdown(popup, opts)
    elseif spec.type == "color" then
        opts.width, opts.hasAlpha, opts.field = 26, true, true
        opts.tooltip = L("parameter." .. spec.key, spec.key)
        opts.preview = function(value) PreviewParameter(spec.key, value) end
        opts.commit = function(value) CommitParameter(spec.key, value) end
        opts.cancel = function() if activeOwner then RefreshPopup(activeOwner) end end
        row.control = GUI.Form:CreateColorPicker(popup, opts)
        AddColorChecker(row.control)
    elseif spec.type == "boolean" then
        opts.width, opts.height = 42, 22
        row.control = GUI.Form:CreateSwitch(popup, opts)
    elseif spec.type == "number" then
        local scale = spec.displayScale or 1
        opts.inline, opts.inputWidth = true, 46
        opts.width = spec.suffix and 170 or 184
        opts.min, opts.max, opts.step, opts.precision = spec.min * scale, spec.max * scale, spec.step * scale, 2
        opts.set = function(value) PreviewParameter(spec.key, value / scale) end
        opts.onCommit = function(_, value) CommitParameter(spec.key, value / scale) end
        row.control = GUI.Form:CreateSlider(popup, opts)
        if spec.suffix then
            row.suffix = GUI:CreateText(row.control, spec.suffix, "font.size.sm", "color.text.secondary")
            row.suffix:SetPoint("LEFT", row.control.inputBox or row.control, "RIGHT", 3, 0)
        end
    end
    popup.rows[key] = row
    return row
end
local function Enabled(spec, values)
    local rule = spec.enabledWhen
    if not rule then return true end
    if rule.values then return rule.values[values[rule.key]] == true end
    if rule.notValue ~= nil then return values[rule.key] ~= rule.notValue end
    return values[rule.key] == rule.value
end
local function BuildRows(specs)
    local byKey, paired, used, rows = {}, {}, {}, {}
    for _, spec in ipairs(specs) do byKey[spec.key] = spec end
    for _, spec in ipairs(specs) do
        if spec.type == "color" and spec.inlineWith and byKey[spec.inlineWith] and not paired[spec.inlineWith] then
            paired[spec.inlineWith], used[spec.key] = spec, true
        end
    end
    for _, spec in ipairs(specs) do
        if not used[spec.key] then rows[#rows + 1] = { main = spec, color = paired[spec.key] } end
    end
    return rows
end
RefreshPopup = function(owner)
    if activeOwner ~= owner then return end
    local style = Style(owner)
    local specs = Skins:GetParameters(style.skinId, owner.binding.product) or {}
    if #specs == 0 then ClosePopup(owner); return end
    local used, rows = {}, BuildRows(specs)
    local values = Skins:Resolve(style, owner.binding.product)
    local function PlaceControl(spec, index, paired, isColor)
        local row = EnsureRow(spec, style.skinId)
        used[row] = true
        row.label:ClearAllPoints(); row.label:SetPoint("TOPLEFT", 14, -139 - (index - 1) * 36)
        row.label:SetShown(not isColor)
        local right = 14 + (paired and 34 or 0) + (spec.suffix and 14 or 0)
        local top = -134 - (index - 1) * 36 - (26 - row.control:GetHeight()) / 2
        row.control:ClearAllPoints(); row.control:SetPoint("TOPRIGHT", -right, top)
        if spec.type == "select" then row.control:SetWidth(paired and 150 or 184) end
        local value = values[spec.key]
        row.control:SetValue(spec.type == "number" and value * (spec.displayScale or 1) or value, true)
        local enabled = Enabled(spec, values)
        row.control:SetDisabled(not enabled)
        if spec.type == "color" then row.control:SetAlpha(enabled and 1 or 0.4) end
        row.control:Show()
    end
    for index, row in ipairs(rows) do
        PlaceControl(row.main, index, row.color ~= nil, false)
        if row.color then PlaceControl(row.color, index, false, true) end
    end
    for _, row in pairs(popup.rows) do
        if not used[row] then row.label:Hide(); row.control:Hide() end
    end
    popup.title:SetText(SkinTitle(style.skinId) .. " · " .. L("adjust", "皮肤调整"))
    popup:SetHeight(134 + #rows * 36 + 42)
    popup:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
    local anchor = owner.binding.getPopupAnchor and owner.binding.getPopupAnchor() or owner
    PlaceBeside(popup, anchor or owner, owner)
    ShowPreview(owner, style.skinId, nil, style, true)
end
function GUI.Form:CreateIconSkinControl(parent, opts)
    local frame = GUI:CreateFrame(parent, { width = opts.width or 220, height = 30 })
    frame.binding = opts
    local function Options()
        local style = Style(frame)
        local list = Skins:GetOptions(style.skinId, opts.native)
        for _, option in ipairs(list) do
            local id = option.value
            option.onEnter = function(row) ShowPreview(frame, id, row) end
            option.onLeave = function() ClosePreview(frame) end
        end
        return list
    end
    frame.dropdown = self:CreateDropdown(frame, { width = (opts.width or 220) - 32, menuWidth = 240, height = 30, options = Options,
        set = function(id)
            ClosePopup(frame)
            local style = Style(frame)
            local selection = Skins:WithSelection(style, opts.product, id)
            if not selection then return end
            opts.set(selection)
            frame:Refresh()
        end })
    frame.dropdown:SetPoint("LEFT", 0, 0)
    frame.gear = self:CreateIconButton(frame, { size = 26, icon = GUI:GetSettingsIcon("settings"), tooltip = L("adjust", "皮肤调整"),
        onClick = function()
            if activeOwner == frame then ClosePopup(frame); return end
            ClosePopup(); ClosePreview(); GUI:CloseDropdown(false)
            local panel = EnsurePopup()
            activeOwner = frame
            panel:Show(); RefreshPopup(frame)
        end })
    frame.gear:SetPoint("RIGHT", 0, 0)
    function frame:Refresh()
        local style = Style(self)
        local context = opts.getContext and opts.getContext() or {}
        if self.contextId ~= context.groupId or self.value ~= style.skinId then ClosePopup(self); ClosePreview(self) end
        self.contextId, self.value = context.groupId, style.skinId
        local parameters = Skins:GetParameters(style.skinId, opts.product)
        local hasParameters = parameters and #parameters > 0
        self.gear:SetShown(hasParameters == true)
        self.dropdown:SetWidth(self:GetWidth() - (hasParameters and 32 or 0))
        self.dropdown:SetValue(style.skinId, true)
        RefreshPopup(self)
    end
    function frame:SetValue() self:Refresh() end
    function frame:ClosePopover() ClosePopup(self); ClosePreview(self); CloseMenuOwnedBy(self) end
    frame:HookScript("OnSizeChanged", function() frame:Refresh() end)
    frame:HookScript("OnHide", function() frame:ClosePopover() end)
    frame.dropdown:HookScript("OnEnter", function() if not activeOwner then ShowPreview(frame, frame.value, frame.dropdown) end end)
    frame.dropdown:HookScript("OnLeave", function() if activeOwner ~= frame then ClosePreview(frame) end end)
    frame.dropdown:HookScript("OnMouseUp", function() ClosePopup(frame); ClosePreview(frame) end)
    frame:Refresh()
    return frame
end
