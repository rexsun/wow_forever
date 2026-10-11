local ADDON_NAME, addonTable = ...
local YUI = _G.YUI
if not (YUI and YUI.Components) then
    YUI = addonTable
end
if not YUI or not YUI.Components then return end

local Components = YUI.Components
local Assets = YUI.Assets
local GUI2 = YUI.GUI2
local Animation = YUI.Animation
local L = YUI.Locale and YUI.Locale:Get("CombatCue") or nil
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local FEATURE_KEY = "CombatCue"
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or YUI.ProductId or "suite"
local CONFIG_KEY = "CombatCue_Config"
local WIDTH, HEIGHT = 360, 200
local FIELD_WIDTH = 320
local FIELD_GAP = 18
local LABEL_WIDTH = 105
local CONTROL_GAP = 0
local CONTROL_WIDTH = FIELD_WIDTH - LABEL_WIDTH - CONTROL_GAP
local SLIDER_VALUE_WIDTH = 50
local SECTION_WIDTH = FIELD_WIDTH * 2 + FIELD_GAP
local TEXT_FONT_FLAGS = "OUTLINE"
local TEXT_FONT_BASE_SIZE = 64
local TEXT_FONT_MIN_SIZE = 14
local TEXT_FONT_MAX_SIZE = 108

local defaults = {
    startImage = "default",
    endImage = "default",
    animation = "float",
    positionPreset = "upper",
    offsetX = 0,
    offsetY = 0,
    scale = 50,
    maxAlpha = 75,
    startSound = "None",
    endSound = "None",
    soundChannel = "SFX",
}

local Feature = {
    id = FEATURE_KEY,
    name = L and L["name"] or "战斗提示",
    description = L and L["description"] or "进入或离开战斗时，在屏幕中央显示标题图片，并可配置动画和音效。",
    default = true,
    settingsMode = "inline",
    product = PRODUCT_ID,
    storageKey = FEATURE_KEY,
    tags = { "战斗辅助" },
    sourceRoot = "Components\\CombatCue",
    assetFolders = { "Components\\CombatCue\\Media" },
    versions = { "forever", "mainline", "mists", "wrath" },
    modSwitchImage = "modswitch\\combatcue-bg.png",
    modSwitchImageCrop = false,
}

local EventOwner = {}
local ConflictOwner = {}
local isHooked = false
local cueFrame
local conflictPrints = {}
local imagePathLogged = false

local VALID_ANIMATIONS = {
    float = true,
    fade = true,
    pop = true,
    slide = true,
}

local ANIMATION_OPTIONS = {
    { textKey = "animation.float", value = "float", fallback = "飘入飘出" },
    { textKey = "animation.fade", value = "fade", fallback = "淡入淡出" },
    { textKey = "animation.pop", value = "pop", fallback = "弹出" },
    { textKey = "animation.slide", value = "slide", fallback = "横向滑动" },
}

local POSITION_PRESETS = {
    center = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 40 },
    upper = { point = "TOP", relativePoint = "TOP", x = 0, y = -220 },
    lower = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 220 },
}

local POSITION_OPTIONS = {
    { textKey = "position.center", value = "center", fallback = "屏幕中央" },
    { textKey = "position.upper", value = "upper", fallback = "上方居中" },
    { textKey = "position.lower", value = "lower", fallback = "下方居中" },
}

local ANIMATION_PROFILES = {
    float = { inDuration = 0.22, hold = 0.72, outDuration = 0.28, distance = 42 },
    fade = { inDuration = 0.18, hold = 0.78, outDuration = 0.22, distance = 0 },
    pop = { inDuration = 0.24, hold = 0.72, outDuration = 0.20, distance = 0 },
    slide = { inDuration = 0.24, hold = 0.70, outDuration = 0.26, distance = 54 },
}

local TEXT_CUE_COLORS = {
    start = { 0.72, 0.24, 0.21, 1 },
    ["end"] = { 0.34, 0.62, 0.38, 1 },
}

local IMAGE_SETS = {
    start = {
        text = {
            labelKey = "image.text",
            fallback = "文字",
            textKey = "cue.start_text",
            textFallback = "进入战斗",
            color = TEXT_CUE_COLORS.start,
        },
        default = {
            labelKey = "image.esports",
            fallback = "电竞",
            texture = "images\\battle-start-title-360x200.png",
        },
        comic = {
            labelKey = "image.comic",
            fallback = "美漫",
            texture = "images\\combat-comic-start-360x200.png",
        },
        rock = {
            labelKey = "image.rock",
            fallback = "摇滚",
            texture = "images\\combat-rock-start-360x200.png",
        },
        ink = {
            labelKey = "image.ink",
            fallback = "水墨",
            texture = "images\\combat-ink-start-360x200.png",
        },
    },
    ["end"] = {
        text = {
            labelKey = "image.text",
            fallback = "文字",
            textKey = "cue.end_text",
            textFallback = "离开战斗",
            color = TEXT_CUE_COLORS["end"],
        },
        default = {
            labelKey = "image.esports",
            fallback = "电竞",
            texture = "images\\battle-end-title-360x200.png",
        },
        comic = {
            labelKey = "image.comic",
            fallback = "美漫",
            texture = "images\\combat-comic-leave-360x200.png",
        },
        rock = {
            labelKey = "image.rock",
            fallback = "摇滚",
            texture = "images\\combat-rock-leave-360x200.png",
        },
        ink = {
            labelKey = "image.ink",
            fallback = "水墨",
            texture = "images\\combat-ink-leave-360x200.png",
        },
    },
}

local IMAGE_ORDER = { "text", "default", "comic", "rock", "ink" }

local SOUND_CHANNEL_OPTIONS = {
    { textKey = "channel.master", value = "Master", fallback = "主声道" },
    { textKey = "channel.sfx", value = "SFX", fallback = "音效" },
    { textKey = "channel.music", value = "Music", fallback = "音乐" },
    { textKey = "channel.ambience", value = "Ambience", fallback = "环境" },
    { textKey = "channel.dialog", value = "Dialog", fallback = "对话" },
}

local VALID_SOUND_CHANNELS = {
    Master = true,
    SFX = true,
    Music = true,
    Ambience = true,
    Dialog = true,
}

local function T(key, fallback)
    if L and L[key] then
        return L[key]
    end
    return fallback or key
end

local function DebugConflict(message)
    if YUI and type(YUI.Debug) == "function" then
        pcall(YUI.Debug, YUI, "Components | CombatCue | " .. tostring(message))
    end
end

local function SafeCall(label, func, ...)
    if type(func) ~= "function" then
        return false
    end

    local ok, result1, result2, result3 = pcall(func, ...)
    if not ok then
        DebugConflict(tostring(label or "third-party call") .. " failed: " .. tostring(result1))
        return false
    end
    return true, result1, result2, result3
end

local function SafeIsAddOnLoaded(addonName)
    if type(addonName) ~= "string" or addonName == "" then
        return false
    end

    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        local ok, loaded = SafeCall("C_AddOns.IsAddOnLoaded:" .. addonName, C_AddOns.IsAddOnLoaded, addonName)
        return ok and loaded == true
    end
    if type(IsAddOnLoaded) == "function" then
        local ok, loaded = SafeCall("IsAddOnLoaded:" .. addonName, IsAddOnLoaded, addonName)
        return ok and loaded == true
    end
    return false
end

local function PrintConflictDisabledOnce(addonName)
    if conflictPrints[addonName] then
        return
    end
    conflictPrints[addonName] = true

    local template = T("conflict.disabled", "已为您禁用冲突的战斗提醒功能【%s】。")
    local message = string.format(template, addonName)
    if YUI and type(YUI.Print) == "function" then
        pcall(YUI.Print, YUI, message)
    else
        print(message)
    end
end

local function Asset(path)
    if Assets and Assets.Component then
        return Assets:Component(FEATURE_KEY, path)
    end
    return path
end

local function DebugImagePathOnce(kind, imageKey, texturePath)
    if imagePathLogged or not texturePath then
        return
    end
    imagePathLogged = true
    DebugConflict(string.format(
        "image texture kind=%s image=%s path=%s addon=%s product=%s",
        tostring(kind),
        tostring(imageKey),
        tostring(texturePath),
        tostring(YUI and YUI.AddonName),
        tostring(PRODUCT_ID)
    ))
end

local function ClampNumber(value, minValue, maxValue, fallback)
    value = tonumber(value)
    if not value then
        return fallback
    end
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local LEGACY_SOUND_VALUES = {
    none = true,
    raidWarning = true,
    countdown = true,
    menuOpen = true,
    menuClose = true,
    checkboxOn = true,
    checkboxOff = true,
    RAID_WARNING = true,
    UI_BATTLEGROUND_COUNTDOWN_TIMER = true,
    IG_MAINMENU_OPEN = true,
    IG_MAINMENU_CLOSE = true,
    IG_MAINMENU_OPTION_CHECKBOX_ON = true,
    IG_MAINMENU_OPTION_CHECKBOX_OFF = true,
    [850] = true,
    [851] = true,
    [856] = true,
    [857] = true,
    [8959] = true,
    [25477] = true,
}

local function IsValidSharedMediaSound(value)
    if not LSM or not LSM.Fetch or type(value) ~= "string" or value == "" then
        return false
    end
    return LSM:Fetch("sound", value, true) ~= nil
end

local function NormalizeSoundValue(value)
    if value == nil or value == "" or value == "None" or LEGACY_SOUND_VALUES[value] then
        return "None"
    end
    if IsValidSharedMediaSound(value) then
        return value
    end
    return "None"
end

local function NormalizeDB(db)
    db = db or defaults

    if not (IMAGE_SETS.start and IMAGE_SETS.start[db.startImage]) then
        db.startImage = defaults.startImage
    end
    if not (IMAGE_SETS["end"] and IMAGE_SETS["end"][db.endImage]) then
        db.endImage = defaults.endImage
    end
    if not VALID_ANIMATIONS[db.animation] then
        db.animation = defaults.animation
    end
    if not POSITION_PRESETS[db.positionPreset] then
        db.positionPreset = defaults.positionPreset
    end
    db.offsetX = ClampNumber(db.offsetX, -400, 400, defaults.offsetX)
    db.offsetY = ClampNumber(db.offsetY, -300, 300, defaults.offsetY)
    db.scale = ClampNumber(db.scale, 20, 180, defaults.scale)
    db.maxAlpha = ClampNumber(db.maxAlpha, 20, 100, defaults.maxAlpha)
    db.startSound = NormalizeSoundValue(db.startSound)
    db.endSound = NormalizeSoundValue(db.endSound)
    if not VALID_SOUND_CHANNELS[db.soundChannel] then
        db.soundChannel = defaults.soundChannel
    end

    return db
end

local function GetDB()
    if Components and Components.EnsureConfig then
        return NormalizeDB(Components:EnsureConfig(CONFIG_KEY, defaults, PRODUCT_ID) or defaults)
    end
    return NormalizeDB(defaults)
end

local function GetMaxAlpha(db)
    db = db or GetDB()
    return ClampNumber(db.maxAlpha, 20, 100, defaults.maxAlpha) / 100
end

local function GetImageOptions(kind)
    local options = {}
    local source = IMAGE_SETS[kind] or IMAGE_SETS.start
    for _, value in ipairs(IMAGE_ORDER) do
        local item = source[value]
        if item then
            options[#options + 1] = {
                text = T(item.labelKey, item.fallback),
                value = value,
            }
        end
    end
    return options
end

local function GetAnimationOptions()
    local options = {}
    for _, item in ipairs(ANIMATION_OPTIONS) do
        options[#options + 1] = {
            text = T(item.textKey, item.fallback),
            value = item.value,
        }
    end
    return options
end

local function GetPositionOptions()
    local options = {}
    for _, item in ipairs(POSITION_OPTIONS) do
        options[#options + 1] = {
            text = T(item.textKey, item.fallback),
            value = item.value,
        }
    end
    return options
end

local function GetSoundChannelOptions()
    local options = {}
    for _, item in ipairs(SOUND_CHANNEL_OPTIONS) do
        options[#options + 1] = {
            text = T(item.textKey, item.fallback),
            value = item.value,
        }
    end
    return options
end

local function ResolveVisual(kind, value)
    local source = IMAGE_SETS[kind] or IMAGE_SETS.start
    return source[value] or source.default
end

local function ResolveImage(kind, value)
    local image = ResolveVisual(kind, value)
    if not image or not image.texture then
        return nil
    end
    return Asset(image.texture)
end

local function PlayConfiguredSound(kind, db)
    if type(PlaySoundFile) ~= "function" or not LSM or not LSM.Fetch then
        return
    end

    local value = kind == "start" and db.startSound or db.endSound
    if value == "None" then
        return
    end

    local path = LSM:Fetch("sound", value, true)
    if not path or path == 1 then
        return
    end

    local channel = VALID_SOUND_CHANNELS[db.soundChannel] and db.soundChannel or defaults.soundChannel
    pcall(PlaySoundFile, path, channel)
end

local function DisableWindToolsCombatAlert()
    if not SafeIsAddOnLoaded("ElvUI_WindTools") and type(_G.WindTools) ~= "table" then
        return false
    end

    local ok, changed = SafeCall("Disable WindTools CombatAlert", function()
        local windTools = _G.WindTools
        local E = type(windTools) == "table" and windTools[3] or nil
        if not E and type(_G.ElvUI) == "table" then
            E = _G.ElvUI[1]
        end

        local combatAlert = E and E.db and E.db.WT and E.db.WT.combat and E.db.WT.combat.combatAlert
        if type(combatAlert) ~= "table" or combatAlert.enable ~= true then
            return false
        end

        combatAlert.enable = false

        local W = type(windTools) == "table" and windTools[1] or nil
        local module
        local moduleOk, moduleResult = SafeCall("WindTools:GetModule(CombatAlert)", function()
            if W and type(W.GetModule) == "function" then
                return W:GetModule("CombatAlert", true)
            end
        end)
        if moduleOk then
            module = moduleResult
        end
        if module and type(module.ProfileUpdate) == "function" then
            SafeCall("WindTools CombatAlert:ProfileUpdate", module.ProfileUpdate, module)
        end

        return true
    end)

    return ok and changed == true
end

local function GetNDuiCurrentProfileDB()
    local ns = _G.NDui
    local config = type(ns) == "table" and ns[2] or nil
    if type(config) == "table" and type(config.db) == "table" then
        return config.db
    end

    local accountDB = _G.NDuiADB
    local profileIndex = type(accountDB) == "table" and accountDB.ProfileIndex or nil
    local profileDBs = _G.NDuiPDB
    if type(profileIndex) == "table" and type(profileDBs) == "table" then
        local okName, playerName = SafeCall("NDui UnitName", UnitName, "player")
        local okRealm, realmName = SafeCall("NDui GetRealmName", GetRealmName)
        local fullName = okName and okRealm and playerName and realmName and (playerName .. "-" .. realmName) or nil
        local index = tonumber(fullName and profileIndex[fullName])
        if index and index > 1 and type(profileDBs[index - 1]) == "table" then
            return profileDBs[index - 1]
        end
    end

    if type(_G.NDuiDB) == "table" then
        return _G.NDuiDB
    end
    return nil
end

local function DisableNDuiCombatAnimation()
    if not SafeIsAddOnLoaded("NDui") and type(_G.NDui) ~= "table" then
        return false
    end

    local ok, changed = SafeCall("Disable NDui CombatAnimation", function()
        local profileDB = GetNDuiCurrentProfileDB()
        if type(profileDB) ~= "table" then
            return false
        end
        if type(profileDB.Misc) ~= "table" then
            profileDB.Misc = {}
        end
        if profileDB.Misc.CombatAnimation == false then
            return false
        end

        profileDB.Misc.CombatAnimation = false
        return true
    end)

    return ok and changed == true
end

local function DisableEnhanceQoLCombatText()
    if not SafeIsAddOnLoaded("EnhanceQoL") and type(_G.EnhanceQoL) ~= "table" then
        return false
    end

    local ok, changed = SafeCall("Disable EnhanceQoL CombatText", function()
        local addon = _G.EnhanceQoL
        if type(addon) ~= "table" or type(addon.db) ~= "table" then
            return false
        end
        if addon.db.combatTextEnabled ~= true then
            return false
        end

        addon.db.combatTextEnabled = false
        if addon.CombatText and type(addon.CombatText.OnSettingChanged) == "function" then
            SafeCall("EnhanceQoL CombatText:OnSettingChanged", addon.CombatText.OnSettingChanged, addon.CombatText, false)
        end
        return true
    end)

    return ok and changed == true
end

local function DisableConflictingCombatAlerts()
    local conflicts = {
        { name = "ElvUI WindTools", disable = DisableWindToolsCombatAlert },
        { name = "NDui", disable = DisableNDuiCombatAnimation },
        { name = "EnhanceQoL", disable = DisableEnhanceQoLCombatText },
    }

    for _, conflict in ipairs(conflicts) do
        local ok, changed = SafeCall("CombatCue conflict disable:" .. conflict.name, conflict.disable)
        if ok and changed == true then
            PrintConflictDisabledOnce(conflict.name)
        end
    end
end

local function GetDefaultTextFont()
    if GameFontNormalHuge and GameFontNormalHuge.GetFont then
        local font = GameFontNormalHuge:GetFont()
        if font then
            return font
        end
    end
    if GameFontNormal and GameFontNormal.GetFont then
        local font = GameFontNormal:GetFont()
        if font then
            return font
        end
    end
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

local function ApplyTextCueFont(frame, db)
    if not frame or not frame.text then
        return
    end

    db = db or GetDB()
    local scale = ClampNumber(db.scale, 20, 180, defaults.scale) / 100
    local fontSize = math.floor(TEXT_FONT_BASE_SIZE * scale + 0.5)
    fontSize = ClampNumber(fontSize, TEXT_FONT_MIN_SIZE, TEXT_FONT_MAX_SIZE, TEXT_FONT_BASE_SIZE)
    frame.text:SetFont(GetDefaultTextFont(), fontSize, TEXT_FONT_FLAGS)
end

local function ApplyCueVisual(frame, visual, texturePath, db)
    if visual and visual.textKey then
        if frame.texture then
            frame.texture:SetTexture(nil)
            frame.texture:Hide()
        end
        if frame.text then
            local color = visual.color or TEXT_CUE_COLORS.start
            frame.text:SetText(T(visual.textKey, visual.textFallback))
            frame.text:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] == nil and 1 or color[4])
            ApplyTextCueFont(frame, db)
            frame.text:Show()
        end
        return
    end

    if frame.text then
        frame.text:SetText("")
        frame.text:Hide()
    end
    if frame.texture then
        if texturePath then
            frame.texture:SetTexture(texturePath)
            frame.texture:Show()
        else
            frame.texture:SetTexture(nil)
            frame.texture:Hide()
        end
    end
end

local function EnsureFrame()
    if cueFrame then
        return cueFrame
    end

    if GUI2 and GUI2.CreateFrame then
        cueFrame = GUI2:CreateFrame(UIParent, {
            name = "YUI_CombatCueFrame",
            width = WIDTH,
            height = HEIGHT,
            strata = "FULLSCREEN_DIALOG",
            level = 500,
            hidden = true,
            mouse = false,
        })
    else
        cueFrame = CreateFrame("Frame", "YUI_CombatCueFrame", UIParent)
        cueFrame:SetSize(WIDTH, HEIGHT)
        cueFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        cueFrame:SetFrameLevel(500)
        cueFrame:EnableMouse(false)
        cueFrame:Hide()
    end

    if cueFrame.SetFrameStrata then
        cueFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    end
    if cueFrame.SetFrameLevel then
        cueFrame:SetFrameLevel(500)
    end
    cueFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)

    if GUI2 and GUI2.CreateTexture then
        cueFrame.texture = GUI2:CreateTexture(cueFrame, { layer = "ARTWORK" })
    else
        cueFrame.texture = cueFrame:CreateTexture(nil, "ARTWORK")
    end
    cueFrame.texture:SetAllPoints(cueFrame)
    cueFrame.texture:SetBlendMode("BLEND")

    cueFrame.text = cueFrame:CreateFontString(nil, "OVERLAY")
    cueFrame.text:SetAllPoints(cueFrame)
    cueFrame.text:SetJustifyH("CENTER")
    if cueFrame.text.SetJustifyV then
        cueFrame.text:SetJustifyV("MIDDLE")
    end
    if cueFrame.text.SetWordWrap then
        cueFrame.text:SetWordWrap(false)
    end
    cueFrame.text:SetShadowColor(0, 0, 0, 0.82)
    cueFrame.text:SetShadowOffset(2, -2)
    cueFrame.text:Hide()

    return cueFrame
end

local function ApplyFrameLayout(frame, db)
    db = db or GetDB()
    local preset = POSITION_PRESETS[db.positionPreset] or POSITION_PRESETS.center
    local scale = ClampNumber(db.scale, 20, 180, defaults.scale) / 100

    frame:ClearAllPoints()
    frame:SetPoint(
        preset.point,
        UIParent,
        preset.relativePoint,
        (preset.x or 0) + (db.offsetX or 0),
        (preset.y or 0) + (db.offsetY or 0)
    )
    frame:SetSize(math.floor(WIDTH * scale + 0.5), math.floor(HEIGHT * scale + 0.5))
    frame:SetScale(1)
    ApplyTextCueFont(frame, db)
end

local function ResetFrame(frame, db)
    ApplyFrameLayout(frame, db)
    frame:SetAlpha(GetMaxAlpha(db))
end

local function RefreshVisibleCueLayout()
    if cueFrame and cueFrame.IsShown and cueFrame:IsShown() then
        ApplyFrameLayout(cueFrame, GetDB())
    end
end

local function RefreshVisibleCueAlpha()
    if cueFrame and cueFrame.IsShown and cueFrame:IsShown() then
        cueFrame:SetAlpha(GetMaxAlpha(GetDB()))
    end
end

local function Schedule(delay, callback)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0, callback)
    else
        callback()
    end
end

local function CancelActiveCue(hideFrame)
    Feature.sequence = (Feature.sequence or 0) + 1
    if Animation and Animation.StopOwner then
        Animation:StopOwner(Feature, false)
    end
    if hideFrame ~= false and cueFrame and cueFrame.Hide then
        cueFrame:Hide()
    end
    return Feature.sequence
end

local function PlayOut(frame, mode, profile, serial, maxAlpha)
    if Feature.sequence ~= serial or not frame then
        return
    end
    maxAlpha = maxAlpha or 1

    if not Animation then
        frame:Hide()
        return
    end

    if mode == "fade" or mode == "pop" then
        if Animation.FadeOut then
            Animation:FadeOut(frame, {
                owner = Feature,
                key = "combatcue-out",
                duration = profile.outDuration,
                easing = "sineIn",
                from = maxAlpha,
                to = 0,
                hide = true,
            })
        else
            frame:Hide()
        end
    elseif mode == "slide" then
        if Animation.SlideOut then
            Animation:SlideOut(frame, {
                owner = Feature,
                key = "combatcue-out",
                to = "right",
                distance = profile.distance,
                duration = profile.outDuration,
                easing = "sineIn",
                fromAlpha = maxAlpha,
                toAlpha = 0,
                hide = true,
            })
        else
            frame:Hide()
        end
    elseif Animation.SlideOut then
        Animation:SlideOut(frame, {
            owner = Feature,
            key = "combatcue-out",
            to = "up",
            distance = profile.distance,
            duration = profile.outDuration,
            easing = "sineIn",
            fromAlpha = maxAlpha,
            toAlpha = 0,
            hide = true,
        })
    else
        frame:Hide()
    end
end

local function PlayIn(frame, mode, profile, maxAlpha)
    maxAlpha = maxAlpha or 1
    if not Animation then
        frame:Show()
        frame:SetAlpha(maxAlpha)
        return
    end

    if mode == "fade" then
        if Animation.FadeIn then
            Animation:FadeIn(frame, {
                owner = Feature,
                key = "combatcue-in",
                duration = profile.inDuration,
                easing = "sineOut",
                from = 0,
                to = maxAlpha,
            })
        else
            frame:Show()
            frame:SetAlpha(maxAlpha)
        end
    elseif mode == "pop" then
        if Animation.Pop then
            Animation:Pop(frame, {
                owner = Feature,
                key = "combatcue-in",
                duration = profile.inDuration,
                easing = "outBack",
                fromAlpha = 0,
                toAlpha = maxAlpha,
                fromScale = 0.84,
                toScale = 1,
            })
        else
            frame:Show()
            frame:SetAlpha(maxAlpha)
        end
    elseif mode == "slide" then
        if Animation.SlideIn then
            Animation:SlideIn(frame, {
                owner = Feature,
                key = "combatcue-in",
                from = "left",
                distance = profile.distance,
                duration = profile.inDuration,
                easing = "sineOut",
                fromAlpha = 0,
                toAlpha = maxAlpha,
            })
        else
            frame:Show()
            frame:SetAlpha(maxAlpha)
        end
    elseif Animation.SlideIn then
        Animation:SlideIn(frame, {
            owner = Feature,
            key = "combatcue-in",
            from = "bottom",
            distance = profile.distance,
            duration = profile.inDuration,
            easing = "sineOut",
            fromAlpha = 0,
            toAlpha = maxAlpha,
        })
    else
        frame:Show()
        frame:SetAlpha(maxAlpha)
    end
end

local function PlayCue(kind, isPreview)
    local db = GetDB()
    local mode = VALID_ANIMATIONS[db.animation] and db.animation or defaults.animation
    local profile = ANIMATION_PROFILES[mode] or ANIMATION_PROFILES.float
    local serial = CancelActiveCue(true)
    local frame = EnsureFrame()
    local imageKey = kind == "start" and db.startImage or db.endImage
    local visual = ResolveVisual(kind, imageKey)
    local texturePath = ResolveImage(kind, imageKey)
    local maxAlpha = GetMaxAlpha(db)

    Feature.previewActive = isPreview == true
    if Feature.previewActive and visual and visual.texture then
        DebugImagePathOnce(kind, imageKey, texturePath)
    end
    ResetFrame(frame, db)
    ApplyCueVisual(frame, visual, texturePath, db)
    frame:Show()

    PlayConfiguredSound(kind, db)
    PlayIn(frame, mode, profile, maxAlpha)

    Schedule((profile.inDuration or 0) + (profile.hold or 0.7), function()
        PlayOut(frame, mode, profile, serial, maxAlpha)
    end)
end

local function OnCombatEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then
        PlayCue("start", false)
    elseif event == "PLAYER_REGEN_ENABLED" then
        PlayCue("end", false)
    end
end

local function ToggleCombatCue(enable)
    if enable then
        DisableConflictingCombatAlerts()
        if not isHooked and YUI.Event then
            YUI.Event:On("PLAYER_REGEN_DISABLED", OnCombatEvent, EventOwner, {
                traceName = "CombatCue:combat-start",
                moduleId = "component:" .. FEATURE_KEY,
            })
            YUI.Event:On("PLAYER_REGEN_ENABLED", OnCombatEvent, EventOwner, {
                traceName = "CombatCue:combat-end",
                moduleId = "component:" .. FEATURE_KEY,
            })
            isHooked = true
        end
    else
        if isHooked and YUI.Event then
            YUI.Event:OffOwner(EventOwner)
        end
        isHooked = false
        Feature.previewActive = false
        CancelActiveCue(true)
    end
end

local function OnSettingsLeave()
    if Feature.previewActive then
        CancelActiveCue(true)
    end
    Feature.previewActive = false
end

local function GetOptions()
    local db = GetDB()

    return {
        {
            type = "row",
            gap = 10,
            children = {
                {
                    type = "button",
                    label = T("settings.preview_start", "预览进入战斗"),
                    width = 150,
                    onClick = function()
                        PlayCue("start", true)
                    end,
                },
                {
                    type = "button",
                    label = T("settings.preview_end", "预览离开战斗"),
                    width = 150,
                    onClick = function()
                        PlayCue("end", true)
                    end,
                },
            },
        },
        { type = "space", height = 8 },
        { type = "divider", label = T("settings.visual", "视觉"), alignLeft = true, width = SECTION_WIDTH },
        {
            type = "row",
            gap = FIELD_GAP,
            children = {
                {
                    type = "dropdown",
                    label = T("settings.start_image", "进入战斗图片"),
                    inlineLabel = true,
                    width = FIELD_WIDTH,
                    labelWidth = LABEL_WIDTH,
                    gap = CONTROL_GAP,
                    controlWidth = CONTROL_WIDTH,
                    options = GetImageOptions("start"),
                    default = defaults.startImage,
                    get = function() return db.startImage end,
                    set = function(value)
                        db.startImage = IMAGE_SETS.start[value] and value or defaults.startImage
                        PlayCue("start", true)
                    end,
                },
                {
                    type = "dropdown",
                    label = T("settings.end_image", "离开战斗图片"),
                    inlineLabel = true,
                    width = FIELD_WIDTH,
                    labelWidth = LABEL_WIDTH,
                    gap = CONTROL_GAP,
                    controlWidth = CONTROL_WIDTH,
                    options = GetImageOptions("end"),
                    default = defaults.endImage,
                    get = function() return db.endImage end,
                    set = function(value)
                        db.endImage = IMAGE_SETS["end"][value] and value or defaults.endImage
                        PlayCue("end", true)
                    end,
                },
            },
        },
        {
            type = "row",
            gap = FIELD_GAP,
            children = {
                {
                    type = "dropdown",
                    label = T("settings.animation", "动画方式"),
                    inlineLabel = true,
                    width = FIELD_WIDTH,
                    labelWidth = LABEL_WIDTH,
                    gap = CONTROL_GAP,
                    controlWidth = CONTROL_WIDTH,
                    options = GetAnimationOptions(),
                    default = defaults.animation,
                    get = function() return db.animation end,
                    set = function(value)
                        db.animation = VALID_ANIMATIONS[value] and value or defaults.animation
                    end,
                },
                {
                    type = "dropdown",
                    label = T("settings.position_preset", "出现位置"),
                    inlineLabel = true,
                    width = FIELD_WIDTH,
                    labelWidth = LABEL_WIDTH,
                    gap = CONTROL_GAP,
                    controlWidth = CONTROL_WIDTH,
                    options = GetPositionOptions(),
                    default = defaults.positionPreset,
                    get = function() return db.positionPreset end,
                    set = function(value)
                        db.positionPreset = POSITION_PRESETS[value] and value or defaults.positionPreset
                        RefreshVisibleCueLayout()
                    end,
                },
            },
        },
        {
            type = "row",
            gap = FIELD_GAP,
            children = {
                {
                    type = "slider",
                    label = T("settings.offset_x", "水平偏移"),
                    inline = true,
                    width = FIELD_WIDTH,
                    labelWidth = LABEL_WIDTH,
                    inputWidth = SLIDER_VALUE_WIDTH,
                    min = -400,
                    max = 400,
                    step = 1,
                    get = function() return db.offsetX end,
                    set = function(value)
                        db.offsetX = ClampNumber(value, -400, 400, defaults.offsetX)
                        RefreshVisibleCueLayout()
                    end,
                },
                {
                    type = "slider",
                    label = T("settings.offset_y", "垂直偏移"),
                    inline = true,
                    width = FIELD_WIDTH,
                    labelWidth = LABEL_WIDTH,
                    inputWidth = SLIDER_VALUE_WIDTH,
                    min = -300,
                    max = 300,
                    step = 1,
                    get = function() return db.offsetY end,
                    set = function(value)
                        db.offsetY = ClampNumber(value, -300, 300, defaults.offsetY)
                        RefreshVisibleCueLayout()
                    end,
                },
            },
        },
        {
            type = "row",
            gap = FIELD_GAP,
            children = {
                {
                    type = "slider",
                    label = T("settings.scale", "图片尺寸"),
                    inline = true,
                    width = FIELD_WIDTH,
                    labelWidth = LABEL_WIDTH,
                    inputWidth = SLIDER_VALUE_WIDTH,
                    min = 20,
                    max = 180,
                    step = 1,
                    get = function() return db.scale end,
                    set = function(value)
                        db.scale = ClampNumber(value, 20, 180, defaults.scale)
                        RefreshVisibleCueLayout()
                    end,
                },
                {
                    type = "slider",
                    label = T("settings.max_alpha", "最大透明度"),
                    inline = true,
                    width = FIELD_WIDTH,
                    labelWidth = LABEL_WIDTH,
                    inputWidth = SLIDER_VALUE_WIDTH,
                    min = 20,
                    max = 100,
                    step = 1,
                    get = function() return db.maxAlpha end,
                    set = function(value)
                        db.maxAlpha = ClampNumber(value, 20, 100, defaults.maxAlpha)
                        RefreshVisibleCueAlpha()
                    end,
                },
            },
        },
        { type = "space", height = 8 },
        { type = "divider", label = T("settings.sound", "音效"), alignLeft = true, width = SECTION_WIDTH },
        {
            type = "row",
            gap = FIELD_GAP,
            children = {
                {
                    type = "sound",
                    label = T("settings.start_sound", "进入战斗音效"),
                    inlineLabel = true,
                    width = FIELD_WIDTH,
                    labelWidth = LABEL_WIDTH,
                    gap = CONTROL_GAP,
                    controlWidth = CONTROL_WIDTH,
                    default = defaults.startSound,
                    get = function() return db.startSound end,
                    set = function(value)
                        db.startSound = NormalizeSoundValue(value)
                        PlayConfiguredSound("start", db)
                    end,
                },
                {
                    type = "sound",
                    label = T("settings.end_sound", "离开战斗音效"),
                    inlineLabel = true,
                    width = FIELD_WIDTH,
                    labelWidth = LABEL_WIDTH,
                    gap = CONTROL_GAP,
                    controlWidth = CONTROL_WIDTH,
                    default = defaults.endSound,
                    get = function() return db.endSound end,
                    set = function(value)
                        db.endSound = NormalizeSoundValue(value)
                        PlayConfiguredSound("end", db)
                    end,
                },
            },
        },
        {
            type = "row",
            gap = FIELD_GAP,
            children = {
                {
                    type = "dropdown",
                    label = T("settings.sound_channel", "音效声道"),
                    inlineLabel = true,
                    width = FIELD_WIDTH,
                    labelWidth = LABEL_WIDTH,
                    gap = CONTROL_GAP,
                    controlWidth = CONTROL_WIDTH,
                    options = GetSoundChannelOptions(),
                    default = defaults.soundChannel,
                    get = function() return db.soundChannel end,
                    set = function(value)
                        db.soundChannel = VALID_SOUND_CHANNELS[value] and value or defaults.soundChannel
                    end,
                },
            },
        },
    }
end

Feature.callback = ToggleCombatCue
Feature.OnSettingsLeave = OnSettingsLeave
Feature.GetOptions = GetOptions
Feature.PlayCue = PlayCue

Components:RegisterFeature(FEATURE_KEY, Feature)

local function DisableConflictsIfEnabled()
    if Components and Components.IsEnabled and Components:IsEnabled(FEATURE_KEY) then
        DisableConflictingCombatAlerts()
    end
end

if YUI.Lifecycle and YUI.Lifecycle.IsReady and YUI.Lifecycle:IsReady("YUI_DB_READY") then
    DisableConflictsIfEnabled()
elseif YUI.Event and YUI.Event.Once then
    YUI.Event:Once("YUI_DB_READY", function()
        DisableConflictsIfEnabled()
    end, ConflictOwner, {
        traceName = "CombatCue:disable-conflicts-db-ready",
        moduleId = "component:" .. FEATURE_KEY,
        phase = "YUI_DB_READY",
    })
end
