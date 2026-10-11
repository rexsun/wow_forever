local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not (YUI and YUI.Components) then return end

local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or (_G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME] and _G.YUI_CORE_EMBED_STATE[ADDON_NAME].productId)
    or YUI.ProductId or "suite"
local TooltipCursor = { product = PRODUCT_ID }
YUI._MouseEnhancementTooltipCursor = TooltipCursor

local Security = YUI.API and YUI.API.Security
local IsSecret = Security and Security.IsSecretValue or _G.issecretvalue or function() return false end
local POSITIONS = {
    TOPRIGHT = { "BOTTOMLEFT", 12, 12 },
    TOP = { "BOTTOM", 0, 12 },
    TOPLEFT = { "BOTTOMRIGHT", -12, 12 },
    RIGHT = { "LEFT", 12, 0 },
    CENTER = { "CENTER", 0, 0 },
    LEFT = { "RIGHT", -12, 0 },
    BOTTOMRIGHT = { "TOPLEFT", 12, -12 },
    BOTTOM = { "TOP", 0, -12 },
    BOTTOMLEFT = { "TOPRIGHT", -12, -12 },
}
local records = setmetatable({}, { __mode = "k" })
local State = {
    enabled = false,
    hooksInstalled = false,
    running = false,
    writing = false,
    point = "BOTTOMLEFT",
    offsetX = 12,
    offsetY = 12,
    positionWrites = 0,
    failures = 0,
}

local function SafeNumber(value)
    if IsSecret(value) or type(value) ~= "number" then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function NormalizeOffset(value)
    value = SafeNumber(value) or 0
    return math.floor(math.max(-100, math.min(100, value)) + 0.5)
end

function TooltipCursor.NormalizeConfig(db)
    db.tooltipCursorEnabled = not IsSecret(db.tooltipCursorEnabled) and db.tooltipCursorEnabled == true
    if IsSecret(db.tooltipCursorPosition) or not POSITIONS[db.tooltipCursorPosition] then
        db.tooltipCursorPosition = "TOPRIGHT"
    end
    db.tooltipCursorOffsetX = NormalizeOffset(db.tooltipCursorOffsetX)
    db.tooltipCursorOffsetY = NormalizeOffset(db.tooltipCursorOffsetY)
end

local function Usable(frame)
    if IsSecret(frame) or not frame then return false end
    if type(frame.IsForbidden) == "function" then
        local ok, forbidden = pcall(frame.IsForbidden, frame)
        if not ok or IsSecret(forbidden) or forbidden ~= false then return false end
    end
    return true
end

local function StopDriver()
    if State.anchor and State.running then
        State.anchor:SetScript("OnUpdate", nil)
        State.anchor:Hide()
    end
    State.running = false
    State.lastX, State.lastY, State.lastScale = nil, nil, nil
end

local function DropOwnership()
    StopDriver()
    local record = State.tooltip and records[State.tooltip]
    if record then
        record.owner = nil
        for i = 1, record.count do record.points[i][2] = nil end
    end
    State.tooltip = nil
end

local function PositionAnchor()
    local uiParent = _G.UIParent
    if not uiParent or type(_G.GetCursorPosition) ~= "function" then return false end
    local ok, rawX, rawY = pcall(_G.GetCursorPosition)
    if not ok then return false end
    local x, y = SafeNumber(rawX), SafeNumber(rawY)
    local scaleOK, rawScale = pcall(uiParent.GetEffectiveScale, uiParent)
    local scale = scaleOK and SafeNumber(rawScale)
    if not x or not y or not scale or scale <= 0 then return false end
    if x == State.lastX and y == State.lastY and scale == State.lastScale then return true end
    State.anchor:ClearAllPoints()
    State.anchor:SetPoint("CENTER", uiParent, "BOTTOMLEFT", x / scale, y / scale)
    State.lastX, State.lastY, State.lastScale = x, y, scale
    State.positionWrites = State.positionWrites + 1
    return true
end

local function RestorePoints(tooltip, record)
    State.writing = true
    local ok = pcall(tooltip.ClearAllPoints, tooltip)
    for i = 1, record.count do
        local point = record.points[i]
        if ok then
            ok = pcall(tooltip.SetPoint, tooltip, point[1], point[2], point[3], point[4], point[5])
        end
    end
    State.writing = false
    if not ok then State.failures = State.failures + 1 end
end

local function Release(restore)
    local tooltip = State.tooltip
    local record = tooltip and records[tooltip]
    if restore and record and Usable(tooltip) then
        local ok, owner = pcall(tooltip.GetOwner, tooltip)
        if ok and not IsSecret(owner) and owner == record.owner then
            RestorePoints(tooltip, record)
        end
    end
    DropOwnership()
end

local function CursorStep()
    local tooltip = State.tooltip
    if not State.enabled or not tooltip or not Usable(tooltip) then
        DropOwnership()
        return
    end
    local ok, shown = pcall(tooltip.IsShown, tooltip)
    if not ok or IsSecret(shown) or shown ~= true then
        StopDriver()
        return
    end
    if not PositionAnchor() then Release(true) end
end

local function CursorOnUpdate()
    local watchdog = YUI.CPUWatchdog
    local startedAt = watchdog and watchdog.timingActive and watchdog:BeginProbeTiming()
    CursorStep()
    if startedAt then watchdog:EndProbeTiming("component.mouse-enhancement", startedAt) end
end

local function EnsureAnchor()
    if State.anchor then return true end
    if type(_G.CreateFrame) ~= "function" or not _G.UIParent then return false end
    -- 非视觉的运行时锚点，只承载鼠标坐标；不挂接共享提示框脚本。
    State.anchor = _G.CreateFrame("Frame", nil, _G.UIParent)
    State.anchor:SetSize(1, 1)
    State.anchor:Hide()
    return true
end

local function StartDriver()
    if not EnsureAnchor() or not PositionAnchor() then return false end
    if not State.running then
        State.anchor:SetScript("OnUpdate", CursorOnUpdate)
        State.anchor:Show()
        State.running = true
    end
    return true
end

local function CapturePoints(tooltip, owner)
    local ok, rawCount = pcall(tooltip.GetNumPoints, tooltip)
    local count = ok and SafeNumber(rawCount)
    if not count or count < 1 or count > 8 or count ~= math.floor(count) then return nil end
    local record = records[tooltip]
    if not record then
        record = { points = {} }
        records[tooltip] = record
    end
    for i = 1, count do
        local readOK, point, relativeTo, relativePoint, x, y = pcall(tooltip.GetPoint, tooltip, i)
        if not readOK or IsSecret(point) or IsSecret(relativeTo) or IsSecret(relativePoint)
            or type(point) ~= "string" or type(relativePoint) ~= "string"
            or (relativeTo and not Usable(relativeTo)) then return nil end
        x, y = SafeNumber(x), SafeNumber(y)
        if not x or not y then return nil end
        local saved = record.points[i]
        if not saved then saved = {}; record.points[i] = saved end
        saved[1], saved[2], saved[3], saved[4], saved[5] = point, relativeTo, relativePoint, x, y
    end
    record.count, record.owner = count, owner
    return record
end

local function AttachTooltip(tooltip)
    State.writing = true
    local ok = pcall(tooltip.ClearAllPoints, tooltip)
    if ok then
        ok = pcall(tooltip.SetPoint, tooltip, State.point, State.anchor, "CENTER", State.offsetX, State.offsetY)
    end
    State.writing = false
    if not ok then
        State.failures = State.failures + 1
        Release(true)
    end
end

local function OnDefaultAnchor(tooltip, owner)
    if not State.enabled or tooltip ~= _G.GameTooltip then return end
    if not Usable(tooltip) or not Usable(owner) then return end
    if not CapturePoints(tooltip, owner) then return end
    State.tooltip = tooltip
    if not StartDriver() then Release(false); return end
    AttachTooltip(tooltip)
end

local function OnOwnerOrPointChanged(tooltip)
    if not State.enabled or State.writing or tooltip ~= State.tooltip then return end
    -- 新 owner 或外部定位接管时让出，避免两个定位器持续争抢。
    DropOwnership()
end

local function OnTooltipShown(tooltip)
    if not State.enabled or tooltip ~= State.tooltip then return end
    if not StartDriver() then Release(true) end
end

local function EnsureHooks()
    if State.hooksInstalled then return true end
    local tooltip = _G.GameTooltip
    if not Usable(tooltip) or type(_G.hooksecurefunc) ~= "function"
        or type(_G.GameTooltip_SetDefaultAnchor) ~= "function" then return false end
    for _, method in ipairs({ "SetOwner", "SetPoint", "ClearAllPoints", "Show" }) do
        if type(tooltip[method]) ~= "function" then return false end
    end
    _G.hooksecurefunc(tooltip, "SetOwner", OnOwnerOrPointChanged)
    _G.hooksecurefunc(tooltip, "SetPoint", OnOwnerOrPointChanged)
    _G.hooksecurefunc(tooltip, "ClearAllPoints", OnOwnerOrPointChanged)
    _G.hooksecurefunc(tooltip, "Show", OnTooltipShown)
    _G.hooksecurefunc("GameTooltip_SetDefaultAnchor", OnDefaultAnchor)
    State.hooksInstalled = true
    return true
end

function TooltipCursor.Configure(db, featureEnabled)
    TooltipCursor.NormalizeConfig(db)
    if not featureEnabled or not db.tooltipCursorEnabled then
        State.enabled = false
        Release(true)
        return
    end
    State.enabled = EnsureHooks()
    local position = POSITIONS[db.tooltipCursorPosition]
    State.point = position[1]
    State.offsetX = position[2] + db.tooltipCursorOffsetX
    State.offsetY = position[3] + db.tooltipCursorOffsetY
    if State.tooltip and Usable(State.tooltip) then AttachTooltip(State.tooltip) end
end

function TooltipCursor.GetDiagnostics()
    return {
        enabled = State.enabled,
        running = State.running,
        hooksInstalled = State.hooksInstalled,
        frameCount = State.anchor and 1 or 0,
        anchored = State.tooltip ~= nil,
        positionWrites = State.positionWrites,
        failures = State.failures,
    }
end
