local ADDON_NAME = ...
local YUI = _G.YUI
local YMap = YUI and YUI.YMap
if not YMap then return end

local hosts = {
    suite = { productId = "suite", settingsMode = "navigation", savedVariable = "YUI_DB", legacyMigration = true },
    toolbox = { productId = "toolbox", settingsMode = "toolbox", savedVariable = "YUI_NovaToolbox_DB" },
}
local productId = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or YUI.ProductId or "suite"
YMap.Host = assert(hosts[productId], "Unsupported YMap host: " .. tostring(productId))

if YMap.Host.settingsMode == "toolbox" then
    YMap.Defaults.enabled = true
    YMap.Defaults.minimap.enabled = false
    YMap.Defaults.worldMap.enabled = false
end

if YMap.Host.settingsMode == "toolbox" then
    local function Placements()
        local db = YMap:GetDB()
        db.placements = db.placements or {}
        return db.placements
    end
    YMap.PlacementStorage = {
        identity = function() return Placements() end,
        get = function(_, id) return Placements()[id] end,
        set = function(_, id, placement) Placements()[id] = placement; return true end,
        clear = function(_, id) Placements()[id] = nil; return true end,
    }
end

if YUI.Assets and YUI.Assets.RegisterComponentRoot then
    YUI.Assets:RegisterComponentRoot("ymap", "Interface\\AddOns\\" .. ADDON_NAME .. "\\Products\\YMap\\Media")
end
