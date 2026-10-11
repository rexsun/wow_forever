
--[[
    CooldownTracker — displays essential cooldown spell icons via the shared
    plain-frame icon tracker factory (Core/IconTracker.lua; display-only, not
    clickable).  CDM (CooldownViewer) category CooldownEssential is the spell
    data source; the CDM viewer is alpha-suppressed and never rendered.
    Custom spells are merged in.  Additional-frame-routed spells are excluded.

    This file owns two layers on top of the factory, both plugged in via hooks:
    the override-bar layer (skyriding / vehicle / override — addon-owned Cooldown
    frames rendered inside the same container, via preRefresh takeover,
    postSwipeUpdate content pass, IsCollapsed / GetComponentSize overrides,
    enable/disable wiring), and the routed addon icons (route_trinkets /
    route_combat_potions — TrinketTracker and ConsumableTracker icons appended
    to the end of our grid, via getAppendFrames).

    pandemic_glow rides Blizzard's native AddPandemicRegion (12.1.0.69111) on
    the factory's aura-slot buttons — see Core/IconTracker.lua's syncAuraSlots.
    Full gap tracker: .context/migration-parity-gaps.md (mirrored on PR #41).
--]]

local _
---@type string, private
local addonName, private = ...

---@class private : table
---@field CooldownTracker cooldowntracker

---@class cooldowntracker : component
---@field IsIconRoutedHere fun(icon: table): boolean

---Component table and factory context — assigned by CreateTracker at the
---bottom of this file; the override-layer functions below only run afterwards.
---@type cooldowntracker
local cooldownTracker
---@type icontracker_ctx
local ctx

-- ---------------------------------------------------------------------------
-- Override bar state (skyriding / vehicle / override)
-- ---------------------------------------------------------------------------

---Whether the component is currently showing addon-owned override ability icons.
---Nil/false when inactive, or a string ("skyriding"|"vehicle"|"override") when active.
---@type string|false|nil
local overrideMode = false

---Pool of addon-owned icon frames for override abilities.
---@type table<integer, frame>
local overrideFrames = {}

---Event frame for bar-change transitions during override mode.
---@type Frame?
local overrideWatcher

---Static set of skyriding ability spell IDs that appear on the bonus bar.
---Only these are shown; player-placed class abilities are filtered out.
---@type table<integer, boolean>
local SKYRIDING_ABILITIES = {
    [372608] = true,  -- Surge Forward
    [372610] = true,  -- Skyward Ascent
    [361584] = true,  -- Whirling Surge
    [418592] = true,  -- Lightning Rush
    [403092] = true,  -- Aerial Halt
    [425782] = true,  -- Second Wind
    [410630] = true,  -- Bronze Timelock
}

-- ---------------------------------------------------------------------------
-- Override bar helpers
-- ---------------------------------------------------------------------------

---Returns the active override bar index and type, or nil if none active and enabled.
---Priority: vehicle > override > skyriding (matches Blizzard precedence).
---@return integer?, string?
local function getActiveOverrideInfo()
    local settings = cooldownTracker.GetSettings()
    if settings.show_vehicle_abilities and C_ActionBar.HasVehicleActionBar() then
        return C_ActionBar.GetVehicleBarIndex(), "vehicle"
    end
    if settings.show_override_bar_abilities and C_ActionBar.HasOverrideActionBar() then
        return C_ActionBar.GetOverrideBarIndex(), "override"
    end
    if settings.show_skyriding_abilities
        and C_ActionBar.GetBonusBarIndex() == 11
        and C_ActionBar.GetBonusBarOffset() == 5 then
        return 11, "skyriding"
    end
    return nil, nil
end

---Return or create a pooled override icon frame at the given index.
---@param index integer
---@return frame
local function getOrCreateOverrideFrame(index)
    if overrideFrames[index] then return overrideFrames[index] end

    local container = ctx.GetContainer()
    local frame = CreateFrame("Frame", nil, container)
    frame:SetFrameLevel(container:GetFrameLevel() + 2)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    frame.Icon = icon

    -- Square mask (WHITE8x8) matching SquarifyViewerIcon style
    local mask = frame:CreateMaskTexture()
    mask:SetAllPoints(icon)
    mask:SetTexture("Interface\\Buttons\\WHITE8x8")
    icon:AddMaskTexture(mask)

    -- Cooldown overlay with square swipe
    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetFrameLevel(frame:GetFrameLevel() + 1)
    cd:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
    cd:SetDrawSwipe(true)
    cd:SetDrawEdge(true)
    cd:SetSwipeColor(0, 0, 0, 0.7)
    cd:SetHideCountdownNumbers(false)
    cd.noCooldownCount = true
    frame.Cooldown = cd

    -- Overlay frame above cooldown swipe for all text elements
    local textOverlay = CreateFrame("Frame", nil, frame)
    textOverlay:SetAllPoints(cd)
    textOverlay:SetFrameLevel(cd:GetFrameLevel() + 10)

    -- Keybind text
    local keybind = textOverlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    frame.Keybind = keybind

    -- Charge count text
    local chargeCount = textOverlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    frame.ChargeCount = chargeCount

    overrideFrames[index] = frame
    return frame
end

---Per-event override content update: cooldown swipe, charge text, and
---usability tint on already-visible override frames.  No geometry, no font
---re-application — the full applyOverrideLayout restyle is reserved for bar
---transitions and Refresh, so the per-event path stays cheap.
---@param settings viewer_tracker_profile_main
local function refreshOverrideContent(settings)
    for i = 1, #overrideFrames do
        local frame = overrideFrames[i]
        if frame:IsShown() and frame._overrideIsSpell then
            local spellID = frame._overrideSpellID
            local cdInfo = C_Spell.GetSpellCooldown(spellID)
            local chargeInfo = C_Spell.GetSpellCharges(spellID)
            local cdDuration
            if chargeInfo and chargeInfo.isActive then
                cdDuration = C_Spell.GetSpellChargeDuration(spellID)
            elseif cdInfo and cdInfo.isActive then
                cdDuration = C_Spell.GetSpellCooldownDuration(spellID)
            end
            -- Direction before duration, and every pass — see refreshButtonContent
            -- in Core/IconTracker.lua for why the reverse order reads as dead.
            frame.Cooldown:SetReverse(settings.reverse_swipe == true)
            if cdDuration then
                frame.Cooldown:SetCooldownFromDurationObject(cdDuration)
                frame.Cooldown:SetDrawSwipe(not settings.hide_cd_swipe)
            else
                frame.Cooldown:Clear()
            end

            local hasCharges = chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1
            if settings.hide_cd_text then
                frame.Cooldown:SetHideCountdownNumbers(true)
            elseif settings.hide_charge_cd_text and hasCharges then
                -- currentCharges is secret (patterns-secrets.md) — all charges
                -- depleted iff both the recharge and a real cooldown are active.
                local allDepleted = chargeInfo.isActive == true
                    and cdInfo and cdInfo.isActive == true and not cdInfo.isOnGCD
                frame.Cooldown:SetHideCountdownNumbers(not allDepleted)
            else
                frame.Cooldown:SetHideCountdownNumbers(false)
            end

            if hasCharges then
                if settings.hide_zero_charges then
                    frame.ChargeCount:SetText(C_StringUtil.TruncateWhenZero(chargeInfo.currentCharges))
                else
                    frame.ChargeCount:SetText(chargeInfo.currentCharges)
                end
            end

            local isUsable = C_Spell.IsSpellUsable(spellID)
            frame.Icon:SetVertexColor(isUsable and 1 or 0.4, isUsable and 1 or 0.4, isUsable and 1 or 0.4)
        end
    end
end

---Hide all override frames and re-enable custom spells.
local function exitOverrideMode()
    if not overrideMode then return end
    overrideMode = false
    for i = 1, #overrideFrames do
        overrideFrames[i]:Hide()
    end
    if private.CustomSpells and cooldownTracker.GetEnabled() then
        private.CustomSpells.OnEnable("CooldownTracker")
    end
    private.Anchor.OnComponentStateChange()
end

---Scan override bar slots and lay out addon-owned ability icons.
---@param settings viewer_tracker_profile_main
---@param barIndex integer  action bar page index from getActiveOverrideInfo
---@param barType string  "skyriding"|"vehicle"|"override"
local function applyOverrideLayout(settings, barIndex, barType)
    local enteringOverride = not overrideMode
    overrideMode = barType
    local container = ctx.GetContainer()

    -- Scan override bar action slots for abilities
    local startSlot = (barIndex - 1) * 12 + 1
    local endSlot = startSlot + 11
    local count = 0
    local isSkyridingFilter = barType == "skyriding"

    for slot = startSlot, endSlot do
        local actionType, id = GetActionInfo(slot)
        if actionType == "spell" and id and id ~= 0 and C_ActionBar.GetActionTexture(slot) then
            if not isSkyridingFilter or SKYRIDING_ABILITIES[id] then
                count = count + 1
                local frame = getOrCreateOverrideFrame(count)
                frame._overrideSpellID = id
                frame._overrideSlot = slot
                frame._overrideIsSpell = true
            end
        elseif C_ActionBar.HasAction(slot) and C_ActionBar.GetActionTexture(slot) then
            if not isSkyridingFilter then
                count = count + 1
                local frame = getOrCreateOverrideFrame(count)
                frame._overrideSpellID = nil
                frame._overrideSlot = slot
                frame._overrideIsSpell = false
            end
        end
    end

    if count == 0 then
        for i = 1, #overrideFrames do overrideFrames[i]:Hide() end
        return
    end

    -- Compute icon size from settings
    local iconSize = settings.icon_size > 0 and settings.icon_size or 50
    local iconHeight = (settings.icon_height and settings.icon_height > 0)
        and settings.icon_height or iconSize
    local xPad = settings.icon_offset or 1

    -- Position icons in a single row
    local totalWidth = count * iconSize + (count - 1) * xPad
    local containerWidth = container:GetWidth()
    if containerWidth <= 0 then containerWidth = totalWidth end
    local startX
    local align = settings.layout_alignment or "center"
    if align == "left" then
        startX = 0
    elseif align == "right" then
        startX = containerWidth - totalWidth
    else
        startX = (containerWidth - totalWidth) / 2
    end

    -- Apply keybind and stacks font profiles once per layout pass
    local keybindFont = settings.keybind_font
    local showOverrideKeybind = settings.show_override_keybind_text ~= false
    local stacksFont = settings.stacks_font

    for i = 1, count do
        local frame = overrideFrames[i]
        local spellID = frame._overrideSpellID
        local slot = frame._overrideSlot
        local isSpell = frame._overrideIsSpell
        frame:SetSize(iconSize, iconHeight)

        if isSpell then
            frame.Icon:SetTexture(C_Spell.GetSpellTexture(spellID))
        else
            frame.Icon:SetTexture(C_ActionBar.GetActionTexture(slot))
        end
        frame.Icon:SetTexCoord(private.Util.GetIconZoomCoords(iconSize, iconHeight))
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT",
            startX + (i - 1) * (iconSize + xPad), 0)
        frame:SetAlpha(1)

        private.Util.ApplyIconBorder(frame)

        local buttonIndex = slot - startSlot + 1
        local key = GetBindingKey("ACTIONBUTTON" .. buttonIndex)
        local keybindText = key and private.Util.FormatBindingKey(key) or nil
        if showOverrideKeybind and keybindText and keybindFont then
            private.Util.ApplyFontProfile(frame.Keybind, keybindFont, frame)
            frame.Keybind:SetText(keybindText)
            frame.Keybind:Show()
        else
            frame.Keybind:Hide()
        end

        if isSpell then
            local cdInfo = C_Spell.GetSpellCooldown(spellID)
            local chargeInfo = C_Spell.GetSpellCharges(spellID)
            local cdDuration
            if chargeInfo and chargeInfo.isActive then
                cdDuration = C_Spell.GetSpellChargeDuration(spellID)
            elseif cdInfo and cdInfo.isActive then
                cdDuration = C_Spell.GetSpellCooldownDuration(spellID)
            end
            frame.Cooldown:SetReverse(settings.reverse_swipe == true)
            if cdDuration then
                frame.Cooldown:SetCooldownFromDurationObject(cdDuration)
                frame.Cooldown:SetDrawSwipe(not settings.hide_cd_swipe)
                frame.Cooldown:Show()
            else
                frame.Cooldown:Clear()
            end

            if settings.hide_cd_text then
                frame.Cooldown:SetHideCountdownNumbers(true)
            elseif settings.hide_charge_cd_text and chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1 then
                -- currentCharges is secret (patterns-secrets.md) — all charges
                -- depleted iff both the recharge and a real cooldown are active.
                local allDepleted = chargeInfo.isActive == true
                    and cdInfo and cdInfo.isActive == true and not cdInfo.isOnGCD
                frame.Cooldown:SetHideCountdownNumbers(not allDepleted)
            else
                frame.Cooldown:SetHideCountdownNumbers(false)
            end

            if chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1 then
                if stacksFont then
                    private.Util.ApplyFontProfile(frame.ChargeCount, stacksFont, frame)
                end
                if settings.hide_zero_charges then
                    frame.ChargeCount:SetText(C_StringUtil.TruncateWhenZero(chargeInfo.currentCharges))
                else
                    frame.ChargeCount:SetText(chargeInfo.currentCharges)
                end
                frame.ChargeCount:Show()
            else
                frame.ChargeCount:Hide()
            end

            local isUsable = C_Spell.IsSpellUsable(spellID)
            frame.Icon:SetVertexColor(isUsable and 1 or 0.4, isUsable and 1 or 0.4, isUsable and 1 or 0.4)
        else
            frame.Cooldown:Clear()
            frame.ChargeCount:Hide()
            frame.Icon:SetVertexColor(1, 1, 1)
        end

        frame:Show()
    end

    for i = count + 1, #overrideFrames do
        overrideFrames[i]:Hide()
    end

    ctx.SetContainerSize(math.max(totalWidth, settings.min_width or 0), iconHeight)
    container:Show()

    if enteringOverride then
        private.Anchor.OnComponentStateChange()
    end
end

-- ---------------------------------------------------------------------------
-- Routed addon icons (trinkets / combat potions)
-- ---------------------------------------------------------------------------

---Icons currently positioned in our grid, in grid order.  Doubles as the
---membership set the source components query (TrinketTracker /
---ConsumableTracker `isIconRouted` skip them in their own layout, and
---`getVisualSettings` reads our settings for them instead of their own).
---@type table[]
local routedList = {}

---Equipment slots TrinketTracker owns.
local TRINKET_SLOTS = { 13, 14 }

---Hand every routed icon back to its source component.
local function clearRoutedAddonIcons()
    for i = 1, #routedList do
        routedList[i]:SetIgnoreParentAlpha(false)
        routedList[i]:SetAlpha(1)
    end
    wipe(routedList)
end

---Restyle a routed icon's text to match our grid.  The source component keeps
---applying its OWN font profiles on its update pass, so this has to re-assert
---on every collect, not just when the routed set changes.
---@param icon table
---@param settings viewer_tracker_profile_main
local function applyAddonIconProperties(icon, settings)
    if settings.timer_font then
        if icon.DurationText then
            private.Util.ApplyFontProfile(icon.DurationText, settings.timer_font, icon)
        end
        if icon.BuffDurationText then
            private.Util.ApplyFontProfile(icon.BuffDurationText, settings.timer_font, icon)
        end
    end
    if icon.KeybindText then
        if settings.keybind_font and settings.keybind_font.enabled then
            local keybindText
            if icon.slotID then
                local itemID = GetInventoryItemID("player", icon.slotID)
                if itemID then keybindText = private.Util.GetKeybindTextForItem(itemID) end
            elseif icon.itemId then
                keybindText = private.Util.GetKeybindTextForItem(icon.itemId)
            end
            if keybindText then
                icon.KeybindText:SetText(keybindText)
                private.Util.ApplyFontProfile(icon.KeybindText, settings.keybind_font, icon)
                icon.KeybindText:Show()
            else
                icon.KeybindText:Hide()
            end
        else
            icon.KeybindText:Hide()
        end
    end
    if settings.stacks_font and icon.Count and icon.Count:IsShown() then
        private.Util.ApplyFontProfile(icon.Count, settings.stacks_font, icon)
    end
end

---Collect the addon icons to append to our grid.  Icons already routed to an
---AdditionalFrame are skipped — AF takes priority.
---@param active boolean  false when our grid is not showing: release, adopt nothing
---@return table[]?
local function collectRoutedAddonIcons(active)
    if not active then
        clearRoutedAddonIcons()
        return nil
    end
    local settings = cooldownTracker.GetSettings()
    -- Hand everything back first, then re-adopt whatever is still routed: with
    -- a handful of icons that is cheaper than diffing, and our caller places
    -- and re-alphas the result in the same frame, so nothing ever draws at the
    -- restored alpha.
    clearRoutedAddonIcons()
    if not settings.route_trinkets and not settings.route_combat_potions then
        return nil
    end

    local afm = private.AdditionalFrameManager
    local n = 0

    if settings.route_trinkets and private.TrinketTracker then
        for _, slotID in ipairs(TRINKET_SLOTS) do
            if not (afm and afm.IsSpellRouted(slotID, "Trinket")) then
                local icon = private.TrinketTracker.GetIconFrame(slotID)
                if icon and icon:IsShown() then
                    n = n + 1
                    routedList[n] = icon
                end
            end
        end
    end

    if settings.route_combat_potions and private.ConsumableTracker then
        if not (afm and afm.IsSpellRouted(1, "Consumable")) then
            for _, icon in ipairs(private.ConsumableTracker.GetIconsByCategory(1)) do
                if icon:IsShown() then
                    n = n + 1
                    routedList[n] = icon
                end
            end
        end
    end

    for i = 1, n do
        local icon = routedList[i]
        icon:SetIgnoreParentAlpha(true)
        applyAddonIconProperties(icon, settings)
    end

    return n > 0 and routedList or nil
end

-- ---------------------------------------------------------------------------
-- Factory hooks
-- ---------------------------------------------------------------------------

---Refresh takeover: while an override bar is active, the override layer owns
---the container (tracker icons parked at alpha 0, custom spells disabled).
---@return boolean handled
local function preRefresh()
    local barIndex, barType = getActiveOverrideInfo()
    if cooldownTracker.GetEnabled() and barIndex then
        if overrideMode ~= barType then exitOverrideMode() end
        -- Hide tracker icons while override bar owns the grid.  Through the
        -- factory, so each icon's per-icon aura wrapper is parked with it — an
        -- engine-shown cue in a slot button's subtree is not in our alpha chain.
        for _, button in pairs(ctx.activeButtons) do
            ctx.SetButtonAlpha(button, 0)
        end
        if private.CustomSpells then
            private.CustomSpells.OnDisable("CooldownTracker")
        end
        applyOverrideLayout(cooldownTracker.GetSettings(), barIndex, barType)
        return true
    end
    -- Leaving override mode: restore normal spell grid.
    if overrideMode then exitOverrideMode() end
    return false
end

---Swipe-watcher seam: in override mode run the content-only pass and suppress
---the factory's membership-change relayout (tracker icons are parked).
---@param settings viewer_tracker_profile_main
---@return boolean handled
local function postSwipeUpdate(settings)
    if overrideMode then
        refreshOverrideContent(settings)
        return true
    end
    return false
end

---Collapsed override: in override mode, collapsed = no override frames shown.
---@return boolean|nil
local function isCollapsedOverride()
    if overrideMode then
        for i = 1, #overrideFrames do
            if overrideFrames[i]:IsShown() then return false end
        end
        return true
    end
    return nil
end

---Size override: in override mode, size from the shown override frames.
---@return number|nil, number|nil
local function getComponentSizeOverride()
    if not overrideMode then return nil end
    local settings = cooldownTracker.GetSettings()
    local iconSize = settings.icon_size > 0 and settings.icon_size or 50
    local iconHeight = (settings.icon_height and settings.icon_height > 0) and settings.icon_height or iconSize
    local xPad = settings.icon_offset or 1
    local count = 0
    for i = 1, #overrideFrames do
        if overrideFrames[i]:IsShown() then count = count + 1 end
    end
    if count == 0 then return 0, 0 end
    return math.max(count * iconSize + (count - 1) * xPad, settings.min_width or 0), iconHeight
end

---Create the override watcher (bar state transitions only; cooldown/usability
---content updates run through the factory's swipe watcher).
local function afterInitialize()
    overrideWatcher = CreateFrame("Frame")
    overrideWatcher:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    overrideWatcher:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
    overrideWatcher:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
    overrideWatcher:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
    overrideWatcher:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
    overrideWatcher:SetScript("OnEvent", function()
        cooldownTracker.Refresh()
    end)
end

local function onEnable()
    if overrideWatcher then
        overrideWatcher:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
        overrideWatcher:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
        overrideWatcher:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
        overrideWatcher:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
        overrideWatcher:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
    end
end

local function onDisable()
    exitOverrideMode()
    clearRoutedAddonIcons()
    if overrideWatcher then overrideWatcher:UnregisterAllEvents() end
end

-- ---------------------------------------------------------------------------
-- Component creation
-- ---------------------------------------------------------------------------

cooldownTracker, ctx = private.IconTracker.CreateTracker({
    name = "CooldownTracker",
    containerName = "CUE_CT_Container",
    categoryId = private.Enum.CooldownViewerCategoryIDs.CooldownEssential,
    routeKey = "Essential",
    extraWatcherEvents = { "ACTION_USABLE_CHANGED" },
    hooks = {
        preRefresh = preRefresh,
        postSwipeUpdate = postSwipeUpdate,
        ---True while the override layer owns the container, so the factory's
        ---SyncAlpha leaves the parked base icons at alpha 0.
        ownsContainer = function()
            return overrideMode and true or false
        end,
        isCollapsed = isCollapsedOverride,
        getComponentSizeOverride = getComponentSizeOverride,
        getAppendFrames = collectRoutedAddonIcons,
        afterInitialize = afterInitialize,
        onEnable = onEnable,
        onDisable = onDisable,
        ---Force the frame visible while override ability bars are active
        ---(skyriding, vehicles) so the anchoring system shows the frame
        ---regardless of anchor chain visibility.  GetForceVisible means the
        ---user's explicit Hidden still wins.
        getForceVisible = function()
            return overrideMode and true or false
        end,
    },
})

---Returns true when the icon is currently positioned in our grid.  Source
---components (TrinketTracker, ConsumableTracker) call this to skip the icon in
---their own layout and to style it from our settings instead of theirs.
---@param icon table
---@return boolean
cooldownTracker.IsIconRoutedHere = function(icon)
    for i = 1, #routedList do
        if routedList[i] == icon then return true end
    end
    return false
end

private.CooldownTracker = cooldownTracker
private.ComponentManager.RegisterComponent("CooldownTracker", cooldownTracker)
