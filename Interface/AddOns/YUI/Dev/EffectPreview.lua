local YUI = _G.YUI
if not YUI then return end
YUI.Dev = YUI.Dev or {}
local Dev = YUI.Dev
local Lab = { border = "contour", size = 48, content = "icon", parameterEffect = "pixel", parameters = {} }
Dev.EffectPreview = Lab

local SHAPES = {
    { "square", "minimal-square" }, { "roundedSquare", "minimal-rounded" },
    { "flatSquare", "minimal-flat" }, { "flatRounded", "minimal-flat-rounded" },
    { "wideSquare", "minimal-wide-square" }, { "wideRounded", "minimal-wide" },
    { "circle", "minimal-circle" }, { "diamond", "minimal-diamond" },
}
local EFFECTS = { "pixel", "nativeproc", "proc", "assisted", "combined", "soft", "pulse", "button", "autocast", "checked", "flash" }
local BORDERS = { "none", "thin", "medium", "thick", "extraThick", "contour", "shade" }
local WIDTH, HEIGHT, ROW_HEIGHT = 1230, 982, 72
local PARAMETER_EFFECTS = { "pixel", "proc", "soft", "pulse", "button", "autocast" }
local PARAMETERS = {
    { "lines", 1, 20, 1, 6 }, { "thickness", 1, 12, 1, 2 },
    { "speed", 0, 2, 0.05, 0.25 }, { "alpha", 0, 1, 0.05, 0.9 },
    { "size", 0.25, 3, 0.05, 1 },
    { "offsetX", -1, 1, 0.05, 0 }, { "offsetY", -1, 1, 0.05, 0 },
}
local ICON = 135807
local CONTENTS = { "icon", "white", "gray" }
local SOLID_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local GOLD = { 1, 0.72, 0.10, 1 }
local AUTOCAST_GOLD = { 1, 0.9, 0.18, 1 }
local CHECKED_COLOR = { 1, 1, 1, 0.9 }

local function L(key) return YUI.Locale:Get("Core")[key] end
local function Print(key)
    if YUI.Print then YUI:Print(L("dev.effects." .. key)) else print(L("dev.effects." .. key)) end
end
local function InCombat() return InCombatLockdown and InCombatLockdown() end

function Lab:GetParameters(effect)
    local params = self.parameters[effect]
    if not params then
        params = { color = GOLD }
        for _, spec in ipairs(PARAMETERS) do params[spec[1]] = spec[5] end
        if effect == "autocast" then params.color, params.alpha = AUTOCAST_GOLD, 1 end
        self.parameters[effect] = params
    end
    return params
end

function Lab:SetParameter(key, value)
    local params = self:GetParameters(self.parameterEffect)
    if params[key] == value then return end
    params[key] = value
    for _, sample in ipairs(self.samples or {}) do
        if sample.effect == self.parameterEffect and sample.glow then
            sample.glow:SetGlowParams(params)
        end
    end
end

function Lab:SyncParameterControls()
    local params = self:GetParameters(self.parameterEffect)
    for key, control in pairs(self.parameterControls) do
        control:SetValue(params[key], true)
        local enabled = (key ~= "lines" and key ~= "thickness") or self.parameterEffect == "pixel"
        if key == "speed" and self.parameterEffect == "soft" then enabled = false end
        if key == "size" and self.parameterEffect == "pixel" then enabled = false end
        control:SetDisabled(not enabled)
    end
end

function Lab:ApplySampleContent(sample)
    -- Keep the same texture region, mask and anchors for all comparisons.
    local solid = self.content ~= "icon"
    local value = self.content == "gray" and 0.5 or 1
    sample.icon:SetTexture(solid and SOLID_TEXTURE or ICON)
    sample.icon:SetVertexColor(value, value, value, 1)
end

function Lab:SetContent(content)
    if content ~= "icon" and content ~= "white" and content ~= "gray" then return false end
    if self.content == content then return false end
    self.content = content
    self:Stop()
    if self.comparison then self.comparison.frame:Hide() end
    for _, sample in ipairs(self.samples or {}) do self:ApplySampleContent(sample) end
    return true
end

function Lab:StopComparison()
    local comparison = self.comparison
    if not comparison then return end
    local manager, native = comparison.nativeManager, comparison.nativeActive
    comparison.nativeManager, comparison.nativeActive = nil, nil
    if manager and native then
        manager:HideAlert(native)
        local alert = native.SpellActivationAlert
        if alert then
            -- Replay owns the reference lifecycle. Do not rely on a template's
            -- OnHide binding to stop the old loop: its Alpha tracks can suppress
            -- the next entry. Restore only the native template's initial pose.
            alert.ProcStartAnim:Stop()
            alert.ProcLoop:Stop()
            alert.ProcStartFlipbook:Show()
            alert.ProcStartFlipbook:SetAlpha(1)
            alert.ProcLoopFlipbook:Show()
            alert.ProcLoopFlipbook:SetAlpha(0)
        end
    end
    if comparison.yui.proc then YUI.GUI2:SetManagedProcGlowShown(comparison.yui.proc, false) end
end

function Lab:Stop()
    self.playing = false
    self:StopComparison()
    local gui = YUI.GUI2
    for _, sample in ipairs(self.samples or {}) do
        if sample.glow then sample.glow:SetGlowShown(false) end
        if sample.proc then gui:SetManagedProcGlowShown(sample.proc, false) end
        if sample.assisted then gui:SetManagedAssistedHighlightShown(sample.assisted, false) end
        if sample.inner then sample.inner:Hide() end
        if sample.flash then
            sample.flash.FlashAnim:Stop()
            sample.flash:Hide()
        end
    end
    if self.status then self.status:SetText(L("dev.effects.stopped")) end
end

function Lab:Close()
    if self.frame and self.frame:IsShown() then self.frame:Hide()
    else self:Stop() end
    if YUI.Event then YUI.Event:OffOwner(self) end
end

local function CloseForCombat() Lab:Close() end

local function CloseOwnedMenu(frame)
    local gui = YUI.GUI2
    local anchor = gui.DropdownFrame and gui.DropdownFrame.anchor
    while anchor do
        if anchor == frame then gui:CloseDropdown(false); return end
        anchor = anchor.GetParent and anchor:GetParent()
    end
end

function Lab:CreateSample(shape, effect, column, row)
    local gui = YUI.GUI2
    local sample = gui.Application:CreateCooldownIcon(self.frame, {
        size = self.size, shape = shape, border = self.border, variant = "bare", icon = ICON,
        cooldownText = { enabled = false },
    })
    sample:EnableMouse(false)
    sample:SetPoint("CENTER", self.frame, "TOPLEFT", 210 + (column - 1) * 100, -166 - (row - 1) * ROW_HEIGHT)
    sample.cooldown:SetDrawBling(false)
    sample.effect, sample.shape = effect, shape
    self.samples[#self.samples + 1] = sample
    return sample
end

function Lab:Unavailable(sample)
    if not sample.unavailable then
        sample.unavailable = YUI.GUI2:CreateText(sample, L("dev.effects.unavailable"), "font.size.sm", "color.text.secondary")
        sample.unavailable:SetPoint("CENTER", sample, "CENTER")
        sample.unavailable:SetWidth(92)
        sample.unavailable:SetJustifyH("CENTER")
        sample.unavailable:SetWordWrap(true)
    end
    sample.icon:SetAlpha(0.18)
end

function Lab:LayoutSample(sample)
    local gui, shape, effect = YUI.GUI2, sample.shape, sample.effect
    local snapshot = gui:CompileIconStyle({ shape = shape, border = self.border, zoom = 0.08 }, sample.snapshot)
    sample.snapshot = snapshot
    sample:SetIconAppearance({ size = self.size, shape = shape, border = self.border, zoom = snapshot.zoom })
    sample:SetIconBorderColor(snapshot.borderColor)
    self:ApplySampleContent(sample)
    local width, height = gui:GetIconAppearanceSize(self.size, shape)
    local level = sample:GetFrameLevel() + 8
    if effect == "nativeproc" or effect == "combined" then
        sample.proc = sample.proc or gui:CreateManagedProcGlow(sample, shape == "circle" and "circle" or "square",
            width, height, level, "DIALOG", shape)
        if sample.proc then gui:LayoutManagedProcGlow(sample.proc, sample, width, height, level, "DIALOG", shape) end
    end
    if effect == "assisted" or effect == "combined" then
        local assistedLevel = sample:GetFrameLevel() + 15
        sample.assisted = sample.assisted or gui:CreateManagedAssistedHighlight(sample, width, height, assistedLevel, "DIALOG", shape)
        if sample.assisted then
            gui:LayoutManagedAssistedHighlight(sample.assisted, sample, width, height, assistedLevel, "DIALOG", shape)
        else self:Unavailable(sample) end
    elseif effect == "checked" then
        -- Static demonstration of the same inward material/content geometry used by Flare.
        -- No action, checked-state event, or secure button is attached to a preview sample.
        if not sample.inner then
            sample.inner = sample:CreateTexture(nil, "OVERLAY", nil, 5)
        end
        local preset = gui:GetIconAppearancePreset(shape)
        local ratio = (preset.cooldownInsets and preset.cooldownInsets[self.border]) or gui.IconCooldownInsets[self.border]
        local inset = ratio and width * ratio or gui:GetIconBorderThickness(self.border) * gui:GetPixelSize(sample, 1, 1)
        sample.inner:ClearAllPoints()
        sample.inner:SetPoint("TOPLEFT", sample, "TOPLEFT", inset, -inset)
        sample.inner:SetPoint("BOTTOMRIGHT", sample, "BOTTOMRIGHT", -inset, inset)
        gui:PaintIconStateTexture(sample.inner, shape, CHECKED_COLOR)
        local mask = sample.icon.gui2IconAppearanceMask
        if sample.innerMask ~= mask then
            if sample.innerMask then sample.inner:RemoveMaskTexture(sample.innerMask) end
            if mask then sample.inner:AddMaskTexture(mask) end
            sample.innerMask = mask
        end
        sample.inner:Hide()
    elseif effect == "flash" then
        if not sample.flash and not sample.flashUnavailable then
            sample.flash = gui:CreateIconCooldownFlash(sample)
            sample.flashUnavailable = not sample.flash
            if sample.flash then sample.flash.FlashAnim:SetLooping("REPEAT") end
        end
        if sample.flash then
            gui:LayoutIconCooldownFlash(sample.flash, sample.cooldown, snapshot, width, height, level)
            sample.flash:Stop()
        else self:Unavailable(sample) end
    elseif effect ~= "nativeproc" then
        sample.glow = gui:CreateGlow(sample, { style = effect, shape = shape, targetShape = shape,
            color = GOLD, alpha = 0.9, lines = 6, thickness = 2, speed = 0.25, hidden = true,
            restrictedParent = effect == "autocast", trustedWidth = width, trustedHeight = height,
            trustedFrameLevel = level })
        sample.glow:SetGlowParams(self:GetParameters(effect))
    end
end

function Lab:LayoutComparison()
    local comparison = self.comparison
    if not comparison then return end
    local gui = YUI.GUI2
    for _, native in pairs(comparison.nativeBySize) do native:Hide() end
    local native = comparison.nativeBySize[self.size]
    if not native then
        -- Keep each reference at its creation size: the native manager sizes
        -- its alert only once. Reusing one resized host would alter the baseline.
        native = gui:CreateFrame(comparison.frame, { width = self.size, height = self.size, mouse = false })
        native:SetPoint("CENTER", comparison.frame, "TOPLEFT", 175, -156)
        native.icon = gui:CreateTexture(native, { texture = ICON, layer = "ARTWORK" })
        native.icon:SetAllPoints(native)
        native.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        comparison.nativeBySize[self.size] = native
    end
    comparison.native = native
    native:Show()
    self:LayoutSample(comparison.yui)
end

function Lab:CreateComparison()
    if self.comparison then return self.comparison.frame end
    local gui = YUI.GUI2
    local frame = gui:CreatePanel(self.frame, { width = 620, height = 340,
        surface = "color.surface.window", border = "color.border.strong", shadow = true })
    frame:Hide()
    frame:SetPoint("CENTER", self.frame, "CENTER")
    frame:SetFrameLevel(self.frame:GetFrameLevel() + 32)
    frame:EnableMouse(true)
    local sample = gui.Application:CreateCooldownIcon(frame, {
        size = self.size, shape = "square", border = self.border, variant = "bare", icon = ICON,
        cooldownText = { enabled = false },
    })
    sample:EnableMouse(false)
    sample:SetPoint("CENTER", frame, "TOPLEFT", 445, -156)
    sample.cooldown:SetDrawBling(false)
    sample.effect, sample.shape = "nativeproc", "square"
    local comparison = { frame = frame, yui = sample, nativeBySize = {} }
    self.comparison = comparison
    frame:SetScript("OnHide", function() Lab:Stop() end)
    comparison.close = gui:CreateCloseButton(frame, function() frame:Hide() end)
    comparison.close:SetPoint("TOPRIGHT", -14, -14)
    local title = gui:CreateText(frame, L("dev.effects.compareTitle"), "font.size.title", "color.text.heading")
    title:SetPoint("TOPLEFT", 18, -18)
    local note = gui:CreateText(frame, L("dev.effects.compareNote"), "font.size.sm", "color.text.secondary")
    note:SetPoint("TOPLEFT", 18, -50)
    note:SetWidth(584)
    note:SetWordWrap(true)
    for _, item in ipairs({ { "compareNative", 175 }, { "compareYUI", 445 } }) do
        local label = gui:CreateText(frame, L("dev.effects." .. item[1]), "font.size.sm", "color.text.heading")
        label:SetPoint("CENTER", frame, "TOPLEFT", item[2], -220)
        label:SetWidth(200)
        label:SetJustifyH("CENTER")
        label:SetWordWrap(true)
    end
    local hint = gui:CreateText(frame, L("dev.effects.compareHint"), "font.size.sm", "color.text.secondary")
    hint:SetPoint("TOPLEFT", 18, -252)
    hint:SetWidth(584)
    hint:SetWordWrap(true)
    comparison.replay = gui.Form:CreateButton(frame, { width = 106, height = 26,
        text = L("dev.effects.replay"), onClick = function() Lab:Play() end })
    comparison.replay:SetPoint("BOTTOMLEFT", 18, 18)
    comparison.stop = gui.Form:CreateButton(frame, { width = 106, height = 26,
        text = L("dev.effects.stop"), onClick = function() Lab:Stop() end })
    comparison.stop:SetPoint("LEFT", comparison.replay, "RIGHT", 10, 0)
    return frame
end

function Lab:OpenComparison()
    if InCombat() then Print("combat"); return end
    if not (self.frame and self.frame:IsShown()) then return end
    self:Stop()
    local frame = self:CreateComparison()
    self:LayoutComparison()
    frame:Show()
    self:Play()
end

function Lab:PlayComparison()
    local comparison = self.comparison
    local manager = ActionButtonSpellAlertManager
    if manager and type(manager.ShowAlert) == "function" and type(manager.HideAlert) == "function" then
        if comparison.native.unavailable then comparison.native.unavailable:Hide() end
        comparison.native.icon:SetAlpha(1)
        comparison.nativeManager, comparison.nativeActive = manager, comparison.native
        -- The reference goes through the game's manager, without GUI2 glow or
        -- skin adoption, texture replacement, geometry writes or timing changes.
        manager:ShowAlert(comparison.native, false)
    else
        self:Unavailable(comparison.native)
        comparison.native.unavailable:Show()
    end
    if comparison.yui.proc then YUI.GUI2:SetManagedProcGlowShown(comparison.yui.proc, true) end
end

function Lab:Play()
    if not (self.frame and self.frame:IsShown()) then return end
    if InCombat() then self:Close(); Print("combat"); return end
    self:Stop()
    self.playing = true
    if self.comparison and self.comparison.frame:IsShown() then
        self:PlayComparison()
    else
        for _, sample in ipairs(self.samples) do
            if sample.glow then sample.glow:SetGlowShown(true) end
            if sample.proc then YUI.GUI2:SetManagedProcGlowShown(sample.proc, true) end
            if sample.assisted then YUI.GUI2:SetManagedAssistedHighlightShown(sample.assisted, true) end
            if sample.inner then sample.inner:Show() end
            if sample.flash then YUI.GUI2:PlayIconCooldownFlash(sample.flash) end
        end
    end
    self.status:SetText(L("dev.effects.playing"))
end

function Lab:Refresh()
    local playing = self.playing
    self:Stop()
    for _, sample in ipairs(self.samples or {}) do self:LayoutSample(sample) end
    self:LayoutComparison()
    if playing then self:Play() end
end

function Lab:Create()
    if self.frame then return self.frame end
    local gui = YUI.GUI2
    local frame = gui:CreatePanel(UIParent, { name = "YUI_DevEffectPreview", width = WIDTH, height = HEIGHT,
        surface = "color.surface.window", border = "color.border.strong", shadow = true })
    frame:Hide()
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnHide", function()
        Lab:Stop()
        if Lab.comparison then Lab.comparison.frame:Hide() end
        CloseOwnedMenu(frame)
        if YUI.Event then YUI.Event:OffOwner(Lab) end
    end)
    self.frame, self.samples = frame, {}
    if UISpecialFrames then table.insert(UISpecialFrames, "YUI_DevEffectPreview") end
    local title = gui:CreateText(frame, L("dev.effects.title"), "font.size.title", "color.text.heading")
    title:SetPoint("TOPLEFT", 18, -16)
    local note = gui:CreateText(frame, L("dev.effects.note"), "font.size.sm", "color.text.secondary")
    note:SetPoint("TOPLEFT", 18, -46)
    note:SetWidth(550)
    local close = gui:CreateCloseButton(frame, function() Lab:Close() end)
    close:SetPoint("TOPRIGHT", -14, -14)
    local borderLabel = gui:CreateText(frame, L("icon_skin.parameter.border"), "font.size.sm", "color.text.primary")
    borderLabel:SetPoint("TOPLEFT", 18, -85)
    local options = {}
    for _, border in ipairs(BORDERS) do options[#options + 1] = { value = border, text = L("icon_skin.value." .. border) } end
    self.borderControl = gui.Form:CreateDropdown(frame, { width = 136, height = 26, options = options, default = self.border,
        onChange = function(_, value) Lab.border = value; Lab:Refresh() end })
    self.borderControl:SetPoint("TOPLEFT", 74, -78)
    local sizeLabel = gui:CreateText(frame, L("common.size"), "font.size.sm", "color.text.primary")
    sizeLabel:SetPoint("TOPLEFT", 234, -85)
    local sizes = {}
    for _, size in ipairs({ 32, 40, 48, 56 }) do sizes[#sizes + 1] = { value = size, text = tostring(size) } end
    self.sizeControl = gui.Form:CreateDropdown(frame, { width = 88, height = 26, options = sizes, default = self.size,
        onChange = function(_, value) Lab.size = value; Lab:Refresh() end })
    self.sizeControl:SetPoint("TOPLEFT", 288, -78)
    local replay = gui.Form:CreateButton(frame, { width = 106, height = 26, text = L("dev.effects.replay"), onClick = function() Lab:Play() end })
    replay:SetPoint("TOPLEFT", 408, -78)
    local stop = gui.Form:CreateButton(frame, { width = 106, height = 26, text = L("dev.effects.stop"), onClick = function() Lab:Stop() end })
    stop:SetPoint("LEFT", replay, "RIGHT", 10, 0)
    self.comparisonControl = gui.Form:CreateButton(frame, { width = 156, height = 26,
        text = L("dev.effects.compare"), onClick = function() Lab:OpenComparison() end })
    self.comparisonControl:SetPoint("LEFT", stop, "RIGHT", 26, 0)
    local contentLabel = gui:CreateText(frame, L("dev.effects.content"), "font.size.sm", "color.text.primary")
    contentLabel:SetPoint("TOPLEFT", 592, -43)
    local contents = {}
    for _, content in ipairs(CONTENTS) do
        contents[#contents + 1] = { value = content, text = L("dev.effects.content." .. content) }
    end
    self.contentControl = gui.Form:CreateDropdown(frame, { width = 156, height = 26,
        options = contents, default = self.content, onChange = function(_, value) Lab:SetContent(value) end })
    self.contentControl:SetPoint("TOPLEFT", 656, -36)
    local parameterTitle = gui:CreateText(frame, L("dev.effects.parameters"), "font.size.sm", "color.text.heading")
    parameterTitle:SetPoint("TOPLEFT", 1000, -85)
    local effectOptions = {}
    for _, effect in ipairs(PARAMETER_EFFECTS) do
        effectOptions[#effectOptions + 1] = { value = effect, text = L("dev.effects." .. effect) }
    end
    self.parameterControls = {}
    self.effectControl = gui.Form:CreateDropdown(frame, { width = 208, height = 26,
        options = effectOptions, default = self.parameterEffect,
        onChange = function(_, value) Lab.parameterEffect = value; Lab:SyncParameterControls() end })
    self.effectControl:SetPoint("TOPLEFT", 1000, -112)
    for index, spec in ipairs(PARAMETERS) do
        local key = spec[1]
        local label = gui:CreateText(frame, L("dev.effects.parameter." .. key), "font.size.sm", "color.text.primary")
        label:SetPoint("TOPLEFT", 1000, -156 - (index - 1) * 64)
        local control = gui.Form:CreateSlider(frame, { width = 208, inline = true, min = spec[2], max = spec[3],
            step = spec[4], precision = spec[4] < 1 and 2 or 0, default = spec[5],
            onChange = function(_, value) Lab:SetParameter(key, value) end })
        control:SetPoint("TOPLEFT", 1000, -178 - (index - 1) * 64)
        self.parameterControls[key] = control
    end
    local reset = gui.Form:CreateButton(frame, { width = 208, height = 26,
        text = L("dev.effects.resetParameters"), onClick = function()
            for _, spec in ipairs(PARAMETERS) do
                local value = Lab.parameterEffect == "autocast" and spec[1] == "alpha" and 1 or spec[5]
                Lab:SetParameter(spec[1], value)
            end
            Lab:SyncParameterControls()
        end })
    reset:SetPoint("TOPLEFT", 1000, -624)
    local parameterNote = gui:CreateText(frame, L("dev.effects.parameterNote"), "font.size.sm", "color.text.secondary")
    parameterNote:SetPoint("TOPLEFT", 1000, -666)
    parameterNote:SetWidth(208)
    parameterNote:SetWordWrap(true)
    self:SyncParameterControls()
    for column, shape in ipairs(SHAPES) do
        local label = gui:CreateText(frame, L("icon_skin." .. shape[2]), "font.size.sm", "color.text.heading")
        label:SetWidth(96)
        label:SetJustifyH("CENTER")
        label:SetWordWrap(true)
        label:SetPoint("CENTER", frame, "TOPLEFT", 210 + (column - 1) * 100, -124)
    end
    for row, effect in ipairs(EFFECTS) do
        local label = gui:CreateText(frame, L("dev.effects." .. effect), "font.size.sm", "color.text.primary")
        label:SetWidth(140)
        label:SetWordWrap(true)
        label:SetPoint("LEFT", frame, "TOPLEFT", 18, -166 - (row - 1) * ROW_HEIGHT)
        for column, shape in ipairs(SHAPES) do self:CreateSample(shape[1], effect, column, row) end
    end
    self.status = gui:CreateText(frame, "", "font.size.sm", "color.text.secondary")
    self.status:SetPoint("BOTTOMLEFT", 18, 44)
    local footer = gui:CreateText(frame, L("dev.effects.footer"), "font.size.sm", "color.text.secondary")
    footer:SetPoint("BOTTOMLEFT", 18, 16)
    footer:SetWidth(WIDTH - 36)
    footer:SetWordWrap(true)
    self:Refresh()
    return frame
end

function Lab:Open()
    if InCombat() then Print("combat"); return end
    local gui = YUI.GUI2
    if not (gui and gui.Form and gui.Application and gui.CreateGlow and gui.CreateManagedProcGlow) then
        Print("notLoaded"); return
    end
    local frame = self:Create()
    frame:SetScale(math.min(1, (UIParent:GetWidth() - 32) / WIDTH, (UIParent:GetHeight() - 32) / HEIGHT))
    frame:Show()
    if YUI.Event then
        YUI.Event:OffOwner(self)
        YUI.Event:On("PLAYER_REGEN_DISABLED", CloseForCombat, self)
    end
    if self.content == "icon" then self:Play() else self:Stop() end
end

function Dev:HandleEffectPreview(args)
    local text = tostring(args or ""):match("^%s*(.-)%s*$"):lower()
    local command, action = text:match("^(%S+)%s*(.-)$")
    if command ~= "effects" then return false end
    if action == "" or action == "on" then Lab:Open()
    elseif action == "off" then Lab:Close()
    elseif action == "stop" then Lab:Stop()
    elseif action == "play" then Lab:Play()
    else Print("usage") end
    return true
end
