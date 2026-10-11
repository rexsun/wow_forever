local ADDON_NAME = ...
local YUI = _G.YUI
local S = YUI and YUI.Settings
local GUI2 = YUI and YUI.GUI2
local Components = YUI and YUI.Components
local LC = YUI and YUI.Locale and YUI.Locale:Get("Core") or nil

if not (YUI and S and GUI2 and Components) then
    return
end

local function T(key, fallback)
    local value = LC and LC[key]
    if type(value) == "string" and value ~= "" and value ~= key then
        return value
    end
    return fallback or key
end

local function IsComponentSettingsProduct(product)
    local component = product and product.component
    local componentId = component and component.id
    return product
        and product.settings
        and product.settings.enabled == true
        and type(componentId) == "string"
        and componentId ~= ""
end

local function GetProduct(productId)
    return productId and YUI.Products and YUI.Products[productId] or nil
end

local function ResolveCandidate(productId)
    local product = GetProduct(productId)
    if IsComponentSettingsProduct(product) then
        return productId, product
    end
    return nil, nil
end

local function ResolveProduct()
    local bootstrapState = _G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME]

    local productId, product = ResolveCandidate(bootstrapState and bootstrapState.productId)
    if productId then
        return productId, product
    end

    productId, product = ResolveCandidate(S.ActiveProductId)
    if productId then
        return productId, product
    end

    productId, product = ResolveCandidate(YUI.ProductId)
    if productId then
        return productId, product
    end

    if YUI.Products then
        for candidateId, candidate in pairs(YUI.Products) do
            if IsComponentSettingsProduct(candidate) then
                return candidateId, candidate
            end
        end
    end

    return nil, nil
end

local productId, product = ResolveProduct()
local componentMeta = product and product.component or nil
local componentId = componentMeta and componentMeta.id or nil

if type(componentId) ~= "string" or componentId == "" then
    return
end

local productSettings = product and product.settings or nil
local settingsEntry = productSettings and productSettings.entry or nil
if type(settingsEntry) ~= "string" or settingsEntry == "" then
    settingsEntry = productId .. ".settings"
end

local activeSettingsFeature
local currentComponent
local missingComponentLogged = false
local renderTarget
local SETTINGS_ICON = "Interface\\Icons\\INV_Misc_Gear_01"

local function CallFeatureHook(feature, hookName)
    local hook = feature and feature[hookName]
    if type(hook) ~= "function" then
        return
    end

    local ok, err = pcall(hook, feature)
    if not ok then
        print("|cffff0000YUI Component Error:|r " .. tostring(feature.name or feature.id or "Unknown") .. " - " .. tostring(err))
    end
end

local function LeaveActiveSettings()
    if not activeSettingsFeature then
        return
    end

    local feature = activeSettingsFeature
    activeSettingsFeature = nil
    CallFeatureHook(feature, "OnSettingsLeave")
end

local function EnterSettings(component)
    local feature = component and (component.feature or component)
    if not feature or activeSettingsFeature == feature then
        return
    end

    LeaveActiveSettings()
    activeSettingsFeature = feature
    CallFeatureHook(feature, "OnSettingsEnter")
end

local function GetComponent()
    local component = Components.Get and Components:Get(componentId) or nil
    if component then
        return component
    end

    local feature = Components.features and Components.features[componentId] or nil
    if feature then
        return {
            id = componentId,
            feature = feature,
            displayName = feature.name,
            description = feature.description,
            settingsMode = feature.settingsMode,
            GetOptions = feature.GetOptions,
        }
    end
    return nil
end

local function LogMissingComponent()
    if missingComponentLogged then
        return
    end
    missingComponentLogged = true

    local bootstrapState = _G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME]
    local registryHasComponent = Components.registry and Components.registry[componentId] ~= nil
    local featuresHasComponent = Components.features and Components.features[componentId] ~= nil
    local message = string.format(
        "YUI ComponentFeature: 未找到组件 component=%s product=%s entry=%s addon=%s stateProduct=%s stateEnabled=%s yuiProduct=%s activeProduct=%s registry=%s features=%s",
        tostring(componentId),
        tostring(productId),
        tostring(settingsEntry),
        tostring(ADDON_NAME),
        tostring(bootstrapState and bootstrapState.productId),
        tostring(bootstrapState and bootstrapState.productEnabled),
        tostring(YUI.ProductId),
        tostring(S.ActiveProductId),
        tostring(registryHasComponent),
        tostring(featuresHasComponent)
    )

    print("|cffffcc00" .. message .. "|r")
end

local function GetComponentOptions(component)
    local feature = component and (component.feature or component)
    local getOptions = component and (component.GetOptions or (feature and feature.GetOptions))
    if type(getOptions) ~= "function" then
        return nil
    end

    local ok, options = pcall(getOptions, feature)
    if ok then
        return options
    end

    local name = Components.GetDisplayName and Components:GetDisplayName(component)
        or component.displayName or component.id
    print("|cffff0000YUI Component Error:|r " .. tostring(name) .. " - " .. tostring(options))
    return nil
end

local function GetEffectiveState(component)
    if Components.GetEffectiveState then
        return Components:GetEffectiveState(component)
    end
    return { effective = true }
end

local function IsComponentIneffective(component)
    if not (Components.IsEnabled and Components:IsEnabled(component)) then
        return false, nil
    end
    local state = GetEffectiveState(component)
    return state and state.effective == false, state
end

local function GetProductTitle()
    if YUI.GetProductShortTitle then
        return YUI:GetProductShortTitle(product or productId)
    end
    if YUI.GetProductTitle then
        return YUI:GetProductTitle(product or productId)
    end
    return product and (product.title or product.id) or productId
end

local function RenderHeader(parent, x, y, width, component)
    local frameWidth = width or 620
    local textTop = -4
    local titleDescGap = 4
    local frame = GUI2:CreateFrame(parent, { width = frameWidth, height = 46 })
    frame:SetPoint("TOPLEFT", x, y)

    local textWidth = frameWidth
    local minimapButton
    if S.CreateProductHeaderMinimapButton then
        minimapButton = S:CreateProductHeaderMinimapButton(frame, productId, { size = 24 })
        if minimapButton then
            minimapButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -2)
            textWidth = frameWidth - 34
        end
    end

    local title = GUI2:CreateText(frame, GetProductTitle(), GUI2.Fonts.size_title, "color.text.heading")
    title:SetFont(GUI2.Fonts.header, GUI2.Fonts.size_title, "OUTLINE")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, textTop)
    title:SetWidth(textWidth)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)

    local description = component and Components.GetDescription
        and Components:GetDescription(component)
        or component and component.description
    if type(description) == "string" and description ~= "" then
        local text = GUI2:CreateText(frame, description, "font.size.sm", "color.text.secondary")
        text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -titleDescGap)
        text:SetWidth(textWidth)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
    end

    return frameWidth, 46
end

local function RefreshCurrentModuleScroll(resetScroll)
    if S.RefreshCurrentModuleScroll and renderTarget and (not renderTarget.IsShown or renderTarget:IsShown()) then
        S:RefreshCurrentModuleScroll(resetScroll)
    end
end

local function Render(parent, isRefresh)
    renderTarget = parent
    local component = GetComponent()
    currentComponent = component

    if parent and parent.HookScript and not parent.yuiComponentFeatureLifecycleHooked then
        parent.yuiComponentFeatureLifecycleHooked = true
        parent:HookScript("OnHide", LeaveActiveSettings)
        parent:HookScript("OnShow", function()
            if currentComponent and not activeSettingsFeature then
                EnterSettings(currentComponent)
            end
            RefreshCurrentModuleScroll(false)
        end)
    end

    S:ClearConfig(parent)
    if component then
        EnterSettings(component)
    else
        LeaveActiveSettings()
    end

    local config = {
        {
            type = "custom",
            render = function(configParent, x, y, width)
                return RenderHeader(configParent, x, y, width, component)
            end,
        },
        { type = "space", height = 5 },
    }

    if not component then
        LogMissingComponent()
        config[#config + 1] = { type = "text", label = T("component.component_missing", "未找到当前产品绑定的组件。"), colorKey = "color.state.warning" }
        S:RenderConfig(parent, config)
        RefreshCurrentModuleScroll(not isRefresh)
        return
    end

    local ineffective, state = IsComponentIneffective(component)
    if ineffective then
        if state.kind == "yield" then
            S:RenderConfig(parent, {
                {
                    type = "text",
                    label = S:FormatYieldNotice(
                        state.featureKey or component.id,
                        state.controller,
                        state.featureLabel or (Components.GetDisplayName and Components:GetDisplayName(component)) or component.displayName
                    ),
                    colorKey = "color.text.primary",
                },
            })
            RefreshCurrentModuleScroll(not isRefresh)
            return
        end
        config[#config + 1] = {
            type = "text",
            label = state.reason or T("component.inactive", "该组件当前未生效。"),
            colorKey = (state.tone == "danger" or state.tone == "error") and "color.state.danger" or "color.state.warning",
        }
        S:RenderConfig(parent, config)
        RefreshCurrentModuleScroll(not isRefresh)
        return
    end

    local feature = component.feature or component
    feature.RefreshCurrentModule = function()
        if renderTarget then
            local target = renderTarget
            local picker = GUI2.ColorPicker
            if picker and picker:DeferRefresh(target, function()
                if renderTarget == target and currentComponent == component then Render(target, true) end
            end) then return end
            Render(renderTarget, true)
        end
    end
    component.RefreshCurrentModule = feature.RefreshCurrentModule

    local options = GetComponentOptions(component)
    if options then
        for _, opt in ipairs(options) do
            config[#config + 1] = opt
        end
    else
        config[#config + 1] = { type = "text", label = T("component.no_options", "该组件没有可配置选项。"), colorKey = "color.text.muted" }
    end

    S:RenderConfig(parent, config)
    RefreshCurrentModuleScroll(not isRefresh)
end

S:RegisterModule(GetProductTitle(), SETTINGS_ICON, Render, {
    id = settingsEntry,
    product = productId,
    scope = productId,
    standaloneOnly = true,
})
