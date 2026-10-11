local YUI = _G.YUI
if not YUI or not YUI.YActionBar then return end

local YAB = YUI.YActionBar
local SettingsBridge = {}
YAB.SettingsBridge = SettingsBridge

function SettingsBridge:Open(barId, group)
    local targetBarId = barId ~= nil and tostring(barId) or nil
    local opened
    local options
    if targetBarId then
        options = {
            afterOpen = function()
                local bridge = YUI.Settings and YUI.Settings.YActionBarModule
                if bridge and bridge.SelectBar then
                    bridge.SelectBar(targetBarId, true, group)
                end
            end,
        }
    end
    if YUI.Settings and YUI.Settings.OpenProduct then
        opened = YUI.Settings:OpenProduct(YAB.PRODUCT_ID, YAB.SETTINGS_ENTRY, options)
    elseif YUI.OpenSettings then
        opened = YUI:OpenSettings("YActionBar", YAB.PRODUCT_ID, options)
    end
    return opened
end

function SettingsBridge:Refresh()
    if YUI.Settings and YUI.Settings.Refresh then
        pcall(YUI.Settings.Refresh, YUI.Settings)
    end
end
