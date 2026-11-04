local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
local View = YHUD and YHUD.View
local I = View and View._internal
if not I then return end

local Unit = YUI.API and YUI.API.Unit
local CreateFrame = _G.CreateFrame
local STATUS_BAR_INTERPOLATION = _G.Enum
    and _G.Enum.StatusBarInterpolation
local STATUS_BAR_INTERPOLATION_IMMEDIATE = STATUS_BAR_INTERPOLATION
    and (STATUS_BAR_INTERPOLATION.Immediate
        or STATUS_BAR_INTERPOLATION.None) or 0
local STATUS_BAR_INTERPOLATION_SMOOTH = STATUS_BAR_INTERPOLATION
    and STATUS_BAR_INTERPOLATION.ExponentialEaseOut
    or STATUS_BAR_INTERPOLATION_IMMEDIATE
local math_ceil = math.ceil
local math_max = math.max
local math_min = math.min
local tonumber = tonumber
local type = type
local FILTERED_AURA_RESTING_WIDTH = 1

-- Potion time remains public and event-driven. Only this separate descendant
-- binds the real applications; Lua never reads its text, value or visibility.
View.buffTimerStackDisplays = View.buffTimerStackDisplays or {}
local potionCountFormatter

local function GetPotionStackConfiguration(runtime, monitor)
    local style = runtime.iconStyle and runtime.iconStyle.countText or {}
    local color = style.color or runtime.countTextColor or {}
    local level, strata = View:GetMonitorDisplayLayer(runtime, monitor.id)
    return {
        -- Compile returns a new table at every cold configuration boundary.
        -- Snapshot authored values so unchanged rules reuse sealed descendants,
        -- while in-place edits cannot mutate the previous configuration.
        rules = YHUD:CopyValue(monitor._yhudGlowRuntime and monitor._yhudGlowRuntime.rules or {}),
        monitorId = monitor.id, groupId = monitor.groupId,
        width = runtime.itemWidth or runtime.iconSize, height = runtime.itemHeight or runtime.iconSize,
        shape = runtime.shape or "square", level = level, strata = strata,
        countText = runtime.countText == true,
        font = style.font or runtime.countTextFont, size = style.size or runtime.countTextSize,
        outline = style.outline or runtime.countTextOutline,
        monochrome = style.monochrome or runtime.countTextMonochrome,
        position = style.position or runtime.countTextPosition,
        offsetX = style.offsetX or runtime.countTextOffsetX, offsetY = style.offsetY or runtime.countTextOffsetY,
        red = color.r or color[1] or 1, green = color.g or color[2] or 1,
        blue = color.b or color[3] or 1, alpha = color.a or color[4] or 1,
    }
end

local function SamePotionStackConfiguration(first, second)
    if first == second then return true end
    if type(first) ~= "table" or type(second) ~= "table" then return false end
    for key, value in pairs(first) do
        if not SamePotionStackConfiguration(value, second[key]) then return false end
    end
    for key in pairs(second) do if first[key] == nil then return false end end
    return true
end

local function ConfigurePotionStackOverlay(record, variant)
    local gui, config, host = YUI.GUI2, record.config, variant.host
    local compiled = record.compiled
    local stackCount = compiled and compiled.stackRuleCount or 0
    local width, height = config.width, config.height
    host:SetSize(width, height)
    variant.countHost:SetShown(config.countText)
    gui:ApplyTextStyle(variant.count, {
        font = config.font, size = config.size, outline = config.outline, monochrome = config.monochrome,
        position = config.position, offsetX = config.offsetX, offsetY = config.offsetY,
        color = { config.red, config.green, config.blue, config.alpha },
    }, { preserveVisibility = true })
    local level, strata = config.level, config.strata
    local glowLevel = level and level + 9 or nil
    if strata then host:SetFrameStrata(strata) end
    if level then
        -- Clipping flattens descendant rendering. Raise the owner before gate
        -- creation so the whole branch stays above the public cooldown (+8).
        host:SetFrameLevel(glowLevel)
        variant.countHost:SetFrameLevel(level + 16)
    end
    local binding
    if stackCount > 1 then
        local set = YHUD.Glow:ConfigureStackSet(host, host, compiled, width, height, nil, record.slot)
        variant.stackSet = set
        host._yhudAuraStackSet = set
        binding = set and set.gate.binding
        YHUD.Glow:ApplyStackSet(set, variant.inCombat, true, config.shape, glowLevel, strata)
    elseif stackCount == 1 then
        local rule = compiled.rules[1]
        if rule.combatOnly ~= true or variant.inCombat then
            local gate = gui:CreateAuraApplicationGate(host, host, rule.stackCondition, width, height)
            host._yhudAuraStackGate = gate
            binding = gate and gate.binding
            if gate then
                local glow = gui:CreateGlow(host, { hidden = true, restrictedParent = true,
                    trustedWidth = width, trustedHeight = height,
                    skinOwner = record.slot,
                    trustedFrameLevel = glowLevel, trustedFrameStrata = strata })
                if glow then
                    local shape = rule.appearance.style == "proc"
                        and (config.shape == "circle" and "circle" or "square") or config.shape
                    glow:SetGlowParams(rule.appearance)
                    glow:SetGlowShape(shape, config.shape)
                    glow:SetGlowClipParent(gate.clip)
                    glow:SetGlowShown(true)
                    host._yhudGlowShown = true
                end
            end
        end
    end
    return { applicationCount = { target = variant.count, options = record.countOptions },
        applicationBar = binding }
end

local function ReleasePotionStackOverlay(record)
    record.active, record.configuredMonitor, record.shown = false, nil, false
    record.root:Hide()
    -- Native descendants may deny all tainted access, including Hide, SetParent
    -- and StatusBar writes. Release only their unrestricted outer owners.
    for _, variant in ipairs(record.variants or {}) do
        variant.root:Hide()
        if variant.handle then Unit.ReleaseFilteredAuraDisplay(variant.handle) end
    end
    record.variants = nil
end

function View:RefreshBuffTimerStackGlow(record)
    if not record then return end
    local active = record.active == true and record.identitySuppressed ~= true
    if record.shown ~= active then
        record.root:SetShown(active)
        record.shown = active
    end
    local inCombat = self.inCombat == true
    local variants = record.variants
    if not variants then return end
    for _, variant in ipairs(variants) do
        local shown = #variants == 1 or variant.inCombat == inCombat
        if variant.shown ~= shown then
            variant.root:SetShown(shown)
            variant.shown = shown
        end
    end
end

function View:SuspendBuffTimerStacks(slot)
    local record = slot and self.buffTimerStackDisplays[slot]
    if not record then return end
    record.active = false
    record.configuredMonitor = nil
    self:RefreshBuffTimerStackGlow(record)
end

function View:ConfigureBuffTimerStacks(slot, runtime, monitor, entry)
    local record = self.buffTimerStackDisplays[slot]
    local spellID = YHUD:GetBuffTimerStackAuraSpellID(entry)
    if not (spellID and runtime.view == "icon" and monitor
        and not (self.preview or self.designMode or self.layoutEditMode
            or slot._yhudDesignProjection)) then
        self:SuspendBuffTimerStacks(slot)
        return
    end
    if not (Unit and Unit.CreateFilteredAuraDisplay and Unit.EnsureFilteredAuraDisplay
        and Unit.EnsureFilteredAuraDisplay() == true) then
        self:SuspendBuffTimerStacks(slot)
        return
    end
    local config = GetPotionStackConfiguration(runtime, monitor)
    -- 只比较公开材质快照；受限后代需要在初始化时重建，不能事后换材质。
    if YUI.GUI2.GetIconSkinProcRecipe then
        config.skinGlow = YUI.GUI2:GetIconSkinProcRecipe(slot)
    end
    if record and record.variants and not SamePotionStackConfiguration(record.config, config) then
        ReleasePotionStackOverlay(record)
    end
    if not record then
        record = { slot = slot, active = false, shown = false }
        record.root = YUI.GUI2:CreateFrame(slot, { mouse = false })
        record.root:SetAllPoints(slot)
        record.root:Hide()
        if not potionCountFormatter and _G.C_StringUtil and _G.C_StringUtil.CreateNumericRuleFormatter then
            potionCountFormatter = _G.C_StringUtil.CreateNumericRuleFormatter()
            potionCountFormatter:SetBreakpoints({ { threshold = 0, format = "%d" } })
        end
        record.countOptions = potionCountFormatter and { formatter = potionCountFormatter } or nil
        self.buffTimerStackDisplays[slot] = record
    end
    if not record.variants then
        record.config, record.compiled, record.variants = config, monitor._yhudGlowRuntime, {}
        local compiled = record.compiled
        local variantCount = compiled and (compiled.stackRuleCount or 0) > 0
            and compiled.hasCombatOnly == true and 2 or 1
        -- A fixed combat plan is armed entirely inside initializeFrame. After
        -- binding, timer/identity/combat changes touch only public ancestors.
        for index = 1, variantCount do
            local variant = { inCombat = index == 2, shown = false }
            record.variants[index] = variant
            variant.root = YUI.GUI2:CreateFrame(record.root, { mouse = false })
            variant.root:SetAllPoints(record.root)
            variant.root:Hide()
            variant.handle = Unit.CreateFilteredAuraDisplay(variant.root, {
                unit = "player", filter = "HELPFUL", spellID = spellID,
                initializeFrame = function(auraFrame)
                    auraFrame:SetAllPoints(variant.root)
                    variant.auraFrame = auraFrame
                    local host = YUI.GUI2:CreateFrame(auraFrame, { mouse = false })
                    host:SetAllPoints(auraFrame)
                    variant.host = host
                    variant.countHost = YUI.GUI2:CreateFrame(host, { mouse = false })
                    variant.countHost:SetAllPoints(host)
                    variant.count = YUI.GUI2:CreateText(variant.countHost, "", "font.size.md", "color.text.primary")
                    return ConfigurePotionStackOverlay(record, variant)
                end,
            })
            if not variant.handle then
                ReleasePotionStackOverlay(record)
                return
            end
        end
    end
    record.configuredMonitor = monitor
    record.identitySuppressed = not (Unit.IsPlayerHelpfulAuraIdentityTrusted
        and Unit.IsPlayerHelpfulAuraIdentityTrusted() == true)
    for _, variant in ipairs(record.variants) do
        Unit.SetFilteredAuraDisplayIdentitySuppressed(variant.handle, record.identitySuppressed)
    end
    self:RefreshBuffTimerStackGlow(record)
end

function View:UpdateBuffTimerStacks(slot, state)
    local record = self.buffTimerStackDisplays[slot]
    local monitor = self.desiredMonitors[slot._yhudMonitorId]
    local live = not (self.preview or self.designMode or self.layoutEditMode or slot._yhudDesignProjection)
    local liquid = state and state.available == true and state.stackAuraSpellID == 1295147
    -- Preview can have acquired the public timer slot without a native overlay.
    -- Restore that binding on the existing runtime update when leaving preview.
    if live and liquid and monitor and (not record or record.configuredMonitor ~= monitor) then
        local runtime = self.groups[monitor.groupId]
        local entry = self.profile and self.profile.entries and self.profile.entries[monitor.entryKey]
        if runtime and runtime.view == "icon" then
            self:ConfigureBuffTimerStacks(slot, runtime, monitor, entry)
            record = self.buffTimerStackDisplays[slot]
        end
    end
    if not record then return end
    local active = monitor ~= nil and record.configuredMonitor == monitor and live and liquid or false
    record.active = active
    self:RefreshBuffTimerStackGlow(record)
end

function View:RefreshBuffTimerStackModes()
    for monitorId, slot in pairs(self.byMonitor) do
        local monitor = self.desiredMonitors[monitorId]
        local state = monitor and YHUD.Model and YHUD.Model:GetState(monitor.sourceKey)
        self:UpdateBuffTimerStacks(slot, state)
    end
end

function View:ReleaseBuffTimerStackDisplays()
    for slot, record in pairs(self.buffTimerStackDisplays) do
        ReleasePotionStackOverlay(record)
        self.buffTimerStackDisplays[slot] = nil
    end
end

local function DynamicNodeGrowsLeft(runtime)
    if runtime.alignment == "center" then
        if runtime.fillMode == "columns" then return runtime.wrapDirection == "up" end
        return runtime.rowDirection == "left"
    end
    -- Edge-aligned rows always grow inward from their physical edge.  Saved
    -- rowDirection is applied by traversal order in Layout.lua.
    return runtime.alignment == "end"
end

local function CreateFilteredAuraDurationTextFormatter()
    local gui = YUI.GUI2
    return gui and gui.GetDurationTextFormatter and gui:GetDurationTextFormatter() or nil
end

local FILTERED_AURA_DURATION_TEXT_FORMATTER =
    CreateFilteredAuraDurationTextFormatter()

View.filteredAuraDisplays = View.filteredAuraDisplays or {}
View.filteredAuraFrames = View.filteredAuraFrames or {}
View.filteredAuraDynamicNodes = View.filteredAuraDynamicNodes or {}
View.filteredAuraGlowRecords = View.filteredAuraGlowRecords or {}
View.filteredAuraFrameRecords = View.filteredAuraFrameRecords
    or setmetatable({}, { __mode = "k" })

local PLAYER_AURA_SCOPE = {
    unit = "player",
    filter = "HELPFUL",
    requirePlayerSource = false,
    playerHelpful = true,
}
local PLAYER_AURA_CDM_EXTENDED_SCOPE = {
    unit = "player",
    filter = "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY",
    requirePlayerSource = false,
    playerHelpful = true,
}
local EXTERNAL_AURA_SCOPE = {
    unit = "player",
    filter = "HELPFUL|!PLAYER",
    requirePlayerSource = false,
    playerHelpful = true,
}
local TARGET_DEBUFF_SCOPE = {
    unit = "target",
    filter = "HARMFUL",
    requirePlayerSource = true,
}

local function IsAuraIdentitySuppressed(scope)
    if not (scope and scope.playerHelpful == true) then
        return false
    end
    return not (Unit and Unit.IsPlayerHelpfulAuraIdentityTrusted
        and Unit.IsPlayerHelpfulAuraIdentityTrusted() == true)
end

local function ResolveFilteredAuraScope(entry)
    local scopeKey = YHUD:GetFilteredAuraScopeKey(entry)
    if scopeKey == YHUD.FILTERED_AURA_SCOPE_EXTERNAL_HELPFUL then
        return EXTERNAL_AURA_SCOPE
    end
    if scopeKey == YHUD.FILTERED_AURA_SCOPE_TARGET_HARMFUL then
        return TARGET_DEBUFF_SCOPE
    end
    if scopeKey == YHUD.FILTERED_AURA_SCOPE_PLAYER_HELPFUL_CDM_EXTENDED then
        return PLAYER_AURA_CDM_EXTENDED_SCOPE
    end
    return PLAYER_AURA_SCOPE
end

local function EnsureFilteredAuraDisplay()
    if not Unit then return false end
    if type(Unit.EnsureFilteredAuraDisplay) == "function" then
        return Unit.EnsureFilteredAuraDisplay() == true
    end
    return YHUD:CanUseFilteredAuraDisplay()
end

local function ResetFilteredAuraMonitorState(monitors)
    for _, monitor in pairs(monitors or {}) do
        monitor._yhudFilteredAuraManaged = nil
        monitor._yhudFilteredAuraFailed = nil
        monitor._yhudFilteredAuraFailureCode = nil
    end
end

local function MarkFilteredAuraFailed(monitors, code)
    for index = 1, #monitors do
        monitors[index]._yhudFilteredAuraFailed = true
        monitors[index]._yhudFilteredAuraFailureCode =
            code or "filtered-aura-create-failed"
    end
end

local function AddSpellID(result, seen, value)
    value = tonumber(value)
    if value and value > 0 and not seen[value] then
        seen[value] = true
        result[#result + 1] = value
    end
end

local function GetEntrySpellIDs(entry, monitor)
    local result = {}
    local seen = {}
    for index = 1, #(monitor and monitor._yhudSpellIdentities or {}) do
        AddSpellID(result, seen, monitor._yhudSpellIdentities[index])
    end
    AddSpellID(result, seen, entry and entry.overrideTooltipSpellId)
    AddSpellID(result, seen, entry and entry.overrideSpellId)
    AddSpellID(result, seen, entry and entry.spellId)
    for index = 1, #(entry and entry.spellIds or {}) do
        AddSpellID(result, seen, entry.spellIds[index])
    end
    for index = 1, #(entry and entry.linkedSpellIds or {}) do
        AddSpellID(result, seen, entry.linkedSpellIds[index])
    end
    table.sort(result)
    return #result > 0 and result or nil
end

View.barStackThresholdOwners = View.barStackThresholdOwners
    or setmetatable({}, { __mode = "k" })

function View:ApplyBarStackPreview(slot, count)
    local policy = slot and slot._yhudBarStackPolicy
    if not (policy and policy.enabled and slot.SetDurationFillColor) then return end
    -- Design text samples may be strings; this path only receives public preview counts.
    count = tonumber(count)
    slot._yhudBarStackPreviewCount = count
    local color = slot._yhudBarStackBaseColor
    if count and policy.high.enabled and count >= policy.high.value then
        color = policy.high.color
    elseif count and policy.low.enabled and count <= policy.low.value then
        color = policy.low.color
    end
    slot:SetDurationFillColor(color)
end

function View:ConfigureBarStackThresholds(owner, runtime, monitor, entry, width)
    local gui = YUI.GUI2
    if not (owner and gui and gui.SetAuraBarThresholds) then return end
    local appearance = monitor and monitor.appearanceOverride
    local policy = appearance and appearance.stackThresholds
    local supported = YHUD:CanUseBarAuraProgress(entry, monitor)
    owner._yhudBarStackPolicy = supported and policy or nil
    owner._yhudBarStackBaseColor = appearance and appearance.fillColor or runtime.fillColor
    if not (supported and policy and policy.enabled) then
        owner._yhudBarStackInputs = nil
        owner._yhudBarStackPreviewCount = nil
        gui:ReleaseAuraBarThresholds(owner)
        self.barStackThresholdOwners[owner] = nil
        return
    end
    if self.preview or self.designMode or self.layoutEditMode then
        owner._yhudBarStackInputs = nil
        gui:ReleaseAuraBarThresholds(owner)
        self.barStackThresholdOwners[owner] = nil
        self:ApplyBarStackPreview(owner, 2)
        return
    end
    if YHUD:IsFilteredAuraMonitor(entry, monitor) and owner._yhudBarStackLive ~= true then
        owner._yhudBarStackInputs = nil
        gui:ReleaseAuraBarThresholds(owner)
        self.barStackThresholdOwners[owner] = nil
        return
    end
    owner._yhudBarStackPreviewCount = nil
    local style = runtime.statusBarStyle or {}
    local fill = owner._yhudBarStackBaseColor
    local cache = owner._yhudBarStackInputs
    if owner.gui2AuraBarThresholdSignature and cache
        and cache.monitor == monitor and cache.entry == entry and cache.policy == policy
        and cache.identities == monitor._yhudSpellIdentities
        and cache.direct == (owner._yhudNativeBarProgress == true)
        and cache.parentManaged == (owner._yhudBarStackLive == true)
        and cache.orientation == runtime.orientation
        and cache.direction == runtime.fillDirection and cache.texture == style.texture
        and cache.u0 == style.textureU0 and cache.u1 == style.textureU1
        and cache.v0 == style.textureV0 and cache.v1 == style.textureV1
        and cache.r == (fill.r or fill[1]) and cache.g == (fill.g or fill[2])
        and cache.b == (fill.b or fill[3]) and cache.a == (fill.a or fill[4] or 1) then
        if owner._yhudBarStackLive == true then return end
        if gui.LayoutAuraBarThresholds and gui:LayoutAuraBarThresholds(owner,
            math_max(1, width), runtime.barHeight or runtime.itemHeight or 1) then
            local gate = owner._yhudNativeCountGate or owner._yhudNativeColorGate
            if gate then gate.lastPublicValue = nil end
        end
        gui:RaiseAuraBarThresholdOverlay(owner, owner.nativeBorderOverlay, 1)
        gui:RaiseAuraBarThresholdOverlay(owner, owner.durationOverlay, 2)
        return
    end
    owner._yhudBarStackInputs = {
        monitor = monitor, entry = entry, policy = policy, identities = monitor._yhudSpellIdentities,
        direct = owner._yhudNativeBarProgress == true,
        parentManaged = owner._yhudBarStackLive == true,
        width = width, orientation = runtime.orientation, direction = runtime.fillDirection,
        texture = style.texture, u0 = style.textureU0, u1 = style.textureU1,
        v0 = style.textureV0, v1 = style.textureV1,
        r = fill.r or fill[1], g = fill.g or fill[2], b = fill.b or fill[3], a = fill.a or fill[4] or 1,
    }
    local spellIDs = GetEntrySpellIDs(entry, monitor)
    if not spellIDs then
        gui:ReleaseAuraBarThresholds(owner)
        self.barStackThresholdOwners[owner] = nil
        return
    end
    local scope = ResolveFilteredAuraScope(entry)
    local function ColorKey(color)
        return table.concat({ color.r or color[1], color.g or color[2],
            color.b or color[3], color.a or color[4] or 1 }, ",")
    end
    local signature = table.concat({ table.concat(spellIDs, ","), scope.unit,
        scope.filter, tostring(scope.requirePlayerSource),
        tostring(owner._yhudNativeBarProgress == true),
        runtime.orientation or "horizontal", runtime.fillDirection or "forward",
        style.texture or "Interface\\Buttons\\WHITE8x8",
        style.textureU0 or 0, style.textureU1 or 1,
        style.textureV0 or 0, style.textureV1 or 1,
        tostring(policy.low.enabled), policy.low.value, ColorKey(policy.low.color),
        tostring(policy.high.enabled), policy.high.value, ColorKey(policy.high.color),
        ColorKey(fill) }, ":")
    gui:SetAuraBarThresholds(owner, {
        signature = signature, policy = policy, spellIDs = spellIDs,
        direct = owner._yhudNativeBarProgress == true,
        parentManaged = owner._yhudBarStackLive == true,
        unit = scope.unit, filter = scope.filter,
        requirePlayerSource = scope.requirePlayerSource,
        width = math_max(1, width), height = runtime.barHeight or runtime.itemHeight or 1, fillColor = fill,
        orientation = runtime.orientation, fillDirection = runtime.fillDirection,
        texture = style.texture or "Interface\\Buttons\\WHITE8x8",
        u0 = style.textureU0 or 0, u1 = style.textureU1 or 1,
        v0 = style.textureV0 or 0, v1 = style.textureV1 or 1,
    })
    gui:RaiseAuraBarThresholdOverlay(owner, owner.nativeBorderOverlay, 1)
    gui:RaiseAuraBarThresholdOverlay(owner, owner.durationOverlay, 2)
    -- Live colors inherit identity suppression and retirement from their
    -- primary Aura display. Never revisit a nested restricted owner.
    self.barStackThresholdOwners[owner] = owner._yhudBarStackLive ~= true and scope or nil
    local handle = owner.gui2AuraBarThresholdHandle
    if handle and not handle.parentManaged and Unit.SetFilteredAuraDisplayIdentitySuppressed then
        Unit.SetFilteredAuraDisplayIdentitySuppressed(handle, IsAuraIdentitySuppressed(scope))
    end
end

local function GetDurationBarOptions(runtime)
    local direction = _G.Enum and _G.Enum.StatusBarTimerDirection
        and _G.Enum.StatusBarTimerDirection.RemainingTime or 1
    return {
        direction = direction,
        interpolation = runtime and runtime.smoothProgress == true
            and STATUS_BAR_INTERPOLATION_SMOOTH
            or STATUS_BAR_INTERPOLATION_IMMEDIATE,
    }
end

local function ApplyGlowRecord(record)
    local monitor = record and View.desiredMonitors[record.monitorId]
    local slot = record and record.slot
    if not (monitor and slot and View.ApplyMonitorGlow) then return false end
    local display = record.display
    local trusted = not (display and display.identitySuppressed == true)
    if record.kind == "static" then
        local present = display and display.auraPresent
        local missing = trusted and present == false
        return View:ApplyMonitorGlow(
            slot,
            monitor,
            nil,
            false,
            missing == true,
            false,
            true
        )
    end
    local present = record.present == true
    return View:ApplyMonitorGlow(
        slot,
        monitor,
        nil,
        false,
        trusted and present,
        present,
        false
    )
end

local function RefreshDisplayGlow(display)
    local changed = false
    for index = 1, #(display and display.glowRecords or {}) do
        changed = ApplyGlowRecord(display.glowRecords[index]) or changed
    end
    return changed
end

local function ResolveDisplayAuraPresence(display)
    local unresolved = false
    for index = 1, #(display and display.glowRecords or {}) do
        local record = display.glowRecords[index]
        if record.kind == "live" then
            if record.present == true then return true end
            if record.present == nil then unresolved = true end
        end
    end
    if unresolved then return nil end
    return false
end

local function DisplayParticipatesInLayout(display)
    if not (display and display.proxy) then return false end
    return display.identitySuppressed ~= true
end

local function SyncDisplayLayoutParticipation(display, relayout)
    if not display then return false end
    if display.externalBuffBlock then return false end
    local participates = DisplayParticipatesInLayout(display)
    if display.layoutParticipates == participates
        or (display.layoutParticipates == nil and participates == false) then
        display.layoutParticipates = participates
        return false
    end
    display.layoutParticipates = participates
    local monitorId = display.monitorId
    if monitorId then
        if participates then
            View.filteredAuraFrames[monitorId] = display.proxy
        elseif View.filteredAuraFrames[monitorId] == display.proxy then
            View.filteredAuraFrames[monitorId] = nil
        end
    end
    if relayout == true and display.proxy
        and display.groupId and View.RelayoutGroup then
        View:RelayoutGroup(display.groupId)
    end
    return true
end

local function RegisterGlowRecord(display, monitor, slot, kind, auraFrame)
    local record = {
        display = display,
        monitorId = monitor.id,
        slot = slot,
        kind = kind,
        -- AuraFrame visibility is secret in 12.1 and must not be observed.
        -- A live glow is armed once and remains visually clipped by its
        -- engine-owned AuraFrame; the outer mixed proxy keeps its stable
        -- pre-PoC layout position.
        present = kind == "live",
    }
    display.glowRecords = display.glowRecords or {}
    display.glowRecords[#display.glowRecords + 1] = record
    if kind == "static" then display.staticGlowRecord = record end
    local byMonitor = View.filteredAuraGlowRecords[monitor.id]
    if not byMonitor then
        byMonitor = {}
        View.filteredAuraGlowRecords[monitor.id] = byMonitor
    end
    byMonitor[#byMonitor + 1] = record
    if auraFrame then
        -- 引擎按钮不写任何自定义字段、不安装脚本，也不读取受限显隐。
        -- 弱键表只保存初始化时已经公开的对象身份，绝不推导 presence。
        View.filteredAuraFrameRecords[auraFrame] = record
    end
    return record
end

local function CreateLiveSlot(auraFrame, runtime, monitor, handle, display)
    auraFrame:SetSize(runtime.itemWidth, runtime.itemHeight)
    local slot = View:CreateFilteredAuraSlot(auraFrame, runtime, monitor, true)
    if not slot then return nil end
    local bindings = View:GetFilteredAuraSlotBindings(slot, runtime)
    if not bindings then return nil end
    local compiled = monitor._yhudGlowRuntime
    if compiled and (compiled.stackRuleCount or 0) > 1 and runtime.view == "icon"
        and YHUD.Glow and YHUD.Glow.ConfigureStackSet then
        local set = YHUD.Glow:ConfigureStackSet(auraFrame, slot, compiled,
            runtime.itemWidth, runtime.itemHeight)
        slot._yhudAuraStackSet = set
        if set then bindings.applicationBar = set.gate.binding end
    else
        for index = 1, #(compiled and compiled.rules or {}) do
            local condition = compiled.rules[index].stackCondition
            if condition and runtime.view == "icon" and YUI.GUI2.CreateAuraApplicationGate then
                local gate = YUI.GUI2:CreateAuraApplicationGate(auraFrame, slot, condition,
                    runtime.itemWidth, runtime.itemHeight)
                if gate then
                    slot._yhudAuraStackGate = gate
                    bindings.applicationBar = gate.binding
                end
                break
            end
        end
    end
    if bindings.durationBar then
        bindings.durationBar = {
            target = bindings.durationBar,
            options = GetDurationBarOptions(runtime),
        }
    end
    if bindings.durationText and FILTERED_AURA_DURATION_TEXT_FORMATTER then
        bindings.durationText = {
            target = bindings.durationText,
            options = {
                textFormatter = FILTERED_AURA_DURATION_TEXT_FORMATTER,
            },
        }
    end
    handle.visuals = handle.visuals or {}
    handle.visuals[#handle.visuals + 1] = slot
    local record = RegisterGlowRecord(
        display,
        monitor,
        slot,
        "live",
        auraFrame
    )
    display.auraPresent = ResolveDisplayAuraPresence(display)
    ApplyGlowRecord(record)
    return bindings
end

local function ResolveFlowLayout(runtime)
    local anchorUtil = _G.AnchorUtil
    local axis = anchorUtil and anchorUtil.FlowLayoutAxis
    local flow = anchorUtil and anchorUtil.FlowDirection
    local verticalBar = runtime.view == "bar"
        and runtime.orientation == "vertical"
    local columnIcons = runtime.view == "icon" and runtime.fillMode == "columns"
    local rowLeft = runtime.rowDirection == "left"
    local wrapUp = runtime.wrapDirection == "up"
    local horizontal = flow and (verticalBar
        and (wrapUp and flow.Left or flow.Right)
        or (rowLeft and flow.Left or flow.Right))
    local vertical = flow and (verticalBar
        and flow.Down
        or (wrapUp and flow.Up or flow.Down))
    if columnIcons then
        local layoutPoint = (wrapUp and "BOTTOM" or "TOP") .. (rowLeft and "RIGHT" or "LEFT")
        local alignment = runtime.alignment == "start" and "TOP"
            or (runtime.alignment == "end" and "BOTTOM" or "")
        return {
            axis = axis and axis.Vertical,
            anchorPoint = layoutPoint,
            horizontalGrowth = horizontal, verticalGrowth = vertical,
            paddingLeft = 0, paddingRight = 0, paddingTop = 0, paddingBottom = 0,
            maximumLineSize = runtime.itemHeight * runtime.maxPerLine
                + math_max(0, runtime.maxPerLine - 1) * runtime.rowSpacing,
        }, alignment .. (rowLeft and "RIGHT" or "LEFT")
    end
    if verticalBar then
        local point = wrapUp and "TOPRIGHT" or "TOPLEFT"
        return {
            axis = axis and axis.Vertical,
            anchorPoint = point,
            horizontalGrowth = horizontal,
            verticalGrowth = vertical,
            paddingLeft = 0,
            paddingRight = 0,
            paddingTop = 0,
            paddingBottom = 0,
            maximumLineSize = (runtime.itemHeight * runtime.maxPerLine)
                + (math_max(0, runtime.maxPerLine - 1)
                    * runtime.rowSpacing),
        }, point
    end
    local layoutAnchor = (wrapUp and "BOTTOM" or "TOP")
        .. (rowLeft and "RIGHT" or "LEFT")
    local horizontalAnchor = runtime.alignment == "start" and "LEFT"
        or (runtime.alignment == "end" and "RIGHT" or "")
    local point = (wrapUp and "BOTTOM" or "TOP") .. horizontalAnchor
    local maximumLineSize = (runtime.itemWidth * runtime.maxPerLine)
        + (math_max(0, runtime.maxPerLine - 1) * runtime.columnSpacing)
    return {
        axis = axis and axis.Horizontal,
        anchorPoint = layoutAnchor,
        horizontalGrowth = horizontal,
        verticalGrowth = vertical,
        paddingLeft = 0,
        paddingRight = 0,
        paddingTop = 0,
        paddingBottom = 0,
        maximumLineSize = maximumLineSize,
    }, point
end

local function SetPureGroupBounds(runtime, count)
    local perLine = math_max(1, math_min(runtime.maxPerLine, count))
    local lines = math_max(1, math_ceil(count / runtime.maxPerLine))
    if (runtime.view == "bar" and runtime.orientation == "vertical")
        or (runtime.view == "icon" and runtime.fillMode == "columns") then
        runtime.filteredAuraWidth = (lines * runtime.itemWidth)
            + (math_max(0, lines - 1) * runtime.columnSpacing)
        runtime.filteredAuraHeight = (perLine * runtime.itemHeight)
            + (math_max(0, perLine - 1) * runtime.rowSpacing)
        if runtime.view == "icon" and runtime.layoutMode ~= "fixed" then
            runtime.filteredAuraHeight = I.GetAutoIconColumnHeight(runtime) or runtime.filteredAuraHeight
        end
    else
        runtime.filteredAuraWidth = (perLine * runtime.itemWidth)
            + (math_max(0, perLine - 1) * runtime.columnSpacing)
        runtime.filteredAuraHeight = (lines * runtime.itemHeight)
            + (math_max(0, lines - 1) * runtime.rowSpacing)
    end
end

local UpdateIndependentBarWidth
function View:UpdateFilteredAuraBarWidth(runtime)
    if not (Unit and Unit.SetFilteredAuraDisplayLayout) then return false end
    local blockChanged = false
    for _, display in pairs(self.filteredAuraDisplays) do
        if display.externalBuffBlock and display.groupId == runtime.id then
            local block = display.blockRuntime
            block.itemWidth, block.itemHeight = runtime.itemWidth, runtime.itemHeight
            block.barWidth, block.barHeight = runtime.barWidth, runtime.barHeight
            local groups = {}
            local vertical = (block.view == "bar" and block.orientation == "vertical")
                or (block.view == "icon" and block.fillMode == "columns")
            local elementSpacing = vertical and block.rowSpacing or block.columnSpacing
            local lineSpacing = vertical and block.columnSpacing or block.rowSpacing
            for index, key in ipairs(display.widthGroupKeys) do
                groups[key] = { layoutIndex = index, elementWidth = block.itemWidth,
                    elementHeight = block.itemHeight, elementSpacing = elementSpacing,
                    lineSpacing = lineSpacing, groupSpacing = elementSpacing,
                    groupLineSpacing = lineSpacing }
            end
            local layout = ResolveFlowLayout(block)
            blockChanged = Unit.SetFilteredAuraDisplayLayout(display.handle, layout, groups) or blockChanged
            SetPureGroupBounds(block, display.capacity)
            display.width, display.height = block.filteredAuraWidth, block.filteredAuraHeight
            display.proxy:SetSize(display.width, display.height)
        end
    end
    if self.RefreshBarProgressGeometry then
        for _, display in pairs(self.filteredAuraDisplays) do
            if display.groupId == runtime.id then
                for _, record in ipairs(display.glowRecords or {}) do
                    local slot = record.slot
                    if record.kind ~= "live" and slot and slot._yhudBarProgress then
                        slot.barWidth = runtime.showIcon == false and runtime.itemWidth or runtime.barWidth
                        slot.barHeight = runtime.showIcon == false and runtime.itemHeight or runtime.barHeight
                        self:RefreshBarProgressGeometry(slot, runtime)
                    end
                end
            end
        end
    end
    local display = self.filteredAuraDisplays["group:" .. runtime.id]
    if not (display and display.pure and display.handle) then
        return (UpdateIndependentBarWidth and UpdateIndependentBarWidth(self, runtime)) or blockChanged
    end
    local groups = {}
    local vertical = (runtime.view == "bar" and runtime.orientation == "vertical")
        or (runtime.view == "icon" and runtime.fillMode == "columns")
    for index, key in ipairs(display.widthGroupKeys or {}) do
        groups[key] = {
            layoutIndex = index, elementWidth = runtime.itemWidth,
            elementHeight = runtime.itemHeight,
            elementSpacing = vertical and runtime.rowSpacing or runtime.columnSpacing,
            lineSpacing = vertical and runtime.columnSpacing or runtime.rowSpacing,
            groupSpacing = vertical and runtime.rowSpacing or runtime.columnSpacing,
            groupLineSpacing = vertical and runtime.columnSpacing or runtime.rowSpacing,
        }
    end
    local layout = ResolveFlowLayout(runtime)
    local ok = Unit.SetFilteredAuraDisplayLayout(display.handle, layout, groups)
    if ok then SetPureGroupBounds(runtime, display.capacity or #(display.widthGroupKeys or {})) end
    return ok or blockChanged
end

local function BuildPureGroup(runtime, monitors, scope)
    local groups = {}
    local display = {
        groupId = runtime.id,
        pure = true,
        widthGroupKeys = {},
        glowRecords = {},
        identitySuppressed = IsAuraIdentitySuppressed(scope),
        capacity = 0,
    }
    for index = 1, #monitors do
        local monitor = monitors[index]
        local entry = View.profile.entries[monitor.entryKey]
        local spellIDs = GetEntrySpellIDs(entry, monitor)
        if spellIDs then
            local currentMonitor = monitor
            local verticalBar = runtime.view == "bar"
                and runtime.orientation == "vertical"
                or runtime.view == "icon" and runtime.fillMode == "columns"
            local elementSpacing = verticalBar
                and runtime.rowSpacing or runtime.columnSpacing
            local lineSpacing = verticalBar
                and runtime.columnSpacing or runtime.rowSpacing
            groups[#groups + 1] = {
                key = "yhud-group-aura-" .. tostring(monitor.id),
                spellIDs = spellIDs,
                maxFrameCount = monitor._yhudAuraMaxFrameCount or 1,
                sortMethod = monitor._yhudAuraMaxFrameCount and 0 or nil,
                sortDirection = monitor._yhudAuraMaxFrameCount and 0 or nil,
                layout = {
                    layoutIndex = index,
                    elementWidth = runtime.itemWidth,
                    elementHeight = runtime.itemHeight,
                    elementSpacing = elementSpacing,
                    lineSpacing = lineSpacing,
                    groupSpacing = elementSpacing,
                    groupLineSpacing = lineSpacing,
                },
                initializeFrame = function(auraFrame, _, handle)
                    return CreateLiveSlot(
                        auraFrame,
                        runtime,
                        currentMonitor,
                        handle,
                        display
                    )
                end,
            }
            display.widthGroupKeys[#display.widthGroupKeys + 1] = groups[#groups].key
            display.capacity = display.capacity + groups[#groups].maxFrameCount
        end
    end
    if #groups == 0 then return nil end
    local layout, point = ResolveFlowLayout(runtime)
    local handle, code = Unit.CreateFilteredAuraDisplay(runtime.frame, {
        showTooltip = runtime.showTooltip ~= false,
        unit = scope.unit,
        filter = scope.filter,
        requirePlayerSource = scope.requirePlayerSource,
        groups = groups,
        layout = layout,
        point = point,
    })
    if not handle then return nil, code end
    SetPureGroupBounds(runtime, display.capacity)
    display.handle = handle
    display.handles = { handle }
    return display
end

local function BuildExternalBuffBlock(runtime, monitor, entry)
    local blockRuntime = {}
    for key, value in pairs(runtime) do blockRuntime[key] = value end
    blockRuntime.frame = YUI.GUI2:CreateFrame(runtime.frame, { mouse = false })
    local display, code = BuildPureGroup(blockRuntime, { monitor }, ResolveFilteredAuraScope(entry))
    if not display then blockRuntime.frame:Hide(); return nil, code end
    display.externalBuffBlock = true
    display.monitorId = monitor.id
    display.proxy = blockRuntime.frame
    display.blockRuntime = blockRuntime
    display.width, display.height = blockRuntime.filteredAuraWidth, blockRuntime.filteredAuraHeight
    display.proxy:SetSize(display.width, display.height)
    display.proxy:Show()
    return display
end

local function BuildMixedMonitor(runtime, monitor, entry, spellIDs, scope)
    local display = {
        monitorId = monitor.id,
        groupId = runtime.id,
        pure = false,
        auraPresent = false,
        glowRecords = {},
        identitySuppressed = IsAuraIdentitySuppressed(scope),
    }
    local proxy = CreateFrame("Frame", nil, runtime.frame)
    proxy:SetSize(runtime.itemWidth, runtime.itemHeight)
    local staticSlot
    if monitor.visibilityMode == "always" then
        staticSlot = View:CreateFilteredAuraSlot(proxy, runtime, monitor)
        if not staticSlot then
            proxy:Hide()
            return nil, "filtered-aura-static-slot-failed"
        end
        local inactiveDesaturate = YHUD:GetEffectiveInactiveDesaturate(
            View.profile,
            monitor,
            entry
        ) == true
        View:ConfigureFilteredAuraStaticSlot(
            staticSlot,
            runtime,
            monitor,
            entry,
            inactiveDesaturate
        )
        RegisterGlowRecord(display, monitor, staticSlot, "static")
    end
    local handle, code = Unit.CreateFilteredAuraDisplay(proxy, {
        showTooltip = runtime.showTooltip ~= false,
        unit = scope.unit,
        filter = scope.filter,
        requirePlayerSource = scope.requirePlayerSource,
        spellIDs = spellIDs,
        key = "yhud-mixed-aura-" .. tostring(monitor.id),
        initializeFrame = function(auraFrame, _, displayHandle)
            auraFrame:SetAllPoints(displayHandle.container)
            return CreateLiveSlot(
                auraFrame,
                runtime,
                monitor,
                displayHandle,
                display
            )
        end,
    })
    if not handle then
        proxy:Hide()
        return nil, code
    end
    proxy:Show()
    display.handle = handle
    display.handles = { handle }
    display.proxy = proxy
    display.staticSlot = staticSlot
    display.auraPresent = ResolveDisplayAuraPresence(display)
    RefreshDisplayGlow(display)
    return display
end

local function ResolveDynamicNodeLayout(runtime, elementWidth, balance)
    local anchorUtil = _G.AnchorUtil
    local axis = anchorUtil and anchorUtil.FlowLayoutAxis
    local flow = anchorUtil and anchorUtil.FlowDirection
    local rowGrowsLeft = DynamicNodeGrowsLeft(runtime)
    local growsLeft = rowGrowsLeft
    if balance == true then growsLeft = not rowGrowsLeft end
    if runtime.fillMode == "columns" then
        return {
            axis = axis and axis.Vertical or 1,
            anchorPoint = growsLeft and "BOTTOM" or "TOP",
            horizontalGrowth = flow and flow.Right or 0,
            verticalGrowth = flow and (growsLeft and flow.Up or flow.Down) or 1,
            paddingLeft = 0, paddingRight = 0, paddingTop = 0, paddingBottom = 0,
            maximumLineSize = elementWidth,
        }
    end
    return {
        axis = axis and axis.Horizontal or 0,
        anchorPoint = growsLeft and "RIGHT" or "LEFT",
        horizontalGrowth = flow
            and (growsLeft and flow.Left or flow.Right) or 1,
        verticalGrowth = flow and flow.Up or 1,
        paddingLeft = 0,
        paddingRight = 0,
        paddingTop = 0,
        paddingBottom = 0,
        maximumLineSize = elementWidth,
    }
end

local function BuildDynamicNodeHandle(
    runtime,
    monitor,
    spellIDs,
    scope,
    display,
    balance
)
    local columnIcons = runtime.fillMode == "columns"
    local cellWidth = math_max(1, columnIcons and (runtime.itemHeight + (runtime.rowSpacing or 0))
        or (runtime.itemWidth + (tonumber(runtime.columnSpacing) or 0)))
    local effectiveWidth = balance and cellWidth / 2 or cellWidth
    local elementWidth = effectiveWidth + FILTERED_AURA_RESTING_WIDTH
    local keyPrefix = balance and "yhud-special-balance-"
        or "yhud-special-aura-"
    local handle, code = Unit.CreateFilteredAuraDisplay(runtime.frame, {
        showTooltip = balance ~= true and runtime.showTooltip ~= false,
        unit = scope.unit,
        filter = scope.filter,
        requirePlayerSource = scope.requirePlayerSource,
        point = columnIcons and "TOP" or "LEFT",
        layout = ResolveDynamicNodeLayout(runtime, elementWidth, balance),
        groups = {
            {
                key = keyPrefix .. tostring(monitor.id),
                spellIDs = spellIDs,
                maxFrameCount = 1,
                layout = {
                    layoutIndex = 1,
                    elementWidth = columnIcons and runtime.itemWidth or elementWidth,
                    elementHeight = columnIcons and elementWidth or runtime.itemHeight,
                    elementSpacing = 0,
                    lineSpacing = 0,
                    groupSpacing = 0,
                    groupLineSpacing = 0,
                },
                initializeFrame = balance and function(auraFrame)
                    auraFrame:SetSize(columnIcons and runtime.itemWidth or effectiveWidth,
                        columnIcons and effectiveWidth or runtime.itemHeight)
                    if auraFrame.SetAlpha then auraFrame:SetAlpha(0) end
                end or function(auraFrame, _, displayHandle)
                    return CreateLiveSlot(
                        auraFrame,
                        runtime,
                        monitor,
                        displayHandle,
                        display
                    )
                end,
            },
        },
    })
    if not handle then return nil, code end
    if handle.container and handle.container.ClearAllPoints then
        handle.container:ClearAllPoints()
    end
    local endpoint = CreateFrame(
        "Frame",
        nil,
        handle.proxy,
        "DisableUntrustedLayoutScriptsTemplate"
    )
    endpoint:SetSize(columnIcons and runtime.itemWidth or 1, columnIcons and 1 or runtime.itemHeight)
    local rowGrowsLeft = DynamicNodeGrowsLeft(runtime)
    local growsLeft = rowGrowsLeft
    if balance == true then growsLeft = not rowGrowsLeft end
    if columnIcons then
        endpoint:SetPoint("CENTER", handle.container, growsLeft and "TOP" or "BOTTOM",
            0, growsLeft and -FILTERED_AURA_RESTING_WIDTH or FILTERED_AURA_RESTING_WIDTH)
    elseif growsLeft then
        endpoint:SetPoint(
            "CENTER",
            handle.container,
            "LEFT",
            FILTERED_AURA_RESTING_WIDTH,
            0
        )
    else
        endpoint:SetPoint(
            "CENTER",
            handle.container,
            "RIGHT",
            -FILTERED_AURA_RESTING_WIDTH,
            0
        )
    end
    return handle, nil, endpoint
end

local function BuildDynamicMonitor(runtime, monitor, entry, spellIDs, scope)
    local display = {
        monitorId = monitor.id,
        groupId = runtime.id,
        dynamic = true,
        glowRecords = {},
        identitySuppressed = IsAuraIdentitySuppressed(scope),
    }
    local handle, code, endpoint = BuildDynamicNodeHandle(
        runtime,
        monitor,
        spellIDs,
        scope,
        display,
        false
    )
    if not handle then return nil, code end
    display.handle = handle
    display.proxy = handle.proxy
    display.node = handle.container
    display.endNode = endpoint
    display.handles = { handle }
    -- Keep the mirror node available for center alignment even while the
    -- group uses a fixed edge, so alignment and row-count transitions retain
    -- the same restricted Aura topology.
    local balanceHandle, balanceCode, balanceEndpoint =
        BuildDynamicNodeHandle(
        runtime,
        monitor,
        spellIDs,
        scope,
        display,
        true
        )
    if not balanceHandle then
        Unit.ReleaseFilteredAuraDisplay(handle)
        return nil, balanceCode
    end
    display.balanceHandle = balanceHandle
    display.balanceNode = balanceHandle.container
    display.balanceEndNode = balanceEndpoint
    display.handles[2] = balanceHandle
    display.auraPresent = ResolveDisplayAuraPresence(display)
    RefreshDisplayGlow(display)
    View.filteredAuraDynamicNodes[monitor.id] = display
    return display
end

UpdateIndependentBarWidth = function(self, runtime)
    local changed = false
    for index = 1, runtime.monitorCount do
        local id = runtime.monitorIds[index]
        local display = self.filteredAuraDisplays["monitor:" .. tostring(id)]
        if display and not display.dynamic and display.proxy then
            display.proxy:SetSize(runtime.itemWidth, runtime.itemHeight)
            changed = true
        elseif display and display.dynamic then
            for _, balance in ipairs({ false, true }) do
                local handle = balance and display.balanceHandle or display.handle
                if handle then
                    local columnIcons = runtime.fillMode == "columns"
                    local width = math_max(1, columnIcons and (runtime.itemHeight + (runtime.rowSpacing or 0))
                        or (runtime.itemWidth + (runtime.columnSpacing or 0)))
                    if balance then width = width / 2 end
                    width = width + FILTERED_AURA_RESTING_WIDTH
                    local key = (balance and "yhud-special-balance-" or "yhud-special-aura-") .. tostring(id)
                    changed = Unit.SetFilteredAuraDisplayLayout(handle,
                        ResolveDynamicNodeLayout(runtime, width, balance), {
                            [key] = { layoutIndex = 1,
                                elementWidth = columnIcons and runtime.itemWidth or width,
                                elementHeight = columnIcons and width or runtime.itemHeight, elementSpacing = 0,
                                lineSpacing = 0, groupSpacing = 0, groupLineSpacing = 0 },
                        }) or changed
                end
            end
        end
    end
    return changed
end

-- Projected duration views have one public display owner per monitor. Suppress it
-- while a verified native totem clock is drawn by the ordinary owned slot;
-- the Aura container and its restricted descendants keep all native bindings.
function View:SetFilteredAuraTotemTakeover(monitorId, active)
    local display = self.filteredAuraDisplays["monitor:" .. monitorId]
    if not display or (display.totemActive == true) == active then return false end
    local proxy = display.proxy
    if not (proxy and proxy.SetAlpha) then return false end
    proxy:SetAlpha(active and 0 or 1)
    display.totemActive = active or nil
    if I.AddViewWrite then I.AddViewWrite(false) end
    return true
end

function View:ReleaseFilteredAuraDisplays()
    local released = false
    for key, display in pairs(self.filteredAuraDisplays or {}) do
        for index = 1, #(display.glowRecords or {}) do
            local record = display.glowRecords[index]
            if record.slot and record.slot.gui2Glow
                and record.slot.gui2Glow.SetGlowShown then
                record.slot.gui2Glow:SetGlowShown(false)
                record.slot._yhudGlowShown = false
            end
            if record.slot then
                if record.slot._yhudAuraStackSet then
                    YHUD.Glow:ReleaseStackSet(record.slot._yhudAuraStackSet)
                    record.slot._yhudAuraStackSet = nil
                end
                local gate = record.slot._yhudAuraStackGate
                if gate then
                    gate.driver:SetValue(0)
                    gate.lastPublicValue = nil
                    if record.slot.gui2Glow and record.slot.gui2Glow.SetGlowClipParent then
                        record.slot.gui2Glow:SetGlowClipParent(nil)
                    end
                end
                record.slot._yhudAuraStackGate = nil
                record.slot._yhudBarStackInputs = nil
                record.slot._yhudBarStackPolicy = nil
                record.slot._yhudBarStackBaseColor = nil
                -- Live descendants retire with the public display owner;
                -- resetting their native drivers after initialization is unsafe.
                if record.kind ~= "live" and self.ClearBarProgress then
                    self:ClearBarProgress(record.slot)
                end
                if YUI.GUI2.ReleaseAuraBarThresholds then
                    YUI.GUI2:ReleaseAuraBarThresholds(record.slot)
                    self.barStackThresholdOwners[record.slot] = nil
                end
                record.slot._yhudGlowRuntime = nil
                -- Live slots remain children of Blizzard's restricted
                -- AuraFrame after the display is released.  They are still
                -- retained by GUI2's cold refresh registries, so their trusted
                -- geometry context must remain intact even while hidden.
                if record.kind ~= "live" then
                    if record.slot.gui2Glow
                        and record.slot.gui2Glow._SetGlowLayoutContext then
                        record.slot.gui2Glow:_SetGlowLayoutContext(false)
                    end
                    record.slot._yhudFilteredAuraGlow = nil
                end
            end
            record.display = nil
            record.slot = nil
        end
        if Unit and Unit.ReleaseFilteredAuraDisplay then
            for handleIndex = 1, #(display.handles or {}) do
                Unit.ReleaseFilteredAuraDisplay(display.handles[handleIndex])
            end
            if not display.handles and display.handle then
                Unit.ReleaseFilteredAuraDisplay(display.handle)
            end
        end
        if display.proxy then display.proxy:Hide() end
        if display.handle then
            display.handle.visuals = nil
        end
        display.glowRecords = nil
        display.staticGlowRecord = nil
        display.staticSlot = nil
        display.handle = nil
        display.handles = nil
        display.balanceHandle = nil
        display.node = nil
        display.endNode = nil
        display.balanceNode = nil
        display.balanceEndNode = nil
        display.proxy = nil
        self.filteredAuraDisplays[key] = nil
        released = true
    end
    self.filteredAuraFrameRecords = setmetatable({}, { __mode = "k" })
    for monitorId in pairs(self.filteredAuraFrames or {}) do
        self.filteredAuraFrames[monitorId] = nil
    end
    for monitorId in pairs(self.filteredAuraDynamicNodes or {}) do
        self.filteredAuraDynamicNodes[monitorId] = nil
    end
    for monitorId in pairs(self.filteredAuraGlowRecords or {}) do
        self.filteredAuraGlowRecords[monitorId] = nil
    end
    for _, runtime in pairs(self.groups or {}) do
        runtime.filteredAuraWidth = nil
        runtime.filteredAuraHeight = nil
        runtime.hasExternalBuffBlock = nil
    end
    return released
end

function View:ReconcilePlayerHelpfulFilteredAuraDisplays(trusted)
    if not (self.active and Unit
        and Unit.SetFilteredAuraDisplayIdentitySuppressed) then
        return false, 0, 0
    end
    if trusted == nil then
        trusted = Unit.IsPlayerHelpfulAuraIdentityTrusted
            and Unit.IsPlayerHelpfulAuraIdentityTrusted() == true
    end
    local sources = YHUD.Sources
    if sources and sources.active then
        sources.auraIdentityTrusted = trusted == true
    end
    local suppressed = trusted ~= true
    local changed = false
    local restored = 0
    local eligible = 0
    for _, display in pairs(self.filteredAuraDisplays or {}) do
        local displayEligible = false
        local handles = display.handles
        local handleCount = handles and #handles
            or (display.handle and 1 or 0)
        for handleIndex = 1, handleCount do
            local handle = handles and handles[handleIndex]
                or display.handle
            if handle
                and handle.unit == "player"
                and handle.hasHelpfulFilter == true
                and handle.active == true
                and handle.released ~= true then
                displayEligible = true
                local handleChanged, handleRestored =
                    Unit.SetFilteredAuraDisplayIdentitySuppressed(
                        handle,
                        suppressed
                    )
                changed = handleChanged == true or changed
                restored = restored + (tonumber(handleRestored) or 0)
            end
        end
        if displayEligible then
            eligible = eligible + 1
            display.identitySuppressed = suppressed
            if display.dynamic ~= true then
                changed = SyncDisplayLayoutParticipation(display, true)
                    or changed
            end
            RefreshDisplayGlow(display)
        end
    end

    for owner, scope in pairs(self.barStackThresholdOwners) do
        local handle = owner.gui2AuraBarThresholdHandle
        if handle and Unit.SetFilteredAuraDisplayIdentitySuppressed then
            Unit.SetFilteredAuraDisplayIdentitySuppressed(handle, IsAuraIdentitySuppressed(scope))
        else
            self.barStackThresholdOwners[owner] = nil
        end
    end
    for _, record in pairs(self.buffTimerStackDisplays or {}) do
        for _, variant in ipairs(record.variants or {}) do
            Unit.SetFilteredAuraDisplayIdentitySuppressed(variant.handle, suppressed)
        end
        record.identitySuppressed = suppressed
        self:RefreshBuffTimerStackGlow(record)
    end
    local resourceChanged = false
    local resourceGroupId
    if self.SetResourceAuraIdentitySuppressed then
        for monitorId, slot in pairs(self.byMonitor or {}) do
            if slot and slot._yhudView == "resource" then
                local slotChanged, slotRestored, groupId =
                    self:SetResourceAuraIdentitySuppressed(
                        monitorId,
                        suppressed
                    )
                if slotChanged == true then
                    resourceChanged = true
                    changed = true
                    resourceGroupId = groupId or resourceGroupId
                end
                restored = restored + (tonumber(slotRestored) or 0)
            end
        end
    end
    if resourceChanged and resourceGroupId and self.RelayoutGroup then
        self:RelayoutGroup(resourceGroupId)
    end
    return changed, restored, eligible
end

function View:RefreshFilteredAuraGlowPresence()
    local changed = false
    for _, display in pairs(self.filteredAuraDisplays or {}) do
        local present = ResolveDisplayAuraPresence(display)
        if display.auraPresent ~= present then
            display.auraPresent = present
            SyncDisplayLayoutParticipation(display, true)
            changed = true
        end
    end
    return changed
end

function View:RefreshFilteredAuraMonitorGlow(monitorId, presenceRefreshed)
    if presenceRefreshed ~= true then
        self:RefreshFilteredAuraGlowPresence()
    end
    local records = self.filteredAuraGlowRecords
        and self.filteredAuraGlowRecords[monitorId]
    local changed = false
    for index = 1, #(records or {}) do
        changed = ApplyGlowRecord(records[index]) or changed
    end
    return changed
end

function View:SyncFilteredAuraDisplays(profile)
    self:ReleaseFilteredAuraDisplays()
    ResetFilteredAuraMonitorState(self.desiredMonitors)
    if not (self.active and not self.preview and not self.designMode
        and EnsureFilteredAuraDisplay()
        and Unit and Unit.CreateFilteredAuraDisplay) then
        return false
    end

    local built = false
    local byGroup = {}
    for groupId, runtime in pairs(self.groups or {}) do
        for _, monitorId in ipairs(runtime.externalBuffMonitorIds or {}) do
            local monitor = self.desiredMonitors[monitorId]
            local entry = monitor and profile.entries[monitor.entryKey]
            if monitor and entry then
                local display, code = BuildExternalBuffBlock(runtime, monitor, entry)
                if display then
                    self.filteredAuraDisplays["monitor:" .. monitorId] = display
                    monitor._yhudFilteredAuraManaged = true
                    runtime.hasExternalBuffBlock = true
                    built = true
                else
                    MarkFilteredAuraFailed({ monitor }, code)
                end
            end
        end
        local list
        for index = 1, runtime.monitorCount or 0 do
            local monitor = self.desiredMonitors[runtime.monitorIds[index]]
            local entry = monitor and profile.entries
                and profile.entries[monitor.entryKey]
            local nativeSingleLineProjection = monitor
                and self.ShouldUseFilteredAuraSingleLineNativeProjection
                and self:ShouldUseFilteredAuraSingleLineNativeProjection(
                    monitor.id,
                    runtime
                )
            if monitor and (YHUD:IsFilteredAuraMonitor(entry, monitor)
                or nativeSingleLineProjection == true) then
                list = list or {}
                list[#list + 1] = monitor
            end
        end
        if list then
            byGroup[groupId] = list
        end
    end

    for groupId, monitors in pairs(byGroup) do
        local runtime = self.groups[groupId]
        local firstEntry = profile.entries[monitors[1].entryKey]
        local groupScope = ResolveFilteredAuraScope(firstEntry)
        local projectionStrategy = runtime
            and runtime.filteredAuraProjectionStrategy
        local groupState = runtime and runtime.filteredAuraProjectionState
        local independent = projectionStrategy ==
                YHUD.FILTERED_AURA_LAYOUT_MIXED_DYNAMIC_SINGLE_LINE
            or projectionStrategy ==
                YHUD.FILTERED_AURA_LAYOUT_MIXED_SEGMENTED_OVERFLOW
            or (projectionStrategy == YHUD.FILTERED_AURA_LAYOUT_ENGINE_FLOW
                and groupState and groupState.hasScopeMismatch == true)
        local pure = projectionStrategy ==
                YHUD.FILTERED_AURA_LAYOUT_ENGINE_FLOW
            and not (groupState and groupState.hasScopeMismatch == true)
        if runtime and pure then
            local display, code = BuildPureGroup(
                runtime,
                monitors,
                groupScope
            )
            if display then
                self.filteredAuraDisplays["group:" .. groupId] = display
                for index = 1, #monitors do
                    monitors[index]._yhudFilteredAuraManaged = true
                end
                built = true
            else
                MarkFilteredAuraFailed(monitors, code)
            end
        elseif runtime then
            for index = 1, #monitors do
                local monitor = monitors[index]
                local entry = profile.entries[monitor.entryKey]
                local spellIDs = GetEntrySpellIDs(entry, monitor)
                local scope = entry and ResolveFilteredAuraScope(entry)
                local display, code
                if spellIDs then
                    if independent then
                        display, code = BuildDynamicMonitor(
                            runtime,
                            monitor,
                            entry,
                            spellIDs,
                            scope
                        )
                    else
                        display, code = BuildMixedMonitor(
                            runtime,
                            monitor,
                            entry,
                            spellIDs,
                            scope
                        )
                    end
                else
                    code = "filtered-aura-spell-identity-missing"
                end
                if display then
                    self.filteredAuraDisplays["monitor:" .. monitor.id] = display
                    if display.dynamic ~= true then
                        SyncDisplayLayoutParticipation(display, false)
                    end
                    monitor._yhudFilteredAuraManaged = true
                    built = true
                else
                    monitor._yhudFilteredAuraFailed = true
                    monitor._yhudFilteredAuraFailureCode =
                        code or "filtered-aura-create-failed"
                end
            end
        end
    end
    if built and self.ReconcilePlayerHelpfulFilteredAuraDisplays then
        self:ReconcilePlayerHelpfulFilteredAuraDisplays()
    end
    return built
end
