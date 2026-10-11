
local _
---@type string, private
local _, private = ...

---@type detailsframework
local framework = _G["DetailsFramework"]

local LibSharedMedia = LibStub("LibSharedMedia-3.0")
local LAC = LibStub("LibAuraContainer-1.0")

---Spell ID of the Ebon Might buff as it appears on the evoker (self).
---Carries only percentage coefficients on aura.points, not the computed stat.
local EBON_MIGHT_SPELL_ID = 395296
---Spell ID of the Ebon Might buff as it appears on allies. Carries the computed
---main-stat grant in aura.points[1]; read to derive the stat value.
local EBON_MIGHT_ALLY_SPELL_ID = 395152
local EBON_MIGHT_COLOR = {0.847, 0.608, 0.220}

---The Duplicate window (Breath of Eons) as a real, readable buff on the Evoker.
---The CDM TrackedBuff entry (cooldownID 94196) resolves to base spell 1259174
---with linked aura 1259171 — 1259174 is the passive talent node (no aura icon),
---so only the linked id is filtered here. The window is read through the aura
---tap: the Ebon Might aura is secret in combat, so nothing CPU-side can
---observe the extensions that drive it.
local DUPLICATE_AURA_SPELL_IDS = { [1259171] = true }

---Double-Time talent (Chronowarden hero tree) — gates whether Ebon Might stat
---grants can crit at all. Without this talent the grant is deterministic and
---any apparent ratio spike is noise, not a crit. `IsPlayerSpell` returns true
---when the talent node is selected.
local DOUBLE_TIME_SPELL_ID = 431874

---12.1+: Ebon Might crits apply "Double-time" as a real, trackable buff on
---the Evoker (15s base, Mastery-scaled, extended instead of overwritten on
---re-crit) rather than silently boosting the stat grant. The CDM TrackedBuff
---entry (cooldownID 198923) resolves to base spell 431874 (the talent ID)
---with linked aura 460688; the tap slot filter includes both so whichever ID
---the applied aura carries matches.
local DOUBLE_TIME_BUFF_SPELL_IDS = { [DOUBLE_TIME_SPELL_ID] = true, [460688] = true }

---True on WoW Forever, which keeps vanilla's five-second rule: Spirit-based
---mana regen pauses for 5 s after mana is spent. No API names the rule, so the
---interface number is the only runtime signal (`ClientScope.CLIENT`).
local HAS_FIVE_SECOND_RULE = private.ClientScope.CLIENT == "forever"
local FIVE_SECOND_RULE_DURATION = 5
-- ponytail: sized by eye. Vanilla drew this 32px spark over a 13px cast bar, so
-- its bright core is about half the texture; a spark twice its band's length
-- puts the core across the band. Tune here if it reads too faint or too long in a client.
local FSR_SPARK_WIDTH = 15
---`five_second_rule_size` → the band the spark rides in, as { centre, length }
---fractions of the bar's cross axis, measured from its top (a vertical bar: its left).
local FSR_BANDS = {
    full = { 1 / 2, 1 },
    top = { 1 / 6, 1 / 3 },
    bottom = { 5 / 6, 1 / 3 },
}

---Cached spec index: survives transient nil returns from GetSpecialization()
---after loading screens. Updated on spec change and whenever the API returns
---a valid value.
local cachedSpecIndex = C_SpecializationInfo.GetSpecialization()

---True when the bar is displaying Ebon Might duration instead of normal power.
local ebonMightMode = false

---Cached bar color (GetStatusBarColor returns secrets in Midnight 12.0+).
---Updated by UpdatePowerColor and the Ebon Might color path.
---@type number[]
local cachedBarColor = {1, 1, 1, 1}

---Cached `IsPlayerSpell(DOUBLE_TIME_SPELL_ID)` result. Without Double-Time the
---Ebon Might stat grant is deterministic and there is no crit to show — the
---Options crit toggles soft-disable. Refreshed on talent/spec/loading-screen
---events.
local doubleTimeKnown = false


---@class private : table
---@field PrimaryResources primaryresources

---@class primaryresources : component
---@field CreatePrimaryResources fun() : df_powerbar Creates the power bar frame
---@field HasFiveSecondRule boolean True on a client with vanilla's five-second mana rule (WoW Forever)

---@type primaryresources
---@diagnostic disable-next-line: missing-fields
local primaryResources = {}

primaryResources.name = "PrimaryResources"
primaryResources.HasFiveSecondRule = HAS_FIVE_SECOND_RULE

---@return component_profile_main
local getSettings = function()
    return private.profile.components[primaryResources.name]
end

primaryResources.GetSettings = getSettings

---@return boolean
local function isAugmentationEvoker()
    local _, class = UnitClass("player")
    if class ~= "EVOKER" then return false end
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if specIndex then
        cachedSpecIndex = specIndex
    end
    return (specIndex or cachedSpecIndex) == 3
end

---Specs whose spec combat resource is relocated to the SecondaryResources bar;
---for these the primary bar shows mana instead of the Blizzard-reported power.
---Keyed by class token then specIndex. Mirrors SecondaryResources SRC.continuousBarPowers.
local primaryManaOverrideSpecs = {
    SHAMAN = { [1] = true }, -- Elemental (Maelstrom → secondary)
    DRUID = { [1] = true }, -- Balance (Astral Power → secondary)
    PRIEST = { [3] = true }, -- Shadow (Insanity → secondary)
}

---Player spec index, but only on a client with a real specialization system.
---
---Neither of the obvious tests works.  `GetSpecialization()` answers with an
---index everywhere — a client carrying one pseudo-spec per class still returns
---`1` — and `GetSpecializationInfo` resolves a genuine specID for it (Forever's
---Druid is `1484`, named "Druid", role `DAMAGER`, and `1484` is not in retail's
---`ChrSpecialization`, which ends at `1480`).  So a non-nil index and a non-nil
---specID both say yes on a client that has no specs at all.
---
---`GetNumSpecializations()` is the test, and it is Blizzard's own: `IsInitialSpec`
---is `specializationIndex > GetNumSpecializations()`
---(`Blizzard_SharedXML/UnitUtil.lua:9`), i.e. they treat the count as the class's
---authoritative spec list.  Retail classes report 3 or 4; a client with no spec
---system reports 1.
---
---Both spec-keyed reads below go through this, so where there is no spec system
---they fall through to the permissive branch instead of reading index 1 as the
---class's first retail spec — which auto-hid the mana bar for every caster on
---such a client, mana being the only resource they have.  Nothing here asks
---which client it is: a spec system appearing raises the count, and the existing
---per-spec behaviour applies unchanged with nothing to unwind.
---@return number? specIndex
local function getRealSpecIndex()
    -- ponytail: the count is the whole test, and the indexes below are retail's.
    -- If a client ever reports several specs on a numbering that is not retail's,
    -- those indexes stop meaning what they say and this has to resolve and
    -- compare specIDs instead (Balance 102, Guardian 104, Arcane 62,
    -- Protection 66, Elemental 262, Shadow 258 — from DB2 ChrSpecialization).
    if GetNumSpecializations() <= 1 then return nil end
    return C_SpecializationInfo.GetSpecialization()
end

---Effective primary power type for the player. For specs in primaryManaOverrideSpecs
---the spec resource lives in SecondaryResources, so the primary bar tracks mana; all
---other specs report the native UnitPowerType.
---@return integer powerType, string powerToken
local function getPlayerPrimaryPowerType()
    local _, class = UnitClass("player")
    local override = primaryManaOverrideSpecs[class]
    if override then
        local specIndex = getRealSpecIndex()
        if specIndex and override[specIndex] then
            return Enum.PowerType.Mana, "MANA"
        end
    end
    return UnitPowerType("player")
end

---@return boolean
local function shouldShowEbonMight()
    return private.profile.augmentation_ebon_might and isAugmentationEvoker()
end

---Returns false when settings.enabled is false, or when auto_hide is enabled and
---the player is a mana-using DPS or tank spec that does not benefit from a
---primary resource bar. Per-class overrides (arcane_mana_bar, paladin_mana_bar,
---augmentation_ebon_might, evoker_mana_bar, druid_mana_bar, shaman_mana_bar,
---balance_mana_bar, priest_mana_bar) let individual classes opt back in.
local getEnabled = function()
    local settings = getSettings()
    if not settings.enabled then return false end
    if private.profile.auto_hide then
        local _, powerToken = getPlayerPrimaryPowerType()
        if powerToken == "MANA" then
            local specIndex = getRealSpecIndex()
            if specIndex then
                local role = private.compat.GetSpecializationRole(specIndex)
                if role == "DAMAGER" then
                    local _, class = UnitClass("player")
                    -- Arcane mages rely on mana; let the dedicated setting override auto-hide.
                    if class == "MAGE" and specIndex == 1 and private.profile.arcane_mana_bar then
                        return true
                    end
                    -- Augmentation Evokers show Ebon Might duration instead of mana.
                    if shouldShowEbonMight() then
                        return true
                    end
                    -- Per-class overrides for DPS mana specs.
                    if class == "PALADIN" and private.profile.paladin_mana_bar then
                        return true
                    end
                    if class == "EVOKER" and private.profile.evoker_mana_bar then
                        return true
                    end
                    -- Elemental Shamans: Maelstrom lives in SecondaryResources; the
                    -- primary bar tracks mana, shown only when opted in.
                    if class == "SHAMAN" and private.profile.shaman_mana_bar then
                        return true
                    end
                    -- Balance Druids: Astral Power lives in SecondaryResources. Gate on
                    -- specIndex so the toggle never un-hides Feral's caster-form mana bar
                    -- (Feral is also a DAMAGER druid that reports mana out of Cat Form).
                    if class == "DRUID" and specIndex == 1 and private.profile.balance_mana_bar then
                        return true
                    end
                    -- Shadow Priests: Insanity lives in SecondaryResources.
                    if class == "PRIEST" and private.profile.priest_mana_bar then
                        return true
                    end
                    return false
                end
                if role == "TANK" then
                    local _, class = UnitClass("player")
                    -- Guardian Druids use Rage in Bear Form; mana in caster form is not useful.
                    if class == "DRUID" and specIndex == 3 then
                        return private.profile.druid_mana_bar
                    end
                    -- Protection Paladins use Holy Power; mana bar hidden unless overridden.
                    if class == "PALADIN" and specIndex == 2 then
                        return private.profile.paladin_mana_bar
                    end
                end
            end
        end
    end
    return true
end

primaryResources.GetEnabled = getEnabled

---Returns "always" when Ebon Might mode is active so the anchoring system shows
---the bar regardless of anchor chain visibility (viewer may have no active items).
---@return string?
primaryResources.GetVisibilityOverride = function()
    if shouldShowEbonMight() then
        if private.Anchor.IsMounted() then
            return nil
        end
        return "always"
    end
end

---Last getEnabled() result, written by Refresh.
---@type boolean?
local lastEnabled

---Event frame to re-evaluate auto-hide on spec change (e.g. Arcane mage ↔ Fire/Frost).
---Registered from Initialize and never unregistered: auto-hide is a GetEnabled()
---false, so FullLayoutRefresh calls OnDisable for it, and the spec change that
---should bring the bar back is exactly what this frame listens for.
local specEventFrame = CreateFrame("Frame")
specEventFrame:SetScript("OnEvent", function(_, event)
    cachedSpecIndex = C_SpecializationInfo.GetSpecialization() or cachedSpecIndex
    local wasEnabled = lastEnabled
    primaryResources.Refresh()
    -- A form shift only matters when it flips auto-hide (Feral/Guardian caster
    -- form); it fires on every shift, and each relayout is a full Anchor.Refresh.
    if event ~= "UPDATE_SHAPESHIFT_FORM" or lastEnabled ~= wasEnabled then
        private.Anchor.OnComponentStateChange()
    end
end)

---@type Frame?
local containerFrame

---@type df_powerbar?
local powerBar

---Event frame for Ebon Might aura tracking (UNIT_AURA on "player").
local ebonMightEventFrame = CreateFrame("Frame")

---Granted main-stat value carried in aura.points[1] (nil when unknown/no aura).
local ebonMightStatValue
---auraInstanceID of the currently tracked Ebon Might (lets us distinguish a fresh
---application from a duration extension — extensions retain the same instance ID).
local ebonMightAuraInstanceID
---Unit token of the current ally whose Ebon Might we poll as the stat reference
---(e.g. "party3"). Ebon Might scales dynamically with the caster's main stat, so
---we re-read this ally's aura every second to keep the displayed stat live.
---Re-scanned if the ally drops the buff, dies, or leaves group.
---@type string?
local ebonMightReferenceAlly
---C_Timer.NewTicker handle for the 1s dynamic-stat poller. Active only while
---Ebon Might mode is on; stopped in the mode-exit paths.
---@type TimerObject?
local ebonMightPollTicker

---Forward declaration: the extension cast handler, updateEbonMight, and the
---enter-mode path all call this.
local applyEbonMightBarColor

---Ebon Might aura tap state. ALL auras — self-cast buffs included — are fully
---secret in combat, so both the Ebon Might duration drive
---(GetPlayerAuraBySpellID) and any CPU-side crit derivation are blind exactly
---when they matter. Two slots on one container replace them: an "ebonmight"
---slot whose button binds a StatusBar (SetDurationBar → engine
---SetTimerDuration fill) and a remaining-time FontString (SetDurationText),
---and a "doubletime" slot carrying the crit glow + Double Time countdown.
---Each slot's button is engine-Shown while its aura is active and
---engine-Hidden when it drops (Blizzard_ManagedAuraContainer.lua:199/209),
---so everything renders with zero addon branching on secret state. All
---references live in this addon-owned table, never written onto the buttons.
---While auras are secret, the buttons and EVERY child (bound or not) are
---forbidden to addon code — all writes go through applyEbonMightTapSettings'
---single secrecy gate. See .context/patterns-secrets.md "Aura-tap".
local ebonMightTap = {
    container = nil,    ---@type Frame?  CUE_PR_EbonMightTap (addon-owned, never forbidden)
    button = nil,       ---@type Frame?  "doubletime" slot button (forbidden while auras are secret)
    glow = nil,         ---@type Frame?  pulsing BackdropTemplate border (crit signal)
    durationText = nil, ---@type FontString?  engine-bound Double Time remaining text
    emButton = nil,     ---@type Frame?  "ebonmight" slot button
    emBar = nil,        ---@type StatusBar?  engine-driven Ebon Might duration fill
    emText = nil,       ---@type FontString?  engine-bound Ebon Might remaining text
    dupButton = nil,    ---@type Frame?  "duplicate" slot button
    dupText = nil,      ---@type FontString?  engine-bound Duplicate remaining text
}

---Create (once) the tap container + aura slot. No-op pre-12.1, in combat
---(AuraContainer creation Lua-errors there by design), or when already
---created; called from every Refresh pass in Ebon Might mode so the first
---out-of-combat pass after a mid-combat login retries. initializeFrame runs
---under UntrustedLayoutScriptExecution: creation + font + bind ONLY — any
---SetPoint in that context errors (including SetBackdrop's edge textures), so
---decorations and anchors are applied later by applyEbonMightTapSettings.
local function ensureEbonMightTap()
    if ebonMightTap.container or not powerBar or InCombatLockdown() then
        return
    end
    local c = LAC:CreateContainer("CUE_PR_EbonMightTap", UIParent)
    c:SetUnit("player")
    c:SetSize(1, 1)
    c:SetPoint("CENTER")
    c:SetEnabled(true)
    c:Show()
    ebonMightTap.container = c
    c:AddAuraSlot("doubletime", "HELPFUL", {
        candidateFilters = { includeSpellIDs = DOUBLE_TIME_BUFF_SPELL_IDS },
        initializeFrame = function(button)
            ebonMightTap.button = button
            -- Font must be set BEFORE the bind — SetDurationText pushes text
            -- immediately and SetText on a font-less FontString errors.
            local fs = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            button:SetDurationText(fs)
            ebonMightTap.durationText = fs
            private.printdebug("EbonMightTap: doubletime slot bound")
        end,
    })
    -- Ebon Might duration slot: engine drives the bound StatusBar via
    -- SetTimerDuration and the bound FontString via the DurationText binding
    -- on every aura update (Blizzard_CustomAuraButton.lua ApplyDurationBar /
    -- ApplyDurationText) — fully engine-side, works while secret.
    local emButton = c:AddAuraSlot("ebonmight", "HELPFUL", {
        candidateFilters = { includeSpellIDs = { [EBON_MIGHT_SPELL_ID] = true } },
        initializeFrame = function(button)
            -- PRE-BIND: creation + styling only, NO anchors in this context.
            local bar = CreateFrame("StatusBar", "CUE_PR_EbonMightTapBar", button)
            bar:SetStatusBarColor(EBON_MIGHT_COLOR[1], EBON_MIGHT_COLOR[2], EBON_MIGHT_COLOR[3])
            button:SetDurationBar(bar, { direction = Enum.StatusBarTimerDirection.RemainingTime })
            ebonMightTap.emBar = bar
            -- Remaining-time text lives ON the bar frame so it draws above
            -- the fill (a child frame renders above its parent's regions).
            local fs = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            button:SetDurationText(fs)
            ebonMightTap.emText = fs
            private.printdebug("EbonMightTap: ebonmight slot bound")
        end,
    })
    ebonMightTap.emButton = emButton
    -- Duplicate window: engine-bound remaining time, the only source that
    -- tracks its extensions correctly. The engine Shows the button exactly
    -- while the buff is up, so nothing needs clearing when it drops.
    -- Ceiling: ONE slot, so a second concurrent Duplicate would not render —
    -- not currently reachable, but gear is expected to bring it back. The
    -- upgrade is `AddAuraGroup("duplicate", ...)` with `maxFrameCount = 2`
    -- (Blizzard flow layout, one button per instance) in place of this slot.
    local dupButton = c:AddAuraSlot("duplicate", "HELPFUL", {
        candidateFilters = { includeSpellIDs = DUPLICATE_AURA_SPELL_IDS },
        initializeFrame = function(button)
            local fs = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            button:SetDurationText(fs)
            ebonMightTap.dupText = fs
            private.printdebug("EbonMightTap: duplicate slot bound")
        end,
    })
    ebonMightTap.dupButton = dupButton
end

---Apply anchors, colors, and profile toggles to the tap decorations.
---Anchoring model: ONE cross-frame edge — the button anchored onto the plain
---powerBar frame (the allowed dependent→plain direction, and a live anchor,
---so bar moves/resizes track automatically) — with every decoration anchored
---in-family on the button, mirroring SecondaryResources' bar-slot model.
---The secrecy gate at the top is load-bearing: every write below it touches
---the button or its children and would Lua-error while auras are secret.
---Skipped passes are retried by the next out-of-combat Refresh.
local function applyEbonMightTapSettings()
    local button = ebonMightTap.button
    if not button or not powerBar then return end
    if C_Secrets.ShouldAurasBeSecret() then return end
    -- Layer the tap WITH the bar rather than above the whole UI.  The container
    -- is UIParent-rooted, so it takes the bar's strata and a level relative to
    -- the bar: container +2 -> slot buttons +3 -> the bound StatusBar +4, one
    -- under ApplyBarBorder's overlay at +5, which carries percentText.  Slot
    -- buttons are plain children of the container
    -- (Blizzard_AuraContainerFrameProviders.lua:76) and nothing in
    -- Blizzard_AuraContainer sets a level or strata, so they follow.
    --
    -- This replaced a fixed HIGH container plus a DIALOG overlay lift, which
    -- drew the fill through Blizzard's Settings panel (HIGH) and the border
    -- through CUE's options and Edit Mode (both DIALOG).
    local c = ebonMightTap.container
    c:SetFrameStrata(powerBar:GetFrameStrata())
    c:SetFrameLevel(powerBar:GetFrameLevel() + 2)
    if not ebonMightTap.glow then
        -- Lazy decoration creation: first non-secret pass after slot creation.
        -- No fill/tint overlay: any region spanning the bar rect sits ABOVE
        -- the bar's fill and text (the tap renders at the container's strata)
        -- and masks the Ebon Might duration readout — the border glow +
        -- duration text alone carry the crit signal.
        local glow = CreateFrame("Frame", "CUE_PR_DoubleTimeGlow", button, "BackdropTemplate")
        glow:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
        glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
        glow:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 2,
        })
        local ag = glow:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        ag:SetToFinalAlpha(true)
        local fade = ag:CreateAnimation("Alpha")
        fade:SetDuration(0.7)
        fade:SetFromAlpha(0.4)
        fade:SetToAlpha(1.0)
        fade:SetSmoothing("IN_OUT")
        fade:SetOrder(1)
        -- Play permanently: the animation only renders while the engine shows
        -- the button, so no addon-side start/stop is needed (or possible —
        -- the frame is forbidden in combat).
        ag:Play()
        ebonMightTap.glow = glow
    end
    button:ClearAllPoints()
    button:SetAllPoints(powerBar)
    local isVertical = (getSettings().orientation or "horizontal") == "vertical"
    local fs = ebonMightTap.durationText
    if fs then
        fs:ClearAllPoints()
        -- Below-right, outside the bar: every in-bar text slot is taken (EM
        -- remaining at the left inset, Duplicate remaining at the center,
        -- percentText's stat readout at the right inset).
        if isVertical then
            fs:SetPoint("BOTTOM", button, "TOP", 0, 20)
        else
            fs:SetPoint("TOPLEFT", button, "BOTTOMRIGHT", 4, -2)
        end
        fs:SetShown(private.profile.augmentation_ebon_might_double_time_text and true or false)
    end
    local critColor = private.profile.augmentation_ebon_might_crit_color_value
    ebonMightTap.glow:SetBackdropBorderColor(critColor[1], critColor[2], critColor[3], critColor[4] or 1)
    ebonMightTap.glow:SetShown(private.profile.augmentation_ebon_might_crit_glow and true or false)
    -- Ebon Might slot geometry + style (same anchoring model: button spans
    -- the powerBar, bar and text in-family).
    local emButton = ebonMightTap.emButton
    if emButton then
        emButton:ClearAllPoints()
        emButton:SetAllPoints(powerBar)
        local emBar = ebonMightTap.emBar
        if emBar then
            emBar:SetAllPoints(emButton)
            local lsmPath = LibSharedMedia:Fetch("statusbar", getSettings().texture, true)
            emBar:SetStatusBarTexture(lsmPath or "Interface\\Buttons\\WHITE8x8")
            emBar:SetStatusBarColor(EBON_MIGHT_COLOR[1], EBON_MIGHT_COLOR[2], EBON_MIGHT_COLOR[3])
        end
        local emText = ebonMightTap.emText
        if emText then
            emText:ClearAllPoints()
            -- Left inset (bottom for vertical): the bar center belongs to the
            -- engine-bound Duplicate remaining time.
            if isVertical then
                emText:SetPoint("BOTTOM", emButton, "BOTTOM", 0, 4)
            else
                emText:SetPoint("LEFT", emButton, "LEFT", 4, 0)
            end
        end
    end
    -- Duplicate slot: same anchoring model, text centered ON the bar — the
    -- readout the player actually watches, in the spot the pre-tap composed
    -- string used. The stat readout (percentText) yields the centre to it and
    -- takes the inset opposite the Ebon Might remaining time.
    local dupButton = ebonMightTap.dupButton
    if dupButton then
        dupButton:ClearAllPoints()
        dupButton:SetAllPoints(powerBar)
        local dupText = ebonMightTap.dupText
        if dupText then
            dupText:ClearAllPoints()
            dupText:SetPoint("CENTER", dupButton, "CENTER", 0, 0)
            dupText:SetShown(private.profile.augmentation_ebon_might_show_duplicates and true or false)
        end
    end
end

---Write the Ebon Might main-bar color plus the cachedBarColor mirror. Called
---from the enter-mode path, the aura-removed branch of updateEbonMight, and
---the tail of updateEbonMight.
applyEbonMightBarColor = function()
    if not powerBar then return end
    local color = EBON_MIGHT_COLOR
    powerBar:SetStatusBarColor(color[1], color[2], color[3])
    cachedBarColor[1], cachedBarColor[2], cachedBarColor[3], cachedBarColor[4] = color[1], color[2], color[3], 1
    if powerBar.background then
        local bgColor = getSettings().background_color
        if bgColor then
            powerBar.background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
        end
    end
end

---Forward declaration so resetEbonMightTracking can call it.
local stopEbonMightPollTicker

---Reset all Ebon Might tracking state (called from mode-exit / disable paths).
local function resetEbonMightTracking()
    ebonMightStatValue = nil
    ebonMightAuraInstanceID = nil
    ebonMightReferenceAlly = nil
    if stopEbonMightPollTicker then stopEbonMightPollTicker() end
    -- The tap container is addon-owned (only the slot BUTTON is forbidden
    -- while auras are secret), so hiding it here is safe in any state.
    if ebonMightTap.container then
        ebonMightTap.container:Hide()
    end
end

---Refresh the cached Double-Time talent state (gates the Options crit toggles).
local function refreshDoubleTimeKnown()
    doubleTimeKnown = IsPlayerSpell(DOUBLE_TIME_SPELL_ID) and true or false
end

---Return points[2] of OUR Ebon Might on `unit` (nil if not present or from another
---caster). Fast path: `C_UnitAuras.GetUnitAuraBySpellID` returns one aura per
---spellID; if it's ours we're done. Only when that fast-path aura exists but
---belongs to another Aug do we pay the full `AuraUtil.ForEachAura` iteration to
---find our instance alongside it.
---@param unit string
---@return number?
local function findOurEbonMightOn(unit)
    local aura = C_UnitAuras.GetUnitAuraBySpellID(unit, EBON_MIGHT_ALLY_SPELL_ID)
    if not aura then return nil end
    if aura.sourceUnit and UnitIsUnit(aura.sourceUnit, "player") then
        -- points[1] is a static nominal coefficient (always ~8),
        -- points[2] is the live dynamic stat value (caster_int × effective %).
        local points = aura.points and aura.points[2]
        if points and points > 0 then return points end
        return nil
    end
    -- Fast-path aura exists but isn't ours — multi-Aug situation. Iterate.
    -- 12.1: slot-based iteration (ForEachAura) Lua-errors while auras are
    -- secret — skip it; the fast path above already covered the common case,
    -- and multi-Aug resolution degrades to nil until access returns.
    if private.Util.IsAuraAccessBlocked() then return nil end
    local foundPoints
    AuraUtil.ForEachAura(unit, "HELPFUL", nil, function(a)
        if a.spellId == EBON_MIGHT_ALLY_SPELL_ID
           and a.sourceUnit and UnitIsUnit(a.sourceUnit, "player") then
            local points = a.points and a.points[2]
            if points and points > 0 then
                foundPoints = points
                return true -- stop iterating
            end
        end
        return false
    end, true)
    return foundPoints
end

---Read the granted main-stat value from a specific ally's Ebon Might aura.
---Returns nil if the ally doesn't exist, is the player, or doesn't have the
---buff from us. Used by the poller to quickly refresh the cached reference ally
---without a full group scan.
---@param unit string? unit token (e.g. "party3")
---@return number?
local function readAllyEbonMightStat(unit)
    if not unit or not UnitExists(unit) or UnitIsUnit(unit, "player") then return nil end
    return findOurEbonMightOn(unit)
end

---Find the first group/raid ally carrying our Ebon Might. Returns (points, unit)
---or (nil, nil). The self-aura only carries percentages; the computed stat grant
---only materializes on ally auras, so ally scan is the only way to derive the
---stat value and detect crit.
---@return number?, string?
local function scanAllyEbonMightStat()
    local prefix, count
    if IsInRaid() then
        prefix, count = "raid", GetNumGroupMembers()
    elseif IsInGroup() then
        prefix, count = "party", GetNumSubgroupMembers()
    else
        return nil, nil
    end
    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local points = findOurEbonMightOn(unit)
            if points then return points, unit end
        end
    end
    return nil, nil
end

---Store a scanned ally stat value for the bar text.
---@param points number?
local function applyEbonMightStatValue(points)
    -- Secret points would poison ebonMightStatValue (read for bar text).
    if points and issecretvalue(points) then return end
    ebonMightStatValue = points
end

---Cast-time scan: triggered 0.1s after a cast event (UNIT_SPELLCAST_SUCCEEDED
---or new self-aura auraInstanceID). Caches the matched ally as the poll
---reference.
local function evaluateEbonMightFromAlly()
    local points, unit = scanAllyEbonMightStat()
    ebonMightReferenceAlly = unit
    applyEbonMightStatValue(points)
end

---1s poller tick. Re-reads the cached reference ally (cheap) to catch dynamic
---stat updates from int procs / gear swaps. Falls back to a full group scan
---if the reference drops the buff, dies, or leaves the group. Skips work
---entirely when we don't currently have the self Ebon Might buff, so a
---stale ticker never picks up another Aug's Ebon Might on nearby allies.
local function pollEbonMightReference()
    if not C_UnitAuras.GetPlayerAuraBySpellID(EBON_MIGHT_SPELL_ID) then return end
    local points = readAllyEbonMightStat(ebonMightReferenceAlly)
    if not points then
        local unit
        points, unit = scanAllyEbonMightStat()
        ebonMightReferenceAlly = unit
    end
    applyEbonMightStatValue(points)
end

---Stop the live-update poller. Safe to call when it isn't running.
stopEbonMightPollTicker = function()
    if ebonMightPollTicker then
        ebonMightPollTicker:Cancel()
        ebonMightPollTicker = nil
    end
end

---Reconcile the 1s poller with the current profile flag. Call from Ebon Might
---mode entry AND every Refresh pass in that mode, so toggling the setting at
---runtime takes effect without leaving mode first.
local function syncEbonMightPollTicker()
    if private.profile.augmentation_ebon_might_live_update then
        if not ebonMightPollTicker then
            ebonMightPollTicker = C_Timer.NewTicker(1, pollEbonMightReference)
        end
    else
        stopEbonMightPollTicker()
    end
end

---Updates the bar from the current Ebon Might aura state.
local function updateEbonMight()
    if not powerBar then return end
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(EBON_MIGHT_SPELL_ID)
    if aura then
        local sameInstance = aura.auraInstanceID == ebonMightAuraInstanceID

        -- The fill is engine-bound (ebonMightTap.emBar) — the aura is only
        -- readable here out of combat, so driving the powerBar too would just
        -- double-draw underneath the tap bar.

        -- New aura instance = fresh Ebon Might cast. Schedule an ally scan after a
        -- brief delay so the ally aura has time to propagate; the self-aura only
        -- carries percentages (e.g. points[1]=20 for the +20% damage buff), so the
        -- actual stat grant must come from an ally's aura.
        if not sameInstance then
            ebonMightAuraInstanceID = aura.auraInstanceID
            C_Timer.After(0.1, evaluateEbonMightFromAlly)
        end
    else
        ebonMightStatValue = nil
        ebonMightAuraInstanceID = nil
        powerBar:SetMinMaxValues(0, 1)
        powerBar:SetValue(0)
    end
    -- Repaint the main bar — the aura-removed branch needs this to reset the
    -- base color cleanly.
    applyEbonMightBarColor()
end

---OnUpdate for the power bar in Ebon Might mode — updates remaining-time value and text.
local function onUpdateEbonMight(self)
    -- Fill + remaining time are engine-bound to the "ebonmight" aura slot
    -- (all auras, self-cast included, are fully secret in combat, so no
    -- CPU-side clock can read the real remaining duration).
    -- The Duplicate remaining time is engine-bound to the "duplicate" slot for
    -- the same reason; only the out-of-combat-resolvable stat value remains
    -- addon-composed here.
    local text
    if private.profile.augmentation_ebon_might_show_stat and ebonMightStatValue then
        text = "+" .. AbbreviateLargeNumbers(ebonMightStatValue)
    end
    self.percentText:SetText(text or "")
end

ebonMightEventFrame:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "UNIT_AURA" and unit == "player" then
        updateEbonMight()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" then
        if spellID == EBON_MIGHT_SPELL_ID or spellID == EBON_MIGHT_ALLY_SPELL_ID then
            -- UNIT_SPELLCAST_SUCCEEDED carries the castable spell ID, which for
            -- Ebon Might is the same ID that lands on allies (395152) rather
            -- than the self-aura ID (395296). Match either so refresh-in-place
            -- casts (which don't generate a new self-aura auraInstanceID) still
            -- trigger a scan.
            C_Timer.After(0.1, evaluateEbonMightFromAlly)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Re-register unit event (can silently drop across loading screens)
        ebonMightEventFrame:RegisterUnitEvent("UNIT_AURA", "player")
        ebonMightEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        refreshDoubleTimeKnown()
        updateEbonMight()
    elseif event == "PLAYER_TALENT_UPDATE"
        or event == "TRAIT_CONFIG_UPDATED"
        or event == "PLAYER_SPECIALIZATION_CHANGED" then
        refreshDoubleTimeKnown()
    end
end)

---Breakpoint pip host for the shared renderer (private.BreakpointPips).
---Created once and mutated in place; bar/key are refreshed by Refresh()
---before each Apply. baseColor references cachedBarColor directly — a stable
---table mutated by the color-application paths, so the fill-curve base is
---always current at Apply time.
---@type BreakpointPipHost
local pipHost = {
    bar = nil,
    key = nil,
    unit = "player",
    getPowerType = function() return powerBar and powerBar.powerType end,
    isVertical = function() return (getSettings().orientation or "horizontal") == "vertical" end,
    baseColor = cachedBarColor,
}

---Spend prediction overlay state.
---@type StatusBar?
local spendPredictionBar
---Stored secret cost from GetSpellPowerCost (or nil when no prediction active).
local spendPredictionCost
---@type Frame?
local spendPredictionEventFrame
local updateSpendPredictionOverlay
local registerSpendPredictionEvents
local unregisterSpendPredictionEvents

---Overrides the DF UpdatePower to apply the user's chosen text_format directly,
---avoiding the double text-set from a post-hook.
---Uses text_format_mana for mana, text_format_other for energy/rage/etc.
local function UpdatePower(self)
    self.currentPower = UnitPower(self.displayedUnit, self.powerType)
    self.currentPowerMissing = UnitPowerMissing(self.displayedUnit, self.powerType)
    self.currentPowerPercent = UnitPowerPercent(self.displayedUnit, self.powerType, false, CurveConstants.ScaleTo100)
    local interpolation = getSettings().bar_smoothing and Enum.StatusBarInterpolation.ExponentialEaseOut or Enum.StatusBarInterpolation.Immediate
    self:SetValue(self.currentPower, interpolation)
    private.BreakpointPips.UpdateDynamic(pipHost)
    updateSpendPredictionOverlay()

    if not self.Settings.ShowPercentText then return end

    local settings = getSettings()
    local isMana = self.powerType == Enum.PowerType.Mana
    local fmt = isMana and (settings.text_format_mana or "percent") or (settings.text_format_other or "current")

    local pct = self.currentPowerPercent or 0
    local cur = self.currentPower or 0

    if fmt == "none" then
        self.percentText:SetText("")
    elseif fmt == "current" then
        self.percentText:SetText(AbbreviateLargeNumbers(cur))
    elseif fmt == "both" then
        self.percentText:SetText(AbbreviateLargeNumbers(cur) .. " - " .. format("%.0f%%", pct))
    else
        self.percentText:SetText(format("%.0f%%", pct))
    end
end

---Applies the current text format to the power bar (for use outside UpdatePower, e.g. on Refresh).
local function updatePowerText()
    if not powerBar or not powerBar.percentText then return end
    UpdatePower(powerBar)
end

---Applies the profile texture to the power bar via LSM lookup.
---If not found or empty, falls back to a solid white fill via barTexture:SetColorTexture(1,1,1,1).
---@param bar df_powerbar
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

-- ── Spend Prediction ──────────────────────────────────────────────────────

---Updates the spend prediction overlay position and visibility.
---Called from UpdatePower (keeps MinMax in sync with mana regen) and on cast events.
updateSpendPredictionOverlay = function()
    if not spendPredictionCost or not spendPredictionBar then
        if spendPredictionBar then spendPredictionBar:Hide() end
        return
    end
    -- currentPower is secret; guard nil only (truthiness test, no comparison).
    -- When power is 0, barTexture has zero width so the overlay is naturally invisible.
    local currentPower = powerBar.currentPower
    if not currentPower then
        spendPredictionBar:Hide()
        return
    end
    local settings = getSettings()
    local c = settings.spend_prediction_color
    local lsmPath = settings.texture and settings.texture ~= "" and LibSharedMedia:Fetch("statusbar", settings.texture, true)
    if lsmPath then
        spendPredictionBar.barTexture:SetTexture(lsmPath)
    else
        spendPredictionBar.barTexture:SetColorTexture(1, 1, 1, 1)
    end
    spendPredictionBar.barTexture:SetVertexColor(c[1], c[2], c[3], c[4])
    -- Both currentPower and spendPredictionCost may be secret; SetMinMaxValues
    -- and SetValue are AllowedWhenTainted — the engine computes fill internally.
    spendPredictionBar:SetMinMaxValues(0, currentPower)
    spendPredictionBar:SetValue(spendPredictionCost)
    spendPredictionBar:Show()
end

---Registers spellcast events for mana spend prediction.
---Creates the event frame on first call; subsequent calls just re-register events.
registerSpendPredictionEvents = function()
    if not spendPredictionEventFrame then
        spendPredictionEventFrame = CreateFrame("Frame")
        spendPredictionEventFrame:SetScript("OnEvent", function(_, event, _, _, spellID)
            if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
                local costTable = C_Spell.GetSpellPowerCost(spellID)
                if costTable then
                    for _, entry in ipairs(costTable) do
                        if entry.type == powerBar.powerType then
                            spendPredictionCost = entry.cost
                            updateSpendPredictionOverlay()
                            return
                        end
                    end
                end
                -- Spell has no matching power cost; clear stale prediction
                spendPredictionCost = nil
                updateSpendPredictionOverlay()
            else
                -- STOP / SUCCEEDED / FAILED / INTERRUPTED
                spendPredictionCost = nil
                updateSpendPredictionOverlay()
            end
        end)
    end
    spendPredictionEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    spendPredictionEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    spendPredictionEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    spendPredictionEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    spendPredictionEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    spendPredictionEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
end

---Unregisters spend prediction events and hides the overlay.
unregisterSpendPredictionEvents = function()
    if spendPredictionEventFrame then
        spendPredictionEventFrame:UnregisterAllEvents()
    end
    spendPredictionCost = nil
    if spendPredictionBar then spendPredictionBar:Hide() end
end

-- ── Five-Second Rule (WoW Forever) ───────────────────────────────────────

---Spark frame: shown for 5 s after each mana-spending cast, its OnUpdate walks
---the spark along its band of the bar. It also carries the
---UNIT_SPELLCAST_SUCCEEDED registration, which fires while it is hidden.
---@type Frame?
local fsrFrame
---@type Texture?
local fsrSpark
local fsrStart = 0
local fsrVertical = false
local fsrBandCentre = FSR_BANDS.full[1]

---Left to right along the band; a vertical bar runs bottom to top with the band
---measured from its left, which is the top under its +90° text rotation.
local function onUpdateFiveSecondRule(self)
    local progress = (GetTime() - fsrStart) / FIVE_SECOND_RULE_DURATION
    if progress >= 1 then
        self:Hide()
        return
    end
    if fsrVertical then
        fsrSpark:SetPoint("CENTER", powerBar, "BOTTOMLEFT", powerBar:GetWidth() * fsrBandCentre, powerBar:GetHeight() * progress)
    else
        fsrSpark:SetPoint("CENTER", powerBar, "TOPLEFT", powerBar:GetWidth() * progress, -powerBar:GetHeight() * fsrBandCentre)
    end
end

---Restart on a cast that spends mana. Wand Shoot and Auto Shot fire this event
---on every shot without spending any, and must not hold the rule open.
local function onFiveSecondRuleCast(self, _, _, _, spellID)
    local costTable = C_Spell.GetSpellPowerCost(spellID)
    if not costTable then return end
    for _, entry in ipairs(costTable) do
        if entry.type == Enum.PowerType.Mana then
            fsrStart = GetTime()
            self:Show()
            return
        end
    end
end

local function stopFiveSecondRule()
    if not fsrFrame then return end
    fsrFrame:UnregisterAllEvents()
    fsrFrame:Hide()
end

local ALTERNATE_POWER_INDEX = Enum.PowerType.Alternate

---Overrides the DF UpdatePowerColor to support custom per-power-type colors.
---When override_colors is enabled, applies the user's custom color for the current
---power token and returns early. Otherwise falls through to the original DF logic.
local function UpdatePowerColor(self)
    local colors = private.profile.primary_resource_colors
    if colors.override_colors then
        local _, powerToken = getPlayerPrimaryPowerType()
        if powerToken then
            local c = colors.power_colors[powerToken]
            if c then
                self:SetStatusBarColor(c[1], c[2], c[3])
                cachedBarColor[1], cachedBarColor[2], cachedBarColor[3], cachedBarColor[4] = c[1], c[2], c[3], 1
                return
            end
        end
    end

    -- Original DF UpdatePowerColor logic
    if not UnitIsConnected(self.unit) then
        self:SetStatusBarColor(.5, .5, .5)
        cachedBarColor[1], cachedBarColor[2], cachedBarColor[3], cachedBarColor[4] = .5, .5, .5, 1
        return
    end

    if self.powerType == ALTERNATE_POWER_INDEX then
        self:SetStatusBarColor(0.7, 0.7, 0.6)
        cachedBarColor[1], cachedBarColor[2], cachedBarColor[3], cachedBarColor[4] = 0.7, 0.7, 0.6, 1
        return
    end

    local powerColor = PowerBarColor[self.powerType]
    if powerColor then
        self:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b)
        cachedBarColor[1], cachedBarColor[2], cachedBarColor[3], cachedBarColor[4] = powerColor.r, powerColor.g, powerColor.b, 1
        return
    end

    local _, _, r, g, b = UnitPowerType(self.displayedUnit)
    if r then
        self:SetStatusBarColor(r, g, b)
        cachedBarColor[1], cachedBarColor[2], cachedBarColor[3], cachedBarColor[4] = r, g, b, 1
        return
    end

    powerColor = PowerBarColor["ENERGY"]
    self:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b)
    cachedBarColor[1], cachedBarColor[2], cachedBarColor[3], cachedBarColor[4] = powerColor.r, powerColor.g, powerColor.b, 1
end

---Creates the player primary resource power bar
---@return df_powerbar
primaryResources.CreatePrimaryResources = function()
    if powerBar then
        error("CreatePrimaryResources() Power bar already exists.")
    end

    local name = "CUE_PrimaryResources"
    containerFrame = CreateFrame("Frame", name .. "_Container", UIParent)
    powerBar = framework:CreatePowerBar(containerFrame, name)
    powerBar:SetPoint("TOPLEFT", containerFrame, "TOPLEFT", 0, 0)
    powerBar:SetPoint("BOTTOMRIGHT", containerFrame, "BOTTOMRIGHT", 0, 0)
    -- Force mana as the primary power type for specs whose combat resource is
    -- relocated to SecondaryResources (Elemental/Balance/Shadow). DF's UpdatePowerInfo
    -- re-derives powerType from UnitPowerType on every UpdatePowerBar; re-apply the
    -- override after it so it survives UNIT_DISPLAYPOWER / SetUnit / PLAYER_ENTERING_WORLD.
    -- The alternate-power case (raid power bar) is left untouched.
    local dfUpdatePowerInfo = powerBar.UpdatePowerInfo
    powerBar.UpdatePowerInfo = function(self)
        dfUpdatePowerInfo(self)
        if self.powerType ~= ALTERNATE_POWER_INDEX then
            self.powerType = getPlayerPrimaryPowerType()
        end
    end
    powerBar.UpdatePower = UpdatePower
    powerBar.UpdatePowerColor = UpdatePowerColor
    -- Override DF's UpdateMaxPower: strip the Hide/Show/SetAlpha logic.
    -- DF hides powerBar when UnitPowerMax transiently returns 0 during zone
    -- transitions (PLAYER_ENTERING_WORLD), and SetAlpha clobbers fade alpha.
    -- We manage powerBar visibility and alpha through shouldBeActive in Refresh().
    powerBar.UpdateMaxPower = function(self)
        self.currentPowerMax = UnitPowerMax(self.displayedUnit, self.powerType)
        self:SetMinMaxValues(self.minPower or 0, math.max(self.currentPowerMax, 1))
    end

    -- Spend prediction overlay: reverse-fill bar showing the cost region at the fill edge
    spendPredictionBar = CreateFrame("StatusBar", nil, powerBar)
    spendPredictionBar.barTexture = spendPredictionBar:CreateTexture(nil, "ARTWORK", nil, 2)
    spendPredictionBar:SetStatusBarTexture(spendPredictionBar.barTexture)
    spendPredictionBar:SetReverseFill(true)
    spendPredictionBar:SetPoint("TOPLEFT", powerBar.barTexture, "TOPLEFT")
    spendPredictionBar:SetPoint("BOTTOMRIGHT", powerBar.barTexture, "BOTTOMRIGHT")
    spendPredictionBar:Hide()

    fsrFrame = CreateFrame("Frame", nil, powerBar)
    fsrFrame:SetAllPoints()
    fsrFrame:Hide()
    fsrSpark = fsrFrame:CreateTexture(nil, "OVERLAY")
    fsrSpark:SetTexture([[Interface\CastingBar\UI-CastingBar-Spark]])
    fsrSpark:SetBlendMode("ADD")
    fsrFrame:SetScript("OnUpdate", onUpdateFiveSecondRule)
    fsrFrame:SetScript("OnEvent", onFiveSecondRuleCast)

    return powerBar
end

---called from the Init.lua file to initialize the component on PLAYER_LOGIN event
primaryResources.Initialize = function()
    -- Always call Refresh so the power bar frame is created and available for Edit Mode,
    -- even when the component is class/spec-constrained to be disabled.
    -- Refresh() handles the disabled case by calling SetUnit(nil) which hides the bar.
    -- Spec events register here, not in OnEnable: the login path never calls OnEnable.
    specEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    specEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    specEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    primaryResources.Refresh()
end

primaryResources.GetFrame = function()
    return containerFrame
end

primaryResources.Refresh = function()
    local settings = getSettings()

    if not powerBar then
        primaryResources.CreatePrimaryResources()
    end

    local shouldBeActive = getEnabled()
    lastEnabled = shouldBeActive

    if shouldBeActive or (private.isEditMode and not (private.editModeHidden and private.editModeHidden[primaryResources.name])) then
        local isVertical = (settings.orientation or "horizontal") == "vertical"
        if isVertical then
            containerFrame:SetSize(settings.height, settings.width)
        else
            containerFrame:SetSize(settings.width, settings.height)
        end
        powerBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
        applyTexture(powerBar, settings.texture)

        local bgColor = settings.background_color
        if bgColor and powerBar.background then
            powerBar.background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
        end

        local overlayFrame = private.Util.ApplyBarBorder(powerBar)

        local valueFont = settings.value_font
        if valueFont and powerBar.percentText then
            powerBar.percentText:SetParent(overlayFrame)
            powerBar.percentText:SetDrawLayer("OVERLAY", 7)
            if private.fontsDirty then
                private.Util.ApplyFontProfile(powerBar.percentText, valueFont, powerBar)
                if isVertical then
                    private.Util.ApplyVerticalFontRotation(powerBar.percentText)
                else
                    powerBar.percentText:SetRotation(0)
                end
            end
        end

        if shouldShowEbonMight() and not private.isEditMode then
            -- Ebon Might mode: stop power tracking, drive bar from aura duration.
            -- SetUnit(nil) internally hides the bar (DF behavior); re-show afterward.
            powerBar:SetUnit(nil)
            powerBar:Show()
            applyEbonMightBarColor()
            ebonMightEventFrame:RegisterUnitEvent("UNIT_AURA", "player")
            ebonMightEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            ebonMightEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
            ebonMightEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
            ebonMightEventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
            ebonMightEventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
            refreshDoubleTimeKnown()
            powerBar:SetScript("OnUpdate", onUpdateEbonMight)
            ebonMightMode = true
            unregisterSpendPredictionEvents()
            syncEbonMightPollTicker()
            do
                ensureEbonMightTap()
                if ebonMightTap.container and not ebonMightTap.container:IsShown() then
                    ebonMightTap.container:Show()
                end
                applyEbonMightTapSettings()
                -- percentText carries only the stat readout on 12.1, and the
                -- bar centre belongs to the engine-bound Duplicate timer — so
                -- it takes the inset opposite the Ebon Might remaining time.
                -- It stays above the engine-bound fill by frame level alone —
                -- applyEbonMightTapSettings layers the tap under the border
                -- overlay that parents it.
                -- Restored to the value_font profile anchor on mode exit.
                local pt = powerBar.percentText
                if pt then
                    pt:ClearAllPoints()
                    if (getSettings().orientation or "horizontal") == "vertical" then
                        pt:SetPoint("TOP", powerBar, "TOP", 0, -4)
                    else
                        pt:SetPoint("RIGHT", powerBar, "RIGHT", -4, 0)
                    end
                end
            end
            updateEbonMight()
        else
            -- Normal power mode: restore standard tracking, clean up Ebon Might state
            if ebonMightMode then
                ebonMightEventFrame:UnregisterAllEvents()
                powerBar:SetScript("OnUpdate", nil)
                resetEbonMightTracking()
                -- Undo the EM-mode percentText centering.
                if settings.value_font and powerBar.percentText then
                    private.Util.ApplyFontProfile(powerBar.percentText, settings.value_font, powerBar)
                end
                ebonMightMode = false
            end
            -- Only call SetUnit when the unit needs to change (avoids redundant
            -- UpdatePowerBar → UpdateMaxPower → SetAlpha that clobbers fade alpha).
            if powerBar.unit ~= "player" then
                powerBar:SetUnit("player")
            end
            updatePowerText()

            -- Spend prediction: only for mana-based specs (effective type, so the
            -- mana-override specs predict against mana, not their relocated resource).
            local _, powerToken = getPlayerPrimaryPowerType()
            if settings.spend_prediction and powerToken == "MANA" then
                registerSpendPredictionEvents()
            else
                unregisterSpendPredictionEvents()
            end

            if HAS_FIVE_SECOND_RULE and settings.five_second_rule and powerToken == "MANA" then
                local band = FSR_BANDS[settings.five_second_rule_size] or FSR_BANDS.full
                fsrVertical = isVertical
                fsrBandCentre = band[1]
                local length = settings.height * band[2] * 2
                if isVertical then
                    fsrSpark:SetSize(length, FSR_SPARK_WIDTH)
                else
                    fsrSpark:SetSize(FSR_SPARK_WIDTH, length)
                end
                -- Above every region of the bar itself, the breakpoint pips
                -- (OVERLAY on powerBar) included, and the spend-prediction child
                -- at +1; under ApplyBarBorder's overlay at +5, which carries
                -- percentText. Re-asserted each pass, as ApplyBarBorder does.
                fsrFrame:SetFrameLevel(powerBar:GetFrameLevel() + 2)
                fsrFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            else
                stopFiveSecondRule()
            end
        end

        pipHost.bar = powerBar
        pipHost.key = private.BreakpointPips.GetKeyForCurrentSpec("primary")
        private.BreakpointPips.Apply(pipHost)
    else
        -- Disabled: stop all tracking
        if ebonMightMode then
            ebonMightEventFrame:UnregisterAllEvents()
            powerBar:SetScript("OnUpdate", nil)
            resetEbonMightTracking()
            -- Undo the EM-mode percentText centering.
            if settings.value_font and powerBar.percentText then
                private.Util.ApplyFontProfile(powerBar.percentText, settings.value_font, powerBar)
            end
            ebonMightMode = false
        end
        powerBar:SetUnit(nil)
        unregisterSpendPredictionEvents()
        stopFiveSecondRule()
        private.BreakpointPips.Clear(pipHost)
    end
end

primaryResources.OnEnable = function()
    primaryResources.Refresh()
end

primaryResources.OnDisable = function()
    -- specEventFrame stays registered: a spec change must be able to re-enable it.
    if ebonMightMode then
        ebonMightEventFrame:UnregisterAllEvents()
        powerBar:SetScript("OnUpdate", nil)
        resetEbonMightTracking()
        -- Undo the EM-mode percentText centering.
        if getSettings().value_font and powerBar.percentText then
            private.Util.ApplyFontProfile(powerBar.percentText, getSettings().value_font, powerBar)
        end
        ebonMightMode = false
    end
    unregisterSpendPredictionEvents()
    stopFiveSecondRule()
    if powerBar and not private.isEditMode then
        powerBar:SetUnit(nil)
    end
end

primaryResources.GetComponentName = function()
    return primaryResources.name
end

---True when Ebon Might crit detection is available (player has Double-Time
---talent learned). Used by Options to soft-disable the crit color/glow toggles.
primaryResources.IsCritDetectionAvailable = function()
    return doubleTimeKnown
end

primaryResources.GetComponentSize = function()
    local settings = getSettings()
    if (settings.orientation or "horizontal") == "vertical" then
        return settings.height, settings.width
    end
    return settings.width, settings.height
end

private.PrimaryResources = primaryResources
private.ComponentManager.RegisterComponent("PrimaryResources", primaryResources)
