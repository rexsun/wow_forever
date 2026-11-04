local YUI = _G.YUI
if not (YUI and YUI.GUI2 and YUI.GUI2.FontStyle) then return end
local GUI, Style = YUI.GUI2, YUI.GUI2.FontStyle
local L = YUI.Locale:Get("Core")
local controls = setmetatable({}, { __mode = "k" })
local function T(key) return L["font_style." .. key] end
function Style:CloseColor()
    local session = self.colorSession
    if session and GUI.ColorPicker and GUI.ColorPicker.owner == session.anchor.colorChip then GUI.ColorPicker:Close("cancel") end
    if self.colorSession == session then self.colorSession = nil end
end
function Style:CloseEditor()
    self:CloseColor()
    local editor = self.editor
    if not editor then return end
    -- Cancel while the owner is still visible: setters may request a settings refresh.
    editor.closing = true
    if GUI.ColorPicker and GUI.ColorPicker.owner == editor.fields.color then GUI.ColorPicker:Close("cancel") end
    editor:Hide()
    editor.closing = nil
end
function Style:Close(clearUndo)
    self:CloseEditor()
    if self.copyWindow then self.copyWindow:Hide() end
    if clearUndo then
        self.undo = nil
        for _, binding in pairs(controls) do binding.target = nil end
    end
end
function Style:CloseForProvider(id)
    local target = self.editor and self.editor.target
    if target and target.key:sub(1,#id+1) == id .. ":" then self:Close() end
    target = self.colorSession and self.colorSession.target
    if target and target.key:sub(1,#id+1) == id .. ":" then self:CloseColor() end
end
local companions = setmetatable({}, { __mode = "k" })
function Style:BindValue(frame, key, attribute)
    companions[frame] = { key = key, attribute = attribute }
end
local function PlainText(text)
    return (text:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", ""))
end
-- Display metadata stays outside the copy payload and its stale-value checks.
local function ColorInfo(target, value)
    if target.colorInfo then return target.colorInfo() end
    return { mode = value.color and "custom" or target.capabilities.color and "state" or "dynamic", color = value.color }
end
local function ColorValue(color)
    return string.format("#%02X%02X%02X%02X", math.floor(color[1]*255+.5), math.floor(color[2]*255+.5),
        math.floor(color[3]*255+.5), math.floor((color[4] or 1)*255+.5))
end
local function ClassMarker(chip)
    local mark = GUI:CreateFrame(chip, {width=8,height=8})
    mark:SetPoint("TOPRIGHT", -1, -1); mark:EnableMouse(false)
    GUI:ApplyBackdrop(mark, "color.control.bg")
    for row = 0, 5 do
        local stripe = GUI:CreateTexture(mark, "color.text.primary", "OVERLAY")
        stripe:SetPoint("TOPRIGHT", -1, -row-1); stripe:SetSize(6-row, 1)
    end
    return mark
end
local function ColorHint(info)
    local text = info.mode == "custom" and "" or info.label or T(info.dynamic and "color_dynamic" or "color_" .. info.mode)
    if info.color then text = text ~= "" and text .. " · " .. ColorValue(info.color) or ColorValue(info.color) end
    if info.hint then text = text .. " · " .. info.hint end
    return text
end
Style.MIN_CONTROL_WIDTH = 96
local function LayoutSummary(frame)
    local width = frame:GetWidth()
    if width < Style.MIN_CONTROL_WIDTH then frame:SetWidth(Style.MIN_CONTROL_WIDTH); return end
    local sizeWidth = math.max(22, math.ceil(frame.sizeText:GetStringWidth()))
    local showSize = frame.hasSize ~= false and width >= 120 and width - sizeWidth - 48 >= 48
    frame.sizeText:SetWidth(sizeWidth); frame.sizeText:SetShown(showSize)
    -- Font name yields first; numbers and color chips are never clipped.
    local chipPadding = frame.hasColor == false and 8 or 32
    frame.sizeText:ClearAllPoints(); frame.sizeText:SetPoint("RIGHT", -chipPadding, 0)
    frame.gui2TextRightPadding = showSize and sizeWidth + chipPadding + 8 or chipPadding
    frame.text:ClearAllPoints(); frame.text:SetPoint("LEFT", 8, 0)
    frame.text:SetPoint("RIGHT", frame, "RIGHT", -frame.gui2TextRightPadding, 0)
    frame.text:SetWidth(width - frame.gui2TextRightPadding - 8)
end
local function Summary(frame, target)
    local value = target.read()
    frame.hasSize = target.capabilities.size == true
    frame.hasColor = target.capabilities.color == true or target.colorInfo ~= nil
    frame.text:SetText(target.capabilities.font and Style.FontName(value.font) or T("text"))
    frame.sizeText:SetText(value.size and tostring(value.size) or target.sizePlaceholder or "")
    frame.colorInfo = ColorInfo(target, value)
    local color = frame.colorInfo.color
    local dynamic = frame.colorInfo.dynamic == true or frame.colorInfo.mode == "dynamic"
    frame.colorChip.fill:SetShown(color ~= nil)
    frame.colorChip.unknown:SetShown(color == nil and not dynamic)
    GUI:SetDynamicColorSwatch(frame.colorChip, frame.colorChip.fill, color == nil and dynamic)
    if color then frame.colorChip.fill:SetColorTexture(color[1], color[2], color[3], color[4] or 1) end
    frame.colorChip.classMark:SetShown(frame.colorInfo.mode == "class" or frame.colorInfo.classDriven == true)
    frame.colorChip:SetShown(frame.hasColor == true)
    LayoutSummary(frame)
end
-- Replace only explicitly named fields; retain the surrounding rows, columns and conditions.
function Style:MergeOptions(options, rules)
    local matches, seen = {}, {}
    for _, rule in ipairs(rules) do
        for _, source in ipairs(rule.sources) do matches[source] = rule end
    end
    local function Visit(items)
        if seen[items] then return end
        seen[items] = true
        for index = #items, 1, -1 do
            local item = items[index]
            if item.children then Visit(item.children) end
            if item.fields then Visit(item.fields) end
            if item.retainedFields then Visit(item.retainedFields) end
            if item.options and type(item.options) == "table" and item.type == "group" then Visit(item.options) end
            local rule = matches[item.fontStyleSource]
            if rule and item.type ~= "divider" and item.type ~= "custom" then
                if item.fontStyleSource ~= rule.sources[1] then table.remove(items, index)
                else
                    if item.type == "slider" and item.inline == true then item.inlineLabel = true end
                    item.type, item.fontStyleKey, item.label = "custom", rule.key, rule.label or T("text")
                    -- FontStyle owns the current-profile binding. The replaced scalar
                    -- callbacks must not remain in the retained Form value inventory.
                    item.get, item.set, item.onChange = nil, nil, nil
                    item.onCommit, item.onPreview = nil, nil
                    item.minControlWidth = Style.MIN_CONTROL_WIDTH
                    item.render = function(parent, x, y, width)
                        -- AlignedFields owns its labels; RenderConfig custom rows own theirs.
                        if type(x) ~= "number" then
                            local control=GUI.Form:CreateFontStyle(parent, {key=rule.key,width=y})
                            control:SetDisabled(type(item.disabled)=="function" and item.disabled() or item.disabled==true)
                            return control
                        end
                        local total = item.width or width or 183
                        local inline = item.inlineLabel == true
                        local height = inline and 26 or 46
                        local row = GUI:CreateFrame(parent, {width=total,height=height})
                        row:SetPoint("TOPLEFT", x, y)
                        local label = GUI:CreateText(row, item.label, "font.size.md", "color.text.primary")
                        label:SetPoint("TOPLEFT", 0, 0)
                        local offset = inline and math.min(item.labelWidth or 100, total-Style.MIN_CONTROL_WIDTH) or 0
                        label:SetWidth(inline and offset-8 or total)
                        label:SetWordWrap(false)
                        if inline then label:SetHeight(26); label:SetJustifyV("MIDDLE") end
                        local control = GUI.Form:CreateFontStyle(row, {key=rule.key,
                            width=math.min(item.controlWidth or total-offset,total-offset)})
                        control:SetPoint("TOPLEFT", offset, inline and 0 or -20)
                        control:SetDisabled(type(item.disabled)=="function" and item.disabled() or item.disabled==true)
                        row.label, row.control = label, control
                        return total, height, row
                    end
                end
            end
            if item.type == "row" and #item.children == 0 then table.remove(items,index) end
        end
    end
    Visit(options)
    return options
end
local function Button(parent, text, width, click)
    return GUI.Form:CreateButton(parent, { text = text, width = width, height = 26, onClick = click })
end
local function Panel(width, height)
    local frame = GUI:CreatePanel(UIParent, { width = width, height = height,
        surface = "color.surface.popup", border = "color.popup.border", shadow = true })
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame.dragHandle = GUI:CreateButtonFrame(frame, { width = width - 56, height = 40 })
    frame.dragHandle:SetPoint("TOPLEFT")
    frame.dragHandle:RegisterForDrag("LeftButton")
    frame.dragHandle:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame.dragHandle:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    frame:HookScript("OnHide", function() frame:StopMovingOrSizing() end)
    GUI:EnableEscapeClose(frame, function()
        if frame == Style.editor then Style:CloseEditor() else frame:Hide() end
    end)
    frame:Hide()
    return frame
end
local strataOrder = { BACKGROUND=1, LOW=2, MEDIUM=3, HIGH=4, DIALOG=5, FULLSCREEN=6, FULLSCREEN_DIALOG=7, TOOLTIP=8 }
local function ShowAbove(frame, owner)
    if GUI.CloseDropdown then GUI:CloseDropdown(true) end
    local strata, level = "DIALOG", 0
    -- Settings pages and module inspectors use different roots and levels.
    -- Include every ancestor; an entry's own level alone is insufficient.
    local root = UIParent
    while owner and owner ~= UIParent do
        root = owner
        local current = owner:GetFrameStrata()
        if (strataOrder[current] or 0) > strataOrder[strata] then strata = current end
        level = math.max(level, owner:GetFrameLevel())
        owner = owner:GetParent()
    end
    -- Keep the popup in its owner's frame tree so raising the settings window
    -- also raises the editor. Its screen anchor remains independent for dragging.
    frame:SetParent(root)
    frame:SetFrameStrata(strata)
    frame:SetFrameLevel(level + 20)
    frame:Show()
    if frame ~= Style.editor then GUI:ShowModalScrim(frame, { alpha = 0.28 }) end
end
function Style.FontName(path)
    local media = LibStub and LibStub("LibSharedMedia-3.0", true)
    local fonts = media and media:HashTable("font") or {}
    for name, value in pairs(fonts) do
        if value == path then return YUI.Locale:GetFontDisplayName(name) end
    end
    return path and (path:match("[^\\/]+$") or path) or T("font")
end
function Style:RefreshControls(changed)
    local catalog = not changed and self:Capture()
    for frame, binding in pairs(controls) do
        local related = changed and changed.group.targetsByKey and changed.group.targetsByKey[binding.key]
        if frame:IsShown() and (not changed or binding.key == changed.key or related) then
            local target = related or changed or self:Find(catalog, binding.key)
            binding.target = target
            if target and target.group.current() then
                Summary(frame, target)
            end
        end
    end
    for frame, binding in pairs(companions) do
        if frame:IsShown() and (not changed or binding.key == changed.key) then
            local target = changed or self:Find(catalog, binding.key)
            if target and target.group.current() then
                local value = target.read()
                frame:SetValue(binding.attribute == "colorMode" and ColorInfo(target, value).mode or value[binding.attribute], true)
            end
        end
    end
end
function Style:IsEditing(parent)
    local editor = self.editor
    local owner = self.colorSession and self.colorSession.anchor
        or editor and (editor:IsShown() or editor.closing) and editor.anchor
    while owner do
        if owner == parent then return true end
        owner = owner:GetParent()
    end
    return false
end
function GUI.Form:CreateFontStyle(parent, opts)
    local frame = GUI.Form:CreateButton(parent, { text = "", width = math.max(opts.width or 183, Style.MIN_CONTROL_WIDTH), height = 26,
        tone = "default", textLeftPadding = 8, textRightPadding = 62, justifyH = "LEFT" })
    frame:SetScript("OnClick", function() Style:OpenEditor(opts.key, frame) end)
    frame.text:SetPoint("LEFT", 8, 0)
    frame.text:SetJustifyH("LEFT")
    frame.text:SetWordWrap(false)
    frame.sizeText = GUI:CreateText(frame, "", "font.size.md", "color.text.secondary")
    frame.sizeText:SetPoint("RIGHT", -32, 0); frame.sizeText:SetJustifyH("RIGHT"); frame.sizeText:SetWordWrap(false)
    frame.colorChip = GUI:CreateButtonFrame(frame, { width = 16, height = 16 })
    frame.colorChip:SetPoint("RIGHT", -8, 0)
    GUI:ApplyBackdrop(frame.colorChip, "color.control.bg"); GUI:CreateBorder(frame.colorChip, "color.border.default")
    frame.colorChip.fill = GUI:CreateTexture(frame.colorChip, nil, "ARTWORK")
    frame.colorChip.fill:SetPoint("TOPLEFT", 2, -2); frame.colorChip.fill:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.colorChip.unknown = GUI:CreateText(frame.colorChip, "?", "font.size.sm", "color.text.secondary")
    frame.colorChip.unknown:SetPoint("CENTER")
    frame.colorChip.classMark = ClassMarker(frame.colorChip)
    frame.colorChip:SetScript("OnClick", function()
        Style:OpenColor(opts.key, frame)
    end)
    frame.colorChip:SetScript("OnEnter", function(chip)
        if not frame.colorInfo then return end
        GameTooltip:SetOwner(chip, "ANCHOR_RIGHT")
        GameTooltip:SetText(ColorHint(frame.colorInfo)); GameTooltip:Show()
    end)
    frame.colorChip:SetScript("OnLeave", function() YUI.HideGameTooltip() end)
    local catalog = Style:Capture()
    local target = Style:Find(catalog, opts.key)
    controls[frame] = { target = target, key = opts.key, onClose = opts.onClose }
    local setDisabled = frame.SetDisabled
    function frame:SetDisabled(disabled, ...)
        if disabled and Style.colorSession and Style.colorSession.anchor == self then Style:CloseColor() end
        return setDisabled(self, disabled, ...)
    end
    function frame:SetTarget(key)
        if opts.key ~= key and Style.editor and Style.editor.anchor == self then Style:CloseEditor() end
        if opts.key ~= key and Style.colorSession and Style.colorSession.anchor == self then Style:CloseColor() end
        opts.key = key
        local binding = controls[self]
        binding.key = key
        binding.target = Style:Find(Style:Capture(), key)
        if binding.target and binding.target.group.current() then Summary(self, binding.target)
        else
            self.text:SetText(T("text")); self.sizeText:SetText("")
            self.hasSize, self.hasColor, self.colorInfo = false, false, nil
            self.colorChip:Hide()
            LayoutSummary(self)
        end
    end
    if target then Summary(frame, target) end
    frame:HookScript("OnSizeChanged", function() LayoutSummary(frame) end)
    frame:HookScript("OnShow", function() Style:RefreshControls() end)
    frame:HookScript("OnHide", function()
        if Style.colorSession and Style.colorSession.anchor == frame then Style:CloseColor() end
        if Style.editor and Style.editor.anchor == frame then Style.editor:Hide() end
        controls[frame].target = nil
        frame.colorInfo = nil
        if GameTooltip.GetOwner and (GameTooltip:GetOwner() == frame or GameTooltip:GetOwner() == frame.colorChip) then YUI.HideGameTooltip() end
    end)
    frame:HookScript("OnEnter", function()
        local binding = controls[frame]
        if not binding or not binding.target or not binding.target.group.current() then return end
        local clipped = frame.text:GetStringWidth() > frame.text:GetWidth() + 1
        local hiddenSize = binding.target.capabilities.size and not frame.sizeText:IsShown()
        if not clipped and not hiddenSize then return end
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        local value = binding.target.read()
        GameTooltip:SetText(binding.target.capabilities.font and Style.FontName(value.font) or T("text"))
        if hiddenSize then GameTooltip:AddLine(T("size") .. ": " .. tostring(value.size), 1, 1, 1) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() YUI.HideGameTooltip() end)
    return frame
end
local function FontMedia()
    local media = LibStub and LibStub("LibSharedMedia-3.0", true)
    return media and media:HashTable("font") or {}
end
local function FontKey(path)
    local options = Style.editor and Style.editor.target and Style.editor.target.fontOptions
    options = type(options) == "function" and options() or options
    for _, option in ipairs(options or {}) do
        if option.fontPath == path then return option.value end
    end
    for name, fontPath in pairs(FontMedia()) do
        if fontPath == path then return name end
    end
    return path
end
local function BindPosition(editor)
    if not (editor.target and editor.target.position) then return end
    editor.positionValue = Style.Copy(editor.target.position.read())
    for axis, field in pairs(editor.positionFields or {}) do
        if field:GetValue() ~= editor.positionValue[axis] then field:SetValue(editor.positionValue[axis], true) end
    end
end
local function BindEditor(editor)
    local value = editor.value
    editor.colorInfo = ColorInfo(editor.target, value)
    if editor.colorOnly then return end
    for _, key in ipairs(Style.attributes) do
        local field = editor.fields[key]
        if not (key == "color" and GUI.ColorPicker and GUI.ColorPicker.owner == field) then
            field:SetValue(key == "color" and (editor.colorInfo.color or {1,1,1,1}) or value[key], true)
        end
    end
    local size = editor.fields.size
    if size.inputBox and not size.fontStyleInputGuard then
        size.fontStyleInputGuard = true
        local enter = size.inputBox:GetScript("OnEnterPressed")
        local escape = size.inputBox:GetScript("OnEscapePressed")
        size.inputBox:SetScript("OnEnterPressed", function(box)
            if tonumber(box:GetText()) == nil then BindEditor(editor); box:ClearFocus(); return end
            if enter then enter(box) end
        end)
        size.inputBox:SetScript("OnEscapePressed", function(box)
            if escape then escape(box) end
            BindEditor(editor)
        end)
    end
    local hasSize = editor.target.capabilities.size == true
    local mixed = hasSize and value.size == nil and editor.target.sizePlaceholder
    editor.labels.size:SetText(T("size"))
    if mixed then size:SetMixedValue() end
    size:SetShown(hasSize and not mixed)
    editor.mixedSize:SetShown(mixed and true or false)
    if mixed then
        editor.mixedSize:ClearAllPoints()
        editor.mixedSize:SetPoint("TOPLEFT", size, "TOPLEFT", 0, 0)
        editor.mixedSize:SetWidth(size:GetWidth())
        editor.mixedSize:SetValue(nil, { silent = true, force = true })
    end
    local info = editor.colorInfo
    editor.colorText:SetText(info.mode == "custom" and info.color and ColorValue(info.color) or info.label or T(info.dynamic and "color_dynamic" or "color_" .. info.mode))
    editor.fields.color.classMark:SetShown(info.mode == "class" or info.classDriven == true)
    editor.fields.color.chip:SetShown(info.color ~= nil)
    local dynamic = info.dynamic == true or info.mode == "dynamic"
    editor.fields.color.unknown:SetShown(info.color == nil and not dynamic)
    GUI:SetDynamicColorSwatch(editor.fields.color.chipBg, editor.fields.color.chip, info.color == nil and dynamic)
    BindPosition(editor)
end
function Style:RefreshExternal(key)
    local editor = self.editor
    if editor and editor.target and editor.target.key == key and not editor.writing and editor.target.group.current() then
        editor.value, editor.before = self.Copy(editor.target.read()), editor.target.group.snapshot(editor.target.id)
        BindEditor(editor)
    end
    for frame, binding in pairs(controls) do
        if binding.key == key and frame:IsShown() and binding.target and binding.target.group.current() then
            Summary(frame, binding.target)
        end
    end
end
local function CurrentEditor(editor)
    local target = editor.target
    return target and target.group.current() and Style.Equal(editor.before, target.group.snapshot(target.id))
        and Style.Equal(editor.value, target.read())
end
local function EditStatus(editor, text)
    local status = editor.colorOnly and GUI.ColorPicker and GUI.ColorPicker.frame and GUI.ColorPicker.frame.message or editor.status
    if status then status:SetText(text) end
end
local function WriteEditor(editor, patch, restoreColor)
    if editor.writing or not editor.target then return false end
    if not CurrentEditor(editor) then
        EditStatus(editor, T("stale")); BindEditor(editor); return false
    end
    local target, before = editor.target, Style.Copy(editor.before)
    if patch then
        local proposed, attributes = Style.Copy(editor.value), {}
        for key, value in pairs(patch.values) do proposed[key], attributes[key] = Style.Copy(value), true end
        for key in pairs(patch.reset or {}) do
            proposed[key] = target.parent(key)
            attributes[key] = proposed[key] ~= nil or nil
        end
        local valid, reason = true, nil
        if next(attributes) then valid, reason = Style.Validate(target, proposed, attributes) end
        if not valid then EditStatus(editor, T(reason)); BindEditor(editor); return false end
    end
    editor.writing = true
    local ok, result
    if restoreColor then
        ok, result = pcall(target.group.restore, { [target.id] = restoreColor }, { color = true })
    else
        ok, result = pcall(target.group.apply, { [target.id] = patch })
    end
    local failure
    if not ok or result == false then
        local restored, outcome = false, false
        if target.group.current() then restored, outcome = pcall(target.group.restore, { [target.id] = before }) end
        failure = restored and outcome ~= false and "failed" or "rollback_failed"
    end
    editor.writing = nil
    if editor.target ~= target then return not failure end
    editor.value, editor.before = Style.Copy(target.read()), target.group.snapshot(target.id)
    BindEditor(editor)
    EditStatus(editor, failure and T(failure) or "")
    Style:RefreshControls(target)
    return not failure
end
local function OpenTargetColor(editor, control)
    local picker = GUI.ColorPicker
    if not picker then return end
    picker:Close("cancel")
    if not CurrentEditor(editor) then EditStatus(editor, T("stale")); return false end
    editor.colorBefore = Style.Copy(editor.before)
    control.gui2ColorPendingValue = nil
    local info = ColorInfo(editor.target, editor.value)
    local color, modes, stateDynamic = info.color or {1,1,1,1}
    if editor.target.colorModes then
        modes = {{value="custom",text=T("color_fixed")}}
        for _, mode in ipairs({"class","state"}) do
            if editor.target.colorModes[mode] then
                local metadata = editor.target.colorInfo and editor.target.colorInfo(mode)
                modes[#modes+1] = {value=mode,text=metadata and metadata.label or T("color_"..mode)}
                if mode == "state" and metadata and metadata.dynamic then stateDynamic = true end
            end
        end
    end
    local function Finish(action)
        if not editor.colorOnly then return end
        if Style.colorSession == editor then Style.colorSession = nil end
        local binding = controls[editor.anchor]
        if action ~= "abandon" and binding and binding.onClose and editor.anchor:IsShown() then binding.onClose() end
    end
    picker:Open(control, {
        r=color[1],g=color[2],b=color[3],a=color[4] or 1,hasAlpha=editor.target.hasAlpha~=false,
        modes=modes,mode=info.mode,stateDynamic=stateDynamic,
        resolveColor=function(mode)
            if editor.target.colorInfo then return editor.target.colorInfo(mode).color end
        end,
        preview=function(r,g,b,a,mode)
            local value = mode == "class" and {mode="class",alpha=a}
                or mode == "state" and {mode="state"} or {r,g,b,a}
            if WriteEditor(editor, {values={color=value}}) and control.PreviewColorValue then control:PreviewColorValue(r,g,b,a) end
        end,
        commit=function() editor.colorBefore = nil; BindEditor(editor) end,
        cancel=function()
            local before = editor.colorBefore
            editor.colorBefore = nil
            if before and (not editor.colorOnly or not Style.Equal(before, editor.before)) then WriteEditor(editor, nil, before) end
        end,
        onClose=Finish,
    })
    return true
end

function Style:OpenColor(key, anchor)
    local editor = self.editor
    if editor and editor.anchor == anchor then editor.suppressOwnerClose = true end
    self:CloseEditor()
    if editor then editor.suppressOwnerClose = nil end
    if not anchor:IsShown() or anchor.gui2Disabled then return end
    local target = self:Find(self:Capture(), key)
    if not target then return end
    if not target.capabilities.color then self:OpenEditor(key, anchor); return end
    if not GUI.ColorPicker then return end
    local session = {colorOnly=true,target=target,anchor=anchor,
        value=self.Copy(target.read()),before=target.group.snapshot(target.id)}
    self.colorSession = session
    if not OpenTargetColor(session, anchor.colorChip) then self.colorSession = nil end
end
-- Position is an optional business-owned editor extension, never a font/copy attribute.
local function WritePosition(editor, values, reset, commit)
    local position = editor.target and editor.target.position
    if not position or editor.writing then return false end
    if not CurrentEditor(editor) or not Style.Equal(editor.positionValue, position.read()) then
        editor.status:SetText(T("stale")); return false
    end
    editor.writing = true
    local ok, result
    if reset then ok, result = pcall(position.reset)
    elseif commit then
        if position.commit then ok, result = pcall(position.commit) else ok, result = true, true end
    else ok, result = pcall(position.apply, values) end
    editor.writing = nil
    if not editor.target then return false end
    BindPosition(editor)
    editor.status:SetText(ok and result ~= false and "" or T("failed"))
    return ok and result ~= false
end
local function ResetAll(editor, reset)
    local target = editor.target
    local position = target.position
    if not CurrentEditor(editor) or position and not Style.Equal(editor.positionValue, position.read()) then
        editor.status:SetText(T("stale")); return false
    end
    local before = Style.Copy(editor.before)
    local beforePosition = position and Style.Copy(position.read())
    if not WriteEditor(editor, {values={},reset=reset}) then return false end
    if position and not WritePosition(editor, nil, true) then
        local restored = false
        if target.group.current() then
            local ok, result = pcall(target.group.restore, {[target.id]=before})
            local positionOK, positionResult = pcall(position.apply, beforePosition)
            local commitOK, commitResult = true, true
            if position.commit then commitOK, commitResult = pcall(position.commit) end
            restored = ok and result ~= false and positionOK and positionResult ~= false and commitOK and commitResult ~= false
        end
        editor.value, editor.before = Style.Copy(target.read()), target.group.snapshot(target.id)
        BindEditor(editor); Style:RefreshControls(target)
        editor.status:SetText(T(restored and "failed" or "rollback_failed"))
        return false
    end
    return true
end
local function CreateEditor()
    local editor = Panel(540, 292)
    editor.title = GUI:CreateText(editor.dragHandle, "", "font.size.lg", "color.text.primary")
    editor.title:SetPoint("TOPLEFT", 20, -14)
    editor.title:SetWidth(454); editor.title:SetWordWrap(false); editor.title:SetJustifyH("LEFT")
    local close = GUI:CreateCloseButton(editor.dragHandle, function() Style:CloseEditor() end)
    editor.close = close
    close:ClearAllPoints(); close:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -16, -14)
    editor.status = GUI:CreateText(editor, "", "font.size.sm", "color.text.secondary")
    editor.status:SetPoint("TOPLEFT", 20, -44); editor.status:SetWidth(500); editor.status:SetHeight(28); editor.status:SetWordWrap(true)
    editor.fields, editor.labels = {}, {}
    local function Change(key, value)
        return WriteEditor(editor, { values = { [key] = Style.Copy(value) } })
    end
    local specs = {
        font = { type = "font", width = 270, previewSelectedFont = false, prependOptions = function()
            local options = editor.target and editor.target.fontOptions
            options = editor.target and editor.target.fontOptionsPosition == "last" and {}
                or Style.Copy(type(options)=="function" and options() or options or {})
            local path = editor.value and editor.value.font
            if path and FontKey(path) == path then
                options[#options+1] = { text = Style.FontName(path), value = path, fontPath = path }
            end
            return options
        end, appendOptions = function()
            local target = editor.target
            if not target or target.fontOptionsPosition ~= "last" then return {} end
            return type(target.fontOptions) == "function" and target.fontOptions() or target.fontOptions
        end },
        size = { type = "slider", width = 194, min = 8, max = 40, step = 1, inline = true, inputWidth = 44, instantUpdate = true },
        outline = { type = "dropdown", width = 270, options = {
            { text = T("none"), value = "NONE" }, { text = T("normal"), value = "OUTLINE" }, { text = T("thick"), value = "THICKOUTLINE" } } },
        shadow = { type = "checkbox", width = 112 }, monochrome = { type = "checkbox", width = 180 },
        color = { type = "color", width = 26, hasAlpha = true },
    }
    local positions = { font = {20,-98}, size = {326,-98}, outline = {20,-160}, shadow = {20,-208}, monochrome = {276,-208}, color = {326,-160} }
    local factories = { font = "CreateLSMFontDropdown", dropdown = "CreateDropdown", slider = "CreateSlider", checkbox = "CreateCheckbox", color = "CreateColorPicker" }
    for _, key in ipairs(Style.attributes) do
        local spec, position = specs[key], positions[key]
        spec.set = function(value) Change(key, key == "font" and (FontMedia()[value] or value) or value) end
        spec.get = function()
            local value = editor.value and (editor.value[key] or key == "color" and (editor.colorInfo and editor.colorInfo.color or {1,1,1,1}))
            return key == "font" and FontKey(value) or value
        end
        spec.label = (key == "shadow" or key == "monochrome") and T(key) or nil
        local field = GUI.Form[factories[spec.type]](GUI.Form, editor, spec)
        if key == "font" then
            -- Providers/copies keep paths; the existing font picker keeps media keys.
            local setValue = field.SetValue
            function field:SetValue(value, silent)
                -- Reused editors may acquire a new owner-specific default option
                -- even when the selected key hasn't changed.
                return setValue(self, FontKey(value), silent and {silent=true,force=true} or false)
            end
        end
        if key == "color" then
            field.classMark = ClassMarker(field.chipBg or field)
            field.unknown = GUI:CreateText(field.chipBg, "?", "font.size.sm", "color.text.secondary")
            field.unknown:SetPoint("CENTER")
            field:SetScript("OnClick", function(control)
                OpenTargetColor(editor, control)
            end)
            field:SetScript("OnEnter", function(control)
                if not editor.colorInfo then return end
                GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
                GameTooltip:SetText(ColorHint(editor.colorInfo)); GameTooltip:Show()
            end)
            field:SetScript("OnLeave", function() YUI.HideGameTooltip() end)
        end
        field:SetPoint("TOPLEFT", unpack(position)); editor.fields[key] = field
        if key == "font" or key == "size" or key == "outline" or key == "color" then
            local label = GUI:CreateText(editor, T(key), "font.size.md", "color.text.primary")
            label:SetPoint("TOPLEFT", position[1], position[2] + 21)
            editor.labels[key] = label
        end
    end
    local sizeOptions = {}
    editor.mixedSize = GUI.Form:CreateDropdown(editor, { width = 194,
        getLabel = function() return editor.target and editor.target.sizePlaceholder or "" end,
        options = function()
            local target = editor.target
            if not target then return {} end
            local rangeKey = target.minSize .. ":" .. target.maxSize
            if not sizeOptions[rangeKey] then
                local options = {}
                for size = target.minSize, target.maxSize do options[#options+1] = {text=tostring(size),value=size} end
                sizeOptions[rangeKey] = options
            end
            return sizeOptions[rangeKey]
        end,
        set = function(value)
            if editor.value and editor.value.size == nil then Change("size", value) end
        end })
    editor.mixedSize:Hide()
    editor.colorText = GUI:CreateText(editor, "", "font.size.sm", "color.text.secondary")
    editor.colorText:SetPoint("LEFT", editor.fields.color.chipBg, "RIGHT", 10, 0)
    editor.colorText:SetWidth(158); editor.colorText:SetHeight(editor.fields.color.chipBg:GetHeight())
    editor.colorText:SetJustifyH("LEFT"); editor.colorText:SetJustifyV("MIDDLE"); editor.colorText:SetWordWrap(false)
    local divider = GUI:CreateTexture(editor, "color.border.subtle", "ARTWORK")
    divider:SetPoint("BOTTOMLEFT", 20, 52); divider:SetPoint("BOTTOMRIGHT", -20, 52); divider:SetHeight(GUI.mult or 1)
    editor.positionDivider = GUI:CreateTexture(editor, "color.border.subtle", "ARTWORK")
    editor.positionDivider:SetHeight(GUI.mult or 1); editor.positionDivider:Hide()
    editor.positionLabels, editor.positionPool, editor.positionFields = {}, {}, {}
    for _, axis in ipairs({"x", "y"}) do
        editor.positionLabels[axis] = GUI:CreateText(editor, L["common.offset_" .. axis], "font.size.md", "color.text.primary")
        editor.positionLabels[axis]:Hide()
    end
    local copy = Button(editor, T("copy"), 126, function()
        if GUI.ColorPicker and GUI.ColorPicker.owner == editor.fields.color and not GUI.ColorPicker:Close("confirm") then return end
        Style:OpenCopy(editor.target)
    end)
    copy:SetPoint("BOTTOMLEFT", 20, 14)
    editor.restore = GUI.Form:CreateDropdown(editor, { width = 126, getLabel = function() return T("restore_menu") end,
        options = function()
            local options = { { text = T("restore_all"), value = "all" } }
            if editor.target and editor.target.position then
                options[#options+1] = { text = T("restore_position"), value = "position" }
            end
            for _, key in ipairs(Style.attributes) do
                if editor.target and editor.target.capabilities[key] then options[#options+1] = { text = T(key), value = key } end
            end
            return options
        end,
        set = function(key)
            if not editor.target or not editor.target.parent then return end
            if GUI.ColorPicker and GUI.ColorPicker.owner == editor.fields.color then GUI.ColorPicker:Close("cancel") end
            if key == "position" then
                WritePosition(editor, nil, true)
                editor.restore:SetValue(nil, true)
                return
            end
            local reset = {}
            for _, attr in ipairs(Style.attributes) do
                if editor.target.capabilities[attr] and (key == "all" or key == attr) then reset[attr] = true end
            end
            if key == "all" then ResetAll(editor, reset)
            else WriteEditor(editor, { values = {}, reset = reset }) end
            editor.restore:SetValue(nil, true)
        end })
    editor.restore:SetPoint("BOTTOMRIGHT", -20, 14)
    editor:HookScript("OnHide", function()
        editor.closing = true
        if editor.target and editor.target.position then WritePosition(editor, nil, false, true) end
        if GUI.ColorPicker and GUI.ColorPicker.owner == editor.fields.color then GUI.ColorPicker:Close("cancel") end
        if Style.copyWindow then Style.copyWindow:Hide() end
        local anchor = editor.anchor
        editor.anchor, editor.target, editor.value, editor.before, editor.colorBefore, editor.colorInfo = nil, nil, nil, nil, nil, nil
        editor.positionValue = nil
        editor.closing = nil
        if GUI.CloseDropdown then GUI:CloseDropdown(true) end
        local binding = anchor and controls[anchor]
        if not editor.suppressOwnerClose and binding and binding.onClose and anchor:IsShown() then binding.onClose() end
    end)
    editor.sizeFields = { ["8:40"] = editor.fields.size }
    return editor
end
function Style:OpenEditor(key, anchor, options)
    self:CloseColor()
    local catalog = self:Capture()
    local target = self:Find(catalog, key)
    if not target then return end
    self.editor = self.editor or CreateEditor()
    local editor = self.editor
    if editor.target and editor.target.position then WritePosition(editor, nil, false, true) end
    if not editor:IsShown() then
        editor:ClearAllPoints(); editor:SetPoint("CENTER", UIParent, "CENTER")
    end
    if GUI.ColorPicker and GUI.ColorPicker.owner == editor.fields.color then GUI.ColorPicker:Close("cancel") end
    editor.target, editor.anchor = target, anchor
    editor.value, editor.before = self.Copy(target.read()), target.group.snapshot(target.id)
    editor.title:SetText(target.label .. " · " .. T("title"))
    for _, attr in ipairs(self.attributes) do
        local field = editor.fields[attr]
        field:SetDisabled(not target.capabilities[attr])
        field:SetShown(target.capabilities[attr] == true)
        if editor.labels[attr] then editor.labels[attr]:SetShown(target.capabilities[attr] == true) end
    end
    editor.restore:SetShown(target.parent ~= nil)
    editor.colorText:SetShown(target.capabilities.color == true)
    editor.fields.size:SetDisabled(true)
    -- The target ranges differ. Reuse one slider per range, created on first visit.
    editor.sizeFields = editor.sizeFields or {}
    local rangeKey = target.minSize .. ":" .. target.maxSize
    if target.capabilities.size and not editor.sizeFields[rangeKey] then
        local slider = GUI.Form:CreateSlider(editor, {width=194,min=target.minSize,max=target.maxSize,step=1,inline=true,inputWidth=44,instantUpdate=true,
            get=function()return editor.value and editor.value.size end,
            set=function(value)WriteEditor(editor,{values={size=value}})end})
        slider:SetPoint("TOPLEFT",326,-98);editor.sizeFields[rangeKey]=slider
    end
    for _, slider in pairs(editor.sizeFields) do slider:Hide() end
    editor.fields.size:Hide()
    if target.capabilities.size then
        editor.fields.size = editor.sizeFields[rangeKey]
        editor.fields.size:SetDisabled(false);editor.fields.size:Show()
    end
    local positions = {font={20,-98},size={326,-98},outline={20,-160},color={326,-160},shadow={20,-208},monochrome={276,-208}}
    local partial = not (target.capabilities.font and target.capabilities.size and target.capabilities.outline)
    local slot, bottom = 0, 0
    for _, attr in ipairs({"font","size","outline","color"}) do
        if target.capabilities[attr] then
            local position = positions[attr]
            if partial then
                position = {slot%2==0 and 20 or 326, -98-math.floor(slot/2)*62}
                slot=slot+1
            end
            local field = editor.fields[attr]
            if attr=="font" or attr=="outline" then field:SetWidth(position[1]==326 and 194 or 270) end
            field:ClearAllPoints(); field:SetPoint("TOPLEFT",position[1],position[2])
            if editor.labels[attr] then
                editor.labels[attr]:ClearAllPoints(); editor.labels[attr]:SetPoint("TOPLEFT",position[1],position[2]+21)
            end
            bottom=math.max(bottom,-position[2]+field:GetHeight())
        end
    end
    local checkX, checkY = 20, partial and (-98-math.ceil(slot/2)*62) or -208
    for _, attr in ipairs({"shadow","monochrome"}) do
        if target.capabilities[attr] then
            local field = editor.fields[attr]
            local width = math.min(500, 26 + math.ceil(field.text:GetStringWidth()))
            if checkX > 20 and checkX + width > 520 then checkX, checkY = 20, checkY - 36 end
            field:SetWidth(width); field.text:SetWidth(width-26)
            field:ClearAllPoints(); field:SetPoint("TOPLEFT", checkX, checkY)
            bottom = math.max(bottom, -checkY + field:GetHeight())
            checkX = checkX + width + 20
        end
    end
    for _, field in pairs(editor.positionPool) do field:Hide() end
    for _, label in pairs(editor.positionLabels) do label:Hide() end
    editor.positionFields = {}
    editor.positionDivider:Hide()
    if target.position then
        local position = target.position
        local top = bottom + 32
        local labelWidth = math.ceil(math.max(editor.positionLabels.x:GetStringWidth(), editor.positionLabels.y:GetStringWidth()))
        editor.positionDivider:ClearAllPoints()
        editor.positionDivider:SetPoint("TOPLEFT", 20, -bottom-16)
        editor.positionDivider:SetPoint("TOPRIGHT", -20, -bottom-16)
        editor.positionDivider:Show()
        for index, axis in ipairs({"x", "y"}) do
            local spec = position[axis]
            local poolKey = axis .. ":" .. spec.min .. ":" .. spec.max .. ":" .. (spec.step or 1)
            local field = editor.positionPool[poolKey]
            if not field then
                field = GUI.Form:CreateSlider(editor, {width=236,min=spec.min,max=spec.max,step=spec.step or 1,
                    inline=true,inputWidth=44,instantUpdate=true,
                    get=function() return editor.positionValue and editor.positionValue[axis] end,
                    set=function(value) WritePosition(editor, {[axis]=value}) end,
                    onCommit=function() WritePosition(editor, nil, false, true) end})
                editor.positionPool[poolKey] = field
                if field.inputBox then
                    local enter = field.inputBox:GetScript("OnEnterPressed")
                    field.inputBox:SetScript("OnEnterPressed", function(box)
                        if tonumber(box:GetText()) == nil then BindEditor(editor); box:ClearFocus(); return end
                        if enter then enter(box) end
                    end)
                end
            end
            local x = index == 1 and 20 or 284
            local label = editor.positionLabels[axis]
            label:ClearAllPoints(); label:SetPoint("LEFT", editor, "TOPLEFT", x, -top-field:GetHeight()/2); label:Show()
            field:SetWidth(236-labelWidth-10)
            local _, _, _, inputGap = field.inputBox:GetPoint(1)
            field.slider:SetWidth(math.max(60, field:GetWidth()-field.inputBox:GetWidth()-(inputGap or 10)))
            field:ClearAllPoints(); field:SetPoint("TOPLEFT", x+labelWidth+10, -top); field:Show()
            editor.positionFields[axis] = field
        end
        bottom = top + 26
    end
    editor:SetHeight(partial and math.max(190,bottom+72) or math.max(292,bottom+52))
    BindEditor(editor); self:RefreshControls(target); editor.status:SetText(""); ShowAbove(editor, anchor)
    if options and options.placement == "right" and anchor then
        editor:ClearAllPoints()
        editor:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 10, 0)
        local right = anchor.GetRight and anchor:GetRight()
        local anchorScale = anchor.GetEffectiveScale and anchor:GetEffectiveScale() or 1
        local editorScale = editor.GetEffectiveScale and editor:GetEffectiveScale() or 1
        local screenScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
        if right and UIParent.GetWidth and right * anchorScale + (editor:GetWidth() + 10) * editorScale > UIParent:GetWidth() * screenScale then
            editor:ClearAllPoints(); editor:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -10, 0)
        end
    end
    return editor
end
local function CopyValue(key, value)
    if key == "font" then return Style.FontName(value) end
    if key == "outline" then return T(value == "THICKOUTLINE" and "thick" or value == "OUTLINE" and "normal" or "none") end
    if key == "shadow" or key == "monochrome" then return T(value and "copy_on" or "copy_off") end
    if key == "color" then
        if not value then return T("color_auto") end
        if value.mode == "class" then return T("color_class") .. "  " .. math.floor(value.alpha*100+.5) .. "%" end
        if not Style.Validate({ capabilities = { color = true } }, { color = value }, { color = true }) then return T("invalid") end
        return ColorValue(value)
    end
    return tostring(value)
end
local function CopyAttribute(key)
    return T(key == "monochrome" and "copy_monochrome" or key)
end
local function TargetReason(window, target)
    if not target.group.current() then return T("stale") end
    if window.attributeCount == 0 then return end
    local valid, reason = Style.Validate(target, window.values, window.selectedAttributes)
    if valid then return end
    if reason == "unsupported" then
        local missing = {}
        for _, key in ipairs(Style.attributes) do
            if window.selectedAttributes[key] and not target.capabilities[key] then missing[#missing + 1] = CopyAttribute(key) end
        end
        return string.format(T("copy_target_unsupported"), table.concat(missing, ", "))
    end
    if reason == "size_range" then return string.format(T("copy_target_size"), target.minSize, target.maxSize) end
    return T(reason)
end
local RefreshRows, BindRows
local function RefreshCopy(window)
    window.attributeCount = 0
    for _, key in ipairs(Style.attributes) do
        if window.selectedAttributes[key] then window.attributeCount = window.attributeCount + 1 end
    end
    local selected, blocked, total = 0, 0, 0
    window.targetReasons = {}
    for _, target in ipairs(window.catalog.entries) do
        if target.key ~= window.source.key then
            total = total + 1
            local reason = TargetReason(window, target)
            window.targetReasons[target.key] = reason
            if window.selected[target.key] then
                selected = selected + 1
                if reason then blocked = blocked + 1 end
            end
        end
    end
    local stale = not window.source.group.current()
        or not Style.Equal(window.sourceBefore, window.source.group.snapshot(window.source.id))
        or not Style.Equal(window.values, window.source.read())
    window.selectedCount = selected
    window.apply:SetDisabled(stale or window.attributeCount == 0 or selected == 0 or blocked > 0)
    window.apply:SetText(selected > 0 and string.format(T("copy_to_count"), selected) or T("copy_apply"))
    window.undoButton:SetDisabled(not Style:CanUndo())
    window.counter:SetText(string.format(T("target_count"), total, selected))
    window.note:SetText(window.selectedAttributes.color and T(window.values.color and window.values.color.mode == "class" and "copy_class_help" or "copy_color_help") or "")
    window.note:SetShown(window.note:GetText() ~= "")
    local message = stale and T("stale") or window.result
    if not message then
        if window.attributeCount == 0 then message = T("copy_choose_attributes")
        elseif selected == 0 then message = T("copy_choose_targets")
        elseif blocked > 0 then message = string.format(T("copy_blocked"), blocked)
        else message = "" end
    end
    window.status:SetText(message)
    RefreshRows(window)
end
RefreshRows = function(window)
    local filtered, items = {}, {}
    local query = (window.search:GetText() or ""):lower()
    for _, section in ipairs(window.sections) do
        local matches, selected, compatible = {}, 0, 0
        local groupMatch = section.label:lower():find(query, 1, true)
        for _, target in ipairs(section.targets) do
            if query == "" or groupMatch or PlainText(target.label):lower():find(query, 1, true) then
                matches[#matches + 1] = target; filtered[#filtered + 1] = target
                if window.selected[target.key] then selected = selected + 1 end
                if not window.targetReasons[target.key] then compatible = compatible + 1 end
            end
        end
        if #matches > 0 then
            if window.grouped then
                items[#items + 1] = { section = section, targets = matches, selected = selected, compatible = compatible }
            end
            if not window.grouped or query ~= "" or not window.collapsed[section.group] then
                for _, target in ipairs(matches) do items[#items + 1] = { target = target } end
            end
        end
    end
    window.filtered, window.items = filtered, items
    local searchable = window.grouped
    window.search:SetShown(searchable)
    local targetTop = window.note:IsShown() and 238 or 202
    local listTop = targetTop + (searchable and 62 or 32)
    local visible = math.min(7, math.max(1, #items))
    window:SetHeight(listTop + visible * 30 + 84)
    window.targetTitle:ClearAllPoints(); window.targetTitle:SetPoint("TOPLEFT", 20, -targetTop)
    window.counter:SetWidth(#filtered > 1 and 284 or 390)
    window.counter:ClearAllPoints(); window.counter:SetPoint("TOPRIGHT", #filtered > 1 and -124 or -20, -targetTop)
    window.targetDivider:ClearAllPoints(); window.targetDivider:SetPoint("TOPLEFT", 20, -targetTop + 10)
    window.targetDivider:SetPoint("TOPRIGHT", -20, -targetTop + 10)
    window.search:ClearAllPoints(); window.search:SetPoint("TOPLEFT", 20, -targetTop - 26)
    window.all:ClearAllPoints(); window.all:SetPoint("TOPRIGHT", -20, -targetTop + 5)
    window.all:SetShown(#filtered > 1)
    window.viewport:ClearAllPoints(); window.viewport:SetPoint("TOPLEFT", 20, -listTop)
    window.viewport:SetHeight(visible * 30)
    window.viewport.child:SetHeight(math.max(1, #items * 30))
    GUI:FitScrollContent(window.viewport)
    local range = math.max(0, (#items - visible) * 30)
    window.viewport:SetVerticalScroll(math.min(window.viewport:GetVerticalScroll(), range))
    BindRows(window)
    local compatible, allSelected = 0, true
    for _, target in ipairs(filtered) do
        if not window.targetReasons[target.key] then
            compatible = compatible + 1
            if not window.selected[target.key] then allSelected = false end
        end
    end
    window.all:SetText(T(allSelected and compatible > 0 and "select_none" or "select_all"))
    window.all:SetDisabled(compatible == 0)
    window.status:ClearAllPoints(); window.status:SetPoint("TOPLEFT", 20, -listTop - visible * 30 - 6)
    window.empty:SetShown(#filtered == 0)
    window.empty:ClearAllPoints(); window.empty:SetPoint("TOPLEFT", 20, -listTop)
end
-- Seven rows plus one clipped overscan row: native scrollbar dragging may stop
-- between rows. Scrolling only rebinds this pool, without rebuilding metadata.
BindRows = function(window)
    if not window.items then return end
    local offset = math.floor(window.viewport:GetVerticalScroll() / 30)
    for index, row in ipairs(window.rows) do
        local item = window.items[index + offset]
        row.item, row.target = item, item and item.target
        if item then
            local target, section = item.target, item.section
            local reason = target and window.targetReasons[target.key]
            local text = target and target.label .. (reason and (" · " .. reason) or "")
                or string.format(T("copy_group_count"), section.label, item.selected, #item.targets)
            row.text:SetText(text)
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", window.grouped and (section and 20 or 40) or 0, -(index + offset - 1) * 30)
            row:SetWidth(window.grouped and (section and 452 or 432) or 472)
            row.text:SetWidth(row:GetWidth() - 26)
            row:SetDisabled(target and reason ~= nil and not window.selected[target.key] or section and item.compatible == 0 and item.selected == 0)
            row:SetChecked(target and window.selected[target.key] or section and item.selected == #item.targets, true)
            row.partial:SetShown(section ~= nil and item.selected > 0 and item.selected < #item.targets)
            row.fold:SetShown(section ~= nil)
            if section then
                local searching = window.search:GetText() ~= ""
                row.fold.vertical:SetShown(not searching and window.collapsed[section.group] == true)
                local color = searching and "color.text.disabled" or "color.text.primary"
                GUI:SetTexturePaintKey(row.fold.horizontal, color)
                GUI:SetTexturePaintKey(row.fold.vertical, color)
                row.fold:SetDisabled(searching)
            end
            row:Show()
        else row:Hide() end
    end
end
local function ToggleTargets(window, targets)
    local allSelected = true
    for _, target in ipairs(targets) do
        if not window.targetReasons[target.key] and not window.selected[target.key] then allSelected = false; break end
    end
    for _, target in ipairs(targets) do
        if allSelected or not window.targetReasons[target.key] then window.selected[target.key] = not allSelected end
    end
    window.result = nil; RefreshCopy(window)
end
local function TruncatedTooltip(frame, extra)
    frame:HookScript("OnEnter", function()
        local content = extra and extra()
        if not content and frame.text:GetStringWidth() > frame.text:GetWidth() + 1 then content = frame.text:GetText() end
        if not content then return end
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT"); GameTooltip:SetText(content); GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() YUI.HideGameTooltip() end)
    frame:HookScript("OnHide", function()
        if GameTooltip.GetOwner and GameTooltip:GetOwner() == frame then YUI.HideGameTooltip() end
    end)
end
local function CreateCopyWindow()
    local window = Panel(540, 328)
    local refreshTheme = window.RefreshTheme
    window.RefreshTheme = function(self)
        if refreshTheme then refreshTheme(self) end
        local r, g, b = GUI:GetColor("color.surface.popup")
        self:SetBackdropColor(r, g, b, 1)
    end
    window:HookScript("OnShow", window.RefreshTheme)
    window:RefreshTheme()
    window.title = GUI:CreateText(window.dragHandle, T("copy_title"), "font.size.lg", "color.text.primary")
    window.title:SetPoint("TOPLEFT", 20, -14)
    local close = GUI:CreateCloseButton(window.dragHandle, function() window:Hide() end)
    close:ClearAllPoints(); close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -16, -14)
    local function Text(value, size, tone, x, y, width)
        local text = GUI:CreateText(window, value, size, tone)
        text:SetPoint("TOPLEFT", x, y); text:SetWidth(width); text:SetJustifyH("LEFT"); text:SetWordWrap(false)
        return text
    end
    window.sourceLabel = Text("", "font.size.md", "color.text.secondary", 20, -44, 500)
    Text(T("copy_contents"), "font.size.md", "color.text.primary", 20, -76, 500)
    window.note = Text("", "font.size.sm", "color.text.secondary", 20, -186, 500)
    window.note:SetHeight(28); window.note:SetWordWrap(true)
    window.attributes = {}
    for index, key in ipairs(Style.attributes) do
        local options = { label = CopyAttribute(key), width = 240, height = 26,
            set = function(value)
                window.selectedAttributes[key] = value; window.result = nil; RefreshCopy(window)
            end }
        local field = GUI.Form:CreateCheckbox(window, options)
        field.copyOptions = options
        field:SetPoint("TOPLEFT", 20 + ((index - 1) % 2) * 260, -98 - math.floor((index - 1) / 2) * 28)
        TruncatedTooltip(field, function()
            if key == "monochrome" then return T("copy_monochrome_help") end
            if key == "color" then return window.colorReason end
        end)
        window.attributes[key] = field
    end
    window.search = GUI.Form:CreateEditBox(window, { width = 500, height = 26, placeholder = T("search") })
    window.search:SetPoint("TOPLEFT", 20, -180)
    window.search:HookScript("OnTextChanged", function()
        if window.catalog and window.targetReasons then window.viewport:SetVerticalScroll(0); RefreshRows(window) end
    end)
    local all = Button(window, T("select_all"), 90, function()
        ToggleTargets(window, window.filtered)
    end)
    all.gui2Tone = "default"; all:RefreshTheme()
    window.all = all
    window.targetTitle = Text(T("copy_targets"), "font.size.md", "color.text.primary", 20, -212, 90)
    window.counter = Text("", "font.size.sm", "color.text.secondary", 120, -212, 360)
    window.counter:SetJustifyH("RIGHT")
    window.targetDivider = GUI:CreateTexture(window, "color.border.default", "ARTWORK")
    window.targetDivider:SetAlpha(0.5)
    window.targetDivider:SetHeight(GUI.mult or 1)
    window.empty = Text(T("no_targets"), "font.size.md", "color.text.secondary", 20, -244, 500)
    window.viewport = GUI:CreateScrollFrame(window, { width = 480, height = 210, childWidth = 480, mouseWheel = true })
    window.viewport:HookScript("OnVerticalScroll", function() BindRows(window) end)
    local function Scroll(_, delta)
        if window.items then
            local range = math.max(0, #window.items * 30 - window.viewport:GetHeight())
            local value = math.max(0, math.min(range, window.viewport:GetVerticalScroll() - delta * 90))
            local bar = window.viewport.gui2ScrollBar
            if bar then bar:SetValue(value) else window.viewport:SetVerticalScroll(value) end
        end
    end
    window.viewport:SetScript("OnMouseWheel", Scroll)
    window.rows = {}
    for index = 1, 8 do
        local row = GUI.Form:CreateCheckbox(window.viewport.child, { width = 472, height = 28 })
        -- Draw signs as textures: the active UI font may not contain Unicode minus.
        local stroke = 2 * (GUI.mult or 1)
        row.partial = GUI:CreateTexture(row.box, "color.text.primary", "OVERLAY")
        row.partial:SetSize(8, stroke)
        row.partial:SetPoint("CENTER"); row.partial:Hide()
        row.fold = GUI.Form:CreateButton(row, { width = 18, height = 24, tone = "default", onClick = function()
            local section = row.item and row.item.section
            if section and window.search:GetText() == "" then
                window.collapsed[section.group] = not window.collapsed[section.group]; RefreshRows(window)
            end
        end })
        row.fold:SetPoint("RIGHT", row, "LEFT", -2, 0)
        row.fold.horizontal = GUI:CreateTexture(row.fold, "color.text.primary", "OVERLAY")
        row.fold.horizontal:SetSize(8, stroke); row.fold.horizontal:SetPoint("CENTER")
        row.fold.vertical = GUI:CreateTexture(row.fold, "color.text.primary", "OVERLAY")
        row.fold.vertical:SetSize(stroke, 8); row.fold.vertical:SetPoint("CENTER")
        -- Bind without relying on callback argument ordering in the form layer.
        row:SetScript("OnClick", function()
            local target, item = row.target, row.item
            if item and item.section then ToggleTargets(window, item.targets); return end
            if target and (window.selected[target.key] or not window.targetReasons[target.key]) then
                window.selected[target.key] = not window.selected[target.key]; window.result = nil; RefreshCopy(window)
            end
        end)
        row.text:SetWordWrap(false)
        TruncatedTooltip(row)
        row:EnableMouseWheel(true); row:SetScript("OnMouseWheel", Scroll)
        window.rows[index] = row
    end
    window:EnableMouseWheel(true)
    window:SetScript("OnMouseWheel", Scroll)
    window.status = Text("", "font.size.sm", "color.text.secondary", 20, -280, 500)
    window.status:SetHeight(30); window.status:SetWordWrap(true)
    local undo = Button(window, T("undo"), 130, function()
        if not Style:CanUndo() then RefreshCopy(window); return end
        local ok, reason = Style:Undo()
        if ok then window.changed = true end
        window.result = T(ok and "undone" or reason); Style:RefreshControls(); RefreshCopy(window)
    end); undo:SetPoint("BOTTOMLEFT", 20, 14)
    undo.gui2Tone = "default"; undo:RefreshTheme(); window.undoButton = undo
    window.apply = GUI.Form:CreateButton(window, { text = T("copy_apply"), width = 168, height = 26,
        state = "selected", selectedSurface = "color.accent.fill", selectedTextColorKey = "color.text.primary", onClick = function()
        window.result = nil; RefreshCopy(window)
        if window.apply.gui2Disabled then return end
        local plan = Style:Plan(window.catalog, window.values, window.selectedAttributes, window.selected)
        if #plan.rejected > 0 then RefreshCopy(window); return end
        local ok, reason = Style:Execute(plan)
        if ok then window.changed = true end
        window.result = ok and string.format(T("copied"), plan.count) or T(reason)
        Style:RefreshControls(); RefreshCopy(window)
    end })
    window.apply:SetPoint("BOTTOMRIGHT", -20, 14)
    window:HookScript("OnHide", function()
        local changed = window.changed
        window.catalog, window.source, window.sourceBefore, window.values = nil, nil, nil, nil
        window.selected, window.selectedAttributes, window.filtered, window.targetReasons = nil, nil, nil, nil
        window.changed, window.result, window.colorReason = nil, nil, nil
        window.sections, window.items, window.collapsed = nil, nil, nil
        for _, row in ipairs(window.rows) do row.target, row.item = nil, nil end
        local editor = Style.editor
        if changed and editor and editor:IsShown() then Style:OpenEditor(editor.target.key, editor.anchor) end
    end)
    return window
end
function Style:OpenCopy(source)
    if not source or not source.group.current() then return end
    self.copyWindow = self.copyWindow or CreateCopyWindow()
    local window = self.copyWindow
    window.catalog = self:Capture()
    source = self:Find(window.catalog, source.key)
    if not source or not source.group.current() then return end
    window.source = source
    window.sourceLabel:SetText(string.format(T("copy_source"), source.label))
    window.sourceBefore, window.values = source.group.snapshot(source.id), self.Copy(source.read())
    window.selected, window.selectedAttributes, window.result, window.changed = {}, {}, nil, nil
    window.sections, window.collapsed = {}, {}
    for _, group in ipairs(window.catalog.groups) do
        local section = { group = group, label = group.label or T("copy_other"), targets = {} }
        for _, target in ipairs(group.targets) do
            if target.key ~= source.key then section.targets[#section.targets + 1] = target end
        end
        if #section.targets > 0 then
            if group == source.group then table.insert(window.sections, 1, section)
            else window.sections[#window.sections + 1] = section end
            window.collapsed[group] = group ~= source.group
        end
    end
    window.grouped = #window.sections > 1 or #window.catalog.entries > 8
    window.colorReason = not source.capabilities.color and T("copy_color_unsupported")
        or (window.values.color == nil or window.values.color.mode == "state") and T("copy_color_rule") or nil
    for _, key in ipairs(self.attributes) do
        local supported = source.capabilities[key] and window.values[key] ~= nil
        local field = window.attributes[key]
        field:SetDisabled(not supported)
        local display = key == "size" and window.values.size == nil and source.sizePlaceholder
            or key == "color" and not source.capabilities.color and T("color_dynamic") or CopyValue(key, window.values[key])
        local label = string.format(T("copy_attribute"), CopyAttribute(key), display)
        field.text:SetText(label)
        window.selectedAttributes[key] = supported and (key == "font" or key == "outline" or key == "shadow" or key == "monochrome") or false
        field:SetChecked(window.selectedAttributes[key], true)
    end
    window.targetReasons = nil
    window.viewport:SetVerticalScroll(0)
    window.status:SetText(""); window.search:SetText("")
    RefreshCopy(window); ShowAbove(window, self.editor)
end
