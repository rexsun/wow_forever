local YUI = _G.YUI
local S = YUI.Settings
local GUI2 = YUI.GUI2
local LC = YUI.Locale:Get("Core")
local SystemAPI = YUI.API and YUI.API.System or YUI.WOW_API

local function IsAddOnLoaded(addonName)
    if not addonName or not SystemAPI then return false end

    if SystemAPI.IsAddOnLoadedSafe then
        return SystemAPI.IsAddOnLoadedSafe(addonName) and true or false
    end

    if SystemAPI.IsAddOnLoaded then
        return SystemAPI.IsAddOnLoaded(addonName) and true or false
    end

    return false
end

local function ResolveNameplateRow(row)
    if IsAddOnLoaded("Plater") then
        return row
    end

    if IsAddOnLoaded("Platynator") then
        return {
            typeKey = row.typeKey,
            name = "Platynator",
            descKey = "settings.addon_list.desc.platynator",
            setting = "/platy",
        }
    end

    return row
end

-- 插件清单数据
local ADDON_LIST = {
    ["Retail"] = {
        { typeKey = "settings.addon_list.type.core", name = "|cFFFF00FFY|r|cFFFF6666U|r|cFFFF9900I|r", descKey = "settings.addon_list.desc.yui", setting = "/yui" },
        { typeKey = "settings.addon_list.type.ui", name = "ElvUI / NDUI", descKey = "settings.addon_list.desc.elvui_ndui", settingKey = "settings.addon_list.setting.ec_or_ndui" },
        { typeKey = "settings.addon_list.type.ui", name = "ToxiUI", descKey = "settings.addon_list.desc.toxiui", setting = "/ec - ToxiUI" },
        { typeKey = "settings.addon_list.type.nameplate", name = "Plater Nameplates", descKey = "settings.addon_list.desc.plater", setting = "/plater", resolve = ResolveNameplateRow },
        { typeKey = "settings.addon_list.type.tools", name = "ExwindTools", descKey = "settings.addon_list.desc.exwindtools", setting = "/ex" },
        { typeKey = "settings.addon_list.type.combat", name = "WarpDeplete", descKey = "settings.addon_list.desc.warpdeplete", setting = "/warp" },
        { typeKey = "settings.addon_list.type.config", name = "MurlokExport", descKey = "settings.addon_list.desc.murlokexport", setting = "/me" },
        { typeKey = "settings.addon_list.type.bags", name = "Baganator", descKey = "settings.addon_list.desc.baganator", setting = "/bgr" },
        { typeKey = "settings.addon_list.type.tools", name = "Plumber", descKey = "settings.addon_list.desc.plumber", setting = "/plumber" },
        { typeKey = "settings.addon_list.type.cosmetic", name = "Waypoint UI", descKey = "settings.addon_list.desc.waypoint", settingKey = "settings.addon_list.setting.esc_options_addons" },
        { typeKey = "settings.addon_list.type.assist", name = "Myslot", descKey = "settings.addon_list.desc.myslot", setting = "/myslot" },
    },
    ["Wrath"] = {
         -- 暂时留空或根据需要填充
         { typeKey = "settings.addon_list.type.notice", nameKey = "settings.addon_list.no_data", descKey = "settings.addon_list.desc.no_data_wrath", setting = "" },
    },
    ["Mists"] = {
         -- 暂时留空或根据需要填充
         { typeKey = "settings.addon_list.type.notice", nameKey = "settings.addon_list.no_data", descKey = "settings.addon_list.desc.no_data_mists", setting = "" },
    }
}

local function BuildRows(rows)
    local data = {}
    for _, sourceRow in ipairs(rows) do
        local row = sourceRow.resolve and sourceRow.resolve(sourceRow) or sourceRow
        table.insert(data, {
            type = row.typeKey and LC[row.typeKey] or row.type,
            name = row.nameKey and LC[row.nameKey] or row.name,
            desc = row.descKey and LC[row.descKey] or row.desc,
            setting = row.settingKey and LC[row.settingKey] or row.setting or "",
        })
    end
    return data
end

local function GetConfig()
    -- 根据当前游戏版本获取对应列表
    local data = ADDON_LIST[YUI.GameVersion] or ADDON_LIST["Retail"]
    
    -- 如果是未知版本，默认显示 Retail
    if not ADDON_LIST[YUI.GameVersion] then
         data = ADDON_LIST["Retail"]
    end

    local config = {
        { type = "header", label = LC["settings.addon_list.title"] },
        { type = "text", label = LC["settings.addon_list.desc"] },
        { type = "space", height = 5 },
        { 
            type = "table", 
            width = 650, 
            height = 350,
            rowHeight = 28,
            columns = {
                { name = LC["settings.addon_list.column.type"], key = "type", width = 70 },
                { name = LC["settings.addon_list.column.name"], key = "name", width = 180 },
                { name = LC["settings.addon_list.column.desc"], key = "desc", width = 250 },
                { name = LC["settings.addon_list.column.setting"], key = "setting", width = 100 },
            },
            data = BuildRows(data)
        },
    }
    
    return config
end

local function Render(parent)
    S:RenderConfig(parent, GetConfig())
end

S:RegisterModule("插件清单", "Interface\\Icons\\INV_Misc_Book_09", Render, {
    hidden = true,
    titleKey = "settings.modules.addon_list",
})
