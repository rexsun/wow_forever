local ADDON_NAME, YUI = ...
local LC = YUI.Locale:Get("Core")

YUI.Installer = {}
local Installer = YUI.Installer
local GUI2 = YUI.GUI2
local Assets = YUI.Assets
local FrameAPI = YUI.API.Frame
local SystemAPI = YUI.API.System
local previousSlashHandler = YUI.HandleSlashCommand

local function GetYUIGlobalDB()
    if YUI.DB and YUI.DB.GetGlobal then
        local global = YUI.DB:GetGlobal(YUI.ProductId or "suite")
        if type(global) == "table" then
            return global
        end
    end
    return type(YUI.global) == "table" and YUI.global or nil
end

-- 安装器窗口
local Frame = nil
local currentStep = 1
local executedSteps = {}
local loginFlowDone

-- 声明局部函数以解决循环依赖
local GoNext
local UpdateInstallerUI
local RefreshForeverActions
local ApplyOrQueuePortraitProfile
local portraitProfileOwner = {}
local steps = {}

local function HasExecutedSteps()
    for _, executed in pairs(executedSteps) do if executed then return true end end
    return false
end

local function CancelButtonTimers(keepSkip)
    if not Frame then return end
    for _, key in ipairs({ "executeTimer", "navigationTimer", "skipTimer" }) do
        if Frame[key] and not (keepSkip and key == "skipTimer") then
            Frame[key]:Cancel(); Frame[key] = nil
        end
    end
end

-- 常量定义
local LAYOUT_NAME = "YUI"
local LAYOUT_NAME_COLORED = "|cff00ff00" .. LAYOUT_NAME .. "|r"
local INSTALLER_SLOGAN_GOLD_START = { 1, 0.50, 0 }
local INSTALLER_SLOGAN_GOLD_END = { 1, 0.84, 0 }
local INSTALLER_ANIMATION_KEY = "installer-window"
local INSTALLER_ANIMATION_DISTANCE = 24
local INSTALLER_ANIMATION_DURATION = 0.18
local INSTALLER_COMPLETION_FADE_DURATION = 0.45

local function PlayInstallerOpen(frame)
    if not frame then return end
    frame.yuiInstallerClosing = nil
    if GUI2 and GUI2.SlideIn then
        GUI2:SlideIn(frame, {
            owner = Installer,
            key = INSTALLER_ANIMATION_KEY,
            from = "bottom",
            distance = INSTALLER_ANIMATION_DISTANCE,
            duration = INSTALLER_ANIMATION_DURATION,
        })
    else
        frame:Show()
        if frame.SetAlpha then frame:SetAlpha(1) end
    end
end

local function PlayInstallerClose(frame, onClosed)
    local completed = false
    local function FinishClose()
        if completed then return end
        completed = true
        if frame then
            frame.yuiInstallerClosing = nil
        end
        if onClosed then onClosed() end
    end

    if not frame then
        FinishClose()
        return
    end

    frame.yuiInstallerClosing = true
    if frame:IsShown() and GUI2 and GUI2.SlideOut then
        local handle = GUI2:SlideOut(frame, {
            owner = Installer,
            key = INSTALLER_ANIMATION_KEY,
            to = "bottom",
            distance = INSTALLER_ANIMATION_DISTANCE,
            duration = INSTALLER_ANIMATION_DURATION,
            hide = true,
            onFinished = function(_, reason, finished)
                if finished == true then
                    FinishClose()
                elseif finished ~= true then
                    frame.yuiInstallerClosing = nil
                    if YUI.Debug then
                        YUI:Debug("Installer close animation did not finish:", tostring(reason))
                    end
                end
            end,
        })
        if not handle or handle.noop then
            if YUI.Debug then
                local reason = handle and handle.reason or "missing-handle"
                YUI:Debug("Installer close animation skipped:", tostring(reason))
            end
            if frame.Hide then frame:Hide() end
            FinishClose()
        end
    else
        if frame.Hide then frame:Hide() end
        FinishClose()
    end
end

-- 设置状态信息
local function SetStatus(msg, type)
    if not Frame or not Frame.statusText then return end

    Frame.statusText:SetText(msg)

    if type == "error" then
        Frame.statusText:SetTextColor(1, 0.2, 0.2) -- 红色
    elseif type == "success" then
        Frame.statusText:SetTextColor(0.2, 1, 0.2) -- 绿色
    elseif type == "warning" then
        Frame.statusText:SetTextColor(1, 1, 0.2) -- 黄色
    else
        Frame.statusText:SetTextColor(0.8, 0.8, 0.8) -- 灰色
    end
end

local function NotifyLoginFlowDone()
    if not loginFlowDone then return end

    local callback = loginFlowDone
    loginFlowDone = nil
    local ok, err = pcall(callback)
    if not ok then
        print("|cffff0000YUI Installer Error:|r LoginFlow callback failed - " .. tostring(err))
    end
end

local INSTALLER_BUTTON_STYLES = {
    red = {
        surface = { 0.8, 0.1, 0.1, 1 },
        hover = { 0.95, 0.16, 0.16, 1 },
        pressed = { 0.55, 0.06, 0.06, 1 },
        border = { 0.95, 0.25, 0.25, 1 },
    },
    green = {
        surface = { 0.0, 0.5, 0.0, 1 },
        hover = { 0.05, 0.65, 0.08, 1 },
        pressed = { 0.0, 0.34, 0.0, 1 },
        border = { 0.2, 0.85, 0.2, 1 },
    },
    blue = {
        surface = { 0.0, 0.5, 0.8, 1 },
        hover = { 0.05, 0.62, 0.95, 1 },
        pressed = { 0.0, 0.34, 0.55, 1 },
        border = { 0.2, 0.68, 1.0, 1 },
    },
    gray = {
        surface = { 0.3, 0.3, 0.3, 1 },
        hover = { 0.4, 0.4, 0.4, 1 },
        pressed = { 0.2, 0.2, 0.2, 1 },
        border = { 0.5, 0.5, 0.5, 1 },
    },
    uiSelected = {
        surface = { 0.2, 0.4, 0.2, 0.5 },
        hover = { 0.24, 0.48, 0.24, 0.62 },
        pressed = { 0.14, 0.30, 0.14, 0.68 },
        border = { 0, 1, 0, 1 },
    },
    uiHover = {
        surface = { 0.2, 0.2, 0.2, 0.8 },
        hover = { 0.25, 0.25, 0.25, 0.86 },
        pressed = { 0.14, 0.14, 0.14, 0.9 },
        border = { 1, 0.82, 0, 1 },
    },
    uiIdle = {
        surface = { 0.1, 0.1, 0.1, 0.8 },
        hover = { 0.18, 0.18, 0.18, 0.86 },
        pressed = { 0.07, 0.07, 0.07, 0.9 },
        border = { 0, 0, 0, 1 },
    },
}

local function CopyButtonColor(color)
    if type(color) ~= "table" then return color end
    return { color[1], color[2], color[3], color[4] }
end

local function ApplyInstallerButtonStyle(button, style)
    if not button then return end
    if type(style) == "string" then
        style = INSTALLER_BUTTON_STYLES[style]
    end
    if type(style) ~= "table" then return end

    local surface = style.surface or style.normal
    local hover = style.hover or surface
    local pressed = style.pressed or surface
    local border = style.border or "color.border.default"
    local hoverBorder = style.hoverBorder or border
    local pressedBorder = style.pressedBorder or border

    button.gui2SurfaceToken = CopyButtonColor(surface)
    button.gui2HoverSurfaceToken = CopyButtonColor(hover)
    button.gui2PressedSurfaceToken = CopyButtonColor(pressed)
    button.gui2BorderToken = CopyButtonColor(border)
    button.gui2HoverBorderToken = CopyButtonColor(hoverBorder)
    button.gui2PressedBorderToken = CopyButtonColor(pressedBorder)

    if button.RefreshTheme then
        button:RefreshTheme()
    else
        if type(surface) == "table" and button.SetBackdropColor then button:SetBackdropColor(unpack(surface)) end
        if border then GUI2:SetBorderColor(button, border) end
    end
end

local EARLY_RELOAD_LAST_STEP = 2

local function HasPendingEarlyReload()
    if YUI.IsForever then return HasExecutedSteps() end
    for stepIndex = 1, EARLY_RELOAD_LAST_STEP do
        if executedSteps[stepIndex] == true then
            return true
        end
    end
    return false
end

local function RefreshDirectCloseButton()
    local button = Frame and Frame.btnCloseDirectly
    if not button or not button.text then return end

    if HasPendingEarlyReload() then
        button:SetText(LC["installer.text.002"])
        button:SetWidth(104)
        ApplyInstallerButtonStyle(button, "green")
    else
        button:SetText(LC["installer.text.003"])
        button:SetWidth(80)
        ApplyInstallerButtonStyle(button, "red")
    end
    if RefreshForeverActions then RefreshForeverActions() end
end

local function MarkStepExecuted(stepIndex)
    executedSteps[stepIndex] = true
    RefreshDirectCloseButton()
end

local function CreateIcon(content, size, point, texture, showBorder, yoffset)
    local icon = GUI2:CreateTexture(content, { layer = "ARTWORK", texture = texture })
    icon:SetSize(size, size)
    icon:SetPoint(point, content, "CENTER", 0, yoffset or -20) -- 向下移动图标 (20 -> -20)  
    
    if showBorder then
        local iconBg = GUI2:CreateFrame(content, { template = "BackdropTemplate" })
        iconBg:SetAllPoints(icon)
        iconBg:SetFrameLevel(content:GetFrameLevel())
        GUI2:CreateBorder(iconBg)
        icon.iconBg = iconBg
    end

    return icon
end

-- 步骤定义
local layoutStepSelection = {
    importEditMode = true,
    alignSupportedWindows = true,
    partyFrameSide = "right",
    applyAddonProfile = true,
    addonProfileName = nil,
    applyPortraitProfile = true,
    portraitProfileName = nil,
    applyNameplateProfile = true,
    nameplateProfileName = nil,
}

local function ResetLayoutStepSelection()
    layoutStepSelection.applyYUIProfile = nil
    layoutStepSelection.importEditMode = true
    layoutStepSelection.alignSupportedWindows = true
    layoutStepSelection.partyFrameSide = "right"
    layoutStepSelection.applyAddonProfile = true
    layoutStepSelection.addonProfileName = nil
    layoutStepSelection.applyPortraitProfile = true
    layoutStepSelection.portraitProfileName = nil
    layoutStepSelection.applyNameplateProfile = true
    layoutStepSelection.nameplateProfileName = nil
end

local function GetYUIProfileDatabase()
    local service = YUI.DB
    if not service or type(service.GetAceDB) ~= "function" then
        return nil, LC["installer.profiles.yui.unavailable"]
    end
    local ready, db = pcall(service.GetAceDB, service, YUI.ProductId or "suite")
    if not ready then return nil, LC["installer.profiles.yui.unavailable"] end
    if not db or type(db.GetProfiles) ~= "function" or type(db.SetProfile) ~= "function"
        or type(db.GetCurrentProfile) ~= "function" or type(service.SwitchProfile) ~= "function"
    then
        return nil, LC["installer.profiles.yui.unavailable"]
    end
    local ok, profiles = pcall(db.GetProfiles, db)
    if not ok or type(profiles) ~= "table" then
        return nil, LC["installer.profiles.yui.unavailable"]
    end
    for _, name in ipairs(profiles) do
        if name == "YUI" then return db end
    end
    return nil, LC["installer.profiles.yui.missing"]
end

local function ApplyYUIProfile()
    local db, reason = GetYUIProfileDatabase()
    if not db then return false, reason end
    local ok, result, code, detail = pcall(YUI.DB.SwitchProfile, YUI.DB, db, "YUI")
    if not ok then return false, string.format(LC["installer.profiles.yui.failed"], tostring(result)) end
    if result == true then return true end
    if code == "failed" then
        return false, string.format(LC["installer.profiles.yui.failed"], tostring(detail))
    end
    local messages = {
        missing = "installer.profiles.yui.missing", unavailable = "installer.profiles.yui.unavailable",
        busy = "installer.profiles.yui.busy", character = "installer.profiles.yui.character",
        binding = "installer.profiles.yui.binding", interrupted = "installer.profiles.yui.interrupted",
        rollback = "installer.profiles.yui.rollback",
    }
    return false, LC[messages[code] or "installer.profiles.yui.unconfirmed"]
end

local SAM_PROFILE_OPTIONS = {
    {
        addonName = "EllesmereUI",
        profileName = "YUI-Ell",
        labelKey = "installer.text.004",
    },
    {
        addonName = "EnhanceQoL",
        profileName = "YUI-EQoL",
        labelKey = "installer.text.005",
    },
}

local function GetSAMProfileModule()
    if not SystemAPI or type(SystemAPI.IsAddOnLoaded) ~= "function" then
        return nil, nil, LC["installer.text.006"]
    end

    local loadedOk, isLoaded = pcall(SystemAPI.IsAddOnLoaded, "SimpleAddonManager")
    if not loadedOk or isLoaded ~= true then
        return nil, nil, LC["installer.text.006"]
    end

    local SAM = _G.SimpleAddonManager
    if not SAM or type(SAM.GetModule) ~= "function" or type(SAM.GetDb) ~= "function" then
        return nil, nil, LC["installer.text.007"]
    end

    local moduleOk, profileModule = pcall(SAM.GetModule, SAM, "Profile")
    if not moduleOk or type(profileModule) ~= "table"
        or type(profileModule.LoadAddonsFromProfile) ~= "function"
    then
        return nil, nil, LC["installer.text.008"]
    end

    local dbOk, db = pcall(SAM.GetDb, SAM)
    if not dbOk or type(db) ~= "table" or type(db.sets) ~= "table" then
        return nil, nil, LC["installer.text.009"]
    end

    return profileModule, db
end

local function GetMatchedSAMProfile()
    local profileModule, db = GetSAMProfileModule()
    if not profileModule then return nil end

    local options = SAM_PROFILE_OPTIONS
    if YUI and YUI.IsForever then
        options = YUI.Data and YUI.Data:GetData("AddonProfiles") or {}
    end
    for _, option in ipairs(options) do
        if SystemAPI.DoesAddOnExist(option.addonName) and type(db.sets[option.profileName]) == "table" then
            return option
        end
    end
    return nil
end

local function ApplySAMProfile(profileName)
    local profileModule, db, err = GetSAMProfileModule()
    if not profileModule then return false, err end
    if type(db.sets[profileName]) ~= "table" then
        return false, LC["installer.text.010"] .. tostring(profileName)
    end

    local ok, applyErr = pcall(profileModule.LoadAddonsFromProfile, profileModule, profileName, false)
    if not ok then
        return false, LC["installer.text.011"] .. tostring(applyErr)
    end
    if not SystemAPI or type(SystemAPI.SaveAddOns) ~= "function" or SystemAPI.SaveAddOns() ~= true then
        return false, LC["installer.text.012"]
    end
    return true
end

local function GetPortraitProfileOption()
    if not YUI.IsForever then return nil end
    local option = YUI.Data and YUI.Data:GetData("PortraitProfile")
    if type(option) ~= "table" or not SystemAPI.DoesAddOnExist(option.addonName) then return nil end
    if SystemAPI.IsAddOnLoadedSafe(option.addonName) then
        local db = _G.BLINKIISPORTRAITS and _G.BLINKIISPORTRAITS.db
        if not db or type(db.GetProfiles) ~= "function" or type(db.SetProfile) ~= "function"
            or type(db.GetCurrentProfile) ~= "function" then return nil end
        local ok, profiles = pcall(db.GetProfiles, db)
        if ok and type(profiles) == "table" then
            for _, name in ipairs(profiles) do
                if name == option.profileName then return option end
            end
        end
    else
        local saved = _G.BlinkiisPortraitsDB
        if saved and type(saved.profiles) == "table" and type(saved.profiles[option.profileName]) == "table" then
            return option
        end
    end
end

local function HasNameplateProfile()
    if not SystemAPI.DoesAddOnExist("Platynator") or not SystemAPI.IsAddOnLoadedSafe("Platynator") then
        return false
    end
    local config = _G.PLATYNATOR_CONFIG
    return type(config) == "table" and type(config.Profiles) == "table"
        and type(config.Profiles.YUI) == "table"
end

local function ApplyNameplateProfile()
    if not HasNameplateProfile() then return false end
    -- 此插件没有公开切换 API；写入角色绑定，由向导结束重载后读取。
    _G.PLATYNATOR_CURRENT_PROFILE = "YUI"
    return true
end

local portraitBindingOwner = {}
local portraitBindingDB

local function PersistPortraitProfile(db)
    local charKey = db and db.keys and db.keys.char
    local keys = db and db.sv and db.sv.profileKeys
    if type(charKey) ~= "string" or charKey == "" or type(keys) ~= "table" then return false end
    local current = db:GetCurrentProfile()
    if type(current) ~= "string" or current == "" then return false end
    if YUI.DB:PersistCurrentProfile(db, "BlinkiisPortraitsDB") ~= true then return false end
    -- 共享库升级后 SetProfile 的写入键可能与创建数据库时的键不同。
    keys[charKey] = current
    return true
end

local function OnPortraitProfileChanged(_, db)
    local ok, persisted = pcall(PersistPortraitProfile, db)
    if not ok or not persisted then YUI:Print(LC["installer.profiles.portrait.unconfirmed"]) end
end

local function EnsurePortraitProfilePersistence()
    local addon = _G.BLINKIISPORTRAITS
    local db = addon and addon.db
    if not db or type(db.RegisterCallback) ~= "function" or type(db.UnregisterCallback) ~= "function" then
        return false
    end
    if portraitBindingDB == db then return true end
    if portraitBindingDB then
        portraitBindingDB.UnregisterCallback(portraitBindingOwner, "OnProfileChanged")
        portraitBindingDB = nil
    end
    db.RegisterCallback(portraitBindingOwner, "OnProfileChanged", OnPortraitProfileChanged)
    portraitBindingDB = db
    return true
end

local function ApplyPortraitProfile(profileName)
    local addon = _G.BLINKIISPORTRAITS
    local db = addon and addon.db
    if not db or type(db.GetProfiles) ~= "function" or type(db.SetProfile) ~= "function"
        or type(db.GetCurrentProfile) ~= "function"
    then
        return false, LC["installer.profiles.portrait.unavailable"]
    end
    local ok, profiles = pcall(db.GetProfiles, db)
    local exists = false
    if ok and type(profiles) == "table" then
        for _, name in ipairs(profiles) do
            if name == profileName then exists = true; break end
        end
    end
    if not exists then
        return false, string.format(LC["installer.profiles.portrait.missing"], profileName)
    end
    if not EnsurePortraitProfilePersistence() then return false, LC["installer.profiles.portrait.unavailable"] end
    local currentOK, current = pcall(db.GetCurrentProfile, db)
    if not currentOK or current ~= profileName then
        local applied, err = pcall(db.SetProfile, db, profileName)
        if not applied then
            return false, string.format(LC["installer.profiles.portrait.failed"], tostring(err))
        end
    end
    currentOK, current = pcall(db.GetCurrentProfile, db)
    if not currentOK or current ~= profileName then
        return false, LC["installer.profiles.portrait.unconfirmed"]
    end
    local persisted, result = pcall(PersistPortraitProfile, db)
    if not persisted or result ~= true then
        return false, LC["installer.profiles.portrait.unconfirmed"]
    end
    return true
end

local function GetInstallerLayoutCapabilities()
    local layout = YUI.InstallerLayoutAligner or YUI.EllesmereDamageMetersLayout
    if not layout or type(layout.GetCapabilities) ~= "function" then
        return nil, { any = false, hasPartyFrames = false }
    end
    local ok, capabilities = pcall(layout.GetCapabilities, layout)
    if not ok or type(capabilities) ~= "table" then
        return layout, { any = false, hasPartyFrames = false }
    end
    return layout, capabilities
end

local ALIGNMENT_FAILURE_MESSAGES = {
    ["not-loaded"] = "installer.text.013",
    ["not-ready"] = "installer.text.014",
    ["no-windows"] = "installer.text.015",
    ["geometry-unavailable"] = "installer.text.016",
    ["parent-geometry-unavailable"] = "installer.text.017",
    ["live-refresh-failed"] = "installer.text.018",
    ["anchor-reapply-failed"] = "installer.text.019",
    ["root-position-failed"] = "installer.text.020",
    ["live-position-failed"] = "installer.text.021",
    ["unlock-refresh-failed"] = "installer.text.022",
    ["combat-defer-failed"] = "installer.text.023",
    ["edit-mode-sync-failed"] = "installer.text.024",
    ["layout-refresh-failed"] = "installer.text.025",
}

local function DescribeAlignmentFailures(summary)
    local failed = type(summary) == "table" and summary.failed
    if type(failed) ~= "table" or #failed == 0 then
        return LC["installer.text.026"]
    end
    local descriptions = {}
    for _, item in ipairs(failed) do
        local label = item.label or item.id or LC["installer.text.027"]
        local reasonKey = ALIGNMENT_FAILURE_MESSAGES[item.reason]
        local reason = reasonKey and LC[reasonKey] or tostring(item.reason or LC["installer.text.028"])
        descriptions[#descriptions + 1] = string.format(LC["installer.text.101"], label, reason)
    end
    return table.concat(descriptions, LC["installer.text.102"])
end

local function ApplyYUIEditModeLayout()
    if YUI.IsForever and not YUI.EditMode:CanModifyLayouts() then return false end
    local latestName, latestVersion = YUI.EditMode:GetLatestYUILayout()
    local currentName = YUI.EditMode:GetCurrentLayoutName()
    if latestName and currentName == latestName then
        return true
    end

    local layouts = YUI.EditMode:GetAllLayouts() or {}
    if YUI.IsForever then
        if YUI.EditMode:GetCurrentLayoutVersion(currentName) >= latestVersion then return true end
        local bestName, bestVersion = nil, latestVersion - 1
        for _, layout in ipairs(layouts) do
            local version = YUI.EditMode:GetCurrentLayoutVersion(layout.layoutName)
            if version > bestVersion then bestName, bestVersion = layout.layoutName, version end
        end
        if bestName then return YUI.EditMode:SwitchLayoutByName(bestName) == true end
    end
    for _, layout in ipairs(layouts) do
        if latestName and layout.layoutName == latestName then
            return YUI.EditMode:SwitchLayoutByName(latestName) == true
        end
    end

    return YUI.EditMode:ImportDefaultLayout() == true
end

-- Step 1: 界面布局
table.insert(steps, {
    titleKey = "installer.text.029",
    descKey = "installer.text.030",
    setup = function(content)
        local _, layoutCapabilities = GetInstallerLayoutCapabilities()
        local canAlignSupportedWindows = layoutCapabilities.any == true
        local hasPartyFrames = layoutCapabilities.hasPartyFrames == true
        local yuiProfileDB = GetYUIProfileDatabase()
        if layoutStepSelection.applyYUIProfile == nil or not yuiProfileDB then
            layoutStepSelection.applyYUIProfile = yuiProfileDB ~= nil
        end
        local matchedSAMProfile = GetMatchedSAMProfile()
        layoutStepSelection.addonProfileName = matchedSAMProfile and matchedSAMProfile.profileName or nil
        local portraitProfile = GetPortraitProfileOption()
        layoutStepSelection.portraitProfileName = portraitProfile and portraitProfile.profileName or nil
        local hasNameplateProfile = HasNameplateProfile()
        layoutStepSelection.nameplateProfileName = hasNameplateProfile and "YUI" or nil
        local optionCount = 1 + (yuiProfileDB and 1 or 0)
            + (canAlignSupportedWindows and 1 or 0)
            + (hasPartyFrames and 1 or 0)
            + (matchedSAMProfile and 1 or 0)
            + (portraitProfile and 1 or 0)
            + (hasNameplateProfile and 1 or 0)
        local optionsHeight = optionCount * 28 + math.max(0, optionCount - 1) * 2
        local layoutGroup = GUI2:CreateFrame(content)
        local options = GUI2:CreateFrame(layoutGroup)
        options:SetSize(225, optionsHeight)
        if YUI.IsForever then
            layoutGroup:SetSize(225, optionsHeight)
            layoutGroup:SetPoint("TOP", content, "TOP", 0, optionCount > 6 and -40 or -60)
            options:SetPoint("TOP", layoutGroup, "TOP", 0, 0)
        else
            local iconSize = optionCount > 5 and 32 or optionCount > 4 and 48 or 72
            layoutGroup:SetSize(225, iconSize + 12 + optionsHeight)
            layoutGroup:SetPoint("TOP", content, "TOP", 0, -55)
            if optionCount > 4 then
                layoutGroup:SetPoint("TOP", content, "TOP", 0, optionCount > 5 and -24 or -40)
            end
            local icon = CreateIcon(layoutGroup, iconSize, "CENTER", Assets:Core("images\\icons\\editmode.png"), false, 0)
            icon:ClearAllPoints()
            icon:SetPoint("TOP", layoutGroup, "TOP", 0, 0)
            options:SetPoint("TOP", icon, "BOTTOM", 0, -12)
        end

        local function RefreshExecuteAvailability()
            local enabled = layoutStepSelection.applyYUIProfile or layoutStepSelection.importEditMode
                or (canAlignSupportedWindows and layoutStepSelection.alignSupportedWindows)
                or (matchedSAMProfile and layoutStepSelection.applyAddonProfile)
                or (portraitProfile and layoutStepSelection.applyPortraitProfile)
                or (hasNameplateProfile and layoutStepSelection.applyNameplateProfile)
            content.disableExecute = not enabled
            if currentStep ~= 1 or not Frame or not Frame.btnExecute then return end
            if enabled then
                Frame.btnExecute:Enable()
                ApplyInstallerButtonStyle(Frame.btnExecute, "green")
            else
                Frame.btnExecute:Disable()
                ApplyInstallerButtonStyle(Frame.btnExecute, "gray")
            end
        end

        local checkboxRows, layoutRows = {}, {}
        if yuiProfileDB then
            local applyYUIProfile = GUI2.Form:CreateCheckbox(options, {
                text = LC["installer.profiles.yui"],
                autoWidth = true,
                height = 28,
                checked = layoutStepSelection.applyYUIProfile,
                tooltip = LC["installer.profiles.yui.tooltip"],
                onClick = function(_, checked)
                    layoutStepSelection.applyYUIProfile = checked == true
                    RefreshExecuteAvailability()
                end,
            })
            content.applyYUIProfileCheckbox = applyYUIProfile
            checkboxRows[#checkboxRows + 1] = applyYUIProfile
            layoutRows[#layoutRows + 1] = { frame = applyYUIProfile, checkbox = true }
        end

        local importEditMode = GUI2.Form:CreateCheckbox(options, {
            text = LC["installer.text.031"],
            autoWidth = true,
            height = 28,
            checked = layoutStepSelection.importEditMode,
            tooltip = LC["installer.text.032"],
            onClick = function(_, checked)
                layoutStepSelection.importEditMode = checked == true
                RefreshExecuteAvailability()
            end,
        })
        content.importEditModeCheckbox = importEditMode
        checkboxRows[#checkboxRows + 1] = importEditMode
        layoutRows[#layoutRows + 1] = { frame = importEditMode, checkbox = true }

        if canAlignSupportedWindows then
            local alignSupportedWindows = GUI2.Form:CreateCheckbox(options, {
                text = LC["installer.text.033"],
                autoWidth = true,
                height = 28,
                checked = layoutStepSelection.alignSupportedWindows,
                tooltip = LC["installer.text.034"],
                onClick = function(_, checked)
                    layoutStepSelection.alignSupportedWindows = checked == true
                    RefreshExecuteAvailability()
                end,
            })
            content.alignSupportedWindowsCheckbox = alignSupportedWindows
            checkboxRows[#checkboxRows + 1] = alignSupportedWindows
            layoutRows[#layoutRows + 1] = { frame = alignSupportedWindows, checkbox = true }
        end

        if matchedSAMProfile then
            local applyAddonProfile = GUI2.Form:CreateCheckbox(options, {
                text = LC[matchedSAMProfile.labelKey],
                autoWidth = true,
                height = 28,
                checked = layoutStepSelection.applyAddonProfile,
                tooltip = LC["installer.text.035"] .. matchedSAMProfile.profileName .. LC["installer.text.036"],
                onClick = function(_, checked)
                    layoutStepSelection.applyAddonProfile = checked == true
                    RefreshExecuteAvailability()
                end,
            })
            content.applyAddonProfileCheckbox = applyAddonProfile
            checkboxRows[#checkboxRows + 1] = applyAddonProfile
            layoutRows[#layoutRows + 1] = { frame = applyAddonProfile, checkbox = true }
        end

        if portraitProfile then
            local applyPortraitProfile = GUI2.Form:CreateCheckbox(options, {
                text = LC["installer.profiles.portrait"],
                autoWidth = true,
                height = 28,
                checked = layoutStepSelection.applyPortraitProfile,
                tooltip = string.format(LC["installer.profiles.portrait.tooltip"], portraitProfile.profileName),
                onClick = function(_, checked)
                    layoutStepSelection.applyPortraitProfile = checked == true
                    RefreshExecuteAvailability()
                end,
            })
            content.applyPortraitProfileCheckbox = applyPortraitProfile
            checkboxRows[#checkboxRows + 1] = applyPortraitProfile
            layoutRows[#layoutRows + 1] = { frame = applyPortraitProfile, checkbox = true }
        end

        if hasNameplateProfile then
            local applyNameplateProfile = GUI2.Form:CreateCheckbox(options, {
                text = LC["installer.profiles.nameplate"],
                autoWidth = true,
                height = 28,
                checked = layoutStepSelection.applyNameplateProfile,
                tooltip = LC["installer.profiles.nameplate.tooltip"],
                onClick = function(_, checked)
                    layoutStepSelection.applyNameplateProfile = checked == true
                    RefreshExecuteAvailability()
                end,
            })
            content.applyNameplateProfileCheckbox = applyNameplateProfile
            checkboxRows[#checkboxRows + 1] = applyNameplateProfile
            layoutRows[#layoutRows + 1] = { frame = applyNameplateProfile, checkbox = true }
        end

        local checkboxBoxWidth = 18
        local checkboxLabelGap = 8
        local checkboxLeadingWidth = checkboxBoxWidth + checkboxLabelGap
        local textColumnWidth = 0
        for _, row in ipairs(checkboxRows) do
            local textWidth = row.text and row.text:GetStringWidth() or 0
            textColumnWidth = math.max(textColumnWidth, textWidth)
        end
        local rowWidth = checkboxLeadingWidth + textColumnWidth

        if hasPartyFrames then
            local partySideChoice = GUI2.Form:CreateBinaryChoice(options, {
                width = rowWidth,
                height = 28,
                values = {
                    { text = LC["installer.text.037"], value = "left" },
                    { text = LC["installer.text.038"], value = "right" },
                },
                get = function()
                    return layoutStepSelection.partyFrameSide
                end,
                set = function(value)
                    layoutStepSelection.partyFrameSide = value == "left" and "left" or "right"
                end,
            })
            content.partySideChoice = partySideChoice
            layoutRows[#layoutRows + 1] = { frame = partySideChoice }
        end

        options:SetWidth(rowWidth)
        for index, rowInfo in ipairs(layoutRows) do
            local row = rowInfo.frame
            row:ClearAllPoints()
            if rowInfo.checkbox then
                row:SetWidth(rowWidth)
                row.text:ClearAllPoints()
                row.text:SetPoint("LEFT", row.box, "RIGHT", checkboxLabelGap, 0)
                row.text:SetWidth(textColumnWidth)
                row.text:SetJustifyH("LEFT")
            end
            if index == 1 then
                row:SetPoint("TOP", options, "TOP", 0, 0)
            else
                row:SetPoint("TOP", layoutRows[index - 1].frame, "BOTTOM", 0, -2)
            end
        end

        RefreshExecuteAvailability()
        
        -- 检查是否存在 YUI 布局
        if C_EditMode and C_EditMode.GetLayouts then
            -- 1. 检查布局数量限制
            local accCount, isFull, hasYuiLayout = YUI.EditMode:CheckLayoutLimit()
            local currentLayoutName = YUI.EditMode:GetCurrentLayoutName()
            local latestName, latestVer = YUI.EditMode:GetLatestYUILayout()
            local currentVer = YUI.EditMode:GetCurrentLayoutVersion(currentLayoutName)
            
            if isFull and not hasYuiLayout then
                    SetStatus(string.format(LC["installer.text.039"], accCount), "error")
                    
                    -- 监听事件自动刷新
                    if not content.eventListener then
                        content.eventListener = YUI.Event:On("EDIT_MODE_LAYOUTS_UPDATED", function()
                            if currentStep == 1 and Frame and Frame:IsShown() then
                                UpdateInstallerUI()
                            end
                        end)
                    end
                    
                    local btnManualDelete = GUI2:CreateButton(content, LC["installer.text.040"], 140, 30)
                    btnManualDelete:SetPoint("BOTTOMRIGHT", content, "BOTTOM", -10, 0)
                    btnManualDelete:SetScript("OnClick", function()
                        if EditModeManagerFrame then
                            if not EditModeManagerFrame:IsShown() then
                                ShowUIPanel(EditModeManagerFrame)
                                -- 把编辑模式Frame的层级提高
                                EditModeManagerFrame:SetFrameLevel(content:GetFrameLevel() + 4)
                            end
                        else
                            -- 尝试打开（有些时候可能需要通过 SlashCmd）
                            C_EditMode.OnEditModeEnter() 
                        end
                    end)
                    
                    local btnAutoDelete = GUI2:CreateButton(content, LC["installer.text.041"], 140, 30)
                    btnAutoDelete:SetPoint("BOTTOMLEFT", content, "BOTTOM", 10, 0)
                    ApplyInstallerButtonStyle(btnAutoDelete, "red")
                    btnAutoDelete:SetScript("OnClick", function()
                        if YUI.EditMode:DeleteNonYUILayout() then
                            UpdateInstallerUI() -- 重新渲染当前步骤
                        end
                    end)
                    
                    -- 禁用执行按钮（将在 UpdateInstallerUI 中处理，这里先标记）
                    content.disableExecute = true
                    return
            end
            
            if hasYuiLayout then
                if YUI.EditMode:IsYUILayout(currentLayoutName) then
                    if currentVer >= 0 and currentVer < latestVer then
                        SetStatus(LC["installer.text.042"], "warning")
                    else
                        SetStatus(LC["installer.text.043"], "success")
                    end
                else
                    SetStatus(LC["installer.text.044"], "error")
                end
            end
        end
    end,
    execute = function()
        if (YUI.IsForever or layoutStepSelection.applyYUIProfile) and InCombatLockdown() then
            SetStatus(LC["installer.settings.combat.blocked"], "warning")
            return false
        end
        if YUI.IsForever and layoutStepSelection.importEditMode then
            local ready, reason = YUI.EditMode:CanModifyLayouts()
            if not ready then
                SetStatus(LC[reason == "editing" and "installer.layout.editing" or "installer.layout.not_ready"], "warning")
                return false
            end
            YUI.EditMode.changedByInstaller = false
        end
        local requestedYUIProfile = layoutStepSelection.applyYUIProfile and GetYUIProfileDatabase() ~= nil
        local requestedEditMode = layoutStepSelection.importEditMode
        local layoutAdapter, layoutCapabilities = GetInstallerLayoutCapabilities()
        local requestedAlignment = layoutStepSelection.alignSupportedWindows
            and layoutCapabilities.any == true
        local matchedSAMProfile = GetMatchedSAMProfile()
        local requestedAddonProfile = layoutStepSelection.applyAddonProfile and matchedSAMProfile ~= nil
            and matchedSAMProfile.profileName == layoutStepSelection.addonProfileName
        local requestedPortraitProfile = layoutStepSelection.applyPortraitProfile
            and layoutStepSelection.portraitProfileName ~= nil
        local requestedNameplateProfile = false
        local editModeApplied = not requestedEditMode
        local alignmentApplied = not requestedAlignment
        local alignmentSummary
        local addonProfileApplied = not requestedAddonProfile
        local portraitProfileQueued = false
        if requestedYUIProfile then
            local applied, profileError = ApplyYUIProfile()
            if not applied then
                SetStatus(profileError, "error")
                return false
            end
            MarkStepExecuted(currentStep)
        end
        if requestedAddonProfile then
            local profileError
            addonProfileApplied, profileError = ApplySAMProfile(layoutStepSelection.addonProfileName)
            if not addonProfileApplied then
                SetStatus(profileError or LC["installer.text.045"], "error")
                return false
            end
            MarkStepExecuted(currentStep)
        end
        local portraitProfile = GetPortraitProfileOption()
        requestedPortraitProfile = requestedPortraitProfile and portraitProfile ~= nil
            and portraitProfile.profileName == layoutStepSelection.portraitProfileName
        if requestedPortraitProfile then
            local applied, profileError, queued = ApplyOrQueuePortraitProfile(layoutStepSelection.portraitProfileName)
            if not applied then
                SetStatus(profileError, "error")
                return false
            end
            portraitProfileQueued = queued == true
            MarkStepExecuted(currentStep)
        end
        if layoutStepSelection.applyNameplateProfile and layoutStepSelection.nameplateProfileName
            and HasNameplateProfile() then
            requestedNameplateProfile = ApplyNameplateProfile()
            if requestedNameplateProfile then MarkStepExecuted(currentStep) end
        end
        if requestedEditMode then
            editModeApplied = ApplyYUIEditModeLayout()
            if YUI.IsForever and YUI.EditMode.changedByInstaller then MarkStepExecuted(currentStep) end
        end
        if requestedAlignment then
            local callOK, applied, summary = pcall(layoutAdapter.Apply, layoutAdapter, {
                partySide = layoutStepSelection.partyFrameSide,
            })
            alignmentApplied = callOK and applied == true
            alignmentSummary = callOK and summary or {
                failed = {
                    { label = LC["installer.text.046"], reason = applied },
                },
            }
        end

        if requestedEditMode and editModeApplied then
            local global = GetYUIGlobalDB()
            if global then
                global.ignoreYUISwitchPrompt = false
            end
        end

        local anyRequested = requestedYUIProfile or requestedEditMode or requestedAlignment or requestedAddonProfile
            or requestedPortraitProfile or requestedNameplateProfile
        local succeeded = anyRequested and editModeApplied and alignmentApplied and addonProfileApplied
        if succeeded and portraitProfileQueued then
            SetStatus(LC["installer.profiles.portrait.pending"], "warning")
        elseif succeeded and requestedNameplateProfile then
            SetStatus(LC["installer.profiles.nameplate.pending"], "warning")
        elseif succeeded and (requestedYUIProfile or requestedPortraitProfile) then
            SetStatus(LC["installer.profiles.applied"], "success")
        elseif succeeded and requestedAddonProfile then
            SetStatus(LC["installer.text.047"], "success")
        elseif succeeded and requestedEditMode and requestedAlignment then
            SetStatus(LC["installer.text.048"], "success")
        elseif succeeded and requestedEditMode then
            SetStatus(LC["installer.text.049"] .. LAYOUT_NAME .. LC["installer.text.050"], "success")
        elseif succeeded then
            SetStatus(LC["installer.text.051"], "success")
        elseif anyRequested then
            local failures = {}
            if requestedEditMode and not editModeApplied then
                failures[#failures + 1] = LC["installer.text.052"]
            end
            if requestedAlignment and not alignmentApplied then
                failures[#failures + 1] = DescribeAlignmentFailures(alignmentSummary)
            end
            local anyApplied = (requestedEditMode and editModeApplied)
                or requestedYUIProfile
                or (requestedAlignment and alignmentApplied)
                or (requestedAddonProfile and addonProfileApplied)
                or requestedPortraitProfile
                or requestedNameplateProfile
            SetStatus(
                LC["installer.text.053"] .. table.concat(failures, LC["installer.text.102"]),
                anyApplied and "warning" or "error"
            )
        else
            SetStatus(LC["installer.text.054"], "warning")
        end
        return succeeded
    end
})

-- Step 2: 冷却管理器
if YUI.IsRetail then
table.insert(steps, {
    titleKey = "installer.text.055",
    descKey = "installer.text.056",
    setup = function(content)
        local function ReadCooldownState()
            local cm = YUI.CooldownMgr
            if not cm then return nil, LC["installer.text.064"] end
            local ok, versions, reason = pcall(cm.GetInstalledVersions, cm)
            if not ok then
                YUI:Debug(tostring(versions))
                return nil, LC["installer.cooldown.read_failed"]
            end
            if not versions then return nil, reason end
            local checked, count, isFull, needed, limitError = pcall(cm.CheckProfileLimit, cm)
            if not checked then
                YUI:Debug(tostring(count))
                return nil, LC["installer.cooldown.read_failed"]
            end
            if count == nil then return nil, limitError end
            return versions, nil, count, isFull, needed
        end

        local installedVersions, readError, count, isFull, netNewNeeded = ReadCooldownState()
        if not installedVersions then
            content.disableExecute = true
            local message = GUI2:CreateText(content, readError or LC["installer.cooldown.pending"], 14)
            message:SetPoint("CENTER", content, "CENTER", 0, 0)
            local retry = GUI2:CreateButton(content, LC["installer.cooldown.retry"], 140, 30)
            retry:SetPoint("TOP", message, "BOTTOM", 0, -20)
            retry:SetScript("OnClick", UpdateInstallerUI)
            SetStatus(readError or LC["installer.cooldown.pending"], "warning")
            local attempts = 0
            local function CheckReady()
                content.refreshTimer = nil
                if not Frame or not Frame:IsShown() or Frame.currentContent ~= content then return end
                local versions, reason = ReadCooldownState()
                if versions then UpdateInstallerUI(); return end
                attempts = attempts + 1
                message:SetText(reason or LC["installer.cooldown.pending"])
                SetStatus(reason or LC["installer.cooldown.pending"], "warning")
                if attempts < 10 then content.refreshTimer = C_Timer.NewTimer(0.5, CheckReady) end
            end
            content.refreshTimer = C_Timer.NewTimer(0.5, CheckReady)
            return
        end
        -- 显示当前职业所有专精图标
        local icons = YUI.CooldownMgr:GetClassSpecIcons()
        local numIcons = #icons
        local iconSize = 38
        local gap = 20
        local totalWidth = (numIcons * iconSize) + ((numIcons - 1) * gap)
        local startX = -(totalWidth / 2) + (iconSize / 2)
        
        -- 获取版本信息
        local _, cls = UnitClass("player")
        local cdCfg = YUI.Data and YUI.Data:GetData("CooldownMgr", cls and cls:upper()) or {}
        local latestVersions = {}
        if cdCfg then
            for _, info in pairs(cdCfg) do
                latestVersions[info.Name] = info.Version
            end
        end
        
        for i, specInfo in ipairs(icons) do
            local specID, specNameRaw, iconTexture = unpack(specInfo)
            local specName = cdCfg[specID] and cdCfg[specID].Name or "???"
            
            local icon = GUI2:CreateTexture(content, { layer = "ARTWORK", texture = iconTexture })
            icon:SetSize(iconSize * 1.15, iconSize * 1.15) -- 放大以填充圆形遮罩
            -- 图标上移 20px (-20 -> 0)
            icon:SetPoint("CENTER", content, "CENTER", startX + (i-1)*(iconSize+gap), 0)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- 去除图标默认边框 

            -- 图标边框
            local iconBg = GUI2:CreateFrame(content, { template = "BackdropTemplate" })
            iconBg:SetAllPoints(icon)
            iconBg:SetFrameLevel(content:GetFrameLevel())
            GUI2:CreateBorder(iconBg)
            icon.iconBg = iconBg
            
            -- 版本状态文本
            local statusText = GUI2:CreateText(content, "", 12)
            statusText:SetPoint("TOP", icon, "BOTTOM", 0, -5)
            
            local installedVer = installedVersions[specName]
            local latestVer = latestVersions[specName] or 0
            
            if not installedVer then
                statusText:SetText(LC["installer.text.057"])
                statusText:SetTextColor(1, 0.2, 0.2) -- 红色
            elseif installedVer < latestVer then
                statusText:SetText(LC["installer.text.058"])
                statusText:SetTextColor(0.2, 1, 0.2) -- 绿色
            else
                -- 已经是最新，不显示文本
                statusText:SetText(YUI.F:GetAtlasString("Adventures-Checkmark", 16))
            end
        end

        -- 检查配置限制
        if isFull then
            local deleteCount = 0

            if netNewNeeded > 0  then
                -- 简化提示：需要 X 个位置
                SetStatus(string.format(LC["installer.text.059"], count, netNewNeeded), "error")
                deleteCount = count + netNewNeeded - 5
            else
                -- 特殊情况：配置已经超过上限，但是里面又有自己的配置
                SetStatus(LC["installer.text.060"], "error")
                deleteCount = count - 5
            end
                
            -- 定时检查自动刷新
            if not content.refreshTimer then
                content.refreshTimer = C_Timer.NewTicker(1, function()
                YUI:Debug(LC["installer.text.061"])
                if currentStep == 2 and Frame and Frame:IsShown() and Frame.currentContent == content then
                    local _, _, newCount, newIsFull = ReadCooldownState()
                    -- 读取失败时回到有明确提示的等待页。
                    if newCount == nil or not newIsFull or newCount < count then
                        UpdateInstallerUI()
                    end
                else
                    -- 停止计时器
                    if content.refreshTimer then content.refreshTimer:Cancel() end
                end
                end)
            end

            local btnManualDelete = GUI2:CreateButton(content, LC["installer.text.040"], 140, 30)
            btnManualDelete:SetPoint("TOPRIGHT", content, "CENTER", -10, -60)
            btnManualDelete:SetScript("OnClick", function()
                if CooldownViewerSettings then
                    CooldownViewerSettings:Show()
                else
                    C_AddOns.LoadAddOn("Blizzard_CooldownViewer")
                    if CooldownViewerSettings then CooldownViewerSettings:Show() end
                end

                -- 把冷却管理器Frame的层级提高
                if CooldownViewerSettings then
                CooldownViewerSettings:SetFrameStrata("DIALOG")
                CooldownViewerSettings:SetFrameLevel(content:GetFrameLevel() + 1)
                end
            end)
            
            local btnAutoDelete = GUI2:CreateButton(content, LC["installer.text.062"] .. deleteCount .. LC["installer.text.063"], 140, 30)
            btnAutoDelete:SetPoint("TOPLEFT", content, "CENTER", 10, -60)
            ApplyInstallerButtonStyle(btnAutoDelete, "red")
            btnAutoDelete:SetScript("OnClick", function()
                local removed, reason = YUI.CooldownMgr:DeleteNonYUIProfiles(deleteCount)
                if removed > 0 then
                    UpdateInstallerUI()
                elseif reason then
                    SetStatus(reason, "error")
                end
            end)
            
            content.disableExecute = true
        end
    end,
    execute = function()
        if not YUI.CooldownMgr then
            SetStatus(LC["installer.text.064"], "error")
            return false
        end

        local succ, msg = YUI.CooldownMgr:ImportClassCooldowns()
        if succ then
            C_CVar.SetCVar("cooldownViewerEnabled", "1")
            SetStatus(msg or LC["installer.text.065"], "success")
            return true
        else
            SetStatus(LC["installer.text.066"] ..
                            (msg or LC["installer.text.028"]), "error")
            return false
        end
    end
})

-- Step 3: 中央资源条 (仅当 SenseiClassResourceBar 加载时显示)
end

if YUI.IsForever and YUI.InstallerSettings then
    table.insert(steps, {
        titleKey = "installer.settings.title",
        descKey = "installer.settings.description",
        setup = function(content)
            local function RefreshSelection()
                content.disableExecute = not YUI.InstallerSettings:HasSelection()
                if Frame and Frame.currentContent == content and RefreshForeverActions then
                    SetStatus("", "info")
                    RefreshForeverActions()
                end
            end
            YUI.InstallerSettings:BuildPage(content, RefreshSelection)
            RefreshSelection()
        end,
        execute = function()
            local ok, result, reason = YUI.InstallerSettings:Apply()
            if Frame.currentContent and Frame.currentContent.RefreshSettingsFeedback then
                Frame.currentContent.RefreshSettingsFeedback()
            end
            if result.applied > 0 or result.changed then MarkStepExecuted(currentStep) end
            if reason == "combat" then
                SetStatus(LC["installer.settings.combat.blocked"], "warning")
            elseif #result.failed > 0 then
                SetStatus(string.format(LC["installer.settings.failed"], result.applied, #result.failed), "warning")
            elseif ok then
                SetStatus(string.format(LC["installer.settings.applied"], result.applied), "success")
            else
                SetStatus(LC["installer.settings.preserve"], "info")
            end
            return ok
        end,
    })
end

if YUI.SCRB and C_AddOns.IsAddOnLoaded("SenseiClassResourceBar")
    and (not YUI.IsForever or (YUI.Data and YUI.Data:GetData("SCRB"))) then
    table.insert(steps, {
        titleKey = "installer.text.067",
        descKey = "installer.text.068",
        setup = function(content)
            -- local icon = content:CreateTexture(nil, "ARTWORK")
            -- icon:SetSize(398, 84) -- 调整为长方形比例
            -- icon:SetPoint("CENTER", content, "CENTER", 0, -20)
            -- -- 使用新的占位图
            -- icon:SetTexture(Assets:Core("images\\icons\\resbar.png"))
            
            -- -- 如果没有图片，回退到默认图标
            -- if not icon:GetTexture() then
            --      icon:SetTexture("Interface\\Icons\\Inv_Hammer_01")
            --      icon:SetSize(64, 64)
            -- end

            CreateIcon(content, 128, "CENTER", Assets:Core("images\\icons\\resbar.png"), false, -30)

        end,
        execute = function()
            local succ, err = YUI.SCRB:ImportDefaultProfile()
            if succ then
                SetStatus(LC["installer.text.069"], "success")
                YUI.SCRB:fullUpdateBars()
                return true
            else
                SetStatus(LC["installer.text.070"] ..
                                (err or LC["installer.text.028"]), "error")
                return false
            end
        end
    })
end

-- INSTALLER_COMPLETION_STEP
-- 最后一步：安装完成
table.insert(steps, {
    titleKey = "installer.text.071",
    descKey = "installer.text.072",
    descColorKey = "color.state.success",
    setup = function(content)
        local messageGroup = GUI2:CreateFrame(content)
        messageGroup:SetSize(520, 96)
        messageGroup:SetPoint("TOP", Frame.stepDesc, "BOTTOM", 0, -36)

        local thanksText = GUI2:CreateText(messageGroup, LC["installer.text.073"], 14, "color.text.secondary")
        thanksText:SetPoint("TOP", 0, 0)

        local philosophyText = GUI2:CreateText(messageGroup, LC["installer.text.074"], 14, "color.text.secondary")
        philosophyText:SetPoint("TOP", thanksText, "BOTTOM", 0, -10)

        local wishText = GUI2:CreateText(messageGroup, LC["installer.text.075"], 14, "color.text.secondary")
        wishText:SetPoint("TOP", philosophyText, "BOTTOM", 0, -8)

        local authorText = GUI2:CreateText(messageGroup, LC["installer.text.076"], 12, "color.text.secondary")
        authorText:SetPoint("TOP", wishText, "BOTTOM", 80, -12)

        local sloganGroup = GUI2:CreateFrame(content)
        sloganGroup:SetSize(420, 58)
        sloganGroup:SetPoint("TOP", messageGroup, "BOTTOM", 0, -28)

        local sloganCN = GUI2:CreateText(
            sloganGroup,
            YUI.F:GetGradientText(LC["installer.text.077"], INSTALLER_SLOGAN_GOLD_START, INSTALLER_SLOGAN_GOLD_END),
            22,
            "color.text.primary"
        )
        sloganCN:SetPoint("TOP", 0, 0)

        local sloganEN = GUI2:CreateText(
            sloganGroup,
            YUI.F:GetGradientText("Less is more", INSTALLER_SLOGAN_GOLD_START, INSTALLER_SLOGAN_GOLD_END),
            16,
            "color.text.primary"
        )
        sloganEN:SetPoint("TOP", sloganCN, "BOTTOM", 0, -10)

        content.UpdateExecuteBtnText = function()
            if not Frame or not Frame.btnExecute then return end

            local hasExecutedAny = false
            for _, wasExecuted in pairs(executedSteps) do
                if wasExecuted then
                    hasExecutedAny = true
                    break
                end
            end

            if hasExecutedAny then
                Frame.btnExecute:SetText(LC["installer.text.078"])
            else
                Frame.btnExecute:SetText(LC["installer.text.079"])
            end
        end

        Frame.stepDesc:SetAlpha(0)
        messageGroup:SetAlpha(0)
        sloganGroup:SetAlpha(0)

        local function FadeSection(target, key, onFinished)
            local function Continue()
                target:SetAlpha(1)
                if onFinished then onFinished() end
            end

            if GUI2 and GUI2.FadeIn then
                local handle = GUI2:FadeIn(target, {
                    owner = content,
                    key = key,
                    duration = INSTALLER_COMPLETION_FADE_DURATION,
                    onFinished = function(_, _, finished)
                        if finished then Continue() end
                    end,
                })
                if handle and not handle.noop then
                    return
                end
            end

            Continue()
        end

        FadeSection(Frame.stepDesc, "installer-completion-ready", function()
            FadeSection(messageGroup, "installer-completion-message", function()
                FadeSection(sloganGroup, "installer-completion-slogan")
            end)
        end)
    end,
    execute = function()
        if YUI.IsRetail then
            C_CVar.SetCVar("nameplateShowOnlyNameForFriendlyPlayerUnits", "1")
            C_CVar.SetCVar("nameplateUseClassColorForFriendlyPlayerUnitNames", "1")
        end
        Installer:CompleteInstall()
        return true
    end
})

--[=[
LEGACY_THREE_IN_ONE_SWITCH_DISABLED
三合一界面切换暂时停用。未来重新启用时，可恢复下面的选择器与
SimpleAddonManager / BlinkiisPortraits Profile 切换逻辑。

local currentLoadedUI = nil
local selectedUI = nil

local function getColoredScore(score)
    if score <= 3 then
        return string.format("|cff00ff00%d|r", score)
    elseif score == 4 then
        return string.format("|cffa335ee%d|r", score)
    else
        return string.format("|cffff8000%d|r", score)
    end
end

-- Step 4: 界面风格
table.insert(steps, {
    title = LC["installer.text.080"],
    desc = LC["installer.text.081"],
    setup = function(content)
        -- 设置底部提示文本
        SetStatus(LC["installer.text.082"], "info")

        -- 检测当前加载的界面
        currentLoadedUI = nil
        if C_AddOns.IsAddOnLoaded("ElvUI") then
            currentLoadedUI = "ElvUI"
        elseif C_AddOns.IsAddOnLoaded("NDui") then
            currentLoadedUI = "NDui"
        elseif C_AddOns.IsAddOnLoaded("EnhanceQoL") then
            currentLoadedUI = "EQoL"
        end

        if not selectedUI then
            selectedUI = currentLoadedUI or "ElvUI" -- 默认选中当前，或者ElvUI
        end

        local uiOptions = {
            {
                id = "ElvUI",
                name = "ElvUI",
                icon = Assets:Core("images\\ElvUI.tga"),
                scores = string.format(LC["installer.text.083"], getColoredScore(4), getColoredScore(5), getColoredScore(3))
            },
            {
                id = "NDui",
                name = "NDUI",
                icon = Assets:Core("images\\NDUI.tga"),
                scores = string.format(LC["installer.text.083"], getColoredScore(4), getColoredScore(4), getColoredScore(4))
            },
            {
                id = "EQoL",
                name = "EQoL",
                icon = Assets:Core("images\\EQoL.tga"),
                scores = string.format(LC["installer.text.083"], getColoredScore(4), getColoredScore(3), getColoredScore(5))
            }
        }

        local btnWidth, btnHeight = 140, 160
        local gap = 20
        local totalWidth = (#uiOptions * btnWidth) + ((#uiOptions - 1) * gap)
        local startX = -(totalWidth / 2) + (btnWidth / 2)

        local uiButtons = {}

        local function UpdateButtonState(btn, isSelected, isHovered)
            if isSelected then
                ApplyInstallerButtonStyle(btn, "uiSelected")
            elseif isHovered then
                ApplyInstallerButtonStyle(btn, "uiHover")
            else
                ApplyInstallerButtonStyle(btn, "uiIdle")
            end
        end

        local function UpdateExecuteBtnText()
            if not Frame or not Frame.btnExecute then return end
            
            local hasExecutedAny = false
            for _, v in pairs(executedSteps) do
                if v then hasExecutedAny = true; break end
            end
            
            if hasExecutedAny then
                Frame.btnExecute.text:SetText(LC["installer.text.078"])
            else
                if selectedUI ~= currentLoadedUI then
                    Frame.btnExecute.text:SetText(LC["installer.text.084"])
                else
                    Frame.btnExecute.text:SetText(LC["installer.text.085"])
                end
            end
        end

        for i, opt in ipairs(uiOptions) do
            -- 使用 GUI2:CreateButton
            local btn = GUI2:CreateButton(content, "", btnWidth, btnHeight)
            btn:SetPoint("CENTER", content, "CENTER", startX + (i-1)*(btnWidth+gap), -20)
            
            -- 清除 CreateButton 默认可能创建的文本以避免重叠
            if btn.text then btn.text:SetText("") end
            
            local nameText = GUI2:CreateText(btn, opt.name, 20)
            nameText:SetPoint("TOP", 0, -15)
            nameText:SetTextColor(1, 0.82, 0)

            local icon = GUI2:CreateTexture(btn, { layer = "ARTWORK", texture = opt.icon })
            if opt.id == "NDui" then
                icon:SetSize(64, 32)
                icon:SetPoint("TOP", nameText, "BOTTOM", 0, -20)
            elseif opt.id == "EQoL" then
                icon:SetSize(32, 32)
                icon:SetPoint("TOP", nameText, "BOTTOM", 0, -20)
            else
                icon:SetSize(48, 48)
                icon:SetPoint("TOP", nameText, "BOTTOM", 0, -10)
            end

            local scoreText = GUI2:CreateText(btn, opt.scores, 12)
            scoreText:SetPoint("BOTTOM", 0, 15)
            scoreText:SetJustifyH("CENTER")

            btn.optId = opt.id

            btn:SetScript("OnClick", function()
                selectedUI = opt.id
                for _, b in ipairs(uiButtons) do
                    UpdateButtonState(b, selectedUI == b.optId, b.isHovered)
                end
                UpdateExecuteBtnText()
            end)
            
            btn:SetScript("OnEnter", function(self)
                self.isHovered = true
                UpdateButtonState(self, selectedUI == self.optId, true)
            end)
            
            btn:SetScript("OnLeave", function(self)
                self.isHovered = false
                UpdateButtonState(self, selectedUI == self.optId, false)
            end)

            table.insert(uiButtons, btn)
            
            -- 初始状态
            UpdateButtonState(btn, selectedUI == opt.id, false)
        end
        
        -- 暴露给外面，以便在 UpdateInstallerUI 时可以刷新
        content.UpdateExecuteBtnText = UpdateExecuteBtnText
    end,
    execute = function()
        -- 处理界面切换逻辑
        local needReload = false
        if selectedUI and selectedUI ~= currentLoadedUI then
            local SAM = _G.SimpleAddonManager
            if SAM then
                local profileModule = SAM:GetModule("Profile")
                local profileName = "YUI-" .. (selectedUI == "NDui" and "NDUI" or selectedUI)
                if profileModule then
                    profileModule:LoadAddonsFromProfile(profileName, false)
                    needReload = true
                else
                    YUI:Print(LC["installer.text.086"])
                end

                -- 切换头像插件配置
                if BLINKIISPORTRAITS and BLINKIISPORTRAITS.db then
                    BLINKIISPORTRAITS.db:SetProfile(profileName)
                end
            else
                YUI:Print(LC["installer.text.087"])
            end
        end
        
        -- 记录是否有其他步骤被执行
        local hasExecutedAny = false
        for _, v in pairs(executedSteps) do
            if v then hasExecutedAny = true; break end
        end
        
        Installer:CompleteInstall(needReload or hasExecutedAny)
        return true
    end
})
]=]

-- 清理安装器内容 (停止 Timer 和 EventListener)
local function ClearInstallerContent()
    CancelButtonTimers(true)
    if not Frame or not Frame.content or not Frame.content.children then return end
    
    for _, child in ipairs(Frame.content.children) do
        -- 显式清理 Timer
        if child.refreshTimer then
            child.refreshTimer:Cancel()
            child.refreshTimer = nil
        end
        
        -- 显式清理 EventListener
        if child.eventListener then
            YUI.Event:Off(child.eventListener)
            child.eventListener = nil
        end

        if YUI.Animation and YUI.Animation.StopOwner then
            YUI.Animation:StopOwner(child, false)
        end

        child:Hide()
        child:SetParent(nil)
    end
    Frame.content.children = {}
    Frame.currentContent = nil
end

-- 更新 UI 显示
UpdateInstallerUI = function()
    if not Frame then return end

    local stepData = steps[currentStep]

    -- 更新标题
    if Frame.logo then
        Frame.logo:SetText(LC["installer.text.001"])
    end
    if Frame.btnBack then
        Frame.btnBack:SetText(LC["installer.text.092"])
    end
    Frame.stepTitle:SetText(string.format(LC["installer.text.088"], currentStep,
                                          #steps, LC[stepData.titleKey]))
    Frame.stepDesc:SetText(LC[stepData.descKey])
    local descColorKey = stepData.descColorKey or "color.text.primary"
    Frame.stepDesc.gui2ColorKey = descColorKey
    Frame.stepDesc:SetTextColor(GUI2:GetColor(descColorKey))

    -- 对最后一步的文字进行特殊处理（放大）
    if currentStep == #steps then
        Frame.stepDesc:SetFont(STANDARD_TEXT_FONT, 24, "OUTLINE") -- 放大并加粗
    else
        Frame.stepDesc:SetFont(STANDARD_TEXT_FONT, 16) -- 恢复正常大小
    end

    -- 重置状态信息
    SetStatus("", "info")

    -- 清理旧的内容
    ClearInstallerContent()
    if not Frame.content.children then Frame.content.children = {} end

    -- 创建临时的内容容器（用于自动清理）
    local contentContainer = GUI2:CreateFrame(Frame.content)
    contentContainer:SetAllPoints()
    table.insert(Frame.content.children, contentContainer)
    Frame.currentContent = contentContainer

    -- 渲染步骤特定内容
    if stepData.setup then stepData.setup(contentContainer) end
    if YUI.IsForever and stepData.titleKey == "installer.settings.title" then
        Frame.stepDesc:SetFont(STANDARD_TEXT_FONT, 14)
        Frame.stepDesc:ClearAllPoints()
        Frame.stepDesc:SetPoint("TOP", 0, -15)
    else
        Frame.stepDesc:ClearAllPoints()
        Frame.stepDesc:SetPoint("TOP", 0, -20)
    end

    -- 更新按钮状态
    if currentStep == 1 then
        Frame.btnBack:Hide()
    else
        Frame.btnBack:Show()
    end
    
    -- 检查是否禁用执行按钮 (例如空间已满)
    local isExecuteDisabled = contentContainer.disableExecute

    if currentStep == #steps then
        Frame.btnBack:Hide() -- 最后一步不需要返回，已经是完成界面了
        Frame.btnSkip:Hide() -- 最后一步不需要跳过
        Frame.btnCloseDirectly:Hide() -- 最后一步统一通过底部完成按钮结束
        
        if contentContainer.UpdateExecuteBtnText then
            contentContainer.UpdateExecuteBtnText()
        else
            -- 检查是否有执行过任何步骤
            local hasExecutedAny = false
            for _, v in pairs(executedSteps) do
                if v then
                    hasExecutedAny = true
                    break
                end
            end
            
            if hasExecutedAny then
                Frame.btnExecute:SetText(LC["installer.text.078"])
            else
                Frame.btnExecute:SetText(LC["installer.text.085"])
            end
        end
        
        Frame.btnExecute:Show()
        -- 调整完成按钮位置居中
        Frame.btnExecute:ClearAllPoints()
        Frame.btnExecute:SetPoint("BOTTOM", 0, 20)
        Frame.btnExecute:SetWidth(160) -- 稍微加宽一点以容纳更长的文字
        Frame.btnExecute:Enable()
        -- 恢复默认颜色
        ApplyInstallerButtonStyle(Frame.btnExecute, "green")
    else
        Frame.btnCloseDirectly:Show()
        RefreshDirectCloseButton()
        Frame.btnSkip:Show()
        if Frame.skipTimer then Frame.btnSkip:Disable() else Frame.btnSkip:Enable() end
        Frame.btnSkip:SetText(LC["installer.text.089"])
        Frame.btnExecute:SetText(stepData.titleKey == "installer.settings.title" and LC["installer.settings.apply"]
            or currentStep == 1 and LC["installer.text.090"] or LC["installer.text.091"])
        Frame.btnExecute:Show()
        -- 恢复按钮位置
        Frame.btnExecute:ClearAllPoints()
        Frame.btnExecute:SetPoint("BOTTOMRIGHT", -20, 20)
        Frame.btnExecute:SetWidth(120) -- 恢复默认宽度
        
        if isExecuteDisabled then
            Frame.btnExecute:Disable()
            ApplyInstallerButtonStyle(Frame.btnExecute, "gray")
        else
            Frame.btnExecute:Enable()
            ApplyInstallerButtonStyle(Frame.btnExecute, "green")
        end
    end
    if RefreshForeverActions then RefreshForeverActions() end
end

-- 导航函数
GoNext = function()
    if currentStep < #steps then
        currentStep = currentStep + 1
        UpdateInstallerUI()
    else
        -- 理论上不会走到这里，因为最后一步是 Finish
        Installer:CompleteInstall()
    end
end

local function GoBack()
    if currentStep > 1 then
        currentStep = currentStep - 1
        UpdateInstallerUI()
    end
end

local function GetInstallerGlobal(create)
    local global = YUI.DB and YUI.DB.GetGlobal and YUI.DB:GetGlobal(YUI.ProductId or "suite") or nil
    if type(global) ~= "table" then
        if not create then
            return nil
        end

        local db = YUI.db
        global = db and db.global or nil
        if type(global) ~= "table" then
            return nil
        end
    end

    YUI.global = global

    return global
end

local function GetInstalledChars(create)
    local global = GetInstallerGlobal(create)
    if type(global) ~= "table" then return nil end

    if YUI.IsForever then
        if type(global.installedCharsByClient) ~= "table" then
            if not create then return nil end
            global.installedCharsByClient = {}
        end
        if type(global.installedCharsByClient.forever) ~= "table" then
            if not create then return nil end
            global.installedCharsByClient.forever = {}
        end
        return global.installedCharsByClient.forever
    end

    if type(global.installedChars) ~= "table" then
        if not create then return nil end
        global.installedChars = {}
    end

    return global.installedChars
end

local function GetCanonicalInstalledCharKey()
    local aceKey = YUI.db and YUI.db.keys and YUI.db.keys.char or nil
    if aceKey and aceKey ~= "" then
        return aceKey
    end

    if YUI.Player and YUI.Player.GetCharacterKey then
        return YUI.Player:GetCharacterKey(aceKey)
    end

    return aceKey
end

local function GetLegacyInstalledCharKey(canonicalKey)
    if canonicalKey and canonicalKey ~= "" then
        local playerName, realmName = canonicalKey:match("^(.+) %- (.+)$")
        if playerName and playerName ~= "" and realmName and realmName ~= "" then
            return playerName .. "-" .. realmName
        end
    end

    if not YUI.Player or not YUI.Player.GetName or not YUI.Player.GetRealmName then
        return nil
    end

    local playerName = YUI.Player:GetName()
    local realmName = YUI.Player:GetRealmName()
    if playerName and playerName ~= "" and realmName and realmName ~= "" then
        return playerName .. "-" .. realmName
    end
    return nil
end

local function GetInstallState(create)
    local installedChars = GetInstalledChars(create)
    local charKey = GetCanonicalInstalledCharKey()
    local legacyKey = GetLegacyInstalledCharKey(charKey)

    return installedChars, charKey, legacyKey
end

local introWaitTimer, introPending, introResumeFrame

local function CancelIntroWait()
    if introWaitTimer then introWaitTimer:Cancel(); introWaitTimer = nil end
    introPending, introResumeFrame = false, false
end

local function WaitForIntro(resumeFrame)
    introPending = true
    introResumeFrame = introResumeFrame or resumeFrame
    if introWaitTimer then return end
    -- 只在动画期间检查；延后执行避免同一次 Esc 同时关闭向导。
    introWaitTimer = C_Timer.NewTimer(0.1, function()
        introWaitTimer = nil
        if FrameAPI.IsCinematicOrMovieShown() then
            WaitForIntro()
            return
        end
        local resume = introResumeFrame
        introPending, introResumeFrame = false, false
        if resume and Frame then
            PlayInstallerOpen(Frame)
        else
            Installer:CheckInstall()
        end
    end)
end

local function GetInstalledCharacterGUID()
    local unitAPI = YUI.API and YUI.API.Unit
    if not unitAPI or type(unitAPI.UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(unitAPI.UnitGUID, "player")
    if not ok then return nil end
    local security = YUI.API and YUI.API.Security
    if security and security.IsSecretValue and security.IsSecretValue(guid) then return nil end
    if type(guid) == "string" and guid:match("^Player%-%d+%-%x+$") then return guid end
    return nil
end

local function SaveInstalledCharacter(installedChars, guid, charKey, legacyKey)
    installedChars[guid] = true
    -- 精确匹配的旧名称转为 GUID，避免继续把可变名称当作角色身份。
    if charKey then installedChars[charKey] = nil end
    if legacyKey then installedChars[legacyKey] = nil end
end

function Installer:MarkInstalled()
    local guid = GetInstalledCharacterGUID()
    if not guid then return false, "missing character GUID" end
    local installedChars, charKey, legacyKey = GetInstallState(true)
    if not installedChars then
        return false, "missing installedChars"
    end
    SaveInstalledCharacter(installedChars, guid, charKey, legacyKey)
    return true, guid
end

function Installer:IsInstalled()
    local guid = GetInstalledCharacterGUID()
    if not guid then return false, "missing character GUID" end
    local installedChars, charKey, legacyKey = GetInstallState(false)
    if not installedChars then
        return false, "missing installedChars"
    end
    if installedChars[guid] then
        return true, "guid"
    end

    if (charKey and installedChars[charKey]) or (legacyKey and installedChars[legacyKey]) then
        SaveInstalledCharacter(installedChars, guid, charKey, legacyKey)
        return true, "migrated"
    end

    return false, "not installed"
end

local function MarkInstalledOrWarn()
    local ok, reason = Installer:MarkInstalled()
    if not ok then
        YUI:Print("Installer install state save failed: " .. tostring(reason))
    end
    return ok
end

ApplyOrQueuePortraitProfile = function(profileName)
    local option = GetPortraitProfileOption()
    if not option or option.profileName ~= profileName then
        return false, LC["installer.profiles.portrait.unavailable"]
    end
    if SystemAPI.IsAddOnLoadedSafe(option.addonName) then
        local ok, err = ApplyPortraitProfile(profileName)
        local global, charKey = GetInstallerGlobal(false), GetCanonicalInstalledCharKey()
        local pending = global and global.installerPendingPortraitProfilesForever
        if ok and type(pending) == "table" and charKey then pending[charKey] = nil end
        return ok, err
    end
    if SystemAPI.GetAddOnEnabledState(option.addonName) ~= true then
        return false, LC["installer.profiles.portrait.unavailable"]
    end
    local global, charKey = GetInstallerGlobal(true), GetCanonicalInstalledCharKey()
    if not global or not charKey then
        return false, LC["installer.profiles.portrait.unavailable"]
    end
    if type(global.installerPendingPortraitProfilesForever) ~= "table" then
        global.installerPendingPortraitProfilesForever = {}
    end
    global.installerPendingPortraitProfilesForever[charKey] = profileName
    return true, nil, true
end

local function ApplyPendingPortraitProfile()
    local global, charKey = GetInstallerGlobal(false), GetCanonicalInstalledCharKey()
    local pending = global and global.installerPendingPortraitProfilesForever
    local profileName = type(pending) == "table" and charKey and pending[charKey]
    if not profileName then return end
    if InCombatLockdown() then
        YUI.Event:Once("PLAYER_REGEN_ENABLED", ApplyPendingPortraitProfile, portraitProfileOwner)
        return
    end
    pending[charKey] = nil
    local option = GetPortraitProfileOption()
    local ok, err = false, LC["installer.profiles.portrait.unavailable"]
    if option and option.profileName == profileName and SystemAPI.IsAddOnLoadedSafe(option.addonName) then
        ok, err = ApplyPortraitProfile(profileName)
    end
    YUI:Print(ok and LC["installer.profiles.applied"] or err)
end

if YUI.IsForever then
    YUI.Event:Once("YUI_LOGIN_READY", function()
        EnsurePortraitProfilePersistence()
        ApplyPendingPortraitProfile()
    end, portraitProfileOwner)
end

RefreshForeverActions = function()
    if not YUI.IsForever or not Frame then return end
    local combat = InCombatLockdown()
    local function Configure(button, reload)
        if not button then return end
        local disabled = reload and combat
        if button == Frame.btnExecute then
            disabled = combat or Frame.executeTimer ~= nil
                or (Frame.currentContent and Frame.currentContent.disableExecute) == true
        end
        if disabled then button:Disable()
        else button:Enable() end
    end
    Configure(Frame.btnExecute, currentStep == #steps and HasExecutedSteps())
    Configure(Frame.btnCloseDirectly, HasPendingEarlyReload())
    if combat then SetStatus(LC["installer.settings.combat.blocked"], "warning") end
end

-- 创建安装器 UI
local function CreateInstallerFrame()
    if Frame then return Frame end

    Frame = GUI2:CreatePanel(UIParent, {
        name = "YUI_InstallerFrame",
        width = 600,
        height = 420,
        surface = "color.surface.panel",
        border = "color.border.default",
        shadow = true,
    })
    Frame:Hide()
    Frame:SetSize(600, 420) -- 稍微增加高度以容纳状态行
    Frame:SetPoint("CENTER")
    Frame:SetFrameStrata("DIALOG")
    if UISpecialFrames and not Frame.yuiInstallerSpecialFrameRegistered then
        local registered = false
        for _, frameName in ipairs(UISpecialFrames) do
            if frameName == "YUI_InstallerFrame" then
                registered = true
                break
            end
        end
        if not registered then
            table.insert(UISpecialFrames, "YUI_InstallerFrame")
        end
        Frame.yuiInstallerSpecialFrameRegistered = true
    end

    -- 标题区域
    local logo = GUI2:CreateText(Frame, LC["installer.text.001"], 32)
    logo:SetFont(STANDARD_TEXT_FONT, 32, "OUTLINE")
    logo:SetPoint("TOPLEFT", 20, -20)
    Frame.logo = logo

    local stepTitle = GUI2:CreateText(Frame, "", 18)
    stepTitle:SetFont(STANDARD_TEXT_FONT, 18, "OUTLINE")
    stepTitle:SetPoint("TOPRIGHT", -20, -25)
    stepTitle:SetTextColor(0.8, 0.8, 0.8)
    Frame.stepTitle = stepTitle

    -- 分隔线
    local line = GUI2:CreateTexture(Frame, { layer = "ARTWORK", paint = "color.border.default" })
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 20, -60)
    line:SetPoint("TOPRIGHT", -20, -60)

    -- 内容区域
    local content = GUI2:CreateFrame(Frame)
    content:SetPoint("TOPLEFT", 20, -70)
    content:SetPoint("BOTTOMRIGHT", -20, 100) -- 调整底部留白给按钮和状态行
    Frame.content = content

    local stepDesc = GUI2:CreateText(content, "", 16, "color.text.primary")
    stepDesc:SetFont(STANDARD_TEXT_FONT, 16)
    stepDesc:SetPoint("TOP", 0, -20)
    stepDesc:SetWidth(500)
    stepDesc:SetJustifyH("CENTER")
    Frame.stepDesc = stepDesc

    -- 状态行
    local statusText = GUI2:CreateText(Frame, "", 14)
    statusText:SetFont(STANDARD_TEXT_FONT, 14)
    statusText:SetPoint("BOTTOM", 0, 65)
    statusText:SetTextColor(0.8, 0.8, 0.8)
    Frame.statusText = statusText

    -- 底部按钮区域
    local btnBack = GUI2:CreateButton(Frame, LC["installer.text.092"], 100, 30)
    btnBack:SetPoint("BOTTOMLEFT", 20, 20)
    btnBack:SetScript("OnClick", GoBack)
    Frame.btnBack = btnBack

    local btnExecute = GUI2:CreateButton(Frame, LC["installer.text.093"], 120, 30)
    btnExecute:SetPoint("BOTTOMRIGHT", -20, 20)
    ApplyInstallerButtonStyle(btnExecute, "green")
    btnExecute:SetScript("OnClick", function(self)
        -- Forever 重载时保持被点击按钮可见且启用；普通步骤仍防止连点。
        local reloadOnComplete = YUI.IsForever and currentStep == #steps and HasExecutedSteps()
        if not reloadOnComplete then
            self:Disable()
            Frame.executeTimer = C_Timer.NewTimer(1, function()
                Frame.executeTimer = nil
                if not (Frame.currentContent and Frame.currentContent.disableExecute) then self:Enable() end
                RefreshForeverActions()
            end)
        end

        if steps[currentStep].execute() then
            -- 只有成功执行的非完成步骤才触发最终重载
            if currentStep < #steps then
                MarkStepExecuted(currentStep)
            end

            -- 如果是最后一步，直接完成；否则延迟进入下一步
            if currentStep == #steps then
                -- execute already called CompleteInstall
            else
                Frame.navigationTimer = C_Timer.NewTimer(0.5, function()
                    Frame.navigationTimer = nil
                    GoNext()
                end)
            end
        end
    end)
    Frame.btnExecute = btnExecute

    local btnSkip = GUI2:CreateButton(Frame, LC["installer.text.094"], 100, 30)
    btnSkip:SetPoint("RIGHT", btnExecute, "LEFT", -10, 0)
    ApplyInstallerButtonStyle(btnSkip, "gray")
    btnSkip:SetScript("OnClick", function(self) 
        -- 防止连点
        self:Disable()
        Frame.skipTimer = C_Timer.NewTimer(0.5, function()
            Frame.skipTimer = nil
            self:Enable()
        end)
        GoNext() 
    end)
    Frame.btnSkip = btnSkip

    -- 直接关闭按钮（右上角框体外）
    local btnCloseDirectly = GUI2:CreateButton(Frame, LC["installer.text.003"], 80, 24)
    btnCloseDirectly:SetPoint("BOTTOMRIGHT", Frame, "TOPRIGHT", 0, 4)
    ApplyInstallerButtonStyle(btnCloseDirectly, "red")
    btnCloseDirectly:SetScript("OnClick", function()
        -- 标记为已安装
        MarkInstalledOrWarn()

        if HasPendingEarlyReload() then
            YUI:Print(LC["installer.text.095"])
            FrameAPI.ReloadUI()
            return
        end

        PlayInstallerClose(Frame, function()
            YUI:Print(LC["installer.text.096"])
        end)
    end)
    Frame.btnCloseDirectly = btnCloseDirectly

    if YUI.IsForever then
        Frame:SetScript("OnShow", function()
            YUI.Event:OffOwner(Installer)
            YUI.Event:On("PLAYER_REGEN_DISABLED", RefreshForeverActions, Installer)
            YUI.Event:On("PLAYER_REGEN_ENABLED", function()
                SetStatus("", "info")
                RefreshForeverActions()
            end, Installer)
            RefreshForeverActions()
        end)
    end
    
    -- 注册 OnHide 事件以清理资源
    Frame:SetScript("OnHide", function()
        if introPending or FrameAPI.IsCinematicOrMovieShown() then
            WaitForIntro(true)
            return
        end
        -- 开场动画等隐藏父界面时，向导自身仍是 shown，不能视为用户关闭。
        if Frame:IsShown() then return end
        CancelIntroWait()
        MarkInstalledOrWarn()
        CancelButtonTimers()
        ClearInstallerContent()
        if YUI.IsForever then YUI.Event:OffOwner(Installer) end
        if YUI.Animation and YUI.Animation.StopOwner then YUI.Animation:StopOwner(Installer, false) end
        NotifyLoginFlowDone()
    end)

    UpdateInstallerUI()

    return Frame
end

-- 完成安装
function Installer:CompleteInstall(forceReload)
    CancelIntroWait()
    -- 使用全局 DB
    MarkInstalledOrWarn()

    -- 检查是否有执行过任何步骤
    local hasExecutedAny = forceReload
    if not hasExecutedAny then
        for _, v in pairs(executedSteps) do
            if v then
                hasExecutedAny = true
                break
            end
        end
    end

    -- 如果没有执行任何步骤（全跳过），则不重载界面
    if hasExecutedAny then
        YUI:Print(LC["installer.text.097"])
        FrameAPI.ReloadUI()
    else
        PlayInstallerClose(Frame, function()
            YUI:Print(LC["installer.text.098"])
        end)
    end
end

-- 检查是否需要安装
function Installer:CheckInstall(onDone)
    if type(onDone) == "function" then
        loginFlowDone = onDone
    end

    -- 身份尚不可用时不把角色误判为首次安装，也不阻塞登录流程。
    if not YUI.db or not GetInstalledCharacterGUID() then
        NotifyLoginFlowDone()
        return false
    end

    
    -- 检查当前角色是否已安装 (使用全局 DB)
    if not self:IsInstalled() then
        if introPending or FrameAPI.IsCinematicOrMovieShown() then
            WaitForIntro()
            return true
        end
        currentStep = 1
        executedSteps = {} -- 重置执行记录
        ResetLayoutStepSelection()
        if YUI.IsForever then YUI.InstallerSettings:Reset() end
        local f = CreateInstallerFrame()
        UpdateInstallerUI()
        PlayInstallerOpen(f)
        return true
    end

    NotifyLoginFlowDone()
    return false
end

-- 手动打开安装器命令
function Installer:Show()
    CancelIntroWait()
    currentStep = 1
    executedSteps = {} -- 重置执行记录
    ResetLayoutStepSelection()
    if YUI.IsForever then YUI.InstallerSettings:Reset() end
    local f = CreateInstallerFrame()
    UpdateInstallerUI()
    PlayInstallerOpen(f)
end

-- 重置安装状态 (清除所有角色的记录)
function Installer:ResetInstall()
    local global = GetInstallerGlobal(true)
    if not global then
        YUI:Print(LC["installer.text.099"])
        return
    end

    if YUI.IsForever then
        global.installedCharsByClient = global.installedCharsByClient or {}
        global.installedCharsByClient.forever = {}
    else
        global.installedChars = {}
    end
    global.Gold = {} -- 清除所有角色的金币记录 (使用全局 DB)
    global.ignoreYUISwitchPrompt = false -- 重置忽略提示标志
    YUI:Print(
        LC["installer.text.100"])
end

-- 处理 slash 命令
function YUI:HandleSlashCommand(msg)
    msg = msg or ""
    local cmd = msg:lower():match("^%s*(%S*)")
    if cmd == "i" then
        Installer:Show()
        return true
    end
    if previousSlashHandler then
        return previousSlashHandler(self, msg)
    end
    return false
end
