local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
local View = YHUD and YHUD.View
local I = View and View._internal
if not I then return end

-- Time resources consume the ordinary spell/timer samples. Public timers are
-- converted once per slot; opaque objects pass straight to the native sink.
function I.UpdateCustomResourceTime(slot, state)
    if not state or state.available == false or not slot.SetResourceValues then return false end
    local duration = state.durationObject
    if not duration and state.durationMode and state.durationMode ~= "none" then
        return true -- Cold replay retains the native timer until a fresh read.
    end
    if not duration and not state.durationMode and state.secret ~= true
        and type(state.startTime) == "number" and type(state.duration) == "number"
        and state.duration > 0 and state.startTime > 0 then
        local object = slot._yhudCustomPublicDuration
        if not object and C_DurationUtil and C_DurationUtil.CreateDuration then
            object = C_DurationUtil.CreateDuration()
            slot._yhudCustomPublicDuration = object
        end
        if object and object.SetTimeFromStart then
            object:SetTimeFromStart(state.startTime, state.duration, 1)
            duration = object
        end
    end
    return slot:SetResourceValues(nil, nil, true, nil, 1, nil, nil, nil, nil, nil, duration)
end

function I.ConfigureResourceProgress(slot, runtime, preset)
    if View.ClearBarProgress then View:ClearBarProgress(slot) end
    if not (preset and preset.progress and View.LayoutBarTicks and slot.track) then return end
    -- Resource cells own their gaps and borders. Generic bar ticks live outside
    -- the resource track and must not survive a switch to independent cells.
    local display = slot.gui2ResourceDisplayConfig
    if display and (display.mode == "cells" or display.mode == "dots") then return end
    slot._yhudBarProgress = preset.progress
    slot._yhudBarMaximum = preset.segmentCountFallback
    View:LayoutBarTicks(slot, runtime, preset.segmentCountFallback)
end
