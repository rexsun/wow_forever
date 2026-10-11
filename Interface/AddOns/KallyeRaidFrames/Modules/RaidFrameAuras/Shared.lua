local addonName, ns = ...
local l = ns.I18N;

-- * avoid conflict override
if ns.CONFLICT then return; end

local RaidFrameAuras = ns.RaidFrameAuras
if not RaidFrameAuras then return end

local Constants = ns.Constants or {}
local DEFAULTS = ns.DEFAULTS or {}
local Util = ns.Util or {}
ns.Util = Util
local State = ns.State or {}

function Util.IsSecretValue(value)
    return type(issecretvalue) == "function" and issecretvalue(value) or false
end

function Util.AsSafeNumber(value, fallback)
    if Util.IsSecretValue(value) then
        return fallback
    end
    value = tonumber(value)
    if Util.IsSecretValue(value) or not value or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

function Util.CopyDefaults(source, destination)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(destination[key]) ~= "table" then
                destination[key] = {}
            end
            Util.CopyDefaults(value, destination[key])
        elseif destination[key] == nil then
            destination[key] = value
        end
    end
end

local function IsFontPath(value)
    return type(value) == "string" and (value:find("\\") or value:find("/")) ~= nil
end

function Util.WipeTable(t)
    if t then
        wipe(t)
    end
end

function Util.PrintMessage(text)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99RaidFrameAuras|r " .. tostring(text or ""))
    end
end

function Util.T(text, ...)
    local L = ns.L or {}
    local value = L[text] or text or ""
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, tostring(value), ...)
        if ok then
            return formatted
        end
    end
    return value
end

function Util.DebugLog(text, ...)
    if not RaidFrameAuras.db or not RaidFrameAuras.db.debugMode then
        return
    end
    local ok, formatted = pcall(string.format, tostring(text or ""), ...)
    Util.PrintMessage(ok and formatted or tostring(text or ""))
end

function Util.IsPerfEnabled()
    return RaidFrameAuras.db and RaidFrameAuras.db.perfMode == true
end

local function EnsurePerfState(reason)
    local perf = State.perf
    if not perf then
        perf = {
            counts = {},
            timings = {},
        }
        State.perf = perf
    end
    perf.reason = reason or perf.reason or "refresh"
    perf.active = true
    perf.startedAt = debugprofilestop and debugprofilestop() or nil
    wipe(perf.counts)
    wipe(perf.timings)
    return perf
end

function Util.PerfReset(reason)
    if not Util.IsPerfEnabled() then return end
    EnsurePerfState(reason)
end

function Util.PerfBegin(name)
    if not Util.IsPerfEnabled() or not debugprofilestop or not State.perf or not State.perf.active then return nil end
    return debugprofilestop()
end

function Util.PerfEnd(name, startedAt)
    if not startedAt or not Util.IsPerfEnabled() or not debugprofilestop then return end
    local perf = State.perf
    if not perf or not perf.active then return end
    local elapsed = debugprofilestop() - startedAt
    local timings = perf.timings
    local bucket = timings[name]
    if not bucket then
        bucket = { count = 0, total = 0, max = 0 }
        timings[name] = bucket
    end
    bucket.count = bucket.count + 1
    bucket.total = bucket.total + elapsed
    if elapsed > bucket.max then
        bucket.max = elapsed
    end
end

function Util.PerfCount(name, amount)
    if not Util.IsPerfEnabled() then return end
    local perf = State.perf
    if not perf or not perf.active then return end
    perf.counts[name] = (perf.counts[name] or 0) + (amount or 1)
end

local function FormatPerfTiming(perf, name, label)
    label = label or name
    local bucket = perf and perf.timings and perf.timings[name]
    if not bucket then
        return label .. "=0"
    end
    return string.format("%s=%dx %.2fms max %.2f", label, bucket.count or 0, bucket.total or 0, bucket.max or 0)
end

local function GetPerfTimingTotal(perf, name)
    local bucket = perf and perf.timings and perf.timings[name]
    return bucket and bucket.total or 0
end

local function ShouldPrintPerfSummary(perf, reason, counts)
    if reason ~= "frame" then return true end
    if (counts.ScanUnitFull or 0) > 0 or (counts.CreateAuraIcon or 0) > 0 then return true end
    if GetPerfTimingTotal(perf, "RunRefreshBurst") >= 8 then return true end
    if GetPerfTimingTotal(perf, "UnitAura") >= 20 then return true end
    return false
end

function Util.PerfFlush(reason)
    if not Util.IsPerfEnabled() then return end
    local perf = State.perf
    if not perf or not perf.active then return end
    perf.active = false

    local counts = perf.counts or {}
    reason = tostring(reason or perf.reason or "refresh")
    if not ShouldPrintPerfSummary(perf, reason, counts) then return end

    local elapsed = perf.startedAt and debugprofilestop and (debugprofilestop() - perf.startedAt) or 0
    Util.PrintMessage(string.format(
        "perf %s window=%.0fms %s %s frames=%s scans=%s skipped=%s deltaSkip=%s fullFallback=%s auraCalls=%s icons=%s timerTicks=%s timerIcons=%s timerDur=%s/%s timerExp=%s/%s timerStale=%s timerPerm=%s/%s paintExp=%s paintStack=%s",
        reason,
        elapsed,
        FormatPerfTiming(perf, "RunRefreshBurst", "refresh"),
        FormatPerfTiming(perf, "UnitAura", "unitAura"),
        tostring(counts.RefreshFrame or 0),
        tostring(counts.ScanUnitFull or 0),
        tostring(counts.UpdateAuraIconsSkipped or 0),
        tostring(counts.UnitAuraRefreshSkipped or 0),
        tostring(counts.UnitAuraFullScanFallback or 0),
        tostring(counts.LiveAuraCall or 0),
        tostring(counts.CreateAuraIcon or 0),
        tostring(counts.AuraTimerTick or 0),
        tostring(counts.AuraTimerIcon or 0),
        tostring(counts.AuraTimerCachedDuration or 0),
        tostring(counts.AuraTimerLiveDuration or 0),
        tostring(counts.AuraTimerCachedExpiration or 0),
        tostring(counts.AuraTimerLiveExpiration or 0),
        tostring(counts.AuraTimerSkippedStaleIcon or 0),
        tostring(counts.AuraTimerKnownPermanent or 0),
        tostring(counts.AuraTimerSkippedPermanent or 0),
        tostring(counts.IconPaintLiveExpiration or 0),
        tostring(counts.IconPaintLiveStack or 0)
    ))
end

function Util.ResolveFont(fontNameOrPath)
    if not fontNameOrPath or fontNameOrPath == "" then
        return Constants.DEFAULT_FONT
    end
    local fontPaths = Constants.FONT_PATHS or {}
    if fontPaths[fontNameOrPath] then
        return fontPaths[fontNameOrPath]
    end
    if IsFontPath(fontNameOrPath) then
        return fontNameOrPath
    end
    return Constants.DEFAULT_FONT
end

function RaidFrameAuras:SafeSetFont(fontString, fontNameOrPath, fontSize, outline)
    if not fontString then return false end
    local fontPath = Util.ResolveFont(fontNameOrPath)
    fontSize = fontSize or 10
    local flags = outline or ""
    local useShadow = flags == "SHADOW"
    if flags == "NONE" or useShadow then
        flags = ""
    end
    local key = tostring(fontPath) .. ":" .. tostring(fontSize) .. ":" .. tostring(flags) .. ":" .. tostring(useShadow)
    if fontString.rfaFontKey == key then
        return true
    end
    local ok = pcall(fontString.SetFont, fontString, fontPath, fontSize, flags)
    if not ok then
        pcall(fontString.SetFont, fontString, Constants.DEFAULT_FONT, fontSize, flags)
    end
    if useShadow then
        fontString:SetShadowColor(0, 0, 0, 0.95)
        fontString:SetShadowOffset(1, -1)
    else
        fontString:SetShadowColor(0, 0, 0, 0)
        fontString:SetShadowOffset(0, 0)
    end
    fontString.rfaFontKey = key
    return ok
end

function Util.Clamp(value, minValue, maxValue, fallback)
    value = Util.AsSafeNumber(value)
    if not value then
        return fallback
    end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

function Util.ReadColor(color, fallbackR, fallbackG, fallbackB, fallbackA)
    if type(color) ~= "table" then
        return fallbackR, fallbackG, fallbackB, fallbackA
    end
    return color.r or color[1] or fallbackR,
        color.g or color[2] or fallbackG,
        color.b or color[3] or fallbackB,
        color.a or color[4] or fallbackA
end

function Util.GetOptionColor(options, defaults, key, fallbackR, fallbackG, fallbackB, fallbackA)
    local color
    if type(options) == "table" and options[key] ~= nil then
        color = options[key]
    elseif type(defaults) == "table" then
        color = defaults[key]
    end
    return Util.ReadColor(color, fallbackR, fallbackG, fallbackB, fallbackA)
end

local function GetRemainingTimeThresholdColors(options, defaults)
    local criticalR, criticalG, criticalB, criticalA = Util.GetOptionColor(options, defaults, "thresholdColorCritical", 1, 0.12, 0.04, 1)
    local shortR, shortG, shortB, shortA = Util.GetOptionColor(options, defaults, "thresholdColorWarning", 1, 0.82, 0, 1)
    local longR, longG, longB, longA = Util.GetOptionColor(options, defaults, "thresholdColorNormal", 1, 1, 1, 1)
    return criticalR, criticalG, criticalB, criticalA,
        shortR, shortG, shortB, shortA,
        longR, longG, longB, longA
end

local function GetOptionNumber(options, defaults, key, minValue, maxValue, fallback)
    local value
    if type(options) == "table" and options[key] ~= nil then
        value = options[key]
    elseif type(defaults) == "table" and defaults[key] ~= nil then
        value = defaults[key]
    end
    return Util.Clamp(value, minValue, maxValue, fallback)
end

local function GetRemainingTimeThresholds(options, defaults)
    local expiringSoon = GetOptionNumber(options, defaults, "thresholdExpiringSoon", 1, 60, 5)
    local shortDuration = GetOptionNumber(options, defaults, "thresholdShortDuration", 5, 300, 60)
    local longDuration = GetOptionNumber(options, defaults, "thresholdLongDuration", 60, 3600, 300)
    local offset = GetOptionNumber(options, defaults, "thresholdTransitionOffset", -2, 2, 0.5)

    if shortDuration < expiringSoon then shortDuration = expiringSoon end
    if longDuration < shortDuration then longDuration = shortDuration end

    local expiringCutoff = math.max(0, expiringSoon + offset)
    local shortCutoff = math.max(expiringCutoff, shortDuration + offset)
    local longCutoff = math.max(shortCutoff, longDuration + offset)
    return expiringCutoff, shortCutoff, longCutoff
end

function Util.GetRemainingTimeColor(options, defaults, remaining)
    remaining = tonumber(remaining)
    if not remaining then return nil end
    remaining = math.max(0, remaining)

    local criticalR, criticalG, criticalB, criticalA,
        shortR, shortG, shortB, shortA,
        longR, longG, longB, longA = GetRemainingTimeThresholdColors(options, defaults)
    local expiringCutoff, shortCutoff, longCutoff = GetRemainingTimeThresholds(options, defaults)

    if remaining < expiringCutoff then
        return criticalR, criticalG, criticalB, criticalA
    elseif remaining < shortCutoff then
        return shortR, shortG, shortB, shortA
    elseif remaining < longCutoff then
        return longR, longG, longB, longA
    end
    return 1, 1, 1, 1
end

function Util.AddRemainingTimeColorPoints(curve, options, defaults)
    if not curve or not CreateColor then return false end

    local criticalR, criticalG, criticalB, criticalA,
        shortR, shortG, shortB, shortA,
        longR, longG, longB, longA = GetRemainingTimeThresholdColors(options, defaults)
    local expiringCutoff, shortCutoff, longCutoff = GetRemainingTimeThresholds(options, defaults)

    local lastPoint
    local function AddPoint(time, color)
        time = tonumber(time) or 0
        if lastPoint and time <= lastPoint then
            time = lastPoint + 0.001
        end
        curve:AddPoint(time, color)
        lastPoint = time
    end

    AddPoint(0, CreateColor(criticalR, criticalG, criticalB, criticalA))
    AddPoint(expiringCutoff, CreateColor(shortR, shortG, shortB, shortA))
    AddPoint(shortCutoff, CreateColor(longR, longG, longB, longA))
    AddPoint(longCutoff, CreateColor(1, 1, 1, 1))
    AddPoint(3600, CreateColor(1, 1, 1, 1))
    return true
end

function Util.ClampCategoryScale(value)
    return Util.Clamp(value, Constants.CATEGORY_SCALE_MIN or 0.5, Constants.CATEGORY_SCALE_MAX or 2, 1)
end

local function GetFrameScaleForAuraSize(frame)
    if not frame or type(frame.GetEffectiveScale) ~= "function" then
        return 1
    end

    local frameScale = Util.AsSafeNumber(frame:GetEffectiveScale(), 1)
    if frameScale <= 0 then
        frameScale = 1
    end

    local rootScale = 1
    if UIParent and type(UIParent.GetEffectiveScale) == "function" then
        rootScale = Util.AsSafeNumber(UIParent:GetEffectiveScale(), 1)
        if rootScale <= 0 then
            rootScale = 1
        end
    end

    return frameScale / rootScale
end

local function GetSafePositiveFrameNumber(frame, method)
    if not frame or type(frame[method]) ~= "function" then return nil end
    local value = Util.AsSafeNumber(frame[method](frame))
    if not value or value <= 0 then return nil end
    return value
end

local function GetFrameDimensionsForAuraScale(frame)
    if not frame then return nil, nil end
    local width = GetSafePositiveFrameNumber(frame, "GetWidth")
    local height = GetSafePositiveFrameNumber(frame, "GetHeight")

    local scale = GetFrameScaleForAuraSize(frame)
    if scale ~= 1 then
        if width then width = width * scale end
        if height then height = height * scale end
    end

    return width, height
end

function RaidFrameAuras:GetAuraAutoScaleReferenceDimensions()
    local db = self.db or DEFAULTS
    local referenceWidth = Util.Clamp(db.previewWidth, Constants.PREVIEW_WIDTH_MIN or 72, Constants.PREVIEW_WIDTH_MAX or 144, DEFAULTS.previewWidth or 144)
    local referenceHeight = Util.Clamp(db.previewHeight, Constants.PREVIEW_HEIGHT_MIN or 36, Constants.PREVIEW_HEIGHT_MAX or 72, DEFAULTS.previewHeight or 72)
    return referenceWidth, referenceHeight
end

function RaidFrameAuras:GetAuraAutoScaleFactor(frame)
    local frameWidth, frameHeight = GetFrameDimensionsForAuraScale(frame)
    if not frameWidth and not frameHeight then
        return 1
    end

    local referenceWidth, referenceHeight = self:GetAuraAutoScaleReferenceDimensions()
    local widthScale = frameWidth and referenceWidth and referenceWidth > 0 and (frameWidth / referenceWidth) or nil
    local heightScale = frameHeight and referenceHeight and referenceHeight > 0 and (frameHeight / referenceHeight) or nil

    if widthScale and heightScale then
        return math.min(widthScale, heightScale)
    end
    return widthScale or heightScale or 1
end

function RaidFrameAuras:GetAuraConfiguredSize(auraType)
    local db = self.db or DEFAULTS
    local prefix = auraType == "BUFF" and "buff" or "debuff"
    return Util.Clamp(db[prefix .. "Size"], 4, 80, DEFAULTS[prefix .. "Size"])
end

function RaidFrameAuras:GetAuraBaseSize(auraType, frame)
    local db = self.db or DEFAULTS
    local prefix = auraType == "BUFF" and "buff" or "debuff"
    local baseSize = self:GetAuraConfiguredSize(auraType)

    if db[prefix .. "AutoScale"] ~= true then
        return baseSize
    end

    local minSize = Util.Clamp(db[prefix .. "AutoScaleMinSize"], 4, 80, DEFAULTS[prefix .. "AutoScaleMinSize"] or 8)
    local maxSize = Util.Clamp(db[prefix .. "AutoScaleMaxSize"], 4, 120, DEFAULTS[prefix .. "AutoScaleMaxSize"] or 60)
    if maxSize < minSize then
        maxSize = minSize
    end

    return Util.Clamp(baseSize * self:GetAuraAutoScaleFactor(frame), minSize, maxSize, baseSize)
end

function RaidFrameAuras:GetAuraIconSize(auraType, categoryScale, frame)
    return self:GetAuraBaseSize(auraType, frame) * Util.ClampCategoryScale(categoryScale)
end

function RaidFrameAuras:GetAuraVisualScale(auraType, categoryScale, frame)
    local configuredSize = self:GetAuraConfiguredSize(auraType)
    if not configuredSize or configuredSize <= 0 then
        return Util.ClampCategoryScale(categoryScale)
    end
    return self:GetAuraIconSize(auraType, categoryScale, frame) / configuredSize
end

function Util.ExtractUnitToken(value)
    if type(value) == "string" then
        return value ~= "" and value or nil
    end
    if type(value) ~= "table" then
        return nil
    end
    local token = value.unitid
        or value.unitID
        or value.unitToken
        or value.displayedUnit
        or value.memberUnit
        or value.unit
    return type(token) == "string" and token ~= "" and token or nil
end

function Util.GetFrameUnit(frame)
    if not frame then return nil end
    return Util.ExtractUnitToken(frame.unitToken)
        or Util.ExtractUnitToken(frame.displayedUnit)
        or Util.ExtractUnitToken(frame.memberUnit)
        or Util.ExtractUnitToken(frame.unit)
        or Util.ExtractUnitToken(frame.unitid)
        or Util.ExtractUnitToken(frame.unitID)
end

function Util.GetCleanRosterUnitForTooltip(frame, fallbackUnit)
    local sourceUnit = fallbackUnit or (frame and frame.rfaUnit) or Util.GetFrameUnit(frame)
    if type(sourceUnit) ~= "string" or not UnitGUID then return nil end
    local guid = UnitGUID(sourceUnit)
    if not guid or Util.IsSecretValue(guid) then return nil end

    if UnitGUID("player") == guid then
        return "player"
    end

    if IsInRaid and IsInRaid() then
        local count = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, count do
            local unit = "raid" .. i
            if UnitGUID(unit) == guid then
                return unit
            end
        end
    else
        local count = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
        for i = 1, count do
            local unit = "party" .. i
            if UnitGUID(unit) == guid then
                return unit
            end
        end
    end
    return nil
end

function Util.IsCompactUnitFrame(frame)
    return type(frame) == "table"
        and type(frame.IsVisible) == "function"
        and type(frame.HookScript) == "function"
end

function Util.IsRosterUnit(unit)
    if type(unit) ~= "string" then return false end
    if unit == "player" then return true end
    if unit:match("^party%d$") then return true end
    if unit:match("^raid%d+$") then return true end
    return false
end

function RaidFrameAuras:IsTrackedUnit(unit)
    local db = self.db
    if not db or not db.enabled or not Util.IsRosterUnit(unit) then
        return false
    end
    if unit == "player" then
        return db.showPlayer == true
    end
    if unit:match("^party%d$") then
        return db.showParty == true
    end
    if unit:match("^raid%d+$") then
        return db.showRaid == true
    end
    return false
end

function Util.GetOppositeAnchor(anchor)
    local opposites = {
        TOPLEFT = "BOTTOMRIGHT",
        TOP = "BOTTOM",
        TOPRIGHT = "BOTTOMLEFT",
        LEFT = "RIGHT",
        CENTER = "CENTER",
        RIGHT = "LEFT",
        BOTTOMLEFT = "TOPRIGHT",
        BOTTOM = "TOP",
        BOTTOMRIGHT = "TOPLEFT",
    }
    return opposites[anchor] or "BOTTOMLEFT"
end

local function IsHorizontalDirection(direction)
    return direction == "LEFT" or direction == "RIGHT"
end

local function IsForwardDirection(direction)
    return direction == "RIGHT" or direction == "UP"
end

local function GetAnchorFactor(anchor, horizontal)
    local anchorFactors = Constants.ANCHOR_FACTORS or {}
    local factors = anchorFactors[anchor] or anchorFactors.BOTTOMLEFT or { x = 0, y = 0 }
    return horizontal and factors.x or factors.y
end

local function GetIconLayoutSize(icon, fallbackSize)
    local fallback = Util.AsSafeNumber(fallbackSize, 1) or 1
    local width = icon and Util.AsSafeNumber(icon.rfaLayoutWidth) or nil
    if not width and icon and type(icon.rfaSizeKey) == "string" then
        local keyWidth = icon.rfaSizeKey:match("^([^:]+)")
        width = Util.AsSafeNumber(keyWidth and tonumber(keyWidth) and tonumber(keyWidth) / 100)
    end
    if not width and icon and icon.GetWidth then
        width = Util.AsSafeNumber(icon:GetWidth(), fallback)
    end
    if not width or width <= 0 then
        width = fallback
    end

    local scale = icon and Util.AsSafeNumber(icon.rfaLayoutScale) or nil
    if not scale and icon and icon.GetScale then
        scale = Util.AsSafeNumber(icon:GetScale(), 1)
    end
    if not scale or scale <= 0 then
        scale = 1
    end

    return width * scale
end

local function GetAxisDistance(direction, previousSize, nextSize, padding, anchorFactor)
    if IsForwardDirection(direction) then
        return ((1 - anchorFactor) * previousSize) + (anchorFactor * nextSize) + padding
    end
    return -((anchorFactor * previousSize) + ((1 - anchorFactor) * nextSize) + padding)
end

local function GetAxisExtents(position, size, anchorFactor)
    return position - (anchorFactor * size), position + ((1 - anchorFactor) * size)
end

local function AddAxisOffset(x, y, horizontal, amount)
    if horizontal then
        return x + amount, y
    end
    return x, y + amount
end

function Util.PositionScaledIconStack(icons, visibleCount, options)
    if not icons or not visibleCount or visibleCount <= 0 then return end
    options = options or {}
    local size = tonumber(options.size) or 1
    local anchor = options.anchor or "BOTTOMLEFT"
    local growth = options.growth or "RIGHT_UP"
    local wrap = Util.Clamp(options.wrap, 1, 20, 1)
    local offsetX = tonumber(options.offsetX) or 0
    local offsetY = tonumber(options.offsetY) or 0
    local paddingX = tonumber(options.paddingX) or 0
    local paddingY = tonumber(options.paddingY) or 0
    local primary, secondary = strsplit("_", growth)
    primary = primary or "LEFT"
    secondary = secondary or "UP"

    local centered = primary == "CENTER"
    local primaryDirection = centered and (IsHorizontalDirection(secondary) and "DOWN" or "RIGHT") or primary
    local primaryHorizontal = IsHorizontalDirection(primaryDirection)
    local secondaryHorizontal = IsHorizontalDirection(secondary)
    local primaryPadding = centered and (primaryHorizontal and paddingX or paddingY) or paddingX
    local secondaryPadding = centered and (secondaryHorizontal and paddingX or paddingY) or paddingY
    local primaryAnchorFactor = GetAnchorFactor(anchor, primaryHorizontal)
    local secondaryAnchorFactor = GetAnchorFactor(anchor, secondaryHorizontal)
    local lines = {}

    for i = 1, visibleCount do
        local lineIndex = math.floor((i - 1) / wrap) + 1
        local line = lines[lineIndex]
        if not line then
            line = { entries = {} }
            lines[lineIndex] = line
        end
        local icon = icons[i]
        line.entries[#line.entries + 1] = {
            icon = icon,
            size = GetIconLayoutSize(icon, size),
            primary = 0,
        }
    end

    for _, line in ipairs(lines) do
        local entries = line.entries
        for i = 2, #entries do
            local previous = entries[i - 1]
            local entry = entries[i]
            entry.primary = previous.primary + GetAxisDistance(primaryDirection, previous.size, entry.size, primaryPadding, primaryAnchorFactor)
        end

        local primaryMin, primaryMax
        local secondaryMin, secondaryMax
        for _, entry in ipairs(entries) do
            local low, high = GetAxisExtents(entry.primary, entry.size, primaryAnchorFactor)
            primaryMin = primaryMin and math.min(primaryMin, low) or low
            primaryMax = primaryMax and math.max(primaryMax, high) or high

            low, high = GetAxisExtents(0, entry.size, secondaryAnchorFactor)
            secondaryMin = secondaryMin and math.min(secondaryMin, low) or low
            secondaryMax = secondaryMax and math.max(secondaryMax, high) or high
        end
        line.primaryOffset = centered and -((primaryMin or 0) + (primaryMax or 0)) / 2 or 0
        line.secondaryMin = secondaryMin or 0
        line.secondaryMax = secondaryMax or size
    end

    for i = 2, #lines do
        local previous = lines[i - 1]
        local line = lines[i]
        if IsForwardDirection(secondary) then
            line.secondary = (previous.secondary or 0) + previous.secondaryMax - line.secondaryMin + secondaryPadding
        else
            line.secondary = (previous.secondary or 0) + previous.secondaryMin - line.secondaryMax - secondaryPadding
        end
    end
    if lines[1] then
        lines[1].secondary = 0
    end

    for _, line in ipairs(lines) do
        for _, entry in ipairs(line.entries) do
            if entry.icon then
                local x, y = offsetX, offsetY
                x, y = AddAxisOffset(x, y, primaryHorizontal, entry.primary + (line.primaryOffset or 0))
                x, y = AddAxisOffset(x, y, secondaryHorizontal, line.secondary or 0)
                entry.icon:ClearAllPoints()
                entry.icon:SetPoint(anchor, options.relativeTo, anchor, x, y)
            end
        end
    end
end
