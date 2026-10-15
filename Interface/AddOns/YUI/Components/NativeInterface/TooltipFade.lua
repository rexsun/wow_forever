local _, addonTable = ...
local YUI = _G.YUI or addonTable
local Native = YUI and YUI.NativeInterface
if not Native then return end

-- Keep the existing diagnostic command available after the component migration.
function Native:GetTooltipFadeDiagnostics()
    local controller = YUI._MouseEnhancementTooltipFade
    if controller then return controller.GetDiagnostics() end
    return { enabled = false, hooked = false, hookCount = 0, hideCount = 0, failureCount = 0, reason = "component-unavailable" }
end
