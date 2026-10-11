local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable

if not YUI or not YUI.IsRetail then return end

local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or YUI.ProductId or "suite"
if not PRODUCT_ID then return end

YUI.WorldEventTrackerNavigationFallbacks = {
    [8936] = { areaPoiID = 8936, uiMapID = 2512, positionX = 0.2640, positionY = 0.6480 },
    [8940] = { areaPoiID = 8940, uiMapID = 2512, positionX = 0.4699, positionY = 0.6223 },
    [8939] = { areaPoiID = 8939, uiMapID = 2512, positionX = 0.7130, positionY = 0.3138 },
    [8938] = { areaPoiID = 8938, uiMapID = 2512, positionX = 0.4470, positionY = 0.2593 },
    [8937] = { areaPoiID = 8937, uiMapID = 2512, positionX = 0.6716, positionY = 0.7752 },
}
