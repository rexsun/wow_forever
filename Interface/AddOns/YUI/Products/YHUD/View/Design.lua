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
local DRAG_PREVIEW_ICON_SIZE = 24
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
local DESIGN_DURATION_PREVIEW_INTERVAL = 0.1
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
    local glowPreview = self.designGlowPreviewMonitorId ~= nil
        and (slot._yhudLogicalMonitorId or slot._yhudMonitorId) == self.designGlowPreviewMonitorId
    outline:SetAlpha(glowPreview and 0 or 1)
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
    local progress = slot and slot._yhudBarProgress
    local maximum = slot and slot._yhudBarMaximum
    if progress and progress.source ~= "time" then
        if not maximum then return false, "" end
        local sample = slot._yhudDesignBarPreview
        if sample and sample.progress == progress and sample.maximum == maximum then
            return true, sample.value
        end
        return true, progress.source == "spell-charges" and math.max(0, maximum - 1) or math.min(2, maximum)
    end
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

local function ClearDesignProgressSample(slot)
    slot._yhudDesignBarPreview = nil
    slot._yhudDesignDurationPreviewCycle = nil
    slot._yhudDesignDurationPreviewProgress = nil
end

-- Public samples only. Compile the bounded stack sequence on configuration
-- changes; the existing shared duration ticker advances every preview source.
local function DesignBarPlaybackSample(slot, elapsed)
    local progress, maximum = slot._yhudBarProgress, slot._yhudBarMaximum
    local policy = slot._yhudBarStackPolicy
    local low = policy and policy.enabled and policy.low.enabled and policy.low.value or nil
    local high = policy and policy.enabled and policy.high.enabled and policy.high.value or nil
    local sample = slot._yhudDesignBarPreview
    if not sample or sample.progress ~= progress or sample.maximum ~= maximum
        or sample.low ~= low or sample.high ~= high then
        sample = { progress = progress, maximum = maximum, low = low, high = high, value = 0 }
        slot._yhudDesignBarPreview = sample
        if progress.source == "aura-stacks" then
            local values, included = {}, {}
            local function add(value)
                value = math.max(0, math.min(maximum, math.floor(value)))
                if not included[value] then
                    included[value] = true
                    values[#values + 1] = value
                end
            end
            for index = 0, math.min(maximum, 10) do
                add(maximum <= 10 and index or maximum * index / 10)
            end
            if low then add(low - 1); add(low); add(low + 1) end
            if high then add(high - 1); add(high); add(high + 1) end
            table.sort(values)
            sample.values = values
        end
    end
    local period = DESIGN_DURATION_SECONDS - DESIGN_DURATION_PREVIEW_ELAPSED
    local phase = elapsed % period
    if progress.source == "spell-charges" then
        if phase < 6 then
            local value = phase * maximum / 6
            sample.value = math.min(maximum, math.floor(value))
            sample.fraction = value - sample.value
        elseif phase < 8 then
            sample.value, sample.fraction = maximum, 0
        else
            sample.value = math.max(0, maximum - math.floor((phase - 8) * maximum / 2) - 1)
            sample.fraction = 0
        end
    else
        local position = phase < 5 and phase / 5
            or phase < 7 and 1 or (period - phase) / 5
        sample.value = sample.values[1 + math.floor(position * (#sample.values - 1))]
    end
    return sample
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
    "numericFont", "numericSize", "numericOutline", "numericMonochrome",
}
local function CommitDesignBarSample(slot, text, value, state, anchorState)
    local previous = state.sampleLayout
    local changed = not previous
        or previous.font ~= state.font or previous.size ~= state.fontSize
        or previous.outline ~= state.fontOutline
        or previous.monochrome ~= state.fontMonochrome
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
    previous.monochrome = state.fontMonochrome
    previous.width, previous.height = slot.gui2DurationWidth, slot.gui2DurationHeight
    previous.orientation, previous.showIcon = slot.orientation, slot.gui2DurationShowIcon
    state.sampleLayout = previous
    if changed then text:SetText("") end
    if changed or state.sampleValue ~= value then text:SetText(value) end
    state.sampleValue = value
end

function View:ApplyDesignTextPreview(slot)
    if not (self.designMode and slot)
        or slot._yhudView == "resource"
        or (self.designProjection and slot._yhudDesignProjection ~= true) then
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

    local presetPreview = YHUD.ClassExtra and YHUD.ClassExtra.previews[slot]
    local timeSample = presetPreview and presetPreview.timeText or DESIGN_COOLDOWN_SAMPLE
    local textPreviewActive = presetPreview ~= nil
        or (runtime.id == self.designCooldownPreviewGroupId and self.designTextPreviewTarget ~= nil)
    local previewTarget = self.designTextPreviewTarget
    local previewAll = presetPreview ~= nil or previewTarget == "all"
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
        monochrome = runtime.cooldownTextMonochrome,
        position = runtime.cooldownTextPosition,
        offsetX = runtime.cooldownTextOffsetX,
        offsetY = runtime.cooldownTextOffsetY,
        color = runtime.cooldownTextColor,
    } or {
        enabled = runtime.timeText ~= false,
        font = runtime.timeTextFont,
        size = runtime.timeTextSize,
        outline = runtime.timeTextOutline,
        monochrome = runtime.timeTextMonochrome,
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
        if slot._yhudView ~= "bar" then cooldownText:SetText(timeSample) end
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
            CommitDesignBarSample(slot, cooldownText, timeSample,
                slot._yhudDesignCooldownTextState, slot._yhudDesignCooldownTextAnchorState)
        end
        SetDesignTextShown(
            cooldownText,
            slot._yhudDesignCooldownTextState,
            cooldownShown
        )
    end

    local countText = slot._yhudDesignCountText
    local hasCount, countValue = ResolveDesignCountPreview(slot)
    if presetPreview then countValue = presetPreview.state.displayCount or 0 end
    if View.ApplyBarStackPreview and (textPreviewActive or durationPreviewActive) then
        View:ApplyBarStackPreview(slot, countValue)
    end
    local countShown = (textPreviewActive or durationPreviewActive)
        and (durationPreviewActive or previewAll or previewTarget == "count")
        and runtime.countText == true
        and (not slot._yhudBarProgress or slot._yhudBarProgress.source == "time" or hasCount)
        and (not presetPreview or presetPreview.state.displayCount ~= nil)
    if countText then
        if slot._yhudView ~= "bar" then countText:SetText(tostring(countValue)) end
        local countStyle = {
            enabled = runtime.countText ~= false,
            font = runtime.countTextFont,
            size = runtime.countTextSize,
            outline = runtime.countTextOutline,
            monochrome = runtime.countTextMonochrome,
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
            monochrome = runtime.nameTextMonochrome,
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

local function FinishDesignGroupDrag(runtime, cancel)
    if not (runtime and runtime.designGroupDragging) then return false end
    runtime.designGroupDragging = false
    View.activeDesignGroupDrag = nil
    if runtime.designGroupLayoutDrag then
        runtime.designGroupLayoutDrag = nil
        local bridge = YHUD.LayoutBridge
        if bridge and bridge.EndGroupDrag then
            bridge:EndGroupDrag(runtime.id, runtime.frame, cancel)
        end
    else
        local frame = runtime.designMoveFrame or runtime.frame
        if frame and frame.StopMovingOrSizing then frame:StopMovingOrSizing() end
        if not cancel then CommitDesignGroupPosition(runtime) end
    end
    if View.designGroupDragStop then View.designGroupDragStop(runtime.id) end
    return true
end

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
            local bridge = YHUD.LayoutBridge
            local layoutDrag = runtime._yhudDesignProjection and bridge and bridge.BeginGroupDrag
            if layoutDrag and not bridge:BeginGroupDrag(runtime.id, runtime.frame) then return end
            runtime.designGroupLayoutDrag = layoutDrag and true or nil
            runtime.designGroupDragging = true
            View.activeDesignGroupDrag = runtime
            if View.designGroupDragStart then
                View.designGroupDragStart(runtime.id)
            end
            if not layoutDrag then
                if frame.SetMovable then frame:SetMovable(true) end
                frame:StartMoving()
            end
        end)
        groupButton:SetScript("OnDragStop", function()
            FinishDesignGroupDrag(runtime)
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
    local room = runtime._yhudDragMakeRoom
    local shiftX = room and room.currentShiftX or 0
    local shiftY = room and room.currentShiftY or 0
    local radialGrowth = room and room.radial and room.currentDistance or 0
    width = width + math.abs(shiftX) + radialGrowth * 2
    height = height + math.abs(shiftY) + radialGrowth * 2

    if runtime.designHeader then
        runtime.designHeader:ClearAllPoints()
        runtime.designHeader:SetPoint(
            "BOTTOMLEFT",
            frame,
            "TOPLEFT",
            offsetX + math.min(0, shiftX) - radialGrowth,
            offsetY + math.max(0, shiftY) + radialGrowth + DESIGN_HEADER_GAP
        )
    end
    if runtime.designMover then
        runtime.designMover:ClearAllPoints()
        runtime.designMover:SetPoint("CENTER", frame, "CENTER", offsetX + shiftX * 0.5, offsetY + shiftY * 0.5)
        runtime.designMover:SetSize(width, height)
    end
    if runtime.designOutline then
        local pixel = GUI2:GetPixelSize(frame, 1, 1)
        runtime.designOutline:ClearAllPoints()
        runtime.designOutline:SetPoint("CENTER", frame, "CENTER", offsetX + shiftX * 0.5, offsetY + shiftY * 0.5)
        runtime.designOutline:SetSize(
            width + (pixel * 2),
            height + (pixel * 2)
        )
    end
    return true
end

function View:EnsureDesignOutline(runtime)
    if runtime.designOutline then
        runtime.designOutline:SetAlpha(runtime.id == self.designGlowPreviewGroupId and 0 or 1)
        return runtime.designOutline
    end
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
    outline:SetAlpha(runtime.id == self.designGlowPreviewGroupId and 0 or 1)
    return outline
end

function View:SetDesignGlowPreview(monitorId, groupId, appearance)
    if not self.designMode then monitorId, groupId, appearance = nil, nil, nil end
    local previous = self.designGlowPreviewMonitorId
    local identityChanged = previous ~= monitorId or self.designGlowPreviewGroupId ~= groupId
    self.designGlowPreviewMonitorId, self.designGlowPreviewGroupId = monitorId, groupId
    self.designGlowPreviewAppearance = appearance
    local projection = self.designProjection
    local slots = projection and projection.byMonitor or self.byMonitor
    local groups = projection and projection.groups or self.groups
    if identityChanged then
        for id, runtime in pairs(groups or {}) do
            if runtime.designOutline then runtime.designOutline:SetAlpha(id == groupId and 0 or 1) end
        end
    end
    for _, slot in pairs(slots or {}) do
        if slot._yhudDesignProjection == true then
            local id = slot._yhudLogicalMonitorId or slot._yhudMonitorId
            if identityChanged and slot._yhudDesignSelectionOutline then
                slot._yhudDesignSelectionOutline:SetAlpha(id == monitorId and 0 or 1)
            end
            if id == monitorId or id == previous then
                local monitor = projection and projection.desiredMonitors[slot._yhudMonitorId]
                self:ApplyMonitorGlow(slot, monitor, nil)
            end
        end
    end
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
                ringRadius = candidate.gui2DurationRingOuterRadius or candidate.ringOuterRadius or width * 0.5,
                ringThickness = candidate.gui2DurationRingResolvedThickness
                    or candidate.resolvedRingThickness or runtime.ringThickness or 8,
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
    if runtime.view == "resource" then
        local rows = {}
        for _, candidate in ipairs(snapshot) do
            local key = candidate.slot._yhudResourceRowKey or candidate.monitorId
            local row = rows[key]
            if not row then
                row = { slots = {} }
                rows[key] = row
            end
            candidate.visualRow = row
            for _, physical in ipairs(candidate.physical) do
                row.slots[#row.slots + 1] = physical.slot
                physical.visualRow = row
                row.minX = math.min(row.minX or math.huge, physical.x - physical.width * 0.5)
                row.maxX = math.max(row.maxX or -math.huge, physical.x + physical.width * 0.5)
                row.minY = math.min(row.minY or math.huge, physical.y - physical.height * 0.5)
                row.maxY = math.max(row.maxY or -math.huge, physical.y + physical.height * 0.5)
            end
        end
        -- Feedback uses complete visual rows; logical candidates and insertion
        -- indices still refer to the individual resource being reordered.
        for _, row in pairs(rows) do
            row.x, row.y = (row.minX + row.maxX) * 0.5, (row.minY + row.maxY) * 0.5
            row.width, row.height = row.maxX - row.minX, row.maxY - row.minY
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
    -- 圆环的隐藏图标保留创建时的占位图，来源图标以槽位缓存为准。
    local ringIcon = sourceSlot and sourceSlot._yhudView == "ring" and sourceSlot._yhudIcon
    local atlas = not ringIcon and source and source.GetAtlas and source:GetAtlas()
    local texture = ringIcon or source and source.GetTexture and source:GetTexture()
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

local function CreateDragLabel(parent)
    local label = GUI2:CreatePanel(parent, {
        surface = "color.surface.raised", border = false,
        radiusKey = "layout.radius.panel", mouse = false,
    })
    label:EnableMouse(false)
    label.text = GUI2:CreateText(label, "", "font.size.md", "color.text.primary", "LEFT")
    local font, size = label.text:GetFont()
    label.text:SetFont(font, size, "OUTLINE")
    label.text:SetShadowColor(0, 0, 0, 0.8)
    label.text:SetShadowOffset(1, -1)
    label.text:SetPoint("TOPLEFT", label, "TOPLEFT", 8, -5)
    label.text:SetWordWrap(true)
    function label:SetText(text)
        self.text:SetText(text)
        local textWidth = self.text.GetUnboundedStringWidth
            and self.text:GetUnboundedStringWidth() or self.text:GetStringWidth()
        local width = math.max(1, math.min(420, textWidth))
        self.text:SetWidth(width)
        self:SetSize(math.ceil(width) + 16, math.ceil(self.text:GetStringHeight()) + 10)
    end
    label:Hide()
    RecordDesignCreate("chrome")
    RecordDesignCreate("text")
    return label
end

local function DragRectOverlaps(left, right, bottom, top, bounds)
    return left < bounds.maxX + 4 and right > bounds.minX - 4
        and bottom < bounds.maxY + 4 and top > bounds.minY - 4
end

local function EnsureMonitorDragPreview(runtime)
    if runtime.designDragPreview then return runtime.designDragPreview end
    local preview = GUI2:CreateFrame(UIParent, {
        mouse = false,
        hidden = true,
    })
    preview.icons = {}
    preview.hint = CreateDragLabel(preview)
    preview.status = preview.hint.text
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
    local hint = preview.hint
    local screenWidth = UIParent:GetWidth()
    local screenHeight = UIParent:GetHeight()
    local previewWidth, previewHeight = FrameSize(preview)
    local hintWidth, hintHeight = FrameSize(hint)
    local x, top
    for position = 1, 4 do
        x = position % 2 == 1 and cursorX + previewWidth * 0.5 + 12
            or cursorX - previewWidth * 0.5 - 12 - hintWidth
        top = position <= 2 and cursorY + previewHeight * 0.5
            or cursorY - previewHeight * 0.5 - 12
        x = math.max(8, math.min(screenWidth - hintWidth - 8, x))
        top = math.max(hintHeight + 8, math.min(screenHeight - 8, top))
        local clear = true
        for _, candidate in ipairs(frame._yhudDragTargets or {}) do
            local bounds = candidate.labelBounds
            if bounds and DragRectOverlaps(x, x + hintWidth, top - hintHeight, top, bounds) then
                clear = false
                break
            end
        end
        if clear then break end
    end
    hint:ClearAllPoints()
    hint:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, top)
end

local function ShowMonitorDragPreview(runtime, frame)
    local preview = EnsureMonitorDragPreview(runtime)
    preview.status:SetText("")
    preview.hint:Hide()
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
        local width, height = DRAG_PREVIEW_ICON_SIZE, DRAG_PREVIEW_ICON_SIZE
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
            local shape = iconSlot and iconSlot.gui2Shape or sourceSlot.gui2Shape
            -- 浮层统一正方比例，保留来源的圆角或圆形轮廓。
            if shape == "wideSquare" or shape == "flatSquare" then
                shape = "square"
            elseif shape == "wideRounded" or shape == "flatRounded" then
                shape = "roundedSquare"
            end
            GUI2:ApplyIconAppearance(holder, {
                shape = shape,
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
    if preview then
        preview.hint:Hide()
        preview:Hide()
    end
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
    spacing,
    runtime
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
    local beforeRow = beforePhysical and beforePhysical.visualRow
    local afterRow = afterPhysical and afterPhysical.visualRow
    local sameResourceRow = beforeRow ~= nil and beforeRow == afterRow
    local beforeVisual = not sameResourceRow and beforeRow or beforePhysical
    local afterVisual = not sameResourceRow and afterRow or afterPhysical

    local horizontal = vectorY == 0
    local function Along(candidate)
        return candidate.x * vectorX + candidate.y * vectorY
    end
    local function Cross(candidate)
        return horizontal and candidate.y or candidate.x
    end
    local stagger = runtime and runtime.view == "icon" and tonumber(runtime.itemOffset) or 0
    local function AlongExtent(candidate)
        return (horizontal and candidate.width or candidate.height) * 0.5
    end
    local function CrossSize(candidate)
        return horizontal and candidate.height or candidate.width
    end
    local reference = beforePhysical or afterPhysical
    local primaryStep = math.max(1, (horizontal and reference.width or reference.height) + (tonumber(spacing) or 0))
    local function LineCross(candidate)
        -- Remove the configured staircase slope only when identifying rows.
        -- The visible caret still uses the actual, offset frame coordinates.
        return Cross(candidate) - Along(candidate) * stagger / primaryStep
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
        local crossDelta = math.abs(LineCross(beforeVisual) - LineCross(afterVisual))
        local tolerance = math.max(
            CrossSize(beforeVisual),
            CrossSize(afterVisual)
        ) * 0.55
        sameVisualLine = crossDelta <= tolerance
        if sameVisualLine then
            local beforeEdge = Along(beforeVisual)
                + AlongExtent(beforeVisual)
            local afterEdge = Along(afterVisual)
                - AlongExtent(afterVisual)
            seamX, seamY = ToPoint(
                (beforeEdge + afterEdge) * 0.5,
                (Cross(beforeVisual) + Cross(afterVisual)) * 0.5
            )
            anchorVariant = "middle"
        else
            local beforeX, beforeY = ToPoint(
                Along(beforeVisual) + AlongExtent(beforeVisual)
                    + halfSpacing,
                Cross(beforeVisual)
            )
            local afterX, afterY = ToPoint(
                Along(afterVisual) - AlongExtent(afterVisual)
                    - halfSpacing,
                Cross(afterVisual)
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
            Along(beforeVisual) + AlongExtent(beforeVisual) + halfSpacing,
            Cross(beforeVisual)
        )
        anchorVariant = "tail"
    else
        seamX, seamY = ToPoint(
            Along(afterVisual) - AlongExtent(afterVisual) - halfSpacing,
            Cross(afterVisual)
        )
        anchorVariant = "head"
    end

    local wrapSpan
    if beforePhysical and afterPhysical and not sameVisualLine and not (beforeRow or afterRow) then
        snapshot._yhudDragLineBounds = snapshot._yhudDragLineBounds or {}
        local function VisualLine(reference)
            local cached = snapshot._yhudDragLineBounds[reference.slot]
            if cached then return cached end
            local line = { minX = math.huge, maxX = -math.huge, minY = math.huge, maxY = -math.huge }
            for _, candidate in ipairs(snapshot) do
                for _, item in ipairs(CandidatePhysicals(candidate)) do
                    local physical = PhysicalCandidate(candidate, item)
                    if math.abs(LineCross(physical) - LineCross(reference))
                        <= math.max(CrossSize(physical), CrossSize(reference)) * 0.55 then
                        line.minX = math.min(line.minX, physical.x - physical.width * 0.5)
                        line.maxX = math.max(line.maxX, physical.x + physical.width * 0.5)
                        line.minY = math.min(line.minY, physical.y - physical.height * 0.5)
                        line.maxY = math.max(line.maxY, physical.y + physical.height * 0.5)
                    end
                end
            end
            snapshot._yhudDragLineBounds[reference.slot] = line
            return line
        end
        local beforeLine, afterLine = VisualLine(beforePhysical), VisualLine(afterPhysical)
        if horizontal then
            local sign = LineCross(afterPhysical) > LineCross(beforePhysical) and 1 or -1
            local beforeEdge = sign > 0 and beforeLine.maxY or beforeLine.minY
            local afterEdge = sign > 0 and afterLine.minY or afterLine.maxY
            seamY = (beforeEdge + afterEdge) * 0.5
            drop.wrapGap = (afterEdge - beforeEdge) * sign
            local minX, maxX = math.min(beforeLine.minX, afterLine.minX), math.max(beforeLine.maxX, afterLine.maxX)
            seamX, wrapSpan = (minX + maxX) * 0.5, maxX - minX
            drop.vectorX, drop.vectorY = 0, sign
        else
            local sign = LineCross(afterPhysical) > LineCross(beforePhysical) and 1 or -1
            local beforeEdge = sign > 0 and beforeLine.maxX or beforeLine.minX
            local afterEdge = sign > 0 and afterLine.minX or afterLine.maxX
            seamX = (beforeEdge + afterEdge) * 0.5
            drop.wrapGap = (afterEdge - beforeEdge) * sign
            local minY, maxY = math.min(beforeLine.minY, afterLine.minY), math.max(beforeLine.maxY, afterLine.maxY)
            seamY, wrapSpan = (minY + maxY) * 0.5, maxY - minY
            drop.vectorX, drop.vectorY = sign, 0
        end
        drop.wrapBoundary = true
        anchorVariant = "wrap-line"
    end

    drop.targetIndex = targetIndex
    drop.beforeCandidate = beforeCandidate
    drop.afterCandidate = afterCandidate
    drop.orderedCandidates = ordered
    drop.beforePhysical = beforePhysical
    drop.afterPhysical = afterPhysical
    drop.sameResourceRow = sameResourceRow
    drop.sameVisualLine = sameVisualLine
    drop.seamX = seamX
    drop.seamY = seamY
    drop.seamSpan = (wrapSpan or math.max(
        beforeVisual and CrossSize(beforeVisual) or 0,
        afterVisual and CrossSize(afterVisual) or 0
    )) + ((beforeRow or afterRow) and 0 or GUI2:GetPixelSize(drop.target.slot, 6, 1))
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

local function IsSegmentedDropTarget(runtime)
    if runtime._yhudDropSegmented ~= nil then
        return runtime._yhudDropSegmented == true
    end
    return runtime.filteredAuraProjectionStrategy ==
        YHUD.FILTERED_AURA_LAYOUT_MIXED_SEGMENTED_OVERFLOW
end

local function ApplySpecialOverflowDropRule(
    self,
    runtime,
    sourceMonitorId,
    drop
)
    if not (drop and IsSegmentedDropTarget(runtime)) then
        return drop
    end
    local sourceSpecial = runtime._yhudDropSourceSpecial
    if sourceSpecial == nil then sourceSpecial = IsSpecialDragMonitor(self, sourceMonitorId) end
    local before = drop.beforeCandidate
    local after = drop.afterCandidate
    local beforeSpecial = before
        and IsSpecialDragMonitor(self, before.monitorId) or false
    local afterSpecial = after
        and IsSpecialDragMonitor(self, after.monitorId) or false
    local valid
    if sourceSpecial then
        valid = afterSpecial or after == nil
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
    if runtime.view == "icon" and runtime.fillMode == "columns" then
        if perLine <= 1 then return runtime.rowDirection == "left" and "left" or "right" end
        return runtime.wrapDirection == "up" and "up" or "down"
    end
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

function View:ResolveMonitorDrop(runtime, slot, cursorX, cursorY, targetSnapshot)
    local snapshot = targetSnapshot or slot and slot._yhudDragSnapshot
    if not (runtime and type(snapshot) == "table" and cursorX and cursorY) then
        return nil
    end

    local crossGroup = targetSnapshot ~= nil
    local sourceIndex = crossGroup and 0 or nil
    local nearest
    local nearestDistance
    local minX
    local maxX
    local minY
    local maxY
    local sourceLogicalId = LogicalMonitorId(slot)
    if crossGroup and #snapshot == 0 then
        local x, y = runtime.frame:GetCenter()
        local width, height = FrameSize(runtime.frame)
        width, height = math.max(100, width), math.max(36, height)
        return {
            operation = "insert", empty = true,
            targetLane = YHUD.CONTENT_LANE_SPEC, targetIndex = 1,
            vectorX = 1, vectorY = 0, key = "empty:" .. runtime.id,
            target = { slot = runtime.frame, width = width, height = height },
            seamX = x - width * 0.5, seamY = y, seamSpan = math.max(24, height),
            placement = { kind = "tail" },
        }
    end
    if runtime.view == "ring" and (runtime.direction == "outward" or runtime.direction == "inward") then
        local x, y = runtime.frame:GetCenter()
        local width, height = FrameSize(runtime.frame)
        if not x or not y or math.abs(cursorX - x) > width * 0.5 + DRAG_GROUP_PADDING
            or math.abs(cursorY - y) > height * 0.5 + DRAG_GROUP_PADDING then return nil end
        local ordered = snapshot._yhudOrderWithoutSource
        if #ordered == 0 then return nil end
        local nearestRing, radialDistance
        for _, candidate in ipairs(ordered) do
            local distance = math.sqrt((cursorX - candidate.x)^2 + (cursorY - candidate.y)^2)
            local edgeDistance = math.abs(distance - candidate.width * 0.5)
            if not radialDistance or edgeDistance < radialDistance then
                nearestRing, radialDistance = candidate, edgeDistance
            end
        end
        local distance = math.sqrt((cursorX - nearestRing.x)^2 + (cursorY - nearestRing.y)^2)
        local inside = distance < nearestRing.width * 0.5
        local before = runtime.direction == "outward" and inside
            or runtime.direction == "inward" and not inside
        local index = 1
        for orderIndex, candidate in ipairs(ordered) do
            if candidate == nearestRing then index = orderIndex; break end
        end
        local targetIndex = index + (before and 0 or 1)
        local beforeCandidate, afterCandidate = ordered[targetIndex - 1], ordered[targetIndex]
        local function RingRadius(candidate) return candidate.ringRadius or candidate.width * 0.5 end
        local function RingThickness(candidate) return candidate.ringThickness or runtime.ringThickness or 8 end
        local radius
        if beforeCandidate and afterCandidate then
            local inner, outer = beforeCandidate, afterCandidate
            if RingRadius(inner) > RingRadius(outer) then inner, outer = outer, inner end
            radius = (RingRadius(inner) + RingRadius(outer) - RingThickness(outer)) * 0.5
        else
            local innerBoundary = (runtime.direction == "outward" and afterCandidate ~= nil)
                or (runtime.direction == "inward" and beforeCandidate ~= nil)
            radius = RingRadius(nearestRing) + (innerBoundary
                and -RingThickness(nearestRing) - (runtime.ringStep or 8) * 0.5
                or (runtime.ringStep or 8) * 0.5)
        end
        radius = math.max(0, radius)
        return ResolveMonitorPlacement({
            operation = "insert", radial = true, targetLane = YHUD.CONTENT_LANE_SPEC,
            targetIndex = targetIndex, sourceLane = YHUD.CONTENT_LANE_SPEC,
            target = nearestRing, key = "ring:" .. targetIndex,
            beforeCandidate = beforeCandidate, afterCandidate = afterCandidate,
            orderedCandidates = ordered, vectorX = 0, vectorY = 1,
            seamX = nearestRing.x, seamY = nearestRing.y + radius,
            seamSpan = math.max(24, nearestRing.width * 0.5),
        }, snapshot)
    end
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
                GetRuntimeAxisSpacing(runtime, true), runtime), snapshot)
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
    if sourceIndex > 0 and sourceIndex < targetIndex then targetIndex = targetIndex - 1 end
    targetIndex = math.max(1, math.min(#snapshot + (crossGroup and 1 or 0), targetIndex))
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
        }, snapshot, sourceLogicalId, slot, cursorX, cursorY, axisSpacing, runtime), snapshot)
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
    local snapshot = slot and (slot._yhudDropSnapshot or slot._yhudDragSnapshot) or {}
    local direction = ResolveDragOrderDirection(runtime)
    local horizontal = direction == "right" or direction == "left"
    local sourceLogical = LogicalMonitorId(slot)
    local segmented = IsSegmentedDropTarget(runtime)
    local sourceSpecial = runtime._yhudDropSourceSpecial
    if sourceSpecial == nil then sourceSpecial = IsSpecialDragMonitor(self, sourceLogical) end
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

local function SetDropIndicatorPoint(indicator, x, y)
    indicator:ClearAllPoints()
    indicator:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    if GUI2.GetPixelOriginCorrection then
        local dx, dy, available = GUI2:GetPixelOriginCorrection(indicator)
        if available and (dx ~= 0 or dy ~= 0) then
            indicator:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x + dx, y + dy)
        end
    end
end

local function ApplyMakeRoom(runtime, session, progress)
    local distance = session.distance * progress
    if GUI2.SnapLayoutBoundary then
        distance = GUI2:SnapLayoutBoundary(runtime.frame, distance, session.layoutScale)
    end
    if session.currentDistance == distance then return end
    -- Use one snapped delta for the whole segment, preserving shared borders.
    local shiftX = session.radial and 0 or session.vectorX * distance
    local shiftY = session.radial and 0 or session.vectorY * distance
    session.currentDistance = distance
    session.currentShiftX, session.currentShiftY = shiftX, shiftY
    for _, slot in ipairs(session.slots) do
        local ring = session.rings[slot]
        if ring then
            local diameter = ring.diameter + distance * 2
            if slot.SetDurationRingSize then
                slot:SetDurationRingSize(diameter, ring.border, ring.thickness, ring.referenceDiameter, ring.material)
            else
                slot:SetSize(diameter, diameter)
            end
        else
            ApplyMakeRoomPoint(slot, shiftX, shiftY)
        end
    end
    View:RefreshDesignChromeGeometry(runtime)
    local candidate = session.targetCandidate
    local panel = candidate and runtime.designTargetFeedback and runtime.designTargetFeedback.panel
    if panel then
        local growth = session.radial and distance * 2 or 0
        panel:SetSize(candidate.width + math.abs(shiftX) + growth, candidate.height + math.abs(shiftY) + growth)
        panel:ClearAllPoints()
        panel:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
            (candidate.minX + candidate.maxX + shiftX) * 0.5,
            (candidate.minY + candidate.maxY + shiftY) * 0.5)
    end
    local indicator = runtime.designDropIndicator
    session.indicatorShiftX = shiftX * 0.5
    session.indicatorShiftY = session.radial and distance * 0.5 or shiftY * 0.5
    if indicator and session.drop.seamX and session.drop.seamY then
        SetDropIndicatorPoint(indicator,
            session.drop.seamX + session.indicatorShiftX, session.drop.seamY + session.indicatorShiftY)
    end
end

local function RestoreMakeRoom(runtime)
    local session = runtime and runtime._yhudDragMakeRoom
    if not session then return end
    if Animation and Animation.StopOwner then Animation:StopOwner(session, false) end
    ApplyMakeRoom(runtime, session, 0)
    for index = 1, #(session.slots or {}) do
        local slot = session.slots[index]
        if slot then
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
        and drop.target and not drop.invalidLane and not drop.invalidReason
        and not drop.invalidSpecialRegion and not drop.sameResourceRow) then
        return false
    end
    local ordered = drop.orderedCandidates
    local vectorX, vectorY = drop.vectorX, drop.vectorY
    if not ordered or vectorX == nil or vectorY == nil then return false end
    if drop.beforeCandidate and drop.afterCandidate
        and not (drop.sameVisualLine or drop.wrapBoundary or drop.radial) then return false end
    local distance = GUI2:GetPixelSize(runtime.frame, DRAG_MAKE_ROOM_PIXELS * 2, 1)
    if drop.wrapGap then
        -- Staggered rows can have overlapping bounding boxes. Open enough
        -- space for the caret and padding across the complete visual line.
        distance = math.max(distance,
            GUI2:GetPixelSize(runtime.frame, DRAG_INDICATOR_SIZE + 4, 1) - drop.wrapGap)
    end
    local session = {
        slots = {}, rings = {}, drop = drop, radial = drop.radial,
        vectorX = vectorX, vectorY = vectorY, distance = distance,
        layoutScale = GUI2.GetPixelLayoutScale and GUI2:GetPixelLayoutScale(runtime.frame),
        shiftX = vectorX * distance, shiftY = vectorY * distance,
    }
    local first, last = drop.targetIndex, #ordered
    if drop.radial and runtime.direction == "inward" then
        -- Always move the outer segment outwards, leaving inner rings intact.
        first, last = 1, drop.targetIndex - 1
    end
    local seen = {}
    local sourceLogicalId = LogicalMonitorId(slot)
    for index = first, last do
        local candidate = ordered[index]
        local slots = candidate.visualRow and candidate.visualRow.slots or CandidateSlots(candidate)
        for _, physicalSlot in ipairs(slots) do
            if not seen[physicalSlot] and LogicalMonitorId(physicalSlot) ~= sourceLogicalId then
                seen[physicalSlot] = true
                local point, relativeTo, relativePoint, x, y = ReadAnchor(physicalSlot)
                physicalSlot._yhudDragMakeRoomBase = {
                    point or "TOPLEFT", relativeTo or UIParent,
                    relativePoint or "TOPLEFT", x or 0, y or 0,
                }
                physicalSlot._yhudDragMakeRoomShiftX = drop.radial and 0 or session.shiftX
                physicalSlot._yhudDragMakeRoomShiftY = drop.radial and 0 or session.shiftY
                session.slots[#session.slots + 1] = physicalSlot
                if drop.radial then
                    local width = FrameSize(physicalSlot)
                    session.rings[physicalSlot] = {
                        diameter = physicalSlot._yhudRingDiameter or physicalSlot.gui2DurationRingSize or width,
                        border = physicalSlot._yhudRingBorder or runtime.border,
                        thickness = physicalSlot._yhudRingThickness or runtime.ringThickness,
                        referenceDiameter = physicalSlot._yhudRingReferenceDiameter or physicalSlot.gui2DurationRingReferenceSize,
                        material = physicalSlot._yhudRingMaterial,
                    }
                end
            end
        end
    end
    for _, candidate in ipairs(slot._yhudDragTargets or {}) do
        if candidate.runtime == runtime then session.targetCandidate = candidate; break end
    end
    runtime._yhudDragMakeRoom = session
    -- One tween keeps all physical members, the outline and the caret in step.
    if Animation and Animation.Tween then
        ApplyMakeRoom(runtime, session, 0)
        Animation:Tween({
            owner = session, target = runtime.frame, key = "yhud-drag-make-room",
            from = 0, to = 1, duration = DRAG_MAKE_ROOM_SECONDS, easing = "out",
            onUpdate = function(progress)
                if runtime._yhudDragMakeRoom == session then ApplyMakeRoom(runtime, session, progress) end
            end,
            onFinished = function(_, _, finished)
                if finished and runtime._yhudDragMakeRoom == session then ApplyMakeRoom(runtime, session, 1) end
            end,
        })
    else
        ApplyMakeRoom(runtime, session, 1)
    end
    return true
end

function View:ClearMonitorDropFeedback(runtime)
    if runtime then
        runtime.designDropFeedbackKey = nil
        RestoreMakeRoom(runtime)
        if runtime.designDropIndicator then runtime.designDropIndicator:Hide() end
        for index = 1, #(runtime.designForbiddenOverlays or {}) do
            runtime.designForbiddenOverlays[index]:Hide()
        end
    end
end

function View:UpdateMonitorDropFeedback(runtime, slot, drop)
    if not (runtime and slot) then return false end
    local key = drop and drop.key or "none"
    if runtime.designDropFeedbackKey == key then return false end
    runtime.designDropFeedbackKey = key
    local indicator = self:EnsureMonitorDropFeedback(runtime)
    self:UpdateForbiddenLaneOverlays(runtime, slot, drop)

    if drop and (drop.invalidReason or drop.invalidSpecialRegion or drop.invalidLane) then
        if indicator then indicator:Hide() end
        return false
    end

    if not (drop and indicator and drop.target) then
        if indicator then indicator:Hide() end
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
        local room = runtime._yhudDragMakeRoom
        local thickness = GUI2:GetPixelSize(indicator, DRAG_INDICATOR_SIZE, 1)
        local span = drop.seamSpan or (horizontal and drop.target.height or drop.target.width) + 6
        if GUI2.SnapLayoutBoundary then span = GUI2:SnapLayoutBoundary(indicator, span) end
        if horizontal then
            indicator:SetSize(
                thickness,
                span
            )
        else
            indicator:SetSize(
                span,
                thickness
            )
        end
        local x = drop.seamX + (room and room.indicatorShiftX or 0)
        local y = drop.seamY + (room and room.indicatorShiftY or 0)
        SetDropIndicatorPoint(indicator, x, y)
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
    indicator:Show()
    return true
end

local function EnsureMonitorTargetFeedback(runtime)
    if runtime.designTargetFeedback then return runtime.designTargetFeedback end
    -- Feedback must not inherit the dimmed content group's alpha.
    local panel = GUI2:CreateFrame(UIParent, { mouse = false, hidden = true })
    GUI2:CreateBorder(panel, "color.border.accent")
    local fill = GUI2:CreatePanel(panel, {
        surface = "color.accent.soft", border = false,
    })
    fill:SetAllPoints(panel)
    fill:SetAlpha(0.3)
    fill:EnableMouse(false)
    local forbidden = GUI2:CreatePanel(panel, {
        surface = "color.state.error", border = false,
    })
    forbidden:SetAllPoints(panel)
    forbidden:SetAlpha(0.14)
    forbidden:EnableMouse(false)
    local label = CreateDragLabel(UIParent)
    label.text:SetWordWrap(false)
    runtime.designTargetFeedback = { panel = panel, fill = fill, forbidden = forbidden, label = label }
    RecordDesignCreate("chrome", 3)
    return runtime.designTargetFeedback
end

local function SetMonitorTargetFeedback(candidate, hovered, drop)
    local runtime = candidate.runtime
    local reason = hovered and drop and (drop.invalidSpecialRegion
        and "special-overflow-region" or drop.invalidReason) or nil
    if candidate.feedbackInitialized and candidate.feedbackHovered == hovered
        and candidate.feedbackReason == reason then return end
    candidate.feedbackInitialized = true
    candidate.feedbackHovered, candidate.feedbackReason = hovered, reason
    local feedback = EnsureMonitorTargetFeedback(runtime)
    feedback.panel:SetSize(candidate.width, candidate.height)
    feedback.panel:ClearAllPoints()
    feedback.panel:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
        (candidate.minX + candidate.maxX) * 0.5, (candidate.minY + candidate.maxY) * 0.5)
    feedback.panel:SetFrameStrata("FULLSCREEN_DIALOG")
    feedback.fill:SetFrameStrata("FULLSCREEN_DIALOG")
    feedback.forbidden:SetFrameStrata("FULLSCREEN_DIALOG")
    feedback.label:SetFrameStrata("FULLSCREEN_DIALOG")
    feedback.panel:SetFrameLevel(310)
    feedback.fill:SetFrameLevel(311)
    feedback.forbidden:SetFrameLevel(311)
    feedback.label:SetFrameLevel(312)
    local forbidden = reason ~= nil
    SetShown(feedback.panel, candidate.allowed or forbidden)
    feedback.panel:SetAlpha(1)
    SetShown(feedback.fill, hovered and candidate.allowed and not forbidden)
    SetShown(feedback.forbidden, forbidden)
    GUI2:SetBorderColor(feedback.panel, forbidden and "color.state.error"
        or hovered and "color.border.accent" or "color.border.default")
    feedback.label:SetText(GroupName(runtime.group))
    SetShown(feedback.label, (hovered or candidate.allowed) and candidate.labelBounds ~= false)
end

local function PlaceMonitorTargetLabel(candidate, candidates)
    local label = candidate.runtime.designTargetFeedback.label
    local width, height = FrameSize(label)
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    candidate.labelBounds = false
    for position = 1, 4 do
        local x = position == 3 and candidate.minX - width - 8
            or position == 4 and candidate.maxX + 8 or candidate.minX
        local top = position == 1 and candidate.maxY + height + 8
            or position == 2 and candidate.minY - 8 or candidate.maxY
        local clear = x >= 8 and x + width <= screenWidth - 8
            and top <= screenHeight - 8 and top - height >= 8
        if clear then
            for _, other in ipairs(candidates) do
                if DragRectOverlaps(x, x + width, top - height, top, other)
                    or other.labelBounds and DragRectOverlaps(x, x + width, top - height, top, other.labelBounds) then
                    clear = false
                    break
                end
            end
        end
        if clear then
            candidate.labelBounds = { minX = x, maxX = x + width, minY = top - height, maxY = top }
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, top)
            return
        end
    end
    -- In a crowded layout the active cursor hint still names the destination.
    label:Hide()
end

function View:BeginMonitorTargetDrag(slot, sourceRuntime)
    if not self.designGetMonitorTargets or slot._yhudDesignResourceId then return end
    local targets, revision = self.designGetMonitorTargets(LogicalMonitorId(slot))
    if not targets then return end
    slot._yhudDragSnapshot._yhudDraftRevision = revision
    local groups = sourceRuntime._yhudDesignProjection
        and self.designProjection.groups or self.groups
    local profile = DesignProfileForRuntime(sourceRuntime)
    local candidates = {}
    for index, groupId in ipairs(profile.groups.order or {}) do
        local runtime = groups[groupId]
        local access = targets[groupId]
        if runtime and access and runtime.group.enabled ~= false
            and runtime.designerStateAllowed ~= false
            and runtime.frame:IsShown() then
            local x, y = runtime.frame:GetCenter()
            local width, height = FrameSize(runtime.frame)
            if x and y then
                local snapshot = runtime == sourceRuntime and slot._yhudDragSnapshot
                    or CaptureDragSnapshot(runtime, slot)
                local minX, maxX = x - width * 0.5, x + width * 0.5
                local minY, maxY = y - height * 0.5, y + height * 0.5
                for _, item in ipairs(snapshot) do
                    for _, physical in ipairs(item.physical) do
                        minX = math.min(minX, physical.x - physical.width * 0.5)
                        maxX = math.max(maxX, physical.x + physical.width * 0.5)
                        minY = math.min(minY, physical.y - physical.height * 0.5)
                        maxY = math.max(maxY, physical.y + physical.height * 0.5)
                    end
                end
                minX, maxX = math.min(minX, x - 50), math.max(maxX, x + 50)
                minY, maxY = math.min(minY, y - 18), math.max(maxY, y + 18)
                width, height = maxX - minX, maxY - minY
                local frameLevel = runtime.frame.GetFrameLevel and runtime.frame:GetFrameLevel()
                local candidate = {
                    runtime = runtime, snapshot = snapshot, allowed = access.allowed,
                    reason = access.reason, width = width, height = height,
                    appearanceReset = access.appearanceReset,
                    minX = minX, maxX = maxX, minY = minY, maxY = maxY,
                    offsetX = (minX + maxX) * 0.5 - x, offsetY = (minY + maxY) * 0.5 - y,
                    layer = frameLevel and frameLevel > 0 and frameLevel
                        or (runtime.group.displayLayer or 5) * 10000 + index,
                }
                candidate.chrome = {}
                for _, field in ipairs({ "designHeader", "designMover", "designOutline" }) do
                    local control = runtime[field]
                    if control then
                        candidate.chrome[#candidate.chrome + 1] = { control = control, shown = control:IsShown() }
                        control:Hide()
                    end
                end
                runtime._yhudDropSegmented = access.segmented
                runtime._yhudDropSourceSpecial = access.sourceSpecial
                candidates[#candidates + 1] = candidate
                SetMonitorTargetFeedback(candidate, false)
            end
        end
    end
    for _, candidate in ipairs(candidates) do
        PlaceMonitorTargetLabel(candidate, candidates)
    end
    slot._yhudDragTargets = candidates
end

function View:ResolveMonitorDragTarget(slot, sourceRuntime, cursorX, cursorY)
    if not cursorX or not cursorY then return nil, nil end
    local candidates = slot._yhudDragTargets
    if not candidates then
        return sourceRuntime, self:ResolveMonitorDrop(sourceRuntime, slot, cursorX, cursorY)
    end
    local selected, selectedRank
    for _, candidate in ipairs(candidates) do
        local inside = cursorX >= candidate.minX and cursorX <= candidate.maxX
            and cursorY >= candidate.minY and cursorY <= candidate.maxY
        local nearby = cursorX >= candidate.minX - DRAG_GROUP_PADDING
            and cursorX <= candidate.maxX + DRAG_GROUP_PADDING
            and cursorY >= candidate.minY - DRAG_GROUP_PADDING
            and cursorY <= candidate.maxY + DRAG_GROUP_PADDING
        if nearby then
            local rank = candidate.layer + (inside and 10000000 or 0)
            if not selectedRank or rank > selectedRank then selected, selectedRank = candidate, rank end
        end
    end
    local runtime = selected and selected.runtime
    slot._yhudDropSnapshot = selected and selected.snapshot or nil
    local drop
    if selected then
        if not selected.allowed then
            drop = { invalidReason = selected.reason or "unsupported", key = "forbidden:" .. runtime.id }
        else
            drop = self:ResolveMonitorDrop(runtime, slot, cursorX, cursorY,
                runtime ~= sourceRuntime and selected.snapshot or nil)
        end
        if drop then
            drop.targetGroupId = runtime.id
            drop.crossGroup = runtime ~= sourceRuntime
            drop.appearanceReset = selected.appearanceReset
            drop.key = runtime.id .. ":" .. drop.key
            if drop.placement then
                local source = slot._yhudDragSnapshot
                drop.placement.sourceGroupId = source._yhudSourceGroupId
                drop.placement.sourceSpecKey = source._yhudSourceSpecKey
                drop.placement.targetGroupId = runtime.id
                drop.placement.draftRevision = source._yhudDraftRevision
            end
        end
    end
    for _, candidate in ipairs(candidates) do
        SetMonitorTargetFeedback(candidate, candidate == selected, drop)
    end
    return runtime, drop
end

local function UpdateMonitorDragHint(slot, runtime, drop)
    local preview = slot._yhudDragPreview
    local key = drop and drop.key or "none"
    if not preview or slot._yhudDragStatus == key then return end
    slot._yhudDragStatus = key
    local text
    if not drop then
        text = YHUD:T("designer.drag.cancel")
    elseif drop.invalidReason or drop.invalidSpecialRegion or drop.invalidLane then
        local reason = drop.invalidSpecialRegion and "special-overflow-region" or drop.invalidReason
        local description = reason and YHUD:T("designer.drag.reason." .. reason,
            YHUD:T("designer.drag.reason.unsupported"))
            or YHUD:T("designer.drag.native_interior_forbidden")
        text = string.format(YHUD:T("designer.drag.cannot_drop", "× 无法放入：%s"), description)
    else
        local position = drop.targetIndex or 1
        if drop.placement then
            position = 1
            for _, item in ipairs(slot._yhudDropSnapshot or slot._yhudDragSnapshot or {}) do
                if item.monitorId ~= LogicalMonitorId(slot) then
                    if drop.placement.kind == "head" or item.monitorId == drop.placement.beforeMonitorId then break end
                    position = position + 1
                end
            end
        end
        text = drop.crossGroup and string.format(
            YHUD:T("designer.drag.move_position", "移入「%s」· 第 %d 位"), GroupName(runtime.group), position)
            or string.format(YHUD:T("designer.drag.reorder_position", "调整至第 %d 位"), position)
        if drop.appearanceReset then
            text = text .. "\n" .. YHUD:T("designer.drag.appearance_reset")
        end
    end
    preview.hint:SetText(text)
    preview.hint:Show()
end

function View:UpdateMonitorDrag(slot)
    if not (slot and slot._yhudDragging) then return false end
    local runtime = DesignRuntimeForSlot(slot)
    if not runtime then return false end
    for _, candidate in ipairs(slot._yhudDragTargets or {}) do
        if not candidate.runtime.frame:IsShown() then
            return self:FinishMonitorDrag(slot, true)
        end
    end
    local cursorX, cursorY = GetDragPointer(slot)
    local targetRuntime, drop = self:ResolveMonitorDragTarget(slot, runtime, cursorX, cursorY)
    UpdateMonitorDragHint(slot, targetRuntime, drop)
    UpdateMonitorDragPreview(slot, cursorX, cursorY)
    local previousRuntime = slot._yhudDropRuntime
    if previousRuntime and previousRuntime ~= targetRuntime then
        self:ClearMonitorDropFeedback(previousRuntime)
    end
    slot._yhudDropRuntime = targetRuntime
    slot._yhudDrop = drop
    self:UpdateMakeRoomFeedback(targetRuntime, slot, drop)
    self:UpdateMonitorDropFeedback(targetRuntime, slot, drop)
    return drop ~= nil
end

function View:SetOtherGroupsDragDimmed(sourceRuntime, dimmed, slot)
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
                local allowed = false
                for _, candidate in ipairs(slot and slot._yhudDragTargets or {}) do
                    if candidate.runtime == runtime then allowed = candidate.allowed; break end
                end
                if runtime.frame.SetAlpha then runtime.frame:SetAlpha(allowed and 1 or 0.36) end
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
    self:ClearMonitorDropFeedback(slot._yhudDropRuntime)
    self:ClearMonitorDropFeedback(runtime)
    for _, candidate in ipairs(slot._yhudDragTargets or {}) do
        candidate.runtime._yhudDropSegmented = nil
        candidate.runtime._yhudDropSourceSpecial = nil
        local feedback = candidate.runtime.designTargetFeedback
        if feedback then
            feedback.panel:Hide()
            feedback.fill:Hide()
            feedback.forbidden:Hide()
            feedback.label:Hide()
        end
        for _, state in ipairs(candidate.chrome) do
            SetShown(state.control, state.shown)
        end
    end
    slot._yhudDragTargets = nil
    slot._yhudDropRuntime = nil
    slot._yhudDropSnapshot = nil
    slot._yhudDragStatus = nil
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
        and not drop.invalidReason
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
    if slot then slot._yhudDesignResourcePreviewColor, slot._yhudDesignResourceCountdown = nil, nil end
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
    if self.RefreshResourcePreviewBarShadow then self:RefreshResourcePreviewBarShadow(slot) end
    slot._yhudDesignResourcePreviewAppearanceDirty = true
    return true
end

function View:ClearDesignSlot(slot)
    if not slot then return end
    ClearDesignProgressSample(slot)
    if YHUD.ClassExtra then YHUD.ClassExtra:ClearDesignPreview(slot) end
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
        and not self.designLayoutMode
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
        and not self.designLayoutMode
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
        or (self.designProjection and slot._yhudDesignProjection ~= true)
        or (slot._yhudSynthetic == true and not resource) then
        self:ClearDesignSlot(slot)
        return false
    end
    slot._yhudDesignResourceId = resource and resource.id or nil
    if self.designLayoutMode then
        I.SetSlotMouseInput(slot, false, false)
        self:SetDesignSlotHovered(slot, false)
        SetShown(slot._yhudDesignSelectionOutline, false)
        return true
    end
    local runtime = DesignRuntimeForSlot(slot)
    slot._yhudDragPairId = runtime and runtime.handPairMode == "split" and resource
        and (resource.id == "swingMainHand" or resource.id == "swingOffHand")
        and (slot._yhudGroupId .. ":swingHands") or nil
    local dragEnabled = not readOnlyPreview
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
            View:BeginMonitorTargetDrag(frame, runtime)
            SetBundleDragActive(frame, true)
            HideBundleSelectionOutlines(frame)
            View.activeMonitorDrag = frame
            View:SetOtherGroupsDragDimmed(runtime, true, frame)
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
    if enabled and YHUD.PressFeedback and YHUD.PressFeedback.active then YHUD.PressFeedback:Clear() end
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
    if enabled and YHUD.PressFeedback and YHUD.PressFeedback.active then YHUD.PressFeedback:Clear() end
    if self.layoutEditMode == enabled then return false end
    self.layoutEditMode = enabled
    if self.RefreshBuffTimerStackModes then self:RefreshBuffTimerStackModes() end
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

local function ApplyDesignResourcePreviewColor(slot, preview)
    local pending = slot._yhudDesignResourcePreviewColor
    if pending and preview.PreviewResourceColor then
        preview:PreviewResourceColor(pending.field, pending.color)
    end
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
            pointShape = source.pointShape,
            nativePointStyle = source.nativePointStyle,
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
            rangedWindup = source.rangedWindup,
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
    ApplyDesignResourcePreviewColor(slot, preview)
    -- Reconfiguration can reset native fills without changing the sample.
    preview._yhudPreviewResourceId = nil
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
    ApplyDesignResourcePreviewColor(slot, preview)
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
        if self.RefreshResourcePreviewBarShadow then self:RefreshResourcePreviewBarShadow(slot) end
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
                local monitor = projection.desiredMonitors and projection.desiredMonitors[slot._yhudMonitorId]
                local preset = monitor and monitor._yhudResource
                applied = self:ApplyDesignResourcePreviewSlot(
                    slot,
                    preset and preset.customEntry and preset or definition,
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
                    preset.customEntry and preset or definition,
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
        local selected = not View.designLayoutMode and groupId == selectedGroupId
        local stateAllowed = runtime.designerStateAllowed ~= false
        local empty = not View.designLayoutMode and runtime.monitorCount == 0
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

local function IsResourceCountdownPreset(preset)
    local kind = preset and preset.provider and preset.provider.kind
    return kind == "aura-duration" or kind == "global-cooldown"
        or kind == "monitor-time" and preset.progress and preset.progress.source == "time"
end

function View:ApplyDesignResourceCountdownSlot(slot, elapsed, visible)
    local projection = self.designProjection
    local monitors = projection and projection.desiredMonitors or self.desiredMonitors
    local monitor = monitors and monitors[slot._yhudMonitorId]
    local preset = monitor and monitor._yhudResource
    if not IsResourceCountdownPreset(preset) then
        if slot._yhudDesignResourceCountdown then self:ClearResourcePreviewSlot(slot) end
        return false, false
    end
    if not visible or not self.designDurationPreviewEnabled then return false, true end
    local duration = math.max(0.1,tonumber(preset.previewMax) or 10)
    -- One second at zero makes the end of each countdown visible. The existing
    -- design ticker owns every timer; selecting one must not start a second loop.
    local progress = math.max(0,1-(elapsed % (duration+1))/duration)
    local applied = self:ApplyDesignResourcePreviewSlot(slot,preset,progress)
    slot._yhudDesignResourceCountdown = applied == true or nil
    return applied, true
end

function View:RefreshDesignResourceCountdown(resourceId, groupId)
    if not self.designMode then return false, false end
    local projection = self.designProjection
    local slots = projection and projection.resourceSlotsById and projection.resourceSlotsById[resourceId]
    if not slots then return false, false end
    local now = _G.GetTime and _G.GetTime() or 0
    local elapsed = math.max(0,now-(self.designDurationPreviewStartedAt or now))
    local applied, eligible = false, false
    for _, slot in ipairs(slots) do
        if groupId == nil or slot._yhudGroupId == groupId then
            local runtime = DesignRuntimeForSlot(slot)
            local visible = runtime and runtime.enabled == true
                and (not runtime.frame.IsShown or runtime.frame:IsShown())
                and (not slot.IsShown or slot:IsShown())
            local updated, countdown = self:ApplyDesignResourceCountdownSlot(slot,elapsed,visible)
            applied, eligible = updated or applied, countdown or eligible
        end
    end
    return applied, eligible
end

function View:ApplyDesignDurationPreview(slot, now, tickOnly)
    if not (self.designMode and self.designDurationPreviewEnabled and slot) then
        return false
    end
    if self.designProjection and slot._yhudDesignProjection ~= true then
        return false
    end
    if YHUD.ClassExtra and YHUD.ClassExtra.previews[slot] then return true end
    now = type(now) == "number" and now
        or (_G.GetTime and _G.GetTime() or 0)
    local elapsed = math.max(0, now - (self.designDurationPreviewStartedAt or now))
    local runtime = DesignRuntimeForSlot(slot)
    local visible = runtime
        and runtime.enabled == true
        and (not runtime.frame.IsShown or runtime.frame:IsShown())
        and (not slot.IsShown or slot:IsShown())
    if slot._yhudView == "resource" and self.ApplyDesignResourceCountdownSlot then
        return self:ApplyDesignResourceCountdownSlot(slot,elapsed,visible)
    end
    local durationView = slot._yhudView == "ring"
        or slot._yhudView == "bar"
    if durationView and visible and slot._yhudBarProgress and slot._yhudBarProgress.source ~= "time"
        and self.ApplyBarValue then
        local charges = slot._yhudBarProgress.source == "spell-charges"
        local maximum = slot._yhudBarMaximum
        local previous = slot._yhudDesignBarPreview
        local previousProgress = slot._yhudDesignDurationPreviewProgress
        local previousValue = previous and previous.value
        local previousFraction = previous and previous.fraction
        local sample = maximum and DesignBarPlaybackSample(slot, elapsed) or nil
        if not maximum then slot._yhudDesignBarPreview = nil end
        slot._yhudDesignDurationPreviewCycle = nil
        slot._yhudDesignDurationPreviewProgress = slot._yhudBarProgress
        if not tickOnly then slot._yhudBarValueValid = nil end
        self:ApplyBarValue(slot, runtime, sample and sample.value or 0, maximum, false)
        if charges and maximum and (not tickOnly or sample ~= previous or previousValue ~= sample.value
            or previousFraction ~= sample.fraction or not slot.gui2RechargeActive) then
            GUI2:SetProjectedStatusBarRechargePreview(slot, sample.fraction)
        elseif (not charges or not maximum) and GUI2.SetProjectedStatusBarRecharge then
            GUI2:SetProjectedStatusBarRecharge(slot, nil)
        end
        if not tickOnly or sample ~= previous or previousProgress ~= slot._yhudBarProgress
            or (sample and previousValue ~= sample.value) then
            self:EnsureDesignTextPreview(slot)
            self:ApplyDesignTextPreview(slot)
        end
        return true
    end
    if durationView and visible and slot.SetDurationFromTimes then
        local period = DESIGN_DURATION_SECONDS - DESIGN_DURATION_PREVIEW_ELAPSED
        local cycle = math.floor(elapsed / period)
        if tickOnly and slot._yhudDesignDurationPreviewCycle == cycle
            and slot._yhudDesignDurationPreviewProgress == slot._yhudBarProgress then return true end
        slot._yhudDesignBarPreview = nil
        slot._yhudDesignDurationPreviewCycle = cycle
        slot._yhudDesignDurationPreviewProgress = slot._yhudBarProgress
        local startTime = now - elapsed + cycle * period - DESIGN_DURATION_PREVIEW_ELAPSED
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
    if durationView and slot.ClearDuration
        and (slot._yhudDesignDurationPreviewCycle ~= nil or slot._yhudDesignBarPreview) then
        ClearDesignProgressSample(slot)
        slot:ClearDuration()
        slot._yhudBarValueValid, slot._yhudBarPublicValue = nil, nil
        if GUI2.SetProjectedStatusBarRecharge then GUI2:SetProjectedStatusBarRecharge(slot, nil) end
    end
    return false
end

function View:RefreshDesignDurationPreview(tickOnly)
    if not (self.designMode and self.designDurationPreviewEnabled) then
        return false
    end
    local now = _G.GetTime and _G.GetTime() or 0
    local applied = false
    ForEachDesignSlot(function(slot)
        applied = self:ApplyDesignDurationPreview(slot, now, tickOnly) or applied
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
        self.designDurationPreviewStartedAt = nil
        ForEachDesignSlot(function(slot)
            ClearDesignProgressSample(slot)
            if slot._yhudDesignResourceCountdown then self:ClearResourcePreviewSlot(slot) end
            if (slot._yhudView == "ring" or slot._yhudView == "bar")
                and slot.ClearDuration then
                if slot._yhudDesignProjection ~= true then
                    self.designRuntimeRestoreRequired = true
                end
                slot:ClearDuration()
                slot._yhudDurationMode, slot._yhudOpaqueRevision = nil, nil
                slot._yhudBarValueValid, slot._yhudBarPublicValue = nil, nil
                slot._yhudBarCountdownMode, slot._yhudBarCountdownRevision = nil, nil
                if slot._yhudBarProgress
                    and slot._yhudBarProgress.source == "spell-charges" then
                    GUI2:SetProjectedStatusBarRecharge(slot, nil)
                end
            end
            self:ApplyDesignTextPreview(slot)
        end)
    end
    if not enabled then return true end

    self.designDurationPreviewStartedAt = _G.GetTime and _G.GetTime() or 0
    self:RefreshDesignDurationPreview()
    local timer = _G.C_Timer
    if timer and timer.NewTicker then
        local ticker
        ticker = timer.NewTicker(
            DESIGN_DURATION_PREVIEW_INTERVAL,
            function()
                if View.designMode
                    and View.designDurationPreviewEnabled
                    and View.designDurationPreviewTicker == ticker then
                    View:RefreshDesignDurationPreview(true)
                end
            end
        )
        self.designDurationPreviewTicker = ticker
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
        classFile, specID = ResourceCatalog:GetCurrentContext()
        formKey = ResourceCatalog:GetCurrentFormKey(classFile, specID)
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
    local bridge = YHUD.LayoutBridge
    if bridge and bridge.SyncDesignProjection then
        return bridge:SyncDesignProjection(projection)
    end
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

function View:SetDesignLayoutMode(enabled)
    enabled = enabled == true
    self.designLayoutMode = enabled
    local projection = self.designProjection
    if enabled and I.CancelDesignTooltip then I.CancelDesignTooltip() end
    if projection and self.ApplyGroupDisplayLayers then
        self:ApplyGroupDisplayLayers(projection.profile, projection)
    end
    for _, runtime in pairs(projection and projection.groups or {}) do
        runtime.frame:EnableMouse(not enabled)
        if enabled then
            if runtime.designHeader then runtime.designHeader:Hide() end
            if runtime.designMover then runtime.designMover:Hide() end
            if runtime.designOutline then runtime.designOutline:Hide() end
        else
            self:RefreshDesignProjectionVisibility(runtime)
        end
    end
    for _, slot in pairs(projection and projection.byMonitor or {}) do
        if enabled then
            I.SetSlotMouseInput(slot, false, false)
            self:SetDesignSlotHovered(slot, false)
            SetShown(slot._yhudDesignSelectionOutline, false)
        else
            self:ConfigureDesignSlot(slot)
        end
    end
end

local function AcquireProjectionGroup(self, projection, groupPlan)
    local group = groupPlan and groupPlan.group
    if not group then return nil end
    local runtime = projection.groups[group.id]
    if runtime then return runtime end
    runtime = PopProjectionPool(ProjectionPools(self).groups) or {}
    local frame = runtime.frame
    if not frame then
        self.designProjectionFrameSerial = (self.designProjectionFrameSerial or 0) + 1
        frame = GUI2:CreateFrame(UIParent, {
            name = "YUI_YHUD_DesignGroup_" .. self.designProjectionFrameSerial,
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
    runtime.designMoveFrame = not (YHUD.LayoutBridge and YHUD.LayoutBridge.SyncDesignProjection)
        and self.groups[group.id] and self.groups[group.id].frame or nil
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
        local width, height = I.ResolveResourceSize(runtime, runtime.resourceWidth, runtime.resourceHeight)
        return App:CreateResourceBar(runtime.frame, {
            width = width,
            height = height,
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
    if YHUD.ClassExtra then
        YHUD.ClassExtra:StartDesignPreview(self, slot, member.entry, member.monitor, runtime)
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
    local minimumStep = GUI2.GetPixelSize
        and GUI2:GetPixelSize(runtime.frame, 1, 1) or (GUI2.mult or 1)
    local resourceScale
    local flowBlocks = I.GetColumnFlowPreviewBlocks(runtime, slots, #slots)
    if runtime.view == "resource" then
        resourceScale = GUI2.GetPixelLayoutScale and GUI2:GetPixelLayoutScale(runtime.frame)
        runtime.effectiveResourceWidth = I.ResolveResourceWidth(View, runtime)
        resourceMetrics = {}
        for index = 1, #slots do
            local member = runtime.members and runtime.members[index]
            local spec = member and member.resourceSpec
            local thickness = I.SnapResourceThickness(runtime.frame,
                spec and spec.height or runtime.resourceHeight, minimumStep, resourceScale)
            local width, height = I.ResolveResourceSize(runtime,
                runtime.effectiveResourceWidth or spec and spec.width or runtime.resourceWidth,
                thickness)
            resourceMetrics[index] = {
                resourceId = slots[index] and slots[index]._yhudResourceId,
                width = width,
                height = height,
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
            flowBlocks = flowBlocks,
            fixedLayout = runtime.layoutMode == "fixed",
            pixelSize = GUI2.GetPixelSize and function(pixels)
                return GUI2:GetPixelSize(runtime.frame, pixels, pixels)
            end or nil,
            minimumPixelStep = minimumStep,
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
            local preview = slot._yhudDesignResourcePreview
            if slot._yhudDesignResourcePreviewBound and preview and preview.SetResourceBarSize then
                preview:SetResourceBarSize(width, height, self.runtime.orientation)
            end
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
        local x, y = placement.x, placement.y
        if self.runtime.view == "resource" and GUI2.SnapLayoutBoundary then
            -- Mixed thicknesses can also centre a row on a half pixel.
            x = GUI2:SnapLayoutBoundary(self.runtime.frame, x, resourceScale)
            y = GUI2:SnapLayoutBoundary(self.runtime.frame, y, resourceScale)
        end
        slot:ClearAllPoints()
        slot:SetPoint(
            placement.point,
            self.runtime.frame,
            placement.relativePoint,
            x,
            y
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
    if View.ApplyBarShadows then View:ApplyBarShadows(runtime, slots, #slots, #slots) end
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
    if self.activeDesignGroupDrag and self.activeDesignGroupDrag.id == groupId then
        FinishDesignGroupDrag(self.activeDesignGroupDrag, true)
    end
    local pools = ProjectionPools(self)
    for monitorId, slot in pairs(projection.byMonitor or {}) do
        if slot and slot._yhudGroupId == groupId then
            if GUI2.HideBarShadow then GUI2:HideBarShadow(slot) end
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
        if self.ClearBarShadows then self:ClearBarShadows(runtime) end
        local bridge = YHUD.LayoutBridge
        if bridge and bridge.UnregisterDesignProjectionGroup then
            bridge:UnregisterDesignProjectionGroup(groupId, runtime.frame)
        end
        if runtime.designHeader then runtime.designHeader:Hide() end
        if runtime.designMover then runtime.designMover:Hide() end
        if runtime.designOutline then runtime.designOutline:Hide() end
        runtime.frame:SetScript("OnMouseDown", nil)
        runtime.frame:EnableMouse(false)
        runtime.frame:ClearAllPoints()
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
        classFile, specID = ResourceCatalog:GetCurrentContext()
        formKey = ResourceCatalog:GetCurrentFormKey(classFile, specID)
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
    FinishDesignGroupDrag(self.activeDesignGroupDrag, true)
    projection.releasing = true
    local bridge = YHUD.LayoutBridge
    if bridge and bridge.designLayoutProjection == projection then
        bridge:EndDesignLayout(true)
    end
    -- Stop while the projection still owns the preview slots. After release,
    -- ForEachDesignSlot falls back to the live slot registry.
    if preserveLiveState ~= true then self:SetDesignDurationPreviewEnabled(false) end
    if preserveLiveState ~= true then self:SetDesignGlowPreview(nil, nil, nil) end
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
        if self.ClearBarShadows then self:ClearBarShadows(runtime) end
        local bridge = YHUD.LayoutBridge
        if bridge and bridge.UnregisterDesignProjectionGroup then
            bridge:UnregisterDesignProjectionGroup(groupId, runtime.frame)
        end
        if runtime.designHeader then runtime.designHeader:Hide() end
        if runtime.designMover then runtime.designMover:Hide() end
        if runtime.designOutline then runtime.designOutline:Hide() end
        runtime.frame:SetScript("OnMouseDown", nil)
        runtime.frame:EnableMouse(false)
        runtime.frame:ClearAllPoints()
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
    if preserveLiveState ~= true then self.classExtraPreviewTimes = nil end
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
    onGroupDragStop,
    onGetMonitorTargets
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
        onGroupDragStop,
        onGetMonitorTargets
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
    local selected = not self.designLayoutMode and runtime.id == self.selectedGroupId
    local empty = not self.designLayoutMode and runtime.monitorCount == 0 and runtime.designContent ~= true
    if runtime.designHeader then SetShown(runtime.designHeader, visible and selected) end
    if runtime.designOutline then SetShown(runtime.designOutline, visible and selected) end
    if runtime.designMover then SetShown(runtime.designMover, visible and empty) end
    if runtime.designMoverLabel then SetShown(runtime.designMoverLabel, visible and empty and not selected) end
    if YHUD.ClassExtra then YHUD.ClassExtra:RefreshClockDriver() end
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
    frame:EnableMouse(not self.designLayoutMode)
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
    local selected = not self.designLayoutMode and groupId == self.selectedGroupId
    local stateAllowed = runtime.designerStateAllowed ~= false
    local empty = not self.designLayoutMode and runtime.monitorCount == 0
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
    if YHUD.ClassExtra then YHUD.ClassExtra:RefreshClockDriver() end

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
    onGroupDragStop,
    onGetMonitorTargets
)
    enabled = enabled == true
    if enabled and YHUD.PressFeedback and YHUD.PressFeedback.active then YHUD.PressFeedback:Clear() end
    local wasEnabled = self.designMode == true
    if not enabled then
        self:SetDesignGlowPreview(nil, nil, nil)
        self:SetDesignDurationPreviewEnabled(false)
        FinishDesignGroupDrag(self.activeDesignGroupDrag)
        if self.designProjection then self:ReleaseDesignProjection() end
        self.designCooldownPreviewGroupId = nil
        self.designTextPreviewTarget = nil
        self:CancelMonitorDrag()
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
    self.designGetMonitorTargets = enabled and onGetMonitorTargets or nil

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
    onGroupDragStop,
    onGetMonitorTargets
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
        onGroupDragStop,
        onGetMonitorTargets
    )
    if not prepared then return false end
    return self:RefreshDesignModePresentation(enabled, wasEnabled, false)
end
