local YUI = _G.YUI
local S = YUI.Settings
local External = YUI.API and YUI.API.External
local Components = YUI.Components
local L = YUI.Locale:Get("YDamageMeter")
local FEATURE_KEY = "YDamageMeter"
local TRANSFER_MODULE_ID = "component.y_damage_meter"
local TEMPORARILY_HIDDEN = true
local TEMPORARILY_DISABLED = true
local TRANSFER_FIELDS = {
    enabled = true,
    texture = true,
    font = true,
    fontFlag = true,
    fontShadow = true,
    gradient = true,
    headerStyle = true,
    edgeMode = true,
    bgStyle = true,
    barBgStyle = true,
    fade = true,
    snap = true,
    snapDirection = true,
    resetMode = true,
    fadeMinAlpha = true,
    fadeMaxAlpha = true,
    fadeDuration = true,
    snapSpacing = true,
}

local function T(key, fallback)
    local value = L[key]
    if value == key then return fallback or key end
    return value
end

local function GetM()
    return YUI.YDamageMeter
end

local function EnsureDB()
    local M = GetM()
    if M and M.EnsureDB then
        return M:EnsureDB()
    end

    local profile = YUI.DB and YUI.DB.GetProfile and YUI.DB:GetProfile(YUI.ProductId or "suite")
    if type(profile) ~= "table" then return nil end
    if type(profile.YDamageMeter) ~= "table" then
        profile.YDamageMeter = {}
    end
    return profile.YDamageMeter
end

local function GetDB(key)
    local db = EnsureDB()
    if db then
        return db[key]
    end
end

local function SetDB(key, val)
    local db = EnsureDB()
    if db then
        db[key] = val
    end
end

local function RefreshAppearance(reason)
    local M = GetM()
    if M and M.RefreshAppearance then
        M:RefreshAppearance(reason)
    elseif M and M.Activate then
        M:Activate(reason)
    end
end

local function GetDefaultEnabled()
    if TEMPORARILY_DISABLED then
        return false
    end

    local value = GetDB("enabled")
    if value == nil then
        return true
    end
    return value == true
end

local function IsFeatureEnabled()
    if Components and Components.Get and Components.IsEnabled then
        local component = Components:Get(FEATURE_KEY)
        if component then
            return Components:IsEnabled(component)
        end
    end
    return GetDefaultEnabled()
end

local function SetFeatureEnabled(enabled)
    enabled = enabled == true
    if Components and Components.features and Components.features[FEATURE_KEY] and Components.SetFeatureEnabled then
        Components:SetFeatureEnabled(FEATURE_KEY, enabled)
    else
        SetDB("enabled", enabled)
    end
end

local function MigrateLegacyEnabled()
    if not (Components and Components.GetStore) then
        return
    end

    local store = Components:GetStore(YUI.ProductId or "suite")
    if TEMPORARILY_DISABLED then
        if store then
            store[FEATURE_KEY] = false
        end
        SetDB("enabled", false)
        return
    end

    local db = EnsureDB()
    if not db or db.enabled == nil then
        return
    end

    if store and store[FEATURE_KEY] == nil then
        store[FEATURE_KEY] = db.enabled == true
    end
end

local function OnFeatureToggled(enabled)
    SetDB("enabled", enabled == true)
    local M = GetM()
    if M and M.RefreshConflictState then
        M:RefreshConflictState({ force = true })
    end
    if enabled and M and M.Activate then
        M:Activate()
    elseif not enabled and YUI.Yield then
        YUI.Yield:Clear("damage_meter")
    end
end

local function GetBlockingDamageAddon(options)
    if type(External) ~= "table" or type(External.ResolveCapability) ~= "function" then return nil, "unknown" end
    local ok, snapshot = pcall(External.ResolveCapability, External, "ui.damage_meter.controller", options)
    if not ok or type(snapshot) ~= "table" then return nil, "unknown" end
    if snapshot.status == "active" then return snapshot.controller, "active" end
    if snapshot.status == "unknown" then return nil, "unknown" end
    return nil, "inactive"
end

local function GetEffectiveState()
    local loadedAddon, status = GetBlockingDamageAddon()
    if status == "active" or status == "unknown" then
        return {
            effective = false,
            kind = status == "active" and "yield" or nil,
            controller = loadedAddon,
            featureKey = "damage_meter",
            status = status,
            tone = "warning",
        }
    end
    return { effective = true }
end

local function GetConfig()
    local loadedAddon, status = GetBlockingDamageAddon()
    if status == "active" or status == "unknown" then
        return {
            {
                type = "text",
                label = status == "active"
                    and S:FormatYieldNotice("damage_meter", loadedAddon)
                    or T("settings.unknown_state", "无法确认同类伤害统计插件状态，当前功能未运行。"),
                colorKey = "color.text.primary",
            },
        }
    end

    return {
        -- 全局启用开关
        { type = "header", label = T("settings.header", "伤害统计增强") },
        { type = "checkbox", label = T("settings.enabled", "启用模块"),
          default = false,
          get = IsFeatureEnabled,
          set = SetFeatureEnabled,
          onChange = function(val)
             YUI:Print(T("settings.reload", "请重载界面以应用更改 (/reload)"))
             S:ShowReload()
          end
        },
        { type = "text", label = T("settings.help", "启用后将对暴雪自带的伤害统计进行美化和功能增强。"), colorKey = "color.text.secondary" },
        
        -- 外观美化
        { type = "space", height = 10 },
        { type = "divider", label = T("section.appearance", "外观美化"), alignLeft = true, width = 600 },
        { type = "space", height = 10 },
        
        { type = "checkbox", label = T("settings.edge_mode", "贴边模式（暂时无效）"),
          default = true,
          get = function() return GetDB("edgeMode") end,
          set = function(val) SetDB("edgeMode", val) end,
          onChange = function(val)
             local M = GetM()
             if M and M.Activate then M:Activate() end
             S:ShowReload()
          end
        },
        { type = "text", label = T("settings.edge_mode.help", "启用后隐藏滚动条，内容向右充满窗口，适合贴边放置。"), colorKey = "color.text.secondary" },
        { type = "space", height = 10 },
        
        {
            type = "row",
            children = {
                { type = "dropdown", label = T("settings.background", "列表背景风格"),
                  options = {
                      { text = T("option.dark_default", "暗黑（默认）"), value = "Dark" },
                      { text = T("option.transparent", "透明"), value = "Transparent" },
                  },
                  default = "Transparent",
                  get = function() return GetDB("bgStyle") or "Transparent" end,
                  set = function(val) SetDB("bgStyle", val) end,
                  onChange = function() 
                      RefreshAppearance("setting:bgStyle")
                  end
                },
                { type = "dropdown", label = T("settings.header_style", "标题栏风格"),
                  options = {
                      { text = T("option.dark", "暗黑"), value = "Dark" },
                      { text = T("option.blizzard", "暴雪"), value = "Blizzard" },
                  },
                  default = "Dark",
                  get = function() return GetDB("headerStyle") or "Dark" end,
                  set = function(val) SetDB("headerStyle", val) end,
                  onChange = function() 
                      RefreshAppearance("setting:headerStyle")
                  end
                },
            }
        },

        {
            type = "row",
            children = {
                { type = "dropdown", label = T("settings.bar_background", "条背景风格"),
                  options = {
                      { text = T("option.blizzard_default", "暴雪默认"), value = "Dark" },
                      { text = T("option.transparent", "透明"), value = "Transparent" },
                  },
                  default = "Dark",
                  get = function() return GetDB("barBgStyle") or "Dark" end,
                  set = function(val) SetDB("barBgStyle", val) end,
                  onChange = function() 
                      RefreshAppearance("setting:barBgStyle")
                  end
                },
                { type = "texture", label = T("settings.texture", "条材质"),
                  default = " |cFFFF00FFY|r|cFFFF6666U|r|cFFFF9900I|r |CFFBA55D3Solid|r",
                  get = function() return GetDB("texture") end,
                  set = function(val) SetDB("texture", val) end,
                  onChange = function() 
                      RefreshAppearance("setting:texture")
                  end
                },
                { type = "checkbox", label = T("settings.gradient", "条颜色渐变"),
                  default = true,
                  get = function() return GetDB("gradient") end,
                  set = function(val) SetDB("gradient", val) end,
                  onChange = function() 
                      RefreshAppearance("setting:gradient")
                  end
                },
            }
        },
        
        {
            type = "row",
            children = {
                { type = "font", label = T("settings.font", "字体样式"),
                --   width = 250, -- 增加宽度
                  default = "默认",
                  get = function() return GetDB("font") end,
                  set = function(val) SetDB("font", val) end,
                  onChange = function() 
                      RefreshAppearance("setting:font")
                  end
                },
                { type = "checkbox", label = T("settings.font_shadow", "启用字体阴影"),
                  default = true,
                  get = function() return GetDB("fontShadow") end,
                  set = function(val) SetDB("fontShadow", val) end,
                  onChange = function() 
                      RefreshAppearance("setting:fontShadow")
                  end
                },
            }
        },
        
        
        
        -- 功能增强
        { type = "space", height = 10 },
        { type = "divider", label = T("section.features", "功能增强"), alignLeft = true, width = 600 },
        { type = "space", height = 10 },
        
        { type = "dropdown", label = T("settings.fade", "渐隐标题栏"),
          options = {
              { text = T("option.fade_none", "不渐隐"), value = "NONE" },
              { text = T("option.fade_header", "保留标题"), value = "HEADER" },
              { text = T("option.fade_all", "全部渐隐"), value = "ALL" },
          },
          default = "ALL",
          get = function() return GetDB("fade") or "ALL" end,
          set = function(val) SetDB("fade", val) end,
          onChange = function() 
              local M = GetM()
              if M and M.Activate then M:Activate() end
              S:ShowReload()
          end
        },
        -- { type = "text", label = "平时隐藏标题栏和按钮，鼠标悬停时显示。", color = {0.5, 0.5, 0.5} },
        
        {
            type = "row",
            children = {
                { 
                  type = "dropdown", 
                  label = T("settings.snap", "窗口自动排列"),
                  width = 250,
                  options = {
                      { text = T("option.off", "关闭"), value = false },
                      { text = T("option.vertical", "垂直堆叠"), value = "VERTICAL" },
                      { text = T("option.horizontal", "水平排列"), value = "HORIZONTAL" },
                      { text = T("option.l_vertical", "L 型布局 - 垂直优先"), value = "L_VERT" },
                      { text = T("option.l_horizontal", "L 型布局 - 水平优先"), value = "L_HORIZ" },
                  },
                  default = "VERTICAL",
                  get = function() 
                      local snap = GetDB("snap")
                      if not snap then return false end
                      return GetDB("snapDirection") or "VERTICAL"
                  end,
                  set = function(val) 
                      if val == false then
                          SetDB("snap", false)
                      else
                          SetDB("snap", true)
                          SetDB("snapDirection", val)
                      end
                  end,
                  onChange = function() 
                      local M = GetM()
                      if M and M.Activate then M:Activate() end 
                  end
                },
                {
                    type = "slider",
                    layout = "legacy",
                    label = T("settings.spacing", "窗口间距"),
                    width = 200, 
                    min = -50, max = 50, step = 1,
                    default = 1,
                    get = function() return GetDB("snapSpacing") or 1 end,
                    set = function(val) SetDB("snapSpacing", val) end,
                    onChange = function() 
                        local M = GetM()
                        if M and M.RearrangeWindows then M:RearrangeWindows() end 
                    end
                }
            }
        },
        { type = "text", label = T("settings.snap.help", "自动将多窗口吸附到主窗口。智能判断屏幕位置决定延伸方向。"), colorKey = "color.text.secondary" },
        
        { type = "dropdown", label = T("settings.reset_policy", "数据重置策略"),
          options = {
              { text = T("option.smart", "智能模式"), value = "Smart" },
            --   { text = "战斗开始", value = "Combat" },
              { text = T("option.never", "从不"), value = "Never" },
          },
          default = "Smart",
          get = function() return GetDB("resetMode") end,
          set = function(val) SetDB("resetMode", val) end,
          onChange = function() 
              local M = GetM()
              if M and M.SetupResetLogic then M:SetupResetLogic() end
              
          end
        },
        { type = "text", label = T("settings.reset_policy.help", "智能模式：进本询问，大秘境插钥匙自动重置。"), colorKey = "color.text.secondary" },

    }
end

if YUI.Event then
    YUI.Event:On("YUI_DB_READY", MigrateLegacyEnabled, Components, { priority = 7900 })
end

if Components and Components.RegisterFeature and not TEMPORARILY_HIDDEN then
    Components:RegisterFeature(FEATURE_KEY, {
        localeNamespace = "YDamageMeter",
        nameKey = "feature.name",
        descriptionKey = "feature.description",
        name = T("feature.name", "暴雪伤害统计增强"),
        description = T("feature.description", "美化暴雪伤害统计，并补充渐隐、吸附排列和智能重置等选项。"),
        default = false,
        tags = { T("tag.skin", "美化皮肤"), T("tag.combat", "战斗辅助") },
        settingsMode = "inline",
        sourceRoot = "Components\\YDamageMeter",
        requiresReload = true,
        callback = OnFeatureToggled,
        GetEffectiveState = GetEffectiveState,
        GetOptions = GetConfig,
    })
end

local function RegisterConfigTransfer()
    local transfer = S and S.ConfigTransfer
    if not (transfer and transfer.RegisterModule)
        or transfer.modules[TRANSFER_MODULE_ID] then
        return
    end
    local feature = Components and Components.features
        and Components.features[FEATURE_KEY] or nil
    transfer:RegisterModule({
        id = TRANSFER_MODULE_ID,
        kind = "component",
        labelKey = "settings.config_transfer.module.y_damage_meter",
        schemaVersion = 1,
        clients = { retail = true, mists = false, wrath = false },
        productId = "suite",
        featureKey = FEATURE_KEY,
        dataRoot = "profile",
        dataPaths = { "YDamageMeter" },
        fieldWhitelists = {
            YDamageMeter = TRANSFER_FIELDS,
        },
        manageFeatureState = feature ~= nil,
        requiresReload = true,
    })
end

RegisterConfigTransfer()
