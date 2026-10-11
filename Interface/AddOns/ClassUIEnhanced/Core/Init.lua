
local _
---@type string, private
local addonName, private = ...

---@type detailsframework
local framework = _G["DetailsFramework"]

local L = private.L

---@type public
local public = framework:CreateAddOn("ClassUIEnhanced", "ClassUIEnhancedDB", private.defaultSettings)
private.public = public

function public:OnInit() --ADDON_LOADED
    local libDataBroker = LibStub("LibDataBroker-1.1")
    local libDBIcon = LibStub("LibDBIcon-1.0")

    local databroker = libDataBroker:NewDataObject("ClassUIEnhanced", {
        type = "launcher",
        icon = "Interface\\AddOns\\ClassUIEnhanced\\Assets\\Textures\\logo.png",
        text = "ClassUIEnhanced",
        OnClick = function(_, button)
            if button == "LeftButton" then
                if InCombatLockdown() then
                    private.print(L["CANNOT_OPEN_EDIT_MODE_COMBAT"])
                    return
                end
                ShowUIPanel(EditModeManagerFrame)
            elseif button == "RightButton" then
                if IsAltKeyDown() and private.PerfProfiler then
                    MenuUtil.CreateContextMenu(nil, function(_, rootDescription)
                        local perf = private.PerfProfiler
                        if perf.IsRunning() then
                            rootDescription:CreateButton("Stop Profiling", perf.Stop)
                        else
                            rootDescription:CreateButton("Start Profiling", perf.Start)
                        end
                        rootDescription:CreateButton("Show Report", perf.ShowReport)
                        rootDescription:CreateButton("Export Trace", perf.ExportTrace)
                    end)
                else
                    private.Options.ToggleOptionsPanel()
                end
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("ClassUIEnhanced")
            tooltip:AddLine(L["TOOLTIP_LEFT_CLICK"], 1, 1, 1)
            tooltip:AddLine(L["TOOLTIP_RIGHT_CLICK"], 1, 1, 1)
            if private.PerfProfiler then
                tooltip:AddLine("ALT+Right-Click: Perf tools", 0.5, 0.5, 0.5)
            end
        end,
    })

    libDBIcon:Register("ClassUIEnhanced", databroker, self.db.global.minimap)
    libDBIcon:AddButtonToCompartment("ClassUIEnhanced")
    private.libDBIcon = libDBIcon

    -- Register AceDBOptions profile management table with AceConfig so the options
    -- panel can embed the standard profile UI via AceConfigDialog.
    local AceConfig = LibStub("AceConfig-3.0")
    local AceDBOptions = LibStub("AceDBOptions-3.0")
    -- Reset and Copy From overwrite the current profile, and stock AceDBOptions
    -- asks only before Delete. Its `args` is ONE table shared by every addon on
    -- the library (and re-assigned on a library upgrade), so the confirms go on
    -- private copies of those two entries inside a table of our own.
    local db = self.db
    local aceProfiles = AceDBOptions:GetOptionsTable(db, true)
    local args = {}
    for key, entry in pairs(aceProfiles.args) do args[key] = entry end
    local function withConfirm(entry, confirm)
        local copy = {}
        for k, v in pairs(entry) do copy[k] = v end
        copy.confirm = confirm
        return copy
    end
    args.reset = withConfirm(args.reset, function()
        return string.format(L["PROFILE_RESET_CONFIRM"], db:GetCurrentProfile())
    end)
    args.copyfrom = withConfirm(args.copyfrom, function(_, source)
        return string.format(L["PROFILE_COPY_CONFIRM"], db:GetCurrentProfile(), source)
    end)
    AceConfig:RegisterOptionsTable("ClassUIEnhanced-Profiles", {
        type = "group",
        name = aceProfiles.name,
        desc = aceProfiles.desc,
        handler = aceProfiles.handler,
        args = args,
    })

    -- Keep private.profile in sync when profiles are changed via AceConfigDialog
    -- (switch, copy, or reset). Delegates to ProfileManager.OnProfileChanged()
    -- which swaps the profile reference, reconciles component lifecycle, runs a
    -- three-pass layout refresh, and notifies CooldownLayoutSync.
    local function onProfileChanged()
        private.ProfileManager.OnProfileChanged()
    end
    self.db.RegisterCallback(self, "OnProfileChanged", onProfileChanged)
    self.db.RegisterCallback(self, "OnProfileCopied", onProfileChanged)
    self.db.RegisterCallback(self, "OnProfileReset", onProfileChanged)
end

function public:OnEnable() --PLAYER_LOGIN
    private.profile = self.db.profile
    -- Before anything reads it: this client's custom spells and frames (#27).
    private.ClientScope.Swap(private.profile)
    -- Character-scoped, profile-independent store.  Three fields, all about how
    -- this character coexists with Blizzard's Cooldown Manager: cdm_hidden (the
    -- player agreed to turn it off), cdm_never_ask (never prompt about turning
    -- it off) and cdm_no_suppress (never hide its frames).  The first is why
    -- suppression survives a reload at all.
    -- Character-scoped so they survive profile switches and never
    -- travel in an export, where they would carry one player's addon
    -- environment onto another's (CDMDataSource).
    private.charDB = self.db.char

    -- Nothing in the addon reads a CooldownViewer child any more, so this never
    -- turns the CDM on; it works out that the CVar could go off and ASKS.  Run
    -- before components initialize so the answer is settled for the first layout
    -- pass.
    private.CDMDataSource.EnsureEnabled()

    -- Mirror saved debug flag into Start.lua's file-local so printdebug can
    -- short-circuit on the local without re-reading the profile each call.
    if private.profile.debug_mode then
        private.SetDebugMode(true)
    end
    private.SetDebugLogCapacity(private.profile.debug_log_size)

    --initialize components
    private.BuffTracker.Initialize()
    private.BuffTrackerBars.Initialize()
    private.CooldownTracker.Initialize()
    private.UtilitiesTracker.Initialize()
    private.TrinketTracker.Initialize()
    private.RacialTracker.Initialize()
    private.ConsumableTracker.Initialize()
    private.ConsumableBuffTracker.Initialize()
    private.RaidBuffTracker.Initialize()
    private.OutboundBuffTracker.Initialize()
    private.PlayerCastBar.Initialize()
    private.TargetCastBar.Initialize()
    private.FocusCastBar.Initialize()
    private.GlobalCooldown.Initialize()
    private.PrimaryResources.Initialize()
    private.PlayerHealthBar.Initialize()
    private.SecondaryResources.Initialize()

    --initialize additional frames (user-defined spell routing)
    private.AdditionalFrameManager.Initialize()

    --initialize anchoring system
    private.Anchor.Initialize()

    --register frames with LibEditMode for in-game repositioning
    private.EditMode.Initialize()

    --register CooldownViewer layout sync (per-spec save/restore)
    private.CooldownLayoutSync.Initialize()

    --register automatic spec/role profile switching
    private.SpecProfileSync.Initialize()

    --initialize button press overlay hooks
    private.ButtonPress.Initialize()

    -- Offer our tracker containers to Plater_UnitFrames as anchor parents — the
    -- mirror of `ClassUIEnhancedAPI.AddAnchors`, which PUF calls on us.  Their
    -- side is position-only (alpha is the one thing that crosses), resolves the
    -- global name on every placement pass, so registering a container that has
    -- not been created yet is fine, and has no unregister.
    -- ponytail: the four main trackers only; add more names here on demand.
    if _G.PlaterUnitFrames and _G.PlaterUnitFrames.AddAnchors then
        _G.PlaterUnitFrames.AddAnchors("ClassUIEnhanced", {
            CUE_BT_Container = "CUE " .. L["COMP_BUFF_TRACKER"],
            CUE_BTB_Container = "CUE " .. L["COMP_BUFF_TRACKER_BARS"],
            CUE_CT_Container = "CUE " .. L["COMP_COOLDOWN_TRACKER"],
            CUE_UT_Container = "CUE " .. L["COMP_UTILITIES_TRACKER"],
        })
    end

    -- Deferred three-pass refresh: Blizzard's ApplySystemAnchor may have
    -- overwritten viewer positions on login (see patterns.md "Three-Pass Refresh").
    -- Wait for LOADING_SCREEN_DISABLED rather than a single-frame defer — the
    -- loading screen must finish before Blizzard frames are fully positioned.
    local initKey = "ClassUIEnhanced_InitLayout"
    EventRegistry:RegisterFrameEventAndCallback("LOADING_SCREEN_DISABLED", function()
        EventRegistry:UnregisterFrameEventAndCallback("LOADING_SCREEN_DISABLED", initKey)
        -- Suppress CDM viewer rendering (kept shown at alpha 0 so Additional
        -- Frames / SecondaryResources / Options pickers keep live viewer
        -- children). Also registers OnCDMSpellsChanged coalesced callback.
        private.CDMDataSource.Initialize()

        -- Re-implements Blizzard's CDM alerts (sounds/glows), lost whenever a
        -- viewer never actually shows (the CVar-off path most CUE profiles
        -- run under) and so never runs Blizzard's own alert engine; see
        -- Core/CDMAlerts.lua.
        private.CDMAlerts.Initialize()

        -- First-run migration: import Blizzard CDM Visible Setting into the
        -- addon's own visibility_rules.  Runs before the first Anchor.Refresh
        -- so any migrated `out_of_combat = "hide"` rule takes effect on the
        -- initial layout pass.  No-op on subsequent logins (per-profile flag).
        private.ProfileManager.MigrateCDMVisibility()

        -- First-run migration: copy Blizzard's per-viewer "Hide when inactive"
        -- into the buff trackers' own always_show_tracked, the last CDM setting
        -- they used to read live.  Same timing and flagging as the one above.
        private.ProfileManager.MigrateHideWhenInactive()

        -- Upgrade migration: convert the legacy proc_glow_hide boolean to the
        -- proc_glow_style dropdown. Self-disabling once the old key is gone.
        private.ProfileManager.MigrateProcGlowStyle()

        -- Upgrade migration: re-key legacy breakpoint pips of the moved
        -- caster specs (Elemental/Balance/Shadow) to per-bar keys.
        -- Marker-free and idempotent; also runs on profile switch and import.
        private.ProfileManager.MigrateBreakpointPipKeys()

        -- Build custom-spell pools for built-in trackers. Their `OnEnable` is
        -- not called on /reload (PLAYER_LOGIN goes through `Refresh`, not
        -- `OnEnable`), so without this the saved `custom_spells` entries
        -- would not appear until the user toggled a component. Must run
        -- before the first `RefreshAllComponents` so `GetSpellMapFor` returns
        -- the saved entries during the initial layout pass.
        private.CustomSpells.Initialize()

        -- First pass: simulate EditMode to force full initialization of all
        -- components (including disabled ones), ensuring containers get sized
        -- and viewer children are fully wired up. `isInitializing` lets paths
        -- that are EditMode-only by *user intent* (e.g. CT's override-preview
        -- I3-exception) opt out of this simulated pass — the user is not
        -- actually in the editor, they just logged in.
        private.isInitializing = true
        private.isEditMode = true
        private.Anchor.Refresh()
        private.ComponentManager.RefreshAllComponents()
        private.Anchor.Refresh()
        -- Immediately restore normal state so hooks checking isEditMode
        -- behave normally from this point on.
        private.isEditMode = false
        private.isInitializing = false

        -- Re-register components with EditMode that were skipped during
        -- Initialize (GetFrame returned nil when viewers were hidden).
        private.EditMode.Refresh()

        -- Deferred pass: Blizzard finishes populating CooldownViewer children
        -- (GetChildren/layoutIndex) in the next frame, so re-run the full
        -- refresh so AF applyFilteredLayout finds all icons.
        C_Timer.After(0, function()
            if not private.profile then return end
            private.Anchor.Refresh()
            private.ComponentManager.RefreshAllComponents()
            private.Anchor.Refresh()
        end)
    end, initKey)

    -- Track external changes to the CDM CVar (Blizzard's settings panel,
    -- console, other addons). CVAR_UPDATE fires with the CVar name as the first
    -- payload argument.  The CVar is ours, so reconcile it in BOTH directions:
    -- EnsureEnabled re-derives the wanted value from the profile and
    -- guard-writes it, so an external flip either way is corrected and an
    -- already-correct value costs one GetCVar.  Our own corrective SetCVar
    -- re-fires CVAR_UPDATE, which then no-ops on the guard.
    local cvarFrame = CreateFrame("Frame")
    cvarFrame:RegisterEvent("CVAR_UPDATE")
    cvarFrame:SetScript("OnEvent", function(_, _, cvarName)
        if cvarName ~= "cooldownViewerEnabled" then return end
        if not private.profile then return end
        private.CDMDataSource.EnsureEnabled()
        private.CDMDataSource.SyncViewerSuppression()
    end)
end
