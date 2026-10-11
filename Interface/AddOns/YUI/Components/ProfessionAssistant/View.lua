local _, YUI = ...
if not YUI.IsForever then return end
local GUI, M = YUI.GUI2, YUI.ProfessionAssistantModel
local L = YUI.Locale:Get("ProfessionAssistant")
local View = {}
YUI.ProfessionAssistantView = View
local function Color(quality)
    local c = ITEM_QUALITY_COLORS[quality or 2]
    return c.r, c.g, c.b
end
local function HideTooltip() GameTooltip:Hide() end
local GLASS_TEXTURE = YUI.Assets:Component("ProfessionAssistant", "BOEGlass.tga")
local NEXT_BORDER = { 1, .78, .12, 1 }
local function PaintField(field, hover)
    local palette = field.professionPalette
    if not palette then return end
    local panel = field.bg or field.gui2Bg
    if panel then
        panel:SetBackdropColor(unpack(palette.background))
        GUI:SetBorderColor(panel, hover and palette.accent or palette.border)
    end
    local arrow = field.arrow and (field.arrow.icon or field.arrow)
    if arrow and arrow.SetVertexColor then
        arrow:SetColorTexture(unpack(palette.accent))
        arrow:SetVertexColor(1, 1, 1, 1)
        arrow:SetTexCoord(0, 1, 0, 1)
        arrow:SetSize(6, 6)
    end
end

-- Use the same resolved window palette for every interactive control.
function View.ApplyControls(frame, context)
    if InCombatLockdown() then return end
    local native = context.source == "native"
    local background = context.background or { GUI:GetColor("color.control.bg") }
    local border = context.border or { GUI:GetColor("color.border.default") }
    local r, g, b = GUI.WindowAppearance:GetAccentColor(context)
    local accent = r and { r, g, b, 1 } or { GUI:GetColor("color.text.accent") }
    if native then
        background, border, accent = { .12, .10, .07, 1 }, { .48, .40, .24, 1 }, { 1, .82, 0, 1 }
    end
    for _, control in ipairs(frame.controls or {}) do
        local button = control.modern
        button.gui2SurfaceToken, button.gui2BorderToken = background, border
        button.gui2HoverSurfaceToken, button.gui2HoverBorderToken = background, accent
        button.gui2PressedSurfaceToken, button.gui2PressedBorderToken = background, accent
        button.gui2TextColorKey, button.gui2HoverTextColorKey = accent, accent
        button.gui2PressedTextColorKey = accent
        button:RefreshTheme()
        GUI.WindowAppearance:ApplyFont(button.text, context)
        control.native:SetShown(native)
        button:SetShown(not native)
        control:Feedback("normal")
    end
    frame.nativeClose:SetShown(native)
    frame.close:SetShown(not native)
    -- Keep the provider font family, but retain the dialog's title hierarchy.
    local font = frame.heading:GetFont()
    frame.heading:ClearAllPoints()
    frame.heading:SetPoint("TOP", 0, native and -6 or -16)
    frame.heading:SetFont(font, native and 14 or 18, "")
    frame.heading:SetShadowOffset(1, -1)
    frame.heading:SetTextColor(unpack(accent))
    frame.heading.RefreshTheme = function()
        GUI.WindowAppearance:ApplyFont(frame.heading, context)
        local family = frame.heading:GetFont()
        frame.heading:SetFont(family, native and 14 or 18, "")
        frame.heading:SetTextColor(unpack(accent))
        frame.heading:SetShadowOffset(1, -1)
    end
    for _, label in ipairs(frame.labels or {}) do
        label.RefreshTheme = function(self)
            GUI.WindowAppearance:ApplyFont(self, context)
            local family = self:GetFont()
            self:SetFont(family, 16, "")
            self:SetTextColor(GUI:GetColor("color.text.primary"))
            self:SetShadowColor(0, 0, 0, 1)
            self:SetShadowOffset(1, -1)
        end
        label:RefreshTheme()
    end
    for _, button in ipairs(frame.textControls or {}) do
        button.professionAccent = accent
        GUI.WindowAppearance:ApplyFont(button.text, context)
        button:RefreshTheme()
    end
    for _, field in ipairs(frame.fields or {}) do
        field.professionPalette = { background = background, border = border, accent = accent }
        PaintField(field)
        GUI.WindowAppearance:ApplyFont(field.text or field, context)
    end
    if frame.scroll then
        frame.scroll.professionPalette = { border = border, accent = accent }
        frame.scroll:RefreshTheme()
    end
end

function View.Raise(view)
    if InCombatLockdown() then return end
    local settings = _G.YUI_SettingsFrame
    local level = math.max(120, settings and settings:GetFrameLevel() + 20 or 120)
    -- Settings is a toplevel DIALOG and can raise itself during the launch click.
    -- Give the visible windows their own strata; raising only the secure root
    -- does not establish the intended ordering of the completed child tree.
    for _, frame in ipairs({ view.left, view.right }) do
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetFrameLevel(level)
        frame:SetToplevel(true)
    end
end

function View.RefreshAppearance(view)
    if InCombatLockdown() then return end
    GUI.WindowAppearance:Refresh(view.left)
    GUI.WindowAppearance:Refresh(view.right)
end

function View.Tooltip(slot, hint)
    GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
    if slot.item then
        if slot.item.preview then GameTooltip:SetText(slot.item.name)
        else GameTooltip:SetHyperlink(slot.item.link) end
        if hint then GameTooltip:AddLine(hint, 1, .82, 0, true) end
    elseif slot.result then
        GameTooltip:SetText(L["done"])
        if #slot.result == 0 then GameTooltip:AddLine(L["noResult"], 1, .82, 0, true) end
        for _, material in ipairs(slot.result) do
            GameTooltip:AddLine(string.format("%s × %d", material.link, material.count), 1, 1, 1, true)
        end
    end
    GameTooltip:Show()
end

local function Slot(parent, size, click)
    local slot = GUI:CreateIconSlot(parent, { size = size, onClick = click, animate = false, crop = true })
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot:SetScript("OnClick", click)
    -- Item quality and queue position own the border, not generic button focus.
    slot:SetScript("OnMouseDown", nil)
    slot:SetScript("OnMouseUp", nil)
    slot.glass = slot:CreateTexture(nil, "OVERLAY", nil, 1)
    slot.glass:SetPoint("TOPLEFT", 1, -1)
    slot.glass:SetPoint("BOTTOMRIGHT", -1, 1)
    slot.glass:SetTexture(GLASS_TEXTURE)
    -- The material's bevel starts about six texels inside its 128px canvas.
    -- Trim that padding so it meets the inside of the quality/target border.
    slot.glass:SetTexCoord(.045, .955, .045, .955)
    slot.glass:SetBlendMode("ADD")
    slot.glass:SetAlpha(1)
    -- A static upper reflection remains visible over dark, low-resolution icons.
    -- It fades before the center; the item artwork and quality rim stay clear.
    slot.glassWash = slot:CreateTexture(nil, "OVERLAY", nil, 0)
    slot.glassWash:SetPoint("TOPLEFT", 1, -1)
    slot.glassWash:SetPoint("TOPRIGHT", -1, -1)
    slot.glassWash:SetHeight(size * .35)
    slot.glassWash:SetColorTexture(1, 1, 1, 1)
    slot.glassWash:SetGradient("VERTICAL", CreateColor(.55, .78, 1, 0), CreateColor(.75, .9, 1, .32))
    slot.ilvl = GUI:CreateText(slot, "", "font.size.md", "color.text.primary")
    slot.ilvl:SetDrawLayer("OVERLAY", 5)
    slot.ilvl:SetPoint("TOPRIGHT", -3, -3)
    local font = slot.ilvl:GetFont()
    slot.ilvl:SetFont(font, size > 60 and 17 or 13, "OUTLINE")
    slot.ilvl:SetShadowColor(0, 0, 0, 1)
    slot.ilvl:SetShadowOffset(1, -1)
    slot.shade = slot:CreateTexture(nil, "OVERLAY", nil, 3)
    slot.shade:SetAllPoints()
    slot.shade:SetColorTexture(0, 0, 0, .6)
    slot.check = slot:CreateTexture(nil, "OVERLAY", nil, 4)
    slot.check:SetSize(size * .5, size * .5)
    slot.check:SetPoint("CENTER")
    slot.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    slot:SetScript("OnLeave", HideTooltip)
    return slot
end

local function Paint(slot, item, selected, nextTarget)
    slot.item, slot.result = item, nil
    slot:SetIcon(item and item.icon or nil)
    slot.icon:SetShown(item ~= nil)
    slot.glass:SetShown(item and item.boe or false)
    slot.glassWash:SetShown(item and item.boe or false)
    local border = nextTarget and "extraThick" or "thin"
    if slot.targetBorder ~= border then
        slot.targetBorder = border
        slot:SetIconAppearance({ border = border })
    end
    slot.ilvl:SetText(item and item.level or "")
    slot.ilvl:SetAlpha(selected and .45 or 1)
    if item then
        local r, g, b = Color(item.quality)
        slot:SetIconBorderColor(nextTarget and NEXT_BORDER or { r, g, b, 1 })
        slot.ilvl:SetTextColor(r, g, b)
    else slot:SetIconBorderColor("color.border.default") end
    slot.shade:SetShown(selected == true)
    slot.check:SetShown(selected == true)
end

function View.Create(callbacks)
    -- The state driver hides secure descendants on the combat transition in C.
    local root = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    root:SetAllPoints(UIParent)
    root:SetFrameStrata("DIALOG")
    root:SetAttribute("_onstate-combat", [[if newstate == "1" then self:Hide() end]])
    local view = { root = root, queue = {}, inventory = {}, offset = 0 }
    -- An unprotected, non-input proxy lets the native Escape handler close the
    -- secure dialog without installing an OnKeyDown listener on either window.
    view.escape = GUI:CreateFrame(UIParent, { name = "YUIProfessionAssistantEscape", width = 1, height = 1, mouse = false, hidden = true })
    table.insert(UISpecialFrames, "YUIProfessionAssistantEscape")
    view.escape:SetScript("OnHide", function()
        if view.root:IsShown() and view.left:IsShown() then callbacks.close() end
    end)
    local function Window(title)
        local frame = GUI:CreateFrame(root, { width = 330, height = 420, movable = true, clamped = true })
        frame:EnableMouse(true)
        frame:SetScript("OnMouseDown", function() View.Raise(view); if view.level then view.level:ClearFocus() end end)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
        frame:SetScript("OnDragStop", function(self) if not InCombatLockdown() then self:StopMovingOrSizing() end end)
        local heading = GUI:CreateText(frame, title, "font.size.lg", "color.text.accent")
        heading:SetPoint("TOP", 0, -16)
        frame.heading, frame.controls = heading, {}
        local close = GUI:CreateButtonFrame(frame, { width = 24, height = 24 })
        for _, angle in ipairs({ math.pi / 4, -math.pi / 4 }) do
            local stroke = GUI:CreateTexture(close, { layer = "ARTWORK" })
            stroke:SetColorTexture(.85, .85, .85, 1)
            stroke:SetSize(13, 2)
            stroke:SetPoint("CENTER")
            stroke:SetRotation(angle)
        end
        close:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        close:SetPoint("TOPRIGHT", -3, -3)
        close:SetScript("OnClick", callbacks.close)
        frame.close = close
        frame.nativeClose = GUI:CreateButtonFrame(frame, { template = "UIPanelCloseButton", width = 24, height = 24 })
        frame.nativeClose:SetPoint("TOPRIGHT", -2, 1)
        frame.nativeClose:SetScript("OnClick", callbacks.close)
        frame:Hide()
        return frame
    end
    view.left = Window(L["disenchant"])
    view.right = Window(L["inventory"])
    view.left:HookScript("OnShow", function() View.Raise(view); view.escape:Show() end)
    view.left:HookScript("OnHide", function() view.escape:Hide() end)
    view.left:SetPoint("CENTER", UIParent, "CENTER", -170, 0)
    view.right:SetPoint("TOPLEFT", view.left, "TOPRIGHT", 10, 0)
    for i = 1, 9 do
        local index = i
        local slot = Slot(view.left, 72, function(_, button)
            view.level:ClearFocus()
            if button == "LeftButton" or button == "RightButton" then callbacks.remove(index); HideTooltip() end
        end)
        slot:SetPoint("TOPLEFT", 45 + ((i - 1) % 3) * 84, -73 - math.floor((i - 1) / 3) * 84)
        slot:SetScript("OnEnter", function(self) View.Tooltip(self, self.item and L["removeHint"]) end)
        slot.materials = {}
        slot.doneLabel = GUI:CreateText(slot, L["done"], "font.size.sm", "color.text.accent")
        slot.doneLabel:SetPoint("TOP", 0, -3)
        for j = 1, 4 do
            local material = GUI:CreateIconSlot(slot, { size = 23, animate = false, crop = true, countSink = true })
            material.count.RefreshTheme = function(self)
                local font = self:GetFont()
                self:SetFont(font, 16, "OUTLINE")
                self:SetTextColor(1, 1, 1, 1)
                self:SetShadowColor(0, 0, 0, 1)
                self:SetShadowOffset(1, -1)
            end
            material.count:RefreshTheme()
            material:EnableMouse(true)
            material:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.link then GameTooltip:SetHyperlink(self.link) end
                if self.more then View.Tooltip(slot) else GameTooltip:Show() end
            end)
            material:SetScript("OnLeave", HideTooltip)
            slot.materials[j] = material
        end
        view.queue[i] = slot
    end
    view.clear = GUI:CreateButtonFrame(view.left, { width = 48, height = 22 })
    view.clear:SetPoint("TOPRIGHT", -45, -44)
    view.clear.text = GUI:CreateText(view.clear, L["queue.clear"], "font.size.md", "color.text.accent")
    view.clear.text:SetPoint("RIGHT")
    view.clear.RefreshTheme = function(self)
        local font = self.text:GetFont()
        self.text:SetFont(font, 14, "")
        if not self:IsEnabled() then self.text:SetTextColor(GUI:GetColor("color.text.disabled"))
        elseif self.hovered then self.text:SetTextColor(GUI:GetColor("color.text.primary"))
        else self.text:SetTextColor(unpack(self.professionAccent or { GUI:GetColor("color.text.accent") })) end
    end
    view.clear.text.RefreshTheme = function() view.clear:RefreshTheme() end
    view.clear:SetScript("OnEnter", function(self) self.hovered = true; self:RefreshTheme() end)
    view.clear:SetScript("OnLeave", function(self) self.hovered = false; self:RefreshTheme() end)
    view.clear:SetScript("OnHide", function(self) self.hovered = false end)
    view.clear:SetScript("OnClick", function() view.level:ClearFocus(); callbacks.clear(); HideTooltip() end)
    view.left.textControls = { view.clear }
    view.devAdd = GUI:CreateButtonFrame(view.left, { width = 170, height = 22 })
    view.devAdd:SetPoint("TOPLEFT", 22, -44)
    view.devAdd.text = GUI:CreateText(view.devAdd, L["dev.add"], "font.size.md", "color.text.accent")
    view.devAdd.text:SetPoint("LEFT")
    view.devAdd.RefreshTheme = view.clear.RefreshTheme
    view.devAdd.text.RefreshTheme = function() view.devAdd:RefreshTheme() end
    view.devAdd:SetScript("OnEnter", function(self) self.hovered = true; self:RefreshTheme() end)
    view.devAdd:SetScript("OnLeave", function(self) self.hovered = false; self:RefreshTheme() end)
    view.devAdd:SetScript("OnHide", function(self) self.hovered = false end)
    view.devAdd:SetScript("OnClick", function()
        if YUI.IsDev == true then view.level:ClearFocus(); callbacks.preview() end
    end)
    view.devAdd:SetShown(YUI.IsDev == true)
    view.left.textControls[#view.left.textControls + 1] = view.devAdd
    local qualityLabel = GUI:CreateText(view.right, L["quality"], "font.size.lg", "color.text.primary")
    qualityLabel:SetPoint("TOPLEFT", 22, -50)
    local options = {}
    for quality = 2, 4 do
        local c = ITEM_QUALITY_COLORS[quality]
        options[#options + 1] = { value = quality, text = c.hex .. L["quality." .. quality] .. "|r" }
    end
    view.quality = GUI:CreateDropdown(view.right, { width = 165, height = 28, options = options,
        get = callbacks.getQuality, set = callbacks.quality })
    view.quality:SetPoint("TOPLEFT", 22, -73)
    local levelLabel = GUI:CreateText(view.right, L["maxLevel"], "font.size.lg", "color.text.primary")
    levelLabel:SetPoint("TOPLEFT", 205, -50)
    view.right.labels = { qualityLabel, levelLabel }
    view.level = GUI:CreateEditBox(view.right, { width = 90, height = 28, text = tostring(UnitLevel("player")) })
    view.level:SetPoint("TOPLEFT", 205, -73)
    view.level:SetNumeric(true)
    view.level:SetMaxLetters(4)
    view.level:HookScript("OnHide", function(self) self:ClearFocus() end)
    view.level:HookScript("OnEnterPressed", function(self) self:ClearFocus() end)
    view.level:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    view.level:HookScript("OnTextChanged", function(self, user) if user then callbacks.level(self:GetText()) end end)
    view.right:EnableMouseWheel(true)
    view.right:SetScript("OnMouseWheel", function(_, delta)
        view.offset = math.max(0, math.min(view.maxOffset or 0, view.offset - delta * 5))
        callbacks.render()
    end)
    for i = 1, 25 do
        local slot = Slot(view.right, 49, function(self, button)
            view.level:ClearFocus()
            if button == "LeftButton" and self.item then callbacks.add(self.item); HideTooltip() end
        end)
        slot:SetPoint("TOPLEFT", 22 + ((i - 1) % 5) * 56, -114 - math.floor((i - 1) / 5) * 51)
        slot:SetScript("OnEnter", function(self) if self.item then View.Tooltip(self, self.selected and L["added"] or L["addHint"]) end end)
        view.inventory[i] = slot
    end
    local function ActionButton(parent, text)
        -- A layout-only owner: native chrome must not sit on a GUI2 backdrop.
        local button = GUI:CreateFrame(parent, { width = 160, height = 32, mouse = false })
        button.modern = GUI:CreateButton(button, text, 160, 32)
        button.modern:SetAllPoints()
        button.native = GUI:CreateButtonFrame(button, { template = "UIPanelButtonTemplate" })
        button.native:SetAllPoints()
        button.native:SetText(text)
        button.SetText = function(self, value) self.modern:SetText(value); self.native:SetText(value) end
        button.Feedback = function(self, state)
            if self.enabled then
                self.native:SetButtonState(state == "pressed" and "PUSHED" or "NORMAL")
                local paint = self.native:GetScript(state == "pressed" and "OnMouseDown" or "OnMouseUp")
                if paint then paint(self.native, "LeftButton") end
            end
            if self.enabled and (state == "hover" or state == "pressed") then self.native:LockHighlight()
            else self.native:UnlockHighlight() end
            self.modern:SetState(self.enabled and state or "disabled")
        end
        button.SetEnabled = function(self, enabled)
            self.enabled = enabled
            self.modern:SetEnabled(enabled)
            self.native:SetEnabled(enabled)
            self:Feedback("normal")
        end
        button:SetEnabled(true)
        parent.controls[#parent.controls + 1] = button
        return button
    end
    view.scroll = GUI:CreateVirtualScrollBar(view.right, { width = 12, height = 253,
        onFirstIndexChanged = function(firstRow)
            if InCombatLockdown() then return end
            view.offset = (firstRow - 1) * 5
            callbacks.render()
        end })
    view.scroll:SetPoint("TOPRIGHT", -8, -114)
    local RefreshScroll = view.scroll.RefreshTheme
    view.scroll.RefreshTheme = function(self)
        RefreshScroll(self)
        local palette = self.professionPalette
        if palette then
            self.gui2VirtualTrack:SetColorTexture(unpack(palette.border))
            self.gui2VirtualThumb:SetColorTexture(unpack(palette.accent))
        end
    end
    view.cast = ActionButton(view.left, L["disenchant"])
    view.cast:SetPoint("BOTTOM", 0, 16)
    view.castHost = GUI.Secure:CreateActionHost(view.cast, { useOnKeyDown = false,
        onEnter = function(_, owner) owner.pointerInside = true; owner:Feedback("hover") end,
        onLeave = function(_, owner) owner.pointerInside = false; owner:Feedback("normal") end })
    -- The secure host receives the hardware click. Drive the actual template's
    -- highlight/pushed states without replacing its textures or secure scripts.
    view.castHost:HookScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then view.cast:Feedback("pressed") end
    end)
    view.castHost:HookScript("OnMouseUp", function()
        view.cast:Feedback(view.cast.pointerInside and "hover" or "normal")
    end)
    view.castHost:HookScript("OnHide", function()
        view.cast.pointerInside = false
        view.cast:Feedback("normal")
    end)
    view.castHost:SetActions({ left = { kind = "spell", spellID = 13262, beforeClick = function(host)
        view.level:ClearFocus()
        callbacks.cast(host)
    end } })
    view.add = ActionButton(view.right, "")
    view.add:SetPoint("BOTTOM", 0, 16)
    local function AddBatch() view.level:ClearFocus(); callbacks.addBatch() end
    view.add.native:SetScript("OnClick", AddBatch)
    view.add.modern:SetScript("OnClick", AddBatch)
    view.right.fields = { view.quality, view.level }
    view.right.scroll = view.scroll
    for _, field in ipairs(view.right.fields) do
        local RefreshField = field.RefreshTheme
        field.RefreshTheme = function(self) RefreshField(self); PaintField(self) end
        local panel = field.bg or field.gui2Bg
        if panel then panel.RefreshTheme = function() PaintField(field) end end
        if field.arrow then field.arrow.RefreshTheme = function() PaintField(field) end end
        field:HookScript("OnEnter", function(self) PaintField(self, true) end)
        field:HookScript("OnLeave", function(self) PaintField(self, false) end)
    end
    for _, frame in ipairs({ view.left, view.right }) do
        GUI.WindowAppearance:Register(frame, { themeProvider = callbacks.theme, heading = frame.heading,
            blizzardWindow = "professions", nativeBorderOverflow = true, role = "profession-assistant", onRefresh = View.ApplyControls })
    end
    root:Hide()
    return view
end

function View.Render(view, state, list, busy)
    view.devAdd:SetShown(YUI.IsDev == true)
    view.devAdd:SetEnabled(not busy)
    view.devAdd:RefreshTheme()
    local nextEntry = M.Next(state)
    local hasEntries = false
    for i = 1, 9 do
        local slot, entry = view.queue[i], state.slots[i]
        if entry then hasEntries = true end
        Paint(slot, entry and not entry.done and entry.item or nil, false, entry ~= nil and entry == nextEntry)
        slot.doneLabel:SetShown(entry and entry.done or false)
        slot.result = entry and entry.done and entry.loot or nil
        local materialCount = math.min(slot.result and #slot.result or 0, 4)
        if slot.materialCount ~= materialCount then
            slot.materialCount = materialCount
            local rows = math.ceil(materialCount / 2)
            for j = 1, materialCount do
                local row, column = math.floor((j - 1) / 2), (j - 1) % 2
                local columns = math.min(2, materialCount - row * 2)
                local widget = slot.materials[j]
                widget:ClearAllPoints()
                -- Center each row and the whole group beneath the status label.
                widget:SetPoint("CENTER", slot, "CENTER", (column - (columns - 1) / 2) * 27,
                    -9 + ((rows - 1) / 2 - row) * 27)
            end
        end
        for j = 1, 4 do
            local widget = slot.materials[j]
            local material = slot.result and slot.result[j]
            widget:SetShown(material ~= nil)
            if material then
                widget:SetIcon(material.icon)
                widget.link, widget.more = material.link, j == 4 and #slot.result > 4
                widget:SetCount(widget.more and ("+" .. (#slot.result - 3)) or material.count)
            end
        end
    end
    view.clear:SetEnabled(hasEntries and not busy)
    view.clear:RefreshTheme()
    view.maxOffset = math.max(0, math.ceil((#list - 25) / 5) * 5)
    view.offset = math.min(view.offset, view.maxOffset)
    view.scroll:SetScrollState(view.offset / 5 + 1, math.ceil(#list / 5), 5, true)
    local available = 0
    for _, item in ipairs(list) do if not M.Contains(state, item.guid) then available = available + 1 end end
    for i, slot in ipairs(view.inventory) do
        local item = list[i + view.offset]
        local selected = item and M.Contains(state, item.guid) ~= nil
        Paint(slot, item, selected)
        slot.selected = selected
        slot:SetShown(item ~= nil)
    end
    view.quality:SetValue(state.quality, true)
    local count = math.min(available, M.Capacity(state))
    view.add:SetText(string.format(L["addBatch"], count))
    view.add:SetEnabled(count > 0 and not busy)
    view.cast:SetEnabled(M.Next(state) ~= nil and not busy and not state.preview)
    view.castHost:EnableMouse(M.Next(state) ~= nil and not busy and not state.preview)
end

function View.PlaceEntry(entry, parent)
    if InCombatLockdown() then return end
    local close = parent.CloseButton or (parent.GetName and _G[(parent:GetName() or "") .. "CloseButton"])
    entry:ClearAllPoints()
    if close then entry:SetPoint("RIGHT", close, "LEFT", -3, 0)
    else entry:SetPoint("TOPRIGHT", -32, -8) end
    -- PortraitFrame chrome sits hundreds of levels above the bag content.
    -- Stay above that chrome and the title's drag handle, within the bag strata.
    local level = parent:GetFrameLevel()
    if close then level = math.max(level, close:GetFrameLevel()) end
    if parent.TitleContainer then level = math.max(level, parent.TitleContainer:GetFrameLevel()) end
    if parent.NineSlice then level = math.max(level, parent.NineSlice:GetFrameLevel()) end
    local strata = parent:GetFrameStrata()
    if entry:GetFrameStrata() ~= strata then entry:SetFrameStrata(strata) end
    if entry:GetFrameLevel() ~= level + 10 then entry:SetFrameLevel(level + 10) end
end

function View.Entry(parent, callbacks)
    local entry = GUI:CreateButtonFrame(parent, { width = 24, height = 24 })
    -- Match the map enhancement button, scaled from its 32px shell to 24px.
    local background = GUI:CreateTexture(entry, { layer = "BACKGROUND" })
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(18.75, 18.75)
    background:SetPoint("TOPLEFT", 1.5, -3)
    -- Keep icon and ring on the same frame: child frames draw above parent textures.
    entry.icon = GUI:CreateIcon(entry, { size = 18, allowTiny = true, crop = true,
        icon = YUI.API.Spell.GetTexture(13262) or 132853 })
    entry.icon:SetPoint("CENTER", -.75, -.75)
    entry.iconMask = entry:CreateMaskTexture(nil, "ARTWORK")
    entry.iconMask:SetTexture(GUI:GetIconAppearanceMask("circle", "none"),
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    entry.iconMask:SetAllPoints(entry.icon)
    entry.icon:AddMaskTexture(entry.iconMask)
    entry.ring = GUI:CreateTexture(entry, { layer = "OVERLAY", subLevel = 1 })
    entry.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    entry.ring:SetSize(40.5, 40.5)
    entry.ring:SetPoint("TOPLEFT")
    entry:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    View.PlaceEntry(entry, parent)
    entry:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    entry:SetScript("OnClick", callbacks.click)
    entry:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["enchanting"])
        GameTooltip:AddLine(L["entryHint"], 1, .82, 0, true)
        GameTooltip:Show()
    end)
    entry:SetScript("OnLeave", HideTooltip)
    return entry
end
