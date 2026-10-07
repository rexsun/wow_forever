-- =============================================================================
-- DungeonsForever · LibHUI 存档桥接
-- LibHUI 内部经 addon.db 读取主题与设置数据，此处桥接到插件自身存档表，
-- 不新增额外的顶层 SavedVariables。必须在 LibHUI.xml 之前加载（见 Libs/embeds.xml）。
-- =============================================================================

local addonName, addon = ...

DungeonsForeverDB = DungeonsForeverDB or {}
DungeonsForeverDB.libHUI = DungeonsForeverDB.libHUI or {}

addon.db = DungeonsForeverDB.libHUI
addon.db.settings = addon.db.settings or {}

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    DungeonsForeverDB = DungeonsForeverDB or {}
    DungeonsForeverDB.libHUI = DungeonsForeverDB.libHUI or {}
    addon.db = DungeonsForeverDB.libHUI
    addon.db.settings = addon.db.settings or {}
end)
