---@class private
local _, private = ...

-- ClassUIEnhanced — CDM Alerts
--
-- Re-implements Blizzard's Cooldown Manager (CDM) alerts
-- (the per-item sound/visual alerts configured in Blizzard's CDM settings)
-- inside ClassUIEnhanced. CUE keeps every CDM viewer alive but suppressed
-- (`Core/CDMDataSource.lua`), and a viewer that is actually SHOWN still runs
-- Blizzard's own alert engine — `CooldownViewerMixin:OnShow`
-- (CooldownViewer.lua:1733) registers the aura/cooldown events and drives
-- OnUpdate, which is the alert clock; `OnHide` (:1747) unregisters all of it,
-- and a hidden frame runs no OnUpdate. So this module must never fire an
-- alert for a key whose owning viewer is currently shown, or the player
-- hears/sees it twice.
--
-- The module implements both halves of Blizzard's alert playback for tracked
-- keys: OnCooldownStateChanged fires the matching Available/OnCooldown alert
-- on a real edge with CUE's own playback -- sound and TTS straight to the C
-- API (`playAudibleAlert`), Visual on an addon-owned overlay
-- (`visualOverlays`); Blizzard's alert code is only ever READ, never run --
-- and ReleaseButton tears a pooled button's alert state
-- back down when IconTracker recycles it. Aura events (AddAuraSound
-- registrations, viewer OnShow/OnHide teardown) and Options widget
-- integration complete the system.
--
-- A spell can also carry CUE's own alert list (`profile.spell_alerts`, edited
-- from the Tracking tab's Alerts menu). It replaces the Cooldown Manager's
-- list for that spell in the replay and never stands down for Blizzard's
-- viewer; Blizzard's data is never written.

---@class CDMAlertsModule
---@field Initialize fun() Register the rebuild signals and run the first pass. Call once from Core/Init.lua.
---@field Rebuild fun() Re-read Blizzard's alert config and rebuild the model; coalesced to one rebuild per frame.
---@field IsEnabled fun(): boolean True when the profile master switch is on and the model resolved at least one key with alerts.
---@field OnCooldownStateChanged fun(key: number, onCooldown: boolean, button: Frame) Called once per active button per rendered frame from IconTracker's swipe pass; fires the matching cooldown alert on a real Available/OnCooldown edge.
---@field OnEquipSlotCooldownChanged fun(equipSlot: number, onCooldown: boolean, button: Frame) The same edge published by an equip SLOT rather than a tracker key, for TrinketTracker's own icons. No-op until a rebuild has seen an alert-carrying trinket entry for that slot.
---@field GetAuraVisualAlert fun(spellID: number): number|nil The Enum.VisualAlertType a tracked buff's OnAuraApplied Visual alert asks for, or nil. Rendered as a persistent glow on the aura button by the slots engine — the engine's own show/hide of that button is the alert's on/off.
---@field ReleaseButton fun(button: Frame) Called when IconTracker returns a pooled button to the pool; clears edge-detection state and releases any visual alerts still running on it.
---@field RebuildRegistrations fun() Rebuild, and re-apply the engine aura registrations even when the CDM-derived model is unchanged. Use instead of Rebuild whenever the master switch moved -- it is not visible to the rebuild's own change detection.
---@field NeedsBlizzardViewer fun(): boolean True while the model holds an alert only Blizzard's own viewer can play (`modelNeedsViewer`). Read by `CDMDataSource.needsViewerChildren`, which then keeps the CDM on and hidden.
---@field GetSpellAlerts fun(key: number): table[]|nil, table[]|nil CUE's own entry for a tracker key (well-formed records only; nil when the key follows the Cooldown Manager), and the Cooldown Manager's list for it at the last rebuild (Blizzard's records: read, never mutate).
---@field GetSpellAlertTypes fun(key: number): boolean, boolean Whether a sound / a visual alert plays for a key, from either source: the Tracking tab's markers.
---@field SetSpellAlerts fun(key: number, alerts: table[]|nil) Write CUE's own entry for a key (nil = back to the Cooldown Manager's list) and rebuild.
---@field CanPlay fun(alertType: number, alertEvent: number, payload: number): boolean Whether CUE can play this combination itself (Core/CDMAlerts.md "Coverage table").
---@field BlizzardPlaysToo fun(key: number): boolean The Cooldown Manager has alerts for this key and its viewer is shown, so Blizzard plays them alongside a CUE entry.
---@field PlaySample fun(alert: table, key: number, frame: Frame) Play one alert once through CUE's own players; a Visual plays on `frame`.
---@field GetPayloadText fun(alert: table): string The sound's or visual's name, from Blizzard's data tables.
local CDMAlerts = {}
private.CDMAlerts = CDMAlerts

---Per tracker key, every alert Blizzard has configured for it, bucketed by
---alert event: `[key][alertEvent] = { alert, alert, ... }`. Blizzard allows
---up to `GetMaxNumAlertsPerItem()` (3, CooldownViewerSettingsLayoutManager.lua)
---alerts per cooldownID and does not dedupe by event, so two different alerts
---(e.g. one Sound, one Visual) can legitimately share one event bucket.
---An `alert` is Blizzard's own live record — decode it with
---`CooldownViewerAlert_GetType` / `_GetEvent` / `_GetPayload`, never by index,
---and never mutate it.
---@type table<number, table<number, table[]>>
local alertsByKey = {}
---Which CDM viewer category (a `private.Enum.CooldownViewerCategoryIDs`
---value) gates one key with alerts — i.e. which viewer, if SHOWN, means
---Blizzard already fires this key's alerts and CUE must not play the audible
---ones. Visuals always play: they are drawn on CUE's own icon.
---@type table<number, number>
local entryCategory = {}

---Per tracker key, the Cooldown Manager's own alert list, flat and in walk
---order across every cooldownID resolving to the key. The Alerts menu's
---pre-fill, kept whether or not a CUE entry replaces it in `alertsByKey`.
---Blizzard's live records: never mutate.
---@type table<number, table[]>
local cdmAlertsByKey = {}

---Tracker keys whose `alertsByKey` entry is CUE's own (`profile.spell_alerts`).
---Exempt from the `blizzardOwnsAlerts` stand-down: Blizzard's viewer plays the
---Cooldown Manager's list, never this one.
---@type table<number, true>
local cueKeys = {}

---Base `resolvedSpellID` -> the `Enum.VisualAlertType` payload of the entry's
---`OnAuraApplied` Visual alert. Read by the aura trackers' slots engine, which
---renders it as a persistent glow on the aura button; see
---`Core/AuraTrackers.md`. Separate from `alertsBySpellID` because that index
---holds alert OBJECTS for the sound path and is keyed by event, while this one
---answers a single question — "what does this spell's buff icon glow like".
---@type table<number, number>
local auraVisualBySpellID = {}

---Equip slot (13/14) -> the `resolvedKey` of the trinket CDM entry that owns
---it, for the keys that carry alerts. `Components/TrinketTracker.lua` draws
---trinkets from the inventory slot and has never had a cooldownID, so this is
---the only bridge from its icons to Blizzard's alert config.
---@type table<number, number>
local equipSlotKey = {}

---The aura-side mirror of `alertsByKey`, keyed by `resolvedSpellID`
---(Core/CDMDataSource.lua) rather than `resolvedKey`: the aura trackers'
---spell maps come from `getTrackedSpellMap(..., includeLinked = true)`, whose
---key branch IS `resolvedSpellID` plus a linked-spell expansion
---(Core/CDMDataSource.lua:492-496), and the two genuinely differ — a 12.1
---item-backed entry has a synthetic `resolvedKey` and a nil `resolvedSpellID`
---(.context/api.md "spellID is nil for item entries"), and a linked-spell
---expansion can put a spellID in an aura tracker's map that appears in no
---`resolvedKey` at all. Only `OnAuraApplied`/`OnAuraRemoved` alerts of type
---Sound ever land here — a cooldown alert has no use for it, and the Visual
---half is answered by `auraVisualBySpellID` above, which needs one payload
---rather than a list of alert objects.
---@type table<number, table<number, table[]>>
local alertsBySpellID = {}
---Which CDM viewer category gates one spellID's aura alerts — the aura-side
---mirror of `entryCategory`. Written only for a spellID that ends up carrying
---at least one Sound alert, same invariant as `entryCategory`.
---@type table<number, number>
local entryCategoryBySpellID = {}

---The four VIEWER-BACKED CDM categories, mirroring `Core/CDMDataSource.lua`'s
---own VIEWER_KEYS_LIST. Two jobs, and they must stay together: these are the
---categories with a viewer to hook (`installAllAuraViewerHooks`) and the ones
---`Util.GetViewerFrame` will accept. The wider set the model is READ from is
---`MODEL_CATEGORY_IDS` below. `Enum.CooldownViewerCategory` (Essential=0,
---Utility=1, TrackedBuff=2, TrackedBar=3, CooldownViewerConstantsDocumentation.lua)
---and `private.Enum.CooldownViewerCategoryIDs` (CooldownEssential=0,
---CooldownUtility=1, BuffIcon=2, BuffBar=3, Core/Util/Util.lua) agree exactly
---for these four values, so a category read off `resolvedCategory` for any
---cooldownID this list produces is already a value `Util.GetViewerFrame`'s
---numeric form accepts — no explicit remap needed.
local ALERT_CATEGORY_IDS = {
    private.Enum.CooldownViewerCategoryIDs.CooldownEssential,
    private.Enum.CooldownViewerCategoryIDs.CooldownUtility,
    private.Enum.CooldownViewerCategoryIDs.BuffIcon,
    private.Enum.CooldownViewerCategoryIDs.BuffBar,
}

---The item categories (`Enum.CooldownViewerCategory` SpecAgnosticEssential 5,
---SpecAgnosticTracked 6, EquipSlotEssential 7, EquipSlotTracked 8).
---
---An alert is configured on the ENTRY, whatever category it currently sits in,
---and a trinket the player has NOT dragged into Essential/Utility stays here --
---which is no viewer at all, yet CUE draws it anyway through
---`Components/TrinketTracker.lua`. Leaving them out of the model walk meant an
---alert on an undragged trinket was in nobody's model: not Blizzard's, because
---no viewer renders the category, and not ours.
local ITEM_CATEGORY_IDS = { 5, 6, 7, 8 }

---Every category `performRebuild` reads alert config from. Deliberately a THIRD
---list rather than a widened `ALERT_CATEGORY_IDS`: that one also answers "which
---viewers are there to hook", and `installAllAuraViewerHooks` feeds it straight
---to `Util.GetViewerFrame`, which asserts `0 <= categoryId <= 3`. Merging the
---two meanings threw on the first item category and aborted `performRebuild` at
---its very first line, taking the whole model -- cooldown side included -- down
---with it. Pick the list by the consequence you mean (`.context/patterns.md`
---makes the same point about `secureComponents` vs `secureClickComponents`).
local MODEL_CATEGORY_IDS = {}
for _, id in ipairs(ALERT_CATEGORY_IDS) do
    MODEL_CATEGORY_IDS[#MODEL_CATEGORY_IDS + 1] = id
end
for _, id in ipairs(ITEM_CATEGORY_IDS) do
    MODEL_CATEGORY_IDS[#MODEL_CATEGORY_IDS + 1] = id
end

local initialized = false

---Trailing-edge debounce for `CDMAlerts.Rebuild`. A rebuild costs a walk of
---every category, entry and alert plus a teardown and re-add of every
---AddAuraSound id, and its triggers arrive in bursts spanning many frames, so
---one-frame coalescing does not collapse them.
local REBUILD_DEBOUNCE = 0.25

---Hard ceiling on how long the debounce may keep pushing a rebuild back. A
---trailing debounce alone starves for as long as signals keep arriving inside
---its window, and the failure is silent -- alerts would simply stop tracking
---config. Past this, the next signal rebuilds immediately instead of
---rescheduling.
local REBUILD_MAX_DELAY = 2.0

---Signature of the model the last rebuild ACTED on. A rebuild landing on the
---same string does nothing further — see `modelSignature`.
---@type string?
local lastModelSignature

---One-shot: run the next rebuild's tail whatever the signature says. Written
---only by `CDMAlerts.RebuildRegistrations`, for the one input `modelSignature`
---cannot see — the master switch, which changes what `applyAuraRegistrations`
---produces while the CDM-derived model is identical.
local forceReapply = false

---One-shot `OnLeaveCombat` handler: the rebuild whose registrations combat
---lockdown refused. Forward-declared: `performRebuild` registers it, and it
---calls `runRebuild`, defined after.
local rebuildAfterCombat

---The last answer of `modelNeedsViewer`, gated by the master switch: what
---`CDMAlerts.NeedsBlizzardViewer` reports.
local needsViewer = false

---@type FunctionContainer?
local rebuildTimer
---GetTime() of the first signal in the current burst, nil when idle.
---@type number?
local rebuildBurstStart

---A rebuild signal arrived while Blizzard's Cooldown Manager settings frame was
---open and was dropped; the frame's OnHide flushes it. Never a latch: the
---deferral re-tests the frame on the frame AFTER the signal, so a missed OnHide
---costs one delayed rebuild, not every future one.
---@type boolean
local deferredRebuild = false

---True while Blizzard's Cooldown Manager settings frame is open. Read from the
---frame rather than tracked with a flag of our own, so nothing can leave the
---deferral stuck on. `Blizzard_CooldownViewer` is not load-on-demand, but the
---nil guard keeps this honest if that ever changes.
---@return boolean
local function settingsFrameOpen()
    return CooldownViewerSettings ~= nil and CooldownViewerSettings:IsShown() == true
end

---Is Blizzard's own alert engine alive for this category right now?
---
---Deliberately NOT the `cooldownViewerEnabled` CVar — wrong in both
---directions: the CVar can be on while a viewer's own `visibleSetting` keeps
---it hidden (the common CUE setup), and EditMode short-circuits the CVar
---check entirely. And deliberately NOT "is the viewer suppressed" — a
---CUE-suppressed viewer is forced SHOWN at alpha 0
---(`Core/CDMDataSource.lua`), so Blizzard's alerts genuinely still fire
---there. One `IsShown` read resolves every case.
---
---Gates AUDIBLE alerts only (sound, text-to-speech). A Visual is drawn on
---CUE's own icon, never Blizzard's, so it cannot double theirs -- and behind a
---CUE-suppressed viewer theirs renders at alpha 0, invisible. Gating visuals
---here was the bug that left the glow dark whenever the CDM was hidden.
---An ITEM category (5-8) always answers false, and not as a convenience: no
---viewer renders one. Every `CooldownViewerMixin:GetCooldownIDs` filters on
---`cooldownInfo.category == self:GetCategory()` and the four viewer categories
---are hardcoded 0-3 in `CooldownViewer.xml` (`:303/314/325/336`), so an
---item-backed entry left in its default category is in no viewer, gets no
---`OnShow`/`OnUpdate`, and Blizzard's alert clock never runs for it. Answering
---it through `Util.GetViewerFrame` is not an option either -- that asserts
---`0 <= categoryId <= 3`.
---@param categoryId number  a `private.Enum.CooldownViewerCategoryIDs` value, or an item category (5-8)
---@return boolean
local function blizzardOwnsAlerts(categoryId)
    if categoryId > private.Enum.CooldownViewerCategoryIDs.BuffBar then return false end
    local viewer = private.Util.GetViewerFrame(categoryId)
    return viewer ~= nil and viewer:IsShown() == true
end

-- Aura-event registration -----------------------------------------------
--
-- Under the 12.1 aura lockdown an addon cannot see aura applications at all,
-- so there is no fire-time check to mirror the cooldown path's
-- blizzardOwnsAlerts re-check: C_UnitAuras.AddAuraSound is a standing
-- registration that keeps firing until something calls RemoveAuraSound.
-- Every id created below must be recoverable (auraSoundIDs) and torn down on
-- every Rebuild and on PLAYER_LOGOUT.

---The AddAuraSound trigger for each of the two CDM aura alert events this
---module honours. `Enum.UnitAuraSoundTrigger.ApplicationsIncreased` is
---deliberately absent — the CDM never offers that event
---(CooldownViewerSettingsAlerts.lua), so no config could ever select it.
---Empty on MoP Classic, which predates AddAuraSound (12.1), so nothing registers.
---@type table<number, number>
local AURA_EVENT_TRIGGERS = Enum.UnitAuraSoundTrigger and {
    [Enum.CooldownViewerAlertEventType.OnAuraApplied] = Enum.UnitAuraSoundTrigger.Added,
    [Enum.CooldownViewerAlertEventType.OnAuraRemoved] = Enum.UnitAuraSoundTrigger.Removed,
} or {}

---Sound kit -> FileDataID for every CDM sound choice, so an aura alert can play
---the sound the player picked in Blizzard's own settings. AddAuraSound takes a
---FILE and a CDM alert stores a sound KIT; nothing at runtime converts one to
---the other, so the mapping is baked from DB2 `SoundKitEntry` (wago.tools,
---2026-09-11): each of the 93 kits in `CooldownViewerSoundAlertData.lua` has
---exactly one entry. The kit itself is read at runtime from Blizzard's own
---sound table (`soundKitForAlert`), so only this half is ours.
---ponytail: static table; a sound Blizzard adds later resolves nil and plays
---nothing until it is added here (or the CUE override is set).
---@type table<number, number>
local CDM_SOUNDKIT_FILE = {
    -- Animals
    [316401] = 7466002, [316406] = 7466004, [316407] = 7466006, [316409] = 7466010, [316715] = 7466951,
    [316411] = 7466012, [316412] = 7466014, [316413] = 7466016, [316414] = 7466018, [316415] = 7466020,
    -- Devices
    [316442] = 7466062, [316436] = 7466054, [316713] = 7466947, [316446] = 7466070, [316717] = 7466955,
    [316718] = 7466957, [316719] = 7466959, [316433] = 7466048, [316492] = 7466124, [316425] = 7466036,
    [316430] = 7466046,
    -- Impacts
    [316528] = 7466899, [316419] = 7466026, [316531] = 7466901, [316532] = 7466903, [316486] = 7466116,
    [316484] = 7466112, [316536] = 7466913, [316434] = 7466050, [316453] = 7466082, [316535] = 7466911,
    -- Instruments
    [316493] = 7466126, [316712] = 7466945, [316722] = 7466965, [316447] = 7466072, [316477] = 7466098,
    [316482] = 7466108, [316509] = 7466148, [316501] = 7466138, [316540] = 7466915, [316476] = 7466096,
    [316460] = 7466092, [316723] = 7466967,
    -- Short
    [353392] = 7962218, [353387] = 7962208, [353388] = 7962210, [353389] = 7962212, [353424] = 7962220,
    [353393] = 7962222, [353395] = 7962224, [353404] = 7962236, [353405] = 7962238, [353406] = 7962240,
    [353407] = 7962242, [353408] = 7962244, [353410] = 7962246, [353425] = 7962248, [353417] = 7962256,
    [353419] = 7962258, [353420] = 7962260, [353421] = 7962262, [353402] = 7962234, [353400] = 7962232,
    [353397] = 7962228, [353399] = 7962230, [353423] = 7962266, [353426] = 7962268, [353427] = 7962270,
    [353428] = 7962272,
    -- War2
    [316731] = 7467017, [316733] = 7467021, [316735] = 7467023, [316736] = 7467025, [316745] = 7464792,
    [316738] = 7467029, [316746] = 7464794, [316748] = 7464798, [316749] = 7464800, [316739] = 7467031,
    [316740] = 7467033, [316737] = 7467027,
    -- War3
    [316773] = 7467088, [316774] = 7467090, [316768] = 7467080, [316775] = 7467092, [316769] = 7467082,
    [316776] = 7467094, [316770] = 7467072, [316778] = 7467098, [316771] = 7467084, [316765] = 7467074,
    [316779] = 7467100, [316766] = 7467076,
}

---CDM sound payload (`Enum.CooldownViewerSound`) -> sound kit, read out of
---Blizzard's `CooldownViewerSoundData` global -- the table their own
---`CooldownViewerUtil.GetSoundTypeSoundKit` answers from. Never ask THAT for
---it: it lazily builds its lookup on the first call
---(`CheckCreateSoundAlertData`, CooldownViewerUtil.lua:47), so a first call
---from addon code builds Blizzard's mapping tainted for the whole session.
---Walked with `pairs`, a superset of their `ipairs` walk.
---@type table<number, number>|nil
local soundKitByPayload
---The same walk's sound names, for the Alerts menu (`CDMAlerts.GetPayloadText`).
---@type table<number, string>|nil
local soundTextByPayload

---@param t table
local function collectSoundKits(t)
    for _, value in pairs(t) do
        if type(value) == "table" then
            if value.soundEnum and value.soundKitID then
                soundKitByPayload[value.soundEnum] = value.soundKitID
                soundTextByPayload[value.soundEnum] = value.text
            else
                collectSoundKits(value)
            end
        end
    end
end

---Build the payload maps on first use. Not cached while
---`CooldownViewerSoundData` is absent, so an early call cannot pin an empty
---map (.context/patterns.md "Lazy caches vs init order").
---@return boolean ready
local function ensureSoundData()
    if soundKitByPayload then return true end
    if not CooldownViewerSoundData then return false end
    soundKitByPayload, soundTextByPayload = {}, {}
    collectSoundKits(CooldownViewerSoundData)
    return true
end

---The sound kit a Sound alert plays, or nil (a Visual alert, text-to-speech,
---or a payload the table does not know).
---@param alert table  a CDM alert from the layout manager
---@return number|nil soundKitID
local function soundKitForAlert(alert)
    if CooldownViewerAlert_GetType(alert) ~= Enum.CooldownViewerAlertType.Sound then return nil end
    local payload = CooldownViewerAlert_GetPayload(alert)
    if payload == Enum.CooldownViewerSound.TextToSpeech then return nil end
    if not ensureSoundData() then return nil end
    return soundKitByPayload[payload]
end

---The file AddAuraSound should play for one event's alerts: the first alert
---whose Blizzard sound kit has a known file. Text-to-speech has no kit, so it
---plays nothing.
---@param alerts table[]  one `alertsBySpellID[spellID][event]` list
---@return number|nil soundFileID
local function resolveAuraSoundFile(alerts)
    for i = 1, #alerts do
        local kit = soundKitForAlert(alerts[i])
        local fileID = kit and CDM_SOUNDKIT_FILE[kit]
        if fileID then return fileID end
    end
    return nil
end

---Every `AddAuraSound` id currently held, so each is recoverable and
---removable: `auraSoundIDs[spellID][trigger] = auraSoundID`. This table IS the
---whole undo list — a leaked id is a sound that keeps firing for an alert
---nobody has configured any more.
---@type table<number, table<number, number>>
local auraSoundIDs = {}

---Remove every `AddAuraSound` id currently held, and forget them.
local function removeAllAuraSounds()
    for _, byTrigger in pairs(auraSoundIDs) do
        for _, auraSoundID in pairs(byTrigger) do
            C_UnitAuras.RemoveAuraSound(auraSoundID)
        end
    end
    wipe(auraSoundIDs)
end

---Single-entry stand-in for GetAuraIdentitySet's nil, so the registration loop
---has one shape. Never handed out; never held across a map key.
---@type table<number, true>
local singleIdScratch = {}

---Register every aura-event sound in Blizzard's alert config, straight from
---`alertsBySpellID`. A sound needs no icon, so what CUE's trackers draw has no
---say in which alerts play: Blizzard fires aura alerts from every viewer
---(`CooldownViewer.lua:1849-1873`), including an Essential or Utility entry's
---buff and a Tracked Bars entry whose bar tracker is off. Until 2026-09-23 the
---list came from the buff trackers' spell maps, and those alerts were silent.
---Assumes every id previously held has been removed by the caller
---(`reapplyAuraRegistrations`).
local function applyAuraRegistrations()
    if not CDMAlerts.IsEnabled() then return end

    -- `alertsBySpellID`/`entryCategoryBySpellID` are filed under the BASE
    -- spellID (performRebuild indexes them by GetResolvedEntry's base spellID).
    for ownerSpellID, byEvent in pairs(alertsBySpellID) do
        -- Same viewer gate as the cooldown path: Blizzard's own alert engine is
        -- still alive for the category that owns this spellID's CDM entry, so
        -- registering here would double up.
        local categoryId = entryCategoryBySpellID[ownerSpellID]
        if not (categoryId and blizzardOwnsAlerts(categoryId)) then
            -- Register the WHOLE identity set, not the base id: the engine
            -- watches for the id that actually manifests as a live aura, and for
            -- a CDM entry that is usually the linked one (DK Outbreak 77575 ->
            -- Virulent Plague 191587, .context/api.md).
            --
            -- Every distinct id, not one: there is no way to know ahead of time
            -- which of base, override and linked manifests on this character, and
            -- registering the wrong one means the alert never fires. The cost is
            -- at most an extra AddAuraSound that never fires; if two ids of one
            -- entry genuinely apply together, the sound plays once per id.
            -- Silent-never beats rare-double here.
            -- A by-name custom aura (#55) first, as the aura trackers'
            -- identitySetFor does: every id carrying its name.
            local idSet = private.CustomSpells.GetAuraIdSetAny(ownerSpellID)
                or private.CDMDataSource.GetAuraIdentitySet(ownerSpellID)
            if not idSet then
                -- No wider identity. Reused scratch: read-only elsewhere, and
                -- the loop below consumes it before the next entry is reached.
                wipe(singleIdScratch)
                singleIdScratch[ownerSpellID] = true
                idSet = singleIdScratch
            end
            for spellID in pairs(idSet) do
                for alertEvent, trigger in pairs(AURA_EVENT_TRIGGERS) do
                    local alerts = byEvent[alertEvent]
                    local soundFileID = alerts and resolveAuraSoundFile(alerts)
                    -- Two entries' identity sets can share a real spellID; the
                    -- first registers it, so the engine plays it once.
                    local held = auraSoundIDs[spellID]
                    if soundFileID and not (held and held[trigger]) then
                        local auraSoundID = C_UnitAuras.AddAuraSound(trigger, {
                            unitToken = "player",
                            spellID = spellID,
                            soundFileID = soundFileID,
                            outputChannel = "Gameplay SFX",
                        })
                        if auraSoundID then
                            if not held then
                                held = {}
                                auraSoundIDs[spellID] = held
                            end
                            held[trigger] = auraSoundID
                        end
                    end
                end
            end
        end
    end
end

---Tear down and re-register every aura-event sound against the
---freshly-rebuilt `alertsBySpellID`/`entryCategoryBySpellID`. Called at the
---end of every `performRebuild` — Blizzard's alert config and the per-category
---shown gate can both have moved since the last rebuild, and a leaked id would
---keep firing for an alert nobody has configured any more.
local function reapplyAuraRegistrations()
    removeAllAuraSounds()
    applyAuraRegistrations()
end

---Viewers already carrying the OnShow/OnHide -> Rebuild hooks below. Keyed by
---frame in an addon-side table — never a field on the viewer itself
---(patterns.md "Taint Prevention"). Weak keys so a viewer going away cannot
---pin it.
local auraHookInstalled = setmetatable({}, { __mode = "k" })

---Install the OnShow/OnHide -> Rebuild hooks on one CDM viewer. Idempotent,
---mirroring `CDMDataSource.installViewerSuppression`. Unlike the cooldown
---path, which re-checks `blizzardOwnsAlerts` on every fire, an `AddAuraSound`
---registration has no fire-time check: if a viewer becomes shown mid-session
---(another addon flips the CVar, EditMode, the CDM settings panel), our
---registrations would keep firing alongside Blizzard's until something
---rebuilds. `HookScript` is additive and insecure-safe.
---@param viewer frame
local function installAuraViewerHooks(viewer)
    if auraHookInstalled[viewer] then return end
    auraHookInstalled[viewer] = true
    viewer:HookScript("OnShow", CDMAlerts.Rebuild)
    viewer:HookScript("OnHide", CDMAlerts.Rebuild)
end

---Install the hooks above on every CDM viewer that exists right now. Called
---from `Initialize` (the fast path) AND from the start of every
---`performRebuild`. This is NOT a self-heal for a viewer `GetViewerFrame`
---once resolved as nil: `Util.lua`'s `cooldownViewerFramesById` is a table of
---`_G[...]` lookups baked at Util.lua LOAD TIME, so a category that resolves
---nil there stays nil for the rest of the session no matter how many times
---this runs. Calling it repeatedly is safe and cheap only because
---`installAuraViewerHooks` is idempotent (`auraHookInstalled`); in practice it
---has nothing new to do here, since `Blizzard_CooldownViewer.toc` carries no
---`LoadOnDemand` and all four viewer globals already exist by the time
---`Initialize()`'s own call runs, before any third-party addon loads.
local function installAllAuraViewerHooks()
    for _, categoryId in ipairs(ALERT_CATEGORY_IDS) do
        local viewer = private.Util.GetViewerFrame(categoryId)
        if viewer then
            installAuraViewerHooks(viewer)
        end
    end
end

---Everything a rebuild can change, as one comparable string: the cooldown-side
---key set with each key's category and Blizzard-owned state, and the aura-side
---(spellID -> alert events) index that is the whole of what
---`applyAuraRegistrations` reads out of the model, each event with its alerts'
---payloads: the payload picks the file AddAuraSound plays (CDM_SOUNDKIT_FILE),
---so a sound re-picked in Blizzard's settings has to count as a change.
---
---Sorted, because `pairs` order is not stable across rebuilds and an unstable
---signature would never match itself.
---@return string
local function modelSignature()
    local parts = {}
    for key, categoryId in pairs(entryCategory) do
        parts[#parts + 1] = ("k%s=%s%s"):format(tostring(key), tostring(categoryId),
            blizzardOwnsAlerts(categoryId) and "!" or "")
    end
    for spellID, byEvent in pairs(alertsBySpellID) do
        local events = {}
        for alertEvent, alerts in pairs(byEvent) do
            local entry = tostring(alertEvent)
            for i = 1, #alerts do
                entry = entry .. "~" .. tostring(CooldownViewerAlert_GetPayload(alerts[i]))
            end
            events[#events + 1] = entry
        end
        table.sort(events)
        parts[#parts + 1] = ("s%s=%s:%s"):format(tostring(spellID),
            tostring(entryCategoryBySpellID[spellID]), table.concat(events, "."))
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

---Does the model hold an alert that only Blizzard's own viewer can play?
---
---Sound or text-to-speech on `PandemicTime` or `ChargeGained`, which this
---module cannot replay at all (see the coverage table in Core/CDMAlerts.md),
---and text-to-speech on `OnAuraApplied` / `OnAuraRemoved`, which `AddAuraSound`
---cannot carry: it plays a file and never calls back. Visual alerts do not
---count, because Blizzard's would draw at alpha 0 behind the suppression.
---
---Only viewer categories count. An item category (5-8) is rendered by no
---viewer, so turning the CDM on would not play its alerts either.
---@param byKey table<number, table<number, table[]>>  `alertsByKey`
---@param categoryOf table<number, number>  `entryCategory`
---@return boolean
local function modelNeedsViewer(byKey, categoryOf)
    for key, byEvent in pairs(byKey) do
        if categoryOf[key] <= private.Enum.CooldownViewerCategoryIDs.BuffBar then
            for alertEvent, alerts in pairs(byEvent) do
                local anySound = alertEvent == Enum.CooldownViewerAlertEventType.PandemicTime
                    or alertEvent == Enum.CooldownViewerAlertEventType.ChargeGained
                local speechOnly = alertEvent == Enum.CooldownViewerAlertEventType.OnAuraApplied
                    or alertEvent == Enum.CooldownViewerAlertEventType.OnAuraRemoved
                for i = 1, #alerts do
                    local alert = alerts[i]
                    if CooldownViewerAlert_GetType(alert) == Enum.CooldownViewerAlertType.Sound
                        and (anySound or (speechOnly
                            and CooldownViewerAlert_GetPayload(alert) == Enum.CooldownViewerSound.TextToSpeech)) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

---Add one alert to an event-bucketed index: `byKey[key][alertEvent]`.
---@param byKey table<number, table<number, table[]>>
---@param key number
---@param alert table
local function bucketAlert(byKey, key, alert)
    local alertEvent = CooldownViewerAlert_GetEvent(alert)
    local byEvent = byKey[key]
    if not byEvent then
        byEvent = {}
        byKey[key] = byEvent
    end
    local list = byEvent[alertEvent]
    if not list then
        list = {}
        byEvent[alertEvent] = list
    end
    list[#list + 1] = alert
end

---File one alert into the model the replay plays from: `alertsByKey`, plus
---the aura-side indices for an aura event.
---@param key number  tracker key
---@param spellID number|nil  the base spellID the aura side is keyed by; nil for an item-backed entry
---@param categoryId number|nil  the category whose shown viewer stands this alert's sound down; nil for a CUE entry, which never stands down
---@param alert table
local function fileAlert(key, spellID, categoryId, alert)
    bucketAlert(alertsByKey, key, alert)
    local alertEvent = CooldownViewerAlert_GetEvent(alert)

    -- Aura-side index: only the two aura events, and only for entries with a
    -- real spellID (nil for a 12.1 item-backed entry -- .context/api.md
    -- "spellID is nil for item entries" -- which an aura tracker's map can
    -- never contain).
    if not spellID or (alertEvent ~= Enum.CooldownViewerAlertEventType.OnAuraApplied
        and alertEvent ~= Enum.CooldownViewerAlertEventType.OnAuraRemoved) then
        return
    end
    local alertType = CooldownViewerAlert_GetType(alert)
    -- A Visual alert on OnAuraApplied becomes a PERSISTENT glow on the aura
    -- button, which the engine then shows for exactly as long as the aura
    -- lasts -- so the missing "when was it applied" callback is not needed.
    -- Every visual payload loops in Blizzard's own XML, so this is their
    -- animation, not a stand-in (Core/Util/GlowEffect.lua, CDM_ALERT_ART).
    --
    -- OnAuraRemoved is deliberately NOT indexed for visuals: the button
    -- hosting the glow is gone at the moment that alert should fire, so there
    -- is nothing to render it on.
    if alertEvent == Enum.CooldownViewerAlertEventType.OnAuraApplied
        and alertType == Enum.CooldownViewerAlertType.Visual then
        -- First one wins: Blizzard permits up to three alerts per item and
        -- does not dedupe by event, but two glows on one button would just
        -- overdraw.
        if auraVisualBySpellID[spellID] == nil then
            auraVisualBySpellID[spellID] = CooldownViewerAlert_GetPayload(alert)
        end
    end
    if alertType == Enum.CooldownViewerAlertType.Sound then
        entryCategoryBySpellID[spellID] = categoryId
        bucketAlert(alertsBySpellID, spellID, alert)
    end
end

---A saved `spell_alerts` record is Blizzard's `{ type, event, payload }`
---shape. Imported profiles are external data, so anything else is skipped
---rather than handed to the players.
---@param alert any
---@return boolean
local function isAlertRecord(alert)
    return type(alert) == "table" and type(alert[1]) == "number"
        and type(alert[2]) == "number" and type(alert[3]) == "number"
end

---File CUE's own entry for a key. No category, so nothing in it stands down
---for Blizzard's viewer. An empty list files nothing, which is what silences
---the spell.
---@param key number
---@param spellID number|nil
---@param list table[]
local function fileCueEntry(key, spellID, list)
    cueKeys[key] = true
    for i = 1, #list do
        if isAlertRecord(list[i]) then fileAlert(key, spellID, nil, list[i]) end
    end
end

---Re-read Blizzard's alert config for every currently-tracked key and
---rebuild `alertsByKey` / `entryCategory` (and their aura-side mirrors,
---`alertsBySpellID` / `entryCategoryBySpellID`) from scratch, with CUE's own
---entries (`profile.spell_alerts`) replacing the Cooldown Manager's list for
---their keys.
local function performRebuild()
    -- Idempotent re-assert, not a self-heal (see installAllAuraViewerHooks
    -- above) — a viewer that resolved nil at Initialize() resolves nil here
    -- too.
    installAllAuraViewerHooks()

    alertsByKey, entryCategory = {}, {}
    cdmAlertsByKey, cueKeys = {}, {}
    alertsBySpellID, entryCategoryBySpellID = {}, {}
    local hadVisuals = next(auraVisualBySpellID) ~= nil
    auraVisualBySpellID = {}
    equipSlotKey = {}
    -- The Cooldown Manager's lists alone, event-bucketed: what
    -- `modelNeedsViewer` reads. A CUE entry replaces a list in the replay,
    -- never in Blizzard's viewer.
    local cdmByKey = {}
    local cue = private.profile.spell_alerts

    local lm = CooldownViewerSettings:GetLayoutManager()
    if lm then
        for _, categoryId in ipairs(MODEL_CATEGORY_IDS) do
            -- Blizzard's category (third arg), not CUE's display one: a CUE-only
            -- move or hide must not change which entries get replayed.
            local cooldownIds = private.CDMDataSource.GetTrackedCooldownIDs(categoryId, true, true)
            for i = 1, #cooldownIds do
                local cooldownID = cooldownIds[i]
                local key, resolvedCategoryId, spellID = private.CDMDataSource.GetResolvedEntry(cooldownID)
                if key then
                    -- AccessOnly: AllowCreate WRITES into Blizzard's layout
                    -- (GetAlertsForLayout creates block.alerts on demand) —
                    -- the same CDM saved-data taint CDMDataSource already
                    -- refuses elsewhere. No active layout -> nil -> no alerts.
                    local alerts = lm:GetAlerts(cooldownID, Enum.CDMLayoutMode.AccessOnly)
                    if alerts and #alerts > 0 then
                        entryCategory[key] = resolvedCategoryId
                        -- Trinket bridge: an equip-slot entry is the only kind
                        -- a component addresses by something other than the
                        -- tracker key (TrinketTracker knows the slot, never the
                        -- cooldownID).  `GetIconSource` is a PEEK, and the walk
                        -- above has already resolved the model.
                        local source = private.CDMDataSource.GetIconSource(key)
                        if source and source.equipSlot then
                            equipSlotKey[source.equipSlot] = key
                        end
                        local cdmList = cdmAlertsByKey[key]
                        if not cdmList then
                            cdmList = {}
                            cdmAlertsByKey[key] = cdmList
                        end
                        for a = 1, #alerts do
                            local alert = alerts[a]
                            cdmList[#cdmList + 1] = alert
                            bucketAlert(cdmByKey, key, alert)
                            if type(cue[key]) ~= "table" then
                                fileAlert(key, spellID, resolvedCategoryId, alert)
                            end
                        end
                    end
                    if type(cue[key]) == "table" and not cueKeys[key] then
                        fileCueEntry(key, spellID, cue[key])
                    end
                end
            end
        end
    end

    -- CUE entries on spells with no Cooldown Manager entry (a custom or
    -- spellbook row): the tracker key is the spellID.
    for key, list in pairs(cue) do
        if type(key) == "number" and type(list) == "table" and not cueKeys[key] then
            fileCueEntry(key, key, list)
        end
    end

    -- An alert only Blizzard can play keeps the CDM on and hidden, as
    -- `cdm_target_sounds` does. Ahead of the signature test: the signature
    -- does not see a pandemic alert added to an entry that already had alerts.
    -- No loop: turning the CDM on shows the viewers, whose hooks rebuild, and
    -- this answer reads the config only, never `blizzardOwnsAlerts`.
    local needs = CDMAlerts.IsEnabled() and modelNeedsViewer(cdmByKey, entryCategory)
    if needs ~= needsViewer then
        needsViewer = needs
        private.CDMDataSource.EnsureEnabled()
    end

    -- The aura trackers read `auraVisualBySpellID` only from their own Refresh,
    -- and the OnCDMSpellsChanged that woke us refreshed them synchronously,
    -- REBUILD_DEBOUNCE ago -- against the previous map, empty at login. Nothing
    -- else re-runs that pass outside aura secrecy until combat ends, so the glow
    -- stayed dark until then. Ahead of the signature test on purpose: visuals
    -- are not in the signature. Skipped when there were and are no visuals, so
    -- a profile with none pays nothing.
    if hadVisuals or next(auraVisualBySpellID) ~= nil then
        private.Callback.Trigger("OnCDMAlertsChanged")
    end
    -- The Tracking tab's alert markers read `cdmAlertsByKey`, which only a
    -- rebuild moves; it listens only while shown, so this costs nothing else.
    private.Callback.Trigger("OnAlertModelRebuilt")

    -- Decide for OURSELVES whether anything moved, rather than trusting the
    -- signal that woke us. Every trigger upstream is a proxy at best:
    -- `OnCDMSpellsChanged` comes from `CDMDataSource`'s direct registration of
    -- `PLAYER_EQUIPMENT_CHANGED`, `SPELLS_CHANGED`, `PLAYER_PVP_TALENT_UPDATE`,
    -- `COOLDOWN_VIEWER_TABLE_HOTFIXED` and the spec events, and most of those
    -- move nothing we hold. Filtering them upstream would only make us miss
    -- real changes -- an equipped trinket genuinely IS a CDM entry -- so the
    -- frequency has to be answered where the answer is knowable: after the
    -- walk, by comparison.
    --
    -- The debounce (REBUILD_DEBOUNCE) collapses a burst. This collapses the
    -- steady drip a burst debounce cannot see, and it is what stops an ordinary
    -- gear swap tearing down and re-adding every AddAuraSound id.
    local signature = modelSignature()
    if signature == lastModelSignature and not forceReapply then return end
    -- `AddAuraSound` is HasRestrictions: ADDON_ACTION_BLOCKED in combat
    -- lockdown. Keep the held ids and leave the signature and force flag
    -- unconsumed, so the combat-exit rebuild still sees the change.
    if InCombatLockdown() then
        private.Callback.Register("OnLeaveCombat", rebuildAfterCombat)
        return
    end
    lastModelSignature = signature
    forceReapply = false

    reapplyAuraRegistrations()
end

---The debounced tail: decide between doing the work and parking it for the
---settings frame's close. Testing the frame HERE rather than in `Rebuild`
---means the test runs after the debounce, so it never depends on whether
---`IsShown` has already gone false when Blizzard fires its OnHide event --
---which is what the flush in `Initialize` rides on.
local function runRebuild()
    rebuildTimer = nil
    rebuildBurstStart = nil
    -- Every alert record is read through Blizzard's CooldownViewerAlert_*
    -- helpers, CUE's own entries included, so without the Cooldown Manager
    -- (MoP Classic) the model stays empty and nothing plays.
    if not private.compat.HasCooldownManager() then return end
    if settingsFrameOpen() then
        deferredRebuild = true
        return
    end
    deferredRebuild = false
    performRebuild()
end

rebuildAfterCombat = function()
    private.Callback.Unregister("OnLeaveCombat", rebuildAfterCombat)
    runRebuild()
end

---Re-read Blizzard's alert config, debounced to the trailing edge of a burst.
---
---Every signal this is registered against arrives in bursts, and they span
---many frames, so the previous one-frame coalescing collapsed almost nothing:
---
---  * `OnCDMSpellsChanged` follows CDMDataSource's direct registration of
---    SPELLS_CHANGED, PLAYER_PVP_TALENT_UPDATE, COOLDOWN_VIEWER_TABLE_HOTFIXED,
---    PLAYER_EQUIPMENT_CHANGED and the spec events -- and SPELLS_CHANGED storms
---    through a zone change. (Until 2026-09-22 this module also listened to
---    Blizzard's `CooldownViewerSettings.OnDataChanged`, which relays the same
---    events, so every one of them cost TWO rebuilds, a frame apart.)
---
---A rebuild is a walk of every category, every entry and every alert plus a
---teardown and re-add of every AddAuraSound id, so the burst was paying that
---repeatedly to arrive at the same answer.
---
---`REBUILD_MAX_DELAY` bounds the debounce. Without it a signal source firing
---faster than the window would starve the rebuild indefinitely, and nothing
---would report it -- alerts would just quietly stop tracking config.
---
---While Blizzard's settings frame is open the rebuild parks instead, and its
---OnHide flushes it. That also matches Blizzard's own commit point: the panel
---does not save until `CooldownViewerSettingsMixin:OnHide` calls
---`CheckSaveCurrentLayout`, and `performRebuild` reads its whole model from
---that frame's layout manager -- so rebuilding mid-edit was reacting to a
---layout the player had not chosen yet.
function CDMAlerts.Rebuild()
    local now = GetTime()
    if not rebuildBurstStart then rebuildBurstStart = now end
    if rebuildTimer then rebuildTimer:Cancel() end
    if now - rebuildBurstStart >= REBUILD_MAX_DELAY then
        runRebuild()
        return
    end
    rebuildTimer = C_Timer.NewTimer(REBUILD_DEBOUNCE, runRebuild)
end

---`Rebuild`, plus "re-apply the engine registrations even if the CDM-derived
---model comes back identical".
---
---`performRebuild` decides for itself whether to do anything, by comparing the
---model it just built (`modelSignature`). That comparison cannot see the one
---other input to `applyAuraRegistrations` — the profile's master switch — so
---anything that moves it must say so here rather than call `Rebuild` and
---silently get nothing.
---
---Deliberately a second function rather than a `Rebuild(force)` argument:
---`Rebuild` is registered directly as an event and callback handler in four
---places, where it is handed a frame, an event name or an owner as its first
---argument. A truthy-first-arg force would be on for every one of them, which
---is the behaviour this exists to stop.
function CDMAlerts.RebuildRegistrations()
    forceReapply = true
    CDMAlerts.Rebuild()
end

---True when the profile master switch is on AND the model actually has
---something to do. Resolving zero alerts (nothing configured in Blizzard's
---CDM) is a legitimate answer, not an unresolved one — callers read this
---to skip registrations entirely rather than pay for empty ones.
---@return boolean
function CDMAlerts.IsEnabled()
    local p = private.profile
    return p ~= nil and p.cdm_alerts == true and next(alertsByKey) ~= nil
end

---True while an alert only Blizzard's own viewer can play is configured and the
---master switch is on. `CDMDataSource.needsViewerChildren` reads it.
---@return boolean
function CDMAlerts.NeedsBlizzardViewer()
    return needsViewer
end

---Previous on-cooldown observation per button, weak-keyed so a released
---button frame doesn't pin an entry forever. `nil` means "no prior
---observation yet" — right after a fresh acquire/re-bind
---(`CDMAlerts.ReleaseButton` clears the entry) — which is what suppresses
---the edge-fire storm at login, on a spec change, and on every pooled-button
---re-bind. Deliberately NOT derived from `button.cue_onCooldown`: a full
---layout pass also calls `refreshButtonContent`, which would overwrite it
---and swallow the edge.
---@type table<Frame, boolean>
local prevOnCooldown = setmetatable({}, { __mode = "k" })

---Blizzard's alert lifetime: `durationSeconds` on `VisualAlertBaseTemplate`
---(`Blizzard_VisualAlerts/VisualAlertTemplates.xml:6`), enforced there by
---`VisualAlertBaseMixin:OnUpdate`.
local VISUAL_ALERT_SECONDS = 2

---Per button, the addon-owned cooldown Visual alert overlays, one per shape:
---`[button] = { ants = frame, flash = frame }`. Weak-keyed like `prevOnCooldown`.
---
---Never Blizzard's own alert frames. `CooldownViewerAlert_PlayAlert`'s visual
---player acquires from the ONE `VisualAlertsManager` pool Blizzard's viewers
---also use, and `VisualAlertMixin:GetAlertID` bumps a file-local
---`alertIDCounter` on every acquire. Called from addon code, every one of those
---writes is tainted; the next secure viewer that acquires an alert reads them,
---and its `UNIT_AURA` handler then dies indexing `auraInstanceIDToItemFramesMap`
---with a secret auraInstanceID (`CheckAuraAddedAlertTriggers`,
---CooldownViewer.lua:1864) -- live 2026-09-27. Same art as the aura-button path
---(`AuraContainer`'s `applyCdmAlertGlow`), built from `GlowEffect` primitives.
---@type table<Frame, table<string, Frame>>
local visualOverlays = setmetatable({}, { __mode = "k" })

---OnUpdate on an overlay while it plays: hide it once its lifetime runs out.
---@param overlay Frame
---@param elapsed number
local function tickVisualAlert(overlay, elapsed)
    overlay.cue_remaining = overlay.cue_remaining - elapsed
    if overlay.cue_remaining <= 0 then
        overlay:SetScript("OnUpdate", nil)
        overlay:Hide()
    end
end

---Play one cooldown Visual alert on an addon-owned icon: show the overlay for
---its shape, restart its animation, and run the lifetime from the top -- a
---re-trigger mid-play restarts it, as a fresh Blizzard acquire would.
---@param button Frame
---@param visualAlertType number  an Enum.VisualAlertType value (the alert's payload)
local function playVisualAlert(button, visualAlertType)
    local art = private.GlowEffect.GetCdmAlertArt(visualAlertType)
    if not art then return end
    local overlays = visualOverlays[button]
    if not overlays then
        overlays = {}
        visualOverlays[button] = overlays
    end
    local overlay = overlays[art.shape]
    if not overlay then
        overlay = private.GlowEffect.CreateCdmAlertGlow(button, art.shape)
        overlays[art.shape] = overlay
    end
    private.GlowEffect.AnchorCdmAlertGlow(overlay, button, button:GetWidth())
    private.GlowEffect.ApplyCdmAlertGlowColor(overlay, art.color)
    overlay.anim:Restart()
    overlay.cue_remaining = VISUAL_ALERT_SECONDS
    overlay:SetScript("OnUpdate", tickVisualAlert)
    overlay:Show()
end

---Pure edge decision: which alert event, if any, a state transition just
---fired. No frame or profile access, so `tests/alerttransition_check.lua`
---can drive it directly by extracting this function's source.
---@param prev boolean|nil  previous observation; nil = none yet
---@param current boolean  current on-cooldown state
---@return number|nil alertEvent  an Enum.CooldownViewerAlertEventType value, or nil when nothing fired
local function computeTransitionEvent(prev, current)
    if prev == nil or prev == current then return nil end
    if current then
        return Enum.CooldownViewerAlertEventType.OnCooldown
    end
    return Enum.CooldownViewerAlertEventType.Available
end

---The tracked spell's name for the text-to-speech alert, or nil. `key < 0` is a synthetic NEGATIVE key for a 12.1
---item-backed CDM entry (potions, trinkets — .context/api.md "spellID is
---nil for item entries") the player has moved into one of the four classic
---categories via Blizzard's own CDM category-transfer drag-and-drop (see
---`getTrackedCooldownIDs`'s doc comment, Core/CDMDataSource.lua) — a real,
---reachable key shape here, not a hypothetical one. It is not a real
---spellID and would just read back nil from C_Spell.GetSpellInfo anyway;
---guarded here rather than relied on, since a negative number is still a
---legal (if meaningless) argument. The practical effect on such an entry's
---alert is that the TTS phrase is silently skipped (`speakAlert` requires a
---truthy spellName, as Blizzard's `CooldownViewerAlert_PlayTTSAlert` does)
---while its Sound/Visual alerts, which don't need a name, still play normally.
---@param key number
---@return string|nil
local function resolveSpellName(key)
    if key < 0 then return nil end
    local info = C_Spell.GetSpellInfo(key)
    return info and info.name
end

---Speak a text-to-speech alert: the spell name, in the player's Standard TTS
---voice at their rate and volume, never queued, overlap allowed -- what
---Blizzard's `CooldownViewerAlert_PlayTTSAlert` does (its formatter is a bare
---`"%s"` for every event). Straight to `C_VoiceChat.SpeakText`, never through
---`TextToSpeech_Speak`: that writes `TextToSpeechFrame.lua`'s file-locals
---(`playbackActive`, `queuedMessages`), which Blizzard's own CDM TTS alert then
---reads tainted. The voice pick mirrors `TextToSpeech_GetSelectedVoice`
---(voice 1 when the saved one is gone).
---@param spellName string|nil
local function speakAlert(spellName)
    if not spellName then return end
    local voices = C_VoiceChat.GetTtsVoices()
    local voiceID = C_TTSSettings.GetVoiceOptionID(Enum.TtsVoiceType.Standard)
    local voice
    for i = 1, #voices do
        if voices[i].voiceID == voiceID then
            voice = voices[i]
            break
        end
    end
    voice = voice or voices[1]
    if not voice then return end
    C_VoiceChat.SpeakText(voice.voiceID, spellName, C_TTSSettings.GetSpeechRate(),
        C_TTSSettings.GetSpeechVolume(), true)
end

---Play one Sound or text-to-speech alert with our own calls only -- the
---audible half of Blizzard's `CooldownViewerAlert_PlayAlert`, which is never
---called: every Blizzard helper behind it writes state their own viewers read.
---@param alert table  a CDM alert from the layout manager
---@param spellName string|nil
local function playAudibleAlert(alert, spellName)
    if CooldownViewerAlert_GetPayload(alert) == Enum.CooldownViewerSound.TextToSpeech then
        speakAlert(spellName)
        return
    end
    local soundKit = soundKitForAlert(alert)
    if soundKit then
        private.compat.PlaySoundKit(soundKit)
    end
end

---Called once per active button per rendered frame from IconTracker's swipe
---pass (`onSwipeUpdate`). Cheap on the no-transition path: one table read
---and one compare, no allocation, no API call (.context/performance.md).
---@param key number  the tracker key: base spellID, or the synthetic negative key for an item-backed entry — same key `alertsByKey`/`entryCategory` use
---@param onCooldown boolean  `button.cue_onCooldown`, published by IconTracker's `refreshButtonContent`
---@param button Frame  the pooled icon button; also the Visual alert overlay's parent
function CDMAlerts.OnCooldownStateChanged(key, onCooldown, button)
    local prev = prevOnCooldown[button]
    if prev == onCooldown then return end
    prevOnCooldown[button] = onCooldown

    local alertEvent = computeTransitionEvent(prev, onCooldown)
    if not alertEvent then return end

    if not CDMAlerts.IsEnabled() then return end

    local byEvent = alertsByKey[key]
    local alerts = byEvent and byEvent[alertEvent]
    if not alerts then return end

    -- A shown owning viewer means Blizzard's engine is already playing this
    -- key's alerts. Only the audible ones would double up: a Visual lands on
    -- OUR icon, and behind a CUE-suppressed viewer theirs draws at alpha 0.
    -- A CUE entry never stands down: Blizzard plays the Cooldown Manager's
    -- list, not this one.
    local categoryId = entryCategory[key]
    local blizzardOwns = not cueKeys[key] and categoryId ~= nil and blizzardOwnsAlerts(categoryId)

    local spellName = resolveSpellName(key)
    for i = 1, #alerts do
        local alert = alerts[i]
        local alertType = CooldownViewerAlert_GetType(alert)
        if alertType == Enum.CooldownViewerAlertType.Visual then
            playVisualAlert(button, CooldownViewerAlert_GetPayload(alert))
        elseif alertType == Enum.CooldownViewerAlertType.Sound and not blizzardOwns then
            playAudibleAlert(alert, spellName)
        end
    end
end

---The same edge as `OnCooldownStateChanged`, addressed by equip slot.
---
---`Components/TrinketTracker.lua` draws the equipped trinkets straight from the
---inventory slot, so it holds no cooldownID and no tracker key -- and its icons
---are the ones on screen whenever the player has not dragged the trinket into
---Essential/Utility, which is the default arrangement. Without this the alert a
---player configured on that trinket had nowhere to play.
---
---A slot with no alert-carrying entry returns before touching `prevOnCooldown`,
---so the first edge after one appears is swallowed exactly like a fresh bind --
---the same suppression `OnCooldownStateChanged`'s nil sentinel provides.
---@param equipSlot number  13 or 14
---@param onCooldown boolean
---@param button Frame  the trinket icon; also the Visual alert overlay's parent
function CDMAlerts.OnEquipSlotCooldownChanged(equipSlot, onCooldown, button)
    local key = equipSlotKey[equipSlot]
    if not key then return end
    CDMAlerts.OnCooldownStateChanged(key, onCooldown, button)
end

---The visual alert a tracked buff's `OnAuraApplied` Visual alert asks for.
---
---This is the one aura-event alert an addon can honour under the 12.1 lockdown,
---and it works by sidestepping the missing trigger rather than recovering it.
---There is no callback when an aura is applied — `UNIT_AURA` payloads are
---secret, the aura button's shown state is secret and dispatches no script, and
---`AddAuraSound` is the engine playing with no return path. But the engine shows
---that button for exactly as long as the aura lasts, so an overlay built in its
---subtree is switched on and off by the aura at no cost
---(`.context/patterns-auracontainer.md`, "an engine-shown button IS a boolean
---Lua cannot read"). Every visual payload loops in Blizzard's own XML, so the
---result is their animation running for the aura's lifetime rather than for
---their 2 s release timer.
---
---Resolved through `GetIdentityOwner` for the same reason `applyAuraRegistrations`
---is: an aura tracker's map comes from `getTrackedSpellMap(..., includeLinked)`,
---so a cell can be keyed by a LINKED id while the index here is filed under the
---entry's base spellID.
---@param spellID number  a key from the tracker's spell map; base or linked
---@return number|nil visualAlertType  an Enum.VisualAlertType value
function CDMAlerts.GetAuraVisualAlert(spellID)
    -- Cheapest possible answer first, and deliberately BEFORE the identity walk:
    -- almost nobody configures one of these, and `GetIdentityOwner` reaches
    -- `ensureResolved`, which can BUILD the CDM model from whatever called it
    -- (.context/patterns.md "Lazy caches vs init order"). Nothing should be able
    -- to trigger that from a per-slot loop that is going to answer nil anyway.
    if next(auraVisualBySpellID) == nil then return nil end
    if not CDMAlerts.IsEnabled() then return nil end
    -- No blizzardOwnsAlerts gate: the glow is on OUR icon, so it cannot double
    -- Blizzard's, and behind a CUE-suppressed viewer theirs draws at alpha 0.
    local visualType = auraVisualBySpellID[spellID]
    if visualType == nil then
        local ownerID = private.CDMDataSource.GetIdentityOwner(spellID)
        visualType = ownerID and auraVisualBySpellID[ownerID] or nil
    end
    return visualType
end

---Called when IconTracker returns a pooled button to the pool. Clears the
---edge-detection state and releases any visual alerts still running on the
---button, so a button re-bound to a different spell doesn't inherit a
---running animation or a stale cooldown edge (.context/patterns.md "Reset
---ALL properties when releasing pooled objects").
---@param button Frame
function CDMAlerts.ReleaseButton(button)
    prevOnCooldown[button] = nil
    local overlays = visualOverlays[button]
    if overlays then
        for _, overlay in pairs(overlays) do
            overlay:SetScript("OnUpdate", nil)
            overlay:Hide()
        end
    end
end

-- The Tracking tab's Alerts menu --------------------------------------------

---CUE's own entry for a tracker key, and the Cooldown Manager's list for it.
---@param key number
---@return table[]|nil own  a filtered copy of `spell_alerts[key]`; nil when the key follows the Cooldown Manager
---@return table[]|nil cdm  Blizzard's records at the last rebuild: read, never mutate
function CDMAlerts.GetSpellAlerts(key)
    local list = private.profile.spell_alerts[key]
    local own
    if type(list) == "table" then
        own = {}
        for i = 1, #list do
            if isAlertRecord(list[i]) then own[#own + 1] = list[i] end
        end
    end
    return own, cdmAlertsByKey[key]
end

---Which kinds of alert play for a key, for the Tracking tab's markers (the
---icons Blizzard's settings window shows on an item with alerts): CUE's entry
---or else the Cooldown Manager's list, plus the Cooldown Manager's alerts only
---Blizzard can play, which play under an entry too.
---@param key number
---@return boolean hasSound, boolean hasVisual
function CDMAlerts.GetSpellAlertTypes(key)
    local own, cdm = CDMAlerts.GetSpellAlerts(key)
    local hasSound, hasVisual = false, false
    local function add(alert)
        if CooldownViewerAlert_GetType(alert) == Enum.CooldownViewerAlertType.Visual then
            hasVisual = true
        else
            hasSound = true
        end
    end
    for i = 1, own and #own or 0 do add(own[i]) end
    for i = 1, cdm and #cdm or 0 do
        local a = cdm[i]
        if not own or not CDMAlerts.CanPlay(CooldownViewerAlert_GetType(a),
            CooldownViewerAlert_GetEvent(a), CooldownViewerAlert_GetPayload(a)) then
            add(a)
        end
    end
    return hasSound, hasVisual
end

---Write CUE's own entry for a key; nil goes back to the Cooldown Manager's
---list. The rebuild's signature sees an aura sound change through
---`alertsBySpellID`; the cooldown side is read at fire time.
---@param key number
---@param alerts table[]|nil  `{ type, event, payload }` records
function CDMAlerts.SetSpellAlerts(key, alerts)
    private.profile.spell_alerts[key] = alerts
    CDMAlerts.Rebuild()
end

---Can CUE play this combination itself? The coverage table in
---Core/CDMAlerts.md: cooldown events take everything; an aura gained takes a
---sound or a visual; an aura lost takes a sound. Text-to-speech needs a
---moment to speak at, which an aura event never gives.
---@param alertType number  Enum.CooldownViewerAlertType
---@param alertEvent number  Enum.CooldownViewerAlertEventType
---@param payload number  Enum.CooldownViewerSound or Enum.VisualAlertType
---@return boolean
function CDMAlerts.CanPlay(alertType, alertEvent, payload)
    local events = Enum.CooldownViewerAlertEventType
    local cooldown = alertEvent == events.Available or alertEvent == events.OnCooldown
    if alertType == Enum.CooldownViewerAlertType.Visual then
        return cooldown or alertEvent == events.OnAuraApplied
    end
    if alertType ~= Enum.CooldownViewerAlertType.Sound then return false end
    if payload == Enum.CooldownViewerSound.TextToSpeech then return cooldown end
    return cooldown or alertEvent == events.OnAuraApplied or alertEvent == events.OnAuraRemoved
end

---Does Blizzard's viewer play the Cooldown Manager's alerts for this key right
---now? Then a CUE entry plays next to them, and only the Cooldown Manager's
---own settings can stop theirs.
---@param key number
---@return boolean
function CDMAlerts.BlizzardPlaysToo(key)
    local categoryId = entryCategory[key]
    return categoryId ~= nil and blizzardOwnsAlerts(categoryId)
end

---Play one alert once, through the same players the replay uses.
---@param alert table
---@param key number  tracker key, for the text-to-speech name
---@param frame Frame  an addon-owned icon a Visual plays on
function CDMAlerts.PlaySample(alert, key, frame)
    if CooldownViewerAlert_GetType(alert) == Enum.CooldownViewerAlertType.Visual then
        playVisualAlert(frame, CooldownViewerAlert_GetPayload(alert))
    else
        playAudibleAlert(alert, resolveSpellName(key))
    end
end

---The sound's or visual's name, read from Blizzard's data tables rather than
---their label functions, which build file-local caches on first call.
---@param alert table
---@return string
function CDMAlerts.GetPayloadText(alert)
    local payload = CooldownViewerAlert_GetPayload(alert)
    if CooldownViewerAlert_GetType(alert) == Enum.CooldownViewerAlertType.Visual then
        local text
        VisualAlertData_ForEach(function(data)
            if data.enum == payload then text = data.text end
        end)
        return text or tostring(payload)
    end
    if payload == Enum.CooldownViewerSound.TextToSpeech then
        return COOLDOWN_VIEWER_SETTINGS_ALERT_LABEL_SOUND_TYPE_TEXT_TO_SPEECH
    end
    return ensureSoundData() and soundTextByPayload[payload] or tostring(payload)
end

---Register the rebuild signals and run the first pass.
function CDMAlerts.Initialize()
    if initialized then return end
    initialized = true
    if not private.compat.HasCooldownManager() then return end

    private.Callback.Register("OnCDMSpellsChanged", CDMAlerts.Rebuild)
    -- Forced: a profile switch can move the enable flag without touching one
    -- byte of the CDM-derived model, so the signature would skip the tail
    -- that re-registers.
    private.Callback.Register("OnProfileChanged", CDMAlerts.RebuildRegistrations)
    -- Forced too: a by-name aura's ids widen its aura-sound registration, and
    -- the signature sees neither the name nor its ids.
    private.Callback.Register("OnSpellNamesResolved", CDMAlerts.RebuildRegistrations)
    -- No spec-change handler of its own: the spec events reach this module as
    -- OnCDMSpellsChanged above, and a spec change moves nothing the signature
    -- cannot see now that registrations no longer follow the trackers' spell
    -- maps.

    -- Flush whatever the settings frame swallowed. Blizzard fires this itself
    -- (`CooldownViewerSettingsMixin:OnHide`), so nothing here hooks or writes to
    -- a CooldownViewer frame. It fires AFTER that handler's
    -- `CheckSaveCurrentLayout`, so a save-on-close lands in the deferral and is
    -- picked up by this same flush rather than needing a second one.
    EventRegistry:RegisterCallback("CooldownViewerSettings.OnHide", function()
        if deferredRebuild then CDMAlerts.Rebuild() end
    end, CDMAlerts)

    -- Fast path for the aura-registration viewer hooks; all four viewer
    -- globals already exist at this point (see installAllAuraViewerHooks),
    -- so performRebuild's later call is a cheap idempotent re-assert, not a
    -- recovery for one missing here.
    installAllAuraViewerHooks()

    -- Settles whether an AddAuraSound registration survives a /reload: it
    -- does not need to, because every id is removed here by construction.
    local logoutEventFrame = CreateFrame("Frame")
    logoutEventFrame:RegisterEvent("PLAYER_LOGOUT")
    logoutEventFrame:SetScript("OnEvent", removeAllAuraSounds)

    -- Not through Rebuild: the first pass should not wait out the debounce,
    -- because anything reading the model before it lands sees an empty one.
    -- The login burst that follows is debounced normally.
    C_Timer.After(0, runRebuild)
end
