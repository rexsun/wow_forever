local YUI = _G.YUI
local View = YUI and YUI.YHUD and YUI.YHUD.View
local I = View and View._internal
if not (I and YUI.IsForever) then return end

local Event = YUI.Event
local GUI2 = YUI.GUI2
local Security = YUI.API.Security
local CAST_SUCCEEDED = "UNIT_SPELLCAST_SUCCEEDED"
local WINDOW = 5
local MANA = Enum.PowerType.Mana
local owner = {}
local slots = {}
local visibleCount = 0
local listener, expiry, duration, endsAt

local function HasManaCost(spellID)
    if Security.IsSecretValue(spellID) or type(spellID) ~= "number" then
        return false
    end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if not ok or not Security.CanAccessTable(costs) then return false end
    for _, cost in ipairs(costs) do
        if Security.CanAccessTable(cost)
            and not Security.IsSecretValue(cost.type) and cost.type == MANA then
            local amount = cost.cost
            return Security.IsSecretValue(amount) or (type(amount) == "number" and amount > 0)
        end
    end
    return false
end

local function HideSpark(slot)
    local overlay = slot._yhudManaRegenOverlay
    if overlay then overlay:Hide() end
end

local function LayoutSpark(slot, overlay)
    local vertical = slot.orientation == "vertical"
    local reverse = slot.gui2ResourceFillDirection == "reverse"
    if overlay.vertical == vertical and overlay.reverse == reverse then return false end
    overlay.vertical, overlay.reverse = vertical, reverse
    overlay:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    overlay:SetReverseFill(reverse)
    local marker, fill = overlay.marker, overlay:GetStatusBarTexture()
    local thickness = GUI2:GetPixelSize(slot.track, 2, 2)
    marker:ClearAllPoints()
    if vertical then
        marker:SetPoint("LEFT", fill, reverse and "BOTTOMLEFT" or "TOPLEFT")
        marker:SetPoint("RIGHT", fill, reverse and "BOTTOMRIGHT" or "TOPRIGHT")
        marker:SetHeight(thickness)
    else
        marker:SetPoint("TOP", fill, reverse and "TOPLEFT" or "TOPRIGHT")
        marker:SetPoint("BOTTOM", fill, reverse and "BOTTOMLEFT" or "BOTTOMRIGHT")
        marker:SetWidth(thickness)
    end
    return true
end

local function ShowSpark(slot)
    local overlay = slot._yhudManaRegenOverlay
    if not overlay then
        overlay = CreateFrame("StatusBar", nil, slot.track)
        overlay:SetAllPoints(slot.track)
        overlay:SetFrameLevel(slot.track:GetFrameLevel() + 11)
        overlay:SetClipsChildren(true)
        overlay:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        overlay:GetStatusBarTexture():SetAlpha(0)
        overlay:SetMinMaxValues(0, 1)
        overlay.marker = overlay:CreateTexture(nil, "OVERLAY")
        overlay.marker:SetColorTexture(GUI2:GetColor("color.text.primary"))
        slot._yhudManaRegenOverlay = overlay
    end
    LayoutSpark(slot, overlay)
    overlay:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate,
        Enum.StatusBarTimerDirection.ElapsedTime)
    overlay:Show()
end

local function FinishSweep()
    endsAt = nil
    for slot, visible in pairs(slots) do
        if visible then HideSpark(slot) end
    end
end

function I.ClearManaRegenSparkTimer()
    if not endsAt then return end
    expiry:Stop()
    FinishSweep()
end

local function OnCast(_, _, _, spellID)
    if visibleCount == 0 or not HasManaCost(spellID) then return end
    if not expiry then
        local clock = CreateFrame("Frame")
        expiry = clock:CreateAnimationGroup()
        local expirySpan = expiry:CreateAnimation("Animation")
        expirySpan:SetDuration(WINDOW)
        expiry:SetScript("OnFinished", FinishSweep)
        duration = C_DurationUtil.CreateDuration()
    end
    local now = GetTime()
    endsAt = now + WINDOW
    duration:SetTimeFromStart(now, WINDOW, 1)
    expiry:Stop()
    expiry:Play()
    for slot, visible in pairs(slots) do
        if visible then ShowSpark(slot) end
    end
end

local function SetSlotVisible(slot, visible)
    if slots[slot] == visible then return end
    slots[slot] = visible
    if visible then
        visibleCount = visibleCount + 1
        if not listener then
            listener = Event:On(CAST_SUCCEEDED, OnCast, owner, {
                unit = "player", moduleId = "YHUD", traceName = "Halo mana regen",
            })
        end
        if endsAt and GetTime() < endsAt then ShowSpark(slot) end
    else
        HideSpark(slot)
        visibleCount = visibleCount - 1
        if visibleCount == 0 then
            Event:Off(listener)
            listener = nil
            I.ClearManaRegenSparkTimer()
        end
    end
end

local function RefreshSlotVisibility(slot)
    if slots[slot] ~= nil then
        SetSlotVisible(slot, View.active == true and not View.preview
            and not View.designMode and not View.layoutEditMode and slot:IsVisible() == true)
    end
end

function I.RefreshManaRegenSparkVisibility()
    for slot in pairs(slots) do RefreshSlotVisibility(slot) end
end

function I.ConfigureManaRegenSpark(slot, enabled)
    if not enabled then
        if slots[slot] ~= nil then
            SetSlotVisible(slot, false)
            slots[slot] = nil
        end
        return
    end
    if slots[slot] == nil then
        slots[slot] = false
        if not slot._yhudManaRegenHooks then
            slot:HookScript("OnShow", RefreshSlotVisibility)
            slot:HookScript("OnHide", RefreshSlotVisibility)
            slot._yhudManaRegenHooks = true
        end
    end
    local overlay = slot._yhudManaRegenOverlay
    if overlay and LayoutSpark(slot, overlay) and slots[slot] and endsAt then
        ShowSpark(slot)
    end
    RefreshSlotVisibility(slot)
end
