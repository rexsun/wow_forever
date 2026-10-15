local YHUD = YUI and YUI.YHUD
local I = YHUD and YHUD.View and YHUD.View._internal
if not I then return end
local GUI2 = YUI.GUI2

function I.IsPlayerCastCollapsed(view, monitor, state)
    if view.preview or view.designMode or view.layoutEditMode
        or not (monitor and monitor._yhudResource and monitor._yhudResource.id == "cast") then return false end
    state = state or YHUD.Model and YHUD.Model:GetState(monitor.sourceKey)
    local presentation = monitor._yhudResourcePresentation
    local cast = presentation and presentation.style and presentation.style.cast
    return cast and cast.idle == "collapse" and not (state and state.castActive == true)
end

local function LayoutStages(slot)
    GUI2:UpdateCastMarkers(slot._yhudCastMarkers, slot.track,
        slot._yhudCastStages, slot._yhudCastTotal, slot._yhudCastTickCount,
        slot.gui2ResourceOrientation == "vertical", slot.gui2ResourceFillDirection == "reverse")
end

function I.ConfigurePlayerCast(slot, preset, style)
    local cast = preset.id == "cast" and style.cast or nil
    if not cast and not slot._yhudCastBaseSize then return end
    slot._yhudPlayerCast = cast
    slot:SetAlpha(1)
    slot._yhudCastAlpha, slot._yhudCastIdleCleared = 1, nil
    if cast and cast.icon and not slot.icon then
        slot.icon = GUI2:CreateIconSlot(slot, { size = 24, animate = false, motion = false })
    end
    if cast and not slot._yhudCastMarkers then
        slot._yhudCastMarkers = GUI2:CreateCastMarkers(slot.resourceOverlay or slot.track, 8)
    end
    slot.iconPosition = cast and cast.icon and cast.iconSide or nil
    slot.iconGap = cast and cast.iconGap or 0
    slot.gui2IconAutoSize = true
    if slot.icon then slot.icon:SetShown(slot.iconPosition ~= nil) end
    if not slot._yhudCastBaseSize then
        slot._yhudCastBaseSize = slot.SetResourceBarSize
        slot.SetResourceBarSize = function(self, ...)
            self._yhudCastBaseSize(self, ...)
            LayoutStages(self)
        end
    end
    slot:SetResourceBarSize(slot.gui2ResourceWidth, slot.gui2ResourceHeight, slot.gui2ResourceOrientation)
    if not cast then
        slot._yhudCastStages, slot._yhudCastTotal, slot._yhudCastTickCount = nil, nil, nil
        LayoutStages(slot)
    end
end

local function ApplyStageMarkers(slot, state)
    slot._yhudCastStages, slot._yhudCastTotal = state.castStages, state.castTotal
    slot._yhudCastTickCount = state.castTickCount
    LayoutStages(slot)
end

function I.UpdatePlayerCast(slot, state, preview)
    local cast = slot._yhudPlayerCast
    if not cast then return end
    local alpha = (preview or state and state.castActive) and 1 or 0
    if slot._yhudCastAlpha ~= alpha then
        slot:SetAlpha(alpha)
        slot._yhudCastAlpha = alpha
    end
    if preview then
        slot._yhudCastStages, slot._yhudCastTotal, slot._yhudCastTickCount = nil, nil, nil
        LayoutStages(slot)
        slot:SetResourceFillColor(slot._yhudResourceStyle.fillColor)
        slot:SetResourceValues(nil, nil, false, 0.58, 1, nil, nil, nil, nil, nil, nil, nil, true)
        slot.resourceNameText:SetText(YHUD:T("player_cast.preview_spell", "奥术冲击"))
        slot.resourceNameText:SetShown(cast.name)
        if slot.icon and slot.icon.icon then slot.icon.icon:SetTexture(136096) end
        slot.resourceDurationCountdown:Hide()
        slot.resourceValueText:SetText("1.2")
        slot.resourceValueText:SetShown(cast.progress)
        return
    end
    if not state or not state.castActive then
        if not slot._yhudCastIdleCleared then
            slot:ClearResourceValues()
            slot._yhudCastIdleCleared = true
        end
        return
    end
    slot._yhudCastIdleCleared = nil
    local raw = state.castDisplayRaw
    if not raw then return end -- A forced source replay supplies transient native sinks after a rebuild.
    slot:SetResourceFillColor(state.castMode == "cast" and slot._yhudResourceStyle.fillColor or state.color)
    local config = slot.gui2ResourceDisplayConfig
    if config then config.durationProgressDirection = raw.channel and "remaining" or "elapsed" end
    if state.castMode == "failed" then
        slot:SetResourceValues(nil, nil, false, 1, 1, nil, nil, nil, nil, nil, nil, nil, true)
        slot.resourceDurationCountdown:Hide()
        slot.resourceValueText:Hide()
    else
        if slot:SetResourceValues(nil, nil, false, 1, 1, nil, nil, nil, nil, nil, raw.duration) ~= true then
            slot:SetAlpha(0)
            slot._yhudCastAlpha = 0
            if YHUD.PlayerBars then
                YHUD.PlayerBars.renderFailed = true
                YHUD.PlayerBars:SyncNativeSuppression(nil)
            end
            return false
        end
        if state.castMode == "empower" then
            slot.resourceDurationCountdown:Hide()
            slot.resourceValueText:SetText(type(state.castStage) == "number" and state.castStage > 0
                and string.format(YHUD:T("player_cast.stage", "%d 阶段"), state.castStage)
                or YHUD:T("player_cast.empower", "蓄力"))
            slot.resourceValueText:SetShown(cast.progress)
        end
    end
    -- Raw name/icon may be secret. Pass them directly to native sinks without caching or comparisons.
    slot.resourceNameText:SetText(raw.name)
    slot.resourceNameText:SetShown(cast.name)
    if slot.icon and slot.icon.icon and state.castMode ~= "failed" then slot.icon.icon:SetTexture(raw.icon) end
    ApplyStageMarkers(slot, state)
end
