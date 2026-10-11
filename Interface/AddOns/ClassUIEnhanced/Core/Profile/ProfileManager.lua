
--[[
    Centralised profile data operations: encoding/decoding, segment registry,
    import/export, profile switching, and layout refresh.

    All external callers (Options UI, Wago integration, etc.) go through
    private.ProfileManager instead of touching AceDB or saved variables directly.
--]]

local _
---@type string, private
local addonName, private = ...
---@type public
local public = private.public
local L = private.L

---@class profilemanager : table
---@field CompressData fun(data: table): string
---@field DecompressData fun(str: string): table|nil, string|nil
---@field DeepCopyInto fun(dest: table, src: table)
---@field GetSegments fun(): segment_definition[]
---@field GetSegmentGroups fun(): segment_group[]
---@field FindSegment fun(segId: string): segment_definition|nil
---@field BuildExportEnvelope fun(prof: profile, selectedIds: table<string, boolean>, profileName?: string): table
---@field ParseEnvelope fun(decoded: any): table|nil, string|nil
---@field MakeComponentRefresh fun(compName: string): fun()
---@field FullLayoutRefresh fun()
---@field OnProfileChanged fun()
---@field MigrateCDMVisibility fun()
---@field MigrateHideWhenInactive fun()
---@field MigrateProcGlowStyle fun()
---@field MigrateBreakpointPipKeys fun(profile: table|nil)
---@field GetCurrentProfileKey fun(): string
---@field GetProfileKeys fun(): table<string, boolean>
---@field SetProfile fun(key: string)
---@field ExportFullProfile fun(profileKey: string|nil): string|nil, string|nil
---@field ImportFullProfile fun(profileString: string, profileKey: string): boolean, string|nil
---@field ExportSegmented fun(selectedIds: table<string, boolean>): string
---@field ImportSegmented fun(envelope: table, selectedSegIds: string[], profileName: string, asNew: boolean): boolean, string|nil
---@field DecodeProfileString fun(str: string): table|nil, string|nil

---@type profilemanager
---@diagnostic disable-next-line: missing-fields
local pm = {}
private.ProfileManager = pm


-- ---------------------------------------------------------------------------
-- Encoding / Decoding
-- ---------------------------------------------------------------------------

---Compress a table to a portable "!CUE!..." import string.
---Uses C_EncodingUtil: CBOR serialization → Deflate compression → Base64 encoding.
---@param data table
---@return string
function pm.CompressData(data)
    local serialized = C_EncodingUtil.SerializeCBOR(data)
    local compressed = C_EncodingUtil.CompressString(serialized, Enum.CompressionMethod.Deflate, Enum.CompressionLevel.OptimizeForSize)
    local encoded = C_EncodingUtil.EncodeBase64(compressed)
    return "!CUE!" .. encoded
end

---Decompress a "!CUE!..." string back to a table.
---@param str string
---@return table|nil data, string|nil errorMessage
function pm.DecompressData(str)
    if type(str) ~= "string" or not string.find(str, "^!CUE!") then
        return nil, "not a valid CUE import string"
    end
    local encoded = string.sub(str, 6)
    local compressed = C_EncodingUtil.DecodeBase64(encoded)
    if not compressed then return nil, "base64 decode failed" end
    local serialized = C_EncodingUtil.DecompressString(compressed)
    if not serialized then return nil, "decompress failed" end
    local data = C_EncodingUtil.DeserializeCBOR(serialized)
    if not data then return nil, "deserialize failed" end
    return data
end


-- ---------------------------------------------------------------------------
-- Utility
-- ---------------------------------------------------------------------------

---Recursively copy all key/value pairs from src into dest.
---Existing keys in dest that are absent from src are left intact.
---Recursion is unbounded: import payloads reach it only after
---pm.ParseEnvelope has proved them tables of bounded depth.
---@param dest table
---@param src table
function pm.DeepCopyInto(dest, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dest[k]) ~= "table" then dest[k] = {} end
            pm.DeepCopyInto(dest[k], v)
        else
            dest[k] = v
        end
    end
end

---True when `t` is a table and every value in it is a table.
---@param t any
---@return boolean
local function isTableOfTables(t)
    if type(t) ~= "table" then return false end
    for _, v in pairs(t) do
        if type(v) ~= "table" then return false end
    end
    return true
end

---True when each named field of `t` is absent or a table.
---@param t table
---@return boolean
local function fieldsAreTables(t, ...)
    for i = 1, select("#", ...) do
        local v = t[select(i, ...)]
        if v ~= nil and type(v) ~= "table" then return false end
    end
    return true
end


-- ---------------------------------------------------------------------------
-- Segment Registry — defines what can be partially imported/exported
-- ---------------------------------------------------------------------------

-- Keys that belong to the "layout" segment (extracted atomically from every
-- component to keep the anchor chain consistent during partial imports).
local LAYOUT_KEYS = { "anchor_profile", "width", "height", "enabled", "visibility", "visibility_rules" }

-- Lookup table for LAYOUT_KEYS for O(1) membership checks.
local isLayoutKey = {}
for _, k in ipairs(LAYOUT_KEYS) do isLayoutKey[k] = true end

---All component names in a stable order for iteration.
local COMPONENT_NAMES = {
    "PlayerCastBar", "TargetCastBar", "FocusCastBar", "GlobalCooldown",
    "CooldownTracker", "BuffTracker", "BuffTrackerBars", "UtilitiesTracker",
    "TrinketTracker", "RacialTracker", "ConsumableTracker", "ConsumableBuffTracker", "RaidBuffTracker", "OutboundBuffTracker", "PrimaryResources", "PlayerHealthBar", "SecondaryResources",
}

---Map component names to locale keys for segment labels.
local COMP_LABEL_MAP = {
    PlayerCastBar = "SEGMENT_PLAYER_CAST_BAR",
    TargetCastBar = "SEGMENT_TARGET_CAST_BAR",
    FocusCastBar = "SEGMENT_FOCUS_CAST_BAR",
    GlobalCooldown = "SEGMENT_GLOBAL_COOLDOWN",
    CooldownTracker = "SEGMENT_COOLDOWN_TRACKER",
    BuffTracker = "SEGMENT_BUFF_TRACKER",
    BuffTrackerBars = "SEGMENT_BUFF_TRACKER_BARS",
    UtilitiesTracker = "SEGMENT_UTILITIES_TRACKER",
    TrinketTracker = "SEGMENT_TRINKET_TRACKER",
    RacialTracker = "SEGMENT_RACIAL_TRACKER",
    ConsumableTracker = "SEGMENT_CONSUMABLE_TRACKER",
    ConsumableBuffTracker = "SEGMENT_CONSUMABLE_BUFF_TRACKER",
    RaidBuffTracker = "SEGMENT_RAID_BUFF_TRACKER",
    OutboundBuffTracker = "SEGMENT_OUTBOUND_BUFF_TRACKER",
    PrimaryResources = "SEGMENT_PRIMARY_RESOURCES",
    PlayerHealthBar = "SEGMENT_PLAYER_HEALTH_BAR",
    SecondaryResources = "SEGMENT_SECONDARY_RESOURCES",
}

---Map component names to locale keys for segment descriptions.
local COMP_DESC_MAP = {
    PlayerCastBar = "SEGMENT_PLAYER_CAST_BAR_DESC",
    TargetCastBar = "SEGMENT_TARGET_CAST_BAR_DESC",
    FocusCastBar = "SEGMENT_FOCUS_CAST_BAR_DESC",
    GlobalCooldown = "SEGMENT_GLOBAL_COOLDOWN_DESC",
    CooldownTracker = "SEGMENT_COOLDOWN_TRACKER_DESC",
    BuffTracker = "SEGMENT_BUFF_TRACKER_DESC",
    BuffTrackerBars = "SEGMENT_BUFF_TRACKER_BARS_DESC",
    UtilitiesTracker = "SEGMENT_UTILITIES_TRACKER_DESC",
    TrinketTracker = "SEGMENT_TRINKET_TRACKER_DESC",
    RacialTracker = "SEGMENT_RACIAL_TRACKER_DESC",
    ConsumableTracker = "SEGMENT_CONSUMABLE_TRACKER_DESC",
    ConsumableBuffTracker = "SEGMENT_CONSUMABLE_BUFF_TRACKER_DESC",
    RaidBuffTracker = "SEGMENT_RAID_BUFF_TRACKER_DESC",
    OutboundBuffTracker = "SEGMENT_OUTBOUND_BUFF_TRACKER_DESC",
    PrimaryResources = "SEGMENT_PRIMARY_RESOURCES_DESC",
    PlayerHealthBar = "SEGMENT_PLAYER_HEALTH_BAR_DESC",
    SecondaryResources = "SEGMENT_SECONDARY_RESOURCES_DESC",
}

---@class segment_group
---@field id string  internal key matching segment.group values
---@field label string  localization key for section header

---@type segment_group[]
local SEGMENT_GROUPS = {
    { id = "general", label = "SEGMENT_GROUP_GENERAL" },
    { id = "positioning", label = "SEGMENT_GROUP_POSITIONING" },
    { id = "components", label = "SEGMENT_GROUP_COMPONENTS" },
}


-- ---------------------------------------------------------------------------
-- Refresh helpers
-- ---------------------------------------------------------------------------

---Build a targeted refresh function for a single component by name.
---@param compName string
---@return fun()
function pm.MakeComponentRefresh(compName)
    return function()
        local comp = private.ComponentManager.GetComponent(compName)
        if comp then
            if comp.GetEnabled() then
                comp.OnEnable()
            else
                comp.OnDisable()
            end
            private.fontsDirty = true
            comp.Refresh()
            private.fontsDirty = false
        end
    end
end

---Full layout refresh: reconcile lifecycle, two-pass anchor, deferred third pass.
---Does NOT call CooldownLayoutSync.OnProfileChanged — that is handled separately
---by OnProfileChanged() or via the cooldown_layout_sync segment's own refresh.
function pm.FullLayoutRefresh()
    -- Invalidate Util caches before the full refresh pass.
    private.Util.InvalidateKeybindCache()

    -- Drop proc glows orphaned by the instance teardown this refresh follows.
    -- Their only stop path is Blizzard's once-per-proc hide event, so one left
    -- running across a rebuild never stops again without a /reload.  Covers the
    -- deferred post-combat re-apply for free, since that re-enters here.
    private.GlowEffect.ReconcileProcGlows()

    private.Anchor.MigrateAnchorProfiles()
    private.Anchor.RebuildAnchorTree()
    private.Anchor.ClearAllComponentPoints()

    private.Anchor.BeginBulkRefresh()
    for _, comp in ipairs(private.ComponentManager.GetAllComponents()) do
        if comp.GetEnabled() then
            comp.OnEnable()
        else
            comp.OnDisable()
        end
    end
    private.Anchor.EndBulkRefresh()

    private.Anchor.Refresh()
    private.fontsDirty = true
    for _, comp in ipairs(private.ComponentManager.GetAllComponents()) do
        comp.Refresh()
    end
    private.fontsDirty = false
    private.Anchor.Refresh()
    private.EditMode.Refresh()

    C_Timer.After(0, function()
        private.ComponentManager.RefreshAllComponents()
        private.Anchor.Refresh()
    end)
end

-- Combat deferral for the frame-touching half of a profile apply.
--
-- A profile apply repositions every component, but ClearAllPoints/SetPoint on
-- the secure components (ConsumableBuffTracker/RaidBuffTracker) are blocked in
-- combat.  That primitive self-skips (Anchoring.ClearAllComponentPoints), so
-- an in-combat apply lands on everything that is not locked down and leaves
-- the rest on its old geometry.  This schedules the one re-run that converges
-- the skipped work after combat.
local pendingCombatRefresh = false

---Re-apply the layout half of a profile switch that was skipped during combat.
---Cooldown/aura secrecy can outlive InCombatLockdown() at a dungeon-exit regen,
---and this re-runs the AF rebuild that drives Blizzard's CDM refresh, so the
---work is re-deferred past secrecy rather than run on the combat edge.
---`pendingCombatRefresh` stays true until it actually runs, keeping repeat
---applies coalesced onto the one queued re-run.
local function applyDeferredLayout()
    private.Callback.Unregister("OnLeaveCombat", applyDeferredLayout)
    private.Util.RunWhenSecrecyClears("ProfileManager.applyDeferredLayout", function()
        pendingCombatRefresh = false
        private.AdditionalFrameManager.OnProfileChanged()
        pm.FullLayoutRefresh()
    end)
end

---Schedule a post-combat re-layout when a profile apply ran during combat.
---Coalesced: repeated applies in one pull register a single re-run.
---Deliberately does NOT re-run pm.OnProfileChanged — that would re-fire the
---OnProfileChanged callback a second time for one switch.
local function deferLayoutIfInCombat()
    if not InCombatLockdown() then return end
    if pendingCombatRefresh then return end
    pendingCombatRefresh = true
    private.Callback.Register("OnLeaveCombat", applyDeferredLayout)
    private.print(L["PROFILE_SWITCH_DEFERRED_COMBAT"])
end


-- ---------------------------------------------------------------------------
-- Segment definitions
-- ---------------------------------------------------------------------------

---@class segment_definition
---@field id string  unique internal key
---@field label string  localization key for display label
---@field desc string  localization key for tooltip description
---@field group string  group key for UI sectioning
---@field extract fun(profile: profile): table|nil  extract segment data from a profile
---@field apply fun(profile: profile, data: table)  merge segment data into a live profile
---@field valid fun(data: table): boolean?  false when `apply` would throw on this payload's shape; checked by pm.ParseEnvelope before anything is written. nil = any table applies
---@field refresh fun()  apply runtime side-effects after import
---@field layoutRefresh fun()?  the part of `refresh` that pm.FullLayoutRefresh does not do. When an import also runs a FullLayoutRefresh, it replaces every segment's `refresh` and only this still runs, ahead of it. nil = fully covered

---@type segment_definition[]
local SEGMENTS = {
    {
        id = "castbar_colors",
        label = "SEGMENT_CASTBAR_COLORS",
        desc = "SEGMENT_CASTBAR_COLORS_DESC",
        group = "general",
        extract = function(p) return p.castbar_colors end,
        apply = function(p, data)
            if not p.castbar_colors then p.castbar_colors = {} end
            pm.DeepCopyInto(p.castbar_colors, data)
        end,
        refresh = function()
            for _, unitId in ipairs({"player", "target", "focus"}) do
                local bar = private.CastBar.GetCastBar(unitId)
                if bar then private.CastBar.ApplyColors(bar) end
            end
        end,
    },
    {
        id = "resource_colors",
        label = "SEGMENT_RESOURCE_COLORS",
        desc = "SEGMENT_RESOURCE_COLORS_DESC",
        group = "general",
        extract = function(p) return p.resource_colors end,
        apply = function(p, data)
            if not p.resource_colors then p.resource_colors = {} end
            pm.DeepCopyInto(p.resource_colors, data)
        end,
        refresh = function() private.SecondaryResources.Refresh() end,
    },
    {
        id = "health_gradient_colors",
        label = "SEGMENT_HEALTH_GRADIENT_COLORS",
        desc = "SEGMENT_HEALTH_GRADIENT_COLORS_DESC",
        group = "general",
        extract = function(p) return p.health_gradient_colors end,
        apply = function(p, data)
            if not p.health_gradient_colors then p.health_gradient_colors = {} end
            pm.DeepCopyInto(p.health_gradient_colors, data)
        end,
        refresh = function() private.PlayerHealthBar.Refresh() end,
    },
    {
        id = "general",
        label = "SEGMENT_GENERAL",
        desc = "SEGMENT_GENERAL_DESC",
        group = "general",
        extract = function(p)
            return {
                auto_hide = p.auto_hide,
                consumable_auto_hide = p.consumable_auto_hide,
                arcane_mana_bar = p.arcane_mana_bar,
                shaman_mana_bar = p.shaman_mana_bar,
                balance_mana_bar = p.balance_mana_bar,
                priest_mana_bar = p.priest_mana_bar,
                button_press = p.button_press,
                bar_border = p.bar_border,
                icon_border = p.icon_border,
                icon_zoom = p.icon_zoom,
                icon_aspect_ratio = p.icon_aspect_ratio,
                augmentation_ebon_might = p.augmentation_ebon_might,
                augmentation_ebon_might_show_stat = p.augmentation_ebon_might_show_stat,
                augmentation_ebon_might_crit_color_value = p.augmentation_ebon_might_crit_color_value,
                augmentation_ebon_might_crit_glow = p.augmentation_ebon_might_crit_glow,
                augmentation_ebon_might_live_update = p.augmentation_ebon_might_live_update,
                primary_resource_colors = p.primary_resource_colors,
            }
        end,
        apply = function(p, data)
            if data.auto_hide ~= nil then p.auto_hide = data.auto_hide end
            if data.consumable_auto_hide ~= nil then p.consumable_auto_hide = data.consumable_auto_hide end
            if data.arcane_mana_bar ~= nil then p.arcane_mana_bar = data.arcane_mana_bar end
            if data.shaman_mana_bar ~= nil then p.shaman_mana_bar = data.shaman_mana_bar end
            if data.balance_mana_bar ~= nil then p.balance_mana_bar = data.balance_mana_bar end
            if data.priest_mana_bar ~= nil then p.priest_mana_bar = data.priest_mana_bar end
            if data.button_press ~= nil then
                if not p.button_press then p.button_press = {} end
                pm.DeepCopyInto(p.button_press, data.button_press)
            end
            if data.bar_border then
                if not p.bar_border then p.bar_border = {} end
                pm.DeepCopyInto(p.bar_border, data.bar_border)
            end
            if data.icon_border then
                if not p.icon_border then p.icon_border = {} end
                pm.DeepCopyInto(p.icon_border, data.icon_border)
            end
            if data.icon_zoom ~= nil then p.icon_zoom = data.icon_zoom end
            if data.icon_aspect_ratio ~= nil then p.icon_aspect_ratio = data.icon_aspect_ratio end
            if data.augmentation_ebon_might ~= nil then p.augmentation_ebon_might = data.augmentation_ebon_might end
            if data.augmentation_ebon_might_show_stat ~= nil then p.augmentation_ebon_might_show_stat = data.augmentation_ebon_might_show_stat end
            if data.augmentation_ebon_might_crit_color_value then
                p.augmentation_ebon_might_crit_color_value = {
                    data.augmentation_ebon_might_crit_color_value[1],
                    data.augmentation_ebon_might_crit_color_value[2],
                    data.augmentation_ebon_might_crit_color_value[3],
                    data.augmentation_ebon_might_crit_color_value[4],
                }
            end
            if data.augmentation_ebon_might_crit_glow ~= nil then p.augmentation_ebon_might_crit_glow = data.augmentation_ebon_might_crit_glow end
            if data.augmentation_ebon_might_live_update ~= nil then p.augmentation_ebon_might_live_update = data.augmentation_ebon_might_live_update end
            if data.primary_resource_colors then
                if not p.primary_resource_colors then p.primary_resource_colors = {} end
                pm.DeepCopyInto(p.primary_resource_colors, data.primary_resource_colors)
            end
        end,
        valid = function(data)
            return fieldsAreTables(data, "button_press", "bar_border", "icon_border",
                "primary_resource_colors", "augmentation_ebon_might_crit_color_value")
        end,
        refresh = function() private.ComponentManager.RefreshAllComponents() end,
    },
    {
        id = "cooldown_layout_sync",
        label = "SEGMENT_COOLDOWN_LAYOUT_SYNC",
        desc = "SEGMENT_COOLDOWN_LAYOUT_SYNC_DESC",
        group = "general",
        extract = function(p)
            return {
                cooldown_layout_sync = p.cooldown_layout_sync,
                cooldown_layouts = p.cooldown_layouts,
            }
        end,
        apply = function(p, data)
            if data.cooldown_layout_sync ~= nil then
                p.cooldown_layout_sync = data.cooldown_layout_sync
            end
            if data.cooldown_layouts then
                if not p.cooldown_layouts then p.cooldown_layouts = {} end
                pm.DeepCopyInto(p.cooldown_layouts, data.cooldown_layouts)
            end
        end,
        valid = function(data) return fieldsAreTables(data, "cooldown_layouts") end,
        refresh = function() private.CooldownLayoutSync.OnProfileChanged() end,
        layoutRefresh = function() private.CooldownLayoutSync.OnProfileChanged() end,
    },
    {
        id = "breakpoint_pips",
        label = "SEGMENT_BREAKPOINT_PIPS",
        desc = "SEGMENT_BREAKPOINT_PIPS_DESC",
        group = "general",
        extract = function(p)
            return p.breakpoint_pips
        end,
        apply = function(p, data)
            if not p.breakpoint_pips then p.breakpoint_pips = {} end
            pm.DeepCopyInto(p.breakpoint_pips, data)
            -- Imported strings may carry legacy pre-2.13.2 spec keys; re-key
            -- immediately (see MigrateBreakpointPipKeys — OnProfileChanged
            -- does not cover the import paths).
            pm.MigrateBreakpointPipKeys(p)
        end,
        -- MigrateBreakpointPipKeys indexes `pips`, and so does every reader.
        valid = function(data) return fieldsAreTables(data, "pips") end,
        refresh = function()
            private.PrimaryResources.Refresh()
            -- Moved specs render their pips on the secondary continuous bar.
            private.SecondaryResources.Refresh()
        end,
    },
    {
        id = "layout",
        label = "SEGMENT_LAYOUT",
        desc = "SEGMENT_LAYOUT_DESC",
        group = "positioning",
        extract = function(p)
            if not p.components then return nil end
            local out = {}
            for _, name in ipairs(COMPONENT_NAMES) do
                local comp = p.components[name]
                if comp then
                    out[name] = {}
                    for _, key in ipairs(LAYOUT_KEYS) do
                        if comp[key] ~= nil then
                            out[name][key] = comp[key]
                        end
                    end
                end
            end
            -- Include additional frame layout (anchor_profile + enabled)
            if p.additional_frames then
                for id, afSettings in pairs(p.additional_frames) do
                    local afKey = "af:" .. id
                    out[afKey] = {}
                    for _, key in ipairs(LAYOUT_KEYS) do
                        if afSettings[key] ~= nil then
                            out[afKey][key] = afSettings[key]
                        end
                    end
                end
            end
            return out
        end,
        apply = function(p, data)
            if not p.components then p.components = {} end
            for name, layoutData in pairs(data) do
                -- Additional frame layout entries are prefixed with "af:"
                local afId = string.match(name, "^af:(.+)$")
                local target
                if afId then
                    -- Only onto a frame the profile already has: a layout entry
                    -- carries no frame_type, so creating one here left a typeless
                    -- stub. A frame that comes with this import arrives whole
                    -- through the additional_frames segment, layout keys included.
                    target = p.additional_frames and p.additional_frames[afId]
                else
                    if not p.components[name] then p.components[name] = {} end
                    target = p.components[name]
                end
                if target then
                    for _, key in ipairs(LAYOUT_KEYS) do
                        if layoutData[key] ~= nil then
                            if type(layoutData[key]) == "table" then
                                if type(target[key]) ~= "table" then
                                    target[key] = {}
                                end
                                pm.DeepCopyInto(target[key], layoutData[key])
                            else
                                target[key] = layoutData[key]
                            end
                        end
                    end
                end
            end
        end,
        valid = isTableOfTables,
        -- Direct reference for identity-based dedup in ImportSegmented.
        -- Assigned inline rather than by index so the SEGMENTS array order can
        -- change without breaking the assignment.
        refresh = pm.FullLayoutRefresh,
    },
}

-- Additional frames segment: exports the entire additional_frames table.
SEGMENTS[#SEGMENTS + 1] = {
    id = "additional_frames",
    label = "SEGMENT_ADDITIONAL_FRAMES",
    desc = "SEGMENT_ADDITIONAL_FRAMES_DESC",
    group = "components",
    extract = function(p)
        if not p.additional_frames or not next(p.additional_frames) then return nil end
        return p.additional_frames
    end,
    apply = function(p, data)
        if not p.additional_frames then p.additional_frames = {} end
        wipe(p.additional_frames)
        pm.DeepCopyInto(p.additional_frames, data)
    end,
    -- Every reader indexes a frame's settings.
    valid = isTableOfTables,
    refresh = function()
        private.AdditionalFrameManager.OnProfileChanged()
        pm.FullLayoutRefresh()
    end,
    layoutRefresh = function() private.AdditionalFrameManager.OnProfileChanged() end,
}

-- Icon overrides segment: exports the icon_overrides table.
SEGMENTS[#SEGMENTS + 1] = {
    id = "icon_overrides",
    label = "SEGMENT_ICON_OVERRIDES",
    desc = "SEGMENT_ICON_OVERRIDES_DESC",
    group = "general",
    extract = function(p)
        if not p.icon_overrides or not next(p.icon_overrides) then return nil end
        return p.icon_overrides
    end,
    apply = function(p, data)
        if not p.icon_overrides then p.icon_overrides = {} end
        wipe(p.icon_overrides)
        pm.DeepCopyInto(p.icon_overrides, data)
    end,
    refresh = function()
        pm.FullLayoutRefresh()
    end,
}

-- Spell alerts segment: the Tracking tab's per-spell alert lists.
SEGMENTS[#SEGMENTS + 1] = {
    id = "spell_alerts",
    label = "SEGMENT_SPELL_ALERTS",
    desc = "SEGMENT_SPELL_ALERTS_DESC",
    group = "general",
    extract = function(p)
        if type(p.spell_alerts) ~= "table" or not next(p.spell_alerts) then return nil end
        return p.spell_alerts
    end,
    apply = function(p, data)
        if not p.spell_alerts then p.spell_alerts = {} end
        wipe(p.spell_alerts)
        pm.DeepCopyInto(p.spell_alerts, data)
    end,
    -- CDMAlerts' rebuild walks each entry as a list.
    valid = isTableOfTables,
    refresh = function() private.CDMAlerts.Rebuild() end,
    -- No layout pass rebuilds the alert model.
    layoutRefresh = function() private.CDMAlerts.Rebuild() end,
}

-- Tracking overrides segment: exports the cdm_category_overrides table.
SEGMENTS[#SEGMENTS + 1] = {
    id = "tracking_overrides",
    label = "SEGMENT_TRACKING_OVERRIDES",
    desc = "SEGMENT_TRACKING_OVERRIDES_DESC",
    group = "general",
    extract = function(p)
        local t = p.cdm_category_overrides
        if type(t) ~= "table" then return nil end
        -- A layer's moves: the all-specs one (t itself) or a spec's.  Also
        -- the "Force active" flags (t.active), which have the same shape.
        local function hasMoves(layer)
            return type(layer) == "table"
                and ((type(layer.cooldown) == "table" and next(layer.cooldown) ~= nil)
                or (type(layer.aura) == "table" and next(layer.aura) ~= nil))
        end
        if hasMoves(t) or hasMoves(t.active) then return t end
        if type(t.spec) == "table" then
            for _, layer in pairs(t.spec) do
                if hasMoves(layer) then return t end
            end
        end
        return nil
    end,
    apply = function(p, data)
        if type(p.cdm_category_overrides) ~= "table" then p.cdm_category_overrides = {} end
        wipe(p.cdm_category_overrides)
        pm.DeepCopyInto(p.cdm_category_overrides, data)
        -- The overlay is baked into CDMDataSource's resolved model, so it must be
        -- dropped here and not only in `refresh`: ImportFullProfile applies
        -- segments after its OnProfileChanged has already fired and never runs
        -- a segment's refresh (patterns.md "Profile upgrade migrations need
        -- three call sites").  Coalesced, so the refresh below adds no rebuild.
        private.CDMDataSource.NotifyUserCategoryChanged()
    end,
    refresh = function()
        private.CDMDataSource.NotifyUserCategoryChanged()
    end,
}

-- Build visual-only segment definitions for each component.
-- These extract everything except LAYOUT_KEYS from a component's profile.
for _, compName in ipairs(COMPONENT_NAMES) do
    SEGMENTS[#SEGMENTS + 1] = {
        id = "component." .. compName,
        label = COMP_LABEL_MAP[compName],
        desc = COMP_DESC_MAP[compName],
        group = "components",
        extract = function(p)
            if not p.components or not p.components[compName] then return nil end
            local comp = p.components[compName]
            local out = {}
            local hasData = false
            for k, v in pairs(comp) do
                if not isLayoutKey[k] then
                    out[k] = v
                    hasData = true
                end
            end
            return hasData and out or nil
        end,
        apply = function(p, data)
            if not p.components then p.components = {} end
            if not p.components[compName] then p.components[compName] = {} end
            for k, v in pairs(data) do
                -- Accept visibility_rules even though it moved to LAYOUT_KEYS (backward compat with old exports)
                if not isLayoutKey[k] or k == "visibility_rules" then
                    if type(v) == "table" then
                        if type(p.components[compName][k]) ~= "table" then
                            p.components[compName][k] = {}
                        end
                        pm.DeepCopyInto(p.components[compName][k], v)
                    else
                        p.components[compName][k] = v
                    end
                end
            end
        end,
        refresh = pm.MakeComponentRefresh(compName),
    }
end


-- ---------------------------------------------------------------------------
-- Segment accessors
-- ---------------------------------------------------------------------------

---Return the full segment definition list (for UI iteration).
---@return segment_definition[]
function pm.GetSegments()
    return SEGMENTS
end

---Return the ordered segment group definitions (for UI section headers).
---@return segment_group[]
function pm.GetSegmentGroups()
    return SEGMENT_GROUPS
end

---Find a segment definition by its id.
---@param segId string
---@return segment_definition|nil
function pm.FindSegment(segId)
    for _, seg in ipairs(SEGMENTS) do
        if seg.id == segId then return seg end
    end
    return nil
end


-- ---------------------------------------------------------------------------
-- Export / Import helpers
-- ---------------------------------------------------------------------------

---Build the export envelope from a profile and selected segment ids.
---@param prof profile
---@param selectedIds table<string, boolean>
---@return table envelope
function pm.BuildExportEnvelope(prof, selectedIds, profileName)
    local segmentList = {}
    local data = {}
    for _, seg in ipairs(SEGMENTS) do
        if selectedIds[seg.id] then
            local extracted = seg.extract(prof)
            if extracted then
                segmentList[#segmentList + 1] = seg.id
                data[seg.id] = extracted
            end
        end
    end
    local envelope = {
        -- 2 (2026-09-22): always_show_tracked is the buff trackers' engine on its
        -- own.  A version-1 export carries it as `false` for every aura tracker
        -- whatever the player saw -- AceDB copies scalar defaults into the profile
        -- table, and the rendered engine came from Blizzard's viewer "Hide when
        -- inactive" on top -- so the import tail re-applies this profile's stored
        -- reading over a pre-2 payload (see reapplyHideWhenInactive).
        profile_export_version = 2,
        -- Name the profile actually being exported, not the active one: a
        -- non-active export would otherwise offer the importer the wrong name.
        name = profileName or public.db:GetCurrentProfile(),
        toc_version = select(4, GetBuildInfo()),
        segments = segmentList,
        data = data,
    }
    -- Include sharing metadata if present (roundtrip from previous import)
    if prof._sharing then
        envelope.semver = prof._sharing.semver
        envelope.url = prof._sharing.url
        envelope.version = prof._sharing.version
    end
    return envelope
end

-- Deepest nesting an import payload may carry. Real profiles sit far below it;
-- it only has to be finite, so a crafted string cannot overflow DeepCopyInto's
-- recursion halfway through an apply that has already wiped its target.
local MAX_IMPORT_DEPTH = 32

---True when `t` is a table nested no deeper than MAX_IMPORT_DEPTH.
---@param t any
---@param depth number
---@return boolean
local function isBoundedTable(t, depth)
    if type(t) ~= "table" or depth > MAX_IMPORT_DEPTH then return false end
    for _, v in pairs(t) do
        if type(v) == "table" and not isBoundedTable(v, depth + 1) then return false end
    end
    return true
end

---Every segment `extract` returns a table, so every `apply` copies its payload
---as one — and the additional_frames / icon_overrides applies `wipe()` the live
---table first. A payload that is not a table must be refused here, before any
---import path touches the profile, or it destroys that table and then throws.
---A segment whose `apply` indexes nested fields names their shape in `valid`,
---or a wrong one throws halfway through the apply.
---@param segments any
---@param data any
---@return string|nil errorMessage  nil when every payload is importable
local function checkSegmentData(segments, data)
    if type(segments) ~= "table" or type(data) ~= "table" then
        return "malformed import string"
    end
    for segId, payload in pairs(data) do
        local seg = pm.FindSegment(segId)
        if not isBoundedTable(payload, 1) or (seg and seg.valid and not seg.valid(payload)) then
            return "malformed segment: " .. tostring(segId)
        end
    end
end

---True when `v` is absent or a string.
---@param v any
---@return boolean
local function isOptionalString(v)
    return v == nil or type(v) == "string"
end

---Parse a decoded table into a structured result for the import UI.
---Handles both new envelope format and legacy full-profile strings.
---@param decoded any
---@return table|nil parsedEnvelope  { name, toc_version, semver, url, version, export_version, segments, data }
---@return string|nil errorMessage
function pm.ParseEnvelope(decoded)
    if type(decoded) ~= "table" then return nil, "malformed import string" end
    -- New envelope format: has profile_export_version and segments
    if decoded.profile_export_version and decoded.segments then
        -- The confirm dialog formats these and `name` becomes a profile name;
        -- finishImport compares the version numerically, after the apply.
        if not (isOptionalString(decoded.name) and isOptionalString(decoded.semver)
            and isOptionalString(decoded.url)
            and type(decoded.profile_export_version) == "number") then
            return nil, "malformed import string"
        end
        local err = checkSegmentData(decoded.segments, decoded.data)
        if err then return nil, err end
        return {
            name = decoded.name,
            toc_version = decoded.toc_version,
            semver = decoded.semver,
            url = decoded.url,
            -- The sharing REVISION.  `export_version` is the envelope format's
            -- own version, which the import tail branches on; a legacy
            -- full-profile string has neither, which counts as pre-2.
            version = decoded.version,
            export_version = decoded.profile_export_version,
            segments = decoded.segments,
            data = decoded.data,
        }
    end
    -- Legacy full-profile string: wrap the entire table as all segments.
    -- The extracts index these tables before any payload is checked.
    if (decoded.components ~= nil and not isTableOfTables(decoded.components))
        or (decoded.additional_frames ~= nil and not isTableOfTables(decoded.additional_frames))
        or (decoded.icon_overrides ~= nil and type(decoded.icon_overrides) ~= "table") then
        return nil, "malformed import string"
    end
    local segmentList = {}
    local data = {}
    for _, seg in ipairs(SEGMENTS) do
        local extracted = seg.extract(decoded)
        if extracted then
            segmentList[#segmentList + 1] = seg.id
            data[seg.id] = extracted
        end
    end
    local err = checkSegmentData(segmentList, data)
    if err then return nil, err end
    return {
        segments = segmentList,
        data = data,
    }
end


-- ---------------------------------------------------------------------------
-- Profile lifecycle
-- ---------------------------------------------------------------------------

---Unified profile-change handler. Called from Init.lua's AceDB callbacks
---(OnProfileChanged, OnProfileCopied, OnProfileReset).
---Swaps the profile reference, reconciles component lifecycle, runs a
---three-pass layout refresh, and notifies CooldownLayoutSync.
---First-run migration: when a profile is loaded for the first time, mirror
---Blizzard's per-viewer CDM "In Combat" Visible Setting into the addon's
---own `visibility_rules.out_of_combat = "hide"` for the matching tracker.
---Other CDM settings (Always, Hidden) leave addon settings unchanged.
---
---Written when the addon stopped taking its visibility from Blizzard's viewer:
---without this migration, users who previously relied on Blizzard's "In Combat
---Only" would have seen their trackers always visible after upgrading.
---
---The flag `_blizzard_cdm_visibility_migrated` is per-profile and NOT in
---defaultSettings so AceDB's removeDefaults() never strips it.  Deferred
---(flag not set) when any CDM viewer is not yet reporting a setting value,
---so a later login retries.
function pm.MigrateCDMVisibility()
    if not private.profile then return end
    if private.profile._blizzard_cdm_visibility_migrated then return end

    local readings = {}
    for componentName, viewerKey in pairs(private.Util.CDM_COMPONENT_VIEWER_KEYS) do
        local s = private.Util.GetViewerVisibleSetting(viewerKey)
        if s == nil then return end
        readings[componentName] = s
    end

    for componentName, setting in pairs(readings) do
        if setting == Enum.CooldownViewerVisibleSetting.InCombat then
            local compSettings = private.profile.components[componentName]
            if compSettings then
                -- Leave `visibility` untouched: the out_of_combat rule is
                -- additive across all visibility modes (incl. "inherit" and
                -- "auto"), so we don't clobber a deliberate "auto" choice.
                compSettings.visibility_rules = compSettings.visibility_rules or {}
                compSettings.visibility_rules.fade_alpha = compSettings.visibility_rules.fade_alpha or 30
                compSettings.visibility_rules.out_of_combat = "hide"
            end
        end
    end
    -- At login this runs after Anchor.Initialize's rule scan, and nothing else
    -- rescans before the first pull: a rule written here would miss the
    -- combat-entry pass that applies it.
    private.Anchor.InvalidateTargetRuleCache()

    private.profile._blizzard_cdm_visibility_migrated = true
end

---What each CDM viewer's "Hide when inactive" setting used to drive.
local HIDE_INACTIVE_TARGETS = {
    BuffIcon = { component = "BuffTracker", frameType = "buffs" },
    BuffBar = { component = "BuffTrackerBars", frameType = "bar" },
}

---Turn the always-show (slots) engine on for everything one CDM viewer fed.
---`doComponent` / `doFrames` let the import tail write only what the import
---actually applied; the migration passes both.
---@param profile profile
---@param viewerKey string  "BuffIcon" | "BuffBar"
---@param doComponent boolean
---@param doFrames boolean
local function applyAlwaysShowTracked(profile, viewerKey, doComponent, doFrames)
    local target = HIDE_INACTIVE_TARGETS[viewerKey]
    local compSettings = doComponent and profile.components and profile.components[target.component]
    if compSettings then compSettings.always_show_tracked = true end
    if doFrames and profile.additional_frames then
        for _, af in pairs(profile.additional_frames) do
            if af.frame_type == target.frameType then af.always_show_tracked = true end
        end
    end
end

---First-run migration: copy Blizzard's per-viewer "Hide when inactive" into the
---buff trackers' own `always_show_tracked`, the last CDM setting CUE read live
---(`IsUsingSlots` used to OR in `not viewer:GetHideWhenInactive()`).
---
---A `false` reading turns `always_show_tracked` on for every tracker that viewer
---fed: BuffTracker and "buffs" Additional Frames (BuffIcon), BuffTrackerBars and
---"bar" Additional Frames (BuffBar).  `true` writes nothing: those trackers
---already render groups with the option off.  `false` is always the player's
---choice, since only Edit Mode's setter writes it (`SetHideWhenInactive(value ==
---1)`, EditModeSystemTemplates.lua); an unapplied setting reads nil.
---
---Both viewers are read before anything is written.  A missing viewer or a nil
---reading defers the whole migration, so a later login or profile change
---retries.  A nil reading already rendered as groups, so deferring changes
---nothing on screen.  A missing viewer used to render as slots, but
---Blizzard_CooldownViewer is not load-on-demand, so that case does not occur.
---
---The reading is stored per profile as `_blizzard_cdm_hide_inactive`
---(`{ BuffIcon = bool, BuffBar = bool }`), and its presence is the migrated flag.
---Not in defaultSettings, so AceDB's removeDefaults() never strips it.
function pm.MigrateHideWhenInactive()
    local profile = private.profile
    if not profile or profile._blizzard_cdm_hide_inactive then return end

    local reading = {}
    for _, viewerKey in ipairs({ "BuffIcon", "BuffBar" }) do
        local viewer = private.Util.GetViewerFrame(viewerKey)
        local hide = viewer and viewer.GetHideWhenInactive and viewer:GetHideWhenInactive()
        if hide == nil then return end
        reading[viewerKey] = hide
    end

    for viewerKey, hide in pairs(reading) do
        if hide == false then applyAlwaysShowTracked(profile, viewerKey, true, true) end
    end

    profile._blizzard_cdm_hide_inactive = reading
end

---One-shot upgrade: convert the legacy `proc_glow_hide` boolean into the
---`proc_glow_style` dropdown ("blizzard"|"border"|"none").
---
---Gated on `proc_glow_hide`, NOT on `proc_glow_style == nil`. `proc_glow_style`
---is a defaulted key, so AceDB's copyDefaults seeds it ("blizzard") on db init
---for every component that has it — a nil-check on it can never detect an
---un-migrated profile. The only reliable legacy signal is a leftover
---`proc_glow_hide` in saved variables: it is no longer a default key, so it
---survives copyDefaults and removeDefaults untouched until stripped here.
---
---Idempotent: nilling `proc_glow_hide` makes any later pass a no-op. The
---`proc_glow_style == "blizzard"` guard lets an explicit dropdown choice made
---on an older build win over the stale boolean. Components without proc glow
---never carry `proc_glow_hide`, so the loop skips them.
function pm.MigrateProcGlowStyle()
    if not private.profile then return end
    for _, settings in pairs(private.profile.components) do
        if settings.proc_glow_hide ~= nil then
            if settings.proc_glow_hide == true and settings.proc_glow_style == "blizzard" then
                settings.proc_glow_style = "none"
            end
            settings.proc_glow_hide = nil
        end
    end
end

---Legacy → per-bar breakpoint pip key map for the specs whose combat resource
---moved from the primary bar to the SecondaryResources continuous bar in
---2.13.2. Mirrors movedSpecs in Core/Util/BreakpointPips.lua — keep in sync.
local legacyPipKeyMap = {
    ["SHAMAN-1"] = "SHAMAN-1-MAELSTROM", -- Elemental
    ["DRUID-1"] = "DRUID-1-LUNAR_POWER", -- Balance
    ["PRIEST-3"] = "PRIEST-3-INSANITY", -- Shadow
}

---Re-key breakpoint pips for the moved specs. A plain "CLASS-spec" key for
---these specs can only be legacy pre-move data — post-move, the primary
---(mana) bar stores under "CLASS-spec-MANA" and the secondary bar under
---"CLASS-spec-<TOKEN>" — so the rename is unambiguous, idempotent, and needs
---no migration marker. That marker-freedom is what makes imported old profile
---strings (which never carry a marker) migrate identically to live upgrades.
---
---Called from three sites, all required:
---1. Init.lua's PLAYER_LOGIN path — the initial profile load (AceDB fires no
---   OnProfileChanged callback for it).
---2. pm.OnProfileChanged() — profile switch/copy/reset.
---3. The breakpoint_pips segment's apply — both import paths funnel through
---   it, and neither is covered by (2): ImportFullProfile fires
---   OnProfileChanged BEFORE segment data lands, and in-place ImportSegmented
---   never fires it at all.
---
---Conflict rule: an existing new-key entry wins; the legacy key is dropped
---either way so it can never re-trigger. per_spec_enabled moves with `~= nil`
---checks because `false` (spec disabled) is meaningful and must be preserved.
---@param profile table?  profile to migrate; defaults to the live profile
function pm.MigrateBreakpointPipKeys(profile)
    profile = profile or private.profile
    local pipSettings = profile and profile.breakpoint_pips
    if not pipSettings then return end
    for oldKey, newKey in pairs(legacyPipKeyMap) do
        local pips = pipSettings.pips
        if pips and pips[oldKey] ~= nil then
            if pips[newKey] == nil then
                pips[newKey] = pips[oldKey]
            end
            pips[oldKey] = nil
        end
        local enabledMap = pipSettings.per_spec_enabled
        if type(enabledMap) == "table" and enabledMap[oldKey] ~= nil then
            if enabledMap[newKey] == nil then
                enabledMap[newKey] = enabledMap[oldKey]
            end
            enabledMap[oldKey] = nil
        end
    end
end

function pm.OnProfileChanged()
    -- Unregister additional frame components while the OLD profile is still
    -- active so their GetSettings() calls remain valid during any layout
    -- passes triggered by Hide() inside deactivateFrame.
    private.AdditionalFrameManager.UnregisterAllComponents()

    private.profile = public.db.profile
    -- This client's custom spells and frames, before the rebuild below reads them.
    private.ClientScope.Swap(private.profile)

    -- Mirror the new profile's debug flag into Start.lua's file-local so
    -- printdebug reflects the new profile's setting immediately.
    private.SetDebugMode(private.profile.debug_mode)
    private.SetDebugLogCapacity(private.profile.debug_log_size)

    -- Invalidate Util caches that are keyed on settings values — the new
    -- profile may have different keybind configuration.
    private.Util.InvalidateKeybindCache()

    -- The CDM model's display categories carry the OLD profile's
    -- cdm_category_overrides; the "OnProfileChanged" trigger below drops them
    -- only after FullLayoutRefresh has laid every tracker out against them.
    private.CDMDataSource.NotifyUserCategoryChanged()

    -- Rebuild additional frames from the new profile before migrating anchors
    -- so any additional frame containers exist for the anchor system.
    private.AdditionalFrameManager.OnProfileChanged()

    pm.MigrateCDMVisibility()
    pm.MigrateHideWhenInactive()
    pm.MigrateProcGlowStyle()
    pm.MigrateBreakpointPipKeys()

    -- The layout tail is FullLayoutRefresh, called rather than duplicated.  The
    -- two bodies were byte-identical apart from FullLayoutRefresh's leading
    -- InvalidateKeybindCache, so every fix landing in one silently missed the
    -- other — a profile switch takes this path, not FullLayoutRefresh's.
    pm.FullLayoutRefresh()

    private.CooldownLayoutSync.OnProfileChanged()
    private.Callback.Trigger("OnProfileChanged")

    deferLayoutIfInCombat()
end


-- ---------------------------------------------------------------------------
-- Profile query / switch (AceDB wrappers)
-- ---------------------------------------------------------------------------

---Return the name of the currently active profile.
---@return string
function pm.GetCurrentProfileKey()
    return public.db:GetCurrentProfile()
end

---Return all existing profile names in {[key]=true} format (Wago spec).
---@return table<string, boolean>
function pm.GetProfileKeys()
    local profiles = public.db:GetProfiles()
    local result = {}
    for _, key in ipairs(profiles) do
        result[key] = true
    end
    return result
end

---Switch to an existing (or new) profile by name.
---AceDB creates the profile if it does not exist. The OnProfileChanged
---callback registered in Init.lua calls pm.OnProfileChanged() to handle
---the full lifecycle refresh.
---@param key string
function pm.SetProfile(key)
    public.db:SetProfile(key)
end


-- ---------------------------------------------------------------------------
-- Full-profile import/export (Wago integration)
-- ---------------------------------------------------------------------------

---Export an entire profile as a compressed string.
---If profileKey is nil or matches the current profile, exports the active
---profile. Otherwise reads from the raw saved variables table.
---@param profileKey string|nil
---@return string|nil encodedString, string|nil errorMessage
function pm.ExportFullProfile(profileKey)
    local prof
    if profileKey and profileKey ~= public.db:GetCurrentProfile() then
        prof = public.db.sv.profiles[profileKey]
        if not prof then return nil, "profile not found" end
    else
        prof = public.db.profile
    end
    -- Export all segments
    local allIds = {}
    for _, seg in ipairs(SEGMENTS) do
        allIds[seg.id] = true
    end
    local envelope = pm.BuildExportEnvelope(prof, allIds, profileKey)
    return pm.CompressData(envelope)
end

---Keep a pre-2 export rendering as it did on the importing client.
---
---Until 2026-09-22 the buff trackers' engine was `always_show_tracked` OR
---Blizzard's viewer "Hide when inactive"; the engine is now the profile key
---alone, seeded once by pm.MigrateHideWhenInactive.  A version-1 export carries
---`always_show_tracked = false` for every aura tracker whatever the exporting
---player saw (AceDB copies scalar defaults into the profile table), so taking it
---literally would drop a player whose own viewer has the setting unchecked onto
---the groups engine, with the stored reading already present so nothing corrects
---it later.  Re-apply that stored reading over what the import just wrote, and
---only for the segments it applied.
---
---Reads no CDM: an unmigrated profile has no stored reading, and the next
---login's migration covers it.
---@param applied segment_definition[]
---@param exportVersion number|nil  nil = a legacy full-profile string, i.e. pre-2
local function reapplyHideWhenInactive(applied, exportVersion)
    if (exportVersion or 1) >= 2 then return end
    local profile = private.profile
    local reading = profile and profile._blizzard_cdm_hide_inactive
    if not reading then return end

    local appliedIds = {}
    for _, seg in ipairs(applied) do appliedIds[seg.id] = true end
    for viewerKey, hide in pairs(reading) do
        if hide == false then
            local target = HIDE_INACTIVE_TARGETS[viewerKey]
            applyAlwaysShowTracked(profile, viewerKey,
                appliedIds["component." .. target.component] == true,
                appliedIds.additional_frames == true)
        end
    end
end

---Tail shared by both import paths, run once the segment data has landed.
---
---MigrateProcGlowStyle runs here because neither path reaches
---pm.OnProfileChanged after its data lands (ImportFullProfile fires it before,
---in-place ImportSegmented never does), and an old export carries
---`proc_glow_hide` verbatim in every component segment.
---
---A due FullLayoutRefresh runs once and stands in for every segment `refresh`;
---each segment's `layoutRefresh` is the work it does not cover, run ahead of it.
---@param applied segment_definition[]
---@param fullLayout boolean
---@param exportVersion number|nil  the payload's `profile_export_version`
local function finishImport(applied, fullLayout, exportVersion)
    pm.MigrateProcGlowStyle()
    reapplyHideWhenInactive(applied, exportVersion)
    if fullLayout then
        for _, seg in ipairs(applied) do
            if seg.layoutRefresh then seg.layoutRefresh() end
        end
        pm.FullLayoutRefresh()
    else
        for _, seg in ipairs(applied) do
            seg.refresh()
        end
        -- FullLayoutRefresh rescans through MigrateAnchorProfiles; this path
        -- must too, or an imported combat/target rule misses the pass it picks.
        private.Anchor.InvalidateTargetRuleCache()
        private.Anchor.Refresh()
    end
end

---Import a full profile from an encoded string.
---Creates or switches to the target profile, then deep-copies the decoded
---data into it and runs a full layout refresh.
---@param profileString string
---@param profileKey string
---@return boolean success, string|nil errorMessage
function pm.ImportFullProfile(profileString, profileKey)
    if type(profileString) ~= "string" or type(profileKey) ~= "string" then
        return false, "invalid arguments"
    end

    local decoded, err = pm.DecompressData(profileString)
    if not decoded then
        return false, err
    end

    local envelope
    envelope, err = pm.ParseEnvelope(decoded)
    if not envelope then
        return false, err
    end

    -- Switch to the target profile (creates it if needed with defaults).
    -- This triggers onProfileChanged → pm.OnProfileChanged(), which sets
    -- private.profile = public.db.profile.
    public.db:SetProfile(profileKey)

    -- Apply all available segments to the now-active profile
    local applied = {}
    for _, segId in ipairs(envelope.segments) do
        local seg = pm.FindSegment(segId)
        if seg and envelope.data[segId] then
            seg.apply(private.profile, envelope.data[segId])
            applied[#applied + 1] = seg
        end
    end

    -- Store sharing metadata if present
    if envelope.semver or envelope.url or envelope.version then
        private.profile._sharing = {
            semver = envelope.semver,
            url = envelope.url,
            version = envelope.version,
        }
    end

    -- Full refresh since we just wrote into the profile after the callback
    finishImport(applied, true, envelope.export_version)
    -- SetProfile above already registered the deferral via OnProfileChanged;
    -- this covers the segment data written after it, and coalesces into the
    -- same single re-run.
    deferLayoutIfInCombat()

    return true
end


-- ---------------------------------------------------------------------------
-- Segmented import/export (Options UI)
-- ---------------------------------------------------------------------------

---Export selected segments from the current profile as a compressed string.
---@param selectedIds table<string, boolean>
---@return string
function pm.ExportSegmented(selectedIds)
    local envelope = pm.BuildExportEnvelope(private.profile, selectedIds)
    return pm.CompressData(envelope)
end

---Import selected segments into the current or a new profile.
---@param envelope table  parsed envelope from ParseEnvelope()
---@param selectedSegIds string[]  segment ids to import
---@param profileName string  target profile name (used when asNew = true)
---@param asNew boolean  if true, create/switch to profileName before applying
---@return boolean success, string|nil errorMessage
function pm.ImportSegmented(envelope, selectedSegIds, profileName, asNew)
    if not envelope then return false, "no envelope" end
    if #selectedSegIds == 0 then return false, "no segments selected" end

    if asNew then
        public.db:SetProfile(profileName)
        private.profile = public.db.profile
    end

    local applied = {}
    local fullLayout = false
    for _, segId in ipairs(selectedSegIds) do
        local seg = pm.FindSegment(segId)
        if seg and envelope.data[segId] then
            seg.apply(private.profile, envelope.data[segId])
            applied[#applied + 1] = seg
            if seg.refresh == pm.FullLayoutRefresh then fullLayout = true end
        end
    end

    -- Store sharing metadata if present
    if envelope.semver or envelope.url or envelope.version then
        private.profile._sharing = {
            semver = envelope.semver,
            url = envelope.url,
            version = envelope.version,
        }
    end

    finishImport(applied, fullLayout, envelope.export_version)
    -- An in-place import (asNew = false) fires no AceDB callback, so this is
    -- the only site that can schedule its post-combat re-layout.  With
    -- asNew = true the SetProfile above already registered one; this coalesces
    -- into it.
    deferLayoutIfInCombat()

    return true
end

---Decode an import string without applying it.
---Returns the parsed envelope table for inspection.
---@param str string
---@return table|nil envelope, string|nil errorMessage
function pm.DecodeProfileString(str)
    local decoded, err = pm.DecompressData(str)
    if not decoded then return nil, err end
    return pm.ParseEnvelope(decoded)
end
