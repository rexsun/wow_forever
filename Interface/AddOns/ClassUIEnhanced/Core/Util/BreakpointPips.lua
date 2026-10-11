--[[
    BreakpointPips — shared renderer for user-defined resource breakpoints
    on a StatusBar: overlay pip lines, background zones with secret-safe
    auto-hide alpha curves, and a bar fill ColorCurve.

    Two consumers ("hosts"): the primary resource bar (PrimaryResources, DF
    power bar) and the SecondaryResources continuous power bar (Elemental
    Maelstrom, Balance Astral Power, Shadow Insanity). Hosts are created once
    by their owning component and mutated in place; per-host render state
    (texture pools, curves) lives in this module keyed by host reference.

    Storage: private.profile.breakpoint_pips.pips, keyed per spec and bar:
      - "CLASS-specIndex"          primary bar, every spec except the moved ones
      - "CLASS-specIndex-MANA"     primary (mana) bar of the moved specs
      - "CLASS-specIndex-<TOKEN>"  secondary continuous bar of the moved specs
    A plain "CLASS-specIndex" key for a moved spec can only be legacy
    pre-2.13.2 data; ProfileManager.MigrateBreakpointPipKeys re-keys it to the
    -<TOKEN> key on profile load and segment import.

    Dynamic updates (zone alpha, fill color) evaluate prebuilt curves via
    UnitPowerPercent — secret-safe and allocation-free, so UpdateDynamic is
    safe on the per-tick UNIT_POWER_FREQUENT path. Curve construction happens
    only in Apply (layout passes).
--]]

local _
---@type string, private
local addonName, private = ...

---@class private : table
---@field BreakpointPips breakpointpips

---@class breakpointpips : table

---@class BreakpointPipHost : table
---@field bar StatusBar?  host StatusBar; also parent of pip/zone textures
---@field key string?  breakpoint_pips storage key for the current spec/bar
---@field unit string  unit the power belongs to ("player")
---@field getPowerType fun(): integer?  live Enum.PowerType of the bar (nil = unknown)
---@field isVertical fun(): boolean  live bar orientation
---@field baseColor number[]  {r,g,b,a} fill-curve base color (stable table, owner-mutated)

---@class BreakpointPipState
---@field pipTextures Texture[]
---@field zoneTextures Texture[]
---@field activeZones {tex: Texture, curve: any}[]
---@field fillColorCurve table?

---@type breakpointpips
local breakpointPips = {}

---Per-host render state. Hosts are created once and mutated in place (stable
---identity), so a plain table cannot leak; if a caller ever recreates hosts,
---switch to __mode="k" per the GlowEffect curve-cache convention.
---@type table<BreakpointPipHost, BreakpointPipState>
local hostState = {}

---Specs whose combat resource moved from the primary bar to the
---SecondaryResources continuous bar in 2.13.2. Mirrors
---primaryManaOverrideSpecs in Components/PrimaryResources.lua (which answers
---"which specs pin mana on the primary bar"); this map adds the derived
---secondary key token and power type. Keep the two in sync.
---@type table<string, table<integer, {token: string, powerType: integer}>>
local movedSpecs = {
    SHAMAN = { [1] = { token = "MAELSTROM", powerType = Enum.PowerType.Maelstrom } }, -- Elemental
    DRUID = { [1] = { token = "LUNAR_POWER", powerType = Enum.PowerType.LunarPower } }, -- Balance
    PRIEST = { [3] = { token = "INSANITY", powerType = Enum.PowerType.Insanity } }, -- Shadow
}

---Storage key + power type for the current spec's pip list on the given bar.
---target "primary": plain "CLASS-spec" key (powerType nil = use the bar's own
---live power); for moved specs "CLASS-spec-MANA" plus Enum.PowerType.Mana.
---target "secondary": "CLASS-spec-TOKEN" plus the continuous power for moved
---specs; nil for every other spec (no continuous secondary bar).
---@param target "primary"|"secondary"
---@return string? key
---@return integer? powerType
function breakpointPips.GetKeyForCurrentSpec(target)
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not specIndex or specIndex == 0 then return nil end
    local _, class = UnitClass("player")
    local moved = movedSpecs[class] and movedSpecs[class][specIndex]
    local baseKey = class .. "-" .. specIndex
    if target == "secondary" then
        if not moved then return nil end
        return baseKey .. "-" .. moved.token, moved.powerType
    end
    if moved then
        return baseKey .. "-MANA", Enum.PowerType.Mana
    end
    return baseKey, nil
end

---Whether pips are enabled for the given storage key: master toggle AND the
---per-key override (missing key = enabled).
---@param key string?
---@return boolean
function breakpointPips.IsEnabledForKey(key)
    local pipSettings = private.profile.breakpoint_pips
    if not pipSettings or not pipSettings.enabled then return false end
    local map = pipSettings.per_spec_enabled
    if type(map) ~= "table" then return true end
    if not key then return true end
    return map[key] ~= false
end

---Get the pip list for the host's key, or an empty table.
---@param host BreakpointPipHost
---@return breakpoint_pip[]
local function getPipsForHost(host)
    if not breakpointPips.IsEnabledForKey(host.key) then return {} end
    if not host.key then return {} end
    return private.profile.breakpoint_pips.pips[host.key] or {}
end

---Get or lazily create the render state for a host.
---@param host BreakpointPipHost
---@return BreakpointPipState
local function getState(host)
    local state = hostState[host]
    if not state then
        state = { pipTextures = {}, zoneTextures = {}, activeZones = {} }
        hostState[host] = state
    end
    return state
end

---Convert a pip's stored value to a 0-1 fraction based on pip_mode.
---Percent mode: pct / 100. Absolute mode: pct / UnitPowerMax of the host power.
---@param host BreakpointPipHost
---@param pct number  the pip's stored value
---@return number  0-1 fraction
local function pipValueToFraction(host, pct)
    local mode = private.profile.breakpoint_pips and private.profile.breakpoint_pips.pip_mode or "percent"
    if mode == "absolute" then
        local powerType = host.getPowerType()
        local maxPower = powerType and UnitPowerMax(host.unit, powerType) or 0
        if maxPower > 0 then
            return pct / maxPower
        end
        return 0
    end
    return pct / 100
end

---Create or reuse a pip texture from the host's pool (OVERLAY lines).
---@param host BreakpointPipHost
---@param state BreakpointPipState
---@param index number  1-based index
---@return Texture
local function getOrCreatePipTexture(host, state, index)
    if state.pipTextures[index] then return state.pipTextures[index] end
    local tex = host.bar:CreateTexture(nil, "OVERLAY")
    tex:SetSnapToPixelGrid(true)
    tex:SetTexelSnappingBias(0)
    state.pipTextures[index] = tex
    return tex
end

---Create or reuse a zone texture (BORDER layer, between bg and fill).
---@param host BreakpointPipHost
---@param state BreakpointPipState
---@param index number  1-based index
---@return Texture
local function getOrCreateZoneTexture(host, state, index)
    if state.zoneTextures[index] then return state.zoneTextures[index] end
    local tex = host.bar:CreateTexture(nil, "BORDER")
    tex:SetSnapToPixelGrid(true)
    tex:SetTexelSnappingBias(0)
    state.zoneTextures[index] = tex
    return tex
end

---Update zone texture alphas from the current power via prebuilt curves.
---Secret-safe; allocation-free — callable per power tick.
---@param host BreakpointPipHost
local function updateZoneAlphas(host)
    local state = hostState[host]
    if not state or #state.activeZones == 0 then return end
    local powerType = host.getPowerType()
    if powerType == nil then return end
    for _, zone in ipairs(state.activeZones) do
        local alpha = UnitPowerPercent(host.unit, powerType, false, zone.curve)
        zone.tex:SetAlpha(alpha)
    end
end

---Update bar fill color from the current power via the prebuilt ColorCurve.
---Secret-safe; allocation-free — callable per power tick.
---@param host BreakpointPipHost
local function updateFillColor(host)
    local state = hostState[host]
    if not state or not state.fillColorCurve then return end
    local powerType = host.getPowerType()
    if powerType == nil then return end
    local color = UnitPowerPercent(host.unit, powerType, false, state.fillColorCurve)
    host.bar:SetStatusBarColor(color.r, color.g, color.b, color.a)
end

---Per-power-update pass: zone alphas + fill color. No-ops when Apply built
---no zones/curve for this host (e.g. pips disabled or host cleared).
---@param host BreakpointPipHost
function breakpointPips.UpdateDynamic(host)
    updateZoneAlphas(host)
    updateFillColor(host)
end

---Hide all pip/zone textures and drop curves for the host. Call when the
---host bar is reused for a different resource (pooled bars) or the owning
---component is disabled. The bar's fill color is left to the owner's own
---color application.
---@param host BreakpointPipHost
function breakpointPips.Clear(host)
    local state = hostState[host]
    if not state then return end
    for i = 1, #state.pipTextures do
        state.pipTextures[i]:Hide()
    end
    for i = 1, #state.zoneTextures do
        state.zoneTextures[i]:Hide()
    end
    wipe(state.activeZones)
    state.fillColorCurve = nil
end

---Position and show/hide pip textures and rebuild zone/fill curves from the
---host's stored pip list. Call from layout passes after the host bar has
---been sized — never from per-tick power updates (curves allocate here).
---The owner must set host.bar, host.key and refresh host.baseColor first.
---@param host BreakpointPipHost
function breakpointPips.Apply(host)
    if not host.bar then return end
    local state = getState(host)

    local pipList = getPipsForHost(host)
    local pipSettings = private.profile.breakpoint_pips
    local pipWidth = pipSettings and pipSettings.pip_width or 2
    local barWidth = host.bar:GetWidth()
    local barHeight = host.bar:GetHeight()
    local isVertical = host.isVertical()

    local showLine = pipSettings and pipSettings.show_pip_line ~= false

    -- Render pip overlay lines
    for i, pip in ipairs(pipList) do
        local tex = getOrCreatePipTexture(host, state, i)
        tex:ClearAllPoints()

        local frac = pipValueToFraction(host, pip.pct)
        if isVertical then
            local yPos = barHeight * frac
            tex:SetPoint("CENTER", host.bar, "BOTTOM", 0, yPos)
            private.Pixel.SetSize(tex, barWidth, pipWidth)
        else
            local xPos = barWidth * frac
            tex:SetPoint("CENTER", host.bar, "LEFT", xPos, 0)
            private.Pixel.SetSize(tex, pipWidth, barHeight)
        end

        local c = pip.color
        tex:SetColorTexture(private.Util.Color(c))
        tex:SetShown(showLine)
    end

    for i = #pipList + 1, #state.pipTextures do
        state.pipTextures[i]:Hide()
    end

    -- Build zone assignments: zoneIndex -> color
    -- Zones: 1 = before pip[1], 2 = between pip[1] and pip[2], ..., n+1 = after pip[n]
    -- Higher pip index wins on conflict (natural overwrite order).
    local zoneAssignments = {}
    for i, pip in ipairs(pipList) do
        if pip.zone_enabled and pip.zone_color then
            local dir = pip.zone_direction or "previous"
            if dir == "previous" then
                zoneAssignments[i] = pip.zone_color
            else
                zoneAssignments[i + 1] = pip.zone_color
            end
        end
    end

    -- Render zone textures and build alpha curves
    wipe(state.activeZones)
    local zoneIdx = 0
    for zoneIndex, zc in pairs(zoneAssignments) do
        zoneIdx = zoneIdx + 1
        local tex = getOrCreateZoneTexture(host, state, zoneIdx)
        tex:ClearAllPoints()

        local startFrac = (zoneIndex > 1) and pipValueToFraction(host, pipList[zoneIndex - 1].pct) or 0
        local endFrac = (zoneIndex <= #pipList) and pipValueToFraction(host, pipList[zoneIndex].pct) or 1

        if isVertical then
            local startPos = barHeight * startFrac
            local endPos = barHeight * endFrac
            tex:SetPoint("BOTTOMLEFT", host.bar, "BOTTOMLEFT", 0, startPos)
            tex:SetPoint("TOPRIGHT", host.bar, "BOTTOMRIGHT", 0, endPos)
        else
            local startPos = barWidth * startFrac
            local endPos = barWidth * endFrac
            tex:SetPoint("TOPLEFT", host.bar, "TOPLEFT", startPos, 0)
            tex:SetPoint("BOTTOMRIGHT", host.bar, "BOTTOMLEFT", endPos, 0)
        end

        local zoneAlpha = zc[4] or 1
        local autoHide = pipSettings and pipSettings.zone_auto_hide ~= false

        if autoHide then
            tex:SetColorTexture(zc[1], zc[2], zc[3], 1)
            tex:SetAlpha(0)
            tex:Show()

            -- Step curve: zone alpha below threshold, 0 at/above
            local curve = C_CurveUtil.CreateCurve()
            curve:SetType(Enum.LuaCurveType.Step)
            curve:AddPoint(0.0, zoneAlpha)
            curve:AddPoint(endFrac, 0.0)
            state.activeZones[zoneIdx] = {tex = tex, curve = curve}
        else
            tex:SetAlpha(1)
            tex:SetColorTexture(zc[1], zc[2], zc[3], zoneAlpha)
            tex:Show()
        end
    end

    for i = zoneIdx + 1, #state.zoneTextures do
        state.zoneTextures[i]:Hide()
    end

    -- Evaluate initial alpha for auto-hide zones
    if #state.activeZones > 0 then
        updateZoneAlphas(host)
    end

    -- Build fill color curve from pips with bar_color_enabled
    local hasBarColor = false
    for _, pip in ipairs(pipList) do
        if pip.bar_color_enabled and pip.bar_color then
            hasBarColor = true
            break
        end
    end

    if hasBarColor then
        local baseR, baseG, baseB, baseA = host.baseColor[1], host.baseColor[2], host.baseColor[3], host.baseColor[4]
        local interpType = (pipSettings.fill_interpolation == "linear") and Enum.LuaCurveType.Linear or Enum.LuaCurveType.Step
        local curve = C_CurveUtil.CreateColorCurve()
        curve:SetType(interpType)
        curve:AddPoint(0.0, CreateColor(baseR, baseG, baseB, baseA or 1))

        local lastFrac = 0
        for _, pip in ipairs(pipList) do
            if pip.bar_color_enabled and pip.bar_color then
                local c = pip.bar_color
                local frac = pipValueToFraction(host, pip.pct)
                curve:AddPoint(frac, CreateColor(private.Util.Color(c)))
                lastFrac = frac
            end
        end

        -- Revert to base color above the last fill pip (for linear interpolation)
        if lastFrac < 1 then
            curve:AddPoint(1.0, CreateColor(baseR, baseG, baseB, baseA or 1))
        end

        state.fillColorCurve = curve
    else
        state.fillColorCurve = nil
    end

    -- Evaluate initial fill color
    if state.fillColorCurve then
        updateFillColor(host)
    end
end

private.BreakpointPips = breakpointPips
