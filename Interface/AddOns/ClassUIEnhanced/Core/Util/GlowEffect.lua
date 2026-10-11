
--[[
    GlowEffect — shared glow/alert utility for icon frames.

    Creates lightweight overlay frames on-demand per icon and manages
    animation lifecycle. Six independent glow styles:

    1. Flash       — one-shot proc burst FlipBook (0.7 s), for cooldown-ready events
    2. Pulse       — looping proc FlipBook border with optional timer, for "available" state
    3. Approaching — subtle gold square border pulse, for items about to come off cooldown
    4. Border      — pulsing red square border for low health alerts on health items
    5. Active      — green square border pulse, for active trinket/potion buff duration
    6. Proc        — pulsing border or LibCustomGlow effect for the proc_glow_style dropdown

    Each style is a separate child Frame so they layer and animate independently.
    Approaching auto-stops when its companion pulse/flash starts.
    No new OnUpdate handlers are introduced; timer expiry is checked by the
    calling component's existing polling loop via IsPulseExpired().

    Flash and Pulse use Blizzard's action bar proc FlipBook atlases
    (ActionButtonSpellAlerts.xml) for square-cornered animations.
    Approaching and Border use BackdropTemplate with a flat edge border.

    Additionally, when profile.proc_glow.enabled is true, Blizzard's native
    CooldownViewer marching ants alert frames are re-anchored to match the
    addon's PULSE_INSET for a tighter fit around the icon.

    This module also hosts the static edge border (ApplyEdgeBorder /
    CreateActiveBorder) that both the pandemic and active-aura cues draw
    directly on an aura button's own regions.

    The "ants"/"autocast"/"pixel" styles on the proc glow dropdown are powered
    by LibCustomGlow. Its effects are applied to addon-owned wrapper frames so
    the library's frame-key writes never taint a CooldownViewer child (see
    patterns.md). They are offered for proc glow only: the pandemic cue lives
    inside an aura button's subtree, where the library's pooled child frames and
    SetScript calls are both blocked by secret aspects.
--]]

local _
---@type string, private
local addonName, private = ...

---@class private : table
---@field GlowEffect gloweffect

---@class gloweffect : table

---@type gloweffect
local glowEffect = {}

-- Per-icon glow state, keyed by icon frame reference. Held in this module
-- table rather than written onto the icon (icon._cueGlow) — writing Lua keys
-- onto CooldownViewer child frames taints wasOnGCDLookup (patterns.md).
-- Mirrors the table<frame,value> pattern used by AssistedHighlight.highlightFrames.
local glowByIcon = {}

-- LibCustomGlow powers the "ants"/"autocast"/"pixel" styles on the proc glow
-- dropdown. Resolved silently — a nil lib degrades those styles to no-ops
-- rather than erroring.
local LCG = LibStub("LibCustomGlow-1.0", true)

-- Color constants for border glow styles.
local COLOR_GOLD = {1, 0.843, 0, 1}
local COLOR_RED = {0.792, 0.102, 0.102, 1}
local COLOR_ACTIVE = {0.2, 0.8, 0.4, 1}

-- Flash/Pulse FlipBook overlays extend beyond the icon by this many pixels on each side.
local PULSE_INSET = 12

-- Blizzard's proc alert geometry (ActionButtonSpellAlerts.lua/.xml) per unit of
-- icon size: the alert frame is the button ×1.4 and the loop fills it; the
-- burst is a fixed 150×150 drawn for the 45px action button.
local PROC_LOOP_OVERHANG = 0.2
local PROC_START_SCALE = 150 / 45

-- Border thickness for Approaching/Border styles (BackdropTemplate edgeSize).
local BORDER_EDGE_SIZE = 2

-- ---------------------------------------------------------------------------
-- Internal: per-icon overlay creation
-- ---------------------------------------------------------------------------

---Create a FlipBook glow sub-frame (used for Flash and Pulse styles).
---Atlas and FlipBook params from Blizzard's ActionButtonSpellAlerts.xml
---(ProcStartAnim for flash, ProcLoop for pulse).
---@param parent frame  parent frame for the glow overlay
---@param anchorTo frame  frame to anchor the glow edges to (typically the icon)
---@param atlas string  atlas name for the FlipBook texture
---@param inset number  pixels to extend beyond icon edges
---@param duration number  seconds per animation cycle
---@param looping string  "NONE"|"REPEAT"
---@param flipRows number  FlipBook spritesheet rows
---@param flipCols number  FlipBook spritesheet columns
---@param flipFrames number  total FlipBook frames
---@return frame glowFrame
local function createFlipBookFrame(parent, anchorTo, atlas, inset, duration, looping, flipRows, flipCols, flipFrames)
    local f = CreateFrame("Frame", nil, parent)
    private.Pixel.SetPoint(f, "TOPLEFT", anchorTo, "TOPLEFT", -inset, inset)
    private.Pixel.SetPoint(f, "BOTTOMRIGHT", anchorTo, "BOTTOMRIGHT", inset, -inset)
    f:SetFrameLevel(anchorTo:GetFrameLevel() + 2)

    local tex = f:CreateTexture(nil, "OVERLAY")
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
    tex:SetAllPoints()
    tex:SetAtlas(atlas)
    f.Flipbook = tex

    local ag = f:CreateAnimationGroup()
    ag:SetLooping(looping)
    ag:SetToFinalAlpha(true)

    local fb = ag:CreateAnimation("FlipBook")
    fb:SetChildKey("Flipbook")
    fb:SetDuration(duration)
    fb:SetOrder(1)
    fb:SetFlipBookRows(flipRows)
    fb:SetFlipBookColumns(flipCols)
    fb:SetFlipBookFrames(flipFrames)
    fb:SetFlipBookFrameWidth(0)
    fb:SetFlipBookFrameHeight(0)

    f.anim = ag
    f:Hide()
    return f
end

---Create a BackdropTemplate border glow sub-frame (used for Approaching and Border styles).
---Uses a flat WHITE8x8 edge for crisp square corners.
---@param parent frame  parent frame for the glow overlay
---@param anchorTo frame  frame to anchor the glow edges to (typically the icon)
---@param color number[]  {r, g, b, a} border color
---@param looping string  "BOUNCE"|"REPEAT"
---@param alphaFrom number  starting alpha for the animation
---@param alphaTo number  ending alpha for the animation
---@param alphaDuration number  seconds per animation cycle
---@return frame glowFrame
local function createBorderFrame(parent, anchorTo, color, looping, alphaFrom, alphaTo, alphaDuration)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    private.Pixel.SetPoint(f, "TOPLEFT", anchorTo, "TOPLEFT", -BORDER_EDGE_SIZE, BORDER_EDGE_SIZE)
    private.Pixel.SetPoint(f, "BOTTOMRIGHT", anchorTo, "BOTTOMRIGHT", BORDER_EDGE_SIZE, -BORDER_EDGE_SIZE)
    f:SetFrameLevel(anchorTo:GetFrameLevel() + 2)

    f:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = BORDER_EDGE_SIZE,
    })
    f:SetBackdropBorderColor(unpack(color))

    local ag = f:CreateAnimationGroup()
    ag:SetLooping(looping)
    ag:SetToFinalAlpha(true)

    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetDuration(alphaDuration)
    fadeIn:SetFromAlpha(alphaFrom)
    fadeIn:SetToAlpha(alphaTo)
    fadeIn:SetSmoothing("IN_OUT")
    fadeIn:SetOrder(1)

    f.anim = ag
    f:Hide()
    return f
end

---Get or create the glow table for an icon, containing flash/pulse/approaching/border sub-frames.
---The border glow uses a two-frame architecture: a wrapper frame whose alpha is
---driven by a secret health curve value, containing the animated border frame.
---Effective border alpha = wrapper.alpha × border.animation.alpha, so the border
---is invisible when the wrapper alpha is 0 (health above threshold) even while
---the animation plays.
---
---All glow sub-frames are parented to glow.root (a wrapper on the icon) rather
---than directly to the icon, which groups them at one frame level and gives
---every effect a single alpha chain back to the icon.
---@param icon frame
---@return table glow  { root, flash, pulse, approaching, borderWrapper, border, active, procWrapper, proc, procLib, pulseExpiry }
local function getOrCreateGlow(icon)
    local existing = glowByIcon[icon]
    if existing then return existing end

    local glow = {}

    -- Root wrapper: sits between the icon and all glow sub-frames.  An
    -- ordinary child, so its effective alpha is the icon's — including when
    -- the icon carries SetIgnoreParentAlpha(true) to be cross-parent
    -- positioned in an AF, since that flag governs only how the ICON reads
    -- its own parent, not what its descendants inherit from it.
    glow.root = CreateFrame("Frame", nil, icon)
    glow.root:SetAllPoints(icon)
    glow.root:SetFrameLevel(icon:GetFrameLevel() + 1)

    -- Flash: one-shot proc burst FlipBook (0.7s).
    -- Atlas and params from ActionButtonSpellAlerts.xml ProcStartAnim.
    glow.flash = createFlipBookFrame(glow.root, icon,
        "UI-HUD-ActionBar-Proc-Start-Flipbook", PULSE_INSET,
        0.7, "NONE", 6, 5, 30)
    glow.flash.anim:SetScript("OnPlay", function()
        glow.flash:Show()
    end)
    glow.flash.anim:SetScript("OnFinished", function()
        glow.flash:Hide()
    end)

    -- Pulse: looping proc FlipBook (1.0s per cycle).
    -- Uses PULSE_INSET for a thicker, more visible border.
    -- Atlas and params from ActionButtonSpellAlerts.xml ProcLoop.
    glow.pulse = createFlipBookFrame(glow.root, icon,
        "UI-HUD-ActionBar-Proc-Loop-Flipbook", PULSE_INSET,
        1, "REPEAT", 6, 5, 30)
    glow.pulse.anim:SetScript("OnPlay", function() glow.pulse:Show() end)
    glow.pulse.anim:SetScript("OnStop", function() glow.pulse:Hide() end)

    -- Approaching wrapper: parent frame whose alpha is driven by secret duration
    -- values from EvaluateRemainingDuration() + step curve. The wrapper's alpha
    -- multiplies with the border animation's alpha, making the border invisible
    -- when the wrapper alpha is 0 (not yet expiring) even while the animation
    -- plays. Show/Hide on the wrapper is controlled by non-secret state; only
    -- the alpha may be secret.
    glow.approachingWrapper = CreateFrame("Frame", nil, glow.root)
    glow.approachingWrapper:SetAllPoints(icon)
    glow.approachingWrapper:SetFrameLevel(icon:GetFrameLevel() + 1)
    glow.approachingWrapper:Hide()

    -- Approaching: subtle gold square border pulse (alpha 0.15 <-> 0.4, 0.8s cycle).
    -- Signals that a cooldown is about to finish. Less intrusive than proc glow.
    -- Uses BackdropTemplate with WHITE8x8 edge for crisp square corners.
    -- Parented to approachingWrapper so wrapper alpha controls effective visibility.
    glow.approaching = createBorderFrame(glow.approachingWrapper, icon, COLOR_GOLD,
        "BOUNCE", 0.15, 0.4, 0.8)
    glow.approaching.anim:SetScript("OnPlay", function()
        glow.approaching:Show()
    end)
    glow.approaching.anim:SetScript("OnStop", function()
        glow.approaching:Hide()
    end)

    -- Border wrapper: parent frame whose alpha is driven by secret health values
    -- from UnitHealthPercent() + step curve. The wrapper's alpha multiplies with
    -- the border animation's alpha, making the border invisible when the wrapper
    -- alpha is 0 (health above threshold). Show/Hide on the wrapper is controlled
    -- by non-secret state (combat, cooldown); only the alpha is secret.
    glow.borderWrapper = CreateFrame("Frame", nil, glow.root)
    glow.borderWrapper:SetAllPoints(icon)
    glow.borderWrapper:SetFrameLevel(icon:GetFrameLevel() + 1)
    glow.borderWrapper:Hide()

    -- Border: low health red square border pulse (alpha 0.5 <-> 1.0 over 0.4s).
    -- Parented to borderWrapper so wrapper alpha controls effective visibility.
    -- Uses BackdropTemplate with WHITE8x8 edge for crisp square corners.
    glow.border = createBorderFrame(glow.borderWrapper, icon, COLOR_RED,
        "BOUNCE", 0.5, 1, 0.4)
    glow.border.anim:SetScript("OnPlay", function()
        glow.border:Show()
    end)
    glow.border.anim:SetScript("OnStop", function()
        glow.border:Hide()
    end)

    -- Active: green square border pulse (alpha 0.5 <-> 0.9 over 1.2s).
    -- Signals that the item's buff effect is currently running on the player.
    -- Uses BackdropTemplate with WHITE8x8 edge for crisp square corners.
    glow.active = createBorderFrame(glow.root, icon, COLOR_ACTIVE,
        "BOUNCE", 0.5, 0.9, 1.2)
    glow.active.anim:SetScript("OnPlay", function()
        glow.active:Show()
    end)
    glow.active.anim:SetScript("OnStop", function()
        glow.active:Hide()
    end)

    -- Proc wrapper: carries the user-configured proc_glow_alpha. The pulse
    -- animation drives glow.proc's own alpha (0.5↔1.0), so the configured
    -- opacity has to ride on a separate frame or the animation overrides it.
    -- Effective alpha = wrapper.alpha × animation alpha. Stays shown;
    -- glow.proc's own Show/Hide controls visibility. Mirrors the
    -- approachingWrapper / borderWrapper pattern.
    glow.procWrapper = CreateFrame("Frame", nil, glow.root)
    glow.procWrapper:SetAllPoints(icon)
    glow.procWrapper:SetFrameLevel(icon:GetFrameLevel() + 1)

    -- Proc: dynamic-color square border pulse for the "border" proc_glow_style.
    -- Fast pulse (alpha 0.5 <-> 1.0 over 0.4s) to match the urgency of a proc.
    -- Color, opacity, and edge thickness are set per-call via StartProc.
    glow.proc = createBorderFrame(glow.procWrapper, icon, {1, 1, 1, 1},
        "BOUNCE", 0.5, 1, 0.4)
    glow.proc.anim:SetScript("OnPlay", function()
        glow.proc:Show()
    end)
    glow.proc.anim:SetScript("OnStop", function()
        glow.proc:Hide()
    end)

    -- Proc lib-glow host: addon-owned frame that receives LibCustomGlow's
    -- _ButtonGlow/_AutoCastGlow/_PixelGlow keys for the ants/autocast/pixel
    -- proc_glow_styles. Separate from the CDM child so the library's frame-key
    -- writes never land on a CooldownViewer frame (patterns.md taint rules).
    glow.procLib = CreateFrame("Frame", nil, glow.root)
    glow.procLib:SetAllPoints(icon)
    glow.procLib:SetFrameLevel(icon:GetFrameLevel() + 1)

    glow.pulseExpiry = nil

    glowByIcon[icon] = glow
    return glow
end

-- ---------------------------------------------------------------------------
-- LibCustomGlow integration
-- ---------------------------------------------------------------------------
-- The "ants"/"autocast"/"pixel" styles (shared by proc_glow_style and
-- pandemic_glow_style) are rendered by LibCustomGlow. The library writes
-- _ButtonGlow / _AutoCastGlow / _PixelGlow keys onto the frame it is given,
-- so callers must pass an addon-owned frame — never a CooldownViewer child.

-- Style keys that route to LibCustomGlow rather than a built-in animation.
local LIB_STYLES = { ants = true, autocast = true, pixel = true }

-- Map the 1–6 thickness slider to an AutoCastGlow scale. Thickness 2 lands
-- exactly on LCG's default scale of 1.0; the range 0.7–2.2 keeps the sparkle
-- size visually meaningful at both ends.
local function lcgAutocastScale(thickness)
    return 0.7 + (math.max(1, math.min(6, thickness or 2)) - 1) * 0.3
end

---Apply a LibCustomGlow effect to an addon-owned frame. Idempotent on style
---AND thickness: the running pair is tracked on the frame
---(_libActiveStyle / _libActiveThickness), so re-calling with the same values
---is a no-op and the effect keeps playing without its intro animation
---replaying — callers on a high-frequency refresh path can invoke this every
---tick. A thickness change forces a clean stop+start because LCG has no
---in-place thickness API. Color is deliberately NOT compared: pandemic glow
---colors may be secret values, and secret values cannot be compared. A color
---change is picked up on the next start instead — proc glows restart on the
---next proc event, pandemic overlays on the next show. No-op when
---LibCustomGlow is unavailable.
---@param frame frame  addon-owned host frame
---@param style string  "ants"|"autocast"|"pixel"
---@param color number[]?  {r, g, b, a}; nil uses the library default
---@param thickness number?  1–6 slider value; drives pixel line width / autocast scale; ignored by ants
local function applyLibGlow(frame, style, color, thickness)
    if not LCG then return end
    -- Already running this style at this thickness — leave it playing.
    if frame._libActiveStyle == style and frame._libActiveThickness == thickness then return end
    frame._libActiveStyle = style
    frame._libActiveThickness = thickness
    if style == "ants" then
        LCG.AutoCastGlow_Stop(frame)
        LCG.PixelGlow_Stop(frame)
        LCG.ButtonGlow_Start(frame, color)
    elseif style == "autocast" then
        LCG.ButtonGlow_Stop(frame)
        LCG.PixelGlow_Stop(frame)
        LCG.AutoCastGlow_Start(frame, color, nil, nil, lcgAutocastScale(thickness))
    elseif style == "pixel" then
        LCG.ButtonGlow_Stop(frame)
        LCG.AutoCastGlow_Stop(frame)
        LCG.PixelGlow_Start(frame, color, nil, nil, nil, thickness or 1)
        -- LCG bakes the line length from GetSize() at start, clamped to
        -- min(w,h), and never re-derives it (see LibCustomGlow PixelGlow_Start
        -- / pUpdate). A freshly-created procLib reads size 0 the frame it is
        -- created — first-ever proc on an icon, anchors unresolved — so length
        -- bakes to 0 and the lines stay invisible forever. Don't latch on a
        -- zero-size start so the next per-tick StartProc restarts it once the
        -- SetAllPoints size has resolved. ButtonGlow/AutoCastGlow bake no
        -- size-derived length, so they don't need this.
        if frame:GetWidth() == 0 then
            frame._libActiveStyle = nil
            frame._libActiveThickness = nil
        end
    end
end

---Stop every LibCustomGlow effect on a frame and clear its tracked running
---state. Safe (and a cheap no-op) on frames that are not currently glowing.
---@param frame frame
local function clearLibGlow(frame)
    if not LCG or not frame._libActiveStyle then return end
    frame._libActiveStyle = nil
    frame._libActiveThickness = nil
    frame._libRecolorAt = nil
    LCG.ButtonGlow_Stop(frame)
    LCG.AutoCastGlow_Stop(frame)
    LCG.PixelGlow_Stop(frame)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

---Play a one-shot flash animation on an icon.
---@param icon frame
function glowEffect.PlayFlash(icon)
    local glow = getOrCreateGlow(icon)
    if glow.flash.anim:IsPlaying() then
        glow.flash.anim:Stop()
    end
    glow.flash.anim:Play()
end

---Start the persistent pulsing glow on an icon.
---@param icon frame
---@param durationSeconds number  0 = infinite (until manually stopped)
function glowEffect.StartPulse(icon, durationSeconds)
    local glow = getOrCreateGlow(icon)
    if not glow.pulse.anim:IsPlaying() then
        glow.pulse.anim:Play()
    end
    if durationSeconds and durationSeconds > 0 then
        glow.pulseExpiry = GetTime() + durationSeconds
    else
        glow.pulseExpiry = nil
    end
end

---Stop just the persistent pulse glow (leaves flash to finish naturally).
---@param icon frame
function glowEffect.StopPulse(icon)
    local glow = glowByIcon[icon]
    if not glow then return end
    if glow.pulse.anim:IsPlaying() then
        glow.pulse.anim:Stop()
    end
    glow.pulseExpiry = nil
end

---Returns true when the pulse timer has expired and should be stopped.
---@param icon frame
---@return boolean
function glowEffect.IsPulseExpired(icon)
    local glow = glowByIcon[icon]
    if not glow then return false end
    local expiry = glow.pulseExpiry
    return expiry ~= nil and GetTime() >= expiry
end

---Play the CDM "cooldown ready" flipbook on an icon, tinted by `cdm_glow_color`.
---
---Atlas and FlipBook params are Blizzard's CooldownFlash template verbatim
---(`CooldownViewer.xml:65-81`: `UI-HUD-ActionBar-GCD-Flipbook`, 11×2 sheet,
---22 frames, 0.75 s), and the tint is a plain `SetVertexColor` with no
---desaturate, matching what Blizzard's own CooldownFlash does.
---
---**Timing deviates by design.** Blizzard SCHEDULES this 0.75 s early so the
---animation *completes* at the ready moment (`SetStartDelay(start + duration -
---GetTime() - 0.75)`, `CooldownViewer.lua:1159-1174`). That arithmetic is on
---secret cooldown times and no animation API accepts a DurationObject, so the
---pre-ready placement is unreachable — see `.context/patterns-secrets.md` "You
---cannot SCHEDULE off a secret time". Callers fire this on the plain-bool ready
---EDGE instead, so the same animation plays starting where Blizzard's ended.
---@param icon frame
---@param color number[]?  {r, g, b, a} tint; nil leaves the atlas untinted
function glowEffect.PlayReadyFlash(icon, color)
    local glow = getOrCreateGlow(icon)
    if not glow.readyFlash then
        -- inset 0: the CooldownFlash template is flush to the item (its 1 px
        -- upward nudge is not worth a parameter on createFlipBookFrame).
        glow.readyFlash = createFlipBookFrame(glow.root, icon,
            "UI-HUD-ActionBar-GCD-Flipbook", 0, 0.75, "NONE", 11, 2, 22)
        glow.readyFlash.anim:SetScript("OnPlay", function() glow.readyFlash:Show() end)
        glow.readyFlash.anim:SetScript("OnFinished", function() glow.readyFlash:Hide() end)
    end
    if color then
        glow.readyFlash.Flipbook:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    end
    if glow.readyFlash.anim:IsPlaying() then
        glow.readyFlash.anim:Stop()
    end
    glow.readyFlash.anim:Play()
end

---Stop the CDM ready flipbook mid-play. Only needed when a pooled icon is
---released inside the 0.75 s window; the animation otherwise self-hides.
---@param icon frame
function glowEffect.StopReadyFlash(icon)
    local glow = glowByIcon[icon]
    if not glow or not glow.readyFlash then return end
    if glow.readyFlash.anim:IsPlaying() then
        glow.readyFlash.anim:Stop()
    end
    glow.readyFlash:Hide()
end

---Start the approaching-ready border glow on an icon. Shows the wrapper
---and plays the pulsing animation. Resets wrapper alpha to 1 so the glow
---is visible by default; use SetApproachingAlpha to override with a
---secret curve value.
---@param icon frame
function glowEffect.StartApproaching(icon)
    local glow = getOrCreateGlow(icon)
    glow.approachingWrapper:SetAlpha(1)
    glow.approachingWrapper:Show()
    if not glow.approaching.anim:IsPlaying() then
        glow.approaching.anim:Play()
    end
end

---Stop the approaching-ready border glow on an icon. Stops the animation
---and hides the wrapper.
---@param icon frame
function glowEffect.StopApproaching(icon)
    local glow = glowByIcon[icon]
    if not glow then return end
    if glow.approaching.anim:IsPlaying() then
        glow.approaching.anim:Stop()
    end
    glow.approachingWrapper:Hide()
end

---Set the approaching wrapper alpha. Accepts secret values from
---EvaluateRemainingDuration() curve evaluation. The wrapper alpha multiplies
---with the border animation's own alpha (0.15↔0.4), so setting 0 makes the
---border invisible while 1 lets the pulsing show through.
---@param icon frame
---@param alpha number  secret or non-secret alpha value [0, 1]
function glowEffect.SetApproachingAlpha(icon, alpha)
    local glow = getOrCreateGlow(icon)
    glow.approachingWrapper:SetAlpha(alpha)
end

---Start the low health border glow on an icon. Shows the wrapper frame and
---plays the pulsing animation. The wrapper's alpha (set via SetBorderAlpha)
---controls whether the border is actually visible. Call this when the icon
---enters combat with the item off cooldown and low_health_enabled is true.
---@param icon frame
function glowEffect.StartBorder(icon)
    local glow = getOrCreateGlow(icon)
    glow.borderWrapper:Show()
    if not glow.border.anim:IsPlaying() then
        glow.border.anim:Play()
    end
end

---Stop the low health border glow on an icon. Stops the animation and hides
---the wrapper. Call this when leaving combat or item goes on cooldown.
---@param icon frame
function glowEffect.StopBorder(icon)
    local glow = glowByIcon[icon]
    if not glow then return end
    if glow.border.anim:IsPlaying() then
        glow.border.anim:Stop()
    end
    glow.borderWrapper:Hide()
end

---Set the low health border wrapper alpha. Accepts secret values from
---UnitHealthPercent() curve evaluation. The wrapper alpha multiplies with
---the border animation's own alpha (0.5↔1.0), so setting 0 makes the
---border invisible while 1 lets the pulsing show through.
---@param icon frame
---@param alpha number  secret or non-secret alpha value [0, 1]
function glowEffect.SetBorderAlpha(icon, alpha)
    local glow = getOrCreateGlow(icon)
    glow.borderWrapper:SetAlpha(alpha)
end

---Start the active buff border glow on an icon. Shows a pulsing border while
---the buff effect is running on the player.
---@param icon frame
---@param color? number[]  {r, g, b, a} border tint; omitted keeps the creation-time green (COLOR_ACTIVE, which is also the active_glow_color default)
function glowEffect.StartActive(icon, color)
    local glow = getOrCreateGlow(icon)
    if color then
        glow.active:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
    end
    if not glow.active.anim:IsPlaying() then
        glow.active.anim:Play()
    end
end

---Stop the active buff border glow on an icon.
---@param icon frame
function glowEffect.StopActive(icon)
    local glow = glowByIcon[icon]
    if not glow then return end
    if glow.active.anim:IsPlaying() then
        glow.active.anim:Stop()
    end
end

---Lazily create the Blizzard-look proc FlipBook frames (start burst + loop).
---Same atlases as glow.flash / glow.pulse, but dedicated to the proc glow so a
---component that also drives the ready-flash or available-pulse on the SAME
---icon cannot stop a running proc (relevant once route_trinkets appends
---TrinketTracker icons to a proc-glowing tracker grid). Created on first
---blizzard-style proc rather than in getOrCreateGlow — icons that never proc
---pay nothing.
---@param icon frame
---@param glow table
local function getOrCreateProcFlipbooks(icon, glow)
    if glow.procStart then return end

    glow.procStart = createFlipBookFrame(glow.procWrapper, icon,
        "UI-HUD-ActionBar-Proc-Start-Flipbook", PULSE_INSET,
        0.7, "NONE", 6, 5, 30)
    glow.procStart.anim:SetScript("OnPlay", function() glow.procStart:Show() end)
    -- The loop follows the burst, as ActionButtonSpellAlertMixin:OnLoad chains
    -- it. OnFinished does not fire on Stop(), so StopProc mid-burst starts nothing.
    glow.procStart.anim:SetScript("OnFinished", function()
        glow.procStart:Hide()
        glow.procLoop.anim:Play()
    end)

    glow.procLoop = createFlipBookFrame(glow.procWrapper, icon,
        "UI-HUD-ActionBar-Proc-Loop-Flipbook", PULSE_INSET,
        1, "REPEAT", 6, 5, 30)
    glow.procLoop.anim:SetScript("OnPlay", function() glow.procLoop:Show() end)
    glow.procLoop.anim:SetScript("OnStop", function() glow.procLoop:Hide() end)
end

---Start the proc glow on an icon for a non-"none" proc_glow_style.
---
---"blizzard" renders the action-bar proc alert with addon-owned FlipBook frames
---rather than ActionButtonSpellAlertManager:ShowAlert — the manager records the
---frame in its own `activeAlerts` table, and writing there from addon code
---taints a table Blizzard's action buttons read. Deviation: Blizzard's manager
---also swaps to the AssistedCombat alt-glow art when an assisted-rotation
---button exists; ours always draws the standard proc art.
---The "border"/"border_inside" styles draw a dynamic-color backdrop edge — beyond
---the icon edge for "outside", within it for "inside" — with the edge anchor
---re-applied when thickness or position changes, and opacity riding on the proc
---wrapper so the pulse animation does not override it. The "ants"/"autocast"/
---"pixel" styles delegate to LibCustomGlow on a dedicated addon-owned host frame;
---"pixel"/"autocast" pick up thickness as line width / sparkle scale, "ants"
---ignores it (LCG ButtonGlow has no size knob).
---@param icon frame
---@param style string  "blizzard"|"border"|"border_inside"|"ants"|"autocast"|"pixel"
---@param color number[]  {r, g, b, a} glow color
---@param alpha number  configured opacity (0–1), applied to the proc wrapper (border and blizzard styles)
---@param thickness number  edge size in pixels (1–6); drives backdrop edge size and LCG line width / autocast scale
function glowEffect.StartProc(icon, style, color, alpha, thickness)
    local glow = getOrCreateGlow(icon)
    if style == "blizzard" then
        -- Blizzard proc art: stop the backdrop border, drive the FlipBooks.
        clearLibGlow(glow.procLib)
        if glow.proc.anim:IsPlaying() then
            glow.proc.anim:Stop()
        end
        glow.proc:Hide()
        getOrCreateProcFlipbooks(icon, glow)
        -- Tint exactly as the CDM path tints ProcStartFlipbook/ProcLoopFlipbook:
        -- desaturate first so a colored tint reads as that color, not a wash.
        local tinted = color and (color[1] ~= 1 or color[2] ~= 1 or color[3] ~= 1)
        local r, g, b = 1, 1, 1
        if tinted then r, g, b = color[1], color[2], color[3] end
        glow.procStart.Flipbook:SetDesaturated(tinted and true or false)
        glow.procStart.Flipbook:SetVertexColor(r, g, b)
        glow.procLoop.Flipbook:SetDesaturated(tinted and true or false)
        glow.procLoop.Flipbook:SetVertexColor(r, g, b)
        glow.procWrapper:SetAlpha(alpha)
        -- Idempotent: the burst or loop already running means this proc is still
        -- the same one, so don't replay the birth burst on every refresh tick.
        if not glow.procStart.anim:IsPlaying() and not glow.procLoop.anim:IsPlaying() then
            -- Sized per proc rather than at creation: icon size is a setting.
            local w, h = icon:GetSize()
            local ox, oy = w * PROC_LOOP_OVERHANG, h * PROC_LOOP_OVERHANG
            glow.procLoop:ClearAllPoints()
            private.Pixel.SetPoint(glow.procLoop, "TOPLEFT", icon, "TOPLEFT", -ox, oy)
            private.Pixel.SetPoint(glow.procLoop, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", ox, -oy)
            glow.procStart:ClearAllPoints()
            private.Pixel.SetPoint(glow.procStart, "CENTER", icon, "CENTER", 0, 0)
            private.Pixel.SetSize(glow.procStart, w * PROC_START_SCALE, h * PROC_START_SCALE)
            glow.procStart.anim:Play()
        end
        return
    end
    if LIB_STYLES[style] then
        -- LibCustomGlow style: stop the backdrop border, drive the library.
        if glow.proc.anim:IsPlaying() then
            glow.proc.anim:Stop()
        end
        glow.proc:Hide()
        applyLibGlow(glow.procLib, style, color, thickness)
        return
    end
    -- "border" / "border_inside": dynamic-color backdrop edge.
    clearLibGlow(glow.procLib)
    local f = glow.proc
    local position = style == "border_inside" and "inside" or "outside"
    -- SetBackdrop's edgeSize is raw UI units with no PixelUtil equivalent, so
    -- an unsnapped thickness renders the WHITE8x8 edge at a fractional pixel
    -- width — blurred and visibly off the configured size. Snap thickness to
    -- whole physical pixels and use the snapped value for both the anchor
    -- inset and edgeSize so the border stays crisp at any UI scale.
    local snapped = PixelUtil.GetNearestPixelSize(thickness, f:GetEffectiveScale(), 1)
    if f._procThickness ~= snapped or f._procPosition ~= position then
        f._procThickness = snapped
        f._procPosition = position
        -- "outside" anchors the frame `snapped` px beyond the icon so the
        -- inward-drawn backdrop edge lands wholly outside the icon art;
        -- "inside" anchors flush to the icon so the edge draws within it.
        local inset = position == "inside" and 0 or snapped
        f:ClearAllPoints()
        private.Pixel.SetPoint(f, "TOPLEFT", icon, "TOPLEFT", -inset, inset)
        private.Pixel.SetPoint(f, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", inset, -inset)
        f:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = snapped,
        })
    end
    f:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
    -- glow.proc's own alpha is driven by the pulse animation (0.5↔1.0); the
    -- configured opacity rides on procWrapper so the two multiply.
    glow.procWrapper:SetAlpha(alpha)
    if not f.anim:IsPlaying() then
        f.anim:Play()
    end
end

---Stop the proc glow on an icon (backdrop border, FlipBooks, and any
---LibCustomGlow effect).
---@param icon frame
function glowEffect.StopProc(icon)
    local glow = glowByIcon[icon]
    if not glow then return end
    if glow.proc.anim:IsPlaying() then
        glow.proc.anim:Stop()
    end
    glow.proc:Hide()
    clearLibGlow(glow.procLib)
    -- nil on the CDM path, where "blizzard" is Blizzard's own alert frame.
    if glow.procLoop then
        if glow.procLoop.anim:IsPlaying() then
            glow.procLoop.anim:Stop()
        end
        glow.procLoop:Hide()
        if glow.procStart.anim:IsPlaying() then
            glow.procStart.anim:Stop()
        end
        glow.procStart:Hide()
    end
end

---Stop proc glows that Blizzard no longer considers active.
---
---A proc glow's ONLY stop path is StopProc from the
---OnSpellActivationOverlayGlowHideEvent hook, and Blizzard fires that event
---exactly once per proc.  A profile switch tears down and rebuilds every AF
---instance and tracker but never touches glowByIcon, so a glow that is running
---across the rebuild is orphaned for the rest of the session: its animation
---keeps playing and nothing will ever call StopProc on it again.  Under
---hide-when-ready that reads as a border glow appearing and vanishing with the
---icon it is anchored to, and only /reload (a fresh Lua state) clears it.
---
---Reconcile rather than blindly stop, so a genuinely-running proc survives the
---switch: HasAlert is the non-secret, frame-keyed record of which frames
---Blizzard actually glowed — the same gate the proc hooks already use.  Icons
---that never started a proc glow (addon-owned trinket/consumable icons) are
---no-ops: glow.proc is already hidden and procLib is proc-only, so the pandemic
---overlays are untouched.
function glowEffect.ReconcileProcGlows()
    if not ActionButtonSpellAlertManager then return end
    for icon in pairs(glowByIcon) do
        if not ActionButtonSpellAlertManager:HasAlert(icon) then
            glowEffect.StopProc(icon)
        end
    end
end

---Stop all glow effects on an icon (flash, pulse, approaching, border, active, proc).
---@param icon frame
function glowEffect.StopAll(icon)
    local glow = glowByIcon[icon]
    if not glow then return end
    glowEffect.StopReadyFlash(icon)
    if glow.flash.anim:IsPlaying() then
        glow.flash.anim:Stop()
    end
    glow.flash:Hide()
    if glow.pulse.anim:IsPlaying() then
        glow.pulse.anim:Stop()
    end
    glow.pulse:Hide()
    if glow.approaching.anim:IsPlaying() then
        glow.approaching.anim:Stop()
    end
    glow.approaching:Hide()
    glow.approachingWrapper:Hide()
    if glow.border.anim:IsPlaying() then
        glow.border.anim:Stop()
    end
    glow.border:Hide()
    glow.borderWrapper:Hide()
    if glow.active.anim:IsPlaying() then
        glow.active.anim:Stop()
    end
    glow.active:Hide()
    -- Delegate the proc teardown rather than repeating it: StopProc also stops
    -- the "blizzard" style's procStart/procLoop FlipBooks, which this function
    -- otherwise leaves playing.
    glowEffect.StopProc(icon)
    glow.pulseExpiry = nil
end

---Returns true when the icon has had glow sub-frames created — i.e. some glow
---was started on it at least once. Lets callers skip teardown for icons that
---never glowed without reaching into module-internal state.
---@param icon frame
---@return boolean
function glowEffect.HasGlow(icon)
    return glowByIcon[icon] ~= nil
end

-- ---------------------------------------------------------------------------
-- Static edge borders (pandemic glow + active-aura glow)
-- ---------------------------------------------------------------------------
-- Both cues are drawn as four anchored edge textures directly ON the object the
-- caller already owns — for pandemic, the very Region handed to Blizzard's
-- `AddPandemicRegion`, whose shown state the engine drives and whose anchors we
-- must not rewrite afterwards.  There is no overlay frame and no animation: the
-- engine's window is binary, so a pulse in here is indistinguishable from the
-- engine toggling the cue, and `SetScript` is blocked by the button's secret
-- aspects anyway.  The style-dispatched overlay system that preceded this
-- (`CreatePandemicOverlay` and friends, driven from a `DurationObject`
-- remaining-% curve) was deleted in the same commit as this note; `cd44f22` is
-- the last commit that had a live caller for it.

-- Draw (and re-size) the pandemic border as four anchored edge textures,
-- creating them on first call. NOT a BackdropTemplate: SetBackdrop runs
-- BackdropTemplateMixin:SetupTextureCoordinates, which does `width / edgeSize`
-- on self:GetWidth() — and the pandemic host hangs off an aura button, whose
-- rect inherits the aura container's SECRET size through the anchor chain
-- (patterns-auracontainer.md "Container size is secret"). Anchored edges need
-- no width read at all. Left/right are inset vertically by `thickness` so the
-- corners are not double-drawn (visible as brighter corners at alpha < 1).
---`outset` pushes the ring outside the frame's own rect.  It is applied to the
---TEXTURES, never to the frame: a registered pandemic region must keep the
---anchors it was handed over with, so "outside the icon" cannot be expressed by
---re-anchoring the region.  Textures are not clipped to their parent (neither
---aura-button template sets `clipsChildren`), so drawing past the edge works.
---@param border frame
---@param thickness number  already pixel-snapped
---@param outset number|nil  0/nil = flush inside the rect
local function applyPandemicBorderEdges(border, thickness, outset)
    local edges = border._edges
    if not edges then
        edges = {}
        for i = 1, 4 do
            local tex = border:CreateTexture(nil, "OVERLAY")
            tex:SetColorTexture(1, 1, 1, 1)
            edges[i] = tex
        end
        border._edges = edges
    end
    local o = outset or 0
    local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", -o, o)
    top:SetPoint("TOPRIGHT", o, o)
    top:SetHeight(thickness)
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", -o, -o)
    bottom:SetPoint("BOTTOMRIGHT", o, -o)
    bottom:SetHeight(thickness)
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", -o, o - thickness)
    left:SetPoint("BOTTOMLEFT", -o, -o + thickness)
    left:SetWidth(thickness)
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", o, o - thickness)
    right:SetPoint("BOTTOMRIGHT", o, -o + thickness)
    right:SetWidth(thickness)
end

---Draw or refresh a static edge border DIRECTLY on `frame`, tracing `anchorTo`.
---
---This is the shape a native pandemic region wants.  `AddPandemicRegion` drives
---the SHOWN state of the object it is handed, so the art has to live ON that
---object: nesting it two frames deeper (host -> overlay -> border, the shape
---this replaced) puts two addon-owned shown states between the engine's
---decision and the pixels, and neither can be read back — everything in that
---subtree carries `Enum.SecretAspect.Shown`.
---
---"Off" is a transparent edge, never a Hide: once registered, a host keeps
---`SecretAspect.Shown` for good and its visibility stops being ours to set.
---@param frame frame  the registered region itself, already anchored
---@param outside boolean  true = edge outside the rect, false = within it
---@param thickness number
---@param color number[]  {r, g, b, a}
function glowEffect.ApplyEdgeBorder(frame, outside, thickness, color)
    local snapped = PixelUtil.GetNearestPixelSize(thickness,
        frame:GetEffectiveScale(), 1)
    local outset = outside and snapped or 0
    if frame._edgeThickness ~= snapped or frame._edgeOutset ~= outset then
        applyPandemicBorderEdges(frame, snapped, outset)
        frame._edgeThickness = snapped
        frame._edgeOutset = outset
    end
    local edges = frame._edges
    for i = 1, #edges do
        edges[i]:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    end
end

---Tint an active border built by `CreateActiveBorder`.
---@param border frame
---@param color number[]|nil  {r, g, b, a}; nil keeps the creation-time green
function glowEffect.ApplyActiveBorderColor(border, color)
    local c = color or COLOR_ACTIVE
    local edges = (border._border or border)._edges
    for i = 1, #edges do
        edges[i]:SetVertexColor(private.Util.Color(c))
    end
end

-- Active-aura border for an AURA BUTTON's subtree (Core/AuraContainer.lua),
-- where the ENGINE owns the shown state and we only supply the art.
--
-- Same look as `glow.active` — green square pulse, alpha 0.5<->0.9 over 1.2s —
-- rebuilt from primitives that are legal in there:
--   * four anchored edge textures, never SetBackdrop: the rect is secret and
--     BackdropTemplateMixin:SetupTextureCoordinates divides by GetWidth();
--   * the pulse is Play()ed once here and never scripted: SetScript is blocked
--     by the button's secret aspects, and hiding a frame does not pause its
--     animation, so one Play carries through every engine show/hide cycle.
-- Both rules and their live incidents: .context/patterns-auracontainer.md.
--
-- No thickness parameter on purpose — `active_glow` exposes a colour and nothing
-- else, so this follows the ordinary border edge size like `glow.active` did.
---@param parent frame  the aura button, or a region inside its subtree
---@return frame
function glowEffect.CreateActiveBorder(parent)
    local border = CreateFrame("Frame", nil, parent)
    -- Same geometry the pandemic overlay uses, deliberately: a FLUSH anchor and
    -- an explicit frame-level raise.  The first attempt outset the frame by the
    -- edge width via PixelUtil.SetPoint and left the level alone — the one
    -- recipe in this file NOT proven to render inside an aura button's
    -- secret-rect subtree, and it drew nothing.  Flush means the edges draw
    -- within the icon (the "border_inside" look) rather than around it.
    -- Built exactly like the pandemic host, which is the one construction
    -- observed to render in here: parented to the button, SetAllPoints, edge
    -- textures, nothing else.  No SetFrameLevel — the host does not set one
    -- either, and it was the last remaining difference between the two.
    border:SetAllPoints(parent)
    local snapped = PixelUtil.GetNearestPixelSize(BORDER_EDGE_SIZE,
        border:GetEffectiveScale(), 1)
    applyPandemicBorderEdges(border, snapped)
    glowEffect.ApplyActiveBorderColor(border, nil)
    border:SetAlpha(1)
    return border
end

-- CDM "Visual" alert art, rebuilt from primitives for an AURA BUTTON's subtree.
--
-- Blizzard's own alert frames (`VisualAlertsManager:AcquireAlert`) cannot be used
-- here: `SetAlertTarget` does `SetParent(target)`, which is only legal on a
-- forbidden aura button inside `initializeFrame`, and the frame it hands back is
-- pool-owned and script-driven. So the two templates are reproduced instead --
-- both public atlases, both animations spelled out in
-- `Blizzard_VisualAlerts/VisualAlertTemplates.xml`.
--
-- Two deliberate deviations from that XML, each for a reason established in this
-- file already:
--   * FLUSH `SetAllPoints`, not Blizzard's -8/+9 outset from `GetAnchors`. The
--     outset is exactly the construction that drew NOTHING inside a secret-rect
--     subtree (see `CreateActiveBorder`), so the alert is inset to the button.
--   * The animation is `Play()`ed once at creation and never scripted. `SetScript`
--     is blocked by the button's secret aspects, and hiding a frame does not pause
--     its animation, so one Play carries through every engine show/hide cycle.
--     This is what makes the glow free: the ENGINE shows the button exactly while
--     the aura is up, so it is also showing (and hiding) the alert.
--
-- Every one of the ten payloads LOOPS in Blizzard's own XML -- `REPEAT` for the
-- five MarchingAnts, `BOUNCE` for the five Flash -- so running one permanently is
-- the same animation Blizzard plays, not a degraded stand-in. The 2 s
-- `durationSeconds` on their template is only the auto-release timer in
-- `VisualAlertBaseMixin:OnUpdate`, which has no counterpart here.
--
-- MoP Classic has no `Enum.VisualAlertType` (its CDM keys visuals by the Lua
-- `CooldownViewerVisual`), and no aura buttons to draw on, so the map is empty.
---@type table<number, {shape: string, color: string}>
local CDM_ALERT_ART = Enum.VisualAlertType and {
    [Enum.VisualAlertType.MarchingAnts]     = { shape = "ants",  color = "GOLD" },
    [Enum.VisualAlertType.MarchingAntsCyan] = { shape = "ants",  color = "CYAN" },
    [Enum.VisualAlertType.MarchingAntsRed]  = { shape = "ants",  color = "RED" },
    [Enum.VisualAlertType.MarchingAntsGreen] = { shape = "ants", color = "GREEN" },
    [Enum.VisualAlertType.MarchingAntsBlue] = { shape = "ants",  color = "BLUE" },
    [Enum.VisualAlertType.Flash]            = { shape = "flash", color = "GOLD" },
    [Enum.VisualAlertType.FlashCyan]        = { shape = "flash", color = "CYAN" },
    [Enum.VisualAlertType.FlashRed]         = { shape = "flash", color = "RED" },
    [Enum.VisualAlertType.FlashGreen]       = { shape = "flash", color = "GREEN" },
    [Enum.VisualAlertType.FlashBlue]        = { shape = "flash", color = "BLUE" },
} or {}

---Blizzard's own alert geometry, identical for both shapes
---(`VisualAlertMarchingAntsBaseMixin:GetAnchors` /
---`VisualAlertFlashBaseMixin:GetAnchors`, VisualAlertTemplates.lua): the alert
---frame OVERHANGS its target rather than sitting inside it, by 8px up/left and
---9px down/right at the reference size.  A `SetAllPoints` reads as a border
---drawn fully inside the icon, which is not the look.
local ALERT_OVERHANG_LEFT, ALERT_OVERHANG_TOP = -8, 8
local ALERT_OVERHANG_RIGHT, ALERT_OVERHANG_BOTTOM = 9, -9

---The icon width those offsets are authored against
---(`VisualAlertTargetMixin:GetReferenceSize`), so scale 1 is a 32px icon.
local ALERT_REFERENCE_SIZE = 32

---Anchor one alert overlay over its button, scaling the overhang with the icon.
---
---The CDM itself never overrides `GetVisualAlertAnchorScale`, so Blizzard's own
---viewer takes the flat 8/9 at every icon size.  Ours is user-sized, which is the
---case `VisualAlertTargetMixin` documents the ratio FOR ("targets that are
---significantly larger or smaller than their alerts"), and
---`PrivateAuraMixin:GetVisualAlertAnchorScale` is its one implementation:
---`max(0.25, iconWidth / referenceSize)`.  Copied rather than invented, floor
---included.
---
---Re-anchored on every show rather than only at creation: the overlay outlives
---any number of `icon_size` edits, and the button it sits on is resized by the
---restyle pass without telling anyone.
---@param frame frame  from CreateCdmAlertGlow
---@param parent frame  the aura button
---@param iconWidth number|nil  current button width; nil = Blizzard's flat scale 1
function glowEffect.AnchorCdmAlertGlow(frame, parent, iconWidth)
    local scale = 1
    if iconWidth and iconWidth > 0 then
        scale = math.max(0.25, iconWidth / ALERT_REFERENCE_SIZE)
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT",
        ALERT_OVERHANG_LEFT * scale, ALERT_OVERHANG_TOP * scale)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT",
        ALERT_OVERHANG_RIGHT * scale, ALERT_OVERHANG_BOTTOM * scale)
end

---Shape and colour for one `Enum.VisualAlertType`, or nil for an unknown value.
---@param visualAlertType number
---@return {shape: string, color: string}|nil
function glowEffect.GetCdmAlertArt(visualAlertType)
    return CDM_ALERT_ART[visualAlertType]
end

---Build one persistent CDM visual-alert overlay in an aura button's subtree.
---@param parent frame  the aura button
---@param shape string  "ants" | "flash"
---@return frame
function glowEffect.CreateCdmAlertGlow(parent, shape)
    local f = CreateFrame("Frame", nil, parent)
    glowEffect.AnchorCdmAlertGlow(f, parent)

    local tex = f:CreateTexture(nil, "OVERLAY")
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
    tex:SetAllPoints()
    -- Assigned before the animation is built: SetChildKey resolves the region by
    -- looking this key up on the animation group's frame.
    f.Art = tex

    local ag = f:CreateAnimationGroup()
    ag:SetToFinalAlpha(true)
    if shape == "ants" then
        tex:SetAtlas("VisualAlert_Ants_Flipbook")
        ag:SetLooping("REPEAT")
        local fb = ag:CreateAnimation("FlipBook")
        fb:SetChildKey("Art")
        fb:SetDuration(1)
        fb:SetOrder(1)
        fb:SetFlipBookRows(6)
        fb:SetFlipBookColumns(5)
        fb:SetFlipBookFrames(30)
        fb:SetFlipBookFrameWidth(0)
        fb:SetFlipBookFrameHeight(0)
    else
        tex:SetAtlas("UI-CooldownManager-VisualAlert-Glow")
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        a:SetChildKey("Art")
        a:SetDuration(0.5)
        a:SetOrder(1)
        a:SetSmoothing("IN_OUT")
        a:SetFromAlpha(0.25)
        a:SetToAlpha(1)
    end
    f.anim = ag
    ag:Play()
    return f
end

---Tint one overlay from Blizzard's own `VISUAL_ALERT_COLOR_*` globals, so a
---colour change on their side follows without a table here going stale. Read by
---name rather than copied: the values are not in the extracted UI source.
---@param frame frame  from CreateCdmAlertGlow
---@param colorKey string  "GOLD"|"CYAN"|"RED"|"GREEN"|"BLUE"
function glowEffect.ApplyCdmAlertGlowColor(frame, colorKey)
    local color = _G["VISUAL_ALERT_COLOR_" .. colorKey]
    if color and color.GetRGBA then
        frame.Art:SetVertexColor(color:GetRGBA())
    end
end

private.GlowEffect = glowEffect
