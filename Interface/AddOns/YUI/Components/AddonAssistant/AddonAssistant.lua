local ADDON_NAME, addonTable = ...
local state = _G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME]
if state and not state.productEnabled then return end
local YUI = _G.YUI or addonTable
local A = YUI and YUI.AddonAssistant
if not A or not YUI.Components then return end
A.L = YUI.Locale:Get("AddonAssistant")

local function open()
    if not A.Runtime.active then YUI.Components:SetFeatureEnabled("AddonAssistant", true) end
    A.View:Show()
end

YUI.Components:RegisterFeature("AddonAssistant", {
    name = A.L.title, description = A.L.description, product = A.product,
    standalone = true, toolboxManaged = A.product == "suite" or A.product == "toolbox",
    default = false, settingsMode = "toggleOnly", order = 400.5, sourceRoot = "Components\\AddonAssistant",
    assetFolders = { "Components\\AddonAssistant\\Media" },
    modSwitchImage = "modswitch\\addonassistant-bg.png", modSwitchImageCrop = false,
    versions = { mainline = true, forever = true }, tags = { "实用功能" },
    callback = function(enabled) if enabled then A.Runtime:Enable() else A.Runtime:Disable() end end,
})

if YUI.Commands then
    YUI.Commands:Register({ id = "addon_assistant.open", productId = A.product, aliases = { "/yaa", "/yaddons" }, handler = open })
end

-- The compartment is optional; slash commands and the component page always work.
if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
    AddonCompartmentFrame:RegisterAddon({ text = A.L.title, icon = 134400, notCheckable = true, func = open })
end
