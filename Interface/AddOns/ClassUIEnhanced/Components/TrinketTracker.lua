
--[[
    TrinketTracker component.
    Displays cooldown icons for equipped on-use trinkets in a standalone frame.
    Layout direction (horizontal or vertical) is configured via the "layout"
    profile setting, independent of anchor side.
--]]

local _
---@type string, private
local addonName, private = ...
local LAC = LibStub("LibAuraContainer-1.0")

---@class private : table
---@field TrinketTracker trinkettracker

---@class trinkettracker : component

---@type trinkettracker
---@diagnostic disable-next-line: missing-fields
local trinketTracker = {}

trinketTracker.name = "TrinketTracker"

-- Trinket equipment slot IDs (from GetInventorySlotInfo)
local TRINKET_SLOT_1 = 13  -- Trinket0Slot
local TRINKET_SLOT_2 = 14  -- Trinket1Slot
local TRINKET_SLOTS = { TRINKET_SLOT_1, TRINKET_SLOT_2 }

-- GCD threshold: cooldowns shorter than this are treated as GCD and ignored
local GCD_THRESHOLD = 1.5

-- Throttle OnUpdate to ~5 fps for cooldown sweep updates
local UPDATE_INTERVAL = 0.2
local timeSinceLastUpdate = 0

-- The active-buff readout ticks at its own display granularity (tenths). It reads
-- only cached state, so it is far cheaper than the cooldown poll above.
local TEXT_INTERVAL = 0.1
local timeSinceLastText = 0

-- Debounce window for duplicate SPELL_UPDATE_COOLDOWN of the same proc spell.
-- A genuine re-proc lands well outside this; a same-frame double-fire does not.
local PROC_DEDUP_WINDOW = 0.1

---@type frame?  container frame (plain Frame acting as a viewer-like host)
local trinketContainer

---@type table<number, frame>  slotID -> icon frame
local trinketIcons = {}

---@type frame?  event listener frame
local eventFrame
---@type boolean
local keybindEventsRegistered = false

---@type table<number, number>  proc buff spellID -> trinket slotID (equipped proc trinkets)
local procSpellSlots = {}

-- Forward declaration: defined after isSlotRouted, used in onUpdate
local getVisualSettings

---@return trinket_tracker_profile_main
local getSettings = function()
    return private.profile.components[trinketTracker.name]
end

trinketTracker.GetSettings = getSettings

local getEnabled = function()
    local settings = getSettings()
    return settings.enabled
end

trinketTracker.GetEnabled = getEnabled

---Check whether a trinket slot is hidden by slot visibility or item blacklist.
---@param slotID number
---@return boolean
local function isSlotExcluded(slotID)
    local settings = getSettings()
    if slotID == TRINKET_SLOT_1 and settings.show_slot_1 == false then return true end
    if slotID == TRINKET_SLOT_2 and settings.show_slot_2 == false then return true end
    local itemID = GetInventoryItemID("player", slotID)
    if itemID and settings.excluded_trinkets and settings.excluded_trinkets[itemID] then return true end
    return false
end

---True when a slot holds a trackable trinket (on-use, or a passive with
---show_passive) and is not excluded.
---@param slotID number
---@return boolean
local function isSlotActive(slotID)
    if isSlotExcluded(slotID) then return false end
    local itemID = GetInventoryItemID("player", slotID)
    local data = private.TrinketData
    return itemID ~= nil and (C_Item.GetItemSpell(itemID) ~= nil
        or (getSettings().show_passive and data ~= nil and (data.proc[itemID] or data.stacks[itemID]) ~= nil))
end

---Count how many trinket slots have an equipped on-use item (respecting excludes).
---@return number
local function getActiveTrinketCount()
    local count = 0
    for _, slotID in ipairs(TRINKET_SLOTS) do
        if isSlotActive(slotID) then
            count = count + 1
        end
    end
    return count
end

---Rebuild the proc buff spellID -> slotID index for equipped proc trinkets.
---Called from refreshAllIcons; drives the SPELL_UPDATE_COOLDOWN handler.
local function rebuildProcIndex()
    wipe(procSpellSlots)
    local data = private.TrinketData
    if not data then return end
    if not getSettings().show_passive then return end
    for _, slotID in ipairs(TRINKET_SLOTS) do
        if not isSlotExcluded(slotID) then
            local itemID = GetInventoryItemID("player", slotID)
            local procData = itemID and data.proc[itemID]
            if procData then
                for _, spellID in ipairs(procData.ids) do
                    procSpellSlots[spellID] = slotID
                end
            end
        end
    end
end

---Returns the effective icon limit for sizing the container frame.
---In Edit Mode: always all slots (both visible for repositioning).
---At runtime with reserve_slots: always all slots (stable frame size).
---At runtime without reserve_slots: only active on-use trinkets (frame collapses).
---@return number
local function getEffectiveIconLimit()
    if private.isEditMode then
        return #TRINKET_SLOTS
    end
    local settings = getSettings()
    if settings.reserve_slots then
        return #TRINKET_SLOTS
    end
    return getActiveTrinketCount()
end

local parseItemBuffDuration = private.Util.ParseItemBuffDuration

-- Re-issuing SetCooldown with identical values restarts the engine's countdown,
-- so the shown seconds jump and stagger on every poll tick and every
-- SPELL_UPDATE_COOLDOWN. No timing clears.
local setIconCooldown = private.Util.SetIconCooldown

---Refresh a single trinket icon: item texture, use-effect detection, cooldown sweep.
---In Edit Mode, shows all slots with placeholder textures for empty or passive trinkets.
---@param icon frame
local function refreshTrinketIcon(icon)
    local slotID = icon.slotID

    -- Slot visibility / item blacklist
    if isSlotExcluded(slotID) then
        icon:Hide()
        return
    end

    local itemID = GetInventoryItemID("player", slotID)
    local data = private.TrinketData
    local spellName = itemID and C_Item.GetItemSpell(itemID)
    -- Proc trinkets have no on-use spell (GetItemSpell == nil); identify them by DB.
    local procData = (not spellName) and itemID and data and data.proc[itemID] or nil
    -- A `stacks` trinket shows like a proc trinket but has no proc window: its only
    -- readout is the engine-bound stack count (syncStackTap), and procData stays nil.
    local isStacks = (not spellName) and itemID and data and data.stacks[itemID] ~= nil
    local settings = getSettings()
    -- When show_passive is off, a proc trinket routes into the placeholder/hide branch.
    local showProc = (procData or isStacks) and settings.show_passive

    -- No item, no on-use effect, and not a shown proc trinket: placeholder / hide.
    if not spellName and not showProc then
        icon.isProc = nil
        icon.procData = nil
        icon.procItemID = nil
        icon.activeBuffDuration = nil
        icon.activeBuffExpiry = nil
        if icon.KeybindText then icon.KeybindText:Hide() end
        if icon.BuffDurationText then icon.BuffDurationText:Hide() end
        if private.isEditMode then
            local tex = itemID and C_Item.GetItemIconByID(itemID) or nil
            icon.Icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
            icon.Icon:SetTexCoord(private.Util.GetIconZoomCoords(icon:GetSize()))
            setIconCooldown(icon)
            icon:Show()
        else
            icon:Hide()
        end
        return
    end

    -- Proc trinket: the ICD sweep, active-window glow and stack count are driven by
    -- SPELL_UPDATE_COOLDOWN (see onProcFired). Here we only set texture and state and
    -- show the icon -- bright when idle, greyed with the ICD timer once it fires.
    if showProc then
        -- Only drop proc runtime state on an actual item swap -- this path also runs
        -- on every BAG_UPDATE_COOLDOWN, where the live proc window must survive.
        if icon.procItemID ~= itemID then
            icon.procSpellID = nil
            icon.lastProcTime = nil
            icon.lastProcSpellID = nil
            icon.stackCount = nil
            icon.stackExpiry = nil
            icon.activeBuffExpiry = nil
            icon.procItemID = itemID
        end
        icon.isProc = true
        icon.procData = procData
        icon.activeBuffDuration = procData and procData.durs[1]
        local procTexture = C_Item.GetItemIconByID(itemID)
        if procTexture then
            icon.Icon:SetTexture(procTexture)
            icon.Icon:SetTexCoord(private.Util.GetIconZoomCoords(icon:GetSize()))
        end
        if icon.KeybindText then icon.KeybindText:Hide() end
        icon:Show()
        return
    end

    icon.isProc = nil
    icon.procData = nil
    icon.procItemID = nil

    -- Cache the item's buff duration for active glow tracking in onUpdate
    icon.activeBuffDuration = (data and data.onUse[itemID]) or parseItemBuffDuration(itemID)

    -- Update icon texture
    local iconTexture = C_Item.GetItemIconByID(itemID)
    if iconTexture then
        icon.Icon:SetTexture(iconTexture)
        icon.Icon:SetTexCoord(private.Util.GetIconZoomCoords(icon:GetSize()))
    end

    -- Update cooldown sweep
    local start, duration, cdEnabled = GetInventoryItemCooldown("player", slotID)
    if start and start > 0 and duration and duration > GCD_THRESHOLD and cdEnabled == 1 then
        setIconCooldown(icon, start, duration)
        -- Preserve countdown suppression when buff duration display is active
        if icon.activeBuffExpiry and GetTime() < icon.activeBuffExpiry and getSettings().show_active_duration then
            icon.Cooldown:SetHideCountdownNumbers(true)
            if icon.DurationText then icon.DurationText:Hide() end
        end
    else
        setIconCooldown(icon)
    end

    -- Update keybind text
    local keybindFont = getSettings().keybind_font
    if keybindFont and keybindFont.enabled and icon.KeybindText then
        local keybindText = private.Util.GetKeybindTextForItem(itemID)
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

-- ── Engine-driven stack counts (`TrinketData.stacks`) ─────────────────────────
-- A `stacks` trinket's aura is secret in combat, so its count cannot be read.
-- Each trinket slot gets an AuraContainer whose single slot binds a FontString
-- through SetApplicationCount, and Blizzard writes the count into it engine-side.
-- Same shape as SecondaryResources' auraTap.ensure.
--
-- The container sits on UIParent, never under trinketContainer: an aura container
-- makes its ancestors protected in combat, and applyLayout resizes trinketContainer
-- in combat on purpose. The FS must be created ON the slot button (the bind rejects
-- a region parented elsewhere) and reaches the icon by a cross-frame anchor, so its
-- visibility follows the container, not the icon -- syncStackTapAlpha mirrors the
-- icon's onto the container. SetAlpha is never protected.

---@type table<number, table>  slotID -> { container, fs, spellID, anchored, alpha }
local stackTaps = {}
local STACK_SLOT_KEY = "stacks"
local NO_SPELLS = {}

---Mirror the icon's on-screen visibility onto its stack tap, so the bound count
---never outlives a hidden, faded or routed-away icon.
---@param slotID number
local function syncStackTapAlpha(slotID)
    local tap = stackTaps[slotID]
    if not tap then return end
    local icon = trinketIcons[slotID]
    local alpha = 0
    if tap.spellID and icon and icon:IsVisible() then
        alpha = icon:IsIgnoringParentAlpha() and icon:GetAlpha() or icon:GetEffectiveAlpha()
    end
    if tap.alpha ~= alpha then
        tap.alpha = alpha
        tap.container:SetAlpha(alpha)
    end
end

---Point slot `slotID`'s stack tap at `spellID` (nil = none), creating it on first
---use. Container creation errors in combat and the bound FS is forbidden while
---auras are secret, so those steps wait for a writable pass -- which costs
---nothing, since trinkets cannot be swapped in combat.
---@param slotID number
---@param spellID number?
local function syncStackTap(slotID, spellID)
    local tap = stackTaps[slotID]
    local writable = not InCombatLockdown() and not C_Secrets.ShouldAurasBeSecret()
    if not tap then
        if not spellID or not writable then return end
        local c = LAC:CreateContainer("CUE_TrinketStacks" .. slotID, UIParent)
        c:SetUnit("player")
        c:SetSize(1, 1)
        c:SetPoint("CENTER")
        c:SetEnabled(true)
        c:Show()
        tap = { container = c }
        stackTaps[slotID] = tap
        c:AddAuraSlot(STACK_SLOT_KEY, "HELPFUL", {
            candidateFilters = { includeSpellIDs = NO_SPELLS },
            initializeFrame = function(button)
                -- Font before the bind: it pushes text at once, and a font-less
                -- SetText errors. No formatter: Blizzard's default leaves 0 and 1
                -- blank, the same ">= 2" rule the proc StackText follows.
                local fs = button:CreateFontString(nil, "OVERLAY")
                fs:SetFontObject(NumberFontNormal)
                fs:SetJustifyH("RIGHT")
                button:SetApplicationCount(fs)
                tap.fs = fs
            end,
        })
    end
    -- Re-filtering is legal at any time, but every call ends in UpdateAllAuras.
    if tap.spellID ~= spellID then
        tap.spellID = spellID
        tap.container:SetAuraSlotCandidateFilters(STACK_SLOT_KEY,
            { includeSpellIDs = spellID and { [spellID] = true } or NO_SPELLS })
    end
    local icon = trinketIcons[slotID]
    if writable and icon then
        if tap.fs and not tap.anchored then
            -- Where the proc StackText sits. The icon never changes, only moves.
            tap.fs:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
            tap.anchored = true
        end
        -- Above the icon's own text overlay (cooldown level + 10).
        tap.container:SetFrameStrata(icon:GetFrameStrata())
        tap.container:SetFrameLevel(icon:GetFrameLevel() + 20)
    end
    syncStackTapAlpha(slotID)
end

---Refresh all trinket icons.
local function refreshAllIcons()
    rebuildProcIndex()
    local data = private.TrinketData
    for slotID, icon in pairs(trinketIcons) do
        refreshTrinketIcon(icon)
        local itemID = icon.isProc and icon.procItemID
        syncStackTap(slotID, itemID and data and data.stacks[itemID] or nil)
    end
end

---Format remaining buff duration for the timer overlay.
---@param remaining number  seconds remaining
---@return string
local function formatDuration(remaining)
    if remaining >= 10 then
        return string.format("%d", remaining)
    else
        return string.format("%.1f", remaining)
    end
end

---Update which duration text is visible on a trinket icon.
---When the buff is active and show_active_duration is on, shows BuffDurationText
---and hides the cooldown countdown. Otherwise shows the cooldown countdown
---when on cooldown, or hides everything.
---@param icon frame
---@param isOnCooldown boolean
---@param vs table?  visual settings override (from CooldownTracker when routed)
local function updateDurationDisplay(icon, isOnCooldown, vs)
    vs = vs or getSettings()
    local showBuff = icon.activeBuffExpiry and GetTime() < icon.activeBuffExpiry and vs.show_active_duration

    local hideCdText = vs.hide_cd_text
    if showBuff then
        icon.Cooldown:SetHideCountdownNumbers(true)
        if icon.DurationText then icon.DurationText:Hide() end
        if icon.BuffDurationText then
            icon.BuffDurationText:SetText(formatDuration(icon.activeBuffExpiry - GetTime()))
            icon.BuffDurationText:Show()
        end
    else
        icon.Cooldown:SetHideCountdownNumbers(hideCdText == true)
        if icon.BuffDurationText then icon.BuffDurationText:Hide() end
        if icon.DurationText then
            if isOnCooldown and not hideCdText then icon.DurationText:Show() else icon.DurationText:Hide() end
        end
    end
end

---Reset transient glow/duration state on a trinket icon.
---@param icon frame
local function resetIconState(icon)
    private.GlowEffect.StopAll(icon)
    icon.wasOnCooldown = nil
    icon.activeBuffExpiry = nil
    icon.stackCount = nil
    icon.stackExpiry = nil
    -- Proc ICD tracking (procSpellID/procItemID/lastProc*) is intentionally NOT reset
    -- here: the ICD ticks regardless of combat, so clearing it would show an on-ICD
    -- proc as ready the moment combat drops. It's dropped only on an item swap
    -- (refreshTrinketIcon's procItemID guard).
    icon.Cooldown:SetHideCountdownNumbers(getSettings().hide_cd_text == true)
    if icon.BuffDurationText then icon.BuffDurationText:Hide() end
    if icon.DurationText then icon.DurationText:Hide() end
    if icon.StackText then icon.StackText:Hide() end
end

---Create a single trinket icon frame as a child of the container.
---@param container frame
---@param slotID number
---@param slotIndex number  1-based index for layoutIndex ordering
---@return frame
local function createTrinketIcon(container, slotID, slotIndex)
    local icon = CreateFrame("Button", nil, container)
    icon:EnableMouse(false)
    icon.slotID = slotID
    icon.layoutIndex = slotIndex

    -- Install CUE tooltip on this addon-owned icon. Resolver reads icon.slotID
    -- and asks GameTooltip to render the equipped inventory item.
    if private.Tooltip then
        private.Tooltip.Apply(icon, getSettings, function(self)
            if not self.slotID then return nil, nil end
            return "inventory", self.slotID
        end, { kind = "own", isSecureClick = false })
    end
    -- Icon texture (fills the button)
    icon.Icon = icon:CreateTexture(nil, "BACKGROUND")
    icon.Icon:SetSnapToPixelGrid(false)
    icon.Icon:SetTexelSnappingBias(0)
    icon.Icon:SetAllPoints()
    icon.Icon:SetTexCoord(private.Util.GetIconZoomCoords())

    -- Cooldown sweep overlay
    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetFrameLevel(icon:GetFrameLevel() + 1)
    cd:SetDrawEdge(false)
    cd:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
    cd:SetSwipeColor(0, 0, 0, 0.7)
    icon.Cooldown = cd

    -- Overlay frame above cooldown swipe for all text elements
    local textOverlay = CreateFrame("Frame", nil, icon)
    textOverlay:SetAllPoints(cd)
    textOverlay:SetFrameLevel(cd:GetFrameLevel() + 10)

    -- Keep Blizzard's cooldown countdown text separate
    icon.DurationText = icon.Cooldown:GetRegions()
    if icon.DurationText then
        icon.DurationText:SetParent(textOverlay)
        icon.DurationText:SetTextColor(1, 1, 1, 1)
        icon.DurationText:Hide()
    end

    -- Buff duration text — parented to textOverlay so it renders above the swipe
    icon.BuffDurationText = textOverlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    icon.BuffDurationText:SetPoint("CENTER", icon, "CENTER", 0, 0)
    icon.BuffDurationText:SetJustifyH("CENTER")
    icon.BuffDurationText:SetJustifyV("MIDDLE")
    icon.BuffDurationText:SetTextColor(1, 1, 1, 1)
    icon.BuffDurationText:Hide()

    -- Stack count text (proc trinkets) — bottom-right corner, above the swipe
    icon.StackText = textOverlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    icon.StackText:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    icon.StackText:SetJustifyH("RIGHT")
    icon.StackText:SetTextColor(1, 1, 1, 1)
    icon.StackText:Hide()

    -- Keybind text overlay (positioned and styled by keybind_font profile in Refresh)
    icon.KeybindText = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    icon.KeybindText:Hide()

    -- A stacks trinket's count lives outside this frame (syncStackTap), so it has to
    -- be told when the icon's visibility changes. OnHide also fires for an ancestor.
    icon:HookScript("OnShow", function(self) syncStackTapAlpha(self.slotID) end)
    icon:HookScript("OnHide", function(self) syncStackTapAlpha(self.slotID) end)

    icon:Hide()
    return icon
end

---Returns true while the player is inside an active Mythic+ keystone run.
---Used to gate the persistent "ready in M+" pulse glow.
local function isInActiveMythicPlus()
    return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive() or false
end

---OnUpdate handler: periodically refresh cooldown sweeps and detect
---cooldown transitions for glow effects.
local function onUpdate(self, elapsed)
    timeSinceLastText = timeSinceLastText + elapsed
    if timeSinceLastText >= TEXT_INTERVAL then
        -- Subtract, don't zero: zeroing discards the frame overshoot, so the real
        -- period drifts to ~0.117s and the tenths visibly skip.
        timeSinceLastText = timeSinceLastText % TEXT_INTERVAL
        local now = GetTime()
        for _, icon in pairs(trinketIcons) do
            local text = icon.BuffDurationText
            if text and text:IsShown() and icon.activeBuffExpiry then
                text:SetText(formatDuration(icon.activeBuffExpiry - now))
            end
        end
    end

    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    if timeSinceLastUpdate < UPDATE_INTERVAL then return end
    timeSinceLastUpdate = timeSinceLastUpdate % UPDATE_INTERVAL

    local inCombat = InCombatLockdown()
    local glowSettings = getSettings().glow
    local glowEnabled = glowSettings and glowSettings.enabled

    for _, icon in pairs(trinketIcons) do
        -- Fades change alpha without a show/hide; cached, so a no-op when unchanged.
        syncStackTapAlpha(icon.slotID)
        if icon:IsShown() then
            local slotID = icon.slotID
            local start, duration, isOnCooldown
            if icon.isProc then
                -- Proc ICD: poll the firing proc spell's cooldown. startTime/duration
                -- are secret in 12.0+, so read only the non-secret isActive/isOnGCD
                -- booleans; the sweep is rendered from the DurationObject below.
                local cdInfo = icon.procSpellID and C_Spell.GetSpellCooldown(icon.procSpellID)
                isOnCooldown = (cdInfo and cdInfo.isActive and not cdInfo.isOnGCD) or false
            else
                local cdEnabled
                start, duration, cdEnabled = GetInventoryItemCooldown("player", slotID)
                isOnCooldown = (start and start > 0 and duration and duration > GCD_THRESHOLD and cdEnabled == 1) or false
            end

            local vs = getVisualSettings(icon)
            icon.Icon:SetDesaturated(isOnCooldown and not vs.no_desaturation)

            if isOnCooldown then
                if icon.isProc then
                    -- Set the ICD sweep once on the off->on transition; re-fetching the
                    -- DurationObject every tick would allocate ~5x/sec (see performance.md).
                    if not icon.wasOnCooldown then
                        icon.Cooldown:SetCooldownFromDurationObject(C_Spell.GetSpellCooldownDuration(icon.procSpellID))
                    end
                else
                    setIconCooldown(icon, start, duration)
                end
                -- Immediately re-suppress countdown in case the cooldown reset it
                if icon.activeBuffExpiry and GetTime() < icon.activeBuffExpiry and vs.show_active_duration then
                    icon.Cooldown:SetHideCountdownNumbers(true)
                    if icon.DurationText then icon.DurationText:Hide() end
                end
            else
                setIconCooldown(icon)
            end

            -- Persistent "ready in M+" glow: independent of combat state.
            -- When the player is inside an active keystone and a trinket is
            -- off cooldown, keep the pulse glow running until it is used or
            -- the player leaves the keystone.
            local persistentReady = glowEnabled
                and glowSettings.ready_in_mplus_enabled
                and glowSettings.pulse_enabled
                and (not isOnCooldown)
                and isInActiveMythicPlus()

            if persistentReady then
                private.GlowEffect.StartPulse(icon, 0)
            elseif icon.persistentReady then
                private.GlowEffect.StopPulse(icon)
            end
            icon.persistentReady = persistentReady

            -- Glow transition detection (combat-only)
            if glowEnabled and inCombat then
                if icon.wasOnCooldown and not isOnCooldown then
                    private.GlowEffect.StopApproaching(icon)
                    if glowSettings.flash_enabled then
                        private.GlowEffect.PlayFlash(icon)
                    end
                    if glowSettings.pulse_enabled and not persistentReady then
                        private.GlowEffect.StartPulse(icon, glowSettings.pulse_duration)
                    end
                elseif not icon.wasOnCooldown and isOnCooldown then
                    private.GlowEffect.StopAll(icon)
                end

                -- Approaching-ready detection (on-use only: procs have no secret-free
                -- numeric ICD remaining, so start/duration are nil for them).
                if not icon.isProc and isOnCooldown and glowSettings.approaching_enabled and glowSettings.approaching_time > 0 then
                    local remaining = (start + duration) - GetTime()
                    if remaining > 0 and remaining <= glowSettings.approaching_time then
                        private.GlowEffect.StartApproaching(icon)
                    else
                        private.GlowEffect.StopApproaching(icon)
                    end
                end

                if not persistentReady and private.GlowEffect.IsPulseExpired(icon) then
                    private.GlowEffect.StopPulse(icon)
                end

                -- Active buff glow
                if glowSettings.active_enabled and icon.activeBuffDuration then
                    -- On-use trinkets open the active window on cooldown start; procs
                    -- stamp activeBuffExpiry in onProcFired when the buff fires.
                    if not icon.isProc and not icon.wasOnCooldown and isOnCooldown then
                        icon.activeBuffExpiry = GetTime() + icon.activeBuffDuration
                    end
                    if icon.activeBuffExpiry and GetTime() < icon.activeBuffExpiry then
                        private.GlowEffect.StartActive(icon)
                    else
                        icon.activeBuffExpiry = nil
                        private.GlowEffect.StopActive(icon)
                    end
                end
            elseif not inCombat and private.GlowEffect.HasGlow(icon) then
                if persistentReady then
                    private.GlowEffect.StopApproaching(icon)
                    private.GlowEffect.StopActive(icon)
                else
                    private.GlowEffect.StopAll(icon)
                end
                icon.activeBuffExpiry = nil
            end

            updateDurationDisplay(icon, isOnCooldown, vs)

            -- Proc stack count overlay (shown at >= 2 stacks; cleared with its window)
            if icon.isProc and icon.stackCount and icon.stackExpiry and GetTime() < icon.stackExpiry then
                if icon.StackText then
                    icon.StackText:SetShown(icon.stackCount > 1)
                    if icon.stackCount > 1 then icon.StackText:SetText(icon.stackCount) end
                end
            else
                icon.stackCount = nil
                icon.stackExpiry = nil
                if icon.StackText then icon.StackText:Hide() end
            end

            -- Replay whatever alert the player configured for this trinket in
            -- Blizzard's Cooldown Manager.  Published from here rather than from
            -- setIconCooldown because this is where the poll
            -- already resolves isOnCooldown for both the on-use and the proc-ICD
            -- shape; CDMAlerts does its own edge detection on top.
            private.CDMAlerts.OnEquipSlotCooldownChanged(slotID, isOnCooldown, icon)

            icon.wasOnCooldown = isOnCooldown
        end
    end
end

---Duration (seconds) of a specific proc buff spellID within a proc entry.
---@param procData table
---@param spellID number
---@return number
local function getProcBuffDuration(procData, spellID)
    for i, sid in ipairs(procData.ids) do
        if sid == spellID then return procData.durs[i] or procData.durs[1] or 0 end
    end
    return procData.durs[1] or 0
end

---Handle a proc trinket firing (SPELL_UPDATE_COOLDOWN): start the ICD sweep, the
---active-window timer and, for the stack buff, the stack count.
---@param icon frame
---@param spellID number
local function onProcFired(icon, spellID)
    local procData = icon.procData
    if not procData then return end

    -- Debounce a same-frame double-fire of this exact proc spell. startTime is a
    -- secret value in 12.0+, so it can't be compared across events; debounce by
    -- wall-clock instead, per spellID so a distinct buff (longest vs stack) firing
    -- alongside this one is still processed.
    local now = GetTime()
    if icon.lastProcSpellID == spellID and icon.lastProcTime
        and (now - icon.lastProcTime) < PROC_DEDUP_WINDOW then
        return
    end
    icon.lastProcSpellID = spellID
    icon.lastProcTime = now

    -- Record the firing spell so onUpdate can poll its (secret) ICD via the
    -- non-secret isActive/isOnGCD booleans and render the sweep from its
    -- DurationObject.
    icon.procSpellID = spellID

    -- Active-window timer (longest buff). Plain numbers -- never secret.
    icon.activeBuffExpiry = now + (procData.durs[1] or 0)

    -- Stack count: each proc of the stack buff adds a stack within its own window.
    if procData.stack and spellID == procData.stack then
        if icon.stackExpiry and now < icon.stackExpiry then
            icon.stackCount = (icon.stackCount or 0) + 1
        else
            icon.stackCount = 1
        end
        icon.stackExpiry = now + getProcBuffDuration(procData, spellID)
    end
end

---Event handler for equipment changes and cooldown updates.
local function onEvent(self, event, ...)
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        local equipSlotID = ...
        if equipSlotID == TRINKET_SLOT_1 or equipSlotID == TRINKET_SLOT_2 then
            -- A new item is a fresh bind: drop the old one's cooldown edge and any
            -- running alert, or swapping an on-cooldown trinket for a ready one
            -- fires the new trinket's "Available" alert on equip.
            if trinketIcons[equipSlotID] then private.CDMAlerts.ReleaseButton(trinketIcons[equipSlotID]) end
            refreshAllIcons()
            trinketTracker.Refresh()
            private.Anchor.Refresh()
        end
    elseif event == "BAG_UPDATE_COOLDOWN" then
        for _, icon in pairs(trinketIcons) do
            if icon:IsShown() then
                refreshTrinketIcon(icon)
            end
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        local spellID = ...
        if not spellID then return end
        local slotID = procSpellSlots[spellID]
        if not slotID then return end
        local icon = trinketIcons[slotID]
        if icon and icon.isProc and icon:IsShown() then
            onProcFired(icon, spellID)
        end
    end
end

---Check whether a trinket slot is routed away from TrinketTracker's own layout.
---A slot is routed if assigned to an AdditionalFrame OR displayed in CooldownTracker.
---@param slotID number
---@return boolean
local function isSlotRouted(slotID)
    local afm = private.AdditionalFrameManager
    if afm and afm.IsSpellRouted(slotID, "Trinket") then return true end
    local ct = private.CooldownTracker
    if ct and ct.IsIconRoutedHere and trinketIcons[slotID] and ct.IsIconRoutedHere(trinketIcons[slotID]) then return true end
    return false
end

---Returns the visual settings to use for a trinket icon.
---When routed to CooldownTracker, returns CT's settings so visual properties
---(desaturation, cd text, duration display) match the host component.
---@param icon frame
---@return table
getVisualSettings = function(icon)
    local ct = private.CooldownTracker
    if ct and ct.IsIconRoutedHere and ct.IsIconRoutedHere(icon) then
        return ct.GetSettings()
    end
    return getSettings()
end

---Returns true if any trinket icons are routed to additional frames or CooldownTracker.
---@return boolean
local function hasRoutedIcons()
    for _, slotID in ipairs(TRINKET_SLOTS) do
        if isSlotRouted(slotID) then
            return true
        end
    end
    return false
end

---Count how many trinket slots are currently routed away from TrinketTracker,
---among the slots getEffectiveIconLimit counted: every slot in Edit Mode or with
---reserve_slots, otherwise only active ones. Counting a routed slot the limit had
---already left out (excluded, or empty) subtracted it twice, drove iconLimit to 0
---and collapsed the container under live icons.
---@return number
local function getRoutedSlotCount()
    local countAll = private.isEditMode or getSettings().reserve_slots
    local count = 0
    for _, slotID in ipairs(TRINKET_SLOTS) do
        if isSlotRouted(slotID) and (countAll or isSlotActive(slotID)) then
            count = count + 1
        end
    end
    return count
end

---Map layout_alignment to the frame_point the anchoring system should use
---so the alignment edge stays fixed when the container resizes.  Only
---applies in free-moving mode (anchor_parent == "none"); anchored mode
---derives growth from the parent relationship.  A Frame Point the user picked
---by hand (`frame_point_manual`) wins; an Edit Mode drag clears it.
local function syncFramePointToAlignment()
    if not trinketContainer then return end
    local settings = getSettings()
    local ap = settings.anchor_profile
    if not ap or ap.anchor_parent ~= "none" or ap.frame_point_manual then return end

    local alignment = settings.layout_alignment or "center"
    local layoutMode = settings.layout

    local desiredFP
    if layoutMode == "horizontal" or layoutMode == nil then
        if alignment == "left" then desiredFP = "left"
        elseif alignment == "right" then desiredFP = "right"
        else desiredFP = "center" end
    elseif layoutMode == "vertical" then
        if alignment == "top" then desiredFP = "top"
        elseif alignment == "bottom" then desiredFP = "bottom"
        else desiredFP = "center" end
    end
    if not desiredFP then return end

    local currentFP = ap.frame_point
    if currentFP == desiredFP then return end

    local left = trinketContainer:GetLeft()
    local right = trinketContainer:GetRight()
    local top = trinketContainer:GetTop()
    local bottom = trinketContainer:GetBottom()
    if not (left and right and top and bottom) then
        ap.frame_point = desiredFP
        return
    end

    local cx, cy = (left + right) / 2, (top + bottom) / 2
    local oldX, oldY = cx, cy
    if currentFP == "left" then oldX = left
    elseif currentFP == "right" then oldX = right
    elseif currentFP == "top" then oldY = top
    elseif currentFP == "bottom" then oldY = bottom
    elseif currentFP == "topleft" then oldX, oldY = left, top
    elseif currentFP == "topright" then oldX, oldY = right, top
    elseif currentFP == "bottomleft" then oldX, oldY = left, bottom
    elseif currentFP == "bottomright" then oldX, oldY = right, bottom
    end

    local newX, newY = cx, cy
    if desiredFP == "left" then newX = left
    elseif desiredFP == "right" then newX = right
    elseif desiredFP == "top" then newY = top
    elseif desiredFP == "bottom" then newY = bottom
    end

    local dx = newX - oldX
    local dy = newY - oldY
    ap.xoff = (ap.xoff or 0) + dx
    ap.yoff = (ap.yoff or 0) + dy
    ap.frame_point = desiredFP
end

-- Re-applies the icon layout using the profile's layout direction.
-- Container size is based on iconLimit (reserved slot count) so the frame
-- occupies a stable footprint. Visible icons are positioned sequentially;
-- hidden icons are sized but not anchored.  Routed icons are skipped
-- (AdditionalFrameManager positions them via cross-parent SetPoint).
local applyLayout = function()
    if not trinketContainer then return end
    -- No combat guard: container and icons are unprotected frames. Anchoring.lua
    -- writes SetHeight(parentH) in percent-match mode; applyLayout must run in
    -- combat to restore the content-driven height, else the center-pivoted
    -- anchor drifts icons up by (parentH - contentH) / 2.

    local iconLimit = math.max(getEffectiveIconLimit() - getRoutedSlotCount(), 0)

    if iconLimit <= 0 then
        trinketContainer:SetSize(1, 1)
        local bgS = getSettings().background
        if bgS then private.Util.ApplyComponentBackground(trinketContainer, bgS) end
        return
    end

    local settings = getSettings()
    local iconSize = settings.icon_size
    local iconOffset = settings.icon_offset
    local isVertical = settings.layout == "vertical"

    -- Resolve icon height override (0 or nil = square).
    local hasIconHeight = settings.icon_height and settings.icon_height > 0
    local iconHeight = hasIconHeight and math.floor(settings.icon_height) or iconSize

    -- Compute container size from iconLimit (reserved slot count)
    local containerWidth, containerHeight
    if isVertical then
        containerWidth = iconSize
        containerHeight = iconLimit * iconHeight + (iconLimit - 1) * iconOffset
    else
        containerWidth = iconLimit * iconSize + (iconLimit - 1) * iconOffset
        containerHeight = iconHeight
    end

    trinketContainer:SetSize(containerWidth, containerHeight)

    -- Count visible, non-routed, non-excluded icons for alignment offset
    local visibleCount = 0
    for _, slotID in ipairs(TRINKET_SLOTS) do
        local icon = trinketIcons[slotID]
        if icon and not isSlotExcluded(slotID) and not isSlotRouted(slotID) and icon:IsShown() then
            visibleCount = visibleCount + 1
        end
    end

    -- Compute alignment offset
    local alignment = settings.layout_alignment or "center"
    local alignOffsetX, alignOffsetY = 0, 0

    if not isVertical then
        local usedWidth = visibleCount > 0 and (visibleCount * iconSize + (visibleCount - 1) * iconOffset) or 0
        if alignment == "center" then
            alignOffsetX = (containerWidth - usedWidth) / 2
        elseif alignment == "right" then
            alignOffsetX = containerWidth - usedWidth
        end
    else
        local usedHeight = visibleCount > 0 and (visibleCount * iconHeight + (visibleCount - 1) * iconOffset) or 0
        if alignment == "center" then
            alignOffsetY = (containerHeight - usedHeight) / 2
        elseif alignment == "bottom" then
            alignOffsetY = containerHeight - usedHeight
        end
    end

    -- Position visible, non-routed icons sequentially
    local visibleIndex = 0
    for _, slotID in ipairs(TRINKET_SLOTS) do
        local icon = trinketIcons[slotID]
        if icon then
            if isSlotRouted(slotID) then
                -- Routed: don't size or position here; the routing
                -- target (AF manager or CooldownTracker) owns both.
            else
                icon:SetSize(iconSize, iconHeight)
                icon:ClearAllPoints()
                if icon:IsShown() then
                    if isVertical then
                        private.Pixel.SetPoint(icon, "TOPLEFT", trinketContainer, "TOPLEFT", 0, -(alignOffsetY + visibleIndex * (iconHeight + iconOffset)))
                    else
                        private.Pixel.SetPoint(icon, "TOPLEFT", trinketContainer, "TOPLEFT", alignOffsetX + visibleIndex * (iconSize + iconOffset), 0)
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
    local bgS = getSettings().background
    if bgS then private.Util.ApplyComponentBackground(trinketContainer, bgS) end
end

trinketTracker.Initialize = function()
    -- Create the container frame (plain Frame positioned by the anchoring system)
    trinketContainer = CreateFrame("Frame", "CUE_TrinketTracker", UIParent)
    trinketContainer:SetSize(110, 50)

    -- Create one icon per trinket slot
    for i, slotID in ipairs(TRINKET_SLOTS) do
        trinketIcons[slotID] = createTrinketIcon(trinketContainer, slotID, i)
    end

    -- Register events
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", onEvent)
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")

    -- OnUpdate for cooldown sweep animation
    trinketContainer:SetScript("OnUpdate", onUpdate)

    -- No OnEnterCombat refresh: at PLAYER_REGEN_DISABLED the lockdown has not
    -- started, so it redrew the pre-combat state already on screen, in the pull
    -- frame.
    private.Callback.Register("OnLeaveCombat", function()
        for _, icon in pairs(trinketIcons) do
            resetIconState(icon)
        end
        trinketTracker.Refresh()
    end)

    trinketTracker.Refresh()
end

trinketTracker.GetFrame = function()
    return trinketContainer
end

---Stop all active glow effects on every trinket icon.
---Used by EditMode when the glow master toggle is disabled.
trinketTracker.StopAllGlows = function()
    for _, icon in pairs(trinketIcons) do
        resetIconState(icon)
    end
end

---A font edit made while hidden waits for the Refresh that shows the icons:
---the pass that reveals them carries no font pass.
local fontsOwed = false

trinketTracker.Refresh = function()
    if not trinketContainer then return end
    if private.fontsDirty then fontsOwed = true end

    -- Show/hide based on both our own enabled state and whether the anchor
    -- parent chain is valid. If our ancestor (e.g. CooldownTracker) is disabled,
    -- the anchoring system hides us; don't override that with Show().
    local shouldShow = (getEnabled() or private.isEditMode)
        and private.Anchor.IsVisibleForComponent(trinketTracker.name)
    if shouldShow then
        trinketContainer:SetAlpha(private.Anchor.GetEffectiveAlpha(trinketTracker.name))
        trinketContainer:Show()
        -- Apply font profiles only when settings may have changed
        if fontsOwed then
            fontsOwed = false
            local settings = getSettings()
            for _, icon in pairs(trinketIcons) do
                if settings.duration_font then
                    if icon.DurationText then
                        private.Util.ApplyFontProfile(icon.DurationText, settings.duration_font, icon)
                    end
                    if icon.BuffDurationText then
                        private.Util.ApplyFontProfile(icon.BuffDurationText, settings.duration_font, icon)
                    end
                end
                if settings.keybind_font and icon.KeybindText then
                    private.Util.ApplyFontProfile(icon.KeybindText, settings.keybind_font, icon)
                end
            end
        end
        refreshAllIcons()
    elseif hasRoutedIcons() then
        -- Disabled but has routed icons: keep container alive at alpha 0.
        -- Non-routed icons inherit alpha 0 (invisible); routed icons use
        -- SetIgnoreParentAlpha(true) set by the AF manager.
        trinketContainer:SetAlpha(0)
        trinketContainer:Show()
        refreshAllIcons()
    else
        trinketContainer:Hide()
    end

    -- Keybind text: Util's shared watcher invalidates the keybind cache and
    -- fires OnKeybindsChanged once per burst of binding / action-bar changes.
    if not keybindEventsRegistered then
        keybindEventsRegistered = true
        private.Callback.Register("OnKeybindsChanged", refreshAllIcons)
    end

    syncFramePointToAlignment()
    applyLayout()

    -- Notify AF manager that trinket icons may have changed
    if private.AdditionalFrameManager and private.AdditionalFrameManager.OnAddonIconRefresh then
        private.AdditionalFrameManager.OnAddonIconRefresh()
    end
end

trinketTracker.OnEnable = function()
    if trinketContainer then
        trinketContainer:SetAlpha(private.Anchor.GetEffectiveAlpha(trinketTracker.name))
        trinketContainer:Show()
        trinketTracker.Refresh()
    end
end

trinketTracker.OnDisable = function()
    if trinketContainer then
        if hasRoutedIcons() then
            trinketContainer:SetAlpha(0)
        else
            trinketContainer:Hide()
        end
    end
end

trinketTracker.GetComponentName = function()
    return trinketTracker.name
end

---Return the icon frame for a specific trinket slot.
---Used by AdditionalFrameManager to find routed trinket icons.
---@param slotID number  equipment slot ID (13 or 14)
---@return frame|nil
trinketTracker.GetIconFrame = function(slotID)
    return trinketIcons[slotID]
end

---TrinketTracker always uses its own computed content width (from icon_size and layout)
---rather than inheriting the anchor parent's width via dual anchors.
trinketTracker.GetWantsContentWidth = function()
    return true
end

---Returns true when enabled but has no active on-use trinkets to display.
---Used by the anchoring system to collapse the chain past this component.
trinketTracker.IsCollapsed = function()
    return getActiveTrinketCount() == 0
end

trinketTracker.GetComponentSize = function()
    local settings = getSettings()
    local iconLimit = math.max(getEffectiveIconLimit() - getRoutedSlotCount(), 0)

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

trinketTracker.ContentLayout = function()
    refreshAllIcons()
    applyLayout()
end

private.TrinketTracker = trinketTracker
private.ComponentManager.RegisterComponent("TrinketTracker", trinketTracker)
