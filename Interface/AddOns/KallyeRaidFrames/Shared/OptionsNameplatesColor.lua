local _, ns = ...
local l = ns.I18N;

-- ! avoid conflict override
if ns.CONFLICT then return; end

local function ManageNameplatesOptions()
    local activeCheckbox = ns.FindControl("ActiveNameplatesColor")
    local headingLabel = ns.FindControl("LabelNameplatesColor")
    local hideDisabledModules = ns.FindControl("HideDisabledModules")
    local isEnabled = ns.IsModuleEnabled(activeCheckbox, headingLabel, _G[ns.OPTIONS_NAME].ActiveNameplatesColor, hideDisabledModules and hideDisabledModules:GetChecked())

    ns.OptionsSiblingsEnable(_G[ns.OPTIONS_NAME], activeCheckbox, isEnabled, .2)

    -- Dynamic colorWidget display
    local frameData = {
        ["FriendsNameplates_Txt_UseColor"] = { link = "FriendsNameplates_Txt_Color", classEnabled = true },
        ["FriendsNameplates_Bar_UseColor"] = { link = "FriendsNameplates_Bar_Color", classEnabled = not ns.HAS_colorNameBySelection },
        ["FriendsNameplates_Txt_ShowLevel"] = { link = "FriendsNameplates_Txt_Level_Color_Under", classEnabled = true },
        ["FriendsNameplates_Txt_ShowLevel "] = { link = "FriendsNameplates_Txt_Level_Color_Over", classEnabled = true },
        -- ["EnemiesNameplates_Txt_ShowLevel"] = { link = "EnemiesNameplates_Txt_Level_Color_Over", classEnabled = true },
        ["EnemiesNameplates_Txt_UseColor"] = { link = "EnemiesNameplates_Txt_Color", classEnabled = true },
        ["EnemiesNameplates_Bar_UseColor"] = { link = "EnemiesNameplates_Bar_Color", classEnabled = not ns.HAS_colorNameBySelection },
        ["EnemiesNameplates_Txt_ShowLevel"] = { link = "EnemiesNameplates_Txt_Level_Color_Under", classEnabled = true },
        ["EnemiesNameplates_Txt_ShowLevel "] = { link = "EnemiesNameplates_Txt_Level_Color_Over", classEnabled = true },
    }
    for frameName, data in pairs(frameData) do
        local dropDownWidget = ns.FindControl(gsub(frameName, " ", ""))
        local colorWidget = ns.FindControl(data.link)
        if not data.classEnabled then
            dropDownWidget:SetAttribute("disabled2", "true")
        end
        if (dropDownWidget:GetValue() ~= nil) then
            ns.OptionsSetShownAndEnable(colorWidget, isEnabled and (dropDownWidget:GetValue()%10 == 2),  isEnabled)
        end
    end

    -- Add icons on texts (pvpIcons[value])
    frameData = {
        ["FriendsNameplates_PvpIcon"] = "",
        ["EnemiesNameplates_PvpIcon"] = "",
    }
    for frameName, _ in pairs(frameData) do
        local dropDownWidget = ns.FindControl(frameName)
        if not dropDownWidget._iconsSet and ns.pvpIcons then
            dropDownWidget._iconsSet = true

            local i = 1
            while(dropDownWidget:GetAttribute("text"..i))
            do
                local key, val = dropDownWidget:GetAttribute("value"..i), dropDownWidget:GetAttribute("text"..i);
                if ns.pvpIcons[key] then
                    val = l[val] or _G[val] or val
                    dropDownWidget:SetAttribute("text"..i, val..ns.pvpIcons[key])
                end
                i=i+1;
            end
        end
    end
    ns.OptionsSiblingsEnable(_G[ns.OPTIONS_NAME], activeCheckbox, isEnabled, .2)
end
K_SHARED_UI.AddRefreshOptions(ManageNameplatesOptions)
