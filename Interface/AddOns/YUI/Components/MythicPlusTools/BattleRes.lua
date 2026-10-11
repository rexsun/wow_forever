local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI or not YUI.IsRetail then return end

local GUI2 = YUI.GUI2
local Tools = YUI.MythicPlusTools
if not Tools or not Tools.RegisterSubFeature then return end

local L = Tools.L or (YUI.Locale and YUI.Locale:Get("MythicPlusTools")) or nil

local FEATURE_KEY = Tools.FEATURE_KEY or "MythicPlusTools"
local LAYOUT_ID = "yui.component.mythicPlusTools.battleRes"
local BATTLE_RES_SPELL_ID = 20484

local DEFAULT_SIZE = 36
local MIN_SIZE = 28
local MAX_SIZE = 72
local AUDIT_INTERVAL = 8
local PROBE_DELAYS = { 0.15, 0.5, 1.5, 3 }
local PREVIEW_REMAINING_OPTIONS = { 40, 65, 900 }

local FIELD_WIDTH = 300
local PREVIEW_BUTTON_WIDTH = 144
local FIELD_GAP = 14
local LABEL_WIDTH = 112
local INPUT_WIDTH = 48
local SECTION_WIDTH = 620
local COLUMN_GAP = 24
local LABEL_GAP = 10
local VALUE_GAP = 10
local COLUMN_WIDTH = math.floor((SECTION_WIDTH - COLUMN_GAP) / 2)
local BODY_WIDTH = COLUMN_WIDTH - LABEL_WIDTH - LABEL_GAP
local TEXT_SIZE_MIN = 8
local TEXT_SIZE_MAX = 28
local TEXT_OFFSET_MIN = -40
local TEXT_OFFSET_MAX = 40

local DEFAULT_TIMER_TEXT_COLOR = { 0.7686, 0.7686, 0.7686, 1 }
local DEFAULT_COUNT_TEXT_COLOR = { 0.1255, 1, 0.0863, 1 }
local DEFAULT_COOLDOWN_SWIPE_COLOR = { 0, 0, 0, 0.65 }
local FALLBACK_TEXT_COLOR = { 1, 1, 1, 1 }
local TOOLTIP_COUNT_READY_COLOR = "|cff00ff00"
local TOOLTIP_COUNT_EMPTY_COLOR = "|cffffffff"
local TOOLTIP_COLOR_END = "|r"

local BattleRes = {
    id = "battleRes",
    order = 10,
}

BattleRes.defaults = {
    battleResEnabled = true,
    battleResSize = DEFAULT_SIZE,
    cooldownSwipeEnabled = true,
    timerTextSize = 13,
    timerTextColor = DEFAULT_TIMER_TEXT_COLOR,
    timerTextOffsetX = 0,
    timerTextOffsetY = 0,
    countTextSize = 13,
    countTextColor = DEFAULT_COUNT_TEXT_COLOR,
    countTextOffsetX = -1,
    countTextOffsetY = 1,
}

local BattleResWidget = {}
local BattleResEventOwner = {}
local BattleResSettingsPreviewButton = nil

local featureActive = false
local battleResRuntimeActive = false
local battleResPreviewActive = false
local battleResLayoutPreview = false
local encounterActive = false

local battleResProbeToken = 0
local battleResClockToken = 0
local battleResAuditToken = 0
local battleResRefreshToken = 0

local function T(key, fallback)
    return (L and L[key]) or fallback or key
end

local function GetBattleResPreviewButtonLabel()
    if battleResPreviewActive then
        return T("settings.preview_stop", "关闭预览")
    end
    return T("settings.preview", "预览")
end

local function UpdateBattleResPreviewButton(button)
    button = button or BattleResSettingsPreviewButton
    if button and button.SetText then
        button:SetText(GetBattleResPreviewButtonLabel())
    end
end

local function Round(value)
    value = tonumber(value) or 0
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end

local function ClampNumber(value, minValue, maxValue, fallback)
    value = tonumber(value)
    if not value then value = fallback end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function ClampUnit(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback or 1 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function GetColorComponents(value, fallback)
    fallback = fallback or FALLBACK_TEXT_COLOR
    local source = type(value) == "table" and value or fallback
    return
        ClampUnit(source[1] or source.r, fallback[1] or fallback.r or 1),
        ClampUnit(source[2] or source.g, fallback[2] or fallback.g or 1),
        ClampUnit(source[3] or source.b, fallback[3] or fallback.b or 1),
        ClampUnit(source[4] or source.a, fallback[4] or fallback.a or 1)
end

local function NormalizeColor(value, fallback)
    local r, g, b, a = GetColorComponents(value, fallback)
    if type(value) == "table" and value ~= fallback then
        value[1], value[2], value[3], value[4] = r, g, b, a
        return value
    end
    return { r, g, b, a }
end

local function SetTextColor(fontString, color)
    if not fontString or not fontString.SetTextColor then return end
    local r, g, b, a = GetColorComponents(color)
    fontString:SetTextColor(r, g, b, a)
end

local function ScheduleAfter(delay, callback)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0, callback)
    else
        callback()
    end
end

local function ToLayoutPlacement(point, relative, relativePoint, x, y)
    return {
        version = 1,
        anchor = {
            point = point or "CENTER",
            relative = relative or "UIParent",
            relativePoint = relativePoint or point or "CENTER",
        },
        offset = { x = Round(x), y = Round(y) },
    }
end

local function GetDefaultPlacement()
    return ToLayoutPlacement("CENTER", "UIParent", "BOTTOM", -460, 339)
end

local function NormalizeDB(db)
    if type(db) ~= "table" then db = BattleRes.defaults end
    if db.battleResEnabled == nil then
        db.battleResEnabled = true
    else
        db.battleResEnabled = db.battleResEnabled == true
    end
    db.battleResSize = ClampNumber(db.battleResSize, MIN_SIZE, MAX_SIZE, DEFAULT_SIZE)
    db.cooldownSwipeEnabled = db.cooldownSwipeEnabled ~= false
    db.timerTextSize = ClampNumber(db.timerTextSize, TEXT_SIZE_MIN, TEXT_SIZE_MAX, BattleRes.defaults.timerTextSize)
    db.timerTextColor = NormalizeColor(db.timerTextColor, DEFAULT_TIMER_TEXT_COLOR)
    db.timerTextOffsetX = ClampNumber(db.timerTextOffsetX, TEXT_OFFSET_MIN, TEXT_OFFSET_MAX, BattleRes.defaults.timerTextOffsetX)
    db.timerTextOffsetY = ClampNumber(db.timerTextOffsetY, TEXT_OFFSET_MIN, TEXT_OFFSET_MAX, BattleRes.defaults.timerTextOffsetY)
    db.countTextSize = ClampNumber(db.countTextSize, TEXT_SIZE_MIN, TEXT_SIZE_MAX, BattleRes.defaults.countTextSize)
    db.countTextColor = NormalizeColor(db.countTextColor, DEFAULT_COUNT_TEXT_COLOR)
    db.countTextOffsetX = ClampNumber(db.countTextOffsetX, TEXT_OFFSET_MIN, TEXT_OFFSET_MAX, BattleRes.defaults.countTextOffsetX)
    db.countTextOffsetY = ClampNumber(db.countTextOffsetY, TEXT_OFFSET_MIN, TEXT_OFFSET_MAX, BattleRes.defaults.countTextOffsetY)
    return db
end

local function GetDB()
    return Tools:GetDB()
end

local function GetNow()
    return GetTime and GetTime() or 0
end

local function GetBattleResTooltipCount()
    local state = BattleResWidget.lastState
    if state and state.currentCharges ~= nil then
        return math.max(0, Round(state.currentCharges))
    end
    return 0
end

local function FormatBattleResTooltipCount(count)
    count = math.max(0, Round(count))
    local color = count > 0 and TOOLTIP_COUNT_READY_COLOR or TOOLTIP_COUNT_EMPTY_COLOR
    return color .. tostring(count) .. TOOLTIP_COLOR_END
end

local function ShowBattleResTooltip(owner)
    if not (owner and GameTooltip) then return end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(T("tooltip.available_battle_res", "可用战复次数：") .. FormatBattleResTooltipCount(GetBattleResTooltipCount()), 1, 1, 1)
    GameTooltip:Show()
end

local function HideBattleResTooltip(owner)
    if not GameTooltip then return end
    if owner and GameTooltip.IsOwned and not GameTooltip:IsOwned(owner) then return end
    YUI.HideGameTooltip()
end

local function RefreshBattleResTooltip()
    local frame = BattleResWidget.frame
    if not (frame and GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(frame)) then return end
    ShowBattleResTooltip(frame)
end

local function CancelBattleResProbe()
    battleResProbeToken = battleResProbeToken + 1
end

local function CancelBattleResClock()
    battleResClockToken = battleResClockToken + 1
    BattleResWidget.expiresAt = nil
end

local function CancelBattleResAudit()
    battleResAuditToken = battleResAuditToken + 1
end

local function CancelBattleResRefresh()
    battleResRefreshToken = battleResRefreshToken + 1
end

local function IsBattleResRuntimeEnabled()
    return featureActive and battleResRuntimeActive and GetDB().battleResEnabled == true
end

local function SetFontSize(fontString, size, flags)
    if not fontString or not fontString.GetFont or not fontString.SetFont then return end
    local font = fontString:GetFont()
    fontString:SetFont(font or STANDARD_TEXT_FONT, Round(size), flags)
end

local function CreateText(parent, text, size, colorKey, justify)
    if GUI2 and GUI2.CreateText then
        return GUI2:CreateText(parent, text, size, colorKey, justify)
    end
    return nil
end

local function ApplyDefaultPoint(frame)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOM", -460, 339)
end

local function IsLayoutEditing()
    return YUI.Layout and YUI.Layout.IsEditing and YUI.Layout:IsEditing()
end

local function CaptureBattleResPlacement(frame)
    if not frame or not UIParent or not frame.GetCenter or not UIParent.GetCenter then return nil end

    local frameX, frameY = frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if not frameX or not frameY or not parentX or not parentY then return nil end

    return ToLayoutPlacement("CENTER", "UIParent", "CENTER", frameX - parentX, frameY - parentY)
end

local function SaveBattleResPreviewPlacement(frame)
    if not (YUI.Layout and YUI.Layout.SetPlacement) then return end

    local placement = CaptureBattleResPlacement(frame)
    if placement then
        YUI.Layout:SetPlacement(LAYOUT_ID, placement, true)
    end
end

local function ShouldEnableBattleResMouse()
    local frame = BattleResWidget.frame
    if not frame then return false end
    if battleResLayoutPreview or IsLayoutEditing() then return false end
    if battleResPreviewActive then return true end
    return BattleResWidget.lastState ~= nil and frame.IsShown and frame:IsShown()
end

local function SetBattleResPreviewDragEnabled(enabled)
    local frame = BattleResWidget.frame
    if not frame or not frame.EnableMouse then return end

    if enabled and battleResPreviewActive and not battleResLayoutPreview and not IsLayoutEditing() then
        frame:EnableMouse(true)
        if frame.SetMovable then frame:SetMovable(true) end
        if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
    else
        if frame.StopMovingOrSizing then
            frame:StopMovingOrSizing()
        end
        frame:EnableMouse(ShouldEnableBattleResMouse())
    end
end

local function CanDragBattleResPreview()
    if not battleResPreviewActive or battleResLayoutPreview or IsLayoutEditing() then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    return true
end

local function OnBattleResPreviewDragStart(frame)
    if CanDragBattleResPreview() and frame and frame.StartMoving then
        frame:StartMoving()
    end
end

local function OnBattleResPreviewDragStop(frame)
    if frame and frame.StopMovingOrSizing then
        frame:StopMovingOrSizing()
    end

    if battleResPreviewActive and not battleResLayoutPreview and not IsLayoutEditing() then
        SaveBattleResPreviewPlacement(frame)
    end
end

local function ApplyBattleResSize()
    local frame = BattleResWidget.frame
    if not frame then return end

    local db = GetDB()
    local size = ClampNumber(db.battleResSize, MIN_SIZE, MAX_SIZE, DEFAULT_SIZE)

    frame:SetSize(size, size)

    if BattleResWidget.icon then
        BattleResWidget.icon:ClearAllPoints()
        BattleResWidget.icon:SetAllPoints(frame)
    end

    if BattleResWidget.cooldown then
        BattleResWidget.cooldown:ClearAllPoints()
        BattleResWidget.cooldown:SetAllPoints(BattleResWidget.icon or frame)
        if BattleResWidget.cooldown.SetFrameLevel and frame.GetFrameLevel then
            BattleResWidget.cooldown:SetFrameLevel((frame:GetFrameLevel() or 0) + 1)
        end
    end

    local cooldownLevel = BattleResWidget.cooldown and BattleResWidget.cooldown.GetFrameLevel and BattleResWidget.cooldown:GetFrameLevel() or (frame.GetFrameLevel and frame:GetFrameLevel() or 0)

    if BattleResWidget.timerTextLayer then
        BattleResWidget.timerTextLayer:ClearAllPoints()
        BattleResWidget.timerTextLayer:SetAllPoints(frame)
        if BattleResWidget.timerTextLayer.SetFrameLevel then
            BattleResWidget.timerTextLayer:SetFrameLevel(cooldownLevel + 10)
        end
    end

    if BattleResWidget.countTextLayer then
        BattleResWidget.countTextLayer:ClearAllPoints()
        BattleResWidget.countTextLayer:SetAllPoints(frame)
        if BattleResWidget.countTextLayer.SetFrameLevel then
            BattleResWidget.countTextLayer:SetFrameLevel(cooldownLevel + 12)
        end
    end

    if BattleResWidget.countText then
        BattleResWidget.countText:ClearAllPoints()
        BattleResWidget.countText:SetPoint("BOTTOMRIGHT", BattleResWidget.countTextLayer or frame, "BOTTOMRIGHT", db.countTextOffsetX, db.countTextOffsetY)
        SetFontSize(BattleResWidget.countText, db.countTextSize, "OUTLINE")
        SetTextColor(BattleResWidget.countText, db.countTextColor)
        if BattleResWidget.countText.SetDrawLayer then
            BattleResWidget.countText:SetDrawLayer("OVERLAY", 8)
        end
    end

    if BattleResWidget.timerText then
        BattleResWidget.timerText:ClearAllPoints()
        BattleResWidget.timerText:SetPoint("CENTER", BattleResWidget.timerTextLayer or frame, "CENTER", db.timerTextOffsetX, db.timerTextOffsetY)
        SetFontSize(BattleResWidget.timerText, db.timerTextSize, "OUTLINE")
        SetTextColor(BattleResWidget.timerText, db.timerTextColor)
        if BattleResWidget.timerText.SetDrawLayer then
            BattleResWidget.timerText:SetDrawLayer("OVERLAY", 7)
        end
    end

    if YUI.Layout and YUI.Layout.RefreshFrame then
        YUI.Layout:RefreshFrame(LAYOUT_ID)
    end
end

local function ClearBattleResCooldown()
    local cooldown = BattleResWidget.cooldown
    if not cooldown then return end

    if cooldown.Clear then
        cooldown:Clear()
    elseif cooldown.SetCooldown then
        cooldown:SetCooldown(0, 0)
    end
    cooldown:Hide()
end

local function ApplyBattleResCooldownAppearance(state)
    local cooldown = BattleResWidget.cooldown
    if not cooldown then return end

    local db = GetDB()
    local enabled = db.cooldownSwipeEnabled == true
    local hasAvailableCharge = enabled and state and tonumber(state.currentCharges) and tonumber(state.currentCharges) > 0
    local color = DEFAULT_COOLDOWN_SWIPE_COLOR

    if cooldown.SetDrawSwipe then cooldown:SetDrawSwipe(enabled and not hasAvailableCharge) end
    if cooldown.SetDrawEdge then cooldown:SetDrawEdge(hasAvailableCharge == true) end
    if cooldown.SetSwipeColor then cooldown:SetSwipeColor(color[1], color[2], color[3], color[4]) end
end

local function SetBattleResCooldown(state, forceReset)
    local cooldown = BattleResWidget.cooldown
    if not cooldown then return end
    if not state then
        ClearBattleResCooldown()
        return
    end

    local startTime = state.cooldownStartTime
    local duration = state.cooldownDuration
    if not startTime or not duration or startTime <= 0 or duration <= 0 then
        ClearBattleResCooldown()
        return
    end

    if forceReset and cooldown.Clear then
        cooldown:Clear()
    end

    ApplyBattleResCooldownAppearance(state)
    if GetDB().cooldownSwipeEnabled ~= true then
        if cooldown.SetCooldown then cooldown:SetCooldown(0, 0) end
        cooldown:Hide()
        return
    end

    cooldown:Show()
    if cooldown.SetCooldown then
        cooldown:SetCooldown(startTime, duration, state.chargeModRate or 1)
    end
    ApplyBattleResCooldownAppearance(state)
end

local function RefreshBattleResCooldownVisual()
    local state = BattleResWidget.lastState
    local hasRecoveringCharge = state and state.expiresAt and state.currentCharges and state.maxCharges and state.currentCharges < state.maxCharges

    if hasRecoveringCharge and state.expiresAt > GetNow() then
        SetBattleResCooldown(state, true)
    else
        ApplyBattleResCooldownAppearance()
        ClearBattleResCooldown()
    end
end

local function FormatRemainingSeconds(remaining)
    local totalSeconds = math.ceil(math.max(0, tonumber(remaining) or 0))
    if totalSeconds < 60 then
        return tostring(totalSeconds)
    end

    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = totalSeconds % 60

    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, seconds)
    end

    return string.format("%d:%02d", minutes, seconds)
end

local function UpdateBattleResCountdown(token)
    if token ~= battleResClockToken then return end
    if not BattleResWidget.frame or not BattleResWidget.frame:IsShown() or not BattleResWidget.expiresAt then return end

    local remaining = BattleResWidget.expiresAt - GetNow()
    if remaining <= 0 then
        if BattleResWidget.timerText then
            BattleResWidget.timerText:SetText("")
        end
        return
    end

    if BattleResWidget.timerText then
        BattleResWidget.timerText:SetText(FormatRemainingSeconds(remaining))
    end

    local visibleSeconds = math.ceil(remaining)
    local delay = remaining - (visibleSeconds - 1)
    if delay < 0.05 then delay = 0.05 end
    if delay > 1 then delay = 1 end

    ScheduleAfter(delay, function()
        UpdateBattleResCountdown(token)
    end)
end

local function StartBattleResClock(expiresAt)
    CancelBattleResClock()
    if not expiresAt or expiresAt <= GetNow() then
        if BattleResWidget.timerText then
            BattleResWidget.timerText:SetText("")
        end
        return
    end

    BattleResWidget.expiresAt = expiresAt
    local token = battleResClockToken
    UpdateBattleResCountdown(token)
end

local function OpenBattleResSettings()
    if YUI.Settings and YUI.Settings.OpenComponentFeature then
        YUI.Settings:OpenComponentFeature(FEATURE_KEY)
        return true
    end
    if YUI.Components and YUI.Components.OpenFeatureSettings then
        YUI.Components:OpenFeatureSettings(FEATURE_KEY)
        return true
    end
    return false
end

local function RegisterBattleResLayout()
    local frame = BattleResWidget.frame
    if not frame then return end

    if not (YUI.Layout and YUI.Layout.RegisterFrame) then
        ApplyDefaultPoint(frame)
        return
    end

    YUI.Layout:RegisterFrame(LAYOUT_ID, {
        frame = frame,
        title = T("layout.battle_res", "战复监控"),
        category = "component",
        defaultPlacement = GetDefaultPlacement,
        movable = true,
        snap = true,
        anchorTargets = { "UIParent" },
        minWidth = MIN_SIZE,
        minHeight = MIN_SIZE,
        isEnabled = function()
            return featureActive and GetDB().battleResEnabled == true
        end,
        openPluginSettings = OpenBattleResSettings,
        onEnterEditMode = function()
            if not IsBattleResRuntimeEnabled() and not battleResPreviewActive then return end
            SetBattleResPreviewDragEnabled(false)
            if battleResPreviewActive then return end

            battleResLayoutPreview = true
            CancelBattleResProbe()
            CancelBattleResClock()
            frame:Show()
            if BattleResWidget.countText then BattleResWidget.countText:SetText("2") end
            if BattleResWidget.timerText then BattleResWidget.timerText:SetText("") end
            ClearBattleResCooldown()
        end,
        onExitEditMode = function()
            battleResLayoutPreview = false
            if battleResPreviewActive then
                SetBattleResPreviewDragEnabled(true)
                return
            end

            CancelBattleResClock()
            CancelBattleResRefresh()
            ScheduleAfter(0, function()
                if featureActive and battleResRuntimeActive then
                    CancelBattleResRefresh()
                    if BattleRes and BattleRes.RefreshBattleResState then
                        BattleRes.RefreshBattleResState("layout-exit")
                    end
                end
            end)
        end,
    })
end

local function EnsureBattleResWidget()
    if BattleResWidget.frame then
        ApplyBattleResSize()
        return BattleResWidget.frame
    end
    if not CreateFrame or not UIParent then return nil end

    GUI2 = YUI.GUI2
    if not (GUI2 and GUI2.Application and GUI2.Application.CreateCooldownIcon) then
        return nil
    end

    local frame = GUI2.Application:CreateCooldownIcon(UIParent, {
        size = DEFAULT_SIZE,
        icon = (YUI.API and YUI.API.Spell and YUI.API.Spell.GetTexture and YUI.API.Spell.GetTexture(BATTLE_RES_SPELL_ID)) or "Interface\\Icons\\Spell_Nature_Reincarnation",
        shape = "square",
    })
    if not frame then return nil end
    if frame.SetFrameStrata then frame:SetFrameStrata("MEDIUM") end
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    if frame.SetMovable then frame:SetMovable(true) end
    if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
    if frame.SetScript then
        frame:SetScript("OnDragStart", OnBattleResPreviewDragStart)
        frame:SetScript("OnDragStop", OnBattleResPreviewDragStop)
        frame:SetScript("OnEnter", ShowBattleResTooltip)
        frame:SetScript("OnLeave", HideBattleResTooltip)
    end
    if frame.EnableMouse then frame:EnableMouse(false) end

    frame:Hide()
    BattleResWidget.frame = frame
    BattleResWidget.icon = frame.icon
    BattleResWidget.cooldown = frame.cooldown

    local cooldown = BattleResWidget.cooldown
    if cooldown then
        cooldown:SetDrawEdge(false)
        if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(true) end
        cooldown.noCooldownCount = true
        ApplyBattleResCooldownAppearance()
        cooldown:Hide()
    end

    local timerTextLayer = GUI2:CreateFrame(frame, { allPoints = true })
    if timerTextLayer and timerTextLayer.EnableMouse then timerTextLayer:EnableMouse(false) end
    BattleResWidget.timerTextLayer = timerTextLayer

    local countTextLayer = GUI2:CreateFrame(frame, { allPoints = true })
    if countTextLayer and countTextLayer.EnableMouse then countTextLayer:EnableMouse(false) end
    BattleResWidget.countTextLayer = countTextLayer

    local countText = CreateText(countTextLayer or frame, "", BattleRes.defaults.countTextSize, "color.text.primary", "RIGHT")
    if countText then
        SetTextColor(countText, DEFAULT_COUNT_TEXT_COLOR)
        countText:SetShadowColor(0, 0, 0, 0.9)
        countText:SetShadowOffset(1, -1)
    end
    BattleResWidget.countText = countText

    local timerText = CreateText(timerTextLayer or frame, "", BattleRes.defaults.timerTextSize, "color.text.primary", "CENTER")
    if timerText then
        SetTextColor(timerText, DEFAULT_TIMER_TEXT_COLOR)
        timerText:SetShadowColor(0, 0, 0, 0.9)
        timerText:SetShadowOffset(1, -1)
    end
    BattleResWidget.timerText = timerText

    ApplyBattleResSize()
    RegisterBattleResLayout()
    return frame
end

local function HideBattleResWidget()
    BattleResWidget.lastState = nil
    CancelBattleResClock()
    HideBattleResTooltip(BattleResWidget.frame)
    if BattleResWidget.timerText then
        BattleResWidget.timerText:SetText("")
    end
    ClearBattleResCooldown()
    if BattleResWidget.frame and not battleResLayoutPreview then
        BattleResWidget.frame:Hide()
    end
    SetBattleResPreviewDragEnabled(false)
end

local function IsChallengeModeActive(instanceType, difficultyID)
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive then
        local active = C_ChallengeMode.IsChallengeModeActive()
        if active ~= nil then
            return active == true
        end
    end
    return instanceType == "party" and difficultyID == 8
end

local function IsRaidEncounterActive(instanceType)
    if instanceType ~= "raid" then return false end
    if encounterActive then return true end
    if IsEncounterInProgress then
        return IsEncounterInProgress() == true
    end
    return false
end

local function GetBattleResContext()
    if not featureActive or GetDB().battleResEnabled ~= true then
        return false, nil
    end

    local _, instanceType, difficultyID = GetInstanceInfo()
    if IsChallengeModeActive(instanceType, difficultyID) then
        return true, "mythic_plus"
    end

    if IsRaidEncounterActive(instanceType) then
        return true, "raid_boss"
    end

    return false, nil
end

local function ReadBattleResCharges()
    local Spell = YUI.API and YUI.API.Spell
    if not (Spell and Spell.GetCharges) then return nil end

    local charges = Spell.GetCharges(BATTLE_RES_SPELL_ID)
    if not charges then return nil end

    charges.currentCharges = tonumber(charges.currentCharges)
    charges.maxCharges = tonumber(charges.maxCharges)
    charges.cooldownStartTime = tonumber(charges.cooldownStartTime) or 0
    charges.cooldownDuration = tonumber(charges.cooldownDuration) or 0
    charges.chargeModRate = tonumber(charges.chargeModRate) or 1

    if not charges.currentCharges or not charges.maxCharges or charges.maxCharges <= 0 then
        return nil
    end

    return charges
end

local function BuildBattleResState(charges)
    if not charges then return nil end

    local maxCharges = math.max(1, charges.maxCharges or 1)
    local currentCharges = math.min(maxCharges, math.max(0, charges.currentCharges or 0))
    local cooldownStartTime = charges.cooldownStartTime or 0
    local cooldownDuration = charges.cooldownDuration or 0
    local expiresAt

    if currentCharges < maxCharges and cooldownStartTime > 0 and cooldownDuration > 0 then
        expiresAt = cooldownStartTime + cooldownDuration
    end

    return {
        visible = true,
        currentCharges = currentCharges,
        maxCharges = maxCharges,
        cooldownStartTime = cooldownStartTime,
        cooldownDuration = cooldownDuration,
        chargeModRate = charges.chargeModRate or 1,
        expiresAt = expiresAt,
    }
end

local function RenderBattleResState(state)
    if not state or not state.visible then
        HideBattleResWidget()
        return
    end

    local frame = EnsureBattleResWidget()
    if not frame then return end

    BattleResWidget.lastState = state
    frame:Show()
    SetBattleResPreviewDragEnabled(battleResPreviewActive)

    if BattleResWidget.countText then
        BattleResWidget.countText:SetText(tostring(state.currentCharges or 0))
    end

    local hasRecoveringCharge = state.expiresAt and state.currentCharges and state.maxCharges and state.currentCharges < state.maxCharges
    if hasRecoveringCharge and state.expiresAt > GetNow() then
        SetBattleResCooldown(state)
        StartBattleResClock(state.expiresAt)
    else
        CancelBattleResClock()
        if BattleResWidget.timerText then
            BattleResWidget.timerText:SetText("")
        end
        ClearBattleResCooldown()
    end

    if YUI.Layout and YUI.Layout.RefreshFrame then
        YUI.Layout:RefreshFrame(LAYOUT_ID)
    end
    RefreshBattleResTooltip()
end

function BattleRes.RefreshBattleResState(reason, knownCharges)
    if battleResPreviewActive or battleResLayoutPreview then
        return
    end

    if not IsBattleResRuntimeEnabled() then
        CancelBattleResProbe()
        HideBattleResWidget()
        return
    end

    local validContext = GetBattleResContext()
    if not validContext then
        CancelBattleResProbe()
        HideBattleResWidget()
        return
    end

    local charges = knownCharges or ReadBattleResCharges()
    if not charges then
        HideBattleResWidget()
        if reason ~= "probe" then
            BattleRes.ScheduleBattleResProbe(reason or "missing")
        end
        return
    end

    CancelBattleResProbe()
    RenderBattleResState(BuildBattleResState(charges))
end

function BattleRes.ScheduleBattleResProbe(reason)
    if not IsBattleResRuntimeEnabled() then return end

    CancelBattleResProbe()
    local token = battleResProbeToken
    local attempt = 1

    local function Probe()
        if token ~= battleResProbeToken then return end
        if not IsBattleResRuntimeEnabled() then return end

        local validContext = GetBattleResContext()
        if not validContext then return end

        local charges = ReadBattleResCharges()
        if charges then
            BattleRes.RefreshBattleResState("probe", charges)
            return
        end

        attempt = attempt + 1
        local delay = PROBE_DELAYS[attempt]
        if delay then
            ScheduleAfter(delay, Probe)
        end
    end

    ScheduleAfter(PROBE_DELAYS[attempt], Probe)
end

local function StartBattleResAudit()
    CancelBattleResAudit()
    local token = battleResAuditToken

    local function Audit()
        if token ~= battleResAuditToken then return end
        if not IsBattleResRuntimeEnabled() then return end

        local validContext = GetBattleResContext()
        if validContext then
            BattleRes.RefreshBattleResState("audit")
        end

        ScheduleAfter(AUDIT_INTERVAL, Audit)
    end

    ScheduleAfter(AUDIT_INTERVAL, Audit)
end

local function StopBattleResPreview()
    battleResPreviewActive = false
    SetBattleResPreviewDragEnabled(false)
    UpdateBattleResPreviewButton()
    CancelBattleResClock()
    if battleResRuntimeActive then
        BattleRes.RefreshBattleResState("preview-stop")
    else
        HideBattleResWidget()
    end
end

local function ShowBattleResPreview()
    EnsureBattleResWidget()
    if not BattleResWidget.frame then return end

    battleResPreviewActive = true
    SetBattleResPreviewDragEnabled(true)
    UpdateBattleResPreviewButton()
    CancelBattleResProbe()

    local now = GetNow()
    local remaining = PREVIEW_REMAINING_OPTIONS[math.random(#PREVIEW_REMAINING_OPTIONS)] or 40
    local duration = math.max(300, remaining)
    RenderBattleResState({
        visible = true,
        currentCharges = 2,
        maxCharges = 3,
        cooldownStartTime = now - (duration - remaining),
        cooldownDuration = duration,
        chargeModRate = 1,
        expiresAt = now + remaining,
    })
end

local function ToggleBattleResPreview(button)
    BattleResSettingsPreviewButton = button or BattleResSettingsPreviewButton
    if battleResPreviewActive then
        StopBattleResPreview()
    else
        ShowBattleResPreview()
    end
    UpdateBattleResPreviewButton(BattleResSettingsPreviewButton)
end

local function OnBattleResEvent(event)
    if event == "ENCOUNTER_START" then
        encounterActive = true
    elseif event == "ENCOUNTER_END" then
        encounterActive = false
    elseif event == "PLAYER_ENTERING_WORLD" then
        encounterActive = IsEncounterInProgress and IsEncounterInProgress() == true or false
    end

    CancelBattleResRefresh()
    local token = battleResRefreshToken
    ScheduleAfter(0, function()
        if token == battleResRefreshToken then
            BattleRes.RefreshBattleResState(event)
        end
    end)
end

local function BindBattleResEvents()
    if not (YUI.Event and YUI.Event.On) then return end

    YUI.Event:OffOwner(BattleResEventOwner)
    YUI.Event:On("SPELL_UPDATE_CHARGES", OnBattleResEvent, BattleResEventOwner)
    YUI.Event:On("CHALLENGE_MODE_START", OnBattleResEvent, BattleResEventOwner)
    YUI.Event:On("CHALLENGE_MODE_COMPLETED", OnBattleResEvent, BattleResEventOwner)
    YUI.Event:On("ENCOUNTER_START", OnBattleResEvent, BattleResEventOwner)
    YUI.Event:On("ENCOUNTER_END", OnBattleResEvent, BattleResEventOwner)
    YUI.Event:On("PLAYER_ENTERING_WORLD", OnBattleResEvent, BattleResEventOwner)
    YUI.Event:On("ZONE_CHANGED_NEW_AREA", OnBattleResEvent, BattleResEventOwner)
end

local function EnableBattleResRuntime()
    if battleResRuntimeActive then
        BattleRes.RefreshBattleResState("enable-refresh")
        return
    end

    battleResRuntimeActive = true
    encounterActive = IsEncounterInProgress and IsEncounterInProgress() == true or false
    EnsureBattleResWidget()
    BindBattleResEvents()
    StartBattleResAudit()
    BattleRes.RefreshBattleResState("enable")
end

local function DisableBattleResRuntime()
    battleResRuntimeActive = false
    battleResPreviewActive = false
    battleResLayoutPreview = false
    SetBattleResPreviewDragEnabled(false)
    if YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(BattleResEventOwner)
    end
    CancelBattleResProbe()
    CancelBattleResClock()
    CancelBattleResAudit()
    CancelBattleResRefresh()
    HideBattleResWidget()
end

local function RefreshBattleResRuntime()
    if featureActive and GetDB().battleResEnabled == true then
        EnableBattleResRuntime()
    else
        DisableBattleResRuntime()
    end
end

function BattleRes:OnSettingsLeave()
    if battleResPreviewActive then StopBattleResPreview() end
end

function BattleRes:NormalizeDB(db)
    return NormalizeDB(db)
end

function BattleRes:RefreshRuntime()
    RefreshBattleResRuntime()
end

function BattleRes:OnFeatureToggle(enable)
    featureActive = enable == true
    RefreshBattleResRuntime()
end

local function AddAlignedFieldGroup(options, label, fields, layout)
    layout = type(layout) == "table" and layout or {}
    if layout.hideDivider ~= true then
        options[#options + 1] = { type = "divider", label = label, alignLeft = true, width = SECTION_WIDTH }
    end
    options[#options + 1] = {
        type = "custom",
        retainedFields = fields,
        width = SECTION_WIDTH,
        render = function(parent, x, y, width)
            local Settings = YUI.Settings
            if not (Settings and Settings.RenderAlignedFields) then
                return SECTION_WIDTH, 1
            end

            local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                x = x,
                y = y,
                width = math.min(width or SECTION_WIDTH, SECTION_WIDTH),
                columns = layout.columns or 2,
                labelPosition = layout.labelPosition or "top",
                columnGap = layout.columnGap or COLUMN_GAP,
                labelWidth = layout.labelWidth or LABEL_WIDTH,
                labelGap = layout.labelGap or LABEL_GAP,
                bodyWidth = layout.bodyWidth or BODY_WIDTH,
                valueWidth = layout.valueWidth or INPUT_WIDTH,
                valueGap = layout.valueGap or VALUE_GAP,
                rowHeight = layout.rowHeight or 32,
                rowGap = layout.rowGap or 10,
                fields = fields,
            })
            return gridWidth, gridHeight
        end,
    }
end

function BattleRes:BuildOptions(db)
    db = db or GetDB()

    local options = {}

    AddAlignedFieldGroup(options, T("settings.battle_res", "战复监控"), {
        {
            type = "checkbox",
            label = T("settings.battle_res_enabled", "启用战复监控"),
            settingsToggle = "battleRes",
            searchKey = "settings.battle_res_enabled",
            get = function() return db.battleResEnabled == true end,
            set = function(value)
                db.battleResEnabled = value == true
                if not db.battleResEnabled then
                    StopBattleResPreview()
                end
                RefreshBattleResRuntime()
            end,
        },
        {
            type = "button",
            label = "",
            text = GetBattleResPreviewButtonLabel(),
            bodyWidth = PREVIEW_BUTTON_WIDTH,
            onClick = ToggleBattleResPreview,
        },
    }, { hideDivider = true })

    AddAlignedFieldGroup(options, T("settings.battle_res_icon", "图标"), {
        {
            type = "slider",
            label = T("settings.icon_size", "图标尺寸"),
            min = MIN_SIZE,
            max = MAX_SIZE,
            step = 1,
            get = function() return db.battleResSize end,
            set = function(value)
                db.battleResSize = ClampNumber(value, MIN_SIZE, MAX_SIZE, DEFAULT_SIZE)
                ApplyBattleResSize()
                if battleResRuntimeActive then
                    BattleRes.RefreshBattleResState("settings-size")
                end
            end,
        },
        {
            type = "checkbox",
            label = T("settings.cooldown_swipe_enabled", "启用冷却刷子"),
            get = function() return db.cooldownSwipeEnabled == true end,
            set = function(value)
                db.cooldownSwipeEnabled = value == true
                RefreshBattleResCooldownVisual()
            end,
        },
    })

    AddAlignedFieldGroup(options, T("settings.battle_res_timer_text", "倒计时文本"), {
        {
            type = "slider",
            label = T("settings.timer_text_size", "倒计时尺寸"),
            min = TEXT_SIZE_MIN,
            max = TEXT_SIZE_MAX,
            step = 1,
            get = function() return db.timerTextSize end,
            set = function(value)
                db.timerTextSize = ClampNumber(value, TEXT_SIZE_MIN, TEXT_SIZE_MAX, BattleRes.defaults.timerTextSize)
                ApplyBattleResSize()
            end,
        },
        {
            type = "color",
            label = T("settings.timer_text_color", "倒计时颜色"),
            layoutPreset = "compactColor",
            hasAlpha = true,
            get = function() return db.timerTextColor end,
            default = DEFAULT_TIMER_TEXT_COLOR,
            set = function(value)
                db.timerTextColor = NormalizeColor(value, DEFAULT_TIMER_TEXT_COLOR)
                ApplyBattleResSize()
            end,
        },
        {
            type = "slider",
            label = T("settings.timer_text_offset_x", "倒计时X"),
            min = TEXT_OFFSET_MIN,
            max = TEXT_OFFSET_MAX,
            step = 1,
            get = function() return db.timerTextOffsetX end,
            set = function(value)
                db.timerTextOffsetX = ClampNumber(value, TEXT_OFFSET_MIN, TEXT_OFFSET_MAX, BattleRes.defaults.timerTextOffsetX)
                ApplyBattleResSize()
            end,
        },
        {
            type = "slider",
            label = T("settings.timer_text_offset_y", "倒计时Y"),
            min = TEXT_OFFSET_MIN,
            max = TEXT_OFFSET_MAX,
            step = 1,
            get = function() return db.timerTextOffsetY end,
            set = function(value)
                db.timerTextOffsetY = ClampNumber(value, TEXT_OFFSET_MIN, TEXT_OFFSET_MAX, BattleRes.defaults.timerTextOffsetY)
                ApplyBattleResSize()
            end,
        },
    })

    AddAlignedFieldGroup(options, T("settings.battle_res_count_text", "层数文本"), {
        {
            type = "slider",
            label = T("settings.count_text_size", "层数尺寸"),
            min = TEXT_SIZE_MIN,
            max = TEXT_SIZE_MAX,
            step = 1,
            get = function() return db.countTextSize end,
            set = function(value)
                db.countTextSize = ClampNumber(value, TEXT_SIZE_MIN, TEXT_SIZE_MAX, BattleRes.defaults.countTextSize)
                ApplyBattleResSize()
            end,
        },
        {
            type = "color",
            label = T("settings.count_text_color", "层数颜色"),
            layoutPreset = "compactColor",
            hasAlpha = true,
            get = function() return db.countTextColor end,
            default = DEFAULT_COUNT_TEXT_COLOR,
            set = function(value)
                db.countTextColor = NormalizeColor(value, DEFAULT_COUNT_TEXT_COLOR)
                ApplyBattleResSize()
            end,
        },
        {
            type = "slider",
            label = T("settings.count_text_offset_x", "层数X"),
            min = TEXT_OFFSET_MIN,
            max = TEXT_OFFSET_MAX,
            step = 1,
            get = function() return db.countTextOffsetX end,
            set = function(value)
                db.countTextOffsetX = ClampNumber(value, TEXT_OFFSET_MIN, TEXT_OFFSET_MAX, BattleRes.defaults.countTextOffsetX)
                ApplyBattleResSize()
            end,
        },
        {
            type = "slider",
            label = T("settings.count_text_offset_y", "层数Y"),
            min = TEXT_OFFSET_MIN,
            max = TEXT_OFFSET_MAX,
            step = 1,
            get = function() return db.countTextOffsetY end,
            set = function(value)
                db.countTextOffsetY = ClampNumber(value, TEXT_OFFSET_MIN, TEXT_OFFSET_MAX, BattleRes.defaults.countTextOffsetY)
                ApplyBattleResSize()
            end,
        },
    })

    return options
end

Tools.BattleRes = BattleRes
Tools:RegisterSubFeature(BattleRes)
