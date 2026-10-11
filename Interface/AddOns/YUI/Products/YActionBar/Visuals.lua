local YUI = _G.YUI
if not YUI or not YUI.YActionBar then return end

local YAB = YUI.YActionBar
local GUI2 = YUI.GUI2
local Security = YUI.API and YUI.API.Security
local Visuals = {}
YAB.Visuals = Visuals

Visuals.implementationType = "native-enhanced"
Visuals.diagnosticVisualMode = Visuals.diagnosticVisualMode or "enhanced"
Visuals.buttons = Visuals.buttons or setmetatable({}, { __mode = "k" })
Visuals.pendingProfessionQuality = Visuals.pendingProfessionQuality or setmetatable({}, { __mode = "k" })
Visuals.professionQualityAtlasRatios = Visuals.professionQualityAtlasRatios or {}
Visuals.spellFlyoutVisualState = Visuals.spellFlyoutVisualState or setmetatable({}, { __mode = "k" })
Visuals.externalRegionState = Visuals.externalRegionState or setmetatable({}, { __mode = "k" })
Visuals.externalTextRegionState = Visuals.externalTextRegionState or setmetatable({}, { __mode = "k" })
Visuals.externalTextViews = Visuals.externalTextViews or setmetatable({}, { __mode = "k" })
Visuals.externalTextSnapshots = Visuals.externalTextSnapshots or setmetatable({}, { __mode = "k" })
Visuals.textAnchorSignatures = Visuals.textAnchorSignatures or setmetatable({}, { __mode = "k" })
Visuals.hooked = Visuals.hooked or setmetatable({}, { __mode = "k" })
Visuals.bindHighlights = Visuals.bindHighlights or setmetatable({}, { __mode = "k" })
Visuals.stats = Visuals.stats or {
    writes = 0,
    gui2ButtonObjects = 0,
    nativeEnhancedButtons = 0,
    fallbackButtons = 0,
    managedCooldownFrames = 0,
    themeRefreshes = 0,
    pixelRefreshes = 0,
    procGlowBackend = "yui-managed-proc-template",
    procGlowFrames = 0,
    skinWrites = 0,
    visualExtraHidden = 0,
}

local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local EMPTY_ICON_COLOR = { 0.35, 0.35, 0.35, 0.35 }
local DEFAULT_TEXT_COLOR = { 1, 1, 1, 1 }
local PET_AUTOCAST_RECT_OUTSET = 1
local PET_AUTOCAST_RECT_SHINE_OUTSET = 5
local PET_AUTOCAST_RECT_MASK_INSET = 4
local PET_AUTOCAST_CIRCLE_MARKER_COLOR = { 1, 0.82, 0.12, 0.95 }
local PET_AUTOCAST_CIRCLE_ANTS_COLOR = { 1, 0.9, 0.18, 1 }
local PET_AUTOCAST_CIRCLE_MARKER_ALPHA = 0.96
local PET_AUTOCAST_CIRCLE_ANTS_ALPHA = 1
local PET_AUTOCAST_CIRCLE_ANTS_DURATION = 4
local PET_AUTOCAST_CIRCLE_MARKER_SUBLEVEL = 6
local PET_AUTOCAST_CIRCLE_ANTS_SUBLEVEL = 7
local MAIN_COOLDOWN_LEVEL_OFFSET = 8
local MAIN_COOLDOWN_SWIPE_ALPHA = 0.82
local CHARGE_COOLDOWN_LEVEL_OFFSET = MAIN_COOLDOWN_LEVEL_OFFSET - 1
local CHARGE_COOLDOWN_SWIPE_ALPHA = 0.42
local CHARGE_COOLDOWN_EDGE_SCALE = 2.1
local CHARGE_COOLDOWN_EDGE_R = 0.973
local CHARGE_COOLDOWN_EDGE_G = 0.839
local CHARGE_COOLDOWN_EDGE_B = 0.604
local CHARGE_COOLDOWN_EDGE_A = 1
local BLACK_BG_COLOR = { 34 / 255, 34 / 255, 34 / 255, 0.72 }
local BLIZZARD_BG_COLOR = { 1, 1, 1, 0.92 }
local DEFAULT_BORDER_COLOR = { 0, 0, 0, 1 }
local FALLBACK_SURFACE_COLOR = { 0.02, 0.02, 0.02, 0.88 }
local FALLBACK_HOVER_COLOR = { 1, 1, 1, 0.16 }
local FALLBACK_PRESSED_COLOR = { 1, 1, 1, 0.24 }
local FALLBACK_CHECKED_COLOR = { 1, 0.82, 0.18, 0.16 }
local PET_CHECKED_FILL_COLOR = { 1, 0.82, 0.18, 0.06 }
local PET_CHECKED_INNER_COLOR = { 1, 0.82, 0.18, 0.96 }
local PET_CHECKED_GLOW_COLOR = { 1, 0.70, 0.12, 0.28 }
local PET_CHECKED_FILL_ALPHA = 0.06
local BUTTON_STATE_COLORS = {
    actionChecked = { 1, 1, 1, 0.9 },
    pressedInnerGlow = { 1, 0.78, 0.18, 0.95 },
    assistedCombat = { 1, 0.78, 0.12, 0.96 },
    petChecked = { 1, 0.78, 0.12, 0.95 },
    flyoutHover = { 1, 0.92, 0.50, 0.42 },
    flyoutPushed = { 1, 0.78, 0.18, 0.62 },
    flyoutChecked = { 1, 0.82, 0.18, 0.72 },
}
local PET_CHECKED_INNER_ALPHA = 0.96
local PET_CHECKED_GLOW_ALPHA = 0.28
local PET_CHECKED_INNER_THICKNESS = 2
local PET_CHECKED_GLOW_THICKNESS = 4
local PET_CHECKED_INNER_OFFSET = 2
local PET_CHECKED_GLOW_OFFSET = 1
local FALLBACK_RANGE_TEXT_COLOR = { 1, 0.2, 0.15, 1 }
local BLIZZARD_BACKGROUND_ATLAS = "UI-HUD-ActionBar-IconFrame-Background"
local ACTION_BARS = {
    main = true,
    bar2 = true,
    bar3 = true,
    bar4 = true,
    bar5 = true,
    bar6 = true,
    bar7 = true,
    bar8 = true,
}
local TEXT_CACHE = setmetatable({}, { __mode = "k" })
local TEXT_COLOR_CACHE = setmetatable({}, { __mode = "k" })
local COOLDOWN_CACHE = setmetatable({}, { __mode = "k" })
local ICON_DESATURATION_CACHE = setmetatable({}, { __mode = "k" })
local LayoutCooldown
local GetFrameSize
local ApplyVisualRect
local AttachMaskTexture
local LayoutCheckedRing
local HidePetCheckedInnerVisual
local SetPetAutoCastCircleVisual
local HidePetAutoCastCircleVisual
local HideNativeButtonStateArt

local function ProductMedia(path)
    local Assets = YUI and YUI.Assets
    if Assets and Assets.Product then
        return Assets:Product(YAB.PRODUCT_ID or "yactionbar", path)
    end
    return "Interface\\AddOns\\" .. (YUI.AddonName or "YUI") .. "\\Products\\YActionBar\\Media\\" .. tostring(path or "")
end

function Visuals:ResolveCoreMedia(path)
    local assets = YUI and YUI.Assets
    if assets and assets.Core then
        return assets:Core(path)
    end
    local mediaRoot = YUI.CoreMode == "embedded"
        and "\\CoreEmbed\\Media\\Core\\" or "\\Media\\Core\\"
    return "Interface\\AddOns\\" .. (YUI.AddonName or "YUI")
        .. mediaRoot .. tostring(path or "")
end

function Visuals:GetCommonIconAppearance(shape)
    if GUI2 and type(GUI2.GetIconAppearancePreset) == "function" then
        return GUI2:GetIconAppearancePreset(shape)
    end
    local presets = GUI2 and GUI2.IconAppearancePresets
    return presets and presets[shape]
end
local ROUNDED_MASK_TEXTURE =
    Visuals:GetCommonIconAppearance("roundedSquare")
        and Visuals:GetCommonIconAppearance("roundedSquare").mask
        or ProductMedia("shapes\\rounded-square-mask.tga")
local WIDE_ROUNDED_MASK_TEXTURE =
    Visuals:GetCommonIconAppearance("wideRounded")
        and Visuals:GetCommonIconAppearance("wideRounded").mask
        or Visuals:ResolveCoreMedia("gui2\\shapes\\wide-rounded-mask.tga")
local CIRCLE_MASK_TEXTURE =
    Visuals:GetCommonIconAppearance("circle")
        and Visuals:GetCommonIconAppearance("circle").mask
        or ProductMedia("shapes\\circle-mask.tga")
local SOLID_SWIPE_TEXTURE =
    Visuals:GetCommonIconAppearance("square")
        and Visuals:GetCommonIconAppearance("square").swipe
        or ProductMedia("shapes\\solid-swipe.tga")
Visuals.vehicleExitIconPath = Visuals.vehicleExitIconPath or ProductMedia("icons\\vehicle-exit-modern.tga")
local CIRCLE_PROC_GLOW_SOFT_TEXTURE = ProductMedia("shapes\\circle-border-3.tga")
local PET_AUTOCAST_CIRCLE_MARKER_TEXTURE = ProductMedia("shapes\\pet-autocast-circle-bottom-dot.tga")
local PET_AUTOCAST_CIRCLE_ANTS_TEXTURE = ProductMedia("shapes\\pet-autocast-circle-ants.tga")
local BUTTON_STATE_INNER_TEXTURES =
    GUI2 and GUI2.IconStateInnerTextures or {
        square = Visuals:ResolveCoreMedia(
            "gui2\\shapes\\button-state-inner-square.tga"
        ),
        roundedSquare = Visuals:ResolveCoreMedia(
            "gui2\\shapes\\button-state-inner-rounded.tga"
        ),
        flatSquare = Visuals:ResolveCoreMedia(
            "gui2\\shapes\\button-state-inner-flat-square.tga"
        ),
        flatRounded = Visuals:ResolveCoreMedia(
            "gui2\\shapes\\button-state-inner-flat-rounded.tga"
        ),
        wideSquare = Visuals:ResolveCoreMedia(
            "gui2\\shapes\\button-state-inner-wide-square.tga"
        ),
        wideRounded = Visuals:ResolveCoreMedia(
            "gui2\\shapes\\button-state-inner-wide-rounded.tga"
        ),
        circle = Visuals:ResolveCoreMedia(
            "gui2\\shapes\\button-state-inner-circle.tga"
        ),
    }
local FLAT_VISUAL_ASPECT = 1.35
local WIDE_VISUAL_ASPECT = 10 / 9
local SPELLFLYOUT_NATIVE_SPACING = 4
local SPELLFLYOUT_MAX_VISUAL_OUTSET = 2


local function BuildActionShapeStyle(shape, fallback, chargeEdge, stateTexture)
    local common = Visuals:GetCommonIconAppearance(shape) or fallback
    return {
        padding = 0,
        mask = common.mask,
        borderFamily = common.borderFamily,
        circular = common.circular == true,
        swipe = common.swipe,
        chargeEdge = chargeEdge,
        aspect = common.aspect,
        stateTexture = stateTexture,
    }
end

local SHAPE_STYLES = {
    square = BuildActionShapeStyle("square", {
        mask = nil,
        borderFamily = nil,
        circular = false,
        swipe = SOLID_SWIPE_TEXTURE,
        aspect = 1,
    }, true, BUTTON_STATE_INNER_TEXTURES.square),
    roundedSquare = BuildActionShapeStyle("roundedSquare", {
        mask = ROUNDED_MASK_TEXTURE,
        borderFamily = "rounded",
        circular = false,
        swipe = ROUNDED_MASK_TEXTURE,
        aspect = 1,
    }, false, BUTTON_STATE_INNER_TEXTURES.roundedSquare),
    flatSquare = BuildActionShapeStyle("flatSquare", {
        mask = nil,
        borderFamily = nil,
        circular = false,
        swipe = SOLID_SWIPE_TEXTURE,
        aspect = FLAT_VISUAL_ASPECT,
    }, true, BUTTON_STATE_INNER_TEXTURES.flatSquare),
    flatRounded = BuildActionShapeStyle("flatRounded", {
        mask = ROUNDED_MASK_TEXTURE,
        borderFamily = "rounded",
        circular = false,
        swipe = ROUNDED_MASK_TEXTURE,
        aspect = FLAT_VISUAL_ASPECT,
    }, false, BUTTON_STATE_INNER_TEXTURES.flatRounded),
    wideSquare = BuildActionShapeStyle("wideSquare", {
        mask = nil,
        borderFamily = nil,
        circular = false,
        swipe = SOLID_SWIPE_TEXTURE,
        aspect = WIDE_VISUAL_ASPECT,
    }, true, BUTTON_STATE_INNER_TEXTURES.wideSquare),
    wideRounded = BuildActionShapeStyle("wideRounded", {
        mask = WIDE_ROUNDED_MASK_TEXTURE,
        borderFamily = "wideRounded",
        circular = false,
        swipe = WIDE_ROUNDED_MASK_TEXTURE,
        aspect = WIDE_VISUAL_ASPECT,
    }, false, BUTTON_STATE_INNER_TEXTURES.wideRounded),
    circle = BuildActionShapeStyle("circle", {
        mask = CIRCLE_MASK_TEXTURE,
        borderFamily = "circle",
        circular = true,
        swipe = CIRCLE_MASK_TEXTURE,
        aspect = 1,
    }, false, BUTTON_STATE_INNER_TEXTURES.circle),
}

function Visuals:GetCommonBorderThickness(border)
    if GUI2 and type(GUI2.GetIconBorderThickness) == "function" then
        return GUI2:GetIconBorderThickness(border)
    end
    local thickness = GUI2 and GUI2.IconBorderThickness
    if thickness and thickness[border] ~= nil then
        return thickness[border]
    end
    if border == "none" then return 0 end
    if border == "medium" then return 2 end
    if border == "thick" then return 3 end
    if border == "extraThick" then return 4 end
    return 1
end

local LINE_BORDER_ALPHA_SCALE = {
    [1] = 0.72,
    [2] = 0.86,
    [3] = 0.94,
    [4] = 1,
}

local SHAPE_BORDER_TEXTURES =
    (GUI2 and GUI2.IconAppearanceBorderTextures) or {
    rounded = {
        ProductMedia("shapes\\rounded-square-border-1.tga"),
        ProductMedia("shapes\\rounded-square-border-2.tga"),
        ProductMedia("shapes\\rounded-square-border-3.tga"),
        ProductMedia("shapes\\rounded-square-border-4.tga"),
    },
    wideRounded = {
        Visuals:ResolveCoreMedia("gui2\\shapes\\wide-rounded-border-1.tga"),
        Visuals:ResolveCoreMedia("gui2\\shapes\\wide-rounded-border-2.tga"),
        Visuals:ResolveCoreMedia("gui2\\shapes\\wide-rounded-border-3.tga"),
        Visuals:ResolveCoreMedia("gui2\\shapes\\wide-rounded-border-4.tga"),
    },
    circle = {
        ProductMedia("shapes\\circle-border-1.tga"),
        ProductMedia("shapes\\circle-border-2.tga"),
        ProductMedia("shapes\\circle-border-3.tga"),
        ProductMedia("shapes\\circle-border-4.tga"),
    },
}

local DEFAULT_RUNTIME_SNAPSHOT = {
    skin = "square",
    iconZoom = 0.08,
    border = "thin",
    borderColor = DEFAULT_BORDER_COLOR,
    background = "black",
    backgroundColor = BLACK_BG_COLOR,
    shadow = true,
    shadowColor = { 0, 0, 0, 0.5 },
    cooldownFade = true,
    cooldownTextSize = 12,
    rangeMode = "red",
    showHotkeys = true,
    hotkeySize = 12,
    hotkeyOffsetX = 0,
    hotkeyOffsetY = 0,
    showCounts = true,
    countSize = 12,
    countOffsetX = 0,
    countOffsetY = 0,
    showMacroNames = true,
    macroNameSize = 10,
    macroNameOffsetX = 0,
    macroNameOffsetY = 0,
    cooldownTextOffsetX = 0,
    cooldownTextOffsetY = 0,
    showProfessionQuality = true,
    professionQualitySize = 21,
    professionQualityOffsetX = 0,
    professionQualityOffsetY = 0,
}

local function EnsureCooldownCache(cooldown)
    local cache = COOLDOWN_CACHE[cooldown]
    if not cache then
        cache = {}
        COOLDOWN_CACHE[cooldown] = cache
    end
    return cache
end

local TOKEN_SPEC = {
    colors = {
        text = "color.text.primary",
        textSecondary = "color.text.secondary",
        accent = "color.text.accent",
        border = "color.border.default",
        surface = "color.surface.sunken",
        hover = "color.control.hover",
        pressed = "color.control.pressed",
        checked = "color.control.active",
        borderActive = "color.border.accent",
    },
    metrics = {
        hairline = "border.width.hairline",
        fontSize = "font.size.sm",
    },
    fonts = {
        body = "font.family.body",
    },
}

local function InCombat()
    return YAB.Adapter and YAB.Adapter:InCombat()
end

local function IsActionButton(button)
    local meta = YAB.SecureFactory and YAB.SecureFactory.GetButtonMeta and YAB.SecureFactory:GetButtonMeta(button) or nil
    return (meta and ACTION_BARS[meta.barId] == true) or (button and ACTION_BARS[button.yabBarId] == true) or false
end

local function GetButtonMeta(button)
    return YAB.SecureFactory and YAB.SecureFactory.GetButtonMeta and YAB.SecureFactory:GetButtonMeta(button) or nil
end

local function IsPetCheckedVisual(button, visual)
    if not (button and visual and visual.nativeSpecial == true) then return false end
    if visual.nativeSpecialKind ~= nil then return visual.nativeSpecialKind == "pet" end
    local meta = GetButtonMeta(button)
    return meta and meta.nativeSpecial == true and meta.barId == "pet" or false
end

local RefreshSkinState

local function IsNativeVisualMode()
    return Visuals.diagnosticVisualMode == "native"
end

local function RegionShown(region, shown)
    if not region then return 0 end
    local isShown = region.IsShown and region:IsShown() or false
    if shown then
        if region.Show and not isShown then
            region:Show()
            return 1
        end
    elseif region.Hide and isShown then
        region:Hide()
        return 1
    end
    return 0
end

local function RegionAlpha(region, alpha)
    if not (region and region.SetAlpha) then return 0 end
    alpha = alpha == nil and 1 or alpha
    if region.yabNativeVisualAlpha == alpha then return 0 end
    region:SetAlpha(alpha)
    region.yabNativeVisualAlpha = alpha
    return 1
end

local function LayoutManagedProcGlow(button, visual)
    local frame = visual and visual.procGlowFrame
    if not (button and frame and GUI2
        and GUI2.LayoutManagedProcGlow) then return end

    local visualWidth = visual.visualWidth
    local visualHeight = visual.visualHeight
    if not (visualWidth and visualHeight) then
        visualWidth, visualHeight = GetFrameSize(button, 36, 36)
    end
    GUI2:LayoutManagedProcGlow(
        frame,
        button,
        visualWidth,
        visualHeight,
        nil,
        nil,
        visual.runtimeSkin
    )
end

local function StopManagedProcGlow(frame)
    if not frame then return end
    if GUI2 and GUI2.SetManagedProcGlowShown then
        GUI2:SetManagedProcGlowShown(frame, false)
        return
    end
    if frame.Hide then frame:Hide() end
end

local function IsManagedProcGlowPlaying(frame)
    if not frame then return false end
    if frame.IsShown and not frame:IsShown() then return false end
    return frame.gui2ProcPlaying == true
        or frame.playingAnimation == true
        or frame.animationPlaying == true
end

local function ShouldRestartProcGlow(oldFrame, newFrame, oldShape, newShape)
    if not newFrame then return false end
    if oldFrame ~= newFrame then return true end
    if oldShape ~= newShape then return true end
    return not IsManagedProcGlowPlaying(newFrame)
end

local function PlayManagedProcGlow(frame)
    if not frame then return end
    if GUI2 and GUI2.SetManagedProcGlowShown then
        GUI2:SetManagedProcGlowShown(frame, true)
        return
    end
    if frame.Show then frame:Show() end
end

local function EnsureManagedProcGlow(button, visual)
    if not (button and visual and GUI2
        and GUI2.CreateManagedProcGlow) then return nil end
    local procShape = visual.runtimeSkin == "circle" and "circle" or "square"
    local frame
    if procShape == "circle" then
        frame = visual.procGlowCircleFrame
        if not frame then
            frame = GUI2:CreateManagedProcGlow(
                button, "circle", nil, nil, nil, nil,
                visual.runtimeSkin
            )
            if frame then frame.yabProcShape = "circle" end
            visual.procGlowCircleFrame = frame
            if frame then
                visual.procGlowBackend = frame.gui2ProcBackend
                    or "circle-managed"
                Visuals.stats.procGlowBackend =
                    "yui-managed-proc-circle-flipbook"
                Visuals.stats.procGlowFrames =
                    (Visuals.stats.procGlowFrames or 0) + 1
            end
        end
        visual.procGlowTexture = nil
    else
        frame = visual.procGlowTemplateFrame or visual.procGlowSquareFrame
        if not frame then
            frame = GUI2:CreateManagedProcGlow(
                button, "square", nil, nil, nil, nil,
                visual.runtimeSkin
            )
            if frame then
                frame.yabProcShape = "square"
                visual.procGlowTemplateFrame = frame
                visual.procGlowBackend = "spell-alert-template"
                Visuals.stats.procGlowBackend = "yui-managed-proc-template"
                Visuals.stats.procGlowFrames = (Visuals.stats.procGlowFrames or 0) + 1
            end
        end
        visual.procGlowTexture = nil
    end
    if visual.procGlowFrame and visual.procGlowFrame ~= frame then
        StopManagedProcGlow(visual.procGlowFrame)
    end
    visual.procGlowFrame = frame
    if frame then
        LayoutManagedProcGlow(button, visual)
    end
    return frame
end

local function SyncManagedProcGlow(button, visual, oldFrame, oldShape)
    if not (button and visual) then return 0 end
    if IsNativeVisualMode() then
        if visual.procGlowFrame then
            StopManagedProcGlow(visual.procGlowFrame)
            return 1
        end
        return 0
    end
    if visual.procGlow ~= true then
        if visual.procGlowFrame then
            StopManagedProcGlow(visual.procGlowFrame)
            return 1
        end
        return 0
    end
    local glow = visual.procGlowFrame
    if not InCombat() then
        glow = EnsureManagedProcGlow(button, visual)
    end
    if not glow then return 0 end
    LayoutManagedProcGlow(button, visual)
    local newShape = glow.yabProcShape
    if ShouldRestartProcGlow(oldFrame, glow, oldShape, newShape) then
        PlayManagedProcGlow(glow)
        return 1
    end
    return 0
end

local function HideNativeProcAlert(button)
    local alert = button and button.SpellActivationAlert
    if alert then
        if alert.Hide then alert:Hide() end
        if alert.SetAlpha then alert:SetAlpha(0) end
    end
end

local function RefreshModeHas(mode, key)
    if mode == nil or mode == "full" or key == "full" then return true end
    if mode == key then return true end
    return type(mode) == "string" and mode:sub(1, 1) == ":" and mode:find(":" .. key .. ":", 1, true) ~= nil
end

local function SetText(text, value)
    if not text then return 0 end
    value = value or ""
    if Security and Security.IsSecretValue and Security.IsSecretValue(value) then
        text:SetText(value)
        TEXT_CACHE[text] = nil
        local writes = 1
        writes = writes + RegionShown(text, true)
        return writes
    end
    local writes = 0
    if TEXT_CACHE[text] ~= value then
        text:SetText(value)
        TEXT_CACHE[text] = value
        writes = writes + 1
    end
    writes = writes + RegionShown(text, value ~= "")
    return writes
end

local function SetTextColor(text, color)
    if not (text and text.SetTextColor) then return 0 end
    color = color or DEFAULT_TEXT_COLOR
    if type(color) ~= "table" then color = DEFAULT_TEXT_COLOR end
    local r = color[1] or color.r or 1
    local g = color[2] or color.g or 1
    local b = color[3] or color.b or 1
    local a = color[4]
    if a == nil then a = color.a end
    if a == nil then a = 1 end
    local cached = TEXT_COLOR_CACHE[text]
    local rgbChanged = not cached or cached[1] ~= r or cached[2] ~= g or cached[3] ~= b
    local alphaChanged = not cached or cached[4] ~= a
    if not rgbChanged and not alphaChanged then return 0 end
    if not cached then
        cached = {}
        TEXT_COLOR_CACHE[text] = cached
    end
    cached[1], cached[2], cached[3], cached[4] = r, g, b, a
    if rgbChanged or (alphaChanged and not text.SetAlpha) then
        text:SetTextColor(r, g, b, text.SetAlpha and 1 or a)
    end
    if alphaChanged and text.SetAlpha then text:SetAlpha(a) end
    return 1
end

local function SetVertexColor(texture, color, fallback)
    if not (texture and texture.SetVertexColor) then return 0 end
    color = color or fallback
    if type(color) ~= "table" then return 0 end
    local r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4] == nil and 1 or color[4]
    texture:SetVertexColor(r, g, b, a)
    return 1
end

local function SetColorTexture(texture, color, fallback)
    if not (texture and texture.SetColorTexture) then return 0 end
    color = color or fallback
    if type(color) ~= "table" then return 0 end
    local r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4] == nil and 1 or color[4]
    texture:SetColorTexture(r, g, b, a)
    texture.yabTexturePath = nil
    texture.yabTextureAtlas = nil
    return 1
end

local function SetColorTextureWithAlpha(texture, color, fallback, alpha)
    if not (texture and texture.SetColorTexture) then return 0 end
    color = type(color) == "table" and color or fallback
    if type(color) ~= "table" then return 0 end
    texture:SetColorTexture(color[1] or 1, color[2] or 1, color[3] or 1, alpha == nil and (color[4] == nil and 1 or color[4]) or alpha)
    texture.yabTexturePath = nil
    return 1
end

local function SetVertexColorWithAlpha(texture, color, fallback, alpha)
    if not (texture and texture.SetVertexColor) then return 0 end
    color = type(color) == "table" and color or fallback
    if type(color) ~= "table" then return 0 end
    texture:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, alpha == nil and (color[4] == nil and 1 or color[4]) or alpha)
    return 1
end

local function SetTexturePath(texture, path)
    if not (texture and texture.SetTexture and path) then return 0 end
    if texture.yabTexturePath == path then return 0 end
    texture:SetTexture(path)
    texture.yabTexturePath = path
    texture.yabTextureAtlas = nil
    return 1
end

function Visuals:SetTextureAtlas(texture, atlas)
    if not (texture and texture.SetAtlas and atlas) then return 0 end
    if texture.yabTextureAtlas == atlas then return 0 end
    local ok = pcall(texture.SetAtlas, texture, atlas, false)
    if not ok then return 0 end
    texture.yabTextureAtlas = atlas
    texture.yabTexturePath = nil
    return 1
end

function Visuals:ApplyShadowFontObject(text)
    if not (text and type(text.SetFontObject) == "function") then return false end
    local fontObject = _G.GameFontHighlight
    if fontObject == nil then return false end
    return pcall(text.SetFontObject, text, fontObject)
end

function Visuals:ApplyOutlineShadow(text)
    if not text then return end
    if type(text.SetShadowColor) == "function" then
        pcall(text.SetShadowColor, text, 0, 0, 0, 1)
    end
    if type(text.SetShadowOffset) == "function" then
        pcall(text.SetShadowOffset, text, 1, -1)
    end
end

local function SetFont(text, snapshot, sizeOverride)
    if not (text and text.SetFont and snapshot) then return end
    local font = snapshot.fonts and snapshot.fonts.body
    local size = tonumber(sizeOverride) or (snapshot.metrics and snapshot.metrics.fontSize)
    if font and size then
        Visuals:ApplyShadowFontObject(text)
        text:SetFont(font, size, "OUTLINE")
        Visuals:ApplyOutlineShadow(text)
    end
end

Visuals.TextAnchors = Visuals.TextAnchors or {}

function Visuals.TextAnchors:OffsetValue(snapshot, key)
    local value = tonumber(snapshot and snapshot[key]) or 0
    if value < -16 then
        return -16
    elseif value > 16 then
        return 16
    end
    return value
end

function Visuals.TextAnchors:ApplySingle(text, button, point, baseX, baseY, offsetX, offsetY)
    if not (text and button and text.ClearAllPoints and text.SetPoint) then return end
    local x = baseX + offsetX
    local y = baseY + offsetY
    local signature = point .. ":" .. tostring(x) .. ":" .. tostring(y)
    if Visuals.textAnchorSignatures[text] == signature then return end
    text:ClearAllPoints()
    text:SetPoint(point, button, point, x, y)
    Visuals.textAnchorSignatures[text] = signature
end

function Visuals.TextAnchors:ApplyHotkey(text, button, snapshot)
    if not (text and button and text.ClearAllPoints and text.SetPoint) then return end
    local offsetX = self:OffsetValue(snapshot, "hotkeyOffsetX")
    local offsetY = self:OffsetValue(snapshot, "hotkeyOffsetY")
    local left = 2 + offsetX
    local right = -2 + offsetX
    local y = -1 + offsetY
    local signature = "hotkey:" .. tostring(left) .. ":" .. tostring(right) .. ":" .. tostring(y)
    if Visuals.textAnchorSignatures[text] == signature then return end
    text:ClearAllPoints()
    text:SetPoint("TOPRIGHT", button, "TOPRIGHT", right, y)
    text:SetPoint("TOPLEFT", button, "TOPLEFT", left, y)
    if text.SetJustifyH then text:SetJustifyH("RIGHT") end
    Visuals.textAnchorSignatures[text] = signature
end

function Visuals.TextAnchors:ApplyMacroName(text, button, visual, snapshot)
    if not (text and button and text.ClearAllPoints and text.SetPoint) then return end
    local width = math.max(tonumber(visual and visual.visualWidth) or 36, 1)
    local visualHeight = math.max(tonumber(visual and visual.visualHeight) or width, 1)
    local fontHeight = math.max(math.floor((tonumber(snapshot and snapshot.macroNameSize) or 10) + 0.5), 1)
    local height = math.min(visualHeight, fontHeight)
    local offsetX = self:OffsetValue(snapshot, "macroNameOffsetX")
    local offsetY = self:OffsetValue(snapshot, "macroNameOffsetY")
    local y = 1 + offsetY
    local signature = "macro:" .. tostring(width) .. ":" .. tostring(height) .. ":" .. tostring(offsetX) .. ":" .. tostring(y)
    if text.SetSize then
        text:SetSize(width, height)
    else
        if text.SetWidth then text:SetWidth(width) end
        if text.SetHeight then text:SetHeight(height) end
    end
    if text.SetJustifyH then text:SetJustifyH("CENTER") end
    if text.SetJustifyV then text:SetJustifyV("MIDDLE") end
    Visuals:ApplySingleLineTextConstraints(text)
    text:ClearAllPoints()
    text:SetPoint("BOTTOM", button, "BOTTOM", offsetX, y)
    Visuals.textAnchorSignatures[text] = signature
end

function Visuals.TextAnchors:ApplyCooldown(cooldown, snapshot)
    if not (cooldown and type(cooldown.GetCountdownFontString) == "function") then return end
    local text = cooldown:GetCountdownFontString()
    if not (text and text.ClearAllPoints and text.SetPoint) then return end
    local cache = EnsureCooldownCache(cooldown)

    local offsetX = self:OffsetValue(snapshot, "cooldownTextOffsetX")
    local offsetY = self:OffsetValue(snapshot, "cooldownTextOffsetY")
    local signature = "cooldown:" .. tostring(offsetX) .. ":" .. tostring(offsetY)
    if cache.countdownAnchorSignature == signature then return end

    text:ClearAllPoints()
    text:SetPoint("CENTER", cooldown, "CENTER", offsetX, offsetY)
    cache.countdownAnchorSignature = signature
end

function Visuals.TextAnchors:Apply(button, visual, snapshot)
    if InCombat() or not (button and visual) then return end
    self:ApplyHotkey(visual.hotkey, button, snapshot)
    self:ApplySingle(visual.count, button, "BOTTOMRIGHT", -2, 1, self:OffsetValue(snapshot, "countOffsetX"), self:OffsetValue(snapshot, "countOffsetY"))
    self:ApplyMacroName(visual.name, button, visual, snapshot)
    self:ApplyCooldown(visual.cooldown, snapshot)
    self:ApplyCooldown(visual.chargeCooldown, snapshot)
end

function Visuals:ApplySingleLineTextConstraints(text)
    if not text then return end
    if type(text.SetWordWrap) == "function" then
        pcall(text.SetWordWrap, text, false)
    end
    if type(text.SetNonSpaceWrap) == "function" then
        pcall(text.SetNonSpaceWrap, text, false)
    end
    if type(text.SetMaxLines) == "function" then
        pcall(text.SetMaxLines, text, 1)
    end
end

local function ApplyTextFonts(button, visual, snapshot)
    if not visual then return end
    snapshot = snapshot or DEFAULT_RUNTIME_SNAPSHOT
    Visuals:ApplySingleLineTextConstraints(visual.hotkey)
    Visuals:ApplySingleLineTextConstraints(visual.count)
    Visuals:ApplySingleLineTextConstraints(visual.name)
    SetFont(visual.hotkey, Visuals.theme, snapshot.hotkeySize)
    SetFont(visual.count, Visuals.theme, snapshot.countSize)
    SetFont(visual.name, Visuals.theme, snapshot.macroNameSize)
    local external = visual.regions ~= nil
    local themeColor = Visuals.theme and Visuals.theme.colors and Visuals.theme.colors.text or DEFAULT_TEXT_COLOR
    if snapshot.hotkeyColor or not external then SetTextColor(visual.hotkey, snapshot.hotkeyColor or themeColor) end
    if snapshot.countColor or not external then SetTextColor(visual.count, snapshot.countColor or themeColor) end
    if snapshot.macroNameColor or not external then SetTextColor(visual.name, snapshot.macroNameColor or themeColor) end
    Visuals:ApplyCooldownTextFont(visual.cooldown, snapshot)
    Visuals:ApplyCooldownTextFont(visual.chargeCooldown, snapshot)
    Visuals:ApplyCooldownTextColor(visual.cooldown, snapshot.cooldownTextColor)
    Visuals:ApplyCooldownTextColor(visual.chargeCooldown, snapshot.cooldownTextColor)
    Visuals.TextAnchors:Apply(button, visual, snapshot)
end

function Visuals:ApplyCooldownTextColor(cooldown, color)
    if not (cooldown and type(cooldown.GetCountdownFontString) == "function") then return end
    local ok, text = pcall(cooldown.GetCountdownFontString, cooldown)
    if not (ok and text) then return end
    local cache = EnsureCooldownCache(cooldown)
    if not cache.countdownTextColorCaptured then
        cache.countdownTextColorCaptured = true
        if type(text.GetTextColor) == "function" then
            local colorOk, r, g, b, a = pcall(text.GetTextColor, text)
            if colorOk then
                cache.countdownTextColor = { r, g, b, a == nil and 1 or a }
            end
        end
        if type(text.GetAlpha) == "function" then
            local alphaOk, alpha = pcall(text.GetAlpha, text)
            if alphaOk and type(alpha) == "number" then
                cache.countdownTextAlpha = alpha
            end
        end
    end
    if type(color) == "table" then
        SetTextColor(text, color)
    elseif cache.countdownTextColor then
        local original = cache.countdownTextColor
        pcall(text.SetTextColor, text, original[1], original[2], original[3], original[4])
        if cache.countdownTextAlpha ~= nil and type(text.SetAlpha) == "function" then
            pcall(text.SetAlpha, text, cache.countdownTextAlpha)
        end
        TEXT_COLOR_CACHE[text] = nil
    end
end

function Visuals:ApplyCooldownTextFont(cooldown, snapshot)
    if not (cooldown and type(cooldown.GetCountdownFontString) == "function") then return end
    local ok, text = pcall(cooldown.GetCountdownFontString, cooldown)
    if not (ok and text and type(text.SetFont) == "function") then return end
    self:ApplySingleLineTextConstraints(text)

    local cache = EnsureCooldownCache(cooldown)
    if not cache.countdownFontCaptured then
        cache.countdownFontCaptured = true
        if type(text.GetFontObject) == "function" then
            local objectOk, fontObject = pcall(text.GetFontObject, text)
            if objectOk and self:IsExternalStateValueSafe(fontObject) then
                cache.countdownFontObjectCaptured = true
                cache.countdownFontObject = fontObject
            end
        end
        if type(text.GetFont) == "function" then
            local fontOk, font, size, flags = pcall(text.GetFont, text)
            if fontOk then
                cache.countdownFont = font
                cache.countdownFontSize = size
                cache.countdownFontFlags = flags
            end
        end
    end
    if not cache.countdownShadowCaptured then
        cache.countdownShadowCaptured = true
        if type(text.GetShadowColor) == "function" then
            local colorOk, r, g, b, a = pcall(text.GetShadowColor, text)
            if colorOk
                and self:IsExternalStateValueSafe(r)
                and self:IsExternalStateValueSafe(g)
                and self:IsExternalStateValueSafe(b)
                and self:IsExternalStateValueSafe(a) then
                cache.countdownShadowColor = { r, g, b, a }
            end
        end
        if type(text.GetShadowOffset) == "function" then
            local offsetOk, x, y = pcall(text.GetShadowOffset, text)
            if offsetOk
                and self:IsExternalStateValueSafe(x)
                and self:IsExternalStateValueSafe(y) then
                cache.countdownShadowX = x
                cache.countdownShadowY = y
                cache.countdownShadowOffsetCaptured = true
            end
        end
    end

    local size = tonumber(snapshot and snapshot.cooldownTextSize) or 0
    if size < 1 then
        if cache.countdownFontObjectCaptured and cache.countdownFontObject ~= nil
            and type(text.SetFontObject) == "function" then
            pcall(text.SetFontObject, text, cache.countdownFontObject)
        end
        if cache.countdownFont and cache.countdownFontSize then
            if cache.countdownFontFlags ~= nil then
                pcall(text.SetFont, text, cache.countdownFont, cache.countdownFontSize, cache.countdownFontFlags)
            else
                pcall(text.SetFont, text, cache.countdownFont, cache.countdownFontSize)
            end
        end
        if cache.countdownShadowColor and type(text.SetShadowColor) == "function" then
            local color = cache.countdownShadowColor
            pcall(text.SetShadowColor, text, color[1], color[2], color[3], color[4])
        end
        if cache.countdownShadowOffsetCaptured and type(text.SetShadowOffset) == "function" then
            pcall(text.SetShadowOffset, text, cache.countdownShadowX, cache.countdownShadowY)
        end
        return
    end
    if size > 32 then size = 32 end

    local font = self.theme and self.theme.fonts and self.theme.fonts.body or cache.countdownFont
    if font then
        self:ApplyShadowFontObject(text)
        pcall(text.SetFont, text, font, size, "OUTLINE")
        self:ApplyOutlineShadow(text)
    end
end

function Visuals:AddExternalTextRegion(view, region)
    if not (view and region) then return end
    view.regions = view.regions or {}
    for index = 1, #view.regions do
        if view.regions[index] == region then return end
    end
    view.regions[#view.regions + 1] = region
end

function Visuals:AddExternalTextCooldown(view, cooldown)
    if not (view and cooldown) then return end
    view.cooldowns = view.cooldowns or {}
    for index = 1, #view.cooldowns do
        if view.cooldowns[index] == cooldown then return end
    end
    view.cooldowns[#view.cooldowns + 1] = cooldown
end

function Visuals:GetExternalTextView(button, visual)
    if not button then return nil end
    local view = self.externalTextViews[button]
    if not view then
        view = { regions = {}, cooldowns = {} }
        self.externalTextViews[button] = view
    end
    visual = visual or (self.buttons and self.buttons[button]) or nil
    view.hotkey = (visual and visual.hotkey) or button.HotKey
    view.count = (visual and visual.count) or button.Count
    view.name = (visual and visual.name) or button.Name
    view.cooldown = (visual and visual.cooldown) or button.cooldown or button.Cooldown
    view.chargeCooldown = (visual and visual.chargeCooldown) or button.chargeCooldown or button.ChargeCooldown
    return view
end

function Visuals:CaptureExternalTextRegionState(region)
    if not region or self.externalTextRegionState[region] then return end
    local state = {}
    if type(region.GetFontObject) == "function" then
        local ok, fontObject = pcall(region.GetFontObject, region)
        if ok and self:IsExternalStateValueSafe(fontObject) then
            state.fontObjectCaptured = true
            state.fontObject = fontObject
        end
    end
    if type(region.GetTextColor) == "function" then
        local ok, r, g, b, a = pcall(region.GetTextColor, region)
        if ok then
            state.textColorCaptured = true
            state.textColor = { r, g, b, a == nil and 1 or a }
        end
    end
    if type(region.GetFont) == "function" then
        local ok, font, size, flags = pcall(region.GetFont, region)
        if ok then
            state.fontCaptured = true
            state.font = font
            state.fontSize = size
            state.fontFlags = flags
        end
    end
    if type(region.GetShadowColor) == "function" then
        local ok, r, g, b, a = pcall(region.GetShadowColor, region)
        if ok
            and self:IsExternalStateValueSafe(r)
            and self:IsExternalStateValueSafe(g)
            and self:IsExternalStateValueSafe(b)
            and self:IsExternalStateValueSafe(a) then
            state.shadowColorCaptured = true
            state.shadowColor = { r, g, b, a }
        end
    end
    if type(region.GetShadowOffset) == "function" then
        local ok, x, y = pcall(region.GetShadowOffset, region)
        if ok
            and self:IsExternalStateValueSafe(x)
            and self:IsExternalStateValueSafe(y) then
            state.shadowOffsetCaptured = true
            state.shadowX = x
            state.shadowY = y
        end
    end
    if type(region.GetJustifyH) == "function" then
        local ok, justify = pcall(region.GetJustifyH, region)
        if ok then
            state.justifyHCaptured = true
            state.justifyH = justify
        end
    end
    if type(region.GetJustifyV) == "function" then
        local ok, justify = pcall(region.GetJustifyV, region)
        if ok then
            state.justifyVCaptured = true
            state.justifyV = justify
        end
    end
    local wordWrapGetter = region.CanWordWrap or region.GetWordWrap
    if type(wordWrapGetter) == "function" then
        local ok, wordWrap = pcall(wordWrapGetter, region)
        if ok then
            state.wordWrapCaptured = true
            state.wordWrap = wordWrap == true
        end
    end
    local nonSpaceWrapGetter = region.CanNonSpaceWrap or region.GetNonSpaceWrap
    if type(nonSpaceWrapGetter) == "function" then
        local ok, nonSpaceWrap = pcall(nonSpaceWrapGetter, region)
        if ok then
            state.nonSpaceWrapCaptured = true
            state.nonSpaceWrap = nonSpaceWrap == true
        end
    end
    if type(region.GetMaxLines) == "function" then
        local ok, maxLines = pcall(region.GetMaxLines, region)
        if ok and type(maxLines) == "number" then
            state.maxLinesCaptured = true
            state.maxLines = maxLines
        end
    end
    if type(region.GetDrawLayer) == "function" then
        local ok, layer, sublevel = pcall(region.GetDrawLayer, region)
        if ok then
            state.drawLayerCaptured = true
            state.drawLayer = layer
            state.drawSublevel = sublevel
        end
    end
    if type(region.GetAlpha) == "function" then
        local ok, alpha = pcall(region.GetAlpha, region)
        if ok and type(alpha) == "number" then
            state.alphaCaptured = true
            state.alpha = alpha
        end
    end
    if type(region.GetSize) == "function" then
        local ok, width, height = pcall(region.GetSize, region)
        if ok and type(width) == "number" and type(height) == "number" then
            state.sizeCaptured = true
            state.width = width
            state.height = height
        end
    elseif type(region.GetWidth) == "function" and type(region.GetHeight) == "function" then
        local okWidth, width = pcall(region.GetWidth, region)
        local okHeight, height = pcall(region.GetHeight, region)
        if okWidth and okHeight and type(width) == "number" and type(height) == "number" then
            state.sizeCaptured = true
            state.width = width
            state.height = height
        end
    end
    if type(region.GetNumPoints) == "function" and type(region.GetPoint) == "function" then
        local ok, count = pcall(region.GetNumPoints, region)
        if ok and type(count) == "number" then
            state.pointsCaptured = true
            state.points = {}
            for index = 1, count do
                local pointOk, point, relativeTo, relativePoint, x, y = pcall(region.GetPoint, region, index)
                if pointOk and point then
                    state.points[#state.points + 1] = { point, relativeTo, relativePoint, x, y }
                end
            end
        end
    end
    self.externalTextRegionState[region] = state
end

function Visuals:CaptureExternalTextState(button, visual)
    local view = self:GetExternalTextView(button, visual)
    if not view then return nil end
    self:AddExternalTextRegion(view, view.hotkey)
    self:AddExternalTextRegion(view, view.count)
    self:AddExternalTextRegion(view, view.name)
    self:AddExternalTextCooldown(view, view.cooldown)
    self:AddExternalTextCooldown(view, view.chargeCooldown)
    for index = 1, #view.cooldowns do
        local cooldown = view.cooldowns[index]
        if type(cooldown.GetCountdownFontString) == "function" then
            local ok, text = pcall(cooldown.GetCountdownFontString, cooldown)
            if ok then self:AddExternalTextRegion(view, text) end
        end
    end
    for index = 1, #view.regions do
        self:CaptureExternalTextRegionState(view.regions[index])
    end
    return view
end

function Visuals:RestoreExternalTextRegionState(region)
    if not region then return 0 end
    local state = self.externalTextRegionState[region]
    self.textAnchorSignatures[region] = nil
    if not state then return 0 end
    local writes = 0
    if state.fontObjectCaptured and state.fontObject ~= nil
        and type(region.SetFontObject) == "function" then
        if pcall(region.SetFontObject, region, state.fontObject) then writes = writes + 1 end
    end
    if state.fontCaptured and state.font and state.fontSize and type(region.SetFont) == "function" then
        local ok
        if state.fontFlags ~= nil then
            ok = pcall(region.SetFont, region, state.font, state.fontSize, state.fontFlags)
        else
            ok = pcall(region.SetFont, region, state.font, state.fontSize)
        end
        if ok then writes = writes + 1 end
    end
    if state.shadowColorCaptured and state.shadowColor
        and type(region.SetShadowColor) == "function" then
        local color = state.shadowColor
        if pcall(region.SetShadowColor, region, color[1], color[2], color[3], color[4]) then
            writes = writes + 1
        end
    end
    if state.shadowOffsetCaptured and type(region.SetShadowOffset) == "function" then
        if pcall(region.SetShadowOffset, region, state.shadowX, state.shadowY) then
            writes = writes + 1
        end
    end
    if state.textColorCaptured and state.textColor and type(region.SetTextColor) == "function" then
        local color = state.textColor
        if pcall(region.SetTextColor, region, color[1], color[2], color[3], color[4]) then writes = writes + 1 end
        TEXT_COLOR_CACHE[region] = nil
    end
    if state.sizeCaptured and type(region.SetSize) == "function" then
        if pcall(region.SetSize, region, state.width, state.height) then writes = writes + 1 end
    end
    if state.pointsCaptured and type(region.ClearAllPoints) == "function" and type(region.SetPoint) == "function" then
        if pcall(region.ClearAllPoints, region) then writes = writes + 1 end
        for index = 1, #state.points do
            local point = state.points[index]
            if pcall(region.SetPoint, region, point[1], point[2], point[3], point[4], point[5]) then
                writes = writes + 1
            end
        end
    end
    if state.justifyHCaptured and state.justifyH and type(region.SetJustifyH) == "function" then
        if pcall(region.SetJustifyH, region, state.justifyH) then writes = writes + 1 end
    end
    if state.justifyVCaptured and state.justifyV and type(region.SetJustifyV) == "function" then
        if pcall(region.SetJustifyV, region, state.justifyV) then writes = writes + 1 end
    end
    if state.wordWrapCaptured and type(region.SetWordWrap) == "function" then
        if pcall(region.SetWordWrap, region, state.wordWrap) then writes = writes + 1 end
    end
    if state.nonSpaceWrapCaptured and type(region.SetNonSpaceWrap) == "function" then
        if pcall(region.SetNonSpaceWrap, region, state.nonSpaceWrap) then writes = writes + 1 end
    end
    if state.maxLinesCaptured and type(region.SetMaxLines) == "function" then
        if pcall(region.SetMaxLines, region, state.maxLines) then writes = writes + 1 end
    end
    if state.drawLayerCaptured and state.drawLayer and type(region.SetDrawLayer) == "function" then
        local ok
        if state.drawSublevel ~= nil then
            ok = pcall(region.SetDrawLayer, region, state.drawLayer, state.drawSublevel)
        else
            ok = pcall(region.SetDrawLayer, region, state.drawLayer)
        end
        if ok then writes = writes + 1 end
    end
    if state.alphaCaptured and type(region.SetAlpha) == "function" then
        if pcall(region.SetAlpha, region, state.alpha) then writes = writes + 1 end
    end
    self.externalTextRegionState[region] = nil
    return writes
end

function Visuals:RestoreExternalTextState(button)
    if not button then return 0 end
    local view = self.externalTextViews[button]
    local writes = 0
    if view then
        for index = 1, #(view.regions or {}) do
            writes = writes + self:RestoreExternalTextRegionState(view.regions[index])
        end
        for index = 1, #(view.cooldowns or {}) do
            COOLDOWN_CACHE[view.cooldowns[index]] = nil
        end
    end
    self.externalTextSnapshots[button] = nil
    self.externalTextViews[button] = nil
    return writes
end

function Visuals:InvalidateExternalTextLayout(button, view)
    view = view or (button and self.externalTextViews[button]) or nil
    if not view then return end
    if view.hotkey then self.textAnchorSignatures[view.hotkey] = nil end
    if view.count then self.textAnchorSignatures[view.count] = nil end
    if view.name then self.textAnchorSignatures[view.name] = nil end
    for index = 1, #(view.cooldowns or {}) do
        local cache = COOLDOWN_CACHE[view.cooldowns[index]]
        if cache then cache.countdownAnchorSignature = nil end
    end
end

function Visuals:ApplyExternalTextSnapshot(button, snapshot)
    if not button then return false end
    snapshot = snapshot or button.yabConfigSnapshot or DEFAULT_RUNTIME_SNAPSHOT
    local visual = self.buttons and self.buttons[button] or nil
    local view = self:CaptureExternalTextState(button, visual)
    if not view then return false end
    if not self.theme then self:RefreshTheme("external-text") end
    self.externalTextSnapshots[button] = snapshot
    if visual then visual.runtimeSnapshot = snapshot end
    self:InvalidateExternalTextLayout(button, view)
    ApplyTextFonts(button, view, snapshot)
    return true
end

local function PrepareText(text, justify)
    if not text then return end
    if text.SetDrawLayer then text:SetDrawLayer("OVERLAY", 7) end
    if text.SetJustifyH and justify then text:SetJustifyH(justify) end
    Visuals:ApplySingleLineTextConstraints(text)
end

local function ApplyIconCrop(icon, zoom)
    if not (icon and icon.SetTexCoord) then return end
    zoom = tonumber(zoom) or 0.08
    if zoom < 0 then zoom = 0 end
    if zoom > 0.24 then zoom = 0.24 end
    icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
end

local function ApplyFlatIconCrop(icon, zoom, aspect)
    if not (icon and icon.SetTexCoord) then return end
    zoom = tonumber(zoom) or 0.08
    if zoom < 0 then zoom = 0 end
    if zoom > 0.24 then zoom = 0.24 end
    aspect = tonumber(aspect) or FLAT_VISUAL_ASPECT
    if aspect <= 1 then
        ApplyIconCrop(icon, zoom)
        return
    end
    local sourceWidth = 1 - (zoom * 2)
    local sourceHeight = sourceWidth / aspect
    if sourceHeight > 1 then sourceHeight = 1 end
    local top = (1 - sourceHeight) * 0.5
    icon:SetTexCoord(zoom, 1 - zoom, top, 1 - top)
end

GetFrameSize = function(frame, fallbackWidth, fallbackHeight)
    local width, height
    if frame and frame.GetSize then
        width, height = frame:GetSize()
    end
    width = tonumber(width) or tonumber(fallbackWidth) or 36
    height = tonumber(height) or tonumber(fallbackHeight) or width
    if width < 1 then width = 1 end
    if height < 1 then height = 1 end
    return width, height
end

ApplyVisualRect = function(button, visual, region, extraOutset)
    if not (button and visual and region) then return end
    extraOutset = tonumber(extraOutset) or 0
    local insetX = (visual.visualInsetX or 0) - extraOutset
    local insetY = (visual.visualInsetY or 0) - extraOutset
    if region.ClearAllPoints then region:ClearAllPoints() end
    if region.SetPoint then
        region:SetPoint("TOPLEFT", button, "TOPLEFT", insetX, -insetY)
        region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -insetX, insetY)
    elseif region.SetAllPoints then
        region:SetAllPoints(button)
    end
end

local function HideNativePetAutoCastOverlay(overlay)
    if not overlay then return 0 end
    local writes = 0
    if overlay.ShowAutoCastEnabled then
        overlay:ShowAutoCastEnabled(false)
    end
    overlay.autoCastEnabled = false
    local shine = overlay.Shine
    if shine and shine.Anim and shine.Anim.Stop then
        shine.Anim:Stop()
    end
    writes = writes + RegionShown(overlay, false)
    writes = writes + RegionShown(overlay.Corners, false)
    writes = writes + RegionShown(shine, false)
    writes = writes + RegionShown(overlay.Mask, false)
    writes = writes + RegionAlpha(overlay.Corners, 0)
    writes = writes + RegionAlpha(shine, 0)
    writes = writes + RegionAlpha(overlay.Mask, 0)
    return writes
end

local function LayoutPetAutoCastOverlay(button, visual)
    local overlay = visual and (visual.autoCastOverlay or (button and button.AutoCastOverlay))
    if not (button and visual and overlay) then return 0 end
    local style = SHAPE_STYLES[visual.runtimeSkin or "square"] or SHAPE_STYLES.square
    if style.circular == true then
        local writes = HideNativePetAutoCastOverlay(overlay)
        if SetPetAutoCastCircleVisual then
            writes = writes + SetPetAutoCastCircleVisual(button, visual, visual.petAutoCastAllowed == true, visual.petAutoCastEnabled == true)
        end
        return writes
    end
    if InCombat() then
        visual.pendingPetAutoCastLayout = true
        return 0
    end
    local writes = 0
    local restoringNativeOverlay = visual.petAutoCastMode ~= "native-rect"
    if restoringNativeOverlay and HidePetAutoCastCircleVisual then
        writes = writes + HidePetAutoCastCircleVisual(visual)
    end
    visual.petAutoCastMode = "native-rect"
    local insetX = (tonumber(visual.visualInsetX) or 0) - PET_AUTOCAST_RECT_OUTSET
    local insetY = (tonumber(visual.visualInsetY) or 0) - PET_AUTOCAST_RECT_OUTSET
    if overlay.ClearAllPoints then overlay:ClearAllPoints() end
    if overlay.SetPoint then
        overlay:SetPoint("TOPLEFT", button, "TOPLEFT", insetX, -insetY)
        overlay:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -insetX, insetY)
    end
    if button.GetFrameLevel and overlay.SetFrameLevel then
        overlay:SetFrameLevel((button:GetFrameLevel() or 1) + 7)
    end
    local shine = overlay.Shine
    if shine and shine.ClearAllPoints and shine.SetPoint then
        if restoringNativeOverlay and shine.Anim and shine.Anim.Stop then
            shine.Anim:Stop()
        end
        shine:ClearAllPoints()
        shine:SetPoint("TOPLEFT", overlay, "TOPLEFT", -PET_AUTOCAST_RECT_SHINE_OUTSET, PET_AUTOCAST_RECT_SHINE_OUTSET)
        shine:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", PET_AUTOCAST_RECT_SHINE_OUTSET, -PET_AUTOCAST_RECT_SHINE_OUTSET)
        writes = writes + RegionAlpha(shine, 1)
        if restoringNativeOverlay then
            writes = writes + RegionShown(shine, false)
        end
    end
    local mask = overlay.Mask
    if mask and mask.ClearAllPoints and mask.SetPoint then
        mask:ClearAllPoints()
        mask:SetPoint("TOPLEFT", overlay, "TOPLEFT", PET_AUTOCAST_RECT_MASK_INSET, -PET_AUTOCAST_RECT_MASK_INSET)
        mask:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -PET_AUTOCAST_RECT_MASK_INSET, PET_AUTOCAST_RECT_MASK_INSET)
        writes = writes + RegionAlpha(mask, 1)
        writes = writes + RegionShown(mask, true)
    end
    local corners = overlay.Corners
    if corners and corners.SetAllPoints then
        if corners.ClearAllPoints then corners:ClearAllPoints() end
        corners:SetAllPoints(overlay)
        writes = writes + RegionAlpha(corners, 1)
        writes = writes + RegionShown(corners, true)
    end
    if restoringNativeOverlay then
        overlay.autoCastEnabled = false
    end
    visual.autoCastOverlay = overlay
    visual.pendingPetAutoCastLayout = nil
    return writes + 1
end

local function SetPetAutoCastVisual(button, visual, allowed, enabled)
    local overlay = visual and (visual.autoCastOverlay or (button and button.AutoCastOverlay))
    allowed = allowed == true
    enabled = enabled == true
    local style = SHAPE_STYLES[visual and visual.runtimeSkin or "square"] or SHAPE_STYLES.square
    if style.circular == true then
        local writes = overlay and HideNativePetAutoCastOverlay(overlay) or 0
        if SetPetAutoCastCircleVisual then
            writes = writes + SetPetAutoCastCircleVisual(button, visual, allowed, enabled)
        end
        visual.petAutoCastAllowed = allowed
        visual.petAutoCastEnabled = enabled
        return writes
    end
    if not overlay then return 0 end
    local writes = LayoutPetAutoCastOverlay(button, visual)
    writes = writes + RegionShown(overlay, allowed)
    writes = writes + RegionShown(overlay.Mask, allowed)
    writes = writes + RegionShown(overlay.Corners, allowed)
    if overlay.ShowAutoCastEnabled then
        overlay:ShowAutoCastEnabled(allowed and enabled)
    end
    visual.petAutoCastAllowed = allowed
    visual.petAutoCastEnabled = enabled
    return writes
end

local function UpdateVisualGeometry(button, visual, style, padding, options)
    if not (button and visual) then return 0 end
    if InCombat() then
        visual.pendingGeometry = true
        return 0
    end
    options = options or {}
    padding = tonumber(padding) or 0
    local buttonWidth, buttonHeight = GetFrameSize(button, options.width or options.size, options.height or options.size)
    local visualWidth = buttonWidth - (padding * 2)
    local visualHeight = buttonHeight - (padding * 2)
    if visualWidth < 1 then visualWidth = 1 end
    if visualHeight < 1 then visualHeight = 1 end
    local aspect = style and tonumber(style.aspect) or nil
    if aspect and aspect > 1 then
        local flatHeight = math.floor((visualWidth / aspect) + 0.5)
        if flatHeight < 1 then flatHeight = 1 end
        if flatHeight < visualHeight then
            visualHeight = flatHeight
        end
    end
    local insetX = (buttonWidth - visualWidth) * 0.5
    local insetY = (buttonHeight - visualHeight) * 0.5
    if visual.visualWidth == visualWidth and visual.visualHeight == visualHeight and visual.visualInsetX == insetX and visual.visualInsetY == insetY then
        visual.pendingGeometry = nil
        return 0
    end
    visual.visualWidth = visualWidth
    visual.visualHeight = visualHeight
    visual.visualInsetX = insetX
    visual.visualInsetY = insetY
    visual.pendingGeometry = nil
    return 1
end

local function ClampTextureSubLevel(subLevel)
    if subLevel == nil then return nil end
    subLevel = tonumber(subLevel) or 0
    if subLevel < -8 then return -8 end
    if subLevel > 7 then return 7 end
    return subLevel
end

local function CreateSkinTexture(button, layer, alpha, subLevel)
    local drawLayer = layer or "OVERLAY"
    local textureSubLevel = ClampTextureSubLevel(subLevel)
    local texture = button:CreateTexture(nil, drawLayer, nil, textureSubLevel)
    texture:SetAllPoints(button)
    if texture.SetDrawLayer then
        texture:SetDrawLayer(drawLayer, textureSubLevel or 0)
    end
    if alpha then texture:SetAlpha(alpha) end
    return texture
end

local function CreateBorderLine(button)
    local line = button:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(0, 0, 0, 1)
    return line
end

local function CreatePetCheckedLine(button, subLevel)
    local textureSubLevel = ClampTextureSubLevel(subLevel)
    local line = button:CreateTexture(nil, "OVERLAY", nil, textureSubLevel)
    if line.SetDrawLayer then
        line:SetDrawLayer("OVERLAY", textureSubLevel or 0)
    end
    line:SetColorTexture(PET_CHECKED_INNER_COLOR[1], PET_CHECKED_INNER_COLOR[2], PET_CHECKED_INNER_COLOR[3], PET_CHECKED_INNER_ALPHA)
    line:Hide()
    return line
end

local function CreatePetCheckedLineSet(button, subLevel)
    return {
        top = CreatePetCheckedLine(button, subLevel),
        bottom = CreatePetCheckedLine(button, subLevel),
        left = CreatePetCheckedLine(button, subLevel),
        right = CreatePetCheckedLine(button, subLevel),
    }
end

local function EnsurePetCheckedInnerVisual(button, visual)
    if not IsPetCheckedVisual(button, visual) then return false end
    if visual.petCheckedState then return true end
    if InCombat() then
        visual.pendingCheckedRingLayout = true
        return false
    end
    visual.petCheckedState = CreateSkinTexture(button, "OVERLAY", nil, 5)
    if visual.petCheckedState.SetBlendMode then
        visual.petCheckedState:SetBlendMode("ADD")
    end
    visual.petCheckedState:Hide()
    return true
end

local function StopTextureAnimation(texture, alpha)
    if not texture then return 0 end
    local group = texture.yabPetAutoCastRotationAnim or texture.yabPulseAnim
    if group and group.Stop and (not group.IsPlaying or group:IsPlaying()) then
        group:Stop()
    end
    if texture.SetRotation then texture:SetRotation(0) end
    return RegionAlpha(texture, alpha or 1)
end

local function EnsurePetAutoCastRotationAnimation(texture)
    if not (texture and texture.CreateAnimationGroup) then return nil end
    if texture.yabPetAutoCastRotationAnim then return texture.yabPetAutoCastRotationAnim end
    local group = texture:CreateAnimationGroup()
    if not group then return nil end
    if group.SetLooping then group:SetLooping("REPEAT") end
    if not group.CreateAnimation then
        if group.Stop then group:Stop() end
        return nil
    end
    local created, rotation = pcall(group.CreateAnimation, group, "Rotation")
    if not (created and rotation) then
        if group.Stop then group:Stop() end
        return nil
    end
    local ok = true
    if rotation.SetDegrees then
        ok = pcall(rotation.SetDegrees, rotation, -360) and ok
    elseif rotation.SetRadians then
        ok = pcall(rotation.SetRadians, rotation, -math.pi * 2) and ok
    end
    if rotation.SetDuration then ok = pcall(rotation.SetDuration, rotation, PET_AUTOCAST_CIRCLE_ANTS_DURATION) and ok end
    if rotation.SetOrder then ok = pcall(rotation.SetOrder, rotation, 1) and ok end
    if rotation.SetOrigin then ok = pcall(rotation.SetOrigin, rotation, "CENTER", 0, 0) and ok end
    if not ok then
        if group.Stop then group:Stop() end
        return nil
    end
    texture.yabPetAutoCastRotationAnim = group
    return group
end

local function EnsurePetAutoCastCircleVisual(button, visual)
    if not (button and visual) then return nil end
    local circle = visual.petAutoCastCircle
    if circle then return circle end
    if InCombat() then return nil end
    local marker = CreateSkinTexture(button, "OVERLAY", nil, PET_AUTOCAST_CIRCLE_MARKER_SUBLEVEL)
    local ants = CreateSkinTexture(button, "OVERLAY", nil, PET_AUTOCAST_CIRCLE_ANTS_SUBLEVEL)
    marker:Hide()
    ants:Hide()
    SetTexturePath(marker, PET_AUTOCAST_CIRCLE_MARKER_TEXTURE)
    SetTexturePath(ants, PET_AUTOCAST_CIRCLE_ANTS_TEXTURE)
    SetVertexColor(marker, PET_AUTOCAST_CIRCLE_MARKER_COLOR, PET_AUTOCAST_CIRCLE_MARKER_COLOR)
    SetVertexColor(ants, PET_AUTOCAST_CIRCLE_ANTS_COLOR, PET_AUTOCAST_CIRCLE_ANTS_COLOR)
    if marker.SetBlendMode then marker:SetBlendMode("ADD") end
    if ants.SetBlendMode then ants:SetBlendMode("BLEND") end
    EnsurePetAutoCastRotationAnimation(ants)
    circle = { marker = marker, ants = ants }
    visual.petAutoCastCircle = circle
    return circle
end

local function LayoutPetAutoCastCircleVisual(button, visual)
    local circle = visual and visual.petAutoCastCircle
    if not circle then return 0 end
    if InCombat() then
        visual.pendingPetAutoCastLayout = true
        return 0
    end
    ApplyVisualRect(button, visual, circle.marker, 0)
    ApplyVisualRect(button, visual, circle.ants, 0)
    visual.pendingPetAutoCastLayout = nil
    return 1
end

HidePetAutoCastCircleVisual = function(visual)
    local writes = 0
    local circle = visual and visual.petAutoCastCircle
    if circle then
        writes = writes + StopTextureAnimation(circle.ants, 0)
        writes = writes + RegionShown(circle.ants, false)
        writes = writes + RegionShown(circle.marker, false)
        writes = writes + RegionAlpha(circle.marker, PET_AUTOCAST_CIRCLE_MARKER_ALPHA)
    end
    return writes
end

SetPetAutoCastCircleVisual = function(button, visual, allowed, enabled)
    if not (button and visual) then return 0 end
    allowed = allowed == true
    enabled = allowed and enabled == true
    local circle = EnsurePetAutoCastCircleVisual(button, visual)
    if not circle then
        visual.pendingPetAutoCastLayout = true
        return 0
    end
    local writes = 0
    writes = writes + LayoutPetAutoCastCircleVisual(button, visual)
    if circle.marker then
        writes = writes + SetTexturePath(circle.marker, PET_AUTOCAST_CIRCLE_MARKER_TEXTURE)
        writes = writes + SetVertexColor(circle.marker, PET_AUTOCAST_CIRCLE_MARKER_COLOR, PET_AUTOCAST_CIRCLE_MARKER_COLOR)
        writes = writes + RegionAlpha(circle.marker, PET_AUTOCAST_CIRCLE_MARKER_ALPHA)
    end
    if circle.ants then
        writes = writes + SetTexturePath(circle.ants, PET_AUTOCAST_CIRCLE_ANTS_TEXTURE)
        writes = writes + SetVertexColor(circle.ants, PET_AUTOCAST_CIRCLE_ANTS_COLOR, PET_AUTOCAST_CIRCLE_ANTS_COLOR)
    end
    if allowed then
        if enabled then
            local group = EnsurePetAutoCastRotationAnimation(circle.ants)
            writes = writes + RegionShown(circle.marker, false)
            writes = writes + RegionAlpha(circle.ants, PET_AUTOCAST_CIRCLE_ANTS_ALPHA)
            writes = writes + RegionShown(circle.ants, group ~= nil)
            if group and group.Play and not (group.IsPlaying and group:IsPlaying()) then
                group:Play()
            end
        else
            writes = writes + RegionShown(circle.marker, true)
            writes = writes + StopTextureAnimation(circle.ants, 0)
            writes = writes + RegionShown(circle.ants, false)
        end
    else
        writes = writes + RegionShown(circle.marker, false)
        writes = writes + StopTextureAnimation(circle.ants, 0)
        writes = writes + RegionShown(circle.ants, false)
    end
    visual.petAutoCastMode = "yui-circle-rotation"
    return writes
end

local function ReleasePetAutoCastVisual(button, visual)
    if not visual then return 0 end
    local overlay = visual.autoCastOverlay or (button and button.AutoCastOverlay)
    local writes = overlay and HideNativePetAutoCastOverlay(overlay) or 0
    writes = writes + HidePetAutoCastCircleVisual(visual)
    visual.petAutoCastAllowed = false
    visual.petAutoCastEnabled = false
    visual.petAutoCastMode = nil
    visual.pendingPetAutoCastLayout = nil
    return writes
end

local function GetPetCheckedInnerColor(colors)
    return PET_CHECKED_INNER_COLOR
end

local function GetPetCheckedInnerThickness()
    local thickness = PET_CHECKED_INNER_THICKNESS
    if thickness < 1 then thickness = 1 end
    if thickness > 4 then thickness = 4 end
    return thickness
end

local function GetPetCheckedGlowThickness()
    local thickness = PET_CHECKED_GLOW_THICKNESS
    if thickness < 1 then thickness = 1 end
    if thickness > 4 then thickness = 4 end
    return thickness
end

local function GetPetCheckedRingTexture(style, thickness)
    local family = style and style.borderFamily
    local familyTextures = family and SHAPE_BORDER_TEXTURES[family]
    return familyTextures and familyTextures[thickness or GetPetCheckedInnerThickness()] or nil
end

function Visuals:GetButtonStateInnerTexture(style)
    return (style and style.stateTexture) or BUTTON_STATE_INNER_TEXTURES.square
end

function Visuals:ApplyAssistedCombatVisual(button, visual, shown)
    if not (button and visual and visual.assistedCombatBorder) then return 0 end
    shown = shown == true and visual.isAction == true
    visual.assistedCombat = shown
    local writes = 0
    if shown then
        local style = SHAPE_STYLES[visual.runtimeSkin or "square"] or SHAPE_STYLES.square
        writes = writes + SetTexturePath(visual.assistedCombatBorder, self:GetButtonStateInnerTexture(style))
        if visual.assistedCombatBorderColorApplied ~= true then
            writes = writes + SetVertexColor(
                visual.assistedCombatBorder,
                BUTTON_STATE_COLORS.assistedCombat,
                BUTTON_STATE_COLORS.assistedCombat
            )
            visual.assistedCombatBorderColorApplied = true
        end
    end
    writes = writes + RegionShown(visual.assistedCombatBorder, shown)
    return writes
end

function Visuals:ApplyPressedVisual(visual, colors)
    local texture = visual and visual.pressedOverlay
    if not texture then return 0 end

    local effect = visual.pressedEffect == "innerGlow" and "innerGlow" or "darken"
    local writes = 0
    if effect == "innerGlow" then
        local style = SHAPE_STYLES[visual.runtimeSkin or "square"] or SHAPE_STYLES.square
        local texturePath = self:GetButtonStateInnerTexture(style)
        if visual.pressedVisualMode ~= effect or visual.pressedTexturePath ~= texturePath then
            writes = writes + SetTexturePath(texture, texturePath)
            writes = writes + SetVertexColor(texture, BUTTON_STATE_COLORS.pressedInnerGlow, BUTTON_STATE_COLORS.pressedInnerGlow)
            if texture.SetBlendMode then texture:SetBlendMode("ADD") end
            texture.yabNativeVisualAlpha = nil
            writes = writes + RegionAlpha(texture, 0.95)
            visual.pressedVisualMode = effect
            visual.pressedTexturePath = texturePath
            visual.pressedColor = nil
        end
    else
        local pressedColor = colors and colors.pressed or FALLBACK_PRESSED_COLOR
        if visual.pressedVisualMode ~= effect or visual.pressedColor ~= pressedColor then
            if texture.SetBlendMode then texture:SetBlendMode("BLEND") end
            writes = writes + SetColorTexture(texture, pressedColor, FALLBACK_PRESSED_COLOR)
            -- RGBA material writes may replace the alpha cached before repaint.
            texture.yabNativeVisualAlpha = nil
            writes = writes + RegionAlpha(texture, 0.28)
            visual.pressedVisualMode = effect
            visual.pressedTexturePath = nil
            visual.pressedColor = pressedColor
        end
    end
    return writes
end

function Visuals:LayoutPetCheckedStateTexture(button, visual, style)
    local texture = visual and visual.petCheckedState
    if not (button and visual and texture) then return 0 end
    local texturePath = self:GetButtonStateInnerTexture(style)
    if not texturePath then return RegionShown(texture, false) end
    local writes = 0
    if not InCombat() then
        ApplyVisualRect(button, visual, texture, 0)
        visual.pendingCheckedRingLayout = nil
    else
        visual.pendingCheckedRingLayout = true
    end
    writes = writes + SetTexturePath(texture, texturePath)
    writes = writes + SetVertexColor(texture, BUTTON_STATE_COLORS.petChecked, BUTTON_STATE_COLORS.petChecked)
    if texture.SetBlendMode then texture:SetBlendMode("ADD") end
    return writes
end

LayoutCheckedRing = function(button, visual, style)
    local ring = visual and visual.checkedRing
    if not (button and visual and ring) then return 0 end
    style = style or SHAPE_STYLES[visual.runtimeSkin or "square"] or SHAPE_STYLES.square
    if visual.nativeChecked then
        if InCombat() then
            visual.pendingCheckedRingLayout = true
            return 0
        end
        -- The CheckButton owns visibility; only its artwork is configured here.
        ApplyVisualRect(button, visual, ring, 0)
        SetTexturePath(ring, Visuals:GetButtonStateInnerTexture(style))
        ring:SetTexCoord(0, 1, 0, 1)
        local color = visual.isAction and BUTTON_STATE_COLORS.actionChecked or BUTTON_STATE_COLORS.petChecked
        SetVertexColor(ring, color, color)
        ring:SetBlendMode("ADD")
        ring:SetDrawLayer("OVERLAY", 5)
        RegionAlpha(ring, IsNativeVisualMode() and 0 or 1)
        RegionShown(ring, button:GetChecked() == true)
        visual.pendingCheckedRingLayout = nil
        return 1
    end
    if IsPetCheckedVisual(button, visual) then
        return RegionShown(ring, false) + RegionShown(visual.checkedGlowRing, false)
    end
    if style.circular ~= true then
        return RegionShown(ring, false)
    end
    if InCombat() then
        visual.pendingCheckedRingLayout = true
        return 0
    end
    ApplyVisualRect(button, visual, ring, 0)
    SetTexturePath(ring, CIRCLE_PROC_GLOW_SOFT_TEXTURE)
    visual.pendingCheckedRingLayout = nil
    return 1
end

HideNativeButtonStateArt = function(button, visual)
    if not button then return 0 end
    local writes = 0
    local fields = {
        "Flash",
        "CheckedTexture",
        "HighlightTexture",
        "SpellHighlightTexture",
        "QuickKeybindHighlightTexture",
        "CooldownFlash",
    }
    for _, field in ipairs(fields) do
        local region = button[field]
        if not (visual and visual.nativeChecked and region == visual.checkedRing) then
            writes = writes + RegionShown(region, false)
            writes = writes + RegionAlpha(region, 0)
            if region and region.StopAnimating then pcall(region.StopAnimating, region) end
        end
    end
    local getters = { "GetCheckedTexture", "GetHighlightTexture" }
    for _, getter in ipairs(getters) do
        if button[getter] then
            local ok, region = pcall(button[getter], button)
            if ok and region and not (visual and visual.nativeChecked and region == visual.checkedRing) then
                writes = writes + RegionShown(region, false)
                writes = writes + RegionAlpha(region, 0)
                if region.StopAnimating then pcall(region.StopAnimating, region) end
            end
        end
    end
    return writes
end

local function SetRegionAlphaNoCache(region, alpha)
    if not (region and region.SetAlpha) then return 0 end
    local ok = pcall(region.SetAlpha, region, alpha == nil and 1 or alpha)
    return ok and 1 or 0
end

local function HideSpellFlyoutBackground(flyout)
    local bg = flyout and flyout.Background
    if not bg then return 0 end
    local writes = SetRegionAlphaNoCache(bg, 0)
    writes = writes + SetRegionAlphaNoCache(bg.Start, 0)
    writes = writes + SetRegionAlphaNoCache(bg.End, 0)
    writes = writes + SetRegionAlphaNoCache(bg.HorizontalMiddle, 0)
    writes = writes + SetRegionAlphaNoCache(bg.VerticalMiddle, 0)
    return writes
end

local function SetBorderColor(visual, color)
    if not visual or not visual.border then return 0 end
    color = type(color) == "table" and color or DEFAULT_BORDER_COLOR
    local r, g, b, a = color[1] or 0, color[2] or 0, color[3] or 0, color[4] == nil and 1 or color[4]
    local lineAlpha = a * (visual.lineBorderAlphaScale or 1)
    local writes = 0
    local border = visual.border
    if border.top then
        border.top:SetColorTexture(r, g, b, lineAlpha)
        writes = writes + 1
    end
    if border.bottom then
        border.bottom:SetColorTexture(r, g, b, lineAlpha)
        writes = writes + 1
    end
    if border.left then
        border.left:SetColorTexture(r, g, b, lineAlpha)
        writes = writes + 1
    end
    if border.right then
        border.right:SetColorTexture(r, g, b, lineAlpha)
        writes = writes + 1
    end
    if visual.shapeBorder then
        writes = writes + SetVertexColor(visual.shapeBorder, color)
    end
    return writes
end

local function SetBorderColorCached(visual, color)
    color = type(color) == "table" and color or DEFAULT_BORDER_COLOR
    local r, g, b, a = color[1] or 0, color[2] or 0, color[3] or 0, color[4] == nil and 1 or color[4]
    local lineAlphaScale = visual.lineBorderAlphaScale or 1
    if visual.borderColorR == r and visual.borderColorG == g and visual.borderColorB == b and visual.borderColorA == a and visual.borderColorLineAlphaScale == lineAlphaScale then
        return 0
    end
    visual.borderColorR = r
    visual.borderColorG = g
    visual.borderColorB = b
    visual.borderColorA = a
    visual.borderColorLineAlphaScale = lineAlphaScale
    return SetBorderColor(visual, color)
end

local function InvalidateBorderColor(visual)
    if not visual then return end
    visual.borderColorR = nil
    visual.borderColorG = nil
    visual.borderColorB = nil
    visual.borderColorA = nil
    visual.borderColorLineAlphaScale = nil
end

local function HideExtraVisualRegion(region)
    if not region then return 0 end
    local writes = 0
    if region.Hide then
        local shown = region.IsShown and region:IsShown() or false
        if shown then
            region:Hide()
            writes = writes + 1
        end
    end
    if region.SetAlpha and region.yabNativeVisualAlpha ~= 0 then
        region:SetAlpha(0)
        region.yabNativeVisualAlpha = 0
        writes = writes + 1
    end
    return writes
end

local function ShowExtraVisualRegion(region, alpha)
    if not region then return 0 end
    local writes = 0
    alpha = alpha == nil and 1 or alpha
    if region.Show then
        local shown = region.IsShown and region:IsShown() or false
        if not shown then
            region:Show()
            writes = writes + 1
        end
    end
    if region.SetAlpha and region.yabNativeVisualAlpha ~= alpha then
        region:SetAlpha(alpha)
        region.yabNativeVisualAlpha = alpha
        writes = writes + 1
    end
    return writes
end

local function SetBorderShown(visual, shown)
    if not visual or not visual.border then return 0 end
    local writes = 0
    local lineShown = shown == true and visual.lineBorderActive == true
    for _, line in pairs(visual.border) do
        if lineShown then
            writes = writes + ShowExtraVisualRegion(line, 1)
        else
            writes = writes + HideExtraVisualRegion(line)
        end
    end
    if visual.shapeBorder then
        if shown == true and visual.shapeBorderActive == true then
            writes = writes + ShowExtraVisualRegion(visual.shapeBorder, 1)
        else
            writes = writes + HideExtraVisualRegion(visual.shapeBorder)
        end
    end
    return writes
end

local function SetMaskTexture(mask, path)
    if not (mask and mask.SetTexture and path) then return 0 end
    if mask.yabMaskPath == path then return 0 end
    mask:SetTexture(path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask.yabMaskPath = path
    return 1
end

AttachMaskTexture = function(texture, mask)
    if not (texture and mask and texture.AddMaskTexture) then return 0 end
    if texture.yabShapeMask == mask then return 0 end
    if texture.yabShapeMask and texture.RemoveMaskTexture then
        texture:RemoveMaskTexture(texture.yabShapeMask)
    end
    texture:AddMaskTexture(mask)
    texture.yabShapeMask = mask
    return 1
end

local function DetachMaskTexture(texture)
    if not (texture and texture.yabShapeMask and texture.RemoveMaskTexture) then return 0 end
    texture:RemoveMaskTexture(texture.yabShapeMask)
    texture.yabShapeMask = nil
    return 1
end

local function ApplyMaskToVisual(button, visual, maskPath)
    if not (button and visual) then return 0 end
    if InCombat() then
        visual.pendingMaskPath = maskPath
        return 0
    end
    local writes = 0
    if maskPath then
        local mask = visual.shapeMask
        if mask then
            ApplyVisualRect(button, visual, mask)
            writes = writes + SetMaskTexture(mask, maskPath)
            writes = writes + AttachMaskTexture(visual.icon, mask)
            writes = writes + AttachMaskTexture(visual.bg, mask)
            writes = writes + AttachMaskTexture(visual.bgSlotArt, mask)
            writes = writes + AttachMaskTexture(visual.hover, mask)
            writes = writes + AttachMaskTexture(visual.pressedOverlay, mask)
            writes = writes + AttachMaskTexture(visual.checkedOverlay, mask)
            writes = writes + AttachMaskTexture(visual.procGlowTexture, mask)
        end
    else
        writes = writes + DetachMaskTexture(visual.icon)
        writes = writes + DetachMaskTexture(visual.bg)
        writes = writes + DetachMaskTexture(visual.bgSlotArt)
        writes = writes + DetachMaskTexture(visual.hover)
        writes = writes + DetachMaskTexture(visual.pressedOverlay)
        writes = writes + DetachMaskTexture(visual.checkedOverlay)
        writes = writes + DetachMaskTexture(visual.procGlowTexture)
    end
    if visual.nativeChecked then
        -- Rounded checked artwork must stay inside the icon's content contour.
        local rounded = visual.runtimeSkin == "roundedSquare" or visual.runtimeSkin == "flatRounded"
            or visual.runtimeSkin == "wideRounded"
        local mask = maskPath and rounded and visual.shapeMask
        if mask then
            writes = writes + AttachMaskTexture(visual.checkedRing, mask)
        else
            writes = writes + DetachMaskTexture(visual.checkedRing)
        end
    end
    visual.pendingMaskPath = nil
    visual.maskPath = maskPath
    return writes
end

Visuals.extraActionNativeArtFields = Visuals.extraActionNativeArtFields or {
    "style",
    "Style",
    "IconMask",
    "Border",
    "BorderShadow",
    "NormalTexture",
    "PushedTexture",
    "HighlightTexture",
    "CheckedTexture",
    "SlotArt",
    "SlotBackground",
    "Flash",
    "NewActionTexture",
    "IconBorder",
    "IconOverlay",
    "SpellHighlightTexture",
    "QuickKeybindHighlightTexture",
    "CooldownFlash",
}

Visuals.extraActionNativeArtGetters = Visuals.extraActionNativeArtGetters or {
    "GetNormalTexture",
    "GetPushedTexture",
    "GetHighlightTexture",
    "GetCheckedTexture",
}

Visuals.zoneAbilityFrames = Visuals.zoneAbilityFrames or setmetatable({}, { __mode = "k" })
Visuals.zoneAbilityFrameArtFields = Visuals.zoneAbilityFrameArtFields or {
    "Style",
}
Visuals.zoneAbilityButtonArtFields = Visuals.zoneAbilityButtonArtFields or {
    "NormalTexture",
    "PushedTexture",
    "HighlightTexture",
    "CheckedTexture",
    "Flash",
    "SpellHighlightTexture",
    "QuickKeybindHighlightTexture",
    "CooldownFlash",
}
Visuals.zoneAbilityButtonArtGetters = Visuals.zoneAbilityButtonArtGetters or {
    "GetNormalTexture",
    "GetPushedTexture",
    "GetHighlightTexture",
    "GetCheckedTexture",
}

Visuals.vehicleExitNativeArtFields = Visuals.vehicleExitNativeArtFields or {
    "NormalTexture",
    "PushedTexture",
    "HighlightTexture",
    "CheckedTexture",
    "DisabledTexture",
}

Visuals.vehicleExitNativeArtGetters = Visuals.vehicleExitNativeArtGetters or {
    "GetNormalTexture",
    "GetPushedTexture",
    "GetHighlightTexture",
    "GetCheckedTexture",
    "GetDisabledTexture",
}

Visuals.vehicleExitStateHooked = Visuals.vehicleExitStateHooked or setmetatable({}, { __mode = "k" })
Visuals.vehicleExitNativeStates = Visuals.vehicleExitNativeStates or setmetatable({}, { __mode = "k" })

function Visuals:AddUniqueExternalRegion(regions, region)
    if not region then return end
    for index = 1, #regions do
        if regions[index] == region then return end
    end
    regions[#regions + 1] = region
end

function Visuals:GetExternalButtonIcon(button)
    if not button then return nil end
    if button.icon then return button.icon end
    if button.Icon then return button.Icon end
    local name = button.GetName and button:GetName()
    return name and _G[name .. "Icon"] or nil
end

function Visuals:CollectExtraActionNativeRegions(button, visual, includeLayoutRegions)
    local regions = {}
    if not button then return regions end
    for _, field in ipairs(self.extraActionNativeArtFields) do
        self:AddUniqueExternalRegion(regions, button[field])
    end
    for _, getter in ipairs(self.extraActionNativeArtGetters) do
        local method = button[getter]
        if type(method) == "function" then
            local ok, region = pcall(method, button)
            if ok then self:AddUniqueExternalRegion(regions, region) end
        end
    end
    if includeLayoutRegions then
        self:AddUniqueExternalRegion(regions, visual and visual.icon or self:GetExternalButtonIcon(button))
        self:AddUniqueExternalRegion(regions, visual and visual.cooldown or button.cooldown or button.Cooldown)
        self:AddUniqueExternalRegion(regions, visual and visual.chargeCooldown or button.chargeCooldown)
        self:AddUniqueExternalRegion(regions, button.Cooldown)
    end
    return regions
end

function Visuals:IsExternalStateValueSafe(value)
    return not (Security and Security.IsSecretValue and Security.IsSecretValue(value) == true)
end

function Visuals:CaptureExternalSingleValue(state, region, getterName, stateKey)
    local getter = region and region[getterName]
    if type(getter) ~= "function" then return end
    local ok, value = pcall(getter, region)
    if not ok or not self:IsExternalStateValueSafe(value) then return end
    if value == nil then return end
    state[stateKey] = value
    state[stateKey .. "Captured"] = true
end

function Visuals:CaptureExternalRegionState(region)
    if not region or Visuals.externalRegionState[region] then return end
    local state = {}
    if region.GetAlpha then
        local ok, alpha = pcall(region.GetAlpha, region)
        if ok then state.alpha = alpha end
    end
    if region.IsShown then
        local ok, shown = pcall(region.IsShown, region)
        if ok then state.shown = shown == true end
    end
    if region.GetWidth and region.GetHeight then
        local okWidth, width = pcall(region.GetWidth, region)
        local okHeight, height = pcall(region.GetHeight, region)
        if okWidth and okHeight and width and height and width > 0 and height > 0 then
            state.width = width
            state.height = height
        end
    end
    if region.GetNumPoints and region.GetPoint then
        local okCount, count = pcall(region.GetNumPoints, region)
        if okCount and type(count) == "number" and count > 0 then
            local points = {}
            for index = 1, count do
                local okPoint, point, relativeTo, relativePoint, x, y = pcall(region.GetPoint, region, index)
                if okPoint and point then
                    points[#points + 1] = { point, relativeTo, relativePoint, x, y }
                end
            end
            if #points > 0 then state.points = points end
        end
    end
    if region.GetTexCoord then
        local ok, left, right, top, bottom, ulx, uly, llx, lly = pcall(region.GetTexCoord, region)
        if ok and left ~= nil then
            state.texCoord = { left, right, top, bottom, ulx, uly, llx, lly }
        end
    end
    if region.GetDrawLayer then
        local ok, layer, sublevel = pcall(region.GetDrawLayer, region)
        if ok and layer ~= nil then
            state.drawLayer = layer
            state.drawSublevel = sublevel
        end
    end
    if region.GetVertexColor then
        local ok, r, g, b, a = pcall(region.GetVertexColor, region)
        if ok
            and self:IsExternalStateValueSafe(r)
            and self:IsExternalStateValueSafe(g)
            and self:IsExternalStateValueSafe(b)
            and self:IsExternalStateValueSafe(a)
            and r ~= nil
        then
            state.vertexColor = { r, g, b, a == nil and 1 or a }
        end
    end
    self:CaptureExternalSingleValue(state, region, "GetFrameLevel", "frameLevel")
    self:CaptureExternalSingleValue(state, region, "GetDrawBling", "drawBling")
    self:CaptureExternalSingleValue(state, region, "GetDrawEdge", "drawEdge")
    self:CaptureExternalSingleValue(state, region, "GetDrawSwipe", "drawSwipe")
    self:CaptureExternalSingleValue(state, region, "GetEdgeScale", "edgeScale")
    self:CaptureExternalSingleValue(state, region, "GetHideCountdownNumbers", "hideCountdownNumbers")
    Visuals.externalRegionState[region] = state
end

function Visuals:RestoreExternalRegionState(region)
    local state = region and Visuals.externalRegionState[region]
    if not state then return 0 end
    local writes = 0
    if state.width and state.height and region.SetSize then
        local ok = pcall(region.SetSize, region, state.width, state.height)
        if ok then writes = writes + 1 end
    end
    if state.points and region.ClearAllPoints and region.SetPoint then
        local ok = pcall(region.ClearAllPoints, region)
        writes = ok and writes + 1 or writes
        for _, point in ipairs(state.points) do
            ok = pcall(region.SetPoint, region, point[1], point[2], point[3], point[4], point[5])
            writes = ok and writes + 1 or writes
        end
    end
    if state.texCoord and region.SetTexCoord then
        local texCoord = state.texCoord
        local ok
        if texCoord[5] ~= nil then
            ok = pcall(region.SetTexCoord, region, texCoord[1], texCoord[2], texCoord[3], texCoord[4], texCoord[5], texCoord[6], texCoord[7], texCoord[8])
        else
            ok = pcall(region.SetTexCoord, region, texCoord[1], texCoord[2], texCoord[3], texCoord[4])
        end
        writes = ok and writes + 1 or writes
    end
    if state.drawLayer and region.SetDrawLayer then
        local ok
        if state.drawSublevel ~= nil then
            ok = pcall(region.SetDrawLayer, region, state.drawLayer, state.drawSublevel)
        else
            ok = pcall(region.SetDrawLayer, region, state.drawLayer)
        end
        writes = ok and writes + 1 or writes
    end
    if state.vertexColor and region.SetVertexColor then
        local color = state.vertexColor
        local ok = pcall(region.SetVertexColor, region, color[1], color[2], color[3], color[4])
        writes = ok and writes + 1 or writes
    end
    if state.frameLevelCaptured and region.SetFrameLevel then
        local ok = pcall(region.SetFrameLevel, region, state.frameLevel)
        writes = ok and writes + 1 or writes
    end
    if state.drawBlingCaptured and region.SetDrawBling then
        local ok = pcall(region.SetDrawBling, region, state.drawBling)
        writes = ok and writes + 1 or writes
    end
    if state.drawEdgeCaptured and region.SetDrawEdge then
        local ok = pcall(region.SetDrawEdge, region, state.drawEdge)
        writes = ok and writes + 1 or writes
    end
    if state.drawSwipeCaptured and region.SetDrawSwipe then
        local ok = pcall(region.SetDrawSwipe, region, state.drawSwipe)
        writes = ok and writes + 1 or writes
    end
    if state.edgeScaleCaptured and region.SetEdgeScale then
        local ok = pcall(region.SetEdgeScale, region, state.edgeScale)
        writes = ok and writes + 1 or writes
    end
    if state.hideCountdownNumbersCaptured and region.SetHideCountdownNumbers then
        local ok = pcall(region.SetHideCountdownNumbers, region, state.hideCountdownNumbers)
        writes = ok and writes + 1 or writes
    end
    if state.alpha ~= nil and region.SetAlpha then
        local ok = pcall(region.SetAlpha, region, state.alpha)
        writes = ok and writes + 1 or writes
    end
    if state.shown ~= nil then
        local method = state.shown and region.Show or region.Hide
        if method then
            local ok = pcall(method, region)
            writes = ok and writes + 1 or writes
        end
    end
    COOLDOWN_CACHE[region] = nil
    Visuals.externalRegionState[region] = nil
    return writes
end

function Visuals:IsProtectedFrameLikeObject(region)
    if not (region and region.GetObjectType) then return false end
    local okType, objectType = pcall(region.GetObjectType, region)
    if not okType then return false end
    if objectType ~= "Frame" and objectType ~= "Button" and objectType ~= "CheckButton" and objectType ~= "Cooldown" then
        return false
    end
    if region.IsProtected then
        local okProtected, protected = pcall(region.IsProtected, region)
        return okProtected and protected == true
    end
    return true
end

function Visuals:SuppressExtraActionNativeArtRegion(region)
    if not region then return 0 end
    self:CaptureExternalRegionState(region)
    if self:IsProtectedFrameLikeObject(region) then return 0 end
    local writes = 0
    if region.Stop then pcall(region.Stop, region) end
    if region.StopAnimating then pcall(region.StopAnimating, region) end
    if region.SetAlpha then
        local ok = pcall(region.SetAlpha, region, 0)
        writes = ok and writes + 1 or writes
    end
    if region.Hide then
        local ok = pcall(region.Hide, region)
        writes = ok and writes + 1 or writes
    end
    return writes
end

function Visuals:CaptureExtraActionNativeArt(button, visual)
    local regions = self:CollectExtraActionNativeRegions(button, visual, true)
    for index = 1, #regions do
        self:CaptureExternalRegionState(regions[index])
    end
end

function Visuals:ApplyButtonShadow(button, visual, snapshot, canLayout, native)
    if not visual or not GUI2 or not GUI2.BindShapeShadow then return 0 end
    snapshot = snapshot or DEFAULT_RUNTIME_SNAPSHOT
    if not native and self.nativeShadowStates then
        local state = self.nativeShadowStates[button]
        if state then GUI2:HideShapeShadow(state.shadowHandle) end
    end
    if not visual.shadowHandle then
        if snapshot.shadow == false or canLayout == false then return 0 end
        visual.shadowHandle = GUI2:CreateShapeShadow(button)
        if not visual.shadowHandle then return 0 end
        visual.shadowStyle = {}
    end
    local style = visual.shadowStyle
    if native then visual.runtimeSnapshot = snapshot end
    style.enabled = snapshot.shadow ~= false and not IsNativeVisualMode()
    style.shape = native and "square" or visual.runtimeSkin or snapshot.skin or "square"
    style.color = snapshot.shadowColor or GUI2.ShapeShadowDefaults.color
    local contour = native and button or visual.shadowContour or visual.bg or visual.icon or button
    if canLayout == false and style.enabled then
        visual.shadowHandle.pending = true
        return 0
    end
    return GUI2:BindShapeShadow(visual.shadowHandle, style, contour, true)
end

function Visuals:ApplyNativeButtonShadow(button, snapshot)
    if not GUI2 or not GUI2.BindShapeShadow then return 0 end
    if snapshot.shadow == false and not self.nativeShadowStates then return 0 end
    self.nativeShadowStates = self.nativeShadowStates or setmetatable({}, { __mode = "k" })
    local state = self.nativeShadowStates[button]
    if not state then
        if snapshot.shadow == false or InCombat() then return 0 end
        state = {}
        self.nativeShadowStates[button] = state
    end
    return self:ApplyButtonShadow(button, state, snapshot, not InCombat(), true)
end

function Visuals:RefreshNativeButtonShadows()
    local writes = 0
    for button, state in pairs(self.nativeShadowStates or {}) do
        writes = writes + self:ApplyButtonShadow(button, state, state.runtimeSnapshot, not InCombat(), true)
    end
    return writes
end

function Visuals:HideEnhancedVisualExtras(button, visual)
    if not visual then return 0 end
    local writes = 0
    if GUI2 and GUI2.HideShapeShadow then writes = writes + GUI2:HideShapeShadow(visual.shadowHandle) end
    writes = writes + HideExtraVisualRegion(visual.bg)
    writes = writes + HideExtraVisualRegion(visual.bgSlotArt)
    writes = writes + HideExtraVisualRegion(visual.hover)
    writes = writes + HideExtraVisualRegion(visual.pressedOverlay)
    writes = writes + HideExtraVisualRegion(visual.checkedOverlay)
    writes = writes + HideExtraVisualRegion(visual.checkedRing)
    writes = writes + HideExtraVisualRegion(visual.shapeBorder)
    writes = writes + SetBorderShown(visual, false)
    writes = writes + HidePetCheckedInnerVisual(visual)
    writes = writes + HidePetAutoCastCircleVisual(visual)
    writes = writes + ApplyMaskToVisual(button, visual, nil)
    if visual.procGlowFrame then
        StopManagedProcGlow(visual.procGlowFrame)
    end
    return writes
end

function Visuals:SuppressExtraActionNativeArt(button, visual)
    self:CaptureExtraActionNativeArt(button, visual)
    local writes = 0
    for _, field in ipairs(self.extraActionNativeArtFields) do
        writes = writes + self:SuppressExtraActionNativeArtRegion(button and button[field])
    end
    for _, getter in ipairs(self.extraActionNativeArtGetters) do
        local method = button and button[getter]
        if type(method) == "function" then
            local ok, region = pcall(method, button)
            if ok then writes = writes + self:SuppressExtraActionNativeArtRegion(region) end
        end
    end
    local icon = visual and visual.icon or self:GetExternalButtonIcon(button)
    local iconMask = button and button.IconMask
    if icon and iconMask and icon.RemoveMaskTexture then
        local ok = pcall(icon.RemoveMaskTexture, icon, iconMask)
        writes = ok and writes + 1 or writes
    end
    if icon and icon.SetAlpha then
        local ok = pcall(icon.SetAlpha, icon, 1)
        writes = ok and writes + 1 or writes
    end
    if visual then
        visual.externalArtMode = "yui"
        visual.nativeVisualExtrasHidden = false
    end
    return writes
end

function Visuals:CollectZoneAbilityNativeRegions(frame, button, visual, includeLayoutRegions)
    local regions = {}
    if frame then
        for _, field in ipairs(self.zoneAbilityFrameArtFields) do
            self:AddUniqueExternalRegion(regions, frame[field])
        end
    end
    if button then
        for _, field in ipairs(self.zoneAbilityButtonArtFields) do
            self:AddUniqueExternalRegion(regions, button[field])
        end
        for _, getter in ipairs(self.zoneAbilityButtonArtGetters) do
            local method = button[getter]
            if type(method) == "function" then
                local ok, region = pcall(method, button)
                if ok then self:AddUniqueExternalRegion(regions, region) end
            end
        end
        if includeLayoutRegions == true then
            self:AddUniqueExternalRegion(regions, visual and visual.icon or self:GetExternalButtonIcon(button))
            self:AddUniqueExternalRegion(regions, visual and visual.cooldown or button.cooldown or button.Cooldown)
            self:AddUniqueExternalRegion(regions, visual and visual.chargeCooldown or button.chargeCooldown or button.ChargeCooldown)
            self:AddUniqueExternalRegion(regions, button.Cooldown)
            self:AddUniqueExternalRegion(regions, button.ChargeCooldown)
        end
    end
    return regions
end

function Visuals:CaptureZoneAbilityNativeArt(frame, button, visual)
    local regions = self:CollectZoneAbilityNativeRegions(frame, button, visual, true)
    for index = 1, #regions do
        self:CaptureExternalRegionState(regions[index])
    end
end

function Visuals:RestoreZoneAbilityFrameArt(frame)
    if not frame then return 0 end
    local writes = 0
    local regions = self:CollectZoneAbilityNativeRegions(frame, nil)
    for index = 1, #regions do
        writes = writes + self:RestoreExternalRegionState(regions[index])
    end
    if self.zoneAbilityFrames then
        self.zoneAbilityFrames[frame] = nil
    end
    return writes
end

function Visuals:RestoreZoneAbilityButton(button)
    local visual = button and self.buttons and self.buttons[button] or nil
    local writes = self:HideEnhancedVisualExtras(button, visual)
    local regions = self:CollectZoneAbilityNativeRegions(nil, button, visual, true)
    for index = 1, #regions do
        writes = writes + self:RestoreExternalRegionState(regions[index])
    end
    writes = writes + self:ResetExternalCooldownShape(visual)
    writes = writes + self:RestoreExternalTextState(button)
    if visual then
        visual.externalArtMode = nil
        visual.pressed = false
        visual.checked = false
        visual.nativeVisualExtrasHidden = true
    end
    return writes
end

function Visuals:RestoreZoneAbilityVisualMode(frame, buttons)
    local writes = self:RestoreZoneAbilityFrameArt(frame)
    for _, button in ipairs(buttons or {}) do
        writes = writes + self:RestoreZoneAbilityButton(button)
    end
    self.stats.writes = (self.stats.writes or 0) + writes
    return writes
end

function Visuals:SuppressZoneAbilityNativeArt(frame, button, visual)
    if frame and self.zoneAbilityFrames then
        self.zoneAbilityFrames[frame] = true
    end
    local writes = 0
    local regions = self:CollectZoneAbilityNativeRegions(frame, button)
    for index = 1, #regions do
        writes = writes + self:SuppressExtraActionNativeArtRegion(regions[index])
    end
    local icon = visual and visual.icon or self:GetExternalButtonIcon(button)
    if icon and icon.SetAlpha then
        local ok = pcall(icon.SetAlpha, icon, 1)
        writes = ok and writes + 1 or writes
    end
    if visual then
        visual.externalArtMode = "yui"
        visual.nativeVisualExtrasHidden = false
    end
    return writes
end

function Visuals:CollectVehicleExitNativeRegions(button)
    local regions = {}
    if not button then return regions end
    for _, field in ipairs(self.vehicleExitNativeArtFields) do
        self:AddUniqueExternalRegion(regions, button[field])
    end
    for _, getter in ipairs(self.vehicleExitNativeArtGetters) do
        local method = button[getter]
        if type(method) == "function" then
            local ok, region = pcall(method, button)
            if ok then self:AddUniqueExternalRegion(regions, region) end
        end
    end
    return regions
end

function Visuals:EnsureVehicleExitIcon(button, visual)
    if not (button and visual) then return nil end
    if visual.vehicleExitIcon then
        visual.icon = visual.vehicleExitIcon
        return visual.vehicleExitIcon
    end
    if InCombat() then return nil end
    local icon = CreateSkinTexture(button, "ARTWORK", nil, -1)
    SetTexturePath(icon, self.vehicleExitIconPath)
    if icon.SetTexCoord then icon:SetTexCoord(0, 1, 0, 1) end
    if icon.SetDrawLayer then icon:SetDrawLayer("ARTWORK", 0) end
    visual.vehicleExitIcon = icon
    visual.icon = icon
    return icon
end

function Visuals:SuppressVehicleExitNativeArt(button, visual)
    local writes = 0
    local regions = self:CollectVehicleExitNativeRegions(button)
    for index = 1, #regions do
        writes = writes + self:SuppressExtraActionNativeArtRegion(regions[index])
    end
    local icon = visual and visual.vehicleExitIcon
    if icon and icon.SetAlpha then
        local ok = pcall(icon.SetAlpha, icon, 1)
        writes = ok and writes + 1 or writes
    end
    if visual then
        visual.externalArtMode = "yui"
        visual.nativeVisualExtrasHidden = false
    end
    return writes
end

function Visuals:RestoreVehicleExitVisualMode(button)
    if GUI2 and GUI2.HideShapeShadow and self.nativeShadowStates then
        local state = self.nativeShadowStates[button]
        if state then GUI2:HideShapeShadow(state.shadowHandle) end
    end
    local visual = button and self.buttons and self.buttons[button] or nil
    local writes = self:HideEnhancedVisualExtras(button, visual)
    if visual and visual.vehicleExitIcon then
        writes = writes + HideExtraVisualRegion(visual.vehicleExitIcon)
    end
    local regions = self:CollectVehicleExitNativeRegions(button)
    for index = 1, #regions do
        writes = writes + self:RestoreExternalRegionState(regions[index])
    end
    writes = writes + self:RestoreExternalTextState(button)
    if visual then
        visual.externalArtMode = nil
        visual.pressed = false
        visual.checked = false
        visual.usable = true
        visual.nativeVisualExtrasHidden = true
    end
    self.stats.writes = (self.stats.writes or 0) + writes
    return writes
end

function Visuals:GetVehicleExitNativeState(button)
    if not button then return nil end
    local state = self.vehicleExitNativeStates and self.vehicleExitNativeStates[button]
    if not state then
        state = {
            enabled = true,
            locked = false,
        }
        self.vehicleExitNativeStates[button] = state
    end
    return state
end

function Visuals:ReadVehicleExitNativeState(button, state)
    state = state or self:GetVehicleExitNativeState(button)
    if not (button and state) then return state end
    if type(button.IsEnabled) == "function" then
        local ok, enabled = pcall(button.IsEnabled, button)
        if ok then state.enabled = enabled == true or enabled == 1 end
    end
    if type(button.IsHighlightLocked) == "function" then
        local ok, locked = pcall(button.IsHighlightLocked, button)
        if ok then state.locked = locked == true or locked == 1 end
    end
    return state
end

function Visuals:RefreshVehicleExitNativeState(button, visual, readNative)
    visual = visual or (button and self.buttons and self.buttons[button]) or nil
    local state = self:GetVehicleExitNativeState(button)
    if not (button and visual and state) then return 0 end
    if readNative ~= false then
        self:ReadVehicleExitNativeState(button, state)
    end
    if visual.externalArtMode ~= "yui" then return 0 end
    self:SuppressVehicleExitNativeArt(button, visual)
    visual.hasAction = true
    visual.usable = state.enabled ~= false
    visual.checked = state.locked == true
    if state.locked == true and visual.pressed ~= true then
        visual.pressed = true
    elseif state.locked ~= true and visual.pressed == true then
        visual.pressed = false
    end
    visual.lastColor = nil
    return RefreshSkinState(button, visual)
end

function Visuals:HookVehicleExitButtonState(button)
    if not (button and type(hooksecurefunc) == "function") or self.vehicleExitStateHooked[button] then return end
    self.vehicleExitStateHooked[button] = true
    if type(button.Enable) == "function" then
        pcall(hooksecurefunc, button, "Enable", function(frame)
            local state = Visuals:GetVehicleExitNativeState(frame)
            if state then state.enabled = true end
            local visual = Visuals.buttons[frame]
            if visual and visual.externalSpecialKind == "vehicleExit" then
                Visuals:RefreshVehicleExitNativeState(frame, visual, false)
            end
        end)
    end
    if type(button.Disable) == "function" then
        pcall(hooksecurefunc, button, "Disable", function(frame)
            local state = Visuals:GetVehicleExitNativeState(frame)
            if state then state.enabled = false end
            local visual = Visuals.buttons[frame]
            if visual and visual.externalSpecialKind == "vehicleExit" then
                Visuals:RefreshVehicleExitNativeState(frame, visual, false)
            end
        end)
    end
    if type(button.LockHighlight) == "function" then
        pcall(hooksecurefunc, button, "LockHighlight", function(frame)
            local state = Visuals:GetVehicleExitNativeState(frame)
            if state then state.locked = true end
            local visual = Visuals.buttons[frame]
            if visual and visual.externalSpecialKind == "vehicleExit" then
                Visuals:RefreshVehicleExitNativeState(frame, visual, false)
            end
        end)
    end
    if type(button.UnlockHighlight) == "function" then
        pcall(hooksecurefunc, button, "UnlockHighlight", function(frame)
            local state = Visuals:GetVehicleExitNativeState(frame)
            if state then state.locked = false end
            local visual = Visuals.buttons[frame]
            if visual and visual.externalSpecialKind == "vehicleExit" then
                Visuals:RefreshVehicleExitNativeState(frame, visual, false)
            end
        end)
    end
    if type(button.SetHighlightTexture) == "function" then
        pcall(hooksecurefunc, button, "SetHighlightTexture", function(frame)
            local visual = Visuals.buttons[frame]
            if visual and visual.externalSpecialKind == "vehicleExit" then
                Visuals:RefreshVehicleExitNativeState(frame, visual, true)
            end
        end)
    end
end

function Visuals:RestoreExternalSpecialButton(button)
    if GUI2 and GUI2.HideShapeShadow and self.nativeShadowStates then
        local state = self.nativeShadowStates[button]
        if state then GUI2:HideShapeShadow(state.shadowHandle) end
    end
    local visual = button and self.buttons and self.buttons[button] or nil
    local writes = self:HideEnhancedVisualExtras(button, visual)
    local regions = self:CollectExtraActionNativeRegions(button, visual, true)
    for index = 1, #regions do
        writes = writes + self:RestoreExternalRegionState(regions[index])
    end
    writes = writes + self:ResetExternalCooldownShape(visual)
    writes = writes + self:RestoreExternalTextState(button)
    local icon = visual and visual.icon or self:GetExternalButtonIcon(button)
    local iconMask = button and button.IconMask
    if icon and iconMask and icon.AddMaskTexture then
        local ok = pcall(icon.AddMaskTexture, icon, iconMask)
        writes = ok and writes + 1 or writes
    end
    if visual then
        visual.externalArtMode = "blizzard"
        visual.pressed = false
        visual.checked = false
        visual.nativeVisualExtrasHidden = true
    end
    self.stats.writes = (self.stats.writes or 0) + writes
    return writes
end

function Visuals:EnsureBlizzardBackgroundArtMask(button, visual)
    if not (button and visual and visual.bgSlotArt and button.CreateMaskTexture) then return nil end
    if visual.bgSlotArtMask then return visual.bgSlotArtMask end
    if InCombat() then
        visual.pendingBlizzardBackgroundArtLayout = true
        return nil
    end
    local ok, mask = pcall(button.CreateMaskTexture, button, nil, "BACKGROUND")
    if not (ok and mask) then return nil end
    if mask.SetAllPoints then mask:SetAllPoints(button) end
    visual.bgSlotArtMask = mask
    return mask
end

function Visuals:LayoutBlizzardBackgroundArt(button, visual, style)
    local art = visual and visual.bgSlotArt
    if not (button and visual and art) then return 0 end
    if InCombat() then
        visual.pendingBlizzardBackgroundArtLayout = true
        return 0
    end

    local width = tonumber(visual.visualWidth)
    local height = tonumber(visual.visualHeight)
    if not (width and height) then
        width, height = GetFrameSize(button, nil, nil)
    end
    local size = math.max(width or 1, height or 1) * 1.08
    if style and tonumber(style.aspect) and tonumber(style.aspect) > 1 then
        size = (width or size) * 1.08
    end

    if art.ClearAllPoints then art:ClearAllPoints() end
    if art.SetPoint then
        art:SetPoint("CENTER", button, "CENTER", 0, 0)
    end
    if art.SetSize then
        art:SetSize(size, size)
    end

    local writes = 1
    if style and style.aspect and not style.mask then
        local mask = self:EnsureBlizzardBackgroundArtMask(button, visual)
        if mask then
            ApplyVisualRect(button, visual, mask)
            writes = writes + SetMaskTexture(mask, SOLID_SWIPE_TEXTURE)
            writes = writes + AttachMaskTexture(art, mask)
        end
    end
    visual.pendingBlizzardBackgroundArtLayout = nil
    return writes
end

local function SetCooldownSwipeTexture(cooldown, texture, r, g, b, a, preserveColor)
    if not (cooldown and cooldown.SetSwipeTexture and texture) then return 0 end
    r = r or 0
    g = g or 0
    b = b or 0
    a = a or 1
    local cache = EnsureCooldownCache(cooldown)
    preserveColor = preserveColor == true
    if cache.swipeTexture == texture and cache.swipePreserveColor == preserveColor
        and (preserveColor or (cache.swipeR == r and cache.swipeG == g and cache.swipeB == b and cache.swipeA == a))
    then
        return 0
    end
    local ok
    if preserveColor then
        ok = pcall(cooldown.SetSwipeTexture, cooldown, texture)
    else
        ok = pcall(cooldown.SetSwipeTexture, cooldown, texture, r, g, b, a)
    end
    if not ok then return 0 end
    cache.swipeTexture = texture
    cache.swipePreserveColor = preserveColor
    cache.swipeR = r
    cache.swipeG = g
    cache.swipeB = b
    cache.swipeA = a
    return 1
end

local function SetCooldownCircularEdge(cooldown, circular)
    if not (cooldown and cooldown.SetUseCircularEdge) then return 0 end
    circular = circular == true
    local cache = EnsureCooldownCache(cooldown)
    if cache.circularEdge == circular then return 0 end
    cooldown:SetUseCircularEdge(circular)
    cache.circularEdge = circular
    return 1
end

local function SetCooldownDrawEdge(cooldown, drawEdge)
    if not (cooldown and cooldown.SetDrawEdge) then return 0 end
    drawEdge = drawEdge == true
    local cache = EnsureCooldownCache(cooldown)
    if cache.drawEdge == drawEdge then return 0 end
    cooldown:SetDrawEdge(drawEdge)
    cache.drawEdge = drawEdge
    return 1
end

local function ApplyCooldownShape(visual, style, swipeOverride)
    if InCombat() then
        visual.pendingCooldownStyle = style
        return 0
    end
    style = style or SHAPE_STYLES.square
    local circular = style.circular == true
    local swipe = swipeOverride or style.swipe or SOLID_SWIPE_TEXTURE
    local writes = 0
    local externalShapeManaged = visual.externalSpecialKind == "extraAction" or visual.externalSpecialKind == "zoneAbility"
    local nativeShapeManaged = visual.nativeSpecialKind == "stance"
    local mainSwipeAlpha = externalShapeManaged and 0.58 or MAIN_COOLDOWN_SWIPE_ALPHA
    local chargeSwipeAlpha = externalShapeManaged and 0.32 or CHARGE_COOLDOWN_SWIPE_ALPHA
    if (visual.nativeSpecial == true and nativeShapeManaged ~= true)
        or (visual.externalSpecial == true and (externalShapeManaged ~= true or visual.externalArtMode ~= "yui"))
    then
        visual.pendingCooldownStyle = nil
        return 0
    end
    writes = writes + SetCooldownCircularEdge(visual.cooldown, circular)
    writes = writes + SetCooldownCircularEdge(visual.chargeCooldown, circular)
    writes = writes + SetCooldownSwipeTexture(visual.cooldown, swipe, 0, 0, 0, mainSwipeAlpha)
    writes = writes + SetCooldownSwipeTexture(visual.chargeCooldown, swipe, 0, 0, 0, chargeSwipeAlpha)
    writes = writes + SetCooldownDrawEdge(visual.cooldown, false)
    writes = writes + SetCooldownDrawEdge(visual.chargeCooldown, style.chargeEdge == true)
    visual.pendingCooldownStyle = nil
    return writes
end

function Visuals:ResetExternalCooldownShape(visual)
    if not visual then return 0 end
    local writes = 0
    writes = writes + SetCooldownCircularEdge(visual.cooldown, false)
    writes = writes + SetCooldownCircularEdge(visual.chargeCooldown, false)
    writes = writes + SetCooldownSwipeTexture(visual.cooldown, SOLID_SWIPE_TEXTURE, 0, 0, 0, 0.8)
    writes = writes + SetCooldownSwipeTexture(visual.chargeCooldown, SOLID_SWIPE_TEXTURE, 0, 0, 0, 0.8)
    visual.pendingCooldownStyle = nil
    return writes
end

local function ApplyShapeBorderTexture(button, visual, family, thickness)
    if not visual or not visual.shapeBorder then return 0 end
    thickness = tonumber(thickness) or 0
    if not family or thickness <= 0 then
        visual.shapeBorderActive = false
        visual.shapeBorderFamily = nil
        return HideExtraVisualRegion(visual.shapeBorder)
    end
    local familyTextures = SHAPE_BORDER_TEXTURES[family]
    local texture = familyTextures and familyTextures[thickness]
    if not texture then
        visual.shapeBorderActive = false
        visual.shapeBorderFamily = nil
        return HideExtraVisualRegion(visual.shapeBorder)
    end
    visual.shapeBorderActive = true
    visual.shapeBorderFamily = family
    if button and visual.shapeBorder.ClearAllPoints then
        ApplyVisualRect(button, visual, visual.shapeBorder)
    end
    local writes = SetTexturePath(visual.shapeBorder, texture)
    writes = writes + ShowExtraVisualRegion(visual.shapeBorder, 1)
    return writes
end

local function ApplyBackground(visual)
    if not (visual and visual.bg) then return 0 end
    local mode = visual.background or "black"
    if mode == "transparent" then
        visual.bgMode = mode
        return HideExtraVisualRegion(visual.bg) + HideExtraVisualRegion(visual.bgSlotArt)
    end
    local writes = ShowExtraVisualRegion(visual.bg, 1)
    if mode == "blizzard" then
        writes = writes + Visuals:SetTextureAtlas(visual.bg, BLIZZARD_BACKGROUND_ATLAS)
        writes = writes + SetVertexColor(visual.bg, BLIZZARD_BG_COLOR, BLIZZARD_BG_COLOR)
        writes = writes + ShowExtraVisualRegion(visual.bgSlotArt, 1)
        writes = writes + Visuals:SetTextureAtlas(visual.bgSlotArt, "ui-hud-actionbar-iconframe-slot")
        writes = writes + SetVertexColor(visual.bgSlotArt, BLIZZARD_BG_COLOR, BLIZZARD_BG_COLOR)
    else
        writes = writes + HideExtraVisualRegion(visual.bgSlotArt)
        writes = writes + SetColorTexture(visual.bg, visual.backgroundColor, BLACK_BG_COLOR)
        writes = writes + SetVertexColor(visual.bg, DEFAULT_TEXT_COLOR, DEFAULT_TEXT_COLOR)
    end
    visual.bgMode = mode
    return writes
end

local function ApplyDiagnosticVisualMode(button, visual)
    if not (button and visual and visual.enhanced) then return 0 end
    local writes = 0
    local oldProcGlowFrame = visual.procGlowFrame
    local oldProcGlowShape = oldProcGlowFrame and oldProcGlowFrame.yabProcShape
    if IsNativeVisualMode() then
        writes = writes + HideExtraVisualRegion(visual.bg)
        writes = writes + HideExtraVisualRegion(visual.bgSlotArt)
        writes = writes + HideExtraVisualRegion(visual.hover)
        writes = writes + HideExtraVisualRegion(visual.pressedOverlay)
        writes = writes + HideExtraVisualRegion(visual.checkedOverlay)
        if visual.nativeChecked then
            writes = writes + RegionAlpha(visual.checkedRing, 0)
        else
            writes = writes + HideExtraVisualRegion(visual.checkedRing)
        end
        writes = writes + HidePetCheckedInnerVisual(visual)
        writes = writes + HidePetAutoCastCircleVisual(visual)
        writes = writes + SetBorderShown(visual, false)
        if visual.procGlowFrame then
            StopManagedProcGlow(visual.procGlowFrame)
        end
        visual.nativeVisualExtrasHidden = true
    else
        writes = writes + ShowExtraVisualRegion(visual.hover, 0.24)
        writes = writes + ShowExtraVisualRegion(visual.pressedOverlay, visual.pressedEffect == "innerGlow" and 0.95 or 0.28)
        writes = writes + ShowExtraVisualRegion(visual.checkedOverlay, 0.18)
        if visual.nativeChecked then
            writes = writes + RegionAlpha(visual.checkedRing, 1)
            writes = writes + RegionShown(visual.checkedRing, button:GetChecked() == true)
        end
        writes = writes + SetBorderShown(visual, visual.borderEnabled == true)
        writes = writes + ApplyBackground(visual)
        visual.nativeVisualExtrasHidden = false
        InvalidateBorderColor(visual)
        visual.bgColor = nil
        visual.hoverColor = nil
        visual.pressedColor = nil
        visual.checkedColor = nil
        visual.checkedColorMode = nil
        RefreshSkinState(button, visual)
        writes = writes + SyncManagedProcGlow(button, visual, oldProcGlowFrame, oldProcGlowShape)
    end
    writes = writes + Visuals:ApplyButtonShadow(button, visual, visual.runtimeSnapshot, not InCombat())
    if writes > 0 then
        Visuals.stats.visualExtraHidden = (Visuals.stats.visualExtraHidden or 0) + writes
    end
    return writes
end

local function UpdateBorderPixel(button, visual, thickness)
    if not (button and visual and visual.border) then return end
    thickness = tonumber(thickness) or tonumber(visual.borderThickness) or 1
    if thickness < 1 then
        thickness = 1
    elseif thickness > 4 then
        thickness = 4
    end
    local pixel = thickness
    if GUI2 and GUI2.GetPixelSize then
        pixel = GUI2:GetPixelSize(button, thickness, thickness) or thickness
    end
    local alphaScale = LINE_BORDER_ALPHA_SCALE[thickness] or 1
    if visual.lineBorderAlphaScale ~= alphaScale then
        visual.lineBorderAlphaScale = alphaScale
        InvalidateBorderColor(visual)
    end
    visual.borderThickness = thickness
    visual.borderSize = pixel
    local insetX = visual.visualInsetX or 0
    local insetY = visual.visualInsetY or 0
    if GUI2 and GUI2.LayoutPixelBorder then
        GUI2:LayoutPixelBorder(
            visual.border,
            button,
            thickness,
            insetX,
            insetY,
            pixel
        )
        return
    end
    local top, bottom, left, right = visual.border.top, visual.border.bottom, visual.border.left, visual.border.right
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", button, "TOPLEFT", insetX, -insetY)
    top:SetPoint("TOPRIGHT", button, "TOPRIGHT", -insetX, -insetY)
    top:SetHeight(pixel)
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", insetX, insetY)
    bottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -insetX, insetY)
    bottom:SetHeight(pixel)
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", button, "TOPLEFT", insetX, -insetY)
    left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", insetX, insetY)
    left:SetWidth(pixel)
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", button, "TOPRIGHT", -insetX, -insetY)
    right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -insetX, insetY)
    right:SetWidth(pixel)
end

local function SetPetCheckedLineSetShown(lines, shown)
    if not lines then return 0 end
    local writes = 0
    for _, line in pairs(lines) do
        if shown then
            writes = writes + ShowExtraVisualRegion(line, 1)
        else
            writes = writes + HideExtraVisualRegion(line)
        end
    end
    return writes
end

HidePetCheckedInnerVisual = function(visual)
    if not visual then return 0 end
    local writes = 0
    writes = writes + RegionShown(visual.checkedRing, false)
    writes = writes + RegionShown(visual.checkedGlowRing, false)
    writes = writes + RegionShown(visual.petCheckedState, false)
    writes = writes + SetPetCheckedLineSetShown(visual.petCheckedInnerLines, false)
    writes = writes + SetPetCheckedLineSetShown(visual.petCheckedGlowLines, false)
    return writes
end

local function SetPetCheckedLineSetColor(lines, color, fallback, alpha)
    if not lines then return 0 end
    local writes = 0
    for _, line in pairs(lines) do
        writes = writes + SetColorTextureWithAlpha(line, color, fallback, alpha)
    end
    return writes
end

local function LayoutPetCheckedLineSet(button, visual, lines, thickness, offset)
    if not (button and visual and lines) then return 0 end
    if InCombat() then
        visual.pendingCheckedRingLayout = true
        return 0
    end
    thickness = tonumber(thickness) or 1
    offset = tonumber(offset) or 0
    local pixel = thickness
    if GUI2 and GUI2.GetPixelSize then
        pixel = GUI2:GetPixelSize(button, thickness, thickness) or thickness
    end
    local insetX = (visual.visualInsetX or 0) + offset
    local insetY = (visual.visualInsetY or 0) + offset
    local top, bottom, left, right = lines.top, lines.bottom, lines.left, lines.right
    if top then
        top:ClearAllPoints()
        top:SetPoint("TOPLEFT", button, "TOPLEFT", insetX, -insetY)
        top:SetPoint("TOPRIGHT", button, "TOPRIGHT", -insetX, -insetY)
        top:SetHeight(pixel)
    end
    if bottom then
        bottom:ClearAllPoints()
        bottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", insetX, insetY)
        bottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -insetX, insetY)
        bottom:SetHeight(pixel)
    end
    if left then
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", button, "TOPLEFT", insetX, -insetY)
        left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", insetX, insetY)
        left:SetWidth(pixel)
    end
    if right then
        right:ClearAllPoints()
        right:SetPoint("TOPRIGHT", button, "TOPRIGHT", -insetX, -insetY)
        right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -insetX, insetY)
        right:SetWidth(pixel)
    end
    return 1
end

local function ApplyPetCheckedEdge(button, visual, colors)
    if not IsPetCheckedVisual(button, visual) then return 0 end
    EnsurePetCheckedInnerVisual(button, visual)
    local style = SHAPE_STYLES[visual.runtimeSkin or "square"] or SHAPE_STYLES.square
    local checked = visual.checked == true
    if checked ~= true then
        return HidePetCheckedInnerVisual(visual)
    end

    local writes = 0
    writes = writes + RegionShown(visual.checkedRing, false)
    writes = writes + RegionShown(visual.checkedGlowRing, false)
    writes = writes + SetPetCheckedLineSetShown(visual.petCheckedGlowLines, false)
    writes = writes + SetPetCheckedLineSetShown(visual.petCheckedInnerLines, false)
    writes = writes + Visuals:LayoutPetCheckedStateTexture(button, visual, style)
    writes = writes + RegionShown(visual.petCheckedState, true)
    return writes
end

local function ApplyNativeIconLayout(button, visual, padding, zoom, style)
    local icon = visual and visual.icon or button and (button.icon or button.Icon)
    if not (button and icon) then return end
    if icon.SetDrawLayer then
        icon:SetDrawLayer("BACKGROUND", 0)
    end
    ApplyVisualRect(button, visual, icon)
    local sharedSnapshot = visual and visual.sharedIconSnapshot
    if GUI2 and GUI2.ApplyIconChrome and sharedSnapshot then
        sharedSnapshot.zoom = zoom
        sharedSnapshot.aspect = style and style.aspect or 1
        local writes = GUI2:ApplyIconChrome(
            visual.sharedIconTarget,
            sharedSnapshot,
            visual.sharedIconState
        )
        Visuals.stats.sharedVisualWrites =
            (Visuals.stats.sharedVisualWrites or 0) + writes
    elseif style and style.aspect and style.aspect > 1 then
        ApplyFlatIconCrop(icon, zoom, style.aspect)
    else
        ApplyIconCrop(icon, zoom)
    end
end

local function SuppressActionArtRegion(region)
    if not region then return end
    if region.Stop then pcall(region.Stop, region) end
    if region.StopAnimating then pcall(region.StopAnimating, region) end
    if region.SetAlpha then region:SetAlpha(0) end
    if region.Hide then region:Hide() end
end

local function NormalizeActionCooldownVisualLayers(button, visual)
    if not (button and visual and visual.isAction) then return end
    SuppressActionArtRegion(button.IconMask)
    SuppressActionArtRegion(button.SlotArt)
    SuppressActionArtRegion(button.SlotBackground)
    if visual.icon and visual.icon.SetDrawLayer then
        visual.icon:SetDrawLayer("BACKGROUND", 0)
    end
    if visual.cooldown then
        LayoutCooldown(visual.cooldown, button, 0, 0, 0, 0, MAIN_COOLDOWN_SWIPE_ALPHA, true, MAIN_COOLDOWN_LEVEL_OFFSET, nil, visual)
    end
end

local function IsCooldownFrame(frame)
    return frame and (type(frame.SetCooldown) == "function" or type(frame.SetCooldownFromDurationObject) == "function")
end

local function CreateManagedCooldown(button, kind)
    if not button or InCombat() then return nil end
    local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, button, "CooldownFrameTemplate")
    if not (ok and cooldown) then return nil end
    cooldown.yabManagedCooldown = kind or true
    if cooldown.EnableMouse then cooldown:EnableMouse(false) end
    if cooldown.Hide then cooldown:Hide() end
    Visuals.stats.managedCooldownFrames = (Visuals.stats.managedCooldownFrames or 0) + 1
    return cooldown
end

local function EnsureCooldown(button, visual, field, managedKind)
    if not (button and visual) then return nil end
    local cooldown = visual[field]
    if not IsCooldownFrame(cooldown) then
        cooldown = button[field]
    end
    if not IsCooldownFrame(cooldown) and field == "cooldown" then
        cooldown = button.Cooldown
    end
    if not IsCooldownFrame(cooldown) then
        cooldown = CreateManagedCooldown(button, managedKind)
        if cooldown then
            button[field] = cooldown
            if field == "cooldown" and not button.Cooldown then
                button.Cooldown = cooldown
            end
        end
    end
    visual[field] = cooldown
    return cooldown
end

LayoutCooldown = function(cooldown, button, padding, r, g, b, a, drawSwipe, levelOffset, drawEdge, visual)
    if not (cooldown and button) then return end
    padding = tonumber(padding) or 2
    if cooldown.ClearAllPoints then cooldown:ClearAllPoints() end
    if visual then
        ApplyVisualRect(button, visual, cooldown)
    elseif padding <= 0 and cooldown.SetAllPoints then
        cooldown:SetAllPoints(button)
    elseif cooldown.SetPoint then
        cooldown:SetPoint("TOPLEFT", button, "TOPLEFT", padding, -padding)
        cooldown:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -padding, padding)
    elseif cooldown.SetAllPoints then
        cooldown:SetAllPoints(button)
    end
    if cooldown.SetFrameLevel and button.GetFrameLevel then
        cooldown:SetFrameLevel((button:GetFrameLevel() or 0) + (levelOffset or 4))
    end
    if cooldown.SetAlpha then cooldown:SetAlpha(1) end
    local nativeOwned = visual and (visual.externalSpecial == true or visual.nativeSpecial == true)
    if not nativeOwned then
        if cooldown.SetDrawEdge then
            local drawEdgeValue = drawEdge == true
            cooldown:SetDrawEdge(drawEdgeValue)
            EnsureCooldownCache(cooldown).drawEdge = drawEdgeValue
        end
        if cooldown.SetDrawBling then cooldown:SetDrawBling(false) end
        if cooldown.SetDrawSwipe then cooldown:SetDrawSwipe(drawSwipe ~= false) end
        if cooldown.SetSwipeColor then cooldown:SetSwipeColor(r or 0, g or 0, b or 0, a or 0.58) end
    end
end

local function StyleChargeCooldown(cooldown)
    if not cooldown then return end
    if cooldown.SetDrawEdge then
        cooldown:SetDrawEdge(true)
        EnsureCooldownCache(cooldown).drawEdge = true
    end
    if cooldown.SetDrawBling then cooldown:SetDrawBling(false) end
    if cooldown.SetDrawSwipe then cooldown:SetDrawSwipe(true) end
    if cooldown.SetSwipeColor then cooldown:SetSwipeColor(0, 0, 0, CHARGE_COOLDOWN_SWIPE_ALPHA) end
    if cooldown.SetEdgeColor then
        cooldown:SetEdgeColor(CHARGE_COOLDOWN_EDGE_R, CHARGE_COOLDOWN_EDGE_G, CHARGE_COOLDOWN_EDGE_B, CHARGE_COOLDOWN_EDGE_A)
    end
    if cooldown.SetEdgeScale then cooldown:SetEdgeScale(CHARGE_COOLDOWN_EDGE_SCALE) end
end

local function SetCooldown(cooldown, durationObject, rawStart, rawDuration, enable, rawModRate)
    if not cooldown then return 0 end
    local active = enable == true
    local cache = EnsureCooldownCache(cooldown)
    local startValue = type(rawStart) == "number" and rawStart or nil
    local durationValue = type(rawDuration) == "number" and rawDuration or nil
    local modRateValue = type(rawModRate) == "number" and rawModRate or nil
    if active and durationObject and cooldown.SetCooldownFromDurationObject then
        cooldown:SetCooldownFromDurationObject(durationObject)
        if cooldown.Show then
            cooldown:Show()
        end
        cache.active = true
        cache.durationObject = true
        cache.start = startValue
        cache.duration = durationValue
        cache.modRate = modRateValue
        return 1
    end
    if not active then
        if cache.active == false then return 0 end
        if cache.active == nil and cooldown.IsShown and not cooldown:IsShown() then
            cache.active = false
            cache.durationObject = nil
            cache.start = nil
            cache.duration = nil
            cache.modRate = nil
            return 0
        end
        if cooldown.Clear then
            cooldown:Clear()
        else
            cooldown:Hide()
        end
        cache.active = false
        cache.durationObject = nil
        cache.start = nil
        cache.duration = nil
        cache.modRate = nil
        return 1
    end
    if startValue ~= nil and durationValue ~= nil then
        if durationValue <= 0 then
            if cache.active == false then return 0 end
            if cache.active == nil and cooldown.IsShown and not cooldown:IsShown() then
                cache.active = false
                cache.durationObject = nil
                cache.start = nil
                cache.duration = nil
                cache.modRate = nil
                return 0
            end
            if cooldown.Clear then cooldown:Clear() else cooldown:Hide() end
            cache.active = false
            cache.durationObject = nil
            cache.start = nil
            cache.duration = nil
            cache.modRate = nil
            return 1
        end
        if cache.active == true and cache.durationObject == nil and cache.start == startValue and cache.duration == durationValue and cache.modRate == modRateValue then return 0 end
        if cooldown.SetCooldown then
            local setter = cooldown.SetCooldown
            if modRateValue ~= nil then
                setter(cooldown, startValue, durationValue, modRateValue)
            else
                setter(cooldown, startValue, durationValue)
            end
            cooldown:Show()
            cache.active = true
            cache.durationObject = nil
            cache.start = startValue
            cache.duration = durationValue
            cache.modRate = modRateValue
            return 1
        end
    end
    return 0
end

local function SetCooldownNumbersHidden(cooldown, hidden)
    if not (cooldown and cooldown.SetHideCountdownNumbers) then return 0 end
    hidden = hidden == true
    local cache = EnsureCooldownCache(cooldown)
    if cache.hideNumbers == hidden then return 0 end
    cooldown:SetHideCountdownNumbers(hidden)
    cache.hideNumbers = hidden
    return 1
end

local function ShouldHideCooldownNumbers(snapshot)
    return not (type(snapshot) == "table"
        and type(snapshot.cooldownTextSize) == "number"
        and snapshot.cooldownTextSize > 0)
end

local function SetMainCooldownNumbersHidden(cooldown, snapshot)
    return SetCooldownNumbersHidden(cooldown, ShouldHideCooldownNumbers(snapshot))
end

local function SetChargeCooldownNumbersHidden(cooldown, snapshot)
    return SetCooldownNumbersHidden(cooldown, ShouldHideCooldownNumbers(snapshot))
end

local function CreateFallbackText(button, point, justify)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local x = point:find("RIGHT", 1, true) and -2 or 2
    local y = point:find("TOP", 1, true) and -1 or 1
    text:SetPoint(point, button, point, x, y)
    text:SetJustifyH(justify or "RIGHT")
    Visuals:ApplySingleLineTextConstraints(text)
    return text
end

local function CreateNameText(button)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 1)
    text:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 1)
    text:SetJustifyH("CENTER")
    Visuals:ApplySingleLineTextConstraints(text)
    return text
end

local function EnsureFallbackVisual(button, visual)
    if visual.fallbackReady then return end
    local icon = button.icon or button.Icon
    if not icon then
        icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
        button.icon = icon
    end
    visual.icon = icon
    visual.hotkey = button.HotKey or CreateFallbackText(button, "TOPRIGHT", "RIGHT")
    visual.count = button.Count or CreateFallbackText(button, "BOTTOMRIGHT", "RIGHT")
    visual.name = button.Name or CreateNameText(button)
    visual.cooldown = EnsureCooldown(button, visual, "cooldown", "fallback")
    LayoutCooldown(visual.cooldown, button, 0, 0, 0, 0, MAIN_COOLDOWN_SWIPE_ALPHA, true, MAIN_COOLDOWN_LEVEL_OFFSET, nil, visual)
    visual.fallbackReady = true
end

local function EnsureVisual(button, options)
    if not button then return nil end
    local externalSpecialKind = options and options.externalSpecialKind or nil
    local visual = Visuals.buttons[button]
    if visual then
        if externalSpecialKind then
            if not visual.enhanced and not InCombat() then
                Visuals.buttons[button] = nil
            else
                visual.externalSpecial = true
                visual.externalSpecialKind = externalSpecialKind
                visual.nativeSpecialKind = visual.nativeSpecialKind or externalSpecialKind
                return visual
            end
        else
            return visual
        end
    end
    if InCombat() then return nil end

    local isAction = (options and options.previewAction == true) or IsActionButton(button)
    local isFlyoutPopup = false
    local meta = GetButtonMeta(button)
    local isQuestItem = meta and meta.kind == "questItems"
        and YAB.Client and YAB.Client.questItems == true
    local isNativeSpecial = meta
        and (meta.nativeSpecial == true or meta.ownedStanceTemplate == true) or false
    local isExternalSpecial = externalSpecialKind ~= nil
    local nativeChecked = (isAction or (meta and meta.ownedStanceTemplate == true))
        and button.GetCheckedTexture and button:GetCheckedTexture() or nil
    visual = {
        isAction = isAction,
        nativeSpecial = isNativeSpecial,
        externalSpecial = isExternalSpecial,
        externalSpecialKind = externalSpecialKind,
        nativeSpecialKind = isNativeSpecial and meta and meta.barId or externalSpecialKind,
        flyoutPopup = isFlyoutPopup,
        enhanced = isAction or isNativeSpecial or isExternalSpecial or isQuestItem,
        nativeChecked = nativeChecked ~= nil,
        icon = button.icon or button.Icon,
        cooldown = button.cooldown or button.Cooldown,
        chargeCooldown = button.chargeCooldown,
        autoCastOverlay = button.AutoCastOverlay,
        hotkey = button.HotKey,
        count = button.Count,
        name = button.Name,
    }
    Visuals.buttons[button] = visual
    -- Owned quest item hosts have no template regions, but use the full skin.
    if isQuestItem then EnsureFallbackVisual(button, visual) end
    if visual.enhanced then
        if visual.isAction then
            EnsureCooldown(button, visual, "cooldown", "action")
            if not visual.flyoutPopup then
                EnsureCooldown(button, visual, "chargeCooldown", "charge")
            end
        elseif not IsCooldownFrame(visual.cooldown) then
            visual.cooldown = CreateManagedCooldown(button, "special")
        end
        visual.bg = CreateSkinTexture(button, "BACKGROUND", nil, -7)
        visual.bgSlotArt = CreateSkinTexture(button, "BACKGROUND", nil, -6)
        visual.hover = CreateSkinTexture(button, "HIGHLIGHT", 0.24)
        if isQuestItem and visual.hover.SetBlendMode then visual.hover:SetBlendMode("ADD") end
        visual.pressedOverlay = CreateSkinTexture(button, "OVERLAY", 0.28)
        visual.checkedOverlay = CreateSkinTexture(button, "OVERLAY", 0.18)
        visual.checkedRing = nativeChecked or CreateSkinTexture(button, "OVERLAY", nil, 5)
        if visual.isAction then
            visual.assistedCombatBorder = CreateSkinTexture(button, "OVERLAY", nil, 5)
            if visual.assistedCombatBorder.SetBlendMode then
                visual.assistedCombatBorder:SetBlendMode("ADD")
            end
            visual.assistedCombatBorder:Hide()
        end
        if visual.nativeSpecialKind == "pet" then
            visual.petCheckedState = CreateSkinTexture(button, "OVERLAY", nil, 5)
            if visual.petCheckedState.SetBlendMode then
                visual.petCheckedState:SetBlendMode("ADD")
            end
            visual.petCheckedState:Hide()
        end
        visual.pressedOverlay:Hide()
        visual.checkedOverlay:Hide()
        visual.checkedRing:Hide()
        if button.CreateMaskTexture then
            local ok, mask = pcall(button.CreateMaskTexture, button, nil, "BACKGROUND")
            if ok and mask then
                mask:SetAllPoints(button)
                visual.shapeMask = mask
            end
        end
        visual.shapeBorder = CreateSkinTexture(button, "OVERLAY", nil, 6)
        visual.shapeBorder:Hide()
        visual.border = {
            top = CreateBorderLine(button),
            bottom = CreateBorderLine(button),
            left = CreateBorderLine(button),
            right = CreateBorderLine(button),
        }
        visual.lineBorderActive = true
        UpdateBorderPixel(button, visual)
        Visuals.stats.nativeEnhancedButtons = (Visuals.stats.nativeEnhancedButtons or 0) + 1
    else
        EnsureFallbackVisual(button, visual)
        Visuals.stats.fallbackButtons = (Visuals.stats.fallbackButtons or 0) + 1
    end
    return visual
end

local function ShouldDesaturate(state)
    if not (state and state.hasAction == true) then return false end
    if state.chargeEnable == true and type(state.maxCharges) == "number" and state.maxCharges > 1 and type(state.charges) == "number" and state.charges <= 0 then
        return true
    end
    if state.cooldownActive == true and state.cooldownOnGCD ~= true then
        return true
    end
    return false
end

local function SetIconDesaturation(icon, value)
    if not icon then return 0 end
    value = value or 0
    if ICON_DESATURATION_CACHE[icon] == value then return 0 end
    ICON_DESATURATION_CACHE[icon] = value
    if icon.SetDesaturation then
        icon:SetDesaturation(value)
    elseif icon.SetDesaturated then
        icon:SetDesaturated(value > 0)
    end
    return 1
end

function Visuals:SetIconDesaturationCache(icon, value)
    if not icon then return end
    ICON_DESATURATION_CACHE[icon] = value
end

function Visuals:PrepareExternalSpecialState(visual, preserveActionState)
    if not visual then return 0 end
    visual.hasAction = true
    if preserveActionState ~= true or visual.usable == nil then
        visual.usable = true
    end
    if preserveActionState ~= true or visual.noMana == nil then
        visual.noMana = false
    end
    if preserveActionState ~= true or visual.outOfRange == nil then
        visual.outOfRange = false
    end
    visual.lastColor = nil
    if preserveActionState == true then return 0 end
    return SetIconDesaturation(visual.icon, 0)
end

function Visuals:GetIconCooldownDesaturation(visual, state)
    if ShouldDesaturate(state) then
        return visual.cooldownDesaturation or ((visual.skin and visual.skin.cooldownDesaturation) or 1)
    end
    return 0
end

local function ApplyRuntimeSnapshot(button, visual, snapshot, options)
    if not (button and visual) then return 0 end
    snapshot = snapshot or DEFAULT_RUNTIME_SNAPSHOT
    options = options or {}
    local oldProcGlowFrame = visual.procGlowFrame
    local oldProcGlowShape = oldProcGlowFrame and oldProcGlowFrame.yabProcShape
    visual.runtimeSnapshot = snapshot
    local runtimeSkin = snapshot.skin or "square"
    if runtimeSkin == "blizzard" then runtimeSkin = "square" end
    visual.runtimeSkin = runtimeSkin
    visual.rangeMode = snapshot.rangeMode == "none" and "none" or "red"
    visual.background = snapshot.background or "black"
    visual.backgroundColor = snapshot.backgroundColor or BLACK_BG_COLOR
    local pressedEffect = snapshot.pressedEffect == "innerGlow" and "innerGlow" or "darken"
    if visual.pressedEffect ~= pressedEffect then
        visual.pressedEffect = pressedEffect
        visual.pressedVisualMode = nil
        visual.pressedTexturePath = nil
        visual.pressedColor = nil
    end
    visual.borderColorOverride = snapshot.borderColor or DEFAULT_BORDER_COLOR
    visual.cooldownDesaturation = snapshot.cooldownFade == false and 0 or ((visual.skin and visual.skin.cooldownDesaturation) or 1)

    local style = SHAPE_STYLES[visual.runtimeSkin] or SHAPE_STYLES.square
    local zoom = tonumber(options.zoom) or tonumber(snapshot.iconZoom) or tonumber(visual.skin and visual.skin.iconZoom) or 0.08
    local padding = tonumber(options.padding) or style.padding or tonumber(visual.skin and visual.skin.padding) or 2
    local thickness = Visuals:GetCommonBorderThickness(
        snapshot.border or "thin"
    ) or 1
    visual.configuredBorderThickness = thickness
    visual.borderEnabled = thickness > 0
    if GUI2 and GUI2.CompileIconStyle then
        local input = visual.sharedIconInput
        if not input then
            input = {}
            visual.sharedIconInput = input
            visual.sharedIconTarget = { icon = visual.icon }
            visual.sharedIconState = {}
        end
        input.iconShape = visual.runtimeSkin
        input.iconBorder = snapshot.border
        input.iconZoom = zoom
        input.iconBorderColor = snapshot.borderColor
        input.iconBackgroundColor = snapshot.backgroundColor
        input.cooldownSwipeColor = snapshot.cooldownSwipeColor
        visual.sharedIconSnapshot = GUI2:CompileIconStyle(
            input,
            visual.sharedIconSnapshot
        )
    end
    local canLayout = not InCombat()

    local writes = 0
    writes = writes + UpdateVisualGeometry(button, visual, style, padding, options)
    if canLayout then
        ApplyVisualRect(button, visual, visual.bg)
        ApplyVisualRect(button, visual, visual.hover)
        ApplyVisualRect(button, visual, visual.pressedOverlay)
        ApplyVisualRect(button, visual, visual.checkedOverlay)
        ApplyNativeIconLayout(button, visual, padding, zoom, style)
        LayoutCooldown(visual.cooldown, button, 0, 0, 0, 0, MAIN_COOLDOWN_SWIPE_ALPHA, true, MAIN_COOLDOWN_LEVEL_OFFSET, nil, visual)
        LayoutCooldown(visual.chargeCooldown, button, 0, 0, 0, 0, CHARGE_COOLDOWN_SWIPE_ALPHA, true, CHARGE_COOLDOWN_LEVEL_OFFSET, true, visual)
        if visual.procGlowFrame then
            LayoutManagedProcGlow(button, visual)
        end
        if visual.nativeSpecial and (visual.autoCastOverlay or visual.petAutoCastCircle) then
            SetPetAutoCastVisual(button, visual, visual.petAutoCastAllowed == true, visual.petAutoCastEnabled == true)
        end
    end
    writes = writes + Visuals:ApplyButtonShadow(button, visual, snapshot, canLayout)
    local appearanceMask = visual.sharedIconSnapshot
        and visual.sharedIconSnapshot.mask
        or style.mask
    writes = writes + ApplyMaskToVisual(button, visual, appearanceMask)
    if canLayout then
        writes = writes + Visuals:LayoutBlizzardBackgroundArt(button, visual, style)
    end
    writes = writes + ApplyCooldownShape(
        visual,
        style,
        appearanceMask
    )
    local nextLineBorderActive = visual.enhanced == true and thickness > 0 and not style.borderFamily
    if visual.enhanced then
        if canLayout then
            visual.lineBorderActive = nextLineBorderActive
            visual.pendingLineBorderActive = nil
            UpdateBorderPixel(button, visual, thickness > 0 and thickness or 1)
            writes = writes + ApplyShapeBorderTexture(button, visual, style.borderFamily, thickness)
            if LayoutCheckedRing then
                writes = writes + LayoutCheckedRing(button, visual, style)
            end
        else
            visual.pendingLineBorderActive = nextLineBorderActive
            visual.pendingGeometry = true
        end
        writes = writes + SetBorderShown(visual, thickness > 0)
        writes = writes + ApplyBackground(visual)
    end
    ApplyTextFonts(button, visual, snapshot)
    writes = writes + SetMainCooldownNumbersHidden(visual.cooldown, snapshot)
    writes = writes + SetChargeCooldownNumbersHidden(
        visual.chargeCooldown,
        snapshot
    )
    if visual.cooldownDesaturation == 0 then
        writes = writes + SetIconDesaturation(visual.icon, 0)
    end
    visual.lastColor = nil
    InvalidateBorderColor(visual)
    writes = writes + RefreshSkinState(button, visual)
    if visual.nativeSpecial and HideNativeButtonStateArt then
        writes = writes + HideNativeButtonStateArt(button, visual)
    end
    writes = writes + SyncManagedProcGlow(button, visual, oldProcGlowFrame, oldProcGlowShape)
    writes = writes + Visuals:ApplyAssistedCombatVisual(button, visual, visual.assistedCombat == true)
    if visual.isAction == true then
        writes = writes + Visuals:ApplyProfessionQuality(button, visual.professionQualityAtlas, snapshot)
    end
    return writes
end

function RefreshSkinState(button, visual)
    if visual and visual.enhanced and IsNativeVisualMode() then
        if visual.nativeVisualExtrasHidden == true then
            return 0
        end
        return ApplyDiagnosticVisualMode(button, visual)
    end
    if visual and visual.externalSpecialKind == "extraAction" and visual.externalArtMode == "blizzard" then
        return Visuals:HideEnhancedVisualExtras(button, visual)
    end

    local skin = visual.skin or (YAB.Skins and YAB.Skins:GetDefinition("default")) or DEFAULT_RUNTIME_SNAPSHOT
    local icon = visual.icon or button.icon or button.Icon
    if not icon then
        return 0
    end

    local writes = Visuals:ApplyActionTintFast(button, visual.usable, visual.noMana, visual.outOfRange, true)
    if visual.enhanced then
        local colors = Visuals.theme and Visuals.theme.colors or DEFAULT_RUNTIME_SNAPSHOT
        local petCheckedVisual = IsPetCheckedVisual(button, visual)
        writes = writes + SetBorderColorCached(visual, visual.borderColorOverride or DEFAULT_BORDER_COLOR)
        local bgKey = visual.background or "black"
        if visual.bgColor ~= bgKey then
            visual.bgColor = bgKey
            writes = writes + ApplyBackground(visual)
        end
        if visual.hoverColor ~= colors.hover then
            visual.hoverColor = colors.hover
            writes = writes + SetColorTexture(visual.hover, colors.hover, FALLBACK_HOVER_COLOR)
            visual.hover.yabNativeVisualAlpha = nil
            writes = writes + RegionAlpha(visual.hover, 0.24)
        end
        writes = writes + Visuals:ApplyPressedVisual(visual, colors)
        local checkedColorMode = petCheckedVisual and "pet" or "default"
        if not visual.nativeChecked and (visual.checkedColor ~= colors.checked or visual.checkedColorMode ~= checkedColorMode) then
            visual.checkedColor = colors.checked
            visual.checkedColorMode = checkedColorMode
            if petCheckedVisual then
                writes = writes + SetColorTextureWithAlpha(visual.checkedOverlay, PET_CHECKED_FILL_COLOR, PET_CHECKED_FILL_COLOR, PET_CHECKED_FILL_ALPHA)
            else
                writes = writes + SetColorTexture(visual.checkedOverlay, colors.checked, FALLBACK_CHECKED_COLOR)
            end
        end
        writes = writes + RegionShown(visual.pressedOverlay, visual.pressed == true)
        writes = writes + RegionShown(visual.checkedOverlay, not visual.nativeChecked and visual.checked == true)
        if petCheckedVisual then
            writes = writes + ApplyPetCheckedEdge(button, visual, colors)
        elseif visual.checkedRing and not visual.nativeChecked then
            local checkedColor = colors.checked or FALLBACK_CHECKED_COLOR
            writes = writes + SetVertexColor(visual.checkedRing, checkedColor, FALLBACK_CHECKED_COLOR)
            writes = writes + RegionShown(visual.checkedRing, visual.checked == true and visual.runtimeSkin == "circle")
        end
    end
    local colors = Visuals.theme and Visuals.theme.colors or DEFAULT_RUNTIME_SNAPSHOT
    local snapshot = visual.runtimeSnapshot or (button and button.yabConfigSnapshot) or DEFAULT_RUNTIME_SNAPSHOT
    writes = writes + SetTextColor(visual.count, snapshot.countColor or colors.text or DEFAULT_TEXT_COLOR)
    writes = writes + SetTextColor(visual.name, snapshot.macroNameColor or colors.text or DEFAULT_TEXT_COLOR)
    Visuals.stats.skinWrites = (Visuals.stats.skinWrites or 0) + writes
    return writes
end

function Visuals:RefreshTheme(reason)
    if GUI2 and GUI2.CreateTokenSnapshot then
        self.theme = GUI2:CreateTokenSnapshot(TOKEN_SPEC, self.theme)
    end
    self.stats.themeRefreshes = (self.stats.themeRefreshes or 0) + 1
    for button, visual in pairs(self.buttons) do
        if visual.externalSpecial ~= true or self.externalTextSnapshots[button] ~= nil then
            ApplyTextFonts(button, visual, visual.runtimeSnapshot or (button and button.yabConfigSnapshot) or DEFAULT_RUNTIME_SNAPSHOT)
            InvalidateBorderColor(visual)
            visual.bgColor = nil
            visual.hoverColor = nil
            visual.pressedColor = nil
            visual.checkedColor = nil
            visual.checkedColorMode = nil
            RefreshSkinState(button, visual)
        end
    end
    for button, snapshot in pairs(self.externalTextSnapshots) do
        if not self.buttons[button] then
            local view = self:CaptureExternalTextState(button, nil)
            if view then ApplyTextFonts(button, view, snapshot) end
        end
    end
    return true
end

function Visuals:RefreshPixel(reason)
    self.stats.pixelRefreshes = (self.stats.pixelRefreshes or 0) + 1
    for button, visual in pairs(self.buttons) do
        if visual.enhanced and not IsNativeVisualMode()
            and (visual.externalSpecial ~= true or self.externalTextSnapshots[button] ~= nil)
        then
            if InCombat() then
                visual.pendingGeometry = true
            else
                local thickness = tonumber(visual.configuredBorderThickness) or tonumber(visual.borderThickness) or 1
                UpdateBorderPixel(button, visual, thickness > 0 and thickness or 1)
                ApplyShapeBorderTexture(button, visual, visual.shapeBorderFamily, thickness)
                if LayoutCheckedRing then
                    LayoutCheckedRing(button, visual, SHAPE_STYLES[visual.runtimeSkin or "square"] or SHAPE_STYLES.square)
                end
                RefreshSkinState(button, visual)
            end
        end
    end
    return true
end

function Visuals:SetManagedPressedState(button, pressed)
    local visual = button and Visuals.buttons[button]
    if not visual or (visual.externalSpecial == true and visual.externalArtMode ~= "yui") then return end
    visual.mousePressed = pressed == true
    pressed = visual.mousePressed or visual.keyboardPressed == true
    if pressed then
        if visual.pressed == true then return end
    elseif visual.pressed ~= true then
        return
    end
    visual.pressed = pressed
    RefreshSkinState(button, visual)
end

function Visuals:SetKeyboardPressedState(button, pressed)
    local visual = button and self.buttons[button]
    if not visual or (visual.externalSpecial == true and visual.externalArtMode ~= "yui") then return end
    visual.keyboardPressed = pressed == true
    self:SetManagedPressedState(button, visual.mousePressed == true)
end

function Visuals.ManagedButtonMouseDown(button, mouseButton)
    if mouseButton == "Keybind" then
        Visuals:SetKeyboardPressedState(button, true)
    else
        Visuals:SetManagedPressedState(button, true)
    end
end

function Visuals.ManagedButtonPressEnd(button, mouseButton)
    if mouseButton == "Keybind" then
        Visuals:SetKeyboardPressedState(button, false)
    else
        Visuals:SetManagedPressedState(button, false)
    end
end

function Visuals.ManagedButtonAllPressEnd(button)
    local visual = button and Visuals.buttons[button]
    if visual then visual.keyboardPressed = false end
    Visuals:SetManagedPressedState(button, false)
    if visual and visual.nativeChecked then
        YAB.BarManager:ClearButtonCheckedState(button)
    end
end

function Visuals.ManagedButtonShow(button)
    local visual = Visuals.buttons[button]
    if visual and visual.nativeChecked then
        YAB.BarManager:RefreshButtonCheckedState(button)
    end
end

function Visuals.ManagedButtonPostClick(button, mouseButton, down)
    -- Click-based keyboard input reports both edges here even without mouse-up.
    -- Change visuals only; the secure action and its release remain untouched.
    if mouseButton == "Keybind" then
        local visual = Visuals.buttons[button]
        -- Synthetic key clicks can also arrive through the mouse scripts.
        if visual then visual.mousePressed = false end
        Visuals:SetKeyboardPressedState(button, down == true)
    elseif down ~= true then
        Visuals:SetManagedPressedState(button, false)
    end
    local visual = Visuals.buttons[button]
    if visual and visual.nativeChecked then
        YAB.BarManager:RefreshButtonCheckedState(button)
    end
end

function Visuals:HookButton(button)
    if not button or self.hooked[button] then return end
    self.hooked[button] = true
    if button.HookScript then
        button:HookScript("OnMouseDown", Visuals.ManagedButtonMouseDown)
        button:HookScript("OnMouseUp", Visuals.ManagedButtonPressEnd)
        button:HookScript("PostClick", Visuals.ManagedButtonPostClick)
        button:HookScript("OnLeave", Visuals.ManagedButtonPressEnd)
        button:HookScript("OnDragStart", Visuals.ManagedButtonAllPressEnd)
        button:HookScript("OnReceiveDrag", Visuals.ManagedButtonAllPressEnd)
        button:HookScript("OnHide", Visuals.ManagedButtonAllPressEnd)
        button:HookScript("OnShow", Visuals.ManagedButtonShow)
    end
end

function Visuals:ApplyExtraActionVisualMode(button, snapshot, options)
    if not button then return false end
    options = options or {}
    snapshot = snapshot or options.snapshot or button.yabConfigSnapshot or DEFAULT_RUNTIME_SNAPSHOT

    if snapshot and snapshot.skin == "blizzard" then
        self:RestoreExternalSpecialButton(button)
        self:ApplyNativeButtonShadow(button, snapshot)
        self:ApplyExternalTextSnapshot(button, snapshot)
        self:HookButton(button)
        return true
    end

    options.externalSpecialKind = "extraAction"
    options.snapshot = snapshot

    local visual = EnsureVisual(button, options)
    if not visual then return false end
    local skin = YAB.Skins and YAB.Skins:GetDefinition("default") or nil
    visual.skin = skin or {}
    visual.lastColor = nil
    visual.externalSpecial = true
    visual.externalSpecialKind = "extraAction"
    visual.nativeSpecialKind = visual.nativeSpecialKind or "extraAction"
    visual.externalArtMode = "yui"
    visual.nativeVisualExtrasHidden = false
    self:PrepareExternalSpecialState(visual, true)

    if not self.theme then self:RefreshTheme("extra-action") end
    if GUI2 and GUI2.RegisterLightBackendOwner then
        GUI2:RegisterLightBackendOwner(self, self)
    end

    self:ApplyExternalTextSnapshot(button, snapshot)
    self:CaptureExtraActionNativeArt(button, visual)
    LayoutCooldown(visual.cooldown, button, 0, 0, 0, 0, MAIN_COOLDOWN_SWIPE_ALPHA, true, MAIN_COOLDOWN_LEVEL_OFFSET, nil, visual)
    SetMainCooldownNumbersHidden(visual.cooldown, snapshot)
    NormalizeActionCooldownVisualLayers(button, visual)
    LayoutCooldown(visual.chargeCooldown, button, 0, 0, 0, 0, CHARGE_COOLDOWN_SWIPE_ALPHA, true, CHARGE_COOLDOWN_LEVEL_OFFSET, true, visual)
    SetChargeCooldownNumbersHidden(visual.chargeCooldown, snapshot)
    PrepareText(visual.hotkey, "RIGHT")
    PrepareText(visual.count, "RIGHT")
    if visual.name then
        PrepareText(visual.name, "CENTER")
    end
    ApplyRuntimeSnapshot(button, visual, snapshot, options)
    self:SuppressExtraActionNativeArt(button, visual)
    if not IsNativeVisualMode() and not visual.flyoutPopup then
        EnsureManagedProcGlow(button, visual)
    end
    self:HookButton(button)
    if visual.enhanced then
        ApplyDiagnosticVisualMode(button, visual)
    else
        RefreshSkinState(button, visual)
    end
    return true
end

function Visuals:ApplyZoneAbilityVisualMode(frame, buttons, snapshot, options)
    if InCombat() then return false end
    buttons = buttons or {}
    options = options or {}
    snapshot = snapshot or options.snapshot or DEFAULT_RUNTIME_SNAPSHOT

    local ok = true
    local skin = YAB.Skins and YAB.Skins:GetDefinition("default") or nil
    for _, button in ipairs(buttons) do
        if button then
            local visualOptions = {
                size = options.size,
                width = options.width,
                height = options.height,
                zoom = snapshot.iconZoom,
                snapshot = snapshot,
                externalSpecialKind = "zoneAbility",
            }
            local visual = EnsureVisual(button, visualOptions)
            if visual then
                visual.skin = skin or {}
                visual.lastColor = nil
                visual.externalSpecial = true
                visual.externalSpecialKind = "zoneAbility"
                visual.nativeSpecialKind = visual.nativeSpecialKind or "zoneAbility"
                visual.externalArtMode = "yui"
                self:PrepareExternalSpecialState(visual, false)
                if not self.theme then self:RefreshTheme("zone-ability") end
                if GUI2 and GUI2.RegisterLightBackendOwner then
                    GUI2:RegisterLightBackendOwner(self, self)
                end
                self:CaptureZoneAbilityNativeArt(frame, button, visual)
                self:ApplyExternalTextSnapshot(button, snapshot)
                LayoutCooldown(visual.cooldown, button, 0, 0, 0, 0, MAIN_COOLDOWN_SWIPE_ALPHA, true, MAIN_COOLDOWN_LEVEL_OFFSET, nil, visual)
                SetMainCooldownNumbersHidden(visual.cooldown, snapshot)
                NormalizeActionCooldownVisualLayers(button, visual)
                LayoutCooldown(visual.chargeCooldown, button, 0, 0, 0, 0, CHARGE_COOLDOWN_SWIPE_ALPHA, true, CHARGE_COOLDOWN_LEVEL_OFFSET, true, visual)
                SetChargeCooldownNumbersHidden(visual.chargeCooldown, snapshot)
                PrepareText(visual.count, "RIGHT")
                ApplyRuntimeSnapshot(button, visual, snapshot, visualOptions)
                self:SuppressZoneAbilityNativeArt(frame, button, visual)
                self:HookButton(button)
                if visual.enhanced then
                    ApplyDiagnosticVisualMode(button, visual)
                else
                    RefreshSkinState(button, visual)
                end
            else
                ok = false
            end
        end
    end
    return ok
end

function Visuals:ApplyVehicleExitVisualMode(button, snapshot, options)
    if not button then return false end
    options = options or {}
    snapshot = snapshot or options.snapshot or DEFAULT_RUNTIME_SNAPSHOT

    if snapshot and snapshot.skin == "blizzard" then
        self:RestoreVehicleExitVisualMode(button)
        self:ApplyNativeButtonShadow(button, snapshot)
        self:HookButton(button)
        self:HookVehicleExitButtonState(button)
        return true
    end

    options.externalSpecialKind = "vehicleExit"
    options.snapshot = snapshot

    local visual = EnsureVisual(button, options)
    if not visual then return false end
    local skin = YAB.Skins and YAB.Skins:GetDefinition("default") or nil
    visual.skin = skin or {}
    visual.lastColor = nil
    visual.externalSpecial = true
    visual.externalSpecialKind = "vehicleExit"
    visual.nativeSpecialKind = visual.nativeSpecialKind or "vehicleExit"
    visual.externalArtMode = "yui"
    visual.nativeVisualExtrasHidden = false
    visual.hasAction = true

    if not self.theme then self:RefreshTheme("vehicle-exit") end
    if GUI2 and GUI2.RegisterLightBackendOwner then
        GUI2:RegisterLightBackendOwner(self, self)
    end

    self:ApplyExternalTextSnapshot(button, snapshot)
    local icon = self:EnsureVehicleExitIcon(button, visual)
    if not icon then return false end
    self:PrepareExternalSpecialState(visual, false)
    SetTexturePath(icon, self.vehicleExitIconPath)
    if icon.SetTexCoord then icon:SetTexCoord(0, 1, 0, 1) end
    if icon.Show then icon:Show() end
    LayoutCooldown(visual.cooldown, button, 0, 0, 0, 0, MAIN_COOLDOWN_SWIPE_ALPHA, true, MAIN_COOLDOWN_LEVEL_OFFSET, nil, visual)
    SetMainCooldownNumbersHidden(visual.cooldown, snapshot)
    NormalizeActionCooldownVisualLayers(button, visual)
    PrepareText(visual.hotkey, "RIGHT")
    ApplyRuntimeSnapshot(button, visual, snapshot, options)
    self:SuppressVehicleExitNativeArt(button, visual)
    self:HookButton(button)
    self:HookVehicleExitButtonState(button)
    self:RefreshVehicleExitNativeState(button, visual, true)
    if visual.enhanced then
        ApplyDiagnosticVisualMode(button, visual)
    else
        RefreshSkinState(button, visual)
    end
    return true
end

function Visuals:ApplyButton(button, skinId, options)
    options = options or {}
    local runtimeSnapshot = options.snapshot or button.yabConfigSnapshot or DEFAULT_RUNTIME_SNAPSHOT
    if options.externalSpecialKind == "extraAction" then
        return self:ApplyExtraActionVisualMode(button, runtimeSnapshot, options)
    elseif options.externalSpecialKind == "zoneAbility" then
        return self:ApplyZoneAbilityVisualMode(options.externalSpecialFrame or _G.ZoneAbilityFrame, { button }, runtimeSnapshot, options)
    elseif options.externalSpecialKind == "vehicleExit" then
        return self:ApplyVehicleExitVisualMode(button, runtimeSnapshot, options)
    end

    local visual = EnsureVisual(button, options)
    if not visual then return false end
    local skin = YAB.Skins and YAB.Skins:GetDefinition(skinId) or nil
    visual.skin = skin or {}
    visual.lastColor = nil

    if not self.theme then self:RefreshTheme("apply") end
    if GUI2 and GUI2.RegisterLightBackendOwner then
        GUI2:RegisterLightBackendOwner(self, self)
    end

    LayoutCooldown(visual.cooldown, button, 0, 0, 0, 0, MAIN_COOLDOWN_SWIPE_ALPHA, true, MAIN_COOLDOWN_LEVEL_OFFSET, nil, visual)
    SetMainCooldownNumbersHidden(visual.cooldown, runtimeSnapshot)
    NormalizeActionCooldownVisualLayers(button, visual)
    LayoutCooldown(visual.chargeCooldown, button, 0, 0, 0, 0, CHARGE_COOLDOWN_SWIPE_ALPHA, true, CHARGE_COOLDOWN_LEVEL_OFFSET, true, visual)
    if visual.nativeSpecial ~= true and visual.externalSpecial ~= true then
        StyleChargeCooldown(visual.chargeCooldown)
    end
    SetChargeCooldownNumbersHidden(visual.chargeCooldown, runtimeSnapshot)
    PrepareText(visual.hotkey, "RIGHT")
    PrepareText(visual.count, "RIGHT")
    if visual.name then
        PrepareText(visual.name, "CENTER")
    end
    ApplyRuntimeSnapshot(button, visual, runtimeSnapshot, options)
    if not IsNativeVisualMode() and not visual.flyoutPopup then
        EnsureManagedProcGlow(button, visual)
    end
    self:HookButton(button)
    if visual.enhanced then
        ApplyDiagnosticVisualMode(button, visual)
    else
        RefreshSkinState(button, visual)
    end
    return true
end

function Visuals:ApplyRuntimeSnapshot(button, snapshot)
    local visual = EnsureVisual(button)
    if not visual then return false end
    if not self.theme then self:RefreshTheme("runtime-snapshot") end
    return ApplyRuntimeSnapshot(button, visual, snapshot or button.yabConfigSnapshot or DEFAULT_RUNTIME_SNAPSHOT, nil)
end

function Visuals:GetSpellFlyoutSnapshot(owner)
    local ownerVisual = owner and Visuals.buttons and Visuals.buttons[owner] or nil
    return (ownerVisual and ownerVisual.runtimeSnapshot) or (owner and owner.yabConfigSnapshot) or DEFAULT_RUNTIME_SNAPSHOT
end

function Visuals:GetSpellFlyoutVisualState(button)
    if not button then return nil end
    local state = self.spellFlyoutVisualState[button]
    if not state then
        state = {}
        self.spellFlyoutVisualState[button] = state
    end
    return state
end

function Visuals:GetSpellFlyoutRGBA(color, fallback)
    color = type(color) == "table" and color or fallback
    if type(color) ~= "table" then color = DEFAULT_BORDER_COLOR end
    return color[1] or 0, color[2] or 0, color[3] or 0, color[4] == nil and 1 or color[4]
end

function Visuals:GetSpellFlyoutNormalTexture(button)
    if not button then return nil end
    if button.NormalTexture then return button.NormalTexture end
    if type(button.GetNormalTexture) ~= "function" then return nil end
    local ok, texture = pcall(button.GetNormalTexture, button)
    return ok and texture or nil
end

local function SuppressSpellFlyoutNativeBackdrop(button, icon)
    if not button then return 0 end
    local writes = 0
    writes = writes + SetRegionAlphaNoCache(Visuals:GetSpellFlyoutNormalTexture(button), 0)
    writes = writes + SetRegionAlphaNoCache(button.SlotBackground, 0)
    writes = writes + SetRegionAlphaNoCache(button.SlotArt, 0)
    writes = writes + SetRegionAlphaNoCache(button.BorderShadow, 0)
    writes = writes + SetRegionAlphaNoCache(button.Border, 0)

    local iconMask = button.IconMask
    if iconMask then
        if icon and icon.RemoveMaskTexture then
            local ok = pcall(icon.RemoveMaskTexture, icon, iconMask)
            if ok then writes = writes + 1 end
        end
        writes = writes + SetRegionAlphaNoCache(iconMask, 0)
        if iconMask.Hide then
            local ok = pcall(iconMask.Hide, iconMask)
            if ok then writes = writes + 1 end
        end
    end
    return writes
end

function Visuals:GetSpellFlyoutVisualInsets(button, style)
    if not (button and style and style.aspect and style.aspect > 1 and button.GetWidth and button.GetHeight) then
        return 0
    end
    local width = tonumber(button:GetWidth()) or 0
    local height = tonumber(button:GetHeight()) or 0
    if width <= 0 or height <= 0 then return 0 end
    local targetHeight = math.min(height, width / style.aspect)
    return math.max(0, (height - targetHeight) * 0.5)
end

function Visuals:GetSpellFlyoutVisualOutsets(button)
    local state = button and self.spellFlyoutVisualState and self.spellFlyoutVisualState[button] or nil
    if not state then return 0, 0 end
    return state.visualOutsetX or 0, state.visualOutsetY or 0
end

function Visuals:LayoutSpellFlyoutVisualRegion(button, region, style)
    if not (button and region) then return 0 end
    if region.ClearAllPoints then pcall(region.ClearAllPoints, region) end
    local insetY = self:GetSpellFlyoutVisualInsets(button, style)
    local outsetX, outsetY = self:GetSpellFlyoutVisualOutsets(button)
    if (insetY > 0 or outsetX > 0 or outsetY > 0) and region.SetPoint then
        pcall(region.SetPoint, region, "TOPLEFT", button, "TOPLEFT", -outsetX, outsetY - insetY)
        pcall(region.SetPoint, region, "BOTTOMRIGHT", button, "BOTTOMRIGHT", outsetX, insetY - outsetY)
        return 1
    end
    if region.SetAllPoints then
        pcall(region.SetAllPoints, region, button)
        return 1
    end
    return 0
end

function Visuals:CreateSpellFlyoutLine(button)
    if not (button and button.CreateTexture) then return nil end
    local ok, line = pcall(button.CreateTexture, button, nil, "OVERLAY", nil, 6)
    if not (ok and line) then return nil end
    if line.SetColorTexture then line:SetColorTexture(0, 0, 0, 1) end
    if line.Hide then line:Hide() end
    return line
end

function Visuals:EnsureSpellFlyoutLineBorder(button, state)
    if not state then return nil end
    if state.lineBorder then return state.lineBorder end
    state.lineBorder = {
        top = self:CreateSpellFlyoutLine(button),
        bottom = self:CreateSpellFlyoutLine(button),
        left = self:CreateSpellFlyoutLine(button),
        right = self:CreateSpellFlyoutLine(button),
    }
    return state.lineBorder
end

function Visuals:SetSpellFlyoutLineBorderShown(state, shown)
    local border = state and state.lineBorder
    if not border then return 0 end
    local writes = 0
    for _, line in pairs(border) do
        if shown and line and line.Show then
            line:Show()
            writes = writes + 1
        elseif line and line.Hide then
            line:Hide()
            writes = writes + 1
        end
    end
    return writes
end

function Visuals:LayoutSpellFlyoutLineBorder(button, state, thickness, r, g, b, a)
    local border = self:EnsureSpellFlyoutLineBorder(button, state)
    if not border then return 0 end
    local pixel = tonumber(thickness) or 1
    if pixel < 1 then pixel = 1 end
    local writes = 0
    local top, bottom, left, right = border.top, border.bottom, border.left, border.right
    local insetY = self:GetSpellFlyoutVisualInsets(button, state and state.style)
    local outsetX = state and state.visualOutsetX or 0
    local outsetY = state and state.visualOutsetY or 0
    if top then
        top:ClearAllPoints()
        top:SetPoint("TOPLEFT", button, "TOPLEFT", -outsetX, outsetY - insetY)
        top:SetPoint("TOPRIGHT", button, "TOPRIGHT", outsetX, outsetY - insetY)
        top:SetHeight(pixel)
        top:SetColorTexture(r, g, b, a)
        top:Show()
        writes = writes + 1
    end
    if bottom then
        bottom:ClearAllPoints()
        bottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -outsetX, insetY - outsetY)
        bottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", outsetX, insetY - outsetY)
        bottom:SetHeight(pixel)
        bottom:SetColorTexture(r, g, b, a)
        bottom:Show()
        writes = writes + 1
    end
    if left then
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", button, "TOPLEFT", -outsetX, outsetY - insetY)
        left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -outsetX, insetY - outsetY)
        left:SetWidth(pixel)
        left:SetColorTexture(r, g, b, a)
        left:Show()
        writes = writes + 1
    end
    if right then
        right:ClearAllPoints()
        right:SetPoint("TOPRIGHT", button, "TOPRIGHT", outsetX, outsetY - insetY)
        right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", outsetX, insetY - outsetY)
        right:SetWidth(pixel)
        right:SetColorTexture(r, g, b, a)
        right:Show()
        writes = writes + 1
    end
    return writes
end

function Visuals:GetSpellFlyoutDirection(owner)
    if owner and type(owner.GetPopupDirection) == "function" then
        local ok, direction = pcall(owner.GetPopupDirection, owner)
        if ok and direction then return direction end
    end
    return "UP"
end

function Visuals:GetSpellFlyoutTargetSpacing(snapshot)
    local spacing = tonumber(snapshot and snapshot.spacing) or SPELLFLYOUT_NATIVE_SPACING
    if spacing < 0 then spacing = 0 end
    if spacing > SPELLFLYOUT_NATIVE_SPACING then spacing = SPELLFLYOUT_NATIVE_SPACING end
    return spacing
end

function Visuals:SyncSpellFlyoutCompactSize(button, state, style, snapshot, owner)
    if not (button and state and button.GetWidth and button.GetHeight) then return 0 end
    local width = tonumber(button:GetWidth()) or 0
    local height = tonumber(button:GetHeight()) or 0
    if width <= 0 or height <= 0 then return 0 end

    if not state.originalWidth or not state.originalHeight or not state.compactSize then
        state.originalWidth = width
        state.originalHeight = height
    end

    local isFlat = style and style.aspect and style.aspect > 1
    local targetSpacing = isFlat and self:GetSpellFlyoutTargetSpacing(snapshot) or SPELLFLYOUT_NATIVE_SPACING
    local visualOutset = math.min(SPELLFLYOUT_MAX_VISUAL_OUTSET, math.max(0, (SPELLFLYOUT_NATIVE_SPACING - targetSpacing) * 0.5))
    local direction = self:GetSpellFlyoutDirection(owner)
    state.visualOutsetX = (direction == "LEFT" or direction == "RIGHT") and visualOutset or 0
    state.visualOutsetY = (direction == "UP" or direction == "DOWN") and visualOutset or 0

    if InCombat() then return 0 end

    local targetWidth = state.originalWidth
    local targetHeight = state.originalHeight
    if isFlat then
        targetHeight = math.max(1, targetWidth / style.aspect)
    end

    if math.abs(width - targetWidth) > 0.5 or math.abs(height - targetHeight) > 0.5 then
        if button.SetSize then
            local ok = pcall(button.SetSize, button, targetWidth, targetHeight)
            if ok then
                state.compactSize = isFlat == true
                return 1
            end
        end
    end
    state.compactSize = isFlat == true
    return 0
end

function Visuals:EnsureSpellFlyoutShapeMask(button, state)
    if not (button and state) then return nil end
    if state.shapeMask then return state.shapeMask end
    if not button.CreateMaskTexture then return nil end
    local ok, mask = pcall(button.CreateMaskTexture, button, nil, "BACKGROUND")
    if ok and mask then
        state.shapeMask = mask
    end
    return state.shapeMask
end

function Visuals:EnsureSpellFlyoutShapeBorder(button, state)
    if not (button and state) then return nil end
    if state.shapeBorder then return state.shapeBorder end
    if not button.CreateTexture then return nil end
    local ok, texture = pcall(button.CreateTexture, button, nil, "OVERLAY", nil, 6)
    if not (ok and texture) then return nil end
    if texture.Hide then texture:Hide() end
    state.shapeBorder = texture
    return texture
end

function Visuals:ApplySpellFlyoutMask(button, state, icon, cooldown, style)
    if not state then return 0 end
    local maskPath = style and style.mask
    local writes = 0
    if not maskPath then
        if icon and state.iconMask and icon.RemoveMaskTexture then
            pcall(icon.RemoveMaskTexture, icon, state.iconMask)
            state.iconMask = nil
            writes = writes + 1
        end
        if cooldown and state.cooldownMask and cooldown.RemoveMaskTexture then
            pcall(cooldown.RemoveMaskTexture, cooldown, state.cooldownMask)
            state.cooldownMask = nil
            writes = writes + 1
        end
        if cooldown and cooldown.SetSwipeTexture then pcall(cooldown.SetSwipeTexture, cooldown, SOLID_SWIPE_TEXTURE) end
        if cooldown and cooldown.SetUseCircularEdge then pcall(cooldown.SetUseCircularEdge, cooldown, false) end
        if state.shapeMask and state.shapeMask.Hide then state.shapeMask:Hide() end
        return writes
    end

    local mask = self:EnsureSpellFlyoutShapeMask(button, state)
    if not mask then return writes end
    if state.maskPath ~= maskPath then
        pcall(mask.SetTexture, mask, maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        state.maskPath = maskPath
    end
    writes = writes + self:LayoutSpellFlyoutVisualRegion(button, mask, style)
    if mask.Show then pcall(mask.Show, mask) end

    if icon and icon.AddMaskTexture and state.iconMask ~= mask then
        if state.iconMask and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, state.iconMask) end
        pcall(icon.AddMaskTexture, icon, mask)
        state.iconMask = mask
        writes = writes + 1
    end
    if cooldown and not (cooldown.IsForbidden and cooldown:IsForbidden()) then
        if cooldown.AddMaskTexture and state.cooldownMask ~= mask then
            if state.cooldownMask and cooldown.RemoveMaskTexture then pcall(cooldown.RemoveMaskTexture, cooldown, state.cooldownMask) end
            pcall(cooldown.AddMaskTexture, cooldown, mask)
            state.cooldownMask = mask
            writes = writes + 1
        end
        if cooldown.SetSwipeTexture then pcall(cooldown.SetSwipeTexture, cooldown, style.swipe or maskPath) end
        if cooldown.SetUseCircularEdge then pcall(cooldown.SetUseCircularEdge, cooldown, style.circular == true) end
    end
    return writes
end

function Visuals:ApplySpellFlyoutBorder(button, state, style, snapshot)
    if not (button and state) then return 0 end
    local thickness = self:GetCommonBorderThickness((snapshot and snapshot.border) or "thin") or 1
    if thickness <= 0 then
        local writes = self:SetSpellFlyoutLineBorderShown(state, false)
        if state.shapeBorder and state.shapeBorder.Hide then
            state.shapeBorder:Hide()
            writes = writes + 1
        end
        return writes
    end
    local r, g, b, a = self:GetSpellFlyoutRGBA(snapshot and snapshot.borderColor, DEFAULT_BORDER_COLOR)
    local familyTextures = style and style.borderFamily and SHAPE_BORDER_TEXTURES[style.borderFamily]
    local texturePath = familyTextures and familyTextures[thickness]
    if texturePath then
        local border = self:EnsureSpellFlyoutShapeBorder(button, state)
        if not border then return 0 end
        local writes = self:LayoutSpellFlyoutVisualRegion(button, border, style)
        if state.shapeBorderPath ~= texturePath then
            border:SetTexture(texturePath)
            state.shapeBorderPath = texturePath
        end
        border:SetVertexColor(r, g, b, a)
        border:Show()
        return writes + 1 + self:SetSpellFlyoutLineBorderShown(state, false)
    end
    if state.shapeBorder and state.shapeBorder.Hide then state.shapeBorder:Hide() end
    state.style = style
    return self:LayoutSpellFlyoutLineBorder(button, state, thickness, r, g, b, a)
end

function Visuals:GetSpellFlyoutStateTexture(button, field, getter)
    if not button then return nil end
    local region = button[field]
    if region then return region end
    if getter and type(button[getter]) == "function" then
        local ok, texture = pcall(button[getter], button)
        return ok and texture or nil
    end
    return nil
end

function Visuals:LayoutSpellFlyoutStateTexture(button, texture, style)
    if not (button and texture) then return 0 end
    return self:LayoutSpellFlyoutVisualRegion(button, texture, style)
end

function Visuals:ApplySpellFlyoutStateTexture(button, texture, style, color)
    if not (button and texture and color) then return 0 end
    local texturePath = self:GetButtonStateInnerTexture(style)
    if not texturePath then return 0 end
    local writes = self:LayoutSpellFlyoutStateTexture(button, texture, style)
    if texture.SetTexture then pcall(texture.SetTexture, texture, texturePath) end
    if texture.SetTexCoord then pcall(texture.SetTexCoord, texture, 0, 1, 0, 1) end
    if texture.SetVertexColor then
        pcall(texture.SetVertexColor, texture, color[1] or 1, color[2] or 1, color[3] or 1, color[4] == nil and 1 or color[4])
    end
    if texture.SetAlpha then pcall(texture.SetAlpha, texture, 1) end
    if texture.SetBlendMode then pcall(texture.SetBlendMode, texture, "ADD") end
    return writes + 1
end

function Visuals:ApplySpellFlyoutStateTextures(button, state, style)
    if not (button and state) then return 0 end
    local writes = 0
    writes = writes + self:ApplySpellFlyoutStateTexture(
        button,
        self:GetSpellFlyoutStateTexture(button, "HighlightTexture", "GetHighlightTexture"),
        style,
        BUTTON_STATE_COLORS.flyoutHover
    )
    writes = writes + self:ApplySpellFlyoutStateTexture(
        button,
        self:GetSpellFlyoutStateTexture(button, "PushedTexture", "GetPushedTexture"),
        style,
        BUTTON_STATE_COLORS.flyoutPushed
    )
    writes = writes + self:ApplySpellFlyoutStateTexture(
        button,
        self:GetSpellFlyoutStateTexture(button, "CheckedTexture", "GetCheckedTexture"),
        style,
        BUTTON_STATE_COLORS.flyoutChecked
    )
    return writes
end

function Visuals:ApplySpellFlyoutButtonVisual(button, owner, snapshot)
    if not button then return 0, false end
    if button.IsForbidden and button:IsForbidden() then return 0, false end
    local icon = button.icon or button.Icon
    if not icon then return 0, false end

    snapshot = snapshot or self:GetSpellFlyoutSnapshot(owner)
    local state = self:GetSpellFlyoutVisualState(button)
    if not state then return 0, false end

    local style = SHAPE_STYLES[(snapshot and snapshot.skin) or "square"] or SHAPE_STYLES.square
    local zoom = tonumber(snapshot and snapshot.iconZoom) or 0.08
    local writes = 0
    writes = writes + self:SyncSpellFlyoutCompactSize(button, state, style, snapshot, owner)
    writes = writes + SuppressSpellFlyoutNativeBackdrop(button, icon)
    if icon.SetAlpha then pcall(icon.SetAlpha, icon, 1) end
    writes = writes + self:LayoutSpellFlyoutVisualRegion(button, icon, style)
    if style.aspect and style.aspect > 1 then
        ApplyFlatIconCrop(icon, zoom, style.aspect)
    else
        ApplyIconCrop(icon, zoom)
    end
    writes = writes + self:ApplySpellFlyoutMask(button, state, icon, button.cooldown or button.Cooldown, style)
    writes = writes + self:ApplySpellFlyoutBorder(button, state, style, snapshot)
    writes = writes + self:ApplySpellFlyoutStateTextures(button, state, style)
    if not InCombat() then
        state.visualWidth = (state.originalWidth or snapshot.size or 36) + (state.visualOutsetX or 0) * 2
        state.visualHeight = state.originalHeight or snapshot.size or 36
        if style.aspect and style.aspect > 1 then
            state.visualHeight = math.min(state.visualHeight, (state.originalWidth or snapshot.size or 36) / style.aspect)
        end
        state.visualHeight = state.visualHeight + (state.visualOutsetY or 0) * 2
    end
    state.runtimeSkin = snapshot.skin
    state.shadowContour = icon
    if InCombat() and snapshot.shadow ~= false then self.spellFlyoutShadowPending = true end
    writes = writes + self:ApplyButtonShadow(button, state, snapshot, not InCombat())
    return writes, true
end

function Visuals:SkinSpellFlyoutButtons(reason)
    if YAB.BarManager and YAB.BarManager.runtimeActive == false then return 0 end
    local flyout = _G.SpellFlyout
    if not flyout then return 0 end
    local owner = flyout.GetParent and flyout:GetParent() or flyout.flyoutButton
    if not owner then owner = flyout.flyoutButton end
    local snapshot = self:GetSpellFlyoutSnapshot(owner)
    local writes = HideSpellFlyoutBackground(flyout)
    local skinned = 0
    local childCount = flyout.GetNumChildren and flyout:GetNumChildren() or 0
    for index = 1, childCount do
        local button = select(index, flyout:GetChildren())
        if button and button.IsShown and button:IsShown() and (button.icon or button.Icon) then
            local buttonWrites, ok = self:ApplySpellFlyoutButtonVisual(button, owner, snapshot)
            writes = writes + (buttonWrites or 0)
            if ok then skinned = skinned + 1 end
        end
    end
    self.stats.spellFlyoutButtons = skinned
    self.stats.spellFlyoutSkinWrites = (self.stats.spellFlyoutSkinWrites or 0) + writes
    return writes
end

function Visuals:FlushPendingSpellFlyoutShadow()
    if not self.spellFlyoutShadowPending or InCombat() then return 0 end
    self.spellFlyoutShadowPending = nil
    local flyout = _G.SpellFlyout
    if not (flyout and flyout.IsShown and flyout:IsShown()) then return 0 end
    return self:SkinSpellFlyoutButtons("combat-deferred-shadow")
end

function Visuals:InstallSpellFlyoutHooks()
    if self.spellFlyoutHooked then return true end
    local flyout = _G.SpellFlyout
    if not (flyout and flyout.HookScript) then return false end
    flyout:HookScript("OnShow", function()
        Visuals:SkinSpellFlyoutButtons("show")
    end)
    self.spellFlyoutHooked = true
    return true
end

function Visuals:EnsureSpellFlyoutHooks()
    if self:InstallSpellFlyoutHooks() then return true end
    if self.spellFlyoutRetryFrame or not _G.CreateFrame then return false end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function(retryFrame)
        if Visuals:InstallSpellFlyoutHooks() then
            retryFrame:UnregisterAllEvents()
            retryFrame:SetScript("OnEvent", nil)
            Visuals.spellFlyoutRetryFrame = nil
        end
    end)
    self.spellFlyoutRetryFrame = frame
    return false
end

function Visuals:SetCountTextFast(button, text, textIsSecret)
    local visual = self.buttons[button]
    if not visual then return nil end
    local writes
    if textIsSecret == true then
        local count = visual.count
        if not count then return nil end
        count:SetText(text)
        TEXT_CACHE[count] = nil
        writes = 1 + RegionShown(count, true)
    else
        writes = SetText(visual.count, text)
    end
    self.stats.writes = (self.stats.writes or 0) + writes
    return writes
end

function Visuals:ApplyActionTintFast(button, usable, noMana, outOfRange, deferStats)
    local visual = button and self.buttons[button]
    if not visual then return 0 end
    local icon = visual.icon or button.icon or button.Icon
    if not icon then return 0 end

    visual.usable = usable == true
    visual.noMana = noMana == true
    visual.outOfRange = outOfRange == true

    local skin = visual.skin or (YAB.Skins and YAB.Skins:GetDefinition("default")) or DEFAULT_RUNTIME_SNAPSHOT
    local color = skin.normalIconColor
    if visual.hasAction == false then
        color = skin.emptyIconColor or EMPTY_ICON_COLOR
    elseif visual.outOfRange == true and visual.rangeMode == "red" then
        color = skin.outOfRangeIconColor
    elseif visual.noMana == true then
        color = skin.noManaIconColor
    elseif visual.usable == false then
        color = skin.unusableIconColor
    end
    local writes = 0
    if visual.lastColor ~= color then
        visual.lastColor = color
        writes = writes + SetVertexColor(icon, color, skin.normalIconColor)
    end
    local colors = self.theme and self.theme.colors or DEFAULT_RUNTIME_SNAPSHOT
    local snapshot = visual.runtimeSnapshot or (button and button.yabConfigSnapshot) or DEFAULT_RUNTIME_SNAPSHOT
    local textColor = visual.outOfRange == true and visual.rangeMode == "red"
        and (skin.outOfRangeTextColor or FALLBACK_RANGE_TEXT_COLOR)
        or snapshot.hotkeyColor or colors.text or DEFAULT_TEXT_COLOR
    writes = writes + SetTextColor(visual.hotkey, textColor)
    if deferStats ~= true then
        self.stats.writes = (self.stats.writes or 0) + writes
        self.stats.skinWrites = (self.stats.skinWrites or 0) + writes
    end
    return writes
end

local function GetProfessionQualityAtlasRatio(visuals, atlas)
    local cached = visuals.professionQualityAtlasRatios[atlas]
    if cached ~= nil then return cached or nil end

    local reader = _G.C_Texture and _G.C_Texture.GetAtlasInfo
    if type(reader) ~= "function" then
        visuals.professionQualityAtlasRatios[atlas] = false
        return nil
    end
    local info = reader(atlas)
    local width = info and tonumber(info.width)
    local height = info and tonumber(info.height)
    if not (width and height and width > 0 and height > 0) then
        visuals.professionQualityAtlasRatios[atlas] = false
        return nil
    end

    local ratio = width / height
    visuals.professionQualityAtlasRatios[atlas] = ratio
    return ratio
end

function Visuals:ApplyProfessionQuality(button, atlas, snapshot)
    local visual = button and self.buttons[button]
    if not visual or visual.isAction ~= true then return 0 end
    if type(atlas) ~= "string" or atlas == "" then atlas = nil end
    visual.professionQualityAtlas = atlas
    snapshot = snapshot or visual.runtimeSnapshot or button.yabConfigSnapshot or DEFAULT_RUNTIME_SNAPSHOT
    local shouldShow = atlas ~= nil and snapshot.showProfessionQuality ~= false
    local atlasRatio = shouldShow and GetProfessionQualityAtlasRatio(self, atlas) or nil
    shouldShow = atlasRatio ~= nil
    local overlay = visual.professionQualityOverlay
    if not shouldShow then
        self.pendingProfessionQuality[button] = nil
        return RegionShown(overlay, false)
    end

    if not overlay then
        if InCombat() then
            self.pendingProfessionQuality[button] = true
            return 0
        end
        if type(_G.CreateFrame) ~= "function" then return 0 end
        overlay = _G.CreateFrame("FRAME", nil, button, "ActionButtonTextureOverlayTemplate")
        local texture = overlay and overlay.Texture
        if not (overlay and texture and type(texture.SetAtlas) == "function") then
            return RegionShown(overlay, false)
        end
        visual.professionQualityOverlay = overlay
        visual.professionQualityTexture = texture
    end

    local texture = visual.professionQualityTexture or overlay.Texture
    if not (texture and type(texture.SetAtlas) == "function") then
        return RegionShown(overlay, false)
    end
    local writes = 0
    if visual.professionQualityAppliedAtlas ~= atlas then
        texture:SetAtlas(atlas, _G.TextureKitConstants.IgnoreAtlasSize)
        visual.professionQualityAppliedAtlas = atlas
        writes = writes + 1
    end
    local size = tonumber(snapshot.professionQualitySize) or 21
    local width = size * atlasRatio
    local offsetX = tonumber(snapshot.professionQualityOffsetX) or 0
    local offsetY = tonumber(snapshot.professionQualityOffsetY) or 0
    if visual.professionQualityWidth ~= width
        or visual.professionQualityHeight ~= size
        or visual.professionQualityOffsetX ~= offsetX
        or visual.professionQualityOffsetY ~= offsetY then
        if InCombat() then
            self.pendingProfessionQuality[button] = true
        else
            if overlay.ClearAllPoints then overlay:ClearAllPoints() end
            overlay:SetPoint("TOPLEFT", button, "TOPLEFT", offsetX, offsetY)
            overlay:SetSize(width, size)
            texture:SetSize(width, size)
            visual.professionQualityWidth = width
            visual.professionQualityHeight = size
            visual.professionQualityOffsetX = offsetX
            visual.professionQualityOffsetY = offsetY
            writes = writes + 3
        end
    end
    if not InCombat() then self.pendingProfessionQuality[button] = nil end
    writes = writes + RegionShown(overlay, true)
    return writes
end

function Visuals:FlushPendingProfessionQuality()
    local refreshed = 0
    local writes = 0
    for button in pairs(self.pendingProfessionQuality) do
        self.pendingProfessionQuality[button] = nil
        local visual = self.buttons[button]
        if visual then
            refreshed = refreshed + 1
            writes = writes + self:ApplyProfessionQuality(
                button,
                visual.professionQualityAtlas,
                visual.runtimeSnapshot or button.yabConfigSnapshot
            )
        end
    end
    return refreshed, writes
end

function Visuals:SetExternalRangeState(button, outOfRange)
    local visual = button and self.buttons[button]
    if not visual or visual.externalSpecial ~= true or visual.externalArtMode == "blizzard" then return nil end
    visual.outOfRange = outOfRange == true
    visual.lastColor = nil
    local writes = RefreshSkinState(button, visual)
    self.stats.writes = (self.stats.writes or 0) + writes
    return writes
end

function Visuals:SetProcGlow(button, shown)
    local visual = self.buttons[button]
    if not visual then return 0 end
    shown = shown == true
    local procShape = visual.runtimeSkin == "circle" and "circle" or "square"
    if visual.procGlow == shown and visual.procGlowFrame and visual.procGlowFrame.yabProcShape == procShape then return 0 end
    if shown == false and not visual.procGlowFrame then
        visual.procGlow = false
        return 0
    end
    visual.procGlow = shown
    if IsNativeVisualMode() then
        if visual.procGlowFrame then
            StopManagedProcGlow(visual.procGlowFrame)
        end
        return 0
    end
    HideNativeProcAlert(button)
    if not visual.procGlow then
        if visual.procGlowFrame then
            StopManagedProcGlow(visual.procGlowFrame)
            return 1
        end
        return 0
    end
    if InCombat() then
        if visual.procGlowFrame then
            PlayManagedProcGlow(visual.procGlowFrame)
            return 1
        end
        return 0
    end
    local glow = EnsureManagedProcGlow(button, visual)
    if not glow then return 0 end
    PlayManagedProcGlow(glow)
    return 1
end

function Visuals:UpdateCooldownFast(button, state)
    local visual = self.buttons[button]
    if not visual then return 0 end
    state = state or {}
    visual.hasAction = state.hasAction == true
    local snapshot = visual.runtimeSnapshot
        or (button and button.yabConfigSnapshot)
        or DEFAULT_RUNTIME_SNAPSHOT

    local writes = 0
    local cooldownWrites = 0
    if visual.icon then
        local desat = self:GetIconCooldownDesaturation(visual, state)
        cooldownWrites = cooldownWrites + SetIconDesaturation(visual.icon, desat)
    end
    local cooldownEnabled = state.cooldownActive == true or state.cooldownEnable == true
    local chargeEnabled = state.chargeEnable == true
    cooldownWrites = cooldownWrites + SetText(visual.count, state.countText)
    cooldownWrites = cooldownWrites + SetMainCooldownNumbersHidden(visual.cooldown, snapshot)
    cooldownWrites = cooldownWrites + SetCooldown(visual.cooldown, state.cooldownDurationObject, state.cooldownStart, state.cooldownDuration, cooldownEnabled, state.cooldownModRate)
    cooldownWrites = cooldownWrites + SetChargeCooldownNumbersHidden(visual.chargeCooldown, snapshot)
    cooldownWrites = cooldownWrites + SetCooldown(visual.chargeCooldown, state.chargeDurationObject, state.chargeStart, state.chargeDuration, chargeEnabled, state.chargeModRate)
    writes = writes + cooldownWrites

    self.stats.writes = (self.stats.writes or 0) + writes
    return writes
end

function Visuals:UpdateActionChargeOnly(button, state)
    local visual = self.buttons[button]
    if not visual then return 0, 0, 0, 0, 0 end
    state = state or {}
    visual.hasAction = state.hasAction == true
    local snapshot = visual.runtimeSnapshot
        or (button and button.yabConfigSnapshot)
        or DEFAULT_RUNTIME_SNAPSHOT

    local writes = 0
    local countWrites = 0
    local chargeWrites = 0
    local skipped = 0

    local maxCharges = type(state.maxCharges) == "number" and state.maxCharges or 0
    if maxCharges > 1 then
        countWrites = SetText(visual.count, state.countText)
        writes = writes + countWrites
        chargeWrites = chargeWrites + SetChargeCooldownNumbersHidden(visual.chargeCooldown, snapshot)
        local chargeEnabled = state.chargeEnable == true
        chargeWrites = chargeWrites + SetCooldown(visual.chargeCooldown, state.chargeDurationObject, state.chargeStart, state.chargeDuration, chargeEnabled, state.chargeModRate)
    else
        if visual.count and TEXT_CACHE[visual.count] ~= nil and TEXT_CACHE[visual.count] ~= "" then
            countWrites = SetText(visual.count, "")
            writes = writes + countWrites
        end
        chargeWrites = SetCooldown(visual.chargeCooldown, nil, nil, nil, false)
    end
    writes = writes + chargeWrites
    if chargeWrites == 0 then skipped = skipped + 1 end

    self.stats.writes = (self.stats.writes or 0) + writes
    local shown = visual.chargeCooldown and visual.chargeCooldown.IsShown and visual.chargeCooldown:IsShown() and 1 or 0
    return writes, chargeWrites, countWrites, skipped, shown
end

function Visuals:UpdateActionCooldownOnly(button, state)
    local visual = self.buttons[button]
    if not visual then return 0, 0, 0, 0, 0, 0 end
    state = state or {}
    visual.hasAction = state.hasAction == true
    local snapshot = visual.runtimeSnapshot
        or (button and button.yabConfigSnapshot)
        or DEFAULT_RUNTIME_SNAPSHOT

    local writes = 0
    local desatWrites = 0
    local countWrites = 0
    local mainWrites = 0
    local chargeWrites = 0
    local skipped = 0

    if visual.icon then
        local desat = self:GetIconCooldownDesaturation(visual, state)
        desatWrites = SetIconDesaturation(visual.icon, desat)
        writes = writes + desatWrites
    end

    countWrites = SetText(visual.count, state.countText)
    writes = writes + countWrites

    local cooldownEnabled = state.cooldownActive == true or state.cooldownEnable == true
    mainWrites = mainWrites + SetMainCooldownNumbersHidden(visual.cooldown, snapshot)
    mainWrites = mainWrites + SetCooldown(visual.cooldown, state.cooldownDurationObject, state.cooldownStart, state.cooldownDuration, cooldownEnabled, state.cooldownModRate)
    writes = writes + mainWrites
    if mainWrites == 0 then skipped = skipped + 1 end

    local maxCharges = type(state.maxCharges) == "number" and state.maxCharges or 0
    if maxCharges > 1 then
        chargeWrites = chargeWrites + SetChargeCooldownNumbersHidden(visual.chargeCooldown, snapshot)
        local chargeEnabled = state.chargeEnable == true
        chargeWrites = chargeWrites + SetCooldown(visual.chargeCooldown, state.chargeDurationObject, state.chargeStart, state.chargeDuration, chargeEnabled, state.chargeModRate)
    else
        chargeWrites = SetCooldown(visual.chargeCooldown, nil, nil, nil, false)
    end
    writes = writes + chargeWrites
    if chargeWrites == 0 then skipped = skipped + 1 end

    self.stats.writes = (self.stats.writes or 0) + writes
    return writes, mainWrites, chargeWrites, countWrites, desatWrites, skipped
end

function Visuals:UpdateButton(button, state, mode)
    local visual = self.buttons[button]
    if not visual then return 0 end
    state = state or {}
    if visual.rankUpgradeSpellID
        and (Security and Security.SafeNumber(state.actionID)) ~= visual.rankUpgradeSpellID then
        self:StopRankUpgrade(button)
    end
    mode = mode or "full"
    local writes = 0

    visual.hasAction = state.hasAction == true
    visual.usable = state.usable ~= false
    visual.noMana = state.noMana == true
    visual.outOfRange = (state.rangeMode == "red" or visual.rangeMode == "red") and state.inRange == false
    visual.checked = state.checked == true
    if visual.nativeChecked and (mode == "full" or RefreshModeHas(mode, "state")) then
        writes = writes + YAB.BarManager:SetButtonCheckedState(button, state.hasAction == true and visual.checked)
    end
    local snapshot = visual.runtimeSnapshot
        or (button and button.yabConfigSnapshot)
        or DEFAULT_RUNTIME_SNAPSHOT

    local countText = state.countText
    if state.hasAction ~= true then
        countText = ""
    end

    local updateIdentity = RefreshModeHas(mode, "identity")
    local updateCooldown = RefreshModeHas(mode, "cooldown")
    local updateCooldownMeta = mode == "cooldownMeta" or (type(mode) == "string" and mode:find(":cooldownMeta:", 1, true) ~= nil)
    local updateHotkey = RefreshModeHas(mode, "hotkey")
    local updateText = mode ~= "full" and RefreshModeHas(mode, "text")
    local updateUsable = RefreshModeHas(mode, "usable") or RefreshModeHas(mode, "range") or RefreshModeHas(mode, "state")
    local updateGlow = RefreshModeHas(mode, "glow")

    if visual.nativeSpecial and visual.autoCastOverlay and (mode == "full" or RefreshModeHas(mode, "state")) then
        writes = writes + SetPetAutoCastVisual(button, visual, state.petAutoCastAllowed == true, state.petAutoCastEnabled == true)
    end

    if visual.isAction then
        if updateIdentity then
            local assistedCombat = state.hasAction == true and state.assistedCombat == true
            writes = writes + self:ApplyAssistedCombatVisual(button, visual, assistedCombat)
        end
        if visual.icon then
            if updateIdentity then
                if state.hasAction == true then
                    local texture = state.texture
                    if Security and Security.IsSecretValue and Security.IsSecretValue(texture) then
                        texture = visual.iconTexture
                    end
                    texture = texture or DEFAULT_ICON
                    if visual.iconTexture ~= texture then
                        visual.icon:SetTexture(texture)
                        visual.iconTexture = texture
                        writes = writes + 1
                    end
                    writes = writes + RegionShown(visual.icon, true)
                else
                    writes = writes + RegionShown(visual.icon, false)
                end
            elseif state.hasAction ~= true then
                writes = writes + RegionShown(visual.icon, false)
            end
            if updateIdentity or updateCooldown or updateCooldownMeta or state.hasAction ~= true then
                writes = writes + SetIconDesaturation(visual.icon, self:GetIconCooldownDesaturation(visual, state))
            end
        end
        if updateHotkey or updateText then
            writes = writes + SetText(visual.hotkey, state.hotkeyText)
            writes = writes + SetText(visual.name, state.nameText)
        end
        if updateText then
            writes = writes + SetText(visual.count, countText)
        end
        if updateCooldown or updateCooldownMeta then
            local cooldownWrites = 0
            local cooldownEnabled = state.cooldownActive == true or state.cooldownEnable == true
            local maxCharges = type(state.maxCharges) == "number" and state.maxCharges or 0
            cooldownWrites = cooldownWrites + SetText(visual.count, countText)
            cooldownWrites = cooldownWrites + SetMainCooldownNumbersHidden(visual.cooldown, snapshot)
            cooldownWrites = cooldownWrites + SetChargeCooldownNumbersHidden(visual.chargeCooldown, snapshot)
            if updateCooldown then
                local mainWrites = SetCooldown(visual.cooldown, state.cooldownDurationObject, state.cooldownStart, state.cooldownDuration, cooldownEnabled, state.cooldownModRate)
                local chargeWrites = 0
                if maxCharges > 1 then
                    local chargeEnabled = state.chargeEnable == true
                    chargeWrites = chargeWrites + SetCooldown(visual.chargeCooldown, state.chargeDurationObject, state.chargeStart, state.chargeDuration, chargeEnabled, state.chargeModRate)
                else
                    chargeWrites = SetCooldown(visual.chargeCooldown, nil, nil, nil, false)
                end
                cooldownWrites = cooldownWrites + mainWrites + chargeWrites
            end
            writes = writes + cooldownWrites
        end
        if updateUsable then
            local stateWrites = RefreshSkinState(button, visual)
            writes = writes + stateWrites
        end
        if updateGlow then
            local glowWrites = self:SetProcGlow(button, state.procGlow == true)
            writes = writes + glowWrites
        end
    else
        if visual.icon then
            if updateIdentity then
                if state.hasAction == true then
                    local texture = state.texture
                    if Security and Security.IsSecretValue and Security.IsSecretValue(texture) then
                        texture = visual.iconTexture
                    end
                    texture = texture or DEFAULT_ICON
                    if visual.iconTexture ~= texture then
                        visual.icon:SetTexture(texture)
                        visual.iconTexture = texture
                        writes = writes + 1
                    end
                    writes = writes + RegionShown(visual.icon, true)
                else
                    writes = writes + RegionShown(visual.icon, false)
                end
            elseif state.hasAction ~= true then
                writes = writes + RegionShown(visual.icon, false)
            end
            if updateCooldown or updateCooldownMeta then
                local cooldownWrites = 0
                local desat = self:GetIconCooldownDesaturation(visual, state)
                cooldownWrites = cooldownWrites + SetIconDesaturation(visual.icon, desat)
                writes = writes + cooldownWrites
            end
        end
        if updateHotkey or updateText then
            writes = writes + SetText(visual.hotkey, state.hotkeyText)
            writes = writes + SetText(visual.name, state.nameText)
        end
        if updateText then
            writes = writes + SetText(visual.count, countText)
        end
        if updateCooldown or updateCooldownMeta then
            local cooldownWrites = 0
            local cooldownEnabled = state.cooldownActive == true or state.cooldownEnable == true
            cooldownWrites = cooldownWrites + SetText(visual.count, countText)
            cooldownWrites = cooldownWrites + SetMainCooldownNumbersHidden(visual.cooldown, snapshot)
            if updateCooldown then
                cooldownWrites = cooldownWrites + SetCooldown(visual.cooldown, state.cooldownDurationObject, state.cooldownStart, state.cooldownDuration, cooldownEnabled, state.cooldownModRate)
            end
            writes = writes + cooldownWrites
        end
        if not visual.nativeChecked and button.SetChecked and (mode == "full" or RefreshModeHas(mode, "state")) then button:SetChecked(state.checked == true) end
        if visual.nativeSpecial and HideNativeButtonStateArt then
            writes = writes + HideNativeButtonStateArt(button, visual)
        end
        if updateUsable then
            local stateWrites = RefreshSkinState(button, visual)
            writes = writes + stateWrites
        end
        if updateGlow then
            local glowWrites = self:SetProcGlow(button, state.procGlow == true)
            writes = writes + glowWrites
        end
    end

    self.stats.writes = (self.stats.writes or 0) + writes
    return writes
end

function Visuals:UpdateEmpty(button)
    return self:UpdateButton(button, { hasAction = false, countText = "" })
end

function Visuals:CreateBindHighlightRegion(button, subLevel)
    if not (button and button.CreateTexture) then return nil end
    local ok, region = pcall(button.CreateTexture, button, nil, "OVERLAY", nil, subLevel or 7)
    if not (ok and region) then return nil end
    region:Hide()
    return region
end

function Visuals:EnsureBindHighlight(button)
    if not button then return nil end
    local state = self.bindHighlights[button]
    if state then return state end
    state = {
        top = self:CreateBindHighlightRegion(button, 7),
        bottom = self:CreateBindHighlightRegion(button, 7),
        left = self:CreateBindHighlightRegion(button, 7),
        right = self:CreateBindHighlightRegion(button, 7),
    }
    if not (state.top and state.bottom and state.left and state.right) then
        return nil
    end
    self.bindHighlights[button] = state
    self.stats.bindHighlightButtons = (self.stats.bindHighlightButtons or 0) + 1
    return state
end

function Visuals:SetBindHighlight(button, shown, hovered)
    local active = shown == true and hovered == true
    local state = active and self:EnsureBindHighlight(button) or self.bindHighlights[button]
    if not state then return false end
    if state.shown == active and state.hovered == active then return true end
    state.shown = active
    state.hovered = active

    local r, g, b, a = 0.35, 0.72, 1, 0.95
    if GUI2 and GUI2.GetColor then
        r, g, b, a = GUI2:GetColor("color.border.accent")
    end
    local thickness = 2
    local edgeAlpha = math.max(tonumber(a) or 1, 0.95)
    local edges = { state.top, state.bottom, state.left, state.right }
    for index = 1, #edges do
        edges[index]:SetColorTexture(r, g, b, edgeAlpha)
    end
    state.top:ClearAllPoints()
    state.top:SetPoint("TOPLEFT", button, "TOPLEFT", -thickness, thickness)
    state.top:SetPoint("TOPRIGHT", button, "TOPRIGHT", thickness, thickness)
    state.top:SetHeight(thickness)
    state.bottom:ClearAllPoints()
    state.bottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -thickness, -thickness)
    state.bottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", thickness, -thickness)
    state.bottom:SetHeight(thickness)
    state.left:ClearAllPoints()
    state.left:SetPoint("TOPLEFT", button, "TOPLEFT", -thickness, thickness)
    state.left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -thickness, -thickness)
    state.left:SetWidth(thickness)
    state.right:ClearAllPoints()
    state.right:SetPoint("TOPRIGHT", button, "TOPRIGHT", thickness, thickness)
    state.right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", thickness, -thickness)
    state.right:SetWidth(thickness)

    if state.fill then
        state.fill:Hide()
    end
    for index = 1, #edges do
        if active then edges[index]:Show() else edges[index]:Hide() end
    end
    return true
end

function Visuals:ReleaseButton(button)
    self:StopRankUpgrade(button)
    self:SetBindHighlight(button, false, false)
    if GUI2 and GUI2.HideShapeShadow and self.nativeShadowStates then
        local state = self.nativeShadowStates[button]
        if state then GUI2:HideShapeShadow(state.shadowHandle) end
    end
    local visual = self.buttons[button]
    if not visual then return end
    if visual.nativeChecked then YAB.BarManager:ClearButtonCheckedState(button) end
    if GUI2 and GUI2.HideShapeShadow then GUI2:HideShapeShadow(visual.shadowHandle) end
    self.pendingProfessionQuality[button] = nil
    RegionShown(visual.professionQualityOverlay, false)
    if visual.externalSpecialKind == "extraAction" then
        self:RestoreExternalSpecialButton(button)
    elseif visual.externalSpecialKind == "zoneAbility" then
        self:RestoreZoneAbilityButton(button)
    elseif visual.externalSpecialKind == "vehicleExit" then
        self:RestoreVehicleExitVisualMode(button)
    end
    self:SetProcGlow(button, false)
    self:ApplyAssistedCombatVisual(button, visual, false)
    ReleasePetAutoCastVisual(button, visual)
    visual.checked = false
    HideExtraVisualRegion(visual.bgSlotArt)
    RegionShown(visual.checkedOverlay, false)
    RegionShown(visual.checkedRing, false)
    RegionShown(visual.petCheckedState, false)
    ApplyPetCheckedEdge(button, visual, nil)
    if visual.procGlowFrame then
        StopManagedProcGlow(visual.procGlowFrame)
    end
    if visual.icon and not visual.isAction and not visual.nativeSpecial and not visual.externalSpecial then visual.icon:Hide() end
    if visual.cooldown and not visual.isAction and not visual.nativeSpecial and not visual.externalSpecial then visual.cooldown:Hide() end
    if visual.icon then ICON_DESATURATION_CACHE[visual.icon] = nil end
    if visual.count then
        TEXT_CACHE[visual.count] = nil
        TEXT_COLOR_CACHE[visual.count] = nil
    end
    if visual.hotkey then
        TEXT_CACHE[visual.hotkey] = nil
        TEXT_COLOR_CACHE[visual.hotkey] = nil
    end
    if visual.name then
        TEXT_CACHE[visual.name] = nil
        TEXT_COLOR_CACHE[visual.name] = nil
    end
    if visual.cooldown then COOLDOWN_CACHE[visual.cooldown] = nil end
    if visual.chargeCooldown then COOLDOWN_CACHE[visual.chargeCooldown] = nil end
end

function Visuals:StopRankUpgrade(button)
    local visual = self.buttons[button]
    if not (visual and visual.rankUpgradeAnimation) then return end
    visual.rankUpgradeSpellID = nil
    visual.rankUpgradeAnimation:Stop()
    visual.rankUpgradeTexture:Hide()
end

function Visuals:StopAllRankUpgrades()
    for button in pairs(self.buttons) do self:StopRankUpgrade(button) end
end

function Visuals:FlashRankUpgrade(button, spellID)
    local visual = self.buttons[button]
    if not (visual and visual.isAction and button.IsVisible and button:IsVisible()) or InCombat() then return false end
    self:StopRankUpgrade(button)
    local texture = visual.rankUpgradeTexture
    if not texture then
        texture = CreateSkinTexture(button, "OVERLAY", nil, 7)
        if not texture then return false end
        visual.rankUpgradeTexture = texture
        local group = texture:CreateAnimationGroup()
        visual.rankUpgradeAnimation = group
        group:SetLooping("NONE")
        group:SetToFinalAlpha(true)
        local phases = { { 0, 1, 0.12 }, { 1, 0.35, 0.18 }, { 0.35, 1, 0.12 }, { 1, 0, 1.08 } }
        for order, phase in ipairs(phases) do
            local animation = group:CreateAnimation("Alpha")
            animation:SetOrder(order)
            animation:SetFromAlpha(phase[1])
            animation:SetToAlpha(phase[2])
            animation:SetDuration(phase[3])
        end
        group:SetScript("OnFinished", function()
            visual.rankUpgradeSpellID = nil
            texture:Hide()
        end)
    end
    local style = SHAPE_STYLES[visual.runtimeSkin or "square"] or SHAPE_STYLES.square
    ApplyVisualRect(button, visual, texture, 0)
    texture:SetTexture(self:GetButtonStateInnerTexture(style))
    texture:SetVertexColor(1, 0.78, 0.12, 1)
    texture:SetBlendMode("ADD")
    texture:SetAlpha(0)
    texture:Show()
    visual.rankUpgradeSpellID = spellID
    visual.rankUpgradeAnimation:Play()
    return true
end

function Visuals:ReleaseAll()
    self.spellFlyoutShadowPending = nil
    for button in pairs(self.buttons) do
        self:ReleaseButton(button)
    end
    for button in pairs(self.externalTextSnapshots) do
        self:RestoreExternalTextState(button)
    end
    for frame in pairs(self.zoneAbilityFrames or {}) do
        self:RestoreZoneAbilityFrameArt(frame)
    end
    if GUI2 and GUI2.HideShapeShadow then
        for _, state in pairs(self.nativeShadowStates or {}) do GUI2:HideShapeShadow(state.shadowHandle) end
        for _, state in pairs(self.spellFlyoutVisualState) do GUI2:HideShapeShadow(state.shadowHandle) end
    end
    if GUI2 and GUI2.UnregisterLightBackendOwner then
        GUI2:UnregisterLightBackendOwner(self)
    end
end

function Visuals:GetDiagnosticVisualMode()
    return self.diagnosticVisualMode or "enhanced"
end

function Visuals:SetDiagnosticVisualMode(mode)
    mode = tostring(mode or ""):lower()
    if mode ~= "native" and mode ~= "enhanced" then
        return false, self:GetDiagnosticVisualMode(), 0
    end
    if self.diagnosticVisualMode == mode then
        local writes = self:RefreshNativeButtonShadows()
        for button, visual in pairs(self.buttons) do
            if visual.externalSpecial ~= true or self.externalTextSnapshots[button] ~= nil then
                writes = writes + ApplyDiagnosticVisualMode(button, visual)
            end
        end
        return true, mode, writes
    end

    self.diagnosticVisualMode = mode
    self.stats.visualModeSwitches = (self.stats.visualModeSwitches or 0) + 1
    local writes = self:RefreshNativeButtonShadows()
    for button, visual in pairs(self.buttons) do
        if visual.externalSpecial ~= true or self.externalTextSnapshots[button] ~= nil then
            writes = writes + ApplyDiagnosticVisualMode(button, visual)
        end
    end
    return true, mode, writes
end

function Visuals:GetStats()
    self.stats.visualImplementationType = self.implementationType
    self.stats.visualMode = self:GetDiagnosticVisualMode()
    self.stats.gui2ButtonObjects = 0
    self.stats.procGlowBackend = self.stats.procGlowBackend or "yui-managed-proc-template"
    local hidden = 0
    local procGlowFrames = 0
    local petAutoCastOverlays = 0
    for _, visual in pairs(self.buttons) do
        if visual.nativeVisualExtrasHidden == true then hidden = hidden + 1 end
        if visual.procGlowFrame then procGlowFrames = procGlowFrames + 1 end
        if visual.autoCastOverlay or visual.petAutoCastCircle then petAutoCastOverlays = petAutoCastOverlays + 1 end
    end
    self.stats.visualExtraHidden = hidden
    self.stats.procGlowFrames = procGlowFrames
    self.stats.petAutoCastOverlays = petAutoCastOverlays
    return self.stats
end

function Visuals:GetButtonVisual(button)
    return self.buttons and self.buttons[button] or nil
end

Visuals:EnsureSpellFlyoutHooks()
