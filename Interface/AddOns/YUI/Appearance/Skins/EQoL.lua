local ADDON_NAME, YUI = ...
local Skins = YUI.Appearance and YUI.Appearance.Skins or YUI.Skins
local GUI2 = YUI.GUI2
local Security = YUI.API and YUI.API.Security or YUI.WOW_API or {}
local cpuWatchdog = YUI.CPUWatchdog

local function Measured(callback, kind)
    if cpuWatchdog and cpuWatchdog.WrapAppearanceCallback then
        return cpuWatchdog:WrapAppearanceCallback("eqol", kind, callback)
    end
    return callback
end
local function ScheduleAfter(delay, callback)
    return C_Timer.After(delay, Measured(callback, "delayed"))
end
local function ScheduleTimer(delay, callback)
    return C_Timer.NewTimer(delay, Measured(callback, "delayed"))
end

-- 控制是否使用渐变纹理代替 Backdrop 来实现底部内侧阴影
-- true: 使用渐变纹理 (无额外 Frame 开销，无宽度溢出)
-- false: 使用旧版 Backdrop (会有两个阴影叠加，且高度为1时两端可能溢出)
local USE_GRADIENT_INNER_SHADOW = true

-- 控制是否美化小队框架
local ENABLE_PARTY_FRAMES_SKIN = true
-- 控制是否美化团队框架 (包括主坦 mt /主助 ma)
local ENABLE_RAID_FRAMES_SKIN = true
-- 黑色 1px，匹配 ElvUI 风格边框。
local FORCED_PIXEL_BORDER_WIDTH = 1
local FORCED_PIXEL_BORDER_COLOR_R = 0
local FORCED_PIXEL_BORDER_COLOR_G = 0
local FORCED_PIXEL_BORDER_COLOR_B = 0
local FORCED_PIXEL_BORDER_COLOR_A = 1
local FORCED_PIXEL_BORDER_LEVEL_OFFSET = 2
local FORCED_PIXEL_BORDER_DRAW_LAYER = "BORDER"
local FORCED_PIXEL_BORDER_DRAW_SUBLEVEL = 7
local TARGET_UNITS = {
    "player",
    "target",
    "targettarget",
    "focus",
    "pet",
    "boss",
}
for index = 1, (_G.MAX_BOSS_FRAMES or 5) do
    TARGET_UNITS[#TARGET_UNITS + 1] = "boss" .. index
end

local TARGET_UNIT_LOOKUP = {}
for _, unit in ipairs(TARGET_UNITS) do
    TARGET_UNIT_LOOKUP[unit] = true
end

-- 如果 EnhanceQoL 未加载，则不注册此功能
if not _G.EnhanceQoL then return end

local pendingRefreshAfterCombat = false
local pendingRefreshAfterCombatReasons = {}
local pendingTextPixelBiasAfterCombat = false
local RefreshEnabledState
local forcedBorderDebugMessages = {}
local lightModeSingleRefreshScheduled = false
local lightModeSingleRosterTransaction = false
local groupButtonSkinQueue = {}
local groupButtonSkinScheduled = false
local groupButtonSkinRosterTransaction = false
local groupTextPixelBiasQueue = {}
local groupTextPixelBiasScheduled = false
local groupTextPixelBiasRosterTransaction = false
local rosterRefreshScheduled = false
local rosterRefreshTimer
local EQOL_GROUP_TEXT_PIXEL_EDGE_THRESHOLD = 0.08
local EQOL_GROUP_TEXT_PIXEL_TARGET_DISTANCE = 0.12
local ENABLE_EQOL_NAME_LAYOUT_DIAGNOSTIC = false
local EQOL_NAME_LAYOUT_DIAGNOSTIC_MAX = 140
local EQOL_NAME_LAYOUT_SAMPLE_INTERVAL = 0.1
local EQOL_NAME_LAYOUT_SAMPLE_PASSES = 180
local nameLayoutDiagnosticCount = 0
local nameLayoutRefreshDiagnosticCount = 0
local nameLayoutRuntimeSampleButtons = {}
local nameLayoutRuntimeSampleScheduled = false
local nameLayoutRuntimeSamplePass = 0
local LIGHT_MODE_SINGLE_UNITS = {
    "player",
    "target",
    "targettarget",
    "focus",
    "pet",
}

local function SafeCall(label, func, ...)
    if Security and Security.SafeCall then
        return Security.SafeCall("Appearance | EQoL | " .. tostring(label or "callback"), func, ...)
    end
    return false, "YUI.API.Security.SafeCall unavailable"
end

local function SafeMethod(label, object, method, ...)
    if Security and Security.SafeMethod then
        return Security.SafeMethod("Appearance | EQoL | " .. tostring(label or method or "method"), object, method, ...)
    end
    return false, "YUI.API.Security.SafeMethod unavailable"
end

local function SafeHook(label, object, method, callback)
    callback = Measured(callback, "hook")
    if Security and Security.SafeHook then
        return Security.SafeHook("Appearance | EQoL | " .. tostring(label or method or "hook"), object, method, callback)
    end
    return false, "YUI.API.Security.SafeHook unavailable"
end

local function IsInCombatLockdown()
    if Security and Security.InCombatLockdown then
        return Security.InCombatLockdown() == true
    end
    return InCombatLockdown and InCombatLockdown() == true
end

local function QueueRefreshAfterCombat(reason)
    local reasonKey = tostring(reason or "unknown")
    local shouldLog = pendingRefreshAfterCombatReasons[reasonKey] ~= true

    pendingRefreshAfterCombat = true
    pendingRefreshAfterCombatReasons[reasonKey] = true

    if shouldLog and YUI.Debug then
        YUI:Debug("Appearance | EQoL | 延后到脱战刷新: " .. reasonKey)
    end
end

local function IsFeatureEnabled()
    if Skins and Skins.IsEnabled then
        return Skins.IsEnabled("eqolUnitFrames")
    end
    return false
end

local function IsShadowEnabled()
    -- EQoL 柔和阴影当前强制关闭，忽略玩家 DB 中的 YUISkins_Shadow/Appearance.skins.shadow。
    -- 未来若确认 EQoL 阴影稳定，可移除此覆盖并重新在设置页显示对应选项。
    return false
end

local function IsForcePixelBorderEnabled()
    if not IsFeatureEnabled() then
        return false
    end
    if Skins and Skins.GetOption then
        return Skins.GetOption("eqolPowerBorder", false) == true
    end
    return false
end

local function IsLightModeEnabled()
    if not IsFeatureEnabled() then
        return false
    end
    if Skins and Skins.GetOption then
        return Skins.GetOption("lightMode", false) == true
    end
    return false
end

-- ==========================================
-- 辅助函数
-- ==========================================

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
    if callOk then
        return value
    end
    return nil
end

local function DebugForcedPixelBorder(key, frame, reason)
    if not (YUI and type(YUI.Debug) == "function") then return end

    local name = FrameMethodValue(frame, "GetName") or "<anonymous>"
    local width = FrameMethodValue(frame, "GetWidth") or 0
    local height = FrameMethodValue(frame, "GetHeight") or 0
    local shown = FrameMethodValue(frame, "IsShown")
    local strata = FrameMethodValue(frame, "GetFrameStrata") or "nil"
    local level = FrameMethodValue(frame, "GetFrameLevel") or "nil"
    local messageKey = tostring(key or "default") .. "|" .. tostring(name) .. "|" .. tostring(reason or "unknown")

    if forcedBorderDebugMessages[messageKey] then return end
    forcedBorderDebugMessages[messageKey] = true

    YUI:Debug(
        "Appearance | EQoL | Forced border skipped | key=" .. tostring(key or "default") ..
        " | reason=" .. tostring(reason or "unknown") ..
        " | frame=" .. tostring(name) ..
        " | shown=" .. tostring(shown) ..
        " | size=" .. tostring(width) .. "x" .. tostring(height) ..
        " | strata=" .. tostring(strata) ..
        " | level=" .. tostring(level)
    )
end

local function IsFrameBlacklisted(frame)
    if not frame then return true end

    -- 1. 检查是否为禁止/受保护框架。正式服污染规则下先做这个判断，避免后续读取触发错误。
    if FrameMethodBool(frame, "IsForbidden") then return true end
    if FrameMethodBool(frame, "IsProtected") then return true end

    -- 2. 严格检查是否为 Tooltip 类型 (核心防 Taint)
    local okObjectType, isTooltip = pcall(function()
        return frame.IsObjectType and frame:IsObjectType("GameTooltip")
    end)
    if okObjectType and isTooltip then
        return true
    end

    -- 3. 特定黑名单
    local name = FrameMethodValue(frame, "GetName")
    if name then
        if name:find("Tooltip") then return true end
        if name:find("NamePlate") then return true end
        if name:find("CastingBar") then return true end
        if name:find("SpellBar") then return true end
    end
    
    return false
end

local function GetBorderTargetBlockReason(frame)
    if not frame then return "frame is nil" end
    if IsFrameBlacklisted(frame) then return "frame is blacklisted/protected" end

    local shown = FrameMethodValue(frame, "IsShown")
    if shown == false then return "frame is hidden" end

    local width = FrameMethodValue(frame, "GetWidth") or 0
    local height = FrameMethodValue(frame, "GetHeight") or 0
    if width <= 0 or height <= 0 then return "frame has no size" end

    return nil
end

local function IsVisibleBorderTarget(frame, key)
    local reason = GetBorderTargetBlockReason(frame)
    if reason then
        DebugForcedPixelBorder(key, frame, reason)
        return false
    end
    return true
end

local function HideFrame(frame, label)
    if not frame or IsFrameBlacklisted(frame) then return end
    if frame.Hide then
        SafeMethod(label or "HideFrame", frame, "Hide")
    end
end

local function ShowFrame(frame, label)
    if not frame or IsFrameBlacklisted(frame) then return end
    if frame.Show then
        SafeMethod(label or "ShowFrame", frame, "Show")
    end
end

local function SuppressThirdPartyBorderFrame(border, label, force)
    if not border or IsFrameBlacklisted(border) then return end

    if force or FrameMethodValue(border, "IsShown") ~= false then
        HideFrame(border, label or "SuppressThirdPartyBorderFrame")
    end

    if not IsInCombatLockdown() and border.SetBackdrop then
        if force or border.__yuiEQoLSuppressedBackdrop ~= true then
            SafeMethod((label or "SuppressThirdPartyBorderFrame") .. ":SetBackdrop", border, "SetBackdrop", nil)
            border.__yuiEQoLSuppressedBackdrop = true
        end
    elseif IsInCombatLockdown() and border.SetBackdrop then
        QueueRefreshAfterCombat((label or "SuppressThirdPartyBorderFrame") .. ":SetBackdrop")
    end
end

local function SuppressFrameNativeBorders(frame, label, force)
    if not frame then return end
    if IsFrameBlacklisted(frame) then return end

    if not frame._ufBorder and not frame._rbBorder and not frame._rbSegmentBorder then return end

    local state = frame.__yuiEQoLNativeBorderRefs
    if not state then
        state = {}
        frame.__yuiEQoLNativeBorderRefs = state
    end

    local function suppress(field)
        local border = frame[field]
        if not border then
            state[field] = nil
            return
        end

        local referenceChanged = state[field] ~= border
        if force or referenceChanged or FrameMethodValue(border, "IsShown") ~= false then
            SuppressThirdPartyBorderFrame(border, (label or "frame") .. "." .. field, force or referenceChanged)
            state[field] = border
        end
    end

    suppress("_ufBorder")
    suppress("_rbBorder")
    suppress("_rbSegmentBorder")
end

local function GetForcedPixelBorderSize(region)
    local desiredPixels = tonumber(region and region.__yuiForcedPixelBorderWidth) or FORCED_PIXEL_BORDER_WIDTH
    local pixelUtil = PixelUtil
    if pixelUtil and pixelUtil.GetPixelToUIUnitFactor and pixelUtil.GetNearestPixelSize then
        local scale = FrameMethodValue(region, "GetEffectiveScale")
        if scale and scale > 0 then
            local okFactor, uiUnitFactor = pcall(pixelUtil.GetPixelToUIUnitFactor)
            if okFactor and type(uiUnitFactor) == "number" and uiUnitFactor > 0 then
                local uiUnits = uiUnitFactor * desiredPixels / scale
                local okSize, size = pcall(pixelUtil.GetNearestPixelSize, uiUnits, scale, desiredPixels)
                if okSize and type(size) == "number" and size > 0 then
                    return size
                end
            end
        end
    end

    local mult = (GUI2 and GUI2.mult) or 1
    return mult * desiredPixels
end

local function UpdateForcedPixelBorderScale(border)
    local borders = border and border.gui2Borders
    if not borders then return end

    local size = GetForcedPixelBorderSize(border)
    if borders.top then borders.top:SetHeight(size) end
    if borders.bottom then borders.bottom:SetHeight(size) end
    if borders.left then borders.left:SetWidth(size) end
    if borders.right then borders.right:SetWidth(size) end
end

local function SetForcedPixelBorderDrawLayer(border)
    local borders = border and border.gui2Borders
    if not borders then return end

    local function apply(texture)
        if texture and texture.SetDrawLayer then
            texture:SetDrawLayer(FORCED_PIXEL_BORDER_DRAW_LAYER, FORCED_PIXEL_BORDER_DRAW_SUBLEVEL)
        end
    end

    apply(borders.top)
    apply(borders.bottom)
    apply(borders.left)
    apply(borders.right)
end

local function ApplyForcedPixelBorderColor(border)
    local borders = border and border.gui2Borders
    if not borders then return end

    -- 保持 numeric colorKey，避免 GUI2 theme refresh 把固定边框色刷回默认 token 色。
    borders.colorKey = FORCED_PIXEL_BORDER_COLOR_R
    borders.colorR = FORCED_PIXEL_BORDER_COLOR_R
    borders.colorG = FORCED_PIXEL_BORDER_COLOR_G
    borders.colorB = FORCED_PIXEL_BORDER_COLOR_B
    borders.colorA = FORCED_PIXEL_BORDER_COLOR_A

    if GUI2 and GUI2.SetBorderColor then
        GUI2:SetBorderColor(
            border,
            FORCED_PIXEL_BORDER_COLOR_R,
            FORCED_PIXEL_BORDER_COLOR_G,
            FORCED_PIXEL_BORDER_COLOR_B,
            FORCED_PIXEL_BORDER_COLOR_A
        )
        return
    end

    local function apply(texture)
        if texture and texture.SetColorTexture then
            texture:SetColorTexture(
                FORCED_PIXEL_BORDER_COLOR_R,
                FORCED_PIXEL_BORDER_COLOR_G,
                FORCED_PIXEL_BORDER_COLOR_B,
                FORCED_PIXEL_BORDER_COLOR_A
            )
        end
    end

    apply(borders.top)
    apply(borders.bottom)
    apply(borders.left)
    apply(borders.right)
end

local function PrepareForcedPixelBorder(border)
    if not border then return end
    border.__yuiForcedPixelBorder = true
    border.__yuiForcedPixelBorderWidth = FORCED_PIXEL_BORDER_WIDTH
    border.UpdateGUI2PixelScale = UpdateForcedPixelBorderScale
    border.UpdatePixelScale = UpdateForcedPixelBorderScale
    SetForcedPixelBorderDrawLayer(border)
    ApplyForcedPixelBorderColor(border)
    UpdateForcedPixelBorderScale(border)
end

local function GetForcedPixelBorderLevel(frame, opts)
    local level = tonumber(FrameMethodValue(frame, "GetFrameLevel")) or 0
    local offset = tonumber(opts and opts.levelOffset) or FORCED_PIXEL_BORDER_LEVEL_OFFSET
    level = level + offset
    if level < 0 then return 0 end
    if level > 65535 then return 65535 end
    return level
end

local function SyncForcedPixelBorderLayer(frame, border, opts)
    if not frame or not border then return end

    local strata = FrameMethodValue(frame, "GetFrameStrata")
    if strata and border.SetFrameStrata and (not border.GetFrameStrata or border:GetFrameStrata() ~= strata) then
        border:SetFrameStrata(strata)
    end

    local level = GetForcedPixelBorderLevel(frame, opts)
    if border.SetFrameLevel and (not border.GetFrameLevel or border:GetFrameLevel() ~= level) then
        border:SetFrameLevel(level)
    end

    PrepareForcedPixelBorder(border)
end

local function GetForcedPixelBorderState(frame, key)
    local states = frame.__yuiForcedPixelBorderStates
    if not states then
        states = {}
        frame.__yuiForcedPixelBorderStates = states
    end

    local state = states[key]
    if not state then
        state = {}
        states[key] = state
    end

    return state
end

local function SetForcedPixelBorder(frame, visible, key, opts)
    key = key or "default"
    if not frame then
        if visible then DebugForcedPixelBorder(key, frame, "frame is nil") end
        return
    end
    if IsFrameBlacklisted(frame) then
        if visible then DebugForcedPixelBorder(key, frame, "frame is blacklisted/protected") end
        return
    end

    local borders = frame.__yuiForcedPixelBorders
    local border = borders and borders[key]
    local dirty = opts and opts.dirty == true
    local state
    local legacyPowerBorder = frame.__yuiPowerBorderFrame

    if legacyPowerBorder then
        state = GetForcedPixelBorderState(frame, key)
        if dirty or state.legacyPowerBorder ~= legacyPowerBorder or FrameMethodValue(legacyPowerBorder, "IsShown") ~= false then
            HideFrame(legacyPowerBorder, "Hide legacy power border")
            state.legacyPowerBorder = legacyPowerBorder
        end
    end

    if visible then
        state = state or GetForcedPixelBorderState(frame, key)

        if not GUI2 or not GUI2.CreateFrame or not GUI2.CreateBorder then
            return
        end

        if not border then
            if IsInCombatLockdown() then
                QueueRefreshAfterCombat("create forced border")
                return
            end

            borders = borders or {}
            frame.__yuiForcedPixelBorders = borders

            border = GUI2:CreateFrame(frame, {
                allPoints = true,
                frameLevel = GetForcedPixelBorderLevel(frame),
                mouse = false,
            })

            GUI2:CreateBorder(
                border,
                FORCED_PIXEL_BORDER_COLOR_R,
                FORCED_PIXEL_BORDER_COLOR_G,
                FORCED_PIXEL_BORDER_COLOR_B,
                FORCED_PIXEL_BORDER_COLOR_A
            )
            PrepareForcedPixelBorder(border)
            SyncForcedPixelBorderLayer(frame, border)
            borders[key] = border
            dirty = true
        end

        local strata = FrameMethodValue(frame, "GetFrameStrata")
        local level = GetForcedPixelBorderLevel(frame, opts)
        local width = FrameMethodValue(frame, "GetWidth") or 0
        local height = FrameMethodValue(frame, "GetHeight") or 0
        local pixelSize = GetForcedPixelBorderSize(border)
        local needsSync = dirty
            or state.strata ~= strata
            or state.level ~= level
            or state.width ~= width
            or state.height ~= height
            or state.pixelSize ~= pixelSize

        if needsSync then
            if IsInCombatLockdown() then
                QueueRefreshAfterCombat("sync forced border")
            else
                SyncForcedPixelBorderLayer(frame, border, opts)
                state.strata = strata
                state.level = level
                state.width = width
                state.height = height
                state.pixelSize = pixelSize
            end
        end

        if dirty or state.visible ~= true or FrameMethodValue(border, "IsShown") ~= true then
            ShowFrame(border, "Show forced pixel border")
        end
        state.visible = true
    elseif border then
        state = state or GetForcedPixelBorderState(frame, key)
        if dirty or state.visible ~= false or FrameMethodValue(border, "IsShown") ~= false then
            HideFrame(border, "Hide forced pixel border")
        end
        state.visible = false
    end
end

local function ApplySkinToFrame(frame, onlyShadow)
    if YUI.Skins and YUI.Skins.ShouldSkipFrame and YUI.Skins.ShouldSkipFrame(frame) then return end
    local isBlacklisted = IsFrameBlacklisted(frame)
    if isBlacklisted then return end
    
    -- 避免重复应用
    if YUI.Skins and YUI.Skins.IsSkinned(frame) then return end

    if IsInCombatLockdown() then
        QueueRefreshAfterCombat("create skin frame")
        return
    end
    
    -- 调用 Core 中定义的渲染 API
    if YUI.Skins and YUI.Skins.CreateSkinFrame then
        local options = {
            -- EQoL 柔和阴影当前强制关闭，忽略玩家 DB 中的 YUISkins_Shadow/Appearance.skins.shadow。
            -- 未来若确认 EQoL 阴影稳定，可移除此覆盖并重新在设置页显示对应选项。
            forceShadow = false,
        }
        YUI.Skins.CreateSkinFrame(frame, nil, nil, onlyShadow, options)
    end
end

-- ==========================================
-- 单位框架处理
-- ==========================================

local function SkinEQoLUnitFrameBar(bar)
    ApplySkinToFrame(bar, true) -- 单位框架仅添加阴影
end

local function ApplyLightModeToEQoLUnitFrame(st, unit)
    if not IsLightModeEnabled() or not st or not st.health then
        return
    end

    if unit then
        st.__yuiLightModeUnit = unit
    else
        unit = st.__yuiLightModeUnit
    end

    if Skins and Skins.ApplyLightModeToBar then
        Skins.ApplyLightModeToBar(st.health, unit)
        if st.health.SetStatusBarDesaturated then
            st.health:SetStatusBarDesaturated(false)
        end
    end
end

local function ResolveEQoLButtonUnit(btn)
    if not btn then return nil end
    if btn.GetAttribute then
        local ok, secureUnit = SafeCall("EQoL button GetAttribute(unit)", btn.GetAttribute, btn, "unit")
        if ok and secureUnit ~= nil and secureUnit ~= "" then
            return secureUnit
        end
    end
    return btn.unit
end

local function HideForcedBordersFromState(st)
    if not st then return end
    SetForcedPixelBorder(st.barGroup, false, "unitFrame")
    SetForcedPixelBorder(st.power, false, "power")
    SetForcedPixelBorder(st.secondaryPower, false, "secondaryPower")
    SetForcedPixelBorder(st.powerGroup, false, "powerGroup")
    SetForcedPixelBorder(st.secondaryPowerGroup, false, "secondaryPowerGroup")
end

local function SuppressNativeUnitFrameBorders(st, force)
    if not st then return end
    SuppressFrameNativeBorders(st.barGroup, "unit.barGroup", force)
    SuppressFrameNativeBorders(st.powerGroup, "unit.powerGroup", force)
    SuppressFrameNativeBorders(st.secondaryPowerGroup, "unit.secondaryPowerGroup", force)
    SuppressFrameNativeBorders(st.power, "unit.power", force)
    SuppressFrameNativeBorders(st.secondaryPower, "unit.secondaryPower", force)
end

local function ApplyForcedResourceBorder(bar, groupFrame, key, opts)
    key = key or "power"
    if not IsForcePixelBorderEnabled() then
        SetForcedPixelBorder(bar, false, key)
        SetForcedPixelBorder(groupFrame, false, key .. "Group")
        return
    end

    local dirty = opts and opts.dirty == true
    SuppressFrameNativeBorders(bar, key, dirty)
    SuppressFrameNativeBorders(groupFrame, key .. "Group", dirty)

    local groupKey = key .. "Group"
    if IsVisibleBorderTarget(groupFrame, groupKey) then
        SetForcedPixelBorder(bar, false, key, opts)
        SetForcedPixelBorder(groupFrame, true, groupKey, opts)
    elseif IsVisibleBorderTarget(bar, key) then
        SetForcedPixelBorder(groupFrame, false, groupKey, opts)
        SetForcedPixelBorder(bar, true, key, opts)
    else
        SetForcedPixelBorder(groupFrame, false, groupKey, opts)
        SetForcedPixelBorder(bar, false, key, opts)
    end
end

local function SuppressEQoLGroupBorders(GF, force)
    if not (GF and type(GF.groupBorders) == "table") then return end

    for kind, border in pairs(GF.groupBorders) do
        SuppressThirdPartyBorderFrame(border, "groupBorders." .. tostring(kind), force)
    end
end

local function ForEachChild(frame, label, callback)
    if not frame or type(callback) ~= "function" then return end

    local ok, children = SafeCall(label or "GetChildren", function(target)
        return { target:GetChildren() }
    end, frame)
    if not ok then return end

    for _, child in ipairs(children or {}) do
        if child then
            callback(child)
        end
    end
end

local function SkinEQoLUnitFrameBarWithInnerBottom(barGroup, healthBar, shadowHeight)
    -- 1. 正常为整个生命条背景应用底层环绕外阴影 (保留原有逻辑)
    ApplySkinToFrame(barGroup, true)
    
    if not healthBar then return end
    if not IsShadowEnabled() then
        if healthBar.__yuiBottomGradient then
            healthBar.__yuiBottomGradient:Hide()
        end
        if barGroup and barGroup.__yuiBottomAnchor then
            barGroup.__yuiBottomAnchor:Hide()
        end
        return
    end

    if USE_GRADIENT_INNER_SHADOW then
        -- 方案1：使用渐变材质法 (无 Frame 开销，无边缘溢出)
        if not healthBar.__yuiBottomGradient then
            if IsInCombatLockdown() then
                QueueRefreshAfterCombat("create bottom gradient")
                return
            end

            local tex = healthBar:CreateTexture(nil, "OVERLAY")
            tex:SetPoint("BOTTOMLEFT")
            tex:SetPoint("BOTTOMRIGHT")
            
            -- 动态计算阴影高度：框体高度的 20%，最小 2 像素，最大 8 像素
            -- local targetHeight = healthBar:GetHeight() or 20
            -- local shadowHeight = math.min(8, math.max(2, targetHeight * 0.2))
            local shadowHeight = shadowHeight or 4
            tex:SetHeight(shadowHeight)
            
            tex:SetColorTexture(1, 1, 1, 1)
            -- 底部黑，顶部透明
            tex:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.6), CreateColor(0, 0, 0, 0))
            
            healthBar.__yuiBottomGradient = tex
        else
            healthBar.__yuiBottomGradient:Show()
        end
    else
        -- 方案2：旧版 Backdrop 法
        -- 如果存在生命条实体，则在其上方创建一个看不见的框体来承载底部内侧阴影
        if not barGroup.__yuiBottomAnchor then
            if IsInCombatLockdown() then
                QueueRefreshAfterCombat("create bottom anchor")
                return
            end

            -- 创建看不见的框体，以 healthBar 为父级
            local dummy = CreateFrame("Frame", nil, healthBar)
            -- 锚点设在底部，与生命条等宽，高度为 1
            dummy:SetPoint("BOTTOMLEFT", barGroup, "BOTTOMLEFT", 0, 0)
            dummy:SetPoint("BOTTOMRIGHT", barGroup, "BOTTOMRIGHT", 0, 0)
            dummy:SetHeight(1)
            
            -- 关键：提高层级，使其位于生命条之上
            local hpLevel = healthBar:GetFrameLevel() or 1
            dummy:SetFrameLevel(hpLevel + 5)
            
            barGroup.__yuiBottomAnchor = dummy
            
            -- 为这个看不见的框体应用柔和阴影美化
            -- 阴影层的层级会自动设为 dummyLevel - 1 (即 hpLevel + 4)，依然在生命条之上
            ApplySkinToFrame(dummy, true)
        else
            barGroup.__yuiBottomAnchor:Show()
        end
    end
end

local function SkinEQoLUnitFrame(st, unit, opts)
    if not st then return end
    if not IsFeatureEnabled() then
        HideForcedBordersFromState(st)
        return
    end

    local dirty = opts and opts.dirty == true
    
    -- EnhanceQoL 的单位框架包含多个部分，给它们的背景容器添加阴影
    if st.barGroup then 
        SkinEQoLUnitFrameBarWithInnerBottom(st.barGroup, st.health) 
        if IsForcePixelBorderEnabled() then
            SuppressNativeUnitFrameBorders(st, dirty)
            SetForcedPixelBorder(st.barGroup, IsVisibleBorderTarget(st.barGroup, "unitFrame"), "unitFrame", opts)
        else
            SetForcedPixelBorder(st.barGroup, false, "unitFrame")
        end
    end
    if st.power then
        ApplySkinToFrame(st.power, true)
        ApplyForcedResourceBorder(st.power, st.powerGroup, "power", opts)
    end
    if st.secondaryPower then
        ApplySkinToFrame(st.secondaryPower, true)
        ApplyForcedResourceBorder(st.secondaryPower, st.secondaryPowerGroup, "secondaryPower", opts)
    end
    if st.portraitHolder then SkinEQoLUnitFrameBar(st.portraitHolder) end

    ApplyLightModeToEQoLUnitFrame(st, unit)
    
    -- 施法条处理
    if st.castBorder then 
        SkinEQoLUnitFrameBar(st.castBorder) 
    elseif st.castBar then 
        SkinEQoLUnitFrameBar(st.castBar) 
    end
end

local function IsEQoLGroupKindEnabled(kind)
    if kind == "party" and not ENABLE_PARTY_FRAMES_SKIN then return false end
    if kind == "raid" and not ENABLE_RAID_FRAMES_SKIN then return false end
    if (kind == "mt" or kind == "ma") and not ENABLE_RAID_FRAMES_SKIN then return false end
    return true
end

local function ResolveEQoLGroupButtonState(btn, label)
    local EnhanceQoL = _G.EnhanceQoL
    local st = btn and btn._eqolUFState
    if not st and EnhanceQoL and EnhanceQoL.Aura and EnhanceQoL.Aura.UFHelper and EnhanceQoL.Aura.UFHelper.getState then
        local ok, state = SafeCall(label or "UFHelper.getState", EnhanceQoL.Aura.UFHelper.getState, btn)
        if ok then
            st = state
        end
    end
    return st
end

local function SkinEQoLGroupButton(btn, opts)
    if not btn then return end
    local kind = btn._eqolGroupKind

    if not IsEQoLGroupKindEnabled(kind) then return end

    local st = ResolveEQoLGroupButtonState(btn, "UFHelper.getState")
    if st then
        SkinEQoLUnitFrame(st, ResolveEQoLButtonUnit(btn), opts)
    end
end

local function QueueEQoLGroupButtonSkin(btn, reason, delay, rosterTransaction)
    if not btn or not btn._eqolGroupKind or not IsEQoLGroupKindEnabled(btn._eqolGroupKind) then return end

    groupButtonSkinQueue[btn] = reason or true
    groupButtonSkinRosterTransaction = groupButtonSkinRosterTransaction or rosterTransaction == true
    if groupButtonSkinScheduled then return end
    groupButtonSkinScheduled = true

    local function run()
        groupButtonSkinScheduled = false
        local isRosterTransaction = groupButtonSkinRosterTransaction
        groupButtonSkinRosterTransaction = false
        local startedAt = cpuWatchdog and cpuWatchdog:BeginProbeTiming()

        local queue = groupButtonSkinQueue
        groupButtonSkinQueue = {}

        local EnhanceQoL = _G.EnhanceQoL
        local GF = EnhanceQoL and EnhanceQoL.Aura and EnhanceQoL.Aura.UF and EnhanceQoL.Aura.UF.GroupFrames
        if IsForcePixelBorderEnabled() then
            SuppressEQoLGroupBorders(GF, true)
        end

        for queuedButton in pairs(queue) do
            if queuedButton and queuedButton._eqolGroupKind and IsEQoLGroupKindEnabled(queuedButton._eqolGroupKind) then
                SafeCall("SkinEQoLGroupButton:" .. tostring(queue[queuedButton] or "queued"), SkinEQoLGroupButton, queuedButton, { dirty = true })
            end
        end
        if startedAt then
            cpuWatchdog:EndProbeTiming(
                "appearance.eqol.group-skin",
                startedAt,
                "EQoL group-skin batch",
                nil,
                isRosterTransaction and cpuWatchdog.ROSTER_TRANSACTION_GROUP_ID or nil,
                isRosterTransaction and cpuWatchdog.ROSTER_TRANSACTION_LABEL or nil
            )
        end
    end

    if C_Timer and C_Timer.After then
        ScheduleAfter(delay or 0, run)
    else
        run()
    end
end

local function PrintEQoLNameDiagnostic(message)
    if not ENABLE_EQOL_NAME_LAYOUT_DIAGNOSTIC then return end
    if YUI and type(YUI.Print) == "function" then
        YUI:Print("EQoLNameDiag | " .. tostring(message or ""))
    elseif print then
        print("YUI EQoLNameDiag | " .. tostring(message or ""))
    end
end

local function FormatDiagnosticNumber(value)
    value = tonumber(value)
    if not value then return "nil" end
    return string.format("%.2f", value)
end

local function GetDiagnosticFramePoint(frame)
    if not (frame and frame.GetPoint) then return "nil", "nil", "nil", "nil" end

    local ok, point, relativeTo, relativePoint, x, y = pcall(frame.GetPoint, frame, 1)
    if not ok then return "err", "err", "nil", "nil" end

    local relativeName = FrameMethodValue(relativeTo, "GetName")
    if not relativeName and relativeTo then
        relativeName = tostring(relativeTo)
    end

    return tostring(point or "nil") .. ">" .. tostring(relativePoint or "nil"),
        tostring(relativeName or "nil"),
        FormatDiagnosticNumber(x),
        FormatDiagnosticNumber(y)
end

local function GetDiagnosticFrameSnapshot(frame)
    if not frame then return "nil" end

    local width = FrameMethodValue(frame, "GetWidth")
    local height = FrameMethodValue(frame, "GetHeight")
    local left = FrameMethodValue(frame, "GetLeft")
    local top = FrameMethodValue(frame, "GetTop")

    return FormatDiagnosticNumber(width) .. "x" .. FormatDiagnosticNumber(height) ..
        "@" .. FormatDiagnosticNumber(left) .. "," .. FormatDiagnosticNumber(top)
end

local function GetDiagnosticCaller()
    if type(debugstack) ~= "function" then return "n/a" end

    local stack = debugstack(4, 4, 0)
    local firstLine = stack and stack:match("[^\n]+")
    if not firstLine then return "n/a" end
    if #firstLine > 96 then
        firstLine = firstLine:sub(1, 96)
    end
    return firstLine
end

local function GetEQoLNameDiagnosticSnapshot(btn)
    if not btn or btn._eqolGroupKind ~= "party" then return nil end

    local st = ResolveEQoLGroupButtonState(btn, "UFHelper.getState(name diagnostic)")
    if not st then return nil end

    local nameText = st.nameText or st.name
    if not nameText then return nil end

    local point, relativeName, x, y = GetDiagnosticFramePoint(nameText)
    local unit = ResolveEQoLButtonUnit(btn) or btn.unit or "nil"
    local layoutAnchor = st.layoutAnchor
    local health = st.health

    local signature = table.concat({
        point,
        relativeName,
        x,
        y,
        GetDiagnosticFrameSnapshot(btn),
        GetDiagnosticFrameSnapshot(layoutAnchor),
        GetDiagnosticFrameSnapshot(health),
        GetDiagnosticFrameSnapshot(nameText),
        FormatDiagnosticNumber(FrameMethodValue(btn, "GetScale")),
        FormatDiagnosticNumber(FrameMethodValue(btn, "GetEffectiveScale")),
    }, "|")

    local message =
        "unit=" .. tostring(unit) ..
        " p=" .. tostring(point) ..
        " rel=" .. tostring(relativeName) ..
        " xy=" .. tostring(x) .. "," .. tostring(y) ..
        " btn=" .. GetDiagnosticFrameSnapshot(btn) ..
        " anchor=" .. GetDiagnosticFrameSnapshot(layoutAnchor) ..
        " health=" .. GetDiagnosticFrameSnapshot(health) ..
        " name=" .. GetDiagnosticFrameSnapshot(nameText) ..
        " scale=" .. FormatDiagnosticNumber(FrameMethodValue(btn, "GetScale")) ..
        "/" .. FormatDiagnosticNumber(FrameMethodValue(btn, "GetEffectiveScale"))

    return signature, message
end

local function ClearEQoLNameRuntimeSamples()
    for btn in pairs(nameLayoutRuntimeSampleButtons) do
        nameLayoutRuntimeSampleButtons[btn] = nil
    end
    nameLayoutRuntimeSampleScheduled = false
    nameLayoutRuntimeSamplePass = 0
end

local function RunEQoLNameRuntimeSamplePass()
    if not ENABLE_EQOL_NAME_LAYOUT_DIAGNOSTIC then
        ClearEQoLNameRuntimeSamples()
        return
    end
    if nameLayoutDiagnosticCount >= EQOL_NAME_LAYOUT_DIAGNOSTIC_MAX then
        ClearEQoLNameRuntimeSamples()
        return
    end

    nameLayoutRuntimeSamplePass = nameLayoutRuntimeSamplePass + 1

    local hasButtons = false
    for btn in pairs(nameLayoutRuntimeSampleButtons) do
        if btn and btn._eqolGroupKind == "party" then
            hasButtons = true

            local signature, message = GetEQoLNameDiagnosticSnapshot(btn)
            if signature and message then
                local changed = signature ~= btn.__yuiEQoLNameRuntimeSampleSignature
                local shouldPrint = changed or nameLayoutRuntimeSamplePass <= 5 or (nameLayoutRuntimeSamplePass % 20) == 0
                btn.__yuiEQoLNameRuntimeSampleSignature = signature

                if shouldPrint and nameLayoutDiagnosticCount < EQOL_NAME_LAYOUT_DIAGNOSTIC_MAX then
                    nameLayoutDiagnosticCount = nameLayoutDiagnosticCount + 1
                    PrintEQoLNameDiagnostic(
                        "live " .. (changed and "changed" or "sample") ..
                        " pass=" .. tostring(nameLayoutRuntimeSamplePass) ..
                        " " .. message
                    )
                end
            end
        else
            nameLayoutRuntimeSampleButtons[btn] = nil
        end
    end

    if not hasButtons or nameLayoutRuntimeSamplePass >= EQOL_NAME_LAYOUT_SAMPLE_PASSES then
        ClearEQoLNameRuntimeSamples()
        return
    end

    if C_Timer and C_Timer.After then
        ScheduleAfter(EQOL_NAME_LAYOUT_SAMPLE_INTERVAL, RunEQoLNameRuntimeSamplePass)
    else
        ClearEQoLNameRuntimeSamples()
    end
end

local function ScheduleEQoLNameRuntimeSampler(btn)
    if not ENABLE_EQOL_NAME_LAYOUT_DIAGNOSTIC then return end
    if not btn or btn._eqolGroupKind ~= "party" then return end

    nameLayoutRuntimeSampleButtons[btn] = true
    if nameLayoutRuntimeSampleScheduled then return end

    nameLayoutRuntimeSampleScheduled = true
    nameLayoutRuntimeSamplePass = 0

    if C_Timer and C_Timer.After then
        ScheduleAfter(EQOL_NAME_LAYOUT_SAMPLE_INTERVAL, RunEQoLNameRuntimeSamplePass)
    else
        RunEQoLNameRuntimeSamplePass()
    end
end

local function TraceEQoLNameLayout(btn, reason)
    if not ENABLE_EQOL_NAME_LAYOUT_DIAGNOSTIC then return end
    if nameLayoutDiagnosticCount >= EQOL_NAME_LAYOUT_DIAGNOSTIC_MAX then return end
    if not btn or btn._eqolGroupKind ~= "party" then return end

    local signature, message = GetEQoLNameDiagnosticSnapshot(btn)
    if not signature or not message then return end

    local calls = (btn.__yuiEQoLNameDiagCalls or 0) + 1
    btn.__yuiEQoLNameDiagCalls = calls

    local changed = signature ~= btn.__yuiEQoLNameDiagSignature
    if not changed and calls > 3 and (calls % 60) ~= 0 then return end
    btn.__yuiEQoLNameDiagSignature = signature
    nameLayoutDiagnosticCount = nameLayoutDiagnosticCount + 1

    local label = changed and "changed" or "sample"
    PrintEQoLNameDiagnostic(
        label ..
        " reason=" .. tostring(reason or "layout") ..
        " call=" .. tostring(calls) ..
        " " .. message ..
        " caller=" .. GetDiagnosticCaller()
    )

    ScheduleEQoLNameRuntimeSampler(btn)
end

local function TraceEQoLGroupRefresh(reason)
    if not ENABLE_EQOL_NAME_LAYOUT_DIAGNOSTIC then return end
    if nameLayoutDiagnosticCount >= EQOL_NAME_LAYOUT_DIAGNOSTIC_MAX then return end

    nameLayoutRefreshDiagnosticCount = nameLayoutRefreshDiagnosticCount + 1
    if nameLayoutRefreshDiagnosticCount > 8 and (nameLayoutRefreshDiagnosticCount % 20) ~= 0 then return end

    nameLayoutDiagnosticCount = nameLayoutDiagnosticCount + 1
    PrintEQoLNameDiagnostic(
        "refresh reason=" .. tostring(reason or "refresh") ..
        " count=" .. tostring(nameLayoutRefreshDiagnosticCount) ..
        " caller=" .. GetDiagnosticCaller()
    )
end

local function SkinEQoLLightModeSingleUnits(reason)
    if not IsLightModeEnabled() then return end
    local EnhanceQoL = _G.EnhanceQoL
    local states = EnhanceQoL and EnhanceQoL.variables and EnhanceQoL.variables.states
    if not states then return end

    for _, unit in ipairs(LIGHT_MODE_SINGLE_UNITS) do
        local st = states[unit]
        if st then
            SkinEQoLUnitFrame(st, unit)
        end
    end
end

local function QueueEQoLLightModeSingleRefresh(reason, delay)
    if not IsLightModeEnabled() then return end
    lightModeSingleRosterTransaction = lightModeSingleRosterTransaction
        or reason == "GROUP_ROSTER_UPDATE"
    if lightModeSingleRefreshScheduled then return end
    lightModeSingleRefreshScheduled = true

    local function run()
        lightModeSingleRefreshScheduled = false
        local rosterTransaction = lightModeSingleRosterTransaction
        lightModeSingleRosterTransaction = false
        local startedAt = cpuWatchdog and cpuWatchdog:BeginProbeTiming()
        SafeCall("SkinEQoLLightModeSingleUnits:" .. tostring(reason or "refresh"), SkinEQoLLightModeSingleUnits, reason)
        if startedAt then
            cpuWatchdog:EndProbeTiming(
                "appearance.eqol.light-mode-refresh",
                startedAt,
                "EQoL light-mode refresh",
                nil,
                rosterTransaction and cpuWatchdog.ROSTER_TRANSACTION_GROUP_ID or nil,
                rosterTransaction and cpuWatchdog.ROSTER_TRANSACTION_LABEL or nil
            )
        end
    end

    if C_Timer and C_Timer.After then
        ScheduleAfter(delay or 0, run)
    else
        run()
    end
end

local function SkinExistingEQoLGroupFrames(GF, reason, delay)
    if not GF then return end
    if IsForcePixelBorderEnabled() then
        SuppressEQoLGroupBorders(GF, true)
    end

    if type(GF.anchors) == "table" then
        for _, anchor in pairs(GF.anchors) do
            if anchor then
                ForEachChild(anchor, "GF.anchor:GetChildren", function(child)
                    if child and child._eqolGroupKind then
                        QueueEQoLGroupButtonSkin(child, reason or "existing anchor", delay)
                    end
                end)
            end
        end
    end

    if type(GF.headers) == "table" then
        for _, header in pairs(GF.headers) do
            if header then
                ForEachChild(header, "GF.header:GetChildren", function(child)
                    if child and child._eqolGroupKind then
                        QueueEQoLGroupButtonSkin(child, reason or "existing header", delay)
                    end
                end)
            end
        end
    end
end

local function ResolveEQoLGroupFrames()
    local EnhanceQoL = _G.EnhanceQoL
    return EnhanceQoL and EnhanceQoL.Aura and EnhanceQoL.Aura.UF and EnhanceQoL.Aura.UF.GroupFrames
end

local function GetPixelToUIUnitFactor()
    local pixelUtil = PixelUtil
    if pixelUtil and type(pixelUtil.GetPixelToUIUnitFactor) == "function" then
        local ok, factor = pcall(pixelUtil.GetPixelToUIUnitFactor)
        if ok then
            factor = tonumber(factor)
            if factor and factor > 0 then
                return factor
            end
        end
    end

    if type(GetPhysicalScreenSize) == "function" then
        local ok, _, physicalHeight = pcall(GetPhysicalScreenSize)
        if ok then
            physicalHeight = tonumber(physicalHeight)
            if physicalHeight and physicalHeight > 0 then
                return 768 / physicalHeight
            end
        end
    end

    return nil
end

local function GetRegionPoint(region)
    if not (region and type(region.GetPoint) == "function") then return nil end

    local ok, point, relativeTo, relativePoint, x, y = pcall(region.GetPoint, region, 1)
    if not ok or not point then return nil end

    return point, relativeTo, relativePoint, tonumber(x) or 0, tonumber(y) or 0
end

local function ValuesNearlyEqual(a, b, epsilon)
    a = tonumber(a)
    b = tonumber(b)
    if not a or not b then return false end
    return math.abs(a - b) <= (epsilon or 0.0005)
end

local function IsSameTextPixelBiasAnchor(state, point, relativeTo, relativePoint, y)
    return state
        and state.point == point
        and state.relativeTo == relativeTo
        and state.relativePoint == relativePoint
        and ValuesNearlyEqual(state.y, y)
end

local function CalculateTextPixelBias(baseLeft, scale, pixelToUIUnitFactor)
    baseLeft = tonumber(baseLeft)
    scale = tonumber(scale)
    pixelToUIUnitFactor = tonumber(pixelToUIUnitFactor)

    if not (baseLeft and scale and pixelToUIUnitFactor) or scale <= 0 or pixelToUIUnitFactor <= 0 then
        return 0
    end

    local physicalX = baseLeft * scale / pixelToUIUnitFactor
    local nearestPixel = math.floor(physicalX + 0.5)
    local distance = physicalX - nearestPixel
    local absDistance = math.abs(distance)

    if absDistance >= EQOL_GROUP_TEXT_PIXEL_EDGE_THRESHOLD then
        return 0
    end

    local targetDistance = EQOL_GROUP_TEXT_PIXEL_TARGET_DISTANCE
    if distance < 0 then
        targetDistance = -targetDistance
    end

    return (targetDistance - distance) * pixelToUIUnitFactor / scale
end

local function ApplyTextPixelBiasToFontString(fontString)
    if not fontString then return end
    if not (fontString.ClearAllPoints and fontString.SetPoint and fontString.GetPoint and fontString.GetLeft and fontString.GetEffectiveScale) then return end

    local point, relativeTo, relativePoint, x, y = GetRegionPoint(fontString)
    if not point then return end

    local state = fontString.__yuiEQoLTextPixelBias
    local baseX = x
    if IsSameTextPixelBiasAnchor(state, point, relativeTo, relativePoint, y) then
        if ValuesNearlyEqual(x, state.appliedX) then
            baseX = tonumber(state.baseX) or (x - (tonumber(state.bias) or 0))
        elseif ValuesNearlyEqual(x, state.baseX) then
            baseX = tonumber(state.baseX) or x
        end
    end

    local left = FrameMethodValue(fontString, "GetLeft")
    local scale = FrameMethodValue(fontString, "GetEffectiveScale")
    local pixelToUIUnitFactor = GetPixelToUIUnitFactor()
    if not (left and scale and pixelToUIUnitFactor) then return end

    local baseLeft = left - (x - baseX)
    local bias = CalculateTextPixelBias(baseLeft, scale, pixelToUIUnitFactor)
    local appliedX = baseX + bias

    local nextState = {
        point = point,
        relativeTo = relativeTo,
        relativePoint = relativePoint,
        y = y,
        baseX = baseX,
        bias = bias,
        appliedX = appliedX,
    }

    if ValuesNearlyEqual(x, appliedX) then
        fontString.__yuiEQoLTextPixelBias = nextState
        return
    end

    fontString:ClearAllPoints()
    if relativeTo then
        fontString:SetPoint(point, relativeTo, relativePoint, appliedX, y)
    else
        fontString:SetPoint(point, appliedX, y)
    end
    fontString.__yuiEQoLTextPixelBias = nextState
end

local function ForEachVisibleEQoLPartyButton(GF, callback)
    if not (GF and type(callback) == "function") then return end
    if not IsEQoLGroupKindEnabled("party") then return end

    local seen = {}
    local function visit(child)
        if not child or seen[child] or child._eqolGroupKind ~= "party" then return end
        seen[child] = true
        if FrameMethodValue(child, "IsShown") == false then return end
        callback(child)
    end

    if type(GF.anchors) == "table" then
        for _, anchor in pairs(GF.anchors) do
            ForEachChild(anchor, "GF.anchor:GetChildren(text pixel bias)", visit)
        end
    end

    if type(GF.headers) == "table" then
        for _, header in pairs(GF.headers) do
            ForEachChild(header, "GF.header:GetChildren(text pixel bias)", visit)
        end
    end
end

local function ApplyEQoLGroupButtonTextPixelBias(btn)
    if not IsFeatureEnabled() then return end
    if not btn or btn._eqolGroupKind ~= "party" then return end
    if FrameMethodValue(btn, "IsShown") == false then return end

    if IsInCombatLockdown() then
        pendingTextPixelBiasAfterCombat = true
        QueueRefreshAfterCombat("text pixel bias")
        return
    end

    local st = ResolveEQoLGroupButtonState(btn, "UFHelper.getState(text pixel bias)")
    if not st then return end

    ApplyTextPixelBiasToFontString(st.nameText or st.name)
    ApplyTextPixelBiasToFontString(st.statusText)
    ApplyTextPixelBiasToFontString(st.groupNumberText)
end

local function QueueEQoLGroupButtonTextPixelBias(btn, reason, delay)
    if not IsFeatureEnabled() then return end
    if not btn or btn._eqolGroupKind ~= "party" then return end

    local reasonKey = tostring(reason or "text pixel bias")
    groupTextPixelBiasRosterTransaction = groupTextPixelBiasRosterTransaction
        or reasonKey == "GROUP_ROSTER_UPDATE"
    if IsInCombatLockdown() then
        pendingTextPixelBiasAfterCombat = true
        QueueRefreshAfterCombat("text pixel bias:" .. reasonKey)
        return
    end

    groupTextPixelBiasQueue[btn] = reasonKey
    if groupTextPixelBiasScheduled then return end
    groupTextPixelBiasScheduled = true

    local function run()
        if IsInCombatLockdown() then
            groupTextPixelBiasScheduled = false
            pendingTextPixelBiasAfterCombat = true
            QueueRefreshAfterCombat("text pixel bias:" .. reasonKey)
            return
        end

        groupTextPixelBiasScheduled = false
        local rosterTransaction = groupTextPixelBiasRosterTransaction
        groupTextPixelBiasRosterTransaction = false
        local startedAt = cpuWatchdog and cpuWatchdog:BeginProbeTiming()

        local queue = groupTextPixelBiasQueue
        groupTextPixelBiasQueue = {}

        for queuedButton, queuedReason in pairs(queue) do
            if queuedButton and queuedButton._eqolGroupKind == "party" then
                SafeCall("ApplyEQoLGroupButtonTextPixelBias:" .. tostring(queuedReason or "queued"), ApplyEQoLGroupButtonTextPixelBias, queuedButton)
                QueueEQoLGroupButtonSkin(queuedButton, "text pixel bias", nil, rosterTransaction)
            end
        end
        if startedAt then
            cpuWatchdog:EndProbeTiming(
                "appearance.eqol.text-pixel-bias",
                startedAt,
                "EQoL text pixel-bias batch",
                nil,
                rosterTransaction and cpuWatchdog.ROSTER_TRANSACTION_GROUP_ID or nil,
                rosterTransaction and cpuWatchdog.ROSTER_TRANSACTION_LABEL or nil
            )
        end
    end

    if C_Timer and C_Timer.After then
        ScheduleAfter(delay or 0, run)
    else
        run()
    end
end

local function QueueExistingEQoLPartyTextPixelBias(GF, reason, delay)
    GF = GF or ResolveEQoLGroupFrames()
    if not GF then return end

    ForEachVisibleEQoLPartyButton(GF, function(btn)
        QueueEQoLGroupButtonTextPixelBias(btn, reason or "existing party", delay)
    end)
end

local function RunEQoLRosterRefresh()
    rosterRefreshScheduled = false
    rosterRefreshTimer = nil
    local startedAt = cpuWatchdog and cpuWatchdog:BeginProbeTiming()
    QueueExistingEQoLPartyTextPixelBias(
        ResolveEQoLGroupFrames(),
        "GROUP_ROSTER_UPDATE"
    )
    QueueEQoLLightModeSingleRefresh("GROUP_ROSTER_UPDATE")
    if startedAt then
        cpuWatchdog:EndProbeTiming(
            "appearance.eqol.roster-discovery",
            startedAt,
            "EQoL roster discovery batch",
            nil,
            cpuWatchdog.ROSTER_TRANSACTION_GROUP_ID,
            cpuWatchdog.ROSTER_TRANSACTION_LABEL
        )
    end
end

local function QueueEQoLRosterRefresh()
    if rosterRefreshScheduled then return end
    rosterRefreshScheduled = true
    if C_Timer and C_Timer.NewTimer then
        rosterRefreshTimer = ScheduleTimer(0.1, RunEQoLRosterRefresh)
    elseif C_Timer and C_Timer.After then
        ScheduleAfter(0.1, RunEQoLRosterRefresh)
    else
        RunEQoLRosterRefresh()
    end
end

local resourceBarRefreshScheduled = false
local SkinEQoLResourceBars

local function ScheduleEQoLResourceBarSkin(delay)
    if resourceBarRefreshScheduled then return end
    resourceBarRefreshScheduled = true

    local function run()
        resourceBarRefreshScheduled = false
        SafeCall("SkinEQoLResourceBars", SkinEQoLResourceBars)
    end

    if C_Timer and C_Timer.After then
        ScheduleAfter(delay or 0.1, run)
    else
        run()
    end
end

local function AddResourceBarFrame(frames, seen, frame)
    if not frame or seen[frame] then return end
    seen[frame] = true
    frames[#frames + 1] = frame
end

local function CollectEQoLResourceBarFrames(ResourceBars)
    local frames = {}
    local seen = {}

    AddResourceBarFrame(frames, seen, _G.EQOLHealthBar)

    local classPowerTypes = ResourceBars and ResourceBars.classPowerTypes
    if type(classPowerTypes) == "table" then
        for _, pType in ipairs(classPowerTypes) do
            AddResourceBarFrame(frames, seen, _G["EQOL" .. tostring(pType) .. "Bar"])
        end
    end

    if ResourceBars and type(ResourceBars.SHARED_SLOT_ORDER) == "table" then
        for _, slot in ipairs(ResourceBars.SHARED_SLOT_ORDER) do
            local frameName = nil
            if type(ResourceBars.GetSharedSlotFrameName) == "function" then
                local ok, name = SafeCall("ResourceBars.GetSharedSlotFrameName", ResourceBars.GetSharedSlotFrameName, slot)
                if ok then
                    frameName = name
                end
            elseif type(ResourceBars.SHARED_SLOT_FRAME_NAME) == "table" then
                frameName = ResourceBars.SHARED_SLOT_FRAME_NAME[slot]
            end

            if frameName then
                AddResourceBarFrame(frames, seen, _G[frameName])
            end

            if type(ResourceBars.GetSharedSlotLiveFrame) == "function" then
                local ok, frame = SafeCall("ResourceBars.GetSharedSlotLiveFrame", ResourceBars.GetSharedSlotLiveFrame, slot)
                if ok then
                    AddResourceBarFrame(frames, seen, frame)
                end
            end
        end
    end

    return frames
end

local function ProcessResourceBarSegments(segments, keyPrefix, forceEnabled)
    local anyShown = false
    if type(segments) ~= "table" then return false end

    for index = 1, #segments do
        local segment = segments[index]
        local key = keyPrefix .. tostring(index)
        if forceEnabled then
            SuppressFrameNativeBorders(segment, key)
        end

        local visible = forceEnabled and IsVisibleBorderTarget(segment, key)
        SetForcedPixelBorder(segment, visible, key)
        if visible then
            anyShown = true
        end
    end

    return anyShown
end

local function ProcessEQoLResourceBar(bar, forceEnabled)
    if not bar then return end

    local barType = bar._rbType or (bar.GetName and FrameMethodValue(bar, "GetName")) or "resource"
    local keyBase = "resource:" .. tostring(barType)
    if forceEnabled then
        SuppressFrameNativeBorders(bar, keyBase)
    end

    local hasSegmentBorder = false
    hasSegmentBorder = ProcessResourceBarSegments(bar.runes, keyBase .. ":rune:", forceEnabled) or hasSegmentBorder
    hasSegmentBorder = ProcessResourceBarSegments(bar.essences, keyBase .. ":essence:", forceEnabled) or hasSegmentBorder
    hasSegmentBorder = ProcessResourceBarSegments(bar._rbDiscreteSegments, keyBase .. ":segment:", forceEnabled) or hasSegmentBorder

    local showBarBorder = forceEnabled and not hasSegmentBorder and IsVisibleBorderTarget(bar, keyBase)
    SetForcedPixelBorder(bar, showBarBorder, keyBase)
end

SkinEQoLResourceBars = function()
    local EnhanceQoL = _G.EnhanceQoL
    local ResourceBars = EnhanceQoL and EnhanceQoL.Aura and EnhanceQoL.Aura.ResourceBars
    if not ResourceBars then return end

    local forceEnabled = IsForcePixelBorderEnabled()
    for _, frame in ipairs(CollectEQoLResourceBarFrames(ResourceBars)) do
        ProcessEQoLResourceBar(frame, forceEnabled)
    end
end

local function HookEQoLResourceBars()
    local EnhanceQoL = _G.EnhanceQoL
    local ResourceBars = EnhanceQoL and EnhanceQoL.Aura and EnhanceQoL.Aura.ResourceBars
    if not ResourceBars then return end

    if ResourceBars.__yuiEQoLForcedPixelBorderHooksInstalled then
        ScheduleEQoLResourceBarSkin(0.1)
        return
    end
    ResourceBars.__yuiEQoLForcedPixelBorderHooksInstalled = true

    local hookMethods = {
        "EnableResourceBars",
        "Refresh",
        "QueueRefresh",
        "ReanchorAll",
        "MaybeRefreshActive",
        "SyncSharedSlotProxyFrames",
    }

    for _, method in ipairs(hookMethods) do
        if type(ResourceBars[method]) == "function" then
            SafeHook("ResourceBars." .. method, ResourceBars, method, function()
                ScheduleEQoLResourceBarSkin(0.1)
            end)
        end
    end

    ScheduleEQoLResourceBarSkin(0.5)
end

local function HookEQoLUnitFrames()
    local EnhanceQoL = _G.EnhanceQoL
    local UF = EnhanceQoL and EnhanceQoL.Aura and EnhanceQoL.Aura.UF
    if not UF then return end
    local unitFrameRefreshScheduled = false

    local function SkinSpecificUnits()
        local states = EnhanceQoL.variables and EnhanceQoL.variables.states
        if not states then return end
        
        for _, unit in ipairs(TARGET_UNITS) do
            local st = states[unit]
            if st then
                SkinEQoLUnitFrame(st, unit)
            end
        end
    end

    local function SkinAllEQoLUnitFrames(reason)
        SkinSpecificUnits()
        SkinExistingEQoLGroupFrames(UF.GroupFrames)
    end

    local function ScheduleEQoLUnitFrameSkin(delay, reason)
        if unitFrameRefreshScheduled then return end
        unitFrameRefreshScheduled = true

        local function run()
            unitFrameRefreshScheduled = false
            SafeCall("SkinAllEQoLUnitFrames:" .. tostring(reason or "refresh"), SkinAllEQoLUnitFrames, reason)
        end

        if C_Timer and C_Timer.After then
            ScheduleAfter(delay or 0.1, run)
        else
            run()
        end
    end

    -- 1. Hook EnhanceQoL 的个体框架刷新路径。
    local unitHooksAlreadyInstalled = UF.__yuiEQoLSkinHooksInstalled == true
    if not unitHooksAlreadyInstalled then
        UF.__yuiEQoLSkinHooksInstalled = true

        if UF.EnsureFrames then
            SafeHook("UF.EnsureFrames", UF, "EnsureFrames", function(unit)
                if TARGET_UNIT_LOOKUP[unit] then
                    ScheduleEQoLUnitFrameSkin(0.1, "UF.EnsureFrames:" .. tostring(unit))
                end
            end)
        end

        local refreshMethods = {
            "Refresh",
            "RefreshUnit",
            "UpdateBossFrames",
        }

        for _, method in ipairs(refreshMethods) do
            local hookMethod = method
            if type(UF[hookMethod]) == "function" then
                SafeHook("UF." .. hookMethod, UF, hookMethod, function(unit)
                    if hookMethod == "RefreshUnit" and TARGET_UNIT_LOOKUP[unit] then
                        local states = EnhanceQoL.variables and EnhanceQoL.variables.states
                        local st = states and states[unit]
                        if st then
                            SkinEQoLUnitFrame(st, unit, { dirty = true })
                            return
                        end
                    end
                    ScheduleEQoLUnitFrameSkin(0.1, "UF." .. hookMethod)
                end)
            end
        end
    end

    -- 2. Hook EnhanceQoL 的小队/团队框架刷新路径。
    local GF = UF.GroupFrames
    if IsForcePixelBorderEnabled() then
        SuppressEQoLGroupBorders(GF, true)
    end
    if GF and not GF.__yuiEQoLGroupSkinHooksInstalled then
        GF.__yuiEQoLGroupSkinHooksInstalled = true

        local buttonMethods = {
            "BuildButton",
            "LayoutButton",
        }

        for _, method in ipairs(buttonMethods) do
            local hookMethod = method
            if type(GF[hookMethod]) == "function" then
                SafeHook("GF." .. hookMethod, GF, hookMethod, function(_, btn)
                    if hookMethod == "LayoutButton" then
                        TraceEQoLNameLayout(btn, "GF.LayoutButton")
                    end
                    QueueEQoLGroupButtonTextPixelBias(btn, "GF." .. hookMethod)
                    QueueEQoLGroupButtonSkin(btn, "GF." .. hookMethod)
                end)
            end
        end

        local groupRefreshMethods = {
            "Refresh",
            "FullRefresh",
            "RefreshChangedUnitButtons",
            "RefreshNames",
        }

        for _, method in ipairs(groupRefreshMethods) do
            local hookMethod = method
            if type(GF[hookMethod]) == "function" then
                SafeHook("GF." .. hookMethod, GF, hookMethod, function()
                    TraceEQoLGroupRefresh("GF." .. hookMethod)
                    SkinExistingEQoLGroupFrames(GF, "GF." .. hookMethod)
                    QueueExistingEQoLPartyTextPixelBias(GF, "GF." .. hookMethod)
                end)
            end
        end

        PrintEQoLNameDiagnostic("hook installed max=" .. tostring(EQOL_NAME_LAYOUT_DIAGNOSTIC_MAX))

        if C_Timer and C_Timer.After then
            ScheduleAfter(1.5, function()
                SkinExistingEQoLGroupFrames(GF, "initial group scan")
                QueueExistingEQoLPartyTextPixelBias(GF, "initial group scan")
            end)
        else
            SkinExistingEQoLGroupFrames(GF, "initial group scan")
            QueueExistingEQoLPartyTextPixelBias(GF, "initial group scan")
        end
    end

    local refreshDelay = unitHooksAlreadyInstalled and 0.1 or 1
    local refreshReason = unitHooksAlreadyInstalled and "existing hooks" or "initial delayed"
    ScheduleEQoLUnitFrameSkin(refreshDelay, refreshReason)
end

-- ==========================================
-- 模块注册
-- ==========================================

RefreshEnabledState = function()
    ScheduleAfter(1, function()
        SafeCall("HookEQoLUnitFrames", HookEQoLUnitFrames)
        SafeCall("HookEQoLResourceBars", HookEQoLResourceBars)
        QueueExistingEQoLPartyTextPixelBias(ResolveEQoLGroupFrames(), "RefreshEnabledState")
    end)
end

if YUI.Event then
    YUI.Event:On("YUI_DB_READY", function()
        RefreshEnabledState()
    end, nil, { priority = -200 })

    YUI.Event:On("PLAYER_LOGIN", function()
        RefreshEnabledState()
    end, nil, { priority = -200 })

    YUI.Event:On("PLAYER_ENTERING_WORLD", function()
        RefreshEnabledState()
        QueueExistingEQoLPartyTextPixelBias(ResolveEQoLGroupFrames(), "PLAYER_ENTERING_WORLD")
    end, nil, { priority = -200 })

    YUI.Event:On("PLAYER_REGEN_ENABLED", function()
        if not pendingRefreshAfterCombat and not pendingTextPixelBiasAfterCombat then return end
        local shouldApplyTextPixelBias = pendingTextPixelBiasAfterCombat
        pendingRefreshAfterCombat = false
        pendingTextPixelBiasAfterCombat = false
        for reason in pairs(pendingRefreshAfterCombatReasons) do
            pendingRefreshAfterCombatReasons[reason] = nil
        end
        RefreshEnabledState()
        if shouldApplyTextPixelBias then
            QueueExistingEQoLPartyTextPixelBias(ResolveEQoLGroupFrames(), "PLAYER_REGEN_ENABLED", 0.1)
        end
    end, nil, { priority = -200 })

    YUI.Event:On("YUI_APPEARANCE_SKIN_OPTION_CHANGED", function(_, key)
        if key == "eqolUnitFrames" or key == "eqolPowerBorder" or key == "lightMode" then
            RefreshEnabledState()
        end
    end)

    YUI.Event:On("PLAYER_TARGET_CHANGED", function()
        QueueEQoLLightModeSingleRefresh("PLAYER_TARGET_CHANGED")
    end, nil, { priority = -200 })

    YUI.Event:On("PLAYER_FOCUS_CHANGED", function()
        QueueEQoLLightModeSingleRefresh("PLAYER_FOCUS_CHANGED")
    end, nil, { priority = -200 })

    YUI.Event:On("GROUP_ROSTER_UPDATE", QueueEQoLRosterRefresh, nil, {
        priority = -200,
        traceName = "Appearance:EQoL:GROUP_ROSTER_UPDATE",
        throttle = 0.1,
    })

    YUI.Event:On("UNIT_PET", function()
        QueueEQoLLightModeSingleRefresh("UNIT_PET")
    end, nil, { priority = -200 })
end
