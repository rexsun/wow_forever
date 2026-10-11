local YUI = _G.YUI
if not YUI or not YUI.YActionBar then return end

-- 1.60.1.70205: identity is classic; action buttons use the modern secure APIs.
local Client = {
    id = "forever",
    supported = true,
    ownedStanceButtons = true,
    nativeSpecialButtons = true,
    deterministicSpecialBars = true,
    nonStructuralNativeSuppression = true,
    directUsableRefresh = true,
    assistedCombat = true,
    heldBindings = true,
    professionQuality = false,
    rankUpgrade = true,
    questItems = true,
    secretRisk = true,
    mainPossess = true,
    vehiclePageFirst = true,
    vehicleFallbackPage = 16,
    petBattle = false,
    skyridingVisibility = false,
}
YUI.YActionBar.Client = Client

local probeFrame
local secureRuntimeReady = false
local function SafeCall(label, func, ...)
    local security = YUI.API and YUI.API.Security
    if security and security.SafeCall then
        return security.SafeCall(label, func, ...)
    end
    if type(func) ~= "function" then return false end
    return pcall(func, ...)
end

function Client.CheckSecureRuntime()
    if secureRuntimeReady then return true end
    local adapter = YUI.YActionBar.Adapter
    if adapter and adapter:InCombat() then return false end
    local owner = YUI.YActionBar
    if owner.ShouldDeferRuntimeStartup and owner:ShouldDeferRuntimeStartup() then return false end
    if not probeFrame then
        local ok, frame = SafeCall("YActionBar secure probe create", _G.CreateFrame,
            "Frame", nil, _G.UIParent, "SecureHandlerBaseTemplate")
        if not ok or not frame then return false end
        probeFrame = frame
        SafeCall("YActionBar secure probe hide", frame.Hide, frame)
    end
    -- The compiler may be cached privately by Blizzard after its global is cleared.
    -- Execute can report an inner error without throwing: require marker readback.
    local ok = SafeCall("YActionBar secure probe execute", probeFrame.Execute, probeFrame,
        'self:SetAttribute("yab-secure-probe", true)')
    if not ok then return false end
    local readOK, marker = SafeCall("YActionBar secure probe read", probeFrame.GetAttribute,
        probeFrame, "yab-secure-probe")
    secureRuntimeReady = readOK and marker == true
    return secureRuntimeReady
end
