local ADDON_NAME = ...
local YUI = _G.YUI
YUI.Settings = YUI.Settings or {}
if YUI.Settings._coreLoaded then
    return
end
local S = YUI.Settings
S._coreLoaded = true
local GUI2 = YUI.GUI2
local LC = YUI.Locale:Get("Core")
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local Assets = YUI.Assets
local bootstrapState = _G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME]
local defaultSettingsProductId = (bootstrapState and bootstrapState.productId) or YUI.ProductId or "suite"

local Elements = {}
S.Elements = Elements

local SETTINGS_ANIMATION_KEY = "settings-window"
local SETTINGS_ANIMATION_DISTANCE = 24
local SETTINGS_ANIMATION_DURATION = 0.18
local SETTINGS_POPUP_DURATION = 0.14
local SETTINGS_BACKGROUND_ALPHA = 0.78
local SETTINGS_BACKGROUND_CROP_LEFT = 0.05
local SETTINGS_BACKGROUND_CROP_RIGHT = 0.95

-- Only explicitly owned settings windows participate; game frames and designers do not.
local settingsScaleWindows = setmetatable({}, { __mode = "k" })
local FRAME_WIDTH = 950
local FRAME_HEIGHT = 600
local SETTINGS_SCREEN_MARGIN = 16
local function NormalizeSettingsScale(value)
    value = tonumber(value) or 1
    if value ~= value then value = 1 end
    return math.floor(math.max(0.7, math.min(2, value)) * 100 + 0.5) / 100
end

function S:GetWindowScaleLimit()
    if not (UIParent and UIParent.GetWidth and UIParent.GetHeight) then return 2 end
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if not (width and height and width > 0 and height > 0) then return 2 end
    local fit = math.min((width - SETTINGS_SCREEN_MARGIN * 2) / FRAME_WIDTH,
        (height - SETTINGS_SCREEN_MARGIN * 2) / FRAME_HEIGHT, 2)
    -- Round down so the applied percentage never exceeds the available viewport.
    return math.max(0.01, math.floor(fit * 100) / 100)
end

function S:GetWindowScale()
    local db = YUI.DB and YUI.DB:GetGlobal(defaultSettingsProductId)
    return math.min(NormalizeSettingsScale(db and db.settingsWindowScale), self:GetWindowScaleLimit())
end

function S:IsScaleOwner(frame)
    while frame and frame ~= UIParent do
        if frame.yuiSettingsScaleRoot then return true end
        frame = frame.GetParent and frame:GetParent()
    end
    return false
end

function S:GetVisibleScaleOwner()
    local frame = Elements.frame
    return frame and frame:IsShown() and frame or nil
end

function S:RegisterScaleWindow(frame)
    if not frame then return end
    settingsScaleWindows[frame] = true
    frame.yuiSettingsScaleRoot = true
    frame:SetScale(self:GetWindowScale())
end

function S:SyncOwnedWindowScale(frame, owner)
    if self:IsScaleOwner(owner) then
        self:RegisterScaleWindow(frame)
    elseif settingsScaleWindows[frame] then
        settingsScaleWindows[frame] = nil
        frame.yuiSettingsScaleRoot = nil
        frame:SetScale(1)
    end
end

function S:SetWindowScale(value)
    value = math.min(NormalizeSettingsScale(value), self:GetWindowScaleLimit())
    local db = YUI.DB and YUI.DB:GetGlobal(defaultSettingsProductId)
    if db then db.settingsWindowScale = value end
    if GUI2.CloseDropdown then GUI2:CloseDropdown(true) end
    for frame in pairs(settingsScaleWindows) do
        frame:SetScale(value)
    end
    local main = Elements.frame
    if main and main.GetLeft and main.GetEffectiveScale then
        local left, right, top, bottom = main:GetLeft(), main:GetRight(), main:GetTop(), main:GetBottom()
        local ratio = main:GetEffectiveScale() / UIParent:GetEffectiveScale()
        if not (left and right and top and bottom)
            or left * ratio < SETTINGS_SCREEN_MARGIN
            or right * ratio > UIParent:GetWidth() - SETTINGS_SCREEN_MARGIN
            or bottom * ratio < SETTINGS_SCREEN_MARGIN
            or top * ratio > UIParent:GetHeight() - SETTINGS_SCREEN_MARGIN then
            main:ClearAllPoints()
            main:SetPoint("CENTER", UIParent, "CENTER")
        end
    end
    if Elements.scaleControl and Elements.scaleControl.RefreshAppliedScale then
        Elements.scaleControl:RefreshAppliedScale()
    end
    if GUI2.QueuePixelRefresh then GUI2:QueuePixelRefresh() end
end

local function ResolveSettingsBackgroundTexture()
    if Assets and Assets.Core then
        return Assets:Core("gui2\\settings\\settings-background-v1.png")
    end
    return "Interface\\AddOns\\" .. (YUI.AddonName or ADDON_NAME or "YUI")
        .. "\\Media\\Core\\gui2\\settings\\settings-background-v1.png"
end

local function GetSettingsBackgroundMode()
    local appearance = GUI2 and GUI2.Appearance
    if appearance and appearance.GetSettingsBackgroundMode then
        return appearance:GetSettingsBackgroundMode()
    end
    return "artwork"
end

function S:RefreshSettingsBackground()
    local backgroundArt = Elements.backgroundArt
    if not backgroundArt then return end
    backgroundArt:SetShown(GetSettingsBackgroundMode() == "artwork")
end

local function PlaySettingsOpen(frame)
    if not frame then return end
    frame.yuiSettingsClosing = nil
    frame.yuiSettingsCombatClosing = nil
    if frame.EnableMouse then frame:EnableMouse(true) end
    if GUI2 and GUI2.SlideIn then
        GUI2:SlideIn(frame, {
            owner = S,
            key = SETTINGS_ANIMATION_KEY,
            from = "bottom",
            distance = SETTINGS_ANIMATION_DISTANCE,
            duration = SETTINGS_ANIMATION_DURATION,
        })
    else
        frame:Show()
        if frame.SetAlpha then frame:SetAlpha(1) end
    end
end

local function PlaySettingsClose(frame)
    if not frame or not frame:IsShown() then return end
    S:Close({ immediate = true })
end

local function PlaySettingsPopup(frame, key)
    if frame and GUI2 and GUI2.SlideIn then
        GUI2:SlideIn(frame, {
            owner = S,
            key = key or "settings-popup",
            from = "bottom",
            distance = 14,
            duration = SETTINGS_POPUP_DURATION,
        })
    end
end

-- GUI2 method proxies shared by Settings modules.
S.Colors = GUI2.Colors
S.Fonts = GUI2.Fonts
S.CreateText = function(_, ...) return GUI2:CreateText(...) end
S.CreateButton = function(_, ...) return GUI2:CreateButton(...) end
S.CreateSlider = function(_, ...) return GUI2:CreateSlider(...) end
S.CreateDropdown = function(_, ...) return GUI2:CreateDropdown(...) end
S.CreateEditBox = function(_, ...) return GUI2:CreateEditBox(...) end
S.CreateCheckBox = function(_, ...) return GUI2:CreateCheckBox(...) end
S.CreateColorPicker = function(_, ...) return GUI2:CreateColorPicker(...) end
S.SkinCheckBox = function(_, ...) return GUI2:SkinCheckBox(...) end
S.SkinEditBox = function(_, ...) return GUI2:SkinEditBox(...) end
S.CreateCloseButton = function(_, ...) return GUI2:CreateCloseButton(...) end

local function ColorByte(value)
    value = tonumber(value) or 1
    if value < 0 then value = 0 elseif value > 1 then value = 1 end
    return math.floor(value * 255 + 0.5)
end

function S:FormatYieldNotice(featureKey, controller, featureLabel)
    if YUI.Yield and type(YUI.Yield.FormatNotice) == "function" then
        return YUI.Yield:FormatNotice(featureKey, controller, featureLabel)
    end
    return string.format(
        "YUI的【%s】功能与【%s】重复，已取消启用",
        tostring(featureLabel or featureKey or "功能"),
        tostring(controller or LC["settings.yield.controller.unknown"] or "其他同类插件")
    )
end

local TEXT_TONE_KEYS = {
    accent = "color.text.accent",
    heading = "color.text.heading",
    danger = "color.state.danger",
    error = "color.state.error",
    info = "color.state.info",
    muted = "color.text.muted",
    primary = "color.text.primary",
    secondary = "color.text.secondary",
    success = "color.state.success",
    warning = "color.state.warning",
}

local function GetTextColorKey(item, fallback)
    if not item then return fallback end
    if item.colorKey then return item.colorKey end
    if item.tone and TEXT_TONE_KEYS[item.tone] then return TEXT_TONE_KEYS[item.tone] end
    return fallback
end

local function ApplyConfigTextColor(text, item, fallback)
    local colorKey = GetTextColorKey(item, fallback)
    if colorKey then
        GUI2:SetTextColorKey(text, colorKey)
    elseif item and item.color then
        text.gui2ColorKey = nil
        text.gui2ColorFallback = nil
        text:SetTextColor(unpack(item.color))
    end
end

local FORM_LAYOUT_TYPES = {
    checkbox = true,
    color = true,
    dropdown = true,
    editbox = true,
    font = true,
    glow = true,
    sound = true,
    notificationSound = true,
    specDropdown = true,
    specdropdown = true,
    binarychoice = true,
    segmented = true,
    slider = true,
    switch = true,
    texture = true,
}

local function BuildLSMMediaDropdownOptions(mediaType, opts)
    opts = type(opts) == "table" and opts or {}
    local options = {}
    local seen = {}

    if mediaType == "sound" and opts.includeNone ~= false then
        local noneText = opts.noneText or "None"
        options[#options + 1] = { text = noneText, value = "None" }
        seen.None = true
    end

    local list = LSM and LSM.List and LSM:List(mediaType)
    if type(list) == "table" then
        for _, name in ipairs(list) do
            if type(name) == "string" and name ~= "" and not seen[name] then
                options[#options + 1] = { text = name, value = name }
                seen[name] = true
            end
        end
    elseif LSM and LSM.HashTable then
        local mediaTable = LSM:HashTable(mediaType)
        if type(mediaTable) == "table" then
            local names = {}
            for name in pairs(mediaTable) do
                if type(name) == "string" and name ~= "" and not seen[name] then
                    names[#names + 1] = name
                end
            end
            table.sort(names)
            for _, name in ipairs(names) do
                options[#options + 1] = { text = name, value = name }
                seen[name] = true
            end
        end
    end

    if #options == 0 and mediaType == "sound" then
        options[1] = { text = opts.noneText or "None", value = "None" }
    end

    return options
end

-- Texture selector widget.
function S:CreateTextureSelector(parent, config)
    local textureList = LSM and LSM.HashTable and LSM:HashTable("statusbar") or {}
    local options = {}
    
    -- 构建下拉菜单选项
    for name, path in pairs(textureList) do
        table.insert(options, {
            text = name,
            value = name, -- Store the Key, not the Path, for LSM compatibility
            texturePath = path, -- Store path for preview lookup
            -- 自定义渲染：将选项按钮的背景替换为材质预览
            render = function(btn)
                -- 创建或复用预览纹理
                if not btn.bgPreview then
                    btn.bgPreview = GUI2:CreateTexture(btn, { layer = "BACKGROUND", subLevel = 1 }) -- SubLevel 1，高于默认背景
                    btn.bgPreview:SetAllPoints(btn)
                    btn.bgPreview:SetVertexColor(1, 1, 1) -- 保持原色
                end
                
                -- 无条件设置纹理，确保显示
                btn.bgPreview:SetTexture(path)
                btn.bgPreview:Show()
                
                -- 隐藏默认背景
                if btn.bg then btn.bg:Hide() end
                
                -- 处理高亮和选中状态，避免遮挡预览
                -- 尝试获取并调整高亮纹理的透明度
                local hl = btn:GetHighlightTexture()
                if hl then hl:SetAlpha(0.3) end
                
                -- 调整文字样式
                if btn.text then
                    btn.text:SetTextColor(1, 1, 1)
                    btn.text:SetShadowColor(0, 0, 0, 1)
                    btn.text:SetShadowOffset(1, -1)
                    -- btn.text:SetPoint("LEFT", 5, 0)
                    btn.text:SetDrawLayer("OVERLAY", 7)
                    
                    -- 限制文本宽度，防止换行
                    btn.text:SetWordWrap(false)
                    btn.text:SetWidth(btn:GetWidth() - 25) -- 留出右侧勾选框空间
                end
            end
        })
    end
    table.sort(options, function(a, b) return a.text < b.text end)

    local function ResolveTextureValue(value)
        if type(value) ~= "string" or value == "" then
            return value, value
        end
        for _, option in ipairs(options) do
            if option.value == value or option.text == value then
                return option.value, option.texturePath
            end
        end

        local path = value
        if GUI2.GetStatusBarTexture then
            local ok, resolved = pcall(
                GUI2.GetStatusBarTexture,
                GUI2,
                value
            )
            if ok and type(resolved) == "string" then
                path = resolved
            end
        elseif not string.find(value, "\\", 1, true)
            and LSM and LSM.Fetch then
            path = LSM:Fetch("statusbar", value, true) or value
        end
        for _, option in ipairs(options) do
            if option.texturePath == path then
                return option.value, path
            end
        end
        return value, path
    end
    
    config.options = options
    
    -- 包装 get 方法以处理默认值
    local originalGet = config.get
    if not originalGet and config.key then
        originalGet = function()
            if YUI.getConfigByKey then
                return YUI:getConfigByKey(config.key, config.default or "Interface\\TargetingFrame\\UI-StatusBar")
            end
            return config.default or "Interface\\TargetingFrame\\UI-StatusBar"
        end
    end
    
    config.get = function()
        local value = originalGet and originalGet()
        local resolved = ResolveTextureValue(value)
        return resolved
    end
    
    -- 创建下拉菜单
    local dropdown = S:CreateDropdown(parent, config)
    
    -- 使用下拉菜单背景内的纹理作为预览，保留标准边框和 hover 状态。
    local previewParent = dropdown.bg or dropdown
    local preview = GUI2:CreateTexture(previewParent, { layer = "ARTWORK" })
    preview:SetAllPoints(previewParent)
    preview:SetVertexColor(1, 1, 1)
    dropdown.bgPreview = preview
    
    -- 调整文字颜色和阴影，确保在亮色纹理上可见
    if dropdown.text then
        dropdown.text:SetTextColor(1, 1, 1) 
        dropdown.text:SetShadowColor(0, 0, 0, 1)
        dropdown.text:SetShadowOffset(1, -1)
        dropdown.text:SetDrawLayer("OVERLAY", 7) -- 确保文字在最上层
    end

    -- 更新预览函数
    local function UpdatePreview(val)
        if not val then return end
        local _, path = ResolveTextureValue(val)

        preview:SetTexture(path)
        preview:Show()
    end

    -- 钩住 SetText 方法来更新预览
    hooksecurefunc(dropdown, "SetText", function(self, text)
        UpdatePreview(text)
    end)
    
    -- 初始化预览
    local currentVal = config.get and config.get()
    
    -- 如果 currentVal 存在，我们需要确保下拉框的文字也更新，这样看起来才一致
    if currentVal then
        -- 尝试找到对应的 text
        local foundName = nil
        -- 如果 currentVal 是材质名
        for _, opt in ipairs(options) do
            if opt.text == currentVal then
                foundName = opt.text
                break
            end
        end
        
        -- 如果没找到，按路径反向查找 LSM 名称。
        if not foundName and string.find(currentVal, "\\", 1, true) then
            for _, opt in ipairs(options) do
                if opt.texturePath == currentVal then
                    foundName = opt.text
                    break
                end
            end
        end
        
        -- 如果找到了名字，更新下拉框文字，这会触发 SetText 钩子进而调用 UpdatePreview
        if foundName then
            dropdown:SetText(" " .. foundName)
        else
            -- 没找到名字（可能不在列表中），直接显示值并更新预览
            -- 注意：如果 dropdown 内部 SetText 只是设置 fontString，我们需要手动调用 UpdatePreview
            -- 但因为我们 hook 了 SetText，所以只要调用 SetText 就会更新预览
            dropdown:SetText(" " .. currentVal)
        end
        
        -- 强制再调用一次 UpdatePreview 以防万一 (例如 SetText 被重写或者 hook 没生效)
        UpdatePreview(currentVal)
    end
    
    -- Dropdown 的 OnClick 会调用 config.set，我们需要在 set 之后更新预览
    local originalSet = config.set
    config.set = function(val)
        if originalSet then originalSet(val) end
        UpdatePreview(val)
    end

    if dropdown.SetValue then
        local originalSetValue = dropdown.SetValue
        dropdown.SetValue = function(self, value, silent)
            local resolved = ResolveTextureValue(value)
            return originalSetValue(self, resolved, silent)
        end
    end
    
    return dropdown
end

-- 缓存 Lua 全局变量
local ipairs, unpack, tinsert = ipairs, unpack, table.insert

-- 缓存 WoW 全局变量

local UIParent = UIParent
local C_Timer = C_Timer
local SecurityAPI = YUI.API and YUI.API.Security or YUI.WOW_API
local SystemAPI = YUI.API and YUI.API.System or YUI.WOW_API
local FrameAPI = YUI.API and YUI.API.Frame or YUI.WOW_API

local function SettingsInCombat()
    if SecurityAPI and SecurityAPI.InCombatLockdown then
        return SecurityAPI.InCombatLockdown() == true
    end
    return InCombatLockdown and InCombatLockdown() == true or false
end

local function PrintSettingsMessage(key, fallback)
    local text = LC[key] or fallback
    if YUI.Print then
        YUI:Print(text)
    elseif print then
        print(text)
    end
end

-- moved to Dev/Dev.lua

S.modules = S.modules or {}
S.modulesById = S.modulesById or {}
S.providers = S.modules
S.ModuleOrder = S.ModuleOrder or {} -- 模块显示顺序配置
local ModulePageLayout = S.ModulePageLayout or {}
S.ModulePageLayout = ModulePageLayout
ModulePageLayout.insetX = 20
ModulePageLayout.titleTop = 20
S.ActiveScope = S.ActiveScope or YUI.SettingsScope or "suite"
S.ActiveProductId = S.ActiveProductId or defaultSettingsProductId
local selectedModule = nil
local SortModules
local RefreshProductIdentity
local RefreshEditModeButton
local RefreshHeaderActions

local function GetModuleDisplayName(module)
    if module and module.titleKey then
        local locale = module.titleNamespace and YUI.Locale:Get(module.titleNamespace) or LC
        return locale[module.titleKey]
    end
    return module and module.name or ""
end

local function GetModuleNavDisplayName(module)
    if module and module.navTitleKey then
        local locale = module.navTitleNamespace and YUI.Locale:Get(module.navTitleNamespace) or LC
        return locale[module.navTitleKey]
    end
    return GetModuleDisplayName(module)
end

-- 常量
local NAV_WIDTH = 180
local NAV_TOGGLE_HIT_SIZE = 24
local NAV_TOGGLE_VISUAL_SIZE = 20
local NAV_TOGGLE_TEXT_INSET = 34
local NAV_TOGGLE_TEXTURE_ENABLED = Assets:Core("gui2\\icons\\settings\\nav-toggle-gem.png")
local NAV_TOGGLE_TEXTURE_HOVER = Assets:Core("gui2\\icons\\settings\\nav-toggle-gem-hover.png")
local NAV_TOGGLE_TEXTURE_DISABLED = Assets:Core("gui2\\icons\\settings\\nav-toggle-empty.png")
local NAV_TOGGLE_TEXTURE_SETS = {
    midnight = {
        enabled = NAV_TOGGLE_TEXTURE_ENABLED,
        hover = NAV_TOGGLE_TEXTURE_HOVER,
        disabled = NAV_TOGGLE_TEXTURE_DISABLED,
    },
    gilded = {
        enabled = Assets:Core("gui2\\icons\\settings\\nav-toggle-gilded.png"),
        hover = Assets:Core("gui2\\icons\\settings\\nav-toggle-gilded-hover.png"),
        disabled = Assets:Core("gui2\\icons\\settings\\nav-toggle-gilded-empty.png"),
    },
    ["astral-violet"] = {
        enabled = Assets:Core("gui2\\icons\\settings\\nav-toggle-astral-violet.png"),
        hover = Assets:Core("gui2\\icons\\settings\\nav-toggle-astral-violet-hover.png"),
        disabled = Assets:Core("gui2\\icons\\settings\\nav-toggle-astral-violet-empty.png"),
    },
}
local NAV_BUTTON_HEIGHT = 34
local NAV_BUTTON_GAP = 2
local NAV_FOOTER_HEIGHT = 38
local NAV_START_OFFSET = -108
local NAV_START_OFFSET_WITH_PRODUCT = -132
local HEADER_HEIGHT = 40
local GAP = 10
local MAIN_NAV_FONT_DELTA = 2
local RIGHT_PREVIEW_DEFAULT_WIDTH = 220
local RIGHT_PREVIEW_DEFAULT_HEIGHT = 220
local RIGHT_PREVIEW_GAP = 12
local RIGHT_PREVIEW_INSET = 12
local RIGHT_PREVIEW_TITLE_HEIGHT = 26
local SPEC_DROPDOWN_WIDTH = 220
local SPEC_DROPDOWN_HEIGHT = 26
local SPEC_PANEL_INSET = 12
local SPEC_PANEL_GAP = 8
local SPEC_PANEL_SCROLLBAR_RESERVE = 22
local SPEC_PANEL_COLUMNS = 3
local SPEC_BUTTON_WIDTH = 100
local SPEC_PANEL_WIDTH = SPEC_PANEL_INSET * 2
    + SPEC_PANEL_SCROLLBAR_RESERVE
    + SPEC_PANEL_COLUMNS * SPEC_BUTTON_WIDTH
    + (SPEC_PANEL_COLUMNS - 1) * SPEC_PANEL_GAP
local SPEC_PANEL_HEIGHT = 430
local SPEC_BUTTON_HEIGHT = 28
local SPEC_ICON_SIZE = 18
local SPEC_DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local SPEC_CLASS_ICON_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local SPEC_CLASS_ICON_TEXCOORD_INSET = 0.07

local SPEC_ARMOR_GROUPS = {
    { key = "cloth", fallback = "Cloth", classes = { "MAGE", "PRIEST", "WARLOCK" } },
    { key = "leather", fallback = "Leather", classes = { "DEMONHUNTER", "MONK", "ROGUE", "DRUID" } },
    { key = "mail", fallback = "Mail", classes = { "EVOKER", "HUNTER", "SHAMAN" } },
    { key = "plate", fallback = "Plate", classes = { "DEATHKNIGHT", "PALADIN", "WARRIOR" } },
}

local function GetSpecDisplayName(specID, fallback)
    if YUI.Locale and YUI.Locale.GetSpecializationName then
        return YUI.Locale:GetSpecializationName(specID, fallback)
    end
    return fallback or (specID and tostring(specID)) or ""
end

function S:GetSpecDisplayName(specID, fallback)
    return GetSpecDisplayName(specID, fallback)
end

local function ApplyMainNavTextStyle(button)
    if not button or not button.text then return end
    button.text:SetFont(GUI2:GetFont("font.family.body"), GUI2:GetMetric("font.size.md", 13) + MAIN_NAV_FONT_DELTA, "")
end

local function NormalizeProviderMeta(name, meta)
    meta = type(meta) == "table" and meta or {}
    local product = meta.product or "suite"
    local scope = meta.scope or product
    return {
        id = meta.id or (product .. "." .. name),
        product = product,
        scope = scope,
        titleKey = meta.titleKey,
        titleNamespace = meta.titleNamespace,
        navTitleKey = meta.navTitleKey,
        navTitleNamespace = meta.navTitleNamespace,
        navIconCrop = meta.navIconCrop,
        navIconSize = meta.navIconSize,
        navToggle = meta.navToggle,
        suiteOnly = meta.suiteOnly == true,
        standaloneOnly = meta.standaloneOnly == true,
        hidden = meta.hidden == true,
    }
end

local function GetProduct(productId)
    return productId and YUI.Products and YUI.Products[productId] or nil
end

local function GetProductDisplayName(product)
    if YUI.GetProductShortTitle then
        return YUI:GetProductShortTitle(product)
    end
    if YUI.GetProductTitle then
        local title = YUI:GetProductTitle(product)
        local shortTitle = type(title) == "string" and title:match("^(.-)%s*·%s*.+$") or nil
        return shortTitle or title
    end
    return product and (product.title or product.id) or ""
end

local function ProductHasSettings(product)
    return product and product.settings and product.settings.enabled == true
end

local function ProductUsesSuiteSettings(product)
    return product and product.settings and product.settings.mode == "suite"
end

local function ProductHasChangelog(product)
    local changelog = YUI.Changelog
    return ProductHasSettings(product) and changelog and changelog.HasData and changelog:HasData(product.id)
end

local function SuiteOwnsSettings()
    return ProductUsesSuiteSettings(GetProduct("suite"))
end

local function NormalizeSettingsProductId(productId)
    if SuiteOwnsSettings() then
        return "suite"
    end
    return productId
end

local function ProductHasCommonPage(product, pageId)
    if not product or not product.settings or type(product.settings.commonPages) ~= "table" then
        return false
    end
    for _, id in ipairs(product.settings.commonPages) do
        if id == pageId then
            return true
        end
    end
    return false
end

function S:GetSettingsProducts()
    local suiteProduct = GetProduct("suite")
    if ProductHasSettings(suiteProduct) and SuiteOwnsSettings() then
        return { suiteProduct }
    end

    local products = {}
    if YUI.Products then
        for _, product in pairs(YUI.Products) do
            if ProductHasSettings(product) and not (YUI.BlockedProducts and YUI.BlockedProducts[product.id]) then
                products[#products + 1] = product
            end
        end
    end
    table.sort(products, function(a, b)
        local orderA = a.order or (a.id == "suite" and 0 or 100)
        local orderB = b.order or (b.id == "suite" and 0 or 100)
        if orderA ~= orderB then
            return orderA < orderB
        end
        return GetProductDisplayName(a) < GetProductDisplayName(b)
    end)
    return products
end

function S:GetDefaultProductId()
    if SuiteOwnsSettings() then
        return "suite"
    end

    local activeProduct = GetProduct(S.ActiveProductId)
    if ProductHasSettings(activeProduct) then
        return S.ActiveProductId
    end

    local defaultProduct = GetProduct(defaultSettingsProductId)
    if ProductHasSettings(defaultProduct) then
        return defaultSettingsProductId
    end

    local dbProductId = YUI.DB and YUI.DB.activeProductId
    local dbProduct = GetProduct(dbProductId)
    if ProductHasSettings(dbProduct) then
        return dbProductId
    end

    local ownProduct = GetProduct(YUI.ProductId)
    if ProductHasSettings(ownProduct) then
        return YUI.ProductId
    end

    local products = S:GetSettingsProducts()
    return products[1] and products[1].id or defaultSettingsProductId or YUI.ProductId or "suite"
end

function S:IsModuleVisible(module)
    if not module then
        return false
    end
    if module.hidden then
        return false
    end

    local product = GetProduct(S.ActiveProductId)
    local usesSuiteSettings = ProductUsesSuiteSettings(product)
    if module.suiteOnly and not usesSuiteSettings then
        return false
    end
    if module.standaloneOnly and usesSuiteSettings then
        return false
    end

    if usesSuiteSettings then
        if S.ModuleOrder and #S.ModuleOrder > 0 then
            for _, key in ipairs(S.ModuleOrder) do
                if key == module.id or key == module.name then
                    return true
                end
            end
            return false
        end
        return true
    end

    if module.product == S.ActiveProductId then
        return true
    end

    return ProductHasCommonPage(product, module.id)
end

local function ClearSelectedModule()
    if S.ClearRightPreview then
        S:ClearRightPreview()
    end
    if S.CloseSpecMultiSelectDropdown then
        S:CloseSpecMultiSelectDropdown()
    end
    if selectedModule and selectedModule.frame then
        selectedModule.frame:Hide()
    end
    selectedModule = nil
end

local function HideInactiveModuleFrames(activeModule)
    for _, module in ipairs(S.modules or {}) do
        if module ~= activeModule and module.frame then
            module.frame:Hide()
        end
    end
end

local function GetContentAreaWidth()
    if Elements.content and Elements.content.GetWidth then
        local width = Elements.content:GetWidth()
        if width and width > 1 then
            return width
        end
    end
    return FRAME_WIDTH - NAV_WIDTH - GAP * 3
end

local function UpdateRightPreviewLayout()
    local scrollFrame = Elements.scrollFrame
    local scrollChild = Elements.scrollChild
    if not scrollFrame then return end

    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT)
    local contentWidth = GetContentAreaWidth()
    local scrollWidth = contentWidth - 40

    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)
    scrollWidth = math.max(scrollWidth or 1, 1)
    if scrollChild then
        scrollChild:SetWidth(scrollWidth)
        for _, module in ipairs(S.modules or {}) do
            if module.frame and module.frame.SetWidth then
                module.frame:SetWidth(scrollWidth)
            end
        end
    end
end

function S:InvalidateModuleFrames()
    self:ClearRightPreview()
    self:CloseSpecMultiSelectDropdown()
    for _, module in ipairs(S.modules or {}) do
        if module.frame then
            module.frame:Hide()
            module.frame = nil
        end
    end
    if Elements.scrollChild then
        S:ClearConfig(Elements.scrollChild)
    end
end

function S:SetScope(scope)
    if not scope or scope == "" then
        scope = "suite"
    end

    S.ActiveScope = scope
    if selectedModule and not S:IsModuleVisible(selectedModule) then
        ClearSelectedModule()
    end

    if Elements.frame then
        S:RefreshNav()
    end
end

function S:GetSelectedModule()
    return selectedModule
end

function S:IsOpen()
    return Elements.frame and Elements.frame:IsShown() and not Elements.frame.yuiSettingsClosing
end

function S:GetOpenState()
    local module = S:GetSelectedModule()
    return {
        productId = S.ActiveProductId,
        scope = S.ActiveScope,
        entry = module and module.id or nil,
    }
end

function S:EnsureVisibleSelection()
    if selectedModule and not S:IsModuleVisible(selectedModule) then
        ClearSelectedModule()
    end

    if not Elements.frame then
        return
    end

    S:RefreshNav()
    if Elements.frame:IsShown() and not selectedModule then
        local visibleModules = S:GetVisibleModules()
        if #visibleModules > 0 then
            S:SelectModule(visibleModules[1])
        end
    end
end

function S:SetActiveProduct(productId)
    productId = productId or S:GetDefaultProductId()
    if not productId or productId == "" then
        productId = "suite"
    end
    productId = NormalizeSettingsProductId(productId)

    if S.ActiveProductId ~= productId then
        S.ActiveProductId = productId
        if S.Search then S.Search:Close(); S.Search.index = nil end
        selectedModule = nil
        S:InvalidateModuleFrames()
    else
        S.ActiveProductId = productId
    end

    if YUI.DB and YUI.DB.SetActiveProduct then
        YUI.DB:SetActiveProduct(productId)
    end

    if RefreshProductIdentity then
        RefreshProductIdentity()
    end
    if Elements.frame then
        S:RefreshNav()
    end
end

function S:GetVisibleModules()
    SortModules()

    local visible = {}
    for _, module in ipairs(S.modules) do
        if S:IsModuleVisible(module) then
            tinsert(visible, module)
        end
    end
    return visible
end

function S:RegisterModule(name, icon, renderFunc, meta)
    if self.Search then self.Search.index = nil end
    local provider = NormalizeProviderMeta(name, meta)
    local existing = S.modulesById[provider.id]
    if existing then
        existing.name = name
        existing.icon = icon
        existing.render = renderFunc
        existing.product = provider.product
        existing.scope = provider.scope
        existing.titleKey = provider.titleKey
        existing.titleNamespace = provider.titleNamespace
        existing.navTitleKey = provider.navTitleKey
        existing.navTitleNamespace = provider.navTitleNamespace
        existing.navIconCrop = provider.navIconCrop
        existing.navIconSize = provider.navIconSize
        existing.navToggle = provider.navToggle
        existing.suiteOnly = provider.suiteOnly
        existing.standaloneOnly = provider.standaloneOnly
        existing.hidden = provider.hidden
        if Elements.frame then
            S:RefreshNav()
        end
        return existing
    end

    local module = {
        name = name,
        icon = icon,
        render = renderFunc,
        id = provider.id,
        product = provider.product,
        scope = provider.scope,
        titleKey = provider.titleKey,
        titleNamespace = provider.titleNamespace,
        navTitleKey = provider.navTitleKey,
        navTitleNamespace = provider.navTitleNamespace,
        navIconCrop = provider.navIconCrop,
        navIconSize = provider.navIconSize,
        navToggle = provider.navToggle,
        suiteOnly = provider.suiteOnly,
        standaloneOnly = provider.standaloneOnly,
        hidden = provider.hidden,
        registerIndex = #S.modules + 1 -- 记录注册顺序
    }
    table.insert(S.modules, module)
    S.modulesById[provider.id] = module
    if Elements.frame then
        S:RefreshNav()
    end
    return module
end

function S:RegisterProvider(provider)
    if type(provider) ~= "table" then return end
    local name = provider.title or provider.name or provider.id
    if not name or not provider.render then return end
    return S:RegisterModule(name, provider.icon, provider.render, provider)
end

function S:IsCombatBlocked()
    return SettingsInCombat() == true
end

function S:PrintCombatBlocked()
    PrintSettingsMessage("settings.combat_blocked", "Settings cannot be opened in combat.")
end

function S:CloseTransientUI()
    if self.Search then self.Search:Close() end
    if S.ClearRightPreview then
        S:ClearRightPreview()
    end
    if S.CloseSpecMultiSelectDropdown then
        S:CloseSpecMultiSelectDropdown()
    end
    if S.CopyFrame then
        S.CopyFrame:Hide()
    end
    if S.SocialFrame then
        S.SocialFrame:Hide()
    end
    if S.ConfirmFrame then
        S.ConfirmFrame:Hide()
    end
    if S.ConfigSetPicker and S.ConfigSetPicker.Close then
        S.ConfigSetPicker:Close()
    end
    if GameTooltip then
        if YUI.HideGameTooltip then
            YUI.HideGameTooltip()
        else
            GameTooltip:Hide()
        end
    end
end

function S:CloseForCombat()
    if not S:IsOpen() then
        S:CloseTransientUI()
        return false
    end
    if Elements.frame then
        Elements.frame.yuiSettingsCombatClosing = true
    end
    PlaySettingsClose(Elements.frame)
    PrintSettingsMessage("settings.combat_closed", "Entering combat closed the settings window.")
    return true
end

function S:Toggle()
    if S:IsOpen() then
        if S:IsCombatBlocked() then
            S:CloseForCombat()
            return false
        end
        S:Close()
        return true
    end
    if S:IsCombatBlocked() then
        S:PrintCombatBlocked()
        return false
    end
    S:SetActiveProduct(S:GetDefaultProductId())
    if not Elements.frame then
        S:CreateMainFrame()
    end
    
    PlaySettingsOpen(Elements.frame)
    RefreshHeaderActions()
    -- Select first module if none selected
    local visibleModules = S:GetVisibleModules()
    if not selectedModule and #visibleModules > 0 then
        S:SelectModule(visibleModules[1])
    end
    return true
end

function S:Close(options)
    S:CloseTransientUI()
    -- 所有入口统一立即关闭，避免退场动画逐帧移动设置窗口。
    local frame = Elements.frame
    local animation = YUI.Animation
    if frame and animation and animation.StopTarget then
        -- 完成尚未结束的开启动画，恢复其最终锚点，避免再次打开时位置漂移。
        animation:StopTarget(frame, SETTINGS_ANIMATION_KEY, true)
    end
    if frame then
        frame.yuiSettingsClosing = nil
        if frame.SetAlpha then frame:SetAlpha(1) end
        if frame.EnableMouse then frame:EnableMouse(true) end
        frame:Hide()
        frame.yuiSettingsCombatClosing = nil
    end
    return true
end

local function RunOpenAfterHook(options, module)
    if type(options) ~= "table" or type(options.afterOpen) ~= "function" or not module then
        return
    end
    local ok, err = pcall(options.afterOpen, module, S, options)
    if not ok then
        print("|cffff0000YUI Settings Error:|r afterOpen - " .. tostring(err))
    end
end

function S:Open(options)
    if S:IsCombatBlocked() then
        S:PrintCombatBlocked()
        return nil, "combat"
    end
    if type(options) == "table" then
        if options.productId then
            S:SetActiveProduct(options.productId)
        else
            S:SetActiveProduct(S:GetDefaultProductId())
        end
        if options.scope then
            S:SetScope(options.scope)
        end
    else
        S:SetActiveProduct(S:GetDefaultProductId())
    end

    if not Elements.frame then
        S:CreateMainFrame()
    end

    if not Elements.frame:IsShown() or Elements.frame.yuiSettingsClosing then
        PlaySettingsOpen(Elements.frame)
    else
        Elements.frame:Show()
    end
    RefreshHeaderActions()

    local visibleModules = S:GetVisibleModules()
    if type(options) == "table" and options.entry then
        local target = S.modulesById[options.entry]
        if target and S:IsModuleVisible(target) then
            local selected = S:SelectModule(target)
            if selected ~= false then
                RunOpenAfterHook(options, target)
            end
            return target
        end
    end
    if not selectedModule and #visibleModules > 0 then
        local target = visibleModules[1]
        local selected = S:SelectModule(target)
        if selected ~= false then
            RunOpenAfterHook(options, target)
        end
        return target
    end
end

function S:OpenProduct(productId, entry, options)
    productId = productId or S:GetDefaultProductId()
    local product = GetProduct(productId)
    if product and product.settings and not entry then
        entry = product.settings.entry
    end
    productId = NormalizeSettingsProductId(productId)
    local openOptions = {}
    if type(options) == "table" then
        for key, value in pairs(options) do
            openOptions[key] = value
        end
    end
    openOptions.productId = productId
    openOptions.entry = entry
    return S:Open(openOptions)
end

function YUI:OpenSettings(moduleNameOrId, productId, options)
    if not S then return end
    productId = productId or S:GetDefaultProductId()

    local entry = moduleNameOrId
    if entry and not S.modulesById[entry] then
        for _, module in ipairs(S.modules or {}) do
            if module.name == moduleNameOrId then
                entry = module.id
                break
            end
        end
    end

    return S:OpenProduct(productId, entry, options)
end

function S:RefreshProducts()
    if not ProductHasSettings(GetProduct(S.ActiveProductId)) then
        S.ActiveProductId = S:GetDefaultProductId()
    end
    if RefreshProductIdentity then
        RefreshProductIdentity()
    end
    if Elements.frame then
        S:RefreshNav()
    end
end

local function RegisterSettingsSlash()
    if not SlashCmdList then return end

    SLASH_YUI1 = SLASH_YUI1 or "/yui"
    SlashCmdList["YUI"] = function(msg)
        if YUI.HandleSlashCommand and YUI:HandleSlashCommand(msg) then
            return
        end

        S:OpenProduct(S:GetDefaultProductId())
    end
end

RegisterSettingsSlash()

function S:ShowCopyPopup(title, text, options)
    if type(options) == "table" and options.multiline == true then
        return S:ShowMultilineCopyPopup(title, text)
    end
    if S.SocialFrame then S.SocialFrame:Hide() end
    if S.MultilineCopyFrame then S.MultilineCopyFrame:Hide() end
    if not S.CopyFrame then
        local f = GUI2:CreatePanel(UIParent, { name = "YUI_CopyFrame", width = 400, height = 120, surface = "color.surface.popup", border = "color.popup.border", shadow = true })
        S:RegisterScaleWindow(f)
        f:SetSize(400, 120)
        f:SetPoint("CENTER")
        f:SetFrameStrata("TOOLTIP")
        f:SetFrameLevel(9999) -- 确保在最上层
        f:EnableMouse(true)
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0.15, 0.15, 0.2, 0.98)
        f:SetBackdropBorderColor(GUI2:GetColor("color.popup.border"))
        
        GUI2:CreateShadow(f, "shadow.popup.size")
        local shadow = f.gui2Shadow
        shadow:SetPoint("TOPLEFT", -3, 3)
        shadow:SetPoint("BOTTOMRIGHT", 3, -3)
        shadow:SetFrameLevel(f:GetFrameLevel() > 0 and f:GetFrameLevel() - 1 or 0)
        shadow:SetBackdrop({
            edgeFile = Assets:Core("images\\GlowTex.tga"),
            edgeSize = 3,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        shadow:SetBackdropBorderColor(0, 0, 0, 0.5)
        f.shadow = shadow
        f.RefreshTheme = function(frame)
            frame.gui2Surface = "color.surface.popup"
            GUI2:RefreshPrimitive(frame)
            GUI2:SetBorderColor(frame, "color.popup.border")
            if frame.title then GUI2:SetTextColorKey(frame.title, "color.text.heading") end
            if frame.tip then GUI2:SetTextColorKey(frame.tip, "color.text.secondary") end
            if frame.editBox and frame.editBox.RefreshTheme then frame.editBox:RefreshTheme() end
        end
        GUI2:RegisterThemeObject(f)
        f:RefreshTheme()
        
        -- 自定义红色方形关闭按钮
        local close = GUI2:CreateCloseButton(f, function() f:Hide() end)
        close:SetPoint("TOPRIGHT", -5, -5)
        
        local titleText = GUI2:CreateText(f, "", GUI2.Fonts.size_header)
        titleText:SetPoint("TOP", 0, -15)
        GUI2:SetTextColorKey(titleText, "color.text.heading")
        f.title = titleText
        
        local editBox = GUI2:CreateEditBox(f, { width = 350, height = 30 })
        editBox:SetSize(350, 30)
        editBox:SetPoint("CENTER", 0, -10)
        editBox:SetFrameLevel(f:GetFrameLevel() + 5)
        
        local font, size, flag = GameFontHighlight:GetFont()
        editBox:SetFont(font, GUI2.Fonts.size_normal, "OUTLINE")
        
        editBox:SetTextColor(1, 1, 1, 1)
        editBox:SetTextInsets(5, 5, 0, 0)
        editBox:SetAutoFocus(true)
        GUI2:SkinEditBox(editBox)
        f.editBox = editBox
        
        local tip = GUI2:CreateText(f, LC["settings.copy_hint"], GUI2.Fonts.size_normal)
        tip:SetPoint("BOTTOM", 0, 15)
        GUI2:SetTextColorKey(tip, "color.text.secondary")
        f.tip = tip
        
        editBox:SetScript("OnEscapePressed", function() f:Hide() end)
        editBox:SetScript("OnEnterPressed", function() f:Hide() end)
        editBox:SetScript("OnTextChanged", function(self)
        end)
        
        S.CopyFrame = f
    end
    
    S.CopyFrame.title:SetText(title)
    S.CopyFrame.editBox:SetText(text or "")
    S.CopyFrame.editBox:SetCursorPosition(0)
    S.CopyFrame.editBox:HighlightText()
    S.CopyFrame:Show()
    PlaySettingsPopup(S.CopyFrame, "settings-copy-popup")
    S.CopyFrame.editBox:SetFocus()
end

local function RefreshMultilineCopyLayout(frame)
    local scroll = frame and frame.scrollFrame
    local editBox = frame and frame.editBox
    if not (scroll and editBox) then return end
    local viewportWidth = tonumber(scroll:GetWidth()) or 680
    local viewportHeight = tonumber(scroll:GetHeight()) or 320
    local lineCount = editBox.GetNumLines and editBox:GetNumLines() or 1
    editBox:SetWidth(math.max(80, viewportWidth - 4))
    editBox:SetHeight(math.max(viewportHeight, (math.max(1, lineCount) * 18) + 20))
    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
end

function S:ShowMultilineCopyPopup(title, text)
    if S.SocialFrame then S.SocialFrame:Hide() end
    if S.CopyFrame then S.CopyFrame:Hide() end
    if not S.MultilineCopyFrame then
        local f = GUI2:CreatePanel(UIParent, {
            name = "YUI_MultilineCopyFrame",
            width = 740,
            height = 420,
            surface = "color.surface.popup",
            border = "color.popup.border",
            shadow = true,
        })
        S:RegisterScaleWindow(f)
        f:SetPoint("CENTER")
        f:SetFrameStrata("TOOLTIP")
        f:SetFrameLevel(9999)
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        f:Hide()

        local close = GUI2:CreateCloseButton(f, function() f:Hide() end)
        close:SetPoint("TOPRIGHT", -5, -5)

        local titleText = GUI2:CreateText(f, "", GUI2.Fonts.size_header)
        titleText:SetPoint("TOP", 0, -15)
        GUI2:SetTextColorKey(titleText, "color.text.heading")
        f.title = titleText

        local scroll = GUI2:CreateScrollFrame(f, {
            name = "YUI_MultilineCopyScrollFrame",
            child = false,
            mouseWheel = true,
        })
        scroll:SetPoint("TOPLEFT", 20, -52)
        scroll:SetPoint("BOTTOMRIGHT", -38, 52)
        scroll:SetFrameLevel(f:GetFrameLevel() + 2)
        f.scrollFrame = scroll

        local editBox = GUI2.Form:CreateEditBox(scroll, {
            width = 678,
            height = 316,
            text = "",
            autoFocus = false,
        })
        editBox:SetMultiLine(true)
        if editBox.SetMaxLetters then editBox:SetMaxLetters(0) end
        editBox:SetTextInsets(8, 8, 8, 8)
        editBox:SetJustifyH("LEFT")
        if editBox.SetJustifyV then editBox:SetJustifyV("TOP") end
        editBox:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
        editBox:SetFrameLevel(scroll:GetFrameLevel() + 1)
        editBox:SetScript("OnEscapePressed", function() f:Hide() end)
        editBox:SetScript("OnTextChanged", function()
            RefreshMultilineCopyLayout(f)
        end)
        scroll:SetScrollChild(editBox)
        f.editBox = editBox

        local tip = GUI2:CreateText(f, LC["settings.copy_hint"], GUI2.Fonts.size_normal)
        tip:SetPoint("BOTTOM", 0, 17)
        GUI2:SetTextColorKey(tip, "color.text.secondary")
        f.tip = tip

        f.RefreshTheme = function(frame)
            frame.gui2Surface = "color.surface.popup"
            GUI2:RefreshPrimitive(frame)
            GUI2:SetBorderColor(frame, "color.popup.border")
            if frame.title then GUI2:SetTextColorKey(frame.title, "color.text.heading") end
            if frame.tip then GUI2:SetTextColorKey(frame.tip, "color.text.secondary") end
            if frame.editBox and frame.editBox.RefreshTheme then frame.editBox:RefreshTheme() end
        end
        GUI2:RegisterThemeObject(f)
        f:RefreshTheme()
        f:SetScript("OnSizeChanged", function() RefreshMultilineCopyLayout(f) end)
        S.MultilineCopyFrame = f
    end

    local frame = S.MultilineCopyFrame
    frame.title:SetText(title or "")
    frame:Show()
    frame.editBox:SetText(text or "")
    RefreshMultilineCopyLayout(frame)
    if frame.scrollFrame.SetVerticalScroll then frame.scrollFrame:SetVerticalScroll(0) end
    frame.editBox:SetCursorPosition(0)
    frame.editBox:HighlightText(0, -1)
    PlaySettingsPopup(frame, "settings-multiline-copy-popup")
    frame.editBox:SetFocus()
    return true
end

local SOCIAL_POPUP_WIDTH = 460
local SOCIAL_POPUP_ROW_HEIGHT = 28
local SOCIAL_POPUP_ROW_GAP = 6
local SOCIAL_POPUP_ROW_TOP = 48
local SOCIAL_POPUP_FOOTER_HEIGHT = 42
local SOCIAL_POPUP_HORIZONTAL_INSET = 20
local SOCIAL_POPUP_BADGE_GAP = 8
local SOCIAL_POPUP_BADGE_RESERVE = 60

local SOCIAL_BILIBILI_ROWS = {
    { text = "阿言同学AI" },
    { text = "https://space.bilibili.com/43313099" },
}

local SOCIAL_DOUYIN_ROWS = {
    { text = "阿言YUI" },
    { text = "https://www.douyin.com/user/MS4wLjABAAAA-JzrkAy8gbpvF_bEuKTwuzZk5E85QwKPp9NBmeEEI5AOgYwoHA_WC3sqeGS3s9DX" },
}

local SOCIAL_QQ_GROUPS = {
    Forever = {
        "1011115763",
    },
    Retail = {
        "223511811",
        "983196010",
        "494453168",
        "955124663",
    },
    Mists = {
        "238386717",
        "2157042187",
    },
    Wrath = {
        "238386717",
        "2157042187",
    },
}

local function BuildQQSocialRows()
    local groups = SOCIAL_QQ_GROUPS[YUI.GameVersion] or SOCIAL_QQ_GROUPS.Retail
    local rows = {}
    for index, groupNumber in ipairs(groups) do
        rows[index] = {
            text = groupNumber,
            recommended = index == 1,
        }
    end
    return rows
end

local function SelectSocialPopupRow(editBox)
    if not editBox then return end
    local frame = S.SocialFrame
    local previous = frame and frame.selectedEditBox
    if previous and previous ~= editBox then
        previous:HighlightText(0, 0)
        previous:ClearFocus()
    end
    if frame then frame.selectedEditBox = editBox end
    editBox:SetFocus()
    editBox:SetCursorPosition(0)
    editBox:HighlightText(0, -1)
end

local function AcquireSocialPopupRow(frame, index)
    local row = frame.rows[index]
    if row then return row end

    local container = GUI2:CreateFrame(frame)
    container:SetHeight(SOCIAL_POPUP_ROW_HEIGHT)
    container:SetWidth(SOCIAL_POPUP_WIDTH - (SOCIAL_POPUP_HORIZONTAL_INSET * 2))
    container:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        SOCIAL_POPUP_HORIZONTAL_INSET,
        -SOCIAL_POPUP_ROW_TOP - ((index - 1) * (SOCIAL_POPUP_ROW_HEIGHT + SOCIAL_POPUP_ROW_GAP))
    )

    local editBox = GUI2:CreateEditBox(container, {
        width = SOCIAL_POPUP_WIDTH - (SOCIAL_POPUP_HORIZONTAL_INSET * 2),
        height = SOCIAL_POPUP_ROW_HEIGHT,
        autoFocus = false,
    })
    editBox:SetPoint("LEFT", container, "LEFT", 0, 0)
    editBox:SetFrameLevel((frame:GetFrameLevel() or 1) + 5)
    editBox:SetTextInsets(8, 8, 0, 0)
    if editBox.SetMaxLetters then editBox:SetMaxLetters(0) end
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    editBox:HookScript("OnEditFocusGained", function(self)
        SelectSocialPopupRow(self)
    end)
    editBox:HookScript("OnMouseUp", function(self)
        SelectSocialPopupRow(self)
    end)

    row = {
        container = container,
        editBox = editBox,
    }
    frame.rows[index] = row
    return row
end

local function EnsureSocialPopup()
    if S.SocialFrame then return S.SocialFrame end

    local frame = GUI2:CreatePanel(UIParent, {
        name = "YUI_SocialFrame",
        width = SOCIAL_POPUP_WIDTH,
        height = 160,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(9999)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()

    local close = GUI2:CreateCloseButton(frame, function() frame:Hide() end)
    close:SetPoint("TOPRIGHT", -5, -5)

    local title = GUI2:CreateText(frame, "", GUI2.Fonts.size_header)
    title:SetPoint("TOP", 0, -15)
    GUI2:SetTextColorKey(title, "color.text.heading")

    local tip = GUI2:CreateText(frame, LC["settings.social.copy_row_hint"], GUI2.Fonts.size_normal)
    tip:SetPoint("BOTTOM", 0, 15)
    GUI2:SetTextColorKey(tip, "color.text.secondary")

    frame.title = title
    frame.tip = tip
    frame.rows = {}
    frame:SetScript("OnHide", function(self)
        for _, row in ipairs(self.rows) do
            row.editBox:HighlightText(0, 0)
            row.editBox:ClearFocus()
        end
        self.selectedEditBox = nil
    end)

    S:RegisterScaleWindow(frame)
    S.SocialFrame = frame
    return frame
end

local function ShowSocialPopup(title, rows, defaultRowIndex)
    if type(rows) == "function" then rows = rows() end
    if type(rows) ~= "table" or #rows == 0 then return end

    if S.CopyFrame then S.CopyFrame:Hide() end
    local frame = EnsureSocialPopup()
    frame.selectedEditBox = nil
    frame.title:SetText(title or "")
    frame.tip:SetText(LC["settings.social.copy_row_hint"])
    frame:SetHeight(
        SOCIAL_POPUP_ROW_TOP
            + (#rows * SOCIAL_POPUP_ROW_HEIGHT)
            + ((#rows - 1) * SOCIAL_POPUP_ROW_GAP)
            + SOCIAL_POPUP_FOOTER_HEIGHT
    )

    for index, rowData in ipairs(rows) do
        local row = AcquireSocialPopupRow(frame, index)
        row.container:Show()
        row.editBox:SetText(tostring(rowData.text or ""))
        row.editBox:HighlightText(0, 0)
        row.editBox:ClearFocus()
        row.editBox:ClearAllPoints()
        row.editBox:SetPoint("LEFT", row.container, "LEFT", 0, 0)

        if rowData.recommended then
            if not row.badge then
                row.badge = GUI2.Data:CreateBadge(row.container, {
                    text = LC["settings.social.recommended"],
                    tone = "green",
                    variant = "solid",
                    height = 20,
                    minWidth = 0,
                    paddingX = 7,
                    radiusKey = "layout.radius.badge",
                })
            end
            row.badge:SetText(LC["settings.social.recommended"])
            row.badge:ClearAllPoints()
            row.badge:SetPoint("LEFT", row.editBox, "RIGHT", SOCIAL_POPUP_BADGE_GAP, 0)
            row.badge:Show()
            local badgeWidth = row.badge:GetWidth() or SOCIAL_POPUP_BADGE_RESERVE
            row.editBox:SetWidth(
                SOCIAL_POPUP_WIDTH
                    - (SOCIAL_POPUP_HORIZONTAL_INSET * 2)
                    - badgeWidth
                    - SOCIAL_POPUP_BADGE_GAP
            )
        else
            if row.badge then row.badge:Hide() end
            row.editBox:SetWidth(SOCIAL_POPUP_WIDTH - (SOCIAL_POPUP_HORIZONTAL_INSET * 2))
        end
    end

    for index = #rows + 1, #frame.rows do
        frame.rows[index].container:Hide()
    end

    frame:Show()
    PlaySettingsPopup(frame, "settings-social-popup")
    defaultRowIndex = math.max(1, math.min(#rows, tonumber(defaultRowIndex) or 1))
    SelectSocialPopupRow(frame.rows[defaultRowIndex].editBox)
end

function S:ShowReload()
    if not Elements.frame then return end
    
    if not Elements.reloadBtn then
        local btn = GUI2:CreateButton(Elements.frame, LC["settings.reload_required"], 110, 26)
        btn:SetPoint("BOTTOMRIGHT", Elements.frame, "TOPRIGHT", -4, 6)
        btn:SetFrameLevel((Elements.frame:GetFrameLevel() or 100) + 20)
        if GUI2.ApplyButtonStyle then
            GUI2:ApplyButtonStyle(btn, "dangerFilled")
        end
        if GUI2.Form and GUI2.Form.SetButtonRelief then
            GUI2.Form:SetButtonRelief(btn, "hairline")
        end
        
        btn:SetScript("OnClick", function()
            FrameAPI.ReloadUI()
        end)
        
        -- 闪烁动画
        local ag = btn:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        a:SetDuration(0.8)
        a:SetFromAlpha(1)
        a:SetToAlpha(0.6)
        ag:Play()
        
        Elements.reloadBtn = btn
        
        -- 关闭窗口时提醒
        Elements.frame:HookScript("OnHide", function()
            if Elements.frame and Elements.frame.yuiSettingsCombatClosing then
                return
            end
            if Elements.reloadBtn and Elements.reloadBtn:IsShown() then
                -- Use custom popup instead of StaticPopup
                S:ShowConfirmPopup(LC["settings.reload_confirm"], function()
                     FrameAPI.ReloadUI()
                end)
            end
        end)
    end
    
    Elements.reloadBtn:ClearAllPoints()
    Elements.reloadBtn:SetPoint("BOTTOMRIGHT", Elements.frame, "TOPRIGHT", -4, 6)
    Elements.reloadBtn:Show()
end

local CONFIRM_FILLED_STYLE_BY_TONE = {
    accent = "successFilled",
    default = "grayFilled",
    success = "successFilled",
    warning = "warningFilled",
    danger = "dangerFilled",
    error = "dangerFilled",
}

local function ResolveConfirmFilledStyle(tone, explicitStyle, fallbackStyle)
    if explicitStyle then return explicitStyle end
    return CONFIRM_FILLED_STYLE_BY_TONE[tone or "success"] or fallbackStyle
end

local function StopConfirmPopupMotion(frame)
    if YUI.Animation and YUI.Animation.StopTarget then
        YUI.Animation:StopTarget(frame, "settings-confirm-popup", false)
    end
end

local function ClearConfirmPopupCallbacks(frame)
    if not frame then return end
    frame.onAccept = nil
    frame.onCancel = nil
    frame.onDismiss = nil
    frame.confirmOwner = nil
    frame.confirmOwnerFrame = nil
    frame.confirmDismissWithOwner = nil
    for _, button in ipairs(frame.confirmButtons or {}) do
        button.confirmCallback = nil
    end
end

local function HideConfirmPopup(frame)
    if not frame then return end
    StopConfirmPopupMotion(frame)
    if frame:IsShown() then
        frame:Hide()
    else
        ClearConfirmPopupCallbacks(frame)
    end
end

local function GetConfirmOptionValue(frame)
    return frame.confirmOption
        and frame.confirmOption:IsShown()
        and frame.confirmOption:GetChecked() == true
end

local function RunConfirmPopupCallback(frame, callback)
    local checked = GetConfirmOptionValue(frame)
    local hideAfterCallback = YUI.IsForever == true
    local generation = frame.confirmGeneration
    -- Forever reload requires the clicked button to remain visible during the callback.
    if not hideAfterCallback then
        HideConfirmPopup(frame)
    end
    if type(callback) == "function" then
        callback(checked)
    end
    if hideAfterCallback and frame.confirmGeneration == generation then
        HideConfirmPopup(frame)
    end
end

local function DismissConfirmPopup(frame)
    local callback = frame and frame.onDismiss
    HideConfirmPopup(frame)
    if type(callback) == "function" then
        callback()
    end
end

local CONFIRM_BASE_SCRIM_LEVEL = 700
local CONFIRM_OWNER_SCRIM_OFFSET = 30
local CONFIRM_PANEL_OFFSET = 2
local CONFIRM_CONTROL_OFFSET = 2
local CONFIRM_DEFAULT_APPEARANCE = {
    surfaceKey = "color.surface.popup",
    borderKey = "color.popup.border",
    titleColorKey = "color.text.heading",
    messageColorKey = "color.text.primary",
    noteColorKey = "color.text.secondary",
}
local confirmOwnerFrameHooks = setmetatable({}, { __mode = "k" })

local function ResolveConfirmAppearance(options)
    local requested = options and options.appearance
    if type(requested) ~= "table" then
        requested = CONFIRM_DEFAULT_APPEARANCE
    end
    return {
        surfaceKey = requested.surfaceKey or CONFIRM_DEFAULT_APPEARANCE.surfaceKey,
        borderKey = requested.borderKey or CONFIRM_DEFAULT_APPEARANCE.borderKey,
        titleColorKey = requested.titleColorKey or CONFIRM_DEFAULT_APPEARANCE.titleColorKey,
        messageColorKey = requested.messageColorKey or CONFIRM_DEFAULT_APPEARANCE.messageColorKey,
        noteColorKey = requested.noteColorKey or CONFIRM_DEFAULT_APPEARANCE.noteColorKey,
    }
end

local function BindConfirmOwnerFrame(ownerFrame)
    if not (ownerFrame and ownerFrame.HookScript) or confirmOwnerFrameHooks[ownerFrame] then
        return
    end
    confirmOwnerFrameHooks[ownerFrame] = true
    ownerFrame:HookScript("OnHide", function(hiddenOwner)
        local confirm = S.ConfirmFrame
        if confirm
            and confirm.confirmDismissWithOwner == true
            and confirm.confirmOwnerFrame == hiddenOwner then
            HideConfirmPopup(confirm)
        end
    end)
end

function S:HideConfirmPopup(owner)
    local frame = S.ConfirmFrame
    if not frame or (owner ~= nil and frame.confirmOwner ~= owner) then
        return false
    end
    HideConfirmPopup(frame)
    return true
end

function S:ShowConfirmPopup(text, onAccept, options)
    options = type(options) == "table" and options or nil

    if not S.ConfirmFrame then
        local f = GUI2:CreatePanel(UIParent, { name = "YUI_ConfirmFrame", width = 400, height = 150, surface = "color.surface.popup", border = "color.popup.border", shadow = true })
        f:SetSize(400, 150)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetFrameLevel(CONFIRM_BASE_SCRIM_LEVEL + CONFIRM_PANEL_OFFSET)
        f:EnableMouse(true)
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0.15, 0.15, 0.2, 0.98)
        f:SetBackdropBorderColor(GUI2:GetColor("color.popup.border"))
        
        GUI2:CreateShadow(f, "shadow.popup.size")
        local shadow = f.gui2Shadow
        shadow:SetPoint("TOPLEFT", -3, 3)
        shadow:SetPoint("BOTTOMRIGHT", 3, -3)
        shadow:SetFrameLevel(f:GetFrameLevel() > 0 and f:GetFrameLevel() - 1 or 0)
        shadow:SetBackdrop({
            edgeFile = Assets:Core("images\\GlowTex.tga"),
            edgeSize = 3,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        shadow:SetBackdropBorderColor(0, 0, 0, 0.5)
        f.shadow = shadow
        f.RefreshTheme = function(frame)
            local appearance = frame.confirmAppearance or CONFIRM_DEFAULT_APPEARANCE
            frame.gui2Surface = appearance.surfaceKey
            GUI2:RefreshPrimitive(frame)
            GUI2:SetBorderColor(frame, appearance.borderKey)
            if frame.title then GUI2:SetTextColorKey(frame.title, appearance.titleColorKey) end
            if frame.msg then GUI2:SetTextColorKey(frame.msg, appearance.messageColorKey) end
            if frame.note then GUI2:SetTextColorKey(frame.note, appearance.noteColorKey) end
        end
        GUI2:RegisterThemeObject(f)
        f:RefreshTheme()
        
        local title = GUI2:CreateText(f, LC["settings.confirm_title"], GUI2.Fonts.size_header)
        title:SetPoint("TOP", 0, -20)
        GUI2:SetTextColorKey(title, "color.text.heading")
        f.title = title
        
        local msg = GUI2:CreateText(f, "", "font.size.lg")
        msg:SetPoint("TOP", 0, -50)
        msg:SetWidth(360)
        msg:SetWordWrap(true)
        msg:SetJustifyH("CENTER")
        f.msg = msg

        local note = GUI2:CreateText(f, "", "font.size.sm", "color.text.secondary")
        note:SetPoint("TOP", msg, "BOTTOM", 0, -10)
        note:SetWidth(340)
        note:SetWordWrap(true)
        note:SetJustifyH("CENTER")
        note:Hide()
        f.note = note
        
        local confirmOption = GUI2.Form:CreateCheckbox(f, {
            text = "",
            width = 180,
            height = 28,
        })
        confirmOption:SetPoint("BOTTOM", 0, 52)
        confirmOption:Hide()
        f.confirmOption = confirmOption

        f.confirmButtons = {}
        for index = 1, 3 do
            local button = GUI2.Form:CreateButton(f, {
                text = "",
                width = 100,
                height = 24,
            })
            button.confirmIndex = index
            button:SetScript("OnClick", function(self)
                local callback = self.confirmCallback
                RunConfirmPopupCallback(f, callback)
            end)
            button:Hide()
            f.confirmButtons[index] = button
        end
        f.btnAccept = f.confirmButtons[1]
        f.btnCancel = f.confirmButtons[2]
        f.btnExtra = f.confirmButtons[3]

        f:HookScript("OnHide", function(frame)
            StopConfirmPopupMotion(frame)
            ClearConfirmPopupCallbacks(frame)
        end)
        GUI2:EnableEscapeClose(f, DismissConfirmPopup)
        
        S.ConfirmFrame = f
    end

    if S.ConfirmFrame:IsShown() then
        HideConfirmPopup(S.ConfirmFrame)
    end
    S.ConfirmFrame.confirmGeneration = (S.ConfirmFrame.confirmGeneration or 0) + 1

    local offsetX = tonumber(options and options.offsetX) or 0
    local offsetY = tonumber(options and options.offsetY) or 0
    local scrimAlpha = tonumber(options and options.scrimAlpha)
    if scrimAlpha then scrimAlpha = math.max(0, math.min(scrimAlpha, 1)) end
    S.ConfirmFrame:ClearAllPoints()
    S.ConfirmFrame:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)

    local ownerFrame = options and options.ownerFrame
    S:SyncOwnedWindowScale(S.ConfirmFrame, ownerFrame or S:GetVisibleScaleOwner())
    local ownerLevel = ownerFrame and ownerFrame.GetFrameLevel
        and tonumber(ownerFrame:GetFrameLevel()) or nil
    local scrimLevel = math.max(
        CONFIRM_BASE_SCRIM_LEVEL,
        (ownerLevel or (CONFIRM_BASE_SCRIM_LEVEL - CONFIRM_OWNER_SCRIM_OFFSET))
            + CONFIRM_OWNER_SCRIM_OFFSET
    )
    local confirmLevel = scrimLevel + CONFIRM_PANEL_OFFSET
    local controlLevel = confirmLevel + CONFIRM_CONTROL_OFFSET
    S.ConfirmFrame:SetFrameLevel(confirmLevel)
    if S.ConfirmFrame.shadow and S.ConfirmFrame.shadow.SetFrameLevel then
        S.ConfirmFrame.shadow:SetFrameLevel(math.max(confirmLevel - 1, 0))
    end

    S.ConfirmFrame.confirmAppearance = ResolveConfirmAppearance(options)
    S.ConfirmFrame:RefreshTheme()

    local messageTopOffset = tonumber(options and options.messageTopOffset) or 50
    S.ConfirmFrame.msg:ClearAllPoints()
    S.ConfirmFrame.msg:SetPoint("TOP", S.ConfirmFrame, "TOP", 0, -messageTopOffset)
    S.ConfirmFrame.msg:SetText(text)
    if S.ConfirmFrame.title then
        S.ConfirmFrame.title:SetText((options and options.titleText) or LC["settings.confirm_title"])
    end
    local noteText = options and options.noteText or ""
    local hasNote = noteText ~= ""
    S.ConfirmFrame.note:SetText(noteText)
    if hasNote then
        S.ConfirmFrame.note:Show()
    else
        S.ConfirmFrame.note:Hide()
    end
    S.ConfirmFrame.onAccept = onAccept
    S.ConfirmFrame.onCancel = options and options.onCancel or nil
    local customButtons = options and type(options.buttons) == "table" and #options.buttons > 0
    if customButtons then
        S.ConfirmFrame.onDismiss = options and options.onDismiss
    else
        S.ConfirmFrame.onDismiss = options and (options.onCancel or options.onDismiss)
    end
    S.ConfirmFrame.confirmOwner = options and options.owner or nil
    S.ConfirmFrame.confirmOwnerFrame = ownerFrame
    S.ConfirmFrame.confirmDismissWithOwner = options and options.dismissWithOwner == true or false
    if S.ConfirmFrame.confirmDismissWithOwner then
        BindConfirmOwnerFrame(ownerFrame)
    end
    local optionText = options and options.checkboxText
    local hasOption = type(optionText) == "string" and optionText ~= ""
    S.ConfirmFrame:SetHeight((options and options.height) or (hasOption and 190 or (hasNote and 170 or 150)))
    if S.ConfirmFrame.confirmOption then
        if S.ConfirmFrame.confirmOption.SetFrameLevel then
            S.ConfirmFrame.confirmOption:SetFrameLevel(controlLevel)
        end
        S.ConfirmFrame.confirmOption:SetChecked(
            hasOption and options.checkboxChecked == true,
            true
        )
        S.ConfirmFrame.confirmOption.text:SetText(optionText or "")
        if hasOption then
            local labelWidth = 0
            if S.ConfirmFrame.confirmOption.text.GetStringWidth then
                labelWidth = S.ConfirmFrame.confirmOption.text:GetStringWidth() or 0
            end
            local optionWidth = math.min(
                344,
                math.max(120, math.ceil(labelWidth + 26))
            )
            S.ConfirmFrame.confirmOption:SetWidth(optionWidth)
            S.ConfirmFrame.confirmOption:ClearAllPoints()
            S.ConfirmFrame.confirmOption:SetPoint(
                "BOTTOM",
                S.ConfirmFrame,
                "BOTTOM",
                0,
                52
            )
            S.ConfirmFrame.confirmOption:Show()
        else
            S.ConfirmFrame.confirmOption:Hide()
        end
    end
    local buttonSpecs
    local buttonGap
    if customButtons then
        buttonSpecs = {}
        for index = 1, math.min(#options.buttons, 3) do
            local spec = options.buttons[index]
            if type(spec) == "table" then
                buttonSpecs[#buttonSpecs + 1] = spec
            end
        end
        buttonGap = options.buttonGap or 12
    else
        buttonSpecs = {
            {
                text = options and options.acceptText or LC["common.confirm"],
                tone = options and options.acceptTone or "success",
                style = options and options.acceptStyle,
                relief = options and options.acceptRelief,
                width = options and options.acceptWidth,
                callback = onAccept,
            },
            {
                text = options and options.cancelText or LC["common.cancel"],
                tone = options and options.cancelTone or "default",
                style = options and options.cancelStyle or "grayFilled",
                relief = options and options.cancelRelief,
                width = options and options.cancelWidth,
                callback = options and (options.onCancel or options.onDismiss),
            },
        }
        buttonGap = options and options.buttonGap or 40
    end

    local resolvedWidths = {}
    local totalWidth = 0
    for index, spec in ipairs(buttonSpecs) do
        local width = spec.width or (customButtons and 108 or 100)
        resolvedWidths[index] = width
        totalWidth = totalWidth + width
        if index > 1 then totalWidth = totalWidth + buttonGap end
    end

    local nextX = -(totalWidth / 2)
    for index, button in ipairs(S.ConfirmFrame.confirmButtons) do
        local spec = buttonSpecs[index]
        if spec then
            local tone = spec.tone or (index == 1 and "success" or "default")
            local width = resolvedWidths[index]
            button.gui2Tone = tone
            button.confirmCallback = spec.callback
            if button.SetFrameLevel then button:SetFrameLevel(controlLevel) end
            button:SetSize(width, spec.height or 24)
            button:ClearAllPoints()
            button:SetPoint("BOTTOMLEFT", S.ConfirmFrame, "BOTTOM", nextX, spec.bottomOffset or 20)
            button:SetText(spec.text or "")
            if GUI2.ApplyButtonStyle then
                GUI2:ApplyButtonStyle(
                    button,
                    ResolveConfirmFilledStyle(
                        tone,
                        spec.style,
                        index == 1 and "successFilled" or "grayFilled"
                    )
                )
            elseif button.RefreshTheme then
                button:RefreshTheme()
            end
            if GUI2.Form and GUI2.Form.SetButtonRelief then
                GUI2.Form:SetButtonRelief(button, spec.relief or "hairline")
            end
            button:Show()
            nextX = nextX + width + buttonGap
        else
            button.confirmCallback = nil
            button:Hide()
        end
    end
    if GUI2.ShowModalScrim then
        GUI2:ShowModalScrim(S.ConfirmFrame, {
            duration = 0.20,
            key = "settings-confirm-scrim",
            frameLevel = scrimLevel,
            alpha = scrimAlpha,
        })
    end
    S.ConfirmFrame:Show()
    PlaySettingsPopup(S.ConfirmFrame, "settings-confirm-popup")
end

local function GetProductLogo(product, preferSmall)
    local logo = product and preferSmall and product.smallLogo or nil
    if not logo or logo == "" then
        logo = product and product.logo or nil
    end
    if logo and logo ~= "" then
        if logo:find("^Interface\\") or logo:find("^Interface/") then
            return logo
        end
        if Assets and Assets.Product and product.id then
            return Assets:Product(product.id, logo)
        end
    end
    return Assets:Core("images\\YUI-LOGO-300.png")
end

local function GetLocaleText(key, fallback)
    local value = LC and LC[key]
    if value and value ~= "" then
        return value
    end
    return fallback or key
end

local function ShowProductHeaderMinimapTooltip(button, product)
    if not (button and GameTooltip) then
        return
    end

    local minimap = YUI.MinimapIcon
    local shown = minimap and minimap.IsShown and minimap:IsShown(product.id)

    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(GetLocaleText("settings.minimap_icon.tooltip.title", "Minimap button"))
    GameTooltip:AddLine(
        shown and GetLocaleText("settings.minimap_icon.tooltip.state_shown", "Current state: shown")
            or GetLocaleText("settings.minimap_icon.tooltip.state_hidden", "Current state: hidden"),
        0.85, 0.85, 0.85
    )
    GameTooltip:AddLine(GetLocaleText("settings.minimap_icon.tooltip.left_click", "Left-click to show or hide the minimap button."), 1, 1, 1)
    GameTooltip:AddLine(GetLocaleText("settings.minimap_icon.tooltip.right_click", "Right-click to reset its position."), 0.75, 0.75, 0.75)
    GameTooltip:Show()
end

function S:CreateProductHeaderMinimapButton(parent, productId, opts)
    opts = opts or {}
    if not (parent and GUI2 and GUI2.Form and GUI2.Form.CreateIconButton) then
        return nil
    end

    if YUI.CoreMode == "suite" or not YUI.MinimapIcon then
        return nil
    end

    local product = GetProduct(productId or self.ActiveProductId)
    if not (product and product.settings and product.settings.enabled == true and product.settings.minimapIcon == true) then
        return nil
    end
    if product.settings.mode == "suite" then
        return nil
    end
    if product.id and YUI.BlockedProducts and YUI.BlockedProducts[product.id] then
        return nil
    end

    local minimap = YUI.MinimapIcon
    if not (minimap.IsShown and minimap.SetShown and minimap.ResetPosition) then
        return nil
    end
    if minimap.RegisterProduct then
        minimap:RegisterProduct(product)
    end

    local button = GUI2.Form:CreateIconButton(parent, {
        size = opts.size or 24,
        icon = opts.icon or GetProductLogo(product, true),
        crop = product.logoCrop ~= false,
        tone = opts.tone or "default",
    })
    if not button then
        return nil
    end

    if button.RegisterForClicks then
        button:RegisterForClicks("AnyUp")
    end

    local function RefreshState()
        local shown = minimap:IsShown(product.id)
        if button.SetSelected then
            button:SetSelected(shown)
        elseif button.SetState then
            button:SetState(shown and "selected" or "normal")
        end
        if button.icon and button.icon.SetAlpha then
            button.icon:SetAlpha(shown and 1 or 0.45)
        end
    end

    button.RefreshMinimapState = RefreshState
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            minimap:ResetPosition(product.id)
        else
            minimap:SetShown(product.id, not minimap:IsShown(product.id))
        end

        RefreshState()
        if GameTooltip and GameTooltip:IsOwned(self) then
            ShowProductHeaderMinimapTooltip(self, product)
        end
    end)
    button:SetScript("OnEnter", function(self)
        if not self.gui2Selected and self.SetState then
            self:SetState("hover")
        end
        ShowProductHeaderMinimapTooltip(self, product)
    end)
    button:SetScript("OnLeave", function(self)
        RefreshState()
        if GameTooltip then
            YUI.HideGameTooltip()
        end
    end)

    RefreshState()
    return button
end

local function BuildProductDropdownOptions()
    local products = S:GetSettingsProducts()
    local options = {}
    for _, product in ipairs(products) do
        options[#options + 1] = {
            text = GetProductDisplayName(product),
            value = product.id,
        }
    end
    return options
end

local function UpdateChangelogLinkLabel()
    if Elements.changelogLink and Elements.changelogLinkText then
        Elements.changelogLinkText:SetText(LC["settings.modules.changelog"])
        Elements.changelogLink:SetWidth(math.ceil(Elements.changelogLinkText:GetStringWidth() or 54) + 4)
    end

    if Elements.contactAuthorText then
        Elements.contactAuthorText:SetText(LC["settings.social.contact_author"])
    end
end

local function RefreshChangelogVisibility(product)
    local visible = ProductHasChangelog(product)
    local changelogLink = Elements.changelogLink
    local contactSeparator = Elements.contactSeparator
    local versionText = Elements.versionText

    if changelogLink then
        if visible then
            changelogLink:Show()
        else
            changelogLink:Hide()
        end
    end

    if contactSeparator then
        contactSeparator:ClearAllPoints()
        if visible and changelogLink then
            contactSeparator:SetPoint("LEFT", changelogLink, "RIGHT", 12, 0)
            contactSeparator:Show()
        elseif versionText then
            contactSeparator:SetPoint("LEFT", versionText, "RIGHT", 12, 0)
            contactSeparator:Show()
        else
            contactSeparator:Hide()
        end
    end
end

RefreshProductIdentity = function()
    if not Elements.logo then
        return
    end

    local product = GetProduct(S.ActiveProductId) or GetProduct(S:GetDefaultProductId())
    local logoSize = product and product.id ~= "suite" and 32 or 60
    local logoInset = (60 - logoSize) / 2
    Elements.logo:SetSize(logoSize, logoSize)
    Elements.logo:SetPoint("TOP", 0, -5 - logoInset)
    Elements.logo:SetTexture(GetProductLogo(product))
    local shouldCropLogo = not (product and product.logoCrop == false)
    if Elements.logoMask and Elements.logoMaskApplied ~= shouldCropLogo then
        if shouldCropLogo then
            Elements.logo:AddMaskTexture(Elements.logoMask)
        else
            Elements.logo:RemoveMaskTexture(Elements.logoMask)
        end
        Elements.logoMaskApplied = shouldCropLogo
    end
    RefreshChangelogVisibility(product)

    local products = S:GetSettingsProducts()
    if Elements.productDropdown then
        Elements.productDropdown:SetPoint("TOP", Elements.logo, "BOTTOM", 0, -4 - logoInset)
        if #products > 1 and product then
            Elements.productDropdown:SetValue(product.id, true)
            Elements.productDropdown:Show()
            Elements.navStartOffset = NAV_START_OFFSET_WITH_PRODUCT
        else
            Elements.productDropdown:Hide()
            Elements.navStartOffset = NAV_START_OFFSET
        end
    end

    if Elements.versionText and product then
        local version = product.version or SystemAPI.GetAddOnMetadata(product.addonName or YUI.AddonName or "YUI", "Version") or "Dev"
        Elements.versionText:SetText(string.format(LC["settings.version"], version))
    end
    UpdateChangelogLinkLabel()
end

local function OpenChangelogModule()
    local product = GetProduct(S.ActiveProductId)
    if not ProductHasChangelog(product) then
        return
    end
    local module = S.modulesById and S.modulesById["core.changelog"]
    if module then
        S:SelectModule(module)
    end
end

local function ApplySolidHeaderButton(button, surfaceKey, borderKey, hoverSurfaceKey, pressedSurfaceKey)
    if not button then return end

    local function Paint(frame, hovered, pressed)
        local resolvedSurface = pressed and (pressedSurfaceKey or surfaceKey)
            or (hovered and (hoverSurfaceKey or surfaceKey) or surfaceKey)
        if frame.SetBackdropColor then
            frame:SetBackdropColor(GUI2:GetColor(resolvedSurface))
        end
        GUI2:SetBorderColor(frame, borderKey)
        if frame.SetTextColor then
            frame:SetTextColor(GUI2:GetColor("color.badge.text"))
        end
    end

    if button.yuiSolidHeaderReady then
        Paint(button, button:IsMouseOver() and not button.gui2Disabled, false)
        return
    end

    button.yuiSolidHeaderReady = true
    GUI2.Form:SetButtonRelief(button, "hairline")
    local baseRefreshTheme = button.RefreshTheme
    button.RefreshTheme = function(frame)
        if baseRefreshTheme then baseRefreshTheme(frame) end
        Paint(frame, frame:IsMouseOver() and not frame.gui2Disabled, false)
    end
    button:HookScript("OnEnter", function(frame)
        if not frame.gui2Disabled then Paint(frame, true, false) end
    end)
    button:HookScript("OnLeave", function(frame)
        Paint(frame, false, false)
    end)
    button:HookScript("OnMouseDown", function(frame)
        if not frame.gui2Disabled then Paint(frame, true, true) end
    end)
    button:HookScript("OnMouseUp", function(frame)
        Paint(frame, frame:IsMouseOver() and not frame.gui2Disabled, false)
    end)
    Paint(button, false, false)
end

local function IsYHUDDesignerAvailable()
    local yhud = YUI.YHUD
    return yhud ~= nil
        and type(yhud.IsEnabled) == "function"
        and yhud:IsEnabled() == true
        and yhud.DesignerUI ~= nil
        and type(yhud.DesignerUI.Open) == "function"
end

RefreshEditModeButton = function()
    local button = Elements.editModeBtn
    if not button then return end
    local editing = YUI.Layout and YUI.Layout.IsEditing and YUI.Layout:IsEditing() == true
    if button.SetSelected then
        button:SetSelected(editing)
    elseif button.SetState then
        button:SetState(editing and "selected" or "normal")
    end
    ApplySolidHeaderButton(
        button,
        "color.interaction.primary",
        "color.border.accent",
        "color.interaction.primaryHover",
        "color.interaction.primaryPressed"
    )
end

local function RefreshYHUDDesignerButton()
    local button = Elements.monitorDesignBtn
    if not button then return end
    if IsYHUDDesignerAvailable() then
        button:Show()
        ApplySolidHeaderButton(
            button,
            "color.badge.orange",
            "color.badge.orange",
            "color.badge.orange.hover",
            "color.badge.orange.pressed"
        )
    else
        button:Hide()
    end
end

RefreshHeaderActions = function()
    RefreshEditModeButton()
    RefreshYHUDDesignerButton()
end

function S:RefreshEditModeButton()
    RefreshEditModeButton()
end

function S:CreateMainFrame()
    -- 主容器
    local f = GUI2:CreatePanel(UIParent, { name = "YUI_SettingsFrame", width = FRAME_WIDTH, height = FRAME_HEIGHT, surface = "color.surface.window", border = "color.border.strong", shadow = true })
    f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    S:RegisterScaleWindow(f)
    f:Hide()
    f:HookScript("OnHide", function()
        if S.Search then S.Search:Close() end
        if S.ClearRightPreview then
            S:ClearRightPreview()
        end
        if YUI.Event and type(YUI.Event.Emit) == "function" then
            YUI.Event:Emit("YUI_SETTINGS_VISIBILITY_CHANGED", false)
        end
    end)
    f:HookScript("OnShow", function()
        S:SetWindowScale(S:GetWindowScale())
        if S.Search then S.Search:RunQuery() end
        if YUI.Event and type(YUI.Event.Emit) == "function" then
            YUI.Event:Emit("YUI_SETTINGS_VISIBILITY_CHANGED", true)
        end
    end)
    GUI2:EnableEscapeClose(f, function(frame)
        if S.Search and S.Search:HandleEscape() then
            -- EscapeClose disables keyboard handling before invoking its callback.
            frame:EnableKeyboard(true)
            return
        end
        PlaySettingsClose(frame)
    end)
    
    -- 背景
    Elements.frame = f
    local backgroundArt = GUI2:CreateTexture(f, {
        texture = ResolveSettingsBackgroundTexture(),
        layer = "BORDER",
        subLevel = -8,
    })
    backgroundArt:SetAllPoints(f)
    backgroundArt:SetTexCoord(
        SETTINGS_BACKGROUND_CROP_LEFT,
        SETTINGS_BACKGROUND_CROP_RIGHT,
        0,
        1
    )
    backgroundArt:SetAlpha(SETTINGS_BACKGROUND_ALPHA)
    Elements.backgroundArt = backgroundArt
    S:RefreshSettingsBackground()
    
    -- 左侧导航面板
    local nav = GUI2:CreateFrame(f)
    nav:SetPoint("TOPLEFT", GAP, -GAP)
    nav:SetPoint("BOTTOMLEFT", GAP, GAP)
    nav:SetWidth(NAV_WIDTH)
    Elements.nav = nav
    -- Fixed navigation: compact rows, never a left-hand scrollbar.
    local navList = GUI2:CreateFrame(nav)
    navList:SetPoint("TOPLEFT", 0, NAV_START_OFFSET)
    navList:SetPoint("BOTTOMRIGHT", -10, NAV_FOOTER_HEIGHT + 8)
    Elements.navList = navList
    nav:HookScript("OnSizeChanged", function() S:LayoutNav() end)

    local scaleControl = GUI2.Form:CreateSlider(nav, {
        width = NAV_WIDTH - 20, inputWidth = 42, inline = true,
        min = 70, max = 200, step = 1,
        get = function() return S:GetWindowScale() * 100 end,
        instantUpdate = false,
        set = function(value) S:SetWindowScale(value / 100) end,
    })
    scaleControl:SetPoint("BOTTOMLEFT", 10, 4)
    scaleControl:SetAlpha(0.55)
    scaleControl.inputBox:Hide()
    local percentage = GUI2:CreateText(scaleControl, "", "font.size.sm", "color.text.secondary")
    percentage:SetPoint("LEFT", scaleControl.slider, "RIGHT", 10, 0)
    local function UpdatePercentage()
        percentage:SetText(string.format("%d%%", scaleControl:GetValue()))
    end
    scaleControl.slider:HookScript("OnValueChanged", UpdatePercentage)
    function scaleControl:RefreshAppliedScale()
        local percent = S:GetWindowScale() * 100
        self:SetValue(percent, true)
        percentage:SetText(string.format("%.0f%%", percent))
    end
    scaleControl:HookScript("OnShow", function()
        scaleControl:RefreshAppliedScale()
    end)
    UpdatePercentage()
    Elements.scaleControl = scaleControl
    
    -- 垂直分割线
    local sep = GUI2:CreateTexture(f, { layer = "OVERLAY" })
    sep:SetWidth(1)
    sep:SetPoint("TOPLEFT", nav, "TOPRIGHT", 0, -10)
    sep:SetPoint("BOTTOMLEFT", nav, "BOTTOMRIGHT", 0, 10)
    GUI2:SetTexturePaintKey(sep, "color.border.default")
    sep:SetAlpha(0.5)
    Elements.separator = sep

    -- Logo
    local logo = GUI2:CreateTexture(nav, { layer = "ARTWORK" })
    logo:SetSize(60, 60)
    logo:SetPoint("TOP", 0, -5)
    logo:SetTexture(Assets:Core("images\\YUI-LOGO-300.png"))
    
    local mask = nav:CreateMaskTexture()
    mask:SetTexture("Interface\\COMMON\\Indicator-Gray")
    mask:SetSize(54, 54)
    mask:SetPoint("CENTER", logo, "CENTER", 0, 0)
    logo:AddMaskTexture(mask)

    Elements.logo = logo
    Elements.logoMask = mask
    Elements.logoMaskApplied = true

    local productDropdown = GUI2.Form:CreateDropdown(nav, {
        width = NAV_WIDTH - 34,
        height = 24,
        options = BuildProductDropdownOptions,
        get = function()
            return S.ActiveProductId
        end,
        set = function(productId)
            local product = GetProduct(productId)
            if product then
                S:OpenProduct(product.id, product.settings and product.settings.entry)
            end
        end,
    })
    productDropdown:SetPoint("TOP", logo, "BOTTOM", 0, -4)
    Elements.productDropdown = productDropdown
    Elements.navStartOffset = NAV_START_OFFSET
    if S.Search then S.Search:Create() end

    -- Right Content Panel
    local content = GUI2:CreateFrame(f)
    content:SetPoint("TOPLEFT", nav, "TOPRIGHT", GAP, 0)
    content:SetPoint("BOTTOMRIGHT", -GAP, GAP)
    Elements.content = content
    
    -- Header Area
    local header = GUI2:CreateFrame(content)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_HEIGHT)
    Elements.header = header
    
    -- Version Text
-- 版本文本
    local verText = SystemAPI.GetAddOnMetadata("YUI", "Version") or "Dev"
    local version = GUI2:CreateText(header, string.format(LC["settings.version"], verText), GUI2.Fonts.size_normal)
    version:SetPoint("LEFT", 20, 0)
    GUI2:SetTextColorKey(version, "color.text.secondary")
    Elements.versionText = version

    local changelogLink = GUI2:CreateButtonFrame(header, { width = 58, height = 20 })
    changelogLink:SetPoint("LEFT", version, "RIGHT", 12, 0)
    local changelogText = GUI2:CreateText(changelogLink, LC["settings.modules.changelog"], GUI2.Fonts.size_normal)
    changelogText:SetPoint("CENTER")
    GUI2:SetTextColorKey(changelogText, "color.text.accent")
    changelogText:SetWordWrap(false)
    changelogLink:SetWidth(math.ceil(changelogText:GetStringWidth() or 54) + 4)

    local changelogUnderline = GUI2:CreateTexture(changelogLink, { layer = "ARTWORK" })
    changelogUnderline:SetHeight(1)
    changelogUnderline:SetPoint("TOPLEFT", changelogText, "BOTTOMLEFT", 0, -1)
    changelogUnderline:SetPoint("TOPRIGHT", changelogText, "BOTTOMRIGHT", 0, -1)
    GUI2:SetTexturePaintKey(changelogUnderline, "color.text.accent")
    changelogLink:SetScript("OnEnter", function()
        GUI2:SetTextColorKey(changelogText, "color.text.primary")
        GUI2:SetTexturePaintKey(changelogUnderline, "color.text.primary")
    end)
    changelogLink:SetScript("OnLeave", function()
        GUI2:SetTextColorKey(changelogText, "color.text.accent")
        GUI2:SetTexturePaintKey(changelogUnderline, "color.text.accent")
    end)
    changelogLink:SetScript("OnClick", OpenChangelogModule)
    Elements.changelogLink = changelogLink
    Elements.changelogLinkText = changelogText
    Elements.changelogLinkUnderline = changelogUnderline

    local contactSeparator = GUI2:CreateTexture(header, { layer = "OVERLAY" })
    contactSeparator:SetWidth(1)
    contactSeparator:SetHeight(28)
    contactSeparator:SetPoint("LEFT", changelogLink, "RIGHT", 12, 0)
    GUI2:SetTexturePaintKey(contactSeparator, "color.border.default")
    contactSeparator:SetAlpha(0.5)
    Elements.contactSeparator = contactSeparator

    local contactAuthorText = GUI2:CreateText(header, LC["settings.social.contact_author"], GUI2.Fonts.size_normal)
    contactAuthorText:SetPoint("LEFT", contactSeparator, "RIGHT", 12, 0)
    contactAuthorText:SetWordWrap(false)
    GUI2:SetTextColorKey(contactAuthorText, "color.text.secondary")
    Elements.contactAuthorText = contactAuthorText

    -- Social Info Buttons
    local function CreateSocialButton(parent, icon, popupTitle, rows, defaultRowIndex)
        local btn = GUI2:CreateButtonFrame(parent, { width = 24, height = 24 })
        btn:SetSize(24, 24)

        local iconTex = GUI2:CreateTexture(btn, { layer = "ARTWORK" })
        iconTex:SetSize(18, 18)
        iconTex:SetPoint("CENTER", 0, 0)
        iconTex:SetTexture(icon)

        local function Paint(hovered, pressed)
            iconTex:ClearAllPoints()
            iconTex:SetPoint("CENTER", pressed and 1 or 0, pressed and -1 or 0)
            iconTex:SetVertexColor(GUI2:GetColor(hovered and "color.text.secondary" or "color.text.muted"))
            iconTex:SetAlpha(hovered and 1 or 0.9)
        end

        btn.RefreshTheme = function()
            Paint(btn:IsMouseOver(), false)
        end
        btn:SetScript("OnEnter", function()
            Paint(true, false)
        end)
        btn:SetScript("OnLeave", function()
            Paint(false, false)
        end)
        btn:SetScript("OnMouseDown", function()
            Paint(true, true)
        end)
        btn:SetScript("OnMouseUp", function()
            Paint(btn:IsMouseOver(), false)
        end)
        btn:SetScript("OnClick", function()
            ShowSocialPopup(popupTitle, rows, defaultRowIndex)
        end)

        Paint(false, false)
        GUI2:RegisterThemeObject(btn)
        return btn
    end

    -- QQ 群
    local qqBtn = CreateSocialButton(
        header,
        Assets:Core("images\\icons\\qq_mono.png"),
        LC["settings.social.qq_title"],
        BuildQQSocialRows
    )
    qqBtn:SetPoint("LEFT", contactAuthorText, "RIGHT", 8, 0)

    local dyBtn = CreateSocialButton(
        header,
        Assets:Core("images\\icons\\dyin_mono.png"),
        LC["settings.social.douyin_title"],
        SOCIAL_DOUYIN_ROWS,
        2
    )
    dyBtn:SetPoint("LEFT", qqBtn, "RIGHT", 8, 0)

    -- Bilibili
    local biliBtn = CreateSocialButton(
        header,
        Assets:Core("images\\icons\\bilibili_mono.png"),
        LC["settings.social.bilibili_title"],
        SOCIAL_BILIBILI_ROWS,
        2
    )
    biliBtn:SetPoint("LEFT", dyBtn, "RIGHT", 8, 0)

    -- 关闭按钮
    local closeBtn = GUI2:CreateCloseButton(header, function() S:Close() end)
    closeBtn:SetPoint("RIGHT", -10, 0)
    closeBtn:SetFrameLevel(header:GetFrameLevel() + 10)

    local editModeBtn = GUI2.Form:CreateButton(header, {
        text = LC["settings.edit_mode.short"],
        tooltip = LC["settings.edit_mode"],
        width = 112,
        height = 26,
        tone = "accent",
        onClick = function()
            if not (YUI.Layout and YUI.Layout.IsEditing) then return end
            if YUI.Layout:IsEditing() then
                if Elements.frame and Elements.frame.yuiSettingsClosing then
                    RefreshEditModeButton()
                    return
                end
                YUI.Layout:CloseEditMode("settings_header")
            else
                YUI.Layout:OpenEditMode("settings_header")
            end
            RefreshEditModeButton()
        end,
    })
    editModeBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    editModeBtn:SetFrameLevel(header:GetFrameLevel() + 10)
    ApplySolidHeaderButton(
        editModeBtn,
        "color.interaction.primary",
        "color.border.accent",
        "color.interaction.primaryHover",
        "color.interaction.primaryPressed"
    )
    Elements.editModeBtn = editModeBtn

    local monitorDesignBtn = GUI2.Form:CreateButton(header, {
        text = LC["settings.monitor_design.short"],
        tooltip = LC["settings.monitor_design"],
        width = 112,
        height = 26,
        tone = "warning",
        onClick = function()
            if not IsYHUDDesignerAvailable() then
                RefreshYHUDDesignerButton()
                return
            end
            YUI.YHUD.DesignerUI:Open("settings")
        end,
    })
    monitorDesignBtn:SetPoint("RIGHT", editModeBtn, "LEFT", -8, 0)
    monitorDesignBtn:SetFrameLevel(header:GetFrameLevel() + 10)
    ApplySolidHeaderButton(
        monitorDesignBtn,
        "color.badge.orange",
        "color.badge.orange",
        "color.badge.orange.hover",
        "color.badge.orange.pressed"
    )
    Elements.monitorDesignBtn = monitorDesignBtn
    RefreshHeaderActions()
    
    -- 分割线
    local line = GUI2:CreateTexture(header, { layer = "ARTWORK" })
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 10, 0)
    line:SetPoint("BOTTOMRIGHT", -10, 0)
    GUI2:SetTexturePaintKey(line, "color.border.default")
    line:SetAlpha(0.5)
    Elements.headerLine = line
    
    -- 主内容区域
    local scrollFrame = GUI2:CreateScrollFrame(content, { child = false })
    GUI2:SkinScrollBar(scrollFrame)
    Elements.scrollFrame = scrollFrame
    
    local scrollChild = GUI2:CreateFrame(scrollFrame)
    scrollChild:SetSize(GetContentAreaWidth() - 40, 1000)
    scrollFrame:SetScrollChild(scrollChild)
    Elements.scrollChild = scrollChild
    UpdateRightPreviewLayout()
    
    RefreshProductIdentity()
    S:RefreshNav()
end

function S:ClearConfig(parent)
    if not parent then return end
    if self.Search and not self.Search.pending then self.Search:CancelLocation() end
    local children = {parent:GetChildren()}
    for _, child in ipairs(children) do
        child:Hide()
        child:SetParent(nil)
    end
    -- Also clear Regions (FontStrings, Textures)
    local regions = {parent:GetRegions()}
    for _, region in ipairs(regions) do
        if region:IsObjectType("FontString") or region:IsObjectType("Texture") then
            region:Hide()
            region:SetParent(nil)
        end
    end
end

local function GetSettingsFormMetric(name, fallback)
    return GUI2:GetMetric("layout.form." .. name, fallback)
end

local function ShouldRenderAlignedField(field)
    if not field then return false end
    if field.requires and not field.requires() then return false end
    if type(field.hidden) == "function" then
        return not field.hidden()
    end
    return field.hidden ~= true
end

local ALIGNED_FIELD_LAYOUT_PRESETS = {
    compactColor = { labelPosition = "left", controlWidth = 32, minControlWidth = 32, labelPadding = 8, field = false },
    inlineSelector = { labelPosition = "left", minLabelWidth = 80, labelPadding = 8, minControlWidth = 140 },
}

local function GetAlignedFieldLayoutValue(field, key)
    if field[key] ~= nil then return field[key] end
    local preset = ALIGNED_FIELD_LAYOUT_PRESETS[field.layoutPreset]
    return preset and preset[key]
end

local function CloneAlignedField(field, bodyWidth, valueWidth, valueGap, maxWidth)
    local copy = {}
    for k, v in pairs(field) do
        copy[k] = v
    end
    local preset = ALIGNED_FIELD_LAYOUT_PRESETS[field.layoutPreset]
    if preset then
        for k, v in pairs(preset) do
            if copy[k] == nil then copy[k] = v end
        end
    end

    copy.label = nil
    copy.inlineLabel = nil
    copy.formLabel = nil
    copy.labelPosition = nil
    copy.row = nil
    copy.col = nil
    copy.column = nil
    copy.span = nil
    copy.layoutPreset = nil

    if copy.type == "slider" then
        copy.inline = true
        copy.width = copy.bodyWidth or copy.controlWidth or bodyWidth
        copy.inputWidth = field.inputWidth or valueWidth
        copy.gap = field.valueGap or valueGap
    elseif copy.type == "color" then
        copy.width = copy.bodyWidth or copy.controlWidth or bodyWidth
        copy.field = copy.field ~= false
    elseif copy.type == "glow" then
        copy.width = copy.bodyWidth or copy.controlWidth or bodyWidth
        copy.inputWidth = field.inputWidth or valueWidth
    elseif copy.type == "checkbox" then
        copy.width = copy.bodyWidth or copy.controlWidth or bodyWidth
        copy.text = field.checkboxText or field.text or ""
    elseif copy.type == "sound" then
        copy.width = copy.bodyWidth or copy.controlWidth or bodyWidth
    elseif copy.type == "specDropdown" or copy.type == "specdropdown" then
        copy.width = copy.bodyWidth or copy.controlWidth or bodyWidth
    elseif copy.type == "specMultiSelect" or copy.type == "specmultiselect" then
        copy.width = copy.bodyWidth or copy.controlWidth or bodyWidth
    else
        copy.width = copy.bodyWidth or copy.controlWidth or bodyWidth
    end

    if maxWidth then copy.width = math.min(copy.width, maxWidth) end
    return copy
end

local function CreateAlignedFieldWidget(parent, field, bodyWidth, valueWidth, valueGap, maxWidth)
    local controlItem = CloneAlignedField(field, bodyWidth, valueWidth, valueGap, maxWidth)
    local fieldType = controlItem.type

    if fieldType == "dropdown" then
        return GUI2.Form:CreateDropdown(parent, controlItem)
    elseif fieldType == "font" and GUI2.Form.CreateLSMFontDropdown then
        return GUI2.Form:CreateLSMFontDropdown(parent, controlItem)
    elseif fieldType == "sound" then
        controlItem.options = controlItem.options or BuildLSMMediaDropdownOptions("sound", controlItem)
        controlItem.default = controlItem.default or "None"
        if GUI2.Form.CreateLSMSoundDropdown then
            return GUI2.Form:CreateLSMSoundDropdown(parent, controlItem)
        end
        return GUI2.Form:CreateDropdown(parent, controlItem)
    elseif fieldType == "notificationSound" and GUI2.Form.CreateNotificationSound then
        return GUI2.Form:CreateNotificationSound(parent, controlItem)
    elseif (fieldType == "specDropdown" or fieldType == "specdropdown") and GUI2.Form.CreateSpecDropdown then
        return GUI2.Form:CreateSpecDropdown(parent, controlItem)
    elseif fieldType == "texture" and S.CreateTextureSelector then
        return S:CreateTextureSelector(parent, controlItem)
    elseif fieldType == "color" then
        return GUI2.Form:CreateColorPicker(parent, controlItem)
    elseif fieldType == "glow" and GUI2.Form.CreateGlowOptions then
        return GUI2.Form:CreateGlowOptions(parent, controlItem)
    elseif fieldType == "slider" then
        return GUI2.Form:CreateSlider(parent, controlItem)
    elseif fieldType == "checkbox" then
        return GUI2.Form:CreateCheckbox(parent, controlItem)
    elseif fieldType == "editbox" then
        return GUI2.Form:CreateEditBox(parent, controlItem)
    elseif fieldType == "button" then
        controlItem.text = field.text or field.label
        return GUI2.Form:CreateButton(parent, controlItem)
    elseif fieldType == "switch" then
        return GUI2.Form:CreateSwitch(parent, controlItem)
    elseif fieldType == "binarychoice" then
        return GUI2.Form:CreateBinaryChoice(parent, controlItem)
    elseif fieldType == "segmented" then
        return GUI2.Form:CreateSegmentedControl(parent, controlItem)
    elseif (fieldType == "specMultiSelect" or fieldType == "specmultiselect") and S.CreateSpecMultiSelectDropdown then
        return S:CreateSpecMultiSelectDropdown(parent, controlItem)
    elseif fieldType == "custom" and field.render then
        return field.render(parent, controlItem, bodyWidth, valueWidth, valueGap)
    end

    return nil
end

local function RenderTopLabelFields(parent, opts, fields, availableWidth)
    local columns = math.max(math.floor(tonumber(opts.columns) or 2), 1)
    local columnGap = tonumber(opts.columnGap) or GetSettingsFormMetric("gap", 10) * 2
    local minColumnWidth = tonumber(opts.minColumnWidth) or GetSettingsFormMetric("width.normal", 180)
    while columns > 1 and columns * minColumnWidth + (columns - 1) * columnGap > availableWidth do
        columns = columns - 1
    end
    local columnWidth = math.max(1, math.floor((availableWidth - (columns - 1) * columnGap) / columns))
    local totalWidth = columns * columnWidth + (columns - 1) * columnGap
    local rowHeight = tonumber(opts.rowHeight) or GetSettingsFormMetric("rowHeight", 32)
    local rowGap = tonumber(opts.rowGap) or GetSettingsFormMetric("rowGap", 10)
    local labelGap = tonumber(opts.topLabelGap) or GetSettingsFormMetric("gap", 10) / 2
    local valueWidth = tonumber(opts.valueWidth) or GetSettingsFormMetric("valueWidth", 56)
    local valueGap = tonumber(opts.valueGap) or GetSettingsFormMetric("gap", 10)
    local container = GUI2:CreateFrame(parent, { width = totalWidth, height = 1 })
    container:SetPoint("TOPLEFT", tonumber(opts.x) or 0, tonumber(opts.y) or 0)
    container.alignedFields = {}
    local rows, current = {}, nil
    for _, field in ipairs(fields) do
        if ShouldRenderAlignedField(field) then
            local span = field.span == "full" and columns
                or math.min(columns, math.max(1, math.floor(tonumber(field.span) or 1)))
            local checkbox = field.type == "checkbox"
            local inlineLabel = GetAlignedFieldLayoutValue(field, "labelPosition") == "left" and not checkbox
            local minControlWidth = inlineLabel and tonumber(GetAlignedFieldLayoutValue(field, "minControlWidth"))
            local configuredControlWidth = field.bodyWidth or GetAlignedFieldLayoutValue(field, "controlWidth")
            local label, labelHeight, inlineLabelWidth
            field.labelRegion = nil
            if field.label and field.label ~= "" then
                local colorKey = field.disabled and "color.text.disabled" or "color.text.primary"
                label = GUI2:CreateText(container, field.label, "font.size.md", colorKey)
                ApplyConfigTextColor(label, field, colorKey)
                if minControlWidth then
                    inlineLabelWidth = math.max(tonumber(GetAlignedFieldLayoutValue(field, "minLabelWidth")) or 0,
                        tonumber(field.labelWidth) or (label:GetStringWidth() + (tonumber(GetAlignedFieldLayoutValue(field, "labelPadding")) or 0)))
                    local requiredWidth = inlineLabelWidth + valueGap + math.max(minControlWidth, configuredControlWidth or 0)
                    span = math.min(columns, math.max(span, math.ceil((requiredWidth + columnGap) / (columnWidth + columnGap))))
                end
            end
            if not current or current.used + span > columns then
                current = { entries = {}, used = 0, labelHeight = 0, controlHeight = rowHeight }
                rows[#rows + 1] = current
            end
            local fieldWidth = span * columnWidth + (span - 1) * columnGap
            if label then
                if inlineLabel then
                    if configuredControlWidth then
                        inlineLabelWidth = fieldWidth - math.min(configuredControlWidth, fieldWidth) - valueGap
                    elseif minControlWidth then
                        inlineLabelWidth = math.min(inlineLabelWidth, math.max(1, fieldWidth - valueGap - minControlWidth))
                    else
                        inlineLabelWidth = math.min(field.labelWidth or label:GetStringWidth(), fieldWidth / 2)
                    end
                end
                label:SetWidth(math.max(1, inlineLabelWidth or (fieldWidth - (checkbox and 26 or 0))))
                label:SetJustifyH("LEFT")
                label:SetWordWrap(not inlineLabel)
                if label.SetNonSpaceWrap then label:SetNonSpaceWrap(true) end
                labelHeight = math.max(GUI2:GetMetric("font.size.md", 13), label:GetStringHeight() or 0)
                field.labelRegion = label
            end
            local controlOffset = inlineLabelWidth and math.max(0, inlineLabelWidth) + valueGap or 0
            local controlWidth = math.max(1, fieldWidth - controlOffset)
            local widget = CreateAlignedFieldWidget(container, field, controlWidth, valueWidth, valueGap, controlWidth)
            if widget then
                local entry = { widget = widget, x = current.used * (columnWidth + columnGap),
                    height = widget:GetHeight() or rowHeight, checkbox = checkbox, label = label,
                    inlineLabel = inlineLabel, controlOffset = controlOffset }
                if label then
                    if checkbox or inlineLabel then
                        current.controlHeight = math.max(current.controlHeight, labelHeight)
                    else
                        current.labelHeight = math.max(current.labelHeight, labelHeight)
                    end
                end
                current.controlHeight = math.max(current.controlHeight, entry.height)
                current.entries[#current.entries + 1] = entry
                current.used = current.used + span
                field.widget = widget
                if S.Search then S.Search:Bind(field, widget, field.labelRegion) end
                container.alignedFields[#container.alignedFields + 1] = widget
            end
        end
    end
    function container:Relayout()
        local cursorY = 0
        for index, row in ipairs(rows) do
            local controlHeight = rowHeight
            for _, entry in ipairs(row.entries) do
                entry.height = entry.widget:GetHeight() or rowHeight
                controlHeight = math.max(controlHeight, entry.height)
                if entry.checkbox or entry.inlineLabel then
                    controlHeight = math.max(controlHeight, entry.label and entry.label:GetStringHeight() or 0)
                end
            end
            row.controlHeight = controlHeight
            local controlY = cursorY - row.labelHeight - (row.labelHeight > 0 and labelGap or 0)
            for _, entry in ipairs(row.entries) do
                entry.widget:ClearAllPoints()
                entry.widget:SetPoint("TOPLEFT", container, "TOPLEFT", entry.x + entry.controlOffset,
                    controlY - (row.controlHeight - entry.height) / 2)
                if entry.label then
                    if entry.checkbox or entry.inlineLabel then
                        entry.label:SetPoint("LEFT", container, "TOPLEFT", entry.x + (entry.checkbox and 26 or 0), controlY - row.controlHeight / 2)
                    else
                        entry.label:SetPoint("TOPLEFT", container, "TOPLEFT", entry.x, cursorY)
                    end
                end
            end
            cursorY = controlY - row.controlHeight - (index < #rows and rowGap or 0)
        end
        local totalHeight = math.max(1, -cursorY)
        if self:GetHeight() ~= totalHeight then self:SetHeight(totalHeight) end
        return totalHeight
    end
    for _, field in ipairs(fields) do
        if field.type == "notificationSound" and field.widget and field.widget.HookScript then
            field.widget:HookScript("OnSizeChanged", function() container:Relayout() end)
        end
    end
    return container, totalWidth, container:Relayout()
end

function S:RenderAlignedFields(parent, opts)
    if not (parent and GUI2 and GUI2.CreateFrame and GUI2.CreateText and GUI2.Form) then
        return nil, 0, 0
    end

    opts = type(opts) == "table" and opts or {}
    local fields = type(opts.fields) == "table" and opts.fields or {}
    local x = tonumber(opts.x) or 0
    local y = tonumber(opts.y) or 0
    local availableWidth = tonumber(opts.width)
    if not availableWidth and parent.GetWidth then
        availableWidth = (parent:GetWidth() or 0) - x
    end
    availableWidth = math.max(availableWidth or 1, 1)

    if opts.labelPosition == "top" then
        return RenderTopLabelFields(parent, opts, fields, availableWidth)
    end

    local columns = math.max(math.floor(tonumber(opts.columns) or 2), 1)
    local columnGap = tonumber(opts.columnGap) or tonumber(opts.gap) or 24
    local labelWidth = tonumber(opts.labelWidth) or GetSettingsFormMetric("labelWidth", 120)
    local labelGap = tonumber(opts.labelGap) or tonumber(opts.controlGap) or GetSettingsFormMetric("gap", 10)
    local bodyWidth = tonumber(opts.bodyWidth) or tonumber(opts.controlWidth) or GetSettingsFormMetric("controlWidth", 220)
    local valueWidth = tonumber(opts.valueWidth) or tonumber(opts.inputWidth) or GetSettingsFormMetric("valueWidth", 56)
    local valueGap = tonumber(opts.valueGap) or GetSettingsFormMetric("gap", 10)
    local rowHeight = tonumber(opts.rowHeight) or GetSettingsFormMetric("rowHeight", 32)
    local rowGap = tonumber(opts.rowGap) or 10
    local minBodyWidth = tonumber(opts.minBodyWidth) or 1
    local columnWidth = tonumber(opts.columnWidth) or (labelWidth + labelGap + bodyWidth)

    while columns > 1 and (columns * columnWidth + (columns - 1) * columnGap) > availableWidth do
        columns = columns - 1
    end

    local fittedColumnWidth = math.floor((availableWidth - ((columns - 1) * columnGap)) / columns)
    if fittedColumnWidth > 0 and columnWidth > fittedColumnWidth then
        bodyWidth = math.max(fittedColumnWidth - labelWidth - labelGap, minBodyWidth)
        columnWidth = labelWidth + labelGap + bodyWidth
    end

    local visibleFields = {}
    for _, field in ipairs(fields) do
        if ShouldRenderAlignedField(field) then
            visibleFields[#visibleFields + 1] = field
        end
    end

    local rowCount = math.max(math.ceil(#visibleFields / columns), 1)
    local totalWidth = columns * columnWidth + (columns - 1) * columnGap
    local totalHeight = rowCount * rowHeight + (rowCount - 1) * rowGap
    local container = GUI2:CreateFrame(parent, {
        width = totalWidth,
        height = totalHeight,
    })
    container:SetPoint("TOPLEFT", x, y)
    container.alignedFields = {}

    for index, field in ipairs(visibleFields) do
        local row = math.floor((index - 1) / columns)
        local col = (index - 1) % columns
        local fieldX = col * (columnWidth + columnGap)
        local fieldY = -(row * (rowHeight + rowGap))
        local centerY = fieldY - (rowHeight / 2)

        if field.label and field.label ~= "" then
            local label = GUI2:CreateText(container, field.label, "font.size.md", field.disabled and "color.text.disabled" or "color.text.primary")
            label:SetWidth(labelWidth)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            label:SetPoint("LEFT", container, "TOPLEFT", fieldX, centerY)
            ApplyConfigTextColor(label, field, field.disabled and "color.text.disabled" or "color.text.primary")
            field.labelRegion = label
        end

        local widget = CreateAlignedFieldWidget(container, field, bodyWidth, valueWidth, valueGap)
        if widget and widget.SetPoint then
            if widget.ClearAllPoints then
                widget:ClearAllPoints()
            end
            widget:SetPoint("LEFT", container, "TOPLEFT", fieldX + labelWidth + labelGap, centerY)
            field.widget = widget
            if S.Search then S.Search:Bind(field, widget, field.labelRegion) end
            container.alignedFields[#container.alignedFields + 1] = widget
        end
    end

    return container, totalWidth, totalHeight
end

local function EnsureRightPreviewPanel()
    if Elements.rightPreviewPanel then
        return Elements.rightPreviewPanel
    end
    if not (Elements.frame and GUI2 and GUI2.CreatePanel and UIParent) then
        return nil
    end

    local panel = GUI2:CreatePanel(UIParent, {
        name = "YUI_SettingsRightPreviewFrame",
        width = RIGHT_PREVIEW_DEFAULT_WIDTH,
        height = RIGHT_PREVIEW_DEFAULT_HEIGHT,
        surface = "color.surface.raised",
        border = "color.border.default",
        shadow = true,
    })
    panel:SetPoint("TOPLEFT", Elements.frame, "TOPRIGHT", RIGHT_PREVIEW_GAP, 0)
    S:RegisterScaleWindow(panel)
    if panel.SetClampedToScreen then
        panel:SetClampedToScreen(true)
    end
    if Elements.frame.GetFrameStrata and panel.SetFrameStrata then
        panel:SetFrameStrata(Elements.frame:GetFrameStrata())
    end
    if Elements.frame.GetFrameLevel and panel.SetFrameLevel then
        panel:SetFrameLevel((Elements.frame:GetFrameLevel() or 0) + 2)
    end
    panel:Hide()

    local title = GUI2:CreateText(panel, "", "font.size.md", "color.text.heading")
    title:SetPoint("TOPLEFT", RIGHT_PREVIEW_INSET, -8)
    title:SetPoint("TOPRIGHT", -RIGHT_PREVIEW_INSET, -8)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    panel.title = title

    local content = GUI2:CreateFrame(panel)
    content:SetPoint("TOPLEFT", RIGHT_PREVIEW_INSET, -RIGHT_PREVIEW_TITLE_HEIGHT - 8)
    content:SetPoint("BOTTOMRIGHT", -RIGHT_PREVIEW_INSET, RIGHT_PREVIEW_INSET)
    panel.content = content

    Elements.rightPreviewPanel = panel
    Elements.rightPreviewContent = content
    Elements.rightPreviewTitle = title
    return panel
end

function S:ShowRightPreview(owner, opts)
    opts = type(opts) == "table" and opts or {}
    local panel = EnsureRightPreviewPanel()
    if not panel then return nil end

    if Elements.rightPreviewOnClear then
        pcall(Elements.rightPreviewOnClear, Elements.rightPreviewContent, Elements.rightPreviewPanel, {
            replacing = Elements.rightPreviewOwner == owner,
        })
    end

    local content = Elements.rightPreviewContent
    if content then
        content:SetScript("OnUpdate", nil)
        self:ClearConfig(content)
    end

    local width = math.max(tonumber(opts.width) or RIGHT_PREVIEW_DEFAULT_WIDTH, 80)
    local height = math.max(tonumber(opts.height) or RIGHT_PREVIEW_DEFAULT_HEIGHT, 80)
    panel:SetSize(width, height)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", Elements.frame, "TOPRIGHT", RIGHT_PREVIEW_GAP, 0)
    if Elements.frame.GetFrameStrata and panel.SetFrameStrata then
        panel:SetFrameStrata(Elements.frame:GetFrameStrata())
    end
    if Elements.frame.GetFrameLevel and panel.SetFrameLevel then
        panel:SetFrameLevel((Elements.frame:GetFrameLevel() or 0) + 2)
    end

    if Elements.rightPreviewTitle then
        Elements.rightPreviewTitle:SetText(opts.title or "")
        if opts.title ~= nil and opts.title ~= "" then
            Elements.rightPreviewTitle:Show()
        else
            Elements.rightPreviewTitle:Hide()
        end
    end
    if content then
        content:ClearAllPoints()
        if opts.title ~= nil and opts.title ~= "" then
            content:SetPoint("TOPLEFT", RIGHT_PREVIEW_INSET, -RIGHT_PREVIEW_TITLE_HEIGHT - 8)
        else
            content:SetPoint("TOPLEFT", RIGHT_PREVIEW_INSET, -RIGHT_PREVIEW_INSET)
        end
        content:SetPoint("BOTTOMRIGHT", -RIGHT_PREVIEW_INSET, RIGHT_PREVIEW_INSET)
    end

    Elements.rightPreviewOwner = owner
    Elements.rightPreviewOnClear = type(opts.onClear) == "function" and opts.onClear or nil
    panel:Show()

    if type(opts.render) == "function" and content then
        local ok, err = pcall(opts.render, content, {
            panel = panel,
            content = content,
            width = width - RIGHT_PREVIEW_INSET * 2,
            height = height - RIGHT_PREVIEW_INSET * 2 - ((opts.title ~= nil and opts.title ~= "") and RIGHT_PREVIEW_TITLE_HEIGHT or 0),
        })
        if not ok then
            print("|cffff0000YUI Settings Preview Error:|r " .. tostring(err))
        end
    end

    return content, panel
end

function S:ClearRightPreview(owner)
    if owner ~= nil and Elements.rightPreviewOwner ~= owner then
        return false
    end

    if Elements.rightPreviewOnClear then
        pcall(Elements.rightPreviewOnClear, Elements.rightPreviewContent, Elements.rightPreviewPanel, {
            clearing = true,
        })
    end
    Elements.rightPreviewOnClear = nil
    Elements.rightPreviewOwner = nil

    local content = Elements.rightPreviewContent
    if content then
        content:SetScript("OnUpdate", nil)
        self:ClearConfig(content)
    end
    if Elements.rightPreviewPanel then
        Elements.rightPreviewPanel:Hide()
    end
    return true
end

local function GetSpecUnitAPI()
    return YUI.API and YUI.API.Unit or YUI.WOW_API or {}
end

local function GetSpecTalentAPI()
    return YUI.API and YUI.API.Talent or YUI.WOW_API or {}
end

local function BuildSpecSelectionKey(classToken, specID)
    if not classToken or not specID then return nil end
    return tostring(classToken) .. ":" .. tostring(specID)
end

function S:BuildSpecSelectionKey(classToken, specID)
    return BuildSpecSelectionKey(classToken, specID)
end

local function GetSpecPlayerClassToken()
    local UnitAPI = GetSpecUnitAPI()
    local _, classToken
    if UnitAPI.UnitClass then
        _, classToken = UnitAPI.UnitClass("player")
    elseif UnitClass then
        _, classToken = UnitClass("player")
    end
    return classToken
end

function S:GetCurrentSpecSelectionKey()
    local TalentAPI = GetSpecTalentAPI()
    local classToken = GetSpecPlayerClassToken()
    if (TalentAPI.GetCurrentConfigurationSpecializationInfo or TalentAPI.GetCurrentSpecializationInfo) then
        local specInfo = (TalentAPI.GetCurrentConfigurationSpecializationInfo or TalentAPI.GetCurrentSpecializationInfo)()
        if specInfo and specInfo.isInitial ~= true and specInfo.specID then
            return BuildSpecSelectionKey(specInfo.classFile or classToken, specInfo.specID)
        end
    end

    if YUI.IsForever and TalentAPI.GetCurrentConfigurationSpecializationInfo then return nil end

    local specIndex = TalentAPI.GetSpecialization and TalentAPI.GetSpecialization() or GetSpecialization and GetSpecialization()
    if specIndex then
        if TalentAPI.IsInitialSpecializationIndex
            and TalentAPI.IsInitialSpecializationIndex(specIndex) then
            return nil
        end
        local specID = TalentAPI.GetSpecializationInfo and TalentAPI.GetSpecializationInfo(specIndex)
            or GetSpecializationInfo and GetSpecializationInfo(specIndex)
        return BuildSpecSelectionKey(classToken, specID or specIndex)
    end

    return nil
end

local function InsetSpecClassTexCoord(texCoord)
    if type(texCoord) ~= "table" then return nil end
    local left = texCoord[1] or 0
    local right = texCoord[2] or 1
    local top = texCoord[3] or 0
    local bottom = texCoord[4] or 1
    local width = right - left
    local height = bottom - top
    local insetX = width * SPEC_CLASS_ICON_TEXCOORD_INSET
    local insetY = height * SPEC_CLASS_ICON_TEXCOORD_INSET
    return { left + insetX, right - insetX, top + insetY, bottom - insetY }
end

local function GetSpecClassIcon(classToken)
    local texCoord = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken] or nil
    if texCoord then
        return SPEC_CLASS_ICON_TEXTURE, InsetSpecClassTexCoord(texCoord)
    end
    return SPEC_DEFAULT_ICON, nil
end

local function GetSpecClassInfoMap()
    local UnitAPI = GetSpecUnitAPI()
    local map = {}
    local classInfos

    if UnitAPI.GetClassInfos then
        classInfos = UnitAPI.GetClassInfos()
    else
        classInfos = {}
        local count = UnitAPI.GetNumClasses and UnitAPI.GetNumClasses() or GetNumClasses and GetNumClasses() or 0
        for index = 1, count do
            local info
            if UnitAPI.GetClassInfo then
                info = UnitAPI.GetClassInfo(index)
            elseif GetClassInfo then
                local className, classFile, classID = GetClassInfo(index)
                info = { className = className, classFile = classFile, classID = classID }
            end
            classInfos[#classInfos + 1] = info
        end
    end

    for index, info in ipairs(classInfos or {}) do
        if type(info) == "table" and info.classFile then
            local icon, texCoord = GetSpecClassIcon(info.classFile)
            map[info.classFile] = {
                token = info.classFile,
                name = YUI.Locale and YUI.Locale.GetClassName
                    and YUI.Locale:GetClassName(info.classFile, info.className or info.classFile)
                    or info.className or info.classFile,
                classID = info.classID or info.id or index,
                icon = icon,
                iconTexCoord = texCoord,
            }
        end
    end

    if not next(map) then
        for _, armorGroup in ipairs(SPEC_ARMOR_GROUPS) do
            for _, token in ipairs(armorGroup.classes) do
                if not map[token] then
                    local icon, texCoord = GetSpecClassIcon(token)
                    map[token] = {
                        token = token,
                        name = YUI.Locale and YUI.Locale.GetClassName
                            and YUI.Locale:GetClassName(token, token)
                            or token,
                        icon = icon,
                        iconTexCoord = texCoord,
                    }
                end
            end
        end
    end

    return map
end

local function GetSpecClassColor(classToken)
    local UnitAPI = GetSpecUnitAPI()
    local color = UnitAPI.GetClassColor and UnitAPI.GetClassColor(classToken)
    if color then
        return color.r or 1, color.g or 1, color.b or 1, 1
    end
    color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if color then
        return color.r or 1, color.g or 1, color.b or 1, 1
    end
    return 1, 1, 1, 1
end

local function GetSpecsForSelectorClass(classInfo)
    local TalentAPI = GetSpecTalentAPI()
    local specs = {}

    if classInfo and (TalentAPI.GetClassConfigurationSpecializations or TalentAPI.GetClassSpecializations) then
        for _, specInfo in ipairs((TalentAPI.GetClassConfigurationSpecializations or TalentAPI.GetClassSpecializations)(classInfo)) do
            if specInfo.specID then
                local specName = specInfo.name or tostring(specInfo.specID)
                specs[#specs + 1] = {
                    key = BuildSpecSelectionKey(specInfo.classFile or classInfo.token, specInfo.specID),
                    specID = specInfo.specID,
                    name = specName,
                    displayName = GetSpecDisplayName(specInfo.specID, specName),
                    icon = specInfo.icon or SPEC_DEFAULT_ICON,
                    classInfo = classInfo,
                }
            end
        end
    end

    if #specs == 0 and classInfo and classInfo.classID and GetSpecializationInfoForClassID then
        local sex = UnitSex and UnitSex("player") or nil
        local count = TalentAPI.GetNumSpecializationsForClassID and TalentAPI.GetNumSpecializationsForClassID(classInfo.classID)
            or GetNumSpecializationsForClassID and GetNumSpecializationsForClassID(classInfo.classID)
            or 0
        for index = 1, count do
            local specID, specName, _, specIcon = GetSpecializationInfoForClassID(classInfo.classID, index, sex)
            if specID then
                specName = specName or tostring(specID)
                specs[#specs + 1] = {
                    key = BuildSpecSelectionKey(classInfo.token, specID),
                    specID = specID,
                    name = specName,
                    displayName = GetSpecDisplayName(specID, specName),
                    icon = specIcon or SPEC_DEFAULT_ICON,
                    classInfo = classInfo,
                }
            end
        end
    end

    if #specs == 0 and classInfo and classInfo.token == GetSpecPlayerClassToken() then
        local count = TalentAPI.GetNumSpecializations and TalentAPI.GetNumSpecializations() or GetNumSpecializations and GetNumSpecializations() or 0
        for index = 1, count do
            local specID, specName, _, specIcon
            if TalentAPI.GetSpecializationInfo then
                specID, specName, _, specIcon = TalentAPI.GetSpecializationInfo(index)
            elseif GetSpecializationInfo then
                specID, specName, _, specIcon = GetSpecializationInfo(index)
            end
            specID = specID or index
            specName = specName or tostring(specID)
            specs[#specs + 1] = {
                key = BuildSpecSelectionKey(classInfo.token, specID),
                specID = specID,
                name = specName,
                displayName = GetSpecDisplayName(specID, specName),
                icon = specIcon or SPEC_DEFAULT_ICON,
                classInfo = classInfo,
            }
        end
    end

    return specs
end

function S:GetSpecSelectionGroups(opts)
    opts = type(opts) == "table" and opts or {}
    local classMap = GetSpecClassInfoMap()
    local groups = {}
    local armorLabels = type(opts.armorLabels) == "table" and opts.armorLabels or {}

    for _, group in ipairs(SPEC_ARMOR_GROUPS) do
        local result = {
            key = group.key,
            label = armorLabels[group.key] or LC["settings.config_sets.armor." .. group.key] or group.fallback,
            classes = {},
            specs = {},
        }
        for _, classToken in ipairs(group.classes) do
            local classInfo = classMap[classToken]
            if classInfo then
                result.classes[#result.classes + 1] = classInfo
                local specs = GetSpecsForSelectorClass(classInfo)
                for _, spec in ipairs(specs) do
                    result.specs[#result.specs + 1] = spec
                end
            end
        end
        if #result.specs > 0 then
            groups[#groups + 1] = result
        end
    end

    return groups
end

local function ResolveSpecSelectionGroups(opts)
    local groups = opts and opts.groups
    if type(groups) == "function" then
        groups = groups(opts)
    end
    if type(groups) ~= "table" then
        groups = S:GetSpecSelectionGroups(opts)
    end
    return groups
end

local function CleanupSpecMultiSelectPanel(panel, reason)
    local anchor = Elements.specMultiSelectAnchor
    local activeOptions = panel and panel.activeOptions or nil
    local closeReason = reason or (panel and panel.pendingCloseReason) or "hidden"

    if anchor and anchor.arrow then
        GUI2:SetDropdownGlyphColor(anchor.arrow, "color.accent.primary")
    end
    Elements.specMultiSelectOwner = nil
    Elements.specMultiSelectAnchor = nil

    if panel then
        panel.pendingCloseReason = nil
        panel.activeOptions = nil
        panel.activeGroups = nil
        if panel.blocker then panel.blocker:Hide() end
        if panel.content then
            S:ClearConfig(panel.content)
        end
    end

    if activeOptions and type(activeOptions.onClose) == "function" then
        activeOptions.onClose(closeReason)
    end
end

local function EnsureSpecMultiSelectPanel()
    if Elements.specMultiSelectPanel then
        return Elements.specMultiSelectPanel
    end
    if not (GUI2 and GUI2.CreatePanel and UIParent) then
        return nil
    end

    local panel = GUI2:CreatePanel(UIParent, {
        name = "YUI_SettingsSpecMultiSelectPanel",
        width = SPEC_PANEL_WIDTH,
        height = SPEC_PANEL_HEIGHT,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    S:RegisterScaleWindow(panel)
    panel:SetFrameStrata("TOOLTIP")
    panel:SetFrameLevel(9100)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()

    local blocker = GUI2:CreateFrame(UIParent, {
        type = "Button",
        frameStrata = "TOOLTIP",
        frameLevel = 9000,
        allPoints = true,
        mouse = true,
        hidden = true,
    })
    blocker:SetScript("OnClick", function()
        S:CloseSpecMultiSelectDropdown(nil, "dismissed")
    end)
    panel.blocker = blocker

    panel.close = GUI2:CreateCloseButton(panel, function()
        S:CloseSpecMultiSelectDropdown(nil, "close-button")
    end)
    panel.close:SetPoint("TOPRIGHT", -10, -10)

    local title = GUI2:CreateText(panel, "", "font.size.md", "color.text.heading")
    title:SetPoint("TOPLEFT", SPEC_PANEL_INSET, -10)
    title:SetPoint("TOPRIGHT", -38, -10)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    panel.title = title

    local scroll = GUI2:CreateScrollFrame(panel, {
        template = "UIPanelScrollFrameTemplate",
    })
    scroll:SetPoint("TOPLEFT", SPEC_PANEL_INSET, -38)
    scroll:SetPoint("BOTTOMRIGHT", -SPEC_PANEL_INSET, SPEC_PANEL_INSET)
    panel.scrollFrame = scroll
    panel.content = scroll.child

    panel:SetScript("OnHide", function(self)
        CleanupSpecMultiSelectPanel(self, self.pendingCloseReason)
    end)
    Elements.specMultiSelectPanel = panel
    return panel
end

function S:CloseSpecMultiSelectDropdown(owner, reason)
    if owner ~= nil and Elements.specMultiSelectOwner ~= owner then
        return false
    end

    local panel = Elements.specMultiSelectPanel
    if panel then
        if panel.blocker then panel.blocker:Hide() end
        if panel:IsShown() then
            panel.pendingCloseReason = reason or "closed"
            panel:Hide()
        else
            CleanupSpecMultiSelectPanel(panel, reason or "closed")
        end
    else
        CleanupSpecMultiSelectPanel(nil, reason or "closed")
    end
    return true
end

local function SpecSelectionTable(opts)
    local value = opts.get and opts.get() or opts.value
    if type(value) ~= "table" and type(opts.selected) == "table" then
        value = opts.selected
    end
    if type(value) ~= "table" and type(opts.defaultSelection) == "table" then
        value = opts.defaultSelection
    end
    if type(value) ~= "table" then
        value = {}
        if opts.set then opts.set(value) end
    end
    opts.value = value
    return value
end

local function IsSpecSelected(valueTable, key, defaultSelected)
    if defaultSelected then
        return valueTable[key] ~= false
    end
    return valueTable[key] == true
end

local function SetSpecSelected(valueTable, key, selected, defaultSelected)
    if defaultSelected then
        if selected then
            valueTable[key] = nil
        else
            valueTable[key] = false
        end
    else
        if selected then
            valueTable[key] = true
        else
            valueTable[key] = nil
        end
    end
end

local function CountSelectedSpecs(groups, valueTable, defaultSelected)
    local selected = 0
    local total = 0
    for _, group in ipairs(groups or {}) do
        for _, spec in ipairs(group.specs or {}) do
            total = total + 1
            if IsSpecSelected(valueTable, spec.key, defaultSelected) then
                selected = selected + 1
            end
        end
    end
    return selected, total
end

local function GetSpecSummaryText(opts, selected, total)
    if type(opts.summaryFormatter) == "function" then
        return opts.summaryFormatter(selected, total)
    end
    return string.format("%d/%d Specs", selected, total)
end

local function CommitSpecSelection(opts, button, valueTable)
    opts.value = valueTable
    if opts.set then opts.set(valueTable) end
    if opts.onChange then opts.onChange(button, valueTable) end
end

local function RenderSpecToggle(parent, spec, x, y, width, height, selected, onClick)
    local nativeIcon = spec.icon or SPEC_DEFAULT_ICON
    local button = GUI2.Form:CreateButton(parent, {
        width = width,
        height = height,
        text = spec.displayName or spec.name or tostring(spec.specID or ""),
        icon = nativeIcon,
        iconSize = SPEC_ICON_SIZE,
        contentAlign = "center",
        justifyH = "CENTER",
        preserveIconColor = true,
        tone = "default",
        onClick = onClick,
    })
    button:SetPoint("TOPLEFT", x, y)

    local Icons = YUI.API and YUI.API.Icons
    if button.icon and Icons and Icons.GetScopedSpecIcon and Icons.ApplyIcon then
        local iconData = Icons.GetScopedSpecIcon(spec.specID, nativeIcon, "settings")
        if iconData then
            Icons.ApplyIcon(button.icon, iconData)
        end
    end
    button.specIcon = button.icon

    local label = button.text
    if label then
        label:SetWordWrap(false)
        if spec.classInfo and spec.classInfo.token then
            label:SetTextColor(GetSpecClassColor(spec.classInfo.token))
        end
    end

    function button:SetSpecSelected(isSelected)
        self.gui2SpecSelected = isSelected and true or false
        if self.SetSelected then
            self:SetSelected(self.gui2SpecSelected)
        end
    end

    if GameTooltip then
        button:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local className = spec.classInfo and spec.classInfo.name or ""
            GameTooltip:SetText((className ~= "" and (className .. " - ") or "") .. (spec.name or tostring(spec.specID or "")), 1, 1, 1)
            GameTooltip:Show()
        end)
        button:HookScript("OnLeave", function()
            YUI.HideGameTooltip()
        end)
    end

    button:SetSpecSelected(selected)
    return button
end

local function RenderSpecMultiSelectPanel(anchor, opts, groups)
    local panel = EnsureSpecMultiSelectPanel()
    if not panel then return end

    local valueTable = SpecSelectionTable(opts)
    local defaultSelected = opts.defaultSelected ~= false
    local panelWidth = math.max(tonumber(opts.panelWidth) or SPEC_PANEL_WIDTH, 320)
    local panelHeight = math.max(tonumber(opts.panelHeight) or SPEC_PANEL_HEIGHT, 220)

    panel:SetSize(panelWidth, panelHeight)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    if panel.title then
        panel.title:SetText(opts.panelTitle or opts.label or "")
    end
    if panel.blocker then
        panel.blocker:Show()
    end
    if panel.content then
        S:ClearConfig(panel.content)
    end

    local content = panel.content
    local innerWidth = panelWidth
        - SPEC_PANEL_INSET * 2
        - SPEC_PANEL_SCROLLBAR_RESERVE
    local preferredButtonWidth = math.min(
        math.max(tonumber(opts.specButtonWidth) or SPEC_BUTTON_WIDTH, 96),
        innerWidth
    )
    local columns = math.max(
        math.floor(
            (innerWidth + SPEC_PANEL_GAP)
                / (preferredButtonWidth + SPEC_PANEL_GAP)
        ),
        1
    )
    local buttonWidth = (
        innerWidth - (columns - 1) * SPEC_PANEL_GAP
    ) / columns
    local contentY = 0
    local renderedButtons = {}
    local selectedCount = 0
    local totalCount = 0

    local function RefreshSummary()
        if anchor.SetSpecSummary then
            anchor:SetSpecSummary(selectedCount, totalCount)
        end
    end

    local function RefreshAll()
        selectedCount, totalCount = CountSelectedSpecs(groups, valueTable, defaultSelected)
        RefreshSummary()
        for _, entry in ipairs(renderedButtons) do
            entry.button:SetSpecSelected(IsSpecSelected(valueTable, entry.key, defaultSelected))
        end
    end

    local topActions = GUI2:CreateFrame(content, { width = innerWidth, height = SPEC_BUTTON_HEIGHT })
    topActions:SetPoint("TOPLEFT", 0, contentY)
    local selectAll = GUI2.Form:CreateButton(topActions, {
        text = opts.selectAllText or LC["settings.config_sets.assignment.all"] or "All",
        width = 82,
        height = SPEC_BUTTON_HEIGHT,
        onClick = function()
            for _, group in ipairs(groups or {}) do
                for _, spec in ipairs(group.specs or {}) do
                    SetSpecSelected(valueTable, spec.key, true, defaultSelected)
                end
            end
            CommitSpecSelection(opts, anchor, valueTable)
            RefreshAll()
        end,
    })
    selectAll:SetPoint("TOPLEFT", 0, 0)
    local clearAll = GUI2.Form:CreateButton(topActions, {
        text = opts.clearText or LC["settings.config_sets.assignment.clear"] or "Clear",
        width = 82,
        height = SPEC_BUTTON_HEIGHT,
        onClick = function()
            for _, group in ipairs(groups or {}) do
                for _, spec in ipairs(group.specs or {}) do
                    SetSpecSelected(valueTable, spec.key, false, defaultSelected)
                end
            end
            CommitSpecSelection(opts, anchor, valueTable)
            RefreshAll()
        end,
    })
    clearAll:SetPoint("LEFT", selectAll, "RIGHT", SPEC_PANEL_GAP, 0)
    contentY = contentY - SPEC_BUTTON_HEIGHT - 12

    for _, group in ipairs(groups or {}) do
        local header = GUI2:CreateText(content, group.label or "", "font.size.md", "color.text.accent")
        header:SetPoint("TOPLEFT", 0, contentY)
        header:SetWidth(innerWidth)
        header:SetJustifyH("LEFT")
        header:SetWordWrap(false)
        contentY = contentY - 24

        for index, spec in ipairs(group.specs or {}) do
            local col = (index - 1) % columns
            local row = math.floor((index - 1) / columns)
            local x = col * (buttonWidth + SPEC_PANEL_GAP)
            local y = contentY - row * (SPEC_BUTTON_HEIGHT + SPEC_PANEL_GAP)
            local key = spec.key
            local button
            button = RenderSpecToggle(
                content,
                spec,
                x,
                y,
                buttonWidth,
                SPEC_BUTTON_HEIGHT,
                IsSpecSelected(valueTable, key, defaultSelected),
                function()
                    local nextSelected =
                        not IsSpecSelected(valueTable, key, defaultSelected)
                    SetSpecSelected(valueTable, key, nextSelected, defaultSelected)
                    selectedCount = selectedCount + (nextSelected and 1 or -1)
                    button:SetSpecSelected(nextSelected)
                    RefreshSummary()
                    CommitSpecSelection(opts, anchor, valueTable)
                end
            )
            renderedButtons[#renderedButtons + 1] = { button = button, key = key }
        end

        local rows = math.max(math.ceil(#(group.specs or {}) / columns), 1)
        contentY = contentY - rows * (SPEC_BUTTON_HEIGHT + SPEC_PANEL_GAP) - 12
    end

    if content then
        content:SetSize(innerWidth, math.max(math.abs(contentY) + 12, panelHeight - 56))
    end
    if panel.scrollFrame and panel.scrollFrame.SetVerticalScroll then
        panel.scrollFrame:SetVerticalScroll(0)
    end

    Elements.specMultiSelectOwner = opts.owner or anchor
    Elements.specMultiSelectAnchor = anchor
    panel.activeOptions = opts
    panel.activeGroups = groups
    panel:Show()
    if anchor.arrow then
        GUI2:SetDropdownGlyphColor(anchor.arrow, "color.text.accent")
    end
    RefreshAll()
end

function S:OpenSpecMultiSelectDropdown(anchor, opts)
    if not anchor then return nil end
    opts = type(opts) == "table" and opts or {}

    if opts.value == nil then
        if type(opts.selected) == "table" then
            opts.value = opts.selected
        elseif type(opts.defaultSelection) == "table" then
            opts.value = opts.defaultSelection
        end
    end

    local groups = ResolveSpecSelectionGroups(opts)
    self:CloseSpecMultiSelectDropdown(nil, "replaced")
    RenderSpecMultiSelectPanel(anchor, opts, groups)
    return Elements.specMultiSelectPanel
end

function S:CreateSpecMultiSelectDropdown(parent, opts)
    opts = type(opts) == "table" and opts or {}
    local width = tonumber(opts.width) or SPEC_DROPDOWN_WIDTH
    local height = tonumber(opts.height) or SPEC_DROPDOWN_HEIGHT
    local button = GUI2:CreateButtonFrame(parent, { template = "BackdropTemplate", width = width, height = height })
    button.width = width
    button.height = height
    GUI2:SkinDropdownButton(button)

    local groups = ResolveSpecSelectionGroups(opts)
    local defaultSelected = opts.defaultSelected ~= false

    function button:SetSpecSummary(selected, total)
        if self.text then
            self.text:SetText(" " .. GetSpecSummaryText(opts, selected or 0, total or 0))
        end
    end

    local function RefreshSummary()
        local selectedCount, totalCount = CountSelectedSpecs(groups, SpecSelectionTable(opts), defaultSelected)
        button:SetSpecSummary(selectedCount, totalCount)
    end

    button:SetScript("OnMouseUp", function(self)
        if self.gui2Disabled then return end
        local owner = opts.owner or self
        if Elements.specMultiSelectPanel and Elements.specMultiSelectPanel:IsShown() and Elements.specMultiSelectOwner == owner then
            S:CloseSpecMultiSelectDropdown(owner, "toggle")
            return
        end
        S:OpenSpecMultiSelectDropdown(self, opts)
    end)
    button:SetScript("OnHide", function(self)
        S:CloseSpecMultiSelectDropdown(opts.owner or self, "owner-hidden")
    end)

    function button:Refresh()
        groups = ResolveSpecSelectionGroups(opts)
        RefreshSummary()
    end

    RefreshSummary()
    return button
end

-- Configuration Renderer Engine
function S:RenderConfig(parent, config)
    local pageLayout = S.ModulePageLayout
    local startX = pageLayout.insetX
    local startY = -pageLayout.titleTop
    if parent.yuiConfigTopInset ~= nil then
        startY = -parent.yuiConfigTopInset
    end
    local yOffset = startY
    local xOffset = startX
    S._dividerCollapseState = S._dividerCollapseState or {}
    if S.Search then S.Search:PrepareConfig(config) end

    local function getFormMetric(name, fallback)
        return GUI2:GetMetric("layout.form." .. name, fallback)
    end

    local function refreshRenderedConfig(contentHeight)
        if parent.yuiConfigAfterRender then
            parent.yuiConfigAfterRender(parent, contentHeight)
        end
        if selectedModule and selectedModule.frame == parent and S.RefreshCurrentModuleScroll then
            S:RefreshCurrentModuleScroll(false)
        end
    end

    local function rerenderConfig()
        local scrollFrame = parent.yuiConfigScrollFrame
        local currentScroll = scrollFrame and scrollFrame.GetVerticalScroll and scrollFrame:GetVerticalScroll() or nil
        S:ClearConfig(parent)
        S:RenderConfig(parent, config)
        if currentScroll and scrollFrame and scrollFrame.SetVerticalScroll then
            local maxScroll = scrollFrame.GetVerticalScrollRange and scrollFrame:GetVerticalScrollRange() or currentScroll
            scrollFrame:SetVerticalScroll(math.min(currentScroll, maxScroll or currentScroll))
        end
    end

    local function shouldRenderItem(item)
        if not item then return false end

        local requires = item.requires
        if requires and not requires() then
            return false
        end

        local hidden = item.hidden
        if type(hidden) == "function" then
            return not hidden()
        end
        return hidden ~= true
    end

    local function getDividerCollapseKey(item)
        return item.collapseKey or item.key or item.id or item.label
    end

    local function isDividerCollapsed(item)
        if not item or item.collapsible ~= true then return false end
        local key = getDividerCollapseKey(item)
        if key ~= nil and S._dividerCollapseState[key] ~= nil then
            return S._dividerCollapseState[key] == true
        end
        return item.collapsed == true
    end

    local function prepareDividerItem(item)
        if not item or item.type ~= "divider" or item.collapsible ~= true then
            return item
        end

        local copy = {}
        for k, v in pairs(item) do
            copy[k] = v
        end

        local key = getDividerCollapseKey(item)
        local originalOnToggle = item.onToggle
        copy.collapsed = isDividerCollapsed(item)
        copy.onToggle = function(nextCollapsed, divider)
            if key ~= nil then
                S._dividerCollapseState[key] = nextCollapsed == true
            end
            if originalOnToggle then
                originalOnToggle(nextCollapsed, divider)
            end
            rerenderConfig()
        end

        return copy
    end

    local function shouldUseFormLayout(item)
        if not item or not FORM_LAYOUT_TYPES[item.type] then return false end
        if item.layout == "legacy" then return false end
        return item.layout == "form" or item.layout == nil
    end

    local function hasRowTopLabel(item)
        if item and item.inlineLabel == true then return false end
        return item and item.label and (
            item.type == "dropdown" or
            item.type == "specDropdown" or
            item.type == "specdropdown" or
            item.type == "font" or
            item.type == "sound" or
            item.type == "notificationSound" or
            item.type == "texture"
        )
    end

    local function alignsToRowControlLane(item)
        if not item then return false end
        if item.type == "slider" then
            return item.inline == true and item.layout ~= "legacy"
        end
        if hasRowTopLabel(item) then return true end
        return item.type == "checkbox" or
            item.type == "binarychoice" or
            item.type == "button" or
            item.type == "switch" or
            item.type == "segmented" or
            item.type == "specDropdown" or
            item.type == "specdropdown" or
            item.type == "color" or
            item.type == "glow" or
            item.type == "sound" or
            item.type == "notificationSound" or
            item.type == "editbox"
    end

    local function getFormLabel(item)
        if not item then return nil end
        if item.formLabel ~= nil then return item.formLabel end
        if item.type == "checkbox" and item.labelPosition == "left" then return item.label end
        if item.type == "checkbox" then return nil end
        if item.inlineLabel ~= false then return item.label end
        return nil
    end

    local function cloneFormItem(item, controlWidth, valueWidth, gap)
        local copy = {}
        for k, v in pairs(item) do
            copy[k] = v
        end

        if item.type == "checkbox" then
            local usesFormLabel = item.formLabel ~= nil or item.labelPosition == "left"
            copy.text = item.checkboxText or item.text or (usesFormLabel and "" or item.label) or ""
            if usesFormLabel then
                copy.label = nil
            end
        elseif item.inlineLabel ~= false then
            copy.label = nil
        end

        if item.type == "slider" then
            copy.inline = true
            if not copy.width and not copy.size then
                copy.width = controlWidth + gap + valueWidth
            end
            if not copy.inputWidth then
                copy.inputWidth = valueWidth
            end
        elseif item.type == "switch" then
            copy.width = item.width or 64
        elseif item.type == "binarychoice" or item.type == "segmented" then
            copy.width = item.width or controlWidth
        elseif item.type == "glow" then
            copy.width = item.width or controlWidth
            copy.inputWidth = item.inputWidth or valueWidth
        elseif not copy.width and not copy.size then
            copy.width = controlWidth
        end

        return copy
    end

    local function cloneControlItem(item, controlWidth)
        local copy = {}
        for k, v in pairs(item) do
            copy[k] = v
        end
        copy.label = nil
        copy.inlineLabel = nil
        if controlWidth then
            copy.width = controlWidth
        end
        return copy
    end

    local function createInlineLabelControl(container, item, controlFactory)
        local labelWidth = item.labelWidth or getFormMetric("labelWidth", 120)
        local gap = item.gap or getFormMetric("gap", 10)
        local totalWidth = item.width or item.rowWidth or (labelWidth + gap + (item.controlWidth or getFormMetric("controlWidth", 220)))
        local controlWidth = item.controlWidth or math.max(totalWidth - labelWidth - gap, 1)
        local rowHeight = item.rowHeight or getFormMetric("rowHeight", 32)
        local row = GUI2:CreateFrame(container, {
            width = totalWidth,
            height = rowHeight,
        })

        local label = GUI2:CreateText(row, item.label, "font.size.md", item.disabled and "color.text.disabled" or "color.text.primary")
        label:SetWidth(labelWidth)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetPoint("LEFT", row, "LEFT", 0, 0)
        ApplyConfigTextColor(label, item, item.disabled and "color.text.disabled" or "color.text.primary")
        row.label = label

        local control = controlFactory(row, cloneControlItem(item, controlWidth))
        control:SetPoint("LEFT", row, "LEFT", labelWidth + gap, 0)
        row.widget = control
        row:SetHeight(math.max(rowHeight, control:GetHeight() or 0))

        return row, totalWidth, row:GetHeight(), row
    end

    local function positionWidget(widget, row, x, rowHeight)
        if not widget then return end
        if widget.ClearAllPoints then
            widget:ClearAllPoints()
        end
        widget:SetPoint("LEFT", row, "LEFT", x, 0)
        if widget.GetHeight then
            rowHeight = math.max(rowHeight, widget:GetHeight() or 0)
        end
        return rowHeight
    end
    
    local function renderItem(item, container, x, y)
        local requires = item.requires
        local hidden = item.hidden
        local isHidden = false
        if hidden then
            if type(hidden) == "function" then
                isHidden = hidden()
            else
                isHidden = hidden
            end
        end

        if (requires and not requires()) or isHidden then
            return nil, 0, 0
        end

        local width = item.width
        local height = item.height or 24
        local widget
        
        -- Helper for DB binding
        if item.key then
            if not item.get then
                item.get = function() 
                    if YUI.getConfigByKey then
                        return YUI:getConfigByKey(item.key, item.default)
                    end
                    return item.default
                end
            end
            if not item.set then
                item.set = function(value)
                    if YUI.setConfigByKey then
                        YUI:setConfigByKey(item.key, value)
                    end
                end
            end
        end
        
        if item.type == "header" then
            widget = GUI2:CreateText(container, item.label, GUI2.Fonts.size_title, GetTextColorKey(item, "color.text.heading"))
            widget:SetFont(GUI2.Fonts.header, GUI2.Fonts.size_title, "OUTLINE")
            ApplyConfigTextColor(widget, item, "color.text.heading")
            height = 30
            
        elseif item.type == "text" then
            local size = item.size or (item.style == "header" and GUI2.Fonts.size_header or GUI2.Fonts.size_normal)
            local defaultColorKey = item.style == "header" and "color.text.heading" or "color.text.primary"
            widget = GUI2:CreateText(container, item.label, size, GetTextColorKey(item, defaultColorKey), item.justify)
            ApplyConfigTextColor(widget, item, defaultColorKey)

            local shouldWrap = item.wrap ~= false and item.noWrap ~= true
            if shouldWrap then
                 widget:SetWidth(item.width or (container:GetWidth() - 40))
                 widget:SetWordWrap(true)
                 if widget.SetNonSpaceWrap then
                     widget:SetNonSpaceWrap(true)
                 end
                 height = math.max(20, (widget:GetStringHeight() or 0) + 5)
            else
                 if item.width then
                     widget:SetWidth(item.width)
                 end
                 widget:SetWordWrap(false)
                 height = 20
            end
            if container.yuiConfigTopInset ~= nil then
                -- Nested scroll pages need room for font ascenders at their top edge.
                local topPadding = y == startY and 4 or 0
                widget:SetHeight(height)
                widget:SetJustifyV("TOP")
                widget:SetPoint("TOPLEFT", x, y - topPadding)
                height = height + topPadding
            end
            
        elseif item.type == "image" then
            width = item.width or 64
            height = item.height or 64
            widget = GUI2:CreateTexture(container, { layer = "ARTWORK" })
            widget:SetSize(width, height)
            if item.texture then widget:SetTexture(item.texture) end
            
        elseif item.type == "custom" then
            if item.render then
                local w, h = item.render(container, x, y, width or (container:GetWidth() - 40))
                if w then width = w end
                if h then height = h end
            end

        elseif item.type == "button" then
            width = width or 120
            widget = GUI2.Form:CreateButton(container, {
                text = item.label,
                width = width,
                height = item.height,
                tone = item.tone,
                disabled = item.disabled,
                tooltip = item.tooltip,
                icon = item.icon or item.texture,
                atlas = item.atlas,
                iconSize = item.iconSize,
                iconLeftPadding = item.iconLeftPadding,
                iconGap = item.iconGap,
                iconYOffset = item.iconYOffset,
                contentAlign = item.contentAlign,
                iconCrop = item.iconCrop,
                iconTexCoords = item.iconTexCoords or item.texCoords,
                onClick = item.onClick,
            })
            height = widget:GetHeight()
            
        elseif item.type == "checkbox" then
            if (item.label and item.labelPosition == "left") or item.formLabel ~= nil then
                local checkboxItem = item
                if item.formLabel ~= nil then
                    checkboxItem = {}
                    for k, v in pairs(item) do checkboxItem[k] = v end
                    checkboxItem.label = item.formLabel
                end
                widget, width, height = createInlineLabelControl(container, checkboxItem, function(parentFrame, controlItem)
                    return GUI2.Form:CreateCheckbox(parentFrame, controlItem)
                end)
            else
                widget = GUI2.Form:CreateCheckbox(container, item)
                width = widget.width
                height = widget.height
            end
            
        elseif item.type == "slider" then
            widget = GUI2.Form:CreateSlider(container, item)
            width = widget:GetWidth()
            height = widget:GetHeight()
            
        elseif item.type == "editbox" then
            widget = GUI2.Form:CreateEditBox(container, item)
            width = widget:GetWidth()
            height = widget:GetHeight()
            
        elseif item.type == "dropdown" or item.type == "specDropdown" or item.type == "specdropdown" then
            local function createDropdownControl(parentFrame, controlItem)
                if (item.type == "specDropdown" or item.type == "specdropdown") and GUI2.Form.CreateSpecDropdown then
                    return GUI2.Form:CreateSpecDropdown(parentFrame, controlItem)
                end
                return GUI2.Form:CreateDropdown(parentFrame, controlItem)
            end

            if item.label and item.inlineLabel == true then
                widget, width, height = createInlineLabelControl(container, item, function(parentFrame, controlItem)
                    return createDropdownControl(parentFrame, controlItem)
                end)
            else
                widget = createDropdownControl(container, item)
                width = widget:GetWidth()
                height = widget:GetHeight()
            
                if item.label then
                     local lbl = GUI2:CreateText(widget, item.label, GUI2.Fonts.size_normal)
                     lbl:SetWidth(item.labelWidth or width)
                     lbl:SetJustifyH("LEFT")
                     lbl:SetWordWrap(false)
                     lbl:SetPoint("BOTTOMLEFT", widget, "TOPLEFT", 0, 5)
                     height = height + 20
                     widget:SetPoint("TOPLEFT", x, y - 20)
                end
            end
            
        elseif item.type == "font" then
            local fontConfig = {}
            for k,v in pairs(item) do fontConfig[k] = v end
            fontConfig.prependOptions = fontConfig.prependOptions
                or fontConfig.options
            
            if item.label and item.inlineLabel == true then
                widget, width, height = createInlineLabelControl(container, fontConfig, function(parentFrame, controlItem)
                    return GUI2.Form:CreateLSMFontDropdown(parentFrame, controlItem)
                end)
            else
                widget = GUI2.Form:CreateLSMFontDropdown(container, fontConfig)
                width = widget:GetWidth()
                height = widget:GetHeight()

                if item.label then
                     local lbl = GUI2:CreateText(widget, item.label, GUI2.Fonts.size_normal)
                     lbl:SetWidth(item.labelWidth or width)
                     lbl:SetJustifyH("LEFT")
                     lbl:SetWordWrap(false)
                     lbl:SetPoint("BOTTOMLEFT", widget, "TOPLEFT", 0, 5)
                     height = height + 20
                     widget:SetPoint("TOPLEFT", x, y - 20)
                end
            end

        elseif item.type == "sound" then
            local soundConfig = {}
            for k, v in pairs(item) do soundConfig[k] = v end
            soundConfig.options = BuildLSMMediaDropdownOptions("sound", item)
            soundConfig.default = soundConfig.default or "None"
            local function createSoundControl(parentFrame, controlItem)
                if GUI2.Form.CreateLSMSoundDropdown then
                    return GUI2.Form:CreateLSMSoundDropdown(parentFrame, controlItem)
                end
                return GUI2.Form:CreateDropdown(parentFrame, controlItem)
            end

            if item.label and item.inlineLabel == true then
                widget, width, height = createInlineLabelControl(container, soundConfig, function(parentFrame, controlItem)
                    return createSoundControl(parentFrame, controlItem)
                end)
            else
                widget = createSoundControl(container, soundConfig)
                width = widget:GetWidth()
                height = widget:GetHeight()

                if item.label then
                     local lbl = GUI2:CreateText(widget, item.label, GUI2.Fonts.size_normal)
                     lbl:SetWidth(item.labelWidth or width)
                     lbl:SetJustifyH("LEFT")
                     lbl:SetWordWrap(false)
                     lbl:SetPoint("BOTTOMLEFT", widget, "TOPLEFT", 0, 5)
                     height = height + 20
                     widget:SetPoint("TOPLEFT", x, y - 20)
                end
            end
            
        elseif item.type == "notificationSound" then
            if item.label and item.inlineLabel == true then
                widget, width, height = createInlineLabelControl(container, item, function(parentFrame, controlItem)
                    return GUI2.Form:CreateNotificationSound(parentFrame, controlItem)
                end)
            else
                widget = GUI2.Form:CreateNotificationSound(container, item)
                width = widget:GetWidth()
                height = widget:GetHeight()
                if item.label then
                    local lbl = GUI2:CreateText(widget, item.label, GUI2.Fonts.size_normal)
                    lbl:SetWidth(item.labelWidth or width)
                    lbl:SetJustifyH("LEFT")
                    lbl:SetWordWrap(false)
                    lbl:SetPoint("BOTTOMLEFT", widget, "TOPLEFT", 0, 5)
                    height = height + 20
                    widget:SetPoint("TOPLEFT", x, y - 20)
                end
            end

        elseif item.type == "color" then
            if item.label and item.inlineLabel == true then
                widget, width, height = createInlineLabelControl(container, item, function(parentFrame, controlItem)
                    return GUI2.Form:CreateColorPicker(parentFrame, controlItem)
                end)
            else
                widget = GUI2.Form:CreateColorPicker(container, item)
                width = widget:GetWidth()
                height = widget:GetHeight()
            end

        elseif item.type == "glow" then
            widget = GUI2.Form:CreateGlowOptions(container, item)
            width = widget:GetWidth()
            height = widget:GetHeight()

        elseif item.type == "binarychoice" then
            if item.label and item.inlineLabel == true then
                widget, width, height = createInlineLabelControl(container, item, function(parentFrame, controlItem)
                    return GUI2.Form:CreateBinaryChoice(parentFrame, controlItem)
                end)
            else
                widget = GUI2.Form:CreateBinaryChoice(container, item)
                width = widget:GetWidth()
                height = widget:GetHeight()
            end

        elseif item.type == "segmented" then
            if item.label and item.inlineLabel == true then
                widget, width, height = createInlineLabelControl(container, item, function(parentFrame, controlItem)
                    return GUI2.Form:CreateSegmentedControl(parentFrame, controlItem)
                end)
            else
                widget = GUI2.Form:CreateSegmentedControl(container, item)
                width = widget:GetWidth()
                height = widget:GetHeight()
            end

        elseif item.type == "switch" then
            if item.label and item.inlineLabel == true then
                widget, width, height = createInlineLabelControl(container, item, function(parentFrame, controlItem)
                    return GUI2.Form:CreateSwitch(parentFrame, controlItem)
                end)
            else
                widget = item.label and GUI2:CreateSwitch(container, item) or GUI2.Form:CreateSwitch(container, item)
                width = widget:GetWidth()
                height = widget:GetHeight()
            end

        elseif item.type == "mod-switch" then
            widget = GUI2.Application:CreateModSwitch(container, item)
            width = widget:GetWidth()
            height = widget:GetHeight()

        elseif item.type == "texture" then
            if item.label and item.inlineLabel == true then
                widget, width, height = createInlineLabelControl(container, item, function(parentFrame, controlItem)
                    return S:CreateTextureSelector(parentFrame, controlItem)
                end)
            else
                widget = S:CreateTextureSelector(container, item)
                width = widget:GetWidth()
                height = widget:GetHeight()

                if item.label then
                     local lbl = GUI2:CreateText(widget, item.label, GUI2.Fonts.size_normal)
                     lbl:SetWidth(item.labelWidth or width)
                     lbl:SetJustifyH("LEFT")
                     lbl:SetWordWrap(false)
                     lbl:SetPoint("BOTTOMLEFT", widget, "TOPLEFT", 0, 5)
                     height = height + 20
                     widget:SetPoint("TOPLEFT", x, y - 20)
                end
            end

        elseif item.type == "table" then
            widget = GUI2:CreateTable(container, item)
            width = widget:GetWidth()
            height = widget:GetHeight()

        elseif item.type == "divider" then
            widget = GUI2:CreateDivider(container, item)
            width = widget:GetWidth()
            height = widget:GetHeight()

            if item.alignLeft then
                widget:SetPoint("TOPLEFT", x, y - 5)
            else
                widget:SetPoint("TOP", container, "TOP", 0, y - 5)
            end
        end
        
        if widget and not widget:GetPoint() then
            widget:SetPoint("TOPLEFT", x, y)
        end
        
        if S.Search then S.Search:Bind(item, widget) end
        return widget, width or 0, height, widget
    end

    local function renderFormItem(item, container, x, y)
        local formLabel = getFormLabel(item)
        local labelWidth = item.labelWidth or getFormMetric("labelWidth", 120)
        local controlWidth = item.controlWidth or getFormMetric("controlWidth", 220)
        local valueWidth = item.valueWidth or getFormMetric("valueWidth", 56)
        local gap = item.gap or getFormMetric("gap", 10)
        local rowHeight = item.rowHeight or getFormMetric("rowHeight", 32)
        local controlX = (item.type == "checkbox" and formLabel == nil) and 0 or (labelWidth + gap)
        local totalWidth = item.rowWidth or (controlX + controlWidth + (controlX > 0 and (gap + valueWidth) or 0))
        local row = GUI2:CreateFrame(container, {
            width = totalWidth,
            height = rowHeight,
        })
        row:SetPoint("TOPLEFT", x, y)

        if formLabel and formLabel ~= "" then
            local label = GUI2:CreateText(row, formLabel, "font.size.md", item.disabled and "color.text.disabled" or "color.text.primary")
            label:SetWidth(labelWidth)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            label:SetPoint("LEFT", row, "LEFT", 0, 0)
            ApplyConfigTextColor(label, item, item.disabled and "color.text.disabled" or "color.text.primary")
            row.label = label
        end

        local controlItem = cloneFormItem(item, controlWidth, valueWidth, gap)
        local widget, _, widgetHeight = renderItem(controlItem, row, controlX, 0)
        rowHeight = math.max(rowHeight, widgetHeight or 0)
        if item.type == "glow" or item.type == "notificationSound" then
            local topRowHeight = (widget and (widget.gui2TopRowHeight or widget.topRowHeight)) or (item.rowHeight or getFormMetric("rowHeight", 32))
            if row.label then
                row.label:ClearAllPoints()
                row.label:SetPoint("LEFT", row, "TOPLEFT", 0, -(topRowHeight / 2))
            end
            if widget then
                if widget.ClearAllPoints then
                    widget:ClearAllPoints()
                end
                widget:SetPoint("TOPLEFT", row, "TOPLEFT", controlX, 0)
            end
        else
            rowHeight = positionWidget(widget, row, controlX, rowHeight) or rowHeight
        end
        row:SetSize(totalWidth, rowHeight)
        row.widget = widget
        if S.Search then S.Search:Bind(item, row) end

        return row, totalWidth, rowHeight, row
    end

    local collapsedGroup = false
    for _, item in ipairs(config) do
        if item.type == "divider" then
            collapsedGroup = false
        end

        if shouldRenderItem(item) then
            if item.type == "row" then
                if not collapsedGroup then
                    local rowX = xOffset
                    local childGap = item.gap or item.columnGap or 20
                    local rowGap = item.rowGap or 15
                    local maxHeight = 0
                    local maxControlHeight = 0
                    local hasLabelLane = false
                    local rowWidgets = {}

                    for _, child in ipairs(item.children) do
                        if hasRowTopLabel(child) then
                            hasLabelLane = true
                            break
                        end
                    end

                    for _, child in ipairs(item.children) do
                        local w, wW, wH, wWidget = renderItem(child, parent, rowX, yOffset)
                        if w then
                            local height = wH or 0
                            local hasTopLabel = hasRowTopLabel(child)
                            local alignToControlLane = alignsToRowControlLane(child)
                            local controlHeight = hasTopLabel and math.max(height - 20, 0) or height

                            maxHeight = math.max(maxHeight, height)
                            if alignToControlLane then
                                maxControlHeight = math.max(maxControlHeight, controlHeight)
                            end
                            table.insert(rowWidgets, {
                                widget = wWidget,
                                x = rowX,
                                height = height,
                                controlHeight = controlHeight,
                                alignToControlLane = alignToControlLane,
                            })
                            rowX = rowX + wW + childGap
                        end
                    end

                    if hasLabelLane then
                        maxHeight = math.max(maxHeight, 20 + maxControlHeight)
                    end

                    for _, rowItem in ipairs(rowWidgets) do
                        local widget = rowItem.widget
                        if widget then
                            local itemY = yOffset
                            if hasLabelLane and rowItem.alignToControlLane then
                                local diff = maxControlHeight - rowItem.controlHeight
                                local offsetY = diff > 0 and -(diff / 2) or 0
                                itemY = yOffset - 20 + offsetY
                            else
                                local diff = maxHeight - rowItem.height
                                local offsetY = diff > 0 and -(diff / 2) or 0
                                itemY = yOffset + offsetY
                            end
                            if widget.ClearAllPoints then
                                widget:ClearAllPoints()
                            end
                            widget:SetPoint("TOPLEFT", rowItem.x, itemY)
                        end
                    end

                    yOffset = yOffset - maxHeight - rowGap
                end
            elseif item.type == "space" then
                if not collapsedGroup then
                    yOffset = yOffset - (item.height or 20)
                end
            elseif shouldUseFormLayout(item) then
                if not collapsedGroup then
                    local w, wW, wH = renderFormItem(item, parent, xOffset, yOffset)
                    if wH then
                        yOffset = yOffset - wH - (item.rowGap or getFormMetric("rowGap", 10))
                    end
                end
            else
                local renderItemConfig = item.type == "divider" and prepareDividerItem(item) or item
                local w, wW, wH = nil, nil, nil
                if item.type == "divider" or not collapsedGroup then
                    w, wW, wH = renderItem(renderItemConfig, parent, xOffset, yOffset)
                end
                if wH then
                    yOffset = yOffset - wH - 15
                end
                if item.type == "divider" then
                    collapsedGroup = isDividerCollapsed(renderItemConfig)
                end
            end
        end
    end
    
    local contentHeight = math.abs(yOffset) + 20
    parent:SetHeight(contentHeight)
    refreshRenderedConfig(contentHeight)
end

function SortModules()
    local orderMap = {}
    if S.ModuleOrder then
        for i, key in ipairs(S.ModuleOrder) do
            orderMap[key] = i
        end
    end

    local activeProduct = GetProduct(S.ActiveProductId)
    local activeProductEntry = activeProduct and activeProduct.settings and activeProduct.settings.entry
    local prioritizeProductEntry = activeProductEntry and not ProductUsesSuiteSettings(activeProduct)

    local function GetSortOrder(module)
        if prioritizeProductEntry and module and module.id == activeProductEntry then
            return 0
        end
        return orderMap[module.id or module.name] or orderMap[module.name] or 999
    end
    
    table.sort(S.modules, function(a, b)
        local orderA = GetSortOrder(a)
        local orderB = GetSortOrder(b)
        
        if orderA ~= orderB then
            return orderA < orderB
        else
            -- 如果都在配置表中没找到（或者配置相同），则按注册顺序
            return (a.registerIndex or 0) < (b.registerIndex or 0)
        end
    end)
end

function S:RefreshGUI2Theme()
    if Elements.frame then
        if Elements.frame.bg then GUI2:SetTexturePaintKey(Elements.frame.bg, "color.surface.window") end
        if Elements.separator then GUI2:SetTexturePaintKey(Elements.separator, "color.border.default") end
        if Elements.headerLine then GUI2:SetTexturePaintKey(Elements.headerLine, "color.border.default") end
        if Elements.versionText then GUI2:SetTextColorKey(Elements.versionText, "color.text.secondary") end
        if Elements.changelogLinkText then GUI2:SetTextColorKey(Elements.changelogLinkText, "color.text.accent") end
        if Elements.changelogLinkUnderline then GUI2:SetTexturePaintKey(Elements.changelogLinkUnderline, "color.text.accent") end
        if Elements.contactSeparator then GUI2:SetTexturePaintKey(Elements.contactSeparator, "color.border.default") end
        if Elements.contactAuthorText then GUI2:SetTextColorKey(Elements.contactAuthorText, "color.text.secondary") end
        if Elements.rightPreviewPanel and Elements.rightPreviewPanel.RefreshTheme then Elements.rightPreviewPanel:RefreshTheme() end
        if Elements.rightPreviewTitle then GUI2:SetTextColorKey(Elements.rightPreviewTitle, "color.text.heading") end
        if Elements.specMultiSelectPanel and Elements.specMultiSelectPanel.RefreshTheme then Elements.specMultiSelectPanel:RefreshTheme() end
        if Elements.specMultiSelectPanel and Elements.specMultiSelectPanel.title then GUI2:SetTextColorKey(Elements.specMultiSelectPanel.title, "color.text.heading") end
    end

    if S.CopyFrame and S.CopyFrame.RefreshTheme then S.CopyFrame:RefreshTheme() end
    if S.ConfirmFrame and S.ConfirmFrame.RefreshTheme then S.ConfirmFrame:RefreshTheme() end
    if Elements.reloadBtn and Elements.reloadBtn.RefreshTheme then Elements.reloadBtn:RefreshTheme() end
    if Elements.editModeBtn and Elements.editModeBtn.RefreshTheme then Elements.editModeBtn:RefreshTheme() end
    if Elements.navButtons then
        S:RefreshNav()
    end
end

local function GetModuleNavToggle(module)
    local toggle = module and module.navToggle
    return type(toggle) == "table" and toggle or nil
end

local function GetModuleNavToggleState(module)
    local toggle = GetModuleNavToggle(module)
    if not toggle then
        return false
    end

    if type(toggle.get) == "function" then
        local ok, enabled = pcall(toggle.get, module, toggle)
        return ok and enabled == true
    end

    local moduleId = toggle.moduleId or toggle.id
    if moduleId and YUI.Module and YUI.Module.IsEnabled then
        return YUI.Module:IsEnabled(moduleId) == true
    end

    return false
end

local function SetModuleNavToggleState(module, enabled)
    local toggle = GetModuleNavToggle(module)
    if not toggle then
        return false
    end

    enabled = enabled == true
    if type(toggle.set) == "function" then
        local ok, result = pcall(toggle.set, module, enabled, toggle)
        return ok and result ~= false
    end

    local moduleId = toggle.moduleId or toggle.id
    if moduleId and YUI.Module and YUI.Module.SetEnabled then
        local result = YUI.Module:SetEnabled(moduleId, enabled)
        return result ~= false
    end

    return false
end

local function GetNavToggleTooltip(module, enabled)
    local key = enabled and "settings.nav.toggle.disable" or "settings.nav.toggle.enable"
    local fallback = enabled and "Disable %s" or "Enable %s"
    local template = LC[key] or fallback
    return string.format(template, GetModuleNavDisplayName(module))
end

local function GetNavToggleConfirmText(module, enabled)
    local key = enabled and "settings.nav.toggle.enable_confirm" or "settings.nav.toggle.disable_confirm"
    local fallback = enabled and "Enable %s?\nReload the UI to fully apply this change." or "Disable %s?\nReload the UI to fully apply this change."
    local template = LC[key] or fallback
    local successR, successG, successB = GUI2:GetColor("color.state.success")
    local function ColorizeSuccess(value)
        return string.format(
            "|cff%02x%02x%02x%s|r",
            math.floor((successR or 1) * 255 + 0.5),
            math.floor((successG or 1) * 255 + 0.5),
            math.floor((successB or 1) * 255 + 0.5),
            tostring(value or "")
        )
    end

    local text = string.format(template, ColorizeSuccess(GetModuleNavDisplayName(module)))
    local reloadKeyword = LC["settings.nav.toggle.reload_keyword"] or "Reload the UI"
    local keywordStart, keywordEnd = string.find(text, reloadKeyword, 1, true)
    if keywordStart then
        text = string.sub(text, 1, keywordStart - 1)
            .. ColorizeSuccess(reloadKeyword)
            .. string.sub(text, keywordEnd + 1)
    end
    return text
end

local function HideNavToggleTooltip(frame)
    if not GameTooltip then return end
    if frame and GameTooltip.IsOwned and GameTooltip:IsOwned(frame) then
        if YUI.HideGameTooltip then
            YUI.HideGameTooltip()
        else
            GameTooltip:Hide()
        end
    end
end

local function IsModuleNavToggleDisabled(module)
    return GetModuleNavToggle(module) ~= nil and GetModuleNavToggleState(module) ~= true
end

local function HideNavToggleDisabledContent()
    if Elements.disabledModuleFrame then
        Elements.disabledModuleFrame:Hide()
    end
end

local function ShowNavToggleDisabledContent(module)
    if not Elements.scrollChild then return end

    S:ClearRightPreview()
    S:CloseSpecMultiSelectDropdown()
    HideInactiveModuleFrames(module)
    if module and module.frame then
        module.frame:Hide()
    end

    local frame = Elements.disabledModuleFrame
    if not frame then
        frame = GUI2:CreateFrame(Elements.scrollChild)
        frame:SetPoint("TOPLEFT", 0, 0)
        frame:SetPoint("TOPRIGHT", 0, 0)
        frame:SetHeight(96)

        local text = GUI2:CreateText(
            frame,
            LC["settings.nav.toggle.disabled_content"] or "This module is disabled. Enable it first.",
            "font.size.lg",
            "color.text.secondary",
            "CENTER"
        )
        text:SetPoint("CENTER", frame, "CENTER", 0, 4)
        text:SetWidth(420)
        text:SetWordWrap(true)
        frame.text = text
        Elements.disabledModuleFrame = frame
    end

    if frame.text then
        frame.text:SetText(LC["settings.nav.toggle.disabled_content"] or "This module is disabled. Enable it first.")
    end
    frame:Show()
    if GUI2 and GUI2.QueuePixelRefresh then
        GUI2:QueuePixelRefresh()
    end
    S:RefreshCurrentModuleScroll(true)
end

function S:IsSearchModuleDisabled(module) return IsModuleNavToggleDisabled(module) end

function S:ShowSearchDisabledModule(module)
    selectedModule = module
    HideInactiveModuleFrames(module)
    ShowNavToggleDisabledContent(module)
end

local function GetNavToggleTextureSet()
    local presetId = GUI2 and GUI2.activePresetId or "midnight"
    return NAV_TOGGLE_TEXTURE_SETS[presetId] or NAV_TOGGLE_TEXTURE_SETS.midnight
end

local function RefreshNavToggleVisual(toggleButton, enabled)
    if not toggleButton or not toggleButton.yuiSettingsNavToggleTexture then return end
    if enabled ~= nil then
        toggleButton.yuiSettingsNavToggleEnabled = enabled == true
    end

    local isEnabled = toggleButton.yuiSettingsNavToggleEnabled == true
    local rowHovered = toggleButton.yuiSettingsNavRowHovered == true
    local directlyHovered = toggleButton.yuiSettingsNavToggleHovered == true
    local texture = toggleButton.yuiSettingsNavToggleTexture
    local textureSet = GetNavToggleTextureSet()
    texture:SetTexture(
        isEnabled
            and (directlyHovered and textureSet.hover or textureSet.enabled)
            or textureSet.disabled
    )
    texture:SetVertexColor(1, 1, 1, 1)
    texture:SetAlpha(rowHovered and 1 or (isEnabled and 0.72 or 0.62))
end

local function EnsureNavToggleButton(navButton)
    if not navButton then return end
    if navButton.navToggleButton and navButton.navToggleButton.yuiSettingsNavToggleTexture then
        return navButton.navToggleButton
    end
    if navButton.navToggleButton then
        navButton.navToggleButton:Hide()
        navButton.navToggleButton = nil
    end

    local toggleButton = GUI2:CreateButtonFrame(navButton, {
        width = NAV_TOGGLE_HIT_SIZE,
        height = NAV_TOGGLE_HIT_SIZE,
        clicks = "AnyUp",
    })
    toggleButton.gui2Component = "SettingsNavGemToggle"
    toggleButton.yuiSettingsNavButton = navButton
    if toggleButton.SetPropagateMouseClicks then
        toggleButton:SetPropagateMouseClicks(false)
    end

    local texture = toggleButton:CreateTexture(nil, "ARTWORK")
    texture:SetSize(NAV_TOGGLE_VISUAL_SIZE, NAV_TOGGLE_VISUAL_SIZE)
    texture:SetPoint("CENTER")
    if texture.EnableMouse then texture:EnableMouse(false) end
    toggleButton.yuiSettingsNavToggleTexture = texture

    toggleButton.RefreshTheme = function(frame)
        RefreshNavToggleVisual(frame)
    end
    toggleButton:SetScript("OnEnter", function(frame)
        frame.yuiSettingsNavToggleHovered = true
        local owner = frame.yuiSettingsNavButton
        if owner then
            owner.yuiSettingsNavRowHovered = true
            frame.yuiSettingsNavRowHovered = true
        end
        frame:RefreshTheme()
        local navModule = frame.yuiSettingsModule
        if navModule and GameTooltip then
            GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
            GameTooltip:SetText(GetNavToggleTooltip(navModule, GetModuleNavToggleState(navModule)), 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    toggleButton:SetScript("OnLeave", function(frame)
        frame.yuiSettingsNavToggleHovered = false
        local owner = frame.yuiSettingsNavButton
        local rowHovered = owner and owner.IsMouseOver and owner:IsMouseOver() == true
        if owner then owner.yuiSettingsNavRowHovered = rowHovered end
        frame.yuiSettingsNavRowHovered = rowHovered
        frame:RefreshTheme()
        HideNavToggleTooltip(frame)
    end)
    toggleButton:SetFrameLevel((navButton:GetFrameLevel() or 1) + 5)
    navButton.navToggleButton = toggleButton
    toggleButton:RefreshTheme()
    return toggleButton
end

local function ApplyNavToggleRowState(navButton, hasNavToggle, enabled, selected)
    if not navButton then return end
    local disabled = hasNavToggle and enabled ~= true
    navButton.yuiSettingsNavToggleDisabled = disabled
    navButton.yuiSettingsNavToggleHasToggle = hasNavToggle == true
    navButton.yuiSettingsNavToggleEnabled = enabled == true
    navButton.yuiSettingsNavToggleSelected = selected == true
    navButton:SetAlpha(1)
    if navButton.SetVisualDisabled then
        navButton:SetVisualDisabled(disabled, {
            selected = selected == true,
            iconColorKey = "color.text.secondary",
            iconAlpha = 0.52,
            textColorKey = "color.text.secondary",
            textAlpha = 0.68,
            iconBgAlpha = 0.16,
            hoverAlpha = 0.04,
            selectedIndicatorAlpha = 0.32,
            selectedBgAlpha = 0.12,
        })
    elseif navButton.RefreshTheme then
        navButton:RefreshTheme()
    end
end

local function RestoreDisabledNavToggleRowState(navButton)
    if navButton and navButton.yuiSettingsNavToggleDisabled then
        ApplyNavToggleRowState(
            navButton,
            navButton.yuiSettingsNavToggleHasToggle,
            navButton.yuiSettingsNavToggleEnabled,
            navButton.yuiSettingsNavToggleSelected
        )
    end
end

local function SetNavToggleRowHovered(navButton, hovered)
    if not navButton then return end
    navButton.yuiSettingsNavRowHovered = hovered == true
    local toggleButton = navButton.navToggleButton
    if toggleButton then
        toggleButton.yuiSettingsNavRowHovered = navButton.yuiSettingsNavRowHovered
        RefreshNavToggleVisual(toggleButton)
    end
    RestoreDisabledNavToggleRowState(navButton)
end

local function EnsureNavToggleRowHooks(navButton)
    if not navButton or navButton.yuiSettingsNavToggleRowHooks or not navButton.HookScript then return end
    navButton.yuiSettingsNavToggleRowHooks = true
    navButton:HookScript("OnEnter", function(frame)
        SetNavToggleRowHovered(frame, true)
    end)
    navButton:HookScript("OnLeave", function(frame)
        local toggleButton = frame.navToggleButton
        SetNavToggleRowHovered(frame, toggleButton and toggleButton.yuiSettingsNavToggleHovered == true)
    end)
    navButton:HookScript("OnMouseUp", RestoreDisabledNavToggleRowState)
end

local function ConfigureNavToggleButton(navButton, module)
    local toggle = GetModuleNavToggle(module)
    if not toggle then
        if navButton and navButton.navToggleButton then
            navButton.navToggleButton:Hide()
            navButton.navToggleButton.yuiSettingsModule = nil
        end
        return false
    end

    local toggleButton = EnsureNavToggleButton(navButton)
    if not toggleButton then return false end

    toggleButton:ClearAllPoints()
    toggleButton:SetPoint("RIGHT", -8, 0)
    toggleButton.yuiSettingsModule = module
    toggleButton.yuiSettingsNavRowHovered = navButton.yuiSettingsNavRowHovered == true
    RefreshNavToggleVisual(toggleButton, GetModuleNavToggleState(module))

    toggleButton:SetScript("OnClick", function(frame)
        local navModule = frame.yuiSettingsModule
        local nextEnabled = not GetModuleNavToggleState(navModule)
        local function applyToggle()
            if SetModuleNavToggleState(navModule, nextEnabled) then
                if selectedModule == navModule then
                    if nextEnabled then
                        S:SelectModule(navModule)
                    else
                        ShowNavToggleDisabledContent(navModule)
                        S:RefreshNav()
                    end
                else
                    S:RefreshNav()
                end
                if S.ShowReload then
                    S:ShowReload()
                end
            end
        end

        HideNavToggleTooltip(frame)
        if S.ShowConfirmPopup then
            S:ShowConfirmPopup(GetNavToggleConfirmText(navModule, nextEnabled), applyToggle, {
                titleText = LC["settings.nav.toggle.confirm_title"] or "Confirm Module Switch",
            })
        else
            applyToggle()
        end
    end)

    toggleButton:Show()
    return true
end

local function RefreshSelectedNavToggleContent()
    if not selectedModule then return end
    if IsModuleNavToggleDisabled(selectedModule) then
        ShowNavToggleDisabledContent(selectedModule)
    elseif Elements.disabledModuleFrame and Elements.disabledModuleFrame:IsShown() then
        S:SelectModule(selectedModule)
    end
end

function S:LayoutNav()
    local list = Elements.navList
    if not list then return end
    local count = Elements.navVisibleCount or 0
    local start = Elements.navStartOffset or NAV_START_OFFSET
    local available = math.max(1, Elements.nav:GetHeight() + start - NAV_FOOTER_HEIGHT - 8)
    list:SetPoint("TOPLEFT", 0, start)
    local height = NAV_BUTTON_HEIGHT
    if count > 0 then
        height = math.min(height, math.floor((available - (count - 1) * NAV_BUTTON_GAP) / count))
    end
    for i = 1, count do
        local button = Elements.navButtons[i]
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 10, -(i - 1) * (height + NAV_BUTTON_GAP))
        button:SetHeight(height)
    end
    Elements.navRowHeight = height
    if S.Search then S.Search:Layout() end
end

function S:RefreshNav()
    if not Elements.nav then return end
    
    -- 排序模块
    SortModules()
    
    if Elements.navButtons then
        for _, btn in ipairs(Elements.navButtons) do
            btn:Hide()
        end
    end
    Elements.navButtons = Elements.navButtons or {}
    
    local visibleModules = S:GetVisibleModules()
    local iconColumnWidth = S.CelestialSeries and S.CelestialSeries.NAV_ICON_SIZE or 26
    Elements.navVisibleCount = #visibleModules
    for i, module in ipairs(visibleModules) do
        local btn = Elements.navButtons[i]
        if not btn then
            btn = GUI2:CreateNavButton(
                Elements.navList,
                GetModuleNavDisplayName(module),
                module.icon,
                NAV_WIDTH - 20,
                NAV_BUTTON_HEIGHT,
                {
                    crop = module.navIconCrop,
                    size = module.navIconSize,
                    columnWidth = iconColumnWidth,
                }
            )
            Elements.navButtons[i] = btn
        end
        btn.gui2SurfaceToken = "color.settings.navItem"
        btn.gui2HoverSurfaceToken = "color.settings.navItem"
        btn.gui2SelectedSurfaceToken = "color.settings.navItem"
        btn.gui2NavHoverOverlayAlpha = 0.42
        btn.gui2NavSelectedOverlayAlpha = 0.28
        EnsureNavToggleRowHooks(btn)
        
        local hasNavToggle = ConfigureNavToggleButton(btn, module)
        local navToggleEnabled = true
        if hasNavToggle then
            navToggleEnabled = GetModuleNavToggleState(module) == true
        end
        if btn.SetTextRightInset then
            btn:SetTextRightInset(hasNavToggle and NAV_TOGGLE_TEXT_INSET or 10)
        end
        btn:SetText(GetModuleNavDisplayName(module))
        ApplyMainNavTextStyle(btn)
        if module.icon then
            btn:SetIcon(module.icon, {
                crop = module.navIconCrop,
                size = module.navIconSize,
                columnWidth = iconColumnWidth,
            })
        end
        btn:Show()
        
        btn:SetScript("OnClick", function()
            if IsModuleNavToggleDisabled(module) then
                return
            end
            S:SelectModule(module)
        end)
        
        if selectedModule == module then
            if btn.SetSelected then btn:SetSelected(true) end
            btn.isSelected = true
        else
            if btn.SetSelected then btn:SetSelected(false) end
            btn.hl:Hide()
            btn.isSelected = false
        end
        ApplyNavToggleRowState(btn, hasNavToggle, navToggleEnabled, selectedModule == module)
        
    end
    self:LayoutNav()
    RefreshSelectedNavToggleContent()
end

local function GetSettingsScrollBar()
    if not Elements.scrollFrame then return end
    local scrollBar = Elements.scrollFrame.ScrollBar or Elements.scrollFrame.gui2ScrollBar
    if not scrollBar and Elements.scrollFrame.GetName then
        local name = Elements.scrollFrame:GetName()
        if name then
            scrollBar = _G[name .. "ScrollBar"]
        end
    end
    return scrollBar
end

local function QueueGUI2PixelRefresh()
    if GUI2 and GUI2.QueuePixelRefresh then
        GUI2:QueuePixelRefresh()
    end
end

function S:RefreshCurrentModuleScroll(resetScroll)
    local contentFrame = selectedModule and selectedModule.frame
    if Elements.disabledModuleFrame and Elements.disabledModuleFrame:IsShown() then
        contentFrame = Elements.disabledModuleFrame
    end
    if not Elements.scrollChild or not selectedModule or not contentFrame then
        return
    end

    local contentHeight = contentFrame:GetHeight() or 1
    contentHeight = math.max(contentHeight, 1)
    Elements.scrollChild:SetHeight(contentHeight)

    local scrollFrame = Elements.scrollFrame
    if not scrollFrame then
        QueueGUI2PixelRefresh()
        return
    end

    local viewportHeight = scrollFrame:GetHeight() or 0
    local maxScroll = math.max(0, contentHeight - viewportHeight)
    local scrollBar = GetSettingsScrollBar()

    if maxScroll <= 0 then
        if scrollFrame.SetVerticalScroll then
            scrollFrame:SetVerticalScroll(0)
        end
        if scrollFrame.EnableMouseWheel then
            scrollFrame:EnableMouseWheel(false)
        end
        if scrollBar then
            scrollBar:Hide()
            scrollBar:SetAlpha(0)
            if scrollBar.visualThumb then scrollBar.visualThumb:Hide() end
        end
        QueueGUI2PixelRefresh()
        return
    end

    if scrollFrame.SetVerticalScroll then
        if resetScroll then
            scrollFrame:SetVerticalScroll(0)
        elseif scrollFrame.GetVerticalScroll then
            local currentScroll = scrollFrame:GetVerticalScroll() or 0
            if currentScroll > maxScroll then
                scrollFrame:SetVerticalScroll(maxScroll)
            elseif currentScroll < 0 then
                scrollFrame:SetVerticalScroll(0)
            end
        end
    end
    if scrollFrame.EnableMouseWheel then
        scrollFrame:EnableMouseWheel(true)
    end
    if scrollBar then
        scrollBar:Show()
        scrollBar:SetAlpha(1)
        if scrollBar.UpdateVisualTrack then scrollBar:UpdateVisualTrack() end
        if scrollBar.UpdateVisualThumb then scrollBar:UpdateVisualThumb() end
    end
    QueueGUI2PixelRefresh()
end

function S:RefreshSelectedModule()
    local module = selectedModule
    local frame = module and module.frame
    if not frame or not module.render or not S:IsOpen() then return false end
    local picker = GUI2.ColorPicker
    if picker and picker:DeferRefresh(frame, function()
        if selectedModule == module then S:RefreshSelectedModule() end
    end) then return true end
    if S.ClearRightPreview then S:ClearRightPreview() end
    if S.ClearConfig then S:ClearConfig(frame) end
    local ok, err = pcall(module.render, frame)
    if not ok then
        print("|cffff0000YUI Module Error:|r " .. (module.name or "Unknown") .. " - " .. tostring(err))
        return false
    end
    frame:Show()
    S:RefreshCurrentModuleScroll(false)
    return true
end

function S:SelectModule(module)
    if not module then return end
    if self.Search and not self.Search.opening and selectedModule ~= module then self.Search:CancelLocation() end
    if IsModuleNavToggleDisabled(module) then
        if selectedModule == module then
            ShowNavToggleDisabledContent(module)
        end
        return false
    end

    if selectedModule ~= module then
        S:ClearRightPreview()
        S:CloseSpecMultiSelectDropdown()
    end
    HideInactiveModuleFrames(module)
    HideNavToggleDisabledContent()

    selectedModule = module
    S:RefreshNav()
    
    if not Elements.scrollChild then
        return
    end

    if not module.frame then
        local container = GUI2:CreateFrame(Elements.scrollChild)
        container:SetSize(Elements.scrollChild:GetWidth(), Elements.scrollChild:GetHeight())
        container:SetPoint("TOPLEFT", 0, 0)
        
        if module.render then
            local success, err = pcall(module.render, container)
            if not success then
                print("|cffff0000YUI Module Error:|r " .. (module.name or "Unknown") .. " - " .. err)
            end
        end
        
        module.frame = container
    end
    
    module.frame:Show()
    QueueGUI2PixelRefresh()
    S:RefreshCurrentModuleScroll(true)
end


if YUI.Event and YUI.Event.On then
    local function RefreshScreenScale()
        if Elements.frame then S:SetWindowScale(S:GetWindowScale()) end
    end
    YUI.Event:On("UI_SCALE_CHANGED", RefreshScreenScale, S, { moduleId = "settings.core" })
    YUI.Event:On("DISPLAY_SIZE_CHANGED", RefreshScreenScale, S, { moduleId = "settings.core" })
    YUI.Event:On("YUI_EXTERNAL_STATE_CHANGED", function()
        S:RefreshSelectedModule()
    end, S, { moduleId = "settings.core", traceName = "Settings:ExternalStateChanged" })
    YUI.Event:On("YUI_LAYOUT_EDIT_MODE_OPENED", RefreshEditModeButton, S, { moduleId = "settings.core" })
    YUI.Event:On("YUI_LAYOUT_EDIT_MODE_CLOSED", RefreshEditModeButton, S, { moduleId = "settings.core" })
    YUI.Event:On("PLAYER_REGEN_DISABLED", function()
        S:CloseForCombat()
    end, S, { moduleId = "settings.core", traceName = "Settings:CloseForCombat" })
    YUI.Event:On("YUI_MODULE_ENABLED", function()
        if Elements.navButtons then
            S:RefreshNav()
        end
        RefreshHeaderActions()
    end, S, { moduleId = "settings.core" })
    YUI.Event:On("YUI_MODULE_DISABLED", function()
        if Elements.navButtons then
            S:RefreshNav()
        end
        RefreshHeaderActions()
    end, S, { moduleId = "settings.core" })
end

-- 配置模块显示顺序
if S then
    S.ModuleOrder = {
        "suite.settings.general",
        "ybar.settings",
        "yactionbar.settings",
        "yunitframes.settings",
        "yhud.settings",
        "yhud.settings.sound",
        "ymap.settings",
        "suite.settings.sound",
        "settings.appearance",
        "suite.settings.native_interface",
        "suite.插件清单",
        "suite.常见问题",
        "core.profiles",
        "core.credits",
    }
end
