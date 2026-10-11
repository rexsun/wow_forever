local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI then return end

local Components = YUI.Components
local Event = YUI.Event
local Security = (YUI.API and YUI.API.Security) or YUI.WOW_API or {}
local L = YUI.Locale and YUI.Locale:Get("WhisperManager") or {}

local FEATURE_KEY = "WhisperManager"
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or (_G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME] and _G.YUI_CORE_EMBED_STATE[ADDON_NAME].productId)
    or YUI.ProductId or "suite"
local CONFIG_KEY = "WhisperManager_Config"
local LEGACY_GRADIENT_KEY = "WhisperColor"
local LEGACY_SUITE_PRODUCT_ID = "suite"
local GRADIENT_LIMITS = {
    maxVisibleChars = 120,
    maxOutputBytes = 1800,
}
local GRADIENT_DEFAULTS = {
    historyEnabled = true,
    gradient = {
        enabled = false,
    },
}

local Gradient = YUI.WhisperGradient or {}
YUI.WhisperGradient = Gradient

local function T(key, fallback)
    if type(L) == "table" and L[key] then
        return L[key]
    end
    return fallback or key
end

local function ClampColor(value, fallback)
    value = tonumber(value)
    if value == nil then
        return fallback
    end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function NormalizeColor(value, fallback)
    local source = value
    if type(source) ~= "table" then
        source = fallback
    end
    if type(source) ~= "table" then
        source = { 1, 1, 1, 1 }
    end

    local r = source.r or source[1]
    local g = source.g or source[2]
    local b = source.b or source[3]
    local a = source.a or source[4]
    return {
        r = ClampColor(r, 1),
        g = ClampColor(g, 1),
        b = ClampColor(b, 1),
        a = ClampColor(a, 1),
    }
end

local function ToColorArray(value)
    local color = NormalizeColor(value)
    return { color.r, color.g, color.b, color.a }
end

function Gradient:GetDefaultColors()
    if YUI.VersionType == "Pro" then
        return { r = 1, g = 1, b = 0, a = 1 }, { r = 1, g = 0.27, b = 0, a = 1 }
    end
    return { r = 0.88, g = 1, b = 1, a = 1 }, { r = 0, g = 0.6, b = 1, a = 1 }
end

local function EnsureGradientConfig(config)
    if type(config.gradient) ~= "table" then
        config.gradient = {}
    end
    if config.gradient.enabled == nil then
        config.gradient.enabled = false
    end
    if config.historyEnabled == nil then
        config.historyEnabled = true
    end
    if type(config._migrations) ~= "table" then
        config._migrations = {}
    end
end

local function GetProfile(productId)
    if YUI.DB and YUI.DB.GetProfile then
        return YUI.DB:GetProfile(productId)
    end
end

local function MigrateLegacyGradientState(config)
    if not (Components and Components.GetStore) then
        return
    end

    local migrations = config._migrations
    if not migrations.whisperGradientV1 then
        local suiteStore = Components:GetStore(LEGACY_SUITE_PRODUCT_ID)
        if type(suiteStore) == "table" and suiteStore[LEGACY_GRADIENT_KEY] ~= nil then
            config.gradient.enabled = suiteStore[LEGACY_GRADIENT_KEY] == true
            suiteStore[LEGACY_GRADIENT_KEY] = nil
        else
            local suiteProfile = GetProfile(LEGACY_SUITE_PRODUCT_ID)
            if type(suiteProfile) == "table" and suiteProfile[LEGACY_GRADIENT_KEY] ~= nil then
                config.gradient.enabled = suiteProfile[LEGACY_GRADIENT_KEY] == true
                suiteProfile[LEGACY_GRADIENT_KEY] = nil
            end
        end
        migrations.whisperGradientV1 = true
    end

    if not migrations.whisperManagerContainerV1 then
        local productStore = Components:GetStore(PRODUCT_ID)
        if type(productStore) == "table" then
            if productStore[FEATURE_KEY] ~= nil then
                config.historyEnabled = productStore[FEATURE_KEY] == true
            end
            productStore[FEATURE_KEY] = true
        end
        migrations.whisperManagerContainerV1 = true
    end
end

function Gradient:GetDB()
    if not (Components and Components.EnsureConfig) then
        return nil
    end

    local config = Components:EnsureConfig(CONFIG_KEY, GRADIENT_DEFAULTS, PRODUCT_ID)
    if type(config) ~= "table" then
        return nil
    end

    EnsureGradientConfig(config)
    MigrateLegacyGradientState(config)
    EnsureGradientConfig(config)
    return config
end

function Gradient:GetEffectiveColors()
    local config = self:GetDB()
    local defaultStart, defaultEnd = self:GetDefaultColors()
    local gradient = config and config.gradient or nil
    local startColor = NormalizeColor(gradient and gradient.startColor, defaultStart)
    local endColor = NormalizeColor(gradient and gradient.endColor, defaultEnd)
    return startColor, endColor
end

function Gradient:IsEnabled()
    if Components and Components.Get and Components.IsEnabled then
        local component = Components:Get(FEATURE_KEY)
        if component and not Components:IsEnabled(component) then
            return false
        end
    end

    local config = self:GetDB()
    if not config then
        return false
    end
    return type(config.gradient) == "table" and config.gradient.enabled == true
end

function Gradient:SetEnabled(enabled)
    local config = self:GetDB()
    if config and type(config.gradient) == "table" then
        config.gradient.enabled = enabled == true
    end
end

function Gradient:SetColor(key, value)
    if key ~= "startColor" and key ~= "endColor" then
        return
    end

    local config = self:GetDB()
    if config and type(config.gradient) == "table" then
        config.gradient[key] = ToColorArray(value)
    end
end

function Gradient:ResetColors()
    local config = self:GetDB()
    if config and type(config.gradient) == "table" then
        config.gradient.startColor = nil
        config.gradient.endColor = nil
    end
end

function Gradient:ColorMessage(message)
    if not message then
        return message
    end

    local startColor, endColor = self:GetEffectiveColors()
    if YUI.F and YUI.F.GetGradientText then
        return YUI.F:GetGradientText(message, startColor, endColor, GRADIENT_LIMITS)
    end
    return "|cff80D8FF" .. message .. "|r"
end

function Gradient:BuildSettingsFields(feature)
    local config = self:GetDB()
    local gradient = config and config.gradient or GRADIENT_DEFAULTS.gradient
    local startDefault, endDefault = self:GetDefaultColors()
    return {
        {
            type = "checkbox",
            label = T("settings.gradient_toggle"),
            get = function() return gradient.enabled == true end,
            set = function(value)
                self:SetEnabled(value == true)
                if feature and feature.RefreshCurrentModule then feature:RefreshCurrentModule() end
            end,
        },
        {
            type = "button",
            text = T("button.reset_gradient", "恢复默认颜色"),
            controlWidth = 130,
            height = 32,
            tone = "default",
            onClick = function()
                self:ResetColors()
                if feature and feature.RefreshCurrentModule then
                    feature:RefreshCurrentModule()
                end
            end,
        },
        {
            type = "color",
            label = T("settings.gradient_start", "起始颜色"),
            field = true,
            hasAlpha = false,
            height = 32,
            hidden = function() return gradient.enabled ~= true end,
            default = ToColorArray(startDefault),
            get = function()
                local startColor = self:GetEffectiveColors()
                return ToColorArray(startColor)
            end,
            set = function(value)
                self:SetColor("startColor", value)
            end,
        },
        {
            type = "color",
            label = T("settings.gradient_end", "结束颜色"),
            field = true,
            hasAlpha = false,
            height = 32,
            hidden = function() return gradient.enabled ~= true end,
            default = ToColorArray(endDefault),
            get = function()
                local _, endColor = self:GetEffectiveColors()
                return ToColorArray(endColor)
            end,
            set = function(value)
                self:SetColor("endColor", value)
            end,
        },
    }
end

function Gradient:BuildSettingsOptions(feature)
    local fields = self:BuildSettingsFields(feature)
    return { {
        type = "custom",
        retainedFields = fields,
        render = function(parent, x, y, width)
            local _, renderedWidth, renderedHeight = YUI.Settings:RenderAlignedFields(parent, {
                x = x, y = y, width = width, fields = fields,
                columns = 2, columnGap = 24, rowGap = 10, rowHeight = 32, labelPosition = "top",
            })
            return renderedWidth, renderedHeight
        end,
    } }
end

local function WhisperInformFilter(self, event, msg, author, ...)
    if Security.IsSecretValue and Security.IsSecretValue(msg) then
        return false, msg, author, ...
    end

    if Gradient:IsEnabled() then
        msg = Gradient:ColorMessage(msg)
    end
    return false, msg, author, ...
end

if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", WhisperInformFilter)
end

if YUI.Lifecycle and YUI.Lifecycle.IsReady and YUI.Lifecycle:IsReady("YUI_DB_READY") then
    Gradient:GetDB()
elseif Event and Event.On then
    Event:On("YUI_DB_READY", function()
        Gradient:GetDB()
    end, Gradient, {
        priority = 7900,
        traceName = "WhisperManager:gradient-migration",
        moduleId = "component:" .. FEATURE_KEY,
        phase = "YUI_DB_READY",
    })
end

if YUI.IsMists and Components and Components.RegisterFeature then
    Components:RegisterFeature(FEATURE_KEY, {
        name = T("name", "密语管家"),
        description = T("description", "记录玩家和战网密语，提供未读提醒和快速回复。"),
        product = PRODUCT_ID,
        default = true,
        settingsMode = "inline",
        callback = function(enabled)
            Gradient.containerEnabled = enabled == true
        end,
        GetOptions = function(feature)
            return Gradient:BuildSettingsOptions(feature)
        end,
    })
end
