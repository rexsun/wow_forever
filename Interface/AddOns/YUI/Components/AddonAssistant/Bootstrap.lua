local ADDON_NAME, addonTable = ...
local state = _G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME]
if state and not state.productEnabled then return end
local YUI = _G.YUI or addonTable
if not YUI or not (YUI.IsRetail or YUI.IsForever) or YUI.AddonAssistant then return end

YUI.AddonAssistant = {
    addonName = ADDON_NAME,
    product = YUI:GetAddonProductId(ADDON_NAME, "addon_assistant"),
    flavor = YUI.IsForever and "forever" or "mainline",
}
