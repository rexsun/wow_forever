
local _
---@type string, private
local addonName, private = ...

---@class private : table
---@field Tooltip cuetooltip

---@class cuetooltip : table
---@field Apply fun(frame: frame, getSettingsFn: fun():table, resolveFn: fun(frame: frame):string|nil, any|nil, opts: cuetooltip_opts)
---@field Release fun(frame: frame)
---@field RefreshAll fun()

---@class cuetooltip_opts : table
---@field kind "own"  every tracked frame is addon-owned; its handlers are installed with SetScript
---@field isSecureClick boolean  true for SecureActionButtonTemplate frames whose mouse must stay enabled when settings.clickable is on

-- Single addon-owned tooltip frame, created once at module load. Strata defaults to TOOLTIP.
-- A private GameTooltipTemplate instance does not interfere with the global GameTooltip.
local CUETooltip = CreateFrame("GameTooltip", "CUE_Tooltip", UIParent, "GameTooltipTemplate")

-- Anchor map for non-DEFAULT modes; "DEFAULT" omits the second arg to fall back to
-- Blizzard's ANCHOR_TOPRIGHT.
local anchorMap = {
    CURSOR = "ANCHOR_CURSOR",
    RIGHT = "ANCHOR_RIGHT",
    TOP = "ANCHOR_TOP",
}

---Tracked frames for combat-driven Refresh walks. Each entry stores only the
---frame reference; settings getter and secure-click flag are looked up via
---`binding[frame]` so AF re-binding is reflected without rewriting `tracked`.
---Most entries never need cleanup: they come from a component's own icon pool
---(TrinketTracker / RaidBuffTracker / etc., bounded per component), and Apply()
---is idempotent on re-entry so re-hooks do not re-append. A pool that is BUILT AFRESH rather than reused is the exception —
---a hosted IconTracker (an Additional Frame) creates new buttons on every
---profile switch — and that is what `Release` is for; without it the array
---would gain one dead entry per icon per switch, walked on every combat
---transition, forever.
---Stale-binding guard: combat walks check `binding[f] ~= nil` before using it,
---so an entry whose binding has been cleared is silently skipped.
---@type {frame: frame}[]
local tracked = {}

---Compute effective EnableMouse state per the rule order:
---  1. Secure click attribute always wins on SecureActionButtonTemplate frames
---     when settings.clickable is on.
---  2. tooltip_mode == "off" → mouse off.
---  3. tooltip_mode == "out_of_combat" + InCombatLockdown() → mouse off.
---  4. otherwise → mouse on.
---@param settings table
---@param isSecureClick boolean
---@return boolean
local function computeMouseEnabled(settings, isSecureClick)
    if isSecureClick and settings and settings.clickable then
        return true
    end
    local mode = settings and settings.tooltip_mode or "off"
    if mode == "off" then return false end
    if mode == "out_of_combat" and InCombatLockdown() then return false end
    return true
end

---Show CUETooltip for the given frame using its settings.
---@param frame frame
---@param getSettingsFn fun():table
---@param resolveFn fun(frame: frame):string|nil, any|nil
local function showTooltip(frame, getSettingsFn, resolveFn)
    local s = getSettingsFn()
    if not s then return end
    if s.tooltip_mode == "off" then return end
    if s.tooltip_mode == "out_of_combat" and InCombatLockdown() then return end

    local kind, payload = resolveFn(frame)
    if not payload then return end

    CUETooltip:Hide()
    local anchor = s.tooltip_anchor or "RIGHT"
    if anchor == "DEFAULT" then
        CUETooltip:SetOwner(frame)
    else
        CUETooltip:SetOwner(frame, anchorMap[anchor] or "ANCHOR_RIGHT")
    end

    if kind == "spell" then
        CUETooltip:SetSpellByID(payload)
    elseif kind == "item" then
        CUETooltip:SetItemByID(payload)
    elseif kind == "inventory" then
        CUETooltip:SetInventoryItem("player", payload)
    end
    CUETooltip:Show()
end

---Re-evaluate a frame's EnableMouse state per the formula. Skipped during
---combat lockdown for protected frames; the next OnLeaveCombat walk converges.
---@param frame frame
---@param getSettingsFn fun():table
---@param isSecureClick boolean
local function applyMouseState(frame, getSettingsFn, isSecureClick)
    local s = getSettingsFn()
    if not s then return end
    if InCombatLockdown() then
        -- EnableMouse is restricted on SecureActionButtonTemplate frames and on
        -- any protected frame during combat. Drop the write; the next
        -- OnLeaveCombat walk re-applies the correct state.
        if isSecureClick or (frame.IsProtected and frame:IsProtected()) then
            return
        end
    end
    frame:EnableMouse(computeMouseEnabled(s, isSecureClick))
end

---Per-frame binding: which getSettingsFn the OnEnter handler should consult,
---and which secure-click flag the mouse formula should use. Mutated in place
---when the owning component re-Applies a frame it already bound (an Additional
---Frame's hosted tracker re-binds its pool on a profile switch), so the newest
---settings getter wins without rewriting `tracked`.
---@type table<frame, {getSettingsFn: fun():table, resolveFn: fun(frame: frame):string|nil, any|nil, isSecureClick: boolean}>
local binding = {}

---Install OnEnter/OnLeave handlers on a frame and apply current mouse state.
---Idempotent: re-entry replaces the binding (so AF re-routing wins) but does
---not double-install scripts.
---@param frame frame
---@param getSettingsFn fun():table
---@param resolveFn fun(frame: frame):string|nil, any|nil
---@param opts cuetooltip_opts
local function Apply(frame, getSettingsFn, resolveFn, opts)
    local b = binding[frame]
    if b then
        b.getSettingsFn = getSettingsFn
        b.resolveFn = resolveFn
        b.isSecureClick = opts.isSecureClick or false
        applyMouseState(frame, getSettingsFn, b.isSecureClick)
        return
    end

    b = {
        getSettingsFn = getSettingsFn,
        resolveFn = resolveFn,
        isSecureClick = opts.isSecureClick or false,
    }
    binding[frame] = b

    local onLeave = function() CUETooltip:Hide() end

    -- Addon-owned frames have no existing handlers.
    local onEnter = function(self)
        local cur = binding[self]
        if cur then showTooltip(self, cur.getSettingsFn, cur.resolveFn) end
    end
    frame:SetScript("OnEnter", onEnter)
    frame:SetScript("OnLeave", onLeave)

    tracked[#tracked + 1] = { frame = frame }

    applyMouseState(frame, getSettingsFn, b.isSecureClick)
end

---Drop a frame's tracking entry and its binding, so `RefreshAll` stops walking
---it. The installed OnEnter/OnLeave handlers stay — they look the binding up
---per event and no-op once it is gone — which is why this is safe on a frame
---that outlives the release.
---
---The handlers are plain SetScript installs, so a later Apply replaces them
---rather than stacking a second copy.  (A CDM child used to be bound with
---HookScripts, which cannot be taken back off; no caller does that any more.)
---@param frame frame
local function Release(frame)
    binding[frame] = nil
    for i = #tracked, 1, -1 do
        if tracked[i].frame == frame then
            table.remove(tracked, i)
            return
        end
    end
end

---Walk every tracked frame and re-apply EnableMouse per current settings.
---Called on combat transitions and whenever tooltip-affecting settings change
---(Options panel writes to `tooltip_mode` / `clickable`, profile switch).
---Initial mouse state for a newly-tracked frame is set by `Apply`; this walk
---only handles post-Apply state changes.
local function RefreshAll()
    for i = 1, #tracked do
        local f = tracked[i].frame
        local b = binding[f]
        if b then applyMouseState(f, b.getSettingsFn, b.isSecureClick) end
    end
end

private.Callback.Register("OnEnterCombat", function()
    CUETooltip:Hide()
    RefreshAll()
end)

private.Callback.Register("OnLeaveCombat", RefreshAll)

private.Callback.Register("OnProfileChanged", RefreshAll)

---@type cuetooltip
private.Tooltip = {
    Apply = Apply,
    Release = Release,
    RefreshAll = RefreshAll,
}
