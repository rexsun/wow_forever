local YUI = _G.YUI
local YBar = YUI.YBar
local Module = YBar.Module:New("BugSack")
local L = YUI.Locale:Get("YBar")
local LC = YUI.Locale:Get("Core")
local LSM = LibStub("LibSharedMedia-3.0")

local DATA_OBJECT_NAME = "BugSack"
local ATTRIBUTE_EVENT = "LibDataBroker_AttributeChanged_BugSack"
local DEFAULT_ICON = "Interface\\AddOns\\BugSack\\Media\\icon"
local DEFAULT_FONT = STANDARD_TEXT_FONT
local DEFAULT_SIZE = 14
local ICON_TEXT_GAP = 4
local HORIZONTAL_PADDING = 2

local RegistrationOwner = {}

local function IsFontPath(value)
    return type(value) == "string" and (value:find("\\", 1, true) or value:find("/", 1, true)) ~= nil
end

local function GetFontSettingValue(value)
    if not IsFontPath(value) then
        return value
    end

    local fontList = LSM:HashTable("font") or {}
    for name, path in pairs(fontList) do
        if path == value then
            return name
        end
    end
    return value
end

local function GetLegacyFontOptions(value)
    if not IsFontPath(value) or GetFontSettingValue(value) ~= value then
        return nil
    end
    return {
        {
            text = value,
            value = value,
            fontPath = value,
        },
    }
end

local function NormalizeFontFlags(flags)
    return type(flags) == "string" and flags or ""
end

local function TrySetFont(text, font, size, flags)
    if not text or type(text.SetFont) ~= "function" then return false end
    local ok, applied = pcall(text.SetFont, text, font, size, flags)
    return ok and applied ~= false
end

local function EnsureModuleDB(self)
    local ybarDB = YBar.GetModuleRoot and YBar:GetModuleRoot("BugSack") or (YBar.EnsureDB and YBar:EnsureDB())
    if type(ybarDB) ~= "table" then return nil, nil end

    if type(ybarDB.BugSack) ~= "table" then
        ybarDB.BugSack = {}
    end
    local db = ybarDB.BugSack
    if db.font == nil then db.font = DEFAULT_FONT end
    if db.size == nil then db.size = DEFAULT_SIZE end
    if db.iconBackground == nil then db.iconBackground = true end
    self.db = db
    return db, ybarDB
end

local function ResolveProvider()
    local addon = _G.BugSack
    local libStubType = type(LibStub)
    if type(addon) ~= "table" or addon.healthCheck ~= true or (libStubType ~= "table" and libStubType ~= "function") then
        return nil, nil
    end

    local ok, ldb = pcall(function()
        return LibStub("LibDataBroker-1.1", true)
    end)
    if not ok or type(ldb) ~= "table" or type(ldb.GetDataObjectByName) ~= "function" then
        return nil, nil
    end

    local provider = ldb:GetDataObjectByName(DATA_OBJECT_NAME)
    if type(provider) ~= "table" or type(provider.OnClick) ~= "function" or type(provider.OnTooltipShow) ~= "function" then
        return nil, nil
    end

    return ldb, provider
end

local function IsFrameReady(frame)
    return not Module._hasError and frame and not frame.ybarErrorPlaceholder and frame.text and frame.icon
end

function Module:RefreshProvider()
    local ldb, provider = ResolveProvider()
    if not provider then return false end

    self.ldb = ldb
    self.provider = provider
    return true
end

function Module:OnInitialize()
    EnsureModuleDB(self)
end

function Module:RefreshWidth(requestLayout)
    local frame = self.frame
    if not IsFrameReady(frame) then return false end

    local db = EnsureModuleDB(self)
    if not db then return false end

    local text = tostring(self.displayText or self.provider and self.provider.text or "0")
    local size = tonumber(db.size) or DEFAULT_SIZE
    local iconSize = size + 2
    local textWidth = frame.text:GetStringWidth() or 0
    if textWidth <= 0 then
        textWidth = #text * size * 0.6
    end

    local width = math.ceil(iconSize + ICON_TEXT_GAP + textWidth + HORIZONTAL_PADDING)
    local oldWidth = self.width
    self.width = width
    local widthChanged = not oldWidth or math.abs(width - oldWidth) > 0.5
    if widthChanged then
        frame:SetWidth(width)
    end

    if requestLayout and oldWidth and widthChanged and YBar.UpdateLayout then
        YBar:UpdateLayout()
    end
    return widthChanged
end

function Module:RefreshProviderDisplay(requestLayout, deferWidth)
    local frame = self.frame
    local provider = self.provider
    if not IsFrameReady(frame) or type(provider) ~= "table" then return false end

    local text = tostring(provider.text or "0")
    local icon = provider.icon or DEFAULT_ICON
    local changed = false
    local iconChanged = false

    if self.displayText ~= text then
        self.displayText = text
        frame.text:SetText(text)
        changed = true
    end

    if self.displayIcon ~= icon then
        self.displayIcon = icon
        iconChanged = true
        if frame.iconSlot then
            YBar:SetIconSlotTexture(frame.iconSlot, icon)
        else
            frame.icon:SetTexture(icon)
        end
        changed = true
    end

    if iconChanged then
        local db = EnsureModuleDB(self)
        if frame.iconSlot and db and db.iconBackground == false then
            YBar:SetIconSlotChromeVisible(frame.iconSlot, false)
        end
    end

    if not changed then return false end
    if not deferWidth then
        self:RefreshWidth(requestLayout)
    end
    return true
end

function Module:RefreshAppearance(requestLayout, forceFont, deferWidth)
    local frame = self.frame
    if not IsFrameReady(frame) then return false end

    local db, ybarDB = EnsureModuleDB(self)
    if not db then return false end

    local size = tonumber(db.size) or DEFAULT_SIZE
    local iconSize = size + 2
    local font = YBar:ResolveFontPath(db.font, DEFAULT_FONT, LSM)
    local fontFlag = ybarDB.fontFlags or (ybarDB.fontOutline and "OUTLINE" or "")
    local fontShadow = ybarDB.fontShadow == true
    local iconBackground = db.iconBackground ~= false
    local changed = false

    local currentFont, currentSize, currentFlag
    if type(frame.text.GetFont) == "function" then
        currentFont, currentSize, currentFlag = frame.text:GetFont()
    end
    currentFlag = NormalizeFontFlags(currentFlag)
    local actualFontKnown = type(currentFont) == "string" and currentFont ~= ""
    local actualFontMatches = actualFontKnown
        and currentFont == font
        and math.abs((tonumber(currentSize) or 0) - size) <= 0.01
        and currentFlag == fontFlag
    local cachedFontMatches = self.displayFont == font
        and self.displaySize == size
        and self.displayFontFlag == fontFlag

    if forceFont or (actualFontKnown and not actualFontMatches) or (not actualFontKnown and not cachedFontMatches) then
        local appliedFont = font
        local applied = TrySetFont(frame.text, font, size, fontFlag)
        if not applied and font ~= DEFAULT_FONT then
            appliedFont = DEFAULT_FONT
            applied = TrySetFont(frame.text, appliedFont, size, fontFlag)
        end

        if applied then
            self.displayFont = appliedFont
            self.displaySize = size
            self.displayFontFlag = fontFlag
            changed = true
        else
            self.displayFont = nil
            self.displaySize = nil
            self.displayFontFlag = nil
        end
    elseif actualFontMatches then
        self.displayFont = font
        self.displaySize = size
        self.displayFontFlag = fontFlag
    end

    if self.displayFontShadow ~= fontShadow then
        self.displayFontShadow = fontShadow
        if fontShadow then
            frame.text:SetShadowColor(0, 0, 0, 1)
            frame.text:SetShadowOffset(1, -1)
        else
            frame.text:SetShadowOffset(0, 0)
        end
        changed = true
    end

    if self.displayIconSize ~= iconSize then
        self.displayIconSize = iconSize
        if frame.iconSlot then
            frame.iconSlot:SetSize(iconSize, iconSize)
        else
            frame.icon:SetSize(iconSize, iconSize)
        end
        changed = true
    end

    if frame.iconSlot and self.displayIconBackground ~= iconBackground then
        self.displayIconBackground = iconBackground
        YBar:SetIconSlotChromeVisible(frame.iconSlot, iconBackground)
        changed = true
    end

    if changed and not deferWidth then
        self:RefreshWidth(requestLayout)
    end
    return changed
end

function Module:RefreshDisplay(requestLayout, forceFont)
    local appearanceChanged = self:RefreshAppearance(false, forceFont, true)
    local providerChanged = self:RefreshProviderDisplay(false, true)
    if appearanceChanged or providerChanged then
        self:RefreshWidth(requestLayout)
        return true
    end
    return false
end

function Module:OnLDBAttributeChanged(_, name, attribute, _, provider)
    if name ~= DATA_OBJECT_NAME or (attribute ~= "text" and attribute ~= "icon") then return end
    if type(provider) == "table" then
        self.provider = provider
    end
    self:RefreshProviderDisplay(true)
end

function Module:AttachRuntime()
    if not IsFrameReady(self.frame) or not self:RefreshProvider() then return end

    if not self.ldbCallbackRegistered and type(self.ldb.RegisterCallback) == "function" then
        self.ldb.RegisterCallback(self, ATTRIBUTE_EVENT, "OnLDBAttributeChanged")
        self.ldbCallbackRegistered = true
    end
    self:RefreshProviderDisplay(false)
end

function Module:DetachRuntime()
    if self.ldbCallbackRegistered and self.ldb and type(self.ldb.UnregisterCallback) == "function" then
        self.ldb.UnregisterCallback(self, ATTRIBUTE_EVENT)
    end
    self.ldbCallbackRegistered = false

    if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == self.frame then
        YUI.HideGameTooltip()
    end
end

function Module:OnEnter(frame)
    if not IsFrameReady(frame) then return end

    if YBar.OnModuleEnter then YBar:OnModuleEnter(frame) end
    YBar:SetThemedTextAccent(frame.text)

    local provider = self.provider
    if not GameTooltip or type(provider) ~= "table" or type(provider.OnTooltipShow) ~= "function" then return end

    local anchor = "ANCHOR_TOP"
    local bar = self.parent
    if bar and bar.GetBottom and bar:GetBottom() > GetScreenHeight() / 2 then
        anchor = "ANCHOR_BOTTOM"
    end

    GameTooltip:SetOwner(frame, anchor)
    GameTooltip:ClearLines()
    local ok = pcall(provider.OnTooltipShow, GameTooltip)
    if ok then
        GameTooltip:Show()
    else
        YUI.HideGameTooltip()
    end
end

function Module:OnLeave(frame)
    if YBar.OnModuleLeave then YBar:OnModuleLeave(frame) end
    if frame and frame.text then
        YBar:RestoreThemedTextColor(frame.text, "color.ybar.text")
    end
    YUI.HideGameTooltip()
end

function Module:OnClick(frame, button)
    local provider = self.provider
    if type(provider) == "table" and type(provider.OnClick) == "function" then
        pcall(provider.OnClick, frame, button)
    end
end

function Module:CreateBarItem(parent)
    local frame = YBar:CreateBarItem(parent, {
        variant = "bare",
        width = 28,
        height = 20,
        clickable = true,
        hoverable = true,
        showIcon = false,
        hoverIcon = false,
        text = false,
        value = false,
    })

    frame.iconSlot, frame.icon = YBar:CreateIconSlot(frame, {
        size = DEFAULT_SIZE + 2,
        icon = DEFAULT_ICON,
        shape = "square",
        padding = 0,
    })
    local iconAnchor = frame.iconSlot or frame.icon
    iconAnchor:SetPoint("LEFT", frame, "LEFT", 0, 0)

    frame.statusText, frame.text = YBar:CreateStatusText(frame, {
        variant = "single",
        value = "0",
        width = 24,
        height = 20,
        justifyH = "LEFT",
        fontSizeKey = "font.size.md",
        colorKey = "color.ybar.text",
    })
    frame.text:ClearAllPoints()
    frame.text:SetPoint("LEFT", iconAnchor, "RIGHT", ICON_TEXT_GAP, 0)
    YBar:RegisterBarItemHoverText(frame, frame.text)

    frame:RegisterForClicks("AnyUp")
    frame:SetScript("OnClick", function(owner, button)
        Module:OnClick(owner, button)
    end)
    frame:SetScript("OnEnter", function(owner)
        Module:OnEnter(owner)
    end)
    frame:SetScript("OnLeave", function(owner)
        Module:OnLeave(owner)
    end)

    self.frame = frame
    self.parent = parent
    self:RefreshDisplay(false, true)

    if YBar.IsSubModuleEnabled and YBar:IsSubModuleEnabled(self.name) then
        self:AttachRuntime()
    end
    return frame
end

function Module:GetOptions()
    return {
        {
            type = "font",
            label = LC["common.font"],
            width = 220,
            default = GetFontSettingValue(DEFAULT_FONT),
            options = function()
                local db = EnsureModuleDB(self)
                return GetLegacyFontOptions(db and db.font)
            end,
            get = function()
                local db = EnsureModuleDB(self)
                return GetFontSettingValue(db and db.font or DEFAULT_FONT)
            end,
            set = function(value)
                local db = EnsureModuleDB(self)
                if not db then return end
                db.font = value
                self:RefreshAppearance(true, true)
            end,
        },
        {
            type = "slider",
            label = LC["common.size"],
            width = 220,
            min = 10,
            max = 32,
            step = 1,
            default = DEFAULT_SIZE,
            get = function()
                local db = EnsureModuleDB(self)
                return db and db.size or DEFAULT_SIZE
            end,
            set = function(value)
                local db = EnsureModuleDB(self)
                if not db then return end
                db.size = tonumber(value) or DEFAULT_SIZE
                self:RefreshAppearance(true, true)
            end,
        },
        {
            type = "checkbox",
            label = L["bugsack.option.icon_background"],
            default = true,
            get = function()
                local db = EnsureModuleDB(self)
                return not db or db.iconBackground ~= false
            end,
            set = function(value)
                local db = EnsureModuleDB(self)
                if not db then return end
                db.iconBackground = value ~= false
                self:RefreshAppearance(false, false)
            end,
        },
    }
end

function Module:UpdateBarItem(frame, parent)
    if frame then self.frame = frame end
    if parent then self.parent = parent end
    self:RefreshDisplay(false, false)
end

function Module:Update()
    self:RefreshDisplay(false, false)
end

function Module:GetWidth()
    return self.width or 28
end

local function TryRegisterModule()
    if Module.registered then return true end
    if not Module:RefreshProvider() then return false end

    Module.registered = true
    YBar:RegisterModule(Module, {
        id = "ybar.bugsack",
        parent = "ybar",
        product = "ybar",
        scope = "ybar",
        dependencies = {"ybar", "core.event"},
        defaultEnabled = true,
    })

    if YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(RegistrationOwner)
    end
    if YBar.frame and YBar.UpdateLayout then
        YBar:UpdateLayout()
    end
    return true
end

function RegistrationOwner:OnAddonLoaded(_, addonName)
    if addonName == DATA_OBJECT_NAME then
        TryRegisterModule()
    end
end

if not TryRegisterModule() and YUI.Event and YUI.Event.On then
    YUI.Event:On("ADDON_LOADED", "OnAddonLoaded", RegistrationOwner, {
        moduleId = "ybar.bugsack.registration",
        traceName = "YBar:BugSack:ADDON_LOADED",
    })
end
