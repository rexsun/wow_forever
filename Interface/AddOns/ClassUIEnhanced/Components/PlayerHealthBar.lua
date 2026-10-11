
local _
---@type string, private
local _, private = ...

---@type detailsframework
local framework = _G["DetailsFramework"]

local LibSharedMedia = LibStub("LibSharedMedia-3.0")

---@class private : table
---@field PlayerHealthBar playerhealthbar

---@class playerhealthbar : component
---@field CreatePlayerHealthBar fun() : df_healthbar Creates the health bar frame

---@type playerhealthbar
---@diagnostic disable-next-line: missing-fields
local playerHealthBar = {}

playerHealthBar.name = "PlayerHealthBar"

---@return healthbar_profile_main
local getSettings = function()
    return private.profile.components[playerHealthBar.name]
end

playerHealthBar.GetSettings = getSettings

local getEnabled = function()
    local settings = getSettings()
    if not settings.enabled then return false end
    return true
end

playerHealthBar.GetEnabled = getEnabled

---@type df_healthbar?
local healthBar

---@type Button?
local clickOverlay

-- Whether the last Refresh wants clickOverlay up (enabled or Edit Mode, and
-- interactable). ContentLayout re-places it only while this is set.
local clickOverlayWanted = false

---@type fontstring?
local valueText

-- Track previous shield/prediction settings to detect changes and force re-registration.
local prevShowShields
local prevShowHealingPrediction

-- Current orientation for the size correction hooks.
local currentOrientation = "horizontal"

-- ---------------------------------------------------------------------------
-- Health gradient color curve
-- ---------------------------------------------------------------------------
-- A color curve that maps health fraction [0, 1] → RGBA, evaluated via the
-- heal calculator to produce secret color values compatible with
-- SetStatusBarColor (AllowedWhenTainted).
--
-- Evidence:
--   C_CurveUtil.CreateColorCurve — CurveUtilDocumentation.lua
--   LuaColorCurveObject:AddPoint(x, colorRGBA) — LuaColorCurveObjectAPIDocumentation.lua
--   Enum.LuaCurveType.Linear — LuaCurveObjectConstantsDocumentation.lua
--   healCalculator:EvaluateCurrentHealthPercent(curve) — unitframe_midnight.lua:309
--   StatusBar:SetStatusBarColor — AllowedWhenTainted (SimpleStatusBarAPIDocumentation.lua)

---@type table?  ColorCurveObject for health gradient
local healthGradientCurve

---Invalidate the cached color curve so it rebuilds from current profile colors.
local function invalidateGradientCurve()
    healthGradientCurve = nil
end

---Build or return the cached color curve for health gradient.
---Reads threshold colors from private.profile.health_gradient_colors.
---@return table colorCurve  ColorCurveObject to pass to EvaluateCurrentHealthPercent
local function getHealthGradientCurve()
    if healthGradientCurve then return healthGradientCurve end
    local colors = private.profile.health_gradient_colors
    healthGradientCurve = C_CurveUtil.CreateColorCurve()
    healthGradientCurve:SetType(Enum.LuaCurveType.Linear)
    healthGradientCurve:AddPoint(0.0, CreateColor(colors.low[1], colors.low[2], colors.low[3], colors.low[4]))
    healthGradientCurve:AddPoint(0.5, CreateColor(colors.mid[1], colors.mid[2], colors.mid[3], colors.mid[4]))
    healthGradientCurve:AddPoint(1.0, CreateColor(colors.full[1], colors.full[2], colors.full[3], colors.full[4]))
    return healthGradientCurve
end

---Applies the green→yellow→red gradient based on current health percentage.
---Uses C_CurveUtil color curve evaluated against the heal calculator to avoid
---arithmetic on secret health values.
---@param bar df_healthbar
local function applyGradientColor(bar)
    if not bar.healCalculator then return end
    bar.healCalculator:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
    local color = bar.healCalculator:EvaluateCurrentHealthPercent(getHealthGradientCurve())
    bar:SetStatusBarColor(color.r, color.g, color.b, color.a)
end

---Applies class color to the health bar.
---@param bar df_healthbar
local function applyClassColor(bar)
    local _, class = UnitClass("player")
    local color = RAID_CLASS_COLORS[class]
    if color then
        bar:SetStatusBarColor(color.r, color.g, color.b, 1)
    end
end

---Updates the bar color based on the current color_mode setting.
---@param bar df_healthbar
local function applyBarColor(bar)
    local settings = getSettings()
    if settings.color_mode == "gradient" then
        applyGradientColor(bar)
    else
        applyClassColor(bar)
    end
end

---Applies the profile texture to the health bar via LSM lookup.
---If not found or empty, falls back to a solid white fill via barTexture:SetColorTexture(1,1,1,1).
---@param bar df_healthbar
---@param texture string LibSharedMedia statusbar key, or "" for default
local function applyTexture(bar, texture)
    if texture and texture ~= "" then
        local lsmPath = LibSharedMedia:Fetch("statusbar", texture, true)
        if lsmPath then
            bar:SetTexture(lsmPath)
            return
        end
    end
    bar.barTexture:SetColorTexture(1, 1, 1, 1)
end

---Formats the health text based on the text_format setting.
---@param bar df_healthbar
local function updateHealthText(bar)
    if not valueText then return end

    local settings = getSettings()
    local fmt = settings.text_format
    local pct = bar.currentHealthPercent or 0
    local cur = bar.currentHealth or 0

    if fmt == "none" then
        valueText:SetText("")
    elseif fmt == "current" then
        valueText:SetText(AbbreviateLargeNumbers(cur))
    elseif fmt == "both" then
        valueText:SetText(AbbreviateLargeNumbers(cur) .. " - " .. format("%.0f%%", pct))
    else
        valueText:SetText(format("%.0f%%", pct))
    end
end

---Called by DF on every health change event.
---@param bar df_healthbar
local function onHealthChanged(bar)
    local settings = getSettings()
    if settings.color_mode == "gradient" then
        applyGradientColor(bar)
    end
    updateHealthText(bar)
end

---Re-anchor and orient the health bar's sub-bars (heal prediction, shield absorb,
---glow) for the given orientation. Called from Refresh() after SetSize.
---@param bar df_healthbar
---@param orientation string "horizontal"|"vertical"
local function applyOrientation(bar, orientation)
    currentOrientation = orientation
    local isVertical = orientation == "vertical"

    bar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
    bar.incomingHealIndicatorBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
    bar.shieldAbsorbIndicatorBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")

    bar.incomingHealIndicatorBar:ClearAllPoints()
    bar.shieldAbsorbIndicatorBar:ClearAllPoints()
    bar.shieldAbsorbGlow:ClearAllPoints()

    if isVertical then
        -- Heal prediction: above the fill, spanning full bar width
        bar.incomingHealIndicatorBar:SetPoint("BOTTOMLEFT", bar.barTexture, "TOPLEFT")
        bar.incomingHealIndicatorBar:SetPoint("BOTTOMRIGHT", bar.barTexture, "TOPRIGHT")
        bar.incomingHealIndicatorBar:SetHeight(bar:GetHeight())

        -- Shield absorb: above the fill (one-sided anchoring, matches DF v693)
        bar.shieldAbsorbIndicatorBar:SetPoint("BOTTOMLEFT", bar.barTexture, "TOPLEFT")
        bar.shieldAbsorbIndicatorBar:SetPoint("BOTTOMRIGHT", bar.barTexture, "TOPRIGHT")
        bar.shieldAbsorbIndicatorBar:SetHeight(bar:GetHeight())

        -- Glow: along the top edge
        bar.shieldAbsorbGlow:SetHeight(bar.Settings.ShieldGlowWidth)
        bar.shieldAbsorbGlow:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 8)
        bar.shieldAbsorbGlow:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 8)
    else
        -- Restore horizontal defaults (matches DF CreateHealthBar anchoring)
        bar.incomingHealIndicatorBar:SetPoint("TOPLEFT", bar.barTexture, "TOPRIGHT")
        bar.incomingHealIndicatorBar:SetPoint("BOTTOMLEFT", bar.barTexture, "BOTTOMRIGHT")
        bar.incomingHealIndicatorBar:SetWidth(bar:GetWidth())

        bar.shieldAbsorbIndicatorBar:SetPoint("TOPLEFT", bar.barTexture, "TOPRIGHT")
        bar.shieldAbsorbIndicatorBar:SetPoint("BOTTOMLEFT", bar.barTexture, "BOTTOMRIGHT")
        bar.shieldAbsorbIndicatorBar:SetWidth(bar:GetWidth())

        bar.shieldAbsorbGlow:SetWidth(bar.Settings.ShieldGlowWidth)
        bar.shieldAbsorbGlow:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 8, 0)
        bar.shieldAbsorbGlow:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 8, 0)
    end
end

---Creates the player health bar frame.
---@return df_healthbar
playerHealthBar.CreatePlayerHealthBar = function()
    if healthBar then
        error("CreatePlayerHealthBar() Health bar already exists.")
    end

    local name = "CUE_PlayerHealthBar"
    healthBar = framework:CreateHealthBar(UIParent, name)

    -- Install post-hooks that fire AFTER DF's SetWidth/SetSize hooks to correct
    -- sub-bar sizing for vertical orientation. DF's hooks unconditionally set
    -- incomingHealIndicatorBar:SetWidth(w) which is wrong when vertical.
    hooksecurefunc(healthBar, "SetWidth", function(self, w)
        if currentOrientation == "vertical" then
            healthBar.incomingHealIndicatorBar:SetHeight(healthBar:GetHeight())
            healthBar.shieldAbsorbIndicatorBar:SetHeight(healthBar:GetHeight())
        end
    end)
    hooksecurefunc(healthBar, "SetHeight", function(self, h)
        if currentOrientation == "vertical" then
            healthBar.incomingHealIndicatorBar:SetHeight(h)
            healthBar.shieldAbsorbIndicatorBar:SetHeight(h)
        end
    end)
    hooksecurefunc(healthBar, "SetSize", function(self, w, h)
        if currentOrientation == "vertical" then
            healthBar.incomingHealIndicatorBar:SetHeight(h)
            healthBar.shieldAbsorbIndicatorBar:SetHeight(h)
        end
    end)

    valueText = healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    private.Pixel.SetPoint(valueText, "CENTER", healthBar, "CENTER", 0, 0)
    valueText:SetJustifyH("CENTER")
    valueText:SetTextColor(1, 1, 1, 1)

    healthBar.OnHealthChange = onHealthChanged

    clickOverlay = CreateFrame("Button", name .. "ClickOverlay", UIParent, "SecureUnitButtonTemplate")
    clickOverlay:SetFrameStrata(healthBar:GetFrameStrata())
    clickOverlay:SetFrameLevel(healthBar:GetFrameLevel() + 10)
    SecureUnitButton_OnLoad(clickOverlay, "player", function(_, unit)
        UnitPopup_OpenMenu("SELF", { unit = unit })
    end)
    clickOverlay:Hide()
    -- Not anchored to healthBar, so hiding the bar does not hide it: a pass that
    -- hides the bar (a mount, combat ending under an out_of_combat hide) left an
    -- invisible click area behind. A secure button cannot be hidden in combat;
    -- the OnLeaveCombat listener below catches that case up.
    healthBar:HookScript("OnHide", function()
        if not InCombatLockdown() then
            clickOverlay:Hide()
        end
    end)

    return healthBar
end

---Snap the secure click overlay onto healthBar's current screen rect. It is
---parented to UIParent and never anchored to healthBar (anchoring would make
---healthBar implicitly protected, and every frame on its anchor chain unsizable
---in combat), so it only moves when this runs. Both corners are pinned, so its
---size is the bar's real one -- an anchor-derived width included -- never the
---profile's. Shown only while healthBar is shown and has a resolvable rect, so
---it is never up without points or over a hidden bar (Refresh places it
---whatever the bar's visibility).
local function placeClickOverlay()
    local left, bottom = healthBar:GetLeft(), healthBar:GetBottom()
    local right, top = healthBar:GetRight(), healthBar:GetTop()
    clickOverlay:ClearAllPoints()
    if left and bottom and right and top and healthBar:IsShown() then
        clickOverlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
        clickOverlay:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
        clickOverlay:Show()
    else
        clickOverlay:Hide()
    end
end

---Called from Init.lua to initialize the component on PLAYER_LOGIN event.
playerHealthBar.Initialize = function()
    -- Always call Refresh so the health bar frame is created and available for Edit Mode,
    -- even when the component is disabled.
    playerHealthBar.Refresh()
end

playerHealthBar.GetFrame = function()
    return healthBar
end

playerHealthBar.Refresh = function()
    local settings = getSettings()

    if not healthBar then
        playerHealthBar.CreatePlayerHealthBar()
    end

    -- Visibility is not consulted: the layout pass owns Show/Hide, and DF's bar
    -- never shows itself. Gating on it skipped every setting edited while the
    -- bar was hidden, and unbound the unit, which no revealing pass (the pull
    -- under an out_of_combat hide, a dismount) re-bound -- those passes call
    -- ContentLayout, never Refresh.
    if getEnabled() or private.isEditMode then
        local isVertical = (settings.orientation or "horizontal") == "vertical"
        if isVertical then
            healthBar:SetSize(settings.height, settings.width)
        else
            healthBar:SetSize(settings.width, settings.height)
        end
        applyOrientation(healthBar, settings.orientation or "horizontal")

        healthBar.Settings.ShowShields = settings.show_shields
        healthBar.Settings.ShowHealingPrediction = settings.show_healing_prediction
        healthBar.Settings.AnimateHealth = settings.bar_smoothing

        local settingsChanged = prevShowShields ~= settings.show_shields or prevShowHealingPrediction ~= settings.show_healing_prediction
        prevShowShields = settings.show_shields
        prevShowHealingPrediction = settings.show_healing_prediction

        if settingsChanged and healthBar.unit == "player" then
            -- DF re-registers events only on a unit change, and its SetUnit(nil)
            -- also Hide()s the bar -- which the layout pass owns, and which a
            -- plain Refresh from the Options toggle never undid.
            local shown = healthBar:IsShown()
            healthBar:SetUnit(nil)
            healthBar:SetShown(shown)
        end

        if healthBar.unit ~= "player" then
            healthBar:SetUnit("player")
        end

        applyTexture(healthBar, settings.texture)

        -- Apply the same texture to the shield absorb bar (always white)
        if healthBar.shieldAbsorbIndicatorBar then
            local lsmPath = settings.texture and settings.texture ~= "" and LibSharedMedia:Fetch("statusbar", settings.texture, true)
            if lsmPath then
                healthBar.shieldAbsorbIndicatorBar.barTexture:SetTexture(lsmPath)
            else
                healthBar.shieldAbsorbIndicatorBar.barTexture:SetColorTexture(1, 1, 1, 1)
            end
            healthBar.shieldAbsorbIndicatorBar.barTexture:SetVertexColor(1, 1, 1, 1)
        end

        -- Apply the same texture to the incoming heal bar
        if healthBar.incomingHealIndicatorBar then
            local lsmPath = settings.texture and settings.texture ~= "" and LibSharedMedia:Fetch("statusbar", settings.texture, true)
            if lsmPath then
                healthBar.incomingHealIndicatorBar.barTexture:SetTexture(lsmPath)
            else
                healthBar.incomingHealIndicatorBar.barTexture:SetColorTexture(0, 0.9, 0, 1)
            end
        end

        applyBarColor(healthBar)

        local bgColor = settings.background_color
        if bgColor and healthBar.background then
            healthBar.background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
        end

        local overlayFrame = private.Util.ApplyBarBorder(healthBar)

        local valueFont = settings.value_font
        if valueFont and valueText then
            valueText:SetParent(overlayFrame)
            valueText:SetDrawLayer("OVERLAY", 7)
            if private.fontsDirty then
                private.Util.ApplyFontProfile(valueText, valueFont, healthBar)
                if isVertical then
                    private.Util.ApplyVerticalFontRotation(valueText)
                else
                    valueText:SetRotation(0)
                end
            end
        end

        updateHealthText(healthBar)

        -- Every caller runs RefreshAllComponents() before Anchor.Refresh(), so
        -- healthBar has not moved yet here; ContentLayout re-places the overlay
        -- once the layout pass has positioned it.
        clickOverlayWanted = settings.interactable and true or false
        if clickOverlay and not InCombatLockdown() then
            clickOverlay:SetFrameStrata(healthBar:GetFrameStrata())
            clickOverlay:SetFrameLevel(healthBar:GetFrameLevel() + 10)
            if settings.interactable then
                placeClickOverlay()
            else
                clickOverlay:ClearAllPoints()
                clickOverlay:Hide()
            end
        end
    else
        healthBar:SetUnit(nil)
        clickOverlayWanted = false
        if clickOverlay and not InCombatLockdown() then
            clickOverlay:ClearAllPoints()
            clickOverlay:Hide()
        end
    end
end

playerHealthBar.OnEnable = function()
    playerHealthBar.Refresh()
end

playerHealthBar.OnDisable = function()
    if healthBar and not private.isEditMode then
        healthBar:SetUnit(nil)
        -- clickOverlay is parented to UIParent (so healthBar stays unprotected),
        -- so hiding the bar cannot cascade to it. Refresh's disabled branch hides
        -- it, but DisableComponent calls OnDisable only — never Refresh.
        clickOverlayWanted = false
        if clickOverlay and not InCombatLockdown() then
            clickOverlay:ClearAllPoints()
            clickOverlay:Hide()
        end
    end
end

---Anchor calls this right after it positions healthBar in a layout pass —
---the one point where healthBar's screen rect is current.
playerHealthBar.ContentLayout = function()
    if clickOverlayWanted and clickOverlay and not InCombatLockdown() then
        placeClickOverlay()
    end
end

playerHealthBar.GetComponentName = function()
    return playerHealthBar.name
end

playerHealthBar.GetComponentSize = function()
    local settings = getSettings()
    if (settings.orientation or "horizontal") == "vertical" then
        return settings.height, settings.width
    end
    return settings.width, settings.height
end

-- The OnHide hook in CreatePlayerHealthBar cannot hide the secure overlay in
-- combat; a bar hidden mid-fight gets it hidden here.
private.Callback.Register("OnLeaveCombat", function()
    if clickOverlay and clickOverlay:IsShown() and not healthBar:IsShown() then
        clickOverlay:Hide()
    end
end)

---Invalidate the gradient curve cache so it rebuilds from updated profile colors.
---Called from the Options panel when a gradient color is changed.
playerHealthBar.InvalidateGradientCurve = invalidateGradientCurve

private.PlayerHealthBar = playerHealthBar
private.ComponentManager.RegisterComponent("PlayerHealthBar", playerHealthBar)
