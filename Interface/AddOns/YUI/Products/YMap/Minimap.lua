local YUI = _G.YUI
if not YUI or not YUI.YMap or (not YUI.IsForever and YUI.IsRetail == false) then return end

local YMap = YUI.YMap
local GUI2 = YUI.GUI2
local Security = YUI.API and YUI.API.Security
local DelvesAPI = YUI.API and YUI.API.Delves
local Event = YUI.Event

local MinimapModule = YMap.Minimap or {}
YMap.Minimap = MinimapModule

local LAYOUT_ID = YMap.LAYOUT_ID or "yui.product.ymap.minimap"
local BELOW_WIDGET_LAYOUT_ID = YMap.BELOW_WIDGET_LAYOUT_ID or "yui.product.ymap.belowWidget"
local SQUARE_MASK = 130937
local NATIVE_MASK = 186178
local EPSILON = 0.001
local DEFAULT_BORDER_RED = 0.22
local DEFAULT_BORDER_GREEN = 0.26
local DEFAULT_BORDER_BLUE = 0.32
local DEFAULT_BORDER_ALPHA = 1
local BELOW_WIDGET_PLACEMENT_MIGRATION_VERSION = 1

local math_abs = math.abs
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local pairs = pairs
local pcall = pcall
local select = select
local setmetatable = setmetatable
local tonumber = tonumber
local type = type
local unpack_values = _G.unpack or table.unpack

local snapshots = setmetatable({}, { __mode = "k" })
local hookedFrames = setmetatable({}, { __mode = "k" })
local hookedScripts = setmetatable({}, { __mode = "k" })
local housingOverlayPoints = {
    { point = "TOPLEFT", relative = nil, relativePoint = "TOPLEFT", x = 0, y = 0 },
    { point = "BOTTOMRIGHT", relative = nil, relativePoint = "BOTTOMRIGHT", x = 0, y = 0 },
}
local housingOverlayTexCoords = {
    0.2, 0.2,
    0.2, 0.8,
    0.8, 0.2,
    0.8, 0.8,
}

local shapeOriginal
local shapeInstalled = false
local appliedMask
local maskTouched = false
local maskOwnershipLost = false
local nativeMask
local nativeMaskCaptured = false
local maskSetterIdentity
local indicatorFunctionHooked = false
local mutationScheduled = false
local baseGeometryMutationPending = false
local mutationOwner = {}
local MUTATION_EVENT = "YUI_YMAP_MINIMAP_MUTATION"

local nativeMetrics = {
    captured = false,
    mapWidth = 198,
    mapOffsetX = 10,
    mapOffsetY = -15,
}

local RELEVANT_LATE_ADDONS = {
    Blizzard_Minimap = true,
    Blizzard_QueueStatusFrame = true,
    Blizzard_TimeManager = true,
    Blizzard_UIWidgets = true,
    EllesmereUIMinimap = true,
}

local SQUARE_ELEMENT_DEFAULTS = {
    expansion = { hidden = false, anchor = "BOTTOMLEFT", offsetX = -20, offsetY = -3, scale = 0.65 },
    tracking = {
        hidden = true,
        anchor = "BOTTOMLEFT",
        offsetX = 3,
        offsetY = 3,
        scale = 1,
        rightClickOpen = true,
        rightClickHint = false,
    },
    calendar = { hidden = false, anchor = "TOPRIGHT", offsetX = -2, offsetY = -2, scale = 1 },
    mail = { hidden = false, anchor = "TOPRIGHT", offsetX = -28, offsetY = -3, scale = 1 },
    crafting = { hidden = false, anchor = "TOPRIGHT", offsetX = -50, offsetY = -3, scale = 1 },
    difficulty = {
        hidden = false,
        anchor = "TOPLEFT",
        offsetX = -3,
        offsetY = 1,
        scale = 1,
        textStyle = "zh",
    },
}

if YUI.IsForever then
    SQUARE_ELEMENT_DEFAULTS.diel = { hidden = false, anchor = "BOTTOMRIGHT", offsetX = -2, offsetY = -2, scale = 0.75 }
end

local NATIVE_APPEARANCE_DEFAULTS = {
    hideClock = true,
    hideCalendar = false,
    zoneNameFontSize = 14,
}

MinimapModule.DIFFICULTY_PREVIEW_STYLES = {
    { id = "normal", red = 0.92, green = 0.92, blue = 0.92, sampleGroupSize = 5 },
    { id = "heroic", red = 0.25, green = 0.68, blue = 1, sampleGroupSize = 5 },
    { id = "mythic", red = 1, green = 0.35, blue = 0.12, sampleGroupSize = 20 },
    { id = "keystone", red = 0.72, green = 0.4, blue = 1 },
    { id = "raid_finder", red = 0.35, green = 1, blue = 0.5, sampleGroupSize = 25 },
    { id = "follower", red = 0.35, green = 0.9, blue = 0.9 },
    { id = "world_tier", red = 1, green = 0.78, blue = 0.2 },
}

local DIFFICULTY_GROUP_SIZE_STYLES = {
    normal = true,
    heroic = true,
    mythic = true,
    raid_finder = true,
}

local VALID_ANCHORS = {
    TOPLEFT = true,
    TOPRIGHT = true,
    BOTTOMLEFT = true,
    BOTTOMRIGHT = true,
}

MinimapModule.enabled = MinimapModule.enabled == true
MinimapModule.active = MinimapModule.active == true
MinimapModule.applying = false
MinimapModule.editModeActive = false
MinimapModule.layoutRegistered = false
MinimapModule.belowWidgetLayoutRegistered = false
MinimapModule.hooksInstalled = false
MinimapModule.pendingRefresh = false
MinimapModule.pendingDisable = false
MinimapModule.pendingDisableKeepsConflict = false
MinimapModule.conflictReason = nil
MinimapModule.appliedStyle = nil
MinimapModule.reconciles = MinimapModule.reconciles or 0
MinimapModule.restoreFailures = MinimapModule.restoreFailures or 0
MinimapModule.writeFailures = MinimapModule.writeFailures or 0
MinimapModule.shadowComparisons = MinimapModule.shadowComparisons or 0
MinimapModule.shadowMismatches = MinimapModule.shadowMismatches or 0
MinimapModule.settingsPreviewKey = nil
MinimapModule.settingsPreviewState = nil
MinimapModule.minimapHovered = false
MinimapModule.rightClickHandlerActive = false
MinimapModule.rightClickHovered = false
MinimapModule.trackingHintEligible = false
MinimapModule.trackingHintDismissed = false
MinimapModule.trackingHintVisible = false
MinimapModule.trackingHintPositionWrites = MinimapModule.trackingHintPositionWrites or 0
MinimapModule.trackingMenuOwned = false
MinimapModule.trackingMenuOpenAttempts = MinimapModule.trackingMenuOpenAttempts or 0
MinimapModule.trackingMenuOpenSuccesses = MinimapModule.trackingMenuOpenSuccesses or 0
MinimapModule.trackingMenuOpenFailures = MinimapModule.trackingMenuOpenFailures or 0
MinimapModule.blobRingScalarsSuppressed = false
MinimapModule.coordinateConsumerRegistered = false
MinimapModule.coordinateVisible = MinimapModule.coordinateVisible == true
MinimapModule.coordinateQX = nil
MinimapModule.coordinateQY = nil
MinimapModule.coordinateReads = MinimapModule.coordinateReads or 0
MinimapModule.coordinateTextWrites = MinimapModule.coordinateTextWrites or 0

local function SetSharedStat(field, value)
    local stats = YMap.Stats
    if not stats then return end
    if stats.Set then
        stats:Set(field, value)
    elseif stats[field] ~= nil then
        stats[field] = value
    end
end

local function IncrementSharedStat(field, amount)
    local stats = YMap.Stats
    if not stats then return end
    if stats.Increment then
        stats:Increment(field, amount or 1)
    elseif type(stats[field]) == "number" then
        stats[field] = stats[field] + (amount or 1)
    end
end

local function Clamp(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value then return fallback end
    return math_min(maximum, math_max(minimum, value))
end

local function Round(value)
    if value >= 0 then return math_floor(value + 0.5) end
    return -math_floor(-value + 0.5)
end

local function NearlyEqual(left, right)
    if left == right then return true end
    if type(left) ~= "number" or type(right) ~= "number" then return false end
    return math_abs(left - right) <= EPSILON
end

local function ReadMethod(object, method, ...)
    if not object then return false end
    local callback = object[method]
    if type(callback) ~= "function" then return false end
    return pcall(callback, object, ...)
end

local function WriteMethod(object, method, ...)
    if not object then return false end
    local callback = object[method]
    if type(callback) ~= "function" then return false end
    local ok = pcall(callback, object, ...)
    if not ok then
        MinimapModule.writeFailures = MinimapModule.writeFailures + 1
    end
    return ok
end

local function RestoreWrite(object, method, ...)
    local ok = WriteMethod(object, method, ...)
    if not ok then
        MinimapModule.restoreFailures = MinimapModule.restoreFailures + 1
        IncrementSharedStat("restoreFailures", 1)
    end
    return ok
end

function MinimapModule:SetBlobRingScalar(method, scalar, restoring)
    local minimap = _G.Minimap
    if not minimap then return false, true end
    if type(minimap[method]) ~= "function" then return false, true end

    local ok
    if restoring then
        ok = RestoreWrite(minimap, method, scalar)
    else
        ok = WriteMethod(minimap, method, scalar)
    end
    return ok, ok
end

function MinimapModule:SetBlobRingScalars(scalar, restoring)
    local archWrote, archSucceeded = self:SetBlobRingScalar("SetArchBlobRingScalar", scalar, restoring)
    local questWrote, questSucceeded = self:SetBlobRingScalar("SetQuestBlobRingScalar", scalar, restoring)
    return archWrote or questWrote, archSucceeded and questSucceeded
end

function MinimapModule:RestoreBlobRingScalars()
    if not self.blobRingScalarsSuppressed then return true end
    local _, restored = self:SetBlobRingScalars(1, true)
    if restored then self.blobRingScalarsSuppressed = false end
    return restored
end

function MinimapModule:ApplyBlobRingScalars(style)
    if style ~= "square" then
        self:RestoreBlobRingScalars()
        return
    end
    local wrote = self:SetBlobRingScalars(0, false)
    if wrote then
        self.blobRingScalarsSuppressed = true
    end
end

local RestoreStateWrite
local BlockForConflict
local RepairBaseGeometryInCombat
local ReapplyYUIEditModeGeometry

local function IsUsableFrame(frame)
    if not frame then return false end
    if frame.IsForbidden then
        local ok, forbidden = pcall(frame.IsForbidden, frame)
        if not ok or forbidden == true then return false end
    end
    return type(frame.GetObjectType) == "function" or type(frame.GetParent) == "function"
end

local function InCombat()
    if Security and Security.InCombatLockdown then
        return Security.InCombatLockdown() == true
    end
    return _G.InCombatLockdown and _G.InCombatLockdown() == true
end

local function CapturePoints(frame)
    local ok, count = ReadMethod(frame, "GetNumPoints")
    if not ok or type(count) ~= "number" then return nil end
    local points = {}
    for index = 1, count do
        local pointOK, point, relative, relativePoint, x, y = ReadMethod(frame, "GetPoint", index)
        if pointOK and point then
            points[#points + 1] = {
                point = point,
                relative = relative,
                relativePoint = relativePoint,
                x = x or 0,
                y = y or 0,
            }
        end
    end
    return points
end

local function CaptureTexCoords(texture)
    local ok, topLeftX, topLeftY, bottomLeftX, bottomLeftY,
        topRightX, topRightY, bottomRightX, bottomRightY = ReadMethod(texture, "GetTexCoord")
    if not ok then return nil end
    return {
        topLeftX,
        topLeftY,
        bottomLeftX,
        bottomLeftY,
        topRightX,
        topRightY,
        bottomRightX,
        bottomRightY,
    }
end

local function CaptureFrame(frame)
    if not IsUsableFrame(frame) then return nil end
    local existing = snapshots[frame]
    if existing then return existing end

    local state = {
        touched = {},
        applied = {},
        methods = {
            SetParent = frame.SetParent,
            SetSize = frame.SetSize,
            SetScale = frame.SetScale,
            SetAlpha = frame.SetAlpha,
            Show = frame.Show,
            Hide = frame.Hide,
            SetFrameLevel = frame.SetFrameLevel,
            SetFrameStrata = frame.SetFrameStrata,
            SetIgnoreParentScale = frame.SetIgnoreParentScale,
            EnableMouse = frame.EnableMouse,
            ClearAllPoints = frame.ClearAllPoints,
            SetPoint = frame.SetPoint,
            SetJustifyH = frame.SetJustifyH,
            SetFont = frame.SetFont,
            SetTexCoord = frame.SetTexCoord,
        },
    }
    local ok
    ok, state.parent = ReadMethod(frame, "GetParent")
    state.hasParent = ok
    ok, state.width, state.height = ReadMethod(frame, "GetSize")
    state.hasSize = ok
    ok, state.scale = ReadMethod(frame, "GetScale")
    state.hasScale = ok
    ok, state.alpha = ReadMethod(frame, "GetAlpha")
    state.hasAlpha = ok
    ok, state.shown = ReadMethod(frame, "IsShown")
    state.hasShown = ok
    ok, state.frameLevel = ReadMethod(frame, "GetFrameLevel")
    state.hasFrameLevel = ok
    ok, state.frameStrata = ReadMethod(frame, "GetFrameStrata")
    state.hasFrameStrata = ok
    ok, state.ignoreParentScale = ReadMethod(frame, "GetIgnoreParentScale")
    state.hasIgnoreParentScale = ok
    ok, state.mouseEnabled = ReadMethod(frame, "IsMouseEnabled")
    state.hasMouseEnabled = ok
    ok, state.justifyH = ReadMethod(frame, "GetJustifyH")
    state.hasJustifyH = ok
    ok, state.font, state.fontSize, state.fontFlags = ReadMethod(frame, "GetFont")
    state.hasFont = ok and state.font ~= nil
    state.points = CapturePoints(frame)
    state.texCoords = CaptureTexCoords(frame)
    state.hasTexCoords = state.texCoords ~= nil
    snapshots[frame] = state
    return state
end

local function Touch(frame, field)
    local state = CaptureFrame(frame)
    if not state then return nil end
    state.touched[field] = true
    return state
end

local function RecordShadowComparison(matches)
    MinimapModule.shadowComparisons = MinimapModule.shadowComparisons + 1
    IncrementSharedStat("shadowComparisons", 1)
    if matches ~= true then
        MinimapModule.shadowMismatches = MinimapModule.shadowMismatches + 1
        IncrementSharedStat("shadowMismatches", 1)
        return false
    end
    return true
end

local function PointsMatch(left, right)
    if type(left) ~= "table" or type(right) ~= "table" or #left ~= #right then return false end
    for index = 1, #left do
        local leftPoint = left[index]
        local rightPoint = right[index]
        if not leftPoint or not rightPoint
            or leftPoint.point ~= rightPoint.point
            or leftPoint.relative ~= rightPoint.relative
            or leftPoint.relativePoint ~= rightPoint.relativePoint
            or not NearlyEqual(leftPoint.x or 0, rightPoint.x or 0)
            or not NearlyEqual(leftPoint.y or 0, rightPoint.y or 0)
        then
            return false
        end
    end
    return true
end

local function TexCoordsMatchCurrent(texture, expected)
    if type(expected) ~= "table" or #expected ~= 8 then return false end
    local ok, topLeftX, topLeftY, bottomLeftX, bottomLeftY,
        topRightX, topRightY, bottomRightX, bottomRightY = ReadMethod(texture, "GetTexCoord")
    return ok
        and NearlyEqual(topLeftX, expected[1])
        and NearlyEqual(topLeftY, expected[2])
        and NearlyEqual(bottomLeftX, expected[3])
        and NearlyEqual(bottomLeftY, expected[4])
        and NearlyEqual(topRightX, expected[5])
        and NearlyEqual(topRightY, expected[6])
        and NearlyEqual(bottomRightX, expected[7])
        and NearlyEqual(bottomRightY, expected[8])
end

local function FieldStillOwned(frame, state, field)
    local applied = state and state.applied and state.applied[field]
    if applied == nil then return RecordShadowComparison(false) end

    local ok, first, second
    if field == "parent" then
        ok, first = ReadMethod(frame, "GetParent")
        return RecordShadowComparison(ok and first == applied)
    elseif field == "size" then
        ok, first, second = ReadMethod(frame, "GetSize")
        return RecordShadowComparison(ok and NearlyEqual(first, applied.width) and NearlyEqual(second, applied.height))
    elseif field == "scale" then
        ok, first = ReadMethod(frame, "GetScale")
        return RecordShadowComparison(ok and NearlyEqual(first, applied))
    elseif field == "alpha" then
        ok, first = ReadMethod(frame, "GetAlpha")
        return RecordShadowComparison(ok and NearlyEqual(first, applied))
    elseif field == "shown" then
        ok, first = ReadMethod(frame, "IsShown")
        return RecordShadowComparison(ok and first == applied)
    elseif field == "frameLevel" then
        ok, first = ReadMethod(frame, "GetFrameLevel")
        return RecordShadowComparison(ok and first == applied)
    elseif field == "mouseEnabled" then
        ok, first = ReadMethod(frame, "IsMouseEnabled")
        return RecordShadowComparison(ok and first == applied)
    elseif field == "ignoreParentScale" then
        ok, first = ReadMethod(frame, "GetIgnoreParentScale")
        return RecordShadowComparison(ok and first == applied)
    elseif field == "justifyH" then
        ok, first = ReadMethod(frame, "GetJustifyH")
        return RecordShadowComparison(ok and first == applied)
    elseif field == "font" then
        local third
        ok, first, second, third = ReadMethod(frame, "GetFont")
        return RecordShadowComparison(ok
            and first == applied.font
            and NearlyEqual(second, applied.size)
            and (third or "") == applied.flags)
    elseif field == "points" then
        return RecordShadowComparison(PointsMatch(CapturePoints(frame), applied))
    elseif field == "texCoords" then
        return RecordShadowComparison(TexCoordsMatchCurrent(frame, applied))
    end
    return RecordShadowComparison(false)
end

local function MarkApplied(state, field, value)
    if state and state.applied then state.applied[field] = value end
end

local function EnsureParent(frame, parent)
    local ok, current = ReadMethod(frame, "GetParent")
    if ok and current == parent then return true end
    local state = Touch(frame, "parent")
    if not state then return false end
    local written = WriteMethod(frame, "SetParent", parent)
    if written then MarkApplied(state, "parent", parent) end
    return written
end

local function EnsureSize(frame, width, height)
    local ok, currentWidth, currentHeight = ReadMethod(frame, "GetSize")
    if ok and NearlyEqual(currentWidth, width) and NearlyEqual(currentHeight, height) then return true end
    local state = Touch(frame, "size")
    if not state then return false end
    local written = WriteMethod(frame, "SetSize", width, height)
    if written then MarkApplied(state, "size", { width = width, height = height }) end
    return written
end

local function EnsureScale(frame, scale)
    local ok, current = ReadMethod(frame, "GetScale")
    if ok and NearlyEqual(current, scale) then return true end
    local state = Touch(frame, "scale")
    if not state then return false end
    local written = WriteMethod(frame, "SetScale", scale)
    if written then MarkApplied(state, "scale", scale) end
    return written
end

local function EnsureAlpha(frame, alpha)
    local ok, current = ReadMethod(frame, "GetAlpha")
    if ok and NearlyEqual(current, alpha) then return true end
    local state = Touch(frame, "alpha")
    if not state then return false end
    local written = WriteMethod(frame, "SetAlpha", alpha)
    if written then MarkApplied(state, "alpha", alpha) end
    return written
end

local function EnsureShown(frame, shown)
    local ok, current = ReadMethod(frame, "IsShown")
    if ok and current == shown then return true end
    local state = Touch(frame, "shown")
    if not state then return false end
    local written = WriteMethod(frame, shown and "Show" or "Hide")
    if written then MarkApplied(state, "shown", shown) end
    return written
end

local function EnsureSetShown(frame, shown)
    local ok, current = ReadMethod(frame, "IsShown")
    if ok and current == shown then return true end
    local state = Touch(frame, "shown")
    if not state then return false end
    local written
    if type(frame.SetShown) == "function" then
        written = WriteMethod(frame, "SetShown", shown)
    else
        written = WriteMethod(frame, shown and "Show" or "Hide")
    end
    if written then MarkApplied(state, "shown", shown) end
    return written
end

local function EnsureFrameLevel(frame, level)
    local ok, current = ReadMethod(frame, "GetFrameLevel")
    if ok and current == level then return true end
    local state = Touch(frame, "frameLevel")
    if not state then return false end
    local written = WriteMethod(frame, "SetFrameLevel", level)
    if written then MarkApplied(state, "frameLevel", level) end
    return written
end

local function EnsureMouse(frame, enabled)
    local ok, current = ReadMethod(frame, "IsMouseEnabled")
    if ok and current == enabled then return true end
    local state = Touch(frame, "mouseEnabled")
    if not state then return false end
    local written = WriteMethod(frame, "EnableMouse", enabled)
    if written then MarkApplied(state, "mouseEnabled", enabled) end
    return written
end

local function EnsureIgnoreParentScale(frame, ignore)
    local ok, current = ReadMethod(frame, "GetIgnoreParentScale")
    if ok and current == ignore then return true end
    local state = Touch(frame, "ignoreParentScale")
    if not state then return false end
    local written = WriteMethod(frame, "SetIgnoreParentScale", ignore)
    if written then MarkApplied(state, "ignoreParentScale", ignore) end
    return written
end

local function EnsureJustifyH(frame, justify)
    local ok, current = ReadMethod(frame, "GetJustifyH")
    if ok and current == justify then return true end
    local state = Touch(frame, "justifyH")
    if not state then return false end
    local written = WriteMethod(frame, "SetJustifyH", justify)
    if written then MarkApplied(state, "justifyH", justify) end
    return written
end

local function EnsureFont(frame, font, size, flags)
    local ok, currentFont, currentSize, currentFlags = ReadMethod(frame, "GetFont")
    flags = flags or ""
    if ok
        and currentFont == font
        and NearlyEqual(currentSize, size)
        and (currentFlags or "") == flags
    then
        return true
    end
    local state = Touch(frame, "font")
    if not state then return false end
    local written = WriteMethod(frame, "SetFont", font, size, flags)
    if written then
        MarkApplied(state, "font", {
            font = font,
            size = size,
            flags = flags,
        })
    end
    return written
end

local function PointMatches(frame, point, relative, relativePoint, x, y)
    local ok, count = ReadMethod(frame, "GetNumPoints")
    if not ok or count ~= 1 then return false end
    local pointOK, currentPoint, currentRelative, currentRelativePoint, currentX, currentY = ReadMethod(frame, "GetPoint", 1)
    if not pointOK then return false end
    return currentPoint == point
        and currentRelative == relative
        and currentRelativePoint == relativePoint
        and NearlyEqual(currentX or 0, x or 0)
        and NearlyEqual(currentY or 0, y or 0)
end

local function EnsurePoint(frame, point, relative, relativePoint, x, y)
    if PointMatches(frame, point, relative, relativePoint, x, y) then return true end
    local state = Touch(frame, "points")
    if not state then return false end
    if frame.ClearAllPoints ~= state.methods.ClearAllPoints or frame.SetPoint ~= state.methods.SetPoint then
        MinimapModule.writeFailures = MinimapModule.writeFailures + 1
        return false
    end
    if not WriteMethod(frame, "ClearAllPoints") then return false end
    local written = WriteMethod(frame, "SetPoint", point, relative, relativePoint, x or 0, y or 0)
    if written then
        MarkApplied(state, "points", {
            {
                point = point,
                relative = relative,
                relativePoint = relativePoint,
                x = x or 0,
                y = y or 0,
            },
        })
    end
    return written
end

local function EnsurePoints(frame, points)
    if PointsMatch(CapturePoints(frame), points) then return true end
    local state = Touch(frame, "points")
    if not state then return false end
    if frame.ClearAllPoints ~= state.methods.ClearAllPoints or frame.SetPoint ~= state.methods.SetPoint then
        MinimapModule.writeFailures = MinimapModule.writeFailures + 1
        return false
    end
    if not WriteMethod(frame, "ClearAllPoints") then return false end
    for index = 1, #points do
        local point = points[index]
        if not WriteMethod(
            frame,
            "SetPoint",
            point.point,
            point.relative,
            point.relativePoint,
            point.x or 0,
            point.y or 0
        ) then
            return false
        end
    end
    MarkApplied(state, "points", CapturePoints(frame))
    return true
end

local function EnsureTexCoords(texture, target)
    if TexCoordsMatchCurrent(texture, target) then return true end
    local state = Touch(texture, "texCoords")
    if not state or texture.SetTexCoord ~= state.methods.SetTexCoord then
        MinimapModule.writeFailures = MinimapModule.writeFailures + 1
        return false
    end
    local written = WriteMethod(texture, "SetTexCoord", target[1], target[5], target[2], target[4])
    if written then MarkApplied(state, "texCoords", target) end
    return written
end

local function RestoreMethodsAvailable(frame, state, ...)
    for index = 1, select("#", ...) do
        local method = select(index, ...)
        local expected = state and state.methods and state.methods[method]
        if type(expected) ~= "function" or not frame or frame[method] ~= expected then
            MinimapModule.restoreFailures = MinimapModule.restoreFailures + 1
            IncrementSharedStat("restoreFailures", 1)
            return false
        end
    end
    return true
end

local function ButtonDrawerOwns(frame)
    local drawer = YMap.ButtonDrawer
    if not frame or not drawer or type(drawer.IsCaptured) ~= "function" then return false end
    local ok, owns = pcall(drawer.IsCaptured, drawer, frame)
    return ok and owns == true
end

local function RestoreFrameBasics(frame, state)
    local touched = state.touched
    state.restoreYielded = false
    if touched.parent and state.hasParent then
        if not FieldStillOwned(frame, state, "parent")
            or not RestoreStateWrite(frame, state, "SetParent", state.parent)
        then
            state.restoreYielded = true
            return
        end
    end
    if touched.ignoreParentScale and state.hasIgnoreParentScale and FieldStillOwned(frame, state, "ignoreParentScale") then
        RestoreStateWrite(frame, state, "SetIgnoreParentScale", state.ignoreParentScale)
    end
    if touched.scale and state.hasScale and FieldStillOwned(frame, state, "scale") then
        RestoreStateWrite(frame, state, "SetScale", state.scale)
    end
    if touched.size and state.hasSize and FieldStillOwned(frame, state, "size") then
        RestoreStateWrite(frame, state, "SetSize", state.width, state.height)
    end
    if touched.frameStrata and state.hasFrameStrata then RestoreStateWrite(frame, state, "SetFrameStrata", state.frameStrata) end
    if touched.frameLevel and state.hasFrameLevel and FieldStillOwned(frame, state, "frameLevel") then
        RestoreStateWrite(frame, state, "SetFrameLevel", state.frameLevel)
    end
    if touched.mouseEnabled and state.hasMouseEnabled and FieldStillOwned(frame, state, "mouseEnabled") then
        RestoreStateWrite(frame, state, "EnableMouse", state.mouseEnabled)
    end
end

local function RestoreFramePoints(frame, state)
    if state.restoreYielded then return end
    if not state.touched.points or not state.points then return end
    if not FieldStillOwned(frame, state, "points") then return end
    if not RestoreMethodsAvailable(frame, state, "ClearAllPoints", "SetPoint") then return end
    if not RestoreWrite(frame, "ClearAllPoints") then return end
    for index = 1, #state.points do
        local point = state.points[index]
        if not RestoreWrite(frame, "SetPoint", point.point, point.relative, point.relativePoint, point.x, point.y) then return end
    end
end

local function RestoreFrameAppearance(frame, state)
    if state.restoreYielded then return end
    local touched = state.touched
    if touched.font and state.hasFont and FieldStillOwned(frame, state, "font") then
        RestoreStateWrite(frame, state, "SetFont", state.font, state.fontSize, state.fontFlags or "")
    end
    if touched.justifyH and state.hasJustifyH and FieldStillOwned(frame, state, "justifyH") then
        RestoreStateWrite(frame, state, "SetJustifyH", state.justifyH)
    end
    if touched.texCoords and state.hasTexCoords and FieldStillOwned(frame, state, "texCoords") then
        if RestoreMethodsAvailable(frame, state, "SetTexCoord") then
            RestoreStateWrite(frame, state, "SetTexCoord", unpack_values(state.texCoords))
        end
    end
    if touched.alpha and state.hasAlpha and FieldStillOwned(frame, state, "alpha") then
        RestoreStateWrite(frame, state, "SetAlpha", state.alpha)
    end
    if touched.shown and state.hasShown and FieldStillOwned(frame, state, "shown") then
        RestoreStateWrite(frame, state, state.shown and "Show" or "Hide")
    end
end

local function RestoreFrame(frame)
    local state = frame and snapshots[frame]
    if not state then return end
    if ButtonDrawerOwns(frame) then return false end
    RestoreFrameBasics(frame, state)
    RestoreFramePoints(frame, state)
    RestoreFrameAppearance(frame, state)
    snapshots[frame] = nil
    return true
end

local function RebaseEditModeGeometry(frame)
    local state = frame and snapshots[frame]
    if not state then return end
    local ok
    ok, state.parent = ReadMethod(frame, "GetParent")
    state.hasParent = ok
    ok, state.width, state.height = ReadMethod(frame, "GetSize")
    state.hasSize = ok
    ok, state.scale = ReadMethod(frame, "GetScale")
    state.hasScale = ok
    ok, state.ignoreParentScale = ReadMethod(frame, "GetIgnoreParentScale")
    state.hasIgnoreParentScale = ok
    state.points = CapturePoints(frame)
    state.touched.parent = nil
    state.touched.size = nil
    state.touched.scale = nil
    state.touched.ignoreParentScale = nil
    state.touched.points = nil
    state.applied.parent = nil
    state.applied.size = nil
    state.applied.scale = nil
    state.applied.ignoreParentScale = nil
    state.applied.points = nil
end

local function RebaseNativeEditModeGeometry()
    local cluster = _G.MinimapCluster
    local container = cluster and cluster.MinimapContainer
    RebaseEditModeGeometry(cluster)
    RebaseEditModeGeometry(container)
    RebaseEditModeGeometry(_G.Minimap)
    RebaseEditModeGeometry(_G.MinimapBackdrop)
end

local function RestoreEditModeMouse()
    local cluster = _G.MinimapCluster
    local state = cluster and snapshots[cluster]
    if not state or state.touched.mouseEnabled ~= true or state.hasMouseEnabled ~= true then
        return true
    end
    if not FieldStillOwned(cluster, state, "mouseEnabled") then return false end
    if not RestoreStateWrite(cluster, state, "EnableMouse", state.mouseEnabled) then return false end
    state.touched.mouseEnabled = nil
    state.applied.mouseEnabled = nil
    return true
end

local function RestoreShapeWrapper()
    if not shapeInstalled then return end
    if _G.GetMinimapShape == MinimapModule.shapeWrapper then
        RecordShadowComparison(true)
        _G.GetMinimapShape = shapeOriginal
    else
        RecordShadowComparison(false)
    end
    shapeInstalled = false
    shapeOriginal = nil
end

local function RestoreAllFrames()
    local retained = setmetatable({}, { __mode = "k" })
    for frame, state in pairs(snapshots) do
        if ButtonDrawerOwns(frame) then retained[frame] = state else RestoreFrameBasics(frame, state) end
    end
    for frame, state in pairs(snapshots) do
        if not retained[frame] then RestoreFramePoints(frame, state) end
    end
    for frame, state in pairs(snapshots) do
        if not retained[frame] then RestoreFrameAppearance(frame, state) end
    end
    snapshots = retained

    RestoreShapeWrapper()
    MinimapModule:RestoreBlobRingScalars()
    if maskTouched and _G.Minimap then
        local ownsMask = RecordShadowComparison(appliedMask ~= nil and maskOwnershipLost ~= true)
        if ownsMask and maskSetterIdentity and _G.Minimap.SetMaskTexture ~= maskSetterIdentity then
            MinimapModule.restoreFailures = MinimapModule.restoreFailures + 1
            IncrementSharedStat("restoreFailures", 1)
        elseif ownsMask then
            RestoreWrite(_G.Minimap, "SetMaskTexture", nativeMask or NATIVE_MASK)
        end
    end
    maskTouched = false
    maskOwnershipLost = false
    appliedMask = nil
    nativeMask = nil
    nativeMaskCaptured = false
    maskSetterIdentity = nil
    if MinimapModule.difficultyText then MinimapModule.difficultyText:Hide() end
    if MinimapModule.coordinateText then MinimapModule.coordinateText:Hide() end
    MinimapModule.coordinateVisible = false
    MinimapModule.coordinateQX = nil
    MinimapModule.coordinateQY = nil
end

local function GetConfig()
    local db = YMap.GetDB and YMap:GetDB()
    return db and db.minimap or nil
end

local function GetSquareAppearance(config)
    return config and type(config.squareAppearance) == "table" and config.squareAppearance or nil
end

function MinimapModule:GetSquareCoordinates(config)
    local appearance = GetSquareAppearance(config)
    return appearance and type(appearance.coordinates) == "table" and appearance.coordinates or nil
end

local function GetNativeAppearance(config)
    return config and type(config.nativeAppearance) == "table"
        and config.nativeAppearance
        or NATIVE_APPEARANCE_DEFAULTS
end

local function GetNativeZoneHorizontalInset(zoneButton, borderTop)
    local state = CaptureFrame(zoneButton)
    local points = state and state.points or CapturePoints(zoneButton)
    for index = 1, type(points) == "table" and #points or 0 do
        local point = points[index]
        if point
            and point.point == "LEFT"
            and point.relative == borderTop
            and point.relativePoint == "LEFT"
        then
            return math_abs(point.x or 0)
        end
    end
    return 4
end

local function RefreshMinimapBorderAppearance(border)
    border = border or MinimapModule.border
    if not border then return end
    local config = GetConfig()
    if MinimapModule.active ~= true
        or MinimapModule.appliedStyle ~= "square"
        or not config
    then
        border:Hide()
        return
    end

    local minimap = _G.Minimap
    if minimap then
        if border:GetParent() ~= minimap then border:SetParent(minimap) end
        border:ClearAllPoints()
        border:SetAllPoints(minimap)
        local strataOK, strata = ReadMethod(minimap, "GetFrameStrata")
        if strataOK and strata then border:SetFrameStrata(strata) end
        local levelOK, level = ReadMethod(minimap, "GetFrameLevel")
        if levelOK and type(level) == "number" then border:SetFrameLevel(level + 50) end
    end

    local appearance = GetSquareAppearance(config)
    local color = appearance and type(appearance.borderColor) == "table" and appearance.borderColor or nil
    local red = Clamp(color and (color[1] or color.r), 0, 1, DEFAULT_BORDER_RED)
    local green = Clamp(color and (color[2] or color.g), 0, 1, DEFAULT_BORDER_GREEN)
    local blue = Clamp(color and (color[3] or color.b), 0, 1, DEFAULT_BORDER_BLUE)
    local alpha = Clamp(color and (color[4] or color.a), 0, 1, DEFAULT_BORDER_ALPHA)
    if GUI2 and GUI2.SetBorderColor then
        GUI2:SetBorderColor(border, red, green, blue, alpha)
    end

    local width = Clamp(appearance and appearance.borderWidth, 0, 8, 1)
    local borders = border.gui2Borders
    if borders then
        local size = GUI2 and GUI2.GetPixelSize and GUI2:GetPixelSize(border, width, 1) or width
        borders.top:SetHeight(size)
        borders.bottom:SetHeight(size)
        borders.left:SetWidth(size)
        borders.right:SetWidth(size)
        if width > 0 then
            borders.top:Show()
            borders.bottom:Show()
            borders.left:Show()
            borders.right:Show()
        else
            borders.top:Hide()
            borders.bottom:Hide()
            borders.left:Hide()
            borders.right:Hide()
        end
    end
    border:Show()
end

local function DetectConflict()
    if (not YUI.IsForever and YUI.IsRetail == false) then return "unsupported-client" end
    local external = YUI.API and YUI.API.External
    if external and type(external.ResolveCapability) == "function" then
        local ok, snapshot = pcall(
            external.ResolveCapability,
            external,
            "ui.minimap.controller"
        )
        if ok and type(snapshot) == "table" and snapshot.status == "active" then
            return "ExternalMinimap", snapshot.controller, snapshot
        end
    end
    local cluster = _G.MinimapCluster
    local minimap = _G.Minimap
    local expectedParent = cluster and cluster.MinimapContainer
    if expectedParent and minimap then
        local ok, parent = ReadMethod(minimap, "GetParent")
        if ok and parent ~= expectedParent then return "MinimapParent" end
    end

    local shape = _G.GetMinimapShape
    if type(shape) == "function" and shape ~= MinimapModule.shapeWrapper then
        return "GetMinimapShape"
    end
    return nil
end

local function CaptureNativeMetrics()
    if nativeMetrics.captured then return end
    nativeMetrics.captured = true
    local minimap = _G.Minimap
    local cluster = _G.MinimapCluster
    if not (minimap and cluster) then return end

    local widthOK, width = ReadMethod(minimap, "GetWidth")
    if widthOK and type(width) == "number" and width > 0 then nativeMetrics.mapWidth = width end

    local mapOK, mapX, mapY = ReadMethod(minimap, "GetCenter")
    local clusterOK, clusterX, clusterY = ReadMethod(cluster, "GetCenter")
    if mapOK and clusterOK and mapX and mapY and clusterX and clusterY then
        local scaleOK, effectiveScale = ReadMethod(cluster, "GetEffectiveScale")
        local parentScaleOK, parentScale = ReadMethod(_G.UIParent, "GetEffectiveScale")
        local relativeScale = scaleOK and parentScaleOK and parentScale ~= 0 and effectiveScale / parentScale or 1
        if relativeScale == 0 then relativeScale = 1 end
        local offsetX = (mapX - clusterX) / relativeScale
        local offsetY = (mapY - clusterY) / relativeScale
        if math_abs(offsetX) < 100 and math_abs(offsetY) < 100 then
            nativeMetrics.mapOffsetX = offsetX
            nativeMetrics.mapOffsetY = offsetY
        end
    end
end

local function PickPoint(centerX, centerY, screenWidth, screenHeight)
    local horizontal = ""
    local vertical = ""
    if centerX < screenWidth * 0.33 then
        horizontal = "LEFT"
    elseif centerX > screenWidth * 0.67 then
        horizontal = "RIGHT"
    end
    if centerY < screenHeight * 0.33 then
        vertical = "BOTTOM"
    elseif centerY > screenHeight * 0.67 then
        vertical = "TOP"
    end
    if vertical ~= "" and horizontal ~= "" then return vertical .. horizontal end
    if vertical ~= "" then return vertical end
    if horizontal ~= "" then return horizontal end
    return "CENTER"
end

local function PointCoordinates(left, bottom, width, height, point)
    local x = left + width * 0.5
    local y = bottom + height * 0.5
    if point:find("LEFT", 1, true) then x = left elseif point:find("RIGHT", 1, true) then x = left + width end
    if point:find("BOTTOM", 1, true) then y = bottom elseif point:find("TOP", 1, true) then y = bottom + height end
    return x, y
end

local function CaptureInitialPlacement(holder)
    local screenWidth = _G.UIParent and _G.UIParent:GetWidth() or 0
    local screenHeight = _G.UIParent and _G.UIParent:GetHeight() or 0
    local centerOK, centerX, centerY = ReadMethod(_G.Minimap, "GetCenter")
    local holderWidth = type(holder) == "number" and holder or holder:GetWidth() or 175
    local holderHeight = type(holder) == "number" and holder or holder:GetHeight() or holderWidth
    if not centerOK or not centerX or not centerY or screenWidth <= 0 or screenHeight <= 0 then
        return {
            version = 2,
            anchor = { point = "TOPRIGHT", relative = "UIParent", relativePoint = "TOPRIGHT" },
            offset = { x = -20, y = -20 },
        }
    end

    local point = PickPoint(centerX, centerY, screenWidth, screenHeight)
    local holderLeft = centerX - holderWidth * 0.5
    local holderBottom = centerY - holderHeight * 0.5
    local frameX, frameY = PointCoordinates(holderLeft, holderBottom, holderWidth, holderHeight, point)
    local parentX, parentY = PointCoordinates(0, 0, screenWidth, screenHeight, point)
    return {
        version = 2,
        anchor = { point = point, relative = "UIParent", relativePoint = point },
        offset = { x = Round(frameX - parentX), y = Round(frameY - parentY) },
    }
end

local function ApplyPlacementDirect(frame, placement)
    local anchor = placement.anchor
    frame:ClearAllPoints()
    frame:SetPoint(anchor.point, _G.UIParent, anchor.relativePoint, placement.offset.x, placement.offset.y)
end

local function GetMinimapMoverBounds()
    local anchor = MinimapModule.placementAnchor
    local size = anchor and anchor.GetWidth and anchor:GetWidth() or 175
    local progressBars = YMap.ProgressBars
    if progressBars and type(progressBars.GetMoverBounds) == "function" then
        return progressBars:GetMoverBounds(size)
    end
    return size, size, 0, 0
end

local function EnsureHolder(config)
    local size = Clamp(config.size, 120, 400, 175)

    if not MinimapModule.placementAnchor then
        if not (GUI2 and GUI2.CreateFrame and GUI2.CreateBorder) then return false end
        local placementAnchor = GUI2:CreateFrame(_G.UIParent, {
            name = "YMapMinimapPlacementAnchor",
            width = size,
            height = size,
            frameStrata = "LOW",
            frameLevel = 5,
            mouse = false,
            clampedToScreen = true,
        })
        local holder = GUI2:CreateFrame(_G.UIParent, {
            name = "YMapMinimapHolder",
            width = size,
            height = size,
            frameStrata = "LOW",
            frameLevel = 5,
            mouse = false,
        })
        holder:SetPoint("CENTER", placementAnchor, "CENTER", 0, 0)
        local border = GUI2:CreateFrame(_G.Minimap, {
            name = "YMapMinimapBorder",
            allPoints = true,
            frameStrata = "MEDIUM",
            frameLevel = 50,
            mouse = false,
        })
        GUI2:CreateBorder(border, "color.border.default")
        border.RefreshTheme = function()
            RefreshMinimapBorderAppearance()
            if YMap.TextComponents then YMap.TextComponents:RefreshTheme() end
        end
        border.UpdatePixelScale = RefreshMinimapBorderAppearance
        border.UpdateGUI2PixelScale = RefreshMinimapBorderAppearance
        border:Hide()
        MinimapModule.placementAnchor = placementAnchor
        MinimapModule.holder = holder
        MinimapModule.border = border
        if GUI2.CreateText then
            local zoneLabel = GUI2:CreateText(border, "", "font.size.sm", "color.text.heading")
            zoneLabel:SetPoint("TOP", border, "TOP", 0, -5)
            zoneLabel:SetJustifyH("CENTER")
            zoneLabel:SetWordWrap(false)
            zoneLabel:Hide()
            MinimapModule.zoneLabel = zoneLabel

            local coordinateText = GUI2:CreateText(border, "", "font.size.sm", "color.text.primary")
            coordinateText:SetPoint("BOTTOM", border, "BOTTOM", 0, 5)
            coordinateText:SetJustifyH("CENTER")
            coordinateText:SetWordWrap(false)
            coordinateText:Hide()
            MinimapModule.coordinateText = coordinateText
        end
    end

    local placementAnchor = MinimapModule.placementAnchor
    local holder = MinimapModule.holder
    placementAnchor:SetSize(size, size)
    if not (YMap.ProgressBars and YMap.ProgressBars.active == true) then
        holder:ClearAllPoints()
        holder:SetPoint("CENTER", placementAnchor, "CENTER", 0, 0)
        holder:SetSize(size, size)
    end
    local placement = CaptureInitialPlacement(placementAnchor)
    if not MinimapModule.layoutRegistered then
        ApplyPlacementDirect(placementAnchor, placement)
        if YUI.Layout and YUI.Layout.RegisterFrame then
            local entry = YUI.Layout:RegisterFrame(LAYOUT_ID, {
                placementStorage = YMap.PlacementStorage,
                frame = placementAnchor,
                title = YMap:T("settings.section.minimap", "YMap 小地图"),
                defaultPlacement = placement,
                combatProtected = false,
                getMoverBounds = GetMinimapMoverBounds,
            })
            MinimapModule.layoutRegistered = entry and true or false
        end
    end
    placementAnchor:Show()
    holder:Show()
    return true
end

local function UnregisterLayout()
    if MinimapModule.layoutRegistered and YUI.Layout and YUI.Layout.UnregisterFrame then
        YUI.Layout:UnregisterFrame(LAYOUT_ID)
    end
    MinimapModule.layoutRegistered = false
end

local function GetBelowWidgetDefaultPlacement()
    return MinimapModule.belowWidgetDefaultPlacement or {
        version = 2,
        anchor = { point = "TOPRIGHT", relative = "UIParent", relativePoint = "TOPRIGHT" },
        offset = { x = -20, y = -220 },
    }
end

local function CaptureBelowWidgetDefaultPlacement(holder)
    local screenWidth = _G.UIParent and _G.UIParent:GetWidth() or 0
    local screenHeight = _G.UIParent and _G.UIParent:GetHeight() or 0
    local source = _G.UIWidgetBelowMinimapContainerFrame
    local centerOK, centerX, centerY = ReadMethod(source, "GetCenter")
    local shownOK, shown = ReadMethod(source, "IsShown")
    local widthOK, sourceWidth = ReadMethod(source, "GetWidth")
    local heightOK, sourceHeight = ReadMethod(source, "GetHeight")
    local centeredOnScreen = centerOK
        and screenWidth > 0
        and screenHeight > 0
        and math_abs(centerX - screenWidth * 0.5) < 1
        and math_abs(centerY - screenHeight * 0.5) < 1
    local sourceReady = centerOK
        and shownOK and shown == true
        and widthOK and (tonumber(sourceWidth) or 0) > 0
        and heightOK and (tonumber(sourceHeight) or 0) > 0
        and not centeredOnScreen
    if not sourceReady then
        source = MinimapModule.holder
        centerOK, centerX, centerY = ReadMethod(source, "GetCenter")
    end
    if source == MinimapModule.holder and centerOK then
        local mapHeight = MinimapModule.holder:GetHeight() or 175
        local holderHeight = holder:GetHeight() or 24
        centerY = centerY - mapHeight * 0.5 - holderHeight * 0.5 - 4
    end
    if not centerOK or not centerX or not centerY or screenWidth <= 0 or screenHeight <= 0 then
        return GetBelowWidgetDefaultPlacement()
    end
    return {
        version = 2,
        anchor = { point = "CENTER", relative = "UIParent", relativePoint = "CENTER" },
        offset = {
            x = Round(centerX - screenWidth * 0.5),
            y = Round(centerY - screenHeight * 0.5),
        },
    }
end

local function IsLegacyCenteredBelowWidgetPlacement(placement)
    local anchor = type(placement) == "table" and placement.anchor or nil
    local offset = type(placement) == "table" and placement.offset or nil
    return type(anchor) == "table"
        and anchor.relative == "UIParent"
        and anchor.point == "CENTER"
        and anchor.relativePoint == "CENTER"
        and math_abs(tonumber(offset and offset.x) or 0) < 1
        and math_abs(tonumber(offset and offset.y) or 0) < 1
end

local function MigrateBelowWidgetPlacement()
    local db = YMap:GetDB()
    if type(db) ~= "table" then return false end
    db.migrations = type(db.migrations) == "table" and db.migrations or {}
    if (tonumber(db.migrations.belowWidgetPlacement) or 0) >= BELOW_WIDGET_PLACEMENT_MIGRATION_VERSION then
        return false
    end

    local layout = YUI.Layout
    if not (layout and type(layout.GetPlacement) == "function" and type(layout.SetPlacement) == "function") then
        return false
    end
    local placement = layout:GetPlacement(BELOW_WIDGET_LAYOUT_ID)
    if not placement then return false end
    if IsLegacyCenteredBelowWidgetPlacement(placement) then
        local recovery = GetBelowWidgetDefaultPlacement()
        if IsLegacyCenteredBelowWidgetPlacement(recovery)
            or layout:SetPlacement(BELOW_WIDGET_LAYOUT_ID, recovery, true) ~= true
        then
            return false
        end
    end
    db.migrations.belowWidgetPlacement = BELOW_WIDGET_PLACEMENT_MIGRATION_VERSION
    return true
end

local function ApplyBelowWidgetPlacementDirect(holder, placement)
    if not holder then return false end
    placement = placement or GetBelowWidgetDefaultPlacement()
    local anchor = placement.anchor
    local relative = _G[anchor.relative] or _G.UIParent
    holder:ClearAllPoints()
    holder:SetPoint(anchor.point, relative, anchor.relativePoint, placement.offset.x, placement.offset.y)
    return true
end

local function GetBelowWidgetMoverBounds()
    local holder = MinimapModule.belowWidgetHolder
    local width = holder and holder.GetWidth and holder:GetWidth() or 120
    local height = holder and holder.GetHeight and holder:GetHeight() or 24
    return math_max(tonumber(width) or 120, 24), math_max(tonumber(height) or 24, 16), 0, 0
end

local function OpenBelowWidgetSettings()
    if type(YMap.OpenSettings) == "function" then
        return YMap:OpenSettings()
    end
    return false
end

local function EnsureBelowWidgetHolder()
    local holder = MinimapModule.belowWidgetHolder
    if not holder then
        if not (GUI2 and GUI2.CreateFrame and _G.UIParent) then return nil end
        holder = GUI2:CreateFrame(_G.UIParent, {
            name = "YMapBelowMinimapWidgetHolder",
            width = 120,
            height = 24,
            frameStrata = "LOW",
            frameLevel = 4,
            mouse = false,
        })
        holder:EnableMouse(false)
        MinimapModule.belowWidgetDefaultPlacement = CaptureBelowWidgetDefaultPlacement(holder)
        ApplyBelowWidgetPlacementDirect(holder, MinimapModule.belowWidgetDefaultPlacement)
        MinimapModule.belowWidgetHolder = holder
    end

    if not MinimapModule.belowWidgetLayoutRegistered then
        local layout = YUI.Layout
        if layout and type(layout.RegisterFrame) == "function" then
            local entry = layout:RegisterFrame(BELOW_WIDGET_LAYOUT_ID, {
                placementStorage = YMap.PlacementStorage,
                frame = holder,
                title = YMap:T("layout.below_widget", "小地图下方工具"),
                category = "product",
                defaultPlacement = GetBelowWidgetDefaultPlacement,
                combatProtected = false,
                movable = true,
                snap = true,
                anchorTargets = { "UIParent", "YMapMinimapHolder" },
                minWidth = 24,
                minHeight = 16,
                getMoverBounds = GetBelowWidgetMoverBounds,
                openPluginSettings = OpenBelowWidgetSettings,
            })
            MinimapModule.belowWidgetLayoutRegistered = entry and true or false
            if MinimapModule.belowWidgetLayoutRegistered then
                MigrateBelowWidgetPlacement()
            end
        else
            ApplyBelowWidgetPlacementDirect(holder)
        end
    end
    holder:Show()
    return holder
end

local function ResolveBelowWidgetScale(widget, width)
    local widthOK, naturalWidth = ReadMethod(widget, "GetWidth")
    naturalWidth = widthOK and tonumber(naturalWidth) or nil
    if not naturalWidth or naturalWidth < 24 then return 1, nil end
    return Clamp(width / naturalWidth, 0.2, 2, 1), naturalWidth
end

local function SyncBelowWidgetHolder(widget, width, deferLayoutRefresh)
    local holder = EnsureBelowWidgetHolder()
    if not holder then return nil end

    width = Clamp(width, 120, 500, 200)
    local targetScale, naturalWidth = ResolveBelowWidgetScale(widget, width)
    local heightOK, height = ReadMethod(widget, "GetHeight")
    height = heightOK and tonumber(height) or nil
    local visualWidth = naturalWidth and naturalWidth * targetScale or width
    local visualHeight = math_max((height and height > 0 and height or 24) * targetScale, 16)
    EnsureScale(widget, targetScale)

    local changed = not NearlyEqual(holder:GetWidth(), visualWidth)
        or not NearlyEqual(holder:GetHeight(), visualHeight)
    if changed then holder:SetSize(visualWidth, visualHeight) end

    local layout = YUI.Layout
    if changed
        and deferLayoutRefresh ~= true
        and MinimapModule.belowWidgetLayoutRegistered
        and layout
        and type(layout.RefreshFrame) == "function"
    then
        layout:RefreshFrame(BELOW_WIDGET_LAYOUT_ID)
    end
    return holder
end

local function UnregisterBelowWidgetLayout()
    if MinimapModule.belowWidgetLayoutRegistered
        and YUI.Layout
        and type(YUI.Layout.UnregisterFrame) == "function"
    then
        YUI.Layout:UnregisterFrame(BELOW_WIDGET_LAYOUT_ID)
    end
    MinimapModule.belowWidgetLayoutRegistered = false
    if MinimapModule.belowWidgetHolder then MinimapModule.belowWidgetHolder:Hide() end
end

local function EnsureMask(mask, useNative)
    if not _G.Minimap then return false end
    if not nativeMaskCaptured then
        nativeMaskCaptured = true
        local ok, currentMask = ReadMethod(_G.Minimap, "GetMaskTexture")
        nativeMask = ok and currentMask or NATIVE_MASK
        maskSetterIdentity = _G.Minimap.SetMaskTexture
    end
    if useNative then mask = nativeMask or NATIVE_MASK end
    if appliedMask == mask then return true end
    maskTouched = true
    local ok = WriteMethod(_G.Minimap, "SetMaskTexture", mask)
    if ok then
        appliedMask = mask
        maskOwnershipLost = false
    end
    return ok
end

function MinimapModule.shapeWrapper()
    if MinimapModule.active == true and MinimapModule.appliedStyle == "square" then
        return "SQUARE"
    end
    if type(shapeOriginal) == "function" and shapeOriginal ~= MinimapModule.shapeWrapper then
        return shapeOriginal()
    end
    return "ROUND"
end

local function InstallShapeWrapper()
    if shapeInstalled and _G.GetMinimapShape == MinimapModule.shapeWrapper then return end
    shapeOriginal = _G.GetMinimapShape
    _G.GetMinimapShape = MinimapModule.shapeWrapper
    shapeInstalled = true
end

local function HookFrameMethod(frame, method, callback)
    if not IsUsableFrame(frame) or type(frame[method]) ~= "function" then return false end
    local methods = hookedFrames[frame]
    if not methods then
        methods = {}
        hookedFrames[frame] = methods
    end
    if methods[method] then return true end

    local ok
    if Security and Security.SafeHook then
        ok = Security.SafeHook("YMap.Minimap:" .. method, frame, method, callback)
    elseif _G.hooksecurefunc then
        ok = pcall(_G.hooksecurefunc, frame, method, callback)
    end
    if ok then methods[method] = true end
    return ok == true
end

local function ShouldReapplyNativeEditMode()
    if MinimapModule.active ~= true
        or MinimapModule.editModeActive ~= true
        or MinimapModule.applying == true
        or InCombat()
    then
        return false
    end
    local manager = _G.EditModeManagerFrame
    if not manager or type(manager.IsEditModeActive) ~= "function" then return false end
    local ok, active = pcall(manager.IsEditModeActive, manager)
    return ok and active == true
end

local function OnNativeMinimapSystemUpdated()
    if not ShouldReapplyNativeEditMode() then return end
    RebaseNativeEditModeGeometry()
    ReapplyYUIEditModeGeometry()
end

local function EnsureNativeMinimapSystemHook()
    local cluster = _G.MinimapCluster
    if not cluster then return false end
    return HookFrameMethod(cluster, "UpdateSystem", OnNativeMinimapSystemUpdated)
end

local function OnNativeEditModeSystemsUpdated()
    if not ShouldReapplyNativeEditMode() then return end
    ReapplyYUIEditModeGeometry()
end

local function OnNativeEditModeLayoutUpdated()
    if not ShouldReapplyNativeEditMode() then return end
    ReapplyYUIEditModeGeometry()
end

local function EnsureNativeEditModeLayoutHook()
    EnsureNativeMinimapSystemHook()
    local manager = _G.EditModeManagerFrame
    if not manager then return false end
    local ok = HookFrameMethod(manager, "UpdateSystems", OnNativeEditModeSystemsUpdated)
    ok = HookFrameMethod(manager, "UpdateLayoutInfo", OnNativeEditModeLayoutUpdated) and ok
    return ok
end

local function HookFrameScript(frame, script, callback)
    if not IsUsableFrame(frame) or type(frame.HookScript) ~= "function" then return false end
    local scripts = hookedScripts[frame]
    if not scripts then
        scripts = {}
        hookedScripts[frame] = scripts
    end
    if scripts[script] then return true end

    local ok = pcall(frame.HookScript, frame, script, callback)
    if ok then scripts[script] = true end
    return ok == true
end

RestoreStateWrite = function(frame, state, method, ...)
    local expected = state and state.methods and state.methods[method]
    if expected and frame and frame[method] ~= expected then
        MinimapModule.restoreFailures = MinimapModule.restoreFailures + 1
        IncrementSharedStat("restoreFailures", 1)
        return false
    end
    return RestoreWrite(frame, method, ...)
end

local function OnMutationRefresh(_, reason)
    mutationScheduled = false
    if MinimapModule.active ~= true or MinimapModule.pendingRefresh ~= true then return end
    if baseGeometryMutationPending and InCombat() and RepairBaseGeometryInCombat then
        if RepairBaseGeometryInCombat() then baseGeometryMutationPending = false end
    elseif not InCombat() then
        baseGeometryMutationPending = false
    end
    MinimapModule:Refresh(reason or "native-layout")
end

local function OnYUILayoutEditModeOpened()
    if MinimapModule.active ~= true then return end
    local config = GetConfig()
    local belowConfig = config and type(config.belowWidget) == "table" and config.belowWidget or nil
    local width = Clamp(belowConfig and belowConfig.width, 120, 500, 200)
    local holder = EnsureBelowWidgetHolder()
    local widget = _G.UIWidgetBelowMinimapContainerFrame
    if holder and widget then
        local wasApplying = MinimapModule.applying
        MinimapModule.applying = true
        EnsurePoint(widget, "TOP", holder, "TOP", 0, 0)
        SyncBelowWidgetHolder(widget, width, true)
        MinimapModule.applying = wasApplying
    end
    local layout = YUI.Layout
    if holder and layout and type(layout.RefreshFrame) == "function" then
        layout:RefreshFrame(BELOW_WIDGET_LAYOUT_ID)
    end
end

local function AttachMutationQueue()
    if not (Event and type(Event.On) == "function") then return false end
    if type(Event.OffOwner) == "function" then Event:OffOwner(mutationOwner) end
    Event:On(MUTATION_EVENT, OnMutationRefresh, mutationOwner, {
        throttle = 0.05,
        moduleId = "ymap.minimap",
    })
    Event:On("YUI_LAYOUT_EDIT_MODE_OPENED", OnYUILayoutEditModeOpened, mutationOwner, {
        moduleId = "ymap.minimap",
    })
    return true
end

local function DetachMutationQueue()
    mutationScheduled = false
    baseGeometryMutationPending = false
    if Event and type(Event.OffOwner) == "function" then
        Event:OffOwner(mutationOwner)
    end
end

local function QueueMutationRefresh(reason, baseGeometry)
    if baseGeometry == true then baseGeometryMutationPending = true end
    if mutationScheduled then return end
    mutationScheduled = true
    MinimapModule.pendingRefresh = true
    SetSharedStat("pendingRefresh", true)
    if Event and type(Event.Emit) == "function" then
        Event:Emit(MUTATION_EVENT, reason)
    else
        OnMutationRefresh(nil, reason)
    end
end

local function OnStructureMutation()
    if MinimapModule.active ~= true or MinimapModule.applying == true or MinimapModule.editModeActive == true then return end
    QueueMutationRefresh("native-layout")
end

local function OnBaseGeometryMutation()
    if MinimapModule.active ~= true or MinimapModule.applying == true or MinimapModule.editModeActive == true then return end
    QueueMutationRefresh("native-layout", true)
end

local function OnHousingOverlayMutation()
    if MinimapModule.active ~= true
        or MinimapModule.appliedStyle ~= "square"
        or MinimapModule.applying == true
        or MinimapModule.editModeActive == true
    then
        return
    end

    local backdrop = _G.MinimapBackdrop
    local overlay = backdrop and backdrop.StaticOverlayTexture
    local state = overlay and snapshots[overlay]
    if state then
        local currentPoints = CapturePoints(overlay)
        if state.touched.points
            and currentPoints
            and not PointsMatch(currentPoints, state.applied.points)
        then
            state.points = currentPoints
        end
        if state.touched.texCoords
            and not TexCoordsMatchCurrent(overlay, state.applied.texCoords)
        then
            local currentTexCoords = CaptureTexCoords(overlay)
            if currentTexCoords then
                state.texCoords = currentTexCoords
                state.hasTexCoords = true
            end
        end
    end
    QueueMutationRefresh("housing-overlay")
end

local function OnMaskMutation()
    if MinimapModule.active ~= true or MinimapModule.applying == true then return end
    maskOwnershipLost = true
    appliedMask = nil
    QueueMutationRefresh("native-mask")
end

local function OnZoomShow(frame)
    if MinimapModule.active ~= true or MinimapModule.applying == true or MinimapModule.editModeActive == true then return end
    local config = GetConfig()
    if config and (MinimapModule.appliedStyle == "square" or config.hideZoomButtons == true) then
        MinimapModule.applying = true
        EnsureShown(frame, false)
        MinimapModule.applying = false
    end
end

local function GetTrackingConfig(config)
    config = config or GetConfig()
    local elements = config and type(config.squareElements) == "table" and config.squareElements or nil
    return elements and type(elements.tracking) == "table" and elements.tracking or SQUARE_ELEMENT_DEFAULTS.tracking
end

local function GetTrackingButton()
    local cluster = _G.MinimapCluster
    return cluster and cluster.Tracking and cluster.Tracking.Button or nil
end

do
    local TRACKING_HINT_CURSOR_GAP = 20
    -- The native hand cursor's visual center is right of its click hotspot.
    local TRACKING_HINT_CURSOR_CENTER_X = 12
    local function HideTrackingHint()
        local hint = MinimapModule.trackingHint
        local wasVisible = MinimapModule.trackingHintVisible
        MinimapModule.trackingHintVisible = false
        if hint then
            hint:SetScript("OnUpdate", nil)
            if wasVisible then hint:Hide() end
        end
        MinimapModule.trackingHintX = nil
        MinimapModule.trackingHintY = nil
    end

    local function TrackingHintOnHide()
        HideTrackingHint()
    end

    local function EnsureTrackingHint()
        if MinimapModule.trackingHint then return MinimapModule.trackingHint end
        if not (GUI2 and GUI2.CreateFrame and GUI2.CreateText and _G.UIParent
            and type(_G.GetCursorPosition) == "function") then return nil end

        local hint = GUI2:CreateFrame(_G.UIParent, {
            name = "YMapTrackingHint", width = 1, height = 20,
            frameStrata = "TOOLTIP", mouse = false, clampedToScreen = true,
        })
        local text = GUI2:CreateText(hint, "", 14, "color.state.success", "CENTER")
        local font, size = text:GetFont()
        text:SetFont(font, size, "OUTLINE")
        text:SetShadowColor(0, 0, 0, 1)
        text:SetShadowOffset(1, -1)
        text:SetWordWrap(false)
        text:SetPoint("CENTER", hint, "CENTER", 0, 0)
        hint:SetScript("OnHide", TrackingHintOnHide)
        hint:Hide()
        MinimapModule.trackingHint = hint
        MinimapModule.trackingHintText = text
        return hint
    end

    local function CanShowTrackingHint()
        if MinimapModule.trackingHintEligible ~= true
            or MinimapModule.active ~= true
            or MinimapModule.appliedStyle ~= "square"
            or MinimapModule.editModeActive == true
            or MinimapModule.rightClickHandlerActive ~= true
            or MinimapModule.rightClickHovered ~= true
            or MinimapModule.trackingHintDismissed == true
        then return false end
        local minimap = _G.Minimap
        if not minimap or not minimap:IsVisible() then return false end
        local button = GetTrackingButton()
        if not button or type(button.OpenMenu) ~= "function" then return false end
        local menu = button and button.menu
        return not (menu and menu:IsShown())
    end

    local function UpdateTrackingHintPosition(hint)
        local x, y = _G.GetCursorPosition()
        local scale = _G.UIParent:GetEffectiveScale()
        if type(x) ~= "number" or type(y) ~= "number" or scale <= 0 then return false end
        x = (x + TRACKING_HINT_CURSOR_CENTER_X) / scale
        y = y / scale - TRACKING_HINT_CURSOR_GAP
        if MinimapModule.trackingHintX ~= x or MinimapModule.trackingHintY ~= y then
            hint:SetPoint("TOP", _G.UIParent, "BOTTOMLEFT", x, y)
            MinimapModule.trackingHintX = x
            MinimapModule.trackingHintY = y
            MinimapModule.trackingHintPositionWrites = MinimapModule.trackingHintPositionWrites + 1
        end
        return true
    end

    local function TrackingHintOnUpdate(hint)
        if not CanShowTrackingHint() or not UpdateTrackingHintPosition(hint) then
            HideTrackingHint()
        end
    end

    local function SyncTrackingHint()
        local hint = MinimapModule.trackingHint
        if not hint or not CanShowTrackingHint() or not UpdateTrackingHintPosition(hint) then
            HideTrackingHint()
            return
        end
        if not MinimapModule.trackingHintVisible then
            MinimapModule.trackingHintVisible = true
            hint:SetScript("OnUpdate", TrackingHintOnUpdate)
            hint:Show()
        end
    end

    local function RefreshTrackingHint(config)
        local tracking = GetTrackingConfig(config)
        MinimapModule.trackingHintEligible = config and config.enabled ~= false
            and config.style ~= "native" and tracking.hidden == true
            and tracking.rightClickOpen ~= false and tracking.rightClickHint == true or false
        if MinimapModule.trackingHintEligible then
            local hint = EnsureTrackingHint()
            if hint then
                local text = MinimapModule.trackingHintText
                local label = YMap:T("minimap.tracking_right_click_hint", "右键追踪")
                if text:GetText() ~= label then
                    text:SetText(label)
                    hint:SetWidth(math_max(text:GetStringWidth() + 8, 8))
                end
            end
        end
        SyncTrackingHint()
    end

    local function OnRightClickHandlerEnter()
        MinimapModule.rightClickHovered = true
        MinimapModule.trackingHintDismissed = false
        SyncTrackingHint()
    end

    local function OnRightClickHandlerLeave()
        MinimapModule.rightClickHovered = false
        MinimapModule.trackingHintDismissed = false
        HideTrackingHint()
    end

    MinimapModule.HideTrackingHint = HideTrackingHint
    MinimapModule.RefreshTrackingHint = RefreshTrackingHint
    MinimapModule.OnRightClickHandlerEnter = OnRightClickHandlerEnter
    MinimapModule.OnRightClickHandlerLeave = OnRightClickHandlerLeave
end

local function CloseOwnedTrackingMenu()
    if MinimapModule.trackingMenuOwned ~= true then return end
    local trackingButton = GetTrackingButton()
    if trackingButton and type(trackingButton.CloseMenu) == "function" then
        ReadMethod(trackingButton, "CloseMenu")
    end
    MinimapModule.trackingMenuOwned = false
end

local function ReanchorHiddenTrackingMenu(trackingButton, trackingConfig)
    if not (trackingConfig and trackingConfig.hidden == true) then return true end
    local menu = trackingButton and trackingButton.menu
    if not (menu and type(menu.ClearAllPoints) == "function" and type(menu.SetPoint) == "function") then
        return false
    end

    local minimap = _G.Minimap
    local uiParent = _G.UIParent
    local centerOK, centerX = ReadMethod(minimap, "GetCenter")
    local widthOK, screenWidth = ReadMethod(uiParent, "GetWidth")
    local mapOnRight = not (centerOK and widthOK and centerX and screenWidth)
        or centerX >= screenWidth * 0.5
    local point = mapOnRight and "TOPRIGHT" or "TOPLEFT"
    local relativePoint = mapOnRight and "TOPLEFT" or "TOPRIGHT"
    local offsetX = mapOnRight and -4 or 4
    local ok = pcall(function()
        menu:ClearAllPoints()
        menu:SetPoint(point, minimap, relativePoint, offsetX, 0)
    end)
    return ok == true
end

local function OpenNativeTrackingMenu(config)
    MinimapModule.trackingMenuOpenAttempts = MinimapModule.trackingMenuOpenAttempts + 1
    local trackingButton = GetTrackingButton()
    if not (trackingButton and type(trackingButton.OpenMenu) == "function") then
        MinimapModule.trackingMenuOpenFailures = MinimapModule.trackingMenuOpenFailures + 1
        return false
    end

    local ok = ReadMethod(trackingButton, "OpenMenu")
    if not ok or not trackingButton.menu then
        MinimapModule.trackingMenuOpenFailures = MinimapModule.trackingMenuOpenFailures + 1
        return false
    end

    MinimapModule.trackingMenuOwned = true
    ReanchorHiddenTrackingMenu(trackingButton, GetTrackingConfig(config))
    MinimapModule.trackingMenuOpenSuccesses = MinimapModule.trackingMenuOpenSuccesses + 1
    return true
end

local function OnMinimapRightMouseDown(_, mouseButton)
    if mouseButton ~= "RightButton"
        or MinimapModule.active ~= true
        or MinimapModule.appliedStyle ~= "square"
        or MinimapModule.editModeActive == true
    then
        return
    end

    local config = GetConfig()
    local trackingConfig = GetTrackingConfig(config)
    if trackingConfig.rightClickOpen == false then return end
    MinimapModule.trackingHintDismissed = true
    MinimapModule.HideTrackingHint()
    OpenNativeTrackingMenu(config)
end

local function OnMinimapInputMouseWheel(_, delta)
    if MinimapModule.active ~= true
        or MinimapModule.appliedStyle ~= "square"
        or MinimapModule.editModeActive == true
    then
        return
    end

    local minimap = _G.Minimap
    if not (minimap and type(minimap.GetScript) == "function") then return end
    local ok, callback = pcall(minimap.GetScript, minimap, "OnMouseWheel")
    if ok and type(callback) == "function" then
        pcall(callback, minimap, delta)
    end
end

local function SetRightClickHandlerEnabled(enabled)
    local handler = MinimapModule.rightClickHandler
    enabled = enabled == true and MinimapModule.active == true
    if not enabled then MinimapModule.OnRightClickHandlerLeave() end
    if not handler then
        MinimapModule.rightClickHandlerActive = false
        if not enabled then CloseOwnedTrackingMenu() end
        return false
    end

    if enabled then
        local levelOK, minimapLevel = ReadMethod(_G.Minimap, "GetFrameLevel")
        if levelOK then
            local handlerLevelOK, handlerLevel = ReadMethod(handler, "GetFrameLevel")
            if not handlerLevelOK or handlerLevel ~= minimapLevel + 1 then
                WriteMethod(handler, "SetFrameLevel", minimapLevel + 1)
            end
        end
        WriteMethod(handler, "EnableMouse", true)
        if type(handler.EnableMouseWheel) == "function" then
            WriteMethod(handler, "EnableMouseWheel", true)
        end
        WriteMethod(handler, "Show")
    else
        WriteMethod(handler, "Hide")
        WriteMethod(handler, "EnableMouse", false)
        if type(handler.EnableMouseWheel) == "function" then
            WriteMethod(handler, "EnableMouseWheel", false)
        end
        CloseOwnedTrackingMenu()
    end
    MinimapModule.rightClickHandlerActive = enabled
    return true
end

local function EnsureRightClickHandler()
    if MinimapModule.rightClickHandler then return MinimapModule.rightClickHandler end
    local minimap = _G.Minimap
    if not (minimap and type(_G.CreateFrame) == "function") then return nil end

    local handler = _G.CreateFrame("Frame", "YMapMinimapClickHandler", minimap)
    if not handler then return nil end
    handler:SetAllPoints(minimap)
    if type(handler.SetPropagateMouseMotion) == "function" then
        handler:SetPropagateMouseMotion(true)
    end
    if type(handler.SetPassThroughButtons) == "function" then
        handler:SetPassThroughButtons("LeftButton", "MiddleButton", "Button4", "Button5")
    end
    handler:SetScript("OnMouseDown", OnMinimapRightMouseDown)
    handler:SetScript("OnEnter", MinimapModule.OnRightClickHandlerEnter)
    handler:SetScript("OnLeave", MinimapModule.OnRightClickHandlerLeave)
    handler:SetScript("OnHide", MinimapModule.OnRightClickHandlerLeave)
    if type(handler.EnableMouseWheel) == "function" then
        handler:SetScript("OnMouseWheel", OnMinimapInputMouseWheel)
        handler:EnableMouseWheel(false)
    end
    handler:EnableMouse(false)
    handler:Hide()
    MinimapModule.rightClickHandler = handler
    return handler
end

local function RefreshRightClickHandler(config, style)
    local trackingConfig = GetTrackingConfig(config)
    local enabled = MinimapModule.active == true
        and style == "square"
        and MinimapModule.editModeActive ~= true
        and trackingConfig.rightClickOpen ~= false
    if enabled then EnsureRightClickHandler() end
    local result = SetRightClickHandlerEnabled(enabled)
    MinimapModule.RefreshTrackingHint(config)
    return result
end

local function GetSquareZoneName()
    if type(_G.GetMinimapZoneText) == "function" then
        local ok, value = pcall(_G.GetMinimapZoneText)
        if ok and type(value) == "string" and value ~= "" then return value end
    end
    local zoneText = _G.MinimapZoneText
    if zoneText and type(zoneText.GetText) == "function" then
        local ok, value = pcall(zoneText.GetText, zoneText)
        if ok and type(value) == "string" and value ~= "" then return value end
    end
    if type(_G.GetZoneText) == "function" then
        local ok, value = pcall(_G.GetZoneText)
        if ok and type(value) == "string" and value ~= "" then return value end
    end
    return ""
end

local function RefreshSquareZoneLabel()
    local label = MinimapModule.zoneLabel
    if not label then return end
    local config = GetConfig()
    local appearance = GetSquareAppearance(config)
    local fontSize = Clamp(appearance and appearance.zoneNameFontSize, 8, 24, 11)
    local fontOK, font, currentSize, flags = ReadMethod(label, "GetFont")
    if fontOK and font and not NearlyEqual(currentSize, fontSize) then
        WriteMethod(label, "SetFont", font, fontSize, flags or "")
    end
    if appearance and YMap.TextComponents then
        YMap.TextComponents:Apply(label, appearance.zoneName, fontSize)
        YMap.TextComponents:Anchor(label, MinimapModule.border, appearance, "zoneName", MinimapModule)
    end
    local zoneNameMode = appearance and appearance.zoneNameMode or "hover"
    local visible = MinimapModule.active == true
        and MinimapModule.appliedStyle == "square"
        and MinimapModule.editModeActive ~= true
        and zoneNameMode ~= "never"
        and (zoneNameMode == "always" or MinimapModule.minimapHovered == true)
    if not visible then
        label:Hide()
        return
    end
    label:SetText(GetSquareZoneName())
    label:Show()
end

local function SquareClockShouldShow(appearance)
    local mode = appearance and appearance.clockMode or "never"
    return mode == "always"
        or (mode == "hover" and MinimapModule.minimapHovered == true)
end

function MinimapModule.RefreshSquareClockHitRect()
    local style = MinimapModule.clockTextStyle
    local clock, text = _G.TimeManagerClockButton, _G.TimeManagerClockTicker
    if not style or not clock or not text or not MinimapModule.active
        or MinimapModule.appliedStyle ~= "square" or not clock:IsShown()
        or (style.fontSize == 0 and style.font == "inherit") then return end
    local _, size = text:GetFont()
    local width = text.GetStringWidth and text:GetStringWidth() or clock:GetWidth()
    EnsureSize(clock, math.ceil(width + 8), (size or 13) + 6)
end

local function RefreshSquareClockVisibility()
    if MinimapModule.active ~= true
        or MinimapModule.appliedStyle ~= "square"
        or MinimapModule.editModeActive == true
    then
        return
    end
    local clock = _G.TimeManagerClockButton
    if not clock then return end
    MinimapModule.applying = true
    EnsureShown(clock, SquareClockShouldShow(GetSquareAppearance(GetConfig())))
    MinimapModule.applying = false
end

function MinimapModule:HideCoordinates()
    local text = MinimapModule.coordinateText
    if text and MinimapModule.coordinateVisible then text:Hide() end
    MinimapModule.coordinateVisible = false
    MinimapModule.coordinateQX = nil
    MinimapModule.coordinateQY = nil
end

function MinimapModule:QuantizeCoordinate(value)
    if type(value) ~= "number" then return nil end
    value = math_min(1, math_max(0, value))
    return math_floor(value * 1000 + 0.5)
end

function MinimapModule:IsCoordinateDisplayActive(config, style)
    local coordinates = self:GetSquareCoordinates(config)
    local minimap = _G.Minimap
    if not coordinates
        or coordinates.enabled ~= true
        or MinimapModule.active ~= true
        or style ~= "square"
        or MinimapModule.editModeActive == true
        or not minimap
        or not minimap.IsShown
        or minimap:IsShown() ~= true
    then
        return false
    end
    return coordinates.displayMode ~= "hover" or MinimapModule.minimapHovered == true
end

function MinimapModule.UpdateMinimapCoordinates()
    local config = GetConfig()
    if not MinimapModule:IsCoordinateDisplayActive(config, MinimapModule.appliedStyle) then
        MinimapModule:HideCoordinates()
        return
    end

    local text = MinimapModule.coordinateText
    local mapAPI = _G.C_Map
    if not text or not mapAPI or type(mapAPI.GetBestMapForUnit) ~= "function"
        or type(mapAPI.GetPlayerMapPosition) ~= "function"
    then
        MinimapModule:HideCoordinates()
        return
    end

    local mapID = mapAPI.GetBestMapForUnit("player")
    if not mapID then
        MinimapModule:HideCoordinates()
        return
    end

    MinimapModule.coordinateReads = MinimapModule.coordinateReads + 1
    IncrementSharedStat("minimapCoordinateReads", 1)
    local position = mapAPI.GetPlayerMapPosition(mapID, "player")
    if not position then
        MinimapModule:HideCoordinates()
        return
    end

    local x, y
    if type(position.GetXY) == "function" then
        x, y = position:GetXY()
    else
        x, y = position.x, position.y
    end
    local qx = MinimapModule:QuantizeCoordinate(x)
    local qy = MinimapModule:QuantizeCoordinate(y)
    if not qx or not qy then
        MinimapModule:HideCoordinates()
        return
    end
    if MinimapModule.coordinateVisible
        and MinimapModule.coordinateQX == qx
        and MinimapModule.coordinateQY == qy
    then
        return
    end

    MinimapModule.coordinateQX = qx
    MinimapModule.coordinateQY = qy
    text:SetText(string.format("%.1f, %.1f", qx / 10, qy / 10))
    if not MinimapModule.coordinateVisible then text:Show() end
    MinimapModule.coordinateVisible = true
    MinimapModule.coordinateTextWrites = MinimapModule.coordinateTextWrites + 1
    IncrementSharedStat("minimapCoordinateTextWrites", 1)
end

function MinimapModule:GetSquareClockReservedHeight()
    local clock = _G.TimeManagerClockButton
    if clock and clock.GetHeight then
        local scale = clock.GetScale and clock:GetScale() or 1
        return math_max(13, clock:GetHeight() * scale) + 2
    end
    return 15
end

function MinimapModule:RefreshCoordinateLayout(config)
    local text = MinimapModule.coordinateText
    local appearance = GetSquareAppearance(config)
    local coordinates = self:GetSquareCoordinates(config)
    if not text or not appearance or not coordinates then return end

    local fontSize = Clamp(coordinates.fontSize, 8, 24, 11)
    local fontOK, font, currentSize, flags = ReadMethod(text, "GetFont")
    if fontOK and font and not NearlyEqual(currentSize, fontSize) then
        WriteMethod(text, "SetFont", font, fontSize, flags or "")
    end

    YMap.TextComponents:Apply(text, coordinates)
    YMap.TextComponents:Anchor(text, MinimapModule.border, appearance, "coordinates", self)
    text:SetHeight(fontSize + 2)
end

function MinimapModule:RefreshCoordinateConsumer(config, style)
    local driver = YMap.CoordinateDriver
    if not (driver and type(driver.RegisterMinimapConsumer) == "function"
        and type(driver.SetMinimapActive) == "function")
    then
        self:HideCoordinates()
        return false
    end
    if not MinimapModule.coordinateConsumerRegistered then
        self.coordinateConsumerRegistered = driver:RegisterMinimapConsumer(self.UpdateMinimapCoordinates) == true
    end
    if not self.coordinateConsumerRegistered then
        self:HideCoordinates()
        return false
    end

    self:RefreshCoordinateLayout(config)
    if YMap.MetricsWidget then YMap.MetricsWidget:Refresh() end
    local active = self:IsCoordinateDisplayActive(config, style)
    driver:SetMinimapActive(active)
    if not active then self:HideCoordinates() end
    return active
end

function MinimapModule:StopCoordinateConsumer()
    if YMap.MetricsWidget then YMap.MetricsWidget:Stop() end
    local driver = YMap.CoordinateDriver
    if driver and type(driver.SetMinimapActive) == "function" then
        driver:SetMinimapActive(false)
    end
    self:HideCoordinates()
end

local function SetSquareZoneHover(hovered)
    if MinimapModule.active ~= true
        or MinimapModule.appliedStyle ~= "square"
        or MinimapModule.editModeActive == true
    then
        return
    end
    MinimapModule.minimapHovered = hovered == true
    RefreshSquareZoneLabel()
    RefreshSquareClockVisibility()
    MinimapModule:RefreshCoordinateConsumer(GetConfig(), MinimapModule.appliedStyle)
end

local function OnMinimapEnter()
    SetSquareZoneHover(true)
end

local function OnMinimapLeave()
    SetSquareZoneHover(false)
end

function MinimapModule.OnMinimapShow()
    if MinimapModule.active == true then
        MinimapModule:RefreshCoordinateConsumer(GetConfig(), MinimapModule.appliedStyle)
    end
end

function MinimapModule.OnMinimapHide()
    MinimapModule.OnRightClickHandlerLeave()
    MinimapModule.minimapHovered = false
    RefreshSquareZoneLabel()
    RefreshSquareClockVisibility()
    MinimapModule:StopCoordinateConsumer()
end

local function OnClockShow(frame)
    if MinimapModule.active ~= true
        or MinimapModule.applying == true
        or MinimapModule.editModeActive == true
    then
        return
    end
    local config = GetConfig()
    local appearance = MinimapModule.appliedStyle == "square"
        and GetSquareAppearance(config)
        or GetNativeAppearance(config)
    local shouldHide
    if MinimapModule.appliedStyle == "square" then
        shouldHide = not SquareClockShouldShow(appearance)
    else
        shouldHide = appearance and appearance.hideClock == true
    end
    if not shouldHide then return end
    MinimapModule.applying = true
    EnsureShown(frame, false)
    MinimapModule.applying = false
end

local function OnCalendarShow(frame)
    if MinimapModule.active ~= true
        or MinimapModule.appliedStyle ~= "native"
        or MinimapModule.applying == true
        or MinimapModule.editModeActive == true
    then
        return
    end
    local appearance = GetNativeAppearance(GetConfig())
    if appearance.hideCalendar ~= true then return end
    MinimapModule.applying = true
    EnsureShown(frame, false)
    MinimapModule.applying = false
end

local function ApplyHousingOverlay(style)
    local backdrop = _G.MinimapBackdrop
    local overlay = backdrop and backdrop.StaticOverlayTexture
    if not overlay then return end
    if style ~= "square" then
        RestoreFrame(overlay)
        return
    end

    local minimap = _G.Minimap
    housingOverlayPoints[1].relative = minimap
    housingOverlayPoints[2].relative = minimap
    EnsurePoints(overlay, housingOverlayPoints)
    EnsureTexCoords(overlay, housingOverlayTexCoords)
end

local function InstallHooks()
    local cluster = _G.MinimapCluster
    local container = cluster and cluster.MinimapContainer
    local minimap = _G.Minimap
    if not (cluster and container and minimap) then return false end

    HookFrameMethod(cluster, "SetPoint", OnBaseGeometryMutation)
    HookFrameMethod(cluster, "SetSize", OnBaseGeometryMutation)
    HookFrameMethod(cluster, "SetScale", OnBaseGeometryMutation)
    HookFrameMethod(cluster, "SetEditModeScale", OnBaseGeometryMutation)
    if YUI.IsForever then
        HookFrameMethod(cluster.DielFrame, "SetPoint", OnStructureMutation)
        HookFrameMethod(cluster.DielFrame, "SetScale", OnStructureMutation)
        HookFrameMethod(cluster.DielFrame, "Show", OnStructureMutation)
        HookFrameMethod(container.PlayerCoords, "Show", OnStructureMutation)
    end
    HookFrameMethod(cluster, "SetHeaderUnderneath", OnBaseGeometryMutation)
    EnsureNativeMinimapSystemHook()
    HookFrameMethod(container, "SetPoint", OnBaseGeometryMutation)
    HookFrameMethod(container, "SetSize", OnBaseGeometryMutation)
    HookFrameMethod(container, "SetScale", OnBaseGeometryMutation)
    HookFrameMethod(minimap, "SetPoint", OnBaseGeometryMutation)
    HookFrameMethod(minimap, "SetSize", OnBaseGeometryMutation)
    HookFrameMethod(minimap, "SetFrameLevel", OnStructureMutation)
    HookFrameMethod(minimap, "SetFrameStrata", OnStructureMutation)
    HookFrameMethod(minimap, "SetMaskTexture", OnMaskMutation)
    HookFrameScript(minimap, "OnEnter", OnMinimapEnter)
    HookFrameScript(minimap, "OnLeave", OnMinimapLeave)
    HookFrameScript(minimap, "OnShow", MinimapModule.OnMinimapShow)
    HookFrameScript(minimap, "OnHide", MinimapModule.OnMinimapHide)
    HookFrameMethod(minimap, "UpdateStaticOverlayTexture", OnHousingOverlayMutation)

    local zoneButton = cluster.ZoneTextButton
    local zoneText = zoneButton and (zoneButton.ZoneText or _G.MinimapZoneText)
    local indicator = cluster.IndicatorFrame
    local difficulty = cluster.InstanceDifficulty
    local tracking = cluster.Tracking
    local mail = indicator and indicator.MailFrame
    local crafting = indicator and indicator.CraftingOrderFrame
    local gameTime = _G.GameTimeFrame
    local expansion = _G.ExpansionLandingPageMinimapButton
    local garrison = _G.GarrisonLandingPageMinimapButton
    HookFrameMethod(zoneButton, "SetPoint", OnStructureMutation)
    HookFrameMethod(zoneButton, "SetSize", OnStructureMutation)
    HookFrameMethod(zoneButton, "SetWidth", OnStructureMutation)
    HookFrameMethod(zoneText, "SetJustifyH", OnStructureMutation)
    HookFrameMethod(zoneText, "SetFont", OnStructureMutation)
    HookFrameMethod(indicator, "SetPoint", OnStructureMutation)
    HookFrameMethod(difficulty, "SetPoint", OnStructureMutation)
    HookFrameMethod(difficulty, "SetSize", OnStructureMutation)
    HookFrameMethod(difficulty, "SetScale", OnStructureMutation)
    HookFrameMethod(difficulty, "Update", OnStructureMutation)
    HookFrameMethod(tracking, "SetPoint", OnStructureMutation)
    HookFrameMethod(tracking, "SetScale", OnStructureMutation)
    HookFrameMethod(tracking, "EnableMouse", OnStructureMutation)
    HookFrameMethod(gameTime, "SetPoint", OnStructureMutation)
    HookFrameMethod(gameTime, "SetScale", OnStructureMutation)
    HookFrameMethod(gameTime, "EnableMouse", OnStructureMutation)
    HookFrameMethod(gameTime, "Show", OnCalendarShow)
    HookFrameMethod(mail, "SetPoint", OnStructureMutation)
    HookFrameMethod(mail, "SetScale", OnStructureMutation)
    HookFrameMethod(mail, "EnableMouse", OnStructureMutation)
    HookFrameMethod(crafting, "SetPoint", OnStructureMutation)
    HookFrameMethod(crafting, "SetScale", OnStructureMutation)
    HookFrameMethod(crafting, "EnableMouse", OnStructureMutation)
    HookFrameMethod(expansion, "SetPoint", OnStructureMutation)
    HookFrameMethod(expansion, "SetScale", OnStructureMutation)
    HookFrameMethod(expansion, "EnableMouse", OnStructureMutation)
    if garrison ~= expansion then
        HookFrameMethod(garrison, "SetPoint", OnStructureMutation)
        HookFrameMethod(garrison, "SetScale", OnStructureMutation)
        HookFrameMethod(garrison, "EnableMouse", OnStructureMutation)
    end

    HookFrameMethod(minimap.ZoomIn, "Show", OnZoomShow)
    HookFrameMethod(minimap.ZoomOut, "Show", OnZoomShow)
    HookFrameMethod(_G.TimeManagerClockButton, "SetParent", OnStructureMutation)
    HookFrameMethod(_G.TimeManagerClockButton, "SetPoint", OnStructureMutation)
    HookFrameMethod(_G.TimeManagerClockButton, "Show", OnClockShow)

    local queue = _G.QueueStatusButton
    HookFrameMethod(queue, "SetPoint", OnStructureMutation)
    HookFrameMethod(queue, "SetParent", OnStructureMutation)
    HookFrameMethod(queue, "SetScale", OnStructureMutation)
    HookFrameMethod(queue, "UpdatePosition", OnStructureMutation)

    local belowWidget = _G.UIWidgetBelowMinimapContainerFrame
    HookFrameMethod(belowWidget, "SetPoint", OnStructureMutation)
    HookFrameMethod(belowWidget, "SetScale", OnStructureMutation)
    HookFrameMethod(belowWidget, "SetSize", OnStructureMutation)
    HookFrameMethod(belowWidget, "SetWidth", OnStructureMutation)
    HookFrameMethod(belowWidget, "SetHeight", OnStructureMutation)

    if not indicatorFunctionHooked and type(_G.MiniMapIndicatorFrame_UpdatePosition) == "function" and _G.hooksecurefunc then
        local ok = pcall(_G.hooksecurefunc, "MiniMapIndicatorFrame_UpdatePosition", OnStructureMutation)
        if ok then indicatorFunctionHooked = true end
    end

    MinimapModule.hooksInstalled = true
    return true
end

local function ApplyBaseGeometry(config, style)
    local cluster = _G.MinimapCluster
    local container = cluster and cluster.MinimapContainer
    local minimap = _G.Minimap
    local placementAnchor = MinimapModule.placementAnchor
    if not (cluster and container and minimap and placementAnchor) then return false end

    CaptureNativeMetrics()
    local size = Clamp(config.size, 120, 400, 175)
    placementAnchor:SetSize(size, size)

    local applied = EnsureScale(container, 1)
    if style == "square" then
        applied = EnsureScale(cluster, 1) and applied
        applied = EnsureSize(cluster, size, size) and applied
        applied = EnsurePoint(cluster, "CENTER", placementAnchor, "CENTER", 0, 0) and applied
        applied = EnsureSize(container, size, size) and applied
        applied = EnsurePoint(container, "CENTER", cluster, "CENTER", 0, 0) and applied
        applied = EnsureSize(minimap, size, size) and applied
        applied = EnsurePoint(minimap, "CENTER", container, "CENTER", 0, 0) and applied

        local backdrop = _G.MinimapBackdrop
        if backdrop then
            applied = EnsureSize(backdrop, size, size) and applied
            applied = EnsurePoint(backdrop, "CENTER", minimap, "CENTER", 0, 0) and applied
        end
    else
        local nativeScale = size / nativeMetrics.mapWidth
        applied = EnsureScale(cluster, nativeScale) and applied
        applied = EnsurePoint(
            cluster,
            "CENTER",
            placementAnchor,
            "CENTER",
            -nativeMetrics.mapOffsetX,
            -nativeMetrics.mapOffsetY
        ) and applied
    end
    return applied
end

ReapplyYUIEditModeGeometry = function()
    if MinimapModule.active ~= true then return false end
    local config = GetConfig()
    if not config then return false end
    local style = MinimapModule.appliedStyle
    if style ~= "square" and style ~= "native" then
        style = config.style == "native" and "native" or "square"
    end

    local wasApplying = MinimapModule.applying
    MinimapModule.applying = true
    local callOK, applied, detail = pcall(function()
        local ok = ApplyBaseGeometry(config, style)
        local cluster = _G.MinimapCluster
        if cluster then EnsureMouse(cluster, false) end
        return ok
    end)
    MinimapModule.applying = wasApplying
    if not callOK then
        MinimapModule.lastError = detail
        return false
    end
    if applied ~= true then
        MinimapModule.lastError = detail or "ymap-edit-mode-geometry"
        return false
    end
    return true
end

local function ApplyBaseOwnership(config, style)
    if not ApplyBaseGeometry(config, style) then return false end
    if style == "square" then
        ApplyHousingOverlay(style)
        EnsureMask(SQUARE_MASK)
        MinimapModule:ApplyBlobRingScalars(style)
        InstallShapeWrapper()
        RefreshMinimapBorderAppearance(MinimapModule.border)
    else
        ApplyHousingOverlay(style)
        EnsureMask(nil, true)
        MinimapModule:ApplyBlobRingScalars(style)
        RestoreShapeWrapper()
        if MinimapModule.border then MinimapModule.border:Hide() end
    end
    return true
end

local function FrameBlocksCombatGeometry(frame)
    if not IsUsableFrame(frame) or type(frame.IsProtected) ~= "function" then return true end
    local ok, protected = pcall(frame.IsProtected, frame)
    return not ok or protected == true
end

RepairBaseGeometryInCombat = function()
    if MinimapModule.active ~= true or MinimapModule.editModeActive == true or not InCombat() then return false end
    local config = GetConfig()
    local cluster = _G.MinimapCluster
    local container = cluster and cluster.MinimapContainer
    local minimap = _G.Minimap
    local placementAnchor = MinimapModule.placementAnchor
    local style = MinimapModule.appliedStyle
    if not config or (style ~= "square" and style ~= "native") then return false end
    if FrameBlocksCombatGeometry(cluster)
        or FrameBlocksCombatGeometry(container)
        or FrameBlocksCombatGeometry(placementAnchor)
        or (style == "square" and FrameBlocksCombatGeometry(minimap))
        or (style == "square" and _G.MinimapBackdrop and FrameBlocksCombatGeometry(_G.MinimapBackdrop))
    then
        return false
    end

    local wasApplying = MinimapModule.applying
    MinimapModule.applying = true
    local ok, repaired = pcall(ApplyBaseGeometry, config, style)
    MinimapModule.applying = wasApplying
    if not ok then
        MinimapModule.lastError = repaired
        MinimapModule.writeFailures = MinimapModule.writeFailures + 1
        return false
    end
    return repaired == true
end

local function ApplyZoneText(config, style)
    local cluster = _G.MinimapCluster
    local zoneButton = cluster and cluster.ZoneTextButton
    local borderTop = cluster and cluster.BorderTop
    local zoneText = zoneButton and (zoneButton.ZoneText or _G.MinimapZoneText)
    if not (zoneButton and zoneText) then
        if MinimapModule.zoneLabel then MinimapModule.zoneLabel:Hide() end
        return
    end

    if style ~= "square" then MinimapModule.minimapHovered = false end
    if style == "square" then
        EnsureAlpha(zoneButton, 0)
        EnsureMouse(zoneButton, false)
        RefreshSquareZoneLabel()
        return
    end

    if MinimapModule.zoneLabel then MinimapModule.zoneLabel:Hide() end
    local appearance = GetNativeAppearance(config)
    if config.zoneTextAlignment ~= "center" then
        RestoreFrame(zoneText)
        RestoreFrame(zoneButton)
    else
        if appearance.hideClock == true and borderTop then
            local inset = GetNativeZoneHorizontalInset(zoneButton, borderTop)
            local borderOK, borderWidth = ReadMethod(borderTop, "GetWidth")
            local buttonOK, _, buttonHeight = ReadMethod(zoneButton, "GetSize")
            if borderOK and buttonOK and type(borderWidth) == "number" and type(buttonHeight) == "number" then
                EnsureSize(zoneButton, math_max(1, borderWidth - (inset * 2)), buttonHeight)
            end
            EnsurePoint(zoneButton, "LEFT", borderTop, "LEFT", inset, 0)
        else
            RestoreFrame(zoneButton)
        end
        EnsureJustifyH(zoneText, "CENTER")
    end
    local fontSize = Clamp(appearance.zoneNameFontSize, 8, 24, 14)
    local fontOK, font, _, flags = ReadMethod(zoneText, "GetFont")
    if fontOK and font then
        EnsureFont(zoneText, font, fontSize, flags or "")
    end
end

local function GetSquareElementConfig(config, key)
    local defaults = SQUARE_ELEMENT_DEFAULTS[key]
    local elements = type(config.squareElements) == "table" and config.squareElements or nil
    local element = elements and type(elements[key]) == "table" and elements[key] or nil
    return element or defaults, defaults
end

local function ApplyElementVisibility(frame, hidden)
    local state = CaptureFrame(frame)
    if not state then return end
    local visible = hidden ~= true
    EnsureAlpha(frame, visible and (state.hasAlpha and state.alpha or 1) or 0)
    if state.hasMouseEnabled then
        EnsureMouse(frame, visible and state.mouseEnabled or false)
    end
end

local function ApplyTrackingMenuHost(tracking, hidden)
    local state = CaptureFrame(tracking)
    if not state then return end
    local button = tracking.Button

    if hidden == true then
        -- Retail dropdowns close when their owner becomes invisible, so park the host offscreen instead.
        EnsureSetShown(tracking, true)
        EnsurePoint(tracking, "TOP", _G.UIParent, "BOTTOM", 0, 0)
        if button then
            local buttonState = CaptureFrame(button)
            if buttonState then
                EnsureSetShown(button, true)
                if buttonState.hasMouseEnabled then EnsureMouse(button, false) end
            end
        end
    else
        if state.hasShown then EnsureSetShown(tracking, state.shown) end
        if button and snapshots[button] then RestoreFrame(button) end
    end
end

local function ApplySquareElement(frame, config, key)
    if not frame or ButtonDrawerOwns(frame) then return end
    local element, defaults = GetSquareElementConfig(config, key)
    local anchor = VALID_ANCHORS[element.anchor] and element.anchor or defaults.anchor
    local scale = Clamp(element.scale, 0.5, 2, defaults.scale)
    local offsetX = Clamp(element.offsetX, -100, 100, defaults.offsetX)
    local offsetY = Clamp(element.offsetY, -100, 100, defaults.offsetY)
    local pointX = (anchor == "TOPLEFT" or anchor == "BOTTOMLEFT") and -offsetX or offsetX
    local pointY = (anchor == "BOTTOMLEFT" or anchor == "BOTTOMRIGHT") and -offsetY or offsetY
    EnsureScale(frame, scale)
    EnsurePoint(frame, anchor, _G.Minimap, anchor, pointX, pointY)
    ApplyElementVisibility(frame, element.hidden, childButton)

    local levelOK, minimapLevel = ReadMethod(_G.Minimap, "GetFrameLevel")
    if levelOK then EnsureFrameLevel(frame, minimapLevel + 8) end
end

function MinimapModule:ApplyDifficultyTextStyle(text)
    if not text
        or type(text.GetFont) ~= "function"
        or type(text.SetFont) ~= "function"
        or type(text.SetShadowColor) ~= "function"
        or type(text.SetShadowOffset) ~= "function"
    then
        return false
    end
    local font, size = text:GetFont()
    if type(font) ~= "string" or font == "" or type(size) ~= "number" then
        return false
    end
    text:SetFont(font, size, "OUTLINE")
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    return true
end

local function EnsureDifficultyText(difficulty)
    if MinimapModule.difficultyText then return MinimapModule.difficultyText end
    if not (difficulty and GUI2 and GUI2.CreateText) then return nil end
    local text = GUI2:CreateText(difficulty, "", "font.size.md", "color.text.heading")
    MinimapModule:ApplyDifficultyTextStyle(text)
    text:SetWordWrap(false)
    text:Hide()
    MinimapModule.difficultyText = text
    MinimapModule.difficultyTextHorizontalPoint = nil
    return text
end

local function ApplyDifficultyTextAlignment(text, difficulty, anchor)
    if not (text and difficulty) then return end
    local horizontalPoint = (anchor == "TOPRIGHT" or anchor == "BOTTOMRIGHT") and "RIGHT" or "LEFT"
    if MinimapModule.difficultyTextHorizontalPoint == horizontalPoint then return end

    text:ClearAllPoints()
    text:SetPoint(horizontalPoint, difficulty, horizontalPoint, 0, 0)
    text:SetJustifyH(horizontalPoint)
    MinimapModule.difficultyTextHorizontalPoint = horizontalPoint
end

function MinimapModule:GetDifficultyStyleLabel(styleId, textStyle, tier, groupSize)
    textStyle = textStyle == "en" and "en" or "zh"
    local label = YMap:T("difficulty.short." .. textStyle .. "." .. styleId)
    if styleId == "world_tier" then
        local ok, value = pcall(string.format, label, tostring(tier or 8))
        return ok and value or label
    end

    local numericGroupSize = DIFFICULTY_GROUP_SIZE_STYLES[styleId] and tonumber(groupSize) or nil
    if numericGroupSize and numericGroupSize > 0 then
        return tostring(math_floor(numericGroupSize)) .. label
    end
    return label
end

local function GetDifficultyPresentation(config)
    if type(_G.GetInstanceInfo) ~= "function" then return nil end
    local _, instanceType, difficultyID, _, _, _, _, _, instanceGroupSize, _, hasWorldTier = _G.GetInstanceInfo()
    if not difficultyID or difficultyID == 0
        or instanceType == "none"
        or instanceType == "interior"
        or instanceType == "neighborhood"
    then
        return nil
    end

    local activeDelveTier, isActiveDelve
    if DelvesAPI and type(DelvesAPI.GetActiveTier) == "function" then
        activeDelveTier, isActiveDelve = DelvesAPI.GetActiveTier(difficultyID)
    end

    local difficultyName
    local styleId
    if isActiveDelve == true then
        if not activeDelveTier then return nil end
        styleId = "world_tier"
    else
        if type(_G.GetDifficultyInfo) ~= "function" then return nil end
        local isHeroic, isChallengeMode, displayHeroic, displayMythic, isLFR
        difficultyName, _, isHeroic, isChallengeMode, displayHeroic, displayMythic, _, isLFR =
            _G.GetDifficultyInfo(difficultyID)
        if not difficultyName then return nil end

        styleId = "normal"
        if hasWorldTier then
            styleId = "world_tier"
        end
        local lfgInfo = _G.C_LFGInfo
        local follower = false
        if lfgInfo and type(lfgInfo.IsInLFGFollowerDungeon) == "function" then
            local ok, value = pcall(lfgInfo.IsInLFGFollowerDungeon)
            follower = ok and value == true
        end
        if not hasWorldTier and follower then
            styleId = "follower"
        elseif not hasWorldTier and isChallengeMode then
            styleId = "keystone"
        elseif not hasWorldTier and displayMythic then
            styleId = "mythic"
        elseif not hasWorldTier and isLFR then
            styleId = "raid_finder"
        elseif not hasWorldTier and (isHeroic or displayHeroic) then
            styleId = "heroic"
        end
    end

    local style
    for index = 1, #MinimapModule.DIFFICULTY_PREVIEW_STYLES do
        local candidate = MinimapModule.DIFFICULTY_PREVIEW_STYLES[index]
        if candidate.id == styleId then
            style = candidate
            break
        end
    end
    if not style then return nil end

    local element = config and GetSquareElementConfig(config, "difficulty") or nil
    local textStyle = element and element.textStyle == "en" and "en" or "zh"
    local tier = activeDelveTier or (hasWorldTier and string.match(difficultyName, "%d+")) or nil
    local label = MinimapModule:GetDifficultyStyleLabel(styleId, textStyle, tier, instanceGroupSize)
    if isActiveDelve ~= true and hasWorldTier and not tier then label = difficultyName end
    return label, style.red, style.green, style.blue
end

local function ApplyDifficultyElement(config, difficulty)
    if not difficulty then return end
    local element, defaults = GetSquareElementConfig(config, "difficulty")
    local anchor = VALID_ANCHORS[element.anchor] and element.anchor or defaults.anchor
    local text = EnsureDifficultyText(difficulty)
    local label, red, green, blue = GetDifficultyPresentation(config)

    EnsureAlpha(difficulty.Default, 0)
    EnsureAlpha(difficulty.Guild, 0)
    EnsureAlpha(difficulty.ChallengeMode, 0)
    EnsureSize(difficulty, 44, 20)
    ApplySquareElement(difficulty, config, "difficulty")
    ApplyDifficultyTextAlignment(text, difficulty, anchor)

    local visible = element.hidden ~= true and label ~= nil
    ApplyElementVisibility(difficulty, not visible)
    if text then
        if visible then
            text:SetText(label)
            text:SetTextColor(red, green, blue, 1)
            text:Show()
        else
            text:Hide()
        end
    end
end

local function ApplyLandingPageSlot(frame, config, style)
    if not frame or ButtonDrawerOwns(frame) then return end
    if style == "square" then
        ApplySquareElement(frame, config, "expansion")
    else
        RestoreFrame(frame)
    end
end

local function ApplySquareSlots(config)
    local cluster = _G.MinimapCluster
    local minimap = _G.Minimap
    if not (cluster and minimap) then return end

    local compass = _G.MinimapCompassTexture
    local borderTop = cluster.BorderTop
    local difficulty = cluster.InstanceDifficulty
    local gameTime = _G.GameTimeFrame
    local clock = _G.TimeManagerClockButton
    local indicator = cluster.IndicatorFrame
    local mail = indicator and indicator.MailFrame
    local crafting = indicator and indicator.CraftingOrderFrame
    local tracking = cluster.Tracking
    EnsureAlpha(compass, 0)
    EnsureAlpha(borderTop, 0)
    EnsureAlpha(tracking and tracking.Background, 0)
    ApplyDifficultyElement(config, difficulty)
    ApplySquareElement(gameTime, config, "calendar")
    if YUI.IsForever then
        ApplySquareElement(cluster.DielFrame, config, "diel")
        -- Hide the native updater as well as its text; leave coordinate CVars intact.
        EnsureShown(cluster.MinimapContainer and cluster.MinimapContainer.PlayerCoords, false)
    end
    ApplySquareElement(mail, config, "mail")
    ApplySquareElement(crafting, config, "crafting")
    ApplySquareElement(tracking, config, "tracking")
    if tracking then
        local trackingConfig = GetSquareElementConfig(config, "tracking")
        ApplyTrackingMenuHost(tracking, trackingConfig.hidden)
    end
    ApplyLandingPageSlot(_G.ExpansionLandingPageMinimapButton, config, "square")
    if _G.GarrisonLandingPageMinimapButton ~= _G.ExpansionLandingPageMinimapButton then
        ApplyLandingPageSlot(_G.GarrisonLandingPageMinimapButton, config, "square")
    end
    if clock then
        local appearance = GetSquareAppearance(config)
        CaptureFrame(clock)
        EnsureParent(clock, minimap)
        local point, x, y = YMap.TextComponents:Placement(appearance, "clock", MinimapModule)
        EnsurePoint(clock, point, minimap, point, x, y)
        local text = _G.TimeManagerClockTicker
        local style = appearance.clock
        MinimapModule.clockTextStyle = style
        if not MinimapModule.clockTextHooked and hooksecurefunc and _G.TimeManagerClockButton_Update then
            hooksecurefunc("TimeManagerClockButton_Update", MinimapModule.RefreshSquareClockHitRect)
            MinimapModule.clockTextHooked = true
        end
        if text and style then
            YMap.TextComponents:Apply(text, style)
            if style.fontSize > 0 or style.font ~= "inherit" then
                local _, size = text:GetFont()
                local width = text.GetStringWidth and text:GetStringWidth() or clock:GetWidth()
                EnsureSize(clock, math.ceil(width + 8), (size or 13) + 6)
            else
                -- Returning to inherited size must release the prior custom hit rectangle.
                local captured = snapshots[clock]
                if captured and captured.hasSize then EnsureSize(clock, captured.width, captured.height) end
            end
        end
        HookFrameScript(clock, "OnEnter", OnMinimapEnter)
        HookFrameScript(clock, "OnLeave", OnMinimapLeave)
        EnsureShown(clock, SquareClockShouldShow(appearance))
    end
end

local function ApplyNativeAppearance(config)
    MinimapModule.clockTextStyle = nil
    if YMap.TextComponents then YMap.TextComponents:Restore(_G.TimeManagerClockTicker) end
    if YUI.IsForever then
        local container = _G.MinimapCluster and _G.MinimapCluster.MinimapContainer
        if container and container.PlayerCoords then RestoreFrame(container.PlayerCoords) end
        local diel = _G.MinimapCluster and _G.MinimapCluster.DielFrame
        local element = GetSquareElementConfig(config, "diel")
        if diel then
            if element.hidden == true then ApplyElementVisibility(diel, true)
            else RestoreFrame(diel) end
        end
    end
    local appearance = GetNativeAppearance(config)
    local clock = _G.TimeManagerClockButton
    local calendar = _G.GameTimeFrame

    if clock then
        if appearance.hideClock == true then
            EnsureShown(clock, false)
        else
            RestoreFrame(clock)
        end
    end
    if calendar then
        if appearance.hideCalendar == true then
            EnsureShown(calendar, false)
        else
            RestoreFrame(calendar)
        end
    end
end

local function ApplyNativeTracking(config)
    local cluster = _G.MinimapCluster
    local tracking = cluster and cluster.Tracking
    if not tracking or ButtonDrawerOwns(tracking) then return end
    local element = GetSquareElementConfig(config, "tracking")
    if element.hidden == true then
        ApplyElementVisibility(tracking, true)
        ApplyTrackingMenuHost(tracking, true)
    else
        RestoreFrame(tracking)
        local button = tracking.Button
        if button and snapshots[button] then RestoreFrame(button) end
    end
end

local ApplyQueue

local function GetSettingsPreviewFrame(key)
    if key == "queue" then return _G.QueueStatusButton end
    local cluster = _G.MinimapCluster
    if not cluster then return nil end
    if key == "expansion" then
        return _G.ExpansionLandingPageMinimapButton or _G.GarrisonLandingPageMinimapButton
    elseif key == "tracking" then
        return cluster.Tracking
    elseif key == "calendar" then
        return _G.GameTimeFrame
    elseif key == "diel" and YUI.IsForever then
        return cluster.DielFrame
    elseif key == "mail" then
        return cluster.IndicatorFrame and cluster.IndicatorFrame.MailFrame
    elseif key == "crafting" then
        return cluster.IndicatorFrame and cluster.IndicatorFrame.CraftingOrderFrame
    elseif key == "difficulty" then
        return cluster.InstanceDifficulty
    end
    return nil
end

local function CaptureSettingsPreviewState(frame, key)
    local state = {
        frame = frame,
        key = key,
        methods = {
            SetAlpha = frame.SetAlpha,
            Show = frame.Show,
            Hide = frame.Hide,
        },
    }
    local ok
    ok, state.alpha = ReadMethod(frame, "GetAlpha")
    state.hasAlpha = ok
    ok, state.shown = ReadMethod(frame, "IsShown")
    state.hasShown = ok

    if key == "difficulty" then
        local text = EnsureDifficultyText(frame)
        state.text = text
        if text then
            state.textMethods = {
                SetText = text.SetText,
                SetTextColor = text.SetTextColor,
                Show = text.Show,
                Hide = text.Hide,
            }
            ok, state.textShown = ReadMethod(text, "IsShown")
            state.hasTextShown = ok
            ok, state.textValue = ReadMethod(text, "GetText")
            state.hasTextValue = ok
            ok, state.textRed, state.textGreen, state.textBlue, state.textAlpha = ReadMethod(text, "GetTextColor")
            state.hasTextColor = ok
        end
    elseif key == "mail" then
        local visual = frame.MailIcon or _G.MiniMapMailIcon
        state.visual = visual
        if visual then
            state.visualMethods = {
                SetAlpha = visual.SetAlpha,
                Show = visual.Show,
                Hide = visual.Hide,
            }
            ok, state.visualAlpha = ReadMethod(visual, "GetAlpha")
            state.hasVisualAlpha = ok
            ok, state.visualShown = ReadMethod(visual, "IsShown")
            state.hasVisualShown = ok
        end
    end
    return state
end

function MinimapModule:ClearSettingsPreview()
    local state = self.settingsPreviewState
    self.settingsPreviewState = nil
    self.settingsPreviewKey = nil
    if not state then return true end

    local frame = state.frame
    if frame then
        if state.hasAlpha and frame.SetAlpha == state.methods.SetAlpha then
            WriteMethod(frame, "SetAlpha", state.alpha)
        end
        if state.hasShown then
            local method = state.shown and "Show" or "Hide"
            local identity = state.shown and state.methods.Show or state.methods.Hide
            if frame[method] == identity then WriteMethod(frame, method) end
        end
    end

    local text = state.text
    local methods = state.textMethods
    if text and methods then
        if state.hasTextValue and text.SetText == methods.SetText then
            WriteMethod(text, "SetText", state.textValue)
        end
        if state.hasTextColor and text.SetTextColor == methods.SetTextColor then
            WriteMethod(text, "SetTextColor", state.textRed, state.textGreen, state.textBlue, state.textAlpha)
        end
        if state.hasTextShown then
            local method = state.textShown and "Show" or "Hide"
            local identity = state.textShown and methods.Show or methods.Hide
            if text[method] == identity then WriteMethod(text, method) end
        end
    end

    local visual = state.visual
    local visualMethods = state.visualMethods
    if visual and visualMethods then
        if state.hasVisualAlpha and visual.SetAlpha == visualMethods.SetAlpha then
            WriteMethod(visual, "SetAlpha", state.visualAlpha)
        end
        if state.hasVisualShown then
            local method = state.visualShown and "Show" or "Hide"
            local identity = state.visualShown and visualMethods.Show or visualMethods.Hide
            if visual[method] == identity then WriteMethod(visual, method) end
        end
    end
    return true
end

function MinimapModule:SetSettingsPreview(key)
    self:ClearSettingsPreview()
    if key == nil then return true end
    if self.active ~= true or InCombat() then return false end

    local config = GetConfig()
    local element
    if key == "queue" then
        element = config and type(config.queue) == "table" and config.queue or nil
    else
        if self.appliedStyle ~= "square" or not SQUARE_ELEMENT_DEFAULTS[key] then return false end
        element = config and GetSquareElementConfig(config, key)
    end
    if not element or element.hidden == true then return false end
    if key == "queue" and element.customLayout == true and ApplyQueue then
        ApplyQueue(config)
    end

    local frame = GetSettingsPreviewFrame(key)
    if not frame or ButtonDrawerOwns(frame) then return false end
    local state = CaptureSettingsPreviewState(frame, key)
    self.settingsPreviewState = state
    self.settingsPreviewKey = key

    if state.hasAlpha then WriteMethod(frame, "SetAlpha", 1) end
    if state.hasShown then WriteMethod(frame, "Show") end
    if key == "queue" and element.customLayout == true and ApplyQueue then
        -- QueueStatusButton:OnShow() synchronously asks MicroMenuContainer to
        -- reposition it. Reapply after Show so the live preview owns the final point.
        ApplyQueue(config)
    end
    if key == "difficulty" and state.text then
        local label, red, green, blue = GetDifficultyPresentation(config)
        local fallbackStyle = element.textStyle == "en" and "en" or "zh"
        WriteMethod(
            state.text,
            "SetText",
            label or self:GetDifficultyStyleLabel("keystone", fallbackStyle)
        )
        WriteMethod(state.text, "SetTextColor", red or 0.72, green or 0.4, blue or 1, 1)
        WriteMethod(state.text, "Show")
    end
    if state.visual then
        if state.hasVisualAlpha then WriteMethod(state.visual, "SetAlpha", 1) end
        if state.hasVisualShown then WriteMethod(state.visual, "Show") end
    end
    return true
end

local function ApplyZoomButtons(config, style)
    local minimap = _G.Minimap
    if not minimap then return end
    if style == "square" or config.hideZoomButtons == true then
        EnsureShown(minimap.ZoomIn, false)
        EnsureShown(minimap.ZoomOut, false)
    else
        RestoreFrame(minimap.ZoomIn)
        RestoreFrame(minimap.ZoomOut)
    end
end

ApplyQueue = function(config)
    local queueConfig = type(config.queue) == "table" and config.queue or nil
    local queue = _G.QueueStatusButton
    if not queue then return end
    if not queueConfig or queueConfig.customLayout ~= true then
        RestoreFrame(queue)
        return
    end

    local anchor = VALID_ANCHORS[queueConfig.anchor] and queueConfig.anchor or "BOTTOMLEFT"
    local size = Clamp(queueConfig.size, 6, 64, 18)
    local offsetX = Clamp(queueConfig.offsetX, -200, 200, -5)
    local offsetY = Clamp(queueConfig.offsetY, -200, 200, -5)
    local pointX = (anchor == "TOPLEFT" or anchor == "BOTTOMLEFT") and -offsetX or offsetX
    local pointY = (anchor == "BOTTOMLEFT" or anchor == "BOTTOMRIGHT") and -offsetY or offsetY
    EnsureParent(queue, _G.Minimap)
    EnsureIgnoreParentScale(queue, true)
    -- Blizzard renders the eye artwork on a 44x44 texture inside a 45x45
    -- button. Scale the whole button tree so the visual icon equals the
    -- configured pixel size; the hit rect then matches within ~2%.
    EnsureScale(queue, size / 44)
    EnsurePoint(queue, anchor, _G.Minimap, anchor, pointX, pointY)
    local minimapLevelOK, minimapLevel = ReadMethod(_G.Minimap, "GetFrameLevel")
    if minimapLevelOK then EnsureFrameLevel(queue, minimapLevel + 10) end
end

local function ApplyBelowWidget(config)
    local belowConfig = type(config.belowWidget) == "table" and config.belowWidget or nil
    local width = Clamp(belowConfig and belowConfig.width, 120, 500, 200)
    local holder = EnsureBelowWidgetHolder()
    if not holder then return end
    local widget = _G.UIWidgetBelowMinimapContainerFrame
    if not widget then return end
    EnsurePoint(widget, "TOP", holder, "TOP", 0, 0)
    SyncBelowWidgetHolder(widget, width)
end

local function VerifyAppliedStyle(style)
    MinimapModule.shadowComparisons = MinimapModule.shadowComparisons + 1
    IncrementSharedStat("shadowComparisons", 1)
    local mismatch = false
    if style == "square" then
        mismatch = _G.GetMinimapShape ~= MinimapModule.shapeWrapper
    else
        mismatch = _G.GetMinimapShape == MinimapModule.shapeWrapper
    end
    if mismatch then
        MinimapModule.shadowMismatches = MinimapModule.shadowMismatches + 1
        IncrementSharedStat("shadowMismatches", 1)
    end
end

local function ApplyCurrent(config, style)
    local settingsPreviewKey = MinimapModule.settingsPreviewKey
    MinimapModule:ClearSettingsPreview()
    if MinimapModule.appliedStyle and MinimapModule.appliedStyle ~= style then
        RestoreAllFrames()
    end
    MinimapModule.appliedStyle = style
    InstallHooks()
    local size = Clamp(config.size, 120, 400, 175)
    if YMap.ProgressBars and type(YMap.ProgressBars.Apply) == "function" then
        YMap.ProgressBars:Apply(
            MinimapModule.holder,
            MinimapModule.placementAnchor,
            size,
            config,
            style
        )
    elseif MinimapModule.holder and MinimapModule.placementAnchor then
        MinimapModule.holder:ClearAllPoints()
        MinimapModule.holder:SetPoint("CENTER", MinimapModule.placementAnchor, "CENTER", 0, 0)
        MinimapModule.holder:SetSize(size, size)
    end
    ApplyBaseOwnership(config, style)
    ApplyZoneText(config, style)
    if style == "square" then
        ApplySquareSlots(config)
    else
        if MinimapModule.difficultyText then MinimapModule.difficultyText:Hide() end
        ApplyNativeAppearance(config)
        ApplyNativeTracking(config)
        ApplyLandingPageSlot(_G.ExpansionLandingPageMinimapButton, config, "native")
        if _G.GarrisonLandingPageMinimapButton ~= _G.ExpansionLandingPageMinimapButton then
            ApplyLandingPageSlot(_G.GarrisonLandingPageMinimapButton, config, "native")
        end
    end
    ApplyZoomButtons(config, style)
    ApplyQueue(config)
    ApplyBelowWidget(config)
    RefreshRightClickHandler(config, style)
    MinimapModule:RefreshCoordinateConsumer(config, style)
    VerifyAppliedStyle(style)
    if settingsPreviewKey then MinimapModule:SetSettingsPreview(settingsPreviewKey) end
end

local function RegisterEditModeCallbacks()
    local registry = _G.EventRegistry
    if not (registry and registry.RegisterCallback) or MinimapModule.editCallbacksRegistered then return end
    registry:RegisterCallback("EditMode.Enter", MinimapModule.OnEditModeEnter, MinimapModule)
    registry:RegisterCallback("EditMode.Exit", MinimapModule.OnEditModeExit, MinimapModule)
    MinimapModule.editCallbacksRegistered = true
    EnsureNativeEditModeLayoutHook()
end

local function UnregisterEditModeCallbacks()
    local registry = _G.EventRegistry
    if MinimapModule.editCallbacksRegistered and registry and registry.UnregisterCallback then
        registry:UnregisterCallback("EditMode.Enter", MinimapModule)
        registry:UnregisterCallback("EditMode.Exit", MinimapModule)
    end
    MinimapModule.editCallbacksRegistered = false
end

local function ClaimNativeEditModeSystem()
    local layout = YUI.Layout
    local frame = _G.MinimapCluster
    if layout and frame and type(layout.SetNativeEditModeClaim) == "function" then
        local ok = layout:SetNativeEditModeClaim(MinimapModule, frame, true)
        MinimapModule.nativeEditModeClaimed = ok == true
    end
end

local function ReleaseNativeEditModeSystem()
    MinimapModule.nativeEditModeClaimed = false
    local layout = YUI.Layout
    if layout and type(layout.ReleaseNativeEditModeOwner) == "function" then
        return layout:ReleaseNativeEditModeOwner(MinimapModule)
    end
    return true
end

function MinimapModule.OnEditModeEnter(owner)
    owner.editModeActive = true
    if owner.zoneLabel then owner.zoneLabel:Hide() end
    owner:StopCoordinateConsumer()
    SetRightClickHandlerEnabled(false)
    EnsureNativeEditModeLayoutHook()
    owner.nativeEditModeGeometryYielded = ReapplyYUIEditModeGeometry() == true
end

function MinimapModule.OnEditModeExit(owner)
    RestoreEditModeMouse()
    owner.editModeActive = false
    owner.nativeEditModeGeometryYielded = false
    if owner.enabled == true then QueueMutationRefresh("edit-mode-exit", true) end
end

local function RuntimeOnEvent(_, event, arg1)
    if event == "PLAYER_REGEN_ENABLED" then
        MinimapModule.eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if MinimapModule.pendingDisable then
            MinimapModule:CompleteDisable(MinimapModule.pendingDisableKeepsConflict)
        elseif MinimapModule.pendingRefresh and MinimapModule.enabled then
            MinimapModule:Refresh("combat-ended")
        end
        return
    end
    if MinimapModule.active ~= true then return end
    if event == "ADDON_LOADED" then
        local conflict, controller, snapshot = DetectConflict()
        if conflict then
            BlockForConflict(conflict, controller, snapshot)
            return
        end
        if RELEVANT_LATE_ADDONS[arg1] then MinimapModule:Refresh("addon-loaded") end
    elseif event == "PLAYER_ENTERING_WORLD" then
        MinimapModule:Refresh("entering-world")
    elseif event == "ZONE_CHANGED"
        or event == "ZONE_CHANGED_INDOORS"
        or event == "ZONE_CHANGED_NEW_AREA"
    then
        RefreshSquareZoneLabel()
    elseif event == "UPDATE_UI_WIDGET" then
        if DelvesAPI and type(DelvesAPI.IsTierWidgetUpdate) == "function"
            and DelvesAPI.IsTierWidgetUpdate(arg1)
        then
            MinimapModule:Refresh("difficulty-widget")
        end
    elseif event == "UPDATE_ALL_UI_WIDGETS" then
        local difficultyID = type(_G.GetInstanceInfo) == "function" and select(3, _G.GetInstanceInfo()) or nil
        if DelvesAPI and type(DelvesAPI.IsDelveDifficulty) == "function"
            and DelvesAPI.IsDelveDifficulty(difficultyID)
        then
            MinimapModule:Refresh("difficulty-widgets")
        end
    elseif event == "PLAYER_DIFFICULTY_CHANGED"
        or event == "INSTANCE_GROUP_SIZE_CHANGED"
        or event == "UPDATE_INSTANCE_INFO"
        or event == "ACTIVE_DELVE_DATA_UPDATE"
        or event == "WALK_IN_DATA_UPDATE"
    then
        MinimapModule:Refresh("difficulty")
    end
end

local function EnsureEventFrame()
    if MinimapModule.eventFrame then return MinimapModule.eventFrame end
    local frame = _G.CreateFrame("Frame")
    frame:SetScript("OnEvent", RuntimeOnEvent)
    MinimapModule.eventFrame = frame
    return frame
end

local function RegisterRuntimeEvents()
    local frame = EnsureEventFrame()
    frame:RegisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("ZONE_CHANGED")
    frame:RegisterEvent("ZONE_CHANGED_INDOORS")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
    frame:RegisterEvent("INSTANCE_GROUP_SIZE_CHANGED")
    frame:RegisterEvent("UPDATE_INSTANCE_INFO")
    frame:RegisterEvent("ACTIVE_DELVE_DATA_UPDATE")
    frame:RegisterEvent("WALK_IN_DATA_UPDATE")
    frame:RegisterEvent("UPDATE_UI_WIDGET")
    frame:RegisterEvent("UPDATE_ALL_UI_WIDGETS")
end

local function UnregisterRuntimeEvents(keepCombatEvent)
    local frame = MinimapModule.eventFrame
    if not frame then return end
    frame:UnregisterAllEvents()
    if keepCombatEvent then frame:RegisterEvent("PLAYER_REGEN_ENABLED") end
end

BlockForConflict = function(reason, controller, snapshot)
    MinimapModule.conflictReason = reason
    MinimapModule.conflictController = controller
    MinimapModule.conflictSnapshot = snapshot
    if (reason == "ExternalMinimap" or reason == "MinimapParent"
        or reason == "GetMinimapShape") and YUI.Yield then
        YUI.Yield:Set("minimap", controller, {
            status = "active",
            matches = snapshot and snapshot.matches,
            enabled = true,
        })
    end
    SetSharedStat("conflictBlocked", true)
    SetSharedStat("minimapActive", false)
    if YMap.ButtonDrawer and type(YMap.ButtonDrawer.Disable) == "function" then
        pcall(YMap.ButtonDrawer.Disable, YMap.ButtonDrawer)
    end
    MinimapModule:Deactivate(true)
    return false, reason
end

function MinimapModule:Enable(reason)
    if self.active == true then return self:Refresh(reason or "enable") end

    local config = GetConfig()
    if not config or config.enabled == false then return false, "disabled" end
    local conflict, controller, snapshot = DetectConflict()
    if conflict then
        self.enabled = false
        self.conflictReason = conflict
        self.conflictController = controller
        self.conflictSnapshot = snapshot
        if (conflict == "ExternalMinimap" or conflict == "MinimapParent"
            or conflict == "GetMinimapShape") and YUI.Yield then
            YUI.Yield:Set("minimap", controller, {
                status = "active",
                matches = snapshot and snapshot.matches,
                enabled = true,
            })
        end
        SetSharedStat("conflictBlocked", true)
        SetSharedStat("minimapActive", false)
        return false, conflict
    end

    if not (_G.Minimap and _G.MinimapCluster and _G.UIParent) then
        self.enabled = false
        self.conflictReason = "Blizzard_Minimap"
        SetSharedStat("conflictBlocked", true)
        return false, self.conflictReason
    end
    if not EnsureHolder(config) then
        self.enabled = false
        self.conflictReason = "YUI.GUI2"
        SetSharedStat("conflictBlocked", true)
        return false, self.conflictReason
    end

    self.enabled = true
    self.active = true
    self.pendingDisable = false
    self.pendingDisableKeepsConflict = false
    self.conflictReason = nil
    self.conflictController = nil
    self.conflictSnapshot = nil
    local editFrame = _G.EditModeManagerFrame
    self.editModeActive = editFrame and editFrame.IsShown and editFrame:IsShown() or false
    RegisterRuntimeEvents()
    RegisterEditModeCallbacks()
    AttachMutationQueue()
    InstallHooks()
    ClaimNativeEditModeSystem()
    if self.editModeActive == true then
        EnsureNativeEditModeLayoutHook()
        self.nativeEditModeGeometryYielded = ReapplyYUIEditModeGeometry() == true
    end
    SetSharedStat("conflictBlocked", false)
    SetSharedStat("minimapActive", true)
    return self:Refresh(reason or "enable")
end

function MinimapModule:Refresh(reason)
    if self.active ~= true then return false, self.conflictReason or "inactive" end

    local config = GetConfig()
    if not config or config.enabled == false then
        self:Disable()
        return false, "disabled"
    end

    MinimapModule.RefreshTrackingHint(config)
    if YMap.MetricsWidget then YMap.MetricsWidget:Refresh() end
    local conflict, controller, snapshot = DetectConflict()
    if conflict then return BlockForConflict(conflict, controller, snapshot) end
    if self.editModeActive == true then
        self.pendingRefresh = true
        SetSharedStat("pendingRefresh", true)
        return true, "edit-mode"
    end
    if InCombat() then
        self.pendingRefresh = true
        SetSharedStat("pendingRefresh", true)
        EnsureEventFrame():RegisterEvent("PLAYER_REGEN_ENABLED")
        return true, "combat"
    end

    baseGeometryMutationPending = false
    self.pendingRefresh = false
    SetSharedStat("pendingRefresh", false)
    local style = config.style == "native" and "native" or "square"
    self.applying = true
    local ok, err = pcall(ApplyCurrent, config, style)
    self.applying = false
    if not ok then
        self.lastError = err
        self.writeFailures = self.writeFailures + 1
        return BlockForConflict("apply-error")
    end

    self.reconciles = self.reconciles + 1
    IncrementSharedStat("minimapReconciles", 1)
    SetSharedStat("minimapActive", true)
    SetSharedStat("conflictBlocked", false)
    return true, reason
end

function MinimapModule:OnButtonDrawerReleased(reason)
    if InCombat() then return false, "combat" end
    if self.active == true then
        return self:Refresh(reason or "button-drawer-release")
    end

    self.applying = true
    local ok, err = pcall(function()
        local config = GetConfig() or {}
        ApplyLandingPageSlot(_G.ExpansionLandingPageMinimapButton, config, "native")
        if _G.GarrisonLandingPageMinimapButton ~= _G.ExpansionLandingPageMinimapButton then
            ApplyLandingPageSlot(_G.GarrisonLandingPageMinimapButton, config, "native")
        end
    end)
    self.applying = false
    if not ok then
        self.lastError = err
        self.writeFailures = self.writeFailures + 1
        return false, err
    end
    return true, reason
end

function MinimapModule:CompleteDisable(keepConflict)
    if YMap.TextComponents then YMap.TextComponents:Restore(_G.TimeManagerClockTicker) end
    ReleaseNativeEditModeSystem()
    self.pendingDisable = false
    self.pendingDisableKeepsConflict = false
    self.pendingRefresh = false
    self:ClearSettingsPreview()
    self:StopCoordinateConsumer()
    SetRightClickHandlerEnabled(false)
    self.applying = true
    RestoreAllFrames()
    self.applying = false
    self.appliedStyle = nil
    self.minimapHovered = false
    nativeMetrics.captured = false
    if self.border then self.border:Hide() end
    if self.zoneLabel then self.zoneLabel:Hide() end
    if self.difficultyText then self.difficultyText:Hide() end
    if YMap.ProgressBars and type(YMap.ProgressBars.Disable) == "function" then
        local config = GetConfig()
        YMap.ProgressBars:Disable(
            self.holder,
            self.placementAnchor,
            config and config.size or 175
        )
    end
    if self.holder then self.holder:Hide() end
    if self.placementAnchor then self.placementAnchor:Hide() end
    UnregisterLayout()
    UnregisterBelowWidgetLayout()
    UnregisterRuntimeEvents(false)
    SetSharedStat("minimapActive", false)
    SetSharedStat("pendingRefresh", false)
    if not keepConflict then
        self.conflictReason = nil
        self.conflictController = nil
        self.conflictSnapshot = nil
        SetSharedStat("conflictBlocked", false)
    end
    return true
end

function MinimapModule:Deactivate(keepConflict)
    self.clockTextStyle = nil
    if YMap.TextComponents then YMap.TextComponents:Restore(_G.TimeManagerClockTicker) end
    ReleaseNativeEditModeSystem()
    self:ClearSettingsPreview()
    self.minimapHovered = false
    self:StopCoordinateConsumer()
    SetRightClickHandlerEnabled(false)
    self.active = false
    self.enabled = false
    self.pendingRefresh = false
    DetachMutationQueue()
    UnregisterEditModeCallbacks()
    RestoreShapeWrapper()
    if self.border then self.border:Hide() end
    if self.zoneLabel then self.zoneLabel:Hide() end
    if YMap.ProgressBars and type(YMap.ProgressBars.Disable) == "function" then
        local config = GetConfig()
        YMap.ProgressBars:Disable(
            self.holder,
            self.placementAnchor,
            config and config.size or 175
        )
    end
    if InCombat() then
        self.pendingDisable = true
        self.pendingDisableKeepsConflict = keepConflict == true
        UnregisterRuntimeEvents(true)
        SetSharedStat("pendingRefresh", true)
        SetSharedStat("minimapActive", false)
        return true, "combat"
    end
    return self:CompleteDisable(keepConflict == true)
end

function MinimapModule:Disable()
    MinimapModule.OnRightClickHandlerLeave()
    self.trackingHintEligible = false
    if self.active ~= true and not self.pendingDisable then
        ReleaseNativeEditModeSystem()
        self:StopCoordinateConsumer()
        if YMap.ProgressBars and type(YMap.ProgressBars.Disable) == "function" then
            local config = GetConfig()
            YMap.ProgressBars:Disable(
                self.holder,
                self.placementAnchor,
                config and config.size or 175
            )
        end
        self.enabled = false
        self.conflictReason = nil
        SetSharedStat("minimapActive", false)
        SetSharedStat("conflictBlocked", false)
        SetSharedStat("pendingRefresh", false)
        return true
    end
    self.conflictReason = nil
    self.conflictController = nil
    self.conflictSnapshot = nil
    return self:Deactivate(false)
end

function MinimapModule:GetConflictReason()
    return self.conflictReason
end

function MinimapModule:GetConflictController()
    return self.conflictController, self.conflictSnapshot
end

function MinimapModule:GetStats(target)
    target = type(target) == "table" and target or {}
    target.minimapActive = self.active == true
    target.minimapReconciles = self.reconciles
    target.pendingRefresh = self.pendingRefresh == true or self.pendingDisable == true
    target.conflictBlocked = self.conflictReason ~= nil
    target.shadowComparisons = YMap.Stats and YMap.Stats.shadowComparisons or self.shadowComparisons
    target.shadowMismatches = YMap.Stats and YMap.Stats.shadowMismatches or self.shadowMismatches
    target.minimapRestoreFailures = self.restoreFailures
    target.minimapWriteFailures = self.writeFailures
    target.minimapEditModeActive = self.editModeActive == true
    target.minimapHooksInstalled = self.hooksInstalled == true
    target.minimapConflictReason = self.conflictReason
    target.minimapDifficultyTextVisible = self.difficultyText and self.difficultyText:IsShown() or false
    target.minimapSettingsPreviewKey = self.settingsPreviewKey
    target.minimapHovered = self.minimapHovered == true
    target.minimapTrackingHintVisible = self.trackingHintVisible == true
    target.minimapTrackingHintDriverActive = self.trackingHint
        and self.trackingHint:GetScript("OnUpdate") ~= nil or false
    target.minimapTrackingHintPositionWrites = self.trackingHintPositionWrites
    target.minimapZoneLabelVisible = self.zoneLabel and self.zoneLabel:IsShown() or false
    target.minimapCoordinateConsumerActive = YMap.CoordinateDriver
        and type(YMap.CoordinateDriver.IsMinimapActive) == "function"
        and YMap.CoordinateDriver:IsMinimapActive()
        or false
    target.minimapCoordinateVisible = self.coordinateVisible == true
    target.minimapCoordinateReads = YMap.Stats and YMap.Stats.minimapCoordinateReads or self.coordinateReads
    target.minimapCoordinateTextWrites = YMap.Stats
        and YMap.Stats.minimapCoordinateTextWrites
        or self.coordinateTextWrites
    target.minimapBelowWidgetLayoutRegistered = self.belowWidgetLayoutRegistered == true
    target.minimapRightClickHandlerActive = self.rightClickHandlerActive == true
    target.minimapTrackingMenuOwned = self.trackingMenuOwned == true
    target.minimapTrackingMenuOpenAttempts = self.trackingMenuOpenAttempts
    target.minimapTrackingMenuOpenSuccesses = self.trackingMenuOpenSuccesses
    target.minimapTrackingMenuOpenFailures = self.trackingMenuOpenFailures
    return target
end


if YUI.Layout and YUI.Layout.RegisterAnchorProvider then
    YUI.Layout:RegisterAnchorProvider(LAYOUT_ID, {
        name = "YMapMinimapPlacementAnchor",
        resolve = function()
            local profile = YMap.GetProfile and YMap:GetProfile()
            if not profile then return nil end
            local db = profile[YMap.STORAGE_KEY]
            local config = db and db.minimap
            local size = Clamp(config and config.size, 120, 400, 175)
            return CaptureInitialPlacement(size), size, size, 1
        end,
    })
end
