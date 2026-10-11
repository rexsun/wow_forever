local _
---@type string, private
local addonName, private = ...
---@type public
local public = private.public

---@class public : df_addon
---@field profile profile
---@field OnLoad fun(self:public) Called on ADDON_LOADED
---@field OnInit fun(self:public) Called on PLAYER_LOGIN

--GLOBAL: ClassUIEnhanced

-- ---------------------------------------------------------------------------
-- Wago Integration API (LibAddonProfiles)
-- Global table so Wago Companion and similar tools can import/export profiles
-- without touching addon internals. All functions delegate to ProfileManager.
-- Available at runtime after all .lua files have loaded and PLAYER_LOGIN fires.
-- ---------------------------------------------------------------------------

---@class ClassUIEnhancedAPI_class : table
---@field ExportProfile fun(profileKey?: string): string|nil, string|nil
---@field ImportProfile fun(profileString: string, profileKey: string): boolean, string|nil
---@field DecodeProfileString fun(profileString: string): table|nil, string|nil
---@field SetProfile fun(profileKey: string)
---@field GetProfileKeys fun(): table<string, boolean>
---@field GetCurrentProfileKey fun(): string
---@field OpenConfig fun()
---@field CloseConfig fun()
---@field AddAnchors fun(addonName: string, anchorTable: table<string, string>)
---@field GetComponentNames fun(): string[]

--GLOBAL: ClassUIEnhancedAPI
ClassUIEnhancedAPI = ClassUIEnhancedAPI or {}

---Export any profile by key. If profileKey is nil, exports the active profile.
---@param profileKey? string
---@return string|nil encodedString, string|nil errorMessage
function ClassUIEnhancedAPI.ExportProfile(profileKey)
    return private.ProfileManager.ExportFullProfile(profileKey)
end

---Import a full profile from an encoded string, creating or overwriting the
---named profile and activating it. Does NOT call ReloadUI — Wago handles
---batched reloads when needed.
---@param profileString string
---@param profileKey string
---@return boolean success, string|nil errorMessage
function ClassUIEnhancedAPI.ImportProfile(profileString, profileKey)
    return private.ProfileManager.ImportFullProfile(profileString, profileKey)
end

---Decode an encoded profile string into a table for inspection (changelogs,
---comparison) without applying it.
---@param profileString string
---@return table|nil decodedData, string|nil errorMessage
function ClassUIEnhancedAPI.DecodeProfileString(profileString)
    return private.ProfileManager.DecodeProfileString(profileString)
end

---Switch to an existing profile by key.
---@param profileKey string
function ClassUIEnhancedAPI.SetProfile(profileKey)
    private.ProfileManager.SetProfile(profileKey)
end

---Return all existing profile keys in { [key] = true } format.
---@return table<string, boolean>
function ClassUIEnhancedAPI.GetProfileKeys()
    return private.ProfileManager.GetProfileKeys()
end

---Return the key of the currently active profile.
---@return string
function ClassUIEnhancedAPI.GetCurrentProfileKey()
    return private.ProfileManager.GetCurrentProfileKey()
end

---Open the addon's configuration panel.
function ClassUIEnhancedAPI.OpenConfig()
    private.Options.OpenOptionsPanel()
end

---Close the addon's configuration panel.
function ClassUIEnhancedAPI.CloseConfig()
    private.Options.CloseOptionsPanel()
end

-- ---------------------------------------------------------------------------
-- External Anchor Registration API
-- Allows other addons to register their frames as valid anchor parents for
-- ClassUIEnhanced components. Registered frames appear in the Edit Mode
-- "Anchor Frame" dropdown alongside CUE's own components.
-- ---------------------------------------------------------------------------

---Register external addon frames as anchor targets for CUE components.
---Keys in anchorTable are global frame names (_G[key] must resolve to a frame
---at runtime); values are human-readable labels shown in the Edit Mode dropdown.
---
---Can be called before or after CUE initializes. If the anchoring system is
---already running, a layout refresh is triggered automatically.
---
---Example:
---  ClassUIEnhancedAPI.AddAnchors("UnhaltedUnitFrames", {
---      ["UUF_Player"] = "Unhalted: Player Frame",
---      ["UUF_Target"] = "Unhalted: Target Frame",
---  })
---@param addonName string  The name of the addon registering the anchors
---@param anchorTable table<string, string>  Mapping of global frame name to display label
function ClassUIEnhancedAPI.AddAnchors(addonName, anchorTable)
    if type(addonName) ~= "string" or type(anchorTable) ~= "table" then return end
    for frameKey, displayName in pairs(anchorTable) do
        if type(frameKey) == "string" and type(displayName) == "string" then
            private.externalAnchors[frameKey] = {
                displayName = displayName,
                addonName = addonName,
            }
        end
    end
    -- If the anchoring system is already initialized, rebuild the anchor tree
    -- so components pointing at these newly-registered names become roots
    -- (instead of orphaned children of an unknown parent), then refresh layout.
    -- Track frames that don't exist in _G yet for deferred resolution.
    if private.Anchor then
        for frameKey in pairs(anchorTable) do
            if type(frameKey) == "string" and not _G[frameKey] and private.Anchor.TrackPendingExternalFrame then
                private.Anchor.TrackPendingExternalFrame(frameKey)
            end
        end
        if private.Anchor.RebuildAnchorTree then
            private.Anchor.RebuildAnchorTree()
        end
        if private.Anchor.Refresh then
            private.Anchor.Refresh()
        end
    end
end

---Return the list of registered component names.
---External addons can use this to discover available anchor targets.
---@return string[]
function ClassUIEnhancedAPI.GetComponentNames()
    local names = {}
    for _, comp in ipairs(private.ComponentManager.GetAllComponents()) do
        names[#names + 1] = comp.GetComponentName()
    end
    return names
end
