local YUI = _G.YUI
local B = YUI and YUI.YBags
if not B then return end
local Skins = YUI.GUI2.IconSkins
local windowSkins = {"native", "minimal"}
local function NormalizeIconSkin(style, windowSkin)
    if type(style) ~= "table" then return nil end
    local id = style.skinId
    if id ~= "native" and (type(id) ~= "string" or not Skins.definitions[id]) then return nil end
    if style.skinOptions ~= nil and type(style.skinOptions) ~= "table" then return nil end
    local options = Skins:NormalizeOptions(style.skinOptions or {})
    if not options then return nil end
    for _, shapeID in ipairs(Skins.order) do
        local values = options[shapeID] or {}
        if values.zoom == nil then values.zoom = 0.03 end
        options[shapeID] = values
    end
    if windowSkin == "minimal" and id ~= "native" then
        local values = options[id]
        if values.border == nil then values.border = "contour" end
    end
    return { skinId = id, skinOptions = options }
end
local defaultIconSkins = {
    native = NormalizeIconSkin({ skinId = "native" }, "native"),
    minimal = NormalizeIconSkin({ skinId = "minimal-rounded" }, "minimal"),
}
local bankViewDefaults = {
    layout = "category", autoSize = false, columns = 16, slotSize = 36,
    showSubnames = true, emptyMode = "all",
}

local function IsBankViewOptionValid(key, value)
    if key == "layout" then return value == "category" or value == "single" end
    if key == "emptyMode" then return value == "all" or value == "one" end
    if key == "autoSize" or key == "showSubnames" then return type(value) == "boolean" end
    if key == "columns" or key == "slotSize" then
        local min, max = 6, 24
        if key == "slotSize" then min, max = 30, 48 end
        return type(value) == "number" and value >= min and value <= max and value == math.floor(value)
    end
    return false
end

B.Defaults = {
    enabled = false, schema = 1, layout = "category", skin = "native", slotSize = 36, columns = 12,
    autoSize = true, showSubnames = true, aggregateItems = true, emptyMode = "all", opacity = 1,
    itemFont = "default", itemTextScale = 100, tintUnusableRecipes = true, tintKnownRecipes = true,
    favorites = {}, locks = {}, manual = {}, tracked = {}, position = {}, collapsed = {}, rules = {}, iconSkins = {},
    deposit = {
        bank = { mode = "materials", keep = 0, exclude = "" },
        shared = { mode = "materials", keep = 0, exclude = "" },
        guild = { mode = "existing", keep = 20, exclude = "" },
    },
}
if B.client == "forever" then
    B.Defaults.combinedSortDirection = "forward"
    B.Defaults.combinedWrapSpecialBags = true
    B.Defaults.tracked = {{kind="currency", id=3402}, {kind="currency", id=515}}
    B.Defaults.bankView = bankViewDefaults
    B.Defaults.guildView = {slotSize=B.Defaults.slotSize, showSubnames=B.Defaults.showSubnames}
end

local function IsGuildViewOptionValid(key, value)
    return (key == "slotSize" or key == "showSubnames") and IsBankViewOptionValid(key, value)
end

local function Defaults(target, source)
    for key, value in pairs(source) do
        if target[key] == nil then target[key] = B:Copy(value)
        elseif type(value) == "table" and type(target[key]) ~= "table" then target[key] = B:Copy(value)
        -- A saved tracking list owns its order and may intentionally be empty.
        elseif type(value) == "table" and key ~= "tracked" then Defaults(target[key], value) end
    end
end
function B:GetConfig()
    if self.config then return self.config end
    local profile = YUI.DB:GetProfile(self.HOST_ID)
    if type(profile) ~= "table" then return nil end
    if type(profile.YBags) ~= "table" then profile.YBags = {} end
    local config = profile.YBags
    config.slotSize = math.max(30, math.min(48, tonumber(config.slotSize) or self.Defaults.slotSize))
    if self.Defaults.guildView then
        -- Inherit the old effective bag settings before recursive defaults can
        -- fill missing guild fields. Persist both values, including false.
        local guild = type(config.guildView) == "table" and config.guildView or {}
        for key, value in pairs(guild) do
            if not IsGuildViewOptionValid(key, value) then guild[key] = nil end
        end
        if guild.slotSize == nil then guild.slotSize = math.floor(config.slotSize + .5) end
        if guild.showSubnames == nil and type(config.showSubnames) == "boolean" then guild.showSubnames = config.showSubnames end
        config.guildView = guild
    end
    Defaults(config, self.Defaults)
    config.schema = 1
    config.columns = math.max(6, math.min(24, tonumber(config.columns) or 12))
    config.opacity = math.max(.6, math.min(1, tonumber(config.opacity) or 1))
    local textScale = tonumber(config.itemTextScale)
    config.itemTextScale = textScale and textScale == textScale and math.max(80, math.min(130, math.floor(textScale + .5))) or 100
    if type(config.itemFont) ~= "string" or config.itemFont == "" or #config.itemFont > 128 then config.itemFont = "default" end
    config.skin = config.skin == "minimal" and "minimal" or "native"
    for _, skin in ipairs(windowSkins) do
        config.iconSkins[skin] = NormalizeIconSkin(config.iconSkins[skin], skin)
    end
    config.layout = config.layout == "single" and "single" or "category"
    config.emptyMode = config.emptyMode == "one" and "one" or "all"
    if self.client == "forever" then
        config.combinedSortDirection = config.combinedSortDirection == "reverse" and "reverse" or "forward"
        if type(config.combinedWrapSpecialBags) ~= "boolean" then
            config.combinedWrapSpecialBags = self.Defaults.combinedWrapSpecialBags
        end
    end
    if self.Defaults.bankView then
        for key, value in pairs(config.bankView) do
            if not IsBankViewOptionValid(key, value) then config.bankView[key] = bankViewDefaults[key] end
        end
    end
    self.config = config
    return config
end

local function RefreshBankWindows(self, kind, resetLayout, refresh)
    local view = self.View
    if not view then return end
    for _, window in pairs(view.windows) do
        if window.liveBank == kind or (window.owner and window.kind == kind) then
            if resetLayout then window.layout = nil end
            window.cols = 0
            if refresh and self.active and window.open then view:Layout(window, true) end
        end
    end
end

function B:SetBankViewOption(key, value)
    local bankView = self.Defaults.bankView and self:GetConfig().bankView
    if not bankView or not IsBankViewOptionValid(key, value) or bankView[key] == value then return end
    bankView[key] = value
    RefreshBankWindows(self, "bank", key == "layout", true)
end

function B:SetGuildViewOption(key, value)
    if not self.Defaults.guildView or not IsGuildViewOptionValid(key, value) then return false end
    local config = self:GetConfig()
    if not config or config.guildView[key] == value then return false end
    config.guildView[key] = value
    RefreshBankWindows(self, "guild", false, true)
    return true
end

function B:GetDefaultItemFont()
    local media=YUI.LSM or (LibStub and LibStub("LibSharedMedia-3.0",true))
    return media and media.GetDefault and media:GetDefault("font") or "default"
end
function B:GetIconSkin()
    local config = self:GetConfig()
    return config.iconSkins[config.skin] or defaultIconSkins[config.skin]
end
function B:SetIconSkin(style)
    local config = self:GetConfig()
    local normalized = NormalizeIconSkin(style, config.skin)
    if not normalized then return false end
    config.iconSkins[config.skin] = normalized
    self.Appearance:RefreshIconStyle()
    return true
end
function B:GetCacheDB()
    local global = YUI.DB:GetGlobal(self.HOST_ID)
    if type(global) ~= "table" then return nil end
    if type(global.YBags) ~= "table" then global.YBags = {} end
    local db = global.YBags
    Defaults(db, { schema = 1, characters = {}, shared = {}, guilds = {}, peers = {} })
    return db
end
function B:IsEnabled()
    local config = self:GetConfig()
    return config and config.enabled == true or false
end
function B:SetEnabled(enabled, lifecycle)
    local config = self:GetConfig()
    if not config then return false end
    config.enabled = enabled == true
    if not lifecycle then return YUI.Module:SetEnabled(self.PRODUCT_ID, enabled == true) end
    return true
end
function B:ConfigChanged(layout)
    if not self.active then return end
    self.Actions:CancelSortForConfigChange()
    self:InvalidateSortSpace()
    self.Model:Reclassify()
    if layout ~= false and self.View then self.View:Invalidate() end
    self:RefreshVisible()
end
function B:ExportConfig()
    local library = LibStub and LibStub("AceSerializer-3.0", true)
    if not library then return nil end
    return "!YUI-YBags-1:" .. library:Serialize({ schema = 1, client = self.client, config = self:GetConfig() })
end
function B:ImportConfig(text)
    local library = LibStub and LibStub("AceSerializer-3.0", true)
    if not library or type(text) ~= "string" or #text > 131072 or text:sub(1, 13) ~= "!YUI-YBags-1:" then return false end
    local ok, value = library:Deserialize(text:sub(14))
    if not ok or type(value) ~= "table" or value.schema ~= 1 or value.client ~= self.client or type(value.config) ~= "table" then return false end
    local source,valid=self:Plain(value.config)
    if not valid or not self:ValidateConfig(source) then return false end
    local target=self:GetConfig()
    if self.Defaults.bankView and source.bankView and source.bankView.columns == nil then
        source.bankView.columns = target.bankView.columns
    end
    local guildChanged, otherOptions = false, false
    for key in pairs(self.Defaults) do
        if key == "guildView" and source.guildView then
            for option, setting in pairs(source.guildView) do
                if target.guildView[option] ~= setting then
                    target.guildView[option] = setting
                    guildChanged = true
                end
            end
        elseif key ~= "enabled" and key ~= "position" and type(source[key]) == type(self.Defaults[key]) then
            target[key] = self:Copy(source[key])
            otherOptions = true
        end
    end
    if not otherOptions and self.Defaults.guildView and source.guildView then
        if guildChanged then RefreshBankWindows(self, "guild", false, true) end
        return true
    end
    self.config = nil
    self:GetConfig()
    self.Diagnostics:NoteConfig("bag-import")
    if self.Defaults.bankView and source.bankView then RefreshBankWindows(self, "bank", true, false) end
    if self.active then self.View:ApplySkin(true) end
    self:ConfigChanged()
    return true
end
function B:ValidateConfig(source)
    if self.client == "forever" then
        local direction, wrap = source.combinedSortDirection, source.combinedWrapSpecialBags
        if direction ~= nil and direction ~= "forward" and direction ~= "reverse" then return false end
        if wrap ~= nil and type(wrap) ~= "boolean" then return false end
    end
    if self.Defaults.guildView and source.guildView ~= nil then
        if type(source.guildView) ~= "table" then return false end
        for key, value in pairs(source.guildView) do
            if not IsGuildViewOptionValid(key, value) then return false end
        end
    end
    if self.Defaults.bankView and source.bankView ~= nil then
        if type(source.bankView) ~= "table" then return false end
        for key, value in pairs(source.bankView) do
            if not IsBankViewOptionValid(key, value) then return false end
        end
    end
    if source.iconSkins ~= nil then
        if type(source.iconSkins) ~= "table" then return false end
        for skin, style in pairs(source.iconSkins) do
            if not defaultIconSkins[skin] or not NormalizeIconSkin(style, skin) then return false end
        end
    end
    for _,key in ipairs({"slotSize","columns","opacity","itemTextScale"}) do
        local value=source[key]
        if value~=nil and (type(value)~="number" or value~=value) then return false end
    end
    if source.itemFont ~= nil and (type(source.itemFont) ~= "string" or #source.itemFont > 128) then return false end
    for _,key in ipairs({"favorites","locks","manual"}) do
        if source[key]~=nil then
            if type(source[key])~="table" then return false end
            for id,value in pairs(source[key]) do
                if type(id)~="string" or #id>80 or (key=="manual" and type(value)~="string" or key~="manual" and type(value)~="boolean") then return false end
            end
        end
    end
    if source.tracked then
        if type(source.tracked)~="table" or #source.tracked>100 then return false end
        for _,entry in pairs(source.tracked) do
            if type(entry)~="table" or entry.kind~="currency" and entry.kind~="item" or type(entry.id)~="number" or entry.id<1 or entry.id~=math.floor(entry.id) then return false end
        end
    end
    if source.rules then
        if type(source.rules)~="table" or #source.rules>100 then return false end
        local sections={general=true,consumable=true,equipment=true,material=true,system=true,other=true}
        local ids={}
        for _,rule in pairs(source.rules) do
            if type(rule)~="table" or type(rule.id)~="string" or #rule.id>80 or ids[rule.id] or not sections[rule.section] then return false end
            ids[rule.id]=true
            for _,key in ipairs({"name","contains","exclude","equipLoc"}) do if rule[key]~=nil and (type(rule[key])~="string" or #rule[key]>1024) then return false end end
            for _,key in ipairs({"priority","order","minLevel","quality","classID"}) do if rule[key]~=nil and type(rule[key])~="number" then return false end end
        end
    end
    if source.deposit then
        if type(source.deposit)~="table" then return false end
        for _,kind in ipairs({"bank","shared","guild"}) do
            local rule=source.deposit[kind]
            if rule then
                if type(rule)~="table" or rule.mode~="materials" and rule.mode~="existing" and rule.mode~="custom"
                    or type(rule.keep)~="number" or rule.keep<0 or rule.keep>100000
                    or rule.contains~=nil and type(rule.contains)~="string" or rule.exclude~=nil and type(rule.exclude)~="string"
                    or rule.classID~=nil and type(rule.classID)~="number" then return false end
            end
        end
    end
    return true
end
