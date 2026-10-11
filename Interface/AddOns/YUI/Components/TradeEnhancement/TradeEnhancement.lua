local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI or not YUI.Components then return end
local Components = YUI.Components
local Social = (YUI.API and YUI.API.Social) or YUI.WOW_API or {}
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or YUI.ProductId or "suite"
local LC = YUI.Locale:Get("Core")

local TRADE_MSG_TMPL = "[YUI] 交易<%s>%s%s%s"
local CONFIG_KEY = "TradeEnhancement_Config"
local MERCHANT_NATIVE_ITEMS_PER_PAGE = 10
local MERCHANT_NATIVE_BUYBACK_ITEMS_PER_PAGE = 12
local MERCHANT_EXPANDED_ITEMS_PER_PAGE = 20
local MERCHANT_RETAIL_BASE_WIDTH = 336
local MERCHANT_WRATH_BASE_WIDTH = 384
local MERCHANT_EXTERNAL_WIDTH_PADDING = 120
local DELETE_CONFIRM_POPUPS = { "DELETE_GOOD_ITEM", "DELETE_GOOD_QUEST_ITEM", "DELETE_QUEST_ITEM" }
local BATCH_BUY_DEFAULT_MAX_QUANTITY = 999
local BATCH_BUY_DEFAULT_PRICE_WARNING_GOLD = 10000
local BATCH_BUY_UNSTACKABLE_FALLBACK_STACK = 20
local BATCH_BUY_BUTTON_VALUES = { "stack", 50, 100, 500 }
local BATCH_BUY_QUEUE_INTERVAL = 0.15
local BATCH_BUY_CURRENCY_QUEUE_INTERVAL = 0.5
local BATCH_BUY_NORMAL_CHUNK_LIMIT = 500
local BATCH_BUY_FRAME_WIDTH = 260
local BATCH_BUY_FRAME_HEIGHT = 254
local BATCH_BUY_FRAME_PADDING = 16
local BATCH_BUY_ICON_SIZE = 44
local BATCH_BUY_CONTROL_HEIGHT = 26
local BATCH_BUY_SMALL_BUTTON_WIDTH = 28
local BATCH_BUY_QUANTITY_INPUT_WIDTH = 156
local BATCH_BUY_STEP_BUTTON_WIDTH = 104
local BATCH_BUY_COLUMN_GAP = 16
local BATCH_BUY_ROW_GAP = 8
local BATCH_BUY_CONTENT_TOP = 12
local BATCH_BUY_ANCHOR_GAP = 10
local COPPER_PER_GOLD = 10000
local KnownItems = {
    defaultColor = { 0.50, 0.95, 0.62 },
    cacheTrue = 1,
    cacheFalse = 0,
    cache = {},
}

local isFeatureEnabled = false
local defaults = {
    tradeWhisper = true,
    autoBag = true,
    merchantFrame = true,
    knownItemTint = true,
    knownItemColor = KnownItems.defaultColor,
    autoDelete = true,
    autoSellJunk = true,
    batchBuy = true,
    batchBuyMaxQuantity = BATCH_BUY_DEFAULT_MAX_QUANTITY,
    batchBuyPriceWarningGold = BATCH_BUY_DEFAULT_PRICE_WARNING_GOLD,
}

local merchantHooksInstalled = false
local merchantFrameApplied = false
local merchantRefreshScheduled = false
local autoDeleteScheduled = false
local batchBuyHooksInstalled = false
local batchBuyControls
local batchBuyContext
local batchBuyQueue
local batchBuyQueueFrame
local batchBuyFrameEventOwner = {
    traceName = "TradeEnhancement.BatchBuyFrame",
    appearance = {},
}
local merchantItemButtonOnModifiedClickOriginal

YUI.Trade = YUI.Trade or {}
YUI.Trade.Record = YUI.Trade.Record or {}

local function T(key)
    return LC[key] or key
end

local function GetDB()
    if Components and Components.EnsureConfig then
        return Components:EnsureConfig(CONFIG_KEY, defaults, PRODUCT_ID) or defaults
    end
    return defaults
end

local function IsOptionEnabled(key)
    if not isFeatureEnabled then
        return false
    end

    local db = GetDB()
    return db[key] == true
end

local function IsMerchantFrameSupported()
    return YUI.IsRetail or YUI.IsWrath or YUI.IsForever
end

function KnownItems:IsEnabled()
    if YUI.IsForever then return false end
    if not isFeatureEnabled or not IsMerchantFrameSupported() then
        return false
    end
    return GetDB().knownItemTint == true
end

function KnownItems:ClampColorChannel(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

function KnownItems:GetColor()
    local color = GetDB().knownItemColor
    if type(color) ~= "table" then
        color = self.defaultColor
    end
    return self:ClampColorChannel(color[1] or color.r, self.defaultColor[1]),
        self:ClampColorChannel(color[2] or color.g, self.defaultColor[2]),
        self:ClampColorChannel(color[3] or color.b, self.defaultColor[3])
end

function KnownItems:CopyColor(color)
    color = type(color) == "table" and color or self.defaultColor
    return {
        self:ClampColorChannel(color[1] or color.r, self.defaultColor[1]),
        self:ClampColorChannel(color[2] or color.g, self.defaultColor[2]),
        self:ClampColorChannel(color[3] or color.b, self.defaultColor[3]),
    }
end

function KnownItems:InvalidateCache()
    wipe(self.cache)
end

local function ClampInteger(value, minValue, maxValue, fallback)
    local number = tonumber(value)
    if not number then
        number = fallback or minValue or 0
    end
    number = math.floor(number + 0.5)
    if minValue and number < minValue then
        number = minValue
    end
    if maxValue and number > maxValue then
        number = maxValue
    end
    return number
end

local function IsBatchBuyEnabled()
    if not isFeatureEnabled or not IsMerchantFrameSupported() then
        return false
    end

    local db = GetDB()
    return db.batchBuy == true
end

local function GetBatchBuyMaxQuantity()
    local db = GetDB()
    return ClampInteger(db.batchBuyMaxQuantity, 1, 9999, BATCH_BUY_DEFAULT_MAX_QUANTITY)
end

local function GetBatchBuyPriceWarningGold()
    local db = GetDB()
    return ClampInteger(db.batchBuyPriceWarningGold, 0, 100000, BATCH_BUY_DEFAULT_PRICE_WARNING_GOLD)
end

local function GetMerchantBaseWidth()
    if YUI.IsRetail or YUI.IsForever then
        return MERCHANT_RETAIL_BASE_WIDTH
    end

    return MERCHANT_WRATH_BASE_WIDTH
end

local function GetMerchantExpandedWidth()
    return GetMerchantBaseWidth() * 2
end

local function GetMerchantRightPanelX()
    return GetMerchantBaseWidth() + 6
end

local MerchantSkinCompat = {
    system = (YUI.API and YUI.API.System) or YUI.WOW_API or {},
    backgroundR = 0.08,
    backgroundG = 0.08,
    backgroundB = 0.08,
    backgroundA = 0.92,
    borderR = 0.20,
    borderG = 0.20,
    borderB = 0.20,
    qualityChroma = 0.10,
    skinStates = setmetatable({}, { __mode = "k" }),
    qualityBorders = setmetatable({}, { __mode = "k" }),
    currencyLiftStates = setmetatable({}, { __mode = "k" }),
    qualityGlobalHooked = false,
}

function MerchantSkinCompat:GetMode()
    local system = self.system
    if not (YUI.IsRetail or YUI.IsForever) or type(system.IsAddOnLoadedSafe) ~= "function" then
        return nil
    end

    local loadedOK, loaded = pcall(system.IsAddOnLoadedSafe, "EllesmereUIBlizzardSkin")
    if not loadedOK or loaded ~= true then
        return nil
    end

    local provider = _G.EllesmereUI
    if type(provider) ~= "table" then
        return nil
    end

    local getStyle = rawget(provider, "GetBlizzWindowStyle")
    if type(getStyle) ~= "function" then
        return nil
    end

    local styleOK, style = pcall(getStyle, "merchant")
    if not styleOK or (style ~= "eui" and style ~= "modern") then
        return nil
    end

    local db = _G.EllesmereUIDB
    if type(db) == "table" and rawget(db, "merchantShowAsList") == true then
        return "list", provider
    end
    return "grid", provider
end

local function IsExternalMerchantExpansionActive()
    local ellesmereMode = MerchantSkinCompat:GetMode()
    if ellesmereMode == "list" then
        return true
    end

    if merchantFrameApplied then
        return false
    end

    local pageSize = type(MERCHANT_ITEMS_PER_PAGE) == "number" and MERCHANT_ITEMS_PER_PAGE or MERCHANT_NATIVE_ITEMS_PER_PAGE
    if pageSize > MERCHANT_NATIVE_ITEMS_PER_PAGE then
        return true
    end

    if _G.MerchantItem13 then
        return true
    end

    if MerchantFrame and MerchantFrame.GetWidth then
        local width = MerchantFrame:GetWidth()
        if width and width > GetMerchantBaseWidth() + MERCHANT_EXTERNAL_WIDTH_PADDING then
            return true
        end
    end

    return false
end

local function IsMerchantFrameEnabled()
    if not isFeatureEnabled or not IsMerchantFrameSupported() then
        return false
    end

    local db = GetDB()
    if db.merchantFrame ~= true then
        return false
    end

    return not IsExternalMerchantExpansionActive()
end

local function IsMerchantFrameVisible()
    return MerchantFrame
        and type(MerchantFrame.IsShown) == "function"
        and MerchantFrame:IsShown()
end

local function ShowFrame(frame, show)
    if not frame then return end
    if show then
        frame:Show()
    else
        frame:Hide()
    end
end

local function GetMerchantItem(index)
    return _G["MerchantItem" .. index]
end

local function GetMerchantItemButton(index)
    return _G["MerchantItem" .. index .. "ItemButton"]
end

local function SafeCall(func, ...)
    if type(func) ~= "function" then
        return false
    end

    local ok = pcall(func, ...)
    return ok == true
end

local function SafeMethod(object, method, ...)
    if not object or type(method) ~= "string" then
        return false
    end

    local func = object[method]
    if type(func) ~= "function" then
        return false
    end

    return SafeCall(func, object, ...)
end

function MerchantSkinCompat.IsForbiddenObject(object)
    if not object or type(object.IsForbidden) ~= "function" then
        return false
    end

    local ok, forbidden = pcall(object.IsForbidden, object)
    return not ok or forbidden == true
end

function MerchantSkinCompat:GetProvider()
    local mode, provider = self:GetMode()
    if mode ~= "grid" or type(provider) ~= "table" then
        return nil
    end

    local pixelPerfect = rawget(provider, "PanelPP") or rawget(provider, "PP")
    if type(pixelPerfect) ~= "table"
        or type(rawget(pixelPerfect, "CreateBorder")) ~= "function"
        or type(rawget(pixelPerfect, "SetBorderColor")) ~= "function"
    then
        return nil
    end
    return pixelPerfect
end

local function GetElvUI()
    local ns = _G.ElvUI
    if type(ns) ~= "table" or type(unpack) ~= "function" then
        return nil
    end

    local ok, E = pcall(unpack, ns)
    if ok and type(E) == "table" then
        return E
    end

    return nil
end

local function GetNDui()
    local ns = _G.NDui or _G.NDUI
    if type(ns) ~= "table" or type(unpack) ~= "function" then
        return nil, nil
    end

    local ok, B, C = pcall(unpack, ns)
    if ok and type(B) == "table" then
        return B, C
    end

    return nil, nil
end

local function GetMerchantSkinReferenceIndex(index)
    local referenceIndex = index - 12
    if referenceIndex >= 1 and referenceIndex <= 12 then
        return referenceIndex
    end
    return 1
end

local function MapMerchantRelativeFrame(relativeTo, referenceIndex, targetIndex)
    if not relativeTo or type(relativeTo.GetName) ~= "function" then
        return relativeTo
    end

    local name = relativeTo:GetName()
    if type(name) ~= "string" then
        return relativeTo
    end

    local referencePrefix = "MerchantItem" .. referenceIndex
    if name == referencePrefix then
        return GetMerchantItem(targetIndex)
    end

    if name:sub(1, #referencePrefix) == referencePrefix then
        return _G["MerchantItem" .. targetIndex .. name:sub(#referencePrefix + 1)] or relativeTo
    end

    return relativeTo
end

local function CopyFrameSize(referenceFrame, targetFrame)
    if not referenceFrame or not targetFrame or not referenceFrame.GetSize or not targetFrame.SetSize then
        return
    end

    local width, height = referenceFrame:GetSize()
    if width and height and width > 0 and height > 0 then
        targetFrame:SetSize(width, height)
    end
end

local function CopyFramePoint(referenceFrame, targetFrame, referenceIndex, targetIndex)
    if not referenceFrame or not targetFrame or not referenceFrame.GetPoint or not targetFrame.SetPoint then
        return false
    end

    local point, relativeTo, relativePoint, x, y = referenceFrame:GetPoint(1)
    if not point then
        return false
    end

    if targetFrame.ClearAllPoints then
        targetFrame:ClearAllPoints()
    end
    local mappedRelativeTo = MapMerchantRelativeFrame(relativeTo, referenceIndex, targetIndex)
    if mappedRelativeTo then
        targetFrame:SetPoint(point, mappedRelativeTo, relativePoint or point, x or 0, y or 0)
    else
        targetFrame:SetPoint(point, x or 0, y or 0)
    end
    return true
end

local function CopyTextureCoords(referenceTexture, targetTexture)
    if not referenceTexture or not targetTexture or not referenceTexture.GetTexCoord or not targetTexture.SetTexCoord then
        return
    end

    targetTexture:SetTexCoord(referenceTexture:GetTexCoord())
end

local function GetMerchantSkinWidgets(index)
    local item = GetMerchantItem(index)
    local itemButton = (item and item.ItemButton) or GetMerchantItemButton(index)
    return item, itemButton, {
        icon = (itemButton and itemButton.icon) or _G["MerchantItem" .. index .. "ItemButtonIconTexture"],
        nameFrame = _G["MerchantItem" .. index .. "NameFrame"],
        name = (item and item.Name) or _G["MerchantItem" .. index .. "Name"],
        money = _G["MerchantItem" .. index .. "MoneyFrame"],
        altCurrency = _G["MerchantItem" .. index .. "AltCurrencyFrame"],
    }
end

local function SyncMerchantItemSkinLayout(index, syncCurrencyGeometry)
    local referenceIndex = GetMerchantSkinReferenceIndex(index)
    local referenceItem, referenceButton, reference = GetMerchantSkinWidgets(referenceIndex)
    local item, itemButton, widgets = GetMerchantSkinWidgets(index)
    if not referenceItem or not item then
        return false
    end

    CopyFrameSize(referenceItem, item)
    if referenceButton and itemButton then
        CopyFrameSize(referenceButton, itemButton)
        CopyFramePoint(referenceButton, itemButton, referenceIndex, index)
    end

    CopyFrameSize(reference.icon, widgets.icon)
    CopyFramePoint(reference.icon, widgets.icon, referenceIndex, index)
    CopyFrameSize(reference.nameFrame, widgets.nameFrame)
    CopyFramePoint(reference.nameFrame, widgets.nameFrame, referenceIndex, index)
    CopyFrameSize(reference.name, widgets.name)
    CopyFramePoint(reference.name, widgets.name, referenceIndex, index)
    if syncCurrencyGeometry ~= false then
        CopyFrameSize(reference.money, widgets.money)
        CopyFramePoint(reference.money, widgets.money, referenceIndex, index)
        CopyFrameSize(reference.altCurrency, widgets.altCurrency)
        CopyFramePoint(reference.altCurrency, widgets.altCurrency, referenceIndex, index)
    end
    CopyTextureCoords(reference.icon, widgets.icon)

    for j = 1, 3 do
        local referenceCurrency = _G["MerchantItem" .. referenceIndex .. "AltCurrencyFrameItem" .. j]
        local targetCurrency = _G["MerchantItem" .. index .. "AltCurrencyFrameItem" .. j]
        local referenceTexture = _G["MerchantItem" .. referenceIndex .. "AltCurrencyFrameItem" .. j .. "Texture"]
        local targetTexture = _G["MerchantItem" .. index .. "AltCurrencyFrameItem" .. j .. "Texture"]
        CopyFrameSize(referenceCurrency, targetCurrency)
        CopyFramePoint(referenceCurrency, targetCurrency, referenceIndex, index)
        CopyTextureCoords(referenceTexture, targetTexture)
    end

    if referenceButton and itemButton and referenceButton.IconBorder and itemButton.IconBorder and referenceButton.IconBorder.GetAlpha then
        itemButton.IconBorder:SetAlpha(referenceButton.IconBorder:GetAlpha())
    end

    if referenceItem.backdrop and item.backdrop then
        CopyFramePoint(referenceItem.backdrop, item.backdrop, referenceIndex, index)
    end

    return true
end

function MerchantSkinCompat.EnsureCurrencyLift(frame)
    if not frame or MerchantSkinCompat.IsForbiddenObject(frame) then
        return false
    end

    local existing = MerchantSkinCompat.currencyLiftStates[frame]
    if existing then
        return true
    end
    if type(hooksecurefunc) ~= "function"
        or type(frame.GetNumPoints) ~= "function"
        or type(frame.GetPoint) ~= "function"
        or type(frame.ClearAllPoints) ~= "function"
        or type(frame.SetPoint) ~= "function"
    then
        return false
    end

    local state = { applying = false }
    MerchantSkinCompat.currencyLiftStates[frame] = state

    local function ApplyLift()
        if state.applying then return end

        local pointCount = tonumber(frame:GetNumPoints()) or 0
        if pointCount < 1 then return end

        local points = {}
        for pointIndex = 1, pointCount do
            local point, relativeTo, relativePoint, x, y = frame:GetPoint(pointIndex)
            if not point then return end
            points[pointIndex] = { point, relativeTo, relativePoint, x or 0, (y or 0) + 6 }
        end

        state.applying = true
        frame:ClearAllPoints()
        for pointIndex = 1, #points do
            local point = points[pointIndex]
            frame:SetPoint(point[1], point[2], point[3], point[4], point[5])
        end
        state.applying = false
    end

    local hookOK = pcall(hooksecurefunc, frame, "SetPoint", ApplyLift)
    if not hookOK then
        MerchantSkinCompat.currencyLiftStates[frame] = nil
        return false
    end

    ApplyLift()
    return true
end

function MerchantSkinCompat.RefreshQualityBorder(itemButton)
    local state = MerchantSkinCompat.qualityBorders[itemButton]
    if not state or not state.qualityHost or not state.pixelPerfect then
        return
    end

    local r, g, b = 0, 0, 0
    local ring = itemButton and itemButton.IconBorder
    if ring and type(ring.IsShown) == "function" and type(ring.GetVertexColor) == "function" then
        local shownOK, shown = pcall(ring.IsShown, ring)
        if shownOK and shown == true then
            local colorOK, ringR, ringG, ringB = pcall(ring.GetVertexColor, ring)
            if colorOK and type(ringR) == "number" and type(ringG) == "number" and type(ringB) == "number"
                and math.max(ringR, ringG, ringB) - math.min(ringR, ringG, ringB) > MerchantSkinCompat.qualityChroma
            then
                r, g, b = ringR, ringG, ringB
            end
        end
    end

    SafeCall(state.pixelPerfect.SetBorderColor, state.qualityHost, r, g, b, 1)
end

function MerchantSkinCompat.EnsureQualityBorder(itemButton, icon, state, pixelPerfect)
    if not itemButton or not icon or not state or not pixelPerfect then
        return false
    end
    if state.qualityUnavailable then
        return false
    end

    if not state.qualityHost then
        local createOK, host = pcall(CreateFrame, "Frame", nil, itemButton)
        if not createOK or not host then
            return false
        end

        SafeMethod(host, "SetPoint", "TOPLEFT", icon, "TOPLEFT", -1, 1)
        SafeMethod(host, "SetPoint", "BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
        if type(itemButton.GetFrameLevel) == "function" then
            local levelOK, level = pcall(itemButton.GetFrameLevel, itemButton)
            if levelOK and type(level) == "number" then
                SafeMethod(host, "SetFrameLevel", level + 6)
            end
        end

        if not SafeCall(pixelPerfect.CreateBorder, host, 0, 0, 0, 1, 1, "OVERLAY", 7) then
            SafeMethod(host, "Hide")
            state.qualityUnavailable = true
            return false
        end
        state.qualityHost = host
    end

    state.pixelPerfect = pixelPerfect
    MerchantSkinCompat.qualityBorders[itemButton] = state

    if not state.qualityMethodHooked and type(itemButton.SetItemButtonQuality) == "function"
        and type(hooksecurefunc) == "function"
    then
        state.qualityMethodHooked = SafeCall(hooksecurefunc,
            itemButton, "SetItemButtonQuality", MerchantSkinCompat.RefreshQualityBorder)
    end
    if not MerchantSkinCompat.qualityGlobalHooked and type(_G.SetItemButtonQuality) == "function"
        and type(hooksecurefunc) == "function"
    then
        MerchantSkinCompat.qualityGlobalHooked = SafeCall(hooksecurefunc,
            "SetItemButtonQuality", MerchantSkinCompat.RefreshQualityBorder)
    end

    MerchantSkinCompat.RefreshQualityBorder(itemButton)
    return true
end

function MerchantSkinCompat.Apply(index, item, itemButton, pixelPerfect)
    if not item or not itemButton or not pixelPerfect
        or MerchantSkinCompat.IsForbiddenObject(item) or MerchantSkinCompat.IsForbiddenObject(itemButton)
    then
        return false
    end

    local state = MerchantSkinCompat.skinStates[item]
    if not state then
        state = {}
        MerchantSkinCompat.skinStates[item] = state
    end
    if state.cardBorderUnavailable then
        return false
    end

    if not state.cardBorder then
        local borderOK, border = pcall(pixelPerfect.CreateBorder, item,
            MerchantSkinCompat.borderR, MerchantSkinCompat.borderG, MerchantSkinCompat.borderB, 1,
            1, "BORDER", -7)
        if borderOK and border then
            state.cardBorder = border
            if type(item.GetFrameLevel) == "function" then
                local levelOK, level = pcall(item.GetFrameLevel, item)
                if levelOK and type(level) == "number" then
                    SafeMethod(border, "SetFrameLevel", level)
                end
            end
        else
            state.cardBorderUnavailable = true
            return false
        end
    end

    if not state.background and type(item.CreateTexture) == "function" then
        local textureOK, background = pcall(item.CreateTexture, item, nil, "BACKGROUND", nil, -7)
        if textureOK and background then
            state.background = background
            SafeMethod(background, "SetPoint", "TOPLEFT", item, "TOPLEFT", 2, -1)
            SafeMethod(background, "SetPoint", "BOTTOMRIGHT", item, "BOTTOMRIGHT", -2, 1)
        end
    end

    local background = state.background
    if background then
        SafeMethod(background, "SetColorTexture",
            MerchantSkinCompat.backgroundR, MerchantSkinCompat.backgroundG,
            MerchantSkinCompat.backgroundB, MerchantSkinCompat.backgroundA)
        SafeMethod(background, "SetAlpha", 1)
    end

    if type(item.GetRegions) == "function" then
        for regionIndex = 1, select("#", item:GetRegions()) do
            local region = select(regionIndex, item:GetRegions())
            if region and region ~= background and type(region.IsObjectType) == "function" then
                local typeOK, isTexture = pcall(region.IsObjectType, region, "Texture")
                if typeOK and isTexture == true then
                    SafeMethod(region, "SetAlpha", 0)
                end
            end
        end
    end

    SyncMerchantItemSkinLayout(index, false)
    local _, _, widgets = GetMerchantSkinWidgets(index)
    MerchantSkinCompat.EnsureCurrencyLift(widgets.money)
    MerchantSkinCompat.EnsureCurrencyLift(widgets.altCurrency)

    local itemName = type(item.GetName) == "function" and item:GetName() or nil
    local buttonName = type(itemButton.GetName) == "function" and itemButton:GetName() or nil
    local name = item.Name or (itemName and _G[itemName .. "Name"])
    local icon = itemButton.Icon or itemButton.icon or (buttonName and _G[buttonName .. "IconTexture"])
    local slot = buttonName and _G[buttonName .. "Slot"]
    local normalTexture = type(itemButton.GetNormalTexture) == "function" and itemButton:GetNormalTexture() or nil

    SafeMethod(normalTexture, "SetAlpha", 0)
    SafeMethod(slot, "SetAlpha", 0)
    if icon and type(icon.SetTexCoord) == "function" then
        local masked = false
        if type(icon.GetNumMaskTextures) == "function" then
            local maskOK, maskCount = pcall(icon.GetNumMaskTextures, icon)
            masked = not maskOK or (tonumber(maskCount) or 0) > 0
        end
        if not masked then
            pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
        end
    end

    if itemButton.IconBorder then
        SafeMethod(itemButton.IconBorder, "SetAlpha", 0)
    end
    SafeMethod(name, "SetWordWrap", true)
    SafeMethod(name, "SetMaxLines", 2)
    MerchantSkinCompat.EnsureQualityBorder(itemButton, icon, state, pixelPerfect)

    item.__YUITradeSkin = "EllesmereUI"
    return true
end

local function ApplyElvUISkinToMerchantItem(index, item, itemButton)
    if not GetElvUI() or not item or not itemButton then
        return false
    end

    if item.__YUITradeSkin ~= "ElvUI" then
        SafeMethod(item, "StripTextures", true)
        SafeMethod(item, "CreateBackdrop", "Transparent")
        SafeMethod(itemButton, "StripTextures")
        SafeMethod(itemButton, "StyleButton")
        SafeMethod(itemButton, "SetTemplate", nil, true)
        item.__YUITradeSkin = "ElvUI"
    end

    return SyncMerchantItemSkinLayout(index)
end

local function ApplyNDuiSkinToMerchantItem(index, item, itemButton)
    local B = GetNDui()
    if not B or not item or not itemButton then
        return false
    end

    if item.__YUITradeSkin ~= "NDui" then
        SafeCall(B.StripTextures, item)
        SafeCall(B.CreateBDFrame, item, 0.25)
        SafeCall(B.StripTextures, itemButton)
        local icon = itemButton.icon or _G["MerchantItem" .. index .. "ItemButtonIconTexture"]
        if icon then
            SafeCall(B.ReskinIcon, icon)
        end
        for j = 1, 3 do
            local texture = _G["MerchantItem" .. index .. "AltCurrencyFrameItem" .. j .. "Texture"]
            if texture then
                SafeCall(B.ReskinIcon, texture)
            end
        end
        item.__YUITradeSkin = "NDui"
    end

    return SyncMerchantItemSkinLayout(index)
end

local function ApplyMerchantExtraItemSkin(index)
    local item = GetMerchantItem(index)
    local itemButton = (item and item.ItemButton) or GetMerchantItemButton(index)
    if not item or not itemButton then
        return
    end

    local ellesmereProvider = MerchantSkinCompat:GetProvider()
    if ellesmereProvider and MerchantSkinCompat.Apply(index, item, itemButton, ellesmereProvider) then
        return
    end

    if GetElvUI() then
        ApplyElvUISkinToMerchantItem(index, item, itemButton)
        return
    end

    if GetNDui() then
        ApplyNDuiSkinToMerchantItem(index, item, itemButton)
    end
end

local function EnsureMerchantExtraItems()
    if not MerchantFrame or not CreateFrame then
        return
    end

    for index = 13, MERCHANT_EXPANDED_ITEMS_PER_PAGE do
        local item = GetMerchantItem(index)
        if not item then
            item = CreateFrame("Frame", "MerchantItem" .. index, MerchantFrame, "MerchantItemTemplate")
        end

        item:SetID(index)

        local itemButton = GetMerchantItemButton(index)
        if itemButton then
            itemButton:SetID(index)
        end

        ApplyMerchantExtraItemSkin(index)
    end
end

local function SetMerchantItemPoint(index, relativeIndex, relativePoint, x, y)
    local item = GetMerchantItem(index)
    if not item then return end

    item:ClearAllPoints()
    if relativeIndex then
        item:SetPoint("TOPLEFT", GetMerchantItem(relativeIndex), relativePoint or "BOTTOMLEFT", x or 0, y or 0)
    else
        item:SetPoint("TOPLEFT", MerchantFrame, "TOPLEFT", x or 11, y or -69)
    end
end

local function GetVisibleMerchantItemCount()
    if type(GetMerchantNumItems) ~= "function" or not MerchantFrame then
        return MERCHANT_EXPANDED_ITEMS_PER_PAGE
    end

    local numItems = GetMerchantNumItems() or 0
    local page = MerchantFrame.page or 1
    local firstIndex = ((page - 1) * MERCHANT_EXPANDED_ITEMS_PER_PAGE) + 1
    local visibleCount = numItems - firstIndex + 1

    if visibleCount < 0 then
        return 0
    end
    if visibleCount > MERCHANT_EXPANDED_ITEMS_PER_PAGE then
        return MERCHANT_EXPANDED_ITEMS_PER_PAGE
    end

    return visibleCount
end

local function GetMerchantIndexForSlot(slot)
    local page = MerchantFrame and MerchantFrame.page or 1
    return ((page - 1) * MERCHANT_EXPANDED_ITEMS_PER_PAGE) + slot
end

local function ClearMerchantItemPurchaseData(itemButton)
    if not itemButton then
        return
    end

    itemButton.price = nil
    itemButton.extendedCost = nil
    itemButton.name = nil
    itemButton.link = nil
    itemButton.texture = nil
    itemButton.count = nil
    itemButton.numAvailable = nil
    itemButton.hasItem = nil
    itemButton.showNonrefundablePrompt = nil
end

local function GetMerchantInfoForIndex(merchantIndex)
    if (YUI.IsRetail or YUI.IsForever) and C_MerchantFrame and type(C_MerchantFrame.GetItemInfo) == "function" then
        local info = C_MerchantFrame.GetItemInfo(merchantIndex)
        if info then
            return info.name, info.texture, info.price, info.stackCount, info.numAvailable,
                info.hasExtendedCost, info.currencyID, info.isPurchasable, info.isUsable
        end
    end

    if type(GetMerchantItemInfo) == "function" then
        local name, texture, price, stackCount, numAvailable, isPurchasable, isUsable, extendedCost, currencyID = GetMerchantItemInfo(merchantIndex)
        if name or texture or price or extendedCost or currencyID then
            return name, texture, price, stackCount, numAvailable, extendedCost, currencyID,
                isPurchasable, isUsable
        end
    end

    if C_MerchantFrame and type(C_MerchantFrame.GetItemInfo) == "function" then
        local info = C_MerchantFrame.GetItemInfo(merchantIndex)
        if info then
            return info.name, info.texture, info.price, info.stackCount, info.numAvailable,
                info.hasExtendedCost, info.currencyID, info.isPurchasable, info.isUsable
        end
    end

    return nil
end

local function IsMerchantBuyTabActive()
    return MerchantFrame and MerchantFrame.selectedTab == 1
end

local function GetMerchantItemInfoKey(owner, merchantIndex)
    local itemInfo
    if merchantIndex and type(GetMerchantItemLink) == "function" then
        itemInfo = GetMerchantItemLink(merchantIndex)
    end
    if not itemInfo and merchantIndex and type(GetMerchantItemID) == "function" then
        itemInfo = GetMerchantItemID(merchantIndex)
    end
    if not itemInfo and owner then
        itemInfo = owner.link or owner.itemID
    end
    return itemInfo
end

local function GetItemStackLimit(itemInfo)
    if itemInfo then
        local itemAPI = YUI.API and YUI.API.Item
        if itemAPI and type(itemAPI.GetMaxStackSize) == "function" then
            local ok, stackCount = pcall(itemAPI.GetMaxStackSize, itemInfo)
            stackCount = ok and tonumber(stackCount) or nil
            if stackCount and stackCount > 0 then
                return math.floor(stackCount + 0.5)
            end
        end

        if itemAPI and type(itemAPI.GetInfo) == "function" then
            local ok, info = pcall(itemAPI.GetInfo, itemInfo)
            info = ok and info or nil
            local stackCount = info and tonumber(info.stackCount)
            if stackCount and stackCount > 0 then
                return math.floor(stackCount + 0.5)
            end
        end

        if type(GetItemInfo) == "function" then
            local ok, itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, stackCount = pcall(GetItemInfo, itemInfo)
            stackCount = ok and stackCount or nil
            stackCount = tonumber(stackCount)
            if stackCount and stackCount > 0 then
                return math.floor(stackCount + 0.5)
            end
        end
    end

    return nil
end

local function GetMerchantItemStackLimit(owner, merchantIndex)
    return GetItemStackLimit(GetMerchantItemInfoKey(owner, merchantIndex))
end

local function GetBatchBuyGroupSizeForStackLimit(stackLimit)
    stackLimit = tonumber(stackLimit) or 0
    if stackLimit <= 1 then
        return BATCH_BUY_UNSTACKABLE_FALLBACK_STACK
    end
    return math.min(stackLimit, BATCH_BUY_UNSTACKABLE_FALLBACK_STACK)
end

local function GetMerchantItemBagCount(owner, merchantIndex)
    local itemInfo = GetMerchantItemInfoKey(owner, merchantIndex)
    if not itemInfo then
        return 0
    end

    local itemAPI = YUI.API and YUI.API.Item
    if itemAPI and type(itemAPI.GetCount) == "function" then
        local ok, count = pcall(itemAPI.GetCount, itemInfo, false, false, false)
        if ok then
            return ClampInteger(count, 0, nil, 0)
        end
    end

    if type(GetItemCount) == "function" then
        local ok, count = pcall(GetItemCount, itemInfo, false, false, false)
        if ok then
            return ClampInteger(count, 0, nil, 0)
        end
    end

    return 0
end

local function GetItemQuality(itemInfo)
    if not itemInfo then
        return nil
    end

    local itemAPI = YUI.API and YUI.API.Item
    if itemAPI and type(itemAPI.GetInfo) == "function" then
        local ok, info = pcall(itemAPI.GetInfo, itemInfo)
        if ok and info and info.quality then
            return tonumber(info.quality)
        end
    end

    if C_Item and type(C_Item.GetItemInfo) == "function" then
        local ok, itemName, itemLink, itemQuality = pcall(C_Item.GetItemInfo, itemInfo)
        if ok and itemQuality then
            return tonumber(itemQuality)
        end
    end

    if type(GetItemInfo) == "function" then
        local ok, itemName, itemLink, itemQuality = pcall(GetItemInfo, itemInfo)
        if ok and itemQuality then
            return tonumber(itemQuality)
        end
    end

    return nil
end

local function GetMerchantUnitPrice(merchantIndex)
    local _, _, price, stackCount = GetMerchantInfoForIndex(merchantIndex)
    price = tonumber(price) or 0
    stackCount = tonumber(stackCount) or 1
    if stackCount < 1 then
        stackCount = 1
    end
    if price <= 0 then
        return 0
    end
    return price / stackCount
end

local function GetMerchantTotalGoldCost(merchantIndex, quantity)
    local unitPrice = GetMerchantUnitPrice(merchantIndex)
    if unitPrice <= 0 then
        return 0
    end
    return math.ceil(unitPrice * (tonumber(quantity) or 0))
end

local function IsItemHyperlink(link)
    return type(link) == "string" and link:find("|Hitem:", 1, true) ~= nil
end

local function IsCurrencyHyperlink(link)
    return type(link) == "string" and link:find("|Hcurrency:", 1, true) ~= nil
end

local function GetCurrencyQuantityFromLink(link)
    if not IsCurrencyHyperlink(link)
        or not C_CurrencyInfo
        or type(C_CurrencyInfo.GetCurrencyInfoFromLink) ~= "function"
    then
        return nil
    end

    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfoFromLink, link)
    local quantity = ok and type(info) == "table" and tonumber(info.quantity) or nil
    if not quantity or quantity < 0 then
        return nil
    end
    return quantity
end

local function GetMerchantCurrencyCostPurchaseLimit(merchantIndex, stackCount)
    if type(GetMerchantItemCostInfo) ~= "function" or type(GetMerchantItemCostItem) ~= "function" then
        return nil, false
    end

    local costCount = tonumber(GetMerchantItemCostInfo(merchantIndex)) or 0
    if costCount < 1 then
        return nil, false
    end

    stackCount = ClampInteger(stackCount, 1, nil, 1)
    local limit, hasItemCost
    for costIndex = 1, costCount do
        local _, cost, costLink = GetMerchantItemCostItem(merchantIndex, costIndex)
        cost = tonumber(cost)
        local owned = GetCurrencyQuantityFromLink(costLink)
        if YUI.IsRetail and IsItemHyperlink(costLink) then
            -- Limited currency items require the native delayed confirmation.
            local itemAPI = YUI.API and YUI.API.Item
            if not (C_Item and type(C_Item.GetLimitedCurrencyItemInfo) == "function"
                and itemAPI and type(itemAPI.GetCount) == "function") then
                return nil, false
            end
            local ok, limitedName = pcall(C_Item.GetLimitedCurrencyItemInfo, costLink)
            if not ok or limitedName then return nil, false end
            local countOK, count = pcall(itemAPI.GetCount, costLink, false, false, true)
            owned = countOK and tonumber(count) or nil
            hasItemCost = true
        end
        if not cost or cost <= 0 or owned == nil then
            return nil, false
        end

        local affordable = math.floor(owned / cost) * stackCount
        if limit == nil or affordable < limit then
            limit = affordable
        end
    end

    return limit, limit ~= nil, hasItemCost
end

local function GetMerchantPurchaseLimit(owner, merchantIndex, nativeMaxStack, productLink)
    local limit = GetBatchBuyMaxQuantity()
    nativeMaxStack = tonumber(nativeMaxStack)

    local _, _, price, stackCount, numAvailable, extendedCost, _, isPurchasable = GetMerchantInfoForIndex(merchantIndex)
    if YUI.IsRetail and isPurchasable == false then return 0, false end
    stackCount = ClampInteger(stackCount, 1, nil, 1)
    local currencyCostLimit, currencyCostQueue, hasItemCost = GetMerchantCurrencyCostPurchaseLimit(merchantIndex, stackCount)
    currencyCostQueue = extendedCost == true
        and not (owner and owner.showNonrefundablePrompt)
        and IsItemHyperlink(productLink)
        and currencyCostQueue

    numAvailable = tonumber(numAvailable)
    if numAvailable == 0 then
        return 0, currencyCostQueue
    end
    if numAvailable and numAvailable > 0 then
        local stockLimit = currencyCostQueue and (numAvailable * stackCount) or numAvailable
        if stockLimit < limit then
            limit = stockLimit
        end
    end
    if currencyCostQueue then
        if currencyCostLimit < 1 then
            return 0, true
        end
        if currencyCostLimit < limit then
            limit = currencyCostLimit
        end
    elseif (extendedCost or (owner and owner.showNonrefundablePrompt))
        and nativeMaxStack and nativeMaxStack > 0 and nativeMaxStack < limit
    then
        limit = nativeMaxStack
    end

    if (not extendedCost or currencyCostQueue) and type(GetMoney) == "function" then
        price = tonumber(price) or 0
        if price > 0 then
            local affordable = math.floor((GetMoney() or 0) / (price / stackCount))
            if affordable < 1 then
                return 0, currencyCostQueue
            end
            if affordable < limit then
                limit = affordable
            end
        end
    end

    if currencyCostQueue and hasItemCost then
        -- Count compatible empty slots and partial stacks, as for ordinary item purchases.
        local containers = C_Container
        local familyAPI = C_Item and C_Item.GetItemFamily or GetItemFamily
        if containers and containers.GetContainerNumFreeSlots and containers.GetContainerNumSlots
            and containers.GetContainerItemInfo and familyAPI and bit and bit.band then
            local family = familyAPI(productLink)
            local itemID = tonumber(productLink:match("|Hitem:(%d+)"))
            local maxStack = GetMerchantItemStackLimit(owner, merchantIndex)
            if family and itemID and maxStack then
                local space = 0
                for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
                    local free, bagFamily = containers.GetContainerNumFreeSlots(bag)
                    if free and bagFamily and (bagFamily == 0 or bit.band(family, bagFamily) ~= 0) then
                        space = space + free * maxStack
                    end
                    for slot = 1, containers.GetContainerNumSlots(bag) do
                        local info = containers.GetContainerItemInfo(bag, slot)
                        if info and info.itemID == itemID then
                            space = space + math.max(0, maxStack - info.stackCount)
                        end
                    end
                end
                limit = math.min(limit, space)
            end
        end
        limit = math.floor(limit / stackCount) * stackCount
        if limit < stackCount then return 0, false end
    end
    return ClampInteger(limit, 1, GetBatchBuyMaxQuantity(), GetBatchBuyMaxQuantity()), currencyCostQueue,
        currencyCostQueue and hasItemCost or false
end

local function GetMerchantNativeMaxStack(merchantIndex)
    if type(GetMerchantItemMaxStack) == "function" then
        return ClampInteger(GetMerchantItemMaxStack(merchantIndex), 1, nil, 1)
    end
    return 1
end

local function IsBatchBuySpecialPurchase(context)
    return context and (context.extendedCost or context.showNonrefundablePrompt)
end

local function IsBatchBuyCurrencyCostQueue(context)
    return context and context.currencyCostQueue == true
end

local function GetMerchantItemLinkSafe(merchantIndex)
    if type(GetMerchantItemLink) == "function" then
        return GetMerchantItemLink(merchantIndex)
    end
    return nil
end

local function GetMerchantItemIDSafe(merchantIndex)
    if type(GetMerchantItemID) == "function" then
        return GetMerchantItemID(merchantIndex)
    end
    return nil
end

local function GetItemClassID(itemInfo)
    if not itemInfo then
        return nil
    end

    local itemAPI = YUI.API and YUI.API.Item
    if itemAPI and type(itemAPI.GetInfoInstant) == "function" then
        local ok, itemID, itemType, itemSubType, itemEquipLoc, icon, classID = pcall(itemAPI.GetInfoInstant, itemInfo)
        if ok and classID then
            return tonumber(classID)
        end
    end

    if C_Item and type(C_Item.GetItemInfoInstant) == "function" then
        local ok, itemID, itemType, itemSubType, itemEquipLoc, icon, classID = pcall(C_Item.GetItemInfoInstant, itemInfo)
        if ok and classID then
            return tonumber(classID)
        end
    end

    if type(GetItemInfoInstant) == "function" then
        local ok, itemID, itemType, itemSubType, itemEquipLoc, icon, classID = pcall(GetItemInfoInstant, itemInfo)
        if ok and classID then
            return tonumber(classID)
        end
    end

    return nil
end

local function GetContainerItemClassID()
    if Enum and Enum.ItemClass and Enum.ItemClass.Container then
        return tonumber(Enum.ItemClass.Container)
    end
    if LE_ITEM_CLASS_CONTAINER then
        return tonumber(LE_ITEM_CLASS_CONTAINER)
    end
    return 1
end

local function IsContainerItemClassID(classID)
    classID = tonumber(classID)
    return classID ~= nil and classID == GetContainerItemClassID()
end

local function GetWeaponItemClassID()
    if Enum and Enum.ItemClass and Enum.ItemClass.Weapon then
        return tonumber(Enum.ItemClass.Weapon)
    end
    if LE_ITEM_CLASS_WEAPON then
        return tonumber(LE_ITEM_CLASS_WEAPON)
    end
    return 2
end

local function GetArmorItemClassID()
    if Enum and Enum.ItemClass and Enum.ItemClass.Armor then
        return tonumber(Enum.ItemClass.Armor)
    end
    if LE_ITEM_CLASS_ARMOR then
        return tonumber(LE_ITEM_CLASS_ARMOR)
    end
    return 4
end

local function IsEquipmentItemClassID(classID)
    classID = tonumber(classID)
    return classID ~= nil and (classID == GetWeaponItemClassID() or classID == GetArmorItemClassID())
end

local function IsSinglePurchaseMerchantItem(context)
    if not context then
        return true
    end
    if IsContainerItemClassID(context.classID) then
        return true
    end
    return (tonumber(context.nativeMaxStack) or 0) <= 1
end

local function RefreshBatchBuyContext(context)
    if not context or not MerchantFrame or not MerchantFrame:IsShown() or not IsMerchantBuyTabActive() then
        return false
    end

    local merchantIndex = context.merchantIndex
    if type(merchantIndex) ~= "number" or merchantIndex < 1 then
        return false
    end

    local name, texture, price, stackCount, numAvailable, extendedCost, currencyID = GetMerchantInfoForIndex(merchantIndex)
    if YUI.IsForever and (extendedCost or currencyID or (context.owner and context.owner.showNonrefundablePrompt)) then return false end
    if not name and not texture and price == nil and not extendedCost and not currencyID then
        return false
    end

    local currentLink = GetMerchantItemLinkSafe(merchantIndex)
    if YUI.IsForever and IsCurrencyHyperlink(currentLink) then return false end
    if context.link and currentLink and currentLink ~= context.link then
        return false
    end
    if not context.link and context.name and name and name ~= context.name then
        return false
    end

    context.name = name or context.name
    context.texture = texture or context.texture
    context.link = currentLink or context.link
    context.itemID = GetMerchantItemIDSafe(merchantIndex) or context.itemID
    context.price = price
    context.stackCount = ClampInteger(stackCount, 1, nil, 1)
    context.numAvailable = numAvailable
    context.extendedCost = extendedCost or nil
    context.currencyID = currencyID
    context.showNonrefundablePrompt = context.owner and context.owner.showNonrefundablePrompt or nil
    context.nativeMaxStack = GetMerchantNativeMaxStack(merchantIndex)
    local itemInfo = context.link or context.itemID or GetMerchantItemInfoKey(context.owner, merchantIndex)
    context.quality = GetItemQuality(itemInfo)
    context.itemStackLimit = GetMerchantItemStackLimit(context.owner, merchantIndex) or 1
    context.bagCount = GetMerchantItemBagCount(context.owner, merchantIndex)
    context.classID = GetItemClassID(itemInfo)
    if IsEquipmentItemClassID(context.classID) then
        return false
    end
    context.singlePurchaseOnly = IsSinglePurchaseMerchantItem(context)
    context.groupSize = GetBatchBuyGroupSizeForStackLimit(context.itemStackLimit)
    context.purchaseLimit, context.currencyCostQueue, context.itemCostQueue = GetMerchantPurchaseLimit(
        context.owner,
        merchantIndex,
        context.nativeMaxStack,
        context.link
    )
    if context.purchaseLimit < (YUI.IsForever and context.stackCount or 1) then
        return false
    end
    context.totalCost = GetMerchantTotalGoldCost(merchantIndex, context.quantity or 1)
    return true
end

local function CreateBatchBuyContext(owner, nativeMaxStack)
    if not owner or type(owner.GetID) ~= "function" then
        return nil
    end

    local merchantIndex = owner:GetID()
    if type(merchantIndex) ~= "number" or merchantIndex < 1 then
        return nil
    end

    local name, texture, price, stackCount, numAvailable, extendedCost, currencyID = GetMerchantInfoForIndex(merchantIndex)
    if YUI.IsForever and (extendedCost or currencyID or owner.showNonrefundablePrompt) then return nil end
    if not name and not texture and price == nil and not extendedCost and not currencyID then
        return nil
    end

    if YUI.IsForever and IsCurrencyHyperlink(GetMerchantItemLinkSafe(merchantIndex)) then return nil end

    nativeMaxStack = ClampInteger(nativeMaxStack or GetMerchantNativeMaxStack(merchantIndex), 1, nil, 1)
    local context = {
        owner = owner,
        merchantIndex = merchantIndex,
        name = name,
        texture = texture,
        link = GetMerchantItemLinkSafe(merchantIndex),
        itemID = GetMerchantItemIDSafe(merchantIndex),
        price = price,
        stackCount = ClampInteger(stackCount, 1, nil, 1),
        numAvailable = numAvailable,
        extendedCost = extendedCost or nil,
        currencyID = currencyID,
        showNonrefundablePrompt = owner.showNonrefundablePrompt or nil,
        nativeMaxStack = nativeMaxStack,
    }
    local itemInfo = context.link or context.itemID or GetMerchantItemInfoKey(owner, merchantIndex)
    context.quality = GetItemQuality(itemInfo)
    context.itemStackLimit = GetMerchantItemStackLimit(owner, merchantIndex) or 1
    context.bagCount = GetMerchantItemBagCount(owner, merchantIndex)
    context.classID = GetItemClassID(itemInfo)
    if IsEquipmentItemClassID(context.classID) then
        return nil
    end
    context.singlePurchaseOnly = IsSinglePurchaseMerchantItem(context)
    context.groupSize = GetBatchBuyGroupSizeForStackLimit(context.itemStackLimit)
    context.purchaseLimit, context.currencyCostQueue, context.itemCostQueue = GetMerchantPurchaseLimit(
        owner,
        merchantIndex,
        nativeMaxStack,
        context.link
    )
    if context.purchaseLimit < (YUI.IsForever and context.stackCount or 1) then
        return nil
    end
    context.totalCost = GetMerchantTotalGoldCost(merchantIndex, 1)
    return context
end

local function GetBatchBuyQueueChunkSize(context, quantity)
    if not context then
        return 0
    end

    quantity = ClampInteger(quantity, 0, nil, 0)
    if quantity < 1 then
        return 0
    end

    if context.singlePurchaseOnly then
        return context.itemCostQueue and context.stackCount or 1
    end

    local chunk = quantity
    if BATCH_BUY_NORMAL_CHUNK_LIMIT > 0 and BATCH_BUY_NORMAL_CHUNK_LIMIT < chunk then
        chunk = BATCH_BUY_NORMAL_CHUNK_LIMIT
    end

    local nativeMaxStack = tonumber(context.nativeMaxStack) or 0
    if nativeMaxStack > 1 and nativeMaxStack < chunk then
        chunk = nativeMaxStack
    end

    local purchaseLimit = tonumber(context.purchaseLimit) or 0
    if purchaseLimit > 0 and purchaseLimit < chunk then
        chunk = purchaseLimit
    end

    if YUI.IsForever or context.itemCostQueue then
        return math.floor(chunk / context.stackCount) * context.stackCount
    end
    return math.max(1, chunk)
end

local function FormatMoneyText(copper)
    copper = tonumber(copper) or 0
    if type(GetCoinTextureString) == "function" then
        return GetCoinTextureString(copper)
    end
    if type(GetMoneyString) == "function" then
        return GetMoneyString(copper, true)
    end
    return string.format("%.2fG", copper / COPPER_PER_GOLD)
end

local function FormatBatchBuyCostCount(count)
    count = tonumber(count) or 0
    if count <= 0 then
        return nil
    end

    local rounded = math.floor(count + 0.5)
    if math.abs(count - rounded) < 0.0001 then
        return tostring(rounded)
    end

    return string.format("%.2f", count)
end

local function FormatBatchBuyCostIcon(texture, count)
    if not texture then
        return nil
    end

    local countText = FormatBatchBuyCostCount(count)
    if not countText then
        return nil
    end

    return string.format("%s |T%s:0:0:0:-1|t", countText, tostring(texture))
end

local function FormatMerchantExtendedCostText(merchantIndex, quantity, stackCount)
    if type(GetMerchantItemCostInfo) ~= "function" or type(GetMerchantItemCostItem) ~= "function" then
        return nil
    end

    merchantIndex = tonumber(merchantIndex)
    if not merchantIndex then
        return nil
    end

    local costCount = tonumber(GetMerchantItemCostInfo(merchantIndex)) or 0
    if costCount <= 0 then
        return nil
    end

    quantity = tonumber(quantity) or 1
    if quantity < 1 then
        quantity = 1
    end

    stackCount = tonumber(stackCount) or 1
    if stackCount < 1 then
        stackCount = 1
    end

    local multiplier = quantity / stackCount
    local parts = {}
    for index = 1, costCount do
        local texture, count = GetMerchantItemCostItem(merchantIndex, index)
        local text = FormatBatchBuyCostIcon(texture, (tonumber(count) or 0) * multiplier)
        if text then
            parts[#parts + 1] = text
        end
    end

    if #parts == 0 then
        return nil
    end

    return table.concat(parts, "  ")
end

local function FormatBatchBuyTotalCost(context, quantity)
    if not context then
        return FormatMoneyText(0)
    end

    quantity = ClampInteger(quantity, 1, nil, 1)

    local totalGoldCost = GetMerchantTotalGoldCost(context.merchantIndex, quantity)
    if not totalGoldCost then
        totalGoldCost = context.totalCost
    end
    local moneyText = nil
    if totalGoldCost and totalGoldCost > 0 then
        moneyText = FormatMoneyText(totalGoldCost)
    end

    local extendedCostText = FormatMerchantExtendedCostText(context.merchantIndex, quantity, context.stackCount)
    if moneyText and extendedCostText then
        return moneyText .. "  " .. extendedCostText
    end
    if extendedCostText then
        return extendedCostText
    end

    return FormatMoneyText(totalGoldCost)
end

local function StopBatchBuyQueue()
    batchBuyFrameEventOwner.generation = (batchBuyFrameEventOwner.generation or 0) + 1
    if batchBuyQueue and YUI.Event and YUI.Event.OffOwner then YUI.Event:OffOwner(batchBuyQueue) end
    if batchBuyQueue then
        batchBuyQueue.cancelled = true
        batchBuyQueue = nil
    end
    if batchBuyQueueFrame then
        batchBuyQueueFrame.queue = nil
        batchBuyQueueFrame.elapsed = 0
        batchBuyQueueFrame:SetScript("OnUpdate", nil)
        batchBuyQueueFrame:Hide()
    end
end

local RunBatchBuyQueueStep

local function OnBatchBuyQueueDelayUpdate(frame, elapsed)
    frame.elapsed = (frame.elapsed or 0) + (elapsed or 0)
    local queue = frame.queue
    local interval = queue and queue.interval or BATCH_BUY_QUEUE_INTERVAL
    if frame.elapsed < interval then
        return
    end

    frame.queue = nil
    frame.elapsed = 0
    frame:SetScript("OnUpdate", nil)
    frame:Hide()

    RunBatchBuyQueueStep(queue)
end

local function ScheduleBatchBuyQueueStep(queue)
    local interval = queue and queue.interval or BATCH_BUY_QUEUE_INTERVAL
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(interval, function()
            RunBatchBuyQueueStep(queue)
        end)
        return
    end

    if not batchBuyQueueFrame and type(CreateFrame) == "function" then
        batchBuyQueueFrame = CreateFrame("Frame")
        batchBuyQueueFrame:Hide()
    end
    if batchBuyQueueFrame then
        batchBuyQueueFrame.queue = queue
        batchBuyQueueFrame.elapsed = 0
        batchBuyQueueFrame:SetScript("OnUpdate", OnBatchBuyQueueDelayUpdate)
        batchBuyQueueFrame:Show()
        return
    end

    RunBatchBuyQueueStep(queue)
end

RunBatchBuyQueueStep = function(queue)
    if not queue or queue.cancelled or batchBuyQueue ~= queue then
        return
    end
    if not RefreshBatchBuyContext(queue.context) then
        StopBatchBuyQueue()
        return
    end
    if queue.currencyCostQueue and not IsBatchBuyCurrencyCostQueue(queue.context) then
        StopBatchBuyQueue()
        return
    end
    if queue.remaining <= 0 then
        StopBatchBuyQueue()
        return
    end

    local chunk = GetBatchBuyQueueChunkSize(queue.context, queue.remaining)
    if chunk < 1 then
        StopBatchBuyQueue()
        return
    end

    if type(BuyMerchantItem) == "function" then
        BuyMerchantItem(queue.context.merchantIndex, chunk)
    end
    queue.remaining = queue.remaining - chunk

    if queue.remaining > 0 then
        ScheduleBatchBuyQueueStep(queue)
    else
        StopBatchBuyQueue()
    end
end

local function StartBatchBuyQueue(context, quantity, interval)
    StopBatchBuyQueue()
    batchBuyQueue = {
        context = context,
        remaining = quantity,
        interval = interval or BATCH_BUY_QUEUE_INTERVAL,
        currencyCostQueue = IsBatchBuyCurrencyCostQueue(context),
    }
    if YUI.IsForever and YUI.Event and YUI.Event.On then
        YUI.Event:On("UI_ERROR_MESSAGE", StopBatchBuyQueue, batchBuyQueue)
    end
    RunBatchBuyQueueStep(batchBuyQueue)
end

local PerformBatchBuy
local HideBatchBuyFrame
local RefreshOpenBatchBuyFrame
local RefreshBatchBuyFrameContent

local function DetachBatchBuyFrameEvents()
    if YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(batchBuyFrameEventOwner)
    end
end

batchBuyFrameEventOwner.OnEvent = function()
    if RefreshOpenBatchBuyFrame then
        RefreshOpenBatchBuyFrame({ preserveInput = true })
    end
end

local function AttachBatchBuyFrameEvents()
    if not (YUI.Event and YUI.Event.On) then
        return
    end

    DetachBatchBuyFrameEvents()
    local options = {
        debounce = 0.05,
        moduleId = "component:TradeEnhancement",
    }
    YUI.Event:On("BAG_UPDATE_DELAYED", "OnEvent", batchBuyFrameEventOwner, options)
    YUI.Event:On("BAG_UPDATE", "OnEvent", batchBuyFrameEventOwner, options)
    YUI.Event:On("PLAYER_MONEY", "OnEvent", batchBuyFrameEventOwner, options)
end

local function ShowBatchBuyPriceWarning(context, quantity, totalCost)
    local Settings = YUI.Settings
    if not (Settings and Settings.ShowConfirmPopup) then
        return false
    end

    local itemName = context and (context.link or context.name)
    if not itemName then
        local name = GetMerchantInfoForIndex(context and context.merchantIndex)
        itemName = name or ""
    end

    Settings:ShowConfirmPopup(string.format(
        T("settings.general.feature.trade_enhancement.batch_buy.price_warning_confirm"),
        itemName,
        FormatMoneyText(totalCost)
    ), function()
        if PerformBatchBuy then
            PerformBatchBuy(context, quantity, true)
        end
    end, {
        titleText = T("settings.general.feature.trade_enhancement.batch_buy.price_warning_title"),
        acceptTone = "warning",
    })
    return true
end

local function ShouldWarnBatchBuyPrice(context, quantity)
    if IsBatchBuySpecialPurchase(context) then
        return false, 0
    end

    local warningGold = GetBatchBuyPriceWarningGold()
    if warningGold <= 0 then
        return false, 0
    end

    local totalCost = GetMerchantTotalGoldCost(context and context.merchantIndex, quantity)
    return totalCost > (warningGold * COPPER_PER_GOLD), totalCost
end

PerformBatchBuy = function(context, quantity, skipWarning)
    if not RefreshBatchBuyContext(context) then
        if HideBatchBuyFrame then
            HideBatchBuyFrame()
        end
        return
    end

    quantity = ClampInteger(quantity, 1, context.purchaseLimit, 1)
    if context.itemCostQueue then
        quantity = math.floor(quantity / context.stackCount) * context.stackCount
        if quantity < context.stackCount then return end
    end
    if YUI.IsForever then
        quantity = math.floor(quantity / context.stackCount) * context.stackCount
        if quantity < 1 then return end
    end

    if not skipWarning then
        local shouldWarn, totalCost = ShouldWarnBatchBuyPrice(context, quantity)
        if shouldWarn and ShowBatchBuyPriceWarning(context, quantity, totalCost) then
            return
        end
    end

    if IsBatchBuyCurrencyCostQueue(context) then
        if context.itemCostQueue and not skipWarning then
            local settings = YUI.Settings
            if not (settings and settings.ShowConfirmPopup) then
                if type(MerchantFrame_ConfirmExtendedItemCost) == "function" then
                    MerchantFrame_ConfirmExtendedItemCost(context.owner, math.min(quantity, context.nativeMaxStack))
                end
                return
            end
            local generation = batchBuyFrameEventOwner.generation
            local confirmedCost = FormatBatchBuyTotalCost(context, quantity)
            settings:ShowConfirmPopup(string.format(
                T("settings.general.feature.trade_enhancement.batch_buy.price_warning_confirm"),
                tostring(quantity) .. " × " .. (context.link or context.name),
                confirmedCost
            ), function()
                if generation ~= batchBuyFrameEventOwner.generation or not IsBatchBuyEnabled() then return end
                if not RefreshBatchBuyContext(context) or not context.itemCostQueue then return end
                if FormatBatchBuyTotalCost(context, quantity) ~= confirmedCost then return end
                PerformBatchBuy(context, quantity, true)
            end, { acceptTone = "warning" })
            return
        end
        StartBatchBuyQueue(context, quantity, BATCH_BUY_CURRENCY_QUEUE_INTERVAL)
        return
    end

    if IsBatchBuySpecialPurchase(context) then
        if type(MerchantFrame_ConfirmExtendedItemCost) == "function" then
            MerchantFrame_ConfirmExtendedItemCost(context.owner, quantity)
        elseif context.owner and context.owner.SplitStack then
            context.owner.SplitStack(context.owner, quantity)
        end
        return
    end

    StartBatchBuyQueue(context, quantity)
end

local function GetBatchBuyFrameQuantity()
    if batchBuyContext and batchBuyContext.quantity then
        return batchBuyContext.quantity
    end
    return 1
end

local function GetBatchBuyFrameQuantityLimit()
    return (batchBuyContext and batchBuyContext.purchaseLimit) or GetBatchBuyMaxQuantity()
end

local function SetBatchBuyFrameButtonText(button, text)
    if button and button.SetText then
        button:SetText(text)
    elseif button and button.text and button.text.SetText then
        button.text:SetText(text)
    end
end

local function SetBatchBuyTextColor(text, colorKey)
    local GUI2 = YUI.GUI2
    if text and GUI2 and type(GUI2.SetTextColorKey) == "function" then
        GUI2:SetTextColorKey(text, colorKey)
    end
end

local function SetBatchBuyItemNameColor(text, quality)
    if not text then
        return
    end

    quality = tonumber(quality)
    if quality then
        local itemAPI = YUI.API and YUI.API.Item
        if itemAPI and type(itemAPI.GetQualityColor) == "function" then
            local r, g, b = itemAPI.GetQualityColor(quality)
            if r then
                text:SetTextColor(r, g, b, 1)
                return
            end
        elseif type(GetItemQualityColor) == "function" then
            local r, g, b = GetItemQualityColor(quality)
            if r then
                text:SetTextColor(r, g, b, 1)
                return
            end
        end
    end

    SetBatchBuyTextColor(text, "color.text.heading")
end

local function FocusBatchBuyQuantityEditBox(selectAll)
    local frame = batchBuyControls
    local editBox = frame and frame.quantityEditBox
    if not editBox then
        return
    end

    if editBox.SetFocus then
        editBox:SetFocus()
    end

    if selectAll then
        if editBox.HighlightText then
            editBox:HighlightText()
        end
        return
    end

    if editBox.HighlightText then
        editBox:HighlightText(0, 0)
    end
    if editBox.SetCursorPosition then
        local text = editBox.GetText and editBox:GetText() or ""
        editBox:SetCursorPosition(#text)
    end
end

local function SetBatchBuyFrameQuantity(quantity)
    if not batchBuyContext then
        return
    end

    quantity = ClampInteger(quantity, 1, GetBatchBuyFrameQuantityLimit(), 1)
    if batchBuyContext.itemCostQueue then
        local step = batchBuyContext.stackCount
        quantity = math.min(math.ceil(quantity / step) * step, GetBatchBuyFrameQuantityLimit())
    end
    if YUI.IsForever then
        local step = batchBuyContext.stackCount
        quantity = math.max(step, math.floor(quantity / step) * step)
    end
    batchBuyContext.quantity = quantity
    batchBuyContext.totalCost = GetMerchantTotalGoldCost(batchBuyContext.merchantIndex, quantity)

    local frame = batchBuyControls
    local editBox = frame and frame.quantityEditBox
    if editBox and editBox.SetText and not frame.__YUIBatchBuyUpdatingInput then
        frame.__YUIBatchBuyUpdatingInput = true
        local text = tostring(quantity)
        editBox:SetText(text)
        if editBox.SetCursorPosition then
            editBox:SetCursorPosition(#text)
        end
        frame.__YUIBatchBuyUpdatingInput = false
    end

    if RefreshBatchBuyFrameContent then
        RefreshBatchBuyFrameContent()
    end
end

local function GetBatchBuyFrameButtonValue(button)
    if not button then
        return 1
    end
    if button.__YUIBatchBuyValue == "stack" then
        return (batchBuyContext and batchBuyContext.groupSize) or BATCH_BUY_UNSTACKABLE_FALLBACK_STACK
    end
    return tonumber(button.__YUIBatchBuyValue) or 1
end

local function OnBatchBuyFrameStepButtonClick(button, mouseButton)
    local value = GetBatchBuyFrameButtonValue(button)
    local current = GetBatchBuyFrameQuantity()
    if mouseButton == "RightButton" then
        SetBatchBuyFrameQuantity(math.max(1, current - value))
    elseif current < value then
        SetBatchBuyFrameQuantity(value)
    else
        SetBatchBuyFrameQuantity(current + value)
    end
    FocusBatchBuyQuantityEditBox(false)
end

local function OnBatchBuyFrameAdjustButtonClick(button)
    SetBatchBuyFrameQuantity(GetBatchBuyFrameQuantity() + (button.__YUIBatchBuyDelta or 0))
    FocusBatchBuyQuantityEditBox(false)
end

HideBatchBuyFrame = function()
    DetachBatchBuyFrameEvents()
    if batchBuyControls then
        if batchBuyControls.quantityEditBox and batchBuyControls.quantityEditBox.ClearFocus then
            batchBuyControls.quantityEditBox:ClearFocus()
        end
        if YUI.HideGameTooltip then
            YUI.HideGameTooltip()
        elseif GameTooltip then
            GameTooltip:Hide()
        end
        batchBuyControls:Hide()
    end
    batchBuyContext = nil
end

local function ConfirmBatchBuyFrame()
    local context = batchBuyContext
    if not context then
        HideBatchBuyFrame()
        return
    end

    -- Commit the current draft before capturing the quantity. Focus loss may
    -- occur after the click/Enter callback, and an empty draft keeps no value.
    local editBox = batchBuyControls and batchBuyControls.quantityEditBox
    if editBox then SetBatchBuyFrameQuantity(editBox:GetText()) end
    local quantity = GetBatchBuyFrameQuantity()
    HideBatchBuyFrame()
    PerformBatchBuy(context, quantity, false)
end

local function OnBatchBuyFrameInputChanged(editBox)
    local frame = batchBuyControls
    if not batchBuyContext or (frame and frame.__YUIBatchBuyUpdatingInput) then
        return
    end

    local text = editBox:GetText()
    if text == "" then
        return
    end

    local quantity = ClampInteger(text, 1, GetBatchBuyFrameQuantityLimit(), 1)
    if tostring(quantity) ~= text then
        SetBatchBuyFrameQuantity(quantity)
    else
        batchBuyContext.quantity = quantity
        batchBuyContext.totalCost = GetMerchantTotalGoldCost(batchBuyContext.merchantIndex, quantity)
        if RefreshBatchBuyFrameContent then
            RefreshBatchBuyFrameContent()
        end
    end
end

local function OnBatchBuyFrameInputCommit(editBox)
    if not batchBuyContext then
        return
    end
    SetBatchBuyFrameQuantity(editBox:GetText())
    if editBox.ClearFocus then
        editBox:ClearFocus()
    end
end

local function CreateBatchBuyFrameButton(parent, name, text, width, onClick, height, tone)
    local GUI2 = YUI.GUI2
    local button
    if GUI2 and GUI2.Form and type(GUI2.Form.CreateButton) == "function" then
        -- Both presentations share a layout owner and the same purchase callback.
        if GUI2.WindowAppearance and GUI2.CreateFrame and GUI2.CreateButtonFrame then
            button = GUI2:CreateFrame(parent, {
                name = name, width = width, height = height or BATCH_BUY_CONTROL_HEIGHT, mouse = false,
            })
        end
        local owner = button
        local modern = GUI2.Form:CreateButton(owner or parent, {
            name = not owner and name or nil,
            text = text,
            width = width,
            height = height or BATCH_BUY_CONTROL_HEIGHT,
            tone = tone or "default",
            onClick = function(control, mouseButton) onClick(owner or control, mouseButton) end,
        })
        if owner then
            modern:SetAllPoints(owner)
            owner.modern = modern
            owner.native = GUI2:CreateButtonFrame(owner, { template = "UIPanelButtonTemplate" })
            owner.native:SetAllPoints(owner)
            owner.native:SetText(text)
            owner.native:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            modern:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            owner.native:SetScript("OnClick", function(_, mouseButton) onClick(owner, mouseButton) end)
            owner.SetText = function(self, value)
                self.modern:SetText(value)
                self.native:SetText(value)
            end
            owner.SetDisabled = function(self, disabled)
                self.modern:SetDisabled(disabled)
                self.native:SetEnabled(not disabled)
            end
            owner.native:Hide()
        else
            button = modern
        end
    elseif CreateFrame then
        button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
        button:SetSize(width, height or BATCH_BUY_CONTROL_HEIGHT)
        button:SetText(text)
        button:SetScript("OnClick", onClick)
    end
    if button and button.RegisterForClicks then
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    return button
end

function batchBuyFrameEventOwner.appearance.PaintInput(editBox)
    local context = editBox.batchBuyAppearance
    if not context then return end
    local GUI2 = YUI.GUI2
    local native = context.source == "native"
    if editBox.gui2Bg then
        editBox.gui2Bg:SetShown(not native)
        if not native then
            editBox.gui2Bg:SetBackdropColor((unpack or table.unpack)(context.background or { GUI2:GetColor("color.control.bg") }))
            local border = (editBox:HasFocus() or editBox:IsMouseOver())
                and (context.accent or "color.border.focus") or (context.border or "color.border.default")
            GUI2:SetBorderColor(editBox.gui2Bg, border)
        end
    end
    for _, region in ipairs(editBox.batchBuyNativeRegions or {}) do region:SetShown(native) end
end

function batchBuyFrameEventOwner.appearance.PaintIcon(slot)
    local context = slot.batchBuyAppearance
    if not context then return end
    local GUI2 = YUI.GUI2
    if slot.SetBackdropColor then
        slot:SetBackdropColor((unpack or table.unpack)(context.background or { GUI2:GetColor("color.control.bg") }))
    end
    GUI2:SetBorderColor(slot, context.source == "native" and "color.text.accent"
        or (context.border or "color.border.default"))
end

function batchBuyFrameEventOwner.appearance.Layout(frame, native)
    if frame.batchBuyNativeLayout == native then return end
    frame.batchBuyNativeLayout = native
    local padding = BATCH_BUY_FRAME_PADDING + (native and 4 or 0)
    local top = BATCH_BUY_CONTENT_TOP + (native and 8 or 4)
    local width = BATCH_BUY_FRAME_WIDTH - padding * 2
    local textX = padding + BATCH_BUY_ICON_SIZE + 12
    local settingsWidth = frame.settingsButton and frame.settingsButton:GetWidth() or 0
    if frame.settingsButton then
        frame.settingsButton:ClearAllPoints()
        frame.settingsButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -padding, -top)
    end
    if frame.itemIconSlot then
        frame.itemIconSlot:ClearAllPoints()
        frame.itemIconSlot:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, -top)
    end
    if frame.itemNameText then
        frame.itemNameText:ClearAllPoints()
        frame.itemNameText:SetPoint("TOPLEFT", frame, "TOPLEFT", textX, -top)
        frame.itemNameText:SetSize(BATCH_BUY_FRAME_WIDTH - padding - textX
            - (settingsWidth > 0 and settingsWidth + 8 or 0), 20)
    end
    if frame.itemStatsText then
        frame.itemStatsText:ClearAllPoints()
        frame.itemStatsText:SetPoint("TOPLEFT", frame, "TOPLEFT", textX, -(top + 24))
        frame.itemStatsText:SetSize(BATCH_BUY_FRAME_WIDTH - padding - textX, 20)
    end
    local costY = top + BATCH_BUY_ICON_SIZE + 12
    if frame.totalCostText then
        frame.totalCostText:ClearAllPoints()
        frame.totalCostText:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, -costY)
        frame.totalCostText:SetSize(width, 18)
    end
    local quantityY = costY + 18 + BATCH_BUY_ROW_GAP
    if frame.minusButton then
        frame.minusButton:ClearAllPoints()
        frame.minusButton:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, -quantityY)
    end
    if frame.quantityEditBox then
        frame.quantityEditBox:SetSize(width - 2 * (BATCH_BUY_SMALL_BUTTON_WIDTH + BATCH_BUY_ROW_GAP),
            BATCH_BUY_CONTROL_HEIGHT)
    end
    local buttonWidth = (width - BATCH_BUY_COLUMN_GAP) / 2
    local shortcutY = quantityY + BATCH_BUY_CONTROL_HEIGHT + BATCH_BUY_ROW_GAP
    for index, button in ipairs(frame.stepButtons) do
        local row, column = math.floor((index - 1) / 2), (index - 1) % 2
        button:ClearAllPoints()
        button:SetSize(buttonWidth, BATCH_BUY_CONTROL_HEIGHT)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", padding + column * (buttonWidth + BATCH_BUY_COLUMN_GAP),
            -(shortcutY + row * (BATCH_BUY_CONTROL_HEIGHT + BATCH_BUY_ROW_GAP)))
    end
    if frame.okayButton then
        frame.okayButton:ClearAllPoints()
        frame.okayButton:SetSize(buttonWidth, BATCH_BUY_CONTROL_HEIGHT)
        frame.okayButton:SetPoint("TOPLEFT", frame, "TOPLEFT", padding,
            -(shortcutY + 2 * BATCH_BUY_CONTROL_HEIGHT + BATCH_BUY_ROW_GAP + 16))
    end
    if frame.cancelButton then frame.cancelButton:SetSize(buttonWidth, BATCH_BUY_CONTROL_HEIGHT) end
end

function batchBuyFrameEventOwner.appearance.Refresh(frame, context)
    local GUI2 = YUI.GUI2
    local appearance = GUI2.WindowAppearance
    local native = context.source == "native"
    local background = context.background or { GUI2:GetColor("color.control.bg") }
    local border = context.border or { GUI2:GetColor("color.border.default") }
    local r, g, b = appearance:GetAccentColor(context)
    local accent = r and { r, g, b, 1 } or { GUI2:GetColor("color.text.accent") }
    for _, control in ipairs(frame.appearanceButtons) do
        if control.modern then
            local modern = control.modern
            modern.gui2SurfaceToken, modern.gui2BorderToken = background, border
            modern.gui2HoverSurfaceToken, modern.gui2HoverBorderToken = background, accent
            modern.gui2PressedSurfaceToken, modern.gui2PressedBorderToken = background, accent
            modern:RefreshTheme()
            appearance:ApplyFont(modern.text, context)
            control.native:SetShown(native)
            modern:SetShown(not native)
        end
    end
    for _, text in ipairs(frame.appearanceTexts) do appearance:ApplyFont(text, context) end
    if frame.quantityEditBox then
        frame.quantityEditBox.batchBuyAppearance = context
        appearance:ApplyFont(frame.quantityEditBox, context)
        batchBuyFrameEventOwner.appearance.PaintInput(frame.quantityEditBox)
    end
    if frame.itemIconSlot then
        frame.itemIconSlot.batchBuyAppearance = context
        batchBuyFrameEventOwner.appearance.PaintIcon(frame.itemIconSlot)
    end
    batchBuyFrameEventOwner.appearance.Layout(frame, native)
end

local function CreateBatchBuyText(parent, text, sizeKey, colorKey, justifyH)
    local GUI2 = YUI.GUI2
    if GUI2 and type(GUI2.CreateText) == "function" then
        return GUI2:CreateText(parent, text or "", sizeKey or "font.size.md", colorKey or "color.text.primary", justifyH or "LEFT")
    end

    if parent and parent.CreateFontString then
        local fontString = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fontString:SetText(text or "")
        if justifyH then
            fontString:SetJustifyH(justifyH)
        end
        return fontString
    end

    return nil
end

local function CreateBatchBuyIconSlot(parent)
    local GUI2 = YUI.GUI2
    local slot
    if GUI2 and type(GUI2.CreateIconSlot) == "function" then
        slot = GUI2:CreateIconSlot(parent, {
            name = "YUITradeBatchBuyItemIcon",
            size = BATCH_BUY_ICON_SIZE,
            icon = "Interface\\Icons\\INV_Misc_QuestionMark",
            onClick = function() end,
        })
    elseif CreateFrame then
        slot = CreateFrame("Button", "YUITradeBatchBuyItemIcon", parent, "BackdropTemplate")
        slot:SetSize(BATCH_BUY_ICON_SIZE, BATCH_BUY_ICON_SIZE)
        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetAllPoints(slot)
        slot.SetIcon = function(frame, texture)
            frame.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        end
    end
    if slot and GUI2 and GUI2.WindowAppearance then
        local refreshTheme = slot.RefreshTheme
        slot.RefreshTheme = function(self)
            if refreshTheme then refreshTheme(self) end
            batchBuyFrameEventOwner.appearance.PaintIcon(self)
        end
    end
    return slot
end

local function ShowBatchBuyItemTooltip(anchor)
    local context = batchBuyContext
    if not context or not GameTooltip then
        return
    end

    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    if context.merchantIndex and GameTooltip.SetMerchantItem and SafeCall(GameTooltip.SetMerchantItem, GameTooltip, context.merchantIndex) then
        GameTooltip:Show()
        return
    end
    if context.link and GameTooltip.SetHyperlink and SafeCall(GameTooltip.SetHyperlink, GameTooltip, context.link) then
        GameTooltip:Show()
        return
    end
    GameTooltip:SetText(context.name or "")
    GameTooltip:Show()
end

local function HideBatchBuyItemTooltip()
    if YUI.HideGameTooltip then
        YUI.HideGameTooltip()
    elseif GameTooltip then
        GameTooltip:Hide()
    end
end

local function OpenBatchBuySettings()
    HideBatchBuyFrame()
    if YUI.Settings and YUI.Settings.OpenComponentFeature then
        YUI.Settings:OpenComponentFeature("TradeEnhancement")
        return
    end
    if Components and Components.OpenFeatureSettings then
        Components:OpenFeatureSettings("TradeEnhancement")
        return
    end
    if YUI.OpenSettings then
        YUI:OpenSettings(T("settings.general.feature.trade_enhancement.label"))
    end
end

local function CreateBatchBuySettingsButton(parent)
    local GUI2 = YUI.GUI2
    if not (GUI2 and parent) then
        return nil
    end

    local options = {
        name = "YUITradeBatchBuySettingsButton",
        size = 20,
        tooltip = T("settings.generic_settings"),
        onClick = OpenBatchBuySettings,
    }
    local button
    if type(GUI2.CreateBlizzardIconButton) == "function" and (YUI.IsRetail or YUI.IsWrath) then
        options.atlas = YUI.IsWrath and "glues-characterSelect-icon-notify-inProgress-hover" or nil
        button = GUI2:CreateBlizzardIconButton(parent, options)
    elseif type(GUI2.CreateIconButton) == "function" then
        options.icon = "Interface\\Icons\\INV_Misc_Gear_01"
        options.texCoords = { 0.12, 0.88, 0.12, 0.88 }
        options.padding = 1
        options.surface = "color.control.bg"
        options.border = "color.border.accent"
        options.iconColor = "color.text.accent"
        button = GUI2:CreateIconButton(parent, options)
    end
    return button
end

local function ApplyBatchBuySuccessButtonStyle(button)
    local GUI2 = YUI.GUI2
    if not (button and GUI2) then
        return
    end

    local originalRefreshTheme = button.RefreshTheme
    local function ApplySuccessState(frame)
        if frame.gui2Disabled then
            return
        end
        if GUI2.SetBorderColor then
            GUI2:SetBorderColor(frame, "color.state.success")
        end
        if frame.text and GUI2.SetTextColorKey then
            GUI2:SetTextColorKey(frame.text, "color.state.success")
        end
    end

    button.RefreshTheme = function(frame)
        if originalRefreshTheme then
            originalRefreshTheme(frame)
        end
        ApplySuccessState(frame)
    end
    if button.HookScript then
        button:HookScript("OnLeave", ApplySuccessState)
        button:HookScript("OnMouseUp", function(frame)
            if not frame:IsMouseOver() then
                ApplySuccessState(frame)
            end
        end)
    end
    button:RefreshTheme()
end

local function EnsureBatchBuyFrame()
    if batchBuyControls then
        return batchBuyControls
    end
    if not UIParent then
        return nil
    end

    local GUI2 = YUI.GUI2
    local frame
    if GUI2 and GUI2.WindowAppearance and type(GUI2.CreateFrame) == "function" then
        frame = GUI2:CreateFrame(UIParent, {
            name = "YUITradeBatchBuyFrame", width = BATCH_BUY_FRAME_WIDTH, height = BATCH_BUY_FRAME_HEIGHT,
        })
    elseif GUI2 and type(GUI2.CreatePanel) == "function" then
        frame = GUI2:CreatePanel(UIParent, {
            name = "YUITradeBatchBuyFrame",
            width = BATCH_BUY_FRAME_WIDTH,
            height = BATCH_BUY_FRAME_HEIGHT,
            surface = "color.surface.popup",
            border = "color.popup.border",
            shadow = true,
        })
    elseif CreateFrame then
        frame = CreateFrame("Frame", "YUITradeBatchBuyFrame", UIParent, "BackdropTemplate")
        frame:SetSize(BATCH_BUY_FRAME_WIDTH, BATCH_BUY_FRAME_HEIGHT)
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
        frame:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
    end
    if not frame then
        return nil
    end

    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(750)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()
    frame:SetScript("OnHide", function()
        DetachBatchBuyFrameEvents()
        HideBatchBuyItemTooltip()
        batchBuyContext = nil
    end)

    if UISpecialFrames then
        UISpecialFrames[#UISpecialFrames + 1] = "YUITradeBatchBuyFrame"
    end

    frame.settingsButton = CreateBatchBuySettingsButton(frame)
    if frame.settingsButton then
        frame.settingsButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -12)
        if frame.settingsButton.SetFrameLevel and frame.GetFrameLevel then
            frame.settingsButton:SetFrameLevel(frame:GetFrameLevel() + 4)
        end
    end

    frame.itemIconSlot = CreateBatchBuyIconSlot(frame)
    if frame.itemIconSlot then
        frame.itemIconSlot:SetPoint("TOPLEFT", frame, "TOPLEFT", BATCH_BUY_FRAME_PADDING, -BATCH_BUY_CONTENT_TOP)
        if frame.itemIconSlot.HookScript then
            frame.itemIconSlot:HookScript("OnEnter", ShowBatchBuyItemTooltip)
            frame.itemIconSlot:HookScript("OnLeave", HideBatchBuyItemTooltip)
        end
    end

    frame.itemNameText = CreateBatchBuyText(frame, "", "font.size.md", "color.text.heading", "LEFT")
    if frame.itemNameText then
        frame.itemNameText:SetPoint("TOPLEFT", frame, "TOPLEFT", 68, -14)
        frame.itemNameText:SetSize(148, 18)
        frame.itemNameText:SetJustifyH("LEFT")
        if frame.itemNameText.SetWordWrap then
            frame.itemNameText:SetWordWrap(false)
        end
    end

    frame.itemStatsText = CreateBatchBuyText(frame, "", "font.size.md", "color.text.secondary", "LEFT")
    if frame.itemStatsText then
        frame.itemStatsText:SetPoint("TOPLEFT", frame, "TOPLEFT", 68, -40)
        frame.itemStatsText:SetSize(176, 20)
        frame.itemStatsText:SetJustifyH("LEFT")
        if frame.itemStatsText.SetWordWrap then
            frame.itemStatsText:SetWordWrap(false)
        end
    end

    frame.totalCostText = CreateBatchBuyText(frame, "", "font.size.md", "color.text.primary", "CENTER")
    if frame.totalCostText then
        frame.totalCostText:SetPoint("TOPLEFT", frame, "TOPLEFT", BATCH_BUY_FRAME_PADDING, -78)
        frame.totalCostText:SetSize(BATCH_BUY_FRAME_WIDTH - (BATCH_BUY_FRAME_PADDING * 2), 18)
        frame.totalCostText:SetJustifyH("CENTER")
    end

    frame.minusButton = CreateBatchBuyFrameButton(frame, "YUITradeBatchBuyMinusButton", "-", BATCH_BUY_SMALL_BUTTON_WIDTH, OnBatchBuyFrameAdjustButtonClick)
    if frame.minusButton then
        frame.minusButton.__YUIBatchBuyDelta = -1
        frame.minusButton:SetPoint("TOPLEFT", frame, "TOPLEFT", BATCH_BUY_FRAME_PADDING, -104)
    end

    if GUI2 and GUI2.WindowAppearance and GUI2.CreateFrame and GUI2.SkinEditBox then
        frame.quantityEditBox = GUI2:CreateFrame(frame, {
            type = "EditBox", template = "InputBoxTemplate", name = "YUITradeBatchBuyQuantityEditBox",
            width = BATCH_BUY_QUANTITY_INPUT_WIDTH, height = BATCH_BUY_CONTROL_HEIGHT,
        })
        local input = frame.quantityEditBox
        input:SetAutoFocus(false)
        input.batchBuyNativeRegions = {}
        for _, key in ipairs({ "Left", "Middle", "Right" }) do
            local region = input[key] or _G["YUITradeBatchBuyQuantityEditBox" .. key]
            if region then
                input.batchBuyNativeRegions[#input.batchBuyNativeRegions + 1] = region
                region:Hide()
                region:SetHeight(BATCH_BUY_CONTROL_HEIGHT)
            end
        end
        local left, middle, right = input.batchBuyNativeRegions[1], input.batchBuyNativeRegions[2], input.batchBuyNativeRegions[3]
        if left and middle and right then
            left:ClearAllPoints()
            left:SetPoint("LEFT", input, "LEFT", 0, 0)
            right:ClearAllPoints()
            right:SetPoint("RIGHT", input, "RIGHT", 0, 0)
            middle:ClearAllPoints()
            middle:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
            middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)
        end
        GUI2:SkinEditBox(input)
        if input.gui2Bg then
            input.gui2Bg:ClearAllPoints()
            input.gui2Bg:SetAllPoints(input)
        end
        local refreshTheme = input.RefreshTheme
        input.RefreshTheme = function(self)
            if refreshTheme then refreshTheme(self) end
            batchBuyFrameEventOwner.appearance.PaintInput(self)
        end
        for _, script in ipairs({ "OnEnter", "OnLeave", "OnEditFocusGained", "OnEditFocusLost" }) do
            input:HookScript(script, batchBuyFrameEventOwner.appearance.PaintInput)
        end
    elseif GUI2 and GUI2.Form and type(GUI2.Form.CreateEditBox) == "function" then
        frame.quantityEditBox = GUI2.Form:CreateEditBox(frame, {
            name = "YUITradeBatchBuyQuantityEditBox",
            width = BATCH_BUY_QUANTITY_INPUT_WIDTH,
            height = BATCH_BUY_CONTROL_HEIGHT,
            autoFocus = false,
        })
    elseif CreateFrame then
        frame.quantityEditBox = CreateFrame("EditBox", "YUITradeBatchBuyQuantityEditBox", frame, "InputBoxTemplate")
        frame.quantityEditBox:SetSize(BATCH_BUY_QUANTITY_INPUT_WIDTH, BATCH_BUY_CONTROL_HEIGHT)
        frame.quantityEditBox:SetAutoFocus(false)
        frame.quantityEditBox:SetFontObject(GameFontHighlight)
    end
    local editBox = frame.quantityEditBox
    if editBox then
        editBox:SetPoint("LEFT", frame.minusButton or frame, frame.minusButton and "RIGHT" or "LEFT", BATCH_BUY_ROW_GAP, 0)
        editBox:SetJustifyH("CENTER")
        if editBox.SetNumeric then
            editBox:SetNumeric(true)
        end
        if editBox.SetMaxLetters then
            editBox:SetMaxLetters(5)
        end
        editBox:SetScript("OnTextChanged", OnBatchBuyFrameInputChanged)
        editBox:SetScript("OnEnterPressed", ConfirmBatchBuyFrame)
        editBox:SetScript("OnEscapePressed", HideBatchBuyFrame)
        editBox:SetScript("OnEditFocusLost", OnBatchBuyFrameInputCommit)
    end

    frame.plusButton = CreateBatchBuyFrameButton(frame, "YUITradeBatchBuyPlusButton", "+", BATCH_BUY_SMALL_BUTTON_WIDTH, OnBatchBuyFrameAdjustButtonClick)
    if frame.plusButton then
        frame.plusButton.__YUIBatchBuyDelta = 1
        frame.plusButton:SetPoint("LEFT", frame.quantityEditBox or frame.minusButton or frame, "RIGHT", BATCH_BUY_ROW_GAP, 0)
    end

    frame.stepButtons = {}
    for index, value in ipairs(BATCH_BUY_BUTTON_VALUES) do
        local button = CreateBatchBuyFrameButton(frame, "YUITradeBatchBuyStep" .. index .. "Button", "", BATCH_BUY_STEP_BUTTON_WIDTH, OnBatchBuyFrameStepButtonClick)
        if button then
            button.__YUIBatchBuyValue = value
            local row = math.floor((index - 1) / 2)
            local column = (index - 1) % 2
            local x = BATCH_BUY_FRAME_PADDING + (column * (BATCH_BUY_STEP_BUTTON_WIDTH + BATCH_BUY_COLUMN_GAP))
            local y = -139 - (row * (BATCH_BUY_CONTROL_HEIGHT + BATCH_BUY_ROW_GAP))
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
            frame.stepButtons[index] = button
        end
    end

    frame.okayButton = CreateBatchBuyFrameButton(frame, "YUITradeBatchBuyOkayButton", T("common.confirm"), BATCH_BUY_STEP_BUTTON_WIDTH, ConfirmBatchBuyFrame, BATCH_BUY_CONTROL_HEIGHT, "accent")
    frame.cancelButton = CreateBatchBuyFrameButton(frame, "YUITradeBatchBuyCancelButton", T("common.cancel"), BATCH_BUY_STEP_BUTTON_WIDTH, HideBatchBuyFrame)
    ApplyBatchBuySuccessButtonStyle(frame.okayButton and (frame.okayButton.modern or frame.okayButton))
    if frame.okayButton then
        frame.okayButton:SetPoint("TOPLEFT", frame, "TOPLEFT", BATCH_BUY_FRAME_PADDING, -215)
    end
    if frame.cancelButton and frame.okayButton then
        frame.cancelButton:SetPoint("LEFT", frame.okayButton, "RIGHT", BATCH_BUY_COLUMN_GAP, 0)
    end

    batchBuyControls = frame
    if GUI2 and GUI2.WindowAppearance then
        frame.appearanceButtons = { frame.minusButton, frame.plusButton, frame.okayButton, frame.cancelButton }
        for _, button in ipairs(frame.stepButtons) do
            frame.appearanceButtons[#frame.appearanceButtons + 1] = button
        end
        frame.appearanceTexts = { frame.itemNameText, frame.itemStatsText, frame.totalCostText }
        GUI2.WindowAppearance:Register(frame, {
            blizzardWindow = "merchant", noTopBar = true, nativeBorderOverflow = true,
            role = "batch-buy", nativeLayout = "Dialog", onRefresh = batchBuyFrameEventOwner.appearance.Refresh,
        })
    end
    return frame
end

RefreshBatchBuyFrameContent = function()
    local frame = batchBuyControls
    local context = batchBuyContext
    if not frame or not context then
        return
    end

    if frame.itemIconSlot and frame.itemIconSlot.SetIcon then
        frame.itemIconSlot:SetIcon(context.texture)
    elseif frame.itemIconSlot and frame.itemIconSlot.icon then
        frame.itemIconSlot.icon:SetTexture(context.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    end

    if frame.itemNameText then
        frame.itemNameText:SetText(context.name or "")
        SetBatchBuyItemNameColor(frame.itemNameText, context.quality)
    end

    if frame.itemStatsText then
        frame.itemStatsText:SetText(string.format("%s: %d    %s: %d",
            T("settings.general.feature.trade_enhancement.batch_buy.stack_label"),
            tonumber(context.itemStackLimit) or 1,
            T("settings.general.feature.trade_enhancement.batch_buy.bag_label"),
            tonumber(context.bagCount) or 0))
    end

    if frame.totalCostText then
        frame.totalCostText:SetText(string.format("%s: %s",
            T("settings.general.feature.trade_enhancement.batch_buy.total_cost_label"),
            FormatBatchBuyTotalCost(context, GetBatchBuyFrameQuantity())))
    end

    local quantity = GetBatchBuyFrameQuantity()
    local limit = GetBatchBuyFrameQuantityLimit()
    if frame.minusButton and frame.minusButton.SetDisabled then
        frame.minusButton:SetDisabled(quantity <= 1)
    end
    if frame.plusButton and frame.plusButton.SetDisabled then
        frame.plusButton:SetDisabled(quantity >= limit)
    end
end

local function RefreshBatchBuyFrameLabels()
    local frame = batchBuyControls
    if not frame or not frame.stepButtons then
        return
    end
    for _, button in ipairs(frame.stepButtons) do
        SetBatchBuyFrameButtonText(button, tostring(GetBatchBuyFrameButtonValue(button)))
    end
end

RefreshOpenBatchBuyFrame = function(options)
    local frame = batchBuyControls
    if not frame or not frame:IsShown() then
        return
    end
    local editBox = frame.quantityEditBox
    local hadFocus = editBox and editBox.HasFocus and editBox:HasFocus()
    if not RefreshBatchBuyContext(batchBuyContext) then
        HideBatchBuyFrame()
        return
    end
    RefreshBatchBuyFrameLabels()

    local quantity = GetBatchBuyFrameQuantity()
    local limit = GetBatchBuyFrameQuantityLimit()
    if hadFocus or (options and options.preserveInput and quantity >= 1 and quantity <= limit) then
        -- Merchant/item events may arrive while the user has deleted the old
        -- number. Refresh the preview, but never replace the focused draft.
        quantity = ClampInteger(quantity, 1, limit, 1)
        batchBuyContext.quantity = quantity
        batchBuyContext.totalCost = GetMerchantTotalGoldCost(batchBuyContext.merchantIndex, quantity)
        if RefreshBatchBuyFrameContent then
            RefreshBatchBuyFrameContent()
        end
        return
    end

    SetBatchBuyFrameQuantity(quantity)
    if options and options.preserveInput and hadFocus then
        FocusBatchBuyQuantityEditBox(false)
    end
end

local function PositionBatchBuyFrame(frame, anchor)
    if not frame then
        return
    end

    frame:ClearAllPoints()
    if not (anchor and anchor.GetObjectType) then
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return
    end

    local parentRight = UIParent and UIParent.GetRight and UIParent:GetRight()
    local anchorRight = anchor.GetRight and anchor:GetRight()
    if parentRight and anchorRight and (parentRight - anchorRight) >= (BATCH_BUY_FRAME_WIDTH + BATCH_BUY_ANCHOR_GAP + 8) then
        frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", BATCH_BUY_ANCHOR_GAP, 0)
    else
        frame:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -BATCH_BUY_ANCHOR_GAP, 0)
    end
end

local function ShowBatchBuyFrame(context, anchor)
    local frame = EnsureBatchBuyFrame()
    if not frame or not context then
        return false
    end

    batchBuyContext = context
    context.quantity = 1
    RefreshBatchBuyFrameLabels()
    SetBatchBuyFrameQuantity(1)

    PositionBatchBuyFrame(frame, anchor)
    frame:Show()
    AttachBatchBuyFrameEvents()
    FocusBatchBuyQuantityEditBox(true)
    return true
end

local function OpenBatchBuyFrame(owner, nativeMaxStack)
    local context = CreateBatchBuyContext(owner, nativeMaxStack)
    if not context then
        return false
    end
    return ShowBatchBuyFrame(context, owner)
end

local function HandleBatchBuyMerchantModifiedClick(owner, button)
    if not IsBatchBuyEnabled() or not owner or not IsMerchantBuyTabActive() then
        return false
    end
    if type(IsModifiedClick) ~= "function" or not IsModifiedClick("SPLITSTACK") then
        return false
    end
    if type(owner.GetID) ~= "function" then
        return false
    end

    local merchantIndex = owner:GetID()
    if type(merchantIndex) ~= "number" or merchantIndex < 1 then
        return false
    end

    if type(GetMerchantItemLink) == "function" and type(HandleModifiedItemClick) == "function" then
        if HandleModifiedItemClick(GetMerchantItemLink(merchantIndex)) then
            return true
        end
    end

    return OpenBatchBuyFrame(owner, GetMerchantNativeMaxStack(merchantIndex))
end

local function BatchBuyMerchantItemButton_OnModifiedClick(self, button)
    if HandleBatchBuyMerchantModifiedClick(self, button) then
        return
    end
    if merchantItemButtonOnModifiedClickOriginal then
        return merchantItemButtonOnModifiedClickOriginal(self, button)
    end
end

local function CloseBatchBuyForMerchantNavigation()
    if HideBatchBuyFrame then
        HideBatchBuyFrame()
    end
    StopBatchBuyQueue()
end

local function InstallBatchBuyHooks()
    if batchBuyHooksInstalled or not IsMerchantFrameSupported() then
        return
    end

    if YUI.IsForever then
        if type(hooksecurefunc) ~= "function" or type(_G.MerchantItemButton_BuyMultipleStacks) ~= "function" then return end
        hooksecurefunc("MerchantItemButton_BuyMultipleStacks", function(owner)
            if not IsBatchBuyEnabled() or not IsMerchantBuyTabActive() then return end
            if OpenBatchBuyFrame(owner, GetMerchantNativeMaxStack(owner:GetID())) then
                local split = _G.StackSplitFrame
                if split and split.owner == owner then split:Hide() end
            end
        end)
    elseif type(_G.MerchantItemButton_OnModifiedClick) == "function" then
        merchantItemButtonOnModifiedClickOriginal = _G.MerchantItemButton_OnModifiedClick
        _G.MerchantItemButton_OnModifiedClick = BatchBuyMerchantItemButton_OnModifiedClick
    end

    if type(hooksecurefunc) == "function" then
        if type(_G.MerchantPrevPageButton_OnClick) == "function" then
            hooksecurefunc("MerchantPrevPageButton_OnClick", CloseBatchBuyForMerchantNavigation)
        end
        if type(_G.MerchantNextPageButton_OnClick) == "function" then
            hooksecurefunc("MerchantNextPageButton_OnClick", CloseBatchBuyForMerchantNavigation)
        end
    end

    batchBuyHooksInstalled = true
end

local function SyncMerchantItemPurchaseData(slot, isVisible)
    local item = GetMerchantItem(slot)
    local itemButton = (item and item.ItemButton) or GetMerchantItemButton(slot)
    if not itemButton then
        return
    end

    local merchantIndex = GetMerchantIndexForSlot(slot)
    if item and item.SetID then
        item:SetID(merchantIndex)
    end
    itemButton:SetID(merchantIndex)

    if not isVisible then
        ClearMerchantItemPurchaseData(itemButton)
        return
    end

    local name, texture, price, stackCount, numAvailable, extendedCost, currencyID = GetMerchantInfoForIndex(merchantIndex)
    if not name and not texture and price == nil and not extendedCost and not currencyID then
        ClearMerchantItemPurchaseData(itemButton)
        return
    end

    if currencyID and CurrencyContainerUtil and type(CurrencyContainerUtil.GetCurrencyContainerInfo) == "function" then
        name, texture = CurrencyContainerUtil.GetCurrencyContainerInfo(currencyID, numAvailable, name, texture, nil)
    end

    itemButton.hasItem = true
    itemButton.name = name
    itemButton.link = type(GetMerchantItemLink) == "function" and GetMerchantItemLink(merchantIndex) or nil
    itemButton.texture = texture
    itemButton.count = stackCount
    itemButton.numAvailable = numAvailable
    itemButton.extendedCost = extendedCost or nil
    itemButton.showNonrefundablePrompt = nil

    if extendedCost and (price or 0) <= 0 then
        itemButton.price = nil
    else
        itemButton.price = price
    end
end

local function ApplyMerchantPageSize()
    MERCHANT_ITEMS_PER_PAGE = MERCHANT_EXPANDED_ITEMS_PER_PAGE
end

local function ApplyMerchantFrameSize()
    if not MerchantFrame then
        return
    end

    local width = GetMerchantExpandedWidth()
    MerchantFrame:SetWidth(width)
    if UIPanelWindows and UIPanelWindows.MerchantFrame then
        UIPanelWindows.MerchantFrame.width = width
    end

    if MerchantNameText then
        MerchantNameText:ClearAllPoints()
        MerchantNameText:SetPoint("TOP", MerchantFrame, "TOP", 0, -5)
    end
end

local function ApplyRetailMerchantFrameSize()
    ApplyMerchantFrameSize()

    if not MerchantFrame then
        return
    end

    if MerchantFrameBottomLeftBorder and MerchantFrameBottomLeftBorder.SetWidth then
        MerchantFrameBottomLeftBorder:SetWidth(GetMerchantExpandedWidth() - 2)
    end
end

local function ApplyMerchantPageLayout()
    if not MerchantFrame then
        return
    end

    local rightPanelX = GetMerchantRightPanelX()
    local visibleCount = GetVisibleMerchantItemCount()

    SetMerchantItemPoint(1, nil, nil, 11, -69)
    SetMerchantItemPoint(2, 1, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(3, 1, "BOTTOMLEFT", 0, -15)
    SetMerchantItemPoint(4, 3, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(5, 3, "BOTTOMLEFT", 0, -15)
    SetMerchantItemPoint(6, 5, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(7, 5, "BOTTOMLEFT", 0, -15)
    SetMerchantItemPoint(8, 7, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(9, 7, "BOTTOMLEFT", 0, -15)
    SetMerchantItemPoint(10, 9, "TOPRIGHT", 12, 0)

    SetMerchantItemPoint(11, nil, nil, rightPanelX, -69)
    SetMerchantItemPoint(12, 11, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(13, 11, "BOTTOMLEFT", 0, -15)
    SetMerchantItemPoint(14, 13, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(15, 13, "BOTTOMLEFT", 0, -15)
    SetMerchantItemPoint(16, 15, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(17, 15, "BOTTOMLEFT", 0, -15)
    SetMerchantItemPoint(18, 17, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(19, 17, "BOTTOMLEFT", 0, -15)
    SetMerchantItemPoint(20, 19, "TOPRIGHT", 12, 0)

    for index = 1, MERCHANT_EXPANDED_ITEMS_PER_PAGE do
        local isVisible = index <= visibleCount
        SyncMerchantItemPurchaseData(index, isVisible)
        ShowFrame(GetMerchantItem(index), true)
    end

    ShowFrame(BuybackBG, false)

    if MerchantPrevPageButton then
        MerchantPrevPageButton:ClearAllPoints()
        MerchantPrevPageButton:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", rightPanelX + 24, 38)
    end

    if MerchantNextPageButton then
        MerchantNextPageButton:ClearAllPoints()
        MerchantNextPageButton:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", rightPanelX + 282, 38)
    end

    if MerchantPageText then
        MerchantPageText:ClearAllPoints()
        MerchantPageText:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", rightPanelX + 110, 47)
    end

    if MerchantBuyBackItem then
        MerchantBuyBackItem:ClearAllPoints()
        MerchantBuyBackItem:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 176, 33)
    end

    if MerchantRepairAllButton then
        MerchantRepairAllButton:ClearAllPoints()
        MerchantRepairAllButton:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 100, 34)
    end

    if MerchantRepairItemButton and MerchantRepairAllButton then
        MerchantRepairItemButton:ClearAllPoints()
        MerchantRepairItemButton:SetPoint("RIGHT", MerchantRepairAllButton, "LEFT", -4, 0)
    end

    if MerchantGuildBankRepairButton and MerchantRepairAllButton then
        MerchantGuildBankRepairButton:ClearAllPoints()
        MerchantGuildBankRepairButton:SetPoint("LEFT", MerchantRepairAllButton, "RIGHT", 4, 0)
    end

    if MerchantRepairText then
        MerchantRepairText:ClearAllPoints()
        MerchantRepairText:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 16, 45)
    end
end

local function ApplyRetailMerchantBottomLayout(rightPanelX)
    if MerchantPrevPageButton then
        MerchantPrevPageButton:ClearAllPoints()
        MerchantPrevPageButton:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", rightPanelX + 24, 38)
    end

    if MerchantNextPageButton then
        MerchantNextPageButton:ClearAllPoints()
        MerchantNextPageButton:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", rightPanelX + 282, 38)
    end

    if MerchantPageText then
        MerchantPageText:ClearAllPoints()
        MerchantPageText:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", rightPanelX + 110, 47)
    end

    if MerchantBuyBackItem then
        MerchantBuyBackItem:ClearAllPoints()
        MerchantBuyBackItem:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 220, 33)
    end

    local repairAnchor = nil
    if MerchantRepairAllButton then
        MerchantRepairAllButton:ClearAllPoints()
        MerchantRepairAllButton:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 100, 34)
        if MerchantRepairAllButton.IsShown and MerchantRepairAllButton:IsShown() then
            repairAnchor = MerchantRepairAllButton
        end
    end

    if MerchantRepairItemButton and MerchantRepairAllButton then
        MerchantRepairItemButton:ClearAllPoints()
        MerchantRepairItemButton:SetPoint("RIGHT", MerchantRepairAllButton, "LEFT", -4, 0)
    end

    if MerchantGuildBankRepairButton and MerchantRepairAllButton then
        MerchantGuildBankRepairButton:ClearAllPoints()
        MerchantGuildBankRepairButton:SetPoint("LEFT", MerchantRepairAllButton, "RIGHT", 4, 0)
        if MerchantGuildBankRepairButton.IsShown and MerchantGuildBankRepairButton:IsShown() then
            repairAnchor = MerchantGuildBankRepairButton
        end
    end

    if MerchantSellAllJunkButton then
        MerchantSellAllJunkButton:ClearAllPoints()
        if repairAnchor then
            MerchantSellAllJunkButton:SetPoint("LEFT", repairAnchor, "RIGHT", 4, 0)
        else
            MerchantSellAllJunkButton:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 100, 34)
        end
    end

    if MerchantRepairText then
        MerchantRepairText:ClearAllPoints()
        MerchantRepairText:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 16, 45)
    end
end

local function ApplyRetailMerchantPageLayout()
    if not MerchantFrame then
        return
    end

    local rightPanelX = GetMerchantRightPanelX()
    local visibleCount = GetVisibleMerchantItemCount()

    SetMerchantItemPoint(1, nil, nil, 11, -69)
    SetMerchantItemPoint(2, 1, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(3, 1, "BOTTOMLEFT", 0, -8)
    SetMerchantItemPoint(4, 3, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(5, 3, "BOTTOMLEFT", 0, -8)
    SetMerchantItemPoint(6, 5, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(7, 5, "BOTTOMLEFT", 0, -8)
    SetMerchantItemPoint(8, 7, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(9, 7, "BOTTOMLEFT", 0, -8)
    SetMerchantItemPoint(10, 9, "TOPRIGHT", 12, 0)

    SetMerchantItemPoint(11, nil, nil, rightPanelX, -69)
    SetMerchantItemPoint(12, 11, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(13, 11, "BOTTOMLEFT", 0, -8)
    SetMerchantItemPoint(14, 13, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(15, 13, "BOTTOMLEFT", 0, -8)
    SetMerchantItemPoint(16, 15, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(17, 15, "BOTTOMLEFT", 0, -8)
    SetMerchantItemPoint(18, 17, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(19, 17, "BOTTOMLEFT", 0, -8)
    SetMerchantItemPoint(20, 19, "TOPRIGHT", 12, 0)

    for index = 1, MERCHANT_EXPANDED_ITEMS_PER_PAGE do
        local isVisible = index <= visibleCount
        SyncMerchantItemPurchaseData(index, isVisible)
        ShowFrame(GetMerchantItem(index), true)
    end

    ShowFrame(BuybackBG, false)
    ShowFrame(MerchantFrameBottomLeftBorder, true)
    ApplyRetailMerchantBottomLayout(rightPanelX)
end

local function ApplyMerchantBuybackItemVisibility()
    for index = 1, MERCHANT_EXPANDED_ITEMS_PER_PAGE do
        ShowFrame(GetMerchantItem(index), index <= MERCHANT_NATIVE_BUYBACK_ITEMS_PER_PAGE)
    end
end

local function ApplyMerchantBuybackLayout()
    ApplyMerchantBuybackItemVisibility()

    if not MerchantFrame then
        return
    end

    local rightPanelX = GetMerchantRightPanelX()

    SetMerchantItemPoint(1, nil, nil, 11, -69)
    SetMerchantItemPoint(2, 1, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(3, 1, "BOTTOMLEFT", 0, -15)
    SetMerchantItemPoint(4, 3, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(5, 3, "BOTTOMLEFT", 0, -15)
    SetMerchantItemPoint(6, 5, "TOPRIGHT", 12, 0)

    SetMerchantItemPoint(7, nil, nil, rightPanelX, -69)
    SetMerchantItemPoint(8, 7, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(9, 7, "BOTTOMLEFT", 0, -15)
    SetMerchantItemPoint(10, 9, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(11, 9, "BOTTOMLEFT", 0, -15)
    SetMerchantItemPoint(12, 11, "TOPRIGHT", 12, 0)

    if MerchantPrevPageButton then
        MerchantPrevPageButton:ClearAllPoints()
        MerchantPrevPageButton:SetPoint("CENTER", MerchantFrame, "BOTTOMLEFT", 25, 96)
    end

    if MerchantNextPageButton then
        MerchantNextPageButton:ClearAllPoints()
        MerchantNextPageButton:SetPoint("CENTER", MerchantFrame, "BOTTOMRIGHT", -25, 96)
    end
end

local function ApplyRetailMerchantBuybackLayout()
    ApplyMerchantBuybackItemVisibility()

    if not MerchantFrame then
        return
    end

    local rightPanelX = GetMerchantRightPanelX()

    SetMerchantItemPoint(1, nil, nil, 11, -69)
    SetMerchantItemPoint(2, 1, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(3, 1, "BOTTOMLEFT", 0, -15)
    SetMerchantItemPoint(4, 3, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(5, 3, "BOTTOMLEFT", 0, -15)
    SetMerchantItemPoint(6, 5, "TOPRIGHT", 12, 0)

    SetMerchantItemPoint(7, nil, nil, rightPanelX, -69)
    SetMerchantItemPoint(8, 7, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(9, 7, "BOTTOMLEFT", 0, -15)
    SetMerchantItemPoint(10, 9, "TOPRIGHT", 12, 0)
    SetMerchantItemPoint(11, 9, "BOTTOMLEFT", 0, -15)
    SetMerchantItemPoint(12, 11, "TOPRIGHT", 12, 0)

    ShowFrame(BuybackBG, true)
    ShowFrame(MerchantSellAllJunkButton, false)

    if MerchantPrevPageButton then
        MerchantPrevPageButton:ClearAllPoints()
        MerchantPrevPageButton:SetPoint("CENTER", MerchantFrame, "BOTTOMLEFT", 25, 96)
    end

    if MerchantNextPageButton then
        MerchantNextPageButton:ClearAllPoints()
        MerchantNextPageButton:SetPoint("CENTER", MerchantFrame, "BOTTOMRIGHT", -25, 96)
    end
end

local function GetItemQualityFromLink(link)
    if not link then
        return nil
    end

    if type(GetItemInfo) == "function" then
        return select(3, GetItemInfo(link))
    end

    if C_Item and type(C_Item.GetItemInfo) == "function" then
        return select(3, C_Item.GetItemInfo(link))
    end

    return nil
end

local function ApplyMerchantItemQualityColors()
    for index = 1, MERCHANT_EXPANDED_ITEMS_PER_PAGE do
        local itemButton = GetMerchantItemButton(index)
        local itemName = _G["MerchantItem" .. index .. "Name"]
        if itemButton and itemName then
            local link = itemButton.link
            local quality = GetItemQualityFromLink(link)
            local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
            if color then
                itemName:SetTextColor(color.r, color.g, color.b)
            else
                itemName:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
            end
        end
    end
end

function KnownItems:IsKnownCollectibleCached(itemLink)
    if not itemLink then
        return false
    end

    local cached = self.cache[itemLink]
    if cached ~= nil then
        return cached == self.cacheTrue
    end

    local itemAPI = YUI.API and YUI.API.Item
    if not itemAPI or type(itemAPI.IsKnownCollectible) ~= "function" then
        return false
    end

    local known, resolved = itemAPI.IsKnownCollectible(itemLink)
    if resolved == true then
        self.cache[itemLink] = known == true and self.cacheTrue or self.cacheFalse
    end
    return known == true
end

function KnownItems:ColorMerchantItem(button, itemLink, isPurchasable, isUsable, numAvailable)
    if not button or not itemLink or isPurchasable ~= true or isUsable ~= true or numAvailable == 0 then
        return
    end
    if button.IsShown and not button:IsShown() then
        return
    end
    if not self:IsKnownCollectibleCached(itemLink) then
        return
    end

    local r, g, b = self:GetColor()
    if type(SetItemButtonTextureVertexColor) == "function" then
        SetItemButtonTextureVertexColor(button, r, g, b)
        return
    end

    local icon = button.icon or button.Icon
    if not icon and button.GetName then
        icon = _G[button:GetName() .. "IconTexture"]
    end
    if icon and icon.SetVertexColor then
        icon:SetVertexColor(r, g, b)
    end
end

function KnownItems:Refresh()
    if not self:IsEnabled() or not MerchantFrame
        or (MerchantFrame.IsShown and not MerchantFrame:IsShown())
    then
        return
    end

    if MerchantFrame.selectedTab == 2 then
        if type(GetNumBuybackItems) ~= "function" or type(GetBuybackItemInfo) ~= "function"
            or type(GetBuybackItemLink) ~= "function"
        then
            return
        end

        local numItems = GetNumBuybackItems() or 0
        local pageSize = tonumber(BUYBACK_ITEMS_PER_PAGE) or 0
        for slot = 1, math.min(numItems, pageSize) do
            local button = GetMerchantItemButton(slot)
            local _, _, _, _, numAvailable, isUsable = GetBuybackItemInfo(slot)
            self:ColorMerchantItem(button, GetBuybackItemLink(slot), true, isUsable, numAvailable)
        end
        return
    end

    if type(GetMerchantNumItems) ~= "function" or type(GetMerchantItemLink) ~= "function" then
        return
    end

    local numItems = GetMerchantNumItems() or 0
    local pageSize = tonumber(MERCHANT_ITEMS_PER_PAGE) or MERCHANT_NATIVE_ITEMS_PER_PAGE
    if pageSize < 1 then return end
    local page = tonumber(MerchantFrame.page) or 1
    local firstIndex = ((page - 1) * pageSize) + 1
    local visibleCount = math.min(pageSize, math.max(0, numItems - firstIndex + 1))
    for slot = 1, visibleCount do
        local merchantIndex = firstIndex + slot - 1
        local _, _, _, _, numAvailable, _, _, isPurchasable, isUsable = GetMerchantInfoForIndex(merchantIndex)
        self:ColorMerchantItem(
            GetMerchantItemButton(slot),
            GetMerchantItemLink(merchantIndex),
            isPurchasable,
            isUsable,
            numAvailable
        )
    end
end

local function RefreshMerchantFrameExtension()
    if not IsMerchantFrameEnabled() or not IsMerchantFrameVisible() then
        return
    end

    ApplyMerchantPageSize()
    EnsureMerchantExtraItems()
    if YUI.IsRetail or YUI.IsForever then
        ApplyRetailMerchantFrameSize()
    else
        ApplyMerchantFrameSize()
    end

    if MerchantFrame.selectedTab == 1 then
        if YUI.IsRetail or YUI.IsForever then
            ApplyRetailMerchantPageLayout()
        else
            ApplyMerchantPageLayout()
        end
    else
        if YUI.IsRetail or YUI.IsForever then
            ApplyRetailMerchantBuybackLayout()
        else
            ApplyMerchantBuybackLayout()
        end
    end

    ApplyMerchantItemQualityColors()
end

function KnownItems.RefreshMerchantInfoEnhancements()
    RefreshMerchantFrameExtension()
    KnownItems:Refresh()
end

local function ScheduleMerchantRefresh()
    if merchantRefreshScheduled or not IsMerchantFrameEnabled() or not IsMerchantFrameVisible() then
        return
    end

    merchantRefreshScheduled = true
    local function Run()
        merchantRefreshScheduled = false
        RefreshMerchantFrameExtension()
    end

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, Run)
    else
        Run()
    end
end

local function InstallMerchantHooks()
    if merchantHooksInstalled or type(hooksecurefunc) ~= "function" then
        return
    end

    if type(MerchantFrame_UpdateMerchantInfo) == "function" then
        hooksecurefunc("MerchantFrame_UpdateMerchantInfo", KnownItems.RefreshMerchantInfoEnhancements)
    end
    if type(MerchantFrame_UpdateBuybackInfo) == "function" then
        hooksecurefunc("MerchantFrame_UpdateBuybackInfo", KnownItems.RefreshMerchantInfoEnhancements)
    end
    if type(MerchantFrame_UpdateRepairButtons) == "function" then
        hooksecurefunc("MerchantFrame_UpdateRepairButtons", RefreshMerchantFrameExtension)
    end
    if type(MerchantFrame_UpdateItemQualityBorders) == "function" then
        hooksecurefunc("MerchantFrame_UpdateItemQualityBorders", RefreshMerchantFrameExtension)
    end

    merchantHooksInstalled = true
end

local function ApplyMerchantFrameFeature()
    if not IsMerchantFrameEnabled() or not MerchantFrame then
        return
    end

    ApplyMerchantPageSize()
    EnsureMerchantExtraItems()
    if YUI.IsRetail or YUI.IsForever then
        ApplyRetailMerchantFrameSize()
    else
        ApplyMerchantFrameSize()
    end
    InstallMerchantHooks()

    merchantFrameApplied = true
    if MerchantFrame:IsShown() and type(MerchantFrame_Update) == "function" then
        MerchantFrame_Update()
    end
    ScheduleMerchantRefresh()
end

local function ApplyBatchBuyFeature()
    if IsBatchBuyEnabled() then
        InstallBatchBuyHooks()
    end
end

local JunkSeller = (function()
local ItemAPI = (YUI.API and YUI.API.Item) or YUI.WOW_API or {}
local JUNK_SELL_QUIET_DELAY = 0.75
local JUNK_SELL_MAX_QUIET_PASSES = 8
local JUNK_SELL_QUEUE_INTERVAL = 0.2
local JUNK_SELL_QUEUE_MAX_RETRIES = 3
local JUNK_SELL_NATIVE_BASE_DELAY = 0.4
local JUNK_SELL_NATIVE_MAX_DELAY = 1.6
local JUNK_SELL_NATIVE_MAX_PASSES = 12
local JUNK_SELL_NATIVE_MAX_STALLS = 3
local ITEM_QUALITY_POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or LE_ITEM_QUALITY_POOR or 0
local ITEM_CLASS_QUEST = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or LE_ITEM_CLASS_QUESTITEM or 12
local ITEM_BIND_QUEST = (Enum and Enum.ItemBind and Enum.ItemBind.Quest) or 4
local BAG_FLAG_EXCLUDE_JUNK = (Enum and Enum.BagSlotFlags and Enum.BagSlotFlags.ExcludeJunkSell) or 64

local function GetContainerNumSlotsSafe(bag)
    local container = _G.C_Container
    local getter = container and container.GetContainerNumSlots or _G.GetContainerNumSlots
    if type(getter) ~= "function" then return 0 end
    local ok, count = pcall(getter, bag)
    count = ok and tonumber(count) or nil
    return count and math.max(0, math.floor(count)) or 0
end

local function GetContainerItemInfoSafe(bag, slot)
    local container = _G.C_Container
    if container and type(container.GetContainerItemInfo) == "function" then
        local ok, info = pcall(container.GetContainerItemInfo, bag, slot)
        if ok and type(info) == "table" then
            return info
        end
        return nil
    end

    if type(_G.GetContainerItemInfo) ~= "function" then return nil end
    local ok, texture, stackCount, isLocked, quality, isReadable, hasLoot, hyperlink,
        isFiltered, hasNoValue, itemID, isBound = pcall(_G.GetContainerItemInfo, bag, slot)
    if not ok or not texture then return nil end
    local resolvedItemID = itemID
    if not resolvedItemID and type(hyperlink) == "string" then
        resolvedItemID = tonumber(hyperlink:match("item:(%d+)"))
    end
    return {
        iconFileID = texture,
        stackCount = stackCount,
        isLocked = isLocked,
        quality = quality,
        isReadable = isReadable,
        hasLoot = hasLoot,
        hyperlink = hyperlink,
        isFiltered = isFiltered,
        hasNoValue = hasNoValue,
        itemID = resolvedItemID,
        isBound = isBound,
    }
end

local function IsBagExcludedFromJunkSale(bag)
    local container = _G.C_Container
    local getter = container and container.GetBagSlotFlag or _G.GetBagSlotFlag
    if type(getter) ~= "function" then return false end
    local ok, excluded = pcall(getter, bag, BAG_FLAG_EXCLUDE_JUNK)
    return ok and excluded == true
end

local function UseContainerItemSafe(bag, slot)
    local container = _G.C_Container
    local useItem = container and container.UseContainerItem or _G.UseContainerItem
    if type(useItem) ~= "function" then return false end
    return pcall(useItem, bag, slot)
end

local function GetJunkItemDetails(itemInfo)
    local key = itemInfo.hyperlink or itemInfo.itemID
    if not key then return nil end

    if type(ItemAPI.GetInfo) == "function" then
        local ok, details = pcall(ItemAPI.GetInfo, key)
        if ok and type(details) == "table" then
            return details
        end
    end

    if type(_G.GetItemInfo) ~= "function" then return nil end
    local ok, name, link, quality, level, minLevel, itemType, itemSubType, stackCount,
        equipLoc, texture, sellPrice, classID, subclassID, bindType = pcall(_G.GetItemInfo, key)
    if not ok or not name then return nil end
    return {
        name = name,
        link = link,
        quality = quality,
        level = level,
        minLevel = minLevel,
        type = itemType,
        subType = itemSubType,
        stackCount = stackCount,
        equipLoc = equipLoc,
        texture = texture,
        sellPrice = sellPrice,
        classID = classID,
        subclassID = subclassID,
        bindType = bindType,
    }
end

local function ReadJunkCandidate(bag, slot)
    local info = GetContainerItemInfoSafe(bag, slot)
    if not info or not info.itemID then return nil, "empty" end

    local quality = tonumber(info.quality)
    if quality == nil then return nil, "unknown", info.itemID end
    if quality ~= ITEM_QUALITY_POOR or info.hasNoValue == true then return nil, "ineligible", info.itemID end

    local details = GetJunkItemDetails(info)
    if not details then return nil, "unknown", info.itemID end
    local detailQuality = tonumber(details.quality)
    if detailQuality ~= nil and detailQuality ~= ITEM_QUALITY_POOR then return nil, "ineligible", info.itemID end
    if tonumber(details.classID) == ITEM_CLASS_QUEST or tonumber(details.bindType) == ITEM_BIND_QUEST then
        return nil, "ineligible", info.itemID
    end

    local unitPrice = tonumber(details.sellPrice)
    if not unitPrice then return nil, "unknown", info.itemID end
    if unitPrice <= 0 then return nil, "ineligible", info.itemID end
    if info.isLocked == true then return nil, "locked", info.itemID end

    local stackCount = math.max(1, math.floor(tonumber(info.stackCount) or 1))
    return {
        bag = bag,
        slot = slot,
        itemID = info.itemID,
        stackCount = stackCount,
        unitPrice = unitPrice,
        totalPrice = unitPrice * stackCount,
    }
end

local function ScanJunkCandidates(collect)
    local result = {
        candidates = collect and {} or nil,
        slotCount = 0,
        itemCount = 0,
        totalValue = 0,
        unknown = 0,
        locked = 0,
    }
    local firstBag = tonumber(_G.BACKPACK_CONTAINER) or 0
    local lastBag = tonumber(_G.NUM_BAG_SLOTS) or 4

    for bag = firstBag, lastBag do
        if not IsBagExcludedFromJunkSale(bag) then
            local slots = GetContainerNumSlotsSafe(bag)
            for slot = 1, slots do
                local candidate, reason = ReadJunkCandidate(bag, slot)
                if candidate then
                    result.slotCount = result.slotCount + 1
                    result.itemCount = result.itemCount + candidate.stackCount
                    result.totalValue = result.totalValue + candidate.totalPrice
                    if result.candidates then
                        result.candidates[#result.candidates + 1] = candidate
                    end
                elseif reason == "unknown" then
                    result.unknown = result.unknown + 1
                elseif reason == "locked" then
                    result.locked = result.locked + 1
                end
            end
        end
    end

    return result
end

local Seller = {
    generation = 0,
    merchantOpen = false,
    phase = "idle",
    activityRevision = 0,
    soldCount = 0,
    soldValue = 0,
}

function Seller:IsEnabled()
    return isFeatureEnabled and GetDB().autoSellJunk == true
end

function Seller:CancelTimer()
    local timer = self.timer
    self.timer = nil
    self.timerSerial = (self.timerSerial or 0) + 1
    if timer and type(timer.Cancel) == "function" then
        pcall(timer.Cancel, timer)
    end
end

function Seller:Schedule(delay, callback)
    self:CancelTimer()
    local timerAPI = _G.C_Timer
    if type(timerAPI) ~= "table" then return false end

    local generation = self.generation
    local timerSerial = self.timerSerial
    local function Run()
        if generation ~= self.generation or timerSerial ~= self.timerSerial then return end
        self.timer = nil
        callback(self)
    end

    if type(timerAPI.NewTimer) == "function" then
        self.timer = timerAPI.NewTimer(delay, Run)
        return self.timer ~= nil
    end
    if type(timerAPI.After) == "function" then
        timerAPI.After(delay, Run)
        return true
    end
    return false
end

function Seller:ResetRuntime(merchantOpen)
    self:CancelTimer()
    self.generation = self.generation + 1
    self.merchantOpen = merchantOpen == true
    self.phase = "idle"
    self.queue = nil
    self.queueIndex = nil
    self.queueRetry = nil
    self.pendingCandidate = nil
    self.quietPasses = nil
    self.observedRevision = nil
    self.nativePasses = nil
    self.nativeStalls = nil
    self.nativeDelay = nil
    self.nativePreviousCount = nil
    self.nativePreviousValue = nil
    self.nativeCanReportTotals = nil
    self.soldCount = 0
    self.soldValue = 0
end

function Seller:CanContinue()
    return self.merchantOpen and self:IsEnabled()
end

function Seller:PrintResults(remaining)
    if self.soldCount > 0 and self.nativeCanReportTotals ~= false and type(YUI.Print) == "function" then
        YUI:Print(string.format(
            T("settings.general.feature.trade_enhancement.auto_sell_junk.summary"),
            self.soldCount,
            FormatMoneyText(self.soldValue)
        ))
    end
    if remaining and remaining.itemCount > 0 and type(YUI.Print) == "function" then
        YUI:Print(string.format(
            T("settings.general.feature.trade_enhancement.auto_sell_junk.incomplete"),
            remaining.itemCount
        ))
    end
end

function Seller:Finish(remaining)
    self:CancelTimer()
    self:PrintResults(remaining)
    self.phase = "idle"
    self.queue = nil
    self.pendingCandidate = nil
end

function Seller:RecordNativeProgress(snapshot)
    -- An unresolved slot can disappear from the scan without having been sold.
    if YUI.IsForever and (snapshot.unknown > 0 or snapshot.locked > 0) then
        return false
    end
    local previousCount = self.nativePreviousCount or snapshot.itemCount
    local previousValue = self.nativePreviousValue or snapshot.totalValue
    local countDelta = math.max(0, previousCount - snapshot.itemCount)
    local valueDelta = math.max(0, previousValue - snapshot.totalValue)
    if countDelta > 0 then self.soldCount = self.soldCount + countDelta end
    if valueDelta > 0 then self.soldValue = self.soldValue + valueDelta end
    self.nativePreviousCount = snapshot.itemCount
    self.nativePreviousValue = snapshot.totalValue
    return countDelta > 0 or valueDelta > 0
end

function Seller:RunNativePass()
    if not self:CanContinue() or self.phase ~= "native" then
        self:ResetRuntime(false)
        return
    end

    local snapshot = ScanJunkCandidates(false)
    local progressed = self:RecordNativeProgress(snapshot)
    if snapshot.slotCount == 0 and snapshot.unknown == 0 and snapshot.locked == 0 then
        self:Finish()
        return
    end

    if progressed then
        self.nativeStalls = 0
        self.nativeDelay = JUNK_SELL_NATIVE_BASE_DELAY
    else
        self.nativeStalls = (self.nativeStalls or 0) + 1
        self.nativeDelay = math.min((self.nativeDelay or JUNK_SELL_NATIVE_BASE_DELAY) * 2, JUNK_SELL_NATIVE_MAX_DELAY)
    end

    if (self.nativePasses or 0) >= JUNK_SELL_NATIVE_MAX_PASSES
        or self.nativeStalls >= JUNK_SELL_NATIVE_MAX_STALLS
    then
        self:Finish(snapshot)
        return
    end

    if snapshot.slotCount > 0 or (YUI.IsForever and (snapshot.unknown > 0 or snapshot.locked > 0)) then
        local merchantAPI = _G.C_MerchantFrame
        local sellAll = merchantAPI and merchantAPI.SellAllJunkItems
        if type(sellAll) ~= "function" or not pcall(sellAll) then
            self:Finish(snapshot)
            return
        end
        self.nativePasses = (self.nativePasses or 0) + 1
    end
    self:Schedule(self.nativeDelay, Seller.RunNativePass)
end

function Seller:StartNative(snapshot)
    self.phase = "native"
    -- Missing initial item data prevents a complete count/value summary.
    self.nativeCanReportTotals = not YUI.IsForever or (snapshot.unknown == 0 and snapshot.locked == 0)
    self.nativePasses = 1
    self.nativeStalls = 0
    self.nativeDelay = JUNK_SELL_NATIVE_BASE_DELAY
    self.nativePreviousCount = snapshot.itemCount
    self.nativePreviousValue = snapshot.totalValue
    local merchantAPI = _G.C_MerchantFrame
    local sellAll = merchantAPI and merchantAPI.SellAllJunkItems
    if type(sellAll) ~= "function" or not pcall(sellAll) then
        self:Finish(snapshot)
        return
    end
    self:Schedule(self.nativeDelay, Seller.RunNativePass)
end

function Seller:AdvanceQueue()
    self.queueIndex = (self.queueIndex or 1) + 1
    self.queueRetry = 0
    self.pendingCandidate = nil
    self:RunQueueStep()
end

function Seller:VerifyQueueCandidate()
    if not self:CanContinue() or self.phase ~= "queue" then
        self:ResetRuntime(false)
        return
    end

    local before = self.pendingCandidate
    if not before then
        self:AdvanceQueue()
        return
    end

    local current, reason, currentItemID = ReadJunkCandidate(before.bag, before.slot)
    if not current and currentItemID == before.itemID and (reason == "unknown" or reason == "locked") then
        self.queueRetry = (self.queueRetry or 0) + 1
        if self.queueRetry < JUNK_SELL_QUEUE_MAX_RETRIES then
            self:Schedule(JUNK_SELL_QUEUE_INTERVAL, Seller.VerifyQueueCandidate)
        else
            self:AdvanceQueue()
        end
        return
    end
    if not current or current.itemID ~= before.itemID then
        if currentItemID == before.itemID then
            self:AdvanceQueue()
            return
        end
        self.soldCount = self.soldCount + before.stackCount
        self.soldValue = self.soldValue + before.totalPrice
        self:AdvanceQueue()
        return
    end

    if current.stackCount < before.stackCount then
        local sold = before.stackCount - current.stackCount
        self.soldCount = self.soldCount + sold
        self.soldValue = self.soldValue + sold * before.unitPrice
        self.queueRetry = 0
    else
        self.queueRetry = (self.queueRetry or 0) + 1
    end

    if self.queueRetry >= JUNK_SELL_QUEUE_MAX_RETRIES then
        self:AdvanceQueue()
        return
    end

    self.pendingCandidate = current
    if not UseContainerItemSafe(current.bag, current.slot) then
        self.queueRetry = self.queueRetry + 1
    end
    self:Schedule(JUNK_SELL_QUEUE_INTERVAL, Seller.VerifyQueueCandidate)
end

function Seller:RunQueueStep()
    if not self:CanContinue() or self.phase ~= "queue" then
        self:ResetRuntime(false)
        return
    end

    while self.queue and self.queueIndex <= #self.queue do
        local queued = self.queue[self.queueIndex]
        local current, reason = ReadJunkCandidate(queued.bag, queued.slot)
        if current and current.itemID == queued.itemID then
            self.pendingCandidate = current
            if UseContainerItemSafe(current.bag, current.slot) then
                self:Schedule(JUNK_SELL_QUEUE_INTERVAL, Seller.VerifyQueueCandidate)
                return
            end
            self.queueRetry = (self.queueRetry or 0) + 1
            if self.queueRetry < JUNK_SELL_QUEUE_MAX_RETRIES then
                self:Schedule(JUNK_SELL_QUEUE_INTERVAL, Seller.RunQueueStep)
                return
            end
        elseif reason == "unknown" or reason == "locked" then
            self.queueRetry = (self.queueRetry or 0) + 1
            if self.queueRetry < JUNK_SELL_QUEUE_MAX_RETRIES then
                self:Schedule(JUNK_SELL_QUEUE_INTERVAL, Seller.RunQueueStep)
                return
            end
        end

        self.queueIndex = self.queueIndex + 1
        self.queueRetry = 0
        self.pendingCandidate = nil
    end

    self:Finish(ScanJunkCandidates(false))
end

function Seller:StartQueue(snapshot)
    self.phase = "queue"
    self.queue = snapshot.candidates or {}
    self.queueIndex = 1
    self.queueRetry = 0
    self:RunQueueStep()
end

function Seller:ObserveQuietPeriod()
    if not self:CanContinue() or self.phase ~= "observe" then
        self:ResetRuntime(false)
        return
    end

    self.quietPasses = (self.quietPasses or 0) + 1
    if self.observedRevision ~= self.activityRevision then
        self.observedRevision = self.activityRevision
        if self.quietPasses < JUNK_SELL_MAX_QUIET_PASSES then
            self:Schedule(JUNK_SELL_QUIET_DELAY, Seller.ObserveQuietPeriod)
        else
            self:Finish()
        end
        return
    end

    local snapshot = ScanJunkCandidates(true)
    if snapshot.slotCount == 0 and snapshot.unknown == 0 and snapshot.locked == 0 then
        self:Finish()
        return
    end
    if snapshot.unknown > 0 or snapshot.locked > 0 then
        if self.quietPasses < JUNK_SELL_MAX_QUIET_PASSES then
            self:Schedule(JUNK_SELL_QUIET_DELAY, Seller.ObserveQuietPeriod)
        else
            self:Finish()
        end
        return
    end

    local merchantAPI = _G.C_MerchantFrame
    if YUI.IsRetail and merchantAPI and type(merchantAPI.SellAllJunkItems) == "function" then
        self:StartNative(snapshot)
    else
        self:StartQueue(snapshot)
    end
end

function Seller:Start()
    self:ResetRuntime(false)
    self.merchantOpen = true
    if not self:IsEnabled() then return end

    -- Forever supports native bulk selling even while Lua item details are pending.
    -- Let the client select sellable junk; local scans only track progress/retries.
    local merchantAPI = _G.C_MerchantFrame
    if YUI.IsForever and merchantAPI and type(merchantAPI.SellAllJunkItems) == "function" then
        self:StartNative(ScanJunkCandidates(false))
        return
    end

    self.phase = "observe"
    self.quietPasses = 0
    self.observedRevision = self.activityRevision
    if not self:Schedule(JUNK_SELL_QUIET_DELAY, Seller.ObserveQuietPeriod) then
        self:ResetRuntime(false)
    end
end

function Seller:OnActivity()
    if self.merchantOpen and self.phase == "observe" then
        self.activityRevision = self.activityRevision + 1
    end
end

function Seller:Stop()
    self:ResetRuntime(false)
end

return Seller
end)()

local function OnMerchantEvent(event)
    if event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        KnownItems:InvalidateCache()
    end
    if event == "MERCHANT_SHOW" then
        JunkSeller:Start()
    elseif event == "MERCHANT_UPDATE" or event == "GET_ITEM_INFO_RECEIVED" then
        JunkSeller:OnActivity()
    end

    if event == "GET_ITEM_INFO_RECEIVED" then
        if not IsMerchantFrameVisible() then
            return
        end
        if RefreshOpenBatchBuyFrame then
            RefreshOpenBatchBuyFrame()
        end
        KnownItems:Refresh()
        return
    end

    if event ~= "MERCHANT_SHOW" and not IsMerchantFrameVisible() then
        return
    end

    ApplyBatchBuyFeature()
    if RefreshOpenBatchBuyFrame then
        RefreshOpenBatchBuyFrame()
    end

    if merchantFrameApplied then
        ScheduleMerchantRefresh()
    elseif IsMerchantFrameEnabled() then
        ApplyMerchantFrameFeature()
    end
    KnownItems:Refresh()
end

local function OnMerchantClosed()
    JunkSeller:Stop()
    KnownItems:InvalidateCache()
    DetachBatchBuyFrameEvents()
    if HideBatchBuyFrame then
        HideBatchBuyFrame()
    end
    StopBatchBuyQueue()
end

function KnownItems.OnBagUpdate()
    if not MerchantFrame or (MerchantFrame.IsShown and not MerchantFrame:IsShown()) then
        return
    end
    KnownItems:InvalidateCache()
    KnownItems:Refresh()
end

local function OnBagUpdateDelayed()
    JunkSeller:OnActivity()
    KnownItems.OnBagUpdate()
end

function KnownItems:RefreshFromSettings()
    self:InvalidateCache()
    if MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown()
        and type(MerchantFrame_Update) == "function"
    then
        MerchantFrame_Update()
    else
        self:Refresh()
    end
end

local function RecordTrade()
    if not UnitExists("NPC") then return end

    local rec = YUI.Trade.Record
    wipe(rec)

    rec.TargetName = GetUnitName("NPC", true)
    if not rec.TargetName then return end

    if rec.TargetName:match("-") then
        rec.TargetFullName = rec.TargetName
    else
        local realm = YUI.Player and type(YUI.Player.GetRealmName) == "function"
            and YUI.Player:GetRealmName()
            or nil
        rec.TargetFullName = type(realm) == "string" and realm ~= ""
            and (rec.TargetName .. "-" .. realm)
            or rec.TargetName
    end

    rec.PlayerTradeMoney = GetPlayerTradeMoney()
    rec.TargetTradeMoney = GetTargetTradeMoney()
    rec.PlayerItem = {}
    rec.TargetItem = {}

    for i = 1, MAX_TRADE_ITEMS do
        rec.PlayerItem[i] = NONE
        rec.TargetItem[i] = NONE
    end

    for i = 1, MAX_TRADE_ITEMS do
        local playerItemLink = GetTradePlayerItemLink(i)
        local targetItemLink = GetTradeTargetItemLink(i)

        if playerItemLink then
            local _, _, quantity = GetTradePlayerItemInfo(i)
            quantity = quantity or 1
            rec.PlayerItem[i] = { playerItemLink, quantity }
        end

        if targetItemLink then
            local _, _, quantity = GetTradeTargetItemInfo(i)
            quantity = quantity or 1
            rec.TargetItem[i] = { targetItemLink, quantity }
        end
    end
end

local function OpenBags()
    local Baganator = _G.Baganator
    if Baganator and Baganator.CallbackRegistry then
        Baganator.CallbackRegistry:TriggerEvent("BagShow")
    end
end

local function CloseBags()
    local Baganator = _G.Baganator
    if Baganator and Baganator.CallbackRegistry then
        Baganator.CallbackRegistry:TriggerEvent("BagHide")
    end
end

local function OnTradeEvent(event)
    if event ~= "TRADE_CLOSED" and event ~= "GET_ITEM_INFO_RECEIVED" and IsOptionEnabled("tradeWhisper") then
        RecordTrade()
    end

    if event == "TRADE_SHOW" and IsOptionEnabled("autoBag") then
        OpenBags()
    elseif event == "TRADE_CLOSED" and IsOptionEnabled("autoBag") then
        CloseBags()
    end
end

local function MergeItem(list, key, num)
    for i = 1, #list do
        if list[i][1] == key then
            list[i][2] = list[i][2] + num
            return
        end
    end
    list[#list + 1] = { key, num }
end

local function AppendItems(target, items)
    for i = 1, #items do
        local item = items[i][1]
        local num = items[i][2]
        if num > 1 then
            target[#target + 1] = string.format("%sx%s", item, num)
        else
            target[#target + 1] = item
        end
    end
end

local function SendTradeReport()
    if not IsOptionEnabled("tradeWhisper") then return end

    local rec = YUI.Trade.Record
    if not rec or not rec.TargetName then return end
    if Social.IsFriend and Social.IsFriend(rec.TargetName) then return end

    local sentItems = {}
    local receivedItems = {}
    local sentMerged = {}
    local receivedMerged = {}

    if rec.PlayerTradeMoney and rec.PlayerTradeMoney > 0 then
        sentItems[#sentItems + 1] = rec.PlayerTradeMoney / 10000 .. "G"
    end

    if rec.TargetTradeMoney and rec.TargetTradeMoney > 0 then
        receivedItems[#receivedItems + 1] = rec.TargetTradeMoney / 10000 .. "G"
    end

    for i = 1, MAX_TRADE_ITEMS do
        local playerItem = rec.PlayerItem and rec.PlayerItem[i]
        if type(playerItem) == "table" then
            MergeItem(sentMerged, playerItem[1], playerItem[2] or 1)
        end

        local targetItem = rec.TargetItem and rec.TargetItem[i]
        if type(targetItem) == "table" then
            MergeItem(receivedMerged, targetItem[1], targetItem[2] or 1)
        end
    end

    AppendItems(sentItems, sentMerged)
    AppendItems(receivedItems, receivedMerged)

    if #sentItems == 0 then return end

    local sentMsg = "交出" .. table.concat(sentItems, " ")
    local receivedMsg = #receivedItems > 0 and ("收到" .. table.concat(receivedItems, " ")) or ""
    local sep = #receivedItems > 0 and ", " or ""
    local message = string.format(TRADE_MSG_TMPL, rec.TargetName, sentMsg, sep, receivedMsg)
    SendChatMessage(message, "WHISPER", nil, rec.TargetName)
end

local function OnUIInfoMessage(event, ...)
    if event ~= "UI_INFO_MESSAGE" then return end

    local _, msg = ...
    if msg == ERR_TRADE_COMPLETE then
        SendTradeReport()
    end
end

local function GetStaticPopupDialog(which)
    if type(StaticPopup_FindVisible) == "function" then
        local dialog = StaticPopup_FindVisible(which)
        if dialog then
            return dialog
        end
    end

    if type(StaticPopup_Visible) == "function" then
        local first, second = StaticPopup_Visible(which)
        if type(first) == "table" then
            return first
        end
        if type(second) == "table" then
            return second
        end
    end

    for index = 1, 4 do
        local dialog = _G["StaticPopup" .. index]
        if dialog and dialog.IsShown and dialog:IsShown() and dialog.which == which then
            return dialog
        end
    end

    return nil
end

local function GetStaticPopupEditBox(dialog)
    if not dialog then
        return nil
    end

    if type(dialog.GetEditBox) == "function" then
        local editBox = dialog:GetEditBox()
        if editBox then
            return editBox
        end
    end

    if dialog.editBox then
        return dialog.editBox
    end
    if dialog.EditBox then
        return dialog.EditBox
    end

    local name = dialog.GetName and dialog:GetName()
    if name then
        return _G[name .. "EditBox"]
    end

    return nil
end

local function FillDeleteConfirmationText()
    autoDeleteScheduled = false
    if not IsOptionEnabled("autoDelete") then
        return
    end

    local confirmText = DELETE_ITEM_CONFIRM_STRING or "DELETE"
    for _, which in ipairs(DELETE_CONFIRM_POPUPS) do
        local dialog = GetStaticPopupDialog(which)
        local editBox = GetStaticPopupEditBox(dialog)
        if editBox and editBox.SetText and (not editBox.IsShown or editBox:IsShown()) then
            editBox:SetText(confirmText)
            if editBox.SetCursorPosition then
                editBox:SetCursorPosition(#confirmText)
            end
            return
        end
    end
end

local function OnDeleteItemConfirm()
    if autoDeleteScheduled or not IsOptionEnabled("autoDelete") then
        return
    end

    autoDeleteScheduled = true
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0.1, FillDeleteConfirmationText)
    else
        FillDeleteConfirmationText()
    end
end

local function OnEnable(enable)
    isFeatureEnabled = enable == true
    if isFeatureEnabled then
        InstallMerchantHooks()
        if IsMerchantFrameVisible() then
            ApplyMerchantFrameFeature()
        end
        ApplyBatchBuyFeature()
        KnownItems:Refresh()
        if MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() then
            JunkSeller:Start()
        end
    else
        JunkSeller:Stop()
        KnownItems:InvalidateCache()
        DetachBatchBuyFrameEvents()
        if HideBatchBuyFrame then
            HideBatchBuyFrame()
        end
        StopBatchBuyQueue()
        if MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown()
            and type(MerchantFrame_Update) == "function"
        then
            MerchantFrame_Update()
        end
    end
end

local Feature = {
    product = PRODUCT_ID,
    localeNamespace = "Core",
    nameKey = "settings.general.feature.trade_enhancement.label",
    descriptionKey = "settings.general.feature.trade_enhancement.text",
    name = T("settings.general.feature.trade_enhancement.label"),
    description = T("settings.general.feature.trade_enhancement.text"),
    default = true,
    callback = OnEnable,
    GetOptions = function()
        local db = GetDB()
        local sectionWidth = 620
        local optionWidth = 220
        local optionGap = 24
        local optionRowGap = 8
        local sliderRowWidth = 560
        local sliderLabelWidth = 150
        local sliderControlWidth = 310
        local sliderValueWidth = 76
        local firstRow = {
            {
                type = "checkbox",
                label = T("settings.general.feature.trade_enhancement.trade_whisper.label"),
                tooltip = T("settings.general.feature.trade_enhancement.trade_whisper.tooltip"),
                width = optionWidth,
                get = function() return db.tradeWhisper end,
                set = function(v) db.tradeWhisper = v == true end,
            },
            {
                type = "checkbox",
                label = T("settings.general.feature.trade_enhancement.auto_bag.label"),
                tooltip = T("settings.general.feature.trade_enhancement.auto_bag.tooltip"),
                width = optionWidth,
                get = function() return db.autoBag end,
                set = function(v) db.autoBag = v == true end,
            },
        }
        local secondRow = {
            {
                type = "checkbox",
                label = T("settings.general.feature.trade_enhancement.auto_delete.label"),
                tooltip = T("settings.general.feature.trade_enhancement.auto_delete.tooltip"),
                width = optionWidth,
                get = function() return db.autoDelete end,
                set = function(v) db.autoDelete = v == true end,
            },
            {
                type = "checkbox",
                label = T("settings.general.feature.trade_enhancement.auto_sell_junk.label"),
                tooltip = T("settings.general.feature.trade_enhancement.auto_sell_junk.tooltip"),
                width = optionWidth,
                get = function() return db.autoSellJunk end,
                set = function(v)
                    db.autoSellJunk = v == true
                    if db.autoSellJunk and MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() then
                        JunkSeller:Start()
                    elseif not db.autoSellJunk then
                        JunkSeller:Stop()
                    end
                end,
            },
        }
        local thirdRow = {}
        local fourthRow = {}

        if IsMerchantFrameSupported() then
            thirdRow[#thirdRow + 1] = {
                type = "checkbox",
                label = T("settings.general.feature.trade_enhancement.merchant_frame.label"),
                tooltip = T("settings.general.feature.trade_enhancement.merchant_frame.tooltip"),
                width = optionWidth,
                get = function() return db.merchantFrame end,
                set = function(v)
                    db.merchantFrame = v == true
                    if YUI.Settings and YUI.Settings.ShowReload then
                        YUI.Settings:ShowReload()
                    end
                    if db.merchantFrame and IsMerchantFrameVisible() then
                        ApplyMerchantFrameFeature()
                    end
                end,
            }
            thirdRow[#thirdRow + 1] = {
                type = "checkbox",
                hidden = YUI.IsForever == true,
                label = T("settings.general.feature.trade_enhancement.known_items.label"),
                tooltip = T("settings.general.feature.trade_enhancement.known_items.tooltip"),
                width = optionWidth,
                get = function() return db.knownItemTint end,
                set = function(v)
                    db.knownItemTint = v == true
                    KnownItems:RefreshFromSettings()
                end,
            }
            fourthRow[#fourthRow + 1] = {
                type = "color",
                hidden = YUI.IsForever == true,
                label = T("settings.general.feature.trade_enhancement.known_items.color"),
                tooltip = T("settings.general.feature.trade_enhancement.known_items.color_tooltip"),
                inlineLabel = true,
                width = optionWidth,
                field = true,
                hasAlpha = false,
                default = KnownItems.defaultColor,
                get = function()
                    return KnownItems:CopyColor(db.knownItemColor)
                end,
                set = function(value)
                    db.knownItemColor = KnownItems:CopyColor(value)
                    KnownItems:RefreshFromSettings()
                end,
            }
        end

        local options = {
            {
                type = "divider",
                label = T("settings.general.feature.trade_enhancement.section.general"),
                width = sectionWidth,
                alignLeft = true,
            },
            {
                type = "row",
                gap = optionGap,
                rowGap = optionRowGap,
                children = firstRow,
            },
            {
                type = "row",
                gap = optionGap,
                rowGap = optionRowGap,
                children = secondRow,
            },
        }

        if #thirdRow > 0 then
            options[#options + 1] = {
                type = "row",
                gap = optionGap,
                rowGap = optionRowGap,
                children = thirdRow,
            }
        end

        if #fourthRow > 0 then
            options[#options + 1] = {
                type = "row",
                gap = optionGap,
                rowGap = optionRowGap,
                children = fourthRow,
            }
        end

        local repairOptions = YUI.AutoRepair:GetOptions(sectionWidth)
        for i = 1, #repairOptions do options[#options + 1] = repairOptions[i] end

        if IsMerchantFrameSupported() then
            options[#options + 1] = {
                type = "divider",
                label = T("settings.general.feature.trade_enhancement.batch_buy.label"),
                width = sectionWidth,
                alignLeft = true,
                collapsible = true,
                collapseKey = "component.trade_enhancement.batch_buy",
                collapsed = false,
            }
            options[#options + 1] = {
                type = "checkbox",
                label = T("settings.general.feature.trade_enhancement.batch_buy.enable_label"),
                tooltip = T("settings.general.feature.trade_enhancement.batch_buy.tooltip"),
                width = optionWidth,
                rowGap = optionRowGap,
                get = function() return db.batchBuy end,
                set = function(v)
                    db.batchBuy = v == true
                    if db.batchBuy then
                        ApplyBatchBuyFeature()
                    else
                        DetachBatchBuyFrameEvents()
                        if HideBatchBuyFrame then
                            HideBatchBuyFrame()
                        end
                        StopBatchBuyQueue()
                    end
                end,
            }
            options[#options + 1] = {
                type = "slider",
                label = T("settings.general.feature.trade_enhancement.batch_buy_max_quantity.label"),
                tooltip = T("settings.general.feature.trade_enhancement.batch_buy_max_quantity.tooltip"),
                min = 1,
                max = 9999,
                step = 1,
                rowWidth = sliderRowWidth,
                labelWidth = sliderLabelWidth,
                controlWidth = sliderControlWidth,
                valueWidth = sliderValueWidth,
                inputWidth = sliderValueWidth,
                rowGap = optionRowGap,
                get = function()
                    return GetBatchBuyMaxQuantity()
                end,
                set = function(value)
                    db.batchBuyMaxQuantity = ClampInteger(value, 1, 9999, BATCH_BUY_DEFAULT_MAX_QUANTITY)
                end,
            }
            options[#options + 1] = {
                type = "slider",
                label = T("settings.general.feature.trade_enhancement.batch_buy_price_warning.label"),
                tooltip = T("settings.general.feature.trade_enhancement.batch_buy_price_warning.tooltip"),
                min = 0,
                max = 100000,
                step = 100,
                rowWidth = sliderRowWidth,
                labelWidth = sliderLabelWidth,
                controlWidth = sliderControlWidth,
                valueWidth = sliderValueWidth,
                inputWidth = sliderValueWidth,
                get = function()
                    return GetBatchBuyPriceWarningGold()
                end,
                set = function(value)
                    db.batchBuyPriceWarningGold = ClampInteger(value, 0, 100000, BATCH_BUY_DEFAULT_PRICE_WARNING_GOLD)
                end,
            }
        end

        return options
    end,
}

Components:RegisterFeature("TradeEnhancement", Feature)

YUI.Event:On("UI_INFO_MESSAGE", OnUIInfoMessage)
YUI.Event:On("TRADE_SHOW", OnTradeEvent)
YUI.Event:On("TRADE_CLOSED", OnTradeEvent)
YUI.Event:On("TRADE_UPDATE", OnTradeEvent)
YUI.Event:On("TRADE_ACCEPT_UPDATE", OnTradeEvent)
YUI.Event:On("TRADE_PLAYER_ITEM_CHANGED", OnTradeEvent)
YUI.Event:On("TRADE_TARGET_ITEM_CHANGED", OnTradeEvent)
YUI.Event:On("TRADE_MONEY_CHANGED", OnTradeEvent)
YUI.Event:On("GET_ITEM_INFO_RECEIVED", OnTradeEvent)
YUI.Event:On("MERCHANT_SHOW", OnMerchantEvent)
YUI.Event:On("MERCHANT_UPDATE", OnMerchantEvent)
YUI.Event:On("MERCHANT_CLOSED", OnMerchantClosed)
YUI.Event:On("GET_ITEM_INFO_RECEIVED", OnMerchantEvent)
YUI.Event:On("BAG_UPDATE_DELAYED", OnBagUpdateDelayed)
YUI.Event:On("DELETE_ITEM_CONFIRM", OnDeleteItemConfirm)
