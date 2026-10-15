local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not (YUI and YUI.Components) then return end

local Components = YUI.Components
local L = YUI.Locale and YUI.Locale:Get("MouseEnhancement") or {}

local FEATURE_KEY = "MouseEnhancement"
local CONFIG_KEY = "MouseEnhancement_Config"
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or (_G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME] and _G.YUI_CORE_EMBED_STATE[ADDON_NAME].productId)
    or YUI.ProductId or "suite"

local MODE_ALWAYS = "always"
local MODE_MODIFIER = "modifier"
local MOD_SHIFT = "SHIFT"
local MOD_CTRL = "CTRL"
local MOD_ALT = "ALT"

local CURSOR_STYLE_BLIZZARD = "blizzard"
local CURSOR_STYLE_RING_DOT = "ring_dot"
local CURSOR_STYLE_INFRARED_LOCK = "infrared_lock"
local CURSOR_STYLE_ROTATING_TRIANGLE = "rotating_triangle"

local CURSOR_SIZE_SMALL = "small"
local CURSOR_SIZE_MEDIUM = "medium"
local CURSOR_SIZE_LARGE = "large"
local CURSOR_SIZE_EXTRA_LARGE = "extra_large"
local CURSOR_SIZE_MASSIVE = "massive"

local OVERLAY_SIZE_SMALL = "small"
local OVERLAY_SIZE_MEDIUM = "medium"
local OVERLAY_SIZE_LARGE = "large"
local OVERLAY_SIZE_EXTRA_LARGE = "extra_large"
local OVERLAY_SIZE_MASSIVE = "massive"

local TRAIL_MODE_NONE = "none"
local TRAIL_MODE_STARS = "stars"
local TRAIL_MODE_FOOTBALL = "football"
local TRAIL_MODEL_MODES = {
    ARC = "model_arc",
    FLARE = "model_flare",
    PRISM = "model_prism",
    COMET = "model_comet",
}

local TRAIL_QUALITY_SMOOTH = "smooth"
local TRAIL_QUALITY_BALANCED = "balanced"
local TRAIL_QUALITY_QUALITY = "quality"

local ID_LABEL_PREFIX = "|cffFF6666ID:|r "
local ID_NUMBER_COLOR_CODE = _G.NORMAL_FONT_COLOR_CODE or "|cffffd200"
local ID_COLOR_CLOSE = _G.FONT_COLOR_CODE_CLOSE or "|r"
local SECTION_WIDTH = 620
local NATIVE_CURSOR_SIZE_CVAR = "cursorSizePreferred"
local CURSOR_MOTION_SCALE_DEFAULT = "1_25"
local MOTION_SCALE_SPEED_FOR_MAX = 1800
local MOTION_SCALE_LERP = 0.35
local TRAIL_STAR_SIZE_SCALE = 0.70
local TRAIL_FOOTBALL_SIZE_SCALE = 0.78
local TRAIL_MIN_SIZE = 10
local MODEL_TRAIL = {
    interval = 1 / 45,
    alpha = 0.95,
}
local MODEL_CURSOR_POSITION, MODEL_CURSOR_TRANSFORM = "position", "transform"

local CURSOR_SIZE_PIXELS = {
    [CURSOR_SIZE_SMALL] = 24,
    [CURSOR_SIZE_MEDIUM] = 32,
    [CURSOR_SIZE_LARGE] = 42,
    [CURSOR_SIZE_EXTRA_LARGE] = 54,
    [CURSOR_SIZE_MASSIVE] = 68,
}

local NATIVE_CURSOR_SIZE_VALUES = {
    [CURSOR_SIZE_SMALL] = 0,
    [CURSOR_SIZE_MEDIUM] = 1,
    [CURSOR_SIZE_LARGE] = 2,
    [CURSOR_SIZE_EXTRA_LARGE] = 3,
    [CURSOR_SIZE_MASSIVE] = 4,
}

local OVERLAY_SIZE_PIXELS = {
    [OVERLAY_SIZE_SMALL] = 28,
    [OVERLAY_SIZE_MEDIUM] = 38,
    [OVERLAY_SIZE_LARGE] = 50,
    [OVERLAY_SIZE_EXTRA_LARGE] = 64,
    [OVERLAY_SIZE_MASSIVE] = 82,
}

local MOTION_SCALE_MAX_VALUES = {
    ["1_15"] = 1.15,
    ["1_25"] = 1.25,
    ["1_40"] = 1.40,
    ["1_60"] = 1.60,
    ["2_00"] = 2.00,
}

local TRAIL_QUALITY_SETTINGS = {
    [TRAIL_QUALITY_SMOOTH] = { interval = 1 / 30, idleInterval = 0.12, maxObjects = 10, distance = 28, duration = 0.20 },
    [TRAIL_QUALITY_BALANCED] = { interval = 1 / 45, idleInterval = 0.09, maxObjects = 16, distance = 22, duration = 0.28 },
    [TRAIL_QUALITY_QUALITY] = { interval = 1 / 60, idleInterval = 0.06, maxObjects = 24, distance = 16, duration = 0.36 },
}

local MODEL_TRAIL_SETTINGS = {
    [TRAIL_MODEL_MODES.ARC] = {
        modelID = 166492,
        cursorMode = MODEL_CURSOR_POSITION,
        modelScale = 0.060,
        cursorStepX = 3430,
        cursorStepY = 3155,
        modelOffsetX = 0.000,
        modelOffsetY = 0.018,
        skewTop = 0.985,
        skewBottom = 1.105,
        offsetZ = 0,
        rotationX = 0,
        rotationY = 0,
        rotationZ = 0,
    },
    [TRAIL_MODEL_MODES.FLARE] = {
        modelID = 1513210,
        cursorMode = MODEL_CURSOR_TRANSFORM,
        modelScale = 0.011,
        offsetX = 0.000,
        offsetY = 0.000,
        offsetZ = 0,
        rotationX = 0,
        rotationY = 90,
        rotationZ = 0,
    },
    [TRAIL_MODEL_MODES.PRISM] = {
        modelID = 1417024,
        cursorMode = MODEL_CURSOR_POSITION,
        modelScale = 0.048,
        cursorStepX = 3430,
        cursorStepY = 3150,
        modelOffsetX = 0.000,
        modelOffsetY = -0.105,
        skewTop = 0.985,
        skewBottom = 1.105,
        offsetZ = 0,
        rotationX = 0,
        rotationY = 0,
        rotationZ = 0,
    },
    [TRAIL_MODEL_MODES.COMET] = {
        modelID = 1513212,
        cursorMode = MODEL_CURSOR_TRANSFORM,
        modelScale = 0.012,
        offsetX = 0.000,
        offsetY = 0.000,
        offsetZ = 0,
        rotationX = 0,
        rotationY = 90,
        rotationZ = 0,
    },
}

local STAR_SIZE_SCALE = { 0.90, 1.15, 0.80, 1.30, 1.00, 0.75, 1.20, 0.95 }
local STAR_DRIFT = { 26, 34, 22, 40, 30, 18, 36, 24 }

local DEFAULTS = {
    playerTooltipColorEnabled = true,
    playerTooltipMythicPlusEnabled = true,
    playerTooltipMythicPlusScoreEnabled = false,
    playerTooltipModifier = MOD_SHIFT,
    tooltipIDEnabled = true,
    itemSpellIDEnabled = true,
    tooltipInstantHide = true,
    tooltipCursorEnabled = false,
    tooltipCursorPosition = "TOPRIGHT",
    tooltipCursorOffsetX = 0,
    tooltipCursorOffsetY = 0,
    cursorEffectsEnabled = false,
    displayMode = MODE_ALWAYS,
    modifierKey = MOD_SHIFT,
    cursorStyle = CURSOR_STYLE_BLIZZARD,
    cursorSize = CURSOR_SIZE_MEDIUM,
    overlaySize = OVERLAY_SIZE_MEDIUM,
    cursorMotionScale = false,
    cursorMotionScaleMax = CURSOR_MOTION_SCALE_DEFAULT,
    trailMode = TRAIL_MODE_NONE,
    trailQuality = TRAIL_QUALITY_BALANCED,
    cursorScene = "always",
}

local State = {
    featureEnabled = false,
    hooksInstalled = false,
    trailPool = {},
    trailPoolSize = 0,
    activeTrailCount = 0,
    cursorDriverActive = false,
    cursorDriverElapsed = 0,
    trailSequence = 0,
    idleTrailWatcher = false,
    motionScale = 1,
    positionModelFrame = nil,
    transformModelFrame = nil,
    modelTrailMode = nil,
    modelTrailCursorMode = nil,
    modelTrailShown = false,
    modelTrailFailedMode = nil,
    modelTrailScreenW = nil,
    modelTrailScreenH = nil,
    modelTrailScreenScale = nil,
    modelTrailScreenDiagonal = nil,
    modelTrailFitDivisorX = nil,
    modelTrailFitDivisorY = nil,
    modelTrailVisualScale = nil,
    modelTrailResolvedOffsetX = nil,
    modelTrailResolvedOffsetY = nil,
    modelTrailOffsetUnit = nil,
    modelTrailSkewTop = nil,
    modelTrailSkewBottom = nil,
    modelTrailSkewSlope = nil,
    cursorInHousing = false,
    overlayRotation = 0,
    nativeAuraIDCVarName = "tooltipShowAuraSpellIDs",
    nativeAuraIDCVarOwned = false,
    nativeAuraIDCVarPrevious = nil,
    nativeAuraIDCVarSyncPending = false,
}

local ADDON_ELV = "ElvUI"
local ADDON_ND = "NDui"
local ADDON_EQOL = "EnhanceQoL"
local ADDON_EQOL_TOOLTIP = "EnhanceQoLTooltip"
local ADDON_EUI = "EllesmereUI"

local EQOL_FLAGS = {
    item = { "TooltipShowItemID" },
    spell = { "TooltipShowSpellID" },
    aura = { "TooltipShowSpellID" },
    macro = { "TooltipShowSpellID", "TooltipShowItemID" },
    currency = { "TooltipShowCurrencyID" },
    quest = { "TooltipShowQuestID", "TooltipShowQuestIDInQuestLog" },
    npc = { "TooltipShowNPCID" },
}

local function T(key, fallback)
    if type(L) == "table" and L[key] then
        return L[key]
    end
    return fallback or key
end

local function CopyDefaultValue(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}
    for key, item in pairs(value) do
        result[key] = CopyDefaultValue(item)
    end
    return result
end

local function FillMissing(target, defaults)
    if type(target) ~= "table" or type(defaults) ~= "table" then
        return
    end

    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = CopyDefaultValue(value)
        end
    end
end

local function NormalizeDB(db)
    FillMissing(db, DEFAULTS)
    db.playerTooltipColorEnabled = db.playerTooltipColorEnabled ~= false
    db.playerTooltipMythicPlusEnabled = db.playerTooltipMythicPlusEnabled ~= false
    db.playerTooltipMythicPlusScoreEnabled = db.playerTooltipMythicPlusScoreEnabled ~= false
    if db.playerTooltipModifier ~= MOD_SHIFT
        and db.playerTooltipModifier ~= MOD_CTRL
        and db.playerTooltipModifier ~= MOD_ALT then
        db.playerTooltipModifier = "NONE"
    end
    db.tooltipIDEnabled = db.tooltipIDEnabled ~= false
    db.itemSpellIDEnabled = db.itemSpellIDEnabled ~= false
    db.cursorEffectsEnabled = db.cursorEffectsEnabled == true
    if db.displayMode ~= MODE_ALWAYS and db.displayMode ~= MODE_MODIFIER then
        db.displayMode = MODE_ALWAYS
    end
    if db.modifierKey ~= MOD_SHIFT and db.modifierKey ~= MOD_CTRL and db.modifierKey ~= MOD_ALT then
        db.modifierKey = MOD_SHIFT
    end
    if db.cursorStyle ~= CURSOR_STYLE_RING_DOT
        and db.cursorStyle ~= CURSOR_STYLE_INFRARED_LOCK
        and db.cursorStyle ~= CURSOR_STYLE_ROTATING_TRIANGLE then
        db.cursorStyle = CURSOR_STYLE_BLIZZARD
    end
    if db.cursorSize ~= CURSOR_SIZE_SMALL
        and db.cursorSize ~= CURSOR_SIZE_LARGE
        and db.cursorSize ~= CURSOR_SIZE_EXTRA_LARGE
        and db.cursorSize ~= CURSOR_SIZE_MASSIVE then
        db.cursorSize = CURSOR_SIZE_MEDIUM
    end
    if db.overlaySize ~= OVERLAY_SIZE_SMALL
        and db.overlaySize ~= OVERLAY_SIZE_LARGE
        and db.overlaySize ~= OVERLAY_SIZE_EXTRA_LARGE
        and db.overlaySize ~= OVERLAY_SIZE_MASSIVE then
        db.overlaySize = OVERLAY_SIZE_MEDIUM
    end
    db.cursorMotionScale = db.cursorMotionScale == true
    if not MOTION_SCALE_MAX_VALUES[db.cursorMotionScaleMax] then
        db.cursorMotionScaleMax = CURSOR_MOTION_SCALE_DEFAULT
    end
    if db.trailMode ~= TRAIL_MODE_STARS
        and db.trailMode ~= TRAIL_MODE_FOOTBALL
        and not MODEL_TRAIL_SETTINGS[db.trailMode] then
        db.trailMode = TRAIL_MODE_NONE
    end
    if db.trailQuality ~= TRAIL_QUALITY_SMOOTH and db.trailQuality ~= TRAIL_QUALITY_QUALITY then
        db.trailQuality = TRAIL_QUALITY_BALANCED
    end
    if db.cursorScene ~= "instance" and db.cursorScene ~= "world" then
        db.cursorScene = "always"
    end
end

local function GetDB()
    local db, store = Components:EnsureConfig(CONFIG_KEY, nil, PRODUCT_ID)
    if type(db) ~= "table" then
        return DEFAULTS
    end
    local tooltipFade = YUI._MouseEnhancementTooltipFade
    if tooltipFade then tooltipFade.NormalizeConfig(db, store) end
    NormalizeDB(db)
    return db
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then
        return false, nil
    end
    return pcall(fn, ...)
end

local function GetComponentAsset(path)
    local assets = YUI.Assets
    if assets and type(assets.Component) == "function" then
        local ok, value = pcall(assets.Component, assets, FEATURE_KEY, path)
        if ok and type(value) == "string" and value ~= "" then
            return value
        end
    end
    return nil
end

local function GetCursorSizePixels(db)
    return CURSOR_SIZE_PIXELS[db and db.cursorSize] or CURSOR_SIZE_PIXELS[CURSOR_SIZE_MEDIUM]
end

local function GetOverlaySizePixels(db)
    return OVERLAY_SIZE_PIXELS[db and db.overlaySize] or OVERLAY_SIZE_PIXELS[OVERLAY_SIZE_MEDIUM]
end

local function GetNativeCursorSizeValue(db)
    return NATIVE_CURSOR_SIZE_VALUES[db and db.cursorSize] or NATIVE_CURSOR_SIZE_VALUES[CURSOR_SIZE_MEDIUM]
end

local function GetMotionScaleMax(db)
    return MOTION_SCALE_MAX_VALUES[db and db.cursorMotionScaleMax] or MOTION_SCALE_MAX_VALUES[CURSOR_MOTION_SCALE_DEFAULT]
end

local function GetTrailQualitySettings(db)
    return TRAIL_QUALITY_SETTINGS[db and db.trailQuality] or TRAIL_QUALITY_SETTINGS[TRAIL_QUALITY_BALANCED]
end

local function IsTextureTrailMode(mode)
    return mode == TRAIL_MODE_STARS or mode == TRAIL_MODE_FOOTBALL
end

local function IsModelTrailMode(mode)
    return MODEL_TRAIL_SETTINGS[mode] ~= nil
end

local function IsValidTrailMode(mode)
    return mode == TRAIL_MODE_NONE or IsTextureTrailMode(mode) or IsModelTrailMode(mode)
end

local function GetCursorDriverInterval(db)
    if db and IsModelTrailMode(db.trailMode) then
        return MODEL_TRAIL.interval
    end

    local settings = GetTrailQualitySettings(db)
    return State.idleTrailWatcher and settings.idleInterval or settings.interval
end

local function GetCursorPositions()
    if not (type(_G.GetCursorPosition) == "function" and _G.UIParent and type(_G.UIParent.GetEffectiveScale) == "function") then
        return nil, nil, nil, nil
    end

    local ok, rawX, rawY = pcall(_G.GetCursorPosition)
    if not ok or type(rawX) ~= "number" or type(rawY) ~= "number" then
        return nil, nil, nil, nil
    end

    local scale = _G.UIParent:GetEffectiveScale()
    if type(scale) ~= "number" or scale <= 0 then
        scale = 1
    end
    return rawX / scale, rawY / scale, rawX, rawY
end

local function IsCustomCursorStyle(db)
    return db and (db.cursorStyle == CURSOR_STYLE_RING_DOT
        or db.cursorStyle == CURSOR_STYLE_INFRARED_LOCK
        or db.cursorStyle == CURSOR_STYLE_ROTATING_TRIANGLE)
end

function State.RefreshCursorHousingState()
    State.cursorInHousing = false

    local housing = _G.C_Housing
    local isOnNeighborhoodMap = housing and housing.IsOnNeighborhoodMap
    if type(isOnNeighborhoodMap) ~= "function" then
        return
    end

    local ok, isOnNeighborhoodMapResult = pcall(isOnNeighborhoodMap)
    State.cursorInHousing = ok and isOnNeighborhoodMapResult == true
end

function State.IsCursorSceneMatched(db)
    local scene = db and db.cursorScene or "always"
    if scene == "always" then
        return true
    end

    -- 家宅社区使用独立实例，但鼠标特效场景中按副本外处理。
    if State.cursorInHousing then
        return scene == "world"
    end

    if type(_G.IsInInstance) ~= "function" then
        return scene == "world"
    end

    local ok, inInstance = pcall(_G.IsInInstance)
    if not ok then
        return scene == "world"
    end

    if scene == "instance" then
        return inInstance == true
    end
    if scene == "world" then
        return inInstance ~= true
    end
    return true
end

function State.AreCursorEffectsEnabled(db)
    return State.featureEnabled and db and db.cursorEffectsEnabled == true
end

local function ShouldShowCursorOverlay(db)
    if not State.AreCursorEffectsEnabled(db) then
        return false
    end
    if not State.IsCursorSceneMatched(db) then
        return false
    end
    return IsCustomCursorStyle(db)
end

local function ShouldRunCursorDriver(db)
    if not State.AreCursorEffectsEnabled(db) then
        return false
    end
    if not State.IsCursorSceneMatched(db) then
        return false
    end

    local trailMode = db and db.trailMode
    local hasTrail = trailMode ~= nil and trailMode ~= TRAIL_MODE_NONE
    if IsModelTrailMode(trailMode) and (State.modelTrailUnavailable or State.modelTrailFailedMode == trailMode) then
        hasTrail = false
    end

    return IsCustomCursorStyle(db) or hasTrail
end

local function EnsureCursorFrames()
    if State.cursorRoot or not (type(_G.CreateFrame) == "function" and _G.UIParent) then
        return State.cursorRoot ~= nil
    end

    State.cursorRoot = _G.CreateFrame("Frame", nil, _G.UIParent)
    State.cursorRoot:SetFrameStrata("TOOLTIP")
    State.cursorRoot:SetFrameLevel(9000)
    State.cursorRoot:EnableMouse(false)
    State.cursorRoot:Hide()

    State.cursorOverlay = _G.CreateFrame("Frame", nil, State.cursorRoot)
    State.cursorOverlay:SetFrameStrata("TOOLTIP")
    State.cursorOverlay:SetFrameLevel(9001)
    State.cursorOverlay:EnableMouse(false)
    State.cursorOverlay:Hide()

    State.cursorOverlayTexture = State.cursorOverlay:CreateTexture(nil, "OVERLAY")
    State.cursorOverlayTexture:SetAllPoints(State.cursorOverlay)

    State.trailLayer = _G.CreateFrame("Frame", nil, State.cursorRoot)
    State.trailLayer:SetFrameStrata("TOOLTIP")
    State.trailLayer:SetFrameLevel(8999)
    State.trailLayer:EnableMouse(false)
    State.trailLayer:Show()

    return true
end

local function HideCursorOverlay()
    if State.cursorOverlay then
        State.cursorOverlay:Hide()
    end
end

local function ResetMotionScale(x, y)
    State.motionScale = 1
    State.lastMotionX = x
    State.lastMotionY = y
end

local function UpdateMotionScale(db, x, y, elapsed)
    if not (db and db.cursorMotionScale == true and IsCustomCursorStyle(db)) then
        ResetMotionScale(x, y)
        return 1
    end

    local maxScale = GetMotionScaleMax(db)
    local target = 1
    if State.lastMotionX and State.lastMotionY and type(elapsed) == "number" and elapsed > 0 then
        local dx = x - State.lastMotionX
        local dy = y - State.lastMotionY
        local speed = math.sqrt(dx * dx + dy * dy) / elapsed
        local boost = (maxScale - 1) * math.min(speed / MOTION_SCALE_SPEED_FOR_MAX, 1)
        target = 1 + boost
    end

    State.motionScale = State.motionScale + ((target - State.motionScale) * MOTION_SCALE_LERP)
    if State.motionScale < 1 then
        State.motionScale = 1
    elseif State.motionScale > maxScale then
        State.motionScale = maxScale
    end
    State.lastMotionX = x
    State.lastMotionY = y
    return State.motionScale
end

local function UpdateCursorOverlay(db, x, y, elapsed)
    if not ShouldShowCursorOverlay(db) or not EnsureCursorFrames() then
        HideCursorOverlay()
        ResetMotionScale(x, y)
        return
    end

    local size = GetOverlaySizePixels(db) * UpdateMotionScale(db, x, y, elapsed)
    local texturePath
    State.cursorOverlay:ClearAllPoints()
    if db.cursorStyle == CURSOR_STYLE_RING_DOT then
        texturePath = GetComponentAsset("cursor\\ring-dot.tga")
    elseif db.cursorStyle == CURSOR_STYLE_INFRARED_LOCK then
        texturePath = GetComponentAsset("cursor\\overlay-infrared-lock.tga")
    else
        texturePath = GetComponentAsset("cursor\\overlay-rotating-triangle.tga")
        State.overlayRotation = (State.overlayRotation + ((elapsed or 0) * 2.6)) % 6.2831853071796
    end

    State.cursorOverlay:SetPoint("CENTER", _G.UIParent, "BOTTOMLEFT", x, y)
    State.cursorOverlay:SetSize(size, size)
    if texturePath and State.cursorOverlayTexture then
        State.cursorOverlayTexture:SetTexture(texturePath)
        if type(State.cursorOverlayTexture.SetRotation) == "function" then
            local rotation = db.cursorStyle == CURSOR_STYLE_ROTATING_TRIANGLE and State.overlayRotation or 0
            pcall(State.cursorOverlayTexture.SetRotation, State.cursorOverlayTexture, rotation)
        end
    end
    State.cursorOverlay:Show()
end

local function HideTrailObject(object)
    object.active = false
    if object.texture then
        object.texture:Hide()
    end
end

local function EnsureTrailPool(maxObjects)
    if not EnsureCursorFrames() then
        return false
    end

    maxObjects = tonumber(maxObjects) or 0
    if maxObjects < 0 then maxObjects = 0 end
    if maxObjects > 24 then maxObjects = 24 end

    for i = State.trailPoolSize + 1, maxObjects do
        local texture = State.trailLayer:CreateTexture(nil, "ARTWORK")
        texture:Hide()
        State.trailPool[i] = {
            texture = texture,
            active = false,
            x = 0,
            y = 0,
            age = 0,
            duration = 0,
            size = 0,
            drift = 0,
            mode = TRAIL_MODE_NONE,
        }
    end
    State.trailPoolSize = math.max(State.trailPoolSize, maxObjects)

    for i = maxObjects + 1, State.trailPoolSize do
        if State.trailPool[i] then
            HideTrailObject(State.trailPool[i])
        end
    end
    return true
end

local function ClearTrailObjects()
    for i = 1, State.trailPoolSize do
        local object = State.trailPool[i]
        if object then
            HideTrailObject(object)
        end
    end
    State.activeTrailCount = 0
end

local function GetTrailTexturePath(mode)
    if mode == TRAIL_MODE_STARS then
        return GetComponentAsset("cursor\\trail-star.tga")
    elseif mode == TRAIL_MODE_FOOTBALL then
        return GetComponentAsset("cursor\\trail-football.tga")
    end
    return GetComponentAsset("cursor\\trail-dot.tga")
end

local function AcquireTrailObject(maxObjects)
    local oldest
    local oldestAge = -1
    for i = 1, maxObjects do
        local object = State.trailPool[i]
        if object and not object.active then
            State.activeTrailCount = State.activeTrailCount + 1
            return object
        elseif object and object.age > oldestAge then
            oldest = object
            oldestAge = object.age
        end
    end
    return oldest
end

local function ConfigureTrailColor(object, mode, index)
    local texture = object.texture
    if not texture then
        return
    end

    if mode == TRAIL_MODE_STARS then
        texture:SetVertexColor(1, 0.86, 0.34, 1)
    elseif mode == TRAIL_MODE_FOOTBALL then
        texture:SetVertexColor(1, 1, 1, 1)
    else
        texture:SetVertexColor(1, 1, 1, 1)
    end
end

local function SpawnTrailObject(db, x, y, modeOverride)
    local settings = GetTrailQualitySettings(db)
    local maxObjects = settings.maxObjects
    local mode = modeOverride or db.trailMode
    if mode == TRAIL_MODE_NONE or not EnsureTrailPool(maxObjects) then
        return
    end

    State.trailSequence = State.trailSequence + 1
    local object = AcquireTrailObject(maxObjects)
    if not (object and object.texture) then
        return
    end

    local cursorSize = GetCursorSizePixels(db)
    local size = math.max(TRAIL_MIN_SIZE, cursorSize * TRAIL_STAR_SIZE_SCALE)
    if mode == TRAIL_MODE_FOOTBALL then
        size = math.max(TRAIL_MIN_SIZE, cursorSize * TRAIL_FOOTBALL_SIZE_SCALE)
    elseif mode == TRAIL_MODE_STARS then
        size = size * STAR_SIZE_SCALE[((State.trailSequence - 1) % #STAR_SIZE_SCALE) + 1]
    end

    object.active = true
    object.x = x
    object.y = y
    object.age = 0
    object.duration = settings.duration
    object.size = size
    object.drift = mode == TRAIL_MODE_STARS and STAR_DRIFT[((State.trailSequence - 1) % #STAR_DRIFT) + 1] or 0
    object.mode = mode

    object.texture:SetTexture(GetTrailTexturePath(mode))
    object.texture:SetAlpha(1)
    object.texture:SetSize(size, size)
    object.texture:ClearAllPoints()
    object.texture:SetPoint("CENTER", _G.UIParent, "BOTTOMLEFT", x, y)
    ConfigureTrailColor(object, mode, State.trailSequence)
    object.texture:Show()
end

local function UpdateTrailObjects(elapsed)
    if State.activeTrailCount <= 0 then
        return
    end

    local active = 0
    for i = 1, State.trailPoolSize do
        local object = State.trailPool[i]
        if object and object.active then
            object.age = object.age + elapsed
            if object.age >= object.duration then
                HideTrailObject(object)
            else
                active = active + 1
                local progress = object.age / object.duration
                local alpha = 1 - progress
                local size = object.size * (1 + progress * 0.35)
                local y = object.y - object.drift * progress
                object.texture:SetAlpha(alpha)
                object.texture:SetSize(size, size)
                object.texture:ClearAllPoints()
                object.texture:SetPoint("CENTER", _G.UIParent, "BOTTOMLEFT", object.x, y)
            end
        end
    end
    State.activeTrailCount = active
end

local function ResetModelTrailFrame(model)
    if not model then
        return
    end
    if type(model.ClearAllPoints) == "function" then pcall(model.ClearAllPoints, model) end
    if type(model.SetAllPoints) == "function" and _G.UIParent then pcall(model.SetAllPoints, model, _G.UIParent) end
    if type(model.ClearTransform) == "function" then pcall(model.ClearTransform, model) end
    if type(model.ClearModel) == "function" then pcall(model.ClearModel, model) end
    if type(model.SetScale) == "function" then pcall(model.SetScale, model, 1) end
    if type(model.SetModelScale) == "function" then pcall(model.SetModelScale, model, 1) end
    if type(model.SetPosition) == "function" then pcall(model.SetPosition, model, 0, 0, 0) end
    if type(model.SetFacing) == "function" then pcall(model.SetFacing, model, 0) end
    if type(model.SetPitch) == "function" then pcall(model.SetPitch, model, 0) end
    if type(model.SetRoll) == "function" then pcall(model.SetRoll, model, 0) end
    if type(model.SetAlpha) == "function" then pcall(model.SetAlpha, model, 0) end
end

local function HideModelTrailFrame(model)
    if not model then
        return
    end
    if type(model.SetAlpha) == "function" then pcall(model.SetAlpha, model, 0) end
end

local function CreateModelTrailFrame(frameLevel)
    if not (type(_G.CreateFrame) == "function" and _G.UIParent) then
        return nil
    end

    local ok, model = pcall(_G.CreateFrame, "PlayerModel", nil, _G.UIParent)
    if not (ok and model) then
        return nil
    end

    if type(model.SetAllPoints) == "function" then pcall(model.SetAllPoints, model, _G.UIParent) end
    if type(model.SetFrameStrata) == "function" then pcall(model.SetFrameStrata, model, "TOOLTIP") end
    if type(model.SetFrameLevel) == "function" then pcall(model.SetFrameLevel, model, frameLevel or 8998) end
    if type(model.EnableMouse) == "function" then pcall(model.EnableMouse, model, false) end
    if type(model.Hide) == "function" then pcall(model.Hide, model) end
    ResetModelTrailFrame(model)
    return model
end

local function EnsureModelTrailFrames()
    if State.modelTrailUnavailable then
        return false
    end
    if State.positionModelFrame and State.transformModelFrame then
        return true
    end

    State.positionModelFrame = State.positionModelFrame or CreateModelTrailFrame(8998)
    State.transformModelFrame = State.transformModelFrame or CreateModelTrailFrame(8997)
    if not (State.positionModelFrame and State.transformModelFrame) then
        State.modelTrailUnavailable = true
        HideModelTrailFrame(State.positionModelFrame)
        HideModelTrailFrame(State.transformModelFrame)
        return false
    end
    return true
end

local function GetModelTrailFrame(cursorMode)
    if cursorMode == MODEL_CURSOR_TRANSFORM then
        return State.transformModelFrame
    end
    return State.positionModelFrame
end

local function GetInactiveModelTrailFrame(cursorMode)
    if cursorMode == MODEL_CURSOR_TRANSFORM then
        return State.positionModelFrame
    end
    return State.transformModelFrame
end

local function HideModelTrail()
    HideModelTrailFrame(State.positionModelFrame)
    HideModelTrailFrame(State.transformModelFrame)
    State.modelTrailShown = false
end

local function ClearModelTrail()
    if State.positionModelFrame then
        ResetModelTrailFrame(State.positionModelFrame)
        HideModelTrailFrame(State.positionModelFrame)
    end
    if State.transformModelFrame then
        ResetModelTrailFrame(State.transformModelFrame)
        HideModelTrailFrame(State.transformModelFrame)
    end
    State.modelTrailMode = nil
    State.modelTrailCursorMode = nil
    State.modelTrailShown = false
    State.modelTrailFailedMode = nil
    State.modelTrailScreenW = nil
    State.modelTrailScreenH = nil
    State.modelTrailScreenScale = nil
    State.modelTrailScreenDiagonal = nil
    State.modelTrailFitDivisorX = nil
    State.modelTrailFitDivisorY = nil
    State.modelTrailVisualScale = nil
    State.modelTrailResolvedOffsetX = nil
    State.modelTrailResolvedOffsetY = nil
    State.modelTrailOffsetUnit = nil
    State.modelTrailSkewTop = nil
    State.modelTrailSkewBottom = nil
    State.modelTrailSkewSlope = nil
end

local function EnsureModelTrailVectors()
    if State.modelTrailPosVector and State.modelTrailRotVector then
        return true
    end
    if type(_G.CreateVector3D) ~= "function" then
        return false
    end

    local okPos, pos = pcall(_G.CreateVector3D, 0, 0, 0)
    local okRot, rot = pcall(_G.CreateVector3D, 0, 0, 0)
    if not (okPos and okRot and pos and rot) then
        return false
    end

    State.modelTrailPosVector = pos
    State.modelTrailRotVector = rot
    return true
end

local function GetModelTrailScreenMetrics()
    local parent = _G.UIParent
    if not parent then
        return nil
    end

    local scale = 1
    if type(parent.GetEffectiveScale) == "function" then
        local okScale, value = pcall(parent.GetEffectiveScale, parent)
        if okScale and type(value) == "number" and value > 0 then
            scale = value
        end
    end

    local width, height
    if type(parent.GetSize) == "function" then
        local okSize, w, h = pcall(parent.GetSize, parent)
        if okSize then
            width, height = w, h
        end
    end
    if (not width or width <= 0) and type(parent.GetWidth) == "function" then
        local okWidth, w = pcall(parent.GetWidth, parent)
        if okWidth then width = w end
    end
    if (not height or height <= 0) and type(parent.GetHeight) == "function" then
        local okHeight, h = pcall(parent.GetHeight, parent)
        if okHeight then height = h end
    end
    if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then
        return nil
    end

    local rawWidth = width * scale
    local rawHeight = height * scale
    local rawMidX = rawWidth * 0.5
    local rawMidY = rawHeight * 0.5
    local rawDiagonal = math.sqrt((rawWidth * rawWidth) + (rawHeight * rawHeight))
    if rawDiagonal <= 0 then
        rawDiagonal = 1
    end
    return width, height, rawMidX, rawMidY, scale, rawDiagonal
end

function State.CorrectPositionModelCursor(rawX, rawY, screenMidX, screenMidY, screenH)
    local skewTop, skewBottom = State.modelTrailSkewTop, State.modelTrailSkewBottom
    if not (skewTop and skewBottom) then
        return rawX, rawY
    end

    local dx = rawX - screenMidX
    local dy = rawY - screenMidY
    local fitRawX = rawX
    local fitRawY = rawY
    if screenH > 0 then
        local blend = rawY / screenH
        fitRawX = screenMidX + (dx * (skewBottom + ((skewTop - skewBottom) * blend)))
    end

    local quarterY = screenH * 0.25
    if quarterY > 0 then
        if dy < 0 then
            if dy > -quarterY then
                fitRawY = screenMidY + (dy * 1.077)
            else
                fitRawY = screenMidY + ((((dy + quarterY) * 1.057) - quarterY) * 1.077)
            end
        elseif dy < quarterY then
            fitRawY = screenMidY + (dy * 1.015)
        else
            fitRawY = screenMidY + ((((dy - quarterY) * 0.952) + quarterY) * 1.015)
        end
    end

    local skewSlope = State.modelTrailSkewSlope or 0
    if skewSlope ~= 0 and screenMidX ~= 0 then
        fitRawY = fitRawY - (skewSlope * dx / screenMidX)
    end

    return fitRawX, fitRawY
end

local function ApplyModelTrailSettings(model, config, screenW, screenH, screenScale, screenDiagonal)
    local userScale = config.userScale or 1
    if userScale <= 0 then
        userScale = 1
    end

    local modelScale = config.modelScale or 1
    if modelScale <= 0 then
        modelScale = 1
    end

    local finalModelScale = userScale * modelScale
    State.modelTrailScale = finalModelScale
    State.modelTrailRotX = math.rad(config.rotationX or 0)
    State.modelTrailRotY = math.rad(config.rotationY or 0)
    State.modelTrailRotZ = math.rad(config.rotationZ or 0)
    State.modelTrailOffsetX = config.offsetX or config.modelOffsetX or 0
    State.modelTrailOffsetY = config.offsetY or config.modelOffsetY or 0
    State.modelTrailOffsetZ = config.offsetZ or 0
    State.modelTrailFitDivisorX = nil
    State.modelTrailFitDivisorY = nil
    State.modelTrailVisualScale = finalModelScale
    State.modelTrailResolvedOffsetX = State.modelTrailOffsetX
    State.modelTrailResolvedOffsetY = State.modelTrailOffsetY
    State.modelTrailOffsetUnit = nil
    State.modelTrailSkewTop = nil
    State.modelTrailSkewBottom = nil
    State.modelTrailSkewSlope = nil

    if type(model.ClearTransform) == "function" then pcall(model.ClearTransform, model) end
    if type(model.SetScale) == "function" then pcall(model.SetScale, model, 1) end
    if type(model.SetModelScale) == "function" then pcall(model.SetModelScale, model, 1) end
    if type(model.SetSize) == "function" then pcall(model.SetSize, model, screenW, screenH) end
    if config.cursorMode == MODEL_CURSOR_TRANSFORM then
        if type(model.UseModelCenterToTransform) == "function" then pcall(model.UseModelCenterToTransform, model, true) end
        if EnsureModelTrailVectors() and type(model.SetTransform) == "function" then
            State.modelTrailPosVector:SetXYZ(State.modelTrailOffsetX, State.modelTrailOffsetY, State.modelTrailOffsetZ)
            State.modelTrailRotVector:SetXYZ(State.modelTrailRotX, State.modelTrailRotY, State.modelTrailRotZ)
            pcall(model.SetTransform, model, State.modelTrailPosVector, State.modelTrailRotVector, State.modelTrailScale or 1)
        end
    else
        State.modelTrailVisualScale = finalModelScale

        local cursorStepX = config.cursorStepX or 3430
        local cursorStepY = config.cursorStepY or 3150
        if cursorStepX <= 0 then cursorStepX = 3430 end
        if cursorStepY <= 0 then cursorStepY = 3150 end
        State.modelTrailOffsetUnit = config.modelUnit or 0.0001
        State.modelTrailFitDivisorX = screenDiagonal * cursorStepX * State.modelTrailOffsetUnit * finalModelScale
        State.modelTrailFitDivisorY = screenDiagonal * cursorStepY * State.modelTrailOffsetUnit * finalModelScale
        if State.modelTrailFitDivisorX <= 0 then State.modelTrailFitDivisorX = 1 end
        if State.modelTrailFitDivisorY <= 0 then State.modelTrailFitDivisorY = 1 end

        State.modelTrailResolvedOffsetX = ((config.modelOffsetX or 0) * State.modelTrailOffsetUnit * screenDiagonal / modelScale / userScale)
        State.modelTrailResolvedOffsetY = ((config.modelOffsetY or 0) * State.modelTrailOffsetUnit * screenDiagonal / modelScale / userScale)
        State.modelTrailSkewTop = config.skewTop
        State.modelTrailSkewBottom = config.skewBottom
        State.modelTrailSkewSlope = config.skewSlope or 0

        if type(model.SetScale) == "function" then pcall(model.SetScale, model, State.modelTrailVisualScale or finalModelScale) end
        if type(model.SetFacing) == "function" then pcall(model.SetFacing, model, State.modelTrailRotX or 0) end
        if type(model.SetPitch) == "function" then pcall(model.SetPitch, model, State.modelTrailRotY or 0) end
        if type(model.SetRoll) == "function" then pcall(model.SetRoll, model, State.modelTrailRotZ or 0) end
        if type(model.SetPosition) == "function" then
            pcall(model.SetPosition, model, State.modelTrailOffsetZ, State.modelTrailResolvedOffsetX, State.modelTrailResolvedOffsetY)
        end
    end

    State.modelTrailScreenW = screenW
    State.modelTrailScreenH = screenH
    State.modelTrailScreenScale = screenScale
    State.modelTrailScreenDiagonal = screenDiagonal
end

local function SetModelTrailMode(mode, screenW, screenH, screenScale, screenDiagonal)
    local config = MODEL_TRAIL_SETTINGS[mode]
    if not config or State.modelTrailFailedMode == mode then
        HideModelTrail()
        return nil
    end
    if not EnsureModelTrailFrames() then
        return nil
    end

    local model = GetModelTrailFrame(config.cursorMode)
    local inactiveModel = GetInactiveModelTrailFrame(config.cursorMode)
    if not model then
        HideModelTrail()
        return nil
    end

    local modeChanged = State.modelTrailMode ~= mode or State.modelTrailCursorMode ~= config.cursorMode
    if modeChanged then
        if inactiveModel then
            ResetModelTrailFrame(inactiveModel)
            HideModelTrailFrame(inactiveModel)
        end
        ResetModelTrailFrame(model)
        local ok = type(model.SetModel) == "function" and pcall(model.SetModel, model, config.modelID)
        if not ok then
            State.modelTrailFailedMode = mode
            HideModelTrail()
            return nil
        end
        if type(model.SetCustomCamera) == "function" then
            pcall(model.SetCustomCamera, model, 1)
        end
        if config.cursorMode == MODEL_CURSOR_TRANSFORM then
            if type(model.SetCamDistanceScale) == "function" then
                pcall(model.SetCamDistanceScale, model, 1)
            end
        end

        State.modelTrailMode = mode
        State.modelTrailCursorMode = config.cursorMode
        State.modelTrailShown = false
    end
    if modeChanged
        or State.modelTrailScreenW ~= screenW
        or State.modelTrailScreenH ~= screenH
        or State.modelTrailScreenScale ~= screenScale
        or State.modelTrailScreenDiagonal ~= screenDiagonal then
        ApplyModelTrailSettings(model, config, screenW, screenH, screenScale, screenDiagonal)
    end

    return config, model
end

local function UpdateModelTrail(db, rawX, rawY)
    local mode = db and db.trailMode
    if not IsModelTrailMode(mode) then
        HideModelTrail()
        return
    end
    if type(rawX) ~= "number" or type(rawY) ~= "number" then
        HideModelTrail()
        return
    end

    local screenW, screenH, screenMidX, screenMidY, uiScale, screenDiagonal = GetModelTrailScreenMetrics()
    if not screenW then
        HideModelTrail()
        return
    end

    local config, model = SetModelTrailMode(mode, screenW, screenH, uiScale, screenDiagonal)
    if not (config and model and _G.UIParent) then
        HideModelTrail()
        return
    end

    if config.cursorMode == MODEL_CURSOR_TRANSFORM then
        if not (State.modelTrailPosVector and State.modelTrailRotVector and type(model.SetTransform) == "function") then
            HideModelTrail()
            return
        end
        local modelX = (rawX / screenDiagonal) + (State.modelTrailOffsetX or 0)
        local modelY = (rawY / screenDiagonal) + (State.modelTrailOffsetY or 0)
        State.modelTrailPosVector:SetXYZ(modelX, modelY, State.modelTrailOffsetZ or 0)
        State.modelTrailRotVector:SetXYZ(State.modelTrailRotX or 0, State.modelTrailRotY or 0, State.modelTrailRotZ or 0)
        pcall(model.SetTransform, model, State.modelTrailPosVector, State.modelTrailRotVector, State.modelTrailScale or 1)
    elseif config.cursorMode == MODEL_CURSOR_POSITION then
        if type(model.SetPosition) ~= "function" then
            HideModelTrail()
            return
        end
        local divisorX = State.modelTrailFitDivisorX or 1
        local divisorY = State.modelTrailFitDivisorY or 1
        if divisorX <= 0 then divisorX = 1 end
        if divisorY <= 0 then divisorY = 1 end

        local fitRawX, fitRawY = State.CorrectPositionModelCursor(rawX, rawY, screenMidX, screenMidY, screenH)

        local modelX = ((fitRawX - screenMidX) / divisorX) + (State.modelTrailResolvedOffsetX or 0)
        local modelY = ((fitRawY - screenMidY) / divisorY) + (State.modelTrailResolvedOffsetY or 0)
        pcall(model.SetPosition, model, State.modelTrailOffsetZ or 0, modelX, modelY)
    else
        HideModelTrail()
        return
    end

    if type(model.SetAlpha) == "function" then pcall(model.SetAlpha, model, MODEL_TRAIL.alpha) end
    if not State.modelTrailShown then
        if type(model.Show) == "function" then pcall(model.Show, model) end
        State.modelTrailShown = true
    end
end

local function UpdateTrail(db, elapsed, x, y)
    local mode = db.trailMode
    if not IsTextureTrailMode(mode) then
        return
    end

    local settings = GetTrailQualitySettings(db)
    if State.lastCursorX and State.lastCursorY then
        local dx = x - State.lastCursorX
        local dy = y - State.lastCursorY
        if (dx * dx + dy * dy) >= (settings.distance * settings.distance) then
            SpawnTrailObject(db, x, y, mode)
            State.lastCursorX = x
            State.lastCursorY = y
            State.idleTrailWatcher = false
        elseif State.activeTrailCount == 0 then
            State.idleTrailWatcher = true
        end
    else
        State.lastCursorX = x
        State.lastCursorY = y
    end

    UpdateTrailObjects(elapsed)
end

local function StopCursorDriver()
    if State.cursorRoot and State.cursorDriverActive then
        State.cursorRoot:SetScript("OnUpdate", nil)
    end
    if State.cursorRoot then
        State.cursorRoot:Hide()
    end
    State.cursorDriverActive = false
    State.cursorDriverElapsed = 0
    ResetMotionScale(nil, nil)
end

local function CursorDriverOnUpdateImpl(_, elapsed)
    local db = GetDB()
    if not ShouldRunCursorDriver(db) then
        HideCursorOverlay()
        ClearTrailObjects()
        ClearModelTrail()
        StopCursorDriver()
        return
    end

    local interval = GetCursorDriverInterval(db)
    State.cursorDriverElapsed = State.cursorDriverElapsed + elapsed
    if State.cursorDriverElapsed < interval then
        return
    end

    local step = State.cursorDriverElapsed
    State.cursorDriverElapsed = 0
    local x, y, rawX, rawY = GetCursorPositions()
    if not x or not y then
        return
    end

    UpdateCursorOverlay(db, x, y, step)
    UpdateTrail(db, step, x, y)
    UpdateModelTrail(db, rawX, rawY)
end

local function CursorDriverOnUpdate(frame, elapsed)
    local cpuWatchdog = YUI.CPUWatchdog
    local cpuStartedAt = cpuWatchdog and cpuWatchdog.timingActive and cpuWatchdog:BeginProbeTiming()
    CursorDriverOnUpdateImpl(frame, elapsed)
    if cpuStartedAt then cpuWatchdog:EndProbeTiming("component.mouse-enhancement", cpuStartedAt) end
end

local function StartCursorDriver()
    if not EnsureCursorFrames() or State.cursorDriverActive then
        return
    end
    State.cursorRoot:SetScript("OnUpdate", CursorDriverOnUpdate)
    State.cursorRoot:Show()
    State.cursorDriverActive = true
end

if YUI.CPUWatchdog and YUI.CPUWatchdog.RegisterProbe then
    YUI.CPUWatchdog:RegisterProbe("component.mouse-enhancement", {
        localeKey = "cpu_watch.probe.mouse",
        kind = "frame",
        getTarget = function() return State.cursorRoot end,
        snapshot = function()
            return {
                running = State.cursorDriverActive == true,
                activeTrails = State.activeTrailCount or 0,
            }
        end,
    })
end

local function ApplyNativeCursorSize(db)
    if not State.AreCursorEffectsEnabled(db) then
        State.nativeCursorSizeLastValue = nil
        return
    end
    if type(_G.GetCVar) ~= "function" or type(_G.SetCVar) ~= "function" then
        return
    end

    local value = GetNativeCursorSizeValue(db)
    if State.nativeCursorSizeLastValue == value then
        return
    end

    local okGet, current = pcall(_G.GetCVar, NATIVE_CURSOR_SIZE_CVAR)
    if not okGet or current == nil then
        return
    end
    if tostring(current) == tostring(value) then
        State.nativeCursorSizeLastValue = value
        return
    end

    local okSet = pcall(_G.SetCVar, NATIVE_CURSOR_SIZE_CVAR, value)
    if okSet then
        State.nativeCursorSizeLastValue = value
    end
end

local function RefreshCursorRuntime()
    State.RefreshCursorHousingState()

    if not State.featureEnabled then
        HideCursorOverlay()
        ClearTrailObjects()
        ClearModelTrail()
        StopCursorDriver()
        State.nativeCursorSizeLastValue = nil
        return
    end

    local db = GetDB()
    if not State.AreCursorEffectsEnabled(db) then
        HideCursorOverlay()
        ClearTrailObjects()
        ClearModelTrail()
        StopCursorDriver()
        State.nativeCursorSizeLastValue = nil
        return
    end

    ApplyNativeCursorSize(db)

    if IsTextureTrailMode(db.trailMode) then
        ClearModelTrail()
        State.lastCursorX = nil
        State.lastCursorY = nil
        State.idleTrailWatcher = false
    else
        ClearTrailObjects()
        State.lastCursorX = nil
        State.lastCursorY = nil
        State.idleTrailWatcher = false
        if not IsModelTrailMode(db.trailMode) then
            ClearModelTrail()
        end
    end

    if ShouldRunCursorDriver(db) then
        StartCursorDriver()
    else
        HideCursorOverlay()
        ClearTrailObjects()
        ClearModelTrail()
        StopCursorDriver()
    end
end

local function SafeBoolMethod(object, methodName)
    if type(object) ~= "table" or type(object[methodName]) ~= "function" then
        return false
    end
    local ok, value = pcall(object[methodName], object)
    return ok and value == true
end

local function IsAddonLoadedSafe(addonName)
    if type(addonName) ~= "string" then
        return false
    end

    if _G.C_AddOns and type(_G.C_AddOns.IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(_G.C_AddOns.IsAddOnLoaded, addonName)
        if ok then
            return loaded == true
        end
    end

    if type(_G.IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(_G.IsAddOnLoaded, addonName)
        if ok then
            return loaded == true
        end
    end

    return false
end

local function IsModifierDown(modifier)
    if modifier == MOD_SHIFT then
        return type(_G.IsShiftKeyDown) == "function" and _G.IsShiftKeyDown() == true
    elseif modifier == MOD_CTRL then
        return type(_G.IsControlKeyDown) == "function" and _G.IsControlKeyDown() == true
    elseif modifier == MOD_ALT then
        return type(_G.IsAltKeyDown) == "function" and _G.IsAltKeyDown() == true
    end
    return false
end

State.ShouldDisplayPlayerMythicPlus = function(db)
    if not State.featureEnabled or YUI.IsRetail ~= true or db.playerTooltipMythicPlusEnabled == false then
        return false
    end
    if db.playerTooltipModifier ~= "NONE" then
        return IsModifierDown(db.playerTooltipModifier)
    end
    return true
end

local function ShouldDisplayID()
    if not State.featureEnabled then
        return false
    end

    local db = GetDB()
    if db.tooltipIDEnabled ~= true then
        return false
    end
    if db.displayMode == MODE_MODIFIER then
        return IsModifierDown(db.modifierKey)
    end
    return true
end

local function ExternalModifierShows(value, defaultOnUnknown)
    if value == "SHOW" or value == "none" then
        return true
    elseif value == "HIDE" then
        return false
    elseif value == "SHIFT" or value == "shift" then
        return IsModifierDown(MOD_SHIFT)
    elseif value == "CTRL" or value == "control" then
        return IsModifierDown(MOD_CTRL)
    elseif value == "ALT" or value == "alt" then
        return IsModifierDown(MOD_ALT)
    end
    return defaultOnUnknown == true
end

local function ShouldYieldToPrimaryUI()
    if not (IsAddonLoadedSafe(ADDON_ELV) or type(_G.ElvUI) == "table") then
        return false
    end

    local ok, result = pcall(function()
        local elv = type(_G.ElvUI) == "table" and _G.ElvUI[1] or nil
        if elv and elv.private and elv.private.tooltip and elv.private.tooltip.enable == false then
            return false
        end

        local tooltipDB = elv and elv.db and elv.db.tooltip
        if type(tooltipDB) ~= "table" then
            return true
        end
        return ExternalModifierShows(tooltipDB.modifierID, true)
    end)

    if not ok then
        return true
    end
    return result == true
end

local function GetPlayerNameVariants()
    local variants = {}
    local name, realm

    if type(_G.UnitFullName) == "function" then
        local ok, unitName, unitRealm = pcall(_G.UnitFullName, "player")
        if ok then
            name, realm = unitName, unitRealm
        end
    end
    if (not name or name == "") and type(_G.UnitName) == "function" then
        local ok, unitName = pcall(_G.UnitName, "player")
        if ok then name = unitName end
    end
    if (not realm or realm == "") and type(_G.GetRealmName) == "function" then
        local ok, realmName = pcall(_G.GetRealmName)
        if ok then realm = realmName end
    end

    if name and name ~= "" then
        variants[#variants + 1] = name
        if realm and realm ~= "" then
            variants[#variants + 1] = name .. "-" .. realm
            variants[#variants + 1] = name .. "-" .. realm:gsub("%s+", "")
        end
    end

    return variants
end

local function ResolveSecondaryUIDB()
    local accountDB = _G.NDuiADB
    if type(accountDB) ~= "table" or type(accountDB.ProfileIndex) ~= "table" then
        return nil
    end

    local index
    local variants = GetPlayerNameVariants()
    for _, key in ipairs(variants) do
        index = accountDB.ProfileIndex[key]
        if index ~= nil then
            break
        end
    end

    index = tonumber(index)
    if not index then
        return nil
    end
    if index <= 1 then
        return type(_G.NDuiDB) == "table" and _G.NDuiDB or nil
    end

    local profiles = _G.NDuiPDB
    return type(profiles) == "table" and type(profiles[index - 1]) == "table" and profiles[index - 1] or nil
end

local function ShouldYieldToSecondaryUI()
    if not (IsAddonLoadedSafe(ADDON_ND) or type(_G.NDuiDB) == "table" or type(_G.NDuiADB) == "table") then
        return false
    end

    local ok, result = pcall(function()
        local db = ResolveSecondaryUIDB()
        if type(db) ~= "table" or type(db.Tooltip) ~= "table" then
            return true
        end
        return db.Tooltip.HideAllID ~= true
    end)

    if not ok then
        return true
    end
    return result == true
end

local function GetUtilityUIDB()
    if type(_G.EnhanceQoL) == "table" and type(_G.EnhanceQoL.db) == "table" then
        return _G.EnhanceQoL.db
    end
    if type(_G.EnhanceQoLTooltip) == "table" and type(_G.EnhanceQoLTooltip.db) == "table" then
        return _G.EnhanceQoLTooltip.db
    end
    return nil
end

local function AnyFlagEnabled(db, keys)
    if type(db) ~= "table" or type(keys) ~= "table" then
        return false
    end
    for _, key in ipairs(keys) do
        if db[key] == true then
            return true
        end
    end
    return false
end

local function UtilityUIModifierAllows(db)
    if type(db) ~= "table" then
        return true
    end
    if db.TooltipIDRequireModifier ~= true then
        return true
    end
    return ExternalModifierShows(db.TooltipIDModifier or "ALT", true)
end

local function ShouldYieldToUtilityUI(kind)
    if not (IsAddonLoadedSafe(ADDON_EQOL) or IsAddonLoadedSafe(ADDON_EQOL_TOOLTIP) or type(_G.EnhanceQoL) == "table") then
        return false
    end

    local ok, result = pcall(function()
        local db = GetUtilityUIDB()
        if type(db) ~= "table" then
            return true
        end

        if not AnyFlagEnabled(db, EQOL_FLAGS[kind] or EQOL_FLAGS.spell) then
            return false
        end
        return UtilityUIModifierAllows(db)
    end)

    if not ok then
        return true
    end
    return result == true
end

local function ShouldYieldToCompactUI(kind)
    if kind ~= "item" and kind ~= "spell" and kind ~= "aura" and kind ~= "macro" then
        return false
    end
    if not (IsAddonLoadedSafe(ADDON_EUI) or type(_G.EllesmereUI) == "table") then
        return false
    end

    local ok, result = pcall(function()
        local db = _G.EllesmereUIDB
        if type(db) ~= "table" then
            return true
        end
        if db.showSpellID ~= true then
            return false
        end
        return ExternalModifierShows(db.spellIDModifier or "none", true)
    end)

    if not ok then
        return true
    end
    return result == true
end

local function ShouldYieldToKnownAddon(kind)
    local checks = {
        ShouldYieldToPrimaryUI,
        ShouldYieldToSecondaryUI,
        ShouldYieldToUtilityUI,
        ShouldYieldToCompactUI,
    }

    for _, checker in ipairs(checks) do
        local ok, result = pcall(checker, kind)
        if not ok or result == true then
            return true
        end
    end
    return false
end

local function IsSecretValue(value)
    if type(_G.issecretvalue) ~= "function" then
        return false
    end
    local ok, secret = pcall(_G.issecretvalue, value)
    return ok and secret == true
end

local function SafeStringValue(value)
    local security = YUI.API and YUI.API.Security
    if security and type(security.SafeString) == "function" then
        local ok, text = pcall(security.SafeString, value)
        if ok and type(text) == "string" and not IsSecretValue(text) then
            return text
        end
        if ok and text == nil then
            return nil
        end
    end

    if IsSecretValue(value) or value == nil then
        return nil
    end
    if type(value) == "string" then
        return value
    end
    return nil
end

local function SafeNonEmptyString(value)
    local text = SafeStringValue(value)
    if text and text ~= "" then
        return text
    end
    return nil
end

local function NormalizeID(id)
    if IsSecretValue(id) then
        return nil
    end

    if type(id) == "number" and id > 0 then
        return tostring(math.floor(id))
    end

    local text = SafeStringValue(id)
    if text then
        return text:match("^(%d+)$")
    end
    return nil
end

local function NormalizeTooltipRightText(text)
    text = SafeNonEmptyString(text)
    if not text then
        return nil
    end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end
    return text
end

local function FormatIDLineText(id)
    return ID_LABEL_PREFIX .. ID_NUMBER_COLOR_CODE .. id .. ID_COLOR_CLOSE
end

local function WrapColor(text, color)
    if not (type(text) == "string" and type(color) == "table" and type(color.r) == "number" and type(color.g) == "number" and type(color.b) == "number") then
        return text
    end

    local r = math.min(255, math.max(0, math.floor(color.r * 255 + 0.5)))
    local g = math.min(255, math.max(0, math.floor(color.g * 255 + 0.5)))
    local b = math.min(255, math.max(0, math.floor(color.b * 255 + 0.5)))
    return string.format("|cff%02x%02x%02x%s|r", r, g, b, text)
end

local function GetUnitClassColor(unit)
    unit = SafeNonEmptyString(unit)
    if not unit or type(_G.UnitClass) ~= "function" then
        return nil
    end

    local ok, _, classFile = pcall(_G.UnitClass, unit)
    classFile = SafeNonEmptyString(ok and classFile or nil)
    if not classFile then
        return nil
    end

    local colors = _G.RAID_CLASS_COLORS
    return type(colors) == "table" and colors[classFile] or nil
end

local function GetUnitDisplayName(unit)
    unit = SafeNonEmptyString(unit)
    if not unit or type(_G.UnitName) ~= "function" then
        return nil
    end

    local ok, name = pcall(_G.UnitName, unit)
    name = SafeNonEmptyString(ok and name or nil)
    if not name then
        return nil
    end
    return WrapColor(name, GetUnitClassColor(unit))
end

local function CanMutateTooltip(tt)
    if not tt then
        return false
    end
    if SafeBoolMethod(tt, "IsForbidden") then
        return false
    end
    return type(tt.AddLine) == "function" and type(tt.Show) == "function"
end

local function StripTooltipText(text)
    text = SafeNonEmptyString(text)
    if not text then
        return nil
    end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function GetTooltipName(tt)
    if not (tt and type(tt.GetName) == "function") then
        return nil
    end
    local ok, name = pcall(tt.GetName, tt)
    if ok and type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

local function TooltipHasIDText(text, id)
    text = StripTooltipText(text)
    if not text then
        return false
    end

    local compact = text:gsub("%s+", "")
    local lower = compact:lower()
    if not lower:find(id, 1, true) then
        return false
    end

    return lower:find("id:" .. id, 1, true)
        or lower:find("id" .. id, 1, true)
        or lower:find("spellid:" .. id, 1, true)
        or lower:find("spellid" .. id, 1, true)
        or lower:find("itemid:" .. id, 1, true)
        or lower:find("itemid" .. id, 1, true)
        or lower:find("npcid:" .. id, 1, true)
        or lower:find("npcid" .. id, 1, true)
        or lower:find("questid:" .. id, 1, true)
        or lower:find("questid" .. id, 1, true)
        or lower:find("currencyid:" .. id, 1, true)
        or lower:find("currencyid" .. id, 1, true)
        or compact:find("法术ID", 1, true) and compact:find(id, 1, true)
        or compact:find("法術ID", 1, true) and compact:find(id, 1, true)
        or compact:find("物品ID", 1, true) and compact:find(id, 1, true)
        or compact:find("任务ID", 1, true) and compact:find(id, 1, true)
        or compact:find("任務ID", 1, true) and compact:find(id, 1, true)
        or compact:find("货币ID", 1, true) and compact:find(id, 1, true)
        or compact:find("貨幣ID", 1, true) and compact:find(id, 1, true)
        or compact:find("NPCID", 1, true) and compact:find(id, 1, true)
end

local function ReadTooltipRegionText(region)
    if not (region and type(region.GetText) == "function") then
        return nil
    end

    local ok, text = pcall(region.GetText, region)
    if not ok then
        return nil
    end
    return SafeStringValue(text)
end

local function FindTooltipIDLine(tt, id, ownLineText, spellOnly)
    local name = GetTooltipName(tt)
    if not name or not (tt and type(tt.NumLines) == "function") then
        return nil
    end

    local ok, numLines = pcall(tt.NumLines, tt)
    if not ok or IsSecretValue(numLines) or type(numLines) ~= "number" then
        return nil
    end

    local hasForeignLine = false
    for i = 1, numLines do
        local left = _G[name .. "TextLeft" .. i]
        local right = _G[name .. "TextRight" .. i]
        local leftText = ReadTooltipRegionText(left)
        local rightText = ReadTooltipRegionText(right)
        if leftText == ownLineText then
            return "owned", right, left
        end
        local text = (leftText or "") .. " " .. (rightText or "")
        if spellOnly then
            -- Item and spell IDs can share the same number; require a spell label.
            text = StripTooltipText(text)
            text = text and text:gsub("%s+", ""):gsub("：", ":"):lower() or ""
            local spellID = text:match("spellid:?(%d+)")
                or text:match("法术id:?(%d+)")
                or text:match("法術id:?(%d+)")
            if spellID == id then hasForeignLine = true end
        elseif TooltipHasIDText(text, id) then
            hasForeignLine = true
        end
    end
    return hasForeignLine and "foreign" or nil
end

local function UpdateOwnedIDLineRightText(tt, right, rightText)
    if not (rightText and right and type(right.SetText) == "function") then
        return false
    end
    if ReadTooltipRegionText(right) == rightText then
        return true
    end

    local ok = pcall(right.SetText, right, rightText)
    if not ok then
        return false
    end
    if type(right.Show) == "function" then
        pcall(right.Show, right)
    end
    if tt and type(tt.Show) == "function" then
        pcall(tt.Show, tt)
    end
    return true
end

local function AddIDLine(tt, id, kind, rightText)
    id = NormalizeID(id)
    if not id or not CanMutateTooltip(tt) or not ShouldDisplayID() then
        return
    end
    kind = kind or "spell"

    rightText = NormalizeTooltipRightText(rightText)
    local lineText = FormatIDLineText(id)
    local lineKind, right = FindTooltipIDLine(tt, id, lineText)
    if lineKind == "owned" then
        UpdateOwnedIDLineRightText(tt, right, rightText)
        return
    end

    if lineKind == "foreign" or ShouldYieldToKnownAddon(kind) then
        return
    end

    tt:AddLine(" ")
    if type(tt.AddDoubleLine) == "function" then
        tt:AddDoubleLine(lineText, rightText or "", 1, 1, 1, 1, 1, 1)
    else
        tt:AddLine(lineText, 1, 1, 1)
    end
    tt:Show()
end

State.AddItemIDLines = function(tt, itemID)
    itemID = NormalizeID(itemID)
    AddIDLine(tt, itemID, "item")
    if not itemID or not CanMutateTooltip(tt) or not ShouldDisplayID()
        or GetDB().itemSpellIDEnabled ~= true then
        return
    end

    local itemAPI = YUI.API and YUI.API.Item
    if not (itemAPI and type(itemAPI.GetSpell) == "function") then return end
    local ok, _, spellID = pcall(itemAPI.GetSpell, tonumber(itemID))
    if not ok then return end
    spellID = NormalizeID(spellID)
    if not spellID or tonumber(spellID) <= 0 then return end

    local lineText = "|cffFF6666" .. T("tooltip.item_spell_id", "法术ID") .. ":|r "
        .. ID_NUMBER_COLOR_CODE .. spellID .. ID_COLOR_CLOSE
    if not FindTooltipIDLine(tt, spellID, lineText, true) then
        if type(tt.AddDoubleLine) == "function" then
            tt:AddDoubleLine(lineText, "", 1, 1, 1, 1, 1, 1)
        else
            tt:AddLine(lineText, 1, 1, 1)
        end
    end

    -- Expand only our own item label once a spell line is actually present.
    local itemLineKind, _, itemLabel = FindTooltipIDLine(tt, itemID, FormatIDLineText(itemID))
    if itemLineKind == "owned" and itemLabel and type(itemLabel.SetText) == "function" then
        local itemText = "|cffFF6666" .. T("tooltip.item_id", "物品ID") .. ":|r "
            .. ID_NUMBER_COLOR_CODE .. itemID .. ID_COLOR_CLOSE
        pcall(itemLabel.SetText, itemLabel, itemText)
    end
    tt:Show()
end

local function GetNPCIDFromGUID(guid)
    guid = SafeNonEmptyString(guid)
    if not guid then
        return nil
    end

    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    if unitType == "Creature" or unitType == "Vehicle" then
        return NormalizeID(npcID)
    end
    return nil
end

local function GetTooltipUnit(tt)
    if tt and type(tt.GetUnit) == "function" then
        local ok, _, unit = pcall(tt.GetUnit, tt)
        local safeUnit = SafeNonEmptyString(ok and unit or nil)
        if safeUnit then
            return safeUnit
        end
    end
    if type(_G.UnitExists) == "function" then
        local ok, exists = pcall(_G.UnitExists, "mouseover")
        if ok and exists then
            return "mouseover"
        end
    end
    return nil
end

local function AddNPCIDFromTooltip(tt, data)
    local guid = type(data) == "table" and SafeStringValue(data.guid) or nil
    if not guid then
        local unit = GetTooltipUnit(tt)
        if unit and type(_G.UnitGUID) == "function" then
            local ok, value = pcall(_G.UnitGUID, unit)
            if ok then guid = value end
        end
    end
    AddIDLine(tt, GetNPCIDFromGUID(guid), "npc")
end

local function ExtractHyperlinkID(link)
    link = SafeNonEmptyString(link)
    if not link then
        return nil, nil
    end
    local linkType, id = link:match("^(%a+):(%d+)")
    if not linkType then
        linkType, id = link:match("|H(%a+):(%d+)")
    end
    if not linkType or not id then
        return nil, nil
    end

    if linkType == "item" then
        return id, "item"
    elseif linkType == "spell" or linkType == "enchant" or linkType == "trade" then
        return id, "spell"
    elseif linkType == "currency" then
        return id, "currency"
    elseif linkType == "quest" then
        return id, "quest"
    end
    return nil, nil
end

local function AddIDFromHyperlink(tt, link)
    local id, kind = ExtractHyperlinkID(link)
    if kind == "item" then
        State.AddItemIDLines(tt, id)
    else
        AddIDLine(tt, id, kind)
    end
end

local function GetItemIDFromTooltip(tt)
    if tt and type(tt.GetItem) == "function" then
        local ok, _, link = pcall(tt.GetItem, tt)
        if ok then
            local id = ExtractHyperlinkID(link)
            return id
        end
    end
    return nil
end

local function GetSpellIDFromTooltip(tt)
    if tt and type(tt.GetSpell) == "function" then
        local ok, _, id = pcall(tt.GetSpell, tt)
        if ok then
            return id
        end
    end
    return nil
end

local function GetAuraInfoByIndex(unit, index, filter)
    if index == nil then
        return nil, nil
    end
    local unitAPI = YUI.API and YUI.API.Unit
    if not (unitAPI and unitAPI.ReadAuraIdentityByIndex) then
        return nil, nil
    end
    local identity = unitAPI.ReadAuraIdentityByIndex(unit, index, filter)
    if not identity then return nil, nil end
    return identity.spellID, GetUnitDisplayName(identity.sourceUnit)
end

local function GetAuraInfoByInstance(unit, auraInstanceID)
    if auraInstanceID == nil then
        return nil, nil
    end

    local unitAPI = YUI.API and YUI.API.Unit
    if not (unitAPI and unitAPI.ReadAuraIdentityByInstance) then
        return nil, nil
    end
    local identity = unitAPI.ReadAuraIdentityByInstance(unit, auraInstanceID)
    if not identity then return nil, nil end
    return identity.spellID, GetUnitDisplayName(identity.sourceUnit)
end

local function AddQuestIDFromFrame(frame)
    if not (_G.GameTooltip and _G.GameTooltip.IsShown and _G.GameTooltip:IsShown()) then
        return
    end

    local questID = frame and frame.questID
    if not questID and frame and frame.questLogIndex and _G.C_QuestLog and type(_G.C_QuestLog.GetQuestIDForLogIndex) == "function" then
        local ok, value = pcall(_G.C_QuestLog.GetQuestIDForLogIndex, frame.questLogIndex)
        if ok then questID = value end
    end
    AddIDLine(_G.GameTooltip, questID, "quest")
end

local function AddCurrencyTokenID(tt, index)
    if not (_G.C_CurrencyInfo and index) then
        return
    end

    if type(_G.C_CurrencyInfo.GetCurrencyListLink) == "function" then
        local ok, link = pcall(_G.C_CurrencyInfo.GetCurrencyListLink, index)
        if ok then
            local id = ExtractHyperlinkID(link)
            if id then
                AddIDLine(tt, id, "currency")
                return
            end
        end
    end

    if type(_G.C_CurrencyInfo.GetBackpackCurrencyInfo) == "function" then
        local ok, info = pcall(_G.C_CurrencyInfo.GetBackpackCurrencyInfo, index)
        if ok and type(info) == "table" then
            AddIDLine(tt, info.currencyTypesID, "currency")
        end
    end
end

local function OnTooltipSetItem(tt)
    State.AddItemIDLines(tt, GetItemIDFromTooltip(tt))
end

State.OnTooltipSetSpell = function(tt)
    AddIDLine(tt, GetSpellIDFromTooltip(tt), "spell")
end

State.ProcessPlayerTooltip = function(tt, data)
    local playerTooltip = YUI._MouseEnhancementPlayerTooltip
    if not (playerTooltip and type(playerTooltip.Process) == "function") then
        return
    end
    local db = GetDB()
    playerTooltip.Process(tt, data, db, State.featureEnabled, State.ShouldDisplayPlayerMythicPlus(db))
end

local function OnTooltipSetUnit(tt)
    AddNPCIDFromTooltip(tt)
    State.ProcessPlayerTooltip(tt, nil)
end

local function OnTooltipSetUnitAura(tt, unit, index, filter)
    local id, casterName = GetAuraInfoByIndex(unit, index, filter)
    AddIDLine(tt, id, "aura", casterName)
end

local function OnTooltipSetUnitAuraInstance(tt, unit, auraInstanceID)
    local id, casterName = GetAuraInfoByInstance(unit, auraInstanceID)
    AddIDLine(tt, id, "aura", casterName)
end

local function OnDataItem(tt, data)
    State.AddItemIDLines(tt, type(data) == "table" and data.id or nil)
end

local function OnDataSpell(tt, data)
    AddIDLine(tt, type(data) == "table" and data.id or nil, "spell")
end

local function OnDataAura(tt, data)
    if type(data) ~= "table" then
        return
    end
    local ok, id = pcall(function()
        return data.id or data.spellID or data.spellId
    end)
    if not ok or IsSecretValue(id) then id = nil end
    local sourceOK, sourceUnit = pcall(function() return data.sourceUnit end)
    if not sourceOK or IsSecretValue(sourceUnit) then sourceUnit = nil end
    AddIDLine(tt, id, "aura", GetUnitDisplayName(sourceUnit))
end

local function OnDataCurrency(tt, data)
    AddIDLine(tt, type(data) == "table" and data.id or nil, "currency")
end

local function OnDataUnit(tt, data)
    AddNPCIDFromTooltip(tt, data)
    State.ProcessPlayerTooltip(tt, data)
end

local function OnDataMacro(tt, data)
    local lineData = type(data) == "table" and data.lines and data.lines[1] or nil
    if not lineData and tt and type(tt.GetTooltipData) == "function" then
        local ok, tooltipData = pcall(tt.GetTooltipData, tt)
        lineData = ok and type(tooltipData) == "table" and tooltipData.lines and tooltipData.lines[1] or nil
    end
    if type(lineData) ~= "table" then
        return
    end

    local kind = lineData.tooltipType == 0 and "item" or "spell"
    AddIDLine(tt, lineData.tooltipID, kind)
end

local function RegisterPostCall(tooltipType, handler)
    if tooltipType == nil or not (_G.TooltipDataProcessor and type(_G.TooltipDataProcessor.AddTooltipPostCall) == "function") then
        return false
    end
    return pcall(_G.TooltipDataProcessor.AddTooltipPostCall, tooltipType, handler) == true
end

local function InstallTooltipDataHooks()
    local types = _G.Enum and _G.Enum.TooltipDataType
    if type(types) ~= "table" then
        return false
    end

    RegisterPostCall(types.Item, OnDataItem)
    RegisterPostCall(types.Toy, OnDataItem)
    RegisterPostCall(types.Spell, OnDataSpell)
    RegisterPostCall(types.UnitAura or types.Aura, OnDataAura)
    RegisterPostCall(types.Macro, OnDataMacro)
    RegisterPostCall(types.PetAction, OnDataMacro)
    RegisterPostCall(types.Currency, OnDataCurrency)
    local unitRegistered = (YUI.IsRetail == true or YUI.IsForever == true)
        and RegisterPostCall(types.Unit, OnDataUnit) or false
    return unitRegistered == true
end

local function HookScriptSafe(tt, scriptName, handler)
    if tt and type(tt.HookScript) == "function" and type(handler) == "function" then
        pcall(tt.HookScript, tt, scriptName, function(...)
            pcall(handler, ...)
        end)
    end
end

local function HookMethodSafe(object, methodName, handler)
    if object and type(object[methodName]) == "function" and type(_G.hooksecurefunc) == "function" and type(handler) == "function" then
        pcall(_G.hooksecurefunc, object, methodName, function(...)
            pcall(handler, ...)
        end)
    end
end

local function HookGlobalSafe(functionName, handler)
    if type(_G[functionName]) == "function" and type(_G.hooksecurefunc) == "function" and type(handler) == "function" then
        pcall(_G.hooksecurefunc, functionName, function(...)
            pcall(handler, ...)
        end)
    end
end

local function SetMouseRuntimeEventFrameEnabled(enabled)
    if not State.cursorEventFrame and type(_G.CreateFrame) == "function" then
        State.cursorEventFrame = _G.CreateFrame("Frame")
        State.cursorEventFrame:SetScript("OnEvent", function()
            State.nativeCursorSizeLastValue = nil
            State.modelTrailScreenW = nil
            State.modelTrailScreenH = nil
            State.modelTrailScreenScale = nil
            RefreshCursorRuntime()
        end)
    end

    if not State.cursorEventFrame then
        return
    end
    if enabled then
        pcall(State.cursorEventFrame.RegisterEvent, State.cursorEventFrame, "PLAYER_ENTERING_WORLD")
        pcall(State.cursorEventFrame.RegisterEvent, State.cursorEventFrame, "UI_SCALE_CHANGED")
        pcall(State.cursorEventFrame.RegisterEvent, State.cursorEventFrame, "DISPLAY_SIZE_CHANGED")
        pcall(State.cursorEventFrame.RegisterEvent, State.cursorEventFrame, "ZONE_CHANGED_NEW_AREA")
        pcall(State.cursorEventFrame.RegisterEvent, State.cursorEventFrame, "PLAYER_DIFFICULTY_CHANGED")
        pcall(State.cursorEventFrame.RegisterEvent, State.cursorEventFrame, "INSTANCE_GROUP_SIZE_CHANGED")
    else
        pcall(State.cursorEventFrame.UnregisterEvent, State.cursorEventFrame, "PLAYER_ENTERING_WORLD")
        pcall(State.cursorEventFrame.UnregisterEvent, State.cursorEventFrame, "UI_SCALE_CHANGED")
        pcall(State.cursorEventFrame.UnregisterEvent, State.cursorEventFrame, "DISPLAY_SIZE_CHANGED")
        pcall(State.cursorEventFrame.UnregisterEvent, State.cursorEventFrame, "ZONE_CHANGED_NEW_AREA")
        pcall(State.cursorEventFrame.UnregisterEvent, State.cursorEventFrame, "PLAYER_DIFFICULTY_CHANGED")
        pcall(State.cursorEventFrame.UnregisterEvent, State.cursorEventFrame, "INSTANCE_GROUP_SIZE_CHANGED")
    end
end

State.CanRefreshVisibleTooltipForModifier = function(tt, key)
    if not (YUI.IsRetail or YUI.IsForever) then
        return true
    end

    local types = _G.Enum and _G.Enum.TooltipDataType
    if type(types) ~= "table" or types.Unit == nil or type(tt.IsTooltipType) ~= "function" then
        return false
    end

    local ok, isUnit = pcall(tt.IsTooltipType, tt, types.Unit)
    if not ok or IsSecretValue(isUnit) or type(isUnit) ~= "boolean" then return false end
    local db = GetDB()
    if isUnit == false then
        return db.tooltipIDEnabled == true and db.displayMode == MODE_MODIFIER
            and State.IsModifierEventKey(db.modifierKey, key)
    end
    local playerTooltip = YUI._MouseEnhancementPlayerTooltip
    return YUI.IsRetail == true and db.playerTooltipMythicPlusEnabled ~= false
        and State.IsModifierEventKey(db.playerTooltipModifier, key)
        and playerTooltip and type(playerTooltip.CanRefresh) == "function"
        and playerTooltip.CanRefresh(tt) == true
end

local function RefreshVisibleTooltipForModifier(key)
    local tt = _G.GameTooltip
    if not (tt and tt.IsShown and tt:IsShown()) then
        return
    end
    if type(tt.RefreshData) == "function" and State.CanRefreshVisibleTooltipForModifier(tt, key) then
        pcall(tt.RefreshData, tt)
    end
end

State.IsModifierEventKey = function(modifier, key)
    if modifier == MOD_SHIFT then
        return key == "LSHIFT" or key == "RSHIFT"
    elseif modifier == MOD_CTRL then
        return key == "LCTRL" or key == "RCTRL"
    elseif modifier == MOD_ALT then
        return key == "LALT" or key == "RALT"
    end
    return false
end

local function IsRelevantModifierKey(key)
    local db = GetDB()
    return (db.tooltipIDEnabled == true
        and db.displayMode == MODE_MODIFIER
        and State.IsModifierEventKey(db.modifierKey, key))
        or (YUI.IsRetail == true and db.playerTooltipMythicPlusEnabled ~= false
            and State.IsModifierEventKey(db.playerTooltipModifier, key))
end

State.IsNativeAuraIDCVarEnabled = function(value)
    return value == true or value == 1 or value == "1" or value == "true"
end

State.ShouldEnableNativeAuraIDs = function()
    if YUI.IsRetail ~= true or not State.featureEnabled then
        return false
    end

    local db = GetDB()
    return db.tooltipIDEnabled == true and db.displayMode == MODE_ALWAYS
end

State.ReleaseNativeAuraIDCVar = function()
    if not State.nativeAuraIDCVarOwned then
        return
    end

    local System = YUI.API and YUI.API.System
    if not (System and type(System.GetCVarSafe) == "function" and type(System.SetCVarIfExists) == "function") then
        return
    end

    local current = System.GetCVarSafe(State.nativeAuraIDCVarName)
    if current == nil then
        return
    end

    if State.IsNativeAuraIDCVarEnabled(current) and State.nativeAuraIDCVarPrevious ~= nil then
        if not System.SetCVarIfExists(State.nativeAuraIDCVarName, State.nativeAuraIDCVarPrevious) then
            return
        end
    end

    State.nativeAuraIDCVarOwned = false
    State.nativeAuraIDCVarPrevious = nil
end

State.SyncNativeAuraIDCVar = function()
    if not State.ShouldEnableNativeAuraIDs() then
        State.ReleaseNativeAuraIDCVar()
        return
    end

    local System = YUI.API and YUI.API.System
    if not (System and type(System.GetCVarSafe) == "function" and type(System.SetCVarIfExists) == "function") then
        return
    end

    local current = System.GetCVarSafe(State.nativeAuraIDCVarName)
    if current == nil or State.IsNativeAuraIDCVarEnabled(current) then
        return
    end

    local previous = State.nativeAuraIDCVarPrevious
    if not State.nativeAuraIDCVarOwned then
        previous = current
    end
    if System.SetCVarIfExists(State.nativeAuraIDCVarName, 1) then
        State.nativeAuraIDCVarPrevious = previous
        State.nativeAuraIDCVarOwned = true
    end
end

State.FlushNativeAuraIDCVarSync = function()
    State.nativeAuraIDCVarSyncPending = false
    State.SyncNativeAuraIDCVar()
end

State.QueueNativeAuraIDCVarSync = function()
    if YUI.IsRetail ~= true or State.nativeAuraIDCVarSyncPending then
        return
    end

    State.nativeAuraIDCVarSyncPending = true
    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
        local ok = pcall(_G.C_Timer.After, 0, State.FlushNativeAuraIDCVarSync)
        if ok then
            return
        end
    end
    State.FlushNativeAuraIDCVarSync()
end

local function InstallModifierWatcher()
    if State.modifierFrame or type(_G.CreateFrame) ~= "function" then
        return
    end

    State.modifierFrame = _G.CreateFrame("Frame")
    State.modifierFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
    State.modifierFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    State.modifierFrame:SetScript("OnEvent", function(_, event, key)
        if event == "PLAYER_ENTERING_WORLD" then
            State.QueueNativeAuraIDCVarSync()
            return
        end
        if State.featureEnabled and IsRelevantModifierKey(key) then
            RefreshVisibleTooltipForModifier(key)
        end
    end)
end

local function InstallHooks()
    if State.hooksInstalled then
        return
    end
    State.hooksInstalled = true

    local unitPostCallInstalled = InstallTooltipDataHooks()
    InstallModifierWatcher()

    local tooltips = {
        _G.GameTooltip,
        _G.ItemRefTooltip,
        _G.ShoppingTooltip1,
        _G.ShoppingTooltip2,
    }

    for _, tt in ipairs(tooltips) do
        HookScriptSafe(tt, "OnTooltipSetItem", OnTooltipSetItem)
        HookScriptSafe(tt, "OnTooltipSetSpell", State.OnTooltipSetSpell)
        if not unitPostCallInstalled then
            HookScriptSafe(tt, "OnTooltipSetUnit", OnTooltipSetUnit)
        end
        HookMethodSafe(tt, "SetHyperlink", function(self, link)
            AddIDFromHyperlink(self, link)
        end)
    end

    if _G.GameTooltip then
        HookMethodSafe(_G.GameTooltip, "SetUnitAura", OnTooltipSetUnitAura)
        HookMethodSafe(_G.GameTooltip, "SetUnitBuff", OnTooltipSetUnitAura)
        HookMethodSafe(_G.GameTooltip, "SetUnitDebuff", OnTooltipSetUnitAura)
        HookMethodSafe(_G.GameTooltip, "SetUnitBuffByAuraInstanceID", OnTooltipSetUnitAuraInstance)
        HookMethodSafe(_G.GameTooltip, "SetUnitDebuffByAuraInstanceID", OnTooltipSetUnitAuraInstance)
        HookMethodSafe(_G.GameTooltip, "SetUnitAuraByAuraInstanceID", OnTooltipSetUnitAuraInstance)
        HookMethodSafe(_G.GameTooltip, "SetCurrencyByID", function(self, id)
            AddIDLine(self, id, "currency")
        end)
        HookMethodSafe(_G.GameTooltip, "SetCurrencyToken", AddCurrencyTokenID)
        HookMethodSafe(_G.GameTooltip, "SetBackpackToken", AddCurrencyTokenID)
    end

    HookGlobalSafe("SetItemRef", function(link)
        AddIDFromHyperlink(_G.ItemRefTooltip, link)
    end)
    HookGlobalSafe("QuestMapLogTitleButton_OnEnter", AddQuestIDFromFrame)
    HookGlobalSafe("TaskPOI_OnEnter", AddQuestIDFromFrame)
end

local function GetDisplayModeOptions()
    return {
        { text = T("mode.always", "始终显示"), value = MODE_ALWAYS },
        { text = T("mode.modifier", "按住修饰键显示"), value = MODE_MODIFIER },
    }
end

local function GetModifierOptions()
    return {
        { text = T("modifier.shift", "Shift"), value = MOD_SHIFT },
        { text = T("modifier.ctrl", "Ctrl"), value = MOD_CTRL },
        { text = T("modifier.alt", "Alt"), value = MOD_ALT },
    }
end

State.GetPlayerTooltipDisplayOptions = function()
    local holdFormat = T("mode.hold_modifier", "按住 %s 显示")
    return {
        { text = T("mode.always", "始终显示"), value = "NONE" },
        { text = string.format(holdFormat, T("modifier.shift", "Shift")), value = MOD_SHIFT },
        { text = string.format(holdFormat, T("modifier.ctrl", "Ctrl")), value = MOD_CTRL },
        { text = string.format(holdFormat, T("modifier.alt", "Alt")), value = MOD_ALT },
    }
end

local function GetCursorStyleOptions()
    return {
        { text = T("cursor_style.blizzard", "无"), value = CURSOR_STYLE_BLIZZARD },
        { text = T("cursor_style.ring_dot", "圆环加点"), value = CURSOR_STYLE_RING_DOT },
        { text = T("cursor_style.infrared_lock", "红外锁定"), value = CURSOR_STYLE_INFRARED_LOCK },
        { text = T("cursor_style.rotating_triangle", "旋转三角"), value = CURSOR_STYLE_ROTATING_TRIANGLE },
    }
end

local function GetCursorSizeOptions()
    return {
        { text = T("cursor_size.small", "小"), value = CURSOR_SIZE_SMALL },
        { text = T("cursor_size.medium", "中"), value = CURSOR_SIZE_MEDIUM },
        { text = T("cursor_size.large", "大"), value = CURSOR_SIZE_LARGE },
        { text = T("cursor_size.extra_large", "超大"), value = CURSOR_SIZE_EXTRA_LARGE },
        { text = T("cursor_size.massive", "巨大"), value = CURSOR_SIZE_MASSIVE },
    }
end

local function GetOverlaySizeOptions()
    return {
        { text = T("cursor_size.small", "小"), value = OVERLAY_SIZE_SMALL },
        { text = T("cursor_size.medium", "中"), value = OVERLAY_SIZE_MEDIUM },
        { text = T("cursor_size.large", "大"), value = OVERLAY_SIZE_LARGE },
        { text = T("cursor_size.extra_large", "超大"), value = OVERLAY_SIZE_EXTRA_LARGE },
        { text = T("cursor_size.massive", "巨大"), value = OVERLAY_SIZE_MASSIVE },
    }
end

local function GetTrailModeOptions()
    return {
        { text = T("trail_mode.none", "关闭"), value = TRAIL_MODE_NONE },
        { text = T("trail_mode.model_arc", "电弧"), value = TRAIL_MODEL_MODES.ARC },
        { text = T("trail_mode.model_flare", "日焰"), value = TRAIL_MODEL_MODES.FLARE },
        { text = T("trail_mode.model_prism", "虹光"), value = TRAIL_MODEL_MODES.PRISM },
        { text = T("trail_mode.model_comet", "星流"), value = TRAIL_MODEL_MODES.COMET },
        { text = T("trail_mode.stars", "星雨"), value = TRAIL_MODE_STARS },
        { text = T("trail_mode.football", "足球"), value = TRAIL_MODE_FOOTBALL },
    }
end

local function GetTrailQualityOptions()
    return {
        { text = T("trail_quality.smooth", "稀疏"), value = TRAIL_QUALITY_SMOOTH },
        { text = T("trail_quality.balanced", "标准"), value = TRAIL_QUALITY_BALANCED },
        { text = T("trail_quality.quality", "稍密"), value = TRAIL_QUALITY_QUALITY },
    }
end

function State.GetCursorSceneOptions()
    return {
        { text = T("cursor_scene.always", "始终"), value = "always" },
        { text = T("cursor_scene.instance", "副本内"), value = "instance" },
        { text = T("cursor_scene.world", "副本外"), value = "world" },
    }
end

local function GetMotionScaleMaxOptions()
    return {
        { text = T("motion_scale_max.1_15", "1.15 倍"), value = "1_15" },
        { text = T("motion_scale_max.1_25", "1.25 倍"), value = "1_25" },
        { text = T("motion_scale_max.1_40", "1.40 倍"), value = "1_40" },
        { text = T("motion_scale_max.1_60", "1.60 倍"), value = "1_60" },
        { text = T("motion_scale_max.2_00", "2.00 倍"), value = "2_00" },
    }
end

function State.ConfigureTooltips(db, enabled)
    local tooltipCursor = YUI._MouseEnhancementTooltipCursor
    if tooltipCursor then tooltipCursor.Configure(db, enabled) end
    local tooltipFade = YUI._MouseEnhancementTooltipFade
    if tooltipFade then tooltipFade.Configure(db, enabled) end
end

local function RefreshFeatureSettings(feature)
    local db = GetDB()
    State.SyncNativeAuraIDCVar()
    SetMouseRuntimeEventFrameEnabled(State.featureEnabled and db.cursorEffectsEnabled == true)
    RefreshCursorRuntime()
    State.ConfigureTooltips(db, State.featureEnabled)
    if feature and feature.RefreshCurrentModule then
        feature:RefreshCurrentModule()
    end
end

local function GetOptions(feature)
    local db = GetDB()
    local tooltipCursor = YUI._MouseEnhancementTooltipCursor
    if tooltipCursor then tooltipCursor.NormalizeConfig(db) end
    local options = {
        {
            type = "divider",
            label = T("settings.section.tooltip", "鼠标提示"),
            alignLeft = true,
            width = SECTION_WIDTH,
            collapsible = true,
            collapseKey = "mouseenhancement.player_tooltip",
            collapsed = false,
        },
        {
            type = "custom",
            width = SECTION_WIDTH,
            render = function(parent, x, y, width)
                local Settings = YUI.Settings
                if not (Settings and Settings.RenderAlignedFields) then return SECTION_WIDTH, 1 end
                local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                    x = x, y = y, width = math.min(width or SECTION_WIDTH, SECTION_WIDTH),
                    columns = 2, columnGap = 56, labelWidth = 112, labelGap = 10,
                    bodyWidth = 160, valueWidth = 0, valueGap = 0, rowHeight = 32, rowGap = 10,
                    fields = {
                        {
                            type = "checkbox",
                            label = T("settings.tooltip_cursor_enabled", "跟随鼠标"),
                            tooltip = T("settings.tooltip_cursor_help", "让常规鼠标提示跟随鼠标，并调整显示方位和距离。"),
                            labelPosition = "left",
                            get = function() return db.tooltipCursorEnabled == true end,
                            set = function(value)
                                db.tooltipCursorEnabled = value == true
                                RefreshFeatureSettings(feature)
                            end,
                        },
                        {
                            type = "checkbox",
                            label = T("settings.tooltip_instant_hide", "立即隐藏鼠标提示"),
                            tooltip = T("settings.tooltip_instant_hide_help"),
                            labelPosition = "left",
                            get = function() return db.tooltipInstantHide == true end,
                            set = function(value)
                                db.tooltipInstantHide = value == true
                                RefreshFeatureSettings(feature)
                            end,
                        },
                        {
                            type = "dropdown",
                            label = T("settings.tooltip_cursor_position", "显示位置"),
                            hidden = function() return db.tooltipCursorEnabled ~= true end,
                            default = "TOPRIGHT",
                            options = {
                                { text = T("tooltip_position.topright", "右上"), value = "TOPRIGHT" },
                                { text = T("tooltip_position.top", "上方"), value = "TOP" },
                                { text = T("tooltip_position.topleft", "左上"), value = "TOPLEFT" },
                                { text = T("tooltip_position.right", "右侧"), value = "RIGHT" },
                                { text = T("tooltip_position.left", "左侧"), value = "LEFT" },
                                { text = T("tooltip_position.bottomright", "右下"), value = "BOTTOMRIGHT" },
                                { text = T("tooltip_position.bottom", "下方"), value = "BOTTOM" },
                                { text = T("tooltip_position.bottomleft", "左下"), value = "BOTTOMLEFT" },
                                { text = T("tooltip_position.center", "居中"), value = "CENTER" },
                            },
                            get = function() return db.tooltipCursorPosition end,
                            set = function(value)
                                db.tooltipCursorPosition = value
                                local tooltipCursor = YUI._MouseEnhancementTooltipCursor
                                if tooltipCursor then tooltipCursor.Configure(db, State.featureEnabled) end
                            end,
                        },
                    },
                })
                return gridWidth, gridHeight
            end,
        },
        {
            type = "custom",
            width = SECTION_WIDTH,
            hidden = function() return db.tooltipCursorEnabled ~= true end,
            render = function(parent, x, y, width)
                local Settings = YUI.Settings
                if not (Settings and Settings.RenderAlignedFields) then return SECTION_WIDTH, 1 end
                local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                    x = x, y = y, width = math.min(width or SECTION_WIDTH, SECTION_WIDTH),
                    columns = 2, columnGap = 56, labelWidth = 112, labelGap = 10,
                    bodyWidth = 160, valueWidth = 48, valueGap = 8, rowHeight = 32, rowGap = 10,
                    fields = {
                        {
                            type = "slider",
                            label = T("settings.tooltip_cursor_offset_x", "横向偏移"),
                            tooltip = T("settings.tooltip_cursor_offset_x_help", "正值向右，负值向左。"),
                            min = -100, max = 100, step = 1, default = 0,
                            get = function() return db.tooltipCursorOffsetX end,
                            set = function(value)
                                db.tooltipCursorOffsetX = value
                                local tooltipCursor = YUI._MouseEnhancementTooltipCursor
                                if tooltipCursor then tooltipCursor.Configure(db, State.featureEnabled) end
                            end,
                        },
                        {
                            type = "slider",
                            label = T("settings.tooltip_cursor_offset_y", "纵向偏移"),
                            tooltip = T("settings.tooltip_cursor_offset_y_help", "正值向上，负值向下。"),
                            min = -100, max = 100, step = 1, default = 0,
                            get = function() return db.tooltipCursorOffsetY end,
                            set = function(value)
                                db.tooltipCursorOffsetY = value
                                local tooltipCursor = YUI._MouseEnhancementTooltipCursor
                                if tooltipCursor then tooltipCursor.Configure(db, State.featureEnabled) end
                            end,
                        },
                    },
                })
                return gridWidth, gridHeight
            end,
        },
        {
            type = "custom",
            width = SECTION_WIDTH,
            render = function(parent, x, y, width)
                local Settings = YUI.Settings
                if not (Settings and Settings.RenderAlignedFields) then
                    return SECTION_WIDTH, 1
                end

                local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                    x = x,
                    y = y,
                    width = math.min(width or SECTION_WIDTH, SECTION_WIDTH),
                    columns = 2,
                    columnGap = 56,
                    labelWidth = 112,
                    labelGap = 10,
                    bodyWidth = 160,
                    valueWidth = 0,
                    valueGap = 0,
                    rowHeight = 32,
                    rowGap = 10,
                    fields = {
                        {
                            type = "checkbox",
                            label = T("settings.player_text_color", "玩家文字染色"),
                            labelPosition = "left",
                            get = function() return db.playerTooltipColorEnabled ~= false end,
                            set = function(value)
                                db.playerTooltipColorEnabled = value == true
                                RefreshVisibleTooltipForModifier()
                                RefreshFeatureSettings(feature)
                            end,
                        },
                        {
                            type = "checkbox",
                            label = T("settings.player_mythic_plus", "大秘境信息"),
                            labelPosition = "left",
                            hidden = function() return YUI.IsRetail ~= true end,
                            get = function() return db.playerTooltipMythicPlusEnabled ~= false end,
                            set = function(value)
                                db.playerTooltipMythicPlusEnabled = value == true
                                RefreshVisibleTooltipForModifier()
                                RefreshFeatureSettings(feature)
                            end,
                        },
                        {
                            type = "checkbox",
                            label = T("settings.player_mythic_plus_score", "显示大秘境评分"),
                            labelPosition = "left",
                            hidden = function() return YUI.IsRetail ~= true end,
                            get = function() return db.playerTooltipMythicPlusScoreEnabled ~= false end,
                            set = function(value)
                                db.playerTooltipMythicPlusScoreEnabled = value == true
                                RefreshVisibleTooltipForModifier()
                                RefreshFeatureSettings(feature)
                            end,
                        },
                        {
                            type = "dropdown",
                            label = T("settings.player_mythic_display_condition", "大秘境显示条件"),
                            options = State.GetPlayerTooltipDisplayOptions(),
                            default = MOD_SHIFT,
                            hidden = function()
                                return YUI.IsRetail ~= true or db.playerTooltipMythicPlusEnabled == false
                            end,
                            get = function() return db.playerTooltipModifier end,
                            set = function(value)
                                if value == MOD_SHIFT or value == MOD_CTRL or value == MOD_ALT then
                                    db.playerTooltipModifier = value
                                else
                                    db.playerTooltipModifier = "NONE"
                                end
                                RefreshVisibleTooltipForModifier()
                            end,
                        },
                    },
                })

                return gridWidth, gridHeight
            end,
        },
        {
            type = "divider",
            label = T("settings.section.tooltip_id", "鼠标提示添加ID"),
            alignLeft = true,
            width = SECTION_WIDTH,
            collapsible = true,
            collapseKey = "mouseenhancement.tooltip_id",
            collapsed = false,
        },
        {
            type = "custom",
            width = SECTION_WIDTH,
            render = function(parent, x, y, width)
                local Settings = YUI.Settings
                if not (Settings and Settings.RenderAlignedFields) then
                    return SECTION_WIDTH, 1
                end

                local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                    x = x,
                    y = y,
                    width = math.min(width or SECTION_WIDTH, SECTION_WIDTH),
                    columns = 2,
                    columnGap = 56,
                    labelWidth = 112,
                    labelGap = 10,
                    bodyWidth = 160,
                    valueWidth = 0,
                    valueGap = 0,
                    rowHeight = 32,
                    rowGap = 10,
                    fields = {
                        {
                            type = "checkbox",
                            label = T("settings.enable", "启用"),
                            labelPosition = "left",
                            get = function() return db.tooltipIDEnabled == true end,
                            set = function(value)
                                db.tooltipIDEnabled = value == true
                                RefreshVisibleTooltipForModifier()
                                RefreshFeatureSettings(feature)
                            end,
                        },
                        {
                            type = "checkbox",
                            label = T("settings.item_spell_id", "显示物品法术ID"),
                            labelPosition = "left",
                            get = function() return db.itemSpellIDEnabled == true end,
                            set = function(value)
                                db.itemSpellIDEnabled = value == true
                                RefreshVisibleTooltipForModifier()
                            end,
                        },
                    },
                })

                return gridWidth, gridHeight
            end,
        },
        {
            type = "custom",
            width = SECTION_WIDTH,
            hidden = function()
                return db.tooltipIDEnabled ~= true
            end,
            render = function(parent, x, y, width)
                local Settings = YUI.Settings
                if not (Settings and Settings.RenderAlignedFields) then
                    return SECTION_WIDTH, 1
                end

                local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                    x = x,
                    y = y,
                    width = math.min(width or SECTION_WIDTH, SECTION_WIDTH),
                    columns = 2,
                    columnGap = 56,
                    labelWidth = 112,
                    labelGap = 10,
                    bodyWidth = 160,
                    valueWidth = 0,
                    valueGap = 0,
                    rowHeight = 32,
                    rowGap = 10,
                    fields = {
                        {
                            type = "dropdown",
                            label = T("settings.display_mode", "显示方式"),
                            hidden = function()
                                return db.tooltipIDEnabled ~= true
                            end,
                            options = GetDisplayModeOptions(),
                            default = MODE_ALWAYS,
                            get = function() return db.displayMode end,
                            set = function(value)
                                db.displayMode = (value == MODE_MODIFIER) and MODE_MODIFIER or MODE_ALWAYS
                                RefreshFeatureSettings(feature)
                            end,
                        },
                        {
                            type = "dropdown",
                            label = T("settings.modifier_key", "修饰键"),
                            options = GetModifierOptions(),
                            default = MOD_SHIFT,
                            hidden = function() return db.displayMode ~= MODE_MODIFIER end,
                            get = function() return db.modifierKey end,
                            set = function(value)
                                if value == MOD_CTRL or value == MOD_ALT then
                                    db.modifierKey = value
                                else
                                    db.modifierKey = MOD_SHIFT
                                end
                            end,
                        },
                    },
                })

                return gridWidth, gridHeight
            end,
        },
        {
            type = "divider",
            label = T("settings.section.cursor_appearance", "鼠标特效"),
            alignLeft = true,
            width = SECTION_WIDTH,
            collapsible = true,
            collapseKey = "mouseenhancement.cursor_effects",
            collapsed = false,
        },
        {
            type = "custom",
            width = SECTION_WIDTH,
            render = function(parent, x, y, width)
                local Settings = YUI.Settings
                if not (Settings and Settings.RenderAlignedFields) then
                    return SECTION_WIDTH, 1
                end

                local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                    x = x,
                    y = y,
                    width = math.min(width or SECTION_WIDTH, SECTION_WIDTH),
                    columns = 2,
                    columnGap = 56,
                    labelWidth = 112,
                    labelGap = 10,
                    bodyWidth = 160,
                    valueWidth = 0,
                    valueGap = 0,
                    rowHeight = 32,
                    rowGap = 10,
                    fields = {
                        {
                            type = "checkbox",
                            label = T("settings.enable", "启用"),
                            labelPosition = "left",
                            get = function() return db.cursorEffectsEnabled == true end,
                            set = function(value)
                                db.cursorEffectsEnabled = value == true
                                RefreshFeatureSettings(feature)
                            end,
                        },
                    },
                })

                return gridWidth, gridHeight
            end,
        },
        {
            type = "text",
            label = T("settings.cursor_warning", "此功能对性能有较大影响，请谨慎使用"),
            hidden = function()
                return db.cursorEffectsEnabled ~= true
            end,
            colorKey = "color.state.danger",
            justify = "LEFT",
            width = SECTION_WIDTH,
            wrap = true,
        },
        {
            type = "custom",
            width = SECTION_WIDTH,
            hidden = function()
                return db.cursorEffectsEnabled ~= true
            end,
            render = function(parent, x, y, width)
                local Settings = YUI.Settings
                if not (Settings and Settings.RenderAlignedFields) then
                    return SECTION_WIDTH, 1
                end

                local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                    x = x,
                    y = y,
                    width = math.min(width or SECTION_WIDTH, SECTION_WIDTH),
                    columns = 2,
                    columnGap = 56,
                    labelWidth = 112,
                    labelGap = 10,
                    bodyWidth = 160,
                    valueWidth = 0,
                    valueGap = 0,
                    rowHeight = 32,
                    rowGap = 10,
                    fields = {
                        {
                            type = "dropdown",
                            label = T("settings.cursor_size", "鼠标尺寸"),
                            options = GetCursorSizeOptions(),
                            default = CURSOR_SIZE_MEDIUM,
                            get = function() return db.cursorSize end,
                            set = function(value)
                                if value == CURSOR_SIZE_SMALL
                                    or value == CURSOR_SIZE_LARGE
                                    or value == CURSOR_SIZE_EXTRA_LARGE
                                    or value == CURSOR_SIZE_MASSIVE then
                                    db.cursorSize = value
                                else
                                    db.cursorSize = CURSOR_SIZE_MEDIUM
                                end
                                RefreshFeatureSettings(feature)
                            end,
                        },
                    },
                })

                return gridWidth, gridHeight
            end,
        },
        {
            type = "custom",
            width = SECTION_WIDTH,
            hidden = function()
                return db.cursorEffectsEnabled ~= true
            end,
            render = function(parent, x, y, width)
                local Settings = YUI.Settings
                if not (Settings and Settings.RenderAlignedFields) then
                    return SECTION_WIDTH, 1
                end

                local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                    x = x,
                    y = y,
                    width = math.min(width or SECTION_WIDTH, SECTION_WIDTH),
                    columns = 2,
                    columnGap = 56,
                    labelWidth = 112,
                    labelGap = 10,
                    bodyWidth = 160,
                    valueWidth = 0,
                    valueGap = 0,
                    rowHeight = 32,
                    rowGap = 10,
                    fields = {
                        {
                            type = "dropdown",
                            label = T("settings.cursor_style", "叠加元素"),
                            options = GetCursorStyleOptions(),
                            default = CURSOR_STYLE_BLIZZARD,
                            get = function() return db.cursorStyle end,
                            set = function(value)
                                if value == CURSOR_STYLE_RING_DOT
                                    or value == CURSOR_STYLE_INFRARED_LOCK
                                    or value == CURSOR_STYLE_ROTATING_TRIANGLE then
                                    db.cursorStyle = value
                                else
                                    db.cursorStyle = CURSOR_STYLE_BLIZZARD
                                end
                                RefreshFeatureSettings(feature)
                            end,
                        },
                        {
                            type = "dropdown",
                            label = T("settings.overlay_size", "叠加尺寸"),
                            hidden = function()
                                return db.cursorStyle == CURSOR_STYLE_BLIZZARD
                            end,
                            options = GetOverlaySizeOptions(),
                            default = OVERLAY_SIZE_MEDIUM,
                            get = function() return db.overlaySize end,
                            set = function(value)
                                if value == OVERLAY_SIZE_SMALL
                                    or value == OVERLAY_SIZE_LARGE
                                    or value == OVERLAY_SIZE_EXTRA_LARGE
                                    or value == OVERLAY_SIZE_MASSIVE then
                                    db.overlaySize = value
                                else
                                    db.overlaySize = OVERLAY_SIZE_MEDIUM
                                end
                                RefreshFeatureSettings(feature)
                            end,
                        },
                    },
                })

                return gridWidth, gridHeight
            end,
        },
        {
            type = "custom",
            width = SECTION_WIDTH,
            hidden = function()
                return db.cursorEffectsEnabled ~= true or db.cursorStyle == CURSOR_STYLE_BLIZZARD
            end,
            render = function(parent, x, y, width)
                local Settings = YUI.Settings
                if not (Settings and Settings.RenderAlignedFields) then
                    return SECTION_WIDTH, 1
                end

                local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                    x = x,
                    y = y,
                    width = math.min(width or SECTION_WIDTH, SECTION_WIDTH),
                    columns = 2,
                    columnGap = 56,
                    labelWidth = 112,
                    labelGap = 10,
                    bodyWidth = 160,
                    valueWidth = 0,
                    valueGap = 0,
                    rowHeight = 32,
                    rowGap = 10,
                    fields = {
                        {
                            type = "checkbox",
                            label = T("settings.cursor_motion_scale", "移动放大"),
                            labelPosition = "left",
                            get = function() return db.cursorMotionScale == true end,
                            set = function(value)
                                db.cursorMotionScale = value == true
                                RefreshFeatureSettings(feature)
                            end,
                        },
                        {
                            type = "dropdown",
                            label = T("settings.cursor_motion_scale_max", "放大上限"),
                            options = GetMotionScaleMaxOptions(),
                            default = CURSOR_MOTION_SCALE_DEFAULT,
                            hidden = function()
                                return db.cursorMotionScale ~= true
                            end,
                            get = function() return db.cursorMotionScaleMax end,
                            set = function(value)
                                if MOTION_SCALE_MAX_VALUES[value] then
                                    db.cursorMotionScaleMax = value
                                else
                                    db.cursorMotionScaleMax = CURSOR_MOTION_SCALE_DEFAULT
                                end
                                RefreshFeatureSettings(feature)
                            end,
                        },
                    },
                })

                return gridWidth, gridHeight
            end,
        },
        {
            type = "custom",
            width = SECTION_WIDTH,
            hidden = function()
                return db.cursorEffectsEnabled ~= true
            end,
            render = function(parent, x, y, width)
                local Settings = YUI.Settings
                if not (Settings and Settings.RenderAlignedFields) then
                    return SECTION_WIDTH, 1
                end

                local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                    x = x,
                    y = y,
                    width = math.min(width or SECTION_WIDTH, SECTION_WIDTH),
                    columns = 2,
                    columnGap = 56,
                    labelWidth = 112,
                    labelGap = 10,
                    bodyWidth = 160,
                    valueWidth = 0,
                    valueGap = 0,
                    rowHeight = 32,
                    rowGap = 10,
                    fields = {
                        {
                            type = "dropdown",
                            label = T("settings.trail_mode", "鼠标拖尾"),
                            options = GetTrailModeOptions(),
                            default = TRAIL_MODE_NONE,
                            get = function() return db.trailMode end,
                            set = function(value)
                                if IsValidTrailMode(value) then
                                    db.trailMode = value
                                else
                                    db.trailMode = TRAIL_MODE_NONE
                                end
                                RefreshFeatureSettings(feature)
                            end,
                        },
                        {
                            type = "dropdown",
                            label = T("settings.trail_quality", "拖尾密度"),
                            hidden = function()
                                return not IsTextureTrailMode(db.trailMode)
                            end,
                            options = GetTrailQualityOptions(),
                            default = TRAIL_QUALITY_BALANCED,
                            get = function() return db.trailQuality end,
                            set = function(value)
                                if value == TRAIL_QUALITY_SMOOTH or value == TRAIL_QUALITY_QUALITY then
                                    db.trailQuality = value
                                else
                                    db.trailQuality = TRAIL_QUALITY_BALANCED
                                end
                                RefreshFeatureSettings(feature)
                            end,
                        },
                    },
                })

                return gridWidth, gridHeight
            end,
        },
        {
            type = "custom",
            width = SECTION_WIDTH,
            hidden = function()
                return db.cursorEffectsEnabled ~= true
            end,
            render = function(parent, x, y, width)
                local Settings = YUI.Settings
                if not (Settings and Settings.RenderAlignedFields) then
                    return SECTION_WIDTH, 1
                end

                local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                    x = x,
                    y = y,
                    width = math.min(width or SECTION_WIDTH, SECTION_WIDTH),
                    columns = 2,
                    columnGap = 56,
                    labelWidth = 112,
                    labelGap = 10,
                    bodyWidth = 160,
                    valueWidth = 0,
                    valueGap = 0,
                    rowHeight = 32,
                    rowGap = 10,
                    fields = {
                        {
                            type = "dropdown",
                            label = T("settings.cursor_scene", "显示场景"),
                            options = State.GetCursorSceneOptions(),
                            default = "always",
                            get = function() return db.cursorScene end,
                            set = function(value)
                                if value == "instance" or value == "world" then
                                    db.cursorScene = value
                                else
                                    db.cursorScene = "always"
                                end
                                RefreshFeatureSettings(feature)
                            end,
                        },
                    },
                })

                return gridWidth, gridHeight
            end,
        },
    }
    return options
end

local function ToggleFeature(enabled)
    State.featureEnabled = enabled == true
    if State.featureEnabled then
        InstallHooks()
    end
    local db = GetDB()
    State.ConfigureTooltips(db, State.featureEnabled)
    State.SyncNativeAuraIDCVar()
    SetMouseRuntimeEventFrameEnabled(State.featureEnabled and db.cursorEffectsEnabled == true)
    RefreshCursorRuntime()
end

Components:RegisterFeature(FEATURE_KEY, {
    name = T("name", "鼠标增强"),
    description = T("description", "增强玩家鼠标提示，并在物品、法术、光环、任务、货币和 NPC 鼠标提示底部显示 ID。"),
    default = true,
    product = PRODUCT_ID,
    storageKey = FEATURE_KEY,
    settingsMode = "inline",
    callback = ToggleFeature,
    GetOptions = GetOptions,
    GetStats = function()
        local tooltipCursor = YUI._MouseEnhancementTooltipCursor
        local tooltipFade = YUI._MouseEnhancementTooltipFade
        return {
            tooltipCursor = tooltipCursor and tooltipCursor.GetDiagnostics() or nil,
            tooltipFade = tooltipFade and tooltipFade.GetDiagnostics() or nil,
        }
    end,
})

if YUI.Module and YUI.Module.Register then
    YUI.Module:Register({
        id = "component.mouse-enhancement.tooltip-cursor",
        owner = State,
        product = PRODUCT_ID,
        dependencies = { "core.db", "core.api", "core.event", "core.locale" },
        getEnabled = function() return Components:IsEnabled(FEATURE_KEY) end,
        OnEnable = function()
            State.ConfigureTooltips(GetDB(), true)
        end,
        OnDisable = function()
            State.ConfigureTooltips(GetDB(), false)
        end,
        OnProfileChanged = function()
            local db = GetDB()
            State.ConfigureTooltips(db, false)
            State.ConfigureTooltips(db, Components:IsEnabled(FEATURE_KEY))
        end,
    })
end
