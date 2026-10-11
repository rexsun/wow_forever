
local _
---@type string, private
local _, private = ...

---@type detailsframework
local framework = _G["DetailsFramework"]

local LibSharedMedia = LibStub("LibSharedMedia-3.0")

---@class private : table
---@field GlobalCooldown globalcooldowncomp

---@class globalcooldowncomp : component

---@type globalcooldowncomp
---@diagnostic disable-next-line: missing-fields
local globalCooldown = {}

globalCooldown.name = "GlobalCooldown"

-- ---------------------------------------------------------------------------
-- Settings access (standard pattern)
-- ---------------------------------------------------------------------------

---@return globalcooldown_profile_main
local getSettings = function()
    return private.profile.components[globalCooldown.name]
end

globalCooldown.GetSettings = getSettings

local getEnabled = function()
    return getSettings().enabled
end

globalCooldown.GetEnabled = getEnabled

-- ---------------------------------------------------------------------------
-- Local state (upvalues, NOT on frames)
-- ---------------------------------------------------------------------------

local castStarted = 0
---@type table?
local currentCast = nil
---@type FunctionContainer?
local scheduleCast = nil
local isPreview = false
local activeGCDStart = 0

---@type frame?
local containerFrame
---@type df_timebar?
local gcdBar
---@type texture?
local latencyTexture
---@type texture?
local queuePipTexture
---@type frame?
local eventFrame

-- ---------------------------------------------------------------------------
-- WoW API upvalues
-- ---------------------------------------------------------------------------

local GetTime = GetTime
local GetNetStats = GetNetStats
local format = format

-- ---------------------------------------------------------------------------
-- GCD tracking core
-- ---------------------------------------------------------------------------

---Query the GCD state via the GCD reference spell (`private.GCD_SPELL_ID`).
---@return number startTime
---@return number duration
---@return number modRate
---@return boolean isActive
---@return boolean isEnabled
local function getCooldownInfo()
    local result = C_Spell.GetSpellCooldown(private.GCD_SPELL_ID)
    if not result then
        return 0, 0, 1, false, false
    end
    return result.startTime, result.duration, result.modRate, result.isActive, result.isEnabled
end

---Update the GlobalCooldown component background visibility.
---When hide_inactive_background is enabled, marks the container as empty
---(hiding the background) when the GCD bar is not actively running.
local function updateInactiveBackground()
    if not containerFrame then return end
    local settings = getSettings()
    if not settings.hide_inactive_background then
        -- Clear the sticky empty flag on the way out: these lines are its only
        -- writer for this container, so a true left over from when the option
        -- WAS on keeps ApplyComponentBackground hiding the panel on every later
        -- layout pass. The next pass re-applies the background.
        private.Util.SetComponentEmpty(containerFrame, false)
        return
    end
    if private.isEditMode then return end

    local barActive = gcdBar ~= nil and gcdBar.statusBar:IsShown()
    private.Util.SetComponentEmpty(containerFrame, not barActive)
    private.Util.ApplyComponentBackground(containerFrame, settings.background)
end

---Deferred callback: start the GCD bar after latency measurement completes.
local function scheduleCastStart()
    if not currentCast then return end
    if not gcdBar then return end

    local startTime, duration, _, isActive = getCooldownInfo()
    if not isActive then return end
    if isPreview then return end
    if startTime == activeGCDStart then return end

    local gcdRemaining = startTime + duration - GetTime()
    if gcdRemaining < 0.1 or gcdRemaining > 1.5 then
        gcdRemaining = 1.5
    end

    local settings = getSettings()

    local secretSpell = issecretvalue(currentCast.spellId)
    local spellInfo = not secretSpell and C_Spell.GetSpellInfo(currentCast.spellId) or nil
    local isInstant = not currentCast.isChannel and not currentCast.isEmpower
        and (secretSpell or not spellInfo or not spellInfo.castTime or spellInfo.castTime == 0)

    if settings.instant_only and not isInstant then
        return
    end

    local barTime = gcdRemaining
    if barTime <= 0 then return end

    activeGCDStart = startTime
    gcdBar:SetTimer(barTime)
    if scheduleCast then
        scheduleCast:Cancel()
        scheduleCast = nil
    end
    updateInactiveBackground()

    if settings.show_icon and not secretSpell then
        local spellTexture = C_Spell.GetSpellTexture(currentCast.spellId)
        local iconRegion = gcdBar.statusBar.icon
        iconRegion:SetTexture(spellTexture)
        iconRegion:SetTexCoord(private.Util.GetIconZoomCoords(iconRegion:GetSize()))
        iconRegion:Show()
    else
        gcdBar.statusBar.icon:Hide()
    end

    if settings.show_spell_name and isInstant and spellInfo then
        gcdBar:SetLeftText(spellInfo.name)
    else
        gcdBar:SetLeftText("")
    end

    if latencyTexture and settings.show_latency and gcdRemaining > 0 then
        latencyTexture:SetWidth((currentCast.latency / gcdRemaining) * gcdBar.statusBar:GetWidth())
    end

    if queuePipTexture and settings.show_queue_pip then
        local queueWindowSec = (tonumber(C_CVar.GetCVar("SpellQueueWindow")) or 400) / 1000
        if queueWindowSec >= gcdRemaining then
            queuePipTexture:Hide()
        else
            local barWidth = gcdBar.statusBar:GetWidth()
            local pipOffset = (queueWindowSec / gcdRemaining) * barWidth
            queuePipTexture:ClearAllPoints()
            if settings.fill_direction == "left" then
                queuePipTexture:SetPoint("TOP", gcdBar.statusBar, "TOPLEFT", pipOffset, 0)
                queuePipTexture:SetPoint("BOTTOM", gcdBar.statusBar, "BOTTOMLEFT", pipOffset, 0)
            else
                queuePipTexture:SetPoint("TOP", gcdBar.statusBar, "TOPRIGHT", -pipOffset, 0)
                queuePipTexture:SetPoint("BOTTOM", gcdBar.statusBar, "BOTTOMRIGHT", -pipOffset, 0)
            end
            queuePipTexture:Show()
        end
    end
end

---OnEvent handler for the GCD tracking event frame.
---@param self frame
---@param event string
---@param ... any
local function onEvent(self, event, ...)
    if event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if scheduleCast then
            scheduleCast:Cancel()
            scheduleCast = nil
        end
        if gcdBar then
            local _, _, _, isActive = getCooldownInfo()
            if not isActive then
                activeGCDStart = 0
                gcdBar:StopTimer()
            end
        end

    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_EMPOWER_START" then
        if gcdBar and activeGCDStart ~= 0 then
            activeGCDStart = 0
            gcdBar:StopTimer()
            updateInactiveBackground()
        end

    elseif event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        -- SENT: unit, target, castGUID, spellID
        -- CHANNEL_START / EMPOWER_STOP: unit, castGUID, spellID
        local castGUID, spellId
        if event == "UNIT_SPELLCAST_SENT" then
            castGUID, spellId = select(3, ...)
        else
            castGUID, spellId = select(2, ...)
        end

        local realLatency = GetTime() - castStarted
        if realLatency < 0.05 or realLatency > 0.6 then
            local _, _, _, ping = GetNetStats()
            realLatency = ping / 1000
        end

        currentCast = {
            castId = not issecretvalue(castGUID) and castGUID or nil,
            latency = realLatency,
            spellId = spellId,
            isChannel = event == "UNIT_SPELLCAST_CHANNEL_START",
            isEmpower = event == "UNIT_SPELLCAST_EMPOWER_STOP",
        }
        if event == "UNIT_SPELLCAST_CHANNEL_START" and gcdBar and activeGCDStart ~= 0 then
            activeGCDStart = 0
            gcdBar:StopTimer()
            updateInactiveBackground()
        end
        if scheduleCast then
            scheduleCast:Cancel()
        end
        scheduleCast = C_Timer.NewTimer(0, scheduleCastStart)

    elseif event == "CURRENT_SPELL_CAST_CHANGED" then
        castStarted = GetTime()

    elseif event == "ACTIONBAR_UPDATE_STATE" or event == "SPELL_UPDATE_COOLDOWN" then
        if castStarted ~= GetTime() then
            castStarted = 0
        end
        if event == "SPELL_UPDATE_COOLDOWN" and currentCast then
            scheduleCastStart()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Event registration
-- ---------------------------------------------------------------------------

local unitEvents = {
    "UNIT_SPELLCAST_SENT",
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
}

local regularEvents = {
    "CURRENT_SPELL_CAST_CHANGED",
    "ACTIONBAR_UPDATE_COOLDOWN",
    "ACTIONBAR_UPDATE_STATE",
    "SPELL_UPDATE_COOLDOWN",
}

local function enableTracking()
    if not eventFrame then return end
    for _, ev in ipairs(unitEvents) do
        eventFrame:RegisterUnitEvent(ev, "player")
    end
    for _, ev in ipairs(regularEvents) do
        eventFrame:RegisterEvent(ev)
    end
end

local function disableTracking()
    if not eventFrame then return end
    eventFrame:UnregisterAllEvents()
    if scheduleCast then
        scheduleCast:Cancel()
        scheduleCast = nil
    end
    currentCast = nil
    castStarted = 0
    activeGCDStart = 0
    if gcdBar then
        gcdBar:StopTimer()
        gcdBar.statusBar.leftText:SetText("")
        gcdBar.statusBar:Hide()
    end
    if queuePipTexture then queuePipTexture:Hide() end
    updateInactiveBackground()
end

-- ---------------------------------------------------------------------------
-- Texture helper
-- ---------------------------------------------------------------------------

local defaultTexture = [[Interface\AddOns\ClassUIEnhanced\Assets\Textures\StatusBar\bar_hyanda.png]]

---Apply icon size and placement. Mirrors the cast-bar convention:
---square sized to bar height, anchored left-outside, zoom-cropped.
local function applyIconLayout()
    if not gcdBar then return end
    local iconRegion = gcdBar.statusBar.icon
    local iconSize = getSettings().height
    if iconSize < 1 then iconSize = 1 end

    iconRegion:SetSize(iconSize, iconSize)
    iconRegion:ClearAllPoints()
    iconRegion:SetPoint("TOPRIGHT", gcdBar.statusBar, "TOPLEFT", 0, 0)
    iconRegion:SetPoint("BOTTOMRIGHT", gcdBar.statusBar, "BOTTOMLEFT", 0, 0)

    if iconRegion:IsShown() then
        iconRegion:SetTexCoord(private.Util.GetIconZoomCoords(iconSize, iconSize))
    end
end

---Apply an LSM texture key to the bar and latency overlay.
---@param texture string  LSM "statusbar" key; "" = solid white
local function applyTexture(texture)
    if not gcdBar then return end
    if texture and texture ~= "" then
        local lsmPath = LibSharedMedia:Fetch("statusbar", texture, true)
        if lsmPath then
            gcdBar:SetStatusBarTexture(lsmPath)
            if latencyTexture then latencyTexture:SetTexture(lsmPath) end
            if queuePipTexture then queuePipTexture:SetTexture(lsmPath) end
            return
        end
    end
    gcdBar:SetStatusBarTexture(defaultTexture)
    if latencyTexture then latencyTexture:SetTexture(defaultTexture) end
    if queuePipTexture then queuePipTexture:SetTexture(defaultTexture) end
end

-- ---------------------------------------------------------------------------
-- Lifecycle methods
-- ---------------------------------------------------------------------------

globalCooldown.Initialize = function()
    if not containerFrame then
        containerFrame = CreateFrame("Frame", "CUE_GlobalCooldown_Container", UIParent)
        containerFrame:SetSize(200, 8)

        gcdBar = framework:CreateTimeBar(containerFrame, defaultTexture, 200, 8, 0, nil, "CUE_GlobalCooldown_Bar")
        gcdBar:SetPoint("TOPLEFT", containerFrame, "TOPLEFT", 0, 0)
        gcdBar:SetPoint("BOTTOMRIGHT", containerFrame, "BOTTOMRIGHT", 0, 0)
        gcdBar:EnableMouse(false)
        gcdBar.statusBar:Hide()

        gcdBar:SetHook("OnTimerEnd", function(statusBar)
            activeGCDStart = 0
            statusBar.leftText:SetText("")
            statusBar:Hide()
            if queuePipTexture then queuePipTexture:Hide() end
            updateInactiveBackground()
        end)

        gcdBar:SetHook("OnUpdate", function(self, statusBar)
            if not getSettings().show_duration then return end
            local _, endTime = statusBar:GetMinMaxValues()
            local remaining = endTime - GetTime()
            if remaining > 0 then
                statusBar.rightText:SetText(format("%.1f", remaining))
            else
                statusBar.rightText:SetText("")
            end
        end)

        latencyTexture = gcdBar.statusBar:CreateTexture(nil, "BORDER")
        latencyTexture:SetTexture(defaultTexture)
        latencyTexture:SetVertexColor(1, 0, 0, 0.8)
        latencyTexture:SetPoint("TOPRIGHT", gcdBar.statusBar, "TOPRIGHT", 0, 0)
        latencyTexture:SetPoint("BOTTOMRIGHT", gcdBar.statusBar, "BOTTOMRIGHT", 0, 0)
        latencyTexture:SetWidth(1)

        queuePipTexture = gcdBar.statusBar:CreateTexture(nil, "OVERLAY")
        queuePipTexture:SetTexture(defaultTexture)
        queuePipTexture:SetVertexColor(1, 1, 0, 0.8)
        queuePipTexture:SetWidth(2)
        queuePipTexture:Hide()

        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", onEvent)
    end

    if getEnabled() then
        enableTracking()
    end

    globalCooldown.Refresh()
end

globalCooldown.Refresh = function()
    if not containerFrame or not gcdBar then return end

    local settings = getSettings()

    applyTexture(settings.texture)

    local bc = settings.bar_color
    gcdBar:SetStatusBarColor(bc[1], bc[2], bc[3], bc[4])

    gcdBar:SetDirection(settings.fill_direction)

    local lc = settings.latency_color
    if latencyTexture then
        latencyTexture:SetVertexColor(lc[1], lc[2], lc[3], lc[4])
        latencyTexture:SetAlpha(settings.show_latency and 1 or 0)
        latencyTexture:ClearAllPoints()
        if settings.fill_direction == "left" then
            latencyTexture:SetPoint("TOPLEFT", gcdBar.statusBar, "TOPLEFT", 0, 0)
            latencyTexture:SetPoint("BOTTOMLEFT", gcdBar.statusBar, "BOTTOMLEFT", 0, 0)
        else
            latencyTexture:SetPoint("TOPRIGHT", gcdBar.statusBar, "TOPRIGHT", 0, 0)
            latencyTexture:SetPoint("BOTTOMRIGHT", gcdBar.statusBar, "BOTTOMRIGHT", 0, 0)
        end
    end

    if queuePipTexture then
        local qc = settings.queue_pip_color
        queuePipTexture:SetVertexColor(qc[1], qc[2], qc[3], qc[4])
        if not settings.show_queue_pip then
            queuePipTexture:Hide()
        end
    end

    private.Util.ApplyFontProfile(gcdBar.statusBar.rightText, settings.duration_font, gcdBar.statusBar)
    private.Util.ApplyFontProfile(gcdBar.statusBar.leftText, settings.spell_name_font, gcdBar.statusBar)

    if not settings.show_icon then
        gcdBar.statusBar.icon:Hide()
    end

    if containerFrame.cueAnchorOwnsWidth then
        containerFrame:SetHeight(settings.height)
    else
        containerFrame:SetSize(settings.width, settings.height)
    end
    applyIconLayout()
    gcdBar.statusBar.spark:Hide()
    gcdBar.statusBar.dontShowSpark = true

    if private.isEditMode then
        containerFrame:Show()
        if not isPreview then
            isPreview = true
            -- A GCD still running from before Edit Mode would keep DF's OnUpdate
            -- writing over the preview and, at its end, fire OnTimerEnd, which
            -- hides the bar. Stop it first; the hook's Hide is undone just below.
            gcdBar:StopTimer()
            gcdBar.statusBar:Show()
            gcdBar.statusBar:SetMinMaxValues(0, 100)
            gcdBar.statusBar:SetValue(70)
        end
        gcdBar.statusBar.rightText:SetText(settings.show_duration and "1.2" or "")
        gcdBar.statusBar.leftText:SetText(settings.show_spell_name and "Spell Name" or "")
        if queuePipTexture and settings.show_queue_pip then
            local queueWindowSec = (tonumber(C_CVar.GetCVar("SpellQueueWindow")) or 400) / 1000
            local previewGCD = 1.5
            if queueWindowSec >= previewGCD then
                queuePipTexture:Hide()
            else
                local barWidth = gcdBar.statusBar:GetWidth()
                local pipOffset = (queueWindowSec / previewGCD) * barWidth
                queuePipTexture:ClearAllPoints()
                if settings.fill_direction == "left" then
                    queuePipTexture:SetPoint("TOP", gcdBar.statusBar, "TOPLEFT", pipOffset, 0)
                    queuePipTexture:SetPoint("BOTTOM", gcdBar.statusBar, "BOTTOMLEFT", pipOffset, 0)
                else
                    queuePipTexture:SetPoint("TOP", gcdBar.statusBar, "TOPRIGHT", -pipOffset, 0)
                    queuePipTexture:SetPoint("BOTTOM", gcdBar.statusBar, "BOTTOMRIGHT", -pipOffset, 0)
                end
                queuePipTexture:Show()
            end
        end
        return
    end

    if isPreview then
        isPreview = false
        gcdBar.statusBar:SetScript("OnUpdate", nil)
        gcdBar.statusBar:SetMinMaxValues(0, 100)
        gcdBar.statusBar:SetValue(0)
        gcdBar.statusBar.leftText:SetText("")
        gcdBar.statusBar.rightText:SetText("")
        gcdBar.statusBar:Hide()
        if queuePipTexture then queuePipTexture:Hide() end
    end

    if not settings.enabled or not private.Anchor.IsVisibleForComponent(globalCooldown.name) then
        containerFrame:Hide()
        return
    end

    containerFrame:Show()
    updateInactiveBackground()
end

globalCooldown.OnEnable = function()
    enableTracking()
    globalCooldown.Refresh()
end

globalCooldown.OnDisable = function()
    disableTracking()
    if containerFrame then containerFrame:Hide() end
end

globalCooldown.GetFrame = function()
    return containerFrame
end

globalCooldown.GetComponentName = function()
    return globalCooldown.name
end

globalCooldown.GetComponentSize = function()
    local settings = getSettings()
    return settings.width, settings.height
end

-- ---------------------------------------------------------------------------
-- Export + register
-- ---------------------------------------------------------------------------

private.GlobalCooldown = globalCooldown
private.ComponentManager.RegisterComponent("GlobalCooldown", globalCooldown)
