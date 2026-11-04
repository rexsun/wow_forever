local YUI = _G.YUI
local H = YUI and YUI.YHUD
local View = H and H.View
local GUI2 = YUI and YUI.GUI2
if not (View and GUI2) then return end

function View:ClearBarShadows(runtime)
    if not runtime then return end
    GUI2:HideRectShadow(runtime.barGroupShadow)
    runtime.barShadowEffectiveMode = nil
    if runtime.barShadowFrames then
        for frame in pairs(runtime.barShadowFrames) do
            GUI2:HideBarShadow(frame, runtime)
            runtime.barShadowFrames[frame] = nil
        end
    end
end

local function Contour(frame)
    if not frame then return nil end
    if frame._yhudNativeStableSlot then frame = frame._yhudNativeFrame end
    if not frame then return nil end
    if frame._yhudView == "resource" then
        return frame._yhudDesignResourcePreviewBound
            and frame._yhudDesignResourcePreview or frame
    end
    if frame._yhudView == "bar" then return frame end
    local bridge = H.NativeBridge
    return bridge and bridge.GetBarShadowContour and bridge:GetBarShadowContour(frame)
end

-- The public value preview hides the original track, including its shadows.
-- Move the existing group ownership to the visible surface at bind/unbind.
function View:RefreshResourcePreviewBarShadow(slot)
    local groupId = slot and slot._yhudGroupId
    local groups = slot and slot._yhudDesignProjection
        and self.designProjection and self.designProjection.groups or self.groups
    local runtime = groupId and groups and groups[groupId]
    if not runtime or runtime.barShadowEffectiveMode ~= "item" then return end
    if slot._yhudDesignProjection and not self.designProjection then return end
    local seen = runtime.barShadowFrames
    local preview = slot._yhudDesignResourcePreview
    if not seen or not (seen[slot] or preview and seen[preview]) then return end
    local target = Contour(slot)
    local previous = target == slot and preview or slot
    if previous and seen[previous] then
        GUI2:HideBarShadow(previous, runtime)
        seen[previous] = nil
    end
    GUI2:SetBarShadow(target, true, runtime.barShadowColor, runtime, runtime.barShadowThickness)
    seen[target] = true
end

function View:ApplyBarShadows(runtime, frames, count, visibleCount)
    local mode = runtime.barShadowMode
    if (runtime.view ~= "resource" and runtime.view ~= "bar")
        or (mode ~= "item" and mode ~= "group") then
        self:ClearBarShadows(runtime)
        return
    end
    -- A bounding rectangle would fill the gaps around dots/independent cells.
    -- Use a single consistent mode for the whole group, never both layers.
    if mode == "group" then
        for index = 1, count do
            local frame = frames[index]
            local config = frame and frame.gui2ResourceDisplayConfig
            if config and (config.mode == "cells" or config.mode == "dots") then
                mode = "item"
                break
            end
        end
    end
    runtime.barShadowEffectiveMode = mode
    local color = runtime.barShadowColor or { r = 0, g = 0, b = 0, a = 0.5 }
    runtime.barShadowFrames = runtime.barShadowFrames or {}
    local seen = runtime.barShadowFrames
    for frame in pairs(seen) do seen[frame] = false end
    for index = 1, count do
        local frame = Contour(frames[index])
        if frame then
            GUI2:SetBarShadow(frame, mode == "item", color, runtime, runtime.barShadowThickness)
            seen[frame] = true
        end
    end
    for frame, used in pairs(seen) do
        if not used then GUI2:HideBarShadow(frame, runtime); seen[frame] = nil end
    end
    if mode == "group" then
        runtime.barGroupShadow = runtime.barGroupShadow or GUI2:CreateRectShadow(runtime.frame)
        local style = runtime.barGroupShadowStyle or { enabled = true, color = {} }
        runtime.barGroupShadowStyle = style
        style.extent = runtime.barShadowThickness or 4
        style.color[1], style.color[2], style.color[3], style.color[4] = color.r or color[1], color.g or color[2], color.b or color[3], color.a or color[4]
        self:ShowBarGroupShadow(runtime, visibleCount > 0)
    else
        GUI2:HideRectShadow(runtime.barGroupShadow)
    end
end

-- Cached resource visibility layouts can show/hide a group without relayout.
function View:ShowBarGroupShadow(runtime, shown)
    if runtime.barShadowEffectiveMode ~= "group" or not runtime.barGroupShadow then return end
    local style = runtime.barGroupShadowStyle
    style.enabled = shown == true
    GUI2:ApplyRectShadow(runtime.barGroupShadow, style, runtime.frame)
end

function View:PreviewBarShadowColor(groupId, color)
    local projection = self.designProjection
    local runtime = projection and projection.groups[groupId] or self.groups[groupId]
    if not runtime then return end
    local previous = runtime.barShadowColor
    runtime.barShadowColor = color
    if runtime.barShadowEffectiveMode == "group" and runtime.barGroupShadowStyle
        and runtime.barGroupShadowStyle.enabled then
        local style = runtime.barGroupShadowStyle
        style.color[1], style.color[2], style.color[3], style.color[4] = color.r or color[1], color.g or color[2], color.b or color[3], color.a or color[4]
        GUI2:ApplyRectShadow(runtime.barGroupShadow, style, runtime.frame)
    end
    if runtime.barShadowEffectiveMode == "item" then
        for frame in pairs(runtime.barShadowFrames or {}) do GUI2:SetBarShadow(frame, true, color, runtime, runtime.barShadowThickness) end
    end
    runtime.barShadowColor = previous
end
