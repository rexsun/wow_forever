local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
local View = YHUD and YHUD.View
local I = View and View._internal
if not I then return end

local GUI2 = YUI.GUI2
local Spell = YUI.API and YUI.API.Spell
local WHITE = "Interface\\Buttons\\WHITE8x8"
local function Host(slot) return slot._yhudBarHost or slot end
local function RaiseOverlay(overlay, level)
    if overlay and overlay:GetFrameLevel() < level then overlay:SetFrameLevel(level) end
end
local function EntrySpellID(entry, monitor)
    return monitor and monitor._yhudRuntimeSpellID or entry.overrideSpellId
        or entry.spellId or entry.spellID or entry.sourceParams and entry.sourceParams.spellID
end
local function PublicMaximum(value)
    if _G.issecretvalue and _G.issecretvalue(value) then return nil end
    if type(value) ~= "number" or value ~= value or value < 1 or value > 100 then return nil end
    return math.floor(value)
end

function View:ReadBarProgressMaximum(entry, monitor, progress)
    if progress.source == "aura-stacks" then
        if not YHUD:CanUseBarAuraProgress(entry, monitor) then return nil end
        if progress.maximumMode == "custom" then return progress.maximum end
        local spellID = EntrySpellID(entry, monitor)
        if Spell and Spell.ReadMaxCumulativeAuraApplications then
            return Spell.ReadMaxCumulativeAuraApplications(spellID)
        end
    elseif progress.source == "spell-charges" then
        if not YHUD:CanUseBarChargeProgress(entry, monitor) then return nil end
        local spellID = EntrySpellID(entry, monitor)
        if Spell and Spell.ReadChargeResourceDisplay then
            local state = Spell.ReadChargeResourceDisplay(spellID, {})
            local maximum = state and state.available and PublicMaximum(state.maxValue)
            -- This cold structural query must never keep a charge value/object.
            if state then state.valueRaw, state.rechargeDurationRaw = nil, nil end
            return maximum and maximum > 1 and maximum or nil
        end
    end
end

local function HideChargeLayers(slot)
    for _, layer in ipairs(slot._yhudChargeColorLayers or {}) do
        layer.root:Hide()
        if layer.rechargeRoot then layer.rechargeRoot:Hide() end
    end
end

local function RechargeColor(color, custom)
    return { color.r or color[1], color.g or color[2], color.b or color[3],
        (color.a or color[4] or 1) * (custom and 1 or .5) }
end

function View:ConfigureBarRechargeAppearance(slot, runtime, monitor)
    local appearance = monitor.appearanceOverride or {}
    slot._yhudBarRechargeCustom = appearance.rechargeColor ~= nil
    local color = appearance.rechargeColor or appearance.fillColor or runtime.fillColor
    GUI2:ConfigureProjectedStatusBarRechargeAppearance(slot,
        RechargeColor(color, slot._yhudBarRechargeCustom), runtime.statusBarStyle)
end

local function ApplyRecharge(slot, state)
    if not slot._yhudBarValueValid or not state or state.durationMode ~= "charge" then
        GUI2:SetProjectedStatusBarRecharge(slot, nil)
    elseif state.durationObject then
        GUI2:SetProjectedStatusBarRecharge(slot, state.durationObject, state.opaqueRevision)
    end
end

function View:ClearBarProgress(slot, preserveRestoredDriver)
    if not slot then return end
    local countGate = slot._yhudNativeCountGate
    local ownsValueMode = slot._yhudBarValueModeOwned
    if countGate and ownsValueMode then
        countGate.driver:Hide()
        countGate.driver:SetValue(0)
        countGate.lastPublicValue = nil
    end
    if countGate then countGate.additionalDrivers = nil end
    local colorGate = slot._yhudNativeColorGate
    if colorGate then
        colorGate.driver, colorGate.additionalDrivers, colorGate.lastPublicValue = nil, nil, nil
    end
    if ownsValueMode and slot._yhudBarTimeDriver then
        slot.nativeStatusBar = slot._yhudBarTimeDriver
        slot.durationStatusBar = slot.nativeStatusBar
    end
    if ownsValueMode then
        if GUI2.SetProjectedStatusBarRecharge then GUI2:SetProjectedStatusBarRecharge(slot, nil) end
        if slot.gui2RechargeSeparate then GUI2:ConfigureProjectedStatusBarRechargeAppearance(slot, nil) end
        if preserveRestoredDriver then
            slot.gui2ProjectedValueMode = false
        elseif GUI2.SetProjectedStatusBarValueMode then
            GUI2:SetProjectedStatusBarValueMode(slot, false)
        end
    end
    HideChargeLayers(slot)
    for _, line in ipairs(slot._yhudBarTicks or {}) do line:Hide() end
    slot._yhudBarProgress, slot._yhudBarMaximum = nil, nil
    slot._yhudBarTickSignature, slot._yhudBarPublicValue = nil, nil
    slot._yhudChargeColorLayerCount = 0
    slot._yhudChargeColorTopLevel = nil
    slot._yhudBarValueValid = nil
    slot._yhudBarValueModeOwned = nil
    slot._yhudBarRechargeCustom = nil
    slot._yhudBarCountdownMode, slot._yhudBarCountdownRevision = nil, nil
    slot._yhudNativeProgressInputs = nil
end

function View:RaiseBarTickLayers(slot)
    local overlay = slot._yhudBarTickOverlay
    if not overlay then return end
    local level = math.max(slot.gui2AuraBarThresholdTopLevel or 0,
        slot.nativeVisibleStatusBar and slot.nativeVisibleStatusBar:GetFrameLevel() or Host(slot):GetFrameLevel(),
        slot._yhudChargeColorTopLevel or 0)
    -- Moving the clip also moves its children; pin the drawing plane afterward
    -- so the border remains above both, including after threshold-layer changes.
    local clip = slot._yhudBarTickClip
    if clip and clip:GetFrameLevel() ~= level + 1 then clip:SetFrameLevel(level + 1) end
    if overlay:GetFrameLevel() ~= level + 1 then overlay:SetFrameLevel(level + 1) end
    local textOverlay = slot.durationOverlay or slot.resourceOverlay
    if slot.SetDurationTextLayer and textOverlay and textOverlay:GetFrameLevel() < level + 2 then
        slot:SetDurationTextLayer(level + 2)
    else
        RaiseOverlay(textOverlay, level + 2)
    end
    RaiseOverlay(slot.nativeBorderOverlay, level + 2)
    RaiseOverlay(slot.resourceBorderOverlay, level + 2)
end

function View:LayoutBarTicks(slot, runtime, maximum)
    local progress = slot._yhudBarProgress
    local ticks = progress and progress.ticks
    if not ticks then return end
    local width, height = slot.gui2ResourceWidth or slot.barWidth or runtime.barWidth,
        slot.gui2ResourceHeight or slot.barHeight or runtime.barHeight
    width, height = math.max(1, width or 1), math.max(1, height or 1)
    local fillDirection = slot.gui2ResourceFillDirection or runtime.fillDirection or "forward"
    local signature = table.concat({ width, height, maximum or 0, runtime.orientation or "horizontal",
        fillDirection, ticks.mode, ticks.step, ticks.thickness,
        ticks.color.r, ticks.color.g, ticks.color.b, ticks.color.a,
        table.concat(ticks.positions, ",") }, ":")
    local unchanged = signature == slot._yhudBarTickSignature
    slot._yhudBarTickSignature = signature
    if unchanged then self:RaiseBarTickLayers(slot); return end
    local positions = {}
    if ticks.mode == "custom" then
        for index, position in ipairs(ticks.positions) do positions[index] = position / 100 end
    elseif ticks.mode ~= "off" and maximum and YHUD:IsBarTickModeAllowed(progress.source, ticks.mode) then
        local step = ticks.mode == "spell-charges" and 1 or ticks.step
        for count = step, maximum - 1, step do positions[#positions + 1] = count / maximum end
    end
    slot._yhudBarTicks = slot._yhudBarTicks or {}
    if #positions > 0 and not slot._yhudBarTickOverlay then
        local clip = GUI2:CreateFrame(Host(slot), { background = false, border = false })
        clip:SetAllPoints(slot.track)
        clip:SetClipsChildren(true)
        -- Textures must belong to a child of the clip. Layering the border
        -- above them cannot hide pixels extending outside the track itself.
        local overlay = GUI2:CreateFrame(clip, { background = false, border = false })
        overlay:SetAllPoints(slot.track)
        slot._yhudBarTickClip = clip
        slot._yhudBarTickOverlay = overlay
    end
    local overlay = slot._yhudBarTickOverlay
    self:RaiseBarTickLayers(slot)
    local pixel = GUI2.GetPixelSize and GUI2:GetPixelSize(Host(slot), 1, 1) or GUI2.mult or 1
    local thickness = math.max(pixel, ticks.thickness * pixel)
    local vertical = runtime.orientation == "vertical"
    local reverse = fillDirection == "reverse" or fillDirection == "down"
        or not vertical and fillDirection == "right"
    for index, position in ipairs(positions) do
        local line = slot._yhudBarTicks[index]
        if not line then
            line = overlay:CreateTexture(nil, "OVERLAY")
            line:SetTexture(WHITE)
            if GUI2.ApplyTexturePixelPolicy then GUI2:ApplyTexturePixelPolicy(line) end
            slot._yhudBarTicks[index] = line
        end
        if reverse then position = 1 - position end
        line:ClearAllPoints()
        if slot._yhudBarStackLive then
            -- Configure before Aura restrictions apply. Native fill geometry
            -- follows later track resizes without touching the live subtree.
            local drivers = slot._yhudBarTickDrivers or {}
            slot._yhudBarTickDrivers = drivers
            local driver = drivers[index]
            if not driver then
                driver = CreateFrame("StatusBar", nil, overlay)
                driver:SetStatusBarTexture(WHITE)
                driver:SetMinMaxValues(0, 1)
                driver:SetReverseFill(false)
                driver:GetStatusBarTexture():SetAlpha(0)
                drivers[index] = driver
            end
            driver:SetAllPoints(slot.track)
            driver:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
            driver:SetValue(position)
            local edge = driver:GetStatusBarTexture()
            if vertical then
                line:SetHeight(thickness)
                line:SetPoint("LEFT", edge, "TOPLEFT")
                line:SetPoint("RIGHT", edge, "TOPRIGHT")
            else
                line:SetWidth(thickness)
                line:SetPoint("TOP", edge, "TOPRIGHT")
                line:SetPoint("BOTTOM", edge, "BOTTOMRIGHT")
            end
        elseif vertical then
            line:SetHeight(thickness)
            line:SetPoint("LEFT", slot.track, "BOTTOMLEFT", 0, height * position)
            line:SetPoint("RIGHT", slot.track, "BOTTOMRIGHT", 0, height * position)
        else
            line:SetWidth(thickness)
            line:SetPoint("TOP", slot.track, "TOPLEFT", width * position, 0)
            line:SetPoint("BOTTOM", slot.track, "BOTTOMLEFT", width * position, 0)
        end
        line:SetVertexColor(ticks.color.r, ticks.color.g, ticks.color.b, ticks.color.a)
        line:Show()
    end
    for index = #positions + 1, #slot._yhudBarTicks do slot._yhudBarTicks[index]:Hide() end
end

-- Integer gates expose one complete track at the boundary. The outer native
-- fill clip still owns the real fill amount; no restricted value or geometry
-- is inspected, compared, cached or converted by Lua.
function View:ConfigureChargeBarColors(slot, runtime, monitor)
    HideChargeLayers(slot)
    local appearance = monitor.appearanceOverride or {}
    local policy = appearance.stackThresholds
    if not (slot._yhudBarProgress and slot._yhudBarProgress.source == "spell-charges"
        and policy and policy.enabled and slot.nativeFillClip) then return end
    local layers = slot._yhudChargeColorLayers or {}
    slot._yhudChargeColorLayers = layers
    local base = appearance.fillColor or runtime.fillColor
    local definitions = { { trigger = 0, color = base, base = true } }
    if policy.low.enabled then
        definitions[1] = { trigger = 0, color = policy.low.color }
        definitions[#definitions + 1] = { trigger = policy.low.value + 1, color = base, base = true }
    end
    if policy.high.enabled then
        definitions[#definitions + 1] = { trigger = policy.high.value, color = policy.high.color }
    end
    for index, definition in ipairs(definitions) do
        local layer = layers[index]
        if not layer then
            layer = { root = GUI2:CreateFrame(slot.nativeFillClip, { background = false, border = false }) }
            layer.gate = GUI2:CreateAuraApplicationGate(layer.root, slot.track,
                { operator = "gte", value = 1 }, slot.barWidth or runtime.barWidth,
                slot.barHeight or runtime.barHeight)
            layer.driver, layer.clip = layer.gate.driver, layer.gate.clip
            layer.material = _G.CreateFrame("StatusBar", nil, layer.clip)
            layers[index] = layer
        end
        layer.root:SetAllPoints(slot.track)
        layer.root:SetFrameLevel(slot.nativeVisibleStatusBar:GetFrameLevel() + index * 3)
        layer.gate.lowerClip:SetFrameLevel(layer.root:GetFrameLevel())
        layer.clip:SetFrameLevel(layer.root:GetFrameLevel() + 1)
        layer.material:SetFrameLevel(layer.root:GetFrameLevel() + 2)
        layer.trigger = definition.trigger
        layer.baseColor = definition.base
        if definition.trigger > 0 then
            GUI2:ConfigureAuraApplicationGate(layer.gate, slot.track,
                { operator = "gte", value = definition.trigger },
                slot.barWidth or runtime.barWidth, slot.barHeight or runtime.barHeight)
        else
            layer.gate.width = nil
            layer.gate.lowerClip:ClearAllPoints()
            layer.gate.lowerClip:SetAllPoints(slot.track)
            layer.clip:ClearAllPoints()
            layer.clip:SetAllPoints(slot.track)
        end
        local material, style = layer.material, runtime.statusBarStyle or {}
        material:SetAllPoints(slot.track)
        material:SetMinMaxValues(0, 1)
        material:SetValue(1)
        material:SetStatusBarTexture(style.texture or WHITE)
        material:GetStatusBarTexture():SetTexCoord(style.textureU0 or 0, style.textureU1 or 1,
            style.textureV0 or 0, style.textureV1 or 1)
        GUI2:ApplyNativeStatusBarStyle(material, style, runtime.orientation, runtime.fillDirection, true)
        local color = definition.color
        material:SetStatusBarColor(color.r or color[1], color.g or color[2], color.b or color[3], color.a or color[4] or 1)
        -- Mirror only the gate's geometry into the recovery clip. Sharing its
        -- native driver keeps available/recovery thresholds on the same sample.
        if not slot._yhudBarRechargeCustom then
            if not layer.rechargeRoot then
                layer.rechargeRoot = GUI2:CreateFrame(slot.gui2RechargeClip, { background = false, border = false })
                layer.rechargeLowerClip = GUI2:CreateFrame(layer.rechargeRoot, { background = false, border = false })
                layer.rechargeLowerClip:SetClipsChildren(true)
                layer.rechargeClip = GUI2:CreateFrame(layer.rechargeLowerClip, { background = false, border = false })
                layer.rechargeClip:SetClipsChildren(true)
                layer.rechargeUpperClip = GUI2:CreateFrame(layer.rechargeClip, { background = false, border = false })
                layer.rechargeUpperClip:SetClipsChildren(true)
                layer.rechargeMaterial = _G.CreateFrame("StatusBar", nil, layer.rechargeUpperClip)
            end
            layer.rechargeRoot:SetAllPoints(slot.track)
            layer.rechargeRoot:SetFrameLevel(layer.root:GetFrameLevel())
            layer.rechargeLowerClip:SetFrameLevel(layer.gate.lowerClip:GetFrameLevel())
            layer.rechargeClip:SetFrameLevel(layer.clip:GetFrameLevel())
            layer.rechargeUpperClip:SetFrameLevel(layer.clip:GetFrameLevel())
            layer.rechargeLowerClip:SetAllPoints(layer.gate.lowerClip)
            layer.rechargeClip:SetAllPoints(layer.clip)
            local recharge = layer.rechargeMaterial
            recharge:SetFrameLevel(material:GetFrameLevel())
            recharge:SetAllPoints(slot.track)
            recharge:SetMinMaxValues(0, 1)
            recharge:SetValue(1)
            recharge:SetStatusBarTexture(style.texture or WHITE)
            recharge:GetStatusBarTexture():SetTexCoord(style.textureU0 or 0, style.textureU1 or 1,
                style.textureV0 or 0, style.textureV1 or 1)
            GUI2:ApplyNativeStatusBarStyle(recharge, style, runtime.orientation, runtime.fillDirection, true)
            local tint = RechargeColor(color)
            recharge:SetStatusBarColor(tint[1], tint[2], tint[3], tint[4])
            layer.rechargeRoot:Show()
        end
        layer.driver:SetValue(0)
        layer.root:Show()
    end
    if not slot._yhudBarRechargeCustom then
        slot.gui2RechargeMaterial:Hide()
        for index = 1, #definitions do
            local layer = layers[index]
            local upper, nextLayer = layer.rechargeUpperClip, layers[index + 1]
            upper:ClearAllPoints()
            if index < #definitions then
                -- Complement of the next >= gate. Recovery intervals are
                -- disjoint, so translucent colors never stack or mix.
                upper:SetPoint("TOPLEFT", nextLayer.driver:GetStatusBarTexture(), "TOPRIGHT")
                upper:SetPoint("BOTTOMRIGHT", nextLayer.driver, "BOTTOMRIGHT")
            else
                upper:SetAllPoints(slot.track)
            end
        end
    end
    slot._yhudChargeColorLayerCount = #definitions
    local level = slot.nativeVisibleStatusBar:GetFrameLevel() + #definitions * 3 + 3
    slot._yhudChargeColorTopLevel = level
    RaiseOverlay(slot.durationOverlay, level + 2)
    RaiseOverlay(slot.nativeBorderOverlay, level + 2)
end

function View:PreviewBarChargeColor(slot, field, color)
    if field == "fillColor" then
        if slot.PreviewDurationFillColor then slot:PreviewDurationFillColor(color) end
        for index = 1, slot._yhudChargeColorLayerCount or 0 do
            local layer = slot._yhudChargeColorLayers[index]
            if layer.baseColor then
                layer.material:SetStatusBarColor(color.r or color[1], color.g or color[2], color.b or color[3], color.a or color[4] or 1)
                if layer.rechargeMaterial and not slot._yhudBarRechargeCustom then
                    local tint = RechargeColor(color)
                    layer.rechargeMaterial:SetStatusBarColor(tint[1], tint[2], tint[3], tint[4])
                end
            end
        end
        if slot._yhudBarRechargeCustom then return true end
    elseif field == "rechargeColor" then
        slot._yhudBarRechargeCustom = true
        for _, layer in ipairs(slot._yhudChargeColorLayers or {}) do
            if layer.rechargeRoot then layer.rechargeRoot:Hide() end
        end
        slot.gui2RechargeMaterial:Show()
    else return false end
    local tint = RechargeColor(color, slot._yhudBarRechargeCustom)
    slot.gui2RechargeMaterial:SetStatusBarColor(tint[1], tint[2], tint[3], tint[4])
    return true
end

function View:PrepareBarValueDriver(slot, runtime)
    slot._yhudBarValueModeOwned = true
    GUI2:SetProjectedStatusBarValueMode(slot, true)
end

function View:RefreshBarProgressGeometry(slot, runtime)
    local maximum = slot._yhudBarMaximum
    if slot._yhudBarProgress and slot._yhudBarProgress.source == "spell-charges" and maximum then
        GUI2:PrepareProjectedStatusBarRecharge(slot, maximum, slot.barWidth, slot.barHeight)
        for index = 1, slot._yhudChargeColorLayerCount or 0 do
            local layer = slot._yhudChargeColorLayers[index]
            if layer.trigger > 0 then
                GUI2:ConfigureAuraApplicationGate(layer.gate, slot.track,
                    { operator = "gte", value = layer.trigger }, slot.barWidth, slot.barHeight)
            end
        end
    end
    self:LayoutBarTicks(slot, runtime, maximum)
end

function View:ConfigureBarProgress(slot, runtime, monitor, entry)
    local previousSource = slot._yhudBarProgress and slot._yhudBarProgress.source
    self:ClearBarProgress(slot)
    if runtime.view ~= "bar" then return end
    local appearance = monitor and monitor.appearanceOverride
    local progress = YHUD:NormalizeBarProgress(appearance and appearance.barProgress)
    if progress.source == "aura-stacks" and not YHUD:CanUseBarAuraProgress(entry, monitor)
        or progress.source == "spell-charges" and not YHUD:CanUseBarChargeProgress(entry, monitor) then
        progress = YHUD:SwitchBarProgressSource(progress, "time")
    end
    slot._yhudBarProgress = progress
    if previousSource ~= progress.source then
        slot._yhudDurationMode, slot._yhudOpaqueRevision = nil, nil
    end
    slot._yhudBarMaximum = self:ReadBarProgressMaximum(entry, monitor, progress)
    if progress.source ~= "time" and slot.RefreshProjectedDriverStyle then
        slot:RefreshProjectedDriverStyle(true)
    end
    if progress.source ~= "time" then self:PrepareBarValueDriver(slot, runtime) end
    if progress.source == "spell-charges" and slot._yhudBarMaximum then
        GUI2:PrepareProjectedStatusBarRecharge(slot, slot._yhudBarMaximum,
            slot.barWidth or runtime.barWidth, slot.barHeight or runtime.barHeight)
    end
    if progress.source == "spell-charges" then self:ConfigureBarRechargeAppearance(slot, runtime, monitor) end
    self:ConfigureChargeBarColors(slot, runtime, monitor)
    self:LayoutBarTicks(slot, runtime, slot._yhudBarMaximum)
end

local function PrepareNativeBarSources(slot)
    if slot._yhudBarProgress.source == "aura-stacks" and slot._yhudBarMaximum
        and not slot._yhudNativeCountGate then
        local driver = CreateFrame("StatusBar", nil, slot.track)
        driver:SetAllPoints(slot.track)
        driver:SetValue(0)
        slot._yhudNativeCountGate = { driver = driver }
    end
    if not slot._yhudNativeColorGate then
        slot._yhudNativeColorGate = {}
    end
end

local function RefreshNativeBarCount(slot, sourceFrame, live)
    local adapter = YUI.API and YUI.API.CooldownViewer
    local countMode = slot._yhudBarProgress.source == 'aura-stacks'
    local maximum = slot._yhudBarMaximum
    local drivers = slot.gui2AuraBarThresholdDrivers
    local gate
    if countMode and not live then
        gate = slot._yhudNativeCountGate
        if gate then gate.driver:Hide() end
        slot.nativeStatusBar, slot.durationStatusBar = slot._yhudBarTimeDriver, slot._yhudBarTimeDriver
        GUI2:SetProjectedStatusBarValueMode(slot, false)
    elseif countMode and maximum then
        gate = slot._yhudNativeCountGate
        if gate.maximum ~= maximum then
            gate.driver:SetMinMaxValues(0, maximum)
            gate.maximum = maximum
        end
        if slot.nativeStatusBar ~= gate.driver then
            GUI2:EnsureProjectedStatusBarFill(slot, slot.track, gate.driver, {
                parent = slot.track, clipFrameLevelOffset = 1, visibleFrameLevelOffset = 1,
                orientation = slot.orientation, fillDirection = slot.fillDirection,
            })
            GUI2:SetProjectedStatusBarValueMode(slot, true)
        end
        slot.durationStatusBar = gate.driver
    elseif not countMode and drivers and #drivers > 0 then
        gate = slot._yhudNativeColorGate
        gate.driver = drivers[1]
    end
    if gate and gate.additionalDrivers ~= drivers then
        gate.additionalDrivers = drivers
        gate.lastPublicValue = nil
    end
    local available = false
    if live and sourceFrame and gate and adapter and adapter.FeedAuraApplicationGate then
        available = adapter:FeedAuraApplicationGate(sourceFrame, gate)
    elseif gate then
        gate.driver:SetValue(0)
        gate.lastPublicValue = nil
    end
    if countMode then GUI2:SetProjectedStatusBarShown(slot, available) end
    if slot.gui2AuraBarThresholdRoot then slot.gui2AuraBarThresholdRoot:SetShown(available) end
end

function View:ConfigureNativeBarProgress(slot, host, runtime, monitor, entry, width, textOverlay, borderOverlay, sourceFrame)
    if not monitor or not entry then self:ClearBarProgress(slot); return end
    slot._yhudBarHost, slot._yhudBarTimeDriver = host, host
    slot._yhudNativeBarProgress = true
    slot.orientation, slot.fillDirection = runtime.orientation, runtime.fillDirection or "forward"
    slot.durationOverlay, slot.nativeBorderOverlay = textOverlay, borderOverlay
    slot.barWidth = width
    slot.barHeight = (runtime.showIcon == false and runtime.itemHeight or runtime.barHeight) or runtime.itemHeight
    local appearance = monitor.appearanceOverride
    local inputs = slot._yhudNativeProgressInputs
    local progress = slot._yhudBarProgress
    local live = not (self.preview or self.designMode or self.layoutEditMode)
    local maximumRecovered = progress and progress.source == "aura-stacks" and progress.maximumMode == "auto"
        and not slot._yhudBarMaximum and self:ReadBarProgressMaximum(entry, monitor, progress) ~= nil
    if inputs and inputs.monitor == monitor and inputs.entry == entry and inputs.appearance == appearance
        and inputs.identities == monitor._yhudSpellIdentities and inputs.live == live
        and inputs.orientation == runtime.orientation and inputs.direction == runtime.fillDirection
        and not maximumRecovered then
        if self.ConfigureBarStackThresholds then
            self:ConfigureBarStackThresholds(slot, runtime, monitor, entry, width)
        end
        RefreshNativeBarCount(slot, sourceFrame, live)
        if inputs.width ~= width or inputs.height ~= slot.barHeight
            or inputs.orientation ~= runtime.orientation or inputs.direction ~= runtime.fillDirection then
            inputs.width, inputs.height = width, slot.barHeight
            inputs.orientation, inputs.direction = runtime.orientation, runtime.fillDirection
            self:LayoutBarTicks(slot, runtime, slot._yhudBarMaximum)
        else
            self:RaiseBarTickLayers(slot)
        end
        return
    end
    slot.durationStatusBar = slot.nativeStatusBar
    self:ConfigureBarProgress(slot, runtime, monitor, entry)
    if self.ConfigureBarStackThresholds then
        self:ConfigureBarStackThresholds(slot, runtime, monitor, entry, width)
    end
    if live then PrepareNativeBarSources(slot) end
    RefreshNativeBarCount(slot, sourceFrame, live)
    slot._yhudNativeProgressInputs = { monitor = monitor, entry = entry, appearance = appearance,
        identities = monitor._yhudSpellIdentities, width = width, height = slot.barHeight,
        orientation = runtime.orientation, direction = runtime.fillDirection, live = live }
    self:LayoutBarTicks(slot, runtime, slot._yhudBarMaximum)
end

function View:ApplyBarValue(slot, runtime, value, maximum, secret)
    maximum = PublicMaximum(maximum)
    local rawSecret = _G.issecretvalue and _G.issecretvalue(value)
    secret = secret == true or rawSecret == true
    local valid = maximum ~= nil and (rawSecret or type(value) == "number")
    local changed = slot._yhudBarMaximum ~= maximum or slot._yhudBarValueValid ~= valid
    slot._yhudBarMaximum, slot._yhudBarValueValid = maximum, valid
    if changed then
        self:LayoutBarTicks(slot, runtime, maximum)
        if maximum and slot._yhudBarProgress.source == "spell-charges" then
            GUI2:PrepareProjectedStatusBarRecharge(slot, maximum,
                slot.barWidth or runtime.barWidth, slot.barHeight or runtime.barHeight)
        end
    end
    if not valid then value = 0 end
    if not changed and secret ~= true and slot._yhudBarPublicValue == value then return end
    slot._yhudBarPublicValue = secret ~= true and value or nil
    slot.gui2DurationObjectSource, slot.gui2DurationTimerBound = nil, false
    local bar = slot.durationStatusBar
    if bar then
        if changed then bar:SetMinMaxValues(0, maximum or 1, 0) end
        bar:SetValue(value, 0)
    end
    if changed and slot.SetNativeFillShown then slot:SetNativeFillShown(valid) end
    for index = 1, slot._yhudChargeColorLayerCount or 0 do
        local layer = slot._yhudChargeColorLayers[index]
        if layer.trigger > 0 then layer.driver:SetValue(value, 0) end
        if changed then layer.root:SetShown(valid) end
        if changed and layer.rechargeRoot then layer.rechargeRoot:SetShown(valid and not slot._yhudBarRechargeCustom) end
    end
end

function View:ApplyBarProgress(slot, state, runtime)
    local progress = slot._yhudBarProgress
    if not progress then return false end
    if progress.source == "time" then return false end
    slot._yhudCooldownRefreshArmed = false
    -- Countdown text remains an independent native cooldown sink.
    local cooldown = slot.countdown
    if cooldown then
        local mode = state and state.durationMode or "none"
        if mode ~= "none" and state.durationObject and cooldown.SetCooldownFromDurationObject
            and (slot._yhudBarCountdownMode ~= mode
                or slot._yhudBarCountdownRevision ~= state.opaqueRevision) then
            cooldown:SetCooldownFromDurationObject(state.durationObject)
            cooldown:Show()
            slot._yhudBarCountdownMode, slot._yhudBarCountdownRevision = mode, state.opaqueRevision
        elseif mode == "none" and slot._yhudBarCountdownMode ~= "none" then
            if cooldown.Clear then cooldown:Clear() end
            cooldown:Hide()
            slot._yhudBarCountdownMode, slot._yhudBarCountdownRevision = "none", nil
        end
    end
    if progress.source == "spell-charges" then
        local maximum = state and state.hasCharges == true and state.chargeReadResolved ~= false
            and state.maxCharges or nil
        local secret = state and state.chargeCountSecret == true
        local value
        if secret then value = state.displayCountRaw else value = state and state.currentCharges end
        if secret and not (_G.issecretvalue and _G.issecretvalue(value)) and value == nil
            and maximum and state.chargeReadResolved ~= false then
            -- A cooldown-only dispatch has no new count payload. Keep the
            -- native sink instead of clearing it or caching a restricted value.
            maximum = PublicMaximum(maximum)
            if maximum and slot._yhudBarMaximum ~= maximum then
                slot._yhudBarMaximum = maximum
                slot.durationStatusBar:SetMinMaxValues(0, maximum, 0)
                self:LayoutBarTicks(slot, runtime, maximum)
                GUI2:PrepareProjectedStatusBarRecharge(slot, maximum,
                    slot.barWidth or runtime.barWidth, slot.barHeight or runtime.barHeight)
            end
            ApplyRecharge(slot, state)
            return true
        end
        self:ApplyBarValue(slot, runtime, value, maximum, secret)
        ApplyRecharge(slot, state)
    else
        -- Live filtered Auras bind SetApplicationBar directly. Public design
        -- samples and inactive placeholders never fabricate a live Aura value.
        local value = self.designMode or self.preview or self.layoutEditMode
        self:ApplyBarValue(slot, runtime, value and 2 or 0, slot._yhudBarMaximum, false)
    end
    return true
end
