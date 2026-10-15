local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
local View = YHUD and YHUD.View
local I = View and View._internal
if not I then return end

local GUI2 = I.GUI2
local App = I.App
local ResourceCatalog = I.ResourceCatalog
local Glow = I.Glow
local Animation = YUI.Animation
local Unpack = table.unpack or _G.unpack
local QUESTION_ICON = I.QUESTION_ICON
local DEFAULT_ICON_SIZE = I.DEFAULT_ICON_SIZE
local DEFAULT_MAX_PER_LINE = I.DEFAULT_MAX_PER_LINE
local EMPTY_DESIGN_GROUP_WIDTH = I.EMPTY_DESIGN_GROUP_WIDTH
local LAYOUT_VIEWS = I.LAYOUT_VIEWS
local AddViewWrite = I.AddViewWrite
local SafeName = I.SafeName
local GroupName = I.GroupName
local FormatMonitorName = I.FormatMonitorName
local GetEntryName = I.GetEntryName
local SameGlowAppearance = I.SameGlowAppearance
local CacheGlowAppearance = I.CacheGlowAppearance
local ApplyRuntimeLayout = I.ApplyRuntimeLayout
local AddPerformanceStat = I.AddPerformanceStat
local ProfileNowMS = I.ProfileNowMS
local SetSlotIcon = I.SetSlotIcon

local DRAG_INDICATOR_SIZE = 3
local DRAG_GROUP_PADDING = 18
local DRAG_BUNDLE_SCALE = 0.5
local DRAG_BUNDLE_STACK_X = 4
local DRAG_BUNDLE_STACK_Y = -4
local DRAG_MAKE_ROOM_PIXELS = 4
local DRAG_MAKE_ROOM_SECONDS = 0.12
local DESIGN_HEADER_GAP = 0
local DESIGN_TITLE_MIN_WIDTH = 100
local DESIGN_TITLE_PADDING = 20
local DESIGN_COOLDOWN_SAMPLE = "15"
local DESIGN_COUNT_SAMPLE = "2"
local DESIGN_DURATION_SECONDS = 15
local DESIGN_DURATION_PREVIEW_ELAPSED = 3
local DESIGN_SELECTION_PIXELS = 4
local DESIGN_HOVER_PIXELS = 1
local DESIGN_RING_SELECTION_OFFSET_PIXELS = 2
local DESIGN_RING_SELECTION_THICKNESS_PIXELS = 2
local DESIGN_RING_SELECTION_LENGTH_PIXELS = 8
local RUNE_PREVIEW_READY = { true, true, true, true, true, true }
local RUNE_PREVIEW_DURATIONS = {}

local function RecordDesignCreate(kind, count)
    count = count or 1
    View.designCreateCount = (View.designCreateCount or 0) + count
    if kind == "chrome" then
        View.designChromeCreateCount =
            (View.designChromeCreateCount or 0) + count
    elseif kind == "slot" then
        View.designSlotCreateCount =
            (View.designSlotCreateCount or 0) + count
    elseif kind == "text" then
        View.designTextCreateCount =
            (View.designTextCreateCount or 0) + count
    end
end

function View:GetDesignCreateStats(target)
    target = type(target) == "table" and target or {}
    target.total = self.designCreateCount or 0
    target.chrome = self.designChromeCreateCount or 0
    target.slot = self.designSlotCreateCount or 0
    target.text = self.designTextCreateCount or 0
    target.resourcePreview = self.designResourcePreviewCreateCount or 0
    return target
end

local function ResolveDesignIconSlot(slot)
    if slot and slot.icon and slot.icon.icon then
        return slot.icon
    end
    return slot
end

local function ResolveDesignCooldown(slot, iconSlot)
    if slot and (slot._yhudView == "bar" or slot._yhudView == "ring") then
        return slot.countdown
    end
    return iconSlot and iconSlot.cooldown or slot and slot.cooldown
end

local function ResolveDesignCount(slot, iconSlot)
    if slot
        and (slot._yhudView == "bar" or slot._yhudView == "ring")
        and slot.durationCountText then
        return slot.durationCountText
    end
    return iconSlot and iconSlot.count or slot and slot.count
end

local function ResolveDesignDurationTextOwner(slot, iconSlot)
    if slot
        and (slot._yhudView == "bar" or slot._yhudView == "ring") then
        return slot
    end
    return iconSlot
end

local function SetShown(region, shown)
    if not region then return end
    if region.SetShown then
        region:SetShown(shown == true)
    elseif shown and region.Show then
        region:Show()
    elseif not shown and region.Hide then
        region:Hide()
    end
end

local function DesignProjectionForSlot(slot)
    local projection = View.designProjection
    if slot and slot._yhudDesignProjection == true
        and type(projection) == "table" then
        return projection
    end
    return nil
end

local function DesignRuntimeForSlot(slot)
    local projection = DesignProjectionForSlot(slot)
    if projection then
        return projection.groups and projection.groups[slot._yhudGroupId]
    end
    return slot and slot._yhudGroupId
        and View.groups[slot._yhudGroupId] or nil
end

local function DesignSlotsForRuntime(runtime)
    local projection = runtime and runtime._yhudDesignProjection
        and View.designProjection or nil
    return projection and projection.byMonitor or View.byMonitor
end

local function DesignProfileForRuntime(runtime)
    local projection = runtime and runtime._yhudDesignProjection
        and View.designProjection or nil
    return projection and projection.profile or View.profile
end

local function ForEachDesignSlot(callback)
    local projection = View.designProjection
    local slots = projection and projection.byMonitor or View.byMonitor
    for monitorId, slot in pairs(slots or {}) do
        callback(slot, monitorId)
    end
end

local function SetBorderShown(frame, shown)
    local borders = frame and frame.gui2Borders
    if not borders then return end
    SetShown(borders.top, shown)
    SetShown(borders.bottom, shown)
    SetShown(borders.left, shown)
    SetShown(borders.right, shown)
end

function View:EnsureDesignSelectionOutline(slot)
    if not slot then return nil end
    local outline = slot._yhudDesignSelectionOutline
    if outline then return outline end
    if not GUI2.CreateFrame then return nil end

    outline = GUI2:CreateFrame(slot, {
        mouse = false,
        hidden = true,
    })
    RecordDesignCreate("slot")
    if GUI2.CreateBorder then
        GUI2:CreateBorder(outline, "color.state.warning")
        if outline.gui2Borders then
            outline.gui2Borders.widthPixels = DESIGN_SELECTION_PIXELS
            if outline.UpdateGUI2PixelScale then
                outline:UpdateGUI2PixelScale()
            end
        end
    end

    if outline.CreateTexture then
        local shapeOutline = outline:CreateTexture(nil, "OVERLAY")
        shapeOutline:SetAllPoints(outline)
        if GUI2.GetColor and shapeOutline.SetVertexColor then
            shapeOutline:SetVertexColor(
                GUI2:GetColor("color.state.warning")
            )
        end
        shapeOutline:Hide()
        outline._yhudDesignShapeOutline = shapeOutline

        local corners = {}
        local anchors = {
            { "TOPLEFT", 1, -1 },
            { "TOPRIGHT", -1, -1 },
            { "BOTTOMLEFT", 1, 1 },
            { "BOTTOMRIGHT", -1, 1 },
        }
        for index = 1, #anchors do
            local horizontal = outline:CreateTexture(nil, "OVERLAY")
            local vertical = outline:CreateTexture(nil, "OVERLAY")
            if GUI2.GetColor then
                local r, g, b, a = GUI2:GetColor("color.state.warning")
                if horizontal.SetColorTexture then
                    horizontal:SetColorTexture(r, g, b, a)
                    vertical:SetColorTexture(r, g, b, a)
                else
                    horizontal:SetVertexColor(r, g, b, a)
                    vertical:SetVertexColor(r, g, b, a)
                end
            end
            horizontal:Hide()
            vertical:Hide()
            corners[index] = {
                anchor = anchors[index][1],
                xDirection = anchors[index][2],
                yDirection = anchors[index][3],
                horizontal = horizontal,
                vertical = vertical,
            }
        end
        outline._yhudDesignCorners = corners
    end

    slot._yhudDesignSelectionOutline = outline
    if slot._yhudView == "resource" and slot.HookScript then
        slot:HookScript("OnSizeChanged", function(frame)
            local indicator = frame._yhudDesignSelectionOutline
            if View.designMode and indicator and indicator:IsShown() then
                View:RefreshDesignSelectionOutline(frame)
            end
        end)
    end
    return outline
end

function View:RefreshDesignSelectionOutline(slot)
    local outline = slot and slot._yhudDesignSelectionOutline
    if not outline then return false end
    AddPerformanceStat("designOutlineRefreshes")
    local isRing = slot._yhudView == "ring"
    local isResource = slot._yhudView == "resource"
    local selected = slot._yhudDesignSelected == true
    local highlightPixels = selected
        and DESIGN_SELECTION_PIXELS or DESIGN_HOVER_PIXELS
    outline:ClearAllPoints()
    outline:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
    outline:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 0, 0)
    if outline.SetFrameLevel and slot.GetFrameLevel then
        outline:SetFrameLevel((slot:GetFrameLevel() or 0) + 12)
    end
    -- 编辑提示高于各分组及播放预览，不改变资源内容自身的叠放顺序。
    if outline.SetFrameStrata then
        outline:SetFrameStrata(isResource and "FULLSCREEN"
            or (slot.GetFrameStrata and slot:GetFrameStrata() or "DIALOG"))
    end
    local arrows = outline._yhudDesignResourceArrows
    if isResource then
        if not arrows then
            arrows = {}
            for index = 1, 2 do
                local arrow = outline:CreateTexture(nil, "OVERLAY")
                arrow:SetAtlas("bag-arrow", false)
                arrows[index] = arrow
            end
            outline._yhudDesignResourceArrows = arrows
        end
        local vertical = slot.gui2ResourceOrientation == "vertical"
        local pixel = GUI2.GetPixelSize and GUI2:GetPixelSize(slot, 1, 1) or 1
        local size = 10 * pixel
        local depth = 6 * pixel
        local offset = 2 * pixel + depth / 2
        for index = 1, 2 do
            local arrow = arrows[index]
            local first = index == 1
            arrow:ClearAllPoints()
            arrow:SetSize(depth, size)
            -- bag-arrow 原始方向向左，围绕中心旋转后始终指向条内。
            arrow:SetRotation(vertical and (first and math.pi / 2 or -math.pi / 2)
                or (first and math.pi or 0))
            arrow:SetPoint("CENTER", slot,
                vertical and (first and "TOP" or "BOTTOM")
                    or (first and "LEFT" or "RIGHT"),
                vertical and 0 or (first and -offset or offset),
                vertical and (first and offset or -offset) or 0)
            arrow:SetAlpha(selected and 1 or 0.45)
            arrow:Show()
        end
    elseif arrows then
        arrows[1]:Hide()
        arrows[2]:Hide()
    end
    if outline.gui2Borders then
        outline.gui2Borders.widthPixels = highlightPixels
        if outline.UpdateGUI2PixelScale then
            outline:UpdateGUI2PixelScale()
        end
    end

    local family
    local shape = slot._yhudView == "icon" and slot.gui2Shape or nil
    if shape and not family and GUI2.GetIconAppearancePreset then
        local preset = GUI2:GetIconAppearancePreset(shape)
        family = preset and preset.borderFamily or nil
    elseif shape and not family and (shape == "roundedSquare"
        or shape == "flatRounded"
        or shape == "wideRounded") then
        family = "rounded"
    elseif shape and not family and shape == "circle" then
        family = "circle"
    end
    local familyPaths = family and GUI2.IconAppearanceBorderTextures
        and GUI2.IconAppearanceBorderTextures[family]
    local shapePath = familyPaths and (
        familyPaths[highlightPixels]
            or familyPaths[2]
            or familyPaths[1]
    )
    local shapeOutline = outline._yhudDesignShapeOutline
    if shapeOutline and shapePath then
        shapeOutline:SetTexture(shapePath)
    end
    SetBorderShown(outline, not isResource and not isRing and shapePath == nil)
    SetShown(shapeOutline, not isResource and not isRing and shapePath ~= nil)
    local corners = outline._yhudDesignCorners
    if corners then
        local thicknessPixels = selected
            and DESIGN_RING_SELECTION_THICKNESS_PIXELS
            or DESIGN_HOVER_PIXELS
        local thickness = GUI2.GetPixelSize
            and GUI2:GetPixelSize(slot, thicknessPixels, 1)
            or thicknessPixels
        local length = GUI2.GetPixelSize
            and GUI2:GetPixelSize(slot, DESIGN_RING_SELECTION_LENGTH_PIXELS, 1)
            or DESIGN_RING_SELECTION_LENGTH_PIXELS
        for index = 1, #corners do
            local corner = corners[index]
            corner.horizontal:ClearAllPoints()
            corner.horizontal:SetPoint(corner.anchor, outline, corner.anchor, 0, 0)
            corner.horizontal:SetSize(length, thickness)
            corner.vertical:ClearAllPoints()
            corner.vertical:SetPoint(corner.anchor, outline, corner.anchor, 0, 0)
            corner.vertical:SetSize(thickness, length)
            SetShown(corner.horizontal, isRing)
            SetShown(corner.vertical, isRing)
        end
    end
    slot._yhudDesignOutlineMode = selected and "selected" or "hover"
    return true
end

local function SetDesignTextShown(region, state, shown)
    if not (region and state) then return end
    shown = shown == true
    state.preserveVisibility = true
    local actualShown = region.IsShown and region:IsShown()
    if state.shown == shown and actualShown == shown then return end
    SetShown(region, shown)
    state.shown = shown
end

local function ResolveDesignCountPreview(slot)
    local monitor = slot
        and View.desiredMonitors
        and View.desiredMonitors[slot._yhudMonitorId]
    local entry = monitor
        and monitor.entryKey
        and View.profile
        and View.profile.entries
        and View.profile.entries[monitor.entryKey]
    local hasCount = entry and entry.charges == true or false
    local state = monitor
        and monitor.sourceKey
        and YHUD.Model
        and YHUD.Model:GetState(monitor.sourceKey)
    if state then
        if state.countSecret ~= true
            and type(state.displayCount) == "number"
            and state.displayCount > 0 then
            return true, state.displayCount
        end
        if type(state.maxCharges) == "number"
            and state.maxCharges > 1 then
            hasCount = true
        end
    end
    if slot and slot._yhudDisplayCount ~= nil then hasCount = true end
    return hasCount, DESIGN_COUNT_SAMPLE
end

local function RefreshDesignHeaderWidth(runtime)
    local button = runtime and runtime.designGroupButton
    local header = runtime and runtime.designHeader
    if not (button and header) then return false end

    local title = GroupName(runtime.group)
    button:SetText(title)
    local label = button.GetFontString and button:GetFontString()
        or button.text
    local textWidth
    if label and label.GetUnboundedStringWidth then
        textWidth = label:GetUnboundedStringWidth()
    elseif label and label.GetStringWidth then
        textWidth = label:GetStringWidth()
    end
    textWidth = type(textWidth) == "number" and textWidth or 0
    local titleWidth
    if runtime.monitorCount == 0 then
        titleWidth = I.GetAutoIconRowWidth(runtime) or EMPTY_DESIGN_GROUP_WIDTH
    else
        titleWidth = math.max(
            DESIGN_TITLE_MIN_WIDTH,
            math.ceil(textWidth + DESIGN_TITLE_PADDING)
        )
    end
    if button.SetWidth then button:SetWidth(titleWidth) end
    if header.SetWidth then header:SetWidth(titleWidth) end
    return true
end

function View:EnsureDesignTextPreview(slot)
    if not (self.designMode and slot)
        or slot._yhudView == "resource" then
        return false
    end
    local iconSlot = ResolveDesignIconSlot(slot)
    if not iconSlot then return false end

    if not slot._yhudDesignTextOverlay and GUI2.CreateFrame then
        local overlay = GUI2:CreateFrame(iconSlot, {
            mouse = false,
            hidden = true,
        })
        RecordDesignCreate("text")
        overlay:SetPoint("TOPLEFT", iconSlot, "TOPLEFT", 0, 0)
        overlay:SetPoint("BOTTOMRIGHT", iconSlot, "BOTTOMRIGHT", 0, 0)
        slot._yhudDesignTextOverlay = overlay
    end
    local textParent = slot._yhudDesignTextOverlay or iconSlot
    local durationOwner = ResolveDesignDurationTextOwner(slot, iconSlot)
    if durationOwner ~= iconSlot
        and not slot._yhudDesignDurationTextOverlay
        and GUI2.CreateFrame then
        local overlay = GUI2:CreateFrame(durationOwner, {
            mouse = false,
            hidden = true,
        })
        RecordDesignCreate("text")
        overlay:SetAllPoints(durationOwner)
        slot._yhudDesignDurationTextOverlay = overlay
    end
    local durationTextParent = slot._yhudDesignDurationTextOverlay
        or textParent
    if not slot._yhudDesignCooldownText and GUI2.CreateText then
        slot._yhudDesignCooldownText = GUI2:CreateText(
            durationTextParent,
            DESIGN_COOLDOWN_SAMPLE,
            "font.size.sm",
            "color.text.primary",
            "CENTER"
        )
        RecordDesignCreate("text")
        slot._yhudDesignCooldownTextState = {}
    end
    if not slot._yhudDesignCountText and GUI2.CreateText then
        local countParent = (slot._yhudView == "bar"
            or slot._yhudView == "ring")
            and durationTextParent or textParent
        slot._yhudDesignCountText = GUI2:CreateText(
            countParent,
            DESIGN_COUNT_SAMPLE,
            "font.size.sm",
            "color.text.primary",
            "RIGHT"
        )
        RecordDesignCreate("text")
        slot._yhudDesignCountTextState = {}
    end
    if not slot._yhudDesignNameText and GUI2.CreateText then
        slot._yhudDesignNameText = GUI2:CreateText(
            durationTextParent,
            "",
            "font.size.sm",
            "color.text.primary",
            "CENTER"
        )
        RecordDesignCreate("text")
        if slot._yhudDesignNameText.SetWordWrap then
            slot._yhudDesignNameText:SetWordWrap(false)
        end
        slot._yhudDesignNameTextState = {}
    end
    return slot._yhudDesignCooldownText ~= nil
        and slot._yhudDesignCountText ~= nil
        and slot._yhudDesignNameText ~= nil
end

local BAR_DESIGN_TEXT_KINDS = { "Cooldown", "Count", "Name" }

function View:InvalidateDesignBarTextLayout(slot)
    if not slot or slot._yhudView ~= "bar" then return end
    for index = 1, #BAR_DESIGN_TEXT_KINDS do
        local prefix = "_yhudDesign" .. BAR_DESIGN_TEXT_KINDS[index] .. "Text"
        slot[prefix .. "State"] = {}
        slot[prefix .. "AnchorState"] = {}
        slot[prefix .. "Region"] = slot[prefix]
    end
end

local function EnsureDesignBarTextStates(slot)
    if slot._yhudView ~= "bar" then return end
    for index = 1, #BAR_DESIGN_TEXT_KINDS do
        local prefix = "_yhudDesign" .. BAR_DESIGN_TEXT_KINDS[index] .. "Text"
        if slot[prefix .. "Region"] ~= slot[prefix]
            or not slot[prefix .. "AnchorState"] then
            slot[prefix .. "State"] = {}
            slot[prefix .. "AnchorState"] = {}
            slot[prefix .. "Region"] = slot[prefix]
        end
    end
end

-- 普通条形设计样本在布局变化后需要重新生成字形；不触碰运行时文字。
local DESIGN_SAMPLE_ANCHOR_KEYS = {
    "target", "point", "relativePoint", "x", "y", "justify", "nameWidth",
    "numericFont", "numericSize", "numericOutline",
}
local function CommitDesignBarSample(slot, text, value, state, anchorState)
    local previous = state.sampleLayout
    local changed = not previous
        or previous.font ~= state.font or previous.size ~= state.fontSize
        or previous.outline ~= state.fontOutline
        or previous.width ~= slot.gui2DurationWidth
        or previous.height ~= slot.gui2DurationHeight
        or previous.orientation ~= slot.orientation
        or previous.showIcon ~= slot.gui2DurationShowIcon
    previous = previous or {}
    for index = 1, #DESIGN_SAMPLE_ANCHOR_KEYS do
        local key = DESIGN_SAMPLE_ANCHOR_KEYS[index]
        local current = anchorState and anchorState[key]
        if previous[key] ~= current then changed = true end
        previous[key] = current
    end
    previous.font, previous.size, previous.outline = state.font, state.fontSize, state.fontOutline
    previous.width, previous.height = slot.gui2DurationWidth, slot.gui2DurationHeight
    previous.orientation, previous.showIcon = slot.orientation, slot.gui2DurationShowIcon
    state.sampleLayout = previous
    if changed then text:SetText("") end
    if changed or state.sampleValue ~= value then text:SetText(value) end
    state.sampleValue = value
end

function View:ApplyDesignTextPreview(slot)
    if not (self.designMode and slot)
        or slot._yhudView == "resource" then
        return false
    end
    local runtime = DesignRuntimeForSlot(slot)
    local iconSlot = ResolveDesignIconSlot(slot)
    if not (runtime and iconSlot
        and slot._yhudDesignCooldownText
        and slot._yhudDesignCountText) then
        return false
    end
    EnsureDesignBarTextStates(slot)

    local textPreviewActive = runtime.id == self.designCooldownPreviewGroupId
        and self.designTextPreviewTarget ~= nil
    local previewTarget = self.designTextPreviewTarget
    local previewAll = previewTarget == "all"
    local durationPreviewActive = self.designDurationPreviewEnabled == true
        and (slot._yhudView == "ring" or slot._yhudView == "bar")
        and runtime.enabled == true
        and (not runtime.frame.IsShown or runtime.frame:IsShown())
    local cooldownText = slot._yhudDesignCooldownText
    local durationText = slot._yhudView == "icon" and {
        enabled = runtime.cooldownText ~= false,
        font = runtime.cooldownTextFont,
        size = runtime.cooldownTextSize,
        outline = runtime.cooldownTextOutline,
        position = runtime.cooldownTextPosition,
        offsetX = runtime.cooldownTextOffsetX,
        offsetY = runtime.cooldownTextOffsetY,
        color = runtime.cooldownTextColor,
    } or {
        enabled = runtime.timeText ~= false,
        font = runtime.timeTextFont,
        size = runtime.timeTextSize,
        outline = runtime.timeTextOutline,
        position = runtime.timeTextPosition,
        anchor = runtime.timeTextAnchor,
        offsetX = runtime.timeTextOffsetX,
        offsetY = runtime.timeTextOffsetY,
        color = runtime.timeTextColor,
    }
    local cooldownShown = textPreviewActive
        and (previewAll or previewTarget == "cooldown")
        and durationText.enabled ~= false
    if cooldownText then
        if slot._yhudView ~= "bar" then cooldownText:SetText(DESIGN_COOLDOWN_SAMPLE) end
        if GUI2.ApplyTextStyle then
            slot._yhudDesignCooldownTextState.preserveVisibility = true
            slot._yhudDesignCooldownTextState.preserveAnchors = slot._yhudView == "bar"
            GUI2:ApplyTextStyle(
                cooldownText,
                durationText,
                slot._yhudDesignCooldownTextState
            )
        end
        if (slot._yhudView == "bar" or slot._yhudView == "ring")
            and slot.PositionDurationTextAnchor then
            slot:PositionDurationTextAnchor(
                cooldownText,
                durationText,
                "time",
                slot._yhudDesignCooldownTextAnchorState
            )
        end
        if slot._yhudView == "bar" then
            CommitDesignBarSample(slot, cooldownText, DESIGN_COOLDOWN_SAMPLE,
                slot._yhudDesignCooldownTextState, slot._yhudDesignCooldownTextAnchorState)
        end
        SetDesignTextShown(
            cooldownText,
            slot._yhudDesignCooldownTextState,
            cooldownShown
        )
    end

    local countText = slot._yhudDesignCountText
    local _, countValue = ResolveDesignCountPreview(slot)
    if View.ApplyBarStackPreview and (textPreviewActive or durationPreviewActive) then
        View:ApplyBarStackPreview(slot, countValue)
    end
    local countShown = (textPreviewActive or durationPreviewActive)
        and (durationPreviewActive or previewAll or previewTarget == "count")
        and runtime.countText == true
    if countText then
        if slot._yhudView ~= "bar" then countText:SetText(tostring(countValue)) end
        local countStyle = {
            enabled = runtime.countText ~= false,
            font = runtime.countTextFont,
            size = runtime.countTextSize,
            outline = runtime.countTextOutline,
            position = runtime.countTextPosition,
            anchor = runtime.countTextAnchor,
            offsetX = runtime.countTextOffsetX,
            offsetY = runtime.countTextOffsetY,
            color = runtime.countTextColor,
        }
        if GUI2.ApplyTextStyle then
            slot._yhudDesignCountTextState.preserveVisibility = true
            slot._yhudDesignCountTextState.preserveAnchors = slot._yhudView == "bar"
            GUI2:ApplyTextStyle(
                countText,
                countStyle,
                slot._yhudDesignCountTextState
            )
        end
        if (slot._yhudView == "bar" or slot._yhudView == "ring")
            and slot.PositionDurationTextAnchor then
            slot:PositionDurationTextAnchor(countText, countStyle, "count",
                slot._yhudDesignCountTextAnchorState)
        end
        if slot._yhudView == "bar" then
            CommitDesignBarSample(slot, countText, tostring(countValue),
                slot._yhudDesignCountTextState, slot._yhudDesignCountTextAnchorState)
        end
        SetDesignTextShown(
            countText,
            slot._yhudDesignCountTextState,
            countShown
        )
    end

    local nameText = slot._yhudDesignNameText
    local nameShown = slot._yhudView ~= "icon"
        and runtime.orientation ~= "vertical"
        and (textPreviewActive or durationPreviewActive)
        and (durationPreviewActive or previewAll or previewTarget == "name")
        and runtime.nameText ~= false
    if nameText then
        if slot._yhudView ~= "bar" then nameText:SetText(slot._yhudName or GroupName(runtime.group)) end
        local nameStyle = {
            enabled = runtime.nameText ~= false,
            font = runtime.nameTextFont,
            size = runtime.nameTextSize,
            outline = runtime.nameTextOutline,
            position = runtime.nameTextPosition,
            anchor = runtime.nameTextAnchor,
            offsetX = runtime.nameTextOffsetX,
            offsetY = runtime.nameTextOffsetY,
            color = runtime.nameTextColor,
        }
        if GUI2.ApplyTextStyle then
            slot._yhudDesignNameTextState.preserveVisibility = true
            slot._yhudDesignNameTextState.preserveAnchors = slot._yhudView == "bar"
            GUI2:ApplyTextStyle(
                nameText,
                nameStyle,
                slot._yhudDesignNameTextState
            )
        end
        if (slot._yhudView == "bar" or slot._yhudView == "ring")
            and slot.PositionDurationTextAnchor then
            slot:PositionDurationTextAnchor(nameText, nameStyle, "name",
                slot._yhudDesignNameTextAnchorState)
        end
        if slot._yhudView == "bar" then
            CommitDesignBarSample(slot, nameText, slot._yhudName or GroupName(runtime.group),
                slot._yhudDesignNameTextState, slot._yhudDesignNameTextAnchorState)
        end
        SetDesignTextShown(
            nameText,
            slot._yhudDesignNameTextState,
            nameShown
        )
    end
    local actualName = slot.durationNameText
    if actualName and actualName ~= nameText then
        if nameShown then
            if slot._yhudDesignActualNameWasShown == nil then
                if actualName.IsShown then
                    slot._yhudDesignActualNameWasShown =
                        actualName:IsShown() == true
                else
                    slot._yhudDesignActualNameWasShown = true
                end
            end
            actualName:Hide()
        elseif slot._yhudDesignActualNameWasShown ~= nil then
            SetShown(
                actualName,
                runtime.nameText ~= false
                    and runtime.orientation ~= "vertical"
            )
            slot._yhudDesignActualNameWasShown = nil
        end
    end

    local overlay = slot._yhudDesignTextOverlay
    if overlay then
        local cooldown = ResolveDesignCooldown(slot, iconSlot)
        local ownerLevel = iconSlot.GetFrameLevel
            and iconSlot:GetFrameLevel() or 0
        local cooldownLevel = cooldown and cooldown.GetFrameLevel
            and cooldown:GetFrameLevel() or ownerLevel
        local textLevel, textStrata
        if self.GetMonitorTextLayer then
            textLevel, textStrata = self:GetMonitorTextLayer(runtime)
        end
        if overlay.SetFrameLevel then
            overlay:SetFrameLevel(
                textLevel or math.max(ownerLevel, cooldownLevel) + 8
            )
        end
        if textStrata and overlay.SetFrameStrata then
            overlay:SetFrameStrata(textStrata)
        end
        SetShown(overlay, countShown
            or ((not slot._yhudDesignDurationTextOverlay)
                and (cooldownShown or nameShown)))
    end
    local durationOverlay = slot._yhudDesignDurationTextOverlay
    if durationOverlay then
        local ownerLevel = slot.GetFrameLevel and slot:GetFrameLevel() or 0
        local cooldown = slot.countdown
        local cooldownLevel = cooldown and cooldown.GetFrameLevel
            and cooldown:GetFrameLevel() or ownerLevel
        local textLevel, textStrata
        if slot._yhudView == "bar" and self.GetMonitorTextLayer then
            textLevel, textStrata = self:GetMonitorTextLayer(runtime)
        end
        if durationOverlay.SetFrameLevel then
            durationOverlay:SetFrameLevel(
                textLevel or math.max(ownerLevel, cooldownLevel) + 8
            )
        end
        if textStrata and durationOverlay.SetFrameStrata then
            durationOverlay:SetFrameStrata(textStrata)
        end
        SetShown(durationOverlay, cooldownShown or countShown or nameShown)
    end

    local actualCount = ResolveDesignCount(slot, iconSlot)
    if (type(actualCount) == "table"
        or type(actualCount) == "userdata")
        and actualCount ~= countText
        and actualCount.Hide then
        if countShown then
            if slot._yhudDesignActualCountWasShown == nil then
                if actualCount.IsShown then
                    slot._yhudDesignActualCountWasShown =
                        actualCount:IsShown() ~= false
                else
                    slot._yhudDesignActualCountWasShown = true
                end
            end
            actualCount:Hide()
        elseif slot._yhudDesignActualCountWasShown ~= nil then
            SetShown(
                actualCount,
                runtime.countText == true
            )
            slot._yhudDesignActualCountWasShown = nil
        end
    end
    local cooldown = ResolveDesignCooldown(slot, iconSlot)
    if cooldown and cooldown.SetHideCountdownNumbers then
        if cooldownShown then
            if slot._yhudDesignCooldownWasHidden == nil then
                slot._yhudDesignCooldownWasHidden =
                    durationText.enabled == false
                if cooldown.GetHideCountdownNumbers then
                    local ok, hidden = pcall(
                        cooldown.GetHideCountdownNumbers,
                        cooldown
                    )
                    if ok then
                        slot._yhudDesignCooldownWasHidden =
                            hidden == true
                    end
                end
            end
            cooldown:SetHideCountdownNumbers(true)
        elseif slot._yhudDesignCooldownWasHidden ~= nil then
            cooldown:SetHideCountdownNumbers(
                durationText.enabled == false
            )
            slot._yhudDesignCooldownWasHidden = nil
        end
    end
    return true
end

local CommitDesignGroupPosition

function View:EnsureDesignChrome(runtime)
    if runtime.designHeader and runtime.designMover then
        return runtime.designHeader
    end
    if not (GUI2.Form and GUI2.Form.CreateButton) then return nil end

    if not runtime.designHeader then
        local header = GUI2:CreateFrame(runtime.frame, {
            width = 166,
            height = 30,
            mouse = true,
            hidden = true,
        })
        header:SetPoint(
            "BOTTOMLEFT",
            runtime.frame,
            "TOPLEFT",
            0,
            DESIGN_HEADER_GAP
        )

        local groupButton = GUI2.Form:CreateButton(header, {
            text = GroupName(runtime.group),
            width = DESIGN_TITLE_MIN_WIDTH,
            height = 30,
            tone = "default",
            onClick = function()
                if View.designSelect then
                    View.designSelect(runtime.id)
                end
            end,
        })
        RecordDesignCreate("chrome", 2)
        groupButton:SetPoint("LEFT", 0, 0)
        if groupButton.RegisterForDrag then
            groupButton:RegisterForDrag("LeftButton")
        end
        groupButton:SetScript("OnDragStart", function()
            if not View.designMode then return end
            if View.designSelect and View.selectedGroupId ~= runtime.id then
                View.designSelect(runtime.id)
            end
            local frame = runtime.designMoveFrame or runtime.frame
            if not (frame and frame.GetCenter and frame.StartMoving) then return end
            runtime.designGroupDragging = true
            View.activeDesignGroupDrag = runtime
            if View.designGroupDragStart then
                View.designGroupDragStart(runtime.id)
            end
            if frame.SetMovable then frame:SetMovable(true) end
            frame:StartMoving()
        end)
        groupButton:SetScript("OnDragStop", function()
            local frame = runtime.designMoveFrame or runtime.frame
            if not frame then return end
            if frame.StopMovingOrSizing then frame:StopMovingOrSizing() end
            if runtime.designGroupDragging then
                runtime.designGroupDragging = false
                View.activeDesignGroupDrag = nil
                CommitDesignGroupPosition(runtime)
                if View.designGroupDragStop then
                    View.designGroupDragStop(runtime.id)
                end
            end
        end)

        runtime.designHeader = header
        runtime.designGroupButton = groupButton
        RefreshDesignHeaderWidth(runtime)
    end

    if not runtime.designMover and GUI2.CreatePanel and GUI2.CreateText then
        local mover = GUI2:CreatePanel(runtime.frame, {
            surface = "color.accent.soft",
            border = "color.border.accent",
            mouse = true,
        })
        mover:SetPoint("TOPLEFT", runtime.frame, "TOPLEFT", 0, 0)
        mover:SetPoint("BOTTOMRIGHT", runtime.frame, "BOTTOMRIGHT", 0, 0)
        mover:EnableMouse(true)
        mover:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" and View.designSelect then
                View.designSelect(runtime.id)
            end
        end)
        local label = GUI2:CreateText(
            mover,
            GroupName(runtime.group),
            "font.size.md",
            "color.text.heading",
            "CENTER"
        )
        RecordDesignCreate("chrome", 2)
        label:SetPoint("CENTER", 0, 0)
        mover:Hide()
        runtime.designMover = mover
        runtime.designMoverLabel = label
    end
    return runtime.designHeader
end

function View:RefreshDesignChromeGeometry(runtime)
    if not (runtime and runtime.frame) then return false end
    local frame = runtime.frame
    local width = runtime.nativeWidth
        or (frame.GetWidth and frame:GetWidth())
        or 1
    local height = runtime.nativeHeight
        or (frame.GetHeight and frame:GetHeight())
        or 1
    local offsetX = runtime.nativeOffsetX or 0
    local offsetY = runtime.nativeOffsetY or 0

    if runtime.designHeader then
        runtime.designHeader:ClearAllPoints()
        runtime.designHeader:SetPoint(
            "BOTTOMLEFT",
            frame,
            "TOPLEFT",
            offsetX,
            offsetY + DESIGN_HEADER_GAP
        )
    end
    if runtime.designMover then
        runtime.designMover:ClearAllPoints()
        runtime.designMover:SetPoint("CENTER", frame, "CENTER", offsetX, offsetY)
        runtime.designMover:SetSize(width, height)
    end
    if runtime.designOutline then
        local pixel = GUI2:GetPixelSize(frame, 1, 1)
        runtime.designOutline:ClearAllPoints()
        runtime.designOutline:SetPoint("CENTER", frame, "CENTER", offsetX, offsetY)
        runtime.designOutline:SetSize(
            width + (pixel * 2),
            height + (pixel * 2)
        )
    end
    return true
end

function View:EnsureDesignOutline(runtime)
    if runtime.designOutline then return runtime.designOutline end
    local outline = GUI2:CreateFrame(runtime.frame, {
        mouse = false,
        hidden = true,
    })
    RecordDesignCreate("chrome")
    outline:SetPoint("TOPLEFT", runtime.frame, "TOPLEFT", 0, 0)
    outline:SetPoint("BOTTOMRIGHT", runtime.frame, "BOTTOMRIGHT", 0, 0)
    if GUI2.CreateBorder then
        GUI2:CreateBorder(outline, "color.border.accent")
    end
    runtime.designOutline = outline
    return outline
end

local function ReadAnchor(frame)
    if frame and frame.GetPoint then
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
        if point then
            return point, relativeTo, relativePoint, x or 0, y or 0
        end
    end
    local stored = frame and frame.point
    if type(stored) == "table" and stored[1] then
        return stored[1], stored[2], stored[3], stored[4] or 0, stored[5] or 0
    end
end

CommitDesignGroupPosition = function(runtime)
    if not runtime then return false end
    if runtime.layoutId then
        local Layout = YUI.Layout
        if Layout and Layout.CommitFramePosition then
            return Layout:CommitFramePosition(
                runtime.layoutId,
                runtime.frame,
                "frame-drag"
            )
        end
    end
    local bridge = YHUD.LayoutBridge
    return bridge and bridge.CommitGroupPosition
        and bridge:CommitGroupPosition(
            runtime.id,
            runtime.designMoveFrame or runtime.frame
        ) or false
end

local function FrameSize(frame)
    local width = frame and frame.GetWidth and frame:GetWidth()
        or frame and frame.width
        or DEFAULT_ICON_SIZE
    local height = frame and frame.GetHeight and frame:GetHeight()
        or frame and frame.height
        or DEFAULT_ICON_SIZE
    return math.max(1, width or DEFAULT_ICON_SIZE),
        math.max(1, height or DEFAULT_ICON_SIZE)
end

local function LogicalMonitorId(slot)
    return slot
        and (slot._yhudDragPairId or slot._yhudLogicalMonitorId or slot._yhudMonitorId)
        or nil
end

local function CaptureDragSnapshot(runtime, draggedSlot)
    local snapshot = {}
    local logicalCandidates = {}
    local logicalOrder = {}
    local designSlots = DesignSlotsForRuntime(runtime)
    for index = 1, runtime.monitorCount do
        local candidate = designSlots[runtime.monitorIds[index]]
        if candidate and candidate.GetCenter then
            local logicalId = LogicalMonitorId(candidate)
            local current = logicalCandidates[logicalId]
            if not current then
                current = {
                    monitorId = logicalId,
                    slot = candidate,
                    slots = {},
                }
                logicalCandidates[logicalId] = current
                logicalOrder[#logicalOrder + 1] = logicalId
            elseif candidate == draggedSlot then
                current.slot = candidate
            end
            current.slots[#current.slots + 1] = candidate
        end
    end
    for index = 1, #logicalOrder do
        local current = logicalCandidates[logicalOrder[index]]
        local candidate = current and current.slot
        if candidate and candidate.GetCenter then
            local physical = {}
            local selectedPhysical
            for physicalIndex = 1, #current.slots do
                local physicalSlot = current.slots[physicalIndex]
                local physicalX, physicalY = physicalSlot:GetCenter()
                local physicalWidth, physicalHeight = FrameSize(physicalSlot)
                local physicalPoint, physicalRelativeTo,
                    physicalRelativePoint, physicalOffsetX, physicalOffsetY =
                    ReadAnchor(physicalSlot)
                local record = {
                    slot = physicalSlot,
                    x = physicalX,
                    y = physicalY,
                    width = physicalWidth,
                    height = physicalHeight,
                    point = physicalPoint,
                    relativeTo = physicalRelativeTo,
                    relativePoint = physicalRelativePoint,
                    offsetX = physicalOffsetX,
                    offsetY = physicalOffsetY,
                }
                physical[physicalIndex] = record
                if physicalSlot == candidate then selectedPhysical = record end
            end
            selectedPhysical = selectedPhysical or physical[1]
            local x = selectedPhysical and selectedPhysical.x
            local y = selectedPhysical and selectedPhysical.y
            local point, relativeTo, relativePoint, offsetX, offsetY =
                ReadAnchor(candidate)
            local width, height = FrameSize(candidate)
            snapshot[index] = {
                index = index,
                laneIndex = index,
                lane = YHUD.CONTENT_LANE_SPEC,
                monitorId = current.monitorId,
                slot = candidate,
                slots = current.slots,
                physical = physical,
                firstSlot = current.slots[1],
                lastSlot = current.slots[#current.slots],
                x = x,
                y = y,
                width = width,
                height = height,
                point = point,
                relativeTo = relativeTo,
                relativePoint = relativePoint,
                offsetX = offsetX,
                offsetY = offsetY,
                shiftX = 0,
                shiftY = 0,
            }
            for physicalIndex = 1, #physical do
                local record = physical[physicalIndex]
                record.index = index
                record.laneIndex = index
                record.lane = YHUD.CONTENT_LANE_SPEC
                record.monitorId = current.monitorId
                record.slots = current.slots
            end
        end
    end
    local sourceLogicalId = LogicalMonitorId(draggedSlot)
    snapshot._yhudSourceLogicalId = sourceLogicalId
    snapshot._yhudSourceGroupId = runtime.id
    local designProfile = DesignProfileForRuntime(runtime)
    snapshot._yhudSourceSpecKey = type(designProfile) == "table"
        and rawget(designProfile, "_yhudSpecKey") or nil
    snapshot._yhudOrderWithoutSource = {}
    for index = 1, #snapshot do
        local candidate = snapshot[index]
        if candidate and candidate.monitorId ~= sourceLogicalId then
            snapshot._yhudOrderWithoutSource[
                #snapshot._yhudOrderWithoutSource + 1
            ] = candidate
        end
    end
    return snapshot
end

local GetDragPointer

local function CollectBundleDragSlots(runtime, frame)
    local logicalId = LogicalMonitorId(frame)
    if not logicalId then return {} end
    local slots = {}
    local designSlots = DesignSlotsForRuntime(runtime)
    for index = 1, #(runtime and runtime.monitorIds or {}) do
        local candidate = designSlots[runtime.monitorIds[index]]
        if candidate ~= frame
            and candidate
            and (candidate._yhudDesignResourceId == nil or frame._yhudDragPairId ~= nil)
            and LogicalMonitorId(candidate) == logicalId then
            slots[#slots + 1] = candidate
        end
    end
    return slots
end

local function CopyDragPreviewTexture(target, sourceSlot)
    if not target then return end
    local iconSlot = ResolveDesignIconSlot(sourceSlot)
    local source = iconSlot and iconSlot.icon
    local atlas = source and source.GetAtlas and source:GetAtlas()
    local texture = source and source.GetTexture and source:GetTexture()
        or source and source.texture
        or iconSlot and iconSlot.iconTexture
        or sourceSlot and sourceSlot.iconTexture
        or QUESTION_ICON
    if target.ResetTexCoord then
        target:ResetTexCoord()
    elseif target.SetTexCoord then
        target:SetTexCoord(0, 1, 0, 1)
    end
    if atlas and target.SetAtlas then
        target:SetAtlas(atlas, false)
    elseif target.SetTexture then
        target:SetTexture(texture)
    end
    if source and source.GetTexCoord and target.SetTexCoord then
        target:SetTexCoord(source:GetTexCoord())
    elseif source and type(source.texCoord) == "table"
        and target.SetTexCoord then
        target:SetTexCoord(Unpack(source.texCoord))
    end
    if source and source.GetVertexColor and target.SetVertexColor then
        target:SetVertexColor(source:GetVertexColor())
    elseif source and type(source.vertexColor) == "table"
        and target.SetVertexColor then
        target:SetVertexColor(Unpack(source.vertexColor))
    end
    if source and source.IsDesaturated and target.SetDesaturated then
        target:SetDesaturated(source:IsDesaturated())
    end
end

local function EnsureMonitorDragPreviewIcon(runtime, index)
    local preview = runtime.designDragPreview
    local icons = preview.icons
    local holder = icons[index]
    if holder then return holder end
    holder = GUI2:CreateFrame(preview, {
        mouse = false,
        hidden = true,
    })
    holder.icon = holder:CreateTexture(nil, "ARTWORK")
    holder.icon:SetAllPoints(holder)
    holder:Hide()
    icons[index] = holder
    RecordDesignCreate("chrome")
    return holder
end

local function EnsureMonitorDragPreview(runtime)
    if runtime.designDragPreview then return runtime.designDragPreview end
    local preview = GUI2:CreateFrame(UIParent, {
        mouse = false,
        hidden = true,
    })
    preview.icons = {}
    if preview.SetFrameStrata then preview:SetFrameStrata("TOOLTIP") end
    if preview.SetFrameLevel then preview:SetFrameLevel(100) end
    preview:Hide()
    runtime.designDragPreview = preview
    RecordDesignCreate("chrome")
    return preview
end

local function UpdateMonitorDragPreview(frame, cursorX, cursorY)
    local preview = frame and frame._yhudDragPreview
    if not preview then return end
    if cursorX == nil or cursorY == nil then
        cursorX, cursorY = GetDragPointer(frame)
    end
    if cursorX == nil or cursorY == nil then return end
    preview:ClearAllPoints()
    preview:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cursorX, cursorY)
end

local function ShowMonitorDragPreview(runtime, frame)
    local preview = EnsureMonitorDragPreview(runtime)
    local sourceSlots = { frame }
    for index = 1, #(frame._yhudDragBundleSlots or {}) do
        sourceSlots[#sourceSlots + 1] = frame._yhudDragBundleSlots[index]
    end
    local maxWidth = 1
    local maxHeight = 1
    for index = 1, #sourceSlots do
        local sourceSlot = sourceSlots[index]
        local holder = EnsureMonitorDragPreviewIcon(runtime, index)
        local iconSlot = ResolveDesignIconSlot(sourceSlot)
        local width, height = FrameSize(iconSlot)
        width = width * DRAG_BUNDLE_SCALE
        height = height * DRAG_BUNDLE_SCALE
        holder:SetSize(width, height)
        holder:ClearAllPoints()
        holder:SetPoint(
            "CENTER",
            preview,
            "CENTER",
            DRAG_BUNDLE_STACK_X * (index - 1),
            DRAG_BUNDLE_STACK_Y * (index - 1)
        )
        if GUI2.ApplyIconAppearance then
            GUI2:ApplyIconAppearance(holder, {
                shape = iconSlot and iconSlot.gui2Shape
                    or sourceSlot.gui2Shape,
                border = iconSlot and iconSlot.gui2IconBorder
                    or sourceSlot.gui2IconBorder,
                size = height,
                zoom = iconSlot and iconSlot.gui2IconZoom
                    or sourceSlot.gui2IconZoom,
            })
        end
        CopyDragPreviewTexture(holder.icon, sourceSlot)
        holder:Show()
        maxWidth = math.max(
            maxWidth,
            width + math.abs(DRAG_BUNDLE_STACK_X) * (index - 1)
        )
        maxHeight = math.max(
            maxHeight,
            height + math.abs(DRAG_BUNDLE_STACK_Y) * (index - 1)
        )
        if sourceSlot._yhudDragOriginalAlpha == nil then
            sourceSlot._yhudDragOriginalAlpha = sourceSlot.GetAlpha
                and sourceSlot:GetAlpha() or 1
        end
        if sourceSlot.SetAlpha then sourceSlot:SetAlpha(0) end
    end
    for index = #sourceSlots + 1, #preview.icons do
        preview.icons[index]:Hide()
    end
    preview:SetSize(maxWidth, maxHeight)
    preview:Show()
    frame._yhudDragPreview = preview
    frame._yhudDragPreviewSourceSlots = sourceSlots
    UpdateMonitorDragPreview(frame)
end

local function HideMonitorDragPreview(frame)
    local preview = frame and frame._yhudDragPreview
    if preview then preview:Hide() end
    for index = 1, #(frame and frame._yhudDragPreviewSourceSlots or {}) do
        local sourceSlot = frame._yhudDragPreviewSourceSlots[index]
        if sourceSlot and sourceSlot._yhudDragOriginalAlpha ~= nil then
            if sourceSlot.SetAlpha then
                sourceSlot:SetAlpha(sourceSlot._yhudDragOriginalAlpha)
            end
            sourceSlot._yhudDragOriginalAlpha = nil
        end
    end
    if frame then
        frame._yhudDragPreview = nil
        frame._yhudDragPreviewSourceSlots = nil
    end
end

local function SetBundleDragActive(frame, active)
    active = active == true
    local slots = frame and frame._yhudDragBundleSlots
    local function Apply(slot)
        if slot then slot._yhudDragBundleActive = active end
    end
    Apply(frame)
    for index = 1, #(type(slots) == "table" and slots or {}) do
        Apply(slots[index])
    end
end

local function HideBundleSelectionOutlines(frame)
    local slots = frame and frame._yhudDragBundleSlots
    local function Hide(slot)
        if slot then
            local outline = slot._yhudDesignSelectionOutline
            if outline then SetShown(outline, false) end
        end
    end
    Hide(frame)
    for index = 1, #(type(slots) == "table" and slots or {}) do
        Hide(slots[index])
    end
end

local function RefreshBundleSelectionOutlines(frame)
    local slots = frame and frame._yhudDragBundleSlots
    local function Refresh(slot)
        if not slot then return end
        local outline = slot._yhudDesignSelectionOutline
        if outline then
            View:RefreshDesignSelectionOutline(slot)
            SetShown(outline, slot._yhudDesignSelected == true
                or slot._yhudDesignHovered == true)
        end
    end
    Refresh(frame)
    for index = 1, #(type(slots) == "table" and slots or {}) do
        Refresh(slots[index])
    end
end

GetDragPointer = function(slot)
    if GetCursorPosition and UIParent and UIParent.GetEffectiveScale then
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        if x and y and scale and scale > 0 then return x / scale, y / scale end
    end
    if slot and slot.GetCenter then return slot:GetCenter() end
end

local function DirectionVector(direction)
    if direction == "left" then return -1, 0 end
    if direction == "down" then return 0, -1 end
    if direction == "up" then return 0, 1 end
    return 1, 0
end

local function GetRuntimeAxisSpacing(runtime, horizontal)
    if not runtime then return 0 end
    if runtime.view == "resource" then
        return tonumber(runtime.spacing) or 0
    end
    return tonumber(horizontal and runtime.columnSpacing
        or runtime.rowSpacing) or 0
end

local function IndicatorSide(direction, before)
    if direction == "left" then return before and "RIGHT" or "LEFT" end
    if direction == "down" then return before and "TOP" or "BOTTOM" end
    if direction == "up" then return before and "BOTTOM" or "TOP" end
    return before and "LEFT" or "RIGHT"
end

local function CandidateSlots(candidate)
    if type(candidate and candidate.slots) == "table"
        and #candidate.slots > 0 then
        return candidate.slots
    end
    return candidate and candidate.slot and { candidate.slot } or {}
end

local function PhysicalCandidate(candidate, physicalSlot)
    if type(physicalSlot) == "table"
        and physicalSlot.slot and physicalSlot.x and physicalSlot.y then
        return physicalSlot
    end
    local x, y = physicalSlot and physicalSlot.GetCenter
        and physicalSlot:GetCenter()
    local width, height = FrameSize(physicalSlot)
    return {
        index = candidate.index,
        laneIndex = candidate.laneIndex,
        lane = candidate.lane,
        monitorId = candidate.monitorId,
        slot = physicalSlot,
        slots = candidate.slots,
        x = x or candidate.x,
        y = y or candidate.y,
        width = width,
        height = height,
    }
end

local function CandidatePhysicals(candidate)
    if type(candidate and candidate.physical) == "table"
        and #candidate.physical > 0 then
        return candidate.physical
    end
    return CandidateSlots(candidate)
end

local function LogicalEdgeCandidate(candidate, vectorX, vectorY, before)
    local selected
    local selectedAlong
    for _, physicalSlot in ipairs(CandidatePhysicals(candidate)) do
        local physical = PhysicalCandidate(candidate, physicalSlot)
        local along = physical.x * vectorX + physical.y * vectorY
        if selectedAlong == nil
            or (before and along < selectedAlong)
            or (not before and along > selectedAlong) then
            selected = physical
            selectedAlong = along
        end
    end
    return selected or candidate
end

local function ResolveDropSeam(
    drop,
    snapshot,
    sourceLogicalId,
    sourceSlot,
    cursorX,
    cursorY,
    spacing
)
    if not (drop and drop.targetLane and drop.targetIndex) then return drop end
    local vectorX = drop.vectorX
    local vectorY = drop.vectorY
    if vectorX == nil or vectorY == nil then return drop end
    local ordered = snapshot and snapshot._yhudOrderWithoutSource
    if type(ordered) ~= "table" then
        ordered = {}
        for index = 1, #(snapshot or {}) do
            local candidate = snapshot[index]
            if candidate and candidate.slot ~= sourceSlot
                and candidate.monitorId ~= sourceLogicalId then
                ordered[#ordered + 1] = candidate
            end
        end
    end
    local targetIndex = math.max(1, math.min(#ordered + 1, drop.targetIndex))
    local beforeCandidate = ordered[targetIndex - 1]
    local afterCandidate = ordered[targetIndex]
    local beforePhysical = beforeCandidate and LogicalEdgeCandidate(
        beforeCandidate,
        vectorX,
        vectorY,
        false
    ) or nil
    local afterPhysical = afterCandidate and LogicalEdgeCandidate(
        afterCandidate,
        vectorX,
        vectorY,
        true
    ) or nil
    if not beforePhysical and not afterPhysical then return drop end

    local horizontal = vectorY == 0
    local function Along(candidate)
        return candidate.x * vectorX + candidate.y * vectorY
    end
    local function Cross(candidate)
        return horizontal and candidate.y or candidate.x
    end
    local function AlongExtent(candidate)
        return (horizontal and candidate.width or candidate.height) * 0.5
    end
    local function CrossSize(candidate)
        return horizontal and candidate.height or candidate.width
    end
    local function ToPoint(along, cross)
        if horizontal then return along * vectorX, cross end
        return cross, along * vectorY
    end
    local function DistanceSquared(x, y)
        local deltaX = (cursorX or x) - x
        local deltaY = (cursorY or y) - y
        return deltaX * deltaX + deltaY * deltaY
    end

    local halfSpacing = math.max(0, tonumber(spacing) or 0) * 0.5
    local seamX
    local seamY
    local anchorVariant = "single"
    local sameVisualLine = false
    if beforePhysical and afterPhysical then
        local crossDelta = math.abs(Cross(beforePhysical) - Cross(afterPhysical))
        local tolerance = math.max(
            CrossSize(beforePhysical),
            CrossSize(afterPhysical)
        ) * 0.55
        sameVisualLine = crossDelta <= tolerance
        if sameVisualLine then
            local beforeEdge = Along(beforePhysical)
                + AlongExtent(beforePhysical)
            local afterEdge = Along(afterPhysical)
                - AlongExtent(afterPhysical)
            seamX, seamY = ToPoint(
                (beforeEdge + afterEdge) * 0.5,
                (Cross(beforePhysical) + Cross(afterPhysical)) * 0.5
            )
            anchorVariant = "middle"
        else
            local beforeX, beforeY = ToPoint(
                Along(beforePhysical) + AlongExtent(beforePhysical)
                    + halfSpacing,
                Cross(beforePhysical)
            )
            local afterX, afterY = ToPoint(
                Along(afterPhysical) - AlongExtent(afterPhysical)
                    - halfSpacing,
                Cross(afterPhysical)
            )
            if DistanceSquared(beforeX, beforeY)
                <= DistanceSquared(afterX, afterY) then
                seamX, seamY = beforeX, beforeY
                anchorVariant = "wrap-tail"
            else
                seamX, seamY = afterX, afterY
                anchorVariant = "wrap-head"
            end
        end
    elseif beforePhysical then
        seamX, seamY = ToPoint(
            Along(beforePhysical) + AlongExtent(beforePhysical) + halfSpacing,
            Cross(beforePhysical)
        )
        anchorVariant = "tail"
    else
        seamX, seamY = ToPoint(
            Along(afterPhysical) - AlongExtent(afterPhysical) - halfSpacing,
            Cross(afterPhysical)
        )
        anchorVariant = "head"
    end

    drop.targetIndex = targetIndex
    drop.beforeCandidate = beforeCandidate
    drop.afterCandidate = afterCandidate
    drop.beforePhysical = beforePhysical
    drop.afterPhysical = afterPhysical
    drop.sameVisualLine = sameVisualLine
    drop.seamX = seamX
    drop.seamY = seamY
    drop.seamSpan = math.max(
        beforePhysical and CrossSize(beforePhysical) or 0,
        afterPhysical and CrossSize(afterPhysical) or 0
    ) + 6
    drop.target = ((anchorVariant == "head"
            or anchorVariant == "wrap-head") and afterPhysical)
        or beforePhysical or afterPhysical
    drop.key = tostring(drop.key) .. ":" .. anchorVariant
    return drop
end

local function ResolveMonitorPlacement(drop, snapshot)
    if not drop then return nil end
    local context = type(snapshot) == "table" and snapshot or nil
    local placement
    if drop.afterCandidate == nil and drop.beforeCandidate ~= nil then
        placement = { kind = "tail" }
    elseif drop.beforeCandidate == nil and drop.afterCandidate ~= nil then
        placement = { kind = "head" }
    elseif drop.afterCandidate and drop.afterCandidate.monitorId then
        placement = {
            beforeMonitorId = drop.afterCandidate.monitorId,
        }
    end
    if placement then
        placement.sourceGroupId = context and context._yhudSourceGroupId or nil
        placement.sourceSpecKey = context and context._yhudSourceSpecKey or nil
        drop.placement = placement
    end
    return drop
end

local function IsSpecialDragMonitor(self, monitorId)
    local projection = self.designProjection
    local projectedSlot = projection and projection.byMonitor
        and projection.byMonitor[monitorId]
    local liveSlot = self.byMonitor and self.byMonitor[monitorId]
    local slot = projectedSlot or liveSlot
    local runtime = slot and DesignRuntimeForSlot(slot)
    local runtimePlan = runtime and runtime.presentationGroupPlan
    local runtimeMember = runtimePlan and runtimePlan.memberById
        and runtimePlan.memberById[monitorId]
    if runtimeMember then return runtimeMember.special == true end
    if runtimePlan and runtimePlan.logicalSpecial
        and runtimePlan.logicalSpecial[monitorId] ~= nil then
        return runtimePlan.logicalSpecial[monitorId] == true
    end
    local presentationPlan = projection and projection.presentationPlan
        or self.presentationPlan
    local member = presentationPlan and presentationPlan.membersById
        and presentationPlan.membersById[monitorId]
    if member then return member.special == true end
    if presentationPlan and presentationPlan.logicalSpecial
        and presentationPlan.logicalSpecial[monitorId] ~= nil then
        return presentationPlan.logicalSpecial[monitorId] == true
    end
    return false
end

local function ApplySpecialOverflowDropRule(
    self,
    runtime,
    sourceMonitorId,
    drop
)
    if not (drop and runtime.filteredAuraProjectionStrategy ==
        YHUD.FILTERED_AURA_LAYOUT_MIXED_SEGMENTED_OVERFLOW) then
        return drop
    end
    local sourceSpecial = IsSpecialDragMonitor(self, sourceMonitorId)
    local before = drop.beforeCandidate
    local after = drop.afterCandidate
    local beforeSpecial = before
        and IsSpecialDragMonitor(self, before.monitorId) or false
    local afterSpecial = after
        and IsSpecialDragMonitor(self, after.monitorId) or false
    local valid
    if sourceSpecial then
        valid = afterSpecial
            or (after == nil and beforeSpecial)
    else
        valid = before == nil or beforeSpecial == false
    end
    if valid then return drop end
    drop.invalidLane = true
    drop.invalidSpecialRegion = true
    drop.key = "special-region-invalid"
    return drop
end

local function ResolveDragOrderDirection(runtime)
    if runtime.view == "resource" then
        return runtime.direction or "right"
    end
    local perLine = tonumber(runtime.maxPerLine) or DEFAULT_MAX_PER_LINE
    if runtime.view == "bar"
        and runtime.orientation == "vertical"
        and perLine <= 1 then
        return runtime.wrapDirection == "up" and "left" or "right"
    end
    if perLine <= 1 then
        return runtime.wrapDirection == "up" and "up" or "down"
    end
    if runtime.view == "bar" and runtime.orientation == "vertical" then
        return "down"
    end
    if runtime.view == "icon" and runtime.rowDirection == "left" then
        return "left"
    end
    return "right"
end

function View:ResolveMonitorDrop(runtime, slot, cursorX, cursorY)
    local snapshot = slot and slot._yhudDragSnapshot
    if not (runtime and type(snapshot) == "table" and cursorX and cursorY) then
        return nil
    end

    local sourceIndex
    local nearest
    local nearestDistance
    local minX
    local maxX
    local minY
    local maxY
    local sourceLogicalId = LogicalMonitorId(slot)
    for index = 1, #snapshot do
        local candidate = snapshot[index]
        local sourceCandidate = candidate and (
            candidate.slot == slot
                or (sourceLogicalId ~= nil
                    and candidate.monitorId == sourceLogicalId)
        )
        if candidate then
            for _, physicalSlot in ipairs(CandidatePhysicals(candidate)) do
                local physical = PhysicalCandidate(candidate, physicalSlot)
                minX = math.min(
                    minX or physical.x,
                    physical.x - physical.width * 0.5
                )
                maxX = math.max(
                    maxX or physical.x,
                    physical.x + physical.width * 0.5
                )
                minY = math.min(
                    minY or physical.y,
                    physical.y - physical.height * 0.5
                )
                maxY = math.max(
                    maxY or physical.y,
                    physical.y + physical.height * 0.5
                )
                if not sourceCandidate then
                    local deltaX = cursorX - physical.x
                    local deltaY = cursorY - physical.y
                    local distance = deltaX * deltaX + deltaY * deltaY
                    if not nearestDistance or distance < nearestDistance then
                        nearest = candidate
                        nearestDistance = distance
                    end
                end
            end
        end
        if sourceCandidate then
            sourceIndex = index
        end
    end
    if not sourceIndex
        or cursorX < (minX or cursorX) - DRAG_GROUP_PADDING
        or cursorX > (maxX or cursorX) + DRAG_GROUP_PADDING
        or cursorY < (minY or cursorY) - DRAG_GROUP_PADDING
        or cursorY > (maxY or cursorY) + DRAG_GROUP_PADDING then
        return nil
    end
    if not nearest then
        return ApplySpecialOverflowDropRule(
            self,
            runtime,
            sourceLogicalId,
            ResolveMonitorPlacement(ResolveDropSeam({
            operation = "insert",
            sourceIndex = sourceIndex,
            sourceLane = YHUD.CONTENT_LANE_SPEC,
            sourceLaneIndex = sourceIndex,
            targetLane = YHUD.CONTENT_LANE_SPEC,
            targetIndex = sourceIndex,
            key = "insert:" .. tostring(sourceIndex),
            vectorX = 1,
            vectorY = 0,
            }, snapshot, sourceLogicalId, slot, cursorX, cursorY,
                GetRuntimeAxisSpacing(runtime, true)), snapshot)
        )
    end

    local orderDirection = ResolveDragOrderDirection(runtime)
    local vectorX, vectorY = DirectionVector(orderDirection)
    local axisSpacing = GetRuntimeAxisSpacing(runtime, vectorY == 0)
    local firstNearest = LogicalEdgeCandidate(nearest, vectorX, vectorY, true)
    local lastNearest = LogicalEdgeCandidate(nearest, vectorX, vectorY, false)
    local blockCenter = (
        firstNearest.x * vectorX + firstNearest.y * vectorY
        + lastNearest.x * vectorX + lastNearest.y * vectorY
    ) * 0.5
    local pointerAlong = cursorX * vectorX + cursorY * vectorY
    local before = pointerAlong < blockCenter
    local targetIndex = before and nearest.index or nearest.index + 1
    if sourceIndex < targetIndex then targetIndex = targetIndex - 1 end
    targetIndex = math.max(1, math.min(#snapshot, targetIndex))
    local indicatorTarget = LogicalEdgeCandidate(
        nearest,
        vectorX,
        vectorY,
        before
    )
    return ApplySpecialOverflowDropRule(
        self,
        runtime,
        sourceLogicalId,
        ResolveMonitorPlacement(ResolveDropSeam({
        operation = "insert",
        sourceIndex = sourceIndex,
        sourceLane = YHUD.CONTENT_LANE_SPEC,
        sourceLaneIndex = sourceIndex,
        targetLane = YHUD.CONTENT_LANE_SPEC,
        targetIndex = targetIndex,
        target = indicatorTarget,
        before = before,
        side = IndicatorSide(orderDirection, before),
        vectorX = vectorX,
        vectorY = vectorY,
        key = "insert:" .. tostring(targetIndex),
        }, snapshot, sourceLogicalId, slot, cursorX, cursorY, axisSpacing), snapshot)
    )
end

function View:EnsureMonitorDropFeedback(runtime)
    if not runtime.designDropIndicator and GUI2.CreatePanel then
        runtime.designDropIndicator = GUI2:CreatePanel(runtime.frame, {
            surface = "color.state.warning",
            border = "color.state.warning",
            mouse = false,
            hidden = true,
        })
        runtime.designDropIndicator:Hide()
    end
    if not runtime.designDropBadge
        and runtime.designDropIndicator
        and GUI2.Data and GUI2.Data.CreateBadge then
        runtime.designDropBadge = GUI2.Data:CreateBadge(runtime.frame, {
            text = YHUD:T("designer.drag.insert_here", "插入此处"),
            height = 22,
            minWidth = 58,
            paddingX = 8,
            autoWidth = true,
            surface = "color.surface.raised",
            border = "color.border.accent",
            textColor = "color.text.accent",
        })
        runtime.designDropBadge:SetPoint(
            "BOTTOM",
            runtime.designDropIndicator,
            "TOP",
            0,
            4
        )
        runtime.designDropBadge:Hide()
    end
    runtime.designForbiddenOverlays =
        runtime.designForbiddenOverlays or {}
    return runtime.designDropIndicator
end

local function EnsureForbiddenOverlay(runtime, index)
    local overlays = runtime.designForbiddenOverlays
    local overlay = overlays[index]
    if overlay then return overlay end
    overlay = GUI2:CreateFrame(runtime.frame, {
        mouse = false,
        hidden = true,
    })
    if overlay.CreateTexture then
        local fill = overlay:CreateTexture(nil, "OVERLAY")
        fill:SetAllPoints(overlay)
        if fill.SetColorTexture then
            fill:SetColorTexture(0.78, 0.08, 0.08, 1)
        end
        overlay._yhudFill = fill
    end
    overlay:Hide()
    overlays[index] = overlay
    return overlay
end

local function BuildBundleForbiddenSegments(
    self,
    snapshot,
    sourceLogical,
    horizontal,
    sourceSpecial,
    segmented
)
    local segments = {}
    for index = 1, #(snapshot or {}) do
        local group = snapshot[index]
        local physical = CandidatePhysicals(group)
        local groupSpecial = group
            and IsSpecialDragMonitor(self, group.monitorId) or false
        local coveredBySpecialRegion = segmented == true
            and groupSpecial ~= sourceSpecial
        if group and group.monitorId ~= sourceLogical
            and #physical > 1 and not coveredBySpecialRegion then
            local current
            for candidateIndex = 1, #physical do
                local candidate = PhysicalCandidate(group, physical[candidateIndex])
                local cross = horizontal and candidate.y or candidate.x
                local tolerance = horizontal
                    and candidate.height * 0.55 or candidate.width * 0.55
                if not current
                    or math.abs(cross - current.cross) > tolerance then
                    current = {
                        logicalId = group.monitorId,
                        cross = cross,
                        candidates = {},
                    }
                    segments[#segments + 1] = current
                end
                current.candidates[#current.candidates + 1] = candidate
            end
        end
    end
    return segments
end

local function BuildSpecialForbiddenSegments(
    self,
    snapshot,
    sourceLogical,
    horizontal,
    sourceSpecial
)
    local segments = {}
    for index = 1, #(snapshot or {}) do
        local group = snapshot[index]
        if group and group.monitorId ~= sourceLogical
            and IsSpecialDragMonitor(self, group.monitorId) ~= sourceSpecial then
            local physical = CandidatePhysicals(group)
            for candidateIndex = 1, #physical do
                local candidate = PhysicalCandidate(group, physical[candidateIndex])
                local cross = horizontal and candidate.y or candidate.x
                local tolerance = horizontal
                    and candidate.height * 0.55 or candidate.width * 0.55
                local segment
                for segmentIndex = 1, #segments do
                    local existing = segments[segmentIndex]
                    if math.abs(cross - existing.cross)
                        <= math.max(tolerance, existing.tolerance) then
                        segment = existing
                        break
                    end
                end
                if not segment then
                    segment = {
                        cross = cross,
                        tolerance = tolerance,
                        logicalIds = {},
                        candidates = {},
                    }
                    segments[#segments + 1] = segment
                end
                segment.logicalIds[group.monitorId] = true
                segment.candidates[#segment.candidates + 1] = candidate
            end
        end
    end
    return segments
end

local function AnchorForbiddenOverlay(runtime, overlay, segment, horizontal)
    local candidates = segment.candidates
    local first = candidates[1]
    local last = candidates[1]
    local frameLevel = runtime.frame.GetFrameLevel
        and runtime.frame:GetFrameLevel() or 0
    for index = 2, #candidates do
        local candidate = candidates[index]
        if horizontal then
            if candidate.x < first.x then first = candidate end
            if candidate.x > last.x then last = candidate end
        else
            if candidate.y > first.y then first = candidate end
            if candidate.y < last.y then last = candidate end
        end
    end
    for index = 1, #candidates do
        local candidate = candidates[index]
        if candidate.slot and candidate.slot.GetFrameLevel then
            frameLevel = math.max(
                frameLevel,
                candidate.slot:GetFrameLevel() or 0
            )
        end
    end
    if overlay.SetFrameStrata and runtime.frame.GetFrameStrata then
        overlay:SetFrameStrata(runtime.frame:GetFrameStrata())
    end
    if overlay.SetFrameLevel then
        overlay:SetFrameLevel(frameLevel + 20)
    end
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", first.slot, "TOPLEFT", -2, 2)
    overlay:SetPoint("BOTTOMRIGHT", last.slot, "BOTTOMRIGHT", 2, -2)
end

function View:UpdateForbiddenLaneOverlays(runtime, slot, drop)
    self:EnsureMonitorDropFeedback(runtime)
    local snapshot = slot and slot._yhudDragSnapshot or {}
    local direction = ResolveDragOrderDirection(runtime)
    local horizontal = direction == "right" or direction == "left"
    local sourceLogical = LogicalMonitorId(slot)
    local segmented = runtime.filteredAuraProjectionStrategy ==
        YHUD.FILTERED_AURA_LAYOUT_MIXED_SEGMENTED_OVERFLOW
    local sourceSpecial = IsSpecialDragMonitor(self, sourceLogical)
    local segments = BuildBundleForbiddenSegments(
        self,
        snapshot,
        sourceLogical,
        horizontal,
        sourceSpecial,
        segmented
    )
    if segmented then
        local specialSegments = BuildSpecialForbiddenSegments(
            self,
            snapshot,
            sourceLogical,
            horizontal,
            sourceSpecial
        )
        for index = 1, #specialSegments do
            segments[#segments + 1] = specialSegments[index]
        end
    end
    for index = 1, #segments do
        local segment = segments[index]
        local overlay = EnsureForbiddenOverlay(runtime, index)
        AnchorForbiddenOverlay(runtime, overlay, segment, horizontal)
        local hovered = drop and (
            segment.logicalId
                and drop.target
                and drop.target.monitorId == segment.logicalId
            or segment.logicalIds
                and drop.target
                and segment.logicalIds[drop.target.monitorId] == true
        )
        if overlay.SetAlpha then overlay:SetAlpha(hovered and 0.40 or 0.22) end
        overlay:Show()
    end
    local used = #segments
    for index = used + 1, #(runtime.designForbiddenOverlays or {}) do
        runtime.designForbiddenOverlays[index]:Hide()
    end
end

local function ApplyMakeRoomPoint(slot, shiftX, shiftY)
    local base = slot and slot._yhudDragMakeRoomBase
    if not (base and slot.ClearAllPoints and slot.SetPoint) then return end
    slot:ClearAllPoints()
    slot:SetPoint(
        base[1],
        base[2],
        base[3],
        base[4] + shiftX,
        base[5] + shiftY
    )
end

local function AnimateMakeRoomSlot(runtime, slot, shiftX, shiftY)
    if not (slot and slot.ClearAllPoints and slot.SetPoint) then return end
    if not slot._yhudDragMakeRoomBase then
        local point, relativeTo, relativePoint, offsetX, offsetY =
            ReadAnchor(slot)
        slot._yhudDragMakeRoomBase = {
            point or "TOPLEFT",
            relativeTo or UIParent,
            relativePoint or "TOPLEFT",
            offsetX or 0,
            offsetY or 0,
        }
    end
    local fromX = slot._yhudDragMakeRoomShiftX or 0
    local fromY = slot._yhudDragMakeRoomShiftY or 0
    if fromX == shiftX and fromY == shiftY then
        ApplyMakeRoomPoint(slot, shiftX, shiftY)
        return
    end
    slot._yhudDragMakeRoomShiftX = shiftX
    slot._yhudDragMakeRoomShiftY = shiftY
    if Animation and Animation.Tween then
        local owner = slot._yhudDragMakeRoomOwner
        if not owner then
            owner = {}
            slot._yhudDragMakeRoomOwner = owner
        end
        Animation:StopOwner(owner, false)
        Animation:Tween({
            owner = owner,
            target = slot,
            key = "yhud-drag-make-room",
            from = 0,
            to = 1,
            duration = DRAG_MAKE_ROOM_SECONDS,
            easing = "out",
            onUpdate = function(progress)
                local base = slot._yhudDragMakeRoomBase
                if not base then return end
                slot:ClearAllPoints()
                slot:SetPoint(
                    base[1],
                    base[2],
                    base[3],
                    base[4] + fromX + (shiftX - fromX) * progress,
                    base[5] + fromY + (shiftY - fromY) * progress
                )
            end,
            onFinished = function(_, _, finished)
                if finished then ApplyMakeRoomPoint(slot, shiftX, shiftY) end
            end,
        })
    else
        ApplyMakeRoomPoint(slot, shiftX, shiftY)
    end
end

local function RestoreMakeRoom(runtime)
    local session = runtime and runtime._yhudDragMakeRoom
    if not session then return end
    for index = 1, #(session.slots or {}) do
        local slot = session.slots[index]
        if slot then
            if Animation and Animation.StopOwner
                and slot._yhudDragMakeRoomOwner then
                Animation:StopOwner(slot._yhudDragMakeRoomOwner, false)
            end
            local base = slot._yhudDragMakeRoomBase
            if base and slot.SetPoint then
                slot:ClearAllPoints()
                slot:SetPoint(base[1], base[2], base[3], base[4], base[5])
            end
            slot._yhudDragMakeRoomBase = nil
            slot._yhudDragMakeRoomShiftX = nil
            slot._yhudDragMakeRoomShiftY = nil
            slot._yhudDragMakeRoomOwner = nil
        end
    end
    runtime._yhudDragMakeRoom = nil
    runtime._yhudDragMakeRoomKey = nil
end

function View:UpdateMakeRoomFeedback(runtime, slot, drop)
    if not (runtime and slot) then return false end
    local key = drop and drop.key or "none"
    if runtime._yhudDragMakeRoomKey == key then return false end
    RestoreMakeRoom(runtime)
    runtime._yhudDragMakeRoomKey = key
    if not (drop and drop.operation == "insert"
        and drop.target and not drop.invalidLane
        and drop.sameVisualLine == true
        and drop.beforeCandidate and drop.afterCandidate) then
        return false
    end
    local orderDirection = ResolveDragOrderDirection(runtime)
    local vectorX, vectorY = DirectionVector(orderDirection)
    local session = { slots = {} }
    local function Shift(candidate, dirX, dirY)
        if not (candidate and candidate.slot) then return end
        for _, physicalSlot in ipairs(CandidateSlots(candidate)) do
            session.slots[#session.slots + 1] = physicalSlot
            AnimateMakeRoomSlot(
                runtime,
                physicalSlot,
                dirX * DRAG_MAKE_ROOM_PIXELS,
                dirY * DRAG_MAKE_ROOM_PIXELS
            )
        end
    end
    Shift(drop.beforeCandidate, -vectorX, -vectorY)
    Shift(drop.afterCandidate, vectorX, vectorY)
    runtime._yhudDragMakeRoom = session
    return true
end

function View:ClearMonitorDropFeedback(runtime)
    if runtime then
        runtime.designDropFeedbackKey = nil
        RestoreMakeRoom(runtime)
        if runtime.designDropIndicator then runtime.designDropIndicator:Hide() end
        if runtime.designDropBadge then runtime.designDropBadge:Hide() end
        for index = 1, #(runtime.designForbiddenOverlays or {}) do
            runtime.designForbiddenOverlays[index]:Hide()
        end
    end
end

function View:UpdateMonitorDropFeedback(runtime, slot, drop)
    if not (runtime and slot) then return false end
    local snapshot = slot._yhudDragSnapshot
    local key = drop and drop.key or "none"
    if runtime.designDropFeedbackKey == key then return false end
    runtime.designDropFeedbackKey = key
    local indicator = self:EnsureMonitorDropFeedback(runtime)
    self:UpdateForbiddenLaneOverlays(runtime, slot, drop)

    if not (drop and indicator and drop.target) then
        if indicator then indicator:Hide() end
        if runtime.designDropBadge then runtime.designDropBadge:Hide() end
        return false
    end
    local horizontal = drop.vectorY == 0
    local halfSpacing = GetRuntimeAxisSpacing(runtime, horizontal) * 0.5
    local indicatorX = 0
    local indicatorY = 0
    if drop.side == "LEFT" then
        indicatorX = indicatorX - halfSpacing
    elseif drop.side == "RIGHT" then
        indicatorX = indicatorX + halfSpacing
    elseif drop.side == "TOP" then
        indicatorY = indicatorY + halfSpacing
    elseif drop.side == "BOTTOM" then
        indicatorY = indicatorY - halfSpacing
    end
    indicator:ClearAllPoints()
    if drop.seamX and drop.seamY then
        if horizontal then
            indicator:SetSize(
                DRAG_INDICATOR_SIZE,
                drop.seamSpan or (drop.target.height + 6)
            )
        else
            indicator:SetSize(
                drop.seamSpan or (drop.target.width + 6),
                DRAG_INDICATOR_SIZE
            )
        end
        indicator:SetPoint(
            "CENTER",
            UIParent,
            "BOTTOMLEFT",
            drop.seamX,
            drop.seamY
        )
    elseif horizontal then
        indicator:SetSize(DRAG_INDICATOR_SIZE, drop.target.height + 6)
        indicator:SetPoint(
            "CENTER",
            drop.target.slot,
            drop.side,
            indicatorX,
            indicatorY
        )
    else
        indicator:SetSize(drop.target.width + 6, DRAG_INDICATOR_SIZE)
        indicator:SetPoint(
            "CENTER",
            drop.target.slot,
            drop.side,
            indicatorX,
            indicatorY
        )
    end
    if indicator.SetFrameLevel and drop.target.slot.GetFrameLevel then
        indicator:SetFrameLevel(drop.target.slot:GetFrameLevel() + 14)
    end
    local badge = runtime.designDropBadge
    if badge then
        local key = drop.invalidSpecialRegion == true
                and "designer.drag.special_region_forbidden"
            or drop.magnet == "before"
                and "designer.drag.magnet_before"
            or drop.magnet == "after"
                and "designer.drag.magnet_after"
            or "designer.drag.insert_here"
        local fallback = drop.invalidSpecialRegion == true
                and "特殊监控与其他监控只能在各自区域内调整顺序"
            or drop.magnet == "before"
                and "将放到原生区之前"
            or drop.magnet == "after"
                and "将放到原生区之后"
            or "插入此处"
        badge:SetText(YHUD:T(key, fallback))
        if badge.SetFrameStrata and runtime.frame.GetFrameStrata then
            badge:SetFrameStrata(runtime.frame:GetFrameStrata())
        end
        if badge.SetFrameLevel and indicator.GetFrameLevel then
            local badgeLevel = indicator:GetFrameLevel() + 1
            local overlays = runtime.designForbiddenOverlays or {}
            for index = 1, #overlays do
                local overlay = overlays[index]
                if overlay and overlay.GetFrameLevel then
                    badgeLevel = math.max(
                        badgeLevel,
                        (overlay:GetFrameLevel() or 0) + 1
                    )
                end
            end
            badge:SetFrameLevel(badgeLevel)
        end
        badge:Show()
    end
    indicator:Show()
    return true
end

function View:UpdateMonitorDrag(slot)
    if not (slot and slot._yhudDragging) then return false end
    local runtime = DesignRuntimeForSlot(slot)
    if not runtime then return false end
    local cursorX, cursorY = GetDragPointer(slot)
    UpdateMonitorDragPreview(slot, cursorX, cursorY)
    local drop = self:ResolveMonitorDrop(runtime, slot, cursorX, cursorY)
    slot._yhudDrop = drop
    self:UpdateMakeRoomFeedback(runtime, slot, drop)
    self:UpdateMonitorDropFeedback(runtime, slot, drop)
    return drop ~= nil
end

function View:SetOtherGroupsDragDimmed(sourceRuntime, dimmed)
    local groups = sourceRuntime and sourceRuntime._yhudDesignProjection
        and self.designProjection and self.designProjection.groups
        or self.groups
    for _, runtime in pairs(groups or {}) do
        if runtime ~= sourceRuntime and runtime.frame then
            if dimmed then
                if runtime._yhudDragPreviousAlpha == nil then
                    runtime._yhudDragPreviousAlpha = runtime.frame.GetAlpha
                        and runtime.frame:GetAlpha() or 1
                end
                if runtime.frame.SetAlpha then runtime.frame:SetAlpha(0.36) end
            elseif runtime._yhudDragPreviousAlpha ~= nil then
                if runtime.frame.SetAlpha then
                    runtime.frame:SetAlpha(runtime._yhudDragPreviousAlpha)
                end
                runtime._yhudDragPreviousAlpha = nil
            end
        end
    end
end

function View:FinishMonitorDrag(slot, cancelled)
    if not slot or slot._yhudFinishingDrag then return false end
    if not slot._yhudDragging then return false end
    slot._yhudFinishingDrag = true
    if slot.StopMovingOrSizing then slot:StopMovingOrSizing() end
    slot:SetScript("OnUpdate", nil)

    local runtime = DesignRuntimeForSlot(slot)
    local drop = slot._yhudDrop
    self:ClearMonitorDropFeedback(runtime)
    self:SetOtherGroupsDragDimmed(runtime, false)
    slot._yhudDragging = nil
    slot._yhudDragElapsed = nil
    slot._yhudDragSnapshot = nil
    HideMonitorDragPreview(slot)
    SetBundleDragActive(slot, false)
    RefreshBundleSelectionOutlines(slot)
    slot._yhudDragBundleSlots = nil
    slot._yhudDrop = nil
    if self.activeMonitorDrag == slot then self.activeMonitorDrag = nil end

    local placement = runtime and runtime.view ~= "resource"
        and drop and drop.placement or nil
    local noOrderChange = not placement and drop
        and drop.operation == "insert"
        and drop.targetLane == drop.sourceLane
        and drop.targetIndex == drop.sourceLaneIndex
    local handled = cancelled ~= true
        and drop
        and drop.invalidSpecialRegion ~= true
        and not noOrderChange
        and self.designReorderMonitor
        and self.designReorderMonitor(
            slot._yhudLogicalMonitorId or slot._yhudMonitorId,
            drop.targetLane,
            drop.targetIndex,
            placement
        ) == true
    if runtime and runtime._yhudDesignProjection ~= true then
        self:RelayoutGroup(runtime.id)
    end
    slot._yhudFinishingDrag = nil
    return handled == true
end

function View:CancelMonitorDrag()
    local slot = self.activeMonitorDrag
    if not slot then return false end
    return self:FinishMonitorDrag(slot, true)
end

local function DesignSlotOnUpdate(frame, elapsed)
    if not frame._yhudDragging then return end
    frame._yhudDragElapsed = (frame._yhudDragElapsed or 0) + (elapsed or 0)
    if frame._yhudDragElapsed > 0.05
        and IsMouseButtonDown
        and not IsMouseButtonDown("LeftButton") then
        View:FinishMonitorDrag(frame, false)
        return
    end
    View:UpdateMonitorDrag(frame)
end

local function DesignSlotOnHide(frame)
    if frame._yhudDragging and not frame._yhudFinishingDrag then
        View:FinishMonitorDrag(frame, true)
    end
end

function View:ClearResourcePreviewSlot(slot)
    local preview = slot and slot._yhudDesignResourcePreview
    if not preview then return false end
    preview:Hide()
    if slot._yhudDesignResourceTrackAlpha ~= nil then
        slot.track:SetAlpha(slot._yhudDesignResourceTrackAlpha)
        slot._yhudDesignResourceTrackAlpha = nil
    end
    if preview.ClearResourceValues then preview:ClearResourceValues() end
    if slot._yhudDesignResourcePreviewBound
        and preview.ReleaseFilteredAuraDisplays then
        preview:ReleaseFilteredAuraDisplays()
    end
    preview._yhudPreviewResourceId = nil
    preview._yhudPreviewValue = nil
    preview._yhudPreviewMaxValue = nil
    preview._yhudPreviewRune = nil
    slot._yhudDesignResourcePreviewBound = nil
    slot._yhudDesignResourcePreviewAppearanceDirty = true
    return true
end

function View:ClearDesignSlot(slot)
    if not slot then return end
    if slot._yhudDesignProjection == true and self.ApplyMonitorGlow then
        slot._yhudGlowRuntime = nil
        self:ApplyMonitorGlow(slot, nil, nil)
    end
    slot._yhudRestrictedGlowPreview = nil
    local retainsRestrictedGlowContext =
        slot._yhudFilteredAuraGlow == true
        or slot._yhudFilteredAuraChainCompatible == true
    if not retainsRestrictedGlowContext
        and slot.gui2Glow and slot.gui2Glow._SetGlowLayoutContext then
        slot.gui2Glow:_SetGlowLayoutContext(false)
    end
    self:ClearResourcePreviewSlot(slot)
    if I.CancelDesignTooltip then I.CancelDesignTooltip(slot) end
    local runtime = DesignRuntimeForSlot(slot)
    if slot._yhudDragging then self:FinishMonitorDrag(slot, true) end
    HideMonitorDragPreview(slot)
    slot:SetScript("OnUpdate", nil)
    slot:SetScript("OnMouseDown", nil)
    slot:SetScript("OnDragStart", nil)
    slot:SetScript("OnDragStop", nil)
    I.SetSlotMouseInput(slot, slot._yhudTooltipEnabled, false)
    if slot.SetMovable then slot:SetMovable(false) end
    if slot.SetClampedToScreen and slot._yhudDesignWasClamped ~= nil then
        slot:SetClampedToScreen(slot._yhudDesignWasClamped)
    end
    slot._yhudDesignWasClamped = nil
    slot._yhudDesignResourceId = nil
    slot._yhudDragPairId = nil
    SetShown(slot._yhudDesignTextOverlay, false)
    SetShown(slot._yhudDesignDurationTextOverlay, false)
    SetShown(slot._yhudDesignCooldownText, false)
    SetShown(slot._yhudDesignCountText, false)
    SetShown(slot._yhudDesignNameText, false)
    if slot._yhudDesignCooldownTextState then
        slot._yhudDesignCooldownTextState.shown = nil
    end
    if slot._yhudDesignCountTextState then
        slot._yhudDesignCountTextState.shown = nil
    end
    if slot._yhudDesignNameTextState then
        slot._yhudDesignNameTextState.shown = nil
    end
    local iconSlot = ResolveDesignIconSlot(slot)
    local actualCount = ResolveDesignCount(slot, iconSlot)
    if slot._yhudDesignActualCountWasShown ~= nil
        and (type(actualCount) == "table"
            or type(actualCount) == "userdata") then
        SetShown(
            actualCount,
            runtime and runtime.countText == true
        )
    end
    slot._yhudDesignActualCountWasShown = nil
    local actualName = slot.durationNameText
    if slot._yhudDesignActualNameWasShown ~= nil and actualName then
        SetShown(
            actualName,
            runtime and runtime.nameText ~= false
                and runtime.orientation ~= "vertical"
        )
    end
    slot._yhudDesignActualNameWasShown = nil
    local cooldown = ResolveDesignCooldown(slot, iconSlot)
    if cooldown and cooldown.SetHideCountdownNumbers
        and slot._yhudDesignCooldownWasHidden ~= nil then
        cooldown:SetHideCountdownNumbers(
            not runtime
                or (slot._yhudView == "icon"
                    and runtime.cooldownText == false)
                or (slot._yhudView ~= "icon"
                    and runtime.timeText == false)
        )
    end
    slot._yhudDesignCooldownWasHidden = nil
    slot._yhudDesignHovered = false
    self:SetDesignSlotSelected(slot, false)
end

function View:SetDesignSlotSelected(slot, selected)
    if not slot then return false end
    selected = selected == true
    local changed = slot._yhudDesignSelected ~= selected
    slot._yhudDesignSelected = selected
    local shown = (selected or slot._yhudDesignHovered == true)
        and slot._yhudDragBundleActive ~= true
    local outline = shown
        and self:EnsureDesignSelectionOutline(slot)
        or slot._yhudDesignSelectionOutline
    if outline then
        self:RefreshDesignSelectionOutline(slot)
        SetShown(outline, shown)
    end
    return changed
end

function View:SetDesignSlotHovered(slot, hovered)
    if not slot then return false end
    if self.designMode ~= true then return false end
    AddPerformanceStat("designHoverEvents")
    hovered = hovered == true
    local changed = slot._yhudDesignHovered ~= hovered
    if not changed then return false end
    slot._yhudDesignHovered = hovered
    local shown = (slot._yhudDesignSelected == true or hovered)
        and slot._yhudDragBundleActive ~= true
    local outline = shown
        and self:EnsureDesignSelectionOutline(slot)
        or slot._yhudDesignSelectionOutline
    if outline then
        local mode = slot._yhudDesignSelected == true
            and "selected" or "hover"
        if shown and slot._yhudDesignOutlineMode ~= mode then
            self:RefreshDesignSelectionOutline(slot)
        end
        SetShown(outline, shown)
    end
    return changed
end

function View:ConfigureDesignSlotInteraction(slot)
    if not slot then return false end
    local projection = DesignProjectionForSlot(slot)
    local desiredMonitors = projection
        and projection.desiredMonitors or self.desiredMonitors
    local runtimeMonitor = slot._yhudMonitorId
        and desiredMonitors
        and desiredMonitors[slot._yhudMonitorId]
    local resource = runtimeMonitor and runtimeMonitor._yhudResource
    local readOnlyPreview = runtimeMonitor
        and runtimeMonitor._yhudReadOnlyPreview == true
    local cacheOnlyPreview = runtimeMonitor
        and runtimeMonitor._yhudCacheOnlyPreview == true
    if not self.designMode
        or (slot._yhudSynthetic == true and not resource) then
        self:ClearDesignSlot(slot)
        return false
    end
    slot._yhudDesignResourceId = resource and resource.id or nil
    local runtime = DesignRuntimeForSlot(slot)
    slot._yhudDragPairId = runtime and runtime.handPairMode == "split" and resource
        and (resource.id == "swingMainHand" or resource.id == "swingOffHand")
        and (slot._yhudGroupId .. ":swingHands") or nil
    local dragEnabled = slot._yhudView ~= "ring"
        and not readOnlyPreview
    if not dragEnabled and slot._yhudDragging then
        self:FinishMonitorDrag(slot, true)
    end

    I.SetSlotMouseInput(slot, slot._yhudTooltipEnabled, true)
    if slot.SetMovable then slot:SetMovable(dragEnabled) end
    if slot.SetClampedToScreen then
        if slot._yhudDesignWasClamped == nil then
            slot._yhudDesignWasClamped = slot.IsClampedToScreen
                and slot:IsClampedToScreen() or false
        end
        slot:SetClampedToScreen(true)
    end
    if slot.RegisterForDrag then
        if dragEnabled then
            slot:RegisterForDrag("LeftButton")
        else
            slot:RegisterForDrag()
        end
    end
    self:SetDesignSlotSelected(
        slot,
        resource and slot._yhudGroupId == self.selectedGroupId
            and resource.id == self.resourceStylePreviewResourceId
            or (slot._yhudLogicalMonitorId or slot._yhudMonitorId)
                == self.selectedMonitorId
    )

    if not slot._yhudDesignMouseDown then
        slot._yhudDesignMouseDown = function(frame, button)
            if button == "LeftButton" and View.designSelectMonitor then
                if frame._yhudDesignResourceId then
                    View.designSelectMonitor(
                        nil,
                        frame._yhudDesignResourceId,
                        frame._yhudGroupId
                    )
                else
                    View.designSelectMonitor(
                        frame._yhudLogicalMonitorId or frame._yhudMonitorId
                    )
                end
            end
        end
        slot._yhudDesignDragStart = function(frame)
            if not View.designMode then return end
            if frame._yhudReadOnlyPreview == true then return end
            if not frame._yhudDesignResourceId
                and View.designSelectMonitor
                and (frame._yhudLogicalMonitorId or frame._yhudMonitorId)
                    ~= View.selectedMonitorId then
                View.designSelectMonitor(
                    frame._yhudLogicalMonitorId or frame._yhudMonitorId
                )
            end
            local runtime = DesignRuntimeForSlot(frame)
            if not runtime then return end
            if View.activeMonitorDrag and View.activeMonitorDrag ~= frame then
                View:FinishMonitorDrag(View.activeMonitorDrag, true)
            end
            frame._yhudDragSnapshot = CaptureDragSnapshot(runtime, frame)
            frame._yhudDragging = true
            frame._yhudDragElapsed = 0
            frame._yhudDragBundleSlots = CollectBundleDragSlots(runtime, frame)
            SetBundleDragActive(frame, true)
            HideBundleSelectionOutlines(frame)
            View.activeMonitorDrag = frame
            View:SetOtherGroupsDragDimmed(runtime, true)
            ShowMonitorDragPreview(runtime, frame)
            frame:SetScript("OnUpdate", DesignSlotOnUpdate)
            View:UpdateMonitorDrag(frame)
        end
        slot._yhudDesignDragStop = function(frame)
            View:FinishMonitorDrag(frame, false)
        end
        if slot.HookScript then slot:HookScript("OnHide", DesignSlotOnHide) end
    end
    slot._yhudReadOnlyPreview = readOnlyPreview
    slot._yhudCacheOnlyPreview = cacheOnlyPreview
    if not slot._yhudDesignHoverHooked and slot.HookScript then
        slot._yhudDesignHoverHooked = true
        slot:HookScript("OnEnter", function(frame)
            View:SetDesignSlotHovered(frame, true)
        end)
        slot:HookScript("OnLeave", function(frame)
            View:SetDesignSlotHovered(frame, false)
        end)
    end
    slot:SetScript("OnMouseDown", slot._yhudDesignMouseDown)
    slot:SetScript(
        "OnDragStart",
        dragEnabled and slot._yhudDesignDragStart or nil
    )
    slot:SetScript(
        "OnDragStop",
        dragEnabled and slot._yhudDesignDragStop or nil
    )
    if self.designDurationPreviewEnabled
        and (slot._yhudView == "ring" or slot._yhudView == "bar") then
        self:ApplyDesignDurationPreview(slot)
    end
    return true
end

function View:ConfigureDesignSlot(slot)
    if not self:ConfigureDesignSlotInteraction(slot) then return false end
    self:EnsureDesignTextPreview(slot)
    self:ApplyDesignTextPreview(slot)
    return true
end

function View:SetPreview(enabled, suppressRefresh)
    enabled = enabled == true
    if not enabled then
        for _, slot in pairs(self.byMonitor or {}) do
            self:ClearResourcePreviewSlot(slot)
        end
    end
    if self.preview == enabled then return false end
    self.preview = enabled
    if suppressRefresh == true then return true end
    return self:RefreshAll()
end

function View:SetLayoutEditMode(enabled, suppressRefresh)
    enabled = enabled == true
    if self.layoutEditMode == enabled then return false end
    self.layoutEditMode = enabled
    if suppressRefresh == true then return true end
    return self:Relayout()
end

function View:SetResourcePreviewContext(
    classFile,
    specID,
    formKey,
    suppressRefresh
)
    if type(formKey) == "boolean" and suppressRefresh == nil then
        suppressRefresh = formKey
        formKey = nil
    end
    classFile = type(classFile) == "string"
        and string.upper(classFile) or nil
    specID = tonumber(specID)
    if specID then specID = math.floor(specID) end
    if self.resourcePreviewClassFile == classFile
        and self.resourcePreviewSpecID == specID
        and self.resourcePreviewFormKey == formKey then
        return false
    end
    self.resourcePreviewClassFile = classFile
    self.resourcePreviewSpecID = specID
    self.resourcePreviewFormKey = type(formKey) == "string" and formKey or nil
    if self.profile and suppressRefresh ~= true then
        self:ApplyConfig(self.profile)
    end
    return true
end

function View:SetResourceStylePreviewResource(resourceId, suppressRefresh, groupId)
    local definition = resourceId and ResourceCatalog
        and ResourceCatalog.GetDefinition
        and ResourceCatalog:GetDefinition(resourceId) or nil
    resourceId = definition and definition.id or nil
    groupId = resourceId and groupId or nil
    if self.resourceStylePreviewResourceId == resourceId
        and self.resourceStylePreviewGroupId == groupId then return false end
    self.resourceStylePreviewResourceId = resourceId
    self.resourceStylePreviewGroupId = groupId
    if self.profile and suppressRefresh ~= true then
        self:ApplyConfig(self.profile)
    end
    return true
end

local function SyncDesignResourcePreviewAppearance(slot, preview)
    if not (slot and preview) then return false end
    local startedAt = ProfileNowMS()
    AddPerformanceStat("resourcePreviewAppearanceSyncs", 1)

    if preview.SetResourceBarSize then
        preview:SetResourceBarSize(
            slot.gui2ResourceWidth
                or (slot.GetWidth and slot:GetWidth()) or 290,
            slot.gui2ResourceHeight
                or (slot.GetHeight and slot:GetHeight()) or 16,
            slot.gui2ResourceOrientation
        )
    end
    if preview.SetResourceFillDirection then
        preview:SetResourceFillDirection(slot.gui2ResourceFillDirection)
    end
    if preview.SetResourceFillStyle and slot.CaptureResourceFillStyle then
        preview:SetResourceFillStyle(slot:CaptureResourceFillStyle({}))
    elseif preview.SetResourceFillTexture then
        preview:SetResourceFillTexture(slot.gui2ResourceFillTexture)
    end
    if preview.SetResourceFillColor then
        preview:SetResourceFillColor(slot.gui2ResourceFillColor)
    end
    if preview.SetResourceBorder then
        preview:SetResourceBorder(slot.gui2ResourceBorder)
    end
    if preview.SetResourceBorderColor then
        preview:SetResourceBorderColor(slot.gui2ResourceBorderColor)
    end
    if preview.SetResourceBackgroundColor then
        preview:SetResourceBackgroundColor(slot.gui2ResourceBackgroundColor)
    end
    if preview.SetResourceDisplayConfig then
        local source = slot.gui2ResourceDisplayConfig or {}
        preview:SetResourceDisplayConfig({
            inverseFill = source.inverseFill == true,
            mode = source.mode,
            smoothProgress = false,
            valueKind = source.valueKind,
            segmentCount = source.segmentCount,
            segmentSpacing = source.segmentSpacing,
            dividerThickness = source.dividerThickness,
            dividerColor = source.dividerColor,
            thresholdColorEnabled = source.thresholdColorEnabled,
            thresholdMode = source.thresholdMode,
            thresholdDirection = source.thresholdDirection,
            fillCeilingPercent = source.fillCeilingPercent,
            thresholdMarkerEnabled = source.thresholdMarkerEnabled,
            thresholds = source.thresholds,
            thresholdMarkerColor = source.thresholdMarkerColor,
            thresholdMarkerThickness = source.thresholdMarkerThickness,
            rechargeProgress = false,
            independentCells = source.independentCells,
            durationProgress = false,
            timerMarkers = false,
            partialRecharge = false,
            chargedPointColor = source.chargedPointColor,
        })
    end
    if preview.SetResourceTextAppearance then
        preview:SetResourceTextAppearance(slot.gui2ResourceTextAppearance)
    end
    slot._yhudDesignResourcePreviewAppearanceDirty = nil
    I.FinishPerformanceStat("resourcePreviewAppearanceElapsedMS", startedAt)
    return true
end

local function EnsureDesignResourcePreview(slot)
    if not slot then return nil end
    local preview = slot._yhudDesignResourcePreview
    if not preview then
        if not (App and App.CreateResourceBar) then return nil end
        local width = slot.GetWidth and slot:GetWidth()
            or slot.gui2ResourceWidth or 290
        local height = slot.GetHeight and slot:GetHeight()
            or slot.gui2ResourceHeight or 16
        preview = App:CreateResourceBar(slot, {
            width = width,
            height = height,
            orientation = slot.gui2ResourceOrientation,
            fillDirection = slot.gui2ResourceFillDirection,
            fillTexture = slot.gui2ResourceFillTexture,
            fillColor = slot.gui2ResourceFillColor,
            border = slot.gui2ResourceBorder,
            borderColor = slot.gui2ResourceBorderColor,
            backgroundColor = slot.gui2ResourceBackgroundColor,
            text = slot.gui2ResourceTextAppearance,
            display = slot.gui2ResourceDisplayConfig,
        })
        if not preview then return nil end
        preview:ClearAllPoints()
        preview:SetAllPoints(slot)
        if preview.EnableMouse then preview:EnableMouse(false) end
        if preview.SetFrameLevel and slot.GetFrameLevel then
            preview:SetFrameLevel((slot:GetFrameLevel() or 0) + 1)
        end
        preview:Hide()
        slot._yhudDesignResourcePreview = preview
        View.designResourcePreviewCreateCount =
            (View.designResourcePreviewCreateCount or 0) + 1
        RecordDesignCreate("slot")
        slot._yhudDesignResourcePreviewAppearanceDirty = true
        View:RefreshResourceTextLayers(slot)
    end
    if slot._yhudDesignResourcePreviewAppearanceDirty then
        SyncDesignResourcePreviewAppearance(slot, preview)
    end
    return preview
end

function View:InvalidateDesignResourcePreviewAppearance(slot)
    if not slot then return false end
    slot._yhudDesignResourcePreviewAppearanceDirty = true
    return true
end

function View:ApplyDesignResourcePreviewSlot(slot, preset, progress, absoluteValue)
    if preset and preset.id == "cast" and I.UpdatePlayerCast then
        if slot._yhudDesignResourcePreview then slot._yhudDesignResourcePreview:Hide() end
        I.UpdatePlayerCast(slot, nil, true)
        return true
    end
    local startedAt = ProfileNowMS()
    local preview = slot and slot._yhudDesignResourcePreview
    if not preview or slot._yhudDesignResourcePreviewAppearanceDirty then
        preview = EnsureDesignResourcePreview(slot)
    end
    if not (preview and preview.SetResourceValues) then return false end
    progress = math.max(0, math.min(1, tonumber(progress) or 1))
    local maxValue = tonumber(preset and preset.previewMax) or 100
    local providerKind = preset and preset.provider and preset.provider.kind or "unit-power"
    local runePreview = providerKind == "rune-cooldowns"
    local value = runePreview and maxValue
        or preset and preset.valueKind == "discrete" and providerKind ~= "unit-power-partial"
            and math.floor((progress * maxValue) + 0.00001)
        or (progress * (tonumber(preset and preset.previewValueMax) or maxValue))
    if preset and preset.appearanceExtension and type(absoluteValue) == "number" then
        value = math.max(0, math.min(600, absoluteValue))
    end
    -- Health and ordinary power use whole units, just like their live values.
    if (providerKind == "unit-power" or providerKind == "unit-health")
        and not (preset and preset.appearanceExtension) then
        value = math.floor(value + 0.00001)
    end
    -- Ironfur fill represents duration; its text represents an independent stack count.
    local previewStacks
    local timerProgress = progress
    if providerKind == "ironfur-timers" then
        -- Three staggered applications, each lasting three timeline units.
        local elapsed = progress * 5
        previewStacks = 0
        timerProgress = 0
        for application = 0, 2 do
            if elapsed >= application and elapsed < application + 3 then
                previewStacks = previewStacks + 1
                timerProgress = (application + 3 - elapsed) / 3
            end
        end
        value = timerProgress * maxValue
    end
    local resourceId = preset and preset.id
    if preview._yhudPreviewResourceId == resourceId
        and preview._yhudPreviewValue == value
        and preview._yhudPreviewMaxValue == maxValue
        and preview._yhudPreviewStacks == previewStacks
        and preview._yhudPreviewRune == runePreview then
        AddPerformanceStat("resourcePreviewSameValueSkips", 1)
        I.FinishPerformanceStat("resourcePreviewElapsedMS", startedAt)
        return true
    end
    local applied = preview:SetResourceValues(
        nil,
        nil,
        false,
        value,
        maxValue,
        nil,
        nil,
        false,
        runePreview and RUNE_PREVIEW_READY or nil,
        runePreview and RUNE_PREVIEW_DURATIONS or nil,
        nil,
        nil,
        true,
        nil,
        nil,
        previewStacks
    ) == true
    if preview.SetResourcePreviewTimerMarkers then
        preview:SetResourcePreviewTimerMarkers(previewStacks or 0, timerProgress,
            previewStacks and (1 / 3) or nil)
    end
    preview._yhudPreviewStacks = previewStacks
    preview._yhudPreviewResourceId = resourceId
    preview._yhudPreviewValue = value
    preview._yhudPreviewMaxValue = maxValue
    preview._yhudPreviewRune = runePreview
    AddPerformanceStat("resourcePreviewWrites", 1)
    if preset and preset.valueKind == "discrete" then
        AddPerformanceStat("resourcePreviewDiscreteWrites", 1)
    end
    I.FinishPerformanceStat("resourcePreviewElapsedMS", startedAt)
    if not slot._yhudDesignResourcePreviewBound then
        slot._yhudDesignResourcePreviewBound = true
        -- 原条的绘制内容都属于 track；预览是 slot 的独立子框体。
        -- 仅隐藏原画面，保留承载框的选中、拖动及实时数据更新。
        local track = slot.track
        if track and track.SetAlpha then
            slot._yhudDesignResourceTrackAlpha =
                track.GetAlpha and track:GetAlpha() or 1
            track:SetAlpha(0)
        end
        preview:Show()
    end
    return applied
end

function View:SetDesignResourceValuePreview(resourceId, progress, absoluteValue, groupId)
    if not (self.designMode and resourceId) then return false end
    local definition = ResourceCatalog and ResourceCatalog.GetDefinition
        and ResourceCatalog:GetDefinition(resourceId) or nil
    if not definition then return false end
    progress = math.max(0, math.min(1, tonumber(progress) or 0))
    local applied = false
    local projection = self.designProjection
    local indexedSlots = projection and projection.resourceSlotsById
        and projection.resourceSlotsById[resourceId]
    if indexedSlots then
        for index = 1, #indexedSlots do
            local slot = indexedSlots[index]
            if groupId == nil or slot._yhudGroupId == groupId then
                applied = self:ApplyDesignResourcePreviewSlot(
                slot,
                definition,
                progress,
                absoluteValue
                ) or applied
            end
        end
    elseif not projection then
        local desiredMonitors = self.desiredMonitors
        ForEachDesignSlot(function(slot)
            local monitor = slot and slot._yhudMonitorId
                and desiredMonitors
                and desiredMonitors[slot._yhudMonitorId]
            local preset = monitor and monitor._yhudResource
            if preset and preset.id == resourceId
                and (groupId == nil or slot._yhudGroupId == groupId) then
                applied = self:ApplyDesignResourcePreviewSlot(
                    slot,
                    definition,
                    progress,
                    absoluteValue
                ) or applied
            end
        end)
    end
    return applied
end

function View:ClearDesignResourceValuePreview()
    local cleared = 0
    ForEachDesignSlot(function(slot)
        if self:ClearResourcePreviewSlot(slot) then
            cleared = cleared + 1
        end
    end)
    return cleared > 0, cleared
end

local function RefreshDesignGroupSelection(groupId, runtime, selectedGroupId)
        local selected = groupId == selectedGroupId
        local stateAllowed = runtime.designerStateAllowed ~= false
        local empty = runtime.monitorCount == 0
            and runtime.designContent ~= true
        local frame = runtime.frame
        if frame.SetAlpha then frame:SetAlpha(1) end
        if runtime.designHeader then
            runtime.designHeader:SetFrameStrata("FULLSCREEN_DIALOG")
            runtime.designHeader:SetFrameLevel(300)
            if selected and stateAllowed then
                runtime.designHeader:Show()
            else
                runtime.designHeader:Hide()
            end
            if runtime.designGroupButton
                and runtime.designGroupButton.SetSelected then
                runtime.designGroupButton:SetSelected(selected)
            end
        end
        if runtime.designMover then
            runtime.designMover:SetFrameStrata("FULLSCREEN_DIALOG")
            runtime.designMover:SetFrameLevel(302)
            SetShown(runtime.designMover, empty and stateAllowed)
            if runtime.designMoverLabel then
                SetShown(
                    runtime.designMoverLabel,
                    empty and not selected and stateAllowed
                )
            end
        end
        if runtime.designOutline then
            runtime.designOutline:SetFrameStrata("FULLSCREEN_DIALOG")
            runtime.designOutline:SetFrameLevel(301)
            if selected and stateAllowed then
                runtime.designOutline:Show()
            else
                runtime.designOutline:Hide()
            end
        end
end

function View:SetDesignSelection(selectedGroupId, selectedMonitorId)
    if not self.designMode then return false end
    if self.selectedGroupId == selectedGroupId
        and self.selectedMonitorId == selectedMonitorId then
        return false
    end

    self.selectedGroupId = selectedGroupId
    self.selectedMonitorId = selectedMonitorId
    local projection = self.designProjection
    local designGroups = projection and projection.groups or self.groups
    local designSlots = projection and projection.byMonitor or self.byMonitor
    for groupId, runtime in pairs(designGroups or {}) do
        RefreshDesignGroupSelection(groupId, runtime, selectedGroupId)
    end
    if projection then
        for groupId, runtime in pairs(self.groups) do
            if runtime.runtimeOwned == true and not designGroups[groupId] then
                RefreshDesignGroupSelection(groupId, runtime, selectedGroupId)
            end
        end
    end
    for monitorId, slot in pairs(designSlots or {}) do
        local resourceId = slot._yhudDesignResourceId
        self:SetDesignSlotSelected(
            slot,
            resourceId and slot._yhudGroupId == selectedGroupId
                and resourceId == self.resourceStylePreviewResourceId
                or (slot._yhudLogicalMonitorId or monitorId)
                    == selectedMonitorId
        )
    end
    return true
end

function View:SetDesignCooldownPreviewGroup(groupId, target)
    if type(groupId) ~= "string" or groupId == "" then
        groupId = nil
    end
    if not groupId then
        target = nil
    elseif target ~= "cooldown" and target ~= "name"
        and target ~= "count" and target ~= "all" then
        target = "all"
    end
    if self.designCooldownPreviewGroupId == groupId
        and self.designTextPreviewTarget == target then
        return false
    end
    self.designCooldownPreviewGroupId = groupId
    self.designTextPreviewTarget = target
    if self.designMode then
        ForEachDesignSlot(function(slot)
            self:EnsureDesignTextPreview(slot)
            self:ApplyDesignTextPreview(slot)
        end)
    end
    return true
end

function View:ApplyDesignDurationPreview(slot, now)
    if not (self.designMode and self.designDurationPreviewEnabled and slot) then
        return false
    end
    now = type(now) == "number" and now
        or (_G.GetTime and _G.GetTime() or 0)
    local startTime = now - DESIGN_DURATION_PREVIEW_ELAPSED
    local runtime = DesignRuntimeForSlot(slot)
    local visible = runtime
        and runtime.enabled == true
        and (not runtime.frame.IsShown or runtime.frame:IsShown())
        and (not slot.IsShown or slot:IsShown())
    local durationView = slot._yhudView == "ring"
        or slot._yhudView == "bar"
    if durationView and visible and slot.SetDurationFromTimes then
        slot:SetDurationFromTimes(
            startTime,
            DESIGN_DURATION_SECONDS,
            1,
            slot._yhudView == "bar" and slot.gui2DurationReverse == true
        )
        self:EnsureDesignTextPreview(slot)
        self:ApplyDesignTextPreview(slot)
        return true
    end
    if durationView and slot.ClearDuration then slot:ClearDuration() end
    return false
end

function View:RefreshDesignDurationPreview()
    if not (self.designMode and self.designDurationPreviewEnabled) then
        return false
    end
    local now = _G.GetTime and _G.GetTime() or 0
    local applied = false
    ForEachDesignSlot(function(slot)
        applied = self:ApplyDesignDurationPreview(slot, now) or applied
    end)
    return applied
end

function View:SetDesignDurationPreviewEnabled(enabled)
    enabled = enabled == true
    if self.designDurationPreviewEnabled == enabled then
        return enabled and self:RefreshDesignDurationPreview() or false
    end

    if self.designDurationPreviewTicker then
        self.designDurationPreviewTicker:Cancel()
        self.designDurationPreviewTicker = nil
    end
    self.designDurationPreviewEnabled = enabled
    if not enabled then
        ForEachDesignSlot(function(slot)
            if (slot._yhudView == "ring" or slot._yhudView == "bar")
                and slot.ClearDuration then
                slot:ClearDuration()
            end
            self:ApplyDesignTextPreview(slot)
        end)
    end
    if not enabled then return true end

    self:RefreshDesignDurationPreview()
    local timer = _G.C_Timer
    if timer and timer.NewTicker then
        self.designDurationPreviewTicker = timer.NewTicker(
            DESIGN_DURATION_SECONDS - DESIGN_DURATION_PREVIEW_ELAPSED,
            function()
                if View.designMode
                    and View.designDurationPreviewEnabled then
                    View:RefreshDesignDurationPreview()
                end
            end
        )
    end
    return true
end

-- 兼容旧的设计器内部调用；参数仅表示设计会话预览是否启用。
function View:SetDesignDurationPreviewGroup(groupId)
    return self:SetDesignDurationPreviewEnabled(groupId ~= nil)
end

local function SetDesignSurfaceAlpha(runtime, alpha)
    for _, surface in ipairs({
        runtime and runtime.designHeader,
        runtime and runtime.designMover,
        runtime and runtime.designOutline,
    }) do
        if surface and surface.SetAlpha then surface:SetAlpha(alpha) end
    end
end

local DESIGN_PROJECTION_FRAME_LEVEL = 240

local function ProjectionPools(self)
    local pools = self.designProjectionPools
    if pools then return pools end
    pools = {
        groups = {},
        slots = { icon = {}, bar = {}, ring = {}, resource = {} },
    }
    self.designProjectionPools = pools
    return pools
end

local function NewProjectionState(self, profile, projectionContext)
    local classFile = self.resourcePreviewClassFile
    local specID = self.resourcePreviewSpecID
    local formKey = self.resourcePreviewFormKey
    if (not classFile or not specID)
        and ResourceCatalog and ResourceCatalog.GetCurrentContext then
        classFile, specID, formKey = ResourceCatalog:GetCurrentContext()
    end
    local presentationPlan = I.BeginPresentationPlan(profile, {
        preview = true,
        copyMonitors = true,
        projectionContext = projectionContext,
        resourceClassFile = classFile,
        resourceSpecID = specID,
        resourceFormKey = formKey,
        focusedResourceId = self.resourceStylePreviewResourceId,
        focusedResourceGroupId = self.resourceStylePreviewGroupId,
    })
    return {
        profile = profile,
        context = projectionContext,
        presentationPlan = presentationPlan,
        groups = {},
        byMonitor = {},
        desiredMonitors = presentationPlan
            and presentationPlan.desiredMonitors or {},
        logicalMonitors = presentationPlan
            and presentationPlan.logicalMonitors or {},
        resourceSlotsById = {},
        resourceClassFile = classFile,
        resourceSpecID = specID,
        resourceFormKey = formKey,
    }
end

function View:RefreshDesignProjectionSourceIcon(state)
    local projection = self.designProjection
    local plan = projection and projection.presentationPlan
    local sourceKey = type(state) == "table" and state.sourceKey or nil
    local consumers = sourceKey and plan
        and plan.monitorsBySource[sourceKey] or nil
    if not (self.designMode and consumers) then return false end

    local updated = false
    for index = 1, #consumers do
        local monitorId = consumers[index]
        local member = plan.membersById[monitorId]
        local monitor = member and member.monitor
        if monitor and monitor._yhudInventorySlotPreview == true then
            local icon, inventorySlotPreview =
                I.ResolveInventorySlotPreviewIcon(member.entry, state, false)
            if inventorySlotPreview and icon then
                monitor._yhudDisplayIcon = icon
                local slot = projection.byMonitor
                    and projection.byMonitor[monitorId]
                if slot and slot._yhudIcon ~= icon then
                    slot._yhudIcon = icon
                    SetSlotIcon(slot, icon)
                    AddViewWrite(false)
                    updated = true
                end
            end
        end
    end
    return updated
end

local function IndexProjectionResourceSlot(projection, slot, member)
    local preset = member and member.monitor and member.monitor._yhudResource
    local resourceId = preset and preset.id
    if not (projection and slot and resourceId) then return false end
    local slots = projection.resourceSlotsById[resourceId]
    if not slots then
        slots = {}
        projection.resourceSlotsById[resourceId] = slots
    end
    slots[#slots + 1] = slot
    slot._yhudProjectionResourceId = resourceId
    return true
end

local function UnindexProjectionResourceSlot(projection, slot)
    local resourceId = slot and slot._yhudProjectionResourceId
    local slots = resourceId and projection
        and projection.resourceSlotsById
        and projection.resourceSlotsById[resourceId]
    if not slots then return false end
    for index = #slots, 1, -1 do
        if slots[index] == slot then table.remove(slots, index) end
    end
    if #slots == 0 then projection.resourceSlotsById[resourceId] = nil end
    slot._yhudProjectionResourceId = nil
    return true
end

local function PopProjectionPool(pool)
    local count = #pool
    if count == 0 then return nil end
    local value = pool[count]
    pool[count] = nil
    return value
end

-- Preserve resolved live placement and apply only preview size compensation.
local PROJECTION_ANCHOR_X = {
    TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0,
    TOP = 0.5, CENTER = 0.5, BOTTOM = 0.5,
    TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1,
}
local PROJECTION_ANCHOR_Y = {
    BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0,
    LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5,
    TOPLEFT = 1, TOP = 1, TOPRIGHT = 1,
}

local function HasLiveProjectionAnchor(frame)
    if not ReadAnchor(frame) then return false end
    -- A stored point alone does not guarantee resolved native coordinates.
    if frame.GetPoint and frame.GetCenter then
        local x, y = frame:GetCenter()
        return type(x) == "number" and type(y) == "number"
    end
    return true
end

local function RestoreProjectionPlacement(projection, runtime)
    local placement = projection.profile.layout
        and projection.profile.layout.placements
        and projection.profile.layout.placements[runtime.id]
    local bridge = YHUD.LayoutBridge
    if not (bridge and bridge.RegisterDesignProjectionGroup
        and bridge:RegisterDesignProjectionGroup(
            runtime.id, runtime.group, runtime.frame, placement
        )) then return false end
    runtime._yhudProjectionIndependentAnchor = true
    runtime.designMoveFrame = nil
    return true
end

function View:RefreshDesignProjectionAnchors()
    local projection = self.designProjection
    if not (self.designMode and projection) then return false end
    local byFrame, resolved, visiting = {}, {}, {}
    for groupId, runtime in pairs(projection.groups) do
        local live = self.groups[groupId]
        if live and live.frame then byFrame[live.frame] = runtime end
    end
    local function Resolve(runtime)
        if resolved[runtime] then return resolved[runtime] end
        if visiting[runtime] then return nil end
        visiting[runtime] = true
        local live = self.groups[runtime.id]
        local liveFrame = live and live.frame
        local basePoint = runtime._yhudProjectionAnchorPoint or "CENTER"
        local result = { x = 0, y = 0, point = basePoint }
        local point, relative, relativePoint = ReadAnchor(liveFrame)
        local target = byFrame[relative]
        if target and target ~= runtime and target.enabled == true
            and target._yhudProjectionBuilt == true
            and runtime._yhudProjectionBuilt == true
            and PROJECTION_ANCHOR_X[point]
            and PROJECTION_ANCHOR_X[relativePoint] then
            local parent = Resolve(target)
            if parent then
                local targetLive = self.groups[target.id].frame
                local width, height = FrameSize(target.frame)
                local liveWidth, liveHeight = FrameSize(targetLive)
                local targetScale = targetLive.GetEffectiveScale
                    and targetLive:GetEffectiveScale() or 1
                local sourceScale = liveFrame.GetEffectiveScale
                    and liveFrame:GetEffectiveScale() or 1
                local scale = targetScale / sourceScale
                result.x = (parent.x + (width - liveWidth)
                    * (PROJECTION_ANCHOR_X[relativePoint]
                        - PROJECTION_ANCHOR_X[parent.point])) * scale
                result.y = (parent.y + (height - liveHeight)
                    * (PROJECTION_ANCHOR_Y[relativePoint]
                        - PROJECTION_ANCHOR_Y[parent.point])) * scale
                result.point = point
            end
        end
        visiting[runtime] = nil
        resolved[runtime] = result
        if liveFrame and not runtime.designGroupDragging
            and not runtime._yhudProjectionIndependentAnchor then
            if HasLiveProjectionAnchor(liveFrame) then
                runtime.frame:ClearAllPoints()
                runtime.frame:SetPoint(result.point, liveFrame, result.point,
                    result.x, result.y)
            else
                RestoreProjectionPlacement(projection, runtime)
            end
        end
        return result
    end
    for _, runtime in pairs(projection.groups) do Resolve(runtime) end
    return true
end

local function AcquireProjectionGroup(self, projection, groupPlan)
    local group = groupPlan and groupPlan.group
    if not group then return nil end
    local runtime = projection.groups[group.id]
    if runtime then return runtime end
    runtime = PopProjectionPool(ProjectionPools(self).groups) or {}
    local frame = runtime.frame
    if not frame then
        frame = GUI2:CreateFrame(UIParent, {
            width = DEFAULT_ICON_SIZE,
            height = DEFAULT_ICON_SIZE,
            mouse = false,
            hidden = true,
        })
        runtime.frame = frame
        RecordDesignCreate("chrome")
    end
    runtime.id = group.id
    runtime.group = group
    runtime.enabled = group.enabled == true
    runtime._yhudDesignProjection = true
    runtime.monitorIds = runtime.monitorIds or {}
    runtime.monitorCount = 0
    runtime.designContent = false
    runtime.designerStateAllowed = self:IsDesignerGroupStateAllowed(runtime)
    runtime.visibilityAllowed = true
    runtime.configuredLayoutMode = groupPlan.configuredLayoutMode
    runtime.layoutMode = groupPlan.effectiveLayoutMode
    runtime.layoutModeForced = groupPlan.layoutModeOverrideReason ~= nil
    runtime.layoutModeOverrideReason = groupPlan.layoutModeOverrideReason
    runtime.designMoveFrame = self.groups[group.id]
        and self.groups[group.id].frame or nil
    local layout = groupPlan.layout
    -- Projection group runtimes are pooled across layout types. A missing
    -- field in the new layout is authoritative here: for example rings use a
    -- nil text anchor so their nine-grid position wins over a pooled bar
    -- anchor. Replace the complete layout snapshot when a runtime is reused.
    if layout then ApplyRuntimeLayout(runtime, layout, true) end
    runtime.filteredAuraProjectionStrategy =
        groupPlan.filteredAuraProjectionStrategy
    runtime.filteredAuraProjectionState =
        groupPlan.filteredAuraProjectionState
    runtime.presentationGroupPlan = groupPlan
    frame:SetParent(UIParent)
    local liveRuntime = self.groups[group.id]
    if liveRuntime and HasLiveProjectionAnchor(liveRuntime.frame) then
        frame:ClearAllPoints()
        -- The projection can be much larger than the currently visible live
        -- group. Pinning both frames by CENTER makes vertical bars and wrapped
        -- groups grow in both directions and moves their saved edge. Reuse the
        -- configured placement point so the design projection grows from the
        -- same edge as the live group.
        local placement = projection.profile.layout
            and projection.profile.layout.placements
            and projection.profile.layout.placements[group.id]
        local anchor = type(placement) == "table" and placement.anchor
        local point = type(anchor) == "table" and anchor.point
        if type(point) ~= "string" then point = "CENTER" end
        frame:SetPoint(point, liveRuntime.frame, point, 0, 0)
        runtime._yhudProjectionAnchorPoint = point
    else
        local placement = projection.profile.layout
            and projection.profile.layout.placements
            and projection.profile.layout.placements[group.id]
        local anchor = type(placement) == "table" and placement.anchor
        local point = type(anchor) == "table" and anchor.point
        if type(point) ~= "string" then point = "CENTER" end
        local registered = RestoreProjectionPlacement(projection, runtime)
        if not registered then
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            point = "CENTER"
        end
        runtime._yhudProjectionAnchorPoint = point
    end
    -- Pooled groups must resolve their current policy rather than retain a
    -- previous group's width, including groups that exist only in the draft.
    runtime.effectiveResourceWidth = runtime.view == "resource"
        and I.ResolveResourceWidth(self, runtime) or nil
    frame:SetFrameStrata("FULLSCREEN")
    frame:SetFrameLevel(DESIGN_PROJECTION_FRAME_LEVEL)
    frame:SetAlpha(0)
    frame:Hide()
    projection.groups[group.id] = runtime
    return runtime
end

local function CreateProjectionSlot(runtime, view)
    if view == "bar" and App.CreateDurationBar then
        return App:CreateDurationBar(runtime.frame, {
            width = runtime.itemWidth,
            height = runtime.itemHeight,
            orientation = runtime.orientation,
            reverse = runtime.fillDirection == "reverse",
            iconPosition = runtime.iconPosition,
            iconGap = runtime.iconGap,
            iconSize = runtime.iconSize,
            showIcon = runtime.showIcon,
            icon = QUESTION_ICON,
            iconShape = runtime.shape,
            iconBorder = runtime.border,
            fillColor = runtime.fillColor,
            fillTexture = runtime.statusBarStyle
                and runtime.statusBarStyle.texture,
            countSink = true,
        })
    end
    if view == "ring" and App.CreateDurationRing then
        return App:CreateDurationRing(runtime.frame, {
            diameter = runtime.diameter,
            icon = QUESTION_ICON,
            iconBorder = runtime.border,
            fillColor = runtime.fillColor,
            ringThickness = runtime.ringThickness,
            ringDirection = runtime.ringDirection,
            ringStart = runtime.ringStart,
            trackColor = runtime.ringTrackColor,
            countSink = true,
        })
    end
    if view == "resource" and App.CreateResourceBar then
        return App:CreateResourceBar(runtime.frame, {
            width = runtime.resourceWidth,
            height = runtime.resourceHeight,
            orientation = runtime.orientation,
            fillDirection = runtime.fillDirection,
            border = runtime.border,
            borderColor = runtime.borderColor,
            backgroundColor = runtime.backgroundColor,
            fillTexture = runtime.statusBarStyle
                and runtime.statusBarStyle.texture,
            fillColor = runtime.fillColor,
            smoothProgress = false,
        })
    end
    if App.CreateCooldownIcon then
        return App:CreateCooldownIcon(runtime.frame, {
            size = runtime.iconSize,
            icon = QUESTION_ICON,
            shape = runtime.shape,
            border = runtime.border,
            variant = "bare",
            countSink = true,
        })
    end
end

local function UsesRestrictedGlowPreview(runtime, member)
    if not (runtime and member) then return false end
    if member.special == true then return true end
    if runtime.view ~= "icon" then return false end
    local strategy = runtime.filteredAuraProjectionStrategy
    if strategy == YHUD.FILTERED_AURA_LAYOUT_MIXED_SEGMENTED_OVERFLOW then
        return true
    end
    if strategy ~= YHUD.FILTERED_AURA_LAYOUT_MIXED_DYNAMIC_SINGLE_LINE then
        return false
    end
    local entry = member.entry
    local monitor = member.monitor
    local category = entry
        and (entry.displayCategory or entry.officialCategory)
    local nativeProjection = entry
        and entry.origin == "official-cdm"
        and category == "trackedBuff"
        and monitor and monitor.view == "icon"
    return nativeProjection ~= true
end
I.UsesRestrictedGlowPreview = UsesRestrictedGlowPreview

local function AdvanceProjectionSlot(self, projection, runtime, member)
    local phase = runtime._yhudProjectionSlotPhase or 1
    local slot = runtime._yhudProjectionPendingSlot
    local view = runtime.view or "icon"
    if phase == 1 then
        local pool = ProjectionPools(self).slots[view]
        slot = PopProjectionPool(pool)
        if not slot then
            slot = CreateProjectionSlot(runtime, view)
            if slot then RecordDesignCreate("slot") end
        end
        if not slot then return nil, true, "acquire" end
        slot:SetParent(runtime.frame)
        slot:ClearAllPoints()
        slot._yhudMonitorId = member.id
        slot._yhudLogicalMonitorId = member.logicalId
        slot._yhudGroupId = runtime.id
        slot._yhudView = view
        self:InvalidateDesignBarTextLayout(slot)
        slot._yhudSynthetic = false
        slot._yhudDesignProjection = true
        slot._yhudRestrictedGlowPreview = nil
        projection.byMonitor[member.id] = slot
        runtime.monitorCount = runtime.monitorCount + 1
        runtime.monitorIds[runtime.monitorCount] = member.id
        runtime._yhudProjectionPendingSlot = slot
        runtime._yhudProjectionSlotPhase = 2
        return nil, false, "acquire"
    end
    if phase == 2 then
        self:ConfigureSlot(slot, runtime, member.monitor)
        self:InvalidateDesignResourcePreviewAppearance(slot)
        slot._yhudName = member.displayName
        slot._yhudDisplayName = member.displayName
        runtime._yhudProjectionSlotPhase = 3
        return nil, false, "configure"
    end
    if phase == 3 then
        if view == "resource" then
            local preset = member.monitor._yhudResource
            local preview = member.resourceSpec
                and member.resourceSpec.preview or nil
            local maximum = tonumber(preview and preview.maxValue)
                or tonumber(preset and preset.previewMax) or 100
            local value = tonumber(preview and preview.value) or maximum
            if slot.SetResourceValues then
                slot:SetResourceValues(
                    nil, nil, false, value, maximum,
                    nil, nil, false,
                    preview and preview.independentCells
                        and RUNE_PREVIEW_READY or nil,
                    preview and preview.independentCells
                        and RUNE_PREVIEW_DURATIONS or nil,
                    nil, nil, true
                )
            end
        else
            slot._yhudRestrictedGlowPreview =
                UsesRestrictedGlowPreview(runtime, member)
            self:ConfigureFilteredAuraStaticSlot(
                slot,
                runtime,
                member.monitor,
                member.entry,
                member.availability == "unavailable"
                    or member.previewOnly == true
            )
            if member.monitor._yhudInventorySlotPreview == true then
                slot._yhudIcon = member.monitor._yhudDisplayIcon
            end
        end
        runtime._yhudProjectionSlotPhase = 4
        return nil, false, "content"
    end
    if phase == 4 then
        self:ConfigureDesignSlotInteraction(slot)
        runtime._yhudProjectionSlotPhase = 5
        return nil, false, "interaction"
    end
    if phase == 5 then
        self:EnsureDesignTextPreview(slot)
        runtime._yhudProjectionSlotPhase = 6
        return nil, false, "text-create"
    end
    self:ApplyDesignTextPreview(slot)
    slot:Show()
    if self.designDurationPreviewEnabled
        and (slot._yhudView == "bar" or slot._yhudView == "ring") then
        self:ApplyDesignDurationPreview(slot)
    end
    runtime._yhudProjectionPendingSlot = nil
    runtime._yhudProjectionSlotPhase = nil
    return slot, true, "text-apply"
end

local function ReadMouseState(frame, methodName, fallbackKey)
    local method = frame and frame[methodName]
    if type(method) == "function" then
        local ok, value = pcall(method, frame)
        if ok then return value == true end
    end
    local fallback = frame and frame[fallbackKey]
    if fallback ~= nil then return fallback == true end
    return nil
end

local function CaptureMouseState(frame)
    return {
        enabled = ReadMouseState(frame, "IsMouseEnabled", "mouseEnabled"),
        click = ReadMouseState(
            frame,
            "IsMouseClickEnabled",
            "mouseClickEnabled"
        ),
        motion = ReadMouseState(
            frame,
            "IsMouseMotionEnabled",
            "mouseMotionEnabled"
        ),
    }
end

local function SetMouseState(frame, state)
    if not (frame and state) then return end
    if state.enabled ~= nil and frame.EnableMouse then
        frame:EnableMouse(state.enabled)
    end
    if state.click ~= nil and frame.SetMouseClickEnabled then
        frame:SetMouseClickEnabled(state.click)
    end
    if state.motion ~= nil and frame.SetMouseMotionEnabled then
        frame:SetMouseMotionEnabled(state.motion)
    end
end

local function SuppressMouse(frame)
    if not frame then return end
    if frame.EnableMouse then frame:EnableMouse(false) end
    if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
    if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(false) end
end

local function SuppressLiveProjectionGroup(self, projection, groupId)
    if not (projection and groupId) then return false end
    projection.liveStates = projection.liveStates or {}
    local liveRuntime = self.groups and self.groups[groupId]
    local liveFrame = liveRuntime and liveRuntime.frame
    if not liveFrame then return false end

    local state = projection.liveStates[groupId]
    if not state then
        state = {
            frame = liveFrame,
            alpha = liveFrame.GetAlpha and liveFrame:GetAlpha() or 1,
            mouse = CaptureMouseState(liveFrame),
            slots = {},
        }
        projection.liveStates[groupId] = state
    end
    if liveFrame.SetAlpha then liveFrame:SetAlpha(0) end
    SuppressMouse(liveFrame)

    for _, slot in pairs(self.byMonitor or {}) do
        if slot and slot._yhudGroupId == groupId
            and slot._yhudDesignProjection ~= true then
            if not state.slots[slot] then
                state.slots[slot] = CaptureMouseState(slot)
            end
            I.SetSlotMouseInput(slot, false, false)
        end
    end
    return true
end

local function RestoreLiveProjectionGroup(groupId, state)
    if not state then return end
    local frame = state.frame
    if frame and frame.SetAlpha then frame:SetAlpha(state.alpha or 1) end
    SetMouseState(frame, state.mouse)
    for slot, mouseState in pairs(state.slots or {}) do
        if slot and slot._yhudGroupId == groupId
            and slot._yhudDesignProjection ~= true then
            SetMouseState(slot, mouseState)
        end
    end
end

function View:ReassertDesignProjectionLiveSuppression()
    local projection = self.designProjection
    if not (self.designMode and projection and projection.liveStates) then
        return false
    end
    local suppressed = false
    for groupId in pairs(projection.liveStates) do
        suppressed = SuppressLiveProjectionGroup(
            self,
            projection,
            groupId
        ) or suppressed
    end
    return suppressed
end

local function ApplySharedProjectionGeometry(runtime, slots, specialFlags)
    local segmented = runtime.filteredAuraProjectionStrategy ==
        YHUD.FILTERED_AURA_LAYOUT_MIXED_SEGMENTED_OVERFLOW
    local resourceMetrics
    if runtime.view == "resource" then
        runtime.effectiveResourceWidth = I.ResolveResourceWidth(View, runtime)
        resourceMetrics = {}
        for index = 1, #slots do
            local member = runtime.members and runtime.members[index]
            local spec = member and member.resourceSpec
            resourceMetrics[index] = {
                resourceId = slots[index] and slots[index]._yhudResourceId,
                width = runtime.effectiveResourceWidth
                    or spec and spec.width
                    or runtime.resourceWidth,
                height = spec and spec.height
                    or slots[index] and slots[index].gui2ResourceHeight
                    or runtime.resourceHeight,
            }
        end
    end
    local geometry = I.BuildGroupGeometry(
        runtime,
        slots,
        #slots,
        {
            design = true,
            segmented = segmented,
            specialFlags = specialFlags,
            fixedLayout = runtime.layoutMode == "fixed",
            pixelSize = GUI2.GetPixelSize and function(pixels)
                return GUI2:GetPixelSize(runtime.frame, pixels, pixels)
            end or nil,
            minimumPixelStep = GUI2.GetPixelSize
                and GUI2:GetPixelSize(runtime.frame, 1, 1)
                or (GUI2.mult or 1),
            resourceMetrics = resourceMetrics,
        }
    )
    local adapter = {
        runtime = runtime,
        slots = slots,
    }
    function adapter:SetHolderSize(width, height)
        self.runtime.frame:SetSize(width, height)
        return true
    end
    function adapter:SetItemSize(index, width, height)
        local slot = self.slots[index]
        if not (slot and slot.SetSize) then return false end
        if self.runtime.view == "resource" and slot.SetResourceBarSize then
            slot:SetResourceBarSize(width, height, self.runtime.orientation)
        else
            slot:SetSize(width, height)
        end
        return true
    end
    function adapter:SetRingGeometry(index, placement)
        local slot = self.slots[index]
        if not slot then return false end
        if slot.SetDurationRingSize then
            slot:SetDurationRingSize(
                placement.diameter,
                self.runtime.border,
                self.runtime.ringThickness,
                placement.referenceDiameter,
                placement.material
            )
            slot._yhudRingDiameter = placement.diameter
            slot._yhudRingBorder = self.runtime.border
            slot._yhudRingThickness = self.runtime.ringThickness
            slot._yhudRingReferenceDiameter =
                placement.referenceDiameter
            slot._yhudRingMaterial = placement.material
        elseif slot.SetSize then
            slot:SetSize(placement.diameter, placement.diameter)
        end
        return true
    end
    function adapter:SetItemPoint(index, placement)
        local slot = self.slots[index]
        if not slot then return false end
        slot:ClearAllPoints()
        slot:SetPoint(
            placement.point,
            self.runtime.frame,
            placement.relativePoint,
            placement.x,
            placement.y
        )
        return true
    end
    function adapter:SetItemFrameLevel(index, offset)
        local slot = self.slots[index]
        if not (slot and slot.SetFrameLevel) then return false end
        local base = self.runtime.frame.GetFrameLevel
            and self.runtime.frame:GetFrameLevel() or 0
        slot:SetFrameLevel(base + offset)
        if slot._yhudView == "resource" then
            View:RefreshResourceTextLayers(slot, self.runtime)
        end
        return true
    end
    I.ApplyGroupGeometry(geometry, adapter)
    runtime.presentationGeometry = geometry
end

function View:RefreshDesignProjectionResources(
    profile,
    groupId,
    resourceId,
    relayout
)
    local projection = self.designProjection
    local plan = projection and projection.presentationPlan
    local runtime = projection and projection.groups
        and projection.groups[groupId]
    if not (self.designMode == true
        and type(profile) == "table"
        and type(groupId) == "string"
        and plan and runtime and runtime.view == "resource"
        and I.RefreshPresentationResources) then
        return false
    end

    plan.profile = profile
    projection.profile = profile
    runtime.resourceProfile = profile
    local refreshed, refreshedCount = I.RefreshPresentationResources(
        plan,
        groupId,
        resourceId
    )
    if not refreshed then return false end

    local configured = 0
    for index = 1, #(runtime.projectionSlots or {}) do
        local slot = runtime.projectionSlots[index]
        local member = slot and runtime.presentationGroupPlan
            and runtime.presentationGroupPlan.memberById
            and runtime.presentationGroupPlan.memberById[
                slot._yhudMonitorId
            ]
        local monitor = member and member.monitor
        local preset = monitor and monitor._yhudResource
        if preset and (resourceId == nil or preset.id == resourceId) then
            self:ConfigureSlot(slot, runtime, monitor)
            self:InvalidateDesignResourcePreviewAppearance(slot)
            configured = configured + 1
        end
    end
    if configured == 0 or configured ~= refreshedCount then return false end

    if relayout == true then
        ApplySharedProjectionGeometry(
            runtime,
            runtime.projectionSlots,
            runtime.projectionSpecialFlags
        )
    end
    return true
end

function View:BeginStagedDesignGroupBuild(groupId)
    local projection = self.designProjection
    local presentationPlan = projection and projection.presentationPlan
    if not presentationPlan then return nil end
    local done, groupPlan = I.StepPresentationGroup(
        presentationPlan,
        groupId,
        1
    )
    if not groupPlan then return nil end
    if not done then return groupPlan end
    local runtime = AcquireProjectionGroup(self, projection, groupPlan)
    if runtime._yhudProjectionBuilt == true then return runtime end
    if runtime._yhudProjectionBuilding ~= true then
        runtime._yhudProjectionBuilding = true
        runtime._yhudProjectionBuildIndex = 1
        runtime.projectionSlots = {}
        runtime.projectionSpecialFlags = {}
        runtime.members = groupPlan.members
        runtime.monitorCount = 0
    end
    return runtime
end

function View:BuildStagedDesignGroupSlice(groupId, limit)
    local projection = self.designProjection
    local presentationPlan = projection and projection.presentationPlan
    if not presentationPlan then return false, nil, 0, "missing-plan" end
    local groupPlan = presentationPlan.groupPlans[groupId]
    if not (groupPlan and groupPlan.done) then
        local done, pendingPlan, processed = I.StepPresentationGroup(
            presentationPlan,
            groupId,
            limit
        )
        if not done then
            return false, pendingPlan, processed, "plan"
        end
        groupPlan = pendingPlan
    end
    local runtime = AcquireProjectionGroup(self, projection, groupPlan)
    if not runtime then return false, nil, 0, "missing-group" end
    if runtime._yhudProjectionBuilding ~= true
        and runtime._yhudProjectionBuilt ~= true then
        runtime._yhudProjectionBuilding = true
        runtime._yhudProjectionBuildIndex = 1
        runtime.projectionSlots = {}
        runtime.projectionSpecialFlags = {}
        runtime.members = groupPlan.members
        runtime.monitorCount = 0
    end
    if runtime._yhudProjectionBuilt == true then return true, runtime, 0 end
    limit = math.max(1, math.floor(tonumber(limit) or 1))
    local built = 0
    while built < limit
        and runtime._yhudProjectionBuildIndex <= #runtime.members do
        local member = runtime.members[runtime._yhudProjectionBuildIndex]
        local slot, complete, slotStage = AdvanceProjectionSlot(
            self,
            projection,
            runtime,
            member
        )
        if not complete then return false, runtime, built, slotStage end
        if slot then
            IndexProjectionResourceSlot(projection, slot, member)
            slot._yhudProjectionSpecial = member.special == true
            runtime.projectionSlots[#runtime.projectionSlots + 1] = slot
            runtime.projectionSpecialFlags[
                #runtime.projectionSpecialFlags + 1
            ] = member.special == true
        end
        runtime._yhudProjectionBuildIndex =
            runtime._yhudProjectionBuildIndex + 1
        built = built + 1
    end
    if runtime._yhudProjectionBuildIndex <= #runtime.members then
        return false, runtime, built, "layout-wait"
    end
    if runtime._yhudProjectionLayoutPending ~= true then
        runtime._yhudProjectionLayoutPending = true
        return false, runtime, built
    end
    runtime._yhudProjectionBuilding = nil
    runtime._yhudProjectionBuildIndex = nil
    runtime._yhudProjectionLayoutPending = nil
    runtime._yhudProjectionBuilt = true
    runtime.designContent = #runtime.projectionSlots > 0
    self:ApplyGroupDisplayLayers(projection.profile, projection)
    ApplySharedProjectionGeometry(
        runtime,
        runtime.projectionSlots,
        runtime.projectionSpecialFlags
    )
    for index = 1, #runtime.projectionSlots do
        local slot = runtime.projectionSlots[index]
        if slot._yhudView == "icon" then
            self:RefreshFilteredAuraSlotLayers(slot, runtime)
        elseif slot._yhudView == "bar" then
            self:RefreshDurationBarTextLayers(slot, runtime)
        end
        self:ApplyDesignTextPreview(slot)
        if self.ApplyMonitorGlow then
            local monitor = projection.desiredMonitors
                and projection.desiredMonitors[slot._yhudMonitorId]
            slot._yhudNativeProcGlowLayoutDirty = true
            self:ApplyMonitorGlow(slot, monitor, nil)
        end
    end
    runtime.frame:Show()
    self:RefreshDesignProjectionAnchors()
    return true, runtime, built, "layout"
end

function View:BuildStagedDesignGroup(groupId)
    local runtime = self:BeginStagedDesignGroupBuild(groupId)
    if not runtime then return nil end
    local done = runtime._yhudProjectionBuilt == true
    while not done do
        done, runtime = self:BuildStagedDesignGroupSlice(groupId, 1)
        if not done and not runtime then return nil, "design-group-unavailable" end
    end
    return runtime
end

local function ReleaseProjectionGroup(self, projection, groupId)
    if not (projection and groupId) then return false end
    local pools = ProjectionPools(self)
    for monitorId, slot in pairs(projection.byMonitor or {}) do
        if slot and slot._yhudGroupId == groupId then
            UnindexProjectionResourceSlot(projection, slot)
            self:ClearDesignSlot(slot)
            slot._yhudDesignProjection = nil
            slot._yhudProjectionSpecial = nil
            slot._yhudMonitorId = nil
            slot._yhudLogicalMonitorId = nil
            slot._yhudGroupId = nil
            slot._yhudName = nil
            slot._yhudDisplayName = nil
            slot:ClearAllPoints()
            slot:Hide()
            pools.slots[slot._yhudView or "icon"][
                #pools.slots[slot._yhudView or "icon"] + 1
            ] = slot
            projection.byMonitor[monitorId] = nil
        end
    end
    local runtime = projection.groups and projection.groups[groupId]
    if runtime then
        local bridge = YHUD.LayoutBridge
        if bridge and bridge.UnregisterDesignProjectionGroup then
            bridge:UnregisterDesignProjectionGroup(groupId, runtime.frame)
        end
        if runtime.designHeader then runtime.designHeader:Hide() end
        if runtime.designMover then runtime.designMover:Hide() end
        if runtime.designOutline then runtime.designOutline:Hide() end
        runtime.frame:SetScript("OnMouseDown", nil)
        runtime.frame:EnableMouse(false)
        runtime.frame:Hide()
        runtime._yhudProjectionBuilt = nil
        runtime._yhudProjectionBuilding = nil
        runtime._yhudProjectionBuildIndex = nil
        runtime._yhudProjectionPendingSlot = nil
        runtime._yhudProjectionSlotPhase = nil
        runtime._yhudProjectionLayoutPending = nil
        runtime._yhudDesignProjection = nil
        runtime._yhudProjectionAnchorPoint = nil
        runtime._yhudProjectionIndependentAnchor = nil
        runtime.designMoveFrame = nil
        runtime.presentationGroupPlan = nil
        runtime.presentationGeometry = nil
        runtime.members = nil
        runtime.projectionSlots = nil
        runtime.projectionSpecialFlags = nil
        runtime.monitorCount = 0
        for index = 1, #(runtime.monitorIds or {}) do
            runtime.monitorIds[index] = nil
        end
        pools.groups[#pools.groups + 1] = runtime
        projection.groups[groupId] = nil
    end
    if self.designReadyGroups then self.designReadyGroups[groupId] = nil end
    return true
end

local function ReplaceProjectionGroupPlan(
    projection,
    replacementPlan,
    groupId
)
    local plan = projection and projection.presentationPlan
    local groupPlan = replacementPlan
        and replacementPlan.groupPlans[groupId]
    if not (plan and groupPlan) then return false end
    local previous = plan.groupPlans[groupId]
    for index = 1, #(previous and previous.members or {}) do
        local member = previous.members[index]
        plan.desiredMonitors[member.physicalId] = nil
        plan.membersById[member.physicalId] = nil
        plan.unavailableMonitors[member.physicalId] = nil
        plan.logicalMonitors[member.logicalId] = nil
        plan.logicalSpecial[member.logicalId] = nil
    end
    for sourceKey, consumers in pairs(plan.monitorsBySource) do
        local writeIndex = 1
        for readIndex = 1, #consumers do
            local member = plan.membersById[consumers[readIndex]]
            if member then
                consumers[writeIndex] = consumers[readIndex]
                writeIndex = writeIndex + 1
            end
        end
        for index = #consumers, writeIndex, -1 do consumers[index] = nil end
        if #consumers == 0 then plan.monitorsBySource[sourceKey] = nil end
    end
    plan.groupPlans[groupId] = groupPlan
    for index = 1, #groupPlan.members do
        local member = groupPlan.members[index]
        plan.desiredMonitors[member.physicalId] = member.monitor
        plan.membersById[member.physicalId] = member
        plan.logicalMonitors[member.logicalId] =
            plan.logicalMonitors[member.logicalId] or member.monitor
        plan.logicalSpecial[member.logicalId] =
            plan.logicalSpecial[member.logicalId] == true
            or member.special == true
        if member.availability == "unavailable"
            or member.previewOnly == true then
            plan.unavailableMonitors[member.physicalId] = true
        end
        local sourceConsumers = replacementPlan.monitorsBySource[
            member.sourceKey
        ]
        if sourceConsumers then
            local targets = plan.monitorsBySource[member.sourceKey] or {}
            plan.monitorsBySource[member.sourceKey] = targets
            targets[#targets + 1] = member.physicalId
        end
    end
    projection.profile = replacementPlan.profile
    projection.context = replacementPlan.projectionContext
    projection.desiredMonitors = plan.desiredMonitors
    projection.logicalMonitors = plan.logicalMonitors
    return true
end

function View:RefreshDesignProjectionGroup(
    profile,
    groupId,
    projectionContext
)
    local projection = self.designProjection
    if not (self.designMode and projection and type(profile) == "table"
        and type(groupId) == "string") then
        return false
    end
    projectionContext = projectionContext
        or (YHUD.BuildMonitorLayoutProjectionContext
            and YHUD:BuildMonitorLayoutProjectionContext(profile, true))
    local classFile = self.resourcePreviewClassFile
    local specID = self.resourcePreviewSpecID
    local formKey = self.resourcePreviewFormKey
    if (not classFile or not specID)
        and ResourceCatalog and ResourceCatalog.GetCurrentContext then
        classFile, specID, formKey = ResourceCatalog:GetCurrentContext()
    end
    local replacementPlan = I.BeginPresentationPlan(profile, {
        preview = true,
        copyMonitors = true,
        projectionContext = projectionContext,
        resourceClassFile = classFile,
        resourceSpecID = specID,
        resourceFormKey = formKey,
        focusedResourceId = self.resourceStylePreviewResourceId,
        focusedResourceGroupId = self.resourceStylePreviewGroupId,
    })
    local groupPlan = replacementPlan
        and I.FinishPresentationGroup(replacementPlan, groupId) or nil
    if not groupPlan then return false end

    -- The candidate plan is complete before the visible group is replaced.
    -- Lua completes this synchronous swap before the next rendered frame, so
    -- the player never sees a partially rebuilt group and the live runtime is
    -- never touched.
    ReleaseProjectionGroup(self, projection, groupId)
    if not ReplaceProjectionGroupPlan(
        projection,
        replacementPlan,
        groupId
    ) then
        return false
    end
    local wasStaged = self.designStaged == true
    self.designStaged = true
    local entered = self:EnterStagedDesignGroup(groupId, nil)
    self.designStaged = wasStaged
    if entered then
        self:SetDesignSelection(self.selectedGroupId, self.selectedMonitorId)
    end
    return entered
end

function View:ReleaseDesignProjection(preserveLiveState)
    local projection = self.designProjection
    if not projection then return false end
    self:CancelMonitorDrag()
    if preserveLiveState ~= true then
        for groupId, state in pairs(projection.liveStates or {}) do
            RestoreLiveProjectionGroup(groupId, state)
        end
    end
    local pools = ProjectionPools(self)
    for monitorId, slot in pairs(projection.byMonitor or {}) do
        UnindexProjectionResourceSlot(projection, slot)
        self:ClearDesignSlot(slot)
        slot._yhudDesignProjection = nil
        slot._yhudProjectionSpecial = nil
        slot._yhudMonitorId = nil
        slot._yhudLogicalMonitorId = nil
        slot._yhudGroupId = nil
        slot._yhudName = nil
        slot._yhudDisplayName = nil
        slot:ClearAllPoints()
        slot:Hide()
        pools.slots[slot._yhudView or "icon"][
            #pools.slots[slot._yhudView or "icon"] + 1
        ] = slot
        projection.byMonitor[monitorId] = nil
    end
    for groupId, runtime in pairs(projection.groups or {}) do
        local bridge = YHUD.LayoutBridge
        if bridge and bridge.UnregisterDesignProjectionGroup then
            bridge:UnregisterDesignProjectionGroup(groupId, runtime.frame)
        end
        if runtime.designHeader then runtime.designHeader:Hide() end
        if runtime.designMover then runtime.designMover:Hide() end
        if runtime.designOutline then runtime.designOutline:Hide() end
        runtime.frame:SetScript("OnMouseDown", nil)
        runtime.frame:EnableMouse(false)
        runtime.frame:Hide()
        runtime._yhudProjectionBuilt = nil
        runtime._yhudProjectionBuilding = nil
        runtime._yhudProjectionBuildIndex = nil
        runtime._yhudProjectionPendingSlot = nil
        runtime._yhudProjectionSlotPhase = nil
        runtime._yhudProjectionLayoutPending = nil
        runtime._yhudDesignProjection = nil
        runtime._yhudProjectionAnchorPoint = nil
        runtime._yhudProjectionIndependentAnchor = nil
        runtime.designMoveFrame = nil
        runtime.presentationGroupPlan = nil
        runtime.presentationGeometry = nil
        runtime.members = nil
        runtime.projectionSlots = nil
        runtime.projectionSpecialFlags = nil
        runtime.monitorCount = 0
        for index = 1, #(runtime.monitorIds or {}) do
            runtime.monitorIds[index] = nil
        end
        pools.groups[#pools.groups + 1] = runtime
        projection.groups[groupId] = nil
    end
    self.designProjection = nil
    return true, preserveLiveState == true and projection.liveStates or nil
end

function View:RefreshDesignProjection(profile, projectionContext)
    if not (self.designMode and type(profile) == "table") then return false end
    local selectedGroupId = self.selectedGroupId
    local selectedMonitorId = self.selectedMonitorId
    -- Keep the original live state across rebuilds, including groups removed
    -- from the draft. Only leaving design mode restores those live surfaces.
    local _, liveStates = self:ReleaseDesignProjection(true)
    self.designProjection = NewProjectionState(
        self,
        profile,
        projectionContext
    )
    self.designProjection.liveStates = liveStates
    self:ReassertDesignProjectionLiveSuppression()
    self.designStaged = true
    self.designReadyGroups = {}
    local groups = profile.groups or {}
    local seen = {}
    local order = {}
    if selectedGroupId and groups.items
        and groups.items[selectedGroupId] then
        order[#order + 1] = selectedGroupId
        seen[selectedGroupId] = true
    end
    for index = 1, #(groups.order or {}) do
        local groupId = groups.order[index]
        if not seen[groupId] then
            order[#order + 1] = groupId
            seen[groupId] = true
        end
    end
    for index = 1, #order do
        self:EnterStagedDesignGroup(order[index], nil)
    end
    self.designStaged = false
    self.selectedGroupId = nil
    self.selectedMonitorId = nil
    self:SetDesignSelection(selectedGroupId, selectedMonitorId)
    -- Layout editing disables duration previews. A complete projection rebuild
    -- must resume them, just like the staged entry finalizer does.
    self:SetDesignDurationPreviewEnabled(true)
    return true
end

function View:PrepareStagedDesignMode(
    profile,
    projectionContext,
    selectedGroupId,
    onSelect,
    onAdd,
    selectedMonitorId,
    onSelectMonitor,
    onReorderMonitor,
    onGroupDragStart,
    onGroupDragStop
)
    if type(profile) ~= "table" then return false end
    local _, liveStates = self:ReleaseDesignProjection(true)
    local prepared, wasEnabled = self:PrepareDesignMode(
        true,
        selectedGroupId,
        onSelect,
        onAdd,
        selectedMonitorId,
        onSelectMonitor,
        onReorderMonitor,
        onGroupDragStart,
        onGroupDragStop
    )
    if not prepared then
        for groupId, state in pairs(liveStates or {}) do
            RestoreLiveProjectionGroup(groupId, state)
        end
        return false
    end
    self.designProjection = NewProjectionState(
        self,
        profile,
        projectionContext
    )
    self.designProjection.liveStates = liveStates
    self:ReassertDesignProjectionLiveSuppression()
    self.designStaged = true
    self.designReadyGroups = {}
    self.designStageWasEnabled = wasEnabled == true
    return true, wasEnabled
end

function View:RefreshDesignProjectionVisibility(runtime)
    local allowed = self:IsDesignerGroupStateAllowed(runtime)
    runtime.designerStateAllowed = allowed
    local ready = self.designReadyGroups and self.designReadyGroups[runtime.id] == true
    local visible = self.designMode and ready and runtime.enabled == true
        and runtime.visibilityAllowed ~= false and allowed
    SetShown(runtime.frame, visible == true)
    local selected = runtime.id == self.selectedGroupId
    local empty = runtime.monitorCount == 0 and runtime.designContent ~= true
    if runtime.designHeader then SetShown(runtime.designHeader, visible and selected) end
    if runtime.designOutline then SetShown(runtime.designOutline, visible and selected) end
    if runtime.designMover then SetShown(runtime.designMover, visible and empty) end
    if runtime.designMoverLabel then SetShown(runtime.designMoverLabel, visible and empty and not selected) end
end

function View:EnterStagedDesignGroup(groupId, animationOwner)
    if not (self.designMode and self.designStaged) then return false end
    local runtime = self:BuildStagedDesignGroup(groupId)
    if not runtime then return false end
    if self.designReadyGroups[groupId] == true then return true end

    local frame = runtime.frame
    if not frame then return false end
    local liveFrame = self.groups[groupId] and self.groups[groupId].frame
    local projection = self.designProjection
    if liveFrame then
        SuppressLiveProjectionGroup(self, projection, groupId)
    end
    if runtime.designAlpha == nil then
        runtime.designAlpha = frame.GetAlpha and frame:GetAlpha() or 1
    end
    if frame.SetAlpha then
        frame:SetAlpha(animationOwner and 0 or 1)
    end
    frame:EnableMouse(true)
    if not runtime.designClick then
        local runtimeRef = runtime
        runtime.designClick = function(_, button)
            if button == "LeftButton" and View.designSelect then
                View.designSelect(runtimeRef.id)
            end
        end
    end
    frame:SetScript("OnMouseDown", runtime.designClick)

    local header = self:EnsureDesignChrome(runtime)
    local outline = self:EnsureDesignOutline(runtime)
    self:RefreshDesignChromeGeometry(runtime)
    local selected = groupId == self.selectedGroupId
    local stateAllowed = runtime.designerStateAllowed ~= false
    local empty = runtime.monitorCount == 0
        and runtime.designContent ~= true
    if header then
        RefreshDesignHeaderWidth(runtime)
        header:SetFrameStrata("FULLSCREEN_DIALOG")
        header:SetFrameLevel(300)
        SetShown(header, selected and stateAllowed)
        if runtime.designGroupButton
            and runtime.designGroupButton.SetSelected then
            runtime.designGroupButton:SetSelected(selected)
        end
    end
    if runtime.designMover then
        runtime.designMover:SetFrameStrata("FULLSCREEN_DIALOG")
        runtime.designMover:SetFrameLevel(302)
        runtime.designMoverLabel:SetText(GroupName(runtime.group))
        SetShown(runtime.designMover, empty and stateAllowed)
        SetShown(
            runtime.designMoverLabel,
            empty and not selected and stateAllowed
        )
    end
    if outline then
        outline:SetFrameStrata("FULLSCREEN_DIALOG")
        outline:SetFrameLevel(301)
        SetShown(outline, selected and stateAllowed)
    end
    if runtime.enabled and (runtime._yhudDesignProjection or self.active)
        and runtime.visibilityAllowed ~= false and stateAllowed then
        frame:Show()
    elseif not stateAllowed then
        frame:Hide()
    end
    local projectionSlots = self.designProjection
        and self.designProjection.byMonitor or {}
    for _, slot in pairs(projectionSlots) do
        if slot and slot._yhudGroupId == groupId then
            self:ConfigureDesignSlot(slot)
        end
    end
    self.designReadyGroups[groupId] = true

    local fadeDuration = 0.2
    if animationOwner and Animation and Animation.FadeIn then
        for _, surface in ipairs({ frame }) do
            if surface and surface.IsShown and surface:IsShown() then
                animationOwner.animationActive =
                    (animationOwner.animationActive or 0) + 1
                animationOwner.animationStartedAt =
                    animationOwner.animationStartedAt
                    or (_G.debugprofilestop and _G.debugprofilestop())
                Animation:FadeIn(surface, {
                    owner = animationOwner,
                    from = 0,
                    to = 1,
                    duration = fadeDuration,
                    key = "yhud-design-group-" .. tostring(groupId),
                    finished = function()
                        animationOwner.animationActive = math.max(
                            0,
                            (animationOwner.animationActive or 1) - 1
                        )
                        if animationOwner.animationActive == 0 then
                            animationOwner.animationStoppedAt =
                                _G.debugprofilestop
                                and _G.debugprofilestop() or nil
                        end
                    end,
                })
            end
        end
    else
        SetDesignSurfaceAlpha(runtime, 1)
    end
    return true
end

function View:FinishStagedDesignGroup(groupId)
    local runtime = self.designProjection
        and self.designProjection.groups
        and self.designProjection.groups[groupId]
    if not runtime or not self.designReadyGroups
        or self.designReadyGroups[groupId] ~= true then
        return false
    end
    if Animation and Animation.StopTarget then
        local key = "yhud-design-group-" .. tostring(groupId)
        Animation:StopTarget(runtime.frame, key, true)
    end
    SetDesignSurfaceAlpha(runtime, 1)
    return true
end

function View:FinishStagedDesignMode()
    if not (self.designMode and self.designStaged) then return false end
    self.designStaged = false
    self:SetDesignSelection(self.selectedGroupId, self.selectedMonitorId)
    self:SetDesignDurationPreviewEnabled(true)
    return true
end

function View:AbortStagedDesignMode()
    self.designStaged = false
    self.designReadyGroups = nil
    self.designStageWasEnabled = nil
    self:ReleaseDesignProjection()
    local prepared, wasEnabled = self:PrepareDesignMode(false)
    if not prepared then return false end
    return true
end

function View:PrepareDesignMode(
    enabled,
    selectedGroupId,
    onSelect,
    onAdd,
    selectedMonitorId,
    onSelectMonitor,
    onReorderMonitor,
    onGroupDragStart,
    onGroupDragStop
)
    enabled = enabled == true
    local wasEnabled = self.designMode == true
    if not enabled then
        if self.designProjection then self:ReleaseDesignProjection() end
        self.designCooldownPreviewGroupId = nil
        self.designTextPreviewTarget = nil
        self:SetDesignDurationPreviewEnabled(false)
        self:CancelMonitorDrag()
        local activeGroupDrag = self.activeDesignGroupDrag
        if activeGroupDrag then
            local frame = activeGroupDrag.frame
            if frame and frame.StopMovingOrSizing then
                frame:StopMovingOrSizing()
            end
            activeGroupDrag.designGroupDragging = false
            self.activeDesignGroupDrag = nil
            CommitDesignGroupPosition(activeGroupDrag)
            if self.designGroupDragStop then
                self.designGroupDragStop(activeGroupDrag.id)
            end
        end
        self.resourcePreviewClassFile = nil
        self.resourcePreviewSpecID = nil
        self.resourcePreviewFormKey = nil
        self.resourceStylePreviewResourceId = nil
        self.resourceStylePreviewGroupId = nil
    end
    self.designMode = enabled
    self:SetVisibilityBypass(enabled)
    self.designSelect = enabled and onSelect or nil
    self.designAdd = enabled and onAdd or nil
    self.selectedGroupId = enabled and selectedGroupId or nil
    self.selectedMonitorId = enabled and selectedMonitorId or nil
    self.designSelectMonitor = enabled and onSelectMonitor or nil
    self.designReorderMonitor = enabled and onReorderMonitor or nil
    self.designGroupDragStart = enabled and onGroupDragStart or nil
    self.designGroupDragStop = enabled and onGroupDragStop or nil

    return true, wasEnabled
end

function View:RefreshDesignModePresentation(
    enabled,
    wasEnabled,
    suppressRelayout
)
    enabled = enabled == true
    wasEnabled = wasEnabled == true
    suppressRelayout = suppressRelayout == true
    if not enabled and I.CancelDesignTooltip then
        I.CancelDesignTooltip()
    end
    if self.ApplyGroupDisplayLayers then
        self:ApplyGroupDisplayLayers(self.profile)
    end
    for groupId, runtime in pairs(self.groups) do
        local frame = runtime.frame
        if enabled then
            if not wasEnabled and not suppressRelayout then
                self:RelayoutGroup(groupId)
            end
            local liveState = self.designProjection
                and self.designProjection.liveStates
                and self.designProjection.liveStates[groupId]
            -- Independent projections own this live holder's alpha until
            -- release. Never cache their temporary suppression as its baseline.
            if not (liveState and liveState.frame == frame) then
                if runtime.designAlpha == nil then
                    runtime.designAlpha = frame.GetAlpha and frame:GetAlpha() or 1
                end
                if frame.SetAlpha then frame:SetAlpha(1) end
            end
            frame:EnableMouse(true)
            if not runtime.designClick then
                local runtimeRef = runtime
                runtime.designClick = function(_, button)
                    if button == "LeftButton" and View.designSelect then
                        View.designSelect(runtimeRef.id)
                    end
                end
            end
            frame:SetScript("OnMouseDown", runtime.designClick)
            local header = self:EnsureDesignChrome(runtime)
            local outline = self:EnsureDesignOutline(runtime)
            self:RefreshDesignChromeGeometry(runtime)
            if header then
                local selected = groupId == self.selectedGroupId
                local stateAllowed = runtime.designerStateAllowed ~= false
                local empty = runtime.monitorCount == 0
                    and runtime.designContent ~= true
                RefreshDesignHeaderWidth(runtime)
                header:SetFrameStrata("FULLSCREEN_DIALOG")
                header:SetFrameLevel(300)
                if selected and stateAllowed then
                    header:Show()
                else
                    header:Hide()
                end
                if runtime.designGroupButton
                    and runtime.designGroupButton.SetSelected then
                    runtime.designGroupButton:SetSelected(selected)
                end
                if runtime.designMover then
                    runtime.designMover:SetFrameStrata("FULLSCREEN_DIALOG")
                    runtime.designMover:SetFrameLevel(302)
                    runtime.designMoverLabel:SetText(GroupName(runtime.group))
                    SetShown(
                        runtime.designMover,
                        empty and stateAllowed
                    )
                    SetShown(
                        runtime.designMoverLabel,
                        empty and not selected and stateAllowed
                    )
                end
                if runtime.enabled and self.active
                    and runtime.visibilityAllowed ~= false
                    and stateAllowed then
                    frame:Show()
                elseif not stateAllowed then
                    frame:Hide()
                end
            end
            if outline then
                outline:SetFrameStrata("FULLSCREEN_DIALOG")
                outline:SetFrameLevel(301)
                if groupId == self.selectedGroupId
                    and runtime.designerStateAllowed ~= false then
                    outline:Show()
                else
                    outline:Hide()
                end
            end
        else
            frame:SetScript("OnMouseDown", nil)
            frame:EnableMouse(false)
            if runtime.designDragPreview then
                runtime.designDragPreview:Hide()
            end
            if runtime.designHeader then runtime.designHeader:Hide() end
            if runtime.designMover then runtime.designMover:Hide() end
            if runtime.designOutline then runtime.designOutline:Hide() end
            if runtime.designAlpha ~= nil then
                if frame.SetAlpha then frame:SetAlpha(runtime.designAlpha or 1) end
                runtime.designAlpha = nil
            end
            if not suppressRelayout then self:RelayoutGroup(groupId) end
        end
    end
    for _, slot in pairs(self.byMonitor) do
        self:ConfigureDesignSlot(slot)
    end
    if enabled and self.ReassertDesignProjectionLiveSuppression then
        self:ReassertDesignProjectionLiveSuppression()
    end
    if enabled then self:SetDesignDurationPreviewEnabled(true) end
    return true
end

function View:SetDesignMode(
    enabled,
    selectedGroupId,
    onSelect,
    onAdd,
    selectedMonitorId,
    onSelectMonitor,
    onReorderMonitor,
    onGroupDragStart,
    onGroupDragStop
)
    enabled = enabled == true
    if enabled then
        local Layout = YUI.Layout
        if Layout
            and Layout.IsEditing
            and Layout:IsEditing() == true
            and Layout.CloseEditMode then
            Layout:CloseEditMode("yhud-design")
        end
    end
    local prepared, wasEnabled = self:PrepareDesignMode(
        enabled,
        selectedGroupId,
        onSelect,
        onAdd,
        selectedMonitorId,
        onSelectMonitor,
        onReorderMonitor,
        onGroupDragStart,
        onGroupDragStop
    )
    if not prepared then return false end
    return self:RefreshDesignModePresentation(enabled, wasEnabled, false)
end
