local ADDON_NAME, YUI = ...
YUI = YUI or _G.YUI
if not YUI then return end

local Assets = YUI.Assets
local UnitAPI = YUI.API and YUI.API.Unit or YUI.WOW_API or {}
local Appearance = YUI.Appearance or {}
YUI.Appearance = Appearance

local DEFAULTS = {
    elvUI = false,
    eqolUnitFrames = false,
    ndui = false,
    nduiUnitFrameTextShadow = true,
    eqolPowerBorder = false,
    shadow = true,
    noise = true,
    lightMode = false,
}

local LEGACY_KEYS = {
    elvUI = "YUISkins",
    eqolUnitFrames = "YUISkins_EQoL",
    eqolPowerBorder = "YUISkins_EQoLPowerBorder",
    shadow = "YUISkins_Shadow",
    noise = "YUISkins_Noise",
    lightMode = "YUISkins_LightMode",
}

local function GetProfile()
    if YUI.DB and YUI.DB.GetProfile then
        local profile = YUI.DB:GetProfile(YUI.ProductId or "suite")
        if type(profile) == "table" then
            return profile
        end
    end
    return nil
end

local function EnsureDB()
    local profile = GetProfile()
    if type(profile) ~= "table" then
        return nil
    end

    if type(profile.Appearance) ~= "table" then
        profile.Appearance = {}
    end
    local appearance = profile.Appearance
    if type(appearance.skins) ~= "table" then
        appearance.skins = {}
    end

    local skins = appearance.skins
    local legacy = type(profile.Components) == "table" and profile.Components or nil
    local hadNDuiOption = skins.ndui ~= nil
    local hadNDuiTextShadowOption = skins.nduiUnitFrameTextShadow ~= nil
    for key, default in pairs(DEFAULTS) do
        if skins[key] == nil then
            local legacyKey = LEGACY_KEYS[key]
            if legacy and legacy[legacyKey] ~= nil then
                skins[key] = legacy[legacyKey] == true
            else
                skins[key] = default
            end
        end
    end

    if not hadNDuiOption and hadNDuiTextShadowOption and skins.nduiUnitFrameTextShadow == true then
        skins.ndui = true
    end

    return skins
end

local function GetOption(key, default)
    local db = EnsureDB()
    if db and db[key] ~= nil then
        return db[key]
    end
    if default ~= nil then
        return default
    end
    return DEFAULTS[key]
end

local function EmitOptionChanged(key, value, previous)
    if previous == value then
        return
    end

    if YUI.Event and YUI.Event.Emit then
        YUI.Event:Emit("YUI_APPEARANCE_SKIN_OPTION_CHANGED", key, value, previous)
    elseif YUI.Fire then
        YUI:Fire("YUI_APPEARANCE_SKIN_OPTION_CHANGED", key, value, previous)
    end
end

local function SetOption(key, value)
    local db = EnsureDB()
    if not db then
        return false
    end
    local normalized = value == true
    local previous = db[key]
    db[key] = normalized
    EmitOptionChanged(key, normalized, previous)
    return true
end

local function IsEnabled(key)
    return GetOption(key, DEFAULTS[key]) == true
end

-- ==========================================
-- 材质定义 (Core)
-- ==========================================
local MEDIA = {
    Noise = Assets:Bundle("appearance-skins", "textures\\noise.blp"),
    Shadow = Assets:Bundle("appearance-skins", "textures\\shadow.blp"),
    Glow = Assets:Core("images\\GlowTex.tga"),
}

-- ==========================================
-- 核心渲染 API (Core)
-- 采用独立阴影层设计，避免直接修改原框架层级引发 Taint
-- ==========================================

-- 弱引用表，用于存储附加到原生框架的组件，避免直接修改原生框架对象导致 Taint
local shadowFrames = setmetatable({}, {__mode = "k"})
local innerNoises = setmetatable({}, {__mode = "k"})
local innerShadows = setmetatable({}, {__mode = "k"})
local skinnedFrames = setmetatable({}, {__mode = "k"})

local function FrameMethodBool(frame, method)
    if not frame then return false end
    local ok, func = pcall(function()
        return frame[method]
    end)
    if not ok or type(func) ~= "function" then return false end

    local callOk, value = pcall(func, frame)
    return callOk and value == true
end

local function FrameMethodValue(frame, method)
    if not frame then return nil end
    local ok, func = pcall(function()
        return frame[method]
    end)
    if not ok or type(func) ~= "function" then return nil end

    local callOk, value = pcall(func, frame)
    if callOk then return value end
    return nil
end

local function FrameMethodExists(frame, method)
    if not frame then return false end
    local ok, func = pcall(function()
        return frame[method]
    end)
    return ok and type(func) == "function"
end

local function IsObjectType(frame, objectType)
    if not frame then return false end
    local ok, isType = pcall(function()
        return frame.IsObjectType and frame:IsObjectType(objectType)
    end)
    return ok and isType == true
end

local function IsDescendantOrSelf(frame, root)
    if not frame or not root then return false end
    if frame == root then return true end

    if IsObjectType(frame, "Frame") and frame.IsDescendantOf then
        local ok, isDescendant = pcall(frame.IsDescendantOf, frame, root)
        if ok and isDescendant then return true end
    end

    local parent = FrameMethodValue(frame, "GetParent")
    local depth = 0
    while parent and depth < 30 do
        if parent == root then return true end
        parent = FrameMethodValue(parent, "GetParent")
        depth = depth + 1
    end

    return false
end

local function HasAncestorNameContaining(frame, text)
    local parent = frame
    local depth = 0
    while parent and depth < 30 do
        local name = FrameMethodValue(parent, "GetName")
        if name and name:find(text, 1, true) then return true end
        parent = FrameMethodValue(parent, "GetParent")
        depth = depth + 1
    end

    return false
end

local function ShouldSkipFrame(frame)
    if not frame then return true end
    if frame == _G.PlayerCastingBarFrame or frame == _G.OverlayPlayerCastingBarFrame then return true end
    if FrameMethodBool(frame, "IsForbidden") then return true end
    if FrameMethodBool(frame, "IsProtected") then return true end
    if IsObjectType(frame, "GameTooltip") then return true end
    if IsDescendantOrSelf(frame, _G.GameTooltip) then return true end
    if FrameMethodExists(frame, "RegisterForWidgetSet") or FrameMethodExists(frame, "UnregisterForWidgetSet") then return true end

    local name = FrameMethodValue(frame, "GetName")
    if name then
        if name:find("CastingBar", 1, true) then return true end
        if name:find("SpellBar", 1, true) then return true end
        if name:find("Tooltip", 1, true) then return true end
        if name:find("UIWidget", 1, true) then return true end
    end
    if HasAncestorNameContaining(frame, "UIWidget") then return true end

    return false
end

local function RefreshShadowLevel(frame)
    local shadowFrame = shadowFrames[frame]
    if frame and shadowFrame then
        local parentLevel = frame:GetFrameLevel()
        -- 确保阴影框架永远在父框架下方，但不能低于0
        shadowFrame:SetFrameLevel(parentLevel > 0 and parentLevel - 1 or 0)
    end
end

-- 创建一个独立的子框架作为所有美化材质的载体
local function GetOrCreateShadowFrame(frame)
    if shadowFrames[frame] then return shadowFrames[frame] end
    
    local shadowFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    shadowFrame.ignoreInLayout = true
    
    -- 基础层级设置
    shadowFrame:SetFrameStrata(frame:GetFrameStrata())
    local parentLevel = frame:GetFrameLevel()
    shadowFrame:SetFrameLevel(parentLevel > 0 and parentLevel - 1 or 0)
    
    -- 动态追踪父框架的层级变化
    pcall(hooksecurefunc, frame, "SetFrameStrata", function()
        local sf = shadowFrames[frame]
        if sf then
            sf:SetFrameStrata(frame:GetFrameStrata())
        end
    end)
    pcall(hooksecurefunc, frame, "SetFrameLevel", RefreshShadowLevel)
    
    shadowFrames[frame] = shadowFrame
    return shadowFrame
end

local function CreateSkinFrame(frame, shadowSize, shadowAlpha, onlyShadow, options)
    if not frame or skinnedFrames[frame] then return end
    if ShouldSkipFrame(frame) then return end
    
    -- 如果目标是 Texture，不能直接作为 Frame 的父级，需要找它的父级
    if frame:IsObjectType("Texture") then
        local parent = frame:GetParent()
        if not parent or not parent:IsObjectType("Frame") then return end
        if ShouldSkipFrame(parent) then return end
        frame = parent
    end
    if ShouldSkipFrame(frame) then return end

    shadowSize = shadowSize or 4
    shadowAlpha = shadowAlpha or 0.6
    
    local shadowFrame = GetOrCreateShadowFrame(frame)
    
    -- 1. 创建外阴影 (Soft Shadow)
    -- 通过 Backdrop 实现发光边缘
    local edgeSize = (options and options.edgeSize) or 1
    local offset = (options and options.offset) or ((shadowSize - edgeSize) or edgeSize)
    shadowFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", -offset, offset)
    shadowFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", offset, -offset)

    -- 执行外部传入的特殊回调 (如 ElvUI 的 Backdrop 坐标修复)
    if options and options.setupTextureCoordinates then
        local ok, err = pcall(options.setupTextureCoordinates, shadowFrame)
        if not ok and YUI.Debug then
            YUI:Debug("Appearance | skin setup callback failed: " .. tostring(err))
        end
    end

    local scaledShadowSize = shadowSize
    if options and options.scaleFunc then
        local ok, value = pcall(options.scaleFunc, shadowSize)
        if ok and type(value) == "number" then
            scaledShadowSize = value
        elseif not ok and YUI.Debug then
            YUI:Debug("Appearance | skin scale callback failed: " .. tostring(value))
        end
    end

    local useShadow
    if options and options.forceShadow ~= nil then
        useShadow = options.forceShadow == true
    else
        useShadow = GetOption("shadow", true) == true
    end
    local useNoise = GetOption("noise", true) == true

    if useShadow then
        shadowFrame:SetBackdrop({
            edgeFile = MEDIA.Glow,
            edgeSize = scaledShadowSize,
        })
        shadowFrame:SetBackdropColor(0, 0, 0, 0)
        shadowFrame:SetBackdropBorderColor(0, 0, 0, shadowAlpha)
        shadowFrame:Show()
    else
        shadowFrame:SetBackdrop(nil)
        shadowFrame:Hide()
    end
    
    if not onlyShadow then
        -- 2. 创建内颗粒 (Inner Noise)
        if useNoise then
            local innerNoise = innerNoises[frame]
            if not innerNoise then
                innerNoise = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
                innerNoise.ignoreInLayout = true
                innerNoise:SetPoint("TOPLEFT", frame, "TOPLEFT", edgeSize, -edgeSize)
                innerNoise:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -edgeSize, edgeSize)
                
                innerNoise:SetTexture(MEDIA.Noise, "REPEAT", "REPEAT")
                innerNoise:SetHorizTile(true)
                innerNoise:SetVertTile(true)
                innerNoise:SetBlendMode("ADD")
                innerNoise:SetVertexColor(1, 1, 1, 1)
                
                innerNoises[frame] = innerNoise
            end
            innerNoise:Show()
        elseif innerNoises[frame] then
            innerNoises[frame]:Hide()
        end
        
        -- 3. 创建内阴影 (Inner Shadow)
        if useShadow then
            local innerShadow = innerShadows[frame]
            if not innerShadow then
                innerShadow = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
                innerShadow.ignoreInLayout = true
                innerShadow:SetPoint("TOPLEFT", frame, "TOPLEFT", edgeSize, -edgeSize)
                innerShadow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -edgeSize, edgeSize)
                
                innerShadow:SetTexture(MEDIA.Shadow)
                innerShadow:SetVertexColor(1, 1, 1, 0.5)
                innerShadow:SetBlendMode("BLEND")
                
                innerShadows[frame] = innerShadow
            end
            innerShadow:Show()
        elseif innerShadows[frame] then
            innerShadows[frame]:Hide()
        end
    end

    skinnedFrames[frame] = true
end

local function IsSkinned(frame)
    return skinnedFrames[frame] or false
end

local lightModeClasses = {
    WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true,
    PRIEST = true, DEATHKNIGHT = true, SHAMAN = true, MAGE = true,
    WARLOCK = true, MONK = true, DRUID = true, DEMONHUNTER = true, EVOKER = true
}

local function GetLightModeClassTexPath(classToken)
    if classToken and lightModeClasses[classToken] then
        return Assets:Bundle("skin-lightmode", "YUI-Light-" .. classToken .. ".tga")
    end
    return nil
end

local function GetLightModeTexPath(unit)
    if not unit or not UnitExists or not UnitExists(unit) then return nil end

    if UnitIsTapDenied and UnitPlayerControlled and UnitIsTapDenied(unit) and not UnitPlayerControlled(unit) then
        return Assets:Bundle("skin-lightmode", "YUI-Light-Tapped.tga")
    end

    local treatAsPlayer = (UnitIsPlayer and UnitIsPlayer(unit))
        or (UnitAPI.UnitTreatAsPlayerForDisplay and UnitAPI.UnitTreatAsPlayerForDisplay(unit))
    if treatAsPlayer and not (UnitIsCharmed and UnitIsCharmed(unit)) then
        local classToken = UnitAPI.UnitClassBase and UnitAPI.UnitClassBase(unit)
        if not classToken and UnitClass then
            local _, fallbackClassToken = UnitClass(unit)
            classToken = fallbackClassToken
        end
        local texPath = GetLightModeClassTexPath(classToken)
        if texPath then return texPath end
    end

    local reaction = UnitReaction and UnitReaction(unit, "player")
    if reaction then
        if reaction >= 5 then
            return GetLightModeClassTexPath("HUNTER")
        elseif reaction == 4 then
            return GetLightModeClassTexPath("ROGUE")
        elseif reaction == 3 then
            return GetLightModeClassTexPath("DRUID")
        elseif reaction <= 2 then
            return GetLightModeClassTexPath("DEATHKNIGHT")
        end
    end

    return nil
end

local ApplyLightModeToBar

local function QueueLightModeRefreshForBar(bar, unit)
    if not bar or bar.__yuiLightModeRefreshQueued then return end

    local function run()
        bar.__yuiLightModeRefreshQueued = nil
        ApplyLightModeToBar(bar, unit or bar.__yuiLightModeUnit)
    end

    bar.__yuiLightModeRefreshQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, run)
    else
        run()
    end
end

local function GetBarTexture(bar)
    local tex = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    local current
    if tex and tex.GetTexture then
        current = tex:GetTexture()
    end
    return tex, current
end

local function SafeLightModeHook(object, method, callback)
    if type(hooksecurefunc) ~= "function" then return false end
    if not object or type(method) ~= "string" or type(object[method]) ~= "function" then return false end

    local ok, err = pcall(hooksecurefunc, object, method, callback)
    if not ok and YUI.Debug then
        YUI:Debug("Appearance | light mode hook failed: " .. tostring(method) .. " - " .. tostring(err))
    end
    return ok
end

local function EnsureLightModeHooks(bar, tex)
    if not bar then return end

    if not bar.__yuiLightModeBarHooked and bar.SetStatusBarTexture then
        bar.__yuiLightModeBarHooked = true
        SafeLightModeHook(bar, "SetStatusBarTexture", function(self)
            if self.__yuiApplyingLightMode then return end
            QueueLightModeRefreshForBar(self, self.__yuiLightModeUnit)
        end)
    end

    if tex and tex.SetTexture and bar.__yuiLightModeTextureHooked ~= tex then
        bar.__yuiLightModeTextureHooked = tex
        SafeLightModeHook(tex, "SetTexture", function()
            if bar.__yuiApplyingLightMode then return end
            QueueLightModeRefreshForBar(bar, bar.__yuiLightModeUnit)
        end)
    end
end

ApplyLightModeToBar = function(bar, unit)
    if not bar or not bar.GetStatusBarTexture then return end
    if unit then
        bar.__yuiLightModeUnit = unit
    else
        unit = bar.__yuiLightModeUnit
    end

    local tex, currentTex = GetBarTexture(bar)
    EnsureLightModeHooks(bar, tex)

    if GetOption("lightMode", false) ~= true then return end

    local texPath = GetLightModeTexPath(unit)
    if not texPath then return end

    bar.__yuiApplyingLightMode = true
    if currentTex ~= texPath and tex and tex.SetTexture then
        tex:SetTexture(texPath)
    elseif currentTex ~= texPath and bar.SetStatusBarTexture then
        bar:SetStatusBarTexture(texPath)
        tex = bar:GetStatusBarTexture()
    end
    if tex and tex.SetAlpha then
        tex:SetAlpha(1)
    end
    bar.__yuiApplyingLightMode = nil
    bar.__yuiLightModeTex = texPath
    EnsureLightModeHooks(bar, tex)
end

-- 公开 API 给外观集成调用；YUI.Skins 保留为内部兼容别名。
local Skins = {
    EnsureDB = EnsureDB,
    GetOption = GetOption,
    SetOption = SetOption,
    IsEnabled = IsEnabled,
    CreateSkinFrame = CreateSkinFrame,
    IsSkinned = IsSkinned,
    ShouldSkipFrame = ShouldSkipFrame,
    GetLightModeClassTexPath = GetLightModeClassTexPath,
    GetLightModeTexPath = GetLightModeTexPath,
    ApplyLightModeToBar = ApplyLightModeToBar,
}

Appearance.Skins = Skins
YUI.Skins = Skins
