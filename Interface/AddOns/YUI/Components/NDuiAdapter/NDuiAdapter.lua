local ADDON_NAME, YUI = ...

local function IsNDuiLoaded()
    local addOns = _G.C_AddOns
    if not addOns or type(addOns.IsAddOnLoaded) ~= "function" then return false end
    local ok, loaded = pcall(addOns.IsAddOnLoaded, "NDui")
    return ok and loaded == true
end

-- 如果 NDui 未加载，则不注册此功能
if not IsNDuiLoaded() then return end

YUI.Components:RegisterFeature("NDuiAdapter", {
    name = "NDui 独家适配",
    default = true,
    requiresReload = true,
    description = "隐藏原生菜单、背包和社交按钮。",
    callback = function(enable)
        if not enable then return end

        -- 防御性编程：检查 NDui 是否加载
        if not IsNDuiLoaded() then return end

        -- 隐藏系统的菜单 背包 社交按钮
        if YUI.IsRetail then
            local hiddenFrame = CreateFrame("Frame")
            hiddenFrame:Hide()

            if MicroButtonAndBagsBar then
                MicroButtonAndBagsBar:SetParent(hiddenFrame)
                MicroButtonAndBagsBar:Hide()
            end

            if BagsBar then
                BagsBar:SetParent(hiddenFrame)
                BagsBar:Hide()
            end

            if MicroMenuContainer then
                MicroMenuContainer:SetParent(hiddenFrame)
                MicroMenuContainer:Hide()
            end

            if QuickJoinToastButton then
                QuickJoinToastButton:SetParent(hiddenFrame)
                QuickJoinToastButton:Hide()
            end
        end
    end
})
