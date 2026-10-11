
local _
---@type string, private
local addonName, private = ...

local LibEditMode = LibStub("LibEditMode")
local L = private.L

local PANEL_WIDTH = 210
local ROW_HEIGHT = 22
local BUTTON_HEIGHT = 20
local SIDE_PAD = 10
local CHECKBOX_SIZE = 20

---@type table<string, boolean> component names hidden during this edit mode session
private.editModeHidden = {}

---@type table<string, CheckButton> checkbox widgets keyed by component name
local checkboxes = {}

---@type CheckButton[] pool of reusable checkbox rows
local rowPool = {}
local rowPoolUsed = 0

---@type Frame|nil
local panel = nil

---Display names for built-in components.
---@type table<string, string>
local displayNames = {
    CooldownTracker = L["COMP_COOLDOWN_TRACKER"],
    TrinketTracker = L["COMP_TRINKET_TRACKER"],
    RacialTracker = L["COMP_RACIAL_TRACKER"],
    ConsumableTracker = L["COMP_CONSUMABLE_TRACKER"],
    BuffTracker = L["COMP_BUFF_TRACKER"],
    BuffTrackerBars = L["COMP_BUFF_TRACKER_BARS"],
    UtilitiesTracker = L["COMP_UTILITIES_TRACKER"],
    PlayerCastBar = L["COMP_PLAYER_CAST_BAR"],
    TargetCastBar = L["COMP_TARGET_CAST_BAR"],
    FocusCastBar = L["COMP_FOCUS_CAST_BAR"],
    PrimaryResources = L["COMP_PRIMARY_RESOURCES"],
    PlayerHealthBar = L["COMP_PLAYER_HEALTH_BAR"],
    SecondaryResources = L["COMP_SECONDARY_RESOURCES"],
}

---Get a display name for a component. Uses locale for built-ins,
---settings.name for additional frames, or falls back to the internal name.
---@param component component
---@return string
local function getDisplayName(component)
    local name = component.GetComponentName()
    if displayNames[name] then
        return displayNames[name]
    end
    -- Additional frames store a user-facing name in settings
    local settings = component.GetSettings()
    if settings and settings.name then
        return settings.name
    end
    return name
end

---Toggle a component's edit-mode visibility and refresh layout.
---@param componentName string
---@param show boolean
local function onToggle(componentName, show)
    if show then
        private.editModeHidden[componentName] = nil
    else
        private.editModeHidden[componentName] = true
    end
    private.Anchor.Refresh()
    local comp = private.ComponentManager.GetComponent(componentName)
    if comp then
        comp.Refresh()
    end
    private.Anchor.Refresh()
end

---Acquire a checkbox row from the pool or create a new one.
---@param parent Frame
local function acquireRow(parent)
    rowPoolUsed = rowPoolUsed + 1
    local row = rowPool[rowPoolUsed]
    if not row then
        row = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        row:SetSize(CHECKBOX_SIZE, CHECKBOX_SIZE)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", row, "RIGHT", 2, 0)
        rowPool[rowPoolUsed] = row
    end
    row:SetParent(parent)
    row:Show()
    return row
end

---Release all rows back to the pool.
local function releaseAllRows()
    for i = 1, rowPoolUsed do
        local r = rowPool[i]
        r:Hide()
        r:SetScript("OnClick", nil)
        r:SetScript("OnEnter", nil)
        r:SetScript("OnLeave", nil)
        r:Enable()
        if r.label then r.label:SetTextColor(1, 1, 1) end
    end
    rowPoolUsed = 0
    wipe(checkboxes)
end

---Set all checkboxes to a given state and update the hidden set.
---@param show boolean
local function setAll(show)
    for componentName, cb in pairs(checkboxes) do
        cb:SetChecked(show)
        if show then
            private.editModeHidden[componentName] = nil
        else
            private.editModeHidden[componentName] = true
        end
    end
    private.Anchor.Refresh()
end

---Create the panel frame (once). Content is rebuilt each time edit mode opens.
local function createPanel()
    local bt = private.Templates.ButtonTemplate

    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    f:SetBackdrop(bt.backdrop)
    f:SetBackdropColor(unpack(bt.backdropcolor))
    f:SetBackdropBorderColor(unpack(bt.backdropbordercolor))

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", SIDE_PAD, -8)
    title:SetText(L["EDITMODE_FRAME_VISIBILITY"])

    -- Description
    local desc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    desc:SetPoint("RIGHT", f, "RIGHT", -SIDE_PAD, 0)
    desc:SetWordWrap(true)
    desc:SetText(L["EDITMODE_FRAME_VISIBILITY_DESC"])

    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButtonNoScripts")
    close:SetSize(20, 20)
    -- The template pins an absolute frameLevel="510", which floats the button
    -- over every other DIALOG-strata frame that covers this panel.
    close:SetFrameLevel(f:GetFrameLevel() + 1)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Show All / Hide All buttons
    local btnWidth = (PANEL_WIDTH - SIDE_PAD * 2 - 4) / 2

    local showAll = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    showAll:SetSize(btnWidth, BUTTON_HEIGHT)
    showAll:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -4)
    showAll:SetText(L["EDITMODE_VIS_SHOW_ALL"])
    showAll:SetScript("OnClick", function() setAll(true) end)
    f.showAllBtn = showAll

    local hideAll = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    hideAll:SetSize(btnWidth, BUTTON_HEIGHT)
    hideAll:SetPoint("LEFT", showAll, "RIGHT", 4, 0)
    hideAll:SetText(L["EDITMODE_VIS_HIDE_ALL"])
    hideAll:SetScript("OnClick", function() setAll(false) end)
    f.hideAllBtn = hideAll

    -- Anchor to EditModeManagerFrame
    if EditModeManagerFrame then
        f:SetPoint("TOPLEFT", EditModeManagerFrame, "TOPRIGHT", 4, 0)
    else
        f:SetPoint("TOP", UIParent, "TOP", 300, -100)
    end

    f:Hide()
    panel = f
end

---Rebuild the checkbox list from currently registered components.
local function rebuildCheckboxes()
    releaseAllRows()

    local prevAnchor = panel.showAllBtn
    local firstGap = 6
    local rowGap = ROW_HEIGHT - CHECKBOX_SIZE
    local rowsAdded = 0

    for i, component in ipairs(private.ComponentManager.GetAllComponents()) do
        local name = component.GetComponentName()
        local label = getDisplayName(component)

        local row = acquireRow(panel)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, i == 1 and -firstGap or -rowGap)
        row:SetChecked(not private.editModeHidden[name])

        row:SetScript("OnClick", function(self)
            local checked = self:GetChecked()
            onToggle(name, checked)
            PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        end)

        row.label:SetText(label)

        checkboxes[name] = row
        prevAnchor = row
        rowsAdded = rowsAdded + 1
    end

    -- Synchronous sizing: generous header estimate covers desc wrapping to a
    -- second line. Backdrop needs a non-zero size at Show() time or the panel
    -- renders invisible.
    local headerEstimate = 8 + 14 + 2 + 24 + 4 + BUTTON_HEIGHT
    panel:SetSize(PANEL_WIDTH, headerEstimate + firstGap + rowsAdded * ROW_HEIGHT + 10)

    -- Fine-tune next frame once the wrap-dependent anchor chain has resolved.
    C_Timer.After(0, function()
        if not panel:IsShown() then return end
        local top = panel:GetTop()
        local bottom = prevAnchor:GetBottom()
        if top and bottom then
            panel:SetSize(PANEL_WIDTH, (top - bottom) + 10)
        end
    end)
end

-- Lifecycle: show panel when edit mode enters, reset and hide on exit.
LibEditMode:RegisterCallback("enter", function()
    if InCombatLockdown() then return end
    if not panel then
        createPanel()
    end
    wipe(private.editModeHidden)
    rebuildCheckboxes()
    panel:Show()
end)

LibEditMode:RegisterCallback("exit", function()
    wipe(private.editModeHidden)
    if panel then
        panel:Hide()
    end
end)
