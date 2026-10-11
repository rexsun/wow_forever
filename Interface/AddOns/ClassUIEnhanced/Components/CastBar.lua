
local _
---@type string, private
local _, private = ...

---@type detailsframework
local framework = _G["DetailsFramework"]

---@class private : table
---@field CastBar castbar_shared

---Shared module that creates and manages cast bar frames for all units.
---Not a component itself; used by PlayerCastBar, TargetCastBar, and FocusCastBar.
---@class castbar_shared : table
---@field CreateCastBar fun(unitId: unit, parent:frame, name:string, settingsOverride:table?) : _castbar Creates the cast bar frame
---@field CreateOverlayBar fun(parent:frame, name:string, settingsOverride:table?) : _castbar Creates a cast bar with no unit binding (no events, no DF state machine) — used for synthetic overlays driven entirely by the caller.
---@field GetCastBar fun(unitId: unit): _castbar Gets the cast bar object for the specified unit
---@field HideForUnit fun(unitId: unit) Hides the cast bar for the specified unit
---@field EnableTalentTracking fun() Registers PLAYER_TALENT_UPDATE to keep tick marks up to date
---@field DisableTalentTracking fun() Unregisters PLAYER_TALENT_UPDATE
---@field EnableEvokerTickCalibration fun() Registers haste-shift events so the Evoker baseline cache stays in sync
---@field DisableEvokerTickCalibration fun() Unregisters haste-shift events and clears the baseline cache
---@field UpdateTicksTable fun() Rebuilds tick mark lookup tables from current talent state
---@field ApplyTexture fun(bar:_castbar, texture:string) Applies the profile texture to a cast bar via LSM lookup or atlas fallback
---@field getTicksForSpell fun(spell:any): number
---@field createTickSparks fun(unitCastBar:_castbar)
---@field UpdateCastTicks fun(unitCastBar:_castbar, keepInterval:boolean?)
---@field UpdateCastTicksEvoker fun(unitCastBar:_castbar)
---@field UpdateCastTicksEvent fun(self:_castbar, unit:unit, event:string)
---@field ShowPushbackCutaway fun(bar:_castbar, low:number, high:number) Draws the progress a pushback took, then fades it
---@field LostSpan fun(isChannel:boolean, startMs:number, oldEndMs:number, newEndMs:number, nowMs:number): number?, number? Fill fractions a pushback took away
---@field CastInfoDuration fun(bar:_castbar): table?, number?, number?, any Duration spanning the bar's cast from UnitCastingInfo / UnitChannelInfo, its start/end in ms and a cast key; nil when unreadable
---@field ApplyFonts fun(bar:_castbar, settings:castbar_component_profile_main) Applies font settings to a cast bar's text elements
---@field FormatCastTime fun(style:string?, remaining:number, total:number): string Formats the cast time text per cast_time_style
---@field DefaultCreateSettings table Default DetailsFramework settings shared by all cast bar CreateCastBar calls
---@field CreateCastBarComponent fun(unitId: unitcastbar, componentName: string, unitChangedEvent: string?): component Creates a standard cast bar component for a unit with no special logic
---
---Texture API: CreateCastBar mixes CastFrameFunctions + StatusBarFunctions (mixins.lua:766).
---  bar:SetTexture(path), bar:SetAtlas(name). ApplyTexture uses LSM lookup → SetTexture,
---  fallback → barTexture:SetColorTexture(1,1,1,1).

---@alias unitcastbar
---| "player"
---| "target"
---| "focus"

local validUnitCastBars = {
    ["player"] = true,
    ["target"] = true,
    ["focus"] = true,
}

---ensure cached player class for ticks
local playerClass = select(2, UnitClass("player"))

---make a castbar object which inherits from the framework castbar
---@class _castbar : df_castbar

---store created cast bars here
---@type table<unitcastbar, _castbar>
local castBarObjects = {}

---@type castbar_shared
---@diagnostic disable-next-line: missing-fields
local castBar = {}

-- Forward declarations for Mass Disintegrate tracking (defined after tick tables)
local massDisWatcher
local massDisCharges = 0

-- Evoker tick calibration state. UnitSpellHaste is a secret in 12.0+, so the
-- unclipped tick interval has to be observed rather than computed. At each
-- non-clip UNIT_SPELLCAST_CHANNEL_START we record the reported channel
-- duration per spellID; clipped channels use it to keep tick marks aligned
-- to the real firing rhythm even when the server reports an extended
-- duration for the remainder of the prior tick. Wiped whenever player haste
-- can shift (talent/spec/gear change).
local evokerBaselineDuration = {}
local evokerLastChannelEndsAt = 0

local castBarEventCallbackFrame = CreateFrame("frame")
castBarEventCallbackFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TALENT_UPDATE" then
        castBar.UpdateTicksTable()
    end
    -- Any haste-affecting event invalidates the baseline cache; next unclipped
    -- channel reseeds it. PLAYER_TALENT_UPDATE is also a haste-shift trigger
    -- (Evoker tick-rate talents) so it shares the wipe.
    evokerBaselineDuration = {}
    evokerLastChannelEndsAt = 0
end)

---Get a cast bar object for the specified unit
---Example: local playerCastBar = castBar.GetCastBar("player")
---@param unitId unit
---@return _castbar
castBar.GetCastBar = function(unitId)
    --avoid typos while calling the function
    assert(type(unitId) == "string", "GetCastBar() unitId must be a string")
    assert(validUnitCastBars[unitId], "GetCastBar() invalid unitId: " .. tostring(unitId))

    return castBarObjects[unitId]
end

-- ── Cast text tracing (/cue debugcast) ──────────────────────────────────────
-- The cast time text is written only by DF's OnTick_LazyTick
-- (unitframe_midnight.lua:1429), which needs Settings.CanTick (installs the
-- OnUpdate), Settings.CanLazyTick and Settings.ShowCastTime all true, and reads
-- durationObject:GetRemainingDuration() — a secret whenever the bar holds DF's
-- getter object (the #50 shim binds a plain span only when cast info is
-- readable). Off by default;
-- when off each wrapper costs one boolean check (per lazy tick, and per frame
-- for the OnTick_Casting / OnTick_Channeling wraps).
local castTextTracing = false
local traceUnitOrder = {"player", "target", "focus"}
local castBarComponentNames = {
    player = "PlayerCastBar",
    target = "TargetCastBar",
    focus = "FocusCastBar",
}

---Render a durationObject duration for the log. GetRemainingDuration and
---GetTotalDuration return secrets in combat, which cannot be tostring()'d.
---@param durationObject any
---@param method string "GetRemainingDuration" | "GetTotalDuration"
---@return string
local function describeDuration(durationObject, method)
    if not durationObject then return "<no durationObject>" end
    local value = durationObject[method](durationObject)
    if issecretvalue(value) then return "<secret>" end
    if value == nil then return "<nil>" end
    return string.format("%.2f", value)
end

---Render a FontString's text for the log. GetText() returns a secret after a
---secret SetText() — see patterns-secrets.md.
---@param fontString fontstring
---@return string
local function describeFontStringText(fontString)
    local text = fontString:GetText()
    if issecretvalue(text) then return "<secret>" end
    if text == nil then return "<nil>" end
    if text == "" then return "<empty>" end
    return text
end

---Render a plain value for the log. self.value / self.maxValue are absolute
---millisecond timestamps (cast start and cast end) and can be secret.
---@param value any
---@return string
local function describeValue(value)
    if issecretvalue(value) then return "<secret>" end
    if value == nil then return "<nil>" end
    if type(value) == "number" then return string.format("%.1f", value) end
    return tostring(value)
end

---Wrap a bar's lazy tick and hook its cast start so the trace can report the
---whole gate chain. Mixin copies CastFrameFunctions onto each bar table
---(unitframe_midnight.lua:2267), so the wrap is instance-local and never
---touches the shared framework mixin.
---@param bar _castbar
local function installCastTextTrace(bar)
    -- Counts every lazy tick since the bar was created. The diagnostic case is
    -- a lazy tick that never runs at all: DF's OnTick (unitframe_midnight.lua:1470)
    -- reaches it only if OnTick_Casting / OnTick_Channeling survives
    -- CheckCastIsDone (line 1219). Its `self.value >= self.maxValue` test compares
    -- the cast's start and end timestamps -- DF no longer updates self.value per
    -- tick under 12.0 (the fill is native, from SetTimerDuration), so on a healthy
    -- bar it stays start-vs-end and never trips; UNIT_SPELLCAST_STOP ends the cast
    -- instead. Degenerate values (equal, zeroed, or a maxValue left over from a
    -- previous cast) declare it finished every tick and the text is never written.
    local lazyTickCount = 0

    ---Wrap one of DF's per-phase tick functions, logging the values
    ---CheckCastIsDone compares. Must return DF's result unchanged — a false
    ---return is what tells OnTick the cast is over.
    ---@param methodName string "OnTick_Casting" | "OnTick_Channeling"
    ---@param phase string label for the log line
    local function wrapTickPhase(methodName, phase)
        local dfTick = bar[methodName]
        local lastAlive, lastPrint = nil, 0
        bar[methodName] = function(self, ...)
            if not castTextTracing then return dfTick(self, ...) end
            -- Sample before the call: CheckCastIsDone fires UNIT_SPELLCAST_STOP
            -- on the way out, which clears the state we want to see.
            local value, maxValue = describeValue(self.value), describeValue(self.maxValue)
            local alive = dfTick(self, ...)
            -- Runs every frame. Log an alive transition immediately, otherwise
            -- at most twice a second.
            local now = GetTime()
            local aliveKey = tostring(alive)
            if aliveKey == lastAlive and now - lastPrint < 0.5 then return alive end
            lastAlive, lastPrint = aliveKey, now
            private.printdebug("castdebug " .. phase, self:GetName(),
                "value", value, "maxValue", maxValue,
                "alive", aliveKey,
                "lazyTicks", tostring(lazyTickCount),
                "casting", tostring(self.casting),
                "channeling", tostring(self.channeling),
                "finished", tostring(self.finished))
            return alive
        end
    end

    wrapTickPhase("OnTick_Casting", "TickCasting")
    wrapTickPhase("OnTick_Channeling", "TickChanneling")

    local dfLazyTick = bar.OnTick_LazyTick
    local lastKey, lastPrint = nil, 0
    bar.OnTick_LazyTick = function(self, ...)
        lazyTickCount = lazyTickCount + 1
        if not castTextTracing then return dfLazyTick(self, ...) end
        local result = dfLazyTick(self, ...)
        local settings = self.Settings
        local key = table.concat({
            tostring(self.casting), tostring(self.channeling),
            tostring(settings.CanTick), tostring(settings.CanLazyTick),
            tostring(settings.ShowCastTime),
            tostring(self.percentText:IsShown()),
            string.format("%.2f", self.percentText:GetAlpha()),
        }, "/")
        -- The lazy tick fires every LazyUpdateCooldown (0.1s). Log every gate
        -- change immediately, otherwise at most twice a second so the duration
        -- progression stays visible without flooding the ring buffer.
        local now = GetTime()
        if key == lastKey and now - lastPrint < 0.5 then return result end
        lastKey, lastPrint = key, now
        private.printdebug("castdebug LazyTick", self:GetName(),
            "casting/channeling/CanTick/CanLazyTick/ShowCastTime/shown/alpha", key,
            "remaining", describeDuration(self.durationObject, "GetRemainingDuration"),
            "text", describeFontStringText(self.percentText))
        return result
    end

    -- Returns nothing: a truthy hook return interrupts the remaining hooks
    -- (ScriptHookMixin.RunHooksForWidget, mixins.lua:386).
    bar:SetHook("OnCastStart", function(self, unit, event)
        if not castTextTracing then return end
        local settings = self.Settings
        local fontPath, fontSize = self.percentText:GetFont()
        local parent = self.percentText:GetParent()
        private.printdebug("castdebug CastStart", self:GetName(), tostring(event),
            "ShowCastTime", tostring(settings.ShowCastTime),
            "CanLazyTick", tostring(settings.CanLazyTick),
            "CanTick", tostring(settings.CanTick),
            "total", describeDuration(self.durationObject, "GetTotalDuration"),
            "shown", tostring(self.percentText:IsShown()),
            "alpha", string.format("%.2f", self.percentText:GetAlpha()),
            "font", tostring(fontPath), tostring(fontSize),
            "parent", parent and parent:GetName() or "<unnamed>")
    end)

    -- Pushback trace: UNIT_SPELLCAST_DELAYED (unitframe_midnight.lua:2136)
    -- re-binds SetTimerDuration, and UNIT_SPELLCAST_CHANNEL_UPDATE (:2154)
    -- delegates to UpdateChannelInfo, which does the same. Both binds pass the
    -- shim in setupCastBarStyling, which swaps in the cast-info span (#50), so
    -- the after-sample shows what the bar is really filling from.
    -- Instance-local, like the tick wraps above.
    ---Wrap one of DF's two pushback handlers and log the state it rewrites,
    ---sampled both before and after DF runs: the diagnostic case is a handler
    ---that runs but moves nothing, which only a before/after pair shows.
    ---@param methodName string "UNIT_SPELLCAST_DELAYED" | "UNIT_SPELLCAST_CHANNEL_UPDATE"
    local function wrapPushback(methodName)
        local dfHandler = bar[methodName]
        if not dfHandler then return end
        bar[methodName] = function(self, unit, ...)
            -- DF discards the handler's return (unitframe_midnight.lua:1424), so
            -- the wrap does not have to forward one.
            if not castTextTracing or not unit then return dfHandler(self, unit, ...) end
            local beforeMax = describeValue(self.maxValue)
            local beforeEnd = describeValue(self.spellEndTime)
            local beforeRemaining = describeDuration(self.durationObject, "GetRemainingDuration")
            -- D1 tell: DF's IsValid (:1185) rejects a bar that is not shown, and
            -- UNIT_SPELLCAST_DELAYED (:2140) does not pass ignoreVisibility.
            local shown = tostring(self:IsShown())
            -- The D2 tell is logged by the SetTimerDuration guard itself
            -- (a "NilDuration" line), not sampled a second time here — that
            -- would re-call a getter DF has already called this dispatch.
            -- delayTimeMs, the cumulative pushback in ms. Cast-only (UnitChannelInfo
            -- has no equivalent) and it may simply not exist on an older client,
            -- in which case this reads <nil>.
            local delay = describeValue(select(11, UnitCastingInfo(unit)))
            dfHandler(self, unit, ...)
            private.printdebug("castdebug Pushback", self:GetName(), methodName,
                "casting", tostring(self.casting),
                "channeling", tostring(self.channeling),
                "empowered", tostring(self.empowered),
                "castBarID", tostring(self.castBarID),
                "shown", shown,
                "delayTimeMs", delay,
                "maxValue", beforeMax .. " -> " .. describeValue(self.maxValue),
                "spellEndTime", beforeEnd .. " -> " .. describeValue(self.spellEndTime),
                "remaining", beforeRemaining .. " -> "
                    .. describeDuration(self.durationObject, "GetRemainingDuration"),
                -- What the engine is actually filling from. Differs from
                -- `remaining` only when the binding is stale.
                "bound", describeDuration(self:GetTimerDuration(), "GetRemainingDuration"))
        end
    end

    wrapPushback("UNIT_SPELLCAST_DELAYED")
    wrapPushback("UNIT_SPELLCAST_CHANNEL_UPDATE")
end

---Write a one-shot snapshot of every cast bar's text state to the debug log.
local function dumpCastTextState()
    for _, unitId in ipairs(traceUnitOrder) do
        local componentName = castBarComponentNames[unitId]
        local settings = private.profile.components[componentName]
        private.printdebug("castdebug profile", componentName,
            "cast_text_format", tostring(settings and settings.cast_text_format),
            "enabled", tostring(settings and settings.enabled))

        local bar = castBarObjects[unitId]
        if not bar then
            private.printdebug("castdebug bar", unitId, "<not created>")
        else
            local dfSettings = bar.Settings
            local fontPath, fontSize = bar.percentText:GetFont()
            local parent = bar.percentText:GetParent()
            private.printdebug("castdebug bar", bar:GetName(),
                "ShowCastTime", tostring(dfSettings.ShowCastTime),
                "CanLazyTick", tostring(dfSettings.CanLazyTick),
                "CanTick", tostring(dfSettings.CanTick),
                "LazyUpdateCooldown", tostring(dfSettings.LazyUpdateCooldown),
                "hasOnUpdate", tostring(bar:GetScript("OnUpdate") ~= nil),
                "value", describeValue(bar.value),
                "maxValue", describeValue(bar.maxValue),
                "finished", tostring(bar.finished),
                "barShown", tostring(bar:IsShown()),
                "textShown", tostring(bar.percentText:IsShown()),
                "textAlpha", string.format("%.2f", bar.percentText:GetAlpha()),
                "font", tostring(fontPath), tostring(fontSize),
                "parent", parent and parent:GetName() or "<unnamed>",
                "text", describeFontStringText(bar.percentText))
        end
    end
end

---Format the cast bar time text according to the profile's cast_time_style.
---@param style string|nil "remaining" (default) | "elapsed_total" | "remaining_total"
---@param remaining number seconds left on the cast
---@param total number total cast duration in seconds
---@return string
castBar.FormatCastTime = function(style, remaining, total)
    -- The totals come from UnitCastingInfo and the remaining from the duration
    -- object; either can be secret in combat, and arithmetic over a secret
    -- throws. Fall back to DF's plain remaining-only text in that case.
    if (style == "elapsed_total" or style == "remaining_total")
        and not issecretvalue(remaining) and not issecretvalue(total) and total > 0 then
        local shown = remaining
        if style == "elapsed_total" then
            shown = math.max(0, total - remaining)
        end
        return format("%.1f / %.1f", shown, total)
    end
    return format("%.1f", remaining)
end

-- ── Cast pushback cutaway ───────────────────────────────────────────────────
-- Declared above setupCastBarStyling because its hooks and its SetTimerDuration
-- shim read them: Lua 5.1 captures locals at definition time, so a local
-- declared further down the file compiles to a GETGLOBAL there and reads nil
-- forever with no error (patterns.md, "Lua 5.1 upvalue safety").
--
-- On a pushback the fill drops back at once, and the progress it lost stays
-- drawn as a solid chunk that holds, then fades. It replaced a white ADD flash
-- over the whole bar that the user found too faint over a bright fill (#50).
-- CUE owns the texture rather than reusing DF's castBar.flashTexture
-- (unitframe_midnight.lua:2252), which DF plays on finish and interrupt and
-- hides on every (re-)setup.
local CUTAWAY_COLOR = {1, 0.25, 0.25}
local CUTAWAY_HOLD = 0.15
local CUTAWAY_FADE = 0.4

---Create or retrieve the cutaway texture on a cast bar. Drawn at ARTWORK
---sublevel 2: above DF's fill (ARTWORK -6) and the latency overlay (ARTWORK
---1), below everything DF puts in OVERLAY — spell name (1), spark (3), icon
---(4), time text (7), finish flash (7) — so a solid block never hides text.
---Solid colour at full alpha, normal blending: it has to read over the dark
---background it mostly sits on.
---@param bar _castbar
---@return texture
local function getOrCreateCutaway(bar)
    if bar.cueCutaway then return bar.cueCutaway end

    local cutaway = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    cutaway:SetColorTexture(CUTAWAY_COLOR[1], CUTAWAY_COLOR[2], CUTAWAY_COLOR[3], 1)
    cutaway:Hide()

    local ag = cutaway:CreateAnimationGroup()
    local fade = ag:CreateAnimation("Alpha")
    fade:SetStartDelay(CUTAWAY_HOLD)
    fade:SetDuration(CUTAWAY_FADE)
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    ag:SetScript("OnStop", function() cutaway:Hide() end)
    ag:SetScript("OnFinished", function() cutaway:Hide() end)

    bar.cueCutaway = cutaway
    bar.cueCutawayAnim = ag
    return cutaway
end

---Stop the cutaway and hide it. No-op before the first one: the texture is
---created lazily, so a bar that is never pushed back (and the unbound
---instant-cast overlay) never allocates one.
---@param bar _castbar
local function stopPushbackCutaway(bar)
    local ag = bar.cueCutawayAnim
    if not ag then return end
    if ag:IsPlaying() then
        ag:Stop()
    end
    bar.cueCutaway:Hide()
end

---The part of the bar a pushback took away, as fill fractions (low, high), or
---nil when it took none. All times in ms on the GetTime() clock.
---Each fill is measured against its OWN span: WoW Forever does not stretch a
---pushed-back cast, it shifts the whole window, start and end both by
---delayTimeMs (in-client /cue debugcast log, 2026-09-27), so the old fill
---measured from the new start comes out a sliver, or nothing at all when the
---new start is already past now.
---A cast fills toward its end (ElapsedTime), a channel drains toward it
---(RemainingTime). A fill that did not drop lost nothing: nil, which is also
---what keeps a channel extended for another reason from drawing one.
---@param isChannel boolean
---@param oldStartMs number
---@param oldEndMs number
---@param newStartMs number
---@param newEndMs number
---@param nowMs number
---@return number? low
---@return number? high
castBar.LostSpan = function(isChannel, oldStartMs, oldEndMs, newStartMs, newEndMs, nowMs)
    if oldEndMs <= oldStartMs or newEndMs <= newStartMs then return end
    local oldFrac, newFrac
    if isChannel then
        oldFrac = (oldEndMs - nowMs) / (oldEndMs - oldStartMs)
        newFrac = (newEndMs - nowMs) / (newEndMs - newStartMs)
    else
        oldFrac = (nowMs - oldStartMs) / (oldEndMs - oldStartMs)
        newFrac = (nowMs - newStartMs) / (newEndMs - newStartMs)
    end
    oldFrac = math.min(math.max(oldFrac, 0), 1)
    newFrac = math.min(math.max(newFrac, 0), 1)
    -- Under half a percent of the bar is not visible at any bar width.
    if oldFrac - newFrac < 0.005 then return end
    return newFrac, oldFrac
end

---Draw the cutaway over [low, high] of the fill and start its hold-and-fade,
---replacing one still showing so each pushback shows its own loss.
---@param bar _castbar
---@param low number fill fraction the bar dropped back to
---@param high number fill fraction it was at
castBar.ShowPushbackCutaway = function(bar, low, high)
    local cutaway = getOrCreateCutaway(bar)
    local ag = bar.cueCutawayAnim
    if ag:IsPlaying() then
        ag:Stop()
    end
    cutaway:ClearAllPoints()
    -- The fill grows from the left, or from the bottom on a vertical bar.
    if bar.cueOrientation == "vertical" then
        local h = bar:GetHeight()
        private.Pixel.SetPoint(cutaway, "BOTTOMLEFT", bar, "BOTTOMLEFT", 0, h * low)
        private.Pixel.SetPoint(cutaway, "TOPRIGHT", bar, "BOTTOMRIGHT", 0, h * high)
    else
        local w = bar:GetWidth()
        private.Pixel.SetPoint(cutaway, "TOPLEFT", bar, "TOPLEFT", w * low, 0)
        private.Pixel.SetPoint(cutaway, "BOTTOMRIGHT", bar, "BOTTOMLEFT", w * high, 0)
    end
    cutaway:Show()
    ag:Play()
end

---Apply the addon's container/layout/hooks to a freshly created framework cast bar.
---Shared between CreateCastBar (unit-bound) and CreateOverlayBar (unbound).
---@param newCastBar _castbar
---@param containerFrame frame
local function setupCastBarStyling(newCastBar, containerFrame)
    -- Stored orientation for layout and spark hook decisions.
    -- Set by component Refresh before calling updateLayout().
    newCastBar.cueOrientation = "horizontal"

    -- Replaces DF's OnTick_LazyTick (unitframe_midnight.lua:1429), which hardcodes
    -- the remaining duration, so the text can also show it against the total cast
    -- time. Own frame, own method table — no Blizzard function is overridden.
    newCastBar.OnTick_LazyTick = function(self)
        if not self.Settings.CanLazyTick then return false end
        if self.Settings.ShowCastTime then
            -- durationObject is nil when DF's duration getter returned nothing:
            -- DF stores it before calling SetTimerDuration, whose guard below
            -- only skips the binding.
            if (self.casting or self.channeling) and self.durationObject then
                local startMs, endMs = self.spellStartTime, self.spellEndTime
                local total = 0
                if not issecretvalue(startMs) and not issecretvalue(endMs) then
                    total = ((endMs or 0) - (startMs or 0)) / 1000
                end
                self.percentText:SetText(castBar.FormatCastTime(
                    self.cueTimeStyle, self.durationObject:GetRemainingDuration(), total))
            else
                self.percentText:SetText("")
            end
        end
        return true
    end

    -- repositions the status bar and icon inside the container depending on
    -- icon visibility and the current orientation.
    local function updateBarLayout()
        local isVertical = newCastBar.cueOrientation == "vertical"
        newCastBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")

        -- Use SetAlpha(0) for icon suppression — the framework explicitly
        -- calls Icon:Show() on every new cast, so Hide() doesn't persist.
        -- SetAlpha is never touched by the framework.
        if newCastBar.cueShowIcon then
            newCastBar.Icon:SetAlpha(1)
        else
            newCastBar.Icon:SetAlpha(0)
        end

        -- Shield texture, size and position — visibility is managed by DF's
        -- UpdateInterruptState via Settings.ShowShield + notInterruptible.
        newCastBar.BorderShield:SetTexture([[Interface\GROUPFRAME\UI-GROUP-MAINTANKICON]])
        newCastBar.BorderShield:SetTexCoord(0, 1, 0, 1)
        newCastBar.BorderShield:SetDesaturated(true)
        local baseW, baseH = 10, 12
        local shieldScale = newCastBar.cueShieldScale or 1.0
        newCastBar.BorderShield:SetSize(baseW * shieldScale, baseH * shieldScale)
        newCastBar.BorderShield:ClearAllPoints()
        newCastBar.BorderShield:SetPoint("CENTER", newCastBar, "LEFT", newCastBar.cueShieldOffsetX or 0, newCastBar.cueShieldOffsetY or 0)

        newCastBar.Icon:ClearAllPoints()
        newCastBar:ClearAllPoints()

        -- Spark visibility & sizing (follows DF timebar pattern: barHeight + 26)
        -- Use Hide/Show instead of SetAlpha — the Spark's ADD blend mode
        -- doesn't fully respect alpha(0). The hooksecurefunc on Spark:Show
        -- re-hides it whenever DF tries to show it while the option is off.
        if newCastBar.cueShowSpark == false then
            newCastBar.Spark:Hide()
        else
            newCastBar.Spark:Show()
        end
        local sparkW = newCastBar.Settings.SparkWidth or 16
        local containerH = isVertical and containerFrame:GetWidth() or containerFrame:GetHeight()
        local sparkH = containerH + 26
        if isVertical then
            newCastBar.Spark:SetSize(sparkH, sparkW)
        else
            newCastBar.Spark:SetSize(sparkW, sparkH)
        end

        if isVertical then
            -- Icon at bottom of container, square (width of container)
            local iconSize = containerFrame:GetWidth()
            newCastBar.Icon:SetSize(iconSize, iconSize)
            newCastBar.Icon:SetTexCoord(private.Util.GetIconZoomCoords())
            newCastBar.Icon:SetPoint("BOTTOMLEFT", containerFrame, "BOTTOMLEFT")
            newCastBar.Icon:SetPoint("BOTTOMRIGHT", containerFrame, "BOTTOMRIGHT")

            if newCastBar.cueShowIcon then
                newCastBar:SetPoint("BOTTOMLEFT", newCastBar.Icon, "TOPLEFT")
                newCastBar:SetPoint("TOPRIGHT", containerFrame, "TOPRIGHT")
            else
                newCastBar:SetAllPoints(containerFrame)
            end
        else
            -- Icon on left side of container, square (height of container)
            local iconSize = containerFrame:GetHeight()
            newCastBar.Icon:SetSize(iconSize, iconSize)
            newCastBar.Icon:SetTexCoord(private.Util.GetIconZoomCoords())
            newCastBar.Icon:SetPoint("TOPLEFT", containerFrame, "TOPLEFT")
            newCastBar.Icon:SetPoint("BOTTOMLEFT", containerFrame, "BOTTOMLEFT")

            if newCastBar.cueShowIcon then
                newCastBar:SetPoint("TOPLEFT", newCastBar.Icon, "TOPRIGHT")
                newCastBar:SetPoint("BOTTOMRIGHT", containerFrame, "BOTTOMRIGHT")
            else
                newCastBar:SetAllPoints(containerFrame)
            end
        end
    end

    -- Hook DF Spark:SetPoint — DF always anchors to barTexture "RIGHT" which
    -- only tracks fill in horizontal mode. For vertical, translate to "TOP".
    local sparkGuard = false
    hooksecurefunc(newCastBar.Spark, "SetPoint", function(self, point, relativeTo, relativePoint, xOfs, yOfs)
        if sparkGuard then return end
        if newCastBar.cueOrientation ~= "vertical" then return end
        if relativeTo == newCastBar.barTexture and relativePoint == "RIGHT" then
            sparkGuard = true
            self:ClearAllPoints()
            self:SetPoint("CENTER", newCastBar.barTexture, "TOP", 0, xOfs or 0)
            sparkGuard = false
        end
    end)

    -- Hook DF Spark:Show — DF calls Show() on every cast start; suppress it
    -- when the user has disabled the spark option.
    hooksecurefunc(newCastBar.Spark, "Show", function(self)
        if newCastBar.cueShowSpark == false then
            self:Hide()
        end
    end)

    -- Hook DF's empowered stage pip positioning — hardcoded horizontal in
    -- unitframe_midnight.lua. After DF places pips and zones, reposition for vertical.
    hooksecurefunc(newCastBar, "CreateOrUpdateEmpoweredPips", function(self)
        if self.cueOrientation ~= "vertical" then return end
        local barWidth = self:GetWidth()
        local barHeight = self:GetHeight()
        -- DF calculated offsets using GetWidth() (the narrow axis in vertical mode).
        -- Scale each offset by height/width to map onto the tall axis.
        local scale = barWidth > 0 and (barHeight / barWidth) or 1
        -- Reposition pips: swap from vertical lines (2×h) at x-offset from LEFT
        -- to horizontal lines (w×2) at y-offset from BOTTOM
        if self.stagePips then
            for _, pip in pairs(self.stagePips) do
                if pip:IsShown() then
                    local _, _, _, xOfs = pip:GetPoint(1)
                    local yOfs = (xOfs or 0) * scale
                    pip:ClearAllPoints()
                    private.Pixel.SetSize(pip, barWidth, 2)
                    pip:SetPoint("LEFT", self, "BOTTOMLEFT", 0, yOfs)
                    pip:SetPoint("RIGHT", self, "BOTTOMRIGHT", 0, yOfs)
                end
            end
        end
        -- Reposition stage zones: vertical spans between pips
        if self.stagePipZones and self.stagePips then
            local numStages = self.numStages or 0
            for i = 1, numStages do
                local zone = self.stagePipZones[i]
                local curPip = self.stagePips[i]
                local nextPip = self.stagePips[i + 1]
                if zone and zone:IsShown() and curPip then
                    zone:ClearAllPoints()
                    zone:SetPoint("BOTTOMLEFT", curPip, "LEFT")
                    if nextPip and nextPip:IsShown() then
                        zone:SetPoint("TOPRIGHT", nextPip, "RIGHT", 0, 0)
                    else
                        zone:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
                    end
                end
            end
        end
    end)

    -- OnShow fires when the bar becomes visible during a cast; Icon:IsShown() is
    -- already true at this point (set in UpdateCastingInfo/UpdateChannelInfo before Show)
    newCastBar:SetHook("OnShow", updateBarLayout)

    -- OnCastStart fires after Icon:Show() on every new cast/channel. For
    -- back-to-back casts where OnShow doesn't re-fire (bar never hid),
    -- re-apply icon alpha suppression so the icon stays hidden.
    newCastBar:SetHook("OnCastStart", function()
        newCastBar.Icon:SetAlpha(newCastBar.cueShowIcon and 1 or 0)
        if newCastBar.cueShowSpark == false then
            newCastBar.Spark:Hide()
        else
            newCastBar.Spark:Show()
        end
        -- A new cast must not inherit the previous cast's pushback cutaway. DF
        -- does not re-Hide the bar between chained casts, so the OnHide
        -- teardown below is not guaranteed to run.
        stopPushbackCutaway(newCastBar)
    end)

    -- DF's OnHide does not call RunHooksForWidget, so SetHook would never fire.
    newCastBar:HookScript("OnHide", function()
        stopPushbackCutaway(newCastBar)
    end)

    -- All three duration getters DF feeds into SetTimerDuration are
    -- MayReturnNothing — UnitCastingDuration (UnitDocumentation.lua:811),
    -- UnitChannelDuration and UnitEmpoweredChannelDuration — while the setter's
    -- duration argument is Nilable = false. DF hands each straight across, at
    -- all three live call sites (unitframe_midnight.lua:1650 cast start, :1868
    -- channel/empower, :2151 pushback; :2175 sits below CHANNEL_UPDATE's
    -- `if true then return end` at :2156 and never runs), so an empty return
    -- throws inside DF's eventFunc before RunHooksForWidget (:1424/:1425), taking this dispatch's
    -- CUE OnEvent hooks (tick marks, the latency-marker re-derive) with it.
    --
    -- Guarding the setter rather than the handlers covers cast, channel and
    -- empower from one place, re-calls no duration getter, and
    -- lets DF finish writing spellStartTime/spellEndTime/maxValue — only the
    -- engine binding is skipped. SetTimerDuration is the raw widget method
    -- (nothing in DF defines one), so the instance field shadows the metatable
    -- lookup for this bar alone.
    --
    -- The same single entry point is where the fill is corrected (#50): every
    -- DF bind — cast start, pushback, channel update, and the
    -- PLAYER_ENTERING_WORLD re-read Refresh runs mid-cast — gets the cast-info
    -- span instead of DF's getter object whenever that info is readable. One
    -- writer, so no hook ordering can undo it. DF sets casting / channeling
    -- before each of its calls (:1627, :1845). With the span bound, an empty
    -- getter on the player bar no longer reaches the NilDuration line below.
    --
    -- It is also the one place that sees both the span a bar had and the span
    -- it gets, so the pushback cutaway is decided here: same cast, and its end
    -- moved the way that loses progress (castBar.LostSpan).
    local dfSetTimerDuration = newCastBar.SetTimerDuration
    newCastBar.SetTimerDuration = function(self, duration, interpolation, direction)
        local fromInfo, startMs, endMs, castKey = castBar.CastInfoDuration(self)
        if fromInfo then
            local sameCast = castKey ~= nil and castKey == self.cueSpanKey
            local enabled, low, high
            if sameCast then
                local componentName = castBarComponentNames[self.unit]
                local settings = componentName and private.profile.components[componentName]
                enabled = settings and settings.pushback_flash
                if enabled then
                    low, high = castBar.LostSpan(self.channeling, self.cueSpanStart,
                        self.cueSpanEnd, startMs, endMs, GetTime() * 1000)
                    if low then
                        castBar.ShowPushbackCutaway(self, low, high)
                        -- The fill drops at once; the cutaway is the transition.
                        interpolation = Enum.StatusBarInterpolation.Immediate
                    end
                end
            end
            if castTextTracing then
                -- Every input the cutaway decision reads, so a pushback that
                -- draws nothing shows which condition failed.
                private.printdebug("castdebug Cutaway", self:GetName(),
                    self.channeling and "channel" or "cast",
                    "sameCast", tostring(sameCast),
                    "start", tostring(self.cueSpanStart) .. " -> " .. tostring(startMs),
                    "end", tostring(self.cueSpanEnd) .. " -> " .. tostring(endMs),
                    "now", string.format("%.0f", GetTime() * 1000),
                    "enabled", tostring(enabled),
                    "lost", low and string.format("%.3f..%.3f", low, high) or "none")
            end
            self.cueSpanKey, self.cueSpanStart, self.cueSpanEnd = castKey, startMs, endMs
            -- DF stored its own object just before calling; the time text,
            -- the tick marks and DF's stop handlers read this field.
            self.durationObject = fromInfo
            return dfSetTimerDuration(self, fromInfo, interpolation, direction)
        end
        self.cueSpanKey, self.cueSpanStart, self.cueSpanEnd = nil, nil, nil
        -- A DurationObject is an opaque handle, not a secret (patterns-secrets.md),
        -- so a nil test touches nothing secret.
        if not duration then
            if castTextTracing then
                private.printdebug("castdebug NilDuration", self:GetName())
            end
            return
        end
        return dfSetTimerDuration(self, duration, interpolation, direction)
    end

    installCastTextTrace(newCastBar)

    newCastBar.containerFrame = containerFrame
    newCastBar.updateLayout = updateBarLayout

    newCastBar:SetHook("OnEvent", castBar.UpdateCastTicksEvent)

    castBar.createTickSparks(newCastBar)
end

---Create a cast bar for the specified unit.
---Settings override is an optional table to override default settings, default settings is found in the 'detailsFramework.CastFrameFunctions'
castBar.CreateCastBar = function(unitId, parent, name, settingsOverride)
    assert(validUnitCastBars[unitId], "CreateCastBar() invalid unitId: " .. tostring(unitId))
    if castBar.GetCastBar(unitId) then
        error("CreateCastBar() Cast bar for unit " .. unitId .. " already exists.")
    end

    -- container represents the total configured width × height;
    -- the icon and status bar are both positioned inside it so the total footprint never changes
    local containerFrame = CreateFrame("Frame", name .. "_Container", parent)

    local newCastBar = framework:CreateCastBar(containerFrame, name, settingsOverride)
    ---@cast newCastBar _castbar
    castBarObjects[unitId] = newCastBar

    newCastBar:SetUnit(unitId)

    setupCastBarStyling(newCastBar, containerFrame)

    return newCastBar
end

---Create an unbound cast bar — same container/layout/hooks as a unit cast bar
---but with no SetUnit call, so DF registers no events and installs no OnTick.
---Driven entirely by the caller (Show/Hide, SetMinMaxValues/SetValue, custom OnUpdate).
---Used for synthetic overlays where DF's lifecycle would conflict.
---@param parent frame
---@param name string
---@param settingsOverride table?
---@return _castbar
castBar.CreateOverlayBar = function(parent, name, settingsOverride)
    local containerFrame = CreateFrame("Frame", name .. "_Container", parent)

    local newCastBar = framework:CreateCastBar(containerFrame, name, settingsOverride)
    ---@cast newCastBar _castbar

    setupCastBarStyling(newCastBar, containerFrame)

    return newCastBar
end

castBar.HideForUnit = function(unitId)
    local castBarObject = castBar.GetCastBar(unitId)
    if castBarObject then
        castBarObject:Hide()
    end
end

---Register PLAYER_TALENT_UPDATE so tick marks update when talents change.
---Called by PlayerCastBar on enable; safe to call multiple times (idempotent).
castBar.EnableTalentTracking = function()
    castBarEventCallbackFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
end

---Unregister PLAYER_TALENT_UPDATE.
---Called by PlayerCastBar on disable; safe to call when already unregistered.
castBar.DisableTalentTracking = function()
    castBarEventCallbackFrame:UnregisterEvent("PLAYER_TALENT_UPDATE")
end

---Register the haste-shift events that invalidate the Evoker baseline cache.
---No-op for non-Evokers. Safe to call multiple times.
castBar.EnableEvokerTickCalibration = function()
    if playerClass ~= "EVOKER" then return end
    castBarEventCallbackFrame:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
    castBarEventCallbackFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
end

---Unregister the Evoker baseline cache invalidation events and reset state.
castBar.DisableEvokerTickCalibration = function()
    castBarEventCallbackFrame:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    castBarEventCallbackFrame:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
    evokerBaselineDuration = {}
    evokerLastChannelEndsAt = 0
end

---Start Mass Disintegrate charge tracking (Evoker only).
---Registers UNIT_SPELLCAST_SUCCEEDED + UNIT_SPELLCAST_EMPOWER_STOP.
---Safe to call multiple times (idempotent — RegisterEvent is a no-op if already registered).
castBar.EnableMassDisintegrateTracking = function()
    if playerClass ~= "EVOKER" then return end
    massDisWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    massDisWatcher:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
end

---Stop Mass Disintegrate charge tracking and reset charges.
castBar.DisableMassDisintegrateTracking = function()
    massDisWatcher:UnregisterAllEvents()
    massDisCharges = 0
end

local tickingClasses = {
    ["DEMONHUNTER"] = 10,
    ["DRUID"] = 16,
    ["EVOKER"] = 5,
    ["MAGE"] = 8,
    ["MONK"] = 8,
    ["PRIEST"] = 6,
    ["WARLOCK"] = 15,
}

local spellTickIDs = {
    -- DH
	[212084] = 10, -- fel devastation
	[452486] = 10, -- fel desolation
	-- druid
	[740] = 4, -- tranquility
	[391528] = 16, -- convoke the spirits
    -- evoker
	[356995] = 3, -- disintegrate
	[436335] = 3, -- mass disintegrate
	[370960] = 5, -- emerald communion
	-- mage
	[5143] = 5, -- arcane missiles
    [12051] = 6, -- evocation
    [198100] = 8, -- kleptomania
	[205021] = 5, -- ray of frost
	[382440] = 4, -- shifting power
	-- monk
    [115175] = 8, -- soothing mist
	[117952] = 4, -- crackling jade lightning
	[443028] = 4, -- celestial conduit
    -- priest
    [15407] = 6, -- mind flay
    [47540] = 3, -- penance
	[64843] = 4, -- divine hymn
    [64901] = 5, -- symbol of hope
    [263165] = 3, -- void torrent
	[391403] = 4, -- mind flay: insanity
	[400169] = 3, -- dark reprimand
    -- warlock
    [196447] = 15, -- channel demonfire
    [198590] = 5, -- drain soul
    [217979] = 5, -- health funnel
	[234153] = 5, -- drain life
	[417537] = 3, -- oblivion
}

local modifyTicksTalents = {
    [5143] = {"MAGE", {236628}, 8}, -- arcane missiles: amplification 5->8
    [47540] = {"PRIEST", {193134}, 4}, -- penance: castigation 3->4
    [356995] = {"EVOKER", {1219723}, 4}, -- disintegrate: azure celerity 3->4
    [436335] = {"EVOKER", {1219723}, 4}, -- mass disintegrate: azure celerity 3->4
    [391528] = {"DRUID", {391548, 393991, 393414, 393371}, 12}, -- convoke: Ashamane/Elune/Ursoc/Cenarius Guidance 16->12
}

local IsPlayerSpell = function(spellID)
    local spellBank = Enum.SpellBookSpellBank.Player
    return C_SpellBook.IsSpellKnown(spellID, spellBank)
end

local IsAnySpellKnown = function(spellIDs)
    for _, spellID in pairs(spellIDs or {}) do
        if IsPlayerSpell(spellID) then
            return true, spellID
        end
    end
    return false
end

castBar.UpdateTicksTable = function()
    local ticksByName = {}
    local ticksById = {}

    for id, ticks in pairs(spellTickIDs) do
        local ticksOverride = modifyTicksTalents[id]
        if ticksOverride then
            ticks = IsAnySpellKnown(ticksOverride[2]) and ticksOverride[3] or ticks
        end
        ticksById[id] = ticks
        local spellName = C_Spell.GetSpellName(id)
        if spellName then
            ticksByName[spellName] = ticks
        end
    end
    castBar.ticksByName = ticksByName
    castBar.ticksById = ticksById
end

castBar.getTicksForSpell = function(spell)
    if issecretvalue(spell) then
        return 0
    end
    if not castBar.ticksByName then
        castBar.UpdateTicksTable()
    end
    return castBar.ticksByName[spell] or castBar.ticksById[spell] or 0
end

castBar.createTickSparks = function(unitCastBar)
    local maxTicks = tickingClasses[playerClass]
    unitCastBar.castTickSparks = unitCastBar.castTickSparks or {}
    for i = 1, maxTicks or 0 do
        local tickSpark = unitCastBar.castTickSparks[i]
        if not tickSpark then
            local newSpark = unitCastBar:CreateTexture(nil, 'OVERLAY')
            newSpark:SetColorTexture(1, 1, 1, 1)
            newSpark:SetSnapToPixelGrid(false)
            newSpark:SetTexelSnappingBias(0)
            unitCastBar.castTickSparks[i] = newSpark
        end
    end
    -- Size is applied per-tick in UpdateCastTicks/UpdateCastTicksEvoker
    -- based on orientation, so no fixed size set here.
end

castBar.UpdateCastTicksEvoker = function(unitCastBar)
    local tickCount = castBar.getTicksForSpell(unitCastBar.spellID)
    if tickCount > 0 then
        if not unitCastBar.durationObject then return end
        local duration = unitCastBar.durationObject:GetTotalDuration()
        if duration == 0 then return end
        -- baseline is an unclipped prior cast's duration for this spellID; when a
        -- new channel clips an existing one the server reports an extended duration
        -- carrying the remainder of the prior tick, and using baseline/tickCount as
        -- the true interval keeps ticks aligned to real firing times instead of
        -- re-spreading them across the extended bar.
        local baseline = evokerBaselineDuration[unitCastBar.spellID] or duration
        local tickTime = baseline / tickCount
        local frac = tickTime / duration
        local isVertical = unitCastBar.cueOrientation == "vertical"
        local barSize = isVertical and unitCastBar:GetHeight() or unitCastBar:GetWidth()
        for i = 1, tickCount do
            local tickSpark = unitCastBar.castTickSparks[i]
            local rel = i * frac
            tickSpark:ClearAllPoints()
            if isVertical then
                private.Pixel.SetSize(tickSpark, unitCastBar:GetWidth(), 2)
                private.Pixel.SetPoint(tickSpark, "CENTER", unitCastBar, "BOTTOM", 0, barSize * rel)
            else
                private.Pixel.SetSize(tickSpark, 2, unitCastBar:GetHeight())
                private.Pixel.SetPoint(tickSpark, "CENTER", unitCastBar, "LEFT", barSize * rel, 0)
            end
            if tickTime * i < duration * 0.99 then
                tickSpark:Show()
            else
                tickSpark:Hide()
            end
        end
        -- hide sparks left over from a longer previous channel (the last spark of
        -- THIS channel is handled by the 0.99 test above, so start at tickCount+1)
        for i = tickCount + 1, #unitCastBar.castTickSparks do
            unitCastBar.castTickSparks[i]:Hide()
        end
    else
        for _, tickSpark in ipairs(unitCastBar.castTickSparks or {}) do
            tickSpark:Hide()
        end
    end
end

castBar.UpdateCastTicks = function(unitCastBar, keepInterval)
    local tickCount = castBar.getTicksForSpell(unitCastBar.spellID)
    if tickCount > 0 then
        if not unitCastBar.durationObject then return end
        local duration = unitCastBar.durationObject:GetTotalDuration()
        if duration == 0 then return end

        -- A pushed-back channel loses time off its end but its ticks keep
        -- their interval, so the last ones are lost (#50). On a channel update
        -- keep the interval measured when this spell's channel started; the
        -- bar now spans the shortened channel (cast-info span).
        local tickTime = duration / tickCount
        if keepInterval and unitCastBar.cueTickTime and unitCastBar.cueTickSpell == unitCastBar.spellID then
            tickTime = unitCastBar.cueTickTime
        end
        unitCastBar.cueTickTime, unitCastBar.cueTickSpell = tickTime, unitCastBar.spellID
        local isVertical = unitCastBar.cueOrientation == "vertical"
        local barSize = isVertical and unitCastBar:GetHeight() or unitCastBar:GetWidth()
        -- show tick marks at positions where each tick fires along the draining bar
        -- the bar drains right-to-left (or top-to-bottom), so tick i is placed from the end
        for i = 1, tickCount-1 do
            local tickSpark = unitCastBar.castTickSparks[i]
            local rel = i * tickTime / duration
            if rel >= 1 then
                -- lost to pushback: fires after the channel now ends
                tickSpark:Hide()
            else
                tickSpark:ClearAllPoints()
                if isVertical then
                    private.Pixel.SetSize(tickSpark, unitCastBar:GetWidth(), 2)
                    private.Pixel.SetPoint(tickSpark, "CENTER", unitCastBar, "TOP", 0, -barSize * rel)
                else
                    private.Pixel.SetSize(tickSpark, 2, unitCastBar:GetHeight())
                    private.Pixel.SetPoint(tickSpark, "CENTER", unitCastBar, "RIGHT", -barSize * rel, 0)
                end
                tickSpark:Show()
            end
        end
        -- hide the last spark (fires at bar=0 = no mark needed) and any unused sparks
        for i = tickCount, #unitCastBar.castTickSparks do
            unitCastBar.castTickSparks[i]:Hide()
        end
    else
        for _, tickSpark in ipairs(unitCastBar.castTickSparks or {}) do
            tickSpark:Hide()
        end
    end
end

-- events that should reposition tick marks (channel is active)
local channelTickEvents = {
    ["UNIT_SPELLCAST_CHANNEL_START"] = true,
    ["UNIT_SPELLCAST_CHANNEL_UPDATE"] = true,
}

-- events that should hide tick marks (regular cast, interrupt, stop, empower)
local hideTickEvents = {
    ["UNIT_SPELLCAST_START"] = true,
    ["UNIT_SPELLCAST_DELAYED"] = true,
    ["UNIT_SPELLCAST_CHANNEL_STOP"] = true,
    ["UNIT_SPELLCAST_EMPOWER_START"] = true,
}

-- ---------------------------------------------------------------------------
-- Mass Disintegrate glow — Scalecommander Evoker
-- Shows a pulsing border on the cast bar when channeling Disintegrate with
-- Mass Disintegrate charges. The buff (436336) is consumed before
-- UNIT_SPELLCAST_CHANNEL_START fires and UNIT_AURA is secret, so we track
-- charges ourselves via UNIT_SPELLCAST_SUCCEEDED on empower spells.
-- ---------------------------------------------------------------------------

local MASS_DISINTEGRATE_TALENT_ID = 436335
local DISINTEGRATE_SPELL_ID = 356995
local MASS_DIS_BORDER_SIZE = 3
local MASS_DIS_COLOR_2 = {0.5, 0.8, 1.0, 1} -- 2 charges: blue
local MASS_DIS_COLOR_1 = {0.9, 0.65, 0.3, 1} -- 1 charge: orange-ish
local MASS_DIS_DURATION = 15
local MASS_DIS_MAX_CHARGES = 2

-- Empower spells that grant Mass Disintegrate charges
local massDisEmpowerSpells = {
    [357208] = true, -- fire breath
    [382266] = true, -- fire breath (font of magic)
    [359073] = true, -- eternity surge
    [382411] = true, -- eternity surge (font of magic)
}

-- Addon-side charge tracking (buff is secret/consumed)
massDisCharges = 0
local massDisExpiry = 0

-- Watcher frame for empower completions
massDisWatcher = CreateFrame("Frame")
massDisWatcher:SetScript("OnEvent", function(_, event, _, _, spellID)
    if playerClass ~= "EVOKER" then return end
    if not IsPlayerSpell(MASS_DISINTEGRATE_TALENT_ID) then return end

    if event == "UNIT_SPELLCAST_SUCCEEDED" and massDisEmpowerSpells[spellID] then
        massDisCharges = math.min(massDisCharges + 1, MASS_DIS_MAX_CHARGES)
        massDisExpiry = GetTime() + MASS_DIS_DURATION
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" and massDisEmpowerSpells[spellID] then
        -- fallback: some empowers may not fire SUCCEEDED
        if massDisCharges == 0 then
            massDisCharges = math.min(massDisCharges + 1, MASS_DIS_MAX_CHARGES)
            massDisExpiry = GetTime() + MASS_DIS_DURATION
        end
    end
end)

---Check whether Mass Disintegrate charges are available (expires after 15s).
---@return boolean
local function hasMassDisintegrateCharges()
    if massDisCharges > 0 and GetTime() < massDisExpiry then
        return true
    end
    massDisCharges = 0
    return false
end

---Create or retrieve the Mass Disintegrate glow border on a cast bar's container.
---@param unitCastBar _castbar
---@return frame|nil glowFrame
local function getOrCreateMassDisintegrateGlow(unitCastBar)
    if unitCastBar._massDisGlow then return unitCastBar._massDisGlow end
    local container = unitCastBar.containerFrame
    if not container then return nil end

    local f = CreateFrame("Frame", nil, container, "BackdropTemplate")
    private.Pixel.SetPoint(f, "TOPLEFT", container, "TOPLEFT", -1, 1)
    private.Pixel.SetPoint(f, "BOTTOMRIGHT", container, "BOTTOMRIGHT", 1, -1)
    f:SetFrameLevel(container:GetFrameLevel() + 2)

    f:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = MASS_DIS_BORDER_SIZE,
    })
    f:SetBackdropBorderColor(unpack(MASS_DIS_COLOR_2))

    local ag = f:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    ag:SetToFinalAlpha(true)

    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetDuration(0.6)
    fadeIn:SetFromAlpha(0.5)
    fadeIn:SetToAlpha(1.0)
    fadeIn:SetSmoothing("IN_OUT")
    fadeIn:SetOrder(1)

    f.anim = ag
    ag:SetScript("OnPlay", function() f:Show() end)
    ag:SetScript("OnStop", function() f:Hide() end)
    f:Hide()

    unitCastBar._massDisGlow = f
    return f
end

---Force-stop the Mass Disintegrate glow animation and hide the frame.
---@param unitCastBar _castbar
local function forceHideMassDisintegrateGlow(unitCastBar)
    local glow = unitCastBar._massDisGlow
    if not glow then return end
    if glow.anim:IsPlaying() then
        glow.anim:Stop()
    end
end

---Show the Mass Disintegrate glow if conditions are met.
---When clipping into a new channel that doesn't qualify, hides any leftover glow.
---@param unitCastBar _castbar
local function showMassDisintegrateGlow(unitCastBar)
    if playerClass ~= "EVOKER" then return end
    local settings = private.profile.components.PlayerCastBar
    if not settings or not settings.mass_disintegrate_glow then return end

    if issecretvalue(unitCastBar.spellID) or unitCastBar.spellID ~= DISINTEGRATE_SPELL_ID
        or not hasMassDisintegrateCharges() then
        -- New channel doesn't qualify — hide any glow left over from the previous channel
        forceHideMassDisintegrateGlow(unitCastBar)
        return
    end

    massDisCharges = massDisCharges - 1
    local glow = getOrCreateMassDisintegrateGlow(unitCastBar)
    if glow then
        local color = massDisCharges > 0 and MASS_DIS_COLOR_2 or MASS_DIS_COLOR_1
        glow:SetBackdropBorderColor(unpack(color))
        if not glow.anim:IsPlaying() then
            glow.anim:Play()
        end
    end
end

---Hide the Mass Disintegrate glow.
---When clipping a channel into another channel, WoW fires CHANNEL_START (new)
---before CHANNEL_STOP (old). DF's handler skips the old STOP (castBarID mismatch)
---without clearing self.channeling, so channeling being true here means the glow
---belongs to the new channel — don't hide it.
---@param unitCastBar _castbar
local function hideMassDisintegrateGlow(unitCastBar)
    if not unitCastBar._massDisGlow then return end
    if unitCastBar.channeling then return end
    if unitCastBar._massDisGlow.anim:IsPlaying() then
        unitCastBar._massDisGlow.anim:Stop()
    end
end

castBar.UpdateCastTicksEvent = function(self, unit, event)
    if unit ~= "player" then return end

    local settings = private.profile.components.PlayerCastBar
    if channelTickEvents[event] then
        if playerClass == "EVOKER" and event == "UNIT_SPELLCAST_CHANNEL_START"
           and self.spellID and not issecretvalue(self.spellID) and self.durationObject then
            local d = self.durationObject:GetTotalDuration()
            if d and d > 0 then
                -- 0.05s epsilon absorbs timestamp rounding between server and client
                if GetTime() >= evokerLastChannelEndsAt - 0.05 then
                    evokerBaselineDuration[self.spellID] = d
                end
                evokerLastChannelEndsAt = GetTime() + d
            end
        end
        if settings and settings.show_channel_ticks then
            if playerClass == "EVOKER" then
                castBar.UpdateCastTicksEvoker(self)
            else
                castBar.UpdateCastTicks(self, event == "UNIT_SPELLCAST_CHANNEL_UPDATE")
            end
        end
        if playerClass == "EVOKER" and event == "UNIT_SPELLCAST_CHANNEL_START" then
            showMassDisintegrateGlow(self)
        end
    elseif hideTickEvents[event] then
        -- Same clipped-channel hazard hideMassDisintegrateGlow guards against: on
        -- a channel clipped into another, WoW fires CHANNEL_START (new) before
        -- CHANNEL_STOP (old), and DF still runs our hook for the stale STOP. Ticks
        -- were placed for the NEW channel at its START, and nothing re-shows them
        -- (channelTickEvents is START/UPDATE only), so wiping here loses them for
        -- the whole channel.  EMPOWER_START is exempt: DF's handler routes it
        -- through CHANNEL_START before this hook runs, so `channeling` is always
        -- set for it, and the empower replaces any channel's ticks.
        if self.channeling and event ~= "UNIT_SPELLCAST_EMPOWER_START" then return end
        for _, tickSpark in ipairs(self.castTickSparks or {}) do
            tickSpark:Hide()
        end
        hideMassDisintegrateGlow(self)
    end
end

---A duration spanning the bar's current cast or channel, built from
---UnitCastingInfo / UnitChannelInfo start and end, or nil when that info is
---unavailable or secret. The SetTimerDuration shim in setupCastBarStyling binds
---this in place of DF's UnitCastingDuration / UnitChannelDuration object.
---
---Issue #50: after a pushback CUE's bar kept filling at the old rate while
---Blizzard's followed the cast. Blizzard's bar takes a pushback's timing from
---exactly this info (CastingBarFrame.lua:494/:524) and reads no duration
---getter; DF re-binds from the getter (unitframe_midnight.lua:2138/:2151, and
---UpdateChannelInfo :1783/:1868), the one input the two bars do not share.
---
---Cast info is plain for the player and their pet, secret for other units
---(SecretWhenUnitSpellCastRestricted; a per-spell flag can override either
---way), so a target/focus cast normally keeps DF's object. An empowered channel
---always does: its span includes the hold time (UnitEmpoweredChannelDuration).
---That is read from UnitChannelInfo's own isEmpowered (NeverSecret), because
---DF sets bar.empowered for the "player" token only (unitframe_midnight.lua:1812).
---
---A new object per bind, never a mutated one: a re-bind of the object the
---engine already holds is not known to take effect. Binds happen a few times
---per cast, never per frame.
---
---Also returns the span in ms and a key naming the cast, so the shim can tell a
---pushback (same cast, moved span) from the next cast: a cast's castID, or for
---a channel, which has none, its castBarID (NeverSecret, one per cast in the
---in-client log). Not the start time: Forever moves a cast's start on
---pushback. nil when the key is secret.
---@param bar _castbar
---@return table? duration LuaDurationObject
---@return number? startMs
---@return number? endMs
---@return any castKey
castBar.CastInfoDuration = function(bar)
    local unit = bar.unit
    if not unit or bar.empowered then return end
    local _, startMs, endMs, castKey
    if bar.channeling then
        local isEmpowered
        startMs, endMs, _, _, _, isEmpowered, _, castKey = select(4, UnitChannelInfo(unit))
        if isEmpowered then return end
    elseif bar.casting then
        startMs, endMs, _, castKey = select(4, UnitCastingInfo(unit))
    else
        return
    end
    if issecretvalue(startMs) or issecretvalue(endMs) or not startMs or not endMs then return end
    if issecretvalue(castKey) then castKey = nil end

    local duration = C_DurationUtil.CreateDuration()
    duration:SetTimeSpan(startMs / 1000, endMs / 1000)
    return duration, startMs, endMs, castKey
end

local LibSharedMedia = LibStub("LibSharedMedia-3.0")

---Apply the profile fill texture to a cast bar.
---Looks up 'texture' as a LibSharedMedia "statusbar" key (LSM:Fetch with noDefault=true).
---If found, applies the file path via bar:SetTexture() (StatusBarFunctions, mixins.lua:767).
---If not found or empty, falls back to a solid white fill via bar.barTexture:SetColorTexture(1,1,1,1).
---@param bar _castbar
---@param texture string LibSharedMedia statusbar key, or "" for white fallback
castBar.ApplyTexture = function(bar, texture)
    if texture and texture ~= "" then
        local lsmPath = LibSharedMedia:Fetch("statusbar", texture, true)
        if lsmPath then
            bar:SetTexture(lsmPath)
            return
        end
    end
    bar.barTexture:SetColorTexture(1, 1, 1, 1)
end

---Apply font settings from the component profile to a cast bar's text elements.
---Uses ApplyFontProfile for font face/size/outline and anchor-based positioning.
---@param bar _castbar
---@param settings castbar_component_profile_main
castBar.ApplyFonts = function(bar, settings)
    local overlayFrame = private.Util.GetBarBorderFrame(bar)
    local isVertical = bar.cueOrientation == "vertical"
    local textMode = settings.cast_text_format or "both"
    local showName = textMode == "both" or textMode == "name"
    local showTime = textMode == "both" or textMode == "time"

    local nameFont = settings.cast_name_font
    if nameFont then
        if overlayFrame then
            bar.Text:SetParent(overlayFrame)
            bar.Text:SetDrawLayer("OVERLAY", 7)
        end
        private.Util.ApplyFontProfile(bar.Text, nameFont, bar)
        local maxWidthPct = settings.cast_name_max_width or 0
        if maxWidthPct > 0 then
            local maxWidth = bar:GetWidth() * (maxWidthPct / 100)
            bar.Text:SetWidth(maxWidth)
            bar.Text:SetWordWrap(false)
            bar.Text:SetNonSpaceWrap(false)
        else
            bar.Text:SetWidth(0)
        end
        if isVertical then
            private.Util.ApplyVerticalFontRotation(bar.Text)
        else
            bar.Text:SetRotation(0)
        end
    end
    -- Name text: DF only ever SetText()s bar.Text during a cast (never
    -- Show/Hide/alpha/color it), so a SetAlpha(0) can be clobbered
    -- (SetTextColor resets alpha — see patterns.md). Hide() sticks across
    -- casts because DF never re-Shows it.
    if showName then
        bar.Text:SetAlpha(1)
        bar.Text:Show()
    else
        bar.Text:Hide()
    end

    local timeFont = settings.cast_time_font
    if timeFont then
        if overlayFrame then
            bar.percentText:SetParent(overlayFrame)
            bar.percentText:SetDrawLayer("OVERLAY", 7)
        end
        private.Util.ApplyFontProfile(bar.percentText, timeFont, bar)
        if isVertical then
            private.Util.ApplyVerticalFontRotation(bar.percentText)
        else
            bar.percentText:SetRotation(0)
        end
    end
    -- Time text: DF re-Shows percentText on every cast start, gated by its own
    -- per-bar Settings.ShowCastTime (unitframe_midnight.lua:1660/1877). Pin that
    -- flag so following casts don't re-reveal it, and sync the current cast's
    -- percentText immediately. Settings is a per-bar copy (CreateCastBar), so this
    -- doesn't leak across bars.
    bar.Settings.ShowCastTime = showTime
    bar.cueTimeStyle = settings.cast_time_style
    if showTime then
        bar.percentText:SetAlpha(1)
        bar.percentText:Show()
    else
        bar.percentText:Hide()
    end
end

---Apply profile color settings to a cast bar's Colors table.
---Each Colors entry is a DF colorTableMixin (fw.lua:2635) with SetColor(r,g,b,a).
---Colors are assigned during CastFrameFunctions.Initialize (unitframe_midnight.lua:1120)
---as self.Colors = self.Settings.Colors.
---@param bar _castbar
castBar.ApplyColors = function(bar)
    local colors = private.profile.castbar_colors
    if not colors then return end
    local casting = colors.casting
    local channeling = colors.channeling
    if colors.use_class_color and bar.unit == "player" then
        local _, class = UnitClass("player")
        local c = class and RAID_CLASS_COLORS[class]
        if c then
            casting = {c.r, c.g, c.b, colors.casting[4] or 1}
            channeling = {c.r, c.g, c.b, colors.channeling[4] or 1}
        end
    end
    bar.Colors.Casting:SetColor(unpack(casting))
    bar.Colors.Channeling:SetColor(unpack(channeling))
    bar.Colors.Finished:SetColor(unpack(colors.finished))
    bar.Colors.NonInterruptible:SetColor(unpack(colors.non_interruptible))
    bar.Colors.Interrupted:SetColor(unpack(colors.interrupted))
    bar.Colors.Important:SetColor(unpack(colors.important))
    bar.Colors.Empowered:SetColor(unpack(colors.empowered))

    if colors.background then
        local r, g, b, a = unpack(colors.background)
        local bgTexture = colors.background_texture
        local applied = false
        if bgTexture and bgTexture ~= "" then
            local lsmPath = LibSharedMedia:Fetch("statusbar", bgTexture, true)
            if lsmPath then
                bar.background:SetTexture(lsmPath)
                bar.extraBackground:SetTexture(lsmPath)
                bar.background:SetVertexColor(r, g, b, a)
                bar.extraBackground:SetVertexColor(r, g, b, a)
                applied = true
            end
        end
        if not applied then
            bar.background:SetColorTexture(r, g, b, a)
            bar.extraBackground:SetColorTexture(r, g, b, a)
        end
    end

    private.Util.ApplyBarBorder(bar, bar.cueShowIcon and bar.containerFrame or nil)
end

---Default DetailsFramework settings shared by all cast bar component CreateCastBar calls.
castBar.DefaultCreateSettings = {
    FadeInTime = 0.02,
    FadeOutTime = 0.66,
    LazyUpdateCooldown = 0.1,
    FillOnInterrupt = false,
    HideSparkOnInterrupt = false,
    ShowEmpoweredDuration = true,
    ShowShield = false,
    ShowTradeSkills = true,
}

---Show a static dummy Frostbolt cast for edit mode preview.
---Sets bar values that won't be overridden by OnTick (casting/channeling are nil).
---@param bar _castbar
castBar.ShowEditModePreview = function(bar)
    -- Clear any lingering cast state so OnTick won't override our preview
    bar.casting = nil
    bar.channeling = nil
    bar:Animation_StopAllAnimations()

    local icon = C_Spell.GetSpellTexture(116)
    if icon then
        bar.Icon:SetTexture(icon)
    end
    bar:Show()
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.5) -- 1.5 of 3.0 seconds = 50%
    bar:SetStatusBarColor(bar.Colors.Casting:GetColor())
    local spellName = C_Spell.GetSpellName(116)
    bar.Text:SetText(spellName or "Frostbolt")
    bar.percentText:SetText(castBar.FormatCastTime(bar.cueTimeStyle, 1.5, 3.0))
    -- Respect the Text Display setting in preview: ApplyFonts pinned ShowCastTime
    -- and Hid/Showed percentText; only re-Show it here when time is enabled.
    if bar.Settings.ShowCastTime then
        bar.percentText:Show()
    end
end

---Reset a cast bar after edit mode preview, clearing dummy values.
---@param bar _castbar
castBar.HideEditModePreview = function(bar)
    bar:Animation_StopAllAnimations()
    -- Animation_StopAllAnimations only knows DF's own hubs; the pushback cutaway
    -- is CUE-owned, so one mid-fade when Edit Mode opened needs its own stop.
    stopPushbackCutaway(bar)
    bar.Text:SetText("")
    bar.percentText:SetText("")
    bar.percentText:Hide()
    bar.Icon:Hide()
    bar:SetValue(0)
    bar:SetAlpha(1)
    bar:Hide()
end

---Create a standard cast bar component for a unit that needs no special logic.
---Returns a complete component table ready for ComponentManager registration.
---Used by TargetCastBar and FocusCastBar; PlayerCastBar has additional logic
---(talent tracking, native bar hiding) and uses DefaultCreateSettings directly.
---@param unitId unitcastbar
---@param componentName string
---@param unitChangedEvent string? Event to listen for when the unit changes (e.g. PLAYER_TARGET_CHANGED)
---@return component
castBar.CreateCastBarComponent = function(unitId, componentName, unitChangedEvent)
    local comp = {}
    comp.name = componentName

    local getSettings = function()
        return private.profile.components[comp.name]
    end
    comp.GetSettings = getSettings

    local getEnabled = function()
        return getSettings().enabled
    end
    comp.GetEnabled = getEnabled

    ---When the player switches target/focus, UNIT_SPELLCAST_START does not fire
    ---for an already in-progress cast. Listen for the unit-changed event and
    ---re-evaluate the cast bar using the same logic as PLAYER_ENTERING_WORLD.
    local unitChangedWatcher
    if unitChangedEvent then
        unitChangedWatcher = CreateFrame("Frame")
        unitChangedWatcher:SetScript("OnEvent", function()
            local bar = castBar.GetCastBar(unitId)
            if bar then
                bar:PLAYER_ENTERING_WORLD(bar.unit, bar.unit)
            end
        end)
    end

    comp.Initialize = function()
        comp.Refresh()
        if unitChangedWatcher and getEnabled() then
            unitChangedWatcher:RegisterEvent(unitChangedEvent)
        end
    end

    comp.GetFrame = function()
        local bar = castBar.GetCastBar(unitId)
        return bar and bar.containerFrame
    end

    comp.Refresh = function()
        if not castBar.GetCastBar(unitId) then
            local name = "CUE_CastBar_" .. unitId
            castBar.CreateCastBar(unitId, UIParent, name, castBar.DefaultCreateSettings)
        end

        local settings = getSettings()
        local bar = castBar.GetCastBar(unitId)

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
        castBar.ApplyTexture(bar, settings.texture)
        castBar.ApplyColors(bar)
        if private.fontsDirty then
            castBar.ApplyFonts(bar, settings)
        end
        local frameW = isVertical and settings.height or settings.width
        local frameH = isVertical and settings.width or settings.height

        -- In edit mode, always show the container with a dummy cast preview
        if private.isEditMode then
            bar.containerFrame:Show()
            private.Pixel.SetSize(bar.containerFrame, frameW, frameH)
            bar.updateLayout()
            castBar.ShowEditModePreview(bar)
            return
        end

        -- Reset any edit mode preview artifacts before normal display logic
        castBar.HideEditModePreview(bar)

        if not settings.enabled or not private.Anchor.IsVisibleForComponent(comp.name) then
            bar.containerFrame:Hide()
            return
        end

        bar.containerFrame:Show()
        private.Pixel.SetSize(bar.containerFrame, frameW, frameH)
        bar.updateLayout()
        -- Re-evaluate current cast state so an in-progress cast shows after
        -- the visibility chain becomes visible (e.g. dismounting)
        bar:PLAYER_ENTERING_WORLD(bar.unit, bar.unit)
    end

    comp.OnEnable = function()
        comp.Refresh()
        if unitChangedWatcher then
            unitChangedWatcher:RegisterEvent(unitChangedEvent)
        end
    end

    comp.OnDisable = function()
        if unitChangedWatcher then
            unitChangedWatcher:UnregisterAllEvents()
        end
        castBar.HideForUnit(unitId)
        local bar = castBar.GetCastBar(unitId)
        if bar then bar.containerFrame:Hide() end
    end

    comp.GetComponentName = function()
        return comp.name
    end

    comp.GetComponentSize = function()
        local settings = getSettings()
        if (settings.orientation or "horizontal") == "vertical" then
            return settings.height, settings.width
        end
        return settings.width, settings.height
    end

    return comp
end

---Toggle cast text tracing and log a snapshot of the current state. Driven by
---/cue debugcast (Core/UI/Slash.lua).
castBar.ToggleTextTrace = function()
    castTextTracing = not castTextTracing
    private.printdebug("castdebug trace", castTextTracing and "ON" or "OFF")
    dumpCastTextState()
end

private.CastBar = castBar
