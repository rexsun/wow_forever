local YUI = _G.YUI
local H = YUI and YUI.YHUD
local UI = H and H.DesignerUI
local GUI2 = YUI and YUI.GUI2
if not (UI and GUI2 and GUI2.Form) then return end
local function T(key, fallback) return H:T(key, fallback) end

local function SyncControls(box, style, preserveThickness)
    box.mode:SetValue(style.barShadowMode, true)
    box.color:SetValue(style.barShadowColor, true)
    box.color:SetDisabled(style.barShadowMode == "none")
    if not preserveThickness then box.thickness:SetValue(style.barShadowThickness or 4, true) end
    box.thickness:SetDisabled(style.barShadowMode == "none")
end

local function EnsureControls(self)
    local box = self.barShadowControls
    if not box then
        box = GUI2:CreateFrame(self.v2PageRoots.appearance, { width = 368, height = 154, mouse = false })
        self.barShadowControls = box
        box.title = GUI2:CreateText(box, T("designer.bar_shadow.title", "分组阴影"), "font.size.md", "color.text.heading", "LEFT")
        box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
        box.heading = GUI2:CreateDivider(box, {
            width = 368, height = 22, label = T("designer.bar_shadow.title", "分组阴影"), alignLeft = true,
        })
        box.heading:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
        box.heading:Hide()
        box.modeLabel = GUI2:CreateText(box, T("designer.bar_shadow.mode", "阴影模式"), "font.size.md", "color.text.primary", "LEFT")
        box.modeLabel:Hide()
        box.colorLabel = GUI2:CreateText(box, T("designer.bar_shadow.color", "阴影颜色"), "font.size.md", "color.text.primary", "LEFT")
        box.colorLabel:SetPoint("TOPLEFT", box, "TOPLEFT", 192, 0)
        box.colorLabel:SetWidth(176)
        local function Commit(field, value)
            if self.v2Refreshing then return end
            local designer = H.Designer
            local session = designer:GetSession()
            if not session or session.selectedGroupId ~= box.groupId then return end
            local setter = box.layout == "resource" and designer.SetGroupResourceStyle
                or designer.SetGroupDurationStyle
            local style = setter(designer, box.groupId, { [field] = value })
            if not style then return end
            -- The shadow section does not change height. A full page refresh
            -- temporarily shrinks the scroll child and loses the current offset.
            SyncControls(box, style, box.layout == "resource" and field == "barShadowThickness")
            self:PreviewSelectedGroup()
            self:SetStatus(T("designer.status_dirty", "当前配置有未保存修改。"))
        end
        local function Preview(value)
            if H.View and H.View.PreviewBarShadowColor then H.View:PreviewBarShadowColor(box.groupId, value) end
        end
        box.modeOptions = {
            { value = "none", text = T("designer.bar_shadow.off", "关闭") },
            { value = "item", text = T("designer.bar_shadow.item", "逐项") },
            { value = "group", text = T("designer.bar_shadow.group", "整组") },
        }
        box.mode = GUI2.Form:CreateDropdown(box, {
            width = 176,
            options = box.modeOptions,
            tooltip = T("designer.bar_shadow.help", "逐项：每条独立绘制，靠近时阴影可能加深。整组：只绘制分组外沿；含圆点或独立格子时自动按逐项显示。"),
            set = function(value) Commit("barShadowMode", value) end,
        })
        box.mode:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -26)
        box.color = GUI2.Form:CreateColorPicker(box, {
            width = 176, height = 30, field = true, hasAlpha = true,
            getDefault = function()
                local normalize = box.layout == "resource" and H.NormalizeResourceGroupStyle
                    or H.NormalizeDurationGroupStyle
                return normalize(H, {}).barShadowColor
            end,
            set = function(value) Commit("barShadowColor", value) end,
        })
        box.color:SetPoint("TOPLEFT", box, "TOPLEFT", 192, -26)
        box.color:SetColorLifecycle(Preview, function(value) Commit("barShadowColor", value) end, Preview)
        box.thicknessLabel = GUI2:CreateText(box, T("designer.bar_shadow.thickness", "阴影厚度"), "font.size.md", "color.text.primary", "LEFT")
        box.thicknessLabel:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -64)
        box.thickness = GUI2.Form:CreateSlider(box, {
            width = 368, inline = true, inputWidth = 44, min = 1, max = 12, step = 1,
            set = function(value) Commit("barShadowThickness", value) end,
        })
        box.thickness:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -88)
        box.note = GUI2:CreateText(box, T("designer.bar_shadow.scope", "应用于当前分组的全部条目。"), "font.size.sm", "color.text.secondary", "LEFT")
        box.note:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -124)
        box.note:SetWidth(368)
    end
    return box
end

local function LayoutResourceControls(box)
    box.title:Hide()
    box.heading:Show()
    local row = UI._internal.PlaceResourceAppearanceRow
    local y = row(box, -28,
        { box.modeLabel, box.mode, "compactSelect", nil, box.modeOptions }, { box.colorLabel, box.color, "color" })
    y = row(box, y, { box.thicknessLabel, box.thickness, "number" })
    box.note:ClearAllPoints()
    box.note:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y - 2)
    local noteHeight = math.max(14, box.note.GetStringHeight and box.note:GetStringHeight() or 14)
    box.note:SetHeight(noteHeight)
    local height = -y + noteHeight + 8
    box:SetHeight(height)
    return height + 18
end

local function LayoutDurationControls(box)
    box.title:Show()
    box.heading:Hide()
    box.modeLabel:Hide()
    if box.thickness.gui2CompactSlider then box.thickness:SetCompactMode(false) end
    if box.mode.SetTextInsets then box.mode:SetTextInsets() end
    box.mode:ClearAllPoints()
    box.mode:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -26)
    box.mode:SetSize(176, 26)
    box.colorLabel:ClearAllPoints()
    box.colorLabel:SetPoint("TOPLEFT", box, "TOPLEFT", 192, 0)
    box.colorLabel:SetWidth(176)
    box.color:ClearAllPoints()
    box.color:SetPoint("TOPLEFT", box, "TOPLEFT", 192, -26)
    box.color:SetSize(176, 30)
    if box.color.chipBg then
        box.color.chipBg:SetSize(176, 24)
        if box.color.chipBg.UpdateGUI2PixelLayout then box.color.chipBg:UpdateGUI2PixelLayout() end
    end
    box.thicknessLabel:ClearAllPoints()
    box.thicknessLabel:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -64)
    box.thicknessLabel:SetWidth(368)
    box.thickness:ClearAllPoints()
    box.thickness:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -88)
    box.note:ClearAllPoints()
    box.note:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -124)
    box:SetHeight(154)
    return 172
end

function UI:RefreshBarShadowControls(profile, group, page)
    if self.barShadowControls then self.barShadowControls:Hide() end
    if page ~= "appearance" or (group.layout ~= "resource" and group.layout ~= "bars") then return end
    local box = EnsureControls(self)
    box.groupId, box.layout = group.id, group.layout
    local style = group.layout == "resource" and H:GetResourceGroupStyle(profile, group.id)
        or H:GetDurationGroupStyle(profile, group.id)
    local y = group.layout == "bars" and 340 or math.max(0, (self.v2InspectorContentHeight or 130) - 20)
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", self.groupInspectorBody, "TOPLEFT", 0, -y)
    SyncControls(box, style)
    local height = group.layout == "resource" and LayoutResourceControls(box) or LayoutDurationControls(box)
    box:Show()
    UI._internal.SetResourceContentHeight(self, y + height)
end
