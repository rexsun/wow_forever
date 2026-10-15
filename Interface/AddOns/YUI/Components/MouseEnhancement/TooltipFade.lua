local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
local Security = YUI and YUI.API and YUI.API.Security
if not (YUI and YUI.Components and Security) then return end
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or (_G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME] and _G.YUI_CORE_EMBED_STATE[ADDON_NAME].productId)
    or YUI.ProductId or "suite"
local TooltipFade = { product = PRODUCT_ID }
YUI._MouseEnhancementTooltipFade = TooltipFade

local hooked = setmetatable({}, { __mode = "k" })
local enabled, hiding = false, false
local hookCount, hideCount, failureCount = 0, 0, 0
local reason = "disabled"

local function ReadBoolean(frame, method)
    local func = frame[method]
    if type(func) ~= "function" then return nil end
    local ok, value = pcall(func, frame)
    if not ok or Security.IsSecretValue(value) or type(value) ~= "boolean" then return nil end
    return value
end

local function CanAccess(frame)
    return frame and ReadBoolean(frame, "IsForbidden") == false
        and ReadBoolean(frame, "IsProtected") == false
end

local function OnFadeOut(frame)
    if not enabled or hiding or frame ~= _G.GameTooltip or not hooked[frame] then return end
    if not CanAccess(frame) or ReadBoolean(frame, "IsShown") ~= true then return end
    -- Keep native FadeOut intact; only collapse the pending fade after it returns.
    hiding = true
    -- Native frame methods come from a metatable; securecallmethod uses raw lookup.
    local ok = Security.SafeMethod("MouseEnhancement:tooltip-hide", frame, "Hide")
    local shown = ok and ReadBoolean(frame, "IsShown")
    hiding = false
    if ok and shown == false then
        hideCount = hideCount + 1
        reason = nil
    else
        failureCount = failureCount + 1
        reason = not ok and "hide-failed" or (shown == true and "hide-not-effective" or "hide-state-unavailable")
    end
end

function TooltipFade.NormalizeConfig(db, store)
    local legacy = type(store) == "table" and store.NativeInterface_Config
    if type(legacy) ~= "table" then legacy = nil end
    local value = rawget(db, "tooltipInstantHide")
    if value == nil and legacy then value = rawget(legacy, "tooltipInstantHide") end
    db.tooltipInstantHide = not Security.IsSecretValue(value) and value ~= false
    if legacy then legacy.tooltipInstantHide = nil end
end

function TooltipFade.Configure(db, featureEnabled)
    enabled = featureEnabled == true and db.tooltipInstantHide == true
    if not enabled then reason = "disabled"; return true end
    local frame = _G.GameTooltip
    if not CanAccess(frame) or type(frame.FadeOut) ~= "function" or type(frame.Hide) ~= "function" then
        enabled, reason = false, "unsupported-tooltip"
        return false, reason
    end
    if not hooked[frame] then
        if not Security.SafeHook("MouseEnhancement:tooltip-fade", frame, "FadeOut", OnFadeOut) then
            enabled, reason = false, "hook-failed"
            failureCount = failureCount + 1
            return false, reason
        end
        hooked[frame] = true
        hookCount = hookCount + 1
    end
    reason = nil
    return true
end

function TooltipFade.Release()
    -- Secure posthooks cannot be removed. Disabled callbacks return before UI reads.
    enabled, reason = false, "disabled"
end

function TooltipFade.GetDiagnostics()
    return {
        enabled = enabled,
        hooked = _G.GameTooltip ~= nil and hooked[_G.GameTooltip] == true,
        hookCount = hookCount,
        hideCount = hideCount,
        failureCount = failureCount,
        reason = reason,
    }
end
