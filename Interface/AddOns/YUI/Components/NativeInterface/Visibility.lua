local _, addonTable = ...
local YUI = _G.YUI or addonTable
local Native = YUI and YUI.NativeInterface
if not Native then return end

local owner = {}
local bagOwner = {}
local recoveryOwner = {}
local hookedBags = setmetatable({}, { __mode = "k" })
local watchingBags = false
local bagsOpen = false
local applied = false
local suppression = {}
local lastReason
local refreshTimer, pendingReason
local recovering = false
local QueueRefresh

local function IsInCombat()
    local security = YUI.API and YUI.API.Security
    local check = security and security.InCombatLockdown or InCombatLockdown
    return type(check) == "function" and check() == true
end

local function OnCombatEnded()
    if pendingReason then QueueRefresh() end
end

local function SetRecovery(enabled)
    if enabled == recovering then return end
    recovering = enabled
    if enabled then
        YUI.Event:On("PLAYER_REGEN_ENABLED", OnCombatEnded, recoveryOwner, { moduleId = Native.MODULE_ID })
    else
        YUI.Event:OffOwner(recoveryOwner)
    end
end

local function CancelQueuedRefresh()
    if refreshTimer then refreshTimer:Cancel(); refreshTimer = nil end
    pendingReason = nil
    SetRecovery(false)
end

local function FlushVisibility()
    refreshTimer = nil
    if not pendingReason then return end
    if IsInCombat() then
        lastReason = "combat-deferred"
        SetRecovery(true)
        return
    end
    local reason = pendingReason
    pendingReason = nil
    SetRecovery(false)
    if Native.runtimeEnabled then Native:RefreshVisibility(reason)
    else Native:ReleaseVisibility() end
end

function QueueRefresh(reason)
    -- Keep configuration refreshes when a bag notification joins the same batch.
    if reason and (not pendingReason or reason ~= "bag-visibility") then pendingReason = reason end
    if not pendingReason then return end
    if IsInCombat() then
        if refreshTimer then refreshTimer:Cancel(); refreshTimer = nil end
        lastReason = "combat-deferred"
        SetRecovery(true)
    elseif not refreshTimer then
        -- Leave the native bag/ESC call stack before querying or changing native UI.
        if C_Timer and C_Timer.NewTimer then
            refreshTimer = C_Timer.NewTimer(0, FlushVisibility)
        else
            lastReason = "refresh-timer-unavailable"
        end
    end
end

local function OnBagVisibilityChanged()
    if not watchingBags or not Native.runtimeEnabled then return end
    QueueRefresh("bag-visibility")
end

local function EnsureBagFrameHooks(frame)
    if not frame or type(frame.HookScript) ~= "function" then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    local hooks = hookedBags[frame] or 0
    if hooks == 0 and pcall(frame.HookScript, frame, "OnShow", OnBagVisibilityChanged) then
        hooks = 1
    end
    if hooks == 1 and pcall(frame.HookScript, frame, "OnHide", OnBagVisibilityChanged) then
        hooks = 2
    end
    hookedBags[frame] = hooks
end

local function EnsureBagHooks()
    EnsureBagFrameHooks(_G.ContainerFrameCombinedBags)
    for index = 1, NUM_CONTAINER_FRAMES or 13 do
        EnsureBagFrameHooks(_G["ContainerFrame" .. index])
    end
end

local function OnBagAddonLoaded(_, addonName)
    if not watchingBags or addonName ~= "Blizzard_UIPanels_Game" then return end
    EnsureBagHooks()
    QueueRefresh("bag-addon-loaded")
end

local function SetBagWatching(enabled)
    if enabled == watchingBags then return end
    watchingBags = enabled
    if enabled then
        EnsureBagHooks()
        if YUI.Event and YUI.Event.On then
            YUI.Event:On("ADDON_LOADED", OnBagAddonLoaded, bagOwner, { moduleId = Native.MODULE_ID })
            YUI.Event:On("PLAYER_ENTERING_WORLD", OnBagVisibilityChanged, bagOwner, { moduleId = Native.MODULE_ID })
        end
    elseif YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(bagOwner)
    end
end

function Native:RefreshVisibility(reason)
    local api = YUI.API and YUI.API.BlizzardUI
    if not (api and type(api.SetOwnerSuppression) == "function") then
        lastReason = "blizzard-ui-api-unavailable"
        return false, lastReason
    end
    local config = self:GetConfig()
    local enabled = self.runtimeEnabled == true
    SetBagWatching(enabled and config.bagsBarVisibility == "auto")
    if IsInCombat() then
        QueueRefresh(reason or "config-refresh")
        return false, lastReason
    end
    CancelQueuedRefresh()
    bagsOpen = watchingBags and type(api.IsPlayerBagOpen) == "function" and api:IsPlayerBagOpen() or false
    local statusTrackingBars = enabled and config.hideStatusTrackingBars == true
    local microMenu = enabled and config.hideMicroMenu == true
    local bagsBar = enabled and (config.bagsBarVisibility == "hide" or (watchingBags and not bagsOpen))
    if reason == "bag-visibility" and applied and suppression.statusTrackingBars == statusTrackingBars
        and suppression.microMenu == microMenu and suppression.bagsBar == bagsBar then
        return true
    end
    suppression.statusTrackingBars = statusTrackingBars
    suppression.microMenu = microMenu
    suppression.bagsBar = bagsBar
    local ok, applyReason = api:SetOwnerSuppression(owner, suppression)
    applied = ok == true
    lastReason = applyReason
    return ok, applyReason
end

function Native:ReleaseVisibility()
    SetBagWatching(false)
    CancelQueuedRefresh()
    applied = false
    bagsOpen = false
    if IsInCombat() then
        QueueRefresh("release")
        return false, lastReason
    end
    local api = YUI.API and YUI.API.BlizzardUI
    if not (api and type(api.ReleaseOwner) == "function") then return true end
    return api:ReleaseOwner(owner)
end

function Native:GetVisibilityDiagnostics()
    return { owner = owner, lastReason = lastReason, watchingBags = watchingBags, bagsOpen = bagsOpen,
        mode = self:GetConfig().bagsBarVisibility, pendingRefresh = pendingReason ~= nil,
        timerPending = refreshTimer ~= nil, combatRecovery = recovering }
end
