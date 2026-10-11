
--[[
    RacialTracker component.
    Displays cooldown icons for the player's active racial abilities in a
    standalone frame.  Layout direction (horizontal or vertical) is configured
    via the "layout" profile setting, independent of anchor side.

    Racial abilities are stored as spellIDs.  For racials with per-class
    variants (Blood Fury, Arcane Torrent) all variant IDs are listed and
    filtered at runtime via C_SpellBook.IsSpellInSpellBook.
--]]

local _
---@type string, private
local addonName, private = ...

---@class private : table
---@field RacialTracker racialtracker

---@class racialtracker : component

---@type racialtracker
---@diagnostic disable-next-line: missing-fields
local racialTracker = {}

racialTracker.name = "RacialTracker"


-- Throttle OnUpdate to ~5 fps for cooldown sweep updates
local UPDATE_INTERVAL = 0.2
local timeSinceLastUpdate = 0

---@type frame?  container frame (plain Frame acting as a viewer-like host)
local racialContainer

---@type table<number, frame>  spellID -> icon frame
local racialIcons = {}

---@type number[]  ordered list of resolved spellIDs for layout iteration
local resolvedSpellIDs = {}

---@type frame?  placeholder icon shown in EditMode when no racials are visible
local placeholderIcon

---@type frame?  event listener frame
local eventFrame
---@type boolean
local keybindEventsRegistered = false

---@return racial_tracker_profile_main
local getSettings
getSettings = function()
    return private.profile.components[racialTracker.name]
end

racialTracker.GetSettings = getSettings

local getEnabled = function()
    local settings = getSettings()
    return settings.enabled
end

racialTracker.GetEnabled = getEnabled


-- ============================================================================
-- Racial Spell Registry — keyed by UnitRace() race token
-- Each entry is a list of spellIDs.  For class-variant racials (Blood Fury,
-- Arcane Torrent) all variants are listed; IsSpellInSpellBook filters at
-- runtime to the player's class.
--
-- A race can also carry the same racial under different spellIDs on different
-- clients: Blizzard renumbered several between 1.x and retail, and the id the
-- other client uses is simply absent from this one's data.  List both — the
-- same filter resolves whichever the running client actually has, so one table
-- is correct everywhere and nothing here branches on the client.
--
-- The Forever entries are not guesses: they are every active, cooldown-bearing
-- ability on that client's racial skill lines, taken from its own DB2 (build
-- 1.60.1.69913, 2026-09-18) — SkillLine -> SkillLineAbility -> SpellName, kept
-- to spells with a non-zero SpellCooldowns recovery and without
-- SPELL_ATTR0_PASSIVE. Recipe in `.context/memory/reference_spell_data_lookup.md`.
-- Passives (Quickness, Hardiness, Touch of the Grave, Big Game Hunter …) and
-- cooldown-less toggles (Find Treasure, Plainsrunning) are deliberately absent:
-- this component draws cooldown icons.
--
-- Forever both renumbers and invents. Will to Survive is 1259718 there against
-- retail's 59752, and Elune's Light / Shatter Curse / Eureka! / Rapid
-- Regeneration / the whole Skyborne set exist in no retail build at all.
-- ============================================================================

---@type table<string, number[]>
local RACIAL_SPELLS = {
    -- Alliance
    Human       = { 59752, 20600, 1259718 }, -- Will to Survive (retail id; Forever id); Perception
    Dwarf       = { 20594 },           -- Stoneform
    NightElf    = { 58984, 20580, 1259799 }, -- Shadowmeld (retail id; 1.x id); Elune's Light
    Gnome       = { 20589, 1259812, 1259821, 1259823, 1259817, 1259813 }, -- Escape Artist; Eureka! (per-class)
    Draenei     = { 28880 },           -- Gift of the Naaru
    Worgen      = { 68992 },           -- Darkflight
    -- Horde
    Orc         = { 20572, 33702, 33697, 1299026 }, -- Blood Fury (AP / Spell / Both); Shatter Curse
    Scourge     = { 7744, 20577 },     -- Will of the Forsaken, Cannibalize
    Tauren      = { 20549 },           -- War Stomp
    Troll       = { 26297, 20554, 1260270 }, -- Berserking (retail id; 1.x id); Rapid Regeneration
    BloodElf    = { 28730, 25046, 50613, 69179, 80483, 129597, 202719, 155145 }, -- Arcane Torrent (Mana/Energy/RP/Rage/Focus/Chi/Fury/HoPo)
    Goblin      = { 69070, 69041 },    -- Rocket Jump, Rocket Barrage
    -- Neutral
    Pandaren    = { 107079 },          -- Quaking Palm
    -- Allied — Alliance
    VoidElf             = { 256948 },  -- Spatial Rift
    LightforgedDraenei  = { 255647 },  -- Light's Judgment
    DarkIronDwarf       = { 265221 },  -- Fireblood
    KulTiran            = { 287712 },  -- Haymaker
    Mechagnome          = { 312924 },  -- Hyper Organic Light Originator
    -- Allied — Horde
    Nightborne          = { 260364 },  -- Arcane Pulse
    HighmountainTauren  = { 255654 },  -- Bull Rush
    MagharOrc           = { 274738 },  -- Ancestral Call
    ZandalariTroll      = { 291944 },  -- Regeneratin'
    Vulpera             = { 312411 },  -- Bag of Tricks
    -- Neutral
    Dracthyr            = { 357214, 368970 }, -- Wing Buffet, Tail Swipe
    EarthenDwarf        = { 436344 },  -- Azerite Surge
    EarthenAlliance     = { 436344 },  -- Azerite Surge
    EarthenHorde        = { 436344 },  -- Azerite Surge
    Harronir            = { 1237885 }, -- Thorn Bloom
    -- Forever-only race (ChrRaces 95 "High Order Skyborne" / 96 "Windshaper
    -- Skyborne", both UnitRace token "Skyborne")
    Skyborne            = { 1259705, 1259416, 1259686 }, -- Read Ley Line, Walk on Air, Skysight
}

-- ============================================================================
-- Spell resolution
-- ============================================================================

---Resolve racial spellIDs for the current character.
---Populates resolvedSpellIDs with the IDs present in the player's spellbook.
local function resolveSpells()
    wipe(resolvedSpellIDs)
    local _, raceToken = UnitRace("player")
    if not raceToken then return end

    local spellIDs = RACIAL_SPELLS[raceToken]
    if not spellIDs then return end

    for _, spellID in ipairs(spellIDs) do
        if C_SpellBook.IsSpellInSpellBook(spellID, Enum.SpellBookSpellBank.Player, true) then
            resolvedSpellIDs[#resolvedSpellIDs + 1] = spellID
        end
    end
end

-- ============================================================================
-- Icon frames
-- ============================================================================

---Create a single racial icon frame as a child of the container.
---@param container frame
---@param spellID number
---@param index number  1-based index for layoutIndex ordering
---@return frame
local function createRacialIcon(container, spellID, index)
    local icon = CreateFrame("Button", nil, container)
    icon:EnableMouse(false)
    icon.spellID = spellID
    icon.layoutIndex = index

    -- Install CUE tooltip on this addon-owned icon. Resolver reads icon.spellID.
    if private.Tooltip then
        private.Tooltip.Apply(icon, getSettings, function(self)
            if not self.spellID then return nil, nil end
            return "spell", self.spellID
        end, { kind = "own", isSecureClick = false })
    end

    -- Icon texture (fills the button)
    icon.Icon = icon:CreateTexture(nil, "BACKGROUND")
    icon.Icon:SetSnapToPixelGrid(false)
    icon.Icon:SetTexelSnappingBias(0)
    icon.Icon:SetAllPoints()

    local texture = C_Spell.GetSpellTexture(spellID)
    if texture then
        icon.Icon:SetTexture(texture)
    end
    icon.Icon:SetTexCoord(private.Util.GetIconZoomCoords())

    -- Cooldown sweep overlay
    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
    cd:SetSwipeColor(0, 0, 0, 0.7)
    cd:SetHideCountdownNumbers(false)
    cd:SetCountdownAbbrevThreshold(180)
    icon.Cooldown = cd

    -- Duration text: the Cooldown frame's built-in countdown FontString
    icon.DurationText = icon.Cooldown:GetRegions()
    if icon.DurationText then
        -- Reparent above cooldown swipe so text isn't hidden behind it
        local textOverlay = CreateFrame("Frame", nil, icon)
        textOverlay:SetAllPoints(cd)
        textOverlay:SetFrameLevel(cd:GetFrameLevel() + 10)
        icon.DurationText:SetParent(textOverlay)
    end

    -- Keybind text overlay (positioned and styled by keybind_font profile in Refresh)
    icon.KeybindText = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    icon.KeybindText:Hide()

    icon:Hide()
    return icon
end

---Refresh a single racial icon: texture, cooldown sweep, keybind text.
---@param icon frame
local function refreshRacialIcon(icon)
    local spellID = icon.spellID
    if not spellID then
        icon:Hide()
        return
    end

    -- User-excluded racials are always hidden
    local excluded = getSettings().excluded_racials
    if excluded and excluded[spellID] then
        icon:Hide()
        return
    end

    -- Check if the spell is still known (handles spec changes etc.)
    if not C_SpellBook.IsSpellInSpellBook(spellID, Enum.SpellBookSpellBank.Player, true) then
        if icon.KeybindText then icon.KeybindText:Hide() end
        if private.isEditMode then
            icon.Cooldown:Clear()
            icon:Show()
        else
            icon:Hide()
        end
        return
    end

    -- Update icon texture
    local texture = C_Spell.GetSpellTexture(spellID)
    if texture then
        icon.Icon:SetTexture(texture)
        icon.Icon:SetTexCoord(private.Util.GetIconZoomCoords(icon:GetSize()))
    end

    -- Update cooldown sweep (startTime/duration are secret — pass duration object to widget)
    -- isActive lives on SpellCooldownInfo (GetSpellCooldown), not the DurationObject.
    local cdStatus = C_Spell.GetSpellCooldown(spellID)
    local hasCooldown = cdStatus and cdStatus.isActive
    -- Reverse swipe direction: routed icons use AF setting; non-routed use RacialTracker's.
    -- Set before the duration and on every pass — the swipe reads its direction
    -- when it starts, so a SetReverse that follows SetCooldown only reaches the
    -- next cooldown (see refreshButtonContent in Core/IconTracker.lua).
    local afm = private.AdditionalFrameManager
    local afSettings = afm and afm.GetRoutedFrameSettings(spellID, "Racial")
    local doReverse = afSettings and afSettings.reverse_swipe
        or (not afSettings and getSettings().reverse_swipe)
    icon.Cooldown:SetReverse(doReverse == true)
    if hasCooldown then
        local cdDur = C_Spell.GetSpellCooldownDuration(spellID)
        icon.Cooldown:SetCooldownFromDurationObject(cdDur)
        -- Suppress swipe during GCD when hide_gcd_swipe is enabled.
        -- Must run synchronously here because SPELL_UPDATE_COOLDOWN re-calls
        -- this function frequently, overriding deferred onUpdate suppression.
        -- Routed icons use the AF's setting; non-routed use RacialTracker's.
        local hideGCDSwipe = afSettings and afSettings.hide_gcd_swipe
            or (not afSettings and getSettings().hide_gcd_swipe)
        if hideGCDSwipe then
            local gcdStatus = C_Spell.GetSpellCooldown(private.GCD_SPELL_ID)
            local gcdActive = gcdStatus and gcdStatus.isActive
            if gcdActive and not icon._cueOnRealCooldown then
                icon.Cooldown:SetDrawSwipe(false)
                icon._cueSwipeSuppressed = true
            end
        end
    else
        icon.Cooldown:Clear()
    end

    -- Hide all cooldown countdown text when setting is on
    icon.Cooldown:SetHideCountdownNumbers(getSettings().hide_cd_text == true)

    -- Update keybind text
    local keybindFont = getSettings().keybind_font
    if keybindFont and keybindFont.enabled and icon.KeybindText then
        local keybindText = private.Util.GetKeybindTextForSpell(spellID)
        if keybindText then
            icon.KeybindText:SetText(keybindText)
            icon.KeybindText:Show()
        else
            icon.KeybindText:Hide()
        end
    elseif icon.KeybindText then
        icon.KeybindText:Hide()
    end

    icon:Show()
end

---Refresh all racial icons.
local function refreshAllIcons()
    for _, icon in pairs(racialIcons) do
        refreshRacialIcon(icon)
    end
end

-- ============================================================================
-- Cooldown tracking via OnUpdate
-- ============================================================================

---OnUpdate handler: periodically refresh cooldown sweeps.
---Glow effects are skipped for racials because spell cooldown values are
---secret numbers that cannot be compared or used in arithmetic.
local function onUpdate(self, elapsed)
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    if timeSinceLastUpdate < UPDATE_INTERVAL then return end
    timeSinceLastUpdate = 0

    local racialHideGCD = getSettings().hide_gcd_swipe
    local afm = private.AdditionalFrameManager

    for _, icon in pairs(racialIcons) do
        if icon:IsShown() then
            -- Routed icons use the AF's setting; non-routed use RacialTracker's.
            local afSettings = afm and afm.GetRoutedFrameSettings(icon.spellID, "Racial")
            local hideGCD = afSettings and afSettings.hide_gcd_swipe
                or (not afSettings and racialHideGCD)
            local gcdStatus = hideGCD and C_Spell.GetSpellCooldown(private.GCD_SPELL_ID)
            local gcdActive = gcdStatus and gcdStatus.isActive

            local cdStatus = C_Spell.GetSpellCooldown(icon.spellID)
            local hasCooldown = cdStatus and cdStatus.isActive

            local noDesat = afSettings and afSettings.no_desaturation
                or (not afSettings and getSettings().no_desaturation)
            icon.Icon:SetDesaturated(hasCooldown and not noDesat)

            -- Only update the CooldownFrame on state transitions
            if hasCooldown and not icon.wasOnCooldown then
                local cdDur = C_Spell.GetSpellCooldownDuration(icon.spellID)
                -- Direction before duration; see the refresh path above.
                local doReverse = afSettings and afSettings.reverse_swipe
                    or (not afSettings and getSettings().reverse_swipe)
                icon.Cooldown:SetReverse(doReverse == true)
                icon.Cooldown:SetCooldownFromDurationObject(cdDur)
                icon.wasOnCooldown = true
                -- Suppress swipe when entering cooldown during GCD and the
                -- icon had no real cooldown before GCD started.
                if gcdActive and not icon._cueOnRealCooldown then
                    icon.Cooldown:SetDrawSwipe(false)
                    icon._cueSwipeSuppressed = true
                end
            elseif not hasCooldown and icon.wasOnCooldown then
                icon.Cooldown:Clear()
                icon.wasOnCooldown = false
                icon._cueSwipeSuppressed = nil
            end
            -- Restore swipe once GCD ends for icons that were suppressed
            if icon._cueSwipeSuppressed and not gcdActive then
                icon.Cooldown:SetDrawSwipe(true)
                icon._cueSwipeSuppressed = nil
            end
            -- Track real cooldown state only when GCD is inactive.
            -- This gives us a snapshot of which icons were on actual cooldown
            -- before GCD started, so we can distinguish GCD-only from real.
            if hideGCD and not gcdActive then
                icon._cueOnRealCooldown = hasCooldown
            end
        end
    end
end

-- ============================================================================
-- Event handling
-- ============================================================================

local function onEvent(self, event, ...)
    if event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        -- Re-resolve spells (handles spec change, talent swap, etc.)
        local previousIDs = {}
        for _, id in ipairs(resolvedSpellIDs) do previousIDs[id] = true end

        resolveSpells()

        -- Check if the set of known racials changed
        local changed = false
        if #resolvedSpellIDs ~= 0 or next(previousIDs) then
            for _, id in ipairs(resolvedSpellIDs) do
                if not previousIDs[id] then changed = true; break end
                previousIDs[id] = nil
            end
            if not changed and next(previousIDs) then changed = true end
        end

        if changed and racialContainer then
            -- Rebuild icons for the new set of spells
            for spellID, icon in pairs(racialIcons) do
                icon:Hide()
            end

            for i, spellID in ipairs(resolvedSpellIDs) do
                if not racialIcons[spellID] then
                    racialIcons[spellID] = createRacialIcon(racialContainer, spellID, i)
                else
                    racialIcons[spellID].layoutIndex = i
                end
            end

            racialTracker.Refresh()
            private.Anchor.Refresh()
        else
            refreshAllIcons()
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        -- Handled by OnUpdate for throttling, but do a quick refresh
        -- to catch the initial cooldown set
        for _, icon in pairs(racialIcons) do
            if icon:IsShown() then
                refreshRacialIcon(icon)
            end
        end
    end
end

-- ============================================================================
-- Routing helpers (for AdditionalFrameManager)
-- ============================================================================

---Returns true if any racial icons are routed to additional frames.
---@return boolean
local function hasRoutedIcons()
    local afm = private.AdditionalFrameManager
    if not afm then return false end
    for _, spellID in ipairs(resolvedSpellIDs) do
        if afm.IsSpellRouted(spellID, "Racial") then
            return true
        end
    end
    return false
end

---Count how many racial spells are currently routed to additional frames.
---@return number
local function getRoutedCount()
    local afm = private.AdditionalFrameManager
    if not afm then return 0 end
    local count = 0
    for _, spellID in ipairs(resolvedSpellIDs) do
        if afm.IsSpellRouted(spellID, "Racial") then
            count = count + 1
        end
    end
    return count
end

---Count how many racial spells are user-excluded via profile settings.
---A spell that is also routed is left to getRoutedCount: subtracting it twice
---drove the icon limit to 0 and collapsed the container under live icons.
---@return number
local function getExcludedCount()
    local excluded = getSettings().excluded_racials
    if not excluded then return 0 end
    local afm = private.AdditionalFrameManager
    local count = 0
    for _, spellID in ipairs(resolvedSpellIDs) do
        if excluded[spellID] and not (afm and afm.IsSpellRouted(spellID, "Racial")) then
            count = count + 1
        end
    end
    return count
end

-- ============================================================================
-- Layout
-- ============================================================================

---Returns the number of icons that should be shown (excluding routed and excluded ones).
---@return number
local function getVisibleIconCount()
    local count = 0
    local excluded = getSettings().excluded_racials
    for _, spellID in ipairs(resolvedSpellIDs) do
        if not (excluded and excluded[spellID]) then
            local icon = racialIcons[spellID]
            if icon and icon:IsShown() then
                local afm = private.AdditionalFrameManager
                if not (afm and afm.IsSpellRouted(spellID, "Racial")) then
                    count = count + 1
                end
            end
        end
    end
    return count
end

---Create (or return existing) placeholder icon for EditMode.
---@return frame
local function getOrCreatePlaceholder()
    if placeholderIcon then return placeholderIcon end
    placeholderIcon = CreateFrame("Button", nil, racialContainer)
    placeholderIcon:EnableMouse(false)
    placeholderIcon.Icon = placeholderIcon:CreateTexture(nil, "BACKGROUND")
    placeholderIcon.Icon:SetSnapToPixelGrid(false)
    placeholderIcon.Icon:SetTexelSnappingBias(0)
    placeholderIcon.Icon:SetAllPoints()
    placeholderIcon.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    placeholderIcon.Icon:SetTexCoord(private.Util.GetIconZoomCoords())
    placeholderIcon:Hide()
    return placeholderIcon
end

---Re-applies the icon layout using the profile's layout direction.
local applyLayout = function()
    if not racialContainer then return end
    -- No combat guard: container and icons are unprotected frames. Anchoring.lua
    -- writes SetHeight(parentH) in percent-match mode; applyLayout must run in
    -- combat to restore the content-driven height, else the center-pivoted
    -- anchor drifts icons up by (parentH - contentH) / 2.

    local settings = getSettings()
    local iconSize = settings.icon_size
    local iconOffset = settings.icon_offset
    local isVertical = settings.layout == "vertical"
    local iconLimit = math.max(#resolvedSpellIDs - getRoutedCount() - getExcludedCount(), 0)

    -- Resolve icon height override (0 or nil = square).
    local hasIconHeight = settings.icon_height and settings.icon_height > 0
    local iconHeight = hasIconHeight and math.floor(settings.icon_height) or iconSize

    -- In EditMode, always show at least one icon (placeholder if needed)
    local showPlaceholder = false
    if private.isEditMode and iconLimit <= 0 then
        showPlaceholder = true
        iconLimit = 1
    end

    if iconLimit <= 0 then
        racialContainer:SetSize(1, 1)
        if placeholderIcon then placeholderIcon:Hide() end
        local bgS = settings.background
        if bgS then private.Util.ApplyComponentBackground(racialContainer, bgS) end
        return
    end

    -- Compute container size
    local containerWidth, containerHeight
    if isVertical then
        containerWidth = iconSize
        containerHeight = iconLimit * iconHeight + (iconLimit - 1) * iconOffset
    else
        containerWidth = iconLimit * iconSize + (iconLimit - 1) * iconOffset
        containerHeight = iconHeight
    end

    racialContainer:SetSize(containerWidth, containerHeight)

    -- Show/hide placeholder
    local ph = getOrCreatePlaceholder()
    if showPlaceholder then
        ph:SetSize(iconSize, iconHeight)
        ph:ClearAllPoints()
        private.Pixel.SetPoint(ph, "TOPLEFT", racialContainer, "TOPLEFT", 0, 0)
        ph:Show()
        if ph.Icon then
            ph.Icon:SetTexCoord(private.Util.GetIconZoomCoords(iconSize, iconHeight))
        end
        private.Util.ApplyIconBorder(ph)
    else
        ph:Hide()
    end

    -- Position visible, non-routed, non-excluded icons sequentially
    local visibleIndex = 0
    local afm = private.AdditionalFrameManager
    local excluded = settings.excluded_racials
    for _, spellID in ipairs(resolvedSpellIDs) do
        local icon = racialIcons[spellID]
        if icon then
            local isExcluded = excluded and excluded[spellID]
            local isRouted = afm and afm.IsSpellRouted(spellID, "Racial")
            if isExcluded then
                icon:Hide()
            elseif isRouted then
                icon:SetSize(iconSize, iconHeight)
            else
                icon:SetSize(iconSize, iconHeight)
                icon:ClearAllPoints()
                if icon:IsShown() then
                    if isVertical then
                        private.Pixel.SetPoint(icon, "TOPLEFT", racialContainer, "TOPLEFT", 0, -visibleIndex * (iconHeight + iconOffset))
                    else
                        private.Pixel.SetPoint(icon, "TOPLEFT", racialContainer, "TOPLEFT", visibleIndex * (iconSize + iconOffset), 0)
                    end
                    visibleIndex = visibleIndex + 1
                end
                if icon.Icon then
                    icon.Icon:SetTexCoord(private.Util.GetIconZoomCoords(iconSize, iconHeight))
                end
                private.Util.ApplyIconBorder(icon)
            end
        end
    end

    -- Update background visibility after layout
    local bgS = settings.background
    if bgS then private.Util.ApplyComponentBackground(racialContainer, bgS) end
end

-- ============================================================================
-- Component lifecycle
-- ============================================================================

racialTracker.Initialize = function()
    -- Resolve racial spells for the current character
    resolveSpells()

    -- Create the container frame (plain Frame positioned by the anchoring system)
    racialContainer = CreateFrame("Frame", "CUE_RacialTracker", UIParent)
    racialContainer:SetSize(60, 50)

    -- Create one icon per resolved racial spell
    for i, spellID in ipairs(resolvedSpellIDs) do
        racialIcons[spellID] = createRacialIcon(racialContainer, spellID, i)
    end

    -- Register events
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", onEvent)
    eventFrame:RegisterEvent("SPELLS_CHANGED")
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- OnUpdate for cooldown sweep animation
    racialContainer:SetScript("OnUpdate", onUpdate)

    -- No OnEnterCombat refresh: at PLAYER_REGEN_DISABLED the lockdown has not
    -- started, so it redrew the pre-combat state already on screen, in the pull
    -- frame.
    private.Callback.Register("OnLeaveCombat", function()
        racialTracker.Refresh()
    end)

    racialTracker.Refresh()
end

racialTracker.GetFrame = function()
    return racialContainer
end

---No-op: glow effects are not supported for racials (spell cooldown values are secret).
racialTracker.StopAllGlows = function() end

---A font edit made while hidden waits for the Refresh that shows the icons:
---the pass that reveals them carries no font pass.
local fontsOwed = false

racialTracker.Refresh = function()
    if not racialContainer then return end
    if private.fontsDirty then fontsOwed = true end

    local shouldShow = (getEnabled() or private.isEditMode)
        and private.Anchor.IsVisibleForComponent(racialTracker.name)
    if shouldShow then
        racialContainer:SetAlpha(private.Anchor.GetEffectiveAlpha(racialTracker.name))
        racialContainer:Show()
        -- Apply font profiles only when settings may have changed
        if fontsOwed then
            fontsOwed = false
            local settings = getSettings()
            for _, icon in pairs(racialIcons) do
                if settings.duration_font then
                    private.Util.ApplyFontProfile(icon.DurationText, settings.duration_font, icon)
                end
                if settings.keybind_font and icon.KeybindText then
                    private.Util.ApplyFontProfile(icon.KeybindText, settings.keybind_font, icon)
                end
            end
        end
        refreshAllIcons()
    elseif hasRoutedIcons() then
        -- Disabled but has routed icons: keep container alive at alpha 0.
        racialContainer:SetAlpha(0)
        racialContainer:Show()
        refreshAllIcons()
    else
        racialContainer:Hide()
    end

    -- Keybind text: Util's shared watcher invalidates the keybind cache and
    -- fires OnKeybindsChanged once per burst of binding / action-bar changes.
    if not keybindEventsRegistered then
        keybindEventsRegistered = true
        private.Callback.Register("OnKeybindsChanged", refreshAllIcons)
    end

    applyLayout()

    -- Notify AF manager that racial icons may have changed
    if private.AdditionalFrameManager and private.AdditionalFrameManager.OnAddonIconRefresh then
        private.AdditionalFrameManager.OnAddonIconRefresh()
    end
end

racialTracker.OnEnable = function()
    if racialContainer then
        racialContainer:SetAlpha(private.Anchor.GetEffectiveAlpha(racialTracker.name))
        racialContainer:Show()
        racialTracker.Refresh()
    end
end

racialTracker.OnDisable = function()
    if racialContainer then
        if hasRoutedIcons() then
            racialContainer:SetAlpha(0)
        else
            racialContainer:Hide()
        end
    end
end

racialTracker.GetComponentName = function()
    return racialTracker.name
end

---Return the icon frame for a specific racial spell.
---Used by AdditionalFrameManager to find routed racial icons.
---@param spellID number
---@return frame|nil
racialTracker.GetIconFrame = function(spellID)
    return racialIcons[spellID]
end

---Return all resolved racial spell IDs for the current character.
---Used by the Options spell dropdown to list available racials.
---@return number[]
racialTracker.GetResolvedSpellIDs = function()
    return resolvedSpellIDs
end

---RacialTracker always uses its own computed content width.
racialTracker.GetWantsContentWidth = function()
    return true
end

racialTracker.IsCollapsed = function()
    return getVisibleIconCount() == 0
end

racialTracker.GetComponentSize = function()
    local settings = getSettings()
    local iconLimit = math.max(#resolvedSpellIDs - getRoutedCount() - getExcludedCount(), 0)

    -- In EditMode, always report at least one icon worth of size
    if private.isEditMode and iconLimit <= 0 then
        iconLimit = 1
    end

    if iconLimit <= 0 then
        return 0, 0
    end

    local iconSize = settings.icon_size
    local iconOffset = settings.icon_offset
    local isVertical = settings.layout == "vertical"
    local iconHeight = (settings.icon_height and settings.icon_height > 0) and math.floor(settings.icon_height) or iconSize

    if isVertical then
        return iconSize, iconLimit * iconHeight + (iconLimit - 1) * iconOffset
    else
        return iconLimit * iconSize + (iconLimit - 1) * iconOffset, iconHeight
    end
end

private.RacialTracker = racialTracker
racialTracker.ContentLayout = function()
    refreshAllIcons()
    applyLayout()
end

private.ComponentManager.RegisterComponent("RacialTracker", racialTracker)
