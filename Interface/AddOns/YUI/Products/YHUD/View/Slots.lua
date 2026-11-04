local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
local View = YHUD and YHUD.View
local I = View and View._internal
if not I then return end

local GUI2 = I.GUI2
local App = I.App
local ResourceCatalog = I.ResourceCatalog
local Glow = I.Glow
local QUESTION_ICON = I.QUESTION_ICON
local DEFAULT_ICON_SIZE = I.DEFAULT_ICON_SIZE
local DEFAULT_SPACING = I.DEFAULT_SPACING
local DEFAULT_MAX_PER_LINE = I.DEFAULT_MAX_PER_LINE
local LAYOUT_VIEWS = I.LAYOUT_VIEWS
local AddMonitorStat = I.AddMonitorStat
local AddViewWrite = I.AddViewWrite
local ProfileNowMS = I.ProfileNowMS
local AddPerformanceStat = I.AddPerformanceStat
local FinishPerformanceStat = I.FinishPerformanceStat
local SafeName = I.SafeName
local GroupName = I.GroupName
local GetIconLayout = I.GetIconLayout
local GetDurationLayout = I.GetDurationLayout
local GetResourceLayout = I.GetResourceLayout
local FormatMonitorName = I.FormatMonitorName
local GetEntryName = I.GetEntryName
local SameGlowAppearance = I.SameGlowAppearance
local CacheGlowAppearance = I.CacheGlowAppearance
local ApplyRuntimeLayout = I.ApplyRuntimeLayout
local Security = YUI.API and YUI.API.Security
local CreateFrame = _G.CreateFrame
local DESIGN_TOOLTIP_DELAY_SECONDS = 0.15
local ICON_COOLDOWN_FRAME_LEVEL_OFFSET = 8
local ICON_CUSTOM_GLOW_FRAME_LEVEL_OFFSET = 9
local ICON_TEXT_FRAME_LEVEL_OFFSET = 10
local ICON_TEXT_DRAW_LAYER = "OVERLAY"
local ICON_TEXT_DRAW_SUBLEVEL = 7
local cooldownOwners = setmetatable({}, { __mode = "kv" })

local function SetFrameLevelIfChanged(frame, level, trustedLevel)
    local frameType = type(frame)
    if not (frameType == "table" or frameType == "userdata")
        or not frame.SetFrameLevel then
        return false
    end
    if trustedLevel ~= true then
        local current = frame.GetFrameLevel and frame:GetFrameLevel() or nil
        if current == level then return false end
    end
    frame:SetFrameLevel(level)
    return true
end

local function SetIconTextDrawLayer(text, trustedLayer)
    local textType = type(text)
    if not (textType == "table" or textType == "userdata")
        or not text.SetDrawLayer then
        return false
    end
    if trustedLayer ~= true then
        local layer, subLevel
        if text.GetDrawLayer then
            layer, subLevel = text:GetDrawLayer()
        end
        if layer == ICON_TEXT_DRAW_LAYER
            and subLevel == ICON_TEXT_DRAW_SUBLEVEL then
            return false
        end
    end
    text:SetDrawLayer(
        ICON_TEXT_DRAW_LAYER,
        ICON_TEXT_DRAW_SUBLEVEL
    )
    return true
end

local function GetCooldownText(cooldown)
    if not (cooldown
        and type(cooldown.GetCountdownFontString) == "function") then
        return nil
    end
    local ok, text = pcall(
        cooldown.GetCountdownFontString,
        cooldown
    )
    return ok and text or nil
end

local function ResolveSlotRuntime(slot, runtime)
    if runtime or not slot then return runtime end
    local groupId = slot._yhudGroupId
    local projection = slot._yhudDesignProjection == true
        and View.designProjection or nil
    return projection and projection.groups and projection.groups[groupId]
        or View.groups and View.groups[groupId]
end

local function EnsureIconTextOverlay(slot, cooldownText)
    if not (slot and cooldownText and GUI2.CreateFrame) then
        return nil, false
    end
    local changed = false
    local previous = slot._yhudCooldownTextRegion
    if previous ~= cooldownText then
        if previous and slot._yhudCooldownTextParent
            and previous.SetParent then
            previous:SetParent(slot._yhudCooldownTextParent)
            changed = true
        end
        slot._yhudCooldownTextRegion = cooldownText
        slot._yhudCooldownTextParent = cooldownText.GetParent
            and cooldownText:GetParent() or nil
    end
    -- Keep native countdown visibility inheritance while raising its draw layer.
    -- A sibling under the icon retains the last glyph after the cooldown hides.
    local parent = slot._yhudCooldownTextParent or slot.cooldown
    if not parent then return nil, changed end
    local overlay = slot._yhudTextOverlay
    if not overlay then
        overlay = GUI2:CreateFrame(parent, {
            allPoints = true,
            mouse = false,
        })
        slot._yhudTextOverlay = overlay
        changed = true
    end
    if overlay and overlay.GetParent and overlay.SetParent
        and overlay:GetParent() ~= parent then
        overlay:SetParent(parent)
        changed = true
    end
    if overlay and cooldownText.GetParent and cooldownText.SetParent
        and cooldownText:GetParent() ~= overlay then
        cooldownText:SetParent(overlay)
        changed = true
    end
    return overlay, changed
end

local function GetNativeProcGlowTarget(slot, runtime)
    if runtime and runtime.view == "bar" then
        if runtime.showIcon == false then return nil end
        return slot.icon and slot.icon.icon and slot.icon or nil
    end
    return slot
end
I.GetNativeProcGlowTarget = GetNativeProcGlowTarget

local function ApplyIconTextLayers(slot, runtime)
    if not slot then return false end
    runtime = ResolveSlotRuntime(slot, runtime)
    local restricted = slot._yhudFilteredAuraGlow == true
        or slot._yhudFilteredAuraChainCompatible == true
        or slot._yhudRestrictedGlowPreview == true
    local level, displayStrata
    if restricted then
        if View.GetMonitorDisplayLayer then
            level, displayStrata = View:GetMonitorDisplayLayer(
                runtime,
                slot._yhudMonitorId
            )
        end
        level = level or runtime and runtime.displayLayerBase or 0
    else
        level = slot.GetFrameLevel and slot:GetFrameLevel() or 0
        displayStrata = runtime and runtime.displayLayerStrata
            or slot.GetFrameStrata and slot:GetFrameStrata() or nil
    end
    local textLevel, textStrata
    if View.GetMonitorTextLayer then
        textLevel, textStrata = View:GetMonitorTextLayer(runtime)
    end
    textLevel = textLevel or level + ICON_TEXT_FRAME_LEVEL_OFFSET
    local changed = false
    local glowLevel = level + ICON_CUSTOM_GLOW_FRAME_LEVEL_OFFSET
    local displayWidth = runtime
        and (runtime.itemWidth or runtime.iconWidth
            or runtime.diameter or runtime.iconSize) or nil
    local displayHeight = runtime
        and (runtime.itemHeight or runtime.iconHeight
            or runtime.diameter or runtime.iconSize) or nil
    local targetShape = runtime and runtime.view == "ring"
        and "circle"
        or runtime and runtime.shape or "square"
    local trustedWidth = restricted and displayWidth or nil
    local trustedHeight = restricted and displayHeight or nil
    if slot.gui2Glow and slot.gui2Glow._SetGlowLayoutContext then
        changed = slot.gui2Glow:_SetGlowLayoutContext(
            restricted,
            trustedWidth,
            trustedHeight
        ) or changed
    end
    if slot.gui2Glow and slot.gui2Glow._SetGlowLayerContext then
        changed = slot.gui2Glow:_SetGlowLayerContext(
            glowLevel,
            displayStrata
        ) or changed
    end
    local procTarget = GetNativeProcGlowTarget(slot, runtime)
    if slot._yhudNativeProcGlow and not procTarget
        and slot._yhudNativeProcGlowShown == true
        and GUI2.SetManagedProcGlowShown then
        GUI2:SetManagedProcGlowShown(slot._yhudNativeProcGlow, false)
        slot._yhudNativeProcGlowShown = false
        changed = true
    end
    if slot._yhudNativeProcGlow and procTarget and GUI2.LayoutManagedProcGlow
        and (slot._yhudNativeProcGlowFrameLevel ~= glowLevel
            or slot._yhudNativeProcGlowFrameStrata ~= displayStrata
            or slot._yhudNativeProcGlowTarget ~= procTarget) then
        local procWidth = procTarget ~= slot and runtime.iconSize or displayWidth
        local procHeight = procTarget ~= slot and runtime.iconSize or displayHeight
        GUI2:LayoutManagedProcGlow(
            slot._yhudNativeProcGlow,
            procTarget,
            procWidth,
            procHeight,
            glowLevel,
            displayStrata,
            targetShape
        )
        slot._yhudNativeProcGlowFrameLevel = glowLevel
        slot._yhudNativeProcGlowFrameStrata = displayStrata
        slot._yhudNativeProcGlowTarget = procTarget
        changed = true
    end
    local cooldown = slot.cooldown
    changed = SetFrameLevelIfChanged(
        cooldown,
        level + ICON_COOLDOWN_FRAME_LEVEL_OFFSET,
        restricted
    ) or changed
    local cooldownText = GetCooldownText(cooldown)
    local textOverlay, overlayChanged =
        EnsureIconTextOverlay(slot, cooldownText)
    changed = overlayChanged or changed
    if textOverlay and textStrata and textOverlay.SetFrameStrata then
        local current
        if not restricted then
            current = textOverlay.GetFrameStrata
                and textOverlay:GetFrameStrata() or nil
        end
        if restricted or current ~= textStrata then
            textOverlay:SetFrameStrata(textStrata)
            changed = true
        end
    end
    changed = SetFrameLevelIfChanged(
        textOverlay,
        textLevel,
        restricted
    ) or changed
    changed = SetIconTextDrawLayer(cooldownText, restricted) or changed

    local count = slot.count
    local countCarrier = slot.countOverlay
    local countType = type(count)
    if not countCarrier
        and (countType == "table" or countType == "userdata")
        and count.GetParent then
        countCarrier = count:GetParent()
    end
    if countCarrier and countCarrier ~= slot then
        changed = SetFrameLevelIfChanged(
            countCarrier,
            textLevel,
            restricted
        ) or changed
    end
    changed = SetIconTextDrawLayer(count, restricted) or changed

    changed = SetFrameLevelIfChanged(
        slot._yhudKeybindOverlay,
        textLevel,
        restricted
    ) or changed
    changed = SetIconTextDrawLayer(
        slot._yhudKeybindText,
        restricted
    ) or changed
    changed = SetFrameLevelIfChanged(
        slot._yhudIconLabelOverlay,
        textLevel,
        restricted
    ) or changed
    changed = SetIconTextDrawLayer(
        slot._yhudIconLabelText,
        restricted
    ) or changed
    return changed
end

local function OnCooldownDone(cooldown)
    if View.preview then return end
    local slot = cooldown and cooldownOwners[cooldown]
    if not (slot and slot._yhudCooldownRefreshArmed == true) then return end
    -- Independent designer samples must not stop the live skill timer below.
    if slot._yhudDesignProjection == true
        or View.designMode and (not View.designProjection or slot._yhudView == "icon") then
        return
    end
    local monitorId = slot._yhudMonitorId
    local monitor = monitorId and View.desiredMonitors[monitorId]
    local entry = monitor and View.profile and View.profile.entries
        and View.profile.entries[monitor.entryKey]
    if slot._yhudView ~= "icon" then
        if not YHUD:CanUseSkillDurationSource(entry, monitor)
            or (slot._yhudBarProgress and slot._yhudBarProgress.source ~= "time") then
            return
        end
    end
    slot._yhudCooldownRefreshArmed = false
    if slot._yhudView == "icon" and slot._yhudCompletionFlashEnabled
        and slot._yhudCooldownFlashEligible == true then
        GUI2:PlayIconCooldownFlash(slot._yhudCompletionFlash)
    end
    slot._yhudCooldownFlashEligible = false
    slot._yhudDurationMode = nil
    slot._yhudOpaqueRevision = nil
    slot._yhudStart = nil
    slot._yhudDuration = nil
    if slot.ClearDuration then
        slot:ClearDuration()
    elseif slot.SetCooldownDurationObject then
        slot:SetCooldownDurationObject(nil)
    elseif slot.SetCooldown then
        slot:SetCooldown(0, 0)
    end
    local sourceKey = YHUD:GetMonitorRuntimeSourceKey(entry, monitor)
    local Monitor = YUI.Monitor
    if not (sourceKey and Monitor and Monitor.QueueSource) then return end
    Monitor:QueueSource(sourceKey, "cooldown-done")
end

local function InstallCooldownDoneHook(slot)
    if not slot or slot._yhudCooldownDoneHooked == true then return false end
    -- Duration views put their native countdown under a text overlay.
    -- Its parent is not the owning slot, including when numbers are hidden.
    local cooldown = slot.countdown or slot.cooldown
    if not (cooldown and type(cooldown.HookScript) == "function") then
        return false
    end
    local ok = pcall(
        cooldown.HookScript,
        cooldown,
        "OnCooldownDone",
        OnCooldownDone
    )
    if ok then
        cooldownOwners[cooldown] = slot
        slot._yhudCooldownDoneHooked = true
    end
    return ok == true
end

local function GetSlotTooltip()
    if type(_G.GetAppropriateTooltip) == "function" then
        local ok, tooltip = pcall(_G.GetAppropriateTooltip)
        if ok and tooltip then return tooltip end
    end
    return _G.GameTooltip
end

local function GetSlotTooltipOwner(slot)
    if slot and (slot._yhudFilteredAuraGlow == true
            or slot._yhudFilteredAuraChainCompatible == true)
        and _G.UIParent then
        return _G.UIParent
    end
    return slot
end

local function TooltipNow()
    return type(_G.GetTime) == "function" and _G.GetTime() or 0
end

local function IsSecretTooltipValue(value)
    local checker = Security and Security.IsSecretValue
        or _G.issecretvalue
    if type(checker) ~= "function" then return false end
    local ok, secret = pcall(checker, value)
    return not ok or secret == true
end

local function SafeTooltipPositiveInteger(value)
    if IsSecretTooltipValue(value) then return nil end

    local numberValue
    if Security and type(Security.SafeNumber) == "function" then
        local ok
        ok, numberValue = pcall(Security.SafeNumber, value)
        if not ok then return nil end
    else
        local valueType = type(value)
        if valueType ~= "number" and valueType ~= "string" then return nil end
        local ok
        ok, numberValue = pcall(tonumber, value)
        if not ok then return nil end
    end

    if IsSecretTooltipValue(numberValue)
        or type(numberValue) ~= "number"
        or numberValue ~= numberValue
        or numberValue <= 0
        or numberValue >= math.huge
        or numberValue % 1 ~= 0 then
        return nil
    end
    return numberValue
end

local function FirstSafeTooltipPositiveInteger(...)
    for index = 1, select("#", ...) do
        local value = SafeTooltipPositiveInteger(select(index, ...))
        if value then return value end
    end
    return nil
end

local function CallTooltipSetter(setter, tooltip, ...)
    local ok, result = pcall(setter, tooltip, ...)
    if not ok or IsSecretTooltipValue(result) then return false end
    return result ~= false
end

local function HideSlotTooltip(slot)
    if not (slot and slot._yhudTooltipShown == true) then return false end
    slot._yhudTooltipShown = nil
    local tooltip = GetSlotTooltip()
    if not tooltip then return false end
    if tooltip == _G.GameTooltip and YUI.HideGameTooltip then
        YUI.HideGameTooltip()
    else
        tooltip:Hide()
    end
    return true
end

local function ShowSlotTooltip(slot, delayed)
    if not (slot and slot._yhudTooltipEnabled == true) then return end
    if delayed == true then
        if View.active ~= true or View.designMode ~= true
            or slot._yhudTooltipHovered ~= true
            or (slot.IsShown and slot:IsShown() ~= true) then
            return false
        end
    end
    local startedAt = delayed == true and ProfileNowMS() or nil
    local tooltip = GetSlotTooltip()
    if not tooltip then return false end
    local owner = GetSlotTooltipOwner(slot)
    if type(_G.GameTooltip_SetDefaultAnchor) == "function" then
        _G.GameTooltip_SetDefaultAnchor(tooltip, owner)
    else
        tooltip:SetOwner(owner, "ANCHOR_RIGHT")
    end
    local shown = false
    if slot._yhudTooltipSlotID and tooltip.SetInventoryItem then
        shown = CallTooltipSetter(
            tooltip.SetInventoryItem,
            tooltip,
            "player",
            slot._yhudTooltipSlotID
        )
    elseif slot._yhudTooltipItemID and tooltip.SetItemByID then
        shown = CallTooltipSetter(
            tooltip.SetItemByID,
            tooltip,
            slot._yhudTooltipItemID
        )
    elseif slot._yhudTooltipSpellID and tooltip.SetSpellByID then
        shown = CallTooltipSetter(
            tooltip.SetSpellByID,
            tooltip,
            slot._yhudTooltipSpellID
        )
    end
    if not shown then
        tooltip:SetText(slot._yhudTooltipName or "-", 1, 1, 1, 1, true)
    end
    tooltip:Show()
    slot._yhudTooltipShown = true
    if delayed == true then
        AddPerformanceStat("designTooltipShows")
        FinishPerformanceStat("designTooltipMS", startedAt)
    end
    return true
end

local ScheduleDesignTooltipTimer

local function RunDesignTooltipTimer(timer, generation)
    if View.designTooltipTimer ~= timer
        or View.designTooltipGeneration ~= generation then
        return
    end
    View.designTooltipTimer = nil

    local slot = View.designTooltipPendingSlot
    local deadline = View.designTooltipDeadline
    if not (slot and deadline and View.designMode == true
        and slot._yhudTooltipHovered == true
        and slot._yhudTooltipEnabled == true
        and (not slot.IsShown or slot:IsShown() == true)) then
        View.designTooltipPendingSlot = nil
        View.designTooltipDeadline = nil
        return
    end

    local remaining = deadline - TooltipNow()
    if remaining > 0 then
        AddPerformanceStat("designTooltipRenewals")
        if not ScheduleDesignTooltipTimer(remaining) then
            View.designTooltipPendingSlot = nil
            View.designTooltipDeadline = nil
        end
        return
    end

    View.designTooltipPendingSlot = nil
    View.designTooltipDeadline = nil
    ShowSlotTooltip(slot, true)
end

ScheduleDesignTooltipTimer = function(delay)
    local timerAPI = _G.C_Timer
    if not (timerAPI and type(timerAPI.NewTimer) == "function") then
        return false
    end
    local generation = View.designTooltipGeneration
    local timer
    timer = timerAPI.NewTimer(math.max(0, delay or 0), function()
        RunDesignTooltipTimer(timer, generation)
    end)
    if not timer then return false end
    View.designTooltipTimer = timer
    return true
end

function I.CancelDesignTooltip(slot)
    if slot then
        slot._yhudTooltipHovered = nil
        HideSlotTooltip(slot)
        if View.designTooltipPendingSlot ~= slot then return false end
    elseif View.designTooltipPendingSlot then
        View.designTooltipPendingSlot._yhudTooltipHovered = nil
    end

    local timer = View.designTooltipTimer
    View.designTooltipGeneration = View.designTooltipGeneration + 1
    View.designTooltipTimer = nil
    View.designTooltipPendingSlot = nil
    View.designTooltipDeadline = nil
    if timer and timer.Cancel then
        timer:Cancel()
        AddPerformanceStat("designTooltipCancels")
    end
    return timer ~= nil
end

local function SlotTooltipOnEnter(slot)
    if not (slot and slot._yhudTooltipEnabled == true) then return end
    slot._yhudTooltipHovered = true
    if View.designMode == true then
        AddPerformanceStat("designTooltipRequests")
        View.designTooltipPendingSlot = slot
        View.designTooltipDeadline = TooltipNow()
            + DESIGN_TOOLTIP_DELAY_SECONDS
        if not View.designTooltipTimer
            and not ScheduleDesignTooltipTimer(
                DESIGN_TOOLTIP_DELAY_SECONDS
            ) then
            View.designTooltipPendingSlot = nil
            View.designTooltipDeadline = nil
        end
        return
    end
    ShowSlotTooltip(slot, false)
end

local function SlotTooltipOnLeave(slot)
    if not slot then return end
    slot._yhudTooltipHovered = nil
    if View.designTooltipPendingSlot == slot then
        View.designTooltipPendingSlot = nil
        View.designTooltipDeadline = nil
    end
    HideSlotTooltip(slot)
end

local function SlotTooltipOnHide(slot)
    I.CancelDesignTooltip(slot)
end

function I.SetSlotMouseInput(slot, tooltipEnabled, designMode)
    if not slot then return false end
    tooltipEnabled = tooltipEnabled == true
    designMode = designMode == true
    local motionEnabled = tooltipEnabled or designMode
    if slot.EnableMouse then slot:EnableMouse(motionEnabled) end
    if slot.SetMouseClickEnabled then
        slot:SetMouseClickEnabled(designMode)
    end
    if slot.SetMouseMotionEnabled then
        slot:SetMouseMotionEnabled(motionEnabled)
    end
    return true
end

local function ConfigureSlotTooltip(slot, runtime, monitor, entry, designMode)
    if not slot then return end
    if not slot._yhudNativeAuraTooltip
        and not slot._yhudTooltipHooked and slot.HookScript then
        slot._yhudTooltipHooked = true
        slot:HookScript("OnEnter", SlotTooltipOnEnter)
        slot:HookScript("OnLeave", SlotTooltipOnLeave)
        slot:HookScript("OnHide", SlotTooltipOnHide)
    end
    local enabled = runtime and runtime.showTooltip ~= false
        and runtime.view ~= "resource"
        and slot._yhudNativeAuraTooltip ~= true
    slot._yhudTooltipEnabled = enabled
    local spellID = monitor and SafeTooltipPositiveInteger(
        monitor._yhudBundleSpellID
    ) or nil
    if not spellID and entry then
        spellID = FirstSafeTooltipPositiveInteger(
            entry.overrideTooltipSpellId,
            entry.overrideTooltipSpellID,
            entry.runtimeSpellId,
            entry.overrideSpellId,
            entry.overrideSpellID,
            entry.spellId,
            entry.spellID
        )
    end
    slot._yhudTooltipSpellID = spellID
    slot._yhudTooltipItemID = entry and FirstSafeTooltipPositiveInteger(
        entry.itemId,
        entry.itemID
    ) or nil
    slot._yhudTooltipSlotID = entry and FirstSafeTooltipPositiveInteger(
        entry.slotId,
        entry.slotID
    ) or nil
    slot._yhudTooltipName = monitor and monitor._yhudDisplayName
        or GetEntryName(entry)
    if not enabled then I.CancelDesignTooltip(slot) end
    I.SetSlotMouseInput(slot, enabled, designMode)
end

local function SetSlotIcon(slot, texture)
    if slot.SetDurationIcon then
        slot:SetDurationIcon(texture)
    elseif slot.SetIcon then
        slot:SetIcon(texture)
    end
end

local function ClearSlotDuration(slot)
    slot._yhudBarPublicValue, slot._yhudBarValueValid = nil, nil
    slot._yhudBarCountdownMode, slot._yhudBarCountdownRevision = nil, nil
    if YHUD.ClassExtra then YHUD.ClassExtra:ClearClock(slot) end
    slot._yhudCooldownRefreshArmed = false
    slot._yhudCooldownFlashEligible = false
    if slot._yhudCompletionFlash then slot._yhudCompletionFlash:Stop() end
    if slot.ClearResourceValues then
        slot:ClearResourceValues()
    elseif slot.ClearDuration then
        slot:ClearDuration()
    else
        if slot.SetCooldownDurationObject then
            slot:SetCooldownDurationObject(nil)
        end
        if slot.SetCooldown then slot:SetCooldown(0, 0) end
    end
end

local function GetSlotIconTexture(slot)
    local iconSlot = slot and slot.icon
    return iconSlot and iconSlot.icon or iconSlot
end

local function ApplySharedCountStyle(slot, runtime)
    local iconStyle = runtime and runtime.iconStyle
    if not (slot and iconStyle and iconStyle.countText) then return end
    if slot.durationCountText then return end
    local iconSlot = slot.icon and slot.icon.icon and slot.icon or slot
    local count = iconSlot.count or slot.count
    if not count then return end
    slot._yhudSharedCountState = slot._yhudSharedCountState or {}
    GUI2:ApplyTextStyle(
        count,
        iconStyle.countText,
        slot._yhudSharedCountState
    )
end

local function EnsureKeybindText(slot, runtime)
    if slot._yhudKeybindText then return slot._yhudKeybindText end
    if not (GUI2.CreateFrame and GUI2.CreateText) then return nil end
    runtime = ResolveSlotRuntime(slot, runtime)
    local restricted = slot._yhudFilteredAuraGlow == true
    local level
    if restricted then
        level = View.GetMonitorDisplayLayer
            and View:GetMonitorDisplayLayer(
                runtime,
                slot._yhudMonitorId
            ) or nil
        level = level or runtime and runtime.displayLayerBase or 0
    else
        level = slot.GetFrameLevel and slot:GetFrameLevel() or 0
    end
    local overlay = GUI2:CreateFrame(slot, {
        allPoints = true,
        mouse = false,
        frameLevel = level + 10,
    })
    local text = GUI2:CreateText(overlay, "", 12, nil, "RIGHT")
    overlay:Hide()
    slot._yhudKeybindOverlay = overlay
    slot._yhudKeybindText = text
    slot._yhudKeybindTextState = {}
    slot._yhudKeybindTextValue = ""
    ApplyIconTextLayers(slot, runtime)
    if GUI2.RefreshIconSkinRegion then GUI2:RefreshIconSkinRegion(slot, "HotKey", text) end
    return text
end

function View:ApplyKeybindText(slot, runtime, monitor, entry, state)
    local service = YHUD.KeybindText
    local text
    if runtime and runtime.view == "icon" and service and service.Resolve then
        text = service:Resolve(runtime, monitor, entry, nil, state)
    end
    if not text and not slot._yhudKeybindText then return 0 end
    local target = EnsureKeybindText(slot, runtime)
    if not target then return 0 end
    local writes = 0
    local value = text or ""
    if slot._yhudKeybindTextValue ~= value then
        target:SetText(value)
        slot._yhudKeybindTextValue = value
        writes = writes + 1
    end
    runtime = runtime or {}
    local snapshot = runtime._keybindTextSnapshot
    if not snapshot then
        snapshot = {}
        runtime._keybindTextSnapshot = snapshot
    end
    snapshot.enabled = text ~= nil
    snapshot.font = runtime.keybindTextFont
    snapshot.size = runtime.keybindTextSize
    snapshot.outline = runtime.keybindTextOutline
    snapshot.monochrome = runtime.keybindTextMonochrome
    snapshot.position = runtime.keybindTextPosition
    snapshot.offsetX = runtime.keybindTextOffsetX
    snapshot.offsetY = runtime.keybindTextOffsetY
    snapshot.color = runtime.keybindTextColor
    writes = writes + GUI2:ApplyTextStyle(
        target,
        snapshot,
        slot._yhudKeybindTextState
    )
    if ApplyIconTextLayers(slot, runtime) then writes = writes + 1 end
    local overlay = slot._yhudKeybindOverlay
    local shown = text ~= nil
    if slot._yhudKeybindOverlayShown ~= shown then
        if shown then overlay:Show() else overlay:Hide() end
        slot._yhudKeybindOverlayShown = shown
        writes = writes + 1
    end
    return writes
end

local function EnsureIconLabelText(slot)
    if slot._yhudIconLabelText then return slot._yhudIconLabelText end
    if not (GUI2.CreateFrame and GUI2.CreateText) then return nil end
    local overlay = GUI2:CreateFrame(slot, {
        allPoints = true,
        mouse = false,
    })
    local text = GUI2:CreateText(overlay, "", 11, nil, "CENTER")
    slot._yhudIconLabelOverlay = overlay
    slot._yhudIconLabelText = text
    slot._yhudIconLabelTextState = {}
    slot._yhudIconLabelTextValue = ""
    return text
end

function View:ApplyIconLabel(slot, runtime, entry)
    local value
    if runtime and runtime.view == "icon" and YHUD.GetEntryPresetLabel then
        value = YHUD:GetEntryPresetLabel(entry)
    end
    if not value and not slot._yhudIconLabelText then return 0 end
    local target = EnsureIconLabelText(slot)
    if not target then return 0 end
    local writes = 0
    value = value or ""
    if slot._yhudIconLabelTextValue ~= value then
        target:SetText(value)
        slot._yhudIconLabelTextValue = value
        writes = writes + 1
    end
    writes = writes + GUI2:ApplyTextStyle(
        target,
        {
            enabled = value ~= "",
            size = 11,
            outline = "outline",
            position = "bottom",
            offsetY = 2,
        },
        slot._yhudIconLabelTextState
    )
    if ApplyIconTextLayers(slot, runtime) then writes = writes + 1 end
    return writes
end

function View:RefreshKeybindTexts()
    local visited, writes = 0, 0
    for monitorId, slot in pairs(self.byMonitor or {}) do
        local runtime = self.groups and self.groups[slot._yhudGroupId]
        if runtime and runtime.view == "icon" then
            visited = visited + 1
            local monitor = self.desiredMonitors
                and self.desiredMonitors[monitorId]
            local entry = monitor and self.profile and self.profile.entries
                and self.profile.entries[monitor.entryKey]
            writes = writes + self:ApplyKeybindText(
                slot, runtime, monitor, entry
            )
        end
    end
    return visited, writes
end

local function ApplySharedIconStyle(slot, runtime, preserveDurationSwipe)
    if not (slot and runtime and runtime.iconStyle) then return end
    local target = slot._yhudSharedIconTarget
    if not target then
        target = {}
        slot._yhudSharedIconTarget = target
        slot._yhudSharedIconState = {}
        slot._yhudSharedCooldownState = {}
    end
    local iconSlot = slot.icon and slot.icon.icon and slot.icon or slot
    target.owner = iconSlot
    target.icon = iconSlot.icon or slot.icon
    target.background = iconSlot.background
    target.border = nil
    target.shapeBorder = iconSlot.gui2IconAppearanceBorder
    target.pixelBorder = iconSlot.gui2Borders
    target.mask = iconSlot.gui2IconAppearanceMask
    if iconSlot.SetIconBorderColor then
        iconSlot:SetIconBorderColor(runtime.iconStyle.borderColor)
    end
    -- SetIconAppearance/SetSelected 属于同一冷配置链路，并会先把边框恢复为
    -- GUI2 主题色。共享绘制缓存不能据此跳过业务颜色的重新写入。
    local state = slot._yhudSharedIconState
    state.borderColor = nil
    state.borderShown = nil
    state.iconBorderThickness = nil
    state.mask = nil
    state.maskShown = nil
    GUI2:ApplyIconChrome(
        target,
        runtime.iconStyle,
        state
    )
    local cooldown = iconSlot.cooldown or slot.cooldown
    if cooldown and preserveDurationSwipe ~= true then
        GUI2:ApplyCooldownChrome(
            cooldown,
            runtime.iconStyle,
            slot._yhudSharedCooldownState
        )
    end
    ApplySharedCountStyle(slot, runtime)
end

local function PrepareChargeRecoveryCurves(runtime, skinAlpha)
    local curveUtil, enum = _G.C_CurveUtil, _G.Enum
    local color = runtime.iconStyle and runtime.iconStyle.swipeColor
    if not (curveUtil and curveUtil.CreateCurve and enum and enum.LuaCurveType and color) then return end
    local alpha = skinAlpha or color[4]
    if runtime.chargeRecoveryCurveAlpha == alpha then return end
    local swipe = curveUtil.CreateCurve()
    swipe:SetType(enum.LuaCurveType.Step)
    swipe:AddPoint(0, 0)
    swipe:AddPoint(0.000001, alpha or 0.7)
    runtime.chargeRecoverySwipeCurve = swipe
    local text = curveUtil.CreateCurve()
    text:SetType(enum.LuaCurveType.Step)
    text:AddPoint(0, 0)
    text:AddPoint(0.000001, 1)
    runtime.chargeRecoveryTextCurve = text
    local edge = curveUtil.CreateCurve()
    edge:SetType(enum.LuaCurveType.Step)
    edge:AddPoint(0, 1)
    edge:AddPoint(0.000001, 0)
    runtime.chargeRecoveryEdgeCurve = edge
    runtime.chargeRecoveryCurveAlpha = alpha
end

function View:RefreshIconSkinCooldown(slot, runtime)
    local iconSlot = slot.icon and slot.icon.icon and slot.icon or slot
    local cooldown = iconSlot.cooldown or slot.cooldown
    local alpha = cooldown and GUI2.GetIconSkinSwipeAlpha and GUI2:GetIconSkinSwipeAlpha(cooldown)
    PrepareChargeRecoveryCurves(runtime, alpha)
    if slot._yhudSharedCooldownState then slot._yhudSharedCooldownState.chargeRecoveryRuntime = nil end
end

local function ApplyRecoverySwipeColor(cooldown, color, alpha)
    if GUI2.ApplyIconSkinSwipeAlpha and GUI2:ApplyIconSkinSwipeAlpha(cooldown, alpha) then return end
    cooldown:SetSwipeColor(color[1], color[2], color[3], alpha)
end

local SKIN_EDGE_COLOR = { 1, 1, 1, 1 }

local function ApplyChargeRecoveryPresentation(slot, cooldown, runtime, state)
    local cache = slot._yhudSharedCooldownState
    local mode = runtime.chargeRecoveryDisplay or "hideSwipeOnly"
    local recovering = state and state.sourceKind == "spell"
        and state.durationMode == "charge" and state.hasCharges == true
    local hideSwipe = recovering and (mode == "hideSwipe" or mode == "hideBoth"
        or mode == "hideSwipeOnly" or mode == "hideSwipeAndCountdown")
    local hideText = recovering and (mode == "hideCountdown" or mode == "hideBoth"
        or mode == "hideEdgeAndCountdown" or mode == "hideSwipeAndCountdown")
    local showEdge = recovering and (mode == "normal" or mode == "hideCountdown"
        or mode == "hideSwipeOnly" or mode == "hideSwipeAndCountdown")
    if not (hideSwipe or hideText or showEdge or cache.chargeRecoveryEdgeApplied
        or cache.chargeRecoverySwipeApplied or cache.chargeRecoveryTextApplied) then
        return 0
    end
    local color = runtime.iconStyle and runtime.iconStyle.swipeColor
    if not color then return 0 end
    local text = (hideText or cache.chargeRecoveryTextApplied)
        and cooldown.GetCountdownFontString and cooldown:GetCountdownFontString() or nil
    if cache.chargeRecoveryRuntime == runtime and cache.chargeRecoveryMode == mode
        and cache.chargeRecoveryRevision == (state and state.opaqueRevision)
        and cache.chargeRecoverySpell == (state and state.spellID)
        and cache.chargeRecoveryActive == recovering and cache.chargeRecoveryText == text then
        return 0
    end
    local duration
    local hidden = false
    if hideSwipe or hideText or showEdge then
        local count = state.currentCharges
        if not (Security and Security.IsSecretValue and Security.IsSecretValue(count))
            and type(count) == "number" then
            hidden = count > 0 and state.cooldownActive ~= true
        else
            local spell = YUI.API and YUI.API.Spell
            if runtime.chargeRecoverySwipeCurve and spell and spell.GetCooldownDurationObject then
                duration = spell.GetCooldownDurationObject(state.spellID, true)
            end
        end
    end
    local samePublic = duration == nil and cache.chargeRecoveryOpaque ~= true
        and cache.chargeRecoveryRuntime == runtime and cache.chargeRecoveryMode == mode
        and cache.chargeRecoveryActive == recovering and cache.chargeRecoveryText == text
        and cache.chargeRecoveryHidden == hidden
    local writes = 0
    if not samePublic and cooldown.SetSwipeColor and (hideSwipe or cache.chargeRecoverySwipeApplied) then
        -- The result goes straight to a native sink; never inspect or cache it.
        if hideSwipe and duration then
            ApplyRecoverySwipeColor(cooldown, color, duration:EvaluateRemainingDuration(runtime.chargeRecoverySwipeCurve, 0))
        else
            local alpha = GUI2.GetIconSkinSwipeAlpha and GUI2:GetIconSkinSwipeAlpha(cooldown) or color[4]
            ApplyRecoverySwipeColor(cooldown, color, hideSwipe and hidden and 0 or alpha)
        end
        writes = writes + 1
    end
    if not samePublic and text and text.SetAlpha and (hideText or cache.chargeRecoveryTextApplied) then
        if hideText and duration then
            text:SetAlpha(duration:EvaluateRemainingDuration(runtime.chargeRecoveryTextCurve, 0))
        else
            text:SetAlpha(hideText and hidden and 0 or 1)
        end
        writes = writes + 1
    end
    if not samePublic and (showEdge or cache.chargeRecoveryEdgeApplied) then
        local drawEdge = showEdge == true and (hidden or duration ~= nil)
        if cooldown.SetDrawEdge and cache.drawEdge ~= drawEdge then
            cooldown:SetDrawEdge(drawEdge)
            cache.drawEdge = drawEdge
            writes = writes + 1
        end
        if cooldown.SetEdgeColor then
            local edgeColor = GUI2.IsIconSkinManaged and GUI2:IsIconSkinManaged(cooldown)
                and SKIN_EDGE_COLOR or GUI2:GetCooldownEdgeStyle(runtime.iconStyle).color
            if showEdge and duration and runtime.chargeRecoveryEdgeCurve then
                cooldown:SetEdgeColor(edgeColor[1], edgeColor[2], edgeColor[3], duration:EvaluateRemainingDuration(runtime.chargeRecoveryEdgeCurve, 0))
            else
                cooldown:SetEdgeColor(edgeColor[1], edgeColor[2], edgeColor[3], 1)
            end
            writes = writes + 1
        end
    end
    cache.chargeRecoveryRuntime, cache.chargeRecoveryMode = runtime, mode
    cache.chargeRecoveryRevision = state and state.opaqueRevision
    cache.chargeRecoverySpell = state and state.spellID
    cache.chargeRecoveryActive, cache.chargeRecoveryText = recovering, hideText and text or nil
    cache.chargeRecoverySwipeApplied, cache.chargeRecoveryTextApplied = hideSwipe, hideText
    cache.chargeRecoveryEdgeApplied = showEdge
    cache.chargeRecoveryHidden, cache.chargeRecoveryOpaque = hidden, duration ~= nil
    return writes
end

local function ConfigureIconCompletionFlash(slot, runtime)
    -- Cold configuration only. Reuse the pooled slot's optional flash, and let
    -- its existing native OnCooldownDone event trigger playback (no time reads).
    local flash = slot._yhudCompletionFlash
    if runtime.cooldownBling == true and not flash and GUI2.CreateIconCooldownFlash then
        flash = GUI2:CreateIconCooldownFlash(slot)
        slot._yhudCompletionFlash = flash
    end
    slot._yhudCompletionFlashEnabled = runtime.cooldownBling == true and flash ~= nil
    if flash then
        flash:Stop()
        if slot._yhudCompletionFlashEnabled then
            GUI2:LayoutIconCooldownFlash(flash, slot.cooldown, runtime.iconStyle,
                runtime.iconWidth, runtime.iconHeight, slot:GetFrameLevel() + ICON_CUSTOM_GLOW_FRAME_LEVEL_OFFSET)
        end
    end
end

function View:ApplyIconCooldownPresentation(slot, runtime, entry, state)
    if not (slot and runtime and runtime.view == "icon"
        and GUI2.ApplyCooldownSwipe) then
        return false
    end
    local iconSlot = slot.icon and slot.icon.icon and slot.icon or slot
    local cooldown = iconSlot.cooldown or slot.cooldown
    if not cooldown then return false end
    local drawSwipe = slot._yhudCooldownSwipeDraw
    local reverse = slot._yhudCooldownSwipeReverse
    if drawSwipe == nil or reverse == nil then
        drawSwipe, reverse = YHUD:ResolveMonitorCooldownSwipe(
            nil,
            runtime.cooldownSwipe,
            YHUD:GetEntrySemantic(entry) == "buff"
        )
    end
    slot._yhudSharedCooldownState = slot._yhudSharedCooldownState or {}
    local writes = GUI2:ApplyCooldownSwipe(
        cooldown,
        drawSwipe,
        reverse,
        slot._yhudSharedCooldownState
    )
    writes = writes + ApplyChargeRecoveryPresentation(slot, cooldown, runtime, state)
    local drawBling = runtime.cooldownBling == true
        and slot._yhudDurationMode ~= "gcd"
        and not slot._yhudCompletionFlashEnabled
    if cooldown.SetDrawBling
        and slot._yhudSharedCooldownState.drawBling ~= drawBling then
        cooldown:SetDrawBling(drawBling)
        slot._yhudSharedCooldownState.drawBling = drawBling
        writes = writes + 1
    end
    if writes > 0 then AddViewWrite(false) end
    return writes > 0
end

local function HideStatusBarEdges(edges)
    if not edges then return end
    local top = edges.top
    local bottom = edges.bottom
    local left = edges.left
    local right = edges.right
    if top and top.Hide then top:Hide() end
    if bottom and bottom.Hide then bottom:Hide() end
    if left and left.Hide then left:Hide() end
    if right and right.Hide then right:Hide() end
end

local function ApplySharedStatusBarStyle(slot, runtime, resource)
    local snapshot = runtime and runtime.statusBarStyle
    if not (slot and snapshot) then return end
    local target = slot._yhudSharedStatusTarget
    if not target then
        target = {}
        slot._yhudSharedStatusTarget = target
        slot._yhudSharedStatusState = {}
    end
    local statusBar = resource
        and slot.resourceStatusBar or slot.durationStatusBar
    target.statusBar = statusBar
        and statusBar.gui2ProjectedVisibleStatusBar or statusBar
    target.owner = slot.track
    target.track = slot.track
    target.orientation = resource
        and slot.gui2ResourceOrientation or slot.orientation
    target.fillDirection = resource
        and slot.gui2ResourceFillDirection
        or (slot.gui2DurationReverse and "reverse" or "forward")
    local displayConfig = resource and slot.gui2ResourceDisplayConfig
    local cellsMode = resource and displayConfig
        and (displayConfig.mode == "cells" or displayConfig.mode == "dots")
    if cellsMode then
        slot.gui2UseStatusBarBorder = true
        target.border = nil
        HideStatusBarEdges(slot.resourceBorderEdges)
        HideStatusBarEdges(slot.track and slot.track.gui2Borders)
        local state = slot._yhudSharedStatusState
        state.statusBorderColor = nil
        state.statusBorderShown = nil
        state.statusBorderThickness = nil
        return
    end
    if resource and slot.resourceBorderEdges then
        slot.gui2UseStatusBarBorder = true
        target.border = slot.resourceBorderEdges
    elseif not resource and slot.durationBorderOverlay then
        slot.gui2UseStatusBarBorder = true
        target.border = GUI2.EnsureStatusBarBorder
            and GUI2:EnsureStatusBarBorder(slot.durationBorderOverlay)
    else
        target.border = GUI2.UseStatusBarBorder
            and GUI2:UseStatusBarBorder(slot, target.statusBar)
            or (GUI2.EnsureStatusBarBorder
                and GUI2:EnsureStatusBarBorder(target.statusBar))
            or (slot.track and slot.track.gui2Borders)
    end
    local trackBorders = slot.track and slot.track.gui2Borders
    if target.border ~= trackBorders and trackBorders then
        HideStatusBarEdges(trackBorders)
    end
    local state = slot._yhudSharedStatusState
    state.statusBorderColor = nil
    state.statusBorderShown = nil
    state.statusBorderThickness = nil
    GUI2:ApplyStatusBarChrome(
        target,
        snapshot,
        state
    )
end

local function PreviewColorComponents(color)
    if type(color) == "string" then
        return GUI2:GetColor(color)
    end
    color = type(color) == "table" and color or {}
    return color[1] or color.r or 1,
        color[2] or color.g or 1,
        color[3] or color.b or 1,
        (color[4] or color.a) == nil and 1
            or (color[4] or color.a)
end

local function PreviewSlotIconColor(slot, field, color)
    local target = slot and slot._yhudSharedIconTarget
    if not target then return false end
    local r, g, b, a = PreviewColorComponents(color)
    if field == "iconBackground" then
        local background = target.background
        if background and background.SetColorTexture then
            background:SetColorTexture(r, g, b, a)
            return true
        end
        return false
    end
    if field ~= "iconBorder" then return false end
    if target.shapeBorder and target.shapeBorder.SetVertexColor then
        target.shapeBorder:SetVertexColor(r, g, b, a)
    end
    local borders = target.pixelBorder
    if borders then
        borders.top:SetColorTexture(r, g, b, a)
        borders.bottom:SetColorTexture(r, g, b, a)
        borders.left:SetColorTexture(r, g, b, a)
        borders.right:SetColorTexture(r, g, b, a)
    end
    return target.shapeBorder ~= nil or borders ~= nil
end

local function PreviewSlotTextColor(slot, target, color)
    local r, g, b, a = PreviewColorComponents(color)
    local iconSlot = slot and slot.icon and slot.icon.icon and slot.icon or slot
    local region
    if target == "name" then
        region = slot and (slot._yhudDesignNameText or slot.durationNameText)
    elseif target == "count" then
        region = slot and (slot._yhudDesignCountText
            or slot.durationCountText
            or (iconSlot and iconSlot.count)
            or slot.count)
    elseif target == "cooldown" then
        region = slot and slot._yhudDesignCooldownText
    else
        region = slot and (slot.resourceValueText or slot.durationCountText)
    end
    if not (region and region.SetTextColor) then return false end
    region:SetTextColor(r, g, b, a)
    return true
end

local function PreviewSlotColor(slot, field, color)
    if field == "iconShadow" then
        return View.PreviewIconShadowColor
            and View:PreviewIconShadowColor(slot, color) or false
    end
    if not slot or (slot.IsShown and not slot:IsShown()) then return false end
    if slot._yhudBarProgress and slot._yhudBarProgress.source == "spell-charges"
        and (field == "fillColor" or field == "rechargeColor") and View.PreviewBarChargeColor then
        return View:PreviewBarChargeColor(slot, field, color)
    end
    if field == "fillColor" then
        if slot.PreviewResourceColor then
            return slot:PreviewResourceColor("fill", color)
        end
        if slot._yhudBarStackPreviewCount ~= nil and View.ApplyBarStackPreview then
            slot._yhudBarStackBaseColor = color
            View:ApplyBarStackPreview(slot, slot._yhudBarStackPreviewCount)
            return true
        end
        return slot.PreviewDurationFillColor
            and slot:PreviewDurationFillColor(color) or false
    elseif field == "trackColor" or field == "backgroundColor" then
        if slot.PreviewResourceColor then
            return slot:PreviewResourceColor("background", color)
        end
        return slot.PreviewDurationTrackColor
            and slot:PreviewDurationTrackColor(color) or false
    elseif field == "borderColor" and slot.PreviewResourceColor then
        return slot:PreviewResourceColor("border", color)
    elseif field == "textColor" then
        if slot.PreviewResourceColor then
            return slot:PreviewResourceColor("text", color)
        end
        return PreviewSlotTextColor(slot, nil, color)
    elseif field == "iconBackground" or field == "iconBorder" then
        return PreviewSlotIconColor(slot, field, color)
    end
    return false
end

local function ColorPreviewContext(self)
    local projection = self.designMode == true and self.designProjection or nil
    if projection then
        return projection.byMonitor or {}, projection.desiredMonitors or {}
    end
    return self.byMonitor or {}, self.desiredMonitors or {}
end

local function IsColorPreviewMonitor(monitorId, physicalId, slot)
    return physicalId == monitorId
        or slot._yhudMonitorId == monitorId
        or slot._yhudLogicalMonitorId == monitorId
end

local function ResolveResourceAuraApplicationVariants(bindings, structuralMax)
    local variants = bindings and bindings.auraApplicationVariants
    if type(variants) ~= "table" then return nil end

    local resolved = {}
    for index = 1, #variants do
        local variant = variants[index]
        if type(variant) == "table" then
            local copy = {}
            for key, value in pairs(variant) do copy[key] = value end
            if index == 1 then copy.maxApplications = structuralMax end
            resolved[index] = copy
        else
            resolved[index] = variant
        end
    end
    return resolved
end

function View:PreviewMonitorColor(monitorId, field, color)
    local changed = false
    local slots = ColorPreviewContext(self)
    for physicalId, slot in pairs(slots) do
        if IsColorPreviewMonitor(monitorId, physicalId, slot) then
            changed = PreviewSlotColor(slot, field, color) or changed
        end
    end
    return changed
end

function View:PreviewGroupColor(groupId, field, color)
    local changed = false
    local slots = ColorPreviewContext(self)
    for _, slot in pairs(slots) do
        if slot._yhudGroupId == groupId then
            changed = PreviewSlotColor(slot, field, color) or changed
        end
    end
    return changed
end

function View:PreviewGroupTextColor(groupId, target, color)
    local changed = false
    local slots = ColorPreviewContext(self)
    for _, slot in pairs(slots) do
        if slot._yhudGroupId == groupId then
            changed = PreviewSlotTextColor(slot, target, color) or changed
        end
    end
    return changed
end

function View:PreviewResourceColor(groupId, resourceId, field, color, finish)
    local changed = false
    local slots, desiredMonitors = ColorPreviewContext(self)
    for monitorId, slot in pairs(slots) do
        if slot._yhudGroupId == groupId and slot.PreviewResourceColor then
            local monitor = desiredMonitors[monitorId]
            local resource = monitor and monitor._yhudResource
            if resourceId == nil or resource and resource.id == resourceId then
                changed = slot:PreviewResourceColor(field, color) or changed
                if self.designMode then
                    if finish then
                        slot._yhudDesignResourcePreviewColor = nil
                    else
                        local pending = slot._yhudDesignResourcePreviewColor or {}
                        pending.field, pending.color = field, color
                        slot._yhudDesignResourcePreviewColor = pending
                    end
                    local preview = slot._yhudDesignResourcePreview
                    if preview and preview.PreviewResourceColor then
                        changed = preview:PreviewResourceColor(field, color) or changed
                    end
                end
            end
        end
    end
    return changed
end

local function RefreshResourceColorCurve(slot, maximum, force)
    if not force and slot._yhudResourceCurveInitialized
        and slot._yhudResourceCurveMax == maximum then return end
    slot._yhudResourceCurveInitialized = true
    local unit = YUI.API and YUI.API.Unit
    slot._yhudResourceCurveMax = maximum
    slot._yhudResourceColorCurve = unit and unit.CreatePowerColorCurve
        and unit.CreatePowerColorCurve(slot._yhudResourceColorPolicy, maximum) or nil
end
I.RefreshResourceColorCurve = RefreshResourceColorCurve

-- Only our public configuration records enter this cache, never resource values
-- or native duration/geometry. Copies detect in-place editor mutations.
local function SameResourceConfig(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do
        if not SameResourceConfig(value, b[key]) then return false end
    end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function CopyResourceConfig(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = CopyResourceConfig(item) end
    return copy
end

local function ResourceConfigChanged(slot, key, value)
    local cache = slot._yhudResourceConfigCache
    local revision = View.resourceConfigRevision
    if not cache or cache.revision ~= revision then
        cache = { revision = revision }
        slot._yhudResourceConfigCache = cache
    end
    if cache[key] and SameResourceConfig(cache[key], value) then return false end
    cache[key] = CopyResourceConfig(value)
    return true
end

local function ApplyResourceDisplayConfig(slot, config)
    -- Release clears live sinks and stops drivers. Such bindings always need
    -- the original setup path, even with identical appearance after pooling.
    local static = not config.rechargeProgress and not config.durationProgress
        and not config.independentCells and not config.timerMarkers
        and not config.partialRecharge and not config.auraDurationSpellID
        and not config.auraDurationSpellIDs and not config.auraTextSpellID
        and not config.auraApplicationSpellIDs and not config.auraApplicationVariants
    if static then
        -- Presentation carries Aura appearance for every provider. Plain power
        -- bars never consume it; a power color change must not rebuild cells
        -- or text solely because these inactive binding fields changed.
        config.auraDurationFillColor = nil
        config.auraDurationTextAppearance = nil
        config.auraApplicationFillColor = nil
        config.auraApplicationTextAppearance = nil
        config.partialUnit, config.partialPowerType, config.partialScale = nil, nil, nil
        config.partialSource, config.partialPollInterval, config.partialProgressReader = nil, nil, nil
    end
    local changed = ResourceConfigChanged(slot, "display", config)
    if not static or changed then
        slot:SetResourceDisplayConfig(config)
    end
    return not static or changed
end

local function ConfigureResourceAppearance(
    slot,
    runtime,
    monitor,
    projectionOnly
)
    local preset = monitor and monitor._yhudResource or {}
    local presentation = monitor and monitor._yhudResourcePresentation
    slot._yhudResourceRowKey = preset.resourceRowKey
    if slot._yhudResourceId ~= preset.id then
        -- Structural maximum updates can mutate the native display config
        -- after its cold setup. Do not reuse that config for another resource.
        local cachedDisplay = slot._yhudResourceConfigCache
            and slot._yhudResourceConfigCache.display
        if slot._yhudResourceStructuralMax and cachedDisplay
            and cachedDisplay.segmentCount ~= slot._yhudResourceStructuralMax then
            slot._yhudResourceConfigCache.display = nil
        end
        slot._yhudResourceId = preset.id
        slot._yhudResourceStructuralMax = nil
    end
    local style = presentation and presentation.style
        or YHUD.GetEffectiveResourceStyle
        and YHUD:GetEffectiveResourceStyle(
            runtime.resourceProfile,
            runtime.resourceGroupId or runtime.id,
            preset.id,
            preset.specID
        ) or runtime
    if slot.SetResourceFillDirection then
        local hand = preset.provider and preset.provider.swingHand
        slot:SetResourceFillDirection(style.fillDirection
            or hand == "mainhand" and runtime.mainHandFillDirection
            or hand == "offhand" and runtime.offHandFillDirection or runtime.fillDirection)
    end
    -- Design geometry owns the assigned share; appearance-only slider updates
    -- retain it. Thickness changes explicitly request a shared layout pass.
    if slot.SetResourceBarSize and projectionOnly ~= true then
        -- Layout owns the resolved group width. Reconfiguring appearance while
        -- leaving design mode must not collapse an automatic-width resource to
        -- its configured minimum before the final layout pass; GUI2 cell
        -- geometry can otherwise retain that transient width until a later
        -- resource update. A real geometry change is still resolved by the
        -- synchronous RelayoutGroup that follows the cold config boundary.
        local width, height = I.ResolveResourceSize(runtime,
            runtime.effectiveResourceWidth or runtime.resourceWidth,
            style.heightOverride or runtime.resourceHeight
        )
        slot:SetResourceBarSize(width, height, runtime.orientation)
    end
    local styleConfig = {
        fillTexture = style.fillTexture,
        fillColorMode = style.fillColorMode,
        fillColor = style.fillColor,
        trackColor = style.backgroundColor,
        border = style.border,
        borderColor = style.borderColor,
    }
    local styleChanged = ResourceConfigChanged(slot, "style", styleConfig)
    local snapshot = slot._yhudResourceCompiledStyle
    if styleChanged then
        snapshot = GUI2.CompileStatusBarStyle
            and GUI2:CompileStatusBarStyle(styleConfig) or runtime.statusBarStyle
        slot._yhudResourceCompiledStyle = snapshot
        if slot.SetResourceBorder then slot:SetResourceBorder(style.border) end
        if slot.SetResourceBorderColor then slot:SetResourceBorderColor(style.borderColor) end
        if slot.SetResourceBackgroundColor then
            slot:SetResourceBackgroundColor(style.backgroundColor)
        end
        if slot.SetResourceFillStyle and snapshot then
            slot:SetResourceFillStyle(snapshot)
        elseif slot.SetResourceFillTexture then
            slot:SetResourceFillTexture(snapshot and snapshot.texture or style.fillTexture)
        end
    end
    if slot.SetResourceFillColor then
        slot:SetResourceFillColor(style.fillColor)
    end
    local displayChanged = true
    if slot.SetResourceDisplayConfig then
        local segmentCount = slot._yhudResourceStructuralMax
            or presentation and presentation.display
                and presentation.display.segmentCount
            or preset.segmentCountFallback or preset.previewMax
        local source = presentation and presentation.display or {}
        local bindings = presentation and presentation.bindings or {}
        local auraApplicationVariants = projectionOnly ~= true
            and ResolveResourceAuraApplicationVariants(bindings, segmentCount)
            or nil
        displayChanged = ApplyResourceDisplayConfig(slot, {
            mode = source.mode or style.displayMode,
            pointShape = source.pointShape or style.pointShape,
            nativePointStyle = source.nativePointStyle,
            inverseFill = source.inverseFill == true,
            smoothProgress = source.smoothProgress == true,
            valueKind = source.valueKind or preset.valueKind,
            segmentCount = segmentCount,
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
            independentCells = source.independentCells == true,
            chargedPointColor = source.chargedPointColor,
            rechargeProgress = projectionOnly ~= true
                and bindings.rechargeProgress == true,
            durationProgress = projectionOnly ~= true
                and bindings.durationProgress == true,
            durationProgressDirection = bindings.durationProgressDirection,
            auraDurationSpellID = projectionOnly ~= true
                and bindings.auraDurationSpellID or nil,
            auraDurationSpellIDs = projectionOnly ~= true and bindings.auraDurationSpellIDs or nil,
            auraDurationRequirePlayerSource = bindings.auraDurationRequirePlayerSource,
            auraDurationUnit = projectionOnly ~= true
                and bindings.auraDurationUnit or nil,
            auraDurationFilter = projectionOnly ~= true
                and bindings.auraDurationFilter or nil,
            auraDurationDirection = projectionOnly ~= true
                and bindings.auraDurationDirection or nil,
            auraDurationFillColor = projectionOnly ~= true
                and bindings.auraDurationFillColor or nil,
            auraTextSpellID = projectionOnly ~= true and bindings.auraTextSpellID or nil,
            auraDurationTextAppearance = projectionOnly ~= true
                and bindings.auraDurationTextAppearance or nil,
            auraApplicationSpellIDs = projectionOnly ~= true
                and bindings.auraApplicationSpellIDs or nil,
            auraApplicationVariants = auraApplicationVariants,
            auraApplicationUnit = projectionOnly ~= true
                and bindings.auraApplicationUnit or nil,
            auraApplicationFilter = projectionOnly ~= true
                and bindings.auraApplicationFilter or nil,
            auraApplicationRequirePlayerSource = projectionOnly ~= true
                and bindings.auraApplicationRequirePlayerSource == true,
            auraApplicationMax = projectionOnly ~= true
                and bindings.auraApplicationMax ~= nil
                and segmentCount or nil,
            auraApplicationFillColor = projectionOnly ~= true
                and bindings.auraApplicationFillColor or nil,
            auraApplicationTextAppearance = projectionOnly ~= true
                and bindings.auraApplicationTextAppearance or nil,
            timerMarkers = projectionOnly ~= true
                and bindings.timerMarkers == true,
            partialRecharge = projectionOnly ~= true
                and bindings.partialRecharge == true,
            partialUnit = projectionOnly ~= true
                and bindings.partialUnit or nil,
            partialPowerType = projectionOnly ~= true
                and bindings.partialPowerType or nil,
            partialScale = projectionOnly ~= true
                and bindings.partialScale or nil,
            partialSource = projectionOnly ~= true
                and bindings.partialSource or nil,
            partialPollInterval = projectionOnly ~= true
                and bindings.partialPollInterval or nil,
            partialProgressReader = projectionOnly ~= true
                and YUI.API and YUI.API.Unit
                and YUI.API.Unit.ReadPowerPartialFraction or nil,
        })
    end
    if slot.SetResourceTextAppearance then
        local textAppearance = presentation and presentation.text or {
            nameText = false,
            valueText = style.valueText,
            valueFormat = style.valueFormat,
            abbreviateValues = style.abbreviateValues,
            text2 = style.text2,
            previewDuration = style.valueDurationPreview,
            fractionalValues = preset.provider and preset.provider.kind == "unit-power-partial",
            position = style.textPosition,
            offsetX = style.textOffsetX,
            offsetY = style.textOffsetY,
            font = style.textFont,
            size = style.textSize,
            runeCooldownTextSize = style.runeCooldownTextSize,
            runeCooldownTextMode = style.runeCooldownTextMode,
            outline = style.textOutline,
            monochrome = style.textMonochrome,
            color = style.textColor,
        }
        local textChanged = ResourceConfigChanged(slot, "text", textAppearance)
        if displayChanged or textChanged then slot:SetResourceTextAppearance(textAppearance) end
    end
    slot._yhudResourceStyle = style
    if I.ConfigurePlayerCast then I.ConfigurePlayerCast(slot, preset, style) end
    if I.ConfigureResourceProgress then I.ConfigureResourceProgress(slot, runtime, preset) end
    slot._yhudResourceColorPolicy = {
        thresholdColorEnabled = style.thresholdColorEnabled == true,
        thresholdMode = style.thresholdMode,
        thresholds = style.thresholds,
        fillColor = style.fillColor,
        valueKind = preset.valueKind,
    }
    RefreshResourceColorCurve(slot, slot._yhudResourceStructuralMax or preset.segmentCountFallback
        or slot._yhudResourceCurveMax, true)
    if styleChanged then
        slot._yhudResourceStatusRuntime = { statusBarStyle = snapshot }
        ApplySharedStatusBarStyle(slot, slot._yhudResourceStatusRuntime, true)
    end
end

I.SetSlotIcon = SetSlotIcon
I.ClearSlotDuration = ClearSlotDuration
I.GetSlotIconTexture = GetSlotIconTexture

local function InvalidateSlotVisualState(slot)
    local iconState = slot and slot._yhudSharedIconState
    if iconState then
        iconState.borderColor = nil
        iconState.borderShown = nil
        iconState.iconBorderThickness = nil
    end
    local statusState = slot and slot._yhudSharedStatusState
    if statusState then
        statusState.statusBorderColor = nil
        statusState.statusBorderShown = nil
        statusState.statusBorderThickness = nil
    end
end

function View:ReapplySlotVisual(slot)
    local runtime = ResolveSlotRuntime(slot)
    if not runtime then return false end
    local projection = slot._yhudDesignProjection == true
        and self.designProjection or nil
    local desiredMonitors = projection
        and projection.desiredMonitors or self.desiredMonitors
    InvalidateSlotVisualState(slot)
    if runtime.view == "resource" then
        ApplySharedStatusBarStyle(
            slot,
            slot._yhudResourceStatusRuntime or runtime,
            true
        )
    else
        self:ConfigureSlot(
            slot,
            runtime,
            desiredMonitors and desiredMonitors[slot._yhudMonitorId]
        )
    end
    return true
end

function View:ReapplyMonitorVisual(monitorId, appearanceOverride)
    local changed = false
    local slots, desiredMonitors = ColorPreviewContext(self)
    local projection = self.designMode == true and self.designProjection or nil
    for physicalId, slot in pairs(slots) do
        if IsColorPreviewMonitor(monitorId, physicalId, slot) then
            local monitor = projection and desiredMonitors[physicalId]
            if monitor and appearanceOverride ~= nil then
                monitor.appearanceOverride = appearanceOverride
            end
            changed = self:ReapplySlotVisual(slot) or changed
            if self.designMode and slot._yhudBarProgress and self.ApplyDesignDurationPreview then
                self:ApplyDesignDurationPreview(slot)
            end
        end
    end
    return changed
end

function View:RefreshDurationBarTextLayers(slot, runtime)
    if not (slot and slot.SetDurationTextLayer) then return false end
    runtime = ResolveSlotRuntime(slot, runtime)
    local level, strata = self:GetMonitorTextLayer(runtime)
    if not level then return false end
    slot:SetDurationTextLayer(level, strata)
    return true
end

function View:RefreshResourceTextLayers(slot, runtime)
    if not (slot and slot.SetResourceTextLayer) then return false end
    runtime = ResolveSlotRuntime(slot, runtime)
    local level, strata = self:GetMonitorTextLayer(runtime)
    if not level then return false end
    slot:SetResourceTextLayer(level, strata)
    local preview = slot._yhudDesignResourcePreview
    if preview and preview.SetResourceTextLayer then
        SetFrameLevelIfChanged(preview, (slot:GetFrameLevel() or 0) + 1)
        if strata and preview.SetFrameStrata and preview:GetFrameStrata() ~= strata then
            preview:SetFrameStrata(strata)
        end
        preview:SetResourceTextLayer(level, strata)
    end
    return true
end

function View:ConfigureSlot(slot, runtime, monitor)
    if not slot then return end
    if runtime.view ~= "resource" then slot._yhudResourceRowKey = nil end
    if GUI2.BeginIconSkin and not GUI2:BeginIconSkin(slot) then
        GUI2:DeferIconSkin(slot, function() self:ConfigureSlot(slot, runtime, monitor) end)
        return
    end
    if runtime.view ~= "icon" and self.HideIconShadow then self:HideIconShadow(slot) end
    if self.GetMonitorDisplayLayer then
        local level, strata = self:GetMonitorDisplayLayer(
            runtime,
            slot._yhudMonitorId or (monitor and monitor.id)
        )
        if strata and slot.SetFrameStrata then slot:SetFrameStrata(strata) end
        if level and slot.SetFrameLevel then slot:SetFrameLevel(level) end
    end
    local profile = type(monitor) == "table"
        and monitor._yhudProjectionProfile or self.profile
    local entry = type(monitor) == "table"
        and (monitor._yhudProjectionEntry
            or profile and profile.entries
                and profile.entries[monitor.entryKey])
    if YHUD.AssistedHighlight then
        YHUD.AssistedHighlight:Bind(slot, runtime, monitor, entry)
    end
    if YHUD.PressFeedback and YHUD.PressFeedback.active then
        YHUD.PressFeedback:Bind(slot, runtime, monitor, entry)
    end
    ConfigureSlotTooltip(slot, runtime, monitor, entry, self.designMode)
    self:ApplyKeybindText(slot, runtime, monitor, entry)
    self:ApplyIconLabel(slot, runtime, entry)
    slot._yhudDisplayName = nil
    if runtime.view == "bar" or runtime.view == "ring" then
        slot._yhudDisplayName = FormatMonitorName(
            runtime.nameTextFormat,
            monitor and monitor._yhudDisplayName or GetEntryName(entry)
        )
    end
    local compiledGlow
    if type(monitor) == "table" and Glow and Glow.Compile then
        compiledGlow = Glow:Compile(profile, monitor)
    end
    slot._yhudGlowRuntime = compiledGlow
    if type(monitor) == "table" then
        monitor._yhudGlowRuntime = compiledGlow
    end
    slot._yhudNativeProcGlowLayoutDirty = true
    if runtime.view == "resource" then
        -- Seed text layers before native Aura initialization seals its children.
        self:RefreshResourceTextLayers(slot, runtime)
        monitor = monitor or self.desiredMonitors[slot._yhudMonitorId]
        if slot.BeginResourceLayoutUpdate and slot.EndResourceLayoutUpdate then
            slot:BeginResourceLayoutUpdate()
            local ok, message = pcall(ConfigureResourceAppearance,
                slot, runtime, monitor, slot._yhudDesignProjection == true)
            local ended, endMessage = pcall(slot.EndResourceLayoutUpdate, slot)
            if not ok or not ended then
                slot._yhudResourceConfigCache = nil
                error(not ok and message or endMessage, 0)
            end
        else
            ConfigureResourceAppearance(
                slot, runtime, monitor, slot._yhudDesignProjection == true)
        end
        return
    end

    local appearance = type(monitor) == "table"
        and type(monitor.appearanceOverride) == "table"
        and monitor.appearanceOverride or nil
    if runtime.view == "icon" then
        PrepareChargeRecoveryCurves(runtime)
        slot._yhudCooldownSwipeDraw, slot._yhudCooldownSwipeReverse =
            YHUD:ResolveMonitorCooldownSwipe(
                appearance and appearance.cooldownSwipeMode,
                runtime.cooldownSwipe,
                YHUD:GetEntrySemantic(entry) == "buff"
            )
    else
        slot._yhudCooldownSwipeDraw = nil
        slot._yhudCooldownSwipeReverse = nil
    end
    local fillColor = appearance and appearance.fillColor
        or runtime.fillColor
    local trackColor = appearance and appearance.trackColor
        or runtime.trackColor
    local cooldownText = {
        enabled = runtime.cooldownText,
        font = runtime.cooldownTextFont,
        size = runtime.cooldownTextSize,
        outline = runtime.cooldownTextOutline,
        monochrome = runtime.cooldownTextMonochrome,
        position = runtime.cooldownTextPosition,
        anchor = runtime.cooldownTextAnchor,
        offsetX = runtime.cooldownTextOffsetX,
        offsetY = runtime.cooldownTextOffsetY,
        color = runtime.cooldownTextColor,
    }
    local nameText = {
        enabled = runtime.nameText,
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

    if runtime.view == "bar" then
        if slot.SetDurationSmoothProgress then
            slot:SetDurationSmoothProgress(runtime.smoothProgress == true)
        end
        local countText = {
            enabled = runtime.countText,
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
        if slot.SetDurationBarLayout then
            slot:SetDurationBarLayout(
                runtime.orientation,
                runtime.iconPosition,
                runtime.iconGap,
                runtime.fillDirection == "reverse"
            )
        end
        if slot.SetDurationBarSize then
            slot:SetDurationBarSize(
                runtime.itemWidth,
                runtime.itemHeight,
                runtime.iconSize
            )
        end
        if slot.SetDurationIconAppearance then
            slot:SetDurationIconAppearance({
                size = runtime.iconSize,
                shape = runtime.shape,
                border = runtime.border,
            })
        end
        if slot.SetDurationIconShown then
            slot:SetDurationIconShown(runtime.showIcon)
        end
        if slot.SetDurationTextAppearance then
            slot:SetDurationTextAppearance(cooldownText)
        end
        if slot.SetDurationNameAppearance then
            slot:SetDurationNameAppearance(nameText)
        end
        if slot.SetDurationCountAppearance then
            slot:SetDurationCountAppearance(countText)
        end
        ApplySharedIconStyle(slot, runtime)
        local statusRuntime = runtime
        if appearance and GUI2.CompileStatusBarStyle then
            local compiled = GUI2:CompileStatusBarStyle({
                fillTexture = runtime.fillTexture,
                fillColor = fillColor,
                trackColor = trackColor,
                border = runtime.barBorder or runtime.border,
                borderColor = runtime.borderColor,
                showIcon = runtime.showIcon,
            })
            slot._yhudMonitorStatusRuntime =
                slot._yhudMonitorStatusRuntime or {}
            slot._yhudMonitorStatusRuntime.statusBarStyle = compiled
            statusRuntime = slot._yhudMonitorStatusRuntime
        else
            slot._yhudMonitorStatusRuntime = nil
        end
        ApplySharedStatusBarStyle(slot, statusRuntime, false)
        if slot.SetDurationFillTexture and runtime.statusBarStyle then
            slot:SetDurationFillTexture(
                runtime.statusBarStyle.texture,
                runtime.statusBarStyle.textureU0,
                runtime.statusBarStyle.textureU1,
                runtime.statusBarStyle.textureV0,
                runtime.statusBarStyle.textureV1
            )
        end
        -- StatusBar 样式和原生计时绑定都可能重建内部填充纹理；单项颜色
        -- 必须作为本次冷配置的最终写入，确保运行时与设计预览一致。
        if slot.SetDurationFillColor then
            slot:SetDurationFillColor(fillColor)
        end
        self:RefreshDurationBarTextLayers(slot, runtime)
        if self.ConfigureBarProgress then
            self:ConfigureBarProgress(slot, runtime, monitor, entry)
        end
        if self.ConfigureBarStackThresholds then
            self:ConfigureBarStackThresholds(slot, runtime, monitor, entry,
                slot.barWidth or runtime.barWidth or runtime.itemWidth or 1)
        end
        if self.LayoutBarTicks then self:LayoutBarTicks(slot, runtime, slot._yhudBarMaximum) end
        if self.ApplySlotIconSkin then self:ApplySlotIconSkin(slot, runtime, monitor) end
        return
    end

    if runtime.view == "ring" then
        -- Ring diameter/layer material belong exclusively to RelayoutGroup.
        -- Reapplying the cold visual style must not collapse every existing
        -- concentric ring back to the group's base diameter before layout's
        -- geometry cache runs.
        if slot.SetDurationRingStyle then
            slot:SetDurationRingStyle({
                thickness = runtime.ringThickness,
                direction = runtime.ringDirection,
                start = runtime.ringStart,
                trackColor = appearance and appearance.trackColor
                    or runtime.ringTrackColor,
                centerColor = runtime.iconStyle
                    and runtime.iconStyle.backgroundColor,
                border = runtime.border,
            })
        end
        if slot.SetDurationTextAppearance then
            slot:SetDurationTextAppearance(cooldownText)
        end
        if slot.SetDurationNameAppearance then
            slot:SetDurationNameAppearance(nameText)
        end
        if slot.SetDurationCountAppearance then
            slot:SetDurationCountAppearance({
                enabled = runtime.countText,
                font = runtime.countTextFont,
                size = runtime.countTextSize,
                outline = runtime.countTextOutline,
                monochrome = runtime.countTextMonochrome,
                position = runtime.countTextPosition,
                anchor = runtime.countTextAnchor,
                offsetX = runtime.countTextOffsetX,
                offsetY = runtime.countTextOffsetY,
                color = runtime.countTextColor,
            })
        end
        if slot.SetDurationFillColor then
            slot:SetDurationFillColor(fillColor)
        end
        -- DurationRing owns its radial material and intentionally has no icon
        -- chrome. Applying icon chrome here can resurrect a square icon border
        -- after a monitor is moved from an icon group into a ring group.
        ApplySharedCountStyle(slot, runtime)
        return
    end

    if slot.SetIconAppearance then
        slot:SetIconAppearance({
            size = runtime.iconSize,
            shape = runtime.shape,
            border = runtime.border,
        })
    else
        slot:SetSize(runtime.iconWidth, runtime.iconHeight)
    end
    if slot.SetCooldownTextAppearance then
        slot:SetCooldownTextAppearance(cooldownText)
    end
    ApplySharedIconStyle(slot, runtime)
    if slot._yhudSharedCooldownState then
        slot._yhudSharedCooldownState.chargeRecoveryRuntime = nil
    end
    local state = monitor and YHUD.Model and YHUD.Model:GetState(monitor.sourceKey)
    ApplyIconTextLayers(slot, runtime)
    if self.ApplyIconShadow then self:ApplyIconShadow(slot, runtime) end
    if self.ApplySlotIconSkin then self:ApplySlotIconSkin(slot, runtime, monitor) end
    ConfigureIconCompletionFlash(slot, runtime)
    self:ApplyIconCooldownPresentation(slot, runtime, entry, state)
    if self.ConfigureBuffTimerStacks then
        self:ConfigureBuffTimerStacks(slot, runtime, monitor, entry)
    end
end

function View:RefreshFilteredAuraSlotLayers(slot, runtime)
    return ApplyIconTextLayers(slot, runtime)
end

function View:CreateFilteredAuraSlot(parent, runtime, monitor, nativeTooltip)
    if not (parent and runtime) then return nil end
    local profile = type(monitor) == "table"
        and monitor._yhudProjectionProfile or self.profile
    local entry = type(monitor) == "table"
        and (monitor._yhudProjectionEntry
            or profile and profile.entries
                and profile.entries[monitor.entryKey])
    local durationName
    if runtime.view == "bar" or runtime.view == "ring" then
        durationName = FormatMonitorName(
            runtime.nameTextFormat,
            monitor and monitor._yhudDisplayName or GetEntryName(entry)
        )
    end
    local slot
    if runtime.view == "bar" and App.CreateDurationBar then
        slot = App:CreateDurationBar(parent, {
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
            name = durationName,
            countSink = true,
        })
    elseif runtime.view == "ring" and App.CreateDurationRing then
        slot = App:CreateDurationRing(parent, {
            diameter = runtime.diameter,
            icon = QUESTION_ICON,
            iconBorder = runtime.border,
            fillColor = runtime.fillColor,
            ringThickness = runtime.ringThickness,
            ringDirection = runtime.ringDirection,
            ringStart = runtime.ringStart,
            trackColor = runtime.ringTrackColor,
            name = durationName,
            countSink = true,
        })
    elseif App.CreateCooldownIcon then
        slot = App:CreateCooldownIcon(parent, {
            size = runtime.iconSize,
            icon = QUESTION_ICON,
            shape = runtime.shape,
            border = runtime.border,
            variant = "bare",
            countSink = true,
        })
    end
    if not slot then return nil end
    slot._yhudFilteredAuraGlow = true
    slot._yhudNativeAuraTooltip = nativeTooltip == true
    slot._yhudMonitorId = monitor and monitor.id
    slot._yhudLogicalMonitorId = monitor and monitor.id
    slot._yhudGroupId = runtime.id
    slot._yhudView = runtime.view
    slot._yhudBarStackLive = nativeTooltip == true
    self:ConfigureSlot(slot, runtime, monitor)
    if slot.SetAllPoints then slot:SetAllPoints(parent) end
    if runtime.view == "bar" and runtime.orientation ~= "vertical"
        and runtime.barWidthMode == "auto" and slot.track then
        -- Native group layout can resize the Aura button in its secure
        -- partition. Anchor the material once, before native bindings exist.
        local inset = runtime.showIcon ~= false and runtime.iconSize + runtime.iconGap or 0
        local left = runtime.iconPosition == "left" and inset or 0
        local right = runtime.iconPosition == "right" and inset or 0
        local top = runtime.iconPosition == "top" and inset or 0
        local bottom = runtime.iconPosition == "bottom" and inset or 0
        slot.track:ClearAllPoints()
        slot.track:SetPoint("TOPLEFT", slot, "TOPLEFT", left, -top)
        slot.track:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -right, bottom)
    end
    if runtime.view == "ring"
        and runtime.timeText ~= false
        and slot.CreateAuraDurationText then
        slot:CreateAuraDurationText()
    end
    return slot
end

function View:GetFilteredAuraSlotBindings(slot, runtime)
    if not (slot and runtime) then return nil end
    local icon
    if runtime.view ~= "bar" or runtime.showIcon ~= false then
        icon = GetSlotIconTexture(slot)
    end
    local count = slot.durationCountText
        or (slot.icon and slot.icon.count)
        or slot.count
    local bindings = {
        icon = icon,
        applicationCount = runtime.countText == true and count or nil,
    }
    if runtime.view == "bar" then
        -- Filtered Aura binds the native timer after this method returns,
        -- bypassing DurationBar:SetDurationObject. Prepare the projected
        -- driver now and keep its authored visible material enabled while
        -- Blizzard owns the secret timer value.
        if slot.RefreshProjectedDriverStyle then
            slot:RefreshProjectedDriverStyle(true)
        end
        if slot.SetNativeFillShown then
            slot:SetNativeFillShown(true)
        end
        local progress = slot._yhudBarProgress
        if progress and progress.source == "aura-stacks" then
            if self.PrepareBarValueDriver then self:PrepareBarValueDriver(slot, runtime) end
            local maximum = slot._yhudBarMaximum
            if maximum then
                bindings.applicationBar = { target = slot.durationStatusBar,
                    options = { maxApplications = maximum, interpolation = 0 } }
            elseif slot.SetNativeFillShown then
                slot:SetNativeFillShown(false)
            end
        else
            bindings.durationBar = slot.durationStatusBar
        end
        bindings.durationCooldown = slot.countdown
    elseif runtime.view == "ring" then
        bindings.durationCooldown = slot.durationRingProgress or slot.cooldown
        if runtime.timeText ~= false then
            bindings.durationText = slot.durationAuraText
        end
    else
        bindings.durationCooldown = slot.cooldown
    end
    return bindings
end

function View:ConfigureFilteredAuraStaticSlot(
    slot,
    runtime,
    monitor,
    entry,
    inactiveDesaturate
)
    if not slot then return false end
    local icon = monitor and monitor._yhudDisplayIcon
        or entry and entry.icon or QUESTION_ICON
    if YHUD.Ammo and entry and entry.sourceType == YHUD.Ammo.SOURCE_TYPE then
        icon = monitor and monitor._yhudDisplayIcon or YHUD.Ammo:GetPreviewIcon()
    end
    slot._yhudIcon = icon
    SetSlotIcon(slot, icon)
    if (runtime.view == "bar" or runtime.view == "ring")
        and slot.SetDurationName then
        slot:SetDurationName(FormatMonitorName(
            runtime.nameTextFormat,
            monitor and monitor._yhudDisplayName or GetEntryName(entry)
        ))
    end
    ClearSlotDuration(slot)
    if slot.SetCount then slot:SetCount(nil) end
    self:ApplyIconDesaturation(slot, nil, inactiveDesaturate == true)
    I.SetSlotMouseInput(slot, slot._yhudTooltipEnabled, self.designMode)
    return true
end

function View:ShouldUseFilteredAuraSingleLineNativeProjection(
    monitorId,
    runtime
)
    local strategy = runtime and runtime.filteredAuraProjectionStrategy
    if not (runtime and runtime.view == "icon"
        and (strategy == YHUD.FILTERED_AURA_LAYOUT_MIXED_DYNAMIC_SINGLE_LINE
            or strategy ==
                YHUD.FILTERED_AURA_LAYOUT_MIXED_SEGMENTED_OVERFLOW)
        and self.preview ~= true
        and self.designMode ~= true
        and self.layoutEditMode ~= true) then
        return false
    end
    local monitor = self.desiredMonitors[monitorId]
        or (self.profile and self.profile.monitors
            and self.profile.monitors[monitorId])
    local entry = monitor and self.profile and self.profile.entries
        and self.profile.entries[monitor.entryKey]
    local displayCategory = entry
        and (entry.displayCategory or entry.officialCategory)
    return entry ~= nil
        and entry.origin == "official-cdm"
        and displayCategory == "trackedBuff"
        and monitor.view == "icon"
end

function View:ShouldUseFilteredAuraChainSlot(monitorId, runtime)
    if not (runtime and runtime.view == "icon"
        and self.preview ~= true
        and self.designMode ~= true
        and self.layoutEditMode ~= true) then
        return false
    end
    local strategy = runtime.filteredAuraProjectionStrategy
    if strategy == YHUD.FILTERED_AURA_LAYOUT_MIXED_SEGMENTED_OVERFLOW then
        local member = runtime.presentationGroupPlan
            and runtime.presentationGroupPlan.memberById
            and runtime.presentationGroupPlan.memberById[monitorId]
        return member ~= nil
    end
    if strategy ~= YHUD.FILTERED_AURA_LAYOUT_MIXED_DYNAMIC_SINGLE_LINE then
        return false
    end
    if self:ShouldUseFilteredAuraSingleLineNativeProjection(
        monitorId,
        runtime
    ) then
        return false
    end
    local monitor = self.desiredMonitors[monitorId]
        or (self.profile and self.profile.monitors
            and self.profile.monitors[monitorId])
    local entry = monitor and self.profile and self.profile.entries
        and self.profile.entries[monitor.entryKey]
    return monitor ~= nil
        and YHUD:IsFilteredAuraLayoutMonitor(entry, monitor, true) ~= true
end

local function AcquireFilteredAuraChainIcon(self, runtime)
    local slot
    if self.freeFilteredAuraChainIconCount > 0 then
        slot = self.freeFilteredAuraChainIcons[
            self.freeFilteredAuraChainIconCount
        ]
        self.freeFilteredAuraChainIcons[
            self.freeFilteredAuraChainIconCount
        ] = nil
        self.freeFilteredAuraChainIconCount =
            self.freeFilteredAuraChainIconCount - 1
        AddMonitorStat("poolFree", -1)
    elseif CreateFrame and App.CreateCooldownIcon then
        local carrier = CreateFrame(
            "Frame",
            nil,
            runtime.frame,
            "DisableUntrustedLayoutScriptsTemplate"
        )
        slot = App:CreateCooldownIcon(carrier, {
            size = runtime.iconSize,
            icon = QUESTION_ICON,
            shape = runtime.shape,
            border = runtime.border,
            variant = "bare",
            countSink = true,
            cooldownText = {
                enabled = runtime.cooldownText,
                font = runtime.cooldownTextFont,
                size = runtime.cooldownTextSize,
                outline = runtime.cooldownTextOutline,
                monochrome = runtime.cooldownTextMonochrome,
                position = runtime.cooldownTextPosition,
                color = runtime.cooldownTextColor,
            },
        })
        if slot then
            slot._yhudFilteredAuraChainCarrier = carrier
            slot._yhudFilteredAuraChainCompatible = true
            slot:SetPoint("CENTER", carrier, "CENTER", 0, 0)
        end
    end
    if not slot then return nil end
    local carrier = slot._yhudFilteredAuraChainCarrier
    if carrier then
        if carrier.SetParent then carrier:SetParent(runtime.frame) end
        I.ClearManagedLayoutPoint(carrier)
        carrier:Show()
    end
    return slot
end

function View:AcquireSlot(monitorId, runtime)
    local acquireStartedAt = runtime and runtime.view == "resource"
        and ProfileNowMS() or nil
    local chainSlot = self:ShouldUseFilteredAuraChainSlot(
        monitorId,
        runtime
    )
    local slot = self.byMonitor[monitorId]
    if slot and (slot._yhudView ~= runtime.view
        or slot._yhudGroupId ~= runtime.id
        or (slot._yhudFilteredAuraChainCompatible == true)
            ~= chainSlot) then
        self:ReleaseSlot(monitorId)
        slot = nil
    end
    if slot then
        local restored = slot._yhudVisibilitySuppressed == true
            and self:SetResourceSlotSuppressed(monitorId, false) == true
        return slot, restored
    end

    if runtime.view == "resource" then
        if self.freeResourceCount > 0 then
            local desired = self.desiredMonitors[monitorId]
            local preset = desired and desired._yhudResource
            local display = desired and desired._yhudResourcePresentation
                and desired._yhudResourcePresentation.display
            local freeIndex, sameMode = self.freeResourceCount, nil
            -- Reuse the same resource first, then the same display shape. The
            -- pool stays bounded; configuration still validates every field.
            for index = self.freeResourceCount, 1, -1 do
                local candidate = self.freeResources[index]
                if preset and candidate._yhudResourceId == preset.id then
                    freeIndex, sameMode = index, nil
                    break
                end
                local cached = candidate._yhudResourceConfigCache
                    and candidate._yhudResourceConfigCache.display
                if not sameMode and display and cached and cached.mode == display.mode then
                    sameMode = index
                end
            end
            freeIndex = sameMode or freeIndex
            slot = self.freeResources[freeIndex]
            self.freeResources[freeIndex] = self.freeResources[self.freeResourceCount]
            self.freeResources[self.freeResourceCount] = nil
            self.freeResourceCount = self.freeResourceCount - 1
            AddMonitorStat("poolFree", -1)
        elseif App.CreateResourceBar then
            local width, height = I.ResolveResourceSize(runtime, runtime.resourceWidth, runtime.resourceHeight)
            slot = App:CreateResourceBar(runtime.frame, {
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
                smoothProgress = runtime.smoothProgress == true,
                text = {
                    nameText = false,
                    valueText = true,
                    font = runtime.textFont,
                    size = runtime.textSize,
                    outline = runtime.textOutline,
                    monochrome = runtime.textMonochrome,
                    color = runtime.textColor,
                },
            })
        end
    elseif runtime.view == "bar" then
        if self.freeBarCount > 0 then
            slot = self.freeBars[self.freeBarCount]
            self.freeBars[self.freeBarCount] = nil
            self.freeBarCount = self.freeBarCount - 1
            AddMonitorStat("poolFree", -1)
        elseif App.CreateDurationBar then
            slot = App:CreateDurationBar(runtime.frame, {
                width = runtime.itemWidth,
                height = runtime.itemHeight,
                orientation = runtime.orientation,
                reverse = runtime.fillDirection == "reverse",
                iconPosition = runtime.iconPosition,
                iconGap = runtime.iconGap,
                iconSize = runtime.iconSize,
                showIcon = runtime.showIcon,
                smoothProgress = runtime.smoothProgress == true,
                icon = QUESTION_ICON,
                iconShape = runtime.shape,
                iconBorder = runtime.border,
                fillColor = runtime.fillColor,
                fillTexture = runtime.statusBarStyle
                    and runtime.statusBarStyle.texture,
                countSink = true,
                cooldownText = {
                    enabled = runtime.cooldownText,
                    font = runtime.cooldownTextFont,
                    size = runtime.cooldownTextSize,
                    outline = runtime.cooldownTextOutline,
                    monochrome = runtime.cooldownTextMonochrome,
                    position = runtime.cooldownTextPosition,
                    anchor = runtime.cooldownTextAnchor,
                    offsetX = runtime.cooldownTextOffsetX,
                    offsetY = runtime.cooldownTextOffsetY,
                    color = runtime.cooldownTextColor,
                },
                nameText = {
                    enabled = runtime.nameText,
                    font = runtime.nameTextFont,
                    size = runtime.nameTextSize,
                    outline = runtime.nameTextOutline,
                    monochrome = runtime.nameTextMonochrome,
                    position = runtime.nameTextPosition,
                    anchor = runtime.nameTextAnchor,
                    offsetX = runtime.nameTextOffsetX,
                    offsetY = runtime.nameTextOffsetY,
                    color = runtime.nameTextColor,
                },
                countText = {
                    enabled = runtime.countText,
                    font = runtime.countTextFont,
                    size = runtime.countTextSize,
                    outline = runtime.countTextOutline,
                    monochrome = runtime.countTextMonochrome,
                    position = runtime.countTextPosition,
                    anchor = runtime.countTextAnchor,
                    offsetX = runtime.countTextOffsetX,
                    offsetY = runtime.countTextOffsetY,
                    color = runtime.countTextColor,
                },
            })
        end
    elseif runtime.view == "ring" then
        if self.freeRingCount > 0 then
            slot = self.freeRings[self.freeRingCount]
            self.freeRings[self.freeRingCount] = nil
            self.freeRingCount = self.freeRingCount - 1
            AddMonitorStat("poolFree", -1)
        elseif App.CreateDurationRing then
            slot = App:CreateDurationRing(runtime.frame, {
                diameter = runtime.diameter,
                icon = QUESTION_ICON,
                iconBorder = runtime.border,
                fillColor = runtime.fillColor,
                ringThickness = runtime.ringThickness,
                ringDirection = runtime.ringDirection,
                ringStart = runtime.ringStart,
                trackColor = runtime.ringTrackColor,
                countSink = true,
                cooldownText = {
                    enabled = runtime.cooldownText,
                    font = runtime.cooldownTextFont,
                    size = runtime.cooldownTextSize,
                    outline = runtime.cooldownTextOutline,
                    monochrome = runtime.cooldownTextMonochrome,
                    position = runtime.cooldownTextPosition,
                    offsetX = runtime.cooldownTextOffsetX,
                    offsetY = runtime.cooldownTextOffsetY,
                    color = runtime.cooldownTextColor,
                },
                nameText = {
                    enabled = runtime.nameText,
                    font = runtime.nameTextFont,
                    size = runtime.nameTextSize,
                    outline = runtime.nameTextOutline,
                    monochrome = runtime.nameTextMonochrome,
                    position = runtime.nameTextPosition,
                    offsetX = runtime.nameTextOffsetX,
                    offsetY = runtime.nameTextOffsetY,
                    color = runtime.nameTextColor,
                },
            })
        end
    elseif chainSlot then
        slot = AcquireFilteredAuraChainIcon(self, runtime)
    else
        if self.freeCount > 0 then
            slot = self.free[self.freeCount]
            self.free[self.freeCount] = nil
            self.freeCount = self.freeCount - 1
            AddMonitorStat("poolFree", -1)
        else
            slot = App:CreateCooldownIcon(runtime.frame, {
                size = runtime.iconSize,
                icon = QUESTION_ICON,
                shape = runtime.shape,
                border = runtime.border,
                variant = "bare",
                countSink = true,
                cooldownText = {
                    enabled = runtime.cooldownText,
                    font = runtime.cooldownTextFont,
                    size = runtime.cooldownTextSize,
                    outline = runtime.cooldownTextOutline,
                    monochrome = runtime.cooldownTextMonochrome,
                    position = runtime.cooldownTextPosition,
                    color = runtime.cooldownTextColor,
                },
            })
        end
    end

    if not slot then return nil, false end
    InstallCooldownDoneHook(slot)
    if slot._yhudFilteredAuraChainCompatible ~= true
        and slot.SetParent then
        slot:SetParent(runtime.frame)
    end
    slot._yhudMonitorId = monitorId
    slot._yhudGroupId = runtime.id
    slot._yhudView = runtime.view
    slot._yhudIcon = nil
    slot._yhudName = nil
    slot._yhudStart = nil
    slot._yhudDuration = nil
    slot._yhudDurationMode = nil
    slot._yhudOpaqueRevision = nil
    slot._yhudFillColor = nil
    slot._yhudPlaced = nil
    slot._yhudDisplayCount = nil
    slot._yhudRawCountShown = false
    slot._yhudIconDesaturated = false
    slot._yhudGlowShown = false
    slot._yhudDisplayName = nil
    slot._yhudGlowRuntime = nil
    slot._yhudNativeProcGlowLayoutDirty = true
    slot._yhudRingDiameter = nil
    slot._yhudRingBorder = nil
    slot._yhudRingThickness = nil
    slot._yhudRingReferenceDiameter = nil
    slot._yhudRingMaterial = nil
    local desired = self.desiredMonitors[monitorId]
    slot._yhudLogicalMonitorId = desired
        and desired._yhudParentMonitorId or monitorId
    slot._yhudSynthetic = desired and desired._yhudSynthetic == true or false
    self.byMonitor[monitorId] = slot
    if runtime.view == "resource" then
        runtime.fixedResourceGeometryReady = false
    end
    self:ConfigureSlot(slot, runtime, desired)
    self:ConfigureDesignSlot(slot)
    slot:Show()
    if runtime.view == "resource"
        and self.SetResourceAuraIdentitySuppressed then
        local unitAPI = YUI.API and YUI.API.Unit
        local trusted = unitAPI
            and unitAPI.IsPlayerHelpfulAuraIdentityTrusted
            and unitAPI.IsPlayerHelpfulAuraIdentityTrusted() == true
        self:SetResourceAuraIdentitySuppressed(monitorId, trusted ~= true)
    end
    AddMonitorStat("poolActive", 1)
    if runtime.view == "resource" then
        AddPerformanceStat("resourceSlotAcquires")
        FinishPerformanceStat("resourceAcquireMS", acquireStartedAt)
    end
    return slot, true
end

function View:SetResourceSlotSuppressed(monitorId, suppressed)
    local slot = self.byMonitor[monitorId]
    if not (slot and slot._yhudView == "resource") then return false end
    suppressed = suppressed == true
    local logicalSuppressed = slot._yhudVisibilitySuppressed == true
    local frameShown = slot:IsShown() == true
    local frameShouldShow = not suppressed
        and slot._yhudAuraIdentitySuppressed ~= true
    local logicalChanged = logicalSuppressed ~= suppressed
    local frameChanged = frameShown ~= frameShouldShow
    if not logicalChanged and not frameChanged then
        AddPerformanceStat("resourceVisibilityNoops")
        return false
    end

    local startedAt = ProfileNowMS()
    slot._yhudVisibilitySuppressed = suppressed and true or nil
    if frameChanged then
        if suppressed then
            slot:Hide()
            AddPerformanceStat("resourceVisibilitySuppressions")
        else
            slot:Show()
            AddPerformanceStat("resourceVisibilityRestores")
        end
        AddViewWrite(false)
    end
    FinishPerformanceStat("resourceVisibilityMS", startedAt)
    return true
end

function View:SetResourceAuraIdentitySuppressed(monitorId, suppressed)
    local slot = self.byMonitor[monitorId]
    if not (slot and slot._yhudView == "resource"
        and slot.SetFilteredAuraIdentitySuppressed) then
        return false, 0, nil
    end

    suppressed = suppressed == true
    local auraChanged, restored, eligible =
        slot:SetFilteredAuraIdentitySuppressed(suppressed)
    local logicalSuppressed = slot._yhudAuraIdentitySuppressed == true
    if (tonumber(eligible) or 0) == 0
        and (suppressed or not logicalSuppressed) then
        return false, 0, slot._yhudGroupId
    end

    local logicalChanged = logicalSuppressed ~= suppressed
    slot._yhudAuraIdentitySuppressed = suppressed and true or nil
    local frameShown = slot:IsShown() == true
    local frameShouldShow = slot._yhudVisibilitySuppressed ~= true
        and not suppressed
    local frameChanged = frameShown ~= frameShouldShow
    if frameChanged then
        if frameShouldShow then
            slot:Show()
        else
            slot:Hide()
        end
        AddViewWrite(false)
    end
    return logicalChanged or frameChanged or auraChanged == true,
        tonumber(restored) or 0,
        slot._yhudGroupId
end

function View:ReleaseSlot(monitorId)
    if self.byMonitor[monitorId] and self.ReleaseIconSkin then self:ReleaseIconSkin(self.byMonitor[monitorId]) end
    if YHUD.PressFeedback and YHUD.PressFeedback.active then
        YHUD.PressFeedback:Release(self.byMonitor[monitorId])
    end
    local slot = self.byMonitor[monitorId]
    if not slot then return false end
    if YUI.GUI2.HideBarShadow then YUI.GUI2:HideBarShadow(slot) end
    if self.ClearBarProgress then self:ClearBarProgress(slot) end
    if self.SuspendBuffTimerStacks then self:SuspendBuffTimerStacks(slot) end
    if YHUD.AssistedHighlight then YHUD.AssistedHighlight:Release(slot) end
    if self.HideIconShadow then self:HideIconShadow(slot) end
    if YUI.GUI2 and YUI.GUI2.ReleaseAuraBarThresholds then
        YUI.GUI2:ReleaseAuraBarThresholds(slot)
    end
    if self.barStackThresholdOwners then self.barStackThresholdOwners[slot] = nil end
    slot._yhudBarStackPolicy = nil
    slot._yhudBarStackBaseColor = nil
    slot._yhudBarStackInputs = nil
    slot._yhudBarStackPreviewCount = nil
    local view = slot._yhudView
    local filteredAuraChainSlot =
        slot._yhudFilteredAuraChainCompatible == true
    local filteredAuraChainCarrier =
        slot._yhudFilteredAuraChainCarrier
    local groupId = slot._yhudGroupId
    local runtime = groupId and self.groups[groupId]
    local releaseStartedAt = view == "resource" and ProfileNowMS() or nil
    if view == "resource" then
        if I.ConfigurePlayerCast then I.ConfigurePlayerCast(slot, {}, {}) end
        slot._yhudResourceColorPolicy, slot._yhudResourceColorCurve = nil, nil
        slot._yhudResourceCurveInitialized, slot._yhudResourceCurveMax = nil, nil
        if runtime then runtime.fixedResourceGeometryReady = false end
        if self.InvalidateResourcePrefixLayout then
            self:InvalidateResourcePrefixLayout(groupId, false)
        end
    end
    I.CancelDesignTooltip(slot)
    -- Hide first so Blizzard AuraContainer children stop their event/dirty
    -- drivers before the resource value sinks are cleared. Resource slots
    -- retain their filtered Aura handles while pooled and resume them only
    -- after the next cold configuration pass.
    slot:Hide()
    self.byMonitor[monitorId] = nil
    self:ClearDesignSlot(slot)
    slot._yhudMonitorId = nil
    slot._yhudLogicalMonitorId = nil
    slot._yhudGroupId = nil
    slot._yhudResourceRowKey = nil
    slot._yhudIcon = nil
    slot._yhudName = nil
    slot._yhudStart = nil
    slot._yhudDuration = nil
    slot._yhudDurationMode = nil
    slot._yhudOpaqueRevision = nil
    slot._yhudFillColor = nil
    slot._yhudPlaced = nil
    slot._yhudSynthetic = nil
    slot._yhudDisplayCount = nil
    slot._yhudRawCountShown = nil
    slot._yhudCooldownSwipeDraw = nil
    slot._yhudCooldownSwipeReverse = nil
    slot._yhudNativePersistentPlaceholder = nil
    slot._yhudNativePlaceholderHidden = nil
    slot._yhudVisibilitySuppressed = nil
    slot._yhudLayoutParticipating = nil
    slot._yhudAuraIdentitySuppressed = nil
    slot._yhudDisplayName = nil
    slot._yhudGlowRuntime = nil
    slot._yhudNativeProcGlowLayoutDirty = nil
    slot._yhudTooltipEnabled = nil
    slot._yhudTooltipSpellID = nil
    slot._yhudTooltipItemID = nil
    slot._yhudTooltipSlotID = nil
    slot._yhudTooltipName = nil
    slot._yhudKeybindItemID, slot._yhudKeybindSpellID = nil, nil
    if slot._yhudKeybindText then
        if slot._yhudKeybindTextValue ~= "" then
            slot._yhudKeybindText:SetText("")
        end
        slot._yhudKeybindTextValue = ""
        slot._yhudKeybindTextState = {}
        slot._yhudKeybindOverlayShown = false
        slot._yhudKeybindOverlay:Hide()
        slot._yhudKeybindText:Hide()
    end
    I.SetSlotMouseInput(slot, false, false)
    if GUI2.ApplyIconDesaturation then
        GUI2:ApplyIconDesaturation(
            GetSlotIconTexture(slot),
            0,
            slot._yhudSharedIconState
        )
    end
    slot._yhudIconDesaturated = nil
    local iconSlot = slot.icon and slot.icon.icon and slot.icon or slot
    if iconSlot.SetIconBorderColor then iconSlot:SetIconBorderColor(nil) end
    if slot.SetCount then slot:SetCount(nil) end
    if slot.gui2Glow and slot.gui2Glow.SetGlowShown then
        slot.gui2Glow:SetGlowShown(false)
    end
    -- A dedicated chain slot remains below its restricted carrier while it is
    -- pooled. Keep the trusted geometry context so later layer refreshes never
    -- fall back to reading secret dimensions from the retained descendant.
    if not filteredAuraChainSlot
        and slot.gui2Glow and slot.gui2Glow._SetGlowLayoutContext then
        slot.gui2Glow:_SetGlowLayoutContext(false)
    end
    if slot.gui2Glow and slot.gui2Glow._SetGlowLayerContext then
        slot.gui2Glow:_SetGlowLayerContext(nil, nil)
    end
    if slot._yhudNativeProcGlow
        and GUI2.SetManagedProcGlowShown then
        GUI2:SetManagedProcGlowShown(
            slot._yhudNativeProcGlow,
            false
        )
    end
    slot._yhudGlowShown = nil
    if slot._yhudAuraStackSet then
        Glow:ReleaseStackSet(slot._yhudAuraStackSet)
        slot._yhudAuraStackSet = nil
    end
    if slot._yhudAuraStackGate then
        slot._yhudAuraStackGate.driver:SetValue(0)
        slot._yhudAuraStackGate.lastPublicValue = nil
    end
    slot._yhudAuraStackGate = nil
    if slot.gui2Glow and slot.gui2Glow.SetGlowClipParent then
        slot.gui2Glow:SetGlowClipParent(nil)
    end
    slot._yhudFilteredAuraGlow = nil
    slot._yhudGlowShape = nil
    slot._yhudNativeProcGlowShown = nil
    slot._yhudNativeProcGlowFrameLevel = nil
    slot._yhudNativeProcGlowFrameStrata = nil
    slot._yhudNativeProcGlowTarget = nil
    slot._yhudDesignSelected = nil
    slot._yhudGlowStyle = nil
    slot._yhudGlowSize = nil
    slot._yhudGlowLines = nil
    slot._yhudGlowThickness = nil
    slot._yhudGlowLength = nil
    slot._yhudGlowSpeed = nil
    slot._yhudGlowAlpha = nil
    slot._yhudGlowFalloff = nil
    slot._yhudGlowOffsetX = nil
    slot._yhudGlowOffsetY = nil
    slot._yhudGlowColorR = nil
    slot._yhudGlowColorG = nil
    slot._yhudGlowColorB = nil
    slot._yhudGlowColorA = nil
    if filteredAuraChainSlot then
        if filteredAuraChainCarrier then
            I.ClearManagedLayoutPoint(filteredAuraChainCarrier)
            filteredAuraChainCarrier:Hide()
        end
    else
        slot:ClearAllPoints()
    end
    ClearSlotDuration(slot)
    if slot.SetDurationName then slot:SetDurationName("") end
    if view == "resource" then
        self.freeResourceCount = self.freeResourceCount + 1
        self.freeResources[self.freeResourceCount] = slot
    elseif view == "bar" then
        self.freeBarCount = self.freeBarCount + 1
        self.freeBars[self.freeBarCount] = slot
    elseif view == "ring" then
        self.freeRingCount = self.freeRingCount + 1
        self.freeRings[self.freeRingCount] = slot
    elseif filteredAuraChainSlot then
        self.freeFilteredAuraChainIconCount =
            self.freeFilteredAuraChainIconCount + 1
        self.freeFilteredAuraChainIcons[
            self.freeFilteredAuraChainIconCount
        ] = slot
    else
        self.freeCount = self.freeCount + 1
        self.free[self.freeCount] = slot
    end
    AddMonitorStat("poolActive", -1)
    AddMonitorStat("poolFree", 1)
    if view == "resource" then
        AddPerformanceStat("resourceFullReleases")
        FinishPerformanceStat("resourceReleaseMS", releaseStartedAt)
    end
    return true
end

function View:ReleasePooledResourceAuraDisplays()
    local released = 0
    for index = 1, self.freeResourceCount do
        local slot = self.freeResources[index]
        if slot and slot.ReleaseFilteredAuraDisplays then
            slot:ReleaseFilteredAuraDisplays()
            released = released + 1
        end
    end
    return released
end

function View:ConfigureGroup(
    runtime,
    profile,
    group,
    projectionContext,
    presentationGroupPlan
)
    if not presentationGroupPlan then
        local plan = I.BeginPresentationPlan(profile, {
            preview = self.preview == true,
            projectionContext = projectionContext,
            resourceClassFile = self.resourcePreviewClassFile,
            resourceSpecID = self.resourcePreviewSpecID,
            resourceFormKey = self.resourcePreviewFormKey,
            focusedResourceId = self.resourceStylePreviewResourceId,
        })
        presentationGroupPlan = plan
            and I.FinishPresentationGroup(plan, runtime.id) or nil
    end
    local layoutType = group and group.layout
    local layout = presentationGroupPlan and presentationGroupPlan.layout
    if not layout and layoutType == "icons" then
        layout = GetIconLayout(profile, runtime.id)
        layout.layoutType = "icons"
        layout.view = "icon"
        layout.itemWidth = layout.iconWidth
        layout.itemHeight = layout.iconHeight
    elseif not layout and (layoutType == "bars" or layoutType == "rings") then
        layout = GetDurationLayout(profile, runtime.id, layoutType)
    elseif not layout and layoutType == "resource" then
        layout = GetResourceLayout(profile, runtime.id)
    elseif not layout then
        layout = {
            layoutType = layoutType,
            view = nil,
        }
    end

    local previousView = runtime.view
    local previousFilteredAuraProjectionStrategy =
        runtime.filteredAuraProjectionStrategy
    local nextLayoutMode, configuredLayoutMode, layoutModeOverrideReason
    local filteredAuraProjectionStrategy
    local filteredAuraProjectionReason
    local filteredAuraProjectionState
    if presentationGroupPlan then
        filteredAuraProjectionStrategy =
            presentationGroupPlan.filteredAuraProjectionStrategy
        filteredAuraProjectionReason =
            presentationGroupPlan.filteredAuraProjectionReason
        filteredAuraProjectionState =
            presentationGroupPlan.filteredAuraProjectionState
    elseif YHUD.GetFilteredAuraGroupProjectionStrategy then
        filteredAuraProjectionStrategy,
            filteredAuraProjectionReason,
            filteredAuraProjectionState =
            YHUD:GetFilteredAuraGroupProjectionStrategy(
                profile,
                group,
                self.preview == true,
                projectionContext
            )
    end
    if presentationGroupPlan then
        configuredLayoutMode = presentationGroupPlan.configuredLayoutMode
        layoutModeOverrideReason =
            presentationGroupPlan.layoutModeOverrideReason
        nextLayoutMode = presentationGroupPlan.effectiveLayoutMode
    else
        configuredLayoutMode = group.layoutMode == "fixed" and "fixed" or "auto"
        layoutModeOverrideReason = filteredAuraProjectionStrategy
                == YHUD.FILTERED_AURA_LAYOUT_MIXED_FIXED
            and filteredAuraProjectionReason or nil
        if layoutModeOverrideReason ==
            YHUD.FILTERED_AURA_FIXED_REASON_CONFIGURED_LAYOUT then
            layoutModeOverrideReason = nil
        end
        nextLayoutMode = layoutModeOverrideReason and "fixed"
            or configuredLayoutMode
    end
    local layoutModeChanged = runtime.layoutMode ~= nextLayoutMode
    local structural = ApplyRuntimeLayout(runtime, layout)
    if self.ClearBarShadows then self:ClearBarShadows(runtime) end
    runtime.group = group
    runtime.visibilityRule = group.visibility
    runtime.configuredLayoutMode = configuredLayoutMode
    runtime.layoutMode = nextLayoutMode
    runtime.layoutModeForced = layoutModeOverrideReason ~= nil
    runtime.layoutModeOverrideReason = layoutModeOverrideReason
    runtime.filteredAuraProjectionStrategy =
        filteredAuraProjectionStrategy
    runtime.filteredAuraProjectionState = filteredAuraProjectionState
    runtime.presentationGroupPlan = presentationGroupPlan
    runtime.enabled = group.enabled == true
        and LAYOUT_VIEWS[group.layout] ~= nil

    if previousFilteredAuraProjectionStrategy
        ~= filteredAuraProjectionStrategy then
        local releaseIds = {}
        for monitorId, slot in pairs(self.byMonitor) do
            if slot._yhudGroupId == runtime.id then
                local expectedChain =
                    self:ShouldUseFilteredAuraChainSlot(monitorId, runtime)
                if (slot._yhudFilteredAuraChainCompatible == true)
                    ~= expectedChain then
                    releaseIds[#releaseIds + 1] = monitorId
                end
            end
        end
        for index = 1, #releaseIds do
            self:ReleaseSlot(releaseIds[index])
        end
    end

    if layoutModeChanged or structural then
        runtime.fixedResourceGeometryReady = false
        if self.InvalidateResourcePrefixLayout then
            self:InvalidateResourcePrefixLayout(runtime.id, true)
        end
    end

    if previousView ~= runtime.view then
        if self.InvalidateResourcePrefixLayout then
            self:InvalidateResourcePrefixLayout(runtime.id, true)
        end
        local releaseIds = {}
        for monitorId, slot in pairs(self.byMonitor) do
            if slot._yhudGroupId == runtime.id then
                releaseIds[#releaseIds + 1] = monitorId
            end
        end
        for index = 1, #releaseIds do
            self:ReleaseSlot(releaseIds[index])
        end
    elseif structural then
        for _, slot in pairs(self.byMonitor) do
            if slot._yhudGroupId == runtime.id then
                self:ConfigureSlot(
                    slot,
                    runtime,
                    self.desiredMonitors[slot._yhudMonitorId]
                )
            end
        end
    end
    return structural
end
