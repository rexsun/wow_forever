local YUI = _G.YUI
local UF = YUI and YUI.YUnitFrames
if not UF then return end
local GUI = YUI.GUI2
local Backend = {}
UF.Backend = Backend

function Backend:UnitColor(unit)
    local player = UnitIsPlayer(unit)
    if not YUI.API.Security.IsSecretValue(player) and player then
        local _, class = UnitClass(unit)
        if not YUI.API.Security.IsSecretValue(class) and class then return UF:GetColor("class", class) end
    end
    -- Native reaction colours can go directly to the colour sink, including secrets.
    return UnitSelectionColor(unit, true)
end

-- This backend is selected by both verified client entries. Keep all native
-- duration/aura contracts here; the model and editor contain no client branches.
Backend.Values = {
    health = UnitHealth, maxHealth = UnitHealthMax, missingHealth = UnitHealthMissing,
    power = UnitPower, maxPower = UnitPowerMax, missingPower = UnitPowerMissing,
    absorbs = UnitGetTotalAbsorbs, healAbsorbs = UnitGetTotalHealAbsorbs,
}

local eventDomains = {
    UNIT_HEALTH = "health", UNIT_MAXHEALTH = "health", UNIT_POWER_UPDATE = "power", UNIT_MAXPOWER = "power", UNIT_DISPLAYPOWER = "power",
    UNIT_ABSORB_AMOUNT_CHANGED = "absorb", UNIT_HEAL_ABSORB_AMOUNT_CHANGED = "absorb",
    UNIT_NAME_UPDATE = "identity", UNIT_LEVEL = "identity", UNIT_FACTION = "identity", UNIT_FLAGS = "identity", UNIT_CONNECTION = "identity",
    UNIT_PORTRAIT_UPDATE = "identity", UNIT_MODEL_CHANGED = "identity", UNIT_TARGET = "target", UNIT_CLASSIFICATION_CHANGED = "identity",
    UNIT_SPELLCAST_START = "cast", UNIT_SPELLCAST_STOP = "cast", UNIT_SPELLCAST_FAILED = "cast", UNIT_SPELLCAST_INTERRUPTED = "cast",
    UNIT_SPELLCAST_DELAYED = "cast", UNIT_SPELLCAST_CHANNEL_START = "cast", UNIT_SPELLCAST_CHANNEL_UPDATE = "cast", UNIT_SPELLCAST_CHANNEL_STOP = "cast",
    UNIT_SPELLCAST_INTERRUPTIBLE = "cast", UNIT_SPELLCAST_NOT_INTERRUPTIBLE = "cast",
}
local globalEvents = { "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "UNIT_PET", "GROUP_ROSTER_UPDATE", "RAID_TARGET_UPDATE", "PLAYER_FLAGS_CHANGED" }
for event, domain in pairs(UF.Client.extraUnitEvents) do eventDomains[event] = domain end
Backend.UnitEvents, Backend.GlobalEvents = eventDomains, globalEvents

function Backend:Percent(unit, power)
    local curve = CurveConstants and CurveConstants.ScaleTo100
    local value
    if power then value = UnitPowerPercent(unit, nil, true, curve)
    else value = UnitHealthPercent(unit, true, curve) end
    return string.format("%.0f", value)
end

function Backend:CreateCastBinding(fontString)
    local binding = C_DurationUtil.CreateDurationTextBinding()
    binding:SetFontString(fontString)
    binding:SetFormatter(C_StringUtil.CreateSecondsFormatter())
    binding:SetEnabled(false)
    return binding
end

function Backend:PaintPortrait(texture, unit)
    -- GUI2 owns the shape mask; the engine must supply uncropped portrait art.
    SetPortraitTexture(texture, unit, true)
    texture:ClearAllPoints(); texture:SetAllPoints()
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

local singleStackFormatter
local function StackOptions(config)
    if config.hideSingle then return {} end
    if not singleStackFormatter then
        singleStackFormatter = C_StringUtil.CreateNumericRuleFormatter()
        singleStackFormatter:AddBreakpoint({ threshold = 0, min = 1, format = "%.0f" })
    end
    return { formatter = singleStackFormatter }
end
local function NativeAuraStyle(element, button)
    local config = element.config
    -- Native buttons retain their fixed dimensions; the public container owns size.
    button:SetSize(32, 32)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button:SetIcon(icon)
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(); cooldown:SetDrawEdge(false); cooldown:SetHideCountdownNumbers(true)
    button:SetDurationCooldown(cooldown)
    local regions = { owner = button, size = 32, cooldown = cooldown, edges = {},
        count = button:CreateFontString(nil, "OVERLAY"), duration = button:CreateFontString(nil, "OVERLAY") }
    for i = 1, 4 do regions.edges[i] = button:CreateTexture(nil, "OVERLAY") end
    UF.View:StyleAuraRegions(regions, config, config.iconSize / 32)
    button:SetApplicationCount(regions.count, StackOptions(config))
    button:SetDurationText(regions.duration, {})
    element.auraRegions[#element.auraRegions + 1] = regions
end

function Backend:ParkAura(element)
    -- SetUnit requires a string. Disabling releases native dynamic events and
    -- aura assignments while preserving the token for the next configuration.
    element.container:SetEnabled(false)
end

function Backend:ConfigureAura(element, record)
    local config = element.config
    if not element.container then
        if not C_AddOns.IsAddOnLoaded(UF.Client.auraAddon) then C_AddOns.LoadAddOn(UF.Client.auraAddon) end
        local container = CreateFrame("AuraContainer", nil, element.frame, UF.Client.auraTemplate)
        element.container = container
        container:SetEnabled(false)
        container:SetSize(1, 1)
        container:AddAuraGroup("main", config.filter, {
            maxFrameCount = config.count,
            initializeFrame = function(button) NativeAuraStyle(element, button) end,
            layout = { elementWidth = 32, elementHeight = 32 },
        })
    end
    local container = element.container
    local scale = config.iconSize / 32
    container:SetScale(scale)
    container:ClearAllPoints()
    local point = config.startCorner
    container:SetPoint(point, element.frame, point, 0, 0)
    container:SetFlowLayoutAnchorPoint(point)
    local right = point == "TOPRIGHT" or point == "BOTTOMRIGHT"
    local bottom = point == "BOTTOMLEFT" or point == "BOTTOMRIGHT"
    local horizontal = right and AnchorUtil.FlowDirection.Left or AnchorUtil.FlowDirection.Right
    local vertical = bottom and AnchorUtil.FlowDirection.Up or AnchorUtil.FlowDirection.Down
    local perLine, columnFirst = UF:AuraLayout(config)
    container:SetFlowLayoutAxis(columnFirst and AnchorUtil.FlowLayoutAxis.Vertical or AnchorUtil.FlowLayoutAxis.Horizontal)
    container:SetFlowLayoutGrowthDirection(horizontal, vertical)
    local mainSpacing = columnFirst and config.spacingY or config.spacing
    local lineSpacing = columnFirst and config.spacing or config.spacingY
    container:SetFlowLayoutMaximumLineSize((perLine * config.iconSize + (perLine - 1) * mainSpacing) / scale)
    container:SetAuraGroupFilterString("main", config.filter)
    container:SetAuraGroupMaxFrameCount("main", config.count)
    container:SetAuraGroupLayout("main", { elementWidth = 32, elementHeight = 32, elementSpacing = mainSpacing / scale, lineSpacing = lineSpacing / scale })
    for _, regions in ipairs(element.auraRegions) do
        UF.View:StyleAuraRegions(regions, config, scale)
        regions.owner:SetApplicationCount(regions.count, StackOptions(config))
    end
    container:SetUnit(record.unit)
    container:SetEnabled(true)
end

function Backend:PaintBar(element, unit)
    local kind, bar = element.kind, element.bar
    if kind ~= "cast" then element.frame:Show() end
    if kind == "cast" then
        local info = element.record.castInfo
        if not info or not element.record.castDuration then
            element.frame:Hide(); if element.binding then element.binding:SetEnabled(false) end; return false
        end
        element.frame:Show()
        self:PaintTicks(element, info)
        if not GUI:BindCastTimer(bar, element.record.castDuration, element.record.castIsChannel) then
            element.frame:Hide(); if element.binding then element.binding:SetEnabled(false) end; return false
        end
        element.label:SetText(info.displayNameRaw)
        element.icon:SetTexture(info.displayTextureRaw)
        if element.binding then element.binding:SetDuration(element.record.castDuration); element.binding:SetEnabled(true) end
    elseif kind == "health" then
        local record = element.record
        if not record.healthRead then
            record.healthDisplay = YUI.API.Unit.ReadHealthDisplay(unit, record.healthDisplay)
            record.healthRead = true
        end
        local display = record.healthDisplay
        if display.rawValuesAvailable then
            bar:SetMinMaxValues(0, display.maxValueRaw); bar:SetValue(display.valueRaw)
        end
    elseif kind == "power" then
        bar:SetMinMaxValues(0, UnitPowerMax(unit)); bar:SetValue(UnitPower(unit))
    elseif kind == "absorbs" then
        bar:SetMinMaxValues(0, UnitHealthMax(unit)); bar:SetValue(UnitGetTotalAbsorbs(unit))
    elseif kind == "healabsorbs" then
        bar:SetMinMaxValues(0, UnitHealthMax(unit)); bar:SetValue(UnitGetTotalHealAbsorbs(unit))
    end
    return true
end


function Backend:PaintTicks(element, info, preview)
    local config = element.config
    local count = 0
    if config.showTicks and (preview or (info and info.isChannel and not info.isEmpowered)) then
        count = config.tickCount or 0
        if count == 0 then
            count = preview and 5 or element.record.castDisplay and element.record.castDisplay.castTickCount or 0
        end
    end
    local display = not preview and config.showTicks and element.record.castDisplay
    GUI:UpdateCastMarkers(element.ticks, element.bar, display and display.castStages,
        display and display.castTotal, count, config.vertical, config.reverse)
end

function Backend:PaintCastPart(element, record)
    local info = record.castInfo
    if element.binding then element.binding:SetEnabled(false) end
    if not record.preview and (not info or not record.castDuration) then element.frame:Hide(); return end
    element.frame:Show()
    if element.kind == "casticon" then
        element.texture:SetTexture(record.preview and 135846 or info.displayTextureRaw)
        element.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    elseif element.kind == "castname" then element.text:SetText(record.preview and UF:T("preview.cast") or info.displayNameRaw)
    elseif element.kind == "casttime" then
        if record.preview then element.text:SetText("1.4")
        elseif element.binding then element.binding:SetDuration(record.castDuration); element.binding:SetEnabled(true) end
    elseif element.kind == "casttarget" then
        if record.preview then element.text:SetText("Astra")
        else
            local target = YUI.API.Unit.GetSpellTargetInfo(record.unit)
            if target then element.text:SetText(target.displayNameRaw) else element.text:SetText("") end
        end
    end
end
