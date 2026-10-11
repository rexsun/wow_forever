local _, ns = ...

-- ! avoid conflict override
if ns.CONFLICT then return; end


local function ManageRaidIconsOptions()
    local activeCheckbox = ns.FindControl("ActiveRaidIcons")
    local headingLabel = ns.FindControl("LabelRaidIcons")
    local hideDisabledModules = ns.FindControl("HideDisabledModules")
    local isEnabled = ns.IsModuleEnabled(activeCheckbox, headingLabel, _G[ns.OPTIONS_NAME].ActiveRaidIcons, hideDisabledModules and hideDisabledModules:GetChecked())

    ns.OptionsSiblingsEnable(_G[ns.OPTIONS_NAME], activeCheckbox, isEnabled, .2)

end
K_SHARED_UI.AddRefreshOptions(ManageRaidIconsOptions)