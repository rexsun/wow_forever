local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
local View = YHUD and YHUD.View
local I = View and View._internal
if not I then return end

local GUI2 = I.GUI2
local App = I.App
local ResourceCatalog = I.ResourceCatalog
local Glow = I.Glow
local RuntimeSound = I.Sound
local IsInCombat = I.IsInCombat
local QUESTION_ICON = I.QUESTION_ICON
local DEFAULT_ICON_SIZE = I.DEFAULT_ICON_SIZE
local DEFAULT_SPACING = I.DEFAULT_SPACING
local DEFAULT_MAX_PER_LINE = I.DEFAULT_MAX_PER_LINE
local LAYOUT_VIEWS = I.LAYOUT_VIEWS
local AddViewWrite = I.AddViewWrite
local SafeName = I.SafeName
local GroupName = I.GroupName
local GetIconLayout = I.GetIconLayout
local GetDurationLayout = I.GetDurationLayout
local GetResourceLayout = I.GetResourceLayout
local FormatMonitorName = I.FormatMonitorName
local GetEntryName = I.GetEntryName
local SameColor = I.SameColor
local SameGlowAppearance = I.SameGlowAppearance
local CacheGlowAppearance = I.CacheGlowAppearance
local ApplyRuntimeLayout = I.ApplyRuntimeLayout
local SetSlotIcon = I.SetSlotIcon
local ClearSlotDuration = I.ClearSlotDuration
local GetSlotIconTexture = I.GetSlotIconTexture
local ProfileNowMS = I.ProfileNowMS
local AddPerformanceStat = I.AddPerformanceStat
local FinishPerformanceStat = I.FinishPerformanceStat
local ICON_CUSTOM_GLOW_FRAME_LEVEL_OFFSET = 9

local RESOURCE_PREVIEW_MAX = {
    MANA = 100,
    RAGE = 100,
    FOCUS = 100,
    ENERGY = 100,
    COMBO_POINTS = 5,
    RUNES = 6,
    RUNIC_POWER = 100,
    SOUL_SHARDS = 5,
    LUNAR_POWER = 100,
    HOLY_POWER = 5,
    MAELSTROM = 100,
    CHI = 6,
    INSANITY = 100,
    ARCANE_CHARGES = 4,
    FURY = 100,
    ESSENCE = 6,
}

local RUNE_PREVIEW_READY = { true, true, true, true, true, true }
local RUNE_PREVIEW_DURATIONS = {}
local SLOT_SOURCE_TYPE = "yhud.inventory-slot-cooldown"

local function GetRuntimeGlowSize(runtime)
    if not runtime then return nil, nil end
    local width = runtime.itemWidth or runtime.iconWidth
        or runtime.diameter or runtime.iconSize
    local height = runtime.itemHeight or runtime.iconHeight
        or runtime.diameter or runtime.iconSize
    return width, height
end

local function GetMonitorGlowLayer(runtime, monitorId)
    if not (runtime and View.GetMonitorDisplayLayer) then
        return nil, nil
    end
    local level, strata = View:GetMonitorDisplayLayer(runtime, monitorId)
    if type(level) == "number" then
        level = level + ICON_CUSTOM_GLOW_FRAME_LEVEL_OFFSET
    else
        level = nil
    end
    return level, strata
end

local function IsActiveTrinketEntry(entry)
    if not (entry and entry.sourceType == SLOT_SOURCE_TYPE) then return false end
    local slotID = tonumber(entry.slotId or entry.slotID)
    return slotID == 13 or slotID == 14
end

local function ApplyResourcePreview(slot, preset)
    if not slot then return false end
    if View.ApplyDesignResourcePreviewSlot then
        return View:ApplyDesignResourcePreviewSlot(slot, preset, 1)
    end
    if not slot.SetResourceValues then return false end
    local maxValue = preset and preset.previewMax
        or RESOURCE_PREVIEW_MAX[preset and preset.powerToken] or 100
    local runePreview = preset and preset.provider
        and preset.provider.kind == "rune-cooldowns"
    return slot:SetResourceValues(
        nil,
        nil,
        false,
        maxValue,
        maxValue,
        nil,
        nil,
        false,
        runePreview and RUNE_PREVIEW_READY or nil,
        runePreview and RUNE_PREVIEW_DURATIONS or nil,
        nil,
        nil,
        true
    ) == true
end

local function ApplyResourceStructuralMax(slot, state)
    local structuralMax = state and state.structuralMax
    if type(structuralMax) ~= "number"
        or structuralMax < 1 or structuralMax > 100
        or structuralMax % 1 ~= 0
        or (slot._yhudResourceStructuralMax == structuralMax
            and not slot.gui2ResourceStructuralMaxPending) then
        return false
    end
    if slot.SetResourceStructuralMax
        and slot:SetResourceStructuralMax(structuralMax) then
        AddViewWrite(false)
    end
    if slot.gui2ResourceStructuralMaxPending then return false end
    slot._yhudResourceStructuralMax = structuralMax
    return true
end

local function ShouldDesaturateIcon(state)
    if not (state and state.available == true) then return false end
    if state.sourceKind == "spell" then
        if type(state.maxCharges) == "number"
            and state.maxCharges > 1
            and type(state.currentCharges) == "number" then
            return state.currentCharges <= 0
        end
        return state.cooldownActive == true
    end
    if state.sourceKind == "item" or state.sourceKind == "slot" then
        if state.secret == true then return false end
        if state.isEnabled == false or state.isEnabled == 0 then
            return true
        end
        return type(state.startTime) == "number"
            and state.startTime > 0
            and type(state.duration) == "number"
            and state.duration > 0
    end
    return false
end

function View:ApplyIconDesaturation(slot, state, forceDesaturated)
    if not (slot and GUI2.ApplyIconDesaturation) then return false end
    local desaturated = forceDesaturated == true
        or ShouldDesaturateIcon(state)
    if slot._yhudIconDesaturated == desaturated then return false end
    local durationWrite = false
    if slot.SetDurationDesaturated then
        durationWrite = slot:SetDurationDesaturated(desaturated) == true
    end
    local writes = GUI2:ApplyIconDesaturation(
        GetSlotIconTexture(slot),
        desaturated and 1 or 0,
        slot._yhudSharedIconState
    )
    slot._yhudIconDesaturated = desaturated
    if writes > 0 or durationWrite then AddViewWrite(false) end
    return writes > 0 or durationWrite
end

function View:ApplyCooldown(slot, state, runtime)
    if state.durationMode ~= nil then
        local durationMode = state.durationMode or "none"
        local durationObject = state.durationObject
        if durationMode == "none" and state.sourceKind == "spell"
            and state.isOnGCD == true and state.isEnabled ~= false
            and state.chargeActive ~= true and state.chargeStateSecret ~= true
            and runtime and runtime.view == "icon"
            and runtime.cooldownGCD ~= false then
            local spell = YUI.API and YUI.API.Spell
            durationObject = spell and spell.GetCooldownDurationObject
                and spell.GetCooldownDurationObject(state.spellID, false) or nil
            if durationObject ~= nil then durationMode = "gcd" end
        end
        local refreshArmed = false
        if durationMode ~= "none" then
            if durationObject ~= nil
                and (slot._yhudDurationMode ~= durationMode
                    or slot._yhudOpaqueRevision ~= state.opaqueRevision) then
                local bound = false
                if slot.SetDurationObject then
                    bound = slot:SetDurationObject(durationObject,
                        slot._yhudView == "bar" and slot.gui2DurationReverse == true)
                        ~= false
                elseif slot.SetCooldownDurationObject then
                    bound = slot:SetCooldownDurationObject(
                        durationObject
                    ) ~= false
                end
                if bound then
                    slot._yhudDurationMode = durationMode
                    slot._yhudOpaqueRevision = state.opaqueRevision
                    refreshArmed = durationMode ~= "gcd"
                else
                    slot._yhudDurationMode = nil
                    slot._yhudOpaqueRevision = nil
                end
                AddViewWrite(false)
            elseif durationObject ~= nil
                and slot._yhudDurationMode == durationMode then
                refreshArmed = durationMode ~= "gcd"
            end
        elseif slot._yhudDurationMode ~= "none" then
            slot._yhudDurationMode = "none"
            slot._yhudOpaqueRevision = state.opaqueRevision
            if slot.ClearDuration then
                slot:ClearDuration()
            elseif slot.SetCooldownDurationObject then
                slot:SetCooldownDurationObject(nil)
            elseif slot.SetCooldown then
                slot:SetCooldown(0, 0)
            end
            AddViewWrite(false)
        end
        slot._yhudCooldownRefreshArmed = refreshArmed
        return
    end

    if slot._yhudDurationMode and slot._yhudDurationMode ~= "none" then
        slot._yhudDurationMode = "none"
        slot._yhudOpaqueRevision = nil
        slot._yhudStart = nil
        slot._yhudDuration = nil
        if slot.ClearDuration then
            slot:ClearDuration()
        elseif slot.SetCooldownDurationObject then
            slot:SetCooldownDurationObject(nil)
        end
        AddViewWrite(false)
    end

    local cooldownActive = state.secret ~= true
        and state.isEnabled ~= false
        and state.isEnabled ~= 0
        and type(state.startTime) == "number"
        and state.startTime > 0
        and type(state.duration) == "number"
        and state.duration > 0
    local startTime = cooldownActive and state.startTime or 0
    local duration = cooldownActive and state.duration or 0
    slot._yhudCooldownRefreshArmed = cooldownActive
    if slot._yhudStart ~= startTime or slot._yhudDuration ~= duration then
        slot._yhudStart = startTime
        slot._yhudDuration = duration
        if not cooldownActive and slot.ClearDuration then
            slot:ClearDuration()
        elseif slot.SetDurationFromTimes then
            slot:SetDurationFromTimes(
                startTime,
                duration,
                state.modRate,
                slot._yhudView == "bar" and slot.gui2DurationReverse == true
            )
        elseif slot.SetCooldown then
            slot:SetCooldown(
                startTime,
                duration,
                state.modRate
            )
        end
        AddViewWrite(false)
    end
end

function View:ApplyMonitorGlow(
    slot,
    monitor,
    state,
    nativeSignal,
    auraResolved,
    auraPresent,
    persistentSlot
)
    local compiled = slot._yhudGlowRuntime
        or monitor and monitor._yhudGlowRuntime
    local preview = self.preview == true
        or slot._yhudDesignProjection == true
    if auraResolved == nil
        and monitor
        and monitor._yhudEquipmentTriggerKind == "active-timer"
        and type(state) == "table"
        and state.sourceKind == "buff-timer"
        and state.secret ~= true
        and state.resolved == true then
        auraResolved = true
        auraPresent = state.available == true
    end
    if persistentSlot == nil and compiled and compiled.kind == "aura" then
        persistentSlot = monitor and monitor.visibilityMode == "always"
    end
    local kind, appearance = Glow:Resolve(
        compiled,
        state,
        self.inCombat == true,
        preview,
        nativeSignal,
        auraResolved,
        auraPresent,
        persistentSlot
    )
    if not kind then
        if slot._yhudNativeProcGlowShown == true
            and slot._yhudNativeProcGlow
            and GUI2.SetManagedProcGlowShown then
            GUI2:SetManagedProcGlowShown(
                slot._yhudNativeProcGlow,
                false
            )
            slot._yhudNativeProcGlowShown = false
            AddViewWrite(false)
        end
        if slot._yhudGlowShown == true
            and slot.gui2Glow
            and slot.gui2Glow.SetGlowShown then
            slot.gui2Glow:SetGlowShown(false)
            slot._yhudGlowShown = false
            AddViewWrite(false)
        end
        return false
    end

    local runtime = monitor and monitor.groupId
        and slot._yhudDesignProjection == true
        and self.designProjection
        and self.designProjection.groups
        and self.designProjection.groups[monitor.groupId]
        or (monitor and monitor.groupId and self.groups[monitor.groupId])
    local glowShape = runtime and runtime.view == "ring"
        and "circle"
        or (runtime and runtime.shape)
    glowShape = glowShape or "square"
    local procShape = glowShape == "circle" and "circle" or "square"
    local customGlowShape = appearance and appearance.style == "proc"
        and procShape or glowShape
    local monitorId = monitor and monitor.id or slot._yhudMonitorId
    local trustedDisplayWidth, trustedDisplayHeight =
        GetRuntimeGlowSize(runtime)
    local glowFrameLevel, glowFrameStrata =
        GetMonitorGlowLayer(runtime, monitorId)

    if kind == "native-default" and GUI2.CreateManagedProcGlow then
        if slot._yhudGlowShown == true
            and slot.gui2Glow and slot.gui2Glow.SetGlowShown then
            slot.gui2Glow:SetGlowShown(false)
            slot._yhudGlowShown = false
            AddViewWrite(false)
        end
        if not slot._yhudNativeProcGlow
            or slot._yhudNativeProcGlowShape ~= procShape then
            if slot._yhudNativeProcGlow
                and GUI2.SetManagedProcGlowShown then
                GUI2:SetManagedProcGlowShown(
                    slot._yhudNativeProcGlow,
                    false
                )
                slot._yhudNativeProcGlowShown = false
                AddViewWrite(false)
            end
            local cacheField = procShape == "circle"
                and "_yhudNativeProcCircle"
                or "_yhudNativeProcSquare"
            slot._yhudNativeProcGlow = slot[cacheField]
            if not slot._yhudNativeProcGlow then
                slot._yhudNativeProcGlow =
                    GUI2:CreateManagedProcGlow(
                        slot,
                        procShape,
                        trustedDisplayWidth,
                        trustedDisplayHeight,
                        glowFrameLevel,
                        glowFrameStrata,
                        glowShape
                    )
                slot[cacheField] = slot._yhudNativeProcGlow
            end
            slot._yhudNativeProcGlowShape = procShape
            slot._yhudNativeProcGlowTargetShape = glowShape
            slot._yhudNativeProcGlowLayoutDirty = true
        end
        if slot._yhudNativeProcGlowTargetShape ~= glowShape then
            slot._yhudNativeProcGlowTargetShape = glowShape
            slot._yhudNativeProcGlowLayoutDirty = true
        end
        local procGlow = slot._yhudNativeProcGlow
        if not procGlow then return false end
        local procLayerDirty = slot._yhudNativeProcGlowFrameLevel
                ~= glowFrameLevel
            or slot._yhudNativeProcGlowFrameStrata ~= glowFrameStrata
        if (slot._yhudNativeProcGlowLayoutDirty == true
                or procLayerDirty)
            and GUI2.LayoutManagedProcGlow then
            GUI2:LayoutManagedProcGlow(
                procGlow,
                slot,
                trustedDisplayWidth,
                trustedDisplayHeight,
                glowFrameLevel,
                glowFrameStrata,
                glowShape
            )
            slot._yhudNativeProcGlowLayoutDirty = false
            slot._yhudNativeProcGlowFrameLevel = glowFrameLevel
            slot._yhudNativeProcGlowFrameStrata = glowFrameStrata
            AddViewWrite(false)
        end
        if slot._yhudNativeProcGlowShown ~= true
            and GUI2.SetManagedProcGlowShown then
            GUI2:SetManagedProcGlowShown(procGlow, true)
            slot._yhudNativeProcGlowShown = true
            AddViewWrite(false)
        end
        return true
    end

    if slot._yhudNativeProcGlowShown == true
        and slot._yhudNativeProcGlow
        and GUI2.SetManagedProcGlowShown then
        GUI2:SetManagedProcGlowShown(slot._yhudNativeProcGlow, false)
        slot._yhudNativeProcGlowShown = false
        AddViewWrite(false)
    end
    local glow = slot.gui2Glow
    local restrictedGlow = slot._yhudFilteredAuraGlow == true
        or slot._yhudFilteredAuraChainCompatible == true
        or slot._yhudRestrictedGlowPreview == true
    local trustedWidth = restrictedGlow and trustedDisplayWidth or nil
    local trustedHeight = restrictedGlow and trustedDisplayHeight or nil
    if not glow and GUI2.CreateGlow then
        glow = GUI2:CreateGlow(slot, {
            hidden = true,
            restrictedParent = restrictedGlow,
            trustedWidth = trustedWidth,
            trustedHeight = trustedHeight,
            trustedFrameLevel = glowFrameLevel,
            trustedFrameStrata = glowFrameStrata,
        })
    end
    if not glow then return false end

    if glow._SetGlowLayoutContext
        and glow:_SetGlowLayoutContext(
            restrictedGlow,
            trustedWidth,
            trustedHeight
        ) then
        glow:SetGlowParams({})
        AddViewWrite(false)
    end

    if glow._SetGlowLayerContext
        and glow:_SetGlowLayerContext(
            glowFrameLevel,
            glowFrameStrata
        ) then
        AddViewWrite(false)
    end

    if glow.SetGlowShape and (slot._yhudGlowShape ~= customGlowShape
            or slot._yhudGlowTargetShape ~= glowShape) then
        glow:SetGlowShape(customGlowShape, glowShape)
        slot._yhudGlowShape = customGlowShape
        slot._yhudGlowTargetShape = glowShape
        AddViewWrite(false)
    end

    if not SameGlowAppearance(slot, appearance) then
        glow:SetGlowParams(appearance)
        CacheGlowAppearance(slot, appearance)
        AddViewWrite(false)
    end

    if slot._yhudGlowShown ~= true then
        glow:SetGlowShown(true)
        slot._yhudGlowShown = true
        AddViewWrite(false)
    end
    return true
end

function View:UpdateMonitor(monitorId, state)
    local monitor = self.desiredMonitors[monitorId]
    if not monitor then
        return self:ReleaseSlot(monitorId), nil
    end
    local runtime = self.groups[monitor.groupId]
    if not (runtime and runtime.enabled) then
        return self:ReleaseSlot(monitorId), monitor.groupId
    end
    local layoutParticipating = self.IsMonitorLayoutParticipating == nil
        or self:IsMonitorLayoutParticipating(
            monitor,
            state,
            runtime.layoutMode == "fixed"
        )
    if layoutParticipating ~= true then
        local slot = self.byMonitor[monitorId]
        if slot then slot._yhudLayoutParticipating = false end
        return self:ReleaseSlot(monitorId), monitor.groupId
    end
    if monitor._yhudFilteredAuraManaged == true
        or monitor._yhudFilteredAuraFailed == true then
        return self:ReleaseSlot(monitorId), monitor.groupId
    end

    local entry = self.profile
        and self.profile.entries
        and self.profile.entries[monitor.entryKey]
    local officialCDM = entry and entry.origin == "official-cdm"
    local nativeOfficialView = officialCDM
        and YHUD.IsOfficialNativeView
        and YHUD:IsOfficialNativeView(
            entry.officialCategory,
            monitor.view
        )
    local persistentDisplay = monitor.visibilityMode == "always"
        and YHUD.SupportsPersistentDisplay
        and YHUD:SupportsPersistentDisplay(entry)
    local nativePersistentPlaceholder = persistentDisplay
        and nativeOfficialView
        and not self.preview
        and runtime.view == "icon"
        and entry.officialCategory == "trackedBuff"
    local filteredAuraChainProjection =
        self.ShouldUseFilteredAuraChainSlot
        and self:ShouldUseFilteredAuraChainSlot(monitorId, runtime)
        or self.ShouldUseFilteredAuraSingleLineNativeProjection
            and self:ShouldUseFilteredAuraSingleLineNativeProjection(
                monitorId,
                runtime
            )
    if nativeOfficialView and not self.preview and not persistentDisplay
        and filteredAuraChainProjection ~= true then
        return self:ReleaseSlot(monitorId), monitor.groupId
    end
    local inactivePersistent = persistentDisplay
        and (nativePersistentPlaceholder
            or not state or state.available ~= true)
    local explicitlyUnavailable =
        self.unavailableMonitors
        and self.unavailableMonitors[monitorId] == true
        or (entry and entry.isKnown == false)
    if officialCDM
        and not self.preview
        and not inactivePersistent
        and (not state or state.available ~= true) then
        explicitlyUnavailable = true
    end
    local activeTrinket = IsActiveTrinketEntry(entry)
    local filteredAuraBound = runtime.view == "resource"
        and state
        and (state.backendStatus == "filtered-aura-application"
            or state.backendStatus == "filtered-aura-duration")
    local visible = not explicitlyUnavailable
        and state
        and state.available == true
    if not activeTrinket then
        visible = self.preview
            or (not explicitlyUnavailable
                and (inactivePersistent
                    or (state and state.available == true)))
    end
    local resourceVisibilitySuppressed = false
    if state and state.sourceKind == "ammo" and state.nameKey == "monitor.ammo.unsupported" then
        visible = false
    end
    if visible and runtime.view == "resource" and not self.preview
        and state and state.secret ~= true
        and type(state.value) == "number" and state.value <= 0 then
        local mode = monitor.resourceVisibilityMode
        visible = mode == "always"
            or (mode == "nonzeroOrCombat" and self.inCombat == true)
        resourceVisibilitySuppressed = not visible
            and (mode == "nonzero" or mode == "nonzeroOrCombat")
    end
    if visible and runtime.view == "ring"
        and not self.preview and not inactivePersistent then
        if state and state.durationMode ~= nil then
            visible = state.cooldownActive == true
                or state.chargeActive == true
        elseif state and state.secret ~= true then
            visible = type(state.startTime) == "number"
                and state.startTime > 0
                and type(state.duration) == "number"
                and state.duration > 0
                and state.isEnabled ~= false
        else
            visible = false
        end
    end
    if not visible then
        local fixedResource = runtime.view == "resource"
            and runtime.layoutMode == "fixed"
        if (resourceVisibilitySuppressed or fixedResource)
            and self.SetResourceSlotSuppressed then
            local structuralChange = false
            if not self.byMonitor[monitorId] then
                local slot, acquired = self:AcquireSlot(monitorId, runtime)
                structuralChange = slot ~= nil and acquired == true
            end
            local slot = self.byMonitor[monitorId]
            if slot and ApplyResourceStructuralMax(slot, state) then
                structuralChange = true
            end
            local suppressed = self:SetResourceSlotSuppressed(monitorId, true)
            return structuralChange or suppressed, monitor.groupId
        end
        return self:ReleaseSlot(monitorId), monitor.groupId
    end

    local slot, acquired = self:AcquireSlot(monitorId, runtime)
    if not slot then return false, monitor.groupId end
    slot._yhudLayoutParticipating =
        monitor._yhudEquipmentTriggerKind == "active-timer"
            and true or nil
    slot._yhudNativePersistentPlaceholder =
        nativePersistentPlaceholder == true or nil

    if runtime.view == "resource" then
        local preset = monitor._yhudResource or {}
        local effectiveStyle = slot._yhudResourceStyle or runtime
        local fillColor = effectiveStyle.fillColorMode == "custom"
            and effectiveStyle.fillColor
            or (state and state.color or preset.color)
        if fillColor and not SameColor(slot._yhudFillColor, fillColor) then
            slot._yhudFillColor = fillColor
            if slot.SetResourceFillColor then
                slot:SetResourceFillColor(fillColor)
            end
            AddViewWrite(false)
        end
        ApplyResourceStructuralMax(slot, state)

        local curveMaximum = state and (state.structuralMax or state.publicMaxValue)
        if curveMaximum ~= slot._yhudResourceCurveMax and I.RefreshResourceColorCurve then
            I.RefreshResourceColorCurve(slot, curveMaximum)
        end
        local colorRaw = state and state.colorRaw
        local unitAPI = YUI.API and YUI.API.Unit
        if state and state.secret == true and state.rawValuesAvailable == true
            and slot._yhudResourceColorCurve and unitAPI and unitAPI.ReadPowerColor then
            colorRaw = unitAPI.ReadPowerColor("player", preset.powerType, slot._yhudResourceColorCurve)
        end

        local applied = false
        local wrote = false
        if self.preview then
            ApplyResourcePreview(slot, preset)
        end
        if filteredAuraBound then
            applied = true
        elseif state and state.available == true
            and slot.SetResourceValues then
            local hasTransientSecretValues = state.secret ~= true
                or state.rawValuesAvailable == true
            local missingIndependentCells = preset and preset.provider
                and preset.provider.kind == "rune-cooldowns"
                and state.cellReadyRaw == nil
            if missingIndependentCells then
                -- 独立符文格在完整 View 刷新后等待 Source 强制重放；
                -- 不用缺失的瞬态数组把现有六格清空。
                applied = true
            elseif hasTransientSecretValues then
                wrote = true
                applied = slot:SetResourceValues(
                    state.valueRaw,
                    state.maxValueRaw,
                    state.secret == true,
                    state.value,
                    state.maxValue,
                    colorRaw,
                    state.rechargeDurationRaw,
                    state.rechargeActive,
                    state.cellReadyRaw,
                    state.cellDurationsRaw,
                    state.durationResourceRaw,
                    state.timerEntriesRaw,
                    nil,
                    state.percentRaw,
                    state.partialFraction,
                    state.displayValue,
                    state.chargedPointMask
                ) == true
                if slot.ConsumeResourceRechargeRetry
                    and slot:ConsumeResourceRechargeRetry()
                    and YHUD.SpecialResources
                    and YHUD.SpecialResources.RequestChargeRetry then
                    YHUD.SpecialResources:RequestChargeRetry(state.sourceKey)
                end
            elseif state.secret == true then
                -- 秘密资源原始值只在数据分发当次有效。冷路径刷新读到的
                -- 持久状态故意不含原始值，此时应保留当前原生 StatusBar
                -- 画面，等待下一次来源刷新，而不是把它误清为 0。
                applied = true
            end
        end
        if not applied and not self.preview then
            ClearSlotDuration(slot)
            wrote = true
        end
        if wrote then AddViewWrite(false) end
        return acquired, monitor.groupId
    end

    local entry = self.profile.entries and self.profile.entries[monitor.entryKey]
    local icon = state and state.icon
        or monitor._yhudDisplayIcon
        or (entry and entry.icon)
        or QUESTION_ICON
    if YHUD.Ammo and entry and entry.sourceType == YHUD.Ammo.SOURCE_TYPE then
        icon = YHUD.Ammo:ResolveIcon(state, false)
    end
    if state and state.sourceKind == "ammo" then
        slot._yhudTooltipSlotID = nil
        slot._yhudTooltipItemID = state.itemID
        slot._yhudTooltipName = YHUD:T(state.nameKey, GetEntryName(entry))
    end
    if slot._yhudIcon ~= icon then
        slot._yhudIcon = icon
        SetSlotIcon(slot, icon)
        AddViewWrite(false)
    end
    if runtime.view == "bar" or runtime.view == "ring" then
        local name = slot._yhudDisplayName
        if slot._yhudName ~= name then
            slot._yhudName = name
            if slot.SetDurationName then slot:SetDurationName(name) end
            AddViewWrite(false)
        end
    end
    if inactivePersistent then
        ClearSlotDuration(slot)
    elseif state then
        self:ApplyCooldown(slot, state, runtime)
    else
        ClearSlotDuration(slot)
    end
    self:ApplyIconCooldownPresentation(slot, runtime, entry)
    local inactiveDesaturate = inactivePersistent
        and YHUD.GetEffectiveInactiveDesaturate
        and YHUD:GetEffectiveInactiveDesaturate(
            self.profile,
            monitor,
            entry
        ) == true
    self:ApplyIconDesaturation(
        slot,
        state,
        inactiveDesaturate
            or (self.preview and explicitlyUnavailable)
    )
    if state and state.countSecret == true and slot.SetRawCount then
        local rawCount = state.displayCountRaw
        if rawCount ~= nil then
            if _G.C_StringUtil and _G.C_StringUtil.TruncateWhenZero then
                rawCount = _G.C_StringUtil.TruncateWhenZero(rawCount)
            end
            if slot:SetRawCount(rawCount) then
                slot._yhudRawCountShown = true
                slot._yhudDisplayCount = nil
                AddViewWrite(false)
            end
        end
    elseif slot.SetCount then
        local count = not inactivePersistent and state and state.displayCount
        if state and state.sourceKind == "ammo" then
            if state.nameKey == "monitor.ammo.missing" then count = "—"
            elseif count == nil then count = "?" end
        elseif type(count) == "number" and count <= 0 then
            count = nil
        end
        if slot._yhudRawCountShown or slot._yhudDisplayCount ~= count then
            slot._yhudRawCountShown = false
            slot._yhudDisplayCount = count
            slot:SetCount(count)
            AddViewWrite(false)
        end
    end
    self:ApplyMonitorGlow(slot, monitor, state)
    if self.designMode then
        if self.ApplyDesignDurationPreview then
            self:ApplyDesignDurationPreview(slot)
        elseif self.ApplyDesignTextPreview then
            self:ApplyDesignTextPreview(slot)
        end
    end
    return acquired, monitor.groupId
end

function View:ObserveMonitorSound(monitor, state)
    if not (monitor
        and monitor._yhudNativeAuraSoundManaged ~= true
        and RuntimeSound
        and RuntimeSound.Observe) then
        return false
    end
    local auraResolved
    local auraPresent
    if monitor._yhudEquipmentTriggerKind == "active-timer"
        and type(state) == "table"
        and state.sourceKind == "buff-timer"
        and state.secret ~= true
        and state.resolved == true then
        auraResolved = true
        auraPresent = state.available == true
    end
    return RuntimeSound:Observe(
        monitor,
        monitor._yhudSoundRuntime,
        state,
        auraResolved,
        auraPresent,
        monitor.visibilityMode == "always",
        self.preview == true
            or self.designMode == true
            or self.layoutEditMode == true
    )
end

function View:UpdateSource(state)
    if not self.active or type(state) ~= "table" then return false end
    local designUpdated = self.RefreshDesignProjectionSourceIcon
        and self:RefreshDesignProjectionSourceIcon(state) == true
        or false
    local sourceKey = state.sourceKey
    local monitorIds = sourceKey and self.monitorsBySource[sourceKey]
    if not monitorIds then return designUpdated end

    local changedGroups
    local updated = false
    for index = 1, #monitorIds do
        local monitorId = monitorIds[index]
        local changedLayout, groupId = self:UpdateMonitor(monitorId, state)
        local monitor = self.desiredMonitors[monitorId]
        self:ObserveMonitorSound(monitor, state)
        local runtime = monitor and self.groups[monitor.groupId]
        if runtime and runtime.nativeByMonitor
            and runtime.nativeByMonitor[monitorId]
            and YHUD.NativeBridge
            and YHUD.NativeBridge.RefreshMonitorGlow then
            YHUD.NativeBridge:RefreshMonitorGlow(monitorId)
        end
        updated = true
        if changedLayout and groupId then
            changedGroups = changedGroups or {}
            changedGroups[groupId] = true
        end
    end
    if changedGroups then
        for groupId in pairs(changedGroups) do
            self:RelayoutGroup(groupId)
        end
        for index = 1, #monitorIds do
            local monitorId = monitorIds[index]
            local monitor = self.desiredMonitors[monitorId]
            local slot = self.byMonitor[monitorId]
            local glow = slot and slot.gui2Glow
            if monitor and changedGroups[monitor.groupId]
                and slot and slot._yhudGlowShown == true
                and glow and glow.SetGlowShown then
                glow:SetGlowShown(true)
                AddViewWrite(false)
            end
        end
    end
    return updated or designUpdated
end

function View:RefreshLayoutPreview(entering)
    if not self.active then return false end
    entering = entering == true

    for monitorId in pairs(self.byMonitor) do
        if not self.desiredMonitors[monitorId] then
            self:ReleaseSlot(monitorId)
        end
    end

    for monitorId, monitor in pairs(self.desiredMonitors) do
        local runtime = self.groups[monitor.groupId]
        local slot = self.byMonitor[monitorId]
        local refreshMonitor = not entering
            or not slot
            or (runtime and runtime.view == "resource")
        local state = YHUD.Model and YHUD.Model:GetState(monitor.sourceKey)
        if refreshMonitor then
            self:UpdateMonitor(monitorId, state)
        elseif self.ApplyMonitorGlow then
            self:ApplyMonitorGlow(slot, monitor, state)
        end
    end

    for groupId in pairs(self.groups) do
        self:RelayoutGroup(groupId)
    end
    return true
end

function View:RefreshAll()
    if not self.active then return false end
    for monitorId in pairs(self.byMonitor) do
        if not self.desiredMonitors[monitorId] then
            self:ReleaseSlot(monitorId)
        end
    end
    for monitorId, monitor in pairs(self.desiredMonitors) do
        local state = YHUD.Model and YHUD.Model:GetState(monitor.sourceKey)
        self:UpdateMonitor(monitorId, state)
    end
    self:Relayout()
    return true
end

function View:RefreshCombatResourceVisibility(monitorId, enteringCombat)
    local monitor = self.desiredMonitors[monitorId]
    if not monitor then return false, nil end
    local runtime = self.groups[monitor.groupId]
    local slot = self.byMonitor[monitorId]
    local state = YHUD.Model and YHUD.Model:GetState(monitor.sourceKey)
    local entry = self.profile
        and self.profile.entries
        and self.profile.entries[monitor.entryKey]
    local unavailable = self.unavailableMonitors
        and self.unavailableMonitors[monitorId] == true
        or (entry and entry.isKnown == false)
    local coldBoundary = monitor.resourceVisibilityMode ~= "nonzeroOrCombat"
        or not runtime
        or runtime.enabled ~= true
        or runtime.view ~= "resource"
        or self.preview
        or self.designMode
        or self.layoutEditMode
        or not self.SetResourceSlotSuppressed
    if coldBoundary then
        AddPerformanceStat("combatResourceFallbacks")
        return self:UpdateMonitor(monitorId, state)
    end

    -- Filtered-Aura structure is owned by its source/config refresh path.
    if monitor._yhudFilteredAuraManaged == true then
        AddPerformanceStat("combatResourceFastPathHits")
        return false, monitor.groupId
    end

    -- An absent source normally has no visibility transition to project. If a
    -- slot survived the source becoming unavailable, however, use the existing
    -- full update path to release that stale structure.
    if unavailable or not state or state.available ~= true then
        if slot then
            AddPerformanceStat("combatResourceFallbacks")
            return self:UpdateMonitor(monitorId, state)
        end
        AddPerformanceStat("combatResourceFastPathHits")
        return false, monitor.groupId
    end

    -- A valid source without its expected retained slot is a real structural
    -- mismatch. Preserve the existing full update as a narrow self-healing path.
    if not slot
        or slot._yhudView ~= "resource"
        or slot._yhudGroupId ~= runtime.id
    then
        AddPerformanceStat("combatResourceFallbacks")
        return self:UpdateMonitor(monitorId, state)
    end

    AddPerformanceStat("combatResourceFastPathHits")
    local suppress = enteringCombat ~= true
        and state.secret ~= true
        and type(state.value) == "number"
        and state.value <= 0
    return self:SetResourceSlotSuppressed(monitorId, suppress), monitor.groupId
end

function View:RefreshGlows(inCombat)
    if not self.active then return false end
    local startedAt = ProfileNowMS()
    AddPerformanceStat("combatRefreshes")
    local monitors = self.combatGlowMonitors
    local resourceMonitors = self.combatResourceMonitors or {}
    local requestedCombat
    if type(inCombat) == "boolean" then
        requestedCombat = inCombat
    else
        requestedCombat = IsInCombat()
    end
    local edgeElapsedField = requestedCombat
        and "combatEntryRefreshMS" or "combatExitRefreshMS"
    self.inCombat = requestedCombat
    local refreshed = false
    local glowStartedAt = ProfileNowMS()
    local nativeBridge = YHUD.NativeBridge
    if nativeBridge and nativeBridge.RefreshGlowCombatState then
        refreshed = nativeBridge:RefreshGlowCombatState(requestedCombat)
            or refreshed
    end
    if self.RefreshFilteredAuraGlowPresence then
        local frameRecords = self.filteredAuraFrameRecords
        if frameRecords and next(frameRecords) then
            self:RefreshFilteredAuraGlowPresence()
        end
    end
    if (not monitors or not next(monitors)) and #resourceMonitors == 0 then
        FinishPerformanceStat("combatGlowApplyMS", glowStartedAt)
        FinishPerformanceStat("combatRefreshMS", startedAt)
        FinishPerformanceStat(edgeElapsedField, startedAt)
        return refreshed
    end
    for monitorId in pairs(monitors or {}) do
        local slot = self.byMonitor[monitorId]
        local monitor = self.desiredMonitors[monitorId]
        if slot and monitor then
            local state = YHUD.Model
                and YHUD.Model:GetState(monitor.sourceKey)
            self:ApplyMonitorGlow(slot, monitor, state)
            refreshed = true
        elseif monitor and self.RefreshFilteredAuraMonitorGlow then
            refreshed = self:RefreshFilteredAuraMonitorGlow(monitorId, true)
                or refreshed
        end
    end
    FinishPerformanceStat("combatGlowApplyMS", glowStartedAt)
    local resourceVisibilityStartedAt = ProfileNowMS()
    local changedGroups = self.combatResourceChangedGroups
    for groupId in pairs(changedGroups) do changedGroups[groupId] = nil end
    for index = 1, #resourceMonitors do
        local monitorId = resourceMonitors[index]
        local monitor = self.desiredMonitors[monitorId]
        if monitor then
            local changedLayout, groupId =
                self:RefreshCombatResourceVisibility(
                    monitorId,
                    requestedCombat
                )
            if changedLayout and groupId then changedGroups[groupId] = true end
            refreshed = true
        end
    end
    FinishPerformanceStat(
        "combatResourceVisibilityMS",
        resourceVisibilityStartedAt
    )
    local resourceProjectionStartedAt = ProfileNowMS()
    for groupId in pairs(changedGroups) do
        local runtime = self.groups[groupId]
        local fixedLayout = runtime and runtime.layoutMode == "fixed"
        local projected = fixedLayout
            and self.ProjectFixedResourceVisibility
            and self:ProjectFixedResourceVisibility(groupId) == true
        if not projected and not fixedLayout then
            projected = self.ProjectSingleResourceVisibility
                and self:ProjectSingleResourceVisibility(groupId) == true
        end
        if not projected and not fixedLayout then
            projected = self.ProjectPreparedResourcePrefix
                and self:ProjectPreparedResourcePrefix(groupId) == true
        end
        if not projected and not fixedLayout then
            projected = self.ProjectPreparedResourceEdgeLayout
                and self:ProjectPreparedResourceEdgeLayout(groupId) == true
        end
        if not projected then
            local relayoutStartedAt = ProfileNowMS()
            self:RelayoutGroup(groupId, true)
            AddPerformanceStat("resourceRelayouts")
            FinishPerformanceStat("resourceRelayoutMS", relayoutStartedAt)
        end
        changedGroups[groupId] = nil
    end
    FinishPerformanceStat(
        "combatResourceProjectionMS",
        resourceProjectionStartedAt
    )
    FinishPerformanceStat("combatRefreshMS", startedAt)
    FinishPerformanceStat(edgeElapsedField, startedAt)
    return refreshed
end
