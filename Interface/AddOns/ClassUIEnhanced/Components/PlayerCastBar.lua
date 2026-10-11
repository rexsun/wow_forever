
local _
---@type string, private
local _, private = ...

local LibSharedMedia = LibStub("LibSharedMedia-3.0")

---@class private : table
---@field PlayerCastBar playercastbar

---@class playercastbar : component

---@type playercastbar
---@diagnostic disable-next-line: missing-fields
local playerCastBar = {}

playerCastBar.name = "PlayerCastBar"

---Guard so the OnShow hook is installed only once, even across profile switches.
local nativeBarHookInstalled = false

---True while the player is casting/channeling (including fade-out animation).
local isCasting = false

---Guard so the cast state hooks are installed only once.
local castStateHookInstalled = false

---GCD instant-cast tracking state
local lastStartedCastGUID = nil
local gcdEventFrame = nil
local isInstantCasting = false
---startTime of the last GCD we displayed an overlay for. Off-GCD spells fire
---SUCCEEDED without triggering a new GCD, so getGCDInfo returns the residual
---startTime of a prior on-GCD cast — matching this value means no fresh GCD
---was incurred and no overlay should be shown.
local lastShownGCDStart = 0
---Synthetic cast bar dedicated to the GCD instant-cast overlay. Created
---unbound (no SetUnit) so DF installs no events and no OnTick — we drive it
---fully via Show/Hide and a custom OnUpdate. Keeps DF's player cast bar
---untouched: its fade, pips, OnTick, and empower lifecycle all stay intact.
---@type _castbar?
local instantOverlay = nil

---Latency tracking. Measured exactly like the GCD bar: the window between the
---client deciding to cast (CURRENT_SPELL_CAST_CHANGED) and the request going
---out (UNIT_SPELLCAST_SENT), falling back to world ping when that window is
---implausible. Drawn as a region covering the end of the bar.
local castSpellChanged = 0
local castLatency = 0
---@type texture?
local latencyTexture

---Forward declarations for file-local functions referenced before definition.
local restoreCastBar
local startInstantCastBar
local updateInactiveBackground
local refreshInstantOverlay

---Query the GCD state via the GCD reference spell (`private.GCD_SPELL_ID`).
---@return number startTime
---@return number duration
local function getGCDInfo()
    local result = C_Spell.GetSpellCooldown(private.GCD_SPELL_ID)
    if not result then
        return 0, 0
    end
    return result.startTime, result.duration
end

---@return castbar_component_profile_main
local getSettings = function()
    return private.profile.components[playerCastBar.name]
end

playerCastBar.GetSettings = getSettings

local getEnabled = function()
    return getSettings().enabled
end

playerCastBar.GetEnabled = getEnabled

---Update the PlayerCastBar component background visibility.
---When hide_inactive_background is enabled, marks the container as empty
---(hiding the background) when the player is not casting or channeling.
updateInactiveBackground = function()
    local settings = getSettings()
    local bar = private.CastBar.GetCastBar("player")
    if not bar or not bar.containerFrame then return end
    if not settings.hide_inactive_background then
        -- Clear the sticky empty flag on the way out — see GlobalCooldown's copy.
        private.Util.SetComponentEmpty(bar.containerFrame, false)
        return
    end
    if private.isEditMode then return end

    private.Util.SetComponentEmpty(bar.containerFrame, not isCasting and not isInstantCasting)
    private.Util.ApplyComponentBackground(bar.containerFrame, settings.background)
end

---Recompute the latency for the cast that is starting. Identical measurement to
---the GCD bar's so both bars report the same number: the window between the
---client deciding to cast and the request going out, falling back to world ping
---when that window is implausible.
local function measureLatency()
    local measured = GetTime() - castSpellChanged
    if measured < 0.05 or measured > 0.6 then
        local _, _, _, ping = GetNetStats()
        measured = ping / 1000
    end
    castLatency = measured
end

---Size and place the latency overlay for the cast in progress. The region
---covers the last `castLatency` seconds of the bar — the window in which the
---next cast can already be queued.
---Duration comes from the bar's own millisecond timestamps, not from
---`durationObject:GetTotalDuration()`: on a regular cast that object can still
---come from `UnitCastingDuration` (CastBar's shim swaps in a plain cast-info
---span only when that info is readable, #50), which is `SecretReturns`, so
---comparing or dividing by its duration would throw. minValue/maxValue come from UnitCastingInfo /
---UnitChannelInfo (secret only while unit spell casts are restricted), so they
---are guarded with `issecretvalue` the way DF guards the same two fields.
local function updateLatencyMarker()
    if not latencyTexture then return end
    local bar = private.CastBar.GetCastBar("player")
    if not isCasting or not getSettings().show_latency or not bar then
        latencyTexture:Hide()
        return
    end

    local minValue, maxValue = bar.minValue, bar.maxValue
    if not minValue or not maxValue or issecretvalue(minValue) or issecretvalue(maxValue) then
        latencyTexture:Hide()
        return
    end

    local duration = (maxValue - minValue) / 1000
    if duration <= 0 or castLatency <= 0 then
        latencyTexture:Hide()
        return
    end

    local frac = castLatency / duration
    if frac > 1 then frac = 1 end

    -- The fill runs out at the far end of a cast or empower (ElapsedTime) and
    -- back at the start of a draining channel (RemainingTime); the overlay
    -- always sits where the bar finishes.
    local atStart = bar.channeling and not bar.empowered
    latencyTexture:ClearAllPoints()
    if bar.cueOrientation == "vertical" then
        local edge = atStart and "BOTTOM" or "TOP"
        latencyTexture:SetPoint(edge .. "LEFT", bar, edge .. "LEFT")
        latencyTexture:SetPoint(edge .. "RIGHT", bar, edge .. "RIGHT")
        latencyTexture:SetHeight(bar:GetHeight() * frac)
    else
        local edge = atStart and "LEFT" or "RIGHT"
        latencyTexture:SetPoint("TOP" .. edge, bar, "TOP" .. edge)
        latencyTexture:SetPoint("BOTTOM" .. edge, bar, "BOTTOM" .. edge)
        latencyTexture:SetWidth(bar:GetWidth() * frac)
    end
    latencyTexture:Show()
end

---Returns true when show_when_casting is enabled and the player is actively
---casting/channeling (including fade-out). Used by the anchor system's
---forceVisible checks to bypass hide decisions without altering alpha/fade.
---@return boolean?
playerCastBar.GetForceVisible = function()
    return (isCasting or isInstantCasting) and getSettings().show_when_casting
end

restoreCastBar = function()
    if not isInstantCasting then return end
    isInstantCasting = false
    if instantOverlay then
        instantOverlay:SetScript("OnUpdate", nil)
        instantOverlay:Hide()
    end
    -- ForceVisibleMatters: forceVisible only ever bypasses a hide gate, so when
    -- nothing would hide this bar (root + "inherit" + no hide rules -- the default
    -- shape) the refresh provably changes nothing and is skipped.  See
    -- Anchoring.ForceVisibleMatters.
    if not isCasting and getSettings().show_when_casting
        and private.Anchor.ForceVisibleMatters(playerCastBar.name) then
        private.Anchor.OnComponentStateChange()
    end
    updateInactiveBackground()
end

startInstantCastBar = function(spellID, startTime, duration)
    if not getSettings().track_instant_casts then return end

    -- Active casts always win — never display the overlay over a real cast.
    if UnitCastingInfo("player") or UnitChannelInfo("player") then return end

    local overlay = instantOverlay
    if not overlay then return end

    local gcdRemaining = startTime + duration - GetTime()
    if gcdRemaining <= 0 then return end

    local spellInfo = C_Spell.GetSpellInfo(spellID)

    isInstantCasting = true
    if getSettings().show_when_casting
        and private.Anchor.ForceVisibleMatters(playerCastBar.name) then
        private.Anchor.OnComponentStateChange()
    end

    local c = private.profile.castbar_colors.instant_cast
    overlay.barTexture:SetVertexColor(private.Util.Color(c))

    overlay:SetMinMaxValues(0, duration)
    overlay:SetValue(gcdRemaining)
    overlay:Show()
    if overlay.Text then
        overlay.Text:SetText(spellInfo and spellInfo.name or "")
    end

    if getSettings().show_icon then
        local spellTexture = C_Spell.GetSpellTexture(spellID)
        if overlay.Icon then
            overlay.Icon:SetTexture(spellTexture)
            overlay.Icon:SetAlpha(1)
            overlay.Icon:Show()
        end
    elseif overlay.Icon then
        overlay.Icon:SetAlpha(0)
        overlay.Icon:Hide()
    end

    overlay:SetScript("OnUpdate", function(self)
        if UnitCastingInfo("player") or UnitChannelInfo("player") then
            restoreCastBar()
            return
        end
        local remaining = startTime + duration - GetTime()
        if remaining <= 0 then
            restoreCastBar()
        else
            self:SetValue(remaining)
            if self.percentText then
                self.percentText:SetText(
                    private.CastBar.FormatCastTime(self.cueTimeStyle, remaining, duration))
            end
        end
    end)
    updateInactiveBackground()
end

local function gcdOnEvent(self, event, unit, castGUID, spellID)
    -- Not a unit event: arg1 is a boolean, so this must precede the unit guard.
    if event == "CURRENT_SPELL_CAST_CHANGED" then
        castSpellChanged = GetTime()
        return
    end

    if unit ~= "player" then return end

    -- Trap: this signature is fixed at (self, event, unit, castGUID, spellID),
    -- but UNIT_SPELLCAST_SENT carries (unit, target, castGUID, spellID) — so
    -- `castGUID` holds the target and `spellID` the castGUID here. This branch
    -- reads neither.
    if event == "UNIT_SPELLCAST_SENT" then
        measureLatency()
        return
    end

    if event == "UNIT_SPELLCAST_START"
        or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_EMPOWER_START" then
        -- START never fires for instants — any START is a real cast. Track
        -- its castGUID so the matching SUCCEEDED can be identified
        -- unambiguously regardless of event/state timing.
        lastStartedCastGUID = castGUID
        restoreCastBar()

    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- Only clear when this FAILED/INTERRUPTED belongs to the tracked
        -- cast — a queued-retry FAILED carries a different castGUID and
        -- must not clobber the live cast's tracking.
        if castGUID == lastStartedCastGUID then
            lastStartedCastGUID = nil
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- castGUID is stable across a cast's whole lifecycle (including
        -- proc/override replacements where spellID changes mid-cast). If
        -- this SUCCEEDED matches the tracked START, it's the real cast's
        -- own completion — clear and suppress overlay.
        if castGUID == lastStartedCastGUID then
            lastStartedCastGUID = nil
            return
        end

        -- Unmatched SUCCEEDED while a tracked cast is still in flight is a
        -- side-effect of the live cast (proc spawn, secondary visual, etc.) —
        -- it carries a different castGUID and would otherwise pre-empt the
        -- real post-cast instant via the lastShownGCDStart dedupe. Ignore.
        if lastStartedCastGUID ~= nil then return end

        C_Timer.After(0, function()
            local startTime, duration = getGCDInfo()
            -- Active casts always win: a real cast in progress (or its
            -- channel) suppresses the overlay entirely.
            if UnitCastingInfo("player") or UnitChannelInfo("player") then return end
            -- Off-GCD spells don't start a new GCD; getGCDInfo returns the
            -- residual prior GCD. Same startTime as last shown means no new
            -- GCD was incurred — skip.
            if duration and duration > 0 and startTime ~= lastShownGCDStart then
                lastShownGCDStart = startTime
                startInstantCastBar(spellID, startTime, duration)
            end
        end)
    end
end

local function enableInstantCastTracking()
    if not gcdEventFrame then
        gcdEventFrame = CreateFrame("Frame")
        gcdEventFrame:SetScript("OnEvent", gcdOnEvent)
    end
    gcdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    gcdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    gcdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    gcdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    gcdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    gcdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    gcdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    gcdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
    gcdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
    gcdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    gcdEventFrame:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
end

local function disableInstantCastTracking()
    if gcdEventFrame then
        gcdEventFrame:UnregisterAllEvents()
    end
    lastStartedCastGUID = nil
    castSpellChanged = 0
    castLatency = 0
    restoreCastBar()
end

---called from the Init.lua file to initialize the component on PLAYER_LOGIN event
playerCastBar.Initialize = function()
    --take in mind this function will be called more than once, when a profile is changed
    if getEnabled() then
        private.CastBar.EnableTalentTracking()
        private.CastBar.EnableMassDisintegrateTracking()
        private.CastBar.EnableEvokerTickCalibration()
        enableInstantCastTracking()
    else
        private.CastBar.DisableTalentTracking()
        private.CastBar.DisableMassDisintegrateTracking()
        private.CastBar.DisableEvokerTickCalibration()
        disableInstantCastTracking()
    end

    if not nativeBarHookInstalled and PlayerCastingBarFrame then
        nativeBarHookInstalled = true
        -- Suppress Blizzard's native cast bar. Some EditMode layouts anchor a
        -- protected frame (e.g. the target frame) onto the cast bar, which makes
        -- the cast bar implicitly protected; Hide() then routes through the
        -- protected HideBase() and is blocked in combat (ADDON_ACTION_BLOCKED,
        -- e.g. Convoke the Spirits firing a CDM refresh mid-channel). When the
        -- frame is protected, fall back to alpha suppression (unprotected,
        -- taint-free) and re-pin it whenever Blizzard raises the alpha again
        -- (cast finish/fade). Matches AzeriteUI's approach for this 12.0
        -- anchor-chain restriction; alpha is reset in OnDisable.
        PlayerCastingBarFrame:HookScript("OnShow", function(self)
            if not getEnabled() then return end
            if self:IsProtected() then
                self:SetAlpha(0)
            else
                self:Hide()
            end
        end)
        hooksecurefunc(PlayerCastingBarFrame, "SetAlpha", function(self, alpha)
            if alpha ~= 0 and getEnabled() and self:IsProtected() then
                self:SetAlpha(0)
            end
        end)
    end

    playerCastBar.Refresh()
end

playerCastBar.GetFrame = function()
    local bar = private.CastBar.GetCastBar("player")
    return bar and bar.containerFrame
end

---Mirror player-bar layout/style settings onto the unbound overlay so options
---changes (texture, fonts, orientation, dimensions) propagate without a reload.
---Called from Refresh after the player bar's own settings have been applied.
refreshInstantOverlay = function()
    local overlay = instantOverlay
    if not overlay then return end
    local settings = getSettings()
    local isVertical = (settings.orientation or "horizontal") == "vertical"
    local frameW = isVertical and settings.height or settings.width
    local frameH = isVertical and settings.width or settings.height
    overlay.cueOrientation = settings.orientation or "horizontal"
    overlay.cueShowIcon = settings.show_icon
    overlay.cueShowSpark = false  -- overlay is a backward-draining timer, no spark
    overlay.Settings.ShowShield = false
    overlay.cueShieldScale = settings.shield_scale or 1.0
    overlay.cueShieldOffsetX = settings.shield_offset_x or 0
    overlay.cueShieldOffsetY = settings.shield_offset_y or 0
    private.CastBar.ApplyTexture(overlay, settings.texture)
    private.CastBar.ApplyColors(overlay)
    if private.fontsDirty then
        private.CastBar.ApplyFonts(overlay, settings)
    end
    -- Explicit size in addition to the SetAllPoints anchor — same-frame
    -- GetWidth/GetHeight reads in updateLayout would otherwise be stale.
    private.Pixel.SetSize(overlay.containerFrame, frameW, frameH)
    overlay.updateLayout()
    -- BorderShield visibility is normally managed by DF's UpdateInterruptState,
    -- which never runs on an unbound bar. Force it hidden — instant casts
    -- can't be non-interruptible, so the shield icon has no meaning here.
    overlay.BorderShield:Hide()
end

playerCastBar.Refresh = function()
    -- Always ensure the cast bar frame exists (needed for Edit Mode positioning)
    if not private.CastBar.GetCastBar("player") then
        local name = "CUE_CastBar_player"
        private.CastBar.CreateCastBar("player", UIParent, name, private.CastBar.DefaultCreateSettings)
    end

    -- Lazy-create the GCD instant-cast overlay, parented to the player
    -- bar's container so it inherits visibility (hidden when component
    -- disabled or anchor-hidden). Geometry tracks the player container
    -- via SetAllPoints — single source of truth for size/position.
    if not instantOverlay then
        local playerBar = private.CastBar.GetCastBar("player")
        instantOverlay = private.CastBar.CreateOverlayBar(
            playerBar.containerFrame,
            "CUE_CastBar_playerInstantOverlay",
            private.CastBar.DefaultCreateSettings
        )
        instantOverlay.containerFrame:SetAllPoints(playerBar.containerFrame)
        instantOverlay:Hide()
    end

    -- Latency overlay. Artwork sublevel 1 draws above the fill (sublevel -6)
    -- and below the icon and spark (overlay). Hidden until a cast sizes it.
    if not latencyTexture then
        local playerBar = private.CastBar.GetCastBar("player")
        latencyTexture = playerBar:CreateTexture(nil, "ARTWORK", nil, 1)
        latencyTexture:Hide()
    end

    if not castStateHookInstalled then
        castStateHookInstalled = true
        local bar = private.CastBar.GetCastBar("player")

        ---Cast started: fires from DF's UpdateCastingInfo/UpdateChannelInfo
        ---event handler, regardless of frame visibility.
        bar:SetHook("OnCastStart", function()
            if not isCasting then
                isCasting = true
                if getSettings().show_when_casting
                    and private.Anchor.ForceVisibleMatters(playerCastBar.name) then
                    private.Anchor.OnComponentStateChange()
                end
                updateInactiveBackground()
            end
            -- Deterministic re-measurement for channels/empowers: same frame,
            -- same hook, immediately before the value is consumed below.
            -- UNIT_SPELLCAST_SENT (gcdOnEvent) remains the only measurement
            -- site for hard casts. bar.channeling is set by DF's
            -- UpdateChannelInfo for both a plain channel and an empower.
            if bar.channeling then measureLatency() end
            -- Last: RunHooksForWidget aborts the remaining hooks in the list on
            -- a throw, so nothing above may depend on this call succeeding.
            updateLatencyMarker()
        end)

        ---Pushback (UNIT_SPELLCAST_DELAYED), a clipped or re-entered channel
        ---(UNIT_SPELLCAST_CHANNEL_UPDATE), and an empower whose duration
        ---changes mid-cast (UNIT_SPELLCAST_EMPOWER_UPDATE, which DF delegates
        ---to CHANNEL_UPDATE) re-assign the bar's maxValue without firing
        ---OnCastStart, so the overlay fraction has to be recomputed.
        ---SetHook appends, so this coexists with the shared module's own
        ---OnEvent hook.
        bar:SetHook("OnEvent", function(_, _, event)
            if event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
                or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
                updateLatencyMarker()
            end
        end)

        ---Cast ended (after fade-out animation completes): DF bar hides.
        ---DF's OnHide does not call RunHooksForWidget, so use HookScript.
        ---Safe — this is an addon-owned DF StatusBar, not a protected frame.
        bar:HookScript("OnHide", function()
            if isCasting then
                isCasting = false
                if getSettings().show_when_casting
                    and private.Anchor.ForceVisibleMatters(playerCastBar.name) then
                    private.Anchor.OnComponentStateChange()
                end
                updateInactiveBackground()
            end
        end)

    end

    local settings = getSettings()
    local bar = private.CastBar.GetCastBar("player")

    -- Set orientation before ApplyFonts so text rotation uses the current value.
    bar.cueOrientation = settings.orientation or "horizontal"
    bar.cueShowIcon = settings.show_icon
    bar.cueShowSpark = settings.show_spark
    bar.Settings.ShowShield = settings.show_shield ~= nil and settings.show_shield or false
    bar.cueShieldScale = settings.shield_scale or 1.0
    bar.cueShieldOffsetX = settings.shield_offset_x or 0
    bar.cueShieldOffsetY = settings.shield_offset_y or 0
    local isVertical = bar.cueOrientation == "vertical"

    -- Apply visual properties before the visibility gate so the bar is
    -- already styled when the anchor chain becomes visible later.
    -- ApplyColors runs before ApplyFonts because ApplyColors creates the
    -- border overlay frame that ApplyFonts reparents text FontStrings to.
    private.CastBar.ApplyTexture(bar, settings.texture)
    private.CastBar.ApplyColors(bar)
    if private.fontsDirty then
        private.CastBar.ApplyFonts(bar, settings)
    end
    -- Overlay wears the bar's own statusbar texture, tinted by latency_color —
    -- same treatment the GCD bar gives its latency region, so the overlay isn't
    -- a flat block over a textured fill. White fallback when the LSM key is
    -- empty or unregistered, matching CastBar.ApplyTexture.
    local latencyPath
    if settings.texture and settings.texture ~= "" then
        latencyPath = LibSharedMedia:Fetch("statusbar", settings.texture, true)
    end
    if latencyPath then
        latencyTexture:SetTexture(latencyPath)
    else
        latencyTexture:SetColorTexture(1, 1, 1, 1)
    end
    local lc = settings.latency_color
    latencyTexture:SetVertexColor(lc[1], lc[2], lc[3], lc[4])
    -- Re-derive geometry here too: gated on isCasting, so this both applies a
    -- mid-cast toggle/width/orientation change and hides the overlay whenever
    -- no cast is running (including the Edit Mode preview).
    updateLatencyMarker()
    -- Mirror styling onto the overlay BEFORE the edit-mode / visibility
    -- early-returns. The overlay must stay in sync with the player bar's
    -- font/anchor settings even when the bar itself is hidden — otherwise
    -- the first time it's shown it renders with DF defaults instead of
    -- user fonts, and the player bar's lingering fade-out text shows
    -- through while the overlay's name draws off-position.
    refreshInstantOverlay()
    local frameW = isVertical and settings.height or settings.width
    local frameH = isVertical and settings.width or settings.height

    -- In edit mode, always show the container with a dummy cast preview
    if private.isEditMode then
        bar.containerFrame:Show()
        private.Pixel.SetSize(bar.containerFrame, frameW, frameH)
        bar.updateLayout()
        private.CastBar.ShowEditModePreview(bar)
        return
    end

    -- Reset any edit mode preview artifacts before normal display logic.
    -- Skip when actively casting — the real cast overwrites preview state,
    -- and HideEditModePreview calls bar:Hide() which would trigger our
    -- OnHide hook and create a show/hide feedback loop.
    if not isCasting then
        private.CastBar.HideEditModePreview(bar)
    end

    if not settings.enabled or not private.Anchor.IsVisibleForComponent(playerCastBar.name) then
        bar.containerFrame:Hide()
        return
    end

    bar.containerFrame:Show()
    private.Pixel.SetSize(bar.containerFrame, frameW, frameH)
    bar.updateLayout()
    -- Re-evaluate current cast state so an in-progress cast shows after
    -- the visibility chain becomes visible (e.g. dismounting)
    bar:PLAYER_ENTERING_WORLD(bar.unit, bar.unit)
    private.CastBar.UpdateTicksTable()
    updateInactiveBackground()

end

playerCastBar.OnEnable = function()
    private.CastBar.EnableTalentTracking()
    private.CastBar.EnableMassDisintegrateTracking()
    private.CastBar.EnableEvokerTickCalibration()
    enableInstantCastTracking()
    playerCastBar.Refresh()
end

playerCastBar.OnDisable = function()
    isCasting = false
    private.CastBar.DisableTalentTracking()
    private.CastBar.DisableMassDisintegrateTracking()
    private.CastBar.DisableEvokerTickCalibration()
    disableInstantCastTracking()
    private.CastBar.HideForUnit("player")
    -- Restore the native cast bar we suppressed via alpha (protected layouts).
    if PlayerCastingBarFrame then PlayerCastingBarFrame:SetAlpha(1) end
    local bar = private.CastBar.GetCastBar("player")
    if bar then bar.containerFrame:Hide() end
end

playerCastBar.GetComponentName = function()
    return playerCastBar.name
end

playerCastBar.GetComponentSize = function()
    local settings = getSettings()
    if (settings.orientation or "horizontal") == "vertical" then
        return settings.height, settings.width
    end
    return settings.width, settings.height
end

private.PlayerCastBar = playerCastBar
private.ComponentManager.RegisterComponent("PlayerCastBar", playerCastBar)
