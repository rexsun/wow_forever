
--[[
    CooldownLayoutSync — stores Blizzard CooldownViewer layout data per class
    in the addon profile and restores it on login or prompts for a reload when
    the layout cannot be applied mid-session.

    The layout data is an opaque string obtained via C_CooldownViewer.GetLayoutData()
    and restored via C_CooldownViewer.SetLayoutData(). It contains the complete
    CooldownViewer configuration for ALL specs (Essential, Utility, Buff categories,
    alert types, spell assignments, per-spec active layout mappings). Blizzard's
    internal SwitchToBestLayoutForSpec() handles per-spec selection within the blob.

    Layouts are saved by explicit user action: closing the Blizzard CDM settings
    window (OnHide) or clicking the manual "Save" button in addon options.

    On login: if a stored layout exists and was not already applied by this
    character, silently applies it via SetLayoutData (before Blizzard's init
    reads from the C API). On mid-session profile switch or import, SetLayoutData
    cannot refresh the viewers, so the user is prompted to /reload.

    A per-character tracking field (_cooldown_layout_char) records which character
    last applied the stored layout. This field is NOT exported with the profile.

    Profile keys use the class filename (e.g. "WARRIOR").
    The feature can be toggled via private.profile.cooldown_layout_sync.
--]]

local _
---@type string, private
local addonName, private = ...

---@class private : table
---@field CooldownLayoutSync cooldownlayoutsync

---@class cooldownlayoutsync : table
---@field Initialize fun() Registers events and callbacks for layout sync; called from Init.lua at PLAYER_LOGIN
---@field OnProfileChanged fun() Checks layout after an AceDB profile switch; called from Init.lua
---@field SaveCurrentLayout fun() Saves the current C_CooldownViewer layout to the profile under the class key
---@field GetStoredLayout fun(): string|nil Returns the stored layout for the current class, or nil
---@field GetLayoutKey fun(): string Returns the profile key for the current class (e.g. "WARRIOR")
---@field ClearStoredLayouts fun() Wipes all stored layouts from the profile

---@type cooldownlayoutsync
---@diagnostic disable-next-line: missing-fields
local layoutSync = {}

-- Cached class filename — constant for the entire session (never changes per character)
local playerClassFilename = select(2, UnitClass("player"))

-- Character identifier for tracking which character applied the layout.
-- Using name-realm so it's stable across sessions.
local playerCharId = UnitName("player") .. "-" .. GetRealmName()

-- Static popup dialog keys (addon-prefixed to avoid collisions)
local POPUP_CLEAR = "CLASSUIENHANCED_CLEAR_LAYOUTS"
local POPUP_RELOAD = "CLASSUIENHANCED_LAYOUT_RELOAD"


-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

---Return the profile key for the current class.
---@return string
function layoutSync.GetLayoutKey()
    return playerClassFilename
end

---Get the stored layout for the current class from the profile.
---Returns nil if no layout has been stored yet or the table was stripped by AceDB.
---@return string|nil
function layoutSync.GetStoredLayout()
    local key = layoutSync.GetLayoutKey()
    local layouts = private.profile.cooldown_layouts
    if not layouts then return nil end
    return layouts[key]
end

---Save the current C_CooldownViewer layout to the profile under the class key.
---Marks the current character as the one who applied this layout.
---No-op if the feature is disabled.
function layoutSync.SaveCurrentLayout()
    if not private.profile.cooldown_layout_sync then return end
    local key = layoutSync.GetLayoutKey()
    if not private.profile.cooldown_layouts then
        private.profile.cooldown_layouts = {}
    end
    local currentData = C_CooldownViewer.GetLayoutData()
    private.profile.cooldown_layouts[key] = currentData

    -- Mark this character as having the latest layout applied
    if not private.profile._cooldown_layout_char then
        private.profile._cooldown_layout_char = {}
    end
    private.profile._cooldown_layout_char[key] = playerCharId

    private.printdebug("CooldownLayoutSync: Saved layout for", private.GetLocalizedClassSpecLabel(key))
end

---Mark Blizzard's layout-manager data provider dirty so the next Blizzard-initiated
---refresh re-reads from the C API.
---
---The serializer's own `cachedSerializedData` is NOT invalidated. The call that used
---to sit here, `TextureLoadingGroupMixin.RemoveTexture(serializer, …)`, wrote
---`serializer.textures[…]` and so never touched that field at all — a provable no-op,
---removed 2026-09-19. There is no public way to drop it alone: `ClearSerializedData()`
---also calls `SetSerializedData("")`, which would wipe the layout being restored.
---The `AddTexture` write below is safe and does not taint (`.context/patterns.md`).
local function invalidateLayoutManagerCaches()
    if not CooldownViewerSettings then return end
    local dataProvider = CooldownViewerSettings:GetDataProvider()
    if dataProvider then
        TextureLoadingGroupMixin.AddTexture({ textures = dataProvider }, "displayDataDirty")
    end
end

---Attempt to restore a layout via SetLayoutData. Invalidates the layout manager's
---caches first so the next Blizzard-initiated refresh reads fresh data from the C API.
---If the call fails during combat (transient failure), defers a retry via
---OnLeaveCombat without deleting the entry. If it fails outside combat (corrupted
---or outdated data), removes the entry from the profile.
---
---One of the addon's two sanctioned `pcall` sites (`.context/patterns.md`, "No
---`pcall` on our own code"): `layoutData` is an opaque blob that reaches us from a
---saved or imported profile, and SetLayoutData throws on one it cannot parse, so
---there is no non-throwing way to ask. The error is reported and acted on — the
---bad entry is named to the user and dropped — never swallowed.
---@param layoutData string  opaque layout string from GetLayoutData()
---@param profileKey string  the cooldown_layouts key to remove on failure (e.g. "WARRIOR")
---@return boolean success
local function trySetLayoutData(layoutData, profileKey)
    invalidateLayoutManagerCaches()
    local ok, err = pcall(C_CooldownViewer.SetLayoutData, layoutData)
    if ok then
        return true
    end

    -- Failure during combat is transient — defer retry, don't delete the entry.
    if InCombatLockdown() then
        private.printdebug("CooldownLayoutSync: SetLayoutData failed during combat for", private.GetLocalizedClassSpecLabel(profileKey), "— deferring retry")
        local function onLeaveCombat()
            private.Callback.Unregister("OnLeaveCombat", onLeaveCombat)
            -- Secrecy can outlive lockdown at a dungeon-exit regen, and
            -- SetLayoutData drives the CDM refresh — re-defer past it.
            private.Util.RunWhenSecrecyClears("CooldownLayoutSync.trySetLayoutData", function()
                if not private.profile then return end
                trySetLayoutData(layoutData, profileKey)
            end)
        end
        private.Callback.Register("OnLeaveCombat", onLeaveCombat)
        return false
    end

    -- Failure outside combat means the data is genuinely bad — remove it.
    private.print("CooldownLayoutSync: Failed to restore layout for " .. private.GetLocalizedClassSpecLabel(profileKey) .. " — removing outdated entry.")
    private.printdebug("CooldownLayoutSync: SetLayoutData error:", err)
    local layouts = private.profile.cooldown_layouts
    if layouts then
        layouts[profileKey] = nil
    end
    return false
end

---Check whether the current character has already applied the stored layout.
---@return boolean
local function isLayoutAppliedByCurrentChar()
    local charTable = private.profile._cooldown_layout_char
    if not charTable then return false end
    return charTable[playerClassFilename] == playerCharId
end

---Mark the current character as having applied the stored layout.
local function markLayoutApplied()
    if not private.profile._cooldown_layout_char then
        private.profile._cooldown_layout_char = {}
    end
    private.profile._cooldown_layout_char[playerClassFilename] = playerCharId
end

---Wipe all stored layouts from the profile.
function layoutSync.ClearStoredLayouts()
    if private.profile.cooldown_layouts then
        wipe(private.profile.cooldown_layouts)
    end
    if private.profile._cooldown_layout_char then
        wipe(private.profile._cooldown_layout_char)
    end
    private.printdebug("CooldownLayoutSync: Cleared all stored layouts")
end


-- ---------------------------------------------------------------------------
-- Static Popup Dialogs
-- ---------------------------------------------------------------------------

-- Confirm clear when disabling the feature from Options
StaticPopupDialogs[POPUP_CLEAR] = {
    text = private.L["LAYOUT_SYNC_CLEAR_PROMPT"],
    button1 = private.L["LAYOUT_SYNC_CLEAR_CONFIRM"],
    button2 = private.L["LAYOUT_SYNC_KEEP"],
    OnAccept = function()
        layoutSync.ClearStoredLayouts()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Prompt user to reload after mid-session layout change
StaticPopupDialogs[POPUP_RELOAD] = {
    text = "Cooldown Manager layout updated. Reload UI to apply changes?",
    button1 = "Reload",
    button2 = "Later",
    OnAccept = function()
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}


-- ---------------------------------------------------------------------------
-- Migration
-- ---------------------------------------------------------------------------

---Migrate old per-spec keys ("CLASS-N") to per-class key ("CLASS").
---Prefers the current spec's data, falls back to any available spec.
---No-op if already migrated or no old keys exist.
local function migratePerSpecKeys()
    local layouts = private.profile.cooldown_layouts
    if not layouts then return end
    if layouts[playerClassFilename] then return end -- already migrated

    local prefix = playerClassFilename .. "-"
    local currentSpecKey = prefix .. (C_SpecializationInfo.GetSpecialization() or 1)
    local bestData = layouts[currentSpecKey]

    -- Prefer current spec's data, fall back to any spec
    if not bestData then
        for key, data in pairs(layouts) do
            if key:sub(1, #prefix) == prefix then
                bestData = data
                break
            end
        end
    end

    if bestData then
        layouts[playerClassFilename] = bestData
        private.printdebug("CooldownLayoutSync: Migrated per-spec layout to per-class key", private.GetLocalizedClassSpecLabel(playerClassFilename))
    end

    -- Clean up old per-spec keys
    for key in pairs(layouts) do
        if key:sub(1, #prefix) == prefix then
            layouts[key] = nil
        end
    end
end


-- ---------------------------------------------------------------------------
-- Core restore logic
-- ---------------------------------------------------------------------------

---Apply the stored layout on login. Works because SetLayoutData is called
---before Blizzard's LoadCooldownSettings reads from the C API.
---@param source string  debug label for what triggered this
local function applyOnLogin(source)
    if not private.profile.cooldown_layout_sync then return end

    migratePerSpecKeys()

    local key = layoutSync.GetLayoutKey()
    local storedLayout = layoutSync.GetStoredLayout()

    if not storedLayout then
        -- First time — save current Blizzard defaults as the initial baseline
        layoutSync.SaveCurrentLayout()
        private.printdebug("CooldownLayoutSync: First-time save for", private.GetLocalizedClassSpecLabel(key), "(" .. source .. ")")
        return
    end

    -- Already applied by this character — skip
    if isLayoutAppliedByCurrentChar() then
        private.printdebug("CooldownLayoutSync: Layout already applied by", playerCharId, "— skipping (" .. source .. ")")
        return
    end

    -- Apply the stored layout (works on login — Blizzard init reads from C API)
    if InCombatLockdown() then
        local function onLeaveCombat()
            private.Callback.Unregister("OnLeaveCombat", onLeaveCombat)
            -- Same secrecy re-defer as the trySetLayoutData retry above;
            -- applyOnLogin re-validates everything when it finally runs.
            private.Util.RunWhenSecrecyClears("CooldownLayoutSync.applyOnLogin", function()
                applyOnLogin(source .. "_deferred")
            end)
        end
        private.Callback.Register("OnLeaveCombat", onLeaveCombat)
        return
    end

    if trySetLayoutData(storedLayout, key) then
        markLayoutApplied()
        private.printdebug("CooldownLayoutSync: Applied layout for", private.GetLocalizedClassSpecLabel(key), "(" .. source .. ")")
    end
end

---Handle a mid-session layout change (profile switch or import).
---SetLayoutData cannot refresh the viewers mid-session, so we apply the data
---at the C level and prompt the user to reload.
local function handleMidSessionChange(source)
    if not private.profile.cooldown_layout_sync then return end

    migratePerSpecKeys()

    local key = layoutSync.GetLayoutKey()
    local storedLayout = layoutSync.GetStoredLayout()

    if not storedLayout then
        -- New profile with no stored layout — save current state as baseline
        layoutSync.SaveCurrentLayout()
        private.printdebug("CooldownLayoutSync: First-time save for", private.GetLocalizedClassSpecLabel(key), "(" .. source .. ")")
        return
    end

    -- Apply at C level so it persists, even though viewers won't refresh yet
    if not InCombatLockdown() then
        if trySetLayoutData(storedLayout, key) then
            markLayoutApplied()
            private.printdebug("CooldownLayoutSync: Applied layout at C level for", private.GetLocalizedClassSpecLabel(key), "(" .. source .. ")")
        end
    end

    -- Prompt user to reload for visual refresh
    StaticPopup_Show(POPUP_RELOAD)
end


-- ---------------------------------------------------------------------------
-- Initialize
-- ---------------------------------------------------------------------------

---Register events and callbacks for layout sync.
---Called from Init.lua in OnEnable() after all components and EditMode are initialized.
function layoutSync.Initialize()
    -- No Cooldown Manager (MoP Classic): no layout to save or restore.
    if not private.compat.HasCooldownManager() then return end
    -- Auto-save when the user closes the Blizzard CDM settings window.
    -- CooldownViewerSettings.OnHide fires after CheckSaveCurrentLayout() has flushed
    -- all pending changes, so the layout data is final at this point.
    EventRegistry:RegisterCallback("CooldownViewerSettings.OnHide", function()
        if not private.profile then return end
        layoutSync.SaveCurrentLayout()
    end, layoutSync)

    -- Event frame for login restore
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
    eventFrame:SetScript("OnEvent", function()
        if not private.profile then return end
        C_Timer.After(0, function()
            if not private.profile then return end
            applyOnLogin("login")
        end)
    end)

    -- COOLDOWN_VIEWER_DATA_LOADED is a C++ engine event that typically fires before
    -- PLAYER_LOGIN, meaning our event frame wasn't registered in time to catch it.
    -- Check if the cooldown system is already available; if so, apply directly.
    local isAvailable = C_CooldownViewer.IsCooldownViewerAvailable()
    if isAvailable then
        C_Timer.After(0, function()
            if not private.profile then return end
            applyOnLogin("login")
        end)
    end
end

---Handle an AceDB profile switch or segment import mid-session.
---Called synchronously from ProfileManager.OnProfileChanged(), and from the
---cooldown_layout_sync segment's refresh on an import.
function layoutSync.OnProfileChanged()
    -- Skip entirely when SpecProfileSync triggered this profile switch —
    -- Blizzard handles CDM layout switching natively via SwitchToBestLayoutForSpec.
    -- Consumed, not peeked: the flag must not outlive the switch that set it.
    if private.SpecProfileSync and private.SpecProfileSync.ConsumeSpecTriggeredSwitch() then
        private.printdebug("CooldownLayoutSync: Skipping OnProfileChanged — spec-triggered switch")
        return
    end
    -- After the consume, so a spec switch never leaves the flag latched.
    if not private.compat.HasCooldownManager() then return end
    handleMidSessionChange("profile_change")
end


private.CooldownLayoutSync = layoutSync
