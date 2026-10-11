local addonName, ns = ...
local l = ns.I18N;

-- * avoid conflict override
if ns.CONFLICT then return; end

local RaidFrameAuras = ns.RaidFrameAuras
if not RaidFrameAuras then return end

local Constants = ns.Constants or {}
local DEFAULTS = ns.DEFAULTS or {}
local State = ns.State or {}
local Util = ns.Util or {}
local C_UnitAuras = C_UnitAuras

State.layoutVersion = State.layoutVersion or 0

local ICON_DRAW_LAYER = "ARTWORK"
local ICON_DRAW_LEVEL = 0
local BORDER_DRAW_LAYER = "BACKGROUND"
local BORDER_DRAW_LEVEL = -1

local function NumberKey(value)
    return tostring(math.floor((tonumber(value) or 0) * 100 + 0.5))
end

local function ConfigureAuraIconMouse(icon)
    if not icon then return end
    -- RFA owns hover so tooltip options are authoritative; clicks are disabled on the aura itself.
    icon:EnableMouse(true)
    if icon.SetMouseMotionEnabled then
        icon:SetMouseMotionEnabled(true)
    end
    if icon.SetPropagateMouseMotion then
        icon:SetPropagateMouseMotion(false)
    end
    if icon.SetPropagateMouseClicks then
        icon:SetPropagateMouseClicks(true)
    end
    if icon.SetMouseClickEnabled then
        icon:SetMouseClickEnabled(false)
    end
end

local function GetAuraFrameStrata(db)
    return (db and db.auraFrameStrata) or DEFAULTS.auraFrameStrata or "LOW"
end

local function GetAuraAnchorTargetSetting(db)
    local validTargets = Constants.VALID_AURA_ANCHOR_TARGETS or {}
    local target = (db and db.auraAnchorTarget) or DEFAULTS.auraAnchorTarget or "FRAME"
    if not validTargets[target] then
        target = DEFAULTS.auraAnchorTarget or "FRAME"
    end
    return target
end

local function IsAnchorableRegion(region)
    return type(region) == "table" and type(region.SetPoint) == "function"
end

local function GetSafeRegionNumber(region, method)
    if not region or type(region[method]) ~= "function" then return nil end
    local value = Util.AsSafeNumber(region[method](region))
    if value == nil then return nil end
    return value
end

local function GetRegionOffset(reference, region, method, fallback)
    local referenceValue = GetSafeRegionNumber(reference, method)
    local regionValue = GetSafeRegionNumber(region, method)
    if referenceValue and regionValue then
        return regionValue - referenceValue
    end
    return fallback or 0
end

local function GetFrameHealthBar(frame)
    if not frame then return nil end
    local healthBar = frame.healthBar or frame.HealthBar or frame.healthbar
    if IsAnchorableRegion(healthBar) then
        return healthBar
    end
    return nil
end

local function GetFrameMaxHealthLossBar(frame)
    if not frame then return nil end
    local maxHealthLossBar = frame.TempMaxHealthLoss or frame.tempMaxHealthLoss
    if IsAnchorableRegion(maxHealthLossBar) then
        return maxHealthLossBar
    end

    local healthBarsContainer = frame.HealthBarsContainer or frame.healthBarsContainer
    if type(healthBarsContainer) == "table" then
        maxHealthLossBar = healthBarsContainer.TempMaxHealthLoss or healthBarsContainer.tempMaxHealthLoss
        if IsAnchorableRegion(maxHealthLossBar) then
            return maxHealthLossBar
        end
    end

    return nil
end

local function GetStableHealthBarAnchorTarget(frame)
    local healthBar = GetFrameHealthBar(frame)
    local maxHealthLossBar = GetFrameMaxHealthLossBar(frame)
    if not healthBar or not maxHealthLossBar then
        return healthBar
    end

    local anchor = frame.rfaStableHealthBarAnchor
    if not IsAnchorableRegion(anchor) then
        anchor = RaidFrameAuras:CreatePrivateFrame("Frame", "HealthBarAnchor", frame)
        anchor:EnableMouse(false)
        frame.rfaStableHealthBarAnchor = anchor
    end

    local powerBarUsedHeight = Util.AsSafeNumber(frame.powerBarUsedHeight, 0) or 0
    local rightOffset = GetRegionOffset(frame, maxHealthLossBar, "GetRight", -1)
    local bottomOffset = GetRegionOffset(frame, healthBar, "GetBottom", 1 + powerBarUsedHeight)
    local key = tostring(healthBar) .. ":" .. tostring(maxHealthLossBar) .. ":" .. NumberKey(rightOffset) .. ":" .. NumberKey(bottomOffset)
    if anchor.rfaStableHealthBarAnchorKey ~= key then
        anchor:ClearAllPoints()
        anchor:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
        -- Blizzard narrows frame.healthBar when temporary max HP loss is shown.
        -- Keep RFA's health-bar target on the full right edge instead.
        anchor:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", rightOffset, bottomOffset)
        anchor.rfaStableHealthBarAnchorKey = key
    end

    return anchor
end

local function GetAuraAnchorTarget(frame, db)
    if GetAuraAnchorTargetSetting(db) == "HEALTH_BAR" then
        return GetStableHealthBarAnchorTarget(frame) or frame
    end
    return frame
end

local function GetAuraAnchorTargetKey(frame, db)
    local target = GetAuraAnchorTarget(frame, db)
    if target == frame then
        return "FRAME"
    end
    return "HEALTH_BAR:" .. tostring(target)
end

function RaidFrameAuras:GetAuraAnchorTarget(frame)
    return GetAuraAnchorTarget(frame, self.db or DEFAULTS)
end

local function GetLayoutCacheKey(frame, auraType, maxIcons, baseSize)
    return tostring(State.layoutVersion or 0)
        .. ":" .. tostring(auraType or "")
        .. ":" .. tostring(maxIcons or 0)
        .. ":" .. tostring(math.floor((tonumber(baseSize) or 0) * 100 + 0.5))
        .. ":" .. tostring(frame and frame:GetFrameLevel() or 0)
        .. ":" .. tostring(GetAuraFrameStrata(RaidFrameAuras.db))
        .. ":" .. tostring(GetAuraAnchorTargetKey(frame, RaidFrameAuras.db))
        .. ":" .. tostring(InCombatLockdown and InCombatLockdown() or false)
end

local function SetSizeIfChanged(region, width, height)
    if not region or not width then return false end
    width = Util.AsSafeNumber(width)
    height = Util.AsSafeNumber(height, width)
    if not width then return false end
    height = height or width

    region.rfaLayoutWidth = width
    region.rfaLayoutHeight = height

    local key = NumberKey(width) .. ":" .. NumberKey(height)
    if region.rfaSizeKey == key then return false end
    region:SetSize(width, height)
    region.rfaSizeKey = key
    return true
end

local function SetAlphaIfChanged(region, alpha)
    if not region then return end
    alpha = tonumber(alpha) or 1
    if region.rfaAlpha == alpha then return end
    region:SetAlpha(alpha)
    region.rfaAlpha = alpha
end

local function SetPointIfChanged(region, key, ...)
    if not region then return end
    if region.rfaPointKey == key then return end
    region:ClearAllPoints()
    region:SetPoint(...)
    region.rfaPointKey = key
end

local function SetTextureBoxIfChanged(region, key, insetX, insetY)
    if not region then return end
    if region.rfaPointKey == key then return end
    insetY = insetY or insetX or 0
    insetX = insetX or 0
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", insetX, -insetY)
    region:SetPoint("BOTTOMRIGHT", -insetX, insetY)
    region.rfaPointKey = key
end

local function ApplyAuraIconRegionGeometry(icon, force)
    if not icon then return end
    local textureInset = tonumber(icon.rfaTextureInset) or 0

    if icon.border and icon.border.SetDrawLayer then
        icon.border:SetDrawLayer(BORDER_DRAW_LAYER, BORDER_DRAW_LEVEL)
    end
    if icon.texture and icon.texture.SetDrawLayer then
        icon.texture:SetDrawLayer(ICON_DRAW_LAYER, ICON_DRAW_LEVEL)
    end

    if force and icon.texture then
        icon.texture.rfaPointKey = nil
    end
    SetTextureBoxIfChanged(icon.texture, "texture:" .. NumberKey(textureInset), textureInset)

    if icon.cooldown and (force or icon.cooldown.rfaPointKey ~= "cooldown:texture") then
        icon.cooldown:ClearAllPoints()
        icon.cooldown:SetAllPoints(icon.texture or icon)
        icon.cooldown.rfaPointKey = "cooldown:texture"
    end
end

function RaidFrameAuras:RestoreAuraIconRegionGeometry(icon)
    ApplyAuraIconRegionGeometry(icon, true)
end

local function SetBorderBoxIfChanged(region, key, leftInset, topInset, rightInset, bottomInset)
    if not region then return end
    if region.rfaPointKey == key then return end
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", leftInset, topInset)
    region:SetPoint("BOTTOMRIGHT", rightInset, bottomInset)
    region.rfaPointKey = key
end

local function SetFrameLayerIfChanged(frame, strata, level)
    if not frame then return end
    if strata and frame.rfaFrameStrata ~= strata then
        frame:SetFrameStrata(strata)
        frame.rfaFrameStrata = strata
    end
    if level and frame.rfaFrameLevel ~= level then
        frame:SetFrameLevel(level)
        frame.rfaFrameLevel = level
    end
end

local function SafeSetTexture(icon, texture)
    if not icon or not icon.texture then
        return false
    end
    local textureIsSecret = Util.IsSecretValue(texture)
    if not textureIsSecret and not texture then
        return false
    end
    local cachedTexture = icon.rfaTexture
    if not textureIsSecret and not Util.IsSecretValue(cachedTexture) and cachedTexture == texture then
        return true
    end
    local ok = pcall(icon.texture.SetTexture, icon.texture, texture)
    if ok then
        if textureIsSecret then
            icon.rfaTexture = nil
        else
            icon.rfaTexture = texture
        end
    end
    return ok
end

local function SafeSetCooldown(cooldown, auraData, unit)
    if not cooldown or not auraData then return end
    if unit and auraData.auraInstanceID
        and C_UnitAuras and C_UnitAuras.GetAuraDuration
        and cooldown.SetCooldownFromDurationObject then
        Util.PerfCount("LiveAuraCall")
        local ok, durationObj = pcall(C_UnitAuras.GetAuraDuration, unit, auraData.auraInstanceID)
        if ok and durationObj then
            cooldown:SetCooldownFromDurationObject(durationObj)
            return durationObj
        end
    end

    local dur = auraData.duration
    local exp = auraData.expirationTime
    if Util.IsSecretValue(dur) or Util.IsSecretValue(exp) then
        return
    end
    if dur and exp and dur > 0 then
        if cooldown.SetCooldownFromExpirationTime then
            cooldown:SetCooldownFromExpirationTime(exp, dur)
        elseif cooldown.SetCooldown then
            cooldown:SetCooldown(exp - dur, dur)
        end
    end
end

function RaidFrameAuras:CreateAuraIcon(parent, auraType)
    Util.PerfCount("CreateAuraIcon")
    local icon = self:CreatePrivateFrame("Frame", auraType == "BUFF" and "BuffIcon" or "DebuffIcon", parent)
    SetSizeIfChanged(icon, 18, 18)
    icon.rfaLayoutScale = 1
    icon:SetFrameLevel((parent:GetFrameLevel() or 1) + (self.db and self.db.auraFrameLevel or 35))
    icon:SetFrameStrata(GetAuraFrameStrata(self.db))
    icon:Hide()

    icon.border = icon:CreateTexture(nil, "BACKGROUND")
    icon.border:SetDrawLayer(BORDER_DRAW_LAYER, BORDER_DRAW_LEVEL)
    icon.border:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    icon.border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    icon.border:SetColorTexture(0, 0, 0, 0.8)

    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetDrawLayer(ICON_DRAW_LAYER, ICON_DRAW_LEVEL)
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.texture:SetAllPoints()

    icon.cooldown = self:CreatePrivateFrame("Cooldown", auraType == "BUFF" and "BuffIconCooldown" or "DebuffIconCooldown", icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints(icon.texture)
    icon.cooldown:SetDrawEdge(false)
    icon.cooldown:SetDrawSwipe(true)
    icon.cooldown:SetReverse(true)
    icon.cooldown:SetHideCountdownNumbers(false)
    icon.rfaTextureInset = 0
    ApplyAuraIconRegionGeometry(icon, true)

    icon.textOverlay = self:CreatePrivateFrame("Frame", auraType == "BUFF" and "BuffIconTextOverlay" or "DebuffIconTextOverlay", icon)
    icon.textOverlay:SetAllPoints(icon)
    icon.textOverlay:SetFrameLevel(icon.cooldown:GetFrameLevel() + 5)
    icon.textOverlay:EnableMouse(false)

    icon.expiringTint = icon.textOverlay:CreateTexture(nil, "BACKGROUND")
    icon.expiringTint:SetAllPoints(icon)
    icon.expiringTint:SetColorTexture(1, 0.3, 0.3, 0.3)
    icon.expiringTint:SetBlendMode("ADD")
    icon.expiringTint:Hide()

    icon.expiringBorderAlphaContainer = self:CreatePrivateFrame("Frame", auraType == "BUFF" and "BuffIconExpiringBorderAlpha" or "DebuffIconExpiringBorderAlpha", icon.textOverlay)
    icon.expiringBorderAlphaContainer:SetAllPoints(icon)
    icon.expiringBorderAlphaContainer:SetFrameLevel(icon.textOverlay:GetFrameLevel())
    icon.expiringBorderAlphaContainer:EnableMouse(false)
    icon.expiringBorderAlphaContainer:Hide()

    icon.expiringBorderContainer = self:CreatePrivateFrame("Frame", auraType == "BUFF" and "BuffIconExpiringBorder" or "DebuffIconExpiringBorder", icon.expiringBorderAlphaContainer)
    icon.expiringBorderContainer:SetAllPoints(icon)
    icon.expiringBorderContainer:EnableMouse(false)

    icon.expiringBorderLeft = icon.expiringBorderContainer:CreateTexture(nil, "OVERLAY")
    icon.expiringBorderRight = icon.expiringBorderContainer:CreateTexture(nil, "OVERLAY")
    icon.expiringBorderTop = icon.expiringBorderContainer:CreateTexture(nil, "OVERLAY")
    icon.expiringBorderBottom = icon.expiringBorderContainer:CreateTexture(nil, "OVERLAY")

    for _, texture in ipairs({ icon.expiringBorderLeft, icon.expiringBorderRight, icon.expiringBorderTop, icon.expiringBorderBottom }) do
        texture:SetColorTexture(1, 1, 1, 1)
    end

    icon.expiringBorderPulse = icon.expiringBorderContainer:CreateAnimationGroup()
    icon.expiringBorderPulse:SetLooping("REPEAT")
    local fadeOut = icon.expiringBorderPulse:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0.3)
    fadeOut:SetDuration(0.5)
    fadeOut:SetOrder(1)
    fadeOut:SetSmoothing("IN_OUT")
    local fadeIn = icon.expiringBorderPulse:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0.3)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.5)
    fadeIn:SetOrder(2)
    fadeIn:SetSmoothing("IN_OUT")

    icon.count = icon.textOverlay:CreateFontString(nil, "OVERLAY")
    icon.count:SetFontObject(GameFontNormalSmall)
    icon.count:SetTextColor(1, 1, 1, 1)

    icon.duration = icon.textOverlay:CreateFontString(nil, "OVERLAY")
    icon.duration:SetFontObject(GameFontNormalSmall)
    icon.duration:SetTextColor(1, 1, 1, 1)
    icon.duration:Hide()

    icon.auraType = auraType
    icon.unitFrame = parent

    icon:SetScript("OnEnter", function(self)
        RaidFrameAuras:ShowAuraTooltip(self)
    end)
    icon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    if not InCombatLockdown() then
        ConfigureAuraIconMouse(icon)
    end

    if self.RegisterMasqueAuraIcon then
        self:RegisterMasqueAuraIcon(icon, auraType)
    end

    return icon
end

function RaidFrameAuras:GetFrameState(frame)
    if not frame then return nil end
    local state = State.frameStates[frame]
    if state then return state end
    state = {
        buffIcons = {},
        debuffIcons = {},
        layoutVersion = -1,
    }
    State.frameStates[frame] = state
    return state
end

local function EnsureIconCount(frame, auraType, count)
    local state = RaidFrameAuras:GetFrameState(frame)
    local icons = auraType == "BUFF" and state.buffIcons or state.debuffIcons
    for i = #icons + 1, count do
        icons[i] = RaidFrameAuras:CreateAuraIcon(frame, auraType)
    end
    return icons
end

local function NormalizeVisualScale(visualScale)
    visualScale = tonumber(visualScale)
    if not visualScale or visualScale ~= visualScale or visualScale == math.huge or visualScale == -math.huge then
        return 1
    end
    return math.max(0.01, visualScale)
end

local function ApplyScaledAuraText(icon, visualScale)
    if not icon then return end
    visualScale = NormalizeVisualScale(visualScale or icon.rfaVisualScale or 1)
    icon.rfaVisualScale = visualScale

    local stackFont = icon.stackFont or DEFAULTS.buffStackFont or "Default"
    local stackOutline = icon.stackOutline or DEFAULTS.buffStackOutline or "OUTLINE"
    local stackScale = tonumber(icon.stackBaseScale) or 1
    local stackAnchor = icon.stackAnchor or "BOTTOMRIGHT"
    local stackX = (tonumber(icon.stackX) or 0) * visualScale
    local stackY = (tonumber(icon.stackY) or 0) * visualScale

    local durationFont = icon.durationFont or DEFAULTS.buffDurationFont or "Default"
    local durationOutline = icon.durationOutline or DEFAULTS.buffDurationOutline or "OUTLINE"
    local durationScale = tonumber(icon.durationBaseScale) or 1
    local durationAnchor = icon.durationAnchor or "CENTER"
    local durationX = (tonumber(icon.durationX) or 0) * visualScale
    local durationY = (tonumber(icon.durationY) or 0) * visualScale
    local textKey = tostring(visualScale)
        .. ":" .. tostring(stackFont)
        .. ":" .. tostring(stackOutline)
        .. ":" .. tostring(stackScale)
        .. ":" .. tostring(stackAnchor)
        .. ":" .. tostring(stackX)
        .. ":" .. tostring(stackY)
        .. ":" .. tostring(durationFont)
        .. ":" .. tostring(durationOutline)
        .. ":" .. tostring(durationScale)
        .. ":" .. tostring(durationAnchor)
        .. ":" .. tostring(durationX)
        .. ":" .. tostring(durationY)
        .. ":" .. tostring(icon.nativeCooldownText ~= nil)
    if icon.rfaTextScaleKey == textKey then
        return
    end

    RaidFrameAuras:SafeSetFont(icon.count, stackFont, 10 * stackScale * visualScale, stackOutline)
    SetPointIfChanged(icon.count, "count:" .. stackAnchor .. ":" .. NumberKey(stackX) .. ":" .. NumberKey(stackY), stackAnchor, icon, stackAnchor, stackX, stackY)

    RaidFrameAuras:SafeSetFont(icon.duration, durationFont, 10 * durationScale * visualScale, durationOutline)
    SetPointIfChanged(icon.duration, "duration:" .. durationAnchor .. ":" .. NumberKey(durationX) .. ":" .. NumberKey(durationY), durationAnchor, icon, durationAnchor, durationX, durationY)

    if icon.nativeCooldownText then
        RaidFrameAuras:SafeSetFont(icon.nativeCooldownText, durationFont, 10 * durationScale * visualScale, durationOutline)
        SetPointIfChanged(icon.nativeCooldownText, "nativeDuration:" .. durationAnchor .. ":" .. NumberKey(durationX) .. ":" .. NumberKey(durationY), durationAnchor, icon, durationAnchor, durationX, durationY)
    end
    icon.rfaTextScaleKey = textKey
end

function RaidFrameAuras:ApplyAuraIconTextScale(icon, auraType, visualScale)
    ApplyScaledAuraText(icon, visualScale)
end

function RaidFrameAuras:ApplyAuraLayout(frame, auraType, requestedIconCount)
    local db = self.db
    if not frame or not db then return end
    local prefix = auraType == "BUFF" and "buff" or "debuff"
    local maxIcons = Util.Clamp(db[prefix .. "Max"], 1, 40, DEFAULTS[prefix .. "Max"])
    local state = self:GetFrameState(frame)
    local icons = auraType == "BUFF" and state.buffIcons or state.debuffIcons
    local targetCount
    if requestedIconCount ~= nil then
        targetCount = Util.Clamp(requestedIconCount, 0, maxIcons, 0)
    else
        targetCount = math.min(#icons, maxIcons)
    end
    local keyName = prefix .. "LayoutCacheKey"
    local countKey = prefix .. "LayoutAppliedCount"
    local size = self.GetAuraBaseSize and self:GetAuraBaseSize(auraType, frame) or Util.Clamp(db[prefix .. "Size"], 4, 80, DEFAULTS[prefix .. "Size"])
    local cacheKey = GetLayoutCacheKey(frame, auraType, maxIcons, size)
    if state[keyName] == cacheKey and (state[countKey] or 0) >= targetCount then
        return
    end
    icons = EnsureIconCount(frame, auraType, targetCount)

    local alpha = Util.Clamp(db[prefix .. "Alpha"], 0, 1, DEFAULTS[prefix .. "Alpha"])
    local anchor = db[prefix .. "Anchor"] or DEFAULTS[prefix .. "Anchor"]
    local anchorTarget = GetAuraAnchorTarget(frame, db)
    local anchorTargetKey = GetAuraAnchorTargetKey(frame, db)
    local offsetX = tonumber(db[prefix .. "OffsetX"]) or DEFAULTS[prefix .. "OffsetX"]
    local offsetY = tonumber(db[prefix .. "OffsetY"]) or DEFAULTS[prefix .. "OffsetY"]
    local borderThickness = Util.Clamp(db[prefix .. "BorderThickness"], 0, 8, DEFAULTS[prefix .. "BorderThickness"])
    local borderInset = Constants.DEFAULT_BORDER_INSET or 0

    local stackScale = Util.Clamp(db[prefix .. "StackScale"], 0.2, 4, DEFAULTS[prefix .. "StackScale"])
    local stackFont = db[prefix .. "StackFont"] or DEFAULTS[prefix .. "StackFont"]
    local stackAnchor = db[prefix .. "StackAnchor"] or DEFAULTS[prefix .. "StackAnchor"]
    local stackX = tonumber(db[prefix .. "StackX"]) or DEFAULTS[prefix .. "StackX"]
    local stackY = tonumber(db[prefix .. "StackY"]) or DEFAULTS[prefix .. "StackY"]
    local stackOutline = db[prefix .. "StackOutline"] or DEFAULTS[prefix .. "StackOutline"]
    local stackMinimum = Util.Clamp(db[prefix .. "StackMinimum"], 1, 99, DEFAULTS[prefix .. "StackMinimum"])

    local showDuration = db[prefix .. "ShowDuration"] == true
    local durationScale = Util.Clamp(db[prefix .. "DurationScale"], 0.2, 4, DEFAULTS[prefix .. "DurationScale"])
    local durationFont = db[prefix .. "DurationFont"] or DEFAULTS[prefix .. "DurationFont"]
    local durationOutline = db[prefix .. "DurationOutline"] or DEFAULTS[prefix .. "DurationOutline"]
    local durationAnchor = db[prefix .. "DurationAnchor"] or DEFAULTS[prefix .. "DurationAnchor"]
    local durationX = tonumber(db[prefix .. "DurationX"]) or DEFAULTS[prefix .. "DurationX"]
    local durationY = tonumber(db[prefix .. "DurationY"]) or DEFAULTS[prefix .. "DurationY"]
    local hideSwipe = db[prefix .. "HideSwipe"] == true

    local frameStrata = GetAuraFrameStrata(db)
    local frameLevel = (frame:GetFrameLevel() or 1) + (db.auraFrameLevel or 35)
    for i = 1, targetCount do
        local icon = icons[i]
        SetFrameLayerIfChanged(icon, frameStrata, frameLevel)
        if SetSizeIfChanged(icon, size, size) and self.ScheduleMasqueIconReskin then
            self:ScheduleMasqueIconReskin(icon)
        end
        icon:SetScale(1)
        icon.rfaLayoutScale = 1
        SetAlphaIfChanged(icon, alpha)

        icon.stackMinimum = stackMinimum
        icon.stackFont = stackFont
        icon.stackOutline = stackOutline
        icon.stackBaseScale = stackScale
        icon.stackAnchor = stackAnchor
        icon.stackX = stackX
        icon.stackY = stackY
        icon.showDuration = showDuration
        icon.durationColorByTime = db[prefix .. "DurationColorByTime"] == true
        icon.durationHideAboveEnabled = db[prefix .. "DurationHideAboveEnabled"] == true
        icon.durationHideAboveThreshold = db[prefix .. "DurationHideAboveThreshold"] or 10
        icon.durationFont = durationFont
        icon.durationOutline = durationOutline
        icon.durationBaseScale = durationScale
        icon.durationAnchor = durationAnchor
        icon.durationX = durationX
        icon.durationY = durationY
        icon.rfaCategoryScale = 1
        icon.rfaVisualScale = self.GetAuraVisualScale and self:GetAuraVisualScale(auraType, 1, frame) or 1
        icon.expiringEnabled = db[prefix .. "ExpiringEnabled"] == true
        icon.expiringThreshold = db[prefix .. "ExpiringThreshold"] or DEFAULTS[prefix .. "ExpiringThreshold"]
        icon.expiringThresholdMode = db[prefix .. "ExpiringThresholdMode"] or DEFAULTS[prefix .. "ExpiringThresholdMode"]
        icon.expiringBorderEnabled = db[prefix .. "ExpiringBorderEnabled"] == true
        icon.expiringBorderColor = db[prefix .. "ExpiringBorderColor"] or DEFAULTS[prefix .. "ExpiringBorderColor"]
        icon.expiringBorderColorByTime = db[prefix .. "ExpiringBorderColorByTime"] == true
        icon.expiringBorderPulsate = db[prefix .. "ExpiringBorderPulsate"] == true
        icon.expiringBorderThickness = db[prefix .. "ExpiringBorderThickness"] or DEFAULTS[prefix .. "ExpiringBorderThickness"]
        icon.expiringBorderInset = Constants.DEFAULT_EXPIRING_BORDER_INSET or 1
        icon.expiringTintEnabled = db[prefix .. "ExpiringTintEnabled"] == true
        icon.expiringTintColor = db[prefix .. "ExpiringTintColor"] or DEFAULTS[prefix .. "ExpiringTintColor"]

        self:ApplyAuraIconTextScale(icon, auraType, icon.rfaVisualScale)

        if icon.cooldown then
            icon.cooldown:SetDrawSwipe(not hideSwipe)
            if icon.cooldown.SetHideCountdownNumbers then
                icon.cooldown:SetHideCountdownNumbers(not showDuration)
            end
        end

        SetPointIfChanged(icon, "layout:" .. anchorTargetKey .. ":" .. anchor .. ":" .. NumberKey(offsetX) .. ":" .. NumberKey(offsetY), anchor, anchorTarget, anchor, offsetX, offsetY)

        local textureInset = math.max(0, borderThickness - 1)
        icon.rfaTextureInset = textureInset
        ApplyAuraIconRegionGeometry(icon, true)
        icon.texture:SetVertexColor(1, 1, 1, 1)

        SetBorderBoxIfChanged(icon.border, "border:" .. NumberKey(borderThickness) .. ":" .. NumberKey(borderInset), -borderThickness + borderInset, borderThickness - borderInset, borderThickness - borderInset, -borderThickness + borderInset)

        local tint = icon.expiringTintColor or { r = 1, g = 0.3, b = 0.3, a = 0.3 }
        icon.expiringTint:SetColorTexture(tint.r or 1, tint.g or 0, tint.b or 0, tint.a or 0.3)

        local thickness = icon.expiringBorderThickness or 2
        local inset = icon.expiringBorderInset or Constants.DEFAULT_EXPIRING_BORDER_INSET or 1
        icon.expiringBorderLeft:ClearAllPoints()
        icon.expiringBorderLeft:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, -inset)
        icon.expiringBorderLeft:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", inset, inset)
        icon.expiringBorderLeft:SetWidth(thickness)
        icon.expiringBorderRight:ClearAllPoints()
        icon.expiringBorderRight:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -inset, -inset)
        icon.expiringBorderRight:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -inset, inset)
        icon.expiringBorderRight:SetWidth(thickness)
        icon.expiringBorderTop:ClearAllPoints()
        icon.expiringBorderTop:SetPoint("TOPLEFT", icon.expiringBorderLeft, "TOPRIGHT", 0, 0)
        icon.expiringBorderTop:SetPoint("TOPRIGHT", icon.expiringBorderRight, "TOPLEFT", 0, 0)
        icon.expiringBorderTop:SetHeight(thickness)
        icon.expiringBorderBottom:ClearAllPoints()
        icon.expiringBorderBottom:SetPoint("BOTTOMLEFT", icon.expiringBorderLeft, "BOTTOMRIGHT", 0, 0)
        icon.expiringBorderBottom:SetPoint("BOTTOMRIGHT", icon.expiringBorderRight, "BOTTOMLEFT", 0, 0)
        icon.expiringBorderBottom:SetHeight(thickness)

        if not InCombatLockdown() then
            ConfigureAuraIconMouse(icon)
        end
    end
    state[keyName] = cacheKey
    state[countKey] = targetCount
end

function RaidFrameAuras:RepositionVisibleAuraIcons(frame, auraType, visibleCount)
    local db = self.db
    if not frame or not db or visibleCount <= 0 then return end
    local state = self:GetFrameState(frame)
    local icons = auraType == "BUFF" and state.buffIcons or state.debuffIcons
    local prefix = auraType == "BUFF" and "buff" or "debuff"
    local anchorTarget = GetAuraAnchorTarget(frame, db)
    local anchorTargetKey = GetAuraAnchorTargetKey(frame, db)
    local positionKey = tostring(visibleCount) .. ":" .. tostring(state[prefix .. "LayoutCacheKey"]) .. ":" .. anchorTargetKey
    for i = 1, visibleCount do
        positionKey = positionKey .. ":" .. tostring(icons[i] and icons[i].rfaSizeKey or "")
    end
    local signatureKey = prefix .. "PositionSignature"
    if state[signatureKey] == positionKey then
        return
    end
    Util.PositionScaledIconStack(icons, visibleCount, {
        relativeTo = anchorTarget,
        size = self.GetAuraBaseSize and self:GetAuraBaseSize(auraType, frame) or db[prefix .. "Size"] or DEFAULTS[prefix .. "Size"],
        anchor = db[prefix .. "Anchor"] or DEFAULTS[prefix .. "Anchor"],
        growth = db[prefix .. "Growth"] or DEFAULTS[prefix .. "Growth"],
        wrap = db[prefix .. "Wrap"] or DEFAULTS[prefix .. "Wrap"],
        offsetX = db[prefix .. "OffsetX"] or DEFAULTS[prefix .. "OffsetX"],
        offsetY = db[prefix .. "OffsetY"] or DEFAULTS[prefix .. "OffsetY"],
        paddingX = db[prefix .. "PaddingX"] or DEFAULTS[prefix .. "PaddingX"],
        paddingY = db[prefix .. "PaddingY"] or DEFAULTS[prefix .. "PaddingY"],
    })
    state[signatureKey] = positionKey
end


local function EnsureNativeCooldownText(icon, db, prefix)
    if not icon or not icon.cooldown then return end
    if icon.nativeCooldownText then
        RaidFrameAuras:ApplyAuraIconTextScale(icon, prefix == "buff" and "BUFF" or "DEBUFF", icon.rfaVisualScale or 1)
        return
    end
    local regions = { icon.cooldown:GetRegions() }
    for _, region in ipairs(regions) do
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
            icon.nativeCooldownText = region
            if not icon.durationHideWrapper then
                icon.durationHideWrapper = RaidFrameAuras:CreatePrivateFrame("Frame", "DurationHideWrapper", icon.cooldown)
                icon.durationHideWrapper:SetAllPoints(icon)
                icon.durationHideWrapper:SetFrameLevel(icon.cooldown:GetFrameLevel() + 2)
                icon.durationHideWrapper:EnableMouse(false)
            end
            region:SetParent(icon.durationHideWrapper)
            RaidFrameAuras:ApplyAuraIconTextScale(icon, prefix == "buff" and "BUFF" or "DEBUFF", icon.rfaVisualScale or 1)
            break
        end
    end
end

local function EnsureDebuffBorderCurve(db)
    if State.debuffBorderCurve then return State.debuffBorderCurve end
    if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then return nil end
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    local none = db.debuffBorderColorNone or DEFAULTS.debuffBorderColorNone
    local magic = db.debuffBorderColorMagic or DEFAULTS.debuffBorderColorMagic
    local curse = db.debuffBorderColorCurse or DEFAULTS.debuffBorderColorCurse
    local disease = db.debuffBorderColorDisease or DEFAULTS.debuffBorderColorDisease
    local poison = db.debuffBorderColorPoison or DEFAULTS.debuffBorderColorPoison
    local bleed = db.debuffBorderColorBleed or DEFAULTS.debuffBorderColorBleed
    curve:AddPoint(0, CreateColor(none.r, none.g, none.b, 1))
    curve:AddPoint(1, CreateColor(magic.r, magic.g, magic.b, 1))
    curve:AddPoint(2, CreateColor(curse.r, curse.g, curse.b, 1))
    curve:AddPoint(3, CreateColor(disease.r, disease.g, disease.b, 1))
    curve:AddPoint(4, CreateColor(poison.r, poison.g, poison.b, 1))
    curve:AddPoint(9, CreateColor(bleed.r, bleed.g, bleed.b, 1))
    curve:AddPoint(11, CreateColor(bleed.r, bleed.g, bleed.b, 1))
    State.debuffBorderCurve = curve
    return State.debuffBorderCurve
end

local function GetNumericStackText(applications, stackMinimum)
    if Util.IsSecretValue(applications) then
        return nil, false
    end
    local value = tonumber(applications)
    if value and value >= stackMinimum then
        return value, true
    end
    return nil, false
end

local function GetAuraStackText(icon, unit, auraData, options)
    local stackMinimum = icon.stackMinimum or 2
    if options.stackText ~= nil then
        return options.stackText, true
    end
    if options.applications ~= nil then
        return GetNumericStackText(options.applications, stackMinimum)
    end

    local cachedText, cachedOk = GetNumericStackText(auraData.applications, stackMinimum)
    if cachedOk then
        return cachedText, true
    end

    if C_UnitAuras.GetAuraApplicationDisplayCount and unit and auraData.auraInstanceID then
        Util.PerfCount("LiveAuraCall")
        Util.PerfCount("IconPaintLiveStack")
        local ok, stackText = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, auraData.auraInstanceID, stackMinimum, 99)
        if ok then
            if Util.IsSecretValue(stackText) then
                return stackText, true
            end
            if stackText ~= nil then
                return stackText, true
            end
        end
    end
    return nil, false
end

local function GetAuraExpirationState(unit, auraData, options)
    if options.hasExpiration ~= nil then
        local hasExpiration = options.hasExpiration == true
        return hasExpiration, hasExpiration
    end

    local duration = auraData and auraData.duration
    local expiration = auraData and auraData.expirationTime
    if not Util.IsSecretValue(duration) and not Util.IsSecretValue(expiration) then
        duration = tonumber(duration)
        expiration = tonumber(expiration)
        if duration ~= nil and expiration ~= nil then
            local hasExpiration = duration > 0 and expiration > 0
            return hasExpiration, hasExpiration
        end
    end

    if options.useLiveCooldown ~= false and unit and auraData and auraData.auraInstanceID then
        if C_UnitAuras.DoesAuraHaveExpirationTime then
            Util.PerfCount("LiveAuraCall")
            Util.PerfCount("IconPaintLiveExpiration")
            local ok, hasExpiration = pcall(C_UnitAuras.DoesAuraHaveExpirationTime, unit, auraData.auraInstanceID)
            if ok then
                if Util.IsSecretValue(hasExpiration) then
                    return hasExpiration, true
                end
                if hasExpiration ~= nil then
                    return hasExpiration == true, true
                end
            end
        end
        return true, true
    end

    return true, true
end

local function SetShownByExpiration(region, hasExpiration, fallbackShown)
    if region.SetShownFromBoolean then
        region:SetShownFromBoolean(hasExpiration, true, false)
    elseif fallbackShown then
        region:Show()
    else
        region:Hide()
    end
end

local ApplyAuraTimerTextState
local UpdateAuraTimerActivity
local AuraTimer_OnUpdate

local function IconHasSafeCachedDuration(icon)
    if not icon then return false end

    local duration = icon.auraDuration
    local expiration = icon.expirationTime

    if Util.IsSecretValue(duration) or Util.IsSecretValue(expiration) then
        return false
    end

    duration = tonumber(duration)
    expiration = tonumber(expiration)

    return duration ~= nil and expiration ~= nil and duration > 0 and expiration > 0
end

local function IconHasKnownExpirationState(icon)
    if not icon then return false end

    if Util.IsSecretValue(icon.hasExpiration) then
        return false
    end

    if icon.hasExpiration ~= nil then
        return true
    end

    if Util.IsSecretValue(icon.hasExpirationFallback) then
        return false
    end

    return icon.hasExpirationFallback ~= nil
end

local function IconHasKnownNonExpiringState(icon)
    if not icon then return false end

    if not Util.IsSecretValue(icon.hasExpiration) and icon.hasExpiration ~= nil then
        return icon.hasExpiration ~= true
    end

    if not Util.IsSecretValue(icon.hasExpirationFallback) and icon.hasExpirationFallback ~= nil then
        return icon.hasExpirationFallback ~= true
    end

    return false
end

local function GetCachedIconHasExpiration(icon)
    if not icon then return true end

    if not Util.IsSecretValue(icon.hasExpiration) and icon.hasExpiration ~= nil then
        return icon.hasExpiration == true
    end

    if not Util.IsSecretValue(icon.hasExpirationFallback) and icon.hasExpirationFallback ~= nil then
        return icon.hasExpirationFallback == true
    end

    return true
end

local function IconNeedsTimer(icon)
    if not icon or not icon:IsShown() or not icon.auraData or not icon.auraData.auraInstanceID then
        return false
    end

    if icon.expiringEnabled and (icon.expiringTintEnabled or icon.expiringBorderEnabled) then
        return true
    end

    if icon.showDurationText and (icon.durationColorByTime or icon.durationHideAboveEnabled) then
        if IconHasKnownNonExpiringState(icon) then
            Util.PerfCount("AuraTimerSkippedPermanent")
            return false
        end

        return true
    end

    return false
end

local function SetIconTimerTracked(icon, shouldTrack)
    if not State.trackedTimerIcons or not icon then
        return
    end

    local shouldBeTracked = shouldTrack and IconNeedsTimer(icon) or false
    local isTracked = State.trackedTimerIcons[icon] == true
    if shouldBeTracked == isTracked then
        return
    end

    if shouldBeTracked then
        State.trackedTimerIcons[icon] = true
    else
        State.trackedTimerIcons[icon] = nil
    end

    if UpdateAuraTimerActivity then
        UpdateAuraTimerActivity()
    end
end

local function ApplyAuraIconVisuals(frame, icon, unit, auraType, auraData, options)
    local db = RaidFrameAuras.db
    if not frame or not icon or not db or not auraData or not SafeSetTexture(icon, auraData.icon) then
        return false
    end

    options = options or {}
    local prefix = auraType == "BUFF" and "buff" or "debuff"
    local id = auraData.auraInstanceID
    local showDurationText = icon.showDuration and options.showDurationText ~= false

    icon.rfaUnit = unit
    icon.unitFrame = frame
    icon.auraType = auraType
    icon.auraData = icon.auraData or {}
    icon.auraData.index = options.index or auraData.index
    icon.auraData.auraInstanceID = id
    icon.expirationTime = auraData.expirationTime
    icon.auraDuration = auraData.duration
    icon.showDurationText = showDurationText
    local hasExpiration, fallbackHasExpiration = GetAuraExpirationState(unit, auraData, options)
    icon.hasExpiration = hasExpiration
    icon.hasExpirationFallback = fallbackHasExpiration

    if icon.cooldown and icon.cooldown.SetHideCountdownNumbers then
        icon.cooldown:SetHideCountdownNumbers(not showDurationText)
    end
    local durationObj = SafeSetCooldown(icon.cooldown, auraData, options.useLiveCooldown == false and nil or unit)
    icon.durationObj = durationObj

    icon.count:SetText("")
    local stackText, hasStackText = GetAuraStackText(icon, unit, auraData, options)
    if hasStackText then
        icon.count:SetText(stackText)
    end

    if icon.cooldown then
        SetShownByExpiration(icon.cooldown, icon.hasExpiration, icon.hasExpirationFallback or options.useLiveCooldown ~= false)
    end
    if icon.duration then
        icon.duration:SetText("")
        if showDurationText then
            SetShownByExpiration(icon.duration, icon.hasExpiration, icon.hasExpirationFallback or options.useLiveCooldown ~= false)
        else
            icon.duration:Hide()
        end
    end

    local borderEnabled
    if auraType == "DEBUFF" then
        borderEnabled = db.debuffBorderEnabled ~= false
    else
        borderEnabled = db.buffBorderEnabled ~= false
    end

    if borderEnabled then
        local r, g, b
        if options.borderColor then
            r, g, b = Util.ReadColor(options.borderColor, 0, 0, 0, 1)
            icon.border:SetColorTexture(r, g, b, 1)
        elseif auraType == "DEBUFF" and not options.unitDeadOrOffline then
            if db.debuffBorderColorByType ~= false and C_UnitAuras.GetAuraDispelTypeColor and unit and id then
                local curve = EnsureDebuffBorderCurve(db)
                Util.PerfCount("LiveAuraCall")
                local borderColor = curve and C_UnitAuras.GetAuraDispelTypeColor(unit, id, curve)
                if borderColor and borderColor.GetRGB then
                    r, g, b = borderColor:GetRGB()
                    icon.border:SetColorTexture(r, g, b, 1)
                else
                    local c = db.debuffBorderColorNone or DEFAULTS.debuffBorderColorNone
                    icon.border:SetColorTexture(c.r, c.g, c.b, 1)
                end
            else
                icon.border:SetColorTexture(0.8, 0, 0, 1)
            end
        else
            icon.border:SetColorTexture(0, 0, 0, 1)
        end
        icon.border:SetAlpha(0.8)
        icon.border:Show()
    else
        icon.border:Hide()
    end

    if options.hideDynamicOverlays then
        if icon.expiringTint then icon.expiringTint:Hide() end
        if icon.expiringBorderAlphaContainer then icon.expiringBorderAlphaContainer:Hide() end
        if icon.expiringBorderPulse and icon.expiringBorderPulse:IsPlaying() then icon.expiringBorderPulse:Stop() end
    end

    icon:Show()
    if options.visualScale then
        icon.rfaVisualScale = NormalizeVisualScale(options.visualScale)
    end
    EnsureNativeCooldownText(icon, db, prefix)
    RaidFrameAuras:ApplyAuraIconTextScale(icon, auraType, icon.rfaVisualScale or 1)
    if icon.cooldown and icon.cooldown.SetHideCountdownNumbers then
        icon.cooldown:SetHideCountdownNumbers(not showDurationText)
    end
    if showDurationText and ApplyAuraTimerTextState then
        ApplyAuraTimerTextState(icon, durationObj, icon.hasExpiration)
    elseif icon.durationHideWrapper then
        icon.durationHideWrapper:SetAlpha(0)
    end

    SetIconTimerTracked(icon, options.trackTimers ~= false)
    return true
end

function RaidFrameAuras:ApplyAuraIconVisuals(frame, icon, unit, auraType, auraData, options)
    return ApplyAuraIconVisuals(frame, icon, unit, auraType, auraData, options)
end

local function HideIcon(icon)
    if not icon then return end
    if not icon:IsShown() and not icon.auraData then return end
    icon.auraData = nil
    icon.rfaUnit = nil
    icon.showDurationText = nil
    icon.expirationTime = nil
    icon.auraDuration = nil
    icon.durationObj = nil
    icon.rfaCategoryScale = nil
    icon.rfaVisualScale = nil
    icon.hasExpiration = nil
    icon.hasExpirationFallback = nil
    if icon.nativeCooldownText then icon.nativeCooldownText:SetTextColor(1, 1, 1, 1) end
    if icon.duration then icon.duration:Hide() end
    if icon.expiringTint then icon.expiringTint:Hide() end
    if icon.expiringBorderAlphaContainer then icon.expiringBorderAlphaContainer:Hide() end
    if icon.expiringBorderPulse and icon.expiringBorderPulse:IsPlaying() then icon.expiringBorderPulse:Stop() end
    State.trackedTimerIcons[icon] = nil
    if UpdateAuraTimerActivity then
        UpdateAuraTimerActivity()
    end
    icon:Hide()
end

function RaidFrameAuras:HideAuraIcon(icon)
    HideIcon(icon)
end

function RaidFrameAuras:HideFrameAuras(frame)
    if self.ClearPrivateAuraAnchors then
        self:ClearPrivateAuraAnchors(frame)
    end
    if self.HideFrameObjectiveCarrier then
        self:HideFrameObjectiveCarrier(frame)
    end
    local state = frame and State.frameStates[frame]
    if not state then return end
    state.buffDisplaySignature = nil
    state.debuffDisplaySignature = nil
    state.buffPositionSignature = nil
    state.debuffPositionSignature = nil
    for _, icon in ipairs(state.buffIcons) do HideIcon(icon) end
    for _, icon in ipairs(state.debuffIcons) do HideIcon(icon) end
end

function RaidFrameAuras:HideFrameAuraType(frame, auraType)
    if auraType == "DEBUFF" and self.ClearPrivateAuraAnchors then
        self:ClearPrivateAuraAnchors(frame)
    end
    local state = frame and State.frameStates[frame]
    if not state then return end
    local prefix = auraType == "BUFF" and "buff" or "debuff"
    state[prefix .. "DisplaySignature"] = nil
    state[prefix .. "PositionSignature"] = nil
    local icons = auraType == "BUFF" and state.buffIcons or state.debuffIcons
    for _, icon in ipairs(icons) do HideIcon(icon) end
end

local function BuildAuraDisplaySignature(unit, auraType, cache, selected, count, unitDeadOrOffline, layoutKey)
    local signature = tostring(unit)
        .. ":" .. tostring(auraType)
        .. ":" .. tostring(cache and cache.generation or 0)
        .. ":" .. tostring(layoutKey or "")
        .. ":" .. tostring(unitDeadOrOffline == true)
        .. ":" .. tostring(count or 0)
    for i = 1, count do
        local auraData = selected[i]
        local id = auraData and auraData.auraInstanceID
        local scale = id and cache and cache.categoryScales and cache.categoryScales[id] or 1
        signature = signature .. ":" .. tostring(id or "") .. "@" .. NumberKey(scale)
    end
    return signature
end

function RaidFrameAuras:UpdateAuraIcons(frame, auraType)
    local perf = Util.PerfBegin("UpdateAuraIcons")
    Util.PerfCount("UpdateAuraIcons")
    local db = self.db
    local state = self:GetFrameState(frame)
    local unit = frame.rfaUnit or Util.GetFrameUnit(frame)
    if not self:IsTrackedUnit(unit) then
        Util.PerfEnd("UpdateAuraIcons", perf)
        return
    end
    local prefix = auraType == "BUFF" and "buff" or "debuff"
    local maxAuras = Util.Clamp(db[prefix .. "Max"], 1, 40, DEFAULTS[prefix .. "Max"])
    local icons = auraType == "BUFF" and state.buffIcons or state.debuffIcons
    local cache = State.auraCache[unit]
    if cache and (cache.buffOrderDirty or cache.debuffOrderDirty) then
        self:RebuildSortedArrays(cache, db, nil, unit)
    end
    local dataList = cache and (auraType == "BUFF" and cache.buffData or cache.debuffData)

    if not dataList then
        for i = 1, #icons do HideIcon(icons[i]) end
        state[prefix .. "DisplaySignature"] = nil
        state[prefix .. "PositionSignature"] = nil
        Util.PerfEnd("UpdateAuraIcons", perf)
        return
    end

    State.updateAuraScratch = State.updateAuraScratch or {}
    local selected = State.updateAuraScratch
    wipe(selected)

    local displayed = 0
    for i = 1, #dataList do
        if displayed >= maxAuras then break end
        local auraData = dataList[i]
        if auraData and auraData.auraInstanceID and auraData.icon then
            displayed = displayed + 1
            selected[displayed] = auraData
        end
    end

    self:ApplyAuraLayout(frame, auraType, displayed)
    icons = auraType == "BUFF" and state.buffIcons or state.debuffIcons

    local unitDeadOrOffline = UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit)
    local signature = BuildAuraDisplaySignature(unit, auraType, cache, selected, displayed, unitDeadOrOffline, state[prefix .. "LayoutCacheKey"])
    local signatureKey = prefix .. "DisplaySignature"
    if state[signatureKey] == signature then
        Util.PerfCount("UpdateAuraIconsSkipped")
        Util.PerfEnd("UpdateAuraIcons", perf)
        return
    end

    local actualDisplayed = 0
    for i = 1, displayed do
        local auraData = selected[i]
        local id = auraData and auraData.auraInstanceID
        if auraData and id then
            local icon = icons[actualDisplayed + 1]
            local categoryScale = cache.categoryScales and cache.categoryScales[id] or 1
            local visualScale = self.GetAuraVisualScale and self:GetAuraVisualScale(auraType, categoryScale, frame) or Util.ClampCategoryScale(categoryScale)
            local iconSize = self:GetAuraIconSize(auraType, categoryScale, frame)
            icon.rfaCategoryScale = categoryScale
            icon.rfaVisualScale = visualScale
            if SetSizeIfChanged(icon, iconSize, iconSize) and self.ScheduleMasqueIconReskin then
                self:ScheduleMasqueIconReskin(icon)
            end
            if ApplyAuraIconVisuals(frame, icon, unit, auraType, auraData, {
                index = i,
                showDurationText = auraType ~= "DEBUFF"
                    or db.debuffShowDurationCrowdControlOnly ~= true
                    or (cache.crowdControls and cache.crowdControls[id] == true),
                unitDeadOrOffline = unitDeadOrOffline,
                visualScale = visualScale,
            }) then
                actualDisplayed = actualDisplayed + 1
            end
        end
    end

    for i = actualDisplayed + 1, #icons do
        HideIcon(icons[i])
    end

    frame[prefix .. "DisplayedCount"] = actualDisplayed
    if actualDisplayed > 0 then
        self:RepositionVisibleAuraIcons(frame, auraType, actualDisplayed)
    else
        state[prefix .. "PositionSignature"] = nil
    end
    state[signatureKey] = signature
    Util.PerfEnd("UpdateAuraIcons", perf)
end

local function EnsureDurationColorCurve()
    if State.durationColorCurve or not C_CurveUtil or not C_CurveUtil.CreateColorCurve then return State.durationColorCurve end
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    Util.AddRemainingTimeColorPoints(curve, RaidFrameAuras.db, DEFAULTS)
    State.durationColorCurve = curve
    return State.durationColorCurve
end

local function GetDurationHideCurve(threshold)
    threshold = tonumber(threshold) or 10
    if State.durationHideCurves[threshold] then return State.durationHideCurves[threshold] end
    if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then return nil end
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, CreateColor(1, 1, 1, 1))
    curve:AddPoint(threshold, CreateColor(1, 1, 1, 0))
    curve:AddPoint(600, CreateColor(1, 1, 1, 0))
    State.durationHideCurves[threshold] = curve
    return curve
end

local function GetIconRemainingDuration(icon)
    if not icon or not GetTime then return nil end
    local duration = icon.auraDuration
    local expiration = icon.expirationTime
    if Util.IsSecretValue(duration) or Util.IsSecretValue(expiration) then
        return nil
    end
    duration = tonumber(duration)
    expiration = tonumber(expiration)
    if not duration or not expiration or duration <= 0 or expiration <= 0 then
        return nil
    end
    return math.max(0, expiration - GetTime())
end

local function ResolveBooleanForSecureMixin(value, fallback)
    if Util.IsSecretValue(value) then
        return value
    end
    if value ~= nil then
        return value == true
    end
    if Util.IsSecretValue(fallback) then
        return fallback
    end
    if fallback ~= nil then
        return fallback == true
    end
    return true
end

ApplyAuraTimerTextState = function(icon, durationObj, hasExpiration)
    if not icon then return end
    local fallbackRemaining
    local fallbackHasExpiration = icon.hasExpiration
    if not Util.IsSecretValue(fallbackHasExpiration) and fallbackHasExpiration == nil then
        fallbackHasExpiration = icon.hasExpirationFallback
    end
    hasExpiration = ResolveBooleanForSecureMixin(hasExpiration, fallbackHasExpiration)

    if icon.nativeCooldownText then
        if icon.durationColorByTime then
            local color
            if durationObj and durationObj.EvaluateRemainingDuration then
                local curve = EnsureDurationColorCurve()
                color = curve and durationObj:EvaluateRemainingDuration(curve)
            end
            if color and color.GetRGBA then
                icon.nativeCooldownText:SetTextColor(color:GetRGBA())
            else
                fallbackRemaining = GetIconRemainingDuration(icon)
                local r, g, b, a = Util.GetRemainingTimeColor(RaidFrameAuras.db, DEFAULTS, fallbackRemaining)
                icon.nativeCooldownText:SetTextColor(r or 1, g or 1, b or 1, a or 1)
            end
        else
            icon.nativeCooldownText:SetTextColor(1, 1, 1, 1)
        end
    end

    if not icon.durationHideWrapper then return end
    if not icon.durationHideAboveEnabled then
        icon.durationHideWrapper:SetAlpha(1)
        return
    end

    local alpha
    if durationObj and durationObj.EvaluateRemainingDuration then
        local curve = GetDurationHideCurve(icon.durationHideAboveThreshold)
        local color = curve and durationObj:EvaluateRemainingDuration(curve)
        if color and color.GetRGBA then
            alpha = select(4, color:GetRGBA())
        end
    end
    if alpha == nil then
        fallbackRemaining = fallbackRemaining or GetIconRemainingDuration(icon)
        if fallbackRemaining then
            local threshold = tonumber(icon.durationHideAboveThreshold) or 10
            alpha = fallbackRemaining <= threshold and 1 or 0
        end
    end

    if alpha ~= nil then
        if icon.durationHideWrapper.SetAlphaFromBoolean then
            icon.durationHideWrapper:SetAlphaFromBoolean(hasExpiration, alpha, 0)
        else
            icon.durationHideWrapper:SetAlpha(alpha)
        end
    else
        icon.durationHideWrapper:SetAlpha(1)
    end
end

local function GetExpiringCurve(threshold, mode)
    threshold = tonumber(threshold) or 30
    mode = mode == "SECONDS" and "SECONDS" or "PERCENT"
    local key = mode .. ":" .. threshold
    if State.expiringCurves[key] then return State.expiringCurves[key] end
    if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then return nil end
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    if mode == "SECONDS" then
        curve:AddPoint(0, CreateColor(1, 1, 1, 1))
        curve:AddPoint(threshold, CreateColor(0, 0, 0, 0))
        curve:AddPoint(600, CreateColor(0, 0, 0, 0))
    else
        curve:AddPoint(0, CreateColor(1, 1, 1, 1))
        curve:AddPoint(threshold / 100, CreateColor(0, 0, 0, 0))
        curve:AddPoint(1, CreateColor(0, 0, 0, 0))
    end
    State.expiringCurves[key] = curve
    return curve
end

local function EnsureExpiringBorderColorCurve()
    if State.expiringBorderColorCurve or not C_CurveUtil or not C_CurveUtil.CreateColorCurve then return State.expiringBorderColorCurve end
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    Util.AddRemainingTimeColorPoints(curve, RaidFrameAuras.db, DEFAULTS)
    State.expiringBorderColorCurve = curve
    return curve
end

local auraTimer = RaidFrameAuras:CreatePrivateFrame("Frame", "AuraTimer")
local auraTimerElapsed = 0

UpdateAuraTimerActivity = function()
    local hasTrackedIcons = false

    if State.trackedTimerIcons then
        for icon in pairs(State.trackedTimerIcons) do
            if IconNeedsTimer(icon) then
                hasTrackedIcons = true
                break
            end
            Util.PerfCount("AuraTimerSkippedStaleIcon")
            State.trackedTimerIcons[icon] = nil
        end
    end

    local currentHandler = auraTimer:GetScript("OnUpdate")
    if hasTrackedIcons then
        if AuraTimer_OnUpdate and currentHandler ~= AuraTimer_OnUpdate then
            auraTimer:SetScript("OnUpdate", AuraTimer_OnUpdate)
        end
    else
        if currentHandler ~= nil then
            auraTimer:SetScript("OnUpdate", nil)
        end
        auraTimerElapsed = 0
    end
end

AuraTimer_OnUpdate = function(_, elapsed)
    auraTimerElapsed = auraTimerElapsed + elapsed
    if auraTimerElapsed < 0.2 then return end
    auraTimerElapsed = 0
    Util.PerfCount("AuraTimerTick")

    local hasValidTrackedIcon = false

    for icon in pairs(State.trackedTimerIcons) do
        if not IconNeedsTimer(icon) then
            Util.PerfCount("AuraTimerSkippedStaleIcon")
            State.trackedTimerIcons[icon] = nil
        else
            hasValidTrackedIcon = true
            Util.PerfCount("AuraTimerIcon")
            local durationObj = icon.durationObj
            if durationObj then
                Util.PerfCount("AuraTimerCachedDurationObject")
            elseif icon.showDurationText and (icon.durationColorByTime or icon.durationHideAboveEnabled) and IconHasSafeCachedDuration(icon) then
                Util.PerfCount("AuraTimerCachedDuration")
            end

            local hasExpiration = icon.hasExpiration
            if IconHasKnownExpirationState(icon) then
                hasExpiration = GetCachedIconHasExpiration(icon)
                Util.PerfCount("AuraTimerCachedExpiration")
            end
            hasExpiration = ResolveBooleanForSecureMixin(hasExpiration, icon.hasExpirationFallback)

            if icon.showDurationText then
                ApplyAuraTimerTextState(icon, durationObj, hasExpiration)
            elseif icon.durationHideWrapper then
                icon.durationHideWrapper:SetAlpha(0)
            end

            if icon.expiringEnabled and durationObj then
                local curve = GetExpiringCurve(icon.expiringThreshold, icon.expiringThresholdMode)
                local result
                if curve then
                    if icon.expiringThresholdMode == "SECONDS" and durationObj.EvaluateRemainingDuration then
                        result = durationObj:EvaluateRemainingDuration(curve)
                    elseif durationObj.EvaluateRemainingPercent then
                        result = durationObj:EvaluateRemainingPercent(curve)
                    end
                end
                local expiringAlpha = 0
                if result and result.GetRGBA then
                    expiringAlpha = select(4, result:GetRGBA())
                end

                if icon.expiringTint and icon.expiringTintEnabled then
                    icon.expiringTint:Show()
                    if icon.expiringTint.SetAlphaFromBoolean then
                        icon.expiringTint:SetAlphaFromBoolean(hasExpiration, expiringAlpha, 0)
                    else
                        icon.expiringTint:SetAlpha(expiringAlpha)
                    end
                elseif icon.expiringTint then
                    icon.expiringTint:Hide()
                end

                if icon.expiringBorderAlphaContainer and icon.expiringBorderEnabled then
                    icon.expiringBorderAlphaContainer:Show()
                    if icon.expiringBorderAlphaContainer.SetAlphaFromBoolean then
                        icon.expiringBorderAlphaContainer:SetAlphaFromBoolean(hasExpiration, expiringAlpha, 0)
                    else
                        icon.expiringBorderAlphaContainer:SetAlpha(expiringAlpha)
                    end

                    if icon.expiringBorderColorByTime and durationObj then
                        local colorCurve = EnsureExpiringBorderColorCurve()
                        local color = colorCurve and durationObj.EvaluateRemainingDuration and durationObj:EvaluateRemainingDuration(colorCurve)
                        if color and color.GetRGBA then
                            local r, g, b, a = color:GetRGBA()
                            icon.expiringBorderTop:SetColorTexture(r, g, b, a)
                            icon.expiringBorderBottom:SetColorTexture(r, g, b, a)
                            icon.expiringBorderLeft:SetColorTexture(r, g, b, a)
                            icon.expiringBorderRight:SetColorTexture(r, g, b, a)
                        else
                            local c = icon.expiringBorderColor or { r = 1, g = 0.15, b = 0.05, a = 1 }
                            icon.expiringBorderTop:SetColorTexture(c.r, c.g, c.b, c.a or 1)
                            icon.expiringBorderBottom:SetColorTexture(c.r, c.g, c.b, c.a or 1)
                            icon.expiringBorderLeft:SetColorTexture(c.r, c.g, c.b, c.a or 1)
                            icon.expiringBorderRight:SetColorTexture(c.r, c.g, c.b, c.a or 1)
                        end
                    else
                        local c = icon.expiringBorderColor or { r = 1, g = 0.15, b = 0.05, a = 1 }
                        icon.expiringBorderTop:SetColorTexture(c.r, c.g, c.b, c.a or 1)
                        icon.expiringBorderBottom:SetColorTexture(c.r, c.g, c.b, c.a or 1)
                        icon.expiringBorderLeft:SetColorTexture(c.r, c.g, c.b, c.a or 1)
                        icon.expiringBorderRight:SetColorTexture(c.r, c.g, c.b, c.a or 1)
                    end
                    if icon.expiringBorderPulsate and not icon.expiringBorderPulse:IsPlaying() then
                        icon.expiringBorderPulse:Play()
                    elseif not icon.expiringBorderPulsate and icon.expiringBorderPulse:IsPlaying() then
                        icon.expiringBorderPulse:Stop()
                        icon.expiringBorderContainer:SetAlpha(1)
                    end
                elseif icon.expiringBorderAlphaContainer then
                    icon.expiringBorderAlphaContainer:Hide()
                end
            else
                if icon.expiringTint then icon.expiringTint:Hide() end
                if icon.expiringBorderAlphaContainer then icon.expiringBorderAlphaContainer:Hide() end
            end
        end
    end

    if not hasValidTrackedIcon and UpdateAuraTimerActivity then
        UpdateAuraTimerActivity()
    end
end

auraTimer:SetScript("OnUpdate", nil)
